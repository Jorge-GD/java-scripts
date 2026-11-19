# arnes-copilot.ps1 - Copilot CLI de mentira para el grupo 'm18 arnes' de tests/probar-local.ps1 (prueba-local.ps1).
# Hace lo de copilot-local.ps1 (le pasa los mismos argumentos) y, en la primera llamada de un arnes, se cuelga o sale mal
# despues de escribir. Con la CORRECCION en el prompt (el segundo intento): si el test que dejo el primero sigue en la copia,
# lo arregla (cambia NO_COMPILA por ARREGLADO, sin reescribirlo); si no, hace lo de copilot-local.ps1 (lo escribe entero).
# RESCATE_FALSO es 'guion' o 'guion:regex' (la regex, sobre el id de la tarea), separados por ';'. Gana el primero. Un guion que
# no es de esta lista se pasa tal cual a copilot-local.ps1 (arnes-no-compila, arnes-toca-main...).
#   colgado-bueno    escribe un test que vale y se cuelga (prueba-local.ps1 lo mata al pasar de SegundosArnes)
#   colgado-malo     escribe un test que no compila (NO_COMPILA) y se cuelga
#   colgado-nada     no escribe nada y se cuelga
#   colgado-parcial  no escribe ningun fichero, dice 'salida parcial...' y se cuelga
#   sale-mal-bueno   escribe un test que vale y sale con codigo 3
#   sale-mal-malo    escribe un test que no compila y sale con codigo 3
#   colgado-siempre  como colgado-malo, y tambien en el reintento (no lo arregla: escribe otra vez un test que no compila y se cuelga)
#   colgado-toca-main  escribe un test que no compila (NO_COMPILA) y src/main/java/Tocado.java (prohibido: el script lo deshace) y se cuelga
# En un reintento de arnes deja en RESCATE_LLAMADAS (si esta) <id>.reintento con lo que encontro en la copia: test=<True|False>
# (el test de ESCRIBIR) y tocado=<True|False> (src/main/java/Tocado.java).
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
$mio = @('colgado-bueno', 'colgado-malo', 'colgado-nada', 'colgado-parcial', 'sale-mal-bueno', 'sale-mal-malo', 'colgado-siempre', 'colgado-toca-main')
$previo = ''
if ($tipo -eq 'arnes-local') { $previo = Join-Path (Get-Location).Path (([regex]::Match($prompt, '(?m)^ESCRIBIR: (.*?)\s*$')).Groups[1].Value) }
if ($tipo -eq 'arnes-local' -and $reintento -and $env:RESCATE_LLAMADAS) {
  [void](New-Item -ItemType Directory -Path $env:RESCATE_LLAMADAS -Force)
  [System.IO.File]::WriteAllLines((Join-Path $env:RESCATE_LLAMADAS ($id + '.reintento')), [string[]]@(('test=' + (Test-Path -LiteralPath $previo -PathType Leaf)), ('tocado=' + (Test-Path -LiteralPath (Join-Path (Get-Location).Path 'src/main/java/Tocado.java')))))
}
if ($tipo -ne 'arnes-local' -or $mio -notcontains $guion -or ($reintento -and $guion -ne 'colgado-siempre')) {
  if ($mio -contains $guion) { $env:RESCATE_FALSO = '' }
  if ($tipo -eq 'arnes-local' -and $reintento -and (Test-Path -LiteralPath $previo -PathType Leaf)) {
    [System.IO.File]::WriteAllText($previo, [System.IO.File]::ReadAllText($previo).Replace('NO_COMPILA', 'ARREGLADO'))
    'he seguido desde el test que habia'
    exit 0
  }
  & $base @args
  exit $LASTEXITCODE
}
$env:RESCATE_FALSO = ''
if ($guion -in @('colgado-malo', 'colgado-siempre', 'sale-mal-malo')) { $env:RESCATE_FALSO = 'arnes-no-compila' }
if ($guion -eq 'colgado-toca-main') { $env:RESCATE_FALSO = 'arnes-toca-main' }
if ($guion -in @('colgado-bueno', 'colgado-malo', 'colgado-siempre', 'colgado-toca-main', 'sale-mal-bueno', 'sale-mal-malo')) { & $base @args | Out-Null }
if ($guion -eq 'colgado-toca-main') { [System.IO.File]::AppendAllText($previo, "// NO_COMPILA`n") }
$env:RESCATE_FALSO = ''
if ($guion -in @('sale-mal-bueno', 'sale-mal-malo')) { 'Copilot se ha caido: sin red'; exit 3 }
if ($guion -eq 'colgado-parcial') { 'salida parcial: leyendo el job cargaRecibosJob' }
Start-Sleep -Seconds 120
exit 0
