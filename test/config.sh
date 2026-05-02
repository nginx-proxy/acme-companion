#!/bin/bash
set -e

globalTests+=(
	docker_api
	docker_api_legacy
	location_config
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
	certs_default_renew
	ocsp_must_staple
)

# The acme_eab test requires Pebble with a specific configuration
if [[ "$ACME_CA" == 'pebble' && "$PEBBLE_CONFIG" == 'pebble-config-eab.json' ]]; then
	globalTests+=(
		acme_eab
	)
fi

# The cert_profiles test requires Pebble multiple profiles support from the default Pebble config
if [[ "$ACME_CA" == 'pebble' && "$PEBBLE_CONFIG" == 'pebble-config.json' ]]; then
	globalTests+=(
		cert_profiles
	)
fi
