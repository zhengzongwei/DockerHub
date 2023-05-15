FROM openeuler/openeuler:22.03-lts-sp1
LABEL MAINTAINER zhengzongwei<zhengzongwei@foxmail.com>

WORKDIR /

RUN dnf update  -y \
    dnf install sudo unzip golang gcc g++ git vim tmux -y

# 配置文件
RUN sed -i "s@TMOUT=300@TMOUT=0@g" /etc/bashrc \
    && source ~/.bashrc

# clean 
RUN dnf clean all
# clean 
RUN rm -rf /root/var \
    && rm -rf /var/cache/dnf
