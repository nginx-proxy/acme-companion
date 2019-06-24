#!/bin/bash

## Test for the /app/force_renew script.

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
  # Remove the Nginx container silently.
  docker rm --force "${domains[0]}" > /dev/null 2>&1
  # Cleanup the files created by this run of the test to avoid foiling following test(s).
  docker exec "$le_container_name" bash -c 'rm -rf /etc/nginx/certs/le?.wtf*'
  # Stop the LE container
  docker stop "$le_container_name" > /dev/null
}
trap cleanup EXIT

# Run a nginx container for ${domains[0]}.
docker run --rm -d \
  --name "${domains[0]}" \
  -e "VIRTUAL_HOST=${domains[0]}" \
  -e "LETSENCRYPT_HOST=${domains[0]}" \
  --network boulder_bluenet \
  nginx:alpine > /dev/null && echo "Started test web server for ${domains[0]}"

# Wait for a symlink at /etc/nginx/certs/${domains[0]}.crt
# Grab the expiration time of the certificate
wait_for_symlink "${domains[0]}" "$le_container_name"
first_cert_expire="$(get_cert_expiration_epoch "${domains[0]}" "$le_container_name")"

# Just to be sure
sleep 5

# Issue a forced renewal
# Grab the expiration time of the renewed certificate
docker exec "$le_container_name" /app/force_renew > /dev/null 2>&1
second_cert_expire="$(get_cert_expiration_epoch "${domains[0]}" "$le_container_name")"

if [[ $second_cert_expire -gt $first_cert_expire ]]; then
  echo "Certificate for ${domains[0]} was correctly renewed."
else
  echo "Certificate for ${domains[0]} was not correctly renewed."
  echo "First certificate expiration epoch : $first_cert_expire."
  echo "Second certificate expiration epoch : $second_cert_expire."
fi
