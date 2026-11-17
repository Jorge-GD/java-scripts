# Paso 4. Plan de un paso

**Qué se consigue:** antes de cambiar nada, un plan escrito de lo que se va a hacer con cada fichero del paso.
**¿Cambia algo?** La primera vez crea el worktree `<REPO>-rescate` y su rama `rescate/...`. No cambia código.

## Qué paso toca

El primero con errores, en este orden: `build`, `estructura`, `hexagonal`, `ficheros`, `config`, `paridad`, `e2e`, `tests`, `calidad`. El diagnóstico lo dice en «Siguiente paso recomendado».

Solo llevan plan `estructura`, `hexagonal`, `ficheros` y `config`. Si toca otro, apúntalo y ve directamente a `guia/paso-5-primer-lote.md`.

## Qué hacer

`.\rescate.ps1 -Modo plan -Repo <REPO> -Plantilla <PLANTILLA> -Legacy <ORIGINAL> -Paso <PASO> -Modelo <MODELO> -EsfuerzoPlan high`

Sin original, quita `-Legacy`. Sin modelo elegido, quita `-Modelo`.

Antes de lanzarlo, explica qué es un worktree: otra carpeta del mismo repo, con otra rama. Lo que pase ahí no afecta a la carpeta de siempre.

Copilot lee todos los ficheros con hallazgos del paso y la plantilla, y escribe `<REPO>-rescate\.rescate\plan-<PASO>.md`.

## Qué mirar

Lee el plan con la persona:

- ¿Cada fichero con hallazgos tiene su línea y un destino?
- ¿Ese destino existe en la plantilla? Compruébalo leyendo la plantilla.
- ¿Las piezas comunes (puertos, adaptadores) son una sola para todos, o se repiten con otro nombre?
- Lo que haya en «Dudas» lo decide la persona, no tú.

El plan es un fichero de texto: se corrige a mano antes de seguir.

## Cuándo está cerrado

- El plan está leído entero y corregido si hacía falta.
- Las dudas están resueltas por la persona.

Apúntalo en la bitácora. Siguiente: `guia/paso-5-primer-lote.md`.
