#!/bin/bash
set -e

testAlias+=(
	[jrcs/letsencrypt-nginx-proxy-companion]='le-companion'
)

imageTests+=(
	[le-companion]='
	docker_api
	default_cert
	certs_single
	certs_san
	force_renew
	container_restart
	permissions_default
	permissions_custom
	symlinks
	'
)
