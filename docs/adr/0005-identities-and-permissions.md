---
status: aceptado
date: 2026-11-05
decision-makers: Platform Engineering
---

# Identidades del pipeline, grupos de Entra ID y acceso al state

## Contexto y problema

El pipeline debe desplegar sin secretos y crear grupos de Entra ID con roles, sin poder escalar privilegios. ¿Qué identidades hay, qué permisos tienen y cómo se accede al state?

## Decisión

**Identidades.** Dos UAMI federadas con GitHub Actions por OIDC, sin secretos ni certificados:
- **plan:** confía en las PR y en `main`. Es Reader en Azure y lectora en Graph.
- **apply:** confía solo en los environments protegidos `lz-<env>`, que tienen revisores obligatorios.

**Grupos y roles.**
- El motor **crea** los grupos (`sg-az-<bu>-<project>-<env>-<name>`) en lugar de referenciar grupos existentes, lo que evitaría un alta manual previa.
- La identidad apply tiene Graph `Group.Create` + `User.Read.All` y queda como owner de sus grupos, lo que le permite gestionar los miembros sin permisos de directorio amplios. Los permisos se conceden una vez, en el bootstrap, con consentimiento de administrador.
- La identidad apply tiene Role Based Access Control Administrator con **condición ABAC**: solo puede asignar o retirar los roles del catálogo, y solo a grupos. No puede darse Owner a sí misma ni a nadie.

**State.**
- Storage account con autenticación **solo Entra ID** (`shared_access_key_enabled = false`) y endpoint público, porque los runners hospedados por GitHub no tienen IP fija ni red privada.
- Contenedor `tfstate` para proyectos y contenedor `bootstrap` aparte.

### Consecuencias

- Positiva: no hay secretos que rotar. Un PR malicioso no puede aplicar (la identidad plan es de lectura) y la apply no puede escalar privilegios.
- Negativa: el bootstrap requiere Privileged Role Administrator en Entra ID una vez.
- Negativa: los grupos creados por el motor solo los gestiona el motor. Si se cambia de identidad apply, hay que transferir la propiedad.
- Negativa: el endpoint público del state se acepta mientras no haya runners privados (roadmap).
