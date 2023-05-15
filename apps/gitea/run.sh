#!/bin/bash

GITEA_PATH=$HOME/gitea/data

sed -i '/^GITEA_PATH/d' .env

echo "GITEA_PATH=$GITEA_PATH" >> .env

mkdir -p $GITEA_PATH

docker-compose -f gitea.yaml up -d