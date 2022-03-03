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
	acme_hooks
)

# The acme_eab test requires Pebble with a specific configuration
if [[ "$ACME_CA" == 'pebble' && "$PEBBLE_CONFIG" == 'pebble-config-eab.json' ]]; then
	globalTests+=(
		acme_eab
	)
fi

# The ocsp_must_staple test does not work with Pebble
if [[ "$ACME_CA" == 'boulder' ]]; then
	globalTests+=(
		ocsp_must_staple
	)
fi