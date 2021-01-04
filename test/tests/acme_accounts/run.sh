#!/bin/bash

## Test for ACME accounts handling.

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
  for domain in "${domains[@]}"; do
    docker rm --force "$domain" &> /dev/null
  done
  # Cleanup the files created by this run of the test to avoid foiling following test(s).
  docker exec "$le_container_name" /app/cleanup_test_artifacts
  # Stop the LE container
  docker stop "$le_container_name" > /dev/null
}
trap cleanup EXIT

# Run an nginx container for ${domains[0]}.
run_nginx_container --hosts "${domains[0]}"

# Wait for a symlink at /etc/nginx/certs/${domains[0]}.crt
wait_for_symlink "${domains[0]}" "$le_container_name"

# Test if the expected folder / file / content are there.
json_file="/etc/acme.sh/default/ca/$ACME_CA/account.json"
if [[ "$ACME_CA" == 'boulder' ]]; then
  no_mail_str='[]'
elif [[ "$ACME_CA" == 'pebble' ]]; then
  no_mail_str='null'
fi
if docker exec "$le_container_name" [[ ! -d "/etc/acme.sh/default" ]]; then
  echo "The /etc/acme.sh/default folder does not exist."
elif docker exec "$le_container_name" [[ ! -f "$json_file" ]]; then
  echo "The $json_file file does not exist."
elif [[ "$(docker exec "$le_container_name" jq .contact "$json_file")" != "$no_mail_str" ]]; then
  echo "There is an address set on ${json_file}."
  docker exec "$le_container_name" jq . "$json_file"
  docker exec "$le_container_name" jq .contact "$json_file"
fi

# Stop the nginx and companion containers silently.
docker stop "${domains[0]}" &> /dev/null
docker stop "$le_container_name" &> /dev/null

# Run the companion container with the DEFAULT_EMAIL env var set.
default_email="contact@${domains[1]}"
le_container_name="${le_container_name}_default"
run_le_container "${1:?}" "$le_container_name" "--env DEFAULT_EMAIL=${default_email}"

# Run an nginx container for ${domains[1]} without LETSENCRYPT_EMAIL set.
run_nginx_container --hosts "${domains[1]}"

# Wait for a symlink at /etc/nginx/certs/${domains[1]}.crt
wait_for_symlink "${domains[1]}" "$le_container_name"

# Test if the expected folder / file / content are there.
json_file="/etc/acme.sh/${default_email}/ca/$ACME_CA/account.json"
if docker exec "$le_container_name" [[ ! -d "/etc/acme.sh/$default_email" ]]; then
  echo "The /etc/acme.sh/$default_email folder does not exist."
elif docker exec "$le_container_name" [[ ! -f "$json_file" ]]; then
  echo "The $json_file file does not exist."
elif [[ "$(docker exec "$le_container_name" jq -r '.contact|.[0]' "$json_file")" != "mailto:${default_email}" ]]; then
  echo "$default_email is not set on ${json_file}."
  docker exec "$le_container_name" jq . "$json_file"
fi

# Run an nginx container for ${domains[2]} with LETSENCRYPT_EMAIL set.
container_email="contact@${domains[2]}"
run_nginx_container --hosts "${domains[2]}" --cli-args "--env LETSENCRYPT_EMAIL=${container_email}"

# Wait for a symlink at /etc/nginx/certs/${domains[2]}.crt
wait_for_symlink "${domains[2]}" "$le_container_name"

# Test if the expected folder / file / content are there.
json_file="/etc/acme.sh/${container_email}/ca/$ACME_CA/account.json"
if docker exec "$le_container_name" [[ ! -d "/etc/acme.sh/$container_email" ]]; then
  echo "The /etc/acme.sh/$container_email folder does not exist."
elif docker exec "$le_container_name" [[ ! -f "$json_file" ]]; then
  echo "The $json_file file does not exist."
elif [[ "$(docker exec "$le_container_name" jq -r '.contact|.[0]' "$json_file")" != "mailto:${container_email}" ]]; then
  echo "$default_email is not set on ${json_file}."
  docker exec "$le_container_name" jq . "$json_file"
fi

# Stop the nginx containers silently.
docker stop "${domains[1]}" &> /dev/null
docker stop "${domains[2]}" &> /dev/null
