#!/bin/bash

## Test for Docker API TLS client-certificate support (DOCKER_TLS_VERIFY / DOCKER_CERT_PATH).
##
## Two complementary checks:
##   1. (default, runs in CI) Deterministic verification that docker_api builds the
##      expected curl invocation for each transport, by stubbing curl. This needs no
##      external TLS daemon and is therefore stable on CI runners.
##   2. (optional, RUN_TLS_INTEGRATION=1) A real TLS handshake against the Docker
##      socket exposed over tcp:// by a socat sidecar, to confirm end-to-end behaviour.
##
## This test is transport-focused and produces identical output regardless of the
## SETUP (2containers / 3containers); it is registered to run once via the CI matrix.

# ---------------------------------------------------------------------------
# 1. curl-stub verification of the curl invocation built by docker_api
# ---------------------------------------------------------------------------

# Replace curl with a stub that prints the arguments it would have received, then
# exercise docker_api over each transport in an isolated subshell (to avoid the
# bash quirk where `VAR=x function_call` leaks VAR into the calling shell).
read -r -d '' commands <<'EOF'
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

docker run --rm "$1" bash -c "$commands" 2>&1

# ---------------------------------------------------------------------------
# 2. Optional real TLS handshake against a socat sidecar (local only)
# ---------------------------------------------------------------------------

if [[ "${RUN_TLS_INTEGRATION:-}" != "1" ]]; then
  exit 0
fi

net='docker-api-tls-net'
proxy='docker-api-tls-proxy'
certs_dir="$(mktemp -d)"
server_dir="${certs_dir}/server"
client_dir="${certs_dir}/client"
mkdir -p "$server_dir" "$client_dir"

function cleanup_integration {
  docker rm --force "$proxy" &> /dev/null
  docker network rm "$net" &> /dev/null
  rm -rf "$certs_dir"
}
trap cleanup_integration EXIT

# Generate a CA, a server certificate (SAN matching the sidecar's network alias)
# and a client certificate, all signed by the CA.
openssl genrsa -out "${certs_dir}/ca-key.pem" 2048 &> /dev/null
openssl req -x509 -new -key "${certs_dir}/ca-key.pem" -days 1 -subj '/CN=test-ca' \
  -out "${certs_dir}/ca.pem" &> /dev/null

openssl genrsa -out "${server_dir}/key.pem" 2048 &> /dev/null
openssl req -new -key "${server_dir}/key.pem" -subj "/CN=${proxy}" \
  -out "${server_dir}/csr.pem" &> /dev/null
openssl x509 -req -in "${server_dir}/csr.pem" \
  -CA "${certs_dir}/ca.pem" -CAkey "${certs_dir}/ca-key.pem" -CAcreateserial \
  -days 1 -extfile <(printf 'subjectAltName=DNS:%s' "$proxy") \
  -out "${server_dir}/cert.pem" &> /dev/null
cp "${certs_dir}/ca.pem" "${server_dir}/ca.pem"

openssl genrsa -out "${client_dir}/key.pem" 2048 &> /dev/null
openssl req -new -key "${client_dir}/key.pem" -subj '/CN=test-client' \
  -out "${client_dir}/csr.pem" &> /dev/null
openssl x509 -req -in "${client_dir}/csr.pem" \
  -CA "${certs_dir}/ca.pem" -CAkey "${certs_dir}/ca-key.pem" -CAcreateserial \
  -days 1 -out "${client_dir}/cert.pem" &> /dev/null
cp "${certs_dir}/ca.pem" "${client_dir}/ca.pem"

docker network create "$net" &> /dev/null

# Expose the Docker socket over tcp://:2376 with mandatory client-cert verification.
docker run --rm -d \
  --name "$proxy" \
  --network "$net" \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -v "${server_dir}:/certs:ro" \
  alpine/socat \
  "OPENSSL-LISTEN:2376,reuseaddr,fork,cert=/certs/cert.pem,key=/certs/key.pem,cafile=/certs/ca.pem,verify=1" \
  "UNIX-CONNECT:/var/run/docker.sock" > /dev/null

# Query the Docker API over TLS through docker_api and print the API version.
integration_commands='source /app/functions.sh; docker_api "/version" | jq -r ".ApiVersion // \"no-response\""'
docker run --rm \
  --network "$net" \
  -e "DOCKER_HOST=tcp://${proxy}:2376" \
  -e "DOCKER_TLS_VERIFY=true" \
  -e "DOCKER_CERT_PATH=/docker-certs" \
  -v "${client_dir}:/docker-certs:ro" \
  "$1" \
  bash -c "$integration_commands" 2>&1
