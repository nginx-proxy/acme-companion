## Usage with Docker Compose

As stated by its repository, [Docker Compose](https://github.com/docker/compose) is a tool for defining and running multi-container Docker applications using a single _Compose file_. This Wiki page is not meant to be a definitive reference on how to run **nginx-proxy** and **acme-companion** with Docker Compose, as the number of possible setups is quite extensive and they can't be all covered.

### Before your start

Be sure to be familiar with both the [basic](./Basic-usage.md) and [advanced](./Advanced-usage.md) non compose setups, and Docker Compose usage.

The following examples are minimal, clean starting points, not a definitive reference. They follow current Docker Compose conventions:

* The top-level `version:` key is intentionally omitted: it is obsolete in the [Compose Specification](https://docs.docker.com/reference/compose-file/) and ignored by Docker Compose.
* They do not use `volumes_from` (a compose file version 2 only feature): every volume is mounted explicitly on each container instead.
* **acme-companion** finds the **nginx**/**nginx-proxy** (and **docker-gen**) container through the `label` method, see [getting container IDs](./Getting-containers-IDs.md). The `NGINX_PROXY_CONTAINER` / `NGINX_DOCKER_GEN_CONTAINER` environment variable method documented there is an equally valid alternative.

If you still rely on a `volumes_from` based compose file, see [getting container IDs](./Getting-containers-IDs.md) for the `docker run --volumes-from` method (still supported) and this page's git history for the previous examples.

The use of named containers and volumes is not required but helps keeping everything clear and organized.

### Two containers example

```yaml
services:
  nginx-proxy:
    image: nginxproxy/nginx-proxy
    container_name: nginx-proxy
    ports:
      - "80:80"
      - "443:443"
    labels:
      - "com.github.nginx-proxy.nginx"
    volumes:
      - certs:/etc/nginx/certs:ro
      - html:/usr/share/nginx/html
      - /var/run/docker.sock:/tmp/docker.sock:ro
      # The vhost and conf volumes are only required
      # if you plan to obtain standalone certificates
      # - vhost:/etc/nginx/vhost.d
      # - conf:/etc/nginx/conf.d

  acme-companion:
    image: nginxproxy/acme-companion
    container_name: nginx-proxy-acme
    environment:
      - DEFAULT_EMAIL=mail@yourdomain.tld
    volumes:
      - certs:/etc/nginx/certs:rw
      - html:/usr/share/nginx/html:rw
      - acme:/etc/acme.sh
      - /var/run/docker.sock:/var/run/docker.sock:ro
      # The vhost and conf volumes are only required
      # if you plan to obtain standalone certificates
      # - vhost:/etc/nginx/vhost.d
      # - conf:/etc/nginx/conf.d

# A user-defined network is optional; Compose creates a default one per project.
#networks:
#  default:
#    name: nginx-proxy

volumes:
  certs:
  html:
  acme:
  # vhost:
  # conf:
```

### Three containers example

```yaml
services:
  nginx:
    image: nginx:alpine
    container_name: nginx-proxy
    ports:
      - "80:80"
      - "443:443"
    labels:
      - "com.github.nginx-proxy.nginx"
    volumes:
      - conf:/etc/nginx/conf.d:ro
      - html:/usr/share/nginx/html
      - certs:/etc/nginx/certs:ro
      # The vhost volume is only required if you
      # plan to obtain standalone certificates
      # - vhost:/etc/nginx/vhost.d

  docker-gen:
    image: nginxproxy/docker-gen
    container_name: nginx-proxy-gen
    command: -notify-sighup nginx-proxy -watch -wait 5s:30s /etc/docker-gen/templates/nginx.tmpl /etc/nginx/conf.d/default.conf
    labels:
      - "com.github.nginx-proxy.docker-gen"
    volumes:
      - conf:/etc/nginx/conf.d:rw
      - certs:/etc/nginx/certs:ro
      - /path/to/nginx.tmpl:/etc/docker-gen/templates/nginx.tmpl:ro
      - /var/run/docker.sock:/tmp/docker.sock:ro
      # The vhost volume is only required if you
      # plan to obtain standalone certificates
      # - vhost:/etc/nginx/vhost.d

  acme-companion:
    image: nginxproxy/acme-companion
    container_name: nginx-proxy-acme
    environment:
      - DEFAULT_EMAIL=mail@yourdomain.tld
    volumes:
      - certs:/etc/nginx/certs:rw
      - html:/usr/share/nginx/html:rw
      - acme:/etc/acme.sh
      - /var/run/docker.sock:/var/run/docker.sock:ro
      # The vhost and conf volumes are only required
      # if you plan to obtain standalone certificates
      # - vhost:/etc/nginx/vhost.d
      # - conf:/etc/nginx/conf.d

#networks:
#  default:
#    name: nginx-proxy

volumes:
  conf:
  html:
  certs:
  acme:
  # vhost:
```

**Note:** don't forget to replace `/path/to/nginx.tmpl` with the actual path to the [`nginx.tmpl`](https://raw.githubusercontent.com/nginx-proxy/nginx-proxy/main/nginx.tmpl) file you downloaded.

### Health check

The **acme-companion** image ships with a Docker [`HEALTHCHECK`](https://docs.docker.com/reference/dockerfile/#healthcheck) that reports the container as healthy while both of its background services (the certificates service and the bundled docker-gen) are running.

This lets you gate startup on the companion being up, for example with `docker compose up --wait`, or by having another service wait for it:

```yaml
services:
  acme-companion:
    image: nginxproxy/acme-companion
    # ...

  myapp:
    image: myapp
    depends_on:
      acme-companion:
        condition: service_healthy
```

You can override or disable the check per container with the [`healthcheck`](https://docs.docker.com/reference/compose-file/services/#healthcheck) key in your Compose file.

### Other (external) examples

**Warning:** some of those examples might be outdated and not working properly with version >= `2.0` of this project.

If you want other examples how to use this container with Docker Compose, look at:

* [Nicolas Duchon's Examples](https://github.com/buchdag/letsencrypt-nginx-proxy-companion-compose) - with automated testing
* [Evert Ramos's Examples](https://github.com/evertramos/docker-compose-letsencrypt-nginx-proxy-companion) - using docker-compose version '3'
* [Karl Fathi's Examples](https://github.com/fatk/docker-letsencrypt-nginx-proxy-companion-examples)
* [More examples from Karl](https://github.com/pixelfordinner/pixelcloud-docker-apps/tree/master/nginx-proxy)
* [George Ilyes' Examples](https://github.com/gilyes/docker-nginx-letsencrypt-sample)
* [Dmitry's simple docker-compose example](https://github.com/dmitrym0/simple-lets-encrypt-docker-compose-sample)
* [Radek's docker-compose jenkins example](https://github.com/dataminelab/docker-jenkins-nginx-letsencrypt)
