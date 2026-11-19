# m40-copilot.ps1 - Copilot CLI de mentira para los tests m40 de tests/probar-local.ps1. Hace lo de copilot-local.ps1 y, si RESCATE_M40 trae
# un guion 'tablas=<n>/<T_A,T_B>:<regex sobre el id de la tarea>' (separados por ';'), el arnes cuyo id casa deja en su test la linea
# '// BASE_TABLAS=T_A,T_B' (m40-mvn.ps1 la lee: es la base de prueba que monta ese test) a partir de su llamada n; en las anteriores no la
# deja. La llamada n se sabe porque no hay en RESCATE_LLAMADAS mas de n-1 ficheros <id>-*.txt de antes.
$texto = ''
for ($i = 0; $i -lt $args.Count; $i++) { if ("$($args[$i])" -eq '-p') { $texto = "$($args[$i + 1])" } }
$desde = 0
$tablas = ''
if ($env:RESCATE_M40 -and $env:RESCATE_LLAMADAS -and $texto -match 'tareas/([\w\-]+)\.prompt\.md') {
  $id = $Matches[1]
  $previas = 0
  if (Test-Path -LiteralPath $env:RESCATE_LLAMADAS) { $previas = @(Get-ChildItem -LiteralPath $env:RESCATE_LLAMADAS -File -Filter ($id + '-*.txt')).Count }
  foreach ($g in ($env:RESCATE_M40 -split ';')) {
    $nombre, $solo = ($g -split ':', 2)
    if (-not $solo) { $solo = '.' }
    $clave, $valor = ($nombre -split '=', 2)
    if ($clave -eq 'tablas' -and -not $tablas -and $id -match $solo) {
      $n, $lista = ($valor -split '/', 2)
      if ($previas + 1 -ge [int]$n) { $tablas = $lista }
    }
  }
}
$salida = & (Join-Path $PSScriptRoot 'copilot-local.ps1') @args
$codigo = $LASTEXITCODE
if ($tablas) {
  $prompt = [System.IO.File]::ReadAllText((Join-Path (Join-Path (Join-Path (Get-Location).Path '.rescate') 'tareas') ($id + '.prompt.md')))
  $ruta = [regex]::Match($prompt, '(?m)^ESCRIBIR: (.*?)\s*$').Groups[1].Value
  if ($ruta) { [System.IO.File]::AppendAllText((Join-Path (Get-Location).Path $ruta), "// BASE_TABLAS=$tablas`n") }
}
$salida
exit $codigo
