#!/bin/bash
#
# Start an ecflow server container.
#
# Optional mode:
#   test-only  Start server, run client tests, then stop server and exit.
#
# Default:
#   Start server and exit, leaving the server running.
#

set -euo pipefail

NETWORK="ecflow-net"
MODE="${1:-start}"

if [[ "${MODE}" != "start" && "${MODE}" != "test-only" ]]; then
	echo "Usage: $0 [test-only]"
	exit 2
fi

# idempotent network creation
echo "Creating network..."
sudo docker network inspect "${NETWORK}" >/dev/null 2>&1 || sudo docker network create "${NETWORK}"

echo "Stopping container if it already exists..."
sudo docker stop ecflow-server 2>/dev/null || true

# Start server container
echo "Starting server container..."
sudo docker run --rm -d --net "${NETWORK}" --name ecflow-server -p 3141:3141 -v "$(pwd)/data/ecflow:/data/ecflow" ecflow-server /usr/local/ecflow/bin/ecflow_server
echo "Container started."

if [[ "${MODE}" == "test-only" ]]; then
	echo "Pinging server container from another container..."
	sudo docker run --rm --net "${NETWORK}" --name ecflow-client ecflow-server ecflow_client --host=ecflow-server --ping
	echo "Successful ping to server from another container."

	echo "Ping from local client..."
	ecflow_client --host=localhost --port 3141 --ping
	echo "Succeeded ping from local client."

	echo "Stopping server container..."
	sudo docker stop ecflow-server 2>/dev/null || true
	echo "Stopped server container."
else
	echo "Server is running (default mode)."
fi

set -x
exit 0
