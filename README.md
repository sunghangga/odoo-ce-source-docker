## Docker Build and Push to Docker Hub
```
docker buildx build --no-cache --platform linux/amd64 -t hospits/odoo:18-source --push --network=host .
```