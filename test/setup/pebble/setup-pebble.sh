#!/bin/bash

set -e

setup_pebble() {
    curl --silent --show-error https://raw.githubusercontent.com/letsencrypt/pebble/master/test/certs/pebble.minica.pem > "${GITHUB_WORKSPACE}/pebble.minica.pem"
    cat "${GITHUB_WORKSPACE}/pebble.minica.pem"
    docker-compose --file "${GITHUB_WORKSPACE}/test/setup/pebble/docker-compose.yml" up --detach
}

wait_for_pebble() {
    for endpoint in 'https://pebble:14000/dir' 'http://pebble-challtestsrv:8055'; do
        while ! curl --cacert "${GITHUB_WORKSPACE}/pebble.minica.pem" "$endpoint" >/dev/null 2>&1; do
            if [ $((i * 5)) -gt $((5 * 60)) ]; then
                echo "$endpoint was not available under 5 minutes, timing out."
                exit 1
            fi
            i=$((i + 1))
            sleep 5
        done
    done
}

setup_pebble_challtestserv() {
    curl --silent --show-error --data '{"ip":"10.30.50.1"}' http://pebble-challtestsrv:8055/set-default-ipv4
    curl --silent --show-error --data '{"ip":""}' http://pebble-challtestsrv:8055/set-default-ipv6
    curl --silent --show-error --data '{"host":"lim.it", "addresses":["10.0.0.0"]}' http://pebble-challtestsrv:8055/add-a
}

setup_pebble
wait_for_pebble
setup_pebble_challtestserv
docker-compose --file "${GITHUB_WORKSPACE}/test/setup/pebble/docker-compose.yml" logs
