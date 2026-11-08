variable "subscription_id" {
  description = "Project subscription whose Activity Log is exported."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.subscription_id))
    error_message = "subscription_id must be a lowercase GUID."
  }
}

variable "log_analytics_workspace_id" {
  description = "Resource ID of the central Log Analytics workspace."
  type        = string

  validation {
    condition     = can(regex("^/subscriptions/[0-9a-f-]{36}/resourceGroups/[^/]+/providers/Microsoft\\.OperationalInsights/workspaces/[^/]+$", var.log_analytics_workspace_id))
    error_message = "log_analytics_workspace_id must be a Log Analytics workspace resource ID."
  }
}

variable "setting_name" {
  description = "Name of every diagnostic setting created by the engine. Must not be \"service\" (legacy name that cannot be fully deleted)."
  type        = string
  default     = "diag-lz-engine"

  validation {
    condition     = var.setting_name != "service" && can(regex("^[-a-zA-Z0-9_.]{1,64}$", var.setting_name))
    error_message = "setting_name must be 1-64 letters, digits, '-', '_' or '.', and not \"service\"."
  }
}

variable "activity_log" {
  description = "Export the subscription Activity Log to the workspace."
  type        = bool
  default     = true
  nullable    = false
}

variable "activity_log_categories" {
  description = "Activity Log categories to export."
  type        = list(string)
  default     = ["Administrative", "Security", "ServiceHealth", "Alert", "Recommendation", "Policy", "Autoscale", "ResourceHealth"]
  nullable    = false

  validation {
    condition     = length(var.activity_log_categories) > 0
    error_message = "At least one Activity Log category is required."
  }
}

variable "resources" {
  description = <<-EOT
    Resources whose diagnostics are sent to the workspace, keyed by a stable name (e.g. "vnet", "nsg-app").
    Keys must be known at plan time; resource IDs may be unknown. Resources without metrics (e.g. NSGs)
    use metric_categories = [].
  EOT
  type = map(object({
    resource_id         = string
    log_category_groups = optional(list(string), ["allLogs"])
    metric_categories   = optional(list(string), ["AllMetrics"])
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for r in values(var.resources) : length(r.log_category_groups) + length(r.metric_categories) > 0])
    error_message = "Each resource needs at least one log category group or metric category."
  }
}
