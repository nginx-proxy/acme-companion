## Environment Variables Reference

### acme-companion Container Variables

| Variable | Default | Legacy Variable | Documentation |
|---|---|---|---|
| `ACME_CA_URI` | `https://acme-v02.api.letsencrypt.org/directory` | — | [Container configuration](./Container-configuration.md#optional-container-environment-variables-for-custom-configuration) |
| `ACME_CHALLENGE` | `HTTP-01` | — | [Let's Encrypt and ACME › DNS-01 challenge](./Let's-Encrypt-and-ACME.md#dns-01-acme-challenge) |
| `ACMESH_DNS_API_CONFIG` | — | — | [Let's Encrypt and ACME › DNS-01 challenge](./Let's-Encrypt-and-ACME.md#dns-01-acme-challenge) |
| `ACME_CERT_PROFILE` | CA default | — | [Let's Encrypt and ACME › Default certificate profile](./Let's-Encrypt-and-ACME.md#default-certificate-profile) |
| `ACME_EAB_KID` | — | — | [Zero SSL](./Zero-SSL.md) · [Google Trust Services](./Google-Trust-Services.md) |
| `ACME_EAB_HMAC_KEY` | — | — | [Zero SSL](./Zero-SSL.md) · [Google Trust Services](./Google-Trust-Services.md) |
| `ACME_HTTP_CHALLENGE_LOCATION` | `false` | — | [Container configuration](./Container-configuration.md#optional-container-environment-variables-for-custom-configuration) |
| `ACME_POST_HOOK` | — | — | [Container configuration](./Container-configuration.md#optional-container-environment-variables-for-custom-configuration) · [Hooks](./Hooks.md) |
| `ACME_PRE_HOOK` | — | — | [Container configuration](./Container-configuration.md#optional-container-environment-variables-for-custom-configuration) · [Hooks](./Hooks.md) |
| `ACME_RENEW_AFTER` | `60` (days) | `DEFAULT_RENEW` ⚠️ deprecated | [Container configuration](./Container-configuration.md#optional-container-environment-variables-for-custom-configuration) |
| `CA_BUNDLE` | Alpine trust store | — | [Container configuration](./Container-configuration.md#optional-container-environment-variables-for-custom-configuration) |
| `CERTS_UPDATE_INTERVAL` | `3600` (seconds) | — | [Container configuration](./Container-configuration.md#optional-container-environment-variables-for-custom-configuration) |
| `CREATE_DEFAULT_CERTIFICATE` | `false` | — | [Let's Encrypt and ACME › Self signed default certificate](./Let's-Encrypt-and-ACME.md#self-signed-default-certificate) |
| `DEBUG` | `0` | — | [Container configuration](./Container-configuration.md#optional-container-environment-variables-for-custom-configuration) |
| `DEFAULT_EMAIL` | — | — | [Let's Encrypt and ACME › Default contact address](./Let's-Encrypt-and-ACME.md#default-contact-address) |
| `DEFAULT_KEY_SIZE` | `4096` | — | [Let's Encrypt and ACME › Private key size](./Let's-Encrypt-and-ACME.md#private-key-size) |
| `DHPARAM_BITS` | `4096` | — | [Container configuration](./Container-configuration.md#optional-container-environment-variables-for-custom-configuration) |
| `DHPARAM_SKIP` | `false` | — | [Container configuration](./Container-configuration.md#optional-container-environment-variables-for-custom-configuration) |
| `DOCKER_CERT_PATH` | — | — | [Container configuration](./Container-configuration.md#optional-container-environment-variables-for-custom-configuration) |
| `DOCKER_CONTAINER_FILTERS` | all containers | — | [Container configuration](./Container-configuration.md#optional-container-environment-variables-for-custom-configuration) |
| `DOCKER_HOST` | `unix:///var/run/docker.sock` | — | [Container configuration](./Container-configuration.md#optional-container-environment-variables-for-custom-configuration) |
| `DOCKER_TLS_VERIFY` | `false` | — | [Container configuration](./Container-configuration.md#optional-container-environment-variables-for-custom-configuration) |
| `ENABLE_IPV6` | `false` | — | [Container configuration](./Container-configuration.md#optional-container-environment-variables-for-custom-configuration) |
| `FILES_GID` | same as `FILES_UID` | — | [Persistent data › Ownership & permissions](./Persistent-data.md#ownership--permissions-of-private-and-acme-account-keys) |
| `FILES_PERMS` | `600` | — | [Persistent data › Ownership & permissions](./Persistent-data.md#ownership--permissions-of-private-and-acme-account-keys) |
| `FILES_UID` | `root` | — | [Persistent data › Ownership & permissions](./Persistent-data.md#ownership--permissions-of-private-and-acme-account-keys) |
| `FOLDERS_PERMS` | `755` | — | [Persistent data › Ownership & permissions](./Persistent-data.md#ownership--permissions-of-private-and-acme-account-keys) |
| `NGINX_DOCKER_GEN_CONTAINER` | — | — | [Advanced usage](./Advanced-usage.md) · [Getting containers IDs](./Getting-containers-IDs.md) |
| `NGINX_PROXY_CONTAINER` | — | — | [Getting containers IDs](./Getting-containers-IDs.md) |
| `RELOAD_NGINX_ONLY_ONCE` | `false` | — | [Container configuration](./Container-configuration.md#optional-container-environment-variables-for-custom-configuration) |
| `RENEW_PRIVATE_KEYS` | `true` | — | [Container configuration](./Container-configuration.md#optional-container-environment-variables-for-custom-configuration) · [Let's Encrypt and ACME › Private key re-utilization](./Let's-Encrypt-and-ACME.md#private-key-re-utilization) |
| `ZEROSSL_API_KEY` | — | — | [Zero SSL](./Zero-SSL.md) |

---

### Proxied Container Variables

| Variable | Default | Legacy Variable | Documentation |
|---|---|---|---|
| `ACME_HOST` | — | `LETSENCRYPT_HOST` | [Basic usage](./Basic-usage.md) · [Let's Encrypt and ACME](./Let's-Encrypt-and-ACME.md) |
| `ACME_EMAIL` | `DEFAULT_EMAIL` or none | `LETSENCRYPT_EMAIL` | [Let's Encrypt and ACME › Contact address](./Let's-Encrypt-and-ACME.md#contact-address) |
| `ACME_CA_URI` | acme-companion's `ACME_CA_URI` | — | [Let's Encrypt and ACME › ACME CA URI](./Let's-Encrypt-and-ACME.md#acme-ca-uri) |
| `ACME_CHALLENGE` | acme-companion's `ACME_CHALLENGE` | — | [Let's Encrypt and ACME › DNS-01 challenge](./Let's-Encrypt-and-ACME.md#dns-01-acme-challenge) |
| `ACMESH_DNS_API_CONFIG` | acme-companion's `ACMESH_DNS_API_CONFIG` | — | [Let's Encrypt and ACME › DNS-01 challenge](./Let's-Encrypt-and-ACME.md#dns-01-acme-challenge) |
| `ACME_CERT_PROFILE` | acme-companion's `ACME_CERT_PROFILE` or CA default | — | [Let's Encrypt and ACME › Certificate profile](./Let's-Encrypt-and-ACME.md#certificate-profile) |
| `ACME_EAB_KID` | acme-companion's `ACME_EAB_KID` | — | [Zero SSL](./Zero-SSL.md) · [Google Trust Services](./Google-Trust-Services.md) |
| `ACME_EAB_HMAC_KEY` | acme-companion's `ACME_EAB_HMAC_KEY` | — | [Zero SSL](./Zero-SSL.md) · [Google Trust Services](./Google-Trust-Services.md) |
| `ACME_KEYSIZE` | `DEFAULT_KEY_SIZE` (`4096`) | `LETSENCRYPT_KEYSIZE` | [Let's Encrypt and ACME › Private key size](./Let's-Encrypt-and-ACME.md#private-key-size) |
| `ACME_OCSP` | `false` | — | [Let's Encrypt and ACME › OCSP stapling](./Let's-Encrypt-and-ACME.md#ocsp-stapling) |
| `ACME_POST_HOOK` | — | — | [Let's Encrypt and ACME › Pre-Hook and Post-Hook](./Let's-Encrypt-and-ACME.md#pre-hook-and-post-hook) |
| `ACME_PRE_HOOK` | — | — | [Let's Encrypt and ACME › Pre-Hook and Post-Hook](./Let's-Encrypt-and-ACME.md#pre-hook-and-post-hook) |
| `ACME_PREFERRED_CHAIN` | — | — | [Let's Encrypt and ACME › Preferred chain](./Let's-Encrypt-and-ACME.md#preferred-chain) |
| `ACME_RENEW_AFTER` | acme-companion's `ACME_RENEW_AFTER` (`60`) | — | [Let's Encrypt and ACME › Certificate renewal timing](./Let's-Encrypt-and-ACME.md#certificate-renewal-timing) |
| `ACME_RENEW_PRIVATE_KEYS` | `RENEW_PRIVATE_KEYS` (`true`) | — | [Container configuration](./Container-configuration.md#optional-container-environment-variables-for-custom-configuration) |
| `ACME_RESTART_CONTAINER` | `false` | `LETSENCRYPT_RESTART_CONTAINER` | [Let's Encrypt and ACME › Container restart on cert renewal](./Let's-Encrypt-and-ACME.md#container-restart-on-cert-renewal) |
| `ACME_SINGLE_DOMAIN_CERTS` | `false` | `LETSENCRYPT_SINGLE_DOMAIN_CERTS` | [Let's Encrypt and ACME › Separate certificate for each domain](./Let's-Encrypt-and-ACME.md#separate-certificate-for-each-domain) |
| `LETSENCRYPT_TEST` | `false` | — | [Let's Encrypt and ACME › Test certificates](./Let's-Encrypt-and-ACME.md#test-certificates) |
| `ZEROSSL_API_KEY` | acme-companion's `ZEROSSL_API_KEY` | — | [Zero SSL](./Zero-SSL.md) |