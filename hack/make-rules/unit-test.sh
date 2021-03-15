#!/usr/bin/env bash

# shellcheck disable=SC2034 # Variables sourced in other scripts.

set -e
shopt -s globstar

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

UNIT_TEST_DIR=$PROJECT_ROOT/test/unit

source_all_files_recursively_from() {
    local directory=$1
    for file in "$directory"/**/*.sh; do
        # shellcheck disable=SC1090 # Sourced files
        source "$file"
    done
}

# shellcheck disable=SC1090 # Sourced files
source "$PROJECT_ROOT/hack/shunit2.sh"

suite() {
    source_all_files_recursively_from "$UNIT_TEST_DIR"
}

# shellcheck disable=SC1090 # Sourced files
. "$SHUNIT2_BIN"
