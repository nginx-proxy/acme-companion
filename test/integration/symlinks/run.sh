#!/bin/bash

## Test for symlink creation / removal.

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
  # Remove all remaining nginx containers silently
  docker rm --force \
    symlink-le1-le2 \
    symlink-le1-le2-le3 \
    symlink-le2 \
    symlink-le3 \
    symlink-lim-le2 \
    &> /dev/null
  # Cleanup the files created by this run of the test to avoid foiling following test(s).
  docker exec "$le_container_name" /app/cleanup_test_artifacts
  # Stop the LE container
  docker stop "$le_container_name" > /dev/null
}
trap cleanup EXIT

# Run a nginx container for the firs two domain in the $domains array ...
run_nginx_container --hosts "${domains[0]},${domains[1]}" --name "symlink-le1-le2"

# ... plus another nginx container for the third domain.
run_nginx_container --hosts "${domains[2]}" --name "symlink-le3"

# Wait for a file at /etc/nginx/certs/$domain/cert.pem
wait_for_symlink "${domains[0]}" "$le_container_name" "./${domains[0]}/fullchain.pem"
wait_for_symlink "${domains[1]}" "$le_container_name" "./${domains[0]}/fullchain.pem"
wait_for_symlink "${domains[2]}" "$le_container_name" "./${domains[2]}/fullchain.pem"

# Create a fake le4.wtf custom certificate and key
docker exec "$le_container_name" mkdir -p /etc/nginx/certs/le4.wtf
docker exec "$le_container_name" cp /etc/nginx/certs/le1.wtf/fullchain.pem /etc/nginx/certs/le4.wtf/
docker exec "$le_container_name" cp /etc/nginx/certs/le1.wtf/key.pem /etc/nginx/certs/le4.wtf/
docker exec "$le_container_name" bash -c 'cd /etc/nginx/certs; ln -s ./le4.wtf/fullchain.pem ./le4.wtf.crt'
docker exec "$le_container_name" bash -c 'cd /etc/nginx/certs; ln -s ./le4.wtf/key.pem ./le4.wtf.key'

# Stop the nginx containers for ${domains[0]} and ${domains[1]} silently,
# then check if the corresponding symlinks are removed.
docker stop "symlink-le1-le2" > /dev/null
for domain in "${domains[@]::2}"; do
  wait_for_symlink_rm "$domain" "$le_container_name"
done

# Check if ${domains[2]} symlink is still there
docker exec "$le_container_name" [ -L "/etc/nginx/certs/${domains[2]}.crt" ] \
  || echo "Symlink to ${domains[2]} certificate was removed."

# Stop the nginx containers for ${domains[2]} silently,
# then check if the corresponding symlink is removed.
docker stop "symlink-le3" > /dev/null
wait_for_symlink_rm "${domains[2]}" "$le_container_name"

# Start the nginx containers for ${domains[2]} again,
# and check if the corresponding symlink is re-created.
run_nginx_container --hosts "${domains[2]}" --name "symlink-le3"
wait_for_symlink "${domains[2]}" "$le_container_name" "./${domains[2]}/fullchain.pem"

# Stop the nginx containers for ${domains[2]} silently and wait for symlink removal.
docker stop "symlink-le3" > /dev/null
wait_for_symlink_rm "${domains[2]}" "$le_container_name"

# Move ${domains[2]} to a san certificate with ${domains[0]} and ${domains[1]}
run_nginx_container --hosts "${domains[0]},${domains[1]},${domains[2]}" --name "symlink-le1-le2-le3"

# Check where the symlink points (should be ./le1.wtf/fullchain.pem)
wait_for_symlink "${domains[2]}" "$le_container_name" "./${domains[0]}/fullchain.pem"

# Stop the nginx container silently.
docker stop "symlink-le1-le2-le3" > /dev/null

# Check if the symlinks are correctly removed
for domain in "${domains[@]}"; do
  wait_for_symlink_rm "$domain" "$le_container_name"
done

# Move ${domains[1]} to a new single domain certificate
run_nginx_container --hosts "${domains[1]}" --name "symlink-le2"

# Check where the symlink points (should be ./le2.wtf/fullchain.pem)
wait_for_symlink "${domains[1]}" "$le_container_name" "./${domains[1]}/fullchain.pem"

# Stop the nginx container silently and try to put ${domains[1]} on a
# san certificate whose authorization will fail.
docker stop "symlink-le2" > /dev/null
run_nginx_container --hosts "lim.it,${domains[1]}" --name "symlink-lim-le2"

# The symlink creation for lim.it should time out, and the ${domains[1]}
# symlink should still point to ./le2.wtf/fullchain.pem
wait_for_symlink "lim.it" "$le_container_name"
wait_for_symlink "${domains[1]}" "$le_container_name" "./${domains[1]}/fullchain.pem"

# Aaaaaand stop the container.
docker stop "symlink-lim-le2" > /dev/null

# Check if the custom certificate is still there
docker exec "$le_container_name" [ -f /etc/nginx/certs/le4.wtf.crt ] \
  || echo "Custom certificate for le4.wtf was removed."
