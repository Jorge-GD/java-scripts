# mvn.ps1 - Maven de mentira para tests/probar.ps1.
# "Compila" si ningun .java contiene NO_COMPILA.
# Con el argumento 'test', los "tests" fallan si algun test contiene TEST_FALLA.
$raiz = (Get-Location).Path
$javas = @(Get-ChildItem -LiteralPath (Join-Path $raiz 'src') -Recurse -File -Filter '*.java')
$malos = @($javas | Where-Object { [System.IO.File]::ReadAllText($_.FullName) -match 'NO_COMPILA' })
if ($malos.Count -gt 0) {
  '[ERROR] COMPILATION ERROR : '
  foreach ($m in $malos) { '[ERROR] ' + $m.FullName + ':[1,1] simbolo de mentira no encontrado' }
  exit 1
}
if ($args -contains 'test') {
  $rep = Join-Path (Join-Path $raiz 'target') 'surefire-reports'
  [void](New-Item -ItemType Directory -Path $rep -Force)
  $fallan = @($javas | Where-Object { ($_.FullName -match '[\\/]src[\\/]test[\\/]') -and ([System.IO.File]::ReadAllText($_.FullName) -match 'TEST_FALLA') })
  foreach ($t in $fallan) {
    [System.IO.File]::WriteAllText((Join-Path $rep ($t.BaseName + '.txt')), 'Tests run: 1, Failures: 1, Errors: 0, Skipped: 0')
  }
  if ($fallan.Count -gt 0) {
    '[ERROR] Tests run: 1, Failures: 1, Errors: 0, Skipped: 0'
    exit 1
  }
}
exit 0
