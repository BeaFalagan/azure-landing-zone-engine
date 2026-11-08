# Ejemplos de proyectos

Ficheros listos para copiar a `projects/<business_unit>/<project>/<environment>.yaml`. Los tres se validan con el esquema en pre-commit y los prueba `engine/root/tests` con un plan simulado.

| Ejemplo | Para qué |
|---|---|
| [minimal](projects/demo/minimal/dev.yaml) | Lo mínimo: resource group con etiquetas y Activity Log al Log Analytics central |
| [webapp](projects/demo/webapp/pro.yaml) | Proyecto completo: grupos de acceso con miembros, red conectada al hub, subnet de App Service, subnet de PostgreSQL y reglas NSG |
| [sandbox](projects/demo/sandbox/dev.yaml) | Red aislada (`peer_to_hub: false`) y sin monitorización central |

Al copiar un ejemplo hay que cambiar:
- `business_unit`, `project` y `environment`, que deben coincidir con la ruta;
- `subscription_id` y `network.address_space`, que entrega el equipo de plataforma;
- las etiquetas;
- los rangos de las subnets, que deben caer dentro del `address_space`.

La línea `# yaml-language-server: $schema=...` activa el autocompletado y la validación en editores con la extensión YAML. En `projects/`, la ruta relativa es `../../../engine/schema/project.schema.json`.

[platform.yaml](platform.yaml) es una copia con IDs ficticios para los tests; el real es `projects/_platform/platform.yaml`.
