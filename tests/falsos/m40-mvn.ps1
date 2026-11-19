# m40-mvn.ps1 - Maven de mentira para los tests m40 de tests/probar-local.ps1. Hace lo de mvn-local.ps1 y, ademas:
#  - Base de prueba: si el PruebaLocalTest.java de la copia lleva la linea '// BASE_TABLAS=T_A,T_B', cada salida de un caso (tambien la del
#    caso vacio) lleva tablas/T_A.csv y tablas/T_B.csv con la cabecera 'ID;NOMBRE' (lo que dejaria el arnes de verdad con esa base).
#  - RESCATE_M40 trae guiones ('guion=valor:regex' o 'guion:regex', separados por ';'; la regex, sobre 'job/caso'; gana el primero). Cada caso
#    que ejecuta (-Dprueba.local.job y -Dprueba.local.caso, menos vacio y otro) hace, segun el guion y el lado (batch-viejo = original):
#   falta-tabla=T_A      original, solo la primera vez que se ejecuta el caso: el test no llega a preparar el caso (sin estado.txt) y su
#                        error.txt dice 'Tabla "T_A" no encontrada' (ScriptStatementFailedException de un datos.sql, con el H2 en espanol)
#   falta-columna=T_A.X  como falta-tabla, con 'Columna "X" no encontrada' en un INSERT INTO T_A
#   migrado-no-corre     migrado: no deja nada (ni estado.txt) y Maven acaba con un [ERROR]
$raiz = (Get-Location).Path
$job = ''; $caso = ''
foreach ($a in $args) {
  if ("$a" -match '^-Dprueba\.local\.job=(.+)$') { $job = $Matches[1] }
  if ("$a" -match '^-Dprueba\.local\.caso=(.+)$') { $caso = $Matches[1] }
}
$previas = 0
$registro = ''
if ($env:RESCATE_LLAMADAS) { $registro = Join-Path $env:RESCATE_LLAMADAS 'mvn.log' }
if ($registro -and $job -and $caso -and (Test-Path -LiteralPath $registro)) {
  $este = '-Dprueba.local.job=' + $job + ' -Dprueba.local.caso=' + $caso
  $previas = @([System.IO.File]::ReadAllLines($registro) | Where-Object { $_.StartsWith($raiz + '|') -and ($_ + ' ').Contains($este + ' ') }).Count
}
& (Join-Path $PSScriptRoot 'mvn-local.ps1') @args
$codigo = $LASTEXITCODE
if ($codigo -ne 0 -or $args -notcontains 'test') { exit $codigo }

$base = Join-Path $raiz 'target/prueba-local'
$test = @(Get-ChildItem -LiteralPath (Join-Path $raiz 'src') -Recurse -File -Filter 'PruebaLocalTest.java')
if ($test.Count -gt 0 -and (Test-Path -LiteralPath $base)) {
  $m = [regex]::Match([System.IO.File]::ReadAllText($test[0].FullName), '(?m)^// BASE_TABLAS=(\S+)')
  if ($m.Success) {
    foreach ($d in @(Get-ChildItem -LiteralPath $base -Directory | ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Directory })) {
      foreach ($t in ($m.Groups[1].Value -split ',')) {
        $f = Join-Path (Join-Path $d.FullName 'tablas') ($t + '.csv')
        if (-not (Test-Path -LiteralPath $f)) {
          [void](New-Item -ItemType Directory -Path (Split-Path $f -Parent) -Force)
          [System.IO.File]::WriteAllText($f, "ID;NOMBRE`n")
        }
      }
    }
  }
}

if ($env:RESCATE_M40 -and $job -and $caso -and $caso -ne 'vacio' -and $caso -ne 'otro') {
  $original = ($raiz -like '*batch-viejo*')
  $guion = ''
  foreach ($g in ($env:RESCATE_M40 -split ';')) {
    $nombre, $solo = ($g -split ':', 2)
    if (-not $solo) { $solo = '.' }
    if ($nombre -and -not $guion -and "$job/$caso" -match $solo) { $guion = $nombre }
  }
  $nombre, $valor = ($guion -split '=', 2)
  $dir = Join-Path (Join-Path $base $job) $caso
  $fallo = ''
  if ($original -and $previas -eq 0 -and $nombre -eq 'falta-tabla') {
    $fallo = "org.springframework.jdbc.datasource.init.ScriptStatementFailedException: Failed to execute SQL script statement #1 of class path resource [prueba-local/$job/$caso/datos.sql]: INSERT INTO $valor (ID) VALUES (1); nested exception is org.h2.jdbc.JdbcSQLSyntaxErrorException: Tabla `"$valor`" no encontrada; Sentencia SQL: INSERT INTO $valor (ID) VALUES (1) [42102-200]"
  }
  if ($original -and $previas -eq 0 -and $nombre -eq 'falta-columna') {
    $tabla, $columna = ($valor -split '\.', 2)
    $fallo = "org.springframework.jdbc.datasource.init.ScriptStatementFailedException: Failed to execute SQL script statement #1 of class path resource [prueba-local/$job/$caso/datos.sql]: INSERT INTO $tabla (ID, $columna) VALUES (1, 2); nested exception is org.h2.jdbc.JdbcSQLSyntaxErrorException: Columna `"$columna`" no encontrada; Sentencia SQL: INSERT INTO $tabla (ID, $columna) VALUES (1, 2) [42122-200]"
  }
  if ($fallo) {
    Get-ChildItem -LiteralPath $dir | Remove-Item -Recurse -Force
    [System.IO.File]::WriteAllText((Join-Path $dir 'error.txt'), ($fallo + "`n"))
    exit 1
  }
  if (-not $original -and $nombre -eq 'migrado-no-corre') {
    Get-ChildItem -LiteralPath $dir | Remove-Item -Recurse -Force
    '[ERROR] El job del migrado no arranca: el contexto de mentira esta roto'
    exit 1
  }
}
exit $codigo
