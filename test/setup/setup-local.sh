#!/bin/bash

set -e

function get_environment {
  dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

  LOCAL_BUILD_DIR="$(cd "$dir/../.." && pwd)"
  export TRAVIS_BUILD_DIR="$LOCAL_BUILD_DIR"

  # shellcheck source=/dev/null
  [[ -f "${TRAVIS_BUILD_DIR}/test/local_test_env.sh" ]] && \
    source "${TRAVIS_BUILD_DIR}/test/local_test_env.sh"

  # Get the environment variables from the .travis.yml file with sed
  declare -a travis_yml
  travis_yml[0]="$(sed -n 's/.*- NGINX_CONTAINER_NAME=//p' "$LOCAL_BUILD_DIR/.travis.yml")"
  travis_yml[1]="$(sed -n 's/.*- DOCKER_GEN_CONTAINER_NAME=//p' "$LOCAL_BUILD_DIR/.travis.yml")"
  travis_yml[2]="$(sed -n 's/.*- TEST_DOMAINS=//p' "$LOCAL_BUILD_DIR/.travis.yml")"

  # If environment variable where sourced or manually set use them, else use those from .travis.yml
  export NGINX_CONTAINER_NAME="${NGINX_CONTAINER_NAME:-${travis_yml[0]}}"
  export DOCKER_GEN_CONTAINER_NAME="${DOCKER_GEN_CONTAINER_NAME:-${travis_yml[1]}}"
  export TEST_DOMAINS="${TEST_DOMAINS:-${travis_yml[2]}}"

  # Build the array containing domains to add to /etc/hosts
  IFS=',' read -r -a domains <<< "$TEST_DOMAINS"

  if [[ -z $SETUP ]]; then
    while true; do
      echo "Which nginx-proxy setup do you want to test or remove ?"
      echo ""
      echo "    1) Two containers setup (nginx-proxy + le-companion)"
      echo "    2) Three containers setup (nginx + docker-gen + le-companion)"
      read -re -p "Select an option [1-2]: " option
      case $option in
        1)
        setup="2containers"
        break
        ;;
        2)
        setup="3containers"
        break
        ;;
        *)
        :
        ;;
      esac
    done
  fi

  export SETUP="${SETUP:-$setup}"
}

case $1 in
  --setup)
    get_environment

    # Prepare the env file that run.sh will source
    cat > "${TRAVIS_BUILD_DIR}/test/local_test_env.sh" <<EOF
export TRAVIS_BUILD_DIR="$LOCAL_BUILD_DIR"
export NGINX_CONTAINER_NAME="$NGINX_CONTAINER_NAME"
export DOCKER_GEN_CONTAINER_NAME="$DOCKER_GEN_CONTAINER_NAME"
export TEST_DOMAINS="$TEST_DOMAINS"
export SETUP="$SETUP"
EOF

    # Add the required custom entries to /etc/hosts
    echo "Adding custom entries to /etc/hosts (requires sudo)."
    for domain in "${domains[@]}"; do
      grep -q "127.0.0.1 $domain # le-companion test suite" /etc/hosts \
        || echo "127.0.0.1 $domain # le-companion test suite" \
        | sudo tee -a /etc/hosts
    done

    # Pull nginx:alpine
    docker pull nginx:alpine

    # Prepare the test setup using the setup scripts
    "${TRAVIS_BUILD_DIR}/test/setup/setup-boulder.sh"
    "${TRAVIS_BUILD_DIR}/test/setup/setup-nginx-proxy.sh"
    ;;

  --teardown)
    get_environment

    # Stop and remove nginx-proxy and (if required) docker-gen
    for cid in $(docker ps -a --filter "label=com.github.jrcs.letsencrypt_nginx_proxy_companion.test_suite" --format "{{.ID}}"); do
      docker stop "$cid"
      docker rm --volumes "$cid"
    done

    # Stop and remove boulder
    docker-compose --project-name 'boulder' \
      --file "${TRAVIS_BUILD_DIR}/go/src/github.com/letsencrypt/boulder/docker-compose.yml" \
      down --volumes

    # Cleanup files created by the setup
    if [[ -n "${TRAVIS_BUILD_DIR// }" ]]; then
      [[ -f "${TRAVIS_BUILD_DIR}/nginx.tmpl" ]]&& rm "${TRAVIS_BUILD_DIR}/nginx.tmpl"
      rm "${TRAVIS_BUILD_DIR}/test/local_test_env.sh"
      echo "The ${TRAVIS_BUILD_DIR}/go folder require superuser permission to fully remove."
      echo "Doing sudo rm -rf in scripts is dangerous, so the folder won't be automatically removed."
    fi

    # Remove custom entries to /etc/hosts
    echo "Removing custom entries from /etc/hosts (requires sudo)."
    for domain in "${domains[@]}"; do
      if [[ "$(uname)" == 'Darwin' ]]; then
        sudo sed -i '' "/127\.0\.0\.1 $domain # le-companion test suite/d" /etc/hosts
      else
        sudo sed --in-place "/127\.0\.0\.1 $domain # le-companion test suite/d" /etc/hosts
      fi
    done
    ;;

    *)
    echo "Usage:"
    echo ""
    echo "    --setup : setup the test suite."
    echo "    --teardown : remove the test suite containers, configuration and files."
    echo ""
    ;;
esac
