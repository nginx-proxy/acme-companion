#!/bin/bash

## Test for ACME External Account Binding (EAB).

declare -A eab=( \
  [kid-1]=zWNDZM6eQGHWpSRTPal5eIUYFTu7EajVIoguysqZ9wG44nMEtx3MUAsUDkMTQ12W \
  [kid-2]=b10lLJs8l1GPIzsLP0s6pMt8O0XVGnfTaCeROxQM0BIt2XrJMDHJZBM5NuQmQJQH \
)

if [[ -z ${GITHUB_ACTIONS} ]]; then
  le_container_name="$(basename "${0%/*}")_$(date "+%Y-%m-%d_%H.%M.%S")"
else
  le_container_name="$(basename "${0%/*}")"
fi

# Create the ${domains} array from comma separated domains in TEST_DOMAINS.
IFS=',' read -r -a domains <<< "${TEST_DOMAINS}"

# Run the acme-companion container with the EAB environment variables and DEFAULT_EMAIL set.
default_email="contact@${domains[0]}"
run_le_container "${1:?}" "${le_container_name}" \
  --cli-args "--env DEFAULT_EMAIL=${default_email}" \
  --cli-args "--env ACME_EAB_KID=kid-1" \
  --cli-args "--env ACME_EAB_HMAC_KEY=${eab[kid-1]}"

# Cleanup function with EXIT trap
function cleanup {
  # Remove any remaining Nginx container(s) silently.
  for domain in "${domains[@]}"; do
    docker rm --force "${domain}" &> /dev/null
  done
  # Cleanup the files created by this run of the test to avoid foiling following test(s).
  docker exec "${le_container_name}" /app/cleanup_test_artifacts
  # Stop the LE container
  docker stop "${le_container_name}" > /dev/null
}
trap cleanup EXIT

# Run an nginx container for ${domains[0]}.
run_nginx_container --hosts "${domains[0]}"

# Run an nginx container for ${domains[1]} with ACME_EMAIL and ACME_EAB_* set.
container_email="contact@${domains[1]}"
run_nginx_container --hosts "${domains[1]}"  \
  --cli-args "--env ACME_EMAIL=${container_email}" \
  --cli-args "--env ACME_EAB_KID=kid-2" \
  --cli-args "--env ACME_EAB_HMAC_KEY=${eab[kid-2]}"

# Wait for a symlink at /etc/nginx/certs/${domains[0]}.crt
wait_for_symlink "${domains[0]}" "${le_container_name}"

# Test if the expected file is there.
config_path="/etc/acme.sh/${default_email}/ca/${ACME_CA}/dir"
json_file="${config_path}/account.json"
conf_file="${config_path}/ca.conf"
if docker exec "${le_container_name}" [[ ! -d "/etc/acme.sh/${default_email}" ]]; then
  echo "The /etc/acme.sh/${default_email} folder does not exist."
elif docker exec "${le_container_name}" [[ ! -f "${json_file}" ]]; then
  echo "The ${json_file} file does not exist."
elif ! docker exec "${le_container_name}" grep -q "${eab[kid-1]}" "${conf_file}"; then
  echo "The correct EAB HMAC key isn't on ${conf_file}."
elif [[ "$(docker exec "${le_container_name}" jq -r '.contact|.[0]' "${json_file}")" != "mailto:${default_email}" ]]; then
  echo "${default_email} is not set on ${json_file}."
  docker exec "${le_container_name}" jq . "${json_file}"
fi

# Wait for a symlink at /etc/nginx/certs/${domains[1]}.crt
wait_for_symlink "${domains[1]}" "${le_container_name}"

# Test if the expected file is there.
config_path="/etc/acme.sh/${container_email}/ca/${ACME_CA}/dir"
json_file="${config_path}/account.json"
conf_file="${config_path}/ca.conf"
if docker exec "${le_container_name}" [[ ! -d "/etc/acme.sh/${container_email}" ]]; then
  echo "The /etc/acme.sh/${container_email} folder does not exist."
elif docker exec "${le_container_name}" [[ ! -f "${json_file}" ]]; then
  echo "The ${json_file} file does not exist."
elif ! docker exec "${le_container_name}" grep -q "${eab[kid-2]}" "${conf_file}"; then
  echo "The correct EAB HMAC key isn't on ${conf_file}."
elif [[ "$(docker exec "${le_container_name}" jq -r '.contact|.[0]' "${json_file}")" != "mailto:${container_email}" ]]; then
  echo "${container_email} is not set on ${json_file}."
  docker exec "${le_container_name}" jq . "${json_file}"
fi

# Stop the nginx containers silently.
docker stop "${domains[0]}" &> /dev/null
docker stop "${domains[1]}" &> /dev/null
