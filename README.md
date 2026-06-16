### Forgejo docker compose instance

This is the forgejo instance, its database and runner, with admin credentials as environment vars

## Containers

1. Mariadb - database backend
2. Forgejo - the git frontend with only the web port exposed
3. runner - a container to manage forgejo acitons
4. docker-in-docker - container environment for action execution 
