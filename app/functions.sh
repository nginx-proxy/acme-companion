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

function ascending_wildcard_locations {
    # Given foo.bar.baz.example.com as argument, will output:
    # - *.bar.baz.example.com
    # - *.baz.example.com
    # - *.example.com
    local domain="${1:?}"
    local first_label
    regex="^[[:alnum:]_\-]+(\.[[:alpha:]]+)?$"
    until [[ "$domain" =~ $regex ]]; do
      first_label="${domain%%.*}"
      domain="${domain/${first_label}./}"
      echo "*.${domain}"
    done
}

function descending_wildcard_locations {
    # Given foo.bar.baz.example.com as argument, will output:
    # - foo.bar.baz.example.*
    # - foo.bar.baz.*
    # - foo.bar.*
    # - foo.*
    local domain="${1:?}"
    local last_label
    regex="^[[:alnum:]_\-]+$"
    until [[ "$domain" =~ $regex ]]; do
      last_label="${domain##*.}"
      domain="${domain/.${last_label}/}"
      echo "${domain}.*"
    done
}

function enumerate_wildcard_locations {
    # Goes through ascending then descending wildcard locations for a given FQDN
    local domain="${1:?}"
    ascending_wildcard_locations "$domain"
    descending_wildcard_locations "$domain"
}

function add_location_configuration {
    local domain="${1:-}"
    local wildcard_domain
    # If no domain was passed use default instead
    [[ -z "$domain" ]] && domain='default'

    # If the domain does not have an exact matching location file, test the possible
    # wildcard locations files. Use default is no location file is present at all.
    if [[ ! -f "${VHOST_DIR}/${domain}" ]]; then
      for wildcard_domain in $(enumerate_wildcard_locations "$domain"); do
        if [[ -f "${VHOST_DIR}/${wildcard_domain}" ]]; then
          domain="$wildcard_domain"
          break
        fi
        domain='default'
      done
    fi

    if [[ -f "${VHOST_DIR}/${domain}" && -n $(sed -n "/$START_HEADER/,/$END_HEADER/p" "${VHOST_DIR}/${domain}") ]]; then
        # If the config file exist and already have the location configuration, end with exit code 0
        return 0
    else
        # Else write the location configuration to a temp file ...
        echo "$START_HEADER" > "${VHOST_DIR}/${domain}".new
        cat /app/nginx_location.conf >> "${VHOST_DIR}/${domain}".new
        echo "$END_HEADER" >> "${VHOST_DIR}/${domain}".new
        # ... append the existing file content to the temp one ...
        [[ -f "${VHOST_DIR}/${domain}" ]] && cat "${VHOST_DIR}/${domain}" >> "${VHOST_DIR}/${domain}".new
        # ... and copy the temp file to the old one (if the destination file is bind mounted, you can't change
        # its inode from within the container, so mv won't work and cp has to be used), then remove the temp file.
        cp -f "${VHOST_DIR}/${domain}".new "${VHOST_DIR}/${domain}" && rm -f "${VHOST_DIR}/${domain}".new
        return 1
    fi
}

function remove_all_location_configurations {
    for file in "${VHOST_DIR}"/*; do
        [[ -e "$file" ]] || continue
        if [[ -n $(sed -n "/$START_HEADER/,/$END_HEADER/p" "$file") ]]; then
            sed "/$START_HEADER/,/$END_HEADER/d" "$file" > "$file".new
            cp -f "$file".new "$file" && rm -f "$file".new
        fi
    done
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
    local self_cid=""

    # Try the /proc files methods first then resort to the Docker API.
    if [[ -f /proc/1/cpuset ]]; then
        self_cid="$(grep -Eo '[[:alnum:]]{64}' /proc/1/cpuset)"
    fi
    if [[ ( ${#self_cid} != 64 ) && ( -f /proc/self/cgroup ) ]]; then
        self_cid="$(grep -Eo -m 1 '[[:alnum:]]{64}' /proc/self/cgroup)"
    fi
    if [[ ( ${#self_cid} != 64 ) ]]; then
        self_cid="$(docker_api "/containers/$(hostname)/json" | jq -r '.Id')"
    fi

    # If it's not 64 characters long, then it's probably not a container ID.
    if [[ ${#self_cid} == 64 ]]; then
        echo "$self_cid"
    else
        echo "$(date "+%Y/%m/%d %T"), Error: can't get my container ID !" >&2
        return 1
    fi
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

function docker_restart {
    local id="${1?missing id}"
    docker_api "/containers/$id/restart" "POST"
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
        elif [[ $(get_self_cid) ]]; then
            volumes_from=$(docker_api "/containers/$(get_self_cid)/json" | jq -r '.HostConfig.VolumesFrom[]' 2>/dev/null)
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

  [[ "$(lc $DEBUG)" == true ]] && echo "Debug: checking $path ownership and permissions."

  # Find the user numeric ID if the FILES_UID environment variable isn't numeric.
  if [[ "$user" =~ ^[0-9]+$ ]]; then
    user_num="$user"
  # Check if this user exist inside the container
  elif id -u "$user" > /dev/null 2>&1; then
    # Convert the user name to numeric ID
    local user_num="$(id -u "$user")"
    [[ "$(lc $DEBUG)" == true ]] && echo "Debug: numeric ID of user $user is $user_num."
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
    [[ "$(lc $DEBUG)" == true ]] && echo "Debug: numeric ID of group $group is $group_num."
  else
    echo "Warning: group $group not found in the container, please use a numeric group ID instead of a group name. Skipping ownership and permissions check."
    return 1
  fi

  # Check and modify ownership if required.
  if [[ -e "$path" ]]; then
    if [[ "$(stat -c %u:%g "$path" )" != "$user_num:$group_num" ]]; then
      [[ "$(lc $DEBUG)" == true ]] && echo "Debug: setting $path ownership to $user:$group."
      if [[ -L "$path" ]]; then
        chown -h "$user_num:$group_num" "$path"
      else
        chown "$user_num:$group_num" "$path"
      fi
    fi
    # If the path is a folder, check and modify permissions if required.
    if [[ -d "$path" ]]; then
      if [[ "$(stat -c %a "$path")" != "$d_perms" ]]; then
        [[ "$(lc $DEBUG)" == true ]] && echo "Debug: setting $path permissions to $d_perms."
        chmod "$d_perms" "$path"
      fi
    # If the path is a file, check and modify permissions if required.
    elif [[ -f "$path" ]]; then
      # Use different permissions for private files (private keys and ACME account files) ...
      if [[ "$path" =~ ^.*(default\.key|key\.pem|\.json)$ ]]; then
        if [[ "$(stat -c %a "$path")" != "$f_perms" ]]; then
          [[ "$(lc $DEBUG)" == true ]] && echo "Debug: setting $path permissions to $f_perms."
          chmod "$f_perms" "$path"
        fi
      # ... and for public files (certificates, chains, fullchains, DH parameters).
      else
        if [[ "$(stat -c %a "$path")" != "644" ]]; then
          [[ "$(lc $DEBUG)" == true ]] && echo "Debug: setting $path permissions to 644."
          chmod "644" "$path"
        fi
      fi
    fi
  else
    echo "Warning: $path does not exist. Skipping ownership and permissions check."
    return 1
  fi
}

# Convert argument to lowercase (bash 4 only)
function lc {
	echo "${@,,}"
}
