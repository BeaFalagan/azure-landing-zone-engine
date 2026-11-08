locals {
  # "<group>/<upn>" => membership. UPNs are compared in lowercase.
  memberships = merge([
    for key, group in var.groups : {
      for upn in distinct([for m in group.members : lower(m)]) : "${key}/${upn}" => { group = key, upn = upn }
    }
  ]...)

  # "<group>/<role>" => assignment.
  role_assignments = merge([
    for key, group in var.groups : {
      for role in group.roles : "${key}/${role}" => { group = key, role = role }
    }
  ]...)
}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# Security groups owned by the identity that runs Terraform (azuread default). Being the owner is
# what allows the pipeline to manage memberships without Group.ReadWrite.All.
resource "azuread_group" "this" {
  for_each = var.groups

  display_name            = each.value.display_name
  description             = coalesce(each.value.description, "Access to ${var.resource_group_name}. Managed by the landing zone engine.")
  security_enabled        = true
  prevent_duplicate_names = true
}

data "azuread_user" "members" {
  for_each = toset([for m in values(local.memberships) : m.upn])

  user_principal_name = each.key
}

# One resource per membership (not azuread_group.members) so that people added outside the engine are kept.
resource "azuread_group_member" "this" {
  for_each = local.memberships

  group_object_id  = azuread_group.this[each.value.group].object_id
  member_object_id = data.azuread_user.members[each.value.upn].object_id
}

resource "azurerm_role_assignment" "this" {
  for_each = local.role_assignments

  scope              = azurerm_resource_group.this.id
  role_definition_id = "/subscriptions/${var.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/${var.role_definition_ids[each.value.role]}"
  principal_id       = azuread_group.this[each.value.group].object_id
  # Required: the pipeline's ABAC condition only allows assignments to groups.
  principal_type = "Group"
  description    = "${each.value.role} for ${var.groups[each.value.group].display_name}. Managed by the landing zone engine."
}
