#!/bin/bash

set -e

function get_base_domain {
  awk -F ',' '{print $1}' <(echo ${1:?})
}

function run_le_container {
  docker run -d \
    --name ${1:?} \
    --volumes-from ${2:?} \
    -v /var/run/docker.sock:/var/run/docker.sock:ro \
    --add-host boulder:${3:?} \
    -e "DEBUG=true" \
    -e "ACME_CA_URI=http://${3:?}:4000/directory" \
    -e "ACME_TOS_HASH=b16e15764b8bc06c5c3f9f19bc8b99fa48e7894aa5a6ccdad65da49bbf564793" \
    $IMAGE
}

wait_for_dhparam() {
  local i=0
  sleep 1
  echo -n "Waiting for the ${1:?} container to generate a DH parameters file."
  until docker exec ${1:?} [ -f /etc/nginx/certs/dhparam.pem ]; do
    if [ $i -gt 600 ]; then
      echo "DH parameters file was not generated under ten minutes by the ${1:?} container, timing out."
      exit 1
    fi
    i=$((i + 5))
    sleep 5
    echo -n "."
  done
  echo " Done."
}

wait_for_cert() {
  local i=0
  echo "Waiting for the ${2:?} container to generate the certificate for ${1:?}."
  until docker exec ${2:?} [ -f /etc/nginx/certs/${1:?}/cert.pem ]; do
    if [ $i -gt 60 ]; then
      echo "Certificate for ${1:?} was not generated under one minute, timing out."
      exit 1
    fi
    i=$((i + 2))
    sleep 2
  done
  echo "Certificate for ${1:?} has been generated."
}

wait_for_conn() {
  local i=0
  echo "Waiting for a successful connection to http://${1:?}"
  until curl -k https://${1:?} > /dev/null 2>&1; do
    if [ $i -gt 60 ]; then
      echo "Could not connect to ${1:?} using https under one minute, timing out."
      exit 1
    fi
    i=$((i + 2))
    sleep 2
  done
  echo "Connection to ${1:?} using https was successfull."
}
