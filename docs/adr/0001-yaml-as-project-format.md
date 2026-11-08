---
status: aceptado
date: 2026-11-05
decision-makers: Platform Engineering
---

# YAML como formato de los proyectos (frente a tfvars y JSON)

## Contexto y problema

Los equipos que dan de alta proyectos son perfiles junior o no técnicos, y en el futuro un portal Backstage generará los ficheros. ¿En qué formato se escriben los datos de un proyecto?

## Opciones consideradas

1. YAML validado con JSON Schema y leído con `yamldecode`
2. `.tfvars` (HCL)
3. JSON

## Decisión

Opción **1**.

- Es legible y admite comentarios, así que se puede copiar un ejemplo y cambiar unos pocos valores.
- Se valida con un JSON Schema **antes** de ejecutar Terraform. Ese mismo esquema genera el formulario de Backstage y el autocompletado del editor (YAML Language Server).
- Se usa YAML plano: sin anchors, aliases, merge keys, tags ni claves duplicadas (lo comprueba `scripts/check_plain_yaml.py`).

### Consecuencias

- Positiva: un único formato para personas, portal y CI; errores con mensaje y ruta del campo antes del plan.
- Negativa: YAML tiene trampas de tipos (`no`, `on`, `08`). Se mitigan con el esquema (tipos estrictos) y con ejemplos que entrecomillan los valores ambiguos.
- Negativa: hay dos capas de validación (esquema y Terraform) que mantener alineadas ([ADR-0004](0004-two-layer-validation.md)).

## Pros y contras de las opciones

- **tfvars:** validación nativa con `validation`, pero exige saber HCL, no hay JSON Schema estándar para Backstage ni para editores, y los errores llegan tarde (en `plan`).
- **JSON:** se valida con el mismo esquema, pero no admite comentarios y es incómodo de editar a mano. Backstage podría generarlo, pero las personas no lo escribirían bien.
