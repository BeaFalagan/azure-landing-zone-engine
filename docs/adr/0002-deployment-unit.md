---
status: aceptado
date: 2026-11-05
decision-makers: Platform Engineering
---

# Unidad de despliegue: proyecto × entorno = un root, un state, una suscripción

## Contexto y problema

Hay que decidir cuántos proyectos y entornos gestiona cada ejecución de Terraform y cómo se aíslan entre sí.

## Opciones consideradas

1. Un fichero `projects/<bu>/<project>/<env>.yaml`, ejecutado por un único root module (`engine/root`) con su propio state y suscripción
2. Un root por unidad de negocio con todos sus proyectos (`for_each`)
3. Un único root para toda la organización

## Decisión

Opción **1**.

- Backend parcial: `-backend-config=key=<bu>/<project>/<env>.tfstate`.
- La suscripción viene del YAML (`subscription_id`) y el provider se configura con ella. No hay providers dinámicos ni un provider por proyecto.
- Lo compartido (hub, Log Analytics) se lee de `projects/_platform/platform.yaml`, que tiene un esquema propio y es propiedad del equipo de plataforma.

### Consecuencias

- Positiva: un error o un bloqueo de state solo afecta a un proyecto y entorno. Los plans son pequeños y paralelizables y el permiso de revisión se asigna por carpeta (CODEOWNERS).
- Positiva: dev y pro del mismo proyecto se despliegan y aprueban por separado.
- Negativa: las comprobaciones entre proyectos (solapes de IP, suscripción repetida) no caben en Terraform. Se hacen con un script en CI ([ADR-0004](0004-two-layer-validation.md)).
- Negativa: cambiar `platform.yaml` o publicar una versión del motor que todos adopten implica muchos plans. Se asume.

## Pros y contras de las opciones

- **Root por BU:** menos states, pero un proyecto roto bloquea a toda la BU, y Terraform no admite `for_each` sobre providers con suscripciones distintas sin generar código.
- **Root único:** radio de impacto máximo y plans lentos; descartado.
