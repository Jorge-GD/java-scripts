# m20a-cobertura-mvn.ps1 - Como m20a-mvn.ps1, sobre cobertura-mvn.ps1 (el Maven de mentira del grupo 'm14 cobertura').
& (Join-Path $PSScriptRoot 'cobertura-mvn.ps1') @args
$codigo = $LASTEXITCODE
if ($codigo -ne 0 -or $args -notcontains 'test') { exit $codigo }
& (Join-Path $PSScriptRoot 'm20a-informes.ps1')
exit $LASTEXITCODE
