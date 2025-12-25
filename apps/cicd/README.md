# Gitea Docker镜像构建和部署指南

## 脚本说明

**`build_and_deploy.sh`** - 统一的构建和部署脚本，集成了镜像构建和容器编排功能

## 使用方法

### 推荐使用方式
```bash
# 进入项目目录
cd /Users/zhengzongwei/CodeHub/GitHub/DockerHub/apps/cicd

# 构建镜像并运行服务（完整流程）
./build_and_deploy.sh

# 或使用不同参数
./build_and_deploy.sh         # 构建镜像并运行（默认）
./build_and_deploy.sh build   # 只构建镜像
./build_and_deploy.sh run     # 只运行服务（假设镜像已构建）
./build_and_deploy.sh clean   # 停止服务并清理资源
./build_and_deploy.sh status  # 查看服务状态
./build_and_deploy.sh logs    # 查看服务日志
./build_and_deploy.sh help    # 显示帮助信息
```

## 脚本功能说明

### `build_and_deploy.sh` 的主要步骤：
1. **构建镜像**：使用 `gitea.dockerfile` 构建自定义Gitea镜像
2. **更新配置**：自动修改 `docker-compose.yaml` 以使用自定义镜像
3. **准备环境**：创建必要的目录结构
4. **运行服务**：启动Gitea、MariaDB、act_runner和Nginx

### 构建的镜像特点：
- 基于官方Gitea镜像
- 添加了额外软件包：asciidoctor、pandoc、jupyter等
- 使用清华镜像源加速下载
- 自定义标签：`gitea-custom:$GITEA_TAG`

## 环境变量

脚本会读取 `.env` 文件中的配置，主要变量包括：

```bash
# Gitea配置
GITEA_TAG=1.25.3
GITEA_PORT=9527
GITEA_SSH_PORT=9528

# 数据库配置
MARIADB_PORT=16030
MARIADB_ROOT_PASSWORD=mysql
MARIADB_USER=gitea
MARIADB_PASSWORD=gitea

# 路径配置
BASE_PATH=/data/apps/cicd
```

## 服务访问地址

部署成功后，可以通过以下地址访问：

- **Gitea Web界面**: http://localhost:9527
- **Gitea SSH端口**: localhost:9528
- **数据库端口**: localhost:16030

## 常见问题

### 1. 权限问题
```bash
# 如果脚本无法执行
chmod +x build_and_deploy.sh

# 如果Docker权限不足
sudo usermod -aG docker $USER
# 重新登录后生效
```

### 2. 构建失败
- 检查网络连接
- 检查Docker是否正常运行：`docker info`
- 检查 `.env` 文件是否存在且配置正确

### 3. 服务启动失败
```bash
# 查看详细错误日志
docker-compose logs

# 检查端口占用
sudo lsof -i :9527
```

## 管理命令

```bash
# 查看所有容器状态
docker-compose ps

# 查看Gitea日志
docker-compose logs gitea-server

# 重启服务
docker-compose restart

# 停止所有服务
docker-compose down

# 清理所有资源（包括数据）
./build_and_deploy.sh clean
```

## 注意事项

1. **首次启动**：Gitea需要初始化数据库，可能需要1-2分钟
2. **磁盘空间**：确保有足够的磁盘空间（镜像约1.1GB，数据另计）
3. **网络配置**：确保所需端口未被占用
4. **备份配置**：脚本会自动备份 `docker-compose.yaml` 文件

## 快速开始

```bash
# 最简单的开始方式
cd /Users/zhengzongwei/CodeHub/GitHub/DockerHub/apps/cicd
./build_and_deploy.sh
```

执行完成后，打开浏览器访问 http://localhost:9527 即可使用Gitea。