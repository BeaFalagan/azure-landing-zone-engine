provider "azurerm" {
  subscription_id                 = "00000000-0000-0000-0000-000000000000"
  resource_provider_registrations = "none"
  features {}
}

provider "azuread" {}

module "resource_group_rbac" {
  source = "../.."

  resource_group_name = "rg-pga-billing-dev-weu"
  location            = "westeurope"
  subscription_id     = "00000000-0000-0000-0000-000000000000"
  tags                = { cost_center = "ES0009" }

  role_definition_ids = {
    "Reader"      = "acdd72a7-3385-48ef-bd42-f606fba81ae7"
    "Contributor" = "b24988ac-6180-42a0-ab88-20f7382dd24c"
  }

  groups = {
    readers = {
      display_name = "sg-az-pga-billing-dev-readers"
      roles        = ["Reader"]
    }
    developers = {
      display_name = "sg-az-pga-billing-dev-developers"
      roles        = ["Contributor"]
      members      = ["ana@example.com"]
    }
  }
}
