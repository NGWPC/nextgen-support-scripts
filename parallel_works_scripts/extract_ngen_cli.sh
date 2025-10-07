#!/usr/bin/env bash
set -Eeuo pipefail

# --- debug mode: NGEN_DEBUG=1 ngen ...
if [[ -n "${NGEN_DEBUG:-}" ]]; then
  export SINGULARITY_MESSAGELEVEL=5   # noisy singularity logs
  PS4='+ ${BASH_SOURCE##*/}:${LINENO}: '
  set -x
fi
trap 'rc=$?; echo "ngen wrapper: ERROR at line ${LINENO} running: ${BASH_COMMAND} (rc=${rc})" >&2' ERR

NGEN_CONTAINER="${NGEN_CONTAINER:-/ngencerf-app/singularity/ngen.sif}"
NGEN_BINARY="${NGEN_BINARY:-/ngen-app/ngen/cmake_build/ngen}"
command -v singularity >/dev/null || { echo "error: singularity not found in PATH" >&2; exit 127; }
[ -r "${NGEN_CONTAINER}" ] || { echo "error: sif not found or unreadable: ${NGEN_CONTAINER}" >&2; exit 126; }
if ! singularity exec "${NGEN_CONTAINER}" test -r "${NGEN_BINARY}"; then
  echo "error: ngen binary not found/readable in image: ${NGEN_BINARY}" >&2
  exit 126
fi

bind_args=(--bind "$PWD:$PWD" --pwd "$PWD")
declare -A _seen=()

add_bind() {
  local host="$1" cont="${2:-$1}"
  [[ -z "$host" ]] && return 0
  if [[ -d "$host" && -z "${_seen[$host]:-}" ]]; then
    bind_args+=(--bind "$host:$cont"); _seen[$host]=1
    echo "ngen wrapper: add bind --bind ${host}:${cont}" >&2
  fi
}

is_path_arg() {
  local a="$1"
  [[ -z "$a" || "$a" == "all" ]] && return 1
  [[ "$a" == -* ]] && return 1
  if [[ "$a" == *,* && "$a" != *"/"* ]]; then return 1; fi
  [[ "$a" == *"/"* ]] && return 0
  local abs="$PWD/$a"; local parent; parent=$(dirname -- "$abs")
  [[ -d "$parent" ]] && return 0
  return 1
}

missing_parents=()
for arg in "$@"; do
  if is_path_arg "$arg"; then
    if [[ "$arg" = /* ]]; then parent=$(dirname -- "$arg"); else parent=$(dirname -- "$PWD/$arg"); fi
    [[ -d "$parent" ]] && add_bind "$parent" || missing_parents+=("$parent (from: $arg)")
  fi
done

if (( ${#missing_parents[@]} > 0 )); then
  echo "warning: not binding these host directories (do not exist):" >&2
  for m in "${missing_parents[@]}"; do echo "  - $m" >&2; done
fi

# ---- verbose summary ----
{
  echo "ngen wrapper: working dir: $PWD"
  echo "ngen wrapper: binds to apply:"

  i=0
  n=${#bind_args[@]}
  while (( i < n )); do
    key=${bind_args[i]}
    val=${bind_args[i+1]:-}
    if [[ "$key" == "--bind" ]]; then
      echo "  --bind $val"
      : $(( i += 2 ))   # safe increment (always exit 0)
    elif [[ "$key" == "--pwd" ]]; then
      echo "  --pwd $val"
      : $(( i += 2 ))
    else
      : $(( i += 1 ))
    fi
  done

  printf 'ngen wrapper: exec command:\n+ singularity exec'
  for a in "${bind_args[@]}"; do printf ' %q' "$a"; done
  printf ' %q %q' "${NGEN_CONTAINER}" "$NGEN_BINARY"
  for a in "$@"; do printf ' %q' "$a"; done
  printf '\n'
} >&2

# run ngen command inside singularity container
exec singularity exec "${bind_args[@]}" "${NGEN_CONTAINER}" "$NGEN_BINARY" "$@"
