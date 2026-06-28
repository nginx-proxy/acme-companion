#!/bin/bash

## Test that existing certificate symlinks are preserved when update_certs runs
## before docker-gen has (re)generated /app/letsencrypt_service_data, instead of
## being removed and replaced by the default certificate (issue #956).

if [[ -z $GITHUB_ACTIONS ]]; then
  le_container_name="$(basename "${0%/*}")_$(date "+%Y-%m-%d_%H.%M.%S")"
else
  le_container_name="$(basename "${0%/*}")"
fi
run_le_container "${1:?}" "$le_container_name"

# Use the first domain from the comma separated TEST_DOMAINS.
IFS=',' read -r -a domains <<< "$TEST_DOMAINS"
domain="${domains[0]}"

# Cleanup function with EXIT trap
function cleanup {
  # Remove the Nginx container silently.
  docker rm --force "$domain" &> /dev/null
  # Cleanup the files created by this run of the test to avoid foiling following test(s).
  docker exec "$le_container_name" /app/cleanup_test_artifacts
  # Stop the LE container
  docker stop "$le_container_name" > /dev/null
}
trap cleanup EXIT

# Issue a certificate for $domain and wait for its symlink.
run_nginx_container --hosts "$domain"
if ! wait_for_symlink "$domain" "$le_container_name" "./${domain}/fullchain.pem"; then
  echo "Failed to issue an initial certificate for $domain."
fi

# Reproduce a data-less first run: remove the generated data file then run
# update_certs synchronously. Before the fix cleanup_links deleted the still
# valid symlink; after the fix the cleanup is deferred while the service data
# file is absent, so the symlink is preserved. docker-gen only regenerates the
# data file on container events, so no event happening here keeps this
# deterministic.

# Case A: no letsencrypt_user_data present.
docker exec "$le_container_name" bash -c \
  'rm -f /app/letsencrypt_service_data /app/letsencrypt_user_data && source /app/letsencrypt_service --source-only && update_certs' \
  > /dev/null 2>&1
if ! docker exec "$le_container_name" test -L "/etc/nginx/certs/${domain}.crt"; then
  echo "The $domain symlink was removed by a data-less update_certs run with no user data (issue #956)."
fi

# Case B: a mounted letsencrypt_user_data exists but docker-gen has not yet
# generated letsencrypt_service_data. cleanup_links would otherwise see only the
# standalone domains as enabled and remove the proxied container's symlink. An
# empty user data file is enough to exercise this since the bug is triggered by
# the file merely existing, not by its content.
docker exec "$le_container_name" bash -c \
  'touch /app/letsencrypt_user_data && rm -f /app/letsencrypt_service_data && source /app/letsencrypt_service --source-only && update_certs; rm -f /app/letsencrypt_user_data' \
  > /dev/null 2>&1
if ! docker exec "$le_container_name" test -L "/etc/nginx/certs/${domain}.crt"; then
  echo "The $domain symlink was removed by a data-less update_certs run with user data present (issue #956)."
fi
