#!/usr/bin/env bash

## Test for private keys types

if [[ -z ${GITHUB_ACTIONS} ]]; then
  le_container_name="$(basename "${0%/*}")_$(date "+%Y-%m-%d_%H.%M.%S")"
else
  le_container_name="$(basename "${0%/*}")"
fi
run_le_container "${1:?}" "${le_container_name}"

# Create the ${domains} array from comma separated domains in TEST_DOMAINS.
IFS=',' read -r -a domains <<< "${TEST_DOMAINS}"

# Cleanup function with EXIT trap
function cleanup {
  # Remove any remaining Nginx container(s) silently.
  for key in "${!key_types[@]}"; do
    docker rm --force "${key}" &> /dev/null
  done
  # Cleanup the files created by this run of the test to avoid foiling following test(s).
  docker exec "${le_container_name}" cleanup_test_artifacts
  # Stop the LE container
  docker stop "${le_container_name}" > /dev/null
}
trap cleanup EXIT

declare -A key_types
key_types=( \
  ['2048']='Public-Key: (2048 bit)' \
  ['3072']='Public-Key: (3072 bit)' \
  ['4096']='Public-Key: (4096 bit)' \
  ['8192']='Public-Key: (8192 bit)' \
  ['ec-256']='prime256v1' \
  ['ec-384']='secp384r1' \
  ['ec-521']='secp521r1' \
)

for key in "${!key_types[@]}"; do

  # Run an Nginx container with the wanted key type.
  run_nginx_container --hosts "${domains[0]}" --name "${key}" --cli-args "--env ACME_KEYSIZE=${key}"

  # Run an Nginx container with the wanted key type and the legacy environment variable name.
  run_nginx_container --hosts "${domains[1]}" --name "${key}-legacy" --cli-args "--env LETSENCRYPT_KEYSIZE=${key}"

  # Grep the expected string from the public key in text form.
  for domain in "${domains[@]:0:2}"; do
    if wait_for_symlink "${domain}" "${le_container_name}"; then
      public_key=$(docker exec "${le_container_name}" openssl pkey -in "/etc/nginx/certs/${domain}.key" -noout -text_pub)
      if ! grep -q "${key_types[${key}]}" <<< "${public_key}"; then
        echo "Private key for test ${key} and domain ${domain} was not of the correct type, expected ${key_types[${key}]} and got the following:"
        echo "${public_key}"
      fi
    else
      echo "${key_types[${key}]} key test timed out for domain ${domain}"
    fi
  done

  docker stop "${key}" "${key}-legacy" &> /dev/null
  docker exec "${le_container_name}" cleanup_test_artifacts

done
