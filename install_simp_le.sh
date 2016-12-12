#!/bin/bash

set -e

# Install python packages needed to build simp_le
apk --update add python py-requests py-setuptools git gcc py-pip musl-dev libffi-dev python-dev openssl-dev

# Get Let's Encrypt simp_le client source
mkdir -p /src
git -C /src clone https://github.com/zenhack/simp_le.git

# Install simp_le in /usr/bin
cd /src/simp_le
python ./setup.py install

# Make house cleaning
cd /
rm -rf /src
apk del git gcc py-pip musl-dev libffi-dev python-dev openssl-dev
rm -rf /var/cache/apk/*
