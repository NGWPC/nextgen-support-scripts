# Docker Build for ecFlow Server

This is a Docker build for an ecFlow server.

Currently this is hard-coded for ecFlow version 5.15.2.  See: https://ecflow.readthedocs.io/en/5.15.2/

Currently this includes build args to specify:

1. Specific base image (currently must have `dnf` package manager, e.g. Rocky 8).
2. The version of boost.

See notes in `ecflow-server-docker-build.sh` and in `Dockerfile.ecflow-server` for details.

## Steps

```bash
cd nwm.v4.0.0/ecflow-server

# Build the server image and run its `ctest` unit tests.
# Note that the tests take significant time. Edit the bottom of the Dockerfile to omit running those.
./ecflow-server-docker-build.sh

# (Optional) install ecFlow client on the host, and test the connection.
# Assumes host uses `apt` and has ecflow-client package available (e.g. Ubuntu).
sudo apt update && sudo apt install -y ecflow-client
./ecflow-server-test-from-local-client.sh
```
