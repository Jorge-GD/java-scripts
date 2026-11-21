# c4-rescate.ps1 - Motor de mentira del grupo c4 de tests/probar-migracion.ps1. Hace lo de rescate-motor.ps1 (la copia de tests/falsos/rescate.ps1, a su
# lado) salvo el diagnostico del cierre: si la orden de $env:MOTOR_FALSO lleva "cierre" ({ md, hallazgos, commitEn }), el diagnostico da ese md y esos
# hallazgos y, con commitEn, hace antes un commit vacio en esa carpeta (alguien avanza tu rama mientras se mide el cierre) y, con ramaEn, cambia esa
# carpeta a una rama nueva, "otra", que sale de donde estaba tu rama (alguien hace git switch mientras se mide el cierre).
# Con falla (un codigo de salida), el diagnostico sale con ese codigo y sin escribir nada (el motor se cae).
# Se copia como rescate.ps1 junto a rescate-motor.ps1.
param([string]$Modo = '', [string]$Repo = '', [string]$Plantilla = '', [string]$Legacy = '', [string]$Modelo = '', [string]$Esfuerzo = '', [string]$EsfuerzoPlan = '', [int]$Lote = 5, [switch]$SinIA, [switch]$Si, [switch]$Todo)
$orden = [System.IO.File]::ReadAllText($env:MOTOR_FALSO) | ConvertFrom-Json
if ($Modo -ne 'diagnostico' -or -not $orden.cierre) {
  $a = @{}
  foreach ($k in $PSBoundParameters.Keys) { $a[$k] = $PSBoundParameters[$k] }
  & (Join-Path $PSScriptRoot 'rescate-motor.ps1') @a
  exit $LASTEXITCODE
}
[System.IO.File]::AppendAllText($env:MOTOR_FALSO + '.llamadas', "$Modo|$Modelo|$Esfuerzo|$EsfuerzoPlan|$Lote|$Todo|$Si|$Repo`n")
if ($orden.cierre.commitEn) { & git -C $orden.cierre.commitEn commit -q --allow-empty -m 'alguien avanza tu rama' 2>&1 | Out-Null }
if ($orden.cierre.ramaEn) { & git -C $orden.cierre.ramaEn switch -q -c otra 2>&1 | Out-Null }
if ($orden.cierre.falla) { exit ([int]$orden.cierre.falla) }
$work = Join-Path $Repo '.rescate'
[void](New-Item -ItemType Directory -Path $work -Force)
[System.IO.File]::WriteAllText((Join-Path $work 'hallazgos.json'), (ConvertTo-Json -InputObject @($orden.cierre.hallazgos) -Depth 4))
[System.IO.File]::WriteAllText((Join-Path $work 'diagnostico.md'), [string]$orden.cierre.md)
exit 0
