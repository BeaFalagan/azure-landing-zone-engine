terraform {
  # Terraform 1.17.1 and azuread 3.10.0 verified on 2026-11-05; azurerm locked at 5.13.0 (2026-11-08, no breaking changes).
  required_version = ">= 1.17.0, < 2.0.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.12"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.10"
    }
  }

  # Partial configuration: the rest comes from -backend-config=backend.hcl (see README).
  # The first run uses local state and is migrated by scripts/bootstrap.sh.
  backend "azurerm" {
    use_azuread_auth = true
  }
}
