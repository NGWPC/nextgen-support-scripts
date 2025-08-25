#!/usr/bin/env bash
set -euo pipefail

# set users, dnf packages, and python packages
ADD_USERS="$USER ngen-pw-user miguel.pena peter.a.kronenberg khalid.ali bijan.zarean christina.osumi"
DNF_PACKAGES_EXTRA=""
PY_PIP_PKGS="Flask gunicorn"

# set singularity cache and tmp dirs
export SINGULARITY_CACHEDIR=/ngencerf-app/singularity/
export SINGULARITY_TMPDIR=/ngencerf-app/singularity/

# repo location and script to fetch
REPO_URL="https://raw.githubusercontent.com/NGWPC/nwm-automation-scripts/pena-pw-updates/parallel_works_scripts"
SCRIPT_PATH="cluster_startup.sh"
LOCAL_SCRIPT="/tmp/${SCRIPT_PATH}"

# fetch with retries
curl -fsSL --retry 3 --retry-connrefused "${REPO_URL}/${SCRIPT_PATH}" -o "$LOCAL_SCRIPT"
chmod +x "$LOCAL_SCRIPT"

# run script with environment variables
ADD_USERS="$ADD_USERS" \
DNF_PACKAGES_EXTRA="$DNF_PACKAGES_EXTRA" \
PY_PIP_PKGS="$PY_PIP_PKGS" \
"$LOCAL_SCRIPT"
