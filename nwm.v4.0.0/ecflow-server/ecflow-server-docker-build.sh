#!/bin/bash
# 
# Build a docker image of an ecflow server and run its built-in unit tests via `ctest`.
# 

set -euo pipefail

# BOOST_VERS_DOT=1.89.0
# BOOST_VERS_UNDER=1_89_0

BOOST_VERS_DOT=1.91.0
BOOST_VERS_UNDER=1_91_0

echo "Building ecflow server image..."
docker build \
    --build-arg BOOST_VERS_DOT=${BOOST_VERS_DOT} \
    --build-arg BOOST_VERS_UNDER=${BOOST_VERS_UNDER} \
    -t ecflow-server \
    -f Dockerfile.ecflow-server .
echo "Done building ecflow server image."

echo "Running ecflow server's unit tests..."
docker run -t ecflow-server ctest --test-dir /src/ecflow/build -E '^u_server_authentication$'
echo "Done with ecflow server tests."
