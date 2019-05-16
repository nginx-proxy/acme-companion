#!/bin/bash

set -e

# Install python and packages needed to build simp_le
apk add --update python3 git gcc musl-dev libffi-dev python3-dev openssl-dev

# Create expected symlinks if they don't exist
[[ -e /usr/bin/pip ]] || ln -sf /usr/bin/pip3 /usr/bin/pip
[[ -e /usr/bin/python ]] || ln -sf /usr/bin/python3 /usr/bin/python

# Get Let's Encrypt simp_le client source
branch="0.14.0"
mkdir -p /src
git -C /src clone --depth=1 --branch $branch https://github.com/zenhack/simp_le.git

# Install simp_le in /usr/bin
cd /src/simp_le
#pip install wheel requests
for pkg in pip setuptools wheel
do
  pip3 install -U "${pkg?}"
done
pip3 install .

# Make house cleaning
cd /
rm -rf /src
apk del git gcc musl-dev libffi-dev python3-dev openssl-dev
rm -rf /var/cache/apk/*
