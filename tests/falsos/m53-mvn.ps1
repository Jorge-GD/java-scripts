# m53-mvn.ps1 - Maven de mentira para los tests m53 de tests/probar-local.ps1. Hace lo de m50-mvn.ps1 (y con el, lo de m48, m33, m25 y mvn-local.ps1) y, ademas:
# - si RESCATE_M53 trae guiones ('guion' o 'guion:regex', separados por ';'; la regex, sobre 'job/caso'; gana el primero que casa), cada ejecucion de un caso
#   (-Dprueba.local.caso; no la del caso vacio ni la de otro del arnes) del migrado (batch-nuevo) acaba asi:
#     contexto    estado=EXCEPCION (salida=UnsatisfiedDependencyException) y Maven, con 0, escribe un aviso WARN de Spring con una TypeNotPresentException y, despues,
#                 el WARN 'Exception encountered during context initialization - cancelling refresh attempt: <UnsatisfiedDependencyException ... found 2: ...>'
#     sin-tests   ni estado.txt ni nada del caso, y Maven sale con 1 y '[ERROR] Failed to execute goal ...surefire...: No tests matching pattern "PruebaLocalTest"
#                 were executed! (...) -> [Help 1]' (sin ninguna excepcion)
#     sin-salida  ni estado.txt ni nada del caso, y Maven sale con 0 y '[INFO] BUILD SUCCESS' (el test no encuentra la carpeta del caso y acaba bien sin hacer nada)
#     sin-salida-rc1    ni estado.txt ni nada del caso, y Maven sale con 1 y '[INFO] BUILD FAILURE' (sin ninguna causa en el log)
#     sin-salida-aviso  ni estado.txt ni nada del caso, y Maven sale con 0 y con el WARN 'cancelling refresh attempt: ...' del guion contexto
#     excepcion-muda    estado=EXCEPCION (sin salida=) y Maven con 0, sin ninguna linea en el log: hay estado.txt y no hay causa
# - si RESCATE_M53_SUITE trae un modo, en la suite de tests unitarios (un 'test' sin -Dtest) cada <failure .../> de los TEST-*.xml que deja m25-mvn.ps1 pasa a ser:
#     mensaje     <error message="Failed to load ApplicationContext ... expected single matching bean but found 2: a,b" ...> con una segunda linea en el mensaje
#     cuerpo      <error message=""> con el texto en el cuerpo (una linea en blanco, la primera linea con texto y dos mas)
#     largo       un message de 400 letras
#     vacio       <error message=""/>, sin texto
$raiz = (Get-Location).Path
& (Join-Path $PSScriptRoot 'm50-mvn.ps1') @args
$codigo = $LASTEXITCODE
$job = ''; $caso = ''
foreach ($a in $args) {
  if ("$a" -match '^-Dprueba\.local\.job=(.+)$') { $job = $Matches[1] }
  if ("$a" -match '^-Dprueba\.local\.caso=(.+)$') { $caso = $Matches[1] }
}
$base = [System.IO.Path]::Combine($raiz, 'target', 'prueba-local')
# Los dos avisos de Spring del guion contexto: uno con una TypeNotPresentException (no da causa) y, despues, el que da la causa (cancelling refresh attempt).
$avisoAntes = '2026-11-20T22:45:20.512+01:00  WARN 11116 --- [app] [main] o.s.c.a.MergedAnnotation : Failed to introspect meta-annotation @ConditionalOnClass on class com.acme.kafka.Receptor: java.lang.TypeNotPresentException: Type com.acme.kafka.FaltaUno not present'
$avisoContexto = "2026-11-20T22:45:23.103+01:00  WARN 11116 --- [app] [main] s.c.a.AnnotationConfigApplicationContext : Exception encountered during context initialization - cancelling refresh attempt: org.springframework.beans.factory.UnsatisfiedDependencyException: Error creating bean with name 'pasoPostProcessor': No qualifying bean of type 'org.springframework.batch.core.listener.StepExecutionListener' available: expected single matching bean but found 2: oyentePaso,oyenteEmpresa"
if ($env:RESCATE_M53 -and $codigo -eq 0 -and $caso -and $caso -ne 'vacio' -and $caso -ne 'otro' -and ($raiz -notlike '*batch-viejo*') -and (Test-Path -LiteralPath $base)) {
  foreach ($dj in @(Get-ChildItem -LiteralPath $base -Directory | Sort-Object Name)) {
    if ($job -and $dj.Name -ne $job) { continue }
    $dir = [System.IO.Path]::Combine($base, $dj.Name, $caso)
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    $guion = ''
    foreach ($g in ($env:RESCATE_M53 -split ';')) {
      $nombre, $solo = ($g -split ':', 2)
      if (-not $solo) { $solo = '.' }
      if ($nombre -and -not $guion -and ($dj.Name + '/' + $caso) -match $solo) { $guion = $nombre }
    }
    if ($guion -eq 'contexto') {
      [System.IO.File]::WriteAllText([System.IO.Path]::Combine($dir, 'estado.txt'), "estado=EXCEPCION`nsalida=org.springframework.beans.factory.UnsatisfiedDependencyException`n")
      $avisoAntes
      $avisoContexto
    }
    if ($guion -eq 'excepcion-muda') {
      [System.IO.File]::WriteAllText([System.IO.Path]::Combine($dir, 'estado.txt'), "estado=EXCEPCION`n")
    }
    if ($guion -in @('sin-tests', 'sin-salida', 'sin-salida-rc1', 'sin-salida-aviso')) {
      Remove-Item -LiteralPath $dir -Recurse -Force
      if ($guion -eq 'sin-tests') {
        '[INFO] BUILD FAILURE'
        '[ERROR] Failed to execute goal org.apache.maven.plugins:maven-surefire-plugin:3.5.6:test (default-test) on project batch-nuevo: No tests matching pattern "PruebaLocalTest" were executed! (Set -Dsurefire.failIfNoSpecifiedTests=false to ignore this error.) -> [Help 1]'
        '[ERROR] '
        '[ERROR] To see the full stack trace of the errors, re-run Maven with the -e switch.'
        exit 1
      }
      if ($guion -eq 'sin-salida-rc1') {
        '[INFO] BUILD FAILURE'
        exit 1
      }
      if ($guion -eq 'sin-salida-aviso') { $avisoContexto }
      '[INFO] BUILD SUCCESS'
    }
  }
}
if ($env:RESCATE_M53_SUITE -and $codigo -eq 0 -and $args -contains 'test' -and @($args | Where-Object { "$_" -like '-Dtest=*' }).Count -eq 0) {
  $informes = Join-Path $raiz 'target/surefire-reports'
  if (Test-Path -LiteralPath $informes) {
    $largo = 'L' * 400
    $cuerpo = switch ($env:RESCATE_M53_SUITE) {
      'mensaje' { '<error message="Failed to load ApplicationContext for [x]: expected single matching bean but found 2: a,b&#10;segunda linea del mensaje" type="java.lang.IllegalStateException"/>' }
      'cuerpo' { "<error message=`"`" type=`"java.lang.IllegalStateException`">`n`n  java.lang.IllegalStateException: Failed to load ApplicationContext for [x]: expected single matching bean but found 2: a,b`n`tat org.springframework.test.context.cache.DefaultCacheAwareContextLoaderDelegate.loadContext(X.java:1)`n`tat org.junit.X.run(X.java:2)`n</error>" }
      'largo' { '<error message="' + $largo + '" type="java.lang.IllegalStateException"/>' }
      default { '<error message=""/>' }
    }
    foreach ($f in @(Get-ChildItem -LiteralPath $informes -File -Filter 'TEST-*.xml')) {
      $x = [System.IO.File]::ReadAllText($f.FullName)
      [System.IO.File]::WriteAllText($f.FullName, [regex]::Replace($x, '<failure message="[^"]*"/>', $cuerpo), (New-Object System.Text.UTF8Encoding($false)))
    }
  }
}
exit $codigo
