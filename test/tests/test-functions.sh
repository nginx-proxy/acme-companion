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
  docker run -d \
    --name "$name" \
    --volumes-from $NGINX_CONTAINER_NAME \
    --volume /var/run/docker.sock:/var/run/docker.sock:ro \
    --env "DEBUG=true" \
    --env "ACME_CA_URI=http://${BOULDER_IP}:4000/directory" \
    --label com.github.jrcs.letsencrypt_nginx_proxy_companion.test_suite \
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
    if [ $i -gt 180 ]; then
      echo "Symlink for $domain certificate was not generated under three minutes, timing out."
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

# Wait for the /etc/nginx/certs/$1.crt file to be removed inside container $2
function wait_for_symlink_rm {
  local domain="${1:?}"
  local name="${2:?}"
  local i=0
  until docker exec "$name" [ ! -f "/etc/nginx/certs/$domain.crt" ]; do
    if [ $i -gt 120 ]; then
      echo "Certificate symlink for $domain was not removed under two minutes, timing out."
      return 1
    fi
    i=$((i + 2))
    sleep 2
  done
  echo "Symlink to $domain certificate has been removed."
}
export -f wait_for_symlink_rm

# Wait for a successful https connection to domain $1
function wait_for_conn {
  local domain="${1:?}"
  local i=0
  until curl -k https://"$domain" > /dev/null 2>&1; do
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
