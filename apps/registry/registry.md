```dockerfile
version: '3'

services:

  auth:
    image: cesanta/docker_auth:1
    command: --v=2 --alsologtostderr /auth.yaml
    volumes:
      - './files/auth.yaml:/auth.yaml:ro'
      - './files/server.pem:/server.pem:ro'
      - './files/server.key:/server.key:ro'
    ports:
      - '5001:5001'

  registry:
    image: registry:2
    environment:
      - 'REGISTRY_AUTH_TOKEN_REALM=https://192.168.178.125:5001/auth'
      - 'REGISTRY_AUTH_TOKEN_SERVICE=Docker registry'
      - 'REGISTRY_AUTH_TOKEN_ISSUER=www.example.com'
      - 'REGISTRY_AUTH_TOKEN_ROOTCERTBUNDLE=/server.pem'
      - 'REGISTRY_HTTP_TLS_CERTIFICATE=/server.pem'
      - 'REGISTRY_HTTP_TLS_KEY=/server.key'
    volumes:
      - './files/server.pem:/server.pem:ro'
      - './files/server.key:/server.key:ro'
    ports:
      - '5000:5000'

  frontend:
    image: klausmeyer/docker-registry-browser:latest
    environment:
      - 'DOCKER_REGISTRY_URL=https://registry:5000'
      - 'NO_SSL_VERIFICATION=true'
      - 'TOKEN_AUTH_USER=admin'
      - 'TOKEN_AUTH_PASSWORD=badmin'
      - 'SSL_CERT_PATH=/server.pem'
      - 'SSL_KEY_PATH=/server.key'
    volumes:
      - './files/server.pem:/server.pem:ro'
      - './files/server.key:/server.key:ro'
    ports:
      - '8443:8443'
```