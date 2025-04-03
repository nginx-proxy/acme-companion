#!/bin/bash

## Test for the DEFAULT_RENEW function.

if [[ -z $GITHUB_ACTIONS ]]; then
  le_container_name="$(basename "${0%/*}")_$(date "+%Y-%m-%d_%H.%M.%S")"
else
  le_container_name="$(basename "${0%/*}")"
fi

default_renew=170
run_le_container "${1:?}" "$le_container_name" \
  --cli-args "--env DEFAULT_RENEW=$default_renew"

# Create the $domains array from comma separated domains in TEST_DOMAINS.
IFS=',' read -r -a domains <<< "$TEST_DOMAINS"

# Cleanup function with EXIT trap
function cleanup {
  # Remove the Nginx container silently.
  docker rm --force "${domains[0]}" &> /dev/null
  # Cleanup the files created by this run of the test to avoid foiling following test(s).
  docker exec "$le_container_name" /app/cleanup_test_artifacts
  # Stop the LE container
  docker stop "$le_container_name" > /dev/null
}
trap cleanup EXIT

container_email="contact@${domains[0]}"
acme_config_file="/etc/acme.sh/$container_email/${domains[0]}/${domains[0]}.conf"

# Run a nginx container for ${domains[0]} with LETSENCRYPT_EMAIL set.
run_nginx_container --hosts "${domains[0]}" \
  --cli-args "--env LETSENCRYPT_EMAIL=${container_email}"

# Wait for a symlink at /etc/nginx/certs/${domains[0]}.crt
wait_for_symlink "${domains[0]}" "$le_container_name"

acme_cert_create_time_key="Le_CertCreateTime="
acme_renewal_days_key="Le_RenewalDays="
acme_next_renew_time_key="Le_NextRenewTime="

# Check if the default command is deliverd properly in /etc/acme.sh
if docker exec "$le_container_name" [[ ! -f "$acme_config_file" ]]; then
  echo "The $acme_config_file file does not exist."
fi

cert_create_time="$(docker exec "$le_container_name" grep "$acme_cert_create_time_key" "$acme_config_file" | cut -f2 -d\')"
expected_renewal_days="${acme_renewal_days_key}'$default_renew'"
expected_next_renew_time="${acme_next_renew_time_key}'$(($cert_create_time + $default_renew * 24 * 60 * 60 - 86400))'"
actual_renewal_days="$(docker exec "$le_container_name" grep "$acme_renewal_days_key" "$acme_config_file")"
actual_next_renew_time="$(docker exec "$le_container_name" grep "$acme_next_renew_time_key" "$acme_config_file")"

if [[ "$expected_renewal_days" != "$actual_renewal_days" ]]; then
  echo "Renewal days is not correct"
fi
if [[ "$expected_next_renew_time" != "$actual_next_renew_time" ]]; then
  echo "Next renewal time is not correct"
fi
