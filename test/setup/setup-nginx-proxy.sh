#!/bin/bash

set -e

case $SETUP in

  2containers)
    docker run -d -p 80:80 -p 443:443 \
      --name $NGINX_CONTAINER_NAME \
      --env "DHPARAM_BITS=256" \
      -v /etc/nginx/vhost.d \
      -v /etc/nginx/conf.d \
      -v /usr/share/nginx/html \
      -v /var/run/docker.sock:/tmp/docker.sock:ro \
      --label com.github.jrcs.letsencrypt_nginx_proxy_companion.test_suite \
      --network boulder_bluenet \
      jwilder/nginx-proxy
    ;;

  3containers)
    curl https://raw.githubusercontent.com/jwilder/nginx-proxy/master/nginx.tmpl > ${TRAVIS_BUILD_DIR}/nginx.tmpl

    docker run -d -p 80:80 -p 443:443 \
      --name $NGINX_CONTAINER_NAME \
      -v /etc/nginx/conf.d \
      -v /etc/nginx/certs \
      -v /etc/nginx/vhost.d \
      -v /usr/share/nginx/html \
      --label com.github.jrcs.letsencrypt_nginx_proxy_companion.test_suite \
      --network boulder_bluenet \
      nginx:alpine

    docker run -d \
      --name $DOCKER_GEN_CONTAINER_NAME \
      --volumes-from $NGINX_CONTAINER_NAME \
      -v ${TRAVIS_BUILD_DIR}/nginx.tmpl:/etc/docker-gen/templates/nginx.tmpl:ro \
      -v /var/run/docker.sock:/tmp/docker.sock:ro \
      --label com.github.jrcs.letsencrypt_nginx_proxy_companion.test_suite \
      --network boulder_bluenet \
      jwilder/docker-gen \
      -notify-sighup $NGINX_CONTAINER_NAME -watch -wait 5s:30s /etc/docker-gen/templates/nginx.tmpl /etc/nginx/conf.d/default.conf
    ;;

  *)
    echo "$0 $SETUP: invalid option."
    exit 1

esac
