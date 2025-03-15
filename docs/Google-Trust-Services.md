## Google Trust Services

[Google Trust Service](https://pki.goog/) is an ACME CA with generous default quota and high ubiquity. 

Using Google Trust Services through an ACME client, like in this container, allows for unlimited 90 days and multi-domains (SAN) certificates.

### Activation

Google Trust Services support is activated when the `ACME_CA_URI` environment variable is set to the Google Trust Services ACME endpoint (`https://dv.acme-v02.api.pki.goog/directory`).

### Account

Google Trust Services requires the use of an externally bound account. First create a [Google Trust Services account](https://cloud.google.com/certificate-manager/docs/public-ca-tutorial#request-key-hmac):

- provide the pre-generated [EAB credentials](https://tools.ietf.org/html/rfc8555#section-7.3.4) using the `ACME_EAB_KID` and `ACME_EAB_HMAC_KEY` environment variables.

These variables can be set on the proxied containers or directly on the **acme-companion** container.
