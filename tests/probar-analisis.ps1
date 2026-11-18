<#
probar-analisis.ps1 - Banco de pruebas de analisis.ps1 (SpotBugs con fb-contrib y PMD sin servidor).
No necesita Maven ni Java: usa el Maven de mentira tests/falsos/analisis-mvn.ps1, que deja los XML reales de
tests/datos/analisis (los que dejaron SpotBugs 4.10.5 con fb-contrib 7.7.4 y PMD 7.17 sobre tests/datos/analisis/juguete).
Nunca llama al Maven real. Vale para Windows PowerShell 5.1 y para PowerShell 7. Solo ASCII a proposito.

  .\tests\probar-analisis.ps1                       # todas las pruebas
  .\tests\probar-analisis.ps1 -Solo tope            # las que llevan 'tope' en el nombre
  .\tests\probar-analisis.ps1 -Dir D:\tmp\x -Conservar

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
$datos = Join-Path (Join-Path $aqui 'datos') 'analisis'
. (Join-Path $aqui 'comun-banco.ps1')
. (Join-Path $raiz 'comun.ps1')
. (Join-Path $raiz 'analisis.ps1')

# ============================== UTILIDADES ==============================
# Un repo de juguete (sin git) con dos fuentes en src/main/java y un pom que nadie debe tocar.
function Nuevo-Repo([string]$Nombre) {
  $r = Join-Path $Dir $Nombre
  if (Test-Path -LiteralPath $r) { Remove-Item -LiteralPath $r -Recurse -Force }
  Escribe $r 'pom.xml' "<project><modelVersion>4.0.0</modelVersion><groupId>com.acme</groupId><artifactId>demo</artifactId><version>1</version></project>`n"
  Escribe $r 'src/main/java/com/acme/demo/Totales.java' "package com.acme.demo;`npublic class Totales { }`n"
  Escribe $r 'src/main/java/com/acme/demo/Clasificador.java' "package com.acme.demo;`npublic class Clasificador { }`n"
  return $r
}

# Corre $Bloque con el Maven falso de analisis (Cfg.MvnExe) y las variables de entorno de $Vars; al salir deja todo como estaba.
function Con-Falso([hashtable]$Vars, [scriptblock]$Bloque) {
  $mvnAntes = $Cfg.MvnExe
  $minAntes = $Cfg.MinutosMaven
  $latAntes = $Cfg.SegundosLatido
  $Cfg.MvnExe = (Join-Path $falsos 'analisis-mvn.ps1')
  $Cfg.SegundosLatido = 0
  $ant = @{}
  foreach ($k in $Vars.Keys) { $ant[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $Vars[$k]) }
  try { return (& $Bloque) }
  finally {
    foreach ($k in $Vars.Keys) { [Environment]::SetEnvironmentVariable($k, $ant[$k]) }
    $Cfg.MvnExe = $mvnAntes
    $Cfg.MinutosMaven = $minAntes
    $Cfg.SegundosLatido = $latAntes
  }
}

# Lo que dejo el Maven falso: una linea por llamada ('<carpeta>|<argumentos>').
function Llamadas-De([string]$Fichero) {
  if (-not (Test-Path -LiteralPath $Fichero)) { return @() }
  return @([System.IO.File]::ReadAllLines($Fichero) | Where-Object { $_ })
}

# Un hallazgo a mano para probar Compare-Analisis.
function Nuevo-Hallazgo([string]$Herramienta, [string]$Regla, [string]$Fichero, [string]$Metodo, [int]$Linea, [string]$Clase = '') {
  return @{ Herramienta = $Herramienta; Regla = $Regla; Fichero = $Fichero; Linea = $Linea; Metodo = $Metodo; Clase = $Clase; Mensaje = "$Regla en $Fichero" }
}

function Busca($Hallazgos, [string]$Herramienta, [string]$Regla) {
  return , @($Hallazgos | Where-Object { $_.Herramienta -ceq $Herramienta -and $_.Regla -ceq $Regla })
}

# Lo que se espera de los cuatro problemas conocidos del juguete (el reboxing y el campo local los dice SpotBugs; la complejidad y el campo sin uso, PMD).
function Comprueba-Cuatro([string]$Que, $H) {
  $tot = 'src/main/java/com/acme/demo/Totales.java'
  $cla = 'src/main/java/com/acme/demo/Clasificador.java'
  $b = Busca $H 'spotbugs' 'BX_UNBOXING_IMMEDIATELY_REBOXED'
  Igual "$Que`: reboxing, uno" 1 $b.Count
  Igual "$Que`: reboxing, fichero" $tot $b[0].Fichero
  Igual "$Que`: reboxing, metodo" 'copiar' $b[0].Metodo
  Igual "$Que`: reboxing, linea" 10 $b[0].Linea
  Igual "$Que`: reboxing, mensaje (el largo, como en Sonar)" 'Boxed value is unboxed and then immediately reboxed in com.acme.demo.Totales.copiar(Integer)' $b[0].Mensaje
  $f = Busca $H 'spotbugs' 'FCBL_FIELD_COULD_BE_LOCAL'
  Igual "$Que`: campo que solo se usa como local, dos (uno por clase)" 2 $f.Count
  $ft = @($f | Where-Object { $_.Fichero -ceq $tot })
  Igual "$Que`: campo local de Totales, uno" 1 $ft.Count
  Igual "$Que`: campo local, sin metodo y con su clase" 'com.acme.demo.Totales' $ft[0].Clase
  Igual "$Que`: campo local, metodo vacio" '' $ft[0].Metodo
  Igual "$Que`: campo local, mensaje" 'The acumulado field in class com.acme.demo.Totales is used only as a local, but defined on class level' $ft[0].Mensaje
  Igual "$Que`: campo local, linea" 15 $ft[0].Linea
  $c = Busca $H 'pmd' 'CognitiveComplexity'
  Igual "$Que`: complejidad cognitiva, una" 1 $c.Count
  Igual "$Que`: complejidad cognitiva, fichero" $cla $c[0].Fichero
  Igual "$Que`: complejidad cognitiva, metodo" 'clasificar' $c[0].Metodo
  Igual "$Que`: complejidad cognitiva, linea" 12 $c[0].Linea
  Comprueba "$Que`: complejidad cognitiva, mensaje con el 20" ($c[0].Mensaje -ceq "The method 'clasificar(List<List<Integer>>, int)' has a cognitive complexity of 20, current threshold is 16") $c[0].Mensaje
  $u = Busca $H 'pmd' 'UnusedPrivateField'
  Igual "$Que`: campo privado sin uso, uno" 1 $u.Count
  Igual "$Que`: campo privado sin uso, fichero" $cla $u[0].Fichero
  Igual "$Que`: campo privado sin uso, metodo vacio y su clase" 'com.acme.demo.Clasificador' $u[0].Clase
  Igual "$Que`: campo privado sin uso, mensaje" "Avoid unused private fields such as 'sinUso'." $u[0].Mensaje
  Igual "$Que`: campo privado sin uso, linea" 9 $u[0].Linea
  $mal = @($H | Where-Object { $_.Fichero -match '^(/|[A-Za-z]:|\.)' -or $_.Fichero -match '\\' })
  Igual "$Que`: todas las rutas son relativas y con /" 0 $mal.Count
}

# ================================ PRUEBAS ================================
$Pruebas = [ordered]@{}

$Pruebas['1 a) Read-SpotbugsXml y Read-PmdXml: los cuatro problemas del XML real, con fichero, metodo y mensaje'] = {
  $sb = @(Read-SpotbugsXml (Join-Path $datos 'spotbugsXml.xml') '/repo')
  $pm = @(Read-PmdXml (Join-Path $datos 'pmd.xml') '/repo')
  Igual 'SpotBugs: los 7 hallazgos del XML' 7 $sb.Count
  Igual 'PMD: los 2 del XML (la complejidad ciclomatica de 10 no pasa del umbral de Sonar)' 2 $pm.Count
  Igual 'SpotBugs: la herramienta' 7 @($sb | Where-Object { $_.Herramienta -ceq 'spotbugs' }).Count
  Igual 'PMD: la herramienta' 2 @($pm | Where-Object { $_.Herramienta -ceq 'pmd' }).Count
  Comprueba-Cuatro 'los dos juntos' (@($sb) + @($pm))
  Comprueba 'SpotBugs trae las claves de fb-contrib y las del nucleo' ((Busca $sb 'spotbugs' 'OCP_OVERLY_CONCRETE_PARAMETER').Count -eq 1 -and (Busca $sb 'spotbugs' 'URF_UNREAD_FIELD').Count -eq 1)
  # la misma lectura con rutas de Windows en los XML
  $xs = [System.IO.File]::ReadAllText((Join-Path $datos 'spotbugsXml.xml')).Replace('<SrcDir>/repo/src/main/java', '<SrcDir>C:\work\acme\src\main\java').Replace('<SrcDir>/repo/target/generated-sources/annotations', '<SrcDir>C:\work\acme\target\generated-sources\annotations')
  $xp = [System.IO.File]::ReadAllText((Join-Path $datos 'pmd.xml')).Replace('"/repo/src/main/java/com/acme/demo/Clasificador.java"', '"C:\work\acme\src\main\java\com\acme\demo\Clasificador.java"')
  Escribe $Dir 'win/spotbugsXml.xml' $xs
  Escribe $Dir 'win/pmd.xml' $xp
  $w = @(Read-SpotbugsXml (Get-Ruta $Dir 'win/spotbugsXml.xml') 'C:\work\acme') + @(Read-PmdXml (Get-Ruta $Dir 'win/pmd.xml') 'C:\work\acme\')
  Comprueba-Cuatro 'con rutas de Windows' $w
}

$Pruebas['2 b) Compare-Analisis: no mira la linea, mira el metodo y cuenta repetidos'] = {
  $a = Nuevo-Hallazgo 'spotbugs' 'BX_UNBOXING_IMMEDIATELY_REBOXED' 'src/main/java/A.java' 'copiar' 10
  $aMovido = Nuevo-Hallazgo 'spotbugs' 'BX_UNBOXING_IMMEDIATELY_REBOXED' 'src/main/java/A.java' 'copiar' 42
  $r = Compare-Analisis @($a) @($aMovido)
  Igual 'un hallazgo que cambia de linea: ningun nuevo' 0 @($r.Nuevos).Count
  Igual 'un hallazgo que cambia de linea: ningun resuelto' 0 @($r.Resueltos).Count
  $otro = Nuevo-Hallazgo 'spotbugs' 'BX_UNBOXING_IMMEDIATELY_REBOXED' 'src/main/java/A.java' 'duplicar' 10
  $r = Compare-Analisis @($a) @($otro)
  Igual 'el mismo fallo en otro metodo: uno nuevo' 1 @($r.Nuevos).Count
  Igual 'el mismo fallo en otro metodo: el nuevo es el de duplicar' 'duplicar' @($r.Nuevos)[0].Metodo
  Igual 'el mismo fallo en otro metodo: uno resuelto' 1 @($r.Resueltos).Count
  Igual 'el mismo fallo en otro metodo: el resuelto es el de copiar' 'copiar' @($r.Resueltos)[0].Metodo
  $r = Compare-Analisis @($a, $aMovido) @($a)
  Igual 'dos iguales antes y uno despues: ninguno nuevo' 0 @($r.Nuevos).Count
  Igual 'dos iguales antes y uno despues: uno resuelto' 1 @($r.Resueltos).Count
  $r = Compare-Analisis @($a) @($a, $aMovido)
  Igual 'uno antes y dos iguales despues: uno nuevo' 1 @($r.Nuevos).Count
  Igual 'uno antes y dos iguales despues: ninguno resuelto' 0 @($r.Resueltos).Count
  # sin metodo manda la clase
  $c1 = Nuevo-Hallazgo 'pmd' 'UnusedPrivateField' 'src/main/java/A.java' '' 9 'com.acme.A'
  $c2 = Nuevo-Hallazgo 'pmd' 'UnusedPrivateField' 'src/main/java/A.java' '' 9 'com.acme.A$Interna'
  $r = Compare-Analisis @($c1) @($c1, $c2)
  Igual 'sin metodo, otra clase del mismo fichero: uno nuevo' 1 @($r.Nuevos).Count
  Igual 'sin metodo, la misma clase en otra linea: no es nuevo' 0 @((Compare-Analisis @($c1) @((Nuevo-Hallazgo 'pmd' 'UnusedPrivateField' 'src/main/java/A.java' '' 30 'com.acme.A'))).Nuevos).Count
  # herramienta, regla y fichero separan
  $p = Nuevo-Hallazgo 'pmd' 'BX_UNBOXING_IMMEDIATELY_REBOXED' 'src/main/java/A.java' 'copiar' 10
  Igual 'otra herramienta con la misma regla: es otro hallazgo' 1 @((Compare-Analisis @($a) @($a, $p)).Nuevos).Count
  $b = Nuevo-Hallazgo 'spotbugs' 'BX_UNBOXING_IMMEDIATELY_REBOXED' 'src/main/java/B.java' 'copiar' 10
  Igual 'otro fichero con el mismo fallo: es otro hallazgo' 1 @((Compare-Analisis @($a) @($a, $b)).Nuevos).Count
  Igual 'otra regla en el mismo metodo: es otro hallazgo' 1 @((Compare-Analisis @($a) @($a, (Nuevo-Hallazgo 'spotbugs' 'NAB_NEEDLESS_AUTOBOXING_VALUEOF' 'src/main/java/A.java' 'copiar' 10))).Nuevos).Count
  # vacios
  $r = Compare-Analisis @() @()
  Igual 'vacios: nada nuevo ni resuelto' 0 (@($r.Nuevos).Count + @($r.Resueltos).Count)
  $r = Compare-Analisis $null @($a)
  Igual 'antes nulo: uno nuevo' 1 @($r.Nuevos).Count
  $r = Compare-Analisis @($a) $null
  Igual 'despues nulo: uno resuelto' 1 @($r.Resueltos).Count
}

$Pruebas['3 c) Invoke-Analisis con un Maven falso que deja los XML: ok y los hallazgos, sin tocar el pom'] = {
  $repo = Nuevo-Repo 'ok'
  $pom = Lee $repo 'pom.xml'
  $log = Join-Path $Dir 'ok-llamadas.txt'
  $r = Con-Falso @{ RESCATE_ANALISIS_LLAMADAS = $log } { Invoke-Analisis $repo }
  Igual 'Estado' 'ok' $r.Estado
  Igual 'los 9 hallazgos: 7 de SpotBugs y 2 de PMD' 9 @($r.Hallazgos).Count
  Comprueba-Cuatro 'Invoke-Analisis' @($r.Hallazgos)
  Igual 'el pom del repo queda igual' $pom (Lee $repo 'pom.xml')
  $l = Llamadas-De $log
  Igual 'dos llamadas a Maven: SpotBugs y PMD' 2 $l.Count
  $sb = "$($l[0])"
  Comprueba 'primera: compila, copia fb-contrib y lanza SpotBugs por coordenadas' ($sb -match ' compile ' -and $sb.Contains('org.apache.maven.plugins:maven-dependency-plugin:3.8.1:copy') -and $sb.Contains('-Dartifact=com.mebigfatguy.fb-contrib:fb-contrib:7.7.4') -and $sb.Contains('com.github.spotbugs:spotbugs-maven-plugin:4.10.5.0:spotbugs')) $sb
  Comprueba 'primera: pide el XML, pasa fb-contrib y no falla por los hallazgos' ($sb.Contains('-Dspotbugs.xmlOutput=true') -and $sb -match '-Dspotbugs\.pluginList=\S*fb-contrib-7\.7\.4\.jar' -and $sb.Contains('-Dspotbugs.failOnError=false')) $sb
  $pm = "$($l[1])"
  Comprueba 'segunda: PMD por coordenadas con el pom auxiliar, el ruleset y el repo' ($pm.Contains('org.apache.maven.plugins:maven-pmd-plugin:3.28.0:pmd') -and $pm -match '-f \S*pom-pmd\.xml' -and $pm -match '-Danalisis\.ruleset=\S*pmd-sonar\.xml' -and $pm.Contains('-Danalisis.repo=' + $repo)) $pm
  Comprueba 'ninguna llamada pide filtro si no se dan ficheros' (-not ($sb + $pm).Contains('onlyAnalyze') -and -not ($sb + $pm).Contains('analisis.includes')) ($sb + ' // ' + $pm)
  Comprueba 'los registros de Maven quedan en target/analisis' ((Test-Path -LiteralPath (Get-Ruta $repo 'target/analisis/spotbugs.log')) -and (Test-Path -LiteralPath (Get-Ruta $repo 'target/analisis/pmd.log')))
  # una segunda pasada no se mezcla con XML viejos: si Maven no deja nada, no se lee lo de antes
  $r2 = Con-Falso @{ RESCATE_ANALISIS_SIN_XML = '1' } { Invoke-Analisis $repo }
  Comprueba 'sin XML nuevo no se lee el viejo' ($r2.Estado -like 'no disponible: *') $r2.Estado
}

$Pruebas['4 d) Invoke-Analisis cuando Maven falla: no disponible con su motivo y sin excepcion'] = {
  $repo = Nuevo-Repo 'falla'
  $texto = 'Plugin com.github.spotbugs:spotbugs-maven-plugin:4.10.5.0 or one of its dependencies could not be resolved: Could not transfer artifact com.github.spotbugs:spotbugs-maven-plugin:pom:4.10.5.0 from/to central (https://repo.maven.apache.org/maven2): Connect to repo.maven.apache.org failed'
  $lanza = $false
  $r = $null
  try { $r = Con-Falso @{ RESCATE_ANALISIS_ERROR = $texto } { Invoke-Analisis $repo } } catch { $lanza = $true }
  Igual 'no lanza excepcion' $false $lanza
  Igual 'Estado: el plugin no se descarga' 'no disponible: no se descarga el plugin' $r.Estado
  Igual 'sin hallazgos' 0 @($r.Hallazgos).Count
  Comprueba 'el detalle trae el primer error de Maven' ("$($r.Detalle)".Contains('could not be resolved')) "$($r.Detalle)"
  $r = Con-Falso @{ RESCATE_ANALISIS_ERROR = 'The goal exploto por algo raro' } { Invoke-Analisis $repo }
  Igual 'Estado: un error cualquiera de Maven' 'no disponible: Maven ha salido con error (codigo 1)' $r.Estado
  Escribe $repo 'src/main/java/com/acme/demo/Rota.java' "package com.acme.demo;`n// NO_COMPILA`n"
  $r = Con-Falso @{} { Invoke-Analisis $repo }
  Igual 'Estado: no compila' 'no disponible: no compila' $r.Estado
  Igual 'no compila: sin hallazgos' 0 @($r.Hallazgos).Count
  Remove-Item -LiteralPath (Get-Ruta $repo 'src/main/java/com/acme/demo/Rota.java') -Force
  $r = Con-Falso @{ RESCATE_ANALISIS_SIN_XML = '1' } { Invoke-Analisis $repo }
  Igual 'Estado: Maven sale bien pero no deja XML' 'no disponible: SpotBugs no ha dejado spotbugsXml.xml' $r.Estado
  # Maven que no se puede lanzar y carpeta que no existe
  $antes = $Cfg.MvnExe
  $Cfg.MvnExe = 'mvn-que-no-existe-xq'
  try { $r = Invoke-Analisis $repo } catch { $r = @{ Estado = 'EXCEPCION: ' + $_.Exception.Message; Hallazgos = @() } } finally { $Cfg.MvnExe = $antes }
  Comprueba 'sin Maven: no disponible, no excepcion' ($r.Estado -like 'no disponible: *') $r.Estado
  $r = Invoke-Analisis (Join-Path $Dir 'no-existe-xq')
  Igual 'sin carpeta: no disponible' 'no disponible: la carpeta no existe' $r.Estado
}

$Pruebas['5 e) Invoke-Analisis con tope: un Maven que duerme mas que MinutosMaven da no disponible: tope'] = {
  $repo = Nuevo-Repo 'tope'
  $reloj = [System.Diagnostics.Stopwatch]::StartNew()
  $r = Con-Falso @{ RESCATE_ANALISIS_ESPERA = '40' } { $Cfg.MinutosMaven = 0.05; Invoke-Analisis $repo }
  Igual 'Estado' 'no disponible: tope' $r.Estado
  Igual 'sin hallazgos' 0 @($r.Hallazgos).Count
  Comprueba 'no espero al falso: menos de 25 s' ($reloj.Elapsed.TotalSeconds -lt 25) ([string]$reloj.Elapsed.TotalSeconds)
  Comprueba 'el detalle dice el tope' ("$($r.Detalle)" -match 'tope') "$($r.Detalle)"
  Igual 'MinutosMaven vuelve a lo que era' 30 $Cfg.MinutosMaven
}

$Pruebas['6 f) Invoke-Analisis con ficheros: el comando lleva el filtro y el resultado solo trae esos ficheros'] = {
  $repo = Nuevo-Repo 'filtro'
  Escribe $repo 'target/classes/com/acme/demo/Totales.class' 'x'
  Escribe $repo 'target/classes/com/acme/demo/Totales$Interna.class' 'x'
  Escribe $repo 'target/classes/com/acme/demo/Clasificador.class' 'x'
  $log = Join-Path $Dir 'filtro-llamadas.txt'
  $r = Con-Falso @{ RESCATE_ANALISIS_LLAMADAS = $log } { Invoke-Analisis $repo @('src/main/java/com/acme/demo/Totales.java') }
  Igual 'Estado' 'ok' $r.Estado
  $l = Llamadas-De $log
  Igual 'dos llamadas' 2 $l.Count
  Comprueba 'SpotBugs: solo la clase y sus anidadas' ("$($l[0])".Contains('-Dspotbugs.onlyAnalyze=com.acme.demo.Totales,com.acme.demo.Totales$Interna') -and -not "$($l[0])".Contains('Clasificador')) "$($l[0])"
  Comprueba 'PMD: solo ese fichero' ("$($l[1])".Contains('-Danalisis.includes=src/main/java/com/acme/demo/Totales.java') -and -not "$($l[1])".Contains('Clasificador')) "$($l[1])"
  Igual 'el resultado trae solo los hallazgos de ese fichero (3 de SpotBugs)' 3 @($r.Hallazgos).Count
  Igual 'y todos son de Totales.java' 3 @($r.Hallazgos | Where-Object { $_.Fichero -ceq 'src/main/java/com/acme/demo/Totales.java' }).Count
  # dos ficheros, uno con separadores de Windows
  if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }
  $r2 = Con-Falso @{ RESCATE_ANALISIS_LLAMADAS = $log } { Invoke-Analisis $repo @('src/main/java/com/acme/demo/Totales.java', 'src\main\java\com\acme\demo\Clasificador.java') }
  $l2 = Llamadas-De $log
  Comprueba 'dos ficheros: SpotBugs con las dos clases' ("$($l2[0])".Contains('-Dspotbugs.onlyAnalyze=com.acme.demo.Totales,com.acme.demo.Totales$Interna,com.acme.demo.Clasificador')) "$($l2[0])"
  Comprueba 'dos ficheros: PMD con los dos, separados por coma' ("$($l2[1])".Contains('-Danalisis.includes=src/main/java/com/acme/demo/Totales.java,src/main/java/com/acme/demo/Clasificador.java')) "$($l2[1])"
  Igual 'dos ficheros: los 9 hallazgos' 9 @($r2.Hallazgos).Count
  # ficheros que no son codigo de main: no hay nada que analizar y no se llama a Maven
  if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }
  $r3 = Con-Falso @{ RESCATE_ANALISIS_LLAMADAS = $log } { Invoke-Analisis $repo @('pom.xml', 'src/test/java/com/acme/demo/TotalesTest.java') }
  Igual 'solo pom y tests: ok sin hallazgos' 'ok' $r3.Estado
  Igual 'solo pom y tests: ningun hallazgo' 0 @($r3.Hallazgos).Count
  Igual 'solo pom y tests: Maven no se llama' 0 (Llamadas-De $log).Count
}

$Pruebas['7 ajustes, ruleset y ficheros: ASCII, claves de Sonar y versiones en $Cfg'] = {
  Igual 'SpotbugsPlugin' 'com.github.spotbugs:spotbugs-maven-plugin:4.10.5.0' $Cfg.SpotbugsPlugin
  Igual 'FbContrib' 'com.mebigfatguy.fb-contrib:fb-contrib:7.7.4' $Cfg.FbContrib
  Igual 'PmdPlugin' 'org.apache.maven.plugins:maven-pmd-plugin:3.28.0' $Cfg.PmdPlugin
  Igual 'DependencyPlugin (copia el jar de fb-contrib)' 'org.apache.maven.plugins:maven-dependency-plugin:3.8.1' $Cfg.DependencyPlugin
  Comprueba 'PmdReglas es el ruleset del repo' ((Test-Path -LiteralPath $Cfg.PmdReglas) -and (Split-Path $Cfg.PmdReglas -Leaf) -ceq 'pmd-sonar.xml') "$($Cfg.PmdReglas)"
  foreach ($f in @('analisis.ps1', 'analisis/pmd-sonar.xml', 'analisis/pom-pmd.xml', 'tests/probar-analisis.ps1', 'tests/falsos/analisis-mvn.ps1')) {
    $t = [System.IO.File]::ReadAllText((Get-Ruta $raiz $f))
    Comprueba "$f`: solo ASCII" ($t -notmatch '[^\x09\x0A\x0D\x20-\x7E]')
  }
  $codigo = [System.IO.File]::ReadAllText((Join-Path $raiz 'analisis.ps1'))
  Comprueba 'analisis.ps1: nada de PowerShell 7 (??, ?. ni ?[)' ($codigo -notmatch '\?\?|[\w\)\]]\?\.\w|\w\?\[')
  $rs = [xml][System.IO.File]::ReadAllText($Cfg.PmdReglas)
  $reglas = @($rs.ruleset.rule)
  Comprueba 'el ruleset es corto (de 5 a 25 reglas)' ($reglas.Count -ge 5 -and $reglas.Count -le 25) "$($reglas.Count)"
  Comprueba 'incluye CognitiveComplexity y CyclomaticComplexity' ((@($reglas | Where-Object { $_.ref -like '*/CognitiveComplexity' }).Count -eq 1) -and (@($reglas | Where-Object { $_.ref -like '*/CyclomaticComplexity' }).Count -eq 1))
  $lineas = @([System.IO.File]::ReadAllLines($Cfg.PmdReglas))
  $sin = @()
  for ($i = 0; $i -lt $lineas.Count; $i++) {
    if ($lineas[$i] -match '<rule ref=' -and $lineas[$i - 1] -notmatch '<!-- java:S\d+ ') { $sin += $lineas[$i].Trim() }
  }
  Igual 'cada regla lleva en la linea de antes un comentario con su clave de Sonar (java:S...)' 0 $sin.Count
  $cog = $rs.ruleset.rule | Where-Object { $_.ref -like '*/CognitiveComplexity' }
  Igual 'CognitiveComplexity avisa desde 16 (Sonar avisa por encima de 15)' '16' (($cog.properties.property | Where-Object { $_.name -eq 'reportLevel' }).value)
  $cic = $rs.ruleset.rule | Where-Object { $_.ref -like '*/CyclomaticComplexity' }
  Igual 'CyclomaticComplexity avisa desde 11 en metodos (Sonar avisa por encima de 10)' '11' (($cic.properties.property | Where-Object { $_.name -eq 'methodReportLevel' }).value)
  $pom = [System.IO.File]::ReadAllText($Cfg.PmdPom)
  Comprueba 'el pom auxiliar es XML y usa las propiedades analisis.repo, analisis.ruleset, analisis.includes y analisis.pmd' (([xml]$pom).project.artifactId -ceq 'pmd-sonar' -and $pom -match '\$\{analisis\.repo\}' -and $pom -match '\$\{analisis\.ruleset\}' -and $pom -match '\$\{analisis\.includes\}' -and $pom -match '\$\{analisis\.pmd\}')
}

# ================================ LANZADOR ================================
Invoke-Banco $Pruebas 'tests/probar-analisis.ps1'
