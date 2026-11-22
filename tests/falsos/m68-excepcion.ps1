# m68-excepcion.ps1 - Maven de mentira para los tests m68 (d) de tests/probar-local.ps1. Hace lo de m48-mvn.ps1 y, con RESCATE_M68='otra-clase', cada caso (no el
# vacio) que el migrado (batch-nuevo) deja con estado=EXCEPCION lleva salida=IllegalStateException y no la clase de m48-mvn.ps1 (BeanCreationException).
$raiz = (Get-Location).Path
$job = ''; $caso = ''
foreach ($a in $args) {
  if ("$a" -match '^-Dprueba\.local\.job=(.+)$') { $job = $Matches[1] }
  if ("$a" -match '^-Dprueba\.local\.caso=(.+)$') { $caso = $Matches[1] }
}
$salida = & (Join-Path $PSScriptRoot 'm48-mvn.ps1') @args
$codigo = $LASTEXITCODE
$estado = [System.IO.Path]::Combine($raiz, 'target', 'prueba-local', $job, $caso, 'estado.txt')
if ($env:RESCATE_M68 -eq 'otra-clase' -and $raiz -like '*batch-nuevo*' -and $job -and $caso -like 'caso-*' -and (Test-Path -LiteralPath $estado)) {
  $texto = [System.IO.File]::ReadAllText($estado)
  if ($texto -match 'estado=EXCEPCION') { [System.IO.File]::WriteAllText($estado, "estado=EXCEPCION`nsalida=IllegalStateException`n") }
}
$salida
exit $codigo
