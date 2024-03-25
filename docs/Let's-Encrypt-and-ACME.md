## Let's Encrypt / ACME

**NOTE on CAA**: Please ensure that your DNS provider answers correctly to CAA record requests. [If your DNS provider answer with an error, Let's Encrypt won't issue a certificate for your domain](https://letsencrypt.org/docs/caa/). Let's Encrypt do not require that you set a CAA record on your domain, just that your DNS provider answers correctly.

**NOTE on IPv6**: If the domain or sub domain you want to issue certificate for has an AAAA record set, Let's Encrypt will favor challenge validation over IPv6. [There is an IPv6 to IPv4 fallback in place but Let's Encrypt can't guarantee it'll work in every possible case](https://github.com/letsencrypt/boulder/issues/2770#issuecomment-340489871), so bottom line is **if you are not sure of both your host and your host's Docker reachability over IPv6, do not advertise an AAAA record** or LE challenge validation might fail.

As described on [basic usage](./Basic-usage.md), the `LETSENCRYPT_HOST` environment variables needs to be declared in each to-be-proxied application containers for which you want to enable SSL and create certificate. It most likely needs to be the same as the `VIRTUAL_HOST` variable and must resolve to your host (which has to be publicly reachable).

The following environment variables are optional and parametrize the way the Let's Encrypt client works.

### per proxyed container

#### Multi-domains certificates

Specify multiple hosts with a comma delimiter to create multi-domains ([SAN](https://www.digicert.com/subject-alternative-name.htm)) certificates (the first domain in the list will be the base domain).

Example:

```shell
$ docker run --detach \
    --name your-proxyed-app \
    --env "VIRTUAL_HOST=yourdomain.tld,www.yourdomain.tld,anotherdomain.tld" \
    --env "LETSENCRYPT_HOST=yourdomain.tld,www.yourdomain.tld,anotherdomain.tld" \
    nginx
```

Let's Encrypt has a limit of [100 domains per certificate](https://letsencrypt.org/fr/docs/rate-limits/), while Buypass limit is [15 domains per certificate](https://www.buypass.com/ssl/products/go-ssl-campaign).

#### Separate certificate for each domain

The example above will issue a single domain certificate for all the domains listed in the `LETSENCRYPT_HOST` environment variable. If you need to have a separate certificate for each of the domains, you can add set the `LETSENCRYPT_SINGLE_DOMAIN_CERTS` environment variable to `true`.

Example:

```shell
$ docker run --detach \
    --name your-proxyed-app \
    --env "VIRTUAL_HOST=yourdomain.tld,www.yourdomain.tld,anotherdomain.tld" \
    --env "LETSENCRYPT_HOST=yourdomain.tld,www.yourdomain.tld,anotherdomain.tld" \
    --env "LETSENCRYPT_SINGLE_DOMAIN_CERTS=true" \
    nginx
```

#### Automatic certificate renewal
Every hour (3600 seconds) the certificates are checked and per default every certificate that have been issued at least [60 days](https://github.com/acmesh-official/acme.sh/blob/f2d350002e7c387fad9777a42cf9befe34996c35/acme.sh#L61) ago is renewed. For Let's Encrypt certificates, that mean they will be renewed 30 days before expiration.

#### Contact address

The `LETSENCRYPT_EMAIL` environment variable must be a valid email and will be used by Let's Encrypt to warn you of impeding certificate expiration (should the automated renewal fail) and to recover an account.

#### Private key size

The `LETSENCRYPT_KEYSIZE` environment variable determines the type and size of the requested key. Supported values are `2048`, `3072` and `4096` for RSA keys, and `ec-256` or `ec-384` for elliptic curve keys. The default is RSA 4096.  
To change the global default set the `DEFAULT_KEY_SIZE` environment variable on the **acme-companion** container to one of the supported values specified above.

#### OCSP stapling

The `ACME_OCSP` environment variable, when set to `true` on a proxied application container, will add the [OCSP Must-Staple extension](https://blog.apnic.net/2019/01/15/is-the-web-ready-for-ocsp-must-staple/) to the issued certificate. Please read about OCSP Must-Staple support in Nginx if you intend to use this feature (https://trac.nginx.org/nginx/ticket/812 and https://trac.nginx.org/nginx/ticket/1830)

#### Test certificates

The `LETSENCRYPT_TEST` environment variable, when set to `true` on a proxied application container, will create a test certificates that don't have the [5 certs/week/domain limits](https://letsencrypt.org/docs/rate-limits/) and are signed by an untrusted intermediate (they won't be trusted by browsers).

If you want to do this globally for all containers, set `ACME_CA_URI` on the **acme-companion** container as described in [Container configuration](./Container-configuration.md).

#### ACME CA URI

The `ACME_CA_URI` environment variable is used to set the ACME API endpoint from which the container's certificate(s) will be requested (defaults to ``https://acme-v02.api.letsencrypt.org/directory``).

#### Preferred chain

If the ACME CA provides multiple cert chain, you can use the `ACME_PREFERRED_CHAIN` environment variable to select one. See [`acme.sh --preferred-chain` documentation](https://github.com/acmesh-official/acme.sh/wiki/Preferred-Chain) for more info.

#### Container restart on cert renewal

The `LETSENCRYPT_RESTART_CONTAINER` environment variable, when set to `true` on an application container, will restart this container whenever the corresponding cert (`LETSENCRYPT_HOST`) is renewed. This is useful when certificates are directly used inside a container for other purposes than HTTPS (e.g. an FTPS server), to make sure those containers always use an up to date certificate.

#### Pre-Hook and Post-Hook

The `ACME_PRE_HOOK` and `ACME_POST_HOOK` let you use the [`acme.sh` Pre- and Post-Hooks feature](https://github.com/acmesh-official/acme.sh/wiki/Using-pre-hook-post-hook-renew-hook-reloadcmd) to run commands respectively before and after the container's certificate has been issued. For more information see [Pre- and Post-Hook](./Hooks.md)


### global (set on acme-companion container)

#### Default contact address

The `DEFAULT_EMAIL` variable must be a valid email and, when set on the **acme-companion** container, will be used as a fallback when no email address is provided using proxyed container's `LETSENCRYPT_EMAIL` environment variables. It is highly recommended to set this variable to a valid email address that you own.

#### Private key re-utilization

The `RENEW_PRIVATE_KEYS` environment variable, when set to `false` on the **acme-companion** container, will set `acme.sh` to reuse previously generated private key instead of generating a new one at renewal for all domains.

Reusing private keys can help if you intend to use [HPKP](https://developer.mozilla.org/en-US/docs/Web/HTTP/Public_Key_Pinning), but please note that HPKP has been deprecated by Google's Chrome and that it is therefore strongly discouraged to use it at all.

#### ACME accounts handling

- Use one `acme.sh` configuration directory (`--config-home`) per account email address.
- Each `acme.sh` configuration directory can hold several accounts on different ACME service providers. But only one per service provider.
- The `default` configuration directory holds the configuration for empty account email address.
- When in testing mode (`LETSENCRYPT_TEST=true`):
    1. The container will use the special purpose `staging` configuration directory.
    1. The directory URI is forced to The Let's Encrypt v2 staging one (`ACME_CA_URI` is ignored)
    2. The account email address is forced empty (`DEFAULT_EMAIL` and `LETSENCRYPT_EMAIL` are ignored)
