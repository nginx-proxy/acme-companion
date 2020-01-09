#!/bin/bash
set -e

testAlias+=(
	[jrcs/letsencrypt-nginx-proxy-companion]='le-companion'
)

imageTests+=(
	[le-companion]='
	docker_api
	location_config
	default_cert
	certs_single
	certs_san
	certs_standalone
	certs_standalone_from_env
	force_renew
	certs_validity
	container_restart
	permissions_default
	permissions_custom
	symlinks
	'
)
