# Ayuda. Si el script falla

Primero distingue qué ha fallado. No es lo mismo un fallo del entorno que un fallo del script.

| Qué ves | Qué es | Qué hacer |
|---|---|---|
| «No encuentro 'git'», Maven o Copilot no arrancan, PowerShell bloquea el script | Entorno | Arreglar la instalación o el PATH. No es el script. |
| Copilot rechaza un parámetro | Versión de Copilot | Quitar ese parámetro de `CopilotArgs` en `.rescate\config.json`. Si es `--effort`, lanzar sin `-Esfuerzo` ni `-EsfuerzoPlan`. |
| Error rojo de PowerShell con un número de línea de `rescate.ps1` | Fallo del script | Ver abajo. |
| El script acaba con un código distinto de 0 | Depende del código | Ver la tabla de códigos. |

## Ajustes sin tocar el script

`.rescate\config.json` cambia cualquier clave del bloque `CONFIGURACION` del script. Cada clave se escribe entera: sustituye a la del script.

Por ejemplo, si esta versión de Copilot no conoce `--no-ask-user`, se escribe la lista del script sin él:

```json
{ "CopilotArgs": ["-s", "--allow-all-tools", "--deny-tool=shell(git push)"] }
```

No quites `--deny-tool=shell(git push)`: es lo que impide que Copilot haga push. Si es justo el que rechaza, díselo a la persona antes de seguir.

Si el worktree ya existe, haz el cambio en `<REPO>-rescate\.rescate\config.json`. El script lee los dos y manda el del worktree.

## Si es un fallo del script

1. Lee la línea que dice el error y unas cuantas alrededor.
2. Propón el cambio más pequeño que lo arregle y explícalo.
3. Aplícalo solo si la persona está de acuerdo.
4. Solo vale si `.\tests\probar.ps1` vuelve a acabar en `TODO BIEN`.

No quites ninguna comprobación de `Invoke-Fix`: son las que impiden que la IA estropee el repo.

## Códigos de salida

| Código | Significado |
|---|---|
| 0 | Ha terminado bien. |
| 1 | Falta algo o un parámetro está mal. El mensaje dice qué. |
| 2 | Hay ficheros atascados, el proyecto no compila o hay demasiados lotes deshechos seguidos. |
| 3 | Git no ha podido hacer el commit o copiar los cambios al worktree. |
| 4 | Se ha modificado la plantilla o el original. Hay que restaurarlos antes de seguir. |

Pase lo que pase, apunta el caso para `guia/informe.md`. Cuando esté resuelto, vuelve al fichero del paso en el que estabas.
