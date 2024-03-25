#!/bin/bash

## Test for the hooks of acme.sh

default_pre_hook_file="/tmp/default_prehook"
default_pre_hook_command="touch $default_pre_hook_file"
default_post_hook_file="/tmp/default_posthook"
default_post_hook_command="touch $default_post_hook_file"

percontainer_pre_hook_file="/tmp/percontainer_prehook"
percontainer_pre_hook_command="touch $percontainer_pre_hook_file"
percontainer_post_hook_file="/tmp/percontainer_posthook"
percontainer_post_hook_command="touch $percontainer_post_hook_file"

if [[ -z $GITHUB_ACTIONS ]]; then
  le_container_name="$(basename "${0%/*}")_$(date "+%Y-%m-%d_%H.%M.%S")"
else
  le_container_name="$(basename "${0%/*}")"
fi
run_le_container "${1:?}" "$le_container_name" \
  --cli-args "--env ACME_PRE_HOOK=$default_pre_hook_command" \
  --cli-args "--env ACME_POST_HOOK=$default_post_hook_command"

# Create the $domains array from comma separated domains in TEST_DOMAINS.
IFS=',' read -r -a domains <<< "$TEST_DOMAINS"

# Cleanup function with EXIT trap
function cleanup {
  # Remove the Nginx container silently.
  docker rm --force "${domains[0]}" &> /dev/null
  # Cleanup the files created by this run of the test to avoid foiling following test(s).
  docker exec "$le_container_name" /app/cleanup_test_artifacts
  # Stop the LE container
  docker stop "$le_container_name" > /dev/null
}
trap cleanup EXIT

container_email="contact@${domains[0]}"

# Run an nginx container for ${domains[0]} with LETSENCRYPT_EMAIL set.
run_nginx_container --hosts "${domains[0]}" \
  --cli-args "--env LETSENCRYPT_EMAIL=${container_email}"

# Run an nginx container for ${domains[1]} with LETSENCRYPT_EMAIL, ACME_PRE_HOOK and ACME_POST_HOOK set.
run_nginx_container --hosts "${domains[1]}" \
  --cli-args "--env LETSENCRYPT_EMAIL=${container_email}" \
  --cli-args "--env ACME_PRE_HOOK=$percontainer_pre_hook_command" \
  --cli-args "--env ACME_POST_HOOK=$percontainer_post_hook_command"

# Wait for a symlink at /etc/nginx/certs/${domains[0]}.crt
wait_for_symlink "${domains[0]}" "$le_container_name"

acme_pre_hook_key="Le_PreHook="
acme_post_hook_key="Le_PostHook="
acme_base64_start="'__ACME_BASE64__START_"
acme_base64_end="__ACME_BASE64__END_'"

# Check if the default command is deliverd properly in /etc/acme.sh
if docker exec "$le_container_name" [[ ! -d "/etc/acme.sh/$container_email" ]]; then
  echo "The /etc/acme.sh/$container_email folder does not exist."
elif docker exec "$le_container_name" [[ ! -d "/etc/acme.sh/$container_email/${domains[0]}" ]]; then
  echo "The /etc/acme.sh/$container_email/${domains[0]} folder does not exist."
elif docker exec "$le_container_name" [[ ! -f "/etc/acme.sh/$container_email/${domains[0]}/${domains[0]}.conf" ]]; then
  echo "The /etc/acme.sh/$container_email/${domains[0]}/${domains[0]}.conf file does not exist."
fi

default_pre_hook_command_base64="${acme_pre_hook_key}${acme_base64_start}$(echo -n "$default_pre_hook_command" | base64)${acme_base64_end}"
default_post_hook_command_base64="${acme_post_hook_key}${acme_base64_start}$(echo -n "$default_post_hook_command" | base64)${acme_base64_end}"

default_acme_pre_hook="$(docker exec "$le_container_name" grep "$acme_pre_hook_key" "/etc/acme.sh/$container_email/${domains[0]}/${domains[0]}.conf")"
default_acme_post_hook="$(docker exec "$le_container_name" grep "$acme_post_hook_key" "/etc/acme.sh/$container_email/${domains[0]}/${domains[0]}.conf")"

if [[ "$default_pre_hook_command_base64" != "$default_acme_pre_hook" ]]; then 
  echo "Default prehook command not saved properly"
fi
if [[ "$default_post_hook_command_base64" != "$default_acme_post_hook" ]]; then 
  echo "Default posthook command not saved properly"
fi


# Check if the default action is performed 
if docker exec "$le_container_name" [[ ! -f "$default_pre_hook_file" ]]; then
  echo "Default prehook action failed"
fi
if docker exec "$le_container_name" [[ ! -f "$default_post_hook_file" ]]; then
  echo "Default posthook action failed"
fi

# Wait for a symlink at /etc/nginx/certs/${domains[1]}.crt
wait_for_symlink "${domains[1]}" "$le_container_name"

# Check if the per-container command is deliverd properly in /etc/acme.sh
if docker exec "$le_container_name" [[ ! -d "/etc/acme.sh/$container_email/${domains[1]}" ]]; then
  echo "The /etc/acme.sh/$container_email/${domains[1]} folder does not exist."
elif docker exec "$le_container_name" [[ ! -f "/etc/acme.sh/$container_email/${domains[1]}/${domains[1]}.conf" ]]; then
  echo "The /etc/acme.sh/$container_email/${domains[1]}/${domains[1]}.conf file does not exist."
fi

percontainer_pre_hook_command_base64="${acme_pre_hook_key}${acme_base64_start}$(echo -n "$percontainer_pre_hook_command" | base64)${acme_base64_end}"
percontainer_post_hook_command_base64="${acme_post_hook_key}${acme_base64_start}$(echo -n "$percontainer_post_hook_command" | base64)${acme_base64_end}"

percontainer_acme_pre_hook="$(docker exec "$le_container_name" grep "$acme_pre_hook_key" "/etc/acme.sh/$container_email/${domains[1]}/${domains[1]}.conf")"
percontainer_acme_post_hook="$(docker exec "$le_container_name" grep "$acme_post_hook_key" "/etc/acme.sh/$container_email/${domains[1]}/${domains[1]}.conf")"

if [[ "$percontainer_pre_hook_command_base64" != "$percontainer_acme_pre_hook" ]]; then 
  echo "Per-container prehook command not saved properly"
fi
if [[ "$percontainer_post_hook_command_base64" != "$percontainer_acme_post_hook" ]]; then 
  echo "Per-container posthook command not saved properly"
fi


# Check if the percontainer action is performed 
if docker exec "$le_container_name" [[ ! -f "$percontainer_pre_hook_file" ]]; then
  echo "Per-container prehook action failed"
fi
if docker exec "$le_container_name" [[ ! -f "$percontainer_post_hook_file" ]]; then
  echo "Per-container posthook action failed"
fi
