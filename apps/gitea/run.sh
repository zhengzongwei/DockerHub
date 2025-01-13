#!/bin/bash

# 从 .env 文件中读取变量
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
else
    echo ".env file not found!"
    exit 1
fi

# 显示脚本的使用方法
usage() {
    echo "Usage: $0 {build|compose}"
    echo "Commands:"
    echo "  build         Build the Docker image using gitea.dockerfile"
    echo "  compose       Run Docker Compose tasks using gitea.yaml"
}

# 解析命令行参数
COMMAND=$1

# 检查命令是否有效
if [[ "$COMMAND" != "build" && "$COMMAND" != "compose" ]]; then
    usage
    exit 1
fi

# 创建 Gitea 数据目录
mkdir -p $GITEA_PATH

# 执行不同的任务
case $COMMAND in
    build)
        echo "Building Docker image with Gitea version ${GITEA_VERSION} using gitea.dockerfile..."
        docker build --build-arg GITEA_VERSION=${GITEA_VERSION} -t gitea-custom:${GITEA_VERSION} -f gitea.dockerfile .
        ;;
    compose)
        echo "Running Docker Compose with Gitea version ${GITEA_VERSION} using gitea.yaml..."
        export GITEA_VERSION=${GITEA_VERSION}
        export GITEA_PATH=${GITEA_PATH}
        export GITEA_PORT=${GITEA_PORT}
        export GITEA_SSH_PORT=${GITEA_SSH_PORT}
        docker-compose -f gitea.yaml up -d --build
        ;;
esac