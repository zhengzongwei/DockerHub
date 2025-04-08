FROM openeuler/openeuler:24.03
LABEL MAINTAINER="zhengzongwei<zhengzongwei@foxmail.com>"

WORKDIR /

RUN dnf install git

RUN git clone https://github.com/openstack/octavia.git /opt/ && cd octavia && git checkout -b 2023.2 remotes/origin/stable/2023.2

RUN python -m venv /opt/octavia/venv


# 配置文件
RUN sed -i "s@TMOUT=300@TMOUT=0@g" /etc/bashrc \
    && source ~/.bashrc

# clean 
RUN dnf clean all
# clean 
RUN rm -rf /root/var \
    && rm -rf /var/cache/dnf
