terraform {
  required_version = ">= 1.17.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.12, < 6.0"
      # azurerm.hub: subscription of the hub VNet, for the hub side of the peering.
      # Pass the default provider when there is no hub.
      configuration_aliases = [azurerm.hub]
    }
  }
}
