## Basic usage (with the nginx-proxy container)

Three writable volumes must be declared on the **nginx-proxy** container so that they can be shared with the **letsencrypt-nginx-proxy-companion** container:

* `/etc/nginx/certs` to store certificates, private keys and ACME account keys (readonly for the **nginx-proxy** container).
* `/etc/nginx/vhost.d` to change the configuration of vhosts (required so the CA may access `http-01` challenge files).
* `/usr/share/nginx/html` to write `http-01` challenge files.

Example of use:

### Step 1 - nginx-proxy

Start **nginx-proxy** with the three additional volumes declared:

```shell
$ docker run --detach \
    --name nginx-proxy \
    --publish 80:80 \
    --publish 443:443 \
    --volume /etc/nginx/certs \
    --volume /etc/nginx/vhost.d \
    --volume /usr/share/nginx/html \
    --volume /var/run/docker.sock:/tmp/docker.sock:ro \
    jwilder/nginx-proxy
```

Binding the host docker socket (`/var/run/docker.sock`) inside the container to `/tmp/docker.sock` is a requirement of **ninx-proxy**.

### Step 2 - letsencrypt-nginx-proxy-companion

Start the **letsencrypt-nginx-proxy-companion** container, getting the volumes from **nginx-proxy** with `--volumes-from`:

```shell
$ docker run --detach \
    --name nginx-proxy-letsencrypt \
    --volumes-from nginx-proxy \
    --volume /var/run/docker.sock:/var/run/docker.sock:ro \
    --env "DEFAULT_EMAIL=mail@yourdomain.tld" \
    jrcs/letsencrypt-nginx-proxy-companion
```

The host docker socket has to be bound inside this container too, this time to `/var/run/docker.sock`.

Albeit **optional**, it is **recommended** to provide a valid default email address through the `DEFAULT_EMAIL` environment variable, so that Let's Encrypt can warn you about expiring certificates and allow you to recover your account.

### Step 3 - proxyed container(s)

Once both **nginx-proxy** and **letsencrypt-nginx-proxy-companion** containers are up and running, start any container you want proxyed with environment variables `VIRTUAL_HOST` and `LETSENCRYPT_HOST` both set to the domain(s) your proxyed container is going to use. Multiple hosts can be separated using commas.

[`VIRTUAL_HOST`](https://github.com/jwilder/nginx-proxy#usage) control proxying by **nginx-proxy** and `LETSENCRYPT_HOST` control certificate creation and SSL enabling by **letsencrypt-nginx-proxy-companion**.

Certificates will only be issued for containers that have both `VIRTUAL_HOST` and `LETSENCRYPT_HOST` variables set to domain(s) that correctly resolve to the host, provided the host is publicly reachable.

```shell
$ docker run --detach \
    --name your-proxyed-app
    --env "VIRTUAL_HOST=subdomain.yourdomain.tld" \
    --env "LETSENCRYPT_HOST=subdomain.yourdomain.tld" \
    nginx
```

The containers being proxied must expose the port to be proxied, either by using the `EXPOSE` directive in their Dockerfile or by using the `--expose` flag to `docker run` or `docker create`.

If the proxyed container listen on and expose another port than the default `80`, you can force **nginx-proxy** to use this port with the [`VIRTUAL_PORT`](https://github.com/jwilder/nginx-proxy#multiple-ports) environment variable.

Example using [Grafana](https://hub.docker.com/r/grafana/grafana/) (expose and listen on port 3000):

```shell
$ docker run --detach \
    --name grafana
    --env "VIRTUAL_HOST=othersubdomain.yourdomain.tld" \
    --env "VIRTUAL_PORT=3000" \
    --env "LETSENCRYPT_HOST=othersubdomain.yourdomain.tld" \
    --env "LETSENCRYPT_EMAIL=mail@yourdomain.tld" \
    grafana/grafana
```

Repeat [Step 3](#step-3---proxyed-containers) for any other container you want to proxy.
