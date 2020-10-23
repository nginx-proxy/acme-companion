#!/bin/bash

set -e

# Get the first domain of a comma separated list.
function get_base_domain {
  awk -F ',' '{print $1}' <<< "${1:?}" | tr -d ' ' | sed 's/\.$//'
}
export -f get_base_domain


# Run a letsencrypt-nginx-proxy-companion container
function run_le_container {
  local image="${1:?}"
  local name="${2:?}"
  local cli_args_str="${3:-}"
  local -a cli_args_arr
  for arg in $cli_args_str; do
    cli_args_arr+=("$arg")
  done

  if [[ "$SETUP" == '3containers' ]]; then
    cli_args_arr+=(--env "NGINX_DOCKER_GEN_CONTAINER=$DOCKER_GEN_CONTAINER_NAME")
  fi
  
  if docker run -d \
    --name "$name" \
    --volumes-from "$NGINX_CONTAINER_NAME" \
    --volume /var/run/docker.sock:/var/run/docker.sock:ro \
    "${cli_args_arr[@]}" \
    --env "DHPARAM_BITS=256" \
    --env "DEBUG=2" \
    --env "ACME_CA_URI=http://boulder:4001/directory" \
    --label com.github.jrcs.letsencrypt_nginx_proxy_companion.test_suite \
    --network boulder_bluenet \
    "$image" > /dev/null; \
  then
    [[ "${DRY_RUN:-}" == 1 ]] && echo "Started letsencrypt container for test ${name%%_2*}"
  else
    echo "Could not start letsencrypt container for test ${name%%_2*}"
    return 1
  fi
  return 0
}
export -f run_le_container

# Run an nginx container
function run_nginx_container {
  local le_host="${1:?}"
  local virtual_host="${le_host// /}"; virtual_host="${virtual_host//.,/,}"; virtual_host="${virtual_host%,}"
  local container_name="${2:-$virtual_host}"
  [[ "${DRY_RUN:-}" == 1 ]] && echo "Starting $container_name nginx container, with environment variables VIRTUAL_HOST=$virtual_host and LETSENCRYPT_HOST=$le_host"
  if docker run --rm -d \
    --name "$container_name" \
    -e "VIRTUAL_HOST=$virtual_host" \
    -e "LETSENCRYPT_HOST=$le_host" \
    --network boulder_bluenet \
    nginx:alpine > /dev/null ; \
  then
    [[ "${DRY_RUN:-}" == 1 ]] && echo "Started $container_name nginx container."
  else
    echo "Failed to start test web server for $le_host"
    return 1
  fi
  return 0
}
export -f run_nginx_container


# Wait for the /etc/nginx/conf.d/standalone-cert-$1.conf file to exist inside container $2
function wait_for_standalone_conf {
  local domain="${1:?}"
  local name="${2:?}"
  local timeout
  timeout="$(date +%s)"
  timeout="$((timeout + 60))"
  local target
  until docker exec "$name" [ -f "/etc/nginx/conf.d/standalone-cert-$domain.conf" ]; do
    if [[ "$(date +%s)" -gt "$timeout" ]]; then
      echo "Standalone configuration file for $domain was not generated under one minute, timing out."
      return 1
    fi
    sleep 0.1
  done
}
export -f wait_for_standalone_conf


# Wait for the /etc/nginx/certs/$1.crt symlink to exist inside container $2
function wait_for_symlink {
  local domain="${1:?}"
  local name="${2:?}"
  local expected_target="${3:-}"
  local timeout
  timeout="$(date +%s)"
  timeout="$((timeout + 60))"
  local target
  until docker exec "$name" [ -L "/etc/nginx/certs/$domain.crt" ]; do
    if [[ "$(date +%s)" -gt "$timeout" ]]; then
      echo "Symlink for $domain certificate was not generated under one minute, timing out."
      return 1
    fi
    sleep 0.1
  done
  [[ "${DRY_RUN:-}" == 1 ]] && echo "Symlink to $domain certificate has been generated."
  if [[ -n "$expected_target" ]]; then
    target="$(docker exec "$name" readlink "/etc/nginx/certs/$domain.crt")"
    if [[ "$target" != "$expected_target" ]]; then
      echo "The symlink to the $domain certificate is expected to point to $expected_target but point to $target instead."
      return 1
    elif [[ "${DRY_RUN:-}" == 1 ]]; then
      echo "The symlink is pointing to the file $target"
    fi
  fi
  return 0
}
export -f wait_for_symlink


# Wait for the /etc/nginx/certs/$1.crt symlink to be removed inside container $2
function wait_for_symlink_rm {
  local domain="${1:?}"
  local name="${2:?}"
  local timeout
  timeout="$(date +%s)"
  timeout="$((timeout + 60))"
  until docker exec "$name" [ ! -L "/etc/nginx/certs/$domain.crt" ]; do
    if [[ "$(date +%s)" -gt "$timeout" ]]; then
      echo "Certificate symlink for $domain was not removed under one minute, timing out."
      return 1
    fi
    sleep 0.1
  done
  [[ "${DRY_RUN:-}" == 1 ]] && echo "Symlink to $domain certificate has been removed."
  return 0
}
export -f wait_for_symlink_rm


# Attempt to grab the certificate from domain passed with -d/--domain
# then check if the subject either match or doesn't match the pattern
# passed with either -m/--match or -nm/--no-match
# If domain can't be reached return 1
function check_cert_subj {
  while [[ $# -gt 0 ]]; do
  local flag="$1"

    case $flag in
      -d|--domain)
      local domain="${2:?}"
      shift
      shift
      ;;

      -m|--match)
      local re="${2:?}"
      local match_rc=0
      local no_match_rc=1
      shift
      shift
      ;;

      -n|--no-match)
      local re="${2:?}"
      local match_rc=1
      local no_match_rc=0
      shift
      shift
      ;;

      *) #Unknown option
      shift
      ;;
    esac
  done

  if curl -k https://"$domain" &> /dev/null; then
    local cert_subject
    cert_subject="$(echo \
      | openssl s_client -showcerts -servername "$domain" -connect "$domain:443" 2>/dev/null \
      | openssl x509 -subject -noout)"
  else
    return 1
  fi

  if [[ "$cert_subject" =~ $re ]]; then
    return $match_rc
  else
    return $no_match_rc
  fi
}
export -f check_cert_subj


# Wait for a successful https connection to domain passed with -d/--domain then wait
#   - until the served certificate isn't the default one (default behavior)
#   - until the served certificate is the default one (--default-cert)
#   - until the served certificate subject match a string (--subject-match)
function wait_for_conn {
  local action
  local domain
  local string

  while [[ $# -gt 0 ]]; do
  local flag="$1"

    case $flag in
      -d|--domain)
      domain="${2:?}"
      shift
      shift
      ;;

      --default-cert)
      action='--match'
      shift
      ;;

      --subject-match)
      action='--match'
      string="$2"
      shift
      shift
      ;;

      *) #Unknown option
      shift
      ;;
    esac
  done

  local timeout
  timeout="$(date +%s)"
  timeout="$((timeout + 60))"
  action="${action:---no-match}"
  string="${string:-letsencrypt-nginx-proxy-companion}"

  until check_cert_subj --domain "$domain" "$action" "$string"; do
    if [[ "$(date +%s)" -gt "$timeout" ]]; then
      echo "Could not connect to $domain using https under two minutes, timing out."
      return 1
    fi
    sleep 0.1
  done
  [[ "${DRY_RUN:-}" == 1 ]] && echo "Connection to $domain using https was successful."
  return 0
}
export -f wait_for_conn


# Get the expiration date in unix epoch of domain $1 inside container $2
function get_cert_expiration_epoch {
  local domain="${1:?}"
  local name="${2:?}"
  local cert_expiration
  cert_expiration="$(docker exec "$name" openssl x509 -noout -enddate -in "/etc/nginx/certs/$domain.crt")"
  cert_expiration="$(echo "$cert_expiration" | cut -d "=" -f 2)"
  if [[ "$(uname)" == 'Darwin' ]]; then
    cert_expiration="$(date -j -f "%b %d %T %Y %Z" "$cert_expiration" "+%s")"
  else
    cert_expiration="$(date -d "$cert_expiration" "+%s")"
  fi
  echo "$cert_expiration"
}
export -f get_cert_expiration_epoch
