#!/bin/bash

set -e

# Get the first domain of a comma separated list.
function get_base_domain {
  awk -F ',' '{print $1}' <(echo ${1:?}) | tr -d ' '
}
export -f get_base_domain


# Run a letsencrypt-nginx-proxy-companion container
function run_le_container {
  local image="${1:?}"
  local name="${2:?}"
  local cli_args="${3:-}"
  if [[ "$SETUP" == '3containers' ]]; then
    cli_args+=" --env NGINX_DOCKER_GEN_CONTAINER=$DOCKER_GEN_CONTAINER_NAME"
  fi
  docker run -d \
    --name "$name" \
    --volumes-from $NGINX_CONTAINER_NAME \
    --volume /var/run/docker.sock:/var/run/docker.sock:ro \
    $cli_args \
    --env "DHPARAM_BITS=256" \
    --env "DEBUG=true" \
    --env "ACME_CA_URI=http://boulder:4001/directory" \
    --label com.github.jrcs.letsencrypt_nginx_proxy_companion.test_suite \
    --network boulder_bluenet \
    "$image" > /dev/null && echo "Started letsencrypt container for test ${name%%_2*}"
}
export -f run_le_container


# Wait for the /etc/nginx/certs/$1.crt symlink to exist inside container $2
function wait_for_symlink {
  local domain="${1:?}"
  local name="${2:?}"
  local i=0
  local target
  until docker exec "$name" [ -L "/etc/nginx/certs/$domain.crt" ]; do
    if [ $i -gt 60 ]; then
      echo "Symlink for $domain certificate was not generated under one minute, timing out."
      return 1
    fi
    i=$((i + 2))
    sleep 2
  done
  target="$(docker exec "$name" readlink "/etc/nginx/certs/$domain.crt")"
  echo "Symlink to $domain certificate has been generated."
  echo "The link is pointing to the file $target"
}
export -f wait_for_symlink


# Wait for the /etc/nginx/certs/$1.crt symlink to be removed inside container $2
function wait_for_symlink_rm {
  local domain="${1:?}"
  local name="${2:?}"
  local i=0
  until docker exec "$name" [ ! -L "/etc/nginx/certs/$domain.crt" ]; do
    if [ $i -gt 60 ]; then
      echo "Certificate symlink for $domain was not removed under one minute, timing out."
      return 1
    fi
    i=$((i + 2))
    sleep 2
  done
  echo "Symlink to $domain certificate has been removed."
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

  if curl -k https://"$domain" > /dev/null 2>&1; then
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

  local i=0
  action="${action:---no-match}"
  string="${string:-letsencrypt-nginx-proxy-companion}"

  until check_cert_subj --domain "$domain" "$action" "$string"; do
    if [ $i -gt 120 ]; then
      echo "Could not connect to $domain using https under two minutes, timing out."
      return 1
    fi
    i=$((i + 2))
    sleep 2
  done
  echo "Connection to $domain using https was successful."
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
