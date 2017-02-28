#!/bin/bash

set -e

# Install python packages needed to build simp_le
apk --update add python py-requests py-setuptools git gcc py-pip musl-dev libffi-dev python-dev openssl-dev

# Get Let's Encrypt simp_le client source
branch="acme-0.8"
mkdir -p /src
git -C /src clone --depth=1 -b $branch https://github.com/kuba/simp_le.git

# Install simp_le in /usr/bin
cd /src/simp_le
git checkout acme-0.8
python ./setup.py install

# Make house cleaning
cd /
rm -rf /src
apk del git gcc py-pip musl-dev libffi-dev python-dev openssl-dev
rm -rf /var/cache/apk/*
