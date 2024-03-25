---
name: Bug report
about: Create a report to help us improve
title: ''
labels: ''
assignees: ''

---

If your are using the latest image tag and recently updated your image: please make sure you've checked the required read on the project's README.

HTTPS does not work / certificate aren't created : please check in your acme-companion container logs if an authorization or verify error is mentioned, if it is please do the following before opening an issue:
- check and follow the troubleshooting instructions in the docs.
- search the existing similar issues, both opened and closed.

Bug description
-----------------

A clear and concise description of what the bug is.

acme-companion image version
-----------------

Please provide the container version that should be printed to the first line of log at container startup:
```
Info: running acme-companion version v2.0.0
```

If this first log line isn't present you are using a v1 image: please provide the tagged version you are using. If you are not using a tagged version latest, please try again with a tagged release before opening an issue (the last v1 tagged release is v1.13.1).

nginx-proxy's Docker configuration
-----------------

Please provide the configuration (either command line, compose file, or other) of your nginx-proxy stack and your proxied container(s).

You can obfuscate information you want to keep private (and should obfuscate configuration secrets) such as domain(s) and/or email adress(es), but other than that please provide the full configurations and not the just snippets of the parts that seem relevants to you.

rendered nginx configuration
-----------------

Please provide the rendered nginx configuration:

```console
docker exec name-of-the-nginx-container nginx -T
```

Containers logs
-----------------

Please provide the logs of:
- your acme-companion container
- your nginx-proxy container (or nginx and docker-gen container in a three containers setup)

```console
docker logs name-of-the-companion-container
```

Docker host
-----------------

 - OS: [e.g. Ubuntu 20.04]
 - Docker version: output of `docker version`
