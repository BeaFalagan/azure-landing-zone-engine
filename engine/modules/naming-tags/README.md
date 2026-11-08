# naming-tags

Calcula los nombres de todos los recursos de un proyecto y las etiquetas finales. No crea recursos ni usa providers, así que la convención de nombres vive en un único sitio y se prueba sin Azure.

| Recurso | Patrón |
|---|---|
| Resource group | `rg-<bu>-<project>-<env>-<region>` |
| VNet | `vnet-<bu>-<project>-<env>-<region>` |
| Subnet | `snet-<name>` |
| NSG | `nsg-<bu>-<project>-<env>-<region>-<subnet>` |
| Tabla de rutas | `rt-<bu>-<project>-<env>-<region>` |
| Peerings | `peer-<bu>-<project>-<env>-to-hub` / `peer-hub-to-<bu>-<project>-<env>` |
| Grupo de Entra ID | `sg-az-<bu>-<project>-<env>-<name>` |

Etiquetas: las de negocio (`cost_center`, `business_owner` y `technical_owner` son obligatorias y no pueden estar en blanco) más las del motor (`business_unit`, `project`, `environment`, `managed_by = lz-engine`, `engine_version`, `source`). Las del motor se aplican al final y no se pueden sobrescribir.

`name_overrides` permite sustituir solo los nombres del resource group y de la VNet. La justificación obligatoria se valida en el esquema del proyecto.

Las longitudes máximas de `business_unit` (6), `project` (14) y los nombres de subnet (32) garantizan que ningún nombre generado supera los límites de Azure; lo comprueba un test.

## Ejemplo

Ver [examples/basic](examples/basic/main.tf).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.17.0 |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| business\_unit | Business unit short code (2-6 lowercase letters or digits, starting with a letter). | `string` | n/a | yes |
| engine\_version | Engine version that deploys the project (added as the engine\_version tag). | `string` | n/a | yes |
| environment | Environment code (3 lowercase letters, e.g. dev, pre, pro). | `string` | n/a | yes |
| project | Project short name (2-14 lowercase letters or digits, starting with a letter). | `string` | n/a | yes |
| region\_short | Short region code from the engine catalog (e.g. weu for westeurope). | `string` | n/a | yes |
| source\_path | Repository path of the project YAML (added as the source tag), e.g. projects/pga/billing/dev.yaml. | `string` | n/a | yes |
| tags | Business tags. cost\_center, business\_owner and technical\_owner are mandatory; engine tags (business\_unit, project, environment, managed\_by, engine\_version, source) are reserved. | `map(string)` | n/a | yes |
| access\_groups | Access group suffixes to generate Entra ID group display names for. | `list(string)` | `[]` | no |
| name\_overrides | Exceptional replacements for generated names (adoption of existing resources). Justification is enforced by the project schema. | <pre>object({<br/>    resource_group_name  = optional(string)<br/>    virtual_network_name = optional(string)<br/>  })</pre> | `{}` | no |
| subnets | Subnet short names (without the snet- prefix) to generate subnet and NSG names for. | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| group\_names | Entra ID group display names by access group suffix. |
| names | Generated names of the project-level resources (resource\_group, virtual\_network, route\_table, peering\_to\_hub, peering\_from\_hub). |
| nsg\_names | NSG names by subnet short name. |
| prefix | Project prefix <business\_unit>-<project>-<environment>. |
| subnet\_names | Subnet names by short name (snet-<name>). |
| tags | Business tags merged with the engine tags. |
<!-- END_TF_DOCS -->
