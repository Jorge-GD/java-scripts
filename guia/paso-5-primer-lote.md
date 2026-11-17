# Paso 5. Primer lote

**Qué se consigue:** ver un arreglo pequeño de principio a fin y decidir si el resultado convence.
**¿Cambia algo?** Sí, pero solo en el worktree `<REPO>-rescate`, en commits locales. La carpeta original no cambia y no hay push.

## Qué hacer

`.\rescate.ps1 -Modo fix -Repo <REPO> -Plantilla <PLANTILLA> -Legacy <ORIGINAL> -Paso <PASO> -Lote 2 -Modelo <MODELO> -Esfuerzo medium`

Sin `-Todo` y sin `-Auto`: así el script para después de cada lote.

Antes de lanzarlo, explica lo que va a pasar:

1. El script repite el diagnóstico.
2. Coge dos ficheros con hallazgos y se los pasa a Copilot junto con el plan.
3. Vuelve a diagnosticar y decide si el lote vale: compila, bajan los hallazgos del paso, no empeoran los pasos anteriores, el código nuevo no añade hallazgos de calidad, no se han borrado tests y nadie ha tocado la plantilla ni el original.
4. Si vale, hace un commit. Si no, reintenta con el motivo y, si sigue mal, deshace el lote.

El script hace preguntas por teclado. Dile antes cuáles son:

- Si el worktree todavía no existe (porque este paso no lleva plan), lo crea ahora y pide confirmación. Explica primero qué es: otra carpeta del mismo repo, con otra rama.
- Si el paso lleva plan, lo enseña y espera: `[Enter] seguir con los lotes | n = parar aqui`.
- Al acabar cada lote: `[Enter] siguiente lote | n = parar aqui | d = deshacer este lote y parar`.

Al acabar el primer lote, que conteste `n` para parar y revisar.

## Qué mirar

- `git -C <REPO>-rescate show --stat HEAD`: qué ficheros ha tocado.
- `git -C <REPO>-rescate show HEAD`: el cambio entero. Léelo con la persona.
- ¿Solo ha cambiado lo que pedía el lote?
- ¿La lógica está intacta? En `estructura` solo deben cambiar el paquete y los imports.
- ¿Los tests se han movido junto con su clase?
- ¿Hay líneas `REVISA:` en la salida? Son cosas que el script deja pasar pero quiere que mire una persona.

Si el lote no convence:

`.\rescate.ps1 -Modo deshacer -Repo <REPO>`

Si el lote no ha pasado las comprobaciones, lee `guia/si-un-lote-falla.md`.

## Cuándo está cerrado

- La persona ha leído el cambio y lo entiende.
- Ha decidido si el lote se queda o se deshace.

Apúntalo en la bitácora. Siguiente: `guia/paso-6-resto.md`.
