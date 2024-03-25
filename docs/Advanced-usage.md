## Advanced usage (with the nginx and docker-gen containers)

**nginx-proxy** can also be run as two separate containers using the [nginx-proxy/**docker-gen**](https://github.com/nginx-proxy/docker-gen) image and the official [**nginx**](https://hub.docker.com/_/nginx/) image. You may want to do this to prevent having the docker socket bound to a publicly exposed container service (ie avoid mounting the docker socket in the nginx exposed container).

Please read and try [basic usage](./Basic-usage.md), and **validate that you have a working two containers setup** before using the three containers setup. In addition to the steps described there, running **nginx-proxy** as two separate containers with **acme-companion** requires the following:

1) Download and mount the template file [nginx.tmpl](https://github.com/nginx-proxy/nginx-proxy/blob/main/nginx.tmpl) into the **docker-gen** container. You can get the nginx.tmpl file with a command like:

```
curl https://raw.githubusercontent.com/nginx-proxy/nginx-proxy/main/nginx.tmpl > /path/to/nginx.tmpl
```

2) Use the `com.github.nginx-proxy.docker-gen` label on the **docker-gen** container, or explicitly set the `NGINX_DOCKER_GEN_CONTAINER` environment variable on the **acme-companion** container to the name or id of the **docker-gen** container (we'll use the later method in the example).

3) Declare `/etc/nginx/conf.d` as a volume on the nginx container so that it can be shared with the **docker-gen** container.

Example:

### Step 1 - nginx

* Start nginx [(official image)](https://hub.docker.com/_/nginx/) with the required volumes:

```shell
$ docker run --detach \
    --name nginx-proxy \
    --publish 80:80 \
    --publish 443:443 \
    --volume conf:/etc/nginx/conf.d  \
    --volume vhost:/etc/nginx/vhost.d \
    --volume html:/usr/share/nginx/html \
    --volume certs:/etc/nginx/certs \
    nginx
```

### Step 2 - docker-gen

* Start the **docker-gen** container with the shared volumes (with `--volume-from`), the template file and the docker socket:

```shell
$ docker run --detach \
    --name nginx-proxy-gen \
    --volumes-from nginx-proxy \
    --volume /path/to/nginx.tmpl:/etc/docker-gen/templates/nginx.tmpl:ro \
    --volume /var/run/docker.sock:/tmp/docker.sock:ro \
    nginxproxy/docker-gen \
    -notify-sighup nginx-proxy -watch -wait 5s:30s /etc/docker-gen/templates/nginx.tmpl /etc/nginx/conf.d/default.conf
```

Note that you must pass the exact name of the **nginx** container to **docker-gen** `-notify-sighup` argument (here `nginx-proxy`).


### Step 3 - acme-companion

* Start the **acme-companion** container with the `NGINX_DOCKER_GEN_CONTAINER` environment variable correctly set:

```shell
$ docker run --detach \
    --name nginx-proxy-acme \
    --volumes-from nginx-proxy \
    --volume /var/run/docker.sock:/var/run/docker.sock:ro \
    --volume acme:/etc/acme.sh \
    --env "NGINX_DOCKER_GEN_CONTAINER=nginx-proxy-gen" \
    --env "DEFAULT_EMAIL=mail@yourdomain.tld" \
    nginxproxy/acme-companion
```

### Step 4 - proxyed container(s)

* Once the three containers are up, start any containers to be proxied as described in [basic usage](./Basic-usage.md).

```shell
$ docker run --detach \
    --name your-proxyed-app \
    --env "VIRTUAL_HOST=subdomain.yourdomain.tld" \
    --env "LETSENCRYPT_HOST=subdomain.yourdomain.tld" \
    nginx
```

If you are experiencing issues with this setup, fall back to the [basic setup](./Basic-usage.md). The advanced setup is not meant to be obligatory.
