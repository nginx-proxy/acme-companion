#!/bin/bash

## Test for standalone certificates by NGINX container env variables

if [[ -z $TRAVIS_CI ]]; then
  le_container_name="$(basename ${0%/*})_$(date "+%Y-%m-%d_%H.%M.%S")"
else
  le_container_name="$(basename ${0%/*})"
fi
run_le_container ${1:?} "$le_container_name"

# Create the $domains array from comma separated domains in TEST_DOMAINS.
IFS=',' read -r -a domains <<< "$TEST_DOMAINS"

# Cleanup function with EXIT trap
function cleanup {
  # Remove any remaining Nginx container(s) silently.
  i=1
  for hosts in "${letsencrypt_hosts[@]}"; do
    docker rm --force "test$i" > /dev/null 2>&1
    i=$(( $i + 1 ))
  done
  # Cleanup the files created by this run of the test to avoid foiling following test(s).
  docker exec "$le_container_name" bash -c 'rm -rf /etc/nginx/certs/le?.wtf*'
  # Stop the LE container
  docker stop "$le_container_name" > /dev/null
}
trap cleanup EXIT

# Create three different comma separated list from the first three domains in $domains.
# testing for regression on spaced lists https://github.com/JrCs/docker-letsencrypt-nginx-proxy-companion/issues/288
# and with trailing comma https://github.com/JrCs/docker-letsencrypt-nginx-proxy-companion/issues/254
letsencrypt_hosts=( \
  [0]="${domains[0]},${domains[1]},${domains[2]}" \     #straight comma separated list
  [1]="${domains[1]}, ${domains[2]}, ${domains[0]}" \   #comma separated list with spaces
  [2]="${domains[2]}, ${domains[0]}, ${domains[1]}," )  #comma separated list with spaces and a trailing comma

i=1

for hosts in "${letsencrypt_hosts[@]}"; do

  # Get the base domain (first domain of the list).
  base_domain="$(get_base_domain "$hosts")"
  container="test$i"

  # Run an Nginx container passing one of the comma separated list as LETSENCRYPT_HOST env var.
  docker run --rm -d \
    --name "$container" \
    -e "VIRTUAL_HOST=${TEST_DOMAINS}" \
    -e "LETSENCRYPT_HOST=${hosts}" \
    -e "LETSENCRYPT_STANDALONE_CERTS=true" \
    --network boulder_bluenet \
    nginx:alpine > /dev/null && echo "Started test web server for $hosts"

  for domain in "${domains[@]}"; do
      ## For all the domains in the $domains array ...
      wait_for_symlink "${domain}" "$le_container_name"
      created_cert="$(docker exec "$le_container_name" \
        openssl x509 -in /etc/nginx/certs/${domain}/cert.pem -text -noout)"
      # ... as well as the certificate fingerprint.
      created_cert_fingerprint="$(docker exec "$le_container_name" \
        sh -c "openssl x509 -in "/etc/nginx/certs/${domain}/cert.pem" -fingerprint -noout")"

    # Check if the domain is on the certificate.
    if grep -q "$domain" <<< "$created_cert"; then
      echo "$domain is on certificate."
      for otherdomain in "${domains[@]}"; do
        if [ "$domain" != "$otherdomain" ]; then
          if grep -q "$otherdomain" <<< "$created_cert"; then
            echo "$otherdomain is on certificate for $domain, but it must not!"
          else
            echo "$otherdomain did not appear on certificate for $domain."
          fi
        fi
      done
    else
      echo "$domain did not appear on certificate."
    fi

    # Wait for a connection to https://domain then grab the served certificate in text form.
    wait_for_conn --domain "$domain"
    served_cert_fingerprint="$(echo \
      | openssl s_client -showcerts -servername $domain -connect $domain:443 2>/dev/null \
      | openssl x509 -fingerprint -noout)"


    # Compare the cert on file and what we got from the https connection.
    # If not identical, display a full diff.
    if [ "$created_cert_fingerprint" != "$served_cert_fingerprint" ]; then
      echo "Nginx served an incorrect certificate for $domain."
      served_cert="$(echo \
        | openssl s_client -showcerts -servername "$domain" -connect "$domain:443" 2>/dev/null \
        | openssl x509 -text -noout \
        | sed 's/ = /=/g' )"
      diff -u <(echo "$created_cert" | sed 's/ = /=/g') <(echo "$served_cert")
    else
      echo "The correct certificate for $domain was served by Nginx."
    fi
  done

  docker stop "$container" > /dev/null 2>&1
  docker exec "$le_container_name" bash -c 'rm -rf /etc/nginx/certs/le?.wtf*'
  i=$(( $i + 1 ))

done
