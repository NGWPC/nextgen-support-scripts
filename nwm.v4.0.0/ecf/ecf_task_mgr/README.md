# ecf_task_mgr

Manages ecflow tasks and subtasks. ecflow tracks status at the Task level only — this package adds a Subtask abstraction using ecflow labels.

## Setup

### 1. Build and start the ecflow server (Docker)

```bash
# With cwd as "nwm-automation-scripts/nwm.v4.0.0/ecflow-server"
bash ecflow-server-docker-build.sh no
bash ecflow-server-test-from-local-client.sh
```

### 2. Build and install the ecflow Python client

```bash
# With cwd as (repo root) "nwm-automation-scripts"
bash nwm.v4.0.0/ecf/ecf_task_mgr/setup/install_ecflow_python_client.sh
```

### 3. Install Python package ecf_task_mgr

```bash
# With cwd as (repo root) "nwm-automation-scripts"
pip install -e nwm.v4.0.0/ecf/ecf_task_mgr
```
