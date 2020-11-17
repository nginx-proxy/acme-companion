#!/bin/bash

set -e

# Install git (required to fetch acme.sh)
apk --no-cache --virtual .acmesh-deps add git

# Get acme.sh ACME client source
mkdir /src
git -C /src clone https://github.com/Neilpang/acme.sh.git
cd /src/acme.sh
if [[ "$ACMESH_VERSION" != "master" ]]; then
  git -c advice.detachedHead=false checkout "$ACMESH_VERSION"
fi

# Install acme.sh in /app
./acme.sh --install \
  --nocron \
  --auto-upgrade 0 \
  --home /app \
  --config-home /etc/acme.sh/default

# Make house cleaning
cd /
rm -rf /src
apk del .acmesh-deps
