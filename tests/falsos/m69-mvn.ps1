# m69-mvn.ps1 - Maven de mentira para los tests m69 de tests/probar-local.ps1. Hace lo de m40-mvn.ps1 (y con el, lo de mvn-local.ps1) y, en un 'test' del
# caso vacio (-Dprueba.local.caso=vacio), lo que digan las lineas '// M69_<clave>=<valor>' del PruebaLocalTest.java de la copia (m69-copilot.ps1 las deja):
#   M69_VACIO=<estado>[:<regex sobre el job>]   el estado de cada caso vacio (o solo el de los jobs que casan): FAILED, EXCEPCION (salida=BeanCreationException)...
#                                              Sin la marca, COMPLETED (lo de mvn-local.ps1)
#   M69_CAUSA=<texto>                           Maven escribe 'Caused by: <texto>' (la causa que Get-CausaMaven le saca a un job que acaba mal)
#   M69_TABLAS=T_A:ID|NOMBRE,T_B:ID             cada caso vacio deja tablas\<T>.csv con esa cabecera (las columnas, separadas por ';'), tambien si ya estaba
$raiz = (Get-Location).Path
$salida = & (Join-Path $PSScriptRoot 'm40-mvn.ps1') @args
$codigo = $LASTEXITCODE
$caso = ''
foreach ($a in $args) { if ("$a" -match '^-Dprueba\.local\.caso=(.+)$') { $caso = $Matches[1] } }
$base = Join-Path (Join-Path $raiz 'target') 'prueba-local'
$test = @(Get-ChildItem -LiteralPath (Join-Path $raiz 'src') -Recurse -File -Filter 'PruebaLocalTest.java')
$causa = ''
if ($args -contains 'test' -and $caso -eq 'vacio' -and $codigo -eq 0 -and $test.Count -gt 0 -and (Test-Path -LiteralPath $base)) {
  $m = @{}
  foreach ($l in [System.IO.File]::ReadAllLines($test[0].FullName)) { if ($l -match '^// M69_(\w+)=(.*)$') { $m[$Matches[1]] = $Matches[2] } }
  $estado, $jobs = ("$($m['VACIO'])" -split ':', 2)
  foreach ($d in @(Get-ChildItem -LiteralPath $base -Directory)) {
    $dir = Join-Path (Join-Path $base $d.Name) 'vacio'
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    if ($estado -and (-not $jobs -or $d.Name -match $jobs)) {
      $clase = $estado
      if ($estado -eq 'EXCEPCION') { $clase = 'BeanCreationException' }
      [System.IO.File]::WriteAllText((Join-Path $dir 'estado.txt'), "estado=$estado`nsalida=$clase`n")
      if ($m['CAUSA']) { $causa = 'Caused by: ' + $m['CAUSA'] }
    }
    foreach ($t in ("$($m['TABLAS'])" -split ',')) {
      if (-not $t) { continue }
      $nombre, $columnas = ($t -split ':', 2)
      $f = Join-Path (Join-Path $dir 'tablas') ($nombre + '.csv')
      [void](New-Item -ItemType Directory -Path (Split-Path $f -Parent) -Force)
      [System.IO.File]::WriteAllText($f, (($columnas -replace '\|', ';') + "`n"))
    }
  }
}
$salida
if ($causa) { $causa }
exit $codigo
