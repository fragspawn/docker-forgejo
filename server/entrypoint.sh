#!/bin/sh
set -eu

DEFAULT_ENTRYPOINT="/usr/bin/entrypoint"
DEFAULT_CMD_BIN="/usr/bin/s6-svscan"
DEFAULT_CMD_ARG="/etc/s6"

FORGEJO_HEALTH_URL="${FORGEJO_HEALTH_URL:-http://127.0.0.1:3000/}"
FORGEJO_ADMIN_USER="${FORGEJO_ADMIN_USER:-forgeadmin}"
FORGEJO_ADMIN_PASSWORD="${FORGEJO_ADMIN_PASSWORD:-}"
FORGEJO_ADMIN_EMAIL="${FORGEJO_ADMIN_EMAIL:-admin@localhost}"

# Start the stock Forgejo entrypoint in the background.
"${DEFAULT_ENTRYPOINT}" "${DEFAULT_CMD_BIN}" "${DEFAULT_CMD_ARG}" &
MAIN_PID=$!

wait_for_forgejo() {
  echo "[server-entrypoint] Waiting for Forgejo to become reachable at ${FORGEJO_HEALTH_URL} ..."
  while kill -0 "${MAIN_PID}" >/dev/null 2>&1; do
    if wget -qO- "${FORGEJO_HEALTH_URL}" >/dev/null 2>&1; then
      echo "[server-entrypoint] Forgejo is reachable."
      return 0
    fi
    sleep 3
  done

  echo "[server-entrypoint] Forgejo process exited before becoming reachable."
  return 1
}

ensure_admin_user() {
  if [ -z "${FORGEJO_ADMIN_USER}" ] || [ -z "${FORGEJO_ADMIN_PASSWORD}" ]; then
    echo "[server-entrypoint] FORGEJO_ADMIN_USER/FORGEJO_ADMIN_PASSWORD not set; skipping admin bootstrap."
    return 0
  fi

  echo "[server-entrypoint] Ensuring admin user '${FORGEJO_ADMIN_USER}' exists ..."

  RETRY=0
  while kill -0 "${MAIN_PID}" >/dev/null 2>&1; do
    RETRY=$((RETRY + 1))

    set +e
    CREATE_OUTPUT="$(su-exec git:git forgejo admin user create \
      --admin \
      --username "${FORGEJO_ADMIN_USER}" \
      --password "${FORGEJO_ADMIN_PASSWORD}" \
      --email "${FORGEJO_ADMIN_EMAIL}" \
      --config /data/gitea/conf/app.ini 2>&1)"
    CREATE_EXIT_CODE=$?
    set -e

    if [ "${CREATE_EXIT_CODE}" -eq 0 ]; then
      echo "[server-entrypoint] Admin user created."
      return 0
    fi

    if echo "${CREATE_OUTPUT}" | grep -Eqi "already exists|already been taken|is already in use"; then
      echo "[server-entrypoint] Admin user already exists."
      return 0
    fi

    if echo "${CREATE_OUTPUT}" | grep -Eqi "name is reserved|reserved"; then
      echo "[server-entrypoint] Admin bootstrap failed: username '${FORGEJO_ADMIN_USER}' is reserved."
      echo "[server-entrypoint] Set FORGEJO_ADMIN_USER to a non-reserved name (for example: forgeadmin)."
      return 1
    fi

    echo "[server-entrypoint] Admin bootstrap attempt ${RETRY} failed; retrying in 5s ..."
    sleep 5
  done

  echo "[server-entrypoint] Forgejo process exited before admin bootstrap completed."
  return 1
}

wait_for_forgejo
ensure_admin_user

# Keep container lifecycle tied to the main Forgejo process.
wait "${MAIN_PID}"
