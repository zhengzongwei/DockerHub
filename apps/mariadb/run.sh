#!/bin/bash

MARIADB_PATH=/data/mariadb/data

sed -i '/^MARIADB_PATH/d' .env

echo "MARIADB_PATH=$MARIADB_PATH" >> .env

mkdir -p $MARIADB_PATH/conf.d/

docker-compose -f mariadb.yaml up -d
