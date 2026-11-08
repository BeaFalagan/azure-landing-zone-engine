# Plan-only tests with mocked providers: nothing reaches Azure or Entra ID.

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "99999999-9999-9999-9999-999999999999"
    }
  }
}

mock_provider "azuread" {
  mock_data "azuread_service_principal" {
    defaults = {
      object_id = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
      app_role_ids = {
        "Group.Create"   = "bf7b1a76-6e77-406b-b258-bf5c7720e98f"
        "Group.Read.All" = "5b567255-7703-4780-807c-7be8301ae99b"
        "User.Read.All"  = "df021288-bdef-4463-88db-98f22de89214"
      }
    }
  }
}

variables {
  subscription_id                   = "00000000-0000-0000-0000-000000000000"
  organization                      = "contoso"
  github_repository                 = "contoso/landing-zones"
  landing_zones_management_group_id = "contoso-landingzones"
  hub_virtual_network_ids = [
    "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-conn-dev-weu/providers/Microsoft.Network/virtualNetworks/vnet-hub-dev-weu",
  ]
  log_analytics_workspace_id   = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-mgmt/providers/Microsoft.OperationalInsights/workspaces/log-mgmt"
  state_admins_group_object_id = "44444444-4444-4444-4444-444444444444"
  tags = {
    cost_center     = "IT0001"
    business_owner  = "owner@example.com"
    technical_owner = "team@example.com"
  }
}

run "state_account_is_entra_only" {
  command = plan

  assert {
    condition     = azurerm_storage_account.state.name == "stcontosolzstateweu"
    error_message = "Unexpected state account name."
  }

  assert {
    condition = (
      azurerm_storage_account.state.shared_access_key_enabled == false &&
      azurerm_storage_account.state.default_to_oauth_authentication == true &&
      azurerm_storage_account.state.allow_nested_items_to_be_public == false &&
      azurerm_storage_account.state.min_tls_version == "TLS1_2"
    )
    error_message = "The state account must only accept Entra ID over TLS 1.2."
  }

  assert {
    condition     = azurerm_storage_account.state.blob_properties[0].versioning_enabled
    error_message = "Blob versioning must be enabled to recover previous states."
  }

  assert {
    condition     = azurerm_management_lock.state.lock_level == "CanNotDelete"
    error_message = "The state account must be protected by a delete lock."
  }

  assert {
    condition     = toset([for c in azurerm_storage_container.state : c.name]) == toset(["tfstate", "bootstrap"])
    error_message = "Project and bootstrap states must live in separate containers."
  }
}

run "github_federation" {
  command = plan

  assert {
    condition = toset([for k, v in azurerm_federated_identity_credential.github : v.subject if startswith(k, "plan-")]) == toset([
      "repo:contoso/landing-zones:pull_request",
      "repo:contoso/landing-zones:ref:refs/heads/main",
    ])
    error_message = "The plan identity must trust pull requests and main only."
  }

  assert {
    condition = toset([for k, v in azurerm_federated_identity_credential.github : v.subject if startswith(k, "apply-")]) == toset([
      "repo:contoso/landing-zones:environment:lz-dev",
      "repo:contoso/landing-zones:environment:lz-pre",
      "repo:contoso/landing-zones:environment:lz-pro",
    ])
    error_message = "The apply identity must trust protected GitHub environments only."
  }

  assert {
    condition = alltrue([
      for v in azurerm_federated_identity_credential.github :
      v.issuer == "https://token.actions.githubusercontent.com" && join(",", v.audience) == "api://AzureADTokenExchange"
    ])
    error_message = "Federated credentials must use the GitHub issuer and the Entra token exchange audience."
  }
}

run "least_privilege_azure_roles" {
  command = plan

  assert {
    condition     = toset([for k, v in azurerm_role_assignment.azure : v.role_definition_name if startswith(k, "plan/")]) == toset(["Reader"])
    error_message = "The plan identity must only be Reader in Azure."
  }

  assert {
    condition     = azurerm_role_assignment.state["plan"].role_definition_name == "Storage Blob Data Reader"
    error_message = "The plan identity must only read project states."
  }

  assert {
    condition     = azurerm_role_assignment.azure["apply/hub-peering/vnet-hub-dev-weu"].role_definition_name == "Network Contributor"
    error_message = "The apply identity needs Network Contributor on each hub to create the hub-side peering."
  }

  assert {
    condition = alltrue([
      for guid in values(yamldecode(file("../engine/catalog/catalog.yaml")).roles) :
      strcontains(azurerm_role_assignment.rbac_admin.condition, guid)
    ])
    error_message = "The ABAC condition must allow every catalog role."
  }

  assert {
    condition = (
      !strcontains(azurerm_role_assignment.rbac_admin.condition, "8e3af657-a8ff-443c-a75c-2fe8c4bcb635") &&
      !strcontains(azurerm_role_assignment.rbac_admin.condition, "18d7d88d-d35e-4fb5-a5c3-7773c20a72d9") &&
      strcontains(azurerm_role_assignment.rbac_admin.condition, "{'Group'}")
    )
    error_message = "The ABAC condition must exclude Owner and User Access Administrator and only allow groups."
  }
}

run "graph_permissions" {
  command = plan

  assert {
    condition     = toset(keys(azuread_app_role_assignment.graph)) == toset(["plan/Group.Read.All", "plan/User.Read.All", "apply/Group.Create", "apply/User.Read.All"])
    error_message = "Graph permissions must be Group.Create + User.Read.All (apply) and Group.Read.All + User.Read.All (plan)."
  }
}

run "github_variables_output" {
  command = plan

  assert {
    condition     = toset(keys(output.github_actions_variables.environments)) == toset(["lz-dev", "lz-pre", "lz-pro"])
    error_message = "There must be one set of variables per GitHub environment."
  }

  assert {
    condition     = output.github_actions_variables.repository.TFSTATE_CONTAINER == "tfstate"
    error_message = "The pipeline must use the project state container."
  }
}

run "rejects_unknown_environment" {
  command = plan

  variables {
    environments = ["dev", "prod"]
  }

  expect_failures = [var.environments]
}

run "rejects_blank_mandatory_tag" {
  command = plan

  variables {
    tags = {
      cost_center     = " "
      business_owner  = "owner@example.com"
      technical_owner = "team@example.com"
    }
  }

  expect_failures = [var.tags]
}

run "rejects_region_outside_catalog" {
  command = plan

  variables {
    location = "eastus"
  }

  expect_failures = [var.location]
}

run "state_admins_group" {
  command = plan

  assert {
    condition = (
      azurerm_role_assignment.state_admins.principal_type == "Group" &&
      azurerm_role_assignment.state_admins.role_definition_name == "Storage Blob Data Contributor"
    )
    error_message = "Only the platform administrators group gets data access to every state."
  }

  assert {
    condition     = strcontains(output.bootstrap_backend_hcl, "container_name       = \"bootstrap\"")
    error_message = "The bootstrap state must live in its own container."
  }
}
