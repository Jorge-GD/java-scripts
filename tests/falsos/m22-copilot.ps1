# m22-copilot.ps1 - Copilot CLI de mentira de las pruebas 'm22' (tests/probar.ps1): hace lo de copilot.ps1 y, con RESCATE_M22_CORTA=<n>, en su llamada n-esima
# (las cuenta en la carpeta RESCATE_M22_ESTADO, fichero copilot.n) deja un fichero nuevo en la carpeta RESCATE_M22_TOCA, la del repo original que rescate.ps1
# vigila: el script lo ve, deshace el lote y para con 'ALTO' (exit 4), como una pasada que se corta tras los lotes anteriores.
if ($args -contains '-p' -and $env:RESCATE_M22_CORTA -and $env:RESCATE_M22_ESTADO) {
  [void](New-Item -ItemType Directory -Path $env:RESCATE_M22_ESTADO -Force)
  $f = Join-Path $env:RESCATE_M22_ESTADO 'copilot.n'
  $n = 0
  if (Test-Path -LiteralPath $f) { $n = [int][System.IO.File]::ReadAllText($f).Trim() }
  $n++
  [System.IO.File]::WriteAllText($f, "$n")
  if ($n -eq [int]$env:RESCATE_M22_CORTA) { [System.IO.File]::WriteAllText((Join-Path $env:RESCATE_M22_TOCA "tocado-$n.txt"), 'lo ha tocado el modelo') }
}
& (Join-Path $PSScriptRoot 'copilot.ps1') @args
exit $LASTEXITCODE
