## Pre-Hooks and Post-Hooks

The Pre- and Post-Hooks of [acme.sh](https://github.com/acmesh-official/acme.sh/) are available through the corresponding environment variables. This allows to trigger actions just before and after certificates are issued (see [acme.sh documentation](https://github.com/acmesh-official/acme.sh/wiki/Using-pre-hook-post-hook-renew-hook-reloadcmd)).

If you set `ACME_PRE_HOOK` and/or `ACME_POST_HOOK` on the **acme-companion** container, **the actions for all certificates will be the same**. If you want specific actions to be run for specific certificates, set the `ACME_PRE_HOOK` / `ACME_POST_HOOK` environment variable(s) on the proxied container(s) instead. Default (on the **acme-companion** container) and per-container `ACME_PRE_HOOK` / `ACME_POST_HOOK` environment variables aren't combined : if both default and per-container variables are set for a given proxied container, the per-container variables will take precedence over the default.

If you want to run the same default hooks for most containers but not for some of them, you can set the `ACME_PRE_HOOK` / `ACME_POST_HOOK` environment variables to the Bash noop operator (ie, `ACME_PRE_HOOK=:`) on those containers.

#### Pre-Hook: `ACME_PRE_HOOK`
This command will be run before certificates are issued.

For example `echo 'start'` on the **acme-companion** container (setting a default Pre-Hook):
```shell
$ docker run --detach \
    --name nginx-proxy-acme \
    --volumes-from nginx-proxy \
    --volume /var/run/docker.sock:/var/run/docker.sock:ro \
    --volume acme:/etc/acme.sh \
    --env "DEFAULT_EMAIL=mail@yourdomain.tld" \
    --env "ACME_PRE_HOOK=echo 'start'" \
    nginxproxy/acme-companion
```

And on a proxied container (setting a per-container Pre-Hook):
```shell
$ docker run --detach \
    --name your-proxyed-app \
    --env "VIRTUAL_HOST=yourdomain.tld" \
    --env "LETSENCRYPT_HOST=yourdomain.tld" \
    --env "ACME_PRE_HOOK=echo 'start'" \
    nginx
```

#### Post-Hook: `ACME_POST_HOOK`
This command will be run after certificates are issued.

For example `echo 'end'` on the **acme-companion** container (setting a default Post-Hook):
```shell
$ docker run --detach \
    --name nginx-proxy-acme \
    --volumes-from nginx-proxy \
    --volume /var/run/docker.sock:/var/run/docker.sock:ro \
    --volume acme:/etc/acme.sh \
    --env "DEFAULT_EMAIL=mail@yourdomain.tld" \
    --env "ACME_POST_HOOK=echo 'end'" \
    nginxproxy/acme-companion
```

And on a proxied container (setting a per-container Post-Hook):
```shell
$ docker run --detach \
    --name your-proxyed-app \
    --env "VIRTUAL_HOST=yourdomain.tld" \
    --env "LETSENCRYPT_HOST=yourdomain.tld" \
    --env "ACME_POST_HOOK=echo 'start'" \
    nginx
```

#### Verification:
If you want to check wether the hook-command is delivered properly to [acme.sh](https://github.com/acmesh-official/acme.sh/), you should check `/etc/acme.sh/[EMAILADDRESS]/[DOMAIN]/[DOMAIN].conf`.
The variable `Le_PreHook` contains the Pre-Hook-Command base64 encoded.
The variable `Le_PostHook` contains the Pre-Hook-Command base64 encoded.

#### Limitations
* The commands that can be used in the hooks are limited to the commands available inside the **acme-companion** container. `curl` and `wget` are available, therefore it is possible to communicate with tools outside the container via HTTP, allowing for complex actions to be implemented outside or in other containers.

#### Use-cases
* Changing some firewall rules just for the ACME authorization, so the ports 80 and/or 443 don't have to be publicly reachable at all time.
* Certificate "post processing" / conversion to another format.
* Monitoring.