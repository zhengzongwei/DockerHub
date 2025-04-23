#!/bin/bash
# ==========================================
# MariaDB 容器管理工具 v1.2
# ==========================================

# 颜色定义
readonly COLOR_RESET='\033[0m'
readonly COLOR_RED='\033[31m'
readonly COLOR_GREEN='\033[32m'
readonly COLOR_YELLOW='\033[33m'
readonly COLOR_BLUE='\033[36m'

# 日志函数
log() { printf '%b\n' "$1" >&2; }
info() { log "${COLOR_BLUE}[*] $1${COLOR_RESET}"; }
warn() { log "${COLOR_YELLOW}[!] $1${COLOR_RESET}"; }
success() { log "${COLOR_GREEN}[✔] $1${COLOR_RESET}"; }
error() { log "${COLOR_RED}[✘] $1${COLOR_RESET}"; exit 1; }

# 默认配置
readonly DEFAULT_ENV_FILE=".env.mariadb"
readonly DEFAULT_COMPOSE_FILE="docker-compose-mariadb.yml"
readonly DEFAULT_NETWORK="app-network"

# 初始化环境
init_env() {
  cat > ${DEFAULT_ENV_FILE} <<EOF
# MariaDB 配置
MARIADB_TAG=11.8-rc
MARIADB_ROOT_PASSWORD=mysql
MARIADB_USER=appuser
MARIADB_PASSWORD=apppass
MARIADB_DATABASE=appdb
MARIADB_PORT=3306
MARIADB_DATA_PATH=./data/mariadb
MARIADB_CONF_PATH=./conf/mariadb

# 网络配置
NETWORK_NAME=${DEFAULT_NETWORK}
EOF
  success "已生成默认环境变量文件: ${DEFAULT_ENV_FILE}"
}

# 加载配置
load_config() {
  local env_file="${1:-${DEFAULT_ENV_FILE}}"
  if [[ -f "${env_file}" ]]; then
    source "${env_file}"
    # 设置默认值
    export MARIADB_TAG=${MARIADB_TAG:-11.8-rc}
    export MARIADB_PORT=${MARIADB_PORT:-3306}
    export MARIADB_DATA_PATH=${MARIADB_DATA_PATH:-./data/mariadb}
    export MARIADB_CONF_PATH=${MARIADB_CONF_PATH:-./conf/mariadb}
    export NETWORK_NAME=${NETWORK_NAME:-${DEFAULT_NETWORK}}
    success "已加载配置: ${env_file}"
  else
    warn "未找到环境变量文件，使用默认配置"
  fi
}

# 生成自定义配置文件
generate_config() {
  # 确保配置目录存在
  local conf_dir="${MARIADB_CONF_PATH:-./conf/mariadb}"
  mkdir -p "$conf_dir" || {
    error "无法创建配置目录: $conf_dir"
    return 1
  }
#   cat > "${MARIADB_CONF_PATH}/custom.cnf" <<EOF
# [mysqld]
# # 性能优化
# innodb_buffer_pool_size=1G
# innodb_log_file_size=256M
# innodb_flush_log_at_trx_commit=2

# # 字符集
# character-set-server=utf8mb4
# collation-server=utf8mb4_unicode_ci

# # 连接设置
# max_connections=200
# wait_timeout=600
# EOF
  success "已生成自定义配置文件"
}

# 生成Docker Compose文件
generate_compose() {
  cat > "${DEFAULT_COMPOSE_FILE}" <<EOF
version: '3.8'

services:
  mariadb:
    image: mariadb:\${MARIADB_TAG}
    container_name: mariadb
    environment:
      - MARIADB_ROOT_PASSWORD=\${MARIADB_ROOT_PASSWORD}
      - MARIADB_USER=\${MARIADB_USER}
      - MARIADB_PASSWORD=\${MARIADB_PASSWORD}
      - MARIADB_DATABASE=\${MARIADB_DATABASE}
    volumes:
      - \${MARIADB_DATA_PATH}:/var/lib/mysql
      - \${MARIADB_CONF_PATH}:/etc/mysql/conf.d
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    ports:
      - "\${MARIADB_PORT}:3306"
    networks:
      - \${NETWORK_NAME}
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 10s
      timeout: 5s
      retries: 3

networks:
  \${NETWORK_NAME}:
    driver: bridge
EOF
  success "已生成 Docker Compose 文件: ${DEFAULT_COMPOSE_FILE}"
}

# 启动服务
start() {
  load_config
  if [[ ! -f "${DEFAULT_COMPOSE_FILE}" ]]; then
    generate_compose
  fi
  
  # 创建必要目录
  mkdir -p "${MARIADB_DATA_PATH}" "${MARIADB_CONF_PATH}"
  
  # 生成默认配置（如果不存在）
  [[ ! -f "${MARIADB_CONF_PATH}/custom.cnf" ]] && generate_config
  
  # 创建Docker网络（如果不存在）
  if ! docker network inspect "${NETWORK_NAME}" >/dev/null 2>&1; then
    docker network create "${NETWORK_NAME}"
    success "已创建Docker网络: ${NETWORK_NAME}"
  fi
  
  # 启动服务
  info "启动 MariaDB 服务..."
  docker-compose -f "${DEFAULT_COMPOSE_FILE}" up -d && {
    success "MariaDB 已启动"
    echo -e "\n连接信息:"
    echo -e "主机: 127.0.0.1"
    echo -e "端口: ${MARIADB_PORT}"
    echo -e "用户: ${MARIADB_USER}"
    echo -e "密码: ${MARIADB_PASSWORD}"
    echo -e "数据库: ${MARIADB_DATABASE}"
    echo -e "\n管理命令: $0 status|stop|logs|cli"
  } || error "启动失败"
}

# 停止服务
stop() {
  load_config
  info "停止 MariaDB 服务..."
  docker-compose -f "${DEFAULT_COMPOSE_FILE}" down
  success "服务已停止"
}

# 服务状态
status() {
  load_config
  docker-compose -f "${DEFAULT_COMPOSE_FILE}" ps
}

# 查看日志
logs() {
  load_config
  docker-compose -f "${DEFAULT_COMPOSE_FILE}" logs -f
}

# 进入CLI
cli() {
  load_config
  info "连接到 MariaDB CLI..."
  docker exec -it mariadb mysql -u${MARIADB_USER} -p${MARIADB_PASSWORD} ${MARIADB_DATABASE}
}

# 备份数据库
backup() {
  load_config
  local backup_dir="./backups"
  local timestamp=$(date +%Y%m%d_%H%M%S)
  local backup_file="${backup_dir}/mariadb_backup_${timestamp}.sql"
  
  mkdir -p "${backup_dir}"
  info "正在备份数据库..."
  docker exec mariadb sh -c 'exec mysqldump -u${MARIADB_USER} -p${MARIADB_PASSWORD} ${MARIADB_DATABASE}' > "${backup_file}" && {
    success "数据库已备份到: ${backup_file}"
  } || error "备份失败"
}

# 主菜单
usage() {
  echo -e "\nMariaDB 容器管理工具"
  echo -e "Usage: $0 {start|stop|status|logs|cli|backup|init|help}"
  echo -e "\nCommands:"
  echo -e "  init        初始化配置文件和目录"
  echo -e "  start       启动MariaDB服务"
  echo -e "  stop        停止服务"
  echo -e "  status      查看服务状态"
  echo -e "  logs        查看实时日志"
  echo -e "  cli         进入MySQL命令行"
  echo -e "  backup      备份数据库"
  echo -e "  help        显示帮助信息"
}

main() {
  case "$1" in
    init)    init_env; generate_config ;;
    start)   start ;;
    stop)    stop ;;
    status)  status ;;
    logs)    logs ;;
    cli)     cli ;;
    backup)  backup ;;
    help|*)  usage ;;
  esac
}

# 执行主函数
if [[ $# -eq 0 ]]; then
  usage
else
  main "$1"
fi