# m87-mvn.ps1 - Maven de mentira para los tests m87 de tests/probar-local.ps1. Hace lo de m48-mvn.ps1 (y con el, lo de m33-mvn.ps1 y mvn-local.ps1) y, si
# RESCATE_M87 trae una regex de nombres de job, en el caso vacio del arnes del ORIGINAL (batch-viejo; 'mvn test' con -Dprueba.local.caso=vacio): en las primeras
# M87_VECES ejecuciones (cuenta en RESCATE_LLAMADAS\m87vacios.cuenta, una por Maven y no por job) cada job que casa no deja estado.txt y su error.txt dice
# 'no se puede abrir el recurso de <job>'.
$raiz = (Get-Location).Path
$salida = & (Join-Path $PSScriptRoot 'm48-mvn.ps1') @args
$codigo = $LASTEXITCODE
$caso = ''
foreach ($a in $args) {
  if ("$a" -match '^-Dprueba\.local\.caso=(.+)$') { $caso = $Matches[1] }
}
$base = [System.IO.Path]::Combine($raiz, 'target', 'prueba-local')
if ($env:RESCATE_M87 -and $args -contains 'test' -and $caso -eq 'vacio' -and ($raiz -like '*batch-viejo*') -and (Test-Path -LiteralPath $base)) {
  $cuenta = Join-Path $env:RESCATE_LLAMADAS 'm87vacios.cuenta'
  $n = 0
  if (Test-Path -LiteralPath $cuenta) { $n = [int][System.IO.File]::ReadAllText($cuenta).Trim() }
  if ($n -lt [int]$env:M87_VECES) {
    foreach ($dj in @(Get-ChildItem -LiteralPath $base -Directory | Sort-Object Name)) {
      $dir = [System.IO.Path]::Combine($base, $dj.Name, 'vacio')
      if ($dj.Name -notmatch $env:RESCATE_M87 -or -not (Test-Path -LiteralPath $dir)) { continue }
      Get-ChildItem -LiteralPath $dir | Remove-Item -Recurse -Force
      [System.IO.File]::WriteAllText((Join-Path $dir 'error.txt'), "no se puede abrir el recurso de $($dj.Name)`n")
    }
  }
  [System.IO.File]::WriteAllText($cuenta, "$($n + 1)`n")
}
$salida
exit $codigo
