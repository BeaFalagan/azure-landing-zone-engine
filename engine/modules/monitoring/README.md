# monitoring

Envía al Log Analytics central (referenciado, no creado):

- el **Activity Log de la suscripción** del proyecto, con todas sus categorías;
- los **diagnósticos de los recursos** indicados en `resources`. Por defecto se envían `allLogs` y `AllMetrics`; para recursos sin métricas, como los NSG, se pasa `metric_categories = []`.

Todos los diagnostic settings se llaman igual (`diag-lz-engine`), así que se identifican fácilmente en el portal y no chocan con los que pueda crear Azure Policy con otro nombre (Azure admite hasta 5 por recurso). El nombre `service` está prohibido porque es un nombre heredado que no se puede borrar del todo.

Las claves de `resources` deben conocerse en el plan (por ejemplo `vnet`, `nsg-app`); los IDs pueden ser desconocidos hasta el apply.

Permisos: la identidad apply necesita escribir diagnostic settings en la suscripción del proyecto (Contributor) y Monitoring Contributor sobre el workspace central; los concede el [bootstrap](../../../bootstrap/README.md).

## Ejemplo

Ver [examples/basic](examples/basic/main.tf).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.17.0 |
| azurerm | >= 5.12, < 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| azurerm | >= 5.12, < 6.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_monitor_diagnostic_setting.activity_log](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_diagnostic_setting) | resource |
| [azurerm_monitor_diagnostic_setting.resources](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_diagnostic_setting) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| log\_analytics\_workspace\_id | Resource ID of the central Log Analytics workspace. | `string` | n/a | yes |
| subscription\_id | Project subscription whose Activity Log is exported. | `string` | n/a | yes |
| activity\_log | Export the subscription Activity Log to the workspace. | `bool` | `true` | no |
| activity\_log\_categories | Activity Log categories to export. | `list(string)` | <pre>[<br/>  "Administrative",<br/>  "Security",<br/>  "ServiceHealth",<br/>  "Alert",<br/>  "Recommendation",<br/>  "Policy",<br/>  "Autoscale",<br/>  "ResourceHealth"<br/>]</pre> | no |
| resources | Resources whose diagnostics are sent to the workspace, keyed by a stable name (e.g. "vnet", "nsg-app").<br/>Keys must be known at plan time; resource IDs may be unknown. Resources without metrics (e.g. NSGs)<br/>use metric\_categories = []. | <pre>map(object({<br/>    resource_id         = string<br/>    log_category_groups = optional(list(string), ["allLogs"])<br/>    metric_categories   = optional(list(string), ["AllMetrics"])<br/>  }))</pre> | `{}` | no |
| setting\_name | Name of every diagnostic setting created by the engine. Must not be "service" (legacy name that cannot be fully deleted). | `string` | `"diag-lz-engine"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| activity\_log\_setting\_id | ID of the subscription Activity Log diagnostic setting, or null when disabled. |
| resource\_setting\_ids | Diagnostic setting IDs by resource key. |
<!-- END_TF_DOCS -->
