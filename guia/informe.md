# Ayuda. Informe para quien mantiene el script

Si algo del script ha fallado o ha dado hallazgos falsos, prepara un texto corto para que la persona lo envíe. Con ese informe se corrige el script para la próxima vez.

## Qué no puede llevar

- Código del trabajo.
- Rutas reales, nombres de personas, de proyectos o de máquinas.
- Contraseñas, tokens ni hosts.

Cambia las rutas por `<REPO>`, `<PLANTILLA>` y `<ORIGINAL>`. Antes de dárselo a la persona, repásalo buscando justo esas cosas.

## Qué lleva

1. Versiones de PowerShell, git, Java, Maven y Copilot.
2. En qué paso de la guía estaba y el comando que lanzó.
3. El error tal cual sale en la consola.
4. La tabla de errores y avisos por paso del último diagnóstico.
5. Los hallazgos falsos: la regla y el patrón de código que la confunde, escrito con nombres inventados. Por ejemplo: «`javadoc-metodo` marca un método que sí tiene Javadoc cuando entre el Javadoc y el método hay un comentario de línea».
6. Si se cambió algo en `rescate.ps1` o en `.rescate\config.json` para seguir, qué se cambió.

Que quepa en una pantalla.
