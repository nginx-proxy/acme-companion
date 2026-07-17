#!/bin/bash

## Test that existing certificate symlinks survive an update_certs run happening
## before docker-gen generated /app/letsencrypt_service_data (issue #956).

if [[ -z ${GITHUB_ACTIONS} ]]; then
  le_container_name="$(basename "${0%/*}")_$(date "+%Y-%m-%d_%H.%M.%S")"
else
  le_container_name="$(basename "${0%/*}")"
fi
run_le_container "${1:?}" "${le_container_name}"

# Use the first domain from the comma separated TEST_DOMAINS.
IFS=',' read -r -a domains <<< "${TEST_DOMAINS}"
domain="${domains[0]}"

# Cleanup function with EXIT trap
function cleanup {
  # Remove the Nginx container silently.
  docker rm --force "${domain}" &> /dev/null
  # Cleanup the files created by this run of the test to avoid foiling following test(s).
  docker exec "${le_container_name}" cleanup_test_artifacts
  # Stop the LE container
  docker stop "${le_container_name}" > /dev/null
}
trap cleanup EXIT

# Issue a certificate for ${domain} and wait for its symlink.
run_nginx_container --hosts "${domain}"
if ! wait_for_symlink "${domain}" "${le_container_name}" "./${domain}/fullchain.pem"; then
  echo "Failed to issue an initial certificate for ${domain}."
fi

# Case A: no user data file present; the symlink must be preserved.
# remove service and user data files
docker exec "${le_container_name}" bash -c 'rm -f /app/letsencrypt_service_data /app/letsencrypt_user_data' 2>&1
# manually trigger cert update loop
if ! update_certs_out="$(docker exec "${le_container_name}" bash -c 'source /app/letsencrypt_service.sh --source-only && update_certs' 2>&1)"; then
  echo "update_certs failed during the data-less run with no user data: ${update_certs_out}"
fi
if ! docker exec "${le_container_name}" test -L "/etc/nginx/certs/${domain}.crt"; then
  echo "The ${domain} symlink was removed by a data-less update_certs run with no user data (issue #956)."
fi

# Case B: an empty user data file but no service data file; the symlink must be preserved.
# create an empty user data file and remove service data file
docker exec "${le_container_name}" bash -c 'touch /app/letsencrypt_user_data && rm -f /app/letsencrypt_service_data' 2>&1
# manually trigger cert update loop
if ! update_certs_out="$(docker exec "${le_container_name}" bash -c 'source /app/letsencrypt_service.sh --source-only && update_certs' 2>&1)"; then
  echo "update_certs failed during the data-less run with user data present: ${update_certs_out}"
fi
if ! docker exec "${le_container_name}" test -L "/etc/nginx/certs/${domain}.crt"; then
  echo "The ${domain} symlink was removed by a data-less update_certs run with user data present (issue #956)."
fi
