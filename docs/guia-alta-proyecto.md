# Guía de alta de proyectos

Esta guía explica cómo dar de alta un proyecto en Azure, cómo cambiarlo y cómo resolver los errores más habituales. No hace falta saber Terraform: solo vas a editar un fichero YAML y abrir una pull request (PR). El pipeline hace el resto y te enseña lo que va a cambiar antes de tocar nada.

Cada campo del fichero está explicado en la [referencia del YAML](referencia-yaml.md).

## Conceptos en 1 minuto

- **Un fichero = un proyecto en un entorno.** `projects/pga/billing/dev.yaml` es el proyecto `billing` de la unidad de negocio `pga` en desarrollo. Su versión de producción es otro fichero, `pro.yaml`, con su propia suscripción.
- **El fichero es la fuente de verdad.** Lo que no esté en el YAML no lo gestiona el motor. Si alguien cambia a mano algo que sí gestiona, el siguiente despliegue lo devuelve a lo que dice el fichero.
- **Plan.** Es la lista de lo que se va a crear, cambiar o destruir. Lo ves como comentario en tu PR antes de que se aplique nada.
- **`engine_version`.** Es la versión del motor que despliega tu fichero. No cambia sola: la subes tú cuando quieras usar una versión nueva.

## Antes de empezar

Pide al equipo de plataforma:

| Dato | Campo del YAML | Ejemplo |
|---|---|---|
| Código de tu unidad de negocio (2-6 caracteres) | `business_unit` | `pga` |
| Una suscripción para cada entorno | `subscription_id` | `3f2b…` |
| Un rango de IP libre, solo si necesitas red | `network.address_space` | `10.48.48.0/20` |

Necesitas además:
- un nombre corto para el proyecto (`project`, 2-14 letras minúsculas o dígitos);
- un centro de coste (`cost_center`);
- los correos de las personas responsables de negocio y técnica.

## Paso a paso

### 1. Crea el fichero

Copia el ejemplo que más se parezca a lo que necesitas ([ejemplos](../engine/examples/)):

| Ejemplo | Cuándo |
|---|---|
| `minimal` | Solo un resource group con etiquetas y monitorización |
| `webapp` | Grupos de acceso, red conectada al hub, subnets para App Service y PostgreSQL |
| `sandbox` | Red aislada, sin hub (pruebas) |

```bash
git switch -c alta-pga-billing-dev
mkdir -p projects/pga/billing
cp engine/examples/projects/demo/webapp/pro.yaml projects/pga/billing/dev.yaml
```

La ruta tiene reglas: todo en minúsculas y el nombre del fichero debe ser `dev.yaml`, `pre.yaml` o `pro.yaml`.

### 2. Edita los campos

Edita como mínimo:
1. `business_unit`, `project` y `environment`, que deben coincidir **exactamente** con la ruta;
2. `subscription_id`;
3. las etiquetas de `tags`;
4. `access`: los grupos de Entra ID que se crearán, con sus roles y sus personas;
5. `network`: tu `address_space` y subnets cuyo `prefix` caiga dentro de él. Si no necesitas red, borra el bloque entero.

Cambia también la línea `# yaml-language-server: $schema=...` por `../../../engine/schema/project.schema.json`. Con la extensión YAML de VS Code tendrás autocompletado y los errores subrayados mientras escribes.

### 3. Valida en local (opcional, recomendado)

```bash
pre-commit run --files projects/pga/billing/dev.yaml
```

Comprueba el esquema de tu `engine_version`, el formato YAML y que no compartes suscripción ni rango de IP con otro proyecto. Si no tienes pre-commit instalado, el pipeline hace lo mismo en la PR.

### 4. Abre la pull request

```bash
git add projects/pga/billing/dev.yaml
git commit -m "Alta de pga/billing/dev"
git push -u origin alta-pga-billing-dev
```

Abre la PR contra `main`. En uno o dos minutos aparecerán comentarios del pipeline:
- **❌ Project checks failed.** Hay que corregir el fichero; el comentario dice qué campo falla. Corrige, haz commit y push, y el comentario se actualiza.
- **✅ `projects/pga/billing/dev.yaml`.** Es el plan. Revísalo (siguiente paso).

### 5. Revisa el plan

El comentario resume, por ejemplo, **12 to add, 0 to change, 0 to destroy**. En un alta todo debe ser *add*.

- **Si aparece "This plan destroys or replaces resources", para.** Algo se va a borrar o a recrear. Suele pasar al cambiar la región, los nombres (`business_unit`, `project`) o el `prefix` de una subnet. Si no es lo que quieres, deshaz ese cambio.
- **Despliega "Full plan" para ver el detalle.** La salida `configuration` muestra lo que el motor ha entendido de tu YAML: nombres finales, etiquetas, reglas NSG con sus prioridades y hub elegido.

### 6. Revisión, fusión y aprobación

1. Los revisores de CODEOWNERS de tu unidad de negocio aprueban la PR y se fusiona.
2. En `main` se repite el plan y espera aprobación en el environment `lz-<entorno>`. La aprueba una persona revisora de ese entorno; en `pro` revisa el equipo de plataforma.
3. Tras la aprobación se aplica. El resultado aparece en el resumen del run (pestaña **Actions**).

Los nombres que se crean siguen siempre la misma regla. Con `pga/billing/dev` en `westeurope` serían estos:

| Recurso | Nombre |
|---|---|
| Resource group | `rg-pga-billing-dev-weu` |
| Grupo de Entra ID `developers` | `sg-az-pga-billing-dev-developers` |
| VNet | `vnet-pga-billing-dev-weu` |
| Subnet `app` y su NSG | `snet-app`, `nsg-pga-billing-dev-weu-app` |

## Cambios habituales

Todos siguen el mismo camino: editar el YAML, abrir la PR, revisar el plan y fusionar.

| Quiero… | Cambio en el YAML | Qué esperar en el plan |
|---|---|---|
| Dar acceso a una persona | Añadir su UPN a `members` del grupo | 1 to add (miembro del grupo) |
| Un grupo nuevo con otro rol | Nueva entrada en `access` | Grupo + asignaciones de rol |
| Abrir un puerto | Nueva regla en `nsg_rules` de la subnet | 1 to add (regla) |
| Una subnet nueva | Nueva entrada en `subnets`, dentro del `address_space` | Subnet, NSG y asociaciones |
| Pasar de `dev` a `pre` | Copiar `dev.yaml` a `pre.yaml` y cambiar `environment`, `subscription_id` y rangos de IP | Un alta completa en otra suscripción |
| Usar una versión nueva del motor | Cambiar `engine_version` (lee antes el [CHANGELOG](../engine/CHANGELOG.md)) | Depende de la versión: una MINOR o una PATCH no deberían destruir nada |

Quitar a una persona de `members` la saca del grupo. Las personas que se añadan al grupo a mano, fuera del YAML, no se tocan.

## Errores frecuentes

Los mensajes aparecen en el comentario de la PR. Los del esquema indican la ruta del campo (`network.subnets[1].prefix` es el `prefix` de la **segunda** subnet, porque se cuenta desde 0).

| Mensaje (resumen) | Causa | Solución |
|---|---|---|
| `'TCP' is not one of ['tcp', 'udp', 'icmp', 'any']` | Valor fuera de la lista permitida (distingue mayúsculas) | Usa uno de los valores que indica el mensaje |
| `'10.48.49.0/33' is not a valid CIDR (example: 10.48.48.0/24)` | Rango IP mal escrito | Formato `a.b.c.d/n`, con `n` entre 0 y 32 |
| `Additional properties are not allowed ('adress_space' was unexpected)` | Campo mal escrito o en el sitio equivocado | Revisa el nombre y la sangría. Ver [referencia](referencia-yaml.md) |
| `'cost_center' is a required property` | Falta un campo obligatorio | Añádelo |
| `the path must be projects/pga/billing/dev.yaml` | `business_unit`, `project` o `environment` no coinciden con la ruta | Haz que coincidan ruta y contenido |
| `is not a valid project file. Project files live at projects/<business_unit>/<project>/<environment>.yaml` | Ruta o nombre de fichero no válidos (`prod.yaml`, mayúsculas, `.yml`…) | Mueve el fichero a una ruta válida |
| `engine_version '1.4.0' is not a published engine version` | Esa versión no existe (todavía) | Usa una de las versiones que lista el mensaje |
| `subscription … is used by projects/…, projects/…` | Dos ficheros con la misma suscripción | Cada proyecto y entorno necesita la suya: pídela a plataforma |
| `projects/a/b/dev.yaml (10.48.48.0/20) overlaps projects/c/d/dev.yaml (…)` | Tu rango IP lo usa otro proyecto o un hub | Pide un rango libre a plataforma |
| `Every subnet prefix must be inside the VNet address_space` | Una subnet se sale del rango de la VNet | Ajusta el `prefix` |
| `Subnet prefixes overlap with each other` | Dos subnets comparten direcciones | Usa rangos distintos (por ejemplo, `.48.0/24` y `.49.0/24`) |
| `Each subnet prefix must be a valid CIDR written as a network address, /29 or larger` | `10.48.48.10/24` no es una dirección de red, o la subnet es menor que /29 | Escribe la dirección de red (`10.48.48.0/24`) |
| `peer_to_hub is true but projects/_platform/platform.yaml has 0 hubs for environment 'pre'…` | No hay hub en tu entorno y región | Pídelo a plataforma o pon `peer_to_hub: false` |
| `NSG rules use the hub alias, but the network is not peered to a hub` | Usas `source: hub` en una red sin hub | Usa un CIDR o conecta la red al hub |
| `Two NSG rules of the same subnet and direction end up with the same priority` | Una `priority` explícita coincide con otra | Quita la `priority` (se asigna sola) o cambia el valor |
| `subnet names must be unique (repeated: app)` / `access names must be unique` | Nombre repetido en la lista | Cambia uno de los nombres |
| Error en `data.azuread_user.members` con el correo de una persona (en el plan) | Ese UPN no existe en Entra ID | Corrige el correo: debe ser el UPN con el que la persona inicia sesión |
| `was deleted. Deleting a project file never destroys its resources` | Has borrado o renombrado un YAML | Restaura el fichero (ver la sección siguiente) |
| `The plan changed after it was shown for approval` | Otro cambio llegó a `main` o a Azure entre el plan y la aprobación | Relanza el run con **Re-run all jobs** (no *failed jobs*), revisa el plan nuevo y aprueba otra vez |

Si un error no está en la tabla, el mensaje casi siempre empieza por la ruta de tu fichero y dice qué hacer. Si no queda claro, pregunta al equipo de plataforma con el enlace a la PR.

## Lo que no se puede hacer (y por qué)

- **Renombrar** la unidad de negocio, el proyecto o el entorno. La ruta del fichero es la clave del state y forma parte de los nombres de todos los recursos. Si hace falta, se da de alta un proyecto nuevo y se da de baja el antiguo.
- **Asignar roles fuera del catálogo**, como Owner o User Access Administrator. El pipeline no tiene permiso para hacerlo: los equipos no pueden repartir permisos de administración.
- **Compartir suscripción o rango de IP** con otro proyecto.
- **Cambiar recursos a mano** en el portal si los gestiona el motor. El siguiente despliegue deshará el cambio.

## Dar de baja un proyecto

Borrar un YAML **no destruye nada**: los recursos seguirían en Azure, sin dueño y facturando. Por eso la PR que borra un fichero falla a propósito. Una baja es un proceso explícito:

1. Abre una petición al equipo de plataforma con el fichero (`projects/pga/billing/dev.yaml`), el motivo y la confirmación de la persona responsable de negocio (`business_owner`).
2. El equipo de plataforma genera un plan de destrucción, lo revisa con la persona responsable y lo aplica. Es un procedimiento manual con sus credenciales ([contribuir al motor](contribuir-motor.md#baja-de-un-proyecto)). Después la suscripción vuelve a plataforma.
3. Cuando el state está vacío, se fusiona la PR que borra el YAML. La fusiona el equipo de plataforma, saltándose la comprobación de borrado.

Un flujo automático de baja (`decommission: true`) está en el [roadmap](roadmap.md).
