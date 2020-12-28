#!/bin/bash

set -e

acme_endpoint='http://boulder:4001/directory'

setup_boulder() {
  export GOPATH=${GITHUB_WORKSPACE}/go
  [[ ! -d $GOPATH/src/github.com/letsencrypt/boulder ]] \
    && git clone https://github.com/letsencrypt/boulder \
      "$GOPATH/src/github.com/letsencrypt/boulder"
  pushd "$GOPATH/src/github.com/letsencrypt/boulder"
  git checkout release-2020-12-14
  if [[ "$(uname)" == 'Darwin' ]]; then
    # Set Standard Ports
    for file in test/config/va.json test/config/va-remote-a.json test/config/va-remote-b.json; do
      sed -i '' 's/ 5002/ 80/g' "$file"
      sed -i '' 's/ 5001/ 443/g' "$file"
    done
    # Modify custom rate limit
    sed -i '' 's/le.wtf,le1.wtf/le1.wtf,le2.wtf,le3.wtf/g' test/rate-limit-policies.yml
  else
    # Set Standard Ports
    for file in test/config/va.json test/config/va-remote-a.json test/config/va-remote-b.json; do
      sed --in-place 's/ 5002/ 80/g' "$file"
      sed --in-place 's/ 5001/ 443/g' "$file"
    done
    # Modify custom rate limit
    sed --in-place 's/le.wtf,le1.wtf/le1.wtf,le2.wtf,le3.wtf/g' test/rate-limit-policies.yml
  fi
  docker-compose build --pull
  docker-compose run -d \
    --use-aliases \
    --name boulder \
    -e FAKE_DNS=10.77.77.1 \
    --service-ports \
    boulder
  popd
}

wait_for_boulder() {
  i=0
  until docker exec boulder bash -c "curl ${acme_endpoint:?} >/dev/null 2>&1"; do
    if [ $i -gt 300 ]; then
      echo "Boulder has not started for 5 minutes, timing out."
      exit 1
    fi
    i=$((i + 5))
    echo "$acme_endpoint : connection refused, Boulder isn't ready yet. Waiting."
    sleep 5
  done
}

setup_boulder
wait_for_boulder
