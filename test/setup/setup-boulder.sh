#!/bin/bash

set -e

SERVER=http://localhost:4000/directory

setup_boulder() {
  # Per the boulder README:
  nginx_proxy_ip="$(docker inspect --format='{{range .NetworkSettings.Networks}}{{.Gateway}}{{end}}' "$NGINX_CONTAINER_NAME")"

  export GOPATH=${TRAVIS_BUILD_DIR}/go
  [[ ! -d $GOPATH/src/github.com/letsencrypt/boulder ]] \
    && git clone --depth=1 https://github.com/letsencrypt/boulder \
      $GOPATH/src/github.com/letsencrypt/boulder
  pushd $GOPATH/src/github.com/letsencrypt/boulder
  sed --in-place 's/ 5002/ 80/g' test/config/va.json
  sed --in-place 's/ 5001/ 443/g' test/config/va.json
  sed --in-place 's/le.wtf,le1.wtf/le1.wtf,le2.wtf,le3.wtf/g' test/rate-limit-policies.yml
  docker-compose pull
  docker-compose build
  docker-compose run -d \
    --name boulder \
    -e FAKE_DNS=$nginx_proxy_ip \
    --service-ports \
    boulder
  popd
}

wait_for_boulder() {
  i=0
  until curl ${SERVER?} >/dev/null 2>&1; do
    if [ $i -gt 300 ]; then
      echo "Boulder has not started for 5 minutes, timing out."
      exit 1
    fi
    i=$((i + 5))
    echo "$SERVER : connection refused, Boulder isn't ready yet. Waiting."
    sleep 5
  done
}

setup_boulder
wait_for_boulder
