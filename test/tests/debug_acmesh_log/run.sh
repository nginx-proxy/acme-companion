#!/bin/bash

## Test that, with DEBUG=1, acme.sh's own log is routed to the container output
## (--log /dev/stderr) instead of being discarded (--log /dev/null). See issue #918.

if [[ -z $GITHUB_ACTIONS ]]; then
  le_container_name="$(basename "${0%/*}")_$(date "+%Y-%m-%d_%H.%M.%S")"
else
  le_container_name="$(basename "${0%/*}")"
fi
# run_le_container starts the companion with DEBUG=1 by default.
run_le_container "${1:?}" "$le_container_name"

# Create the $domains array from comma separated domains in TEST_DOMAINS.
IFS=',' read -r -a domains <<< "$TEST_DOMAINS"
domain="${domains[0]}"

# Cleanup function with EXIT trap
function cleanup {
  # Remove the remaining Nginx container silently.
  docker rm --force "$domain" &> /dev/null
  # Cleanup the files created by this run of the test to avoid foiling following test(s).
  docker exec "$le_container_name" /app/cleanup_test_artifacts
  # Stop the LE container
  docker stop "$le_container_name" > /dev/null
}
trap cleanup EXIT

# Trigger a certificate issuance so that acme.sh actually runs.
run_nginx_container --hosts "$domain"

# Wait for the certificate to be issued (symlink created).
if ! wait_for_symlink "$domain" "$le_container_name" "./${domain}/fullchain.pem" ; then
  echo "Certificate for $domain was not issued, cannot check acme.sh log routing."
fi

le_logs="$(docker logs "$le_container_name" 2>&1)"

# With DEBUG=1, acme.sh must be invoked with '--log /dev/stderr' ...
if ! grep -q -- '--log /dev/stderr' <<< "$le_logs"; then
  echo "acme.sh was not invoked with '--log /dev/stderr' while DEBUG=1."
elif [[ "${DRY_RUN:-}" == 1 ]]; then
  echo "acme.sh was invoked with '--log /dev/stderr' while DEBUG=1."
fi

# ... and must never fall back to '--log /dev/null' while DEBUG=1.
if grep -q -- '--log /dev/null' <<< "$le_logs"; then
  echo "acme.sh was still invoked with '--log /dev/null' while DEBUG=1."
elif [[ "${DRY_RUN:-}" == 1 ]]; then
  echo "acme.sh was not invoked with '--log /dev/null' while DEBUG=1."
fi

docker stop "$domain" > /dev/null
