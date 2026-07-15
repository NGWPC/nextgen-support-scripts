#!/usr/bin/env bash

set -xa
set -euo pipefail

if [ $# -eq 0 ]; then
  echo "Use default port."
  export ECF_PORT=3141
else
  echo "Use port $1"
  export ECF_PORT=$1
fi 

export NWM_PACKAGE_DIR="$(pwd)"
export DATAROOT="${DATAROOT:-${NWM_PACKAGE_DIR}/data/tmp}"

echo "NWM_PACKAGE_DIR=${NWM_PACKAGE_DIR}"
echo "DATAROOT=${DATAROOT}"


function run_ecf_task() {
  local task_path="$1"
  echo "Triggering ${task_path} ..."
  docker exec ecflow-server bash -c "ecflow_client --run=${task_path}"
  while docker exec ecflow-server bash -c "ecflow_client --get_state=${task_path}" | grep -q "state:submitted\|state:active"; do
    sleep 5
    echo "  ... ${task_path} is running ..."
  done
  echo "${task_path} final state: $(docker exec ecflow-server bash -c "ecflow_client --get_state=${task_path}" | grep -o 'state:[^ ]*')"
}


PDY=$(date +"%Y%m%d")
sed -i -e "s|edit ECF_HOME .*|edit ECF_HOME \"${NWM_PACKAGE_DIR}/ecf\"|" ecf/nwm.def
sed -i -e "s|edit ECF_INCLUDE .*|edit ECF_INCLUDE \"${NWM_PACKAGE_DIR}/ecf\"|" ecf/nwm.def
sed -i -e "s|edit ECF_OUT .*|edit ECF_OUT \"${DATAROOT}\"|" ecf/nwm.def
sed -i -e "s/repeat date YMD [0-9]*/repeat date YMD ${PDY}/" ecf/nwm.def

sed -i -e "s|^export DATAROOT=.*|export DATAROOT=${DATAROOT}|" ecf/model_envir.h
sed -i -e "s|^export PACKAGEROOT=.*|export PACKAGEROOT=$(dirname "${NWM_PACKAGE_DIR}")|" ecf/model_envir.h

if [ ! -d "${NWM_PACKAGE_DIR}/ush/nwm-rte" ]; then
  echo "Installing RTE ..."
  cd "${NWM_PACKAGE_DIR}/ush"
  # TODO update this line to clone either the default branch or the development branch
  git clone -b maxkipp-ecflow-client https://github.com/NGWPC/nwm-rte.git
  cd ./nwm-rte/
  ./setup_clone_repos.sh https
  ./ngen_rte_build.sh
  cd "${NWM_PACKAGE_DIR}"
else
  echo "RTE already installed, skipping."
fi

mkdir -p "${DATAROOT}"
mkdir -p "${DATAROOT}/nwm/test"
mkdir -p "${DATAROOT}/nwm/hourly/nwm_analysis_assim"
mkdir -p "${DATAROOT}/nwm/hourly/nwm_short_range"
mkdir -p "${DATAROOT}/nwm/daily/nwm_extended_analysis_assim"

echo "Starting ecflow-server container ..."
cd "${NWM_PACKAGE_DIR}/ecflow-server"
NWM_PACKAGE_DIR="${NWM_PACKAGE_DIR}" DATAROOT="${DATAROOT}" ./ecflow-server-start.sh
cd "${NWM_PACKAGE_DIR}"

echo "Loading NWM suite into server ..."
docker exec ecflow-server bash -c "
  cd ${NWM_PACKAGE_DIR}/ecf && \
  ecflow_client --delete yes /nwm 2>/dev/null || true && \
  ecflow_client --load=nwm.def && \
  ecflow_client --begin=nwm && \
  ecflow_client --restart && \
  ecflow_client --stats
"

echo "NWM v4.0.0 is installed (Docker approach). Running tests..."

run_ecf_task /nwm/test/test_ngen_rte_noop
run_ecf_task /nwm/test/test_ngen_rte_pytest
