# m47-mvn.ps1 - Maven de mentira para los tests m47 de tests/probar-local.ps1: pasa todo a mvn-local.ps1 y, con -v, dice ademas lo que dice
# 'mvn -v' (la version de Maven y la de Java, esta ultima la de la variable M47_JAVA).
& (Join-Path $PSScriptRoot 'mvn-local.ps1') @args
$codigo = $LASTEXITCODE
if ($args -contains '-v') {
  'Apache Maven 3.9.6 (de mentira)'
  'Maven home: /opt/maven'
  "Java version: $env:M47_JAVA, vendor: Acme, runtime: /opt/jdk"
  'Default locale: es_ES, platform encoding: UTF-8'
}
exit $codigo
