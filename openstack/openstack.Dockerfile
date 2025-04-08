FROM openeuler/openeuler:24.03-lts
# FROM ${IMAGE_TAG}:${IMAGE_VERSION}

LABEL MAINTAINER="zhengzongwei <zhengzongwei@foxmail.com>" 

# 系统配置

RUN dnf install sudo vim less gcc python3-devel python3-unversioned-command git python-pip patch hostname net-tools iputils  -y

# PIP 设置
RUN pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple

RUN sudo ldconfig

# ------------ hosts 修改
# 设置环境变量
# ENV HOSTNAME controller
# ENV IP_ADDRESS 127.0.0.1

# 在镜像构建过程中执行Shell脚本来检查和添加记录
RUN \
    if grep -qE "^\s*$IP_ADDRESS\s+$HOSTNAME\s*$" /etc/hosts; then \
    echo "记录已存在"; \
    else \
    echo "记录不存在，正在新增记录..."; \
    echo "$IP_ADDRESS $HOSTNAME" | tee -a /etc/hosts > /dev/null; \
    if [ $? -eq 0 ]; then \
    echo "记录已成功添加"; \
    else \
    echo "添加记录失败"; \
    exit 1; \
    fi; \
    fi

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

RUN dnf install mariadb-server
# 配置 MARIADB
RUN useradd -r mysql
# 启动 MARIADB
RUN su mysql -s /bin/bash -c 'mysqld &'


# RABBITMQ
RUN yum install rabbitmq-server -y 

# 配置 MARIADB
RUN useradd -r mysql
# 启动 MARIADB
RUN mysql_install_db --user=mysql --ldata=/var/lib/mysql && su mysql -s /bin/bash -c 'mysqld &'


# RABBITMQ
RUN dnf install rabbitmq-server -y

RUN rabbitmqctl add_user openstack openstack && rabbitmqctl set_permissions openstack ".*" ".*" ".*" && rabbitmq-plugins enable rabbitmq_management 

# MEMCACHE
RUN dnf install memcached -y

RUN  mkdir -p /var/run/memcached \
    chown memcached:memcached /var/run/memcached \
    chmod 755 /var/run/memcached

# RUN useradd -r memcache && memcached -d -u memcache


# openStack 组件部署

# ------------------ openstackclient 部署
RUN python -m venv /opt/openstackclient/venv && source /opt/openstackclient/venv/bin/activate &&  pip install openstackclient && cp /opt/openstackclient/venv/bin/openstack* /usr/bin/


#------------------keystone 部署

RUN dnf install httpd mod_wsgi -y

RUN getent group keystone >/dev/null || groupadd -r keystone \
    && ! getent passwd keystone >/dev/null && \
    useradd -r -g keystone -G keystone,nobody -d /var/lib/keystone -s /sbin/nologin -c "OpenStack Keystone Daemons" keystone

RUN git clone https://opendev.org/openstack/keystone.git /opt/keystone && cd /opt/keystone && \
    git checkout -b stable/2023.2 remotes/origin/stable/2023.2

RUN mkdir -p /etc/keystone /var/lib/keystone /var/log/keystone \
    && chown -R keystone:keystone /etc/keystone /var/lib/keystone /var/log/keystone /opt/keystone

RUN python -m venv /opt/keystone/venv && source /opt/keystone/venv/bin/activate &&  pip install -r requirements.txt && pip install python-memcached pymysql SQLAlchemy==1.4.52 && python /opt/keystone/setup.py install && cp /opt/keystone/venv/bin/keystone-* /usr/bin/

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
    --bootstrap-admin-url http://$HOSTNAME:5000/v3/ \
    --bootstrap-internal-url http://$HOSTNAME:5000/v3/ \
    --bootstrap-public-url http://$HOSTNAME:5000/v3/ \
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


RUN sed -i 's/#ServerName www.example.com:80/ServerName ${HOSTNAME}/' /etc/httpd/conf/httpd.conf && httpd -DFOREGROUND &

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


RUN source ~/.admin-openrc && openstack domain create --description "An Example Domain" example && \
    openstack project create --domain default --description "Service Project" service && \
    openstack project create --domain default --description "Demo Project" demo-project && \
    openstack user create --domain default --password "demo" demo && \
    openstack role create demo && \
    openstack role add --project demo-project --user demo demo

# 验证
RUN openstack --os-auth-url http://controller-1:5000/v3 \
    --os-project-domain-name Default --os-user-domain-name Default \
    --os-project-name admin --os-username admin token issue

# Glance 
RUN getent group glance >/dev/null || groupadd -r glance \
    && ! getent passwd glance >/dev/null && \
    useradd -r -g glance -G glance,nobody -d /var/lib/glance -s /sbin/nologin -c "OpenStack Glance Daemons" glance

RUN mkdir -p /var/lib/glance/ /var/log/glance /etc/glance /etc/glance/glance-api.conf.d/ /etc/glance/glance.conf.d/


RUN git clone https://opendev.org/openstack/glance.git /opt/glance && cd /opt/glance && \
    git checkout -b stable/2023.2 remotes/origin/stable/2023.2

RUN chown -R glance:glance /etc/glance/ /var/log/glance/ /var/lib/glance/ /opt/glance

RUN python -m venv /opt/glance/venv && source /opt/glance/venv/bin/activate && \
    pip install -r requirements.txt && python /opt/glance/setup.py install && cp /opt/glance/venv/bin/glance-* /usr/bin/ \
    pip install python-memcached pymysql SQLAlchemy==1.4.52


RUN mysql -e "\
    CREATE DATABASE glance; \
    GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY 'glance'; \
    GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY 'glance';"

RUN su -s /bin/sh -c "glance-manage db_sync" glance

RUN tee /etc/glance/glance-api.conf > /dev/null <<EOF
[DEFAULT]
# 日志文件路径，如果你不想记录到文件，可以不设置此选项
log_file = /var/log/glance/api.log

[database]
connection = mysql+pymysql://glance:glance@${HOSTNAME}/glance

[keystone_authtoken]
www_authenticate_uri  = http://${HOSTNAME}:5000
auth_url = http://${HOSTNAME}:5000
memcached_servers = ${HOSTNAME}:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = glance
password = glance

[paste_deploy]
flavor = keystone

[glance_store]
stores = file,http
default_store = file
filesystem_store_datadir = /var/lib/glance/images/

EOF

# RUN cp /opt/glance/etc/glance-api-paste.ini /opt/glance/

COPY /opt/glance/etc/glance-api-paste.ini /opt/glance/

RUN openstack user create --domain default --password "glance" glance && \
    openstack role add --project service --user glance admin && \
    openstack service create --name glance --description "OpenStack Image" image

RUN openstack endpoint create --region RegionOne image public http://${hostname}:9292 && \
    openstack endpoint create --region RegionOne image internal http://${hostname}:9292 && \
    openstack endpoint create --region RegionOne image admin http://${hostname}:9292

COPY ./init.d/glance-api /etc/init.d/

RUN chown +x /etc/init.d/glance-api && /etc/init.d/glance-api restart



RUN IMAGE_VERSION=$IMAGE_VERSION \
    IMAGE_ARCH=$(uname -m) \
    IMAGE_NAME=cirros${IMAGE_VERSION}-${IMAGE_ARCH}-disk.img \
    IMAGE_PATH = /opt/${IMAGE_NAME}
# 验证镜像
RUN if [ ! -f "/path/to/" ]; then \
    echo "文件 $FILE_NAME 不存在。正在下载..."; \
    curl -L -O https://github.com/cirros-dev/cirros/releases/download/${IMAGE_VERSION}/${IMAGE_NAME} \
    else \
    echo "文件 $FILE_NAME 已存在。"; \
    fi

RUN openstack image create --disk-format qcow2 --container-format bare --file $IMAGE_NAME --public cirros


# placement 部署
RUN getent group placement >/dev/null || groupadd -r placement \
    && ! getent passwd placement >/dev/null && \
    useradd -r -g placement -G placement,nobody -d /var/lib/placement -s /sbin/nologin -c "OpenStack Placement Daemons" placement


RUN git clone https://opendev.org/openstack/placement.git /opt/placement && git config --global --add safe.directory /opt/placement && cd /opt/placement/ \
    && git checkout -b stable/2023.2 remotes/origin/stable/2023.2

RUN mkdir -p /var/log/placement/ /etc/placement/ && chown -R placement:placement /var/log/placement/ /etc/placement/ /opt/placement/

RUN python -m venv /opt/placement/venv && source /opt/placement/venv/bin/activate \
    &&  pip install -r requirements.txt && pip install python-memcached pymysql SQLAlchemy==1.4.52 \
    && python /opt/placement/setup.py install && deactivate && cp /opt/placement/venv/bin/placement-* /usr/bin/

RUN mysql -e "\
    CREATE DATABASE placement; \
    GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'localhost' IDENTIFIED BY 'placement'; \
    GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'%' IDENTIFIED BY 'placement';"


# 创建Placement API服务
RUN source ~/.admin-openrc && openstack user create --domain default --password "placement" placement \
    && openstack role add --project service --user placement admin \
    && openstack service create --name placement --description "Placement API" placement \
    && openstack endpoint create --region RegionOne placement public http://${HOSTNAME}:8778 \
    && openstack endpoint create --region RegionOne placement internal http://${HOSTNAME}:8778 \
    && openstack endpoint create --region RegionOne placement admin http://${HOSTNAME}:8778

RUN tee /etc/placement//placement.conf > /dev/null <<EOF
[placement_database]
connection = mysql+pymysql://placement:placement@controller/placement
[api]
auth_strategy = keystone
[keystone_authtoken]
auth_url = http://controller:5000/v3
memcached_servers = controller:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = placement
password = placement

EOF

RUN su -s /bin/sh -c "placement-manage db sync" placement

RUN tee /etc/httpd/conf.d/00-placement-api.conf > /dev/null <<EOF
Listen 8778

<VirtualHost *:8778>
  WSGIProcessGroup placement-api
  WSGIApplicationGroup %{GLOBAL}
  WSGIPassAuthorization On
  WSGIDaemonProcess placement-api processes=5 threads=1 user=placement group=placement display-name=%{GROUP} home=/opt/placement python-home=/opt/placement/venv python-path=/opt/placement/venv/lib/python3.9/site-packages
  WSGIScriptAlias / /usr/bin/placement-api
  <IfVersion >= 2.4>
    ErrorLogFormat "%M"
  </IfVersion>
  ErrorLog /var/log/placement/placement-api.log
  #SSLEngine On
  #SSLCertificateFile ...
  #SSLCertificateKeyFile ...
    <Directory /usr/bin>
    <IfVersion >= 2.4>
      Require all granted
    </IfVersion>
    <IfVersion < 2.4>
      Order allow,deny
      Allow from all
    </IfVersion>
  </Directory>
  <Directory /opt/keystone/venv/bin>
    <IfVersion >= 2.4>
      Require all granted
    </IfVersion>
    <IfVersion < 2.4>
      Order allow,deny
      Allow from all
    </IfVersion>
  </Directory>
</VirtualHost>

Alias /placement-api /opt/keystone/venv/bin/placement-api
<Location /placement-api>
  SetHandler wsgi-script
  Options +ExecCGI
  WSGIProcessGroup placement-api
  WSGIApplicationGroup %{GLOBAL}
  WSGIPassAuthorization On
</Location>

EOF

# 验证
# curl http://controller:8778
# placement-status upgrade check

## Nova 
RUN getent group nova >/dev/null || groupadd -r nova  \
    && ! getent passwd nova >/dev/null && \
    useradd -r -g nova -G nova,nobody -d /var/lib/nova -s /sbin/nologin -c "OpenStack Nova Daemons" nova

RUN dnf install novnc libvirt* -y

RUN git clone https://opendev.org/openstack/nova.git /opt/nova && git config --global --add safe.directory /opt/nova && cd /opt/nova/ \
    && git checkout -b stable/2023.2 remotes/origin/stable/2023.2

RUN mkdir -p /var/log/nova/ /etc/nova/ /var/lib/nova \
    chown -R nova:nova /var/log/nova/ /etc/nova/ /opt/nova/ /var/lib/nova

RUN cp -r\
    /opt/nova/etc/nova/api-paste.ini \
    /opt/nova/etc/nova/rootwrap.conf \
    /opt/nova/etc/nova/rootwrap.d \
    /etc/nova/
RUN python -m venv /opt/nova/venv && source /opt/nova/venv/bin/activate \
    &&  pip install -r requirements.txt && pip install python-memcached pymysql SQLAlchemy==1.4.52 \
    && python /opt/nova/setup.py install && deactivate && cp /opt/nova/venv/bin/nova-* /usr/bin/

RUN usermod -aG libvirt nova

RUN mysql -e "\
    CREATE DATABASE nova_api; \
    CREATE DATABASE nova; \
    CREATE DATABASE nova_cell0; \
    GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'localhost' IDENTIFIED BY 'nova'; \
    GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'%' IDENTIFIED BY 'nova'; \
    GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY 'nova'; \
    GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY 'nova'; \
    GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'localhost' IDENTIFIED BY 'nova'; \
    GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'%' IDENTIFIED BY 'nova';"

RUN source ~/.admin-openrc && openstack user create --domain default --password "nova" nova \
    && openstack role add --project service --user nova admin \
    && openstack service create --name nova --description "OpenStack Compute" compute \
    && openstack endpoint create --region RegionOne compute public http://${HOSTNAME}:8774/v2.1 \
    && openstack endpoint create --region RegionOne compute internal http://$HOSTNAME:8774/v2.1 \
    && openstack endpoint create --region RegionOne compute admin http://$HOSTNAME:8774/v2.1

RUN HOST_IP=$(ip a show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1)
RUN tee /etc/nova/nova.conf > /dev/null <<EOF
[DEFAULT]
enabled_apis = osapi_compute,metadata
transport_url = rabbit://openstack:openstack@127.0.0.1:5672/
my_ip = $HOST_IP
use_neutron = true
firewall_driver = nova.virt.firewall.NoopFirewallDriver
compute_driver=libvirt.LibvirtDriver
instances_path = /var/lib/nova/instances/
lock_path = /var/lib/nova/tmp
log_dir = /var/log/nova/

[api_database]
connection = mysql+pymysql://nova:nova@127.0.0.1/nova_api

[database]
connection = mysql+pymysql://nova:nova@127.0.0.1/nova

[api]
auth_strategy = keystone

[keystone_authtoken]
www_authenticate_uri = http://127.0.0.1:5000/
auth_url = http://127.0.0.1:5000/
memcached_servers = 127.0.0.1:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = nova
password = nova

[vnc]
enabled = true
server_listen = \$my_ip
server_proxyclient_address = \$my_ip
novncproxy_base_url = http://$my_ip:6080/vnc_auto.html

[libvirt]
virt_type = qemu
# cpu_mode = custom
# cpu_model = cortex-a72

[glance]
api_servers = http://127.0.0.1:9292

[oslo_concurrency]
lock_path = /var/lib/nova/tmp

[placement]
region_name = RegionOne
project_domain_name = Default
project_name = service
auth_type = password
user_domain_name = Default
auth_url = http://127.0.0.1:5000/v3
username = placement
password = placement

[neutron]
auth_url = http://127.0.0.1:5000
auth_type = password
project_domain_name = default
user_domain_name = default
region_name = RegionOne
project_name = service
username = neutron
password = neutron
service_metadata_proxy = true
metadata_proxy_shared_secret = METADATA_SECRET

EOF

RUN su -s /bin/sh -c "nova-manage api_db sync" nova && \
    su -s /bin/sh -c "nova-manage cell_v2 map_cell0" nova && \
    su -s /bin/sh -c "nova-manage cell_v2 create_cell --name=cell1 --verbose" nova && \
    su -s /bin/sh -c "nova-manage db sync" nova && \
    su -s /bin/sh -c "nova-manage cell_v2 list_cells" nova && \
    su -s /bin/sh -c "nova-manage cell_v2 discover_hosts --verbose" nova



COPY ../init.d/nova-api \ 
    ../init.d/nova-compute \
    ../init.d/nova-scheduler \
    ../init.d/nova-conductor \
    .././init.d/nova-novncproxy \
    /etc/init.d/

RUN chmod +x /etc/init.d/nova-api \
    /etc/init.d/nova-compute \
    /etc/init.d/nova-scheduler \
    /etc/init.d/nova-conductor \
    /etc/init.d/nova-novncproxy

## Neutron 部署
RUN getent group neutron >/dev/null || groupadd -r neutron  \
    && ! getent passwd neutron >/dev/null && \
    useradd -r -g neutron -G nova,nobody -d /var/lib/neutron -s /sbin/nologin -c "OpenStack Neutron Daemons" neutron

RUN git clone https://opendev.org/openstack/neutron.git /opt/neutron && git config --global --add safe.directory /opt/neutron && cd /opt/neutron/ \
    && git checkout -b stable/2023.2 remotes/origin/stable/2023.2

RUN mkdir -p /var/lib/neutron/ /var/log/neutron /etc/neutron && chown -R neutron:neutron /var/lib/neutron/ /var/log/neutron /etc/neutron /opt/neutron

RUN python -m venv /opt/neutron/venv && source /opt/neutron/venv/bin/activate \
    &&  pip install -r requirements.txt && pip install python-memcached pymysql SQLAlchemy==1.4.52 \
    && python /opt/neutron/setup.py install && deactivate && cp /opt/neutron/venv/bin/neutron-* /usr/bin/

RUN mysql -e "\
    CREATE DATABASE neutron; \
    GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY 'neutron'; \
    GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY 'neutron';"

RUN source ~/.admin-openrc \
    openstack user create --domain default --password "neutron" neutron \
    openstack role add --project service --user neutron admin \
    openstack service create --name neutron --description "OpenStack Networking" network \
    openstack endpoint create --region RegionOne network public http://${HOSTNAME}:9696 \
    openstack endpoint create --region RegionOne network internal http://${HOSTNAME}:9696 \
    openstack endpoint create --region RegionOne network admin http://${HOSTNAME}:9696 
    
RUN  dnf install ebtables ipset -y

RUN tee /etc/neutron/neutron.conf > /dev/null <<EOF

[DEFAULT]
core_plugin = ml2
service_plugins = router
allow_overlapping_ips = true
transport_url = rabbit://openstack:openstack@127.0.0.1
auth_strategy = keystone
notify_nova_on_port_status_changes = true
notify_nova_on_port_data_changes = true
api_workers = 3  

[database]
connection = mysql+pymysql://neutron:neutron@127.0.0.1/neutron

[keystone_authtoken]
www_authenticate_uri = http://127.0.0.1:5000
auth_url = http://127.0.0.1:5000
memcached_servers = 127.0.0.1:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = neutron
password = neutron

[nova]
auth_url = http://127.0.0.1:5000
auth_type = password
project_domain_name = Default
user_domain_name = Default
region_name = RegionOne
project_name = service
username = nova
password = nova

[oslo_concurrency]
lock_path = /var/lib/neutron/tmp

[experimental]
linuxbridge = true

EOF

RUN tee /etc/neutron/plugins/ml2/ml2_conf.ini > /dev/null <<EOF
[ml2]
type_drivers = flat,vlan,vxlan
tenant_network_types = vxlan
mechanism_drivers = linuxbridge,l2population
extension_drivers = port_security

[ml2_type_flat]
flat_networks = provider

[ml2_type_vxlan]
vni_ranges = 1:1000

[securitygroup]
enable_ipset = true

EOF

RUN ln -s /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini

RUN tee /etc/neutron/plugins/ml2/linuxbridge_agent.ini  > /dev/null <<EOF

[linux_bridge]
physical_interface_mappings = provider:PROVIDER_INTERFACE_NAME

[vxlan]
enable_vxlan = true
local_ip = OVERLAY_INTERFACE_IP_ADDRESS
l2_population = true

[securitygroup]
enable_security_group = true
firewall_driver = neutron.agent.linux.iptables_firewall.IptablesFirewallDriver

EOF

RUN tee /etc/neutron/l3_agent.ini  > /dev/null <<EOF

[DEFAULT]
interface_driver = linuxbridge
EOF

RUN tee /etc/neutron/dhcp_agent.ini  > /dev/null <<EOF

[DEFAULT]
interface_driver = linuxbridge
dhcp_driver = neutron.agent.linux.dhcp.Dnsmasq
enable_isolated_metadata = true
EOF

RUN tee  /etc/neutron/metadata_agent.ini  > /dev/null <<EOF
[DEFAULT]
nova_metadata_host = controller
metadata_proxy_shared_secret = METADATA_SECRET
EOF


RUN su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron


## Cinder
RUN getent group cinder >/dev/null || groupadd -r cinder  \
    && ! getent passwd cinder >/dev/null && \
    useradd -r -g cinder -G nova,nobody -d /var/lib/cinder -s /sbin/nologin -c "OpenStack Cinder Daemons" cinder

RUN dnf install lvm2 scsi-target-utils rpcbind nfs-utils


RUN git clone https://opendev.org/openstack/cinder.git /opt/cinder && git config --global --add safe.directory /opt/cinder && cd /opt/cinder/ \
    && git checkout -b stable/2023.2 remotes/origin/stable/2023.2

RUN mkdir -p /var/log/cinder/ /var/lib/cinder /etc/cinder && chown -R cinder:cinder /var/log/cinder/ /var/lib/cinder /etc/cinder /opt/cinder

RUN mysql -e "\
    CREATE DATABASE cinder; \
    GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'localhost' IDENTIFIED BY 'cinder'; \
    GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'%' IDENTIFIED BY 'cinder';"


RUN source ~/.admin-openrc \
    openstack user create --domain default --password "cinder" cinder \
    openstack role add --project service --user cinder admin \
    openstack service create --name cinderv2 --description "OpenStack Block Storage" volumev2 \
    openstack service create --name cinderv3 --description "OpenStack Block Storage" volumev3 \
    openstack endpoint create --region RegionOne volumev2 public http://${HOSTNAME}:8776/v2/%\(project_id\)s \
    openstack endpoint create --region RegionOne volumev2 internal http://${HOSTNAME}:8776/v2/%\(project_id\)s \
    openstack endpoint create --region RegionOne volumev2 admin http://${HOSTNAME}:8776/v2/%\(project_id\)s \
    openstack endpoint create --region RegionOne volumev3 public http://${HOSTNAME}:8776/v3/%\(project_id\)s \
    openstack endpoint create --region RegionOne volumev3 internal http://${HOSTNAME}:8776/v3/%\(project_id\)s \
    openstack endpoint create --region RegionOne volumev3 admin http://${HOSTNAME}:8776/v3/%\(project_id\)s

# TODO 存储设备配置
RUN tee /etc/cinder/cinder.conf > /dev/null <<EOF

[DEFAULT]
transport_url = rabbit://openstack:openstack@${HOSTNAME}
auth_strategy = keystone
my_ip = ${HOST_IP}
enabled_backends = lvm
backup_driver=cinder.backup.drivers.nfs.NFSBackupDriver
backup_share=controller:/data/cinder/backup

osapi_volume_workers = 3

[database]
connection = mysql+pymysql://cinder:cinder@${HOSTNAME}/cinder

[keystone_authtoken]
www_authenticate_uri = http://${HOSTNAME}:5000
auth_url = http://${HOSTNAME}:5000
memcached_servers = ${HOSTNAME}:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = cinder
password = cinder

[oslo_concurrency]
lock_path = /var/lib/cinder/tmp

[lvm]
volume_driver = cinder.volume.drivers.lvm.LVMVolumeDriver
volume_group = cinder-volumes
iscsi_protocol = iscsi
iscsi_helper = tgtadm

EOF

RUN su -s /bin/sh -c "cinder-manage db sync" cinder

