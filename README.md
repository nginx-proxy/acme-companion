[![](https://img.shields.io/badge/dockerhub-master-brightgreen.svg)](https://hub.docker.com/r/jrcs/letsencrypt-nginx-proxy-companion 'Repository on DockerHub')
![License MIT](https://img.shields.io/badge/license-MIT-blue.svg) [![](https://badge.imagelayers.io/jrcs/letsencrypt-nginx-proxy-companion:latest.svg)](https://imagelayers.io/?images=jrcs/letsencrypt-nginx-proxy-companion:latest 'Get your own badge on imagelayers.io')

letsencrypt-nginx-proxy-companion is a lightweight companion container for the [nginx-proxy](https://github.com/jwilder/nginx-proxy). It allow the creation/renewal of Let's Encrypt certificates automatically. See [Let's Encrypt section](#lets-encrypt) for configuration details.

### Features:
* Automatic creation/renewal of Let's Encrypt certificates using original nginx-proxy container.
* Support creation of Multi-Domain ([SAN](https://www.digicert.com/subject-alternative-name.htm)) Certificates.
* Automatically creation of a Strong Diffie-Hellman Group (for having an A+ Rate on the [Qualsys SSL Server Test](https://www.ssllabs.com/ssltest/)).
* Work with all versions of docker.

#### Usage

To use it with original [nginx-proxy](https://github.com/jwilder/nginx-proxy) container you must declare 3 writable volumes from the [nginx-proxy](https://github.com/jwilder/nginx-proxy) container:
* `/etc/nginx/certs` to create/renew Let's Encrypt certificates
* `/etc/nginx/vhost.d` to change the configuration of vhosts (need by Let's Encrypt)
* `/usr/share/nginx/html` to write challenge files.

Example of use:

* First start nginx with the 3 volumes declared:
```bash
$ docker run -d -p 80:80 -p 443:443 \
    --name nginx-proxy \
    -v /path/to/certs:/etc/nginx/certs:ro \
    -v /etc/nginx/vhost.d \
    -v /usr/share/nginx/html \
    -v /var/run/docker.sock:/tmp/docker.sock:ro \
    jwilder/nginx-proxy
```

* Second start this container:
```bash
$ docker run -d \
    -v /path/to/certs:/etc/nginx/certs:rw \
    --volumes-from nginx-proxy \
    -v /var/run/docker.sock:/var/run/docker.sock:ro \
    jrcs/letsencrypt-nginx-proxy-companion
```

Then start any containers you want to proxied with a env var `VIRTUAL_HOST=subdomain.youdomain.com`

    $ docker run -e VIRTUAL_HOST=foo.bar.com ...

The containers being proxied must [expose](https://docs.docker.com/reference/run/#expose-incoming-ports) the port to be proxied, either by using the `EXPOSE` directive in their `Dockerfile` or by using the `--expose` flag to `docker run` or `docker create`. See [nginx-proxy](https://github.com/jwilder/nginx-proxy) for more informations. To generate automatically Let's Encrypt certificates see next section.

#### Let's Encrypt

To use the Let's Encrypt service to automatically create a valid certificate for virtual host(s).

Set the following environment variables to enable Let's Encrypt support for a container being proxied.

- `LETSENCRYPT_HOST`
- `LETSENCRYPT_EMAIL`

The `LETSENCRYPT_HOST` variable most likely needs to be the same as the `VIRTUAL_HOST` variable and must be publicly reachable domains. Specify multiple hosts with a comma delimiter.

For example

```bash
$ docker run -d -p 80:80 \
    -e VIRTUAL_HOST="foo.bar.com,bar.com" \
    -e LETSENCRYPT_HOST="foo.bar.com,bar.com" \
    -e LETSENCRYPT_EMAIL="foo@bar.com" ...
```

#### Optional container environment variables

Optional letsencrypt-nginx-proxy-companion container environment variables for custom configuration.

* `ACME_CA_URI` - Directory URI for the CA ACME API endpoint (default: ``https://acme-v01.api.letsencrypt.org/directory``)

For example

```bash
$ docker run -d \
    -e ACME_CA_URI="https://acme-staging.api.letsencrypt.org/directory" \
    -v /path/to/certs:/etc/nginx/certs:rw \
    --volumes-from nginx-proxy \
    -v /var/run/docker.sock:/var/run/docker.sock:ro \
    jrcs/letsencrypt-nginx-proxy-companion
```

* `DEBUG` - Set it to `true` to enable debugging of the entrypoint script, which could help you pin point any configuration issues.
