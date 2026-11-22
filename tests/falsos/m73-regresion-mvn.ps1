# m73-regresion-mvn.ps1 - Maven de mentira para el test m73 (d) de tests/probar-regresion.ps1. Hace lo de m33-mvn.ps1 y, antes de ejecutar los casos (un 'test'
# con -Dtest=...PruebaLocalTest..., con -Dprueba.local.job y -Dprueba.local.caso si los lleva), deja en la salida de cada caso ficheros/informe.xlsx (m73-libro.ps1):
# el mismo en el original y en el migrado, y los mismos bytes en cada ejecucion. RESCATE_M73 son palabras separadas por comas:
#   fecha=<caso>   el libro de ese caso lleva la fecha de hoy y una hora en una celda (Hoja1!A2); el de los demas casos, no lleva ninguna fecha
$raiz = (Get-Location).Path
$job = ''; $solo = ''
foreach ($a in $args) {
  if ("$a" -match '^-Dprueba\.local\.job=(.+)$') { $job = $Matches[1] }
  if ("$a" -match '^-Dprueba\.local\.caso=(.+)$') { $solo = $Matches[1] }
}
$prueba = @($args | Where-Object { "$_" -like '-Dtest=*' })
$casos = Join-Path $raiz 'src/test/resources/prueba-local'
if ($args -contains 'test' -and $prueba.Count -gt 0 -and "$($prueba[0])" -match 'PruebaLocalTest' -and (Test-Path -LiteralPath $casos)) {
  $palabras = @("$env:RESCATE_M73" -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  $hoy = (Get-Date).ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
  foreach ($dj in @(Get-ChildItem -LiteralPath $casos -Directory)) {
    if ($job -and $dj.Name -ne $job) { continue }
    foreach ($dc in @(Get-ChildItem -LiteralPath $dj.FullName -Directory)) {
      if ($solo -and $dc.Name -ne $solo) { continue }
      if ($dc.Name -eq 'vacio' -or $dc.Name -eq 'otro') { continue }
      $generado = 'por el batch'
      if ($palabras -contains ('fecha=' + $dc.Name)) { $generado = $hoy + ' 10:26:58' }
      & (Join-Path $PSScriptRoot 'm73-libro.ps1') ([System.IO.Path]::Combine($raiz, 'target', 'prueba-local', $dj.Name, $dc.Name, 'ficheros', 'informe.xlsx')) ($hoy + 'T10:26:58Z') $generado 'x'
    }
  }
}
& (Join-Path $PSScriptRoot 'm33-mvn.ps1') @args
exit $LASTEXITCODE
