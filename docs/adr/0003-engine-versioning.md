---
status: aceptado
date: 2026-11-05
decision-makers: Platform Engineering
---

# Versionado del motor con SemVer y pin exacto por proyecto

## Contexto y problema

El motor evoluciona, pero un proyecto en producción no debe cambiar solo porque se publique una versión nueva. ¿Cómo se versiona el motor y cómo elige cada proyecto su versión?

## Opciones consideradas

1. Tags `engine/vX.Y.Z` en este repositorio. Cada YAML fija `engine_version` y el pipeline hace checkout de ese tag para ejecutar su `engine/root`
2. Un root HCL por proyecto que llama a `engine/root` como módulo remoto con `?ref=`
3. Sin versiones: todos los proyectos usan `main`

## Decisión

Opción **1**.

- `engine/VERSION` contiene la versión de `main`. Al fusionar un cambio en `VERSION` se crea el tag y se exige la entrada en `engine/CHANGELOG.md`.
- El root comprueba que `engine_version` del YAML coincide con `engine/VERSION` del checkout, así que nunca se ejecuta una versión distinta de la declarada.
- Cada YAML se valida con el esquema **de su versión**, el de `engine/schema/` dentro del tag.

**Reglas SemVer** (la interfaz es el esquema YAML más el plan resultante):

| Cambio | Tipo |
|---|---|
| Campo opcional nuevo, nueva entrada de catálogo, nuevo módulo opcional | MINOR |
| Fix sin cambios de esquema ni de plan para proyectos existentes | PATCH |
| Campo eliminado o renombrado, nuevo campo obligatorio, entrada de catálogo eliminada, cambio de naming, cualquier cambio que reemplace o destruya recursos existentes | MAJOR |

**Deprecación:** un campo se marca como obsoleto en la descripción del esquema y en el CHANGELOG, y el root emite un `check` con aviso durante al menos una MINOR. Se elimina en la siguiente MAJOR. Las variables de módulos usan el atributo `deprecated`. Los cambios de dirección de recursos llevan bloques `moved`.

### Consecuencias

- Positiva: actualizar es explícito (una PR que cambia `engine_version`, con su plan) y el mismo código produce el mismo plan.
- Negativa: conviven varias versiones en uso. Se publica la tabla de versiones soportadas en el CHANGELOG y se automatizan las PR de actualización (roadmap: Renovate).
- Negativa: los fixes de seguridad no llegan solos. Hay que publicar una PATCH y actualizar los proyectos.

## Pros y contras de las opciones

- **Root HCL por proyecto:** es el mecanismo nativo de Terraform, pero vuelve a generar o copiar código por proyecto, que es justo lo que se quería eliminar.
- **Siempre `main`:** cada fusión del motor cambia todos los proyectos a la vez; descartado.
