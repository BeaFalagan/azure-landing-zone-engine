# engine/root

Root module del motor: lo que el pipeline ejecuta para **un** proyecto y entorno ([ADR-0002](../../docs/adr/0002-deployment-unit.md)).

```bash
terraform -chdir=engine/root init \
  -backend-config=backend.hcl -backend-config="key=<bu>/<project>/<env>.tfstate"
terraform -chdir=engine/root plan \
  -var project_file=$PWD/projects/<bu>/<project>/<env>.yaml \
  -var platform_file=$PWD/projects/_platform/platform.yaml
```

## Qué hace

1. **Lee** el YAML del proyecto, `platform.yaml`, el catálogo y `engine/VERSION`.
2. **Normaliza** el YAML:
   - aplica valores por defecto (`peer_to_hub: true`, `log_analytics: true`, `ports: ["*"]`…);
   - convierte las listas en mapas por `name`;
   - traduce los aliases del catálogo: `hub` → `@hub`, `vnet` → `VirtualNetwork`, `postgresql` → `Microsoft.DBforPostgreSQL/flexibleServers`;
   - elige el hub del mismo entorno y región;
   - hereda los DNS del hub si el proyecto no define los suyos.
3. **Comprueba** lo que el esquema JSON no puede (`terraform_data.project_checks`). El plan se detiene con un mensaje que señala el fichero:

   | Comprobación | Mensaje (resumen) |
   |---|---|
   | `engine_version` igual a `engine/VERSION` | `engine_version is 0.9.0 but this engine is 1.0.0…` |
   | Ruta y contenido coinciden | `the path must be projects/demo/billing/dev.yaml…` |
   | Región en el catálogo | `location 'eastus' is not in the engine catalog…` |
   | Nombres de `access` y de subnets únicos | `subnet names must be unique (repeated: app)` |
   | Hay exactamente un hub para entorno y región | `platform.yaml has 0 hubs for environment 'pre'…` |
   | Delegaciones y direcciones conocidas | `NSG rule addresses must be a CIDR or one of…` |
   | Overrides con justificación | `overrides need a justification of at least 20 characters` |

   El resto de reglas (rangos IP, solapes, prioridades, etiquetas, roles) las validan los [módulos](../modules/).
4. **Llama** a `naming-tags`, `resource-group-rbac`, `network` (si hay bloque `network`) y `monitoring` (si `log_analytics` es `true`).

## Providers

- `azurerm`: suscripción del proyecto. Registra solo los resource providers del catálogo. Con `register_resource_providers = false` no registra nada; así se ejecutan los plans de PR, porque la identidad de plan es de solo lectura.
- `azurerm.hub`: suscripción del hub (sacada del ID de la VNet hub), solo para el lado hub del peering.
- `azuread`: grupos de Entra ID.

Las credenciales llegan por variables de entorno (`ARM_USE_OIDC`, `ARM_CLIENT_ID`, `ARM_TENANT_ID`); no hay secretos en el código.

## Salidas

`configuration` muestra la configuración ya normalizada: nombres, etiquetas, subnets con reglas resueltas, hub y DNS. Aparece en el plan y permite revisar qué ha entendido el motor del YAML.

## Tests

`tests/root.tftest.hcl` hace un plan simulado de los tres [ejemplos](../examples/) y de los ficheros de `tests/fixtures/`, que contienen errores a propósito.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.17.0, < 2.0.0 |
| azuread | ~> 3.10 |
| azurerm | ~> 5.12 |

## Providers

| Name | Version |
| ---- | ------- |
| terraform | n/a |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| monitoring | ../modules/monitoring | n/a |
| naming | ../modules/naming-tags | n/a |
| network | ../modules/network | n/a |
| resource\_group | ../modules/resource-group-rbac | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [terraform_data.project_checks](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| platform\_file | Path to the platform references (projects/\_platform/platform.yaml). | `string` | n/a | yes |
| project\_file | Path to the project YAML. Must end in projects/<business\_unit>/<project>/<environment>.yaml. | `string` | n/a | yes |
| register\_resource\_providers | Register the catalog resource providers in the project subscription. Pull request plans run with false because the plan identity is read-only. | `bool` | `true` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| configuration | Normalized configuration derived from the YAML (names, tags, network and access). Useful to review a plan and in tests. |
| groups | Entra ID groups created for the project (object\_id, display\_name). |
| network | Virtual network and subnet IDs, or null when the project has no network. |
| resource\_group | Project resource group (id, name, location). |
<!-- END_TF_DOCS -->
