mock_provider "azurerm" {}

mock_provider "azurerm" {
  alias = "hub"
}

variables {
  name                = "vnet-pga-billing-dev-weu"
  resource_group_name = "rg-pga-billing-dev-weu"
  location            = "westeurope"
  address_space       = ["10.48.48.0/20"]
  route_table_name    = "rt-pga-billing-dev-weu"
  tags                = { cost_center = "ES0009" }

  hub = {
    virtual_network_id  = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-conn-dev-weu/providers/Microsoft.Network/virtualNetworks/vnet-hub-dev-weu"
    address_space       = ["10.0.0.0/22", "10.0.4.0/24"]
    firewall_private_ip = "10.0.0.4"
    use_remote_gateways = true
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
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault"]
      nsg_rules = [
        { name = "allow-https-from-hub", direction = "inbound", access = "allow", protocol = "tcp", source = "@hub", ports = ["443", "8443"] },
        { name = "allow-lb-probes", direction = "inbound", access = "allow", protocol = "any", source = "AzureLoadBalancer", priority = 4000 },
        { name = "deny-internet-out", direction = "outbound", access = "deny", protocol = "any", source = "@subnet", destination = "Internet" },
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
}

run "vnet_and_subnets" {
  command = plan

  providers = {
    azurerm     = azurerm
    azurerm.hub = azurerm.hub
  }

  assert {
    condition     = azurerm_virtual_network.this.name == "vnet-pga-billing-dev-weu" && length(azurerm_subnet.this) == 2
    error_message = "VNet and two subnets expected."
  }

  assert {
    condition     = alltrue([for s in azurerm_subnet.this : s.default_outbound_access_enabled == false])
    error_message = "Subnets must not have implicit Internet access."
  }

  assert {
    condition     = one(azurerm_subnet.this["db"].delegation).service_delegation[0].name == "Microsoft.DBforPostgreSQL/flexibleServers"
    error_message = "The db subnet must be delegated to PostgreSQL."
  }

  assert {
    condition     = toset([for e in azurerm_subnet.this["app"].service_endpoint : e.service]) == toset(["Microsoft.Storage", "Microsoft.KeyVault"])
    error_message = "Service endpoints must be configured."
  }

  assert {
    condition     = length(azurerm_network_security_group.this) == 2 && length(azurerm_subnet_network_security_group_association.this) == 2
    error_message = "Every subnet needs its own NSG and association."
  }
}

run "nsg_rules_are_translated" {
  command = plan

  providers = {
    azurerm     = azurerm
    azurerm.hub = azurerm.hub
  }

  assert {
    condition = (
      azurerm_network_security_rule.this["app/allow-https-from-hub"].priority == 100 &&
      azurerm_network_security_rule.this["app/allow-https-from-hub"].direction == "Inbound" &&
      azurerm_network_security_rule.this["app/allow-https-from-hub"].protocol == "Tcp"
    )
    error_message = "First rule: priority 100, Inbound, Tcp."
  }

  assert {
    condition = (
      toset(azurerm_network_security_rule.this["app/allow-https-from-hub"].source_address_prefixes) == toset(["10.0.0.0/22", "10.0.4.0/24"]) &&
      azurerm_network_security_rule.this["app/allow-https-from-hub"].source_address_prefix == null &&
      toset(azurerm_network_security_rule.this["app/allow-https-from-hub"].destination_port_ranges) == toset(["443", "8443"]) &&
      azurerm_network_security_rule.this["app/allow-https-from-hub"].destination_address_prefix == "10.48.48.0/24"
    )
    error_message = "@hub must expand to the hub ranges (plural) and @subnet to the subnet prefix (singular)."
  }

  assert {
    condition = (
      azurerm_network_security_rule.this["app/allow-lb-probes"].priority == 4000 &&
      azurerm_network_security_rule.this["app/allow-lb-probes"].source_address_prefix == "AzureLoadBalancer" &&
      azurerm_network_security_rule.this["app/allow-lb-probes"].protocol == "*" &&
      azurerm_network_security_rule.this["app/allow-lb-probes"].destination_port_range == "*"
    )
    error_message = "Explicit priority, service tag and default ports must be respected."
  }

  assert {
    condition = (
      azurerm_network_security_rule.this["app/deny-internet-out"].priority == 120 &&
      azurerm_network_security_rule.this["app/deny-internet-out"].access == "Deny" &&
      azurerm_network_security_rule.this["app/deny-internet-out"].destination_address_prefix == "Internet"
    )
    error_message = "Automatic priority follows list position (100 + 10 x index)."
  }
}

run "routes_and_peering_with_hub" {
  command = plan

  providers = {
    azurerm     = azurerm
    azurerm.hub = azurerm.hub
  }

  assert {
    condition = (
      length(azurerm_route_table.this) == 1 &&
      azurerm_route_table.this[0].bgp_route_propagation_enabled == false &&
      one(azurerm_route_table.this[0].route).next_hop_in_ip_address == "10.0.0.4" &&
      length(azurerm_subnet_route_table_association.this) == 2
    )
    error_message = "With a hub firewall every subnet routes 0.0.0.0/0 to it."
  }

  assert {
    condition = (
      azurerm_virtual_network_peering.from_hub[0].resource_group_name == "rg-conn-dev-weu" &&
      azurerm_virtual_network_peering.from_hub[0].virtual_network_name == "vnet-hub-dev-weu" &&
      azurerm_virtual_network_peering.from_hub[0].allow_gateway_transit == true &&
      azurerm_virtual_network_peering.to_hub[0].use_remote_gateways == true
    )
    error_message = "Peering must be created on both sides with gateway transit."
  }
}

run "isolated_vnet_without_hub" {
  command = plan

  providers = {
    azurerm     = azurerm
    azurerm.hub = azurerm
  }

  variables {
    hub           = null
    peering_names = null
    subnets = {
      app = {
        name     = "snet-app"
        nsg_name = "nsg-pga-billing-dev-weu-app"
        prefix   = "10.48.48.0/24"
      }
    }
  }

  assert {
    condition     = length(azurerm_virtual_network_peering.to_hub) == 0 && length(azurerm_route_table.this) == 0
    error_message = "Without hub there is no peering and no route table."
  }
}

run "rejects_subnet_outside_address_space" {
  command = plan

  providers = {
    azurerm     = azurerm
    azurerm.hub = azurerm.hub
  }

  variables {
    subnets = {
      app = { name = "snet-app", nsg_name = "nsg-app", prefix = "10.49.0.0/24" }
    }
  }

  expect_failures = [var.subnets]
}

run "rejects_overlapping_subnets" {
  command = plan

  providers = {
    azurerm     = azurerm
    azurerm.hub = azurerm.hub
  }

  variables {
    subnets = {
      app = { name = "snet-app", nsg_name = "nsg-app", prefix = "10.48.48.0/23" }
      db  = { name = "snet-db", nsg_name = "nsg-db", prefix = "10.48.49.0/24" }
    }
  }

  expect_failures = [var.subnets]
}

run "rejects_prefix_not_network_address" {
  command = plan

  providers = {
    azurerm     = azurerm
    azurerm.hub = azurerm.hub
  }

  variables {
    subnets = {
      app = { name = "snet-app", nsg_name = "nsg-app", prefix = "10.48.48.5/24" }
    }
  }

  expect_failures = [var.subnets]
}

run "rejects_priority_collision" {
  command = plan

  providers = {
    azurerm     = azurerm
    azurerm.hub = azurerm.hub
  }

  variables {
    subnets = {
      app = {
        name     = "snet-app"
        nsg_name = "nsg-app"
        prefix   = "10.48.48.0/24"
        nsg_rules = [
          { name = "first", direction = "inbound", access = "allow", protocol = "tcp", source = "VirtualNetwork", ports = ["443"] },
          { name = "second", direction = "inbound", access = "allow", protocol = "tcp", source = "VirtualNetwork", ports = ["80"], priority = 100 },
        ]
      }
    }
  }

  expect_failures = [var.subnets]
}

run "rejects_overlap_with_hub" {
  command = plan

  providers = {
    azurerm     = azurerm
    azurerm.hub = azurerm.hub
  }

  variables {
    address_space = ["10.0.0.0/16"]
    subnets       = {}
  }

  expect_failures = [var.hub]
}

run "rejects_hub_alias_without_hub" {
  command = plan

  providers = {
    azurerm     = azurerm
    azurerm.hub = azurerm
  }

  variables {
    hub           = null
    peering_names = null
    subnets = {
      app = {
        name      = "snet-app"
        nsg_name  = "nsg-app"
        prefix    = "10.48.48.0/24"
        nsg_rules = [{ name = "from-hub", direction = "inbound", access = "allow", protocol = "tcp", source = "@hub" }]
      }
    }
  }

  expect_failures = [var.subnets]
}
