# Mocked plans of the example projects: nothing reaches Azure or Entra ID.

mock_provider "azurerm" {}

mock_provider "azurerm" {
  alias = "hub"
}

mock_provider "azuread" {
  mock_data "azuread_user" {
    defaults = {
      object_id = "55555555-5555-5555-5555-555555555555"
    }
  }
}

variables {
  platform_file = "../examples/platform.yaml"
}

run "minimal_example" {
  command = plan

  variables {
    project_file = "../examples/projects/demo/minimal/dev.yaml"
  }

  assert {
    condition     = output.configuration.names.resource_group == "rg-demo-minimal-dev-weu"
    error_message = "Unexpected resource group name."
  }

  assert {
    condition = (
      output.configuration.tags.source == "projects/demo/minimal/dev.yaml" &&
      output.configuration.tags.engine_version == "1.0.0" &&
      output.configuration.tags.cost_center == "ES0009"
    )
    error_message = "Business and engine tags must be applied."
  }

  assert {
    condition     = output.network == null && length(output.configuration.groups) == 0
    error_message = "The minimal example has no network and no access groups."
  }

  assert {
    condition     = output.configuration.log_analytics == true
    error_message = "Central monitoring is on by default."
  }
}

run "complete_example" {
  command = plan

  variables {
    project_file = "../examples/projects/demo/webapp/pro.yaml"
  }

  assert {
    condition     = output.configuration.network.hub.virtual_network_id == "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-conn-pro-weu/providers/Microsoft.Network/virtualNetworks/vnet-hub-pro-weu"
    error_message = "A pro project in westeurope must peer to the pro westeurope hub."
  }

  assert {
    condition     = join(",", output.configuration.network.dns_servers) == "10.0.9.4" && output.configuration.network.hub.firewall_private_ip == "10.0.8.4"
    error_message = "Peered projects inherit the hub DNS and route to its firewall."
  }

  assert {
    condition = (
      output.configuration.network.subnets["app"].name == "snet-app" &&
      output.configuration.network.subnets["app"].nsg_name == "nsg-demo-webapp-pro-weu-app" &&
      output.configuration.network.subnets["db"].delegation.service == "Microsoft.DBforPostgreSQL/flexibleServers"
    )
    error_message = "Subnet names and delegation aliases must be resolved."
  }

  assert {
    condition = (
      output.configuration.network.subnets["app"].nsg_rules[0].source == "@hub" &&
      output.configuration.network.subnets["app"].nsg_rules[0].destination == "@subnet" &&
      output.configuration.network.subnets["db"].nsg_rules[0].source == "10.48.48.0/24" &&
      output.configuration.network.subnets["db"].nsg_rules[1].source == "VirtualNetwork" &&
      output.configuration.network.subnets["db"].nsg_rules[1].priority == 4000
    )
    error_message = "Address aliases must be translated (hub -> @hub, vnet -> VirtualNetwork) and CIDRs kept."
  }

  assert {
    condition = (
      output.configuration.groups["developers"].display_name == "sg-az-demo-webapp-pro-developers" &&
      join(",", output.configuration.groups["developers"].members) == "ana@example.com,luis@example.com" &&
      join(",", output.configuration.groups["readers"].roles) == "Reader"
    )
    error_message = "Access entries must become named groups with roles and members."
  }
}

run "isolated_sandbox_example" {
  command = plan

  variables {
    project_file = "../examples/projects/demo/sandbox/dev.yaml"
  }

  assert {
    condition     = output.configuration.names.virtual_network == "vnet-demo-sandbox-dev-neu"
    error_message = "Region short code must come from the catalog (northeurope -> neu)."
  }

  assert {
    condition     = output.configuration.network.hub == null && length(output.configuration.network.dns_servers) == 0
    error_message = "A network with peer_to_hub: false has no hub and uses Azure DNS."
  }

  assert {
    condition     = output.configuration.log_analytics == false
    error_message = "monitoring.log_analytics: false must disable central monitoring."
  }
}

run "rejects_engine_version_mismatch" {
  command = plan

  variables {
    project_file = "tests/fixtures/projects/demo/oldversion/dev.yaml"
  }

  expect_failures = [terraform_data.project_checks]
}

run "rejects_path_mismatch" {
  command = plan

  variables {
    project_file = "tests/fixtures/projects/demo/wrongpath/dev.yaml"
  }

  expect_failures = [terraform_data.project_checks]
}

run "rejects_missing_hub" {
  command = plan

  variables {
    project_file = "tests/fixtures/projects/demo/nohub/pre.yaml"
  }

  expect_failures = [terraform_data.project_checks]
}

run "rejects_duplicate_names" {
  command = plan

  variables {
    project_file = "tests/fixtures/projects/demo/duplicates/dev.yaml"
  }

  expect_failures = [terraform_data.project_checks]
}

run "rejects_file_outside_projects_layout" {
  command = plan

  variables {
    project_file = "../catalog/catalog.yaml"
  }

  expect_failures = [var.project_file]
}
