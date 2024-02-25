#!/bin/bash

## Test for Network segregation.

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

run_le_container ${1:?} "$le_container_name" "--env NETWORK_SCOPE=$test_net"

# Create the $domains array from comma separated domains in TEST_DOMAINS.
IFS=',' read -r -a domains <<< "$TEST_DOMAINS"

# Cleanup function with EXIT trap
function cleanup {
  # Remove any remaining Nginx container(s) silently.
  for domain in "${domains[@]}"; do
    docker rm --force "$domain" > /dev/null 2>&1
  done
  # Cleanup the files created by this run of the test to avoid foiling following test(s).
  docker exec "$le_container_name" /app/cleanup_test_artifacts
  # Remove the LE container, as it it network-scoped and may affect following test(s).
  docker rm --force "$le_container_name" > /dev/null
  # Drop temp network
  docker network rm "le_test_other_net1" > /dev/null
  docker network rm "le_test_other_net2" > /dev/null
}
trap cleanup EXIT

docker network create "le_test_other_net1" > /dev/null
docker network create "le_test_other_net2" > /dev/null

networks_map=("$test_net" le_test_other_net1 le_test_other_net2)

# Run a separate nginx container for each domain in the $domains array.
# Start all the containers in a row so that docker-gen debounce timers fire only once.
i=0
for domain in "${domains[@]}"; do
  docker run --rm -d \
    --name "$domain" \
    -e "VIRTUAL_HOST=${domain}" \
    -e "LETSENCRYPT_HOST=${domain}" \
    --network "${networks_map[i]}" \
    nginx:alpine > /dev/null && echo "Started test web server for $domain in the network ${i}"

  i=$(( $i + 1 ))
done

i=0
for domain in "${domains[@]}"; do
  if [ "${networks_map[i]}" != "$test_net" ]; then
     echo "$domain is not in the primary network, cert should not be generated";

     service_data="$(docker exec "$le_container_name" cat /app/letsencrypt_service_data)"
     if grep -q "$domain" <<< "$service_data"; then
       echo "Domain $domain is on data list, but MUST not!"
     else
       echo "Domain $domain was not included in the service_data."
     fi
  else
      echo "$domain is in the primary network, cert should be generated";
      wait_for_symlink "$domain" "$le_container_name"
  fi
  # Stop the Nginx container silently.
  docker stop "$domain" > /dev/null
  i=$(( $i + 1 ))
done

