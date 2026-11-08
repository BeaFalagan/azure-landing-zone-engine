output "virtual_network" {
  description = "Virtual network (id, name, address_space)."
  value = {
    id            = azurerm_virtual_network.this.id
    name          = azurerm_virtual_network.this.name
    address_space = azurerm_virtual_network.this.address_space
  }
}

output "subnet_ids" {
  description = "Subnet IDs by short name."
  value       = { for key, subnet in azurerm_subnet.this : key => subnet.id }
}

output "network_security_group_ids" {
  description = "NSG IDs by subnet short name."
  value       = { for key, nsg in azurerm_network_security_group.this : key => nsg.id }
}

output "route_table_id" {
  description = "Route table ID, or null when the hub has no firewall."
  value       = one(azurerm_route_table.this[*].id)
}

output "peering_ids" {
  description = "Peering IDs (to_hub, from_hub), or null when not peered."
  value = var.hub == null ? null : {
    to_hub   = azurerm_virtual_network_peering.to_hub[0].id
    from_hub = azurerm_virtual_network_peering.from_hub[0].id
  }
}
