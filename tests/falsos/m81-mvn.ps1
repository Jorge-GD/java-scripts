# m81-mvn.ps1 - Maven de mentira para los tests m81 de tests/probar-local.ps1 (cada caso con surefire:test, un solo test-compile por copia).
# Apunta cada llamada en RESCATE_LLAMADAS/mvn.log (carpeta|JAVA_HOME|argumentos, tal como llegan) y hace lo de m32-mvn.ps1 (y con el, lo de mvn-local.ps1:
# el XML de surefire con su time incluido) con 'surefire:test' como si fuera 'test'. RESCATE_M81 trae palabras separadas por ';':
#   argline               un surefire:test sin -DargLine= sale como un JaCoCo sin prepare-agent: la JVM no arranca ('Could not find or load main class @{argLine}'),
#                         sale con 1 y no deja nada; con -DargLine= va bien
#   sin-directo           un surefire:test no llega a ejecutar ningun test (sale con 1 y no deja nada); 'test' va bien
#   sin-directo-original  como sin-directo, solo en la copia del original (batch-viejo)
#   sin-estado-migrado    un surefire:test del migrado (batch-nuevo) ejecuta el test (deja TEST-<paquete>.PruebaLocalTest.xml) pero el contexto de Spring no arranca:
#                         no deja estado.txt ni error.txt y sale con 1 (el informe de surefire existe: el test llego a correr)
#   plano                 cada caso deja, en los dos lados, ficheros/a/<M81_CARPETA letras>/resultado_nnnnnnnnnnnnnnnnnnnn_<fecha de hoy>.txt: con la carpeta del
#                         proyecto corta, no cabe en salidas con nombre corto y si aplanado
#   sin-plano             cada caso deja, en los dos lados, <M81_CARPETA letras>/dato.txt: la primera carpeta ya es tan larga que ni aplanado cabe
#   compilar-lento        un test-compile (la compilacion de la copia) tarda 4 s mas que un caso: los tiempos de compilar y los de los casos salen distintos
$raiz = (Get-Location).Path
$original = ($raiz -like '*batch-viejo*')
$guiones = @("$env:RESCATE_M81" -split ';')
$directo = ($args -contains 'surefire:test')
if ($env:RESCATE_LLAMADAS) {
  [void](New-Item -ItemType Directory -Path $env:RESCATE_LLAMADAS -Force)
  [System.IO.File]::AppendAllText((Join-Path $env:RESCATE_LLAMADAS 'mvn.log'), ($raiz + '|' + $env:JAVA_HOME + '|' + ($args -join ' ') + "`n"))
}
if ($guiones -contains 'compilar-lento' -and $args -contains 'test-compile') { Start-Sleep -Seconds 4 }
if ($directo -and $guiones -contains 'argline' -and $args -notcontains '-DargLine=') {
  '[ERROR] Error: Could not find or load main class @{argLine}'
  '[ERROR] The forked VM terminated without properly saying goodbye. VM crash or System.exit called?'
  exit 1
}
if ($directo -and ($guiones -contains 'sin-directo' -or ($guiones -contains 'sin-directo-original' -and $original))) {
  '[ERROR] No tests were executed!  (Set -Dsurefire.failIfNoSpecifiedTests=false to ignore this error.)'
  exit 1
}
if ($directo -and $guiones -contains 'sin-estado-migrado' -and -not $original) {
  $informe = [System.IO.Path]::Combine([string[]]@($raiz, 'target', 'surefire-reports', 'TEST-com.acme.nuevo.PruebaLocalTest.xml'))
  [void](New-Item -ItemType Directory -Path (Split-Path $informe -Parent) -Force)
  [System.IO.File]::WriteAllText($informe, ('<?xml version="1.0" encoding="UTF-8"?>' + "`n" + '<testsuite name="com.acme.nuevo.PruebaLocalTest" time="0.3" tests="1" errors="1" skipped="0" failures="0"/>' + "`n"))
  '[ERROR] Tests run: 1, Failures: 0, Errors: 1, Skipped: 0'
  '[ERROR] Failed to load ApplicationContext'
  exit 1
}
$a = @($args | ForEach-Object { if ("$_" -eq 'surefire:test') { 'test' } else { "$_" } })
$env:RESCATE_LLAMADAS = ''   # la llamada ya esta apuntada: los falsos de debajo no la apuntan otra vez
& (Join-Path $PSScriptRoot 'm32-mvn.ps1') @a
$codigo = $LASTEXITCODE
$job = ''
$caso = ''
foreach ($x in $args) {
  if ("$x" -match '^-Dprueba\.local\.job=(.+)$') { $job = $Matches[1] }
  if ("$x" -match '^-Dprueba\.local\.caso=(caso-\d+)$') { $caso = $Matches[1] }
}
$dir = [System.IO.Path]::Combine([string[]]@($raiz, 'target', 'prueba-local', $job, $caso))
if ($codigo -eq 0 -and $job -and $caso -and (Test-Path -LiteralPath $dir) -and ($guiones -contains 'plano' -or $guiones -contains 'sin-plano')) {
  $rel = ('p' * [int]$env:M81_CARPETA) + '/dato.txt'
  if ($guiones -contains 'plano') { $rel = 'ficheros/a/' + ('c' * [int]$env:M81_CARPETA) + '/resultado_' + ('n' * 20) + '_' + (Get-Date).ToString('yyyyMMdd', [System.Globalization.CultureInfo]::InvariantCulture) + '.txt' }
  $f = [System.IO.Path]::Combine([string[]](@($dir) + $rel.Split('/')))
  [void](New-Item -ItemType Directory -Path (Split-Path $f -Parent) -Force)
  [System.IO.File]::WriteAllText($f, "ok`n")
}
exit $codigo
