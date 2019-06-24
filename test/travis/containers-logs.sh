#!/bin/bash

fold_start() {
  echo -e "travis_fold:start:$1\033[33;1m$2\033[0m"
}

fold_end() {
  echo -e "\ntravis_fold:end:$1\r"
}

for container in $(docker ps -a --format '{{.Names}}'); do
  fold_start "$container" "Docker container output for $container"
  docker logs "$container"
  fold_end "$container"
done
