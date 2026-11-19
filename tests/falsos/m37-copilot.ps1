# m37-copilot.ps1 - Copilot de mentira para los tests m37 de tests/probar-local.ps1 (el test del original y el del migrado que lo traduce).
# Hace lo de m29-copilot.ps1 (y con el, lo de m25-copilot.ps1 y copilot-local.ps1) y, en una tarea de arnes que traduce el test del original,
# apunta ademas en su fichero de RESCATE_LLAMADAS (<id>-<pid>.txt):
#   original-marca=<x>       la marca '// MARCA_ARNES=<x>' que lleva el test del original que dice el prompt, tal como esta al empezar la
#                            llamada: dice cual de los tests del original (el de antes o el nuevo) es el que traduce.
$texto = ''
for ($i = 0; $i -lt $args.Count; $i++) { if ("$($args[$i])" -eq '-p') { $texto = "$($args[$i + 1])" } }
$raiz = (Get-Location).Path
$id = ''
if ($texto -match 'tareas/([\w\-]+)\.prompt\.md') { $id = $Matches[1] }
$prompt = ''
if ($id) { $prompt = [System.IO.File]::ReadAllText((Join-Path (Join-Path (Join-Path $raiz '.rescate') 'tareas') ($id + '.prompt.md'))) }
$marca = ''
if ($prompt -match '(?m)^TIPO: arnes-local\s*$') {
  $m = [regex]::Match($prompt, 'El test del original ya est. escrito y vale: `([^`]+)`')
  if ($m.Success -and (Test-Path -LiteralPath $m.Groups[1].Value)) {
    $x = [regex]::Match([System.IO.File]::ReadAllText($m.Groups[1].Value), 'MARCA_ARNES=(\S+)')
    if ($x.Success) { $marca = $x.Groups[1].Value }
  }
}
& (Join-Path $PSScriptRoot 'm29-copilot.ps1') @args
$codigo = $LASTEXITCODE
if ($marca -and $env:RESCATE_LLAMADAS) { [System.IO.File]::AppendAllLines((Join-Path $env:RESCATE_LLAMADAS ($id + '-' + $PID + '.txt')), [string[]]@("original-marca=$marca")) }
exit $codigo
