## Usage with Docker Compose

As stated by its repository, [Docker Compose](https://github.com/docker/compose) is a tool for defining and running multi-container Docker applications using a single _Compose file_. This Wiki page is not meant to be a definitive reference on how to run **nginx-proxy** and **letsencrypt-nginx-proxy-companion** with Docker Compose, as the number of possible setups is quite extensive and they can't be all covered.

### Before your start

Be sure to be familiar with both the [basic](./Basic-usage.md) and [avanced](./Advanced-usage.md) non compose setups, and Docker Compose usage.

Please read [getting container IDs](./Getting-containers-IDs.md) and be aware that the `--volumes-from method` is **only** available on compose file version 2.

The following examples are minimal, clean starting points using compose file version 2. Again they are not intended as a definitive reference.

The use of named containers and volume is not required but helps keeping everything clear and organized.

### Two containers example

```yaml
version: '2'

services:
  nginx-proxy:
    image: jwilder/nginx-proxy
    container_name: nginx-proxy
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - conf:/etc/nginx/conf.d
      - vhost:/etc/nginx/vhost.d
      - html:/usr/share/nginx/html
      - dhparam:/etc/nginx/dhparam
      - certs:/etc/nginx/certs:ro
      - /var/run/docker.sock:/tmp/docker.sock:ro
    network_mode: bridge

  letsencrypt:
    image: jrcs/letsencrypt-nginx-proxy-companion
    container_name: nginx-proxy-le
    volumes_from:
      - nginx-proxy
    volumes:
      - certs:/etc/nginx/certs:rw
      - /var/run/docker.sock:/var/run/docker.sock:ro
    network_mode: bridge

volumes:
  conf:
  vhost:
  html:
  dhparam:
  certs:
```

**Note:** **nginx-proxy** Dockerfile [create a volume for `/etc/nginx/dhparam`](https://github.com/jwilder/nginx-proxy/blob/e80fc0b304bcbcf703d86392394c1a5adb823e3c/Dockerfile#L34), so this compose file include it as a named volume instead of letting it be created anyway as an anonymous volume.

### Three containers example

```yaml
version: '2'

services:
  nginx-proxy:
    image: nginx:alpine
    container_name: nginx-proxy
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - conf:/etc/nginx/conf.d
      - vhost:/etc/nginx/vhost.d
      - html:/usr/share/nginx/html
      - certs:/etc/nginx/certs:ro
    network_mode: bridge

  docker-gen:
    image: jwilder/docker-gen
    container_name: nginx-proxy-gen
    command: -notify-sighup nginx-proxy -watch /etc/docker-gen/templates/nginx.tmpl /etc/nginx/conf.d/default.conf
    volumes_from:
      - nginx-proxy
    volumes:
      - /path/to/nginx.tmpl:/etc/docker-gen/templates/nginx.tmpl:ro
      - /var/run/docker.sock:/tmp/docker.sock:ro
    labels:
      - "com.github.jrcs.letsencrypt_nginx_proxy_companion.docker_gen"
    network_mode: bridge

  letsencrypt:
    image: jrcs/letsencrypt-nginx-proxy-companion
    container_name: nginx-proxy-le
    volumes_from:
      - nginx-proxy
    volumes:
      - certs:/etc/nginx/certs:rw
      - /var/run/docker.sock:/var/run/docker.sock:ro
    network_mode: bridge

volumes:
  conf:
  vhost:
  html:
  certs:
```

**Note:** don't forget to replace `/path/to/nginx.tmpl` with the actual path to the [`nginx.tmpl`](https://raw.githubusercontent.com/jwilder/nginx-proxy/master/nginx.tmpl) file you downloaded.

### Other (external) examples

If you want other examples how to use this container with Docker Compose, look at:

* [Nicolas Duchon's Examples](https://github.com/buchdag/letsencrypt-nginx-proxy-companion-compose) - with automated testing
* [Evert Ramos's Examples](https://github.com/evertramos/docker-compose-letsencrypt-nginx-proxy-companion) - using docker-compose version '3'
* [Karl Fathi's Examples](https://github.com/fatk/docker-letsencrypt-nginx-proxy-companion-examples)
* [More examples from Karl](https://github.com/pixelfordinner/pixelcloud-docker-apps/tree/master/nginx-proxy)
* [George Ilyes' Examples](https://github.com/gilyes/docker-nginx-letsencrypt-sample)
* [Dmitry's simple docker-compose example](https://github.com/dmitrym0/simple-lets-encrypt-docker-compose-sample)
* [Radek's docker-compose jenkins example](https://github.com/dataminelab/docker-jenkins-nginx-letsencrypt)
