---
status: aceptado
date: 2026-11-05
decision-makers: Platform Engineering
---

# Validación en dos capas y forma del YAML

## Contexto y problema

Los errores deben detectarse antes del plan y explicarse en términos del YAML. El mismo contrato tiene que servir a personas, editores, CI y al formulario de Backstage (React JSON Schema Form 5 con ajv8).

## Decisión

**Capa 1: JSON Schema draft-07** (`engine/schema/`), en pre-commit y en CI.
- Comprueba tipos, obligatorios, formatos (GUID, SemVer, email, CIDR, IPv4), longitudes y listas cerradas.
- Cada campo lleva `title`, `description`, `default` y `examples`.
- Se usa draft-07 porque es el dialecto por defecto del validador de Backstage.
- Cada proyecto se valida con el esquema **de su `engine_version`** (el del tag `engine/vX.Y.Z`), no con el de `main`, para que un proyecto fijado a una versión anterior no se rompa cuando el esquema evoluciona (`scripts/validate_project.py`).

**Capa 2: Terraform** (`validation`, `precondition`, `check`).
- Comprueba lo que el esquema no puede expresar: la ruta coincide con el contenido, la versión coincide, los nombres no se repiten, las subnets caen dentro del address space y no se solapan, los tags no quedan vacíos tras `trimspace` y existe un hub para el entorno y la región.

**Capa global: script en CI.** Comprueba los solapes de IP entre proyectos y que no haya una suscripción usada por dos proyectos.

**Forma del YAML:**
- Las colecciones son **listas de objetos con `name`**, no mapas, porque RJSF pinta bien los arrays y mal los `additionalProperties`. El motor las convierte en mapas.
- Las listas cerradas viven en `engine/catalog/catalog.yaml`. El esquema repite sus claves como `enum` y `scripts/check_schema_catalog.py` exige que coincidan.
- Las prioridades de las reglas NSG son automáticas por orden.
- Los nombres se generan siempre; el override es excepcional y exige `justification`.

### Consecuencias

- Positiva: la mayoría de errores aparecen en segundos con la ruta del campo, sin credenciales de Azure.
- Negativa: las enums están duplicadas entre catálogo y esquema. Lo cubre la comprobación de sincronía.
- Negativa: la unicidad de `name` en listas no se puede expresar en JSON Schema; la valida Terraform.
