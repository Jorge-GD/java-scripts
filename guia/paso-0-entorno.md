# Paso 0. Entorno

**Qué se consigue:** saber que la máquina tiene lo necesario y cómo está el repo antes de tocar nada.
**¿Cambia algo?** No. Todo son consultas.

## Qué hacer

Un comando cada vez, explicando para qué sirve:

1. `$PSVersionTable.PSVersion`
2. `git --version`
3. `java -version`
4. `mvn -v` (o el `mvnw` del repo)
5. `copilot --version`
6. En el repo: `git branch --show-current`
7. En el repo: `git status --short`
8. Que la plantilla y el original existen: `git -C <PLANTILLA> status --short` y lo mismo con `<ORIGINAL>`.

## Qué mirar

- PowerShell 5.1 o 7: valen los dos.
- Copilot arranca y tiene la sesión iniciada.
- Si el repo tiene cambios sin commit, explica que el script los copiará al worktree en un commit «foto» y que la carpeta original no cambia. Si son cambios a medias que no quiere mezclar con el arreglo, mejor hacer commit antes. Lo decide la persona.

## Cuándo está cerrado

- Todas las herramientas responden.
- La persona sabe en qué rama está y qué va a pasar con sus cambios sin commit.

Apúntalo en la bitácora. Siguiente: `guia/paso-1-probar-el-script.md`.
