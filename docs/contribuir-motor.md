# Contribuir al motor

Guía para quien cambia `engine/`, los scripts o el pipeline. Las decisiones de fondo están en los [ADRs](adr/). Esta guía explica el **cómo**.

## Principios

1. **Datos y motor separados.** El YAML no contiene lógica y el motor no contiene datos de proyectos. Nada genera ni copia código por proyecto.
2. **Simplicidad.** Un módulo por dominio, sin abstracciones "por si acaso". Antes de añadir una opción al YAML, pregunta si la mayoría de proyectos la necesita. Si no la necesitan, es un override o va al roadmap.
3. **Errores pensados para quien escribe el YAML.** Cada `validation` o `precondition` dice qué campo falla y cómo corregirlo. Los mensajes del root empiezan por la ruta del fichero.
4. **Nada toca Azure fuera del pipeline.** En local solo se usan `fmt`, `validate`, `init -backend=false`, linters y `terraform test` con providers simulados.

## Estructura del motor

| Ruta | Qué es | Quién la usa |
|---|---|---|
| `engine/VERSION` | Versión de `main` | Release, root (comprueba `engine_version`) |
| `engine/catalog/catalog.yaml` | Listas cerradas: regiones, roles (con GUID), delegaciones, service endpoints, aliases, resource providers | Root, esquema (enums), bootstrap (condición ABAC) |
| `engine/schema/` | JSON Schema draft-07 del proyecto y de la plataforma, con casos de prueba en `tests/` | pre-commit, CI, Backstage, editores |
| `engine/modules/` | Un módulo por dominio ([índice](../engine/modules/)) | Root |
| `engine/root/` | Lee el YAML, normaliza, comprueba y llama a los módulos | Pipeline |
| `engine/examples/` | Proyectos de ejemplo y `platform.yaml` ficticio | Tests, guía de alta |

## Entorno local

Herramientas: Terraform 1.17.1 (`.terraform-version`), tflint 0.65.0, terraform-docs 0.24.0, checkov 3.4.3, Python 3.11+ y pre-commit 4.

```bash
pre-commit install
pre-commit run --all-files     # todo lo que comprueba la CI salvo el plan de ejemplos
scripts/test-all.sh            # terraform test de bootstrap, módulos y root
scripts/plan-examples.sh       # plan simulado de cada ejemplo, con la salida completa
python3 scripts/test_schema.py # casos válidos e inválidos del esquema
python3 -m unittest discover -s scripts/tests -t scripts   # scripts del pipeline
```

## Cómo hacer los cambios habituales

### Añadir una entrada al catálogo (MINOR)

Por ejemplo, una región, un rol o una delegación.

1. Añádela en `engine/catalog/catalog.yaml`.
2. Añade la misma clave al `enum` correspondiente de `engine/schema/project.schema.json` (y a `enumNames` si lo tiene). `schema-catalog-sync` falla si no coinciden.
3. **Roles:** vuelve a aplicar el [bootstrap](../bootstrap/README.md) después de publicar. La condición ABAC solo permite asignar los roles del catálogo, así que hasta entonces el apply fallará al asignar el rol nuevo.
4. Actualiza [docs/referencia-yaml.md](referencia-yaml.md) y el CHANGELOG.

Quitar una entrada es **MAJOR**: algún proyecto puede estar usándola.

### Añadir un campo opcional al YAML (MINOR)

1. **Esquema:**
   - define el campo con `title`, `description`, `default` y `examples`, que son los textos que verá Backstage;
   - añade al menos un caso válido y uno inválido en `engine/schema/tests/project/`, con la cabecera `# expect:`.
2. **Root (`locals.tf`):**
   - lee el campo con su valor por defecto (`try(local.raw.x, <defecto>)`). Un proyecto antiguo que no lo tenga debe producir **el mismo plan**;
   - usa `try()` en lugar de un condicional para las listas: las listas YAML son tuplas cuyo tipo depende de su longitud.
3. **Módulo:** variable tipada con `optional()` y `validation`.
4. **Tests:** una aserción en el test del módulo y, si cambia la normalización, en `engine/root/tests/root.tftest.hcl`.
5. Si el campo es útil para copiar, añádelo a un ejemplo. Después actualiza la referencia del YAML y el CHANGELOG.

### Añadir un dominio nuevo (MINOR)

Por ejemplo, máquinas virtuales o PostgreSQL ([roadmap](roadmap.md)).

1. **Módulo** `engine/modules/<dominio>/` con la misma forma que los existentes:
   - `versions.tf` con rangos de providers, `variables.tf`, `main.tf` y `outputs.tf`;
   - `README.md` en español con el bloque de terraform-docs;
   - `examples/basic/` y `tests/` con `mock_provider` y `command = plan`.
2. **Esquema:** un bloque opcional de primer nivel, en `snake_case`, con las colecciones como listas de objetos con `name` ([ADR-0004](adr/0004-two-layer-validation.md)).
3. **Root:** normalización en `locals.tf`, llamada con `count` o `for_each` en `main.tf` (sin el bloque no se crea nada) y salidas en `outputs.tf`.
4. **Permisos:** si el dominio necesita roles nuevos para la identidad de apply, cambia el bootstrap.
5. Ejemplo, referencia del YAML y CHANGELOG.

### Cambios incompatibles (MAJOR)

Son MAJOR:
- renombrar o eliminar un campo;
- un campo obligatorio nuevo;
- un cambio de naming;
- quitar una entrada del catálogo;
- cualquier cambio que reemplace o destruya recursos existentes ([ADR-0003](adr/0003-engine-versioning.md)).

Cómo hacerlos:
- **Deprecación previa.** Marca el campo como obsoleto en su `description` y en el CHANGELOG, y añade un `check` en el root que avise mientras se use. Debe pasar al menos una MINOR antes de eliminarlo.
- **Bloques `moved`** para cualquier cambio de dirección de recurso.
- **Una guía de migración** en la sección de la versión del CHANGELOG.

## Publicar una versión

1. Elige el número según las reglas SemVer de [ADR-0003](adr/0003-engine-versioning.md).
2. En la misma PR:
   - cambia `engine/VERSION`;
   - convierte `## [Sin publicar]` en `## [X.Y.Z] - AAAA-MM-DD` y deja un `## [Sin publicar]` vacío encima;
   - actualiza `engine_version` en `engine/examples/projects/`, en los fixtures de `engine/root/tests/fixtures/` y en las aserciones de `engine/root/tests/root.tftest.hcl`. No cambies el fixture `oldversion`, que usa una versión antigua a propósito. Los casos de `engine/schema/tests/` no hace falta cambiarlos: el esquema solo comprueba el formato.
3. El job `version and changelog` de `engine-pr` comprueba tres cosas: que la versión sube, que no está publicada y que tiene su sección en el CHANGELOG.
4. Al fusionar, `engine-release` crea el tag `engine/vX.Y.Z` y la release con esa sección.
5. Los proyectos se actualizan con PR que cambian su `engine_version`, cada una con su plan.

Un tag publicado no se mueve ni se borra: si una versión tiene un fallo, se publica una PATCH.

## Pipeline

| Workflow | Cuándo | Qué hace |
|---|---|---|
| [`projects-pr`](../.github/workflows/projects-pr.yml) | Toda PR (actúa si cambia `projects/`) | Detecta los YAML cambiados y rechaza borrados. Valida YAML plano, esquema de su versión, suscripciones repetidas y solapes. Planifica con el motor del tag (identidad de plan, `-lock=false`, sin registrar resource providers) y comenta el plan |
| [`projects-apply`](../.github/workflows/projects-apply.yml) | Push a `main` en `projects/`, o manual con un fichero | Plan con la identidad de lectura y aprobación en `lz-<env>`. Después apply con la identidad de apply, que vuelve a planificar y no aplica si el plan cambió |
| [`engine-pr`](../.github/workflows/engine-pr.yml) | Toda PR (actúa si cambia el motor o las herramientas) | pre-commit completo, `terraform test`, plan simulado de los ejemplos y reglas de versión |
| [`engine-release`](../.github/workflows/engine-release.yml) | Cambio de `engine/VERSION` en `main` | Tag y release |

La lógica vive en scripts que se pueden ejecutar y probar en local, no en el YAML de los workflows:

| Script | Hace |
|---|---|
| `scripts/ci/changed_projects.py` | Detecta los ficheros afectados y construye la matriz del pipeline |
| `scripts/ci/run-engine.sh` | Checkout del tag, validación, plan y apply, e informe Markdown |
| `scripts/ci/check_release.py` | Reglas de versión |
| `scripts/ci/pr-comment.js` | Un comentario por proyecto, que se actualiza en cada push |
| `scripts/validate_project.py` | Esquema según `engine_version` |
| `scripts/check_cross_project.py` | Suscripciones repetidas y solapes de IP |

Las actions de terceros se fijan por **SHA de commit** con la versión en un comentario. Para actualizar una:

```bash
gh api repos/actions/checkout/releases/latest --jq .tag_name     # p. ej. v7.0.1
gh api repos/actions/checkout/commits/v7.0.1 --jq .sha            # SHA a fijar
```

La configuración de GitHub que no está en el código (environments, variables, reglas de rama y de tags) se describe en [bootstrap/README.md](../bootstrap/README.md#configurar-github).

## Actualizar dependencias

| Dependencia | Dónde | Cómo |
|---|---|---|
| Terraform | `.terraform-version`, `required_version` | Un proyecto usa la versión de Terraform de su tag, así que el cambio llega con la versión del motor |
| Providers | `versions.tf` (rangos) y lock files de `bootstrap/` y `engine/root/` | `scripts/lock-providers.sh` regenera los lock files multiplataforma. Lee el changelog del provider y anota la versión en el CHANGELOG |
| tflint, terraform-docs, checkov, pre-commit | `.tflint.hcl`, `.pre-commit-config.yaml`, `scripts/ci/requirements*.txt`, `engine-pr.yml` | Misma versión en todos los sitios. El checksum de terraform-docs está en `engine-pr.yml` |
| Actions | `.github/` | SHA nuevo, como se explica arriba |

## Checklist de revisión

- [ ] Un proyecto existente que no cambia su YAML obtiene el mismo plan, o el cambio es MAJOR y lo documenta.
- [ ] Los campos nuevos del esquema tienen `title`, `description`, `default` y `examples`, y casos de prueba.
- [ ] Los mensajes de error dicen qué campo corregir y cómo.
- [ ] Hay tests (módulo y/o root) y `pre-commit run --all-files` pasa.
- [ ] CHANGELOG, referencia del YAML y README del módulo están actualizados (terraform-docs lo hace solo).
- [ ] No hay secretos, IDs reales ni `terraform apply` fuera del pipeline.

## Baja de un proyecto

Procedimiento manual del equipo de plataforma mientras no exista el flujo automático ([roadmap](roadmap.md)). Requisitos:
- ser miembro del grupo de administradores del state;
- tener permisos de Owner o Contributor sobre la suscripción del proyecto y Network Contributor sobre el hub;
- en Entra ID, el rol Groups Administrator, porque los grupos son propiedad de la identidad de apply.

```bash
az login
ver=1.0.0   # engine_version del fichero
git worktree add --detach .engine "engine/v${ver}"
terraform -chdir=.engine/engine/root init \
  -backend-config=../../../bootstrap/backend.hcl \
  -backend-config=container_name=tfstate \
  -backend-config=key=pga/billing/dev.tfstate
terraform -chdir=.engine/engine/root plan -destroy -out=destroy.tfplan \
  -var project_file="$PWD/projects/pga/billing/dev.yaml" \
  -var platform_file="$PWD/projects/_platform/platform.yaml"
# Revisar el plan con la persona responsable (business_owner) y entonces:
terraform -chdir=.engine/engine/root apply destroy.tfplan
git worktree remove .engine
```

`bootstrap/backend.hcl` apunta al contenedor `bootstrap`; los dos `-backend-config` siguientes lo sustituyen por el contenedor y la clave del proyecto. Después, fusiona la PR que borra el YAML usando la excepción de la regla de rama (el check `projects-pr / result` falla con los borrados a propósito) y devuelve la suscripción.
