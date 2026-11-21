# m62-mvn.ps1 - Maven de mentira para los tests m62 de tests/probar-local.ps1. Hace lo de m61-mvn.ps1 (y con el, lo de m40-mvn.ps1 y mvn-local.ps1) y, ademas:
#  - Un 'mvn test' cuyo PruebaLocalTest.java lleva la linea '// M56_columnas' (m56-copilot.ps1 la deja) no deja estado.txt y acaba con un [ERROR] y la
#    salida de un test cuya base no tiene cinco columnas (COD_ZONA, IMPORTE, COD_ZONA otra vez, ID y NOMBRE), en ingles y en espanol, cada una con su SQL
#    en la linea de abajo (los datos son inventados).
#  - RESCATE_M62 trae guiones 'nombre=TABLA.COLUMNA:regex' separados por ';' (la regex, sobre 'job/caso'; gana el primero). Cada caso que ejecuta el
#    original (menos vacio y otro) hace, segun el guion: no deja estado.txt y su error.txt dice que a la tabla le falta la columna, al cargar su datos.sql:
#      es, en              siempre, en espanol o en ingles
#      despues, despues-en desde la segunda vez que el original ejecuta el caso, en espanol o en ingles (la primera, cuando la IA lo prepara, corre bien)
$raiz = (Get-Location).Path
$job = ''; $caso = ''
foreach ($a in $args) {
  if ("$a" -match '^-Dprueba\.local\.job=(.+)$') { $job = $Matches[1] }
  if ("$a" -match '^-Dprueba\.local\.caso=(.+)$') { $caso = $Matches[1] }
}
if ($args -contains 'test') {
  $test = @(Get-ChildItem -LiteralPath (Join-Path $raiz 'src') -Recurse -File -Filter 'PruebaLocalTest.java')
  if ($test.Count -gt 0 -and [regex]::Match([System.IO.File]::ReadAllText($test[0].FullName), '(?m)^// M56_(\S+)').Groups[1].Value -eq 'columnas') {
    '[INFO] Running com.acme.viejo.PruebaLocalTest'
    $falta = @(
      @('Column "COD_ZONA" not found; SQL statement:', 'INSERT INTO T_A (ID, COD_ZONA) VALUES (1, 2) [42122-200]'),
      @('Columna "IMPORTE" no encontrada; Sentencia SQL:', 'SELECT IMPORTE FROM T_A WHERE ID = 1 [42122-200]'),
      @('Column "COD_ZONA" not found; SQL statement:', 'INSERT INTO T_A (ID, COD_ZONA) VALUES (3, 4) [42122-200]'),
      @('Columna "ID" no encontrada; Sentencia SQL:', 'SELECT ID FROM T_A [42122-200]'),
      @('Column "NOMBRE" not found; SQL statement:', 'SELECT NOMBRE FROM T_A [42122-200]'))
    foreach ($f in $falta) { 'Caused by: org.h2.jdbc.JdbcSQLSyntaxErrorException: ' + $f[0]; $f[1] }
    '[ERROR] Tests run: 1, Failures: 0, Errors: 1, Skipped: 0, Time elapsed: 1.2 s <<< FAILURE! - in com.acme.viejo.PruebaLocalTest'
    '[ERROR] Failed to execute goal org.apache.maven.plugins:maven-surefire-plugin:2.22.2:test (default-test) on project batch-viejo: There are test failures.'
    exit 1
  }
}
$previas = 0
$registro = ''
if ($env:RESCATE_LLAMADAS) { $registro = Join-Path $env:RESCATE_LLAMADAS 'mvn.log' }
if ($registro -and $job -and $caso -and (Test-Path -LiteralPath $registro)) {
  $este = '-Dprueba.local.job=' + $job + ' -Dprueba.local.caso=' + $caso
  $previas = @([System.IO.File]::ReadAllLines($registro) | Where-Object { $_.StartsWith($raiz + '|') -and ($_ + ' ').Contains($este + ' ') }).Count
}
$salida = & (Join-Path $PSScriptRoot 'm61-mvn.ps1') @args
$codigo = $LASTEXITCODE
if ($env:RESCATE_M62 -and $job -and $caso -and $caso -ne 'vacio' -and $caso -ne 'otro' -and ($raiz -like '*batch-viejo*')) {
  $guion = ''
  $columna = ''
  foreach ($g in ($env:RESCATE_M62 -split ';')) {
    $cabeza, $solo = ($g -split ':', 2)
    if (-not $solo) { $solo = '.' }
    if ($cabeza -and -not $guion -and "$job/$caso" -match $solo) { $guion, $columna = ($cabeza -split '=', 2) }
  }
  $dir = Join-Path (Join-Path (Join-Path $raiz 'target/prueba-local') $job) $caso
  $fallo = ''
  if ($guion -and $columna -and ($guion -in @('es', 'en') -or $previas -gt 0)) {
    $tabla, $nombre = ($columna -split '\.', 2)
    $sql = "INSERT INTO $tabla (ID, $nombre) VALUES ('01', 'Z1')"
    if ($guion -in @('es', 'despues')) { $dicho = "Columna `"$nombre`" no encontrada; Sentencia SQL: $sql [42122-200]" }
    else { $dicho = "Column `"$nombre`" not found; SQL statement: $sql [42122-200]" }
    $fallo = "org.springframework.jdbc.datasource.init.ScriptStatementFailedException: Failed to execute SQL script statement #1 of file [prueba-local/$job/$caso/datos.sql]: $sql; nested exception is org.h2.jdbc.JdbcSQLSyntaxErrorException: $dicho"
  }
  if ($fallo -and (Test-Path -LiteralPath $dir)) {
    Get-ChildItem -LiteralPath $dir | Remove-Item -Recurse -Force
    [System.IO.File]::WriteAllText((Join-Path $dir 'error.txt'), ($fallo + "`n"))
    '[ERROR] El test del original no prepara el caso'
    exit 1
  }
}
$salida
exit $codigo
