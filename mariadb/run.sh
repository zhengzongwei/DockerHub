#!/bin/bash

mkdir -p $HOME/mariadb/data

docker-compose -f mariadb.yaml up -d 
