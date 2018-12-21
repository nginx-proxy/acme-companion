#!/bin/bash

## Test for LETSENCRYPT_RESTART_CONTAINER variable.

if [[ -z $TRAVIS_CI ]]; then
  le_container_name="$(basename ${0%/*})_$(date "+%Y-%m-%d_%H.%M.%S")"
else
  le_container_name="$(basename ${0%/*})"
fi
run_le_container ${1:?} "$le_container_name"

# Create the $domains array from comma separated domains in TEST_DOMAINS.
IFS=',' read -r -a domains <<< "$TEST_DOMAINS"

# Listen for Docker restart events
docker events \
  --filter event=restart \
  --format 'Container {{.Actor.Attributes.name}} restarted' > ${TRAVIS_BUILD_DIR}/test/tests/container_restart/docker_event_out.txt &
docker_events_pid=$!

# Cleanup function with EXIT trap
function cleanup {
  # Kill the Docker events listener
  kill $docker_events_pid && wait $docker_events_pid 2>/dev/null
  # Remove temporary files
  rm -f ${TRAVIS_BUILD_DIR}/test/tests/container_restart/docker_event_out.txt
  # Remove any remaining Nginx container(s) silently.
  for domain in "${domains[@]}"; do
    docker rm --force "$domain" > /dev/null 2>&1
  done
  # Cleanup the files created by this run of the test to avoid foiling following test(s).
  docker exec "$le_container_name" bash -c 'rm -rf /etc/nginx/certs/le?.wtf*'
  # Stop the LE container
  docker stop "$le_container_name" > /dev/null
}
trap cleanup EXIT

# Run a separate nginx container for each domain in the $domains array.
# Start all the containers in a row so that docker-gen debounce timers fire only once.
for domain in "${domains[@]}"; do
  docker run --rm -d \
    --name "$domain" \
    -e "VIRTUAL_HOST=${domain}" \
    -e "LETSENCRYPT_HOST=${domain}" \
    -e "LETSENCRYPT_RESTART_CONTAINER=true" \
    --network boulder_bluenet \
    nginx:alpine > /dev/null && echo "Started test web server for $domain"
done

for domain in "${domains[@]}"; do

  # Check if container restarted
  i=0
  until grep "$domain" ${TRAVIS_BUILD_DIR}/test/tests/container_restart/docker_event_out.txt; do
    if [ "$waited_once" = true ]; then
      echo "Container $domain didn't restart in under one minute."
      break
    elif [ $i -gt 60 ]; then
      echo "Container $domain didn't restart in under one minute."
      # Wait only once for all containers (since all containers are started together)
      waited_once=true
      break
    fi
    i=$((i + 2))
    sleep 2
  done
  
  # Stop the Nginx container silently.
  docker stop "$domain" > /dev/null
done
