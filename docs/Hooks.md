## Pre-Hooks and Post-Hooks

The Pre- and Post-Hooks of [acme.sh](https://github.com/acmesh-official/acme.sh/) are available through the corresponding environment variables. This allows to trigger actions just before and after certificates are issued (see  [acme.sh documentation](https://github.com/acmesh-official/acme.sh/wiki/Using-pre-hook-post-hook-renew-hook-reloadcmd))

#### Pre-Hook
This command will be run before certificates are issued. For example `echo 'start'`:
```shell
$ docker run --detach \
    --name nginx-proxy-acme \
    --volumes-from nginx-proxy \
    --volume /var/run/docker.sock:/var/run/docker.sock:ro \
    --volume acme:/etc/acme.sh \
    --env "DEFAULT_EMAIL=mail@yourdomain.tld" \
    --env "ACME_PRE_HOOK=echo 'start'"
    nginxproxy/acme-companion
```

#### Post-Hook
This command will be run after certificates are issued. For example `echo 'end'`:
```shell
$ docker run --detach \
    --name nginx-proxy-acme \
    --volumes-from nginx-proxy \
    --volume /var/run/docker.sock:/var/run/docker.sock:ro \
    --volume acme:/etc/acme.sh \
    --env "DEFAULT_EMAIL=mail@yourdomain.tld" \
    --env "ACME_POST_HOOK=echo 'end'"
    nginxproxy/acme-companion
```

#### Verification:
If you want to check wether the hook-command is delivered properly to [acme.sh](https://github.com/acmesh-official/acme.sh/), you should check `/etc/acme.sh/[EMAILADDRESS]/[DOMAIN]/[DOMAIN].conf`.
The variable `Le_PreHook` contains the Pre-Hook-Command base64 encoded.
The variable `Le_PostHook` contains the Pre-Hook-Command base64 encoded.

#### Limitations
* The commands that can be used in the hooks are limited to the commands available inside the **acme-companion** container. `curl` and `wget` are available, therefore it is possible to communicate with tools outside the container via HTTP, allowing for complex actions to be implemented outside or in other containers.
* The hooks are general options, therefore **the actions for all certificates are the same**.

#### Use-cases
* Change some firewall rules just for the issuing process of the certificates, so the ports 80 and/or 443 don't have to be publicly reachable at all time.
* Monitoring.