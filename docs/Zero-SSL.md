## Zero SSL

[Zero SSL](https://zerossl.com/) is an ACME CA that offer some advantages over Let's Encrypt:
- no staging endpoint and [no rate limiting on the production endpoint](https://zerossl.com/features/acme/).
- web based [management console](https://zerossl.com/features/console/) to keep track of your SSL certificates.

Using Zero SSL through an ACME client, like in this container, allows for unlimited 90 days and multi-domains (SAN) certificates.

### Activation

The Zero SSL support is activated when the `ACME_CA_URI` environment variable is set to the Zero SSL ACME endpoint (`https://acme.zerossl.com/v2/DV90`).

### Account

Unlike Let's Encrypt, Zero SSL requires the use of an email bound account. If you already created a Zero SSL account, you can either:

- provide pre-generated [EAB credentials](https://tools.ietf.org/html/rfc8555#section-7.3.4) using the `ACME_EAB_KID` and `ACME_EAB_HMAC_KEY` environment variables.
- provide your ZeroSSL API key using the `ZEROSSL_API_KEY` environment variable.

These variables can be set on the proxied containers or directly on the **acme-companion** container.

If you don't have a ZeroSSL account, you can let **acme-companion** create a Zero SSL account with the adress provided in the `ACME_EMAIL` or `DEFAULT_EMAIL` environment variable. Note that the adresse that will be used must be a valid email adress that you actually own.
