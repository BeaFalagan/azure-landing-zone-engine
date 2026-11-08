locals {
  catalog        = yamldecode(file("${path.module}/../catalog/catalog.yaml"))
  engine_version = trimspace(file("${path.module}/../VERSION"))
  raw            = yamldecode(file(var.project_file))
  platform       = yamldecode(file(var.platform_file))

  # projects/<bu>/<project>/<env>.yaml, wherever the repository is checked out.
  source_path = regex("projects/[^/]+/[^/]+/[^/]+\\.yaml$", var.project_file)
  path_parts  = split("/", trimsuffix(local.source_path, ".yaml"))

  location     = local.raw.location
  region_short = try(local.catalog.regions[local.location].short, "xxx")

  # ---- Access -------------------------------------------------------------------------------
  access_list  = try(local.raw.access, [])
  access_names = [for a in local.access_list : a.name]
  # Grouping (...) avoids a crash on duplicate names; the duplicate check reports them clearly.
  access = { for name, entries in { for a in local.access_list : a.name => a... } : name => entries[0] }

  groups = {
    for name, a in local.access : name => {
      display_name = module.naming.group_names[name]
      description  = try(a.description, null)
      roles        = a.roles
      members      = try(a.members, [])
    }
  }

  # ---- Network ------------------------------------------------------------------------------
  network     = try(local.raw.network, null)
  has_network = local.network != null
  peer_to_hub = local.has_network && try(local.network.peer_to_hub, true)
  # try() instead of a conditional: YAML lists are tuples whose type depends on their length.
  subnet_list  = try(local.network.subnets, [])
  subnet_names = [for s in local.subnet_list : s.name]
  subnets_raw  = { for name, entries in { for s in local.subnet_list : s.name => s... } : name => entries[0] }

  hubs_matching = [for h in local.platform.hubs : h if h.environment == local.raw.environment && h.location == local.location]
  hub = local.peer_to_hub && length(local.hubs_matching) == 1 ? {
    virtual_network_id  = local.hubs_matching[0].virtual_network_id
    address_space       = local.hubs_matching[0].address_space
    firewall_private_ip = try(local.hubs_matching[0].firewall_private_ip, null)
    use_remote_gateways = try(local.hubs_matching[0].use_remote_gateways, false)
  } : null

  # Own DNS servers if set; otherwise the hub DNS when peered; otherwise Azure DNS.
  dns_servers = (
    length(try(local.network.dns_servers, [])) > 0 ? tolist(local.network.dns_servers) :
    local.hub != null ? tolist(try(local.hubs_matching[0].dns_servers, [])) : tolist([])
  )

  # Catalog alias (any, vnet, hub, subnet...) -> value understood by the network module; a CIDR passes through.
  address_aliases = local.catalog.address_aliases

  subnets = {
    for name, s in local.subnets_raw : name => {
      name              = module.naming.subnet_names[name]
      nsg_name          = module.naming.nsg_names[name]
      prefix            = s.prefix
      service_endpoints = try(s.service_endpoints, [])
      delegation = try(s.delegation, null) == null ? null : {
        service = try(local.catalog.delegations[s.delegation].service, "unknown")
        actions = try(local.catalog.delegations[s.delegation].actions, [])
      }
      nsg_rules = [
        for r in try(s.nsg_rules, []) : {
          name        = r.name
          direction   = r.direction
          access      = r.access
          protocol    = r.protocol
          source      = lookup(local.address_aliases, r.source, r.source)
          destination = lookup(local.address_aliases, try(r.destination, "subnet"), try(r.destination, "subnet"))
          ports       = [for p in try(r.ports, ["*"]) : tostring(p)]
          priority    = try(r.priority, null)
        }
      ]
    }
  }

  # Addresses that are neither a catalog alias nor a CIDR (the schema already prevents them).
  unknown_addresses = flatten([
    for s in local.subnet_list : [
      for r in try(s.nsg_rules, []) : [
        for a in [r.source, try(r.destination, "subnet")] : a
        if !contains(keys(local.address_aliases), a) && !can(cidrhost(a, 0))
      ]
    ]
  ])
  unknown_delegations = [for s in local.subnet_list : s.delegation if try(s.delegation, null) != null && !contains(keys(local.catalog.delegations), try(s.delegation, ""))]

  # ---- Monitoring ---------------------------------------------------------------------------
  log_analytics = try(local.raw.monitoring.log_analytics, true)

  # VNet: logs and metrics. NSGs: logs only (they have no metrics).
  diagnostic_resources = merge(
    { for name in(local.has_network ? ["vnet"] : []) : name => {
      resource_id       = module.network[0].virtual_network.id
      metric_categories = ["AllMetrics"]
    } },
    { for name in keys(local.subnets) : "nsg-${name}" => {
      resource_id       = module.network[0].network_security_group_ids[name]
      metric_categories = []
    } },
  )

  # ---- Overrides ----------------------------------------------------------------------------
  overrides = try(local.raw.overrides, {})
  has_override = (
    try(local.overrides.resource_group_name, null) != null ||
    try(local.overrides.virtual_network_name, null) != null
  )
}
