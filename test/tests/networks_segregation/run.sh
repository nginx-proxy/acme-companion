#!/bin/bash

## Test for single domain certificates.

if [[ -z $TRAVIS ]]; then
  le_container_name="$(basename ${0%/*})_$(date "+%Y-%m-%d_%H.%M.%S")"
else
  le_container_name="$(basename ${0%/*})"
fi
desired_network="boulder_bluenet"
run_le_container ${1:?} "$le_container_name" "--env MUST_BE_CONNECTED_WITH_NETWORK=$desired_network"

# Create the $domains array from comma separated domains in TEST_DOMAINS.
IFS=',' read -r -a domains <<< "$TEST_DOMAINS"

# Cleanup function with EXIT trap
function cleanup {
  # Remove any remaining Nginx container(s) silently.
  for domain in "${domains[@]}"; do
    docker rm --force "$domain" > /dev/null 2>&1
  done
  # Cleanup the files created by this run of the test to avoid foiling following test(s).
  docker exec "$le_container_name" bash -c 'rm -rf /etc/nginx/certs/le?.wtf*'
  # Stop the LE container
  docker stop "$le_container_name" > /dev/null
  # Drop temp network
  docker network rm "le_test_other_net1" > /dev/null
  docker network rm "le_test_other_net2" > /dev/null
}
trap cleanup EXIT

docker network create "le_test_other_net1" > /dev/null
docker network create "le_test_other_net2" > /dev/null

networks_map=("$desired_network" le_test_other_net1 le_test_other_net2)

# Run a separate nginx container for each domain in the $domains array.
# Start all the containers in a row so that docker-gen debounce timers fire only once.
i=0
for domain in "${domains[@]}"; do
  docker run --rm -d \
    --name "$domain" \
    -e "VIRTUAL_HOST=${domain}" \
    -e "LETSENCRYPT_HOST=${domain}" \
    --network "${networks_map[i]}" \
    nginx:alpine > /dev/null && echo "Started test web server for $domain in net ${networks_map[${i}]}"

  i=$(( $i + 1 ))
done

i=0
for domain in "${domains[@]}"; do
  if [ "${networks_map[i]}" != "$desired_network" ]; then
     echo "$domain is not in $desired_network, cert should not be generated";

     service_data="$(docker exec "$le_container_name" cat /app/letsencrypt_service_data)"
     if grep -q "$domain" <<< "$service_data"; then
       echo "Domain $domain is on data list, but MUST not!"
     else
       echo "Domain $domain was not included in the service_data."
     fi
  else
      echo "$domain is in $desired_network, cert should be generated";

      # Wait for a symlink at /etc/nginx/certs/$domain.crt
      wait_for_symlink "$domain" "$le_container_name"
  fi
  # Stop the Nginx container silently.
  docker stop "$domain" > /dev/null
  i=$(( $i + 1 ))
done
