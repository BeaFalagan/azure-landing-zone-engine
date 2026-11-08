output "resource_group" {
  description = "Project resource group (id, name, location)."
  value = {
    id       = azurerm_resource_group.this.id
    name     = azurerm_resource_group.this.name
    location = azurerm_resource_group.this.location
  }
}

output "groups" {
  description = "Created Entra ID groups by access name (object_id, display_name)."
  value = {
    for key, group in azuread_group.this : key => {
      object_id    = group.object_id
      display_name = group.display_name
    }
  }
}

output "role_assignment_ids" {
  description = "Role assignment IDs by \"<group>/<role>\"."
  value       = { for key, assignment in azurerm_role_assignment.this : key => assignment.id }
}
