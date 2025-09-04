#!/usr/bin/env bash
set -euo pipefail

# set sudo users, dnf packages, and python packages
ADD_USERS="ngen-pw-user miguel.pena peter.a.kronenberg khalid.ali bijan.zarean christina.osumi"
DNF_PACKAGES_EXTRA=""
PY_PIP_PKGS="Flask gunicorn"

# set startup_cluster script paths
REPO_URL="https://raw.githubusercontent.com/NGWPC/nwm-automation-scripts/pena-pw-updates/parallel_works_scripts"
SCRIPT_PATH="startup_cluster.sh"
LOCAL_SCRIPT="/tmp/${SCRIPT_PATH}"

# fetch startup_cluster script
curl -fsSL --retry 3 --retry-connrefused "${REPO_URL}/${SCRIPT_PATH}" -o "$LOCAL_SCRIPT"
chmod +x "$LOCAL_SCRIPT"

# run script with environment variables
ADD_USERS="$ADD_USERS" \
DNF_PACKAGES_EXTRA="$DNF_PACKAGES_EXTRA" \
PY_PIP_PKGS="$PY_PIP_PKGS" \
"$LOCAL_SCRIPT"
