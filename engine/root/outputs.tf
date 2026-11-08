output "configuration" {
  description = "Normalized configuration derived from the YAML (names, tags, network and access). Useful to review a plan and in tests."
  value = {
    source         = local.source_path
    engine_version = local.engine_version
    names          = module.naming.names
    tags           = module.naming.tags
    groups         = local.groups
    network = local.has_network ? {
      address_space = local.network.address_space
      dns_servers   = local.dns_servers
      hub           = local.hub
      subnets       = local.subnets
    } : null
    log_analytics = local.log_analytics
  }
}

output "resource_group" {
  description = "Project resource group (id, name, location)."
  value       = module.resource_group.resource_group
}

output "groups" {
  description = "Entra ID groups created for the project (object_id, display_name)."
  value       = module.resource_group.groups
}

output "network" {
  description = "Virtual network and subnet IDs, or null when the project has no network."
  value = local.has_network ? {
    virtual_network = module.network[0].virtual_network
    subnet_ids      = module.network[0].subnet_ids
    route_table_id  = module.network[0].route_table_id
    peering_ids     = module.network[0].peering_ids
  } : null
}
