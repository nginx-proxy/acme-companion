#!/bin/bash

# Check that the companion container reports a 'healthy' Docker health status
# once its background services are running (issue #709).

if [[ -z $GITHUB_ACTIONS ]]; then
  le_container_name="$(basename "${0%/*}")_$(date "+%Y-%m-%d_%H.%M.%S")"
else
  le_container_name="$(basename "${0%/*}")"
fi
run_le_container "${1:?}" "$le_container_name"

function cleanup {
  # Cleanup the files created by this run of the test to avoid foiling following test(s).
  docker exec "$le_container_name" /app/cleanup_test_artifacts
  # Stop the LE container
  docker stop "$le_container_name" > /dev/null
}
trap cleanup EXIT

# Wait for the container to report a healthy status.
timeout="$(($(date +%s) + 120))"
until [[ "$(docker inspect --format '{{.State.Health.Status}}' "$le_container_name" 2>/dev/null)" == 'healthy' ]]; do
  if [[ "$(date +%s)" -gt "$timeout" ]]; then
    status="$(docker inspect --format '{{.State.Health.Status}}' "$le_container_name" 2>/dev/null)"
    echo "Container $le_container_name did not become healthy within two minutes (status: ${status})."
    exit 1
  fi
  sleep 1
done
