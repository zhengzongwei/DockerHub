#!/bin/bash

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查 Docker 是否安装
check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装，请先安装 Docker"
        exit 1
    fi

    if ! command -v docker-compose &> /dev/null; then
        log_error "docker-compose 未安装，请先安装 docker-compose"
        exit 1
    fi

    if ! docker info &> /dev/null; then
        log_error "Docker 守护进程未运行，请启动 Docker"
        exit 1
    fi

    log_info "Docker 检查通过"
}

# 加载环境变量
load_env() {
    local env_file=".env"
    local env_example=".env.example"

    # 如果 .env 不存在，从 .env.example 复制
    if [ ! -f "$env_file" ]; then
        if [ -f "$env_example" ]; then
            log_warning ".env 文件不存在，从 .env.example 复制"
            cp "$env_example" "$env_file"
            log_info "已创建 .env 文件，请根据需要修改配置"
        else
            log_error ".env 文件不存在且 .env.example 也不存在"
            exit 1
        fi
    fi

    # 加载环境变量
    if [ -f "$env_file" ]; then
        log_info "加载环境变量从 $env_file"

        # 安全地加载环境变量，忽略注释和空行
        while IFS='=' read -r key value || [ -n "$key" ]; do
            # 跳过注释和空行
            [[ $key =~ ^#.* ]] || [[ -z $key ]] && continue

            # 去除可能的引号
            value="${value%\"}"
            value="${value#\"}"
            value="${value%\'}"
            value="${value#\'}"

            # 导出变量
            export "$key=$value"
        done < <(grep -v '^\s*#' "$env_file" | grep -v '^\s*$')

        log_info "环境变量加载完成"
    else
        log_error "无法加载 .env 文件"
        exit 1
    fi
}

# 创建目录结构
create_directories() {
    log_info "开始创建目录结构..."

    # 从环境变量获取基础路径或使用默认值
    BASE_PATH="${DATA_VOLUME%/data}"
    if [ -z "$BASE_PATH" ] || [ "$BASE_PATH" = "/data/apps/mariadb" ]; then
        BASE_PATH="/data/apps"
        MARIADB_PATH="$BASE_PATH/mariadb"
    else
        MARIADB_PATH="${DATA_VOLUME%/data}"
    fi

    log_info "使用基础路径: $MARIADB_PATH"

    # 创建目录
    local dirs=("data" "config" "backups" "init-scripts")
    for dir in "${dirs[@]}"; do
        local full_path="$MARIADB_PATH/$dir"
        if [ ! -d "$full_path" ]; then
            log_info "创建目录: $full_path"
            sudo mkdir -p "$full_path"
            sudo chmod 755 "$full_path"
        else
            log_info "目录已存在: $full_path"
        fi
    done

    # 设置权限
    if [ -d "$MARIADB_PATH" ]; then
        sudo chmod 755 "$MARIADB_PATH"
    fi

    log_info "✓ 目录结构创建完成"
}

# 迁移现有数据
migrate_existing_data() {
    local current_dir="$(pwd)"
    local dirs=("data" "config" "backups" "init-scripts")

    log_info "检查是否有现有的配置数据..."

    for dir in "${dirs[@]}"; do
        if [ -d "$current_dir/$dir" ] && [ "$(ls -A "$current_dir/$dir" 2>/dev/null)" ]; then
            log_info "迁移 $dir 目录..."
            if [ -d "$MARIADB_PATH/$dir" ]; then
                sudo cp -r "$current_dir/$dir/"* "$MARIADB_PATH/$dir/" 2>/dev/null || \
                    log_warning "$dir 目录迁移失败或为空"
                log_info "✓ $dir 目录迁移完成"
            else
                log_warning "目标目录 $MARIADB_PATH/$dir 不存在"
            fi
        else
            log_info "没有现有的 $dir 目录数据"
        fi
    done
}

# 启动 Docker Compose
start_docker_compose() {
    log_info "启动 MariaDB 容器..."

    # 检查 docker-compose.yaml 是否存在
    if [ ! -f "docker-compose.yaml" ]; then
        log_error "docker-compose.yaml 文件不存在"
        exit 1
    fi

    # 显示配置信息
    log_info "容器配置信息:"
    echo "========================================"
    echo "容器名称: ${CONTAINER_NAME:-mariadb}"
    echo "主机端口: ${HOST_PORT:-3306}"
    echo "网络名称: ${NETWORK_NAME:-mariadb-network}"
    echo "数据目录: ${DATA_VOLUME:-./data}"
    echo "配置目录: ${CONFIG_VOLUME:-./config}"
    echo "备份目录: ${BACKUP_VOLUME:-./backups}"
    echo "初始化脚本目录: ${INIT_SCRIPTS_VOLUME:-./init-scripts}"
    echo "========================================"

    # 启动容器
    log_info "正在启动 MariaDB 容器..."

    if docker-compose up -d; then
        log_info "✓ MariaDB 容器启动成功"

        # 显示容器状态
        log_info "容器状态:"
        docker-compose ps

        # 显示连接信息
        echo ""
        log_info "连接信息:"
        echo "主机: localhost"
        echo "端口: ${HOST_PORT:-3306}"
        echo "用户名: ${MYSQL_USER:-root}"
        echo "密码: ${MYSQL_PASSWORD:-请查看 .env 文件}"

        if [ -n "${MYSQL_DATABASE:-}" ]; then
            echo "数据库: ${MYSQL_DATABASE}"
        fi

        log_info "可以使用以下命令查看日志: docker-compose logs -f"
        log_info "可以使用以下命令停止容器: docker-compose down"

    else
        log_error "MariaDB 容器启动失败"
        log_info "请查看详细日志: docker-compose logs"
        exit 1
    fi
}

# 主函数
main() {
    log_info "======= MariaDB 一键启动脚本 ======="
    log_info "开始时间: $(date)"
    echo ""

    # 检查 Docker
    check_docker

    # 加载环境变量
    load_env

    # 创建目录结构
    create_directories

    # 迁移现有数据
    migrate_existing_data

    # 启动 Docker Compose
    start_docker_compose

    echo ""
    log_info "======= 脚本执行完成 ======="
    log_info "完成时间: $(date)"
}

# 运行主函数
main "$@"