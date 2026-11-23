# m83-mvn.ps1 - Maven de mentira para los tests m83 de tests/probar-local.ps1. Hace lo de m33-mvn.ps1 (y con el, lo de m25-mvn.ps1 y mvn-local.ps1) y, si
# RESCATE_M83 trae un guion ('guion' o 'guion:regex sobre job/caso'), cada ejecucion de un caso (-Dprueba.local.caso) de los dos lados deja ademas, con el
# mismo contenido:
#   plano     ficheros/a/<M83_CARPETA letras>/<fecha de hoy>-<hora>/informe-resumen-recibos-cobrados.xlsx (un libro que el job escribe en una carpeta
#             larga, con la fecha y la hora en la carpeta); no cabe en salidas\ ni con nombre corto, pero si aplanado (ficheros/<nombre corto>)
#   sin-sitio <200 letras>/a/informe-resumen-recibos-cobrados.xlsx (la primera carpeta ya mide tanto que ni aplanado cabe)
$raiz = (Get-Location).Path
& (Join-Path $PSScriptRoot 'm33-mvn.ps1') @args
$codigo = $LASTEXITCODE
$job = ''; $caso = ''
foreach ($a in $args) {
  if ("$a" -match '^-Dprueba\.local\.job=(.+)$') { $job = $Matches[1] }
  if ("$a" -match '^-Dprueba\.local\.caso=(.+)$') { $caso = $Matches[1] }
}
$base = [System.IO.Path]::Combine($raiz, 'target', 'prueba-local')
if ($env:RESCATE_M83 -and $codigo -eq 0 -and $caso -and $caso -ne 'otro' -and (Test-Path -LiteralPath $base)) {
  $inv = [System.Globalization.CultureInfo]::InvariantCulture
  foreach ($dj in @(Get-ChildItem -LiteralPath $base -Directory | Sort-Object Name)) {
    if ($job -and $dj.Name -ne $job) { continue }
    $dir = [System.IO.Path]::Combine($base, $dj.Name, $caso)
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    $guion = ''
    foreach ($g in ($env:RESCATE_M83 -split ';')) {
      $nombre, $solo = ($g -split ':', 2)
      if (-not $solo) { $solo = '.' }
      if ($nombre -and -not $guion -and ($dj.Name + '/' + $caso) -match $solo) { $guion = $nombre }
    }
    $rel = ''
    if ($guion -eq 'plano') { $rel = 'ficheros/a/' + ('c' * [int]$env:M83_CARPETA) + '/' + (Get-Date).ToString('yyyyMMdd-HHmmss', $inv) + '/informe-resumen-recibos-cobrados.xlsx' }
    if ($guion -eq 'sin-sitio') { $rel = ('c' * 200) + '/a/informe-resumen-recibos-cobrados.xlsx' }
    if (-not $rel) { continue }
    $f = [System.IO.Path]::Combine([string[]](@($dir) + $rel.Split('/')))
    [void](New-Item -ItemType Directory -Path (Split-Path $f -Parent) -Force)
    [System.IO.File]::WriteAllText($f, "ok`n")
  }
}
exit $codigo
