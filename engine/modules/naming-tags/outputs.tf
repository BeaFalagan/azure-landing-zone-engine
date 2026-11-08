output "prefix" {
  description = "Project prefix <business_unit>-<project>-<environment>."
  value       = local.prefix
}

output "names" {
  description = "Generated names of the project-level resources (resource_group, virtual_network, route_table, peering_to_hub, peering_from_hub)."
  value       = local.names
}

output "subnet_names" {
  description = "Subnet names by short name (snet-<name>)."
  value       = local.subnet_names
}

output "nsg_names" {
  description = "NSG names by subnet short name."
  value       = local.nsg_names
}

output "group_names" {
  description = "Entra ID group display names by access group suffix."
  value       = local.group_names
}

output "tags" {
  description = "Business tags merged with the engine tags."
  value       = local.tags
}
