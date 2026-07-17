#!/bin/bash

# shellcheck source=app/letsencrypt_service.sh
source /app/letsencrypt_service.sh --source-only

update_certs --force-renew
