#!/usr/bin/env bash
set -euo pipefail

HF_BUCKET="${HF_BUCKET:-ngwpc-hydrofabric}"
FORCING_BUCKET="${FORCING_BUCKET:-ngwpc-forcing}"
COASTAL_BUCKET="${COASTAL_BUCKET:-ngwpc-coastal}"

HF_MOUNT_DIR="${HF_MOUNT_DIR:-/ngwpc-hydrofabric}"
FORCING_MOUNT_DIR="${FORCING_MOUNT_DIR:-/ngwpc-forcing}"
COASTAL_MOUNT_DIR="${COASTAL_MOUNT_DIR:-/ngwpc-coastal}"

AWS_SHARED_CREDENTIALS_FILE="${AWS_SHARED_CREDENTIALS_FILE:-/etc/aws_credentials}"

# prompt for variables
prompt() {
  # usage: prompt VAR "message"
  local var="$1" msg="$2" silent="${3:-}"
  if [ -z "${!var:-}" ]; then
    if [ "$silent" = "silent" ]; then
      read -r -s -p "$msg: " "$var"; echo
    else
      read -r -p "$msg: " "$var"
    fi
    export "$var"
  fi
}

# s3 buckets
prompt HF_BUCKET       "hydrofabric S3 bucket name"
prompt FORCING_BUCKET  "forcing S3 bucket name"
prompt COASTAL_BUCKET  "coastal S3 bucket name"

# mount paths
prompt HF_MOUNT_DIR       "local mount dir for hydrofabric (e.g., /ngwpc-hydrofabric)"
prompt FORCING_MOUNT_DIR  "local mount dir for forcing (e.g., /ngwpc-forcing)"
prompt COASTAL_MOUNT_DIR  "local mount dir for coastal (e.g., /ngwpc-coastal)"

# create aws creds file
echo "aws creds will be written to: $AWS_SHARED_CREDENTIALS_FILE"
prompt AWS_ACCESS_KEY_ID     "AWS Access Key ID"
prompt AWS_SECRET_ACCESS_KEY "AWS Secret Access Key" "silent"

# write to aws creds file
sudo touch "$AWS_SHARED_CREDENTIALS_FILE"
sudo chmod 600 "$AWS_SHARED_CREDENTIALS_FILE"
sudo tee "$AWS_SHARED_CREDENTIALS_FILE" >/dev/null <<EOF
[default]
aws_access_key_id=${AWS_ACCESS_KEY_ID}
aws_secret_access_key=${AWS_SECRET_ACCESS_KEY}
EOF
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY

# check if mount-s3 is installed
if ! command -v mount-s3 >/dev/null 2>&1; then
  echo "error: mount-s3 not found. install Mountpoint for Amazon S3 first." >&2
  exit 1
fi

# create mountpoints
sudo mkdir -p "$HF_MOUNT_DIR" "$FORCING_MOUNT_DIR" "$COASTAL_MOUNT_DIR"

# function to mount s3 bucket
mount_pair() {
  local bucket="$1" target="$2"
  # skip if target already mounted
  if findmnt -rn -T "$target" >/dev/null 2>&1; then
    echo "skip: $target already mounted"
    return 0
  fi
  echo "mounting s3://$bucket -> $target"
  sudo AWS_SHARED_CREDENTIALS_FILE="$AWS_SHARED_CREDENTIALS_FILE" \
    mount-s3 --allow-other --read-only "$bucket" "$target"
}

# mount s3 buckets
mount_pair "$HF_BUCKET"      "$HF_MOUNT_DIR"
mount_pair "$FORCING_BUCKET" "$FORCING_MOUNT_DIR"
mount_pair "$COASTAL_BUCKET" "$COASTAL_MOUNT_DIR"

# verify mounts
verify_mount() {
  local target="$1"
  if findmnt -rn -T "$target" >/dev/null 2>&1; then
    echo "ok: $target is mounted"
  else
    echo "error: $target is not mounted" >&2
    return 1
  fi
}
fail=0
verify_mount "$HF_MOUNT_DIR" || fail=1
verify_mount "$FORCING_MOUNT_DIR" || fail=1
verify_mount "$COASTAL_MOUNT_DIR" || fail=1
[ "$fail" -eq 0 ] || exit 1

echo "s3 bucket mounted:"
echo "  $HF_BUCKET      -> $HF_MOUNT_DIR"
echo "  $FORCING_BUCKET -> $FORCING_MOUNT_DIR"
echo "  $COASTAL_BUCKET -> $COASTAL_MOUNT_DIR"
