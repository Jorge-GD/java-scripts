# m68-mvn.ps1 - Maven de mentira para los tests m68 de tests/probar-local.ps1. Hace lo de m40-mvn.ps1 (y con el, lo de mvn-local.ps1: la base de prueba de la
# linea '// BASE_TABLAS=T_A,T_B' del PruebaLocalTest.java) y, en cada caso que ejecuta (-Dprueba.local.job y -Dprueba.local.caso; ni el vacio ni 'otro'):
#  - Apunta en RESCATE_LLAMADAS/m68-sql.log una linea 'carpeta|job/caso|<datos.sql en una sola linea, con \n por cada salto>': el datos.sql que vio de verdad el caso.
#  - Hace de H2: si su datos.sql hace CREATE TABLE <T> sin IF NOT EXISTS y T es una de BASE_TABLAS (el test ya la crea), no deja estado.txt y su error.txt dice
#    'Tabla "T" ya existe' (con la bandera en, 'Table "T" already exists') y el codigo 42101. Con IF NOT EXISTS, el caso corre.
#  - RESCATE_M68 trae banderas separadas por ';':
#      en        el error de arriba, en ingles
$raiz = (Get-Location).Path
$job = ''; $caso = ''
foreach ($a in $args) {
  if ("$a" -match '^-Dprueba\.local\.job=(.+)$') { $job = $Matches[1] }
  if ("$a" -match '^-Dprueba\.local\.caso=(.+)$') { $caso = $Matches[1] }
}
$salida = & (Join-Path $PSScriptRoot 'm40-mvn.ps1') @args
$codigo = $LASTEXITCODE
if ($args -notcontains 'test' -or -not $job -or -not $caso -or $caso -eq 'otro') { $salida; exit $codigo }
$banderas = @("$env:RESCATE_M68" -split ';')
$dir = [System.IO.Path]::Combine($raiz, 'target', 'prueba-local', $job, $caso)
$sql = [System.IO.Path]::Combine($raiz, 'src', 'test', 'resources', 'prueba-local', $job, $caso, 'datos.sql')
if ($caso -ne 'vacio' -and (Test-Path -LiteralPath $sql)) {
  $texto = [System.IO.File]::ReadAllText($sql)
  if ($env:RESCATE_LLAMADAS) {
    [void](New-Item -ItemType Directory -Path $env:RESCATE_LLAMADAS -Force)
    [System.IO.File]::AppendAllText((Join-Path $env:RESCATE_LLAMADAS 'm68-sql.log'), ($raiz + '|' + $job + '/' + $caso + '|' + ($texto.TrimEnd() -replace "`r?`n", '\n') + "`n"))
  }
  $test = @(Get-ChildItem -LiteralPath (Join-Path $raiz 'src') -Recurse -File -Filter 'PruebaLocalTest.java')
  $base = @()
  if ($test.Count -gt 0) { $base = @(([regex]::Match([System.IO.File]::ReadAllText($test[0].FullName), '(?m)^// BASE_TABLAS=(\S+)').Groups[1].Value) -split ',') }
  $ya = ''
  foreach ($m in [regex]::Matches($texto, '(?i)\bCREATE\s+TABLE\s+(?!IF\s+NOT\s+EXISTS\b)(\w+)')) {
    if (-not $ya -and $base -contains $m.Groups[1].Value.ToUpperInvariant()) { $ya = $m.Groups[1].Value.ToUpperInvariant() }
  }
  if ($ya -and (Test-Path -LiteralPath $dir)) {
    $frase = "Tabla `"$ya`" ya existe; Sentencia SQL"
    if ($banderas -contains 'en') { $frase = "Table `"$ya`" already exists; SQL statement" }
    $fallo = "org.springframework.jdbc.datasource.init.ScriptStatementFailedException: Failed to execute SQL script statement #1 of class path resource [prueba-local/$job/$caso/datos.sql]: CREATE TABLE $ya (ID INT); nested exception is org.h2.jdbc.JdbcSQLSyntaxErrorException: ${frase}: CREATE TABLE $ya (ID INT) [42101-200]"
    Get-ChildItem -LiteralPath $dir | Remove-Item -Recurse -Force
    [System.IO.File]::WriteAllText((Join-Path $dir 'error.txt'), ($fallo + "`n"))
    '[ERROR] El test no prepara el caso'
    exit 1
  }
}
$salida
exit $codigo
