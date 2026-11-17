# mvn.ps1 - Maven de mentira para tests/probar.ps1 y tests/probar-preflight.ps1.
# "Compila" si ningun .java contiene NO_COMPILA.
# Con el argumento 'test', los "tests" fallan si algun test contiene TEST_FALLA.
# Para el preflight: '--version' dice una version; el paso de JaCoCo deja
# target/site/jacoco/jacoco.csv (y falla con '[ERROR] <texto>' si existe RESCATE_MVN_ERROR);
# el de OpenRewrite mueve com.ejemplo.service.Saludo a com.ejemplo.application.usecase.
# Con RESCATE_MVN_ESPERA=<n>, cada llamada (menos '--version') tarda n segundos mas (para probar el latido).
if ($args -contains '--version') { 'Apache Maven 3.9.8 (de mentira)'; exit 0 }
if ($env:RESCATE_MVN_ESPERA) { Start-Sleep -Seconds ([int]$env:RESCATE_MVN_ESPERA) }
$raiz = (Get-Location).Path
$conJacoco = (@($args | Where-Object { "$_" -match 'jacoco-maven-plugin' }).Count -gt 0)
$conRewrite = (@($args | Where-Object { "$_" -match 'rewrite-maven-plugin' }).Count -gt 0)
if ($conJacoco -and $env:RESCATE_MVN_ERROR) { '[ERROR] ' + $env:RESCATE_MVN_ERROR; exit 1 }
$javas = @(Get-ChildItem -LiteralPath (Join-Path $raiz 'src') -Recurse -File -Filter '*.java')
$malos = @($javas | Where-Object { [System.IO.File]::ReadAllText($_.FullName) -match 'NO_COMPILA' })
if ($malos.Count -gt 0) {
  '[ERROR] COMPILATION ERROR : '
  foreach ($m in $malos) { '[ERROR] ' + $m.FullName + ':[1,1] simbolo de mentira no encontrado' }
  exit 1
}
if ($args -contains 'test') {
  $rep = Join-Path (Join-Path $raiz 'target') 'surefire-reports'
  [void](New-Item -ItemType Directory -Path $rep -Force)
  $fallan = @($javas | Where-Object { ($_.FullName -match '[\\/]src[\\/]test[\\/]') -and ([System.IO.File]::ReadAllText($_.FullName) -match 'TEST_FALLA') })
  foreach ($t in $fallan) {
    [System.IO.File]::WriteAllText((Join-Path $rep ($t.BaseName + '.txt')), 'Tests run: 1, Failures: 1, Errors: 0, Skipped: 0')
  }
  if ($fallan.Count -gt 0) {
    '[ERROR] Tests run: 1, Failures: 1, Errors: 0, Skipped: 0'
    exit 1
  }
}
# Para el examen del preflight (E1): con 'test', los tests tambien fallan si algun fichero de src/main contiene TEST_FALLA.
if ($args -contains 'test') {
  $rotos = @($javas | Where-Object { ($_.FullName -match '[\\/]src[\\/]main[\\/]') -and ([System.IO.File]::ReadAllText($_.FullName) -match 'TEST_FALLA') })
  if ($rotos.Count -gt 0) {
    '[ERROR] Tests run: 1, Failures: 1, Errors: 0, Skipped: 0'
    exit 1
  }
}
if ($conJacoco) {
  $csv = Join-Path $raiz 'target/site/jacoco'
  [void](New-Item -ItemType Directory -Path $csv -Force)
  [System.IO.File]::WriteAllText((Join-Path $csv 'jacoco.csv'), (@('GROUP,PACKAGE,CLASS,LINE_MISSED,LINE_COVERED', ',com.ejemplo.service,Saludo,0,4') -join "`n"))
}
if ($conRewrite) {
  $vieja = Join-Path $raiz 'src/main/java/com/ejemplo/service/Saludo.java'
  $nueva = Join-Path $raiz 'src/main/java/com/ejemplo/application/usecase/Saludo.java'
  if (Test-Path -LiteralPath $vieja) {
    [void](New-Item -ItemType Directory -Path (Split-Path $nueva -Parent) -Force)
    [System.IO.File]::WriteAllText($nueva, [System.IO.File]::ReadAllText($vieja).Replace('com.ejemplo.service', 'com.ejemplo.application.usecase'))
    Remove-Item -LiteralPath $vieja -Force
    foreach ($j in $javas) {
      if (Test-Path -LiteralPath $j.FullName) {
        $t = [System.IO.File]::ReadAllText($j.FullName)
        if ($t.Contains('com.ejemplo.service.Saludo')) { [System.IO.File]::WriteAllText($j.FullName, $t.Replace('com.ejemplo.service.Saludo', 'com.ejemplo.application.usecase.Saludo')) }
      }
    }
  }
}
exit 0
