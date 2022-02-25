#!/bin/bash

## Test for the hooks of acme.sh
pre_hook_file="/tmp/prehook"
pre_hook_command="touch $pre_hook_file"
post_hook_file="/tmp/posthook"
post_hook_command="touch $post_hook_file"



if [[ -z $GITHUB_ACTIONS ]]; then
  le_container_name="$(basename "${0%/*}")_$(date "+%Y-%m-%d_%H.%M.%S")"
else
  le_container_name="$(basename "${0%/*}")"
fi
run_le_container "${1:?}" "$le_container_name" --cli-args "--env ACME_PRE_HOOK=$pre_hook_command" --cli-args "--env ACME_POST_HOOK=$post_hook_command"

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

# Run an nginx container for ${domains[0]} with LETSENCRYPT_EMAIL set.
container_email="contact@${domains[0]}"
run_nginx_container --hosts "${domains[0]}" --cli-args "--env LETSENCRYPT_EMAIL=${container_email}"

# Wait for a symlink at /etc/nginx/certs/${domains[0]}.crt
wait_for_symlink "${domains[0]}" "$le_container_name"

##Check if the command is deliverd properly in /etc/acme.sh
if docker exec "$le_container_name" [[ ! -d "/etc/acme.sh/$container_email" ]]; then
  echo "The /etc/acme.sh/$container_email folder does not exist."
elif docker exec "$le_container_name" [[ ! -d "/etc/acme.sh/$container_email/${domains[0]}" ]]; then
  echo "The /etc/acme.sh/$container_email/${domains[0]} folder does not exist."
elif docker exec "$le_container_name" [[ ! -f "/etc/acme.sh/$container_email/${domains[0]}/${domains[0]}.conf" ]]; then
  echo "The /etc/acme.sh/$container_email/${domains[0]}/${domains[0]}.conf file does not exist."
fi
acme_pre_hook_key="Le_PreHook="
acme_post_hook_key="Le_PostHook="
acme_base64_start="'__ACME_BASE64__START_"
acme_base64_end="__ACME_BASE64__END_'"
pre_hook_command_base64=$(echo -n "$pre_hook_command" | base64)
post_hook_command_base64=$(echo -n "$post_hook_command" | base64)

acme_pre_hook="$(docker exec "$le_container_name" grep "$acme_pre_hook_key" "/etc/acme.sh/$container_email/${domains[0]}/${domains[0]}.conf")"
acme_post_hook="$(docker exec "$le_container_name" grep "$acme_post_hook_key" "/etc/acme.sh/$container_email/${domains[0]}/${domains[0]}.conf")"

if [[ "$acme_pre_hook_key$acme_base64_start$pre_hook_command_base64$acme_base64_end" != "$acme_pre_hook" ]]; then 
  echo "Prehook command not saved properly"
fi
if [[ "$acme_post_hook_key$acme_base64_start$post_hook_command_base64$acme_base64_end" != "$acme_post_hook" ]]; then 
  echo "Posthook command not saved properly"
fi


## Check if the action ist performed 
if docker exec "$le_container_name" [[ ! -f "$pre_hook_file" ]]; then
  echo "Prehook action failed"
fi
if docker exec "$le_container_name" [[ ! -f "$post_hook_file" ]]; then
  echo "Posthook action failed"
fi
