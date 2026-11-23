# m82-mvn.ps1 - Maven de mentira para los tests m82 de tests/probar-local.ps1. Pasa todo a mvn-local.ps1 y, si RESCATE_M82 trae una expresion regular, en cada 'test'
# los jobs cuyo nombre casa con ella dejan lo que dejaria un test que no les pasa las entradas: de cada caso de target/prueba-local/<job> se borran ficheros\ y tablas\
# (queda estado.txt), como con IGNORA_ENTRADAS de m20b-mvn.ps1 pero solo en esos jobs. Los demas jobs salen como siempre.
$raiz = (Get-Location).Path
$test = ($args -contains 'test')
& (Join-Path $PSScriptRoot 'mvn-local.ps1') @args
$codigo = $LASTEXITCODE
$salidas = Join-Path $raiz 'target/prueba-local'
if ($test -and $codigo -eq 0 -and $env:RESCATE_M82 -and (Test-Path -LiteralPath $salidas)) {
  foreach ($j in @(Get-ChildItem -LiteralPath $salidas -Directory | Where-Object { $_.Name -match $env:RESCATE_M82 })) {
    foreach ($d in @(Get-ChildItem -LiteralPath $j.FullName -Recurse -Directory | Where-Object { $_.Name -eq 'ficheros' -or $_.Name -eq 'tablas' })) {
      if (Test-Path -LiteralPath $d.FullName) { Remove-Item -LiteralPath $d.FullName -Recurse -Force }
    }
  }
}
exit $codigo
