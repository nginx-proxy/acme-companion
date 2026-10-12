#!/bin/bash

## Test for standalone certificates obtained for containers with an
## ACME_HOST / LETSENCRYPT_HOST environment variable but no VIRTUAL_HOST.

case ${ACME_CA} in
  pebble)
    test_net='acme_net'
  ;;
  boulder)
    test_net='boulder_bluenet'
  ;;
  *)
    echo "$0 ${ACME_CA}: invalid option."
    exit 1
esac

if [[ -z ${GITHUB_ACTIONS} ]]; then
  le_container_name="$(basename "${0%/*}")_$(date "+%Y-%m-%d_%H.%M.%S")"
else
  le_container_name="$(basename "${0%/*}")"
fi

# Create the ${domains} array from comma separated domains in TEST_DOMAINS.
IFS=',' read -r -a domains <<< "${TEST_DOMAINS}"

# Cleanup function with EXIT trap
function cleanup {
  # Remove the test containers silently.
  docker rm --force "${domains[0]}" "${domains[1]}" &> /dev/null
  # Cleanup the files created by this run of the test to avoid foiling following test(s).
  docker exec "${le_container_name}" cleanup_test_artifacts
  # Stop the LE container
  docker stop "${le_container_name}" > /dev/null
}
trap cleanup EXIT

run_le_container "${1:?}" "${le_container_name}"

# Proxied container: must not go through the standalone flow.
run_nginx_container --hosts "${domains[0]}"

# Container with only LETSENCRYPT_HOST: certificate obtained through the standalone flow.
if ! docker run --rm -d \
    --name "${domains[1]}" \
    -e "LETSENCRYPT_HOST=${domains[1]}" \
    --label com.github.nginx-proxy.acme-companion.test-suite \
    --network "${test_net}" \
    nginx:alpine > /dev/null;
then
  echo "Could not start test container for ${domains[1]}"
elif [[ "${DRY_RUN:-}" == 1 ]]; then
  echo "Started test container for ${domains[1]}"
fi

# Wait for a file at /etc/nginx/conf.d/standalone-cert-${domains[1]}.conf
wait_for_standalone_conf "${domains[1]}" "${le_container_name}"

# Wait for a symlink at /etc/nginx/certs/${domains[1]}.crt
if wait_for_symlink "${domains[1]}" "${le_container_name}"; then
  # then grab the certificate in text form ...
  created_cert="$(docker exec "${le_container_name}" \
    openssl x509 -in "/etc/nginx/certs/${domains[1]}/cert.pem" -text -noout)"
fi

# Check if the domain is on the certificate.
if ! grep -q "${domains[1]}" <<< "${created_cert}"; then
  echo "Domain ${domains[1]} did not appear on certificate."
elif [[ "${DRY_RUN:-}" == 1 ]]; then
  echo "Domain ${domains[1]} is on certificate."
fi

# The standalone conf is removed once the certificate is issued; wait for that.
wait_for_standalone_conf_rm "${domains[1]}" "${le_container_name}"

# The proxied container's certificate is obtained through the regular flow.
if wait_for_symlink "${domains[0]}" "${le_container_name}"; then
  created_cert="$(docker exec "${le_container_name}" \
    openssl x509 -in "/etc/nginx/certs/${domains[0]}/cert.pem" -text -noout)"
fi
if ! grep -q "${domains[0]}" <<< "${created_cert}"; then
  echo "Domain ${domains[0]} did not appear on certificate."
elif [[ "${DRY_RUN:-}" == 1 ]]; then
  echo "Domain ${domains[0]} is on certificate."
fi

# Only the container without VIRTUAL_HOST should be listed in ACME_STANDALONE_CONTAINERS.
standalone_cid="$(docker inspect --format '{{.Id}}' "${domains[1]}" | cut -c1-12)"
proxied_cid="$(docker inspect --format '{{.Id}}' "${domains[0]}" | cut -c1-12)"
standalone_containers="$(docker exec "${le_container_name}" \
  bash -c 'source /app/letsencrypt_service_data && echo "${ACME_STANDALONE_CONTAINERS[*]}"')"
if ! grep -q "${standalone_cid}" <<< "${standalone_containers}"; then
  echo "Container ${domains[1]} (${standalone_cid}) is missing from ACME_STANDALONE_CONTAINERS."
fi
if grep -q "${proxied_cid}" <<< "${standalone_containers}"; then
  echo "Proxied container ${domains[0]} (${proxied_cid}) should not be in ACME_STANDALONE_CONTAINERS."
fi
