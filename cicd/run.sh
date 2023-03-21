#!/bin/bash

CICD_PATH=$HOME/cicd/
GITEA_PATH = $CICD_PATH/gitea/data
DRONE_PATH = $CICD_PATH/drone/data

sed -i '/^GITEA_PATH/d' .env
echo "GITEA_PATH=$GITEA_PATH" >> .env

sed -i '/^DRONE_PATH/d' .env
echo "DRONE_PATH=$DRONE_PATH" >> .env

mkdir -p $GITEA_PATH
mkdir -p $DRONE_PATH

docker-compose -f cicd.yaml up -d