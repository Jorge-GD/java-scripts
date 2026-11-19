# m32-mvn.ps1 - Maven de mentira para los tests m32 de tests/probar-local.ps1. Hace lo de mvn-local.ps1 (que apunta cada llamada en
# RESCATE_LLAMADAS/mvn.log) y, ademas:
#  - un caso que llega a ejecutarse (-Dprueba.local.caso=caso-<n>) deja target/surefire-reports/TEST-<paquete>.PruebaLocalTest.xml con un
#    testsuite de time = 0.2 por <n> (caso-01 = 0.2, caso-02 = 0.4);
#  - si RESCATE_M32 trae un guion:
#      sin-red-original   en la copia del original (batch-viejo), con -o, el caso no llega a ejecutar el test (como un Maven sin red que no tiene
#                         en su repositorio local lo que necesita): sale con 1 sin dejar nada. Sin -o va bien. El migrado va bien con -o o sin el
#      migrado-roto       en la copia del migrado, caso-01 no llega a ejecutar el test ni con -o ni sin el
#      falla-migrado      en la copia del migrado, caso-01 deja estado=FAILED y caso-02 deja error.txt (sin estado.txt): Maven sale con 1
#      xml-viejo          el XML solo lo escribe el primer caso de cada copia: los demas Maven dejan el que ya habia, de antes de ese Maven
$raiz = (Get-Location).Path
$original = ($raiz -like '*batch-viejo*')
$guion = "$env:RESCATE_M32"
$job = ''
$caso = ''
foreach ($a in $args) {
  if ("$a" -match '^-Dprueba\.local\.job=(.+)$') { $job = $Matches[1] }
  if ("$a" -match '^-Dprueba\.local\.caso=(caso-\d+)$') { $caso = $Matches[1] }
}
$noEjecuta = ($caso -and (($guion -eq 'sin-red-original' -and $original -and ($args -contains '-o')) -or ($guion -eq 'migrado-roto' -and -not $original -and $caso -eq 'caso-01')))
if ($noEjecuta) {
  if ($env:RESCATE_LLAMADAS) {
    [void](New-Item -ItemType Directory -Path $env:RESCATE_LLAMADAS -Force)
    [System.IO.File]::AppendAllText((Join-Path $env:RESCATE_LLAMADAS 'mvn.log'), ($raiz + '|' + $env:JAVA_HOME + '|' + ($args -join ' ') + "`n"))
  }
  '[ERROR] Failed to execute goal on project batch: Could not resolve dependencies (modo sin red)'
  exit 1
}
& (Join-Path $PSScriptRoot 'mvn-local.ps1') @args
$codigo = $LASTEXITCODE
if (-not $caso) { exit $codigo }
$salida = Join-Path $raiz "target/prueba-local/$job/$caso"
if (-not $original -and $guion -eq 'falla-migrado' -and $caso -eq 'caso-01') {
  [System.IO.File]::WriteAllText((Join-Path $salida 'estado.txt'), "estado=FAILED`n")
  $codigo = 1
}
if (-not $original -and $guion -eq 'falla-migrado' -and $caso -eq 'caso-02') {
  Remove-Item -LiteralPath (Join-Path $salida 'estado.txt') -Force
  [System.IO.File]::WriteAllText((Join-Path $salida 'error.txt'), "java.lang.IllegalStateException: el job ha fallado`n")
  $codigo = 1
}
$paquete = 'com.acme.nuevo'
if ($original) { $paquete = 'com.acme.viejo' }
$informe = Join-Path $raiz "target/surefire-reports/TEST-$paquete.PruebaLocalTest.xml"
if ((Test-Path -LiteralPath $salida) -and -not ($guion -eq 'xml-viejo' -and (Test-Path -LiteralPath $informe))) {
  $segundos = [Math]::Round(0.2 * [int]($caso -replace '\D', ''), 1).ToString([System.Globalization.CultureInfo]::InvariantCulture)
  [void](New-Item -ItemType Directory -Path (Split-Path $informe -Parent) -Force)
  [System.IO.File]::WriteAllText($informe, ('<?xml version="1.0" encoding="UTF-8"?>' + "`n" + '<testsuite name="' + $paquete + '.PruebaLocalTest" time="' + $segundos + '" tests="1" errors="0" skipped="0" failures="0">' + "`n" + '</testsuite>' + "`n"))
}
exit $codigo
