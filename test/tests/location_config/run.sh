#!/bin/bash

## Test for automatic location configuration.

# Set variables
test_comment='### This is a test comment'
vhost_path='/etc/nginx/vhost.d'

# Create custom location configuration file to be bind mounted
location_file="${TRAVIS_BUILD_DIR}/test/tests/location_config/le2.wtf"
echo "$test_comment" > "$location_file"

# Create le1.wtf configuration file, *.le3.wtf and test.* from inside the nginx container
docker exec "$NGINX_CONTAINER_NAME" sh -c "echo '### This is a test comment' > /etc/nginx/vhost.d/le1.wtf"
docker exec "$NGINX_CONTAINER_NAME" sh -c "echo '### This is a test comment' > /etc/nginx/vhost.d/\*.example.com"
docker exec "$NGINX_CONTAINER_NAME" sh -c "echo '### This is a test comment' > /etc/nginx/vhost.d/test.\*"

# Zero the default configuration file.
docker exec "$NGINX_CONTAINER_NAME" sh -c "echo '' > /etc/nginx/vhost.d/default"

if [[ -z $TRAVIS ]]; then
  le_container_name="$(basename ${0%/*})_$(date "+%Y-%m-%d_%H.%M.%S")"
else
  le_container_name="$(basename ${0%/*})"
fi
run_le_container "${1:?}" "$le_container_name" "--volume $location_file:$vhost_path/le2.wtf"

# Create the $domains array from comma separated domains in TEST_DOMAINS.
IFS=',' read -r -a domains <<< "$TEST_DOMAINS"

# Cleanup function with EXIT trap
function cleanup {
  # Cleanup the files created by this run of the test to avoid foiling following test(s).
  docker exec "$le_container_name" bash -c 'rm -rf /etc/nginx/vhost.d/le1.wtf'
  docker exec "$le_container_name" bash -c 'rm -rf /etc/nginx/vhost.d/\*.example.com'
  docker exec "$le_container_name" bash -c 'rm -rf /etc/nginx/vhost.d/test.\*'
  # Stop the LE container
  docker stop "$le_container_name" > /dev/null
}
trap cleanup EXIT

# Check if the ACME location configuration was correctly applied (ie only once) to the target file
function check_location {
  local container="${1:?}"
  local path="${2:?}"
  local start_comment='## Start of configuration add by letsencrypt container'
  local end_comment='## End of configuration add by letsencrypt container'

  if [[ "$(docker exec "$container" grep -c "$start_comment" "$path")" != 1 ]]; then
    return 1
  elif [[ "$(docker exec "$container" grep -c "$end_comment" "$path")" != 1 ]]; then
    return 1
  else
    return 0
  fi
}

# check the wildcard location enumeration function
docker exec "$le_container_name" bash -c 'source /app/functions.sh; enumerate_wildcard_locations foo.bar.baz.example.com'

# default configuration file should be empty
config_path="$vhost_path/default"
if docker exec "$le_container_name" [ ! -s "$config_path" ]; then
  echo "$config_path should be empty at container startup:"
  docker exec "$le_container_name" cat "$config_path"
fi

# custom configuration files should only contains the test comment
for domain in "${domains[@]:0:2}" '*.example.com' 'test.*'; do
  config_path="$vhost_path/$domain"
  if check_location "$le_container_name" "$config_path"; then
    echo "Unexpected location configuration on $config_path at container startup:"
    docker exec "$le_container_name" cat "$config_path"
  elif ! docker exec "$le_container_name" grep -q "$test_comment" "$config_path"; then
    echo "$config_path should have test comment at container startup:"
    docker exec "$le_container_name" cat "$config_path"
  fi
done

# le3.wtf configuration file should not exist
config_path="$vhost_path/${domains[2]}"
if docker exec "$le_container_name" [ -e "$config_path" ]; then
  echo "$config_path should not exist at container startup :"
  docker exec "$le_container_name" ls -lh "$config_path"
  docker exec "$le_container_name" cat "$config_path"
fi

# Add default location configuration then check
config_path="$vhost_path/default"
docker exec "$le_container_name" bash -c 'source /app/functions.sh; add_location_configuration'
if ! check_location "$le_container_name" "$config_path" ; then
  echo "Unexpected location configuration on $config_path after call to add_location_configuration:"
  docker exec "$le_container_name" cat "$config_path"
fi

# Add le1.wtf and le2.wtf location configurations then check
for domain in "${domains[@]:0:2}"; do
  config_path="$vhost_path/$domain"
  docker exec "$le_container_name" bash -c "source /app/functions.sh; add_location_configuration $domain"
  if ! check_location "$le_container_name" "$config_path" ; then
    echo "Unexpected location configuration on $config_path after call to add_location_configuration $domain:"
    docker exec "$le_container_name" cat "$config_path"
  elif ! docker exec "$le_container_name" grep -q "$test_comment" "$config_path"; then
    echo "$config_path should still have test comment after call to add_location_configuration $domain:"
    docker exec "$le_container_name" cat "$config_path"
  fi
done

# Adding subdomain.example.com location configurations should use the *.example.com file
domain="subdomain.example.com"
config_path="$vhost_path/*.example.com"
docker exec "$le_container_name" bash -c "source /app/functions.sh; add_location_configuration $domain"
if ! check_location "$le_container_name" "$config_path" ; then
  echo "Unexpected location configuration on $config_path after call to add_location_configuration $domain:"
  docker exec "$le_container_name" cat "$config_path"
elif ! docker exec "$le_container_name" grep -q "$test_comment" "$config_path"; then
  echo "$config_path should still have test comment after call to add_location_configuration $domain:"
  docker exec "$le_container_name" cat "$config_path"
fi

# Adding test.domain.tld location configurations should use the test.* file
domain="test.domain.tld"
config_path="$vhost_path/test.*"
docker exec "$le_container_name" bash -c "source /app/functions.sh; add_location_configuration $domain"
if ! check_location "$le_container_name" "$config_path" ; then
  echo "Unexpected location configuration on $config_path after call to add_location_configuration $domain:"
  docker exec "$le_container_name" cat "$config_path"
elif ! docker exec "$le_container_name" grep -q "$test_comment" "$config_path"; then
  echo "$config_path should still have test comment after call to add_location_configuration $domain:"
  docker exec "$le_container_name" cat "$config_path"
fi

# Remove all location configurations
docker exec "$le_container_name" bash -c "source /app/functions.sh; remove_all_location_configurations"

# default configuration file should be empty again
config_path="$vhost_path/default"
if docker exec "$le_container_name" [ ! -s "$config_path" ]; then
  echo "$config_path should be empty after call to remove_all_location_configurations:"
  docker exec "$le_container_name" cat "$config_path"
fi

# Custom configuration files should have reverted to only containing the test comment
for domain in "${domains[@]:0:2}" '*.example.com' 'test.*'; do
  config_path="$vhost_path/$domain"
  if check_location "$le_container_name" "$config_path"; then
    echo "Unexpected location configuration on $config_path after call to remove_all_location_configurations:"
    docker exec "$le_container_name" cat "$config_path"
  elif ! docker exec "$le_container_name" grep -q "$test_comment" "$config_path"; then
    echo "$config_path should still have test comment after call to remove_all_location_configurations:"
    docker exec "$le_container_name" cat "$config_path"
  fi
done

# Trying to add location configuration to non existing le3.wtf should only configure default
docker exec "$le_container_name" bash -c "source /app/functions.sh; add_location_configuration ${domains[2]}"

config_path="$vhost_path/${domains[2]}"
if docker exec "$le_container_name" [ -e "$config_path" ]; then
  echo "$config_path should not exist after call to add_location_configuration ${domains[2]}:"
  docker exec "$le_container_name" ls -lh "$config_path"
  docker exec "$le_container_name" cat "$config_path"
fi

config_path="$vhost_path/default"
docker exec "$le_container_name" bash -c 'source /app/functions.sh; add_location_configuration'
if ! check_location "$le_container_name" "$config_path" ; then
  echo "Unexpected location configuration on $config_path after call to remove_all_location_configurations ${domains[2]}:"
  docker exec "$le_container_name" cat "$config_path"
fi
