---
name: Bug report
about: Create a report to help us improve
title: ''
labels: ''
assignees: ''

---

If your are using `latest` and recently updated your image: please make sure you've checked the required read on [the project's README.md](https://github.com/nginx-proxy/docker-letsencrypt-nginx-proxy-companion/blob/master/README.md).

**HTTPS does not work / certificate aren't created** : please check in your letsencrypt-nginx-proxy-companion container logs if an authorization or verify error is mentioned, for instance:
```
[Wed Dec 16 14:45:12 UTC 2020] sub.domain.com:Verify error:Invalid response from http://sub.domain.com/.well-known/acme-challenge/xxxxxxxxxxxxxxxxxxxxxxxxxx
```
If it is please do the following before opening an issue:
- check and follow the [troubleshooting instructions](https://github.com/nginx-proxy/docker-letsencrypt-nginx-proxy-companion/blob/master/docs/Invalid-authorizations.md) in the docs.
- [search the existing similar issues](https://github.com/nginx-proxy/docker-letsencrypt-nginx-proxy-companion/issues?q=is%3Aissue+label%3A%22Failing+authorization%22+), both opened and closed.

Bug description
-----------------
A clear and concise description of what the bug is.

letsencrypt-nginx-proxy-companion image version
-----------------

Please provide the container version that should be printed to the first line of log at container startup:
```bash
[you@yourhost]: $ docker logs companion-container-name
Info: running letsencrypt-nginx-proxy-companion version v2.0.0
[...]
```

If this first log line isn't present you are using a `v1` image: please provide the [tagged version](https://github.com/nginx-proxy/docker-letsencrypt-nginx-proxy-companion/releases) you are using. If you are using `latest`, please try again with a tagged release before opening an issue (the last `v1` tagged release is `v1.13.1`).

nginx-proxy-companion configuration
-----------------

Please provide the configuration (either command line, compose file, or other) of your nginx-proxy stack and your proxied container(s).

You can obfuscate information you want to keep private (and should obfuscate configuration secrets) such as domain(s) and/or email adress(es), but other than that **please provide the full configurations** and not the just snippets of the parts that seem relevants to you.

Containers logs
-----------------

Please provide the logs of:
- your `letsencrypt-nginx-proxy-companion` container
- your `nginx-proxy` container (or `nginx` and `docker-gen` container in a three containers setup)

`docker logs name-of-the-container`

Docker host
-----------------

 - OS: [e.g. Ubuntu 20.04]
 - Docker version: output of `docker version`
