data "azuread_service_principal" "msgraph" {
  client_id = local.msgraph_client_id
}

# Grants (and consents) Microsoft Graph application permissions to the pipeline identities.
# The person running the bootstrap needs Privileged Role Administrator (see README).
resource "azuread_app_role_assignment" "graph" {
  for_each = local.graph_assignments

  app_role_id         = data.azuread_service_principal.msgraph.app_role_ids[each.value.role]
  principal_object_id = azurerm_user_assigned_identity.this[each.value.identity].principal_id
  resource_object_id  = data.azuread_service_principal.msgraph.object_id
}
