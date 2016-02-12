FROM alpine:latest
# Changed, not sure if needed
MAINTAINER Moreno Sint Hill <info@mirabis.nl> (@mirabis)

ENV DEBUG=false              \
    DOCKER_GEN_VERSION=0.4.3 \
    DOCKER_HOST=unix:///var/run/docker.sock

RUN apk --update add bash curl ca-certificates tar procps jq && \
    rm -rf /var/cache/apk/*

RUN curl -L -O https://github.com/jwilder/docker-gen/releases/download/$DOCKER_GEN_VERSION/docker-gen-linux-amd64-$DOCKER_GEN_VERSION.tar.gz \
 && tar -C /usr/local/bin -xvzf docker-gen-linux-amd64-$DOCKER_GEN_VERSION.tar.gz \
 && rm -f docker-gen-linux-amd64-$DOCKER_GEN_VERSION.tar.gz

WORKDIR /app

# Install simp_le program
COPY /install_simp_le.sh /app/install_simp_le.sh
RUN chmod +rx /app/install_simp_le.sh && sync && /app/install_simp_le.sh && rm -f /app/install_simp_le.sh

ENTRYPOINT ["/bin/bash", "/app/entrypoint.sh" ]
CMD ["/bin/bash", "/app/start.sh" ]

COPY /app/ /app/
