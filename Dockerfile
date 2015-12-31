FROM alpine:latest

MAINTAINER Yves Blusseau <90z7oey02@sneakemail.com> (@blusseau)

ENV DOCKER_VERSION=latest    \
    DOCKER_GEN_VERSION=0.4.3 \
    DOCKER_HOST=unix:///var/run/docker.sock

RUN apk --update add bash wget ca-certificates tar procps && \
    rm -rf /var/cache/apk/*

RUN wget https://github.com/jwilder/docker-gen/releases/download/$DOCKER_GEN_VERSION/docker-gen-linux-amd64-$DOCKER_GEN_VERSION.tar.gz \
 && tar -C /usr/local/bin -xvzf docker-gen-linux-amd64-$DOCKER_GEN_VERSION.tar.gz \
 && rm -f docker-gen-linux-amd64-$DOCKER_GEN_VERSION.tar.gz

RUN wget -O /usr/bin/docker https://get.docker.com/builds/Linux/x86_64/docker-$DOCKER_VERSION && \
	chmod +rx /usr/bin/docker

WORKDIR /app

# Install simp_le program
COPY /install_simp_le.sh /app/install_simp_le.sh
RUN chmod +rx /app/install_simp_le.sh && sync && /app/install_simp_le.sh && rm -f /app/install_simp_le.sh

ENTRYPOINT ["/bin/bash", "/app/entrypoint.sh" ]
CMD ["/bin/bash", "/app/start.sh" ]

COPY /app/ /app/
