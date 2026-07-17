#!/bin/bash

## Test for the ACME_RENEW_AFTER function.

if [[ -z $GITHUB_ACTIONS ]]; then
  le_container_name="$(basename "${0%/*}")_$(date "+%Y-%m-%d_%H.%M.%S")"
else
  le_container_name="$(basename "${0%/*}")"
fi

global_renew=170
run_le_container "${1:?}" "$le_container_name" \
  --cli-args "--env ACME_RENEW_AFTER=$global_renew" \
  --cli-args "--env NO_ARI=1"

# Create the $domains array from comma separated domains in TEST_DOMAINS.
IFS=',' read -r -a domains <<< "$TEST_DOMAINS"

# Cleanup function with EXIT trap
function cleanup {
  # Remove any remaining Nginx container(s) silently.
  docker rm --force "${domains[0]}" "${domains[1]}" &> /dev/null
  # Cleanup the files created by this run of the test to avoid foiling following test(s).
  docker exec "$le_container_name" /app/cleanup_test_artifacts
  # Stop the LE container
  docker stop "$le_container_name" > /dev/null
}
trap cleanup EXIT

acme_cert_create_time_key="Le_CertCreateTime="
acme_renewal_days_key="Le_RenewalDays="
acme_next_renew_time_key="Le_NextRenewTime="

# Test global ACME_RENEW_AFTER setting
container_email="contact@${domains[0]}"
acme_config_file="/etc/acme.sh/$container_email/${domains[0]}/${domains[0]}.conf"

# Run a nginx container for ${domains[0]} with ACME_EMAIL set.
run_nginx_container --hosts "${domains[0]}" \
  --cli-args "--env ACME_EMAIL=${container_email}"

# Wait for a symlink at /etc/nginx/certs/${domains[0]}.crt
wait_for_symlink "${domains[0]}" "$le_container_name"

if ! docker exec "$le_container_name" test -f "$acme_config_file"; then
  echo "The $acme_config_file file does not exist."
fi

cert_create_time="$(docker exec "$le_container_name" grep "$acme_cert_create_time_key" "$acme_config_file" | cut -f2 -d\')"
expected_renewal_days="${acme_renewal_days_key}'$global_renew'"
expected_next_renew_time="${acme_next_renew_time_key}'$(($cert_create_time + $global_renew * 24 * 60 * 60 - 86400))'"
actual_renewal_days="$(docker exec "$le_container_name" grep "$acme_renewal_days_key" "$acme_config_file")"
actual_next_renew_time="$(docker exec "$le_container_name" grep "$acme_next_renew_time_key" "$acme_config_file")"

if [[ "$expected_renewal_days" != "$actual_renewal_days" ]]; then
  echo "Global renewal days is not correct, expected: $expected_renewal_days, actual: $actual_renewal_days"
fi
if [[ "$expected_next_renew_time" != "$actual_next_renew_time" ]]; then
  echo "Global next renewal time is not correct, expected: $expected_next_renew_time, actual: $actual_next_renew_time"
fi

# Test per-container ACME_RENEW_AFTER override
container_renew=30
container_email_2="contact@${domains[1]}"
acme_config_file_2="/etc/acme.sh/$container_email_2/${domains[1]}/${domains[1]}.conf"

# Run a nginx container for ${domains[1]} with ACME_EMAIL and ACME_RENEW_AFTER set.
run_nginx_container --hosts "${domains[1]}" \
  --cli-args "--env ACME_EMAIL=${container_email_2}" \
  --cli-args "--env ACME_RENEW_AFTER=$container_renew"

# Wait for a symlink at /etc/nginx/certs/${domains[1]}.crt
wait_for_symlink "${domains[1]}" "$le_container_name"

if ! docker exec "$le_container_name" test -f "$acme_config_file_2"; then
  echo "The $acme_config_file_2 file does not exist."
fi

cert_create_time_2="$(docker exec "$le_container_name" grep "$acme_cert_create_time_key" "$acme_config_file_2" | cut -f2 -d\')"
expected_renewal_days_2="${acme_renewal_days_key}'$container_renew'"
expected_next_renew_time_2="${acme_next_renew_time_key}'$(($cert_create_time_2 + $container_renew * 24 * 60 * 60 - 86400))'"
actual_renewal_days_2="$(docker exec "$le_container_name" grep "$acme_renewal_days_key" "$acme_config_file_2")"
actual_next_renew_time_2="$(docker exec "$le_container_name" grep "$acme_next_renew_time_key" "$acme_config_file_2")"

if [[ "$expected_renewal_days_2" != "$actual_renewal_days_2" ]]; then
  echo "Per-container renewal days is not correct, expected: $expected_renewal_days_2, actual: $actual_renewal_days_2"
fi
if [[ "$expected_next_renew_time_2" != "$actual_next_renew_time_2" ]]; then
  echo "Per-container next renewal time is not correct, expected: $expected_next_renew_time_2, actual: $actual_next_renew_time_2"
fi
