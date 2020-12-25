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
	ocsp_must_staple
	container_restart
	permissions_default
	permissions_custom
	networks_segregation
	symlinks
)
