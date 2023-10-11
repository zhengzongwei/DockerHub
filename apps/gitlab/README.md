The latest Docker guide can be found here: [GitLab Docker images](https://docs.gitlab.com/ee/install/docker.html).


```bash
cd gitlab-docker
# 构建 GitLab CE 镜像
docker build . \
   -t gitlab-ce:16.4.1-ce.0 \
   --build-arg RELEASE_PACKAGE=gitlab-ce \
   --build-arg RELEASE_VERSION=16.4.1-ce.0
# 构建 GitLab EE 镜像
docker build . \
   -t gitlab-ee:15.9.0-ee.0 \
   --build-arg RELEASE_PACKAGE=gitlab-ee \
   --build-arg RELEASE_VERSION=15.9.0-ee.0
```