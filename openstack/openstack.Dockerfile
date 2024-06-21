# FROM openeuler/openeuler:24.03-lts
FROM ${IMAGE_TAG}:${IMAGE_VERSION}

LABEL MAINTAINER="zhengzongwei <zhengzongwei@foxmail.com>" 

# 系统配置
RUN dnf install sudo vim less gcc python3-devel python3-unversioned-command git python-pip patch
# PIP 设置
RUN pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple

RUN sudo ldconfig

# ------------ hosts 修改


# 中间件部署

RUN mkdir -p /etc/my.cnf.d/ && \
 tee /etc/my.cnf.d/openstack.cnf > /dev/null <<EOF
[mysqld]
bind-address = 127.0.0.1
default-storage-engine = innodb
innodb_file_per_table = on
max_connections = 4096
collation-server = utf8_general_ci
character-set-server = utf8
EOF


RUN mariadb mariadb-server python3-PyMySQL
# 配置 MARIADB
RUN useradd -r mysql
# 启动 MARIADB
RUN su mysql -s /bin/bash -c 'mysqld &'


# RABBITMQ
RUN yum install rabbitmq-server -y && rabbitmq-server &

RUN rabbitmqctl add_user openstack openstack && rabbitmqctl set_permissions openstack ".*" ".*" ".*" && rabbitmq-plugins enable rabbitmq_management 

# MEMCACHE
RUN dnf install memcached

RUN useradd -r memcache && memcached -d -u memcache

# openStack 组件部署

# ------------------ openstackclient 部署
RUN python -m venv /opt/openstackclient/venv && source /opt/openstackclient/venv/bin/activate &&  pip install openstackclient && cp /opt/openstackclient/venv/bin/openstack* /usr/bin/


#------------------keystone 部署

RUN dnf install httpd mod_wsgi -y

 
RUN getent group keystone >/dev/null || groupadd -r keystone \
    && ! getent passwd keystone >/dev/null && \
    useradd -r -g keystone -G keystone,nobody -d /var/lib/keystone -s /sbin/nologin -c "OpenStack Keystone Daemons" keystone

RUN mkdir -p /etc/keystone /var/lib/keystone /var/log/keystone \
    && chown -R keystone:keystone /etc/keystone /var/lib/keystone /var/log/keystone

RUN git clone https://opendev.org/openstack/keystone.git /opt/keystone && cd /opt/keystone && \
    git checkout -b stable/2023.2 remotes/origin/stable/2023.2

RUN python -m venv /opt/keystone/venv && source /opt/keystone/venv/bin/activate &&  pip install -r keystone.txt && python /opt/keystone/setup.py install && cp /opt/keystone/venv/bin/keystone-* /usr/bin/

RUN PYTHON_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")


RUN patch -d /opt/keystone/venv/lib64/python$PYTHON_VERSION/site-packages/eventlet/green/ -p0 <<EOF
--- thread.py   2024-06-21 09:41:23.272953003 +0000
+++ thread.py   2024-06-21 09:41:47.157214000 +0000
@@ -32,9 +32,12 @@
 
 
 def get_ident(gr=None):
-    if gr is None:
-        return id(greenlet.getcurrent())
-    else:
+    try:
+        if gr is None:
+            return id(greenlet.getcurrent())
+        else:
+            return id(gr)
+    except:
         return id(gr)
 
 def __thread_body(func, args, kwargs):
EOF

# RUN mysql && \
# CREATE DATABASE keystone; \ 
# GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY 'keystone'; && \
# GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY 'keystone'; 

# RUN keystone-manage db_sync && keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone && \
# keystone-manage credential_setup --keystone-user keystone --keystone-group keystone
RUN mysql -e "\
    CREATE DATABASE keystone; \
    GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY 'keystone'; \
    GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY 'keystone';"

# 执行Keystone数据库初始化和设置
RUN keystone-manage db_sync && \
    keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone && \
    keystone-manage credential_setup --keystone-user keystone --keystone-group keystone

RUN tee /etc/keystone/keystone.conf > /dev/null <<EOF
[database]
connection = mysql+pymysql://keystone:keystone@127.0.0.1/keystone

[token]
provider = fernet

EOF

RUN keystone-manage bootstrap --bootstrap-password admin \
--bootstrap-admin-url http://127.0.0.1:5000/v3/ \
--bootstrap-internal-url http://127.0.0.1:5000/v3/ \
--bootstrap-public-url http://127.0.0.1:5000/v3/ \
--bootstrap-region-id RegionOne

RUN ln -s /opt/keystone/httpd/wsgi-keystone.conf /etc/httpd/conf.d/

RUN tee /etc/httpd/conf.d/wsgi-keystone.conf > /dev/null <<EOF
Listen 5000

<VirtualHost *:5000>
    WSGIDaemonProcess keystone-public processes=5 threads=1 user=keystone group=keystone display-name=%{GROUP} home=/opt/keystone python-home=/opt/keystone/venv python-path=/opt/keystone/venv/lib/python3.9/site-packages
    WSGIProcessGroup keystone-public
    WSGIScriptAlias / /opt/keystone/venv/bin/keystone-wsgi-public
    WSGIApplicationGroup %{GLOBAL}
    WSGIPassAuthorization On
    LimitRequestBody 114688
    <IfVersion >= 2.4>
      ErrorLogFormat "%{cu}t %M"
    </IfVersion>
    ErrorLog /var/log/httpd/keystone_error.log
    CustomLog /var/log/httpd/keystone_access.log combined

    <Directory /opt/keystone/venv>
        <IfVersion >= 2.4>
            Require all granted
        </IfVersion>
        <IfVersion < 2.4>
            Order allow,deny
            Allow from all
        </IfVersion>
    </Directory>
</VirtualHost>
Alias /identity /opt/keystone/venv/bin/keystone-wsgi-public
<Location /identity>
    SetHandler wsgi-script
    Options +ExecCGI

    WSGIProcessGroup keystone-public
    WSGIApplicationGroup %{GLOBAL}
    WSGIPassAuthorization On
</Location>

EOF

RUN sed -i 's/#ServerName www.example.com:80/ServerName controller/' /etc/httpd/conf/httpd.conf && httpd -DFOREGROUND &

RUN tee /root/.admin-openrc > /dev/null <<EOF
export OS_PROJECT_DOMAIN_NAME=Default
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_NAME=admin
export OS_USERNAME=admin
export OS_PASSWORD=admin
export OS_AUTH_URL=http://controller:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
EOF

RUN source ~/.admin-openrc && openstack domain create --description "An Example Domain" example



RUN openstack domain create --description "An Example Domain" example && \
 openstack project create --domain default --description "Service Project" service && \
 openstack project create --domain default --description "Demo Project" demo-project && \
 openstack user create --domain default --password "demo" demo && \
 openstack role create demo && \
 openstack role add --project demo-project --user demo demo

 # 验证
 RUN openstack --os-auth-url http://controller:5000/v3 \
--os-project-domain-name Default --os-user-domain-name Default \
--os-project-name admin --os-username admin token issue