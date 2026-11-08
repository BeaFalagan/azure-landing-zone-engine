provider "azurerm" {
  subscription_id = var.subscription_id

  # azurerm 5.x registers no resource provider by default: list the ones this root needs.
  resource_provider_registrations = "none"
  resource_providers_to_register  = ["Microsoft.ManagedIdentity", "Microsoft.Storage"]

  # Shared keys are disabled on the state account: use Entra ID for the data plane too.
  storage_use_azuread = true

  features {}
}

provider "azuread" {}
