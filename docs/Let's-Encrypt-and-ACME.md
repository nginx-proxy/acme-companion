## Let's Encrypt / ACME

**NOTE on CAA**: Please ensure that your DNS provider answers correctly to CAA record requests. [If your DNS provider answer with an error, Let's Encrypt won't issue a certificate for your domain](https://letsencrypt.org/docs/caa/). Let's Encrypt do not require that you set a CAA record on your domain, just that your DNS provider answers correctly.

**NOTE on IPv6**: If the domain or sub domain you want to issue certificate for has an AAAA record set, Let's Encrypt will favor challenge validation over IPv6. [There is an IPv6 to IPv4 fallback in place but Let's Encrypt can't guarantee it'll work in every possible case](https://github.com/letsencrypt/boulder/issues/2770#issuecomment-340489871), so bottom line is **if you are not sure of both your host and your host's Docker reachability over IPv6, do not advertise an AAAA record** or LE challenge validation might fail.

As described on [basic usage](./Basic-usage.md), the `LETSENCRYPT_HOST` environment variables needs to be declared in each to-be-proxied application containers for which you want to enable SSL and create certificate. It most likely needs to be the same as the `VIRTUAL_HOST` variable and must resolve to your host (which has to be publicly reachable).

Specify multiple hosts with a comma delimiter to create multi-domain ([SAN](https://www.digicert.com/subject-alternative-name.htm)) certificates (the first domain in the list will be the base domain).

The following environment variables are optional and parametrize the way the Let's Encrypt client works.

### per proxyed container

#### Automatic certificate renewal
Every hour (3600 seconds) the certificates are checked and per default every certificate that will expire in the next [30 days](https://github.com/zenhack/simp_le/blob/a8a8013c097910f8f3cce046f1077b41b745673b/simp_le.py#L73) (90 days / 3) is renewed.

The `LETSENCRYPT_MIN_VALIDITY` environment variable can be used to set a different minimum validity (in seconds) for certificates. Note that the possible values are internally capped at an upper bound of 7603200 (88 days) and a lower bound of 7200 (2 hours) as a security margin, considering that the Let's Encrypt CA does only issues certificates with a lifetime of [90 days](https://letsencrypt.org/2015/11/09/why-90-days.html) (upper bound), the rate limits imposed on certificate renewals are [5 per week](https://letsencrypt.org/docs/rate-limits/) (upper bound), and the fact that the certificates are checked and renewed accordingly every hour (lower bound).

#### Contact address

The `LETSENCRYPT_EMAIL` environment variable must be a valid email and will be used by Let's Encrypt to warn you of impeding certificate expiration (should the automated renewal fail) and to recover an account. For reasons detailed below, it is **recommended** to provide a default valid contact address for all containers by setting the [`DEFAULT_EMAIL`](#default-contact-address) environment variable on the **letsencrypt_nginx_proxy_companion container**.

**Please note that for each separate [ACME account](#acme-account-keys), only the email provided as a container environment variable at the time of this account creation will be subsequently used. If you don't provide an email address when the account is created, this account will remain without a contact address even if you provide an address in the future.**

Examples:

```bash
$ docker run -d nginx \
  VIRTUAL_HOST=somedomain.tld \
  LETSENCRYPT_HOST=somedomain.tld \
  LETSENCRYPT_EMAIL=contact@somedomain.tld

$ docker run -d nginx \
  VIRTUAL_HOST=anotherdomain.tld \
  LETSENCRYPT_HOST=anotherdomain.tld \
  LETSENCRYPT_EMAIL=someone@anotherdomain.tld
```

This will result in only the first address being used (contact@somedomain.tld) and it will be used for **all** future certificates issued with the default ACME account.

This incorrect behaviour is due to a misunderstanding about the way ACME handled contact address(es) when the container was changed to re-use ACME account keys ([more info there](https://github.com/JrCs/docker-letsencrypt-nginx-proxy-companion/issues/510#issuecomment-463256716)) and the fact that `simp_le` is silently discarding the unused addresses. Due to this, it is highly recommended to use the [`DEFAULT_EMAIL`](#default-contact-address) environment variable to avoid unwittingly creating ACME accounts without contact addresses.

If you need to use different contact addresses, you'll need to either use different [ACME account aliases](#multiple-account-keys-per-endpoint) or [disable ACME account keys re-utilization entirely](#disable-account-keys-re-utilization).

#### Private key size

The `LETSENCRYPT_KEYSIZE` environment variable determines the size of the requested key (in bit, defaults to 4096).

#### Test certificates

The `LETSENCRYPT_TEST` environment variable, when set to `true` on a proxyed application container, will create a test certificates that don't have the [5 certs/week/domain limits](https://letsencrypt.org/docs/rate-limits/) and are signed by an untrusted intermediate (they won't be trusted by browsers).

If you want to do this globally for all containers, set `ACME_CA_URI` as described in [Container configuration](./Container-configuration.md).

#### Container restart on cert renewal

The `LETSENCRYPT_RESTART_CONTAINER` environment variable, when set to `true` on an application container, will restart this container whenever the corresponding cert (`LETSENCRYPT_HOST`) is renewed. This is useful when certificates are directly used inside a container for other purposes than HTTPS (e.g. an FTPS server), to make sure those containers always use an up to date certificate.

#### ACME account alias

See the [ACME account keys](#multiple-account-keys-per-endpoint) section.

### global (set on letsencrypt-nginx-proxy-companion container)

#### Default contact address

The `DEFAULT_EMAIL` variable must be a valid email and, when set on the **letsencrypt_nginx_proxy_companion** container, will be used as a fallback when no email address is provided using proxyed container's `LETSENCRYPT_EMAIL` environment variables.

#### Private key re-utilization

The `REUSE_PRIVATE_KEYS` environment variable, when set to `true` on the **letsencrypt-nginx-proxy-companion** container, will set **simp_le** to reuse previously generated private key instead of generating a new one at renewal for all domains.

Reusing private keys can help if you intend to use HPKP, but please note that HPKP will be deprecated by at least one major browser (Chrome), and that it is therefore strongly discouraged to use it at all.

#### ACME account key re-utilization

See the [ACME account keys](#disable-account-keys-re-utilization) section.

## ACME account keys

By default the container will save the first ACME account key created for each ACME API endpoint used, and will reuse it for all subsequent authorization and issuance requests made to this endpoint. This behavior is enabled by default to avoid running into Let's Encrypt account [rate limits](https://letsencrypt.org/docs/rate-limits/).

For instance, when using the default Let's Encrypt production endpoint, the container will save the first account key created for this endpoint as `/etc/nginx/certs/accounts/acme-v01.api.letsencrypt.org/directory/default.json` and will reuse it for future requests made to this endpoint.

#### Multiple account keys per endpoint

If required, you can use multiple accounts for the same ACME API endpoint by using the `LETSENCRYPT_ACCOUNT_ALIAS` environment variable on your proxyed container. This instruct the **letsencrypt-nginx-proxy-companion** container to look for an account key named after the provided alias instead of `default.json`. For example, `LETSENCRYPT_ACCOUNT_ALIAS=client1` will use the key named `client1.json` in the corresponding ACME API endpoint folder for this proxyed container (or will create it if it does not exists yet).

Please see the *One Account or Many?* paragraph on [Let's Encrypt Integration Guide](https://letsencrypt.org/docs/integration-guide/) for additional information.

#### Disable account keys re-utilization

If you want to disable the account key re-utilization entirely, you can set the environment variable `REUSE_ACCOUNT_KEYS` to `false` on the **letsencrypt-nginx-proxy-companion** container. This creates a new ACME registration with a corresponding account key for each new certificate issuance. Note that this won't create new account keys for certs already issued before `REUSE_ACCOUNT_KEYS` is set to `false`. This is not recommended unless you have specific reasons to do so.
