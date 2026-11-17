# Paso 7. Cierre

**Qué se consigue:** revisar todo lo hecho de una vez y dejar claro qué está comprobado y qué no.
**¿Cambia algo?** No, salvo que la persona decida traer los cambios a su rama.

## Qué hacer

1. Diagnóstico final: `.\rescate.ps1 -Repo <REPO> -Plantilla <PLANTILLA>`
2. Build completo dentro del worktree `<REPO>-rescate`: `mvn -B verify` (o el `mvnw` del repo). El diagnóstico ya lanza los tests; esto añade el empaquetado y los tests de integración, si los hay.
3. Todo lo que ha cambiado, visto desde la carpeta original:

   `git -C <REPO> diff --stat <rama>...<rama-rescate>`

   El script dice el nombre de la rama de rescate al acabar cada `-Modo fix`.

## Qué mirar

- Los avisos del informe: no bloquean, pero alguien tiene que leerlos.
- `.rescate\atascados.md`: lo que la IA no supo arreglar.
- Las líneas `REVISA:` que hayan salido por el camino.

## Qué decide la persona

- Traer los cambios: `git -C <REPO> merge <rama-rescate>`, o subir la rama y abrir un PR. Tú no haces ninguna de las dos cosas.
- Borrar el worktree cuando ya no haga falta: `git -C <REPO> worktree remove <REPO>-rescate`. La rama se conserva.
- Si tenía cambios sin commit al empezar, van dentro de la rama de rescate, en el commit «foto». Antes del merge hay que guardarlos o descartarlos en la carpeta original.

## Qué queda sin comprobar

Dilo con claridad, sin suavizarlo:

- El script mide la forma: estructura, capas, configuración y Javadoc.
- No mide el comportamiento. Que la salida del batch sea igual a la del original hay que probarlo aparte, con ficheros de prueba y en el entorno de preproducción.
- Si se saltó el paso de la lista de jobs, `paridad` y `e2e` no están comprobados.

## Cuándo está cerrado

- La persona tiene una lista de lo comprobado y otra de lo pendiente, y puede explicárselas a quien apruebe la migración.

Apúntalo en la bitácora. Si por el camino falló algo del script o hubo hallazgos falsos, lee `guia/informe.md`.
