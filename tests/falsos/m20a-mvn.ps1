# m20a-mvn.ps1 - Maven de mentira de los grupos de tests/probar.ps1 que ejecutan los tests: hace lo de mvn.ps1 y, si con 'test' sale con 0, deja
# los informes de surefire de lo que hay en src/test/java (m20a-informes.ps1), como Maven. mvn.ps1 solo deja el de los TEST_FALLA.
& (Join-Path $PSScriptRoot 'mvn.ps1') @args
$codigo = $LASTEXITCODE
if ($codigo -ne 0 -or $args -notcontains 'test') { exit $codigo }
& (Join-Path $PSScriptRoot 'm20a-informes.ps1')
exit $LASTEXITCODE
