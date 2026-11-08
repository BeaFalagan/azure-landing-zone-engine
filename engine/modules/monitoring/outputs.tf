output "activity_log_setting_id" {
  description = "ID of the subscription Activity Log diagnostic setting, or null when disabled."
  value       = one(azurerm_monitor_diagnostic_setting.activity_log[*].id)
}

output "resource_setting_ids" {
  description = "Diagnostic setting IDs by resource key."
  value       = { for key, setting in azurerm_monitor_diagnostic_setting.resources : key => setting.id }
}
