#!/bin/bash

## Test for sensitive files and folders permissions

if [[ -z $TRAVIS_CI ]]; then
  le_container_name="$(basename ${0%/*})_$(date "+%Y-%m-%d_%H.%M.%S")"
else
  le_container_name="$(basename ${0%/*})"
fi
run_le_container ${1:?} "$le_container_name"

# Create the $domains array from comma separated domains in TEST_DOMAINS.
IFS=',' read -r -a domains <<< "$TEST_DOMAINS"

# Cleanup function with EXIT trap
function cleanup {
  # Remove the ${domains[0]} Nginx container silently.
  docker rm --force "${domains[0]}" > /dev/null 2>&1
  # Cleanup the files created by this run of the test to avoid foiling following test(s).
  docker exec "$le_container_name" bash -c 'rm -rf /etc/nginx/certs/le?.wtf*'
  # Stop the LE container
  docker stop "$le_container_name" > /dev/null
}
trap cleanup EXIT

# Run an nginx container for ${domains[0]}.
docker run --rm -d \
  --name "${domains[0]}" \
  -e "VIRTUAL_HOST=${domains[0]}" \
  -e "LETSENCRYPT_HOST=${domains[0]}" \
  nginx:alpine > /dev/null && echo "Started test web server for ${domains[0]}"

# Wait for the cert symlink.
wait_for_symlink "${domains[0]}" "$le_container_name"

# Array of folder paths to test
folders=( \
  [0]="/etc/nginx/certs/accounts" \
  [1]="/etc/nginx/certs/accounts/boulder:4000" \
  [2]="/etc/nginx/certs/accounts/boulder:4000/directory" \
  [3]="/etc/nginx/certs/${domains[0]}" \
  )

# Test folder paths
for folder in  "${folders[@]}"; do
  ownership_and_permissions="$(docker exec "$le_container_name" stat -c %U:%G:%a "$folder")"
  [[ "$ownership_and_permissions" == root:root:755 ]] || echo "Expected root:root:755 on ${folder}, found ${ownership_and_permissions}."
done

# Array of file paths to test
files=( \
  [0]="/etc/nginx/certs/default.key" \
  [1]="/etc/nginx/certs/accounts/boulder:4000/directory/default.json" \
  [2]="/etc/nginx/certs/${domains[0]}/key.pem" \
  )

# Test file paths
for file in  "${files[@]}"; do
  ownership_and_permissions="$(docker exec "$le_container_name" stat -c %U:%G:%a "$file")"
  [[ "$ownership_and_permissions" == root:root:644 ]] || echo "Expected root:root:644 on ${file}, found ${ownership_and_permissions}."
done
