<#
probar-propiedades.ps1 - Banco de pruebas de propiedades.ps1 (C6a: comparar las propiedades del original con las del migrado, sin IA).
No necesita Maven ni Java: usa el Maven de mentira tests/falsos/c6-mvn.ps1, que deja el fichero de classpath con jars de prueba (zips
creados aqui, con un META-INF/spring-configuration-metadata.json). Nunca llama al Maven real. Datos inventados (com.acme, batch-recibos).
Vale para Windows PowerShell 5.1 y para PowerShell 7. Solo ASCII a proposito.

  .\tests\probar-propiedades.ps1                       # todas las pruebas
  .\tests\probar-propiedades.ps1 -Solo cache           # las que llevan 'cache' en el nombre
  .\tests\probar-propiedades.ps1 -Dir D:\tmp\x -Conservar

Sale con 0 si todo pasa y con 1 si algo falla.
#>
param(
  [string]$Dir = '',
  [string]$Solo = '',
  [switch]$Conservar
)
$ErrorActionPreference = 'Stop'
$aqui = Split-Path -Parent $MyInvocation.MyCommand.Path
$raiz = Split-Path -Parent $aqui
$falsos = Join-Path $aqui 'falsos'
. (Join-Path $aqui 'comun-banco.ps1')
. (Join-Path $raiz 'comun.ps1')
. (Join-Path $raiz 'tareas.ps1')
. (Join-Path $raiz 'propiedades.ps1')
Add-Type -AssemblyName System.IO.Compression.FileSystem

# ================================ UTILIDADES ================================
$RR = 'src/main/resources/'

function Pom { return "<project><modelVersion>4.0.0</modelVersion><groupId>com.acme</groupId><artifactId>batch-recibos</artifactId><version>1</version></project>`n" }

# Un jar de prueba: un zip con un META-INF/spring-configuration-metadata.json ($null = sin ese fichero) y una clase de mentira.
function Nuevo-Jar([string]$Ruta, $Metadatos) {
  $d = Split-Path $Ruta -Parent
  if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -Force) }
  $zip = [System.IO.Compression.ZipFile]::Open($Ruta, 'Create')
  try {
    $nombres = @{ 'com/acme/Falsa.class' = 'x' }
    if ($null -ne $Metadatos) { $nombres['META-INF/spring-configuration-metadata.json'] = [string]$Metadatos }
    foreach ($n in $nombres.Keys) {
      $e = $zip.CreateEntry($n)
      $w = New-Object System.IO.StreamWriter($e.Open())
      try { $w.Write($nombres[$n]) } finally { $w.Dispose() }
    }
  }
  finally { $zip.Dispose() }
}

# Lo que dicen los jars de prueba: acme.batch.oyente.activo es una propiedad, acme.grupo un grupo, y dos claves viejas de Spring.
$MetaBase = @'
{"groups":[{"name":"acme.grupo"},{"name":"spring.batch"}],
 "properties":[
  {"name":"acme.batch.oyente.activo","type":"java.lang.Boolean"},
  {"name":"spring.batch.initialize-schema","deprecation":{"level":"error","replacement":"spring.batch.jdbc.initialize-schema"}},
  {"name":"spring.batch.table-prefix","deprecation":{"level":"error","replacement":"spring.batch.jdbc.table-prefix"}},
  {"name":"spring.batch.jdbc.initialize-schema","type":"java.lang.String"},
  {"name":"spring.batch.jdbc.table-prefix","type":"java.lang.String"},
  {"name":"spring.viejo.quitado","deprecation":{"level":"error"}},
  {"name":"spring.viejo.aviso","deprecation":{"level":"warning","replacement":"spring.nuevo.aviso"}}
 ]}
'@

# Un escenario: el original, el migrado (con su pom.xml), la referencia y los jars de prueba. Cada hashtable es ruta relativa -> texto.
function Nuevo-Escenario([string]$Nombre, [hashtable]$Legacy = @{}, [hashtable]$Migrado = @{}, [hashtable]$Ref = @{}, $Metadatos = @($MetaBase)) {
  $r = Join-Path $Dir $Nombre
  if (Test-Path -LiteralPath $r) { Remove-Item -LiteralPath $r -Recurse -Force }
  $leg = Join-Path $r 'life-java8'
  $mig = Join-Path $r 'batch-recibos'
  $dirRef = Join-Path $r 'batch-ejemplo'
  foreach ($par in @(@($leg, $Legacy), @($mig, $Migrado), @($dirRef, $Ref))) {
    [void](New-Item -ItemType Directory -Path $par[0] -Force)
    foreach ($k in $par[1].Keys) { Escribe $par[0] $k $par[1][$k] }
  }
  if (-not $Migrado.ContainsKey('pom.xml')) { Escribe $mig 'pom.xml' (Pom) }
  $jars = @()
  $n = 0
  foreach ($m in @($Metadatos)) {
    $n++
    $jar = Join-Path (Join-Path $r 'jars') "dep$n.jar"
    Nuevo-Jar $jar $m
    $jars += $jar
  }
  foreach ($d in @('datos', 'registros')) { [void](New-Item -ItemType Directory -Path (Join-Path $r $d) -Force) }
  return [pscustomobject]@{
    Raiz = $r; Legacy = $leg; Migrado = $mig; Ref = $dirRef; Datos = (Join-Path $r 'datos'); Registros = (Join-Path $r 'registros')
    Llamadas = (Join-Path $r 'mvn-llamadas.txt'); Classpath = ($jars -join [System.IO.Path]::PathSeparator)
    Json = (Join-Path (Join-Path $r 'datos') 'propiedades.json'); Log = (Join-Path (Join-Path $r 'registros') 'propiedades.log')
  }
}

# Corre $Bloque con el Maven de mentira (Cfg.MvnExe), los ajustes de $Ajustes en $Cfg y las variables de entorno de $Entorno; al salir deja todo como estaba.
function Con-Falso([hashtable]$Entorno, [hashtable]$Ajustes, [scriptblock]$Bloque) {
  $todo = @{ MvnExe = (Join-Path $falsos 'c6-mvn.ps1'); SegundosLatido = 0 }
  foreach ($k in $Ajustes.Keys) { $todo[$k] = $Ajustes[$k] }
  $cfgAntes = @{}
  foreach ($k in $todo.Keys) { $cfgAntes[$k] = $Cfg[$k]; $Cfg[$k] = $todo[$k] }
  $envAntes = @{}
  foreach ($k in $Entorno.Keys) { $envAntes[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $Entorno[$k]) }
  try { return (& $Bloque) }
  finally {
    foreach ($k in $Entorno.Keys) { [Environment]::SetEnvironmentVariable($k, $envAntes[$k]) }
    foreach ($k in $cfgAntes.Keys) { $Cfg[$k] = $cfgAntes[$k] }
  }
}

function Lee-Json([string]$Ruta) {
  if (-not (Test-Path -LiteralPath $Ruta)) { return $null }
  return ([System.IO.File]::ReadAllText($Ruta) | ConvertFrom-Json)
}

function Lee-Texto([string]$Ruta) {
  if (-not (Test-Path -LiteralPath $Ruta)) { return '' }
  return [System.IO.File]::ReadAllText($Ruta)
}

# Invoke-Propiedades sobre el escenario con los falsos. Devuelve el JSON que dejo, el texto del JSON y del log, lo que dijo por consola
# (Texto) y los avisos (las lineas amarillas).
function Mide($E, [hashtable]$Entorno = @{}, [hashtable]$Ajustes = @{}) {
  $Entorno['C6_LLAMADAS'] = $E.Llamadas
  if (-not $Entorno.ContainsKey('C6_CLASSPATH')) { $Entorno['C6_CLASSPATH'] = $E.Classpath }
  $todo = @(Con-Falso $Entorno $Ajustes { Invoke-Propiedades $E.Legacy $E.Migrado $E.Ref $E.Datos $E.Registros } 6>&1)
  $info = @($todo | Where-Object { $_ -is [System.Management.Automation.InformationRecord] })
  return [pscustomobject]@{
    Json = (Lee-Json $E.Json)
    JsonTexto = (Lee-Texto $E.Json)
    LogTexto = (Lee-Texto $E.Log)
    Texto = (@($info | ForEach-Object { "$_" }) -join "`n")
    Avisos = @($info | Where-Object { "$($_.MessageData.ForegroundColor)" -ceq 'Yellow' } | ForEach-Object { "$_" })
  }
}

function Llamadas-De([string]$Fichero) {
  if (-not (Test-Path -LiteralPath $Fichero)) { return , @() }
  return , @([System.IO.File]::ReadAllLines($Fichero) | Where-Object { $_ })
}

function Del-Legacy($J, [string]$Clave, [string]$Perfil = 'default') { return @($J.legacy | Where-Object { $_.clave -ceq $Clave -and $_.perfil -ceq $Perfil })[0] }

function Del-Migrado($J, [string]$Clave) { return @($J.migrado | Where-Object { $_.clave -ceq $Clave })[0] }

function Linea-Propiedades([string]$Texto) { return @($Texto -split "`n" | Where-Object { $_ -like 'Propiedades: *' })[0] }

# Las claves de un texto, como 'clave|valor|linea|perfil' (los saltos del valor, como \n).
function Resumen-Claves($Claves) {
  return @($Claves | ForEach-Object { "$($_.clave)|$(("$($_.valor)") -replace "`n", '\n')|$($_.linea)|$($_.perfil)" })
}

# ================================ PRUEBAS ================================
$Pruebas = [ordered]@{}

$YmlA = @'
# configuracion del batch
spring:
  application:
    name: batch-recibos   # el nombre
app:
  ruta: "/datos/in"
  url: 'jdbc:h2:mem:x'
  nota: "con # dentro"   # esto si es comentario
  plano: valor # fuera
  items:
    - uno
    - dos
  destinos:
    - name: a
      host: h1
    - name: b
      host: h2
  texto: |
    primera
    segunda
  lista: [a, b]
  mapa: {x: 1}
  "comillas": cierto
  "[a.b]": punto
---
spring:
  config:
    activate:
      on-profile: pro
app:
  ruta: /datos/pro
'@

$Pruebas['1 a) lector yml: mapas, listas, listas de mapas, comentarios, comillas, bloque |, en linea, claves con comillas y un segundo documento con su perfil'] = {
  $c = @(Read-PropiedadesFichero 'src/main/resources/application.yml' $YmlA 'default')
  $esperado = @(
    'spring.application.name|batch-recibos|4|default',
    'app.ruta|/datos/in|6|default',
    'app.url|jdbc:h2:mem:x|7|default',
    'app.nota|con # dentro|8|default',
    'app.plano|valor|9|default',
    'app.items[0]|uno|11|default',
    'app.items[1]|dos|12|default',
    'app.destinos[0].name|a|14|default',
    'app.destinos[0].host|h1|15|default',
    'app.destinos[1].name|b|16|default',
    'app.destinos[1].host|h2|17|default',
    'app.texto|primera\nsegunda|18|default',
    'app.lista|[a, b]|21|default',
    'app.mapa|{x: 1}|22|default',
    'app.comillas|cierto|23|default',
    'app.a.b|punto|24|default',
    'spring.config.activate.on-profile|pro|29|pro',
    'app.ruta|/datos/pro|31|pro'
  )
  $real = Resumen-Claves $c
  Igual 'cuantas claves' $esperado.Count $real.Count
  for ($i = 0; $i -lt [Math]::Min($esperado.Count, $real.Count); $i++) { Igual "clave $($i + 1): clave|valor|linea|perfil" $esperado[$i] $real[$i] }
  Igual 'cada clave dice su fichero' 'src/main/resources/application.yml' $c[0].fichero
}

$YmlB = @'
spring:
  profiles: dev
app:
  vacia:
  lista:
  - uno
  - dos
  anidada:
    -   x: 1
        y: 2
    - fin
  largo: >
    una
    dos

  despues: si
  url: jdbc:oracle:thin:@host:1521/x
  # comentario solo
  plano: it's # comentario
  doble: "a \"b\" c"
  simple: 'don''t'
  flujo: [a,
    b]
'@

$Pruebas['2 a) lector yml: claves vacias, lista pegada a su clave, bloque >, : dentro del valor, comillas escapadas, flujo en dos lineas y spring.profiles'] = {
  $c = @(Read-PropiedadesFichero 'src/main/resources/application-dev.yml' $YmlB 'dev')
  $esperado = @(
    'spring.profiles|dev|2|dev',
    'app.vacia||4|dev',
    'app.lista[0]|uno|6|dev',
    'app.lista[1]|dos|7|dev',
    'app.anidada[0].x|1|9|dev',
    'app.anidada[0].y|2|10|dev',
    'app.anidada[1]|fin|11|dev',
    'app.largo|una dos|12|dev',
    'app.despues|si|16|dev',
    'app.url|jdbc:oracle:thin:@host:1521/x|17|dev',
    'app.plano|it''s|19|dev',
    'app.doble|a "b" c|20|dev',
    'app.simple|don''t|21|dev',
    'app.flujo|[a, b]|22|dev'
  )
  $real = @(Resumen-Claves $c)
  Igual 'cuantas claves' $esperado.Count $real.Count
  for ($i = 0; $i -lt [Math]::Min($esperado.Count, $real.Count); $i++) { Igual "clave $($i + 1): clave|valor|linea|perfil" $esperado[$i] $real[$i] }
  # el perfil de un documento lo dice spring.profiles o spring.config.activate.on-profile; un fichero application-dev toma dev
  $t = "app:`n  a: 1`n---`nspring:`n  profiles: pro`napp:`n  a: 2`n---`napp:`n  a: 3`n"
  $d = @(Read-PropiedadesFichero 'src/main/resources/application.yml' $t 'default')
  Igual 'tres documentos: 1 y 3 en default, el del medio en pro' 'default pro pro default' (@($d | ForEach-Object { $_.perfil }) -join ' ')
  Igual 'y sus lineas' '2 5 7 10' (@($d | ForEach-Object { $_.linea }) -join ' ')
}

$PropsB = @'
# comentario con almohadilla
! comentario con exclamacion
app.ruta=/datos
app.lote : 100
app.host   servidor1
app.largo=uno,\
    dos,\
    tres
app.url=jdbc\:h2\:mem
app\=x=1
app.vacia=
  app.sangrada = si
app.eco=a\\
app.otra=b
'@

$Pruebas['3 b) lector properties: =, : y espacio, linea que sigue con \, \: y \=, comentarios # y !, vacia y sangrada'] = {
  $c = @(Read-PropiedadesFichero 'src/main/resources/application.properties' $PropsB 'default')
  $esperado = @(
    'app.ruta|/datos|3|default',
    'app.lote|100|4|default',
    'app.host|servidor1|5|default',
    'app.largo|uno,dos,tres|6|default',
    'app.url|jdbc:h2:mem|9|default',
    'app=x|1|10|default',
    'app.vacia||11|default',
    'app.sangrada|si|12|default',
    'app.eco|a\|13|default',
    'app.otra|b|14|default'
  )
  $real = Resumen-Claves $c
  Igual 'cuantas claves' $esperado.Count $real.Count
  for ($i = 0; $i -lt [Math]::Min($esperado.Count, $real.Count); $i++) { Igual "clave $($i + 1): clave|valor|linea|perfil" $esperado[$i] $real[$i] }
  $d = @(Read-PropiedadesFichero 'src/main/resources/application-pro.properties' "a=1`n" 'pro')
  Igual 'el perfil es el que se pide' 'pro' $d[0].perfil
  $u = @(Read-PropiedadesFichero 'src/main/resources/x.properties' "a=\u00e9`n" 'default')
  Igual 'un \uXXXX se decodifica' ([string][char]0xe9) $u[0].valor
}

$LegC = "app.ruta=/datos`napp.lote=100`napp.host=x`napp.maxItems=5`napp.solo.legacy=1`n"
$YmlC = "app:`n  ruta: /datos`n  lote: 50`n  host: `${APP_HOST}`n  max-items: 5`n"
$JavaApp = "package com.acme.batch;`n`n@ConfigurationProperties(prefix = `"app`")`npublic class Ajustes {`n}`n"

$Pruebas['4 c) estados: igual, distinto, por-variable (con su variable), igual por maxItems/max-items y falta; la linea de la consola y el orden del JSON'] = {
  $E = Nuevo-Escenario 'c' @{ ($RR + 'application.properties') = $LegC } @{ ($RR + 'application.yml') = $YmlC; 'src/main/java/com/acme/batch/Ajustes.java' = $JavaApp }
  $m = Mide $E
  $j = $m.Json
  Comprueba 'deja datos\propiedades.json' ($null -ne $j)
  if ($null -eq $j) { return }
  Igual 'los campos del JSON, en su orden' 'clave ficheros renombres legacy migrado resumen' ($j.PSObject.Properties.Name -join ' ')
  Igual '5 claves del original' 5 @($j.legacy).Count
  Igual 'los campos de cada clave, en su orden' 'clave perfil fichero linea estado enMigrado valorLegacy valorMigrado variable renombradaA valorIgual secreto texto' (@($j.legacy)[0].PSObject.Properties.Name -join ' ')
  $a = Del-Legacy $j 'app.ruta'
  Igual 'app.ruta: igual' 'igual' $a.estado
  Igual 'app.ruta: fichero' ($RR + 'application.properties') $a.fichero
  Igual 'app.ruta: linea' 1 $a.linea
  Igual 'app.ruta: valor del original' '/datos' $a.valorLegacy
  Igual 'app.ruta: valor del migrado' '/datos' $a.valorMigrado
  Igual 'app.ruta: enMigrado.clave' 'app.ruta' $a.enMigrado.clave
  Igual 'app.ruta: enMigrado.fichero' ($RR + 'application.yml') $a.enMigrado.fichero
  Igual 'app.ruta: enMigrado.linea' 2 $a.enMigrado.linea
  Igual 'app.ruta: secreto false' $false $a.secreto
  $a = Del-Legacy $j 'app.lote'
  Igual 'app.lote: distinto' 'distinto' $a.estado
  Igual 'app.lote: valores' '100|50' "$($a.valorLegacy)|$($a.valorMigrado)"
  $a = Del-Legacy $j 'app.host'
  Igual 'app.host: por-variable' 'por-variable' $a.estado
  Igual 'app.host: variable' 'APP_HOST' $a.variable
  $a = Del-Legacy $j 'app.maxItems'
  Igual 'app.maxItems frente a app.max-items: igual' 'igual' $a.estado
  Igual 'app.maxItems: enMigrado.clave es la del migrado' 'app.max-items' $a.enMigrado.clave
  $a = Del-Legacy $j 'app.solo.legacy'
  Igual 'app.solo.legacy: falta' 'falta' $a.estado
  Comprueba 'app.solo.legacy: enMigrado null' ($null -eq $a.enMigrado)
  Igual 'resumen: total, igual, por-variable, distinto, renombrada, renombrada-falta, ya-no-existe, falta' '5 2 1 1 0 0 0 1' (@($j.resumen.total, $j.resumen.igual, $j.resumen.'por-variable', $j.resumen.distinto, $j.resumen.renombrada, $j.resumen.'renombrada-falta', $j.resumen.'ya-no-existe', $j.resumen.falta) -join ' ')
  Igual 'ninguna del migrado sin leer (el @ConfigurationProperties lee app.*)' 0 @($j.migrado).Count
  $linea = Linea-Propiedades $m.Texto
  Write-Host "        consola: $linea"
  Igual 'la linea de la consola' "Propiedades: 5 del original: 2 iguales, 1 por variable, 0 renombradas, 1 faltan, 1 distintas, 0 ya no existen; 0 del migrado sin leer. Detalle en $($E.Json)." $linea
  Igual 'una sola linea Propiedades:' 1 @($m.Texto -split "`n" | Where-Object { $_ -like 'Propiedades: *' }).Count
  Comprueba 'la consola dice los ficheros leidos de cada lado' ($m.Texto -match 'application\.properties' -and $m.Texto -match 'application\.yml')
  Comprueba 'el log dice los ficheros leidos' ($m.LogTexto -match 'application\.properties' -and $m.LogTexto -match 'application\.yml')
}

$Pruebas['5 d) renombres: la vieja en el original y la nueva en el migrado da renombrada, con renombradaA y valorIgual true, false o null'] = {
  $leg = @{ ($RR + 'application.properties') = "spring.batch.initialize-schema=always`nspring.batch.table-prefix=BATCH_`n" }
  $E = Nuevo-Escenario 'd1' $leg @{ ($RR + 'application.yml') = "spring:`n  batch:`n    jdbc:`n      initialize-schema: always`n      table-prefix: OTRO_`n" }
  $j = (Mide $E).Json
  Igual 'renombres: ok' 'ok' $j.renombres.estado
  $a = Del-Legacy $j 'spring.batch.initialize-schema'
  Igual 'initialize-schema: renombrada' 'renombrada' $a.estado
  Igual 'renombradaA' 'spring.batch.jdbc.initialize-schema' $a.renombradaA
  Igual 'valorIgual true' 'True' "$($a.valorIgual)"
  Igual 'enMigrado.clave es la nueva' 'spring.batch.jdbc.initialize-schema' $a.enMigrado.clave
  $a = Del-Legacy $j 'spring.batch.table-prefix'
  Igual 'table-prefix: renombrada' 'renombrada' $a.estado
  Igual 'valorIgual false con otro valor' 'False' "$($a.valorIgual)"
  Igual 'la nueva del migrado no es una clave nueva ni sin leer: no sale en migrado[]' 0 @($j.migrado).Count
  $E = Nuevo-Escenario 'd1b' $leg @{ ($RR + 'application.yml') = "spring:`n  batch:`n    jdbc:`n      initialize-schema: `${ESQUEMA:always}`n      table-prefix: BATCH_`n" }
  $j = (Mide $E).Json
  $a = Del-Legacy $j 'spring.batch.initialize-schema'
  Igual 'con variable en el migrado: renombrada' 'renombrada' $a.estado
  Comprueba 'valorIgual null (va por variable)' ($null -eq $a.valorIgual)
  Igual 'y guarda la variable' 'ESQUEMA' $a.variable
  Igual 'resumen: 2 renombradas' 2 $j.resumen.renombrada
}

$Pruebas['6 d) renombres: renombrada-falta con el nombre nuevo en el texto, ya-no-existe, y un level warning sin replacement no es ya-no-existe'] = {
  $leg = @{ ($RR + 'application.properties') = "spring.batch.initialize-schema=always`nspring.viejo.quitado=1`nspring.viejo.aviso=1`nspring.otra.cosa=1`n" }
  $E = Nuevo-Escenario 'd2' $leg @{ ($RR + 'application.yml') = "app:`n  x: 1`n" }
  $m = Mide $E
  $j = $m.Json
  $a = Del-Legacy $j 'spring.batch.initialize-schema'
  Igual 'renombrada-falta' 'renombrada-falta' $a.estado
  Igual 'el texto' 'En Spring Boot 3 se llama spring.batch.jdbc.initialize-schema y no esta en el migrado' $a.texto
  Igual 'renombradaA' 'spring.batch.jdbc.initialize-schema' $a.renombradaA
  Comprueba 'enMigrado null' ($null -eq $a.enMigrado)
  $a = Del-Legacy $j 'spring.viejo.quitado'
  Igual 'ya-no-existe' 'ya-no-existe' $a.estado
  Igual 'el texto de ya-no-existe' 'Spring Boot 3 ya no la tiene: quitala o busca que la sustituye' $a.texto
  $a = Del-Legacy $j 'spring.viejo.aviso'
  Igual 'un warning con replacement que no esta: renombrada-falta' 'renombrada-falta' $a.estado
  $a = Del-Legacy $j 'spring.otra.cosa'
  Igual 'una que los metadatos no conocen: falta' 'falta' $a.estado
  Igual 'resumen: ya-no-existe, renombrada-falta, falta y total' '1 2 1 4' (@($j.resumen.'ya-no-existe', $j.resumen.'renombrada-falta', $j.resumen.falta, $j.resumen.total) -join ' ')
  Igual 'la linea de la consola cuenta renombradas-falta como faltan (3) y ya no existen (1)' 'Propiedades: 4 del original: 0 iguales, 0 por variable, 0 renombradas, 3 faltan, 0 distintas, 1 ya no existen; 1 del migrado sin leer.' ((Linea-Propiedades $m.Texto) -replace ' Detalle en .*$', '')
}

$Pruebas['7 d) nombreViejo: la clave vieja escrita en el migrado sale en migrado[] con nombreViejo y el texto con el nombre nuevo'] = {
  $leg = @{ ($RR + 'application.properties') = "spring.batch.initialize-schema=always`n" }
  $E = Nuevo-Escenario 'd3' $leg @{ ($RR + 'application.yml') = "spring:`n  batch:`n    initialize-schema: always`n    jdbc:`n      table-prefix: X_`n" }
  $j = (Mide $E).Json
  $a = Del-Legacy $j 'spring.batch.initialize-schema'
  Igual 'la del original esta tal cual en el migrado: igual' 'igual' $a.estado
  $v = Del-Migrado $j 'spring.batch.initialize-schema'
  Comprueba 'sale en migrado[]' ($null -ne $v)
  if ($null -eq $v) { return }
  Igual 'nombreViejo' 'True' "$($v.nombreViejo)"
  Igual 'renombradaA' 'spring.batch.jdbc.initialize-schema' $v.renombradaA
  Igual 'el texto' 'Con este nombre Spring Boot 3 no la lee: se llama spring.batch.jdbc.initialize-schema' $v.texto
  Igual 'fichero y linea' ($RR + 'application.yml') $v.fichero
  Igual 'la linea' 3 $v.linea
  Igual 'no es nueva (esta en el original)' 'False' "$($v.nueva)"
  Igual 'resumen.nombreViejo' 1 $j.resumen.nombreViejo
  $w = Del-Migrado $j 'spring.batch.jdbc.table-prefix'
  Comprueba 'una nueva de Spring (jdbc.table-prefix) que el original no tiene sale como nueva' ($null -ne $w -and $w.nueva -eq $true)
}

$Pruebas['8 e) Maven falla: renombres no se pudo medir con su motivo y las ultimas lineas, los demas estados como en c, sin excepcion y sin guardar el fallo'] = {
  $E = Nuevo-Escenario 'e' @{ ($RR + 'application.properties') = $LegC + "spring.batch.initialize-schema=always`n" } @{ ($RR + 'application.yml') = $YmlC; 'src/main/java/com/acme/batch/Ajustes.java' = $JavaApp }
  $m = Mide $E @{ C6_RC = '1'; C6_ERROR = 'no se resuelve com.acme:falsa:1.0' }
  $j = $m.Json
  Comprueba 'el JSON se escribe igual' ($null -ne $j)
  if ($null -eq $j) { return }
  Igual 'renombres.estado' 'no se pudo medir' $j.renombres.estado
  Comprueba 'el motivo lleva el error de Maven' ("$($j.renombres.motivo)" -like '*no se resuelve com.acme:falsa:1.0*') "$($j.renombres.motivo)"
  Comprueba 'el motivo dice el codigo' ("$($j.renombres.motivo)" -like '*codigo 1*') "$($j.renombres.motivo)"
  Igual 'jars' 0 $j.renombres.jars
  Igual 'claves' 0 $j.renombres.claves
  Igual 'app.ruta sigue igual' 'igual' (Del-Legacy $j 'app.ruta').estado
  Igual 'app.lote sigue distinto' 'distinto' (Del-Legacy $j 'app.lote').estado
  Igual 'app.host sigue por-variable' 'por-variable' (Del-Legacy $j 'app.host').estado
  Igual 'la renombrada, sin metadatos, es falta' 'falta' (Del-Legacy $j 'spring.batch.initialize-schema').estado
  Comprueba 'un Aviso con el motivo' (@($m.Avisos | Where-Object { $_ -like '*no se resuelve com.acme:falsa:1.0*' }).Count -ge 1) ($m.Avisos -join ' / ')
  Comprueba 'sigue saliendo la linea Propiedades:' ($null -ne (Linea-Propiedades $m.Texto))
  Comprueba 'el log lleva la salida de Maven' ($m.LogTexto -like '*no se resuelve com.acme:falsa:1.0*')
  Igual 'Maven se llamo una vez' 1 (Llamadas-De $E.Llamadas).Count
  Comprueba 'no deja la cache de metadatos' (-not (Test-Path -LiteralPath (Join-Path $E.Datos 'propiedades-metadatos.json')))
  # un fallo no se guarda: la siguiente vez Maven se lanza otra vez y, si ya va, mide
  $m = Mide $E
  Igual 'la segunda vez Maven se lanza otra vez' 2 (Llamadas-De $E.Llamadas).Count
  Igual 'y ahora renombres ok' 'ok' $m.Json.renombres.estado
  Igual 'y la renombrada ya sale como renombrada-falta (no como falta)' 'renombrada-falta' (Del-Legacy $m.Json 'spring.batch.initialize-schema').estado
  # sin classpath (Maven sale con 0 y no deja el fichero)
  $E2 = Nuevo-Escenario 'e2' @{ ($RR + 'application.properties') = "app.a=1`n" } @{ ($RR + 'application.yml') = "app:`n  a: 1`n" }
  $m = Mide $E2 @{ C6_CLASSPATH = '' }
  Igual 'sin fichero de classpath: no se pudo medir' 'no se pudo medir' $m.Json.renombres.estado
  Comprueba 'el motivo dice classpath' ("$($m.Json.renombres.motivo)" -like '*classpath*') "$($m.Json.renombres.motivo)"
  # ningun jar con metadatos
  $E3 = Nuevo-Escenario 'e3' @{ ($RR + 'application.properties') = "app.a=1`n" } @{ ($RR + 'application.yml') = "app:`n  a: 1`n" } @{} @($null, $null)
  $m = Mide $E3
  Igual 'sin metadatos en ningun jar: no se pudo medir' 'no se pudo medir' $m.Json.renombres.estado
  Comprueba 'el motivo dice metadatos' ("$($m.Json.renombres.motivo)" -like '*metadatos*') "$($m.Json.renombres.motivo)"
  # sin pom.xml, sin original y sin carpeta de datos: tampoco para
  $E4 = Nuevo-Escenario 'e4'
  Remove-Item -LiteralPath (Join-Path $E4.Migrado 'pom.xml') -Force
  Remove-Item -LiteralPath $E4.Legacy -Recurse -Force
  Remove-Item -LiteralPath $E4.Datos -Recurse -Force
  $m = Mide $E4
  Comprueba 'sin pom, sin original y sin datos: escribe el JSON igual' ($null -ne $m.Json)
  Igual 'no se pudo medir' 'no se pudo medir' $m.Json.renombres.estado
  Comprueba 'el motivo dice pom.xml' ("$($m.Json.renombres.motivo)" -like '*pom.xml*') "$($m.Json.renombres.motivo)"
  Igual 'ninguna clave' 0 @($m.Json.legacy).Count
}

$JavaF = @'
package com.acme.batch;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.core.env.Environment;

@ConfigurationProperties(prefix = "app.foo")
class FooProps { }

@ConditionalOnProperty(prefix = "app.cond", name = "activo", havingValue = "true")
class Condicionada { }

class Lector {
    @Value("${app.otra}") private String otra;
    @Value("${app.con.defecto:5}") private int conDefecto;
    String prop(Environment env) { return env.getProperty("app.prop"); }
}
'@

$YmlF = @'
app:
  foo:
    bar: 1
  otra: 2
  prop: 3
  con:
    defecto: 4
  cond:
    activo: true
  huerfana: 9
acme:
  batch:
    oyente:
      activo: true
  grupo:
    algo: 1
ref:
  clave: 1
spring:
  algo: 1
'@

$Pruebas['9 f) sin-leer: ConfigurationProperties, Value, getProperty, ConditionalOnProperty, metadatos, grupo, referencia y spring.* no; app.huerfana si'] = {
  $E = Nuevo-Escenario 'f' @{} @{ ($RR + 'application.yml') = $YmlF; 'src/main/java/com/acme/batch/Lector.java' = $JavaF } @{ ($RR + 'application.yml') = "ref:`n  clave: x`n" }
  $j = (Mide $E).Json
  Comprueba 'deja el JSON' ($null -ne $j)
  if ($null -eq $j) { return }
  $sin = @($j.migrado | Where-Object { $_.sinLeer -eq $true } | ForEach-Object { $_.clave })
  Igual 'la unica sin leer' 'app.huerfana' ($sin -join ' ')
  foreach ($k in @('app.foo.bar', 'app.otra', 'app.prop', 'app.con.defecto', 'app.cond.activo', 'acme.batch.oyente.activo', 'acme.grupo.algo', 'ref.clave', 'spring.algo')) {
    $v = Del-Migrado $j $k
    Comprueba "$k : no esta sin leer" ($null -ne $v -and $v.sinLeer -eq $false) "$($v | ConvertTo-Json -Compress)"
  }
  $v = Del-Migrado $j 'app.huerfana'
  Igual 'app.huerfana: es nueva y sin leer' 'True True' "$($v.nueva) $($v.sinLeer)"
  Igual 'resumen.sinLeer' 1 $j.resumen.sinLeer
  Comprueba 'el texto de sin leer lo dice' ("$($v.texto)" -like '*ni el codigo ni las librerias*') "$($v.texto)"
  # sin leer es independiente de nueva: una clave que esta en el original tambien puede estar sin leer
  $E = Nuevo-Escenario 'f2' @{ ($RR + 'application.properties') = "app.huerfana=9`n" } @{ ($RR + 'application.yml') = "app:`n  huerfana: 9`n" }
  $j = (Mide $E).Json
  $v = Del-Migrado $j 'app.huerfana'
  Igual 'esta en el original: no es nueva pero si sin leer' 'False True' "$($v.nueva) $($v.sinLeer)"
  Igual 'y en el original es igual' 'igual' (Del-Legacy $j 'app.huerfana').estado
}

$Pruebas['10 g) secretos: ningun valor suyo en el JSON, el log ni la consola; secreto true y los estados igual que siempre'] = {
  $leg = "db.password=Secreto123`ndb.pass=Secreto789`n"
  $mig = "db:`n  password: OtroValor456`n  pass: `${DB_PASSWORD:Defecto321}`njobs:`n  token: abc999`n"
  $E = Nuevo-Escenario 'g' @{ ($RR + 'application.properties') = $leg } @{ ($RR + 'application.yml') = $mig }
  $m = Mide $E
  $j = $m.Json
  Comprueba 'deja el JSON' ($null -ne $j)
  if ($null -eq $j) { return }
  foreach ($s in @('Secreto123', 'OtroValor456', 'Secreto789', 'Defecto321', 'abc999')) {
    Comprueba "$s : no esta en el JSON" ($m.JsonTexto -notmatch $s)
    Comprueba "$s : no esta en el log" ($m.LogTexto -notmatch $s)
    Comprueba "$s : no esta en la consola" ($m.Texto -notmatch $s)
  }
  $a = Del-Legacy $j 'db.password'
  Igual 'db.password: secreto' 'True' "$($a.secreto)"
  Igual 'db.password: distinto' 'distinto' $a.estado
  Comprueba 'db.password: sin valores' ($null -eq $a.valorLegacy -and $null -eq $a.valorMigrado)
  $a = Del-Legacy $j 'db.pass'
  Igual 'db.pass: secreto por el nombre de la variable' 'True' "$($a.secreto)"
  Igual 'db.pass: por-variable' 'por-variable' $a.estado
  Igual 'db.pass: la variable se dice' 'DB_PASSWORD' $a.variable
  Comprueba 'db.pass: sin valores' ($null -eq $a.valorLegacy -and $null -eq $a.valorMigrado)
  $v = Del-Migrado $j 'jobs.token'
  Igual 'jobs.token (solo del migrado): secreto y sin valor' 'True True' "$($v.secreto) $($null -eq $v.valor)"
}

$Pruebas['11 h) cache: la misma medida no lanza Maven ni toca el JSON y solo dice la linea; con otro pom.xml, Maven otra vez; con otro fichero, mide sin Maven'] = {
  $E = Nuevo-Escenario 'h' @{ ($RR + 'application.properties') = $LegC } @{ ($RR + 'application.yml') = $YmlC; 'src/main/java/com/acme/batch/Ajustes.java' = $JavaApp }
  $m1 = Mide $E
  Igual 'la primera vez, una llamada a Maven' 1 (Llamadas-De $E.Llamadas).Count
  $c = Join-Path $E.Registros 'propiedades-classpath.txt'
  Comprueba 'el classpath queda en registros' (Test-Path -LiteralPath $c)
  Comprueba 'la cache de metadatos queda en datos' (Test-Path -LiteralPath (Join-Path $E.Datos 'propiedades-metadatos.json'))
  $linea1 = Linea-Propiedades $m1.Texto
  $m2 = Mide $E
  Igual 'la segunda vez, ninguna llamada mas' 1 (Llamadas-De $E.Llamadas).Count
  Igual 'el JSON es el mismo, byte a byte' $m1.JsonTexto $m2.JsonTexto
  Igual 'el log es el mismo' $m1.LogTexto $m2.LogTexto
  Igual 'la consola dice la misma linea' $linea1 (Linea-Propiedades $m2.Texto)
  Igual 'y solo esa linea (no repite los ficheros leidos)' 1 @($m2.Texto -split "`n" | Where-Object { $_ }).Count
  # el pom cambia: Maven otra vez
  Escribe $E.Migrado 'pom.xml' ((Pom) + "<!-- otra version -->`n")
  $m3 = Mide $E
  Igual 'con otro pom.xml, Maven se lanza otra vez' 2 (Llamadas-De $E.Llamadas).Count
  # un fichero leido cambia: se vuelve a medir, sin Maven
  Escribe $E.Migrado ($RR + 'application.yml') ($YmlC + "  nueva: 1`n")
  $m4 = Mide $E
  Igual 'con otro yml, Maven no se lanza' 2 (Llamadas-De $E.Llamadas).Count
  Comprueba 'pero el JSON cambia' ($m4.JsonTexto -ne $m3.JsonTexto)
  Comprueba 'y lleva la clave nueva' ($null -ne (Del-Migrado $m4.Json 'app.nueva'))
  # el codigo que lee tambien cuenta (sin leer depende de el)
  Escribe $E.Migrado 'src/main/java/com/acme/batch/Ajustes.java' "package com.acme.batch;`n`npublic class Ajustes { }`n"
  $m5 = Mide $E
  Comprueba 'quitar el @ConfigurationProperties vuelve a medir: ahora hay claves sin leer' ($m5.Json.resumen.sinLeer -gt 0) "$($m5.Json.resumen.sinLeer)"
  # sin el JSON, mide otra vez pero con la cache de metadatos: sin Maven
  Remove-Item -LiteralPath $E.Json -Force
  $m6 = Mide $E
  Comprueba 'sin propiedades.json, lo vuelve a dejar' ($null -ne $m6.Json)
  Igual 'y sin Maven (la cache de metadatos vale)' 2 (Llamadas-De $E.Llamadas).Count
}

$Pruebas['12 i) exclusiones: messages, ValidationMessages, META-INF y log4j/logback no se leen; solo application* del migrado; la consola dice los ficheros'] = {
  $leg = @{
    ($RR + 'application.properties') = "app.a=1`n"
    ($RR + 'config/batch.yml') = "app:`n  b: 2`n"
    ($RR + 'messages.properties') = "msg.hola=Hola`n"
    ($RR + 'messages_es.properties') = "msg.hola=Hola`n"
    ($RR + 'i18n/messages.properties') = "msg.hola=Hola`n"
    ($RR + 'ValidationMessages_es.properties') = "val.x=1`n"
    ($RR + 'META-INF/x.properties') = "meta.x=1`n"
    ($RR + 'META-INF/spring/y.yml') = "meta:`n  y: 1`n"
    ($RR + 'log4j.properties') = "log4j.rootLogger=INFO`n"
    ($RR + 'log4j2.yml') = "Configuration:`n  status: warn`n"
    ($RR + 'logback-spring.yml') = "logging:`n  level: INFO`n"
    ($RR + 'datos.xml') = '<datos/>'
  }
  $mig = @{
    ($RR + 'application.yml') = "app:`n  a: 1`n"
    ($RR + 'application-pro.yml') = "app:`n  a: 2`n"
    ($RR + 'config/application.properties') = "app.c=3`n"
    ($RR + 'bootstrap.yml') = "b:`n  c: 1`n"
    ($RR + 'otro.properties') = "o.p=1`n"
    ($RR + 'application.xml') = '<x/>'
  }
  $E = Nuevo-Escenario 'i' $leg $mig @{ ($RR + 'application.yml') = "r:`n  x: 1`n"; ($RR + 'config/application-dev.yaml') = "r:`n  y: 1`n"; ($RR + 'otro.yml') = "z:`n  z: 1`n" }
  $m = Mide $E
  $j = $m.Json
  Igual 'original: solo application.properties y config/batch.yml' "${RR}application.properties ${RR}config/batch.yml" (@($j.ficheros.legacy) -join ' ')
  Igual 'migrado: los application* de resources y de resources/config' "${RR}application-pro.yml ${RR}application.yml ${RR}config/application.properties" (@($j.ficheros.migrado) -join ' ')
  Igual 'referencia: lo mismo' "${RR}application.yml ${RR}config/application-dev.yaml" (@($j.ficheros.referencia) -join ' ')
  Igual 'las claves del original: a y b' 'app.a app.b' (@($j.legacy | ForEach-Object { $_.clave }) -join ' ')
  Comprueba 'la consola dice los ficheros del original' ($m.Texto -like "*${RR}application.properties*" -and $m.Texto -like "*${RR}config/batch.yml*")
  Comprueba 'y no nombra los excluidos' ($m.Texto -notmatch 'messages' -and $m.Texto -notmatch 'META-INF' -and $m.Texto -notmatch 'log4j' -and $m.Texto -notmatch 'logback')
  Comprueba 'el log dice los ficheros del migrado' ($m.LogTexto -like "*${RR}application-pro.yml*")
  Igual 'la lista de exclusiones de Cfg' 'META-INF/* log4j* logback* messages*.properties ValidationMessages*.properties' (@($Cfg.PropiedadesExcluir) -join ' ')
}

$Pruebas['13 perfiles: application-pro se compara con application-pro y no con application; una clave solo de otro perfil falta (o va por variable)'] = {
  $leg = @{
    ($RR + 'application.properties') = "app.lote=100`napp.y=5`n"
    ($RR + 'application-pro.properties') = "app.lote=50`napp.solo.pro=1`napp.x=1`napp.z=1`n"
  }
  $mig = @{
    ($RR + 'application.yml') = "app:`n  lote: 100`n  x: 1`n  z: `${Z}`n"
    ($RR + 'application-pro.yml') = "app:`n  lote: 50`n  y: 5`n"
  }
  $E = Nuevo-Escenario 'p' $leg $mig
  $j = (Mide $E).Json
  Igual 'app.lote default: igual' 'igual' (Del-Legacy $j 'app.lote' 'default').estado
  Igual 'app.lote pro: igual (con el 50 de pro, no el 100)' 'igual' (Del-Legacy $j 'app.lote' 'pro').estado
  Igual 'app.lote pro: enMigrado es el de application-pro.yml' ($RR + 'application-pro.yml') (Del-Legacy $j 'app.lote' 'pro').enMigrado.fichero
  Igual 'app.solo.pro: falta' 'falta' (Del-Legacy $j 'app.solo.pro' 'pro').estado
  $a = Del-Legacy $j 'app.x' 'pro'
  Igual 'app.x de pro esta en el migrado en default con el mismo valor: igual (lo de default vale con pro)' 'igual' $a.estado
  Igual 'y enMigrado es el de application.yml' ($RR + 'application.yml') $a.enMigrado.fichero
  $a = Del-Legacy $j 'app.y' 'default'
  Igual 'app.y esta solo en pro: con default, falta' 'falta' $a.estado
  Comprueba 'y el texto dice el otro perfil' ("$($a.texto)" -like '*otro perfil*' -and "$($a.texto)" -like '*pro*') "$($a.texto)"
  $a = Del-Legacy $j 'app.z' 'pro'
  Igual 'app.z va por variable en el migrado (aunque sea de otro perfil)' 'por-variable' $a.estado
  Igual 'y dice cual' 'Z' $a.variable
  Igual 'perfil del original con application-pro.properties' 'pro' (Del-Legacy $j 'app.solo.pro' 'pro').perfil
}

$Pruebas['16 perfiles: lo de application (default) vale tambien con pro, salvo que application-pro lo cambie; el reves no'] = {
  $leg = @{
    ($RR + 'application.properties') = "app.d1=1`napp.d2=1`napp.d3=1`napp.d4=1`napp.solodef=1`n"
    ($RR + 'application-pro.properties') = "app.a=1`napp.b=1`napp.c=5`napp.e=5`napp.v=1`nspring.batch.initialize-schema=always`nspring.batch.table-prefix=ACME_`n"
  }
  $mig = @{
    ($RR + 'application.yml') = "app:`n  a: 1`n  b: 9`n  c: 9`n  e: 5`n  v: `${V}`nspring:`n  batch:`n    jdbc:`n      initialize-schema: always`n      table-prefix: OTRO_`n"
    ($RR + 'application-pro.yml') = "app:`n  c: 5`n  e: 7`n  d2: 1`n  d3: 7`n  d4: `${D4}`n  solodef: 1`n"
  }
  $E = Nuevo-Escenario 'q' $leg $mig
  $j = (Mide $E).Json
  # pro en el original y default en el migrado
  $a = Del-Legacy $j 'app.a' 'pro'
  Igual 'pro en el original, default en el migrado, mismo valor: igual' 'igual' $a.estado
  Igual 'enMigrado apunta a application.yml' ($RR + 'application.yml') $a.enMigrado.fichero
  Igual 'y a su linea' 2 $a.enMigrado.linea
  Igual 'valorMigrado es el del migrado' '1' $a.valorMigrado
  $a = Del-Legacy $j 'app.b' 'pro'
  Igual 'lo mismo con otro valor: distinto' 'distinto' $a.estado
  Igual 'y enMigrado sigue siendo el de default' ($RR + 'application.yml') $a.enMigrado.fichero
  Igual 'y valorMigrado es el 9 de default' '9' $a.valorMigrado
  # el migrado la tiene en pro y en default: gana la de pro
  $a = Del-Legacy $j 'app.c' 'pro'
  Igual 'en pro y en default con valores distintos, y el de pro es el del original: igual' 'igual' $a.estado
  Igual 'gana la de pro (enMigrado es application-pro.yml)' ($RR + 'application-pro.yml') $a.enMigrado.fichero
  $a = Del-Legacy $j 'app.e' 'pro'
  Igual 'si la de pro es otra y la de default coincide con el original: distinto (gana la de pro)' 'distinto' $a.estado
  Igual 'y valorMigrado es el 7 de pro' '7' $a.valorMigrado
  # por variable
  $a = Del-Legacy $j 'app.v' 'pro'
  Igual 'default en el migrado va por variable: por-variable' 'por-variable' $a.estado
  Igual 'y dice cual' 'V' $a.variable
  # renombradas
  $a = Del-Legacy $j 'spring.batch.initialize-schema' 'pro'
  Igual 'renombrada con el nombre nuevo en default y el mismo valor: renombrada' 'renombrada' $a.estado
  Igual 'y el destino es el de application.yml' ($RR + 'application.yml') $a.enMigrado.fichero
  Igual 'con el mismo valor' $true $a.valorIgual
  $a = Del-Legacy $j 'spring.batch.table-prefix' 'pro'
  Igual 'renombrada con el nombre nuevo en default y otro valor: renombrada' 'renombrada' $a.estado
  Igual 'y valorIgual es false' $false $a.valorIgual
  # el reves: lo de default no se cumple por lo que tenga pro
  $a = Del-Legacy $j 'app.d1' 'default'
  Igual 'default en el original y la clave ni esta en el migrado: falta' 'falta' $a.estado
  $a = Del-Legacy $j 'app.d2' 'default'
  Igual 'default en el original y el migrado solo la tiene en pro con un valor literal: falta' 'falta' $a.estado
  Comprueba 'y el texto dice solo con otro perfil (pro)' ("$($a.texto)" -like '*solo con otro perfil (pro)*') "$($a.texto)"
  $a = Del-Legacy $j 'app.d3' 'default'
  Igual 'lo mismo con otro valor en pro: falta' 'falta' $a.estado
  $a = Del-Legacy $j 'app.d4' 'default'
  Igual 'el migrado solo la tiene en pro y va por variable: por-variable (como antes)' 'por-variable' $a.estado
  $a = Del-Legacy $j 'app.solodef' 'default'
  Igual 'default en el original, pro en el migrado con el mismo literal: sigue falta' 'falta' $a.estado
}

$Pruebas['14 nunca para: sin pom, sin original y con un fichero ilegible, el JSON se escribe y no hay excepcion'] = {
  $E = Nuevo-Escenario 'n' @{ ($RR + 'application.properties') = "app.a=1`n" } @{ ($RR + 'application.yml') = "app:`n  a: [`n" }
  $m = Mide $E
  Comprueba 'un yml mal formado no para' ($null -ne $m.Json)
  Comprueba 'y deja su linea' ($null -ne (Linea-Propiedades $m.Texto))
  $E2 = Nuevo-Escenario 'n2' @{ ($RR + 'application.properties') = "app.a=1`n" } @{ ($RR + 'application.yml') = "app:`n  a: 1`n" }
  $m = Mide $E2 @{} @{ MvnExe = (Join-Path $E2.Raiz 'no-existe.ps1') }
  Comprueba 'con un Maven que no existe, tampoco' ($null -ne $m.Json -and $m.Json.renombres.estado -ceq 'no se pudo medir') "$($m.Json.renombres.estado)"
  Comprueba 'y el motivo lo dice' ("$($m.Json.renombres.motivo)" -like '*Maven*') "$($m.Json.renombres.motivo)"
}

$Pruebas['15 k) propiedades.ps1: solo funciones, cabecera, ASCII, nada de PowerShell 7 y ninguna funcion repetida en otro script'] = {
  $ruta = Join-Path $raiz 'propiedades.ps1'
  Comprueba 'existe junto a migracion.ps1' (Test-Path -LiteralPath $ruta)
  if (-not (Test-Path -LiteralPath $ruta)) { return }
  $codigo = [System.IO.File]::ReadAllText($ruta)
  Comprueba 'empieza con su cabecera de ayuda' ($codigo.TrimStart().StartsWith('<#'))
  Comprueba 'nada de PowerShell 7 (??, ?. ni ?[)' ($codigo -notmatch '\?\?|[\w\)\]]\?\.\w|\w\?\[')
  Comprueba 'sin -AsHashtable ni ConvertFrom-Json -Depth' ($codigo -notmatch 'AsHashtable|ConvertFrom-Json[^|\r\n]*-Depth')
  Comprueba 'sin Join-Path de tres rutas' ($codigo -notmatch 'Join-Path\s+[^\s|)]+\s+[^\s|)]+\s+[^\s|)]+\s*\)')
  foreach ($f in @('propiedades.ps1', 'tests/probar-propiedades.ps1', 'tests/falsos/c6-mvn.ps1')) {
    $t = [System.IO.File]::ReadAllText((Get-Ruta $raiz $f))
    Comprueba "$f : solo ASCII" ($t -notmatch '[^\x09\x0A\x0D\x20-\x7E]')
  }
  $ast = [System.Management.Automation.Language.Parser]::ParseInput($codigo, [ref]$null, [ref]$null)
  $sueltas = @($ast.EndBlock.Statements | Where-Object { $_ -isnot [System.Management.Automation.Language.FunctionDefinitionAst] -and "$_" -notmatch '^\$Cfg \+= ' })
  Igual 'nada fuera de las funciones (salvo el $Cfg +=)' 0 $sueltas.Count
  $suyas = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Name })
  $deMas = @(Get-ChildItem -LiteralPath $raiz -File -Filter '*.ps1' | Where-Object { $_.Name -cne 'propiedades.ps1' } | ForEach-Object {
      [regex]::Matches([System.IO.File]::ReadAllText($_.FullName), '(?m)^function ([\w-]+)') | ForEach-Object { $_.Groups[1].Value }
    })
  $repetidas = @($suyas | Where-Object { $deMas -contains $_ })
  Comprueba 'define funciones' ($suyas.Count -gt 0)
  Comprueba 'ninguna esta repetida en otro .ps1 de la raiz' ($repetidas.Count -eq 0) ($repetidas -join ', ')
  $mig = [System.IO.File]::ReadAllText((Join-Path $raiz 'migracion.ps1'))
  Comprueba 'migracion.ps1 la carga junto a los demas' ($mig -match "(?m)^\. \(Join-Path \`$PSScriptRoot 'propiedades\.ps1'\)")
  Comprueba 'y la nombra en su linea Necesita' ($mig -match '(?m)^Necesita [^\r\n]*propiedades\.ps1')
  Comprueba 'y la llama justo despues del diagnostico' ($mig -match '(?s)Invoke-FaseDiagnostico\s*\r?\n\s*if \(-not \$script:Parada\) \{ Invoke-Propiedades \$LegacyRoot \$RepoRoot \$PlantillaRoot \$Datos \$Registros \}')
}

Invoke-Banco $Pruebas 'tests/probar-propiedades.ps1'
