FROM golang:1.15-alpine AS build-docker-gen

ARG DOCKER_GEN_VERSION=fix-current-container-id

LABEL stage=intermediate

# Install build dependencies for docker-gen
RUN apk add --update \
	curl \
	gcc \
	git \
	make \
	musl-dev

# Build docker-gen
RUN go get github.com/buchdag/docker-gen \
    && mv /go/src/github.com/buchdag /go/src/github.com/jwilder \
    && cd /go/src/github.com/jwilder/docker-gen \
    && git -c advice.detachedHead=false checkout $DOCKER_GEN_VERSION \
    && make get-deps \
    && make all

FROM alpine:3.8

LABEL maintainer="Nicolas Duchon <nicolas.duchon@gmail.com>"

# DOCKER_GEN_VERSION environment variable is required by letsencrypt-nginx-proxy-companion
ENV DOCKER_GEN_VERSION=0.7.4 \
    DOCKER_HOST=unix:///tmp/docker.sock

# Copy docker-gen binary from build stage
COPY --from=build-docker-gen /go/src/github.com/jwilder/docker-gen/docker-gen /usr/local/bin/

# Get latest nginx.tmpl
ADD https://raw.githubusercontent.com/nginx-proxy/nginx-proxy/master/nginx.tmpl /etc/docker-gen/templates/

ENTRYPOINT ["/usr/local/bin/docker-gen"]