# NextGen support scripts

This repository contains development and operational scripts for the NextGen water prediction ecosystem. This repository brings together tools for setting up Parallel Works clusters, building NextGen components, managing releases, and running NWM workflows on the operational testbed. Each area has its own requirements and instructions.

## Repository contents

| Directory | What it contains | Start here |
| --- | --- | --- |
| [`parallel_works_scripts/`](parallel_works_scripts/) | Cluster setup, configuration, cleanup, and container builds for NextGen components. | [Build script reference](parallel_works_scripts/build_cluster_REFERENCE.md) |
| [`nwm.v4.0.0/`](nwm.v4.0.0/) | ecFlow definitions and scripts for scheduled NWM v4.0.0 testbed workflows, plus performance tests. | [NWM testbed installation](nwm.v4.0.0/INSTALL.md) |
| [`create_release/`](create_release/) | Scripts and configuration examples for release candidates, official releases, and related GitHub repository tasks. | [Release script guide](create_release/README_createrelease.md) |
| [`model_formulations/`](model_formulations/) | Formulation data and utilities for NextGen model testing. | [Model formulations README](model_formulations/README.md) |

## Getting started

Clone the `development` branch, then open the guide for the area you need:

```bash
git clone --branch development https://github.com/NGWPC/nextgen-support-scripts.git
cd nextgen-support-scripts
```

These scripts target specific environments. Review the relevant guide and script options before running setup, build, or release commands.
