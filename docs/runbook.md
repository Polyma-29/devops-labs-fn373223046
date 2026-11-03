## Start locally / Локално стартиране

```bash
docker build -t notes-api:0.3.0 .
docker run -d --name notes-api -p 8000:8000 notes-api:0.3.0

## Run with Compose

To run the full stack (application and database) using Docker Compose:

### Commands
- **Start services in background:**
  ```bash
  docker compose up -d

Check service status:
  docker compose ps

View container logs:
 docker compose logs -f

Stop and remove containers:
 docker compose down


Difference between down and down -v
 docker compose down: Stops and removes the containers and networks, but preserves the persistent data volumes (your database notes remain saved).

 docker compose down -v: Stops and removes containers, networks, AND deletes the volumes. This permanently deletes all stored database data.