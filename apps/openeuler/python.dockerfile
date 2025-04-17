# openEuler 虚环境制作镜像

FROM openeuler/openeuler:22.03-lts-sp3
LABEL MAINTAINER zhengzongwei<zhengzongwei@foxmail.com>

WORKDIR /

RUN dnf update  -y \
    dnf install gcc git python-devel -y

# 配置文件
RUN sed -i "s@TMOUT=300@TMOUT=0@g" /etc/bashrc \
    && source ~/.bashrc

# clean 
RUN dnf clean all
# clean 
RUN rm -rf /root/var \
    && rm -rf /var/cache/dnf
