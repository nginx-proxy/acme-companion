#!/bin/bash

set -e

setup_pebble() {
    docker network create --driver=bridge --subnet=10.30.50.0/24 acme_net
    curl https://raw.githubusercontent.com/letsencrypt/pebble/master/test/certs/pebble.minica.pem > "${GITHUB_WORKSPACE}/pebble.minica.pem"
    cat "${GITHUB_WORKSPACE}/pebble.minica.pem"

    docker run -d \
        --name pebble \
        --volume "${GITHUB_WORKSPACE}/test/setup/pebble-config.json:/test/config/pebble-config.json" \
        --network acme_net \
        --ip="10.30.50.2" \
        --publish 14000:14000 \
        --label com.github.jrcs.letsencrypt_nginx_proxy_companion.test_suite \
        letsencrypt/pebble:v2.3.1 \
        pebble -config /test/config/pebble-config.json -dnsserver 10.30.50.3:8053

    docker run -d \
        --name challtestserv \
        --network acme_net \
        --ip="10.30.50.3" \
        --publish 8055:8055 \
        --label com.github.jrcs.letsencrypt_nginx_proxy_companion.test_suite \
        letsencrypt/pebble-challtestsrv:v2.3.1 \
        pebble-challtestsrv -tlsalpn01 ""
}

wait_for_pebble() {
    for endpoint in 'https://pebble:14000/dir' 'http://pebble-challtestsrv:8055'; do
        while ! curl -k "$endpoint" >/dev/null 2>&1; do
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
    curl -X POST -d '{"ip":"10.30.50.1"}' http://pebble-challtestsrv:8055/set-default-ipv4
    curl -X POST -d '{"ip":""}' http://pebble-challtestsrv:8055/set-default-ipv6
    curl -X POST -d '{"host":"lim.it", "addresses":["10.0.0.0"]}' http://pebble-challtestsrv:8055/add-a
}

setup_pebble
wait_for_pebble
setup_pebble_challtestserv