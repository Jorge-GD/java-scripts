# mvn-local.ps1 - Maven de mentira para tests/probar-local.ps1 (prueba-local.ps1).
# test-compile: falla si algun .java de src contiene NO_COMPILA.
# test -Dtest=PruebaLocalTest [-Dprueba.local.job=<job>] [-Dprueba.local.caso=<caso>]: hace lo que haria el
# PruebaLocalTest del contrato (si el test lleva IGNORA_CASO, no hace caso de prueba.local.caso). Por cada carpeta
# src/test/resources/prueba-local/<job>/<caso>/ (de ese job y ese caso, si se piden) deja target/prueba-local/<job>/<caso>/
# con estado.txt y, si el caso trae ficheros/, ficheros/salida/resultado_<aaaammdd de hoy>.txt: una linea por linea
# de entrada, con 'aceptado' o 'rechazado' segun el importe=<n> de la linea frente al 'minimo' de regla.txt (en la
# raiz del repo, o src/main/resources/regla.txt si existe: ahi puede arreglarlo una IA que solo escribe en src/main/). regla.txt
# (clave=valor) tambien lleva 'segundos': la hora que se apunta va desplazada esos segundos.
# Una linea de entrada con AZAR deja ademas un numero al azar; con LATIN, la linea acaba en una enie (mayuscula si
# regla.txt lleva mayus=si) y el fichero se escribe en Latin-1. El fichero lleva tambien la carpeta donde se ejecuta
# (ruta completa). Con datos.sql, tablas/DATOS.csv: sus lineas ordenadas, con la misma regla del minimo.
# Con estatico=si en regla.txt, el batch guarda estado entre ejecuciones de la misma JVM (como un campo static): a partir
# del segundo caso de un mismo 'test', el resultado lleva una linea mas con los casos que arrastra.
# Un PruebaLocalTest con ARNES_SUREFIRE_<X> hace fallar el 'test' como un test de verdad (sale con 1, con las lineas [ERROR] cortadas de
# Maven) y deja en target/surefire-reports/com.acme.viejo.PruebaLocalTest.txt el informe de surefire que dice X:
#   ERROR      <<< ERROR! y una traza con dos 'Caused by:' (la causa de verdad es el ultimo)
#   SIN_CAUSA  <<< ERROR! y ningun 'Caused by:'
#   LARGA      como ERROR, con un ultimo 'Caused by:' de mas de 300 caracteres
#   VIEJO      ningun informe nuevo: solo queda uno de hace un dia, con otra causa (el de una ejecucion anterior)
#   SALIDA     ningun informe (surefire recorta la traza y a veces no deja nada): la traza entera, con dos 'Caused by:', va en la salida de Maven
#   SIN_CAUSA_CON_SALIDA  informe como SIN_CAUSA y, en la salida de Maven, una traza con un 'Caused by:'
# Cada 'test' anade una linea a logs/mvn.log en la raiz del repo (fuera de target, como un log de verdad).
# Cada llamada anade a RESCATE_LLAMADAS/mvn.log (si esta) una linea: carpeta|JAVA_HOME|argumentos.
$raiz = (Get-Location).Path
if ($env:RESCATE_LLAMADAS) {
  [void](New-Item -ItemType Directory -Path $env:RESCATE_LLAMADAS -Force)
  [System.IO.File]::AppendAllText((Join-Path $env:RESCATE_LLAMADAS 'mvn.log'), ($raiz + '|' + $env:JAVA_HOME + '|' + ($args -join ' ') + "`n"))
}
$javas = @(Get-ChildItem -LiteralPath (Join-Path $raiz 'src') -Recurse -File -Filter '*.java')
$malos = @($javas | Where-Object { [System.IO.File]::ReadAllText($_.FullName) -match 'NO_COMPILA' })
if ($malos.Count -gt 0) {
  '[ERROR] COMPILATION ERROR : '
  foreach ($m in $malos) { '[ERROR] ' + $m.Name + ':[1,1] simbolo de mentira no encontrado' }
  exit 1
}
if ($args -notcontains 'test') { exit 0 }
if (@($javas | Where-Object { $_.Name -eq 'PruebaLocalTest.java' }).Count -eq 0) { '[ERROR] No tests matching pattern "PruebaLocalTest" were executed!'; exit 1 }
$sure = [regex]::Match([System.IO.File]::ReadAllText(@($javas | Where-Object { $_.Name -eq 'PruebaLocalTest.java' })[0].FullName), 'ARNES_SUREFIRE_(\w+)').Groups[1].Value
if ($sure) {
  $informe = Join-Path $raiz 'target/surefire-reports/com.acme.viejo.PruebaLocalTest.txt'
  [void](New-Item -ItemType Directory -Path (Split-Path $informe -Parent) -Force)
  $linea = '-------------------------------------------------------------------------------'
  $texto = @($linea, 'Test set: com.acme.viejo.PruebaLocalTest', $linea, 'Tests run: 1, Failures: 0, Errors: 1, Skipped: 0, Time elapsed: 1.2 s <<< FAILURE! - in com.acme.viejo.PruebaLocalTest', 'ejecutaCasosLocales  Time elapsed: 1.1 s  <<< ERROR!')
  $ultimo = "Caused by: java.lang.IllegalArgumentException: Could not resolve placeholder 'acme.entrada.ruta' in value `"`${acme.entrada.ruta}`""
  if ($sure -eq 'LARGA') { $ultimo = 'Caused by: java.lang.IllegalStateException: ' + ('larga' * 100) }
  if ($sure -like 'SIN_CAUSA*') { $texto += @('java.lang.NullPointerException: no hay nada de fondo', "`tat com.acme.viejo.Lector.lee(Lector.java:10)") }
  else { $texto += @('java.lang.IllegalStateException: Failed to load ApplicationContext', "`tat org.springframework.test.context.cache.DefaultCacheAwareContextLoaderDelegate.loadContext(DefaultCacheAwareContextLoaderDelegate.java:132)", "Caused by: org.springframework.beans.factory.UnsatisfiedDependencyException: Error creating bean with name 'reciboReader'", "`tat org.springframework.beans.factory.support.ConstructorResolver.createArgumentArray(ConstructorResolver.java:800)", $ultimo, "`t... 40 more") }
  if ($sure -eq 'VIEJO') {
    $texto = @($linea, 'Test set: com.acme.viejo.PruebaLocalTest', $linea, 'ejecutaCasosLocales  Time elapsed: 1.1 s  <<< ERROR!', 'Caused by: java.io.FileNotFoundException: causa-vieja-de-otra-ejecucion')
  }
  if ($sure -ne 'SALIDA') { [System.IO.File]::WriteAllText($informe, (($texto -join "`n") + "`n")) }
  if ($sure -eq 'VIEJO') { (Get-Item -LiteralPath $informe).LastWriteTime = (Get-Date).AddDays(-1) }
  if ($sure -eq 'SALIDA') { 'java.lang.IllegalStateException: Failed to load ApplicationContext'; "Caused by: org.springframework.beans.factory.UnsatisfiedDependencyException: Error creating bean with name 'reciboReader'" }
  if ($sure -eq 'SIN_CAUSA_CON_SALIDA') { '    Caused by: java.net.ConnectException: Connection refused' }
  '[ERROR] Tests run: 1, Failures: 0, Errors: 1, Skipped: 0, Time elapsed: 1.2 s <<< FAILURE! - in com.acme.viejo.PruebaLocalTest'
  '[ERROR] PruebaLocalTest.ejecutaCasosLocales ? IllegalState Failed to load ApplicationC...'
  '[ERROR] Failed to execute goal org.apache.maven.plugins:maven-surefire-plugin:2.22.2:test (default-test) on project batch-viejo: There are test failures.'
  if ($sure -eq 'SALIDA') { '[ERROR] ' + $ultimo }
  exit 1
}
$soloJob = ''
$soloCaso = ''
foreach ($a in $args) {
  if ("$a" -match '^-Dprueba\.local\.job=(.+)$') { $soloJob = $Matches[1] }
  if ("$a" -match '^-Dprueba\.local\.caso=(.+)$') { $soloCaso = $Matches[1] }
}
if (@($javas | Where-Object { [System.IO.File]::ReadAllText($_.FullName) -match 'IGNORA_CASO' }).Count -gt 0) { $soloCaso = '' }
$arrastra = 0
[void](New-Item -ItemType Directory -Path (Join-Path $raiz 'logs') -Force)
[System.IO.File]::AppendAllText((Join-Path $raiz 'logs/mvn.log'), ('test ' + [DateTime]::UtcNow.Ticks + "`n"))
$regla = @{ minimo = '0'; segundos = '0'; mayus = 'no' }
$fr = Join-Path $raiz 'src/main/resources/regla.txt'
if (-not (Test-Path -LiteralPath $fr)) { $fr = Join-Path $raiz 'regla.txt' }
if (Test-Path -LiteralPath $fr) { foreach ($l in [System.IO.File]::ReadAllLines($fr)) { $k, $v = $l -split '=', 2; if ($k) { $regla[$k.Trim()] = "$v".Trim() } } }
$casos = Join-Path $raiz 'src/test/resources/prueba-local'
if (-not (Test-Path -LiteralPath $casos)) { exit 0 }
$inv = [System.Globalization.CultureInfo]::InvariantCulture
function Veredicto([string]$l) {
  if ($l -match 'importe=([\d\.]+)' -and [double]::Parse($Matches[1], $inv) -lt [double]::Parse($regla.minimo, $inv)) { return 'rechazado' }
  return 'aceptado'
}
foreach ($dj in @(Get-ChildItem -LiteralPath $casos -Directory | Sort-Object Name)) {
  if ($soloJob -and $dj.Name -ne $soloJob) { continue }
  foreach ($dc in @(Get-ChildItem -LiteralPath $dj.FullName -Directory | Sort-Object Name)) {
    if ($soloCaso -and $dc.Name -ne $soloCaso) { continue }
    $out = Join-Path $raiz ('target/prueba-local/' + $dj.Name + '/' + $dc.Name)
    [void](New-Item -ItemType Directory -Path $out -Force)
    $entradas = @()
    $dirF = Join-Path $dc.FullName 'ficheros'
    if (Test-Path -LiteralPath $dirF) { $entradas = @(Get-ChildItem -LiteralPath $dirF -Recurse -File | Sort-Object FullName) }
    if ($entradas.Count -gt 0) {
      $res = @("procesado en $raiz/target/trabajo")
      $latin = $false
      foreach ($f in $entradas) {
        foreach ($l in [System.IO.File]::ReadAllLines($f.FullName)) {
          $linea = "$l -> " + (Veredicto $l)
          if ($l -match 'LATIN') { $latin = $true; if ($regla.mayus -eq 'si') { $linea += ' ' + [char]0xD1 } else { $linea += ' ' + [char]0xF1 } }
          $res += $linea
          if ($l -match 'AZAR') { $res += ('azar ' + [System.Guid]::NewGuid().ToString('N')) }
        }
      }
      if ($regla.estatico -eq 'si' -and $arrastra -gt 0) { $res += "arrastra el estado de $arrastra casos" }
      $arrastra++
      $ahora = (Get-Date).AddSeconds([int]$regla.segundos)
      $res += ('hecho el ' + $ahora.ToString('dd/MM/yyyy HH:mm:ss', $inv) + ' (' + $ahora.ToString('HH:mm:ss', $inv) + ')')
      $sal = Join-Path $out 'ficheros/salida'
      [void](New-Item -ItemType Directory -Path $sal -Force)
      $cod = New-Object System.Text.UTF8Encoding($false)
      if ($latin) { $cod = [System.Text.Encoding]::GetEncoding(28591) }
      [System.IO.File]::WriteAllText((Join-Path $sal ('resultado_' + (Get-Date).ToString('yyyyMMdd', $inv) + '.txt')), (($res -join "`n") + "`n"), $cod)
    }
    $sql = Join-Path $dc.FullName 'datos.sql'
    if (Test-Path -LiteralPath $sql) {
      [void](New-Item -ItemType Directory -Path (Join-Path $out 'tablas') -Force)
      [System.IO.File]::WriteAllText((Join-Path $out 'tablas/DATOS.csv'), ((@([System.IO.File]::ReadAllLines($sql) | ForEach-Object { "$_ -> " + (Veredicto $_) }) | Sort-Object) -join "`n"))
    }
    [System.IO.File]::WriteAllText((Join-Path $out 'estado.txt'), "estado=COMPLETED`nsalida=COMPLETED`n")
  }
}
'[INFO] BUILD SUCCESS'
exit 0
