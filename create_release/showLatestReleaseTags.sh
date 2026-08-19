#!/usr/bin/env bash

set -euo pipefail

DEFAULT_CONFIG="createReleaseConfig.json"
DEFAULT_RELEASE_TYPE="RC"

# Track latest tag across all scanned repos
LATEST_TAG_DATE=""
LATEST_TAG_REPO=""
LATEST_TAG_NAME=""

usage() {
    cat <<EOF
Usage:
  $(basename "$0") [config.json] [release_type]

Description:
  Scans git repositories listed in a JSON config file and prints either the
  release tag or the highest release candidate tag (-rcX), along with
  the tag creation date and associated commit hash.

  Also prints (at the end) the latest tag date found across all scanned repos.

Arguments:
  config.json     Optional. Path to JSON config file.
                  Default: ${DEFAULT_CONFIG}
  release_type    Optional. "RC" (default) or "Official".
                  RC       → use the release tag if skip is true otherwise the highest release candidate tag (-rcX)
                  Official → get the highest official release/hotfix tag that matches the configured release
                             prefix, checked for both the standard tag and its "-pw" counterpart. If both
                             exist, both are shown, comma-separated, in the Tag/Tag Date/Commit columns.

Options:
  -h, --help      Show this help message and exit.

Tag behavior:
  RC:
    skip = true    → use <release> tag
    skip = false   → use highest <release>-rc<number> tag

  Official:
    Uses the configured release as the base release and finds the highest
    matching final/hotfix tag by the last numeric component, separately for
    the standard tag and the "-pw" tag. If only one of the two exists, only
    that one is shown. If neither exists, "(not found)" is shown.

    Example:
      release       = 3.1.2.0.0
      standard tags = 3.1.2.0.0, 3.1.2.0.1, 3.1.2.0.2
      pw tags       = 3.1.2.0.0-pw
      result        = 3.1.2.0.2, 3.1.2.0.0-pw

Minimal example JSON config:

[
    {
        "repo_directory": "~/ngwpc/repositories/noah-owp-modular",
        "release": "3.1.2.0.0"
    }
]

Notes:
- 'repo_directory' supports '~' for the home directory.
- 'skip' is optional. Defaults to false when release_type is RC.
EOF
}

# Help option
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

CONFIG_FILE="${1:-$DEFAULT_CONFIG}"
RELEASE_TYPE="${2:-$DEFAULT_RELEASE_TYPE}"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "❌ Config file not found: $CONFIG_FILE"
    echo
    usage
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "❌ jq is required but not installed."
    exit 1
fi

# join_by <delim> <items...>
# Joins arguments with the given delimiter. Used to combine standard/-pw
# results into a single comma-separated cell. (Not implemented via IFS +
# "$*" — that only honors the first character of a multi-character IFS.)
join_by() {
    local delim="$1"
    shift
    local result="" item first=true
    for item in "$@"; do
        if $first; then
            result="$item"
            first=false
        else
            result="${result}${delim}${item}"
        fi
    done
    echo "$result"
}

# get_highest_official_tag <release_prefix> <suffix>
# Finds the highest matching official/hotfix tag for the given prefix
# (e.g. "3.1.2.0") whose last numeric component follows the prefix.
# <suffix> is either "" (standard tags) or "-pw" (pw tags) — only tags
# ending in that suffix (or, for "", NOT ending in "-pw") are considered.
# Prints the winning tag name, or nothing if none match.
get_highest_official_tag() {
    local prefix="$1"
    local suffix="$2"
    local prefix_count
    prefix_count=$(awk -F. '{print NF}' <<< "$prefix")

    local best_patch=-1
    local best_tag=""

    while IFS= read -r t; do
        [[ -z "$t" ]] && continue

        local core="$t"
        if [[ "$suffix" == "-pw" ]]; then
            [[ "$t" == *-pw ]] || continue
            core="${t%-pw}"
        else
            [[ "$t" == *-pw ]] && continue
        fi

        IFS='.' read -ra parts <<< "$core"
        if (( ${#parts[@]} != prefix_count + 1 )); then
            continue
        fi

        local core_prefix
        core_prefix=$(IFS=. ; echo "${parts[*]:0:prefix_count}")
        [[ "$core_prefix" == "$prefix" ]] || continue

        local patch="${parts[$prefix_count]}"
        [[ "$patch" =~ ^[0-9]+$ ]] || continue

        if (( patch > best_patch )); then
            best_patch=$patch
            best_tag="$t"
        fi
    done < <(git tag --list "${prefix}.*")

    echo "$best_tag"
}

# get_tag_date <tag>
# Prints the annotated tag date, falling back to the commit date for
# lightweight tags. Empty string if the tag can't be resolved.
get_tag_date() {
    local tag="$1"
    local d
    d="$(git for-each-ref --format='%(taggerdate:iso8601-strict)' "refs/tags/${tag}" 2>/dev/null || true)"
    if [[ -z "$d" ]]; then
        d="$(git show -s --format=%cd --date=format:'%Y-%m-%d %H:%M:%S' "$tag" 2>/dev/null || true)"
    else
        d="${d%+*}"
        d="${d%Z}"
    fi
    echo "$d"
}

# get_tag_commit <tag>
# Prints the commit hash the tag points to, or "-" if unresolvable.
get_tag_commit() {
    local tag="$1"
    local c
    c="$(git rev-list -n 1 "$tag" 2>/dev/null || true)"
    [[ -n "$c" ]] || c="-"
    echo "$c"
}

# Row separator, reused between each repo's block of line(s) instead of just
# between header and body.
ROW_SEP="$(printf "%-25s-+-%-25s-+-%-20s-+-%-40s" \
       "-------------------------" \
       "-------------------------" \
       "--------------------" \
       "----------------------------------------")"

# Table header
printf "\n%-25s | %-25s | %-20s | %-40s\n" \
       "Repository" "Tag" "Tag Date" "Commit"
printf '%s\n' "$ROW_SEP"

# IMPORTANT: Use process substitution to avoid subshell so we can print summary at the end
while IFS= read -r entry; do
    repo_dir=$(echo "$entry" | jq -r '.repo_directory')
    release=$(echo "$entry" | jq -r '.release')
    skip=$(echo "$entry" | jq -r '.skip // false')

    repo_dir="${repo_dir/#\~/$HOME}"
    repo_name=$(basename "$repo_dir")

    if [[ ! -d "$repo_dir/.git" ]]; then
        printf "%-25s | %-25s | %-20s | %-40s\n" \
               "$repo_name" "NOT A GIT REPO" "-" "-"
        printf '%s\n' "$ROW_SEP"
        continue
    fi

    pushd "$repo_dir" >/dev/null

    # Update remote refs and tags
    git fetch --all --tags --prune --quiet

    # --- Track latest tag in this repo (any tag), for end-of-run summary ---
    # iso-strict compares cleanly as a string (YYYY-MM-DDTHH:MM:SS±HH:MM)
    latest_tag_line="$(
        git for-each-ref \
            --sort=-creatordate \
            --format='%(creatordate:iso-strict)|%(refname:short)' \
            refs/tags 2>/dev/null | head -n 1 || true
    )"

    if [[ -n "$latest_tag_line" ]]; then
        repo_latest_date="${latest_tag_line%%|*}"
        repo_latest_tag="${latest_tag_line#*|}"

        if [[ -z "$LATEST_TAG_DATE" || "$repo_latest_date" > "$LATEST_TAG_DATE" ]]; then
            LATEST_TAG_DATE="$repo_latest_date"
            LATEST_TAG_REPO="$repo_name"
            LATEST_TAG_NAME="$repo_latest_tag"
        fi
    fi
    # -------------------------------------------------------------------

    # row_tags/row_dates/row_commits hold one entry per line to print for
    # this repo. Normally one line; Official mode prints one line per tag
    # found (standard and/or -pw) instead of comma-joining them.
    row_tags=()
    row_dates=()
    row_commits=()

    if [[ "$RELEASE_TYPE" == "Official" ]]; then
        # Official release behavior:
        # Treat the configured release as the base release and find the highest
        # matching final/hotfix tag by the last numeric component — separately
        # for the standard tag and the "-pw" tag. If both exist, each gets its
        # own line below the repo name.
        release_prefix="${release%.*}"

        standard_tag="$(get_highest_official_tag "$release_prefix" "")"
        pw_tag="$(get_highest_official_tag "$release_prefix" "-pw")"

        found_tags=()
        [[ -n "$standard_tag" ]] && found_tags+=("$standard_tag")
        [[ -n "$pw_tag" ]] && found_tags+=("$pw_tag")

        if (( ${#found_tags[@]} == 0 )); then
            row_tags+=("(not found)")
            row_dates+=("-")
            row_commits+=("-")
        else
            for t in "${found_tags[@]}"; do
                d="$(get_tag_date "$t")"
                [[ -n "$d" ]] || d="-"
                row_tags+=("$t")
                row_dates+=("$d")
                row_commits+=("$(get_tag_commit "$t")")
            done
        fi
    else
        # RC behavior
        tag=""
        if [[ "$skip" == "true" ]]; then
            # Final release tag
            if git rev-parse -q --verify "refs/tags/${release}" >/dev/null; then
                tag="$release"
            else
                tag="(not found)"
            fi
        else
            # Highest RC tag
            highest_rc=$(
                git tag \
                  | grep "^${release}-rc[0-9]\+$" \
                  | sed "s/^${release}-rc//" \
                  | sort -n \
                  | tail -1 \
                  || true
            )

            if [[ -n "$highest_rc" ]]; then
                tag="${release}-rc${highest_rc}"
            else
                tag="(none)"
            fi
        fi

        tag_date="-"
        commit_hash="-"
        if [[ "$tag" != "(none)" && "$tag" != "(not found)" ]]; then
            # Annotated tag date
            tag_date="$(git for-each-ref --format='%(taggerdate:iso8601-strict)' "refs/tags/${tag}" || true)"

            # Fallback for lightweight tags → commit date
            if [[ -z "$tag_date" ]]; then
                tag_date="$(git show -s --format=%cd --date=format:'%Y-%m-%d %H:%M:%S' "$tag" || true)"
            else
                # Strip timezone from annotated tag date (keep behavior you had)
                tag_date="${tag_date%+*}"
                tag_date="${tag_date%Z}"
            fi

            commit_hash="$(git rev-list -n 1 "$tag" || true)"
            [[ -n "$commit_hash" ]] || commit_hash="-"
        fi

        row_tags+=("$tag")
        row_dates+=("$tag_date")
        row_commits+=("$commit_hash")
    fi

    for (( r=0; r<${#row_tags[@]}; r++ )); do
        if (( r == 0 )); then
            printf "%-25s | %-25s | %-20s | %-40s\n" \
                   "$repo_name" "${row_tags[$r]}" "${row_dates[$r]}" "${row_commits[$r]}"
        else
            printf "%-25s | %-25s | %-20s | %-40s\n" \
                   "" "${row_tags[$r]}" "${row_dates[$r]}" "${row_commits[$r]}"
        fi
    done
    printf '%s\n' "$ROW_SEP"

    popd >/dev/null
done < <(jq -c '.[]' "$CONFIG_FILE")

# --- Print latest tag date across all scanned repos ---
printf "\nLatest tag date (across scanned repos)\n"
printf "=============================================================\n"
if [[ -n "$LATEST_TAG_DATE" ]]; then
    printf "  %s | %s | %s\n" "$LATEST_TAG_DATE" "$LATEST_TAG_REPO" "$LATEST_TAG_NAME"
else
    printf "  (no tags found in scanned repositories)\n"
fi
