# prueba-local.ps1 - Prueba en local de mentira para tests/probar-migracion.ps1: hace lo que diga el JSON de $env:PRUEBA_LOCAL_FALSA y
# apunta cada llamada en <ese JSON>.llamadas (una linea por llamada: Legacy|Migrado|Modelo|JavaLegacy|Si).
#   json     si lo hay, se escribe en <Migrado>/migracion-*/datos/prueba-local.json (la carpeta migracion-* que haya).
#   salida   lineas que imprime.
#   codigo   con el que sale.
# Sin $env:PRUEBA_LOCAL_FALSA imprime que no tiene orden y sale con 1.
param([string]$Legacy = '', [string]$Migrado = '', [string]$Modelo = '', [string]$JavaLegacy = '', [string]$Job = '', [switch]$Si)
if (-not $env:PRUEBA_LOCAL_FALSA) { Write-Host 'prueba-local de mentira sin orden'; exit 1 }
$orden = [System.IO.File]::ReadAllText($env:PRUEBA_LOCAL_FALSA) | ConvertFrom-Json
[System.IO.File]::AppendAllText($env:PRUEBA_LOCAL_FALSA + '.llamadas', "$Legacy|$Migrado|$Modelo|$JavaLegacy|$Si`n")
if ($orden.json) {
  $salida = @(Get-ChildItem -LiteralPath $Migrado -Directory -Filter 'migracion-*')[0]
  [System.IO.File]::WriteAllText((Join-Path (Join-Path $salida.FullName 'datos') 'prueba-local.json'), (ConvertTo-Json -InputObject $orden.json -Depth 8))
}
foreach ($l in @($orden.salida | Where-Object { $_ })) { Write-Host $l }
exit ([int]$orden.codigo)
