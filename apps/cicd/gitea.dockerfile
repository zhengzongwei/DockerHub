FROM gitea/gitea:1.19

# 更新软件源
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories

RUN apk --no-cache add asciidoctor freetype freetype-dev gcc g++ libpng libffi-dev py-pip python3-dev py3-pip py3-pyzmq
# install any other package you need for your external renderers
RUN apk --no-cache add pandoc

# 更新pip源
RUN pip3 config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple

RUN pip3 install --upgrade pip
RUN pip3 install -U setuptools
RUN pip3 install jupyter docutils


