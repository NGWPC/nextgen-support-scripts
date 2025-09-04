#!/bin/bash

set -e
set -o pipefail

# ==============================================================================
# NGEN/NGENCERF Build Script
# ==============================================================================
#
# This script builds and symlinks Singularity containers for selected NGEN repos.
# It supports both interactive use and non-interactive (automated) use via CLI.
#
# ------------------------------------------------------------------------------
# USAGE EXAMPLES
# ------------------------------------------------------------------------------
#
# Interactive mode (will prompt for build type and repos):
#   ./build_cluster.sh
#
# Development build (non-interactive, builds ngen and nwm-cal-mgr):
#   ./build_cluster.sh --build-type=development ngen nwm-cal-mgr
#
# Build all supported repos (non-interactive):
#   ./build_cluster.sh --build-type=development all
#
# Build for release (will still prompt for tags):
#   ./build_cluster.sh --build-type=release ngen nwm-cal-mgr ngen-verf
#   (will still prompt for tags)
#
# ------------------------------------------------------------------------------
# ARGUMENTS
# ------------------------------------------------------------------------------
#
#   --build-type=TYPE     One of: development, release
#   repo names              List of repos to build (space-separated), or use "all"
#
# Supported repos:
#   ngencerf-server, ngencerf-ui, ngencerf-docker, ngen, nwm-cal-mgr, ngen-bmi-forcing, ngen-lumped-forcing, ngen-coastal, nwm-fcst-mgr, nwm-verf
#
# Notes:
# - If no arguments are passed, the script runs interactively.
# - If "all" is passed as a repo, it expands to all supported repos.
# - For release, tag prompts will appear.
#
# ==============================================================================

# --- BASE DIRECTORY SETUP ---
# BASE_PATH is the root for all NGEN build assets, including repos and Singularity output
BASE_PATH="/ngencerf-app"
SINGULARITY_DIR="${BASE_PATH}/singularity"
mkdir -p $SINGULARITY_DIR

# Redirect stdout and stderr to a log file in the Singularity directory
LOGFILE="${SINGULARITY_DIR}/build_cluster_$(date -u +"%Y-%m-%dT%H:%M:%SZ").log"
exec > >(tee -i "$LOGFILE") 2>&1

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
REGISTRY="ghcr.io/ngwpc"

BUILD_TYPE=""
SELECTED_REPOS=()

# helper to map a repo to docker image name(s) and the desired sif name(s)
# format: "docker_image|sif_name" space separated for multiples
images_for_repo() {
    local repo="$1"
    case "$repo" in
        ngen) echo "ngen|ngen" ;;
        ngencerf-ui) echo "" ;; # no sif
        ngencerf-server) echo "" ;; # no sif
        ngencerf-docker) echo "" ;; # no image or sif
        nwm-cal-mgr) echo "nwm-cal-mgr|ngen-cal" ;; # image vs sif name difference
        ngen-forcing) echo "ngen-bmi-forcing|ngen-bmi-forcing ngen-lumped-forcing|ngen-lumped-forcing" ;; # ngen-coastal|ngen-coastal" ;;
        nwm-fcst-mgr) echo "nwm-fcst-mgr|ngen-fcst" ;; # image vs sif name difference
        nwm-verf) echo "nwm-verf|ngen-verf" ;;
        *) echo "$repo|$repo" ;;
    esac
}

# helper to say whether a repo should produce a sif
repo_has_sif() {
    case "$1" in
        ngencerf-server|ngencerf-ui|ngencerf-docker) return 1 ;;
        *) return 0 ;;
    esac
}

# --- Parse command-line args ---
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
        --build-type=*)
            BUILD_TYPE="${1#*=}"
            ;;
        --build-type)
            shift
            BUILD_TYPE="$1"
            ;;
        -*)
            echo "Unknown option: $1"
            exit 1
            ;;
        *)
            SELECTED_REPOS+=("$1")
            ;;
        esac
        shift
    done
}

parse_args "$@"

# --- Prompt interactively if needed ---
if [[ -z "$BUILD_TYPE" && -t 0 ]]; then
    echo "Select build type:"
    echo "1) development"
    echo "2) release"
    read -p "Enter number [1-2]: " build_choice
    case $build_choice in
    1) BUILD_TYPE="development" ;;
    2) BUILD_TYPE="release" ;;
    *)
        echo "Invalid choice, exiting."
        exit 1
        ;;
    esac
fi

if [[ ${#SELECTED_REPOS[@]} -eq 0 && -t 0 ]]; then
    echo "Available repos: ${REPOS[*]}"
    read -p "Enter repos to build (space-separated from the list above): " -a SELECTED_REPOS
fi

if [[ -z "$BUILD_TYPE" || ${#SELECTED_REPOS[@]} -eq 0 ]]; then
    echo "Error: build type and at least one repo must be provided."
    exit 1
fi

echo "Build type selected: $BUILD_TYPE"
echo "Selected repos: ${SELECTED_REPOS[*]}"

# Handle 'all' keyword
if [[ " ${SELECTED_REPOS[*]} " =~ " all " ]]; then
    echo "'all' specified — building all available repos."
    SELECTED_REPOS=("${REPOS[@]}")
    echo "Repos to build: ${SELECTED_REPOS[*]}"
fi

# validate SELECTED_REPOS
INVALID_REPOS=()
for repo in "${SELECTED_REPOS[@]}"; do
    if [[ ! " ${REPOS[*]} " =~ " $repo " ]]; then
        INVALID_REPOS+=("$repo")
    fi
done

if [[ ${#INVALID_REPOS[@]} -gt 0 ]]; then
    echo "Error: Invalid repo(s): ${INVALID_REPOS[*]}"
    echo "Allowed repos are: ${REPOS[*]}"
    exit 1
fi

# prompt for tags if 'release'
declare -A TAGS
if [[ "$BUILD_TYPE" == "release" ]]; then
    for repo in "${SELECTED_REPOS[@]}"; do
        case $repo in
        ngencerf-ui)
            read -p "Enter ngencerf-ui tag: " TAGS[ngencerf-ui]
            ;;
        ngencerf-server)
            read -p "Enter ngencerf-server tag: " TAGS[ngencerf-server]
            ;;
        ngencerf-docker)
            read -p "Enter ngencerf-docker tag: " TAGS[ngencerf-docker]
            ;;
        ngen)
            read -p "Enter ngen tag: " TAGS[ngen]
            ;;
        nwm-cal-mgr)
            read -p "Enter nwm-cal-mgr tag: " TAGS[nwm-cal-mgr]
            ;;
        ngen-forcing)
            read -p "Enter ngen-forcing tag (shared for bmi/lumped/coastal): " TAGS[ngen-forcing]
            ;;
        nwm-fcst-mgr)
            read -p "Enter nwm-fcst-mgr tag: " TAGS[nwm-fcst-mgr]
            ;;
        nwm-verf)
            read -p "Enter nwm-verf tag: " TAGS[nwm-verf]
            read -p "Enter nwm-eval-mgr tag: " TAGS[nwm-eval-mgr]
            ;;
        esac
    done
fi

# function to update symlinks after building SIFs
build_singularity_container_update_symlink() {
    local build_type="$1"
    local sif_base="$2"     # desired base name for sif and symlink (second column)
    local image_ref="$3"    # full docker image ref (registry/name:tag)
    local tag="$4"          # tag string used for naming

    # Directory where SIFs and symlinks are stored
    local sif_dir="${SINGULARITY_DIR}"

    # The actual .sif filename with a timestamp
    if [[ "$build_type" == "development" ]]; then
        local sif_file="${sif_base}-latest-$(date -u +"%Y-%m-%dT%H:%M:%SZ").sif"
    else
        local sif_file="${sif_base}-${tag}-$(date -u +"%Y-%m-%dT%H:%M:%SZ").sif"
    fi

    # The symlink name (e.g., ngen-cal.sif)
    local symlink_name="${sif_base}.sif"

    (
        cd "$sif_dir"
        echo "Removing old ${symlink_name} symlink for $sif_base..."
        rm -f "${symlink_name}"

        echo "Saving docker image to tar: ${image_ref}"
        local tar_name="${sif_base}.tar"
        docker save "${image_ref}" -o "${tar_name}"

        echo "Building SIF: ${sif_file} from docker-archive:${tar_name}"
        singularity build "${sif_dir}/${sif_file}" "docker-archive:${tar_name}"

        echo "Creating relative symlink: ${symlink_name} -> ${sif_file}"
        ln -sf "${sif_file}" "${symlink_name}"

        rm -f "${tar_name}"
    )
}

# update repo to latest from specified branch
update_repo_branch() {
    local repo="$1"
    local branch="$2"

    echo "Updating $repo to latest from $branch branch..."
    cd "$BASE_PATH/$repo"
    git fetch origin
    git stash save
    git checkout "$branch"
    git pull origin "$branch" --rebase
    git stash pop || true # prevent exit if nothing to pop

    if [[ "$repo" == "ngen" ]]; then
        # initialize and update submodules to correct commit
        git submodule update --init --recursive
    fi
}

# checkout repo at specified tag
checkout_repo_tag() {
    local repo="$1"
    local tag="$2"

    echo "Checking out $repo at tag $tag..."
    cd "$BASE_PATH/$repo"
    git fetch origin
    git stash save
    git checkout "$tag"
    git stash pop || true # prevent exit if nothing to pop

    if [[ "$repo" == "ngen" ]]; then
        # initialize and update submodules to correct commit
        git submodule update --init --recursive
    fi
}

# --- RELEASE WORKFLOW ---
if [[ "$BUILD_TYPE" == "release" ]]; then
    cd "$BASE_PATH"

    # build order: ngen -> others
    if [[ " ${SELECTED_REPOS[@]} " =~ " ngen " ]]; then
        echo "Pulling ngen Docker image..."
        docker pull "${REGISTRY}/ngen:${TAGS[ngen]}"
    fi

    for repo in "${SELECTED_REPOS[@]}"; do
        # do per-repo checkout/build/pull
        case "$repo" in
        "nwm-cal-mgr")
            checkout_repo_tag "nwm-cal-mgr" "${TAGS[nwm-cal-mgr]}"
            echo "Building nwm-cal-mgr Docker image..."
            docker build \
                --progress=plain \
                --no-cache \
                --build-arg NGEN_IMAGE_TAG="${TAGS[ngen]}" \
                --tag="${REGISTRY}/nwm-cal-mgr:${TAGS[nwm-cal-mgr]}" \
                "${BASE_PATH}/nwm-cal-mgr"
            ;;
        "ngen-forcing")
            echo "Pulling ngen-bmi-forcing Docker image..."
            docker pull "${REGISTRY}/ngen-bmi-forcing:${TAGS[ngen-forcing]}"
            echo "Pulling ngen-lumped-forcing Docker image..."
            docker pull "${REGISTRY}/ngen-lumped-forcing:${TAGS[ngen-forcing]}"
            # echo "Pulling ngen-coastal Docker image..."
            # docker pull "${REGISTRY}/ngen-coastal:${TAGS[ngen-forcing]}"
            ;;
        "nwm-fcst-mgr")
            checkout_repo_tag "nwm-fcst-mgr" "${TAGS[nwm-fcst-mgr]}"
            echo "Building nwm-fcst-mgr Docker image..."
            docker build \
                --progress=plain \
                --no-cache \
                --build-arg NGEN_VERSION="${TAGS[ngen]}" \
                --tag="${REGISTRY}/nwm-fcst-mgr:${TAGS[nwm-fcst-mgr]}" \
                "${BASE_PATH}/nwm-fcst-mgr"
            ;;
        "nwm-verf")
            checkout_repo_tag "nwm-verf" "${TAGS[nwm-verf]}"
            echo "Building nwm-verf Docker image..."
            docker build \
                --progress=plain \
                --no-cache \
                --build-arg NWM_EVAL_MGR_TAG="${TAGS[nwm-eval-mgr]}" \
                --tag="${REGISTRY}/nwm-verf:${TAGS[nwm-verf]}" \
                "${BASE_PATH}/nwm-verf"
            ;;
        "ngen")
            # already handled above
            :
            ;;
        ngencerf*)
            checkout_repo_tag "$repo" "${TAGS[$repo]}"
            ;;
        esac

        # build sif(s) according to mapping using explicit docker->sif pairs
        if repo_has_sif "$repo"; then
            tag_val="${TAGS[$repo]}"
            for pair in $(images_for_repo "$repo"); do
                [[ -z "$pair" ]] && continue
                docker_img="${pair%%|*}"
                sif_name="${pair##*|}"
                build_singularity_container_update_symlink "$BUILD_TYPE" "$sif_name" "${REGISTRY}/${docker_img}:${tag_val}" "$tag_val"
            done
        fi
    done

    echo "Release build completed successfully!"
    exit 0
fi

# ---- DEVELOPMENT WORKFLOW ----
if [[ "$BUILD_TYPE" == "development" ]]; then
    cd "$BASE_PATH"

    for repo in "${SELECTED_REPOS[@]}"; do
        echo
        # update ngencerf* repo's development branch
        if [[ "$repo" == ngencerf* ]]; then
            update_repo_branch "$repo" "development"
        fi

        if repo_has_sif "$repo"; then
            # pull and convert to sif for each docker|sif pair
            for pair in $(images_for_repo "$repo"); do
                [[ -z "$pair" ]] && continue
                docker_img="${pair%%|*}"
                sif_name="${pair##*|}"
                IMAGE="${REGISTRY}/${docker_img}:latest"
                echo "Pulling docker image: $IMAGE"
                # TODO: ngen-coastal image builds are failing
                docker pull "$IMAGE"
                build_singularity_container_update_symlink "$BUILD_TYPE" "$sif_name" "$IMAGE" "latest"
            done
        fi
    done

    echo "Development build completed successfully!"
fi
