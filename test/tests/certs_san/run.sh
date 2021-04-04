#!/bin/bash

## Test for SAN (Subject Alternative Names) certificates.

if [[ -z $GITHUB_ACTIONS ]]; then
  le_container_name="$(basename "${0%/*}")_$(date "+%Y-%m-%d_%H.%M.%S")"
else
  le_container_name="$(basename "${0%/*}")"
fi
run_le_container "${1:?}" "$le_container_name"

# Create the $domains array from comma separated domains in TEST_DOMAINS.
IFS=',' read -r -a domains <<< "$TEST_DOMAINS"

# Cleanup function with EXIT trap
function cleanup {
  # Remove any remaining Nginx container(s) silently.
  i=1
  for hosts in "${letsencrypt_hosts[@]}"; do
    docker rm --force "test$i" &> /dev/null
    i=$(( i + 1 ))
  done
  # Cleanup the files created by this run of the test to avoid foiling following test(s).
  docker exec "$le_container_name" /app/cleanup_test_artifacts
  # Stop the LE container
  docker stop "$le_container_name" > /dev/null
}
trap cleanup EXIT

# Create three different comma separated list from the first three domains in $domains.
# testing for regression on spaced lists https://github.com/nginx-proxy/acme-companion/issues/288
# with trailing comma https://github.com/nginx-proxy/acme-companion/issues/254
# and with trailing dot https://github.com/nginx-proxy/acme-companion/issues/676
letsencrypt_hosts=( \
  [0]="${domains[0]},${domains[1]},${domains[2]}" \     #straight comma separated list
  [1]="${domains[1]}, ${domains[2]}, ${domains[0]}" \   #comma separated list with spaces
  [2]="${domains[2]}, ${domains[0]}, ${domains[1]}," \  #comma separated list with spaces and a trailing comma
  [3]="${domains[0]}.,${domains[2]}.,${domains[1]}" )   #trailing dots

i=1

for hosts in "${letsencrypt_hosts[@]}"; do

  # Get the base domain (first domain of the list).
  base_domain="$(get_base_domain "$hosts")"
  container="test$i"

  # Run an Nginx container passing one of the comma separated list as LETSENCRYPT_HOST env var.
  run_nginx_container --hosts "$hosts" --name "$container"

  # Wait for a symlink at /etc/nginx/certs/$base_domain.crt
  if wait_for_symlink "$base_domain" "$le_container_name" "./${base_domain}/fullchain.pem"; then
    # then grab the certificate in text form ...
    created_cert="$(docker exec "$le_container_name" \
      openssl x509 -in "/etc/nginx/certs/${base_domain}/cert.pem" -text -noout)"
    # ... as well as the certificate fingerprint.
    created_cert_fingerprint="$(docker exec "$le_container_name" \
      openssl x509 -in "/etc/nginx/certs/${base_domain}/cert.pem" -fingerprint -noout)"
  fi

  for domain in "${domains[@]}"; do
  ## For all the domains in the $domains array ...

    # Check if the domain is on the certificate.
    if ! grep -q "$domain" <<< "$created_cert"; then
      echo "$domain did not appear on certificate."
    elif [[ "${DRY_RUN:-}" == 1 ]]; then
      echo "$domain is on certificate."
    fi

    # Wait for a connection to https://domain then grab the served certificate in text form.
    wait_for_conn --domain "$domain"
    served_cert_fingerprint="$(echo \
      | openssl s_client -showcerts -servername "$domain" -connect "$domain:443" 2>/dev/null \
      | openssl x509 -fingerprint -noout)"


    # Compare the cert on file and what we got from the https connection.
    # If not identical, display a full diff.
    if [ "$created_cert_fingerprint" != "$served_cert_fingerprint" ]; then
      echo "Nginx served an incorrect certificate for $domain."
      served_cert="$(echo \
        | openssl s_client -showcerts -servername "$domain" -connect "$domain:443" 2>/dev/null \
        | openssl x509 -text -noout \
        | sed 's/ = /=/g' )"
      diff -u <(echo "${created_cert// = /=}") <(echo "$served_cert")
    elif [[ "${DRY_RUN:-}" == 1 ]]; then
       echo "The correct certificate for $domain was served by Nginx."
    fi
  done

  docker stop "$container" &> /dev/null
  docker exec "$le_container_name" /app/cleanup_test_artifacts
  i=$(( i + 1 ))

done
