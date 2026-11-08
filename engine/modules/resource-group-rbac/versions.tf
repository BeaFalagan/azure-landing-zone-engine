terraform {
  required_version = ">= 1.17.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.12, < 6.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 3.10, < 4.0"
    }
  }
}
