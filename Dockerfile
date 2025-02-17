FROM docker.io/nginxproxy/docker-gen:0.14.5 AS docker-gen

FROM docker.io/library/alpine:3.21.3

ARG GIT_DESCRIBE="unknown"
ARG ACMESH_VERSION=3.1.0

ENV ACMESH_VERSION=${ACMESH_VERSION} \
    COMPANION_VERSION=${GIT_DESCRIBE} \
    DOCKER_HOST=unix:///var/run/docker.sock \
    PATH=${PATH}:/app

# Install packages required by the image
RUN apk add --no-cache --virtual .bin-deps \
    bash \
    bind-tools \
    coreutils \
    curl \
    jq \
    libidn \
    oath-toolkit-oathtool \
    openssh-client \
    openssl \
    sed \
    socat \
    tar \
    tzdata

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
