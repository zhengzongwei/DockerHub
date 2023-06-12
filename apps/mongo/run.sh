# 请先在操作系统中创建 /home/mongodb 目录，作为持久化容器内数据的挂载点
# $ mkdir /home/mongodb 
docker run -d -v /home/zhengzongwei/mongodb:/data/db \
  -p 27017:27017 -p 28017:28017 \
  -e MONGODB_USER="dbuser" -e MONGODB_DATABASE="dbuser" \
  -e MONGODB_PASS="dbpassword" --name mongodb mongodb

docker run -d -v /home/zhengzongwei/mongodb:/data/db \
  -p 27017:27017 -p 28017:28017 \
  -e MONGO_INITDB_ROOT_USERNAME="mongo" -e MONGO_INITDB_DATABASE="info" \
  -e MONGO_INITDB_ROOT_PASSWORD="mongo" --name mongodb mongo:6.0.5
