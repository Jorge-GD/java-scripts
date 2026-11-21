# m56-copilot.ps1 - Copilot CLI de mentira para los tests m56 de tests/probar-local.ps1. Hace lo de copilot-local.ps1 y, si RESCATE_M56 trae un
# guion '<nombre>:<regex sobre el id de la tarea>' (separados por ';'; gana el primero), el arnes cuyo id casa deja en su test, en todas sus llamadas,
# la linea '// M56_<nombre>': m56-mvn.ps1 la lee y hace fallar el mvn test como dice el nombre.
$texto = ''
for ($i = 0; $i -lt $args.Count; $i++) { if ("$($args[$i])" -eq '-p') { $texto = "$($args[$i + 1])" } }
$id = ''
$marca = ''
if ($env:RESCATE_M56 -and $texto -match 'tareas/([\w\-]+)\.prompt\.md') {
  $id = $Matches[1]
  foreach ($g in ($env:RESCATE_M56 -split ';')) {
    $nombre, $solo = ($g -split ':', 2)
    if (-not $solo) { $solo = '.' }
    if ($nombre -and -not $marca -and $id -match $solo) { $marca = $nombre }
  }
}
$salida = & (Join-Path $PSScriptRoot 'copilot-local.ps1') @args
$codigo = $LASTEXITCODE
if ($marca) {
  $prompt = [System.IO.File]::ReadAllText((Join-Path (Join-Path (Join-Path (Get-Location).Path '.rescate') 'tareas') ($id + '.prompt.md')))
  $ruta = [regex]::Match($prompt, '(?m)^ESCRIBIR: (.*?)\s*$').Groups[1].Value
  if ($ruta) { [System.IO.File]::AppendAllText((Join-Path (Get-Location).Path $ruta), "// M56_$marca`n") }
}
$salida
exit $codigo
