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
  Igual 'una fecha y hora UTC de otro dia que el local, pero de la ejecucion, sale igual que una local' 'x <hora>' $v['N1']
  Igual 'con T y fraccion, tambien' 'x <hora>' $v['N2']
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

$Pruebas['63 m20b (j): la huella cambia y el test guardado ya no compila: se llama a la IA como hoy, solo para ese arnes y sin el aviso de volver a escribir'] = {
  $e = Nuevo-Escenario 'm20b-huella-rota' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') })
  $r = Prueba $e
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  $n = @(Llamadas $e).Count
  foreach ($lado in @('original', 'migrado')) { Cambia-Huella $e $lado }
  Rompe-Arnes-Guardado $e 'original'
  $r = Prueba $e
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'una sola llamada: el arnes del original (el del migrado sigue valiendo)' ($n + 1) @(Llamadas $e).Count
  Comprueba 'el del migrado se usa sin llamar' ($r.Salida -match 'Arnes del migrado: bien \(el test de otro lanzamiento sigue valiendo\)') (Cola $r.Salida)
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

$Pruebas['65 m20b (l): una tarea de arnes hecha cuyo test guardado ya no vale sigue como hoy: se avisa de que se vuelve a escribir'] = {
  $e = Nuevo-Escenario 'm20b-hecha-rota' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') })
  $r = Prueba $e
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  $n = @(Llamadas $e).Count
  Rompe-Arnes-Guardado $e 'original'
  $r = Prueba $e
  Igual 'sale con 0' 0 $r.Codigo
  Comprueba 'dice que el test del original ya no vale y que se vuelve a escribir' ($r.Salida -match 'Arnes|test PruebaLocalTest del original de otro lanzamiento ya no vale' -and $r.Salida -match 'se vuelve a escribir') (Cola $r.Salida)
  Igual 'una llamada: el arnes del original' ($n + 1) @(Llamadas $e).Count
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
  Comprueba 'la consola dice que ya esta probado en este commit' ($r.Salida -match 'ya probado en este commit') (Cola $r.Salida)
  $rep = @(Reparaciones $e)
  Igual 'reparaciones sigue con una entrada, no arreglada' 'no arreglado' $rep[0].resultado
  Comprueba 'con el motivo de antes tras lo de ya probado' ($rep[0].motivo -match '^ya probado en este commit: ' -and $rep[0].motivo.Contains(($motivo -split "`n")[0])) $rep[0].motivo
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
  Comprueba 'y acaba con una linea Causa: y el ULTIMO Caused by' ($m.TrimEnd().EndsWith("`nCausa: " + $M28Fondo)) $m
  Comprueba 'no el primero' ($m -notmatch 'Causa: Caused by: org\.springframework') $m
  Comprueba 'el prompt del reintento (registro del intento 2) lleva esa causa' ($x.Reintento.Contains('Causa: ' + $M28Fondo)) (Cola $x.Reintento)
  Comprueba 'la consola la ensena' ($x.R.Salida.Contains('Causa: ' + $M28Fondo)) (Cola $x.R.Salida)
}

$Pruebas['m28 (b) un informe viejo de otra ejecucion y ninguno nuevo: el motivo no lleva la causa vieja ni Causa:'] = {
  $x = Arnes-Falla-Surefire 'm28-b' 'arnes-surefire-viejo'
  Igual 'sale con 1' 1 $x.R.Codigo
  $m = [string]$x.T.motivo
  Comprueba 'el motivo lleva las lineas [ERROR] de Maven' ($m -match '\[ERROR\] Failed to execute goal') $m
  Comprueba 'no lleva la causa vieja' ($m -notmatch 'causa-vieja') $m
  Comprueba 'ni una linea Causa:' ($m -notmatch '(?m)^Causa:') $m
  Comprueba 'el prompt del reintento tampoco' ($x.Reintento -and $x.Reintento -notmatch 'causa-vieja' -and $x.Reintento -notmatch '(?m)^Causa:') (Cola $x.Reintento)
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
  Comprueba 'el motivo acaba con Causa: y el ultimo Caused by de la salida' ($m.TrimEnd().EndsWith("`nCausa: " + $M28Fondo)) $m
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
  Comprueba 'no dice que ya estaba probada en este commit' ($r.Salida -notmatch 'ya probado en este commit') (Cola $r.Salida)
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
  Igual 'el segundo lanzamiento anade las suyas (las del original, dos veces, y el migrado) sin pisar las de antes' ($antes + 6) $t2.Count
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
  [System.IO.File]::WriteAllText($f, ('param([string]$Raiz)' + "`n" + (Texto-De-Funciones $Script @('Compare-Caso', 'Compare-Fichero', 'Get-LineasNormales', 'Sort-Tabla', 'Get-Normal', 'Get-Legible', 'Get-NotaJdk')) + "`n" + (Texto-De-Funciones (Join-Path (Split-Path -Parent $Script) 'comun.ps1') @('Get-Rel')) + "`n" + '$Latin = [System.Text.Encoding]::GetEncoding(28591); $Utf8 = New-Object System.Text.UTF8Encoding($false)' + "`n" + $cuerpo))
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
  $m = @(Llamadas-Arnes $e 'migrado')[1]
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

$Pruebas['m37 (a2) el caso de verdad: los dos arneses de antes (sin plantilla y con la huella de la plantilla de entonces): el del original se reutiliza sin llamar y el del migrado se escribe otra vez'] = {
  $e = Escenario-M29 'm37-a2' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba $e
  Igual 'la primera vez sale con 0' 0 $r.Codigo
  $original = Test-Guardado $e 'original'
  Deja-Tarea-M37 $e 'original' $null 'aaaaaaaa'
  Deja-Tarea-M37 $e 'migrado' $null 'bbbbbbbb'
  $r = Prueba $e
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'el del original: ninguna llamada nueva' 1 (Llamadas-Arnes $e 'original').Count
  Comprueba 'se reutiliza porque sigue valiendo' ($r.Salida -match 'Arnes del original: bien \(el test de otro lanzamiento sigue valiendo\)') (Cola $r.Salida)
  Igual 'el del migrado: una llamada nueva' 2 (Llamadas-Arnes $e 'migrado').Count
  Comprueba 'con la Info' ($r.Salida.Contains($AvisoM37)) (Cola $r.Salida)
  Comprueba 'y el del migrado guardado es el de la segunda llamada' ((Test-Guardado $e 'migrado').Contains('MARCA_ARNES=migrado-2'))
  Igual 'el del original guardado no cambia' $original (Test-Guardado $e 'original')
  Igual 'la tarea del migrado guarda la plantilla de ahora' (Plantilla-Ahora-M37) (Plantilla-Tarea-M37 $e 'migrado')
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

# ================================ LANZADOR ================================
Invoke-Banco $Pruebas $Script
