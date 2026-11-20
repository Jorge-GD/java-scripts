# m50-mvn.ps1 - Maven de mentira para los tests m50 de tests/probar-local.ps1. Hace lo de m48-mvn.ps1 (y con el, lo de m33-mvn.ps1, m25-mvn.ps1 y
# mvn-local.ps1) y, ademas:
# - 'dependency:tree' deja un arbol de dependencias de mentira (el de siempre de Maven: lineas '[INFO] +- g:a:jar:v:scope'), con 7 lineas de
#   org.springframework.kafka y una de io.micrometer, y sale con 0. Con M50_ARBOL=falla sale con 1 y un [ERROR] (el plugin no se resuelve).
# - si RESCATE_M50 trae guiones ('guion' o 'guion:regex', separados por ';'; la regex, sobre 'job/caso'; gana el primero que casa), cada ejecucion de un
#   caso (-Dprueba.local.caso) deja ademas, segun el lado (batch-viejo = original):
#     numero       el migrado acaba FAILED con 'Caused by: java.lang.IllegalStateException: no hay datos para <caso> (id <100 + el numero del caso>)'
#     otra         el migrado acaba FAILED con 'Caused by: java.lang.IllegalStateException: sin correo'
#     tipo         el migrado acaba FAILED con 'Caused by: java.lang.TypeNotPresentException: Type org.springframework.kafka.support.micrometer.KafkaRecordReceiverContext not present'
#     tipo2        el migrado acaba FAILED con 'Caused by: java.lang.ClassNotFoundException: io.micrometer.observation.ObservationRegistry'
#     tabla-igual  tablas/CLIENTES.csv con las mismas columnas y datos en otro orden en cada lado y un valor con ';' dentro (a@x;b@x)
#     tabla-dato   como tabla-igual, con un nombre distinto en el migrado
#     tabla-dos    ';' dentro de un valor en dos columnas distintas (correos en una fila, nombre en otra): ninguna columna da las dos tablas iguales
#     extra        el migrado deja ademas ficheros/extra.txt (sobra en el migrado)
#     falta        el migrado no deja su ficheros/salida/resultado_<hoy>.txt (falta en el migrado)
$raiz = (Get-Location).Path
& (Join-Path $PSScriptRoot 'm48-mvn.ps1') @args
$codigo = $LASTEXITCODE
if ($args -contains 'dependency:tree') {
  if ($env:M50_ARBOL -eq 'falla') {
    '[ERROR] Failed to execute goal org.apache.maven.plugins:maven-dependency-plugin:3.6.0:tree (default-cli) on project batch-nuevo: Could not resolve dependencies'
    exit 1
  }
  '[INFO] --- maven-dependency-plugin:3.6.0:tree (default-cli) @ batch-nuevo ---'
  '[INFO] com.acme:batch-nuevo:jar:1.0.0'
  '[INFO] +- org.springframework.boot:spring-boot-starter-batch:jar:3.1.0:compile'
  '[INFO] |  \- org.springframework.batch:spring-batch-core:jar:5.0.1:compile'
  '[INFO] +- org.springframework.kafka:spring-kafka:jar:2.9.0:compile'
  '[INFO] |  +- org.springframework:spring-messaging:jar:6.0.9:compile'
  '[INFO] |  \- io.micrometer:micrometer-observation:jar:1.9.0:compile'
  foreach ($a in @('test', 'streams', 'extras', 'bom', 'docs', 'otro')) { '[INFO] +- org.springframework.kafka:spring-kafka-' + $a + ':jar:2.9.0:test' }
  '[INFO] \- org.springframework.boot:spring-boot-starter-web:jar:3.1.0:compile'
  exit 0
}
$job = ''; $caso = ''
foreach ($a in $args) {
  if ("$a" -match '^-Dprueba\.local\.job=(.+)$') { $job = $Matches[1] }
  if ("$a" -match '^-Dprueba\.local\.caso=(.+)$') { $caso = $Matches[1] }
}
$base = [System.IO.Path]::Combine($raiz, 'target', 'prueba-local')
if ($env:RESCATE_M50 -and $codigo -eq 0 -and $caso -and (Test-Path -LiteralPath $base)) {
  $original = ($raiz -like '*batch-viejo*')
  $inv = [System.Globalization.CultureInfo]::InvariantCulture
  foreach ($dj in @(Get-ChildItem -LiteralPath $base -Directory | Sort-Object Name)) {
    if ($job -and $dj.Name -ne $job) { continue }
    $dir = [System.IO.Path]::Combine($base, $dj.Name, $caso)
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    $guion = ''
    foreach ($g in ($env:RESCATE_M50 -split ';')) {
      $nombre, $solo = ($g -split ':', 2)
      if (-not $solo) { $solo = '.' }
      if ($nombre -and -not $guion -and ($dj.Name + '/' + $caso) -match $solo) { $guion = $nombre }
    }
    function Escribe-Salida([string]$Rel, [string]$Texto) {
      $f = [System.IO.Path]::Combine([string[]](@($dir) + $Rel.Split('/')))
      [void](New-Item -ItemType Directory -Path (Split-Path $f -Parent) -Force)
      [System.IO.File]::WriteAllText($f, $Texto)
    }
    if (-not $original -and @('numero', 'otra', 'tipo', 'tipo2') -contains $guion) {
      Escribe-Salida 'estado.txt' "estado=FAILED`nsalida=FAILED`n"
      if ($guion -eq 'numero') { 'Caused by: java.lang.IllegalStateException: no hay datos para ' + $caso + ' (id ' + (100 + [int]($caso -replace '\D', '')) + ')' }
      if ($guion -eq 'otra') { 'Caused by: java.lang.IllegalStateException: sin correo' }
      if ($guion -eq 'tipo') { 'Caused by: java.lang.TypeNotPresentException: Type org.springframework.kafka.support.micrometer.KafkaRecordReceiverContext not present' }
      if ($guion -eq 'tipo2') { 'Caused by: java.lang.ClassNotFoundException: io.micrometer.observation.ObservationRegistry' }
    }
    if ($guion -like 'tabla-*') {
      $tabla = "ID;CORREOS;NOMBRE`n1;a@x;b@x;ana`n2;c@x;maria`n"
      if (-not $original) { $tabla = "NOMBRE;ID;CORREOS`nmaria;2;c@x`nana;1;a@x;b@x`n" }
      if ($guion -eq 'tabla-dato' -and -not $original) { $tabla = $tabla.Replace('maria', 'marta') }
      if ($guion -eq 'tabla-dos') {
        $tabla = "ID;CORREOS;NOMBRE`n1;a@x;b@x;ana`n2;c@x;lopez;maria`n"
        if (-not $original) { $tabla = "NOMBRE;ID;CORREOS`nana;1;a@x;b@x`nlopez;maria;2;c@x`n" }
      }
      Escribe-Salida 'tablas/CLIENTES.csv' $tabla
    }
    if ($guion -eq 'extra' -and -not $original) { Escribe-Salida 'ficheros/extra.txt' "de mas`n" }
    if ($guion -eq 'falta' -and -not $original) {
      Get-ChildItem -LiteralPath $dir -Recurse -File -Filter 'resultado_*.txt' | Remove-Item -Force
    }
  }
}
exit $codigo
