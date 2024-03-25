#!/bin/bash

## Test for standalone certificates.

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

# Create the $domains array from comma separated domains in TEST_DOMAINS.
IFS=',' read -r -a domains <<< "$TEST_DOMAINS"
subdomain="sub.${domains[0]}"

# Cleanup function with EXIT trap
function cleanup {
  # Remove the Nginx container silently.
  docker rm --force "$subdomain" &> /dev/null
  # Cleanup the files created by this run of the test to avoid foiling following test(s).
  docker exec "$le_container_name" /app/cleanup_test_artifacts
  # Stop the LE container
  docker stop "$le_container_name" > /dev/null
}
trap cleanup EXIT

# Create letsencrypt_user_data with a single domain cert
cat > "${GITHUB_WORKSPACE}/test/tests/certs_standalone/letsencrypt_user_data" <<EOF
LETSENCRYPT_STANDALONE_CERTS=('single')
LETSENCRYPT_single_HOST=('${domains[0]}')
EOF

# Run an nginx container with a VIRTUAL_HOST set to a subdomain of ${domains[0]} in order to check for
# this regression : https://github.com/nginx-proxy/acme-companion/issues/674
if ! docker run --rm -d \
    --name "$subdomain" \
    -e "VIRTUAL_HOST=$subdomain" \
    --network "$test_net" \
    nginx:alpine > /dev/null;
then
  echo "Could not start test web server for $subdomain"
elif [[ "${DRY_RUN:-}" == 1 ]]; then
  echo "Started test web server for $subdomain"
fi

run_le_container "${1:?}" "$le_container_name" \
  "--volume ${GITHUB_WORKSPACE}/test/tests/certs_standalone/letsencrypt_user_data:/app/letsencrypt_user_data"

# Wait for a file at /etc/nginx/conf.d/standalone-cert-${domains[0]}.conf
wait_for_standalone_conf "${domains[0]}" "$le_container_name"

# Wait for a symlink at /etc/nginx/certs/${domains[0]}.crt
if wait_for_symlink "${domains[0]}" "$le_container_name"; then
  # then grab the certificate in text form ...
  created_cert="$(docker exec "$le_container_name" \
    openssl x509 -in "/etc/nginx/certs/${domains[0]}/cert.pem" -text -noout)"
fi

# Check if the domain is on the certificate.
if ! grep -q "${domains[0]}" <<< "$created_cert"; then
  echo "Domain ${domains[0]} did not appear on certificate."
elif [[ "${DRY_RUN:-}" == 1 ]]; then
  echo "Domain ${domains[0]} is on certificate."
fi

docker exec "$le_container_name" bash -c "[[ -f /etc/nginx/conf.d/standalone-cert-${domains[0]}.conf ]]" \
  && echo "Standalone configuration for ${domains[0]} wasn't correctly removed."

# Add another (SAN) certificate to letsencrypt_user_data
cat > "${GITHUB_WORKSPACE}/test/tests/certs_standalone/letsencrypt_user_data" <<EOF
LETSENCRYPT_STANDALONE_CERTS=('single' 'san')
LETSENCRYPT_single_HOST=('${domains[0]}')
LETSENCRYPT_san_HOST=('${domains[1]}' '${domains[2]}')
EOF

# Manually trigger the service loop
docker exec "$le_container_name" /app/signal_le_service > /dev/null

for domain in "${domains[1]}" "${domains[2]}"; do
  # Wait for a file at /etc/nginx/conf.d/standalone-cert-$domain.conf
  wait_for_standalone_conf "$domain" "$le_container_name"
done

# Wait for a symlink at /etc/nginx/certs/${domains[1]}.crt
if wait_for_symlink "${domains[1]}" "$le_container_name"; then
  # then grab the certificate in text form ...
  created_cert="$(docker exec "$le_container_name" \
    openssl x509 -in "/etc/nginx/certs/${domains[1]}/cert.pem" -text -noout)"
fi

for domain in "${domains[1]}" "${domains[2]}"; do
  # Check if the domain is on the certificate.
  if ! grep -q "$domain" <<< "$created_cert"; then
    echo "Domain $domain did not appear on certificate."
  elif [[ "${DRY_RUN:-}" == 1 ]]; then
    echo "Domain $domain is on certificate."
  fi
done

docker exec "$le_container_name" bash -c "[[ ! -f /etc/nginx/conf.d/standalone-cert-${domains[1]}.conf ]]" \
  || echo "Standalone configuration for ${domains[1]} wasn't correctly removed."
