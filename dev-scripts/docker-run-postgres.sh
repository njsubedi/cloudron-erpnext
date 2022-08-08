#!/bin/sh

# Run `postgres` container named `postgres` in docker network `localnet`
# Create a network, if not exists: `docker network create localnet`

docker run --name postgres -d -p 5432:5432 --network localnet \
	-e POSTGRES_USER=erpnextuser \
	-e POSTGRES_PASSWORD=erpnextpassword \
	-e POSTGRES_DB=erpnext \
	postgres:latest


# Login to pg cli
PGPASSWORD=erpnextpassword psql -h postgres -p 5432 -U erpnextuser -d erpnext

# Recreate database quickly.
drop database erpnext;
create database erpnext with encoding 'utf-8' owner postgres;
