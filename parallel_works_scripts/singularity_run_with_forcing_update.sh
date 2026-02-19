#!/bin/bash

# ==============================================================================
# Singularity Run with ngen-forcing Python Package Update
# ==============================================================================
#
# Purpose: Run Singularity containers with an updated ngen-forcing Python
#          package installed at runtime. No .sif modification needed.
#
# Usage:
#   ./singularity_run_with_forcing_update.sh [OPTIONS] <sif_file> -- <command>
#
# Options:
#   --forcing-path PATH     Path to ngen-forcing repo (default: /ngencerf-app/ngen-forcing)
#   --no-update            Skip pip install (just run command normally)
#   --singularity-opts     Additional singularity exec options
#   --help                 Show this help message
#
# Examples:
#   # Run a Python script
#   ./singularity_run_with_forcing_update.sh nwm-cal-mgr.sif -- python calibration.py
#
#   # Run with additional singularity options
#   ./singularity_run_with_forcing_update.sh --singularity-opts "--env FOO=bar" \
#     nwm-cal-mgr.sif -- python script.py
#
#   # Skip the update (run normally)
#   ./singularity_run_with_forcing_update.sh --no-update nwm-cal-mgr.sif -- python script.py
#
# Note: This adds ~5-10 seconds to startup for pip install
#
# ==============================================================================

set -e

# --- Default Configuration ---
FORCING_PATH="/ngencerf-app/ngen-forcing"
DO_UPDATE=true
SINGULARITY_OPTS=""
SIF_FILE=""
COMMAND_ARGS=()

# --- Help Function ---
show_help() {
    sed -n '3,28p' "$0" | sed 's/^# //' | sed 's/^#//'
}

# --- Parse Arguments ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            show_help
            exit 0
            ;;
        --forcing-path)
            shift
            FORCING_PATH="$1"
            ;;
        --no-update)
            DO_UPDATE=false
            ;;
        --singularity-opts)
            shift
            SINGULARITY_OPTS="$1"
            ;;
        --)
            shift
            COMMAND_ARGS=("$@")
            break
            ;;
        *)
            if [[ -z "$SIF_FILE" ]]; then
                SIF_FILE="$1"
            else
                echo "Error: Unexpected argument '$1'"
                echo "Use -- to separate SIF file from command"
                echo "Example: $0 file.sif -- python script.py"
                exit 1
            fi
            ;;
    esac
    shift
done

# --- Validation ---
if [[ -z "$SIF_FILE" ]]; then
    echo "Error: No SIF file specified"
    echo ""
    show_help
    exit 1
fi

if [[ ! -f "$SIF_FILE" ]]; then
    echo "Error: SIF file not found: $SIF_FILE"
    exit 1
fi

if [[ ${#COMMAND_ARGS[@]} -eq 0 ]]; then
    echo "Error: No command specified"
    echo "Use -- to separate SIF file from command"
    echo "Example: $0 $SIF_FILE -- python script.py"
    exit 1
fi

if [[ "$DO_UPDATE" == "true" ]] && [[ ! -d "$FORCING_PATH" ]]; then
    echo "Warning: ngen-forcing directory not found at: $FORCING_PATH"
    echo "Skipping pip install update"
    DO_UPDATE=false
fi

# --- Build Command ---
if [[ "$DO_UPDATE" == "true" ]]; then
    # Combine the pip install with the actual command
    FULL_COMMAND="pip install --force-reinstall --quiet --user /ngen-forcing 2>&1 | grep -v 'WARNING: Running pip' || true; ${COMMAND_ARGS[*]}"

    echo "========================================"
    echo "Running with ngen-forcing update"
    echo "========================================"
    echo "SIF: $SIF_FILE"
    echo "Forcing path: $FORCING_PATH"
    echo "Command: ${COMMAND_ARGS[*]}"
    echo ""
    echo "Installing ngen-forcing Python package..."

    # Run with bind mount
    singularity exec \
        --bind "$FORCING_PATH:/ngen-forcing" \
        $SINGULARITY_OPTS \
        "$SIF_FILE" \
        bash -c "$FULL_COMMAND"
else
    echo "========================================"
    echo "Running without update"
    echo "========================================"
    echo "SIF: $SIF_FILE"
    echo "Command: ${COMMAND_ARGS[*]}"
    echo ""

    # Run normally without bind mount
    singularity exec \
        $SINGULARITY_OPTS \
        "$SIF_FILE" \
        "${COMMAND_ARGS[@]}"
fi
