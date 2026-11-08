#!/usr/bin/env bash
# Run `terraform test` (mocked providers, no Azure access) in every directory that has tests/.
set -euo pipefail

cd "$(dirname "$0")/.."

status=0
while IFS= read -r dir; do
  echo "==> ${dir}"
  terraform -chdir="${dir}" init -backend=false -input=false >/dev/null
  terraform -chdir="${dir}" test || status=1
done < <(find . -path '*/.terraform' -prune -o -name '*.tftest.hcl' -print | sed 's|/[^/]*/[^/]*$||' | sort -u)

exit "${status}"
