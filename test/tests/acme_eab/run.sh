#!/bin/bash

## Test for ACME External Account Binding (EAB).

declare -A eab=( \
  [kid-1]=zWNDZM6eQGHWpSRTPal5eIUYFTu7EajVIoguysqZ9wG44nMEtx3MUAsUDkMTQ12W \
  [kid-2]=b10lLJs8l1GPIzsLP0s6pMt8O0XVGnfTaCeROxQM0BIt2XrJMDHJZBM5NuQmQJQH \
)

if [[ -z $GITHUB_ACTIONS ]]; then
  le_container_name="$(basename "${0%/*}")_$(date "+%Y-%m-%d_%H.%M.%S")"
else
  le_container_name="$(basename "${0%/*}")"
fi
run_le_container "${1:?}" "$le_container_name" \
  --cli-args "--env ACME_EAB_KID=kid-1" \
  --cli-args "--env ACME_EAB_HMAC_KEY=${eab[kid-1]}"

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

# Run an nginx container for ${domains[0]}.
run_nginx_container --hosts "${domains[0]}"

# Run an nginx container for ${domains[1]} with LETSENCRYPT_EMAIL and ACME_EAB_* set.
container_email="contact@${domains[1]}"
run_nginx_container --hosts "${domains[1]}"  \
  --cli-args "--env LETSENCRYPT_EMAIL=${container_email}" \
  --cli-args "--env ACME_EAB_KID=kid-2" \
  --cli-args "--env ACME_EAB_HMAC_KEY=${eab[kid-2]}"

# Wait for a symlink at /etc/nginx/certs/${domains[0]}.crt
wait_for_symlink "${domains[0]}" "$le_container_name"

# Test if the expected file is there.
config_path="/etc/acme.sh/default/ca/$ACME_CA"
json_file="${config_path}/account.json"
conf_file="${config_path}/ca.conf"
if docker exec "$le_container_name" [[ ! -f "$json_file" ]]; then
  echo "The $json_file file does not exist."
elif ! docker exec "$le_container_name" grep -q "${eab[kid-1]}" "$conf_file"; then
  echo "There correct EAB HMAC key isn't on ${conf_file}."
fi

# Wait for a symlink at /etc/nginx/certs/${domains[1]}.crt
wait_for_symlink "${domains[1]}" "$le_container_name"

# Test if the expected file is there.
config_path="/etc/acme.sh/${container_email}/ca/$ACME_CA"
json_file="${config_path}/account.json"
conf_file="${config_path}/ca.conf"
if docker exec "$le_container_name" [[ ! -f "$json_file" ]]; then
  echo "The $json_file file does not exist."
elif ! docker exec "$le_container_name" grep -q "${eab[kid-2]}" "$conf_file"; then
  echo "There correct EAB HMAC key isn't on ${conf_file}."
fi

# Stop the nginx containers silently.
docker stop "${domains[0]}" &> /dev/null
docker stop "${domains[1]}" &> /dev/null
