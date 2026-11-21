# m59-mvn.ps1 - Maven de mentira para los tests m59 de tests/probar-local.ps1. Hace lo de mvn-local.ps1 y, antes, apunta cada llamada en
# RESCATE_LLAMADAS/m59-mvn.log (si esta): carpeta|JAVA_TOOL_OPTIONS que recibe|si la carpeta tiene target (si o no)|argumentos.
$raiz = (Get-Location).Path
if ($env:RESCATE_LLAMADAS) {
  [void](New-Item -ItemType Directory -Path $env:RESCATE_LLAMADAS -Force)
  $target = 'no'
  if (Test-Path -LiteralPath (Join-Path $raiz 'target')) { $target = 'si' }
  [System.IO.File]::AppendAllText((Join-Path $env:RESCATE_LLAMADAS 'm59-mvn.log'), ($raiz + '|' + $env:JAVA_TOOL_OPTIONS + '|' + $target + '|' + ($args -join ' ') + "`n"))
}
& (Join-Path $PSScriptRoot 'mvn-local.ps1') @args
exit $LASTEXITCODE
