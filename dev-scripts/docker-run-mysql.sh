#!/bin/sh

# Run `postgres` container named `postgres` in docker network `localnet`
# Create a network, if not exists: `docker network create localnet`
docker run --name mariadb -d -p 3306:3306 --network localnet \
  -e MYSQL_ROOT_PASSWORD=root \
   mariadb:10.3

# Login to pg cli
PGPASSWORD=erpnextpassword psql -h 127.0.0.1 -p 5432 -U erpnextuser -d erpnext

# Recreate database quickly.
drop database erpnext;
create database erpnext with encoding 'utf-8' owner postgres;
