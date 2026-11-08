# Project subscription. Credentials come from the environment (ARM_USE_OIDC, ARM_CLIENT_ID, ARM_TENANT_ID).
provider "azurerm" {
  subscription_id = local.raw.subscription_id

  # azurerm 5.x registers nothing by default: register exactly what the catalog lists.
  resource_provider_registrations = "none"
  resource_providers_to_register  = var.register_resource_providers ? local.catalog.resource_providers : []

  features {}
}

# Hub subscription, only for the hub side of the peering. Without hub it points to the project subscription.
provider "azurerm" {
  alias           = "hub"
  subscription_id = local.hub == null ? local.raw.subscription_id : split("/", local.hub.virtual_network_id)[2]

  resource_provider_registrations = "none"

  features {}
}

provider "azuread" {}
