#!/bin/bash
# shellcheck disable=SC2155

[[ -z "${VHOST_DIR:-}" ]] && \
 declare -r VHOST_DIR=/etc/nginx/vhost.d
[[ -z "${START_HEADER:-}" ]] && \
 declare -r START_HEADER='## Start of configuration add by letsencrypt container'
[[ -z "${END_HEADER:-}" ]] && \
 declare -r END_HEADER='## End of configuration add by letsencrypt container'

function check_nginx_proxy_container_run {
    local _nginx_proxy_container=$(get_nginx_proxy_container)
    if [[ -n "$_nginx_proxy_container" ]]; then
        if [[ $(docker_api "/containers/${_nginx_proxy_container}/json" | jq -r '.State.Status') = "running" ]];then
            return 0
        else
            echo "$(date "+%Y/%m/%d %T") Error: nginx-proxy container ${_nginx_proxy_container} isn't running." >&2
            return 1
        fi
    else
        echo "$(date "+%Y/%m/%d %T") Error: could not get a nginx-proxy container ID." >&2
        return 1
fi
}

function add_location_configuration {
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

function remove_all_location_configurations {
    local old_shopt_options=$(shopt -p) # Backup shopt options
    shopt -s nullglob
    for file in "${VHOST_DIR}"/*; do
        [[ -n $(sed -n "/$START_HEADER/,/$END_HEADER/p" "$file") ]] && \
         sed -i "/$START_HEADER/,/$END_HEADER/d" "$file"
    done
    eval "$old_shopt_options" # Restore shopt options
}

function check_cert_min_validity {
    # Check if a certificate ($1) is still valid for a given amount of time in seconds ($2).
    # Returns 0 if the certificate is still valid for this amount of time, 1 otherwise.
    local cert_path="$1"
    local min_validity="$(( $(date "+%s") + $2 ))"

    local cert_expiration
    cert_expiration="$(openssl x509 -noout -enddate -in "$cert_path" | cut -d "=" -f 2)"
    cert_expiration="$(date --utc --date "${cert_expiration% GMT}" "+%s")"

    [[ $cert_expiration -gt $min_validity ]] || return 1
}

function get_self_cid {
    DOCKER_PROVIDER=${DOCKER_PROVIDER:-docker}

    case "${DOCKER_PROVIDER}" in
    ecs|ECS)
        # AWS ECS. Enabled in /etc/ecs/ecs.config (http://docs.aws.amazon.com/AmazonECS/latest/developerguide/container-metadata.html)
        if [[ -n "${ECS_CONTAINER_METADATA_FILE:-}" ]]; then
            grep ContainerID "${ECS_CONTAINER_METADATA_FILE}" | sed 's/.*: "\(.*\)",/\1/g'
        else
            echo "${DOCKER_PROVIDER} specified as 'ecs' but not available. See: http://docs.aws.amazon.com/AmazonECS/latest/developerguide/container-metadata.html" >&2
            exit 1
        fi
        ;;
    *)
        sed -nE 's/^.+docker[\/-]([a-f0-9]{64}).*/\1/p' /proc/self/cgroup | head -n 1
        ;;
    esac
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
    if [[ -n "$exec_id" && "$exec_id" != "null" ]]; then
        docker_api /exec/$exec_id/start "POST" '{"Detach": false, "Tty":false}'
    else
        echo "$(date "+%Y/%m/%d %T"), Error: can't exec command ${cmd} in container ${id}. Check if the container is running." >&2
        return 1
    fi
}

function docker_kill {
    local id="${1?missing id}"
    local signal="${2?missing signal}"
    docker_api "/containers/$id/kill?signal=$signal" "POST"
}

function labeled_cid {
    docker_api "/containers/json" | jq -r '.[] | select(.Labels["'$1'"])|.Id'
}

function is_docker_gen_container {
    local id="${1?missing id}"
    if [[ $(docker_api "/containers/$id/json" | jq -r '.Config.Env[]' | egrep -c '^DOCKER_GEN_VERSION=') = "1" ]]; then
        return 0
    else
        return 1
    fi
}

function get_docker_gen_container {
    # First try to get the docker-gen container ID from the container label.
    local docker_gen_cid="$(labeled_cid com.github.jrcs.letsencrypt_nginx_proxy_companion.docker_gen)"

    # If the labeled_cid function dit not return anything and the env var is set, use it.
    if [[ -z "$docker_gen_cid" ]] && [[ -n "${NGINX_DOCKER_GEN_CONTAINER:-}" ]]; then
        docker_gen_cid="$NGINX_DOCKER_GEN_CONTAINER"
    fi

    # If a container ID was found, output it. The function will return 1 otherwise.
    [[ -n "$docker_gen_cid" ]] && echo "$docker_gen_cid"
}

function get_nginx_proxy_container {
    local volumes_from
    # First try to get the nginx container ID from the container label.
    local nginx_cid="$(labeled_cid com.github.jrcs.letsencrypt_nginx_proxy_companion.nginx_proxy)"

    # If the labeled_cid function dit not return anything ...
    if [[ -z "${nginx_cid}" ]]; then
        # ... and the env var is set, use it ...
        if [[ -n "${NGINX_PROXY_CONTAINER:-}" ]]; then
            nginx_cid="$NGINX_PROXY_CONTAINER"
        # ... else try to get the container ID with the volumes_from method.
        else
            volumes_from=$(docker_api "/containers/${SELF_CID:-$(get_self_cid)}/json" | jq -r '.HostConfig.VolumesFrom[]' 2>/dev/null)
            for cid in $volumes_from; do
                cid="${cid%:*}" # Remove leading :ro or :rw set by remote docker-compose (thx anoopr)
                if [[ $(docker_api "/containers/$cid/json" | jq -r '.Config.Env[]' | egrep -c '^NGINX_VERSION=') = "1" ]];then
                    nginx_cid="$cid"
                    break
                fi
            done
        fi
    fi

    # If a container ID was found, output it. The function will return 1 otherwise.
    [[ -n "$nginx_cid" ]] && echo "$nginx_cid"
}

## Nginx
function reload_nginx {
    local _docker_gen_container=$(get_docker_gen_container)
    local _nginx_proxy_container=$(get_nginx_proxy_container)

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
                '[ "sh", "-c", "/app/docker-entrypoint.sh /usr/local/bin/docker-gen /app/nginx.tmpl /etc/nginx/conf.d/default.conf; /usr/sbin/nginx -s reload" ]' \
                | sed -rn 's/^.*([0-9]{4}\/[0-9]{2}\/[0-9]{2}.*$)/\1/p'
            [[ ${PIPESTATUS[0]} -eq 1 ]] && echo "$(date "+%Y/%m/%d %T"), Error: can't reload nginx-proxy." >&2
        fi
    fi
}

function set_ownership_and_permissions {
  local path="${1:?}"
  # The default ownership is root:root, with 755 permissions for folders and 644 for files.
  local user="${FILES_UID:-root}"
  local group="${FILES_GID:-$user}"
  local f_perms="${FILES_PERMS:-644}"
  local d_perms="${FOLDERS_PERMS:-755}"

  if [[ ! "$f_perms" =~ ^[0-7]{3,4}$ ]]; then
    echo "Warning : the provided files permission octal ($f_perms) is incorrect. Skipping ownership and permissions check."
    return 1
  fi
  if [[ ! "$d_perms" =~ ^[0-7]{3,4}$ ]]; then
    echo "Warning : the provided folders permission octal ($d_perms) is incorrect. Skipping ownership and permissions check."
    return 1
  fi

  # Find the user numeric ID if the FILES_UID environment variable isn't numeric.
  if [[ "$user" =~ ^[0-9]+$ ]]; then
    user_num="$user"
  # Check if this user exist inside the container
  elif id -u "$user" > /dev/null 2>&1; then
    # Convert the user name to numeric ID
    local user_num="$(id -u "$user")"
    [[ $DEBUG == true ]] && echo "Debug: numeric ID of user $user is $user_num."
  else
    echo "Warning: user $user not found in the container, please use a numeric user ID instead of a user name. Skipping ownership and permissions check."
    return 1
  fi

  # Find the group numeric ID if the FILES_GID environment variable isn't numeric.
  if [[ "$group" =~ ^[0-9]+$ ]]; then
    group_num="$group"
  # Check if this group exist inside the container
  elif getent group "$group" > /dev/null 2>&1; then
    # Convert the group name to numeric ID
    local group_num="$(getent group "$group" | awk -F ':' '{print $3}')"
    [[ $DEBUG == true ]] && echo "Debug: numeric ID of group $group is $group_num."
  else
    echo "Warning: group $group not found in the container, please use a numeric group ID instead of a group name. Skipping ownership and permissions check."
    return 1
  fi

  # Check and modify ownership if required.
  if [[ -e "$path" ]]; then
    if [[ "$(stat -c %u:%g "$path" )" != "$user_num:$group_num" ]]; then
      [[ $DEBUG == true ]] && echo "Debug: setting $path ownership to $user:$group."
      chown "$user_num:$group_num" "$path"
    fi
  else
    echo "Warning: $path does not exist. Skipping ownership and permissions check."
    return 1
  fi

  # If the path is a folder, check and modify permissions if required.
  if [[ -d "$path" ]]; then
    if [[ "$(stat -c %a "$path")" != "$d_perms" ]]; then
      [[ $DEBUG == true ]] && echo "Debug: setting $path permissions to $d_perms."
      chmod "$d_perms" "$path"
    fi
  # If the path is a file, check and modify permissions if required.
elif [[ -f "$path" ]]; then
    # Use different permissions for private files (private keys and ACME account keys) ...
    if [[ "$path" =~ ^.*(default\.key|key\.pem|\.json)$ ]]; then
      if [[ "$(stat -c %a "$path")" != "$f_perms" ]]; then
        [[ $DEBUG == true ]] && echo "Debug: setting $path permissions to $f_perms."
        chmod "$f_perms" "$path"
      fi
    # ... and for public files (certificates, chains, fullchains, DH parameters).
    else
      if [[ "$(stat -c %a "$path")" != "644" ]]; then
        [[ $DEBUG == true ]] && echo "Debug: setting $path permissions to 644."
        chmod "$f_perms" "$path"
      fi
    fi
  fi
}

# Convert argument to lowercase (bash 4 only)
function lc {
	echo "${@,,}"
}
