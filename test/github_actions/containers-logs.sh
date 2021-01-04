#!/bin/bash

bold_echo() {
  echo -e "\033[33;1m$1\033[0m"
}

if [[ -f "$GITHUB_WORKSPACE/test/github_actions/failed_tests.txt" ]]; then
  mapfile -t containers < "$GITHUB_WORKSPACE/test/github_actions/failed_tests.txt"
fi

containers+=("$NGINX_CONTAINER_NAME")
[[ $SETUP = "3containers" ]] && containers+=("$DOCKER_GEN_CONTAINER_NAME")
[[ $ACME_CA = "boulder" ]] && containers+=(boulder)
[[ $ACME_CA = "pebble" ]] && containers+=(pebble challtestserv)

for container in "${containers[@]}"; do
  bold_echo "Docker container output for $container"
  docker logs "$container"
  docker inspect "$container"
  if [[ "$container" == "acme_accounts" ]]; then
    bold_echo "Docker container output for ${container}_default"
    docker logs "${container}_default"
    docker inspect "${container}_default"
  fi
done
