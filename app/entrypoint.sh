#!/bin/bash
# shellcheck disable=SC2155

set -u

if [[ -n "${ACME_TOS_HASH:-}" ]]; then
    echo "Info: the ACME_TOS_HASH environment variable is no longer used by simp_le and has been deprecated."
    echo "simp_le now implicitly agree to the ACME CA ToS."
fi

DOCKER_PROVIDER=${DOCKER_PROVIDER:-docker}

case "${DOCKER_PROVIDER}" in
ecs|ECS)
    # AWS ECS. Enabled in /etc/ecs/ecs.config (http://docs.aws.amazon.com/AmazonECS/latest/developerguide/container-metadata.html)
    if [[ -n "${ECS_CONTAINER_METADATA_FILE:-}" ]]; then
      export CONTAINER_ID=$(grep ContainerID "${ECS_CONTAINER_METADATA_FILE}" | sed 's/.*: "\(.*\)",/\1/g')
    else
      echo "${DOCKER_PROVIDER} specified as 'ecs' but not available. See: http://docs.aws.amazon.com/AmazonECS/latest/developerguide/container-metadata.html"
      exit 1
    fi
    ;;
*)
    export CONTAINER_ID=$(sed -nE 's/^.+docker[\/-]([a-f0-9]{64}).*/\1/p' /proc/self/cgroup | head -n 1)
    ;;
esac

if [[ -z "$CONTAINER_ID" ]]; then
    echo "Error: can't get my container ID !" >&2
    exit 1
fi

function check_docker_socket {
    if [[ $DOCKER_HOST == unix://* ]]; then
        socket_file=${DOCKER_HOST#unix://}
        if [[ ! -S $socket_file ]]; then
            echo "Error: you need to share your Docker host socket with a volume at $socket_file" >&2
            echo "Typically you should run your container with: '-v /var/run/docker.sock:$socket_file:ro'" >&2
            exit 1
        fi
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
        echo "Check that '$dir' directory is declared as a writable volume." >&2
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
    local DHPARAM_BITS="${DHPARAM_BITS:-2048}"
    re='^[0-9]*$'
    if ! [[ "$DHPARAM_BITS" =~ $re ]] ; then
       echo "Error: invalid Diffie-Hellman size of $DHPARAM_BITS !" >&2
       exit 1
    fi
    if [[ ! -f /etc/nginx/certs/dhparam.pem ]]; then
        echo "Creating Diffie-Hellman group (can take several minutes...)"
        openssl dhparam -out /etc/nginx/certs/.dhparam.pem.tmp $DHPARAM_BITS
        mv /etc/nginx/certs/.dhparam.pem.tmp /etc/nginx/certs/dhparam.pem || exit 1
    fi
}

source /app/functions.sh

[[ $DEBUG == true ]] && set -x

if [[ "$*" == "/bin/bash /app/start.sh" ]]; then
    check_docker_socket
    if [[ -z "$(get_nginx_proxy_container)" ]]; then
        echo "Error: can't get nginx-proxy container ID !" >&2
        echo "Check that you are doing one of the following :" >&2
        echo -e "\t- Use the --volumes-from option to mount volumes from the nginx-proxy container." >&2
        echo -e "\t- Set the NGINX_PROXY_CONTAINER env var on the letsencrypt-companion container to the name of the nginx-proxy container." >&2
        echo -e "\t- Label the nginx-proxy container to use with 'com.github.jrcs.letsencrypt_nginx_proxy_companion.nginx_proxy'." >&2
        exit 1
    elif [[ -z "$(get_docker_gen_container)" ]] && ! is_docker_gen_container "$(get_nginx_proxy_container)"; then
        echo "Error: can't get docker-gen container id !" >&2
        echo "If you are running a three containers setup, check that you are doing one of the following :" >&2
        echo -e "\t- Set the NGINX_DOCKER_GEN_CONTAINER env var on the letsencrypt-companion container to the name of the docker-gen container." >&2
        echo -e "\t- Label the docker-gen container to use with 'com.github.jrcs.letsencrypt_nginx_proxy_companion.docker_gen.'" >&2
        exit 1
    fi
    check_writable_directory '/etc/nginx/certs'
    check_writable_directory '/etc/nginx/vhost.d'
    check_writable_directory '/usr/share/nginx/html'
    check_dh_group
fi

exec "$@"
