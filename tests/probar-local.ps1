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
function Prueba($E, [string[]]$A = @(), [string]$Guion = '') {
  $env:RESCATE_HOME = $E.Home
  $env:RESCATE_LLAMADAS = $E.Llamadas
  try { return Lanzar $Script (@('-Legacy', $E.Legacy, '-Migrado', $E.Migrado, '-Modelo', 'modelo-x', '-Si') + $A) $Guion }
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

$Pruebas['6 arnes prohibido: tocar src/main o meter una dependencia sin scope test se rechaza'] = {
  $e = Nuevo-Escenario 'arnes-main' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba $e @() 'arnes-toca-main:arnes-original'
  Igual 'sin arnes del original sale con 1' 1 $r.Codigo
  $t = Lee-Json (Get-Ruta $e.Local 'tareas/arnes-original.json')
  Igual 'el arnes del original queda atascado' 'atascada' $t.estado
  Comprueba 'con el fichero de src/main en el motivo' ($t.motivo -match 'src/main/java/Tocado\.java') $t.motivo
  Comprueba 'el fichero no queda en la copia' (-not (Test-Path -LiteralPath (Get-Ruta $e.CopiaOrig 'src/main/java/Tocado.java')))
  Comprueba 'dice que esta atascado y da el texto para Copilot' ($r.Salida -match 'atascad' -and $r.Salida -match 'Copilot') (Cola $r.Salida)
  Igual 'sin arnes del original no se prepara ningun caso' 0 @(Llamadas $e | Where-Object { $_.tipo -eq 'caso-local' }).Count
  $e = Nuevo-Escenario 'arnes-dep' ([ordered]@{ cargaJob = @('importe=10.00') })
  $r = Prueba $e @() 'arnes-dep-sin-test:arnes-original'
  Igual 'con una dependencia sin scope test sale con 1' 1 $r.Codigo
  $t = Lee-Json (Get-Ruta $e.Local 'tareas/arnes-original.json')
  Comprueba 'y el motivo habla del scope test' ($t.estado -eq 'atascada' -and $t.motivo -match 'scope') $t.motivo
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
  Igual 'los dos arneses, a la vez' 2 (Max-Simultaneas @(Llamadas $e | Where-Object { $_.tipo -eq 'arnes-local' }))
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
  Comprueba 'ficha-job sigue con sus claves de siempre' ($ficha -match '^CLAVES ficha-1 CITA_MAX=\d+;DATOS=d;JOB=cargaJob;PASOS=p;PASOS_MAX=\d+;SALIDA=\.rescate/tareas/ficha-1\.json$') "$ficha"
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
# tests/falsos/mvn-dormido.ps1 (escribe una linea, lanza un hijo que duerme y duerme 40 s) y un tope de 0.05 min (3 s).

# Esta el proceso $Num? Un zombi (estado Z en /proc/<pid>/stat) ya no corre: solo espera a su padre, y cuenta como muerto.
function Proceso-Vivo([int]$Num) {
  if (-not (Get-Process -Id $Num -ErrorAction SilentlyContinue)) { return $false }
  if (-not (Test-Path -LiteralPath "/proc/$Num/stat")) { return $true }
  try { return (([System.IO.File]::ReadAllText("/proc/$Num/stat") -replace '^.*\) ', '')[0] -ne 'Z') }
  catch { return $false }
}

# Lo que se comprueba en todo tope hecho con mvn-dormido.ps1: sus PID (el del falso y el de su hijo, en $CarpetaPids\pids.txt) ya
# no viven (10 s de plazo), la llamada ha tardado menos de $Limite s (el falso duerme 40) y el registro lleva lo que escribio.
function Comprueba-Tope([string]$CarpetaPids, [double]$Segundos, [int]$Limite, [string]$Registro) {
  $nums = @()
  $f = Join-Path $CarpetaPids 'pids.txt'
  if (Test-Path -LiteralPath $f) { $nums = @([System.IO.File]::ReadAllLines($f) | Where-Object { $_ } | ForEach-Object { [int]$_ }) }
  $plazo = (Get-Date).AddSeconds(10)
  do {
    $vivos = @($nums | Where-Object { Proceso-Vivo $_ })
    if ($vivos.Count -eq 0) { break }
    Start-Sleep -Milliseconds 200
  } while ((Get-Date) -lt $plazo)
  Comprueba 'el falso se colgo (anoto su PID y el de su hijo) y ninguno de los dos vive' ($nums.Count -ge 2 -and $vivos.Count -eq 0) ("PID: $($nums -join ' '), vivos: $($vivos -join ' ')")
  Comprueba "la llamada no espero al falso: menos de $Limite s" ($Segundos -lt $Limite) "$Segundos s"
  $texto = ''
  if (Test-Path -LiteralPath $Registro) { $texto = [System.IO.File]::ReadAllText($Registro) }
  Comprueba 'el registro lleva lo que Maven habia escrito' ($texto -match [regex]::Escape('[INFO] Running com.ejemplo.CuelgaTest')) "$Registro : $texto"
}

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
  $reloj = [System.Diagnostics.Stopwatch]::StartNew()
  try { $r = Prueba $E }
  finally { $env:RESCATE_MVN_FALSO = ''; $env:RESCATE_MVN_CUELGA = ''; $env:RESCATE_MVN_PIDS = '' }
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
  Comprueba-Tope $r.Pids $r.Segundos 30 $reg
}

$Pruebas['16 tope de Maven: prueba-local: un caso que se cuelga en el original no se da por bueno y su motivo lleva el mensaje'] = {
  $e = Nuevo-Escenario 'tope-original' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $r = Prueba-Con-Tope $e ([regex]::Escape($e.CopiaOrig) + '\|.*-Dprueba\.local\.caso=caso-01( |$)')
  $c = Caso $e 'cargaJob' 'caso-01'
  $motivo = "$($c.motivo)"
  Igual 'el caso que se cuelga: no se pudo preparar' 'no se pudo preparar' $c.resultado
  Comprueba 'y su motivo lleva el mensaje del tope' ($motivo -match [regex]::Escape('Maven se ha pasado del tope de 0.05 min')) $motivo
  Igual 'el otro caso sale igual' 'igual' (Caso $e 'cargaJob' 'caso-02').resultado
  Comprueba-Tope $r.Pids $r.Segundos 30 (Registro-Del-Tope $motivo)
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

# ================================ LANZADOR ================================
Invoke-Banco $Pruebas $Script
