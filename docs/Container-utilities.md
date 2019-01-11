The container provide the following utilities (replace `nginx-letsencrypt` with the name or ID of your **letsencrypt-nginx-proxy-companion** container when executing the commands):

### Force certificates renewal
If needed, you can force a running **letsencrypt-nginx-proxy-companion** container to renew all certificates that are currently in use with the following command:

```bash
$ docker exec nginx-letsencrypt /app/force_renew
```

### Manually trigger the service loop
You can trigger the execution of the service loop before the hourly execution with:

```bash
$ docker exec nginx-letsencrypt /app/signal_le_service
```
Unlike the previous command, this won't force renewal of certificates that don't need to be renewed.

### Show certificates informations
To display informations about your existing certificates, use the following command:

```bash
$ docker exec nginx-letsencrypt /app/cert_status
```