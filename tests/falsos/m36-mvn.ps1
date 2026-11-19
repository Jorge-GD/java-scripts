# m36-mvn.ps1 - Maven de mentira para los tests m36 de tests/probar-local.ps1. Hace lo de m31-mvn.ps1 (y con el, lo de m25-mvn.ps1 y mvn-local.ps1)
# y, si RESCATE_M36 trae guiones ('guion' o 'guion:regex', separados por ';'; la regex, sobre 'job/caso'; gana el primero que casa), cada caso
# que ejecuta (-Dprueba.local.job y -Dprueba.local.caso, menos vacio y otro) deja ademas, segun el lado (batch-viejo = original):
#   tabla-cabecera       original: tablas/T.csv con solo la cabecera; migrado: sin esa tabla
#   tabla-cabecera-mig   original: sin esa tabla; migrado: tablas/T.csv con solo la cabecera
#   tabla-fila           original: tablas/T.csv con la cabecera y una fila; migrado: sin esa tabla
#   tabla-fila-mig       original: sin esa tabla; migrado: tablas/T.csv con la cabecera y una fila
#   tabla-blancos        original: tablas/T.csv con la cabecera y lineas en blanco; migrado: sin esa tabla
#   excepcion            original: el job no arranca (estado=EXCEPCION, salida=IllegalStateException, error.txt con la causa y nada mas)
#   excepcion-sin-error  como excepcion, sin error.txt
#   failed               original: estado=FAILED y salida=FAILED, con lo demas que deja el caso
# El migrado deja lo de siempre en los guiones de excepcion y de failed.
$raiz = (Get-Location).Path
& (Join-Path $PSScriptRoot 'm31-mvn.ps1') @args
$codigo = $LASTEXITCODE
$job = ''; $caso = ''
foreach ($a in $args) {
  if ("$a" -match '^-Dprueba\.local\.job=(.+)$') { $job = $Matches[1] }
  if ("$a" -match '^-Dprueba\.local\.caso=(.+)$') { $caso = $Matches[1] }
}
if ($env:RESCATE_M36 -and $codigo -eq 0 -and $job -and $caso -and $caso -ne 'vacio' -and $caso -ne 'otro') {
  $original = ($raiz -like '*batch-viejo*')
  $guion = ''
  foreach ($g in ($env:RESCATE_M36 -split ';')) {
    $nombre, $solo = ($g -split ':', 2)
    if (-not $solo) { $solo = '.' }
    if ($nombre -and -not $guion -and "$job/$caso" -match $solo) { $guion = $nombre }
  }
  $dir = [System.IO.Path]::Combine($raiz, 'target', 'prueba-local', $job, $caso)
  function Escribe-Salida([string]$Rel, [string]$Texto) {
    $f = [System.IO.Path]::Combine([string[]](@($dir) + $Rel.Split('/')))
    [void](New-Item -ItemType Directory -Path (Split-Path $f -Parent) -Force)
    [System.IO.File]::WriteAllText($f, $Texto)
  }
  $lado = $original
  if ($guion -like 'tabla-*-mig') { $lado = -not $original }
  if ($guion -like 'tabla-*' -and $lado) {
    if ($guion -like 'tabla-cabecera*') { Escribe-Salida 'tablas/T.csv' "ID;NOMBRE`n" }
    if ($guion -like 'tabla-fila*') { Escribe-Salida 'tablas/T.csv' "ID;NOMBRE`n1;ana`n" }
    if ($guion -eq 'tabla-blancos') { Escribe-Salida 'tablas/T.csv' "ID;NOMBRE`n`n   `n`n" }
  }
  if ($original -and $guion -like 'excepcion*') {
    Get-ChildItem -LiteralPath $dir | Remove-Item -Recurse -Force
    Escribe-Salida 'estado.txt' "estado=EXCEPCION`nsalida=IllegalStateException`n"
    if ($guion -eq 'excepcion') { Escribe-Salida 'error.txt' "Could not resolve placeholder 'acme.entrada.ruta'`n    at com.acme.viejo.Lector.lee(Lector.java:10)`n" }
  }
  if ($original -and $guion -eq 'failed') { Escribe-Salida 'estado.txt' "estado=FAILED`nsalida=FAILED`n" }
}
exit $codigo
