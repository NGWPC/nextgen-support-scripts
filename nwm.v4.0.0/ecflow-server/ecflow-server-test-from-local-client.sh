#!/bin/bash
# 
# Start a ecflow server container and test client connections to it.
# 

set -euo pipefail

NETWORK="ecflow-net"

# idempotent network creation
echo "Creating network..."
docker network inspect "${NETWORK}" >/dev/null 2>&1 || docker network create "${NETWORK}"

echo "Stopping container if it already exists..."
docker stop ecflow-server 2>/dev/null || true

# Start server container
echo "Starting server container..."
docker run --rm -d --net "${NETWORK}" --name ecflow-server -p 3141:3141 -v "$(pwd)/data/ecflow:/data/ecflow" ecflow-server /usr/local/ecflow/bin/ecflow_server
echo "Container started."

echo "Pinging server container from another container..."
docker run --rm --net "${NETWORK}" --name ecflow-client ecflow-server ecflow_client --host=ecflow-server --ping
echo "Successful ping to server from another container."

echo "Ping from local client..."
ecflow_client --host=localhost --port 3141 --ping
echo "Succeeded ping from local client."

echo "Stopping server container..."
docker stop ecflow-server 2>/dev/null || true
echo "Stopped server container."

set -x
exit 0
