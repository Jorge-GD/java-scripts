# m69-copilot.ps1 - Copilot CLI de mentira para los tests m69 de tests/probar-local.ps1. Hace lo de m40-copilot.ps1 y, si RESCATE_M69 trae guiones
# '<regex sobre el id de la tarea>@<n>@<marca>~<marca>' (separados por ';'), el arnes cuyo id casa deja al final de su test una linea '// <marca>' por marca, solo
# en su llamada n. La cuenta de llamadas es la de todos los lanzamientos: se sabe porque no hay en RESCATE_LLAMADAS mas de n-1 ficheros <id>-*.txt de antes.
# m69-mvn.ps1 lee las marcas M69_* (M69_VERSION=<x> no cambia nada: solo hace distinto el test).
$texto = ''
for ($i = 0; $i -lt $args.Count; $i++) { if ("$($args[$i])" -eq '-p') { $texto = "$($args[$i + 1])" } }
$marcas = @()
$id = ''
if ($env:RESCATE_M69 -and $env:RESCATE_LLAMADAS -and $texto -match 'tareas/([\w\-]+)\.prompt\.md') {
  $id = $Matches[1]
  $previas = 0
  if (Test-Path -LiteralPath $env:RESCATE_LLAMADAS) { $previas = @(Get-ChildItem -LiteralPath $env:RESCATE_LLAMADAS -File -Filter ($id + '-*.txt')).Count }
  foreach ($g in ($env:RESCATE_M69 -split ';')) {
    $re, $n, $lista = ($g -split '@', 3)
    if ($re -and $id -match $re -and ($previas + 1) -eq [int]$n) { $marcas += @($lista -split '~') }
  }
}
$salida = & (Join-Path $PSScriptRoot 'm40-copilot.ps1') @args
$codigo = $LASTEXITCODE
if ($marcas.Count -gt 0) {
  $prompt = [System.IO.File]::ReadAllText((Join-Path (Join-Path (Join-Path (Get-Location).Path '.rescate') 'tareas') ($id + '.prompt.md')))
  $ruta = [regex]::Match($prompt, '(?m)^ESCRIBIR: (.*?)\s*$').Groups[1].Value
  if ($ruta) { foreach ($m in $marcas) { [System.IO.File]::AppendAllText((Join-Path (Get-Location).Path $ruta), "// $m`n") } }
}
$salida
exit $codigo
