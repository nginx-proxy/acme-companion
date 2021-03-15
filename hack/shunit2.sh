#!/usr/bin/env bash

# shellcheck disable=SC2034 # Variables sourced in other scripts.

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# shellcheck disable=SC1090 # Sourced files
source "$PROJECT_ROOT/hack/init.sh"

SHUNIT2_VERSION=v2.1.8
SHUNIT2_REPO_URL=https://github.com/kward/shunit2
SHUNIT2_DIR=$THIRD_PARTY/shunit2
SHUNIT2_BIN=$SHUNIT2_DIR/shunit2

shunit2::validate() {
    # Validate shUnit2 is installed
    if [[ ! -d $SHUNIT2_DIR ]]; then
        echo "shUnit2 is not installed."
        return 1
    fi

    # Validate installed version
    local expected_release=$SHUNIT2_VERSION
    local current_release

    current_release=$(cd "$SHUNIT2_DIR" && git describe --tags)
    if [[ "$current_release" != "$expected_release" ]]; then
        echo "shUnit2 version $expected_release required, the current version" \
            "installed is $current_release."
        return 1
    fi
}

shunit2::install() {
    if shunit2::validate; then
        echo "shUnit2 ${SHUNIT2_VERSION} already installed."
        return 1
    else
        shunit2::cleanup

        git clone --branch "$SHUNIT2_VERSION" "$SHUNIT2_REPO_URL" "$SHUNIT2_DIR"
        chmod +x "$SHUNIT2_BIN"
    fi
}

shunit2::cleanup() {
    if [[ -d "$SHUNIT2_DIR" ]]; then
        rm -rf "$SHUNIT2_DIR"
    fi
}
