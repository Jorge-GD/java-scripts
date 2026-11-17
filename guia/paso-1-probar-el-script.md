# Paso 1. Probar el script en esta máquina

**Qué se consigue:** saber que `rescate.ps1` funciona con este PowerShell y este git antes de usarlo con un repo de verdad.
**¿Cambia algo?** No. Las pruebas crean repos de juguete en una carpeta temporal y la borran al acabar.

## Qué hacer

En la carpeta del script:

`.\tests\probar.ps1`

Usa un Maven de mentira y un Copilot de mentira. Solo necesita `git`. Tarda poco: de unos segundos a un par de minutos, según la máquina.

Si PowerShell bloquea el script:

`powershell -ExecutionPolicy Bypass -File .\tests\probar.ps1`

## Qué mirar

- La última línea tiene que ser `TODO BIEN`, con el número de comprobaciones.
- Si sale `FALLAN`, cada línea `FALLA` dice qué comprobación no ha pasado.

## Cuándo está cerrado

- Sale `TODO BIEN`.

Si no sale, no sigas con el repo real. Lee `guia/si-el-script-falla.md`.

Apúntalo en la bitácora. Siguiente: `guia/paso-2-diagnostico.md`.
