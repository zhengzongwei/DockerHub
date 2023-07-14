#!/bin/bash

msg() {
  printf '%b\n' "$1" >&2
}

tips() {
  msg "\33[36m[*]\33[0m ${1}${2}"
}

success() {
  msg "\33[32m[✔]\33[0m ${1}${2}"
}

error() {
  msg "\33[31m[✘]\33[0m ${1}${2}"
  exit 1
}

CICD_PATH=/opt/cicd/
GITEA_PATH=$CICD_PATH/gitea/data
DRONE_PATH=$CICD_PATH/drone/data

function check_dir(){
    if [ ! -d $1 ];then
        sudo mkdir -p $1
    else
        msg "$1 文件夹已存在"
    fi
}

function create_dir(){

    check_dir $GITEA_PATH $DRONE_PATH
    sudo chown -R $USER:$USER $CICD_PATH
    success "文件夹创建完成"
    msg "根目录：CICD_PATH"
}

function parse_env(){
    sed -i -e s:GITEA_PATH=.*:GITEA_PATH=${GITEA_PATH}:g .env

    sed -i -e s:DRONE_PATH=.*:DRONE_PATH=${DRONE_PATH}:g .env

}


function run(){
    docker-compose -f cicd.yaml up -d
}
function main(){
    tips "基础环境准备"
    create_dir

    tips "配置env文件"
    parse_env

    run

}


main


