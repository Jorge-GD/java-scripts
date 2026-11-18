# sonar-copilot.ps1 - Copilot CLI de mentira para el test de 'm10 sonar' con dos incidencias de un mismo fichero (tests/probar.ps1).
# Lee .rescate/prompt.md. En un lote del paso 'sonar' recorre cada incidencia del prompt ('- fichero:linea - detalle'). RESCATE_FALSO:
#   sonar-deja-y-atasca  la que lleva DEJAME en el detalle la apunta con su motivo en .rescate/sonar-sin-arreglar.txt y no la toca;
#                        la que lleva ATASCA no la toca ni la apunta; las demas las corrige cambiando el codigo de su linea (' + 0;')
# Con cualquier otro prompt o guion no hace nada.
if ($args -contains '--version') { 'GitHub Copilot CLI 1.0.112 (de mentira).'; exit 0 }
$raiz = (Get-Location).Path
$rescate = Join-Path $raiz '.rescate'
$prompt = [System.IO.File]::ReadAllText((Join-Path $rescate 'prompt.md'))
$titulo = ($prompt -split "`r?`n")[0]
if ($titulo -notmatch "paso 'sonar'" -or "$env:RESCATE_FALSO" -ne 'sonar-deja-y-atasca') { 'hecho'; exit 0 }

function Get-Ruta([string]$Rel) {
  $p = $raiz
  foreach ($s in $Rel.Split('/')) { if ($s) { $p = Join-Path $p $s } }
  return $p
}

$dentro = $false
$dejadas = @()
foreach ($l in ($prompt -split "`r?`n")) {
  if ($l -match '^## (Hallazgos|Ficheros del lote)') { $dentro = $true; continue }
  if ($dentro -and $l -match '^## ') { break }
  if (-not ($dentro -and $l -match '^- (\S+?):(\d+) - ')) { continue }
  $f = $Matches[1]; $n = [int]$Matches[2]
  if ($l -match 'ATASCA') { continue }
  if ($l -match 'DEJAME') { $dejadas += "${f}:${n} | cambiaria la API publica"; continue }
  $t = @([System.IO.File]::ReadAllText((Get-Ruta $f)) -split "`r?`n")
  $t[$n - 1] = ($t[$n - 1] -replace ';\s*$', ' + 0;')
  [System.IO.File]::WriteAllText((Get-Ruta $f), ($t -join "`n"))
}
if ($dejadas.Count -gt 0) {
  [System.IO.File]::WriteAllText((Get-Ruta '.rescate/sonar-sin-arreglar.txt'), (($dejadas -join "`n") + "`n"))
}
'hecho'
exit 0
