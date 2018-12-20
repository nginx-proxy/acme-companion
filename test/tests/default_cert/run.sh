#!/bin/bash

## Test for default certificate creation.

if [[ -z $TRAVIS_CI ]]; then
  le_container_name="$(basename ${0%/*})_$(date "+%Y-%m-%d_%H.%M.%S")"
else
  le_container_name="$(basename ${0%/*})"
fi
run_le_container ${1:?} "$le_container_name"

# Create the $domains array from comma separated domains in TEST_DOMAINS.
IFS=',' read -r -a domains <<< "$TEST_DOMAINS"

# Cleanup function with EXIT trap
function cleanup {
  # Cleanup the files created by this run of the test to avoid foiling following test(s).
  docker exec "$le_container_name" bash -c 'rm -f /etc/nginx/certs/default.*'
  docker stop "$le_container_name" > /dev/null
}
trap cleanup EXIT

function default_cert_fingerprint {
  docker exec "$le_container_name" openssl x509 -in "/etc/nginx/certs/default.crt" -fingerprint -noout
}

function default_cert_subject {
  docker exec "$le_container_name" openssl x509 -in "/etc/nginx/certs/default.crt" -subject -noout
}

user_cn="user-provided"

i=0
until docker exec "$le_container_name" [[ -f /etc/nginx/certs/default.crt ]]; do
  if [ $i -gt 60 ]; then
    echo "Default cert wasn't created under one minute at container first launch."
    break
  fi
  i=$((i + 2))
  sleep 2
done

# Connection test to unconfigured domains
for domain in "${domains[@]}"; do
  wait_for_conn --domain "$domain" --default-cert
done

# Test if the default certificate get re-created when
# the certificate or private key file are deleted
for file in 'default.key' 'default.crt'; do
  old_default_cert_fingerprint="$(default_cert_fingerprint)"
  docker exec "$le_container_name" rm -f /etc/nginx/certs/$file
  docker restart "$le_container_name" > /dev/null && sleep 5
  i=0
  while [[ "$(default_cert_fingerprint)" == "$old_default_cert_fingerprint" ]]; do
    if [ $i -gt 55 ]; then
      echo "Default cert wasn't re-created under one minute after $file deletion."
      break
    fi
    i=$((i + 2))
    sleep 2
  done
done

# Test if the default certificate get re-created when
# the certificate expire in less than three months
docker exec "$le_container_name" bash -c 'rm -rf /etc/nginx/certs/default.*'
docker exec "$le_container_name" openssl req -x509 \
  -newkey rsa:4096 -sha256 -nodes -days 60 \
  -subj "/CN=letsencrypt-nginx-proxy-companion" \
  -keyout /etc/nginx/certs/default.key \
  -out /etc/nginx/certs/default.crt > /dev/null 2>&1
old_default_cert_fingerprint="$(default_cert_fingerprint)"
docker restart "$le_container_name" > /dev/null && sleep 5
i=0
while [[ "$(default_cert_fingerprint)" == "$old_default_cert_fingerprint" ]]; do
  if [ $i -gt 55 ]; then
    echo "Default cert wasn't re-created under one minute when the certificate expire in less than three months."
    break
  fi
  i=$((i + 2))
  sleep 2
done

# Test that a user provided default certificate isn't overwrited
docker exec "$le_container_name" bash -c 'rm -rf /etc/nginx/certs/default.*'
docker exec "$le_container_name" openssl req -x509 \
  -newkey rsa:4096 -sha256 -nodes -days 60 \
  -subj "/CN=$user_cn" \
  -keyout /etc/nginx/certs/default.key \
  -out /etc/nginx/certs/default.crt > /dev/null 2>&1
docker restart "$le_container_name" > /dev/null

# Connection test to unconfigured domains
for domain in "${domains[@]}"; do
  wait_for_conn --domain "$domain" --subject-match "$user_cn"
done
