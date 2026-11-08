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

  # One state per project and environment. The pipeline passes the rest with -backend-config:
  # subscription_id, resource_group_name, storage_account_name, container_name and
  # key = "<business_unit>/<project>/<environment>.tfstate" (see docs/adr/0002).
  backend "azurerm" {
    use_azuread_auth = true
  }
}
