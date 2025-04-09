#!/bin/bash

# ==========================================
# 容器镜像构建与部署工具 v2.1
# ==========================================

########################  基础配置  ########################
# 颜色定义
readonly COLOR_RESET='\033[0m'
readonly COLOR_RED='\033[31m'
readonly COLOR_GREEN='\033[32m'
readonly COLOR_YELLOW='\033[33m'
readonly COLOR_BLUE='\033[36m'

# 默认文件
readonly DEFAULT_ENV_FILE=".env"
readonly DEFAULT_COMPOSE_FILE="docker-compose.yml"

########################  日志函数  ########################
log() { printf '%b\n' "$1" >&2; }
info() { log "${COLOR_RESET}[*] $1${COLOR_RESET}"; }
warn() { log "${COLOR_YELLOW}[!] $1${COLOR_RESET}"; }
success() { log "${COLOR_GREEN}[✔] $1${COLOR_RESET}"; }
error() { log "${COLOR_RED}[✘] $1${COLOR_RESET}"; exit 1; }

########################  核心功能  ########################
# 加载统一环境变量
load_env(){
    local env_file="${1:-$DEFAULT_ENV_FILE}"
    if [[ -f "$env_file" ]]; then
        info "加载环境变量: $env_file"
        export $(grep -v '^#' .env | xargs)
    else
        warn ".env file not found!"
        exit 1
    fi
}

# 构建镜像
build() {
    local tag="${1:-${APP_NAME:-gitea-custom}:${APP_VERSION:-${GITEA_VERSION}}}"
    info "构建镜像: GITEA:$GITEA_VERSION"
    docker build --build-arg GITEA_VERSION=${GITEA_VERSION} \
        -t gitea-custom:${GITEA_VERSION} \
        -f gitea.dockerfile . && {
        success "镜像构建成功"
        docker images | grep "${tag%:*}" | grep "${tag#*:}"
    } || error "镜像构建失败"
}
# 部署服务
# compose(){
#     export GITEA_VERSION=${GITEA_VERSION:-1.23.7}
#     export GITEA_PATH=${GITEA_PATH:-$HOME/gitea/data}
#     export GITEA_PORT=${GITEA_PORT:-3000}
#     export GITEA_SSH_PORT=${GITEA_SSH_PORT:-2222}
#     local compose_file="${1:-$DEFAULT_COMPOSE_FILE}"
#     [[ -f "$compose_file" ]] || error "Compose文件不存在: $compose_file"
#     info "启动服务..."
#     docker-compose -f "$compose_file" up -d && {
#         success "服务启动成功"
#         docker-compose -f "$compose_file" ps
#     } || error "服务启动失败"

# }
compose() {
    # 加载环境配置（支持.env文件和默认值）
    local env_file="${PWD}/.env"
    [ -f "${env_file}" ] && source "${env_file}"
    
    # 设置带默认值的环境变量
    export GITEA_VERSION="${GITEA_VERSION:-1.23.7}"
    export GITEA_PATH="${GITEA_PATH:-${HOME}/gitea/data}"
    export GITEA_PORT="${GITEA_PORT:-3000}"
    export GITEA_SSH_PORT="${GITEA_SSH_PORT:-2222}"

    # 检查必要目录
    mkdir -p "${GITEA_PATH}" || {
        error "无法创建数据目录: ${GITEA_PATH}"
        return 1
    }

    # 处理compose文件路径
    local compose_file="${1:-${DEFAULT_COMPOSE_FILE:-docker-compose.yml}}"
    [ -f "${compose_file}" ] || {
        error "Compose文件不存在: ${compose_file}"
        return 1
    }

    # 启动服务
    info "启动服务 (GITEA_VERSION=${GITEA_VERSION})..."
    if docker compose -f "${compose_file}" up -d; then
        success "服务启动成功"
        printf "\n容器状态:\n"
        docker compose -f "${compose_file}" ps
        printf "\n访问地址: http://localhost:${GITEA_PORT}\n"
    else
        error "服务启动失败"
        docker compose -f "${compose_file}" logs
        return 1
    fi
}

# 清理资源
clean() {
  info "清理未使用资源..."
  docker system prune -f
  success "资源清理完成"
}

########################  主流程  ########################

# 显示脚本的使用方法
usage() {
    echo "Usage: $0 {build|compose|clean}"
    echo "Commands:"
    echo "  build         Build the Docker image using gitea.dockerfile"
    echo "  compose       Run Docker Compose tasks using gitea.yaml"
    echo "  clean         Clean up Docker containers and images"
    echo "  help          Show this help message"
}

main(){
    local env_file="$DEFAULT_ENV_FILE"
    # 处理命令参数
    [[ $# -gt 0 ]] && command="$1"
    # 加载环境变量
    load_env "$env_file"

    # 解析参数
    while getopts ":he:f:t:" opt; do
        case $opt in
            h) usage; exit 0 ;;
            # e) env_file="$OPTARG" ;;
            # f) compose_file="$OPTARG" ;;
            # t) image_tag="$OPTARG" ;;
            \?) error "无效选项: -$OPTARG" ;;
            :) error "选项 -$OPTARG 需要参数" ;;
        esac
  done

    # 执行命令
    case "$command" in
        build)
        build
        ;;
        compose)
        compose
        ;;
        clean)
        clean
        ;;
        *)
        error "未知命令: $command"
        ;;
    esac

}

# 严格模式并启动
set -euo pipefail
main "$@"