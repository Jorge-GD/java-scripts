# arnes-mvn.ps1 - Maven de mentira para el grupo 'm18 arnes' de tests/probar-local.ps1 (prueba-local.ps1).
# Hace lo de mvn-local.ps1 salvo en un 'mvn test' con -Dsurefire.timeout=<n>, si RESCATE_ARNES_SUREFIRE vale 'si': ahi dice lo que
# dice Maven cuando Surefire mata el fork (SurefireHelper.createErrorMessage) y sale con 1. Con RESCATE_ARNES_SUREFIRE=2x, con la
# redaccion de Surefire 2.x ('There was a timeout or other error in the fork').
if (@('si', '2x') -contains "$env:RESCATE_ARNES_SUREFIRE" -and $args -contains 'test' -and @($args | Where-Object { "$_" -match '^-Dsurefire\.timeout=\d+$' }).Count -gt 0) {
  '[INFO] Running com.acme.nuevo.PruebaLocalTest'
  if ($env:RESCATE_ARNES_SUREFIRE -eq '2x') { '[ERROR] Failed to execute goal org.apache.maven.plugins:maven-surefire-plugin:2.22.2:test (default-test) on project batch-viejo: There was a timeout or other error in the fork -> [Help 1]' }
  else { '[ERROR] Failed to execute goal org.apache.maven.plugins:maven-surefire-plugin:3.2.5:test (default-test) on project batch-viejo: There was a timeout in the fork -> [Help 1]' }
  exit 1
}
& (Join-Path $PSScriptRoot 'mvn-local.ps1') @args
exit $LASTEXITCODE
