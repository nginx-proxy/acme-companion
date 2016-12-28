#!/bin/bash

set -e

# Install python packages needed to build simp_le
apk --update add python py-requests py-setuptools git gcc py-pip musl-dev libffi-dev python-dev openssl-dev

# Get Let's Encrypt simp_le client source
mkdir -p /src
# with -b argument, we clone only the branch we need to use.
git -C /src clone https://github.com/kuba/simp_le.git -b acme-0.8

# Install simp_le in /usr/bin
cd /src/simp_le
# the command below isn't needed if we clone only the good branch
#git checkout acme-0.8
python ./setup.py install

# Make house cleaning
cd /
rm -rf /src
apk del git gcc py-pip musl-dev libffi-dev python-dev openssl-dev
rm -rf /var/cache/apk/*
