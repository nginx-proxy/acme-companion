#!/bin/bash

## Test for single domain certificates.

if [[ -z $TRAVIS ]]; then
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
  for domain in "${domains[@]}"; do
    docker rm --force "$domain" > /dev/null 2>&1
  done
  # Cleanup the files created by this run of the test to avoid foiling following test(s).
  docker exec "$le_container_name" bash -c 'rm -rf /etc/nginx/certs/le?.wtf*'
  # Stop the LE container
  docker stop "$le_container_name" > /dev/null
}
trap cleanup EXIT

# Run a separate nginx container for each domain in the $domains array.
# Start all the containers in a row so that docker-gen debounce timers fire only once.
for domain in "${domains[@]}"; do
  docker run --rm -d \
    --name "$domain" \
    -e "VIRTUAL_HOST=${domain}" \
    -e "LETSENCRYPT_HOST=${domain}" \
    --network boulder_bluenet \
    nginx:alpine > /dev/null && echo "Started test web server for $domain"
done

for domain in "${domains[@]}"; do

  # Wait for a symlink at /etc/nginx/certs/$domain.crt
  # then grab the certificate in text form from the file ...
  wait_for_symlink "$domain" "$le_container_name"
  created_cert="$(docker exec "$le_container_name" \
    sh -c "openssl x509 -in "/etc/nginx/certs/${domain}/cert.pem" -text -noout")"
  # ... as well as the certificate fingerprint.
  created_cert_fingerprint="$(docker exec "$le_container_name" \
    sh -c "openssl x509 -in "/etc/nginx/certs/${domain}/cert.pem" -fingerprint -noout")"

  # Check if the domain is on the certificate.
  if grep -q "$domain" <<< "$created_cert"; then
    echo "Domain $domain is on certificate."
  else
    echo "Domain $domain isn't on certificate."
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
    diff -u <(echo "$created_cert" | sed 's/ = /=/g') <(echo "$served_cert")
  else
    echo "The correct certificate for $domain was served by Nginx."
  fi

  # Stop the Nginx container silently.
  docker stop "$domain" > /dev/null
done
