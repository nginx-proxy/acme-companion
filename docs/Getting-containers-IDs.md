## Getting nginx-proxy/nginx/docker-gen containers IDs

For **acme-companion** to work properly, it needs to know the ID of the **nginx**/**nginx-proxy** container (in both [two](./Basic-usage.md) and [three](./Advanced-usage.md) containers setups), plus the ID of the **docker-gen** container in a [three container setup](./Advanced-usage.md).

There are three methods to inform the **acme-companion** container of the **nginx**/**nginx-proxy** container ID:

* `label` method: add the label `com.github.jrcs.letsencrypt_nginx_proxy_companion.nginx_proxy` to the **nginx**/**nginx-proxy** container.

* `environment variable` method: assign a fixed name to the **nginx**/**nginx-proxy** container with `container_name:` and set the environment variable `NGINX_PROXY_CONTAINER` to this name on the **acme-companion** container.

* `volumes_from` method. Using this method, the **acme-companion** container will get the **nginx**/**nginx-proxy** container ID from the volumes it got using the `volumes_from` option.

And two methods to inform the **acme-companion** container of the **docker-gen** container ID:

* `label` method: add the label `com.github.jrcs.letsencrypt_nginx_proxy_companion.docker_gen` to the **docker-gen** container.

* `environment variable` method: assign a fixed name to the **docker-gen** container with `container_name:` and set the environment variable `NGINX_DOCKER_GEN_CONTAINER` to this name on the **acme-companion** container.

The methods for each container are sorted by order of precedence, meaning that if you use both the label and the volumes_from method, the ID of the **nginx**/**nginx-proxy** container that will be used will be the one found using the label. **There is no point in using more than one method at a time for either the nginx/nginx-proxy or docker-gen container beside potentially confusing yourself**.

The advantage the `label` methods have over the `environment variable` (and `volumes_from`) methods is enabling the use of the **acme-companion** in environments where containers names are dynamic, like in Swarm Mode or in Docker Cloud. Howhever if you intend to do so, as upstream **docker-gen** lacks the ability to identify containers from labels, you'll need both to either use the two containers setup or to replace nginx-proxy/docker-gen with a fork that has this ability like [herlderco/docker-gen](https://github.com/helderco/docker-gen). Be advised that for now, this works to a very limited extent [(everything has to be on the same node)](https://github.com/nginx-proxy/acme-companion/pull/231#issuecomment-330624331).

#### Examples with three containers setups:

`label` method.
```
$ docker run --detach \
    [...]
    --label com.github.jrcs.letsencrypt_nginx_proxy_companion.nginx_proxy \
    nginx

$ docker run --detach \
    [...]
    --label com.github.jrcs.letsencrypt_nginx_proxy_companion.docker_gen \
    nginxproxy/docker-gen

$ docker run --detach \
    [...]
    nginxproxy/acme-companion
```

`environment variable` method
```
$ docker run --detach \
    [...]
    --name unique-container-name \
    nginx

$ docker run --detach \
    [...]
    --name another-unique-container-name \
    nginxproxy/docker-gen

$ docker run --detach \
    [...]
    --env NGINX_PROXY_CONTAINER=unique-container-name \
    --env NGINX_DOCKER_GEN_CONTAINER=another-unique-container-name \
    nginxproxy/acme-companion
```

`volumes_from` (**nginx**) + `label` (**docker-gen**) method
```
$ docker run --detach \
    [...]
    --name unique-container-name \
    nginx

$ docker run --detach \
    [...]
    --label com.github.jrcs.letsencrypt_nginx_proxy_companion.docker_gen \
    nginxproxy/docker-gen

$ docker run --detach \
    [...]
    --volumes-from unique-container-name \
    nginxproxy/acme-companion
```

`volumes_from` (**nginx**) + `environment variable` (**docker-gen**) method
```
$ docker run --detach \
    [...]
    --name unique-container-name \
    nginx

$ docker run --detach \
    [...]
    --name another-unique-container-name \
    nginxproxy/docker-gen

$ docker run --detach \
    [...]
    --volumes-from unique-container-name \
    --env NGINX_DOCKER_GEN_CONTAINER=another-unique-container-name \
    nginxproxy/acme-companion
```
