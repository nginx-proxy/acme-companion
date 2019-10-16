#!/bin/bash

## Test for sensitive files and folders permissions

files_uid=1000
files_gid=1001
files_perms=640
folders_perms=750

if [[ -z $TRAVIS ]]; then
  le_container_name="$(basename ${0%/*})_$(date "+%Y-%m-%d_%H.%M.%S")"
else
  le_container_name="$(basename ${0%/*})"
fi
run_le_container ${1:?} "$le_container_name" \
  "--env FILES_UID=$files_uid --env FILES_GID=$files_gid --env FILES_PERMS=$files_perms --env FOLDERS_PERMS=$folders_perms"

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
  [1]="/etc/nginx/certs/accounts/boulder:4001" \
  [2]="/etc/nginx/certs/accounts/boulder:4001/directory" \
  [3]="/etc/nginx/certs/${domains[0]}" \
  )

# Test folder paths
for folder in  "${folders[@]}"; do
  ownership_and_permissions="$(docker exec "$le_container_name" stat -c %u:%g:%a "$folder")"
  if [[ "$ownership_and_permissions" != ${files_uid}:${files_gid}:${folders_perms} ]]; then
    echo "Expected ${files_uid}:${files_gid}:${folders_perms} on ${folder}, found ${ownership_and_permissions}."
  fi
done

# Array of symlinks paths to test
symlinks=( \
  [0]="/etc/nginx/certs/${domains[0]}.crt" \
  [1]="/etc/nginx/certs/${domains[0]}.key" \
  [2]="/etc/nginx/certs/${domains[0]}.chain.pem" \
  [3]="/etc/nginx/certs/${domains[0]}.dhparam.pem" \
  [4]="/etc/nginx/certs/${domains[0]}/account_key.json" \
  [5]="/etc/nginx/certs/${domains[0]}/account_reg.json" \
  )

  # Test symlinks paths
  for symlink in  "${symlinks[@]}"; do
    ownership="$(docker exec "$le_container_name" stat -c %u:%g "$symlink")"
    if [[ "$ownership" != ${files_uid}:${files_gid} ]]; then
      echo "Expected ${files_uid}:${files_gid} on ${symlink}, found ${ownership}."
    fi
  done

# Array of private file paths to test
private_files=( \
  [0]="/etc/nginx/certs/default.key" \
  [1]="/etc/nginx/certs/accounts/boulder:4001/directory/default_key.json" \
  [2]="/etc/nginx/certs/accounts/boulder:4001/directory/default_reg.json" \
  [3]="/etc/nginx/certs/${domains[0]}/key.pem" \
  )

# Test private file paths
for file in  "${private_files[@]}"; do
  ownership_and_permissions="$(docker exec "$le_container_name" stat -c %u:%g:%a "$file")"
  if [[ "$ownership_and_permissions" != ${files_uid}:${files_gid}:${files_perms} ]]; then
    echo "Expected ${files_uid}:${files_gid}:${files_perms} on ${file}, found ${ownership_and_permissions}."
  fi
done

# Array of public files paths to test
public_files=( \
  [0]="/etc/nginx/certs/${domains[0]}/.companion" \
  [1]="/etc/nginx/certs/${domains[0]}/cert.pem" \
  [2]="/etc/nginx/certs/${domains[0]}/chain.pem" \
  [3]="/etc/nginx/certs/${domains[0]}/fullchain.pem" \
  [4]="/etc/nginx/certs/default.crt" \
  [5]="/etc/nginx/certs/dhparam.pem" \
  )

# Test public file paths
for file in  "${public_files[@]}"; do
  ownership_and_permissions="$(docker exec "$le_container_name" stat -c %u:%g:%a "$file")"
  if [[ "$ownership_and_permissions" != ${files_uid}:${files_gid}:644 ]]; then
    echo "Expected ${files_uid}:${files_gid}:644 on ${file}, found ${ownership_and_permissions}."
  fi
done
