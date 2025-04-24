#!/bin/bash
# Docker Compose CI/CD 环境启动脚本

# 设置颜色代码
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# 检查依赖项
check_dependencies() {
    if ! command -v docker-compose &> /dev/null; then
        echo -e "${RED}错误: docker-compose 未安装${NC}"
        exit 1
    fi
}

# 安全加载环境变量
load_env() {
    local env_file=".env"
    
    if [[ -f "$env_file" ]]; then
        echo -e "${GREEN}加载环境变量: $env_file${NC}"
        export $(grep -v '^#' "$env_file" | grep -v '^$' | xargs -0)
    else
        echo -e "${RED}错误: 未找到 .env 文件${NC}"
        exit 1
    fi
}

# 检查端口占用
check_ports() {
    local ports=($NGINX_PORT $NGINX_SSL_PORT $NGINX_SSH_PORT)
    for port in "${ports[@]}"; do
        if lsof -i :$port &>/dev/null; then
            echo -e "${RED}错误: 端口 $port 已被占用${NC}"
            exit 1
        fi
    done
}

# 准备目录结构
setup_dirs() {
    local dirs=("$MARIADB_PATH" "$GITEA_PATH" "$ACT_PATH" "$NGINX_PATH")
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            echo -e "${GREEN}创建目录: $dir${NC}"
        fi
    done
}

# 启动服务
start_service() {
    echo -e "${GREEN}启动 Docker Compose 服务...${NC}"
    docker-compose --env-file .env -f docker-compose.yml up -d --build
    
    if [[ $? -eq 0 ]]; then
        echo -e "\n${GREEN}服务启动成功！${NC}"
        echo -e "访问地址: http://localhost:$NGINX_PORT"
        echo -e "SSH 访问: git@localhost:$NGINX_SSH_PORT"
    else
        echo -e "${RED}服务启动失败${NC}"
        exit 1
    fi
}

# 主流程
main() {
    check_dependencies
    load_env
    check_ports
    setup_dirs
    start_service
}

main "$@"