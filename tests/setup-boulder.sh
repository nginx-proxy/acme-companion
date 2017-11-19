#!/bin/bash

set -e

SERVER=http://localhost:4000/directory

setup_boulder() {
  # Per the boulder README:
  nginx_proxy_ip=$(ifconfig docker0 | grep "inet addr:" | cut -d: -f2 | awk '{ print $1}')

  export GOPATH=${TRAVIS_BUILD_DIR}/go
  git clone --depth=1 https://github.com/letsencrypt/boulder \
    $GOPATH/src/github.com/letsencrypt/boulder
  cd $GOPATH/src/github.com/letsencrypt/boulder
  sed --in-place 's/ 5002/ 80/g' test/config/va.json
  sed --in-place 's/ 5001/ 443/g' test/config/va.json
  docker-compose pull
  docker-compose build
  docker-compose run \
    -e FAKE_DNS=$nginx_proxy_ip \
    --service-ports \
    boulder &
  cd -
}

wait_for_boulder() {
  i=0
  until curl ${SERVER?} >/dev/null 2>&1; do
    if [ $i -gt 300 ]; then
      echo "Boulder has not started for 5 minutes, timing out."
      exit 1
    fi
    i=$((i + 5))
    echo "$SERVER : connection refused. Waiting."
    sleep 5
  done
}

setup_boulder
wait_for_boulder
