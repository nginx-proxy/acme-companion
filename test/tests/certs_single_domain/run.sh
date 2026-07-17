#!/bin/bash

## Test for splitting SAN certificates into single domain certificates by NGINX container env variables
## Tests both ACME_SINGLE_DOMAIN_CERTS (current) and LETSENCRYPT_SINGLE_DOMAIN_CERTS (legacy) env vars.

if [[ -z ${GITHUB_ACTIONS} ]]; then
  le_container_name="$(basename "${0%/*}")_$(date "+%Y-%m-%d_%H.%M.%S")"
else
  le_container_name="$(basename "${0%/*}")"
fi
run_le_container "${1:?}" "${le_container_name}"

# Create the ${domains} array from comma separated domains in TEST_DOMAINS.
IFS=',' read -r -a domains <<< "${TEST_DOMAINS}"

# Cleanup function with EXIT trap
function cleanup {
  # Remove any remaining Nginx container(s) silently.
  i=1
  for hosts in "${letsencrypt_hosts[@]}"; do
    docker rm --force "test${i}" &> /dev/null
    i=$(( i + 1 ))
  done
  # Cleanup the files created by this run of the test to avoid foiling following test(s).
  docker exec "${le_container_name}" cleanup_test_artifacts
  # Stop the LE container
  docker stop "${le_container_name}" > /dev/null
}
trap cleanup EXIT

# Create three different comma separated list from the first three domains in ${domains}.
# testing for regression on spaced lists https://github.com/nginx-proxy/acme-companion/issues/288
# and with trailing comma https://github.com/nginx-proxy/acme-companion/issues/254
letsencrypt_hosts=( \
  [0]="${domains[0]},${domains[1]},${domains[2]}" \     #straight comma separated list
  [1]="${domains[1]}, ${domains[2]}, ${domains[0]}" \   #comma separated list with spaces
  [2]="${domains[2]}, ${domains[0]}, ${domains[1]}," )  #comma separated list with spaces and a trailing comma

# Alternate between the current and legacy single domain certs env var to test both.
single_domain_env_vars=( \
  [0]="ACME_SINGLE_DOMAIN_CERTS" \
  [1]="LETSENCRYPT_SINGLE_DOMAIN_CERTS" \
  [2]="ACME_SINGLE_DOMAIN_CERTS" )

i=1

for hosts in "${letsencrypt_hosts[@]}"; do

  container="test${i}"
  single_domain_env_var="${single_domain_env_vars[$((i - 1))]}"

  # Run an Nginx container passing one of the comma separated lists as ACME_HOST env var,
  # alternating between ACME_SINGLE_DOMAIN_CERTS and LETSENCRYPT_SINGLE_DOMAIN_CERTS.
  run_nginx_container --hosts "${hosts}" --name "${container}" --cli-args "--env ${single_domain_env_var}=true"

  for domain in "${domains[@]}"; do
      ## For all the domains in the ${domains} array ...
      # Wait for a symlink at /etc/nginx/certs/${domain}.crt
      if wait_for_symlink "${domain}" "${le_container_name}" "./${domain}/fullchain.pem"; then
        # then grab the certificate in text form from the file ...
        created_cert="$(docker exec "${le_container_name}" \
          openssl x509 -in "/etc/nginx/certs/${domain}/cert.pem" -text -noout)"
        # ... as well as the certificate fingerprint.
        created_cert_fingerprint="$(docker exec "${le_container_name}" \
          openssl x509 -in "/etc/nginx/certs/${domain}/cert.pem" -fingerprint -noout)"
    fi

    # Check if the domain is on the certificate.
    if grep -q "${domain}" <<< "${created_cert}"; then
      if [[ "${DRY_RUN:-}" == 1 ]]; then
        echo "${domain} is on certificate."
      fi
      for otherdomain in "${domains[@]}"; do
        if [[ "${domain}" != "${otherdomain}" ]]; then
          if grep -q "${otherdomain}" <<< "${created_cert}"; then
            echo "${otherdomain} is on certificate for ${domain}, but it must not!"
          elif [[ "${DRY_RUN:-}" == 1 ]]; then
            echo "${otherdomain} did not appear on certificate for ${domain}."
          fi
        fi
      done
    else
      echo "${domain} did not appear on certificate."
    fi

    # Wait for a connection to https://domain and for the served
    # certificate to match the created certificate.
    # If it does not, display a full diff.
    if ! wait_for_conn --domain "${domain}" --cert-match "${created_cert_fingerprint}"; then
      echo "Nginx served an incorrect certificate for ${domain}."
      served_cert="$(echo \
        | openssl s_client -showcerts -servername "${domain}" -connect "${domain}:443" 2>/dev/null \
        | openssl x509 -text -noout \
        | sed 's/ = /=/g' )"
      diff -u <(echo "${created_cert// = /=}") <(echo "${served_cert}")
    elif [[ "${DRY_RUN:-}" == 1 ]]; then
       echo "The correct certificate for ${domain} was served by Nginx."
    fi
  done

  docker stop "${container}" &> /dev/null
  i=$(( i + 1 ))

done
