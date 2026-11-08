variables {
  business_unit  = "pga"
  project        = "billing"
  environment    = "pro"
  region_short   = "weu"
  subnets        = ["app", "db"]
  access_groups  = ["readers", "developers"]
  engine_version = "1.2.3"
  source_path    = "projects/pga/billing/pro.yaml"
  tags = {
    cost_center     = "ES0009"
    business_owner  = "owner@example.com"
    technical_owner = "team@example.com"
  }
}

run "generates_caf_names" {
  command = plan

  assert {
    condition = output.names == {
      resource_group   = "rg-pga-billing-pro-weu"
      virtual_network  = "vnet-pga-billing-pro-weu"
      route_table      = "rt-pga-billing-pro-weu"
      peering_to_hub   = "peer-pga-billing-pro-to-hub"
      peering_from_hub = "peer-hub-to-pga-billing-pro"
    }
    error_message = "Unexpected generated names: ${jsonencode(output.names)}"
  }

  assert {
    condition     = output.subnet_names["app"] == "snet-app" && output.nsg_names["db"] == "nsg-pga-billing-pro-weu-db"
    error_message = "Unexpected subnet or NSG names."
  }

  assert {
    condition     = output.group_names["readers"] == "sg-az-pga-billing-pro-readers"
    error_message = "Unexpected group name."
  }
}

run "longest_names_fit_azure_limits" {
  command = plan

  variables {
    business_unit = "abcdef"
    project       = "abcdefghijklmn"
    subnets       = ["a234567890123456789012345678901b"]
    access_groups = ["a23456789012345678901234"]
  }

  assert {
    condition     = length(output.nsg_names["a234567890123456789012345678901b"]) <= 80
    error_message = "NSG names must fit in 80 characters."
  }

  assert {
    condition     = length(output.names.resource_group) <= 90 && length(output.names.virtual_network) <= 64
    error_message = "Resource group (90) and VNet (64) name limits exceeded."
  }
}

run "engine_tags_are_added" {
  command = plan

  assert {
    condition = (
      output.tags.managed_by == "lz-engine" &&
      output.tags.engine_version == "1.2.3" &&
      output.tags.source == "projects/pga/billing/pro.yaml" &&
      output.tags.environment == "pro" &&
      output.tags.cost_center == "ES0009"
    )
    error_message = "Engine tags must be merged with business tags."
  }
}

run "overrides_replace_generated_names" {
  command = plan

  variables {
    name_overrides = {
      resource_group_name = "rg-legacy-billing"
    }
  }

  assert {
    condition     = output.names.resource_group == "rg-legacy-billing" && output.names.virtual_network == "vnet-pga-billing-pro-weu"
    error_message = "Only the overridden name must change."
  }
}

run "rejects_reserved_tag" {
  command = plan

  variables {
    tags = {
      cost_center     = "ES0009"
      business_owner  = "owner@example.com"
      technical_owner = "team@example.com"
      environment     = "prod"
    }
  }

  expect_failures = [var.tags]
}

run "rejects_blank_mandatory_tag" {
  command = plan

  variables {
    tags = {
      cost_center     = "  "
      business_owner  = "owner@example.com"
      technical_owner = "team@example.com"
    }
  }

  expect_failures = [var.tags]
}

run "rejects_duplicate_subnets" {
  command = plan

  variables {
    subnets = ["app", "app"]
  }

  expect_failures = [var.subnets]
}

run "rejects_uppercase_business_unit" {
  command = plan

  variables {
    business_unit = "PGA"
  }

  expect_failures = [var.business_unit]
}
