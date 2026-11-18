# mvn-m6.ps1 - Maven de mentira para las pruebas del M6 de tests/probar.ps1: hace lo mismo que mvn.ps1 y, como los
# tests de algunos batchs, deja un fichero fuera de target (output/x.csv) cada vez que pasa los tests.
& (Join-Path $PSScriptRoot 'mvn.ps1') @args
$codigo = $LASTEXITCODE
if ($args -contains 'test') {
  $d = Join-Path (Get-Location).Path 'output'
  if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -Force) }
  [System.IO.File]::WriteAllText((Join-Path $d 'x.csv'), "id;importe`n1;10`n")
}
exit $codigo
