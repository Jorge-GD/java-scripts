# m36-copilot.ps1 - Copilot CLI de mentira para los tests m36 de tests/probar-local.ps1. Hace lo de copilot-local.ps1 y, con el guion
# primera-nada (RESCATE_FALSO), la primera llamada de cada tarea de caso no escribe nada (la tarea se rechaza por eso); las demas llamadas
# escriben el caso como siempre. La primera se sabe porque no hay en RESCATE_LLAMADAS un <id>-*.txt de antes.
$texto = ''
for ($i = 0; $i -lt $args.Count; $i++) { if ("$($args[$i])" -eq '-p') { $texto = "$($args[$i + 1])" } }
if ("$env:RESCATE_FALSO" -eq 'primera-nada' -and $env:RESCATE_LLAMADAS -and $texto -match 'tareas/([\w\-]+)\.prompt\.md') {
  $id = $Matches[1]
  $prompt = [System.IO.File]::ReadAllText((Join-Path (Join-Path (Join-Path (Get-Location).Path '.rescate') 'tareas') ($id + '.prompt.md')))
  [void](New-Item -ItemType Directory -Path $env:RESCATE_LLAMADAS -Force)
  $previas = @(Get-ChildItem -LiteralPath $env:RESCATE_LLAMADAS -File -Filter ($id + '-*.txt'))
  if ($prompt -match '(?m)^TIPO: caso-local\s*$' -and $previas.Count -eq 0) {
    [System.IO.File]::WriteAllLines((Join-Path $env:RESCATE_LLAMADAS ($id + '-' + $PID + '.txt')), [string[]]@("id=$id", "pid=$PID", 'tipo=caso-local', 'guion=primera-nada'))
    'hecho'
    exit 0
  }
}
& (Join-Path $PSScriptRoot 'copilot-local.ps1') @args
exit $LASTEXITCODE
