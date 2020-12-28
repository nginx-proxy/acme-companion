#!/bin/bash
set -e

globalTests+=(
	docker_api
	location_config
	default_cert
	certs_single
	certs_san
	certs_single_domain
	certs_standalone
	force_renew
	acme_accounts
	private_keys
	container_restart
	permissions_default
	permissions_custom
	symlinks
)

# The ocsp_must_staple test does not work with Pebble
if [[ "$ACME_CA" == 'boulder' ]]; then
	globalTests+=(
		ocsp_must_staple
	)
fi