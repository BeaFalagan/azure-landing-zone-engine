#!/usr/bin/env bash
# shellcheck disable=SC2016 # backticks in strings are Markdown, not command substitution
# Run the engine for one project file in CI. Always called from the repository root.
#
#   run-engine.sh prepare FILE   check out engine/v<engine_version> into .engine/ (git worktree) and
#                                validate FILE with the schema of that version
#   run-engine.sh plan FILE      terraform init + plan; writes plan.txt and changes.json
#   run-engine.sh apply FILE     plan again, compare with $LZ_APPROVED_CHANGES and apply
#
# Every mode writes $LZ_OUT/report.md (Markdown for the pull request comment and job summary).
# Environment: LZ_OUT, LZ_LOCK (true|false), TFSTATE_SUBSCRIPTION, TFSTATE_RESOURCE_GROUP,
# TFSTATE_ACCOUNT, TFSTATE_CONTAINER, the ARM_* OIDC variables and, for apply, LZ_APPROVED_CHANGES.
set -euo pipefail

mode="${1:?mode: prepare|plan|apply}"
file="${2:?project file}"
out="${LZ_OUT:?LZ_OUT not set}"
engine=".engine"
root="${engine}/engine/root"
plan_limit=55000

mkdir -p "${out}"
report="${out}/report.md"
log="${out}/${mode}.log"
key="${file#projects/}"
key="${key%.yaml}.tfstate"

# Report shown if the job dies before writing a better one.
printf '### ❌ `%s`\n\nThe pipeline failed before running the engine. See the job logs.\n' "${file}" > "${report}"

fail() {
  local message="$1" details="${2:-}"
  {
    printf '### ❌ `%s`\n\n%s\n' "${file}" "${message}"
    if [[ -n "${details}" && -s "${details}" ]]; then
      printf '\n```\n'
      sed -e 's/\x1b\[[0-9;]*m//g' "${details}" | grep -v '^[[:space:]]*$' | tail -n 60
      printf '```\n'
    fi
  } > "${report}"
  echo "::error file=${file}::${message}"
  exit 1
}

# Run a command, keep its output in the log and show it; fail with a readable message.
step() {
  local title="$1"
  shift
  if ! "$@" > "${log}" 2>&1; then
    cat "${log}"
    fail "${title}" "${log}"
  fi
  cat "${log}"
}

version() {
  python3 -c 'import sys, yaml; d = yaml.safe_load(open(sys.argv[1])); print(d.get("engine_version", "") if isinstance(d, dict) else "")' "${file}" 2>/dev/null || true
}

prepare() {
  local ver tag
  ver="$(version)"
  if [[ ! "${ver}" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    step "The file does not match the engine schema (engine_version is missing or invalid)." \
      python3 scripts/validate_project.py "${file}"
    fail "engine_version is missing or invalid."
  fi
  tag="engine/v${ver}"
  if ! git rev-parse -q --verify "refs/tags/${tag}^{commit}" > /dev/null; then
    fail "engine_version \`${ver}\` is not a published engine version. Published: $(git tag --list 'engine/v*' --sort=-v:refname | head -n 5 | sed 's|engine/v||' | paste -sd, - | sed 's/,/, /g')."
  fi
  git worktree remove --force "${engine}" 2> /dev/null || true
  step "Cannot check out ${tag}." git worktree add --detach "${engine}" "${tag}"
  step "The file does not match the schema of engine ${ver}. Fix the fields listed below." \
    python3 scripts/validate_project.py --schema "${engine}/engine/schema/project.schema.json" "${file}"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "terraform_version=$(tr -d '[:space:]' < "${engine}/.terraform-version")" >> "${GITHUB_OUTPUT}"
  fi
  printf '### ⏳ `%s`\n\nSchema of engine %s: OK. Running Terraform...\n' "${file}" "${ver}" > "${report}"
}

plan() {
  local lock=()
  [[ "${LZ_LOCK:-true}" == "false" ]] && lock=(-lock=false)

  step "terraform init failed (state backend or providers)." \
    terraform -chdir="${root}" init -input=false -no-color -lockfile=readonly \
      -backend-config="subscription_id=${TFSTATE_SUBSCRIPTION}" \
      -backend-config="resource_group_name=${TFSTATE_RESOURCE_GROUP}" \
      -backend-config="storage_account_name=${TFSTATE_ACCOUNT}" \
      -backend-config="container_name=${TFSTATE_CONTAINER}" \
      -backend-config="key=${key}"

  step "terraform plan failed. The error below names the field to fix." \
    terraform -chdir="${root}" plan -input=false -no-color ${lock[@]+"${lock[@]}"} -out=tfplan \
      -var="project_file=${PWD}/${file}" \
      -var="platform_file=${PWD}/projects/_platform/platform.yaml"

  terraform -chdir="${root}" show -no-color tfplan > "${out}/plan.txt"
  terraform -chdir="${root}" show -json tfplan | jq -S '
    [.resource_changes[]? | select(.change.actions != ["no-op"]) | {address, actions: .change.actions}]
    | sort_by(.address)' > "${out}/changes.json"

  local add change destroy risky
  add=$(jq '[.[] | select(.actions | index("create"))] | length' "${out}/changes.json")
  change=$(jq '[.[] | select(.actions == ["update"])] | length' "${out}/changes.json")
  destroy=$(jq '[.[] | select(.actions | index("delete"))] | length' "${out}/changes.json")
  risky=$(jq -r '.[] | select(.actions | index("delete")) | "- `\(.address)` (\(.actions | join(" + ")))"' "${out}/changes.json")

  {
    printf '### ✅ `%s` · engine %s\n\n' "${file}" "$(version)"
    if [[ "$(jq length "${out}/changes.json")" == "0" ]]; then
      printf '**No changes.** Azure already matches the file.\n'
    else
      printf '**%s to add, %s to change, %s to destroy.**\n' "${add}" "${change}" "${destroy}"
    fi
    if [[ -n "${risky}" ]]; then
      printf '\n> [!WARNING]\n> This plan destroys or replaces resources. Check that it is intended before approving:\n\n%s\n' "${risky}"
    fi
    printf '\n<details><summary>Full plan</summary>\n\n```hcl\n'
    head -c "${plan_limit}" "${out}/plan.txt"
    if [[ $(wc -c < "${out}/plan.txt") -gt ${plan_limit} ]]; then
      printf '\n... (truncated: the complete plan is in the job artifact)\n'
    fi
    printf '```\n\n</details>\n'
  } > "${report}"
}

apply() {
  plan
  if [[ -n "${LZ_APPROVED_CHANGES:-}" ]] && ! diff -u --label "approved plan" --label "new plan" "${LZ_APPROVED_CHANGES}" "${out}/changes.json" > "${out}/drift.diff"; then
    fail "The plan changed after it was shown for approval (another change reached main or Azure changed). Nothing was applied: re-run the workflow to get a new plan." "${out}/drift.diff"
  fi
  step "terraform apply failed. Part of the plan may have been applied: fix the cause and re-run the workflow." \
    terraform -chdir="${root}" apply -input=false -no-color tfplan
  sed -i.bak '1s/^### ✅/### 🚀 Applied:/' "${report}" && rm -f "${report}.bak"
}

case "${mode}" in
  prepare) prepare ;;
  plan) plan ;;
  apply) apply ;;
  *) fail "unknown mode ${mode}" ;;
esac
