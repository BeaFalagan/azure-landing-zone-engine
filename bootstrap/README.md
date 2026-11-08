# bootstrap

Configuración que se aplica **una sola vez** (y al cambiar permisos), a mano, por una persona administradora de la plataforma. Crea lo que el pipeline necesita para funcionar sin secretos:

| Recurso | Para qué |
|---|---|
| Storage account `st<org>lzstate<reg>` | States de Terraform. Solo Entra ID (sin claves compartidas ni SAS), TLS 1.2, GZRS, versionado y borrado temporal de 30 días, lock `CanNotDelete` y `prevent_destroy` |
| Contenedor `tfstate` | Un state por proyecto y entorno: `<business_unit>/<project>/<environment>.tfstate` |
| Contenedor `bootstrap` | State de esta configuración. Las identidades del pipeline no tienen acceso |
| UAMI `id-<org>-lzengine-plan-<reg>` | Identidad de **plan**. Federada con las PR y con `main` |
| UAMI `id-<org>-lzengine-apply-<reg>` | Identidad de **apply**. Federada solo con los environments protegidos `lz-<env>` |

## Permisos que concede

| Identidad | Azure | Microsoft Graph |
|---|---|---|
| plan | Reader en el management group de landing zones, en los hubs y en el Log Analytics central. Storage Blob Data Reader en `tfstate` (los plans de PR se ejecutan con `-lock=false`) | `Group.Read.All`, `User.Read.All` |
| apply | Contributor en el management group de landing zones. Role Based Access Control Administrator **con condición ABAC**: solo los roles de `engine/catalog/catalog.yaml` y solo a grupos. Network Contributor en cada hub (lado hub del peering). Monitoring Contributor en el Log Analytics central. Storage Blob Data Contributor en `tfstate` | `Group.Create`, `User.Read.All` |
| grupo de administradores del state | Storage Blob Data Contributor en la cuenta completa (migración del state del bootstrap y recuperación) | — |

`Group.Create` permite crear grupos y gestionar los que la identidad posee. El motor queda como owner de sus grupos, así que no necesita `Group.ReadWrite.All` ni `GroupMember.ReadWrite.All`.

Si se añade un rol al catálogo, hay que volver a aplicar el bootstrap para que la condición ABAC lo permita.

## Requisitos de quien lo ejecuta

- **Owner** (o User Access Administrator + Contributor) en la suscripción del state, en el management group de landing zones, en las VNets hub y en el Log Analytics central.
- **Privileged Role Administrator** en Entra ID, para conceder los permisos de aplicación de Microsoft Graph (equivale al consentimiento de administrador).
- Ser miembro del grupo `state_admins_group_object_id`.
- `az login` con esa cuenta, Terraform 1.17.x.

## Uso

```bash
cp bootstrap/terraform.tfvars.example bootstrap/terraform.tfvars   # rellenar
scripts/bootstrap.sh
```

La primera vez el script usa un state local, muestra el plan, pide confirmación, aplica, genera `bootstrap/backend.hcl` y migra el state al contenedor `bootstrap`. Las siguientes veces solo genera un plan contra el state remoto; el apply se lanza a mano.

## Configurar GitHub

Se hace una vez, después del primer apply. No hay ningún secreto que guardar: todo son variables.

1. **Environments `lz-dev`, `lz-pre` y `lz-pro`** (Settings → Environments):
   - *Required reviewers*: quién aprueba cada entorno. En `lz-pro`, el equipo de plataforma;
   - *Deployment branches*: solo `main`;
   - variable `AZURE_CLIENT_ID_APPLY` con el valor de `environments` en `terraform output github_actions_variables`.
2. **Variables del repositorio** (Settings → Secrets and variables → Actions → Variables): las de `repository` en el mismo output: `AZURE_TENANT_ID`, `AZURE_CLIENT_ID_PLAN`, `TFSTATE_SUBSCRIPTION`, `TFSTATE_RESOURCE_GROUP`, `TFSTATE_ACCOUNT` y `TFSTATE_CONTAINER`.
3. **Regla de rama para `main`** (Settings → Rules → Rulesets):
   - pull request obligatoria con revisión de CODEOWNERS;
   - checks obligatorios `projects-pr / result` y `engine-pr / result`;
   - *Require branches to be up to date before merging*, para que dos PR a la vez no se queden con el mismo rango de IP o la misma suscripción;
   - excepción (*bypass*) solo para el equipo de plataforma, que la usa para fusionar las bajas de proyectos.
4. **Regla de tags para `engine/v*`**: bloquear *update* y *deletion*. Una versión publicada no se mueve ni se borra; los tags los crea el workflow `engine-release`.
5. **Actions** (Settings → Actions → General): permisos por defecto del `GITHUB_TOKEN` en *Read*. Cada workflow pide solo los que necesita.
6. **CODEOWNERS**: añade en [.github/CODEOWNERS](../.github/CODEOWNERS) una línea por unidad de negocio (`/projects/<bu>/ @org/<equipo>`).

Con `gh` y el output en JSON:

```bash
terraform -chdir=bootstrap output -json github_actions_variables > vars.json
jq -r '.repository | to_entries[] | "\(.key) \(.value)"' vars.json |
  while read -r name value; do gh variable set "$name" --body "$value"; done
for env in lz-dev lz-pre lz-pro; do
  gh api -X PUT "repos/{owner}/{repo}/environments/${env}" >/dev/null
  gh variable set AZURE_CLIENT_ID_APPLY --env "$env" --body "$(jq -r ".environments[\"${env}\"].AZURE_CLIENT_ID_APPLY" vars.json)"
done
rm vars.json
```

Los revisores, las ramas permitidas de cada environment y las reglas se configuran en la interfaz de GitHub.

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
| azuread | ~> 3.10 |
| azurerm | ~> 5.12 |

## Resources

| Name | Type |
| ---- | ---- |
| [azuread_app_role_assignment.graph](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/app_role_assignment) | resource |
| [azurerm_federated_identity_credential.github](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/federated_identity_credential) | resource |
| [azurerm_management_lock.state](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/management_lock) | resource |
| [azurerm_resource_group.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group) | resource |
| [azurerm_role_assignment.azure](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.rbac_admin](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.state](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.state_admins](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_storage_account.state](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_account) | resource |
| [azurerm_storage_container.state](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_container) | resource |
| [azurerm_user_assigned_identity.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |
| [azuread_service_principal.msgraph](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/data-sources/service_principal) | data source |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| github\_repository | GitHub repository (owner/name) whose workflows may use the pipeline identities. | `string` | n/a | yes |
| landing\_zones\_management\_group\_id | Name (ID) of the management group that contains every project subscription. The pipeline identities get their Azure roles here. | `string` | n/a | yes |
| log\_analytics\_workspace\_id | Resource ID of the central Log Analytics workspace (log\_analytics\_workspace\_id in platform.yaml). | `string` | n/a | yes |
| organization | Short organization code used in resource names (2-8 lowercase letters or digits). The state storage account name must be globally unique. | `string` | n/a | yes |
| state\_admins\_group\_object\_id | Object ID of the Entra ID group of platform administrators. It gets Storage Blob Data Contributor on the state account (bootstrap state migration and break-glass recovery). The person running the bootstrap must be a member. | `string` | n/a | yes |
| subscription\_id | Subscription that hosts the Terraform state and the pipeline identities (platform management subscription). | `string` | n/a | yes |
| tags | Business tags for the bootstrap resources. cost\_center, business\_owner and technical\_owner are mandatory and cannot be blank. | `map(string)` | n/a | yes |
| environments | Environments that get a GitHub environment (<github\_environment\_prefix><env>) trusted by the apply identity. | `list(string)` | <pre>[<br/>  "dev",<br/>  "pre",<br/>  "pro"<br/>]</pre> | no |
| github\_environment\_prefix | Prefix of the GitHub environments that protect apply jobs. | `string` | `"lz-"` | no |
| hub\_virtual\_network\_ids | Resource IDs of the hub VNets listed in projects/\_platform/platform.yaml. The apply identity needs them to create the hub side of each peering. | `list(string)` | `[]` | no |
| location | Region of the bootstrap resources. Must be a region of engine/catalog/catalog.yaml. | `string` | `"westeurope"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| bootstrap\_backend\_hcl | Content of bootstrap/backend.hcl, used to migrate and later reuse the bootstrap state. |
| github\_actions\_variables | Values to create as GitHub Actions variables (not secrets: none of them is confidential). |
| identities | Client IDs and principal IDs of the pipeline identities. |
| state\_backend | Backend settings for project roots. The key is <business\_unit>/<project>/<environment>.tfstate. |
<!-- END_TF_DOCS -->
