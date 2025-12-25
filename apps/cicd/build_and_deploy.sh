#!/bin/bash

# Gitea Docker镜像构建和部署脚本
# 这个脚本专门用于先构建自定义的Gitea镜像，然后再运行服务

# 更严格的错误处理（去掉 -u，避免未加载 .env 时因未定义变量退出）
set -eo pipefail

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查命令
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "命令 $1 未找到，请先安装"
        exit 1
    fi
}

# 检查Docker
check_docker() {
    if ! docker info &> /dev/null; then
        log_error "Docker未运行或当前用户无权限"
        exit 1
    fi
}

# 加载环境变量
load_env() {
    if [ -f .env ]; then
        log_info "加载环境变量..."
        set -a
        source .env
        set +a
    else
        log_warning "未找到 .env 文件"
        exit 1
    fi
}

# 初始化日志（需在 load_env 之后调用）
init_logging() {
    DEPLOY_LOG_PATH="${DEPLOY_LOG_PATH:-${BASE_PATH}/logs/deploy.log}"
    sudo mkdir -p "$(dirname "$DEPLOY_LOG_PATH")" 2>/dev/null || true
    sudo touch "$DEPLOY_LOG_PATH" 2>/dev/null || true
    sudo chown "$(id -u):$(id -g)" "$(dirname "$DEPLOY_LOG_PATH")" 2>/dev/null || true
    log_info "部署日志: $DEPLOY_LOG_PATH"
}

# 检查并修复 docker-compose.yaml（移除 BOM 并验证语法）
ensure_compose_valid() {
    if [ ! -f "docker-compose.yaml" ]; then
        log_error "未找到 docker-compose.yaml 文件"
        exit 1
    fi

    # 检测并移除 UTF-8 BOM（EF BB BF）
    if head -c 3 docker-compose.yaml | od -An -t x1 | tr -d ' \t\n' | grep -qi '^efbbbf'; then
        log_warning "检测到 UTF-8 BOM，正在移除..."
        # tail -c +4 从第4字节开始，保留文件其余内容
        if tail -c +4 docker-compose.yaml > docker-compose.yaml.nobom 2>/dev/null; then
            mv docker-compose.yaml.nobom docker-compose.yaml
            log_success "已移除 BOM"
        else
            log_error "移除 BOM 失败（tail 命令出错）"
            exit 1
        fi
    fi

    # 使用 docker-compose 验证语法
    if ! docker-compose -f docker-compose.yaml config >/dev/null 2>&1; then
        log_error "docker-compose.yaml 语法校验失败，打印诊断信息："
        echo "---- 文件头 1-10 行 (不可见字符用 ^ 表示) ----"
        sed -n '1,10p' docker-compose.yaml | cat -A
        echo "---- 文件前 2 行十六进制 ----"
        if command -v hexdump >/dev/null 2>&1; then
            hexdump -C docker-compose.yaml | sed -n '1,2p'
        else
            od -An -t x1 -N 16 docker-compose.yaml | sed -n '1p'
        fi
        log_error "请修复 docker-compose.yaml 后重试"
        exit 1
    fi
}

# 步骤1: 构建Gitea镜像
build_gitea_image() {
    log_info "步骤1: 构建自定义Gitea镜像"

    # 检查Dockerfile
    if [ ! -f "$GITEA_DOCKERFILE_NAME" ]; then
        log_error "未找到 $GITEA_DOCKERFILE_NAME 文件"
        exit 1
    fi

    # 若未设置 GITEA_VERSION，则提示并跳过构建（避免 set -u 导致错误）
    if [ -z "${GITEA_VERSION:-}" ]; then
        log_warning "GITEA_VERSION 未设置，跳过构建自定义 Gitea 镜像。如需构建请在 .env 中设置 GITEA_VERSION"
        return 0
    fi

    log_info "使用Dockerfile: $GITEA_DOCKERFILE_NAME"
    log_info "Gitea版本: $GITEA_VERSION"
    log_info "构建上下文: $GITEA_DOCKERFILE_DIR"

    # 构建镜像
    log_info "开始构建镜像 (这可能需要几分钟)..."

    if docker build \
        --build-arg GITEA_VERSION="$GITEA_VERSION" \
        -t "gitea-custom:$GITEA_VERSION" \
        -f "$GITEA_DOCKERFILE_NAME" \
        "$GITEA_DOCKERFILE_DIR"; then

        log_success "Gitea镜像构建完成: gitea-custom:$GITEA_VERSION"
        # 显示镜像信息
        log_info "镜像信息:"
        docker images | grep gitea-custom
    else
        log_error "Gitea镜像构建失败"
        exit 1
    fi
}

# 额外的校验：检测 BOM/CRLF/制表符并用 docker-compose 校验
lint_compose() {
    if [ ! -f "docker-compose.yaml" ]; then
        log_error "未找到 docker-compose.yaml"
        exit 1
    fi

    # 检测 BOM（EF BB BF）
    if head -c 3 docker-compose.yaml | od -An -t x1 | tr -d ' \t\n' | grep -qi '^efbbbf'; then
        log_warning "检测到 UTF-8 BOM，正在移除..."
        tail -c +4 docker-compose.yaml > docker-compose.yaml.nobom && mv docker-compose.yaml.nobom docker-compose.yaml
        log_success "已移除 BOM"
    fi

    # 检测 Windows CRLF
    if grep -q $'\r' docker-compose.yaml; then
        log_warning "检测到 CRLF（Windows 行结束），建议转换为 LF"
        # 自动转换（如果可行）
        sed -i 's/\r$//' docker-compose.yaml || true
    fi

    # 检测制表符（YAML 要求空格缩进）
    if grep -n $'\t' docker-compose.yaml >/dev/null 2>&1; then
        log_error "检测到制表符 (tab)，请将缩进改为空格"
        grep -n $'\t' docker-compose.yaml | sed -n '1,10p'
        exit 1
    fi

    # 使用 docker-compose 做最终校验
    if ! docker-compose -f docker-compose.yaml config >/dev/null 2>&1; then
        log_error "docker-compose.yaml 校验失败，打印头部以供诊断："
        sed -n '1,20p' docker-compose.yaml | cat -A
        if command -v hexdump >/dev/null 2>&1; then
            hexdump -C docker-compose.yaml | sed -n '1,2p'
        fi
        exit 1
    fi

    log_info "docker-compose.yaml 校验通过"
}

# 步骤2: 更新docker-compose配置
update_docker_compose() {
    log_info "步骤2: 更新docker-compose配置"

    if [ ! -f "docker-compose.yaml" ]; then
        log_error "未找到 docker-compose.yaml 文件"
        exit 1
    fi

    # 先校验文件
    lint_compose

    # 备份原始文件（仅备份一次）
    if [ ! -f "docker-compose.yaml.backup" ]; then
        cp docker-compose.yaml docker-compose.yaml.backup
        log_info "已备份原始docker-compose.yaml文件"
    fi

    # 如果已经配置为自定义镜像则退出
    if grep -q "image: gitea-custom" docker-compose.yaml; then
        log_info "docker-compose已配置为使用自定义镜像"
        return 0
    fi

    if [ -z "${GITEA_VERSION:-}" ]; then
        log_warning "GITEA_VERSION 未设置，跳过向 docker-compose 自动插入 image: gitea-custom:<version>"
        return 0
    fi

    # 插入 image 行（在 container_name 之后）
    if sed -n '/^  gitea-server:/,/^[^[:space:]]/p' docker-compose.yaml | grep -q 'container_name: gitea-server'; then
        sed -i '/^  container_name: gitea-server/a\    image: gitea-custom:'"$GITEA_VERSION" docker-compose.yaml
        log_info "已向 gitea-server 添加 image: gitea-custom:$GITEA_VERSION"
        # 再次校验
        if ! docker-compose -f docker-compose.yaml config >/dev/null 2>&1; then
            log_error "插入 image 后校验失败，已恢复备份"
            mv docker-compose.yaml.backup docker-compose.yaml
            exit 1
        fi
        log_success "docker-compose配置已更新为使用自定义镜像"
    else
        log_warning "未在 gitea-server 块中找到 container_name: gitea-server，跳过自动插入"
    fi
}

# 步骤3: 准备配置文件
prepare_configurations() {
    log_info "步骤3: 准备配置文件"

    # 必要环境变量（与 .env 保持一致）
    required=(BASE_PATH CONF_BASE_PATH DATA_BASE_PATH \
              MARIADB_DATA_PATH MARIADB_CONF_PATH \
              GITEA_DATA_PATH GITEA_CONF_PATH \
              ACT_DATA_PATH ACT_CONF_PATH \
              NGINX_DATA_PATH NGINX_CONF_PATH)

    for v in "${required[@]}"; do
        if [ -z "${!v}" ]; then
            log_error "环境变量 $v 未设置，请在 .env 中添加并重试"
            exit 1
        fi
    done

    # 创建目录（含 conf 与 data 子目录）
    dirs=( "$BASE_PATH" "$CONF_BASE_PATH" "$DATA_BASE_PATH" \
           "$MARIADB_DATA_PATH" "$MARIADB_CONF_PATH" \
           "$GITEA_DATA_PATH" "$GITEA_CONF_PATH" \
           "$ACT_DATA_PATH" "$ACT_CONF_PATH" \
           "$NGINX_DATA_PATH" "$NGINX_CONF_PATH" )

    for d in "${dirs[@]}"; do
        sudo mkdir -p "$d"
    done

    log_info "已创建必要的目录结构: BASE:$BASE_PATH, CONF:$CONF_BASE_PATH, DATA:$DATA_BASE_PATH, MariaDB:$MARIADB_DATA_PATH, Gitea:$GITEA_DATA_PATH, Actions:$ACT_DATA_PATH, Nginx:$NGINX_DATA_PATH"

    # 将整个 cicd 基础目录（BASE_PATH）递归设置为 0755（仅修改权限，不改变属主）
    if [ -d "$BASE_PATH" ]; then
        log_info "正在将 $BASE_PATH 及其子目录权限设置为 0755（仅修改权限，不改变属主）"
        if sudo chmod -R 0755 "$BASE_PATH"; then
            log_success "已将 $BASE_PATH 权限设置为 0755"
            log_info "当前 $BASE_PATH 权限: $(ls -ld "$BASE_PATH" | awk '{print $1, $3":"$4}')"
        else
            log_warning "无法自动设置 $BASE_PATH 为 0755。请手动运行： sudo chmod -R 0755 \"$BASE_PATH\""
        fi
    else
        log_warning "$BASE_PATH 不存在，跳过权限设置"
    fi

    # 复制/覆盖配置：将仓库 conf 同步到目标配置目录（直接覆盖，不保留备份）
    if [ -d "conf" ]; then
        sudo mkdir -p "$CONF_BASE_PATH"
        log_info "正在将仓库 conf 同步到 $CONF_BASE_PATH（直接覆盖目标）"
        # 无 rsync：清空目标再复制
        sudo rm -rf "${CONF_BASE_PATH:?}/"*
        sudo cp -a conf/. "$CONF_BASE_PATH"/ || true
    fi

    # 确保 act_runner 的配置被复制到 ACT_CONF_PATH（覆盖/补齐）
    if [ -d "conf/act_runner" ]; then
        sudo mkdir -p "$ACT_CONF_PATH"
        log_info "正在将 conf/act_runner 内容复制到 $ACT_CONF_PATH（覆盖/补齐）"
        sudo cp -a "conf/act_runner/." "$ACT_CONF_PATH"/ || true
        log_success "已将 conf/act_runner 复制到 $ACT_CONF_PATH"
    fi

    # 处理 nginx.conf 若被误建为目录：直接删除目录并使用仓库中的 nginx.conf 覆盖（不备份）
    if [ -d "$NGINX_CONF_PATH/nginx.conf" ]; then
        log_warning "检测到 $NGINX_CONF_PATH/nginx.conf 为目录，执行删除以便覆盖主配置文件（不会备份）"
        sudo rm -rf "$NGINX_CONF_PATH/nginx.conf" || true
    fi

    # 如果仓库中有示例 nginx.conf，直接覆盖目标 nginx.conf（强制覆盖）
    if [ -f "conf/nginx/nginx.conf" ]; then
        sudo mkdir -p "$NGINX_CONF_PATH"
        sudo cp -f "conf/nginx/nginx.conf" "$NGINX_CONF_PATH/nginx.conf" || true
        log_success "已将仓库 conf/nginx/nginx.conf 覆盖到 $NGINX_CONF_PATH/nginx.conf"
    fi

    # # 合并/覆盖后立即校验 nginx 配置，若失败则提示并中止
    # if ! check_nginx_config; then
    #     log_error "合并/覆盖配置后 nginx 配置校验失败，请修复 $NGINX_CONF_PATH 的配置后重试"
    #     exit 1
    # fi

    # 关于配置文件，脚本只负责复制样例和创建目录；其他问题仅提示用户手动修复
    # 检查 nginx.conf 类型与存在性并提示（不做自动修改）
    if [ -d "$NGINX_CONF_PATH/nginx.conf" ]; then
        log_warning "$NGINX_CONF_PATH/nginx.conf 是目录，但应该是文件。请手动修复（删除或重命名），脚本不会自动更改配置文件。"
    fi

    if [ ! -f "$NGINX_CONF_PATH/nginx.conf" ]; then
        log_warning "未找到 $NGINX_CONF_PATH/nginx.conf。请在 $NGINX_CONF_PATH 中放置正确的 nginx.conf（脚本不会自动创建该文件）。"
    fi

    # 确保 conf.d/stream.d 目录存在（脚本会创建目录，但不会填充内容）
    sudo mkdir -p "$NGINX_CONF_PATH/conf.d" "$NGINX_CONF_PATH/stream.d"
    if [ ! -d "$NGINX_CONF_PATH/conf.d" ] || [ ! -d "$NGINX_CONF_PATH/stream.d" ]; then
        log_warning "未检测到 $NGINX_CONF_PATH/conf.d 或 $NGINX_CONF_PATH/stream.d，脚本已尝试创建。请将您的 *.conf 放入相应目录。"
    fi

    # 提示其他服务配置目录（仅提示，不修改）
    for svc_conf in "$MARIADB_CONF_PATH" "$GITEA_CONF_PATH" "$ACT_CONF_PATH"; do
        if [ ! -d "$svc_conf" ]; then
            log_warning "未检测到配置目录 $svc_conf。请在该目录放置相应配置（脚本不会自动创建配置内容）。"
        fi
    done
}

# 步骤4: 运行服务
run_services() {
    log_info "步骤4: 启动所有服务"

    log_info "正在启动服务 (这可能需要一些时间)..."

    # 运行docker-compose
    if docker-compose up -d; then
        log_success "服务启动成功"

        # 显示服务状态
        log_info "服务状态:"
        docker-compose ps

        # 等待服务完全启动
        log_info "等待服务初始化 (15秒)..."
        sleep 15

        # 显示访问信息
        echo ""
        echo "========================================="
        echo "         Gitea CI/CD 环境已就绪"
        echo "========================================="
        echo ""
        echo "📱 访问信息:"
        echo "  Gitea Web界面: http://localhost:$GITEA_PORT"
        echo "  Gitea SSH端口: localhost:$GITEA_SSH_PORT"
        echo "  数据库端口:    localhost:$MARIADB_PORT"
        echo ""
        echo "⚙️  管理命令:"
        echo "  查看日志:      docker-compose logs -f"
        echo "  停止服务:      docker-compose down"
        echo "  重启服务:      docker-compose restart"
        echo "  查看状态:      docker-compose ps"
        echo ""
        echo "🔧 其他命令:"
        echo "  构建镜像:      $0 build"
        echo "  只运行服务:    $0 run"
        echo "  清理资源:      $0 clean"
        echo ""
        echo "⚠️  注意: 首次访问需要等待数据库初始化完成"
        echo "========================================="

        # 提示：如何避免每次通过 SSH 指定端口（例如 2222）
        echo ""
        echo "[TIP] 若不想在 git/ssh 操作时每次指定 -p ${NGINX_SSH_PORT:-2222}，可在本机添加 SSH 配置："
        echo ""
        echo "  $ mkdir -p ~/.ssh && chmod 700 ~/.ssh"
        echo "  $ cat >> ~/.ssh/config <<'EOF'"
        echo "Host ${DOMAIN:-code.dev.com}"
        echo "  HostName localhost"
        echo "  Port ${NGINX_SSH_PORT:-2222}"
        echo "  User git"
        echo "  IdentitiesOnly yes"
        echo "EOF"
        echo "  $ chmod 600 ~/.ssh/config"
        echo ""
        echo "之后直接使用 git@${DOMAIN:-code.dev.com}:<owner>/<repo>.git 不需要再指定端口。"
        echo "替代方案：可使用 ssh://git@<host>:<port>/owner/repo.git 或 GIT_SSH_COMMAND='ssh -p <port>' 来临时指定端口。"
    else
        log_error "服务启动失败"
        # 检查常见端口冲突（例如宿主 22 被占用）
        if command -v ss >/dev/null 2>&1; then
            if ss -ltn | awk '{print $4}' | grep -qE '(:|\\.)22$'; then
                log_warning "检测到主机上端口 22 已被占用，可能与 nginx 的 SSH 端口映射冲突"
                log_info "请检查 .env 中 NGINX_SSH_PORT/ GITEA_SSH_PORT 是否冲突，或将 NGINX_SSH_PORT 改为其他端口（例如 2222）"
            fi
        elif command -v netstat >/dev/null 2>&1; then
            if netstat -ltn | awk '{print $4}' | grep -qE '(:|\\.)22$'; then
                log_warning "检测到主机上端口 22 已被占用，可能与 nginx 的 SSH 端口映射冲突"
                log_info "请检查 .env 中 NGINX_SSH_PORT/ GITEA_SSH_PORT 是否冲突，或将 NGINX_SSH_PORT 改为其他端口（例如 2222）"
            fi
        fi
        log_info "查看详细日志: docker-compose logs"
        exit 1
    fi
}

# --------- 新增/改进：校验 nginx 配置（用于 doctor） ----------
check_nginx_config() {
    if [ -z "${NGINX_CONF_PATH:-}" ]; then
        log_warning "NGINX_CONF_PATH 未设置，跳过 nginx 配置校验"
        return 1
    fi

    if [ ! -d "$NGINX_CONF_PATH" ]; then
        log_warning "未找到 nginx 配置目录: $NGINX_CONF_PATH"
        return 1
    fi

    if [ -d "$NGINX_CONF_PATH/nginx.conf" ]; then
        log_error "$NGINX_CONF_PATH/nginx.conf 是目录，应该是文件。请修正后重试。"
        return 1
    fi

    if [ ! -f "$NGINX_CONF_PATH/nginx.conf" ]; then
        log_warning "未找到主配置文件 $NGINX_CONF_PATH/nginx.conf，跳过语法校验"
        return 1
    fi

    # 如果有名为 cicd 的 Docker 网络，使用该网络运行临时容器以便解析内部服务名（如 gitea-server）
    NET_OPT=""
    if docker network inspect cicd >/dev/null 2>&1; then
        NET_OPT="--network cicd"
        log_info "检测到 Docker 网络 'cicd'，将在该网络下运行临时 nginx 验证以解析内部主机名"
    fi

    log_info "使用临时 nginx 镜像验证 $NGINX_CONF_PATH 下的配置（nginx -t）..."
    tmpout="$(mktemp)"
    if docker run --rm $NET_OPT -v "${NGINX_CONF_PATH}:/etc/nginx:ro" nginx:latest nginx -t -c /etc/nginx/nginx.conf >"$tmpout" 2>&1; then
        log_success "nginx 配置校验通过"
        rm -f "$tmpout" || true
        return 0
    else
        # 如果错误中包含 upstream 主机解析失败，这通常是因为在无网络或无目标容器时无法解析，
        # 把该情况降级为警告（语法可能正确，但无法解析 upstream 主机）。
        if grep -qi "host not found in upstream" "$tmpout" 2>/dev/null; then
            log_warning "nginx 配置语法基本通过，但检测到 upstream 主机解析失败（示例: 'host not found in upstream')."
            log_warning "请确保相关服务（如 gitea-server）在同一 Docker 网络上运行，或在容器内验证 nginx 启动。nginx -t 输出（部分）："
            sed -n '1,200p' "$tmpout" | sed -n '1,40p' || true
            rm -f "$tmpout" || true
            return 0
        fi

        log_error "nginx 配置校验失败，输出如下："
        sed -n '1,200p' "$tmpout" || true
        rm -f "$tmpout" || true
        return 1
    fi
}
# --------- 新增/改进结束 ----------

# 新增：收集关键服务日志的“医生”命令
doctor() {
    log_info "运行系统检查（doctor），将关键日志追加到 $DEPLOY_LOG_PATH"
    ensure_compose_valid || true
    check_nginx_config || true

    echo "===== docker-compose ps =====" >> "$DEPLOY_LOG_PATH" 2>/dev/null || true
    docker-compose ps >> "$DEPLOY_LOG_PATH" 2>&1 || true

    # 输出 act_runner 配置文件状态/内容，帮助定位注册失败（缺少 /data/config.yaml 或 token 错误等）
    echo "===== act_runner config =====" >> "$DEPLOY_LOG_PATH" 2>/dev/null || true
    if [ -f "$ACT_DATA_PATH/config.yaml" ]; then
        echo "CONFIG_PATH: $ACT_DATA_PATH/config.yaml" >> "$DEPLOY_LOG_PATH" 2>/dev/null || true
        echo "---- head (first 200 lines) ----" >> "$DEPLOY_LOG_PATH" 2>/dev/null || true
        sed -n '1,200p' "$ACT_DATA_PATH/config.yaml" >> "$DEPLOY_LOG_PATH" 2>&1 || true
    else
        echo "CONFIG_MISSING: $ACT_DATA_PATH/config.yaml" >> "$DEPLOY_LOG_PATH" 2>/dev/null || true
    fi

    for svc in mariadb mariadb-cicd nginx gitea-server act_runner; do
        echo "===== logs ${svc} (tail 200) =====" >> "$DEPLOY_LOG_PATH" 2>/dev/null || true
        docker logs --tail 200 "${svc}" >> "$DEPLOY_LOG_PATH" 2>&1 || true
    done

    log_info "诊断已写入: $DEPLOY_LOG_PATH"
}

# 清理资源
cleanup() {
    log_info "清理资源..."

    # 停止服务
    docker-compose down 2>/dev/null || true

    # # 删除自定义镜像
    # docker rmi "gitea-custom:$GITEA_VERSION" 2>/dev/null || true

    # 恢复原始docker-compose文件
    if [ -f "docker-compose.yaml.backup" ]; then
        mv docker-compose.yaml.backup docker-compose.yaml
        log_info "已恢复原始docker-compose.yaml文件"
    fi

    log_success "资源清理完成"
}

build_only() {
	check_command docker
	check_docker
	load_env
	build_gitea_image
}

# 添加：运行服务（假设镜像已构建）
run_only() {
	# 检查必需工具并加载环境，然后按正常流程准备并启动服务
	check_command docker
	check_command docker-compose
	check_docker
	load_env
	prepare_configurations
	# 在运行服务前验证 docker-compose 文件
	ensure_compose_valid
	run_services
}

# 显示帮助
show_help() {
    echo "Gitea Docker镜像构建和部署脚本"
    echo ""
    echo "使用方法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  (无参数)  构建镜像并启动所有服务（默认）"
    echo "  build     只构建Gitea Docker镜像"
    echo "  run       只运行服务（需要已构建的镜像）"
    # echo "  validate  验证 docker-compose 与 nginx 配置（不启动服务）"
    echo "  doctor    收集各服务日志（写入部署日志），用于故障排查"
    # echo "  fix-mariadb  尝试修复 MariaDB 数据目录权限（需 sudo）"
    echo "  clean     停止服务并清理资源"
    echo "  status    查看服务状态"
    echo "  logs      查看服务日志（实时）"
    echo "  help      显示此帮助信息"
    echo ""
    echo "部署日志路径: ${DEPLOY_LOG_PATH:-<未初始化>}"
    echo ""
}

# 主函数
main() {
    log_info "开始执行Gitea镜像构建和部署"
    echo ""

    # 检查必要工具
    check_command docker
    check_command docker-compose
    check_docker

    # 加载环境变量
    load_env

    # 初始化日志
    init_logging

    # 验证 docker-compose.yaml（并移除 BOM）
    ensure_compose_valid

    # 执行所有步骤
    build_gitea_image
    update_docker_compose
    prepare_configurations
    run_services

    log_success "Gitea CI/CD环境部署完成！"
}

# 根据参数执行
case "${1:-}" in
    build)
        build_only
        ;;
    run)
        run_only
        ;;
    # validate)
    #     load_env
    #     init_logging
    #     validate_all
    #     ;;
    doctor)
        load_env
        init_logging
        doctor
        ;;
    # fix-mariadb)
    #     load_env
    #     init_logging
    #     fix_mariadb_perms || exit 1
    #     ;;
    clean)
        cleanup
        ;;
    status)
        docker-compose ps
        ;;
    logs)
        docker-compose logs -f
        ;;
    help|--help|-h)
        show_help
        ;;
    "")
        main
        ;;
    *)
        log_error "未知选项: $1"
        show_help
        exit 1
        ;;
esac

