variable "project_file" {
  description = "Path to the project YAML. Must end in projects/<business_unit>/<project>/<environment>.yaml."
  type        = string

  validation {
    condition     = can(regex("projects/[a-z][a-z0-9]{1,5}/[a-z][a-z0-9]{1,13}/[a-z]{3}\\.yaml$", var.project_file))
    error_message = "project_file must end in projects/<business_unit>/<project>/<environment>.yaml."
  }

  validation {
    condition     = can(yamldecode(file(var.project_file)))
    error_message = "project_file cannot be read or is not valid YAML."
  }
}

variable "platform_file" {
  description = "Path to the platform references (projects/_platform/platform.yaml)."
  type        = string

  validation {
    condition     = can(yamldecode(file(var.platform_file)))
    error_message = "platform_file cannot be read or is not valid YAML."
  }
}

variable "register_resource_providers" {
  description = "Register the catalog resource providers in the project subscription. Pull request plans run with false because the plan identity is read-only."
  type        = bool
  default     = true
  nullable    = false
}
