![Tests](https://github.com/nginx-proxy/acme-companion/workflows/Tests/badge.svg)
[![GitHub release](https://img.shields.io/github/release/nginx-proxy/acme-companion.svg)](https://github.com/nginx-proxy/acme-companion/releases)
[![Docker Image Size](https://img.shields.io/docker/image-size/nginxproxy/acme-companion?sort=semver)](https://hub.docker.com/r/nginxproxy/acme-companion "Click to view the image on Docker Hub")
[![Docker stars](https://img.shields.io/docker/stars/nginxproxy/acme-companion.svg)](https://hub.docker.com/r/nginxproxy/acme-companion "Click to view the image on Docker Hub")
[![Docker pulls](https://img.shields.io/docker/pulls/nginxproxy/acme-companion.svg)](https://hub.docker.com/r/nginxproxy/acme-companion "Click to view the image on Docker Hub")

**acme-companion** is a lightweight companion container for [**nginx-proxy**](https://github.com/nginx-proxy/nginx-proxy).

It handles the automated creation, renewal and use of SSL certificates for proxied Docker containers through the ACME protocol.

**Required read if you use the `latest` version** : the `v2.0.0` release of this project mark the switch of the ACME client used by the Docker image from [**simp.le**](https://github.com/zenhack/simp_le) to [**acme.sh**](https://github.com/acmesh-official/acme.sh). This switch result in some backward incompatible changes, so please read [this issue](https://github.com/nginx-proxy/acme-companion/issues/510) and the updated docs for more details before updating your image. The single most important change is that the container now requires a volume mounted to `/etc/acme.sh` in order to persist ACME account keys and SSL certificates. The last tagged version that uses **simp_le** is `v1.13.1`.

### Features:
* Automated creation/renewal of Let's Encrypt (or other ACME CAs) certificates using [**acme.sh**](https://github.com/acmesh-official/acme.sh).
* Let's Encrypt / ACME domain validation through `http-01` challenge only.
* Automated update and reload of nginx config on certificate creation/renewal.
* Support creation of [Multi-Domain (SAN) Certificates](https://github.com/nginx-proxy/acme-companion/blob/main/docs/Let's-Encrypt-and-ACME.md#multi-domains-certificates).
* Creation of a Strong Diffie-Hellman Group at startup.
* Work with all versions of docker.

### Requirements:
* Your host **must** be publicly reachable on **both** port [`80`](https://letsencrypt.org/docs/allow-port-80/) and [`443`](https://github.com/nginx-proxy/acme-companion/discussions/873#discussioncomment-1410225).
* Check your firewall rules and [**do not attempt to block port `80`**](https://letsencrypt.org/docs/allow-port-80/) as that will prevent `http-01` challenges from completing.
* For the same reason, you can't use nginx-proxy's [`HTTPS_METHOD=nohttp`](https://github.com/nginx-proxy/nginx-proxy#how-ssl-support-works).
* The (sub)domains you want to issue certificates for must correctly resolve to the host.
* Your DNS provider must [answer correctly to CAA record requests](https://letsencrypt.org/docs/caa/).
* If your (sub)domains have AAAA records set, the host must be publicly reachable over IPv6 on port `80` and `443`.

![schema](https://github.com/nginx-proxy/acme-companion/blob/main/schema.png)

## Basic usage (with the nginx-proxy container)

Three writable volumes must be declared on the **nginx-proxy** container so that they can be shared with the **acme-companion** container:

* `/etc/nginx/certs` to store certificates and private keys (readonly for the **nginx-proxy** container).
* `/etc/nginx/vhost.d` to change the configuration of vhosts (required so the CA may access `http-01` challenge files).
* `/usr/share/nginx/html` to write `http-01` challenge files.

Additionally, a fourth volume must be declared on the **acme-companion** container to store `acme.sh` configuration and state: `/etc/acme.sh`.

Please also read the doc about [data persistence](./docs/Persistent-data.md).

Example of use:

### Step 1 - nginx-proxy

Start **nginx-proxy** with the three additional volumes declared:

```shell
$ docker run --detach \
    --name nginx-proxy \
    --publish 80:80 \
    --publish 443:443 \
    --volume certs:/etc/nginx/certs \
    --volume vhost:/etc/nginx/vhost.d \
    --volume html:/usr/share/nginx/html \
    --volume /var/run/docker.sock:/tmp/docker.sock:ro \
    nginxproxy/nginx-proxy
```

Binding the host docker socket (`/var/run/docker.sock`) inside the container to `/tmp/docker.sock` is a requirement of **nginx-proxy**.

### Step 2 - acme-companion

Start the **acme-companion** container, getting the volumes from **nginx-proxy** with `--volumes-from`:

```shell
$ docker run --detach \
    --name nginx-proxy-acme \
    --volumes-from nginx-proxy \
    --volume /var/run/docker.sock:/var/run/docker.sock:ro \
    --volume acme:/etc/acme.sh \
    --env "DEFAULT_EMAIL=mail@yourdomain.tld" \
    nginxproxy/acme-companion
```

The host docker socket has to be bound inside this container too, this time to `/var/run/docker.sock`.

Albeit **optional**, it is **recommended** to provide a valid default email address through the `DEFAULT_EMAIL` environment variable, so that Let's Encrypt can warn you about expiring certificates and allow you to recover your account.

### Step 3 - proxied container(s)

Once both **nginx-proxy** and **acme-companion** containers are up and running, start any container you want proxied with environment variables `VIRTUAL_HOST` and `LETSENCRYPT_HOST` both set to the domain(s) your proxied container is going to use.

[`VIRTUAL_HOST`](https://github.com/nginx-proxy/nginx-proxy#usage) control proxying by **nginx-proxy** and `LETSENCRYPT_HOST` control certificate creation and SSL enabling by **acme-companion**.

Certificates will only be issued for containers that have both `VIRTUAL_HOST` and `LETSENCRYPT_HOST` variables set to domain(s) that correctly resolve to the host, provided the host is publicly reachable.

```shell
$ docker run --detach \
    --name your-proxied-app \
    --env "VIRTUAL_HOST=subdomain.yourdomain.tld" \
    --env "LETSENCRYPT_HOST=subdomain.yourdomain.tld" \
    nginx
```

The containers being proxied must expose the port to be proxied, either by using the `EXPOSE` directive in their Dockerfile or by using the `--expose` flag to `docker run` or `docker create`.

If the proxied container listen on and expose another port than the default `80`, you can force **nginx-proxy** to use this port with the [`VIRTUAL_PORT`](https://github.com/nginx-proxy/nginx-proxy#multiple-ports) environment variable.

Example using [Grafana](https://hub.docker.com/r/grafana/grafana/) (expose and listen on port 3000):

```shell
$ docker run --detach \
    --name grafana \
    --env "VIRTUAL_HOST=othersubdomain.yourdomain.tld" \
    --env "VIRTUAL_PORT=3000" \
    --env "LETSENCRYPT_HOST=othersubdomain.yourdomain.tld" \
    --env "LETSENCRYPT_EMAIL=mail@yourdomain.tld" \
    grafana/grafana
```

Repeat [Step 3](#step-3---proxied-containers) for any other container you want to proxy.

## Additional documentation

Please check the [docs section](https://github.com/nginx-proxy/acme-companion/tree/main/docs).
