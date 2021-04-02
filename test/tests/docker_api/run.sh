#!/bin/bash

## Test for the Docker API.

nginx_vol='nginx-volumes-from'
nginx_env='nginx-env-var'
nginx_lbl='nginx-label'
docker_gen='docker-gen-no-label'
docker_gen_lbl='docker-gen-label'

case $SETUP in

  2containers)
  # Cleanup function with EXIT trap
  function cleanup {
    # Kill the Docker events listener
    kill "$docker_events_pid" && wait "$docker_events_pid" 2>/dev/null
    # Remove the remaining containers silently
    docker rm --force \
      "$nginx_vol" \
      "$nginx_env" \
      "$nginx_lbl" \
      &> /dev/null
  }
  trap cleanup EXIT

  # Set the commands to be passed to docker exec
  commands='source /app/functions.sh; reload_nginx > /dev/null; check_nginx_proxy_container_run; get_nginx_proxy_container'

  # Listen to Docker exec_start events
  docker events \
    --filter event=exec_start \
    --format 'Container {{.Actor.Attributes.name}} received {{.Action}}' &
  docker_events_pid=$!

  # Run a nginx-proxy container named nginx-volumes-from, without the nginx_proxy label
  docker run --rm -d \
    --name "$nginx_vol" \
    -v /var/run/docker.sock:/tmp/docker.sock:ro \
    nginxproxy/nginx-proxy > /dev/null

  # Run a nginx-proxy container named nginx-env-var, without the nginx_proxy label
  docker run --rm -d \
    --name "$nginx_env" \
    -v /var/run/docker.sock:/tmp/docker.sock:ro \
    nginxproxy/nginx-proxy > /dev/null

  # This should target the nginx-proxy container obtained with
  # the --volume-from argument (nginx-volumes-from)
  docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock:ro \
    --volumes-from "$nginx_vol" \
    "$1" \
    bash -c "$commands" 2>&1

  # This should target the nginx-proxy container obtained with
  # the NGINX_PROXY_CONTAINER environment variable (nginx-env-var)
  docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock:ro \
    --volumes-from "$nginx_vol" \
    -e "NGINX_PROXY_CONTAINER=$nginx_env" \
    "$1" \
    bash -c "$commands" 2>&1

  # Run a nginx-proxy container named nginx-label, with the nginx_proxy label.
  # Store the container id in the labeled_nginx_cid variable.
  labeled_nginx_cid="$(docker run --rm -d \
    --name "$nginx_lbl" \
    -v /var/run/docker.sock:/tmp/docker.sock:ro \
    --label com.github.jrcs.letsencrypt_nginx_proxy_companion.nginx_proxy \
    nginxproxy/nginx-proxy)"

  # This should target the nginx-proxy container with the label (nginx-label)
  docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock:ro \
    --volumes-from "$nginx_vol" \
    -e "NGINX_PROXY_CONTAINER=$nginx_env" \
    "$1" \
    bash -c "$commands" 2>&1

  cat > "${GITHUB_WORKSPACE}/test/tests/docker_api/expected-std-out.txt" <<EOF
Container $nginx_vol received exec_start: sh -c /app/docker-entrypoint.sh /usr/local/bin/docker-gen /app/nginx.tmpl /etc/nginx/conf.d/default.conf; /usr/sbin/nginx -s reload
$nginx_vol
Container $nginx_env received exec_start: sh -c /app/docker-entrypoint.sh /usr/local/bin/docker-gen /app/nginx.tmpl /etc/nginx/conf.d/default.conf; /usr/sbin/nginx -s reload
$nginx_env
Container $nginx_lbl received exec_start: sh -c /app/docker-entrypoint.sh /usr/local/bin/docker-gen /app/nginx.tmpl /etc/nginx/conf.d/default.conf; /usr/sbin/nginx -s reload
$labeled_nginx_cid
EOF
  ;;

  3containers)
  # Cleanup function with EXIT trap
  function cleanup {
    # Kill the Docker events listener
    kill $docker_events_pid && wait $docker_events_pid 2>/dev/null
    # Remove the remaining containers silently
    docker stop \
      "$nginx_vol" \
      "$nginx_env" \
      "$nginx_lbl" \
      "$docker_gen" \
      "$docker_gen_lbl" \
      &> /dev/null
  }
  trap cleanup EXIT

  # Set the commands to be passed to docker exec
  commands='source /app/functions.sh; reload_nginx > /dev/null; check_nginx_proxy_container_run; get_docker_gen_container; get_nginx_proxy_container'

  # Listen to Docker kill events
  docker events \
    --filter event=kill \
    --format 'Container {{.Actor.Attributes.name}} received signal {{.Actor.Attributes.signal}}' &
  docker_events_pid=$!

  # Run a nginx container named nginx-volumes-from, without the nginx_proxy label.
  docker run --rm -d \
    --name "$nginx_vol" \
    -v /var/run/docker.sock:/tmp/docker.sock:ro \
    nginx:alpine > /dev/null

  # Run a nginx container named nginx-env-var, without the nginx_proxy label.
  docker run --rm -d \
    --name "$nginx_env" \
    -v /var/run/docker.sock:/tmp/docker.sock:ro \
    nginx:alpine > /dev/null

  # Spawn a "fake docker-gen" container named docker-gen-nolabel, without the docker_gen label.
  docker run --rm -d \
    --name "$docker_gen" \
    nginx:alpine > /dev/null

  # This should target the nginx container whose id or name was obtained with
  # the --volumes-from argument (nginx-volumes-from)
  # and the docker-gen container whose id or name was obtained with
  # the NGINX_DOCKER_GEN_CONTAINER environment variable (docker-gen-nolabel).
  docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock:ro \
    --volumes-from "$nginx_vol" \
    -e "NGINX_DOCKER_GEN_CONTAINER=$docker_gen" \
    "$1" \
    bash -c "$commands" 2>&1

  # This should target the nginx container whose id or name was obtained with
  # the NGINX_PROXY_CONTAINER environment variable (nginx-env-var)
  # and the docker-gen container whose id or name was obtained with
  # the NGINX_DOCKER_GEN_CONTAINER environment variable (docker-gen-nolabel)
  docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock:ro \
    --volumes-from "$nginx_vol" \
    -e "NGINX_PROXY_CONTAINER=$nginx_env" \
    -e "NGINX_DOCKER_GEN_CONTAINER=$docker_gen" \
    "$1" \
    bash -c "$commands" 2>&1

  # Spawn a nginx container named nginx-label, with the nginx_proxy label.
  labeled_nginx1_cid="$(docker run --rm -d \
    --name "$nginx_lbl" \
    --label com.github.jrcs.letsencrypt_nginx_proxy_companion.nginx_proxy \
    nginx:alpine)"

  # This should target the nginx container whose id or name was obtained with
  # the nginx_proxy label (nginx-label)
  # and the docker-gen container whose id or name was obtained with
  # the NGINX_DOCKER_GEN_CONTAINER environment variable (docker-gen-nolabel)
  docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock:ro \
    --volumes-from "$nginx_vol" \
    -e "NGINX_PROXY_CONTAINER=$nginx_env" \
    -e "NGINX_DOCKER_GEN_CONTAINER=$docker_gen" \
    "$1" \
    bash -c "$commands" 2>&1

  docker stop "$nginx_lbl" > /dev/null

  # Spawn a "fake docker-gen" container named docker-gen-label, with the docker_gen label.
  labeled_docker_gen_cid="$(docker run --rm -d \
    --name "$docker_gen_lbl" \
    --label com.github.jrcs.letsencrypt_nginx_proxy_companion.docker_gen \
    nginx:alpine)"

  # This should target the nginx container whose id or name was obtained with
  # the --volumes-from argument (nginx-volumes-from)
  # and the docker-gen container whose id or name was obtained with
  # the docker_gen label (docker-gen-label)
  docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock:ro \
    --volumes-from "$nginx_vol" \
    -e "NGINX_DOCKER_GEN_CONTAINER=$docker_gen" \
    "$1" \
    bash -c "$commands" 2>&1

  # This should target the nginx container whose id or name was obtained with
  # the NGINX_PROXY_CONTAINER environment variable (nginx-env-var)
  # and the docker-gen container whose id or name was obtained with
  # the docker_gen label (docker-gen-label)
  docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock:ro \
    --volumes-from "$nginx_vol" \
    -e "NGINX_PROXY_CONTAINER=$nginx_env" \
    -e "NGINX_DOCKER_GEN_CONTAINER=$docker_gen" \
    "$1" \
    bash -c "$commands" 2>&1

  # Spawn a nginx container named nginx-label, with the nginx_proxy label.
  labeled_nginx2_cid="$(docker run --rm -d \
    --name "$nginx_lbl" \
    --label com.github.jrcs.letsencrypt_nginx_proxy_companion.nginx_proxy \
    nginx:alpine)"

  # This should target the nginx container whose id or name was obtained with
  # the nginx_proxy label (nginx-label)
  # and the docker-gen container whose id or name was obtained with
  # the docker_gen label (docker-gen-label)
  docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock:ro \
    --volumes-from "$nginx_vol" \
    -e "NGINX_PROXY_CONTAINER=$nginx_env" \
    -e "NGINX_DOCKER_GEN_CONTAINER=$docker_gen" \
    "$1" \
    bash -c "$commands" 2>&1

    cat > "${GITHUB_WORKSPACE}/test/tests/docker_api/expected-std-out.txt" <<EOF
Container $docker_gen received signal 1
Container $nginx_vol received signal 1
$docker_gen
$nginx_vol
Container $docker_gen received signal 1
Container $nginx_env received signal 1
$docker_gen
$nginx_env
Container $docker_gen received signal 1
Container $nginx_lbl received signal 1
$docker_gen
$labeled_nginx1_cid
Container $nginx_lbl received signal 3
Container $docker_gen_lbl received signal 1
Container $nginx_vol received signal 1
$labeled_docker_gen_cid
$nginx_vol
Container $docker_gen_lbl received signal 1
Container $nginx_env received signal 1
$labeled_docker_gen_cid
$nginx_env
Container $docker_gen_lbl received signal 1
Container $nginx_lbl received signal 1
$labeled_docker_gen_cid
$labeled_nginx2_cid
EOF
  ;;

esac
