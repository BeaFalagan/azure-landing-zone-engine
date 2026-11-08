locals {
  hub_address_space = try(var.hub.address_space, [])
  firewall_ip       = try(var.hub.firewall_private_ip, null)

  # /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<name>
  hub_id_parts = var.hub == null ? [] : split("/", var.hub.virtual_network_id)

  protocols = { tcp = "Tcp", udp = "Udp", icmp = "Icmp", any = "*" }

  # "<subnet>/<rule>" => rule with aliases resolved to address lists.
  nsg_rules = merge([
    for key, subnet in var.subnets : {
      for index, rule in subnet.nsg_rules : "${key}/${rule.name}" => {
        subnet    = key
        name      = rule.name
        direction = title(rule.direction)
        access    = title(rule.access)
        protocol  = local.protocols[rule.protocol]
        priority  = coalesce(rule.priority, 100 + 10 * index)
        ports     = rule.ports
        source = (
          rule.source == "@subnet" ? [subnet.prefix] :
          rule.source == "@hub" ? local.hub_address_space : [rule.source]
        )
        destination = (
          rule.destination == "@subnet" ? [subnet.prefix] :
          rule.destination == "@hub" ? local.hub_address_space : [rule.destination]
        )
      }
    }
  ]...)
}

resource "azurerm_virtual_network" "this" {
  #checkov:skip=CKV_AZURE_182:DNS servers come from the platform (hub DNS in platform.yaml); the engine does not decide how many exist.
  #checkov:skip=CKV_AZURE_183:Same reason: an empty list (Azure DNS) is valid for isolated networks.
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = var.address_space
  dns_servers         = var.dns_servers
  tags                = var.tags
}

resource "azurerm_subnet" "this" {
  for_each = var.subnets

  name                 = each.value.name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [each.value.prefix]

  # No implicit Internet access: outbound traffic goes through the hub firewall.
  default_outbound_access_enabled = false

  dynamic "service_endpoint" {
    for_each = toset(each.value.service_endpoints)

    content {
      service = service_endpoint.value
    }
  }

  dynamic "delegation" {
    for_each = each.value.delegation == null ? [] : [each.value.delegation]

    content {
      name = "delegation"

      service_delegation {
        name    = delegation.value.service
        actions = delegation.value.actions
      }
    }
  }
}

resource "azurerm_network_security_group" "this" {
  for_each = var.subnets

  name                = each.value.nsg_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

# Separate rule resources: a change to one rule shows up as exactly one change in the plan.
# Service tags are only valid in the singular *_prefix arguments, so single values use them.
resource "azurerm_network_security_rule" "this" {
  for_each = local.nsg_rules

  name                        = each.value.name
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.this[each.value.subnet].name
  direction                   = each.value.direction
  access                      = each.value.access
  protocol                    = each.value.protocol
  priority                    = each.value.priority

  source_port_range            = "*"
  destination_port_range       = length(each.value.ports) == 1 ? each.value.ports[0] : null
  destination_port_ranges      = length(each.value.ports) > 1 ? each.value.ports : null
  source_address_prefix        = length(each.value.source) == 1 ? each.value.source[0] : null
  source_address_prefixes      = length(each.value.source) > 1 ? each.value.source : null
  destination_address_prefix   = length(each.value.destination) == 1 ? each.value.destination[0] : null
  destination_address_prefixes = length(each.value.destination) > 1 ? each.value.destination : null
}

resource "azurerm_subnet_network_security_group_association" "this" {
  for_each = var.subnets

  subnet_id                 = azurerm_subnet.this[each.key].id
  network_security_group_id = azurerm_network_security_group.this[each.key].id
}

# Default route to the hub firewall, only when the hub declares one.
resource "azurerm_route_table" "this" {
  count = local.firewall_ip == null ? 0 : 1

  name                          = var.route_table_name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  bgp_route_propagation_enabled = false
  tags                          = var.tags

  route = [
    {
      name                   = "default-to-hub-firewall"
      address_prefix         = "0.0.0.0/0"
      next_hop_type          = "VirtualAppliance"
      next_hop_in_ip_address = local.firewall_ip
    },
  ]
}

resource "azurerm_subnet_route_table_association" "this" {
  for_each = local.firewall_ip == null ? {} : var.subnets

  subnet_id      = azurerm_subnet.this[each.key].id
  route_table_id = azurerm_route_table.this[0].id
}

# Hub side first: use_remote_gateways in the spoke requires gateway transit already enabled in the hub.
resource "azurerm_virtual_network_peering" "from_hub" {
  count    = var.hub == null ? 0 : 1
  provider = azurerm.hub

  name                         = var.peering_names.from_hub
  resource_group_name          = local.hub_id_parts[4]
  virtual_network_name         = local.hub_id_parts[8]
  remote_virtual_network_id    = azurerm_virtual_network.this.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = var.hub.use_remote_gateways
}

resource "azurerm_virtual_network_peering" "to_hub" {
  count = var.hub == null ? 0 : 1

  name                         = var.peering_names.to_hub
  resource_group_name          = var.resource_group_name
  virtual_network_name         = azurerm_virtual_network.this.name
  remote_virtual_network_id    = var.hub.virtual_network_id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  use_remote_gateways          = var.hub.use_remote_gateways

  depends_on = [azurerm_virtual_network_peering.from_hub]
}
