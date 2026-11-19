<#
probar-regresion.ps1 - Banco de pruebas de -Regresion de prueba-local.ps1 (m33): los casos que salen iguales en la prueba en local se quedan
como tests de JUnit en la rama de rescate del migrado.
No necesita Maven, Java ni Copilot: usa tests/falsos/m25-copilot.ps1 y m33-mvn.ps1 (sobre m25-mvn.ps1 y mvn-local.ps1) y repos de juguete
que crea en una carpeta temporal. Solo hace falta git; con un javac (o el modulo jdk.compiler del java) tambien compila y ejecuta la plantilla
regresion/RegresionLocalTest.java.txt contra un JUnit 5 falso. Vale para Windows PowerShell 5.1 y PowerShell 7. Solo ASCII.

  .\tests\probar-regresion.ps1                          # todas las pruebas
  .\tests\probar-regresion.ps1 -Solo sordo              # las que llevan 'sordo' en el nombre
  .\tests\probar-regresion.ps1 -Dir D:\tmp\x -Conservar # deja los repos de juguete para mirarlos

Sale con 0 si todo pasa y con 1 si algo falla.
#>
param(
  [string]$Dir = '',
  [string]$Script = '',
  [string]$Solo = '',
  [switch]$Conservar
)
$ErrorActionPreference = 'Stop'
$aqui = Split-Path -Parent $MyInvocation.MyCommand.Path
$raiz = Split-Path -Parent $aqui
if (-not $Script) { $Script = Join-Path $raiz 'prueba-local.ps1' }
$falsos = Join-Path $aqui 'falsos'
. (Join-Path $aqui 'comun-banco.ps1')

# ============================== UTILIDADES ==============================
function Pom([string]$Id) {
  return "<project xmlns=`"http://maven.apache.org/POM/4.0.0`">`n  <modelVersion>4.0.0</modelVersion>`n  <groupId>com.acme</groupId>`n  <artifactId>$Id</artifactId>`n  <version>1.0.0</version>`n</project>`n"
}

function App([string]$Paquete) {
  return "package $Paquete;`n`n@SpringBootApplication`npublic class App {`n}`n"
}

function Lee-Json([string]$Ruta) {
  if (-not (Test-Path -LiteralPath $Ruta)) { return $null }
  return ([System.IO.File]::ReadAllText($Ruta) | ConvertFrom-Json)
}

# Hace un commit en $D con $Rel = $Texto.
function Commit-En([string]$D, [string]$Rel, [string]$Texto, [string]$Asunto) {
  Escribe $D $Rel $Texto
  [void](GitEn $D @('add', '--', $Rel))
  [void](GitEn $D @('commit', '-q', '-m', $Asunto))
}

# Un escenario como el de tests/probar-local.ps1: el original (batch-viejo, con $ReglaOrig en regla.txt), el migrado (batch-nuevo, rama main) con su
# worktree de rescate (rama rescate/main-1, con $ReglaMig en regla.txt), los casos de migracion.ps1 ($Casos: job -> entradas, una por caso) y la
# carpeta de ajustes, con el Copilot de m25 y el Maven de m33. Con -Limite, la rama de rescate lleva minimo=5.01 en src/main/resources/regla.txt (que
# mvn-local.ps1 lee antes que el de la raiz) y el 'arreglo' de m25-copilot.ps1 (reparar-arregla) es dejarlo en 5.00.
function Escenario-M33([string]$Nombre, $Casos, [string]$ReglaOrig = 'minimo=5.00', [string]$ReglaMig = 'minimo=5.00', [switch]$Limite) {
  $raizE = Join-Path $Dir $Nombre
  if (Test-Path -LiteralPath $raizE) { Remove-Item -LiteralPath $raizE -Recurse -Force }
  $leg = Join-Path $raizE 'batch-viejo'
  $mig = Join-Path $raizE 'batch-nuevo'
  $casa = Join-Path $raizE 'home'
  Escribe $leg 'pom.xml' (Pom 'batch-viejo')
  Escribe $leg 'src/main/java/com/acme/viejo/App.java' (App 'com.acme.viejo')
  Escribe $leg 'src/main/java/com/acme/viejo/Lector.java' "package com.acme.viejo;`n`npublic class Lector {`n}`n"
  Escribe $leg 'regla.txt' "$ReglaOrig`n"
  Escribe $mig 'pom.xml' (Pom 'batch-nuevo')
  Escribe $mig 'src/main/java/com/acme/nuevo/App.java' (App 'com.acme.nuevo')
  Escribe $mig 'regla.txt' "minimo=5.00`n"
  foreach ($d in @($leg, $mig)) { Inicia-Repo $d }
  $wt = $mig + '-rescate'
  [void](GitEn $mig @('worktree', 'add', '-q', '-b', 'rescate/main-1', $wt))
  Escribe $wt 'regla.txt' "$ReglaMig`n"
  [void](GitEn $wt @('commit', '-q', '-a', '--allow-empty', '-m', 'rescate'))
  if ($Limite) { Commit-En $wt 'src/main/resources/regla.txt' "minimo=5.01`n" 'migra el limite' }
  [System.IO.File]::AppendAllText((Get-Ruta $mig '.git/info/exclude'), "`nmigracion-*/`n")
  $datos = Get-Ruta $mig 'migracion-batch-nuevo/datos'
  $jobs = @()
  foreach ($j in $Casos.Keys) {
    $cs = @()
    $n = 0
    foreach ($en in @($Casos[$j])) { $n++; $cs += [ordered]@{ titulo = "Caso $n de $j"; entrada = $en; esperado = 'Lo que haga el original.'; refs = @('clase-11111111#1') } }
    Escribe $datos "pruebas/$j.json" (ConvertTo-Json -InputObject ([ordered]@{ job = $j; preparar = @(); casos = $cs; comprobar = @(); sinCaso = @(); redaccion = 'hecha' }) -Depth 6)
    $jobs += [ordered]@{ job = $j; clases = @([ordered]@{ clase = 'Lector'; fichero = 'src/main/java/com/acme/viejo/Lector.java'; ficha = 'clase-11111111' }) }
  }
  Escribe $datos 'mapa.json' (ConvertTo-Json -InputObject ([ordered]@{ jobs = $jobs; sinJob = @() }) -Depth 6)
  $ficha = [ordered]@{ id = 'clase-11111111'; fichero = 'src/main/java/com/acme/viejo/Lector.java'; clase = 'Lector'; papel = 'lector'; queHace = 'Lee la entrada.'; datos = @([ordered]@{ tipo = 'entrada-fichero'; texto = 'Lee el fichero de entrada.' }, [ordered]@{ tipo = 'regla'; texto = 'El importe minimo es 5,00.' }) }
  Escribe $datos 'fichas/clase-11111111.json' (ConvertTo-Json -InputObject $ficha -Depth 6)
  $aj = [ordered]@{ CopilotExe = (Join-Path $falsos 'm25-copilot.ps1'); MvnExe = (Join-Path $falsos 'm33-mvn.ps1'); SegundosPorLlamada = 60 }
  Escribe $casa 'ajustes.json' (ConvertTo-Json -InputObject $aj)
  return [pscustomobject]@{
    Raiz = $raizE; Legacy = $leg; Migrado = $mig; Wt = $wt; Home = $casa; Llamadas = (Join-Path $raizE 'llamadas')
    Local = (Get-Ruta $mig 'migracion-batch-nuevo/prueba-local'); Json = (Get-Ruta $mig 'migracion-batch-nuevo/datos/prueba-local.json')
    Regresion = (Get-Ruta $mig 'migracion-batch-nuevo/datos/regresion.json')
  }
}

# Lanza prueba-local.ps1 -Si con RESCATE_HOME en la carpeta del escenario (nunca toca los ajustes reales). $Modo son las palabras de RESCATE_M33
# (ver m33-mvn.ps1); por defecto, 'estable': lo que sale de un caso no lleva la fecha, la hora ni la ruta de hoy.
function Prueba($E, [string[]]$A = @(), [string]$Guion = '', [string]$Modo = 'estable') {
  $env:RESCATE_HOME = $E.Home
  $env:RESCATE_LLAMADAS = $E.Llamadas
  $env:RESCATE_M33 = $Modo
  try { return Lanzar $Script (@('-Legacy', $E.Legacy, '-Migrado', $E.Migrado, '-Modelo', 'modelo-x', '-Si') + $A) $Guion @('') }
  finally { $env:RESCATE_HOME = ''; $env:RESCATE_LLAMADAS = ''; $env:RESCATE_M33 = '' }
}

function Corto([string]$Hash) { return $Hash.Substring(0, 7) }

function Caso($E, [string]$Job, [string]$Caso) { return @((Lee-Json $E.Json).casos | Where-Object { $_.job -eq $Job -and $_.caso -eq $Caso })[0] }

# Los ficheros que toco el commit $Ref de $D, en orden ordinal y unidos con '|'.
function Ficheros-Del-Commit([string]$D, [string]$Ref = 'HEAD') {
  [string[]]$l = @((GitEn $D @('show', '--name-only', '--format=', $Ref)) -split "`n" | Where-Object { $_ })
  [System.Array]::Sort($l, [System.StringComparer]::Ordinal)
  return ($l -join '|')
}

function Estado-Git([string]$D) { return ((GitEn $D @('rev-parse', 'HEAD')) + '|' + (GitEn $D @('status', '--porcelain'))) }

function Foto([string]$D) { return ((GitEn $D @('rev-parse', 'HEAD')) + '|' + (GitEn $D @('status', '--porcelain')) + '|' + (GitEn $D @('branch', '-v', '--no-abbrev'))) }

# El esperado y las entradas de un caso, en la rama de rescate, tal como los deja -Regresion.
$Esp = 'src/test/resources/prueba-local-esperado'
$Ent = 'src/test/resources/prueba-local'

# ================================ PRUEBAS ================================
$Pruebas = [ordered]@{}

$Pruebas['m33 (a)(g) dos casos iguales y uno distinto: se commitean los dos con sus entradas, su esperado, el arnes y RegresionLocalTest.java con su paquete; el distinto no; el commit lleva solo esos ficheros y la rama de rescate queda limpia'] = {
  $e = Escenario-M33 'm33-a' ([ordered]@{ cargaJob = @('importe=10.00 | SQL importe=7.00', 'importe=5.00'); remesaJob = @('importe=20.00') }) 'minimo=5.00' 'minimo=5.01'
  $wt0 = GitEn $e.Wt @('rev-parse', 'HEAD')
  $usuario = Estado-Git $e.Migrado
  $original = Foto $e.Legacy
  $r = Prueba $e @('-Regresion')
  Igual 'sale con 2 (un caso sigue distinto: la regresion no cambia el codigo)' 2 $r.Codigo
  Igual 'los casos: igual, distinto, igual' 'igual,distinto,igual' ((@((Lee-Json $e.Json).casos | ForEach-Object { $_.resultado })) -join ',')
  Igual 'un solo commit nuevo en la rama de rescate' 1 (GitEn $e.Wt @('rev-list', '--count', "$wt0..HEAD"))
  Igual 'con el asunto de siempre y los numeros' 'test(regresion): casos de la prueba en local como tests (2 casos, 2 jobs)' (GitEn $e.Wt @('log', '-1', '--format=%s'))
  $quedan = 'src/test/java/com/acme/nuevo/PruebaLocalTest.java', 'src/test/java/com/acme/nuevo/RegresionLocalTest.java', 'src/test/resources/junit-platform.properties',
    "$Esp/cargaJob/caso-01/estado.txt", "$Esp/cargaJob/caso-01/ficheros/salida/resultado.txt", "$Esp/cargaJob/caso-01/tablas/DATOS.csv",
    "$Esp/remesaJob/caso-01/estado.txt", "$Esp/remesaJob/caso-01/ficheros/salida/resultado.txt",
    "$Ent/cargaJob/caso-01/datos.sql", "$Ent/cargaJob/caso-01/ficheros/entrada/datos.txt", "$Ent/remesaJob/caso-01/ficheros/entrada/datos.txt"
  [string[]]$quedan = $quedan
  [System.Array]::Sort($quedan, [System.StringComparer]::Ordinal)
  Igual '(g) el commit lleva solo esos ficheros: el arnes, RegresionLocalTest, el orden de las clases, y las entradas y el esperado de los dos casos' ($quedan -join '|') (Ficheros-Del-Commit $e.Wt)
  Igual '(g) la carpeta de la rama de rescate queda limpia' '' (GitEn $e.Wt @('status', '--porcelain'))
  Igual '(g) la rama y la carpeta del usuario no se mueven' $usuario (Estado-Git $e.Migrado)
  Igual '(g) el original queda como estaba' $original (Foto $e.Legacy)
  Comprueba 'el caso distinto no va, ni sus entradas ni su esperado' (-not (Test-Path -LiteralPath (Get-Ruta $e.Wt "$Esp/cargaJob/caso-02")) -and -not (Test-Path -LiteralPath (Get-Ruta $e.Wt "$Ent/cargaJob/caso-02"))) ''
  $t = Lee $e.Wt 'src/test/java/com/acme/nuevo/RegresionLocalTest.java'
  Comprueba 'RegresionLocalTest lleva el paquete del arnes, sin la marca de la plantilla' ($t.StartsWith('package com.acme.nuevo;') -and -not $t.Contains('{{')) $t.Substring(0, [Math]::Min(80, $t.Length))
  Comprueba 'y lleva @Tag("regresion") y su orden' ($t.Contains('@Tag("regresion")') -and $t.Contains('@Order(Integer.MAX_VALUE)')) ''
  Comprueba 'junit-platform.properties pone a las clases con @Order por su numero' ((Lee $e.Wt 'src/test/resources/junit-platform.properties') -match '(?m)^junit\.jupiter\.testclass\.order\.default=org\.junit\.jupiter\.api\.ClassOrderer\$OrderAnnotation\s*$') ''
  Igual 'el arnes del migrado es el guardado' (Lee $e.Local 'arnes/migrado/src/test/java/com/acme/nuevo/PruebaLocalTest.java') (Lee $e.Wt 'src/test/java/com/acme/nuevo/PruebaLocalTest.java')
  foreach ($c in @('cargaJob/caso-01', 'remesaJob/caso-01')) {
    Igual "el esperado de $c es la salida del original (el fichero)" (Lee $e.Local "salidas/original/$c/ficheros/salida/resultado.txt") (Lee $e.Wt "$Esp/$c/ficheros/salida/resultado.txt")
    Igual "y su estado.txt" (Lee $e.Local "salidas/original/$c/estado.txt") (Lee $e.Wt "$Esp/$c/estado.txt")
    Igual "las entradas de $c son las que usa el arnes" (Lee $e.Local "casos/$c/ficheros/entrada/datos.txt") (Lee $e.Wt "$Ent/$c/ficheros/entrada/datos.txt")
  }
  Igual 'la tabla del esperado, la del original' (Lee $e.Local 'salidas/original/cargaJob/caso-01/tablas/DATOS.csv') (Lee $e.Wt "$Esp/cargaJob/caso-01/tablas/DATOS.csv")
  Igual 'y el sql de las entradas' (Lee $e.Local 'casos/cargaJob/caso-01/datos.sql') (Lee $e.Wt "$Ent/cargaJob/caso-01/datos.sql")
  $j = Lee-Json $e.Regresion
  Igual 'regresion.json: el commit' (GitEn $e.Wt @('rev-parse', 'HEAD')) $j.commit
  Igual 'la rama' 'rescate/main-1' $j.rama
  Igual 'los casos puestos' 'cargaJob/caso-01,remesaJob/caso-01' ((@($j.casos | ForEach-Object { "$($_.job)/$($_.caso)" })) -join ',')
  Igual 'ninguno quitado' 0 @($j.quitados).Count
  Comprueba 'la consola dice cuantos casos, de cuantos jobs, en que rama y con que commit, y que no quita ninguno' ($r.Salida -match ('Regresion: 2 casos de 2 jobs quedan como tests en rescate/main-1 \(' + (Corto $j.commit) + '\)\. Quitados: 0\.')) (Cola $r.Salida)
}

$Pruebas['m33 (b) el esperado no lleva las tablas BATCH_ ni TASK_, aunque estan en la salida del original; las demas tablas, si'] = {
  $e = Escenario-M33 'm33-b' ([ordered]@{ cargaJob = @('importe=10.00 | SQL importe=7.00') })
  $r = Prueba $e @('-Regresion') '' 'estable,framework'
  Igual 'sale con 0' 0 $r.Codigo
  Comprueba 'la salida del original tiene las tablas del framework (si no, esta prueba no prueba nada)' ((Test-Path -LiteralPath (Get-Ruta $e.Local 'salidas/original/cargaJob/caso-01/tablas/BATCH_JOB_INSTANCE.csv')) -and (Test-Path -LiteralPath (Get-Ruta $e.Local 'salidas/migrado/cargaJob/caso-01/tablas/TASK_EXECUTION.csv'))) ''
  Igual 'el caso sale igual' 'igual' (Caso $e 'cargaJob' 'caso-01').resultado
  $f = @((Ficheros-Del-Commit $e.Wt) -split '\|')
  Comprueba 'el commit lleva el esperado de la tabla del batch' ($f -contains "$Esp/cargaJob/caso-01/tablas/DATOS.csv") ($f -join ' ')
  Igual 'pero ningun BATCH_*.csv ni TASK_*.csv' 0 @($f | Where-Object { $_ -match '/tablas/(BATCH|TASK)_' }).Count
  Igual 'ni en el arbol de la rama' 0 @((GitEn $e.Wt @('ls-files')) -split "`n" | Where-Object { $_ -match '/tablas/(BATCH|TASK)_' }).Count
}

$Pruebas['m33 (c) sensibilidad: si el Maven (sordo) no falla con un byte cambiado, no se commitea nada y el motivo lo dice'] = {
  $e = Escenario-M33 'm33-c' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $antes = Estado-Git $e.Wt
  $r = Prueba $e @('-Regresion') '' 'estable,sordo'
  Igual 'sale con 0 (los casos salen iguales)' 0 $r.Codigo
  Igual 'la rama de rescate no se mueve' $antes (Estado-Git $e.Wt)
  Comprueba 'la consola dice que no es sensible y no da ningun commit' ($r.Salida -match 'no es sensible' -and $r.Salida -notmatch 'quedan como tests') (Cola $r.Salida)
  $j = Lee-Json $e.Regresion
  Igual 'regresion.json: sin commit' '' $j.commit
  Comprueba 'con el motivo' ($j.motivo -match 'no es sensible') $j.motivo
  Igual 'ni casos puestos' 0 @($j.casos).Count
}

$Pruebas['m33 (d) un caso que falla en la copia (el estado static de la JVM pasa de un caso al siguiente) se quita, el resto se commitea y regresion.json lo cuenta'] = {
  $e = Escenario-M33 'm33-d' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00', 'importe=30.00') }) 'minimo=5.00' "minimo=5.00`nestatico=si"
  $r = Prueba $e @('-Regresion')
  Igual 'sale con 0 (cada caso va en su Maven y sale igual)' 0 $r.Codigo
  Igual 'los tres casos salen iguales' 'igual,igual,igual' ((@((Lee-Json $e.Json).casos | ForEach-Object { $_.resultado })) -join ',')
  $j = Lee-Json $e.Regresion
  Igual 'se pone el primero' 'cargaJob/caso-01' ((@($j.casos | ForEach-Object { "$($_.job)/$($_.caso)" })) -join ',')
  Igual 'se quitan el segundo y el tercero' 'cargaJob/caso-02,cargaJob/caso-03' ((@($j.quitados | ForEach-Object { "$($_.job)/$($_.caso)" })) -join ',')
  Comprueba 'con su motivo: el fichero y la linea que sale distinta' ($j.quitados[0].motivo -match 'ficheros/salida/resultado\.txt: linea \d+' -and $j.quitados[0].motivo -match 'arrastra') $j.quitados[0].motivo
  Comprueba 'hay un commit, con un caso' ($j.commit -and (GitEn $e.Wt @('log', '-1', '--format=%s')) -eq 'test(regresion): casos de la prueba en local como tests (1 casos, 1 jobs)') (GitEn $e.Wt @('log', '-1', '--format=%s'))
  Comprueba 'el arbol lleva el caso 1 y no el 2 ni el 3' ((Test-Path -LiteralPath (Get-Ruta $e.Wt "$Esp/cargaJob/caso-01/estado.txt")) -and -not (Test-Path -LiteralPath (Get-Ruta $e.Wt "$Esp/cargaJob/caso-02")) -and -not (Test-Path -LiteralPath (Get-Ruta $e.Wt "$Ent/cargaJob/caso-03"))) ''
  Comprueba 'la consola cuenta los quitados' ($r.Salida -match 'Quitados: 2\.') (Cola $r.Salida)
  Igual 'la carpeta de la rama de rescate queda limpia' '' (GitEn $e.Wt @('status', '--porcelain'))
}

$Pruebas['m33 (e) sin casos iguales: no hay commit y sale la linea'] = {
  $e = Escenario-M33 'm33-e' ([ordered]@{ cargaJob = @('importe=5.00') }) 'minimo=5.00' 'minimo=5.01'
  $antes = Estado-Git $e.Wt
  $r = Prueba $e @('-Regresion')
  Igual 'sale con 2 (el unico caso es distinto)' 2 $r.Codigo
  Igual 'la rama de rescate no se mueve' $antes (Estado-Git $e.Wt)
  Comprueba 'la consola dice que ningun caso sale igual' ($r.Salida -match 'Regresion: ningun caso sale igual.*no se commitea nada') (Cola $r.Salida)
  $j = Lee-Json $e.Regresion
  Comprueba 'regresion.json existe, sin commit y con el motivo' ($j -and $j.commit -eq '' -and $j.motivo -match 'ningun caso sale igual') (Get-Content -LiteralPath $e.Regresion -Raw -ErrorAction SilentlyContinue)
}

$Pruebas['m33 (n) lanzarlo dos veces: la segunda no hace otro commit y lo dice; los casos siguen en regresion.json'] = {
  $e = Escenario-M33 'm33-n' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba $e @('-Regresion')
  Igual 'la primera sale con 0' 0 $r.Codigo
  $primero = GitEn $e.Wt @('rev-parse', 'HEAD')
  $r = Prueba $e @('-Regresion')
  Igual 'la segunda sale con 0' 0 $r.Codigo
  Igual 'la rama de rescate no se mueve' $primero (GitEn $e.Wt @('rev-parse', 'HEAD'))
  Comprueba 'la consola dice que ya estaban, sin cambios' ($r.Salida -match 'Regresion: 2 casos de 1 jobs ya estaban como tests en rescate/main-1 \(' + (Corto $primero) + '\), sin cambios: no hay commit nuevo\. Quitados: 0\.') (Cola $r.Salida)
  $j = Lee-Json $e.Regresion
  Igual 'regresion.json sigue con el commit que tiene los tests' $primero $j.commit
  Igual 'y con los dos casos' 'cargaJob/caso-01,cargaJob/caso-02' ((@($j.casos | ForEach-Object { "$($_.job)/$($_.caso)" })) -join ',')
  Igual 'la carpeta de la rama de rescate queda limpia' '' (GitEn $e.Wt @('status', '--porcelain'))
}

$Pruebas['m33 (f) sin -Regresion no cambia nada: ni commit ni regresion.json'] = {
  $e = Escenario-M33 'm33-f' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $antes = Estado-Git $e.Wt
  $r = Prueba $e
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'la rama de rescate no se mueve' $antes (Estado-Git $e.Wt)
  Comprueba 'no hay regresion.json' (-not (Test-Path -LiteralPath $e.Regresion)) ''
  Comprueba 'y la consola no habla de regresion' ($r.Salida -notmatch 'Regresion') (Cola $r.Salida)
  Comprueba 'la copia de la regresion no se ha creado' (-not (Test-Path -LiteralPath ($e.Migrado + '-regresion'))) ''
}

# ======================== LA PLANTILLA DE JAVA (h) ========================
# El javac de esta maquina: el del PATH o, si el java trae el modulo jdk.compiler, 'java -m jdk.compiler/com.sun.tools.javac.Main'. Vacio si no hay.
function Get-Javac {
  $c = Get-Command javac -ErrorAction SilentlyContinue
  if ($c) { return @($c.Source) }
  $j = Get-Command java -ErrorAction SilentlyContinue
  if ($j -and @(& $j.Source --list-modules 2>$null | Where-Object { "$_" -match '^jdk\.compiler' }).Count -gt 0) { return @($j.Source, '-m', 'jdk.compiler/com.sun.tools.javac.Main') }
  return @()
}

# Un JUnit 5 de mentira, lo justo para RegresionLocalTest: las anotaciones Test, Tag y Order, Assertions.fail y un Runner que ejecuta los @Test de una clase.
function Escribe-JUnit-Falso([string]$Raiz) {
  $api = 'org/junit/jupiter/api'
  Escribe $Raiz "$api/Test.java" "package org.junit.jupiter.api;`nimport java.lang.annotation.*;`n@Retention(RetentionPolicy.RUNTIME) @Target(ElementType.METHOD)`npublic @interface Test {}`n"
  Escribe $Raiz "$api/Tag.java" "package org.junit.jupiter.api;`nimport java.lang.annotation.*;`n@Retention(RetentionPolicy.RUNTIME) @Target({ElementType.TYPE, ElementType.METHOD})`npublic @interface Tag { String value(); }`n"
  Escribe $Raiz "$api/Order.java" "package org.junit.jupiter.api;`nimport java.lang.annotation.*;`n@Retention(RetentionPolicy.RUNTIME) @Target({ElementType.TYPE, ElementType.METHOD})`npublic @interface Order { int value(); }`n"
  Escribe $Raiz "$api/Assertions.java" "package org.junit.jupiter.api;`npublic class Assertions { public static void fail(String m) { throw new AssertionError(m); } }`n"
  Escribe $Raiz 'Runner.java' ("public class Runner {`n  public static void main(String[] a) throws Exception {`n    Class<?> c = Class.forName(a[0]);`n    java.lang.reflect.Constructor<?> k = c.getDeclaredConstructor();`n    k.setAccessible(true);`n    Object o = k.newInstance();`n    int rc = 0;`n" +
    "    for (java.lang.reflect.Method m : c.getDeclaredMethods()) {`n      if (!m.isAnnotationPresent(org.junit.jupiter.api.Test.class)) continue;`n      m.setAccessible(true);`n      try { m.invoke(o); System.out.println(`"PASA `" + m.getName()); }`n      catch (java.lang.reflect.InvocationTargetException e) { System.out.println(`"FALLA `" + e.getCause().getMessage()); rc = 1; }`n    }`n    System.exit(rc);`n  }`n}`n")
}

# Un proyecto de juguete para el Runner: lo esperado y lo que sale, ficheros ($Esperado y $Sale: ruta relativa -> texto).
function Escribe-Proyecto([string]$Raiz, [hashtable]$Esperado, [hashtable]$Sale) {
  if (Test-Path -LiteralPath $Raiz) { Remove-Item -LiteralPath $Raiz -Recurse -Force }
  [void](New-Item -ItemType Directory -Path $Raiz -Force)
  foreach ($k in $Esperado.Keys) { Escribe $Raiz ('src/test/resources/prueba-local-esperado/' + $k) $Esperado[$k] }
  foreach ($k in $Sale.Keys) { Escribe $Raiz ('target/prueba-local/' + $k) $Sale[$k] }
}

# Ejecuta el Runner sobre RegresionLocalTest en el proyecto $Proy. Devuelve el codigo, lo que escribe y el contenido de target/regresion-fallos.txt.
function Corre-Runner([string]$Java, [string]$Clases, [string]$Proy, [string]$Clase) {
  Push-Location -LiteralPath $Proy
  try {
    $ErrorActionPreference = 'Continue'
    $o = & $Java -cp $Clases Runner $Clase 2>&1 | ForEach-Object { "$_" }
    $c = $LASTEXITCODE
  }
  finally { Pop-Location }
  $f = Join-Path $Proy 'target/regresion-fallos.txt'
  $fallos = ''
  if (Test-Path -LiteralPath $f) { $fallos = [System.IO.File]::ReadAllText($f) }
  return [pscustomobject]@{ Codigo = $c; Salida = (@($o) -join "`n"); Fallos = $fallos }
}

$Pruebas['m33 (h) la plantilla compila en Java 17 contra un JUnit 5 falso, con y sin paquete; y su comparacion es la de la prueba en local (se salta si no hay javac)'] = {
  $javac = @(Get-Javac)
  if ($javac.Count -eq 0) { Write-Host '  se salta: en esta maquina no hay javac ni el modulo jdk.compiler del java'; return }
  $base = Join-Path $Dir 'm33-h'
  if (Test-Path -LiteralPath $base) { Remove-Item -LiteralPath $base -Recurse -Force }
  $falso = Join-Path $base 'junit-falso'
  Escribe-JUnit-Falso $falso
  $plantilla = [System.IO.File]::ReadAllText((Join-Path (Join-Path $raiz 'regresion') 'RegresionLocalTest.java.txt'), [System.Text.Encoding]::UTF8)
  $bytes = [System.IO.File]::ReadAllBytes((Join-Path (Join-Path $raiz 'regresion') 'RegresionLocalTest.java.txt'))
  Comprueba 'la plantilla no lleva BOM' (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) ''
  Comprueba 'ni nada fuera de ASCII (compila con la codificacion de cada equipo)' ($plantilla -notmatch '[^\x00-\x7F]') ''
  foreach ($paquete in @('com.acme.nuevo', '')) {
    $nombre = 'con-paquete'
    if (-not $paquete) { $nombre = 'sin-paquete' }
    $fuente = Join-Path $base "fuente-$nombre"
    $decl = ''
    if ($paquete) { $decl = "package $paquete;" }
    Escribe $fuente 'RegresionLocalTest.java' ($plantilla.Replace('package {{PAQUETE}};', $decl))
    $salida = Join-Path $base "clases-$nombre"
    [void](New-Item -ItemType Directory -Path $salida -Force)
    $fuentes = @((Join-Path $fuente 'RegresionLocalTest.java')) + @(Get-ChildItem -LiteralPath $falso -Recurse -File -Filter '*.java' | ForEach-Object { $_.FullName })
    $ErrorActionPreference = 'Continue'
    $o = & $javac[0] @($javac | Select-Object -Skip 1) --release 17 -Xlint:all -d $salida @fuentes 2>&1 | ForEach-Object { "$_" }
    $c = $LASTEXITCODE
    # un java sin lib/ct.sym (el modulo jdk.compiler suelto) no sabe de --release: se compila con -source y -target, que no comprueban la API
    if ($c -ne 0 -and ($o -join ' ') -match 'release version 17 not supported') {
      $o = & $javac[0] @($javac | Select-Object -Skip 1) -source 17 -target 17 -Xlint:all,-options -d $salida @fuentes 2>&1 | ForEach-Object { "$_" }
      $c = $LASTEXITCODE
    }
    $ErrorActionPreference = 'Stop'
    Igual "compila ($nombre, --release 17)" 0 $c
    Comprueba "sin avisos de javac ($nombre)" (@($o | Where-Object { $_ }).Count -eq 0) (@($o) -join ' / ')
  }
  # Lo que hace: con el Runner sobre la clase compilada con paquete
  $clases = Join-Path $base 'clases-con-paquete'
  $java = (Get-Command java).Source
  $clase = 'com.acme.nuevo.RegresionLocalTest'
  $estado = "estado=COMPLETED`nsalida=COMPLETED`n"
  # 1. Lo mismo con otro orden de columnas y de filas, con CRLF, sin el ultimo salto y con tablas del framework distintas: pasa
  $p1 = Join-Path $base 'p1'
  Escribe-Proyecto $p1 @{
    'job1/caso-01/estado.txt' = $estado
    'job1/caso-01/tablas/T.csv' = "ID;NOMBRE;IMPORTE`n1;ana;10`n2;luis;20`n"
    'job1/caso-01/ficheros/salida/a.txt' = "uno`ndos`ntres`n"
  } @{
    'job1/caso-01/estado.txt' = $estado.Replace("`n", "`r`n")
    'job1/caso-01/tablas/T.csv' = "NOMBRE;IMPORTE;ID`nluis;20;2`nana;10;1`n"
    'job1/caso-01/tablas/BATCH_JOB_INSTANCE.csv' = "ID`n7`n"
    'job1/caso-01/tablas/TASK_EXECUTION.csv' = "ID`n9`n"
    'job1/caso-01/ficheros/salida/a.txt' = "uno`ndos`ntres"
  }
  $r = Corre-Runner $java $clases $p1 $clase
  Igual 'mismas filas con otro orden, CRLF, sin ultimo salto y tablas del framework distintas: pasa' 0 $r.Codigo
  Comprueba 'y no deja fichero de fallos' ($r.Fallos -eq '') $r.Fallos
  # 2. Un caso distinto en un fichero, uno sin salida, uno con un fichero de mas, uno con la tabla cambiada y uno con una fila rara: fallan, con job, caso, fichero y linea
  $p2 = Join-Path $base 'p2'
  Escribe-Proyecto $p2 @{
    'job1/caso-01/estado.txt' = $estado
    'job1/caso-02/ficheros/salida/a.txt' = "uno`ndos`ntres`n"
    'job1/caso-03/estado.txt' = $estado
    'job1/caso-04/estado.txt' = $estado
    'job1/caso-05/tablas/T.csv' = "ID;NOMBRE`n1;ana`n"
    'job2/caso-01/tablas/T.csv' = "ID;NOMBRE`n1;ana;x`n"
  } @{
    'job1/caso-01/estado.txt' = $estado
    'job1/caso-02/ficheros/salida/a.txt' = "uno`ndos`ntrex`n"
    'job1/caso-04/estado.txt' = $estado
    'job1/caso-04/extra.txt' = "de mas`n"
    'job1/caso-05/tablas/T.csv' = "ID;NOMBRE`n1;luis`n"
    'job2/caso-01/tablas/T.csv' = "NOMBRE;ID`nana;1;x`n"
  }
  $r = Corre-Runner $java $clases $p2 $clase
  Igual 'con diferencias falla' 1 $r.Codigo
  Comprueba 'el mensaje dice job, caso, fichero, linea y las dos lineas' ($r.Salida.Contains("job1/caso-02: ficheros/salida/a.txt: linea 3: esperado 'tres' y sale 'trex'")) $r.Salida
  Comprueba 'un caso sin salida lo dice' ($r.Salida.Contains('job1/caso-03: no hay salida en target/prueba-local/job1/caso-03')) $r.Salida
  Comprueba 'un fichero de mas lo dice' ($r.Salida.Contains('job1/caso-04: extra.txt: sobra, el original no lo deja')) $r.Salida
  Comprueba 'una tabla con un valor cambiado: la linea ya ordenada' ($r.Salida.Contains("job1/caso-05: tablas/T.csv: linea 2: esperado '1;ana' y sale '1;luis'")) $r.Salida
  Comprueba 'una fila con otros campos que la cabecera se compara tal cual (la cabecera, que ya difiere)' ($r.Salida.Contains("job2/caso-01: tablas/T.csv: linea 1: esperado 'ID;NOMBRE' y sale 'NOMBRE;ID'")) $r.Salida
  Comprueba 'el caso que sale igual no esta en el mensaje' (-not $r.Salida.Contains('job1/caso-01')) $r.Salida
  $lineas = @($r.Fallos -split "`n" | Where-Object { $_ })
  Igual 'target/regresion-fallos.txt: una linea por caso que falla' 5 $lineas.Count
  Igual 'con job, caso y mensaje separados por tabuladores' "job1`tcaso-02`tficheros/salida/a.txt: linea 3: esperado 'tres' y sale 'trex'" $lineas[0]
}

# ============================== EL ARRANQUE (l) Y LA AYUDA ==============================
$Pruebas['m33 (l) arranque: -Regresion sin worktree de rescate, o con la rama de rescate con cambios sin commit, no empieza y dice por que'] = {
  $e = Escenario-M33 'm33-l' ([ordered]@{ cargaJob = @('importe=10.00') })
  Escribe $e.Wt 'sucio.txt' "sin commit`n"
  $r = Prueba $e @('-Regresion')
  Igual 'con cambios sin commit sale con 1' 1 $r.Codigo
  Comprueba 'y dice que la carpeta tiene cambios sin commit' ($r.Salida -match 'cambios sin commit' -and $r.Salida -match '-Regresion') (Cola $r.Salida)
  Comprueba 'sin haber llamado a Copilot ni a Maven' (-not (Test-Path -LiteralPath $e.Llamadas)) ''
  Remove-Item -LiteralPath (Join-Path $e.Wt 'sucio.txt')
  [void](GitEn $e.Migrado @('worktree', 'remove', '--force', $e.Wt))
  $r = Prueba $e @('-Regresion')
  Igual 'sin worktree de rescate sale con 1' 1 $r.Codigo
  Comprueba 'y dice que -Regresion lo necesita' ($r.Salida -match '-Regresion necesita el worktree de rescate') (Cola $r.Salida)
  $r = Prueba $e
  Comprueba 'sin -Regresion, el mismo escenario no se queja del worktree' ($r.Salida -notmatch '-Regresion') (Cola $r.Salida)
}

$Pruebas['m33 (m) la ayuda de prueba-local.ps1 explica -Regresion (cabecera y uso) y el script carga regresion.ps1'] = {
  $t = [System.IO.File]::ReadAllText($Script)
  $cabecera = $t.Substring(0, $t.IndexOf('#>'))
  Comprueba 'la cabecera lleva el paso de -Regresion' ($cabecera -match '8\. Solo con -Regresion') ''
  Comprueba 'y la linea de uso' ($cabecera -match '(?m)^  \.\\prueba-local\.ps1 \.\.\. -Regresion ') ''
  Comprueba 'el switch esta en el param' ($t -match '\[switch\]\$Regresion') ''
  Comprueba 'regresion.ps1 se carga con . (Join-Path $PSScriptRoot ...)' ($t -match "\. \(Join-Path \`$PSScriptRoot 'regresion\.ps1'\)") ''
  $r = [System.IO.File]::ReadAllText((Join-Path (Split-Path -Parent $Script) 'regresion.ps1'))
  $codigo = $r.Substring($r.IndexOf("`n#>") + 3)
  Comprueba 'y regresion.ps1 solo lleva funciones (nada se ejecuta al cargarlo)' (@($codigo -split "`r?`n" | Where-Object { $_ -match '^[^\s#}]' -and $_ -notmatch '^function ' }).Count -eq 0) ''
}

# ================================ LANZADOR ================================
Invoke-Banco $Pruebas 'tests/probar-regresion.ps1'
