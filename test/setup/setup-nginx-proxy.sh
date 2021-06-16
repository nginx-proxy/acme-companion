#!/bin/bash

set -e

case $ACME_CA in

  pebble)
    test_net='acme_net'
  ;;

  boulder)
    test_net='boulder_bluenet'
  ;;

  *)
    echo "$0 $ACME_CA: invalid option."
    exit 1

esac

case $SETUP in

  2containers)
    docker run -d -p 80:80 -p 443:443 \
      --name "$NGINX_CONTAINER_NAME" \
      --env "DHPARAM_BITS=256" \
      -v /etc/nginx/vhost.d \
      -v /etc/nginx/conf.d \
      -v /usr/share/nginx/html \
      -v /var/run/docker.sock:/tmp/docker.sock:ro \
      --label com.github.jrcs.letsencrypt_nginx_proxy_companion.test_suite \
      --network "$test_net" \
      nginxproxy/nginx-proxy
    ;;

  3containers)
    curl https://raw.githubusercontent.com/nginx-proxy/nginx-proxy/main/nginx.tmpl > "${GITHUB_WORKSPACE}/nginx.tmpl"

    docker run -d -p 80:80 -p 443:443 \
      --name "$NGINX_CONTAINER_NAME" \
      -v /etc/nginx/conf.d \
      -v /etc/nginx/certs \
      -v /etc/nginx/vhost.d \
      -v /usr/share/nginx/html \
      --label com.github.jrcs.letsencrypt_nginx_proxy_companion.test_suite \
      --network "$test_net" \
      nginx:alpine

    docker run -d \
      --name "$DOCKER_GEN_CONTAINER_NAME" \
      --volumes-from "$NGINX_CONTAINER_NAME" \
      -v "${GITHUB_WORKSPACE}/nginx.tmpl:/etc/docker-gen/templates/nginx.tmpl:ro" \
      -v /var/run/docker.sock:/tmp/docker.sock:ro \
      --label com.github.jrcs.letsencrypt_nginx_proxy_companion.test_suite \
      --network "$test_net" \
      nginxproxy/docker-gen \
      -notify-sighup "$NGINX_CONTAINER_NAME" -watch /etc/docker-gen/templates/nginx.tmpl /etc/nginx/conf.d/default.conf
    ;;

  *)
    echo "$0 $SETUP: invalid option."
    exit 1

esac
