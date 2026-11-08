# Módulos del motor

Un módulo por dominio. Los llama `engine/root` con datos ya normalizados desde el YAML; no están pensados para usarse fuera del motor.

| Módulo | Qué crea | Providers |
|---|---|---|
| [naming-tags](naming-tags/) | Nada: calcula nombres y etiquetas | — |
| [resource-group-rbac](resource-group-rbac/) | Resource group, grupos de Entra ID, miembros y asignaciones de roles | azurerm, azuread |
| [network](network/) | VNet, subnets, NSG y reglas, tabla de rutas al firewall del hub, peering con el hub | azurerm, azurerm.hub |
| [monitoring](monitoring/) | Diagnostic settings hacia el Log Analytics central (Activity Log y recursos) | azurerm |

Convenciones comunes:
- Variables tipadas con `object()` y `optional()`, y `validation` con mensajes que explican cómo corregir el valor.
- Restricciones de providers como rango (`>= 5.12, < 6.0`): el root fija la versión exacta con su lock file.
- `examples/basic/` se valida con `terraform validate`; `tests/` usa providers simulados (`terraform test`, sin Azure).
- La interfaz de los módulos se versiona con el motor ([ADR-0003](../../docs/adr/0003-engine-versioning.md)): renombrar una variable o cambiar una dirección de recurso sin `moved` es un cambio MAJOR.
