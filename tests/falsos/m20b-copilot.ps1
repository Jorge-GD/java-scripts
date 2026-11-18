# m20b-copilot.ps1 - Copilot de mentira para los tests m20b de tests/probar-local.ps1. Hace lo de copilot-local.ps1 y, con el guion
# 'm20b-sin-entradas' (RESCATE_FALSO), el test PruebaLocalTest que escribe una tarea de arnes lleva ademas la marca IGNORA_ENTRADAS:
# m20b-mvn.ps1 lo trata como un arnes que no le pasa las entradas al job. Las tareas de casos salen como siempre.
$texto = ''
for ($i = 0; $i -lt $args.Count; $i++) { if ("$($args[$i])" -eq '-p') { $texto = "$($args[$i + 1])" } }
& (Join-Path $PSScriptRoot 'copilot-local.ps1') @args
$codigo = $LASTEXITCODE
if ($texto -match 'tareas/arnes-' -and "$env:RESCATE_FALSO" -match 'm20b-sin-entradas') {
  foreach ($f in @(Get-ChildItem -LiteralPath (Get-Location).Path -Recurse -File -Filter 'PruebaLocalTest.java')) { [System.IO.File]::AppendAllText($f.FullName, "// IGNORA_ENTRADAS`n") }
}
exit $codigo
