#!/bin/bash

# SIGTERM-handler
term_handler() {
    [[ -n "$docker_gen_pid" ]] && kill "$docker_gen_pid"
    [[ -n "$letsencrypt_service_pid" ]] && kill "$letsencrypt_service_pid"

    # shellcheck source=functions.sh
    source /app/functions.sh
    remove_all_location_configurations
    remove_all_standalone_configurations

    exit 0
}

trap 'term_handler' INT QUIT TERM

/app/letsencrypt_service &
letsencrypt_service_pid=$!

wait_default="5s:20s"
DOCKER_GEN_WAIT="${DOCKER_GEN_WAIT:-$wait_default}"
docker-gen -watch -notify '/app/signal_le_service' -wait "$DOCKER_GEN_WAIT" /app/letsencrypt_service_data.tmpl /app/letsencrypt_service_data &
docker_gen_pid=$!

# wait "indefinitely"
while [[ -e /proc/$docker_gen_pid ]]; do
    wait $docker_gen_pid # Wait for any signals or end of execution of docker-gen
done

# Stop container properly
term_handler
