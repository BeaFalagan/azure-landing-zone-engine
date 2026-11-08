output "state_backend" {
  description = "Backend settings for project roots. The key is <business_unit>/<project>/<environment>.tfstate."
  value = {
    subscription_id      = var.subscription_id
    resource_group_name  = azurerm_resource_group.this.name
    storage_account_name = azurerm_storage_account.state.name
    container_name       = azurerm_storage_container.state["projects"].name
    use_azuread_auth     = true
  }
}

output "identities" {
  description = "Client IDs and principal IDs of the pipeline identities."
  value = {
    for kind, identity in azurerm_user_assigned_identity.this : kind => {
      client_id    = identity.client_id
      principal_id = identity.principal_id
    }
  }
}

output "github_actions_variables" {
  description = "Values to create as GitHub Actions variables (not secrets: none of them is confidential)."
  value = {
    repository = {
      AZURE_TENANT_ID        = data.azurerm_client_config.current.tenant_id
      AZURE_CLIENT_ID_PLAN   = azurerm_user_assigned_identity.this["plan"].client_id
      TFSTATE_SUBSCRIPTION   = var.subscription_id
      TFSTATE_RESOURCE_GROUP = azurerm_resource_group.this.name
      TFSTATE_ACCOUNT        = azurerm_storage_account.state.name
      TFSTATE_CONTAINER      = azurerm_storage_container.state["projects"].name
    }
    environments = {
      for env in var.environments : "${var.github_environment_prefix}${env}" => {
        AZURE_CLIENT_ID_APPLY = azurerm_user_assigned_identity.this["apply"].client_id
      }
    }
  }
}

output "bootstrap_backend_hcl" {
  description = "Content of bootstrap/backend.hcl, used to migrate and later reuse the bootstrap state."
  value       = <<-EOT
    subscription_id      = "${var.subscription_id}"
    resource_group_name  = "${azurerm_resource_group.this.name}"
    storage_account_name = "${azurerm_storage_account.state.name}"
    container_name       = "${azurerm_storage_container.state["bootstrap"].name}"
    key                  = "bootstrap.tfstate"
  EOT
}
