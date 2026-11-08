# Pipeline identities: user-assigned managed identities federated with GitHub Actions (OIDC).
# No client secrets or certificates exist.
resource "azurerm_user_assigned_identity" "this" {
  for_each = local.names.identity

  name                = each.value
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "github" {
  for_each = local.federated_credentials

  name                      = each.key
  user_assigned_identity_id = azurerm_user_assigned_identity.this[each.value.identity].id
  issuer                    = local.github_issuer
  audience                  = [local.github_audience]
  subject                   = each.value.subject
}
