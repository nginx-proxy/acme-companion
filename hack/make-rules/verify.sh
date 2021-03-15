#!/usr/bin/env bash

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

# shellcheck disable=SC1090 # Sourced files
source "$PROJECT_ROOT/hack/shunit2.sh"

shunit2::validate
