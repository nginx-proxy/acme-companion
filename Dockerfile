FROM nginxproxy/docker-gen:0.8.4 AS docker-gen

FROM alpine:3.15.4

ARG GIT_DESCRIBE
ARG ACMESH_VERSION=2.9.0

ENV COMPANION_VERSION=$GIT_DESCRIBE \
    DOCKER_HOST=unix:///var/run/docker.sock \
    PATH=$PATH:/app

# Install packages required by the image
RUN apk add --no-cache --virtual .bin-deps \
    bash \
    coreutils \
    curl \
    jq \
    openssl \
    socat

# Install docker-gen from the nginxproxy/docker-gen image
COPY --from=docker-gen /usr/local/bin/docker-gen /usr/local/bin/

# Install acme.sh
COPY /install_acme.sh /app/install_acme.sh
RUN chmod +rx /app/install_acme.sh \
    && sync \
    && /app/install_acme.sh \
    && rm -f /app/install_acme.sh

COPY app LICENSE /app/

WORKDIR /app

ENTRYPOINT [ "/bin/bash", "/app/entrypoint.sh" ]
CMD [ "/bin/bash", "/app/start.sh" ]
