#!/bin/bash

## Test for ACME certificate profiles.

default_profile="default"
default_validity=157766400
shortlived_profile="shortlived"
shortlived_validity=518400
validity_tolerance=2

if [[ -z $GITHUB_ACTIONS ]]; then
  le_container_name="$(basename "${0%/*}")_$(date "+%Y-%m-%d_%H.%M.%S")"
else
  le_container_name="$(basename "${0%/*}")"
fi
run_le_container "${1:?}" "$le_container_name" \
  --cli-args "--env ACME_CERT_PROFILE=$default_profile" \
  --cli-args "--env DEFAULT_RENEW=1"

# Create the $domains array from comma separated domains in TEST_DOMAINS.
IFS=',' read -r -a domains <<< "$TEST_DOMAINS"

# Cleanup function with EXIT trap
function cleanup {
  # Remove any remaining Nginx container(s) silently.
  for domain in "${domains[0]}" "${domains[1]}"; do
    docker rm --force "$domain" &> /dev/null
  done
  # Cleanup the files created by this run of the test to avoid foiling following test(s).
  docker exec "$le_container_name" /app/cleanup_test_artifacts
  # Stop the LE container
  docker stop "$le_container_name" > /dev/null
}
trap cleanup EXIT

container_email="contact@${domains[0]}"

# Run an nginx container inheriting the default profile from the companion container.
run_nginx_container --hosts "${domains[0]}" \
  --cli-args "--env LETSENCRYPT_EMAIL=${container_email}"

# Run an nginx container overriding the default profile.
run_nginx_container --hosts "${domains[1]}" \
  --cli-args "--env LETSENCRYPT_EMAIL=${container_email}" \
  --cli-args "--env ACME_CERT_PROFILE=${shortlived_profile}"

# Wait for issuance of both certificates.
wait_for_symlink "${domains[0]}" "$le_container_name"
wait_for_symlink "${domains[1]}" "$le_container_name"

default_actual_validity="$(get_cert_validity_seconds "${domains[0]}" "$le_container_name")"
shortlived_actual_validity="$(get_cert_validity_seconds "${domains[1]}" "$le_container_name")"

default_validity_diff="$((default_actual_validity - default_validity))"
if (( default_validity_diff < 0 )); then
  default_validity_diff=$(( -default_validity_diff ))
fi

shortlived_validity_diff="$((shortlived_actual_validity - shortlived_validity))"
if (( shortlived_validity_diff < 0 )); then
  shortlived_validity_diff=$(( -shortlived_validity_diff ))
fi

if (( default_validity_diff > validity_tolerance )); then
  echo "Default profile certificate validity is $default_actual_validity seconds instead of $default_validity +/- $validity_tolerance."
elif [[ "${DRY_RUN:-}" == 1 ]]; then
  echo "Default profile certificate validity matches $default_validity seconds."
fi

if (( shortlived_validity_diff > validity_tolerance )); then
  echo "Short-lived profile certificate validity is $shortlived_actual_validity seconds instead of $shortlived_validity +/- $validity_tolerance."
elif [[ "${DRY_RUN:-}" == 1 ]]; then
  echo "Short-lived profile certificate validity matches $shortlived_validity seconds."
fi
