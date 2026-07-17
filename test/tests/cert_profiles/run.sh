#!/bin/bash

## Test for ACME certificate profiles.

companion_default_profile="longlived"
companion_default_profile_validity=31536000
shortlived_profile="shortlived"
shortlived_profile_validity=518400
validity_tolerance=2

if [[ -z ${GITHUB_ACTIONS} ]]; then
  le_container_name="$(basename "${0%/*}")_$(date "+%Y-%m-%d_%H.%M.%S")"
else
  le_container_name="$(basename "${0%/*}")"
fi
run_le_container "${1:?}" "${le_container_name}" \
  --cli-args "--env ACME_CERT_PROFILE=${companion_default_profile}"

# Create the ${domains} array from comma separated domains in TEST_DOMAINS.
IFS=',' read -r -a domains <<< "${TEST_DOMAINS}"

# Cleanup function with EXIT trap
function cleanup {
  # Remove any remaining Nginx container(s) silently.
  for domain in "${domains[0]}" "${domains[1]}"; do
    docker rm --force "${domain}" &> /dev/null
  done
  # Cleanup the files created by this run of the test to avoid foiling following test(s).
  docker exec "${le_container_name}" /app/cleanup_test_artifacts
  # Stop the LE container
  docker stop "${le_container_name}" > /dev/null
}
trap cleanup EXIT

container_email="contact@${domains[0]}"

# Run an nginx container inheriting the companion container profile.
run_nginx_container --hosts "${domains[0]}" \
  --cli-args "--env ACME_EMAIL=${container_email}"

# Run an nginx container overriding the companion container profile.
run_nginx_container --hosts "${domains[1]}" \
  --cli-args "--env ACME_EMAIL=${container_email}" \
  --cli-args "--env ACME_CERT_PROFILE=${shortlived_profile}"

# Wait for issuance of both certificates.
wait_for_symlink "${domains[0]}" "${le_container_name}"
wait_for_symlink "${domains[1]}" "${le_container_name}"

companion_actual_validity="$(get_cert_validity_seconds "${domains[0]}" "${le_container_name}")"
shortlived_actual_validity="$(get_cert_validity_seconds "${domains[1]}" "${le_container_name}")"

companion_default_profile_validity_diff="$((companion_actual_validity - companion_default_profile_validity))"
if (( companion_default_profile_validity_diff < 0 )); then
  companion_default_profile_validity_diff=$(( -companion_default_profile_validity_diff ))
fi

shortlived_profile_validity_diff="$((shortlived_actual_validity - shortlived_profile_validity))"
if (( shortlived_profile_validity_diff < 0 )); then
  shortlived_profile_validity_diff=$(( -shortlived_profile_validity_diff ))
fi

if (( companion_default_profile_validity_diff > validity_tolerance )); then
  echo "Companion profile certificate validity is ${companion_actual_validity} seconds instead of ${companion_default_profile_validity} +/- ${validity_tolerance}."
elif [[ "${DRY_RUN:-}" == 1 ]]; then
  echo "Companion profile certificate validity matches ${companion_default_profile_validity} seconds."
fi

if (( shortlived_profile_validity_diff > validity_tolerance )); then
  echo "Short-lived profile certificate validity is ${shortlived_actual_validity} seconds instead of ${shortlived_profile_validity} +/- ${validity_tolerance}."
elif [[ "${DRY_RUN:-}" == 1 ]]; then
  echo "Short-lived profile certificate validity matches ${shortlived_profile_validity} seconds."
fi
