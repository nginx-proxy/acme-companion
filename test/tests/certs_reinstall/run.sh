#!/bin/bash

## Test that a certificate still present in the acme.sh data is reinstalled
## to the certs volume (using acme.sh --install-cert) when the certificate
## files are missing from /etc/nginx/certs, instead of being silently skipped
## by acme.sh --issue returning 2 (RENEW_SKIP).

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
  exit 1
fi

# Record the serial of the original certificate.
original_serial="$(get_cert_serial "${domain}" "${le_container_name}")"

# Simulate a recreated certs volume: remove the certificate folder and every
# symlink related to ${domain}, while the acme.sh data is left intact.
if ! docker exec "${le_container_name}" bash -c \
  "rm -rf '/etc/nginx/certs/${domain}' '/etc/nginx/certs/${domain}.crt' '/etc/nginx/certs/${domain}.key' '/etc/nginx/certs/${domain}.dhparam.pem' '/etc/nginx/certs/${domain}.chain.pem'"
then
  echo "Failed to remove the ${domain} certificate files from the certs volume."
fi

# Manually trigger a cert update loop. acme.sh --issue must skip the renewal
# (return code 2) since the acme.sh data still holds a valid certificate, and
# the companion must reinstall the certificate files from the acme.sh data.
if ! update_certs_out="$(docker exec "${le_container_name}" bash -c 'source /app/letsencrypt_service.sh --source-only && update_certs' 2>&1)"; then
  echo "update_certs failed during the missing-certs run: ${update_certs_out}"
fi

# The certificate files must have been reinstalled from the acme.sh data.
if ! docker exec "${le_container_name}" test -f "/etc/nginx/certs/${domain}/fullchain.pem"; then
  echo "The ${domain} fullchain.pem was not reinstalled from the acme.sh data by update_certs."
fi
if ! docker exec "${le_container_name}" test -f "/etc/nginx/certs/${domain}/key.pem"; then
  echo "The ${domain} key.pem was not reinstalled from the acme.sh data by update_certs."
fi

# The certificate symlink must have been recreated.
if ! wait_for_symlink "${domain}" "${le_container_name}" "./${domain}/fullchain.pem"; then
  echo "The ${domain} certificate symlink was not recreated by update_certs."
fi

# The reinstalled certificate must be the original one, i.e. the certificate
# was reinstalled from the acme.sh data, not re-issued against the ACME CA.
reinstalled_serial="$(get_cert_serial "${domain}" "${le_container_name}" 2>/dev/null || true)"
if [[ "${reinstalled_serial}" != "${original_serial}" ]]; then
  echo "The reinstalled ${domain} certificate serial (${reinstalled_serial:-none}) does not match the original one (${original_serial}), expected the certificate to be reinstalled from the acme.sh data, not re-issued."
fi
