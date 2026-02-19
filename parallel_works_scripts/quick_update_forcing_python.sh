#!/bin/bash

# ==============================================================================
# Quick Update: ngen-forcing Python Package
# ==============================================================================
#
# Purpose: Rapidly update the ngen-forcing Python package in existing Docker
#          images without needing to rebuild from source. Useful for testing
#          Python-only changes to ngen-forcing.
#
# Usage:
#   ./quick_update_forcing_python.sh [OPTIONS]
#
# Options:
#   --images "image1 image2"    Specify which images to update (space-separated)
#   --tag TAG                   Specify which tag to update (default: latest)
#   --registry REGISTRY         Specify registry (default: ghcr.io/ngwpc)
#   --forcing-path PATH         Path to ngen-forcing repo (default: /ngencerf-app/ngen-forcing)
#   --help                      Show this help message
#
# Examples:
#   # Update all default images with :latest tag
#   ./quick_update_forcing_python.sh
#
#   # Update only ngen and cal-mgr
#   ./quick_update_forcing_python.sh --images "ngen nwm-cal-mgr"
#
#   # Update feature tag instead of latest
#   ./quick_update_forcing_python.sh --tag feature
#
# Note: This ONLY works for Python code changes. For C++ changes or Dockerfile
#       modifications, you must do a full rebuild.
#
# ==============================================================================

set -e

# --- Default Configuration ---
REGISTRY="ghcr.io/ngwpc"
TAG="latest"
FORCING_PATH="/ngencerf-app/ngen-forcing"

# Default images that run ngen and can benefit from quick Python updates
DEFAULT_IMAGES=(
    "ngen"
    "ngen-bmi-forcing"
    "ngen-lumped-forcing"
    "ngen-coastal"
    "nwm-cal-mgr"
    "nwm-fcst-mgr"
)

SELECTED_IMAGES=()

# --- Help Function ---
show_help() {
    sed -n '3,34p' "$0" | sed 's/^# //' | sed 's/^#//'
}

# --- Parse Arguments ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            show_help
            exit 0
            ;;
        --images)
            shift
            IFS=' ' read -ra SELECTED_IMAGES <<< "$1"
            ;;
        --tag)
            shift
            TAG="$1"
            ;;
        --registry)
            shift
            REGISTRY="$1"
            ;;
        --forcing-path)
            shift
            FORCING_PATH="$1"
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
    shift
done

# Use default images if none specified
if [[ ${#SELECTED_IMAGES[@]} -eq 0 ]]; then
    SELECTED_IMAGES=("${DEFAULT_IMAGES[@]}")
fi

# --- Validation ---
if [[ ! -d "$FORCING_PATH" ]]; then
    echo "Error: ngen-forcing directory not found at: $FORCING_PATH"
    echo "Use --forcing-path to specify the correct location"
    exit 1
fi

if [[ ! -f "$FORCING_PATH/setup.py" ]] && [[ ! -f "$FORCING_PATH/pyproject.toml" ]]; then
    echo "Error: $FORCING_PATH does not appear to be a valid Python package"
    exit 1
fi

# --- Main Update Loop ---
echo "========================================"
echo "Quick Update: ngen-forcing Python Package"
echo "========================================"
echo "Registry: $REGISTRY"
echo "Tag: $TAG"
echo "Forcing Path: $FORCING_PATH"
echo "Images to update: ${SELECTED_IMAGES[*]}"
echo ""

UPDATED_COUNT=0
SKIPPED_COUNT=0
FAILED_COUNT=0

for image_name in "${SELECTED_IMAGES[@]}"; do
    full_image="${REGISTRY}/${image_name}:${TAG}"

    echo "----------------------------------------"
    echo "[$(date '+%H:%M:%S')] Processing: $full_image"

    # Check if image exists locally
    if ! docker image inspect "$full_image" &>/dev/null; then
        echo "  Skipped - Image not found locally"
        echo "  (Run build_cluster.sh first to create this image)"
        ((SKIPPED_COUNT++))
        continue
    fi

    # Create a temporary Dockerfile that reinstalls ngen-forcing Python package
    echo "  Reinstalling ngen-forcing Python package..."

    if docker build --progress=plain -t "$full_image" - <<EOF
FROM $full_image
RUN if [ -d /ngen-forcing ]; then \
        pip install --force-reinstall /ngen-forcing; \
    elif [ -d /ngencerf-app/ngen-forcing ]; then \
        pip install --force-reinstall /ngencerf-app/ngen-forcing; \
    else \
        echo "Warning: ngen-forcing not found in expected locations"; \
        exit 1; \
    fi
EOF
    then
        echo "  Successfully updated $full_image"
        ((UPDATED_COUNT++))
    else
        echo "  Failed to update $full_image"
        ((FAILED_COUNT++))
    fi
done

echo ""
echo "========================================"
echo "Summary"
echo "========================================"
echo "Updated:  $UPDATED_COUNT images"
echo "Skipped:  $SKIPPED_COUNT images (not found locally)"
echo "Failed:   $FAILED_COUNT images"
echo ""

if [[ $UPDATED_COUNT -gt 0 ]]; then
    echo "Python package updates complete!"
    echo ""
    echo "Next steps:"
    echo "  1. If using Singularity: Rebuild .sif files with build_cluster.sh"
    echo "  2. Restart your containers to use the updated images"
    echo "  3. Test your Python changes"
fi

if [[ $FAILED_COUNT -gt 0 ]]; then
    echo ""
    echo "Some images failed to update. Check the output above for details."
    exit 1
fi

exit 0
