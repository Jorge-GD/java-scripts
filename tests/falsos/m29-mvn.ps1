# m29-mvn.ps1 - Maven de mentira para los tests m29 de tests/probar-local.ps1. Pasa todo a m25-mvn.ps1 (y con el, a mvn-local.ps1) y, en
# cada 'test -Dtest=PruebaLocalTest', anade a RESCATE_LLAMADAS/m29-tests.log (si esta) una linea carpeta|caso|marca: la carpeta donde se
# lanza, el valor de -Dprueba.local.caso y la marca '// MARCA_ARNES=<x>' del PruebaLocalTest.java de esa carpeta (m29-copilot.ps1).
$raiz = (Get-Location).Path
$argumentos = @($args)
& (Join-Path $PSScriptRoot 'm25-mvn.ps1') @argumentos
$codigo = $LASTEXITCODE
if ($env:RESCATE_LLAMADAS -and $argumentos -contains 'test' -and ($argumentos -contains '-Dtest=PruebaLocalTest')) {
  $caso = ''
  foreach ($a in $argumentos) { if ("$a" -match '^-Dprueba\.local\.caso=(.+)$') { $caso = $Matches[1] } }
  $marca = ''
  $tests = Join-Path $raiz 'src/test/java'
  if (Test-Path -LiteralPath $tests) {
    foreach ($f in @(Get-ChildItem -LiteralPath $tests -Recurse -File -Filter 'PruebaLocalTest.java')) { $x = [regex]::Match([System.IO.File]::ReadAllText($f.FullName), 'MARCA_ARNES=(\S+)'); if ($x.Success) { $marca = $x.Groups[1].Value } }
  }
  [System.IO.File]::AppendAllText((Join-Path $env:RESCATE_LLAMADAS 'm29-tests.log'), ($raiz + '|' + $caso + '|' + $marca + "`n"))
}
exit $codigo
