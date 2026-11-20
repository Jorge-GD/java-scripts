# m49-mvn.ps1 - Maven de mentira que apunta cada llamada y sigue con mvn.ps1. Variable:
#   M49_LLAMADAS   fichero: cada llamada anade una linea con sus argumentos.
if ($env:M49_LLAMADAS) { [System.IO.File]::AppendAllText($env:M49_LLAMADAS, (($args -join ' ') + "`n")) }
& (Join-Path $PSScriptRoot 'mvn.ps1') @args
exit $LASTEXITCODE
