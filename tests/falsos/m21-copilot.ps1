# m21-copilot.ps1 - Copilot CLI de mentira de las pruebas 'm21' (tests/probar.ps1): tarda RESCATE_M21_ESPERA segundos (2 si no esta), no toca nada y sale
# con 1. Asi el script ve un fallo de Copilot sin cambios, repite la llamada una vez, y los segundos de las dos llamadas salen en .rescate/intentos.tsv.
if ($args -contains '--version') { 'GitHub Copilot CLI 1.0.112 (de mentira).'; exit 0 }
$espera = 2
if ($env:RESCATE_M21_ESPERA) { $espera = [int]$env:RESCATE_M21_ESPERA }
Start-Sleep -Seconds $espera
'Error: de mentira, sin tocar nada'
exit 1
