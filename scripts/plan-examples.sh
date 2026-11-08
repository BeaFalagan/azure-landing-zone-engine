#!/usr/bin/env bash
# Plan every example project with mocked providers and print each plan (nothing reaches Azure).
# A run block is generated per engine/examples/projects/**/*.yaml, so new examples are picked up
# without editing any test file. Specific assertions live in engine/root/tests/root.tftest.hcl.
set -euo pipefail

cd "$(dirname "$0")/../engine/root"

dir=".examples-test"
rm -rf "${dir}"
mkdir "${dir}"
trap 'rm -rf "${dir}"' EXIT

{
  cat <<'HCL'
mock_provider "azurerm" {}

mock_provider "azurerm" {
  alias = "hub"
}

mock_provider "azuread" {
  mock_data "azuread_user" {
    defaults = {
      object_id = "55555555-5555-5555-5555-555555555555"
    }
  }
}

variables {
  platform_file = "../examples/platform.yaml"
}
HCL
  find ../examples/projects -name '*.yaml' | sort | while read -r file; do
    name="$(echo "${file#../examples/projects/}" | sed 's/\.yaml$//' | tr '/' '_')"
    printf '\nrun "%s" {\n  command = plan\n\n  variables {\n    project_file = "%s"\n  }\n}\n' "${name}" "${file}"
  done
} > "${dir}/examples.tftest.hcl"

terraform init -backend=false -input=false > /dev/null
terraform test -test-directory="${dir}" -verbose
