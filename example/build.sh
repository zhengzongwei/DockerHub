#!/usr/bin/env bash

# ==========================================
# 容器镜像构建与部署工具 v2.1
# 功能：统一使用 .env 的构建部署方案
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
info() { log "${COLOR_RESET}[ ] $1${COLOR_RESET}"; }
warn() { log "${COLOR_YELLOW}[!] $1${COLOR_RESET}"; }
success() { log "${COLOR_GREEN}[✔] $1${COLOR_RESET}"; }
error() { log "${COLOR_RED}[✘] $1${COLOR_RESET}"; exit 1; }

########################  核心功能  ########################
# 加载统一环境变量
load_env() {
  local env_file="${1:-$DEFAULT_ENV_FILE}"
  
  if [[ -f "$env_file" ]]; then
    info "加载环境变量: $env_file"
    # 安全加载，忽略注释和空行
    export $(grep -v '^#' "$env_file" | grep -v '^$' | xargs)
  else
    warn "未找到环境变量文件: $env_file"
  fi
}

# 构建镜像
build_image() {
  local tag="${1:-${APP_NAME:-myapp}:${APP_VERSION:-latest}}"
  
  info "构建镜像: $tag"
  docker build \
    --build-arg "BASE_IMAGE=${BASE_IMAGE:-alpine}" \
    --build-arg "APP_VERSION=${APP_VERSION:-1.0}" \
    -t "$tag" . && {
    success "镜像构建成功"
    docker images | grep "${tag%:*}" | grep "${tag#*:}"
  } || error "镜像构建失败"
}

# 部署服务
deploy_services() {
  local compose_file="${1:-$DEFAULT_COMPOSE_FILE}"
  
  [[ -f "$compose_file" ]] || error "Compose文件不存在: $compose_file"
  
  info "启动服务..."
  docker-compose -f "$compose_file" up -d && {
    success "服务启动成功"
    docker-compose -f "$compose_file" ps
  } || error "服务启动失败"
}

# 清理资源
clean_resources() {
  info "清理未使用资源..."
  docker system prune -f
  success "资源清理完成"
}

########################  主流程  ########################
show_help() {
  cat <<EOF
容器管理工具 v2.1

用法: $0 [命令] [选项]

命令:
  build       构建镜像 (默认命令)
  deploy      通过Compose部署
  clean       清理资源

选项:
  -h          显示帮助
  -e <文件>   指定.env文件 (默认: .env)
  -f <文件>   指定compose文件 (默认: docker-compose.yml)
  -t <标签>   镜像标签 (格式: name:version)

示例:
  # 构建镜像 (使用.env中的APP_NAME和APP_VERSION)
  $0 build

  # 使用自定义标签构建
  $0 build -t myapp:v1

  # 部署服务
  $0 deploy -f docker-compose.prod.yml

  # 清理资源
  $0 clean
EOF
}

main() {
  local command="build"
  local env_file="$DEFAULT_ENV_FILE"
  local compose_file="$DEFAULT_COMPOSE_FILE"
  local image_tag=""

  # 解析参数
  while getopts ":he:f:t:" opt; do
    case $opt in
      h) show_help; exit 0 ;;
      e) env_file="$OPTARG" ;;
      f) compose_file="$OPTARG" ;;
      t) image_tag="$OPTARG" ;;
      \?) error "无效选项: -$OPTARG" ;;
      :) error "选项 -$OPTARG 需要参数" ;;
    esac
  done
  shift $((OPTIND-1))

  # 处理命令参数
  [[ $# -gt 0 ]] && command="$1"

  # 加载环境变量
  load_env "$env_file"

  # 执行命令
  case "$command" in
    build)
      build_image "$image_tag"
      ;;
    deploy)
      deploy_services "$compose_file"
      ;;
    clean)
      clean_resources
      ;;
    *)
      error "未知命令: $command"
      ;;
  esac
}

# 严格模式并启动
set -euo pipefail
main "$@"