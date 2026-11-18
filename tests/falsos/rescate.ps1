# rescate.ps1 - Motor de mentira para tests/probar-migracion.ps1: hace lo que diga el JSON de $env:MOTOR_FALSO y apunta cada llamada
# en <ese JSON>.llamadas (una linea por llamada: modo|modelo|esfuerzo|esfuerzoPlan|lote|todo|si|repo).
#   pre          escribe un contrato sin jobs.
#   diagnostico  escribe .rescate/hallazgos.json y diagnostico.md con "antes" y, tras un fix, con "despues" (hallazgos y md).
#                Si no hay datos para esa vez, sale con 5.
#   fix          escribe "ficheros" (ruta -> texto) en el repo, quita con git rm las rutas de "borrar", hace un commit por cada
#                asunto de "commits", anade las lineas de "atascados" a .rescate/atascados.md, imprime "salida" y sale con "codigo".
param([string]$Modo = '', [string]$Repo = '', [string]$Plantilla = '', [string]$Legacy = '', [string]$Modelo = '', [string]$Esfuerzo = '', [string]$EsfuerzoPlan = '', [int]$Lote = 5, [switch]$SinIA, [switch]$Si, [switch]$Todo)
$orden = [System.IO.File]::ReadAllText($env:MOTOR_FALSO) | ConvertFrom-Json
$llamadas = $env:MOTOR_FALSO + '.llamadas'
$huboFix = $false
if (Test-Path -LiteralPath $llamadas) { $huboFix = (@([System.IO.File]::ReadAllLines($llamadas) | Where-Object { $_ -like 'fix|*' }).Count -gt 0) }
[System.IO.File]::AppendAllText($llamadas, "$Modo|$Modelo|$Esfuerzo|$EsfuerzoPlan|$Lote|$Todo|$Si|$Repo`n")
$work = Join-Path $Repo '.rescate'
[void](New-Item -ItemType Directory -Path $work -Force)
if ($Modo -eq 'pre') {
  [System.IO.File]::WriteAllText((Join-Path $work 'contrato.json'), '{ "jobs": [] }')
  exit 0
}
if ($Modo -eq 'diagnostico') {
  $d = $orden.antes
  if ($huboFix) { $d = $orden.despues }
  if (-not $d) { Write-Host 'el motor de mentira no tiene diagnostico que dar'; exit 5 }
  [System.IO.File]::WriteAllText((Join-Path $work 'hallazgos.json'), (ConvertTo-Json -InputObject @($d.hallazgos) -Depth 4))
  [System.IO.File]::WriteAllText((Join-Path $work 'diagnostico.md'), [string]$d.md)
  exit 0
}
if ($orden.ficheros) {
  foreach ($f in $orden.ficheros.PSObject.Properties) {
    $ruta = Join-Path $Repo $f.Name
    [void](New-Item -ItemType Directory -Path (Split-Path $ruta -Parent) -Force)
    [System.IO.File]::WriteAllText($ruta, [string]$f.Value)
  }
}
foreach ($b in @($orden.borrar | Where-Object { $_ })) { & git -C $Repo rm -q -f -- $b 2>&1 | Out-Null }
foreach ($c in @($orden.commits | Where-Object { $_ })) {
  & git -C $Repo add -A 2>&1 | Out-Null
  & git -C $Repo commit -q --allow-empty -m $c 2>&1 | Out-Null
}
if ($orden.atascados) { [System.IO.File]::AppendAllText((Join-Path $work 'atascados.md'), ((@($orden.atascados) -join "`n") + "`n")) }
foreach ($l in @($orden.salida | Where-Object { $_ })) { Write-Host $l }
exit ([int]$orden.codigo)
