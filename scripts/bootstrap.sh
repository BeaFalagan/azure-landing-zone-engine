#!/usr/bin/env bash
# One-off bootstrap of the state account and the pipeline identities.
# Run by a platform administrator with `az login`; CI never runs it.
#
#   1st run: local state -> plan -> confirmation -> apply -> writes backend.hcl -> migrates the state.
#   Next runs: remote state (backend.hcl) -> plan only; apply the saved plan by hand.
set -euo pipefail

cd "$(dirname "$0")/../bootstrap"

die() { echo "ERROR: $*" >&2; exit 1; }

command -v terraform >/dev/null || die "terraform not found"
command -v az >/dev/null || die "Azure CLI not found"
az account show >/dev/null 2>&1 || die "run 'az login' first"
[[ -f terraform.tfvars ]] || die "create bootstrap/terraform.tfvars from terraform.tfvars.example"

if [[ -f backend.hcl ]]; then
  terraform init -input=false -backend-config=backend.hcl
  terraform plan -out=tfplan
  echo "Review the plan and run: terraform -chdir=bootstrap apply tfplan"
  exit 0
fi

# First run: temporary local backend (the *_override.tf file is git-ignored).
trap 'rm -f backend_override.tf' EXIT
printf 'terraform {\n  backend "local" {}\n}\n' > backend_override.tf

terraform init -input=false -reconfigure
terraform plan -out=tfplan

read -r -p "Apply this plan? Type 'yes' to continue: " answer
[[ "${answer}" == "yes" ]] || die "aborted"
terraform apply tfplan
rm -f tfplan

terraform output -raw bootstrap_backend_hcl > backend.hcl
rm -f backend_override.tf
trap - EXIT

# The state admins role assignment can take a few minutes to propagate.
for attempt in 1 2 3 4 5 6 7 8 9 10; do
  if terraform init -input=false -migrate-state -force-copy -backend-config=backend.hcl; then
    echo "State migrated. Commit bootstrap/backend.hcl (no secrets) and delete the local terraform.tfstate* files."
    exit 0
  fi
  echo "Migration failed (attempt ${attempt}/10), waiting for RBAC propagation..."
  sleep 30
done
die "could not migrate the state; check your membership in the state admins group and retry"
