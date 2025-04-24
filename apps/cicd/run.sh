#!/bin/bash
# Docker Compose 快速启动脚本

# 设置颜色代码
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# 检查依赖项
check_dependencies() {
    if ! command -v docker-compose &> /dev/null; then
        echo -e "${RED}错误: docker-compose 未安装${NC}"
        exit 1
    fi
}

# 加载环境变量
load_env() {
    local env_file=".env"
    
    if [[ -f "$env_file" ]]; then
        echo -e "${GREEN}加载环境变量: $env_file${NC}"
        # 安全地加载环境变量（忽略注释和空行）
        export $(grep -v '^#' "$env_file" | xargs)
    else
        echo -e "${RED}错误: 未找到 .env 文件${NC}"
        exit 1
    fi
}

# 启动服务
start_service() {
    local compose_file="docker-compose.yml"
    
    echo -e "${GREEN}启动 Docker Compose 服务...${NC}"
    docker-compose --env-file .env -f "$compose_file" up -d
    
    if [[ $? -eq 0 ]]; then
        echo -e "\n${GREEN}服务启动成功！${NC}"
        echo -e "运行以下命令查看日志:"
        echo -e "  docker-compose logs -f"
    else
        echo -e "${RED}服务启动失败${NC}"
        exit 1
    fi
}

# 主流程
main() {
    check_dependencies
    load_env
    start_service
}

main "$@"