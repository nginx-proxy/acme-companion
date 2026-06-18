#!/bin/bash

## Test for IPv6 support in standalone challenge configs (ENABLE_IPV6). See issue #710.
##
## Deterministic check that add_standalone_configuration emits 'listen [::]:80;' only
## when ENABLE_IPV6 is enabled. It sources functions.sh and inspects the generated
## config, so it needs no external ACME daemon and is stable on CI runners.

commands="$(cat <<'EOF'
source /app/functions.sh
mkdir -p /etc/nginx/conf.d
# A pre-existing unrelated vhost so the server_name lookup glob expands cleanly
# (add_standalone_configuration greps /etc/nginx/conf.d/*.conf).
printf 'server { server_name other.example.test; }\n' > /etc/nginx/conf.d/other.conf

echo '## ipv6-enabled'
( export ENABLE_IPV6=true; add_standalone_configuration 'ipv6.example.test' )
cat /etc/nginx/conf.d/standalone-cert-ipv6.example.test.conf
echo '## ipv6-disabled'
( export ENABLE_IPV6=false; add_standalone_configuration 'plain.example.test' )
cat /etc/nginx/conf.d/standalone-cert-plain.example.test.conf
echo '## ipv6-unset'
( unset ENABLE_IPV6; add_standalone_configuration 'unset.example.test' )
cat /etc/nginx/conf.d/standalone-cert-unset.example.test.conf
EOF
)"

docker run --rm "$1" bash -c "$commands" 2>&1
