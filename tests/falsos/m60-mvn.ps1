# m60-mvn.ps1 - Maven de mentira para los tests m60 de tests/probar-local.ps1. Con un PruebaLocalTest que lleva la linea '// M56_<nombre>'
# (m56-copilot.ps1 la deja) y uno de estos nombres, el 'mvn test' no deja estado.txt y acaba con un [ERROR] y la salida de un contexto de Spring
# que no arranca (los datos son inventados); con cualquier otro nombre o sin nombre hace lo de m56-mvn.ps1 (y, con el, lo de mvn-local.ps1):
#   prop-export     un job (exportJob) cuya propiedad app.export.dir no tiene valor: la cadena de beans de abajo arriba y 'app.export.dir is not configured'
#   placeholder     Could not resolve placeholder 'app.sftp.host' in value "${app.sftp.host}"
#   bind            Failed to bind properties under 'app.limites' to com.acme.Limites
#   bean-conexion   la cadena de un bean que llama fuera y falla con java.lang.IllegalStateException: Connection refused, y una linea 'host is not set' (sin punto)
#   prop-dos        dos propiedades: app.sftp.host (tres veces, de tres maneras) y app.export.dir
#   prop-create     un CREATE TABLE que H2 rechaza (como create-es de m56-mvn.ps1) y, ademas, app.export.dir is not configured
#   prop-cuatro     cuatro propiedades distintas sin valor: app.uno.dir, app.dos.dir, app.tres.dir y app.cuatro.dir
$raiz = (Get-Location).Path
$guion = ''
if ($args -contains 'test') {
  $test = @(Get-ChildItem -LiteralPath (Join-Path $raiz 'src') -Recurse -File -Filter 'PruebaLocalTest.java')
  if ($test.Count -gt 0) { $guion = [regex]::Match([System.IO.File]::ReadAllText($test[0].FullName), '(?m)^// M56_(\S+)').Groups[1].Value }
}
if (@('prop-export', 'placeholder', 'bind', 'bean-conexion', 'prop-dos', 'prop-create', 'prop-cuatro') -notcontains $guion) {
  & (Join-Path $PSScriptRoot 'm56-mvn.ps1') @args
  exit $LASTEXITCODE
}
$bean = "org.springframework.beans.factory.UnsatisfiedDependencyException: Error creating bean with name 'reciboReader' defined in file [/obra/ReciboReader.class]: Unsatisfied dependency expressed through constructor parameter 0; nested exception is org.springframework.beans.factory.BeanCreationException: Error creating bean with name 'clientesFinder' defined in class path resource [com/acme/recibos/config/InformeConfig.class]: Failed to instantiate [com.acme.recibos.ports.ClientesFinder]: Factory method 'clientesFinder' threw exception with message: "
$sentencia = 'CREATE TABLE IF NOT EXISTS PUBLIC.IF[*] (IF VARCHAR(4000),NOT VARCHAR(4000),EXISTS VARCHAR(4000),T_COMIS VARCHAR(4000))'
'[INFO] Running com.acme.viejo.PruebaLocalTest'
'java.lang.IllegalStateException: Failed to load ApplicationContext'
if ($guion -eq 'prop-export') {
  "org.springframework.beans.factory.BeanCreationException: Error creating bean with name 'jobOperator' defined in class path resource [org/springframework/batch/core/configuration/annotation/BatchConfiguration.class]: Factory method 'jobOperator' threw exception with message: Error creating bean with name 'exportJob' defined in class path resource [com/acme/export/config/ExportConfig.class]: Failed to instantiate [org.springframework.batch.core.Job]: Factory method 'exportJob' threw exception with message: app.export.dir is not configured"
  'Caused by: java.lang.IllegalArgumentException: app.export.dir is not configured'
}
elseif ($guion -eq 'placeholder') {
  'Caused by: java.lang.IllegalArgumentException: Could not resolve placeholder ''app.sftp.host'' in value "${app.sftp.host}"'
}
elseif ($guion -eq 'bind') {
  'Caused by: org.springframework.boot.context.properties.bind.BindException: Failed to bind properties under ''app.limites'' to com.acme.Limites'
}
elseif ($guion -eq 'bean-conexion') {
  $bean + 'java.lang.IllegalStateException: Connection refused'
  'Caused by: java.lang.IllegalStateException: Connection refused'
  'host is not set'
}
elseif ($guion -eq 'prop-dos') {
  'Caused by: java.lang.IllegalArgumentException: Could not resolve placeholder ''app.sftp.host'' in value "${app.sftp.host}"'
  'Caused by: java.lang.IllegalStateException: app.sftp.host is not configured'
  'app.sftp.host is not configured'
  'Caused by: java.lang.IllegalStateException: app.export.dir is not configured'
}
elseif ($guion -eq 'prop-cuatro') {
  foreach ($k in @('app.uno.dir', 'app.dos.dir', 'app.tres.dir', 'app.cuatro.dir')) { "Caused by: java.lang.IllegalStateException: $k is not configured" }
}
else {
  'Caused by: org.h2.jdbc.JdbcSQLSyntaxErrorException: Error de Sintaxis en sentencia SQL "' + $sentencia + '"; se esperaba "identifier"; SQL statement:'
  'Caused by: java.lang.IllegalArgumentException: app.export.dir is not configured'
}
'[ERROR] Tests run: 1, Failures: 0, Errors: 1, Skipped: 0, Time elapsed: 1.2 s <<< FAILURE! - in com.acme.viejo.PruebaLocalTest'
'[ERROR] Failed to execute goal org.apache.maven.plugins:maven-surefire-plugin:2.22.2:test (default-test) on project batch-viejo: There are test failures.'
exit 1
