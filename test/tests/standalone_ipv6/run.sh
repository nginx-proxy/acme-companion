#!/bin/bash

## Test that standalone challenge configs listen over IPv6 only when ENABLE_IPV6 is set. See #710.

commands="$(cat <<'EOF'
source /app/functions.sh
mkdir -p /etc/nginx/conf.d
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

docker run --rm "$1" bash -c "${commands}" 2>&1
