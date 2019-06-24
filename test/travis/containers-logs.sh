#!/bin/bash

fold_start() {
  echo -e "travis_fold:start:$1\033[33;1m$2\033[0m"
}

fold_end() {
  echo -e "\ntravis_fold:end:$1\r"
}

if [[ -f "$TRAVIS_BUILD_DIR/test/travis/failed_tests.txt" ]]; then
  mapfile -t containers < "$TRAVIS_BUILD_DIR/test/travis/failed_tests.txt"
fi

containers+=("$NGINX_CONTAINER_NAME")
[[ $SETUP = "3containers" ]] && containers+=("$DOCKER_GEN_CONTAINER_NAME")
containers+=("boulder")

for container in "${containers[@]}"; do
  fold_start "$container" "Docker container output for $container"
  docker logs "$container"
  fold_end "$container"
done
