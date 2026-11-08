mock_provider "azurerm" {}

mock_provider "azuread" {
  mock_data "azuread_user" {
    defaults = {
      object_id = "55555555-5555-5555-5555-555555555555"
    }
  }
}

variables {
  resource_group_name = "rg-pga-billing-dev-weu"
  location            = "westeurope"
  subscription_id     = "00000000-0000-0000-0000-000000000000"
  tags                = { cost_center = "ES0009" }
  role_definition_ids = {
    "Reader"                 = "acdd72a7-3385-48ef-bd42-f606fba81ae7"
    "Contributor"            = "b24988ac-6180-42a0-ab88-20f7382dd24c"
    "Key Vault Secrets User" = "4633458b-17de-408a-b874-0445c86b69e6"
  }
  groups = {
    readers = {
      display_name = "sg-az-pga-billing-dev-readers"
      roles        = ["Reader"]
    }
    developers = {
      display_name = "sg-az-pga-billing-dev-developers"
      roles        = ["Contributor", "Key Vault Secrets User"]
      members      = ["Ana@Example.com", "luis@example.com", "ana@example.com"]
    }
  }
}

run "creates_groups_and_assignments" {
  command = plan

  assert {
    condition     = azurerm_resource_group.this.name == "rg-pga-billing-dev-weu" && azurerm_resource_group.this.tags.cost_center == "ES0009"
    error_message = "Resource group name or tags are wrong."
  }

  assert {
    condition     = alltrue([for g in azuread_group.this : g.security_enabled && g.prevent_duplicate_names])
    error_message = "Groups must be security groups with duplicate name protection."
  }

  assert {
    condition     = toset(keys(azurerm_role_assignment.this)) == toset(["readers/Reader", "developers/Contributor", "developers/Key Vault Secrets User"])
    error_message = "One role assignment per group and role is expected."
  }

  assert {
    condition     = alltrue([for a in azurerm_role_assignment.this : a.principal_type == "Group"])
    error_message = "principal_type must be Group (required by the pipeline ABAC condition)."
  }

  assert {
    condition     = azurerm_role_assignment.this["readers/Reader"].role_definition_id == "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
    error_message = "Role definition IDs must come from the catalog GUIDs."
  }
}

run "memberships_are_deduplicated_case_insensitively" {
  command = plan

  assert {
    condition     = toset(keys(azuread_group_member.this)) == toset(["developers/ana@example.com", "developers/luis@example.com"])
    error_message = "Members must be lowercased and deduplicated."
  }

  assert {
    condition     = length(data.azuread_user.members) == 2
    error_message = "Each user must be looked up once."
  }
}

run "no_groups_only_resource_group" {
  command = plan

  variables {
    groups = {}
  }

  assert {
    condition     = length(azuread_group.this) == 0 && length(azurerm_role_assignment.this) == 0
    error_message = "Without access entries nothing but the resource group is created."
  }
}

run "rejects_role_outside_catalog" {
  command = plan

  variables {
    groups = {
      admins = {
        display_name = "sg-az-pga-billing-dev-admins"
        roles        = ["Owner"]
      }
    }
  }

  expect_failures = [var.groups]
}

run "rejects_invalid_member" {
  command = plan

  variables {
    groups = {
      readers = {
        display_name = "sg-az-pga-billing-dev-readers"
        roles        = ["Reader"]
        members      = ["Ana Garcia"]
      }
    }
  }

  expect_failures = [var.groups]
}

run "rejects_group_without_roles" {
  command = plan

  variables {
    groups = {
      readers = {
        display_name = "sg-az-pga-billing-dev-readers"
        roles        = []
      }
    }
  }

  expect_failures = [var.groups]
}
