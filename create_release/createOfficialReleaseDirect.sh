#!/bin/bash
# Define color codes
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Release branch is selected in main(). STANDARD uses development; PW uses development-pw.
DEVELOPMENT_BRANCH="development"
BRANCH_ENVIRONMENT="STANDARD"

# Toggle for printing the exact 'gh' commands being executed.
# Printed commands go to STDERR so that JSON captures using $(...) are not polluted.
DEBUG_GH=false

#-----------------------------------------
# Function: usage
# Displays usage information and exits.
#-----------------------------------------
usage() {
  cat <<EOF

Usage: $(basename "$0") [OPTIONS]

Creates an OFFICIAL GitHub release directly off the "development" (or
"development-pw") branch for every repository listed in a JSON config file,
using the release number and notes already in that file.

There is no RC step, no ngwpc-candidate/ngwpc-release branches, and no pull
requests — this tags and releases whatever is currently on the selected
development branch, as-is.

OPTIONS
  -c, --config FILE          Configuration JSON file.
                              Default: createReleaseConfig.json
  -e, --environment ENV      Branch/release environment: STANDARD or PW.
                              Default: STANDARD
  -o, --create-owp-branch     After a successful release, also create and
                              push ngwpc-<release> (or ngwpc-<release>-pw
                              under PW) from the release tag's exact commit.
                              This is what gets submitted as a pull request
                              to the upstream NOAA OWP parent repo; this
                              script only prepares and pushes the branch, it
                              does not open that PR for you.
                              Default: false (off)
  -v, --verbose               Print the exact 'gh' commands being executed
                              Default: false
  -h, --help                  Display this help and exit.

Environment branches:
  STANDARD:  development
  PW:        development-pw

Release tags:
  STANDARD: 10.2
  PW:       10.2-pw

Examples:
  $(basename "$0")
  $(basename "$0") --config createReleaseConfig.json
  $(basename "$0") --environment PW --config createReleaseConfig_pass1_pw.json
  $(basename "$0") --create-owp-branch

Per-repo config field "env" (optional; PW, AWS, or ALL; defaults to ALL):
  Controls which -e environment(s) a repo entry is processed under,
  independent of the "skip" flag:
    -e PW                  -> repo runs only if env is PW or ALL
    -e STANDARD (default)  -> repo runs only if env is AWS or ALL
  A repo entry with "skip": true is always skipped regardless of "env".
EOF
  exit "${1:-0}"
}

#-----------------------------------------
# Function: git_push
# Quiet wrapper around `git push` that suppresses routine output but
# still surfaces real errors.
#-----------------------------------------
git_push() {
  if ! out=$(git push -q "$@" 2>&1); then
    echo -e "${RED}git push failed: git push $*${NC}"
    echo "$out" >&2
    return 1
  fi
  return 0
}

#-----------------------------------------
# Function: run_gh
# Prints and executes a `gh` command.
# If DEBUG_GH=true, prints "Executing: gh <args...>" to STDERR so it never
# pollutes a $(...) capture. Returns gh's exit status.
#-----------------------------------------
run_gh() {
  local args=("$@")
  if [ "$DEBUG_GH" = true ]; then
    printf 'Executing: ' >&2; printf '%q ' gh "${args[@]}" >&2; echo >&2
  fi
  gh "${args[@]}"
}

#-----------------------------------------
# Function: clean_and_encode_project
# Normalizes a GitHub remote URL to the canonical "owner/repo" form.
#-----------------------------------------
clean_and_encode_project() {
  local project_url="$1"
  project_url=$(echo "$project_url" | sed -e 's#^https\?://[^/]*@#https://#')
  project_url=$(echo "$project_url" | sed -e 's#^https://github\.com/##')
  project_url=$(echo "$project_url" | sed -e 's#^git@github\.com:##')
  project_url=$(echo "$project_url" | sed -e 's#\.git$##')
  echo "$project_url"
}

#-----------------------------------------
# Function: repo_env_applies
# Decides whether a repo config entry should be processed under the current
# BRANCH_ENVIRONMENT (STANDARD or PW), based on the config's optional "env"
# field (PW, AWS, or ALL; defaults to ALL when absent).
#   -e PW       -> repo processed only if env is PW or ALL
#   -e STANDARD -> repo processed only if env is AWS or ALL
#-----------------------------------------
repo_env_applies() {
  local repo_env="$1"
  case "$BRANCH_ENVIRONMENT" in
    PW)
      [[ "$repo_env" == "PW" || "$repo_env" == "ALL" ]]
      ;;
    STANDARD)
      [[ "$repo_env" == "AWS" || "$repo_env" == "ALL" ]]
      ;;
    *)
      return 1
      ;;
  esac
}

#-----------------------------------------
# Function: create_release
# Creates a GitHub release (not a pre-release) using `gh release create`.
#
# Arguments:
#   $1 - Release tag (e.g., "10.2" or "10.2-pw")
#   $2 - Release name
#   $3 - Release notes (description)
#   $4 - Ref branch (the branch to base the release on)
#-----------------------------------------
create_release() {
  local release_tag="$1"
  local release_name="$2"
  local release_notes="$3"
  local ref_branch="$4"

  local release_url
  if release_url=$(run_gh release create "$release_tag" \
        --title "$release_name" \
        --notes "$release_notes" \
        --target "$ref_branch"); then
    echo -e "Release ${GREEN}$release_url${NC} created successfully."
    return 0
  fi

  echo -e "${RED}Error creating release.${NC}"
  return 1
}

#-----------------------------------------
# Function: process_repo
# Tags and releases a single repository directly off the selected
# development branch. No merges, no PRs, no submodule updates.
#
# Arguments:
#   $1 - Repository directory
#   $2 - Base release number (e.g., "10.2")
#   $3 - Release notes
#   $4 - Commit summary (optional; appended as a "Commit Summary" section)
#-----------------------------------------
process_repo() {
  local repo_directory="$1"
  local base_release_number="$2"
  local release_notes="$3"
  local commit_summary="$4"

  local start_time
  start_time=$(date +"%Y-%m-%d %H:%M:%S")
  local start_seconds=$SECONDS

  echo "----------------------------------------------------------"

  local return_code=0
  local repo_directory_short

  if [[ $repo_directory == "$HOME"* ]]; then
    repo_directory_short="~${repo_directory#$HOME}"
  else
    repo_directory_short="$repo_directory"
  fi

  if [[ $repo_directory == ~* ]]; then
    repo_directory="${repo_directory/#\~/$HOME}"
  fi

  if [[ ! -d "$repo_directory" ]]; then
    echo -e "${RED}Path does not exist:${NC} $repo_directory"
    repo_status["$repo_directory_short"]="$base_release_number | FAILED | 0s | (no repo)"
    repo_order+=("$repo_directory_short")
    return 1
  fi

  if ! cd "$repo_directory"; then
    echo "Cannot cd to $repo_directory"
    repo_status["$repo_directory_short"]="$base_release_number | FAILED | 0s | (cd failed)"
    repo_order+=("$repo_directory_short")
    return 1
  fi

  local RELEASE_NUMBER
  if [[ "$BRANCH_ENVIRONMENT" == "PW" ]]; then
    RELEASE_NUMBER="${base_release_number}-pw"
  else
    RELEASE_NUMBER="$base_release_number"
  fi

  echo -e "$start_time ${GREEN}Processing repository: $repo_directory (Release: $RELEASE_NUMBER)${NC}"
  echo

  echo -e "${YELLOW}Proceed with processing this repository? (C)ontinue, (S)kip, (Q)uit [default: C in 60s]:${NC}"
  read -t 60 -n 1 -s -r user_input
  echo
  user_input="${user_input:-C}"
  user_input=$(echo "$user_input" | tr '[:lower:]' '[:upper:]')

  case "$user_input" in
    Q)
      echo -e "${YELLOW}Quit requested. No release actions will be performed for this repository.${NC}"
      repo_status["$repo_directory_short"]="$RELEASE_NUMBER | QUIT | 0s | -"
      repo_order+=("$repo_directory_short")
      GLOBAL_RETURN_CODE=2
      return 2
      ;;
    S)
      echo -e "${YELLOW}Skipping this repository.${NC}"
      repo_status["$repo_directory_short"]="$RELEASE_NUMBER | SKIPPED | 0s | -"
      repo_order+=("$repo_directory_short")
      return 0
      ;;
    C|*)
      echo -e "${GREEN}Continuing with $repo_directory...${NC}"
      ;;
  esac

  local repo_remote
  repo_remote=$(git remote get-url origin)
  local REPO_PROJECT
  REPO_PROJECT=$(clean_and_encode_project "$repo_remote")
  echo "Remote URL: $repo_remote"

  if ! run_gh repo view "$REPO_PROJECT" >/dev/null 2>&1; then
    echo -e "${RED}gh cannot determine repository context in $repo_directory. Is this a GitHub repo and are you authenticated?${NC}"
    repo_status["$repo_directory_short"]="$RELEASE_NUMBER | FAILED | 0s | (gh auth)"
    repo_order+=("$repo_directory_short")
    return 1
  fi

  # Fetch remote tags and refuse to clobber an existing one.
  local remote_tags
  remote_tags=$(git ls-remote --tags origin | awk '{print $2}' | sed 's#refs/tags/##')
  if echo "$remote_tags" | grep -Fxq "$RELEASE_NUMBER"; then
    echo -e "${RED}Tag '$RELEASE_NUMBER' already exists in the remote repository. Skipping.${NC}"
    repo_status["$repo_directory_short"]="$RELEASE_NUMBER | FAILED | 0s | (tag exists)"
    repo_order+=("$repo_directory_short")
    return 1
  fi

  echo -e "Pulling latest updates for branch ${GREEN}${DEVELOPMENT_BRANCH}${NC}..."
  if ! git checkout --quiet "$DEVELOPMENT_BRANCH" || ! git pull --quiet --ff-only; then
    echo -e "${RED}Unable to update branch $DEVELOPMENT_BRANCH.${NC}"
    repo_status["$repo_directory_short"]="$RELEASE_NUMBER | FAILED | 0s | (pull failed)"
    repo_order+=("$repo_directory_short")
    return 1
  fi

  local final_release_notes="$release_notes"
  if [ -n "$commit_summary" ]; then
    final_release_notes="${final_release_notes}

Commit Summary

${commit_summary}"
  fi

  echo -e "${GREEN}Creating GitHub release for $REPO_PROJECT $RELEASE_NUMBER...${NC}"
  if ! create_release "$RELEASE_NUMBER" "Release $RELEASE_NUMBER" "$final_release_notes" "$DEVELOPMENT_BRANCH"; then
    echo -e "${RED}Error: GitHub release creation for $REPO_PROJECT $RELEASE_NUMBER failed.${NC}"
    repo_status["$repo_directory_short"]="$RELEASE_NUMBER | FAILED | 0s | (release failed)"
    repo_order+=("$repo_directory_short")
    return_code=1
  fi

  # --- OWP branch: create ngwpc-<release>[-pw] from the release tag's exact
  # commit (not the development branch HEAD, which may have moved on). Only
  # runs when -o/--create-owp-branch was passed, and only after a successful
  # release, so a failure here never rolls back the release itself.
  if [ "$CREATE_OWP_BRANCH" = true ] && [ "$return_code" -eq 0 ]; then
    local owp_branch="ngwpc-${base_release_number}"
    if [[ "$BRANCH_ENVIRONMENT" == "PW" ]]; then
      owp_branch+="-pw"
    fi

    echo -e "${GREEN}Creating OWP branch $owp_branch from release tag $RELEASE_NUMBER...${NC}"

    if ! git fetch --quiet origin "refs/tags/${RELEASE_NUMBER}:refs/tags/${RELEASE_NUMBER}"; then
      echo -e "${RED}Unable to fetch tag $RELEASE_NUMBER to create $owp_branch.${NC}"
      return_code=1
    elif git ls-remote --heads origin "$owp_branch" | grep -q "$owp_branch"; then
      echo -e "${RED}Branch '$owp_branch' already exists on origin. Skipping OWP branch creation.${NC}"
      return_code=1
    else
      git branch --quiet -D "$owp_branch" >/dev/null 2>&1 || true
      if ! git checkout --quiet -b "$owp_branch" "refs/tags/${RELEASE_NUMBER}"; then
        echo -e "${RED}Unable to create branch $owp_branch from tag $RELEASE_NUMBER.${NC}"
        return_code=1
      elif ! git_push --set-upstream origin "$owp_branch"; then
        echo -e "${RED}Failed to push $owp_branch.${NC}"
        return_code=1
      else
        echo -e "${GREEN}Created and pushed $owp_branch from tag $RELEASE_NUMBER.${NC}"
      fi
      git checkout --quiet "$DEVELOPMENT_BRANCH" >/dev/null 2>&1 || true
    fi
  fi

  local latest_commit_hash
  latest_commit_hash=$(git rev-parse HEAD 2>/dev/null || echo "(unavailable)")
  local elapsed_seconds=$(( SECONDS - start_seconds ))
  local status="SUCCESS"
  [ "$return_code" -ne 0 ] && status="FAILED"
  repo_status["$repo_directory_short"]="$RELEASE_NUMBER | $status | ${elapsed_seconds}s | $latest_commit_hash"
  repo_order+=("$repo_directory_short")

  local end_time
  end_time=$(date +"%Y-%m-%d %H:%M:%S")
  echo -e "$end_time ${GREEN}Finished processing: $REPO_PROJECT ($repo_directory_short)${NC} (Elapsed time: $elapsed_seconds seconds)"

  if [ "$return_code" -ne 0 ]; then
    GLOBAL_RETURN_CODE=$return_code
  fi

  return "$return_code"
}

#-----------------------------------------
# Function: print_summary
#-----------------------------------------
print_summary() {
  local longest_repo_name=0
  local total_elapsed_seconds=$(( SECONDS - ${total_seconds:-$SECONDS} ))

  for repo in "${repo_order[@]}"; do
    if (( ${#repo} > longest_repo_name )); then
      longest_repo_name=${#repo}
    fi
  done

  local repo_column_width=$((longest_repo_name + 2))
  local release_column_width=15
  local status_column_width=10
  local time_column_width=6
  local commit_column_width=40
  local total_width=$((repo_column_width + release_column_width + status_column_width + time_column_width + commit_column_width + 13))

  local summary_file="${SCRIPT_DIR}/release_summary_direct.txt"

  printf "\n%-${repo_column_width}s | %-${release_column_width}s | %-${status_column_width}s | %-${time_column_width}s | %-${commit_column_width}s\n" \
    "Repository" "Release" "Status" "Time" "Commit Hash" | tee "$summary_file"
  printf -- "%-${total_width}s\n" | tr ' ' '-' | tee -a "$summary_file"

  for repo in "${repo_order[@]}"; do
    IFS='|' read -r release status time commit_hash <<< "${repo_status[$repo]}"
    printf "%-${repo_column_width}s | %-15s | %-10s | %-6s | %-40s\n" \
      "$repo" "$release" "$status" "$time" "$commit_hash" | tee -a "$summary_file"
  done

  printf -- "%-${total_width}s\n" | tr ' ' '-' | tee -a "$summary_file"
  echo "All repositories processed (Total elapsed time: ${total_elapsed_seconds} seconds)." | tee -a "$summary_file"

  echo -e "${GREEN}Summary saved to: ${summary_file}${NC}"
}

#-----------------------------------------
# Function: main
#-----------------------------------------
main() {
  total_seconds=$SECONDS
  SCRIPT_DIR="$(pwd)"

  json_file="createReleaseConfig.json"
  CREATE_OWP_BRANCH=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -c|--config)
        [[ $# -ge 2 ]] || { echo -e "${RED}Missing value for $1.${NC}"; exit 1; }
        json_file="$2"
        shift 2
        ;;
      -e|--environment)
        [[ $# -ge 2 ]] || { echo -e "${RED}Missing value for $1.${NC}"; exit 1; }
        BRANCH_ENVIRONMENT="$2"
        shift 2
        ;;
      -o|--create-owp-branch)
        CREATE_OWP_BRANCH=true
        shift 1
        ;;
      -v|--verbose)
        DEBUG_GH=true
        shift 1
        ;;
      -h|--help|?)
        usage
        ;;
      --)
        shift
        break
        ;;
      -*)
        echo -e "${RED}Unknown option: $1${NC}"
        echo
        usage 1
        ;;
      *)
        echo -e "${RED}Unexpected argument: $1${NC}"
        echo
        usage 1
        ;;
    esac
  done

  LOGFILE="createOfficialReleaseDirect_$(date +%Y%m%d_%H%M%S).log"
  exec > >(tee >(sed -r "s/\x1B\[[0-9;]*[mK]//g" >> "$LOGFILE")) 2>&1
  echo "All output will be logged to: $LOGFILE"

  if ! command -v git >/dev/null 2>&1; then
    echo -e "${RED}Required git command missing. Ensure git is installed.${NC}"
    exit 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo -e "${RED}Required jq command missing. Ensure jq installed.${NC}"
    exit 1
  fi
  if ! command -v gh >/dev/null 2>&1; then
    echo -e "${RED}The GitHub CLI (gh) is not installed. Please install and run 'gh auth login'.${NC}"
    exit 1
  fi
  if ! run_gh auth status; then
    echo -e "${RED}GitHub CLI authentication is not valid. Run 'gh auth login' and try again.${NC}"
    exit 1
  fi

  if [ ! -f "$json_file" ]; then
    echo -e "${RED}JSON file $json_file not found.${NC}"
    echo
    usage 1
  fi

  if ! jq empty "$json_file" >/dev/null 2>&1; then
    echo -e "${RED}Error: JSON file '$json_file' is invalid and could not be parsed.${NC}"
    exit 1
  fi
  if [[ "$(jq -r 'type' "$json_file")" != "array" ]]; then
    echo -e "${RED}Error: JSON configuration must contain a top-level array.${NC}"
    exit 1
  fi

  # Validate the optional per-repo "env" field: must be PW, AWS, ALL, or absent.
  validation_repo_count=$(jq length "$json_file")
  for (( vi=0; vi<validation_repo_count; vi++ )); do
    repo_env_check=$(jq -r ".[$vi].env // \"ALL\"" "$json_file" | tr '[:lower:]' '[:upper:]')
    case "$repo_env_check" in
      PW|AWS|ALL) ;;
      *)
        bad_repo_dir=$(jq -r ".[$vi].repo_directory" "$json_file")
        echo -e "${RED}Error: invalid \"env\" value '$repo_env_check' for repo_directory '$bad_repo_dir' (entry $vi). Must be PW, AWS, or ALL.${NC}"
        exit 1
        ;;
    esac
  done

  BRANCH_ENVIRONMENT=$(echo "$BRANCH_ENVIRONMENT" | tr '[:lower:]' '[:upper:]')
  case "$BRANCH_ENVIRONMENT" in
    DEFAULT|STANDARD|AWS)
      BRANCH_ENVIRONMENT="STANDARD"
      DEVELOPMENT_BRANCH="development"
      ;;
    PW|PARALLEL-WORKS|PARALLEL_WORKS)
      BRANCH_ENVIRONMENT="PW"
      DEVELOPMENT_BRANCH="development-pw"
      ;;
    *)
      echo -e "${RED}Invalid environment '$BRANCH_ENVIRONMENT'. Use STANDARD or PW.${NC}"
      exit 1
      ;;
  esac

  echo "Branch environment: $BRANCH_ENVIRONMENT"
  echo "  Development branch: $DEVELOPMENT_BRANCH"
  echo -e "${YELLOW}This will tag and create an OFFICIAL GitHub release directly off $DEVELOPMENT_BRANCH.${NC}"
  echo -e "${YELLOW}No branches are merged, no PRs are created, and submodule pointers are NOT updated.${NC}"
  if [ "$CREATE_OWP_BRANCH" = true ]; then
    echo -e "${YELLOW}After each successful release, an OWP branch (ngwpc-<release>$( [[ "$BRANCH_ENVIRONMENT" == "PW" ]] && echo -pw )) will also be created and pushed from the release tag.${NC}"
  fi
  echo

  echo -e "${GREEN}Reading from $json_file${NC}"
  echo

  json_data=$(cat "$json_file")
  repo_count=$(echo "$json_data" | jq length)

  echo -e "${GREEN}The following repositories will be processed:${NC}"
  for (( i=0; i<repo_count; i++ )); do
    repo_directory=$(echo "$json_data" | jq -r ".[$i].repo_directory")
    release=$(echo "$json_data" | jq -r ".[$i].release")
    skip=$(echo "$json_data" | jq -r ".[$i].skip // false")
    repo_env=$(echo "$json_data" | jq -r ".[$i].env // \"ALL\"" | tr '[:lower:]' '[:upper:]')

    display_dir="$repo_directory"
    resolved_dir="$repo_directory"
    if [[ $resolved_dir == ~* ]]; then
      resolved_dir="${resolved_dir/#\~/$HOME}"
    fi

    exists_note=""
    if [[ ! -d "$resolved_dir" ]]; then
      exists_note=" ${RED}(missing)${NC}"
    fi

    if [ "$skip" = "true" ]; then
      echo -e "${YELLOW}Repo: $display_dir (Release: $release) (skipping)${NC}${exists_note}"
    elif ! repo_env_applies "$repo_env"; then
      echo -e "${YELLOW}Repo: $display_dir (Release: $release) (skipping: env=$repo_env doesn't apply under -e $BRANCH_ENVIRONMENT)${NC}${exists_note}"
    else
      echo -e "${GREEN}Repo: $display_dir (Release: $release)${NC}${exists_note}"
    fi
  done

  echo
  echo -n "Proceed with processing these repositories? (Y/N): "
  read -r confirm
  confirm=$(echo "$confirm" | tr '[:lower:]' '[:upper:]')
  if [ "$confirm" != "Y" ]; then
    echo "Aborting."
    exit 0
  fi

  declare -A repo_status
  repo_order=()
  GLOBAL_RETURN_CODE=0

  for (( i=0; i<repo_count; i++ )); do
    repo_directory=$(echo "$json_data" | jq -r ".[$i].repo_directory")
    release=$(echo "$json_data" | jq -r ".[$i].release")
    release_notes=$(echo "$json_data" | jq -r ".[$i].release_notes // \"\"")
    commit_summary=$(echo "$json_data" | jq -r ".[$i].commit_summary // \"\"")
    skip=$(echo "$json_data" | jq -r ".[$i].skip // false")
    repo_env=$(echo "$json_data" | jq -r ".[$i].env // \"ALL\"" | tr '[:lower:]' '[:upper:]')

    if [[ $repo_directory == ~* ]]; then
      repo_directory="${repo_directory/#\~/$HOME}"
    fi

    if [ "$skip" = "true" ]; then
      echo -e "${YELLOW}Skipping repository: $repo_directory (Release: $release)${NC}"
      continue
    fi

    if ! repo_env_applies "$repo_env"; then
      echo -e "${YELLOW}Skipping repository: $repo_directory (Release: $release) — env=$repo_env doesn't apply under -e $BRANCH_ENVIRONMENT${NC}"
      continue
    fi

    process_repo "$repo_directory" "$release" "$release_notes" "$commit_summary"

    if [ "${GLOBAL_RETURN_CODE:-0}" -eq 2 ]; then
      echo "User chose to quit. Exiting script."
      break
    fi
  done

  print_summary
  exit "${GLOBAL_RETURN_CODE:-0}"
}

main "$@"
