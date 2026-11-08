variable "business_unit" {
  description = "Business unit short code (2-6 lowercase letters or digits, starting with a letter)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,5}$", var.business_unit))
    error_message = "business_unit must be 2-6 lowercase letters or digits, starting with a letter."
  }
}

variable "project" {
  description = "Project short name (2-14 lowercase letters or digits, starting with a letter)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,13}$", var.project))
    error_message = "project must be 2-14 lowercase letters or digits, starting with a letter."
  }
}

variable "environment" {
  description = "Environment code (3 lowercase letters, e.g. dev, pre, pro)."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{3}$", var.environment))
    error_message = "environment must be 3 lowercase letters."
  }
}

variable "region_short" {
  description = "Short region code from the engine catalog (e.g. weu for westeurope)."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{3}$", var.region_short))
    error_message = "region_short must be 3 lowercase letters."
  }
}

variable "subnets" {
  description = "Subnet short names (without the snet- prefix) to generate subnet and NSG names for."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for s in var.subnets : can(regex("^[a-z][a-z0-9-]{0,30}[a-z0-9]$", s))])
    error_message = "Each subnet name must be 2-32 lowercase letters, digits or hyphens, starting with a letter and not ending with a hyphen."
  }

  validation {
    condition     = length(distinct(var.subnets)) == length(var.subnets)
    error_message = "Subnet names must be unique."
  }
}

variable "access_groups" {
  description = "Access group suffixes to generate Entra ID group display names for."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for g in var.access_groups : can(regex("^[a-z][a-z0-9-]{1,23}$", g))])
    error_message = "Each access group name must be 2-24 lowercase letters, digits or hyphens, starting with a letter."
  }

  validation {
    condition     = length(distinct(var.access_groups)) == length(var.access_groups)
    error_message = "Access group names must be unique."
  }
}

variable "name_overrides" {
  description = "Exceptional replacements for generated names (adoption of existing resources). Justification is enforced by the project schema."
  type = object({
    resource_group_name  = optional(string)
    virtual_network_name = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.name_overrides.resource_group_name == null || can(regex("^[-a-zA-Z0-9._()]{1,89}[-a-zA-Z0-9_()]$", var.name_overrides.resource_group_name))
    error_message = "name_overrides.resource_group_name is not a valid resource group name."
  }

  validation {
    condition     = var.name_overrides.virtual_network_name == null || can(regex("^[a-zA-Z0-9][-a-zA-Z0-9._]{0,62}[a-zA-Z0-9_]$", var.name_overrides.virtual_network_name))
    error_message = "name_overrides.virtual_network_name is not a valid virtual network name."
  }
}

variable "tags" {
  description = "Business tags. cost_center, business_owner and technical_owner are mandatory; engine tags (business_unit, project, environment, managed_by, engine_version, source) are reserved."
  type        = map(string)

  validation {
    condition = alltrue([
      for key in ["cost_center", "business_owner", "technical_owner"] : trimspace(lookup(var.tags, key, "")) != ""
    ])
    error_message = "tags must include non-empty cost_center, business_owner and technical_owner."
  }

  validation {
    condition     = alltrue([for value in values(var.tags) : trimspace(value) != "" && length(value) <= 256])
    error_message = "Tag values cannot be blank or longer than 256 characters."
  }

  validation {
    condition     = alltrue([for key in keys(var.tags) : can(regex("^[a-z][a-z0-9_]{0,62}$", key))])
    error_message = "Tag keys must be lowercase letters, digits or underscores, starting with a letter (max 63)."
  }

  validation {
    condition     = length(setintersection(keys(var.tags), ["business_unit", "project", "environment", "managed_by", "engine_version", "source"])) == 0
    error_message = "Tag keys business_unit, project, environment, managed_by, engine_version and source are reserved for the engine."
  }
}

variable "engine_version" {
  description = "Engine version that deploys the project (added as the engine_version tag)."
  type        = string

  validation {
    condition     = can(regex("^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$", var.engine_version))
    error_message = "engine_version must be a SemVer version such as 1.0.0."
  }
}

variable "source_path" {
  description = "Repository path of the project YAML (added as the source tag), e.g. projects/pga/billing/dev.yaml."
  type        = string

  validation {
    condition     = can(regex("^[-a-zA-Z0-9_./]{1,256}$", var.source_path))
    error_message = "source_path must be a relative repository path."
  }
}
