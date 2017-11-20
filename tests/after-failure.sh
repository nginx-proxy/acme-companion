#!/bin/bash

set -e

case $1 in
  2containers)
    echo "Logs of $NGINX_CONTAINER_NAME container:"
    docker logs $NGINX_CONTAINER_NAME
    echo -e "\nLogs of $LETSENCRYPT_CONTAINER_NAME container:"
    docker logs $LETSENCRYPT_CONTAINER_NAME
    ;;
  3containers)
    echo "Logs of $NGINX_CONTAINER_NAME container:"
    docker logs $NGINX_CONTAINER_NAME
    echo -e "\nLogs of $DOCKER_GEN_CONTAINER_NAME container:"
    docker logs $DOCKER_GEN_CONTAINER_NAME
    echo -e "\nLogs of $LETSENCRYPT_CONTAINER_NAME container:"
    docker logs $LETSENCRYPT_CONTAINER_NAME
    ;;
  *)
    echo "$0 $1: invalid option."
    exit 1
esac
