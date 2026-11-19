# m38-rescate.ps1 - Motor de mentira de los tests m38 de tests/probar-migracion.ps1. Hace lo de tests/falsos/rescate.ps1 y, ademas,
# acepta -Reintentar y lo apunta en <MOTOR_FALSO>.reintentar (una linea por llamada: modo|Reintentar).
# Se copia como rescate.ps1 junto a rescate-motor.ps1, que es la copia de tests/falsos/rescate.ps1.
param([string]$Modo = '', [string]$Repo = '', [string]$Plantilla = '', [string]$Legacy = '', [string]$Modelo = '', [string]$Esfuerzo = '', [string]$EsfuerzoPlan = '', [int]$Lote = 5, [switch]$SinIA, [switch]$Si, [switch]$Todo, [switch]$Reintentar)
[System.IO.File]::AppendAllText($env:MOTOR_FALSO + '.reintentar', "$Modo|$Reintentar`n")
$a = @{}
foreach ($k in $PSBoundParameters.Keys) { if ($k -ne 'Reintentar') { $a[$k] = $PSBoundParameters[$k] } }
& (Join-Path $PSScriptRoot 'rescate-motor.ps1') @a
exit $LASTEXITCODE
