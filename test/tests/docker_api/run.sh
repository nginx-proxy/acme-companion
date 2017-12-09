#!/bin/bash

## Test for the Docker API.

nginx_labeled_container_name='nginx-proxy-label'
docker_gen_unlabeled_container_name='nginx-proxy-gen-nolabel'

case $SETUP in

  2containers)
  cat > ${TRAVIS_BUILD_DIR}/test/tests/docker_api/expected_std_out.txt <<EOF
Container $NGINX_CONTAINER_NAME received exec_start: sh -c /usr/local/bin/docker-gen /app/nginx.tmpl /etc/nginx/conf.d/default.conf; /usr/sbin/nginx -s reload
Container $nginx_labeled_container_name received exec_start: sh -c /usr/local/bin/docker-gen /app/nginx.tmpl /etc/nginx/conf.d/default.conf; /usr/sbin/nginx -s reload
EOF

  # Listen to Docker exec_start events
  docker events \
    --filter event=exec_start \
    --format 'Container {{.Actor.Attributes.name}} received {{.Action}}' &
  docker_events_pid=$!

  # Spawn a nginx-proxy container with the nginx_proxy label
  # The setup already spawned a container without the label
  docker run --rm -d \
    --name "$nginx_labeled_container_name" \
    -v /var/run/docker.sock:/tmp/docker.sock:ro \
    --label com.github.jrcs.letsencrypt_nginx_proxy_companion.nginx_proxy \
    jwilder/nginx-proxy > /dev/null

  # This should exec into the nginx-proxy container without the label (nginx-proxy)
  docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock:ro \
    -e "NGINX_PROXY_CONTAINER=$NGINX_CONTAINER_NAME" \
    "$1" \
    bash -c 'source /app/functions.sh && reload_nginx' > /dev/null

  # This should should exec into the nginx-proxy container with the label (nginx-proxy-label)
  docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock:ro \
    "$1" \
    bash -c 'source /app/functions.sh && reload_nginx' > /dev/null

  # Cleanup
  kill $docker_events_pid && wait $docker_events_pid 2>/dev/null
  docker stop "$nginx_labeled_container_name" > /dev/null
  ;;

  3containers)
  cat > ${TRAVIS_BUILD_DIR}/test/tests/docker_api/expected_std_out.txt <<EOF
Container $docker_gen_unlabeled_container_name received signal 1
Container $NGINX_CONTAINER_NAME received signal 1
Container $DOCKER_GEN_CONTAINER_NAME received signal 1
Container $nginx_labeled_container_name received signal 1
EOF

  # Listen to Docker kill events
  docker events \
    --filter event=kill \
    --format 'Container {{.Actor.Attributes.name}} received signal {{.Actor.Attributes.signal}}' &
  docker_events_pid=$!

  # Spawn a nginx container with the nginx_proxy label
  # The setup already spawned a container without the label
  docker run --rm -d \
    --name "$nginx_labeled_container_name" \
    --label com.github.jrcs.letsencrypt_nginx_proxy_companion.nginx_proxy \
    nginx:alpine > /dev/null

  # Spawn a fake docker-gen container without the docker-gen label
  # The setup already spawned a container with the label
  docker run --rm -d \
    --name "$docker_gen_unlabeled_container_name" \
    nginx:alpine > /dev/null

  # This should send SIGHUP to the non labeled docker-gen and nginx (nginx-proxy-gen-nolabel and nginx-proxy)
  docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock:ro \
    -e "NGINX_PROXY_CONTAINER=$NGINX_CONTAINER_NAME" \
    -e "NGINX_DOCKER_GEN_CONTAINER=$docker_gen_unlabeled_container_name" \
    "$1" \
    bash -c 'source /app/functions.sh && reload_nginx' > /dev/null

  # This should send SIGHUP to the labeled docker-gen and nginx (nginx-proxy-gen and nginx-proxy-label)
  docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock:ro \
    "$1" \
    bash -c 'source /app/functions.sh && reload_nginx' > /dev/null

  # Cleanup
  kill $docker_events_pid && wait $docker_events_pid 2>/dev/null
  docker stop \
    "$nginx_labeled_container_name" \
    "$docker_gen_unlabeled_container_name" > /dev/null
  ;;
esac
