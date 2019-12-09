## Deploy in Swarm
We will deploy nginx-3-companion as 2 or 3 containers (basic vs advanced usage) and an other service "test-app" to demonstrate usage.
You would to create a "reverseproxy" network before hand,and any service that need to be routing by the 3-companions need to be in this network.

## Basic usage
```yaml
version: "3.8"
volumes:
  nginx-certs:
  nginx-vhost:
  public-html:

networks:
  reverseproxy:
    external: true
    name: reverseproxy

services:
  nginx-proxy:
    image: jwilder/nginx-proxy
    volumes:
      - nginx-certs:/etc/nginx/certs
      - nginx-vhost:/etc/nginx/vhost.d
      - public-html:/usr/share/nginx/html
      - /var/run/docker.sock:/tmp/docker.sock:ro
    networks:
      - reverseproxy
    labels:
      - com.github.jrcs.letsencrypt_nginx_proxy_companion.nginx_proxy
    ports:
      - 80:80
      - 443:443
  nginx-proxy-letsencrypt:
    image: jrcs/letsencrypt-nginx-proxy-companion
    environment:
      - EFAULT_EMAIL=mail@yourdomain.tld
    volumes:
      - nginx-certs:/etc/nginx/certs
      - nginx-vhost:/etc/nginx/vhost.d
      - public-html:/usr/share/nginx/html
      - /var/run/docker.sock:/tmp/docker.sock:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
  test-app:
    image: nginxdemos/hello
    deploy:
      replicas: 4
    environment:
      - VIRTUAL_HOST=nom-de-domain.com
      - LETSENCRYPT_HOST=nom-de-domain.com
    networks:
      - reverseproxy
```

## Advanced configuration
```yaml
version: "3.8"
volumes:
  nginx-conf:
  nginx-vhost:
  public-html:
  nginx-certs:
  nginx-tmpl:

networks:
  reverseproxy:
    external: true
    name: reverseproxy

services:
  nginx-proxy:
    image: nginx
    volumes:
      - nginx-conf:/etc/nginx/conf.d
      - nginx-vhost:/etc/nginx/vhost.d
      - public-html:/usr/share/nginx/html
      - nginx-certs:/etc/nginx/certs
    networks:
      - reverseproxy
    labels:
      - com.github.jrcs.letsencrypt_nginx_proxy_companion.nginx_proxy
    ports:
      - 80:80
      - 443:443
  nginx-proxy-gen:
    image: helder/docker-gen
    command: -notify "docker-label-sighup com.github.jrcs.letsencrypt_nginx_proxy_companion.nginx_proxy" -watch -wait 5s:30s /etc/docker-gen/templates/nginx.tmpl /etc/nginx/conf.d/default.conf
    networks:
      - reverseproxy
    labels:
     - com.github.jrcs.letsencrypt_nginx_proxy_companion.docker_gen
    volumes:
      - nginx-conf:/etc/nginx/conf.d
      - nginx-vhost:/etc/nginx/vhost.d
      - public-html:/usr/share/nginx/html
      - nginx-certs:/etc/nginx/certs
      - nginx-tmpl:/etc/docker-gen/templates
      - /var/run/docker.sock:/tmp/docker.sock:ro
  nginx-proxy-letsencrypt:
    image: jrcs/letsencrypt-nginx-proxy-companion
    environment:
      - DEFAULT_EMAIL=default_email@email.com
    volumes:
      - nginx-conf:/etc/nginx/conf.d
      - nginx-vhost:/etc/nginx/vhost.d
      - public-html:/usr/share/nginx/html
      - nginx-certs:/etc/nginx/certs
      - /var/run/docker.sock:/var/run/docker.sock:ro
  test-app:
    image: nginxdemos/hello
    deploy:
      replicas: 4
    environment:
      - VIRTUAL_HOST=nom-de-domain.com
      - LETSENCRYPT_HOST=nom-de-domain.com
    networks:
      - reverseproxy

```
