#!/bin/bash

## Test for the /app/force_renew script.

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
  # Remove the Nginx container silently.
  docker rm --force "${domains[0]}" &> /dev/null
  # Cleanup the files created by this run of the test to avoid foiling following test(s).
  docker exec "$le_container_name" /app/cleanup_test_artifacts
  # Stop the LE container
  docker stop "$le_container_name" > /dev/null
}
trap cleanup EXIT

# Run a nginx container for ${domains[0]}.
run_nginx_container --hosts "${domains[0]}"

# Wait for the certificate to be issued, then record its serial number.
wait_for_symlink "${domains[0]}" "$le_container_name"
first_serial="$(get_cert_serial "${domains[0]}" "$le_container_name")"

# Just to be sure
sleep 5

# Issue a forced renewal (capture the output so a failure is diagnosable).
renew_output="$(docker exec "$le_container_name" /app/force_renew 2>&1)"

# A renewal re-issues the cert, so its serial must change.
timeout=$(($(date +%s) + 30))
second_serial="$first_serial"
while [[ $(date +%s) -lt $timeout ]]; do
  new_serial="$(get_cert_serial "${domains[0]}" "$le_container_name" 2>/dev/null || true)"
  if [[ -n "$new_serial" && "$new_serial" != "$first_serial" ]]; then
    second_serial="$new_serial"
    [[ "${DRY_RUN:-}" == 1 ]] && echo "Certificate for ${domains[0]} was correctly renewed."
    break
  fi
  sleep 2
done

# Final check - verify the certificate was actually re-issued.
if [[ "$second_serial" == "$first_serial" ]]; then
  echo "Certificate for ${domains[0]} was not correctly renewed within 30s (serial unchanged: $first_serial)."
  echo "force_renew output:"
  echo "$renew_output"
fi
