#!/bin/bash

## Test for the LETSENCRYPT_MIN_VALIDITY environment variable.

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
# Default validity
docker run --rm -d \
  --name "${domains[0]}" \
  -e "VIRTUAL_HOST=${domains[0]}" \
  -e "LETSENCRYPT_HOST=${domains[0]}" \
  --network boulder_bluenet \
  nginx:alpine > /dev/null && echo "Started test web server for ${domains[0]}"
# Manual validity (same as default)
docker run --rm -d \
  --name "${domains[1]}" \
  -e "VIRTUAL_HOST=${domains[1]}" \
  -e "LETSENCRYPT_HOST=${domains[1]}" \
  -e "LETSENCRYPT_MIN_VALIDITY=2592000" \
  --network boulder_bluenet \
  nginx:alpine > /dev/null && echo "Started test web server for ${domains[1]}"
# Manual validity (few seconds shy of MIN_VALIDITY_CAP=7603200)
docker run --rm -d \
  --name "${domains[2]}" \
  -e "VIRTUAL_HOST=${domains[2]}" \
  -e "LETSENCRYPT_HOST=${domains[2]}" \
  -e "LETSENCRYPT_MIN_VALIDITY=7603190" \
  --network boulder_bluenet \
  nginx:alpine > /dev/null && echo "Started test web server for ${domains[2]}"

# Wait for a symlinks
wait_for_symlink "${domains[0]}" "$le_container_name"
wait_for_symlink "${domains[1]}" "$le_container_name"
wait_for_symlink "${domains[2]}" "$le_container_name"
# Grab the expiration times of the certificates
first_cert_expire_1="$(get_cert_expiration_epoch "${domains[0]}" "$le_container_name")"
first_cert_expire_2="$(get_cert_expiration_epoch "${domains[1]}" "$le_container_name")"
first_cert_expire_3="$(get_cert_expiration_epoch "${domains[2]}" "$le_container_name")"

# Wait for ${domains[2]} set certificate validity to expire
sleep 10

# Manually trigger letsencrypt_service
docker exec "$le_container_name" /bin/bash -c "source /app/letsencrypt_service --source-only; update_certs" > /dev/null 2>&1

# Grab the new expiration times of the certificates
second_cert_expire_1="$(get_cert_expiration_epoch "${domains[0]}" "$le_container_name")"
second_cert_expire_2="$(get_cert_expiration_epoch "${domains[1]}" "$le_container_name")"
second_cert_expire_3="$(get_cert_expiration_epoch "${domains[2]}" "$le_container_name")"

if [[ $second_cert_expire_1 -eq $first_cert_expire_1 ]]; then
  echo "Certificate for ${domains[0]} was not renewed."
else
  echo "Certificate for ${domains[0]} was incorrectly renewed."
  echo "First certificate expiration epoch : $first_cert_expire_1."
  echo "Second certificate expiration epoch : $second_cert_expire_1."
fi
if [[ $second_cert_expire_2 -eq $first_cert_expire_2 ]]; then
  echo "Certificate for ${domains[1]} was not renewed."
else
  echo "Certificate for ${domains[1]} was incorrectly renewed."
  echo "First certificate expiration epoch : $first_cert_expire_2."
  echo "Second certificate expiration epoch : $second_cert_expire_2."
fi
if [[ $second_cert_expire_3 -gt $first_cert_expire_3 ]]; then
  echo "Certificate for ${domains[2]} was renewed."
else
  echo "Certificate for ${domains[2]} was not renewed."
  echo "First certificate expiration epoch : $first_cert_expire_3."
  echo "Second certificate expiration epoch : $second_cert_expire_3."
fi
