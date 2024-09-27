## Standalone certificates

You can generate certificate that are not tied to containers environment variable by mounting a user configuration file inside the container at `/app/letsencrypt_user_data`. This feature also require sharing the `/etc/nginx/vhost.d` and `/etc/nginx/conf.d` folder between the **nginx-proxy** and **acme-companion** container (and the **docker-gen** container if you are running a [three container setup](./Advanced-usage.md)):

```bash
$ docker run --detach \
    --name nginx-proxy \
    --publish 80:80 \
    --publish 443:443 \
    --volume certs:/etc/nginx/certs \
    --volume vhost:/etc/nginx/vhost.d \
    --volume conf:/etc/nginx/conf.d \
    --volume html:/usr/share/nginx/html \
    --volume /var/run/docker.sock:/tmp/docker.sock:ro \
    nginxproxy/nginx-proxy
```

```bash
$ docker run --detach \
    --name nginx-proxy-acme \
    --volumes-from nginx-proxy \
    --volume /var/run/docker.sock:/var/run/docker.sock:ro \
    --volume acme:/etc/acme.sh \
    --volume /path/to/your/config_file:/app/letsencrypt_user_data:ro \
    nginxproxy/acme-companion
```

The user configuration file is a collection of bash variables and array, and follows the syntax of the `/app/letsencrypt_service_data` file that get created by **docker-gen**.

### Required configuration parameters:

`LETSENCRYPT_STANDALONE_CERTS` : a bash array containing identifier(s) for you standalone certificate(s). Each element in the array has to be unique. Those identifiers are internal to the container process and won't ever be visible to the outside world or appear on your certificate.

`LETSENCRYPT_uniqueidentifier_HOST` : a bash array containing domain(s) that will be covered by the certificate corresponding to `uniqueidentifier`.

Each identifier in `LETSENCRYPT_STANDALONE_CERTS` must have its own corresponding `LETSENCRYPT_uniqueidentifier_HOST` array, where the string `uniqueidentifier` has to be identical to that identifier. 

**Minimal example generating a single certificate for a single domain:**

```bash
LETSENCRYPT_STANDALONE_CERTS=('uniqueidentifier')
LETSENCRYPT_uniqueidentifier_HOST=('yourdomain.tld')
```

**Example with multiple certificates and domains:**

```bash
LETSENCRYPT_STANDALONE_CERTS=('web' 'app' 'othersite')
LETSENCRYPT_web_HOST=('yourdomain.tld' 'www.yourdomain.tld')
LETSENCRYPT_app_HOST=('myapp.yourdomain.tld' 'myapp.yourotherdomain.tld' 'service.yourotherdomain.tld')
LETSENCRYPT_othersite_HOST=('yetanotherdomain.tld')
```

**Example using DNS-01 verification:**

In this example: `web` and `app` generate a certificate using the global/default configuration. However `othersite` will perform it's certificate verification using a specific DNS-01 API configuration.

```bash
LETSENCRYPT_STANDALONE_CERTS=('web' 'app' 'othersite')
LETSENCRYPT_web_HOST=('yourdomain.tld' 'www.yourdomain.tld')
LETSENCRYPT_app_HOST=('myapp.yourdomain.tld' 'myapp.yourotherdomain.tld' 'service.yourotherdomain.tld')
LETSENCRYPT_othersite_HOST=('yetanotherdomain.tld')

ACME_othersite_CHALLENGE=DNS-01
declare -A ACMESH_othersite_DNS_API_CONFIG=(
    ['DNS_API']='dns_cf'
    ['CF_Token']='<CLOUDFLARE_TOKEN>'
    ['CF_Account_ID']='<CLOUDFLARE_ACCOUNT_ID>'
    ['CF_Zone_ID']='<CLOUDFLARE_ZONE_ID>'
)
```

### Optional configuration parameters:

Single bash variables:

`LETSENCRYPT_uniqueidentifier_EMAIL` : must be a valid email and will be used by Let's Encrypt to warn you of impeding certificate expiration (should the automated renewal fail).

`LETSENCRYPT_uniqueidentifier_KEYSIZE` : determines the size of the requested private key. See [private key size](./Let's-Encrypt-and-ACME.md#private-key-size) for accepted values.

`LETSENCRYPT_uniqueidentifier_TEST` : if set to true, the corresponding certificate will be a test certificates: it won't have the 5 certs/week/domain limits and will be signed by an untrusted intermediate (ie it won't be trusted by browsers).

DNS-01 related variables:

`ACME_uniqueidentifier_CHALLENGE`: Defaults to HTTP-01. In order to switch to the DNS-01 ACME challenge set it to `DNS-01`

`ACMESH_uniqueidentifier_DNS_API_CONFIG`: Defaults to the values of DNS_API_CONFIG. However if you wish to specify a specific DNS-01 verification method on a particular standalone certificate. It must be defined as a bash associative array.

Example
```bash
declare -A ACMESH_alt_DNS_API_CONFIG=(
    ['DNS_API']='dns_cf'
    ['CF_Token']='<CLOUDFLARE_TOKEN>'
    ['CF_Account_ID']='<CLOUDFLARE_ACCOUNT_ID>'
    ['CF_Zone_ID']='<CLOUDFLARE_ZONE_ID>'
)
```

### Picking up changes to letsencrypt_user_data

The container does not actively watch the `/app/letsencrypt_user_data` file for changes.

Changes will either be picked up every hour when the service loop execute again, or by using `docker exec your-le-container-name-or-id /app/signal_le_service` to manually trigger the service loop execution.

### Proxying to something else than a Docker container

Please see the [**nginx-proxy** documentation](https://github.com/nginx-proxy/nginx-proxy#proxy-wide).

No support will be provided on the **acme-companion** repo for proxying related issues or questions.
