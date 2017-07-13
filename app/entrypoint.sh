#!/bin/bash

set -u

export CONTAINER_ID=$(cat /proc/self/cgroup | sed -nE 's/^.+docker[\/-]([a-f0-9]{64}).*/\1/p' | head -n 1)

if [[ -z "$CONTAINER_ID" ]]; then
    echo "Error: can't get my container ID !" >&2
    exit 1
fi

function check_docker_socket {
    if [[ $DOCKER_HOST == unix://* ]]; then
        socket_file=${DOCKER_HOST#unix://}
        if [[ ! -S $socket_file ]]; then
            cat >&2 <<-EOT
ERROR: you need to share your Docker host socket with a volume at $socket_file
Typically you should run your container with: \`-v /var/run/docker.sock:$socket_file:ro\`
See the documentation at http://git.io/vZaGJ
EOT
            exit 1
        fi
    fi
}

function get_nginx_proxy_cid {
    # Look for a NGINX_VERSION environment variable in containers that we have mount volumes from.
    local volumes_from=$(docker_api "/containers/$CONTAINER_ID/json" | jq -r '.HostConfig.VolumesFrom[]' 2>/dev/null)
    for cid in $volumes_from; do
        cid=${cid%:*} # Remove leading :ro or :rw set by remote docker-compose (thx anoopr)
        if [[ $(docker_api "/containers/$cid/json" | jq -r '.Config.Env[]' | egrep -c '^NGINX_VERSION=') = "1" ]];then
            export NGINX_PROXY_CONTAINER=$cid
            break
        fi
    done
    if [[ -z "$(nginx_proxy_container)" ]]; then
        echo "Error: can't get nginx-proxy container id !" >&2
        echo "Check that you use the --volumes-from option to mount volumes from the nginx-proxy or label the nginx proxy container to use with 'com.github.jrcs.letsencrypt_nginx_proxy_companion.nginx_proxy=true'." >&2
        exit 1
    fi
}

function check_writable_directory {
    local dir="$1"
    docker_api "/containers/$CONTAINER_ID/json" | jq ".Mounts[].Destination" | grep -q "^\"$dir\"$"
    if [[ $? -ne 0 ]]; then
        echo "Warning: '$dir' does not appear to be a mounted volume."
    fi
    if [[ ! -d "$dir" ]]; then
        echo "Error: can't access to '$dir' directory !" >&2
        echo "Check that '$dir' directory is declared has a writable volume." >&2
        exit 1
    fi
    touch $dir/.check_writable 2>/dev/null
    if [[ $? -ne 0 ]]; then
        echo "Error: can't write to the '$dir' directory !" >&2
        echo "Check that '$dir' directory is export as a writable volume." >&2
        exit 1
    fi
    rm -f $dir/.check_writable
}

function check_dh_group {
    if [[ ! -f /etc/nginx/certs/dhparam.pem ]]; then
        echo "Creating Diffie-Hellman group (can take several minutes...)"
        openssl dhparam -out /etc/nginx/certs/.dhparam.pem.tmp 2048
        mv /etc/nginx/certs/.dhparam.pem.tmp /etc/nginx/certs/dhparam.pem || exit 1
    fi
}

source /app/functions.sh

[[ $DEBUG == true ]] && set -x

if [[ "$*" == "/bin/bash /app/start.sh" ]]; then
    check_docker_socket
    if [[ -z "$(docker_gen_container)" ]]; then
        [[ -z "${NGINX_PROXY_CONTAINER:-}" ]] && get_nginx_proxy_cid
    fi
    check_writable_directory '/etc/nginx/certs'
    check_writable_directory '/etc/nginx/vhost.d'
    check_writable_directory '/usr/share/nginx/html'
    check_dh_group
fi

exec "$@"
