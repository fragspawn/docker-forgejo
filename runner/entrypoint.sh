#!/bin/sh
set -e

FORGEJO_INSTANCE_URL="${FORGEJO_INSTANCE_URL:-http://server:3000}"
FORGEJO_ADMIN_USER="${FORGEJO_ADMIN_USER:-admin}"
FORGEJO_ADMIN_PASSWORD="${FORGEJO_ADMIN_PASSWORD:-changeme-admin}"
RUNNER_NAME="${RUNNER_NAME:-forgejo-runner}"
RUNNER_LABELS="${RUNNER_LABELS:-ubuntu-latest:docker://node:20-bookworm}"
CONFIG_FILE="/data/runner-config.yml"
REGISTERED_FLAG="/data/.runner-registered"

# ---------------------------------------------------------------------------
# Wait for Forgejo to be reachable
# ---------------------------------------------------------------------------
echo "[entrypoint] Waiting for Forgejo at ${FORGEJO_INSTANCE_URL} ..."
until wget -qO- "${FORGEJO_INSTANCE_URL}/api/swagger" >/dev/null 2>&1; do
  sleep 5
done
echo "[entrypoint] Forgejo is reachable."

# ---------------------------------------------------------------------------
# Write runner config if not already present
# ---------------------------------------------------------------------------
if [ ! -f "${CONFIG_FILE}" ]; then
  echo "[entrypoint] Writing runner config to ${CONFIG_FILE} ..."
  cat > "${CONFIG_FILE}" <<EOF
log:
  level: info
  job_level: info

runner:
  file: /data/.runner
  capacity: 1
  envs: {}
  env_file: ""
  timeout: 3h
  shutdown_timeout: 3h
  insecure: false
  fetch_timeout: 30s
  fetch_interval: 2s
  report_interval: 1s
  labels: []

cache:
  enabled: true
  port: 0
  dir: ""

container:
  network: ""
  enable_ipv6: false
  privileged: false
  options:
  workdir_parent:
  valid_volumes:
    - "**"
  docker_host: tcp://docker-in-docker:2375
  force_pull: false
  force_rebuild: false

host:
  workdir_parent:

server:
  connections: {}
EOF
fi

# ---------------------------------------------------------------------------
# Register runner (once) by fetching an admin registration token from API
# ---------------------------------------------------------------------------
if [ ! -f "${REGISTERED_FLAG}" ]; then
  echo "[entrypoint] Attempting to obtain runner registration token ..."

  RETRY=0
  TOKEN=""
  BASIC_AUTH="$(printf '%s:%s' "${FORGEJO_ADMIN_USER}" "${FORGEJO_ADMIN_PASSWORD}" | base64 | tr -d '\n')"
  while [ -z "${TOKEN}" ]; do
    RETRY=$((RETRY + 1))
    RESPONSE=$(wget -qO- \
      --header="Content-Type: application/json" \
      --header="Authorization: Basic ${BASIC_AUTH}" \
      "${FORGEJO_INSTANCE_URL}/api/v1/admin/runners/registration-token" 2>/dev/null || true)

    TOKEN=$(echo "${RESPONSE}" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)

    if [ -z "${TOKEN}" ]; then
      echo "[entrypoint] Could not get token (attempt ${RETRY}). Is the admin user created?"
      echo "[entrypoint]   -> Run: docker exec forgejo forgejo admin user create --admin --username ${FORGEJO_ADMIN_USER} --password ${FORGEJO_ADMIN_PASSWORD} --email admin@localhost"
      echo "[entrypoint] Retrying in 30s ..."
      sleep 30
    fi
  done

  echo "[entrypoint] Registration token obtained. Registering runner ..."
  forgejo-runner register \
    --no-interactive \
    --instance "${FORGEJO_INSTANCE_URL}" \
    --token "${TOKEN}" \
    --name "${RUNNER_NAME}" \
    --labels "${RUNNER_LABELS}" \
    --config "${CONFIG_FILE}"

  touch "${REGISTERED_FLAG}"
  echo "[entrypoint] Runner registered successfully."
fi

# ---------------------------------------------------------------------------
# Start the runner daemon
# ---------------------------------------------------------------------------
echo "[entrypoint] Starting forgejo-runner daemon ..."
exec forgejo-runner daemon --config "${CONFIG_FILE}"
