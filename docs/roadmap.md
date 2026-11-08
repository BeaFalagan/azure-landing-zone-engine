# Roadmap

Lo que queda fuera de la primera versión del motor para mantenerlo simple. Cada punto entra como una versión MINOR o MAJOR según [ADR-0003](adr/0003-engine-versioning.md).

## Nuevos dominios

Mismo patrón que los dominios actuales: un bloque opcional en el YAML, un módulo en `engine/modules/`, entradas de catálogo y tests.

| Dominio | Bloque YAML previsto | Notas |
|---|---|---|
| Máquinas virtuales | `virtual_machines` | Tallas e imágenes desde catálogo, sin IP pública, acceso por Bastion del hub |
| AKS | `kubernetes` | Clúster privado, Azure CNI overlay, integración con Entra ID |
| PostgreSQL Flexible Server | `postgresql` | Usa la subnet con `delegation: postgresql` y la zona DNS privada de plataforma |
| Firewall propio del proyecto | `firewall` | Solo para casos sin hub; por defecto la salida va por el firewall del hub |
| VPN propia | `vpn` | Igual: excepcional, la conectividad híbrida es del hub |
| Private endpoints | `private_endpoints` | Con zonas DNS privadas de plataforma |

## Plataforma y ciclo de vida

- **Baja de proyectos (`decommission`)**: borrar un YAML no destruye nada; la PR falla con instrucciones. Se añadirá un flujo explícito (`decommission: true`, plan de destrucción aprobado y borrado del YAML después).
- **Subscription vending**: crear la suscripción desde el YAML (hoy la entrega el equipo de plataforma).
- **Presupuestos y alertas de coste** por proyecto.
- **IPAM**: asignación automática de `address_space`.
- **Varias regiones** por proyecto.
- **Una identidad apply por entorno** para separar más producción.
- **Runners privados** y state sin endpoint público; claves gestionadas por el cliente (CMK) en el state.
- **Detección de drift** programada.
- **Renovate** para proponer PRs de `engine_version`.
- **Terraform Policy** (GA en Terraform 1.17) para reglas sobre el plan.

## Backstage

Software Template que:
1. reutiliza `engine/schema/project.schema.json` como `parameters` del formulario (draft-07, compatible con el validador ajv8 del scaffolder);
2. genera `projects/<bu>/<project>/<env>.yaml` con `fetch:template`;
3. abre la PR con `publish:github:pull-request`, que recorre el mismo flujo de validación, plan y aprobación que una PR manual.
