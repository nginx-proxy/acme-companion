#!/bin/bash

## Test for single domain certificates.

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
  for domain in "${domains[@]}"; do
    docker rm --force "$domain" &> /dev/null
  done
  # Cleanup the files created by this run of the test to avoid foiling following test(s).
  docker exec "$le_container_name" /app/cleanup_test_artifacts
  # Stop the LE container
  docker stop "$le_container_name" > /dev/null
}
trap cleanup EXIT

# Run a separate nginx container for each domain in the $domains array.
# Start all the containers in a row so that docker-gen debounce timers fire only once.
for domain in "${domains[@]}"; do
  run_nginx_container --hosts "$domain"
done

for domain in "${domains[@]}"; do

  # Wait for a symlink at /etc/nginx/certs/$domain.crt
  if wait_for_symlink "$domain" "$le_container_name" "./${domain}/fullchain.pem" ; then
    # then grab the certificate in text form from the file ...
    created_cert="$(docker exec "$le_container_name" \
      openssl x509 -in "/etc/nginx/certs/${domain}/cert.pem" -text -noout)"
    # ... as well as the certificate fingerprint.
    created_cert_fingerprint="$(docker exec "$le_container_name" \
      openssl x509 -in "/etc/nginx/certs/${domain}/cert.pem" -fingerprint -noout)"
  fi


  # Check if the domain is on the certificate.
  if ! grep -q "$domain" <<< "$created_cert"; then
    echo "Domain $domain isn't on certificate."
  elif [[ "${DRY_RUN:-}" == 1 ]]; then
    echo "Domain $domain is on certificate."
  fi

  # Wait for a connection to https://domain then grab the served certificate fingerprint.
  wait_for_conn --domain "$domain"
  served_cert_fingerprint="$(echo \
    | openssl s_client -showcerts -servername "$domain" -connect "$domain:443" 2>/dev/null \
    | openssl x509 -fingerprint -noout)"

  # Compare fingerprints from the cert on file and what we got from the https connection.
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

  # Stop the Nginx container silently.
  docker stop "$domain" > /dev/null
done
