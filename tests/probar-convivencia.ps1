<#
probar-convivencia.ps1 - Banco de pruebas de convivencia.ps1 (C2: en pre, el viejo y el nuevo a la vez o uno detras de otro, sin IA).
No necesita Maven, Java ni Copilot: lee codigo de mentira (com.acme, jobs cargaJob, resumenJob y avisoJob) con regex y escribe
datos\convivencia.json. Las paginas se generan con Write-Informes en este mismo proceso. Vale para Windows PowerShell 5.1 y para PowerShell 7.
Solo ASCII a proposito: los textos con tilde se escriben con \uXXXX y se pasan por [regex]::Unescape.

  .\tests\probar-convivencia.ps1                       # todas las pruebas
  .\tests\probar-convivencia.ps1 -Solo cerrojo         # las que llevan 'cerrojo' en el nombre
  .\tests\probar-convivencia.ps1 -Dir D:\tmp\x -Conservar

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
. (Join-Path $aqui 'comun-banco.ps1')
. (Join-Path $raiz 'comun.ps1')
. (Join-Path $raiz 'tareas.ps1')
. (Join-Path $raiz 'lanzadores.ps1')
. (Join-Path $raiz 'practicas.ps1')
# antes de escribir convivencia.ps1 el banco corre en rojo: cada prueba que la necesita falla porque Invoke-Convivencia no existe
if (Test-Path -LiteralPath (Join-Path $raiz 'convivencia.ps1')) { . (Join-Path $raiz 'convivencia.ps1') }
. (Join-Path $raiz 'informe.ps1')

# ================================ UTILIDADES ================================
function Es([string]$Ascii) { return [regex]::Unescape($Ascii) }

$UnoDetras = Es 'Uno detr\u00e1s de otro'
$NoSeDeQueJob = Es 'no s\u00e9 de qu\u00e9 job'
$NoSeLoQueToca = Es 'no s\u00e9 lo que toca'
$LeidoPorIA = Es 'Le\u00eddo por la IA, con prueba'
$QueReponer = Es 'Qu\u00e9 reponer'

function Java([string]$Paquete, [string]$Clase, [string]$Cuerpo) {
  return "package com.acme.$Paquete;`n`npublic class $Clase {`n$Cuerpo}`n"
}

# La clase de lectura de siempre: no escribe nada.
$MigradoLee = @{ 'src/main/java/com/acme/nuevo/Lector.java' = (Java 'nuevo' 'Lector' "  private JdbcCursorItemReader<Recibo> lector;`n  private FlatFileItemReader<Recibo> fichero;`n") }

function Escribe-Json([string]$Ruta, $Objeto) {
  $d = Split-Path $Ruta -Parent
  if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -Force) }
  [System.IO.File]::WriteAllText($Ruta, (ConvertTo-Json -InputObject $Objeto -Depth 8))
}

function Lee-Json([string]$Ruta) {
  if (-not (Test-Path -LiteralPath $Ruta)) { return $null }
  return ([System.IO.File]::ReadAllText($Ruta) | ConvertFrom-Json)
}

function Lee-Texto([string]$Ruta) {
  if (-not (Test-Path -LiteralPath $Ruta)) { return '' }
  return [System.IO.File]::ReadAllText($Ruta)
}

# El numero de la primera linea de $Texto que lleva $Trozo.
function Linea-De([string]$Texto, [string]$Trozo) {
  $i = 0
  foreach ($l in ($Texto -split "`n")) { $i++; if ($l.Contains($Trozo)) { return $i } }
  return 0
}

# Un escenario: el original (con su src/main/java), el migrado y la carpeta datos con jobs\. $Legacy y $Migrado: ruta relativa -> texto.
function Nuevo-Escenario([string]$Nombre, [hashtable]$Legacy = @{}, [hashtable]$Migrado = $null) {
  if ($null -eq $Migrado) { $Migrado = $MigradoLee }
  $r = Join-Path $Dir $Nombre
  if (Test-Path -LiteralPath $r) { Remove-Item -LiteralPath $r -Recurse -Force }
  $leg = Join-Path $r 'life-java8'
  $mig = Join-Path $r 'batch-recibos'
  foreach ($par in @(@($leg, $Legacy), @($mig, $Migrado))) {
    [void](New-Item -ItemType Directory -Path $par[0] -Force)
    foreach ($k in $par[1].Keys) { Escribe $par[0] $k $par[1][$k] }
  }
  $datos = Join-Path $r 'datos'
  [void](New-Item -ItemType Directory -Path (Join-Path $datos 'jobs') -Force)
  return [pscustomobject]@{ Raiz = $r; Legacy = $leg; Migrado = $mig; Datos = $datos; Json = (Join-Path $datos 'convivencia.json') }
}

# datos\mapa.json: $Jobs es nombre de job -> sus ficheros del original (rutas relativas).
function Escribe-Mapa($E, $Jobs) {
  $js = @()
  foreach ($j in $Jobs.Keys) {
    $cs = @($Jobs[$j] | ForEach-Object { [ordered]@{ clase = ((Split-Path $_ -Leaf) -replace '\.java$', ''); fichero = $_; ficha = 'clase-11111111'; por = 'paso'; tieneFicha = $true } })
    $js += [ordered]@{ job = $j; definidoEn = 'src/main/java/com/acme/Config.java'; linea = 1; probado = $true; pasos = @(); clases = $cs; dudas = @() }
  }
  Escribe-Json (Join-Path $E.Datos 'mapa.json') ([ordered]@{ jobs = $js; sinJob = @() })
}

# datos\jobs\<job>.json: la ficha del job, con produce y conexiones del $Extra.
function Escribe-Ficha($E, [string]$Job, [hashtable]$Extra = @{}, [string]$Redaccion = 'hecha') {
  $f = [ordered]@{
    job = $Job; titulo = "Titulo de $Job"; paraQue = 'Hace algo.'; pasos = @(); necesita = @(); produce = @(); conexiones = @(); reglas = @(); siFalla = @()
    sinFicha = @(); fuera = @(); dudas = @(); redaccion = $Redaccion
  }
  foreach ($k in $Extra.Keys) { $f[$k] = $Extra[$k] }
  Escribe-Json (Join-Path (Join-Path $E.Datos 'jobs') ((Get-NombreJob $Job) + '.json')) $f
}

# Un dato de una ficha de job.
function Dato([string]$Tipo, [string]$Texto, [string]$Fichero, [int]$Linea, [string]$Cita) {
  return [ordered]@{ tipo = $Tipo; texto = $Texto; ref = 'clase-11111111#0'; clase = 'Clase'; fichero = $Fichero; linea = $Linea; cita = $Cita; probado = $true }
}

# datos\lanzadores.json con el inventario de verdad (Get-InventarioLanzador) de cada script. $Lista: @{ nombre; lineas; jobs }.
function Escribe-Lanzadores($E, $Lista) {
  $zs = @()
  $n = 0
  foreach ($l in $Lista) {
    $n++
    $rel = 'lanzadores/' + $l.nombre
    Escribe $E.Legacy $rel ((@($l.lineas) -join "`n") + "`n")
    $zs += [ordered]@{
      id = "sh-0000000$n"; rel = $rel; ruta = (Get-Ruta $E.Legacy $rel); interprete = 'bash'; lineas = @($l.lineas).Count; jobs = @($l.jobs)
      enlace = [ordered]@{ como = 'argumento'; fichero = $rel; linea = 1 }; inventario = @(Get-InventarioLanzador @($l.lineas))
    }
  }
  Escribe-Json (Join-Path $E.Datos 'lanzadores.json') ([ordered]@{ lanzadores = $zs })
}

# Invoke-Convivencia sobre el escenario. Devuelve el JSON que dejo, lo que salio por la consola (Salida: todo lo que no es el flujo de Info) y las lineas Info.
function Mide($E) {
  $todo = @(Invoke-Convivencia $E.Legacy $E.Migrado $E.Datos 6>&1)
  $info = @($todo | Where-Object { $_ -is [System.Management.Automation.InformationRecord] })
  return [pscustomobject]@{
    Json = (Lee-Json $E.Json)
    Todo = $todo
    Info = $info
    Colores = @($info | Where-Object { @('Yellow', 'Red') -contains "$($_.MessageData.ForegroundColor)" })
  }
}

function De($J, [string]$Job) { return @($J.jobs | Where-Object { $_.job -ceq $Job })[0] }

function Motivos-De($Job, [string]$Cat, [string]$Lado = '') {
  return @(@($Job.motivos) | Where-Object { $_.categoria -ceq $Cat -and ((-not $Lado) -or $_.lado -ceq $Lado) })
}

function Categorias-De($Job) { return ((@(@($Job.motivos) | ForEach-Object { $_.categoria } | Sort-Object -Unique)) -join ',') }

$Pruebas = [ordered]@{}

# ================================ (a) a (j): LOS MOTIVOS ================================
$Pruebas['01 a) una clase de cargaJob con JdbcBatchItemWriter: en-serie, motivo tabla del original con su linea'] = {
  $texto = Java 'carga' 'CargaWriter' "  private JdbcBatchItemWriter<Recibo> escritor;`n"
  $e = Nuevo-Escenario 'a' @{ 'src/main/java/com/acme/carga/CargaWriter.java' = $texto }
  Escribe-Mapa $e ([ordered]@{ cargaJob = @('src/main/java/com/acme/carga/CargaWriter.java') })
  Escribe-Ficha $e 'cargaJob'
  $r = Mide $e
  $j = De $r.Json 'cargaJob'
  Comprueba 'hay JSON con cargaJob' ($null -ne $j) 'sin convivencia.json'
  if ($null -eq $j) { return }
  Igual 'veredicto' 'en-serie' $j.veredicto
  $m = @(Motivos-De $j 'tabla' 'original')
  Igual 'un motivo tabla del original' 1 $m.Count
  if ($m.Count -ne 1) { return }
  Igual 'fichero' 'src/main/java/com/acme/carga/CargaWriter.java' $m[0].fichero
  Igual 'linea de la clase, no la del import' (Linea-De $texto 'JdbcBatchItemWriter<Recibo>') $m[0].linea
  Comprueba 'la cita es la linea' ($m[0].cita -ceq 'private JdbcBatchItemWriter<Recibo> escritor;') $m[0].cita
  Comprueba 'el texto dice que es del original' ($m[0].texto -match 'en el original') $m[0].texto
  Comprueba 'no es de la IA' ($m[0].ia -eq $false)
  Igual 'ningun otro motivo' 1 @($j.motivos).Count
}

$Pruebas['02 b) resumenJob solo lee, sin produce ni conexiones, y el migrado no escribe: a-la-vez; un test del migrado no cuenta'] = {
  $lee = Java 'resumen' 'ResumenReader' "  private JdbcCursorItemReader<Recibo> r;`n  private FlatFileItemReader<Recibo> f;`n  void m() { jdbcTemplate.queryForList(`"SELECT * FROM T_POLIZAS WHERE A = 1`"); repo.findAll(); mongoTemplate.find(q, X.class); }`n"
  $mig = @{} + $MigradoLee
  $mig['src/test/java/com/acme/nuevo/GuardaTest.java'] = (Java 'nuevo' 'GuardaTest' "  void m() { mongoTemplate.save(x); }`n")
  $e = Nuevo-Escenario 'b' @{ 'src/main/java/com/acme/resumen/ResumenReader.java' = $lee } $mig
  Escribe-Mapa $e ([ordered]@{ resumenJob = @('src/main/java/com/acme/resumen/ResumenReader.java') })
  Escribe-Ficha $e 'resumenJob'
  $r = Mide $e
  $j = De $r.Json 'resumenJob'
  Comprueba 'hay JSON con resumenJob' ($null -ne $j)
  if ($null -eq $j) { return }
  Igual 'veredicto' 'a-la-vez' $j.veredicto
  Igual 'sin motivos' 0 @($j.motivos).Count
  Igual 'sin nada que reponer' 0 @($j.reponer).Count
}

$Pruebas['03 c) como b, pero el migrado lleva mongoTemplate.save(: en-serie, lado migrado, no se sabe de que job; y reponer habla de Mongo'] = {
  $mig = @{} + $MigradoLee
  $guarda = Java 'nuevo' 'Guarda' "  void m() { mongoTemplate.save(x); }`n"
  $mig['src/main/java/com/acme/nuevo/Guarda.java'] = $guarda
  $e = Nuevo-Escenario 'c' @{ 'src/main/java/com/acme/resumen/ResumenReader.java' = (Java 'resumen' 'ResumenReader' "  private JdbcCursorItemReader<Recibo> r;`n") } $mig
  Escribe-Mapa $e ([ordered]@{ resumenJob = @('src/main/java/com/acme/resumen/ResumenReader.java'); cargaJob = @('src/main/java/com/acme/resumen/ResumenReader.java') })
  Escribe-Ficha $e 'resumenJob'
  Escribe-Ficha $e 'cargaJob'
  $r = Mide $e
  foreach ($nombre in @('resumenJob', 'cargaJob')) {
    $j = De $r.Json $nombre
    if ($null -eq $j) { Comprueba "hay JSON con $nombre" $false; continue }
    Igual "$nombre : veredicto" 'en-serie' $j.veredicto
    $m = @(Motivos-De $j 'mongo' 'migrado')
    Igual "$nombre : un motivo mongo del migrado" 1 $m.Count
    if ($m.Count -ne 1) { continue }
    Comprueba "$nombre : el texto dice que no sabe de que job es" ($m[0].texto.Contains($NoSeDeQueJob)) $m[0].texto
    Igual "$nombre : fichero" 'src/main/java/com/acme/nuevo/Guarda.java' $m[0].fichero
    Igual "$nombre : linea" (Linea-De $guarda 'mongoTemplate.save(') $m[0].linea
    Comprueba "$nombre : reponer habla de las colecciones de Mongo" (@($j.reponer | Where-Object { $_ -match 'colecciones de Mongo' }).Count -eq 1) (@($j.reponer) -join ' / ')
  }
}

$Pruebas['04 d) un lanzador enlazado con cargaJob que hace mv: motivo consume del lanzador con su linea y su cita, y una entrada en reponer; el de otro job no cuenta'] = {
  $e = Nuevo-Escenario 'd' @{
    'src/main/java/com/acme/carga/Lee.java' = (Java 'carga' 'Lee' "  private FlatFileItemReader<Recibo> r;`n")
    'src/main/java/com/acme/resumen/Lee.java' = (Java 'resumen' 'Lee' "  private FlatFileItemReader<Recibo> r;`n")
  }
  Escribe-Mapa $e ([ordered]@{ cargaJob = @('src/main/java/com/acme/carga/Lee.java'); resumenJob = @('src/main/java/com/acme/resumen/Lee.java') })
  Escribe-Ficha $e 'cargaJob'
  Escribe-Ficha $e 'resumenJob'
  Escribe-Lanzadores $e @(@{ nombre = 'lanza-carga.sh'; lineas = @('#!/bin/bash', 'mv entrada/*.txt hecho/', 'java -jar batch-recibos.jar --job=cargaJob'); jobs = @('cargaJob') })
  $r = Mide $e
  $j = De $r.Json 'cargaJob'
  Comprueba 'hay JSON con cargaJob' ($null -ne $j)
  if ($null -eq $j) { return }
  Igual 'veredicto' 'en-serie' $j.veredicto
  $m = @(Motivos-De $j 'consume' 'lanzador')
  Igual 'un motivo consume del lanzador' 1 $m.Count
  if ($m.Count -eq 1) {
    Igual 'fichero: el script' 'lanzadores/lanza-carga.sh' $m[0].fichero
    Igual 'linea del mv' 2 $m[0].linea
    Igual 'cita: la linea del script' 'mv entrada/*.txt hecho/' $m[0].cita
  }
  Comprueba 'reponer lleva la cita y dice que mueve o borra ficheros' (@($j.reponer | Where-Object { $_ -match '^mv entrada/\*\.txt hecho/: mueve o borra ficheros\. Antes de lanzar el segundo' }).Count -eq 1) (@($j.reponer) -join ' / ')
  Igual 'resumenJob (sin lanzador) sigue a-la-vez' 'a-la-vez' (De $r.Json 'resumenJob').veredicto
}

$Pruebas['05 e) un lanzador con flock: motivo cerrojo, con el texto de que el segundo no arranca mientras el primero corre'] = {
  $e = Nuevo-Escenario 'e' @{ 'src/main/java/com/acme/carga/Lee.java' = (Java 'carga' 'Lee' "  private FlatFileItemReader<Recibo> r;`n") }
  Escribe-Mapa $e ([ordered]@{ cargaJob = @('src/main/java/com/acme/carga/Lee.java') })
  Escribe-Ficha $e 'cargaJob'
  Escribe-Lanzadores $e @(@{ nombre = 'lanza-carga.sh'; lineas = @('#!/bin/bash', 'flock -n 9 || exit 1', 'java -jar batch-recibos.jar --job=cargaJob'); jobs = @('cargaJob') })
  $r = Mide $e
  $j = De $r.Json 'cargaJob'
  Comprueba 'hay JSON con cargaJob' ($null -ne $j)
  if ($null -eq $j) { return }
  Igual 'veredicto' 'en-serie' $j.veredicto
  $m = @(Motivos-De $j 'cerrojo' 'lanzador')
  Igual 'un motivo cerrojo del lanzador' 1 $m.Count
  if ($m.Count -eq 1) {
    Igual 'linea del flock' 2 $m[0].linea
    Comprueba 'el texto' ($m[0].texto -ceq 'comparten cerrojo: el segundo no arranca mientras el primero corre') $m[0].texto
  }
}

$Pruebas['06 f) avisoJob sin ficha de job: motivo sin-datos y en-serie; con la ficha atascada, tambien'] = {
  $e = Nuevo-Escenario 'f' @{ 'src/main/java/com/acme/aviso/Lee.java' = (Java 'aviso' 'Lee' "  private FlatFileItemReader<Recibo> r;`n") }
  Escribe-Mapa $e ([ordered]@{ avisoJob = @('src/main/java/com/acme/aviso/Lee.java'); resumenJob = @('src/main/java/com/acme/aviso/Lee.java') })
  Escribe-Ficha $e 'resumenJob' @{} 'atascada'
  $r = Mide $e
  foreach ($caso in @(@('avisoJob', 'sin ficha'), @('resumenJob', 'con la ficha atascada'))) {
    $j = De $r.Json $caso[0]
    if ($null -eq $j) { Comprueba "hay JSON con $($caso[0])" $false; continue }
    Igual "$($caso[1]) : veredicto" 'en-serie' $j.veredicto
    $m = @(Motivos-De $j 'sin-datos')
    Igual "$($caso[1]) : un motivo sin-datos" 1 $m.Count
    if ($m.Count -eq 1) { Comprueba "$($caso[1]) : el texto" ($m[0].texto -ceq ($NoSeLoQueToca + (Es ': la ficha del job no est\u00e1 hecha'))) $m[0].texto }
  }
}

$Pruebas['07 g) un jdbcTemplate.update( en un comentario, en un bloque de comentario o dentro de un texto no salta'] = {
  $cuerpo = "  // jdbcTemplate.update(sql);`n  /* repo.save(x); `n     mongoTemplate.save(x); */`n  void m() { log.info(`"jdbcTemplate.update( y Files.write( fallan`"); }`n"
  $e = Nuevo-Escenario 'g' @{ 'src/main/java/com/acme/carga/Comentada.java' = (Java 'carga' 'Comentada' $cuerpo) }
  Escribe-Mapa $e ([ordered]@{ cargaJob = @('src/main/java/com/acme/carga/Comentada.java') })
  Escribe-Ficha $e 'cargaJob'
  $r = Mide $e
  $j = De $r.Json 'cargaJob'
  Comprueba 'hay JSON con cargaJob' ($null -ne $j)
  if ($null -eq $j) { return }
  Igual 'a-la-vez' 'a-la-vez' $j.veredicto
  Igual 'sin motivos' 0 @($j.motivos).Count
}

$Pruebas['08 h) un INSERT INTO T_POLIZAS en una cadena: motivo tabla y reponer nombra T_POLIZAS; todas las tablas del fichero salen, las que solo se leen no'] = {
  $cuerpo = @'
  static final String A = "INSERT INTO T_POLIZAS (ID, IMPORTE) VALUES (?, ?)";
  static final String B = "update ESQ.T_PAGOS p set p.estado = 'X' where p.id = ?";
  static final String C = "DELETE FROM T_AVISOS WHERE F < ?";
  static final String D = "MERGE INTO T_RESUMEN r USING DUAL ON (1 = 1)";
  static final String E = "TRUNCATE TABLE T_TEMPORAL";
  static final String F = "INSERT INTO T_DESTINO SELECT * FROM T_SOLO_LEE";
  static final String G = "SELECT * FROM T_OTRA_LEE FOR UPDATE";
  static final String H = "Error al hacer update the cache";
'@
  $texto = Java 'carga' 'Dao' ($cuerpo + "`n")
  $e = Nuevo-Escenario 'h' @{ 'src/main/java/com/acme/carga/Dao.java' = $texto }
  Escribe-Mapa $e ([ordered]@{ cargaJob = @('src/main/java/com/acme/carga/Dao.java') })
  Escribe-Ficha $e 'cargaJob'
  $r = Mide $e
  $j = De $r.Json 'cargaJob'
  Comprueba 'hay JSON con cargaJob' ($null -ne $j)
  if ($null -eq $j) { return }
  $m = @(Motivos-De $j 'tabla' 'original')
  Igual 'un solo motivo tabla (el de la primera linea)' 1 $m.Count
  if ($m.Count -eq 1) { Igual 'linea del primer INSERT' (Linea-De $texto 'INSERT INTO T_POLIZAS') $m[0].linea }
  $rep = @($j.reponer) -join ' / '
  foreach ($t in @('T_POLIZAS', 'T_PAGOS', 'T_AVISOS', 'T_RESUMEN', 'T_TEMPORAL', 'T_DESTINO')) {
    Comprueba "reponer nombra $t" (@($j.reponer | Where-Object { $_ -ceq ("la tabla $t" + (Es ': deja sus filas como estaban antes del primero (o compara solo lo que a\u00f1ade cada uno)')) }).Count -eq 1) $rep
  }
  Comprueba 'reponer no nombra las que solo se leen' ($rep -notmatch 'T_SOLO_LEE|T_OTRA_LEE|DUAL|\bthe\b') $rep
  Igual 'reponer: solo esas seis tablas' 6 @($j.reponer).Count
}

$Pruebas['09 i) la ficha del job con produce y conexiones: motivos con la marca de IA, con la cita de la ficha; el codigo gana a la ficha si dicen lo mismo del mismo fichero'] = {
  $lee = @{
    'src/main/java/com/acme/carga/Escritor.java' = (Java 'carga' 'Escritor' "  private FlatFileItemReader<Recibo> r;`n")
    'src/main/java/com/acme/carga/Copia.java' = (Java 'carga' 'Copia' "  void m() { Files.write(p, b); }`n")
  }
  $e = Nuevo-Escenario 'i' $lee
  Escribe-Mapa $e ([ordered]@{ cargaJob = @('src/main/java/com/acme/carga/Escritor.java', 'src/main/java/com/acme/carga/Copia.java') })
  Escribe-Ficha $e 'cargaJob' @{
    produce = @(
      (Dato 'salida-fichero' 'Deja el fichero de recibos' 'src/main/java/com/acme/carga/Escritor.java' 12 'writer.write(recibos);'),
      (Dato 'tabla-escribe' 'Guarda los recibos' 'src/main/java/com/acme/carga/Escritor.java' 20 'repo.guardar(recibos);'),
      (Dato 'salida-fichero' 'Otra copia del fichero' 'src/main/java/com/acme/carga/Copia.java' 5 'Files.write(p, b);'))
    conexiones = @(
      (Dato 'sftp' 'Lo sube al servidor' 'src/main/java/com/acme/carga/Escritor.java' 30 'canal.subir(f);'),
      (Dato 'externo' 'Avisa al servicio de recibos' 'src/main/java/com/acme/carga/Escritor.java' 40 'cliente.avisar();'))
  }
  $r = Mide $e
  $j = De $r.Json 'cargaJob'
  Comprueba 'hay JSON con cargaJob' ($null -ne $j)
  if ($null -eq $j) { return }
  Igual 'veredicto' 'en-serie' $j.veredicto
  $f = @(Motivos-De $j 'fichero' 'original' | Where-Object { $_.fichero -ceq 'src/main/java/com/acme/carga/Escritor.java' })
  Igual 'un motivo fichero de la ficha (Escritor)' 1 $f.Count
  if ($f.Count -eq 1) {
    Comprueba 'lleva la marca de IA' ($f[0].ia -eq $true)
    Igual 'linea de la ficha' 12 $f[0].linea
    Igual 'cita de la ficha' 'writer.write(recibos);' $f[0].cita
  }
  foreach ($c in @('tabla', 'sftp', 'http')) {
    $m = @(Motivos-De $j $c)
    Igual "un motivo $c de la ficha" 1 $m.Count
    if ($m.Count -eq 1) { Comprueba "$c lleva la marca de IA" ($m[0].ia -eq $true) }
  }
  $copia = @(Motivos-De $j 'fichero' | Where-Object { $_.fichero -ceq 'src/main/java/com/acme/carga/Copia.java' })
  Igual 'Copia.java: un solo motivo fichero' 1 $copia.Count
  if ($copia.Count -eq 1) { Comprueba 'y es el del codigo (sin marca de IA)' ($copia[0].ia -eq $false) }
}

$Pruebas['10 j) tres .save( en el mismo fichero dan un solo motivo, el de la primera linea; otro fichero da otro'] = {
  $uno = Java 'carga' 'Guarda1' "  void a() { repo.save(x); }`n  void b() { repo.save(y); }`n  void c() { repo.save(z); }`n"
  $dos = Java 'carga' 'Guarda2' "  void a() { otro.save(x); }`n"
  $e = Nuevo-Escenario 'j' @{ 'src/main/java/com/acme/carga/Guarda1.java' = $uno; 'src/main/java/com/acme/carga/Guarda2.java' = $dos }
  Escribe-Mapa $e ([ordered]@{ cargaJob = @('src/main/java/com/acme/carga/Guarda1.java', 'src/main/java/com/acme/carga/Guarda2.java') })
  Escribe-Ficha $e 'cargaJob'
  $r = Mide $e
  $j = De $r.Json 'cargaJob'
  Comprueba 'hay JSON con cargaJob' ($null -ne $j)
  if ($null -eq $j) { return }
  $m = @(Motivos-De $j 'tabla' 'original')
  Igual 'dos motivos (uno por fichero)' 2 $m.Count
  if ($m.Count -eq 2) {
    Igual 'Guarda1: la primera linea' (Linea-De $uno 'repo.save(x)') (@($m | Where-Object { $_.fichero -match 'Guarda1' })[0]).linea
    Igual 'Guarda2: su linea' (Linea-De $dos 'otro.save(x)') (@($m | Where-Object { $_.fichero -match 'Guarda2' })[0]).linea
  }
}

# ================================ CATEGORIAS ================================
$Pruebas['11 categorias del codigo Java: cada patron del encargo da su categoria, y los que solo leen no dan ninguna'] = {
  # nombre del patron -> @(categoria esperada o '' si no debe saltar nada, codigo)
  $casos = [ordered]@{
    'tabla JdbcBatchItemWriter'   = @('tabla', 'new JdbcBatchItemWriterBuilder<X>().build();')
    'tabla JpaItemWriter'         = @('tabla', 'JpaItemWriter<X> w = null;')
    'tabla HibernateItemWriter'   = @('tabla', 'HibernateItemWriter<X> w = null;')
    'tabla RepositoryItemWriter'  = @('tabla', 'RepositoryItemWriter<X> w = null;')
    'tabla .saveAll('             = @('tabla', 'repo.saveAll(xs);')
    'tabla .delete(x)'            = @('tabla', 'repo.delete(x);')
    'tabla .deleteAll('           = @('tabla', 'repo.deleteAll();')
    'tabla .deleteById('          = @('tabla', 'repo.deleteById(1L);')
    'tabla jdbcTemplate.update('  = @('tabla', 'jdbcTemplate.update(sql, a);')
    'tabla .batchUpdate('         = @('tabla', 'jdbc.batchUpdate(sql, lote);')
    'tabla UPDATE SET'            = @('tabla', 'String s = "UPDATE T_PAGOS SET A = 1";')
    'tabla DELETE FROM'           = @('tabla', 'String s = "DELETE FROM T_PAGOS";')
    'tabla MERGE INTO'            = @('tabla', 'String s = "MERGE INTO T_PAGOS USING DUAL ON (1 = 1)";')
    'tabla TRUNCATE TABLE'        = @('tabla', 'String s = "TRUNCATE TABLE T_PAGOS";')
    'fichero FlatFileItemWriter'  = @('fichero', 'new FlatFileItemWriterBuilder<X>().build();')
    'fichero StaxEventItemWriter' = @('fichero', 'new StaxEventItemWriter<X>();')
    'fichero JsonFileItemWriter'  = @('fichero', 'new JsonFileItemWriter<X>(r, m);')
    'fichero Files.write'         = @('fichero', 'Files.write(p, b);')
    'fichero Files.writeString'   = @('fichero', 'Files.writeString(p, s);')
    'fichero newBufferedWriter'   = @('fichero', 'Files.newBufferedWriter(p);')
    'fichero newOutputStream'     = @('fichero', 'Files.newOutputStream(p);')
    'fichero Files.copy'          = @('fichero', 'Files.copy(a, b);')
    'fichero FileWriter'          = @('fichero', 'new FileWriter(f);')
    'fichero FileOutputStream'    = @('fichero', 'new FileOutputStream(f);')
    'consume Files.move'          = @('consume', 'Files.move(a, b);')
    'consume Files.delete'        = @('consume', 'Files.delete(p);')
    'consume deleteIfExists'      = @('consume', 'Files.deleteIfExists(p);')
    'consume renameTo'            = @('consume', 'f.renameTo(g);')
    'consume .delete()'           = @('consume', 'f.delete();')
    'sftp put'                    = @('sftp', 'ChannelSftp ch = abre(); ch.put(a, b);')
    'sftp rename'                 = @('sftp', 'ChannelSftp ch = abre(); ch.rename(a, b);')
    'sftp rm'                     = @('sftp', 'ChannelSftp ch = abre(); ch.rm(a);')
    'sftp mkdir'                  = @('sftp', 'ChannelSftp ch = abre(); ch.mkdir(a);')
    'sftp SftpRemoteFileTemplate' = @('sftp', 'SftpRemoteFileTemplate t = null;')
    'mongo insert'                = @('mongo', 'mongoTemplate.insert(x);')
    'mongo save (no es tabla)'    = @('mongo', 'mongoTemplate.save(x);')
    'mongo upsert'                = @('mongo', 'mongoTemplate.upsert(q, u, X.class);')
    'mongo updateFirst'           = @('mongo', 'mongoTemplate.updateFirst(q, u, X.class);')
    'mongo remove con tipo'       = @('mongo', 'MongoTemplate m = null; m.remove(q, X.class);')
    'mongo findAndModify'         = @('mongo', 'secondaryMongoTemplate.findAndModify(q, u, X.class);')
    'mongo findAndRemove'         = @('mongo', 'mongoTemplate.findAndRemove(q, X.class);')
    'mongo MongoItemWriter'       = @('mongo', 'new MongoItemWriter<X>();')
    'correo JavaMailSender'       = @('correo', 'JavaMailSender s = null;')
    'correo MimeMessage'          = @('correo', 'MimeMessage m = null;')
    'correo SimpleMailMessage'    = @('correo', 'SimpleMailMessage m = new SimpleMailMessage();')
    'mensajes KafkaTemplate'      = @('mensajes', 'KafkaTemplate<String, String> k = null;')
    'mensajes JmsTemplate'        = @('mensajes', 'JmsTemplate k = null;')
    'mensajes RabbitTemplate'     = @('mensajes', 'RabbitTemplate k = null;')
    'mensajes StreamBridge'       = @('mensajes', 'StreamBridge k = null;')
    'http postForObject'          = @('http', 'restTemplate.postForObject(u, b, X.class);')
    'http put'                    = @('http', 'restTemplate.put(u, b);')
    'http delete'                 = @('http', 'restTemplate.delete(u);')
    'http exchange'               = @('http', 'restTemplate.exchange(u, m, e, X.class);')
    'http patchForObject'         = @('http', 'restTemplate.patchForObject(u, b, X.class);')
    'http WebClient post'         = @('http', 'webClient.post().uri(u);')
    'http WebClient put'          = @('http', 'webClient.put().uri(u);')
    'http WebClient delete'       = @('http', 'webClient.delete().uri(u);')
    'http WebClient delete con tipo' = @('http', 'WebClient c = null; c.delete().uri(u);')
    'http WebClient patch'        = @('http', 'webClient.patch().uri(u);')
    'solo lee: RestTemplate get'  = @('', 'restTemplate.getForObject(u, X.class);')
    'solo lee: WebClient get'     = @('', 'webClient.get().uri(u);')
    'solo lee: repo.findAll'      = @('', 'repo.findAll();')
    'solo lee: jdbc query'        = @('', 'jdbcTemplate.queryForList(sql);')
    'solo lee: mongo find'        = @('', 'mongoTemplate.find(q, X.class);')
    'solo lee: Files.readAllLines' = @('', 'Files.readAllLines(p); Files.exists(p);')
    'solo lee: SELECT FOR UPDATE' = @('', 'String s = "SELECT * FROM T_PAGOS FOR UPDATE";')
    'solo lee: Map.put y save sin punto' = @('', 'mapa.put(k, v); guardar(x);')
    'solo lee: un import'         = @('IMPORT', '')
  }
  $legacy = @{}
  $jobs = [ordered]@{}
  $n = 0
  foreach ($k in $casos.Keys) {
    $n++
    $nombre = 'job{0:D2}' -f $n
    $rel = "src/main/java/com/acme/p/C$n.java"
    $cuerpo = '  void m() { ' + $casos[$k][1] + " }`n"
    $texto = Java 'p' "C$n" $cuerpo
    if ($k -ceq 'solo lee: un import') { $texto = "package com.acme.p;`n`nimport org.springframework.batch.item.database.JdbcBatchItemWriter;`nimport java.nio.file.Files;`n`npublic class C$n {`n}`n" }
    $legacy[$rel] = $texto
    $jobs[$nombre] = @($rel)
  }
  $e = Nuevo-Escenario 'categorias' $legacy
  Escribe-Mapa $e $jobs
  foreach ($nombre in $jobs.Keys) { Escribe-Ficha $e $nombre }
  $r = Mide $e
  Comprueba 'hay JSON' ($null -ne $r.Json)
  if ($null -eq $r.Json) { return }
  $n = 0
  foreach ($k in $casos.Keys) {
    $n++
    $j = De $r.Json ('job{0:D2}' -f $n)
    $esperada = $casos[$k][0]
    if ($esperada -ceq 'IMPORT') { $esperada = '' }
    Comprueba "$k" ($null -ne $j -and (Categorias-De $j) -ceq $esperada) "esperaba '$esperada' y sale '$(if ($j) { Categorias-De $j })'"
  }
}

$Pruebas['12 categorias del lanzador: cp, touch, gzip, zip y tar son fichero; mv y rm, consume; sftp, scp y ftp, sftp; mail, mailx y sendmail, correo; curl, http; find, ls y cd, nada; un lanzador de otro job no cuenta'] = {
  $e = Nuevo-Escenario 'lanzador-categorias' @{ 'src/main/java/com/acme/carga/Lee.java' = (Java 'carga' 'Lee' "  private FlatFileItemReader<Recibo> r;`n") }
  $nombres = [ordered]@{
    fichero = @('cp a b', 'touch listo.ok', 'gzip salida.txt', 'zip -r s.zip salida', 'tar cf s.tar salida')
    consume = @('mv a b', 'rm -f a')
    sftp = @('sftp usuario@host', 'scp a usuario@host:b', 'ftp -n host')
    correo = @('mail -s asunto x@acme.com', 'mailx -s asunto x@acme.com', 'sendmail x@acme.com')
    http = @('curl -X POST http://servicio.acme.com/avisa')
    nada = @('find . -name x', 'ls entrada', 'cd /tmp')
  }
  $mapa = [ordered]@{}
  $lz = @()
  foreach ($cat in $nombres.Keys) {
    foreach ($linea in $nombres[$cat]) {
      $orden = ($linea -split ' ')[0]
      $job = "job-$orden"
      $mapa[$job] = @('src/main/java/com/acme/carga/Lee.java')
      $lz += @{ nombre = "$orden.sh"; lineas = @('#!/bin/bash', $linea); jobs = @($job) }
    }
  }
  $mapa['jobSinLanzador'] = @('src/main/java/com/acme/carga/Lee.java')
  $mapa['jobOtro'] = @('src/main/java/com/acme/carga/Lee.java')
  $lz += @{ nombre = 'otro.sh'; lineas = @('#!/bin/bash', 'mv a b'); jobs = @('jobOtro') }
  $lz += @{ nombre = 'suelto.sh'; lineas = @('#!/bin/bash', 'mv a b'); jobs = @() }
  Escribe-Mapa $e $mapa
  foreach ($j in $mapa.Keys) { Escribe-Ficha $e $j }
  Escribe-Lanzadores $e $lz
  $r = Mide $e
  Comprueba 'hay JSON' ($null -ne $r.Json)
  if ($null -eq $r.Json) { return }
  foreach ($cat in $nombres.Keys) {
    foreach ($linea in $nombres[$cat]) {
      $orden = ($linea -split ' ')[0]
      $j = De $r.Json "job-$orden"
      $esperada = $cat
      if ($cat -ceq 'nada') { $esperada = '' }
      Comprueba "$orden -> '$esperada'" ($null -ne $j -and (Categorias-De $j) -ceq $esperada -and @($j.motivos | Where-Object { $_.lado -cne 'lanzador' }).Count -eq 0) "sale '$(if ($j) { Categorias-De $j })'"
    }
  }
  Igual 'un job sin lanzador (y el lanzador sin enlazar no cuenta para nadie): a-la-vez' 'a-la-vez' (De $r.Json 'jobSinLanzador').veredicto
  Igual 'el lanzador de jobOtro cuenta para jobOtro' 'en-serie' (De $r.Json 'jobOtro').veredicto
}

# ================================ EL JSON ================================
$Pruebas['13 el JSON: jobs en el orden de mapa.json, los textos fijos, el mismo JSON al repetir y la cita a 160'] = {
  $larga = "  void m() { repo.save(x); /* " + ('x' * 220) + " */ int y = 1; String s = `"" + ('y' * 200) + "`"; }"
  $texto = ((Java 'carga' 'Larga' ($larga + "`n")) -replace "`n", "`r`n")
  $e = Nuevo-Escenario 'json' @{ 'src/main/java/com/acme/carga/Larga.java' = $texto; 'src/main/java/com/acme/carga/Lee.java' = (Java 'carga' 'Lee' "  private FlatFileItemReader<Recibo> r;`n") }
  Escribe-Mapa $e ([ordered]@{ zetaJob = @('src/main/java/com/acme/carga/Lee.java'); alfaJob = @('src/main/java/com/acme/carga/Larga.java'); medioJob = @('src/main/java/com/acme/carga/Lee.java') })
  foreach ($j in @('zetaJob', 'alfaJob', 'medioJob')) { Escribe-Ficha $e $j }
  $r = Mide $e
  Comprueba 'hay JSON' ($null -ne $r.Json)
  if ($null -eq $r.Json) { return }
  Igual 'jobs en el orden de mapa.json' 'zetaJob,alfaJob,medioJob' ((@($r.Json.jobs | ForEach-Object { $_.job })) -join ',')
  foreach ($c in @('job', 'veredicto', 'motivos', 'reponer')) { Comprueba "el job lleva '$c'" ($null -ne (@($r.Json.jobs)[0].PSObject.Properties[$c])) }
  $m = @(Motivos-De (De $r.Json 'alfaJob') 'tabla')[0]
  Comprueba 'la cita sale sin salto de linea' ($m -and $m.cita -notmatch "[\r\n]") "$($m.cita)"
  Comprueba 'la cita se recorta a 160' ($m -and $m.cita.Length -eq 160) "$($m.cita.Length)"
  foreach ($c in @('fichero', 'linea', 'cita', 'texto', 'lado', 'categoria')) { Comprueba "el motivo lleva '$c'" ($m -and $null -ne $m.PSObject.Properties[$c]) }
  $fijos = $r.Json.fijos
  Comprueba 'fijos.batch habla de BATCH_JOB_EXECUTION_PARAMS y de Spring Batch 5' ($fijos.batch -match 'BATCH_JOB_EXECUTION_PARAMS' -and $fijos.batch -match 'Spring Batch 5')
  Igual 'fijos.serie: cinco pasos' 5 @($fijos.serie).Count
  Comprueba 'fijos.serie: el primero lanza el viejo y el cuarto el nuevo' ($fijos.serie[0] -match '^Lanza el viejo' -and $fijos.serie[3] -match '^Lanza el nuevo')
  Comprueba 'fijos.aLaVez' ($fijos.aLaVez -match 'puedes lanzarlos a la vez')
  $antes = Lee-Texto $e.Json
  [void](Mide $e)
  Comprueba 'repetir da el mismo JSON, byte a byte' ($antes -ceq (Lee-Texto $e.Json))
  $total = @($r.Info).Count
  Igual 'una sola linea Info' 1 $total
}

$Pruebas['14 nunca lanza ni para: sin mapa.json no escribe nada y dice una linea Info; con un mapa roto, un original o un migrado que no se leen, tampoco lanza y dice que no sabe'] = {
  # (l) sin mapa.json
  $e = Nuevo-Escenario 'l-sin-mapa'
  $r = Mide $e
  Comprueba 'sin mapa.json no escribe convivencia.json' (-not (Test-Path -LiteralPath $e.Json))
  Igual 'sin mapa.json no deja ningun fichero en datos' 0 @(Get-ChildItem -LiteralPath $e.Datos -Recurse -File).Count
  Igual 'sin mapa.json: una sola cosa en la consola' 1 @($r.Todo).Count
  Igual 'y es una linea Info' 1 @($r.Info).Count
  Igual 'ni aviso ni fallo (ni amarillo ni rojo)' 0 @($r.Colores).Count
  # mapa.json que no se lee
  $e = Nuevo-Escenario 'l-mapa-roto'
  Escribe (Join-Path $e.Raiz 'datos') 'mapa.json' '{ esto no es json'
  $r = Mide $e
  Comprueba 'con el mapa roto no escribe convivencia.json' (-not (Test-Path -LiteralPath $e.Json))
  Igual 'con el mapa roto: una sola linea Info' 1 @($r.Todo).Count
  # una clase del mapa que no esta en el original: no se sabe lo que toca
  $e = Nuevo-Escenario 'l-sin-clase'
  Escribe-Mapa $e ([ordered]@{ cargaJob = @('src/main/java/com/acme/carga/NoEsta.java') })
  Escribe-Ficha $e 'cargaJob'
  $r = Mide $e
  $j = De $r.Json 'cargaJob'
  Comprueba 'con una clase que no se lee: hay JSON y es en-serie con sin-datos' ($null -ne $j -and $j.veredicto -ceq 'en-serie' -and @(Motivos-De $j 'sin-datos' 'original').Count -eq 1)
  # un migrado sin src/main/java
  $e = Nuevo-Escenario 'l-sin-migrado' @{ 'src/main/java/com/acme/carga/Lee.java' = (Java 'carga' 'Lee' "  private FlatFileItemReader<Recibo> r;`n") } @{ 'README.md' = 'nada' }
  Escribe-Mapa $e ([ordered]@{ cargaJob = @('src/main/java/com/acme/carga/Lee.java') })
  Escribe-Ficha $e 'cargaJob'
  $r = Mide $e
  $j = De $r.Json 'cargaJob'
  Comprueba 'sin src/main/java en el migrado: en-serie con sin-datos del migrado' ($null -ne $j -and $j.veredicto -ceq 'en-serie' -and @(Motivos-De $j 'sin-datos' 'migrado').Count -eq 1)
  # sin lanzadores.json ni carpeta jobs: sigue sin lanzar
  $e = Nuevo-Escenario 'l-sin-fichas' @{ 'src/main/java/com/acme/carga/Lee.java' = (Java 'carga' 'Lee' "  private FlatFileItemReader<Recibo> r;`n") }
  Remove-Item -LiteralPath (Join-Path $e.Datos 'jobs') -Recurse -Force
  Escribe-Mapa $e ([ordered]@{ cargaJob = @('src/main/java/com/acme/carga/Lee.java') })
  $r = Mide $e
  Comprueba 'sin la carpeta jobs: hay JSON con sin-datos' ($null -ne $r.Json -and @(Motivos-De (De $r.Json 'cargaJob') 'sin-datos').Count -eq 1)
}

# ================================ LA PAGINA 1 ================================
# El hash de la pagina 1 del escenario de pagina sin convivencia.json, medido con el codigo de antes de C2 (667216e): tiene que seguir igual.
$HashPagina1SinConvivencia = '82BDDA8C49159DADC10A7FF7653F09795190C732829D10C181FA6C5A928DA52F'

function Nueva-Salida([string]$Nombre) {
  $lee = @{
    'src/main/java/com/acme/carga/CargaWriter.java' = (Java 'carga' 'CargaWriter' "  private JdbcBatchItemWriter<Recibo> escritor;`n")
    'src/main/java/com/acme/resumen/ResumenReader.java' = (Java 'resumen' 'ResumenReader' "  private JdbcCursorItemReader<Recibo> r;`n")
    'src/main/java/com/acme/aviso/AvisoTasklet.java' = (Java 'aviso' 'AvisoTasklet' "  private FlatFileItemReader<Recibo> r;`n")
  }
  $e = Nuevo-Escenario $Nombre $lee
  Escribe-Mapa $e ([ordered]@{ cargaJob = @('src/main/java/com/acme/carga/CargaWriter.java'); resumenJob = @('src/main/java/com/acme/resumen/ResumenReader.java'); avisoJob = @('src/main/java/com/acme/aviso/AvisoTasklet.java') })
  Escribe-Ficha $e 'cargaJob'
  Escribe-Ficha $e 'resumenJob'
  Escribe-Json (Join-Path (Join-Path $e.Datos 'pruebas') 'cargaJob.json') ([ordered]@{ job = 'cargaJob'; preparar = @(); casos = @([ordered]@{ titulo = 'Caso 1'; entrada = 'Un recibo.'; esperado = 'Se guarda.'; refs = @() }); comprobar = @(); sinCaso = @(); redaccion = 'hecha' })
  Escribe-Lanzadores $e @(@{ nombre = 'lanza-carga.sh'; lineas = @('#!/bin/bash', 'mv entrada/*.txt hecho/', 'java -jar batch-recibos.jar --job=cargaJob'); jobs = @('cargaJob') })
  return $e
}

function Pagina([string]$Salida, [string]$Nombre) { return ([System.IO.File]::ReadAllText((Join-Path $Salida $Nombre)) -replace "`r`n", "`n") }

function Hash-Texto([string]$Texto) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  return (([BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Texto)))) -replace '-', '')
}

# El <article> de un job de la pagina 1.
function Articulo([string]$Html, [string]$Job) {
  return [regex]::Match($Html, '(?s)<article class="job" id="job-' + [regex]::Escape($Job) + '">.*?</article>').Value
}

$Pruebas['15 k) pagina 1 con convivencia.json: el bloque arriba de "Como probarlo en pre" con el veredicto, los motivos, que reponer, el orden y el texto de BATCH_'] = {
  $e = Nueva-Salida 'pagina'
  Write-Informes -Salida $e.Raiz
  $sin = Pagina $e.Raiz '1-batch-original.html'
  $sinOtras = @('index.html', '2-problemas.html', '3-original-vs-migrado.html', '4-correcciones.html', '5-buenas-practicas.html' | ForEach-Object { Hash-Texto (Pagina $e.Raiz $_) })
  Comprueba 'sin convivencia.json la pagina no lleva ningun bloque conv' ($sin -notmatch 'class="conv')
  Igual 'sin convivencia.json la pagina 1 es la de antes (hash medido en 667216e)' $HashPagina1SinConvivencia (Hash-Texto $sin)
  [void](Mide $e)
  Comprueba 'Invoke-Convivencia ha dejado convivencia.json' (Test-Path -LiteralPath $e.Json)
  Write-Informes -Salida $e.Raiz
  $con = Pagina $e.Raiz '1-batch-original.html'
  $otras = @('index.html', '2-problemas.html', '3-original-vs-migrado.html', '4-correcciones.html', '5-buenas-practicas.html' | ForEach-Object { Hash-Texto (Pagina $e.Raiz $_) })
  Igual 'las demas paginas no cambian' ($sinOtras -join ',') ($otras -join ',')
  $json = Lee-Json $e.Json
  $carga = Articulo $con 'cargaJob'
  $conv = [regex]::Match($carga, '(?s)<div class="conv">.*?</div>').Value
  Comprueba 'cargaJob lleva el bloque' ($conv.Length -gt 0) 'no hay <div class="conv">'
  $pre = $carga.IndexOf('Antes de lanzarlo')
  Comprueba 'el bloque esta arriba: antes de "Antes de lanzarlo" y despues del titulo de la seccion' ($conv.Length -gt 0 -and $carga.IndexOf('<div class="conv">') -lt $pre -and $carga.IndexOf('<div class="conv">') -gt $carga.IndexOf((Es 'C\u00f3mo probarlo en pre')))
  Comprueba 'dice Uno detras de otro' ($conv.Contains($UnoDetras))
  Comprueba 'el motivo lleva fichero:linea' ($conv.Contains('src/main/java/com/acme/carga/CargaWriter.java:4'))
  Comprueba 'el motivo lleva la cita (escapada)' ($conv.Contains((ConvertTo-TextoHtml 'private JdbcBatchItemWriter<Recibo> escritor;')))
  Comprueba 'el motivo lleva la etiqueta Medido' ($conv.Contains('et-medido'))
  Comprueba 'que reponer lleva la linea del mv' ($conv.Contains($QueReponer) -and $conv.Contains('mv entrada/*.txt hecho/'))
  Igual 'el orden en serie lleva los cinco pasos' 5 ([regex]::Matches($conv, '<li>(Lanza|Guarda|Rep|Compara)').Count)
  Comprueba 'lleva el texto de BATCH_ del JSON (escapado)' ($conv.Contains((ConvertTo-TextoHtml $json.fijos.batch)))
  Comprueba 'no lleva el texto de a la vez' (-not $conv.Contains((ConvertTo-TextoHtml $json.fijos.aLaVez)))
  $resumen = Articulo $con 'resumenJob'
  $convR = [regex]::Match($resumen, '(?s)<div class="conv">.*?</div>').Value
  Comprueba 'resumenJob: dice A la vez y lleva su texto' ($convR.Contains('A la vez') -and $convR.Contains((ConvertTo-TextoHtml $json.fijos.aLaVez)))
  Comprueba 'resumenJob: sin motivos, sin que reponer y sin orden' (-not $convR.Contains($QueReponer) -and -not $convR.Contains($UnoDetras) -and $convR -notmatch '<li>')
  Comprueba 'resumenJob: lleva el texto de BATCH_' ($convR.Contains((ConvertTo-TextoHtml $json.fijos.batch)))
  $aviso = Articulo $con 'avisoJob'
  Comprueba 'avisoJob (sin ficha): lleva su seccion de pre con el bloque y dice que no sabe lo que toca' ($aviso.Contains('id="pre-avisoJob"') -and $aviso.Contains($UnoDetras) -and $aviso.Contains($NoSeLoQueToca))
  # solo cambian los bloques: quitados, la pagina es la de antes
  $quitada = [regex]::Replace($con, '(?s)<div class="conv">.*?</div>\n', '')
  $quitada = [regex]::Replace($quitada, '(?s)<section class="pre" id="pre-avisoJob">.*?</section>', '')
  Comprueba 'quitados los bloques, la pagina 1 es la de antes' ($quitada -ceq $sin)
  # un JSON sin ese job: la pagina es la de antes
  $json.jobs = @($json.jobs | Where-Object { $_.job -cne 'cargaJob' -and $_.job -cne 'resumenJob' -and $_.job -cne 'avisoJob' })
  Escribe-Json $e.Json $json
  Write-Informes -Salida $e.Raiz
  Igual 'con un convivencia.json sin esos jobs la pagina 1 es la de antes' $HashPagina1SinConvivencia (Hash-Texto (Pagina $e.Raiz '1-batch-original.html'))
}

$Pruebas['16 k) pagina 1 con un convivencia.json hecho a mano: mas de 8 motivos dicen "y N mas", la marca de IA sale en los de la ficha y todo se escapa'] = {
  $e = Nueva-Salida 'pagina-mano'
  $motivos = @()
  for ($i = 1; $i -le 10; $i++) {
    $motivos += [ordered]@{ categoria = 'fichero'; lado = 'original'; fichero = "src/main/java/com/acme/carga/F$i.java"; linea = $i; cita = "cita <$i> & co"; texto = "texto $i"; ia = ($i -eq 2) }
  }
  $json = [ordered]@{
    jobs = @([ordered]@{ job = 'cargaJob'; veredicto = 'en-serie'; motivos = $motivos; reponer = @('la tabla T_X: algo <raro>') })
    fijos = [ordered]@{ batch = 'Texto BATCH_ <fijo>'; serie = @('Paso uno', 'Paso dos'); aLaVez = 'Texto a la vez' }
  }
  Escribe-Json $e.Json $json
  Write-Informes -Salida $e.Raiz
  $carga = Articulo (Pagina $e.Raiz '1-batch-original.html') 'cargaJob'
  $conv = [regex]::Match($carga, '(?s)<div class="conv">.*?</div>').Value
  Comprueba 'hay bloque' ($conv.Length -gt 0)
  Igual 'ocho motivos' 8 ([regex]::Matches($conv, 'texto \d+').Count)
  Comprueba 'y 2 mas' ($conv.Contains((Es 'y 2 m\u00e1s')))
  Comprueba 'el segundo motivo lleva la marca de IA' ($conv.Contains($LeidoPorIA))
  Igual 'y solo ese' 1 ([regex]::Matches($conv, [regex]::Escape($LeidoPorIA)).Count)
  Igual 'los otros siete llevan Medido' 7 ([regex]::Matches($conv, 'et et-medido').Count)
  Comprueba 'la cita sale escapada' ($conv.Contains('cita &lt;1&gt; &amp; co') -and -not $conv.Contains('<1>'))
  Comprueba 'que reponer sale escapado' ($conv.Contains('la tabla T_X: algo &lt;raro&gt;'))
  Comprueba 'el texto fijo sale escapado' ($conv.Contains('Texto BATCH_ &lt;fijo&gt;'))
  Comprueba 'los pasos del JSON' ($conv.Contains('<li>Paso uno</li>') -and $conv.Contains('<li>Paso dos</li>'))
}

# ================================ EL CODIGO ================================
$Pruebas['17 m) Get-NombreTabla y Get-TablasSql se han movido a comun.ps1, sin copias en otro .ps1, y siguen dando lo mismo'] = {
  $dueno = @(Get-ChildItem -LiteralPath $raiz -File -Filter '*.ps1' | ForEach-Object { $n = $_.Name; [regex]::Matches([System.IO.File]::ReadAllText($_.FullName), '(?m)^function (Get-NombreTabla|Get-TablasSql)\b') | ForEach-Object { "$n : $($_.Groups[1].Value)" } })
  Igual 'cada una esta definida una sola vez' 2 $dueno.Count
  Comprueba 'las dos estan en comun.ps1' (@($dueno | Where-Object { $_ -match '^comun\.ps1 : ' }).Count -eq 2) ($dueno -join ', ')
  $t = @(Get-TablasSql 'INSERT INTO esq.t_polizas (id) VALUES (?)')
  Comprueba 'Get-TablasSql da T_POLIZAS' ($t.Count -eq 1 -and $t[0].tabla -ceq 'T_POLIZAS') (($t | ForEach-Object { $_.tabla }) -join ',')
  Igual 'Get-NombreTabla descarta BATCH_' '' (Get-NombreTabla 'BATCH_JOB_INSTANCE')
  Igual 'Get-NombreTabla quita esquema y comillas' 'T_X' (Get-NombreTabla '"ESQ"."T_X"')
}

$Pruebas['18 convivencia.ps1: solo funciones, cabecera, ASCII, nada de PowerShell 7 y ninguna funcion repetida en otro script'] = {
  $ruta = Join-Path $raiz 'convivencia.ps1'
  Comprueba 'existe junto a migracion.ps1' (Test-Path -LiteralPath $ruta)
  if (-not (Test-Path -LiteralPath $ruta)) { return }
  $codigo = [System.IO.File]::ReadAllText($ruta)
  Comprueba 'empieza con su cabecera de ayuda' ($codigo.TrimStart().StartsWith('<#'))
  Comprueba 'nada de PowerShell 7 (??, ?. ni ?[)' ($codigo -notmatch '\?\?|[\w\)\]]\?\.\w|\w\?\[')
  Comprueba 'sin -AsHashtable ni ConvertFrom-Json -Depth' ($codigo -notmatch 'AsHashtable|ConvertFrom-Json[^|\r\n]*-Depth')
  Comprueba 'sin Join-Path de tres rutas' ($codigo -notmatch 'Join-Path\s+[^\s|)]+\s+[^\s|)]+\s+[^\s|)]+\s*\)')
  foreach ($f in @('convivencia.ps1', 'tests/probar-convivencia.ps1')) {
    $x = [System.IO.File]::ReadAllText((Get-Ruta $raiz $f))
    Comprueba "$f : solo ASCII" ($x -notmatch '[^\x09\x0A\x0D\x20-\x7E]')
  }
  $ast = [System.Management.Automation.Language.Parser]::ParseInput($codigo, [ref]$null, [ref]$null)
  $sueltas = @($ast.EndBlock.Statements | Where-Object { $_ -isnot [System.Management.Automation.Language.FunctionDefinitionAst] })
  Igual 'nada fuera de las funciones' 0 $sueltas.Count
  $suyas = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Name })
  $deMas = @(Get-ChildItem -LiteralPath $raiz -File -Filter '*.ps1' | Where-Object { $_.Name -cne 'convivencia.ps1' } | ForEach-Object {
      [regex]::Matches([System.IO.File]::ReadAllText($_.FullName), '(?m)^function ([\w-]+)') | ForEach-Object { $_.Groups[1].Value }
    })
  $repetidas = @($suyas | Where-Object { $deMas -contains $_ })
  Comprueba 'define funciones' ($suyas.Count -gt 0)
  Comprueba 'define Invoke-Convivencia' ($suyas -contains 'Invoke-Convivencia')
  Comprueba 'ninguna esta repetida en otro .ps1 de la raiz' ($repetidas.Count -eq 0) ($repetidas -join ', ')
}

Invoke-Banco $Pruebas 'tests/probar-convivencia.ps1'
