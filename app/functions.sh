[[ -z "${VHOST_DIR:-}" ]] && \
 declare -r VHOST_DIR=/etc/nginx/vhost.d
[[ -z "${START_HEADER:-}" ]] && \
 declare -r START_HEADER='## Start of configuration add by letsencrypt container'
[[ -z "${END_HEADER:-}" ]] && \
 declare -r END_HEADER='## End of configuration add by letsencrypt container'

add_location_configuration() {
    local domain="${1:-}"
    [[ -z "$domain" || ! -f "${VHOST_DIR}/${domain}" ]] && domain=default
    [[ -f "${VHOST_DIR}/${domain}" && \
       -n $(sed -n "/$START_HEADER/,/$END_HEADER/p" "${VHOST_DIR}/${domain}") ]] && return 0
    echo "$START_HEADER" > "${VHOST_DIR}/${domain}".new
    cat /app/nginx_location.conf >> "${VHOST_DIR}/${domain}".new
    echo "$END_HEADER" >> "${VHOST_DIR}/${domain}".new
    [[ -f "${VHOST_DIR}/${domain}" ]] && cat "${VHOST_DIR}/${domain}" >> "${VHOST_DIR}/${domain}".new
    mv -f "${VHOST_DIR}/${domain}".new "${VHOST_DIR}/${domain}"
    return 1
}

remove_all_location_configurations() {
    local old_shopt_options=$(shopt -p) # Backup shopt options
    shopt -s nullglob
    for file in "${VHOST_DIR}"/*; do
        [[ -n $(sed -n "/$START_HEADER/,/$END_HEADER/p" "$file") ]] && \
         sed -i "/$START_HEADER/,/$END_HEADER/d" "$file"
    done
    eval "$old_shopt_options" # Restore shopt options
}

## Docker API
function docker_api {
    local scheme
    local curl_opts=(-s)
    local method=${2:-GET}
    # data to POST
    if [[ -n "${3:-}" ]]; then
        curl_opts+=(-d "$3")
    fi
    if [[ -z "$DOCKER_HOST" ]];then
        echo "Error DOCKER_HOST variable not set" >&2
        return 1
    fi
    if [[ $DOCKER_HOST == unix://* ]]; then
        curl_opts+=(--unix-socket ${DOCKER_HOST#unix://})
        scheme='http://localhost'
    else
        scheme="http://${DOCKER_HOST#*://}"
    fi
    [[ $method = "POST" ]] && curl_opts+=(-H 'Content-Type: application/json')
    curl "${curl_opts[@]}" -X${method} ${scheme}$1
}

function docker_exec {
    local id="${1?missing id}"
    local cmd="${2?missing command}"
    local data=$(printf '{ "AttachStdin": false, "AttachStdout": true, "AttachStderr": true, "Tty":false,"Cmd": %s }' "$cmd")
    exec_id=$(docker_api "/containers/$id/exec" "POST" "$data" | jq -r .Id)
    if [[ -n "$exec_id" ]]; then
        docker_api /exec/$exec_id/start "POST" '{"Detach": false, "Tty":false}'
    fi
}

function docker_kill {
    local id="${1?missing id}"
    local signal="${2?missing signal}"
    docker_api "/containers/$id/kill?signal=$signal" "POST"
}

function labeled_cid {
    docker_api "/containers/json" | jq -r '.[] | select( .Labels["'$1'"] == "true")|.Id'
}

function docker_gen_container {
    echo ${NGINX_DOCKER_GEN_CONTAINER:-$(labeled_cid com.github.jrcs.letsencrypt_nginx_proxy_companion.docker_gen)}
}

function nginx_proxy_container {
    echo ${NGINX_PROXY_CONTAINER:-$(labeled_cid com.github.jrcs.letsencrypt_nginx_proxy_companion.nginx_proxy)}
}

## Nginx
reload_nginx() {
    local _docker_gen_container=$(docker_gen_container)
    local _nginx_proxy_container=$(nginx_proxy_container)

    if [[ -n "${_docker_gen_container:-}" ]]; then
        # Using docker-gen and nginx in separate container
        echo "Reloading nginx docker-gen (using separate container ${_docker_gen_container})..."
        docker_kill "${_docker_gen_container}" SIGHUP

        if [[ -n "${_nginx_proxy_container:-}" ]]; then
            # Reloading nginx in case only certificates had been renewed
            echo "Reloading nginx (using separate container ${_nginx_proxy_container})..."
            docker_kill "${_nginx_proxy_container}" SIGHUP
        fi
    else
        if [[ -n "${_nginx_proxy_container:-}" ]]; then
            echo "Reloading nginx proxy (${_nginx_proxy_container})..."
            docker_exec "${_nginx_proxy_container}" \
                        '[ "sh", "-c", "/usr/local/bin/docker-gen -only-exposed /app/nginx.tmpl /etc/nginx/conf.d/default.conf; /usr/sbin/nginx -s reload" ]'
        fi
    fi
}

# Convert argument to lowercase (bash 4 only)
function lc() {
	echo "${@,,}"
}
