# m48-mvn.ps1 - Maven de mentira para los tests m48 de tests/probar-local.ps1 y tests/probar-regresion.ps1. Hace lo de m33-mvn.ps1 (y con el, lo de
# m25-mvn.ps1 y mvn-local.ps1) y, si RESCATE_M48 trae guiones ('guion' o 'guion:regex', separados por ';'; la regex, sobre 'job/caso'; gana el primero que
# casa), cada ejecucion de un caso (-Dprueba.local.caso, tambien el vacio del arnes: 'job/vacio') deja ademas, segun el lado (batch-viejo = original):
#   largo               los dos lados: ficheros/logs/jobs/proceso-largo-nnn..._<fecha de hoy>.log, de M48_LARGO letras en total (un nombre con la fecha), con el
#                       mismo contenido
#   largo-fijo          como largo, sin la fecha en el nombre (de M48_LARGO letras en total, acaba en .log)
#   largo-distinto      como largo, pero el migrado lo escribe con otro contenido
#   sin-sitio           los dos lados: <200 letras>/<100 letras>/dato.txt (la primera carpeta ya es tan larga que ni un nombre corto aplanado cabe)
#   failed-mig          el migrado acaba estado=FAILED (el job corre y falla); Maven sale con 0 y escribe 'Caused by: java.lang.IllegalStateException: sin correo'
#   excepcion-orig      el original no arranca: estado=EXCEPCION, salida=BadSqlGrammarException, sin error.txt; Maven sale con 0 y escribe
#                       'Caused by: org.h2.jdbc.JdbcSQLSyntaxErrorException: Table "T_X" not found'
#   excepcion-ambos     los dos lados no arrancan: estado=EXCEPCION, salida=BeanCreationException, sin error.txt (el caso sale igual); Maven escribe lo de excepcion-mig
#   excepcion-mig       el migrado no arranca: estado=EXCEPCION, salida=BeanCreationException, sin error.txt; Maven sale con 0 y escribe
#                       'Caused by: java.lang.IllegalStateException: sin correo'
#   obstaculo           el migrado deja un FICHERO donde su carpeta ficheros\ va a guardarse (M48_OBSTACULO, la ruta completa): copiar a salidas\ falla
#   vacio-excepcion-mig solo en el caso vacio del arnes del migrado: las primeras M48_VACIOS veces (cuenta en RESCATE_LLAMADAS\m48vacios.cuenta) deja
#                       estado=EXCEPCION, salida=BeanCreationException (sin error.txt) y Maven escribe 'Caused by: ...BeanCreationException: sin correo'
$raiz = (Get-Location).Path
& (Join-Path $PSScriptRoot 'm33-mvn.ps1') @args
$codigo = $LASTEXITCODE
$job = ''; $caso = ''
foreach ($a in $args) {
  if ("$a" -match '^-Dprueba\.local\.job=(.+)$') { $job = $Matches[1] }
  if ("$a" -match '^-Dprueba\.local\.caso=(.+)$') { $caso = $Matches[1] }
}
$base = [System.IO.Path]::Combine($raiz, 'target', 'prueba-local')
if ($env:RESCATE_M48 -and $codigo -eq 0 -and $caso -and $caso -ne 'otro' -and (Test-Path -LiteralPath $base)) {
  $original = ($raiz -like '*batch-viejo*')
  $inv = [System.Globalization.CultureInfo]::InvariantCulture
  foreach ($dj in @(Get-ChildItem -LiteralPath $base -Directory | Sort-Object Name)) {
    if ($job -and $dj.Name -ne $job) { continue }
    $dir = [System.IO.Path]::Combine($base, $dj.Name, $caso)
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    $guion = ''
    foreach ($g in ($env:RESCATE_M48 -split ';')) {
      $nombre, $solo = ($g -split ':', 2)
      if (-not $solo) { $solo = '.' }
      if ($nombre -and -not $guion -and ($dj.Name + '/' + $caso) -match $solo) { $guion = $nombre }
    }
    function Escribe-Salida([string]$Rel, [string]$Texto) {
      $f = [System.IO.Path]::Combine([string[]](@($dir) + $Rel.Split('/')))
      [void](New-Item -ItemType Directory -Path (Split-Path $f -Parent) -Force)
      [System.IO.File]::WriteAllText($f, $Texto)
    }
    if ($guion -like 'largo*') {
      $texto = "ok`n"
      if ($guion -eq 'largo-distinto' -and -not $original) { $texto = "otro`n" }
      $sufijo = '.log'
      if ($guion -ne 'largo-fijo') { $sufijo = '_' + (Get-Date).ToString('yyyyMMdd', $inv) + '.log' }
      Escribe-Salida ('ficheros/logs/jobs/proceso-largo-' + ('n' * [Math]::Max(0, [int]$env:M48_LARGO - 14 - $sufijo.Length)) + $sufijo) $texto
    }
    if ($guion -eq 'obstaculo' -and -not $original) {
      [void](New-Item -ItemType Directory -Path (Split-Path $env:M48_OBSTACULO -Parent) -Force)
      [System.IO.File]::WriteAllText($env:M48_OBSTACULO, "no soy una carpeta`n")
    }
    if ($guion -eq 'sin-sitio') { Escribe-Salida (('a' * 200) + '/' + ('b' * 100) + '/dato.txt') "ok`n" }
    if ($guion -eq 'failed-mig' -and -not $original) {
      Escribe-Salida 'estado.txt' "estado=FAILED`nsalida=FAILED`n"
      'Caused by: java.lang.IllegalStateException: sin correo'
    }
    if ($guion -eq 'excepcion-orig' -and $original) {
      Get-ChildItem -LiteralPath $dir | Remove-Item -Recurse -Force
      Escribe-Salida 'estado.txt' "estado=EXCEPCION`nsalida=BadSqlGrammarException`n"
      'Caused by: org.h2.jdbc.JdbcSQLSyntaxErrorException: Table "T_X" not found'
    }
    if (($guion -eq 'excepcion-mig' -and -not $original) -or $guion -eq 'excepcion-ambos') {
      Get-ChildItem -LiteralPath $dir | Remove-Item -Recurse -Force
      Escribe-Salida 'estado.txt' "estado=EXCEPCION`nsalida=BeanCreationException`n"
      'Caused by: java.lang.IllegalStateException: sin correo'
    }
    if ($guion -eq 'vacio-excepcion-mig' -and -not $original -and $caso -eq 'vacio') {
      $cuenta = Join-Path $env:RESCATE_LLAMADAS 'm48vacios.cuenta'
      $n = 0
      if (Test-Path -LiteralPath $cuenta) { $n = [int][System.IO.File]::ReadAllText($cuenta).Trim() }
      if ($n -lt [int]$env:M48_VACIOS) {
        Get-ChildItem -LiteralPath $dir | Remove-Item -Recurse -Force
        Escribe-Salida 'estado.txt' "estado=EXCEPCION`nsalida=BeanCreationException`n"
        'Caused by: org.springframework.beans.factory.BeanCreationException: sin correo'
      }
      [System.IO.File]::WriteAllText($cuenta, "$($n + 1)`n")
    }
  }
}
exit $codigo
