resource "azurerm_role_assignment" "azure" {
  for_each = local.azure_role_assignments

  scope                            = each.value.scope
  role_definition_name             = each.value.role
  principal_id                     = azurerm_user_assigned_identity.this[each.value.identity].principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
  description                      = "Landing zone engine pipeline (${each.key})."
}

# Apply identity can grant access, but only the catalog roles and only to groups (ABAC).
resource "azurerm_role_assignment" "rbac_admin" {
  scope                            = local.landing_zones_scope
  role_definition_name             = "Role Based Access Control Administrator"
  principal_id                     = azurerm_user_assigned_identity.this["apply"].principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
  condition                        = local.rbac_admin_condition
  condition_version                = "2.0"
  description                      = "Landing zone engine pipeline: catalog roles to groups only."
}

# State access is limited to the project state container; the bootstrap container stays private.
resource "azurerm_role_assignment" "state" {
  for_each = local.state_role_assignments

  scope                            = azurerm_storage_container.state["projects"].id
  role_definition_name             = each.value
  principal_id                     = azurerm_user_assigned_identity.this[each.key].principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
  description                      = "Landing zone engine pipeline (${each.key}) on project states."
}

# Platform administrators: data access to every state (bootstrap migration, recovery).
resource "azurerm_role_assignment" "state_admins" {
  scope                = azurerm_storage_account.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.state_admins_group_object_id
  principal_type       = "Group"
  description          = "Platform administrators: Terraform state access."
}
