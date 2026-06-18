#!/bin/bash

## Test for Docker API TLS client-certificate support (DOCKER_TLS_VERIFY / DOCKER_CERT_PATH).
##
## Deterministic verification that docker_api builds the expected curl invocation for
## each transport, by stubbing curl. This needs no external TLS daemon and is therefore
## stable on CI runners.
##
## This test is transport-focused and produces identical output regardless of the
## SETUP (2containers / 3containers); it is registered to run once via the CI matrix.

# Replace curl with a stub that prints the arguments it would have received, then
# exercise docker_api over each transport in an isolated subshell (to avoid the
# bash quirk where `VAR=x function_call` leaks VAR into the calling shell).
commands="$(cat <<'EOF'
curl() { printf '%s\n' "$*"; }
source /app/functions.sh
echo '## tls-verify-true-get'
( export DOCKER_HOST='tcp://docker:2376' DOCKER_TLS_VERIFY='true' DOCKER_CERT_PATH='/docker-certs'; docker_api '/version' )
echo '## tls-verify-true-post'
( export DOCKER_HOST='tcp://docker:2376' DOCKER_TLS_VERIFY='true' DOCKER_CERT_PATH='/docker-certs'; docker_api '/containers/test/restart' 'POST' )
echo '## tls-verify-false-get'
( export DOCKER_HOST='tcp://docker:2376' DOCKER_TLS_VERIFY='false' DOCKER_CERT_PATH='/docker-certs'; docker_api '/version' )
echo '## unix-socket-get'
( export DOCKER_HOST='unix:///var/run/docker.sock'; docker_api '/version' )
EOF
)"

docker run --rm "$1" bash -c "$commands" 2>&1
