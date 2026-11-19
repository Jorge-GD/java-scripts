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
# tests/falsos/mvn-dormido.ps1 (escribe una linea, lanza un hijo que duerme y duerme 40 s) y un tope de 0.05 min (3 s).

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

$Pruebas['54 m18 arnes (k4): la llamada cortada escribio el test (permitido) y toco src/main (prohibido): en la 2.a, el test sigue en la copia y src/main esta como en la base'] = {
  $e = Nuevo-Escenario 'm18-k4' ([ordered]@{ cargaJob = @('importe=10.00') })
  Ajustes-Arnes $e
  $r = Prueba $e @() 'colgado-toca-main:arnes-original'
  Igual 'sale con 0 (el segundo intento vale)' 0 $r.Codigo
  $p2 = Registro-Arnes $e 'original' 2
  Comprueba 'el motivo de la 1.a nombra el fichero de src/main que toco' ($p2 -match 'Tocado\.java') $p2
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

$Pruebas['m25 (b) -Reparar: la IA toca un test: rechazado con ese motivo, reintento y, al final, no arreglado; la rama de rescate no se mueve'] = {
  $e = Escenario-M25 'm25-b' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') }) -Test
  $antes = Estado-Git $e.Wt
  $r = Prueba $e @('-Reparar') 'reparar-test'
  Igual 'sale con 2 (el caso sigue distinto)' 2 $r.Codigo
  Igual 'el caso del limite sigue distinto' 'distinto,igual' ((Resultados $e) -join ',')
  Igual 'dos llamadas: el intento y el reintento' 2 (Llamadas-Reparar $e).Count
  Igual 'la rama de rescate no se mueve' $antes (Estado-Git $e.Wt)
  $rep = @(Reparaciones $e)
  Igual 'reparaciones: una entrada, no arreglado' 'no arreglado' $rep[0].resultado
  Igual 'con dos intentos' 2 $rep[0].intentos
  Comprueba 'el motivo nombra el test que ha tocado' ($rep[0].motivo -match 'src/test/java/com/acme/nuevo/ReglaTest\.java') $rep[0].motivo
  Comprueba 'y dice que solo se cambia src/main/' ($rep[0].motivo -match 'src/main/') $rep[0].motivo
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
  $e = Escenario-M25 'm25-g' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') }) -Sano
  $wt0 = GitEn $e.Wt @('rev-parse', 'HEAD')
  $r = Prueba $e @('-Reparar') 'reparar-test1'
  Igual 'sale con 0 (el reintento arregla)' 0 $r.Codigo
  Igual 'dos llamadas' 2 (Llamadas-Reparar $e).Count
  $uno = @(Registros-Reparar $e 1)[0]
  $dos = @(Registros-Reparar $e 2)[0]
  Comprueba 'el primer prompt no lleva la correccion' ($uno -notmatch 'CORRECCI') ''
  Comprueba 'el segundo si, con el test que toco' ($dos -match 'CORRECCI' -and $dos -match 'src/test/java/com/acme/nuevo/ReglaTest\.java') ''
  Comprueba 'y con el diff que se rechazo (el cambio de regla.txt y el del test)' ($dos -match 'diff --git a/src/main/resources/regla\.txt' -and $dos -match '\+minimo=5\.00' -and $dos -match 'diff --git a/src/test/java/com/acme/nuevo/ReglaTest\.java') ''
  Igual 'un commit nuevo' 1 (GitEn $e.Wt @('rev-list', '--count', "$wt0..HEAD"))
  Comprueba 'sin el test que la IA toco en el primer intento' (-not (Test-Path -LiteralPath (Get-Ruta $e.Wt 'src/test/java/com/acme/nuevo/ReglaTest.java'))) ''
  Igual 'la entrada dice arreglado con dos intentos' 'arreglado 2' ((@(Reparaciones $e)[0]).resultado + ' ' + (@(Reparaciones $e)[0]).intentos)
}

$Pruebas['m25 (h) -Reparar: relanzar con el mismo HEAD y la tarea atascada no llama a Copilot y lo dice'] = {
  $e = Escenario-M25 'm25-h' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') })
  $r = Prueba $e @('-Reparar') 'reparar-test'
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

$Pruebas['m26 (b) -Reparar: la IA arregla src/main/ y crea src/test/.../NuevoTest.java: rechazado nombrando ese fichero y src/main/, sin commit'] = {
  $e = Escenario-M25 'm26-b' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') })
  $antes = Estado-Git $e.Wt
  $r = Prueba $e @('-Reparar') 'reparar-test-nuevo'
  Igual 'sale con 2 (el caso sigue distinto)' 2 $r.Codigo
  Igual 'el caso del limite sigue distinto' 'distinto,igual' ((Resultados $e) -join ',')
  $rep = @(Reparaciones $e)
  Igual 'no arreglado' 'no arreglado' $rep[0].resultado
  Comprueba 'el motivo nombra el test nuevo' ($rep[0].motivo -match 'src/test/java/com/acme/nuevo/NuevoTest\.java') $rep[0].motivo
  Comprueba 'y dice que solo se cambia src/main/' ($rep[0].motivo -match 'src/main/') $rep[0].motivo
  Igual 'sin commit nuevo en la rama de rescate' $antes (Estado-Git $e.Wt)
  Comprueba 'lo nuevo bajo src/ no es ruido: la consola no dice que lo quita' ($r.Salida -notmatch 'Quito lo que ha dejado') (Cola $r.Salida)
  Comprueba 'el test nuevo se deshace en la copia' (-not (Test-Path -LiteralPath (Get-Ruta $e.CopiaMig 'src/test/java/com/acme/nuevo/NuevoTest.java'))) ''
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

$Pruebas['m26 (d) -Reparar: la IA arregla src/main/ y cambia pom.xml (con seguimiento): rechazado nombrando pom.xml, sin commit'] = {
  $e = Escenario-M25 'm26-d' ([ordered]@{ cargaJob = @('importe=5.00', 'importe=10.00') })
  $antes = Estado-Git $e.Wt
  $r = Prueba $e @('-Reparar') 'reparar-pom'
  Igual 'sale con 2 (el caso sigue distinto)' 2 $r.Codigo
  $rep = @(Reparaciones $e)
  Igual 'no arreglado' 'no arreglado' $rep[0].resultado
  Comprueba 'el motivo nombra pom.xml' ($rep[0].motivo -match 'pom\.xml') $rep[0].motivo
  Comprueba 'y dice que solo se cambia src/main/' ($rep[0].motivo -match 'src/main/') $rep[0].motivo
  Igual 'sin commit nuevo en la rama de rescate' $antes (Estado-Git $e.Wt)
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

$Pruebas['m27 (a) -JavaLegacy: la IA del original (arnes y casos) ve JAVA_HOME = -JavaLegacy, la del migrado ve el de antes, aunque vayan en la misma tanda'] = {
  $e = Nuevo-Escenario 'm27-a' ([ordered]@{ cargaJob = @('importe=10.00', 'importe=20.00') })
  $jdk = Join-Path $e.Raiz 'jdk-viejo'
  [void](New-Item -ItemType Directory -Path $jdk -Force)
  $proceso = Join-Path $e.Raiz 'jdk-del-proceso'
  $r = Prueba-Con-JavaHome $e @('-JavaLegacy', $jdk) $proceso
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'el arnes del original ve la carpeta de -JavaLegacy' $jdk (JavaHome-De $e 'arnes-original')
  Igual 'el arnes del migrado ve el JAVA_HOME de antes' $proceso (JavaHome-De $e 'arnes-migrado')
  Igual 'los dos fueron a la vez (la misma tanda)' 2 (Max-Simultaneas @(Llamadas $e | Where-Object { $_.id -like 'arnes-*' }))
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

# ================================ LANZADOR ================================
Invoke-Banco $Pruebas $Script
