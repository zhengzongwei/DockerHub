# MariaDB 12.1.2-noble Docker Compose 配置

这是一个可配置的 MariaDB 12.1.2-noble 容器配置，支持远程连接和自定义配置。

## 功能特性

- ✅ MariaDB 12.1.2-noble 版本
- ✅ 支持远程连接
- ✅ 可配置端口映射
- ✅ 数据持久化到本地目录
- ✅ 健康检查
- ✅ 自定义配置文件挂载
- ✅ 初始化脚本支持
- ✅ 备份目录映射

## 快速开始

1. **复制环境变量配置文件**
   ```bash
   cp .env.example .env
   ```

2. **修改 .env 文件**
   编辑 `.env` 文件，设置您的数据库密码和其他配置：
   ```bash
   MYSQL_ROOT_PASSWORD=your_secure_root_password
   MYSQL_USER=myuser
   MYSQL_PASSWORD=myuser_password
   HOST_PORT=3307  # 如果需要更改端口
   ```

3. **启动容器**
   ```bash
   docker-compose up -d
   ```

4. **验证运行状态**
   ```bash
   docker-compose ps
   docker-compose logs -f mariadb
   ```

## 配置文件说明

### docker-compose.yaml
- **端口映射**: `${HOST_PORT}:3306` - 可配置主机端口
- **数据卷**:
  - `./data` → `/var/lib/mysql` - 数据库数据
  - `./config` → `/etc/mysql/conf.d` - 自定义配置
  - `./backups` → `/backups` - 备份目录
  - `./init-scripts` → `/docker-entrypoint-initdb.d` - 初始化脚本
- **远程连接**: 配置了 `--bind-address=0.0.0.0` 允许远程连接
- **字符集**: 默认使用 `utf8mb4` 字符集和 `utf8mb4_unicode_ci` 排序规则

### 环境变量配置 (.env)

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `CONTAINER_NAME` | `mariadb` | 容器名称 |
| `HOST_PORT` | `3306` | 主机端口 |
| `MYSQL_ROOT_PASSWORD` | - | **必须设置** - root 用户密码 |
| `MYSQL_DATABASE` | `mydatabase` | 初始数据库名称 |
| `MYSQL_USER` | - | **必须设置** - 普通用户名称 |
| `MYSQL_PASSWORD` | - | **必须设置** - 普通用户密码 |
| `DATA_VOLUME` | `./data` | 数据目录 |
| `CONFIG_VOLUME` | `./config` | 配置目录 |
| `BACKUP_VOLUME` | `./backups` | 备份目录 |
| `INIT_SCRIPTS_VOLUME` | `./init-scripts` | 初始化脚本目录 |
| `MAX_CONNECTIONS` | `100` | 最大连接数 |
| `MAX_ALLOWED_PACKET` | `256M` | 最大数据包大小 |
| `INNODB_BUFFER_POOL_SIZE` | `256M` | InnoDB 缓冲池大小 |

## 目录结构

```
mariadb/
├── docker-compose.yaml    # Docker Compose 配置
├── .env.example          # 环境变量配置示例
├── .env                  # 实际环境变量配置 (需要创建)
├── data/                 # 数据库数据 (自动创建)
├── config/               # 自定义配置 (自动创建)
├── backups/              # 备份目录 (自动创建)
└── init-scripts/         # 初始化SQL脚本 (自动创建)
```

## 使用方法

### 1. 连接数据库

```bash
# 使用 root 用户连接
mysql -h 127.0.0.1 -P ${HOST_PORT} -u root -p

# 使用普通用户连接
mysql -h 127.0.0.1 -P ${HOST_PORT} -u ${MYSQL_USER} -p
```

### 2. 远程连接配置

容器已配置为允许远程连接。在客户端连接时使用：
- 主机: 您的服务器IP地址
- 端口: 您在 `.env` 中设置的 `HOST_PORT`
- 用户名: `root` 或您在 `.env` 中设置的 `MYSQL_USER`

### 3. 自定义配置

在 `config/` 目录下创建 `.cnf` 文件，这些文件将自动加载到 MariaDB 配置中。

例如，创建 `config/my-custom.cnf`:
```ini
[mysqld]
innodb_log_file_size = 256M
query_cache_size = 128M
```

### 4. 初始化脚本

将 SQL 脚本放入 `init-scripts/` 目录，容器启动时会自动执行这些脚本。

### 5. 备份和恢复

备份目录映射到 `backups/`，您可以将备份文件放入此目录或在容器内访问 `/backups`。

### 6. 管理命令

```bash
# 停止容器
docker-compose down

# 查看日志
docker-compose logs -f mariadb

# 进入容器
docker-compose exec mariadb bash

# 备份数据库 (在容器内)
docker-compose exec mariadb mysqldump -u root -p ${MYSQL_DATABASE} > backups/backup-$(date +%Y%m%d).sql
```

## 安全建议

1. **修改默认密码**: 务必修改 `.env` 文件中的密码
2. **使用强密码**: 密码应包含大小写字母、数字和特殊字符
3. **限制访问**: 如果仅本地使用，考虑使用 `127.0.0.1` 而非 `0.0.0.0`
4. **定期备份**: 定期备份 `data/` 目录或使用数据库备份工具
5. **更新镜像**: 定期更新 MariaDB 镜像以获取安全补丁

## 故障排除

### 端口冲突
如果端口被占用，修改 `.env` 文件中的 `HOST_PORT` 变量。

### 权限问题
如果遇到权限问题，确保当前用户有权限读写相关目录。

### 连接失败
检查防火墙设置，确保端口已开放。

## 版本信息

- MariaDB: 12.1.2-noble
- Docker Compose: 版本 3.8
- 默认字符集: utf8mb4
- 默认排序规则: utf8mb4_unicode_ci