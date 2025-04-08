ARG BASE_IMAGE=openeuler/openeuler:24.03-lts-sp1
ARG MAINTAINER_INFO="zhengzognwei <zhengzongwei@foxmail.com>"
ARG BASH_TIMEOUT=0


FROM $BASE_IMAGE
LABEL MAINTAINER="zhengzognwei <zhengzongwei@foxmail.com>"

# 安装依赖
RUN dnf install git vim rpmdevtools* -y

# 配置文件
RUN sed -i "s@TMOUT=300@TMOUT=${BASH_TIMEOUT}@g" /etc/bashrc && \
    echo "source /etc/bashrc" >> /root/.bashrc

# clean 
RUN dnf clean all
# clean 
RUN rm -rf /root/var \
    && rm -rf /var/cache/dnf

WORKDIR /app