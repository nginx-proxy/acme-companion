#!/bin/bash

sudo rm /usr/local/bin/docker-compose
curl -L https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m) > docker-compose.temp
chmod +x docker-compose.temp
sudo mv docker-compose.temp /usr/local/bin/docker-compose
docker-compose --version
