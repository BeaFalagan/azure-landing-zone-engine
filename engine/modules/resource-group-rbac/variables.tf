variable "resource_group_name" {
  description = "Name of the project resource group."
  type        = string

  validation {
    condition     = can(regex("^[-a-zA-Z0-9._()]{1,89}[-a-zA-Z0-9_()]$", var.resource_group_name))
    error_message = "resource_group_name is not a valid resource group name."
  }
}

variable "location" {
  description = "Azure region of the resource group."
  type        = string
}

variable "subscription_id" {
  description = "Subscription of the resource group. Used to build role definition IDs."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.subscription_id))
    error_message = "subscription_id must be a lowercase GUID."
  }
}

variable "tags" {
  description = "Tags of the resource group."
  type        = map(string)
  default     = {}
}

variable "role_definition_ids" {
  description = "Roles that may be granted, as built-in role name => role definition GUID (the engine catalog). Any role outside this map is rejected."
  type        = map(string)

  validation {
    condition     = alltrue([for id in values(var.role_definition_ids) : can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", id))])
    error_message = "role_definition_ids values must be role definition GUIDs."
  }
}

variable "groups" {
  description = <<-EOT
    Entra ID security groups to create, keyed by access name. Each group gets its roles on the resource group.
    members are user principal names added to the group without taking ownership of the whole membership:
    people added outside Terraform are kept.
  EOT
  type = map(object({
    display_name = string
    description  = optional(string)
    roles        = list(string)
    members      = optional(list(string), [])
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for g in values(var.groups) : length(g.roles) > 0 && length(distinct(g.roles)) == length(g.roles)])
    error_message = "Each group needs at least one role and no repeated roles."
  }

  validation {
    condition     = alltrue(flatten([for g in values(var.groups) : [for r in g.roles : contains(keys(var.role_definition_ids), r)]]))
    error_message = "Every role must be one of the allowed roles (role_definition_ids)."
  }

  validation {
    condition     = alltrue(flatten([for g in values(var.groups) : [for m in g.members : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", m))]]))
    error_message = "members must be user principal names (name@domain)."
  }

  validation {
    condition     = alltrue([for g in values(var.groups) : length(g.display_name) <= 256 && trimspace(g.display_name) != ""])
    error_message = "display_name cannot be blank or longer than 256 characters."
  }

  validation {
    condition     = length(distinct([for g in values(var.groups) : lower(g.display_name)])) == length(var.groups)
    error_message = "Group display names must be unique."
  }
}
