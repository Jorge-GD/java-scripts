# Ayuda. Si un lote falla

Que un lote falle es normal y no rompe nada: el script lo deshace entero y el worktree queda como estaba.

## Qué significa cada mensaje

| Mensaje | Qué ha pasado | Qué hace el script |
|---|---|---|
| `NO PASA:` | El lote no cumple una comprobación. El mensaje dice cuál. | Reintenta, diciéndole a Copilot el motivo. |
| `Lote ... DESHECHO` | Ha agotado los intentos. | Deshace el lote y lo reintenta fichero a fichero. |
| `ATASCADO` | Un fichero no sale ni solo. | Lo apunta en `.rescate\atascados.md` y sigue con los demás. |
| `PARO:` | Varios lotes deshechos seguidos. | Se detiene. |
| `ALTO:` | Alguien ha modificado la plantilla o el original. | Deshace el lote y se detiene. Hay que restaurarlos. |

## Dónde mirar

- `.rescate\lote-<paso>-<n>-<i>.log`: lo que contestó Copilot en ese intento.
- `.rescate\prompt.md`: lo último que se le pidió, con la corrección.
- `.rescate\build.log`: la salida de Maven.
- `.rescate\atascados.md`: los ficheros atascados y el motivo.

## Qué probar, de menos a más

1. Lotes de un fichero: `-Lote 1`.
2. Más esfuerzo: `-Esfuerzo high`.
3. Un modelo de reserva: `-ModeloB <id>`. El script lo usa solo cuando el principal se atasca.
4. Corregir el plan a mano, si el fallo viene de una decisión del plan.
5. Arreglar ese fichero a mano en el worktree, hacer commit ahí y repetir el diagnóstico.

## Si es un `PARO`

Casi siempre es el entorno y no el código: un parámetro que esta versión de Copilot no conoce, o Maven que no arranca. Lee el registro del último lote. Si es eso, sigue en `guia/si-el-script-falla.md`.

Cuando esté resuelto, vuelve al fichero del paso en el que estabas.
