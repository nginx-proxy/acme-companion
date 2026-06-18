#!/bin/bash

## Test for per-container private key renewal (LETSENCRYPT_RENEW_PRIVATE_KEYS). See issue #1191.
## A proxied container opting out must keep the same private key across a renewal, even though
## the companion's global RENEW_PRIVATE_KEYS default (true) would otherwise rotate it.

if [[ -z $GITHUB_ACTIONS ]]; then
  le_container_name="$(basename "${0%/*}")_$(date "+%Y-%m-%d_%H.%M.%S")"
else
  le_container_name="$(basename "${0%/*}")"
fi
run_le_container "${1:?}" "$le_container_name"

# Create the $domains array from comma separated domains in TEST_DOMAINS.
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

# Fingerprint of the public key derived from the certificate's private key.
function key_fingerprint {
  docker exec "$le_container_name" \
    openssl pkey -in "/etc/nginx/certs/${domain}.key" -pubout 2>/dev/null | sha256sum | cut -d' ' -f1
}

# Run an nginx container that opts out of private key renewal for its certificate.
run_nginx_container --hosts "$domain" --cli-args "--env LETSENCRYPT_RENEW_PRIVATE_KEYS=false"

# Wait for issuance, then record the initial key fingerprint and expiration date.
wait_for_symlink "$domain" "$le_container_name"
first_key="$(key_fingerprint)"
first_cert_expire="$(get_cert_date_epoch expiration "$domain" "$le_container_name")"

# Just to be sure
sleep 5

# Issue a forced renewal and poll until the certificate is actually renewed.
docker exec "$le_container_name" /app/force_renew &> /dev/null
timeout=$(($(date +%s) + 30))
second_cert_expire="$first_cert_expire"
while [[ $(date +%s) -lt $timeout ]]; do
  new_expire="$(get_cert_date_epoch expiration "$domain" "$le_container_name" 2>/dev/null || echo "$first_cert_expire")"
  if [[ "$new_expire" =~ ^[0-9]+$ ]] && [[ $new_expire -gt $first_cert_expire ]]; then
    second_cert_expire="$new_expire"
    break
  fi
  sleep 2
done

if ! [[ $second_cert_expire -gt $first_cert_expire ]]; then
  echo "Certificate for $domain was not renewed within 30s, cannot verify key reuse."
fi

# With LETSENCRYPT_RENEW_PRIVATE_KEYS=false the private key must be unchanged after renewal.
second_key="$(key_fingerprint)"
if [[ "$first_key" != "$second_key" ]]; then
  echo "Private key for $domain changed across renewal despite LETSENCRYPT_RENEW_PRIVATE_KEYS=false."
  echo "Before: $first_key"
  echo "After:  $second_key"
elif [[ "${DRY_RUN:-}" == 1 ]]; then
  echo "Private key for $domain was correctly reused across renewal."
fi

docker stop "$domain" > /dev/null
