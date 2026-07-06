#!/bin/bash
set -e

globalTests+=(
	docker_api
	docker_api_legacy
	docker_api_tls
	location_config
	debug_acmesh_log
	certs_single
	certs_san
	certs_single_domain
	certs_standalone
	standalone_ipv6
	force_renew
	acme_accounts
	private_keys
	renew_private_keys
	container_restart
	permissions_default
	permissions_custom
	symlinks
	acme_hooks
	certs_renew_after
	certs_default_renew_deprecated
	ocsp_must_staple
	certs_persistence
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
