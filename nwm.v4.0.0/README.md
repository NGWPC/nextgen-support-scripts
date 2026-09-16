# NWM Operational Testbed 

This directory contains scripts and ecFlow definitions for running NextGen workflows on the operational testbed with a WCOSS2-like filesystem structure. Once the workflows are set up, the ecFlow suite runs in real time on a schedule. Currently, the suite covers data assimilation preprocessing, analysis and assimilation, short range forecasts, extended analysis and assimilation, and cleanup.

The [performance_test](performance_test) directory contains scripts to run multiple VPU performance tests.

## Prerequisites

It assumes a Parallel Works Rocky 8 cluster has been provisioned. A user bootstrap script is created to install necessary software packages during the cluster booting process. The bootstrap is [bootstrap.bash](bootstrap.bash). When configuring the cluster, copy and paste the content of this file to the "User bootstrap" section.

The minimum hardware requirement is the c5.9xlarge node type for both the controller node and compute nodes.

By default, it uses the `/lfs/h1/ops/prod` directory for permanent storage and the `${HOME}/test/tmp` directory as the temporary working directory for ecFlow tasks. To customize these paths, set the `$OPSROOT` and `$DATAROOT` environment variables before running the installer.

## Getting started

This setup is intended for the operational testbed and requires Docker, ecFlow, and the [NWM runtime environment](https://github.com/NGWPC/nwm-rte). From the `development` branch of this repository:

The data assimilation pre-processing workflows need FTP login credentials for the RFC reservoir forecasts and an API Key for downloading observed streamflow from the USGS Water Data server. The FTP credentials and API Key should be saved in a text file named `.env` in the same directory as the installation script, `nwm.v4.0.0/install_testbed.sh`, before the starting the installation procedures.

First build the EcFlow server docker image,

```bash
cd nwm.v4.0.0/ecflow-server
./ecflow-server-docker-build.sh no
```
Then install the testbed package,
```bash
cd ..
./install_testbed.sh
```

The installer builds the runtime environment if needed, starts the ecFlow server container, and loads the NWM suite. **On an existing testbed, this clears ecFlow checkpoint data and replaces the loaded `/nwm` suite.** Use `-p <port>` to select an ecFlow port or `-b <branch>` to select an NWM runtime environment branch. See [INSTALL.md](INSTALL.md) for testbed setup and ecFlow UI instructions.

## Contents

- `ecf/`: ecFlow suite and task definitions.
- `jobs/`, `scripts/`, and `ush/`: job wrappers, shell scripts, and Python workflow code.
- `ecflow-server/`: Docker build and startup scripts for the ecFlow server ([details](ecflow-server/README.md)).
- `performance_test/`: testbed performance scripts ([details](performance_test/README.md)).
