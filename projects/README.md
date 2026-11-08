# projects

Un fichero por proyecto y entorno: `projects/<business_unit>/<project>/<environment>.yaml`.

- Cómo dar de alta o cambiar un proyecto: [guía de alta](../docs/guia-alta-proyecto.md).
- Qué significa cada campo: [referencia del YAML](../docs/referencia-yaml.md).
- Ficheros de ejemplo para copiar: [engine/examples](../engine/examples/).

`_platform/platform.yaml` contiene los hubs y el Log Analytics central. Es del equipo de plataforma y lo leen todos los proyectos: si cambia, el pipeline vuelve a planificar todos.

No borres ni renombres un fichero: la pull request fallará, porque eso no destruye nada en Azure. Para dar de baja un proyecto, sigue la sección [Dar de baja un proyecto](../docs/guia-alta-proyecto.md#dar-de-baja-un-proyecto).
