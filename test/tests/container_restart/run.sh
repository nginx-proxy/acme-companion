#!/bin/bash

## Test for LETSENCRYPT_RESTART_CONTAINER variable.

case $ACME_CA in
  pebble)
    test_net='acme_net'
  ;;
  boulder)
    test_net='boulder_bluenet'
  ;;
  *)
    echo "$0 $ACME_CA: invalid option."
    exit 1
esac

if [[ -z $GITHUB_ACTIONS ]]; then
  le_container_name="$(basename "${0%/*}")_$(date "+%Y-%m-%d_%H.%M.%S")"
else
  le_container_name="$(basename "${0%/*}")"
fi
run_le_container "${1:?}" "$le_container_name"

# Create the $domains array from comma separated domains in TEST_DOMAINS.
IFS=',' read -r -a domains <<< "$TEST_DOMAINS"

# Listen for Docker restart events
docker events \
  --filter event=restart \
  --format 'Container {{.Actor.Attributes.name}} restarted' > "${GITHUB_WORKSPACE}/test/tests/container_restart/docker_event_out.txt" &
docker_events_pid=$!

# Cleanup function with EXIT trap
function cleanup {
  # Kill the Docker events listener
  kill $docker_events_pid && wait $docker_events_pid 2>/dev/null
  # Remove temporary files
  rm -f "${GITHUB_WORKSPACE}/test/tests/container_restart/docker_event_out.txt"
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

# Run a separate nginx container for each domain in the $domains array.
for domain in "${domains[@]}"; do
  if docker run --rm -d \
    --name "$domain" \
    -e "VIRTUAL_HOST=${domain}" \
    -e "LETSENCRYPT_HOST=${domain}" \
    -e "LETSENCRYPT_RESTART_CONTAINER=true" \
    --network "$test_net" \
    nginx:alpine > /dev/null; \
  then
    [[ "${DRY_RUN:-}" == 1 ]] && echo "Started test web server for $domain"
  else
    echo "Could not start test web server for $domain"
  fi

  # Check if container restarted
  timeout="$(date +%s)"
  timeout="$((timeout + 60))"
  until grep "$domain" "${GITHUB_WORKSPACE}"/test/tests/container_restart/docker_event_out.txt; do
    if [[ "$(date +%s)" -gt "$timeout" ]]; then
      echo "Container $domain didn't restart in under one minute."
      break
    fi
    sleep 0.1
  done
done
