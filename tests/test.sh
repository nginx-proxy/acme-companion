#!/bin/bash

set -e

boulder_ip="$(ifconfig docker0 | grep "inet addr:" | cut -d: -f2 | awk '{ print $1}')"

# shellcheck source=test-functions.sh
source ${TRAVIS_BUILD_DIR}/tests/test-functions.sh

echo "Starting $LETSENCRYPT_CONTAINER_NAME container."

case $1 in
  2containers)
    run_le_container $LETSENCRYPT_CONTAINER_NAME $NGINX_CONTAINER_NAME $boulder_ip
    wait_for_dhparam $LETSENCRYPT_CONTAINER_NAME
    ;;
  3containers)
    run_le_container $LETSENCRYPT_CONTAINER_NAME $NGINX_CONTAINER_NAME $boulder_ip
    wait_for_dhparam $LETSENCRYPT_CONTAINER_NAME
    ;;
  *)
    echo "$0 $1: invalid option."
    exit 1
esac

echo "Starting test web server for ${TEST_DOMAINS}."

docker run -d \
  --name webapp-test \
  -e "VIRTUAL_HOST=${TEST_DOMAINS}" \
  -e "VIRTUAL_PORT=80" \
  -e "LETSENCRYPT_HOST=${TEST_DOMAINS}" \
  -e "LETSENCRYPT_EMAIL=foo@bar.com" \
  nginx:alpine

base_domain=$(get_base_domain "$TEST_DOMAINS")

wait_for_cert $base_domain $LETSENCRYPT_CONTAINER_NAME

created_cert="$(docker exec $LETSENCRYPT_CONTAINER_NAME openssl x509 -in /etc/nginx/certs/${base_domain}/cert.pem -text -noout)"

wait_for_conn $base_domain

while IFS=',' read -ra DOMAINS; do
  for domain in "${DOMAINS[@]}"; do
    if grep -q "$domain" <<< "$created_cert"; then
      echo "$domain is on certificate."
    else
      echo "$domain did not appear on certificate."
      exit 1
    fi

    served_cert="$(echo \
      | openssl s_client -showcerts -servername $domain -connect $domain:443 2>/dev/null \
      | openssl x509 -inform pem -text -noout)"

    if [ "$created_cert" != "$served_cert" ]; then
      echo "Nginx served an incorrect certificate for $domain."
      diff -u <"$(echo "$created_cert")" <"$(echo "$served_cert")"
      exit 1
    else
      echo "The correct certificate for $domain was served by Nginx."
    fi
  done
done <<< "$TEST_DOMAINS"

echo "$served_cert"
