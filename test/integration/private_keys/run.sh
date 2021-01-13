#!/usr/bin/env bash

## Test for private keys types

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
  for key in "${!key_types[@]}"; do
    docker rm --force "${key}" &> /dev/null
  done
  # Cleanup the files created by this run of the test to avoid foiling following test(s).
  docker exec "$le_container_name" /app/cleanup_test_artifacts
  # Stop the LE container
  docker stop "$le_container_name" > /dev/null
}
trap cleanup EXIT

declare -A key_types
key_types=( \
  ['2048']='RSA Public-Key: (2048 bit)' \
  ['3072']='RSA Public-Key: (3072 bit)' \
  ['4096']='RSA Public-Key: (4096 bit)' \
  ['ec-256']='prime256v1' \
  ['ec-384']='secp384r1' \
)

for key in "${!key_types[@]}"; do

  # Run an Nginx container with the wanted key type.
  run_nginx_container --hosts "${domains[0]}" --name "${key}" --cli-args "--env LETSENCRYPT_KEYSIZE=${key}"

  # Grep the expected string from the public key in text form.
  if wait_for_symlink "${domains[0]}" "$le_container_name"; then
    public_key=$(docker exec "$le_container_name" openssl pkey -in "/etc/nginx/certs/${domains[0]}.key" -noout -text_pub)
    if ! grep -q "${key_types[$key]}" <<< "$public_key"; then
      echo "Keys for test $key were not of the correct type, expected ${key_types[$key]} and got the following:"
      echo "$public_key"
    fi
  else
    echo "${key_types[$key]} key test timed out"
  fi

  docker stop "${key}" &> /dev/null
  docker exec "$le_container_name" /app/cleanup_test_artifacts

done
