# Consistency checks that the JSON Schema cannot express. They stop the plan with a message
# that points to the YAML file (check blocks would only warn).
resource "terraform_data" "project_checks" {
  input = local.source_path

  lifecycle {
    precondition {
      condition     = local.raw.engine_version == local.engine_version
      error_message = "${local.source_path}: engine_version is ${local.raw.engine_version} but this engine is ${local.engine_version}. The pipeline must run the engine from tag engine/v${local.raw.engine_version}."
    }

    precondition {
      condition = (
        local.path_parts[1] == local.raw.business_unit &&
        local.path_parts[2] == local.raw.project &&
        local.path_parts[3] == local.raw.environment
      )
      error_message = "${local.source_path}: the path must be projects/${local.raw.business_unit}/${local.raw.project}/${local.raw.environment}.yaml (business_unit, project and environment must match the folders and the file name)."
    }

    precondition {
      condition     = contains(keys(local.catalog.regions), local.location)
      error_message = "${local.source_path}: location '${local.location}' is not in the engine catalog (${join(", ", keys(local.catalog.regions))})."
    }

    precondition {
      condition     = length(distinct(local.access_names)) == length(local.access_names)
      error_message = "${local.source_path}: access names must be unique (repeated: ${join(", ", distinct([for n in local.access_names : n if length([for m in local.access_names : m if m == n]) > 1]))})."
    }

    precondition {
      condition     = length(distinct(local.subnet_names)) == length(local.subnet_names)
      error_message = "${local.source_path}: subnet names must be unique (repeated: ${join(", ", distinct([for n in local.subnet_names : n if length([for m in local.subnet_names : m if m == n]) > 1]))})."
    }

    precondition {
      condition     = !local.peer_to_hub || length(local.hubs_matching) == 1
      error_message = "${local.source_path}: peer_to_hub is true but projects/_platform/platform.yaml has ${length(local.hubs_matching)} hubs for environment '${local.raw.environment}' and location '${local.location}' (exactly 1 needed). Ask the platform team, or set network.peer_to_hub: false."
    }

    precondition {
      condition     = length(local.unknown_delegations) == 0
      error_message = "${local.source_path}: unknown delegation(s) ${join(", ", local.unknown_delegations)}. Allowed: ${join(", ", keys(local.catalog.delegations))}."
    }

    precondition {
      condition     = length(local.unknown_addresses) == 0
      error_message = "${local.source_path}: NSG rule addresses must be a CIDR or one of ${join(", ", keys(local.address_aliases))}. Invalid: ${join(", ", local.unknown_addresses)}."
    }

    precondition {
      condition     = !local.has_override || length(trimspace(try(local.overrides.justification, ""))) >= 20
      error_message = "${local.source_path}: overrides need a justification of at least 20 characters."
    }
  }
}

module "naming" {
  source = "../modules/naming-tags"

  business_unit  = local.raw.business_unit
  project        = local.raw.project
  environment    = local.raw.environment
  region_short   = local.region_short
  subnets        = distinct(local.subnet_names)
  access_groups  = distinct(local.access_names)
  engine_version = local.raw.engine_version
  source_path    = local.source_path
  tags           = { for k, v in local.raw.tags : k => tostring(v) }

  name_overrides = {
    resource_group_name  = try(local.overrides.resource_group_name, null)
    virtual_network_name = try(local.overrides.virtual_network_name, null)
  }
}

module "resource_group" {
  source = "../modules/resource-group-rbac"

  resource_group_name = module.naming.names.resource_group
  location            = local.location
  subscription_id     = local.raw.subscription_id
  tags                = module.naming.tags
  role_definition_ids = local.catalog.roles
  groups              = local.groups
}

module "network" {
  source = "../modules/network"
  count  = local.has_network ? 1 : 0

  providers = {
    azurerm     = azurerm
    azurerm.hub = azurerm.hub
  }

  name                = module.naming.names.virtual_network
  resource_group_name = module.resource_group.resource_group.name
  location            = local.location
  tags                = module.naming.tags
  address_space       = local.network.address_space
  dns_servers         = local.dns_servers
  subnets             = local.subnets
  hub                 = local.hub
  route_table_name    = module.naming.names.route_table

  peering_names = local.hub == null ? null : {
    to_hub   = module.naming.names.peering_to_hub
    from_hub = module.naming.names.peering_from_hub
  }
}

module "monitoring" {
  source = "../modules/monitoring"
  count  = local.log_analytics ? 1 : 0

  subscription_id            = local.raw.subscription_id
  log_analytics_workspace_id = local.platform.log_analytics_workspace_id
  resources                  = local.diagnostic_resources
}
