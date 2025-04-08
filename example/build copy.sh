#!/usr/bin/env bash

# ==========================================
# 容器镜像构建工具 v1.3
# 功能：支持带环境变量的镜像构建，可删除旧镜像
# ==========================================

########################  基础库  ########################
# 设置颜色代码
readonly COLOR_YELLOW='\033[33m'
readonly COLOR_RESET='\033[0m'
readonly COLOR_BLUE='\033[36m'
readonly COLOR_GREEN='\033[32m'
readonly COLOR_RED='\033[31m'

msg() {
  printf '%b\n' "$1" >&2
}

info() {
  msg "${COLOR_RESET}[ ] ${COLOR_RESET}$1${COLOR_RESET}"
}

warn() {
  msg "${COLOR_YELLOW}[!] ${COLOR_YELLOW}$1${COLOR_RESET}"
}

tips() {
  msg "${COLOR_BLUE}[*] ${COLOR_BLUE}$1${COLOR_RESET}"
}

success() {
  msg "${COLOR_GREEN}[✔] ${COLOR_GREEN}$1${COLOR_RESET}"
}

error() {
  msg "${COLOR_RED}[✘] ${COLOR_RED}$1${COLOR_RESET}"
  exit 1
}

########################  主逻辑  ########################
# 严格模式
set -euo pipefail
IFS=$'\n\t'

# 常量定义
readonly DEFAULT_TAG="my-openeuler-image:latest"
readonly DEFAULT_BASE_IMAGE="openeuler/openeuler:22.03-lts-sp1"
readonly DEFAULT_PACKAGES="sudo git"
readonly SCRIPT_NAME=$(basename "$0")

# 全局变量
show_help=false
remove_old=false
force_remove=false
image_tag=""
build_args=()

# 显示帮助信息
show_help() {
  tips "容器镜像构建工具"
  tips "用法: $SCRIPT_NAME [选项]"
  echo
  tips "选项:"
  info "  -h           显示此帮助信息"
  info "  -t <标签>     指定镜像标签 (默认: ${DEFAULT_TAG})"
  info "  -r           构建前删除同名旧镜像"
  info "  -f           强制删除关联容器后再删除镜像(需配合 -r 使用)"
  info "  -e <文件>     指定环境变量文件 (默认: .env)"
  echo
  tips "示例:"
  info "  $SCRIPT_NAME -t custom-image:v1     # 构建自定义标签镜像"
  info "  $SCRIPT_NAME -r -t test-image      # 删除旧镜像后构建"
  info "  $SCRIPT_NAME -r -f -t prod-image   # 强制清理后构建"
  info "  $SCRIPT_NAME -e config.env         # 使用指定环境变量文件"
}

# 解析命令行参数
parse_args() {
  local env_file=".dockerfile.env"

  while getopts ":hrt:fe:" opt; do
    case ${opt} in
      h ) show_help=true ;;
      t ) image_tag=$OPTARG ;;
      r ) remove_old=true ;;
      f ) force_remove=true ;;
      e ) env_file=$OPTARG ;;
      \? )
        error "无效选项: -$OPTARG"
        ;;
      : )
        error "选项 -$OPTARG 需要一个参数"
        ;;
    esac
  done
  shift $((OPTIND -1))

  # 处理-f没有-r的情况
  if [ "$force_remove" = true ] && [ "$remove_old" = false ]; then
    warn "-f 需要与 -r 一起使用，已忽略 -f 参数"
    force_remove=false
  fi
}

# 删除旧镜像
remove_old_image() {
  local tag=$1
  tips "检查旧镜像: $tag"

  if ! docker image inspect "$tag" &>/dev/null; then
    info "未找到同名旧镜像"
    return 0
  fi

  # 强制删除关联容器
  if [ "$force_remove" = true ]; then
    local containers=$(docker ps -aq --filter "ancestor=$tag")
    if [ -n "$containers" ]; then
      tips "正在强制删除关联容器..."
      docker rm -f $containers || {
        warn "部分容器删除失败"
      }
    fi
  fi

  # 删除镜像
  tips "正在删除旧镜像: $tag"
  if docker rmi "$tag"; then
    success "旧镜像删除成功"
  else
    warn "旧镜像删除失败，继续构建..."
  fi
}

# 加载环境变量
load_env() {
  local env_file=${1:-.env}
  
  if [ ! -f "$env_file" ]; then
    warn "未找到环境变量文件: $env_file，使用默认值"
    return 1
  fi

  tips "加载环境变量文件: $env_file"
  set -a
  source "$env_file" || {
    warn "环境变量文件加载失败"
    return 1
  }
  set +a

  # 验证必要变量
  if [ -z "${BASE_IMAGE:-}" ]; then
    warn "BASE_IMAGE 未设置，使用默认值: $DEFAULT_BASE_IMAGE"
  fi
}

# 准备构建参数
prepare_build_args() {
  build_args=(
    "--build-arg" "BASE_IMAGE=${BASE_IMAGE:-$DEFAULT_BASE_IMAGE}"
    "--build-arg" "MAINTAINER_NAME=${MAINTAINER_NAME:-auto}"
    "--build-arg" "MAINTAINER_EMAIL=${MAINTAINER_EMAIL:-}"
    "--build-arg" "PACKAGES=${PACKAGES:-$DEFAULT_PACKAGES}"
    "--build-arg" "BASH_TIMEOUT=${BASH_TIMEOUT:-0}"
  )
}

# 构建镜像
build_image() {
  local tag=$1
  shift
  local build_args=("$@")

  tips "开始构建镜像: $tag"
  info "构建参数: ${build_args[*]}"

  if docker build -t "$tag" "${build_args[@]}" .; then
    success "镜像构建成功: $tag"
    # 显示镜像信息
    tips "镜像详细信息:"
    docker images | grep "^${tag%:*}" | grep "${tag#*:}" || true
  else
    error "镜像构建失败"
  fi
}

# 主函数
main() {
  parse_args "$@"

  if [ "$show_help" = true ]; then
    show_help
    exit 0
  fi

  local tag=${image_tag:-$DEFAULT_TAG}

  # 删除旧镜像
  if [ "$remove_old" = true ]; then
    remove_old_image "$tag"
  fi

  # 加载环境变量
  load_env "${env_file:-.env}"

  # 准备构建参数
  prepare_build_args

  # 执行构建
  build_image "$tag" "${build_args[@]}"
}

main "$@"