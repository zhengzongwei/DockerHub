#!/bin/bash
# ==========================================
# Gitea CI/CD 容器管理工具 v3.0
# ==========================================

########################  初始化配置  ########################
set -euo pipefail  # 严格模式

# 颜色定义
readonly COLOR_RESET='\033[0m'
readonly COLOR_RED='\033[31m'
readonly COLOR_GREEN='\033[32m'
readonly COLOR_YELLOW='\033[33m'
readonly COLOR_BLUE='\033[36m'

# 默认文件
readonly DEFAULT_ENV_FILE=".env"
readonly DEFAULT_COMPOSE_FILE="docker-compose.yml"
readonly DEFAULT_DOCKERFILE="Dockerfile"

########################  日志函数  ########################
log() { printf '%b\n' "$*" >&2; }
info() { log "${COLOR_BLUE}[*] $*${COLOR_RESET}"; }
warn() { log "${COLOR_YELLOW}[!] $*${COLOR_RESET}"; }
success() { log "${COLOR_GREEN}[✔] $*${COLOR_RESET}"; }
error() { log "${COLOR_RED}[✘] $*${COLOR_RESET}"; exit 1; }

########################  核心功能  ########################

# 检查依赖项
check_dependencies() {
    local missing=()
    for cmd in docker docker-compose curl; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "缺少依赖: ${missing[*]}"
    fi
}

# 安全加载环境变量
load_env() {
    local env_file="${1:-$DEFAULT_ENV_FILE}"
    
    if [[ ! -f "$env_file" ]]; then
        warn "未找到环境变量文件: $env_file"
        return 1
    fi

    info "加载环境变量: $env_file"
    export $(grep -v '^#' "$env_file" | xargs) >/dev/null 2>&1

    # 设置默认值
    export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-gitea_stack}"
    export GITEA_PORT="${GITEA_PORT:-3000}"
    export GITEA_HTTP_PORT="${GITEA_HTTP_PORT:-3000}"
}

# 验证必须变量
validate_required_vars() {
    local required_vars=(
        "MARIADB_ROOT_PASSWORD"
        "MARIADB_PASSWORD"
        "GITEA_SECRET_KEY"
    )

    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error "必须设置环境变量: $var"
        fi
    done
}

# 生成 Runner Token
generate_runner_token() {
    if [[ -z "${GITEA_RUNNER_REGISTRATION_TOKEN:-}" ]]; then
        info "正在生成 Gitea Runner 注册令牌..."
        
        local max_retries=3
        local retry_delay=5
        local token=""
        
        for ((i=1; i<=max_retries; i++)); do
            if token=$(docker exec -i gitea-server gitea actions generate-runner-token 2>/dev/null); then
                export GITEA_RUNNER_REGISTRATION_TOKEN="$token"
                echo "GITEA_RUNNER_REGISTRATION_TOKEN=$token" >> "$DEFAULT_ENV_FILE"
                success "已生成并保存 Runner Token"
                return 0
            fi
            sleep "$retry_delay"
        done
        
        error "生成 Runner Token 失败"
    fi
}

# 等待服务就绪
wait_for_service() {
    local service="$1"
    local port="${2:-}"
    local max_retries=12
    local retry_delay=5

    info "等待 $service 服务就绪..."
    
    if [[ -n "$port" ]]; then
        # 通过端口检测
        for ((i=1; i<=max_retries; i++)); do
            if curl -sSf "http://localhost:$port" >/dev/null; then
                success "$service 服务已就绪"
                return 0
            fi
            sleep "$retry_delay"
        done
    else
        # 通过日志检测
        for ((i=1; i<=max_retries; i++)); do
            if docker-compose logs "$service" | grep -q "Listening on"; then
                success "$service 服务已就绪"
                return 0
            fi
            sleep "$retry_delay"
        done
    fi
    
    error "$service 服务启动超时"
}

# 构建镜像
build_image() {
    info "构建 Gitea 自定义镜像"
    
    docker build \
        --build-arg GITEA_VERSION="${GITEA_VERSION:-1.23.7}" \
        -t "gitea-custom:${GITEA_VERSION:-latest}" \
        -f "${GITEA_DOCKERFILE_NAME:-$DEFAULT_DOCKERFILE}" . && {
        success "镜像构建成功"
        docker images | grep "gitea-custom"
    } || error "镜像构建失败"
}

# 启动服务
start_services() {
    info "启动容器服务..."
    
    # 创建必要目录
    mkdir -p "${MARIADB_PATH:-./data/mariadb}" \
             "${GITEA_PATH:-./data/gitea}" \
             "${ACT_PATH:-./data/act_runner}"
    
    if docker-compose up -d; then
        success "容器启动命令已发送"
    else
        error "容器启动失败"
    fi
}

# 显示服务状态
show_status() {
    echo -e "\n${COLOR_GREEN}======= 服务状态 =======${COLOR_RESET}"
    docker-compose ps
    
    echo -e "\n${COLOR_GREEN}======= 访问信息 =======${COLOR_RESET}"
    echo "Gitea:    http://localhost:${GITEA_PORT:-3000}"
    echo "MariaDB:  localhost:${MARIADB_PORT:-3306}"
    echo "SSH:      ssh://git@localhost:${GITEA_SSH_PORT:-2222}"
    
    if [[ -n "${GITEA_RUNNER_REGISTRATION_TOKEN:-}" ]]; then
        echo -e "\n${COLOR_GREEN}Runner 注册令牌:${COLOR_RESET} $GITEA_RUNNER_REGISTRATION_TOKEN"
    fi
}

# 清理资源
clean_resources() {
    info "清理未使用的Docker资源..."
    docker system prune -f && success "资源清理完成" || warn "资源清理过程中出现警告"
}

########################  主流程  ########################

# 部署完整环境
deploy() {
    check_dependencies
    load_env
    validate_required_vars
    start_services
    wait_for_service "gitea-server" "${GITEA_PORT:-3000}"
    generate_runner_token
    show_status
}

# 显示帮助
usage() {
    cat <<EOF
Usage: $0 [command]

Commands:
  build       构建自定义Gitea镜像
  deploy      部署完整环境 (默认命令)
  clean       清理未使用的Docker资源
  status      显示服务状态
  help        显示帮助信息

Environment:
  默认从当前目录的 .env 文件加载环境变量
EOF
}

main() {
    local command="${1:-deploy}"
    
    case "$command" in
        build)
            load_env
            build_image
            ;;
        deploy)
            deploy
            ;;
        clean)
            clean_resources
            ;;
        status)
            load_env
            show_status
            ;;
        help|-h|--help)
            usage
            ;;
        *)
            error "未知命令: $command\n$(usage)"
            ;;
    esac
}

# 执行入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi