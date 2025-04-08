#!/usr/bin/env bash

# ==========================================
# 容器镜像构建与部署工具 v2.3
# 功能：兼容各Bash版本的构建部署方案
# ==========================================

########################  基础配置  ########################
# 颜色定义
declare -r COLOR_RESET='\033[0m'
declare -r COLOR_RED='\033[31m'
declare -r COLOR_GREEN='\033[32m'
declare -r COLOR_YELLOW='\033[33m'
declare -r COLOR_BLUE='\033[36m'

# 默认文件
declare -r DEFAULT_ENV_FILE=".env"
declare -r DEFAULT_COMPOSE_FILE="docker-compose.yml"

########################  日志函数  ########################
log() { printf '%b\n' "$1" >&2; }
info() { log "${COLOR_RESET}[*] $1${COLOR_RESET}"; }
warn() { log "${COLOR_YELLOW}[!] $1${COLOR_RESET}"; }
success() { log "${COLOR_GREEN}[✔] $1${COLOR_RESET}"; }
error() { log "${COLOR_RED}[✘] $1${COLOR_RESET}"; exit 1; }

########################  核心功能  ########################
get_os_info() {
    case "$(uname -s)" in
        Linux*)
            if [ -f /etc/os-release ]; then
                . /etc/os-release
                echo "Linux/$ID/$VERSION_ID/$(uname -m)"
            else
                echo "Linux/unknown/$(uname -m)"
            fi ;;
        Darwin*)
            echo "macOS/$(sw_vers -productVersion)/$(uname -m)" ;;
        CYGWIN*|MINGW*|MSYS*)
            echo "Windows/$(uname -m)" ;;
        *)
            echo "unknown" ;;
    esac
}

# 兼容老版本Bash的环境变量加载
load_env() {
  local env_file="${1:-$DEFAULT_ENV_FILE}"
  
  if [[ ! -f "$env_file" ]]; then
    warn "未找到环境变量文件: $env_file"
    return 1
  fi

  info "正在加载环境变量: $env_file"
  
  # 兼容性更好的加载方式
  while IFS=$'\n' read -r line; do
    line="${line%%#*}"               # 移除行内注释
    line="${line%"${line##*[![:space:]]}"}" # 移除尾部空格
    
    [[ -z "$line" ]] && continue     # 跳过空行
    
    if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      export "$line" || warn "无法设置变量: ${BASH_REMATCH[1]}"
    else
      warn "忽略无效变量定义: $line"
    fi
  done < <(grep -v '^[[:space:]]*#' "$env_file")
}


# 构建镜像（兼容旧版Docker）
build_image() {
  local tag="${1:-${APP_NAME:-myapp}:${APP_VERSION:-latest}}"
  
  info "开始构建镜像: $tag"
  
  local build_args=()
  info "使用基础镜像: ${BASE_IMAGE}"
  [[ -n "${BASE_IMAGE:-}" ]] && build_args+=(--build-arg "BASE_IMAGE=$BASE_IMAGE_REPO:$BASE_IMAGE_TAG")
  [[ -n "${MAINTAINER_INFO:-}" ]] && build_args+=(--build-arg "MAINTAINER_INFO=$MAINTAINER_NAME <>$MAINTAINER_EMAIL>")
  [[ -n "${APP_VERSION:-}" ]] && build_args+=(--build-arg "APP_VERSION=${APP_VERSION}")

  if ! docker build -t "$tag" "${build_args[@]}" . 2>&1 | tee build.log; then
    error "镜像构建失败，详见 build.log"
  fi

  success "镜像构建成功"
  docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" | 
    grep -E "^${tag%%:*}\s"
}

# 部署服务（兼容旧版docker-compose）
deploy_services() {
  local compose_file="${1:-$DEFAULT_COMPOSE_FILE}"
  
  [[ -f "$compose_file" ]] || error "Compose文件不存在: $compose_file"
  
  info "正在启动服务..."
  if docker-compose -f "$compose_file" up -d; then
    success "服务启动成功"
    
    # 基础健康检查（兼容方案）
    for i in {1..30}; do
      if docker-compose -f "$compose_file" ps | grep -q "Up"; then
        break
      fi
      sleep 1
    done
    
    docker-compose -f "$compose_file" ps 2>/dev/null || 
      warn "无法获取服务状态（可能版本不兼容）"
  else
    error "服务启动失败"
  fi
}

# 资源清理（兼容方案）
clean_resources() {
  info "正在清理资源..."
  
  docker system prune -f 2>/dev/null || {
    # 回退方案
    docker rm -f $(docker ps -aq) 2>/dev/null || true
    docker rmi -f $(docker images -q) 2>/dev/null || true
  }
  
  success "资源清理完成"
}

########################  主流程  ########################
show_help() {
  cat <<EOF
容器管理工具 v2.3 (兼容版)

用法: $(basename "$0") [命令] [选项]

命令:
  build       构建镜像 (默认)
  deploy      部署服务
  clean       清理资源

选项:
  -h          显示帮助
  -e <文件>   指定.env文件 (默认: .env)
  -f <文件>   指定compose文件 (默认: docker-compose.yml)
  -t <标签>   镜像标签 (格式: name:version)

示例:
  # 基础构建
  $(basename "$0") build -t myapp:v1

  # 指定配置部署
  $(basename "$0") deploy -f docker-compose.prod.yml -e .env.prod

  # 清理资源
  $(basename "$0") clean
EOF
}

main() {
  local command="build"
  local env_file="$DEFAULT_ENV_FILE"
  local compose_file="$DEFAULT_COMPOSE_FILE"
  local image_tag=""

  # 兼容性参数解析
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) show_help; exit 0 ;;
      -e|--env) env_file="$2"; shift ;;
      -f|--file) compose_file="$2"; shift ;;
      -t|--tag) image_tag="$2"; shift ;;
      build|deploy|clean) command="$1" ;;
      *) error "未知参数: $1" ;;
    esac
    shift
  done

  # 加载环境配置
  os_info=$(get_os_info)
  if [[ "$os_info" == *"Linux"* ]]; then
    load_env "$env_file"
  fi
  info 加载环境配置 $BASE_IMAGE_REPO
  # 执行命令
  case "$command" in
    build)  build_image "$image_tag" ;;
    deploy) deploy_services "$compose_file" ;;
    clean)  clean_resources ;;
    *)      error "未知命令: $command" ;;
  esac
}

# 兼容性严格模式设置
set -eo pipefail
if [[ "$BASH_VERSION" =~ ^[4-9] ]]; then
  shopt -s inherit_errexit 2>/dev/null || true
fi
main "$@"