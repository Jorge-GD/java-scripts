# Paso 6. Resto de lotes y de pasos

**Qué se consigue:** dejar a 0 el paso empezado y repetir el ciclo con los siguientes.
**¿Cambia algo?** Sí, solo en el worktree, en commits locales.

## Qué hacer

1. Repite el comando del primer lote. El script sigue por donde iba:

   `.\rescate.ps1 -Modo fix -Repo <REPO> -Plantilla <PLANTILLA> -Legacy <ORIGINAL> -Paso <PASO> -Lote 2 -Modelo <MODELO> -Esfuerzo medium`

2. Revisa cada lote igual que el primero, aunque sea más rápido: qué ficheros ha tocado y si hay líneas `REVISA:`.
3. Cuando el paso quede a 0, repite el diagnóstico:

   `.\rescate.ps1 -Repo <REPO> -Plantilla <PLANTILLA>`

   Mientras exista el worktree, el diagnóstico mira el worktree, no la carpeta original.
4. Si quedan pasos con errores, vuelve a `guia/paso-4-plan.md` con el siguiente del orden.

## Cuándo ir más deprisa

- Con dos o tres lotes buenos seguidos, se puede subir a `-Lote 5`.
- Cuando un paso entero haya ido bien, se puede añadir `-Auto` para no parar entre lotes.
- `-Todo` encadena todos los pasos sin parar. Solo cuando dos pasos enteros hayan ido bien y la persona lo decida.
- El paso `calidad` puede hacer muchas llamadas a Copilot en un repo grande. Avisa antes de empezarlo.

Ir más deprisa es revisar menos. Dilo cada vez que lo propongas.

## Si un lote falla

Lee `guia/si-un-lote-falla.md`.

## Cuándo está cerrado

- El diagnóstico no tiene errores en los pasos que la persona quería hacer, o los que quedan están apuntados como atascados.

Apúntalo en la bitácora, con la tabla final. Siguiente: `guia/paso-7-cierre.md`.
