<#
probar-local.ps1 - Banco de pruebas de prueba-local.ps1.
No necesita Maven, Java ni Copilot: usa tests/falsos/copilot-local.ps1 y mvn-local.ps1 y repos de juguete que
crea en una carpeta temporal. Solo hace falta git. Vale para Windows PowerShell 5.1 y PowerShell 7. Solo ASCII.

  .\tests\probar-local.ps1                          # todas las pruebas
  .\tests\probar-local.ps1 -Solo distinto           # las que llevan 'distinto' en el nombre
  .\tests\probar-local.ps1 -Dir D:\tmp\x -Conservar # deja los repos de juguete para mirarlos

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
if (-not $Script) { $Script = Join-Path (Split-Path -Parent $aqui) 'prueba-local.ps1' }
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

# Un escenario: el original, el migrado (rama main) con su worktree de rescate (rama rescate/main-1, que lleva su
# propia regla.txt), los casos de migracion.ps1 en el migrado y la carpeta de ajustes. $Casos: job -> lista de
# entradas (una por caso). Con $SinPruebas no hay datos/pruebas.
function Nuevo-Escenario([string]$Nombre, $Casos, [string]$ReglaOrig = 'minimo=5.00', [string]$ReglaMig = 'minimo=5.00', [switch]$SinPruebas) {
  $raiz = Join-Path $Dir $Nombre
  if (Test-Path -LiteralPath $raiz) { Remove-Item -LiteralPath $raiz -Recurse -Force }
  $leg = Join-Path $raiz 'batch-viejo'
  $mig = Join-Path $raiz 'batch-nuevo'
  $casa = Join-Path $raiz 'home'
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
  [System.IO.File]::AppendAllText((Get-Ruta $mig '.git/info/exclude'), "`nmigracion-*/`n")
  $datos = Get-Ruta $mig 'migracion-batch-nuevo/datos'
  if (-not $SinPruebas) {
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
  }
  else { Escribe $datos 'mapa.json' '{ "jobs": [], "sinJob": [] }' }
  $aj = [ordered]@{ CopilotExe = (Join-Path $falsos 'copilot-local.ps1'); MvnExe = (Join-Path $falsos 'mvn-local.ps1'); SegundosPorLlamada = 60 }
  Escribe $casa 'ajustes.json' (ConvertTo-Json -InputObject $aj)
  return [pscustomobject]@{
    Raiz = $raiz; Legacy = $leg; Migrado = $mig; Wt = $wt; Home = $casa; Llamadas = (Join-Path $raiz 'llamadas')
    Local = (Get-Ruta $mig 'migracion-batch-nuevo/prueba-local'); CopiaOrig = ($leg + '-prueba-local'); CopiaMig = ($mig + '-prueba-local')
    Json = (Get-Ruta $mig 'migracion-batch-nuevo/datos/prueba-local.json')
  }
}

# Lanza prueba-local.ps1 con RESCATE_HOME en la carpeta del escenario (nunca toca los ajustes reales).
function Prueba($E, [string[]]$A = @(), [string]$Guion = '', [string]$Responde = '') {
  $env:RESCATE_HOME = $E.Home
  $env:RESCATE_LLAMADAS = $E.Llamadas
  $si = @('-Si')
  if ($Responde) { $si = @() }   # con $Responde, sin -Si: prueba-local.ps1 pregunta y lee esa respuesta de la entrada estandar
  try { return Lanzar $Script (@('-Legacy', $E.Legacy, '-Migrado', $E.Migrado, '-Modelo', 'modelo-x') + $si + $A) $Guion @($Responde) }
  finally { $env:RESCATE_HOME = ''; $env:RESCATE_LLAMADAS = '' }
}

function Caso($E, [string]$Job, [string]$Caso) { return @((Lee-Json $E.Json).casos | Where-Object { $_.job -eq $Job -and $_.caso -eq $Caso })[0] }

function Resultados($E) { return @((Lee-Json $E.Json).casos | ForEach-Object { $_.resultado }) }

# Las llamadas que dejo el Copilot falso (una por fichero <id>-<pid>.txt), como objetos clave=valor.
function Llamadas($E) {
  if (-not (Test-Path -LiteralPath $E.Llamadas)) { return @() }
  return @(Get-ChildItem -LiteralPath $E.Llamadas -File -Filter '*-*.txt' | Sort-Object Name | ForEach-Object {
      $o = [ordered]@{}
      foreach ($l in [System.IO.File]::ReadAllLines($_.FullName)) { $k, $v = ($l -split '=', 2); $o[$k] = $v }
      [pscustomobject]$o
    })
}

function Max-Simultaneas($Lista) {
  $ev = @()
  foreach ($l in $Lista) {
    if ($l.inicio -and $l.fin) { $ev += [pscustomobject]@{ T = [long]$l.inicio; D = 1 }; $ev += [pscustomobject]@{ T = [long]$l.fin; D = -1 } }
  }
  $max = 0; $cur = 0
  foreach ($x in @($ev | Sort-Object T, D)) { $cur += $x.D; if ($cur -gt $max) { $max = $cur } }
  return $max
}

# Lo que tiene que quedar igual de un repo: HEAD, cambios sin commit y ramas con su commit.
function Foto([string]$D) { return ((GitEn $D @('rev-parse', 'HEAD')) + '|' + (GitEn $D @('status', '--porcelain')) + '|' + (GitEn $D @('branch', '-v', '--no-abbrev'))) }

function Hoy { return (Get-Date).ToString('yyyyMMdd') }

# ================================ PRUEBAS ================================
$Pruebas = [ordered]@{}

$Pruebas['1 iguales: codigo 0, todo igual, sin tocar los repos (huella) y al relanzar sin llamar otra vez a Copilot'] = {
  $e = Nuevo-Escenario 'iguales' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00', 'importe=30.00'); remesaJob = @('importe=40.00', 'importe=50.00') })
  $antes = @((Foto $e.Legacy), (Foto $e.Migrado), (Foto $e.Wt))
  $r = Prueba $e
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'los cinco casos salen iguales' 'igual,igual,igual,igual,igual' ((Resultados $e) -join ',')
  $o = Lee-Json $e.Json
  Igual 'por job: cargaJob con 3 casos y 3 iguales' '3/3/0/0' ((@($o.jobs | Where-Object { $_.job -eq 'cargaJob' } | ForEach-Object { "$($_.casos)/$($_.iguales)/$($_.distintos)/$($_.sinProbar)" })) -join '')
  Comprueba 'la consola lleva la tabla por job' ($r.Salida -match 'cargaJob\s+3\s+3\s+0\s+0') (Cola $r.Salida)
  Comprueba 'y dice lo que no promete (lo de fuera se prueba en pre)' ($r.Salida -match 'simulado' -and $r.Salida -match 'pre') (Cola $r.Salida)
  Comprueba 'el arnes del original queda guardado' (Test-Path -LiteralPath (Get-Ruta $e.Local 'arnes/original/src/test/java/com/acme/viejo/PruebaLocalTest.java'))
  Comprueba 'con su pom.xml (solo una dependencia de test)' ((Lee $e.Local 'arnes/original/pom.xml') -match '<scope>test</scope>')
  Comprueba 'el del migrado, en el paquete de su clase de arranque' (Test-Path -LiteralPath (Get-Ruta $e.Local 'arnes/migrado/src/test/java/com/acme/nuevo/PruebaLocalTest.java'))
  Comprueba 'los casos quedan guardados' (Test-Path -LiteralPath (Get-Ruta $e.Local 'casos/cargaJob/caso-01/ficheros/entrada/datos.txt'))
  foreach ($s in @('original', 'original-2', 'migrado')) {
    Comprueba "y las salidas de $s" (Test-Path -LiteralPath (Get-Ruta $e.Local "salidas/$s/remesaJob/caso-02/estado.txt"))
  }
  $despues = @((Foto $e.Legacy), (Foto $e.Migrado), (Foto $e.Wt))
  Igual 'el original queda como estaba' $antes[0] $despues[0]
  Igual 'el migrado y sus ramas (tambien la de rescate) quedan como estaban' $antes[1] $despues[1]
  Igual 'el worktree de rescate queda como estaba' $antes[2] $despues[2]
  Comprueba 'las copias son worktrees aparte' ((Test-Path -LiteralPath $e.CopiaOrig) -and (Test-Path -LiteralPath $e.CopiaMig))
  $n = @(Llamadas $e).Count
  Igual 'siete llamadas: dos arneses y cinco casos' 7 $n
  $r = Prueba $e
  Igual 'al relanzar sale con 0' 0 $r.Codigo
  Igual 'sin ninguna llamada nueva a Copilot' $n @(Llamadas $e).Count
  Igual 'y los cinco casos siguen iguales (se han vuelto a ejecutar)' 'igual,igual,igual,igual,igual' ((Resultados $e) -join ',')
  Igual 'el original sigue como estaba tras el relanzamiento' $antes[0] (Foto $e.Legacy)
}

$Pruebas['2 distinto: el migrado (de la rama de rescate) deja otro fichero en un caso: codigo 2 y la primera linea de cada lado'] = {
  $e = Nuevo-Escenario 'distinto' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') }) 'minimo=5.00' 'minimo=5.01'
  $r = Prueba $e
  Igual 'sale con 2' 2 $r.Codigo
  $c = Caso $e 'cargaJob' 'caso-01'
  Igual 'el caso del limite sale distinto' 'distinto' $c.resultado
  $d = @($c.diferencias)[0]
  Igual 'en el fichero de salida' ('ficheros/salida/resultado_' + (Hoy) + '.txt') $d.fichero
  Igual 'una linea distinta' 1 $d.lineas
  Igual 'la del original' 'importe=5.00 -> aceptado' $d.original
  Igual 'la del migrado' 'importe=5.00 -> rechazado' $d.migrado
  Igual 'el otro caso sale igual' 'igual' (Caso $e 'cargaJob' 'caso-02').resultado
  Comprueba 'la consola lo dice con las dos lineas' ($r.Salida -match 'distinto' -and $r.Salida -match 'importe=5\.00 -> rechazado') (Cola $r.Salida)
}

$Pruebas['3 no determinista: dos salidas distintas del original no cuentan como distinto'] = {
  $e = Nuevo-Escenario 'azar' ([ordered]@{ cargaJob = @('importe=10.00 AZAR', 'importe=10.00') })
  $r = Prueba $e
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'el caso con azar es no determinista' 'no determinista' (Caso $e 'cargaJob' 'caso-01').resultado
  Igual 'el otro, igual' 'igual' (Caso $e 'cargaJob' 'caso-02').resultado
  Igual 'no cuenta como distinto en el job' 0 @((Lee-Json $e.Json).jobs)[0].distintos
}

$Pruebas['4 horas: si solo cambian las horas y la fecha de hoy, es igual'] = {
  $e = Nuevo-Escenario 'horas' ([ordered]@{ cargaJob = @('importe=10.00') }) 'minimo=5.00' "minimo=5.00`nsegundos=7"
  $r = Prueba $e
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'el caso sale igual' 'igual' (Caso $e 'cargaJob' 'caso-01').resultado
  $rel = 'cargaJob/caso-01/ficheros/salida/resultado_' + (Hoy) + '.txt'
  Comprueba 'aunque los ficheros no son identicos (la hora va 7 s desplazada)' ((Lee $e.Local "salidas/original/$rel") -ne (Lee $e.Local "salidas/migrado/$rel"))
}

$Pruebas['5 fuera: un caso que escribe fuera de su carpeta se rechaza y se deshace, sin arrastrar a los demas'] = {
  $e = Nuevo-Escenario 'fuera' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00', 'importe=30.00') })
  $r = Prueba $e @() 'caso-fuera:caso-cargaJob-02'
  Igual 'sale con 0 (nada distinto)' 0 $r.Codigo
  $c = Caso $e 'cargaJob' 'caso-02'
  Igual 'ese caso no se pudo preparar' 'no se pudo preparar' $c.resultado
  Comprueba 'y el motivo dice que escribio fuera' ($c.motivo -match 'fuera\.txt') $c.motivo
  Igual 'los otros dos salen iguales' 'igual,igual' (((Caso $e 'cargaJob' 'caso-01').resultado, (Caso $e 'cargaJob' 'caso-03').resultado) -join ',')
  Comprueba 'el fichero de fuera no queda en la copia del original' (-not (Test-Path -LiteralPath (Get-Ruta $e.CopiaOrig 'src/main/resources/fuera.txt')))
  Comprueba 'ni el caso queda guardado' (-not (Test-Path -LiteralPath (Get-Ruta $e.Local 'casos/cargaJob/caso-02')))
  $t = Lee-Json (Get-Ruta $e.Local 'tareas/caso-cargaJob-02.json')
  Igual 'la tarea queda atascada' 'atascada' $t.estado
}

$Pruebas['6 arnes con extras: tocar src/main se deshace y una dependencia sin scope test recibe el scope; un arnes que no compila sigue rechazado'] = {
  $e = Nuevo-Escenario 'arnes-main' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba $e @() 'arnes-toca-main:arnes-original'
  Igual 'con un fichero de mas en src/main sale con 0' 0 $r.Codigo
  $t = Lee-Json (Get-Ruta $e.Local 'tareas/arnes-original.json')
  Igual 'el arnes del original queda hecho, a la primera' 'hecha/1' "$($t.estado)/$($t.intentos)"
  Comprueba 'la consola dice el fichero de src/main que deshace' ($r.Salida.Contains('Deshago lo que la IA ha tocado fuera de lo suyo: src/main/java/Tocado.java')) (Cola $r.Salida)
  Comprueba 'el fichero no queda en la copia' (-not (Test-Path -LiteralPath (Get-Ruta $e.CopiaOrig 'src/main/java/Tocado.java')))
  Comprueba 'ni en el arnes guardado' (-not (Test-Path -LiteralPath (Get-Ruta $e.Local 'arnes/original/src/main/java/Tocado.java')))
  $e = Nuevo-Escenario 'arnes-dep' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba $e @() 'arnes-dep-sin-test:arnes-original'
  Igual 'con una dependencia sin scope test sale con 0' 0 $r.Codigo
  $t = Lee-Json (Get-Ruta $e.Local 'tareas/arnes-original.json')
  Igual 'el arnes del original queda hecho' 'hecha' $t.estado
  Comprueba 'la dependencia nueva lleva scope test en el pom de la copia' ((Lee $e.CopiaOrig 'pom.xml') -match '(?s)<artifactId>runtime</artifactId>.*?<scope>test</scope>.*?</dependency>') (Lee $e.CopiaOrig 'pom.xml')
  $e = Nuevo-Escenario 'arnes-mig' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba $e @() 'arnes-no-compila:arnes-migrado'
  Igual 'sin arnes del migrado sale con 1' 1 $r.Codigo
  Igual 'el arnes del migrado se intento dos veces' 2 @(Llamadas $e | Where-Object { $_.id -eq 'arnes-migrado' }).Count
  $t = Lee-Json (Get-Ruta $e.Local 'tareas/arnes-migrado.json')
  Comprueba 'y el motivo lleva el error de Maven' ($t.motivo -match 'simbolo de mentira') $t.motivo
  Igual 'el caso se prepara igual (queda para el relanzamiento)' 1 @(Llamadas $e | Where-Object { $_.tipo -eq 'caso-local' }).Count
  Igual 'pero sin migrado no se puede comparar' 'no se pudo preparar' (Caso $e 'cargaJob' 'caso-01').resultado
}

$Pruebas['7 no aplica: un caso con no-aplica.txt queda sin probar en local'] = {
  $e = Nuevo-Escenario 'no-aplica' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba $e @() 'caso-no-aplica:caso-cargaJob-01'
  Igual 'sale con 0' 0 $r.Codigo
  $c = Caso $e 'cargaJob' 'caso-01'
  Igual 'el caso queda sin probar en local' 'sin probar en local' $c.resultado
  Comprueba 'con la frase de la IA' ($c.motivo -match 'correo') $c.motivo
  Igual 'el job lo cuenta en sin probar' 1 @((Lee-Json $e.Json).jobs)[0].sinProbar
}

$Pruebas['8 paralelo: nunca mas de 4 llamadas a la vez'] = {
  $e = Nuevo-Escenario 'paralelo' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=11.00', 'importe=12.00', 'importe=13.00', 'importe=14.00', 'importe=15.00') })
  $env:RESCATE_ESPERA = '2'
  try { $r = Prueba $e }
  finally { $env:RESCATE_ESPERA = '' }
  Igual 'sale con 0' 0 $r.Codigo
  $casos = @(Llamadas $e | Where-Object { $_.tipo -eq 'caso-local' })
  Igual 'seis llamadas de casos' 6 $casos.Count
  $max = Max-Simultaneas $casos
  Comprueba 'como mucho 4 a la vez' ($max -le 4) "hubo $max"
  Comprueba 'y en paralelo de verdad (mas de 1)' ($max -gt 1) "hubo $max"
  Igual 'los dos arneses, uno detras de otro (el del migrado traduce el del original, m29)' 1 (Max-Simultaneas @(Llamadas $e | Where-Object { $_.tipo -eq 'arnes-local' }))
}

$Pruebas['9 sin pruebas: sin datos/pruebas para y dice que se lance antes migracion.ps1'] = {
  $e = Nuevo-Escenario 'sin-pruebas' @{} -SinPruebas
  $r = Prueba $e
  Igual 'sale con 1' 1 $r.Codigo
  Comprueba 'dice que se lance antes migracion.ps1' ($r.Salida -match 'migracion\.ps1') (Cola $r.Salida)
  Comprueba 'sin crear las copias' (-not (Test-Path -LiteralPath $e.CopiaOrig))
  Igual 'ni llamar a Copilot' 0 @(Llamadas $e).Count
}

$Pruebas['10 JDK: -JavaLegacy solo para el original, -Job solo ese job y un original que no compila pide -JavaLegacy'] = {
  $e = Nuevo-Escenario 'jdk' ([ordered]@{ cargaJob = @('importe=10.00'); remesaJob = @('importe=20.00') })
  $jdk = Join-Path $e.Raiz 'jdk-viejo'
  [void](New-Item -ItemType Directory -Path $jdk -Force)
  $r = Prueba $e @('-JavaLegacy', $jdk, '-Job', 'remesaJob')
  Igual 'sale con 0' 0 $r.Codigo
  $mvn = @([System.IO.File]::ReadAllLines((Join-Path $e.Llamadas 'mvn.log')))
  $orig = @($mvn | Where-Object { $_.StartsWith($e.CopiaOrig + '|') })
  $migr = @($mvn | Where-Object { $_.StartsWith($e.CopiaMig + '|') })
  Comprueba 'Maven corre en las dos copias' ($orig.Count -gt 0 -and $migr.Count -gt 0) ($mvn -join ' / ')
  Comprueba 'en el original, con JAVA_HOME = -JavaLegacy' (@($orig | Where-Object { $_.Split('|')[1] -ne $jdk }).Count -eq 0) ($orig -join ' / ')
  Comprueba 'en el migrado, sin el' (@($migr | Where-Object { $_.Split('|')[1] -eq $jdk }).Count -eq 0) ($migr -join ' / ')
  Comprueba 'los test de Maven, sin saltarse los tests aunque el pom lo diga' (@($mvn | Where-Object { $_ -match '\btest\b' -and $_ -notmatch '-DskipTests=false' }).Count -eq 0) ($mvn -join ' / ')
  Igual 'con -Job solo sale ese job' 'remesaJob' ((@((Lee-Json $e.Json).casos | ForEach-Object { $_.job }) | Select-Object -Unique) -join ',')
  Igual 'y solo se preparan sus casos' 0 @(Llamadas $e | Where-Object { $_.id -like 'caso-cargaJob-*' }).Count
  $e = Nuevo-Escenario 'no-compila' ([ordered]@{ cargaJob = @('importe=10.00') })
  Escribe $e.Legacy 'src/main/java/com/acme/viejo/Lector.java' "package com.acme.viejo;`n// NO_COMPILA`n"
  [void](GitEn $e.Legacy @('commit', '-q', '-a', '-m', 'no compila'))
  $r = Prueba $e
  Igual 'un original que no compila sale con 1' 1 $r.Codigo
  Comprueba 'y pide -JavaLegacy' ($r.Salida -match '-JavaLegacy') (Cola $r.Salida)
  Igual 'sin llamar a Copilot' 0 @(Llamadas $e).Count
}

$Pruebas['11 arreglo: un commit nuevo en la rama de rescate se prueba sin volver a llamar a Copilot'] = {
  $e = Nuevo-Escenario 'arreglo' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') })
  $r = Prueba $e
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  $n = @(Llamadas $e).Count
  Escribe $e.Wt 'regla.txt' "minimo=5.01`n"
  [void](GitEn $e.Wt @('commit', '-q', '-a', '-m', 'cambia el limite'))
  $r = Prueba $e
  Igual 'con el limite cambiado en la rama de rescate sale con 2' 2 $r.Codigo
  Igual 'el caso del limite sale distinto' 'distinto' (Caso $e 'cargaJob' 'caso-01').resultado
  Igual 'sin llamar otra vez a Copilot (el arnes del migrado sigue valiendo)' $n @(Llamadas $e).Count
}

$Pruebas['12 entradas raras: carpeta vacia, caso sin efecto, IA que hace commit, azar en un fichero y Latin-1'] = {
  $e = Nuevo-Escenario 'raras' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=10.00', 'importe=10.00', 'importe=10.00 AZAR | SQL importe=5.00', 'importe=10.00 LATIN') }) 'minimo=5.00' "minimo=5.01`nmayus=si"
  $r = Prueba $e @() 'caso-carpeta-vacia:caso-cargaJob-01;caso-sin-efecto:caso-cargaJob-02;caso-commit:caso-cargaJob-03'
  Igual 'sale con 2 (hay distintos)' 2 $r.Codigo
  Comprueba 'y deja su resultado' (Test-Path -LiteralPath $e.Json) (Cola $r.Salida)
  $c = Caso $e 'cargaJob' 'caso-01'
  Comprueba 'un caso con solo una carpeta vacia no vale (pide sin-entrada.txt)' ($c.resultado -eq 'no se pudo preparar' -and $c.motivo -match 'sin-entrada\.txt') "$($c.resultado): $($c.motivo)"
  $c = Caso $e 'cargaJob' 'caso-02'
  Comprueba 'un caso que sale como el vacio es igual, con aviso' ($c.resultado -eq 'igual' -and $c.motivo -match 'vacio') "$($c.resultado): $($c.motivo)"
  $c = Caso $e 'cargaJob' 'caso-03'
  Comprueba 'lo que la IA mete en un commit se ve y se rechaza' ($c.resultado -eq 'no se pudo preparar' -and $c.motivo -match 'fuera\.txt') "$($c.resultado): $($c.motivo)"
  Igual 'y la copia vuelve al commit del original' (GitEn $e.Legacy @('rev-parse', 'HEAD')) (GitEn $e.CopiaOrig @('rev-parse', 'HEAD'))
  $c = Caso $e 'cargaJob' 'caso-04'
  Igual 'un fichero que cambia de una ejecucion a otra no tapa la diferencia de una tabla' 'distinto' $c.resultado
  Igual 'que es la de la tabla' 'tablas/DATOS.csv' (@($c.diferencias)[0].fichero)
  Comprueba 'y dice que fichero no se ha contado' ($c.motivo -match 'resultado_') $c.motivo
  $c = Caso $e 'cargaJob' 'caso-05'
  Igual 'dos ficheros en Latin-1 que solo cambian en una letra con tilde son distintos' 'distinto' $c.resultado
}

$Pruebas['13 tareas.ps1: Get-VariablesPrompt da las claves de entradas.prompt y no cambia las tareas de siempre'] = {
  $f = Join-Path $Dir 'variables-prompt.ps1'
  [System.IO.File]::WriteAllText($f, @'
param([string]$Sis)
. (Join-Path $Sis 'comun.ps1')
. (Join-Path $Sis 'tareas.ps1')
$nueva = '{"id":"arnes-1","tipo":"arnes-local","entradas":{"prompt":{"JOB":"cargaJob","TEST":"src/test/java/X.java"}}}' | ConvertFrom-Json
$ficha = '{"id":"ficha-1","tipo":"ficha-job","entradas":{"job":"cargaJob","pasos":"p","datos":"d"}}' | ConvertFrom-Json
foreach ($t in @($nueva, $ficha)) {
  $v = Get-VariablesPrompt $t 'leer.java'
  $k = @($v.Keys | ForEach-Object { [string]$_ }); [Array]::Sort($k, [StringComparer]::Ordinal)
  'CLAVES ' + $t.id + ' ' + (@($k | ForEach-Object { $_ + '=' + $v[$_] }) -join ';')
}
'@)
  $r = Lanzar $f @((Split-Path -Parent $Script))
  $nueva = @($r.Salida -split "`n" | Where-Object { $_ -like 'CLAVES arnes-1 *' })[0]
  $ficha = @($r.Salida -split "`n" | Where-Object { $_ -like 'CLAVES ficha-1 *' })[0]
  Comprueba 'una tarea con entradas.prompt recibe sus claves' ($nueva -match 'JOB=cargaJob;' -and $nueva -match 'TEST=src/test/java/X\.java') (Cola $r.Salida)
  Comprueba 'y no las de ficha-clase' ($nueva -and $nueva -notmatch 'PAPELES=|FICHERO=') "$nueva"
  Comprueba 'ficha-job sigue con sus claves de siempre' ($ficha -match '^CLAVES ficha-1 CITA_MAX=\d+;DATOS=d;JOB=cargaJob;PASOS=p;PASOS_MAX=\d+;RELLENO="de forma clara"[^;]*;SALIDA=\.rescate/tareas/ficha-1\.json$') "$ficha"
}

$Pruebas['14 un caso por JVM: un original con estado static entre ejecuciones no da distintos falsos; el arnes debe filtrar por caso'] = {
  $e = Nuevo-Escenario 'estatico' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00', 'importe=30.00') }) "minimo=5.00`nestatico=si"
  $r = Prueba $e
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'los tres casos salen iguales' 'igual,igual,igual' ((Resultados $e) -join ',')
  $tests = @([System.IO.File]::ReadAllLines((Join-Path $e.Llamadas 'mvn.log')) | Where-Object { $_ -match 'prueba\.local\.job=' })
  Comprueba 'cada Maven de los casos lleva un solo caso (-Dprueba.local.caso)' ($tests.Count -gt 0 -and @($tests | Where-Object { $_ -notmatch '-Dprueba\.local\.caso=caso-\d+' }).Count -eq 0) ($tests -join ' / ')
  $e = Nuevo-Escenario 'sin-filtro' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba $e @() 'arnes-sin-filtro:arnes-original'
  Igual 'un arnes que no filtra por caso no vale: sale con 1' 1 $r.Codigo
  $t = Lee-Json (Get-Ruta $e.Local 'tareas/arnes-original.json')
  Comprueba 'y el motivo nombra prueba.local.caso' ($t.estado -eq 'atascada' -and $t.motivo -match 'prueba\.local\.caso') "$($t.estado): $($t.motivo)"
}

# Pasados MinutosMaven minutos se para Maven con sus procesos hijos y la llamada cuenta como fallida. Estas pruebas lo cuelgan con
# tests/falsos/mvn-dormido.ps1 (escribe una linea, lanza un hijo que duerme y duerme 120 s) y un tope de 0.05 min (3 s). Si el tope
# no parase a Maven, el lanzamiento duraria mas de 120 s: el limite de 90 s deja margen al resto del lanzamiento con la maquina cargada.

# Lanza prueba-local.ps1 con el Maven que se cuelga (mvn-dormido, que pasa el resto al mvn-local) y un tope de 0.05 min en el
# ajustes.json del escenario. Se cuelgan las llamadas cuya '<carpeta>|<argumentos>' casa con $Cuelga. Devuelve lo de Prueba, mas
# Segundos (lo que ha tardado) y Pids (la carpeta donde el falso apunta lo suyo).
function Prueba-Con-Tope($E, [string]$Cuelga) {
  $aj = [ordered]@{ CopilotExe = (Join-Path $falsos 'copilot-local.ps1'); MvnExe = (Join-Path $falsos 'mvn-dormido.ps1'); SegundosPorLlamada = 60; MinutosMaven = 0.05 }
  Escribe $E.Home 'ajustes.json' (ConvertTo-Json -InputObject $aj)
  $pids = Join-Path $E.Raiz 'pids'
  $env:RESCATE_MVN_FALSO = 'mvn-local.ps1'
  $env:RESCATE_MVN_CUELGA = $Cuelga
  $env:RESCATE_MVN_PIDS = $pids
  $env:RESCATE_MVN_SEGUNDOS = '120'
  $reloj = [System.Diagnostics.Stopwatch]::StartNew()
  try { $r = Prueba $E }
  finally { $env:RESCATE_MVN_FALSO = ''; $env:RESCATE_MVN_CUELGA = ''; $env:RESCATE_MVN_PIDS = ''; $env:RESCATE_MVN_SEGUNDOS = '' }
  return [pscustomobject]@{ Codigo = $r.Codigo; Salida = $r.Salida; Segundos = $reloj.Elapsed.TotalSeconds; Pids = $pids }
}

# El registro que dice un mensaje de tope ('... Registro: <ruta>.').
function Registro-Del-Tope([string]$Mensaje) { return [regex]::Match($Mensaje, 'Registro: (\S+)\.(\s|$)').Groups[1].Value }

$Pruebas['15 tope de Maven: prueba-local: el caso del migrado que se cuelga sale sin ejecutar con el mensaje y el siguiente se ejecuta (MinutosMaven de ajustes.json)'] = {
  $e = Nuevo-Escenario 'tope-migrado' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba-Con-Tope $e ([regex]::Escape($e.CopiaMig) + '\|.*-Dprueba\.local\.caso=caso-01( |$)')
  Igual 'sale con 0, como siempre' 0 $r.Codigo
  $c = Caso $e 'cargaJob' 'caso-01'
  $motivo = "$($c.motivo)"
  Igual 'el caso que se cuelga: no se pudo preparar' 'no se pudo preparar' $c.resultado
  Comprueba 'y su motivo es el mensaje del tope (0.05: manda el ajustes.json)' ($motivo.StartsWith('Maven se ha pasado del tope de 0.05 min y se ha parado (Maven, migrado cargaJob caso-01). Registro: ')) $motivo
  $reg = Registro-Del-Tope $motivo
  Comprueba 'con su registro' ($reg -and (Test-Path -LiteralPath $reg)) $motivo
  Igual 'el otro caso sale igual' 'igual' (Caso $e 'cargaJob' 'caso-02').resultado
  Comprueba-Tope $r.Pids $r.Segundos 90 $reg
}

$Pruebas['16 tope de Maven: prueba-local: un caso que se cuelga en el original no se da por bueno y su motivo lleva el mensaje'] = {
  $e = Nuevo-Escenario 'tope-original' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba-Con-Tope $e ([regex]::Escape($e.CopiaOrig) + '\|.*-Dprueba\.local\.caso=caso-01( |$)')
  $c = Caso $e 'cargaJob' 'caso-01'
  $motivo = "$($c.motivo)"
  Igual 'el caso que se cuelga: no se pudo preparar' 'no se pudo preparar' $c.resultado
  Comprueba 'y su motivo lleva el mensaje del tope' ($motivo -match [regex]::Escape('Maven se ha pasado del tope de 0.05 min')) $motivo
  Igual 'el otro caso sale igual' 'igual' (Caso $e 'cargaJob' 'caso-02').resultado
  Comprueba-Tope $r.Pids $r.Segundos 90 (Registro-Del-Tope $motivo)
}

$Pruebas['17 tope de Maven: cobertura (tareas.ps1): pasado el tope, sin medida y el motivo es el mensaje'] = {
  $f = Join-Path $Dir 'tope-cobertura.ps1'
  [System.IO.File]::WriteAllText($f, @'
param([string]$Sis, [string]$Mvn, [string]$Carpeta, [string]$Registro)
. (Join-Path $Sis 'comun.ps1')
. (Join-Path $Sis 'tareas.ps1')
$Cfg.MvnExe = $Mvn
$Cfg.MinutosMaven = 0.05
$Cfg.SegundosLatido = 0
$reloj = [System.Diagnostics.Stopwatch]::StartNew()
$o = Get-Cobertura $Carpeta $Registro $true
'MEDIDA ' + $o.medida
'PORCENTAJE [' + $o.porcentaje + ']'
'MOTIVO ' + $o.motivo
'SEGUNDOS ' + $reloj.Elapsed.TotalSeconds
'@)
  $reg = Join-Path $Dir 'tope-t7.log'
  $carpPids = Join-Path $Dir 'tope-t7-pids'
  $env:RESCATE_MVN_CUELGA = 'jacoco'
  $env:RESCATE_MVN_PIDS = $carpPids
  try { $r = Lanzar $f @((Split-Path -Parent $Script), (Join-Path $falsos 'mvn-dormido.ps1'), $Dir, $reg) }
  finally { $env:RESCATE_MVN_CUELGA = ''; $env:RESCATE_MVN_PIDS = '' }
  $v = @{}
  foreach ($l in @($r.Salida -split "`n")) { if ($l -cmatch '^([A-Z]+) (.*)$') { $v[$Matches[1]] = $Matches[2] } }
  Igual 'sin medida' 'False' $v['MEDIDA']
  Igual 'y sin porcentaje' '[]' $v['PORCENTAJE']
  Igual 'el motivo es el mensaje del tope' "Maven se ha pasado del tope de 0.05 min y se ha parado (Maven (cobertura)). Registro: $reg." $v['MOTIVO']
  Comprueba-Tope $carpPids ([double]$v['SEGUNDOS']) 20 $reg
}

# ===================== CULPABLE: -Desde <commit> [-Deshacer] =====================
# Con -Desde, cada caso distinto se busca, por biseccion en la rama que se prueba (la de rescate), hasta dar con el primer commit
# donde deja de ser igual. Con -Deshacer, ese commit se revierte con git revert en la carpeta de rescate. Estas pruebas hacen
# commits a mano en el worktree de rescate del escenario. El caso 1 de los escenarios es el del limite (importe=5.00): sale igual
# con minimo=5.00 y distinto con minimo=5.01.

# Hace un commit en $D con $Rel = $Texto y devuelve su hash.
function Commit-En([string]$D, [string]$Rel, [string]$Texto, [string]$Asunto) {
  Escribe $D $Rel $Texto
  [void](GitEn $D @('add', '--', $Rel))
  [void](GitEn $D @('commit', '-q', '-m', $Asunto))
  return (GitEn $D @('rev-parse', 'HEAD'))
}

# $N commits en la rama de rescate del escenario, uno detras de otro: el numero $Rompe (si es > 0) pone minimo=5.01 en regla.txt
# y los demas solo apuntan una nota. Devuelve Desde (el HEAD de antes) y Commits (los hashes, del mas viejo al mas nuevo).
# Los commits van a la rama de rescate ($E.Wt) o, si se da $D, a esa carpeta.
function Historia($E, [int]$Rompe, [int]$N = 5, [string]$D = '') {
  if (-not $D) { $D = $E.Wt }
  $desde = GitEn $D @('rev-parse', 'HEAD')
  $cs = @()
  for ($i = 1; $i -le $N; $i++) {
    if ($i -eq $Rompe) { $cs += (Commit-En $D 'regla.txt' "minimo=5.01`n" "cambia el limite del paso $i") }
    else { $cs += (Commit-En $D "notas/paso-$i.txt" "nota $i`n" "nota del paso $i") }
  }
  return [pscustomobject]@{ Desde = $desde; Commits = $cs }
}

function Corto([string]$Hash) { return $Hash.Substring(0, 7) }

# Cuantas veces se ha ejecutado en el migrado (su copia) el caso $Caso (las lineas 'test' de mvn.log del Maven falso).
function Ejecuciones-Mig($E, [string]$Caso) {
  $p = $E.CopiaMig + '|'
  return @([System.IO.File]::ReadAllLines((Join-Path $E.Llamadas 'mvn.log')) | Where-Object { $_.StartsWith($p) -and $_ -match ' test -Dtest=PruebaLocalTest ' -and $_ -match ('-Dprueba\.local\.caso=' + $Caso + '( |$)') }).Count
}

function Culpables($E) { return @((Lee-Json $E.Json).culpables | Where-Object { $_ }) }

# El HEAD y los cambios sin commit de una carpeta (sin las ramas: la de rescate cambia con un revert).
function Estado-Git([string]$D) { return ((GitEn $D @('rev-parse', 'HEAD')) + '|' + (GitEn $D @('status', '--porcelain'))) }

# Hay un git revert a medias en $D?
function Revert-A-Medias([string]$D) {
  $p = GitEn $D @('rev-parse', '--git-path', 'REVERT_HEAD')
  if (-not [System.IO.Path]::IsPathRooted($p)) { $p = Join-Path $D $p }
  return (Test-Path -LiteralPath $p)
}

$Pruebas['18 culpable (a): cinco commits despues de -Desde y el caso se rompe en el 3.o: lo encuentra, con pocas ejecuciones del migrado, y lo dice'] = {
  $e = Nuevo-Escenario 'culpable-a' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') })
  $h = Historia $e 3
  $antes = Estado-Git $e.Wt
  $r = Prueba $e @('-Desde', $h.Desde)
  Igual 'sale con 2 (sin -Deshacer el caso sigue distinto)' 2 $r.Codigo
  $msg = "El caso cargaJob/caso-01 era igual en $(Corto $h.Desde) y se rompe en $(Corto $h.Commits[2]) (cambia el limite del paso 3)."
  Comprueba 'la consola dice cual era igual y cual lo rompe, con su asunto' ($r.Salida.Contains($msg)) $msg
  Igual 'el otro caso sale igual' 'igual' (Caso $e 'cargaJob' 'caso-02').resultado
  $c = @(Culpables $e)
  Igual 'culpables lleva una entrada' 1 $c.Count
  Igual 'con el job' 'cargaJob' $c[0].job
  Igual 'el caso' 'caso-01' $c[0].caso
  Igual 'el commit entero' $h.Commits[2] $c[0].commit
  Igual 'el asunto' 'cambia el limite del paso 3' $c[0].asunto
  Igual 'sin deshacer' 'False' "$($c[0].deshecho)"
  $n = Ejecuciones-Mig $e 'caso-01'
  Comprueba 'como mucho 4 ejecuciones del migrado en la busqueda (sin la de la comparacion normal)' (($n - 1) -le 4) "ejecuciones en total: $n"
  Igual 'sin -Deshacer la rama de rescate queda como estaba' $antes (Estado-Git $e.Wt)
}

$Pruebas['19 culpable (a2): ocho commits y el caso se rompe en el 6.o: biseccion, no uno a uno'] = {
  $e = Nuevo-Escenario 'culpable-a2' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') })
  $h = Historia $e 6 8
  $r = Prueba $e @('-Desde', $h.Desde)
  Igual 'sale con 2' 2 $r.Codigo
  $c = @(Culpables $e)
  Igual 'encuentra el 6.o' $h.Commits[5] "$($c[0].commit)"
  $n = Ejecuciones-Mig $e 'caso-01'
  Comprueba 'con 4 ejecuciones o menos en la busqueda (uno a uno serian 7)' (($n - 1) -le 4) "ejecuciones en total: $n"
}

$Pruebas['20 culpable (b): un caso que ya era distinto en -Desde: lo dice y no busca'] = {
  $e = Nuevo-Escenario 'culpable-b' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') }) 'minimo=5.00' 'minimo=5.01'
  $h = Historia $e 0 2
  $r = Prueba $e @('-Desde', $h.Desde)
  Igual 'sale con 2' 2 $r.Codigo
  Comprueba 'dice que el caso ya era distinto en -Desde' ($r.Salida.Contains("El caso cargaJob/caso-01 ya era distinto en $(Corto $h.Desde)")) (Cola $r.Salida)
  Comprueba 'y no dice que se rompe en ningun commit' ($r.Salida -notmatch 'se rompe en') (Cola $r.Salida)
  Igual 'culpables vacio' 0 @(Culpables $e).Count
  Igual 'dos ejecuciones del migrado: la normal y la de -Desde, ninguna mas' 2 (Ejecuciones-Mig $e 'caso-01')
}

$Pruebas['21 culpable (c): -Deshacer revierte el commit, el caso vuelve a igual y no se toca nada mas'] = {
  $e = Nuevo-Escenario 'culpable-c' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') })
  $h = Historia $e 3
  $legacy = Foto $e.Legacy
  $migrado = Estado-Git $e.Migrado
  $r = Prueba $e @('-Desde', $h.Desde, '-Deshacer')
  Igual 'sale con 0 (el estado final es todo igual)' 0 $r.Codigo
  Comprueba 'la consola dice que ahora es igual' ($r.Salida -match 'cargaJob/caso-01.*ahora igual') (Cola $r.Salida)
  Igual 'el caso queda igual' 'igual,igual' ((Resultados $e) -join ',')
  Igual 'el HEAD de rescate tiene un solo commit nuevo, encima del ultimo' $h.Commits[4] (GitEn $e.Wt @('rev-parse', 'HEAD~1'))
  Comprueba 'que es un Revert del 3.o' ((GitEn $e.Wt @('log', '-1', '--format=%s')) -like 'Revert "cambia el limite del paso 3"*') (GitEn $e.Wt @('log', '-1', '--format=%s'))
  Igual 'sus cinco commits siguen igual (en su sitio)' ($h.Commits -join ',') ((GitEn $e.Wt @('rev-list', '--reverse', "$($h.Desde)..HEAD~1")) -split "`n" -join ',')
  Igual 'regla.txt vuelve a lo de antes' "minimo=5.00`n" (Lee $e.Wt 'regla.txt')
  Igual 'sin cambios sin commit' '' (GitEn $e.Wt @('status', '--porcelain'))
  Igual 'la carpeta del migrado queda como estaba' $migrado (Estado-Git $e.Migrado)
  Igual 'la del original, tambien' $legacy (Foto $e.Legacy)
  $c = @(Culpables $e)
  Igual 'culpables: el 3.o, deshecho' "$($h.Commits[2]) True" "$($c[0].commit) $($c[0].deshecho)"
  Igual 'el json lleva el commit migrado de ahora (el del revert)' (GitEn $e.Wt @('rev-parse', 'HEAD')) (Lee-Json $e.Json).commitMigrado
  Comprueba 'y la prueba no dice que han cambiado las carpetas' ($r.Salida -notmatch 'Ha cambiado durante la prueba') (Cola $r.Salida)
}

$Pruebas['22 culpable (d): conflicto al revertir (el 4.o toca las mismas lineas): se aborta, el HEAD queda igual y lo dice'] = {
  $e = Nuevo-Escenario 'culpable-d' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') })
  $desde = GitEn $e.Wt @('rev-parse', 'HEAD')
  $c1 = Commit-En $e.Wt 'notas/paso-1.txt' "nota 1`n" 'nota del paso 1'
  $c2 = Commit-En $e.Wt 'notas/paso-2.txt' "nota 2`n" 'nota del paso 2'
  $c3 = Commit-En $e.Wt 'regla.txt' "minimo=5.01`n" 'cambia el limite del paso 3'
  $c4 = Commit-En $e.Wt 'regla.txt' "minimo=5.02`n" 'cambia otra vez el limite'
  $c5 = Commit-En $e.Wt 'notas/paso-5.txt' "nota 5`n" 'nota del paso 5'
  $r = Prueba $e @('-Desde', $desde, '-Deshacer')
  Igual 'sale con 2 (sigue distinto)' 2 $r.Codigo
  Comprueba 'encuentra el 3.o' ($r.Salida.Contains("se rompe en $(Corto $c3) (cambia el limite del paso 3)")) (Cola $r.Salida)
  Comprueba 'dice que no lo deshace por el conflicto' ($r.Salida -match 'No deshago' -and $r.Salida -match 'conflicto') (Cola $r.Salida)
  Igual 'el HEAD de rescate queda en el ultimo commit' $c5 (GitEn $e.Wt @('rev-parse', 'HEAD'))
  Igual 'sin cambios sin commit' '' (GitEn $e.Wt @('status', '--porcelain'))
  Comprueba 'y sin un revert a medias' (-not (Revert-A-Medias $e.Wt))
  Igual 'culpables: el 3.o, sin deshacer' "$c3 False" "$(@(Culpables $e)[0].commit) $(@(Culpables $e)[0].deshecho)"
  Igual 'el caso sigue distinto' 'distinto' (Caso $e 'cargaJob' 'caso-01').resultado
}

$Pruebas['23 culpable (e): cambios sin commit en la carpeta de rescate: no deshace y lo dice'] = {
  $e = Nuevo-Escenario 'culpable-e' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') })
  $h = Historia $e 3
  Escribe $e.Wt 'notas/paso-1.txt' "a medias`n"
  $antes = Estado-Git $e.Wt
  $r = Prueba $e @('-Desde', $h.Desde, '-Deshacer')
  Igual 'sale con 2 (sigue distinto)' 2 $r.Codigo
  Comprueba 'dice que no deshace por los cambios sin commit' ($r.Salida -match 'No deshago' -and $r.Salida -match 'cambios sin commit') (Cola $r.Salida)
  Igual 'el HEAD y los cambios quedan como estaban' $antes (Estado-Git $e.Wt)
  Igual 'y el fichero a medias sigue como lo dejo quien lo toco' "a medias`n" (Lee $e.Wt 'notas/paso-1.txt')
  Igual 'culpables: el 3.o, sin deshacer' "$($h.Commits[2]) False" "$(@(Culpables $e)[0].commit) $(@(Culpables $e)[0].deshecho)"
}

$Pruebas['24 culpable (f): dos casos rotos por el mismo commit: un solo revert'] = {
  $e = Nuevo-Escenario 'culpable-f' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=5.00', 'importe=10.00') })
  $h = Historia $e 3
  $r = Prueba $e @('-Desde', $h.Desde, '-Deshacer')
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'un solo commit nuevo en rescate' 1 (GitEn $e.Wt @('rev-list', '--count', "$($h.Commits[4])..HEAD"))
  $c = @(Culpables $e)
  Igual 'culpables lleva los dos casos' 'caso-01,caso-02' ((@($c | ForEach-Object { $_.caso })) -join ',')
  Igual 'los dos con el mismo commit, el 3.o' "$($h.Commits[2]),$($h.Commits[2])" ((@($c | ForEach-Object { $_.commit })) -join ',')
  Igual 'los dos deshechos' 'True,True' ((@($c | ForEach-Object { "$($_.deshecho)" })) -join ',')
  Igual 'los tres casos quedan iguales' 'igual,igual,igual' ((Resultados $e) -join ',')
}

$Pruebas['25 culpable (g): sin -Desde todo sigue igual; -Deshacer sin -Desde y un -Desde que no vale paran antes de gastar nada'] = {
  $e = Nuevo-Escenario 'culpable-g' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $h = Historia $e 0 1
  $r = Prueba $e @('-Deshacer')
  Igual '-Deshacer sin -Desde sale con 1' 1 $r.Codigo
  Comprueba 'y dice que solo vale con -Desde' ($r.Salida -match '-Deshacer solo vale con -Desde') (Cola $r.Salida)
  $r = Prueba $e @('-Desde', 'este-commit-no-existe')
  Igual 'un -Desde que no es un commit sale con 1' 1 $r.Codigo
  Comprueba 'y lo nombra' ($r.Salida -match 'este-commit-no-existe') (Cola $r.Salida)
  $ajeno = Commit-En $e.Migrado 'otro.txt' "otro`n" 'commit de main, que no esta en la rama de rescate'
  $r = Prueba $e @('-Desde', $ajeno)
  Igual 'un -Desde que no esta en la rama que se prueba sale con 1' 1 $r.Codigo
  Comprueba 'y dice que no esta en su historia' ($r.Salida -match 'no esta en la historia') (Cola $r.Salida)
  Igual 'sin llamar a Copilot' 0 @(Llamadas $e).Count
  Comprueba 'sin crear las copias' (-not (Test-Path -LiteralPath $e.CopiaOrig) -and -not (Test-Path -LiteralPath $e.CopiaMig))
  $r = Prueba $e
  Igual 'sin -Desde sale con 0' 0 $r.Codigo
  Comprueba 'y el resultado no lleva la clave culpables' (@((Lee-Json $e.Json).PSObject.Properties.Name) -notcontains 'culpables')
  Igual 'ni se ejecuta el migrado una vez de mas' 1 (Ejecuciones-Mig $e 'caso-01')
  $r = Prueba $e @('-Desde', $h.Desde)
  Igual 'con -Desde y nada distinto sale con 0' 0 $r.Codigo
  Comprueba 'dice que no hay casos distintos que buscar' ($r.Salida -match 'no hay casos distintos') (Cola $r.Salida)
  Igual 'culpables vacio' 0 @(Culpables $e).Count
  Comprueba 'pero la clave esta' (@((Lee-Json $e.Json).PSObject.Properties.Name) -contains 'culpables')
}

$Pruebas['26 culpable (h): la busqueda y el revert no llaman nunca a Copilot (arnes y casos ya guardados)'] = {
  $e = Nuevo-Escenario 'culpable-h' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') })
  $h = Historia $e 3
  $r = Prueba $e
  Igual 'la primera vez, sin -Desde, sale con 2' 2 $r.Codigo
  $n = @(Llamadas $e).Count
  Igual 'cuatro llamadas: dos arneses y dos casos' 4 $n
  $r = Prueba $e @('-Desde', $h.Desde, '-Deshacer')
  Igual 'con -Desde y -Deshacer sale con 0' 0 $r.Codigo
  Igual 'sin ninguna llamada nueva a Copilot' $n @(Llamadas $e).Count
  Comprueba 'y deshizo el commit' ((GitEn $e.Wt @('log', '-1', '--format=%s')) -like 'Revert *') (GitEn $e.Wt @('log', '-1', '--format=%s'))
}

# M20b: un commit donde el caso no se pudo ejecutar no es ni bueno ni malo: se salta, como git bisect skip. Si solo quedan commits saltados
# antes del malo, no hay culpable claro y no se deshace nada (antes, ese commit contaba como malo y se daba por culpable).
$Pruebas['27 culpable (i): un commit en el que no se puede ejecutar el caso se salta: si solo quedan ese y el siguiente, no se da culpable y el mensaje lo dice'] = {
  $e = Nuevo-Escenario 'culpable-i' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') })
  $desde = GitEn $e.Wt @('rev-parse', 'HEAD')
  $c1 = Commit-En $e.Wt 'notas/paso-1.txt' "nota 1`n" 'nota del paso 1'
  $c2 = Commit-En $e.Wt 'notas/paso-2.txt' "nota 2`n" 'nota del paso 2'
  $c3 = Commit-En $e.Wt 'src/main/java/com/acme/nuevo/Roto.java' "package com.acme.nuevo;`n// NO_COMPILA`n" 'mete una clase que no compila'
  [void](GitEn $e.Wt @('rm', '-q', 'src/main/java/com/acme/nuevo/Roto.java'))
  Escribe $e.Wt 'regla.txt' "minimo=5.01`n"
  [void](GitEn $e.Wt @('add', '--', 'regla.txt'))
  [void](GitEn $e.Wt @('commit', '-q', '-m', 'quita la clase y cambia el limite'))
  $c4 = GitEn $e.Wt @('rev-parse', 'HEAD')
  $c5 = Commit-En $e.Wt 'notas/paso-5.txt' "nota 5`n" 'nota del paso 5'
  $r = Prueba $e @('-Desde', $desde)
  Igual 'sale con 2' 2 $r.Codigo
  Comprueba 'no da por culpable al que no compila ni al siguiente' ($r.Salida -notmatch 'se rompe en') (Cola $r.Salida)
  Comprueba 'dice que es uno de los dos' ($r.Salida.Contains((Corto $c3)) -and $r.Salida.Contains((Corto $c4)) -and $r.Salida -match 'no se puede decir') (Cola $r.Salida)
  Comprueba 'y que en uno no se pudo ejecutar el caso, con lo que dijo Maven' ($r.Salida -match 'no se pudo ejecutar' -and $r.Salida -match 'simbolo de mentira') (Cola $r.Salida)
  Igual 'culpables vacio' 0 @(Culpables $e).Count
}

$Pruebas['28 culpable (j): el culpable es un merge: no se deshace y se dice'] = {
  $e = Nuevo-Escenario 'culpable-j' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') })
  $desde = GitEn $e.Wt @('rev-parse', 'HEAD')
  [void](GitEn $e.Wt @('checkout', '-q', '-b', 'lado'))
  [void](Commit-En $e.Wt 'regla.txt' "minimo=5.01`n" 'limite en la rama lado')
  [void](GitEn $e.Wt @('checkout', '-q', 'rescate/main-1'))
  [void](Commit-En $e.Wt 'notas/uno.txt' "uno`n" 'nota')
  [void](GitEn $e.Wt @('merge', '-q', '--no-ff', '-m', 'une la rama lado', 'lado'))
  $merge = GitEn $e.Wt @('rev-parse', 'HEAD')
  $r = Prueba $e @('-Desde', $desde, '-Deshacer')
  Igual 'sale con 2' 2 $r.Codigo
  Comprueba 'el culpable es el merge' ($r.Salida.Contains("se rompe en $(Corto $merge) (une la rama lado)")) (Cola $r.Salida)
  Comprueba 'dice que no lo deshace por ser un merge' ($r.Salida -match 'No deshago' -and $r.Salida -match 'es un commit de merge') (Cola $r.Salida)
  Igual 'el HEAD queda en el merge' $merge (GitEn $e.Wt @('rev-parse', 'HEAD'))
}

$Pruebas['29 culpable (l): sin worktree de rescate se busca y se deshace en la carpeta del migrado, y la huella lo admite'] = {
  $e = Nuevo-Escenario 'culpable-l' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') })
  [void](GitEn $e.Migrado @('worktree', 'remove', '--force', $e.Wt))
  $h = Historia $e 3 5 $e.Migrado
  $r = Prueba $e @('-Desde', $h.Desde, '-Deshacer')
  Igual 'sale con 0' 0 $r.Codigo
  Comprueba 'el culpable es el 3.o de main' ($r.Salida.Contains("se rompe en $(Corto $h.Commits[2]) (cambia el limite del paso 3)")) (Cola $r.Salida)
  Igual 'un solo commit nuevo en la carpeta del migrado, encima del ultimo' $h.Commits[4] (GitEn $e.Migrado @('rev-parse', 'HEAD~1'))
  Comprueba 'que es el Revert' ((GitEn $e.Migrado @('log', '-1', '--format=%s')) -like 'Revert *') (GitEn $e.Migrado @('log', '-1', '--format=%s'))
  Igual 'sin cambios sin commit' '' (GitEn $e.Migrado @('status', '--porcelain'))
  Comprueba 'y la prueba no dice que han cambiado las carpetas' ($r.Salida -notmatch 'Ha cambiado durante la prueba') (Cola $r.Salida)
}

$Pruebas['30 culpable (m): dos casos rotos por commits distintos: se deshacen del mas nuevo al mas viejo (al reves daria conflicto)'] = {
  $e = Nuevo-Escenario 'culpable-m' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00 LATIN') })
  $desde = GitEn $e.Wt @('rev-parse', 'HEAD')
  $c1 = Commit-En $e.Wt 'notas/paso-1.txt' "nota 1`n" 'nota del paso 1'
  $c2 = Commit-En $e.Wt 'regla.txt' "minimo=5.01`n" 'cambia el limite'
  $c3 = Commit-En $e.Wt 'notas/paso-3.txt' "nota 3`n" 'nota del paso 3'
  $c4 = Commit-En $e.Wt 'regla.txt' "minimo=5.01`nmayus=si`n" 'pasa la enie a mayuscula'
  $c5 = Commit-En $e.Wt 'notas/paso-5.txt' "nota 5`n" 'nota del paso 5'
  $r = Prueba $e @('-Desde', $desde, '-Deshacer')
  Igual 'sale con 0' 0 $r.Codigo
  $c = @(Culpables $e)
  Igual 'el caso 1 lo rompe el 2.o commit y el caso 2, el 4.o' "$c2,$c4" ((@($c | ForEach-Object { $_.commit })) -join ',')
  Igual 'los dos deshechos' 'True,True' ((@($c | ForEach-Object { "$($_.deshecho)" })) -join ',')
  Igual 'dos commits nuevos, encima del ultimo' 2 (GitEn $e.Wt @('rev-list', '--count', "$c5..HEAD"))
  Igual 'el primero deshecho es el mas nuevo' 'Revert "pasa la enie a mayuscula"' (GitEn $e.Wt @('log', '-1', '--format=%s', 'HEAD~1'))
  Igual 'y el ultimo, el mas viejo' 'Revert "cambia el limite"' (GitEn $e.Wt @('log', '-1', '--format=%s'))
  Igual 'los dos casos quedan iguales' 'igual,igual' ((Resultados $e) -join ',')
}

$Pruebas['31 culpable (n): si el culpable es el ultimo commit no se ejecuta otra vez (ya se comparo), y -Desde igual al HEAD dice que ya era distinto sin ejecutar nada'] = {
  $e = Nuevo-Escenario 'culpable-n' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') })
  $h = Historia $e 5
  $r = Prueba $e @('-Desde', $h.Desde)
  Igual 'sale con 2' 2 $r.Codigo
  Comprueba 'el culpable es el ultimo' ($r.Salida.Contains("se rompe en $(Corto $h.Commits[4]) (cambia el limite del paso 5).")) (Cola $r.Salida)
  Igual 'la normal, -Desde y dos mas de la biseccion (el ultimo no se repite)' 4 (Ejecuciones-Mig $e 'caso-01')
  $r = Prueba $e @('-Desde', $h.Commits[4])
  Igual 'con -Desde igual al HEAD sale con 2' 2 $r.Codigo
  Comprueba 'dice que ya era distinto' ($r.Salida.Contains("El caso cargaJob/caso-01 ya era distinto en $(Corto $h.Commits[4])")) (Cola $r.Salida)
  Igual 'y solo se ejecuta la comparacion normal (una mas)' 5 (Ejecuciones-Mig $e 'caso-01')
}

# Prueba con el Maven falso de culpable-mvn.ps1, que toca la carpeta de rescate ($Modo: ver ese fichero) en medio de la prueba.
function Prueba-Con-Toque($E, [string]$Modo, [string[]]$A) {
  $aj = [ordered]@{ CopilotExe = (Join-Path $falsos 'copilot-local.ps1'); MvnExe = (Join-Path $falsos 'culpable-mvn.ps1'); SegundosPorLlamada = 60 }
  Escribe $E.Home 'ajustes.json' (ConvertTo-Json -InputObject $aj)
  $env:RESCATE_TOCA = $E.Wt + '|' + $Modo
  try { return (Prueba $E $A) }
  finally { $env:RESCATE_TOCA = '' }
}

$Pruebas['32 culpable (k): -Deshacer no tapa otros cambios en la carpeta de rescate (un commit ajeno, un fichero ajeno despues del revert o un reset ajeno): la huella los ve'] = {
  $e = Nuevo-Escenario 'culpable-k1' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') })
  $h = Historia $e 3
  $r = Prueba-Con-Toque $e 'commit' @('-Desde', $h.Desde, '-Deshacer')
  Igual 'con un commit ajeno en medio sale con 1' 1 $r.Codigo
  Comprueba 'y dice que ha cambiado una carpeta' ($r.Salida -match 'Ha cambiado durante la prueba') (Cola $r.Salida)
  Comprueba 'el revert si se hizo (esta encima del commit ajeno)' ((GitEn $e.Wt @('log', '-1', '--format=%s')) -like 'Revert *') (GitEn $e.Wt @('log', '-1', '--format=%s'))
  $e = Nuevo-Escenario 'culpable-k2' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') })
  $h = Historia $e 3
  $r = Prueba-Con-Toque $e 'fichero-tras-revert' @('-Desde', $h.Desde, '-Deshacer')
  Igual 'con un fichero ajeno aparecido despues del revert sale con 1' 1 $r.Codigo
  Comprueba 'y dice que ha cambiado una carpeta' ($r.Salida -match 'Ha cambiado durante la prueba') (Cola $r.Salida)
  Comprueba 'el fichero ajeno esta (lo dejo el falso, no el script)' (Test-Path -LiteralPath (Get-Ruta $e.Wt 'ajeno.txt'))
  $e = Nuevo-Escenario 'culpable-k3' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') })
  $h = Historia $e 3
  $r = Prueba-Con-Toque $e 'reset' @('-Desde', $h.Desde, '-Deshacer')
  Igual 'con un reset ajeno (un commit menos, y el revert encima de otro) sale con 1' 1 $r.Codigo
  Comprueba 'y dice que ha cambiado una carpeta' ($r.Salida -match 'Ha cambiado durante la prueba') (Cola $r.Salida)
}

# Prueba con el Maven falso de culpable-mvn.ps1 y un tope de 0.05 min (3 s) en el ajustes.json del escenario: un commit con
# cuelga.txt en la raiz cuelga a Maven. Devuelve lo de Prueba, mas Segundos (lo que ha tardado) y Pids (donde apunta lo suyo).
function Prueba-Con-Cuelgue($E, [string[]]$A) {
  $aj = [ordered]@{ CopilotExe = (Join-Path $falsos 'copilot-local.ps1'); MvnExe = (Join-Path $falsos 'culpable-mvn.ps1'); SegundosPorLlamada = 60; MinutosMaven = 0.05 }
  Escribe $E.Home 'ajustes.json' (ConvertTo-Json -InputObject $aj)
  $pids = Join-Path $E.Raiz 'pids'
  $env:RESCATE_MVN_PIDS = $pids
  $reloj = [System.Diagnostics.Stopwatch]::StartNew()
  try { $r = Prueba $E $A }
  finally { $env:RESCATE_MVN_PIDS = '' }
  return [pscustomobject]@{ Codigo = $r.Codigo; Salida = $r.Salida; Segundos = $reloj.Elapsed.TotalSeconds; Pids = $pids }
}

$Pruebas['33 culpable (o): un commit en el que Maven se cuelga (pasa del tope) se salta: con -Deshacer no se revierte nada y el mensaje dice lo del tope'] = {
  $e = Nuevo-Escenario 'culpable-o' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') })
  $desde = GitEn $e.Wt @('rev-parse', 'HEAD')
  $c1 = Commit-En $e.Wt 'notas/paso-1.txt' "nota 1`n" 'nota del paso 1'
  $c2 = Commit-En $e.Wt 'notas/paso-2.txt' "nota 2`n" 'nota del paso 2'
  $c3 = Commit-En $e.Wt 'cuelga.txt' "el job no acaba`n" 'un lector que devuelve una lista vacia y el job no acaba'
  [void](GitEn $e.Wt @('rm', '-q', 'cuelga.txt'))
  Escribe $e.Wt 'regla.txt' "minimo=5.01`n"
  [void](GitEn $e.Wt @('add', '--', 'regla.txt'))
  [void](GitEn $e.Wt @('commit', '-q', '-m', 'quita el bucle y cambia el limite'))
  $c5 = Commit-En $e.Wt 'notas/paso-5.txt' "nota 5`n" 'nota del paso 5'
  $r = Prueba-Con-Cuelgue $e @('-Desde', $desde, '-Deshacer')
  Igual 'sale con 2 (no se deshace nada: sigue distinto)' 2 $r.Codigo
  Comprueba 'no da por culpable al que cuelga a Maven ni al siguiente' ($r.Salida -notmatch 'se rompe en') (Cola $r.Salida)
  Comprueba 'y el mensaje dice que ahi no se pudo ejecutar, por el tope de Maven' ($r.Salida -match 'no se pudo ejecutar' -and $r.Salida -match 'se ha pasado del tope de 0\.05 min') (Cola $r.Salida)
  Igual 'culpables vacio' 0 @(Culpables $e).Count
  Igual 'la rama de rescate queda en su ultimo commit, sin ningun revert' $c5 (GitEn $e.Wt @('rev-parse', 'HEAD'))
  Comprueba-Tope $r.Pids $r.Segundos 60 (Registro-Del-Tope $r.Salida)
}

$Pruebas['34 culpable (p): la busqueda recorre solo la primera linea de la rama (--first-parent): un merge con dos commits laterales cuenta como uno'] = {
  $e = Nuevo-Escenario 'culpable-p' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') })
  $desde = GitEn $e.Wt @('rev-parse', 'HEAD')
  $c1 = Commit-En $e.Wt 'notas/paso-1.txt' "nota 1`n" 'nota del paso 1'
  [void](GitEn $e.Wt @('checkout', '-q', '-b', 'lado'))
  $s1 = Commit-En $e.Wt 'notas/lado-1.txt' "lado 1`n" 'primer commit de la rama lateral'
  $s2 = Commit-En $e.Wt 'notas/lado-2.txt' "lado 2`n" 'segundo commit de la rama lateral'
  [void](GitEn $e.Wt @('checkout', '-q', 'rescate/main-1'))
  $c2 = Commit-En $e.Wt 'notas/paso-2.txt' "nota 2`n" 'nota del paso 2'
  [void](GitEn $e.Wt @('merge', '-q', '--no-ff', '-m', 'une la rama lateral', 'lado'))
  $m = GitEn $e.Wt @('rev-parse', 'HEAD')
  $c4 = Commit-En $e.Wt 'regla.txt' "minimo=5.01`n" 'cambia el limite'
  $c5 = Commit-En $e.Wt 'notas/paso-5.txt' "nota 5`n" 'nota del paso 5'
  $r = Prueba $e @('-Desde', $desde)
  Igual 'sale con 2' 2 $r.Codigo
  Comprueba 'cuenta cinco commits (c1, c2, el merge, c4, c5), no siete' ($r.Salida -match '\(5 commits despues de ') (Cola $r.Salida)
  Comprueba 'ningun commit de la rama lateral sale como probado' ($r.Salida -notmatch "en $(Corto $s1)" -and $r.Salida -notmatch "en $(Corto $s2)") (Cola $r.Salida)
  Comprueba 'el culpable es el cuarto de la primera linea' ($r.Salida.Contains("se rompe en $(Corto $c4) (cambia el limite).")) (Cola $r.Salida)
  Igual 'sin sumar a la busqueda mas ejecuciones que Desde y dos del medio' 3 ((Ejecuciones-Mig $e 'caso-01') - 1)
}

# ===================== M18: el arnes que vale aunque la llamada falle, y lo que se le pide a la IA =====================
# Ajustes del escenario con el Copilot y el Maven de mentira de este grupo (arnes-copilot.ps1 y arnes-mvn.ps1). Las llamadas de arnes
# pasan del tope a los 10 s (SegundosArnes). $Mas: otras claves de ajustes.json (por ejemplo SegundosTestArnes).
function Ajustes-Arnes($E, [hashtable]$Mas = @{}) {
  $aj = [ordered]@{ CopilotExe = (Join-Path $falsos 'arnes-copilot.ps1'); MvnExe = (Join-Path $falsos 'arnes-mvn.ps1'); SegundosPorLlamada = 60; SegundosArnes = 10 }
  foreach ($k in $Mas.Keys) { $aj[$k] = $Mas[$k] }
  Escribe $E.Home 'ajustes.json' (ConvertTo-Json -InputObject $aj)
}

# El registro de la llamada $N de la tarea del arnes del $Repo ('original' o 'migrado'): su prompt, y lo que dijo Copilot.
function Registro-Arnes($E, [string]$Repo, [int]$N) {
  $f = Get-Ruta $E.Local "registros/arnes-$Repo-$N.log"
  if (-not (Test-Path -LiteralPath $f)) { return '' }
  return [System.IO.File]::ReadAllText($f)
}

function Tarea-Arnes($E, [string]$Repo) { return (Lee-Json (Get-Ruta $E.Local "tareas/arnes-$Repo.json")) }

# Las lineas de mvn.log (las que apunta mvn-local.ps1) que casan con $Patron.
function Mavens-Con($E, [string]$Patron) {
  $f = Join-Path $E.Llamadas 'mvn.log'
  if (-not (Test-Path -LiteralPath $f)) { return @() }
  return @([System.IO.File]::ReadAllLines($f) | Where-Object { $_ -match $Patron })
}

$Pruebas['41 m18 arnes (a): la llamada se pasa del tope pero deja un test que vale: el arnes vale, sin reintento, y avisa'] = {
  $e = Nuevo-Escenario 'm18-a' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  Ajustes-Arnes $e
  $r = Prueba $e @() 'colgado-bueno:arnes-original'
  Igual 'sale con 0' 0 $r.Codigo
  $t = Tarea-Arnes $e 'original'
  Igual 'la tarea del arnes del original queda hecha' 'hecha' $t.estado
  Igual 'con una sola llamada (sin reintento)' 1 $t.intentos
  Comprueba 'no hay registro de una segunda llamada' (-not (Test-Path -LiteralPath (Get-Ruta $e.Local 'registros/arnes-original-2.log')))
  Comprueba 'el registro de la primera dice que se agoto el tiempo' ((Registro-Arnes $e 'original' 1) -match 'tiempo agotado')
  Comprueba 'el arnes del original queda guardado' (Test-Path -LiteralPath (Get-Ruta $e.Local 'arnes/original/src/test/java/com/acme/viejo/PruebaLocalTest.java'))
  Comprueba 'la consola avisa de que usa el test que dejo' ($r.Salida.Contains('La IA se ha pasado del tiempo, pero el test que ha dejado vale: lo uso.')) (Cola $r.Salida)
  Comprueba 'y no dice que lo rechaza' ($r.Salida -notmatch 'Arnes del original rechazado') (Cola $r.Salida)
  Igual 'los dos casos salen iguales' 'igual,igual' ((Resultados $e) -join ',')
}

$Pruebas['42 m18 arnes (a2): la llamada sale con codigo distinto de 0 pero deja un test que vale: el arnes vale y el aviso dice que ha fallado'] = {
  $e = Nuevo-Escenario 'm18-a2' ([ordered]@{ cargaJob = @('importe=10.00') })
  Ajustes-Arnes $e
  $r = Prueba $e @() 'sale-mal-bueno:arnes-original'
  Igual 'sale con 0' 0 $r.Codigo
  $t = Tarea-Arnes $e 'original'
  Igual 'la tarea del arnes del original queda hecha, con una llamada' 'hecha/1' "$($t.estado)/$($t.intentos)"
  Comprueba 'la consola avisa de que ha fallado y usa el test' ($r.Salida.Contains('La IA ha fallado (codigo 3), pero el test que ha dejado vale: lo uso.')) (Cola $r.Salida)
}

$Pruebas['43 m18 arnes (b): la llamada se pasa del tope y el test que deja no compila: el motivo lleva el tiempo agotado y el error de Maven, y el segundo prompt lo recibe'] = {
  $e = Nuevo-Escenario 'm18-b' ([ordered]@{ cargaJob = @('importe=10.00') })
  Ajustes-Arnes $e
  $r = Prueba $e @() 'colgado-malo:arnes-original'
  Igual 'sale con 0 (el segundo intento vale)' 0 $r.Codigo
  Comprueba 'la consola rechaza el primer arnes con el tiempo agotado' ($r.Salida.Contains('Arnes del original rechazado: Tiempo agotado: la llamada se paso del tope y se mato. Ademas, lo que dejo escrito no vale: El test no compila')) (Cola $r.Salida)
  $p2 = Registro-Arnes $e 'original' 2
  Comprueba 'el segundo prompt lleva el tiempo agotado' ($p2.Contains('Tiempo agotado: la llamada se paso del tope y se mato. Ademas, lo que dejo escrito no vale:')) $p2
  Comprueba 'y el error concreto de Maven' ($p2 -match 'simbolo de mentira no encontrado') $p2
  Igual 'la tarea queda hecha en el segundo intento' 'hecha/2' "$((Tarea-Arnes $e 'original').estado)/$((Tarea-Arnes $e 'original').intentos)"
}

$Pruebas['44 m18 arnes (c): la llamada se pasa del tope y no escribe nada: el motivo es solo el tiempo agotado, como hoy'] = {
  $e = Nuevo-Escenario 'm18-c' ([ordered]@{ cargaJob = @('importe=10.00') })
  Ajustes-Arnes $e
  $r = Prueba $e @() 'colgado-nada:arnes-original'
  Igual 'sale con 0 (el segundo intento vale)' 0 $r.Codigo
  Comprueba 'la consola rechaza el primer arnes solo con el tiempo agotado' ($r.Salida -match '(?m)Arnes del original rechazado: Tiempo agotado: la llamada se paso del tope y se mato\.\r?$') (Cola $r.Salida)
  $p2 = Registro-Arnes $e 'original' 2
  Comprueba 'el segundo prompt lleva el tiempo agotado' ($p2.Contains('Tiempo agotado: la llamada se paso del tope y se mato.')) $p2
  Comprueba 'sin el Ademas de un test que no vale' ($p2 -notmatch 'Ademas, lo que dejo escrito') $p2
  Igual 'la tarea queda hecha en el segundo intento' 'hecha/2' "$((Tarea-Arnes $e 'original').estado)/$((Tarea-Arnes $e 'original').intentos)"
}

$Pruebas['45 m18 arnes (d): el prompt lleva la lista cerrada de comandos de Maven y los segundos de SegundosTestArnes'] = {
  $e = Nuevo-Escenario 'm18-d' ([ordered]@{ cargaJob = @('importe=10.00') })
  Ajustes-Arnes $e @{ SegundosTestArnes = 77 }
  $r = Prueba $e
  Igual 'sale con 0' 0 $r.Codigo
  foreach ($repo in @('original', 'migrado')) {
    $p = Registro-Arnes $e $repo 1
    Comprueba "el prompt del $repo lleva mvn -q test-compile" ($p.Contains('`mvn -q test-compile`')) $p
    Comprueba "y el mvn test del caso con el tope de 77 s" ($p.Contains('`mvn test -Dtest=PruebaLocalTest -Dprueba.local.caso=<caso> -Dsurefire.timeout=77`')) $p
    Comprueba 'y dice que, si se pasa de 77 s, el job intenta conectar con algo de verdad' ($p -match 'se pasa de 77 s' -and $p -match 'conectar con algo de verdad') $p
    foreach ($x in @('mvn test` sin `-Dtest', 'mvn verify', 'mvn package', 'mvn install', 'mvn spring-boot:run', 'java -jar')) {
      Comprueba "y prohibe $x" ($p.Contains($x)) $p
    }
    Comprueba 'y no deja ninguna clave sin sustituir' ($p -notmatch '\{\{\w+\}\}') $p
    Comprueba 'ni la frase de lanzar mvn sin limite' (-not $p.Contains('Puedes lanzar `mvn` para probarlo')) $p
  }
}

$Pruebas['46 m18 arnes (e): el mvn test del caso vacio lleva -Dsurefire.timeout; los casos de verdad, no'] = {
  $e = Nuevo-Escenario 'm18-e1' ([ordered]@{ cargaJob = @('importe=10.00') })
  Ajustes-Arnes $e
  $r = Prueba $e
  Igual 'sale con 0' 0 $r.Codigo
  $vacios = @(Mavens-Con $e 'Dprueba\.local\.caso=vacio')
  Comprueba 'hay un mvn test del caso vacio por arnes' ($vacios.Count -ge 2) ($vacios -join ' // ')
  Comprueba 'todos con -Dsurefire.timeout=300 (el valor por defecto)' (@($vacios | Where-Object { $_ -notmatch '-Dsurefire\.timeout=300( |$)' }).Count -eq 0) ($vacios -join ' // ')
  $reales = @(Mavens-Con $e 'Dprueba\.local\.job=')
  Comprueba 'hay ejecuciones de casos de verdad' ($reales.Count -ge 3) ($reales -join ' // ')
  Comprueba 'y ninguna lleva -Dsurefire.timeout' (@($reales | Where-Object { $_ -match 'surefire\.timeout' }).Count -eq 0) ($reales -join ' // ')
}

$Pruebas['47 m18 arnes (e2): si Maven dice que el fork se paso de tiempo, el motivo dice que el job intenta conectar con algo de verdad'] = {
  $e = Nuevo-Escenario 'm18-e2' ([ordered]@{ cargaJob = @('importe=10.00') })
  Ajustes-Arnes $e
  $env:RESCATE_ARNES_SUREFIRE = 'si'
  try { $r = Prueba $e }
  finally { $env:RESCATE_ARNES_SUREFIRE = '' }
  Igual 'sale con 1 (el arnes del original queda atascado)' 1 $r.Codigo
  $motivo = 'Con un caso vacio, el test no termina en 300 s: el job intenta conectar con algo de verdad (base de datos, SFTP, correo, HTTP). Simulalo en el test.'
  Comprueba 'el motivo del atasco es el concreto' ($r.Salida.Contains($motivo)) (Cola $r.Salida)
  Comprueba 'y el segundo prompt lo lleva' ((Registro-Arnes $e 'original' 2).Contains($motivo))
  Comprueba 'sin el texto de que no ha dejado estado.txt' ($r.Salida -notmatch 'no ha dejado estado\.txt') (Cola $r.Salida)
}

$Pruebas['48 m18 arnes (f): el arnes atascado dice donde esta el registro de la ultima llamada'] = {
  $e = Nuevo-Escenario 'm18-f' ([ordered]@{ cargaJob = @('importe=10.00') })
  Ajustes-Arnes $e
  $r = Prueba $e @() 'arnes-no-compila:arnes-original'
  Igual 'sale con 1' 1 $r.Codigo
  $reg = Get-Ruta $e.Local 'registros/arnes-original-2.log'
  Comprueba 'el registro de la ultima llamada existe' (Test-Path -LiteralPath $reg) $reg
  Comprueba 'el mensaje de atascado lleva su ruta' ($r.Salida.Contains($reg)) (Cola $r.Salida)
  Comprueba 'en su propia linea: lo que dijo Copilot en la ultima llamada esta ahi, para abrirlo o mandarlo' ($r.Salida.Contains("Lo que dijo Copilot en la ultima llamada esta en ${reg}: abrelo o mandalo.")) (Cola $r.Salida)
  $linea = @($r.Salida -split "`n" | Where-Object { $_.Contains('ha quedado atascado') -or $_.Contains('Estoy ejecutando prueba-local.ps1') })
  Comprueba 'tambien el texto para pegar en Copilot' (@($linea | Where-Object { $_.Contains('Estoy ejecutando prueba-local.ps1') -and $_.Contains($reg) }).Count -eq 1) (Cola $r.Salida)
}

$Pruebas['49 m18 arnes (g): el registro de una llamada matada por el tope guarda lo que Copilot escribio hasta entonces'] = {
  $e = Nuevo-Escenario 'm18-g' ([ordered]@{ cargaJob = @('importe=10.00') })
  Ajustes-Arnes $e
  $r = Prueba $e @() 'colgado-parcial:arnes-original'
  Igual 'sale con 0 (el segundo intento vale)' 0 $r.Codigo
  $l = Registro-Arnes $e 'original' 1
  Comprueba 'el registro dice que la llamada se paso del tope' ($l -match '# salida \(codigo -?\d+, \d+ s, tiempo agotado\)') $l
  Comprueba 'y lleva su salida parcial' ($l.Contains('salida parcial: leyendo el job cargaRecibosJob')) $l
}

$Pruebas['50 m18 arnes (k): la llamada se pasa del tope y su test no vale: el test se queda en la copia, el reintento sigue desde ahi y su prompt lo dice'] = {
  $e = Nuevo-Escenario 'm18-k' ([ordered]@{ cargaJob = @('importe=10.00') })
  Ajustes-Arnes $e
  $r = Prueba $e @() 'colgado-malo:arnes-original'
  Igual 'sale con 0 (el segundo intento vale)' 0 $r.Codigo
  Igual 'la tarea queda hecha en el segundo intento' 'hecha/2' "$((Tarea-Arnes $e 'original').estado)/$((Tarea-Arnes $e 'original').intentos)"
  $test = Get-Ruta $e.Local 'arnes/original/src/test/java/com/acme/viejo/PruebaLocalTest.java'
  Comprueba 'la 2.a llamada encontro el test de la 1.a (lo arreglo en vez de escribirlo de cero)' ((Test-Path -LiteralPath $test) -and (Lee $e.Local 'arnes/original/src/test/java/com/acme/viejo/PruebaLocalTest.java').Contains('ARREGLADO')) $test
  $p2 = Registro-Arnes $e 'original' 2
  Comprueba 'su prompt dice que el intento se corto por tiempo y que siga desde lo escrito' ($p2 -match 'Tu intento anterior se cort. por tiempo\. Lo que escribiste sigue en la copia: contin.a desde ah., no empieces de cero\.') $p2
  Comprueba 'despues va el motivo concreto' ($p2 -match '(?s)no empieces de cero\..*Tiempo agotado: la llamada se paso del tope y se mato\. Ademas, lo que dejo escrito no vale:.*simbolo de mentira no encontrado') $p2
  Comprueba 'y no dice que lo escrito se ha deshecho' ($p2 -notmatch 'se ha deshecho') $p2
  Comprueba 'ni deja marcas de la plantilla en el prompt' ($p2 -notmatch '<!--no-->|\{\{') $p2
}

$Pruebas['51 m18 arnes (k2): si la llamada no se corto por tiempo (sale con codigo 3) y su test no vale, se deshace todo como hoy'] = {
  $e = Nuevo-Escenario 'm18-k2' ([ordered]@{ cargaJob = @('importe=10.00') })
  Ajustes-Arnes $e
  $r = Prueba $e @() 'sale-mal-malo:arnes-original'
  Igual 'sale con 0 (el segundo intento vale)' 0 $r.Codigo
  $test = Get-Ruta $e.Local 'arnes/original/src/test/java/com/acme/viejo/PruebaLocalTest.java'
  Comprueba 'la 2.a llamada no encontro el test de la 1.a (lo escribio entero)' ((Test-Path -LiteralPath $test) -and -not (Lee $e.Local 'arnes/original/src/test/java/com/acme/viejo/PruebaLocalTest.java').Contains('ARREGLADO')) $test
  $p2 = Registro-Arnes $e 'original' 2
  Comprueba 'su prompt dice que lo escrito se ha deshecho' ($p2 -match 'se ha deshecho') $p2
  Comprueba 'y no dice que el intento se corto por tiempo' ($p2 -notmatch 'se cort. por tiempo') $p2
  Comprueba 'ni deja marcas de la plantilla en el prompt' ($p2 -notmatch '<!--no-->|\{\{') $p2
  Comprueba 'el motivo lleva el codigo de salida y el error de Maven' ($p2 -match 'Copilot salio con codigo 3' -and $p2 -match 'simbolo de mentira no encontrado') $p2
}

$Pruebas['52 m18 arnes (e3): si Maven dice lo de Surefire 2.x (timeout or other error in the fork), el motivo tambien es el concreto'] = {
  $e = Nuevo-Escenario 'm18-e3' ([ordered]@{ cargaJob = @('importe=10.00') })
  Ajustes-Arnes $e
  $env:RESCATE_ARNES_SUREFIRE = '2x'
  try { $r = Prueba $e }
  finally { $env:RESCATE_ARNES_SUREFIRE = '' }
  Igual 'sale con 1 (el arnes del original queda atascado)' 1 $r.Codigo
  $motivo = 'Con un caso vacio, el test no termina en 300 s: el job intenta conectar con algo de verdad (base de datos, SFTP, correo, HTTP). Simulalo en el test.'
  Comprueba 'el motivo del atasco es el concreto' ($r.Salida.Contains($motivo)) (Cola $r.Salida)
  Comprueba 'sin el texto de que no ha dejado estado.txt' ($r.Salida -notmatch 'no ha dejado estado\.txt') (Cola $r.Salida)
}

$Pruebas['53 m18 arnes (k3): en el ULTIMO intento una llamada cortada por tiempo con un test que no vale lo deshace todo: el test no queda en la copia y la tarea queda atascada'] = {
  $e = Nuevo-Escenario 'm18-k3' ([ordered]@{ cargaJob = @('importe=10.00') })
  Ajustes-Arnes $e
  $r = Prueba $e @() 'colgado-siempre:arnes-original'
  Igual 'sale con 1 (el arnes del original queda atascado)' 1 $r.Codigo
  $t = Tarea-Arnes $e 'original'
  Igual 'la tarea queda atascada tras dos intentos' 'atascada/2' "$($t.estado)/$($t.intentos)"
  Comprueba 'las dos llamadas se pasaron del tope' ((Registro-Arnes $e 'original' 1) -match 'tiempo agotado' -and (Registro-Arnes $e 'original' 2) -match 'tiempo agotado')
  Comprueba 'el test de la ultima llamada ya no esta en la copia' (-not (Test-Path -LiteralPath (Get-Ruta $e.CopiaOrig 'src/test/java/com/acme/viejo/PruebaLocalTest.java'))) (Cola $r.Salida)
  Igual 'la copia queda como su base: sin cambios' '' (GitEn $e.CopiaOrig @('status', '--porcelain', '--untracked-files=all', '--', '.', ':(exclude).rescate', ':(exclude)target'))
}

$Pruebas['54 m18 arnes (k4): la llamada cortada escribio un test que no vale (permitido) y toco src/main (prohibido): el script deshace src/main al comprobar y, en la 2.a, el test sigue en la copia'] = {
  $e = Nuevo-Escenario 'm18-k4' ([ordered]@{ cargaJob = @('importe=10.00') })
  Ajustes-Arnes $e
  $r = Prueba $e @() 'colgado-toca-main:arnes-original'
  Igual 'sale con 0 (el segundo intento vale)' 0 $r.Codigo
  $p2 = Registro-Arnes $e 'original' 2
  Comprueba 'el motivo de la 1.a empieza por el fichero de src/main que deshizo' ($p2 -match 'He deshecho lo que tocaste fuera de .*: src/main/java/Tocado\.java\.') $p2
  $f = Join-Path $e.Llamadas 'arnes-original.reintento'
  $v = ''
  if (Test-Path -LiteralPath $f) { $v = ([System.IO.File]::ReadAllLines($f) -join ' ') }
  Igual 'al empezar la 2.a llamada: el test sigue en la copia y src/main/java/Tocado.java no' 'test=True tocado=False' $v
}

# ===================== M20b: lo que no es igual no sale igual, y -Deshacer no deshace a ciegas =====================
# Ajustes del escenario con los falsos de este grupo: m20b-copilot.ps1 (con el guion m20b-sin-entradas: un arnes que no le pasa las entradas
# al job) y m20b-mvn.ps1 (IGNORA_ENTRADAS y las lineas 'reescribe=<texto>=><otro>' de regla.txt: el migrado escribe otro texto).
function Ajustes-M20b($E) {
  $aj = [ordered]@{ CopilotExe = (Join-Path $falsos 'm20b-copilot.ps1'); MvnExe = (Join-Path $falsos 'm20b-mvn.ps1'); SegundosPorLlamada = 60 }
  Escribe $E.Home 'ajustes.json' (ConvertTo-Json -InputObject $aj)
}

# El texto de las funciones $Nombres de un script, para probarlas sin lanzar el script entero.
function Texto-De-Funciones([string]$Ruta, [string[]]$Nombres) {
  $ast = [System.Management.Automation.Language.Parser]::ParseFile($Ruta, [ref]$null, [ref]$null)
  $fs = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $Nombres -contains $n.Name }, $true))
  return (($fs | ForEach-Object { $_.Extent.Text }) -join "`n")
}

# Las funciones del script que leen un fichero para compararlo (Get-LineasNormales y lo que decide por su tipo, M73 (c)): las que necesita cualquier prueba que extraiga Compare-Fichero.
$FnLeer = @('Get-LineasNormales', 'Get-LineasContenido', 'Get-TipoContenido', 'Get-LineasExcel', 'Get-LineasZip', 'Get-LineaBinaria', 'Get-Hash256')

$Pruebas['55 m20b (a, b): una fecha de negocio que no es de hoy y cambia entre el original y el migrado sale distinta; la fecha y hora de hoy con otra hora sale igual'] = {
  $hoy = (Get-Date).ToString('yyyy-MM-dd')
  $e = Nuevo-Escenario 'm20b-fechas' ([ordered]@{ cargaJob = @('importe=10.00 vence=1980-05-12 00:00:00', "importe=10.00 hecho=$hoy 10:00:00") }) 'minimo=5.00' "minimo=5.00`nreescribe=1980-05-12 00:00:00=>1980-05-11 23:00:00`nreescribe=$hoy 10:00:00=>$hoy 11:30:00"
  Ajustes-M20b $e
  $r = Prueba $e
  Igual 'sale con 2 (hay un distinto)' 2 $r.Codigo
  $c = Caso $e 'cargaJob' 'caso-01'
  Igual '(a) la fecha de negocio que cambia de dia sale distinta' 'distinto' $c.resultado
  $d = @($c.diferencias)[0]
  Comprueba '(a) con la linea del original, con la fecha de antes' ("$($d.original)" -match '1980-05-12 00:00:00') "$($d.original)"
  Comprueba '(a) y la del migrado, con la de despues' ("$($d.migrado)" -match '1980-05-11 23:00:00') "$($d.migrado)"
  Igual '(b) la fecha y hora de hoy con otra hora sale igual' 'igual' (Caso $e 'cargaJob' 'caso-02').resultado
  $rel = 'cargaJob/caso-02/ficheros/salida/resultado_' + (Hoy) + '.txt'
  Comprueba '(b) aunque los ficheros no son identicos' ((Lee $e.Local "salidas/original/$rel") -ne (Lee $e.Local "salidas/migrado/$rel"))
}

$Pruebas['56 m20b (c): Get-Hoy da los dias de la ejecucion en hora local y en UTC; una fecha UTC de otro dia sale igual y una de negocio no se toca'] = {
  $f = Join-Path $Dir 'm20b-hoy.ps1'
  $cuerpo = @'
$Inv = [System.Globalization.CultureInfo]::InvariantCulture
$RutasCopia = @()
$off = [System.TimeZoneInfo]::Local.GetUtcOffset([datetime]'2026-11-18T12:00:00').TotalHours
$inicio = [datetime]'2026-11-18T00:30:00'
if ($off -lt 0) { $inicio = [datetime]'2026-11-18T23:30:00' }
$loc = $inicio.Date.ToString('yyyy-MM-dd', $Inv)
$utc = $inicio.ToUniversalTime().Date.ToString('yyyy-MM-dd', $Inv)
$Hoy = @(Get-Hoy $inicio ($inicio.AddHours(1)))
'OFFSET ' + $off
'LOC ' + $loc
'UTC ' + $utc
'HOY ' + (@($Hoy | ForEach-Object { $_.ToString('yyyy-MM-dd', $Inv) } | Sort-Object) -join ',')
'N1 ' + (Get-Normal "x $utc 10:00:00")
'N2 ' + (Get-Normal "x ${loc}T10:00:00.123")
'N3 ' + (Get-Normal 'x 1980-05-12 00:00:00')
'N4 ' + (Get-Normal 'x 2026-11-16 23:45:00')
'N5 ' + (Get-Normal 'a 10:11:12 b')
'N6 ' + (Get-Normal "f_${loc}.txt")
'@
  [System.IO.File]::WriteAllText($f, ((Texto-De-Funciones $Script @('Get-Normal', 'Get-Hoy')) + "`n" + $cuerpo))
  $tzAntes = $env:TZ
  $env:TZ = 'Europe/Madrid'   # en Linux hace que la hora local sea UTC+1; en Windows no vale y se usa la de la maquina
  try { $r = Lanzar $f @() }
  finally { if ($null -eq $tzAntes) { Remove-Item Env:TZ -ErrorAction SilentlyContinue } else { $env:TZ = $tzAntes } }
  $v = @{}
  foreach ($l in @($r.Salida -split "`n")) { if ($l -cmatch '^([A-Z0-9]+) (.*)$') { $v[$Matches[1]] = $Matches[2].TrimEnd() } }
  Comprueba 'los dias de la ejecucion llevan el local y el UTC' ($v['HOY'] -and $v['HOY'].Contains($v['LOC']) -and $v['HOY'].Contains($v['UTC'])) (Cola $r.Salida)
  if ($v['OFFSET'] -and [double]$v['OFFSET'] -ne 0) { Comprueba 'con otra hora que UTC son dos dias distintos' ($v['LOC'] -ne $v['UTC'] -and @($v['HOY'] -split ',').Count -eq 2) "$($v['LOC']) $($v['UTC']) $($v['HOY'])" }
  else { Write-Host '  (esta maquina va en UTC: no se ve la diferencia entre el dia local y el UTC)' }
  Igual 'una fecha y hora UTC de otro dia que el local, pero de la ejecucion, sale igual que una local' 'x <hoy:yyyy-MM-dd><hora>' $v['N1']
  Igual 'con T y fraccion, tambien' 'x <hoy:yyyy-MM-dd><hora>' $v['N2']
  Igual 'una fecha de negocio con hora no se toca' 'x 1980-05-12 00:00:00' $v['N3']
  Igual 'ni otra de hace dias' 'x 2026-11-16 23:45:00' $v['N4']
  Igual 'las horas sueltas se siguen tapando' 'a <hora> b' $v['N5']
  Igual 'la fecha de hoy sola sigue con su marca' 'f_<hoy:yyyy-MM-dd>.txt' $v['N6']
}

$Pruebas['57 m20b (d): todos los casos de un job como el vacio y ninguno distinto: fallo con el detalle, arnes invalidado y el motivo llega a la IA al relanzar'] = {
  $e = Nuevo-Escenario 'm20b-vacios' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00', 'importe=30.00') })
  Ajustes-M20b $e
  $detalle = 'En cargaJob, ningun caso deja nada distinto del caso vacio: el test no le pasa las entradas al job'
  New-Item -ItemType Directory -Force -Path (Split-Path $e.Json) | Out-Null
  Set-Content -LiteralPath $e.Json -Value '{"jobs":[]}'   # el de un lanzamiento anterior: el informe lo pintaria como bueno
  $r = Prueba $e @() 'm20b-sin-entradas'
  Igual 'sale con 1 (fallo)' 1 $r.Codigo
  Comprueba 'el detalle esta en las tres ultimas lineas con texto (lo que guarda migracion.ps1)' ((@($r.Salida -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 3) -join ' / ').Contains($detalle)) (Cola $r.Salida)
  Comprueba 'no deja prueba-local.json (el informe no da por buenos casos que no probaron nada)' (-not (Test-Path -LiteralPath $e.Json))
  foreach ($lado in @('original', 'migrado')) {
    Comprueba "el arnes guardado del $lado queda invalidado" (-not (Test-Path -LiteralPath (Get-Ruta $e.Local "arnes/$lado")))
    $t = Tarea-Arnes $e $lado
    Comprueba "y su tarea vuelve a pendiente, con un intento y el motivo ($lado)" ($t.estado -eq 'pendiente' -and $t.intentos -eq 1 -and "$($t.motivo)".Contains($detalle)) "$($t.estado) $($t.intentos) $($t.motivo)"
  }
  $n = @(Llamadas $e).Count
  Igual 'cinco llamadas: dos arneses y tres casos' 5 $n
  $r = Prueba $e
  Igual 'al relanzar, con un arnes que si pasa las entradas, sale con 0' 0 $r.Codigo
  Igual 'solo se vuelven a escribir los dos arneses' ($n + 2) @(Llamadas $e).Count
  foreach ($lado in @('original', 'migrado')) {
    $p = Registro-Arnes $e $lado 2
    Comprueba "el prompt del arnes del $lado lleva el motivo, en la seccion de correccion" ($p -match 'CORRECCI' -and $p.Contains($detalle)) $p
  }
  Igual 'los tres casos salen iguales' 'igual,igual,igual' ((Resultados $e) -join ',')
  Comprueba 'y ya hay prueba-local.json' (Test-Path -LiteralPath $e.Json)
}

$Pruebas['58 m20b (e): si solo algunos casos salen como el vacio, o el job tiene un distinto, todo sigue como hoy'] = {
  $e = Nuevo-Escenario 'm20b-algunos' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00', 'importe=30.00') })
  $r = Prueba $e @() 'caso-sin-efecto:caso-cargaJob-01'
  Igual 'sale con 0, como siempre' 0 $r.Codigo
  Igual 'los tres casos salen iguales' 'igual,igual,igual' ((Resultados $e) -join ',')
  Comprueba 'el que sale como el vacio lleva su aviso' ((Caso $e 'cargaJob' 'caso-01').motivo -match 'vacio')
  Igual 'y los otros dos, ninguno' '' ((@((Caso $e 'cargaJob' 'caso-02').motivo, (Caso $e 'cargaJob' 'caso-03').motivo) | Where-Object { $_ }) -join '')
  Comprueba 'los arneses siguen hechos y guardados' ((Tarea-Arnes $e 'original').estado -eq 'hecha' -and (Test-Path -LiteralPath (Get-Ruta $e.Local 'arnes/migrado')))
  $e = Nuevo-Escenario 'm20b-algunos-2' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') }) 'minimo=5.00' 'minimo=5.01'
  $r = Prueba $e @() 'caso-sin-efecto:caso-cargaJob-02'
  Igual 'con un distinto en el job (aunque el otro caso salga como el vacio) sale con 2, no con 1' 2 $r.Codigo
  Igual 'el distinto y el igual con aviso' 'distinto,igual' ((Resultados $e) -join ',')
}

$Pruebas['59 m20b (f): -Deshacer vuelve a ejecutar todos los casos tras el revert: el que arreglaba el commit revertido sale distinto'] = {
  $e = Nuevo-Escenario 'm20b-deshacer-f' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=5.50') }) 'minimo=5.40' 'minimo=5.60'
  $desde = GitEn $e.Wt @('rev-parse', 'HEAD')
  $c1 = Commit-En $e.Wt 'notas/paso-1.txt' "nota 1`n" 'nota del paso 1'
  $c2 = Commit-En $e.Wt 'notas/paso-2.txt' "nota 2`n" 'nota del paso 2'
  $x = Commit-En $e.Wt 'regla.txt' "minimo=5.00`n" 'baja el limite: arregla el caso 2 y rompe el 1'
  $c4 = Commit-En $e.Wt 'notas/paso-4.txt' "nota 4`n" 'nota del paso 4'
  $c5 = Commit-En $e.Wt 'notas/paso-5.txt' "nota 5`n" 'nota del paso 5'
  $r = Prueba $e @('-Desde', $desde, '-Deshacer')
  Igual 'sale con 2: sin el commit, el caso 2 vuelve a estar distinto' 2 $r.Codigo
  $c = @(Culpables $e)
  Igual 'el unico culpable es el caso 1, por ese commit, deshecho' "caso-01 $x True" "$($c[0].caso) $($c[0].commit) $($c[0].deshecho)"
  Igual 'el caso 1 queda igual y el 2, distinto' 'igual,distinto' ((Resultados $e) -join ',')
  Igual 'el caso 2 se ha vuelto a ejecutar con el revert (la comparacion normal y la de despues)' 2 (Ejecuciones-Mig $e 'caso-02')
  Comprueba 'la tabla de despues de deshacer lo dice' ($r.Salida -match 'distinto: cargaJob/caso-02') (Cola $r.Salida)
  Igual 'el json lleva el commit de ahora (el del revert)' (GitEn $e.Wt @('rev-parse', 'HEAD')) (Lee-Json $e.Json).commitMigrado
}

$Pruebas['60 m20b (g): -Deshacer salta un commit donde el caso no se pudo ejecutar: no lo da por culpable y no lo revierte, y el culpable de verdad si'] = {
  $e = Nuevo-Escenario 'm20b-salta' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') })
  $desde = GitEn $e.Wt @('rev-parse', 'HEAD')
  $c1 = Commit-En $e.Wt 'notas/paso-1.txt' "nota 1`n" 'nota del paso 1'
  $c2 = Commit-En $e.Wt 'notas/paso-2.txt' "nota 2`n" 'nota del paso 2'
  $roto = Commit-En $e.Wt 'src/main/java/com/acme/nuevo/Roto.java' "package com.acme.nuevo;`n// NO_COMPILA`n" 'mete una clase que no compila'
  [void](GitEn $e.Wt @('rm', '-q', 'src/main/java/com/acme/nuevo/Roto.java'))
  [void](GitEn $e.Wt @('commit', '-q', '-m', 'quita la clase que no compila'))
  $c4 = Commit-En $e.Wt 'regla.txt' "minimo=5.01`n" 'cambia el limite'
  $c5 = Commit-En $e.Wt 'notas/paso-5.txt' "nota 5`n" 'nota del paso 5'
  $r = Prueba $e @('-Desde', $desde, '-Deshacer')
  Igual 'sale con 0 (el revert del limite arregla el caso)' 0 $r.Codigo
  Comprueba 'el culpable es el que cambia el limite, no el que no compila' ($r.Salida.Contains("se rompe en $(Corto $c4) (cambia el limite).")) (Cola $r.Salida)
  Comprueba 'y dice que ha saltado el commit donde no se pudo ejecutar' ($r.Salida -match 'saltados' -and $r.Salida.Contains((Corto $roto))) (Cola $r.Salida)
  $c = @(Culpables $e)
  Igual 'culpables: solo el del limite, deshecho' "$c4 True 1" "$($c[0].commit) $($c[0].deshecho) $($c.Count)"
  Igual 'el unico commit nuevo es el revert del limite, encima del ultimo' $c5 (GitEn $e.Wt @('rev-parse', 'HEAD~1'))
  Igual 'que es el revert de cambia el limite' 'Revert "cambia el limite"' (GitEn $e.Wt @('log', '-1', '--format=%s'))
  Igual 'sin cambios sin commit' '' (GitEn $e.Wt @('status', '--porcelain'))
}

$Pruebas['61 m20b (h): -Deshacer quita el revert que no arregla el caso: otro revert encima, el aviso en rojo y la rama con su contenido de antes'] = {
  $base = "minimo=5.00`nsegundos=0`nmayus=no`nrelleno1=1`nrelleno2=2`nrelleno3=3`nrelleno4=4`n"
  $e = Nuevo-Escenario 'm20b-deshacer-h' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') }) 'minimo=5.00' $base.TrimEnd("`n")
  $desde = GitEn $e.Wt @('rev-parse', 'HEAD')
  $c1 = Commit-En $e.Wt 'notas/paso-1.txt' "nota 1`n" 'nota del paso 1'
  $c2 = Commit-En $e.Wt 'notas/paso-2.txt' "nota 2`n" 'nota del paso 2'
  $c3 = Commit-En $e.Wt 'regla.txt' $base.Replace('minimo=5.00', 'minimo=5.01') 'sube el limite'
  $c4 = Commit-En $e.Wt 'notas/paso-4.txt' "nota 4`n" 'nota del paso 4'
  $final = $base.Replace('minimo=5.00', 'minimo=5.01').Replace('relleno4=4', 'minimo=5.01')
  $c5 = Commit-En $e.Wt 'regla.txt' $final 'sube el limite otra vez, al final del fichero'
  $r = Prueba $e @('-Desde', $desde, '-Deshacer')
  Igual 'sale con 2 (el caso sigue distinto)' 2 $r.Codigo
  Comprueba 'dice en rojo que deshacer ese commit no arregla el caso y que lo deja como estaba' ($r.Salida.Contains("Deshacer $(Corto $c3) no arregla cargaJob/caso-01: lo vuelvo a dejar como estaba")) (Cola $r.Salida)
  Igual 'la rama lleva dos commits nuevos: el revert y el revert del revert' 2 (GitEn $e.Wt @('rev-list', '--count', "$c5..HEAD"))
  $ultimo = GitEn $e.Wt @('log', '-1', '--format=%s')
  Comprueba 'el ultimo es el revert del revert (git nuevo lo titula Reapply, el viejo Revert "Revert ...")' ($ultimo -ceq 'Reapply "sube el limite"' -or $ultimo -ceq 'Revert "Revert "sube el limite""') $ultimo
  Igual 'regla.txt queda como en el ultimo commit de antes' $final (Lee $e.Wt 'regla.txt')
  Igual 'sin cambios sin commit' '' (GitEn $e.Wt @('status', '--porcelain'))
  $c = @(Culpables $e)
  Igual 'culpables: el commit del limite, sin deshacer' "$c3 False" "$($c[0].commit) $($c[0].deshecho)"
  Igual 'el caso 1 sigue distinto y el 2 igual' 'distinto,igual' ((Resultados $e) -join ',')
  Comprueba 'la prueba no dice que han cambiado las carpetas (los dos commits son suyos)' ($r.Salida -notmatch 'Ha cambiado durante la prueba') (Cola $r.Salida)
  Igual 'el caso 1 se ha ejecutado tras el revert y tras quitarlo: la normal, -Desde, dos de la busqueda y dos de despues' 6 (Ejecuciones-Mig $e 'caso-01')
}

# Un arnes guardado que sigue valiendo no se vuelve a pedir a la IA, aunque su tarea no este hecha.
# Cambia la huella de la tarea del arnes del $Repo (como si la plantilla hubiera cambiado) y, con $Estado, su estado.
function Cambia-Huella($E, [string]$Repo, [string]$Estado = '') {
  $f = Get-Ruta $E.Local "tareas/arnes-$Repo.json"
  $t = Lee-Json $f
  $t.entradas.huella = 'plantilla-vieja'
  if ($Estado) { $t.estado = $Estado; $t.intentos = 2; $t.motivo = 'no compila' }
  [System.IO.File]::WriteAllText($f, (ConvertTo-Json -InputObject $t -Depth 8))
}

# Estropea el test que el arnes del $Repo dejo guardado: ya no compila.
function Rompe-Arnes-Guardado($E, [string]$Repo) {
  foreach ($f in @(Get-ChildItem -LiteralPath (Get-Ruta $E.Local "arnes/$Repo") -Recurse -File -Filter 'PruebaLocalTest.java')) { [System.IO.File]::AppendAllText($f.FullName, "// NO_COMPILA`n") }
}

$Pruebas['62 m20b (i): la huella del arnes cambia (la plantilla) y el test guardado sigue valiendo: se usa, sin llamar a Copilot, y la tarea queda hecha'] = {
  $e = Nuevo-Escenario 'm20b-huella' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') })
  $r = Prueba $e
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  $n = @(Llamadas $e).Count
  foreach ($lado in @('original', 'migrado')) { Cambia-Huella $e $lado }
  $r = Prueba $e
  Igual 'con la huella cambiada sale con 0' 0 $r.Codigo
  Igual 'sin ninguna llamada a Copilot' $n @(Llamadas $e).Count
  foreach ($lado in @('original', 'migrado')) {
    $t = Tarea-Arnes $e $lado
    Comprueba "la tarea del $lado queda hecha, con la huella de ahora" ($t.estado -eq 'hecha' -and $t.entradas.huella -ne 'plantilla-vieja') "$($t.estado) $($t.entradas.huella)"
    Comprueba "dice que el test de otro lanzamiento del $lado sigue valiendo" ($r.Salida -match "Arnes del ${lado}: bien \(el test de otro lanzamiento sigue valiendo\)") (Cola $r.Salida)
  }
  Comprueba 'no dice que lo vuelve a escribir' ($r.Salida -notmatch 'se vuelve a escribir') (Cola $r.Salida)
}

$Pruebas['63 m20b (j): la huella cambia y el test guardado del original ya no compila: se llama a la IA para el original y, como el del migrado lo traduce, tambien para el migrado; sin el aviso de volver a escribir'] = {
  $e = Nuevo-Escenario 'm20b-huella-rota' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') })
  $r = Prueba $e
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  $n = @(Llamadas $e).Count
  foreach ($lado in @('original', 'migrado')) { Cambia-Huella $e $lado }
  Rompe-Arnes-Guardado $e 'original'
  $r = Prueba $e
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'dos llamadas: el arnes del original y el del migrado (que traduce el nuevo, aunque el suyo siga valiendo)' ($n + 2) @(Llamadas $e).Count
  Comprueba 'el del migrado no se usa sin llamar' ($r.Salida -notmatch 'Arnes del migrado: bien \(el test de otro lanzamiento sigue valiendo\)') (Cola $r.Salida)
  Comprueba 'el del original no dice que se use el de antes' ($r.Salida -notmatch 'Arnes del original: bien \(el test de otro lanzamiento') (Cola $r.Salida)
  Comprueba 'ni lo de volver a escribir (la tarea ya era nueva)' ($r.Salida -notmatch 'se vuelve a escribir') (Cola $r.Salida)
  Igual 'la tarea del original queda hecha, con la IA' 'hecha' (Tarea-Arnes $e 'original').estado
  Comprueba 'y lo guardado ahora es lo que escribio la IA, que compila' (-not ((Get-ChildItem -LiteralPath (Get-Ruta $e.Local 'arnes/original') -Recurse -File | ForEach-Object { [System.IO.File]::ReadAllText($_.FullName) }) -join '' ).Contains('NO_COMPILA'))
}

$Pruebas['64 m20b (k): la tarea del arnes quedo atascada en otro lanzamiento y el test guardado vale: se usa, sin llamar a Copilot'] = {
  $e = Nuevo-Escenario 'm20b-atascada' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') })
  $r = Prueba $e
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  $n = @(Llamadas $e).Count
  foreach ($lado in @('original', 'migrado')) { Cambia-Huella $e $lado 'atascada' }
  $r = Prueba $e
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'sin ninguna llamada a Copilot' $n @(Llamadas $e).Count
  foreach ($lado in @('original', 'migrado')) { Igual "la tarea del $lado queda hecha" 'hecha' (Tarea-Arnes $e $lado).estado }
}

$Pruebas['65 m20b (l): una tarea de arnes hecha cuyo test guardado ya no vale: se avisa de que se vuelve a escribir (y el del migrado, que lo traduce, tambien)'] = {
  $e = Nuevo-Escenario 'm20b-hecha-rota' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') })
  $r = Prueba $e
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  $n = @(Llamadas $e).Count
  Rompe-Arnes-Guardado $e 'original'
  $r = Prueba $e
  Igual 'sale con 0' 0 $r.Codigo
  Comprueba 'dice que el test del original ya no vale y que se vuelve a escribir' ($r.Salida -match 'Arnes|test PruebaLocalTest del original de otro lanzamiento ya no vale' -and $r.Salida -match 'se vuelve a escribir') (Cola $r.Salida)
  Igual 'dos llamadas: el arnes del original y el del migrado' ($n + 2) @(Llamadas $e).Count
}

$Pruebas['m24 config.json del migrado: las claves de rescate.ps1 (PalabrasConfigAntigua, PasosSoloCompila) no avisan de desconocidas en la consola'] = {
  $e = Nuevo-Escenario 'm24-claves-de-rescate' ([ordered]@{ cargaJob = @('importe=10.00') })
  Escribe $e.Migrado '.rescate/config.json' (ConvertTo-Json -InputObject ([ordered]@{ PalabrasConfigAntigua = @('inventory'); PasosSoloCompila = @('sonar'); PasosTestsElegidos = @('sonar') }))
  $r = Prueba $e
  Igual 'sale con 0' 0 $r.Codigo
  Comprueba 'la consola no dice clave desconocida' ($r.Salida -notmatch 'clave desconocida') (Cola $r.Salida)
  Igual 'el caso sale igual (la prueba corrio entera)' 'igual' ((Resultados $e) -join ',')
}

# ===================== REPARAR: -Reparar (m25) =====================
# Con -Reparar, de los casos distintos la IA escribe arreglos en la copia del migrado y el script solo da por bueno el que pasa las
# puertas: el caso, los demas casos y la suite de tests unitarios. Estos escenarios usan m25-copilot.ps1 y m25-mvn.ps1: el migrado (su
# rama de rescate) lleva minimo=5.01 en src/main/resources/regla.txt, el original 5.00, y el 'arreglo' es dejar 5.00 ahi. Con -Test,
# la rama lleva un test unitario que espera lo de ahora (minimo=5.01); con -Sano, uno que pasa con cualquier limite; con -SuiteRota, la
# suite de tests unitarios no se puede ejecutar. El caso del limite (importe=5.00) sale distinto. Una entrada con ';;' lleva una linea
# de datos por trozo (m25-copilot.ps1).

function Escenario-M25([string]$Nombre, $Casos, [switch]$Test, [switch]$Sano, [switch]$SuiteRota, [hashtable]$Ajustes = @{}) {
  $e = Nuevo-Escenario $Nombre $Casos
  $aj = [ordered]@{ CopilotExe = (Join-Path $falsos 'm25-copilot.ps1'); MvnExe = (Join-Path $falsos 'm25-mvn.ps1'); SegundosPorLlamada = 60 }
  foreach ($k in $Ajustes.Keys) { $aj[$k] = $Ajustes[$k] }
  Escribe $e.Home 'ajustes.json' (ConvertTo-Json -InputObject $aj)
  [void](Commit-En $e.Wt 'src/main/resources/regla.txt' "minimo=5.01`n" 'migra el limite')
  if ($Test) { [void](Commit-En $e.Wt 'src/test/java/com/acme/nuevo/ReglaTest.java' "package com.acme.nuevo;`n// ESPERA minimo=5.01`nclass ReglaTest {}`n" 'test del limite') }
  if ($Sano) { [void](Commit-En $e.Wt 'src/test/java/com/acme/nuevo/OtroTest.java' "package com.acme.nuevo;`nclass OtroTest {}`n" 'otro test') }
  if ($SuiteRota) { [void](Commit-En $e.Wt 'src/main/resources/suite-rota.txt' "la suite no se ejecuta`n" 'suite rota') }
  return $e
}

function Reparaciones($E) { return @((Lee-Json $E.Json).reparaciones | Where-Object { $_ }) }

function Llamadas-Reparar($E) { return @(Llamadas $E | Where-Object { $_.tipo -eq 'reparar' }) }

# El asunto del commit de un arreglo del caso $Job/$Caso con la clave de siempre (el fichero de salida de hoy).
function Asunto-M25([string]$Job, [string]$Caso) { return "rescate(local): $Job/$Caso ficheros/salida/resultado_<hoy:yyyyMMdd>.txt" }

# Los registros (prompt y respuesta) de la llamada $N de las tareas de reparar, en orden.
function Registros-Reparar($E, [int]$N) {
  return @(Get-ChildItem -LiteralPath (Get-Ruta $E.Local 'registros') -File -Filter "reparar-*-$N.log" | Sort-Object Name | ForEach-Object { [System.IO.File]::ReadAllText($_.FullName) })
}

$Pruebas['m25 (a) -Reparar: dos casos distintos por la misma causa: una llamada, un commit en la rama de rescate, los tres iguales y reparaciones con arreglado; la rama del usuario no se mueve'] = {
  $e = Escenario-M25 'm25-a' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00'); remesaJob = @('importe=5.00') }) -Sano
  $wt0 = GitEn $e.Wt @('rev-parse', 'HEAD')
  $usuario = Estado-Git $e.Migrado
  $original = Foto $e.Legacy
  $r = Prueba $e @('-Reparar') 'reparar-arregla'
  Igual 'sale con 0 (todo igual al final)' 0 $r.Codigo
  Igual 'los tres casos salen iguales' 'igual,igual,igual' ((Resultados $e) -join ',')
  Igual 'una sola llamada para arreglar' 1 (Llamadas-Reparar $e).Count
  Igual 'un commit nuevo en la rama de rescate' 1 (GitEn $e.Wt @('rev-list', '--count', "$wt0..HEAD"))
  Igual 'con el asunto del caso y la clave' (Asunto-M25 'cargaJob' 'caso-01') (GitEn $e.Wt @('log', '-1', '--format=%s'))
  Igual 'que lleva el arreglo' "minimo=5.00`n" (Lee $e.Wt 'src/main/resources/regla.txt')
  Igual 'y solo ese fichero' 'src/main/resources/regla.txt' (GitEn $e.Wt @('diff', '--name-only', "$wt0..HEAD"))
  Igual 'la carpeta de rescate queda sin cambios sin commit' '' (GitEn $e.Wt @('status', '--porcelain'))
  Igual 'la rama y la carpeta del usuario no se mueven' $usuario (Estado-Git $e.Migrado)
  Igual 'el original queda como estaba' $original (Foto $e.Legacy)
  $rep = @(Reparaciones $e)
  Igual 'reparaciones lleva una entrada' 1 $rep.Count
  Igual 'que dice arreglado' 'arreglado' $rep[0].resultado
  Igual 'con el job, el caso y la clave' "cargaJob caso-01 ficheros/salida/resultado_<hoy:yyyyMMdd>.txt" "$($rep[0].job) $($rep[0].caso) $($rep[0].clave)"
  Igual 'los casos que tenian esa clave' 2 $rep[0].casos
  Igual 'el commit entero' (GitEn $e.Wt @('rev-parse', 'HEAD')) $rep[0].commit
  Igual 'su asunto' (Asunto-M25 'cargaJob' 'caso-01') $rep[0].asunto
  Igual 'y un intento' 1 $rep[0].intentos
  Igual 'el json guarda el commit de ahora del migrado' (GitEn $e.Wt @('rev-parse', 'HEAD')) (Lee-Json $e.Json).commitMigrado
  Comprueba 'la consola dice que lo ha arreglado, con el commit' ($r.Salida -match 'arreglado' -and $r.Salida.Contains((Corto $rep[0].commit))) (Cola $r.Salida)
  Comprueba 'las salidas del migrado son las del arreglo' ((Lee $e.Local "salidas/migrado/remesaJob/caso-01/ficheros/salida/resultado_$(Hoy).txt") -match 'importe=5\.00 -> aceptado') ''
  Comprueba 'el parche queda en prueba-local' (@(Get-ChildItem -LiteralPath $e.Local -File -Filter '*.patch').Count -ge 1) ''
}

$Pruebas['m25 (b) -Reparar: la IA toca un test y su cambio de src/main/ no mejora el caso: el test se deshace y el motivo lo dice; reintento y, al final, no arreglado; la rama de rescate no se mueve'] = {
  $e = Escenario-M25 'm25-b' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') }) -Test -Ajustes @{ CopilotExe = (Join-Path $falsos 'm30-copilot.ps1') }
  $antes = Estado-Git $e.Wt
  $r = Prueba $e @('-Reparar') 'reparar-test-inutil'
  Igual 'sale con 2 (el caso sigue distinto)' 2 $r.Codigo
  Igual 'el caso del limite sigue distinto' 'distinto,igual' ((Resultados $e) -join ',')
  Igual 'dos llamadas: el intento y el reintento' 2 (Llamadas-Reparar $e).Count
  Igual 'la rama de rescate no se mueve' $antes (Estado-Git $e.Wt)
  $rep = @(Reparaciones $e)
  Igual 'reparaciones: una entrada, no arreglado' 'no arreglado' $rep[0].resultado
  Igual 'con dos intentos' 2 $rep[0].intentos
  Comprueba 'el motivo empieza por lo que ha deshecho: el test que ha tocado, fuera de src/main/' ($rep[0].motivo -match '^He deshecho lo que tocaste fuera de src/main/: src/test/java/com/acme/nuevo/ReglaTest\.java\. ') $rep[0].motivo
  Comprueba 'y sigue con el motivo de siempre' ($rep[0].motivo -match 'sigue igual de distinto') $rep[0].motivo
  Igual 'sin commit nuevo en la rama de rescate' $antes (Estado-Git $e.Wt)
  Igual 'la copia del migrado queda como estaba: regla.txt con el limite de antes' "minimo=5.01`n" (Lee $e.CopiaMig 'src/main/resources/regla.txt')
  Igual 'y el test, sin lo que le anadio la IA' "package com.acme.nuevo;`n// ESPERA minimo=5.01`nclass ReglaTest {}`n" (Lee $e.CopiaMig 'src/test/java/com/acme/nuevo/ReglaTest.java')
  Comprueba 'las salidas del intento rechazado se borran' (-not (Test-Path -LiteralPath (Get-Ruta $e.Local 'salidas/reparar/1')) -and -not (Test-Path -LiteralPath (Get-Ruta $e.Local 'salidas/reparar/2'))) ''
  Comprueba 'la consola dice que no se ha arreglado' ($r.Salida -match 'no arreglado') (Cola $r.Salida)
  Igual 'la tarea queda atascada' 'atascada' (@(Get-ChildItem -LiteralPath (Get-Ruta $e.Local 'tareas') -File -Filter 'reparar-*.json' | ForEach-Object { (Lee-Json $_.FullName).estado }))[0]
}

$Pruebas['m25 (c) -Reparar: el arreglo iguala el caso de la tarea pero otro caso que era igual sale distinto: rechazado, nombrando ese caso'] = {
  $e = Escenario-M25 'm25-c' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00 LATIN') })
  $antes = Estado-Git $e.Wt
  $r = Prueba $e @('-Reparar') 'reparar-rompe'
  Igual 'sale con 2' 2 $r.Codigo
  Igual 'el caso del limite sigue distinto y el otro igual' 'distinto,igual' ((Resultados $e) -join ',')
  $rep = @(Reparaciones $e)
  Igual 'no arreglado' 'no arreglado' $rep[0].resultado
  Comprueba 'el motivo nombra el caso que ha empeorado' ($rep[0].motivo -match 'cargaJob/caso-02') $rep[0].motivo
  Comprueba 'y dice como: antes igual y ahora distinto' ($rep[0].motivo -match 'igual' -and $rep[0].motivo -match 'distinto') $rep[0].motivo
  Igual 'la rama de rescate no se mueve' $antes (Estado-Git $e.Wt)
  Comprueba 'el reintento recibe el caso que ha empeorado en su prompt' ((@(Registros-Reparar $e 2)[0]) -match 'cargaJob/caso-02') ''
}

$Pruebas['m25 (d) -Reparar: el arreglo iguala los casos pero fallan mas tests unitarios: rechazado, con los tests en el motivo'] = {
  $e = Escenario-M25 'm25-d' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') }) -Test
  $antes = Estado-Git $e.Wt
  $r = Prueba $e @('-Reparar') 'reparar-arregla'
  Igual 'sale con 2' 2 $r.Codigo
  Igual 'el caso sigue distinto' 'distinto,igual' ((Resultados $e) -join ',')
  $rep = @(Reparaciones $e)
  Igual 'no arreglado' 'no arreglado' $rep[0].resultado
  Comprueba 'el motivo dice que arregla el caso pero rompe tests' ($rep[0].motivo -match 'arregla el caso, pero rompe estos tests') $rep[0].motivo
  Comprueba 'y nombra el test que falla' ($rep[0].motivo -match 'com\.acme\.nuevo\.ReglaTest') $rep[0].motivo
  Igual 'la rama de rescate no se mueve' $antes (Estado-Git $e.Wt)
  Igual 'se reintento una vez (dos llamadas)' 2 (Llamadas-Reparar $e).Count
  $e2 = Escenario-M25 'm25-d2' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') }) -Test
  $antes2 = Estado-Git $e2.Wt
  $r = Prueba $e2 @('-Reparar') 'reparar-sin-tests'
  Igual 'si el arreglo hace que se ejecuten menos tests, sale con 2' 2 $r.Codigo
  Comprueba 'lo dice con las cifras (1 antes, 0 ahora)' ((@(Reparaciones $e2)[0]).motivo -match 'menos tests' -and (@(Reparaciones $e2)[0]).motivo -match '0' -and (@(Reparaciones $e2)[0]).motivo -match '1') (@(Reparaciones $e2)[0]).motivo
  Igual 'y la rama de rescate no se mueve' $antes2 (Estado-Git $e2.Wt)
}

$Pruebas['m25 (e) -Reparar: reparar-no.txt: no se arregla, con su motivo, sin reintento y sin commit'] = {
  $e = Escenario-M25 'm25-e' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') })
  $antes = Estado-Git $e.Wt
  $r = Prueba $e @('-Reparar') 'reparar-no'
  Igual 'sale con 2 (el caso sigue distinto)' 2 $r.Codigo
  Igual 'una sola llamada' 1 (Llamadas-Reparar $e).Count
  $rep = @(Reparaciones $e)
  Igual 'la clave queda no se arregla' 'no se arregla' $rep[0].resultado
  Igual 'con el motivo de la IA' 'La prueba local simula el correo y en el entorno real ya esta bien.' $rep[0].motivo
  Igual 'sin commit nuevo' $antes (Estado-Git $e.Wt)
  Comprueba 'la consola lo dice con el motivo' ($r.Salida -match 'no se arregla' -and $r.Salida -match 'simula el correo') (Cola $r.Salida)
  Comprueba 'el fichero de la IA no se queda en la copia' (-not (Test-Path -LiteralPath (Get-Ruta $e.CopiaMig '.rescate/reparar-no.txt'))) ''
  Igual 'la copia queda como estaba: regla.txt con el limite de antes' "minimo=5.01`n" (Lee $e.CopiaMig 'src/main/resources/regla.txt')
}

$Pruebas['m25 (f) -Reparar: con -Desde o -Deshacer, sin worktree de rescate o con la carpeta de rescate sucia: error de arranque claro y ninguna llamada'] = {
  $e = Escenario-M25 'm25-f1' ([ordered]@{ cargaJob = @('importe=5.00') })
  $desde = GitEn $e.Wt @('rev-parse', 'HEAD')
  $r = Prueba $e @('-Reparar', '-Desde', $desde)
  Igual 'con -Desde sale con 1' 1 $r.Codigo
  Comprueba 'dice que no se combina' ($r.Salida -match '-Reparar' -and $r.Salida -match '-Desde') (Cola $r.Salida)
  Igual 'sin llamadas' 0 @(Llamadas $e).Count
  Comprueba 'ni copias' (-not (Test-Path -LiteralPath $e.CopiaOrig)) ''
  $r = Prueba $e @('-Reparar', '-Desde', $desde, '-Deshacer')
  Igual 'con -Deshacer tambien sale con 1' 1 $r.Codigo
  Comprueba 'y lo dice' ($r.Salida -match '-Reparar' -and $r.Salida -match '-Deshacer') (Cola $r.Salida)
  $r = Prueba $e @('-Reparar', '-Deshacer')
  Igual '-Reparar con -Deshacer solo tambien sale con 1' 1 $r.Codigo
  Comprueba 'dice lo de -Reparar y no lo de -Desde' ($r.Salida -match '-Reparar' -and $r.Salida -match '-Deshacer') (Cola $r.Salida)
  Igual 'sin llamadas' 0 @(Llamadas $e).Count
  $e = Escenario-M25 'm25-f2' ([ordered]@{ cargaJob = @('importe=5.00') })
  [void](GitEn $e.Migrado @('worktree', 'remove', '--force', $e.Wt))
  $r = Prueba $e @('-Reparar')
  Igual 'sin worktree de rescate sale con 1' 1 $r.Codigo
  Comprueba 'dice que se lance migracion.ps1 primero y que crea la carpeta de rescate' ($r.Salida -match 'lanza migracion\.ps1 primero' -and $r.Salida.Contains($e.Wt)) (Cola $r.Salida)
  Igual 'sin llamadas' 0 @(Llamadas $e).Count
  Comprueba 'ni copias' (-not (Test-Path -LiteralPath $e.CopiaOrig)) ''
  $e = Escenario-M25 'm25-f3' ([ordered]@{ cargaJob = @('importe=5.00') })
  Escribe $e.Wt 'sucio.txt' "sin commit`n"
  $antes = Estado-Git $e.Wt
  $r = Prueba $e @('-Reparar')
  Igual 'con la carpeta de rescate sucia sale con 1' 1 $r.Codigo
  Comprueba 'dice que tiene cambios sin commit y de que carpeta' ($r.Salida -match 'cambios sin commit' -and $r.Salida.Contains($e.Wt)) (Cola $r.Salida)
  Igual 'sin llamadas' 0 @(Llamadas $e).Count
  Igual 'y no la toca' $antes (Estado-Git $e.Wt)
}

$Pruebas['m25 (g) -Reparar: el reintento lleva en su prompt el motivo y el diff rechazado, y arregla; el primer intento no lleva la correccion'] = {
  $e = Escenario-M25 'm25-g' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') }) -Sano -Ajustes @{ CopilotExe = (Join-Path $falsos 'm30-copilot.ps1') }
  $wt0 = GitEn $e.Wt @('rev-parse', 'HEAD')
  $r = Prueba $e @('-Reparar') 'reparar-inutil1'
  Igual 'sale con 0 (el reintento arregla)' 0 $r.Codigo
  Igual 'dos llamadas' 2 (Llamadas-Reparar $e).Count
  $uno = @(Registros-Reparar $e 1)[0]
  $dos = @(Registros-Reparar $e 2)[0]
  Comprueba 'el primer prompt no lleva la correccion' ($uno -notmatch 'CORRECCI') ''
  Comprueba 'el segundo si, con el motivo (sigue igual de distinto)' ($dos -match 'CORRECCI' -and $dos -match 'sigue igual de distinto') ''
  Comprueba 'y con el diff que se rechazo (el cambio de nota.txt)' ($dos -match 'diff --git a/src/main/resources/nota\.txt' -and $dos -match '\+sin efecto') ''
  Igual 'un commit nuevo' 1 (GitEn $e.Wt @('rev-list', '--count', "$wt0..HEAD"))
  Comprueba 'sin la nota.txt que la IA dejo en el primer intento' (-not (Test-Path -LiteralPath (Get-Ruta $e.Wt 'src/main/resources/nota.txt'))) ''
  Igual 'la entrada dice arreglado con dos intentos' 'arreglado 2' ((@(Reparaciones $e)[0]).resultado + ' ' + (@(Reparaciones $e)[0]).intentos)
}

$Pruebas['m25 (h) -Reparar: relanzar con el mismo HEAD y la tarea atascada no llama a Copilot y lo dice'] = {
  $e = Escenario-M25 'm25-h' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') })
  $r = Prueba $e @('-Reparar') 'reparar-inutil'
  Igual 'la primera vez sale con 2' 2 $r.Codigo
  $n = (Llamadas-Reparar $e).Count
  Igual 'con dos llamadas' 2 $n
  $motivo = (@(Reparaciones $e)[0]).motivo
  $r = Prueba $e @('-Reparar') 'reparar-arregla'
  Igual 'al relanzar sale con 2' 2 $r.Codigo
  Igual 'sin ninguna llamada nueva a reparar' $n (Llamadas-Reparar $e).Count
  Comprueba 'la consola dice que ya esta probado con este codigo del migrado' ($r.Salida -match 'ya probado con este codigo del migrado') (Cola $r.Salida)
  $rep = @(Reparaciones $e)
  Igual 'reparaciones sigue con una entrada, no arreglada' 'no arreglado' $rep[0].resultado
  Comprueba 'con el motivo de antes tras lo de ya probado' ($rep[0].motivo -match '^ya probado con este codigo del migrado: ' -and $rep[0].motivo.Contains(($motivo -split "`n")[0])) $rep[0].motivo
}

$Pruebas['m25 (i) -Reparar: con dos claves se prueba primero la que tienen mas casos; MaxReparaciones corta y la consola dice lo que queda sin probar'] = {
  $e = Escenario-M25 'm25-i' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00 | SQL importe=5.00', 'importe=10.00 | SQL importe=5.00') }) -Ajustes @{ MaxReparaciones = 1 }
  $antes = Estado-Git $e.Wt
  $r = Prueba $e @('-Reparar') 'reparar-no'
  Igual 'sale con 2 (siguen distintos)' 2 $r.Codigo
  Igual 'una sola llamada: el tope es 1' 1 (Llamadas-Reparar $e).Count
  $rep = @(Reparaciones $e)
  Igual 'reparaciones lleva una entrada' 1 $rep.Count
  Igual 'la clave es la tabla, que tienen 2 casos y la otra 1' 'tablas/DATOS.csv' $rep[0].clave
  Igual 'con su primer caso' 'caso-02' $rep[0].caso
  Igual 'y los 2 casos' 2 $rep[0].casos
  Comprueba 'la consola dice que quedan sin probar la otra clave' ($r.Salida -match 'MaxReparaciones' -and $r.Salida -match 'sin probar' -and $r.Salida.Contains('resultado_')) (Cola $r.Salida)
  Igual 'sin commit nuevo' $antes (Estado-Git $e.Wt)
}

$Pruebas['m25 (j) -Reparar: un cambio en src/main/ que no mejora el caso, o ningun cambio: rechazado con su motivo, sin commit y no arreglado'] = {
  $e = Escenario-M25 'm25-j1' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') })
  $antes = Estado-Git $e.Wt
  $r = Prueba $e @('-Reparar') 'reparar-inutil'
  Igual 'con un cambio sin efecto sale con 2' 2 $r.Codigo
  Igual 'el caso sigue distinto' 'distinto,igual' ((Resultados $e) -join ',')
  Igual 'dos llamadas: el intento y el reintento' 2 (Llamadas-Reparar $e).Count
  $rep = @(Reparaciones $e)
  Igual 'no arreglado' 'no arreglado' $rep[0].resultado
  Igual 'con dos intentos' 2 $rep[0].intentos
  Comprueba 'el motivo dice que sigue igual de distinto' ($rep[0].motivo -match 'sigue igual de distinto' -and $rep[0].motivo -match 'cargaJob/caso-01') $rep[0].motivo
  Igual 'sin commit nuevo en la rama de rescate' $antes (Estado-Git $e.Wt)
  Comprueba 'lo que dejo la IA se deshace en la copia' (-not (Test-Path -LiteralPath (Get-Ruta $e.CopiaMig 'src/main/resources/nota.txt'))) ''
  $e = Escenario-M25 'm25-j2' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') })
  $antes = Estado-Git $e.Wt
  $r = Prueba $e @('-Reparar') 'reparar-nada'
  Igual 'sin ningun cambio tambien sale con 2' 2 $r.Codigo
  Igual 'con dos llamadas' 2 (Llamadas-Reparar $e).Count
  $rep = @(Reparaciones $e)
  Igual 'no arreglado' 'no arreglado' $rep[0].resultado
  Comprueba 'el motivo dice que no ha cambiado ningun fichero de src/main/' ($rep[0].motivo -match 'No has cambiado ningun fichero de src/main/' -and $rep[0].motivo -notmatch 'sigue igual') $rep[0].motivo
  Igual 'sin commit nuevo' $antes (Estado-Git $e.Wt)
}

$Pruebas['m25 (k) -Reparar: el arreglo iguala el caso de la tarea pero otro caso distinto con la misma clave tiene mas lineas distintas: rechazado, nombrando ese caso'] = {
  $e = Escenario-M25 'm25-k' ([ordered]@{ cargaJob = @('importe=5.00;;importe=5.00;;importe=5.00', 'importe=5.00;;importe=4.80;;importe=4.80') })
  $antes = Estado-Git $e.Wt
  $r = Prueba $e @('-Reparar') 'reparar-pasado'
  Igual 'sale con 2' 2 $r.Codigo
  Igual 'los dos siguen distintos (nada se da por arreglado)' 'distinto,distinto' ((Resultados $e) -join ',')
  $rep = @(Reparaciones $e)
  Igual 'la tarea es la del primer caso, con la clave de los dos' 'caso-01 2' "$($rep[0].caso) $($rep[0].casos)"
  Igual 'no arreglado' 'no arreglado' $rep[0].resultado
  Comprueba 'el motivo nombra el otro caso' ($rep[0].motivo -match 'cargaJob/caso-02') $rep[0].motivo
  Comprueba 'y las lineas distintas de antes (1) y de ahora (2)' ($rep[0].motivo -match 'antes tenia 1 lineas distintas y ahora 2') $rep[0].motivo
  Comprueba 'no es una clave nueva' ($rep[0].motivo -notmatch 'diferencia nueva') $rep[0].motivo
  Igual 'sin commit nuevo en la rama de rescate' $antes (Estado-Git $e.Wt)
}

$Pruebas['m25 (l) -Reparar: el arreglo iguala el caso de la tarea pero otro caso ya no se puede ejecutar: rechazado, nombrando ese caso'] = {
  $e = Escenario-M25 'm25-l' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') }) -Ajustes @{ MinutosMaven = 0.1 }
  $antes = Estado-Git $e.Wt
  $r = Prueba $e @('-Reparar') 'reparar-cuelga'
  Igual 'sale con 2' 2 $r.Codigo
  Igual 'el caso del limite sigue distinto' 'distinto,igual' ((Resultados $e) -join ',')
  $rep = @(Reparaciones $e)
  Igual 'no arreglado' 'no arreglado' $rep[0].resultado
  Comprueba 'el motivo dice que el caso ya no se puede ejecutar' ($rep[0].motivo -match 'cargaJob/caso-02 ya no se puede ejecutar') $rep[0].motivo
  Comprueba 'con el motivo de Maven' ($rep[0].motivo -match 'tope') $rep[0].motivo
  Igual 'sin commit nuevo en la rama de rescate' $antes (Estado-Git $e.Wt)
}

$Pruebas['m25 (m) -Reparar: la suite de tests unitarios de partida no se puede ejecutar: no se repara nada, sin llamadas a Copilot, y lo dice'] = {
  $e = Escenario-M25 'm25-m' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') }) -SuiteRota
  $antes = Estado-Git $e.Wt
  $r = Prueba $e @('-Reparar') 'reparar-arregla'
  Igual 'sale con 2 (hay un caso distinto)' 2 $r.Codigo
  Igual 'ninguna llamada a reparar' 0 (Llamadas-Reparar $e).Count
  Comprueba 'la consola dice que no ha podido medir los tests unitarios de partida' ($r.Salida -match 'no he podido medir los tests unitarios de partida') (Cola $r.Salida)
  Igual 'sin commit nuevo en la rama de rescate' $antes (Estado-Git $e.Wt)
  Igual 'reparaciones queda vacio' 0 (Reparaciones $e).Count
}

# ===================== REPARAR: el ruido de la ejecucion (m26) =====================
# La IA prueba su arreglo ejecutando el batch (mvn test), que puede dejar ficheros nuevos fuera de src/ (un log, una base H2): no son suyos y
# no rechazan el arreglo. Todo lo demas fuera de src/main/ sigue rechazando. Usan los escenarios de m25 y sus guiones de m25-copilot.ps1.

$Pruebas['m26 (a) -Reparar: la IA arregla src/main/ y la ejecucion deja logs/batch.log y datos/h2.mv.db nuevos: arreglado, un commit que solo toca src/main/, los dos ficheros fuera de la copia y la consola los nombra'] = {
  $e = Escenario-M25 'm26-a' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') }) -Sano
  $wt0 = GitEn $e.Wt @('rev-parse', 'HEAD')
  $r = Prueba $e @('-Reparar') 'reparar-ruido'
  Igual 'sale con 0 (todo igual al final)' 0 $r.Codigo
  Igual 'los dos casos salen iguales' 'igual,igual' ((Resultados $e) -join ',')
  Igual 'una sola llamada: el ruido no rechaza' 1 (Llamadas-Reparar $e).Count
  $rep = @(Reparaciones $e)
  Igual 'reparaciones: arreglado' 'arreglado' $rep[0].resultado
  Igual 'con un intento' 1 $rep[0].intentos
  Igual 'un commit nuevo en la rama de rescate' 1 (GitEn $e.Wt @('rev-list', '--count', "$wt0..HEAD"))
  Igual 'que solo toca src/main/' 'src/main/resources/regla.txt' (GitEn $e.Wt @('diff', '--name-only', "$wt0..HEAD"))
  Igual 'la carpeta de rescate queda sin cambios sin commit' '' (GitEn $e.Wt @('status', '--porcelain'))
  Comprueba 'logs/batch.log ya no esta en la copia' (-not (Test-Path -LiteralPath (Get-Ruta $e.CopiaMig 'logs/batch.log'))) ''
  Comprueba 'datos/h2.mv.db tampoco' (-not (Test-Path -LiteralPath (Get-Ruta $e.CopiaMig 'datos/h2.mv.db'))) ''
  Comprueba 'la consola nombra logs/batch.log en la linea de lo que quita' ($r.Salida -match 'Quito lo que ha dejado la ejecucion fuera de src/: [^\r\n]*logs/batch\.log') (Cola $r.Salida)
  Comprueba 'y datos/h2.mv.db' ($r.Salida -match 'Quito lo que ha dejado la ejecucion fuera de src/: [^\r\n]*datos/h2\.mv\.db') (Cola $r.Salida)
}

$Pruebas['m26 (b) -Reparar: la IA arregla src/main/ y crea src/test/.../NuevoTest.java (bajo src/, no es ruido): el script lo deshace, lo dice y el arreglo vale, con un commit que solo toca src/main/'] = {
  $e = Escenario-M25 'm26-b' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') }) -Sano
  $wt0 = GitEn $e.Wt @('rev-parse', 'HEAD')
  $r = Prueba $e @('-Reparar') 'reparar-test-nuevo'
  Igual 'sale con 0 (todo igual al final)' 0 $r.Codigo
  Igual 'una sola llamada' 1 (Llamadas-Reparar $e).Count
  Igual 'reparaciones: arreglado' 'arreglado' (@(Reparaciones $e)[0]).resultado
  Igual 'un commit nuevo en la rama de rescate' 1 (GitEn $e.Wt @('rev-list', '--count', "$wt0..HEAD"))
  Igual 'que solo toca src/main/' 'src/main/resources/regla.txt' (GitEn $e.Wt @('diff', '--name-only', "$wt0..HEAD"))
  Comprueba 'la consola nombra el test nuevo en lo que deshace' ($r.Salida -match 'Deshago lo que la IA ha tocado fuera de lo suyo: src/test/java/com/acme/nuevo/NuevoTest\.java') (Cola $r.Salida)
  Comprueba 'lo nuevo bajo src/ no es ruido: la consola no dice que lo quita' ($r.Salida -notmatch 'Quito lo que ha dejado') (Cola $r.Salida)
  Comprueba 'el test nuevo no esta en la copia' (-not (Test-Path -LiteralPath (Get-Ruta $e.CopiaMig 'src/test/java/com/acme/nuevo/NuevoTest.java'))) ''
}

$Pruebas['m26 (c) -Reparar: la IA solo deja logs/batch.log: es ruido, asi que no ha cambiado src/main/: rechazado con ese motivo y el fichero ya no esta'] = {
  $e = Escenario-M25 'm26-c' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') })
  $antes = Estado-Git $e.Wt
  $r = Prueba $e @('-Reparar') 'reparar-ruido-solo'
  Igual 'sale con 2' 2 $r.Codigo
  $rep = @(Reparaciones $e)
  Igual 'no arreglado' 'no arreglado' $rep[0].resultado
  Comprueba 'el motivo dice que no ha cambiado ningun fichero de src/main/' ($rep[0].motivo -match 'No has cambiado ningun fichero de src/main/\.' -and $rep[0].motivo -notmatch 'logs/batch\.log') $rep[0].motivo
  Comprueba 'la consola dice que quita logs/batch.log' ($r.Salida -match 'Quito lo que ha dejado la ejecucion fuera de src/: [^\r\n]*logs/batch\.log') (Cola $r.Salida)
  Comprueba 'logs/batch.log ya no esta en la copia' (-not (Test-Path -LiteralPath (Get-Ruta $e.CopiaMig 'logs/batch.log'))) ''
  Igual 'sin commit nuevo en la rama de rescate' $antes (Estado-Git $e.Wt)
}

$Pruebas['m26 (d) -Reparar: la IA arregla src/main/ y cambia pom.xml (con seguimiento): el script lo deja como estaba, lo dice y el arreglo vale, con un commit que solo toca src/main/'] = {
  $e = Escenario-M25 'm26-d' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') }) -Sano
  $wt0 = GitEn $e.Wt @('rev-parse', 'HEAD')
  $r = Prueba $e @('-Reparar') 'reparar-pom'
  Igual 'sale con 0 (todo igual al final)' 0 $r.Codigo
  Igual 'reparaciones: arreglado' 'arreglado' (@(Reparaciones $e)[0]).resultado
  Igual 'un commit nuevo que solo toca src/main/' 'src/main/resources/regla.txt' (GitEn $e.Wt @('diff', '--name-only', "$wt0..HEAD"))
  Comprueba 'la consola dice que deshace pom.xml' ($r.Salida -match 'Deshago lo que la IA ha tocado fuera de lo suyo: pom\.xml') (Cola $r.Salida)
  Comprueba 'el pom.xml de la copia queda como estaba' ((Lee $e.CopiaMig 'pom.xml') -notmatch 'tocado por la IA') ''
}

# ===================== JAVA_HOME de la IA (m27) =====================
# La IA que escribe el arnes del original y los casos ejecuta Maven en la copia del original: tiene que ver el JDK de -JavaLegacy y no el
# del proceso. copilot-local.ps1 apunta en el registro de cada llamada el JAVA_HOME que ve (javahome=).

# Lanza prueba-local.ps1 con JAVA_HOME = $Proceso (o sin JAVA_HOME si es '') y cada llamada de Copilot tardando 1 s (RESCATE_ESPERA), para
# que se vea cuales van a la vez. Devuelve lo de Prueba; el JAVA_HOME de cada llamada queda en el registro del falso (JavaHome-De).
function Prueba-Con-JavaHome($E, [string[]]$A, [string]$Proceso) {
  $antes = $env:JAVA_HOME
  if ($Proceso) { $env:JAVA_HOME = $Proceso } else { $env:JAVA_HOME = $null }
  $env:RESCATE_ESPERA = '1'
  try { $r = Prueba $E $A }
  finally { $env:RESCATE_ESPERA = ''; $env:JAVA_HOME = $antes }
  return $r
}

# El JAVA_HOME que vieron las llamadas cuyo id casa con $Id ('arnes-original', 'caso-*'), sin repetidos y unidos con comas.
function JavaHome-De($E, [string]$Id) { return ((@(Llamadas $E | Where-Object { $_.id -like $Id } | ForEach-Object { $_.javahome } | Select-Object -Unique)) -join ',') }

$Pruebas['m27 (a) -JavaLegacy: la IA del original (arnes y casos) ve JAVA_HOME = -JavaLegacy, la del migrado ve el de antes'] = {
  $e = Nuevo-Escenario 'm27-a' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $jdk = Join-Path $e.Raiz 'jdk-viejo'
  [void](New-Item -ItemType Directory -Path $jdk -Force)
  $proceso = Join-Path $e.Raiz 'jdk-del-proceso'
  $r = Prueba-Con-JavaHome $e @('-JavaLegacy', $jdk) $proceso
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'el arnes del original ve la carpeta de -JavaLegacy' $jdk (JavaHome-De $e 'arnes-original')
  Igual 'el arnes del migrado ve el JAVA_HOME de antes' $proceso (JavaHome-De $e 'arnes-migrado')
  Igual 'los dos, uno detras de otro (m29: el del migrado traduce el del original)' 1 (Max-Simultaneas @(Llamadas $e | Where-Object { $_.id -like 'arnes-*' }))
  Igual 'los casos, que se preparan en la copia del original, ven la carpeta de -JavaLegacy' $jdk (JavaHome-De $e 'caso-*')
  Igual 'cuatro llamadas en total: dos arneses y dos casos' 4 @(Llamadas $e).Count
  $e2 = Nuevo-Escenario 'm27-a-vacio' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-Con-JavaHome $e2 @('-JavaLegacy', $jdk) ''
  Igual 'sin JAVA_HOME en el proceso: sale con 0' 0 $r.Codigo
  Igual 'el arnes del migrado ve el JAVA_HOME vacio' '' (JavaHome-De $e2 'arnes-migrado')
  Igual 'y el del original, -JavaLegacy' $jdk (JavaHome-De $e2 'arnes-original')
}

$Pruebas['m27 (b) sin -JavaLegacy: la IA del original y la del migrado ven el JAVA_HOME de antes'] = {
  $e = Nuevo-Escenario 'm27-b' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $proceso = Join-Path $e.Raiz 'jdk-del-proceso'
  $r = Prueba-Con-JavaHome $e @() $proceso
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'el arnes del original ve el JAVA_HOME de antes' $proceso (JavaHome-De $e 'arnes-original')
  Igual 'el arnes del migrado, el mismo' $proceso (JavaHome-De $e 'arnes-migrado')
  Igual 'los casos, el mismo' $proceso (JavaHome-De $e 'caso-*')
  Igual 'cuatro llamadas en total' 4 @(Llamadas $e).Count
}

$Pruebas['m27 (c) Invoke-Llamadas: JavaHome solo vale para su elemento y el JAVA_HOME del script queda como estaba (con y sin JAVA_HOME, y si Copilot no se puede lanzar)'] = {
  $f = Join-Path $Dir 'm27-llamadas.ps1'
  [System.IO.File]::WriteAllText($f, @'
param([string]$Sis, [string]$Copilot, [string]$Carpeta)
. (Join-Path $Sis 'comun.ps1')
. (Join-Path $Sis 'tareas.ps1')
$Cfg.CopilotExe = $Copilot
function Lote([string]$Marca) {
  $con = [pscustomobject]@{ Id = "$Marca-con"; Dir = $Carpeta; Modelo = 'modelo-x'; Esfuerzo = 'medium'; Prompt = "TIPO: nada`n"; JavaHome = 'C:\jdk-del-item' }
  $sin = [pscustomobject]@{ Id = "$Marca-sin"; Dir = $Carpeta; Modelo = 'modelo-x'; Esfuerzo = 'medium'; Prompt = "TIPO: nada`n" }
  return @($con, $sin)
}
function Estado([string]$Que) { 'JAVA_HOME ' + $Que + ' [' + [Environment]::GetEnvironmentVariable('JAVA_HOME') + ']' }
$env:JAVA_HOME = 'C:\jdk-del-script'
[void](Invoke-Llamadas (Lote 'con-java'))
Estado 'despues con JAVA_HOME'
$env:JAVA_HOME = $null
[void](Invoke-Llamadas (Lote 'sin-java'))
Estado 'despues sin JAVA_HOME'
$env:JAVA_HOME = 'C:\jdk-del-script'
$Cfg.CopilotExe = Join-Path $Carpeta 'no-existe.ps1'
$v = @(Invoke-Llamadas @([pscustomobject]@{ Id = 'roto'; Dir = $Carpeta; Modelo = 'modelo-x'; Esfuerzo = 'medium'; Prompt = "TIPO: nada`n"; JavaHome = 'C:\jdk-del-item' }))[0]
'LANZAMIENTO ' + $v.Texto
Estado 'despues de un lanzamiento que falla'
'@)
  $carpeta = Join-Path $Dir 'm27-c'
  $reg = Join-Path $Dir 'm27-c-llamadas'
  $env:RESCATE_LLAMADAS = $reg
  try { $r = Lanzar $f @((Split-Path -Parent $Script), (Join-Path $falsos 'copilot-local.ps1'), $carpeta) }
  finally { $env:RESCATE_LLAMADAS = '' }
  $ll = Llamadas ([pscustomobject]@{ Llamadas = $reg })
  Igual 'el elemento con JavaHome lo ve (en las dos tandas)' 'C:\jdk-del-item' ((@($ll | Where-Object { $_.id -like '*-con' } | ForEach-Object { $_.javahome } | Select-Object -Unique)) -join ',')
  Igual 'el elemento sin JavaHome ve el del script (la primera tanda) o ninguno (la segunda)' 'C:\jdk-del-script,' ((@($ll | Where-Object { $_.id -like '*-sin' } | Sort-Object id | ForEach-Object { $_.javahome }) -join ','))
  Comprueba 'despues, el JAVA_HOME del script es el de antes' ($r.Salida -match '(?m)^JAVA_HOME despues con JAVA_HOME \[C:\\jdk-del-script\]$') (Cola $r.Salida)
  Comprueba 'y sin JAVA_HOME antes, sigue sin JAVA_HOME' ($r.Salida -match '(?m)^JAVA_HOME despues sin JAVA_HOME \[\]$') (Cola $r.Salida)
  Comprueba 'un lanzamiento que falla lo dice' ($r.Salida -match '(?m)^LANZAMIENTO No pude lanzar Copilot') (Cola $r.Salida)
  Comprueba 'y deja el JAVA_HOME como estaba' ($r.Salida -match '(?m)^JAVA_HOME despues de un lanzamiento que falla \[C:\\jdk-del-script\]$') (Cola $r.Salida)
}

# ===================== LA CAUSA DE VERDAD DE UN TEST QUE DA ERROR (m28) =====================
# Cuando el test del arnes del original da error, el motivo lleva, al final, 'Causa: ' y la del informe de surefire de la copia (target/surefire-reports/*.txt):
# el ultimo 'Caused by:' o, si no hay, la primera linea con texto tras '<<< ERROR!'. mvn-local.ps1 deja ese informe segun el ARNES_SUREFIRE_<X> del test que escribe
# copilot-local.ps1 (guion arnes-surefire-<x>, solo para el arnes del original).

# Lanza un escenario con el arnes del original fallando como dice $Guion y devuelve la consola, la tarea (atascada) y el prompt del reintento.
function Arnes-Falla-Surefire([string]$Nombre, [string]$Guion) {
  $e = Nuevo-Escenario $Nombre ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba $e @() ($Guion + ':arnes-original')
  $reintento = ''
  if (Test-Path -LiteralPath (Get-Ruta $e.Local 'registros/arnes-original-2.log')) { $reintento = Lee $e.Local 'registros/arnes-original-2.log' }
  return [pscustomobject]@{ E = $e; R = $r; T = (Lee-Json (Get-Ruta $e.Local 'tareas/arnes-original.json')); Reintento = $reintento }
}

$M28Fondo = 'Caused by: java.lang.IllegalArgumentException: Could not resolve placeholder ''acme.entrada.ruta'' in value "${acme.entrada.ruta}"'

$Pruebas['m28 (a) el arnes del original da error en el test: el motivo acaba con Causa: y el ultimo Caused by del informe de surefire, y lo ven el reintento y la consola'] = {
  $x = Arnes-Falla-Surefire 'm28-a' 'arnes-surefire-error'
  Igual 'sale con 1' 1 $x.R.Codigo
  Igual 'el arnes queda atascado' 'atascada' $x.T.estado
  $m = [string]$x.T.motivo
  Comprueba 'el motivo sigue diciendo que el job no dejo estado.txt, con las lineas [ERROR] de Maven' ($m -match 'el job cargaJob no ha dejado estado\.txt\. Maven dice:' -and $m -match '\[ERROR\] Failed to execute goal') $m
  Comprueba 'y acaba con una linea Causa: y el ULTIMO Caused by (y, tras ella, la pista de M60: la causa es una propiedad sin valor)' ($m.TrimEnd().EndsWith("`nCausa: " + $M28Fondo + "`n" + (Pista-M60 'acme.entrada.ruta'))) $m
  Comprueba 'no el primero' ($m -notmatch 'Causa: Caused by: org\.springframework') $m
  Comprueba 'el prompt del reintento (registro del intento 2) lleva esa causa' ($x.Reintento.Contains('Causa: ' + $M28Fondo)) (Cola $x.Reintento)
  Comprueba 'la consola la ensena' ($x.R.Salida.Contains('Causa: ' + $M28Fondo)) (Cola $x.R.Salida)
}

$Pruebas['m28 (b) un informe viejo de otra ejecucion y ninguno nuevo: el motivo no lleva la causa vieja, y su Causa: es el mensaje del Failed to execute goal de Maven (m53)'] = {
  $x = Arnes-Falla-Surefire 'm28-b' 'arnes-surefire-viejo'
  Igual 'sale con 1' 1 $x.R.Codigo
  $m = [string]$x.T.motivo
  Comprueba 'el motivo lleva las lineas [ERROR] de Maven' ($m -match '\[ERROR\] Failed to execute goal') $m
  Comprueba 'no lleva la causa vieja' ($m -notmatch 'causa-vieja') $m
  # antes de m53 no habia ninguna linea Causa: (la salida de Maven solo traia el [ERROR] Failed to execute goal ... There are test failures., que no daba causa)
  Comprueba 'la linea Causa: es el mensaje del Failed to execute goal de Maven' ($m -match '(?m)^Causa: There are test failures\.$') $m
  Comprueba 'el prompt del reintento tampoco lleva la causa vieja y lleva esa Causa:' ($x.Reintento -and $x.Reintento -notmatch 'causa-vieja' -and $x.Reintento -match '(?m)^Causa: There are test failures\.') (Cola $x.Reintento)
}

$Pruebas['m28 (c) informe con <<< ERROR! y ningun Caused by: la causa es la primera linea con texto despues'] = {
  $x = Arnes-Falla-Surefire 'm28-c' 'arnes-surefire-sin-causa'
  $m = [string]$x.T.motivo
  Comprueba 'acaba con Causa: y esa linea (no la del nombre del test)' ($m.TrimEnd().EndsWith("`nCausa: java.lang.NullPointerException: no hay nada de fondo")) $m
}

$Pruebas['m28 (d) la causa se recorta a 300 caracteres'] = {
  $x = Arnes-Falla-Surefire 'm28-d' 'arnes-surefire-larga'
  $m = [string]$x.T.motivo
  $causa = [regex]::Match($m, '(?m)^Causa: (.*)$').Groups[1].Value
  Igual 'la causa mide 300' 300 $causa.Length
  Comprueba 'y es el principio del ultimo Caused by' ($causa.StartsWith('Caused by: java.lang.IllegalStateException: largalarga')) $causa
}

# Surefire 2.x recorta la traza del informe (trimStackTrace) y puede dejarlo sin la cadena de Caused by: la traza entera sale en la salida de Maven.
$Pruebas['m28 (e) sin informe de surefire y con dos Caused by en la salida de Maven: la causa es el ultimo, sin el [ERROR] de delante'] = {
  $x = Arnes-Falla-Surefire 'm28-e' 'arnes-surefire-salida'
  Igual 'sale con 1' 1 $x.R.Codigo
  $m = [string]$x.T.motivo
  Comprueba 'el motivo acaba con Causa: y el ultimo Caused by de la salida (y, tras ella, la pista de M60: la causa es una propiedad sin valor)' ($m.TrimEnd().EndsWith("`nCausa: " + $M28Fondo + "`n" + (Pista-M60 'acme.entrada.ruta'))) $m
  Comprueba 'el prompt del reintento la lleva' ($x.Reintento.Contains('Causa: ' + $M28Fondo)) (Cola $x.Reintento)
}

$Pruebas['m28 (f) informe con <<< ERROR! y sin Caused by, y un Caused by en la salida de Maven: gana el de la salida'] = {
  $x = Arnes-Falla-Surefire 'm28-f' 'arnes-surefire-sin-causa-con-salida'
  $m = [string]$x.T.motivo
  Comprueba 'el motivo acaba con Causa: y el Caused by de la salida, no la linea del informe' ($m.TrimEnd().EndsWith("`nCausa: Caused by: java.net.ConnectException: Connection refused")) $m
  Comprueba 'y no lleva la excepcion del informe como causa' ($m -notmatch 'Causa: java\.lang\.NullPointerException') $m
}

# ===================== M29: el test del migrado se escribe traduciendo el del original =====================
# Estos escenarios usan m29-copilot.ps1 y m29-mvn.ps1 (sobre los de m25): el falso de Copilot apunta en la llamada de un arnes si su prompt
# lleva la seccion de traducir el test del original (traduce=, original=, original-existe=) y deja en el test una marca con el numero de la
# llamada (MARCA_ARNES=<repo>-<n>); el de Maven apunta en m29-tests.log con que marca se ejecuto cada caso. Con $Distinto, el migrado lleva el
# limite de m25 (5.01) y el caso importe=5.00 sale distinto.

function Escenario-M29([string]$Nombre, $Casos, [switch]$Distinto) {
  if ($Distinto) { $e = Escenario-M25 $Nombre $Casos } else { $e = Nuevo-Escenario $Nombre $Casos }
  $aj = [ordered]@{ CopilotExe = (Join-Path $falsos 'm29-copilot.ps1'); MvnExe = (Join-Path $falsos 'm29-mvn.ps1'); SegundosPorLlamada = 60 }
  Escribe $e.Home 'ajustes.json' (ConvertTo-Json -InputObject $aj)
  return $e
}

# Los tests guardados de cada lado: donde los deja Save-Arnes.
function Test-Guardado($E, [string]$Repo) {
  $paquete = 'viejo'
  if ($Repo -eq 'migrado') { $paquete = 'nuevo' }
  return (Lee $E.Local "arnes/$Repo/src/test/java/com/acme/$paquete/PruebaLocalTest.java")
}

function Llamadas-Arnes($E, [string]$Repo) { return @(Llamadas $E | Where-Object { $_.id -eq "arnes-$Repo" }) }

# Las ejecuciones de casos que apunto m29-mvn.ps1 desde la linea $Desde, de la copia $Copia: la marca del arnes con que se ejecuto cada una.
function Marcas-Casos($E, [string]$Copia, [int]$Desde = 0) {
  $f = Join-Path $E.Llamadas 'm29-tests.log'
  if (-not (Test-Path -LiteralPath $f)) { return @() }
  $lineas = @([System.IO.File]::ReadAllLines($f))
  return @($lineas | Select-Object -Skip $Desde | ForEach-Object { $c, $caso, $marca = $_ -split '\|'; if ($c -eq $Copia -and $caso -like 'caso-*') { $marca } })
}

function Lineas-Marcas($E) {
  $f = Join-Path $E.Llamadas 'm29-tests.log'
  if (-not (Test-Path -LiteralPath $f)) { return 0 }
  return @([System.IO.File]::ReadAllLines($f)).Count
}

$Traducelo = 'trad' + [char]0xFA + 'celo'

$Pruebas['m29 (a) los dos arneses pendientes: el del migrado se escribe despues del del original, con la ruta del test guardado y el texto de traducirlo; el del original no lleva la seccion'] = {
  $e = Escenario-M29 'm29-a' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $env:RESCATE_ESPERA = '2'
  try { $r = Prueba $e }
  finally { $env:RESCATE_ESPERA = '' }
  Igual 'sale con 0' 0 $r.Codigo
  $o = @(Llamadas-Arnes $e 'original')
  $m = @(Llamadas-Arnes $e 'migrado')
  Igual 'una llamada de arnes del original' 1 $o.Count
  Igual 'y una del migrado' 1 $m.Count
  Comprueba 'la del migrado empieza despues de que acabe la del original' ([long]$m[0].inicio -ge [long]$o[0].fin) "original fin=$($o[0].fin), migrado inicio=$($m[0].inicio)"
  Igual 'los dos arneses no van a la vez' 1 (Max-Simultaneas @($o + $m))
  $ruta = Get-Ruta $e.Local 'arnes/original/src/test/java/com/acme/viejo/PruebaLocalTest.java'
  $pm = Registro-Arnes $e 'migrado' 1
  $po = Registro-Arnes $e 'original' 1
  Comprueba 'el prompt del migrado lleva la ruta del test guardado del original' ($pm.Contains($ruta)) $ruta
  Comprueba 'y el texto de traducirlo' ($pm.Contains($Traducelo))
  Comprueba 'el prompt del original no lleva esa seccion' (-not $po.Contains($Traducelo) -and -not $po.Contains('El test del original ya'))
  Comprueba 'ni una llave de la plantilla sin sustituir en ninguno' ($pm -notmatch '\{\{' -and $po -notmatch '\{\{')
  Igual 'el falso ve el prompt del migrado con la seccion' 'si' $m[0].traduce
  Igual 'y el del original, sin ella' 'no' $o[0].traduce
  Igual 'el falso lee la ruta del original en el prompt' $ruta $m[0].original
  Igual 'cuando el migrado empieza, el test del original ya esta guardado' 'si' $m[0].'original-existe'
  Comprueba 'la carpeta del arnes guardado del original va en los dirs de la llamada del migrado' ($m[0].flags.Contains('--add-dir=' + (Get-Ruta $e.Local 'arnes/original'))) $m[0].flags
  Comprueba 'y no en los del original' (-not $o[0].flags.Contains('arnes/original')) $o[0].flags
}

$Pruebas['m29 (b) -RehacerArnes con los dos arneses hechos: una sola llamada de arnes, la del migrado; el del original no cambia y los casos del migrado se ejecutan con el arnes nuevo'] = {
  $e = Escenario-M29 'm29-b' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba $e
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  $original = Test-Guardado $e 'original'
  $migrado = Test-Guardado $e 'migrado'
  Comprueba 'el migrado guardado lleva la marca de su primera llamada' ($migrado.Contains('MARCA_ARNES=migrado-1')) $migrado
  $n = @(Llamadas $e).Count
  $lineas = Lineas-Marcas $e
  $r = Prueba $e @('-RehacerArnes')
  Igual 'con -RehacerArnes sale con 0' 0 $r.Codigo
  Igual 'una sola llamada nueva' ($n + 1) @(Llamadas $e).Count
  Igual 'y es de arnes: ahora hay tres' 3 @(Llamadas $e | Where-Object { $_.tipo -eq 'arnes-local' }).Count
  Igual 'hay una llamada del original (la de antes)' 1 (Llamadas-Arnes $e 'original').Count
  Igual 'y dos del migrado' 2 (Llamadas-Arnes $e 'migrado').Count
  Igual 'el arnes del original guardado no cambia' $original (Test-Guardado $e 'original')
  $nuevo = Test-Guardado $e 'migrado'
  Comprueba 'el del migrado guardado es el de la segunda llamada' ($nuevo.Contains('MARCA_ARNES=migrado-2') -and $nuevo -ne $migrado) $nuevo
  $marcas = @(Marcas-Casos $e $e.CopiaMig $lineas)
  Igual 'los dos casos del migrado se vuelven a ejecutar' 2 $marcas.Count
  Comprueba 'con el arnes nuevo' (@($marcas | Where-Object { $_ -ne 'migrado-2' }).Count -eq 0) ($marcas -join ',')
  Igual 'la tarea del migrado queda hecha' 'hecha' (Tarea-Arnes $e 'migrado').estado
  Igual 'los casos salen iguales' 'igual,igual' ((Resultados $e) -join ',')
  Comprueba 'no dice que use el arnes de otro lanzamiento' ($r.Salida -notmatch 'el test de otro lanzamiento sigue valiendo') (Cola $r.Salida)
  $n = @(Llamadas $e).Count
  $r = Prueba $e
  Igual 'sin el switch, el siguiente lanzamiento no vuelve a llamar' $n @(Llamadas $e).Count
  Igual 'y el arnes del migrado sigue siendo el rehecho' $nuevo (Test-Guardado $e 'migrado')
}

$Pruebas['m29 (c) -RehacerArnes -Reparar: una clave que salio no se arregla se vuelve a probar con el arnes nuevo; sin el switch no, y la pista sale una sola vez'] = {
  $e = Escenario-M29 'm29-c' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') }) -Distinto
  $pista = 'Si la IA dice que la diferencia es del test del migrado y no del codigo, relanza con -RehacerArnes.'
  $r = Prueba $e @('-Reparar') 'reparar-no'
  Igual 'sale con 2 (el caso sigue distinto)' 2 $r.Codigo
  Igual 'la clave sale no se arregla' 'no se arregla' (@(Reparaciones $e)[0]).resultado
  Igual 'con una llamada de reparar' 1 (Llamadas-Reparar $e).Count
  Igual 'la pista sale una sola vez' 1 ([regex]::Matches($r.Salida, [regex]::Escape($pista))).Count
  Comprueba 'y despues de la lista de reparaciones' ($r.Salida.IndexOf($pista) -gt $r.Salida.IndexOf('Reparaciones:')) (Cola $r.Salida)
  $r = Prueba $e @('-Reparar') 'reparar-no'
  Igual 'relanzado sin el switch no llama otra vez a reparar' 1 (Llamadas-Reparar $e).Count
  Igual 'la clave sigue en no se arregla' 'no se arregla' (@(Reparaciones $e)[0]).resultado
  $r = Prueba $e @('-RehacerArnes', '-Reparar') 'reparar-no'
  Igual 'con -RehacerArnes -Reparar sale con 2' 2 $r.Codigo
  Igual 'se rehace el arnes del migrado' 2 (Llamadas-Arnes $e 'migrado').Count
  Igual 'y la misma clave se vuelve a probar: otra llamada de reparar' 2 (Llamadas-Reparar $e).Count
  Comprueba 'no dice que ya estaba probada con este codigo del migrado' ($r.Salida -notmatch 'ya probado con este codigo del migrado') (Cola $r.Salida)
  $rep = @(Reparaciones $e)
  Igual 'sigue una sola reparacion' 1 $rep.Count
  Igual 'la clave vuelve a salir no se arregla' 'no se arregla' $rep[0].resultado
  Igual 'y la pista vuelve a salir, una vez' 1 ([regex]::Matches($r.Salida, [regex]::Escape($pista))).Count
}

$Pruebas['m29 (d) la plantilla del arnes: carga datos.sql con ScriptUtils o ResourceDatabasePopulator, pone adjunto= en el correo, no deja sustituir clases del batch y lleva la seccion de traducir solo para el migrado'] = {
  $t = [System.IO.File]::ReadAllText((Join-Path (Join-Path (Split-Path -Parent $Script) 'tareas') 'arnes-local.md'), (New-Object System.Text.UTF8Encoding($false)))
  Comprueba 'carga datos.sql con ScriptUtils.executeSqlScript o ResourceDatabasePopulator de Spring' ($t -match 'ScriptUtils\.executeSqlScript' -and $t -match 'ResourceDatabasePopulator')
  Comprueba 'y dice que no se parte a mano por ;' ($t -match 'No lo partas a mano')
  Comprueba 'cada adjunto del correo va en la cabecera con adjunto=<nombre del fichero>' ($t -match 'adjunto=<nombre del fichero>')
  Comprueba 'el cuerpo del correo es el del mensaje' ($t -match 'como qued.r.a en la bandeja')
  Comprueba 'sustituye la clase de la libreria que abre la conexion (JavaMailSender, RestTemplate)' ($t -match 'JavaMailSender' -and $t -match 'RestTemplate')
  Comprueba 'nunca los puertos, adaptadores o servicios del batch' ($t -match 'Nunca sustituyas[^.]*puertos[^.]*adaptadores[^.]*servicios del batch')
  Comprueba 'la seccion del test del original solo sale con la clave SI_ORIGINAL' ($t -match '\{\{SI_ORIGINAL\}\}' -and $t.Contains('{{ORIGINAL}}') -and $t.Contains($Traducelo))
  $conOriginal = @($t -split "`n" | Where-Object { $_.Contains($Traducelo) -or $_.Contains('{{ORIGINAL}}') })
  Comprueba 'y cada linea de esa seccion lleva la clave' (@($conOriginal | Where-Object { -not $_.StartsWith('{{SI_ORIGINAL}}') }).Count -eq 0) ($conOriginal -join ' / ')
}

$Pruebas['m29 (e) el arnes del original atascado: el del migrado no se lanza y se para como hoy'] = {
  $e = Escenario-M29 'm29-e' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba $e @() 'arnes-no-compila:arnes-original'
  Igual 'sale con 1' 1 $r.Codigo
  Igual 'el arnes del original queda atascado' 'atascada' (Tarea-Arnes $e 'original').estado
  Igual 'sin ninguna llamada de arnes del migrado' 0 (Llamadas-Arnes $e 'migrado').Count
  Igual 'y su tarea sigue pendiente' 'pendiente' (Tarea-Arnes $e 'migrado').estado
  Comprueba 'la consola dice que el del original ha quedado atascado' ($r.Salida -match 'PruebaLocalTest del original ha quedado atascado') (Cola $r.Salida)
}

$Pruebas['m29 (f) la huella del arnes del migrado lleva el hash del test del original guardado: si cambia, la tarea deja de estar hecha y el test guardado, si vale, se reutiliza'] = {
  $e = Escenario-M29 'm29-f' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba $e
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  $huella = (Tarea-Arnes $e 'migrado').entradas.huella
  $n = @(Llamadas $e).Count
  $r = Prueba $e
  Igual 'sin cambios, sin llamadas' $n @(Llamadas $e).Count
  Igual 'y la huella es la de antes' $huella (Tarea-Arnes $e 'migrado').entradas.huella
  Comprueba 'sin aviso de que se use un test de otro lanzamiento' ($r.Salida -notmatch 'el test de otro lanzamiento sigue valiendo') (Cola $r.Salida)
  [System.IO.File]::AppendAllText((Get-Ruta $e.Local 'arnes/original/src/test/java/com/acme/viejo/PruebaLocalTest.java'), "// otro test`n")
  $r = Prueba $e
  Igual 'con otro test del original sale con 0' 0 $r.Codigo
  Igual 'sin llamadas: el test del migrado guardado sigue valiendo' $n @(Llamadas $e).Count
  Comprueba 'la tarea del migrado dejo de estar hecha y vuelve a estarlo por el test de otro lanzamiento' ($r.Salida -match 'Arnes del migrado: bien \(el test de otro lanzamiento sigue valiendo\)') (Cola $r.Salida)
  Comprueba 'la tarea del original no' ($r.Salida -notmatch 'Arnes del original: bien \(el test de otro lanzamiento') (Cola $r.Salida)
  $t = Tarea-Arnes $e 'migrado'
  Comprueba 'queda hecha, con otra huella' ($t.estado -eq 'hecha' -and $t.entradas.huella -ne $huella) "$($t.estado) $($t.entradas.huella)"
}

$Pruebas['m29 (g) -RehacerArnes pregunta como hoy antes de llamar a Copilot: con no, no se hace nada y el arnes guardado se queda'] = {
  $e = Escenario-M29 'm29-g' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba $e
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  $migrado = Test-Guardado $e 'migrado'
  $n = @(Llamadas $e).Count
  $r = Prueba $e @('-RehacerArnes') '' 'n'
  Comprueba 'pregunta por la tarea que va a llamar' ($r.Salida -match 'Llamar a Copilot para esas 1 tareas\?') (Cola $r.Salida)
  Comprueba 'con n dice que no se ha hecho nada' ($r.Salida -match 'No se ha hecho nada') (Cola $r.Salida)
  Igual 'sin llamadas nuevas' $n @(Llamadas $e).Count
  Igual 'y el arnes guardado del migrado sigue ahi' $migrado (Test-Guardado $e 'migrado')
  $r = Prueba $e @('-RehacerArnes') '' 's'
  Igual 'con s sale con 0' 0 $r.Codigo
  Igual 'y llama una vez' ($n + 1) @(Llamadas $e).Count
  Comprueba 'con el arnes nuevo guardado' ((Test-Guardado $e 'migrado').Contains('MARCA_ARNES=migrado-2'))
}

$Pruebas['m29 (h) -RehacerArnes con un arnes nuevo que no vale: lo viejo ya no esta guardado y el siguiente lanzamiento, sin el switch, vuelve a llamar a la IA en vez de reutilizarlo'] = {
  $e = Escenario-M29 'm29-h' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba $e
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  $original = Test-Guardado $e 'original'
  Comprueba 'el arnes del migrado queda guardado' (Test-Path -LiteralPath (Get-Ruta $e.Local 'arnes/migrado'))
  $r = Prueba $e @('-RehacerArnes') 'arnes-no-compila:arnes-migrado'
  Igual 'con -RehacerArnes y un test que no compila sale con 1' 1 $r.Codigo
  Igual 'el arnes del migrado queda atascado' 'atascada' (Tarea-Arnes $e 'migrado').estado
  Igual 'tras su llamada de antes y los dos intentos de ahora' 3 (Llamadas-Arnes $e 'migrado').Count
  Comprueba 'el arnes viejo del migrado ya no esta guardado' (-not (Test-Path -LiteralPath (Get-Ruta $e.Local 'arnes/migrado')))
  Igual 'el del original sigue como estaba' $original (Test-Guardado $e 'original')
  $r = Prueba $e
  Igual 'el siguiente lanzamiento, sin el switch, sale con 0' 0 $r.Codigo
  Igual 'vuelve a llamar a la IA para el migrado' 4 (Llamadas-Arnes $e 'migrado').Count
  Comprueba 'y no usa el arnes viejo' ($r.Salida -notmatch 'Arnes del migrado: bien \(el test de otro lanzamiento sigue valiendo\)') (Cola $r.Salida)
  Comprueba 'lo guardado ahora es lo que escribio esa llamada' ((Test-Guardado $e 'migrado').Contains('MARCA_ARNES=migrado-4'))
  Igual 'la tarea del migrado queda hecha' 'hecha' (Tarea-Arnes $e 'migrado').estado
}

# ===================== M30: lo que la IA toca de mas, el script lo deshace y prueba lo que queda =====================
# Estos escenarios usan m30-copilot.ps1 y m30-mvn.ps1 (sobre los de m25 y, con ellos, los de siempre): el Copilot de mentira deja, ademas de
# un arnes bueno, lo que dice su guion (ficheros de mas, un pom.xml cambiado, un cambio en src/main/ sin el que el arnes no compila). Con
# -Pom, el original lleva un pom.xml con CRLF y dos dependencias (org.projectlombok:lombok 1.16.20 y com.acme:otra con scope provided).
# Con -Reparar, el escenario es el de m25 (con tests que pasan) y ReglaTest.java con seguimiento en el migrado.

# El pom.xml del original de los escenarios con -Pom, con el salto de linea $Nl.
function Pom-M30([string]$Nl) {
  $l = @('<?xml version="1.0" encoding="UTF-8"?>', '<project xmlns="http://maven.apache.org/POM/4.0.0">', '  <!-- el pom del batch -->', '  <modelVersion>4.0.0</modelVersion>',
    '  <groupId>com.acme</groupId>', '  <artifactId>batch-viejo</artifactId>', '  <version>1.0.0</version>', '  <description/>', '  <dependencies>',
    '    <dependency>', '      <groupId>org.projectlombok</groupId>', '      <artifactId>lombok</artifactId>', '      <version>1.16.20</version>', '    </dependency>',
    '    <dependency>', '      <groupId>com.acme</groupId>', '      <artifactId>otra</artifactId>', '      <version>3.0</version>', '      <scope>provided</scope>', '    </dependency>',
    '  </dependencies>', '</project>')
  return (($l -join $Nl) + $Nl)
}

function Escenario-M30([string]$Nombre, $Casos, [switch]$Reparar, [switch]$Pom) {
  if ($Reparar) {
    $e = Escenario-M25 $Nombre $Casos -Sano
    [void](Commit-En $e.Wt 'src/test/java/com/acme/nuevo/ReglaTest.java' "package com.acme.nuevo;`nclass ReglaTest {}`n" 'test de la regla')
  }
  else { $e = Nuevo-Escenario $Nombre $Casos }
  $aj = [ordered]@{ CopilotExe = (Join-Path $falsos 'm30-copilot.ps1'); MvnExe = (Join-Path $falsos 'm30-mvn.ps1'); SegundosPorLlamada = 60 }
  Escribe $e.Home 'ajustes.json' (ConvertTo-Json -InputObject $aj)
  if ($Pom) { [void](Commit-En $e.Legacy 'pom.xml' (Pom-M30 "`r`n") 'pom con dependencias') }
  return $e
}

# Un mvnw de mentira (sh) en $Repo, ya en git y ejecutable: falla si no tiene al lado .mvn/wrapper/maven-wrapper.properties (como el de verdad
# sin red: intenta bajarse el wrapper) y, si lo tiene, hace lo que el Maven de mentira $Falso.
function Pon-Mvnw([string]$Repo, [string]$Falso) {
  Escribe $Repo 'mvnw' ("#!/bin/sh`n" + "[ -f ./.mvn/wrapper/maven-wrapper.properties ] || { echo '[ERROR] no puedo bajar el wrapper de repo.maven.apache.org'; exit 1; }`n" + "exec '" + $ps + "' -NoProfile -File '" + $Falso + "' `"`$@`"`n")
  & chmod +x (Get-Ruta $Repo 'mvnw')
  [void](GitEn $Repo @('add', '--', 'mvnw'))
  [void](GitEn $Repo @('update-index', '--chmod=+x', '--', 'mvnw'))
  [void](GitEn $Repo @('commit', '-q', '-m', 'mvnw'))
}

$Pruebas['m30 (a) Maven de la copia: .mvn/wrapper/ del repo pasa a la copia sin pisar lo que git ya trae, y Get-Mvn solo usa mvnw si tiene maven-wrapper.properties al lado'] = {
  $e = Nuevo-Escenario 'm30-a' ([ordered]@{ cargaJob = @('importe=10.00') })
  foreach ($d in @($e.Legacy, $e.Migrado)) {
    [void](Commit-En $d '.mvn/wrapper/en-git.txt' "de git`n" 'wrapper en git')
    Escribe $d '.mvn/wrapper/en-git.txt' "tocado a mano`n"
    Escribe $d '.mvn/wrapper/maven-wrapper.properties' "distributionUrl=x`n"
    Escribe $d '.mvn/wrapper/maven-wrapper.jar' "jar`n"
  }
  $r = Prueba $e
  Igual 'sale con 0' 0 $r.Codigo
  foreach ($c in @($e.CopiaOrig, $e.CopiaMig)) {
    $props = Get-Ruta $c '.mvn/wrapper/maven-wrapper.properties'
    $texto = '(no esta)'
    if (Test-Path -LiteralPath $props) { $texto = [System.IO.File]::ReadAllText($props) }
    Igual "$(Split-Path $c -Leaf): la copia trae maven-wrapper.properties, que git no tiene" "distributionUrl=x`n" $texto
    Comprueba "$(Split-Path $c -Leaf): y el jar" (Test-Path -LiteralPath (Get-Ruta $c '.mvn/wrapper/maven-wrapper.jar'))
  }
  $enGit = Get-Ruta $e.CopiaOrig '.mvn/wrapper/en-git.txt'
  $texto = '(no esta)'
  if (Test-Path -LiteralPath $enGit) { $texto = [System.IO.File]::ReadAllText($enGit) }
  Igual 'lo que git ya trae en la copia no se pisa' "de git`n" $texto
  if ($env:OS -ne 'Windows_NT') {   # el mvnw de mentira es un script de sh
    $e2 = Nuevo-Escenario 'm30-a2' ([ordered]@{ cargaJob = @('importe=10.00') })
    Escribe $e2.Home 'ajustes.json' (ConvertTo-Json -InputObject ([ordered]@{ CopilotExe = (Join-Path $falsos 'copilot-local.ps1'); SegundosPorLlamada = 60 }))
    foreach ($d in @($e2.Legacy, $e2.Migrado, $e2.Wt)) { Pon-Mvnw $d (Join-Path $falsos 'mvn-local.ps1') }
    foreach ($d in @($e2.Legacy, $e2.Migrado)) { Escribe $d '.mvn/wrapper/maven-wrapper.properties' "distributionUrl=x`n" }
    $r = Prueba $e2
    Igual 'con un mvnw que sin su maven-wrapper.properties no funciona (y sin MvnExe), sale con 0' 0 $r.Codigo
    Igual 'y el caso sale igual' 'igual' ((Resultados $e2) -join ',')
  }
  $f = Join-Path $Dir 'get-mvn.ps1'
  [System.IO.File]::WriteAllText($f, "param([string]`$Sis, [string]`$Raiz)`n. (Join-Path `$Sis 'comun.ps1')`n'MVN ' + (Get-Mvn `$Raiz)`n")
  $sis = Split-Path -Parent $Script
  $raiz = Join-Path $Dir 'm30-a-get-mvn'
  Escribe $raiz 'mvnw' "x`n"
  Escribe $raiz 'mvnw.cmd' "x`n"
  $r = Lanzar $f @($sis, $raiz)
  Igual 'con mvnw y sin maven-wrapper.properties, Get-Mvn da mvn' 'MVN mvn' (@($r.Salida -split "`n" | Where-Object { $_ -like 'MVN *' })[0]).Trim()
  Escribe $raiz '.mvn/wrapper/maven-wrapper.properties' "distributionUrl=x`n"
  $r = Lanzar $f @($sis, $raiz)
  $envoltorio = 'mvnw'
  if ([System.IO.Path]::DirectorySeparatorChar -eq '\') { $envoltorio = 'mvnw.cmd' }
  Igual 'con maven-wrapper.properties al lado, el envoltorio' ('MVN ' + (Join-Path $raiz $envoltorio)) (@($r.Salida -split "`n" | Where-Object { $_ -like 'MVN *' })[0]).Trim()
}

$Pruebas['m30 (b) arnes: la IA deja META-INF/ y un .class en la raiz y toca src/main (y el pom del migrado): sale bien, lo de fuera se deshace y la consola lo dice'] = {
  $e = Escenario-M30 'm30-b' ([ordered]@{ cargaJob = @('importe=10.00') })
  $appO = Lee $e.Legacy 'src/main/java/com/acme/viejo/App.java'
  $appM = Lee $e.Wt 'src/main/java/com/acme/nuevo/App.java'
  $pomM = Lee $e.Wt 'pom.xml'
  $r = Prueba $e @() 'arnes-de-mas'
  Igual 'sale con 0' 0 $r.Codigo
  foreach ($lado in @('original', 'migrado')) { Igual "el arnes del $lado sale bien a la primera" 'hecha/1' "$((Tarea-Arnes $e $lado).estado)/$((Tarea-Arnes $e $lado).intentos)" }
  foreach ($c in @($e.CopiaOrig, $e.CopiaMig)) {
    $n = Split-Path $c -Leaf
    Comprueba "${n}: META-INF/MANIFEST.MF ya no esta" (-not (Test-Path -LiteralPath (Get-Ruta $c 'META-INF/MANIFEST.MF'))) (Cola $r.Salida)
    Comprueba "${n}: com/x/Y.class tampoco" (-not (Test-Path -LiteralPath (Get-Ruta $c 'com/x/Y.class'))) (Cola $r.Salida)
  }
  Igual 'el original: el fichero de src/main vuelve a como estaba' $appO (Lee $e.CopiaOrig 'src/main/java/com/acme/viejo/App.java')
  Igual 'el migrado: el de src/main vuelve a como estaba' $appM (Lee $e.CopiaMig 'src/main/java/com/acme/nuevo/App.java')
  Igual 'y su pom.xml (que el arnes del migrado no puede tocar)' $pomM (Lee $e.CopiaMig 'pom.xml')
  Comprueba 'el arnes guardado del original no lleva lo de fuera' (-not (Test-Path -LiteralPath (Get-Ruta $e.Local 'arnes/original/META-INF')) -and (Test-Path -LiteralPath (Get-Ruta $e.Local 'arnes/original/src/test/java/com/acme/viejo/PruebaLocalTest.java'))) ''
  Comprueba 'la consola dice lo que deshace en el original' ($r.Salida.Contains('Deshago lo que la IA ha tocado fuera de lo suyo: META-INF/MANIFEST.MF, com/x/Y.class, src/main/java/com/acme/viejo/App.java')) (Cola $r.Salida)
  Comprueba 'y en el migrado, con su pom.xml' ($r.Salida.Contains('Deshago lo que la IA ha tocado fuera de lo suyo: META-INF/MANIFEST.MF, com/x/Y.class, pom.xml, src/main/java/com/acme/nuevo/App.java')) (Cola $r.Salida)
  Comprueba 'y no rechaza el arnes' ($r.Salida -notmatch 'Arnes del (original|migrado) rechazado') (Cola $r.Salida)
  $e = Escenario-M30 'm30-b2' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba $e @() 'arnes-de-mas-muchos:arnes-original'
  Igual 'con siete ficheros de mas sale con 0' 0 $r.Codigo
  Comprueba 'la consola nombra cinco y dice cuantos mas' ($r.Salida.Contains('Deshago lo que la IA ha tocado fuera de lo suyo: fuera/f1.txt, fuera/f2.txt, fuera/f3.txt, fuera/f4.txt, fuera/f5.txt (y 2 mas)')) (Cola $r.Salida)
  Comprueba 'y los siete ya no estan' (@(1..7 | Where-Object { Test-Path -LiteralPath (Get-Ruta $e.CopiaOrig "fuera/f$_.txt") }).Count -eq 0) ''
}

$Pruebas['m30 (b3) arnes: con exactamente cinco ficheros de mas la linea los nombra los cinco y no dice cuantos mas'] = {
  $e = Escenario-M30 'm30-b3' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba $e @() 'arnes-de-mas-cinco:arnes-original'
  Igual 'sale con 0' 0 $r.Codigo
  $linea = ([regex]::Match($r.Salida, 'Deshago lo que la IA ha tocado fuera de lo suyo: [^\r\n]*')).Value
  Igual 'la linea lista los cinco, sin (y N mas)' 'Deshago lo que la IA ha tocado fuera de lo suyo: fuera/f1.txt, fuera/f2.txt, fuera/f3.txt, fuera/f4.txt, fuera/f5.txt' $linea
  Comprueba 'y los cinco ya no estan' (@(1..5 | Where-Object { Test-Path -LiteralPath (Get-Ruta $e.CopiaOrig "fuera/f$_.txt") }).Count -eq 0) ''
}

$Pruebas['m30 (c) pom.xml del original: la IA cambia la version de una dependencia que ya estaba y anade dos nuevas: queda el pom de antes con las dos con scope test, y la consola dice que version deshace'] = {
  $e = Escenario-M30 'm30-c' ([ordered]@{ cargaJob = @('importe=10.00') }) -Pom
  $antes = Lee $e.Legacy 'pom.xml'
  $r = Prueba $e @() 'arnes-pom-lombok:arnes-original'
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'el arnes del original sale bien a la primera' 'hecha/1' "$((Tarea-Arnes $e 'original').estado)/$((Tarea-Arnes $e 'original').intentos)"
  $pom = Lee $e.CopiaOrig 'pom.xml'
  $q = $antes.IndexOf("`r`n  </dependencies>")
  Comprueba 'el pom final empieza y acaba como el original, byte a byte (con sus CRLF, su comentario y su <description/>)' ($q -gt 0 -and $pom.StartsWith($antes.Substring(0, $q), [System.StringComparison]::Ordinal) -and $pom.EndsWith($antes.Substring($q), [System.StringComparison]::Ordinal)) $pom
  $medio = ''
  if ($pom.Length -gt $antes.Length) { $medio = $pom.Substring($q, $pom.Length - $antes.Length) }
  Comprueba 'lo unico que anade son las dos dependencias nuevas' ($medio.Contains('<artifactId>nueva-sin-scope</artifactId>') -and $medio.Contains('<artifactId>nueva-test</artifactId>') -and -not $medio.Contains('lombok')) $medio
  Igual 'las dos con <scope>test</scope>' 2 ([regex]::Matches($medio, '<scope>test</scope>')).Count
  Comprueba 'lombok sigue con su version de antes' ($pom.Contains('<version>1.16.20</version>') -and -not $pom.Contains('1.18.30')) $pom
  Comprueba 'sin BOM' ([System.IO.File]::ReadAllBytes((Get-Ruta $e.CopiaOrig 'pom.xml'))[0] -eq 0x3C) ''
  Igual 'el pom que se guarda con el arnes es ese' $pom (Lee $e.Local 'arnes/original/pom.xml')
  Comprueba 'la consola dice la dependencia y el cambio de version' ($r.Salida -match 'Dejo el pom\.xml del original como estaba, con tus dependencias nuevas de test: [^\r\n]*org\.projectlombok:lombok: <version> 1\.16\.20 -> 1\.18\.30') (Cola $r.Salida)
  Comprueba 'y no rechaza el arnes' ($r.Salida -notmatch 'Arnes del original rechazado') (Cola $r.Salida)
  $e = Escenario-M30 'm30-c2' ([ordered]@{ cargaJob = @('importe=10.00') }) -Pom
  $r = Prueba $e @() 'arnes-pom-mas:arnes-original'
  Igual 'quitar un scope y anadir una <properties>: sale con 0' 0 $r.Codigo
  $pom = Lee $e.CopiaOrig 'pom.xml'
  Comprueba 'la dependencia que ya estaba conserva su scope y no hay <properties>' ($pom.Contains('<scope>provided</scope>') -and -not $pom.Contains('<properties>')) $pom
  Comprueba 'la nueva sin scope lo recibe' ($pom -match '(?s)<artifactId>nueva-sin-scope</artifactId>.*?<scope>test</scope>') $pom
  Comprueba 'la consola dice que scope se quita y que hay algo mas fuera de <dependencies>' ($r.Salida -match 'com\.acme:otra: <scope> quitado' -and $r.Salida.Contains('algo mas del pom.xml fuera de <dependencies>')) (Cola $r.Salida)
  $e = Escenario-M30 'm30-c3' ([ordered]@{ cargaJob = @('importe=10.00') }) -Pom
  $r = Prueba $e @() 'arnes-pom-roto:arnes-original'
  Igual 'un pom que no es XML valido: sale con 0' 0 $r.Codigo
  Igual 'el pom vuelve al del original' (Lee $e.Legacy 'pom.xml') (Lee $e.CopiaOrig 'pom.xml')
  Comprueba 'y la consola lo dice' ($r.Salida -match 'Dejo el pom\.xml del original como estaba, con tus dependencias nuevas de test: [^\r\n]*XML valido') (Cola $r.Salida)
}

$Pruebas['m30 (c4) pom.xml del original: la IA solo cambia la version de una dependencia que ya estaba: el pom final es el del original, byte a byte, y la consola dice que version deshace'] = {
  $e = Escenario-M30 'm30-c4' ([ordered]@{ cargaJob = @('importe=10.00') }) -Pom
  $antes = Lee $e.Legacy 'pom.xml'
  $r = Prueba $e @() 'arnes-pom-version:arnes-original'
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'el arnes del original sale bien a la primera' 'hecha/1' "$((Tarea-Arnes $e 'original').estado)/$((Tarea-Arnes $e 'original').intentos)"
  Igual 'sin dependencias nuevas, el pom final es el del original, byte a byte' $antes (Lee $e.CopiaOrig 'pom.xml')
  Comprueba 'la consola dice la dependencia y el cambio de version' ($r.Salida -match 'Dejo el pom\.xml del original como estaba, con tus dependencias nuevas de test: [^\r\n]*org\.projectlombok:lombok: <version> 1\.16\.20 -> 1\.18\.30') (Cola $r.Salida)
}

$Pruebas['m30 (c5) pom.xml del original: si con el cambio de pom el arnes no compila, el motivo empieza por lo que se ha dejado como estaba, con la lista, y lleva el error de Maven'] = {
  $e = Escenario-M30 'm30-c5' ([ordered]@{ cargaJob = @('importe=10.00') }) -Pom
  $r = Prueba $e @() 'arnes-pom-version-no-compila:arnes-original'
  Igual 'sale con 1 (el arnes del original queda atascado)' 1 $r.Codigo
  $t = Tarea-Arnes $e 'original'
  Igual 'la tarea queda atascada tras dos intentos' 'atascada/2' "$($t.estado)/$($t.intentos)"
  $m = [string]$t.motivo
  Comprueba 'el motivo empieza por lo del pom, con la dependencia y su cambio de version' ($m.StartsWith('Dejo el pom.xml del original como estaba, con tus dependencias nuevas de test: org.projectlombok:lombok: <version> 1.16.20 -> 1.18.30')) $m
  Comprueba 'y sigue con el fallo de Maven' ($m -match 'El test no compila' -and $m -match 'simbolo de mentira') $m
  Comprueba 'el reintento recibe ese motivo' ((Registro-Arnes $e 'original' 2).Contains('Dejo el pom.xml del original como estaba, con tus dependencias nuevas de test')) ''
}

$Pruebas['m30 (d) arnes: deshacer no esconde un fallo: si solo compila con el cambio de src/main que se deshace, se rechaza y el motivo empieza por lo que se ha deshecho y lleva el error de Maven'] = {
  $e = Escenario-M30 'm30-d' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba $e @() 'arnes-solo-con-main:arnes-original'
  Igual 'sale con 1 (el arnes del original queda atascado)' 1 $r.Codigo
  $t = Tarea-Arnes $e 'original'
  Igual 'la tarea queda atascada tras dos intentos' 'atascada/2' "$($t.estado)/$($t.intentos)"
  $m = [string]$t.motivo
  Comprueba 'el motivo empieza por lo que se ha deshecho, con lo permitido y la ruta' ($m.StartsWith('He deshecho lo que tocaste fuera de src/test/java/com/acme/viejo/PruebaLocalTest.java, src/test/resources/application-prueba-local.yml, pom.xml: src/main/java/com/acme/viejo/App.java.')) $m
  Comprueba 'y sigue con el fallo de Maven' ($m -match 'El test no compila' -and $m -match 'MAIN_TOCADO') $m
  Comprueba 'el reintento recibe ese motivo' ((Registro-Arnes $e 'original' 2).Contains('He deshecho lo que tocaste fuera de')) ''
  Comprueba 'el cambio de src/main ya no esta en la copia' (-not (Lee $e.CopiaOrig 'src/main/java/com/acme/viejo/App.java').Contains('MAIN_TOCADO')) ''
}

$Pruebas['m30 (e) -Reparar: un arreglo que cambia src/main/ y un test se acepta con el test deshecho; uno que solo cambia un test da No has cambiado ningun fichero de src/main/'] = {
  $e = Escenario-M30 'm30-e' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') }) -Reparar
  $wt0 = GitEn $e.Wt @('rev-parse', 'HEAD')
  $test = Lee $e.Wt 'src/test/java/com/acme/nuevo/ReglaTest.java'
  $r = Prueba $e @('-Reparar') 'reparar-test'
  Igual 'sale con 0 (el caso sale igual)' 0 $r.Codigo
  Igual 'una sola llamada' 1 (Llamadas-Reparar $e).Count
  $rep = @(Reparaciones $e)
  Igual 'reparaciones: arreglado, en un intento' 'arreglado 1' "$($rep[0].resultado) $($rep[0].intentos)"
  Igual 'un commit nuevo en la rama de rescate' 1 (GitEn $e.Wt @('rev-list', '--count', "$wt0..HEAD"))
  Igual 'que solo toca src/main/' 'src/main/resources/regla.txt' (GitEn $e.Wt @('diff', '--name-only', "$wt0..HEAD"))
  Igual 'el test de la copia queda como estaba' $test (Lee $e.CopiaMig 'src/test/java/com/acme/nuevo/ReglaTest.java')
  Comprueba 'la consola dice que deshace el test' ($r.Salida.Contains('Deshago lo que la IA ha tocado fuera de lo suyo: src/test/java/com/acme/nuevo/ReglaTest.java')) (Cola $r.Salida)
  $e = Escenario-M30 'm30-e2' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') }) -Reparar
  $antes = Estado-Git $e.Wt
  $test = Lee $e.Wt 'src/test/java/com/acme/nuevo/ReglaTest.java'
  $r = Prueba $e @('-Reparar') 'reparar-solo-test'
  Igual 'con un arreglo que solo cambia un test sale con 2' 2 $r.Codigo
  $rep = @(Reparaciones $e)
  Igual 'no arreglado, con dos intentos' 'no arreglado 2' "$($rep[0].resultado) $($rep[0].intentos)"
  Comprueba 'el motivo empieza por lo que se ha deshecho' ($rep[0].motivo.StartsWith('He deshecho lo que tocaste fuera de src/main/: src/test/java/com/acme/nuevo/ReglaTest.java.')) $rep[0].motivo
  Comprueba 'y sigue con No has cambiado ningun fichero de src/main/' ($rep[0].motivo.Contains('No has cambiado ningun fichero de src/main/.')) $rep[0].motivo
  Igual 'sin commit nuevo en la rama de rescate' $antes (Estado-Git $e.Wt)
  Igual 'y el test de la copia, como estaba' $test (Lee $e.CopiaMig 'src/test/java/com/acme/nuevo/ReglaTest.java')
}

$Pruebas['m30 (f) plantillas: la del arnes lleva las tres vinetas nuevas y lo que hace el script con el pom y con lo de fuera; ni ella ni reparar.md dicen que se rechaza entero'] = {
  $tareas = Join-Path (Split-Path -Parent $Script) 'tareas'
  $arnes = [System.IO.File]::ReadAllText((Join-Path $tareas 'arnes-local.md'), [System.Text.Encoding]::UTF8)
  $reparar = [System.IO.File]::ReadAllText((Join-Path $tareas 'reparar.md'), [System.Text.Encoding]::UTF8)
  Comprueba 'el arnes: el script pone el scope test a las dependencias que falten' ($arnes.Contains('Si una no lleva `<scope>test</scope>`, el script se lo pone. Lo dem') -and $arnes -match 'el script lo deja como estaba y prueba tu test sin ese cambio') ''
  Comprueba 'las tres vinetas van en Lo de fuera, simulado, detras de la de sustituir la clase de la libreria y en este orden' ($arnes -match '(?s)## Lo de fuera, simulado.*Sustituye la clase de la librer.a.*spring\.autoconfigure\.exclude.*Cannot register bean definition.*jar tf <jar>.*javap -cp <jar> <clase>.*## Formato de la salida') ''
  Comprueba 'la 1.a: autoconfiguracion con spring.factories o AutoConfiguration.imports' ($arnes.Contains('META-INF/spring.factories') -and $arnes.Contains('META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports') -and $arnes.Contains('`application-prueba-local.yml` con `spring.autoconfigure.exclude`')) ''
  Comprueba 'la 2.a: no declarar un bean con el nombre de otro (dataSource, transactionManager)' ($arnes.Contains('`dataSource` o `transactionManager`') -and $arnes.Contains('otro nombre y `@Primary`')) ''
  Comprueba 'la 3.a: no descomprimir el jar dentro de la copia' ($arnes.Contains('No lo descomprimas dentro de la copia.')) ''
  Comprueba 'el arnes ya no dice que se rechaza el test entero ni que el pom no se toca mas' ($arnes -notmatch 'rechaza el test entero' -and $arnes -notmatch 'Nada m.s del `pom\.xml`') ''
  Comprueba 'reparar.md: lo de fuera de src/main/ se deja como estaba y se prueba el arreglo sin ello' ($reparar -match 'el script lo deja como estaba y prueba tu arreglo sin ese cambio' -and $reparar -notmatch 'rechaza todo tu arreglo') ''
}

# ===================== M31: menos diferencias falsas y un orden de comprobacion mas barato en -Reparar =====================
# m31-mvn.ps1 deja tablas que dice RESCATE_M31 en cada caso, segun el lado, y apunta en mvn.log cada suite de tests unitarios.

# Un escenario normal con el Maven de mentira de m31.
function Escenario-M31([string]$Nombre, $Casos) {
  $e = Nuevo-Escenario $Nombre $Casos
  $aj = [ordered]@{ CopilotExe = (Join-Path $falsos 'copilot-local.ps1'); MvnExe = (Join-Path $falsos 'm31-mvn.ps1'); SegundosPorLlamada = 60 }
  Escribe $e.Home 'ajustes.json' (ConvertTo-Json -InputObject $aj)
  return $e
}

# Lanza -Si con el guion de tablas $Guion de m31-mvn.ps1 y devuelve lo de Prueba.
function Prueba-M31($E, [string]$Guion) {
  $env:RESCATE_M31 = $Guion
  try { return (Prueba $E) }
  finally { $env:RESCATE_M31 = '' }
}

# La posicion de la ultima de las $Lineas que casa con $Patron (-1 si ninguna).
function Ultimo-Indice([string[]]$Lineas, [string]$Patron) {
  $u = -1
  for ($i = 0; $i -lt $Lineas.Count; $i++) { if ($Lineas[$i] -match $Patron) { $u = $i } }
  return $u
}

$Pruebas['m31 (a) tablas: las mismas filas con las columnas y las filas en otro orden salen iguales; con un valor cambiado salen distintas y la linea ensenada sale reordenada; con una fila rara se compara tal cual'] = {
  $e = Escenario-M31 'm31-a' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M31 $e 'columnas'
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'las mismas filas con otro orden de columnas y de filas: igual' 'igual' (Caso $e 'cargaJob' 'caso-01').resultado
  $e = Escenario-M31 'm31-a2' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M31 $e 'columnas-valor'
  Igual 'con un valor cambiado sale con 2' 2 $r.Codigo
  $c = Caso $e 'cargaJob' 'caso-01'
  Igual 'el caso sale distinto' 'distinto' $c.resultado
  $d = @($c.diferencias)
  Igual 'con una sola diferencia, en la tabla' 'tablas/T.csv' ($d | ForEach-Object { $_.fichero }) 
  Igual 'una linea distinta' 1 $d[0].lineas
  Igual 'la tercera: la de luis, ya reordenada' 3 $d[0].linea
  Igual 'lo del original, con las columnas en orden de nombre' '2;20;luis' $d[0].original
  Igual 'y lo del migrado, igual' '2;25;luis' $d[0].migrado
  $e = Escenario-M31 'm31-a3' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M31 $e 'columnas-fila-rara'
  Igual 'con una fila de otro numero de campos sale con 2' 2 $r.Codigo
  $d = @((Caso $e 'cargaJob' 'caso-01').diferencias)
  Igual 'se compara tal cual: la primera linea es la cabecera de cada lado' 'ID;NOMBRE|NOMBRE;ID' "$($d[0].original)|$($d[0].migrado)"
}

$Pruebas['m31 (a4) un .csv fuera de tablas/ con las columnas permutadas no se reordena: sale distinto'] = {
  $e = Escenario-M31 'm31-a4' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M31 $e 'csv-fuera'
  Igual 'sale con 2' 2 $r.Codigo
  $c = Caso $e 'cargaJob' 'caso-01'
  Igual 'el caso sale distinto' 'distinto' $c.resultado
  $d = @($c.diferencias)
  Igual 'por ese fichero y solo por ese' 'ficheros/salida/x.csv' ($d | ForEach-Object { $_.fichero })
  Igual 'se compara tal cual: la primera linea es la cabecera de cada lado' 'ID;NOMBRE;IMPORTE|NOMBRE;IMPORTE;ID' "$($d[0].original)|$($d[0].migrado)"
}

$Pruebas['m31 (b) tablas del framework: TASK_EXECUTION.csv solo en el migrado y BATCH_JOB_INSTANCE.csv distinto en los dos no cuentan: el caso sale igual'] = {
  $e = Escenario-M31 'm31-b' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M31 $e 'framework'
  Igual 'sale con 0' 0 $r.Codigo
  $c = Caso $e 'cargaJob' 'caso-01'
  Igual 'el caso sale igual' 'igual' $c.resultado
  Igual 'sin diferencias' 0 @($c.diferencias).Count
  Comprueba 'las tablas estan en las salidas de los dos lados (es la comparacion la que no las cuenta)' ((Test-Path -LiteralPath (Get-Ruta $e.Local 'salidas/migrado/cargaJob/caso-01/tablas/TASK_EXECUTION.csv')) -and (Test-Path -LiteralPath (Get-Ruta $e.Local 'salidas/original/cargaJob/caso-01/tablas/BATCH_JOB_INSTANCE.csv'))) ''
}

$Pruebas['m31 (c) -Reparar: un arreglo que mejora su caso pero rompe un test unitario se rechaza con el motivo de los tests y los demas casos no se ejecutan'] = {
  $e = Escenario-M25 'm31-c' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') }) -Test -Ajustes @{ MvnExe = (Join-Path $falsos 'm31-mvn.ps1') }
  $r = Prueba $e @('-Reparar') 'reparar-arregla'
  Igual 'sale con 2' 2 $r.Codigo
  $rep = @(Reparaciones $e)
  Igual 'no arreglado' 'no arreglado' $rep[0].resultado
  Comprueba 'el motivo es el de los tests: arregla el caso pero rompe el test' ($rep[0].motivo -match 'arregla el caso, pero rompe estos tests' -and $rep[0].motivo -match 'com\.acme\.nuevo\.ReglaTest') $rep[0].motivo
  Igual 'dos llamadas: el intento y el reintento' 2 (Llamadas-Reparar $e).Count
  Igual 'el caso de la tarea se ejecuta en el migrado al empezar y en cada intento' 3 (Ejecuciones-Mig $e 'caso-01')
  Igual 'el otro caso, solo al empezar: tras un arreglo que rompe un test ya no se ejecuta' 1 (Ejecuciones-Mig $e 'caso-02')
}

$Pruebas['m31 (d) -Reparar: un arreglo bueno pasa los tres pasos en el orden nuevo: el caso de la tarea, los tests unitarios y los demas casos'] = {
  $e = Escenario-M25 'm31-d' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') }) -Sano -Ajustes @{ MvnExe = (Join-Path $falsos 'm31-mvn.ps1') }
  $r = Prueba $e @('-Reparar') 'reparar-arregla'
  Igual 'sale con 0 (todo igual al final)' 0 $r.Codigo
  Igual 'reparaciones: arreglado, con un intento' 'arreglado 1' ((@(Reparaciones $e)[0]).resultado + ' ' + (@(Reparaciones $e)[0]).intentos)
  $l = @(Mavens-Con $e ('^' + [regex]::Escape($e.CopiaMig + '|')))
  $uno = Ultimo-Indice $l '-Dprueba\.local\.caso=caso-01( |$)'
  $suite = Ultimo-Indice $l 'surefire\.excludesFile'
  $dos = Ultimo-Indice $l '-Dprueba\.local\.caso=caso-02( |$)'
  Comprueba 'los tres pasos se ejecutan' ($uno -ge 0 -and $suite -ge 0 -and $dos -ge 0) "caso-01 en $uno, suite en $suite, caso-02 en $dos"
  Comprueba 'primero el caso de la tarea, despues la suite y al final los demas casos' ($uno -lt $suite -and $suite -lt $dos) "caso-01 en $uno, suite en $suite, caso-02 en $dos"
}

$Pruebas['m31 (e) plantilla del arnes: las tablas son las que no son de Spring Batch ni de Spring Cloud Task'] = {
  $arnes = [System.IO.File]::ReadAllText((Join-Path (Join-Path (Split-Path -Parent $Script) 'tareas') 'arnes-local.md'), [System.Text.Encoding]::UTF8)
  Comprueba 'tablas/<TABLA>.csv: una por cada tabla que no es de Spring Batch ni de Spring Cloud Task (BATCH_..., TASK_...)' ($arnes.Contains('uno por cada tabla que no es de Spring Batch ni de Spring Cloud Task (`BATCH_...`, `TASK_...`), con el nombre')) ''
}

# ===================== M32: medir y acortar el Maven de cada caso =====================
# m32-mvn.ps1 deja el XML de surefire de cada caso con un time fijo (0.2 por el numero del caso) y, segun RESCATE_M32, un Maven que sin
# red no llega a ejecutar el test, un job que falla o un XML que no se renueva. mvn.log (RESCATE_LLAMADAS) apunta cada llamada.

function Escenario-M32([string]$Nombre, $Casos, [hashtable]$Ajustes = @{}, [string]$Mvn = 'm32-mvn.ps1') {
  $e = Nuevo-Escenario $Nombre $Casos
  $aj = [ordered]@{ CopilotExe = (Join-Path $falsos 'copilot-local.ps1'); MvnExe = (Join-Path $falsos $Mvn); SegundosPorLlamada = 60 }
  foreach ($k in $Ajustes.Keys) { $aj[$k] = $Ajustes[$k] }
  Escribe $e.Home 'ajustes.json' (ConvertTo-Json -InputObject $aj)
  return $e
}

function Prueba-M32($E, [string]$Guion) {
  $env:RESCATE_M32 = $Guion
  try { return (Prueba $E) }
  finally { $env:RESCATE_M32 = '' }
}

# Las llamadas a Maven de los casos (-Dprueba.local.caso=caso-<n>) hechas en la copia $Copia, en orden.
function Casos-Mvn($E, [string]$Copia) { return @(Mavens-Con $E ('^' + [regex]::Escape($Copia + '|') + '.* -Dprueba\.local\.caso=caso-')) }

function Con-O([string]$Linea) { return ($Linea -match ' -o( |$)') }

function Caso-De([string]$Linea) { return [regex]::Match($Linea, '-Dprueba\.local\.caso=(caso-\d+)').Groups[1].Value }

# Las filas de datos\prueba-local-tiempos.json (de todos los lanzamientos, en orden).
function Tiempos($E) { return @(Lee-Json (Join-Path (Split-Path $E.Json -Parent) 'prueba-local-tiempos.json') | Where-Object { $_ }) }

# segundosTest de cada fila, separados por comas ('null' si no lo hay).
function Tests-De($Filas) { return ((@($Filas) | ForEach-Object { if ($null -eq $_.segundosTest) { 'null' } else { "$($_.segundosTest)" } }) -join ',') }

$Pruebas['m32 (a) los casos llevan -o y las propiedades de MavenCasoRapido; el test-compile del principio y el arnes no; con la lista vaciada en ajustes solo va -o'] = {
  $e = Escenario-M32 'm32-a' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba $e
  Igual 'sale con 0' 0 $r.Codigo
  $propiedades = @('-Dcheckstyle.skip', '-Denforcer.skip', '-Dspotbugs.skip', '-Dpmd.skip', '-Dmaven.javadoc.skip', '-Dmaven.source.skip', '-Dmaven.gitcommitid.skip', '-Dlicense.skip')
  foreach ($copia in @($e.CopiaOrig, $e.CopiaMig)) {
    $c = @(Casos-Mvn $e $copia)
    Comprueba "hay llamadas de casos en $(Split-Path $copia -Leaf)" ($c.Count -ge 2) "$($c.Count)"
    Comprueba '  todas llevan -o' (@($c | Where-Object { -not (Con-O $_) }).Count -eq 0) ($c -join ' / ')
    foreach ($p in $propiedades) { Comprueba "  y $p" (@($c | Where-Object { $_ -notmatch (' ' + [regex]::Escape($p) + '( |$)') }).Count -eq 0) ($c -join ' / ') }
  }
  $otras = @(Mavens-Con $e '.' | Where-Object { $_ -notmatch ' -Dprueba\.local\.caso=caso-' })
  Comprueba 'el test-compile del principio de cada copia esta entre las demas llamadas' (@($otras | Where-Object { $_ -match ' test-compile( |$)' }).Count -ge 2) ($otras -join ' / ')
  Comprueba 'el arnes (caso vacio) tambien' (@($otras | Where-Object { $_ -match '-Dprueba\.local\.caso=vacio' }).Count -ge 1) ($otras -join ' / ')
  Comprueba 'ninguna de las demas lleva -o ni propiedades de plugins' (@($otras | Where-Object { (Con-O $_) -or $_ -match '\.skip( |$)' }).Count -eq 0) ($otras -join ' / ')
  $e2 = Escenario-M32 'm32-a2' ([ordered]@{ cargaJob = @('importe=10.00') }) @{ MavenCasoRapido = @() }
  $r = Prueba $e2
  Igual 'con MavenCasoRapido vacio sale con 0' 0 $r.Codigo
  $c = @(Casos-Mvn $e2 $e2.CopiaMig)
  Comprueba 'sigue con -o' ($c.Count -ge 1 -and @($c | Where-Object { -not (Con-O $_) }).Count -eq 0) ($c -join ' / ')
  Comprueba 'pero sin ninguna propiedad de plugin' (@(Mavens-Con $e2 '\.skip( |$)').Count -eq 0) ((Mavens-Con $e2 '\.skip( |$)') -join ' / ')
}

$Pruebas['m32 (b) un caso en -o que no llega a ejecutar el test se repite con red y lo dice; esa copia sigue con red y la otra con -o'] = {
  $e = Escenario-M32 'm32-b' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00', 'importe=30.00') })
  $r = Prueba-M32 $e 'sin-red-original'
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'los tres casos salen iguales' 'igual,igual,igual' ((Resultados $e) -join ',')
  Igual 'la Info sale una sola vez' 1 (@([regex]::Matches($r.Salida, [regex]::Escape('Sin red Maven no ha podido: repito el caso con red y sigo con red en esta copia.'))).Count)
  $o = @(Casos-Mvn $e $e.CopiaOrig)
  Comprueba 'la primera llamada del original lleva -o' (Con-O $o[0]) $o[0]
  Igual 'la segunda es del mismo caso' (Caso-De $o[0]) (Caso-De $o[1])
  Comprueba 'y va sin -o' (-not (Con-O $o[1])) $o[1]
  Comprueba 'el resto del original, sin -o' (@($o | Select-Object -Skip 1 | Where-Object { Con-O $_ }).Count -eq 0) ($o -join ' / ')
  $m = @(Casos-Mvn $e $e.CopiaMig)
  Igual 'el migrado ejecuta sus tres casos una vez' 3 $m.Count
  Comprueba 'todos con -o' (@($m | Where-Object { -not (Con-O $_) }).Count -eq 0) ($m -join ' / ')
  $f = @(Tiempos $e | Where-Object { $_.lado -eq 'original' -and $_.caso -eq (Caso-De $o[0]) })
  Igual 'filas del primer caso del original: la del -o y la repetida' 'True,False' ((@($f | Select-Object -First 2) | ForEach-Object { $_.offline }) -join ',')
  Igual 'la del -o no llego al test: sin segundosTest; la repetida si' 'null,0.2' (Tests-De ($f | Select-Object -First 2))
}

$Pruebas['m32 (b2) si la repeticion con red tambien falla es el fallo de siempre: no lo dice como bueno y la copia vuelve a probar con -o en el caso siguiente'] = {
  $e = Escenario-M32 'm32-b2' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba-M32 $e 'migrado-roto'
  Igual 'la Info sale una sola vez' 1 (@([regex]::Matches($r.Salida, [regex]::Escape('Sin red Maven no ha podido'))).Count)
  $m = @(Casos-Mvn $e $e.CopiaMig)
  Igual 'caso-01 dos veces (con -o y sin el) y caso-02 una' 'caso-01 True,caso-01 False,caso-02 True' ((@($m | ForEach-Object { (Caso-De $_) + ' ' + (Con-O $_) })) -join ',')
  Comprueba 'el original no se entera: sus casos van con -o' (@(Casos-Mvn $e $e.CopiaOrig | Where-Object { -not (Con-O $_) }).Count -eq 0) ((Casos-Mvn $e $e.CopiaOrig) -join ' / ')
}

$Pruebas['m32 (b3) un caso sin estado.txt ni error.txt cuya salida no habla de la red (el contexto de Spring no arranca) no se repite: sin Info y la copia sigue con -o'] = {
  $e = Escenario-M32 'm32-b3' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba-M32 $e 'contexto-roto'
  Comprueba 'no sale la Info de repetir con red' ($r.Salida -notmatch 'Sin red Maven no ha podido') (Cola $r.Salida)
  $m = @(Casos-Mvn $e $e.CopiaMig)
  Igual 'el migrado ejecuta caso-01 (que no llega al test) una sola vez y caso-02 una, las dos con -o' 'caso-01 True,caso-02 True' ((@($m | ForEach-Object { (Caso-De $_) + ' ' + (Con-O $_) })) -join ',')
  Comprueba 'el caso roto no dejo estado.txt ni error.txt' (-not (Test-Path -LiteralPath (Get-Ruta $e.CopiaMig 'target/prueba-local/cargaJob/caso-01/estado.txt')) -and -not (Test-Path -LiteralPath (Get-Ruta $e.CopiaMig 'target/prueba-local/cargaJob/caso-01/error.txt'))) ''
  Igual 'una sola fila de caso-01 en el migrado, con -o' 'True' ((@(Tiempos $e | Where-Object { $_.lado -eq 'migrado' -and $_.caso -eq 'caso-01' }) | ForEach-Object { $_.offline }) -join ',')
}

# El registro de Maven (registros\mvn-<n>-<que>.log) de los casos del migrado de $Caso, en orden: lo que dijo cada llamada.
function Registros-Mvn-Migrado($E, [string]$Caso) {
  return @(Get-ChildItem -LiteralPath (Get-Ruta $E.Local 'registros') -File -Filter "mvn-*-migrado-cargaJob-$Caso.log" | Sort-Object { [int]($_.Name -replace '^mvn-(\d+)-.*$', '$1') })
}

$Pruebas['m32 (b4) un caso que ya dejo estado.txt, o solo error.txt, no se repite aunque la salida de Maven diga offline'] = {
  $e = Escenario-M32 'm32-b4' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba-M32 $e 'ejecutado-y-offline'
  foreach ($c in @('caso-01', 'caso-02')) {
    $reg = @(Registros-Mvn-Migrado $e $c)
    Igual "$c del migrado: una sola llamada de Maven" 1 $reg.Count
    Comprueba "  y su salida dice offline (el guion se cumplio)" ($reg.Count -gt 0 -and [System.IO.File]::ReadAllText($reg[0].FullName) -match 'offline') ''
  }
  Comprueba 'caso-01 dejo estado.txt y caso-02 solo error.txt' ((Test-Path -LiteralPath (Get-Ruta $e.CopiaMig 'target/prueba-local/cargaJob/caso-01/estado.txt')) -and -not (Test-Path -LiteralPath (Get-Ruta $e.CopiaMig 'target/prueba-local/cargaJob/caso-02/estado.txt')) -and (Test-Path -LiteralPath (Get-Ruta $e.CopiaMig 'target/prueba-local/cargaJob/caso-02/error.txt'))) ''
  Comprueba 'no sale la Info de repetir con red' ($r.Salida -notmatch 'Sin red Maven no ha podido') (Cola $r.Salida)
  $m = @(Casos-Mvn $e $e.CopiaMig)
  Igual 'el migrado ejecuta cada caso una vez y con -o' 'caso-01 True,caso-02 True' ((@($m | ForEach-Object { (Caso-De $_) + ' ' + (Con-O $_) })) -join ',')
}

$Pruebas['m32 (b5) un caso que Maven para por el tope no se repite aunque su salida diga offline'] = {
  $e = Escenario-M32 'm32-b5' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') }) @{ MinutosMaven = 0.1 }
  $r = Prueba-M32 $e 'tope-offline'
  Comprueba 'Maven se paso del tope en caso-01 del migrado' ($r.Salida -match 'Maven se ha pasado del tope de 0\.1 min y se ha parado \(Maven, migrado cargaJob caso-01\)') (Cola $r.Salida)
  $reg = @(Registros-Mvn-Migrado $e 'caso-01')
  Comprueba 'su registro lleva lo que Maven dijo antes de colgarse: offline' ($reg.Count -gt 0 -and [System.IO.File]::ReadAllText($reg[0].FullName) -match 'offline') ''
  Igual 'caso-01 del migrado: una sola llamada de Maven' 1 $reg.Count
  Comprueba 'no sale la Info de repetir con red' ($r.Salida -notmatch 'Sin red Maven no ha podido') (Cola $r.Salida)
  $m = @(Casos-Mvn $e $e.CopiaMig)
  Igual 'el migrado ejecuta cada caso una vez y con -o' 'caso-01 True,caso-02 True' ((@($m | ForEach-Object { (Caso-De $_) + ' ' + (Con-O $_) })) -join ',')
}

$Pruebas['m32 (b6) al repetir con red se borra antes lo que dejo el intento sin red: un fichero suelto de ese intento no queda en la salida del caso'] = {
  $e = Escenario-M32 'm32-b6' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba-M32 $e 'sin-red-parcial'
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'los dos casos salen iguales' 'igual,igual' ((Resultados $e) -join ',')
  Igual 'la Info sale una vez' 1 (@([regex]::Matches($r.Salida, [regex]::Escape('Sin red Maven no ha podido'))).Count)
  $m = @(Casos-Mvn $e $e.CopiaMig)
  Igual 'caso-01 con -o y repetido sin -o; caso-02 ya sin -o' 'caso-01 True,caso-01 False,caso-02 False' ((@($m | ForEach-Object { (Caso-De $_) + ' ' + (Con-O $_) })) -join ',')
  Comprueba 'ficheros/parcial.txt no esta en la salida del caso de la copia' (-not (Test-Path -LiteralPath (Get-Ruta $e.CopiaMig 'target/prueba-local/cargaJob/caso-01/ficheros/parcial.txt'))) ''
  Comprueba 'ni en la que guarda la prueba (salidas\migrado)' (-not (Test-Path -LiteralPath (Get-Ruta $e.Local 'salidas/migrado/cargaJob/caso-01/ficheros/parcial.txt'))) ''
}

$Pruebas['m32 (c) un caso que deja estado.txt (aunque sea FAILED) o error.txt no se repite, ni con -o'] = {
  $e = Escenario-M32 'm32-c' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00', 'importe=30.00') })
  $r = Prueba-M32 $e 'falla-migrado'
  Comprueba 'el job falla en el migrado y la prueba lo cuenta (no sale con 0)' ($r.Codigo -ne 0) "rc=$($r.Codigo)"
  Comprueba 'no sale la Info de repetir con red' ($r.Salida -notmatch 'Sin red Maven no ha podido') (Cola $r.Salida)
  $m = @(Casos-Mvn $e $e.CopiaMig)
  Igual 'el migrado ejecuta cada caso una sola vez (caso-01 FAILED, caso-02 con error.txt, caso-03 bien)' 'caso-01,caso-02,caso-03' ((@($m | ForEach-Object { Caso-De $_ })) -join ',')
  Comprueba 'todas con -o' (@($m | Where-Object { -not (Con-O $_) }).Count -eq 0) ($m -join ' / ')
  Comprueba 'los casos quedaron como los dejo el job' ((Test-Path -LiteralPath (Get-Ruta $e.CopiaMig 'target/prueba-local/cargaJob/caso-02/error.txt')) -and (Lee $e.CopiaMig 'target/prueba-local/cargaJob/caso-01/estado.txt') -match 'FAILED') ''
}

$Pruebas['m32 (d) prueba-local-tiempos.json: una fila por ejecucion de un caso, con segundosTest igual al time del XML, y la consola da la media; un segundo lanzamiento anade'] = {
  $e = Escenario-M32 'm32-d' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba $e
  Igual 'sale con 0' 0 $r.Codigo
  $t = @(Tiempos $e)
  $llamadas = @(Casos-Mvn $e $e.CopiaOrig).Count + @(Casos-Mvn $e $e.CopiaMig).Count
  Igual 'una fila por llamada de caso a Maven' $llamadas $t.Count
  Igual 'original: 6 (los casos de la IA, el original y el original-2) y migrado: 2' '6,2' ((@(@($t | Where-Object { $_.lado -eq 'original' }).Count, @($t | Where-Object { $_.lado -eq 'migrado' }).Count)) -join ',')
  Comprueba 'cada fila: job, caso, segundosMaven, offline y cuando' ($t.Count -gt 0 -and @($t | Where-Object { $_.job -ne 'cargaJob' -or $_.caso -notmatch '^caso-0[12]$' -or $null -eq $_.segundosMaven -or $_.offline -ne $true -or -not $_.cuando }).Count -eq 0) (($t | ForEach-Object { ConvertTo-Json -InputObject $_ -Compress }) -join ' / ')
  $uno = @(@($t | Where-Object { $_.caso -eq 'caso-01' }) | ForEach-Object { "$($_.segundosTest)" } | Select-Object -Unique)
  $dos = @(@($t | Where-Object { $_.caso -eq 'caso-02' }) | ForEach-Object { "$($_.segundosTest)" } | Select-Object -Unique)
  Igual 'segundosTest: siempre 0.2 en las filas de caso-01 y siempre 0.4 en las de caso-02' '0.2|0.4' (($uno -join ',') + '|' + ($dos -join ','))
  $xml = New-Object System.Xml.XmlDocument
  $xml.Load((Get-Ruta $e.CopiaMig 'target/surefire-reports/TEST-com.acme.nuevo.PruebaLocalTest.xml'))
  $ultimo = @($t | Where-Object { $_.lado -eq 'migrado' })[-1]
  Igual 'la ultima fila del migrado lleva el time del XML que dejo Maven' $xml.DocumentElement.GetAttribute('time') "$($ultimo.segundosTest)"
  Comprueba 'la consola da la media: el test 0.3 s (la de 0.2 y 0.4)' ($r.Salida -match 'Maven por caso: [\d\.]+ s de media; el test 0\.3 s y Maven [\d\.]+ s \(arranque, plugins y red\)\. Detalle: .*prueba-local-tiempos\.json') (Cola $r.Salida)
  $f = @($t | Where-Object { $null -ne $_.segundosTest })
  $mediaMaven = ($f | Measure-Object -Property segundosMaven -Average).Average
  $resta = [Math]::Round($mediaMaven - ($f | Measure-Object -Property segundosTest -Average).Average, 1)
  Comprueba 'la media de los segundos de Maven y la de Maven menos test se distinguen (el test dura 0.3 s)' ([Math]::Round($mediaMaven, 1) -ne $resta) "$mediaMaven $resta"
  Comprueba "y la linea da Maven menos test: y Maven $resta s (no los segundos de Maven)" ($r.Salida.Contains("y Maven $resta s (arranque")) (Cola $r.Salida)
  $antes = $t.Count
  $r = Prueba $e
  $t2 = @(Tiempos $e)
  Igual 'el segundo lanzamiento anade las suyas (solo las del migrado: el original no ha cambiado y se reutiliza) sin pisar las de antes' ($antes + 2) $t2.Count
  Igual 'las primeras siguen como estaban' (($t | ForEach-Object { "$($_.lado)|$($_.caso)|$($_.cuando)" }) -join ',') ((@($t2 | Select-Object -First $antes) | ForEach-Object { "$($_.lado)|$($_.caso)|$($_.cuando)" }) -join ',')
  Comprueba 'la media de la consola es la de este lanzamiento' ($r.Salida -match 'Maven por caso: [\d\.]+ s de media; el test 0\.3 s') (Cola $r.Salida)
}

$Pruebas['m32 (e) un XML de surefire anterior a ese Maven no cuenta (segundosTest null) y la media no lo incluye; sin ningun XML la linea no sale'] = {
  $e = Escenario-M32 'm32-e' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M32 $e 'xml-viejo'
  Igual 'sale con 0' 0 $r.Codigo
  $t = @(Tiempos $e)
  Igual 'original: el primer Maven escribe el XML; el original y el original-2 dejan el de antes: null' '0.2,null,null' (Tests-De ($t | Where-Object { $_.lado -eq 'original' }))
  Igual 'migrado: su primer Maven escribe el suyo' '0.2' (Tests-De ($t | Where-Object { $_.lado -eq 'migrado' }))
  Comprueba 'la media del test es 0.2: las filas null no cuentan como 0' ($r.Salida -match 'Maven por caso: [\d\.]+ s de media; el test 0\.2 s y Maven') (Cola $r.Salida)
  $e2 = Escenario-M32 'm32-e2' ([ordered]@{ cargaJob = @('importe=10.00') }) @{} 'mvn-local.ps1'
  $r = Prueba $e2
  Igual 'sin ningun XML, sale con 0' 0 $r.Codigo
  $t = @(Tiempos $e2)
  Comprueba 'hay filas, todas con segundosTest null' ($t.Count -ge 3 -and (Tests-De $t) -notmatch '[0-9]') (Tests-De $t)
  Comprueba 'y la linea de Maven por caso no sale' ($r.Salida -notmatch 'Maven por caso') (Cola $r.Salida)
}

$Pruebas['m32 (f) un prueba-local-tiempos.json de antes que no se puede leer no para la prueba: sale con 0, avisa y no lo pisa'] = {
  $e = Escenario-M32 'm32-f' ([ordered]@{ cargaJob = @('importe=10.00') })
  $datos = Split-Path $e.Json -Parent
  Escribe $datos 'prueba-local-tiempos.json' "esto no es json {`n"
  $r = Prueba $e
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'el caso sale igual' 'igual' ((Resultados $e) -join ',')
  Comprueba 'avisa: No he podido guardar los tiempos' ($r.Salida -match 'No he podido guardar los tiempos') (Cola $r.Salida)
  Igual 'y el fichero de antes sigue como estaba' "esto no es json {`n" (Lee $datos 'prueba-local-tiempos.json')
}

# ===================== M36: una tabla vacia es una tabla que no esta, y un original que no arranca no prueba nada =====================
# m36-mvn.ps1 deja, segun el guion de RESCATE_M36 ('guion:regex sobre job/caso', separados por ';'), tablas vacias o con filas en un solo
# lado y un original que no arranca (estado=EXCEPCION) o que acaba mal (estado=FAILED).

# Un escenario normal con el Maven de mentira de m36.
function Escenario-M36([string]$Nombre, $Casos) {
  $e = Nuevo-Escenario $Nombre $Casos
  $aj = [ordered]@{ CopilotExe = (Join-Path $falsos 'copilot-local.ps1'); MvnExe = (Join-Path $falsos 'm36-mvn.ps1'); SegundosPorLlamada = 60 }
  Escribe $e.Home 'ajustes.json' (ConvertTo-Json -InputObject $aj)
  return $e
}

# Lanza -Si con los guiones $Guion de m36-mvn.ps1 y devuelve lo de Prueba.
function Prueba-M36($E, [string]$Guion, [string[]]$A = @(), [string]$GuionCopilot = '') {
  $env:RESCATE_M36 = $Guion
  try { return (Prueba $E $A $GuionCopilot) }
  finally { $env:RESCATE_M36 = '' }
}

function Llamadas-Casos($E) { return @(Llamadas $E | Where-Object { $_.tipo -eq 'caso-local' }) }

# La tarea del caso $Caso (de dos digitos) del job $Job.
function Tarea-Caso-M36($E, [string]$Job, [string]$Caso) { return (Lee-Json (Get-Ruta $E.Local "tareas/caso-$Job-$Caso.json")) }

# El prompt y la respuesta de la llamada $N de la tarea del caso $Caso del job $Job.
function Registro-Caso-M36($E, [string]$Job, [string]$Caso, [int]$N) {
  $f = Get-Ruta $E.Local "registros/caso-$Job-$Caso-$N.log"
  if (-not (Test-Path -LiteralPath $f)) { return '' }
  return [System.IO.File]::ReadAllText($f)
}

$Pruebas['m36 (a, b) tablas: una tabla vacia (sin filas, con la cabecera sola o con lineas en blanco) en un solo lado sale igual que una que no esta; con una fila, distinta'] = {
  $e = Escenario-M36 'm36-a' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=10.00', 'importe=10.00', 'importe=10.00', 'importe=10.00') })
  $r = Prueba-M36 $e 'tabla-cabecera:/caso-01;tabla-fila:/caso-02;tabla-cabecera-mig:/caso-03;tabla-fila-mig:/caso-04;tabla-blancos:/caso-05'
  Igual 'sale con 2 (hay distintos)' 2 $r.Codigo
  Igual 'iguales los de tabla vacia, distintos los de una fila' 'igual,distinto,igual,distinto,igual' ((Resultados $e) -join ',')
  Comprueba 'las tablas estan en las salidas (es la comparacion la que las deja pasar)' ((Test-Path -LiteralPath (Get-Ruta $e.Local 'salidas/original/cargaJob/caso-01/tablas/T.csv')) -and (Test-Path -LiteralPath (Get-Ruta $e.Local 'salidas/migrado/cargaJob/caso-03/tablas/T.csv'))) ''
  $d = @((Caso $e 'cargaJob' 'caso-02').diferencias)
  Igual 'con una fila solo en el original: esa tabla y solo ella' 'tablas/T.csv' ($d | ForEach-Object { $_.fichero })
  Igual 'la cabecera del original frente a (no esta)' 'ID;NOMBRE|(no esta)' "$($d[0].original)|$($d[0].migrado)"
  $d = @((Caso $e 'cargaJob' 'caso-04').diferencias)
  Igual 'con una fila solo en el migrado: esa tabla y solo ella' 'tablas/T.csv' ($d | ForEach-Object { $_.fichero })
  Igual 'y (no esta) frente a la cabecera del migrado' '(no esta)|ID;NOMBRE' "$($d[0].original)|$($d[0].migrado)"
}

$Pruebas['m36 (a2) Compare-Caso: la tabla vacia de un solo lado no cuenta; con una fila, con las dos del mismo lado o fuera de tablas/ si cuenta'] = {
  $f = Join-Path $Dir 'm36-comparar.ps1'
  $raizCmp = Join-Path $Dir 'm36-comparar'
  $cuerpo = @'
$Inv = [System.Globalization.CultureInfo]::InvariantCulture
$Utf8Estricto = New-Object System.Text.UTF8Encoding($false, $true)
$RutasCopia = @()
$Hoy = @()
function Caso([string]$Id, [hashtable]$A, [hashtable]$B) {
  $dirs = @{}
  foreach ($x in @(@('A', $A), @('B', $B))) {
    $d = Join-Path (Join-Path $Raiz $Id) $x[0]
    [void](New-Item -ItemType Directory -Path $d -Force)
    foreach ($k in $x[1].Keys) {
      $p = Join-Path $d $k
      [void](New-Item -ItemType Directory -Path (Split-Path $p -Parent) -Force)
      [System.IO.File]::WriteAllText($p, $x[1][$k])
    }
    $dirs[$x[0]] = $d
  }
  'R ' + $Id + ' ' + (@(Compare-Caso $dirs.A $dirs.B | ForEach-Object { $_.fichero }) -join ',')
}
$t = 'tablas/T.csv'
Caso 'cabecera' @{ $t = "ID;NOMBRE`n" } @{}
Caso 'cabecera-mig' @{} @{ $t = "ID;NOMBRE`r`n" }
Caso 'vacio-0' @{ $t = '' } @{}
Caso 'blancos' @{ $t = "ID;NOMBRE`n`n   `n`n" } @{}
Caso 'fila' @{ $t = "ID;NOMBRE`n1;ana`n" } @{}
Caso 'fila-tras-blancos' @{} @{ $t = "ID;NOMBRE`n`n1;ana`n" }
Caso 'dos-lados' @{ $t = "ID;NOMBRE`n" } @{ $t = "ID;NOMBRE`n1;ana`n" }
Caso 'dos-lados-iguales' @{ $t = "ID;NOMBRE`n" } @{ $t = "ID;NOMBRE`n" }
Caso 'dos-cabeceras' @{ $t = "ID;NOMBRE`n" } @{ $t = "NOMBRE;ID`n" }
Caso 'fuera-de-tablas' @{ 'ficheros/salida/x.csv' = "ID;NOMBRE`n" } @{}
Caso 'tablas-no-csv' @{ 'tablas/nota.txt' = "ID;NOMBRE`n" } @{}
Caso 'vacia-y-otra' @{ $t = "ID;NOMBRE`n"; 'tablas/U.csv' = "ID;NOMBRE`n1;ana`n" } @{}
'@
  [System.IO.File]::WriteAllText($f, ('param([string]$Raiz)' + "`n" + (Texto-De-Funciones $Script (@('Compare-Caso', 'Compare-Fichero') + $FnLeer + @('Sort-Tabla', 'Resolve-ParTablas', 'Sort-Ordinal', 'Get-Normal', 'Get-Legible', 'Get-NotaJdk'))) + "`n" + (Texto-De-Funciones (Join-Path (Split-Path -Parent $Script) 'comun.ps1') @('Get-Rel')) + "`n" + '$Latin = [System.Text.Encoding]::GetEncoding(28591); $Utf8 = New-Object System.Text.UTF8Encoding($false)' + "`n" + $cuerpo))
  $r = Lanzar $f @($raizCmp)
  $v = @{}
  foreach ($l in @($r.Salida -split "`n")) { if ($l -cmatch '^R (\S+) ?(.*)$') { $v[$Matches[1]] = $Matches[2].TrimEnd() } }
  Igual 'la cabecera sola en el original y nada en el migrado: sin diferencias' '' $v['cabecera']
  Igual 'al reves, con saltos de linea de Windows: sin diferencias' '' $v['cabecera-mig']
  Igual 'un fichero de 0 bytes: sin diferencias' '' $v['vacio-0']
  Igual 'la cabecera y lineas en blanco: sin diferencias' '' $v['blancos']
  Igual 'con una fila: distinta' 'tablas/T.csv' $v['fila']
  Igual 'con una fila tras lineas en blanco, en el migrado: distinta' 'tablas/T.csv' $v['fila-tras-blancos']
  Igual 'en los dos lados, la cabecera frente a la cabecera y una fila: distinta, como siempre' 'tablas/T.csv' $v['dos-lados']
  Igual 'en los dos lados y la misma cabecera: igual' '' $v['dos-lados-iguales']
  Igual 'en los dos lados con otra cabecera: se ordenan las columnas y sale igual, como siempre' '' $v['dos-cabeceras']
  Igual 'un .csv fuera de tablas/ con la cabecera sola en un lado: distinto' 'ficheros/salida/x.csv' $v['fuera-de-tablas']
  Igual 'un fichero de tablas/ que no es .csv: distinto' 'tablas/nota.txt' $v['tablas-no-csv']
  Igual 'una tabla vacia no tapa a otra con filas del mismo caso' 'tablas/U.csv' $v['vacia-y-otra']
}

$Pruebas['m36 (c, f) un caso cuyo original no arranca (estado=EXCEPCION): se rechaza con el motivo una vez y en el reintento se acepta; con FAILED, no cambia'] = {
  $e = Escenario-M36 'm36-c' ([ordered]@{ cargaJob = @('importe=10.00'); remesaJob = @('importe=10.00'); tarifaJob = @('importe=10.00') })
  $r = Prueba-M36 $e 'excepcion:^cargaJob/;excepcion-sin-error:^remesaJob/;failed:^tarifaJob/'
  Igual 'sale con 2 (los tres salen distintos del migrado)' 2 $r.Codigo
  $ll = @(Llamadas-Casos $e)
  Igual 'dos llamadas por cada job con EXCEPCION y una por el de FAILED' 5 $ll.Count
  Igual 'cargaJob: dos llamadas' 2 @($ll | Where-Object { $_.id -like 'caso-cargaJob-*' }).Count
  Igual 'remesaJob: dos llamadas' 2 @($ll | Where-Object { $_.id -like 'caso-remesaJob-*' }).Count
  Igual 'tarifaJob (FAILED): una llamada, como hoy' 1 @($ll | Where-Object { $_.id -like 'caso-tarifaJob-*' }).Count
  Comprueba 'la consola dice que el caso se rechaza porque el job no arranca' ($r.Salida -match 'caso-cargaJob-01 rechazado: En el original el job no llega a arrancar') (Cola $r.Salida)
  Comprueba 'y no rechaza el de FAILED' ($r.Salida -notmatch 'caso-tarifaJob-01 rechazado') (Cola $r.Salida)
  $p = Registro-Caso-M36 $e 'cargaJob' '01' 2
  Comprueba 'el reintento recibe el motivo con la salida y la primera linea de la causa' ($p.Contains("En el original el job no llega a arrancar: lanzarlo da IllegalStateException (error.txt: Could not resolve placeholder 'acme.entrada.ruta'). Si el caso no busca justo eso, corrige las entradas (parametros, datos.sql...) para que el job arranque y haga lo que dice el titulo.")) (Cola $p)
  Comprueba 'sin la segunda linea de la causa' (-not $p.Contains('at com.acme.viejo.Lector.lee')) ''
  $p = Registro-Caso-M36 $e 'remesaJob' '01' 2
  Comprueba 'sin error.txt, el motivo dice la salida y no la causa' ($p.Contains('lanzarlo da IllegalStateException. Si el caso no busca justo eso') -and -not $p.Contains('error.txt:')) (Cola $p)
  $t = Tarea-Caso-M36 $e 'cargaJob' '01'
  Igual 'cargaJob: la tarea queda hecha tras el reintento' 'hecha' $t.estado
  Igual 'con dos intentos' 2 $t.intentos
  Igual 'apuntado en la tarea que ya se pidio' $true $t.entradas.excepcionPedida
  Igual 'el original sigue dando EXCEPCION y el caso se prueba' 'distinto' (Caso $e 'cargaJob' 'caso-01').resultado
  Comprueba 'la salida guardada del original dice EXCEPCION' ((Lee $e.Local 'salidas/original/cargaJob/caso-01/estado.txt') -match 'estado=EXCEPCION') ''
  $t = Tarea-Caso-M36 $e 'tarifaJob' '01'
  Igual 'tarifaJob: hecha con un intento' 'hecha' $t.estado
  Igual 'sin pedir nada de EXCEPCION' 1 $t.intentos
  Comprueba 'y sin apuntarlo en la tarea' (-not $t.entradas.excepcionPedida) ''
}

$Pruebas['m36 (c2) un caso rechazado antes por otro motivo y que luego deja un original que no arranca: no queda atascado, se acepta en su ultimo intento'] = {
  $e = Escenario-M36 'm36-c2' ([ordered]@{ cargaJob = @('importe=10.00') })
  $aj = [ordered]@{ CopilotExe = (Join-Path $falsos 'm36-copilot.ps1'); MvnExe = (Join-Path $falsos 'm36-mvn.ps1'); SegundosPorLlamada = 60 }
  Escribe $e.Home 'ajustes.json' (ConvertTo-Json -InputObject $aj)
  $r = Prueba-M36 $e 'excepcion' @() 'primera-nada'
  Igual 'sale con 2 (el caso sale distinto del migrado)' 2 $r.Codigo
  Igual 'dos llamadas, sin una tercera para lo de EXCEPCION' 2 (Llamadas-Casos $e).Count
  Comprueba 'el primer rechazo es por no escribir nada' ($r.Salida -match 'caso-cargaJob-01 rechazado: No has escrito ningun fichero') (Cola $r.Salida)
  $t = Tarea-Caso-M36 $e 'cargaJob' '01'
  Igual 'la tarea queda hecha' 'hecha' $t.estado
  Igual 'con dos intentos' 2 $t.intentos
  Igual 'apuntado que ya se vio' $true $t.entradas.excepcionPedida
  Igual 'el caso se prueba' 'distinto' (Caso $e 'cargaJob' 'caso-01').resultado
}

$Pruebas['m36 (c3) con Intentos = 3, un caso nuevo cuyo original no arranca se rechaza en el primer intento y se acepta en el segundo: no hay una tercera llamada'] = {
  $e = Escenario-M36 'm36-c3' ([ordered]@{ cargaJob = @('importe=10.00') })
  $aj = [ordered]@{ CopilotExe = (Join-Path $falsos 'copilot-local.ps1'); MvnExe = (Join-Path $falsos 'm36-mvn.ps1'); SegundosPorLlamada = 60; Intentos = 3 }
  Escribe $e.Home 'ajustes.json' (ConvertTo-Json -InputObject $aj)
  $r = Prueba-M36 $e 'excepcion'
  Igual 'sale con 2 (el caso sale distinto del migrado)' 2 $r.Codigo
  Igual 'dos llamadas, no tres' 2 (Llamadas-Casos $e).Count
  Comprueba 'el primer intento se rechaza porque el job no arranca' ($r.Salida -match 'caso-cargaJob-01 rechazado: En el original el job no llega a arrancar') (Cola $r.Salida)
  Igual 'y solo se rechaza una vez' 1 @([regex]::Matches($r.Salida, 'caso-cargaJob-01 rechazado')).Count
  $t = Tarea-Caso-M36 $e 'cargaJob' '01'
  Igual 'la tarea queda hecha' 'hecha' $t.estado
  Igual 'con dos intentos' 2 $t.intentos
  Igual 'apuntado que ya se pidio' $true $t.entradas.excepcionPedida
}

$Pruebas['m36 (d) un caso hecho en otro lanzamiento con EXCEPCION guardada vuelve a pendiente una vez, con la Info; en el siguiente lanzamiento no se repite'] = {
  $e = Escenario-M36 'm36-d' ([ordered]@{ cargaJob = @('importe=10.00'); remesaJob = @('importe=10.00') })
  $r = Prueba-M36 $e ''
  Igual 'el primer lanzamiento sale con 0' 0 $r.Codigo
  Igual 'dos llamadas de casos' 2 (Llamadas-Casos $e).Count
  Comprueba 'sin nada que rehacer, ninguna Info de eso' ($r.Salida -notmatch 'Se rehacen') (Cola $r.Salida)
  # el original de cargaJob dejo EXCEPCION en aquel lanzamiento (remesaJob, no)
  Escribe $e.Local 'salidas/original/cargaJob/caso-01/estado.txt' "estado=EXCEPCION`nsalida=IllegalStateException`n"
  Escribe $e.Local 'salidas/original/cargaJob/caso-01/error.txt' "Could not resolve placeholder 'acme.entrada.ruta'`n"
  $r = Prueba-M36 $e 'excepcion:^cargaJob/'
  Comprueba 'la Info dice que se rehace 1 caso' ($r.Salida -match 'Se rehacen 1 caso') (Cola $r.Salida)
  Igual 'una llamada mas, solo la de ese caso' 3 (Llamadas-Casos $e).Count
  $p = Registro-Caso-M36 $e 'cargaJob' '01' 2
  Comprueba 'la IA recibe el motivo, con la causa guardada' ($p.Contains("En el original el job no llega a arrancar: lanzarlo da IllegalStateException (error.txt: Could not resolve placeholder 'acme.entrada.ruta')")) ''
  Comprueba 'remesaJob no se toca: sigue con su unico registro' (-not (Test-Path -LiteralPath (Get-Ruta $e.Local 'registros/caso-remesaJob-01-2.log'))) ''
  $t = Tarea-Caso-M36 $e 'cargaJob' '01'
  Igual 'la tarea queda hecha' 'hecha' $t.estado
  Igual 'apuntado que ya se pidio' $true $t.entradas.excepcionPedida
  Comprueba 'el original sigue sin arrancar y se acepta (la salida guardada ahora es la del segundo lanzamiento)' ((Lee $e.Local 'salidas/original/cargaJob/caso-01/estado.txt') -match 'estado=EXCEPCION') ''
  $r = Prueba-M36 $e 'excepcion:^cargaJob/'
  Comprueba 'el tercer lanzamiento no rehace nada' ($r.Salida -notmatch 'Se rehacen') (Cola $r.Salida)
  Igual 'ni llama a la IA' 3 (Llamadas-Casos $e).Count
}

$Pruebas['m36 (d2) sin salida guardada del original, un caso hecho no cambia'] = {
  $e = Escenario-M36 'm36-d2' ([ordered]@{ cargaJob = @('importe=10.00') })
  [void](Prueba-M36 $e '')
  Remove-Item -LiteralPath (Get-Ruta $e.Local 'salidas') -Recurse -Force
  $r = Prueba-M36 $e ''
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'sin llamadas nuevas' 1 (Llamadas-Casos $e).Count
  Comprueba 'ni Info de rehacer' ($r.Salida -notmatch 'Se rehacen') (Cola $r.Salida)
}

$Pruebas['m36 (e) -Reparar se salta el caso cuyo original da EXCEPCION y lo dice; el otro se arregla y el resultado del primero no cambia'] = {
  $e = Escenario-M25 'm36-e' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=5.00') }) -Sano -Ajustes @{ MvnExe = (Join-Path $falsos 'm36-mvn.ps1') }
  $r = Prueba-M36 $e 'excepcion:^cargaJob/caso-01$' @('-Reparar') 'reparar-arregla'
  Igual 'sale con 2 (el de EXCEPCION sigue distinto)' 2 $r.Codigo
  Comprueba 'la Info dice que salta 1 caso' ($r.Salida -match 'salto 1 caso') (Cola $r.Salida)
  Igual 'el caso con EXCEPCION sigue distinto y el otro queda igual' 'distinto,igual' ((Resultados $e) -join ',')
  Igual 'una sola llamada de reparar' 1 (Llamadas-Reparar $e).Count
  $rep = @(Reparaciones $e)
  Igual 'una reparacion, arreglada' 'arreglado' $rep[0].resultado
  Igual 'del caso que si arranca' 'caso-02' $rep[0].caso
  Igual 'y solo cuenta ese caso para la clave' 1 $rep[0].casos
}

$Pruebas['m36 (e2) -Reparar: si todos los distintos son de un original que no arranca, no llama a la IA ni mide los tests'] = {
  $e = Escenario-M25 'm36-e2' ([ordered]@{ cargaJob = @('importe=5.00') }) -Sano -Ajustes @{ MvnExe = (Join-Path $falsos 'm36-mvn.ps1') }
  $wt0 = GitEn $e.Wt @('rev-parse', 'HEAD')
  $r = Prueba-M36 $e 'excepcion' @('-Reparar') 'reparar-arregla'
  Igual 'sale con 2' 2 $r.Codigo
  Comprueba 'la Info dice que salta 1 caso' ($r.Salida -match 'salto 1 caso') (Cola $r.Salida)
  Igual 'ninguna llamada de reparar' 0 (Llamadas-Reparar $e).Count
  Igual 'el caso sigue distinto' 'distinto' ((Resultados $e) -join ',')
  Igual 'la rama de rescate no se mueve' $wt0 (GitEn $e.Wt @('rev-parse', 'HEAD'))
  Comprueba 'los tests unitarios de partida no se miden' ($r.Salida -notmatch 'Tests unitarios de partida') (Cola $r.Salida)
}

$Pruebas['m36 (e3) -Reparar: un caso igual cuyo original da EXCEPCION (y el migrado tambien) no se salta ni se cuenta: el distinto de al lado se repara'] = {
  $e = Escenario-M25 'm36-e3' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') }) -Sano -Ajustes @{ MvnExe = (Join-Path $falsos 'm36-mvn.ps1') }
  $r = Prueba-M36 $e 'excepcion-ambos:^cargaJob/caso-02$' @('-Reparar') 'reparar-arregla'
  Igual 'sale con 0 (el distinto se arregla y el otro era igual)' 0 $r.Codigo
  Igual 'los dos salen iguales al final' 'igual,igual' ((Resultados $e) -join ',')
  Igual 'una llamada de reparar' 1 (Llamadas-Reparar $e).Count
  $rep = @(Reparaciones $e)
  Igual 'arreglado, el caso que salia distinto' 'arreglado caso-01' "$($rep[0].resultado) $($rep[0].caso)"
  Comprueba 'la Info del salto no sale: no hay ningun distinto con EXCEPCION' ($r.Salida -notmatch 'Salto \d') (Cola $r.Salida)
}

$Pruebas['m36 (d3) con Intentos = 3, un caso hecho que se rehace por EXCEPCION se acepta en su reintento: no se le pide otra vez ni hay una llamada de mas'] = {
  $e = Escenario-M36 'm36-d3' ([ordered]@{ cargaJob = @('importe=10.00') })
  $aj = [ordered]@{ CopilotExe = (Join-Path $falsos 'copilot-local.ps1'); MvnExe = (Join-Path $falsos 'm36-mvn.ps1'); SegundosPorLlamada = 60; Intentos = 3 }
  Escribe $e.Home 'ajustes.json' (ConvertTo-Json -InputObject $aj)
  $r = Prueba-M36 $e ''
  Igual 'el primer lanzamiento sale con 0' 0 $r.Codigo
  Igual 'una llamada de caso' 1 (Llamadas-Casos $e).Count
  Escribe $e.Local 'salidas/original/cargaJob/caso-01/estado.txt' "estado=EXCEPCION`nsalida=IllegalStateException`n"
  $r = Prueba-M36 $e 'excepcion'
  Comprueba 'la Info dice que se rehace 1 caso' ($r.Salida -match 'Se rehacen 1 caso') (Cola $r.Salida)
  Igual 'una llamada mas y ninguna otra: el reintento se acepta' 2 (Llamadas-Casos $e).Count
  Comprueba 'sin rechazo en el reintento' ($r.Salida -notmatch 'caso-cargaJob-01 rechazado') (Cola $r.Salida)
  $t = Tarea-Caso-M36 $e 'cargaJob' '01'
  Igual 'la tarea queda hecha' 'hecha' $t.estado
  Igual 'con dos intentos (el de antes y el de ahora)' 2 $t.intentos
  Igual 'apuntado que ya se pidio' $true $t.entradas.excepcionPedida
}

$Pruebas['m36 (e4) -Reparar con MaxReparaciones = 1: el aviso de lo que queda sin probar no nombra las claves de un caso que se salta'] = {
  $e = Escenario-M25 'm36-e4' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=5.00', 'importe=10.00') }) -Sano -Ajustes @{ MvnExe = (Join-Path $falsos 'm36-mvn.ps1'); MaxReparaciones = 1 }
  $r = Prueba-M36 $e 'excepcion:^cargaJob/caso-02$;tabla-fila:^cargaJob/caso-03$' @('-Reparar') 'reparar-arregla'
  Comprueba 'salta 1 caso' ($r.Salida -match 'Salto 1 caso') (Cola $r.Salida)
  Igual 'una sola reparacion, la del caso 01' 'caso-01' (@(Reparaciones $e)[0]).caso
  Comprueba 'el aviso de tope dice que queda sin probar la tabla del caso 03 y solo esa' ($r.Salida -match 'quedan sin probar: tablas/T\.csv\. Vuelve a lanzar') (Cola $r.Salida)
  Comprueba 'sin nombrar el estado ni el error del caso que se salta' ($r.Salida -notmatch 'quedan sin probar:[^\r\n]*(estado|error)\.txt') (Cola $r.Salida)
}

# ===================== M37: el test del migrado escrito con una plantilla anterior se escribe otra vez =====================
# Estos escenarios usan los falsos de m29 (m29-copilot.ps1 y m29-mvn.ps1): el Copilot de mentira apunta en cada llamada de arnes si su
# prompt lleva el test del original (traduce=, original-existe=) y deja en el test la marca MARCA_ARNES=<repo>-<n>.
# La tarea del arnes guarda en entradas.plantilla el hash de la plantilla con que se escribio el test guardado; si la del migrado no la
# tiene o no es la de ahora, se escribe otra vez traduciendo el del original (como con -RehacerArnes). El del original no cambia.

$AvisoM37 = 'La plantilla del test ha cambiado desde que se escribio el del migrado: lo escribo otra vez traduciendo el del original.'

# El hash de la plantilla del arnes de ahora, como lo apunta la tarea: los 4 primeros bytes del SHA1 del texto, con saltos de linea LF.
function Plantilla-Ahora-M37 {
  $t = [System.IO.File]::ReadAllText((Join-Path (Join-Path (Split-Path -Parent $Script) 'tareas') 'arnes-local.md'), (New-Object System.Text.UTF8Encoding($false))) -replace "`r`n", "`n"
  $sha = [System.Security.Cryptography.SHA1]::Create()
  try { $b = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($t)) } finally { $sha.Dispose() }
  return ((@($b[0..3]) | ForEach-Object { $_.ToString('x2') }) -join '')
}

# Deja la tarea del arnes del $Repo como la dejaria un lanzamiento anterior: sin plantilla ($Plantilla = $null) o con la que se diga, y con
# otra huella si se da (la de una plantilla de antes: la tarea ya no es la de ahora y se hace una nueva).
function Deja-Tarea-M37($E, [string]$Repo, $Plantilla, [string]$Huella = '') {
  $f = Get-Ruta $E.Local "tareas/arnes-$Repo.json"
  $t = Lee-Json $f
  [void]$t.entradas.PSObject.Properties.Remove('plantilla')
  if ($null -ne $Plantilla) { $t.entradas | Add-Member -NotePropertyName plantilla -NotePropertyValue $Plantilla }
  if ($Huella) { $t.entradas.huella = $Huella }
  [System.IO.File]::WriteAllText($f, (ConvertTo-Json -InputObject $t -Depth 8))
}

function Plantilla-Tarea-M37($E, [string]$Repo) { return [string](Tarea-Arnes $E $Repo).entradas.plantilla }

# M37b: si el del original guardado es el de una plantilla vieja, se escriben otra vez los dos; sale esta Info y no la del migrado.
$AvisoM37b = 'La plantilla del test ha cambiado desde que se escribio el del original: escribo otra vez los dos (el del migrado traduce el nuevo).'

# Como Escenario-M29, con m37-copilot.ps1: ademas apunta cual de los tests del original (por su marca) traduce el arnes del migrado.
function Escenario-M37([string]$Nombre, $Casos) {
  $e = Nuevo-Escenario $Nombre $Casos
  $aj = [ordered]@{ CopilotExe = (Join-Path $falsos 'm37-copilot.ps1'); MvnExe = (Join-Path $falsos 'm29-mvn.ps1'); SegundosPorLlamada = 60 }
  Escribe $e.Home 'ajustes.json' (ConvertTo-Json -InputObject $aj)
  return $e
}

# Las llamadas de arnes del $Repo, en el orden en que empezaron (el nombre de su fichero lleva el pid, que no manda).
function Arneses-En-Orden-M37($E, [string]$Repo) { return @(Llamadas-Arnes $E $Repo | Sort-Object { [long]$_.inicio }) }

$Pruebas['m37 (a) los dos arneses guardados y la tarea del migrado sin plantilla: el del migrado se escribe otra vez (una llamada, con el test del original en el prompt), el del original no, y sale la Info'] = {
  $e = Escenario-M29 'm37-a' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba $e
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  $original = Test-Guardado $e 'original'
  $migrado = Test-Guardado $e 'migrado'
  Igual 'la tarea del migrado guarda la plantilla con que se escribio' (Plantilla-Ahora-M37) (Plantilla-Tarea-M37 $e 'migrado')
  Deja-Tarea-M37 $e 'migrado' $null
  Igual 'la dejo sin plantilla' '' (Plantilla-Tarea-M37 $e 'migrado')
  $r = Prueba $e
  Igual 'el segundo lanzamiento sale con 0' 0 $r.Codigo
  Igual 'el del migrado: una llamada nueva' 2 (Llamadas-Arnes $e 'migrado').Count
  Igual 'el del original: ninguna' 1 (Llamadas-Arnes $e 'original').Count
  $m = @(Arneses-En-Orden-M37 $e 'migrado')[1]
  $ruta = Get-Ruta $e.Local 'arnes/original/src/test/java/com/acme/viejo/PruebaLocalTest.java'
  $p = Registro-Arnes $e 'migrado' 1   # el registro lleva el numero de intento de la tarea, que vuelve a empezar
  Comprueba 'el prompt de la llamada lleva la ruta del test del original y el texto de traducirlo' ($p.Contains($ruta) -and $p.Contains($Traducelo)) $ruta
  Igual 'el falso ve la seccion de traducir' 'si' $m.traduce
  Igual 'y el test del original ya guardado' 'si' $m.'original-existe'
  Comprueba 'sale la Info de que la plantilla ha cambiado, una vez' ([regex]::Matches($r.Salida, [regex]::Escape($AvisoM37)).Count -eq 1) (Cola $r.Salida)
  Comprueba 'no dice que use el test de otro lanzamiento para el migrado' ($r.Salida -notmatch 'Arnes del migrado: bien \(el test de otro lanzamiento sigue valiendo\)') (Cola $r.Salida)
  Igual 'el del original guardado no cambia' $original (Test-Guardado $e 'original')
  $nuevo = Test-Guardado $e 'migrado'
  Comprueba 'el del migrado guardado es el de la segunda llamada' ($nuevo.Contains('MARCA_ARNES=migrado-2') -and $nuevo -ne $migrado) $nuevo
  Igual 'la tarea del migrado queda hecha' 'hecha' (Tarea-Arnes $e 'migrado').estado
  Igual 'y con la plantilla de ahora' (Plantilla-Ahora-M37) (Plantilla-Tarea-M37 $e 'migrado')
}

$Pruebas['m37 (a2) el caso de verdad: los dos arneses de antes (sin plantilla y con la huella de la plantilla de entonces): se escriben otra vez los dos, el del migrado traduciendo el nuevo del original, con la Info del original y no la del migrado'] = {
  $e = Escenario-M37 'm37-a2' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba $e
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  $casos = (Llamadas-Casos $e).Count
  Deja-Tarea-M37 $e 'original' $null 'aaaaaaaa'
  Deja-Tarea-M37 $e 'migrado' $null 'bbbbbbbb'
  $r = Prueba $e
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'el del original: una llamada nueva' 2 (Llamadas-Arnes $e 'original').Count
  Igual 'el del migrado: una llamada nueva' 2 (Llamadas-Arnes $e 'migrado').Count
  Igual 'el del migrado traduce el test del original nuevo' 'original-2' @(Arneses-En-Orden-M37 $e 'migrado')[1].'original-marca'
  Igual 'la Info del original, una vez' 1 ([regex]::Matches($r.Salida, [regex]::Escape($AvisoM37b))).Count
  Comprueba 'y no la del migrado' (-not $r.Salida.Contains($AvisoM37)) (Cola $r.Salida)
  Comprueba 'no dice que use el test de otro lanzamiento para ninguno' ($r.Salida -notmatch 'el test de otro lanzamiento sigue valiendo') (Cola $r.Salida)
  Igual 'los casos no se rehacen: sin llamadas de casos nuevas' $casos (Llamadas-Casos $e).Count
  Comprueba 'el del original guardado es el de la segunda llamada' ((Test-Guardado $e 'original').Contains('MARCA_ARNES=original-2'))
  Comprueba 'y el del migrado' ((Test-Guardado $e 'migrado').Contains('MARCA_ARNES=migrado-2'))
  Igual 'la tarea del original guarda la plantilla de ahora' (Plantilla-Ahora-M37) (Plantilla-Tarea-M37 $e 'original')
  Igual 'y la del migrado' (Plantilla-Ahora-M37) (Plantilla-Tarea-M37 $e 'migrado')
}

$Pruebas['m37 (b) con la plantilla de ahora en la tarea del migrado: no hay llamada para ningun arnes, ni con la tarea hecha ni con la huella de otro lanzamiento'] = {
  $e = Escenario-M29 'm37-b' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba $e
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  $migrado = Test-Guardado $e 'migrado'
  $n = @(Llamadas $e).Count
  Deja-Tarea-M37 $e 'migrado' (Plantilla-Ahora-M37)
  $r = Prueba $e
  Igual 'con la tarea hecha, sale con 0' 0 $r.Codigo
  Igual 'y sin llamadas' $n @(Llamadas $e).Count
  Comprueba 'sin la Info' (-not $r.Salida.Contains($AvisoM37)) (Cola $r.Salida)
  Deja-Tarea-M37 $e 'migrado' (Plantilla-Ahora-M37) 'bbbbbbbb'
  $r = Prueba $e
  Igual 'con la huella de otro lanzamiento, sale con 0' 0 $r.Codigo
  Igual 'sin llamadas' $n @(Llamadas $e).Count
  Comprueba 'el del migrado se reutiliza porque sigue valiendo' ($r.Salida -match 'Arnes del migrado: bien \(el test de otro lanzamiento sigue valiendo\)') (Cola $r.Salida)
  Comprueba 'sin la Info' (-not $r.Salida.Contains($AvisoM37)) (Cola $r.Salida)
  Igual 'el del migrado guardado es el de antes' $migrado (Test-Guardado $e 'migrado')
}

$Pruebas['m37 (c) con otra plantilla en la tarea del migrado (otro hash): se escribe otra vez el del migrado, con la tarea hecha o con otra huella'] = {
  $e = Escenario-M29 'm37-c' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba $e
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  Deja-Tarea-M37 $e 'migrado' 'deadbeef'
  $r = Prueba $e
  Igual 'con la tarea hecha, sale con 0' 0 $r.Codigo
  Igual 'el del migrado: una llamada nueva' 2 (Llamadas-Arnes $e 'migrado').Count
  Igual 'el del original: ninguna' 1 (Llamadas-Arnes $e 'original').Count
  Comprueba 'con la Info' ($r.Salida.Contains($AvisoM37)) (Cola $r.Salida)
  Igual 'la tarea queda con la plantilla de ahora' (Plantilla-Ahora-M37) (Plantilla-Tarea-M37 $e 'migrado')
  Deja-Tarea-M37 $e 'migrado' 'deadbeef' 'bbbbbbbb'
  $r = Prueba $e
  Igual 'con otra huella, sale con 0' 0 $r.Codigo
  Igual 'otra llamada del migrado' 3 (Llamadas-Arnes $e 'migrado').Count
  Igual 'y ninguna del original' 1 (Llamadas-Arnes $e 'original').Count
  Comprueba 'con la Info' ($r.Salida.Contains($AvisoM37)) (Cola $r.Salida)
  Comprueba 'y el del migrado guardado es el de la tercera llamada' ((Test-Guardado $e 'migrado').Contains('MARCA_ARNES=migrado-3'))
}

$Pruebas['m37 (d) con la misma plantilla y -Job con uno solo de los dos jobs: no se escribe otra vez ningun arnes'] = {
  $e = Escenario-M29 'm37-d' ([ordered]@{ cargaJob = @('importe=10.00'); remesaJob = @('importe=10.00') })
  $r = Prueba $e
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  Igual 'la tarea del migrado guarda la plantilla de ahora' (Plantilla-Ahora-M37) (Plantilla-Tarea-M37 $e 'migrado')
  $n = @(Llamadas-Arnes $e 'migrado').Count + @(Llamadas-Arnes $e 'original').Count
  $migrado = Test-Guardado $e 'migrado'
  $r = Prueba $e @('-Job', 'remesaJob')
  Igual 'con -Job sale con 0' 0 $r.Codigo
  Igual 'sin llamadas de arnes' $n (@(Llamadas-Arnes $e 'migrado').Count + @(Llamadas-Arnes $e 'original').Count)
  Comprueba 'sin la Info' (-not $r.Salida.Contains($AvisoM37)) (Cola $r.Salida)
  Igual 'el del migrado guardado es el de antes' $migrado (Test-Guardado $e 'migrado')
  Igual 'la plantilla de la tarea sigue siendo la de ahora' (Plantilla-Ahora-M37) (Plantilla-Tarea-M37 $e 'migrado')
}

$Pruebas['m37 (e) la tarea nueva guarda la plantilla: el lanzamiento que escribe los arneses y el siguiente a otro que rehizo el del migrado no llaman a la IA'] = {
  $e = Escenario-M29 'm37-e' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba $e
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  Igual 'la tarea del original guarda la plantilla de ahora' (Plantilla-Ahora-M37) (Plantilla-Tarea-M37 $e 'original')
  Igual 'y la del migrado' (Plantilla-Ahora-M37) (Plantilla-Tarea-M37 $e 'migrado')
  Deja-Tarea-M37 $e 'migrado' $null
  $r = Prueba $e
  Igual 'el segundo lanzamiento sale con 0' 0 $r.Codigo
  Igual 'rehace el del migrado: tres llamadas de arnes en total' 3 @(Llamadas $e | Where-Object { $_.tipo -eq 'arnes-local' }).Count
  Igual 'la tarea del migrado guarda la plantilla de ahora' (Plantilla-Ahora-M37) (Plantilla-Tarea-M37 $e 'migrado')
  $r = Prueba $e
  Igual 'el tercer lanzamiento sale con 0' 0 $r.Codigo
  Igual 'no hay llamadas nuevas' 3 @(Llamadas $e | Where-Object { $_.tipo -eq 'arnes-local' }).Count
  Comprueba 'ni la Info' (-not $r.Salida.Contains($AvisoM37)) (Cola $r.Salida)
  Comprueba 'ni el aviso de usar un test de otro lanzamiento' ($r.Salida -notmatch 'el test de otro lanzamiento sigue valiendo') (Cola $r.Salida)
}

$Pruebas['m37 (f) la pregunta cuenta el arnes del migrado entre las tareas por hacer; con n no se toca nada y el siguiente lanzamiento, con s, lo escribe otra vez'] = {
  $e = Escenario-M29 'm37-f' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba $e
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  $migrado = Test-Guardado $e 'migrado'
  Deja-Tarea-M37 $e 'migrado' $null 'bbbbbbbb'
  $n = @(Llamadas $e).Count
  $r = Prueba $e @() '' 'n'
  Comprueba 'pregunta por 1 tarea' ($r.Salida -match 'Llamar a Copilot para esas 1 tareas\?') (Cola $r.Salida)
  Comprueba 'con n dice que no se ha hecho nada' ($r.Salida -match 'No se ha hecho nada') (Cola $r.Salida)
  Igual 'sin llamadas nuevas' $n @(Llamadas $e).Count
  Igual 'el del migrado guardado sigue ahi' $migrado (Test-Guardado $e 'migrado')
  Comprueba 'y la tarea sigue sin la plantilla de ahora' ((Plantilla-Tarea-M37 $e 'migrado') -ne (Plantilla-Ahora-M37)) (Plantilla-Tarea-M37 $e 'migrado')
  $r = Prueba $e @() '' 's'
  Igual 'con s sale con 0' 0 $r.Codigo
  Igual 'llama una vez' ($n + 1) @(Llamadas $e).Count
  Comprueba 'con la Info' ($r.Salida.Contains($AvisoM37)) (Cola $r.Salida)
  Comprueba 'y el del migrado guardado es el nuevo' ((Test-Guardado $e 'migrado').Contains('MARCA_ARNES=migrado-2'))
}

$Pruebas['m37 (g) con -RehacerArnes y la tarea del migrado sin plantilla: se escribe otra vez una sola vez y sin la Info, que ya lo pidio el usuario'] = {
  $e = Escenario-M29 'm37-g' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba $e
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  Deja-Tarea-M37 $e 'migrado' $null
  $r = Prueba $e @('-RehacerArnes')
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'el del migrado: una llamada nueva' 2 (Llamadas-Arnes $e 'migrado').Count
  Comprueba 'no sale la Info de la plantilla' (-not $r.Salida.Contains($AvisoM37)) (Cola $r.Salida)
  Igual 'la tarea del migrado guarda la plantilla de ahora' (Plantilla-Ahora-M37) (Plantilla-Tarea-M37 $e 'migrado')
}

# (h) y (i): la tarea del original sin plantilla ($Plantilla = $null) o con otra, y la del migrado con la de ahora.
function Prueba-Original-Viejo-M37([string]$Nombre, $Plantilla) {
  $e = Escenario-M37 $Nombre ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba $e
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  $casos = (Llamadas-Casos $e).Count
  $original = Test-Guardado $e 'original'
  $migrado = Test-Guardado $e 'migrado'
  Igual 'la tarea del migrado guarda la plantilla de ahora' (Plantilla-Ahora-M37) (Plantilla-Tarea-M37 $e 'migrado')
  Deja-Tarea-M37 $e 'original' $Plantilla
  $r = Prueba $e
  Igual 'el segundo lanzamiento sale con 0' 0 $r.Codigo
  $o = @(Arneses-En-Orden-M37 $e 'original')
  $m = @(Arneses-En-Orden-M37 $e 'migrado')
  Igual 'el del original: una llamada nueva' 2 $o.Count
  Igual 'el del migrado: una llamada nueva' 2 $m.Count
  Igual 'la del original no traduce nada' 'no' $o[1].traduce
  Igual 'la del migrado traduce el test del original' 'si' $m[1].traduce
  Igual 'y es el nuevo, no el de antes' 'original-2' $m[1].'original-marca'
  Comprueba 'la del migrado empieza cuando ha acabado la del original' ([long]$m[1].inicio -ge [long]$o[1].fin) "original fin=$($o[1].fin), migrado inicio=$($m[1].inicio)"
  Igual 'la Info del original, una vez' 1 ([regex]::Matches($r.Salida, [regex]::Escape($AvisoM37b))).Count
  Comprueba 'y no la del migrado' (-not $r.Salida.Contains($AvisoM37)) (Cola $r.Salida)
  Igual 'los casos no se rehacen: sin llamadas de casos nuevas' $casos (Llamadas-Casos $e).Count
  $nuevoOriginal = Test-Guardado $e 'original'
  Comprueba 'el del original guardado es el de la segunda llamada' ($nuevoOriginal.Contains('MARCA_ARNES=original-2') -and $nuevoOriginal -ne $original) $nuevoOriginal
  $nuevoMigrado = Test-Guardado $e 'migrado'
  Comprueba 'y el del migrado' ($nuevoMigrado.Contains('MARCA_ARNES=migrado-2') -and $nuevoMigrado -ne $migrado) $nuevoMigrado
  Igual 'la tarea del original queda hecha con la plantilla de ahora' ('hecha:' + (Plantilla-Ahora-M37)) ((Tarea-Arnes $e 'original').estado + ':' + (Plantilla-Tarea-M37 $e 'original'))
  Igual 'y la del migrado' ('hecha:' + (Plantilla-Ahora-M37)) ((Tarea-Arnes $e 'migrado').estado + ':' + (Plantilla-Tarea-M37 $e 'migrado'))
  $n = @(Llamadas $e).Count
  $r = Prueba $e
  Igual 'el tercer lanzamiento sale con 0' 0 $r.Codigo
  Igual 'sin llamadas nuevas' $n @(Llamadas $e).Count
  Comprueba 'ni Info' (-not $r.Salida.Contains($AvisoM37b) -and -not $r.Salida.Contains($AvisoM37)) (Cola $r.Salida)
}

$Pruebas['m37 (h) la tarea del original sin plantilla y la del migrado con la de ahora: se escriben otra vez los dos, el del migrado traduciendo el nuevo del original; una sola Info, la del original; los casos no'] = {
  Prueba-Original-Viejo-M37 'm37-h' $null
}

$Pruebas['m37 (i) la tarea del original con otra plantilla (otro hash) y la del migrado con la de ahora: lo mismo que (h)'] = {
  Prueba-Original-Viejo-M37 'm37-i' 'deadbeef'
}

$Pruebas['m37 (j) el original con la plantilla de ahora y el migrado sin ella: solo se escribe otra vez el del migrado, con la Info del migrado y no la del original'] = {
  $e = Escenario-M37 'm37-j' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba $e
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  $casos = (Llamadas-Casos $e).Count
  $original = Test-Guardado $e 'original'
  Deja-Tarea-M37 $e 'migrado' $null
  $r = Prueba $e
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'el del original: ninguna llamada nueva' 1 (Llamadas-Arnes $e 'original').Count
  Igual 'el del migrado: una llamada nueva' 2 (Llamadas-Arnes $e 'migrado').Count
  Igual 'traduce el mismo test del original de antes' 'original-1' @(Arneses-En-Orden-M37 $e 'migrado')[1].'original-marca'
  Igual 'la Info del migrado, una vez' 1 ([regex]::Matches($r.Salida, [regex]::Escape($AvisoM37))).Count
  Comprueba 'y no la del original' (-not $r.Salida.Contains($AvisoM37b)) (Cola $r.Salida)
  Igual 'sin llamadas de casos nuevas' $casos (Llamadas-Casos $e).Count
  Igual 'el del original guardado no cambia' $original (Test-Guardado $e 'original')
}

$Pruebas['m37 (k) -RehacerArnes con el original de una plantilla vieja: se escriben otra vez los dos, sin ninguna Info; con el original de ahora, solo el migrado'] = {
  $e = Escenario-M37 'm37-k' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba $e
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  $original = Test-Guardado $e 'original'
  $r = Prueba $e @('-RehacerArnes')
  Igual 'con el original de ahora, sale con 0' 0 $r.Codigo
  Igual 'el del original: ninguna llamada nueva' 1 (Llamadas-Arnes $e 'original').Count
  Igual 'el del migrado: una nueva' 2 (Llamadas-Arnes $e 'migrado').Count
  Igual 'el del original guardado no cambia' $original (Test-Guardado $e 'original')
  Comprueba 'sin Info' (-not $r.Salida.Contains($AvisoM37b) -and -not $r.Salida.Contains($AvisoM37)) (Cola $r.Salida)
  $casos = (Llamadas-Casos $e).Count
  Deja-Tarea-M37 $e 'original' $null
  $r = Prueba $e @('-RehacerArnes')
  Igual 'con el original viejo, sale con 0' 0 $r.Codigo
  Igual 'el del original: una llamada nueva' 2 (Llamadas-Arnes $e 'original').Count
  Igual 'el del migrado: otra' 3 (Llamadas-Arnes $e 'migrado').Count
  Igual 'el del migrado traduce el nuevo del original' 'original-2' @(Arneses-En-Orden-M37 $e 'migrado')[2].'original-marca'
  Comprueba 'sin ninguna Info' (-not $r.Salida.Contains($AvisoM37b) -and -not $r.Salida.Contains($AvisoM37)) (Cola $r.Salida)
  Igual 'sin llamadas de casos nuevas' $casos (Llamadas-Casos $e).Count
  Igual 'la tarea del original guarda la plantilla de ahora' (Plantilla-Ahora-M37) (Plantilla-Tarea-M37 $e 'original')
}

$Pruebas['m37 (l) la pregunta cuenta los dos arneses; con n no se toca nada y el siguiente lanzamiento, con s, escribe otra vez los dos aunque el original sea ya el de otra huella'] = {
  $e = Escenario-M37 'm37-l' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba $e
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  $original = Test-Guardado $e 'original'
  $migrado = Test-Guardado $e 'migrado'
  Deja-Tarea-M37 $e 'original' $null 'aaaaaaaa'
  $n = @(Llamadas $e).Count
  $r = Prueba $e @() '' 'n'
  Comprueba 'pregunta por 2 tareas' ($r.Salida -match 'Llamar a Copilot para esas 2 tareas\?') (Cola $r.Salida)
  Comprueba 'con n dice que no se ha hecho nada' ($r.Salida -match 'No se ha hecho nada') (Cola $r.Salida)
  Igual 'sin llamadas nuevas' $n @(Llamadas $e).Count
  Igual 'el del original guardado sigue ahi' $original (Test-Guardado $e 'original')
  Igual 'y el del migrado' $migrado (Test-Guardado $e 'migrado')
  $r = Prueba $e @() '' 's'
  Igual 'con s sale con 0' 0 $r.Codigo
  Igual 'llama dos veces' ($n + 2) @(Llamadas $e).Count
  Comprueba 'con la Info del original' ($r.Salida.Contains($AvisoM37b)) (Cola $r.Salida)
  Comprueba 'el del original guardado es el nuevo' ((Test-Guardado $e 'original').Contains('MARCA_ARNES=original-2'))
  Comprueba 'y el del migrado' ((Test-Guardado $e 'migrado').Contains('MARCA_ARNES=migrado-2'))
}

# M37c: el original guardado ya no vale en este commit (Rompe-Arnes-Guardado: mvn-local.ps1 no compila un .java con NO_COMPILA; Use-ArnesGuardado lo deja pendiente) y
# el migrado guardado si vale y tiene la plantilla de ahora: se escribe otra vez el del original y, como lo traduce, el del migrado tambien.
$Pruebas['m37 (m) el arnes del original guardado ya no vale en este commit: se escribe otra vez y el del migrado tambien, traduciendo el nuevo, aunque el suyo siga valiendo y lleve la plantilla de ahora; sin Info de la plantilla'] = {
  $e = Escenario-M37 'm37-m' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba $e
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  $casos = (Llamadas-Casos $e).Count
  $migrado = Test-Guardado $e 'migrado'
  Igual 'la tarea del original guarda la plantilla de ahora' (Plantilla-Ahora-M37) (Plantilla-Tarea-M37 $e 'original')
  Igual 'y la del migrado' (Plantilla-Ahora-M37) (Plantilla-Tarea-M37 $e 'migrado')
  Rompe-Arnes-Guardado $e 'original'
  $r = Prueba $e
  Igual 'el segundo lanzamiento sale con 0' 0 $r.Codigo
  Comprueba 'dice que el del original ya no vale en este commit' ($r.Salida -match 'PruebaLocalTest del original de otro lanzamiento ya no vale en este commit') (Cola $r.Salida)
  Igual 'el del original: una llamada nueva' 2 (Llamadas-Arnes $e 'original').Count
  Igual 'el del migrado: una llamada nueva' 2 (Llamadas-Arnes $e 'migrado').Count
  $m = @(Arneses-En-Orden-M37 $e 'migrado')[1]
  Igual 'el del migrado traduce el test del original' 'si' $m.traduce
  Igual 'y es el nuevo, no el que ya no valia' 'original-2' $m.'original-marca'
  Comprueba 'sin Info de la plantilla, ni la del original ni la del migrado' (-not $r.Salida.Contains($AvisoM37b) -and -not $r.Salida.Contains($AvisoM37)) (Cola $r.Salida)
  Comprueba 'no dice que use el test de otro lanzamiento para el migrado' ($r.Salida -notmatch 'Arnes del migrado: bien \(el test de otro lanzamiento sigue valiendo\)') (Cola $r.Salida)
  Igual 'los casos no se rehacen: sin llamadas de casos nuevas' $casos (Llamadas-Casos $e).Count
  $nuevoOriginal = Test-Guardado $e 'original'
  Comprueba 'el del original guardado es el de la segunda llamada' ($nuevoOriginal.Contains('MARCA_ARNES=original-2') -and -not $nuevoOriginal.Contains('NO_COMPILA')) $nuevoOriginal
  $nuevoMigrado = Test-Guardado $e 'migrado'
  Comprueba 'y el del migrado' ($nuevoMigrado.Contains('MARCA_ARNES=migrado-2') -and $nuevoMigrado -ne $migrado) $nuevoMigrado
  Igual 'las dos tareas quedan hechas' 'hecha,hecha' ((Tarea-Arnes $e 'original').estado + ',' + (Tarea-Arnes $e 'migrado').estado)
  $n = @(Llamadas $e).Count
  $r = Prueba $e
  Igual 'el tercer lanzamiento sale con 0' 0 $r.Codigo
  Igual 'sin llamadas nuevas' $n @(Llamadas $e).Count
}

# ===================== -Job guarda lo de los otros jobs, y 'mejorado' (m39) =====================
# E6: con -Job, datos\prueba-local.json se escribia solo con ese job y el informe contaba uno. Ahora, si lo guardado de antes es del mismo
# commit del migrado y del mismo del original, el JSON lleva ademas lo de los otros jobs tal como estaba (casos, jobs, reparaciones y
# culpables, por job); con otro commit lo descarta y lo dice. Sin -Job se escribe entero. Y un arreglo de -Reparar que baja las lineas
# distintas pero deja la clave distinta es 'mejorado', no 'arreglado'. Los escenarios de -Reparar son los de m25.

# cargaJob (dos casos) sale igual y remesaJob (el caso del limite, importe=5.00) sale distinto: el migrado lleva minimo=5.01.
function Escenario-M39([string]$Nombre) {
  return (Nuevo-Escenario $Nombre ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00'); remesaJob = @('importe=5.00') }) 'minimo=5.00' 'minimo=5.01')
}

$AvisoM39 = 'Los otros jobs se probaron con otro commit: no los guardo. Lanza sin -Job para probarlos todos.'

function Jobs-M39($E) { return (@((Lee-Json $E.Json).jobs | ForEach-Object { $_.job }) -join ',') }

function Casos-M39($E) { return (@((Lee-Json $E.Json).casos | ForEach-Object { "$($_.job)/$($_.caso)" }) -join ',') }

# La fila de jobs y los casos de $Job tal como los lee el JSON, en una sola linea cada cosa: para ver que no han cambiado.
function Entradas-M39($E, [string]$Job) {
  $o = Lee-Json $E.Json
  return ((ConvertTo-Json -InputObject @($o.jobs | Where-Object { $_.job -eq $Job }) -Depth 10 -Compress) + '|' + (ConvertTo-Json -InputObject @($o.casos | Where-Object { $_.job -eq $Job }) -Depth 10 -Compress))
}

$Pruebas['m39 (a) -Job con lo guardado del mismo commit: el JSON lleva el job de ahora y el otro tal como estaba, en el orden de los jobs; la consola, solo el de ahora'] = {
  $e = Escenario-M39 'm39-a'
  $r = Prueba $e
  Igual 'el lanzamiento entero sale con 2 (remesaJob distinto)' 2 $r.Codigo
  $otro = Entradas-M39 $e 'remesaJob'
  Comprueba 'el otro job lleva su diferencia' ($otro -match '"resultado":"distinto"' -and $otro -match '"diferencias":\[') $otro
  $r = Prueba $e @('-Job', 'cargaJob')
  Igual 'con -Job sale con 0 (cargaJob igual)' 0 $r.Codigo
  Igual 'el JSON lleva los dos jobs' 'cargaJob,remesaJob' (Jobs-M39 $e)
  Igual 'y los tres casos' 'cargaJob/caso-01,cargaJob/caso-02,remesaJob/caso-01' (Casos-M39 $e)
  Comprueba 'el caso del otro job llevaba su grupo (el del lanzamiento de antes)' ($otro -match '"grupo":\d+') $otro
  Igual 'la fila y el caso del otro job son los de antes, tal cual, menos su grupo (que es de otro lanzamiento: M50)' ($otro -replace ',"grupo":\d+', '') (Entradas-M39 $e 'remesaJob')
  Comprueba 'la consola ensena la tabla del job de ahora' ($r.Salida -match 'cargaJob\s+2\s+2\s+0\s+0') (Cola $r.Salida)
  Comprueba 'y nada del otro job' ($r.Salida -notmatch 'remesaJob') (Cola $r.Salida)
  Comprueba 'sin la Info de otro commit' (-not $r.Salida.Contains($AvisoM39)) (Cola $r.Salida)
  $o = Lee-Json $e.Json
  Igual 'los commits del JSON son los de siempre' (GitEn $e.Wt @('rev-parse', 'HEAD')) $o.commitMigrado
}

$Pruebas['m39 (b) -Job con lo guardado de otro commit, del migrado o del original: el JSON solo lleva el job de ahora y la consola dice que descarta los otros'] = {
  $e = Escenario-M39 'm39-b'
  [void](Prueba $e)
  [void](Commit-En $e.Wt 'notas/paso-1.txt' "nota`n" 'otro commit en el migrado')
  $r = Prueba $e @('-Job', 'cargaJob')
  Igual 'con -Job sale con 0' 0 $r.Codigo
  Igual 'el JSON solo lleva el job de ahora' 'cargaJob' (Jobs-M39 $e)
  Igual 'y sus dos casos' 'cargaJob/caso-01,cargaJob/caso-02' (Casos-M39 $e)
  Comprueba 'la consola dice que no guarda los otros' ($r.Salida.Contains($AvisoM39)) (Cola $r.Salida)
  Igual 'el commit del migrado del JSON es el nuevo' (GitEn $e.Wt @('rev-parse', 'HEAD')) (Lee-Json $e.Json).commitMigrado
  # lo mismo con un commit nuevo en el original
  $r = Prueba $e
  Igual 'sin -Job el JSON vuelve a llevar los dos jobs' 'cargaJob,remesaJob' (Jobs-M39 $e)
  Comprueba 'y no dice nada de otro commit' (-not $r.Salida.Contains($AvisoM39)) (Cola $r.Salida)
  [void](Commit-En $e.Legacy 'notas/paso-1.txt' "nota`n" 'otro commit en el original')
  $r = Prueba $e @('-Job', 'cargaJob')
  Igual 'con otro commit del original tambien: solo el job de ahora' 'cargaJob' (Jobs-M39 $e)
  Comprueba 'y lo dice' ($r.Salida.Contains($AvisoM39)) (Cola $r.Salida)
  Igual 'el commit del original del JSON es el nuevo' (GitEn $e.Legacy @('rev-parse', 'HEAD')) (Lee-Json $e.Json).commitOriginal
}

$Pruebas['m39 (c) sin -Job el JSON se escribe entero, como hoy, sin mezclar lo de antes; con -Job y sin JSON de antes, solo ese job y sin Info'] = {
  $e = Escenario-M39 'm39-c'
  [void](Prueba $e)
  Igual 'la primera vez, remesaJob sale distinto' 'igual,igual,distinto' ((Resultados $e) -join ',')
  [void](Commit-En $e.Wt 'regla.txt' "minimo=5.00`n" 'arregla el limite')
  $r = Prueba $e
  Igual 'el segundo lanzamiento sale con 0' 0 $r.Codigo
  Igual 'los tres casos son los de ahora' 'igual,igual,igual' ((Resultados $e) -join ',')
  Igual 'los dos jobs' 'cargaJob,remesaJob' (Jobs-M39 $e)
  Comprueba 'sin Info de otro commit' (-not $r.Salida.Contains($AvisoM39)) (Cola $r.Salida)
  Remove-Item -LiteralPath $e.Json
  $r = Prueba $e @('-Job', 'remesaJob')
  Igual 'sin JSON de antes, -Job escribe solo ese job' 'remesaJob' (Jobs-M39 $e)
  Comprueba 'y sin Info' (-not $r.Salida.Contains($AvisoM39)) (Cola $r.Salida)
}

$Pruebas['m39 (d) -Reparar: el arreglo baja las lineas distintas pero la clave sigue distinta: la consola y la reparacion dicen mejorado, no arreglado; el commit y el resultado, como siempre'] = {
  $e = Escenario-M25 'm39-d' ([ordered]@{ cargaJob = @('importe=5.00;;importe=5.00;;importe=4.80') })
  $wt0 = GitEn $e.Wt @('rev-parse', 'HEAD')
  $antes = (Caso $e 'cargaJob' 'caso-01')
  $r = Prueba $e @('-Reparar') 'reparar-pasado'
  Igual 'sale con 2 (el caso sigue distinto)' 2 $r.Codigo
  Igual 'el caso sigue distinto' 'distinto' (Caso $e 'cargaJob' 'caso-01').resultado
  Igual 'con una linea distinta (eran dos)' 1 (@((Caso $e 'cargaJob' 'caso-01').diferencias | ForEach-Object { [int]$_.lineas } | Measure-Object -Sum).Sum)
  Igual 'un commit nuevo en la rama de rescate' 1 (GitEn $e.Wt @('rev-list', '--count', "$wt0..HEAD"))
  $rep = @(Reparaciones $e)
  Igual 'reparaciones lleva una entrada' 1 $rep.Count
  Igual 'que dice mejorado' 'mejorado' $rep[0].resultado
  Igual 'con el commit entero' (GitEn $e.Wt @('rev-parse', 'HEAD')) $rep[0].commit
  Igual 'su asunto' (Asunto-M25 'cargaJob' 'caso-01') $rep[0].asunto
  Igual 'y un intento' 1 $rep[0].intentos
  Comprueba 'la consola dice Mejorado, con la clave y el commit' ($r.Salida.Contains("Mejorado cargaJob/caso-01 ficheros/salida/resultado_<hoy:yyyyMMdd>.txt en el commit $(Corto $rep[0].commit): sigue distinta, con menos lineas.")) (Cola $r.Salida)
  Comprueba 'y no dice Arreglado' ($r.Salida -cnotmatch 'Arreglado ') (Cola $r.Salida)
  Comprueba 'el resumen de reparaciones dice mejorado' ($r.Salida -match "(?m)^  mejorado: cargaJob/caso-01 .* en $(Corto $rep[0].commit) ") (Cola $r.Salida)
  Comprueba 'y no lo da por arreglado ni por no arreglado' ($r.Salida -notmatch '(?m)^  (no )?arreglado: ') (Cola $r.Salida)
  Comprueba 'sigue la tabla de despues de reparar' ($r.Salida.Contains('Despues de reparar:')) (Cola $r.Salida)
}

$Pruebas['m39 (e) -Reparar: el arreglo deja la clave igual: sigue diciendo Arreglado, en la consola y en la reparacion'] = {
  $e = Escenario-M25 'm39-e' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') }) -Sano
  $r = Prueba $e @('-Reparar') 'reparar-arregla'
  Igual 'sale con 0' 0 $r.Codigo
  $rep = @(Reparaciones $e)
  Igual 'reparaciones lleva una entrada, arreglado' 'arreglado' $rep[0].resultado
  Comprueba 'la consola dice Arreglado, con la clave y el commit' ($r.Salida.Contains("Arreglado cargaJob/caso-01 ficheros/salida/resultado_<hoy:yyyyMMdd>.txt en el commit $(Corto $rep[0].commit).")) (Cola $r.Salida)
  Comprueba 'y no dice Mejorado' ($r.Salida -cnotmatch 'Mejorado ') (Cola $r.Salida)
  Comprueba 'el resumen dice arreglado' ($r.Salida -match '(?m)^  arreglado: cargaJob/caso-01 ') (Cola $r.Salida)
  Comprueba 'sigue la tabla de despues de reparar' ($r.Salida.Contains('Despues de reparar:')) (Cola $r.Salida)
}

$Pruebas['m39 (f) -Job con -Reparar: el arreglo hace un commit nuevo y lo guardado de los otros jobs ya no vale: el JSON solo lleva el job de ahora, con su reparacion, y la consola lo dice'] = {
  $e = Escenario-M25 'm39-f' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00'); remesaJob = @('importe=10.00') }) -Sano
  $r = Prueba $e
  Igual 'el lanzamiento entero sale con 2' 2 $r.Codigo
  Igual 'el JSON lleva los dos jobs' 'cargaJob,remesaJob' (Jobs-M39 $e)
  $r = Prueba $e @('-Job', 'cargaJob', '-Reparar') 'reparar-arregla'
  Igual 'con -Job y -Reparar sale con 0' 0 $r.Codigo
  Igual 'el JSON solo lleva el job de ahora' 'cargaJob' (Jobs-M39 $e)
  Comprueba 'la consola dice que no guarda los otros' ($r.Salida.Contains($AvisoM39)) (Cola $r.Salida)
  $rep = @(Reparaciones $e)
  Igual 'con su reparacion, arreglada' 'arreglado' $rep[0].resultado
  Igual 'el commit del JSON es el del arreglo' $rep[0].commit (Lee-Json $e.Json).commitMigrado
}

$Pruebas['m39 (g) -Job con -Reparar sin commit nuevo: las reparaciones del otro job tambien se quedan, por job'] = {
  $e = Escenario-M25 'm39-g' ([ordered]@{ cargaJob = @('importe=5.00'); remesaJob = @('importe=10.00') }) -Sano
  $r = Prueba $e @('-Reparar') 'reparar-no'
  Igual 'el lanzamiento entero sale con 2' 2 $r.Codigo
  $rep = @(Reparaciones $e)
  Igual 'cargaJob: no se arregla' 'cargaJob no se arregla' "$($rep[0].job) $($rep[0].resultado)"
  $antes = ConvertTo-Json -InputObject $rep -Depth 10 -Compress
  $r = Prueba $e @('-Job', 'remesaJob', '-Reparar') 'reparar-no'
  Igual 'con -Job remesaJob sale con 0' 0 $r.Codigo
  Comprueba 'dice que no hay casos distintos que arreglar' ($r.Salida.Contains('no hay casos distintos que arreglar')) (Cola $r.Salida)
  Igual 'el JSON lleva los dos jobs' 'cargaJob,remesaJob' (Jobs-M39 $e)
  Igual 'y la reparacion de cargaJob, como estaba' $antes (ConvertTo-Json -InputObject @(Reparaciones $e) -Depth 10 -Compress)
  Comprueba 'sin Info de otro commit' (-not $r.Salida.Contains($AvisoM39)) (Cola $r.Salida)
}

$Pruebas['m39 (h) -Job: lo del job de ahora es lo nuevo aunque lo guardado diga otra cosa, y los culpables del otro job se quedan'] = {
  $e = Escenario-M39 'm39-h'
  $r = Prueba $e
  Igual 'el lanzamiento entero sale con 2 (remesaJob distinto)' 2 $r.Codigo
  $o = Lee-Json $e.Json
  foreach ($c in @($o.casos | Where-Object { $_.job -eq 'cargaJob' })) { $c.resultado = 'distinto' }
  $cul = [pscustomobject]@{ job = 'remesaJob'; caso = 'caso-01'; commit = $o.commitMigrado; asunto = 'm39: culpable de antes'; deshecho = $false }
  $o | Add-Member -NotePropertyName culpables -NotePropertyValue @($cul) -Force
  [System.IO.File]::WriteAllText($e.Json, (ConvertTo-Json -InputObject $o -Depth 20))
  $r = Prueba $e @('-Job', 'cargaJob')
  Igual 'con -Job sale con 0 (cargaJob igual)' 0 $r.Codigo
  $n = Lee-Json $e.Json
  Igual 'los casos de cargaJob son los de ahora (iguales), no los guardados' 'igual,igual' (@($n.casos | Where-Object { $_.job -eq 'cargaJob' } | ForEach-Object { $_.resultado }) -join ',')
  Igual 'los culpables del otro job se quedan' 'remesaJob/caso-01 m39: culpable de antes' (@($n.culpables | ForEach-Object { "$($_.job)/$($_.caso) $($_.asunto)" }) -join ',')
}

# ===================== M40: la base de prueba tiene las tablas que usa el batch =====================
# Estos escenarios usan los falsos m40-copilot.ps1 y m40-mvn.ps1 (guiones en RESCATE_M40, 'guion=valor:regex' separados por ';'):
#   tablas=<n>/<T_A,T_B>:<id de tarea>   el arnes cuyo id casa deja en su test la base con esas tablas desde su llamada n (con n alto, nunca)
#   falta-tabla=T_A:<job/caso>           el original, la primera vez que ejecuta el caso, no lo prepara: Tabla "T_A" no encontrada
#   falta-columna=T_A.X:<job/caso>       lo mismo con Columna "X" no encontrada en un INSERT INTO T_A
#   migrado-no-corre:<job/caso>          el migrado no deja nada de ese caso
# El original lleva un Repo.java con 'INSERT INTO T_A' en la linea 4.

$SitioTablaM40 = 'src/main/java/com/acme/viejo/Repo.java:4'

function Escenario-M40([string]$Nombre, $Casos, [string]$Prefijo = 'm40') {
  $e = Nuevo-Escenario $Nombre $Casos
  $aj = [ordered]@{ CopilotExe = (Join-Path $falsos "$Prefijo-copilot.ps1"); MvnExe = (Join-Path $falsos "$Prefijo-mvn.ps1"); SegundosPorLlamada = 60 }
  Escribe $e.Home 'ajustes.json' (ConvertTo-Json -InputObject $aj)
  Escribe $e.Legacy 'src/main/java/com/acme/viejo/Repo.java' "package com.acme.viejo;`n`npublic class Repo {`n  static final String A = `"INSERT INTO T_A (ID, NOMBRE) VALUES (?, ?)`";`n}`n"
  [void](GitEn $e.Legacy @('add', 'src/main/java/com/acme/viejo/Repo.java'))
  [void](GitEn $e.Legacy @('commit', '-q', '-m', 'repo con sql'))
  return $e
}

function Prueba-M40($E, [string]$Guion, [string[]]$A = @()) {
  $env:RESCATE_M40 = $Guion
  try { return (Prueba $E $A) }
  finally { $env:RESCATE_M40 = '' }
}

# El registro (prompt y respuesta) de la llamada $N de la tarea del caso $Caso (de dos digitos) del job $Job.
function Registro-Caso-M40($E, [string]$Job, [string]$Caso, [int]$N) {
  $f = Get-Ruta $E.Local "registros/caso-$Job-$Caso-$N.log"
  if (-not (Test-Path -LiteralPath $f)) { return '' }
  return [System.IO.File]::ReadAllText($f)
}

function Tarea-Caso-M40($E, [string]$Job, [string]$Caso) { return (Lee-Json (Get-Ruta $E.Local "tareas/caso-$Job-$Caso.json")) }

# Lanza Get-TablasBatch sobre $Raiz en un .ps1 con solo las funciones del inventario: una linea 'T|tabla|sitio' por tabla, y despues el $Extra que se pase.
function Inventario-M40([string]$Raiz, [string]$Extra = '') {
  $f = Join-Path $Dir 'm40-inventario.ps1'
  $cuerpo = "foreach (`$t in @(Get-TablasBatch `$Raiz)) { 'T|' + `$t.tabla + '|' + `$t.sitio }`n" + $Extra
  [System.IO.File]::WriteAllText($f, ('param([string]$Raiz)' + "`n" + (Texto-De-Funciones $Script @('Get-TablasBatch', 'Get-FicherosConSql', 'Get-ListaTablas', 'Sort-Ordinal')) + "`n" + (Texto-De-Funciones (Join-Path (Split-Path -Parent $Script) 'comun.ps1') @('Join-Ruta', 'Get-Rel', 'Get-TablasSql', 'Get-NombreTabla')) + "`n" + $cuerpo))
  return (Lanzar $f @($Raiz))
}

$Pruebas['m40 (a) inventario de tablas: las de las cadenas de los .java, @Table y el texto de .sql, .xml, .properties y .yml, con su primer sitio; no las de comentarios, Spring Batch, DUAL ni las de :x, ? o $'] = {
  $raiz = Join-Path $Dir 'm40-inventario'
  Escribe $raiz 'src/main/java/com/acme/Dao.java' @'
package com.acme;

// lee from the file y nada mas
/* y actualiza update the cache */
@Table(name = "T_C")
public class Dao {
  static final String A = "INSERT INTO T_A (ID) VALUES (?)";
  static final String B = "select x from ESQ.T_B b where b.id = 1"; // delete from T_COMENTADA
  static final String M = "MERGE INTO T_M USING DUAL ON (1 = 1)";
  static final String P = "SELECT * FROM BATCH_JOB_INSTANCE, TASK_EXECUTION JOIN DUAL";
  static final String Q = "SELECT * FROM :tabla";
  static final String R = "SELECT * FROM ${esquema}.T_Z";
  static final String S = "select a from ab where x = ?";
  static final String U = "SELECT 1 FROM ? x";
  static final String D = "DELETE FROM T_DEL WHERE 1 = 1";
  static final String J = "SELECT * FROM T_A a JOIN T_J j ON a.id = j.id";
  static final String T = "CREATE TABLE IF NOT EXISTS T_CREADA (ID INT)";
  static final char C = '"';
  static final String L = "http://x?q=1 UPDATE T_URL SET a = 1" + C;
  static final String N = "SELECT * FROM T_NL\n WHERE 1 = 1";
  static final String TB = """
      SELECT *
        FROM T_TB
      """;
}
'@
  Escribe $raiz 'src/main/resources/schema.sql' "-- insert into T_SQL_COMENTADA`nUPDATE T_D SET x = 1;`n`nselect * from`n  T_D2;`n"
  Escribe $raiz 'src/main/resources/mapper.xml' "<!-- select * from T_XML_COMENTADA -->`n<mapper>`n  <select id=`"x`">select * from T_E</select>`n</mapper>`n"
  Escribe $raiz 'src/main/resources/batch.properties' "# delete from T_PROP_COMENTADA`nsql.lista=select * from T_F`n"
  Escribe $raiz 'src/main/resources/application.yml' "consulta: delete from T_G where x = 1`n"
  Escribe $raiz 'src/main/resources/notas.txt' "from T_TXT`n"
  Escribe $raiz 'src/test/java/com/acme/DaoTest.java' "class DaoTest { String s = `"INSERT INTO T_TEST (ID) VALUES (1)`"; }`n"
  $r = Inventario-M40 $raiz @'
'L|' + (Get-ListaTablas @(1..12 | ForEach-Object { [pscustomobject]@{ tabla = ('T_' + $_.ToString('00')); sitio = "x.java:$_" } }))
'V|' + @(Get-TablasBatch (Join-Path $Raiz 'no-existe')).Count
'@
  $t = @($r.Salida -split "`n" | Where-Object { $_ -cmatch '^T\|' } | ForEach-Object { $_.TrimEnd().Substring(2) })
  $c = 'src/main/java/com/acme/Dao.java'
  $s = 'src/main/resources'
  $esperado = @("T_A|${c}:7", "T_B|${c}:8", "T_C|${c}:5", "T_CREADA|${c}:17", "T_D|$s/schema.sql:2", "T_D2|$s/schema.sql:5", "T_DEL|${c}:15", "T_E|$s/mapper.xml:3", "T_F|$s/batch.properties:2", "T_G|$s/application.yml:1", "T_J|${c}:16", "T_M|${c}:9", "T_NL|${c}:20", "T_TB|${c}:23", "T_URL|${c}:19")
  Igual 'las tablas con su primer sitio, en orden' ($esperado -join ',') ($t -join ',')
  Comprueba 'ni una de las que no son' (@($t | Where-Object { $_ -match 'COMENTADA|THE|CACHE|BATCH_|TASK_|DUAL|T_Z|TABLA|T_TEST|T_TXT|^AB\|' }).Count -eq 0) ($t -join ',')
  $l = @($r.Salida -split "`n" | Where-Object { $_ -cmatch '^L\|' })[0]
  Igual 'la lista del motivo: 10 tablas con su sitio y las demas contadas' ('L|' + ((@(1..10 | ForEach-Object { 'T_' + $_.ToString('00') + " (x.java:$_)" }) -join ', ') + ' y 2 mas')) ($l.TrimEnd())
  Igual 'una carpeta sin src/main: ninguna' 'V|0' (@($r.Salida -split "`n" | Where-Object { $_ -cmatch '^V\|' })[0]).TrimEnd()
}

$Pruebas['m40 (a2) inventario: una tabla de una cadena de .java solo cuenta si la cadena lleva otra palabra de SQL o si el nombre va todo en mayusculas; los mensajes de log no dan tablas'] = {
  $raiz = Join-Path $Dir 'm40-inventario-log'
  Escribe $raiz 'src/main/java/com/acme/Logs.java' @'
package com.acme;

class Logs {
  void f(Object x) {
    log.error("Error reading from file {}", x);
    log.warn("Unable to update record");
    log.info("Updating from file " + x);
    String a = "select a from t_low where x = ?";
    String b = " FROM T_FRAG ";
    String c = "from file";
    String d = " JOIN esq.T_SCH ";
    String e = " into t_bajo ";
    String f = "order by x" + " from t_orden";
  }
}
'@
  $r = Inventario-M40 $raiz
  $t = @($r.Salida -split "`n" | Where-Object { $_ -cmatch '^T\|' } | ForEach-Object { $_.TrimEnd().Substring(2) })
  $c = 'src/main/java/com/acme/Logs.java'
  Igual 'solo las de SQL: la de select ... where en minusculas, las de nombre en mayusculas (con su esquema en minusculas) y ninguna de los mensajes' "T_FRAG|${c}:9,T_LOW|${c}:8,T_SCH|${c}:11" ($t -join ',')
}

$Pruebas['m40 (b) arnes nuevo cuyo caso vacio no deja la tabla del codigo: el primer intento se rechaza con la tabla y su sitio; el segundo, que la deja, se acepta'] = {
  $e = Escenario-M40 'm40-b' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba-M40 $e 'tablas=2/T_A:arnes-original;tablas=1/T_A:arnes-migrado'
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'dos llamadas al arnes del original' 2 (Llamadas-Arnes $e 'original').Count
  $p = Registro-Arnes $e 'original' 2
  Comprueba 'el prompt del reintento lleva el motivo con la tabla y su fichero:linea' ($p.Contains("La base de prueba no tiene estas tablas que usa el batch: T_A ($SitioTablaM40). Crealas en el paso de la base limpia con las columnas que usa el codigo.")) (Cola $p)
  Comprueba 'la consola dice que lo rechaza' ($r.Salida -match 'Arnes del original rechazado: La base de prueba no tiene estas tablas que usa el batch: T_A') (Cola $r.Salida)
  Comprueba 'y no avisa de que siga sin ellas' ($r.Salida -notmatch 'sigue sin estas tablas') (Cola $r.Salida)
  $t = Tarea-Arnes $e 'original'
  Igual 'la tarea queda hecha con dos intentos' 'hecha,2' "$($t.estado),$($t.intentos)"
  Comprueba 'el test guardado es el del segundo intento (con la tabla)' ((Lee $e.Local 'arnes/original/src/test/java/com/acme/viejo/PruebaLocalTest.java').Contains('BASE_TABLAS=T_A')) ''
  Comprueba 'y su caso vacio guardado lleva la tabla' (Test-Path -LiteralPath (Get-Ruta $e.Local 'salidas/vacio/cargaJob/tablas/T_A.csv')) ''
  Igual 'el arnes del migrado (sin tablas en su codigo) no se rechaza: una llamada' 1 (Llamadas-Arnes $e 'migrado').Count
}

$Pruebas['m40 (c, d) sin la tabla en todos los intentos el arnes se acepta con el Aviso; el guardado la ultima vez se usa con el mismo Aviso y sin llamada nueva al arnes'] = {
  $e = Escenario-M40 'm40-c' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $aviso = "La base de prueba sigue sin estas tablas: T_A ($SitioTablaM40). Los casos que las usen saldran FAILED en el original."
  $r = Prueba-M40 $e 'tablas=9/T_A:arnes-original'
  Igual '(c) sale con 0' 0 $r.Codigo
  Igual '(c) dos llamadas al arnes del original' 2 (Llamadas-Arnes $e 'original').Count
  Comprueba '(c) el primer intento se rechaza' ($r.Salida -match 'Arnes del original rechazado: La base de prueba no tiene estas tablas') (Cola $r.Salida)
  Igual '(c) el Aviso, una vez' 1 ([regex]::Matches($r.Salida, [regex]::Escape($aviso))).Count
  Comprueba '(c) y despues, el arnes del original bien' ($r.Salida -match 'Arnes del original: bien\.') (Cola $r.Salida)
  $t = Tarea-Arnes $e 'original'
  Igual '(c) la tarea queda hecha con dos intentos' 'hecha,2' "$($t.estado),$($t.intentos)"
  Comprueba '(c) el test se guarda' (Test-Path -LiteralPath (Get-Ruta $e.Local 'arnes/original/src/test/java/com/acme/viejo/PruebaLocalTest.java')) ''
  Comprueba '(c) y su caso vacio, el que usa la comparacion' (Test-Path -LiteralPath (Get-Ruta $e.Local 'salidas/vacio/cargaJob/estado.txt')) ''
  $n = (Llamadas $e).Count
  $r = Prueba-M40 $e 'tablas=9/T_A:arnes-original'
  Igual '(d) el segundo lanzamiento sale con 0' 0 $r.Codigo
  Igual '(d) sin ninguna llamada nueva (ni de arnes ni de casos)' $n (Llamadas $e).Count
  Igual '(d) el Aviso, una vez' 1 ([regex]::Matches($r.Salida, [regex]::Escape($aviso))).Count
  Comprueba '(d) y no rechaza nada' ($r.Salida -notmatch 'rechazado') (Cola $r.Salida)
  Igual '(d) la tarea sigue hecha con sus dos intentos' 'hecha,2' "$((Tarea-Arnes $e 'original').estado),$((Tarea-Arnes $e 'original').intentos)"
  # (d2) Un arnes guardado que otro lanzamiento dio por bueno (Use-ArnesGuardado le deja 0 intentos), como uno escrito antes de m40, aun tiene
  # intentos: la puerta no lo rechaza igual, porque un arnes que ya sale todo igual no se rehace por esto.
  $f = Get-Ruta $e.Local 'tareas/arnes-original.json'
  $t = Lee-Json $f; $t.intentos = 0
  [System.IO.File]::WriteAllText($f, (ConvertTo-Json -InputObject $t -Depth 20))
  $n = (Llamadas $e).Count
  $r = Prueba-M40 $e 'tablas=9/T_A:arnes-original'
  Igual '(d2) con 0 intentos guardados sale con 0' 0 $r.Codigo
  Igual '(d2) sin ninguna llamada nueva' $n (Llamadas $e).Count
  Igual '(d2) el Aviso, una vez' 1 ([regex]::Matches($r.Salida, [regex]::Escape($aviso))).Count
  Comprueba '(d2) no dice que el test ya no vale' ($r.Salida -notmatch 'ya no vale') (Cola $r.Salida)
}

$Pruebas['m40 (e) un caso cuyo original da Tabla "T_A" no encontrada, con T_A en el inventario: no se pudo preparar con su motivo, sin reintento (una sola llamada)'] = {
  $e = Escenario-M40 'm40-e' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba-M40 $e 'tablas=9/T_A:arnes-original;falta-tabla=T_A:^cargaJob/caso-01'
  Igual 'sale con 0 (el otro caso sale igual)' 0 $r.Codigo
  $motivo = "La base de prueba no tiene la tabla T_A (el test no la crea; la usa $SitioTablaM40)."
  Igual 'el caso 1: una sola llamada' 1 @(Llamadas-Casos $e | Where-Object { $_.id -eq 'caso-cargaJob-01' }).Count
  Igual 'el caso 2: una sola llamada' 1 @(Llamadas-Casos $e | Where-Object { $_.id -eq 'caso-cargaJob-02' }).Count
  $t = Tarea-Caso-M40 $e 'cargaJob' '01'
  Igual 'la tarea del caso 1 queda atascada con un intento' 'atascada,1' "$($t.estado),$($t.intentos)"
  Igual 'con ese motivo' $motivo $t.motivo
  $c = Caso $e 'cargaJob' 'caso-01'
  Igual 'el resultado: no se pudo preparar' 'no se pudo preparar' $c.resultado
  Comprueba 'con el motivo' ($c.motivo.Contains($motivo)) $c.motivo
  Comprueba 'la consola lo dice' ($r.Salida -match [regex]::Escape("caso-cargaJob-01 rechazado: $motivo")) (Cola $r.Salida)
  Igual 'el caso 2 sale igual' 'igual' (Caso $e 'cargaJob' 'caso-02').resultado
}

$Pruebas['m40 (e2) Tabla "X" no encontrada con X que no usa el codigo: el reintento dice que no existe en el batch y el caso se hace'] = {
  $e = Escenario-M40 'm40-e2' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M40 $e 'tablas=1/T_A:arnes-original;falta-tabla=T_INVENTADA:^cargaJob/caso-01'
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'dos llamadas para el caso' 2 @(Llamadas-Casos $e).Count
  Comprueba 'el reintento lleva que la tabla no existe en el batch' ((Registro-Caso-M40 $e 'cargaJob' '01' 2).Contains('La tabla T_INVENTADA no existe en el batch: usa solo tablas que use su codigo.')) ''
  $t = Tarea-Caso-M40 $e 'cargaJob' '01'
  Igual 'la tarea queda hecha con dos intentos' 'hecha,2' "$($t.estado),$($t.intentos)"
  Igual 'el caso sale igual' 'igual' (Caso $e 'cargaJob' 'caso-01').resultado
}

$Pruebas['m40 (f) Columna "X" no encontrada en T_A: el reintento lleva las columnas de T_A en la base de prueba; sin su .csv, solo la primera frase'] = {
  $e = Escenario-M40 'm40-f' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M40 $e 'tablas=1/T_A:arnes-original;falta-columna=T_A.X:^cargaJob/caso-01'
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'dos llamadas para el caso' 2 @(Llamadas-Casos $e).Count
  Comprueba 'el reintento lleva la tabla, la columna y las columnas de la base de prueba' ((Registro-Caso-M40 $e 'cargaJob' '01' 2).Contains('La tabla T_A no tiene la columna X. Sus columnas en la base de prueba son: ID, NOMBRE.')) (Cola (Registro-Caso-M40 $e 'cargaJob' '01' 2))
  Igual 'el caso sale igual' 'igual' (Caso $e 'cargaJob' 'caso-01').resultado
  $e = Escenario-M40 'm40-f2' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M40 $e 'tablas=9/T_A:arnes-original;falta-columna=T_A.X:^cargaJob/caso-01'
  $p = Registro-Caso-M40 $e 'cargaJob' '01' 2
  Comprueba 'sin el .csv de la tabla, solo la primera frase' ($p.Contains('La tabla T_A no tiene la columna X.') -and -not $p.Contains('Sus columnas')) (Cola $p)
}

$Pruebas['m40 (g) un caso que el migrado no corrio (sin estado.txt) sale distinto y su motivo dice que no lo corrio y por que'] = {
  $e = Escenario-M40 'm40-g' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba-M40 $e 'tablas=1/T_A:arnes-original;migrado-no-corre:^cargaJob/caso-01'
  Igual 'sale con 2' 2 $r.Codigo
  $c = Caso $e 'cargaJob' 'caso-01'
  Igual 'el caso 1 sale distinto' 'distinto' $c.resultado
  Comprueba 'con el motivo de que el migrado no lo corrio' ($c.motivo.StartsWith('El migrado no corrio este caso: ')) $c.motivo
  Comprueba 'y la causa de Maven' ($c.motivo.Contains('El job del migrado no arranca')) $c.motivo
  Comprueba 'las diferencias siguen: el estado.txt del original' (@($c.diferencias | Where-Object { $_.fichero -eq 'estado.txt' }).Count -eq 1) ''
  Comprueba 'la consola ensena el motivo antes de las diferencias' ($r.Salida -match '(?s)distinto: cargaJob/caso-01.*?El migrado no corrio este caso:.*?estado\.txt: lineas distintas') (Cola $r.Salida)
  $c2 = Caso $e 'cargaJob' 'caso-02'
  Igual 'el caso 2 sale igual y sin motivo' 'igual|' "$($c2.resultado)|$($c2.motivo)"
}

# ===================== M43: LA CLAVE DE REPARAR SIGUE AL CODIGO DEL MIGRADO, NO AL COMMIT =====================
# El id de la tarea de reparar lleva el arbol de src/main y el pom.xml del migrado, no su HEAD: un commit que solo toca src/test (la
# regresion, la cobertura) no hace volver a probar una clave que salio 'no se arregla'. Una tarea con el id de antes (con el HEAD) vale si
# el HEAD es el mismo.

function Hash8-M43([string]$Texto) {
  $sha = [System.Security.Cryptography.SHA1]::Create()
  try { $b = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Texto)) } finally { $sha.Dispose() }
  return ((@($b[0..3]) | ForEach-Object { $_.ToString('x2') }) -join '')
}

# Las tareas de reparar guardadas en prueba-local\tareas.
function Tareas-Reparar-M43($E) {
  $d = Get-Ruta $E.Local 'tareas'
  if (-not (Test-Path -LiteralPath $d)) { return @() }
  return @(Get-ChildItem -LiteralPath $d -File -Filter 'reparar-*.json' | Sort-Object Name | ForEach-Object { Lee-Json $_.FullName })
}

# El escenario de reparar con una primera pasada en la que la IA dice que no se arregla (una llamada, el caso sigue distinto).
function M43-No-Se-Arregla([string]$Nombre) {
  $e = Escenario-M25 $Nombre ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') })
  $r = Prueba $e @('-Reparar') 'reparar-no'
  Igual 'la primera vez sale con 2 (el caso sigue distinto)' 2 $r.Codigo
  Igual 'con una llamada de reparar' 1 (Llamadas-Reparar $e).Count
  return $e
}

$Pruebas['m43 (e) -Reparar: una clave que salio no se arregla no se vuelve a probar tras un commit que solo toca src/test en la rama de rescate'] = {
  $e = M43-No-Se-Arregla 'm43-e'
  $t0 = @(Tareas-Reparar-M43 $e)
  Igual 'hay una tarea de reparar, atascada' 'atascada' $t0[0].estado
  [void](Commit-En $e.Wt 'src/test/java/com/acme/nuevo/RegresionNuevaTest.java' "package com.acme.nuevo;`nclass RegresionNuevaTest {}`n" 'test de regresion')
  [void](Commit-En $e.Wt 'src/test/resources/prueba-local-esperado/cargaJob/caso-01/salida.txt' "esperado`n" 'esperado de la regresion')
  $r = Prueba $e @('-Reparar') 'reparar-arregla'
  Igual 'al relanzar sale con 2' 2 $r.Codigo
  Igual 'ninguna llamada nueva a reparar' 1 (Llamadas-Reparar $e).Count
  Comprueba 'la consola dice por que no se arregla, con el motivo de la IA' ($r.Salida -match 'simula el correo') (Cola $r.Salida)
  $t1 = @(Tareas-Reparar-M43 $e)
  Igual 'sigue siendo una sola tarea, con el mismo id' $t0[0].id (($t1 | ForEach-Object { $_.id }) -join ',')
  $rep = @(Reparaciones $e)
  Igual 'reparaciones sigue con la clave no se arregla' 'no se arregla' $rep[0].resultado
}

$Pruebas['m43 (f) -Reparar: el mismo commit pero en src/main cambia el id: la clave que salio no se arregla se vuelve a probar'] = {
  $e = M43-No-Se-Arregla 'm43-f'
  $t0 = @(Tareas-Reparar-M43 $e)
  [void](Commit-En $e.Wt 'src/main/resources/otra-regla.txt' "otra=1`n" 'otro cambio del migrado')
  $r = Prueba $e @('-Reparar') 'reparar-no'
  Igual 'al relanzar sale con 2' 2 $r.Codigo
  Igual 'una llamada mas a reparar' 2 (Llamadas-Reparar $e).Count
  $t1 = @(Tareas-Reparar-M43 $e)
  Igual 'hay dos tareas, con ids distintos' 2 $t1.Count
  Comprueba 'y la de antes sigue guardada' (@($t1 | Where-Object { $_.id -ceq $t0[0].id }).Count -eq 1) (($t1 | ForEach-Object { $_.id }) -join ',')
  [void](Commit-En $e.Wt 'pom.xml' ((Lee $e.Wt 'pom.xml') + "<!-- m43 -->`n") 'cambia el pom')
  $r = Prueba $e @('-Reparar') 'reparar-no'
  Igual 'un commit que cambia el pom.xml tambien cambia el id: otra llamada' 3 (Llamadas-Reparar $e).Count
}

# Cambia la tarea de reparar guardada al id que tenia antes de M43 (el HEAD en vez del codigo) y le pone $Huella (la de la plantilla de ahora si
# no se da). Devuelve la tarea como era, con su id de ahora en idNuevo.
function M43-Tarea-Vieja($E, [string]$Huella = '') {
  $t = @(Tareas-Reparar-M43 $E)[0]
  $idNuevo = $t.id
  $head = GitEn $E.Wt @('rev-parse', 'HEAD')
  $hashArnes = Hash8-M43 (Lee $E.Local ('arnes/migrado/' + (Tarea-Arnes $E 'migrado').entradas.test))
  $viejo = 'reparar-' + (Hash8-M43 "$head|$($t.entradas.job)|$($t.entradas.caso)|$($t.entradas.clave)|$hashArnes")
  Comprueba 'el id de antes no es el de ahora' ($viejo -cne $idNuevo) $viejo
  if (-not $Huella) { $Huella = Hash8-M43 (([System.IO.File]::ReadAllText((Join-Path (Split-Path -Parent $Script) 'tareas/reparar.md')) -replace "`r`n", "`n") + '|' + $viejo) }
  Remove-Item -LiteralPath (Get-Ruta $E.Local ('tareas/' + $idNuevo + '.json'))
  $t.id = $viejo
  $t.salida = "prueba-local/reparar/$viejo"
  $t.entradas.huella = $Huella
  [System.IO.File]::WriteAllText((Get-Ruta $E.Local ('tareas/' + $viejo + '.json')), (ConvertTo-Json -InputObject $t -Depth 8))
  return [pscustomobject]@{ IdNuevo = $idNuevo; Tarea = $t }
}

$Pruebas['m43 (g) -Reparar: una tarea guardada con el id de antes (con el HEAD) y el mismo HEAD: se usa su veredicto sin llamar, y queda con el id nuevo'] = {
  $e = M43-No-Se-Arregla 'm43-g'
  $v = M43-Tarea-Vieja $e
  $r = Prueba $e @('-Reparar') 'reparar-arregla'
  Igual 'sale con 2: el veredicto es el de antes' 2 $r.Codigo
  Igual 'ninguna llamada nueva a reparar' 1 (Llamadas-Reparar $e).Count
  $nuevo = Get-Ruta $e.Local ('tareas/' + $v.IdNuevo + '.json')
  Comprueba 'la tarea queda guardada con el id nuevo' (Test-Path -LiteralPath $nuevo) $nuevo
  if (Test-Path -LiteralPath $nuevo) {
    $n = Lee-Json $nuevo
    Igual 'atascada, con el veredicto de antes' 'atascada|no se arregla' "$($n.estado)|$($n.ultimoEstado)"
    Igual 'y el motivo de antes' $v.Tarea.motivo $n.motivo
  }
  $rep = @(Reparaciones $e)
  Igual 'reparaciones dice no se arregla' 'no se arregla' $rep[0].resultado
}

$Pruebas['m43 (g2) -Reparar: la tarea con el id de antes pero hecha con otra plantilla (otra huella) no vale: la clave se vuelve a probar'] = {
  $e = M43-No-Se-Arregla 'm43-g2'
  $v = M43-Tarea-Vieja $e 'plantilla-vieja'
  $r = Prueba $e @('-Reparar') 'reparar-no'
  Igual 'sale con 2' 2 $r.Codigo
  Igual 'una llamada mas a reparar' 2 (Llamadas-Reparar $e).Count
}

# ===================== M47: el original no se ejecuta otra vez si no ha cambiado nada de lo que entra en su ejecucion =====================
# El original y el original-2 de cada caso se guardan en salidas\ con una clave (HEAD del original, su arnes, las entradas del caso, el JDK,
# Maven y sus ajustes) y los dias de su ejecucion (salidas\originales.json). Un relanzamiento con la misma clave los reutiliza; el migrado
# se ejecuta siempre. mvn.log (RESCATE_LLAMADAS) apunta cada Maven: aqui se cuentan los del original.

# Los Maven de casos hechos en la copia del original ($Job y $Caso son regex: por defecto, todos).
function Orig-Mvn($E, [string]$Job = '[^ ]+', [string]$Caso = 'caso-\d+') {
  return @(Mavens-Con $E ('^' + [regex]::Escape($E.CopiaOrig + '|') + '.* -Dprueba\.local\.job=' + $Job + ' -Dprueba\.local\.caso=' + $Caso + '( |$)')).Count
}

# Los Maven de casos hechos en la copia del migrado.
function Mig-Mvn($E) { return @(Mavens-Con $E ('^' + [regex]::Escape($E.CopiaMig + '|') + '.* -Dprueba\.local\.caso=caso-')).Count }

# Deja lo guardado del original (original y original-2) como si se hubiera ejecutado hace $Dias dias: el nombre y la fecha de hoy de sus ficheros
# pasan a ser los de ese dia y la ventana de salidas\originales.json, solo ese dia.
function Envejece-M47($E, [int]$Dias) {
  $inv = [System.Globalization.CultureInfo]::InvariantCulture
  $lat = [System.Text.Encoding]::GetEncoding(28591)
  $hoy = Get-Date
  $antes = $hoy.AddDays(-$Dias)
  foreach ($n in @('original', 'original-2')) {
    foreach ($f in @(Get-ChildItem -LiteralPath (Get-Ruta $E.Local "salidas/$n") -Recurse -File -Filter 'resultado_*.txt')) {
      [System.IO.File]::WriteAllText($f.FullName, ([System.IO.File]::ReadAllText($f.FullName, $lat).Replace($hoy.ToString('dd/MM/yyyy', $inv), $antes.ToString('dd/MM/yyyy', $inv))), $lat)
      Rename-Item -LiteralPath $f.FullName -NewName $f.Name.Replace($hoy.ToString('yyyyMMdd', $inv), $antes.ToString('yyyyMMdd', $inv))
    }
  }
  $j = Get-Ruta $E.Local 'salidas/originales.json'
  $o = Lee-Json $j
  foreach ($c in @($o.casos)) { $c.dias = @($antes.ToString('yyyy-MM-dd', $inv)) }
  [System.IO.File]::WriteAllText($j, (ConvertTo-Json -InputObject $o -Depth 6))
}

$Pruebas['m47 (a) relanzar sin cambiar nada: ni el original ni el original-2 se ejecutan, el migrado si, y los resultados son los mismos'] = {
  $e = Nuevo-Escenario 'm47-a' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=5.00'); remesaJob = @('importe=40.00') }) 'minimo=5.00' 'minimo=5.01'
  $r = Prueba $e
  Igual 'el primer lanzamiento sale con 2 (el caso del limite sale distinto)' 2 $r.Codigo
  Comprueba 'dice que ejecuta los 3 casos y no reutiliza ninguno' ($r.Salida -match 'Original: se reutilizan las salidas de 0 caso\(s\) y se ejecutan 3\.') (Cola $r.Salida)
  Comprueba 'las salidas guardadas llevan su clave y sus dias en originales.json' (@((Lee-Json (Get-Ruta $e.Local 'salidas/originales.json')).casos).Count -eq 3) ''
  $o1 = Orig-Mvn $e
  $m1 = Mig-Mvn $e
  $antes = (Resultados $e) -join ','
  $r = Prueba $e
  Igual 'el relanzamiento sale con 2' 2 $r.Codigo
  Igual 'ninguna ejecucion mas del original ni del original-2' $o1 (Orig-Mvn $e)
  Igual 'el migrado, una mas por caso' ($m1 + 3) (Mig-Mvn $e)
  Igual 'los mismos resultados' $antes ((Resultados $e) -join ',')
  Comprueba 'la consola lo dice en una linea: 3 reutilizados y 0 ejecutados' ($r.Salida -match 'Original: se reutilizan las salidas de 3 caso\(s\) y se ejecutan 0\.') (Cola $r.Salida)
  Igual 'el distinto sigue con sus lineas' 'importe=5.00 -> aceptado|importe=5.00 -> rechazado' ((@((Caso $e 'cargaJob' 'caso-02').diferencias)[0] | ForEach-Object { "$($_.original)|$($_.migrado)" }))
}

$Pruebas['m47 (b) un commit en el original: sus casos se ejecutan otra vez y el resultado es el nuevo'] = {
  $e = Nuevo-Escenario 'm47-b' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba $e
  Igual 'el primero sale con 0' 0 $r.Codigo
  $o1 = Orig-Mvn $e
  [void](Commit-En $e.Legacy 'regla.txt' "minimo=15.00`n" 'sube el minimo del original')
  $r = Prueba $e
  Igual 'sale con 2 (el original ahora rechaza el importe de 10)' 2 $r.Codigo
  Comprueba 'el original y el original-2 de los dos casos se ejecutan otra vez' ((Orig-Mvn $e) -ge ($o1 + 4)) "antes $o1, ahora $(Orig-Mvn $e)"
  Igual 'caso-01 distinto y caso-02 igual' 'distinto,igual' ((Resultados $e) -join ',')
  Comprueba 'la consola dice 0 reutilizados' ($r.Salida -match 'Original: se reutilizan las salidas de 0 caso\(s\) y se ejecutan 2\.') (Cola $r.Salida)
}

$Pruebas['m47 (c) otro arnes del original: se ejecuta otra vez; -RehacerArnes (que solo rehace el del migrado): no'] = {
  $e = Nuevo-Escenario 'm47-c' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  [void](Prueba $e)
  $o1 = Orig-Mvn $e
  $r = Prueba $e @('-RehacerArnes')
  Igual 'con -RehacerArnes sale con 0' 0 $r.Codigo
  Igual 'el original no se ejecuta otra vez (su arnes no cambia)' $o1 (Orig-Mvn $e)
  $t = 'arnes/original/src/test/java/com/acme/viejo/PruebaLocalTest.java'
  Escribe $e.Local $t ((Lee $e.Local $t) + "// otro arnes`n")
  $r = Prueba $e
  Igual 'con otro test del original sale con 0' 0 $r.Codigo
  Igual 'sus dos casos se ejecutan otra vez, el original y el original-2' ($o1 + 4) (Orig-Mvn $e)
  Comprueba 'la consola lo dice' ($r.Salida -match 'Original: se reutilizan las salidas de 0 caso\(s\) y se ejecutan 2\.') (Cola $r.Salida)
  $o2 = Orig-Mvn $e
  [void](Prueba $e)
  Igual 'y al relanzar con ese arnes, otra vez nada' $o2 (Orig-Mvn $e)
}

$Pruebas['m47 (d) las entradas de un caso cambian: se ejecuta solo ese caso'] = {
  $e = Nuevo-Escenario 'm47-d' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00', 'importe=30.00') })
  [void](Prueba $e)
  $antes = @(1, 2, 3 | ForEach-Object { Orig-Mvn $e 'cargaJob' ('caso-0' + $_) })
  Escribe $e.Local 'casos/cargaJob/caso-02/ficheros/entrada/datos.txt' "importe=2.00`n"
  $r = Prueba $e
  Igual 'sale con 0 (las dos lados rechazan el 2.00)' 0 $r.Codigo
  Igual 'caso-01 y caso-03 no se ejecutan; caso-02, el original y el original-2' ((@($antes[0], ($antes[1] + 2), $antes[2])) -join ',') ((@(1, 2, 3 | ForEach-Object { Orig-Mvn $e 'cargaJob' ('caso-0' + $_) })) -join ',')
  Igual 'los tres salen iguales (el original de caso-02 es el de las entradas nuevas)' 'igual,igual,igual' ((Resultados $e) -join ',')
  Comprueba 'la consola dice 2 reutilizados y 1 ejecutado' ($r.Salida -match 'Original: se reutilizan las salidas de 2 caso\(s\) y se ejecutan 1\.') (Cola $r.Salida)
  Comprueba 'la salida guardada de caso-02 es la nueva' ((Lee $e.Local ('salidas/original/cargaJob/caso-02/ficheros/salida/resultado_' + (Hoy) + '.txt')) -match 'importe=2\.00 -> rechazado') ''
}

$Pruebas['m47 (e) fechas: el original de hace dias sale igual que el migrado de hoy con el mismo dato; una fecha de negocio distinta sigue saliendo distinta'] = {
  $e = Nuevo-Escenario 'm47-e' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=10.00 vence=1980-05-12 00:00:00') }) 'minimo=5.00' "minimo=5.00`nreescribe=1980-05-12 00:00:00=>1980-05-11 23:00:00"
  Ajustes-M20b $e
  $r = Prueba $e
  Igual 'el primer lanzamiento sale con 2 (la fecha de negocio cambia en el migrado)' 2 $r.Codigo
  Envejece-M47 $e 3
  $rel = 'cargaJob/caso-01/ficheros/salida/resultado_' + (Get-Date).AddDays(-3).ToString('yyyyMMdd') + '.txt'
  Comprueba 'el original guardado lleva la fecha de hace tres dias en su nombre y en su texto' ((Lee $e.Local "salidas/original/$rel") -match ('hecho el ' + (Get-Date).AddDays(-3).ToString('dd/MM/yyyy'))) ''
  $o1 = @(Orig-Mvn $e 'cargaJob' 'caso-01'; Orig-Mvn $e 'cargaJob' 'caso-02')
  $r = Prueba $e
  Igual 'el relanzamiento sale con 2' 2 $r.Codigo
  Igual 'el original de hace tres dias (su fecha y la de hoy con el mismo dato) sale igual' 'igual' (Caso $e 'cargaJob' 'caso-01').resultado
  Igual 'y no se ha ejecutado otra vez' $o1[0] (Orig-Mvn $e 'cargaJob' 'caso-01')
  $c = Caso $e 'cargaJob' 'caso-02'
  Igual 'la fecha de negocio que cambia sigue saliendo distinta' 'distinto' $c.resultado
  $d = @($c.diferencias)[0]
  Comprueba 'con la fecha de antes en el original' ("$($d.original)" -match '1980-05-12 00:00:00') "$($d.original)"
  Comprueba 'y la de despues en el migrado' ("$($d.migrado)" -match '1980-05-11 23:00:00') "$($d.migrado)"
}

$Pruebas['m47 (e2) fechas: un migrado que escribe la fecha de la ejecucion del original (no la de hoy) sale distinto, no igual'] = {
  $e = Nuevo-Escenario 'm47-e2' ([ordered]@{ cargaJob = @('importe=10.00') })
  [void](Prueba $e)
  Envejece-M47 $e 3
  [void](Commit-En $e.Wt 'regla.txt' "minimo=5.00`nsegundos=-259200`n" 'el migrado escribe la fecha de hace tres dias')
  $r = Prueba $e
  Igual 'sale con 2' 2 $r.Codigo
  Igual 'el caso sale distinto: la fecha de hace tres dias del migrado no es de la ejecucion de hoy' 'distinto' (Caso $e 'cargaJob' 'caso-01').resultado
  $d = @((Caso $e 'cargaJob' 'caso-01').diferencias)[0]
  Comprueba 'y la linea distinta es la de la fecha' ("$($d.migrado)" -match 'hecho el ' + (Get-Date).AddDays(-3).ToString('dd/MM/yyyy')) "$($d.migrado)"
}

$Pruebas['m47 (e3) Compare-Caso y Get-MotivoCambiante con los dias de cada lado: cada salida se normaliza con los dias de su ejecucion'] = {
  $f = Join-Path $Dir 'm47-comparar.ps1'
  $raizCmp = Join-Path $Dir 'm47-comparar'
  $cuerpo = @'
$Inv = [System.Globalization.CultureInfo]::InvariantCulture
$Utf8Estricto = New-Object System.Text.UTF8Encoding($false, $true)
$RutasCopia = @()
$d17 = @([datetime]'2026-11-17')
$d20 = @([datetime]'2026-11-20')
$Hoy = $d20
function Lado([string]$Id, [string]$Lado, [hashtable]$Ficheros) {
  $d = Join-Path (Join-Path $Raiz $Id) $Lado
  foreach ($k in $Ficheros.Keys) {
    $p = Join-Path $d $k
    [void](New-Item -ItemType Directory -Path (Split-Path $p -Parent) -Force)
    [System.IO.File]::WriteAllText($p, $Ficheros[$k])
  }
  return $d
}
function Caso([string]$Id, [hashtable]$A, [hashtable]$B, $DiasA = $null, $DiasB = $null) {
  $dirA = Lado $Id 'A' $A
  $dirB = Lado $Id 'B' $B
  if ($null -eq $DiasA) { 'R ' + $Id + ' ' + (@(Compare-Caso $dirA $dirB | ForEach-Object { $_.fichero }) -join ',') }
  else { 'R ' + $Id + ' ' + (@(Compare-Caso $dirA $dirB $DiasA $DiasB | ForEach-Object { $_.fichero }) -join ',') }
}
$n17 = 'ficheros/resultado_20261117.txt'
$n20 = 'ficheros/resultado_20261120.txt'
# el original se ejecuto el 17 y el migrado el 20, con el mismo dato
Caso 'misma-ventana' @{ $n17 = "fecha 17/11/2026 y 2026-11-17 10:00:00`n" } @{ $n20 = "fecha 20/11/2026 y 2026-11-20 11:30:00`n" } $d17 $d20
Caso 'sin-ventana' @{ $n17 = "fecha 17/11/2026`n" } @{ $n20 = "fecha 20/11/2026`n" }
Caso 'ventana-del-original-en-el-migrado' @{ $n17 = "fecha 17/11/2026`n" } @{ $n20 = "fecha 17/11/2026`n" } $d17 $d20
Caso 'ventana-de-hoy-en-el-original' @{ $n17 = "fecha 20/11/2026`n" } @{ $n20 = "fecha 20/11/2026`n" } $d17 $d20
Caso 'dato-de-negocio' @{ $n17 = "vence 2026-11-18 00:00:00`n" } @{ $n20 = "vence 2026-11-19 00:00:00`n" } $d17 $d20
Caso 'dato-de-negocio-igual' @{ $n17 = "vence 2026-11-18 00:00:00`n" } @{ $n20 = "vence 2026-11-18 00:00:00`n" } $d17 $d20
Caso 'nombre-con-otro-dia' @{ $n17 = "x`n" } @{ 'ficheros/resultado_20261119.txt' = "x`n" } $d17 $d20
$o = Join-Path $Raiz 'cambiante'
[void](New-Item -ItemType Directory -Path $o -Force)
[System.IO.File]::WriteAllText((Join-Path $o 'x.txt'), "fecha 2026-11-17`n")
'M dias-del-original [' + (Get-MotivoCambiante $o @('x.txt') $d17) + ']'
'M dias-de-hoy [' + (Get-MotivoCambiante $o @('x.txt')) + ']'
'@
  $comun = Join-Path (Split-Path -Parent $Script) 'comun.ps1'
  $regresion = Join-Path (Split-Path -Parent $Script) 'regresion.ps1'
  [System.IO.File]::WriteAllText($f, ('param([string]$Raiz)' + "`n" + (Texto-De-Funciones $Script (@('Compare-Caso', 'Compare-Fichero') + $FnLeer + @('Sort-Tabla', 'Resolve-ParTablas', 'Sort-Ordinal', 'Get-Normal', 'Get-Legible', 'Get-NotaJdk'))) + "`n" + (Texto-De-Funciones $comun @('Get-Rel', 'Join-Ruta')) + "`n" + (Texto-De-Funciones $regresion @('Get-MotivoCambiante')) + "`n" + '$Latin = [System.Text.Encoding]::GetEncoding(28591); $Utf8 = New-Object System.Text.UTF8Encoding($false)' + "`n" + $cuerpo))
  $r = Lanzar $f @($raizCmp)
  $v = @{}
  foreach ($l in @($r.Salida -split "`n")) {
    if ($l -cmatch '^R (\S+) ?(.*)$') { $v[$Matches[1]] = $Matches[2].TrimEnd() }
    if ($l -cmatch '^M (\S+) \[(.*)\]$') { $v['M-' + $Matches[1]] = $Matches[2] }
  }
  Igual 'cada salida con los dias de su ejecucion: el 17 del original y el 20 del migrado, igual' '' $v['misma-ventana']
  Comprueba 'sin dias por lado, con los de hoy en los dos, el 17 es un dato y sale distinto' ($v['sin-ventana'] -ne '') (Cola $r.Salida)
  Igual 'un migrado que escribe el 17 (no es de su ejecucion) sale distinto' 'ficheros/resultado_20261117.txt' $v['ventana-del-original-en-el-migrado']
  Igual 'un original que escribe el 20 (no es de su ejecucion) tambien' 'ficheros/resultado_20261117.txt' $v['ventana-de-hoy-en-el-original']
  Comprueba 'un dato de negocio con otra fecha sale distinto' ($v['dato-de-negocio'] -ne '') (Cola $r.Salida)
  Igual 'y el mismo dato de negocio, igual' '' $v['dato-de-negocio-igual']
  Comprueba 'un nombre con otro dia que el de la ejecucion sale distinto' ($v['nombre-con-otro-dia'] -ne '') (Cola $r.Salida)
  Comprueba 'una salida con una fecha de su ejecucion no vale como test fijo (Get-MotivoCambiante con los dias del original)' ($v['M-dias-del-original'] -match 'fecha de hoy') (Cola $r.Salida)
  Igual 'con los de hoy, esa fecha es un dato y vale' '' $v['M-dias-de-hoy']
}

$Pruebas['m47 (f) sin la carpeta de salidas de un caso (o de un original-2, o de todas): se ejecutan esos casos'] = {
  $e = Nuevo-Escenario 'm47-f' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00', 'importe=30.00') })
  [void](Prueba $e)
  $n = { @(1, 2, 3 | ForEach-Object { Orig-Mvn $e 'cargaJob' ('caso-0' + $_) }) -join ',' }
  $a = @(1, 2, 3 | ForEach-Object { Orig-Mvn $e 'cargaJob' ('caso-0' + $_) })
  Remove-Item -LiteralPath (Get-Ruta $e.Local 'salidas/original/cargaJob/caso-02') -Recurse -Force
  Remove-Item -LiteralPath (Get-Ruta $e.Local 'salidas/original-2/cargaJob/caso-03') -Recurse -Force
  $r = Prueba $e
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'caso-02 (sin original) y caso-03 (sin original-2) se ejecutan; caso-01 no' ((@($a[0], ($a[1] + 2), ($a[2] + 2))) -join ',') (& $n)
  Igual 'los tres iguales' 'igual,igual,igual' ((Resultados $e) -join ',')
  Comprueba 'la consola dice 1 reutilizado y 2 ejecutados' ($r.Salida -match 'Original: se reutilizan las salidas de 1 caso\(s\) y se ejecutan 2\.') (Cola $r.Salida)
  $a = @(1, 2, 3 | ForEach-Object { Orig-Mvn $e 'cargaJob' ('caso-0' + $_) })
  Remove-Item -LiteralPath (Get-Ruta $e.Local 'salidas') -Recurse -Force
  $r = Prueba $e
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'sin salidas\ se ejecutan los tres (borrar prueba-local\salidas repite el original)' ((@(($a[0] + 2), ($a[1] + 2), ($a[2] + 2))) -join ',') (& $n)
  Comprueba 'y originales.json vuelve a tener los tres' (@((Lee-Json (Get-Ruta $e.Local 'salidas/originales.json')).casos).Count -eq 3) ''
}

$Pruebas['m47 (g) otro JDK (-JavaLegacy o su fichero release), otro ajuste de Maven (variables de entorno, MavenCasoRapido): se ejecuta otra vez; lo mismo, no'] = {
  $e = Nuevo-Escenario 'm47-g' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $jdk = Join-Path $e.Raiz 'jdk-viejo'
  Escribe $jdk 'release' "JAVA_VERSION=`"1.8.0_392`"`n"
  [void](Prueba $e)
  $o = Orig-Mvn $e
  [void](Prueba $e @('-JavaLegacy', $jdk))
  Igual 'con -JavaLegacy, otro JDK: se ejecutan los dos casos' ($o + 4) (Orig-Mvn $e)
  $o = Orig-Mvn $e
  [void](Prueba $e @('-JavaLegacy', $jdk))
  Igual 'con el mismo -JavaLegacy, ninguno' $o (Orig-Mvn $e)
  Escribe $jdk 'release' "JAVA_VERSION=`"1.8.0_402`"`n"
  [void](Prueba $e @('-JavaLegacy', $jdk))
  Igual 'la misma carpeta con otra version en su release: se ejecutan' ($o + 4) (Orig-Mvn $e)
  $o = Orig-Mvn $e
  $antes = $env:MAVEN_OPTS
  $env:MAVEN_OPTS = '-Duser.timezone=UTC'
  try {
    [void](Prueba $e @('-JavaLegacy', $jdk))
    Igual 'otro MAVEN_OPTS: se ejecutan' ($o + 4) (Orig-Mvn $e)
    $o = Orig-Mvn $e
    [void](Prueba $e @('-JavaLegacy', $jdk))
    Igual 'el mismo MAVEN_OPTS: ninguno' $o (Orig-Mvn $e)
  }
  finally { $env:MAVEN_OPTS = $antes }
  [void](Prueba $e @('-JavaLegacy', $jdk))   # sin MAVEN_OPTS otra vez: es otra clave, y de aqui en adelante solo cambia MavenCasoRapido
  $aj = [ordered]@{ CopilotExe = (Join-Path $falsos 'copilot-local.ps1'); MvnExe = (Join-Path $falsos 'mvn-local.ps1'); SegundosPorLlamada = 60; MavenCasoRapido = @('-Dm47.skip') }
  Escribe $e.Home 'ajustes.json' (ConvertTo-Json -InputObject $aj)
  $o = Orig-Mvn $e
  [void](Prueba $e @('-JavaLegacy', $jdk))
  Igual 'otra lista de MavenCasoRapido: se ejecutan' ($o + 4) (Orig-Mvn $e)
}

$Pruebas['m47 (g2) otra version de Java o de Maven en lo que dice mvn -v: se ejecuta otra vez; la misma, no'] = {
  $e = Nuevo-Escenario 'm47-g2' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $aj = [ordered]@{ CopilotExe = (Join-Path $falsos 'copilot-local.ps1'); MvnExe = (Join-Path $falsos 'm47-mvn.ps1'); SegundosPorLlamada = 60 }
  Escribe $e.Home 'ajustes.json' (ConvertTo-Json -InputObject $aj)
  $antes = $env:M47_JAVA
  try {
    $env:M47_JAVA = '1.8.0_392'
    [void](Prueba $e)
    $o = Orig-Mvn $e
    [void](Prueba $e)
    Igual 'la misma version: ninguno' $o (Orig-Mvn $e)
    $env:M47_JAVA = '1.8.0_402'
    $r = Prueba $e
    Igual 'otra version de Java: se ejecutan los dos casos' ($o + 4) (Orig-Mvn $e)
    Comprueba 'la consola dice 0 reutilizados' ($r.Salida -match 'Original: se reutilizan las salidas de 0 caso\(s\) y se ejecutan 2\.') (Cola $r.Salida)
  }
  finally { $env:M47_JAVA = $antes }
}

$Pruebas['m47 (h) un original de otro dia que sale distinto se ejecuta otra vez para confirmarlo; uno de hoy no'] = {
  $e = Nuevo-Escenario 'm47-h' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  [void](Prueba $e)
  # el original guardado de caso-01 dice otra cosa (lo que dejaria uno viejo con algo que la clave no ve): original y original-2 de acuerdo
  foreach ($n in @('original', 'original-2')) {
    $f = "salidas/$n/cargaJob/caso-01/ficheros/salida/resultado_$(Hoy).txt"
    Escribe $e.Local $f ((Lee $e.Local $f).Replace('importe=10.00 -> aceptado', 'importe=10.00 -> rechazado'))
  }
  $a = @(Orig-Mvn $e 'cargaJob' 'caso-01'; Orig-Mvn $e 'cargaJob' 'caso-02')
  $r = Prueba $e
  Igual 'con el original de hoy sale con 2 (distinto)' 2 $r.Codigo
  Igual 'caso-01 distinto: el de hoy no se confirma' 'distinto,igual' ((Resultados $e) -join ',')
  Igual 'y no se ejecuta ninguno' ($a[0] + $a[1]) ((Orig-Mvn $e 'cargaJob' 'caso-01') + (Orig-Mvn $e 'cargaJob' 'caso-02'))
  Envejece-M47 $e 2
  $r = Prueba $e
  Igual 'con el original de hace dos dias, el distinto se confirma y sale con 0' 0 $r.Codigo
  Igual 'los dos iguales' 'igual,igual' ((Resultados $e) -join ',')
  Igual 'caso-01 se ejecuta otra vez en el original (original y original-2); caso-02, no' ((@(($a[0] + 2), $a[1])) -join ',') ((@((Orig-Mvn $e 'cargaJob' 'caso-01'), (Orig-Mvn $e 'cargaJob' 'caso-02'))) -join ',')
  Comprueba 'la consola lo dice' ($r.Salida -match 'Original de otro dia: 1 caso\(s\) sale\(n\) distinto\(s\); los ejecuto otra vez para confirmarlo\.') (Cola $r.Salida)
  $dias = @((Lee-Json (Get-Ruta $e.Local 'salidas/originales.json')).casos | Where-Object { $_.caso -eq 'caso-01' })[0].dias
  Igual 'y su ventana guardada es la de hoy' ((Get-Date).ToString('yyyy-MM-dd')) (@($dias)[0])
}

$Pruebas['m47 (i) un caso hecho cuyo original dejo EXCEPCION vuelve a pendiente y su original se ejecuta otra vez aunque las entradas sean las mismas'] = {
  $e = Escenario-M36 'm47-i' ([ordered]@{ cargaJob = @('importe=10.00'); remesaJob = @('importe=10.00') })
  [void](Prueba-M36 $e '')
  Escribe $e.Local 'salidas/original/cargaJob/caso-01/estado.txt' "estado=EXCEPCION`nsalida=IllegalStateException`n"
  $a = @(Orig-Mvn $e 'cargaJob'; Orig-Mvn $e 'remesaJob')
  $r = Prueba-M36 $e 'excepcion:^cargaJob/'
  Comprueba 'la Info dice que se rehace 1 caso' ($r.Salida -match 'Se rehacen 1 caso') (Cola $r.Salida)
  Igual 'cargaJob: el original se ejecuta otra vez (en la preparacion, el original y el original-2); remesaJob, no' ((@(($a[0] + 3), $a[1])) -join ',') ((@((Orig-Mvn $e 'cargaJob'), (Orig-Mvn $e 'remesaJob'))) -join ',')
  Comprueba 'la salida guardada es la nueva' ((Lee $e.Local 'salidas/original/cargaJob/caso-01/estado.txt') -match 'salida=') ''
}

$Pruebas['m47 (k) un original que deja su estado.txt pero se pasa del tope de Maven no queda guardado para reutilizar'] = {
  $e = Nuevo-Escenario 'm47-k' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $env:RESCATE_MVN_ESCRIBE = '1'
  try { $r = Prueba-Con-Tope $e ([regex]::Escape($e.CopiaOrig) + '\|.*-Dprueba\.local\.caso=caso-01( |$)') }
  finally { $env:RESCATE_MVN_ESCRIBE = '' }
  Comprueba 'el original de caso-01 dejo su estado.txt antes de colgarse' (Test-Path -LiteralPath (Get-Ruta $e.Local 'salidas/original/cargaJob/caso-01/estado.txt')) ''
  $guardados = @(@((Lee-Json (Get-Ruta $e.Local 'salidas/originales.json')).casos) | ForEach-Object { "$($_.job)|$($_.caso)" })
  Comprueba 'caso-01 no queda en originales.json' ($guardados -notcontains 'cargaJob|caso-01') ($guardados -join ', ')
  Comprueba 'caso-02 si' ($guardados -contains 'cargaJob|caso-02') ($guardados -join ', ')
  Comprueba-Tope $r.Pids $r.Segundos 90 (Registro-Del-Tope "$((Caso $e 'cargaJob' 'caso-01').motivo)")
}

$Pruebas['m47 (j) con -Job las salidas de los otros jobs se quedan, y el siguiente lanzamiento sin -Job las reutiliza'] = {
  $e = Nuevo-Escenario 'm47-j' ([ordered]@{ cargaJob = @('importe=10.00'); remesaJob = @('importe=20.00') })
  [void](Prueba $e)
  $a = @(Orig-Mvn $e 'cargaJob'; Orig-Mvn $e 'remesaJob')
  $r = Prueba $e @('-Job', 'cargaJob')
  Igual 'con -Job sale con 0' 0 $r.Codigo
  Igual 'no ejecuta el original de nadie' ((@($a[0], $a[1])) -join ',') ((@((Orig-Mvn $e 'cargaJob'), (Orig-Mvn $e 'remesaJob'))) -join ',')
  Comprueba 'las salidas del otro job siguen en salidas\original' (Test-Path -LiteralPath (Get-Ruta $e.Local 'salidas/original/remesaJob/caso-01/estado.txt')) ''
  Comprueba 'y su clave en originales.json' (@((Lee-Json (Get-Ruta $e.Local 'salidas/originales.json')).casos).Count -eq 2) ''
  $r = Prueba $e
  Igual 'sin -Job sale con 0' 0 $r.Codigo
  Igual 'tampoco ejecuta el original' ((@($a[0], $a[1])) -join ',') ((@((Orig-Mvn $e 'cargaJob'), (Orig-Mvn $e 'remesaJob'))) -join ',')
}

# ===================== M48: un fichero largo no tumba la prueba, un caso que falla dice por que y un test del migrado roto no se acepta =====================
# m48-mvn.ps1 (sobre m33-mvn.ps1) deja, segun el guion de RESCATE_M48 ('guion:regex sobre job/caso', separados por ';'): ficheros de nombre largo
# (M48_LARGO letras), un fichero que no cabe ni con nombre corto, un migrado FAILED o EXCEPCION (con su 'Caused by:' en la salida de Maven), un original
# EXCEPCION, el caso vacio del migrado EXCEPCION (las primeras M48_VACIOS veces) y un fichero donde va una carpeta (M48_OBSTACULO).

# Un escenario con el Copilot de m25 y el Maven de m48; $Mas son otras claves de ajustes.json.
function Escenario-M48([string]$Nombre, $Casos, [hashtable]$Mas = @{}) {
  $aj = @{ MvnExe = (Join-Path $falsos 'm48-mvn.ps1') }
  foreach ($k in $Mas.Keys) { $aj[$k] = $Mas[$k] }
  return (Escenario-M25 $Nombre $Casos -Sano -Ajustes $aj)
}

# Lanza con los guiones $Guion de m48-mvn.ps1, las variables de entorno $Env (nombre -> valor) y, con $GuionCopilot, el guion del Copilot falso.
function Prueba-M48($E, [string]$Guion, [string[]]$A = @(), [string]$GuionCopilot = '', [hashtable]$Env = @{}) {
  $env:RESCATE_M48 = $Guion
  foreach ($k in $Env.Keys) { Set-Item -Path "env:$k" -Value ([string]$Env[$k]) }
  try { return (Prueba $E $A $GuionCopilot) }
  finally {
    $env:RESCATE_M48 = ''
    foreach ($k in $Env.Keys) { Remove-Item -Path "env:$k" -ErrorAction SilentlyContinue }
  }
}

# Las letras que tiene que tener el nombre de un fichero de ficheros\logs\jobs\ para que su ruta en salidas\original-2\<job>\<caso> mida $Destino.
function Largo-M48($E, [string]$Job, [string]$Caso, [int]$Destino) { return ($Destino - ($E.Local.Length + $Job.Length + $Caso.Length + 41)) }

# Los nombres de lo que hay en ficheros\logs\jobs\ de un lado ($Lado: original, original-2, migrado) de un caso.
function Nombres-M48($E, [string]$Lado, [string]$Job = 'cargaJob', [string]$Caso = 'caso-01') {
  $d = Get-Ruta $E.Local "salidas/$Lado/$Job/$Caso/ficheros/logs/jobs"
  if (-not (Test-Path -LiteralPath $d)) { return @() }
  return @(Get-ChildItem -LiteralPath $d -File | ForEach-Object { $_.Name })
}

$NombreCorto48 = '^proceso-largo-nnnnnn~[0-9a-f]{8}\.log$'

# Comprueba que original, original-2 y migrado guardan un solo fichero largo con el mismo nombre corto.
function Comprueba-Corto-M48($E) {
  $n = @{}
  foreach ($lado in @('original', 'original-2', 'migrado')) {
    $n[$lado] = @(Nombres-M48 $E $lado)
    Igual "$lado guarda un solo fichero en ficheros\logs\jobs" 1 $n[$lado].Count
    Comprueba "$lado : su nombre es el corto (20 letras, ~, 8 de hash y la extension)" ($n[$lado].Count -eq 1 -and $n[$lado][0] -cmatch $NombreCorto48) ($n[$lado] -join ',')
  }
  Comprueba 'el mismo nombre en los tres lados' (($n['original'] -join ',') -ceq ($n['original-2'] -join ',') -and ($n['original'] -join ',') -ceq ($n['migrado'] -join ',')) ("$($n['original']) | $($n['original-2']) | $($n['migrado'])")
}

$Pruebas['m48 (a) un fichero cuya ruta en salidas pasa de 259 letras se guarda con un nombre corto, el mismo en original, original-2 y migrado: el caso sale igual y su original se reutiliza en el siguiente lanzamiento'] = {
  $e = Escenario-M48 'm48-a' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $n = Largo-M48 $e 'cargaJob' 'caso-01' 270
  Comprueba 'la prueba cabe: el nombre largo mide entre 40 y 250 letras' ($n -ge 40 -and $n -le 250) "n=$n, Local=$($e.Local.Length)"
  $r = Prueba-M48 $e 'largo:/caso-01' @() '' @{ M48_LARGO = $n }
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'los dos casos salen iguales' 'igual,igual' ((Resultados $e) -join ',')
  Comprueba-Corto-M48 $e
  Igual 'el contenido del fichero guardado es el que dejo el job' "ok`n" (Lee $e.Local ('salidas/migrado/cargaJob/caso-01/ficheros/logs/jobs/' + (@(Nombres-M48 $e 'migrado'))[0]))
  Comprueba 'lo demas del caso se guarda como siempre (estado y resultado)' ((Test-Path -LiteralPath (Get-Ruta $e.Local 'salidas/migrado/cargaJob/caso-01/estado.txt')) -and (Test-Path -LiteralPath (Get-Ruta $e.Local ('salidas/original/cargaJob/caso-01/ficheros/salida/resultado_' + (Hoy) + '.txt')))) ''
  Comprueba 'la consola no dice que algun fichero no se guarde' ($r.Salida -notmatch 'no se ha podido guardar' -and $r.Salida -notmatch 'carpeta mas corta') (Cola $r.Salida)
  Igual 'los dos casos quedan como originales reutilizables' 2 @((Lee-Json (Get-Ruta $e.Local 'salidas/originales.json')).casos).Count
  $o1 = Orig-Mvn $e
  $r = Prueba-M48 $e 'largo:/caso-01' @() '' @{ M48_LARGO = $n }
  Comprueba 'el siguiente lanzamiento reutiliza los 2 originales' ($r.Salida -match 'Original: se reutilizan las salidas de 2 caso\(s\) y se ejecutan 0\.') (Cola $r.Salida)
  Igual 'sin otro Maven del original' $o1 (Orig-Mvn $e)
  Igual 'y sigue igual' 'igual,igual' ((Resultados $e) -join ',')
}

$Pruebas['m48 (a2) la decision no depende del lado: un fichero que cabria en el original y en el migrado pero no en la ruta mas larga de salidas (culpable) tambien se guarda con nombre corto, en los tres lados'] = {
  $e = Escenario-M48 'm48-a2' ([ordered]@{ cargaJob = @('importe=10.00') })
  $n = Largo-M48 $e 'cargaJob' 'caso-01' 250
  Comprueba 'la prueba cabe: el nombre largo mide entre 40 y 250 letras' ($n -ge 40 -and $n -le 250) "n=$n, Local=$($e.Local.Length)"
  $r = Prueba-M48 $e 'largo:/caso-01' @() '' @{ M48_LARGO = $n }
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'el caso sale igual' 'igual' ((Resultados $e) -join ',')
  Comprueba-Corto-M48 $e
}

$Pruebas['m48 (a3) el nombre corto: la misma ruta da el mismo nombre en cualquier dia, lo que cabe no cambia, lo que no cabe ni asi no se guarda y regresion.ps1 lo reconoce'] = {
  $f = Join-Path $Dir 'm48-corto.ps1'
  $cuerpo = @'
$Inv = [System.Globalization.CultureInfo]::InvariantCulture
$RutasCopia = @(); $Hoy = @()
$LimiteRuta = 259
$Local = 'x' * 150
$ayer = [datetime]'2026-11-19'; $hoy = [datetime]'2026-11-20'
$dir = 'ficheros/logs/jobs/'
$resto = 'proceso-largo-' + ('n' * 60)
function Salida([string]$K, $V) { if ($null -eq $V) { $V = '(null)' }; $K + ' ' + $V }
Salida 'A' (Get-RelSalida 'cargaJob' ($dir + $resto + '_20261119.log') @($ayer))
Salida 'B' (Get-RelSalida 'cargaJob' ($dir + $resto + '_20261120.log') @($hoy))
Salida 'C' (Get-RelSalida 'cargaJob' ($dir + $resto + '_20261120.log') @($ayer, $hoy))
Salida 'D' (Get-RelSalida 'cargaJob' 'ficheros/salida/resultado_20261120.txt' @($hoy))
Salida 'E' (Get-RelSalida 'cargaJob' ($dir + $resto + '_20261121.log') @($hoy))
Salida 'F' (Get-RelSalida 'cargaJob' ('ficheros/' + ('a' * 100) + '/' + ('b' * 100) + '/dato.txt') @($hoy))
$k = 259 - $Local.Length - 'cargaJob'.Length - 43
Salida 'G' (Get-RelSalida 'cargaJob' ('a/' + ('b' * $k)) @($hoy)).Length
Salida 'H' (Get-RelSalida 'cargaJob' ('a/' + ('b' * ($k + 1))) @($hoy))
Salida 'I' (Get-RelSalida 'cargaJob' ('a/' + ('resultado_20261119_' + ('c' * 120)) + '.txt') @($ayer))
Salida 'J' (Get-RelSalida 'cargaJob' ('a/' + ('resultado_20261120_' + ('c' * 120)) + '.txt') @($hoy))
Salida 'K' (Get-RelSalida 'cargaJob' ($dir + $resto + '.log') @($hoy))
Salida 'L' (Test-NombreCorto (Get-RelSalida 'cargaJob' ($dir + $resto + '_20261120.log') @($hoy)))
Salida 'M' (Test-NombreCorto 'ficheros/salida/resultado_20261120.txt')
Salida 'N' ($k + 2)
'@
  [System.IO.File]::WriteAllText($f, ('param([string]$Raiz)' + "`n" + (Texto-De-Funciones $Script @('Get-LargoRuta', 'Get-RelSalida', 'Get-NombreCorto', 'Test-NombreCorto', 'Get-Normal')) + "`n" + (Texto-De-Funciones (Join-Path (Split-Path -Parent $Script) 'tareas.ps1') @('Get-Hash8')) + "`n" + $cuerpo))
  $r = Lanzar $f @()
  Igual 'el script de la prueba sale con 0' 0 $r.Codigo
  $v = @{}
  foreach ($l in ($r.Salida -split "`r?`n")) { if ($l -match '^([A-Z]) (.*)$') { $v[$Matches[1]] = $Matches[2] } }
  Comprueba 'A: una ruta larga se guarda con 20 letras, ~, 8 de hash y la extension, en su misma carpeta' ($v['A'] -cmatch '^ficheros/logs/jobs/proceso-largo-nnnnnn~[0-9a-f]{8}\.log$') $r.Salida
  Igual 'B: el original de ayer (con su fecha y sus dias) y el migrado de hoy dan el mismo nombre' $v['A'] $v['B']
  Igual 'C: con los dos dias en la lista, el mismo' $v['A'] $v['C']
  Igual 'D: lo que cabe se queda como estaba' 'ficheros/salida/resultado_20261120.txt' $v['D']
  Comprueba 'E: una fecha que no es de los dias de la ejecucion es otro dato: otro nombre' ($v['E'] -cmatch '~[0-9a-f]{8}\.log$' -and $v['E'] -cne $v['A']) $r.Salida
  Igual 'F: ni con nombre corto cabe (la carpeta ya mide demas): no se guarda' '(null)' $v['F']
  Igual 'G: justo en 259 letras (la ruta mas larga de salidas) cabe y se queda' $v['N'] $v['G']
  Comprueba 'H: con una letra mas ya no cabe y se acorta' ($v['H'] -cmatch '^a/b{20}~[0-9a-f]{8}$') $r.Salida
  Igual 'I y J: el prefijo sale del nombre normalizado: la fecha de otro dia no cambia el nombre corto' $v['I'] $v['J']
  Comprueba 'K: el mismo nombre sin la fecha es otra ruta: otro hash' ($v['K'] -cmatch '~[0-9a-f]{8}\.log$' -and $v['K'] -cne $v['A']) $r.Salida
  Igual 'L: Test-NombreCorto reconoce un nombre corto' 'True' $v['L']
  Igual 'M: y no un nombre normal' 'False' $v['M']
}

$Pruebas['m48 (b) un fichero que no cabe ni con nombre corto no se guarda: el lanzamiento sigue, el caso sale distinto con el fichero y el motivo, la consola sugiere una carpeta mas corta una sola vez, no queda como original reutilizable y -Reparar no lo toca'] = {
  $e = Escenario-M48 'm48-b' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00'); remesaJob = @('importe=10.00') })
  $rel = 'ficheros/' + ('a' * 100) + '/' + ('b' * 100) + '/dato.txt'
  $r = Prueba-M48 $e 'sin-sitio:^cargaJob/caso-01$' @('-Reparar')
  Igual 'el lanzamiento acaba: sale con 2 (un caso distinto)' 2 $r.Codigo
  Igual 'el caso con el fichero sale distinto y los demas, iguales' 'distinto,igual,igual' ((Resultados $e) -join ',')
  $d = @((Caso $e 'cargaJob' 'caso-01').diferencias)
  Igual 'una diferencia: el fichero' $rel ($d | ForEach-Object { $_.fichero })
  Comprueba 'con el motivo: no se ha podido guardar y la ruta de tantas letras' ("$($d[0].original)" -match '^no se ha podido guardar: ruta de \d+ letras$' -and "$($d[0].migrado)" -match '^no se ha podido guardar: ruta de \d+ letras$') "$($d[0].original) | $($d[0].migrado)"
  Comprueba 'la consola dice el fichero y el motivo' ($r.Salida.Contains($rel) -and $r.Salida -match 'no se ha podido guardar: ruta de \d+ letras') (Cola $r.Salida)
  Igual 'y sugiere una carpeta mas corta una sola vez (aunque falle en tres lados)' 1 @([regex]::Matches($r.Salida, 'carpeta mas corta')).Count
  Comprueba 'el fichero no esta en ningun lado' (-not (Test-Path -LiteralPath (Get-Ruta $e.Local ('salidas/original/cargaJob/caso-01/ficheros/' + ('a' * 100))))) ''
  Comprueba 'lo demas del caso se guarda (estado.txt en los tres lados)' ((Test-Path -LiteralPath (Get-Ruta $e.Local 'salidas/original/cargaJob/caso-01/estado.txt')) -and (Test-Path -LiteralPath (Get-Ruta $e.Local 'salidas/original-2/cargaJob/caso-01/estado.txt')) -and (Test-Path -LiteralPath (Get-Ruta $e.Local 'salidas/migrado/cargaJob/caso-01/estado.txt'))) ''
  $j = @((Lee-Json (Get-Ruta $e.Local 'salidas/originales.json')).casos | ForEach-Object { "$($_.job)/$($_.caso)" })
  Igual 'el caso con un fichero sin guardar no queda como original reutilizable (los otros dos, si)' 'cargaJob/caso-02,remesaJob/caso-01' ($j -join ',')
  Comprueba 'con -Reparar, lo salta y lo dice, sin llamar a Copilot para repararlo' ($r.Salida -match 'Salto 1 caso\(s\) distinto\(s\)' -and (Llamadas-Reparar $e).Count -eq 0) (Cola $r.Salida)
  $r = Prueba-M48 $e 'sin-sitio:^cargaJob/caso-01$'
  Comprueba 'el siguiente lanzamiento reutiliza 2 originales y ejecuta el del caso sin guardar' ($r.Salida -match 'Original: se reutilizan las salidas de 2 caso\(s\) y se ejecutan 1\.') (Cola $r.Salida)
  Igual 'sigue distinto' 'distinto,igual,igual' ((Resultados $e) -join ',')
}

$Pruebas['m48 (b2) un error al copiar a salidas (un fichero donde va una carpeta) tambien se apunta, con el mensaje del error: el lanzamiento sigue y el caso sale distinto'] = {
  $e = Escenario-M48 'm48-b2' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $obstaculo = Get-Ruta $e.Local 'salidas/migrado/cargaJob/caso-01/ficheros'
  $r = Prueba-M48 $e 'obstaculo:/caso-01' @() '' @{ M48_OBSTACULO = $obstaculo }
  Igual 'sale con 2' 2 $r.Codigo
  Igual 'el caso sale distinto y el otro, igual' 'distinto,igual' ((Resultados $e) -join ',')
  $d = @((Caso $e 'cargaJob' 'caso-01').diferencias | Where-Object { $_.fichero -like 'ficheros/salida/resultado_*' })
  Igual 'una diferencia: el fichero que no se pudo guardar' 1 $d.Count
  Comprueba 'su motivo es el mensaje del error, no el de la ruta' ("$($d[0].migrado)" -match '^no se ha podido guardar: .{5,}' -and "$($d[0].migrado)" -notmatch 'ruta de \d+ letras') "$($d[0].migrado)"
  Comprueba 'el original si lo guardo' ("$($d[0].original)" -notmatch 'no se ha podido guardar') "$($d[0].original)"
  Comprueba 'la consola lo dice' ($r.Salida -match 'resultado_\d{8}\.txt.*no se ha podido guardar') (Cola $r.Salida)
  Comprueba 'y no sugiere la carpeta mas corta (no es la ruta)' ($r.Salida -notmatch 'carpeta mas corta') (Cola $r.Salida)
}

$Pruebas['m48 (c) el migrado acaba FAILED y su Maven escribe la causa: la causa esta en prueba-local.json, en la consola, en el HTML de la comparacion y en el prompt de -Reparar'] = {
  $e = Escenario-M48 'm48-c' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba-M48 $e 'failed-mig:/caso-01' @('-Reparar') 'reparar-no'
  Igual 'sale con 2' 2 $r.Codigo
  Igual 'el caso sale distinto y el otro, igual' 'distinto,igual' ((Resultados $e) -join ',')
  $f = @((Caso $e 'cargaJob' 'caso-01').fallos)
  Igual 'prueba-local.json: un fallo, el del migrado, FAILED' 'migrado|FAILED' (($f | ForEach-Object { "$($_.lado)|$($_.estado)" }) -join ',')
  Igual 'con su causa, sin el Caused by:' 'java.lang.IllegalStateException: sin correo' "$($f[0].causa)"
  Igual 'el caso igual no lleva fallos' 0 @((Caso $e 'cargaJob' 'caso-02').fallos).Count
  Comprueba 'la consola: el migrado acaba FAILED y la causa, bajo el caso distinto' ($r.Salida -match 'el migrado acaba FAILED: java\.lang\.IllegalStateException: sin correo') (Cola $r.Salida)
  Comprueba 'la causa no esta dentro de las carpetas que se comparan' (@(Get-ChildItem -LiteralPath (Get-Ruta $e.Local 'salidas') -Recurse -File | Where-Object { [System.IO.File]::ReadAllText($_.FullName) -match 'sin correo' }).Count -eq 0) ''
  $p = @(Registros-Reparar $e 1)
  Comprueba 'hay una llamada de reparar y su prompt lleva la causa del lado que falla' ($p.Count -ge 1 -and $p[0].Contains('el migrado acaba FAILED: java.lang.IllegalStateException: sin correo')) (Cola ($p -join ' '))
  $g = Join-Path $Dir 'm48-html.ps1'
  $raiz = Split-Path -Parent $Script
  $cuerpo = @"
`$ErrorActionPreference = 'Stop'
. '$(Join-Path $raiz 'comun.ps1')'
. '$(Join-Path $raiz 'tareas.ps1')'
. '$(Join-Path $raiz 'informe.ps1')'
`$marco = Split-Plantilla (Read-PlantillaInforme 'marco.html')
`$pl = Split-Plantilla (Read-PlantillaInforme '3-original-vs-migrado.html')
`$T = Merge-Trozos `$marco.Trozos `$pl.Trozos
`$c = @((Get-Content -Raw -LiteralPath '$($e.Json)' | ConvertFrom-Json).casos | Where-Object { `$_.caso -eq 'caso-01' })[0]
Get-CasoLocalHtml `$T `$c
"@
  [System.IO.File]::WriteAllText($g, $cuerpo)
  $h = Lanzar $g @()
  Igual 'el HTML del caso se monta' 0 $h.Codigo
  Comprueba 'el HTML dice que el migrado acaba FAILED y la causa' ($h.Salida -match 'migrado' -and $h.Salida -match 'FAILED' -and $h.Salida.Contains('java.lang.IllegalStateException: sin correo')) $h.Salida
}

$Pruebas['m48 (d) el original de un caso no arranca y Maven dice por que: el motivo del rechazo lleva la causa; la causa de un original reutilizado sigue disponible y la de un caso hecho en otro lanzamiento tambien'] = {
  $e = Escenario-M48 'm48-d' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M48 $e 'excepcion-orig'
  Igual 'sale con 2 (el migrado arranca, el original no)' 2 $r.Codigo
  $p = Registro-Caso-M36 $e 'cargaJob' '01' 2
  Comprueba 'el reintento recibe el motivo con la clase y la causa de Maven' ($p.Contains('lanzarlo da BadSqlGrammarException (org.h2.jdbc.JdbcSQLSyntaxErrorException: Table "T_X" not found). Si el caso no busca justo eso')) (Cola $p)
  $f = @((Caso $e 'cargaJob' 'caso-01').fallos)
  Igual 'prueba-local.json: el fallo es el del original, EXCEPCION' 'original|EXCEPCION' (($f | ForEach-Object { "$($_.lado)|$($_.estado)" }) -join ',')
  Igual 'con la causa de Maven' 'org.h2.jdbc.JdbcSQLSyntaxErrorException: Table "T_X" not found' "$($f[0].causa)"
  Comprueba 'la consola dice que el original acaba EXCEPCION y la causa' ($r.Salida -match 'el original acaba EXCEPCION: org\.h2\.jdbc\.JdbcSQLSyntaxErrorException: Table "T_X" not found') (Cola $r.Salida)
  $o1 = Orig-Mvn $e
  $r = Prueba-M48 $e 'excepcion-orig'
  Comprueba 'el siguiente lanzamiento reutiliza el original' ($r.Salida -match 'Original: se reutilizan las salidas de 1 caso\(s\) y se ejecutan 0\.') (Cola $r.Salida)
  Igual 'sin otro Maven del original' $o1 (Orig-Mvn $e)
  $f = @((Caso $e 'cargaJob' 'caso-01').fallos)
  Igual 'y la causa del original reutilizado sigue en prueba-local.json' 'org.h2.jdbc.JdbcSQLSyntaxErrorException: Table "T_X" not found' "$($f[0].causa)"
  # un caso hecho en otro lanzamiento cuyo original dejo EXCEPCION: el motivo lleva la causa que se guardo con ese original
  $e2 = Escenario-M48 'm48-d2' ([ordered]@{ cargaJob = @('importe=10.00') })
  [void](Prueba-M48 $e2 '')
  Escribe $e2.Local 'salidas/original/cargaJob/caso-01/estado.txt' "estado=EXCEPCION`nsalida=BadSqlGrammarException`n"
  $o = Lee-Json (Get-Ruta $e2.Local 'salidas/originales.json')
  foreach ($c in @($o.casos)) { Add-Member -InputObject $c -NotePropertyName causa -NotePropertyValue 'org.h2.jdbc.JdbcSQLSyntaxErrorException: Table "T_X" not found' -Force }
  [System.IO.File]::WriteAllText((Get-Ruta $e2.Local 'salidas/originales.json'), (ConvertTo-Json -InputObject $o -Depth 6))
  $r = Prueba-M48 $e2 'excepcion-orig'
  Comprueba 'la Info dice que se rehace 1 caso' ($r.Salida -match 'Se rehacen 1 caso') (Cola $r.Salida)
  $p = Registro-Caso-M36 $e2 'cargaJob' '01' 2
  Comprueba 'y la IA recibe el motivo con la causa que se guardo con el original' ($p.Contains('lanzarlo da BadSqlGrammarException (org.h2.jdbc.JdbcSQLSyntaxErrorException: Table "T_X" not found).')) (Cola $p)
}

$MotivoVacio48 = 'Con un caso vacio, el original arranca el job cargaJob (estado=COMPLETED) y con tu test el migrado no: BeanCreationException (org.springframework.beans.factory.BeanCreationException: sin correo). Revisa lo que simula el test y las propiedades que le pasa.'

$Pruebas['m48 (e1) caso vacio: el original acaba COMPLETED y el migrado EXCEPCION: con intentos de sobra se rechaza con la causa y el reintento, que arranca, se acepta'] = {
  $e = Escenario-M48 'm48-e1' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba-M48 $e 'vacio-excepcion-mig:/vacio' @() '' @{ M48_VACIOS = 1 }
  Igual 'sale con 0' 0 $r.Codigo
  Comprueba 'la consola rechaza el arnes del migrado por eso' ($r.Salida -match 'Arnes del migrado rechazado: Con un caso vacio, el original arranca el job cargaJob \(estado=COMPLETED\) y con tu test el migrado no: BeanCreationException \(org\.springframework\.beans\.factory\.BeanCreationException: sin correo\)') (Cola $r.Salida)
  $t = Tarea-Arnes $e 'migrado'
  Igual 'la tarea del migrado queda hecha, con dos intentos' 'hecha:2' "$($t.estado):$($t.intentos)"
  Comprueba 'el reintento recibe el motivo entero' ((Registro-Arnes $e 'migrado' 2).Contains($MotivoVacio48)) (Cola (Registro-Arnes $e 'migrado' 2))
  Igual 'los casos salen iguales' 'igual,igual' ((Resultados $e) -join ',')
}

$Pruebas['m48 (e5) caso vacio: si tampoco arranca en el original (el job necesita algo que el caso vacio no trae), el test del migrado se acepta a la primera y sin aviso'] = {
  $e = Escenario-M48 'm48-e5' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M48 $e 'excepcion-ambos:/vacio'
  Igual 'sale con 0' 0 $r.Codigo
  Comprueba 'el caso vacio del original tambien acaba EXCEPCION' ((Lee $e.Local 'salidas/vacio/cargaJob/estado.txt') -match 'estado=EXCEPCION') ''
  Comprueba 'la consola no rechaza ni avisa por el caso vacio' ($r.Salida -notmatch 'Con un caso vacio, el original arranca') (Cola $r.Salida)
  $t = Tarea-Arnes $e 'migrado'
  Igual 'la tarea del migrado queda hecha a la primera' 'hecha:1' "$($t.estado):$($t.intentos)"
}

$Pruebas['m48 (e2) caso vacio: en el ultimo intento el test se acepta con un aviso (puede ser el codigo del migrado)'] = {
  $e = Escenario-M48 'm48-e2' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba-M48 $e 'vacio-excepcion-mig:/vacio' @() '' @{ M48_VACIOS = 9 }
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'el primer intento se rechaza' 1 @([regex]::Matches($r.Salida, 'Arnes del migrado rechazado: Con un caso vacio')).Count
  Comprueba 'el ultimo se acepta' ($r.Salida -match 'Arnes del migrado: bien\.') (Cola $r.Salida)
  Igual 'con el aviso del motivo (ademas del rechazo del primer intento)' 2 @([regex]::Matches($r.Salida, [regex]::Escape($MotivoVacio48))).Count
  $t = Tarea-Arnes $e 'migrado'
  Igual 'la tarea queda hecha, con dos intentos' 'hecha:2' "$($t.estado):$($t.intentos)"
  Comprueba 'el test se guarda' (Test-Path -LiteralPath (Get-Ruta $e.Local 'arnes/migrado')) ''
  Igual 'los casos se ejecutan' 'igual,igual' ((Resultados $e) -join ',')
}

$Pruebas['m48 (e3) caso vacio: un test guardado de otro lanzamiento que da EXCEPCION con el caso vacio se usa, solo con un aviso y sin llamar a Copilot'] = {
  $e = Escenario-M48 'm48-e3' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M48 $e ''
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  $n = @(Llamadas $e).Count
  Cambia-Huella $e 'migrado'
  $r = Prueba-M48 $e 'vacio-excepcion-mig:/vacio' @() '' @{ M48_VACIOS = 99 }
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'sin llamadas a Copilot' $n @(Llamadas $e).Count
  Comprueba 'dice que el test de otro lanzamiento sigue valiendo' ($r.Salida -match 'Arnes del migrado: bien \(el test de otro lanzamiento sigue valiendo\)') (Cola $r.Salida)
  Comprueba 'y avisa de lo del caso vacio' ($r.Salida.Contains($MotivoVacio48)) (Cola $r.Salida)
  Igual 'la tarea queda hecha' 'hecha' (Tarea-Arnes $e 'migrado').estado
}

$Pruebas['m48 (e4) caso vacio: el test que dejo una llamada pasada de tiempo y da EXCEPCION con el caso vacio se rechaza igual, con el motivo de la llamada y el del vacio'] = {
  $e = Escenario-M48 'm48-e4' ([ordered]@{ cargaJob = @('importe=10.00') }) @{ CopilotExe = (Join-Path $falsos 'arnes-copilot.ps1'); SegundosArnes = 10 }
  $r = Prueba-M48 $e 'vacio-excepcion-mig:/vacio' @() 'colgado-bueno:arnes-migrado' @{ M48_VACIOS = 1 }
  Igual 'sale con 0 (el reintento arranca)' 0 $r.Codigo
  $p = Registro-Arnes $e 'migrado' 2
  Comprueba 'hay un reintento (la llamada pasada de tiempo no se acepta aunque dejo un test)' ($p.Length -gt 0) (Cola (Registro-Arnes $e 'migrado' 1))
  Comprueba 'y su prompt lleva el motivo del caso vacio' ($p.Contains('Con un caso vacio, el original arranca el job cargaJob (estado=COMPLETED) y con tu test el migrado no: BeanCreationException')) (Cola $p)
  $t = Tarea-Arnes $e 'migrado'
  Igual 'la tarea queda hecha con dos intentos' 'hecha:2' "$($t.estado):$($t.intentos)"
}

$Pruebas['m48 (f) si el migrado acaba EXCEPCION en todos los casos de un job y el original no: sale la linea de -RehacerArnes; no sale si falla un solo caso ni si el original tambien acaba EXCEPCION'] = {
  $e = Escenario-M48 'm48-f' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00'); remesaJob = @('importe=10.00', 'importe=20.00'); tarifaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba-M48 $e 'excepcion-mig:^cargaJob/caso-;excepcion-mig:^remesaJob/caso-01$;excepcion-mig:^tarifaJob/caso-01$;excepcion-ambos:^tarifaJob/caso-02$'
  Igual 'sale con 2' 2 $r.Codigo
  Comprueba 'la linea de cargaJob, con la clase y la causa' ($r.Salida.Contains('El migrado no arranca el job cargaJob en ningun caso (BeanCreationException: java.lang.IllegalStateException: sin correo). Casi siempre es el test del migrado, no el codigo: relanza con -RehacerArnes.')) (Cola $r.Salida)
  Igual 'solo una linea de esas' 1 @([regex]::Matches($r.Salida, 'El migrado no arranca el job')).Count
  Comprueba 'remesaJob (falla un solo caso) no la lleva' ($r.Salida -notmatch 'no arranca el job remesaJob') (Cola $r.Salida)
  Comprueba 'tarifaJob (el migrado no arranca en todos, pero el original tampoco en uno) no la lleva' ($r.Salida -notmatch 'no arranca el job tarifaJob') (Cola $r.Salida)
}

# Un primer lanzamiento con una copia de prueba-local.ps1 (y lo que carga) en la que la constante $Constante vale uno menos, y dos con el de
# ahora: la clave del original lleva esa constante, asi que el segundo ejecuta otra vez los 2 casos y el tercero ya los reutiliza.
function Comprueba-Clave-M48($E, [string]$Constante) {
  $raiz = Split-Path -Parent $Script
  $viejo = Join-Path $Dir "m48-$Constante-viejo"
  if (Test-Path -LiteralPath $viejo) { Remove-Item -LiteralPath $viejo -Recurse -Force }
  [void](New-Item -ItemType Directory -Path $viejo -Force)
  foreach ($x in @('prueba-local.ps1', 'comun.ps1', 'tareas.ps1', 'regresion.ps1', 'tareas', 'regresion')) { Copy-Item -LiteralPath (Join-Path $raiz $x) -Destination $viejo -Recurse -Force }
  $texto = [System.IO.File]::ReadAllText((Join-Path $viejo 'prueba-local.ps1'))
  $m = [regex]::Match($texto, '\$' + $Constante + ' = (\d+)')
  Comprueba "prueba-local.ps1 lleva la constante `$$Constante, con un numero" $m.Success ''
  if ($m.Success) { [System.IO.File]::WriteAllText((Join-Path $viejo 'prueba-local.ps1'), $texto.Replace($m.Value, '$' + $Constante + ' = ' + (([int]$m.Groups[1].Value) - 1))) }
  $actual = $Script
  $Script = Join-Path $viejo 'prueba-local.ps1'
  $r = Prueba-M48 $E ''
  $Script = $actual
  Igual "con otro `$$Constante sale con 0" 0 $r.Codigo
  $o1 = Orig-Mvn $E
  $r = Prueba-M48 $E ''
  Comprueba "con el `$$Constante de ahora no reutiliza nada y ejecuta los 2 casos" ($r.Salida -match 'Original: se reutilizan las salidas de 0 caso\(s\) y se ejecutan 2\.') (Cola $r.Salida)
  Igual 'el original y el original-2 de cada caso se ejecutan otra vez' ($o1 + 4) (Orig-Mvn $E)
  $r = Prueba-M48 $E ''
  Comprueba 'y el siguiente lanzamiento ya los reutiliza' ($r.Salida -match 'Original: se reutilizan las salidas de 2 caso\(s\) y se ejecutan 0\.') (Cola $r.Salida)
  Igual 'sin otro Maven del original' ($o1 + 4) (Orig-Mvn $E)
}

$Pruebas['m48 (h) la clave del original lleva la version del formato de salidas: un original guardado con otra version se ejecuta otra vez, una sola vez'] = {
  Comprueba-Clave-M48 (Escenario-M48 'm48-h' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })) 'VersionSalidas'
}

$Pruebas['m48 (h2) la clave del original lleva el tope de la ruta de salidas (decide los nombres cortos): con otro tope, el original se ejecuta otra vez'] = {
  Comprueba-Clave-M48 (Escenario-M48 'm48-h2' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })) 'LimiteRuta'
}

# ===================== M50: grupos por causa, el dato de dependencias y las tablas con ';' dentro de un valor =====================
# m50-mvn.ps1 (sobre m48-mvn.ps1) deja, segun el guion de RESCATE_M50 ('guion:regex sobre job/caso', separados por ';'): un migrado FAILED con una causa
# (numero, otra, tipo, tipo2), tablas con ';' dentro de un valor, un fichero de mas o de menos en el migrado; y un arbol de dependencias de mentira
# para 'dependency:tree' (M50_ARBOL=falla: el plugin falla). Los escenarios son los de m25: el migrado lleva minimo=5.01 y la entrada importe=5.00 sale distinta.

function Escenario-M50([string]$Nombre, $Casos, [hashtable]$Mas = @{}) {
  $aj = @{ MvnExe = (Join-Path $falsos 'm50-mvn.ps1') }
  foreach ($k in $Mas.Keys) { $aj[$k] = $Mas[$k] }
  return (Escenario-M25 $Nombre $Casos -Sano -Ajustes $aj)
}

# Lanza con los guiones $Guion de m50-mvn.ps1 y las variables de entorno $Env (nombre -> valor).
function Prueba-M50($E, [string]$Guion, [string[]]$A = @(), [hashtable]$Env = @{}) {
  $env:RESCATE_M50 = $Guion
  foreach ($k in $Env.Keys) { Set-Item -Path "env:$k" -Value ([string]$Env[$k]) }
  try { return (Prueba $E $A) }
  finally {
    $env:RESCATE_M50 = ''
    foreach ($k in $Env.Keys) { Remove-Item -Path "env:$k" -ErrorAction SilentlyContinue }
  }
}

function Grupos-M50($E) { return @((Lee-Json $E.Json).grupos | Where-Object { $_ }) }

# Los 'mvn dependency:tree' que se han lanzado (en cualquier copia).
function Arboles-M50($E) { return @(Mavens-Con $E 'dependency:tree').Count }

# Cuenta cuantas veces sale $Texto (literal) en $Salida.
function Veces-M50([string]$Salida, [string]$Texto) { return @([regex]::Matches($Salida, [regex]::Escape($Texto))).Count }

$NotaTabla50 = "la tabla tiene ';' dentro de algun valor (fila 2: 4 campos; la cabecera, 3): no se han podido ordenar sus columnas"

$Pruebas['m50 (a) una tabla con un valor con ; dentro (a@x;b@x), las columnas en otro orden en cada lado y los mismos datos: el caso sale igual'] = {
  $e = Escenario-M50 'm50-a' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba-M50 $e 'tabla-igual:/caso-01'
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'los dos casos salen iguales' 'igual,igual' ((Resultados $e) -join ',')
  Comprueba 'el original guarda la tabla con ID primero y el migrado con NOMBRE primero (no era la misma, en bruto)' (((Lee $e.Local 'salidas/original/cargaJob/caso-01/tablas/CLIENTES.csv') -match '^ID;CORREOS;NOMBRE') -and ((Lee $e.Local 'salidas/migrado/cargaJob/caso-01/tablas/CLIENTES.csv') -match '^NOMBRE;ID;CORREOS')) ''
  Igual 'sin grupos en prueba-local.json' 0 (Grupos-M50 $e).Count
}

$Pruebas['m50 (a2) la misma tabla con un dato distinto en otra columna: el caso sale distinto, con la nota de ;'] = {
  $e = Escenario-M50 'm50-a2' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M50 $e 'tabla-dato'
  Igual 'sale con 2' 2 $r.Codigo
  $c = Caso $e 'cargaJob' 'caso-01'
  Igual 'el caso sale distinto' 'distinto' $c.resultado
  $d = @($c.diferencias)
  Igual 'solo por la tabla' 'tablas/CLIENTES.csv' (($d | ForEach-Object { $_.fichero }) -join ',')
  Igual 'con la nota del punto y coma, con la fila y los campos del original' $NotaTabla50 "$($d[0].nota)"
  Comprueba 'la consola lleva la nota' ($r.Salida.Contains("($NotaTabla50)")) (Cola $r.Salida)
}

$Pruebas['m50 (a3) filas con ; en dos columnas distintas (correos en una, nombre en otra): ninguna columna da las tablas iguales: distinto, con la nota'] = {
  $e = Escenario-M50 'm50-a3' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M50 $e 'tabla-dos'
  Igual 'sale con 2' 2 $r.Codigo
  $d = @((Caso $e 'cargaJob' 'caso-01').diferencias)
  Igual 'distinto por la tabla' 'tablas/CLIENTES.csv' (($d | ForEach-Object { $_.fichero }) -join ',')
  Igual 'con la nota' $NotaTabla50 "$($d[0].nota)"
}

# Compara con Compare-Fichero (como tabla) los pares de contenidos de $Casos (lineas "Caso '<id>' <A> <B>"): devuelve id -> 'igual' o 'distinto [<nota>]'.
function Tablas-M50([string]$Nombre, [string]$Casos) {
  $f = Join-Path $Dir "$Nombre.ps1"
  $cuerpo = @'
$Inv = [System.Globalization.CultureInfo]::InvariantCulture
$RutasCopia = @()
$Hoy = @()
function Caso([string]$Id, [string]$A, [string]$B) {
  $d = Join-Path $Raiz $Id
  [void](New-Item -ItemType Directory -Path $d -Force)
  $pa = Join-Path $d 'a.csv'; $pb = Join-Path $d 'b.csv'
  [System.IO.File]::WriteAllText($pa, $A); [System.IO.File]::WriteAllText($pb, $B)
  $c = Compare-Fichero $pa $pb $true
  if ($c) { 'R ' + $Id + ' distinto [' + $c.Nota + ']' } else { 'R ' + $Id + ' igual' }
}

'@ + "`n" + $Casos
  [System.IO.File]::WriteAllText($f, ('param([string]$Raiz)' + "`n" + (Texto-De-Funciones $Script (@('Compare-Fichero') + $FnLeer + @('Sort-Tabla', 'Resolve-ParTablas', 'Sort-Ordinal', 'Get-Normal', 'Get-Legible', 'Get-NotaJdk'))) + "`n" + '$Latin = [System.Text.Encoding]::GetEncoding(28591); $Utf8 = New-Object System.Text.UTF8Encoding($false); $Utf8Estricto = New-Object System.Text.UTF8Encoding($false, $true)' + "`n" + $cuerpo))
  $r = Lanzar $f @((Join-Path $Dir $Nombre))
  $v = @{}
  foreach ($l in @($r.Salida -split "`n")) { if ($l -cmatch '^R (\S+) (.*)$') { $v[$Matches[1]] = $Matches[2].TrimEnd() } }
  return $v
}

$Pruebas['m50 (a4) Compare-Fichero con tablas: la columna con ; en cualquier sitio (primera, ultima), 1 o 2 campos de mas por fila, un lado u otro, cabeceras con otros nombres, filas con menos campos'] = {
  $v = Tablas-M50 'm50-tablas' @'
Caso 'sin-punto-y-coma' "ID;NOMBRE`n1;ana`n" "NOMBRE;ID`nana;1`n"
Caso 'primera-columna' "CORREOS;ID`na@x;b@x;1`n" "ID;CORREOS`n1;a@x;b@x`n"
Caso 'ultima-columna' "ID;CORREOS`n1;a@x;b@x`n" "CORREOS;ID`na@x;b@x;1`n"
Caso 'uno-o-dos-de-mas-por-fila' "ID;CORREOS`n1;a;b`n2;c;d;e`n3;f`n" "CORREOS;ID`nf;3`nc;d;e;2`na;b;1`n"
Caso 'ancho-solo-en-el-migrado-y-distinto' "ID;NOMBRE`n1;ana`n2;maria`n" "NOMBRE;ID`nana;1`nmaria;2;x`n"
Caso 'cabeceras-con-otros-nombres' "ID;NOMBRE`n1;a;b`n" "ID;OTRO`n1;a;b`n"
Caso 'fila-con-menos-campos' "ID;CORREOS;NOMBRE`n1;a;b;ana`n2;c`n" "NOMBRE;ID;CORREOS`nana;1;a;b`n"
Caso 'dos-columnas-con-punto-y-coma' "ID;CORREOS;NOMBRE`n1;a@x;b@x;ana`n2;c@x;lopez;maria`n" "NOMBRE;ID;CORREOS`nana;1;a@x;b@x`nlopez;maria;2;c@x`n"
Caso 'nombre-repetido-en-la-cabecera' "ID;V;V`n1;x;y;z`n" "V;V;ID`nx;y;z;1`n"
Caso 'iguales-en-bruto-con-ancho' "ID;CORREOS`n1;a;b`n" "ID;CORREOS`n1;a;b`n"
'@
  Igual 'sin ; de mas: se ordenan las columnas, como siempre' 'igual' $v['sin-punto-y-coma']
  Igual 'la columna con ; es la primera' 'igual' $v['primera-columna']
  Igual 'la columna con ; es la ultima' 'igual' $v['ultima-columna']
  Igual 'filas con uno y con dos campos de mas, y otra sin ninguno' 'igual' $v['uno-o-dos-de-mas-por-fila']
  Igual 'con un nombre de columna repetido, la primera con ese nombre se lleva lo de mas' 'igual' $v['nombre-repetido-en-la-cabecera']
  Igual 'dos tablas iguales en bruto con ; de mas: iguales' 'igual' $v['iguales-en-bruto-con-ancho']
  Igual 'el ancho esta solo en el migrado (fila 3, 3 campos, cabecera 2) y no hay columna que lo arregle: distinto, con la fila del migrado' "distinto [la tabla tiene ';' dentro de algun valor (fila 3: 3 campos; la cabecera, 2): no se han podido ordenar sus columnas]" $v['ancho-solo-en-el-migrado-y-distinto']
  Igual 'cabeceras con otros nombres: distinto y sin nota (no se prueba nada)' 'distinto []' $v['cabeceras-con-otros-nombres']
  Comprueba 'una fila con menos campos: ninguna columna sirve; distinto con la nota (la primera fila con otro numero de campos, la 2)' ($v['fila-con-menos-campos'] -ceq "distinto [la tabla tiene ';' dentro de algun valor (fila 2: 4 campos; la cabecera, 3): no se han podido ordenar sus columnas]") "$($v['fila-con-menos-campos'])"
  Igual 'dos columnas con ; en filas distintas: distinto, con la nota' "distinto [la tabla tiene ';' dentro de algun valor (fila 2: 4 campos; la cabecera, 3): no se han podido ordenar sus columnas]" $v['dos-columnas-con-punto-y-coma']
}


$Pruebas['m50 (a5) tablas con un valor con ; dentro: una fila con menos campos que la cabecera no se rellena con un campo vacio, ni con el mismo numero de filas'] = {
  $v = Tablas-M50 'm50-tablas-corta' @'
Caso 'corta-frente-a-completa-con-vacio' "ID;CORREOS;NOMBRE`n1;a@x;b@x;ana`n2;c@x`n" "NOMBRE;ID;CORREOS`nana;1;a@x;b@x`n;2;c@x`n"
Caso 'la-misma-con-el-campo-escrito' "ID;CORREOS;NOMBRE`n1;a@x;b@x;ana`n2;c@x;maria`n" "NOMBRE;ID;CORREOS`nana;1;a@x;b@x`nmaria;2;c@x`n"
'@
  Igual 'la fila 2 del original tiene un campo menos (2 de 3) y la del migrado lo tiene vacio: distinto, con la nota de la primera fila con otro numero de campos (la 2, de 4 campos)' "distinto [$NotaTabla50]" $v['corta-frente-a-completa-con-vacio']
  Igual 'con el campo escrito en los dos lados, igual (la prueba del helper y de la columna con ;)' 'igual' $v['la-misma-con-el-campo-escrito']
}

$Pruebas['m50 (b) 9 casos con la misma causa (cambia un numero y el nombre del caso): un grupo, una cabecera, el detalle de 2 casos, grupos en prueba-local.json y grupo en cada caso'] = {
  $e = Escenario-M50 'm50-b' ([ordered]@{ cargaJob = @(1..9 | ForEach-Object { 'importe=10.00' }) })
  $r = Prueba-M50 $e 'numero:/caso-'
  Igual 'sale con 2' 2 $r.Codigo
  Igual 'los 9 casos salen distintos' (@(1..9 | ForEach-Object { 'distinto' }) -join ',') ((Resultados $e) -join ',')
  Comprueba 'la consola: una sola cabecera, con los 9 casos y la causa del primero sin normalizar' ($r.Salida.Contains('Grupo 1: 9 casos distintos, el migrado acaba FAILED: java.lang.IllegalStateException: no hay datos para caso-01 (id 101)')) (Cola $r.Salida)
  Igual 'y ningun grupo 2' 0 (Veces-M50 $r.Salida 'Grupo 2')
  Comprueba 'la lista de casos, sin el y N mas (son menos de 10)' ($r.Salida.Contains('casos: cargaJob/caso-01, cargaJob/caso-02, cargaJob/caso-03, cargaJob/caso-04, cargaJob/caso-05, cargaJob/caso-06, cargaJob/caso-07, cargaJob/caso-08, cargaJob/caso-09') -and $r.Salida -match 'caso-09\r?\n') (Cola $r.Salida)
  Igual 'el detalle de 2 casos, no de los 9' 2 @([regex]::Matches($r.Salida, 'distinto: cargaJob/caso-\d\d \(')).Count
  Comprueba 'que son los dos primeros' ($r.Salida.Contains('distinto: cargaJob/caso-01 (') -and $r.Salida.Contains('distinto: cargaJob/caso-02 (') -and -not $r.Salida.Contains('distinto: cargaJob/caso-03 (')) (Cola $r.Salida)
  Comprueba 'cada uno con su fallo, en su linea (la cabecera no cuenta)' (@([regex]::Matches($r.Salida, '(?m)^\s+el migrado acaba FAILED: java\.lang\.IllegalStateException: no hay datos para caso-0[12] ')).Count -eq 2) (Cola $r.Salida)
  $g = @(Grupos-M50 $e)
  Igual 'prueba-local.json lleva un grupo' 1 $g.Count
  Igual 'con numero, tipo y firma (la causa normalizada)' '1|fallo|fallo|FAILED|java.lang.IllegalStateException: no hay datos para <caso> (id <n>)' "$($g[0].numero)|$($g[0].tipo)|$($g[0].firma)"
  Igual 'los 9 casos, job/caso' (@(1..9 | ForEach-Object { 'cargaJob/caso-0' + $_ }) -join ',') (@($g[0].casos) -join ',')
  Igual 'la descripcion es la cabecera sin Grupo n' '9 casos distintos, el migrado acaba FAILED: java.lang.IllegalStateException: no hay datos para caso-01 (id 101)' "$($g[0].descripcion)"
  Igual 'sin hechos (ni de dependencias ni de cambio con el test)' 0 @($g[0].hechos).Count
  Igual 'cada caso lleva su grupo, el 1' '1,1,1,1,1,1,1,1,1' ((@((Lee-Json $e.Json).casos | ForEach-Object { $_.grupo })) -join ',')
}

$Pruebas['m50 (b2) un caso con un fallo y con diferencias de fichero va solo a su grupo de fallo'] = {
  $e = Escenario-M50 'm50-b2' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=5.00', 'importe=10.00') })
  $r = Prueba-M50 $e 'numero:/caso-01$'
  Igual 'sale con 2' 2 $r.Codigo
  Igual 'dos casos distintos y uno igual' 'distinto,distinto,igual' ((Resultados $e) -join ',')
  $c1 = Caso $e 'cargaJob' 'caso-01'
  Comprueba 'el caso 1 tiene diferencias de fichero ademas del fallo (el resultado y el estado)' (@($c1.diferencias).Count -ge 2 -and @($c1.fallos).Count -eq 1) "diferencias: $(@($c1.diferencias).Count), fallos: $(@($c1.fallos).Count)"
  $g = @(Grupos-M50 $e)
  Igual 'dos grupos' 2 $g.Count
  Igual 'el 1 es el de fallo, solo con el caso 1' '1|fallo|cargaJob/caso-01' "$($g[0].numero)|$($g[0].tipo)|$(@($g[0].casos) -join ',')"
  Igual 'el 2 es de fichero, solo con el caso 2 (sin fallo, con las diferencias de fichero)' '2|fichero|cargaJob/caso-02' "$($g[1].numero)|$($g[1].tipo)|$(@($g[1].casos) -join ',')"
  Igual 'la firma de fichero: la clave normalizada con su tipo' ('fichero|ficheros/salida/resultado_<hoy:yyyyMMdd>.txt:contenido') "$($g[1].firma)"
  Igual 'el caso 3, igual, no lleva grupo' 0 @((Caso $e 'cargaJob' 'caso-03').PSObject.Properties | Where-Object { $_.Name -eq 'grupo' }).Count
  Igual 'el 1 lleva el grupo 1 y el 2, el 2' '1,2' (((Caso $e 'cargaJob' 'caso-01').grupo, (Caso $e 'cargaJob' 'caso-02').grupo) -join ',')
}

$Pruebas['m50 (b3) dos causas de fallo y una de fichero: los grupos van primero los de fallo, y los de mas casos antes'] = {
  $e = Escenario-M50 'm50-b3' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=10.00', 'importe=10.00', 'importe=10.00', 'importe=10.00', 'importe=5.00', 'importe=5.00', 'importe=5.00', 'importe=5.00') })
  $r = Prueba-M50 $e 'otra:/caso-0[123]$;numero:/caso-0[45]$'
  Igual 'sale con 2' 2 $r.Codigo
  $g = @(Grupos-M50 $e)
  Igual 'tres grupos' 3 $g.Count
  Igual 'el 1: fallo, 3 casos (sin correo), aunque su firma va despues en orden alfabetico' '1|fallo|3|fallo|FAILED|java.lang.IllegalStateException: sin correo' "$($g[0].numero)|$($g[0].tipo)|$(@($g[0].casos).Count)|$($g[0].firma)"
  Igual 'el 2: fallo, 2 casos (no hay datos)' '2|fallo|2|fallo|FAILED|java.lang.IllegalStateException: no hay datos para <caso> (id <n>)' "$($g[1].numero)|$($g[1].tipo)|$(@($g[1].casos).Count)|$($g[1].firma)"
  Igual 'el 3: fichero, 4 casos, aunque tiene mas casos que los de fallo' '3|fichero|4' "$($g[2].numero)|$($g[2].tipo)|$(@($g[2].casos).Count)"
  $s = $r.Salida
  $i1 = [regex]::Match($s, [regex]::Escape('Grupo 1: 3 casos distintos, el migrado acaba FAILED: java.lang.IllegalStateException: sin correo')).Index
  $i2 = [regex]::Match($s, [regex]::Escape('Grupo 2: 2 casos distintos, el migrado acaba FAILED: java.lang.IllegalStateException: no hay datos para caso-04 (id 104)')).Index
  $i3 = [regex]::Match($s, [regex]::Escape('Grupo 3: 4 casos distintos, en ficheros/salida/resultado_')).Index
  Comprueba 'la consola los saca en ese orden, con la cabecera de cada uno' ($i1 -gt 0 -and $i2 -gt $i1 -and $i3 -gt $i2) "$i1 $i2 $i3 | $(Cola $s)"
  Comprueba 'el de fichero dice el fichero y el tipo' ($s -match 'Grupo 3: 4 casos distintos, en ficheros/salida/resultado_\d{8}\.txt: contenido\r?\n') (Cola $s)
  Igual 'cada caso con su grupo' '1,1,1,2,2,3,3,3,3' ((@((Lee-Json $e.Json).casos | ForEach-Object { $_.grupo })) -join ',')
}

$Pruebas['m50 (b4) casos de fichero con las mismas diferencias: un grupo de fichero (con y N mas); un fichero que sobra y uno que falta, cada uno el suyo'] = {
  $uno = @(1..12 | ForEach-Object { 'importe=5.00' })
  $e = Escenario-M50 'm50-b4' ([ordered]@{ cargaJob = @($uno + @('importe=10.00', 'importe=10.00')) })
  $r = Prueba-M50 $e 'extra:/caso-13$;falta:/caso-14$'
  Igual 'sale con 2' 2 $r.Codigo
  $g = @(Grupos-M50 $e)
  Igual 'tres grupos, todos de fichero' 'fichero,fichero,fichero' ((@($g | ForEach-Object { $_.tipo })) -join ',')
  Igual 'el 1 son los 12 casos con la misma diferencia' '12|fichero|ficheros/salida/resultado_<hoy:yyyyMMdd>.txt:contenido' "$(@($g[0].casos).Count)|$($g[0].tipo)|$($g[0].firma -replace '^fichero\|', '')"
  Igual 'el 2 y el 3, de un caso cada uno; a igualdad, por firma: sobra (extra.txt) y falta (resultado)' 'fichero|ficheros/extra.txt:sobra,fichero|ficheros/salida/resultado_<hoy:yyyyMMdd>.txt:falta' ($g[1].firma + ',' + $g[2].firma)
  Comprueba 'la lista de casos del 1: los 10 primeros y y 2 mas' ($r.Salida.Contains('cargaJob/caso-10 y 2 mas')) (Cola $r.Salida)
  Comprueba 'el grupo de un caso dice un caso distinto y el fichero que sobra' ($r.Salida -match 'Grupo 2: 1 caso distinto, en ficheros/extra\.txt: sobra\r?\n') (Cola $r.Salida)
  Comprueba 'el del fichero que falta' ($r.Salida -match 'Grupo 3: 1 caso distinto, en ficheros/salida/resultado_\d{8}\.txt: falta\r?\n') (Cola $r.Salida)
  Igual 'el detalle de 2 casos del grupo 1 y uno de cada uno de los otros dos' 4 @([regex]::Matches($r.Salida, 'distinto: cargaJob/caso-\d\d \(')).Count
}

$Pruebas['m50 (b5) Get-CausaNormal: numeros de 2 cifras o mas, rutas, fechas y horas, el nombre del caso, @hex y 200 letras'] = {
  $f = Join-Path $Dir 'm50-causa.ps1'
  $cuerpo = @'
$Inv = [System.Globalization.CultureInfo]::InvariantCulture
$RutasCopia = @('/copia/x')
$Hoy = @([datetime]'2026-11-20')
function Prueba([string]$Id, [string]$Causa, [string]$Caso = 'caso-07') { 'R ' + $Id + ' ' + (Get-CausaNormal $Causa $Caso) }
Prueba 'numeros' 'Error 5 de 12 en la linea 345 (1234)'
Prueba 'caso' 'no hay datos para caso-07 y para caso-07'
Prueba 'rutas' 'No existe /home/ana/datos/in.csv ni C:\datos\in.csv ni \\srv\comp\x'
Prueba 'ruta-corta' 'En /tmp no hay nada y a/b si'
Prueba 'ruta-jvm' 'java.lang.NoClassDefFoundError: org/x/a/ClaseA y (org/x/b/ClaseB)'
Prueba 'ruta-ejemplos' 'En C:\datos\x\caso.txt y /tmp/a/b y C:/datos/x y file:///x/y'
Prueba 'copia' 'No existe /copia/x/src/main/A.java'
Prueba 'hex' 'Bean@1a2b3c4d no es Bean@FF00AA ni ana@acme.com'
Prueba 'fechas' 'En 2026-11-20 10:20:30 y a las 10:20:30 y el 2026-11-18'
Prueba 'sin-nada' 'java.lang.IllegalStateException: sin correo'
Prueba 'clase' 'java.lang.TypeNotPresentException: Type org.springframework.kafka.support.micrometer.KafkaRecordReceiverContext not present'
Prueba 'larga' ('x' * 250)
Prueba 'vacia' ''
'@
  [System.IO.File]::WriteAllText($f, ((Texto-De-Funciones $Script @('Get-CausaNormal', 'Get-Normal')) + "`n" + $cuerpo))
  $r = Lanzar $f @()
  $v = @{}
  foreach ($l in @($r.Salida -split "`n")) { if ($l -cmatch '^R (\S+) ?(.*)$') { $v[$Matches[1]] = $Matches[2].TrimEnd() } }
  Igual 'los numeros de 2 cifras o mas, a <n>; el de una, no' 'Error 5 de <n> en la linea <n> (<n>)' $v['numeros']
  Igual 'el nombre del caso, a <caso>' 'no hay datos para <caso> y para <caso>' $v['caso']
  Igual 'las rutas (con / o con \, y mas de un segmento), a <ruta>' 'No existe <ruta> ni <ruta> ni <ruta>' $v['rutas']
  Igual 'una sola barra al principio (/tmp) no es una ruta, ni a/b: sin \ y sin barra inicial no es una ruta (cambia a proposito: antes a/b salia <ruta>)' 'En /tmp no hay nada y a/b si' $v['ruta-corta']
  Igual 'el nombre de una clase con barras (NoClassDefFoundError) no es una ruta: dos clases distintas, dos causas' 'java.lang.NoClassDefFoundError: org/x/a/ClaseA y (org/x/b/ClaseB)' $v['ruta-jvm']
  Igual 'es ruta C:\... y C:/... (unidad), /a/b, y file:' 'En <ruta> y <ruta> y <ruta> y <ruta>' $v['ruta-ejemplos']
  Igual 'la ruta de la copia (<copia>) con lo que sigue, una sola ruta' 'No existe <ruta>' $v['copia']
  Igual '@ y hexadecimal, a @<id>; un correo no' 'Bean@<id> no es Bean@<id> ni ana@acme.com' $v['hex']
  Igual 'fechas y horas como Get-Normal: la de hoy con hora, a <hoy:formato><hora>; la hora suelta, a <hora>; otra fecha, sus numeros' 'En <hoy:yyyy-MM-dd><hora> y a las <hora> y el <n>-<n>-<n>' $v['fechas']
  Igual 'sin nada que cambiar, igual' 'java.lang.IllegalStateException: sin correo' $v['sin-nada']
  Igual 'la causa de un TypeNotPresentException no cambia' 'java.lang.TypeNotPresentException: Type org.springframework.kafka.support.micrometer.KafkaRecordReceiverContext not present' $v['clase']
  Igual 'recortada a 200 letras' (('x' * 200)) $v['larga']
  Igual 'una causa vacia, vacia' '' $v['vacia']
}

$Pruebas['m50 (b6) Get-Grupos con resultados inventados: tipos de diferencia, un original que tambien falla, sin estado.txt, el orden y los empates'] = {
  $f = Join-Path $Dir 'm50-grupos.ps1'
  $cuerpo = @'
$Inv = [System.Globalization.CultureInfo]::InvariantCulture
$RutasCopia = @()
$Hoy = @([datetime]'2026-11-20')
function Fallo-M([string]$Estado, [string]$Causa, [string]$Lado = 'migrado') { [ordered]@{ lado = $Lado; estado = $Estado; causa = $Causa } }
function Dif([string]$Clave, [string]$Original, [string]$Migrado, [bool]$NoGuardado = $false) {
  $d = [ordered]@{ fichero = $Clave; clave = $Clave; lineas = 1; linea = 1; original = $Original; migrado = $Migrado; nota = '' }
  if ($NoGuardado) { $d.noGuardado = $true }
  return $d
}
function Caso-M([string]$Job, [string]$Caso, [string]$Resultado, $Fallos = @(), $Dif = @()) {
  [ordered]@{ job = $Job; caso = $Caso; titulo = 't'; resultado = $Resultado; motivo = ''; diferencias = @($Dif); fallos = @($Fallos) }
}
$res = @(
  (Caso-M 'remesaJob' 'caso-02' 'distinto' @() @((Dif 'b.txt' 'x' '(no esta)'), (Dif 'a.txt' '(no esta)' 'y'), (Dif 'c.txt' 'x' 'y'), (Dif 'd.txt' 'no se ha podido guardar: ruta' '(guardado)' $true))),
  (Caso-M 'cargaJob' 'caso-02' 'distinto' @() @((Dif 'c.txt' 'x' 'y'), (Dif 'a.txt' '(no esta)' 'y'), (Dif 'b.txt' 'x' '(no esta)'), (Dif 'd.txt' 'no se ha podido guardar: ruta' '(guardado)' $true))),
  (Caso-M 'cargaJob' 'caso-01' 'igual'),
  (Caso-M 'cargaJob' 'caso-03' 'distinto' @((Fallo-M 'EXCEPCION' 'org.h2.X: Table "T_X" not found' 'original')) @((Dif 'e.txt' 'x' 'y'))),
  (Caso-M 'cargaJob' 'caso-04' 'distinto' @((Fallo-M 'FAILED' 'java.lang.A: uno 12'), (Fallo-M 'FAILED' 'java.lang.A: uno 99' 'original')) @((Dif 'e.txt' 'x' 'y'))),
  (Caso-M 'cargaJob' 'caso-05' 'distinto' @((Fallo-M 'sin estado.txt' '')) @((Dif 'estado.txt' 'estado=COMPLETED' '(no esta)'))),
  (Caso-M 'cargaJob' 'caso-06' 'distinto' @((Fallo-M 'FAILED' 'java.lang.A: uno 77')) @((Dif 'e.txt' 'x' 'y'))),
  (Caso-M 'cargaJob' 'caso-07' 'distinto' @((Fallo-M 'EXCEPCION' 'java.lang.B: dos')) @((Dif 'e.txt' 'x' 'y'))),
  (Caso-M 'cargaJob' 'caso-08' 'no determinista'),
  (Caso-M 'cargaJob' 'caso-09' 'distinto' @((Fallo-M 'FAILED' 'java.lang.A: uno 55')) @((Dif 'f.txt' 'x' 'y'))),
  (Caso-M 'cargaJob' 'caso-10' 'distinto' @((Fallo-M 'FAILED' 'java.lang.A: uno 31')) @((Dif 'g.txt' 'x' 'y')))
)
foreach ($g in @(Get-Grupos $res)) { 'G ' + $g.numero + ' ## ' + $g.tipo + ' ## ' + $g.firma + ' ## ' + (@($g.casos) -join ',') + ' ## ' + $g.descripcion }
'@
  [System.IO.File]::WriteAllText($f, ((Texto-De-Funciones $Script @('Get-Grupos', 'Get-TipoDif', 'Format-Carpetas', 'Get-CausaNormal', 'Get-Normal', 'Format-Fallo', 'Sort-Ordinal')) + "`n" + $cuerpo))
  $r = Lanzar $f @()
  $g = @($r.Salida -split "`n" | Where-Object { $_ -cmatch '^G ' } | ForEach-Object { $_.TrimEnd().Substring(2) })
  Igual 'cinco grupos' 5 $g.Count
  Igual '1: de fallo, los 3 casos con java.lang.A (el numero se normaliza; sus diferencias de fichero no cuentan), por job y caso; la cabecera, con la causa del primero sin normalizar' '1 ## fallo ## fallo|FAILED|java.lang.A: uno <n> ## cargaJob/caso-06,cargaJob/caso-09,cargaJob/caso-10 ## 3 casos distintos, el migrado acaba FAILED: java.lang.A: uno 77' $g[0]
  Igual '2: de fallo, 1 caso (EXCEPCION); a igualdad de casos, por la firma en orden ordinal' '2 ## fallo ## fallo|EXCEPCION|java.lang.B: dos ## cargaJob/caso-07 ## 1 caso distinto, el migrado acaba EXCEPCION: java.lang.B: dos' $g[1]
  Igual '3: de fallo, sin estado.txt y sin causa' '3 ## fallo ## fallo|sin estado.txt| ## cargaJob/caso-05 ## 1 caso distinto, el migrado no deja estado.txt' $g[2]
  Igual '4: de fichero (2 casos, el mismo de dos jobs): la lista ordenada de clave:tipo (sobra, falta, contenido, noGuardado) y la cabecera con el primero y los que faltan' '4 ## fichero ## fichero|a.txt:sobra|b.txt:falta|c.txt:contenido|d.txt:noGuardado ## cargaJob/caso-02,remesaJob/caso-02 ## 2 casos distintos, en a.txt: sobra y 3 ficheros mas' $g[3]
  Igual '5: de fichero: un caso con fallo del migrado y del original, y otro con fallo solo del original, no son de fallo' '5 ## fichero ## fichero|e.txt:contenido ## cargaJob/caso-03,cargaJob/caso-04 ## 2 casos distintos, en e.txt: contenido' $g[4]
}

$Pruebas['m50 (b7) dos clases distintas que faltan (NoClassDefFoundError con barras): dos grupos, no uno'] = {
  $f = Join-Path $Dir 'm50-clases.ps1'
  $cuerpo = @'
$Inv = [System.Globalization.CultureInfo]::InvariantCulture
$RutasCopia = @()
$Hoy = @([datetime]'2026-11-20')
function Caso-M([string]$Caso, [string]$Causa) {
  [ordered]@{ job = 'cargaJob'; caso = $Caso; titulo = 't'; resultado = 'distinto'; motivo = ''; diferencias = @(); fallos = @([ordered]@{ lado = 'migrado'; estado = 'FAILED'; causa = $Causa }) }
}
$res = @((Caso-M 'caso-01' 'java.lang.NoClassDefFoundError: org/x/a/ClaseA'), (Caso-M 'caso-02' 'java.lang.NoClassDefFoundError: org/x/a/ClaseB'), (Caso-M 'caso-03' 'java.lang.NoClassDefFoundError: org/x/a/ClaseA'))
foreach ($g in @(Get-Grupos $res)) { 'G ' + $g.numero + ' ## ' + $g.firma + ' ## ' + (@($g.casos) -join ',') }
'@
  [System.IO.File]::WriteAllText($f, ((Texto-De-Funciones $Script @('Get-Grupos', 'Get-TipoDif', 'Format-Carpetas', 'Get-CausaNormal', 'Get-Normal', 'Format-Fallo', 'Sort-Ordinal')) + "`n" + $cuerpo))
  $r = Lanzar $f @()
  $g = @($r.Salida -split "`n" | Where-Object { $_ -cmatch '^G ' } | ForEach-Object { $_.TrimEnd().Substring(2) })
  Igual 'dos grupos' 2 $g.Count
  Igual 'el 1: la clase A, con sus dos casos, y la barra de la clase en la firma' '1 ## fallo|FAILED|java.lang.NoClassDefFoundError: org/x/a/ClaseA ## cargaJob/caso-01,cargaJob/caso-03' $g[0]
  Igual 'el 2: la clase B' '2 ## fallo|FAILED|java.lang.NoClassDefFoundError: org/x/a/ClaseB ## cargaJob/caso-02' $g[1]
}

$Pruebas['m50 (c) causa de dependencias (TypeNotPresentException de org.springframework.kafka): un solo dependency:tree aunque haya dos grupos, dependencias.txt guardado y el hecho con las lineas del prefijo'] = {
  $e = Escenario-M50 'm50-c' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00'); remesaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba-M50 $e 'tipo:^cargaJob/caso-;tipo2:^remesaJob/caso-'
  Igual 'sale con 2' 2 $r.Codigo
  Igual 'un solo dependency:tree en todo el lanzamiento (dos grupos de dependencias)' 1 (Arboles-M50 $e)
  Comprueba 'y en la copia del migrado' (@(Mavens-Con $e ('^' + [regex]::Escape($e.CopiaMig + '|') + '.*dependency:tree')).Count -eq 1) ''
  $dep = Get-Ruta $e.Local 'dependencias.txt'
  Comprueba 'prueba-local\dependencias.txt guardado, con el arbol' ((Test-Path -LiteralPath $dep) -and (Lee $e.Local 'dependencias.txt').Contains('org.springframework.kafka:spring-kafka:jar:2.9.0:compile')) ''
  $g = @(Grupos-M50 $e)
  Igual 'dos grupos de fallo' 'fallo,fallo' ((@($g | ForEach-Object { $_.tipo })) -join ',')
  Comprueba 'el 1 (empatan a 2 casos; la firma de ClassNotFound va antes) es el de io.micrometer' ($g[0].firma -match 'ClassNotFoundException') $g[0].firma
  $kafka = $g | Where-Object { $_.firma -match 'TypeNotPresentException' }
  $esperado = 'de dependencias: falta una clase o un metodo de org.springframework.kafka. En el arbol del migrado: org.springframework.kafka:spring-kafka:jar:2.9.0:compile; org.springframework.kafka:spring-kafka-test:jar:2.9.0:test; org.springframework.kafka:spring-kafka-streams:jar:2.9.0:test; org.springframework.kafka:spring-kafka-extras:jar:2.9.0:test; org.springframework.kafka:spring-kafka-bom:jar:2.9.0:test. Arbol completo: ' + $dep
  Igual 'el hecho del grupo de kafka: el prefijo de 3 segmentos, 5 lineas como mucho, sin los caracteres del arbol ni [INFO]' $esperado ((@($kafka.hechos) -join '|'))
  $micro = $g | Where-Object { $_.firma -match 'ClassNotFoundException' }
  Igual 'el del otro grupo: sin lineas con io.micrometer.observation, se prueba con los 2 primeros segmentos' ('de dependencias: falta una clase o un metodo de io.micrometer. En el arbol del migrado: io.micrometer:micrometer-observation:jar:1.9.0:compile. Arbol completo: ' + $dep) ((@($micro.hechos) -join '|'))
  Comprueba 'la consola lleva el hecho de kafka, con medido:' ($r.Salida.Contains('medido: ' + $esperado)) (Cola $r.Salida)
}

$Pruebas['m50 (c2) otra causa (IllegalStateException): ningun dependency:tree, sin dependencias.txt y sin hecho de dependencias'] = {
  $e = Escenario-M50 'm50-c2' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba-M50 $e 'otra:/caso-'
  Igual 'sale con 2' 2 $r.Codigo
  Igual 'ningun dependency:tree' 0 (Arboles-M50 $e)
  Comprueba 'ni dependencias.txt' (-not (Test-Path -LiteralPath (Get-Ruta $e.Local 'dependencias.txt'))) ''
  Igual 'el grupo sin hechos' 0 @((Grupos-M50 $e)[0].hechos).Count
  Comprueba 'la consola no dice medido:' ($r.Salida -notmatch 'medido:') (Cola $r.Salida)
}

$Pruebas['m50 (c3) dependency:tree falla: el hecho dice sin arbol, no hay dependencias.txt y el lanzamiento acaba igual'] = {
  $e = Escenario-M50 'm50-c3' ([ordered]@{ cargaJob = @('importe=10.00') ; remesaJob = @('importe=10.00') })
  $r = Prueba-M50 $e 'tipo:^cargaJob/caso-;tipo2:^remesaJob/caso-' @() @{ M50_ARBOL = 'falla' }
  Igual 'sale con 2 (los casos distintos)' 2 $r.Codigo
  Igual 'un solo intento de dependency:tree, aunque falle' 1 (Arboles-M50 $e)
  Comprueba 'sin dependencias.txt' (-not (Test-Path -LiteralPath (Get-Ruta $e.Local 'dependencias.txt'))) ''
  $g = @(Grupos-M50 $e)
  Igual 'los dos grupos llevan el hecho, con el motivo corto' 2 @($g | Where-Object { @($_.hechos).Count -eq 1 -and $_.hechos[0] -match '^de dependencias, sin arbol: .*Could not resolve dependencies' }).Count
  Comprueba 'prueba-local.json se escribio y la consola lo dice' ((Test-Path -LiteralPath $e.Json) -and $r.Salida -match 'medido: de dependencias, sin arbol: ') (Cola $r.Salida)
}

# Un lanzamiento sin guiones (todos iguales) y, a partir del prueba-local.json que deja, uno por cada $Variante (un bloque que cambia ese json antes), con el guion 'otra'.
$Pruebas['m50 (d) cambio con el test: mismo codigoMigrado, otro hashArnesMigrado y casos antes iguales: sale el hecho; con otro codigo, el mismo hash, un json sin esos campos o menos de la mitad iguales, no'] = {
  $e = Escenario-M50 'm50-d' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba-M50 $e ''
  Igual 'el primero sale con 0' 0 $r.Codigo
  $base = Lee-Json $e.Json
  Comprueba 'prueba-local.json guarda codigoMigrado y hashArnesMigrado (8 hex)' (("$($base.codigoMigrado)".Length -gt 8) -and ("$($base.hashArnesMigrado)" -match '^[0-9a-f]{8}$')) "$($base.codigoMigrado) / $($base.hashArnesMigrado)"
  $hechoCon = 'cambio con el test: {0} de {1} casos eran iguales con el test del migrado anterior y el mismo codigo'
  $variante = {
    param([string]$Que, [scriptblock]$Cambia, [string]$Esperado)
    $j = $base | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    & $Cambia $j
    [System.IO.File]::WriteAllText($e.Json, (ConvertTo-Json -InputObject $j -Depth 8))
    $r = Prueba-M50 $e 'otra:/caso-'
    Igual "$Que : sale con 2" 2 $r.Codigo
    $g = @(Grupos-M50 $e)
    Igual "$Que : un grupo" 1 $g.Count
    Igual "$Que : hechos" $Esperado ((@($g[0].hechos)) -join '|')
    if ($Esperado) { Comprueba "$Que : la consola lo dice" ($r.Salida.Contains("medido: $Esperado")) (Cola $r.Salida) }
    else { Comprueba "$Que : la consola no dice medido:" ($r.Salida -notmatch 'medido:') (Cola $r.Salida) }
  }
  & $variante 'otro hash, mismo codigo, los dos casos eran iguales' { param($j) $j.hashArnesMigrado = '00000000' } ($hechoCon -f 2, 2)
  & $variante 'el mismo hash' { param($j) } ''
  & $variante 'otro codigo del migrado' { param($j) $j.hashArnesMigrado = '00000000'; $j.codigoMigrado = 'otro-codigo' } ''
  & $variante 'un json sin esos campos (el primer lanzamiento tras este cambio)' { param($j) $j.PSObject.Properties.Remove('hashArnesMigrado'); $j.PSObject.Properties.Remove('codigoMigrado') } ''
  & $variante 'solo la mitad de los casos eran iguales (1 de 2)' { param($j) $j.hashArnesMigrado = '00000000'; $j.casos[0].resultado = 'distinto' } ($hechoCon -f 1, 2)
  & $variante 'ninguno era igual (0 de 2)' { param($j) $j.hashArnesMigrado = '00000000'; foreach ($c in @($j.casos)) { $c.resultado = 'distinto' } } ''
}

$Pruebas['m50 (e) datos/prueba-local-grupos.jsonl: una linea por grupo y lanzamiento, y crece al relanzar'] = {
  $e = Escenario-M50 'm50-e' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=10.00', 'importe=10.00') })
  $jsonl = Get-Ruta (Split-Path -Parent $e.Json) 'prueba-local-grupos.jsonl'
  $r = Prueba-M50 $e 'otra:/caso-0[12]$;tipo:/caso-03$'
  Igual 'sale con 2' 2 $r.Codigo
  $l = @([System.IO.File]::ReadAllLines($jsonl) | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
  Igual 'dos lineas, una por grupo' 2 $l.Count
  Igual 'cada una con numero, tipo y N casos' '1|fallo,2|fallo|2,1' ((($l | ForEach-Object { "$($_.numero)|$($_.tipo)" }) -join ',') + '|' + (($l | ForEach-Object { "$($_.casos)" }) -join ','))
  Comprueba 'la firma es la del json' ($l[0].firma -ceq (Grupos-M50 $e)[0].firma -and $l[1].firma -ceq (Grupos-M50 $e)[1].firma) ''
  $crudo = @([System.IO.File]::ReadAllLines($jsonl) | Where-Object { $_.Trim() })
  Comprueba 'con la fecha (ISO) y los hechos como lista' ($crudo[0] -match '"fecha":"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d"' -and $crudo[0] -match '"hechos":\[\]') $crudo[0]
  Igual 'el segundo grupo lleva el hecho de dependencias' 1 @($l[1].hechos).Count
  $r = Prueba-M50 $e 'otra:/caso-0[12]$;tipo:/caso-03$'
  $l = @([System.IO.File]::ReadAllLines($jsonl) | Where-Object { $_.Trim() })
  Igual 'al relanzar, 4 lineas: se anade, no se pisa' 4 $l.Count
  Igual 'la misma firma las dos veces' (($l[0] | ConvertFrom-Json).firma) (($l[2] | ConvertFrom-Json).firma)
}

$Pruebas['m50 (f) la linea de -RehacerArnes sale dentro del bloque del grupo, una vez por job cuyo migrado no arranca en ningun caso, con el mismo texto de siempre'] = {
  $e = Escenario-M48 'm50-f' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00'); remesaJob = @('importe=10.00', 'importe=20.00'); tarifaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba-M48 $e 'excepcion-mig:^cargaJob/caso-;excepcion-mig:^remesaJob/caso-01$;excepcion-mig:^tarifaJob/caso-01$;excepcion-ambos:^tarifaJob/caso-02$'
  Igual 'sale con 2' 2 $r.Codigo
  $linea = 'El migrado no arranca el job cargaJob en ningun caso (BeanCreationException: java.lang.IllegalStateException: sin correo). Casi siempre es el test del migrado, no el codigo: relanza con -RehacerArnes.'
  Comprueba 'la linea de cargaJob, igual que antes' ($r.Salida.Contains($linea)) (Cola $r.Salida)
  Comprueba 'dentro del bloque del grupo 1: despues de su cabecera y antes del detalle de sus casos' ($r.Salida -cmatch '(?s)Grupo 1: 4 casos distintos, el migrado acaba EXCEPCION: .*?El migrado no arranca el job cargaJob.*?distinto: cargaJob/caso-01 \(') (Cola $r.Salida)
  Igual 'y solo una linea de esas' 1 (Veces-M50 $r.Salida 'El migrado no arranca el job')
  Comprueba 'remesaJob (falla un solo caso) y tarifaJob (el original tambien falla en otro) no la llevan' ($r.Salida -notmatch 'no arranca el job (remesaJob|tarifaJob)') (Cola $r.Salida)
}

$Pruebas['m50 (g) con -Job los grupos son solo de este lanzamiento: los casos de los otros jobs que se conservan no llevan grupo'] = {
  $e = Escenario-M50 'm50-g' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=10.00'); remesaJob = @('importe=10.00', 'importe=10.00') })
  $r = Prueba-M50 $e 'otra:/caso-'
  Igual 'el primero (todos los jobs) sale con 2' 2 $r.Codigo
  Igual 'con un grupo de 4 casos' 4 @((Grupos-M50 $e)[0].casos).Count
  $r = Prueba-M50 $e 'otra:/caso-' @('-Job', 'cargaJob')
  Igual 'con -Job sale con 2' 2 $r.Codigo
  $o = Lee-Json $e.Json
  Igual 'prueba-local.json sigue con los casos de los dos jobs' 4 @($o.casos).Count
  Igual 'pero el grupo es solo de cargaJob' 'cargaJob/caso-01,cargaJob/caso-02' ((@($o.grupos[0].casos)) -join ',')
  Igual 'cargaJob lleva el grupo 1' '1,1' (((Caso $e 'cargaJob' 'caso-01').grupo, (Caso $e 'cargaJob' 'caso-02').grupo) -join ',')
  Igual 'remesaJob (de antes) no lleva grupo: apuntaria a otro grupo' 0 @((Caso $e 'remesaJob' 'caso-01').PSObject.Properties | Where-Object { $_.Name -eq 'grupo' }).Count
}

# ===================== M52: la causa de un caso nunca sale de una linea de aviso; sin causa, se dice donde esta el registro =====================
# m50-mvn.ps1 deja, segun el guion de RESCATE_M50, un migrado FAILED y en la salida de Maven lineas de log con su nivel (avisos de Spring con una
# TypeNotPresentException, un [ERROR] con una NullPointerException, lineas JSON...). Los nombres son inventados (com.acme, pasoDoce, cargaJob).

$NpeCausa52 = 'java.lang.NullPointerException: Cannot invoke "org.springframework.batch.core.step.StepExecution.getExecutionContext()" because "this.stepExecution" is null'

# El fallo del migrado de un caso (de prueba-local.json): lado, estado, causa y registro.
function Fallo-M52($E, [string]$Job, [string]$Caso) { return @((Caso $E $Job $Caso).fallos | Where-Object { $_.lado -ceq 'migrado' })[0] }

# La ruta de registro que dice la consola ('registros\mvn-<n>-<que>.log'), la primera que sale.
function Registro-Consola-M52([string]$Salida) { return [regex]::Match($Salida, 'sin causa en la salida de Maven: mira (registros\\mvn-[^\s)]+\.log)').Groups[1].Value }

$Pruebas['m52 (a) avisos de Spring con TypeNotPresentException, un INFO y un [ERROR] con NullPointerException: la causa es la del ERROR, en la consola y en el JSON'] = {
  $e = Escenario-M50 'm52-a' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M50 $e 'avisos-error'
  Igual 'sale con 2' 2 $r.Codigo
  $f = Fallo-M52 $e 'cargaJob' 'caso-01'
  Igual 'el fallo del migrado: FAILED, con la causa del NullPointerException (de la clase, sin el [ERROR] ni la hora)' "FAILED|$NpeCausa52" "$($f.estado)|$($f.causa)"
  Igual 'dos veces en la consola (la cabecera y el detalle)' 2 (Veces-M50 $r.Salida "el migrado acaba FAILED: $NpeCausa52")
  Comprueba 'la consola no dice TypeNotPresentException' ($r.Salida -notmatch 'TypeNotPresentException') (Cola $r.Salida)
}

$Pruebas['m52 (a2) la misma causa en 3 casos: un solo grupo, con la firma del NullPointerException, y ningun dependency:tree'] = {
  $e = Escenario-M50 'm52-a2' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00', 'importe=30.00') })
  $r = Prueba-M50 $e 'avisos-error'
  Igual 'sale con 2' 2 $r.Codigo
  $g = @(Grupos-M50 $e)
  Igual 'un grupo' 1 $g.Count
  Igual 'con la firma del NullPointerException' "fallo|FAILED|$NpeCausa52" "$($g[0].firma)"
  Igual 'con los 3 casos' 3 @($g[0].casos).Count
  Igual 'ningun dependency:tree (el hecho de dependencias no salta)' 0 (Arboles-M50 $e)
  Comprueba 'ni dependencias.txt' (-not (Test-Path -LiteralPath (Get-Ruta $e.Local 'dependencias.txt'))) ''
  Igual 'el grupo sin hechos' 0 @($g[0].hechos).Count
  Comprueba 'la consola no dice medido:' ($r.Salida -notmatch 'medido:') (Cola $r.Salida)
}

$Pruebas['m52 (b) solo avisos con excepciones y ningun ERROR: sin causa; la consola dice donde esta el registro de Maven del caso y ese fichero existe'] = {
  $e = Escenario-M50 'm52-b' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M50 $e 'solo-avisos'
  Igual 'sale con 2' 2 $r.Codigo
  $f = Fallo-M52 $e 'cargaJob' 'caso-01'
  Igual 'el fallo del migrado: FAILED y causa vacia' 'FAILED|' "$($f.estado)|$($f.causa)"
  Comprueba 'la consola dice sin causa en la salida de Maven: mira registros\mvn-' ($r.Salida.Contains('sin causa en la salida de Maven: mira registros\mvn-')) (Cola $r.Salida)
  $reg = Registro-Consola-M52 $r.Salida
  Comprueba 'con el nombre del fichero de este caso (mvn-<n>-migrado-cargaJob-caso-01.log)' ($reg -cmatch '^registros\\mvn-\d+-migrado-cargaJob-caso-01\.log$') $reg
  $ruta = Get-Ruta $e.Local ('registros/' + $reg.Substring('registros\'.Length))
  Comprueba 'ese fichero existe en la carpeta prueba-local' (Test-Path -LiteralPath $ruta) $ruta
  Comprueba 'y es la salida de Maven de ese caso (lleva los avisos)' ((Test-Path -LiteralPath $ruta) -and ([System.IO.File]::ReadAllText($ruta)).Contains('com.acme.kafka.FaltaDos')) $ruta
  Igual 'dos veces en la consola (la cabecera del grupo y el detalle del caso)' 2 (Veces-M50 $r.Salida "el migrado acaba FAILED: sin causa en la salida de Maven: mira $reg")
  Comprueba 'la consola no dice TypeNotPresentException' ($r.Salida -notmatch 'TypeNotPresentException') (Cola $r.Salida)
  $g = @(Grupos-M50 $e)
  Igual 'un grupo, con la firma de siempre con causa vacia (la ruta no entra en la firma)' 'fallo|FAILED|' "$($g[0].firma)"
  Igual 'ningun dependency:tree' 0 (Arboles-M50 $e)
}

$Pruebas['m52 (b2) sin causa en 3 casos: un solo grupo (la ruta del registro no entra en la firma) y la cabecera apunta al registro del primero'] = {
  $e = Escenario-M50 'm52-b2' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00', 'importe=30.00') })
  $r = Prueba-M50 $e 'solo-avisos'
  Igual 'sale con 2' 2 $r.Codigo
  $g = @(Grupos-M50 $e)
  Igual 'un grupo, de fallo, con los 3 casos y la firma con causa vacia' '1|fallo|fallo|FAILED||3' "$(@($g).Count)|$($g[0].tipo)|$($g[0].firma)|$(@($g[0].casos).Count)"
  Comprueba 'la descripcion del grupo (cabecera) lleva el registro del primer caso' ("$($g[0].descripcion)" -cmatch '^3 casos distintos, el migrado acaba FAILED: sin causa en la salida de Maven: mira registros\\mvn-\d+-migrado-cargaJob-caso-01\.log$') "$($g[0].descripcion)"
}

$Pruebas['m52 (c) un aviso WARN con Caused by dentro y, despues, una linea sin nivel con IllegalStateException: la causa es la de IllegalStateException'] = {
  $e = Escenario-M50 'm52-c' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M50 $e 'aviso-caused'
  Igual 'sale con 2' 2 $r.Codigo
  Igual 'la causa' 'java.lang.IllegalStateException: sin datos' "$((Fallo-M52 $e 'cargaJob' 'caso-01').causa)"
  Comprueba 'la consola no dice ClassNotFoundException ni sin causa' ($r.Salida -notmatch 'ClassNotFoundException' -and $r.Salida -notmatch 'sin causa en la salida') (Cola $r.Salida)
}

$Pruebas['m52 (d) linea JSON con logLevel ERROR y una excepcion en log: es la causa; con logLevel WARN, no'] = {
  $e = Escenario-M50 'm52-d' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba-M50 $e 'json-error:/caso-01$;json-warn:/caso-02$'
  Igual 'sale con 2' 2 $r.Codigo
  $error52 = (Fallo-M52 $e 'cargaJob' 'caso-01').causa
  Comprueba 'caso-01 (ERROR): la causa es la IllegalArgumentException, desde la clase' ("$error52".StartsWith('java.lang.IllegalArgumentException: importe no valido')) "$error52"
  $warn52 = Fallo-M52 $e 'cargaJob' 'caso-02'
  Igual 'caso-02 (WARN): sin causa' '' "$($warn52.causa)"
  Comprueba 'y la consola dice donde esta su registro' ($r.Salida -cmatch 'sin causa en la salida de Maven: mira registros\\mvn-\d+-migrado-cargaJob-caso-02\.log') (Cola $r.Salida)
}

$Pruebas['m52 (e) [ERROR] que dice INFO.txt antes de una FileNotFoundException: es la causa (el primer nivel es ERROR)'] = {
  $e = Escenario-M50 'm52-e' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M50 $e 'error-info'
  Igual 'sale con 2' 2 $r.Codigo
  Igual 'la causa' 'java.io.FileNotFoundException: INFO.txt' "$((Fallo-M52 $e 'cargaJob' 'caso-01').causa)"
}

$Pruebas['m52 (f) registro en el JSON de un fallo con causa y de uno sin causa: la ruta relativa de su mvn-*.log, que existe y es el de ese caso'] = {
  $e = Escenario-M50 'm52-f' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba-M50 $e 'avisos-error:/caso-01$;solo-avisos:/caso-02$'
  Igual 'sale con 2' 2 $r.Codigo
  $con = Fallo-M52 $e 'cargaJob' 'caso-01'
  $sin = Fallo-M52 $e 'cargaJob' 'caso-02'
  Comprueba 'el de caso-01 (con causa) lleva registro: registros\mvn-<n>-migrado-cargaJob-caso-01.log' ("$($con.registro)" -cmatch '^registros\\mvn-\d+-migrado-cargaJob-caso-01\.log$') "$($con.registro)"
  Comprueba 'el de caso-02 (sin causa) lleva el suyo' ("$($sin.registro)" -cmatch '^registros\\mvn-\d+-migrado-cargaJob-caso-02\.log$') "$($sin.registro)"
  Comprueba 'el de caso-01 existe y lleva el NullPointerException de su caso' ((Lee $e.Local ('registros/' + "$($con.registro)".Substring('registros\'.Length))).Contains('StepExecution.getExecutionContext()')) "$($con.registro)"
  Comprueba 'el de caso-02 existe y no lo lleva' ((Test-Path -LiteralPath (Get-Ruta $e.Local ('registros/' + "$($sin.registro)".Substring('registros\'.Length)))) -and -not (Lee $e.Local ('registros/' + "$($sin.registro)".Substring('registros\'.Length))).Contains('StepExecution.getExecutionContext()')) "$($sin.registro)"
  Comprueba 'la consola de caso-01 (con causa) no dice sin causa' (-not $r.Salida.Contains('sin causa en la salida de Maven: mira ' + $con.registro)) (Cola $r.Salida)
  Comprueba 'la del caso sin causa dice el suyo' ($r.Salida.Contains('sin causa en la salida de Maven: mira ' + $sin.registro)) (Cola $r.Salida)
}

# Get-CausaMaven con salidas de Maven inventadas (sin informes de surefire: la carpeta no existe), una fila por salida: 'R <id> <causa>'.
$Pruebas['m52 (h) Get-CausaMaven: el primer nivel antes de la causa (TRACE, DEBUG, INFO, WARN, WARNING no dan causa; sin nivel, ERROR, FATAL y SEVERE, si; en mayusculas y entero)'] = {
  $f = Join-Path $Dir 'm52-niveles.ps1'
  $cuerpo = @'
$ErrorActionPreference = 'Stop'
$Desde = [datetime]'2026-11-20'
function Fila([string]$Id, [string[]]$Salida) { 'R ' + $Id + ' ' + (Get-CausaMaven (Join-Path $Raiz 'no-existe') $Desde $Salida) }
$X = 'java.lang.IllegalStateException: uno'
Fila 'sin-nivel' @($X)
Fila 'error-maven' @("[ERROR] $X")
Fila 'fatal' @("FATAL $X")
Fila 'severe' @("SEVERE: $X")
Fila 'warn-spring' @("2026-11-20T13:53:58.154+01:00  WARN 2192 --- [app] [main] o.s.c.a.MergedAnnotation : Failed to introspect $X")
Fila 'warn-logback' @("[WARN ] 2026-11-20 02:00:17.145 [main] MergedAnnotation - $X")
Fila 'warning-maven' @("[WARNING] $X")
Fila 'warning-java-util' @("WARNING: $X")
Fila 'info-maven' @("[INFO] $X")
Fila 'debug' @("DEBUG $X")
Fila 'trace' @("[TRACE] $X")
Fila 'json-info' @('{"logLevel":"INFO","log":"x java.lang.IllegalStateException: uno","error":"false"}')
Fila 'json-warn' @('{"logLevel":"WARN","log":"x java.lang.IllegalStateException: uno","error":"false"}')
Fila 'json-error' @('{"logLevel":"ERROR","log":"x java.lang.IllegalStateException: uno"}')
Fila 'minuscula' @("warn $X")
Fila 'pegado-letra' @("AWARN $X")
Fila 'pegado-cifra' @("WARN2 $X")
Fila 'pegado-guion-bajo' @("WARN_MODE $X")
Fila 'pegado-punto' @("INFO.txt $X")
Fila 'pegado-dolar' @("INFO`$1 $X")
Fila 'error-y-luego-info' @("[ERROR] leyendo INFO java.io.FileNotFoundException: INFO.txt")
Fila 'info-y-luego-error' @("[INFO] ERROR $X")
Fila 'nivel-despues-de-la-causa' @("$X WARN")
Fila 'caused-en-warn' @("[WARN ] aviso Caused by: java.lang.A: uno", "[INFO] Caused by: java.lang.B: dos")
Fila 'caused-sin-nivel-despues-de-warn' @("[WARN ] aviso Caused by: java.lang.A: uno", "    Caused by: java.lang.B: dos", "[WARN ] otro Caused by: java.lang.C: tres")
Fila 'caused-con-error' @("[ERROR] Caused by: java.lang.A: uno", "[WARN ] Caused by: java.lang.B: dos")
Fila 'caused-gana-a-la-excepcion' @($X, "Caused by: java.lang.B: dos")
Fila 'excepcion-tras-aviso' @("[WARN ] aviso $X", "[ERROR] otra java.lang.IllegalArgumentException: dos")
Fila 'recorte-300' @('[ERROR] x java.lang.IllegalStateException: ' + ('a' * 400))
Fila 'caused-nivel-en-su-mensaje' @("Caused by: java.lang.A: modo WARN apagado")
'@
  [System.IO.File]::WriteAllText($f, ('param([string]$Raiz)' + "`n" + (Texto-De-Funciones $Script @('Get-CausaMaven', 'Test-SinNivelDeAviso')) + "`n" + (Texto-De-Funciones (Join-Path (Split-Path -Parent $Script) 'comun.ps1') @('Join-Ruta')) + "`n" + $cuerpo))
  $r = Lanzar $f @($Dir)
  $v = @{}
  foreach ($l in @($r.Salida -split "`n")) { if ($l -cmatch '^R (\S+) ?(.*)$') { $v[$Matches[1]] = $Matches[2].TrimEnd() } }
  $x = 'java.lang.IllegalStateException: uno'
  Igual 'sin nivel: vale' $x $v['sin-nivel']
  Igual '[ERROR] de Maven: vale' $x $v['error-maven']
  Igual 'FATAL: vale' $x $v['fatal']
  Igual 'SEVERE: vale' $x $v['severe']
  Igual 'WARN de Spring Boot (por defecto): no' '' $v['warn-spring']
  Igual '[WARN ] de Logback: no' '' $v['warn-logback']
  Igual '[WARNING] de Maven: no' '' $v['warning-maven']
  Igual 'WARNING de java.util.logging: no' '' $v['warning-java-util']
  Igual '[INFO]: no' '' $v['info-maven']
  Igual 'DEBUG: no' '' $v['debug']
  Igual '[TRACE]: no' '' $v['trace']
  Igual 'JSON con logLevel INFO: no' '' $v['json-info']
  Igual 'JSON con logLevel WARN: no' '' $v['json-warn']
  Igual 'JSON con logLevel ERROR: vale, desde la clase hasta el final de la linea' 'java.lang.IllegalStateException: uno"}' $v['json-error']
  Igual 'warn en minusculas no es un nivel: vale' $x $v['minuscula']
  Igual 'AWARN (letra pegada) no es un nivel: vale' $x $v['pegado-letra']
  Igual 'WARN2 (cifra pegada): vale' $x $v['pegado-cifra']
  Igual 'WARN_MODE (guion bajo pegado): vale' $x $v['pegado-guion-bajo']
  Igual 'INFO.txt (punto pegado): vale' $x $v['pegado-punto']
  Igual 'INFO$1 (dolar pegado): vale' $x $v['pegado-dolar']
  Igual 'el primer nivel es ERROR aunque despues venga INFO: vale' 'java.io.FileNotFoundException: INFO.txt' $v['error-y-luego-info']
  Igual 'el primer nivel es INFO aunque despues venga ERROR: no' '' $v['info-y-luego-error']
  Igual 'un nivel despues de la causa no cuenta: vale, con ese WARN' "$x WARN" $v['nivel-despues-de-la-causa']
  Igual 'Caused by en lineas de aviso: no se usa ninguno' '' $v['caused-en-warn']
  Igual 'el ultimo Caused by que vale, no el de una linea de aviso' 'Caused by: java.lang.B: dos' $v['caused-sin-nivel-despues-de-warn']
  Igual 'Caused by en un [ERROR] vale y el ultimo que vale gana' 'Caused by: java.lang.A: uno' $v['caused-con-error']
  Igual 'el orden de las reglas no cambia: un Caused by gana a la primera excepcion' 'Caused by: java.lang.B: dos' $v['caused-gana-a-la-excepcion']
  Igual 'la primera excepcion que vale: la del [ERROR], no la del aviso de antes' 'java.lang.IllegalArgumentException: dos' $v['excepcion-tras-aviso']
  Igual 'se recorta a 300' 300 $v['recorte-300'].Length
  Igual 'un nivel dentro del mensaje de un Caused by (despues de la causa) no cuenta: vale' 'Caused by: java.lang.A: modo WARN apagado' $v['caused-nivel-en-su-mensaje']
}

# El prompt de -Reparar no lleva la ruta del registro: Copilot trabaja en la rama de rescate y no lee registros\ (solo la consola la dice).
$Pruebas['m52 (i) -Reparar con un caso sin causa: el prompt dice que el migrado acaba FAILED, sin la ruta del registro; la consola si la dice'] = {
  $e = Escenario-M50 'm52-i' ([ordered]@{ cargaJob = @('importe=10.00') })
  $env:RESCATE_M50 = 'solo-avisos'
  try { $r = Prueba $e @('-Reparar') 'reparar-no' } finally { $env:RESCATE_M50 = '' }
  Igual 'sale con 2' 2 $r.Codigo
  $p = @(Registros-Reparar $e 1)
  Comprueba 'hay una llamada de reparar y su prompt dice que el migrado acaba FAILED' ($p.Count -ge 1 -and $p[0].Contains('el migrado acaba FAILED')) (Cola ($p -join ' '))
  Comprueba 'sin la ruta del registro' ($p.Count -ge 1 -and -not $p[0].Contains('mira registros')) (Cola ($p -join ' '))
  Comprueba 'la consola si la dice' ($r.Salida.Contains('sin causa en la salida de Maven: mira registros\mvn-')) (Cola $r.Salida)
}

# ===================== M53: causas que la consola no daba (contexto de Spring, Maven sin excepcion, Maven bien sin salida) y dos fallos de -Reparar =====================
# m53-mvn.ps1 (sobre m50-mvn.ps1) deja, segun el guion de RESCATE_M53, un migrado EXCEPCION con el aviso de Spring 'cancelling refresh attempt', uno sin estado.txt con un
# '[ERROR] Failed to execute goal ...' de Maven, o uno sin estado.txt con Maven en 0; y, con RESCATE_M53_SUITE, tests unitarios que fallan con un <error message=...>.
# m53-copilot.ps1 (sobre m25-copilot.ps1) imita al Copilot de verdad: rechaza con 'error: option' un --add-dir que no existe. Los nombres son inventados (com.acme, cargaJob).

function Escenario-M53([string]$Nombre, $Casos, [switch]$Test, [hashtable]$Mas = @{}) {
  $aj = @{ MvnExe = (Join-Path $falsos 'm53-mvn.ps1'); CopilotExe = (Join-Path $falsos 'm53-copilot.ps1') }
  foreach ($k in $Mas.Keys) { $aj[$k] = $Mas[$k] }
  return (Escenario-M25 $Nombre $Casos -Sano -Test:$Test -Ajustes $aj)
}

# Lanza con los guiones $Guion de m53-mvn.ps1, las variables de entorno $Env (nombre -> valor) y, con $GuionCopilot, el guion del Copilot falso.
function Prueba-M53($E, [string]$Guion, [string[]]$A = @(), [hashtable]$Env = @{}, [string]$GuionCopilot = '') {
  $env:RESCATE_M53 = $Guion
  foreach ($k in $Env.Keys) { Set-Item -Path "env:$k" -Value ([string]$Env[$k]) }
  try { return (Prueba $E $A $GuionCopilot) }
  finally {
    $env:RESCATE_M53 = ''
    foreach ($k in $Env.Keys) { Remove-Item -Path "env:$k" -ErrorAction SilentlyContinue }
  }
}

function Fallo-M53($E, [string]$Job, [string]$Caso) { return @((Caso $E $Job $Caso).fallos | Where-Object { $_.lado -ceq 'migrado' })[0] }

$CausaContexto53 = "org.springframework.beans.factory.UnsatisfiedDependencyException: Error creating bean with name 'pasoPostProcessor': No qualifying bean of type 'org.springframework.batch.core.listener.StepExecutionListener' available: expected single matching bean but found 2: oyentePaso,oyenteEmpresa"
$CausaNoTests53 = 'No tests matching pattern "PruebaLocalTest" were executed! (Set -Dsurefire.failIfNoSpecifiedTests=false to ignore this error.)'
$CausaSinSalida53 = 'Maven acaba bien, pero el test no ha dejado salida: no ha ejecutado el caso (mira si ve su carpeta en src\test\resources\prueba-local)'

$Pruebas['m53 (a) el contexto de Spring no arranca (el migrado acaba EXCEPCION en 3 casos): la causa es la del aviso cancelling refresh attempt, no la del aviso de antes, y hay un solo grupo'] = {
  $e = Escenario-M53 'm53-a' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00', 'importe=30.00') })
  $r = Prueba-M53 $e 'contexto'
  Igual 'sale con 2' 2 $r.Codigo
  $f = Fallo-M53 $e 'cargaJob' 'caso-02'
  Igual 'el fallo del migrado: EXCEPCION, con la causa del aviso de Spring (lo que va despues de la marca)' "EXCEPCION|$CausaContexto53" "$($f.estado)|$($f.causa)"
  Comprueba 'la consola dice el migrado acaba EXCEPCION con esa causa (la cabecera del grupo y el detalle de un caso)' ((Veces-M50 $r.Salida "el migrado acaba EXCEPCION: $CausaContexto53") -ge 2) (Cola $r.Salida)
  Comprueba 'la consola no dice TypeNotPresentException ni sin causa' ($r.Salida -notmatch 'TypeNotPresentException' -and $r.Salida -notmatch 'sin causa en la salida') (Cola $r.Salida)
  $g = @(Grupos-M50 $e)
  Igual 'un solo grupo, de fallo, con los 3 casos' '1|fallo|3' "$($g.Count)|$($g[0].tipo)|$(@($g[0].casos).Count)"
  Comprueba 'con la firma de la UnsatisfiedDependencyException' ("$($g[0].firma)".StartsWith('fallo|EXCEPCION|org.springframework.beans.factory.UnsatisfiedDependencyException: Error creating bean with name')) "$($g[0].firma)"
}

$Pruebas['m53 (b) sin estado.txt y Maven con [ERROR] Failed to execute goal ... No tests matching pattern: la causa es el mensaje, sin el -> [Help 1], en la consola y en el JSON'] = {
  $e = Escenario-M53 'm53-b' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M53 $e 'sin-tests'
  Igual 'sale con 2' 2 $r.Codigo
  $f = Fallo-M53 $e 'cargaJob' 'caso-01'
  Igual 'el fallo del migrado: sin estado.txt, con el mensaje de Maven' "sin estado.txt|$CausaNoTests53" "$($f.estado)|$($f.causa)"
  Comprueba 'la causa empieza por No tests matching pattern y no lleva -> [Help' ("$($f.causa)".StartsWith('No tests matching pattern') -and "$($f.causa)" -notmatch '-> \[Help') "$($f.causa)"
  Comprueba 'la consola lo dice (el migrado no deja estado.txt: <causa>) y ya no dice sin causa' ($r.Salida.Contains("el migrado no deja estado.txt: $CausaNoTests53") -and $r.Salida -notmatch 'sin causa en la salida') (Cola $r.Salida)
  Comprueba 'el registro del JSON se queda: registros\mvn-<n>-migrado-cargaJob-caso-01.log' ("$($f.registro)" -cmatch '^registros\\mvn-\d+-migrado-cargaJob-caso-01\.log$') "$($f.registro)"
}

$Pruebas['m53 (c) sin estado.txt, Maven con 0 y sin excepciones: la causa es que el test no ha dejado salida, en la consola, en el JSON y en la firma, y dos casos van al mismo grupo'] = {
  $e = Escenario-M53 'm53-c' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba-M53 $e 'sin-salida'
  Igual 'sale con 2' 2 $r.Codigo
  $f = Fallo-M53 $e 'cargaJob' 'caso-01'
  Igual 'el fallo del migrado: sin estado.txt, con la causa de que no ha dejado salida' "sin estado.txt|$CausaSinSalida53" "$($f.estado)|$($f.causa)"
  Comprueba 'la consola lo dice y ya no dice sin causa en la salida de Maven' ($r.Salida.Contains("el migrado no deja estado.txt: $CausaSinSalida53") -and $r.Salida -notmatch 'sin causa en la salida') (Cola $r.Salida)
  Comprueba 'el registro del JSON se queda' ("$($f.registro)" -cmatch '^registros\\mvn-\d+-migrado-cargaJob-caso-01\.log$') "$($f.registro)"
  $g = @(Grupos-M50 $e)
  Igual 'un solo grupo con los 2 casos' '1|2' "$($g.Count)|$(@($g[0].casos).Count)"
  Comprueba 'con la causa en la firma y en la cabecera' ("$($g[0].firma)".StartsWith('fallo|sin estado.txt|Maven acaba bien, pero el test no ha dejado salida: no ha ejecutado el caso') -and "$($g[0].descripcion)".Contains($CausaSinSalida53)) "$($g[0].firma) // $($g[0].descripcion)"
}

$Pruebas['m53 (c2) sin estado.txt con Maven en 0 pero con la salida de Maven que si da causa (un FAILED del migrado, o EXCEPCION con causa) no cambia: solo el caso sin estado.txt y sin causa dice lo del test'] = {
  $e = Escenario-M53 'm53-c2' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba-M53 $e 'contexto:/caso-01$;sin-salida:/caso-02$'
  Igual 'sale con 2' 2 $r.Codigo
  Igual 'caso-01 (con EXCEPCION y su causa): la del aviso de Spring' "EXCEPCION|$CausaContexto53" "$((Fallo-M53 $e 'cargaJob' 'caso-01').estado)|$((Fallo-M53 $e 'cargaJob' 'caso-01').causa)"
  Igual 'caso-02 (sin estado.txt): la de que no ha dejado salida' "sin estado.txt|$CausaSinSalida53" "$((Fallo-M53 $e 'cargaJob' 'caso-02').estado)|$((Fallo-M53 $e 'cargaJob' 'caso-02').causa)"
  Igual 'dos grupos' 2 @(Grupos-M50 $e).Count
}

$Pruebas['m53 (d) -Reparar con un caso cuyo migrado no deja salida: la llamada se hace y --add-dir no lleva la carpeta salidas\migrado\<job>\<caso>, que no existe'] = {
  $e = Escenario-M53 'm53-d' ([ordered]@{ cargaJob = @('importe=5.00') })
  $falta = Get-Ruta $e.Local 'salidas/migrado/cargaJob/caso-01'
  $r = Prueba-M53 $e 'sin-salida' @('-Reparar') @{} 'reparar-nada'
  Comprueba 'el migrado no dejo esa carpeta (lo que prueba el caso)' (-not (Test-Path -LiteralPath $falta)) $falta
  $ll = @(Llamadas-Reparar $e)
  Comprueba 'se llamo a Copilot para reparar' ($ll.Count -ge 1) (Cola $r.Salida)
  Comprueba 'ninguna llamada lleva la carpeta que falta' (@($ll | Where-Object { $_.flags.Contains($falta) }).Count -eq 0) (($ll | ForEach-Object { $_.flags }) -join ' // ')
  $dirs = @($ll | ForEach-Object { [regex]::Matches($_.flags, '--add-dir=(\S+)') | ForEach-Object { $_.Groups[1].Value } })
  Comprueba 'todas las carpetas de --add-dir existen' ($dirs.Count -gt 0 -and @($dirs | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Container) }).Count -eq 0) ($dirs -join ' ')
  Comprueba 'el script no se para con Copilot no responde' ($r.Salida -notmatch 'Copilot no responde' -and $r.Salida -notmatch 'Copilot rechaza') (Cola $r.Salida)
}

$Pruebas['m53 (d2) Get-ArgsCopilot: --add-dir solo de las carpetas que existen (no de un fichero, de una ruta que no esta ni de una vacia)'] = {
  $f = Join-Path $Dir 'm53-args.ps1'
  $cuerpo = @'
$Cfg = @{ CopilotArgs = @('-s', '--no-ask-user') }
$ok = Join-Path $Raiz 'existe'
[void](New-Item -ItemType Directory -Path $ok -Force)
$fichero = Join-Path $Raiz 'fichero.txt'
[System.IO.File]::WriteAllText($fichero, 'x')
$falta = Join-Path $Raiz 'no-esta'
'R todas ' + ((Get-ArgsCopilot 'texto' 'mod' 'high' @($ok, $falta, $fichero, '') $true) -join '|')
'R ninguna ' + ((Get-ArgsCopilot 'texto' '' '' @($falta, '') $false) -join '|')
'R sin-dirs ' + ((Get-ArgsCopilot 'texto' '' '' @() $false) -join '|')
'@
  $ok = Join-Path $Dir 'm53-args/existe'
  [System.IO.File]::WriteAllText($f, ('param([string]$Raiz)' + "`n" + (Texto-De-Funciones (Join-Path (Split-Path -Parent $Script) 'comun.ps1') @('Get-ArgsCopilot')) + "`n" + $cuerpo))
  [void](New-Item -ItemType Directory -Path (Join-Path $Dir 'm53-args') -Force)
  $r = Lanzar $f @((Join-Path $Dir 'm53-args'))
  $v = @{}
  foreach ($l in @($r.Salida -split "`n")) { if ($l -cmatch '^R (\S+) (.*)$') { $v[$Matches[1]] = $Matches[2].TrimEnd() } }
  Igual 'con una carpeta que existe, un fichero, una que no esta y una vacia: solo la que existe' "-p|texto|-s|--no-ask-user|--model=mod|--effort=high|--no-custom-instructions|--add-dir=$ok" $v['todas']
  Igual 'sin ninguna que exista: sin --add-dir' '-p|texto|-s|--no-ask-user' $v['ninguna']
  Igual 'sin carpetas: igual' '-p|texto|-s|--no-ask-user' $v['sin-dirs']
}

$Pruebas['m53 (e) una racha de llamadas que Copilot rechaza con error: option: el mensaje de parada dice que es un fallo del script, no que mire si Copilot funciona'] = {
  $e = Nuevo-Escenario 'm53-e' ([ordered]@{ cargaJob = @('importe=10.00') })
  Escribe $e.Home 'ajustes.json' (ConvertTo-Json -InputObject ([ordered]@{ CopilotExe = (Join-Path $falsos 'm53-copilot.ps1'); MvnExe = (Join-Path $falsos 'mvn-local.ps1'); SegundosPorLlamada = 60; FallosSeguidos = 2 }))
  $env:RESCATE_M53_RECHAZA = '1'
  try { $r = Prueba $e } finally { Remove-Item -Path 'env:RESCATE_M53_RECHAZA' -ErrorAction SilentlyContinue }
  Comprueba 'el script se para (sale con distinto de 0)' ($r.Codigo -ne 0) "rc=$($r.Codigo)"
  Comprueba 'dice que Copilot rechaza los argumentos que le pasa el script, con la linea de error: option' ($r.Salida.Contains("Copilot rechaza los argumentos que le pasa el script (es un fallo del script, no de Copilot): error: option '--add-dir <directory>' argument '")) (Cola $r.Salida)
  Comprueba 'y no dice Mira que Copilot funciona' ($r.Salida -notmatch 'Mira que Copilot funciona') (Cola $r.Salida)
  Comprueba 'sigue diciendo cuantas llamadas han fallado y que se vuelva a lanzar el mismo comando' ($r.Salida -match 'llamadas seguidas han fallado' -and $r.Salida -match 'vuelve a lanzar el mismo comando: lo hecho se conserva') (Cola $r.Salida)
}

$Pruebas['m53 (e2) una racha de llamadas que fallan por otra cosa (sesion caducada): el mensaje de siempre, Mira que Copilot funciona'] = {
  $e = Nuevo-Escenario 'm53-e2' ([ordered]@{ cargaJob = @('importe=10.00') })
  Escribe $e.Home 'ajustes.json' (ConvertTo-Json -InputObject ([ordered]@{ CopilotExe = (Join-Path $falsos 'm53-copilot.ps1'); MvnExe = (Join-Path $falsos 'mvn-local.ps1'); SegundosPorLlamada = 60; FallosSeguidos = 2 }))
  $env:RESCATE_M53_RECHAZA = 'sesion'
  try { $r = Prueba $e } finally { Remove-Item -Path 'env:RESCATE_M53_RECHAZA' -ErrorAction SilentlyContinue }
  Comprueba 'el script se para' ($r.Codigo -ne 0) "rc=$($r.Codigo)"
  Comprueba 'dice Mira que Copilot funciona y no que rechaza los argumentos' ($r.Salida.Contains('Mira que Copilot funciona (sesion, cuota, red)') -and $r.Salida -notmatch 'rechaza los argumentos') (Cola $r.Salida)
}

# El motivo del reintento de -Reparar cuando el arreglo rompe un test: lleva el primer mensaje de fallo de los TEST-*.xml.
$Pruebas['m53 (f) -Reparar: el arreglo rompe un test unitario con <error message="...found 2: a,b">: el motivo y el prompt del reintento llevan El primero falla con: y el mensaje (solo su primera linea)'] = {
  $e = Escenario-M53 'm53-f' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') }) -Test
  $r = Prueba-M53 $e '' @('-Reparar') @{ RESCATE_M53_SUITE = 'mensaje' } 'reparar-arregla'
  Igual 'sale con 2' 2 $r.Codigo
  $rep = @(Reparaciones $e)
  Comprueba 'el motivo sigue diciendo que arregla el caso pero rompe tests y nombra el test' ($rep[0].motivo -match 'arregla el caso, pero rompe estos tests' -and $rep[0].motivo -match 'com\.acme\.nuevo\.ReglaTest') $rep[0].motivo
  Comprueba 'y acaba con El primero falla con: el mensaje, con found 2' ($rep[0].motivo.Contains('Fallan 1 y antes fallaban 0. El primero falla con: Failed to load ApplicationContext for [x]: expected single matching bean but found 2: a,b.')) $rep[0].motivo
  Comprueba 'sin la segunda linea del mensaje' ($rep[0].motivo -notmatch 'segunda linea') $rep[0].motivo
  $p = @(Registros-Reparar $e 2)
  Comprueba 'el prompt del reintento lleva El primero falla con: y found 2' ($p.Count -ge 1 -and $p[0].Contains('El primero falla con:') -and $p[0].Contains('found 2: a,b')) (Cola ($p -join ' '))
}

$Pruebas['m53 (f2) -Reparar: el <error> con message vacio y el texto en el cuerpo: lleva la primera linea con texto del cuerpo'] = {
  $e = Escenario-M53 'm53-f2' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') }) -Test
  $r = Prueba-M53 $e '' @('-Reparar') @{ RESCATE_M53_SUITE = 'cuerpo' } 'reparar-arregla'
  Igual 'sale con 2' 2 $r.Codigo
  $rep = @(Reparaciones $e)
  Comprueba 'el motivo acaba con la primera linea del cuerpo (sin la linea en blanco de antes ni las de despues)' ($rep[0].motivo.Contains('El primero falla con: java.lang.IllegalStateException: Failed to load ApplicationContext for [x]: expected single matching bean but found 2: a,b.') -and $rep[0].motivo -notmatch 'DefaultCacheAware') $rep[0].motivo
  $p = @(Registros-Reparar $e 2)
  Comprueba 'y el prompt del reintento lo lleva' ($p.Count -ge 1 -and $p[0].Contains('El primero falla con: java.lang.IllegalStateException') -and $p[0].Contains('found 2: a,b')) (Cola ($p -join ' '))
}

$Pruebas['m53 (f3) -Reparar: un mensaje de 400 letras se recorta a 300; sin mensaje ni texto, el motivo no lleva El primero falla con'] = {
  $e = Escenario-M53 'm53-f3' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') }) -Test
  [void](Prueba-M53 $e '' @('-Reparar') @{ RESCATE_M53_SUITE = 'largo' } 'reparar-arregla')
  $m = "$(@(Reparaciones $e)[0].motivo)"
  Comprueba 'con 300 letras justas' ($m.Contains('El primero falla con: ' + ('L' * 300) + '.') -and -not $m.Contains('L' * 301)) $m
  $e2 = Escenario-M53 'm53-f3b' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') }) -Test
  [void](Prueba-M53 $e2 '' @('-Reparar') @{ RESCATE_M53_SUITE = 'vacio' } 'reparar-arregla')
  $v = "$(@(Reparaciones $e2)[0].motivo)"
  Comprueba 'sin mensaje: el motivo de siempre, acabado en el recuento' ($v -match 'rompe estos tests' -and $v -match 'Fallan 1 y antes fallaban 0\.$' -and $v -notmatch 'El primero falla con') $v
}

# Get-CausaMaven con salidas de Maven inventadas (sin informes de surefire: la carpeta no existe), una fila por salida: 'R <id> <causa>'.
$Pruebas['m53 (h) Get-CausaMaven: el aviso cancelling refresh attempt da la causa aunque sea WARN; un Failed to execute goal sin mas causa da su mensaje; lo demas, como antes'] = {
  $f = Join-Path $Dir 'm53-causas.ps1'
  $cuerpo = @'
$ErrorActionPreference = 'Stop'
$Desde = [datetime]'2026-11-20'
function Fila([string]$Id, [string[]]$Salida) { 'R ' + $Id + ' ' + (Get-CausaMaven (Join-Path $Raiz 'no-existe') $Desde $Salida) }
$U = "org.springframework.beans.factory.UnsatisfiedDependencyException: Error creating bean with name 'a': found 2: x,y"
$W = "2026-11-20T22:45:23.103+01:00  WARN 11116 --- [app] [main] s.c.a.AnnotationConfigApplicationContext : Exception encountered during context initialization - cancelling refresh attempt: $U"
$T = '2026-11-20T22:45:20.512+01:00  WARN 11116 --- [app] [main] o.s.c.a.MergedAnnotation : Failed to introspect X: java.lang.TypeNotPresentException: Type com.acme.Falta not present'
$G = '[ERROR] Failed to execute goal org.apache.maven.plugins:maven-surefire-plugin:3.5.6:test (default-test) on project batch-x: No tests matching pattern "PruebaLocalTest" were executed! (Set -Dsurefire.failIfNoSpecifiedTests=false to ignore this error.) -> [Help 1]'
Fila 'refresh-warn' @($W)
Fila 'refresh-tras-aviso' @($T, $W)
Fila 'refresh-gana-a-la-posterior' @($W, '[ERROR] otra java.lang.IllegalArgumentException: dos', 'java.lang.B: tres')
Fila 'refresh-en-error' @("[ERROR] ... cancelling refresh attempt: $U")
Fila 'refresh-sin-nivel' @("cancelling refresh attempt: $U")
Fila 'refresh-recorte-300' @('x WARN cancelling refresh attempt: ' + ('a' * 400))
Fila 'refresh-sin-dos-puntos' @('x WARN cancelling refresh attempt')
Fila 'otro-aviso-sin-causa' @($T)
Fila 'caused-gana-al-aviso' @($W, 'Caused by: java.lang.B: dos')
Fila 'goal' @($G)
Fila 'goal-primera' @($G, '[ERROR] Failed to execute goal org.x:y:1:z (a) on project p: otro mensaje -> [Help 1]')
Fila 'goal-sin-help' @('[ERROR] Failed to execute goal org.x:y:1:z (a) on project p: sin ayuda')
Fila 'goal-sin-plugin' @('[ERROR] Failed to execute goal on project batch-nuevo: Cannot access central in offline mode')
Fila 'goal-con-excepcion' @('[ERROR] Failed to execute goal org.x:y:1:z (a) on project p: Fallo java.lang.IllegalStateException: uno -> [Help 1]')
Fila 'goal-tras-excepcion' @('[ERROR] java.lang.IllegalStateException: antes', $G)
Fila 'goal-en-warning' @('[WARNING] Failed to execute goal org.x:y:1:z (a) on project p: aviso -> [Help 1]')
Fila 'goal-recorte-300' @('[ERROR] Failed to execute goal org.x:y:1:z (a) on project p: ' + ('b' * 400) + ' -> [Help 1]')
Fila 'sin-nada' @('[INFO] BUILD SUCCESS')
'@
  [System.IO.File]::WriteAllText($f, ('param([string]$Raiz)' + "`n" + (Texto-De-Funciones $Script @('Get-CausaMaven', 'Test-SinNivelDeAviso')) + "`n" + (Texto-De-Funciones (Join-Path (Split-Path -Parent $Script) 'comun.ps1') @('Join-Ruta')) + "`n" + $cuerpo))
  $r = Lanzar $f @($Dir)
  $v = @{}
  foreach ($l in @($r.Salida -split "`n")) { if ($l -cmatch '^R (\S+) ?(.*)$') { $v[$Matches[1]] = $Matches[2].TrimEnd() } }
  $u = "org.springframework.beans.factory.UnsatisfiedDependencyException: Error creating bean with name 'a': found 2: x,y"
  Igual 'aviso WARN de Spring: la causa es lo que va despues de la marca' $u $v['refresh-warn']
  Igual 'con un aviso WARN con otra excepcion antes: la del refresh' $u $v['refresh-tras-aviso']
  Igual 'gana a las lineas posteriores (una excepcion con [ERROR] y otra sin nivel despues)' $u $v['refresh-gana-a-la-posterior']
  Igual 'la linea con nivel ERROR: tambien' $u $v['refresh-en-error']
  Igual 'sin nivel: tambien' $u $v['refresh-sin-nivel']
  Igual 'se recorta a 300' 300 $v['refresh-recorte-300'].Length
  Igual 'la marca sin los dos puntos y el espacio no vale: sin causa' '' $v['refresh-sin-dos-puntos']
  Igual 'el resto de avisos sigue sin dar causa' '' $v['otro-aviso-sin-causa']
  Igual 'el orden de las reglas no cambia: un Caused by gana (esta en la misma regla que el aviso)' 'Caused by: java.lang.B: dos' $v['caused-gana-al-aviso']
  Igual 'Failed to execute goal sin mas causa: su mensaje, sin el -> [Help 1]' 'No tests matching pattern "PruebaLocalTest" were executed! (Set -Dsurefire.failIfNoSpecifiedTests=false to ignore this error.)' $v['goal']
  Igual 'se usa la primera de esas lineas' 'No tests matching pattern "PruebaLocalTest" were executed! (Set -Dsurefire.failIfNoSpecifiedTests=false to ignore this error.)' $v['goal-primera']
  Igual 'sin -> [Help 1]: el mensaje entero' 'sin ayuda' $v['goal-sin-help']
  Igual 'sin plugin (Failed to execute goal on project <p>:): el mensaje' 'Cannot access central in offline mode' $v['goal-sin-plugin']
  Igual 'si el mensaje lleva una excepcion, gana la regla de la primera excepcion (desde la clase)' 'java.lang.IllegalStateException: uno -> [Help 1]' $v['goal-con-excepcion']
  Igual 'una excepcion antes: la excepcion, no el goal' 'java.lang.IllegalStateException: antes' $v['goal-tras-excepcion']
  Igual 'un [WARNING] con Failed to execute goal no cuenta' '' $v['goal-en-warning']
  Igual 'se recorta a 300' 300 $v['goal-recorte-300'].Length
  Igual 'sin nada: sin causa' '' $v['sin-nada']
}

$Pruebas['m53 (i) -Reparar con dos tests que fallan, cada uno con su message: El primero falla con: lleva el del primero de la lista, no el del ultimo'] = {
  $e = Escenario-M53 'm53-i' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') }) -Test
  # ZonaTest ya falla antes del arreglo (espera 5.02) y ReglaTest empieza a fallar con el (espera 5.01): fallan los dos, con messages distintos
  [void](Commit-En $e.Wt 'src/test/java/com/acme/nuevo/ZonaTest.java' "package com.acme.nuevo;`n// ESPERA minimo=5.02`nclass ZonaTest {}`n" 'test que ya fallaba')
  $r = Prueba-M53 $e '' @('-Reparar') @{} 'reparar-arregla'
  Igual 'sale con 2' 2 $r.Codigo
  $rep = @(Reparaciones $e)
  $m = [regex]::Match("$($rep[0].motivo)", '\(esperan el comportamiento de ahora\?\): (\S+?),\s')
  $mensajes = @{ 'com.acme.nuevo.ReglaTest.espera' = 'esperaba minimo=5.01 y hay 5.00'; 'com.acme.nuevo.ZonaTest.espera' = 'esperaba minimo=5.02 y hay 5.00' }
  $otro = @{ 'com.acme.nuevo.ReglaTest.espera' = 'esperaba minimo=5.02'; 'com.acme.nuevo.ZonaTest.espera' = 'esperaba minimo=5.01' }
  Comprueba 'el motivo nombra los dos tests y dice Fallan 2 y antes fallaban 1' ($m.Success -and $mensajes.ContainsKey($m.Groups[1].Value) -and $rep[0].motivo.Contains('Fallan 2 y antes fallaban 1.')) $rep[0].motivo
  $primero = $m.Groups[1].Value
  Comprueba 'acaba con El primero falla con: el message del primero de la lista' ($m.Success -and $rep[0].motivo.EndsWith(" El primero falla con: $($mensajes[$primero]).")) $rep[0].motivo
  Comprueba 'y no con el del segundo' ($m.Success -and -not $rep[0].motivo.Contains($otro[$primero])) $rep[0].motivo
  $p = @(Registros-Reparar $e 2)
  Comprueba 'el prompt del reintento lleva lo mismo' ($m.Success -and $p.Count -ge 1 -and $p[0].Contains(" El primero falla con: $($mensajes[$primero]).")) (Cola ($p -join ' '))
}

$Pruebas['m53 (j) sin estado.txt con Maven en 1 y sin causa en el log: no es el caso de Maven bien y sin salida, la causa queda vacia y la consola dice sin causa'] = {
  $e = Escenario-M53 'm53-j' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M53 $e 'sin-salida-rc1'
  Igual 'sale con 2' 2 $r.Codigo
  $f = Fallo-M53 $e 'cargaJob' 'caso-01'
  Igual 'el fallo del migrado: sin estado.txt y sin causa' 'sin estado.txt|' "$($f.estado)|$($f.causa)"
  Comprueba 'la consola dice sin causa en la salida de Maven y no lo de que no ha dejado salida' ($r.Salida -match 'el migrado no deja estado\.txt: sin causa en la salida de Maven' -and -not $r.Salida.Contains($CausaSinSalida53)) (Cola $r.Salida)
}

$Pruebas['m53 (k) un lado con estado.txt (EXCEPCION), Maven en 0 y sin causa en el log: no es el caso de Maven bien y sin salida, la causa queda vacia y la consola dice sin causa'] = {
  $e = Escenario-M53 'm53-k' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M53 $e 'excepcion-muda'
  Igual 'sale con 2' 2 $r.Codigo
  $f = Fallo-M53 $e 'cargaJob' 'caso-01'
  Igual 'el fallo del migrado: EXCEPCION y sin causa' 'EXCEPCION|' "$($f.estado)|$($f.causa)"
  Comprueba 'la consola dice sin causa en la salida de Maven y no lo de que no ha dejado salida' ($r.Salida -match 'el migrado acaba EXCEPCION: sin causa en la salida de Maven' -and -not $r.Salida.Contains($CausaSinSalida53)) (Cola $r.Salida)
}

$Pruebas['m53 (l) sin estado.txt con Maven en 0 y una causa en el log (el aviso cancelling refresh attempt): la causa es la del log, no el texto fijo de que no ha dejado salida'] = {
  $e = Escenario-M53 'm53-l' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M53 $e 'sin-salida-aviso'
  Igual 'sale con 2' 2 $r.Codigo
  $f = Fallo-M53 $e 'cargaJob' 'caso-01'
  Igual 'el fallo del migrado: sin estado.txt, con la causa del aviso de Spring' "sin estado.txt|$CausaContexto53" "$($f.estado)|$($f.causa)"
  Comprueba 'la consola dice esa causa y no lo de que no ha dejado salida' ($r.Salida.Contains("el migrado no deja estado.txt: $CausaContexto53") -and -not $r.Salida.Contains($CausaSinSalida53)) (Cola $r.Salida)
}

# ===================== M56: el test de la prueba en local no se queda atascado sin salida =====================
# Estos escenarios usan los falsos m40 (-RehacerOriginal y los avisos de las tablas) y m56-copilot.ps1 y m56-mvn.ps1 (RESCATE_M56 = '<nombre>:<id de tarea>'):
# el arnes cuyo id casa deja un test cuyo mvn test acaba con la salida de bean, bean-tabla, create-es, create-en o create-min (ver m56-mvn.ps1).
# El original lleva un Repo.java con 'INSERT INTO T_A' en la linea 4 (Escenario-M40).

function Prueba-M56($E, [string]$Guion, [string[]]$A = @()) {
  $env:RESCATE_M56 = $Guion
  try { return (Prueba $E $A) }
  finally { $env:RESCATE_M56 = '' }
}

$Pruebas['m56 (a) -RehacerOriginal con los dos arneses guardados y hechos: se escriben otra vez los dos (dos llamadas); sin la opcion, ninguna'] = {
  $e = Nuevo-Escenario 'm56-a' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba $e
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  Igual 'una llamada al arnes del original' 1 @(Llamadas-Arnes $e 'original').Count
  Igual 'y una al del migrado' 1 @(Llamadas-Arnes $e 'migrado').Count
  $r = Prueba $e
  Igual 'sin la opcion sale con 0' 0 $r.Codigo
  Igual 'sin llamadas nuevas' 2 (@(Llamadas-Arnes $e 'original').Count + @(Llamadas-Arnes $e 'migrado').Count)
  $r = Prueba $e @('-RehacerOriginal')
  Igual 'con -RehacerOriginal sale con 0' 0 $r.Codigo
  Igual 'se escribe otra vez el del original' 2 @(Llamadas-Arnes $e 'original').Count
  Igual 'y el del migrado, que lo traduce' 2 @(Llamadas-Arnes $e 'migrado').Count
  Comprueba 'los dos quedan hechos' ((Tarea-Arnes $e 'original').estado -eq 'hecha' -and (Tarea-Arnes $e 'migrado').estado -eq 'hecha') ''
  Comprueba 'y no avisa de casos sin preparar por las tablas' ($r.Salida -notmatch 'no se pudieron preparar porque') (Cola $r.Salida)
}

$Pruebas['m56 (b) un arnes del original sin una tabla del inventario: el aviso, al escribirlo y al usar el guardado, dice que relance con -RehacerOriginal; con la opcion y el test con la tabla, el aviso se va'] = {
  $e = Escenario-M40 'm56-b' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $aviso = "La base de prueba sigue sin estas tablas: T_A ($SitioTablaM40). Los casos que las usen saldran FAILED en el original. Para que lo escriba otra vez con ellas, relanza con -RehacerOriginal."
  $r = Prueba-M40 $e 'tablas=9/T_A:arnes-original'
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'el aviso con -RehacerOriginal, una vez' 1 ([regex]::Matches($r.Salida, [regex]::Escape($aviso))).Count
  $r = Prueba-M40 $e 'tablas=9/T_A:arnes-original'
  Igual 'con el arnes guardado, el mismo aviso, una vez' 1 ([regex]::Matches($r.Salida, [regex]::Escape($aviso))).Count
  $r = Prueba-M40 $e 'tablas=1/T_A:arnes-original;tablas=1/T_A:arnes-migrado' @('-RehacerOriginal')
  Igual 'con -RehacerOriginal y la tabla en el test nuevo, sale con 0' 0 $r.Codigo
  Comprueba 'el test guardado lleva la tabla' ((Test-Guardado $e 'original').Contains('BASE_TABLAS=T_A')) ''
  Comprueba 'y ya no avisa' ($r.Salida -notmatch 'sigue sin estas tablas') (Cola $r.Salida)
}

$Pruebas['m56 (c) tres casos que no se pudieron preparar por una tabla del inventario: una sola linea de aviso con 3 caso(s)'] = {
  $e = Escenario-M40 'm56-c' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00', 'importe=30.00') })
  $r = Prueba-M40 $e 'tablas=9/T_A:arnes-original;falta-tabla=T_A:^cargaJob/caso-0[123]'
  Igual 'sale con 1 (ningun caso se compara)' 1 $r.Codigo
  Igual 'los tres casos: no se pudo preparar' 'no se pudo preparar,no se pudo preparar,no se pudo preparar' ((Resultados $e) -join ',')
  $linea = '3 caso(s) no se pudieron preparar porque el test del original no crea sus tablas: relanza con -RehacerOriginal.'
  Igual 'la linea de aviso, una vez' 1 ([regex]::Matches($r.Salida, [regex]::Escape($linea))).Count
  Igual 'y ninguna otra con esa cuenta' 1 ([regex]::Matches($r.Salida, 'caso\(s\) no se pudieron preparar porque')).Count
}

$M56Bean = "El contexto de Spring no arranca: el bean clientesFinder falla al crearse (Error getting clientes). Si llama fuera al arrancar (base de datos, Mongo, REST, ficheros), sustituyelo en el test por un @MockBean (@MockitoBean en Spring Boot 3.4 o posterior) o por un @Bean @Primary de prueba que no llame fuera. No toques src/main."

$Pruebas['m56 (d) un bean que llama fuera al crearse y hace fallar el contexto: el motivo del reintento y el de Show-Atascado llevan el bean mas interno, @MockBean, @MockitoBean y No toques src/main'] = {
  $e = Escenario-M40 'm56-d' ([ordered]@{ cargaJob = @('importe=10.00') }) 'm56'
  $r = Prueba-M56 $e 'bean:arnes-original'
  Igual 'sale con 1 (el arnes del original queda atascado)' 1 $r.Codigo
  Igual 'dos llamadas al arnes del original' 2 @(Llamadas-Arnes $e 'original').Count
  Comprueba 'el prompt del reintento lleva la pista, con el bean mas interno (clientesFinder) y su mensaje' ((Registro-Arnes $e 'original' 2).Contains($M56Bean)) (Cola (Registro-Arnes $e 'original' 2))
  Comprueba 'y el primer prompt no' (-not (Registro-Arnes $e 'original' 1).Contains('@MockBean')) ''
  $t = Tarea-Arnes $e 'original'
  Igual 'la tarea queda atascada con dos intentos' 'atascada,2' "$($t.estado),$($t.intentos)"
  Comprueba 'su motivo lleva la pista, tras lo que ya decia (que no dejo estado.txt)' ($t.motivo.Contains($M56Bean) -and $t.motivo -match 'no ha dejado estado\.txt') $t.motivo
  $pegar = @($r.Salida -split "`n" | Where-Object { $_.Contains('Estoy ejecutando prueba-local.ps1') })
  Comprueba 'el texto para pegar en Copilot (Show-Atascado) la lleva' ($pegar.Count -eq 1 -and $pegar[0].Contains($M56Bean)) (Cola $r.Salida)
  Comprueba 'y la consola del atasco, tambien' ($r.Salida.Contains("ha quedado atascado: ") -and $r.Salida.Contains('@MockitoBean')) (Cola $r.Salida)
}

$Pruebas['m56 (d2) la misma cadena del bean con la causa Table "T_A" not found: sin la pista del bean (de las tablas se ocupa m40)'] = {
  $e = Escenario-M40 'm56-d2' ([ordered]@{ cargaJob = @('importe=10.00') }) 'm56'
  $r = Prueba-M56 $e 'bean-tabla:arnes-original'
  Igual 'sale con 1' 1 $r.Codigo
  Igual 'dos llamadas al arnes del original' 2 @(Llamadas-Arnes $e 'original').Count
  $t = Tarea-Arnes $e 'original'
  Comprueba 'el motivo sigue diciendo que no dejo estado.txt, con la causa de la tabla' ($t.motivo -match 'no ha dejado estado\.txt' -and $t.motivo.Contains('Table "T_A" not found')) $t.motivo
  Comprueba 'pero no lleva la pista del bean' ($t.motivo -notmatch 'El contexto de Spring no arranca' -and $t.motivo -notmatch '@MockBean') $t.motivo
  Comprueba 'ni el prompt del reintento' (-not (Registro-Arnes $e 'original' 2).Contains('@MockBean')) ''
}

$Pruebas['m56 (e) el test crea mal una tabla (H2 rechaza CREATE TABLE IF NOT EXISTS PUBLIC.IF[*]): el motivo lleva la sentencia y el inventario del repo, no IF como tabla; en espanol y en ingles'] = {
  $sentencia = 'CREATE TABLE IF NOT EXISTS PUBLIC.IF[*] (IF VARCHAR(4000),NOT VARCHAR(4000),EXISTS VARCHAR(4000),T_COMIS VARCHAR(4000))'
  $inventario = "con las columnas que usa el codigo: T_A ($SitioTablaM40)."
  foreach ($x in @(@('create-es', $sentencia), @('create-en', $sentencia), @('create-min', $sentencia.ToLowerInvariant()))) {
    $e = Escenario-M40 ('m56-e-' + $x[0]) ([ordered]@{ cargaJob = @('importe=10.00') }) 'm56'
    $r = Prueba-M56 $e ($x[0] + ':arnes-original')
    $pista = "El test crea mal una tabla ($($x[1].Substring(0, 60))). No saques las tablas del SQL del codigo: escribe un CREATE TABLE fijo para cada una de estas, $inventario"
    Igual "$($x[0]): sale con 1" 1 $r.Codigo
    $t = Tarea-Arnes $e 'original'
    Comprueba "$($x[0]): el motivo lleva la pista, con los 60 primeros caracteres de la sentencia y el inventario" ($t.motivo.Contains($pista)) $t.motivo
    Comprueba "$($x[0]): el reintento la lleva" ((Registro-Arnes $e 'original' 2).Contains($pista)) (Cola (Registro-Arnes $e 'original' 2))
    Comprueba "$($x[0]): el inventario no lleva IF como tabla" ($t.motivo -notmatch '(?m)(^|[ ,:])IF \(src/') $t.motivo
    Comprueba "$($x[0]): ni la pista del bean" ($t.motivo -notmatch 'El contexto de Spring no arranca') $t.motivo
  }
}

$Pruebas['m56 (f) un arnes atascado: relanzar el mismo comando lo vuelve a intentar con dos intentos nuevos, como dice el texto de Show-Atascado'] = {
  $e = Nuevo-Escenario 'm56-f' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba $e @() 'arnes-no-compila:arnes-original'
  Igual 'sale con 1' 1 $r.Codigo
  Igual 'dos llamadas al arnes del original' 2 @(Llamadas-Arnes $e 'original').Count
  $pegar = @($r.Salida -split "`n" | Where-Object { $_.Contains('Estoy ejecutando prueba-local.ps1') })
  Comprueba 'el texto para pegar acaba diciendo que se vuelve a lanzar el mismo comando' ($pegar.Count -eq 1 -and $pegar[0].EndsWith('Despues vuelvo a lanzar el mismo comando.')) (Cola $r.Salida)
  $r = Prueba $e @() 'arnes-no-compila:arnes-original'
  Igual 'el mismo comando, otra vez, sale con 1' 1 $r.Codigo
  Igual 'vuelve a llamar a la IA: dos llamadas mas' 4 @(Llamadas-Arnes $e 'original').Count
  $t = Tarea-Arnes $e 'original'
  Igual 'con dos intentos nuevos, no con cuatro: la tarea atascada no se conserva' 'atascada,2' "$($t.estado),$($t.intentos)"
  $r = Prueba $e
  Igual 'arreglado lo que fallaba, el mismo comando sale con 0' 0 $r.Codigo
  Igual 'con una llamada mas' 5 @(Llamadas-Arnes $e 'original').Count
  Igual 'y el arnes queda hecho' 'hecha' (Tarea-Arnes $e 'original').estado
}

$Pruebas['m56 (g) un original corrido a caballo de la medianoche (R_2026_11_20.TXT y R_2026_11_21.TXT): no es no determinista, y el migrado con el nombre de hoy sale igual; con un nombre de otro dia, distinto'] = {
  $f = Join-Path $Dir 'm56-fechas.ps1'
  $raizCmp = Join-Path $Dir 'm56-fechas'
  $cuerpo = @'
$Inv = [System.Globalization.CultureInfo]::InvariantCulture
$Utf8Estricto = New-Object System.Text.UTF8Encoding($false, $true)
$RutasCopia = @()
$caballo = @([datetime]'2026-11-20', [datetime]'2026-11-21')
$Hoy = @([datetime]'2026-11-21')
function Lado([string]$Id, [string]$Lado, [hashtable]$Ficheros) {
  $d = Join-Path (Join-Path $Raiz $Id) $Lado
  foreach ($k in $Ficheros.Keys) {
    $p = Join-Path $d $k
    [void](New-Item -ItemType Directory -Path (Split-Path $p -Parent) -Force)
    [System.IO.File]::WriteAllText($p, $Ficheros[$k])
  }
  return $d
}
function Caso([string]$Id, [hashtable]$A, [hashtable]$B, $DiasA, $DiasB = $null) {
  $dirA = Lado $Id 'A' $A
  $dirB = Lado $Id 'B' $B
  'R ' + $Id + ' ' + (@(Compare-Caso $dirA $dirB $DiasA $DiasB | ForEach-Object { $_.fichero }) -join ',')
}
$a = 'ficheros/outbox/R_2026_11_20.TXT'
$b = 'ficheros/outbox/R_2026_11_21.TXT'
$c = 'ficheros/outbox/R_2026_11_22.TXT'
# original y original-2 (los dos dias del original en los dos lados)
Caso 'original-y-original-2' @{ $a = "total 3`n" } @{ $b = "total 3`n" } $caballo $caballo
# original frente al migrado (el migrado, con los dias de hoy)
Caso 'migrado-de-hoy' @{ $a = "total 3`n" } @{ $b = "total 3`n" } $caballo
Caso 'migrado-con-otro-contenido' @{ $a = "total 3`n" } @{ $b = "total 4`n" } $caballo
Caso 'migrado-de-otro-dia' @{ $a = "total 3`n" } @{ $c = "total 3`n" } $caballo
Caso 'original-de-otro-dia' @{ $c = "total 3`n" } @{ $b = "total 3`n" } $caballo
Caso 'sin-ventana' @{ $a = "total 3`n" } @{ $b = "total 3`n" } $null
'N ' + (Get-Normal 'ficheros/outbox/R_2026_11_20.TXT y 2026_11_20_153045' $caballo)
'@
  $comun = Join-Path (Split-Path -Parent $Script) 'comun.ps1'
  [System.IO.File]::WriteAllText($f, ('param([string]$Raiz)' + "`n" + (Texto-De-Funciones $Script (@('Compare-Caso', 'Compare-Fichero') + $FnLeer + @('Sort-Tabla', 'Resolve-ParTablas', 'Sort-Ordinal', 'Get-Normal', 'Get-Legible', 'Get-NotaJdk'))) + "`n" + (Texto-De-Funciones $comun @('Get-Rel', 'Join-Ruta')) + "`n" + '$Latin = [System.Text.Encoding]::GetEncoding(28591); $Utf8 = New-Object System.Text.UTF8Encoding($false)' + "`n" + $cuerpo))
  $r = Lanzar $f @($raizCmp)
  $v = @{}
  foreach ($l in @($r.Salida -split "`n")) { if ($l -cmatch '^R (\S+) ?(.*)$') { $v[$Matches[1]] = $Matches[2].TrimEnd() } }
  Igual 'original y original-2, uno con cada dia en el nombre: el mismo fichero (no no determinista)' '' $v['original-y-original-2']
  Igual 'el migrado con el nombre de hoy y el mismo contenido: igual' '' $v['migrado-de-hoy']
  Comprueba 'con otro contenido, distinto' ($v['migrado-con-otro-contenido'] -ne '') (Cola $r.Salida)
  Comprueba 'con una fecha de otro dia en el nombre (el 22), distinto' ($v['migrado-de-otro-dia'] -ne '') (Cola $r.Salida)
  Comprueba 'un original con una fecha que no es de sus dias, distinto' ($v['original-de-otro-dia'] -ne '') (Cola $r.Salida)
  Comprueba 'sin dias de ejecucion por lado, con solo los de hoy, el nombre del 20 es un dato y sale distinto' ($v['sin-ventana'] -ne '') (Cola $r.Salida)
  Comprueba 'la fecha con guion bajo tambien se normaliza en el contenido, con su marca y la hora pegada' ($r.Salida -match '(?m)^N ficheros/outbox/R_<hoy:yyyy_MM_dd>\.TXT y <hoy:yyyy_MM_dd><hora>$') (Cola $r.Salida)
}

$Pruebas['m56 (h) un job de 38 caracteres: las columnas de la tabla del resumen quedan alineadas; con nombres cortos, el ancho de siempre'] = {
  $f = Join-Path $Dir 'm56-tabla.ps1'
  $cuerpo = @'
$largo = 'procesarRecibosPendientesDeClientesJob'
'L ' + $largo.Length
Show-Resultado @() @([pscustomobject]@{ job = 'cargaJob'; casos = 3; iguales = 3; distintos = 0; sinProbar = 0 }) @()
'---'
Show-Resultado @() @([pscustomobject]@{ job = 'cargaJob'; casos = 3; iguales = 3; distintos = 0; sinProbar = 0 }, [pscustomobject]@{ job = $largo; casos = 12; iguales = 10; distintos = 1; sinProbar = 1 }) @()
'@
  $comun = Join-Path (Split-Path -Parent $Script) 'comun.ps1'
  [System.IO.File]::WriteAllText($f, ((Texto-De-Funciones $Script @('Show-Resultado')) + "`n" + (Texto-De-Funciones $comun @('Info', 'Fallo', 'Aviso')) + "`n" + $cuerpo))
  $r = Lanzar $f @()
  $partes = @($r.Salida -split "`n---`n")
  Comprueba 'el job largo mide 38' ($r.Salida -match '(?m)^L 38$') (Cola $r.Salida)
  Comprueba 'hay dos tablas' ($partes.Count -eq 2) (Cola $r.Salida)
  $corta = @($partes[0] -split "`n" | Where-Object { $_ -match '^(Job|cargaJob)\s' })
  Igual 'con nombres cortos: la cabecera y su fila, con el ancho de siempre (71 letras)' '71,71' (($corta | ForEach-Object { $_.Length }) -join ',')
  $larga = @($partes[1] -split "`n" | Where-Object { $_ -match '^(Job|cargaJob|procesarRecibosPendientesDeClientesJob)\s' })
  Igual 'con el job largo: la cabecera y las dos filas miden lo mismo' 1 @($larga | ForEach-Object { $_.Length } | Select-Object -Unique).Count
  Igual 'son tres lineas' 3 $larga.Count
}

$Pruebas['m56 (i) un Error creating bean que no es de un bean que llama fuera (NoSuchBeanDefinitionException, sin Factory method, Failed to instantiate ni BeanInstantiationException): sin la pista del bean'] = {
  $e = Escenario-M40 'm56-i' ([ordered]@{ cargaJob = @('importe=10.00') }) 'm56'
  $r = Prueba-M56 $e 'bean-sin-factory:arnes-original'
  Igual 'sale con 1' 1 $r.Codigo
  Igual 'dos llamadas al arnes del original' 2 @(Llamadas-Arnes $e 'original').Count
  $t = Tarea-Arnes $e 'original'
  Comprueba 'el motivo sigue diciendo que no dejo estado.txt, con la causa (No qualifying bean)' ($t.motivo -match 'no ha dejado estado\.txt' -and $t.motivo.Contains('No qualifying bean of type')) $t.motivo
  Comprueba 'pero no lleva la pista del bean' ($t.motivo -notmatch 'El contexto de Spring no arranca' -and $t.motivo -notmatch '@MockBean') $t.motivo
  Comprueba 'ni el prompt del reintento' (-not (Registro-Arnes $e 'original' 2).Contains('@MockBean')) ''
}

$Pruebas['m56 (j) un bean que falla al crearse con un mensaje de 300 caracteres: la pista lleva los 120 primeros y no el resto'] = {
  $e = Escenario-M40 'm56-j' ([ordered]@{ cargaJob = @('importe=10.00') }) 'm56'
  $r = Prueba-M56 $e 'bean-largo:arnes-original'
  Igual 'sale con 1' 1 $r.Codigo
  $t = Tarea-Arnes $e 'original'
  $m = [regex]::Match($t.motivo, 'El contexto de Spring no arranca: el bean (\S+) falla al crearse \((.*?)\)\. Si llama fuera')
  Comprueba 'el motivo lleva la pista del bean' $m.Success $t.motivo
  Igual 'con el bean mas interno' 'clientesFinder' $m.Groups[1].Value
  Igual 'y el mensaje cortado a 120 caracteres: los 120 primeros' ('0123456789' * 12) $m.Groups[2].Value
  Comprueba 'el prompt del reintento lleva ese corte y no el mensaje entero' ((Registro-Arnes $e 'original' 2).Contains('(' + ('0123456789' * 12) + ')') -and -not (Registro-Arnes $e 'original' 2).Contains('(' + ('0123456789' * 13))) ''
}

# ===================== M59: el original en UTF-8 y los casos sin probar que se vuelven a preparar =====================
# Estos escenarios usan m59-mvn.ps1, que apunta en RESCATE_LLAMADAS/m59-mvn.log la carpeta, el JAVA_TOOL_OPTIONS que recibe, si la carpeta tiene
# target y los argumentos de cada Maven (el resto, como mvn-local.ps1).

function Escenario-M59([string]$Nombre, $Casos) { return (Escenario-M32 $Nombre $Casos @{} 'm59-mvn.ps1') }

# Cada Maven que se ha lanzado, en orden: carpeta, jto, target y args.
function Mavens-M59($E) {
  $f = Join-Path $E.Llamadas 'm59-mvn.log'
  if (-not (Test-Path -LiteralPath $f)) { return @() }
  return @([System.IO.File]::ReadAllLines($f) | ForEach-Object { $p = $_ -split '\|', 4; [pscustomobject]@{ carpeta = $p[0]; jto = $p[1]; target = $p[2]; args = $p[3] } })
}

# Prueba con JAVA_TOOL_OPTIONS = $Valor ($null: sin la variable) y lo deja como estaba.
function Prueba-M59-Jto($E, $Valor, [string[]]$A = @()) {
  $antes = $env:JAVA_TOOL_OPTIONS
  $env:JAVA_TOOL_OPTIONS = $Valor
  try { return (Prueba $E $A) }
  finally { $env:JAVA_TOOL_OPTIONS = $antes }
}

# Deja en la tarea de un caso el hash del arnes del original con que se decidio ($Valor), o quita el dato ($null: una tarea de antes de M59).
function Pon-Hash-M59($E, [string]$Id, $Valor) {
  $f = Get-Ruta $E.Local "tareas/$Id.json"
  $t = Lee-Json $f
  [void]$t.entradas.PSObject.Properties.Remove('hashArnesOriginal')
  if ($null -ne $Valor) { Add-Member -InputObject $t.entradas -NotePropertyName hashArnesOriginal -NotePropertyValue $Valor }
  [System.IO.File]::WriteAllText($f, (ConvertTo-Json -InputObject $t -Depth 8))
}

function Hash-M59($E, [string]$Id) { return [string](Lee-Json (Get-Ruta $E.Local "tareas/$Id.json")).entradas.hashArnesOriginal }

function Llamadas-Caso-M59($E, [string]$Id) { return @(Llamadas $E | Where-Object { $_.id -eq $Id }).Count }

$Pruebas['m59 (a) cada Maven del original lleva JAVA_TOOL_OPTIONS=-Dfile.encoding=UTF-8 (compilar, el arnes, los casos, mvn -v); con un -Xmx1g de antes lleva los dos y el entorno no acumula; el migrado, solo lo de antes'] = {
  $e = Escenario-M59 'm59-a' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M59-Jto $e $null
  Igual 'sin nada de antes: sale con 0' 0 $r.Codigo
  $o = @(Mavens-M59 $e | Where-Object { $_.carpeta -eq $e.CopiaOrig })
  Comprueba 'hay Mavens del original: compilar, mvn -v y casos' (@($o | Where-Object { $_.args -match 'test-compile' }).Count -ge 1 -and @($o | Where-Object { $_.args -match '(^| )-v( |$)' }).Count -eq 1 -and @($o | Where-Object { $_.args -match 'prueba\.local\.caso=caso-' }).Count -ge 2) (($o | ForEach-Object { $_.args }) -join ' / ')
  Comprueba 'todos con -Dfile.encoding=UTF-8' (@($o | Where-Object { $_.jto -cne '-Dfile.encoding=UTF-8' }).Count -eq 0) (($o | ForEach-Object { $_.jto } | Select-Object -Unique) -join ' / ')
  $m = @(Mavens-M59 $e | Where-Object { $_.carpeta -eq $e.CopiaMig })
  Comprueba 'hay Mavens del migrado, sin el ajuste (su JDK ya usa UTF-8)' ($m.Count -ge 2 -and @($m | Where-Object { $_.jto -cne '' }).Count -eq 0) (($m | ForEach-Object { $_.jto } | Select-Object -Unique) -join ' / ')
  $e2 = Escenario-M59 'm59-a2' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M59-Jto $e2 '-Xmx1g'
  Igual 'con -Xmx1g de antes: sale con 0' 0 $r.Codigo
  $todos = @(Mavens-M59 $e2)
  $o = @($todos | Where-Object { $_.carpeta -eq $e2.CopiaOrig })
  $m = @($todos | Where-Object { $_.carpeta -eq $e2.CopiaMig })
  Comprueba 'el original lleva lo de antes y el ajuste, cada uno una vez' (@($o | Where-Object { $_.jto -cne '-Xmx1g -Dfile.encoding=UTF-8' }).Count -eq 0 -and $o.Count -ge 5) (($o | ForEach-Object { $_.jto } | Select-Object -Unique) -join ' / ')
  Comprueba 'el migrado, solo lo de antes' ($m.Count -ge 2 -and @($m | Where-Object { $_.jto -cne '-Xmx1g' }).Count -eq 0) (($m | ForEach-Object { $_.jto } | Select-Object -Unique) -join ' / ')
  $iO = [array]::IndexOf(@($todos | ForEach-Object { $_.carpeta }), $e2.CopiaOrig)
  $iM = [array]::IndexOf(@($todos | ForEach-Object { $_.carpeta }), $e2.CopiaMig)
  Comprueba 'el primer Maven del migrado va despues del primero del original: el entorno ya estaba como antes' ($iO -ge 0 -and $iM -gt $iO) "original $iO, migrado $iM"
}

$Pruebas['m59 (b) la clave de las salidas guardadas del original lleva el ajuste de UTF-8: con otro ajuste, otra clave'] = {
  $f = Join-Path $Dir 'm59-b.ps1'
  $cuerpo = @'
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$CopiaOrig = 'copia'; $JavaLegacy = ''; $HeadOrig = 'abc'; $Local = 'local'; $Cfg = @{ MavenCasoRapido = @('-Dx') }; $VersionSalidas = 1; $LimiteRuta = 100
function Invoke-Maven($D, $O, $A, $Q) { return [pscustomobject]@{ Salida = @('Apache Maven 3.9.6', 'Java version: 1.8.0') } }
function Get-Mvn($R) { return 'mvn' }
function Get-HashCarpeta($D) { return 'hash' }
function Join-Ruta($A, $B) { return "$A/$B" }
$OpcionJvmOriginal = '-Dfile.encoding=UTF-8'
$a = Get-ClaveBaseOriginal
$OpcionJvmOriginal = '-Dfile.encoding=Cp1252'
$b = Get-ClaveBaseOriginal
"$a|$b"
'@
  $texto = Texto-De-Funciones $Script @('Get-ClaveBaseOriginal', 'Get-HashArnesOriginal', 'Get-EntornoMaven', 'Get-Hash256')
  [System.IO.File]::WriteAllText($f, ($texto + "`n" + $cuerpo))
  $r = Lanzar $f @()
  $k = @(($r.Salida.Trim()) -split '\|')
  Comprueba 'salen dos claves de 64 letras' ($k.Count -eq 2 -and $k[0] -match '^[0-9a-f]{64}$' -and $k[1] -match '^[0-9a-f]{64}$') (Cola $r.Salida)
  Comprueba 'distintas' ($k.Count -eq 2 -and $k[0] -cne $k[1]) (Cola $r.Salida)
}

$Pruebas['m59 (b2) las salidas del original guardadas con otra clave (las de antes) se ejecutan otra vez; con la clave de ahora ya guardada, se reutilizan'] = {
  $e = Escenario-M59 'm59-b2' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba $e
  Comprueba 'la primera vez se ejecutan los dos' ($r.Salida -match 'Original: se reutilizan las salidas de 0 caso\(s\) y se ejecutan 2\.') (Cola $r.Salida)
  $r = Prueba $e
  Comprueba 'con su clave guardada, se reutilizan los dos' ($r.Salida -match 'Original: se reutilizan las salidas de 2 caso\(s\) y se ejecutan 0\.') (Cola $r.Salida)
  $j = Get-Ruta $e.Local 'salidas/originales.json'
  $o = Lee-Json $j
  foreach ($c in @($o.casos)) { $c.clave = 'clave-de-antes' }
  [System.IO.File]::WriteAllText($j, (ConvertTo-Json -InputObject $o -Depth 6))
  $r = Prueba $e
  Comprueba 'con la clave de antes, se ejecutan otra vez los dos' ($r.Salida -match 'Original: se reutilizan las salidas de 0 caso\(s\) y se ejecutan 2\.') (Cola $r.Salida)
  $r = Prueba $e
  Comprueba 'y con la nueva ya guardada, se reutilizan' ($r.Salida -match 'Original: se reutilizan las salidas de 2 caso\(s\) y se ejecutan 0\.') (Cola $r.Salida)
}

$Pruebas['m59 (c) un caso no-aplica con el hash del arnes de antes y el arnes del original rehecho: se vuelve a preparar (una llamada nueva) y la consola cuenta 1; el caso con entradas no llama'] = {
  $e = Escenario-M59 'm59-c' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba $e @() 'caso-no-aplica:caso-cargaJob-01'
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  Igual 'el caso 1 queda sin probar en local' 'sin probar en local' (Caso $e 'cargaJob' 'caso-01').resultado
  Comprueba 'su tarea guarda el hash del arnes del original con que se decidio' ((Hash-M59 $e 'caso-cargaJob-01') -match '^[0-9a-f]{16,}$') (Hash-M59 $e 'caso-cargaJob-01')
  Igual 'y el caso con entradas, ninguno' '' (Hash-M59 $e 'caso-cargaJob-02')
  Pon-Hash-M59 $e 'caso-cargaJob-01' 'arnes-de-antes'
  $r = Prueba $e @('-RehacerOriginal')
  Igual 'con -RehacerOriginal sale con 0' 0 $r.Codigo
  Igual 'el caso no-aplica se prepara otra vez (una llamada nueva)' 2 (Llamadas-Caso-M59 $e 'caso-cargaJob-01')
  Igual 'el caso con entradas, no' 1 (Llamadas-Caso-M59 $e 'caso-cargaJob-02')
  Comprueba 'la consola cuenta 1 caso' ($r.Salida.Contains('1 caso(s) sin probar se vuelven a preparar: el test del original ha cambiado.')) (Cola $r.Salida)
  Comprueba 'el caso ya no sale sin probar en local' ((Caso $e 'cargaJob' 'caso-01').resultado -ne 'sin probar en local') (Caso $e 'cargaJob' 'caso-01').resultado
}

$Pruebas['m59 (d) un caso no-aplica de antes (sin hash guardado): sin rehacer el arnes del original no se prepara otra vez; con -RehacerOriginal, si'] = {
  $e = Escenario-M59 'm59-d' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba $e @() 'caso-no-aplica:caso-cargaJob-01'
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  Pon-Hash-M59 $e 'caso-cargaJob-01' $null
  $r = Prueba $e
  Igual 'sin la opcion sale con 0' 0 $r.Codigo
  Igual 'el caso no-aplica no llama a la IA' 1 (Llamadas-Caso-M59 $e 'caso-cargaJob-01')
  Comprueba 'y la consola no dice nada de prepararlo otra vez' (-not $r.Salida.Contains('se vuelven a preparar')) (Cola $r.Salida)
  Igual 'sigue sin probar en local' 'sin probar en local' (Caso $e 'cargaJob' 'caso-01').resultado
  $r = Prueba $e @('-RehacerOriginal')
  Igual 'con -RehacerOriginal sale con 0' 0 $r.Codigo
  Igual 'el caso no-aplica se prepara otra vez' 2 (Llamadas-Caso-M59 $e 'caso-cargaJob-01')
  Igual 'el caso con entradas, no' 1 (Llamadas-Caso-M59 $e 'caso-cargaJob-02')
  Comprueba 'la consola cuenta 1 caso' ($r.Salida.Contains('1 caso(s) sin probar se vuelven a preparar: el test del original ha cambiado.')) (Cola $r.Salida)
}

$Pruebas['m59 (e) el original se compila de cero en cada lanzamiento: la copia se rehace y lo que habia en su target (compilado con la codificacion de antes) ya no esta'] = {
  $e = Escenario-M59 'm59-e' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba $e
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  Comprueba 'la copia del original tiene target tras correr los casos' (Test-Path -LiteralPath (Join-Path $e.CopiaOrig 'target'))
  $clase = Join-Path $e.CopiaOrig 'target/classes/Viejo.class'
  [void](New-Item -ItemType Directory -Path (Split-Path $clase -Parent) -Force)
  [System.IO.File]::WriteAllText($clase, 'compilado con la codificacion de antes')
  $n = @(Mavens-M59 $e).Count
  $r = Prueba $e
  Igual 'la segunda vez sale con 0' 0 $r.Codigo
  $nuevos = @(@(Mavens-M59 $e) | Select-Object -Skip $n | Where-Object { $_.carpeta -eq $e.CopiaOrig })
  $c = @($nuevos | Where-Object { $_.args -match 'test-compile' })[0]
  Comprueba 'el primer Maven del original (compilar) no ve un target' ($c -and $c.target -eq 'no') "$($c.args) target=$($c.target)"
  Comprueba 'y la clase vieja ya no esta' (-not (Test-Path -LiteralPath $clase))
}

$Pruebas['m59 (k) un caso no-aplica hecho con el hash del arnes del original de ahora: un relanzamiento sin -RehacerOriginal no llama a la IA ni dice que se vuelve a preparar (ni una ni otra vez)'] = {
  $e = Escenario-M59 'm59-k' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba $e @() 'caso-no-aplica:caso-cargaJob-01'
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  Comprueba 'su tarea guarda el hash del arnes de ahora' ((Hash-M59 $e 'caso-cargaJob-01') -match '^[0-9a-f]{16,}$') (Hash-M59 $e 'caso-cargaJob-01')
  foreach ($vez in 2, 3) {
    $r = Prueba $e
    Igual "la vez $vez sale con 0" 0 $r.Codigo
    Igual "la vez ${vez}: el caso no-aplica no llama a la IA" 1 (Llamadas-Caso-M59 $e 'caso-cargaJob-01')
    Comprueba "la vez ${vez}: la consola no dice que se vuelva a preparar" (-not $r.Salida.Contains('se vuelven a preparar')) (Cola $r.Salida)
    Igual "la vez ${vez}: sigue sin probar en local" 'sin probar en local' (Caso $e 'cargaJob' 'caso-01').resultado
  }
}

$Pruebas['m59 (l) un caso no-aplica que se vuelve a preparar empieza con 0 intentos: tras un intento nuevo que sale bien, la tarea tiene 1 intento y no la suma con los de antes'] = {
  $e = Escenario-M59 'm59-l' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba $e @() 'caso-no-aplica:caso-cargaJob-01'
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  $t = Lee-Json (Get-Ruta $e.Local 'tareas/caso-cargaJob-01.json')
  Igual 'la primera vez, hecha con 1 intento' 'hecha,1' "$($t.estado),$($t.intentos)"
  Pon-Hash-M59 $e 'caso-cargaJob-01' 'arnes-de-antes'
  $r = Prueba $e @('-RehacerOriginal')
  Igual 'con -RehacerOriginal sale con 0' 0 $r.Codigo
  Igual 'el caso se prepara otra vez' 2 (Llamadas-Caso-M59 $e 'caso-cargaJob-01')
  $t = Lee-Json (Get-Ruta $e.Local 'tareas/caso-cargaJob-01.json')
  Igual 'la tarea queda hecha con 1 intento (el nuevo), no con 2' 'hecha,1' "$($t.estado),$($t.intentos)"
}

# ===================== M60: la pista de la propiedad que falta en el test =====================
# Estos escenarios usan los falsos m40 y m56-copilot.ps1 (RESCATE_M56 = '<nombre>:<id de tarea>', como los de M56) y m60-mvn.ps1, que da la salida de
# prop-export, placeholder, bind, bean-conexion, prop-dos o prop-create (ver m60-mvn.ps1) y, con los nombres de m56-mvn.ps1, la de siempre.

function Escenario-M60([string]$Nombre, $Casos) {
  $e = Escenario-M40 $Nombre $Casos 'm56'
  $aj = [ordered]@{ CopilotExe = (Join-Path $falsos 'm56-copilot.ps1'); MvnExe = (Join-Path $falsos 'm60-mvn.ps1'); SegundosPorLlamada = 60 }
  Escribe $e.Home 'ajustes.json' (ConvertTo-Json -InputObject $aj)
  return $e
}

# La pista de la propiedad sin valor, con las claves ya unidas (', ').
function Pista-M60([string]$Claves) {
  return "Falta una propiedad en el test: $Claves. En el servidor llega por el configmap o por una variable de entorno; en el test nadie le da valor. Dale un valor en el test (@TestPropertySource, @DynamicPropertySource o src/test/resources); si es una carpeta o un fichero, usa una carpeta temporal del test (@TempDir). No la sustituyas por un mock y no toques src/main."
}

# El motivo del arnes del original tras un 'mvn test' que acaba con la salida $Guion (dos intentos y atascado).
function Motivo-M60([string]$Nombre, [string]$Guion) {
  $e = Escenario-M60 $Nombre ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M56 $e ($Guion + ':arnes-original')
  return [pscustomobject]@{ E = $e; R = $r; T = (Tarea-Arnes $e 'original') }
}

$Pruebas['m60 (a) un job cuya propiedad no tiene valor (app.export.dir is not configured, dentro de la cadena de dos beans): el motivo del reintento y el de Show-Atascado llevan la propiedad y @TestPropertySource, y no @MockBean'] = {
  $x = Motivo-M60 'm60-a' 'prop-export'
  $p = Pista-M60 'app.export.dir'
  Igual 'sale con 1 (el arnes del original queda atascado)' 1 $x.R.Codigo
  Igual 'dos llamadas al arnes del original' 2 @(Llamadas-Arnes $x.E 'original').Count
  Igual 'la tarea queda atascada con dos intentos' 'atascada,2' "$($x.T.estado),$($x.T.intentos)"
  Comprueba 'el motivo lleva la pista de la propiedad, tras lo que ya decia (que no dejo estado.txt)' ($x.T.motivo.Contains($p) -and $x.T.motivo -match 'no ha dejado estado\.txt') $x.T.motivo
  Comprueba 'y no lleva @MockBean ni la pista del bean' ($x.T.motivo -notmatch '@MockBean' -and $x.T.motivo -notmatch 'El contexto de Spring no arranca') $x.T.motivo
  $reintento = Registro-Arnes $x.E 'original' 2
  Comprueba 'el prompt del reintento lleva la pista y no @MockBean' ($reintento.Contains($p) -and -not $reintento.Contains('@MockBean')) (Cola $reintento)
  $pegar = @($x.R.Salida -split "`n" | Where-Object { $_.Contains('Estoy ejecutando prueba-local.ps1') })
  Comprueba 'el texto para pegar en Copilot (Show-Atascado) la lleva y no lleva @MockBean' ($pegar.Count -eq 1 -and $pegar[0].Contains($p) -and -not $pegar[0].Contains('@MockBean')) (Cola $x.R.Salida)
  Comprueba 'y la consola del atasco, tambien (app.export.dir y @TestPropertySource)' ($x.R.Salida.Contains('ha quedado atascado: ') -and $x.R.Salida.Contains('app.export.dir') -and $x.R.Salida.Contains('@TestPropertySource')) (Cola $x.R.Salida)
}

$Pruebas['m60 (b) Could not resolve placeholder app.sftp.host: la pista con app.sftp.host'] = {
  $x = Motivo-M60 'm60-b' 'placeholder'
  Igual 'sale con 1' 1 $x.R.Codigo
  Comprueba 'el motivo lleva la pista con app.sftp.host' ($x.T.motivo.Contains((Pista-M60 'app.sftp.host'))) $x.T.motivo
}

$Pruebas['m60 (c) Failed to bind properties under app.limites: la pista con app.limites'] = {
  $x = Motivo-M60 'm60-c' 'bind'
  Igual 'sale con 1' 1 $x.R.Codigo
  Comprueba 'el motivo lleva la pista con app.limites' ($x.T.motivo.Contains((Pista-M60 'app.limites'))) $x.T.motivo
}

$Pruebas['m60 (d) la cadena del bean de M56 (Error getting clientes, sin propiedad): sigue la pista del bean y no la de la propiedad'] = {
  $x = Motivo-M60 'm60-d' 'bean'
  Igual 'sale con 1' 1 $x.R.Codigo
  Comprueba 'el motivo lleva la pista del bean' ($x.T.motivo.Contains($M56Bean)) $x.T.motivo
  Comprueba 'y no la de la propiedad' ($x.T.motivo -notmatch 'Falta una propiedad en el test') $x.T.motivo
}

$Pruebas['m60 (e) java.lang.IllegalStateException: Connection refused dentro de una cadena de bean, y un host is not set (sin punto): no hay pista de propiedad; un paquete con puntos no cuenta como clave'] = {
  $x = Motivo-M60 'm60-e' 'bean-conexion'
  Igual 'sale con 1' 1 $x.R.Codigo
  Comprueba 'el motivo no lleva la pista de la propiedad' ($x.T.motivo -notmatch 'Falta una propiedad en el test') $x.T.motivo
  Comprueba 'y sigue con la del bean' ($x.T.motivo -match 'El contexto de Spring no arranca: el bean clientesFinder falla al crearse \(java\.lang\.IllegalStateException: Connection refused\)') $x.T.motivo
}

$Pruebas['m60 (f) dos propiedades, y la misma repetida tres veces (de tres maneras): salen las dos, cada una una vez y en el orden en que salen'] = {
  $x = Motivo-M60 'm60-f' 'prop-dos'
  Igual 'sale con 1' 1 $x.R.Codigo
  Comprueba 'el motivo lleva la pista con app.sftp.host y app.export.dir' ($x.T.motivo.Contains((Pista-M60 'app.sftp.host, app.export.dir'))) $x.T.motivo
  Igual 'y la pista una sola vez' 1 ([regex]::Matches($x.T.motivo, 'Falta una propiedad en el test').Count)
}

$Pruebas['m60 (g) un CREATE TABLE que H2 rechaza junto con una propiedad sin valor: salen las dos pistas'] = {
  $x = Motivo-M60 'm60-g' 'prop-create'
  Igual 'sale con 1' 1 $x.R.Codigo
  $sentencia = 'CREATE TABLE IF NOT EXISTS PUBLIC.IF[*] (IF VARCHAR(4000),NOT VARCHAR(4000),EXISTS VARCHAR(4000),T_COMIS VARCHAR(4000))'
  $sql = "El test crea mal una tabla ($($sentencia.Substring(0, 60))). No saques las tablas del SQL del codigo: escribe un CREATE TABLE fijo para cada una de estas, con las columnas que usa el codigo: T_A ($SitioTablaM40)."
  Comprueba 'el motivo lleva la pista de la propiedad' ($x.T.motivo.Contains((Pista-M60 'app.export.dir'))) $x.T.motivo
  Comprueba 'y la del CREATE TABLE' ($x.T.motivo.Contains($sql)) $x.T.motivo
}

$Pruebas['m60 (h) cuatro propiedades distintas sin valor: la pista nombra las tres primeras y no la cuarta (tope de 3 claves)'] = {
  $x = Motivo-M60 'm60-h' 'prop-cuatro'
  Igual 'sale con 1' 1 $x.R.Codigo
  Comprueba 'el motivo lleva la pista con las tres primeras, en orden' ($x.T.motivo.Contains((Pista-M60 'app.uno.dir, app.dos.dir, app.tres.dir'))) $x.T.motivo
  Igual 'y las claves de la pista son solo esas tres (la cuarta, app.cuatro.dir, no)' 'app.uno.dir, app.dos.dir, app.tres.dir' ([regex]::Match($x.T.motivo, 'Falta una propiedad en el test: (.*?)\. En el servidor').Groups[1].Value)
}

# ===================== M61: el test que se escribe otra vez sabe que fallo antes =====================
# Estos escenarios usan m61-mvn.ps1 (lo de m40-mvn.ps1 y, ademas, los guiones de abajo) y el Copilot de m40 o el de m56:
#   RESCATE_M56 = '<nombre>:<id de tarea>'   el arnes cuyo id casa deja un test cuyo mvn test acaba con drop-en, drop-es o drop-create (ver m61-mvn.ps1)
#   RESCATE_M61 = '<nombre>:<regex sobre job/caso>'   create-es, create-en o create-despues: el original no corre el caso porque H2 rechaza un CREATE TABLE
#   RESCATE_M40: como en m40 (tablas=<n>/<T_A>:<id> y falta-tabla=T_A:<job/caso>)

$M61Sentencia = 'CREATE TABLE IF NOT EXISTS PUBLIC.IF[*] (IF VARCHAR(4000),NOT VARCHAR(4000),EXISTS VARCHAR(4000),T_COMIS VARCHAR(4000))'
$M61TablaMal = 'El test del original crea mal una tabla: ' + $M61Sentencia.Substring(0, 60)
$M61Bloque = 'Lo que fallo la otra vez'

function Escenario-M61([string]$Nombre, $Casos, [string]$Copilot = 'm40') {
  $e = Escenario-M40 $Nombre $Casos $Copilot
  $aj = [ordered]@{ CopilotExe = (Join-Path $falsos "$Copilot-copilot.ps1"); MvnExe = (Join-Path $falsos 'm61-mvn.ps1'); SegundosPorLlamada = 60 }
  Escribe $e.Home 'ajustes.json' (ConvertTo-Json -InputObject $aj)
  return $e
}

function Prueba-M61($E, [string[]]$A = @(), [string]$M61 = '', [string]$M40 = '', [string]$M56 = '') {
  $env:RESCATE_M61 = $M61; $env:RESCATE_M40 = $M40; $env:RESCATE_M56 = $M56
  try { return (Prueba $E $A) }
  finally { $env:RESCATE_M61 = ''; $env:RESCATE_M40 = ''; $env:RESCATE_M56 = '' }
}

# La pista del DROP de M61, con la tabla ($Tabla) que dice H2.
function Pista-M61([string]$Tabla) {
  return "El test borra las tablas una a una y una depende de otra ($Tabla). No borres tablas: usa una base H2 en memoria con un nombre unico en cada ejecucion (jdbc:h2:mem:<nombre>;DB_CLOSE_DELAY=-1) o, si tiene que limpiar, DROP ALL OBJECTS al principio."
}

# La pista del CREATE TABLE de M56 con el inventario del original de Escenario-M40 (T_A, en su Repo.java).
$M61PistaCreate = "El test crea mal una tabla ($($M61Sentencia.Substring(0, 60))). No saques las tablas del SQL del codigo: escribe un CREATE TABLE fijo para cada una de estas, con las columnas que usa el codigo: T_A ($SitioTablaM40)."

$Pruebas['m61 (a) el caso vacio del migrado falla con el DROP de H2 (en ingles y en espanol): el motivo del reintento y el de Show-Atascado llevan la pista con T_GRUPO, DROP ALL OBJECTS y jdbc:h2:mem:'] = {
  foreach ($l in @('en', 'es')) {
    $e = Escenario-M61 "m61-a-$l" ([ordered]@{ cargaJob = @('importe=10.00') }) 'm56'
    $r = Prueba-M61 $e -M56 "drop-${l}:arnes-migrado"
    $p = Pista-M61 'T_GRUPO'
    Igual "($l) sale con 1 (el arnes del migrado queda atascado)" 1 $r.Codigo
    Igual "($l) dos llamadas al arnes del migrado" 2 @(Llamadas-Arnes $e 'migrado').Count
    $t = Tarea-Arnes $e 'migrado'
    Igual "($l) la tarea queda atascada con dos intentos" 'atascada,2' "$($t.estado),$($t.intentos)"
    $reintento = Registro-Arnes $e 'migrado' 2
    Comprueba "($l) el prompt del reintento lleva la pista, con T_GRUPO, DROP ALL OBJECTS y jdbc:h2:mem:" ($reintento.Contains($p) -and $reintento.Contains('DROP ALL OBJECTS') -and $reintento.Contains('jdbc:h2:mem:')) (Cola $reintento)
    Comprueba "($l) el motivo de la tarea la lleva, tras lo que ya decia (que no dejo estado.txt)" ($t.motivo.Contains($p) -and $t.motivo -match 'no ha dejado estado\.txt') $t.motivo
    $pegar = @($r.Salida -split "`n" | Where-Object { $_.Contains('Estoy ejecutando prueba-local.ps1') })
    Comprueba "($l) el texto para pegar en Copilot (Show-Atascado) la lleva" ($pegar.Count -eq 1 -and $pegar[0].Contains($p)) (Cola $r.Salida)
    Comprueba "($l) el primer prompt, que no sabe de ningun fallo, no" (-not (Registro-Arnes $e 'migrado' 1).Contains('DROP ALL OBJECTS') -and -not (Registro-Arnes $e 'migrado' 1).Contains($M61Bloque)) ''
  }
}

$Pruebas['m61 (b) tres casos cuyo original no corre porque H2 rechaza un CREATE TABLE (en espanol, en ingles y desde la segunda ejecucion): cada motivo lleva el prefijo nuevo y sale una sola linea de aviso con 3 caso(s) y -RehacerOriginal'] = {
  $e = Escenario-M61 'm61-b' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00', 'importe=30.00') })
  $r = Prueba-M61 $e -M40 'tablas=1/T_A:arnes-original' -M61 'create-es:^cargaJob/caso-01;create-en:^cargaJob/caso-02;create-despues:^cargaJob/caso-03'
  Igual 'sale con 1 (ningun caso se compara)' 1 $r.Codigo
  Igual 'los tres casos: no se pudo preparar' 'no se pudo preparar,no se pudo preparar,no se pudo preparar' ((Resultados $e) -join ',')
  foreach ($c in @('caso-01', 'caso-02', 'caso-03')) {
    $m = [string](Caso $e 'cargaJob' $c).motivo
    Comprueba "$c lleva el prefijo nuevo y los 60 primeros caracteres de la sentencia" ($m.Contains($M61TablaMal)) $m
    Comprueba "$c no lleva la sentencia entera ni el texto de H2" (-not $m.Contains($M61Sentencia) -and $m -notmatch 'Sintaxis|Syntax error') $m
  }
  Igual 'el caso 1 (la IA lo prepara y no corre): una sola llamada, sin reintento' 1 @(Llamadas-Casos $e | Where-Object { $_.id -eq 'caso-cargaJob-01' }).Count
  Igual 'el caso 3 (corre al prepararlo y no al ejecutarlo): una sola llamada' 1 @(Llamadas-Casos $e | Where-Object { $_.id -eq 'caso-cargaJob-03' }).Count
  $linea = '3 caso(s) no se pudieron preparar porque el test del original crea mal sus tablas: relanza con -RehacerOriginal.'
  Igual 'la linea de aviso, una vez' 1 ([regex]::Matches($r.Salida, [regex]::Escape($linea))).Count
  Igual 'y ninguna otra con esa cuenta' 1 ([regex]::Matches($r.Salida, 'caso\(s\) no se pudieron preparar porque')).Count
}

$Pruebas['m61 (c) un caso sin tabla (m40) y otro con la tabla mal creada: salen los dos avisos, cada uno con 1'] = {
  $e = Escenario-M61 'm61-c' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba-M61 $e -M40 'tablas=1/T_A:arnes-original;falta-tabla=T_A:^cargaJob/caso-01' -M61 'create-es:^cargaJob/caso-02'
  Igual 'sale con 1' 1 $r.Codigo
  Igual 'los dos casos: no se pudo preparar' 'no se pudo preparar,no se pudo preparar' ((Resultados $e) -join ',')
  Comprueba 'el caso 1 lleva el motivo de la tabla que falta' ([string](Caso $e 'cargaJob' 'caso-01').motivo).Contains("La base de prueba no tiene la tabla T_A (el test no la crea; la usa $SitioTablaM40).") ''
  Comprueba 'el caso 2 lleva el prefijo de la tabla mal creada' ([string](Caso $e 'cargaJob' 'caso-02').motivo).Contains($M61TablaMal) ''
  $sin = '1 caso(s) no se pudieron preparar porque el test del original no crea sus tablas: relanza con -RehacerOriginal.'
  $mal = '1 caso(s) no se pudieron preparar porque el test del original crea mal sus tablas: relanza con -RehacerOriginal.'
  Igual 'el aviso de la tabla que falta, una vez' 1 ([regex]::Matches($r.Salida, [regex]::Escape($sin))).Count
  Igual 'el aviso de la tabla mal creada, una vez' 1 ([regex]::Matches($r.Salida, [regex]::Escape($mal))).Count
}

$Pruebas['m61 (d) con el prueba-local.json de unos casos que no se pudieron preparar por un CREATE TABLE y -RehacerOriginal: el primer intento del test del original lleva el bloque con la pista del CREATE TABLE y el inventario, una vez; el del migrado no'] = {
  $e = Escenario-M61 'm61-d' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00', 'importe=30.00') })
  $r = Prueba-M61 $e -M40 'tablas=1/T_A:arnes-original' -M61 'create-es:^cargaJob/caso-01;create-en:^cargaJob/caso-02;create-despues:^cargaJob/caso-03'
  Igual 'el primer lanzamiento sale con 1' 1 $r.Codigo
  Comprueba 'su primer prompt del original no lleva el bloque' (-not (Registro-Arnes $e 'original' 1).Contains($M61Bloque)) ''
  $r = Prueba $e @('-RehacerOriginal')
  Igual 'con -RehacerOriginal sale con 0' 0 $r.Codigo
  Igual 'los tres casos salen iguales' 'igual,igual,igual' ((Resultados $e) -join ',')
  $primero = Registro-Arnes $e 'original' 1
  Comprueba 'el primer intento del original lleva el bloque' ($primero.Contains($M61Bloque)) (Cola $primero)
  Comprueba 'con la pista del CREATE TABLE y el inventario de tablas' ($primero.Contains($M61PistaCreate)) (Cola $primero)
  Igual 'la pista, una sola vez (los tres casos dicen lo mismo)' 1 ([regex]::Matches($primero, 'El test crea mal una tabla')).Count
  Comprueba 'el primer intento del migrado, que se traduce del original, no lleva bloque (no tiene nada suyo que decir)' (-not (Registro-Arnes $e 'migrado' 1).Contains($M61Bloque)) ''
}

$Pruebas['m61 (d2) las pistas de los casos del prueba-local.json de antes: solo los no se pudo preparar, sin repetir y como mucho 3'] = {
  $e = Escenario-M61 'm61-d2' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba $e
  Igual 'el primer lanzamiento sale con 0' 0 $r.Codigo
  $quita = { param([string]$Clave) "En el original error.txt: java.lang.IllegalArgumentException: Could not resolve placeholder '$Clave' in value `"`${$Clave}`"" }
  $caso = { param([string]$N, [string]$Resultado, [string]$Clave) [ordered]@{ job = 'cargaJob'; caso = $N; titulo = ''; resultado = $Resultado; motivo = (& $quita $Clave); diferencias = @(); fallos = @() } }
  $o = Lee-Json $e.Json
  $o.casos = @((& $caso 'caso-01' 'distinto' 'app.k5'), (& $caso 'caso-02' 'no se pudo preparar' 'app.k1'), (& $caso 'caso-03' 'no se pudo preparar' 'app.k1'), (& $caso 'caso-04' 'no se pudo preparar' 'app.k2'), (& $caso 'caso-05' 'no se pudo preparar' 'app.k3'), (& $caso 'caso-06' 'no se pudo preparar' 'app.k4'))
  [System.IO.File]::WriteAllText($e.Json, (ConvertTo-Json -InputObject $o -Depth 20))
  $r = Prueba $e @('-RehacerOriginal')
  Igual 'con -RehacerOriginal sale con 0' 0 $r.Codigo
  $primero = Registro-Arnes $e 'original' 1
  Comprueba 'el bloque lleva las pistas de app.k1, app.k2 y app.k3' ($primero.Contains($M61Bloque) -and $primero.Contains((Pista-M60 'app.k1')) -and $primero.Contains((Pista-M60 'app.k2')) -and $primero.Contains((Pista-M60 'app.k3'))) (Cola $primero)
  Igual 'la de app.k1, una sola vez (dos casos la dicen)' 1 ([regex]::Matches($primero, [regex]::Escape((Pista-M60 'app.k1')))).Count
  Comprueba 'ni la cuarta distinta (app.k4: el tope es 3)' (-not $primero.Contains('app.k4')) (Cola $primero)
  Comprueba 'ni la de un caso distinto (app.k5: solo cuentan los que no se pudieron preparar)' (-not $primero.Contains('app.k5')) (Cola $primero)
}

$Pruebas['m61 (e) el test del migrado atascado con el DROP, relanzado sin opciones: el primer intento nuevo lleva el motivo de antes (y la huella de su tarea no cambia)'] = {
  $e = Escenario-M61 'm61-e' ([ordered]@{ cargaJob = @('importe=10.00') }) 'm56'
  $r = Prueba-M61 $e -M56 'drop-en:arnes-migrado'
  Igual 'el primer lanzamiento sale con 1 (migrado atascado)' 1 $r.Codigo
  $antes = Tarea-Arnes $e 'migrado'
  Igual 'la tarea queda atascada con dos intentos' 'atascada,2' "$($antes.estado),$($antes.intentos)"
  Comprueba 'su motivo lleva la pista del DROP' ($antes.motivo.Contains((Pista-M61 'T_GRUPO'))) $antes.motivo
  $deOriginal = @(Llamadas-Arnes $e 'original').Count   # (el del original pide dos: a su base le falta T_A, que el original usa en Repo.java)
  $r = Prueba $e
  Igual 'relanzado sin opciones sale con 0' 0 $r.Codigo
  Igual 'el migrado: dos llamadas de antes y una nueva' 3 @(Llamadas-Arnes $e 'migrado').Count
  Igual 'el original, que estaba hecho: ninguna nueva' $deOriginal @(Llamadas-Arnes $e 'original').Count
  $ahora = Tarea-Arnes $e 'migrado'
  Igual 'la tarea nueva queda hecha con un intento' 'hecha,1' "$($ahora.estado),$($ahora.intentos)"
  $primero = Registro-Arnes $e 'migrado' 1
  Comprueba 'el primer intento nuevo lleva el bloque' ($primero.Contains($M61Bloque)) (Cola $primero)
  Comprueba 'con el motivo de antes, entero' ($primero.Contains($antes.motivo)) (Cola $primero)
  Comprueba 'y su pista del DROP (T_GRUPO, DROP ALL OBJECTS)' ($primero.Contains((Pista-M61 'T_GRUPO')) -and $primero.Contains('DROP ALL OBJECTS')) (Cola $primero)
  Igual 'la huella de la tarea es la misma que antes del bloque' $antes.entradas.huella $ahora.entradas.huella
}

$Pruebas['m61 (f) un lanzamiento sin nada que rehacer: el prompt de los dos tests no lleva bloque, su huella no cambia y no hay llamadas'] = {
  $e = Escenario-M61 'm61-f' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba $e
  Igual 'el primer lanzamiento sale con 0' 0 $r.Codigo
  $huellas = @((Tarea-Arnes $e 'original').entradas.huella, (Tarea-Arnes $e 'migrado').entradas.huella) -join ','
  $llamadas = (Llamadas $e).Count
  foreach ($repo in @('original', 'migrado')) { Comprueba "el prompt del $repo no lleva bloque" (-not (Registro-Arnes $e $repo 1).Contains($M61Bloque)) '' }
  $r = Prueba $e
  Igual 'el segundo lanzamiento sale con 0' 0 $r.Codigo
  Igual 'sin llamadas nuevas' $llamadas (Llamadas $e).Count
  Igual 'la huella de los dos tests es la misma' $huellas (@((Tarea-Arnes $e 'original').entradas.huella, (Tarea-Arnes $e 'migrado').entradas.huella) -join ',')
  Comprueba 'las tareas no guardan nada de antes' ([string](Tarea-Arnes $e 'original').entradas.previo -eq '' -and [string](Tarea-Arnes $e 'migrado').entradas.previo -eq '') ''
  Comprueba 'y los tests guardados siguen siendo los de antes (no se escriben otra vez)' ((Tarea-Arnes $e 'original').estado -eq 'hecha' -and (Tarea-Arnes $e 'migrado').estado -eq 'hecha') ''
}

$Pruebas['m61 (g) el DROP junto con un CREATE TABLE que H2 rechaza: salen las dos pistas (el DROP es compatible con las demas)'] = {
  $e = Escenario-M61 'm61-g' ([ordered]@{ cargaJob = @('importe=10.00') }) 'm56'
  $r = Prueba-M61 $e -M56 'drop-create:arnes-migrado'
  Igual 'sale con 1' 1 $r.Codigo
  $t = Tarea-Arnes $e 'migrado'
  Comprueba 'el motivo lleva la pista del DROP' ($t.motivo.Contains((Pista-M61 'T_GRUPO'))) $t.motivo
  Comprueba 'y la del CREATE TABLE' ($t.motivo.Contains("El test crea mal una tabla ($($M61Sentencia.Substring(0, 60))).")) $t.motivo
}

$Pruebas['m61 (h) lo que fallo la otra vez no se pierde si un lanzamiento se para antes de llamar a la IA (se dice que no a la pregunta): el siguiente lo lleva en su primer intento'] = {
  $e = Escenario-M61 'm61-h' ([ordered]@{ cargaJob = @('importe=10.00') }) 'm56'
  $r = Prueba-M61 $e -M56 'drop-en:arnes-migrado'
  Igual 'el primer lanzamiento sale con 1 (migrado atascado)' 1 $r.Codigo
  $antes = Tarea-Arnes $e 'migrado'
  $n = (Llamadas $e).Count
  $r = Prueba $e @() '' 'n'
  Comprueba 'con n dice que no se ha hecho nada' ($r.Salida -match 'No se ha hecho nada') (Cola $r.Salida)
  Igual 'sin llamadas nuevas' $n (Llamadas $e).Count
  $r = Prueba $e
  Igual 'el tercer lanzamiento sale con 0' 0 $r.Codigo
  $primero = Registro-Arnes $e 'migrado' 1
  Comprueba 'su primer intento lleva el bloque, con el motivo del primer lanzamiento y su pista del DROP' ($primero.Contains($M61Bloque) -and $primero.Contains($antes.motivo) -and $primero.Contains((Pista-M61 'T_GRUPO'))) (Cola $primero)
}

# ===================== M62: la columna que el test del original no crea =====================
# Estos escenarios usan m62-mvn.ps1 (lo de m61-mvn.ps1 y, ademas, los guiones de abajo) y el Copilot de m40 o el de m56. El original lleva, ademas del Repo.java de
# M40 (INSERT INTO T_A (ID, NOMBRE) en la linea 4), un Zonas.java con el SQL en minusculas en la linea 4: select cod_zona, importe from T_A where cod_zona_old ...
#   RESCATE_M62 = 'nombre=TABLA.COLUMNA:regex sobre job/caso'   es o en (siempre) y despues o despues-en (desde la segunda ejecucion): el original no corre el caso
#                                                               porque a la tabla le falta la columna, en espanol o en ingles (ver m62-mvn.ps1)
#   RESCATE_M56 = 'columnas:arnes-original'                     el test del arnes del original falla con cinco columnas que faltan (COD_ZONA dos veces, IMPORTE, ID y NOMBRE)
#   RESCATE_M40: como en m40 (tablas=<n>/<T_A>:<id> y falta-tabla=T_A:<job/caso>)

$M62Sitio = 'src/main/java/com/acme/viejo/Zonas.java:4'
$M62Motivo = "El test del original no crea la columna T_A.COD_ZONA (la usa $M62Sitio)."
$M62Aviso = ' caso(s) no se pudieron preparar porque el test del original no crea una columna que usa el codigo: relanza con -RehacerOriginal.'

function Escenario-M62([string]$Nombre, $Casos, [string]$Copilot = 'm40') {
  $e = Escenario-M61 $Nombre $Casos $Copilot
  $aj = [ordered]@{ CopilotExe = (Join-Path $falsos "$Copilot-copilot.ps1"); MvnExe = (Join-Path $falsos 'm62-mvn.ps1'); SegundosPorLlamada = 60 }
  Escribe $e.Home 'ajustes.json' (ConvertTo-Json -InputObject $aj)
  Escribe $e.Legacy 'src/main/java/com/acme/viejo/Zonas.java' "package com.acme.viejo;`n`npublic class Zonas {`n  static final String Z = `"select cod_zona, importe from T_A where cod_zona_old is null`";`n}`n"
  [void](GitEn $e.Legacy @('add', 'src/main/java/com/acme/viejo/Zonas.java'))
  [void](GitEn $e.Legacy @('commit', '-q', '-m', 'zonas con sql'))
  return $e
}

function Prueba-M62($E, [string[]]$A = @(), [string]$M62 = '', [string]$M40 = '', [string]$M56 = '') {
  $env:RESCATE_M62 = $M62
  try { return (Prueba-M61 $E $A '' $M40 $M56) }
  finally { $env:RESCATE_M62 = '' }
}

# La pista de la columna que falta, con su tabla (o sin ella si $Tabla es '') y el sitio donde la usa el codigo.
function Pista-M62([string]$Tabla, [string]$Columna, [string]$Sitio = $M62Sitio) {
  if ($Tabla) { return "La tabla $Tabla de la base limpia no tiene la columna $Columna, que usa el codigo ($Sitio): anadela en su CREATE TABLE." }
  return "Una tabla de la base limpia no tiene la columna $Columna, que usa el codigo ($Sitio): anadela en su CREATE TABLE."
}

$Pruebas['m62 (a) un caso nuevo cuyo original falla con Columna/Column "COD_ZONA" y el codigo la usa (en espanol y en ingles; el SQL va en minusculas): el motivo lleva el prefijo, la tabla y el sitio, sin reintento (una sola llamada), y sale la linea de aviso'] = {
  foreach ($l in @('es', 'en')) {
    $e = Escenario-M62 "m62-a-$l" ([ordered]@{ cargaJob = @('importe=10.00') })
    $r = Prueba-M62 $e -M40 'tablas=1/T_A:arnes-original' -M62 "${l}=T_A.COD_ZONA:^cargaJob/caso-01"
    Igual "($l) sale con 1 (ningun caso se compara)" 1 $r.Codigo
    Igual "($l) el caso: no se pudo preparar" 'no se pudo preparar' ((Resultados $e) -join ',')
    $m = [string](Caso $e 'cargaJob' 'caso-01').motivo
    Comprueba "($l) el motivo lleva el prefijo, la tabla, la columna y el sitio" ($m.Contains($M62Motivo)) $m
    Comprueba "($l) y no el texto de H2 ni las columnas de la base de prueba" (-not $m.Contains('no encontrada') -and -not $m.Contains('not found') -and -not $m.Contains('Sus columnas')) $m
    Igual "($l) una sola llamada para el caso: no hay reintento" 1 @(Llamadas-Casos $e).Count
    $t = Tarea-Caso-M40 $e 'cargaJob' '01'
    Igual "($l) la tarea queda atascada tras un solo intento" 'atascada,1' "$($t.estado),$($t.intentos)"
    Igual "($l) la linea de aviso, una vez" 1 ([regex]::Matches($r.Salida, [regex]::Escape("1$M62Aviso"))).Count
  }
}

$Pruebas['m62 (b) una columna que el codigo no usa (QQ): el motivo de siempre (la tabla, la columna y las de la base de prueba), con reintento y sin aviso'] = {
  $e = Escenario-M62 'm62-b' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M62 $e -M40 'tablas=1/T_A:arnes-original' -M62 'es=T_A.QQ:^cargaJob/caso-01'
  Igual 'sale con 1' 1 $r.Codigo
  $m = [string](Caso $e 'cargaJob' 'caso-01').motivo
  Comprueba 'el motivo es el de siempre, con las columnas de la base de prueba' ($m.Contains('La tabla T_A no tiene la columna QQ. Sus columnas en la base de prueba son: ID, NOMBRE.')) $m
  Comprueba 'y no lleva el prefijo' (-not $m.Contains('El test del original no crea la columna')) $m
  Igual 'dos llamadas para el caso: hay reintento' 2 @(Llamadas-Casos $e).Count
  $t = Tarea-Caso-M40 $e 'cargaJob' '01'
  Igual 'la tarea queda atascada tras dos intentos' 'atascada,2' "$($t.estado),$($t.intentos)"
  Comprueba 'el prompt del reintento lleva el motivo de siempre' ((Registro-Caso-M40 $e 'cargaJob' '01' 2).Contains('La tabla T_A no tiene la columna QQ.')) (Cola (Registro-Caso-M40 $e 'cargaJob' '01' 2))
  Comprueba 'no sale la linea de aviso de la columna' (-not $r.Salida.Contains('no crea una columna que usa el codigo')) (Cola $r.Salida)
}

$Pruebas['m62 (c) tres casos que corrian al prepararlos y cuyo original nuevo ya no crea la columna (en espanol y en ingles): cada motivo lleva el prefijo y sale una sola linea de aviso con 3 caso(s) y -RehacerOriginal'] = {
  $e = Escenario-M62 'm62-c' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00', 'importe=30.00') })
  $r = Prueba-M62 $e -M40 'tablas=1/T_A:arnes-original' -M62 'despues=T_A.COD_ZONA:^cargaJob/caso-01;despues-en=T_A.COD_ZONA:^cargaJob/caso-02;despues=T_A.COD_ZONA:^cargaJob/caso-03'
  Igual 'sale con 1 (ningun caso se compara)' 1 $r.Codigo
  Igual 'los tres casos: no se pudo preparar' 'no se pudo preparar,no se pudo preparar,no se pudo preparar' ((Resultados $e) -join ',')
  foreach ($c in @('caso-01', 'caso-02', 'caso-03')) {
    $m = [string](Caso $e 'cargaJob' $c).motivo
    Comprueba "$c lleva el prefijo, la tabla, la columna y el sitio" ($m.Contains($M62Motivo)) $m
    Comprueba "$c no lleva el texto de H2 ni el de siempre" (-not $m.Contains('no encontrada') -and -not $m.Contains('not found') -and -not $m.StartsWith('En el original')) $m
  }
  Igual 'una sola llamada por caso (corrian al prepararlos)' 3 @(Llamadas-Casos $e).Count
  Igual 'la linea de aviso, una vez' 1 ([regex]::Matches($r.Salida, [regex]::Escape("3$M62Aviso"))).Count
  Igual 'y ninguna otra con esa cuenta' 1 ([regex]::Matches($r.Salida, 'caso\(s\) no se pudieron preparar porque')).Count
}

$Pruebas['m62 (c2) un caso sin tabla (m40) y otro sin columna: salen los dos avisos, cada uno con 1'] = {
  $e = Escenario-M62 'm62-c2' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba-M62 $e -M40 'tablas=1/T_A:arnes-original;falta-tabla=T_A:^cargaJob/caso-01' -M62 'es=T_A.COD_ZONA:^cargaJob/caso-02'
  Igual 'sale con 1' 1 $r.Codigo
  Igual 'los dos casos: no se pudo preparar' 'no se pudo preparar,no se pudo preparar' ((Resultados $e) -join ',')
  Comprueba 'el caso 1 lleva el motivo de la tabla que falta' ([string](Caso $e 'cargaJob' 'caso-01').motivo).Contains("La base de prueba no tiene la tabla T_A (el test no la crea; la usa $SitioTablaM40).") ''
  Comprueba 'el caso 2 lleva el prefijo de la columna' ([string](Caso $e 'cargaJob' 'caso-02').motivo).Contains($M62Motivo) ''
  $sin = '1 caso(s) no se pudieron preparar porque el test del original no crea sus tablas: relanza con -RehacerOriginal.'
  Igual 'el aviso de la tabla que falta, una vez' 1 ([regex]::Matches($r.Salida, [regex]::Escape($sin))).Count
  Igual 'el aviso de la columna, una vez' 1 ([regex]::Matches($r.Salida, [regex]::Escape("1$M62Aviso"))).Count
}

$Pruebas['m62 (d) con el prueba-local.json de unos casos sin la columna y -RehacerOriginal: el primer intento del test del original lleva el bloque con la pista de T_A y COD_ZONA, una vez; el del migrado no'] = {
  $e = Escenario-M62 'm62-d' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00', 'importe=30.00') })
  $r = Prueba-M62 $e -M40 'tablas=1/T_A:arnes-original' -M62 'despues=T_A.COD_ZONA:^cargaJob/caso-01;despues-en=T_A.COD_ZONA:^cargaJob/caso-02;es=T_A.COD_ZONA:^cargaJob/caso-03'
  Igual 'el primer lanzamiento sale con 1' 1 $r.Codigo
  Comprueba 'su primer prompt del original no lleva el bloque' (-not (Registro-Arnes $e 'original' 1).Contains($M61Bloque)) ''
  $r = Prueba $e @('-RehacerOriginal')
  Igual 'con -RehacerOriginal sale con 0' 0 $r.Codigo
  Igual 'los tres casos salen iguales' 'igual,igual,igual' ((Resultados $e) -join ',')
  $primero = Registro-Arnes $e 'original' 1
  Comprueba 'el primer intento del original lleva el bloque' ($primero.Contains($M61Bloque)) (Cola $primero)
  Comprueba 'con la pista de T_A, COD_ZONA y el sitio' ($primero.Contains((Pista-M62 'T_A' 'COD_ZONA'))) (Cola $primero)
  Igual 'la pista, una sola vez (los tres casos dicen lo mismo)' 1 ([regex]::Matches($primero, 'no tiene la columna COD_ZONA')).Count
  Comprueba 'el primer intento del migrado, que se traduce del original, no lleva bloque' (-not (Registro-Arnes $e 'migrado' 1).Contains($M61Bloque)) ''
}

$Pruebas['m62 (d2) un prueba-local.json de antes de M62 (el motivo trae el error de H2, en espanol y en ingles, o sin SQL): la pista sale con la tabla del SQL o sin tabla, y una columna que el codigo no usa (ZONA) no da pista'] = {
  $e = Escenario-M62 'm62-d2' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba $e
  Igual 'el primer lanzamiento sale con 0' 0 $r.Codigo
  $h2 = { param([string]$Dicho, [string]$Sql) "En el original error.txt: org.springframework.jdbc.datasource.init.ScriptStatementFailedException: Failed to execute SQL script statement #1 of file [C:\obra\datos.sql]: $Sql; nested exception is org.h2.jdbc.JdbcSQLSyntaxErrorException: $Dicho" }
  $sql = { param([string]$C) "INSERT INTO T_A (ID, $C) VALUES ('01', 'Z1')" }
  $caso = { param([string]$N, [string]$Motivo) [ordered]@{ job = 'cargaJob'; caso = $N; titulo = ''; resultado = 'no se pudo preparar'; motivo = $Motivo; diferencias = @(); fallos = @() } }
  $o = Lee-Json $e.Json
  $o.casos = @(
    (& $caso 'caso-01' (& $h2 'Columna "COD_ZONA" no encontrada; Sentencia SQL: ' (& $sql 'COD_ZONA'))),
    (& $caso 'caso-02' (& $h2 'Column "COD_ZONA" not found; SQL statement: ' (& $sql 'COD_ZONA'))),
    (& $caso 'caso-03' (& $h2 'Columna "ZONA" no encontrada; Sentencia SQL: ' (& $sql 'ZONA'))),
    (& $caso 'caso-04' 'En el original error.txt: org.h2.jdbc.JdbcSQLSyntaxErrorException: Column "NOMBRE" not found'))
  [System.IO.File]::WriteAllText($e.Json, (ConvertTo-Json -InputObject $o -Depth 20))
  $r = Prueba $e @('-RehacerOriginal')
  Igual 'con -RehacerOriginal sale con 0' 0 $r.Codigo
  $primero = Registro-Arnes $e 'original' 1
  Comprueba 'el bloque lleva la pista de T_A y COD_ZONA, con la tabla que sale del SQL' ($primero.Contains($M61Bloque) -and $primero.Contains((Pista-M62 'T_A' 'COD_ZONA'))) (Cola $primero)
  Igual 'la de COD_ZONA, una sola vez (dos casos la dicen)' 1 ([regex]::Matches($primero, 'no tiene la columna COD_ZONA')).Count
  Comprueba 'y la de NOMBRE, sin tabla (el motivo no trae SQL), con el sitio de Repo.java' ($primero.Contains((Pista-M62 '' 'NOMBRE' $SitioTablaM40))) (Cola $primero)
  Comprueba 'ZONA solo sale dentro de otras palabras en el codigo: no da pista' (-not $primero.Contains('columna ZONA')) (Cola $primero)
}

$Pruebas['m62 (e) el test del original falla con cinco columnas que faltan (COD_ZONA dos veces, IMPORTE, ID y NOMBRE): la pista nombra las tres primeras distintas, una vez cada una y en orden, con su tabla y su sitio'] = {
  $e = Escenario-M62 'm62-e' ([ordered]@{ cargaJob = @('importe=10.00') }) 'm56'
  $r = Prueba-M62 $e -M56 'columnas:arnes-original'
  Igual 'sale con 1 (el arnes del original queda atascado)' 1 $r.Codigo
  $t = Tarea-Arnes $e 'original'
  Igual 'la tarea queda atascada con dos intentos' 'atascada,2' "$($t.estado),$($t.intentos)"
  $pista = (Pista-M62 'T_A' 'COD_ZONA') + ' ' + (Pista-M62 'T_A' 'IMPORTE') + ' ' + (Pista-M62 'T_A' 'ID' $SitioTablaM40)
  Comprueba 'el motivo lleva las tres pistas, en una sola' ($t.motivo.Contains($pista)) $t.motivo
  Igual 'y las columnas son solo esas tres, cada una una vez (NOMBRE, la cuarta distinta, no)' 'COD_ZONA,IMPORTE,ID' (@([regex]::Matches($t.motivo, 'no tiene la columna (\w+)') | ForEach-Object { $_.Groups[1].Value }) -join ',')
  Comprueba 'el prompt del reintento lleva la pista' ((Registro-Arnes $e 'original' 2).Contains($pista)) (Cola (Registro-Arnes $e 'original' 2))
}

$Pruebas['m62 (f) una columna que solo aparece dentro de otras palabras del codigo (ZONA, en COD_ZONA y COD_ZONA_OLD): no cuenta como usada, y el caso sigue como hoy (motivo de siempre y reintento)'] = {
  $e = Escenario-M62 'm62-f' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M62 $e -M40 'tablas=1/T_A:arnes-original' -M62 'es=T_A.ZONA:^cargaJob/caso-01'
  Igual 'sale con 1' 1 $r.Codigo
  $m = [string](Caso $e 'cargaJob' 'caso-01').motivo
  Comprueba 'el motivo es el de siempre' ($m.Contains('La tabla T_A no tiene la columna ZONA.') -and -not $m.Contains('El test del original no crea la columna')) $m
  Igual 'dos llamadas para el caso: hay reintento' 2 @(Llamadas-Casos $e).Count
  Comprueba 'no sale la linea de aviso de la columna' (-not $r.Salida.Contains('no crea una columna que usa el codigo')) (Cola $r.Salida)
}

# ===================== M63: un fichero de salida con la ruta de origen larga =====================
# Estas pruebas lanzan, en un .ps1 con solo las funciones de la copia de salidas, Get-RutaLarga, Copy-Fichero y Copy-Salida. Linux admite rutas de mas de 259 letras,
# asi que lo de Windows se simula con $SoWindows (la plataforma que lee Get-RutaLarga) o con su segundo parametro; que el prefijo \\?\ funcione en Windows
# 5.1 (.NET Framework 4.6.2 o posterior) no se puede probar aqui.

# Lanza $Cuerpo con las funciones de la copia de salidas y una linea 'K valor' por cada Salida; devuelve las lineas por su clave K.
function Lanza-M63([string]$Nombre, [string]$Cuerpo) {
  $f = Join-Path $Dir "m63-$Nombre.ps1"
  $pre = @'
$ErrorActionPreference = 'Stop'
$Inv = [System.Globalization.CultureInfo]::InvariantCulture
$RutasCopia = @(); $Hoy = @()
$LimiteRuta = 259
$Local = 'x' * 50
$SoWindows = $false
$script:AvisoCarpetaCorta = $false
$hoy = [datetime]'2026-11-21'
function Salida([string]$K, $V) { if ($null -eq $V) { $V = '(null)' }; $K + ' ' + $V }
'@
  $raizPs = Split-Path -Parent $Script
  $texto = 'param([string]$Raiz)' + "`n" + (Texto-De-Funciones $Script @('Get-RutaLarga', 'Copy-ConDotNet', 'Copy-Fichero', 'Copy-Salida', 'Get-RelSalida', 'Get-LargoRuta', 'Get-NombreCorto', 'Test-NombreCorto', 'Get-Normal')) + "`n" +
    (Texto-De-Funciones (Join-Path $raizPs 'tareas.ps1') @('Get-Hash8')) + "`n" + (Texto-De-Funciones (Join-Path $raizPs 'comun.ps1') @('Join-Ruta', 'Get-Rel', 'Aviso')) + "`n" + $pre + "`n" + $Cuerpo
  [System.IO.File]::WriteAllText($f, $texto)
  $r = Lanzar $f @($Dir)
  $v = @{}
  foreach ($l in ($r.Salida -split "`r?`n")) { if ($l -match '^([A-Z][0-9]?) (.*)$') { $v[$Matches[1]] = $Matches[2] } }
  return [pscustomobject]@{ R = $r; V = $v }
}

$Pruebas['m63 (a) la ruta de origen con prefijo: en Windows, una de mas de 259 letras lleva \\?\ (y \\?\UNC\ si es de red, con las / en \); una corta, la de 259 y las que ya lo llevan, no; fuera de Windows, ninguna'] = {
  $x = Lanza-M63 'a' @'
$largo = 'C:\Trabajo\' + ('a' * 289)
Salida 'A' ((Get-RutaLarga $largo $true) -ceq ('\\?\' + $largo))
Salida 'B' ((Get-RutaLarga ('C:\Trabajo\' + ('a' * 189)) $true) -ceq ('C:\Trabajo\' + ('a' * 189)))
Salida 'C' ((Get-RutaLarga ('\\servidor\recurso\' + ('a' * 281)) $true) -ceq ('\\?\UNC\servidor\recurso\' + ('a' * 281)))
Salida 'D' ((Get-RutaLarga $largo $false) -ceq $largo)
Salida 'E' ((Get-RutaLarga ('C:\' + ('a' * 256)) $true) -ceq ('C:\' + ('a' * 256)))
Salida 'F' ((Get-RutaLarga ('C:\' + ('a' * 257)) $true) -ceq ('\\?\C:\' + ('a' * 257)))
Salida 'G' ((Get-RutaLarga ('C:/Trabajo/' + ('a' * 289)) $true) -ceq ('\\?\C:\Trabajo\' + ('a' * 289)))
Salida 'H' ((Get-RutaLarga ('\\?\' + $largo) $true) -ceq ('\\?\' + $largo))
$SoWindows = $true
Salida 'I' ((Get-RutaLarga $largo) -ceq ('\\?\' + $largo))
$SoWindows = $false
Salida 'J' ((Get-RutaLarga $largo) -ceq $largo)
'@
  Igual 'el script de la prueba sale con 0' 0 $x.R.Codigo
  Igual 'A: 300 letras en Windows: \\?\ y la ruta' 'True' $x.V['A']
  Igual 'B: una de 200 letras, tal cual' 'True' $x.V['B']
  Igual 'C: una de red lleva \\?\UNC\ y la ruta sin las dos barras' 'True' $x.V['C']
  Igual 'D: en un sistema que no es Windows, tal cual' 'True' $x.V['D']
  Igual 'E: una de 259 letras (el limite), tal cual' 'True' $x.V['E']
  Igual 'F: una de 260 letras ya lleva el prefijo' 'True' $x.V['F']
  Igual 'G: las / se cambian por \ (con \\?\ Windows no las normaliza)' 'True' $x.V['G']
  Igual 'H: una que ya lleva el prefijo no lleva otro' 'True' $x.V['H']
  Igual 'I: sin segundo parametro, lee $SoWindows: en Windows lleva el prefijo' 'True' $x.V['I']
  Igual 'J: y fuera de Windows, no' 'True' $x.V['J']
}

$Pruebas['m63 (b) Copy-Salida con un origen de mas de 260 letras de verdad (en Linux): copia el fichero y no hay nada sin guardar; con Windows simulado lo lee con el prefijo (y un origen corto, sin el)'] = {
  $x = Lanza-M63 'b' @'
$de = Join-Path $Raiz ('m63-origen/' + ('o' * 100) + '/' + ('p' * 100) + '/' + ('q' * 60))
New-Item -ItemType Directory -Path (Join-Path $de 'ficheros/logs') -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $de 'ficheros/logs/dato.txt'), 'hola')
$f = @(Get-ChildItem -LiteralPath $de -Recurse -File)[0].FullName
Salida 'A' ($f.Length -gt 260)
$no = @(Copy-Salida $de (Join-Path $Raiz 'm63-destino') 'cargaJob' 'caso' @($hoy))
Salida 'B' $no.Count
Salida 'C' ([System.IO.File]::ReadAllText((Join-Path $Raiz 'm63-destino/ficheros/logs/dato.txt')))
$SoWindows = $true
$no = @(Copy-Salida $de (Join-Path $Raiz 'm63-destino2') 'cargaJob' 'caso' @($hoy))
Salida 'D' $no.Count
Salida 'E' ($no.Count -gt 0 -and $no[0].motivo.Contains('\\?\'))
Salida 'F' (Test-Path -LiteralPath (Join-Path $Raiz 'm63-destino2/ficheros/logs/dato.txt'))
$corto = Join-Path $Raiz 'm63-corto'
New-Item -ItemType Directory -Path $corto -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $corto 'dato.txt'), 'hola')
$no = @(Copy-Salida $corto (Join-Path $Raiz 'm63-destino3') 'cargaJob' 'caso' @($hoy))
Salida 'G' $no.Count
Salida 'H' (Test-Path -LiteralPath (Join-Path $Raiz 'm63-destino3/dato.txt'))
'@
  Igual 'el script de la prueba sale con 0' 0 $x.R.Codigo
  Igual 'A: la ruta del fichero de origen pasa de 260 letras' 'True' $x.V['A']
  Igual 'B: Copy-Salida no deja nada sin guardar' 0 $x.V['B']
  Igual 'C: y el fichero copiado tiene su contenido' 'hola' $x.V['C']
  Igual 'D: con Windows simulado, el origen largo se lee con \\?\ (que en Linux no existe): un fichero sin guardar' 1 $x.V['D']
  Igual 'E: y su motivo dice la ruta con el prefijo' 'True' $x.V['E']
  Igual 'F: sin copiar' 'False' $x.V['F']
  Igual 'G: un origen corto con Windows simulado no se toca: nada sin guardar' 0 $x.V['G']
  Igual 'H: y se copia' 'True' $x.V['H']
}

$Pruebas['m63 (c) un origen que no existe sigue dando el motivo de siempre (el de Copy-Item), y con una ruta larga y Windows simulado tampoco se copia en silencio'] = {
  $x = Lanza-M63 'c' @'
$sin = Join-Path $Raiz 'm63-sin/no-existe.txt'
$m1 = ''; $m2 = ''
try { Copy-Fichero $sin (Join-Path $Raiz 'm63-x/no.txt') } catch { $m1 = $_.Exception.Message }
try { Copy-Item -LiteralPath $sin -Destination (Join-Path $Raiz 'm63-x/no.txt') -Force } catch { $m2 = $_.Exception.Message }
Salida 'A' ($m1 -ne '')
Salida 'B' ($m1 -ceq $m2)
$SoWindows = $true
$m3 = ''
try { Copy-Fichero (Join-Path $Raiz ('m63-sin/' + ('z' * 100) + '/' + ('y' * 100) + '/' + ('x' * 60) + '.txt')) (Join-Path $Raiz 'm63-x/no2.txt') } catch { $m3 = $_.Exception.Message }
Salida 'C' ($m3 -ne '')
Salida 'D' (Test-Path -LiteralPath (Join-Path $Raiz 'm63-x/no2.txt'))
'@
  Igual 'el script de la prueba sale con 0' 0 $x.R.Codigo
  Igual 'A: con un origen corto que no existe, Copy-Fichero falla' 'True' $x.V['A']
  Igual 'B: con el mismo mensaje que Copy-Item (el motivo de hoy)' 'True' $x.V['B']
  Igual 'C: con un origen largo que no existe y Windows simulado, falla tambien' 'True' $x.V['C']
  Igual 'D: y no deja ningun fichero' 'False' $x.V['D']
}

$Pruebas['m63 (d) con un origen largo en Windows, Copy-Fichero prueba primero Copy-Item con la ruta con \\?\ y, si falla, .NET con la misma ruta; si el primero copia no llega al segundo, y uno corto no pasa por .NET'] = {
  $x = Lanza-M63 'd' @'
$SoWindows = $true
$de = Join-Path $Raiz ('m63-d/' + ('o' * 100) + '/' + ('p' * 100) + '/' + ('q' * 60) + '.txt')
New-Item -ItemType Directory -Path (Split-Path $de -Parent) -Force | Out-Null
[System.IO.File]::WriteAllText($de, 'hola')
$corto = Join-Path $Raiz 'm63-d/corto.txt'
[System.IO.File]::WriteAllText($corto, 'hola')
$script:Llamadas = @()
$script:ItemFalla = $true
function Copy-Item {
  param([string]$LiteralPath, [string]$Destination, [switch]$Force, $ErrorAction)
  $script:Llamadas += 'item:' + $LiteralPath
  if ($script:ItemFalla) { throw 'Copy-Item falla' }
  Microsoft.PowerShell.Management\Copy-Item -LiteralPath $de -Destination $Destination -Force
}
function Copy-ConDotNet {
  param([string]$Origen, [string]$A)
  $script:Llamadas += 'net:' + $Origen
  [System.IO.File]::Copy($de, $A, $true)
}
$larga = Get-RutaLarga $de $true
Copy-Fichero $de (Join-Path $Raiz 'm63-d/destino1.txt')
Salida 'A' (($script:Llamadas -join '|') -ceq ('item:' + $larga + '|net:' + $larga))
Salida 'B' ([System.IO.File]::ReadAllText((Join-Path $Raiz 'm63-d/destino1.txt')))
$script:Llamadas = @(); $script:ItemFalla = $false
Copy-Fichero $de (Join-Path $Raiz 'm63-d/destino2.txt')
Salida 'C' (($script:Llamadas -join '|') -ceq ('item:' + $larga))
Salida 'D' ([System.IO.File]::ReadAllText((Join-Path $Raiz 'm63-d/destino2.txt')))
$script:Llamadas = @(); $script:ItemFalla = $true
$ok = $true
try { Copy-Fichero $corto (Join-Path $Raiz 'm63-d/destino3.txt') } catch { $ok = $false }
Salida 'E' (($script:Llamadas -join '|') -ceq ('item:' + $corto))
Salida 'F' (-not $ok)
$script:Llamadas = @(); $script:ItemFalla = $false
Copy-Fichero $corto (Join-Path $Raiz 'm63-d/destino4.txt')
Salida 'G' (($script:Llamadas -join '|') -ceq ('item:' + $corto))
'@
  Igual 'el script de la prueba sale con 0' 0 $x.R.Codigo
  Igual 'A: si Copy-Item falla, prueba .NET con la misma ruta con prefijo, despues de Copy-Item' 'True' $x.V['A']
  Igual 'B: y el fichero se copia' 'hola' $x.V['B']
  Igual 'C: si Copy-Item copia, no llega a .NET' 'True' $x.V['C']
  Igual 'D: y el fichero se copia' 'hola' $x.V['D']
  Igual 'E: un origen corto va solo con Copy-Item y su ruta, sin prefijo' 'True' $x.V['E']
  Igual 'F: y si falla, falla (no hay segundo intento)' 'True' $x.V['F']
  Igual 'G: y si copia, se copia una sola vez' 'True' $x.V['G']
}

$Pruebas['m63 (e) con un origen largo en Windows y las dos copias fallando, Copy-Salida deja el fichero sin guardar con el motivo del ultimo error (el de .NET)'] = {
  $x = Lanza-M63 'e' @'
$SoWindows = $true
$de = Join-Path $Raiz ('m63-e/' + ('o' * 100) + '/' + ('p' * 100) + '/' + ('q' * 60))
New-Item -ItemType Directory -Path $de -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $de 'dato.txt'), 'hola')
function Copy-Item { param([string]$LiteralPath, [string]$Destination, [switch]$Force, $ErrorAction) throw 'Copy-Item falla' }
function Copy-ConDotNet { param([string]$De, [string]$A) throw 'File.Copy falla' }
$no = @(Copy-Salida $de (Join-Path $Raiz 'm63-e/destino') 'cargaJob' 'caso' @($hoy))
Salida 'A' $no.Count
Salida 'B' $no[0].motivo
Salida 'C' $no[0].fichero
Salida 'D' (Test-Path -LiteralPath (Join-Path $Raiz 'm63-e/destino/dato.txt'))
'@
  Igual 'el script de la prueba sale con 0' 0 $x.R.Codigo
  Igual 'A: un fichero sin guardar' 1 $x.V['A']
  Igual 'B: con el mensaje del ultimo error, el de .NET' 'File.Copy falla' $x.V['B']
  Igual 'C: el del fichero' 'dato.txt' $x.V['C']
  Igual 'D: sin copiar' 'False' $x.V['D']
}

# ===================== M64: el test del migrado prepara lo que preparan los tests del repo =====================
# Escenario-M64 es el de M61 con tests de ejemplo (@SpringBootTest, @SpringBatchTest) en las copias:
#   migrado (rescate): CargaIT.java con un @BeforeEach en la linea 8 (preparaContexto) y OtraIT.java con un @Before en la 7 (inicia)
#   original: ViejoIT.java con un @BeforeEach en la linea 7 (preparaViejo)
# Con $SinPrepara los del migrado no tienen ningun metodo de preparacion (SinIT.java) y hay ademas un UnitTest.java con @BeforeEach pero sin arrancar el batch.

$M64Cabecera = 'Estos tests preparan algo antes de lanzar el job: '
$M64Fin = 'El test del original puede ser de otra version del framework y no hacerlo. Si este repositorio lo necesita (por ejemplo, un contexto que en produccion pone el arranque de la aplicacion), haz lo mismo en tu test antes de lanzar cada job. No lo uses para tapar un fallo del codigo de src/main.'
$M64Frase = 'Si viene de una clase de una libreria porque al test le falta algo que en produccion prepara el arranque, preparalo como los tests de ejemplo. Si viene del codigo de src/main, no lo tapes: es un fallo del migrado.'
$M64Npe = 'java.lang.NullPointerException: Cannot invoke "com.acme.marco.traza.ContextoTraza.aConstructor()" because "contexto" is null'
$M64Otra = 'java.lang.IllegalStateException: Failed to load ApplicationContext'
$M64Ruta = 'src/test/java/com/acme/nuevo/'

function Escenario-M64([string]$Nombre, $Casos, [switch]$SinPrepara) {
  $e = Escenario-M61 $Nombre $Casos
  if ($SinPrepara) {
    Escribe $e.Wt ($M64Ruta + 'SinIT.java') "package com.acme.nuevo;`n`n@SpringBootTest`npublic class SinIT {`n  @Test`n  void arranca() {}`n}`n"
    Escribe $e.Wt ($M64Ruta + 'UnitTest.java') "package com.acme.nuevo;`n`npublic class UnitTest {`n  @BeforeEach`n  void inicia() {}`n}`n"
  }
  else {
    Escribe $e.Wt ($M64Ruta + 'CargaIT.java') "package com.acme.nuevo;`n`n@SpringBootTest`npublic class CargaIT {`n  @Autowired JobLauncherTestUtils utils;`n`n  @BeforeEach`n  void preparaContexto() {`n    HolderTraza.actual().put(`"contextoTraza`", new ContextoTraza());`n  }`n}`n"
    Escribe $e.Wt ($M64Ruta + 'OtraIT.java') "package com.acme.nuevo;`n`n@RunWith(SpringRunner.class)`n@SpringBatchTest`npublic class OtraIT {`n  @Before`n  public void inicia() throws Exception {`n  }`n}`n"
  }
  [void](GitEn $e.Wt @('add', 'src/test'))
  [void](GitEn $e.Wt @('commit', '-q', '-m', 'tests de ejemplo'))
  Escribe $e.Legacy 'src/test/java/com/acme/viejo/ViejoIT.java' "package com.acme.viejo;`n`n@SpringBootTest`npublic class ViejoIT {`n  @Autowired JobLauncherTestUtils utils;`n  @BeforeEach`n  void preparaViejo() {`n  }`n}`n"
  [void](GitEn $e.Legacy @('add', 'src/test'))
  [void](GitEn $e.Legacy @('commit', '-q', '-m', 'test de ejemplo'))
  return $e
}

# Un caso del prueba-local.json de antes: distinto, con los fallos que se digan ('migrado:FAILED:causa' u 'original:FAILED:causa', separados por ;).
function Caso-M64([string]$N, [string]$Fallos, [string]$Resultado = 'distinto') {
  $f = @()
  foreach ($x in @($Fallos -split ';' | Where-Object { $_ })) { $l, $est, $causa = $x -split ':', 3; $f += [ordered]@{ lado = $l; estado = $est; causa = $causa; registro = '' } }
  return [ordered]@{ job = 'cargaJob'; caso = $N; titulo = ''; resultado = $Resultado; motivo = ''; diferencias = @(); fallos = $f }
}

# Deja en el prueba-local.json de $E los casos de $Grupos: lista de (cuantos, fallos de cada caso y, si no es 'distinto', su resultado).
function Anterior-M64($E, $Grupos) {
  $o = Lee-Json $E.Json
  $casos = @()
  $n = 0
  foreach ($g in $Grupos) { $res = 'distinto'; if ($g.Count -gt 2) { $res = $g[2] }; for ($i = 0; $i -lt $g[0]; $i++) { $n++; $casos += , (Caso-M64 ('caso-' + $n.ToString('D2')) $g[1] $res) } }
  $o.casos = $casos
  [System.IO.File]::WriteAllText($E.Json, (ConvertTo-Json -InputObject $o -Depth 20))
}

$Pruebas['m64 (a) el migrado con tests de ejemplo que preparan algo (@BeforeEach, @Before): su prompt lleva el parrafo con fichero:linea y metodo de cada uno despues de la lista; el original no; la huella no cambia'] = {
  $e = Escenario-M64 'm64-a' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba $e
  Igual 'sale con 0' 0 $r.Codigo
  $lista = "${M64Ruta}CargaIT.java:8 (preparaContexto), ${M64Ruta}OtraIT.java:7 (inicia)"
  $parrafo = $M64Cabecera + $lista + '. ' + $M64Fin
  $mig = Registro-Arnes $e 'migrado' 1
  Comprueba 'el prompt del migrado lleva el parrafo entero con sus dos metodos' ($mig.Contains($parrafo)) (Cola $mig)
  Comprueba 'y el texto de la plantilla sigue despues de una linea en blanco' ($mig.Contains($parrafo + "`n`nPueden ser de otra")) (Cola $mig)
  $lineas = @($mig -split "`n")
  $iUltimo = [array]::IndexOf($lineas, ($lineas | Where-Object { $_ -like '- *OtraIT.java' } | Select-Object -First 1))
  Comprueba 'va despues de la lista de ejemplos y una linea en blanco' ($iUltimo -ge 0 -and $lineas[$iUltimo + 1] -ceq '' -and $lineas[$iUltimo + 2].StartsWith($M64Cabecera)) (Cola $mig)
  $orig = Registro-Arnes $e 'original' 1
  Comprueba 'el prompt del original, con su propio @BeforeEach en un ejemplo, no lleva el parrafo' (-not $orig.Contains('Estos tests preparan') -and $orig.Contains('ViejoIT.java')) (Cola $orig)
  $huella = (Tarea-Arnes $e 'migrado').entradas.huella
  $llamadas = @(Llamadas-Arnes $e 'migrado').Count
  [void](GitEn $e.Wt @('rm', '-q', "${M64Ruta}CargaIT.java", "${M64Ruta}OtraIT.java"))
  [void](GitEn $e.Wt @('commit', '-q', '-m', 'sin ejemplos'))
  $r = Prueba $e
  Igual 'sin los ejemplos sale con 0' 0 $r.Codigo
  Igual 'la huella del migrado es la misma que con el parrafo' $huella (Tarea-Arnes $e 'migrado').entradas.huella
  Igual 'y no se escribe otra vez (ninguna llamada nueva)' $llamadas @(Llamadas-Arnes $e 'migrado').Count
}

$Pruebas['m64 (a2) un ejemplo con seis metodos de preparacion (@BeforeAll, @BeforeClass, con otra anotacion de por medio, @Before, @BeforeEach) y un @Test: el parrafo nombra los cinco primeros, con su linea'] = {
  $e = Nuevo-Escenario 'm64-a2' ([ordered]@{ cargaJob = @('importe=10.00') })
  $aj = [ordered]@{ CopilotExe = (Join-Path $falsos 'm40-copilot.ps1'); MvnExe = (Join-Path $falsos 'm61-mvn.ps1'); SegundosPorLlamada = 60 }
  Escribe $e.Home 'ajustes.json' (ConvertTo-Json -InputObject $aj)
  Escribe $e.Wt ($M64Ruta + 'MuchosIT.java') "package com.acme.nuevo;`n`n@SpringBootTest`npublic class MuchosIT {`n  @BeforeAll`n  static void uno() {}`n  @BeforeClass`n  public static void dos() {}`n  @BeforeEach`n  @SuppressWarnings(`"unused`")`n  protected void tres() {}`n  @Before`n  public void cuatro() {}`n  @BeforeEach`n  void cinco() {}`n  @BeforeEach`n  void seis() {}`n  @Test`n  void noPrepara() {}`n}`n"
  [void](GitEn $e.Wt @('add', 'src/test'))
  [void](GitEn $e.Wt @('commit', '-q', '-m', 'tests de ejemplo'))
  $r = Prueba $e
  Igual 'sale con 0' 0 $r.Codigo
  $f = "${M64Ruta}MuchosIT.java"
  $lista = "$f`:6 (uno), $f`:8 (dos), $f`:11 (tres), $f`:13 (cuatro), $f`:15 (cinco)"
  $mig = Registro-Arnes $e 'migrado' 1
  Comprueba 'el parrafo nombra los cinco primeros, en orden' ($mig.Contains($M64Cabecera + $lista + '. ')) (Cola $mig)
  Comprueba 'ni el sexto (seis) ni el @Test (noPrepara)' (-not $mig.Contains('seis') -and -not $mig.Contains('noPrepara')) (Cola $mig)
}

$Pruebas['m64 (b) sin metodos de preparacion en los ejemplos de la copia (o con ellos solo en un test que no arranca el batch o en la referencia): EJEMPLOS sale como hoy, sin el parrafo'] = {
  $e = Escenario-M64 'm64-b1' ([ordered]@{ cargaJob = @('importe=10.00') }) -SinPrepara
  $r = Prueba $e
  Igual 'sin metodos de preparacion sale con 0' 0 $r.Codigo
  $mig = Registro-Arnes $e 'migrado' 1
  Comprueba 'el prompt del migrado lista el ejemplo' ($mig.Contains("${M64Ruta}SinIT.java")) (Cola $mig)
  Comprueba 'y no lleva el parrafo (el @BeforeEach de UnitTest, que no arranca el batch, no cuenta)' (-not $mig.Contains('Estos tests preparan') -and -not $mig.Contains('UnitTest.java')) (Cola $mig)
  Comprueba 'y la lista acaba como hoy: una linea en blanco y el texto de la plantilla' ($mig.Contains("${M64Ruta}SinIT.java`n`nPueden ser de otra")) (Cola $mig)
  $e = Nuevo-Escenario 'm64-b2' ([ordered]@{ cargaJob = @('importe=10.00') })
  $ref = Join-Path $e.Raiz 'referencia'
  Escribe $ref 'src/test/java/com/ref/RefIT.java' "package com.ref;`n`n@SpringBootTest`npublic class RefIT {`n  @BeforeEach`n  void preparaRef() {`n  }`n}`n"
  $aj = [ordered]@{ CopilotExe = (Join-Path $falsos 'm40-copilot.ps1'); MvnExe = (Join-Path $falsos 'm61-mvn.ps1'); SegundosPorLlamada = 60; Plantilla = $ref }
  Escribe $e.Home 'ajustes.json' (ConvertTo-Json -InputObject $aj)
  $r = Prueba $e
  Igual 'con un ejemplo solo en la referencia sale con 0' 0 $r.Codigo
  $mig = Registro-Arnes $e 'migrado' 1
  Comprueba 'el prompt del migrado lista el ejemplo de la referencia' ($mig.Contains('RefIT.java')) (Cola $mig)
  Comprueba 'y no lleva el parrafo (solo cuentan los ejemplos de la copia)' (-not $mig.Contains('Estos tests preparan') -and -not $mig.Contains('preparaRef')) (Cola $mig)
}

$Pruebas['m64 (c) el prueba-local.json de antes con 13 casos del migrado FAILED con una NPE (y el original bien) y otros 2 con otra causa, con -RehacerArnes: el primer intento del migrado lleva la frase y las dos lineas, la de 13 primero'] = {
  $e = Escenario-M64 'm64-c' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba $e
  Igual 'el primer lanzamiento sale con 0' 0 $r.Codigo
  $solo = 'java.lang.ArithmeticException: / by zero'
  $sin = 'el job no ha dejado estado.txt'
  Anterior-M64 $e @(@(13, "migrado:FAILED:$M64Npe"), @(2, "migrado:FAILED:$M64Otra"), @(1, "migrado:FAILED:$solo"), @(2, "migrado:sin estado.txt:$sin"))
  $r = Prueba $e @('-RehacerArnes')
  Igual 'con -RehacerArnes sale con 0' 0 $r.Codigo
  $mig = Registro-Arnes $e 'migrado' 1
  $l13 = "En 13 casos el migrado acaba FAILED y el original no: $M64Npe."
  $l2 = "En 2 casos el migrado acaba FAILED y el original no: $M64Otra."
  Comprueba 'el primer intento del migrado lleva el bloque de lo que fallo la otra vez' ($mig.Contains($M61Bloque)) (Cola $mig)
  Comprueba 'con la linea de los 13 casos de la NPE' ($mig.Contains($l13)) (Cola $mig)
  Comprueba 'y la de los 2 de la otra causa' ($mig.Contains($l2)) (Cola $mig)
  Comprueba 'la frase de encima de las lineas, una sola vez' ($mig.Contains($M64Frase + "`n") -and [regex]::Matches($mig, [regex]::Escape($M64Frase)).Count -eq 1 -and $mig.IndexOf($M64Frase) -lt $mig.IndexOf($l13)) (Cola $mig)
  Comprueba 'la de 13 va antes que la de 2' ($mig.IndexOf($l13) -lt $mig.IndexOf($l2)) (Cola $mig)
  Comprueba 'un caso solo con otra causa y dos que no dejan estado.txt no dan linea: son dos lineas' ([regex]::Matches($mig, 'En \d+ casos el migrado acaba').Count -eq 2 -and -not $mig.Contains($solo) -and -not $mig.Contains($sin)) (Cola $mig)
  Comprueba 'la tarea del migrado guarda el bloque en entradas.previo (no en la huella)' ([string](Tarea-Arnes $e 'migrado').entradas.previo -match [regex]::Escape($l13)) ''
}

$Pruebas['m64 (c2) con -RehacerOriginal (que arrastra al migrado) y ese mismo prueba-local.json: el primer intento del original no lleva ni la frase ni las lineas (son del migrado) y el del migrado si'] = {
  $e = Escenario-M64 'm64-c2' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba $e
  Igual 'el primer lanzamiento sale con 0' 0 $r.Codigo
  Anterior-M64 $e @(@(13, "migrado:FAILED:$M64Npe"), @(2, "migrado:FAILED:$M64Otra"))
  $deAntes = @(Llamadas-Arnes $e 'original').Count
  $r = Prueba $e @('-RehacerOriginal')
  Igual 'con -RehacerOriginal sale con 0' 0 $r.Codigo
  Comprueba 'el original se escribe otra vez (una llamada nueva como minimo)' (@(Llamadas-Arnes $e 'original').Count -gt $deAntes) ''
  $orig = Registro-Arnes $e 'original' 1
  Comprueba 'su primer prompt es el de ahora (lleva su ejemplo ViejoIT.java)' ($orig.Contains('ViejoIT.java')) (Cola $orig)
  Comprueba 'y no lleva ni la frase ni las lineas del migrado' (-not $orig.Contains($M64Frase) -and -not $orig.Contains('el migrado acaba')) (Cola $orig)
  $mig = Registro-Arnes $e 'migrado' 1
  Comprueba 'el del migrado, que se escribe otra vez traduciendo el nuevo, lleva la linea de los 13 casos' ($mig.Contains("En 13 casos el migrado acaba FAILED y el original no: $M64Npe.")) (Cola $mig)
}

$Pruebas['m64 (d) una causa con un solo caso no sale; si los dos lados acaban FAILED o el migrado no deja estado.txt el caso no cuenta; EXCEPCION cuenta con su estado; solo las tres causas de mas casos'] = {
  $e = Escenario-M64 'm64-d' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba $e
  Igual 'el primer lanzamiento sale con 0' 0 $r.Codigo
  $solo = 'java.lang.ArithmeticException: / by zero'
  $ambos = 'java.lang.IllegalArgumentException: los dos lados'
  $sin = 'sin estado.txt del migrado'
  $exc = 'java.lang.ClassNotFoundException: com.acme.Falta'
  $c3 = 'java.lang.RuntimeException: tercera'
  $c4 = 'java.lang.RuntimeException: cuarta'
  $noDistinto = 'java.lang.IllegalStateException: de un caso que no sale distinto'
  Anterior-M64 $e @(@(1, "migrado:FAILED:$solo"), @(2, "migrado:FAILED:$ambos;original:FAILED:$ambos"), @(2, "migrado:sin estado.txt:$sin"), @(5, "migrado:EXCEPCION:$exc"), @(3, "migrado:FAILED:$c3"), @(2, "migrado:FAILED:$c4"), @(2, "migrado:FAILED:$M64Otra"), @(4, "migrado:FAILED:$noDistinto", 'no se pudo preparar'), @(2, 'migrado:FAILED:'))
  $r = Prueba $e @('-RehacerArnes')
  Igual 'con -RehacerArnes sale con 0' 0 $r.Codigo
  $mig = Registro-Arnes $e 'migrado' 1
  Comprueba 'la causa de 5 casos sale con su estado (EXCEPCION)' ($mig.Contains("En 5 casos el migrado acaba EXCEPCION y el original no: $exc.")) (Cola $mig)
  Comprueba 'la de 3 casos tambien' ($mig.Contains("En 3 casos el migrado acaba FAILED y el original no: $c3.")) (Cola $mig)
  Comprueba 'de las de 2 casos, la primera por orden de firma (IllegalStateException va antes que RuntimeException) y nada mas: tres lineas en total' ([regex]::Matches($mig, 'En \d+ casos el migrado acaba').Count -eq 3 -and $mig.Contains("En 2 casos el migrado acaba FAILED y el original no: $M64Otra.")) (Cola $mig)
  Comprueba 'la de un solo caso no sale' (-not $mig.Contains($solo)) (Cola $mig)
  Comprueba 'la de los dos lados FAILED no sale' (-not $mig.Contains($ambos)) (Cola $mig)
  Comprueba 'la de sin estado.txt no sale' (-not $mig.Contains($sin)) (Cola $mig)
  Comprueba 'la cuarta causa (2 casos, despues de la otra por orden) no sale' (-not $mig.Contains($c4)) (Cola $mig)
  Comprueba 'la de casos que no salen distintos (no se pudo preparar) no sale' (-not $mig.Contains($noDistinto)) (Cola $mig)
  Comprueba 'ni la de casos sin causa (la linea acabaria en dos puntos y un punto)' (-not $mig.Contains('y el original no: .')) (Cola $mig)
}

$Pruebas['m64 (d2) la causa del migrado se corta en 200 letras y las causas que solo cambian en un numero o en el nombre del caso son una'] = {
  $e = Escenario-M64 'm64-d2' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba $e
  Igual 'el primer lanzamiento sale con 0' 0 $r.Codigo
  $larga = 'java.lang.IllegalStateException: ' + ('x' * 300)
  $o = Lee-Json $e.Json
  $casos = @()
  foreach ($n in 1..3) { $casos += , (Caso-M64 ('caso-0' + $n) "migrado:FAILED:no hay filas para el id 1$n en caso-0$n") }
  foreach ($n in 4..5) { $casos += , (Caso-M64 ('caso-0' + $n) "migrado:FAILED:$larga") }
  $o.casos = $casos
  [System.IO.File]::WriteAllText($e.Json, (ConvertTo-Json -InputObject $o -Depth 20))
  $r = Prueba $e @('-RehacerArnes')
  Igual 'con -RehacerArnes sale con 0' 0 $r.Codigo
  $mig = Registro-Arnes $e 'migrado' 1
  Comprueba 'las tres causas que solo cambian en el numero y el caso son una de 3 casos' ($mig.Contains('En 3 casos el migrado acaba FAILED y el original no: no hay filas para el id 1')) (Cola $mig)
  Comprueba 'la larga sale cortada a 200 letras' ($mig.Contains('En 2 casos el migrado acaba FAILED y el original no: ' + $larga.Substring(0, 200) + '.') -and -not $mig.Contains($larga.Substring(0, 201))) (Cola $mig)
}

$Pruebas['m64 (e) un lanzamiento sin -RehacerArnes con ese mismo prueba-local.json: ni llamadas ni prompt nuevo ni nada guardado'] = {
  $e = Escenario-M64 'm64-e' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba $e
  Igual 'el primer lanzamiento sale con 0' 0 $r.Codigo
  $llamadas = (Llamadas $e).Count
  $huellas = @((Tarea-Arnes $e 'original').entradas.huella, (Tarea-Arnes $e 'migrado').entradas.huella) -join ','
  Anterior-M64 $e @(@(13, "migrado:FAILED:$M64Npe"), @(2, "migrado:FAILED:$M64Otra"))
  $r = Prueba $e
  Igual 'el segundo lanzamiento sale con 0' 0 $r.Codigo
  Igual 'sin llamadas nuevas' $llamadas (Llamadas $e).Count
  Comprueba 'el prompt del migrado no lleva ni el bloque ni la frase' (-not (Registro-Arnes $e 'migrado' 1).Contains($M61Bloque) -and -not (Registro-Arnes $e 'migrado' 1).Contains($M64Frase)) ''
  Comprueba 'la tarea del migrado no guarda nada de antes' ([string](Tarea-Arnes $e 'migrado').entradas.previo -eq '') ''
  Igual 'la huella de los dos tests es la misma' $huellas (@((Tarea-Arnes $e 'original').entradas.huella, (Tarea-Arnes $e 'migrado').entradas.huella) -join ',')
}

# ===================== M68: menos ruido y puertas mas finas en la prueba en local =====================
# Escenarios con el Copilot de m40 y el Maven de m68 (tests/falsos/m68-mvn.ps1; sus banderas, en RESCATE_M68). RESCATE_M40 = 'tablas=1/CALENDARIO_02' deja esa
# tabla en la base de prueba de los dos tests desde su primera llamada (m40-copilot.ps1).

function Escenario-M68([string]$Nombre, $Casos, [hashtable]$Mas = @{}) {
  $e = Nuevo-Escenario $Nombre $Casos
  $aj = [ordered]@{ CopilotExe = (Join-Path $falsos 'm40-copilot.ps1'); MvnExe = (Join-Path $falsos 'm68-mvn.ps1'); SegundosPorLlamada = 60 }
  foreach ($k in $Mas.Keys) { $aj[$k] = $Mas[$k] }
  Escribe $e.Home 'ajustes.json' (ConvertTo-Json -InputObject $aj)
  return $e
}

# Lanza con las banderas $Banderas del Maven falso, la base de los tests $Tablas ('tablas=<n>/<T_A,T_B>' de m40-copilot.ps1) y las variables de entorno $Env (nombre -> valor).
function Prueba-M68($E, [string]$Banderas = '', [string]$Tablas = '', [string[]]$A = @(), [hashtable]$Env = @{}) {
  $env:RESCATE_M68 = $Banderas
  $env:RESCATE_M40 = $Tablas
  foreach ($k in $Env.Keys) { Set-Item -Path "env:$k" -Value ([string]$Env[$k]) }
  try { return (Prueba $E $A) }
  finally {
    $env:RESCATE_M68 = ''
    $env:RESCATE_M40 = ''
    foreach ($k in $Env.Keys) { Remove-Item -Path "env:$k" -ErrorAction SilentlyContinue }
  }
}

# El datos.sql que vio cada ejecucion de un caso en la copia $Copia (m68-sql.log), como 'job/caso|sql', en orden.
function Sql-M68($E, [string]$Copia) {
  $f = Join-Path $E.Llamadas 'm68-sql.log'
  if (-not (Test-Path -LiteralPath $f)) { return @() }
  return @([System.IO.File]::ReadAllLines($f) | Where-Object { $_.StartsWith($Copia + '|') } | ForEach-Object { $_.Substring($Copia.Length + 1) })
}

$SqlM68 = 'create table CALENDARIO_02 (ID int)'

$Pruebas['m68 (a1) un datos.sql que crea una tabla que el test ya crea (CALENDARIO_02): el caso corre en el original y en el migrado sin ya existe, y lo guardado en casos no cambia'] = {
  $e = Escenario-M68 'm68-a1' ([ordered]@{ cargaJob = @("importe=10.00 | SQL $SqlM68") })
  $r = Prueba-M68 $e '' 'tablas=1/CALENDARIO_02'
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'el caso sale igual' 'igual' ((Resultados $e) -join ',')
  Comprueba 'el original deja estado.txt y no deja error.txt' ((Test-Path -LiteralPath (Get-Ruta $e.Local 'salidas/original/cargaJob/caso-01/estado.txt')) -and -not (Test-Path -LiteralPath (Get-Ruta $e.Local 'salidas/original/cargaJob/caso-01/error.txt'))) ''
  $con = 'cargaJob/caso-01|create table IF NOT EXISTS CALENDARIO_02 (ID int)'
  Igual 'el original vio IF NOT EXISTS en sus tres ejecuciones (la que prepara el caso y las dos de comparar)' 3 @(Sql-M68 $e $e.CopiaOrig | Where-Object { $_ -ceq $con }).Count
  Igual 'y el migrado, en la suya' 1 @(Sql-M68 $e $e.CopiaMig | Where-Object { $_ -ceq $con }).Count
  Igual 'ninguna ejecucion vio el datos.sql sin cambiar' 0 @(@(Sql-M68 $e $e.CopiaOrig) + @(Sql-M68 $e $e.CopiaMig) | Where-Object { $_ -ceq "cargaJob/caso-01|$SqlM68" }).Count
  $rel = 'src/test/resources/prueba-local/cargaJob/caso-01/datos.sql'
  Igual 'lo guardado en casos no cambia' $SqlM68 (Lee $e.Local 'casos/cargaJob/caso-01/datos.sql').Trim()
  Igual 'ni lo que queda en la copia del original' $SqlM68 (Lee $e.CopiaOrig $rel).Trim()
  Igual 'ni en la copia del migrado' $SqlM68 (Lee $e.CopiaMig $rel).Trim()
}

$Pruebas['m68 (a2) un CREATE TABLE que ya lleva IF NOT EXISTS no se toca (en mayusculas, en minusculas, con espacios de mas), el que no lo lleva si aunque vaya despues en la misma linea, y lo demas del fichero queda byte a byte'] = {
  $enie = "insert into T_C values ('" + [char]0xF1 + 'and' + [char]0xFA + "')"
  $sql = "create table IF NOT EXISTS T_A (ID int); CREATE   TABLE  if  not  exists  T_B (ID int); Create Table T_C (ID int); $enie"
  $e = Escenario-M68 'm68-a2' ([ordered]@{ cargaJob = @("importe=10.00 | SQL $sql") })
  $r = Prueba-M68 $e
  Igual 'sale con 0' 0 $r.Codigo
  $visto = @(Sql-M68 $e $e.CopiaMig)
  Igual 'el migrado vio solo el tercero cambiado, y la enie y la u con tilde enteras' "cargaJob/caso-01|create table IF NOT EXISTS T_A (ID int); CREATE   TABLE  if  not  exists  T_B (ID int); Create Table IF NOT EXISTS T_C (ID int); $enie" ($visto -join '|')
  Igual 'ninguno queda doble' 0 @($visto | Where-Object { $_ -match '(?i)IF NOT EXISTS\s+IF NOT EXISTS' }).Count
  Igual 'lo guardado en casos no cambia' $sql ((Lee $e.Local 'casos/cargaJob/caso-01/datos.sql').Trim())
}

$Pruebas['m68 (a3) un caso hecho de antes cuyo original guardo ya existe, already exists o 42101 se ejecuta otra vez, sin -Rehacer y sin llamar a Copilot; los demas, no'] = {
  $e = Escenario-M68 'm68-a3' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00', 'importe=30.00', 'importe=40.00', 'importe=50.00') })
  $r = Prueba-M68 $e
  Igual 'el primer lanzamiento sale con 0' 0 $r.Codigo
  $llamadas = (Llamadas $e).Count
  $antes = @(1..5 | ForEach-Object { Orig-Mvn $e 'cargaJob' ('caso-0' + $_) }) -join ','
  Igual 'cada caso se ejecuto 3 veces en el original (prepararlo y dos de comparar)' '3,3,3,3,3' $antes
  $dicen = @{
    1 = 'org.h2.jdbc.JdbcSQLSyntaxErrorException: Tabla "CALENDARIO_02" ya existe; Sentencia SQL: CREATE TABLE CALENDARIO_02 (ID INT) [42101-200]'
    2 = 'org.h2.jdbc.JdbcSQLSyntaxErrorException: Table "CALENDARIO_02" already exists; SQL statement: CREATE TABLE CALENDARIO_02 (ID INT)'
    3 = 'org.h2.jdbc.JdbcSQLSyntaxErrorException: [42101-200]'
    5 = 'org.h2.jdbc.JdbcSQLSyntaxErrorException: Tabla "CALENDARIO_02" ya existe'
  }
  foreach ($n in $dicen.Keys) { Escribe $e.Local "salidas/original/cargaJob/caso-0$n/error.txt" ($dicen[$n] + "`n") }
  Remove-Item -LiteralPath (Get-Ruta $e.Local 'salidas/original/cargaJob/caso-05/estado.txt')   # el 5 tiene la forma de siempre: sin estado.txt, solo el error
  $r = Prueba-M68 $e
  Igual 'el segundo lanzamiento sale con 0' 0 $r.Codigo
  Igual 'sin llamadas nuevas a Copilot' $llamadas (Llamadas $e).Count
  $despues = @(1..5 | ForEach-Object { Orig-Mvn $e 'cargaJob' ('caso-0' + $_) }) -join ','
  Igual 'los cuatro con el error se ejecutan otra vez (original y original-2) y el otro, no' '5,5,5,3,5' $despues
  Comprueba 'la consola dice cuantos' ($r.Salida -match 'Se ejecuta otra vez el original de 4 caso\(s\)') (Cola $r.Salida)
  Comprueba 'el error.txt guardado de antes ya no esta' (-not (Test-Path -LiteralPath (Get-Ruta $e.Local 'salidas/original/cargaJob/caso-01/error.txt'))) ''
  Igual 'los cinco salen iguales' 'igual,igual,igual,igual,igual' ((Resultados $e) -join ',')
  $r = Prueba-M68 $e
  Comprueba 'un tercer lanzamiento ya no ejecuta ninguno otra vez' ($r.Salida -match 'Original: se reutilizan las salidas de 5 caso\(s\) y se ejecutan 0\.' -and $r.Salida -notmatch 'Se ejecuta otra vez el original') (Cola $r.Salida)
}

$Pruebas['m68 (b1) un .log que solo deja el migrado (el log por job del framework nuevo): los casos salen iguales, y el log queda guardado'] = {
  $e = Escenario-M68 'm68-b1' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba-M68 $e 'logs'
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'los dos casos salen iguales' 'igual,igual' ((Resultados $e) -join ',')
  Comprueba 'los dos logs del migrado estan en salidas' ((Test-Path -LiteralPath (Get-Ruta $e.Local 'salidas/migrado/cargaJob/caso-01/ficheros/logs/job-cargaJob-a1b2c3.log')) -and (Test-Path -LiteralPath (Get-Ruta $e.Local 'salidas/migrado/cargaJob/caso-01/ficheros/logs/jobs/cargaJob/ejecucion.log'))) ''
  Comprueba 'y el original no los tiene' (-not (Test-Path -LiteralPath (Get-Ruta $e.Local 'salidas/original/cargaJob/caso-01/ficheros/logs'))) ''
}

$Pruebas['m68 (b2) un .txt que solo deja el migrado sigue saliendo distinto, aunque deje tambien sus logs: la unica diferencia es el .txt'] = {
  $e = Escenario-M68 'm68-b2' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M68 $e 'logs;txt'
  Igual 'sale con 2' 2 $r.Codigo
  Igual 'el caso sale distinto' 'distinto' ((Resultados $e) -join ',')
  Igual 'con una sola diferencia: el .txt' 'ficheros/extra.txt' (@((Caso $e 'cargaJob' 'caso-01').diferencias | ForEach-Object { $_.fichero }) -join ',')
}

$Pruebas['m68 (b3) con CompararIgnorar vacio (en ajustes.json), el .log vuelve a contar: el caso sale distinto con los dos logs'] = {
  $e = Escenario-M68 'm68-b3' ([ordered]@{ cargaJob = @('importe=10.00') }) @{ CompararIgnorar = @() }
  $r = Prueba-M68 $e 'logs'
  Igual 'sale con 2' 2 $r.Codigo
  Igual 'el caso sale distinto' 'distinto' ((Resultados $e) -join ',')
  Igual 'con los dos logs entre las diferencias' 'ficheros/logs/job-cargaJob-a1b2c3.log,ficheros/logs/jobs/cargaJob/ejecucion.log' ((@((Caso $e 'cargaJob' 'caso-01').diferencias | ForEach-Object { $_.fichero }) | Sort-Object { $_ }) -join ',')
}

$Pruebas['m68 (b4) un .log que no cabe en salidas ni con nombre corto no cuenta como fichero sin guardar (la consola si lo dice): el caso sale igual y el siguiente lanzamiento reutiliza el original'] = {
  $e = Escenario-M68 'm68-b4' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M68 $e 'sin-sitio'
  Comprueba 'la consola dice que el log no se pudo guardar' ($r.Salida -match 'dato\.log: no se ha podido guardar') (Cola $r.Salida)
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'el caso sale igual' 'igual' ((Resultados $e) -join ',')
  Igual 'sin ninguna diferencia' 0 @((Caso $e 'cargaJob' 'caso-01').diferencias).Count
  $r = Prueba-M68 $e
  Comprueba 'el siguiente lanzamiento reutiliza el original' ($r.Salida -match 'Original: se reutilizan las salidas de 1 caso\(s\) y se ejecutan 0\.') (Cola $r.Salida)
}

$Pruebas['m68 (b5) los patrones de CompararIgnorar casan con el nombre del fichero, no con su ruta: con job-*.log, el log por job que solo deja el migrado no cuenta y otro .log (ejecucion.log) si'] = {
  $e = Escenario-M68 'm68-b5' ([ordered]@{ cargaJob = @('importe=10.00') }) @{ CompararIgnorar = @('job-*.log') }
  $r = Prueba-M68 $e 'logs'
  Igual 'sale con 2' 2 $r.Codigo
  Igual 'el caso sale distinto' 'distinto' ((Resultados $e) -join ',')
  Igual 'con una sola diferencia: el otro .log' 'ficheros/logs/jobs/cargaJob/ejecucion.log' (@((Caso $e 'cargaJob' 'caso-01').diferencias | ForEach-Object { $_.fichero }) -join ',')
}

# --- (c) la base del test del migrado tiene las tablas de la base del test del original ---
# 'tablas=<n>/<T_A,T_B>:<id>' de m40-copilot.ps1 pone esa base en el test del arnes que casa desde su llamada n; el caso vacio de cada lado deja un tablas\<T>.csv por tabla.

$MotivoTablas68 = 'La base de tu test no tiene estas tablas que si tiene la del test del original: CALENDARIO_02. Crealas con las mismas columnas que en el test del original.'

$Pruebas['m68 (c1) el caso vacio del original deja CALENDARIO_02 y el del migrado no: el primer intento del migrado se rechaza con el motivo y la tabla, y el segundo, que la crea, se acepta'] = {
  $e = Escenario-M68 'm68-c1' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M68 $e '' 'tablas=1/CALENDARIO_02:arnes-original;tablas=2/CALENDARIO_02:arnes-migrado'
  Igual 'sale con 0' 0 $r.Codigo
  Comprueba 'la consola rechaza el primer intento del migrado con el motivo' ($r.Salida.Contains("Arnes del migrado rechazado: $MotivoTablas68")) (Cola $r.Salida)
  Igual 'hay dos llamadas del migrado' 2 (Llamadas-Arnes $e 'migrado').Count
  Comprueba 'el reintento recibe el motivo entero' ((Registro-Arnes $e 'migrado' 2).Contains($MotivoTablas68)) (Cola (Registro-Arnes $e 'migrado' 2))
  Igual 'la tarea del migrado queda hecha, con dos intentos' 'hecha:2' "$((Tarea-Arnes $e 'migrado').estado):$((Tarea-Arnes $e 'migrado').intentos)"
  Comprueba 'el segundo se acepta sin aviso de tablas' ($r.Salida -match 'Arnes del migrado: bien\.' -and $r.Salida -notmatch 'sigue sin estas tablas') (Cola $r.Salida)
  Igual 'el caso sale igual' 'igual' ((Resultados $e) -join ',')
}

$Pruebas['m68 (c2) en el ultimo intento, y con un test guardado, el migrado sin esa tabla se acepta con un aviso y los casos se ejecutan'] = {
  $e = Escenario-M68 'm68-c2' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M68 $e '' 'tablas=1/CALENDARIO_02:arnes-original;tablas=9/CALENDARIO_02:arnes-migrado'
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'el primer intento se rechaza' 1 @([regex]::Matches($r.Salida, [regex]::Escape("Arnes del migrado rechazado: $MotivoTablas68"))).Count
  Comprueba 'el ultimo se acepta' ($r.Salida -match 'Arnes del migrado: bien\.') (Cola $r.Salida)
  $aviso = 'La base de tu test sigue sin estas tablas que si tiene la del test del original: CALENDARIO_02.'
  Comprueba 'con el aviso' ($r.Salida.Contains($aviso)) (Cola $r.Salida)
  Igual 'la tarea queda hecha, con dos intentos' 'hecha:2' "$((Tarea-Arnes $e 'migrado').estado):$((Tarea-Arnes $e 'migrado').intentos)"
  Igual 'el caso sale igual' 'igual' ((Resultados $e) -join ',')
  $n = @(Llamadas $e).Count
  Cambia-Huella $e 'migrado'
  $r = Prueba-M68 $e '' 'tablas=9/CALENDARIO_02:arnes-migrado'
  Igual 'con el test guardado sale con 0' 0 $r.Codigo
  Igual 'sin llamadas a Copilot' $n @(Llamadas $e).Count
  Comprueba 'dice que el test de otro lanzamiento sigue valiendo' ($r.Salida -match 'Arnes del migrado: bien \(el test de otro lanzamiento sigue valiendo\)') (Cola $r.Salida)
  Comprueba 'y avisa de la tabla' ($r.Salida.Contains($aviso)) (Cola $r.Salida)
}

$Pruebas['m68 (c3) las tablas BATCH_ y TASK_ que deja el caso vacio del original y no el del migrado no cuentan: el migrado se acepta a la primera, sin aviso'] = {
  $e = Escenario-M68 'm68-c3' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M68 $e '' 'tablas=1/CALENDARIO_02,BATCH_JOB_INSTANCE,task_execution:arnes-original;tablas=1/CALENDARIO_02:arnes-migrado'
  Igual 'sale con 0' 0 $r.Codigo
  Comprueba 'el caso vacio del original deja la de Spring Batch' (Test-Path -LiteralPath (Get-Ruta $e.Local 'salidas/vacio/cargaJob/tablas/BATCH_JOB_INSTANCE.csv')) ''
  Comprueba 'y una TASK_ escrita en minusculas, que tampoco cuenta' (Test-Path -LiteralPath (Get-Ruta $e.Local 'salidas/vacio/cargaJob/tablas/task_execution.csv')) ''
  Igual 'la tarea del migrado queda hecha a la primera' 'hecha:1' "$((Tarea-Arnes $e 'migrado').estado):$((Tarea-Arnes $e 'migrado').intentos)"
  Comprueba 'sin rechazo ni aviso de tablas' ($r.Salida -notmatch 'tablas que si tiene la del test del original') (Cola $r.Salida)
}

$Pruebas['m68 (c4) el primer intento del migrado ya lleva la lista de tablas de la base del test del original en su prompt, el del original no, y la huella no cambia'] = {
  $e = Escenario-M68 'm68-c4' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M68 $e '' 'tablas=1/T_B,CALENDARIO_02,BATCH_JOB_INSTANCE:arnes-original;tablas=1/T_B,CALENDARIO_02:arnes-migrado'
  Igual 'sale con 0' 0 $r.Codigo
  $lista = 'La base del test del original tiene estas tablas: CALENDARIO_02, T_B.'
  $p = Registro-Arnes $e 'migrado' 1
  Comprueba 'el prompt del primer intento del migrado lleva la lista, sin las de Spring Batch' ($p.Contains($lista)) (Cola $p)
  Comprueba 'el del original no' (-not (Registro-Arnes $e 'original' 1).Contains('La base del test del original tiene estas tablas')) ''
  Igual 'la tarea del migrado queda hecha a la primera' 'hecha:1' "$((Tarea-Arnes $e 'migrado').estado):$((Tarea-Arnes $e 'migrado').intentos)"
  $n = @(Llamadas $e).Count
  $r = Prueba-M68 $e '' 'tablas=1/T_B,CALENDARIO_02,BATCH_JOB_INSTANCE:arnes-original;tablas=1/T_B,CALENDARIO_02:arnes-migrado'
  Igual 'el segundo lanzamiento no escribe ningun test otra vez' $n @(Llamadas $e).Count
}

$Pruebas['m68 (c5) los nombres de las tablas se comparan sin distinguir mayusculas, como Get-TablasFaltan: calendario_02 en el migrado es CALENDARIO_02 del original'] = {
  $e = Escenario-M68 'm68-c5' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M68 $e '' 'tablas=1/CALENDARIO_02:arnes-original;tablas=1/calendario_02:arnes-migrado'
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'la tarea del migrado queda hecha a la primera' 'hecha:1' "$((Tarea-Arnes $e 'migrado').estado):$((Tarea-Arnes $e 'migrado').intentos)"
  Comprueba 'sin rechazo ni aviso de tablas' ($r.Salida -notmatch 'tablas que si tiene la del test del original') (Cola $r.Salida)
}

# --- (d) un job que no arranca con el test aceptado no se ejecuta en todos sus casos ---
# Estos escenarios usan el Maven de m48 (excepcion-mig: el migrado acaba EXCEPCION en el caso vacio y en los casos; el original, no) o el de m68-excepcion.ps1 (lo mismo,
# con otra clase de excepcion en los casos). Con Intentos = 2 (por defecto), el primer test se rechaza por el caso vacio y el segundo se acepta con el aviso.

function Escenario-M68d([string]$Nombre, [switch]$OtraClase) {
  $mas = @{}
  if ($OtraClase) { $mas.MvnExe = (Join-Path $falsos 'm68-excepcion.ps1') }
  return (Escenario-M48 $Nombre ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00', 'importe=30.00', 'importe=40.00', 'importe=50.00') }) $mas)
}

$Pruebas['m68 (d1) el test del migrado se acepta en el ultimo intento con el aviso de que no arranca: se ejecuta un caso, los otros 4 salen sin probar con su motivo y la linea final dice que puede ser el codigo'] = {
  $e = Escenario-M68d 'm68-d1'
  $r = Prueba-M48 $e 'excepcion-mig:^cargaJob/'
  Igual 'sale con 2' 2 $r.Codigo
  Igual 'el primer intento del test se rechaza' 1 @([regex]::Matches($r.Salida, 'Arnes del migrado rechazado: Con un caso vacio, el original arranca el job cargaJob')).Count
  Comprueba 'el ultimo se acepta' ($r.Salida -match 'Arnes del migrado: bien\.') (Cola $r.Salida)
  Igual 'el migrado ejecuta un solo caso' 1 (Casos-Mvn $e $e.CopiaMig).Count
  Igual 'el primero sale distinto y los otros cuatro, sin probar en local' 'distinto,sin probar en local,sin probar en local,sin probar en local,sin probar en local' ((Resultados $e) -join ',')
  Igual 'con su motivo' 'el migrado no arranca el job con este test' (Caso $e 'cargaJob' 'caso-05').motivo
  Comprueba 'la consola lo dice por caso' ($r.Salida -match 'sin probar en local: cargaJob/caso-05 \(Caso 5 de cargaJob\)\. el migrado no arranca el job con este test') (Cola $r.Salida)
  $linea = 'El migrado no arranca el job cargaJob (BeanCreationException: java.lang.IllegalStateException: sin correo). El test ya se escribio 2 veces con este error: puede ser el codigo del migrado. Pregunta a Copilot, en el repo del migrado, si el job arrancaria igual fuera del test.'
  Igual 'una sola linea final, la nueva' 1 @([regex]::Matches($r.Salida, 'El migrado no arranca el job cargaJob \(')).Count
  Comprueba 'y la consola dice, al ejecutar, que no lanza los demas casos' ($r.Salida.Contains('El migrado no arranca el job cargaJob con este test (BeanCreationException): no ejecuto sus demas casos.')) (Cola $r.Salida)
  Comprueba 'con el detalle, las veces y el consejo' ($r.Salida.Contains($linea)) (Cola $r.Salida)
  Comprueba 'sin el consejo de -RehacerArnes' ($r.Salida -notmatch 'relanza con -RehacerArnes') (Cola $r.Salida)
}

$Pruebas['m68 (d2) sin ese rechazo (un test guardado de otro lanzamiento, que se usa con el aviso) se ejecutan los 5 casos y sale la linea de siempre, con -RehacerArnes'] = {
  $e = Escenario-M68d 'm68-d2'
  $r = Prueba-M48 $e ''
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  $antes = (Casos-Mvn $e $e.CopiaMig).Count
  Cambia-Huella $e 'migrado'
  $r = Prueba-M48 $e 'excepcion-mig:^cargaJob/'
  Igual 'sale con 2' 2 $r.Codigo
  Comprueba 'el test guardado se usa, con el aviso del caso vacio' ($r.Salida -match 'Arnes del migrado: bien \(el test de otro lanzamiento sigue valiendo\)' -and $r.Salida -match 'Con un caso vacio, el original arranca el job cargaJob \(estado=COMPLETED\) y con tu test el migrado no: BeanCreationException \(java\.lang\.IllegalStateException: sin correo\)\.') (Cola $r.Salida)
  Igual 'el migrado ejecuta los 5 casos' 5 ((Casos-Mvn $e $e.CopiaMig).Count - $antes)
  Igual 'los cinco salen distintos' 'distinto,distinto,distinto,distinto,distinto' ((Resultados $e) -join ',')
  Comprueba 'la linea de siempre' ($r.Salida.Contains('El migrado no arranca el job cargaJob en ningun caso (BeanCreationException: java.lang.IllegalStateException: sin correo). Casi siempre es el test del migrado, no el codigo: relanza con -RehacerArnes.')) (Cola $r.Salida)
  Comprueba 'y ni rastro de la nueva' ($r.Salida -notmatch 'puede ser el codigo del migrado') (Cola $r.Salida)
}

$Pruebas['m68 (d3) si el primer caso acaba EXCEPCION con otra clase que la del caso vacio, no se salta ninguno: se ejecutan los 5 casos'] = {
  $e = Escenario-M68d 'm68-d3' -OtraClase
  $env:RESCATE_M68 = 'otra-clase'
  try { $r = Prueba-M48 $e 'excepcion-mig:^cargaJob/' }
  finally { $env:RESCATE_M68 = '' }
  Igual 'sale con 2' 2 $r.Codigo
  Comprueba 'el test se acepta con el aviso' ($r.Salida -match 'Arnes del migrado: bien\.') (Cola $r.Salida)
  Igual 'el migrado ejecuta los 5 casos' 5 (Casos-Mvn $e $e.CopiaMig).Count
  Igual 'ninguno sin probar' 0 @(Resultados $e | Where-Object { $_ -eq 'sin probar en local' }).Count
}

$Pruebas['m68 (d4) un test que se acepta sin haberse rechazado por eso (con Intentos = 1 el primer intento es el ultimo) no recorta nada: se ejecutan los 5 casos y sale la linea de siempre'] = {
  $e = Escenario-M48 'm68-d4' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00', 'importe=30.00', 'importe=40.00', 'importe=50.00') }) @{ Intentos = 1 }
  $r = Prueba-M48 $e 'excepcion-mig:^cargaJob/'
  Igual 'sale con 2' 2 $r.Codigo
  Comprueba 'el test se acepta a la primera, con el aviso' ($r.Salida -match 'Arnes del migrado: bien\.' -and $r.Salida -match 'Con un caso vacio, el original arranca el job cargaJob') (Cola $r.Salida)
  Igual 'el migrado ejecuta los 5 casos' 5 (Casos-Mvn $e $e.CopiaMig).Count
  Igual 'los cinco salen distintos' 'distinto,distinto,distinto,distinto,distinto' ((Resultados $e) -join ',')
  Comprueba 'la linea de siempre, sin la nueva' ($r.Salida -match 'en ningun caso \(BeanCreationException' -and $r.Salida -notmatch 'puede ser el codigo del migrado') (Cola $r.Salida)
}

$Pruebas['m68 (d5) si el primer caso arranca, los demas se ejecutan aunque alguno acabe EXCEPCION con la misma clase: solo se mira el primero'] = {
  $e = Escenario-M68d 'm68-d5'
  $r = Prueba-M48 $e 'vacio-excepcion-mig:/vacio;excepcion-mig:^cargaJob/caso-0[2-5]' @() '' @{ M48_VACIOS = 9 }
  Igual 'sale con 2' 2 $r.Codigo
  Comprueba 'el test se acepta con el aviso del caso vacio' ($r.Salida -match 'Arnes del migrado: bien\.' -and $r.Salida -match 'Con un caso vacio, el original arranca el job cargaJob') (Cola $r.Salida)
  Igual 'el migrado ejecuta los 5 casos' 5 (Casos-Mvn $e $e.CopiaMig).Count
  Igual 'el primero sale igual y los otros cuatro, distintos: ninguno sin probar' 'igual,distinto,distinto,distinto,distinto' ((Resultados $e) -join ',')
}

$Pruebas['m68 (d6) un test guardado de otro lanzamiento, cuya tarea quedo cortada tras un intento rechazado por eso (el motivo lo dice), se usa con el aviso y no recorta nada: se ejecutan los 5 casos y sale la linea de siempre'] = {
  $e = Escenario-M68d 'm68-d6'
  $r = Prueba-M48 $e ''
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  $antes = (Casos-Mvn $e $e.CopiaMig).Count
  $f = Get-Ruta $e.Local 'tareas/arnes-migrado.json'
  $t = Lee-Json $f
  $t.estado = 'pendiente'; $t.intentos = 1
  $t.motivo = 'Con un caso vacio, el original arranca el job cargaJob (estado=COMPLETED) y con tu test el migrado no: BeanCreationException. Revisa lo que simula el test y las propiedades que le pasa.'
  [System.IO.File]::WriteAllText($f, (ConvertTo-Json -InputObject $t -Depth 8))
  $r = Prueba-M48 $e 'excepcion-mig:^cargaJob/'
  Igual 'sale con 2' 2 $r.Codigo
  Comprueba 'el test guardado se usa, con el aviso' ($r.Salida -match 'Arnes del migrado: bien \(el test de otro lanzamiento sigue valiendo\)' -and $r.Salida -match 'Con un caso vacio, el original arranca el job cargaJob') (Cola $r.Salida)
  Igual 'el migrado ejecuta los 5 casos' 5 ((Casos-Mvn $e $e.CopiaMig).Count - $antes)
  Comprueba 'la linea de siempre, sin la nueva' ($r.Salida -match 'en ningun caso \(BeanCreationException' -and $r.Salida -notmatch 'puede ser el codigo del migrado') (Cola $r.Salida)
}

# ===================== M69: un test que se escribe otra vez no puede quedar peor que el de antes =====================
# Escenarios con el Copilot de m69 (tests/falsos/m69-copilot.ps1) y el Maven de m69 (m69-mvn.ps1), que hacen lo de m40 y, con RESCATE_M69 (guiones separados por ';'
# '<regex sobre el id de la tarea>@<n>@<marca>~<marca>'), dejan en el test del arnes que casa, en su llamada n (contando las de todos los lanzamientos), una linea
# '// <marca>' por marca: M69_VERSION=<x> (solo hace distinto el test), M69_VACIO=<estado>[:<regex sobre el job>] (el estado del caso vacio: COMPLETED, FAILED,
# EXCEPCION...), M69_CAUSA=<texto> (la causa que dice Maven), M69_TABLAS=T_A:ID|NOMBRE,T_B:ID (las tablas, con sus columnas, que deja el caso vacio).

function Escenario-M69([string]$Nombre, $Casos, [hashtable]$Mas = @{}) {
  $e = Nuevo-Escenario $Nombre $Casos
  $aj = [ordered]@{ CopilotExe = (Join-Path $falsos 'm69-copilot.ps1'); MvnExe = (Join-Path $falsos 'm69-mvn.ps1'); SegundosPorLlamada = 60 }
  foreach ($k in $Mas.Keys) { $aj[$k] = $Mas[$k] }
  Escribe $e.Home 'ajustes.json' (ConvertTo-Json -InputObject $aj)
  return $e
}

# Lanza con los guiones $Guiones de m69-copilot.ps1 (RESCATE_M69) y la base de los tests $Tablas ('tablas=<n>/<T_A,T_B>:<id>' de m40-copilot.ps1).
function Prueba-M69($E, [string]$Guiones = '', [string[]]$A = @(), [string]$Tablas = '', [string]$Guion = '') {
  $env:RESCATE_M69 = $Guiones
  $env:RESCATE_M40 = $Tablas
  try { return (Prueba $E $A $Guion) }
  finally { $env:RESCATE_M69 = ''; $env:RESCATE_M40 = '' }
}

# El test que dejo guardado, en arnes-anterior, el arnes del $Repo ('original' o 'migrado'), o '' si no hay.
function Test-Anterior($E, [string]$Repo) {
  $paquete = 'viejo'
  if ($Repo -eq 'migrado') { $paquete = 'nuevo' }
  $f = Get-Ruta $E.Local "arnes-anterior/$Repo/src/test/java/com/acme/$paquete/PruebaLocalTest.java"
  if (-not (Test-Path -LiteralPath $f)) { return '' }
  return [System.IO.File]::ReadAllText($f)
}

# Los ficheros de una carpeta de prueba-local, con su contenido, para comparar dos carpetas: 'ruta relativa=contenido' en orden y separados por '|'.
function Foto-Carpeta($E, [string]$Rel) {
  $d = Get-Ruta $E.Local $Rel
  if (-not (Test-Path -LiteralPath $d)) { return '(no existe)' }
  $base = (Resolve-Path -LiteralPath $d).Path
  return ((@(Get-ChildItem -LiteralPath $d -Recurse -File | ForEach-Object { $_.FullName.Substring($base.Length).Replace('\', '/') + '=' + ([System.IO.File]::ReadAllText($_.FullName) -replace "\s+", ' ') }) | Sort-Object { $_ }) -join '|')
}

$V2 = 'arnes-original@2@M69_VERSION=v2;arnes-migrado@2@M69_VERSION=v2'

$Pruebas['m69 (a1) con -RehacerOriginal, el test del original y el del migrado de antes acaban en arnes-anterior y salidas/vacio en salidas/vacio-anterior; sin -Rehacer..., nada se mueve'] = {
  $e = Escenario-M69 'm69-a1' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M69 $e $V2
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  $o1 = Test-Guardado $e 'original'; $m1 = Test-Guardado $e 'migrado'
  $v1 = Foto-Carpeta $e 'salidas/vacio'
  Comprueba 'el caso vacio guardado lleva algo' ($v1 -match 'cargaJob/estado.txt=estado=COMPLETED') $v1
  Comprueba 'aun no hay arnes-anterior ni salidas/vacio-anterior' (-not (Test-Path -LiteralPath (Get-Ruta $e.Local 'arnes-anterior')) -and -not (Test-Path -LiteralPath (Get-Ruta $e.Local 'salidas/vacio-anterior'))) ''
  $r = Prueba-M69 $e $V2
  Igual 'sin -Rehacer, sale con 0' 0 $r.Codigo
  Comprueba 'sin -Rehacer no se mueve nada: ni arnes-anterior ni salidas/vacio-anterior' (-not (Test-Path -LiteralPath (Get-Ruta $e.Local 'arnes-anterior')) -and -not (Test-Path -LiteralPath (Get-Ruta $e.Local 'salidas/vacio-anterior'))) ''
  Igual 'y los tests guardados son los mismos' "$o1|$m1" ((Test-Guardado $e 'original') + '|' + (Test-Guardado $e 'migrado'))
  $r = Prueba-M69 $e $V2 @('-RehacerOriginal')
  Igual 'con -RehacerOriginal, sale con 0' 0 $r.Codigo
  Igual 'arnes-anterior/original es el test de antes' $o1 (Test-Anterior $e 'original')
  Igual 'arnes-anterior/migrado es el de antes del migrado (se escribe otra vez por el original)' $m1 (Test-Anterior $e 'migrado')
  Comprueba 'el del original guardado ahora es el nuevo (con su marca)' ((Test-Guardado $e 'original').Contains('M69_VERSION=v2') -and (Test-Guardado $e 'original') -ne $o1) ''
  Comprueba 'y el del migrado' ((Test-Guardado $e 'migrado').Contains('M69_VERSION=v2') -and (Test-Guardado $e 'migrado') -ne $m1) ''
  Igual 'salidas/vacio-anterior es el caso vacio de antes, entero' $v1 (Foto-Carpeta $e 'salidas/vacio-anterior')
}

$Pruebas['m69 (a2) con -RehacerArnes solo el del migrado va a arnes-anterior: el del original y salidas/vacio no se tocan'] = {
  $e = Escenario-M69 'm69-a2' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M69 $e $V2
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  $o1 = Test-Guardado $e 'original'; $m1 = Test-Guardado $e 'migrado'
  $v1 = Foto-Carpeta $e 'salidas/vacio'
  $r = Prueba-M69 $e $V2 @('-RehacerArnes')
  Igual 'con -RehacerArnes, sale con 0' 0 $r.Codigo
  Igual 'arnes-anterior/migrado es el de antes' $m1 (Test-Anterior $e 'migrado')
  Comprueba 'el del migrado guardado es el nuevo' ((Test-Guardado $e 'migrado').Contains('M69_VERSION=v2')) ''
  Igual 'arnes-anterior/original no existe' '' (Test-Anterior $e 'original')
  Comprueba 'ni salidas/vacio-anterior' (-not (Test-Path -LiteralPath (Get-Ruta $e.Local 'salidas/vacio-anterior'))) ''
  Igual 'el del original guardado no cambia' $o1 (Test-Guardado $e 'original')
  Igual 'ni salidas/vacio' $v1 (Foto-Carpeta $e 'salidas/vacio')
}

$Pruebas['m69 (a3) un test guardado con la plantilla de otro lanzamiento (se escribe otra vez sin que nadie lo pida) tambien pasa a arnes-anterior; un tercer -RehacerOriginal pisa el de antes'] = {
  $e = Escenario-M69 'm69-a3' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M69 $e 'arnes-original@2@M69_VERSION=v2;arnes-migrado@2@M69_VERSION=v2;arnes-original@3@M69_VERSION=v3;arnes-migrado@3@M69_VERSION=v3'
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  $o1 = Test-Guardado $e 'original'
  Deja-Tarea-M37 $e 'original' $null 'aaaaaaaa'
  Deja-Tarea-M37 $e 'migrado' $null 'bbbbbbbb'
  $r = Prueba-M69 $e 'arnes-original@2@M69_VERSION=v2;arnes-migrado@2@M69_VERSION=v2;arnes-original@3@M69_VERSION=v3;arnes-migrado@3@M69_VERSION=v3'
  Igual 'con la plantilla vieja, sale con 0' 0 $r.Codigo
  Comprueba 'dice que escribe otra vez los dos' ($r.Salida.Contains($AvisoM37b)) (Cola $r.Salida)
  Igual 'arnes-anterior/original es el de la primera vez' $o1 (Test-Anterior $e 'original')
  $o2 = Test-Guardado $e 'original'
  Comprueba 'y el guardado es el nuevo' ($o2.Contains('M69_VERSION=v2')) ''
  $r = Prueba-M69 $e 'arnes-original@2@M69_VERSION=v2;arnes-migrado@2@M69_VERSION=v2;arnes-original@3@M69_VERSION=v3;arnes-migrado@3@M69_VERSION=v3' @('-RehacerOriginal')
  Igual 'con -RehacerOriginal, sale con 0' 0 $r.Codigo
  Igual 'arnes-anterior/original es ahora el de la segunda vez: pisa el de antes' $o2 (Test-Anterior $e 'original')
  Comprueba 'y el guardado es el de la tercera' ((Test-Guardado $e 'original').Contains('M69_VERSION=v3')) ''
}

# --- (b) el test nuevo del original no puede quedar peor que el de antes, y tiene que crear las columnas pedidas ---

$CausaM69 = 'java.nio.file.NoSuchFileException: /datos/salida/RESUMEN.txt'
$PeorM69 = "Con tu test, el caso vacio de cargaJob acaba FAILED ($CausaM69) y con el test de antes acababa COMPLETED."
$TablasM69 = 'M69_TABLAS=T_A:ID|NOMBRE,T_B:ID'
$SitioM69 = 'src/main/java/com/acme/viejo/Recibos.java:42'
$MotivoColumnaM69 = "El test del original no crea la columna RECIBOS.IMPORTE_NETO (la usa $SitioM69)."

# Deja en el prueba-local.json de antes (el $Anterior del siguiente lanzamiento) un caso que no se pudo preparar con este motivo.
function Pone-Motivo-M69($E, [string]$Motivo) {
  $j = Lee-Json $E.Json
  $j.casos[0].resultado = 'no se pudo preparar'
  $j.casos[0].motivo = $Motivo
  [System.IO.File]::WriteAllText($E.Json, (ConvertTo-Json -InputObject $j -Depth 10))
}

# El estado del caso vacio guardado (salidas/vacio) del job $Job: la linea estado= de su estado.txt.
function Vacio-Estado-M69($E, [string]$Carpeta = 'salidas/vacio', [string]$Job = 'cargaJob') {
  $f = Get-Ruta $E.Local "$Carpeta/$Job/estado.txt"
  if (-not (Test-Path -LiteralPath $f)) { return '' }
  return ([regex]::Match([System.IO.File]::ReadAllText($f), '(?m)^estado=(\S+)').Groups[1].Value)
}

$Pruebas['m69 (b1) el caso vacio de antes es COMPLETED y el nuevo FAILED con una NoSuchFileException: el primer intento se rechaza con el motivo, el estado y la causa; el segundo, COMPLETED, se acepta'] = {
  $e = Escenario-M69 'm69-b1' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M69 $e
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  $o1 = Test-Guardado $e 'original'
  $r = Prueba-M69 $e "arnes-original@2@M69_VACIO=FAILED~M69_CAUSA=$CausaM69;arnes-original@3@M69_VERSION=v3" @('-RehacerOriginal')
  Igual 'con -RehacerOriginal, sale con 0' 0 $r.Codigo
  Igual 'el original lleva tres llamadas en total: la primera vez y dos ahora' 3 (Llamadas-Arnes $e 'original').Count
  Comprueba 'la consola rechaza el primer intento con el motivo, el estado y la causa' ($r.Salida.Contains("Arnes del original rechazado: $PeorM69")) (Cola $r.Salida)
  Comprueba 'el reintento recibe el motivo entero' ((Registro-Arnes $e 'original' 2).Contains($PeorM69)) (Cola (Registro-Arnes $e 'original' 2))
  Igual 'la tarea del original queda hecha, con dos intentos' 'hecha:2' "$((Tarea-Arnes $e 'original').estado):$((Tarea-Arnes $e 'original').intentos)"
  Comprueba 'el test guardado es el del segundo intento' ((Test-Guardado $e 'original').Contains('M69_VERSION=v3')) ''
  Igual 'el caso vacio guardado es COMPLETED' 'COMPLETED' (Vacio-Estado-M69 $e)
  Igual 'arnes-anterior es el de la primera vez' $o1 (Test-Anterior $e 'original')
  Comprueba 'no se vuelve al de antes' ($r.Salida -notmatch 'sigo con el de antes') (Cola $r.Salida)
  Igual 'el caso sale igual' 'igual' ((Resultados $e) -join ',')
}

$Pruebas['m69 (b2) al nuevo le falta una tabla que antes estaba, o una columna de una tabla que antes estaba: se rechaza con lo que falta y el segundo intento, completo, se acepta'] = {
  $e = Escenario-M69 'm69-b2' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M69 $e "arnes-original@1@$TablasM69;arnes-migrado@1@$TablasM69"
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  Comprueba 'el caso vacio guardado lleva las dos tablas' ((Test-Path -LiteralPath (Get-Ruta $e.Local 'salidas/vacio/cargaJob/tablas/T_A.csv')) -and (Test-Path -LiteralPath (Get-Ruta $e.Local 'salidas/vacio/cargaJob/tablas/T_B.csv'))) ''
  # el intento 1 pierde T_B; el 2 completo (con una columna de mas, que no cuenta)
  $g = "arnes-original@2@M69_TABLAS=T_A:ID|NOMBRE;arnes-original@3@M69_TABLAS=T_A:ID|NOMBRE|EXTRA,T_B:ID;arnes-migrado@2@$TablasM69;arnes-migrado@3@$TablasM69"
  $r = Prueba-M69 $e $g @('-RehacerOriginal')
  Igual 'con -RehacerOriginal, sale con 0' 0 $r.Codigo
  Comprueba 'se rechaza el primero por la tabla que falta' ($r.Salida.Contains('Arnes del original rechazado: En el caso vacio de cargaJob, tu base no tiene estas tablas que si tenia la del test de antes: T_B.')) (Cola $r.Salida)
  Igual 'la tarea del original queda hecha, con dos intentos' 'hecha:2' "$((Tarea-Arnes $e 'original').estado):$((Tarea-Arnes $e 'original').intentos)"
  Comprueba 'el guardado es el segundo' ((Lee $e.Local 'salidas/vacio/cargaJob/tablas/T_A.csv').Contains('EXTRA')) ''
  # otra vez: el intento 1 pierde una columna de T_A (NOMBRE); el 2 la trae
  $g = "arnes-original@4@M69_TABLAS=T_A:ID,T_B:ID;arnes-original@5@$TablasM69;arnes-migrado@3@$TablasM69;arnes-migrado@4@$TablasM69"
  $r = Prueba-M69 $e $g @('-RehacerOriginal')
  Igual 'la segunda vez, sale con 0' 0 $r.Codigo
  Comprueba 'se rechaza el primero por la columna que falta' ($r.Salida.Contains('Arnes del original rechazado: En el caso vacio de cargaJob, la tabla T_A de tu base ya no tiene estas columnas que si tenia la del test de antes: NOMBRE, EXTRA.')) (Cola $r.Salida)
  Igual 'la tarea del original queda hecha, con dos intentos' 'hecha:2' "$((Tarea-Arnes $e 'original').estado):$((Tarea-Arnes $e 'original').intentos)"
}

$Pruebas['m69 (b3) el prueba-local.json de antes dice que el test no crea RECIBOS.IMPORTE_NETO: sin ella en tablas/RECIBOS.csv se rechaza el primer intento, con ella se acepta; sin la tabla en el motivo vale en cualquier tabla'] = {
  $e = Escenario-M69 'm69-b3' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M69 $e 'arnes-original@1@M69_TABLAS=RECIBOS:ID|NOMBRE;arnes-migrado@1@M69_TABLAS=RECIBOS:ID|NOMBRE'
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  Pone-Motivo-M69 $e $MotivoColumnaM69
  $conColumna = 'M69_TABLAS=RECIBOS:ID|NOMBRE|IMPORTE_NETO'
  $g = "arnes-original@2@M69_TABLAS=RECIBOS:ID|NOMBRE;arnes-original@3@$conColumna;arnes-migrado@2@$conColumna;arnes-migrado@3@$conColumna"
  $r = Prueba-M69 $e $g @('-RehacerOriginal')
  Igual 'con -RehacerOriginal, sale con 0' 0 $r.Codigo
  Comprueba 'se rechaza el primero sin la columna, con su sitio' ($r.Salida.Contains("Arnes del original rechazado: Tu base no crea estas columnas que usa el codigo: RECIBOS.IMPORTE_NETO ($SitioM69).")) (Cola $r.Salida)
  Igual 'la tarea del original queda hecha, con dos intentos' 'hecha:2' "$((Tarea-Arnes $e 'original').estado):$((Tarea-Arnes $e 'original').intentos)"
  Comprueba 'el guardado lleva la columna' ((Lee $e.Local 'salidas/vacio/cargaJob/tablas/RECIBOS.csv').Contains('IMPORTE_NETO')) ''
  Comprueba 'no hay aviso de columnas sin crear' ($r.Salida -notmatch 'sigue sin crear') (Cola $r.Salida)
  # la columna esta en otra tabla: el motivo sin tabla la acepta; el motivo con la tabla RECIBOS, no
  $e = Escenario-M69 'm69-b3b' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M69 $e
  Igual 'sin tabla: la primera vez sale con 0' 0 $r.Codigo
  Pone-Motivo-M69 $e "El test del original no crea la columna IMPORTE_NETO (la usa $SitioM69)."
  $r = Prueba-M69 $e 'arnes-original@2@M69_TABLAS=OTRA:ID|IMPORTE_NETO' @('-RehacerOriginal')
  Igual 'sin tabla: sale con 0' 0 $r.Codigo
  Igual 'sin tabla: la tarea del original queda hecha a la primera' 'hecha:1' "$((Tarea-Arnes $e 'original').estado):$((Tarea-Arnes $e 'original').intentos)"
  Comprueba 'sin tabla: ni rechazo ni aviso' ($r.Salida -notmatch 'sigue sin crear|Tu base no crea') (Cola $r.Salida)
}

$Pruebas['m69 (b4) en el ultimo intento sigue FAILED y antes era COMPLETED: se vuelve al de antes (la copia, arnes/original y salidas/vacio), sale el aviso y ningun caso hecho se ejecuta otra vez; el del migrado tambien vuelve'] = {
  $e = Escenario-M69 'm69-b4' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba-M69 $e
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  $o1 = Test-Guardado $e 'original'; $m1 = Test-Guardado $e 'migrado'
  $v1 = Foto-Carpeta $e 'salidas/vacio'
  $antes = @(1..2 | ForEach-Object { Orig-Mvn $e 'cargaJob' ('caso-0' + $_) }) -join ','
  Igual 'cada caso se ejecuto 3 veces en el original' '3,3' $antes
  $llamadas = (Llamadas $e).Count
  $mal = "M69_VACIO=FAILED~M69_CAUSA=$CausaM69~M69_VERSION=v"
  $r = Prueba-M69 $e "arnes-original@2@${mal}2;arnes-original@3@${mal}3" @('-RehacerOriginal')
  Igual 'con -RehacerOriginal, sale con 0' 0 $r.Codigo
  Igual 'dos llamadas nuevas: las dos del original, ninguna del migrado' ($llamadas + 2) (Llamadas $e).Count
  Comprueba 'el primer intento se rechaza' ($r.Salida.Contains("Arnes del original rechazado: $PeorM69")) (Cola $r.Salida)
  $aviso = "El test nuevo del original quedaba peor que el de antes ($($PeorM69.TrimEnd('.'))): sigo con el de antes."
  Comprueba 'el ultimo intento no se acepta: sale el aviso de que se sigue con el de antes' ($r.Salida.Contains($aviso)) (Cola $r.Salida)
  Igual 'arnes/original es el de antes, byte a byte' $o1 (Test-Guardado $e 'original')
  Igual 'la copia del original tiene el de antes' $o1 (Lee $e.CopiaOrig 'src/test/java/com/acme/viejo/PruebaLocalTest.java')
  Igual 'salidas/vacio es el de antes, entero' $v1 (Foto-Carpeta $e 'salidas/vacio')
  Igual 'la tarea del original queda hecha, con dos intentos' 'hecha:2' "$((Tarea-Arnes $e 'original').estado):$((Tarea-Arnes $e 'original').intentos)"
  Comprueba 'y guarda el motivo' ([string](Tarea-Arnes $e 'original').motivo -match 'quedaba peor que el de antes') ''
  Igual 'el del migrado guardado es el de antes (no se rehizo: solo cambiaba el original)' $m1 (Test-Guardado $e 'migrado')
  Comprueba 'la consola dice que el del migrado sigue valiendo' ($r.Salida -match 'Arnes del migrado: bien \(el test de otro lanzamiento sigue valiendo\)') (Cola $r.Salida)
  Igual 'la tarea del migrado queda hecha' 'hecha' (Tarea-Arnes $e 'migrado').estado
  $despues = @(1..2 | ForEach-Object { Orig-Mvn $e 'cargaJob' ('caso-0' + $_) }) -join ','
  Igual 'ningun caso se ejecuta otra vez en el original' $antes $despues
  Igual 'los dos casos salen iguales' 'igual,igual' ((Resultados $e) -join ',')
}

$Pruebas['m69 (b5) en el ultimo intento no queda peor pero le falta la columna pedida: se acepta con un aviso, y el test nuevo se queda'] = {
  $e = Escenario-M69 'm69-b5' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M69 $e 'arnes-original@1@M69_TABLAS=RECIBOS:ID|NOMBRE;arnes-migrado@1@M69_TABLAS=RECIBOS:ID|NOMBRE'
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  Pone-Motivo-M69 $e $MotivoColumnaM69
  $sin = 'M69_TABLAS=RECIBOS:ID|NOMBRE'
  $r = Prueba-M69 $e "arnes-original@2@$sin~M69_VERSION=v2;arnes-original@3@$sin~M69_VERSION=v3;arnes-migrado@2@$sin;arnes-migrado@3@$sin" @('-RehacerOriginal')
  Igual 'sale con 0' 0 $r.Codigo
  Comprueba 'se rechaza el primero' ($r.Salida.Contains("Arnes del original rechazado: Tu base no crea estas columnas que usa el codigo: RECIBOS.IMPORTE_NETO ($SitioM69).")) (Cola $r.Salida)
  Comprueba 'el ultimo se acepta' ($r.Salida -match 'Arnes del original: bien\.') (Cola $r.Salida)
  $aviso = "La base de tu test sigue sin crear estas columnas que usa el codigo: RECIBOS.IMPORTE_NETO ($SitioM69). Los casos que las usen saldran FAILED en el original. Para que lo escriba otra vez con ellas, relanza con -RehacerOriginal."
  Comprueba 'con el aviso' ($r.Salida.Contains($aviso)) (Cola $r.Salida)
  Comprueba 'no se vuelve al de antes' ($r.Salida -notmatch 'sigo con el de antes') (Cola $r.Salida)
  Comprueba 'el test guardado es el del segundo intento' ((Test-Guardado $e 'original').Contains('M69_VERSION=v3')) ''
  Igual 'la tarea del original queda hecha, con dos intentos' 'hecha:2' "$((Tarea-Arnes $e 'original').estado):$((Tarea-Arnes $e 'original').intentos)"
}

$Pruebas['m69 (b6) antes era FAILED y el nuevo es FAILED: no se rechaza por el estado; pasar de FAILED a EXCEPCION si es peor, a STOPPED no'] = {
  $e = Escenario-M69 'm69-b6' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M69 $e "arnes-original@1@M69_VACIO=FAILED~M69_CAUSA=$CausaM69"
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  Igual 'el caso vacio guardado es FAILED' 'FAILED' (Vacio-Estado-M69 $e)
  $r = Prueba-M69 $e "arnes-original@2@M69_VACIO=FAILED~M69_CAUSA=$CausaM69~M69_VERSION=v2" @('-RehacerOriginal')
  Igual 'FAILED a FAILED: sale con 0' 0 $r.Codigo
  Igual 'se acepta a la primera' 'hecha:1' "$((Tarea-Arnes $e 'original').estado):$((Tarea-Arnes $e 'original').intentos)"
  Comprueba 'sin rechazo ni vuelta atras' ($r.Salida -notmatch 'rechazado: Con tu test|sigo con el de antes') (Cola $r.Salida)
  Comprueba 'el guardado es el nuevo' ((Test-Guardado $e 'original').Contains('M69_VERSION=v2')) ''
  $r = Prueba-M69 $e 'arnes-original@3@M69_VACIO=EXCEPCION;arnes-original@4@M69_VACIO=STOPPED~M69_VERSION=v4' @('-RehacerOriginal')
  Igual 'de FAILED a EXCEPCION y a STOPPED: sale con 0' 0 $r.Codigo
  Comprueba 'EXCEPCION es peor que FAILED: se rechaza, con la clase y lo que acababa antes (y su causa)' ($r.Salida.Contains("Arnes del original rechazado: Con tu test, el caso vacio de cargaJob acaba EXCEPCION (BeanCreationException) y con el test de antes acababa FAILED ($CausaM69).")) (Cola $r.Salida)
  Igual 'STOPPED no es peor que FAILED: hecha tras dos intentos' 'hecha:2' "$((Tarea-Arnes $e 'original').estado):$((Tarea-Arnes $e 'original').intentos)"
  Comprueba 'el guardado es el del segundo intento' ((Test-Guardado $e 'original').Contains('M69_VERSION=v4')) ''
}

$Pruebas['m69 (b7) un test guardado de otro lanzamiento que no se rehace no pasa por estas puertas: aunque le falte la columna pedida, se usa sin rechazo ni aviso'] = {
  $e = Escenario-M69 'm69-b7' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M69 $e 'arnes-original@1@M69_TABLAS=RECIBOS:ID|NOMBRE;arnes-migrado@1@M69_TABLAS=RECIBOS:ID|NOMBRE'
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  Pone-Motivo-M69 $e $MotivoColumnaM69
  Cambia-Huella $e 'original'
  $n = @(Llamadas $e).Count
  $r = Prueba-M69 $e ''
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'sin llamadas a Copilot' $n @(Llamadas $e).Count
  Comprueba 'dice que el test de otro lanzamiento sigue valiendo' ($r.Salida -match 'Arnes del original: bien \(el test de otro lanzamiento sigue valiendo\)') (Cola $r.Salida)
  Comprueba 'sin aviso ni rechazo de columnas' ($r.Salida -notmatch 'sigue sin crear|Tu base no crea') (Cola $r.Salida)
}

$Pruebas['m69 (b8) las columnas se comparan sin distinguir mayusculas: el test nuevo con id y nombre en minusculas, donde antes estaba ID y NOMBRE, se acepta en el primer intento'] = {
  $e = Escenario-M69 'm69-b8' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M69 $e "arnes-original@1@$TablasM69;arnes-migrado@1@$TablasM69"
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  $minus = 'M69_TABLAS=T_A:id|nombre,T_B:id'
  $r = Prueba-M69 $e "arnes-original@2@$minus;arnes-migrado@2@$TablasM69" @('-RehacerOriginal')
  Igual 'con -RehacerOriginal, sale con 0' 0 $r.Codigo
  Comprueba 'no se rechaza nada' ($r.Salida -notmatch 'Arnes del original rechazado') (Cola $r.Salida)
  Igual 'la tarea del original queda hecha, con un intento' 'hecha:1' "$((Tarea-Arnes $e 'original').estado):$((Tarea-Arnes $e 'original').intentos)"
  Comprueba 'el guardado es el nuevo, en minusculas' ((Lee $e.Local 'salidas/vacio/cargaJob/tablas/T_A.csv') -cmatch 'nombre') ''
}

$Pruebas['m69 (b9) tras volver al de antes, un caso no-aplica de antes de M59 (sin hash del arnes) no se prepara otra vez: el test del original no ha cambiado'] = {
  $e = Escenario-M69 'm69-b9' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba-M69 $e '' @() '' 'caso-no-aplica:caso-cargaJob-01'
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  Igual 'el caso 1 queda sin probar en local' 'sin probar en local' (Caso $e 'cargaJob' 'caso-01').resultado
  Pon-Hash-M59 $e 'caso-cargaJob-01' $null
  $mal = "M69_VACIO=FAILED~M69_CAUSA=$CausaM69~M69_VERSION=v"
  $r = Prueba-M69 $e "arnes-original@2@${mal}2;arnes-original@3@${mal}3" @('-RehacerOriginal')
  Igual 'con -RehacerOriginal, sale con 0' 0 $r.Codigo
  Comprueba 'se vuelve al de antes' ($r.Salida.Contains('sigo con el de antes')) (Cola $r.Salida)
  Igual 'el caso no-aplica no llama a la IA otra vez' 1 (Llamadas-Caso-M59 $e 'caso-cargaJob-01')
  Comprueba 'y la consola no dice nada de prepararlo otra vez' (-not $r.Salida.Contains('se vuelven a preparar')) (Cola $r.Salida)
  Igual 'sigue sin probar en local' 'sin probar en local' (Caso $e 'cargaJob' 'caso-01').resultado
}

# --- (c) el primer intento del original ya sabe lo que fallo en el caso vacio de antes ---

$Pruebas['m69 (c1) el previo del primer intento del original lleva una linea del caso vacio de antes que no acabo COMPLETED, con su causa; el job que si acabo no lleva ninguna; la huella no cambia'] = {
  $e = Escenario-M69 'm69-c1' ([ordered]@{ cargaJob = @('importe=10.00'); otroJob = @('importe=20.00') })
  $r = Prueba-M69 $e "arnes-original@1@M69_VACIO=FAILED:cargaJob~M69_CAUSA=$CausaM69"
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  Comprueba 'el primer intento de la primera vez no lleva nada del caso vacio de antes' (-not (Registro-Arnes $e 'original' 1).Contains('Con el test de antes')) ''
  Igual 'el caso vacio guardado es FAILED en cargaJob y COMPLETED en otroJob' 'FAILED,COMPLETED' ((Vacio-Estado-M69 $e) + ',' + (Vacio-Estado-M69 $e 'salidas/vacio' 'otroJob'))
  $huella = (Tarea-Arnes $e 'original').entradas.huella
  $r = Prueba-M69 $e '' @('-RehacerOriginal')
  Igual 'con -RehacerOriginal, sale con 0' 0 $r.Codigo
  $p = Registro-Arnes $e 'original' 1
  $linea = "Con el test de antes, el caso vacio de cargaJob acababa FAILED: $CausaM69."
  Comprueba 'el primer intento lleva la linea de cargaJob, con su causa' ($p.Contains($linea)) (Cola $p)
  Comprueba 'y ninguna de otroJob, que acabo COMPLETED' (-not $p.Contains('el caso vacio de otroJob')) (Cola $p)
  Comprueba 'dentro del bloque de lo que fallo la otra vez' ($p.Contains('Lo que fallo la otra vez (de un lanzamiento anterior):')) (Cola $p)
  Igual 'la huella de la tarea no cambia' $huella (Tarea-Arnes $e 'original').entradas.huella
  Comprueba 'el primer intento del migrado no lleva la linea' (-not (Registro-Arnes $e 'migrado' 1).Contains('Con el test de antes')) ''
}

$Pruebas['m69 (c2) cuatro jobs cuyo caso vacio de antes acabo EXCEPCION: el previo lleva tres lineas, las de los tres primeros jobs, con la clase y la causa'] = {
  $e = Escenario-M69 'm69-c2' ([ordered]@{ aJob = @('importe=10.00'); bJob = @('importe=20.00'); cJob = @('importe=30.00'); dJob = @('importe=40.00') })
  $r = Prueba-M69 $e "arnes-original@1@M69_VACIO=EXCEPCION~M69_CAUSA=java.lang.IllegalStateException: sin correo"
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  $r = Prueba-M69 $e '' @('-RehacerOriginal')
  Igual 'con -RehacerOriginal, sale con 0' 0 $r.Codigo
  $p = Registro-Arnes $e 'original' 1
  Igual 'tres lineas, no cuatro' 3 ([regex]::Matches($p, 'Con el test de antes, el caso vacio de')).Count
  foreach ($j in @('aJob', 'bJob', 'cJob')) {
    Comprueba "la de $j, con la clase y la causa" ($p.Contains("Con el test de antes, el caso vacio de $j acababa EXCEPCION: BeanCreationException: java.lang.IllegalStateException: sin correo.")) (Cola $p)
  }
  Comprueba 'y la del cuarto no' (-not $p.Contains('el caso vacio de dJob')) (Cola $p)
}

# --- (d) la causa del caso vacio de antes cuando no hay causas.json (un caso vacio guardado antes de M69) ---

# Deja en registros un registro de Maven del caso vacio del arnes del original (el nombre de Invoke-Maven: mvn-<n>-arnes-original--caso-vacio.log) con las
# lineas $Lineas, escrito hace $Minutos minutos.
function Pon-Registro-Vacio-M69($E, [int]$N, [string[]]$Lineas, [int]$Minutos = 0) {
  $f = Get-Ruta $E.Local "registros/mvn-$N-arnes-original--caso-vacio.log"
  [System.IO.File]::WriteAllText($f, (($Lineas -join "`n") + "`n"))
  [System.IO.File]::SetLastWriteTimeUtc($f, [DateTime]::UtcNow.AddMinutes(-$Minutos))
}

# Deja el caso vacio guardado como lo dejaba M68: sin causas.json y sin ningun registro de Maven del caso vacio del original.
function Deja-Vacio-De-Antes-M69($E) {
  $c = Get-Ruta $E.Local 'salidas/vacio/causas.json'
  if (Test-Path -LiteralPath $c) { Remove-Item -LiteralPath $c }
  foreach ($f in @(Get-ChildItem -LiteralPath (Get-Ruta $E.Local 'registros') -File -Filter 'mvn-*-arnes-original--caso-vacio.log')) { Remove-Item -LiteralPath $f.FullName }
}

$Pruebas['m69 (d1) un caso vacio FAILED guardado sin causas.json y un registro de Maven con la NoSuchFileException: el primer intento lleva la linea con la causa, y la causa se apunta en causas.json de lo guardado y de lo de antes'] = {
  $e = Escenario-M69 'm69-d1' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M69 $e 'arnes-original@1@M69_VACIO=FAILED'
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  Igual 'el caso vacio guardado es FAILED' 'FAILED' (Vacio-Estado-M69 $e)
  Deja-Vacio-De-Antes-M69 $e
  Pon-Registro-Vacio-M69 $e 7 @('[INFO] Running com.acme.viejo.PruebaLocalTest', "Caused by: $CausaM69", '[INFO] BUILD SUCCESS')
  $r = Prueba-M69 $e '' @('-RehacerOriginal')
  Igual 'con -RehacerOriginal, sale con 0' 0 $r.Codigo
  $p = Registro-Arnes $e 'original' 1
  $linea = "Con el test de antes, el caso vacio de cargaJob acababa FAILED: $CausaM69."
  Comprueba 'el primer intento lleva la linea de cargaJob, con la causa del registro' ($p.Contains($linea)) (Cola $p)
  Igual 'lo guardado de antes lleva la causa en su causas.json' $CausaM69 ([string](Lee-Json (Get-Ruta $e.Local 'salidas/vacio-anterior/causas.json')).cargaJob)
}

$Pruebas['m69 (d2) dos registros del caso vacio: la causa es la del mas reciente por fecha de escritura, no por el numero del nombre'] = {
  $e = Escenario-M69 'm69-d2' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M69 $e 'arnes-original@1@M69_VACIO=FAILED'
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  Deja-Vacio-De-Antes-M69 $e
  Pon-Registro-Vacio-M69 $e 9 @('Caused by: java.lang.IllegalStateException: de un lanzamiento viejo') 90
  Pon-Registro-Vacio-M69 $e 2 @("Caused by: $CausaM69") 1
  $r = Prueba-M69 $e '' @('-RehacerOriginal')
  Igual 'con -RehacerOriginal, sale con 0' 0 $r.Codigo
  $p = Registro-Arnes $e 'original' 1
  Comprueba 'el primer intento lleva la causa del registro mas reciente (el de numero 2)' ($p.Contains("Con el test de antes, el caso vacio de cargaJob acababa FAILED: $CausaM69.")) (Cola $p)
  Comprueba 'y no la del de numero 9' (-not $p.Contains('de un lanzamiento viejo')) (Cola $p)
}

$Pruebas['m69 (d3) con causas.json manda causas.json aunque haya un registro mas reciente con otra causa'] = {
  $e = Escenario-M69 'm69-d3' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M69 $e "arnes-original@1@M69_VACIO=FAILED~M69_CAUSA=$CausaM69"
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  Igual 'causas.json lleva la causa' $CausaM69 ([string](Lee-Json (Get-Ruta $e.Local 'salidas/vacio/causas.json')).cargaJob)
  Pon-Registro-Vacio-M69 $e 50 @('Caused by: java.lang.IllegalStateException: la del registro') 0
  $r = Prueba-M69 $e '' @('-RehacerOriginal')
  Igual 'con -RehacerOriginal, sale con 0' 0 $r.Codigo
  $p = Registro-Arnes $e 'original' 1
  Comprueba 'el primer intento lleva la causa de causas.json' ($p.Contains("Con el test de antes, el caso vacio de cargaJob acababa FAILED: $CausaM69.")) (Cola $p)
  Comprueba 'y no la del registro' (-not $p.Contains('la del registro')) (Cola $p)
}

$Pruebas['m69 (d4) la causa de lo guardado antes de M69 se apunta al empezar: el motivo del primer intento rechazado dice la de antes y no la del registro del intento nuevo'] = {
  $e = Escenario-M69 'm69-d4' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M69 $e "arnes-original@1@M69_VACIO=FAILED~M69_CAUSA=$CausaM69"
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  $c = Get-Ruta $e.Local 'salidas/vacio/causas.json'
  Remove-Item -LiteralPath $c
  $nueva = 'java.lang.IllegalStateException: sin correo'
  $r = Prueba-M69 $e "arnes-original@2@M69_VACIO=EXCEPCION~M69_CAUSA=$nueva" @('-RehacerOriginal')
  Igual 'con -RehacerOriginal, sale con 0' 0 $r.Codigo
  $dice = "Arnes del original rechazado: Con tu test, el caso vacio de cargaJob acaba EXCEPCION (BeanCreationException: $nueva) y con el test de antes acababa FAILED ($CausaM69)."
  Comprueba 'el primer intento se rechaza por pasar de FAILED a EXCEPCION, con la causa de antes (la del registro de antes de empezar)' ($r.Salida.Contains($dice)) (Cola $r.Salida)
}

$Pruebas['m69 (d5) sin registro de Maven del caso vacio, o con uno sin causa: la linea sale sin causa'] = {
  foreach ($n in @('sin-registro', 'sin-causa')) {
    $e = Escenario-M69 "m69-d5-$n" ([ordered]@{ cargaJob = @('importe=10.00') })
    $r = Prueba-M69 $e 'arnes-original@1@M69_VACIO=FAILED'
    Igual "$n : la primera vez sale con 0" 0 $r.Codigo
    Deja-Vacio-De-Antes-M69 $e
    if ($n -eq 'sin-causa') { Pon-Registro-Vacio-M69 $e 3 @('[INFO] Running com.acme.viejo.PruebaLocalTest', '[INFO] BUILD SUCCESS') }
    $r = Prueba-M69 $e '' @('-RehacerOriginal')
    Igual "$n : con -RehacerOriginal, sale con 0" 0 $r.Codigo
    $p = Registro-Arnes $e 'original' 1
    Comprueba "$n : la linea sale como hoy, sin causa" ($p.Contains('Con el test de antes, el caso vacio de cargaJob acababa FAILED.')) (Cola $p)
  }
}

# ===================== M67: el mismo fichero en otra carpeta es una sola diferencia, y una sola causa =====================
# Escenarios con el Maven de m67 (tests/falsos/m67-mvn.ps1, sobre el de m25): el original deja CIERRE_2024_06_<n>.txt en trabajo/enviados y en ficheros/enviados y el
# migrado, que lleva minimo=5.01 en src/main/resources/regla.txt, en ficheros/salida; el 'arreglo' de m25-copilot.ps1 (reparar-arregla) lo deja como el original.
# Las banderas de RESCATE_M67 (misma, contenido, log, suelto) cambian lo que deja cada lado.

$OrigM67 = 'en ficheros/enviados y trabajo/enviados'
$MigM67 = 'en ficheros/salida'
$ClaveM67 = 'ficheros/enviados,trabajo/enviados -> ficheros/salida'
$AyudaM67 = 'Suele ser el test del migrado, que da a su propiedad de carpeta otro valor: relanza con -RehacerArnes. Si no, mira la propiedad en el application.yml del migrado o un cambio del codigo.'

function Escenario-M67([string]$Nombre, $Casos, [hashtable]$Mas = @{}) {
  $aj = @{ MvnExe = (Join-Path $falsos 'm67-mvn.ps1') }
  foreach ($k in $Mas.Keys) { $aj[$k] = $Mas[$k] }
  return (Escenario-M25 $Nombre $Casos -Sano -Ajustes $aj)
}

# Lanza con las banderas $Banderas del Maven falso (RESCATE_M67) y el guion $Guion del Copilot falso.
function Prueba-M67($E, [string]$Banderas = '', [string[]]$A = @(), [string]$Guion = '') {
  $env:RESCATE_M67 = $Banderas
  try { return (Prueba $E $A $Guion) }
  finally { $env:RESCATE_M67 = '' }
}

function Difs-M67($E, [string]$Caso) { return @((Caso $E 'cargaJob' $Caso).diferencias | Where-Object { $_ }) }

# Un script con lo de Compare-Caso y Join-OtraCarpeta que, por cada 'Caso <id> @{ carpeta/fichero = contenido } @{ ... }' de $Cuerpo (el original y el migrado), escribe una linea
# 'R <id> <tipo>|<fichero>|<original>|<migrado>|<lineas>|<linea>|<nota>|<clave>' por diferencia. Devuelve id -> sus lineas.
function Compara-M67([string]$Nombre, [string]$Cuerpo) {
  $f = Join-Path $Dir "$Nombre.ps1"
  $cabeza = @'
param([string]$Raiz)
$Inv = [System.Globalization.CultureInfo]::InvariantCulture
$Utf8Estricto = New-Object System.Text.UTF8Encoding($false, $true)
$RutasCopia = @()
$Hoy = @()
$Cfg = @{ CompararIgnorar = @('*.log') }
function Caso([string]$Id, [hashtable]$A, [hashtable]$B) {
  $dirs = @{}
  foreach ($x in @(@('A', $A), @('B', $B))) {
    $d = Join-Path (Join-Path $Raiz $Id) $x[0]
    [void](New-Item -ItemType Directory -Path $d -Force)
    foreach ($k in $x[1].Keys) {
      $p = Join-Path $d $k
      [void](New-Item -ItemType Directory -Path (Split-Path $p -Parent) -Force)
      [System.IO.File]::WriteAllText($p, $x[1][$k])
    }
    $dirs[$x[0]] = $d
  }
  $dif = @(Compare-Caso $dirs.A $dirs.B)
  $dif = @(Join-OtraCarpeta $dif $dirs.A $dirs.B)
  foreach ($d in $dif) { 'R ' + $Id + ' ' + (Get-TipoDif $d) + '|' + $d.fichero + '|' + $d.original + '|' + $d.migrado + '|' + $d.lineas + '|' + $d.linea + '|' + $d.nota + '|' + $d.clave }
  if ($dif.Count -eq 0) { 'R ' + $Id + ' (ninguna)' }
}
'@
  $comun = Join-Path (Split-Path -Parent $Script) 'comun.ps1'
  $funciones = (@('Compare-Caso', 'Join-OtraCarpeta', 'New-DifOtraCarpeta', 'Get-TipoDif', 'Format-Carpetas', 'Compare-Fichero') + $FnLeer + @('Sort-Tabla', 'Resolve-ParTablas', 'Sort-Ordinal', 'Get-Normal', 'Get-Legible', 'Get-NotaJdk', 'Test-Ignorado'))
  [System.IO.File]::WriteAllText($f, ($cabeza + "`n" + (Texto-De-Funciones $Script $funciones) + "`n" + (Texto-De-Funciones $comun @('Get-Rel', 'Join-Ruta')) + "`n" + '$Latin = [System.Text.Encoding]::GetEncoding(28591); $Utf8 = New-Object System.Text.UTF8Encoding($false)' + "`n" + $Cuerpo))
  $r = Lanzar $f @((Join-Path $Dir ($Nombre + '-dirs')))
  $v = [ordered]@{}
  foreach ($l in @($r.Salida -split "`n")) {
    if ($l -cmatch '^R (\S+) (.*)$') { $id = $Matches[1]; if (-not $v.Contains($id)) { $v[$id] = @() }; $v[$id] += $Matches[2].TrimEnd() }
  }
  return $v
}

$Pruebas['m67 (a1) tres casos con otra fecha en el nombre, el original con el fichero en dos carpetas y el migrado en otra: una sola diferencia por caso, con las carpetas de los dos lados, y la consola lo dice'] = {
  $e = Escenario-M67 'm67-a1' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00', 'importe=30.00') })
  $r = Prueba-M67 $e
  Igual 'sale con 2' 2 $r.Codigo
  Igual 'los tres casos salen distintos' 'distinto,distinto,distinto' ((Resultados $e) -join ',')
  foreach ($n in 1..3) {
    $d = @(Difs-M67 $e "caso-0$n")
    Igual "caso-0${n}: una sola diferencia" 1 $d.Count
    Igual "caso-0${n}: el nombre del caso, el tipo nuevo y lo que dice cada lado" "CIERRE_2024_06_0$n.txt|True|$OrigM67|$MigM67" ($d[0].fichero + '|' + $d[0].otraCarpeta + '|' + $d[0].original + '|' + $d[0].migrado)
    Igual "caso-0${n}: las carpetas de cada lado, en una lista" 'ficheros/enviados,trabajo/enviados|ficheros/salida' ((@($d[0].carpetasOriginal) -join ',') + '|' + (@($d[0].carpetasMigrado) -join ','))
    Igual "caso-0${n}: la clave es la pareja de carpetas" $ClaveM67 $d[0].clave
  }
  Comprueba 'la consola dice las carpetas de cada lado del primer caso' ($r.Salida.Contains("CIERRE_2024_06_01.txt: el original lo deja $OrigM67; el migrado, $MigM67")) (Cola $r.Salida)
  Comprueba 'y no dice (no esta)' ($r.Salida -notmatch '\(no esta\)') (Cola $r.Salida)
}

$Pruebas['m67 (a2) el contenido: igual al de alguno del original, se dice (y a cual); distinto, sale la primera linea distinta, con sus lineas'] = {
  $cuerpo = @'
Caso 'igual' @{ 'ficheros/enviados/X_01.txt' = "a`nb`n"; 'trabajo/enviados/X_01.txt' = "a`nb`n" } @{ 'ficheros/salida/X_01.txt' = "a`nb`n" }
Caso 'distinto' @{ 'ficheros/enviados/X_01.txt' = "a`nb`nc`n" } @{ 'ficheros/salida/X_01.txt' = "a`nz`nz`n" }
Caso 'solo-el-segundo' @{ 'ficheros/enviados/X_01.txt' = "a`nb`n"; 'trabajo/enviados/X_01.txt' = "a`nc`n" } @{ 'ficheros/salida/X_01.txt' = "a`nc`n" }
Caso 'fechas' @{ 'ficheros/enviados/X_01.txt' = "a`n"; 'ficheros/enviados/X_02.txt' = "a`n" } @{ 'ficheros/salida/X_01.txt' = "a`n"; 'ficheros/salida/X_02.txt' = "b`n" }
Caso 'raiz' @{ 'X_01.txt' = "a`n" } @{ 'ficheros/salida/X_01.txt' = "a`n" }
'@
  $v = Compara-M67 'm67-a2' $cuerpo
  $igual = 'el contenido es igual al de'
  Igual 'igual: una linea, con las dos carpetas del original y la primera con el mismo contenido' @("otraCarpeta|X_01.txt|en ficheros/enviados y trabajo/enviados|en ficheros/salida|1|1|$igual ficheros/enviados/X_01.txt, del original|ficheros/enviados,trabajo/enviados -> ficheros/salida") @($v['igual'])
  Igual 'distinto: la primera linea distinta, la 2, y cuantas son (2)' @('otraCarpeta|X_01.txt|en ficheros/enviados|en ficheros/salida|2|2|el contenido es distinto: la primera linea distinta, la 2: original [b]; migrado [z]|ficheros/enviados -> ficheros/salida') @($v['distinto'])
  Igual 'igual al del original de la otra carpeta: dice cual' @("otraCarpeta|X_01.txt|en ficheros/enviados y trabajo/enviados|en ficheros/salida|1|1|$igual trabajo/enviados/X_01.txt, del original|ficheros/enviados,trabajo/enviados -> ficheros/salida") @($v['solo-el-segundo'])
  Igual 'fechas: un nombre por diferencia, la misma clave, y cada uno con su contenido' @("otraCarpeta|X_01.txt|en ficheros/enviados|en ficheros/salida|1|1|$igual ficheros/enviados/X_01.txt, del original|ficheros/enviados -> ficheros/salida", 'otraCarpeta|X_02.txt|en ficheros/enviados|en ficheros/salida|1|1|el contenido es distinto: la primera linea distinta, la 1: original [a]; migrado [b]|ficheros/enviados -> ficheros/salida') @($v['fechas'])
  Igual 'un fichero en la raiz del caso: (raiz)' @("otraCarpeta|X_01.txt|en (raiz)|en ficheros/salida|1|1|$igual X_01.txt, del original|(raiz) -> ficheros/salida") @($v['raiz'])
}

$Pruebas['m67 (a3) el mismo nombre en la misma carpeta se compara como hoy: contenido distinto es una diferencia de contenido, y solo la copia de otra carpeta sin pareja sigue siendo (no esta)'] = {
  $cuerpo = @'
Caso 'misma' @{ 'ficheros/salida/X_01.txt' = "a`n" } @{ 'ficheros/salida/X_01.txt' = "b`n" }
Caso 'iguales' @{ 'ficheros/salida/X_01.txt' = "a`n" } @{ 'ficheros/salida/X_01.txt' = "a`n" }
Caso 'misma-y-otra' @{ 'ficheros/salida/X_01.txt' = "a`n"; 'trabajo/X_01.txt' = "a`n" } @{ 'ficheros/salida/X_01.txt' = "b`n" }
Caso 'misma-y-otra-en-el-migrado' @{ 'ficheros/salida/X_01.txt' = "a`n" } @{ 'ficheros/salida/X_01.txt' = "a`n"; 'trabajo/X_01.txt' = "a`n" }
'@
  $v = Compara-M67 'm67-a3' $cuerpo
  Igual 'la misma carpeta, otro contenido: contenido, con la linea de cada lado y la clave del fichero' @('contenido|ficheros/salida/X_01.txt|a|b|1|1||ficheros/salida/X_01.txt') @($v['misma'])
  Igual 'la misma carpeta, igual: ninguna' @('(ninguna)') @($v['iguales'])
  Igual 'la misma y otra solo en el original: la de la misma carpeta, de contenido; la otra, falta, como hoy' @('contenido|ficheros/salida/X_01.txt|a|b|1|1||ficheros/salida/X_01.txt', 'falta|trabajo/X_01.txt|a|(no esta)|1|1||trabajo/X_01.txt') @($v['misma-y-otra'])
  Igual 'la misma y otra solo en el migrado: sobra, como hoy' @('sobra|trabajo/X_01.txt|(no esta)|a|1|1||trabajo/X_01.txt') @($v['misma-y-otra-en-el-migrado'])
}

$Pruebas['m67 (a4) un fichero que solo esta en un lado, sin otro con el mismo nombre en el otro, sigue saliendo (no esta); las tablas no se emparejan; con un .log tampoco'] = {
  $cuerpo = @'
Caso 'solo-original' @{ 'ficheros/salida/X_01.txt' = "a`n" } @{}
Caso 'solo-migrado' @{} @{ 'ficheros/salida/X_01.txt' = "a`n" }
Caso 'otros-nombres' @{ 'ficheros/enviados/X_01.txt' = "a`n" } @{ 'ficheros/salida/Y_01.txt' = "a`n" }
Caso 'dos-copias-solo-original' @{ 'ficheros/enviados/X_01.txt' = "a`n"; 'trabajo/enviados/X_01.txt' = "a`n" } @{}
Caso 'tablas' @{ 'tablas/T.csv' = "ID;NOMBRE`n1;ana`n" } @{ 'otra/T.csv' = "ID;NOMBRE`n1;ana`n" }
Caso 'logs' @{ 'trabajo/enviados/X_01.log' = "a`n" } @{ 'ficheros/salida/X_01.log' = "a`n" }
'@
  $v = Compara-M67 'm67-a4' $cuerpo
  Igual 'solo en el original: falta' @('falta|ficheros/salida/X_01.txt|a|(no esta)|1|1||ficheros/salida/X_01.txt') @($v['solo-original'])
  Igual 'solo en el migrado: sobra' @('sobra|ficheros/salida/X_01.txt|(no esta)|a|1|1||ficheros/salida/X_01.txt') @($v['solo-migrado'])
  Igual 'otro nombre en cada lado: una falta y una sobra, sueltas' @('falta|ficheros/enviados/X_01.txt|a|(no esta)|1|1||ficheros/enviados/X_01.txt', 'sobra|ficheros/salida/Y_01.txt|(no esta)|a|1|1||ficheros/salida/Y_01.txt') @($v['otros-nombres'])
  Igual 'dos copias solo en el original: dos faltas' @('falta|ficheros/enviados/X_01.txt|a|(no esta)|1|1||ficheros/enviados/X_01.txt', 'falta|trabajo/enviados/X_01.txt|a|(no esta)|1|1||trabajo/enviados/X_01.txt') @($v['dos-copias-solo-original'])
  Igual 'una tabla en otra carpeta no se empareja' @('sobra|otra/T.csv|(no esta)|ID;NOMBRE|2|1||otra/T.csv', 'falta|tablas/T.csv|ID;NOMBRE|(no esta)|2|1||tablas/T.csv') @($v['tablas'])
  Igual 'un .log (CompararIgnorar) no entra en la comparacion: ninguna' @('(ninguna)') @($v['logs'])
}

$Pruebas['m67 (a5) un .log que cada lado deja en otra carpeta, con CompararIgnorar por defecto: los casos salen iguales; con la lista vacia, salen distintos (una sola diferencia por caso)'] = {
  $e = Escenario-M67 'm67-a5' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M67 $e 'log'
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'el caso sale igual' 'igual' ((Resultados $e) -join ',')
  Igual 'sin ninguna diferencia' 0 (Difs-M67 $e 'caso-01').Count
  $e = Escenario-M67 'm67-a5b' ([ordered]@{ cargaJob = @('importe=10.00') }) @{ CompararIgnorar = @() }
  $r = Prueba-M67 $e 'log'
  Igual 'con CompararIgnorar vacio, sale con 2' 2 $r.Codigo
  $d = @(Difs-M67 $e 'caso-01')
  Igual 'con una sola diferencia, la del .log movido' 'CIERRE_2024_06_01.log|True' ($d[0].fichero + '|' + $d[0].otraCarpeta)
  Igual 'y es la unica' 1 $d.Count
}

$Pruebas['m67 (b1) los tres casos de (a1): un solo grupo de 3 casos con la pareja de carpetas en su firma, la cabecera con las carpetas de los dos lados y la linea de ayuda, una vez; un grupo de contenido no lleva la ayuda'] = {
  $e = Escenario-M67 'm67-b1' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00', 'importe=30.00') })
  $r = Prueba-M67 $e
  $j = Lee-Json $e.Json
  $g = @($j.grupos)
  Igual 'un grupo' 1 $g.Count
  Igual 'de fichero, con la pareja de carpetas y no el nombre en la firma' "fichero|${ClaveM67}:otraCarpeta" $g[0].firma
  Igual 'de los tres casos' 'cargaJob/caso-01,cargaJob/caso-02,cargaJob/caso-03' (@($g[0].casos) -join ',')
  Igual 'con la cabecera de las carpetas de cada lado' '3 casos distintos, el migrado deja sus ficheros en ficheros/salida y el original en ficheros/enviados y trabajo/enviados' $g[0].descripcion
  Igual 'cada caso apunta a su grupo' '1,1,1' (@($j.casos | ForEach-Object { $_.grupo }) -join ',')
  Comprueba 'la consola dice el grupo' ($r.Salida.Contains("Grupo 1: $($g[0].descripcion)")) (Cola $r.Salida)
  Igual 'y la linea de ayuda, una sola vez' 1 ([regex]::Matches($r.Salida, [regex]::Escape($AyudaM67))).Count
  $e = Escenario-M67 'm67-b1b' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M67 $e 'misma;contenido'
  Igual 'con el mismo fichero en la misma carpeta y otro contenido, sale con 2' 2 $r.Codigo
  Igual 'un grupo, de contenido' 'fichero|ficheros/salida/CIERRE_2024_06_01.txt:contenido' @((Lee-Json $e.Json).grupos)[0].firma
  Comprueba 'sin la linea de ayuda de carpetas' (-not $r.Salida.Contains('Suele ser el test del migrado')) (Cola $r.Salida)
}

$Pruebas['m67 (b2) prueba-local.json guarda el tipo nuevo; -Reparar con un caso asi: una clave (la pareja de carpetas) para los tres casos, una llamada, un commit y los tres iguales; con reparar-no, no se arregla y sin commit'] = {
  $e = Escenario-M67 'm67-b2' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00', 'importe=30.00') })
  $wt0 = GitEn $e.Wt @('rev-parse', 'HEAD')
  $r = Prueba-M67 $e '' @('-Reparar') 'reparar-arregla'
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'los tres casos salen iguales' 'igual,igual,igual' ((Resultados $e) -join ',')
  Igual 'una sola llamada para arreglar' 1 (Llamadas-Reparar $e).Count
  Igual 'un commit nuevo en la rama de rescate' 1 (GitEn $e.Wt @('rev-list', '--count', "$wt0..HEAD"))
  $rep = @(Reparaciones $e)
  Igual 'una reparacion, arreglada, con la pareja de carpetas por clave y los tres casos' "1|arreglado|$ClaveM67|3" "$($rep.Count)|$($rep[0].resultado)|$($rep[0].clave)|$($rep[0].casos)"
  $p = @(Registros-Reparar $e 1)[0]
  Comprueba 'el prompt dice el fichero y las carpetas de cada lado' ($p.Contains('CIERRE_2024_06_01.txt') -and $p.Contains($OrigM67) -and $p.Contains($MigM67)) $p
  $e = Escenario-M67 'm67-b2b' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $antes = Estado-Git $e.Wt
  $r = Prueba-M67 $e '' @('-Reparar') 'reparar-no'
  Igual 'con reparar-no, sale con 2' 2 $r.Codigo
  Igual 'sin commit nuevo' $antes (Estado-Git $e.Wt)
  $rep = @(Reparaciones $e)
  Igual 'la clave queda no se arregla, y es la pareja de carpetas' "no se arregla|$ClaveM67" "$($rep[0].resultado)|$($rep[0].clave)"
  $json = [System.IO.File]::ReadAllText($e.Json)
  Comprueba 'el json lleva el tipo nuevo' ($json -match '"otraCarpeta":\s*true') ''
}

$Pruebas['m67 (b3) Get-Grupos con otraCarpeta: la misma pareja de carpetas con nombres distintos es un grupo; otra pareja, otro; la cabecera dice las carpetas y, con mas ficheros, cuantos mas'] = {
  $f = Join-Path $Dir 'm67-grupos.ps1'
  $cuerpo = @'
$Inv = [System.Globalization.CultureInfo]::InvariantCulture
$RutasCopia = @()
$Hoy = @()
function Dif([string]$Fichero, [string]$Clave, [string]$Orig, [string]$Mig, [string[]]$CarpetasOrig = $null, [string[]]$CarpetasMig = $null) {
  $d = [ordered]@{ fichero = $Fichero; clave = $Clave; lineas = 1; linea = 1; original = $Orig; migrado = $Mig; nota = '' }
  if ($CarpetasOrig) { $d.otraCarpeta = $true; $d.carpetasOriginal = $CarpetasOrig; $d.carpetasMigrado = $CarpetasMig }
  return $d
}
function Caso-M([string]$Caso, $Dif) { [ordered]@{ job = 'cargaJob'; caso = $Caso; titulo = 't'; resultado = 'distinto'; motivo = ''; diferencias = @($Dif); fallos = @() } }
$par = 'ficheros/enviados -> ficheros/salida'
$res = @(
  (Caso-M 'caso-01' @((Dif 'CIERRE_2024_06_01.txt' $par 'en ficheros/enviados' 'en ficheros/salida' @('ficheros/enviados') @('ficheros/salida')))),
  (Caso-M 'caso-02' @((Dif 'CIERRE_2024_06_02.txt' $par 'en ficheros/enviados' 'en ficheros/salida' @('ficheros/enviados') @('ficheros/salida')))),
  (Caso-M 'caso-03' @((Dif 'CIERRE_2024_06_03.txt' 'ficheros/enviados,trabajo/enviados -> ficheros/salida' 'en ficheros/enviados y trabajo/enviados' 'en ficheros/salida' @('ficheros/enviados', 'trabajo/enviados') @('ficheros/salida')))),
  (Caso-M 'caso-04' @((Dif 'CIERRE_2024_06_04.txt' $par 'en ficheros/enviados' 'en ficheros/salida' @('ficheros/enviados') @('ficheros/salida')), (Dif 'otro.txt' 'ficheros/salida/otro.txt' 'x' 'y'))),
  (Caso-M 'caso-05' @((Dif 'CIERRE_2024_06_05.txt' $par 'en ficheros/enviados' 'en ficheros/salida' @('ficheros/enviados') @('ficheros/salida')), (Dif 'CIERRE_X.txt' 'a -> b' 'en a' 'en b' @('a') @('b'))))
)
foreach ($g in @(Get-Grupos $res)) { 'G ' + $g.numero + ' ## ' + $g.firma + ' ## ' + (@($g.casos) -join ',') + ' ## ' + $g.descripcion }
'@
  [System.IO.File]::WriteAllText($f, ((Texto-De-Funciones $Script @('Get-Grupos', 'Get-TipoDif', 'Format-Carpetas', 'Get-CausaNormal', 'Get-Normal', 'Format-Fallo', 'Sort-Ordinal')) + "`n" + $cuerpo))
  $r = Lanzar $f @()
  $g = @($r.Salida -split "`n" | Where-Object { $_ -cmatch '^G ' } | ForEach-Object { $_.TrimEnd().Substring(2) })
  Igual 'cuatro grupos' 4 $g.Count
  Igual '1: la misma pareja con nombres de otra fecha: 2 casos' "1 ## fichero|ficheros/enviados -> ficheros/salida:otraCarpeta ## cargaJob/caso-01,cargaJob/caso-02 ## 2 casos distintos, el migrado deja sus ficheros en ficheros/salida y el original en ficheros/enviados" $g[0]
  Igual '2: una pareja a -> b (la primera en orden ordinal) y otra: la cabecera es de la primera y cuenta el fichero mas' '2 ## fichero|a -> b:otraCarpeta|ficheros/enviados -> ficheros/salida:otraCarpeta ## cargaJob/caso-05 ## 1 caso distinto, el migrado deja sus ficheros en b y el original en a y 1 fichero mas' $g[1]
  Igual '3: la misma pareja que el 1 y ademas un fichero de contenido: otro grupo, con la cabecera de la pareja y el fichero mas' '3 ## fichero|ficheros/enviados -> ficheros/salida:otraCarpeta|ficheros/salida/otro.txt:contenido ## cargaJob/caso-04 ## 1 caso distinto, el migrado deja sus ficheros en ficheros/salida y el original en ficheros/enviados y 1 fichero mas' $g[2]
  Igual '4: otra pareja de carpetas, con dos del original' '4 ## fichero|ficheros/enviados,trabajo/enviados -> ficheros/salida:otraCarpeta ## cargaJob/caso-03 ## 1 caso distinto, el migrado deja sus ficheros en ficheros/salida y el original en ficheros/enviados y trabajo/enviados' $g[3]
}

# Una linea de lo que el prueba-local.json de antes decia de las carpetas: 'En N casos el original deja sus ficheros en A y el migrado en B: ...'
function Linea-M67([int]$N, [string]$Original, [string]$Migrado) {
  return "- En $N casos el original deja sus ficheros en $Original y el migrado en ${Migrado}: da a las propiedades de carpetas del test del migrado los mismos valores que les da el test del original."
}

# Deja en el prueba-local.json de $E los casos de $Parejas: lista de (cuantos casos, carpetas del original, carpetas del migrado y, si se pone, 'dos': el primer
# caso lleva ademas otro fichero de la misma pareja). Cada caso sale distinto, con su diferencia otraCarpeta.
function Anterior-M67($E, $Parejas) {
  $o = Lee-Json $E.Json
  $casos = @()
  $n = 0
  foreach ($p in $Parejas) {
    for ($i = 0; $i -lt $p[0]; $i++) {
      $n++
      $dif = @()
      foreach ($nombre in @("CIERRE_2024_06_$n.txt") + @(if ($i -eq 0 -and $p.Count -gt 3) { "OTRO_2024_06_$n.txt" })) {
        $dif += , [ordered]@{ fichero = $nombre; clave = (@($p[1]) -join ',') + ' -> ' + (@($p[2]) -join ','); lineas = 1; linea = 1; original = 'en ' + (@($p[1]) -join ' y '); migrado = 'en ' + (@($p[2]) -join ' y '); nota = ''; otraCarpeta = $true; carpetasOriginal = @($p[1]); carpetasMigrado = @($p[2]) }
      }
      $casos += , [ordered]@{ job = 'cargaJob'; caso = ('caso-' + $n.ToString('D2')); titulo = ''; resultado = 'distinto'; motivo = ''; diferencias = $dif; fallos = @() }
    }
  }
  $o.casos = $casos
  [System.IO.File]::WriteAllText($E.Json, (ConvertTo-Json -InputObject $o -Depth 20))
}

$Pruebas['m67 (c1) el prueba-local.json de antes con 3 casos de la misma pareja de carpetas (uno con dos ficheros de ella): sin -RehacerArnes, ni llamadas ni prompt nuevo; con -RehacerArnes, el primer intento del migrado lleva la linea, una vez, con 3 casos, y la huella no cambia'] = {
  $e = Escenario-M64 'm67-c1' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba $e
  Igual 'el primer lanzamiento sale con 0' 0 $r.Codigo
  $huella = (Tarea-Arnes $e 'migrado').entradas.huella
  Anterior-M67 $e @(, @(3, @('ficheros/enviados', 'trabajo/enviados'), @('ficheros/salida'), 'dos'))
  $llamadas = @(Llamadas-Arnes $e 'migrado').Count
  $r = Prueba $e
  Igual 'sin -RehacerArnes sale con 0' 0 $r.Codigo
  Igual 'sin llamadas nuevas del migrado' $llamadas @(Llamadas-Arnes $e 'migrado').Count
  Comprueba 'y el prompt de antes no lleva la linea' (-not (Registro-Arnes $e 'migrado' 1).Contains('el original deja sus ficheros')) ''
  Anterior-M67 $e @(, @(3, @('ficheros/enviados', 'trabajo/enviados'), @('ficheros/salida'), 'dos'))   # el lanzamiento de arriba lo ha pisado
  $r = Prueba $e @('-RehacerArnes')
  Igual 'con -RehacerArnes sale con 0' 0 $r.Codigo
  $mig = Registro-Arnes $e 'migrado' 1
  $linea = Linea-M67 3 'ficheros/enviados y trabajo/enviados' 'ficheros/salida'
  Comprueba 'el primer intento del migrado lleva la linea de los 3 casos (el caso con dos ficheros de la pareja cuenta una vez)' ($mig.Contains($linea)) (Cola $mig)
  Comprueba 'dentro del bloque de lo que fallo la otra vez, una sola vez' ($mig.Contains($M61Bloque) -and [regex]::Matches($mig, 'el original deja sus ficheros').Count -eq 1) (Cola $mig)
  Comprueba 'sin la frase de las causas de fallo (no hay ninguna)' (-not $mig.Contains($M64Frase)) (Cola $mig)
  Comprueba 'el del original no la lleva' (-not (Registro-Arnes $e 'original' 1).Contains('el original deja sus ficheros')) ''
  Comprueba 'la tarea del migrado guarda la linea en entradas.previo' ([string](Tarea-Arnes $e 'migrado').entradas.previo -match [regex]::Escape($linea)) ''
  Igual 'la huella del migrado no cambia' $huella (Tarea-Arnes $e 'migrado').entradas.huella
}

$Pruebas['m67 (c2) una pareja con un solo caso no sale; de las de 2 casos, las primeras por orden de firma, 3 lineas como mucho y la de mas casos primero; las carpetas se dicen con y; sin ninguna pareja repetida, el prompt no cambia'] = {
  $e = Escenario-M64 'm67-c2' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba $e
  Igual 'el primer lanzamiento sale con 0' 0 $r.Codigo
  Anterior-M67 $e @(@(1, @('g'), @('h')), @(2, @('e'), @('f')), @(2, @('c'), @('d')), @(3, @('ficheros/enviados', 'trabajo/enviados'), @('ficheros/salida')), @(2, @('a'), @('b')))
  $r = Prueba $e @('-RehacerArnes')
  Igual 'con -RehacerArnes sale con 0' 0 $r.Codigo
  $mig = Registro-Arnes $e 'migrado' 1
  $l3 = Linea-M67 3 'ficheros/enviados y trabajo/enviados' 'ficheros/salida'
  $lab = Linea-M67 2 'a' 'b'
  $lcd = Linea-M67 2 'c' 'd'
  Comprueba 'la de 3 casos' ($mig.Contains($l3)) (Cola $mig)
  Comprueba 'las de 2 casos, a -> b y c -> d, por orden de firma' ($mig.Contains($lab) -and $mig.Contains($lcd) -and $mig.IndexOf($lab) -lt $mig.IndexOf($lcd)) (Cola $mig)
  Comprueba 'la de mas casos va antes' ($mig.IndexOf($l3) -lt $mig.IndexOf($lab)) (Cola $mig)
  Comprueba 'tres lineas en total: la tercera pareja de 2 casos (e -> f) y la de un caso (g -> h) no salen' ([regex]::Matches($mig, 'el original deja sus ficheros').Count -eq 3 -and -not $mig.Contains('en e y el migrado') -and -not $mig.Contains('en g y el migrado')) (Cola $mig)
  $e = Escenario-M64 'm67-c2b' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba $e
  Anterior-M67 $e @(@(1, @('a'), @('b')), @(1, @('c'), @('d')))
  $r = Prueba $e @('-RehacerArnes')
  Igual 'con dos parejas de un solo caso sale con 0' 0 $r.Codigo
  Comprueba 'el prompt del migrado no lleva ni el bloque de lo que fallo la otra vez' (-not (Registro-Arnes $e 'migrado' 1).Contains($M61Bloque)) ''
}

# ===================== M73: lo que hoy da 'distinto' sin serlo (SQL que ya existe, horas en rutas, Excel y binarios) =====================
# Escenarios con el Copilot de m40 y el Maven de m73 (tests/falsos/m73-mvn.ps1, sobre el de m68; sus banderas, en RESCATE_M73). Los datos son inventados.

function Escenario-M73([string]$Nombre, $Casos, [hashtable]$Mas = @{}) {
  $aj = @{ MvnExe = (Join-Path $falsos 'm73-mvn.ps1') }
  foreach ($k in $Mas.Keys) { $aj[$k] = $Mas[$k] }
  return (Escenario-M68 $Nombre $Casos $aj)
}

# Lanza con las banderas $Banderas del Maven falso de m73 (RESCATE_M73) y la base de los tests $Tablas (RESCATE_M40, como Prueba-M68).
function Prueba-M73($E, [string]$Banderas = '', [string]$Tablas = '', [string[]]$A = @()) {
  $env:RESCATE_M73 = $Banderas
  try { return (Prueba-M68 $E '' $Tablas $A) }
  finally { $env:RESCATE_M73 = '' }
}

# Edit-DatosSql sobre un fichero por cada texto de $Textos (en Latin-1, byte a byte): devuelve, por cada uno, @(el texto que queda en el fichero, 'si' si devuelve los bytes de antes).
function EditaSql-M73([string]$Nombre, [string[]]$Textos) {
  $latin = [System.Text.Encoding]::GetEncoding(28591)
  $d = Join-Path $Dir $Nombre
  [void](New-Item -ItemType Directory -Path $d -Force)
  for ($i = 0; $i -lt $Textos.Count; $i++) { [System.IO.File]::WriteAllBytes((Join-Path $d "c$i.sql"), $latin.GetBytes($Textos[$i])) }
  $f = Join-Path $Dir "$Nombre.ps1"
  $cabeza = @'
param([string]$Carpeta)
$Latin = [System.Text.Encoding]::GetEncoding(28591)
'@
  $cuerpo = @'
foreach ($f in @(Get-ChildItem -LiteralPath $Carpeta -Filter 'c*.sql')) {
  $antes = Edit-DatosSql $f.FullName
  $d = ''
  if ($null -ne $antes) { $d = 'si:' + $Latin.GetString($antes) }
  [System.IO.File]::WriteAllText($f.FullName + '.antes', $d, $Latin)
}
'@
  [System.IO.File]::WriteAllText($f, ($cabeza + "`n" + (Texto-De-Funciones $Script @('Edit-DatosSql', 'Get-MascaraSql')) + "`n" + $cuerpo))
  $r = Lanzar $f @($d)
  $v = @()
  for ($i = 0; $i -lt $Textos.Count; $i++) {
    $ruta = Join-Path $d "c$i.sql"
    $v += , @($latin.GetString([System.IO.File]::ReadAllBytes($ruta)), [System.IO.File]::ReadAllText($ruta + '.antes', $latin))
  }
  return $v
}

# Comprueba que cada par @(entrada, esperada) de $Pares sale de Edit-DatosSql como se espera y que los bytes de antes se devuelven solo si algo cambio y son los de la entrada.
function Comprueba-Sql-M73([string]$Nombre, $Pares) {
  $v = EditaSql-M73 $Nombre @($Pares | ForEach-Object { $_[0] })
  for ($i = 0; $i -lt $Pares.Count; $i++) {
    $q = ($Pares[$i][0] -replace "`r", '\r' -replace "`n", '\n')
    Igual "[$i] $q" $Pares[$i][1] $v[$i][0]
    $cambia = $Pares[$i][0] -cne $Pares[$i][1]
    Igual "[$i] devuelve los bytes de antes solo si cambia" $(if ($cambia) { 'si:' + $Pares[$i][0] } else { '' }) $v[$i][1]
  }
}

$Pruebas['m73 (a1) CREATE SEQUENCE, CREATE UNIQUE INDEX, CREATE SCHEMA, ADD CONSTRAINT y ADD COLUMN llevan IF NOT EXISTS en lo que se ejecuta: en mayusculas, en minusculas y en varias lineas'] = {
  $pares = @(
    @('CREATE SEQUENCE X', 'CREATE SEQUENCE IF NOT EXISTS X'),
    @('create sequence x start with 1 increment by 50;', 'create sequence IF NOT EXISTS x start with 1 increment by 50;'),
    @("CREATE`r`n  SEQUENCE`n  BATCH_STEP_EXECUTION_SEQ`n  START WITH 1;", "CREATE`r`n  SEQUENCE`n  IF NOT EXISTS BATCH_STEP_EXECUTION_SEQ`n  START WITH 1;"),
    @('CREATE UNIQUE INDEX I ON T(C)', 'CREATE UNIQUE INDEX IF NOT EXISTS I ON T(C)'),
    @('create unique index i on t (c);', 'create unique index IF NOT EXISTS i on t (c);'),
    @('CREATE INDEX I ON T(C)', 'CREATE INDEX IF NOT EXISTS I ON T(C)'),
    @('CREATE HASH INDEX I ON T(C)', 'CREATE HASH INDEX IF NOT EXISTS I ON T(C)'),
    @('CREATE UNIQUE HASH INDEX S.I ON T(C)', 'CREATE UNIQUE HASH INDEX IF NOT EXISTS S.I ON T(C)'),
    @('CREATE SPATIAL INDEX I ON T(C)', 'CREATE SPATIAL INDEX IF NOT EXISTS I ON T(C)'),
    @("create`n  unique`n  index`n  i`n  on t(c);", "create`n  unique`n  index`n  IF NOT EXISTS i`n  on t(c);"),
    @('CREATE SCHEMA S', 'CREATE SCHEMA IF NOT EXISTS S'),
    @('create schema s authorization sa;', 'create schema IF NOT EXISTS s authorization sa;'),
    @("CREATE SCHEMA`n  S;", "CREATE SCHEMA`n  IF NOT EXISTS S;"),
    @('ALTER TABLE T ADD CONSTRAINT K FOREIGN KEY (C) REFERENCES P(ID)', 'ALTER TABLE T ADD CONSTRAINT IF NOT EXISTS K FOREIGN KEY (C) REFERENCES P(ID)'),
    @('alter table t add constraint k unique (c);', 'alter table t add constraint IF NOT EXISTS k unique (c);'),
    @("ALTER TABLE T`n  ADD CONSTRAINT`n  K PRIMARY KEY (C)", "ALTER TABLE T`n  ADD CONSTRAINT`n  IF NOT EXISTS K PRIMARY KEY (C)"),
    @('ALTER TABLE IF EXISTS S.T ADD CONSTRAINT K CHECK (C > 0)', 'ALTER TABLE IF EXISTS S.T ADD CONSTRAINT IF NOT EXISTS K CHECK (C > 0)'),
    @('ALTER TABLE T ADD COLUMN C INT', 'ALTER TABLE T ADD COLUMN IF NOT EXISTS C INT'),
    @('alter table s.t add column c varchar(10) not null;', 'alter table s.t add column IF NOT EXISTS c varchar(10) not null;'),
    @('ALTER TABLE T ADD C INT', 'ALTER TABLE T ADD IF NOT EXISTS C INT'),
    @("ALTER TABLE T`n  ADD`n  COLUMN`n  C INT;", "ALTER TABLE T`n  ADD`n  COLUMN`n  IF NOT EXISTS C INT;"),
    @('ALTER TABLE IF EXISTS T ADD COLUMN C INT', 'ALTER TABLE IF EXISTS T ADD COLUMN IF NOT EXISTS C INT'),
    @('create sequence A; create sequence B; alter table T add column D int;', 'create sequence IF NOT EXISTS A; create sequence IF NOT EXISTS B; alter table T add column IF NOT EXISTS D int;')
  )
  Comprueba-Sql-M73 'm73-a1' $pares
}

$Pruebas['m73 (a1b) el resto de lo que acepta IF NOT EXISTS en las tres gramaticas de H2 (1.4.193, 1.4.200 y 2.x): tablas con modificadores, vistas, roles, usuarios, constantes, dominios, alias, agregados, triggers y tablas enlazadas'] = {
  $pares = @(
    @('CREATE TABLE T (ID INT)', 'CREATE TABLE IF NOT EXISTS T (ID INT)'),
    @('CREATE CACHED TABLE T (ID INT)', 'CREATE CACHED TABLE IF NOT EXISTS T (ID INT)'),
    @('create memory table t (id int)', 'create memory table IF NOT EXISTS t (id int)'),
    @('CREATE GLOBAL TEMPORARY TABLE T (ID INT)', 'CREATE GLOBAL TEMPORARY TABLE IF NOT EXISTS T (ID INT)'),
    @('CREATE LOCAL TEMPORARY TABLE T (ID INT)', 'CREATE LOCAL TEMPORARY TABLE IF NOT EXISTS T (ID INT)'),
    @('CREATE TEMP TABLE T (ID INT)', 'CREATE TEMP TABLE IF NOT EXISTS T (ID INT)'),
    @('CREATE MEMORY TEMPORARY TABLE T (ID INT)', 'CREATE MEMORY TEMPORARY TABLE IF NOT EXISTS T (ID INT)'),
    @("CREATE FORCE LINKED TABLE T('org.h2.Driver', 'jdbc:h2:mem:x', 'sa', '', 'P')", "CREATE FORCE LINKED TABLE IF NOT EXISTS T('org.h2.Driver', 'jdbc:h2:mem:x', 'sa', '', 'P')"),
    @('CREATE VIEW V AS SELECT 1 FROM DUAL', 'CREATE VIEW IF NOT EXISTS V AS SELECT 1 FROM DUAL'),
    @('create force view v as select 1 from dual', 'create force view IF NOT EXISTS v as select 1 from dual'),
    @('CREATE ROLE R', 'CREATE ROLE IF NOT EXISTS R'),
    @("CREATE USER U PASSWORD 'p'", "CREATE USER IF NOT EXISTS U PASSWORD 'p'"),
    @('CREATE CONSTANT K VALUE 1', 'CREATE CONSTANT IF NOT EXISTS K VALUE 1'),
    @('CREATE DOMAIN D AS INT', 'CREATE DOMAIN IF NOT EXISTS D AS INT'),
    @('CREATE ALIAS A FOR "com.acme.Util.f"', 'CREATE ALIAS IF NOT EXISTS A FOR "com.acme.Util.f"'),
    @('CREATE AGGREGATE G FOR "com.acme.Media"', 'CREATE AGGREGATE IF NOT EXISTS G FOR "com.acme.Media"'),
    @('CREATE TRIGGER TR AFTER INSERT ON T CALL "com.acme.Disparo"', 'CREATE TRIGGER IF NOT EXISTS TR AFTER INSERT ON T CALL "com.acme.Disparo"')
  )
  Comprueba-Sql-M73 'm73-a1b' $pares
}

$Pruebas['m73 (a2) lo que ya lleva IF NOT EXISTS no cambia (ni en mayusculas, minusculas o espacios de mas); tampoco lo que no lo acepta en alguna gramatica ni lo que va en un comentario o un texto; lo demas del fichero queda byte a byte'] = {
  $enie = [string][char]0xF1 + 'and' + [char]0xFA
  $pares = @(
    @('CREATE SEQUENCE IF NOT EXISTS X', 'CREATE SEQUENCE IF NOT EXISTS X'),
    @('create   index  if  not  exists  i on t(c)', 'create   index  if  not  exists  i on t(c)'),
    @("CREATE SCHEMA`n  IF NOT EXISTS`n  S", "CREATE SCHEMA`n  IF NOT EXISTS`n  S"),
    @('ALTER TABLE T ADD COLUMN IF NOT EXISTS C INT', 'ALTER TABLE T ADD COLUMN IF NOT EXISTS C INT'),
    @('ALTER TABLE T ADD IF NOT EXISTS C INT', 'ALTER TABLE T ADD IF NOT EXISTS C INT'),
    @('alter table t add constraint  if not exists  k unique (c)', 'alter table t add constraint  if not exists  k unique (c)'),
    @('CREATE TABLE IF NOT EXISTS T (ID INT)', 'CREATE TABLE IF NOT EXISTS T (ID INT)'),
    @('CREATE OR REPLACE VIEW V AS SELECT 1 FROM DUAL', 'CREATE OR REPLACE VIEW V AS SELECT 1 FROM DUAL'),
    @('CREATE OR REPLACE FORCE VIEW V AS SELECT 1 FROM DUAL', 'CREATE OR REPLACE FORCE VIEW V AS SELECT 1 FROM DUAL'),
    @('CREATE INDEX ON T(C)', 'CREATE INDEX ON T(C)'),
    @('create unique index on t(c)', 'create unique index on t(c)'),
    @('CREATE PRIMARY KEY ON T(C)', 'CREATE PRIMARY KEY ON T(C)'),
    @('CREATE SCHEMA AUTHORIZATION SA', 'CREATE SCHEMA AUTHORIZATION SA'),
    @('CREATE MATERIALIZED VIEW V AS SELECT 1 FROM DUAL', 'CREATE MATERIALIZED VIEW V AS SELECT 1 FROM DUAL'),
    @('ALTER TABLE T ADD PRIMARY KEY (C)', 'ALTER TABLE T ADD PRIMARY KEY (C)'),
    @('ALTER TABLE T ADD UNIQUE (C)', 'ALTER TABLE T ADD UNIQUE (C)'),
    @('ALTER TABLE T ADD FOREIGN KEY (C) REFERENCES P(ID)', 'ALTER TABLE T ADD FOREIGN KEY (C) REFERENCES P(ID)'),
    @('ALTER TABLE T ADD CHECK (C > 0)', 'ALTER TABLE T ADD CHECK (C > 0)'),
    @('ALTER TABLE T ADD (A INT, B INT)', 'ALTER TABLE T ADD (A INT, B INT)'),
    @('ALTER TABLE T ADD COLUMN (A INT, B INT)', 'ALTER TABLE T ADD COLUMN (A INT, B INT)'),
    @('ALTER TABLE T ALTER COLUMN C INT', 'ALTER TABLE T ALTER COLUMN C INT'),
    @('ALTER TABLE T DROP COLUMN C', 'ALTER TABLE T DROP COLUMN C'),
    @('-- CREATE SEQUENCE X', '-- CREATE SEQUENCE X'),
    @("-- no es la de 'ayer'`nCREATE SEQUENCE X", "-- no es la de 'ayer'`nCREATE SEQUENCE IF NOT EXISTS X"),
    @('/* CREATE TABLE T (ID INT); ALTER TABLE T ADD COLUMN C INT */', '/* CREATE TABLE T (ID INT); ALTER TABLE T ADD COLUMN C INT */'),
    @("INSERT INTO LOG VALUES ('CREATE SEQUENCE X; ALTER TABLE T ADD COLUMN C INT')", "INSERT INTO LOG VALUES ('CREATE SEQUENCE X; ALTER TABLE T ADD COLUMN C INT')"),
    @("INSERT INTO LOG VALUES ('it''s: CREATE TABLE T'); CREATE SEQUENCE X", "INSERT INTO LOG VALUES ('it''s: CREATE TABLE T'); CREATE SEQUENCE IF NOT EXISTS X"),
    @('CREATE ALIAS A AS $$ String f() { return "CREATE SEQUENCE X"; } $$', 'CREATE ALIAS IF NOT EXISTS A AS $$ String f() { return "CREATE SEQUENCE X"; } $$'),
    @("CREATE /* a */ SEQUENCE /* b */ X", "CREATE /* a */ SEQUENCE /* b */ IF NOT EXISTS X"),
    @("insert into T values ('$enie')`r`ncreate sequence S;`r`n", "insert into T values ('$enie')`r`ncreate sequence IF NOT EXISTS S;`r`n"),
    @('', '')
  )
  Comprueba-Sql-M73 'm73-a2' $pares
}

$Pruebas['m73 (a3) un caso hecho de antes cuyo original guardo que una secuencia, un indice, un esquema, una vista, una restriccion o una columna ya existe (en espanol, en ingles o solo con el codigo) se ejecuta otra vez; los demas errores, no'] = {
  $casos = @(1..16 | ForEach-Object { 'importe=' + $_ + '0.00' })
  $e = Escenario-M73 'm73-a3' ([ordered]@{ cargaJob = $casos })
  $r = Prueba-M73 $e
  Igual 'el primer lanzamiento sale con 0' 0 $r.Codigo
  $llamadas = (Llamadas $e).Count
  $h2 = 'org.h2.jdbc.JdbcSQLSyntaxErrorException: '
  $dicen = @{
    1  = @($true, ($h2 + 'Sequence "BATCH_STEP_EXECUTION_SEQ" already exists; SQL statement: CREATE SEQUENCE BATCH_STEP_EXECUTION_SEQ [90035-200]'))
    2  = @($true, ($h2 + 'Sequence "BATCH_STEP_EXECUTION_SEQ" ya existe; Sentencia SQL: CREATE SEQUENCE BATCH_STEP_EXECUTION_SEQ [90035-200]'))
    3  = @($true, ($h2 + '[90035-200]'))
    4  = @($true, ($h2 + 'Indice "IX_A" ya existe; Sentencia SQL: CREATE UNIQUE INDEX IX_A ON T_A(ID) [42111-200]'))
    5  = @($true, ($h2 + 'Index "IX_A" already exists [42111-200]'))
    6  = @($true, ($h2 + 'Schema "S_A" already exists'))
    7  = @($true, ($h2 + 'View "V_A" ya existe; Sentencia SQL: CREATE VIEW V_A AS SELECT 1 FROM DUAL'))
    8  = @($true, ($h2 + 'Constraint "K_A" already exists; SQL statement: ALTER TABLE T_A ADD CONSTRAINT K_A UNIQUE (ID) [90045-200]'))
    9  = @($true, ($h2 + 'Nombre de columna Duplicada "COL_X"; Sentencia SQL: ALTER TABLE T_A ADD COLUMN COL_X INT [42121-200]'))
    10 = @($true, ("Failed to execute SQL script statement #1: ALTER TABLE T_A ADD COLUMN COL_X INT; nested exception is " + $h2 + 'Duplicate column name "COL_X" [42121-200]'))
    11 = @($true, ($h2 + 'Role "R_A" already exists [90069-200]; User "U_A" ya existe [90033-200]; Trigger "TR_A" ya existe [90041-200]; Constant "K" ya existe [90114-200]; Function alias "A" already exists [90076-200]; Domain "D" ya existe [90119-200]'))
    12 = @($false, ($h2 + 'Duplicate column name "C"; SQL statement: CREATE TABLE T_A (C INT, C INT) [42121-200]'))
    13 = @($false, ($h2 + 'Tabla "T_A" no encontrada; Sentencia SQL: SELECT * FROM T_A [42102-200]'))
    14 = @($false, ('Se han tratado 1190035 filas y el codigo 420112 no es un error de H2'))
    15 = @($false, ('java.lang.NullPointerException'))
  }
  foreach ($n in $dicen.Keys) { Escribe $e.Local ('salidas/original/cargaJob/caso-' + $n.ToString('D2') + '/error.txt') ($dicen[$n][1] + "`n") }
  $r = Prueba-M73 $e
  Igual 'el segundo lanzamiento sale con 0' 0 $r.Codigo
  Igual 'sin llamadas nuevas a Copilot' $llamadas (Llamadas $e).Count
  $esperado = @(1..16 | ForEach-Object { if ($dicen.ContainsKey($_) -and $dicen[$_][0]) { '5' } else { '3' } }) -join ','
  $despues = @(1..16 | ForEach-Object { Orig-Mvn $e 'cargaJob' ('caso-' + $_.ToString('D2')) }) -join ','
  Igual 'los once con el error se ejecutan otra vez (original y original-2) y los demas, no' $esperado $despues
  Comprueba 'la consola dice cuantos' ($r.Salida -match 'Se ejecuta otra vez el original de 11 caso\(s\)') (Cola $r.Salida)
  Comprueba 'y que es porque su error.txt dice que algo ya existe (no solo una tabla)' ($r.Salida -match 'dice que algo ya existe') (Cola $r.Salida)
}

$Pruebas['m73 (a3b) $PatronYaExiste: cada codigo de H2 de algo que ya existe se reconoce por si solo, y la columna repetida solo con un ALTER TABLE'] = {
  $texto = [System.IO.File]::ReadAllText($Script)
  foreach ($v in @('CodigosYaExiste', 'ColumnaRepetida', 'PatronYaExiste')) {
    $l = [regex]::Match($texto, '(?m)^\$' + $v + ' = .*$')
    Comprueba "$v esta definido en una linea" $l.Success ''
    Invoke-Expression $l.Value
  }
  foreach ($c in @(42101, 42111, 90033, 90035, 90038, 90041, 90045, 90069, 90076, 90078, 90114, 90119)) { Comprueba "el codigo $c, solo" ("[$c-200]" -match $PatronYaExiste) '' }
  Comprueba 'ya existe, solo' ('Tabla "T" ya existe' -match $PatronYaExiste) ''
  Comprueba 'already exists, solo' ('Table "T" already exists' -match $PatronYaExiste) ''
  Comprueba 'un codigo pegado a otras cifras no cuenta' (-not ('1190035 y 420112' -match $PatronYaExiste)) ''
  foreach ($c in @('Duplicate column name "C"', 'Nombre de columna Duplicada "C"', '[42121-200]')) {
    Comprueba "con ALTER TABLE: $c" (("ALTER TABLE T ADD COLUMN C INT; $c") -match $PatronYaExiste) ''
    Comprueba "sin ALTER TABLE: $c" (-not (("CREATE TABLE T (C INT, C INT); $c") -match $PatronYaExiste)) ''
  }
}

$Pruebas['m73 (a4) un datos.sql que crea una secuencia, un indice, un esquema y una columna que la base ya tiene: el caso corre en el original y en el migrado, y lo guardado en casos no cambia'] = {
  $sql = 'create sequence BATCH_STEP_EXECUTION_SEQ start with 1; create unique index IX_A on T_A(ID); alter table T_A add column COL_X int; create schema S_A; alter table T_A add constraint K_A unique (ID)'
  $e = Escenario-M73 'm73-a4' ([ordered]@{ cargaJob = @("importe=10.00 | SQL $sql") })
  $r = Prueba-M73 $e 'ya=BATCH_STEP_EXECUTION_SEQ,IX_A,COL_X,S_A,K_A' 'tablas=1/CALENDARIO_02'
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'el caso sale igual' 'igual' ((Resultados $e) -join ',')
  Comprueba 'el original no deja error.txt' (-not (Test-Path -LiteralPath (Get-Ruta $e.Local 'salidas/original/cargaJob/caso-01/error.txt'))) ''
  $con = 'cargaJob/caso-01|create sequence IF NOT EXISTS BATCH_STEP_EXECUTION_SEQ start with 1; create unique index IF NOT EXISTS IX_A on T_A(ID); alter table T_A add column IF NOT EXISTS COL_X int; create schema IF NOT EXISTS S_A; alter table T_A add constraint IF NOT EXISTS K_A unique (ID)'
  Igual 'el original vio las cinco sentencias con IF NOT EXISTS en sus tres ejecuciones' 3 @(Sql-M68 $e $e.CopiaOrig | Where-Object { $_ -ceq $con }).Count
  Igual 'y el migrado, en la suya' 1 @(Sql-M68 $e $e.CopiaMig | Where-Object { $_ -ceq $con }).Count
  Igual 'lo guardado en casos no cambia' $sql (Lee $e.Local 'casos/cargaJob/caso-01/datos.sql').Trim()
  $rel = 'src/test/resources/prueba-local/cargaJob/caso-01/datos.sql'
  Igual 'ni lo que queda en la copia del original' $sql (Lee $e.CopiaOrig $rel).Trim()
  Igual 'ni en la copia del migrado' $sql (Lee $e.CopiaMig $rel).Trim()
  $e = Escenario-M73 'm73-a4b' ([ordered]@{ cargaJob = @("importe=10.00 | SQL $sql") })
  $r = Prueba-M73 $e 'ya=BATCH_STEP_EXECUTION_SEQ,IX_A,COL_X,S_A,K_A;en' 'tablas=1/CALENDARIO_02'
  Igual 'con los mensajes de H2 en ingles tambien sale con 0' 0 $r.Codigo
}

# Un script con Get-Normal y lo de comparar que, con el dia 2026-11-22 como el de la ejecucion ($Hoy), por cada 'Caso <id> @{ carpeta/fichero = contenido } @{ ... }' de $Cuerpo (el original
# y el migrado) escribe una linea 'R <id> <tipo>|<fichero>|<original>|<migrado>|<lineas>|<linea>|<nota>|<clave>' por diferencia (Get-TipoDif), o 'R <id> (ninguna)'. Un contenido que es un
# [byte[]] se escribe tal cual: los de $Bin (nombre -> bytes) se escriben aparte y el script los lee con Bin '<nombre>'. Devuelve id -> sus lineas.
function Compara-M73([string]$Nombre, [string]$Cuerpo, [hashtable]$Bin = @{}) {
  $f = Join-Path $Dir "$Nombre.ps1"
  $cabeza = @'
param([string]$Raiz, [string]$BinDir)
$Inv = [System.Globalization.CultureInfo]::InvariantCulture
$Utf8Estricto = New-Object System.Text.UTF8Encoding($false, $true)
$RutasCopia = @()
$Hoy = @([datetime]'2026-11-22')
$Cfg = @{ CompararIgnorar = @('*.log') }
Add-Type -AssemblyName System.IO.Compression
function Bin([string]$N) { return , [System.IO.File]::ReadAllBytes((Join-Path $BinDir $N)) }
function Caso([string]$Id, [hashtable]$A, [hashtable]$B) {
  $dirs = @{}
  foreach ($x in @(@('A', $A), @('B', $B))) {
    $d = Join-Path (Join-Path $Raiz $Id) $x[0]
    [void](New-Item -ItemType Directory -Path $d -Force)
    foreach ($k in $x[1].Keys) {
      $p = Join-Path $d $k
      [void](New-Item -ItemType Directory -Path (Split-Path $p -Parent) -Force)
      if ($x[1][$k] -is [byte[]]) { [System.IO.File]::WriteAllBytes($p, $x[1][$k]) } else { [System.IO.File]::WriteAllText($p, $x[1][$k]) }
    }
    $dirs[$x[0]] = $d
  }
  $dif = @(Compare-Caso $dirs.A $dirs.B)
  $dif = @(Join-OtraCarpeta $dif $dirs.A $dirs.B)
  foreach ($d in $dif) { 'R ' + $Id + ' ' + (Get-TipoDif $d) + '|' + $d.fichero + '|' + $d.original + '|' + $d.migrado + '|' + $d.lineas + '|' + $d.linea + '|' + $d.nota + '|' + $d.clave }
  if ($dif.Count -eq 0) { 'R ' + $Id + ' (ninguna)' }
}
'@
  $comun = Join-Path (Split-Path -Parent $Script) 'comun.ps1'
  [System.IO.File]::WriteAllText($f, ($cabeza + "`n" + (Texto-De-Funciones $Script $FnComparaM73) + "`n" + (Texto-De-Funciones $comun @('Get-Rel', 'Join-Ruta')) + "`n" + '$Latin = [System.Text.Encoding]::GetEncoding(28591); $Utf8 = New-Object System.Text.UTF8Encoding($false)' + "`n" + $Cuerpo))
  $bd = Join-Path $Dir ($Nombre + '-bin')
  [void](New-Item -ItemType Directory -Path $bd -Force)
  foreach ($k in $Bin.Keys) { [System.IO.File]::WriteAllBytes((Join-Path $bd $k), [byte[]]$Bin[$k]) }
  $r = Lanzar $f @((Join-Path $Dir ($Nombre + '-dirs')), $bd)
  $v = [ordered]@{}
  foreach ($l in @($r.Salida -split "`n")) {
    if ($l -cmatch '^R (\S+) (.*)$') { $id = $Matches[1]; if (-not $v.Contains($id)) { $v[$id] = @() }; $v[$id] += $Matches[2].TrimEnd() }
  }
  if ($v.Count -eq 0) { Comprueba "${Nombre}: el script da alguna linea R" $false (Cola $r.Salida) }
  return $v
}
# Las funciones del script que necesita Compara-M73.
$FnComparaM73 = (@('Compare-Caso', 'Join-OtraCarpeta', 'New-DifOtraCarpeta', 'Get-TipoDif', 'Format-Carpetas', 'Compare-Fichero') + $FnLeer + @('Sort-Tabla', 'Resolve-ParTablas', 'Sort-Ordinal', 'Get-Normal', 'Get-Legible', 'Get-NotaJdk', 'Test-Ignorado'))

# Get-Normal del dia 2026-11-22 sobre cada texto de $Textos (uno por linea, sin saltos): devuelve lo que sale, en el mismo orden.
function Normaliza-M73([string]$Nombre, [string[]]$Textos) {
  $f = Join-Path $Dir "$Nombre.ps1"
  $cabeza = @'
param([string]$Entrada)
$Inv = [System.Globalization.CultureInfo]::InvariantCulture
$RutasCopia = @()
$Hoy = @([datetime]'2026-11-22')
'@
  $cuerpo = @'
foreach ($l in [System.IO.File]::ReadAllLines($Entrada)) { 'N ' + (Get-Normal $l) }
'@
  $en = Join-Path $Dir "$Nombre.txt"
  [System.IO.File]::WriteAllLines($en, $Textos)
  [System.IO.File]::WriteAllText($f, ($cabeza + "`n" + (Texto-De-Funciones $Script @('Get-Normal')) + "`n" + $cuerpo))
  $r = Lanzar $f @($en)
  return @(@($r.Salida -split "`n") | Where-Object { $_ -cmatch '^N ' } | ForEach-Object { $_.Substring(2).TrimEnd("`r") })
}

$Pruebas['m73 (b1) la misma fecha de hoy con hora en una carpeta del original y del migrado, con otra hora cada uno (informes/<hoy>-10-26-58/ y informes/<hoy>-10-31-07/): se emparejan por su clave y, con el mismo contenido, salen iguales; con otro, distintos'] = {
  $cuerpo = @'
Caso 'igual' @{ 'informes/2026-11-22-10-26-58/resumen.txt' = "importe;10`n" } @{ 'informes/2026-11-22-10-31-07/resumen.txt' = "importe;10`n" }
Caso 'distinto' @{ 'informes/2026-11-22-10-26-58/resumen.txt' = "importe;10`n" } @{ 'informes/2026-11-22-10-31-07/resumen.txt' = "importe;11`n" }
Caso 'dos-ejecuciones' @{ 'informes/2026-11-22-10-26-58/r.txt' = "a`n"; 'informes/2026-11-22-10-27-00/r.txt' = "b`n" } @{ 'informes/2026-11-22-10-31-07/r.txt' = "a`n"; 'informes/2026-11-22-10-31-09/r.txt' = "b`n" }
Caso 'dos-una-distinta' @{ 'informes/2026-11-22-10-26-58/r.txt' = "a`n"; 'informes/2026-11-22-10-27-00/r.txt' = "b`n" } @{ 'informes/2026-11-22-10-31-07/r.txt' = "a`n"; 'informes/2026-11-22-10-31-09/r.txt' = "c`n" }
Caso 'dos-y-una' @{ 'informes/2026-11-22-10-26-58/r.txt' = "a`n"; 'informes/2026-11-22-10-27-00/r.txt' = "a`n" } @{ 'informes/2026-11-22-10-31-07/r.txt' = "a`n" }
'@
  $v = Compara-M73 'm73-b1' $cuerpo
  Igual 'el mismo contenido en las dos carpetas con hora: ninguna diferencia' @('(ninguna)') @($v['igual'])
  Igual 'otro contenido: una de contenido, con la ruta del original y la clave normalizada' @('contenido|informes/2026-11-22-10-26-58/resumen.txt|importe;10|importe;11|1|1||informes/<hoy:yyyy-MM-dd><hora>/resumen.txt') @($v['distinto'])
  Igual 'dos carpetas con hora en cada lado: se emparejan por orden y salen iguales' @('(ninguna)') @($v['dos-ejecuciones'])
  Igual 'dos carpetas con hora en cada lado y la segunda distinta: una sola diferencia, la de la segunda' @('contenido|informes/2026-11-22-10-27-00/r.txt|b|c|1|1||informes/<hoy:yyyy-MM-dd><hora>/r.txt') @($v['dos-una-distinta'])
  Igual 'dos en el original y una en el migrado: la que sobra en el original, falta' @('falta|informes/2026-11-22-10-27-00/r.txt|a|(no esta)|1|1||informes/<hoy:yyyy-MM-dd><hora>/r.txt') @($v['dos-y-una'])
}

$Pruebas['m73 (b2) la hora de hoy con cualquier separador (-, _, ., :, T, espacio, coma o nada), con o sin milisegundos y en cualquier formato de fecha de hoy, pasa a la marca del formato y <hora>'] = {
  $esperado = [ordered]@{
    '2026-11-22 10:26:58'         = '<hoy:yyyy-MM-dd><hora>'
    '2026-11-22T10:26:58.123'     = '<hoy:yyyy-MM-dd><hora>'
    '2026-11-22T10:26:58,123456'  = '<hoy:yyyy-MM-dd><hora>'
    '2026-11-22-10-26-58'         = '<hoy:yyyy-MM-dd><hora>'
    '2026-11-22_10-26-58'         = '<hoy:yyyy-MM-dd><hora>'
    '2026-11-22_10_26_58'         = '<hoy:yyyy-MM-dd><hora>'
    '2026-11-22.10.26.58'         = '<hoy:yyyy-MM-dd><hora>'
    '2026-11-22-10-26-58-123'     = '<hoy:yyyy-MM-dd><hora>'
    '2026-11-22T102658'           = '<hoy:yyyy-MM-dd><hora>'
    '2026-11-22 102658123'        = '<hoy:yyyy-MM-dd><hora>'
    '2026-11-22 10:26'            = '<hoy:yyyy-MM-dd><hora>'
    '20261122_102658'             = '<hoy:yyyyMMdd><hora>'
    '20261122102658'              = '<hoy:yyyyMMdd><hora>'
    '20261122102658123'           = '<hoy:yyyyMMdd><hora>'
    '20261122T10:26:58'           = '<hoy:yyyyMMdd><hora>'
    '22/11/2026 10:26:58'         = '<hoy:dd/MM/yyyy><hora>'
    '22/11/2026, 10:26:58'        = '<hoy:dd/MM/yyyy><hora>'
    '22/11/2026-10-26-58'         = '<hoy:dd/MM/yyyy><hora>'
    '22112026_102658'             = '<hoy:ddMMyyyy><hora>'
    '2026_11_22-10_26_58'         = '<hoy:yyyy_MM_dd><hora>'
    '2026/11/22 10:26:58'         = '<hoy:yyyy/MM/dd><hora>'
    '22-11-2026 10:26:58'         = '<hoy:dd-MM-yyyy><hora>'
    '22-11-2026_10-26-58'         = '<hoy:dd-MM-yyyy><hora>'
    '22.11.2026 10.26.58'         = '<hoy:dd.MM.yyyy><hora>'
    '22.11.2026 10:26:58'         = '<hoy:dd.MM.yyyy><hora>'
    '2026.11.22 10:26:58'         = '<hoy:yyyy.MM.dd><hora>'
    '22_11_2026-10_26_58'         = '<hoy:dd_MM_yyyy><hora>'
    '11/22/2026 10:26:58'         = '<hoy:MM/dd/yyyy><hora>'
    '11-22-2026 10:26:58'         = '<hoy:MM-dd-yyyy><hora>'
    'informes/2026-11-22-10-26-58/resumen.xlsx' = 'informes/<hoy:yyyy-MM-dd><hora>/resumen.xlsx'
    'informes_20261122_102658.csv' = 'informes_<hoy:yyyyMMdd><hora>.csv'
    'en 2026-11-22 y en 22/11/2026' = 'en <hoy:yyyy-MM-dd> y en <hoy:dd/MM/yyyy>'
    'a las 10:26:58 y a las 10:26:58.123' = 'a las <hora> y a las <hora>'
    'dos: 2026-11-22 10:26:58 y 2026-11-22 10:31:07' = 'dos: <hoy:yyyy-MM-dd><hora> y <hoy:yyyy-MM-dd><hora>'
  }
  $v = Normaliza-M73 'm73-b2' @($esperado.Keys)
  $i = 0
  foreach ($k in $esperado.Keys) { Igual $k $esperado[$k] $v[$i]; $i++ }
  # Dos horas distintas del mismo dia dan el mismo texto: es lo que hace que el original y el migrado salgan iguales.
  $dos = Normaliza-M73 'm73-b2b' @('informes/2026-11-22-10-26-58/resumen.xlsx', 'informes/2026-11-22-10-31-07/resumen.xlsx', 'r_20261122_102658.txt', 'r_20261122_103107.txt')
  Igual 'dos horas, la misma ruta normalizada' $dos[0] $dos[1]
  Igual 'dos horas sin separador, el mismo nombre normalizado' $dos[2] $dos[3]
}

$Pruebas['m73 (b3) lo que no es de la ejecucion sigue como esta: una fecha de otro dia con hora (en cualquier formato), una hora sin fecha ni dos puntos, un numero de 6 cifras y una fecha de hoy que no es fecha'] = {
  $quedan = @(
    '1980-05-12 00:00:00',
    '2026-11-21 10:26:58',
    '2026-11-21T10:26:58.123',
    '12/05/1980 10:00:00',
    '21/11/2026 10:26:58',
    '12-05-1980 10:00:00',
    '2026-11-21-10-26-58',
    '20261121_102658',
    'a las 10-26-58 y las 10.26.58',
    'importe 102658 y 10:26',
    'id=220000 y 2026-13-22 y 2026-11-2',
    'Nov 22, 2026 y 22-nov-2026 y 22/11/26'
  )
  $v = Normaliza-M73 'm73-b3' $quedan
  for ($i = 0; $i -lt $quedan.Count; $i++) { Igual $quedan[$i] $quedan[$i] $v[$i] }
  $mez = @(Normaliza-M73 'm73-b3m' @('hecho 2026-11-22 10-26.58'))
  Igual 'una hora con dos separadores distintos no es una hora: la fecha pasa a su marca y lo demas se queda' 'hecho <hoy:yyyy-MM-dd> 10-26.58' $mez[0]
  $cuerpo = @'
Caso 'negocio' @{ 'a.txt' = "vence 1980-05-12 00:00:00`n" } @{ 'a.txt' = "vence 1980-05-11 23:00:00`n" }
Caso 'negocio-igual' @{ 'a.txt' = "vence 12/05/1980 10:00:00`n" } @{ 'a.txt' = "vence 12/05/1980 10:00:00`n" }
Caso 'negocio-otro-formato' @{ 'a.txt' = "vence 12/05/1980 10:00:00`n" } @{ 'a.txt' = "vence 12/05/1980 11:00:00`n" }
Caso 'hoy' @{ 'a.txt' = "hecho 2026-11-22 10:26:58`n" } @{ 'a.txt' = "hecho 2026-11-22 10:31:07`n" }
'@
  $c = Compara-M73 'm73-b3c' $cuerpo
  Igual 'una fecha de negocio con hora que cambia: contenido' @('contenido|a.txt|vence 1980-05-12 00:00:00|vence 1980-05-11 23:00:00|1|1||a.txt') @($c['negocio'])
  Igual 'la misma, igual' @('(ninguna)') @($c['negocio-igual'])
  Igual 'una fecha de negocio dd/MM/yyyy con hora que cambia: contenido' @('contenido|a.txt|vence 12/05/1980 10:00:00|vence 12/05/1980 11:00:00|1|1||a.txt') @($c['negocio-otro-formato'])
  Igual 'la de hoy con otra hora: igual' @('(ninguna)') @($c['hoy'])
}

$Pruebas['m73 (b4) una marca de tiempo Unix de hoy en segundos (10 cifras) o en milisegundos (13) pasa a <hora>; un numero de 10 o 13 cifras fuera de los dias de la ejecucion, no'] = {
  $esperado = [ordered]@{
    'ts=1795348800'                = 'ts=<hora>'
    'ts=1795348800123'             = 'ts=<hora>'
    'a 1795348800 y 1795348800999 b' = 'a <hora> y <hora> b'
    '{"t":1795348800,"u":1795348800123}' = '{"t":<hora>,"u":<hora>}'
    'ayer 1795262400'              = 'ayer 1795262400'
    'ayer 1795262400123'           = 'ayer 1795262400123'
    'manana 1795435200'            = 'manana 1795435200'
    'de hace anos 1700000000'      = 'de hace anos 1700000000'
    'una cuenta 1234567890'        = 'una cuenta 1234567890'
    'un numero 1795348800123456'   = 'un numero 1795348800123456'
    'once 17953488001'             = 'once 17953488001'
    'decimal 1.1795348800'         = 'decimal 1.1795348800'
    'de 9 cifras 179534880'        = 'de 9 cifras 179534880'
  }
  $v = Normaliza-M73 'm73-b4' @($esperado.Keys)
  $i = 0
  foreach ($k in $esperado.Keys) { Igual $k $esperado[$k] $v[$i]; $i++ }
}

$Pruebas['m73 (b5) de punta a punta: el original deja informes/<hoy>-10-26-58/resumen.txt y el migrado informes/<hoy>-10-31-07/resumen.txt con lo mismo: el caso sale igual (no distinto, ni una carpeta distinta)'] = {
  $e = Escenario-M73 'm73-b5' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M73 $e 'informes-txt'
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'el caso sale igual' 'igual' ((Resultados $e) -join ',')
  $hoy = (Get-Date).ToString('yyyy-MM-dd')
  Comprueba 'el original guardo su carpeta con la hora (si no, esta prueba no prueba nada)' (Test-Path -LiteralPath (Get-Ruta $e.Local "salidas/original/cargaJob/caso-01/ficheros/informes/$hoy-10-26-58/resumen.txt")) ''
}

# Las lineas (Get-LineasNormales) de un fichero de nombre $Fichero y bytes $Bytes, con el dia 2026-11-22 como el de la ejecucion, como las ensena la consola (Get-Legible).
function Lineas-M73([string]$Nombre, [string]$Fichero, [byte[]]$Bytes) {
  $f = Join-Path $Dir "$Nombre.ps1"
  $cabeza = @'
param([string]$Ruta)
$Inv = [System.Globalization.CultureInfo]::InvariantCulture
$Utf8Estricto = New-Object System.Text.UTF8Encoding($false, $true)
$RutasCopia = @()
$Hoy = @([datetime]'2026-11-22')
$Latin = [System.Text.Encoding]::GetEncoding(28591); $Utf8 = New-Object System.Text.UTF8Encoding($false)
'@
  $cola = 'foreach ($l in @(Get-LineasNormales $Ruta)) { ''L '' + (Get-Legible $l) }'
  [System.IO.File]::WriteAllText($f, ($cabeza + "`n" + (Texto-De-Funciones $Script ($FnComparaM73 + @('Get-Legible'))) + "`n" + $cola))
  $x = Join-Path $Dir "$Nombre-$Fichero"
  [System.IO.File]::WriteAllBytes($x, $Bytes)
  $r = Lanzar $f @($x)
  return @(@($r.Salida -split "`n") | Where-Object { $_ -cmatch '^L ' } | ForEach-Object { $_.Substring(2).TrimEnd("`r") })
}

# Un zip (en bytes) con las partes de $Partes (nombre -> texto o [byte[]]), con la fecha de cada entrada fija: los mismos bytes cada vez que se construye.
function Zip-M73($Partes) {
  Add-Type -AssemblyName System.IO.Compression
  $ms = New-Object System.IO.MemoryStream
  $zip = New-Object System.IO.Compression.ZipArchive($ms, [System.IO.Compression.ZipArchiveMode]::Create, $true)
  $fijo = New-Object System.DateTimeOffset(2020, 1, 1, 0, 0, 0, [System.TimeSpan]::Zero)
  foreach ($k in $Partes.Keys) {
    $e = $zip.CreateEntry($k)
    $e.LastWriteTime = $fijo
    $b = $Partes[$k]
    if ($b -is [string]) { $b = (New-Object System.Text.UTF8Encoding($false)).GetBytes($b) }
    if ($b.Length -gt 0) { $s = $e.Open(); $s.Write($b, 0, $b.Length); $s.Dispose() }
  }
  $zip.Dispose()
  return , $ms.ToArray()
}

# Un .xlsx (en bytes) con el XML minimo: $Creado va en docProps/core.xml y $Estilo en xl/styles.xml (no cuentan). $Hojas: nombre de hoja -> celdas, cada una @(ref, tipo, valor [, cache])
# con tipo s (cadena compartida), i (cadena en la propia celda), n (numero), b (booleano), f (formula, con su valor en cache).
function Xlsx-M73([string]$Creado, $Hojas, [string]$Estilo = 'a') {
  $esc = { param([string]$s) [System.Security.SecurityElement]::Escape($s) }
  $compartidas = New-Object System.Collections.ArrayList
  $partes = [ordered]@{}
  $partes['[Content_Types].xml'] = '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="xml" ContentType="application/xml"/></Types>'
  $partes['_rels/.rels'] = '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'
  $partes['docProps/core.xml'] = '<?xml version="1.0" encoding="UTF-8"?><cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dcterms="http://purl.org/dc/terms/"><dcterms:created>' + $Creado + '</dcterms:created></cp:coreProperties>'
  $partes['docProps/app.xml'] = '<?xml version="1.0" encoding="UTF-8"?><Properties><TotalTime>' + $Creado.Length + '</TotalTime></Properties>'
  $partes['xl/styles.xml'] = '<?xml version="1.0" encoding="UTF-8"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="1"><font><name val="' + $Estilo + '"/></font></fonts></styleSheet>'
  $hojasXml = ''; $rels = ''; $n = 0
  foreach ($nombre in $Hojas.Keys) {
    $n++
    $filas = [ordered]@{}
    foreach ($c in $Hojas[$nombre]) {
      $fila = [regex]::Match($c[0], '\d+').Value
      if (-not $filas.Contains($fila)) { $filas[$fila] = '' }
      $v = [string]$c[2]
      switch ($c[1]) {
        's' { $ix = $compartidas.IndexOf($v); if ($ix -lt 0) { $ix = $compartidas.Add($v) }; $xml = '<c r="' + $c[0] + '" t="s"><v>' + $ix + '</v></c>' }
        'i' { $xml = '<c r="' + $c[0] + '" t="inlineStr"><is><t>' + (& $esc $v) + '</t></is></c>' }
        'b' { $xml = '<c r="' + $c[0] + '" t="b"><v>' + $v + '</v></c>' }
        'f' { $xml = '<c r="' + $c[0] + '"><f>' + (& $esc $v) + '</f><v>' + $c[3] + '</v></c>' }
        default { $xml = '<c r="' + $c[0] + '"><v>' + $v + '</v></c>' }
      }
      $filas[$fila] += $xml
    }
    $datos = ''
    foreach ($f in $filas.Keys) { $datos += '<row r="' + $f + '">' + $filas[$f] + '</row>' }
    $partes["xl/worksheets/sheet$n.xml"] = '<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>' + $datos + '</sheetData></worksheet>'
    $hojasXml += '<sheet name="' + (& $esc $nombre) + '" sheetId="' + $n + '" r:id="rId' + $n + '"/>'
    $rels += '<Relationship Id="rId' + $n + '" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet' + $n + '.xml"/>'
  }
  $partes['xl/workbook.xml'] = '<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>' + $hojasXml + '</sheets></workbook>'
  $partes['xl/_rels/workbook.xml.rels'] = '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' + $rels + '</Relationships>'
  if ($compartidas.Count -gt 0) {
    $partes['xl/sharedStrings.xml'] = '<?xml version="1.0" encoding="UTF-8"?><sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="' + $compartidas.Count + '" uniqueCount="' + $compartidas.Count + '">' + (($compartidas | ForEach-Object { '<si><t>' + (& $esc $_) + '</t></si>' }) -join '') + '</sst>'
  }
  return , (Zip-M73 $partes)
}

function Sha-M73([byte[]]$Bytes) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { return ((@($sha.ComputeHash($Bytes)) | ForEach-Object { $_.ToString('x2') }) -join '') } finally { $sha.Dispose() }
}

# Un .png de mentira de 19 bytes; $Ultimo es su ultimo byte.
function Png-M73([byte]$Ultimo = 0x80) { return , ([byte[]](0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0xFF, 0xFE, $Ultimo)) }

# Un .gz (en bytes) con el texto $Texto.
function Gz-M73([string]$Texto) {
  $ms = New-Object System.IO.MemoryStream
  $g = New-Object System.IO.Compression.GZipStream($ms, [System.IO.Compression.CompressionMode]::Compress, $true)
  $b = [System.Text.Encoding]::UTF8.GetBytes($Texto)
  $g.Write($b, 0, $b.Length); $g.Dispose()
  return , $ms.ToArray()
}

# Un PDF de mentira (en bytes) con el texto $Cuerpo y, si $Fecha no es '', su /CreationDate, su /ModDate (de $Fecha) y su /ID (de $Id).
function Pdf-M73([string]$Fecha, [string]$Id, [string]$Cuerpo) {
  $info = ''; $trailer = '<< /Root 1 0 R >>'
  if ($Fecha) { $info = " /CreationDate (D:$Fecha+01'00') /ModDate (D:$Fecha+01'00')"; $trailer = "<< /Root 1 0 R /ID [<$Id><$Id>] >>" }
  $t = "%PDF-1.4`n1 0 obj << /Producer (acme)$info >> endobj`n2 0 obj << /Length 5 >> stream`n$Cuerpo`nendstream endobj`ntrailer $trailer`n%%EOF`n"
  return , [System.Text.Encoding]::GetEncoding(28591).GetBytes($t + [string][char]0x80)
}

# El libro de los tests: dos hojas (Hoja1: texto, numero, texto con la hora de hoy y $Texto en B3; Datos: una cadena con enie y u con tilde, un booleano y una formula).
function Libro-M73([string]$Texto = 'x', [string]$Hora = '10:26:58', [string]$Estilo = 'a') {
  $hojas = [ordered]@{
    Hoja1 = @(@('A1', 's', 'importe'), @('B1', 'n', '10'), @('A2', 's', "generado 2026-11-22 $Hora"), @('B3', 's', $Texto))
    Datos = @(@('A1', 'i', ([string][char]0xF1 + 'and' + [char]0xFA)), @('B2', 'b', '1'), @('C3', 'f', 'SUM(B1:B1)', '10'))
  }
  return , (Xlsx-M73 ('2026-11-22T' + $Hora + 'Z') $hojas $Estilo)
}

$Pruebas['m73 (c1) dos .xlsx con las mismas celdas y distinto docProps/core.xml, estilos y hora dentro de una celda: iguales; se leen celda a celda (hoja!celda: valor), con las cadenas compartidas, en el orden de las hojas'] = {
  $a = Libro-M73 'x' '10:26:58' 'a'
  $b = Libro-M73 'x' '10:31:07' 'b'
  Comprueba 'los dos .xlsx no son el mismo fichero' ((Sha-M73 $a) -ne (Sha-M73 $b)) ''
  $v = Compara-M73 'm73-c1' "Caso 'igual' @{ 'ficheros/informe.xlsx' = (Bin 'a') } @{ 'ficheros/informe.xlsx' = (Bin 'b') }" @{ a = $a; b = $b }
  Igual 'iguales' @('(ninguna)') @($v['igual'])
  $l = Lineas-M73 'm73-c1l' 'informe.xlsx' $a
  $esperadas = @('Hoja1!A1: importe', 'Hoja1!B1: 10', 'Hoja1!A2: generado <hoy:yyyy-MM-dd><hora>', 'Hoja1!B3: x', ('Datos!A1: ' + [char]0xF1 + 'and' + [char]0xFA), 'Datos!B2: TRUE', 'Datos!C3: =SUM(B1:B1) -> 10')
  Igual 'las lineas del libro: hoja!celda: valor, las hojas en orden, la cadena compartida resuelta, la enie y la u con tilde, el booleano y la formula con su valor' ($esperadas -join '|') ($l -join '|')
}

$Pruebas['m73 (c2) una celda distinta: distinto, con la primera linea distinta Hoja1!B3 en los dos lados; ni lo que sale en la consola ni el JSON llevan bytes que no sean de texto; de punta a punta, igual con otra hora y distinto con otra celda'] = {
  $a = Libro-M73 'x'
  $b = Libro-M73 'y' '10:31:07' 'b'
  $v = Compara-M73 'm73-c2' "Caso 'dif' @{ 'ficheros/informe.xlsx' = (Bin 'a') } @{ 'ficheros/informe.xlsx' = (Bin 'b') }" @{ a = $a; b = $b }
  Igual 'una diferencia de contenido: la linea 4, Hoja1!B3, en cada lado, sin nota' @('contenido|ficheros/informe.xlsx|Hoja1!B3: x|Hoja1!B3: y|1|4||ficheros/informe.xlsx') @($v['dif'])
  $e = Escenario-M73 'm73-c2e' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M73 $e 'informes;celda'
  Igual 'de punta a punta sale con 2 (el Maven falso deja el libro con otra celda en el migrado: un caso distinto)' 2 $r.Codigo
  $c = Caso $e 'cargaJob' 'caso-01'
  Igual 'el caso sale distinto' 'distinto' $c.resultado
  $d = @($c.diferencias)[0]
  Igual 'con la linea del original: la celda' 'Hoja1!B3: x' "$($d.original)"
  Igual 'y la del migrado' 'Hoja1!B3: y' "$($d.migrado)"
  $json = [System.IO.File]::ReadAllText($e.Json)
  $mal = '[\x00-\x08\x0B\x0C\x0E-\x1F\uFFFD]'
  Comprueba 'el JSON no lleva bytes de control ni caracteres de reemplazo' ($json -notmatch $mal) ''
  Comprueba 'la consola tampoco' ($r.Salida -notmatch $mal) (Cola $r.Salida)
  Comprueba 'y la consola dice la celda' ($r.Salida.Contains('Hoja1!B3')) (Cola $r.Salida)
  $e = Escenario-M73 'm73-c2f' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M73 $e 'informes'
  Igual 'dos libros con las mismas celdas y otra hora (en la carpeta, en docProps y en una celda): sale con 0' 0 $r.Codigo
  Igual 'el caso sale igual' 'igual' ((Resultados $e) -join ',')
}

$Pruebas['m73 (c3) un numero que es una fecha de Excel de uno de los dias de la ejecucion: con fraccion de hora, <hoy:excel><hora> (otra hora, igual); sin ella, <hoy:excel>; el dia siguiente, no'] = {
  $serial = ([datetime]'2026-11-22' - [datetime]'1899-12-30').Days
  $hojas = { param([string]$Fraccion, [int]$Dia) [ordered]@{ Hoja1 = @(@('A1', 'n', "$serial.$Fraccion"), @('A2', 'n', "$serial"), @('A3', 'n', "$Dia"), @('A4', 'n', '0.4351851852'), @('A5', 'n', '1234567')) } }
  $a = Xlsx-M73 '2026-11-22T10:26:58Z' (& $hojas '4351851852' ($serial + 1))
  $b = Xlsx-M73 '2026-11-22T10:31:07Z' (& $hojas '4382870370' ($serial + 1))
  $c = Xlsx-M73 '2026-11-22T10:31:07Z' (& $hojas '4382870370' ($serial + 2))
  $cuerpo = "Caso 'igual' @{ 'i.xlsx' = (Bin 'a') } @{ 'i.xlsx' = (Bin 'b') }`nCaso 'manana' @{ 'i.xlsx' = (Bin 'a') } @{ 'i.xlsx' = (Bin 'c') }"
  $v = Compara-M73 'm73-c3' $cuerpo @{ a = $a; b = $b; c = $c }
  Igual 'la misma fecha con otra hora: igual' @('(ninguna)') @($v['igual'])
  Igual 'el dia de despues no es de hoy: sale como numero, y distinto' @("contenido|i.xlsx|Hoja1!A3: $($serial + 1)|Hoja1!A3: $($serial + 2)|1|3||i.xlsx") @($v['manana'])
  $l = Lineas-M73 'm73-c3l' 'i.xlsx' $a
  Igual 'con fraccion, <hoy:excel><hora>; sin ella, <hoy:excel>; el dia siguiente, otro numero que sigue como esta, y los que no son una fecha de hoy' "Hoja1!A1: <hoy:excel><hora>|Hoja1!A2: <hoy:excel>|Hoja1!A3: $($serial + 1)|Hoja1!A4: 0.4351851852|Hoja1!A5: 1234567" ($l -join '|')
}

$Pruebas['m73 (c4) un .png (y otro binario, o un fichero con un byte 0): una sola linea binario: <n> bytes, sha256 <hash>; distinto con la nota, igual si los bytes lo son'] = {
  $a = Png-M73 0x80
  $b = Png-M73 0x81
  $n1 = [byte[]](0x61, 0x00, 0x62, 0xFF)
  $n2 = [byte[]](0x61, 0x00, 0x63, 0xFF)
  $cuerpo = "Caso 'igual' @{ 'ficheros/logo.png' = (Bin 'a') } @{ 'ficheros/logo.png' = (Bin 'a') }`nCaso 'dif' @{ 'ficheros/logo.png' = (Bin 'a') } @{ 'ficheros/logo.png' = (Bin 'b') }`nCaso 'nul' @{ 'datos.dat' = (Bin 'n1') } @{ 'datos.dat' = (Bin 'n2') }"
  $v = Compara-M73 'm73-c4' $cuerpo @{ a = $a; b = $b; n1 = $n1; n2 = $n2 }
  $nota = 'binario: se compara entero (sha256), no por dentro'
  Igual 'los mismos bytes: igual' @('(ninguna)') @($v['igual'])
  Igual 'otro byte: una linea binario en cada lado, con su hash, y la nota' @("contenido|ficheros/logo.png|binario: 19 bytes, sha256 $(Sha-M73 $a)|binario: 19 bytes, sha256 $(Sha-M73 $b)|1|1|$nota|ficheros/logo.png") @($v['dif'])
  Igual 'un fichero con un byte 0 en los primeros 8 KB, aunque su extension no diga nada, tambien es binario' @("contenido|datos.dat|binario: 4 bytes, sha256 $(Sha-M73 $n1)|binario: 4 bytes, sha256 $(Sha-M73 $n2)|1|1|$nota|datos.dat") @($v['nul'])
  $e = Escenario-M73 'm73-c4e' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba-M73 $e 'png-otro'
  $d = @((Caso $e 'cargaJob' 'caso-01').diferencias)[0]
  Igual 'de punta a punta: el caso sale distinto con la linea binario en el JSON' "binario: 19 bytes, sha256 $(Sha-M73 $a)|binario: 19 bytes, sha256 $(Sha-M73 $b)" "$($d.original)|$($d.migrado)"
  Comprueba 'y la consola no lleva bytes de control' ($r.Salida -notmatch '[\x00-\x08\x0B\x0C\x0E-\x1F\uFFFD]') (Cola $r.Salida)
  $e = Escenario-M73 'm73-c4f' ([ordered]@{ cargaJob = @('importe=10.00') })
  [void](Prueba-M73 $e 'png')
  Igual 'con el mismo .png en los dos lados, igual' 'igual' ((Resultados $e) -join ',')
}

$Pruebas['m73 (c5) un .zip con un .txt que lleva la hora de hoy dentro, una imagen y un .xlsx dentro, y un .gz con un texto: se leen entrada a entrada, con su nombre delante; otra hora, igual; otro contenido, distinto en la linea de esa entrada'] = {
  $png = Png-M73 0x80
  $zip = {
    param([string]$Hora, [string]$Importe = '10', [string]$LibroTexto = 'x')
    Zip-M73 ([ordered]@{ 'r.txt' = "hecho 2026-11-22 $Hora`nimporte;$Importe`n"; 'logo.png' = $png; 'sub/libro.xlsx' = (Libro-M73 $LibroTexto $Hora); 'sub/' = '' })
  }
  $gz = { param([string]$Hora) Gz-M73 "hecho 2026-11-22 $Hora`nimporte;10`n" }
  $roto = [byte[]](0x50, 0x4B, 0x03, 0x04, 0x01, 0x02)
  $roto2 = [byte[]](0x50, 0x4B, 0x03, 0x04, 0x01, 0x03)
  $bin = @{ z1 = (& $zip '10:26:58'); z2 = (& $zip '10:31:07'); z3 = (& $zip '10:31:07' '11'); z4 = (& $zip '10:31:07' '10' 'y'); g1 = (& $gz '10:26:58'); g2 = (& $gz '10:31:07'); r1 = $roto; r2 = $roto2 }
  $cuerpo = @'
Caso 'igual' @{ 'ficheros/lote.zip' = (Bin 'z1') } @{ 'ficheros/lote.zip' = (Bin 'z2') }
Caso 'dif' @{ 'ficheros/lote.zip' = (Bin 'z1') } @{ 'ficheros/lote.zip' = (Bin 'z3') }
Caso 'libro' @{ 'ficheros/lote.zip' = (Bin 'z1') } @{ 'ficheros/lote.zip' = (Bin 'z4') }
Caso 'gz' @{ 'r.txt.gz' = (Bin 'g1') } @{ 'r.txt.gz' = (Bin 'g2') }
Caso 'malo' @{ 'roto.zip' = (Bin 'r1') } @{ 'roto.zip' = (Bin 'r2') }
'@
  $v = Compara-M73 'm73-c5' $cuerpo $bin
  Igual 'el zip con otra hora en el .txt y en el libro de dentro: igual' @('(ninguna)') @($v['igual'])
  Igual 'otro importe en el .txt: una diferencia, la linea de r.txt (despues de logo.png y la hora), con el nombre de la entrada delante' @('contenido|ficheros/lote.zip|r.txt: importe;10|r.txt: importe;11|1|3||ficheros/lote.zip') @($v['dif'])
  Igual 'una celda distinta en el libro de dentro: sub/libro.xlsx: Hoja1!B3' @('contenido|ficheros/lote.zip|sub/libro.xlsx: Hoja1!B3: x|sub/libro.xlsx: Hoja1!B3: y|1|7||ficheros/lote.zip') @($v['libro'])
  Igual 'un .gz con un texto con otra hora: igual' @('(ninguna)') @($v['gz'])
  Igual 'un .zip roto (no se puede abrir): una linea binario y la nota, no basura' @("contenido|roto.zip|binario: 6 bytes, sha256 $(Sha-M73 $roto)|binario: 6 bytes, sha256 $(Sha-M73 $roto2)|1|1|binario: se compara entero (sha256), no por dentro|roto.zip") @($v['malo'])
  $l = Lineas-M73 'm73-c5l' 'lote.zip' (& $zip '10:26:58')
  $esperadas = @(('logo.png: binario: 19 bytes, sha256 ' + (Sha-M73 $png)), 'r.txt: hecho <hoy:yyyy-MM-dd><hora>', 'r.txt: importe;10', 'sub/libro.xlsx: Hoja1!A1: importe')
  Igual 'las primeras lineas del zip: cada entrada con su nombre delante, la imagen como binario y las entradas en orden de nombre' ($esperadas -join '|') (@($l | Select-Object -First 4) -join '|')
}

$Pruebas['m73 (c6) un PDF: sin su /CreationDate, /ModDate ni /ID se compara como binario, asi que dos PDF que solo cambian en eso salen iguales; si cambia otra cosa, distinto con la nota de la fecha de creacion'] = {
  $bin = @{ p1 = (Pdf-M73 '20261122102658' 'AA11BB22' 'hola'); p2 = (Pdf-M73 '20261122103107' 'CC33DD44' 'hola'); p3 = (Pdf-M73 '20261122103107' 'CC33DD44' 'adios') }
  $cuerpo = "Caso 'igual' @{ 'ficheros/informe.pdf' = (Bin 'p1') } @{ 'ficheros/informe.pdf' = (Bin 'p2') }`nCaso 'dif' @{ 'ficheros/informe.pdf' = (Bin 'p1') } @{ 'ficheros/informe.pdf' = (Bin 'p3') }"
  $v = Compara-M73 'm73-c6' $cuerpo $bin
  Igual 'dos PDF que solo cambian en la fecha y el /ID: igual' @('(ninguna)') @($v['igual'])
  $dif = @($v['dif'])
  Igual 'con otro cuerpo: una diferencia' 1 $dif.Count
  Comprueba 'es una linea binario en cada lado' ($dif[0] -cmatch '^contenido\|ficheros/informe\.pdf\|binario: \d+ bytes, sha256 [0-9a-f]{64}\|binario: \d+ bytes, sha256 [0-9a-f]{64}\|1\|1\|') $dif[0]
  Comprueba 'con la nota que dice que puede ser la fecha de creacion' ($dif[0].Contains('un PDF lleva su fecha de creacion dentro')) $dif[0]
}

$Pruebas['m73 (d2) Get-MotivoCambiante: un .xlsx con la fecha de hoy en una celda, un .zip o un .gz con la hora de hoy en un texto y un PDF con su fecha de creacion no valen como test fijo (el motivo de siempre); sin fechas (o con la fecha solo en docProps) valen, y un .png tambien'] = {
  $serial = ([datetime]'2026-11-22' - [datetime]'1899-12-30').Days
  $png = Png-M73 0x80
  $ficheros = [ordered]@{
    'con-excel.xlsx' = (Xlsx-M73 '2026-11-22T10:26:58Z' ([ordered]@{ Hoja1 = @(@('A1', 's', 'importe'), @('A2', 'n', "$serial.5")) }))
    'texto-excel.xlsx' = (Xlsx-M73 '2026-11-22T10:26:58Z' ([ordered]@{ Hoja1 = @(, @('A1', 's', 'generado 2026-11-22 10:26:58')) }))
    'sin-excel.xlsx' = (Xlsx-M73 '2026-11-22T10:26:58Z' ([ordered]@{ Hoja1 = @(@('A1', 's', 'importe'), @('A2', 'n', '15')) }))
    'con-zip.zip' = (Zip-M73 ([ordered]@{ 'r.txt' = "hecho 2026-11-22 10:26:58`n"; 'logo.png' = $png }))
    'nombre-zip.zip' = (Zip-M73 ([ordered]@{ 'r_20261122.txt' = "importe;10`n" }))
    'sin-zip.zip' = (Zip-M73 ([ordered]@{ 'r.txt' = "importe;10`n"; 'logo.png' = $png }))
    'con-gz.txt.gz' = (Gz-M73 "hecho 2026-11-22 10:26:58`n")
    'sin-gz.txt.gz' = (Gz-M73 "importe;10`n")
    'con-pdf.pdf' = (Pdf-M73 '20261122102658' 'AA11BB22' 'hola')
    'sin-pdf.pdf' = (Pdf-M73 '' '' 'hola')
    'pdf-otro-dia.pdf' = (Pdf-M73 '20200101120000' 'CC33DD44' 'hola')
    'zip-en-zip.zip' = (Zip-M73 ([ordered]@{ 'dentro.zip' = (Zip-M73 ([ordered]@{ 'informe-2026-11-22.txt' = "importe;10`n" })) }))
    'sin-zip-en-zip.zip' = (Zip-M73 ([ordered]@{ 'dentro.zip' = (Zip-M73 ([ordered]@{ 'informe.txt' = "importe;10`n" })) }))
    'logo.png' = $png
  }
  $d = Join-Path $Dir 'm73-d2-ficheros'
  if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force }
  [void](New-Item -ItemType Directory -Path $d -Force)
  foreach ($k in $ficheros.Keys) { [System.IO.File]::WriteAllBytes((Join-Path $d $k), [byte[]]$ficheros[$k]) }
  $f = Join-Path $Dir 'm73-d2.ps1'
  $cabeza = @'
param([string]$Raiz)
$Inv = [System.Globalization.CultureInfo]::InvariantCulture
$RutasCopia = @()
$Hoy = @([datetime]'2026-11-22')
$Latin = [System.Text.Encoding]::GetEncoding(28591); $Utf8 = New-Object System.Text.UTF8Encoding($false)
'@
  $cola = 'foreach ($n in @(Get-ChildItem -LiteralPath $Raiz -File | ForEach-Object { $_.Name })) { ''M '' + $n + '' ['' + (Get-MotivoCambiante $Raiz @($n)) + '']'' }'
  $comun = Join-Path (Split-Path -Parent $Script) 'comun.ps1'
  $regresion = Join-Path (Split-Path -Parent $Script) 'regresion.ps1'
  [System.IO.File]::WriteAllText($f, ($cabeza + "`n" + (Texto-De-Funciones $Script ($FnLeer + @('Get-Normal', 'Test-NombreCorto'))) + "`n" + (Texto-De-Funciones $comun @('Join-Ruta')) + "`n" + (Texto-De-Funciones $regresion @('Get-MotivoCambiante')) + "`n" + $cola))
  $r = Lanzar $f @($d)
  $m = @{}
  foreach ($l in @($r.Salida -split "`n")) { if ($l -cmatch '^M (\S+) \[(.*)\]$') { $m[$Matches[1]] = $Matches[2] } }
  $motivo = 'lleva la fecha de hoy, una hora o la ruta de una copia: no saldria igual en otra ejecucion.'
  foreach ($k in @('con-excel.xlsx', 'texto-excel.xlsx', 'con-zip.zip', 'nombre-zip.zip', 'con-gz.txt.gz', 'con-pdf.pdf', 'pdf-otro-dia.pdf', 'zip-en-zip.zip')) { Igual "$k no vale como test fijo, con el motivo de siempre" "$k $motivo" $m[$k] }
  foreach ($k in @('sin-excel.xlsx', 'sin-zip.zip', 'sin-gz.txt.gz', 'sin-pdf.pdf', 'sin-zip-en-zip.zip', 'logo.png')) { Igual "$k vale" '' $m[$k] }
}

$Pruebas['m73 (c7) cada tipo, por su lado: una extension de binario sin ningun byte 0 es binario; un .xlsx que es un zip sin libro se lee como zip; un .gz sale con el nombre de dentro; una entrada vacia se dice; un zip dentro de un zip dentro de un zip dentro de un zip se queda en un binario'] = {
  $bin = '^binario: \d+ bytes, sha256 [0-9a-f]{64}$'
  $texto = [System.Text.Encoding]::GetEncoding(28591).GetBytes('no es un jpeg de verdad')
  $l = @(Lineas-M73 'm73-c7a' 'logo.jpg' $texto)
  Comprueba 'un .jpg sin byte 0: una linea binario' ($l.Count -eq 1 -and $l[0] -cmatch $bin) ($l -join '|')
  $l = @(Lineas-M73 'm73-c7b' 'logo.txt' $texto)
  Igual 'los mismos bytes en un .txt: el texto' 'no es un jpeg de verdad' ($l -join '|')
  $l = @(Lineas-M73 'm73-c7c' 'raro.xlsx' (Zip-M73 ([ordered]@{ 'r.txt' = "importe;10`n" })))
  Igual 'un .xlsx que es un zip sin libro: sus entradas' 'r.txt: importe;10' ($l -join '|')
  $l = @(Lineas-M73 'm73-c7d' 'datos.txt.gz' (Gz-M73 "a;b`n"))
  Igual 'un .gz: el nombre de dentro (el del fichero sin .gz) y su linea' 'm73-c7d-datos.txt: a;b' ($l -join '|')
  $l = @(Lineas-M73 'm73-c7e' 'vacia.zip' (Zip-M73 ([ordered]@{ 'r.txt' = 'x'; 'vacio.txt' = '' })))
  Igual 'una entrada vacia sale como (vacio), con las entradas en orden de nombre' 'r.txt: x|vacio.txt: (vacio)' ($l -join '|')
  $tres = Zip-M73 ([ordered]@{ 'l1.zip' = (Zip-M73 ([ordered]@{ 'l2.zip' = (Zip-M73 ([ordered]@{ 'a.txt' = 'x' })) })) })
  $l = @(Lineas-M73 'm73-c7f' 'tres.zip' $tres)
  Igual 'dos zips dentro: se leen hasta el texto' 'l1.zip: l2.zip: a.txt: x' ($l -join '|')
  $cuatro = Zip-M73 ([ordered]@{ 'l1.zip' = (Zip-M73 ([ordered]@{ 'l2.zip' = (Zip-M73 ([ordered]@{ 'l3.zip' = (Zip-M73 ([ordered]@{ 'a.txt' = 'x' })) })) })) })
  $l = @(Lineas-M73 'm73-c7g' 'cuatro.zip' $cuatro)
  Comprueba 'tres zips dentro: el tercero ya es un binario' ($l.Count -eq 1 -and $l[0] -cmatch ('^l1\.zip: l2\.zip: l3\.zip: ' + $bin.TrimStart('^'))) ($l -join '|')
}

# ===================== M77: la prueba en local dice quien no arranca (original o migrado, test o codigo) y no ejecuta casos que no valen =====================
# m77-mvn.ps1 (sobre m48-mvn.ps1) deja, segun el guion de RESCATE_M77 ('guion:regex sobre job/caso', separados por ';'), un job que no arranca o que falla igual: el
# original con NoSuchBeanDefinitionException (orig-bean), BeanCreationException (orig-creacion), JobParametersInvalidException (orig-parametros) o FAILED con una
# NoSuchFileException de una carpeta fija (orig-failed, orig-failed-caso); el migrado con una clase final (mig-proxy), una referencia circular (mig-circular) o un
# bean repetido (mig-override); o los dos lados (ambos-bean). RESCATE_M48 sigue valiendo.

$M77Bean = "org.springframework.beans.factory.NoSuchBeanDefinitionException: No bean named 'contableConfig' available"
$M77Fichero = 'java.nio.file.NoSuchFileException: C:\datos\salida\outbox'
$M77Motivo = 'el original falla igual en los primeros casos de este job con este test y no se ejecutan los demas: relanza con -RehacerOriginal'

function Escenario-M77([string]$Nombre, $Casos, [hashtable]$Mas = @{}) {
  $aj = @{ MvnExe = (Join-Path $falsos 'm77-mvn.ps1') }
  foreach ($k in $Mas.Keys) { $aj[$k] = $Mas[$k] }
  return (Escenario-M25 $Nombre $Casos -Sano -Ajustes $aj)
}

# Lanza con los guiones $Guion de m77-mvn.ps1 y, con $M48, los de m48-mvn.ps1.
function Prueba-M77($E, [string]$Guion, [string[]]$A = @(), [string]$M48 = '') {
  $env:RESCATE_M77 = $Guion
  $env:RESCATE_M48 = $M48
  try { return (Prueba $E $A) }
  finally { $env:RESCATE_M77 = ''; $env:RESCATE_M48 = '' }
}

# Los casos de un job que han tenido un Maven de $Lado (original, original-2 o migrado) en este lanzamiento, por su registro en prueba-local\registros: 'caso-01,caso-02'.
function Casos-M77($E, [string]$Lado, [string]$Job = 'cargaJob') {
  $d = Get-Ruta $E.Local 'registros'
  if (-not (Test-Path -LiteralPath $d)) { return '' }
  return ((@(Get-ChildItem -LiteralPath $d -File -Filter "mvn-*-$Lado-$Job-caso-*.log" | ForEach-Object { [regex]::Match($_.Name, '(caso-\d+)\.log$').Groups[1].Value } | Sort-Object)) -join ',')
}

$Pruebas['m77 (a1) cargaJob con 5 casos y el original con NoSuchBeanDefinitionException en todos: del original (y del original-2) se ejecutan los 3 primeros, del migrado los mismos 3, y los otros 2 salen sin probar con el motivo nuevo'] = {
  $e = Escenario-M77 'm77-a1' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00', 'importe=30.00', 'importe=40.00', 'importe=50.00') }) @{ Intentos = 1 }
  $r = Prueba-M77 $e 'orig-bean:^cargaJob/caso-'
  Igual 'sale con 2 (los 3 primeros salen distintos)' 2 $r.Codigo
  Igual 'el original ejecuta solo los 3 primeros casos' 'caso-01,caso-02,caso-03' (Casos-M77 $e 'original')
  Igual 'el original-2, los mismos' 'caso-01,caso-02,caso-03' (Casos-M77 $e 'original-2')
  Igual 'el migrado, los mismos: ninguno mas de ese job en ningun lado' 'caso-01,caso-02,caso-03' (Casos-M77 $e 'migrado')
  Igual 'los tres primeros distintos y los otros 2 sin probar' 'distinto,distinto,distinto,sin probar en local,sin probar en local' ((Resultados $e) -join ',')
  foreach ($c in @('caso-04', 'caso-05')) { Igual "el motivo de $c" $M77Motivo "$((Caso $e 'cargaJob' $c).motivo)" }
  Comprueba 'la consola dice que para tras los 3 primeros' ($r.Salida -match 'El original no arranca el job cargaJob con este test \(NoSuchBeanDefinitionException\): no ejecuto sus demas casos') (Cola $r.Salida)
  Comprueba 'y no guarda salida del original del cuarto caso' (-not (Test-Path -LiteralPath (Get-Ruta $e.Local 'salidas/original/cargaJob/caso-04'))) ''
  $r = Prueba-M77 $e 'orig-bean:^cargaJob/caso-'
  Igual 'otro lanzamiento (los 3 primeros se reutilizan): los 2 siguen sin probar' 'distinto,distinto,distinto,sin probar en local,sin probar en local' ((Resultados $e) -join ',')
  Comprueba 'y tampoco ejecuta ahora el cuarto en el original' (-not (Test-Path -LiteralPath (Get-Ruta $e.Local 'salidas/original/cargaJob/caso-04'))) ''
}

$Pruebas['m77 (a2) no se para con causas distintas en los 3 primeros casos, con solo 2 iguales, ni con un job de menos de 3 casos'] = {
  $e = Escenario-M77 'm77-a2' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00', 'importe=30.00', 'importe=40.00'); remesaJob = @('importe=10.00', 'importe=20.00', 'importe=30.00', 'importe=40.00'); tarifaJob = @('importe=10.00', 'importe=20.00') }) @{ Intentos = 1 }
  $r = Prueba-M77 $e 'orig-bean:^cargaJob/caso-0[13]$;orig-creacion:^cargaJob/caso-02$;orig-bean:^remesaJob/caso-0[12]$;orig-bean:^tarifaJob/caso-'
  Igual 'sale con 2' 2 $r.Codigo
  Igual 'cargaJob (3 causas distintas en los 3 primeros): sus 4 casos en el original' 'caso-01,caso-02,caso-03,caso-04' (Casos-M77 $e 'original' 'cargaJob')
  Igual 'y en el migrado' 'caso-01,caso-02,caso-03,caso-04' (Casos-M77 $e 'migrado' 'cargaJob')
  Igual 'remesaJob (2 iguales y el tercero bien): sus 4 casos en el original' 'caso-01,caso-02,caso-03,caso-04' (Casos-M77 $e 'original' 'remesaJob')
  Igual 'y en el migrado' 'caso-01,caso-02,caso-03,caso-04' (Casos-M77 $e 'migrado' 'remesaJob')
  Igual 'tarifaJob (2 casos): los dos en el original' 'caso-01,caso-02' (Casos-M77 $e 'original' 'tarifaJob')
  Igual 'y en el migrado' 'caso-01,caso-02' (Casos-M77 $e 'migrado' 'tarifaJob')
  Comprueba 'ningun caso sale sin probar' (@(Resultados $e | Where-Object { $_ -ceq 'sin probar en local' }).Count -eq 0) ((Resultados $e) -join ',')
  Comprueba 'y la consola no dice que deja de ejecutar casos' ($r.Salida -notmatch 'no ejecuto sus demas casos') (Cola $r.Salida)
}

$Pruebas['m77 (a3) con 3 FAILED iguales en el original (la ruta de la causa lleva el nombre del caso, Get-CausaNormal la deja igual) tambien se para; con 3 casos no queda nada que parar'] = {
  $e = Escenario-M77 'm77-a3' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00', 'importe=30.00', 'importe=40.00', 'importe=50.00'); remesaJob = @('importe=10.00', 'importe=20.00', 'importe=30.00') }) @{ Intentos = 1 }
  $r = Prueba-M77 $e 'orig-failed-caso:^cargaJob/caso-;orig-failed:^remesaJob/caso-'
  Igual 'sale con 2' 2 $r.Codigo
  Igual 'cargaJob: el original ejecuta los 3 primeros casos' 'caso-01,caso-02,caso-03' (Casos-M77 $e 'original' 'cargaJob')
  Igual 'y el migrado, los mismos' 'caso-01,caso-02,caso-03' (Casos-M77 $e 'migrado' 'cargaJob')
  foreach ($c in @('caso-04', 'caso-05')) { Igual "cargaJob/$c sale sin probar, con el motivo" "sin probar en local|$M77Motivo" "$((Caso $e 'cargaJob' $c).resultado)|$((Caso $e 'cargaJob' $c).motivo)" }
  Comprueba 'la consola dice que falla igual en los 3 primeros' ($r.Salida -match 'El original falla igual en los 3 primeros casos del job cargaJob con este test \(FAILED\): no ejecuto sus demas casos') (Cola $r.Salida)
  Igual 'remesaJob (3 casos): los 3 en el original' 'caso-01,caso-02,caso-03' (Casos-M77 $e 'original' 'remesaJob')
  Igual 'y los 3 en el migrado' 'caso-01,caso-02,caso-03' (Casos-M77 $e 'migrado' 'remesaJob')
}

$M77Orig = "El original no arranca el job cargaJob (NoSuchBeanDefinitionException: $M77Bean). Es el test del original, no el codigo: relanza con -RehacerOriginal."
$M77Igual = "El original falla igual en todos los casos de cargaJob (FAILED: $M77Fichero). El original funciona en produccion: es su test, no el codigo. Relanza con -RehacerOriginal."

$Pruebas['m77 (b1) la linea final sale una vez por job, con la clase y la causa, y sin -RehacerArnes para ese job; un job cuyo migrado no arranca sigue con la suya'] = {
  $e = Escenario-M77 'm77-b1' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00', 'importe=30.00', 'importe=40.00'); remesaJob = @('importe=10.00', 'importe=20.00') }) @{ Intentos = 1 }
  $r = Prueba-M77 $e 'orig-bean:^cargaJob/caso-' @() 'excepcion-mig:^remesaJob/caso-'
  Igual 'sale con 2' 2 $r.Codigo
  Comprueba 'la linea de cargaJob (parado), con la clase y la causa' ($r.Salida.Contains($M77Orig)) (Cola $r.Salida)
  Igual 'una sola linea de esas (la otra, la de la consola, dice "con este test")' 1 (Veces-M50 $r.Salida 'El original no arranca el job cargaJob (')
  Comprueba 'cargaJob no lleva la linea de -RehacerArnes del migrado' ($r.Salida -notmatch 'El migrado no arranca el job cargaJob') (Cola $r.Salida)
  Comprueba 'remesaJob (el migrado no arranca en ningun caso y el original si) conserva la suya' ($r.Salida.Contains('El migrado no arranca el job remesaJob en ningun caso (BeanCreationException: java.lang.IllegalStateException: sin correo). Casi siempre es el test del migrado, no el codigo: relanza con -RehacerArnes.')) (Cola $r.Salida)
  Comprueba 'y el original de remesaJob no se da por no arrancado ni por fallo igual' ($r.Salida -notmatch 'El original no arranca el job remesaJob' -and $r.Salida -notmatch 'El original falla igual en todos los casos de remesaJob') (Cola $r.Salida)
}

$Pruebas['m77 (b2) los dos lados con la misma excepcion de arranque (casos igual): la linea sale; con causas distintas en los 3 casos no sale ninguna'] = {
  $e = Escenario-M77 'm77-b2' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') }) @{ Intentos = 1 }
  $r = Prueba-M77 $e 'ambos-bean:^cargaJob/caso-'
  Igual 'los dos casos salen iguales' 'igual,igual' ((Resultados $e) -join ',')
  Igual 'sale con 0' 0 $r.Codigo
  Comprueba 'la linea de cargaJob sale' ($r.Salida.Contains($M77Orig)) (Cola $r.Salida)
  Igual 'una sola vez' 1 (Veces-M50 $r.Salida 'El original no arranca el job')
  $e = Escenario-M77 'm77-b2b' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00', 'importe=30.00') }) @{ Intentos = 1 }
  $r = Prueba-M77 $e 'orig-bean:^cargaJob/caso-01$;orig-creacion:^cargaJob/caso-0[23]$'
  Igual 'sin parar: sus 3 casos en el original' 'caso-01,caso-02,caso-03' (Casos-M77 $e 'original')
  Igual 'los 3 salen distintos' 'distinto,distinto,distinto' ((Resultados $e) -join ',')
  Comprueba 'y no sale ninguna linea del original' ($r.Salida -notmatch 'El original no arranca el job' -and $r.Salida -notmatch 'El original falla igual en todos') (Cola $r.Salida)
}

$Pruebas['m77 (b3) el original FAILED con la misma causa en todos los casos comparados (2 o mas): la linea de que falla igual, una vez, tambien en un job que se paro; con un caso distinto en medio, ninguna'] = {
  $e = Escenario-M77 'm77-b3' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00'); remesaJob = @('importe=10.00', 'importe=20.00', 'importe=30.00', 'importe=40.00'); tarifaJob = @('importe=10.00', 'importe=20.00', 'importe=30.00') }) @{ Intentos = 1 }
  $r = Prueba-M77 $e 'orig-failed:^cargaJob/caso-;orig-failed-caso:^remesaJob/caso-;orig-failed:^tarifaJob/caso-0[12]$'
  Igual 'sale con 2' 2 $r.Codigo
  Comprueba 'cargaJob (2 casos, sin parar): la linea de que falla igual' ($r.Salida.Contains($M77Igual)) (Cola $r.Salida)
  Comprueba 'remesaJob (se para tras 3): su linea, con la causa del primer caso' ($r.Salida.Contains('El original falla igual en todos los casos de remesaJob (FAILED: java.nio.file.NoSuchFileException: C:\datos\salida\caso-01\outbox). El original funciona en produccion: es su test, no el codigo. Relanza con -RehacerOriginal.')) (Cola $r.Salida)
  Comprueba 'tarifaJob (2 FAILED y un caso bien) no la lleva' ($r.Salida -notmatch 'El original falla igual en todos los casos de tarifaJob') (Cola $r.Salida)
  Igual 'dos lineas de esas, una por job' 2 (Veces-M50 $r.Salida 'El original falla igual en todos los casos de')
  Comprueba 'y ninguna es de no arranca (un FAILED no es una excepcion de arranque)' ($r.Salida -notmatch 'El original no arranca el job') (Cola $r.Salida)
  Comprueba 'ni lleva la linea de -RehacerArnes del migrado' ($r.Salida -notmatch 'El migrado no arranca el job') (Cola $r.Salida)
}

# ================================ LANZADOR ================================
Invoke-Banco $Pruebas $Script
