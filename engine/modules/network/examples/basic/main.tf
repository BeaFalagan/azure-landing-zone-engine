provider "azurerm" {
  subscription_id                 = "00000000-0000-0000-0000-000000000000"
  resource_provider_registrations = "none"
  features {}
}

# Hub subscription (connectivity), used only for the hub side of the peering.
provider "azurerm" {
  alias                           = "hub"
  subscription_id                 = "22222222-2222-2222-2222-222222222222"
  resource_provider_registrations = "none"
  features {}
}

module "network" {
  source = "../.."

  providers = {
    azurerm     = azurerm
    azurerm.hub = azurerm.hub
  }

  name                = "vnet-pga-billing-dev-weu"
  resource_group_name = "rg-pga-billing-dev-weu"
  location            = "westeurope"
  address_space       = ["10.48.48.0/20"]
  dns_servers         = ["10.0.1.4"]
  route_table_name    = "rt-pga-billing-dev-weu"

  hub = {
    virtual_network_id  = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-conn-dev-weu/providers/Microsoft.Network/virtualNetworks/vnet-hub-dev-weu"
    address_space       = ["10.0.0.0/22"]
    firewall_private_ip = "10.0.0.4"
  }

  peering_names = {
    to_hub   = "peer-pga-billing-dev-to-hub"
    from_hub = "peer-hub-to-pga-billing-dev"
  }

  subnets = {
    app = {
      name              = "snet-app"
      nsg_name          = "nsg-pga-billing-dev-weu-app"
      prefix            = "10.48.48.0/24"
      service_endpoints = ["Microsoft.Storage"]
      nsg_rules = [
        { name = "allow-https-from-hub", direction = "inbound", access = "allow", protocol = "tcp", source = "@hub", ports = ["443"] },
      ]
    }
    db = {
      name     = "snet-db"
      nsg_name = "nsg-pga-billing-dev-weu-db"
      prefix   = "10.48.49.0/24"
      delegation = {
        service = "Microsoft.DBforPostgreSQL/flexibleServers"
        actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
      }
    }
  }

  tags = { cost_center = "ES0009" }
}
