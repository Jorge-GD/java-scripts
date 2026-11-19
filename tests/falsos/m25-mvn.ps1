# m25-mvn.ps1 - Maven de mentira para los tests m25 de tests/probar-local.ps1 (-Reparar). Pasa a mvn-local.ps1 todo menos la suite de
# tests unitarios (un 'test' sin -Dtest). Esa la hace como Surefire: deja un target/surefire-reports/TEST-<clase>.xml por cada
# src/test/java/**/*Test.java (menos PruebaLocalTest) y la clase falla si su texto lleva 'ESPERA minimo=<n>' y el 'minimo' de regla.txt
# (el de src/main/resources/regla.txt o, si no esta, el de la raiz) es otro. Con src/main/resources/sin-tests.txt no ejecuta ninguna clase.
# Falla (exit 1) si la suite no lleva -Dsurefire.excludesFile=<fichero con **/PruebaLocalTest*> y -Dmaven.test.failure.ignore=true.
$raiz = (Get-Location).Path
$argumentos = @($args)
$suite = ($argumentos -contains 'test' -and @($argumentos | Where-Object { "$_" -like '-Dtest=*' }).Count -eq 0)
if (-not $suite) {
  & (Join-Path $PSScriptRoot 'mvn-local.ps1') @argumentos
  exit $LASTEXITCODE
}
$excluye = ''
foreach ($a in $argumentos) { if ("$a" -match '^-Dsurefire\.excludesFile=(.+)$') { $excluye = $Matches[1] } }
if (-not $excluye -or -not (Test-Path -LiteralPath $excluye) -or [System.IO.File]::ReadAllText($excluye) -notmatch '\*\*/PruebaLocalTest\*') {
  '[ERROR] la suite no excluye PruebaLocalTest: falta -Dsurefire.excludesFile=<fichero con **/PruebaLocalTest*>'
  exit 1
}
if ($argumentos -notcontains '-Dmaven.test.failure.ignore=true') { '[ERROR] la suite no lleva -Dmaven.test.failure.ignore=true'; exit 1 }
$fr = Join-Path $raiz 'src/main/resources/regla.txt'
if (-not (Test-Path -LiteralPath $fr)) { $fr = Join-Path $raiz 'regla.txt' }
$minimo = ''
if (Test-Path -LiteralPath $fr) { foreach ($l in [System.IO.File]::ReadAllLines($fr)) { if ($l -match '^minimo=(.*)$') { $minimo = $Matches[1].Trim() } } }
$informes = Join-Path $raiz 'target/surefire-reports'
[void](New-Item -ItemType Directory -Path $informes -Force)
$tests = Join-Path $raiz 'src/test/java'
if ((Test-Path -LiteralPath $tests) -and -not (Test-Path -LiteralPath (Join-Path $raiz 'src/main/resources/sin-tests.txt'))) {
  foreach ($f in @(Get-ChildItem -LiteralPath $tests -Recurse -File -Filter '*Test.java' | Where-Object { $_.Name -ne 'PruebaLocalTest.java' })) {
    $clase = ($f.FullName.Substring($tests.Length).TrimStart('\', '/') -replace '\.java$', '') -replace '[\\/]', '.'
    $espera = [regex]::Match([System.IO.File]::ReadAllText($f.FullName), 'ESPERA minimo=(\S+)')
    $falla = ($espera.Success -and $espera.Groups[1].Value -ne $minimo)
    $cuerpo = ''
    if ($falla) { $cuerpo = '<failure message="esperaba minimo=' + $espera.Groups[1].Value + ' y hay ' + $minimo + '"/>' }
    $xml = '<?xml version="1.0" encoding="UTF-8"?>' + "`n" + '<testsuite name="' + $clase + '" tests="1" errors="0" skipped="0" failures="' + [int]$falla + '">' + "`n" + '  <testcase name="espera" classname="' + $clase + '">' + $cuerpo + '</testcase>' + "`n" + '</testsuite>' + "`n"
    [System.IO.File]::WriteAllText((Join-Path $informes ('TEST-' + $clase + '.xml')), $xml, (New-Object System.Text.UTF8Encoding($false)))
  }
}
'[INFO] BUILD SUCCESS'
exit 0
