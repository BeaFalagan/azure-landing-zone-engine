#!/usr/bin/env bash
# Regenerate the multi-platform provider lock file of every Terraform root.
# Run it after changing a provider constraint and commit the resulting .terraform.lock.hcl.
set -euo pipefail

cd "$(dirname "$0")/.."

PLATFORMS=(linux_amd64 darwin_arm64 darwin_amd64 windows_amd64)
ROOTS=(bootstrap engine/root)

args=()
for platform in "${PLATFORMS[@]}"; do
  args+=("-platform=${platform}")
done

for root in "${ROOTS[@]}"; do
  echo "==> ${root}"
  terraform -chdir="${root}" init -backend=false -input=false -upgrade >/dev/null
  terraform -chdir="${root}" providers lock "${args[@]}"
done
