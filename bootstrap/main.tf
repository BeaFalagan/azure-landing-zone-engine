data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "this" {
  name     = local.names.resource_group
  location = var.location
  tags     = local.tags
}

# State account: Entra ID authentication only (no shared keys, no SAS), versioning and soft delete.
resource "azurerm_storage_account" "state" {
  #checkov:skip=CKV_AZURE_59:Public endpoint required by GitHub-hosted runners; access is Entra ID only (shared keys disabled). See docs/adr/0005.
  #checkov:skip=CKV2_AZURE_33:No private endpoint for the same reason (GitHub-hosted runners).
  #checkov:skip=CKV2_AZURE_1:Microsoft-managed keys are enough for Terraform state; CMK is in docs/roadmap.md.
  #checkov:skip=CKV_AZURE_33:Queue service is not used.
  #checkov:skip=CKV2_AZURE_41:SAS is impossible: shared keys are disabled.
  #checkov:skip=CKV2_AZURE_40:Shared keys are disabled (shared_access_key_enabled = false); false positive.
  name                     = local.names.storage_account
  resource_group_name      = azurerm_resource_group.this.name
  location                 = azurerm_resource_group.this.location
  account_tier             = "Standard"
  account_kind             = "StorageV2"
  account_replication_type = "GZRS"

  min_tls_version                   = "TLS1_2"
  https_traffic_only_enabled        = true
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  allow_nested_items_to_be_public   = false
  cross_tenant_replication_enabled  = false
  local_user_enabled                = false
  sftp_enabled                      = false
  infrastructure_encryption_enabled = true
  public_network_access             = "Enabled"

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }

  tags = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_storage_container" "state" {
  #checkov:skip=CKV2_AZURE_21:Blob logging is configured at account level in the platform landing zone (diagnostics policy).
  for_each = local.state_containers

  name                  = each.value
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_management_lock" "state" {
  name       = "lock-state-cannot-delete"
  scope      = azurerm_storage_account.state.id
  lock_level = "CanNotDelete"
  notes      = "Holds every Terraform state of the landing zone engine."
}
