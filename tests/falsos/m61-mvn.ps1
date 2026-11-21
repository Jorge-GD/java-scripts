# m61-mvn.ps1 - Maven de mentira para los tests m61 de tests/probar-local.ps1. Hace lo de m40-mvn.ps1 (y con el, lo de mvn-local.ps1) y, ademas:
#  - Un 'mvn test' cuyo PruebaLocalTest.java lleva la linea '// M56_<nombre>' (m56-copilot.ps1 la deja) con uno de estos nombres no deja estado.txt y acaba
#    con un [ERROR] y la salida de un test que borra sus tablas una a una (los datos son inventados):
#      drop-en   H2 en ingles: Cannot drop "T_GRUPO" because "T_GRUPO" depends on it
#      drop-es   H2 en espanol: Imposible eliminar "T_GRUPO" debido a que "T_GRUPO" depende de el
#      drop-create  el drop-en y, ademas, un CREATE TABLE que H2 rechaza (como create-es de m56-mvn.ps1)
#  - RESCATE_M61 trae guiones 'nombre:regex' separados por ';' (la regex, sobre 'job/caso'; gana el primero). Cada caso que ejecuta el original (menos
#    vacio y otro) hace, segun el guion: no deja estado.txt y su error.txt dice que H2 rechaza un CREATE TABLE (el test tomo IF como nombre de tabla):
#      create-es       siempre, con el texto en espanol
#      create-en       siempre, con el texto en ingles
#      create-despues  en espanol, pero solo desde la segunda vez que el original ejecuta el caso (la primera, cuando la IA lo prepara, corre bien)
$raiz = (Get-Location).Path
$job = ''; $caso = ''
foreach ($a in $args) {
  if ("$a" -match '^-Dprueba\.local\.job=(.+)$') { $job = $Matches[1] }
  if ("$a" -match '^-Dprueba\.local\.caso=(.+)$') { $caso = $Matches[1] }
}
$guionTest = ''
if ($args -contains 'test') {
  $test = @(Get-ChildItem -LiteralPath (Join-Path $raiz 'src') -Recurse -File -Filter 'PruebaLocalTest.java')
  if ($test.Count -gt 0) { $guionTest = [regex]::Match([System.IO.File]::ReadAllText($test[0].FullName), '(?m)^// M56_(\S+)').Groups[1].Value }
}
if (@('drop-en', 'drop-es', 'drop-create') -contains $guionTest) {
  '[INFO] Running com.acme.nuevo.PruebaLocalTest'
  if ($guionTest -ne 'drop-es') { 'Caused by: org.h2.jdbc.JdbcSQLSyntaxErrorException: Cannot drop "T_GRUPO" because "T_GRUPO" depends on it; SQL statement:' }
  else { 'Caused by: org.h2.jdbc.JdbcSQLSyntaxErrorException: Imposible eliminar "T_GRUPO" debido a que "T_GRUPO" depende de el; SQL statement:' }
  'DROP TABLE IF EXISTS PUBLIC."T_GRUPO" [90107-240]'
  if ($guionTest -eq 'drop-create') { 'Caused by: org.h2.jdbc.JdbcSQLSyntaxErrorException: Error de Sintaxis en sentencia SQL "CREATE TABLE IF NOT EXISTS PUBLIC.IF[*] (IF VARCHAR(4000),NOT VARCHAR(4000),EXISTS VARCHAR(4000),T_COMIS VARCHAR(4000))"; se esperaba "identifier"; SQL statement:' }
  '[ERROR] Tests run: 1, Failures: 0, Errors: 1, Skipped: 0, Time elapsed: 1.2 s <<< FAILURE! - in com.acme.nuevo.PruebaLocalTest'
  '[ERROR] Failed to execute goal org.apache.maven.plugins:maven-surefire-plugin:2.22.2:test (default-test) on project batch-nuevo: There are test failures.'
  exit 1
}
$previas = 0
$registro = ''
if ($env:RESCATE_LLAMADAS) { $registro = Join-Path $env:RESCATE_LLAMADAS 'mvn.log' }
if ($registro -and $job -and $caso -and (Test-Path -LiteralPath $registro)) {
  $este = '-Dprueba.local.job=' + $job + ' -Dprueba.local.caso=' + $caso
  $previas = @([System.IO.File]::ReadAllLines($registro) | Where-Object { $_.StartsWith($raiz + '|') -and ($_ + ' ').Contains($este + ' ') }).Count
}
$salida = & (Join-Path $PSScriptRoot 'm40-mvn.ps1') @args
$codigo = $LASTEXITCODE
if ($env:RESCATE_M61 -and $job -and $caso -and $caso -ne 'vacio' -and $caso -ne 'otro' -and ($raiz -like '*batch-viejo*')) {
  $guion = ''
  foreach ($g in ($env:RESCATE_M61 -split ';')) {
    $nombre, $solo = ($g -split ':', 2)
    if (-not $solo) { $solo = '.' }
    if ($nombre -and -not $guion -and "$job/$caso" -match $solo) { $guion = $nombre }
  }
  $dir = Join-Path (Join-Path (Join-Path $raiz 'target/prueba-local') $job) $caso
  $sentencia = 'CREATE TABLE IF NOT EXISTS PUBLIC.IF[*] (IF VARCHAR(4000),NOT VARCHAR(4000),EXISTS VARCHAR(4000),T_COMIS VARCHAR(4000))'
  $fallo = ''
  if ($guion -eq 'create-es' -or ($guion -eq 'create-despues' -and $previas -gt 0)) { $fallo = 'org.h2.jdbc.JdbcSQLSyntaxErrorException: Error de Sintaxis en sentencia SQL "' + $sentencia + '"; se esperaba "identifier"; SQL statement:' }
  if ($guion -eq 'create-en') { $fallo = 'org.h2.jdbc.JdbcSQLSyntaxErrorException: Syntax error in SQL statement "' + $sentencia + '"; expected "identifier"; SQL statement:' }
  if ($fallo -and (Test-Path -LiteralPath $dir)) {
    Get-ChildItem -LiteralPath $dir | Remove-Item -Recurse -Force
    [System.IO.File]::WriteAllText((Join-Path $dir 'error.txt'), ($fallo + "`n"))
    '[ERROR] El test del original no prepara el caso'
    exit 1
  }
}
$salida
exit $codigo
