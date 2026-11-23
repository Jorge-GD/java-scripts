# m89-mvn.ps1 - Maven de mentira para los tests m89 de tests/probar-local.ps1. Hace lo de m25-mvn.ps1 (y con el, lo de mvn-local.ps1) y, en cada caso que ejecuta
# (-Dprueba.local.job y -Dprueba.local.caso; ni el vacio ni 'otro'), hace que el migrado deje donde estaba el fichero de entrada ficheros/entrada/datos.txt del caso
# (el original lo quita al procesarlo: no lo deja) y, ademas, un fichero que no es de entrada, ficheros/entrada/extra.txt.
$raiz = (Get-Location).Path
$job = ''; $caso = ''
foreach ($a in $args) {
  if ("$a" -match '^-Dprueba\.local\.job=(.+)$') { $job = $Matches[1] }
  if ("$a" -match '^-Dprueba\.local\.caso=(.+)$') { $caso = $Matches[1] }
}
$salida = & (Join-Path $PSScriptRoot 'm25-mvn.ps1') @args
$codigo = $LASTEXITCODE
$dir = [System.IO.Path]::Combine($raiz, 'target', 'prueba-local', $job, $caso)
$entrada = [System.IO.Path]::Combine($raiz, 'src', 'test', 'resources', 'prueba-local', $job, $caso, 'ficheros', 'entrada', 'datos.txt')
if ($args -notcontains 'test' -or -not $job -or -not $caso -or $caso -eq 'otro' -or $caso -eq 'vacio' -or -not (Test-Path -LiteralPath $dir) -or $raiz -notlike '*batch-nuevo*' -or -not (Test-Path -LiteralPath $entrada)) { $salida; exit $codigo }
$donde = [System.IO.Path]::Combine($dir, 'ficheros', 'entrada')
[void](New-Item -ItemType Directory -Path $donde -Force)
Copy-Item -LiteralPath $entrada -Destination (Join-Path $donde 'datos.txt') -Force
[System.IO.File]::WriteAllText((Join-Path $donde 'extra.txt'), "no es de entrada`n")
$salida
exit $codigo
