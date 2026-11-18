FROM codeberg.org/forgejo/forgejo:17 AS repo

COPY server/entrypoint.sh /entrypoint.sh
