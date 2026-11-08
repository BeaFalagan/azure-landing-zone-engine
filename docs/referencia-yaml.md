# Referencia del YAML de proyecto

Describe cada campo de `projects/<business_unit>/<project>/<environment>.yaml` en la versión **1.0.0** del motor. La definición formal es el esquema [engine/schema/project.schema.json](../engine/schema/project.schema.json), y las listas cerradas (regiones, roles, delegaciones…) salen del [catálogo](../engine/catalog/catalog.yaml). Si esta página y el esquema no coinciden, manda el esquema.

Para el paso a paso, consulta la [guía de alta](guia-alta-proyecto.md).

## Reglas generales

- **YAML plano.** Un solo documento por fichero, sin anclas (`&`), alias (`*`), `<<`, etiquetas (`!!str`) ni claves repetidas.
- **Solo los campos de esta página.** Un campo desconocido o mal escrito es un error, no se ignora.
- **Distingue mayúsculas.** `tcp` es válido y `TCP` no.
- **Las listas de objetos se identifican por `name`.** El orden importa solo en `nsg_rules`, donde decide la prioridad.
- **Las comillas son opcionales** salvo en valores que YAML interpretaría de otra forma. Pon entre comillas `engine_version`, los GUID, los puertos y los códigos que empiezan por cero (`"0042"`).

## Campos de primer nivel

| Campo | Obligatorio | Tipo | Descripción |
|---|---|---|---|
| `engine_version` | sí | texto SemVer | Versión exacta del motor que despliega el fichero, p. ej. `"1.0.0"`. El pipeline usa el tag `engine/v<versión>` |
| `business_unit` | sí | texto | Código de la unidad de negocio: 2-6 caracteres, minúsculas y dígitos, empieza por letra. Igual a la primera carpeta |
| `project` | sí | texto | Nombre del proyecto: 2-14 caracteres, minúsculas y dígitos, empieza por letra. Igual a la segunda carpeta |
| `environment` | sí | `dev` \| `pre` \| `pro` | Igual al nombre del fichero |
| `subscription_id` | sí | GUID en minúsculas | Suscripción exclusiva de este proyecto y entorno. La entrega plataforma |
| `location` | sí | `westeurope` \| `northeurope` \| `spaincentral` | Región de todos los recursos. Cambiarla recrea todo |
| `tags` | sí | objeto | Etiquetas de negocio ([tags](#tags)) |
| `access` | no | lista | Grupos de Entra ID y roles ([access](#access)). Por defecto: ninguno |
| `network` | no | objeto | Red del proyecto ([network](#network)). Sin este bloque no se crea red |
| `monitoring` | no | objeto | Monitorización central ([monitoring](#monitoring)) |
| `overrides` | no | objeto | Excepcional: nombres que sustituyen a los generados ([overrides](#overrides)) |

## `tags`

Se aplican a todos los recursos.

| Campo | Obligatorio | Descripción |
|---|---|---|
| `cost_center` | sí | Centro de coste. No puede estar vacío |
| `business_owner` | sí | Correo de la persona responsable del proyecto |
| `technical_owner` | sí | Correo del contacto técnico (persona o buzón de equipo) |
| *(otras)* | no | Etiquetas libres. La clave va en minúsculas, dígitos y `_`, empieza por letra y tiene un máximo de 63 caracteres. El valor no puede estar vacío y tiene un máximo de 256 caracteres |

El motor añade siempre las etiquetas `business_unit`, `project`, `environment`, `managed_by = lz-engine`, `engine_version` y `source` (la ruta del YAML). Esas claves no se pueden usar en `tags`.

## `access`

Cada entrada crea un **grupo de seguridad de Entra ID** llamado `sg-az-<bu>-<project>-<env>-<name>` y le asigna sus roles sobre el resource group del proyecto.

| Campo | Obligatorio | Descripción |
|---|---|---|
| `name` | sí | Sufijo del grupo: 2-24 caracteres, minúsculas, dígitos y `-`. Único en el fichero |
| `description` | no | Descripción del grupo (máx. 200 caracteres) |
| `roles` | sí | Uno o más roles del catálogo, sin repetir |
| `members` | no | UPN de las personas que se añaden al grupo. Deben existir en Entra ID |

**Roles disponibles:** `Reader`, `Contributor`, `Monitoring Reader`, `Monitoring Contributor`, `Storage Blob Data Reader`, `Storage Blob Data Contributor`, `Key Vault Reader` y `Key Vault Secrets User`. Los roles que dan permisos de administración (Owner, User Access Administrator) no están disponibles a propósito.

La pertenencia **no es exclusiva**: el motor añade y quita a las personas de `members`, pero no toca a quien se haya añadido al grupo por otra vía.

```yaml
access:
  - name: readers
    roles: [Reader]
  - name: developers
    description: Equipo de desarrollo de billing
    roles: [Contributor, Key Vault Secrets User]
    members: [ana@example.com, luis@example.com]
```

## `network`

Crea una VNet con sus subnets. Cada subnet lleva un NSG propio. Las subnets **no tienen salida implícita a internet** (`default_outbound_access_enabled = false`).

| Campo | Obligatorio | Por defecto | Descripción |
|---|---|---|---|
| `address_space` | sí | — | Rangos CIDR de la VNet, que entrega plataforma. Se escriben como dirección de red (`10.48.48.0/20`, no `10.48.50.0/20`). No pueden solaparse con otro proyecto ni con un hub |
| `peer_to_hub` | no | `true` | Conecta la VNet al hub de su entorno y región ([hub](#conexión-al-hub)) |
| `dns_servers` | no | DNS del hub | Servidores DNS propios. Si se deja vacío, se usan los del hub cuando hay peering y el DNS de Azure cuando no lo hay |
| `subnets` | sí | — | Una o más subnets ([subnets](#subnets)) |

### Conexión al hub

Con `peer_to_hub: true` el motor busca en `projects/_platform/platform.yaml` el hub con el mismo `environment` y `location`, que debe ser exactamente uno. Después:
- crea el peering en los dos sentidos;
- usa la puerta de enlace VPN/ExpressRoute del hub si plataforma la ha habilitado (`use_remote_gateways`);
- si el hub declara un firewall, crea una tabla de rutas que envía todo el tráfico (`0.0.0.0/0`) a ese firewall en todas las subnets. Las salidas a internet se abren entonces en el firewall, y las pide el equipo de plataforma.

### `subnets`

| Campo | Obligatorio | Descripción |
|---|---|---|
| `name` | sí | 2-32 caracteres, minúsculas, dígitos y `-`. No acaba en `-`. Único en el fichero. El recurso se llama `snet-<name>` |
| `prefix` | sí | CIDR dentro del `address_space`, de /29 o más grande, escrito como dirección de red. No se solapa con otras subnets. Cambiarlo recrea la subnet |
| `service_endpoints` | no | `Microsoft.AzureCosmosDB`, `Microsoft.ContainerRegistry`, `Microsoft.EventHub`, `Microsoft.KeyVault`, `Microsoft.ServiceBus`, `Microsoft.Sql`, `Microsoft.Storage` y `Microsoft.Web` |
| `delegation` | no | Delega la subnet en un servicio: `app-service`, `container-apps`, `container-instances`, `mysql` o `postgresql` |
| `nsg_rules` | no | Reglas del NSG de la subnet ([nsg_rules](#nsg_rules)) |

### `nsg_rules`

| Campo | Obligatorio | Por defecto | Descripción |
|---|---|---|---|
| `name` | sí | — | 2-63 caracteres, minúsculas, dígitos y `-`. Único en la subnet |
| `direction` | sí | — | `inbound` \| `outbound` |
| `access` | sí | — | `allow` \| `deny` |
| `protocol` | sí | — | `tcp` \| `udp` \| `icmp` \| `any` |
| `source` | sí | — | Alias o CIDR ([direcciones](#direcciones)) |
| `destination` | no | `subnet` | Alias o CIDR |
| `ports` | no | `["*"]` | Puertos de destino como texto: `"443"`, `"8080-8090"` o `"*"` |
| `priority` | no | automática | Entre 100 y 4096. Solo para forzar un valor |

**Prioridades.** Si no se indican, valen `100 + 10 × posición` en la lista de la subnet: 100, 110, 120… Un número menor se evalúa antes. Dos reglas de la misma subnet y dirección no pueden acabar con la misma prioridad. Las reglas por defecto de Azure siguen activas por debajo; para bloquear el tráfico interno de la VNet hay que añadir una regla `deny` explícita, como en el ejemplo `webapp`.

#### Direcciones

`source` y `destination` aceptan un CIDR (`10.48.48.0/24`) o uno de estos alias:

| Alias | Significado |
|---|---|
| `subnet` | El rango de la propia subnet |
| `vnet` | La VNet y las redes conectadas por peering (etiqueta `VirtualNetwork` de Azure) |
| `hub` | El `address_space` del hub. Requiere `peer_to_hub: true` |
| `internet` | Internet (etiqueta `Internet`) |
| `azure-lb` | Sondas del balanceador de Azure (`AzureLoadBalancer`) |
| `any` | Cualquier dirección (`*`) |

```yaml
network:
  address_space: ["10.48.48.0/20"]
  subnets:
    - name: app
      prefix: "10.48.48.0/24"
      delegation: app-service
      nsg_rules:
        - name: allow-https-from-hub
          direction: inbound
          access: allow
          protocol: tcp
          source: hub
          ports: ["443"]
```

## `monitoring`

| Campo | Por defecto | Descripción |
|---|---|---|
| `log_analytics` | `true` | Envía el Activity Log de la suscripción y los diagnósticos de la VNet y los NSG al Log Analytics central. Desactívalo solo en suscripciones de pruebas |

## `overrides`

Es excepcional: sirve para adoptar un recurso que ya existe con otro nombre. Lo revisa el equipo de plataforma.

| Campo | Descripción |
|---|---|
| `resource_group_name` | Nombre del resource group en lugar de `rg-<bu>-<project>-<env>-<región>` |
| `virtual_network_name` | Nombre de la VNet en lugar de `vnet-<bu>-<project>-<env>-<región>` |
| `justification` | Obligatorio si hay algún override; al menos 20 caracteres |

## Nombres generados

Con `<base> = <bu>-<project>-<env>-<región corta>`, donde la región corta es `weu`, `neu` o `spc`:

| Recurso | Nombre |
|---|---|
| Resource group | `rg-<base>` |
| VNet | `vnet-<base>` |
| Subnet | `snet-<name>` |
| NSG | `nsg-<base>-<subnet>` |
| Tabla de rutas | `rt-<base>` |
| Peerings | `peer-<bu>-<project>-<env>-to-hub`, `peer-hub-to-<bu>-<project>-<env>` |
| Grupo de Entra ID | `sg-az-<bu>-<project>-<env>-<name>` |
| Diagnostic settings | `diag-lz-engine` |

## Comprobaciones del motor

Además del esquema, el motor comprueba antes de planificar:
- que la ruta del fichero coincide con `business_unit`, `project` y `environment`;
- que `engine_version` coincide con la versión que se ejecuta;
- que los nombres no se repiten;
- los rangos IP y sus solapes;
- las prioridades de las reglas;
- que existe un hub cuando hace falta.

En la PR también se comprueba que ningún otro proyecto usa tu suscripción ni se solapa con tus rangos. Los mensajes de error y cómo resolverlos están en la [guía de alta](guia-alta-proyecto.md#errores-frecuentes).
