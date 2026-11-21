# m56-mvn.ps1 - Maven de mentira para los tests m56 de tests/probar-local.ps1. Hace lo de mvn-local.ps1 salvo en un 'mvn test' cuyo
# PruebaLocalTest.java lleva la linea '// M56_<nombre>' (m56-copilot.ps1 la deja): ese test no deja estado.txt y Maven acaba con un [ERROR], con
# la salida de un contexto de Spring que no arranca, segun el nombre (los datos son inventados):
#   bean         un bean (clientesFinder) que llama fuera al crearse y falla con 'Error getting clientes'; su UnsatisfiedDependencyException lleva dos beans
#   bean-tabla   la misma cadena, pero el bean falla con Table "T_A" not found
#   create-es    H2 en espanol rechaza un CREATE TABLE IF NOT EXISTS PUBLIC.IF[*] (...): el test tomo IF como nombre de tabla
#   create-en    lo mismo con el texto en ingles
#   create-min   lo mismo en ingles y con la sentencia en minusculas
$raiz = (Get-Location).Path
$guion = ''
if ($args -contains 'test') {
  $test = @(Get-ChildItem -LiteralPath (Join-Path $raiz 'src') -Recurse -File -Filter 'PruebaLocalTest.java')
  if ($test.Count -gt 0) { $guion = [regex]::Match([System.IO.File]::ReadAllText($test[0].FullName), '(?m)^// M56_(\S+)').Groups[1].Value }
}
if (-not $guion) {
  & (Join-Path $PSScriptRoot 'mvn-local.ps1') @args
  exit $LASTEXITCODE
}
$bean = "org.springframework.beans.factory.UnsatisfiedDependencyException: Error creating bean with name 'reciboReader' defined in file [/obra/ReciboReader.class]: Unsatisfied dependency expressed through constructor parameter 0; nested exception is org.springframework.beans.factory.BeanCreationException: Error creating bean with name 'clientesFinder' defined in class path resource [com/acme/recibos/config/InformeConfig.class]: Failed to instantiate [com.acme.recibos.ports.ClientesFinder]: Factory method 'clientesFinder' threw exception with message: "
$sentencia = 'CREATE TABLE IF NOT EXISTS PUBLIC.IF[*] (IF VARCHAR(4000),NOT VARCHAR(4000),EXISTS VARCHAR(4000),T_COMIS VARCHAR(4000))'
'[INFO] Running com.acme.viejo.PruebaLocalTest'
'java.lang.IllegalStateException: Failed to load ApplicationContext'
if ($guion -eq 'bean') {
  $bean + 'Error getting clientes'
  'Caused by: com.acme.recibos.ClientesException: Error getting clientes'
}
elseif ($guion -eq 'bean-tabla') {
  $bean + 'bad SQL grammar [SELECT ID FROM T_A]; nested exception is org.h2.jdbc.JdbcSQLSyntaxErrorException: Table "T_A" not found (this database is empty)'
  'Caused by: org.h2.jdbc.JdbcSQLSyntaxErrorException: Table "T_A" not found (this database is empty); SQL statement:'
}
elseif ($guion -eq 'create-es') {
  'Caused by: org.h2.jdbc.JdbcSQLSyntaxErrorException: Error de Sintaxis en sentencia SQL "' + $sentencia + '"; se esperaba "identifier"; SQL statement:'
}
elseif ($guion -eq 'create-en') {
  'Caused by: org.h2.jdbc.JdbcSQLSyntaxErrorException: Syntax error in SQL statement "' + $sentencia + '"; expected "identifier"; SQL statement:'
}
else {
  'Caused by: org.h2.jdbc.JdbcSQLSyntaxErrorException: syntax error in sql statement "' + $sentencia.ToLowerInvariant() + '"; expected "identifier"; SQL statement:'
}
'[ERROR] Tests run: 1, Failures: 0, Errors: 1, Skipped: 0, Time elapsed: 1.2 s <<< FAILURE! - in com.acme.viejo.PruebaLocalTest'
'[ERROR] Failed to execute goal org.apache.maven.plugins:maven-surefire-plugin:2.22.2:test (default-test) on project batch-viejo: There are test failures.'
exit 1
