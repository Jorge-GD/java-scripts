# m53-copilot.ps1 - Copilot CLI de mentira para los tests m53 de tests/probar-local.ps1. Imita al de verdad: si algun --add-dir=<carpeta> nombra una carpeta que no
# existe, escribe "error: option '--add-dir <directory>' argument '<carpeta>' is invalid" y sale con 1 sin hacer nada (deja su registro en RESCATE_LLAMADAS, con el
# guion 'rechazada', para que el test vea con que carpetas se le llamo). Con RESCATE_M53_RECHAZA=1 lo hace siempre, con la primera carpeta que lleve o con 'x'.
# Con RESCATE_M53_RECHAZA=sesion falla siempre con 'Error: la sesion ha caducado' (un fallo de Copilot, no de los argumentos), sin hacer nada.
# Si no, hace lo de m25-copilot.ps1 (y con el, lo de copilot-local.ps1).
$texto = ''
$dirs = @()
for ($i = 0; $i -lt $args.Count; $i++) {
  if ("$($args[$i])" -eq '-p') { $texto = "$($args[$i + 1])" }
  if ("$($args[$i])" -match '^--add-dir=(.*)$') { $dirs += $Matches[1] }
}
if ($env:RESCATE_M53_RECHAZA -eq 'sesion') { 'Error: la sesion ha caducado'; exit 1 }
$falta = ''
foreach ($d in $dirs) { if (-not $falta -and -not (Test-Path -LiteralPath $d -PathType Container)) { $falta = $d } }
if ($env:RESCATE_M53_RECHAZA -eq '1' -and -not $falta) { $falta = 'x'; if ($dirs.Count -gt 0) { $falta = $dirs[0] } }
if (-not $falta) {
  & (Join-Path $PSScriptRoot 'm25-copilot.ps1') @args
  exit $LASTEXITCODE
}
if ($env:RESCATE_LLAMADAS -and $texto -match 'tareas/([\w\-]+)\.prompt\.md') {
  $id = $Matches[1]
  $prompt = Join-Path (Join-Path (Join-Path (Get-Location).Path '.rescate') 'tareas') ($id + '.prompt.md')
  $tipo = ''
  if (Test-Path -LiteralPath $prompt) { $tipo = [regex]::Match([System.IO.File]::ReadAllText($prompt), '(?m)^TIPO: (\S+)').Groups[1].Value }
  $flags = (@($args | Where-Object { "$_" -match '^--(model=|effort=|add-dir=)' }) -join ' ')
  [void](New-Item -ItemType Directory -Path $env:RESCATE_LLAMADAS -Force)
  [System.IO.File]::WriteAllLines((Join-Path $env:RESCATE_LLAMADAS ($id + '-' + $PID + '.txt')), [string[]]@("id=$id", "tipo=$tipo", "flags=$flags", 'guion=rechazada'))
}
"error: option '--add-dir <directory>' argument '$falta' is invalid"
exit 1
