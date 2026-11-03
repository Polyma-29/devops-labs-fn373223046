## Start locally / Локално стартиране

```bash
docker build -t notes-api:0.3.0 .
docker run -d --name notes-api -p 8000:8000 notes-api:0.3.0