# 使用 ARG 指令来接收环境变量，并提供默认值
ARG GITEA_VERSION=1.24.6

# 使用动态版本的基础镜像
FROM gitea/gitea:${GITEA_VERSION}

LABEL maintainer="zhengzongwei<zhengzongwei@foxmail.com>"
LABEL description="Customized Gitea Docker image with additional packages"

# 更新软件源
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories

RUN apk --no-cache add asciidoctor freetype freetype-dev gcc g++ libpng libffi-dev pandoc python3-dev py3-pyzmq pipx
# 安装其他您需要的外部渲染器的软件包

RUN pipx install jupyter docutils --include-deps --index-url https://pypi.tuna.tsinghua.edu.cn/simple
