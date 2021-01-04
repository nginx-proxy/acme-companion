#!/bin/bash

set -e

function get_environment {
  dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

  LOCAL_BUILD_DIR="$(cd "$dir/../.." && pwd)"
  export GITHUB_WORKSPACE="$LOCAL_BUILD_DIR"

  # shellcheck source=/dev/null
  [[ -f "${GITHUB_WORKSPACE}/test/local_test_env.sh" ]] && \
    source "${GITHUB_WORKSPACE}/test/local_test_env.sh"

  # Get the environment variables from the .github/workflows/test.yml file with sed
  declare -a ci_test_yml
  ci_test_yml[0]="$(sed -n 's/.* NGINX_CONTAINER_NAME: //p' "$LOCAL_BUILD_DIR/.github/workflows/test.yml")"
  ci_test_yml[1]="$(sed -n 's/.* DOCKER_GEN_CONTAINER_NAME: //p' "$LOCAL_BUILD_DIR/.github/workflows/test.yml")"
  ci_test_yml[2]="$(sed -n 's/.* TEST_DOMAINS: //p' "$LOCAL_BUILD_DIR/.github/workflows/test.yml")"

  # If environment variable where sourced or manually set use them, else use those from 
  # .github/workflows/test.yml
  export NGINX_CONTAINER_NAME="${NGINX_CONTAINER_NAME:-${ci_test_yml[0]}}"
  export DOCKER_GEN_CONTAINER_NAME="${DOCKER_GEN_CONTAINER_NAME:-${ci_test_yml[1]}}"
  export TEST_DOMAINS="${TEST_DOMAINS:-${ci_test_yml[2]}}"

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

  if [[ -z $ACME_CA ]]; then
    while true; do
      echo "Which ACME CA do you want to use or remove ?"
      echo ""
      echo "    1) Boulder https://github.com/letsencrypt/boulder"
      echo "    2) Pebble  https://github.com/letsencrypt/pebble"
      read -re -p "Select an option [1-2]: " option
      case $option in
        1)
        acme_ca="boulder"
        break
        ;;
        2)
        acme_ca="pebble"
        break
        ;;
        *)
        :
        ;;
      esac
    done
  fi
  export ACME_CA="${ACME_CA:-$acme_ca}"
}

case $1 in
  --setup)
    get_environment

    # Prepare the env file that run.sh will source
    cat > "${GITHUB_WORKSPACE}/test/local_test_env.sh" <<EOF
export GITHUB_WORKSPACE="$LOCAL_BUILD_DIR"
export NGINX_CONTAINER_NAME="$NGINX_CONTAINER_NAME"
export DOCKER_GEN_CONTAINER_NAME="$DOCKER_GEN_CONTAINER_NAME"
export TEST_DOMAINS="$TEST_DOMAINS"
export SETUP="$SETUP"
export ACME_CA="$ACME_CA"
EOF

    # Add the required custom entries to /etc/hosts
    echo "Adding custom entries to /etc/hosts (requires sudo)."
    declare -a hosts=("${domains[@]}")
    if [[ "$ACME_CA" == 'pebble' ]]; then
      hosts+=(pebble pebble-challtestsrv)
    fi
    for host in "${hosts[@]}"; do
      grep -q "127.0.0.1 $host # le-companion test suite" /etc/hosts \
        || echo "127.0.0.1 $host # le-companion test suite" \
        | sudo tee -a /etc/hosts
    done

    # Pull nginx:alpine
    docker pull nginx:alpine

    # Prepare the test setup using the setup scripts
    if [[ "$ACME_CA" == 'boulder' ]]; then
      "${GITHUB_WORKSPACE}/test/setup/setup-boulder.sh"
    elif [[ "$ACME_CA" == 'pebble' ]]; then
      "${GITHUB_WORKSPACE}/test/setup/setup-pebble.sh"
    else
      echo "ACME_CA is not set, aborting."
      exit 1
    fi
    "${GITHUB_WORKSPACE}/test/setup/setup-nginx-proxy.sh"
    ;;

  --teardown)
    get_environment

    # Stop and remove nginx-proxy and (if required) docker-gen
    for cid in $(docker ps -a --filter "label=com.github.jrcs.letsencrypt_nginx_proxy_companion.test_suite" --format "{{.ID}}"); do
      docker stop "$cid"
      docker rm --volumes "$cid"
    done

    if [[ "$ACME_CA" == 'boulder' ]]; then
      # Stop and remove boulder
      docker-compose --project-name 'boulder' \
        --file "${GITHUB_WORKSPACE}/go/src/github.com/letsencrypt/boulder/docker-compose.yml" \
        down --volumes
    elif [[ "$ACME_CA" == 'pebble' ]]; then
      docker network rm acme_net
      [[ -f "${GITHUB_WORKSPACE}/pebble.minica.pem" ]] && rm "${GITHUB_WORKSPACE}/pebble.minica.pem"
    fi

    # Cleanup files created by the setup
    if [[ -n "${GITHUB_WORKSPACE// }" ]]; then
      [[ -f "${GITHUB_WORKSPACE}/nginx.tmpl" ]] && rm "${GITHUB_WORKSPACE}/nginx.tmpl"
      rm "${GITHUB_WORKSPACE}/test/local_test_env.sh"
      echo "The ${GITHUB_WORKSPACE}/go folder require superuser permission to fully remove."
      echo "Doing sudo rm -rf in scripts is dangerous, so the folder won't be automatically removed."
    fi

    # Remove custom entries to /etc/hosts
    echo "Removing custom entries from /etc/hosts (requires sudo)."
    declare -a hosts=("${domains[@]}")
    if [[ "$ACME_CA" == 'pebble' ]]; then
      hosts+=(pebble pebble-challtestsrv)
    fi
    for host in "${hosts[@]}"; do
      if [[ "$(uname)" == 'Darwin' ]]; then
        sudo sed -i '' "/127\.0\.0\.1 $host # le-companion test suite/d" /etc/hosts
      else
        sudo sed --in-place "/127\.0\.0\.1 $host # le-companion test suite/d" /etc/hosts
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
