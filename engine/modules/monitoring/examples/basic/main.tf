provider "azurerm" {
  subscription_id                 = "00000000-0000-0000-0000-000000000000"
  resource_provider_registrations = "none"
  features {}
}

module "monitoring" {
  source = "../.."

  subscription_id            = "00000000-0000-0000-0000-000000000000"
  log_analytics_workspace_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-mgmt-pro-weu/providers/Microsoft.OperationalInsights/workspaces/log-mgmt-pro-weu"

  resources = {
    vnet = {
      resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-pga-billing-dev-weu/providers/Microsoft.Network/virtualNetworks/vnet-pga-billing-dev-weu"
    }
    nsg-app = {
      resource_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-pga-billing-dev-weu/providers/Microsoft.Network/networkSecurityGroups/nsg-pga-billing-dev-weu-app"
      metric_categories = []
    }
  }
}
