# Changelog del motor

Formato [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y [SemVer](https://semver.org/lang/es/).
Cada versión publicada se etiqueta `engine/vX.Y.Z` y es la que fijan los proyectos en `engine_version`.
Política de versiones, deprecaciones y cambios incompatibles: [ADR-0003](../docs/adr/0003-engine-versioning.md). Cómo publicar: [contribuir al motor](../docs/contribuir-motor.md#publicar-una-versión).

## Versiones soportadas

| Versión | Estado | Terraform | azurerm | azuread |
|---|---|---|---|---|
| 1.0.x | Soportada | 1.17.1 | 5.13.0 | 3.10.0 |

## [Sin publicar]

### Cambiado
- El repositorio pasa a llamarse `azure-landing-zone-engine`: se actualiza el `$id` de los esquemas JSON.

## [1.0.0] - 2026-11-08

Primera versión.

### Añadido
- **Formato del proyecto:**
  - un YAML por proyecto y entorno en `projects/<business_unit>/<project>/<environment>.yaml`, con esquema JSON draft-07 (`schema/project.schema.json`) compatible con Backstage;
  - las referencias de plataforma (hubs y Log Analytics) van en `projects/_platform/platform.yaml`, con su propio esquema;
  - campos: `engine_version`, `business_unit`, `project`, `environment`, `subscription_id`, `location`, `tags`, `access`, `network`, `monitoring` y `overrides`.
- **Catálogo** (`catalog/catalog.yaml`): regiones (`westeurope`, `northeurope`, `spaincentral`), entornos, roles asignables, delegaciones, service endpoints, aliases de direcciones y resource providers.
- **Módulos:**
  - `naming-tags`: nombres CAF y etiquetas obligatorias más las del motor;
  - `resource-group-rbac`: resource group, grupos de seguridad de Entra ID creados por el motor, miembros no exclusivos y roles del catálogo asignados solo a grupos;
  - `network`: VNet, subnets sin salida implícita, un NSG por subnet con prioridades automáticas, ruta por defecto al firewall del hub y peering en los dos sentidos;
  - `monitoring`: Activity Log de la suscripción y diagnósticos de la VNet y los NSG hacia el Log Analytics central.
- **Root module** (`root/`): lee y normaliza el YAML, resuelve aliases, elige el hub del entorno y la región y hereda sus DNS. Comprueba ruta, versión, región, nombres únicos, hub, delegaciones, direcciones y overrides, y detiene el plan con mensajes que señalan el fichero.
- **Ejemplos** `minimal`, `webapp` y `sandbox`, probados con planes simulados.
- **Pipeline** (GitHub Actions, OIDC, actions fijadas por SHA):
  - PR: validación con el esquema de cada `engine_version`, comprobaciones entre proyectos, plan comentado en la PR y bloqueo de borrados;
  - `main`: plan, aprobación por environment y apply que no aplica si el plan ha cambiado;
  - motor: pre-commit, `terraform test`, plan de los ejemplos y publicación de versiones.
