#!/bin/bash

## issue #1006: reload_nginx and check_nginx_proxy_container_run must handle
## several nginx-proxy replicas that share the same detection label.

docker_gen='replicas-docker-gen'
nginx1='replicas-nginx-1'
nginx2='replicas-nginx-2'
aio1='replicas-aio-1'
aio2='replicas-aio-2'
companion_aio='replicas-companion-aio'
events_file="$(mktemp)"

function cleanup {
  kill "${docker_events_pid}" 2>/dev/null && wait "${docker_events_pid}" 2>/dev/null
  rm -f "${events_file}"
  docker rm --force "${docker_gen}" "${nginx1}" "${nginx2}" "${aio1}" "${aio2}" "${companion_aio}" &> /dev/null
}
trap cleanup EXIT

## Part 1: separate docker-gen + several nginx replicas (reload via SIGHUP).

# A fake docker-gen so reload_nginx takes the separate-container (SIGHUP) path.
docker run --rm -d --name "${docker_gen}" --label com.github.nginx-proxy.docker-gen nginx:alpine > /dev/null

# Two nginx replicas sharing the same nginx-proxy detection label.
docker run --rm -d --name "${nginx1}" --label com.github.nginx-proxy.nginx nginx:alpine > /dev/null
docker run --rm -d --name "${nginx2}" --label com.github.nginx-proxy.nginx nginx:alpine > /dev/null

# Record kill (SIGHUP) events.
docker events --filter event=kill \
  --format '{{.Actor.Attributes.name}} {{.Actor.Attributes.signal}}' > "${events_file}" &
docker_events_pid=$!

# Run reload + health-check inside the companion.
commands='source /app/functions.sh; reload_nginx > /dev/null; check_nginx_proxy_container_run && echo CHECK_OK'
out="$(docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  "$1" \
  bash -c "${commands}" 2>&1)"

# Wait (up to ~10s) for both replicas' SIGHUP to be recorded.
timeout="$(($(date +%s) + 10))"
until grep -qE "^${nginx1} (1|SIGHUP)$" "${events_file}" && grep -qE "^${nginx2} (1|SIGHUP)$" "${events_file}"; do
  [[ "$(date +%s)" -gt "${timeout}" ]] && break
  sleep 0.5
done

# The health-check must succeed when several replicas share the label.
if ! grep -q 'CHECK_OK' <<< "${out}"; then
  echo "check_nginx_proxy_container_run did not succeed with multiple nginx replicas (issue #1006): ${out}"
fi

# Both replicas must have received SIGHUP on reload (order-independent).
for name in "${nginx1}" "${nginx2}"; do
  if ! grep -qE "^${name} (1|SIGHUP)$" "${events_file}"; then
    echo "nginx replica ${name} did not receive SIGHUP on reload (issue #1006)."
  fi
done

## Part 2: several all-in-one nginx-proxy replicas (bundled docker-gen, no separate
## docker-gen). The companion startup check must detect the bundled docker-gen across
## replicas instead of failing with "can't get docker-gen container id" (issue #1006).
docker run --rm -d --name "${aio1}" --label com.github.nginx-proxy.nginx \
  -v /var/run/docker.sock:/tmp/docker.sock:ro nginxproxy/nginx-proxy > /dev/null
docker run --rm -d --name "${aio2}" --label com.github.nginx-proxy.nginx \
  -v /var/run/docker.sock:/tmp/docker.sock:ro nginxproxy/nginx-proxy > /dev/null

# Start the companion through its real entrypoint (anonymous writable volumes so the
# later checks pass). With the bug it exits early on the docker-gen detection.
docker run -d --name "${companion_aio}" \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -v /etc/nginx/certs \
  -v /etc/acme.sh \
  "$1" > /dev/null
sleep 6

if docker logs "${companion_aio}" 2>&1 | grep -q "can't get docker-gen container id"; then
  echo "companion failed to start with multiple all-in-one nginx-proxy replicas (issue #1006)."
fi
if [[ "$(docker inspect -f '{{.State.Running}}' "${companion_aio}" 2>/dev/null)" != 'true' ]]; then
  echo "companion is not running with multiple all-in-one nginx-proxy replicas (issue #1006)."
fi
