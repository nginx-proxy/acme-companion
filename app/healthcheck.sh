#!/bin/bash

# Docker healthcheck: the container is healthy while both background services
# started by start.sh (the certificates service and docker-gen) are alive.

check_pid_file() {
    local name="$1" file="$2" pid
    if [[ ! -s "$file" ]]; then
        echo "unhealthy: $name PID file $file is missing or empty" >&2
        return 1
    fi
    pid="$(cat "$file")"
    if ! kill -0 "$pid" 2>/dev/null; then
        echo "unhealthy: $name (PID $pid) is not running" >&2
        return 1
    fi
}

rc=0
check_pid_file letsencrypt_service /var/run/letsencrypt_service.pid || rc=1
check_pid_file docker-gen /var/run/docker-gen.pid || rc=1
exit "$rc"
