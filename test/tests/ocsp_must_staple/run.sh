#!/bin/bash

## Test for OCSP Must-Staple extension.

case $ACME_CA in
  pebble)
    test_net='acme_net'
  ;;
  boulder)
    test_net='boulder_bluenet'
  ;;
  *)
    echo "$0 $ACME_CA: invalid option."
    exit 1
esac

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

# Run an nginx container with ACME_OCSP=true
if docker run --rm -d \
  --name "${domains[0]}" \
  -e "VIRTUAL_HOST=${domains[0]}" \
  -e "LETSENCRYPT_HOST=${domains[0]}" \
  -e "ACME_OCSP=true" \
  --network "$test_net" \
  nginx:alpine > /dev/null; \
then
  [[ "${DRY_RUN:-}" == 1 ]] && echo "Started test web server for ${domains[0]} (ACME_OCSP=true)"
else
  echo "Could not start test web server for ${domains[0]} (ACME_OCSP=true)"
fi

# Run an second nginx container without ACME_OCSP=true
run_nginx_container "${domains[1]}"

# Wait for the symlink to the ${domains[0]} certificate
wait_for_symlink "${domains[0]}" "$le_container_name"

# Check if the OCSP Must-Staple extension is present in the ${domains[0]} certificate
if docker exec "$le_container_name" openssl x509 -in "/etc/nginx/certs/${domains[0]}/cert.pem" -text -noout | grep -q -E '1\.3\.6\.1\.5\.5\.7\.1\.24|status_request'; then
  [[ "${DRY_RUN:-}" == 1 ]] && echo "The OCSP Must-Staple extension is present on the ${domains[0]} certificate."
else
  echo "The OCSP Must-Staple extension is absent from the ${domains[0]} certificate."
fi

# Wait for the symlink to the ${domains[1]} certificate
wait_for_symlink "${domains[1]}" "$le_container_name"

# Check if the OCSP Must-Staple extension is absent from the ${domains[1]} certificate
if docker exec "$le_container_name" openssl x509 -in "/etc/nginx/certs/${domains[1]}/cert.pem" -text -noout | grep -q -E '1\.3\.6\.1\.5\.5\.7\.1\.24|status_request'; then
  echo "The OCSP Must-Staple extension is present on the ${domains[1]} certificate."
elif [[ "${DRY_RUN:-}" == 1 ]]; then
  echo "The OCSP Must-Staple extension is absent from the ${domains[1]} certificate."
fi
