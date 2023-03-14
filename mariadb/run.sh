#!/bin/bash

MARIADB_PATH=$HOME/mariadb/data

sed -i '/^MARIADB_PATH/d' .env

echo "MARIADB_PATH=$MARIADB_PATH" >> .env

mkdir -p $MARIADB_PATH

docker-compose -f mariadb.yaml up -d
