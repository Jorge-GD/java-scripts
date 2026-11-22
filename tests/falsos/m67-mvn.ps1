# m67-mvn.ps1 - Maven de mentira para los tests m67 de tests/probar-local.ps1. Hace lo de m25-mvn.ps1 (y con el, lo de mvn-local.ps1) y, en cada caso que ejecuta
# (-Dprueba.local.job y -Dprueba.local.caso; ni el vacio ni 'otro'), saca de ficheros/salida/resultado_<hoy>.txt un fichero con el nombre CIERRE_2024_06_<n>.txt
# (n, el numero del caso: cada caso, otra fecha) y lo deja donde digan las banderas de RESCATE_M67, separadas por ';':
#   sin banderas  el original lo deja en trabajo/enviados y en ficheros/enviados; el migrado, en ficheros/salida si su regla.txt lleva minimo=5.01 (el codigo que lo
#                 deja en otra carpeta) y como el original con minimo=5.00 (lo que arregla reparar-arregla, de m25-copilot.ps1)
#   misma         los dos lados lo dejan en ficheros/salida
#   contenido     el migrado lleva una linea mas en ese fichero
#   log           el nombre acaba en .log, y el resultado_<hoy>.txt se queda donde esta (el caso no es igual al vacio, que es lo que diria 'el test no le pasa las entradas')
#   suelto        el migrado deja ademas ficheros/solo-migrado.txt, un nombre que el original no tiene
$raiz = (Get-Location).Path
$job = ''; $caso = ''
foreach ($a in $args) {
  if ("$a" -match '^-Dprueba\.local\.job=(.+)$') { $job = $Matches[1] }
  if ("$a" -match '^-Dprueba\.local\.caso=(.+)$') { $caso = $Matches[1] }
}
$salida = & (Join-Path $PSScriptRoot 'm25-mvn.ps1') @args
$codigo = $LASTEXITCODE
$dir = [System.IO.Path]::Combine($raiz, 'target', 'prueba-local', $job, $caso)
if ($args -notcontains 'test' -or -not $job -or -not $caso -or $caso -eq 'otro' -or $caso -eq 'vacio' -or -not (Test-Path -LiteralPath $dir)) { $salida; exit $codigo }
$banderas = @("$env:RESCATE_M67" -split ';')
$migrado = ($raiz -like '*batch-nuevo*')
$regla = Join-Path $raiz 'src/main/resources/regla.txt'
$lleva501 = ((Test-Path -LiteralPath $regla) -and [System.IO.File]::ReadAllText($regla).Contains('minimo=5.01'))
$origen = @(Get-ChildItem -LiteralPath $dir -Recurse -File -Filter 'resultado_*.txt')
if ($origen.Count -eq 0) { $salida; exit $codigo }
$nombre = 'CIERRE_2024_06_' + ($caso -replace '\D', '')
if ($banderas -contains 'log') { $nombre += '.log' } else { $nombre += '.txt' }
$texto = [System.IO.File]::ReadAllText($origen[0].FullName)
if ($banderas -notcontains 'log') { Remove-Item -LiteralPath $origen[0].FullName }
if ($banderas -contains 'misma') { $carpetas = @('ficheros/salida') }
elseif ($migrado -and $lleva501) { $carpetas = @('ficheros/salida') }
else { $carpetas = @('trabajo/enviados', 'ficheros/enviados') }
if ($migrado -and $banderas -contains 'contenido') { $texto += "una linea mas del migrado`n" }
foreach ($c in $carpetas) {
  $f = [System.IO.Path]::Combine([string[]](@($dir) + $c.Split('/') + $nombre))
  [void](New-Item -ItemType Directory -Path (Split-Path $f -Parent) -Force)
  [System.IO.File]::WriteAllText($f, $texto)
}
if ($migrado -and $banderas -contains 'suelto') { [System.IO.File]::WriteAllText([System.IO.Path]::Combine($dir, 'ficheros', 'solo-migrado.txt'), "solo el migrado`n") }
$salida
exit $codigo
