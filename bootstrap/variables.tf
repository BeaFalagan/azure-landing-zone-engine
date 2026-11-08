variable "subscription_id" {
  description = "Subscription that hosts the Terraform state and the pipeline identities (platform management subscription)."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.subscription_id))
    error_message = "subscription_id must be a lowercase GUID."
  }
}

variable "organization" {
  description = "Short organization code used in resource names (2-8 lowercase letters or digits). The state storage account name must be globally unique."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,7}$", var.organization))
    error_message = "organization must be 2-8 lowercase letters or digits, starting with a letter."
  }
}

variable "location" {
  description = "Region of the bootstrap resources. Must be a region of engine/catalog/catalog.yaml."
  type        = string
  default     = "westeurope"

  validation {
    condition     = contains(keys(local.catalog.regions), var.location)
    error_message = "location must be one of the regions in engine/catalog/catalog.yaml."
  }
}

variable "github_repository" {
  description = "GitHub repository (owner/name) whose workflows may use the pipeline identities."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must look like owner/name."
  }
}

variable "environments" {
  description = "Environments that get a GitHub environment (<github_environment_prefix><env>) trusted by the apply identity."
  type        = list(string)
  default     = ["dev", "pre", "pro"]

  validation {
    condition     = length(var.environments) > 0 && alltrue([for env in var.environments : contains(local.catalog.environments, env)])
    error_message = "environments must be a non-empty subset of the environments in engine/catalog/catalog.yaml."
  }
}

variable "github_environment_prefix" {
  description = "Prefix of the GitHub environments that protect apply jobs."
  type        = string
  default     = "lz-"
}

variable "landing_zones_management_group_id" {
  description = "Name (ID) of the management group that contains every project subscription. The pipeline identities get their Azure roles here."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_().-]{1,90}$", var.landing_zones_management_group_id))
    error_message = "landing_zones_management_group_id must be a management group name, not a full resource ID."
  }
}

variable "hub_virtual_network_ids" {
  description = "Resource IDs of the hub VNets listed in projects/_platform/platform.yaml. The apply identity needs them to create the hub side of each peering."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for id in var.hub_virtual_network_ids :
      can(regex("^/subscriptions/[0-9a-f-]{36}/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+$", id))
    ])
    error_message = "Each hub_virtual_network_ids entry must be a virtual network resource ID."
  }
}

variable "log_analytics_workspace_id" {
  description = "Resource ID of the central Log Analytics workspace (log_analytics_workspace_id in platform.yaml)."
  type        = string

  validation {
    condition     = can(regex("^/subscriptions/[0-9a-f-]{36}/resourceGroups/[^/]+/providers/Microsoft\\.OperationalInsights/workspaces/[^/]+$", var.log_analytics_workspace_id))
    error_message = "log_analytics_workspace_id must be a Log Analytics workspace resource ID."
  }
}

variable "tags" {
  description = "Business tags for the bootstrap resources. cost_center, business_owner and technical_owner are mandatory and cannot be blank."
  type        = map(string)

  validation {
    condition = alltrue([
      for key in ["cost_center", "business_owner", "technical_owner"] :
      trimspace(lookup(var.tags, key, "")) != ""
    ])
    error_message = "tags must include non-empty cost_center, business_owner and technical_owner."
  }
}

variable "state_admins_group_object_id" {
  description = "Object ID of the Entra ID group of platform administrators. It gets Storage Blob Data Contributor on the state account (bootstrap state migration and break-glass recovery). The person running the bootstrap must be a member."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.state_admins_group_object_id))
    error_message = "state_admins_group_object_id must be a lowercase GUID."
  }
}
