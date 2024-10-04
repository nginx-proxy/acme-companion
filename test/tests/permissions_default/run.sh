#!/bin/bash

## Test for sensitive files and folders permissions

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
  # Remove the ${domains[0]} Nginx container silently.
  docker rm --force "${domains[0]}" &> /dev/null
  # Cleanup the files created by this run of the test to avoid foiling following test(s).
  docker exec "$le_container_name" /app/cleanup_test_artifacts
  # Stop the LE container
  docker stop "$le_container_name" > /dev/null
}
trap cleanup EXIT

# Run an nginx container for ${domains[0]}.
run_nginx_container --hosts "${domains[0]}"

# Wait for the cert symlink.
wait_for_symlink "${domains[0]}" "$le_container_name"

# Array of folder paths to test
folders=( \
  [0]="/etc/nginx/certs/${domains[0]}" \
  )

# Test folder paths
for folder in  "${folders[@]}"; do
  ownership_and_permissions="$(docker exec "$le_container_name" stat -c %u:%g:%a "$folder")"
  if [[ "$ownership_and_permissions" != 0:0:755 ]]; then
    echo "Expected 0:0:755 on ${folder}, found ${ownership_and_permissions}."
  fi
done

# Array of symlinks paths to test
symlinks=( \
  [0]="/etc/nginx/certs/${domains[0]}.crt" \
  [1]="/etc/nginx/certs/${domains[0]}.key" \
  [2]="/etc/nginx/certs/${domains[0]}.chain.pem" \
  [3]="/etc/nginx/certs/${domains[0]}.dhparam.pem" \
  )

# Test symlinks paths
for symlink in  "${symlinks[@]}"; do
  ownership="$(docker exec "$le_container_name" stat -c %u:%g "$symlink")"
  if [[ "$ownership" != 0:0 ]]; then
    echo "Expected 0:0 on ${symlink}, found ${ownership}."
  fi
done

# Array of private file paths to test
private_files=( \
  [0]="/etc/nginx/certs/${domains[0]}/key.pem" \
  [1]="/etc/acme.sh/default/${domains[0]}/${domains[0]}.key" \
  )

# Test private file paths
for file in  "${private_files[@]}"; do
  ownership_and_permissions="$(docker exec "$le_container_name" stat -c %u:%g:%a "$file")"
  if [[ "$ownership_and_permissions" != 0:0:600 ]]; then
    echo "Expected 0:0:600 on ${file}, found ${ownership_and_permissions}."
  fi
done

# Array of public files paths to test
public_files=( \
  [0]="/etc/nginx/certs/${domains[0]}/.companion" \
  [1]="/etc/nginx/certs/${domains[0]}/cert.pem" \
  [2]="/etc/nginx/certs/${domains[0]}/chain.pem" \
  [3]="/etc/nginx/certs/${domains[0]}/fullchain.pem" \
  [4]="/etc/nginx/certs/dhparam.pem" \
  )

# Test public file paths
for file in  "${public_files[@]}"; do
  ownership_and_permissions="$(docker exec "$le_container_name" stat -c %u:%g:%a "$file")"
  if [[ "$ownership_and_permissions" != 0:0:644 ]]; then
    echo "Expected 0:0:644 on ${file}, found ${ownership_and_permissions}."
  fi
done
