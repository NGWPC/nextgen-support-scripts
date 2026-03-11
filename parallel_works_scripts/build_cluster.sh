#!/bin/bash

set -e
set -o pipefail

# Trap errors to provide better error reporting
trap 'handle_error $? $LINENO' ERR

handle_error() {
    local exit_code=$1
    local line_number=$2

    echo ""
    echo "=========================================="
    echo "BUILD FAILED"
    echo "=========================================="
    echo "Error occurred at line: $line_number"
    echo "Exit code: $exit_code"
    echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    echo "Check the build output above for details."
    echo "Log file: ${LOGFILE:-build_cluster.log}"
    echo "=========================================="
    echo ""

    # Exit cleanly without killing the parent shell
    exit $exit_code
}

# ==============================================================================
# NGEN/NGENCERF Build Script
# ==============================================================================
#
# This script pulls Docker images from the registry and builds Singularity
# containers (SIFs) for selected NGEN repos.
# It supports both interactive use and non-interactive (automated) use via CLI.
#
# Docker images are built via GitHub Actions CI/CD workflows. To build an image:
#   1. Navigate to the repo on GitHub
#   2. Click Actions -> the CI/CD workflow (e.g., "CI/CD")
#   3. Click "Run workflow" and specify any build arguments (e.g., branch overrides)
#   4. After the workflow completes, the image is available to pull here
#
# ------------------------------------------------------------------------------
# USAGE EXAMPLES
# ------------------------------------------------------------------------------
#
# Interactive mode (will prompt for build type, repos, and tags):
#   ./build_cluster.sh
#
# Development build (non-interactive, pulls :latest and builds SIFs):
#   ./build_cluster.sh --build-type=development ngen nwm-cal-mgr
#
# Build all supported repos (non-interactive):
#   ./build_cluster.sh --build-type=development all
#
# Release build (will prompt for tags if not provided):
#   ./build_cluster.sh --build-type=release ngen nwm-cal-mgr nwm-verf
#
# Release build with tags specified up front:
#   ./build_cluster.sh --build-type=release \
#     --tag=ngen:v1.2.3 --tag=nwm-cal-mgr:v1.2.3 --tag=nwm-verf:v1.2.3 \
#     ngen nwm-cal-mgr nwm-verf
#
# ------------------------------------------------------------------------------
# ARGUMENTS
# ------------------------------------------------------------------------------
#
#   --build-type=TYPE        One of: development, release
#   --tag=REPO:TAG           Specify the Docker image tag to pull for REPO.
#                            ngen-forcing can be used as shorthand for all forcing images.
#                            Example: --tag=ngen:v1.2.3
#                            Example: --tag=ngen-forcing:v1.2.3
#   repo names               List of repos to pull (space-separated on CLI), or use "all"
#                            In interactive mode, repos can be space or comma-separated
#
# Supported repos:
#   ngencerf-server, ngencerf-ui, ngencerf-docker, ngen, nwm-cal-mgr, ngen-forcing,
#   ngen-bmi-forcing, ngen-sfincs-forcing, ngen-coastal, nwm-fcst-mgr, nwm-verf
#
# ngen-forcing expands to all individual forcing images (ngen-bmi-forcing, ngen-sfincs-forcing, ngen-coastal).
#
# Notes:
# - If no arguments are passed, the script runs interactively.
# - If "all" is passed as a repo, it expands to all supported repos.
# - For release, tag prompts will appear if tags are not provided via --tag.
#
# ==============================================================================

# --- BASE DIRECTORY SETUP (paths only, actual creation happens after arg parsing) ---
BASE_PATH="/ngencerf-app"
SINGULARITY_DIR="${BASE_PATH}/singularity"

REPOS=(
    "ngencerf-ui"
    "ngencerf-server"
    "ngencerf-docker"
    "ngen"
    "nwm-cal-mgr"
    "ngen-forcing"
    "nwm-fcst-mgr"
    "nwm-verf"
)
# individual forcing image repos (ngen-forcing expands to these)
FORCING_IMAGE_REPOS=("ngen-bmi-forcing" "ngen-sfincs-forcing" "ngen-coastal")
REGISTRY="ghcr.io/ngwpc"

BUILD_TYPE=""
SELECTED_REPOS=()

# Tags for release builds
declare -A TAGS  # map: repo -> tag

# map repo -> "docker_image|sif_name" (space-separated for multiples)
images_for_repo() {
    local repo="$1"
    case "$repo" in
        ngen)            echo "ngen|ngen" ;;
        ngencerf-ui)     echo "" ;;
        ngencerf-server) echo "" ;;
        ngencerf-docker) echo "" ;;
        nwm-cal-mgr)     echo "nwm-cal-mgr|nwm-cal-mgr" ;;
        ngen-bmi-forcing) echo "ngen-bmi-forcing|ngen-bmi-forcing" ;;
        ngen-sfincs-forcing) echo "ngen-sfincs-forcing|ngen-sfincs-forcing" ;;
        ngen-coastal)    echo "ngen-coastal|ngen-coastal" ;;
        nwm-fcst-mgr)    echo "nwm-fcst-mgr|nwm-fcst-mgr" ;;
        nwm-verf)        echo "nwm-verf|nwm-verf" ;;
        *)               echo "$repo|$repo" ;;
    esac
}

# function to determine if a repo has an associated SIF to build
repo_has_sif() {
    case "$1" in
        ngencerf-server|ngencerf-ui|ngencerf-docker) return 1 ;;
        *) return 0 ;;
    esac
}

# --- Help function ---
show_help() {
    cat <<'EOF'
NGEN/NGENCERF Build Script

This script pulls Docker images from the registry and builds Singularity
containers (SIFs) for selected NGEN repos.

Docker images are built via GitHub Actions. To build an image:
  1. Navigate to the repo on GitHub
  2. Click Actions -> the CI/CD workflow (e.g., "CI/CD")
  3. Click "Run workflow" and specify any build arguments
  4. After the workflow completes, the image is available to pull here

USAGE:
  ./build_cluster.sh [OPTIONS] [REPOS...]

OPTIONS:
  --build-type=TYPE          One of: development, release
  --tag=REPO:TAG             Specify Docker image tag to pull for REPO. Can be repeated.
                             ngen-forcing can be used as shorthand for all forcing images.
                             Example: --tag=ngen:v1.2.3
  --help, -h                 Show this help message and exit

REPOS:
  Supported repos: ngencerf-server, ngencerf-ui, ngencerf-docker, ngen, nwm-cal-mgr,
                   ngen-forcing, ngen-bmi-forcing, ngen-sfincs-forcing, ngen-coastal, nwm-fcst-mgr, nwm-verf
  ngen-forcing expands to all forcing images (ngen-bmi-forcing, ngen-sfincs-forcing, ngen-coastal)
  Use "all" to pull all supported repos

EXAMPLES:
  Interactive mode (will prompt for build type, repos, and tags):
    ./build_cluster.sh

  Development build (pulls :latest for all selected repos):
    ./build_cluster.sh --build-type=development ngen nwm-cal-mgr

  Development build for all repos:
    ./build_cluster.sh --build-type=development all

  Release build (will prompt for tags):
    ./build_cluster.sh --build-type=release ngen nwm-cal-mgr nwm-verf

  Release build with tags specified up front:
    ./build_cluster.sh --build-type=release \
      --tag=ngen:v1.2.3 --tag=nwm-cal-mgr:v1.2.3 --tag=nwm-verf:v1.2.3 \
      ngen nwm-cal-mgr nwm-verf

  Release build with ngen-forcing shorthand:
    ./build_cluster.sh --build-type=release \
      --tag=ngen-forcing:v1.2.3 --tag=ngen:v1.2.3 \
      ngen-forcing ngen

NOTES:
  - If no arguments are passed, the script runs interactively
  - If "all" is passed as a repo, it expands to all supported repos
  - ngen-forcing expands to ngen-bmi-forcing + ngen-sfincs-forcing + ngen-coastal
  - For release builds, tag prompts will appear if not specified via --tag
  - Logs are written to: ${SINGULARITY_DIR}/build_cluster_<timestamp>.log
EOF
}

# --- Parse args ---
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                show_help
                exit 0
            ;;
            --build-type=*)
                BUILD_TYPE="${1#*=}"
            ;;
            --build-type)
                shift; BUILD_TYPE="$1"
            ;;
            --tag=*)
                local kv="${1#*=}"
                local repo="${kv%%:*}"
                local tag="${kv##*:}"
                if [[ -z "$tag" ]]; then
                    echo "Error: --tag '${kv}' must specify a tag (format: REPO:TAG)"; exit 1
                fi
                # ngen-forcing is a shorthand for all individual forcing image repos
                if [[ "$repo" == "ngen-forcing" ]]; then
                    for fr in "${FORCING_IMAGE_REPOS[@]}"; do
                        TAGS["$fr"]="$tag"
                    done
                elif [[ " ${REPOS[*]} " =~ " ${repo} " ]] || [[ " ${FORCING_IMAGE_REPOS[*]} " =~ " ${repo} " ]]; then
                    TAGS["$repo"]="$tag"
                else
                    echo "Error: --tag targets unsupported repo '${repo}'. Allowed: ngen-forcing ${REPOS[*]} ${FORCING_IMAGE_REPOS[*]}"; exit 1
                fi
            ;;
            -*)
                echo "Unknown option: $1"; exit 1
            ;;
            *)
                SELECTED_REPOS+=("$1")
            ;;
        esac
        shift
    done
}

parse_args "$@"

# validate BUILD_TYPE if provided via CLI
if [[ -n "$BUILD_TYPE" ]] && [[ "$BUILD_TYPE" != "development" ]] && [[ "$BUILD_TYPE" != "release" ]]; then
    echo "Error: Invalid --build-type '${BUILD_TYPE}'. Must be one of: development, release"
    exit 1
fi

# --- Create directories and setup logging (after arg parsing to allow --help to work) ---
mkdir -p "$SINGULARITY_DIR"
LOGFILE="${SINGULARITY_DIR}/build_cluster_$(date -u +"%Y-%m-%dT%H:%M:%SZ").log"
exec > >(tee -i "$LOGFILE") 2>&1

# --- Interactive prompts if needed ---
if [[ -z "$BUILD_TYPE" && -t 0 ]]; then
    echo "Select build type:"
    echo "1) development"
    echo "2) release"
    read -p "Enter number [1-2]: " build_choice || { echo "Error reading input, exiting."; exit 1; }
    case $build_choice in
        1) BUILD_TYPE="development" ;;
        2) BUILD_TYPE="release" ;;
        *) echo "Invalid choice, exiting."; exit 1 ;;
    esac
fi

if [[ ${#SELECTED_REPOS[@]} -eq 0 && -t 0 ]]; then
    echo "Available repos: ${REPOS[*]}"
    read -p "Enter repos to pull (space or comma-separated, or press Enter for all): " repos_input || { echo "Error reading input, exiting."; exit 1; }
    # if user pressed Enter without typing anything, select all repos
    if [[ -z "$repos_input" ]]; then
        SELECTED_REPOS=("${REPOS[@]}")
        echo "All repos selected: ${SELECTED_REPOS[*]}"
    else
        # normalize input: replace commas with spaces, then split into array
        repos_input="${repos_input//,/ }"
        read -ra SELECTED_REPOS <<< "$repos_input"
    fi
fi

if [[ -z "$BUILD_TYPE" || ${#SELECTED_REPOS[@]} -eq 0 ]]; then
    echo "Error: build type and at least one repo must be provided."; exit 1
fi

# expand 'all'
if [[ " ${SELECTED_REPOS[*]} " =~ " all " ]]; then
    echo "'all' specified — pulling all available repos."
    SELECTED_REPOS=("${REPOS[@]}")
    echo "Repos to pull: ${SELECTED_REPOS[*]}"
fi

# validate repos (accept both REPOS and individual FORCING_IMAGE_REPOS)
INVALID_REPOS=()
for repo in "${SELECTED_REPOS[@]}"; do
    if [[ ! " ${REPOS[*]} " =~ " $repo " ]] && [[ ! " ${FORCING_IMAGE_REPOS[*]} " =~ " $repo " ]]; then
        INVALID_REPOS+=("$repo")
    fi
done
if [[ ${#INVALID_REPOS[@]} -gt 0 ]]; then
    echo "Error: Invalid repo(s): ${INVALID_REPOS[*]}"
    echo "Allowed repos are: ${REPOS[*]} ${FORCING_IMAGE_REPOS[*]}"
    exit 1
fi

# expand ngen-forcing to individual forcing image repos
if [[ " ${SELECTED_REPOS[*]} " =~ " ngen-forcing " ]]; then
    echo "'ngen-forcing' selected — expanding to all forcing images: ${FORCING_IMAGE_REPOS[*]}"
    local_new_selected=()
    for r in "${SELECTED_REPOS[@]}"; do
        if [[ "$r" == "ngen-forcing" ]]; then
            for fr in "${FORCING_IMAGE_REPOS[@]}"; do
                # avoid duplicates
                if [[ ! " ${local_new_selected[*]} " =~ " ${fr} " ]]; then
                    local_new_selected+=("$fr")
                fi
            done
        else
            local_new_selected+=("$r")
        fi
    done
    SELECTED_REPOS=("${local_new_selected[@]}")
    # transfer ngen-forcing tag settings to individual repos if not already set
    if [[ -n "${TAGS[ngen-forcing]:-}" ]]; then
        for fr in "${FORCING_IMAGE_REPOS[@]}"; do
            if [[ -z "${TAGS[$fr]:-}" ]]; then
                TAGS["$fr"]="${TAGS[ngen-forcing]}"
            fi
        done
    fi
    echo "Expanded repos: ${SELECTED_REPOS[*]}"
fi

echo "Build type selected: $BUILD_TYPE"
echo "Selected repos: ${SELECTED_REPOS[*]}"

# --- tag prompts for release builds ---
if [[ "$BUILD_TYPE" == "release" ]]; then
    for repo in "${SELECTED_REPOS[@]}"; do
        case $repo in
            ngencerf-ui|ngencerf-server|ngencerf-docker|\
            ngen-bmi-forcing|ngen-coastal|ngen-sfincs-forcing|\
            ngen|nwm-cal-mgr|nwm-fcst-mgr|nwm-verf)
                if [[ -z "${TAGS[$repo]:-}" ]]; then
                    read -p "Enter ${repo} tag: " TAGS[$repo] || { echo "Error reading input, exiting."; exit 1; }
                fi
            ;;
        esac
    done

    # validate that all required tags have been provided
    for repo in "${SELECTED_REPOS[@]}"; do
        if repo_has_sif "$repo" && [[ -z "${TAGS[$repo]:-}" ]]; then
            echo "Error: Tag for '$repo' cannot be empty"; exit 1
        fi
    done
fi


# build SIF and update symlink
# only rebuild when docker image digest/id changes; always delete temp tar
# keeps a tiny .meta file to remember the last image key and built sif filename
get_image_key() {
    local ref="$1"
    local dig
    dig="$(docker inspect --format='{{index .RepoDigests 0}}' "$ref" 2>/dev/null || true)"
    if [[ -n "$dig" && "$dig" != "<no value>" ]]; then
        echo "${dig##*@}"   # sha256:...
        return 0
    fi
    docker inspect --format='{{.Id}}' "$ref" 2>/dev/null || true
}

ensure_image_present() {
    local repo="$1"
    local image_ref="$2"

    echo "[$(date '+%H:%M:%S')] Pulling docker image: $image_ref"
    if ! docker pull "$image_ref"; then
        echo ""
        echo "=========================================="
        echo "DOCKER PULL FAILED"
        echo "=========================================="
        echo "Repository: ${repo}"
        echo "Image: ${image_ref}"
        echo ""
        echo "The image does not exist in the registry."
        echo "This typically happens when:"
        echo "  1. The GitHub Actions build hasn't been triggered yet"
        echo "  2. The tag name is incorrect"
        echo ""
        echo "To build and publish the image:"
        echo "  - Navigate to the ${repo} repo on GitHub"
        echo "  - Click Actions -> CI/CD workflow"
        echo "  - Click 'Run workflow' and specify any build arguments"
        echo "=========================================="
        exit 1
    fi
}

build_singularity_container_update_symlink() {
    local build_type="$1"
    local sif_base="$2"
    local image_ref="$3"
    local tag="$4"

    local sif_dir="${SINGULARITY_DIR}"
    local symlink_name="${sif_base}.sif"
    local ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    local sif_file
    local meta_file="${sif_dir}/${sif_base}.meta"

    # naming: dev -> latest; release -> explicit tag
    if [[ "$build_type" == "development" ]]; then
        sif_file="${sif_base}-latest-${ts}.sif"
    else
        sif_file="${sif_base}-${tag}-${ts}.sif"
    fi

    # compute current image key and read previous if available
    local current_key prev_key="" prev_sif=""
    current_key="$(get_image_key "$image_ref")"
    if [[ -z "$current_key" ]]; then
        echo "could not inspect '$image_ref' to compute image key"; exit 1
    fi
    if [[ -f "$meta_file" ]]; then
        # validate meta file contains only expected variable assignments
        if grep -Eq '^[A-Z_]+=' "$meta_file" && ! grep -Eq '[;&|$(){}<>`]' "$meta_file"; then
            # Extract only the specific variables we need instead of sourcing the entire file
            # This prevents polluting the global environment with BUILD_TYPE from previous builds
            prev_key="$(grep -E '^IMAGE_KEY=' "$meta_file" | cut -d'=' -f2- || true)"
            prev_sif="$(grep -E '^SIF_FILE=' "$meta_file" | cut -d'=' -f2- || true)"
        else
            echo "Warning: meta file '$meta_file' appears corrupted or unsafe, ignoring it."
        fi
    fi

    # skip rebuild if image unchanged and previous sif exists; just refresh symlink
    if [[ -n "$prev_key" && "$prev_key" == "$current_key" && -n "$prev_sif" && -f "${sif_dir}/${prev_sif}" ]]; then
        ln -sfn "$prev_sif" "${sif_dir}/${symlink_name}"
        echo "no image change for ${image_ref} (${current_key}); kept existing SIF: ${symlink_name} -> ${prev_sif}"
        return 0
    fi

    (
        cd "$sif_dir"
        # create temp tar name and ensure cleanup on any exit
        local tar_name
        tar_name="$(mktemp -p "$sif_dir" "${sif_base}.XXXXXXXX.tar")"
        cleanup() { rm -f "$tar_name"; }
        trap cleanup EXIT INT TERM

        echo "[$(date '+%H:%M:%S')] Saving docker image to tar: ${image_ref}"
        docker save "${image_ref}" -o "${tar_name}"

        echo "[$(date '+%H:%M:%S')] Building SIF: ${sif_file} from docker-archive:${tar_name}"
        singularity build "${sif_file}" "docker-archive:${tar_name}"

        echo "[$(date '+%H:%M:%S')] Creating relative symlink: ${symlink_name} -> ${sif_file}"
        ln -sfn "${sif_file}" "${symlink_name}"

        # write/update meta so future runs can skip when unchanged
        {
            echo "IMAGE_REF=${image_ref}"
            echo "IMAGE_KEY=${current_key}"
            echo "TIMESTAMP=${ts}"
            echo "SIF_FILE=${sif_file}"
            echo "BUILD_TYPE=${build_type}"
            echo "TAG=${tag}"
        } > "${meta_file}"
    )
}

# ---- DEVELOPMENT WORKFLOW ----
if [[ "$BUILD_TYPE" == "development" ]]; then
    cd "$BASE_PATH"

    for repo in "${SELECTED_REPOS[@]}"; do
        echo

        if repo_has_sif "$repo"; then
            for pair in $(images_for_repo "$repo"); do
                [[ -z "$pair" ]] && continue
                docker_img="${pair%%|*}"
                sif_name="${pair##*|}"
                IMAGE="${REGISTRY}/${docker_img}:latest"

                ensure_image_present "$repo" "$IMAGE"
                build_singularity_container_update_symlink "$BUILD_TYPE" "$sif_name" "$IMAGE" "latest"
            done
        else
            echo "[$(date '+%H:%M:%S')] Skipping SIF build for ${repo} (no SIF target)"
        fi
    done

    echo "Development build completed successfully!"
    exit 0
fi

# --- RELEASE WORKFLOW ---
if [[ "$BUILD_TYPE" == "release" ]]; then
    cd "$BASE_PATH"

    for repo in "${SELECTED_REPOS[@]}"; do
        echo

        if repo_has_sif "$repo"; then
            tag_val="${TAGS[$repo]}"
            for pair in $(images_for_repo "$repo"); do
                [[ -z "$pair" ]] && continue
                docker_img="${pair%%|*}"
                sif_name="${pair##*|}"
                IMAGE="${REGISTRY}/${docker_img}:${tag_val}"

                ensure_image_present "$repo" "$IMAGE"
                build_singularity_container_update_symlink "$BUILD_TYPE" "$sif_name" "$IMAGE" "$tag_val"
            done
        else
            echo "[$(date '+%H:%M:%S')] Skipping SIF build for ${repo} (no SIF target)"
        fi
    done

    echo "Release build completed successfully!"
    exit 0
fi

# --- INVALID BUILD_TYPE ---
echo "Error: Invalid BUILD_TYPE '${BUILD_TYPE}'. Must be one of: development, release"
exit 1
