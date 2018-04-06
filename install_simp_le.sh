#!/bin/bash

set -e

# Install python packages needed to build simp_le
apk --update add python py-setuptools git gcc py-pip musl-dev libffi-dev python-dev openssl-dev

# Get Let's Encrypt simp_le client source
branch="0.7.0"
mkdir -p /src
git -C /src clone --depth=1 --branch $branch https://github.com/zenhack/simp_le.git

# Install simp_le in /usr/bin
cd /src/simp_le
#pip install wheel requests
for pkg in pip distribute setuptools wheel
do
  pip install -U "${pkg?}"
done
pip install .

# Make house cleaning
cd /
rm -rf /src
apk del git gcc py-pip musl-dev libffi-dev python-dev openssl-dev
rm -rf /var/cache/apk/*
