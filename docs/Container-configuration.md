## Optional container environment variables for custom configuration.

* `ACME_CA_URI` - Directory URI for the CA ACME API endpoint (defaults to ``https://acme-v02.api.letsencrypt.org/directory``).

If you set this environment variable value to `https://acme-staging-v02.api.letsencrypt.org/directory` the container will obtain its certificates from Let's Encrypt test API endpoint that don't have the [5 certs/week/domain limit](https://letsencrypt.org/docs/rate-limits/) (but are not trusted by browsers).

For example

```bash
$ docker run --detach \
    --name nginx-proxy-acme \
    --volumes-from nginx-proxy \
    --volume /var/run/docker.sock:/var/run/docker.sock:ro \
    --volume certs:/etc/nginx/certs:rw \
    --volume acme:/etc/acme.sh \
    --env "ACME_CA_URI=https://acme-staging-v02.api.letsencrypt.org/directory" \
    nginxproxy/acme-companion
```
You can also create test certificates per container (see [Test certificates](./Let's-Encrypt-and-ACME.md#test-certificates))

* `DEBUG` - Set it to `1` to enable debugging of the entrypoint script and generation of LetsEncrypt certificates, which could help you pin point any configuration issues.

* `RENEW_PRIVATE_KEYS` - Set it to `false` to make `acme.sh` reuse previously generated private key for each certificate instead of creating a new one on certificate renewal. Reusing private keys can help if you intend to use [HPKP](https://developer.mozilla.org/en-US/docs/Web/HTTP/Public_Key_Pinning), but please note that HPKP has been deprecated by Google's Chrome and that it is therefore strongly discouraged to use it at all.

* `DHPARAM_BITS` - Change the key size of the RFC7919 Diffie-Hellman group used by the container from the default value of 4096 bits. Supported values are `2048`, `3072` and `4096`. The DH group file will be located in the container at `/etc/nginx/certs/dhparam.pem`. Mounting a different `dhparam.pem` file at that location will override the RFC7919 group creation by the acme-companion container. **COMPATIBILITY WARNING**: some older clients (like Java 6 and 7) do not support DH keys with over 1024 bits. In order to support these clients, you must provide your own `dhparam.pem`.

* `DHPARAM_SKIP` - Set it to `true` to disable the Diffie-Hellman group creation by the container entirely.

* `CA_BUNDLE` - This is a test only variable [for use with Pebble](https://github.com/letsencrypt/pebble#avoiding-client-https-errors). It changes the trusted root CA used by `acme.sh`, from the default Alpine trust store to the CA bundle file located at the provided path (inside the container). Do **not** use it in production unless you are running your own ACME CA.

* `CERTS_UPDATE_INTERVAL` - 3600 seconds by default, this defines how often the container will check if the certificates require update.

* `ACME_PRE_HOOK` - The provided command will be run before every certificate issuance. The action is limited to the commands available inside the **acme-companion** container. For example `--env "ACME_PRE_HOOK=echo 'start'"`. For more information see [Pre- and Post-Hook](./Hooks.md)

* `ACME_POST_HOOK` - The provided command will be run after every certificate issuance. The action is limited to the commands available inside the **acme-companion** container. For example `--env "ACME_POST_HOOK=echo 'end'"`. For more information see [Pre- and Post-Hook](./Hooks.md)

* `DEFAULT_RENEW` - 60 days by default, this defines the number of days between certificate renewals attempts. For certificates issued by certain Certificate Authorities, such as Buypass, which have a lifespan of 180 days, it may be advisable to initiate the renewal process on day 170 rather than the default day 60. See [BuyPass.com CA](https://github.com/acmesh-official/acme.sh/wiki/BuyPass.com-CA) for more detail.

* `ACME_HTTP_CHALLENGE_LOCATION` - Previously **acme-companion** automatically added the ACME HTTP challenge location to the nginx configuration through files generated in `/etc/nginx/vhost.d`. Recent versions of **nginx-proxy** (>= `1.6`) already include the required location configuration, which remove the need for **acme-companion** to attempt to dynamically add them. If you're running and older version of **nginx-proxy** (or **docker-gen** with an older version of the `nginx.tmpl` file), you can re-enable this behaviour by setting `ACME_HTTP_CHALLENGE_LOCATION` to `true`.

* `RELOAD_NGINX_ONLY_ONCE` - The companion reload nginx configuration after every new or renewed certificate. Previously this was done only once per service loop, at the end of the loop (this was causing delayed availability of HTTPS enabled application when multiple new certificates where requested at once, see [issue #1147](https://github.com/nginx-proxy/acme-companion/issues/1147)). You can restore the previous behaviour if needed by setting the environment variable `RELOAD_NGINX_ONLY_ONCE` to `true`.

* `INCLUDE_STOPPED` - Whether to include stopped containers when generating certificates. Useful for when the **nginx-proxy** container might need to serve a valid page for offline containers.