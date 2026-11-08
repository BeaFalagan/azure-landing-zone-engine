locals {
  # <bu>-<project>-<env>: identifies the project and environment everywhere.
  prefix = "${var.business_unit}-${var.project}-${var.environment}"
  # <bu>-<project>-<env>-<region>: for regional resources.
  base = "${local.prefix}-${var.region_short}"

  names = {
    resource_group   = coalesce(var.name_overrides.resource_group_name, "rg-${local.base}")
    virtual_network  = coalesce(var.name_overrides.virtual_network_name, "vnet-${local.base}")
    route_table      = "rt-${local.base}"
    peering_to_hub   = "peer-${local.prefix}-to-hub"
    peering_from_hub = "peer-hub-to-${local.prefix}"
  }

  subnet_names = { for s in var.subnets : s => "snet-${s}" }
  nsg_names    = { for s in var.subnets : s => "nsg-${local.base}-${s}" }
  group_names  = { for g in var.access_groups : g => "sg-az-${local.prefix}-${g}" }

  # Engine tags are applied last: they always win.
  tags = merge(var.tags, {
    business_unit  = var.business_unit
    project        = var.project
    environment    = var.environment
    managed_by     = "lz-engine"
    engine_version = var.engine_version
    source         = var.source_path
  })
}
