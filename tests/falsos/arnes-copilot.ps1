# arnes-copilot.ps1 - Copilot CLI de mentira para el grupo 'm18 arnes' de tests/probar-local.ps1 (prueba-local.ps1).
# Hace lo de copilot-local.ps1 (le pasa los mismos argumentos) y, en la primera llamada de un arnes, se cuelga o sale mal
# despues de escribir. Con la CORRECCION en el prompt (el segundo intento) hace lo de copilot-local.ps1 sin mas.
# RESCATE_FALSO es 'guion' o 'guion:regex' (la regex, sobre el id de la tarea), separados por ';'. Gana el primero. Un guion que
# no es de esta lista se pasa tal cual a copilot-local.ps1 (arnes-no-compila, arnes-toca-main...).
#   colgado-bueno    escribe un test que vale y se cuelga (prueba-local.ps1 lo mata al pasar de SegundosArnes)
#   colgado-malo     escribe un test que no compila (NO_COMPILA) y se cuelga
#   colgado-nada     no escribe nada y se cuelga
#   colgado-parcial  no escribe ningun fichero, dice 'salida parcial...' y se cuelga
#   sale-mal-bueno   escribe un test que vale y sale con codigo 3
$texto = ''
for ($i = 0; $i -lt $args.Count; $i++) { if ("$($args[$i])" -eq '-p') { $texto = "$($args[$i + 1])" } }
if ($texto -notmatch 'tareas/([\w\-]+)\.prompt\.md') { 'no entiendo el prompt'; exit 1 }
$id = $Matches[1]
$prompt = [System.IO.File]::ReadAllText((Join-Path (Join-Path (Join-Path (Get-Location).Path '.rescate') 'tareas') ($id + '.prompt.md')))
$tipo = ([regex]::Match($prompt, '(?m)^TIPO: (.*?)\s*$')).Groups[1].Value
$guion = ''
foreach ($g in ("$env:RESCATE_FALSO" -split ';')) {
  $nombre, $solo = ($g -split ':', 2)
  if (-not $solo) { $solo = '.' }
  if ($nombre -and -not $guion -and $id -match $solo) { $guion = $nombre }
}
$base = Join-Path $PSScriptRoot 'copilot-local.ps1'
$reintento = ($prompt -match 'intento anterior no pas')
$mio = @('colgado-bueno', 'colgado-malo', 'colgado-nada', 'colgado-parcial', 'sale-mal-bueno')
if ($tipo -ne 'arnes-local' -or $mio -notcontains $guion -or $reintento) {
  if ($mio -contains $guion) { $env:RESCATE_FALSO = '' }
  & $base @args
  exit $LASTEXITCODE
}
$env:RESCATE_FALSO = ''
if ($guion -eq 'colgado-malo') { $env:RESCATE_FALSO = 'arnes-no-compila' }
if ($guion -in @('colgado-bueno', 'colgado-malo', 'sale-mal-bueno')) { & $base @args | Out-Null }
$env:RESCATE_FALSO = ''
if ($guion -eq 'sale-mal-bueno') { 'Copilot se ha caido: sin red'; exit 3 }
if ($guion -eq 'colgado-parcial') { 'salida parcial: leyendo el job cargaRecibosJob' }
Start-Sleep -Seconds 120
exit 0
