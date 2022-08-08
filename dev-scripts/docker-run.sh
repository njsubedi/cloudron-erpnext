#!/bin/sh
# Uncomment for Fresh Run
docker rm -f erpnext_custom

# Build with detailed output
BUILDKIT_PROGRESS=plain docker build --platform linux/amd64 -t erpnext_custom .

# Run in an environment similar to Cloudron.
# Must access using nginx or similar reverse proxy.
BUILDKIT_PROGRESS=plain docker build --platform linux/amd64 -t erpnext_custom . &&
  docker run --platform linux/amd64 --read-only \
    -v "$(pwd)"/.docker/app/data:/app/data:rw \
    -v "$(pwd)"/.docker/tmp:/tmp:rw \
    -v "$(pwd)"/.docker/run:/run:rw \
    -p 8000:80 \
    -p 9000:9000 \
    --network localnet \
    -e CLOUDRON_MYSQL_USERNAME=erpnext \
    -e CLOUDRON_MYSQL_PASSWORD=erpnext \
    -e CLOUDRON_MYSQL_HOST=host.docker.internal \
    -e CLOUDRON_MYSQL_PORT=3306 \
    -e CLOUDRON_MYSQL_DATABASE=erpnext_site1 \
    erpnext_custom

BUILDKIT_PROGRESS=plain docker build --platform linux/amd64 -t erpnext_custom . &&
  docker run --platform linux/amd64 --read-only \
    -v "$(pwd)"/.docker/app/data:/app/data:rw \
    -v "$(pwd)"/.docker/tmp:/tmp:rw \
    -v "$(pwd)"/.docker/run:/run:rw \
    -p 8000:80 \
    -p 9000:9000 \
    erpnext_custom
