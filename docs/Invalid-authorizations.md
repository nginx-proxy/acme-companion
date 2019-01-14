## Troubleshooting failing authorizations

The first two things to do in case of failing authorization are to run the **letsencrypt-nginx-proxy-companion** container with the environment variable `DEBUG=true` to enable the more detailed error messages, and to [request test certificates](./Let's-Encrypt-and-ACME.md#test-certificates) while troubleshooting the issue.

Common causes of of failing authorizations:

#### port `80` or `443` on your host are closed / filtered from the outside, possibly because of a misconfigured firewall.

Check your host `80` and `443` ports **from the outside** (as in from a host having a different public IP) with `nmap` or a similar tool.

#### your domain name does not resolve to your host IPv4 and/or IPv6.

Check that your domain name A (and AAAA, if present) records points to the correct adresses using `drill`, `dig` or `nslookup`.

#### your domain name advertise an AAAA (IPv6) record, but your host or your host's docker isn't actually reachable over IPv6.

Create a test nginx container on your host and try to reach it over both IPv4 and IPv6.

```bash
you@remotedockerhost$ docker run -d -p 80:80 nginx:alpine

you@localcomputer$ curl http://your.domain.tld
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
[...]
</html>

you@localcomputer$ curl -6 http://your.domain.tld
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
[...]
</html>
```

If you are unsure of your host/hosts's docker IPv6 connectivity, drop the AAAA record from your domain name and wait for the modification to propagate.

#### your domain name DNS provider answers incorrectly to CAA record requests.

Read https://letsencrypt.org/docs/caa/ and test with https://unboundtest.com/

#### the **nginx-proxy**/**nginx**/**docker-gen**/**letsencrypt-nginx-proxy-companion** containers were misconfigured.

Review [basic usage](./Basic-usage.md) or [advanced usage](./Advanced-usage.md), plus the [nginx-proxy documentation](https://github.com/jwilder/nginx-proxy).

Pay special attention to the fact that the volumes **MUST** be shared between the different containers.

#### you forgot to set both `VIRTUAL_HOST` and `LETSENCRYPT_HOST` on the proxyed container.

Both are required. Every domain on `LETSENCRYPT_HOST`**must** be on `VIRTUAL_HOST`too.

#### you are using an outdated version of either **letsencrypt-nginx-proxy-companion** or the nginx.tmpl file (if running a 3 containers setup)

Pull `jrcs/letsencrypt-nginx-proxy-companion:latest` again and get the latest [latest nginx.tmpl](https://raw.githubusercontent.com/jwilder/nginx-proxy/master/nginx.tmpl).


***


The challenge files are automatically cleaned up **after** the authorization process, wether it succeeded or failed, so trying to `curl` them from the outside won't yeld any result. You can however create a test file inside the same folder and use it to test the challenge files reachability from the outside (over both IPv4 and IPv6 if you want to use the latter):

```
you@remotedockerhost$ docker exec your-le-container bash -c 'echo "Hello world!" > /usr/share/nginx/html/.well-known/acme-challenge/hello-world'

you@localcomputer$ curl http://yourdomain.tld/.well-known/acme-challenge/hello-world
Hello world!
you@localcomputer$ curl -6 http://yourdomain.tld/.well-known/acme-challenge/hello-world
Hello world!
```

If you have issues with the [advanced setup](./Advanced-usage.md), fallback to the [basic setup](./Basic-usage.md). The advanced setup is not meant to be obligatory.
