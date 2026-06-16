FROM codeberg.org/forgejo/forgejo:15 AS repo

COPY server/entrypoint.sh /entrypoint.sh
