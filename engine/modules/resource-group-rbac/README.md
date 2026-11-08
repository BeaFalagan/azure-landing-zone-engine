# resource-group-rbac

Crea el resource group del proyecto y el acceso de las personas:

- Un **grupo de seguridad de Entra ID** por entrada de `groups`, con `prevent_duplicate_names`. La identidad que ejecuta Terraform queda como owner del grupo (comportamiento por defecto de azuread). Por eso el pipeline puede gestionar los miembros con solo `Group.Create` + `User.Read.All` ([ADR-0005](../../../docs/adr/0005-identities-and-permissions.md)).
- Una **asignación de rol** por grupo y rol, sobre el resource group, con `principal_type = "Group"`. La condición ABAC del pipeline solo permite asignar a grupos y solo los roles del catálogo, que llegan en `role_definition_ids`. Un rol fuera del catálogo falla en la validación, antes del plan.
- Un **`azuread_group_member`** por miembro indicado. No se usa el atributo `members` del grupo porque haría a Terraform dueño de toda la membresía y borraría a quien se añada fuera del motor. Los UPN se comparan en minúsculas y sin duplicados.

Los role definition IDs se construyen con el GUID del catálogo (`/subscriptions/<sub>/providers/Microsoft.Authorization/roleDefinitions/<guid>`), sin consultar Azure, así que el plan no depende de búsquedas por nombre.

## Ejemplo

Ver [examples/basic](examples/basic/main.tf).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.17.0 |
| azuread | >= 3.10, < 4.0 |
| azurerm | >= 5.12, < 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| azuread | >= 3.10, < 4.0 |
| azurerm | >= 5.12, < 6.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [azuread_group.this](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/group) | resource |
| [azuread_group_member.this](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/group_member) | resource |
| [azurerm_resource_group.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group) | resource |
| [azurerm_role_assignment.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azuread_user.members](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/data-sources/user) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| location | Azure region of the resource group. | `string` | n/a | yes |
| resource\_group\_name | Name of the project resource group. | `string` | n/a | yes |
| role\_definition\_ids | Roles that may be granted, as built-in role name => role definition GUID (the engine catalog). Any role outside this map is rejected. | `map(string)` | n/a | yes |
| subscription\_id | Subscription of the resource group. Used to build role definition IDs. | `string` | n/a | yes |
| groups | Entra ID security groups to create, keyed by access name. Each group gets its roles on the resource group.<br/>members are user principal names added to the group without taking ownership of the whole membership:<br/>people added outside Terraform are kept. | <pre>map(object({<br/>    display_name = string<br/>    description  = optional(string)<br/>    roles        = list(string)<br/>    members      = optional(list(string), [])<br/>  }))</pre> | `{}` | no |
| tags | Tags of the resource group. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| groups | Created Entra ID groups by access name (object\_id, display\_name). |
| resource\_group | Project resource group (id, name, location). |
| role\_assignment\_ids | Role assignment IDs by "<group>/<role>". |
<!-- END_TF_DOCS -->
