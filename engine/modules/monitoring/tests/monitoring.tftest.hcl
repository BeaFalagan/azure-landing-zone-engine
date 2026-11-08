mock_provider "azurerm" {}

variables {
  subscription_id            = "00000000-0000-0000-0000-000000000000"
  log_analytics_workspace_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-mgmt/providers/Microsoft.OperationalInsights/workspaces/log-mgmt"
  resources = {
    vnet    = { resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet" }
    nsg-app = { resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/networkSecurityGroups/nsg", metric_categories = [] }
  }
}

run "activity_log_to_central_workspace" {
  command = plan

  assert {
    condition = (
      azurerm_monitor_diagnostic_setting.activity_log[0].target_resource_id == "/subscriptions/00000000-0000-0000-0000-000000000000" &&
      azurerm_monitor_diagnostic_setting.activity_log[0].log_analytics_workspace_id == var.log_analytics_workspace_id &&
      length(azurerm_monitor_diagnostic_setting.activity_log[0].enabled_log) == 8
    )
    error_message = "The subscription Activity Log must go to the central workspace with every category."
  }
}

run "resource_diagnostics" {
  command = plan

  assert {
    condition = (
      [for l in azurerm_monitor_diagnostic_setting.resources["vnet"].enabled_log : l.category_group] == ["allLogs"] &&
      [for m in azurerm_monitor_diagnostic_setting.resources["vnet"].enabled_metric : m.category] == ["AllMetrics"]
    )
    error_message = "By default resources send allLogs and AllMetrics."
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.resources["nsg-app"].enabled_metric) == 0
    error_message = "NSGs have no metrics."
  }
}

run "activity_log_can_be_disabled" {
  command = plan

  variables {
    activity_log = false
    resources    = {}
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.activity_log) == 0 && output.activity_log_setting_id == null
    error_message = "No Activity Log export when disabled."
  }
}

run "rejects_legacy_setting_name" {
  command = plan

  variables {
    setting_name = "service"
  }

  expect_failures = [var.setting_name]
}

run "rejects_resource_without_logs_or_metrics" {
  command = plan

  variables {
    resources = {
      vnet = { resource_id = "/subscriptions/x/rg/vnet", log_category_groups = [], metric_categories = [] }
    }
  }

  expect_failures = [var.resources]
}
