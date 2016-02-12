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
            export NGINX_PROXY_CID=$cid
            break
        fi
    done
    if [[ -z "${NGINX_PROXY_CID:-}" ]]; then
        echo "Error: can't get nginx-proxy container id !" >&2
        echo "Check that you use the --volumes-from option to mount volumes from the nginx-proxy." >&2
        exit 1
    fi
}

function check_writable_directory {
    local dir="$1"
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

function create_nginx_config {
	# Since NGINX does not support environment variables
	echo "Creating nginx config file..."
	cat > .nginx_location.conf <<-'EOF'
	# Generated through environment variable upon creation
	location /.well-known/ {
		auth_basic off;
		root $CHALLENGE_PATH;
		try_files $uri =404;
	}
EOF
}

function check_dh_group {
    if [[ ! -f $CERT_PATH/dhparam.pem ]]; then
        echo "Creating Diffie-Hellman group (can take several minutes...)"
        openssl dhparam -out $CERT_PATH/.dhparam.pem.tmp 2048 2>/dev/null
        mv $CERT_PATH/.dhparam.pem.tmp $CERT_PATH/dhparam.pem || exit 1
    fi
}

source /app/functions.lib

[[ $DEBUG == true ]] && set -x

if [[ "$*" == "/bin/bash /app/start.sh" ]]; then
    check_docker_socket
    get_nginx_proxy_cid
    check_writable_directory ${CERT_PATH:='/etc/nginx/certs'}
    check_writable_directory ${VHOST_PATH:='/etc/nginx/vhost.d'} 
    check_writable_directory ${CHALLENGE_PATH:='/usr/share/nginx/html'} 
	create_nginx_config
    check_dh_group
fi

exec "$@"
