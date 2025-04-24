# 使用官方Ubuntu LTS镜像
FROM ubuntu:latest

# 设置环境变量（避免交互式提示）
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Shanghai

# 安装基础开发工具集
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    # 系统工具
    ca-certificates \
    curl \
    wget \
    git \
    ssh \
    vim \
    # 编译工具链
    build-essential \
    gcc \
    g++ \
    make \
    cmake \
    autoconf \
    # 语言环境
    python3 \
    python3-pip \
    python3-venv \
    golang \
    # 其他常用工具
    tree \
    htop \
    net-tools \
    # 清理缓存
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# 配置Python别名
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3 1

# 验证安装
RUN echo "Installed tools:" && \
    gcc --version | head -n1 && \
    python --version && \
    go version && \
    tree --version

RUN  rm -rf /var/lib/apt/lists/*
# 设置工作目录
WORKDIR /workspace

# 默认启动命令
CMD ["/bin/bash"]
