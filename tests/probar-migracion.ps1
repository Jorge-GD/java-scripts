<#
probar-migracion.ps1 - Banco de pruebas de migracion.ps1.
No necesita Maven, Java ni Copilot: usa los programas de mentira de tests/falsos
y repos de juguete que crea en una carpeta temporal. Solo hace falta git.
Vale para Windows PowerShell 5.1 y para PowerShell 7. Solo ASCII a proposito.

  .\tests\probar-migracion.ps1                          # todas las pruebas
  .\tests\probar-migracion.ps1 -Solo cita               # las que llevan 'cita' en el nombre
  .\tests\probar-migracion.ps1 -Dir D:\tmp\x -Conservar # deja los repos de juguete para mirarlos
  .\tests\probar-migracion.ps1 -Script C:\otra\migracion.ps1

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
if (-not $Script) { $Script = Join-Path (Split-Path -Parent $aqui) 'migracion.ps1' }
$Script = (Resolve-Path -LiteralPath $Script).Path
$falsos = Join-Path $aqui 'falsos'
. (Join-Path $aqui 'comun-banco.ps1')

# ============================== UTILIDADES ==============================
# Lanza migracion.ps1 con RESCATE_HOME en la carpeta del escenario: nunca toca los ajustes reales.
function Migra($E, [string[]]$A, [string]$Guion = '', [string[]]$Entrada = @('')) {
  $env:RESCATE_HOME = $E.Home
  try { return Lanzar $Script $A $Guion $Entrada }
  finally { $env:RESCATE_HOME = '' }
}

# Argumentos de un arranque normal que no pregunta nada y no corrige.
function Basicos($E, [string]$Modelo = 'modelo-x') {
  return @('-Legacy', $E.Legacy, '-Migrado', $E.Migrado, '-Plantilla', $E.Plantilla, '-Modelo', $Modelo, '-SoloInforme')
}

function Lee-Json([string]$Ruta) {
  if (-not (Test-Path -LiteralPath $Ruta)) { return $null }
  return ([System.IO.File]::ReadAllText($Ruta) | ConvertFrom-Json)
}

function Estado($E) { return (Lee-Json (Get-Ruta $E.Out 'datos/estado.json')) }

function Tareas($E) {
  $d = Get-Ruta $E.Out 'datos/tareas'
  if (-not (Test-Path -LiteralPath $d)) { return @() }
  return @(Get-ChildItem -LiteralPath $d -File -Filter '*.json' | Sort-Object Name | ForEach-Object { Lee-Json $_.FullName })
}

function Fichas($E) {
  $d = Get-Ruta $E.Out 'datos/fichas'
  if (-not (Test-Path -LiteralPath $d)) { return @() }
  return @(Get-ChildItem -LiteralPath $d -File -Filter 'clase-*.json' | Sort-Object Name | ForEach-Object { Lee-Json $_.FullName })
}

function De-Clase($Lista, [string]$Clase) {
  return @($Lista | Where-Object { $_.fichero -like "*/$Clase.java" })
}

# Lo que dejo cada llamada del Copilot falso en $Carpeta/.rescate/falso: clave=valor por linea.
function Llamadas([string]$Carpeta) {
  $d = Join-Path (Join-Path $Carpeta '.rescate') 'falso'
  if (-not (Test-Path -LiteralPath $d)) { return @() }
  return @(Get-ChildItem -LiteralPath $d -File | Sort-Object Name | ForEach-Object {
      $o = [ordered]@{}
      foreach ($l in [System.IO.File]::ReadAllLines($_.FullName)) { $k, $v = ($l -split '=', 2); $o[$k] = $v }
      [pscustomobject]$o
    })
}

function Llamadas-De($Llamadas, [string]$Prefijo) { return @($Llamadas | Where-Object { $_.id -like ($Prefijo + '*') }) }

# Cuantas llamadas hubo a la vez como maximo, con las horas que dejo cada una.
function Max-Simultaneas($Llamadas) {
  $ev = @()
  foreach ($l in $Llamadas) {
    if ($l.inicio -and $l.fin) {
      $ev += [pscustomobject]@{ T = [long]$l.inicio; D = 1 }
      $ev += [pscustomobject]@{ T = [long]$l.fin; D = -1 }
    }
  }
  $max = 0; $cur = 0
  foreach ($x in @($ev | Sort-Object T, D)) { $cur += $x.D; if ($cur -gt $max) { $max = $cur } }
  return $max
}

function Cuenta-Estado($Tareas, [string]$Estado) { return @($Tareas | Where-Object { $_.estado -eq $Estado }).Count }

# ============================ REPOS DE JUGUETE ============================
function Pom([string]$Id) {
  return @"
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.acme</groupId>
  <artifactId>$Id</artifactId>
  <version>1.0.0</version>
</project>
"@
}

# Una clase de 11 lineas; las que acaban en ; (sin package) son la 5, la 8 y la 9.
function Clase-Juguete([string]$Nombre) {
  return @"
package com.acme.old;

/** Clase $Nombre. */
public class $Nombre {
    private int valor = 1;

    public int dobla(int x) {
        int r = x * 2;
        return r;
    }
}
"@
}

# Un escenario: el original (Legacy), la referencia, el migrado y la carpeta de ajustes (Home).
function Nuevo-Escenario([string]$Nombre, [string[]]$Clases = @('Clase1', 'Clase2', 'Clase3', 'Clase4', 'Clase5'), [hashtable]$Ajustes = @{}) {
  $raiz = Join-Path $Dir $Nombre
  if (Test-Path -LiteralPath $raiz) { Remove-Item -LiteralPath $raiz -Recurse -Force }
  $leg = Join-Path $raiz 'life-java8'
  $pl = Join-Path $raiz 'batch-terminado'
  $mig = Join-Path $raiz 'batch-life'
  $casa = Join-Path $raiz 'home'
  Escribe $leg 'pom.xml' (Pom 'life-java8')
  foreach ($c in $Clases) { Escribe $leg "src/main/java/com/acme/old/$c.java" (Clase-Juguete $c) }
  Escribe $pl 'pom.xml' (Pom 'plantilla')
  Escribe $pl 'src/main/java/com/acme/plantilla/App.java' "package com.acme.plantilla;`n`n/** Arranque. */`npublic class App {`n}`n"
  Escribe $mig 'pom.xml' (Pom 'batch')
  Escribe $mig 'src/main/java/com/acme/life/App.java' "package com.acme.life;`n`n/** Arranque. */`npublic class App {`n}`n"
  foreach ($d in @($leg, $pl, $mig)) { Inicia-Repo $d }
  $aj = [ordered]@{
    CopilotExe = (Join-Path $falsos 'copilot.ps1'); MvnExe = (Join-Path $falsos 'mvn.ps1'); JavaExe = (Join-Path $falsos 'java.ps1')
    SegundosPorLlamada = 20
  }
  foreach ($k in $Ajustes.Keys) { $aj[$k] = $Ajustes[$k] }
  Escribe $casa 'ajustes.json' (ConvertTo-Json -InputObject $aj)
  return [pscustomobject]@{
    Raiz = $raiz; Legacy = $leg; Plantilla = $pl; Migrado = $mig; Home = $casa
    Wt = ($mig + '-rescate'); Out = (Join-Path $mig 'migracion-batch')
  }
}

# ================================ PRUEBAS ================================
$Pruebas = [ordered]@{}

$Pruebas['1 arranque: valida lo que falta, guarda la referencia y no la vuelve a pedir'] = {
  $e = Nuevo-Escenario 'arranque' @('Clase1')
  $r = Migra $e @('-Migrado', $e.Migrado, '-Plantilla', $e.Plantilla, '-Modelo', 'modelo-x', '-SoloInforme')
  Igual 'sin -Legacy sale con 1' 1 $r.Codigo
  Comprueba 'dice que falta -Legacy' ($r.Salida -match '-Legacy') (Cola $r.Salida)
  $suelta = Join-Path $e.Raiz 'sin-git'
  Escribe $suelta 'pom.xml' (Pom 'x')
  $r = Migra $e @('-Legacy', $suelta, '-Migrado', $e.Migrado, '-Plantilla', $e.Plantilla, '-Modelo', 'modelo-x', '-SoloInforme')
  Igual 'un original sin repo git sale con 1' 1 $r.Codigo
  Comprueba 'dice que no es un repo git' ($r.Salida -match 'repo git') (Cola $r.Salida)
  $r = Migra $e ((Basicos $e) + '-Si')
  Igual '-SoloInforme y -Si a la vez salen con 1' 1 $r.Codigo
  $r = Migra $e @('-Legacy', $e.Legacy, '-Migrado', $e.Migrado, '-Modelo', 'modelo-x', '-SoloInforme')
  Igual 'sin referencia (ni guardada ni respondida) sale con 1' 1 $r.Codigo
  Comprueba 'dice que falta la referencia' ($r.Salida -match 'referencia') (Cola $r.Salida)
  [void](GitEn $e.Migrado @('checkout', '-q', '--detach'))
  $r = Migra $e (Basicos $e)
  Igual 'un migrado sin rama sale con 1' 1 $r.Codigo
  Comprueba 'dice que no esta en una rama (HEAD suelto)' ($r.Salida -match 'no esta en una rama \(HEAD suelto\)') (Cola $r.Salida)
  Comprueba 'y no llega a crear el worktree' (-not (Test-Path -LiteralPath $e.Wt))
  [void](GitEn $e.Migrado @('checkout', '-q', 'main'))
  Comprueba 'hasta aqui no hay worktree ni estado' ((-not (Test-Path -LiteralPath $e.Wt)) -and ($null -eq (Estado $e)))
  # la referencia se contesta por la entrada y se guarda
  $r = Migra $e @('-Legacy', $e.Legacy, '-Migrado', $e.Migrado, '-Modelo', 'modelo-x', '-SoloInforme') '' @($e.Plantilla)
  Igual 'con la referencia respondida sale con 0' 0 $r.Codigo
  $aj = Lee-Json (Get-Ruta $e.Home 'ajustes.json')
  Igual 'la referencia queda en ajustes.json' $e.Plantilla $aj.Plantilla
  Comprueba 'los demas ajustes se conservan' ($aj.SegundosPorLlamada -eq 20 -and $aj.CopilotExe) (Cola $r.Salida)
  $r = Migra $e @('-Legacy', $e.Legacy, '-Migrado', $e.Migrado, '-Modelo', 'modelo-x', '-SoloInforme')
  Igual 'sin -Plantilla usa la guardada y sale con 0' 0 $r.Codigo
  $s = Estado $e
  Igual 'estado: respuesta parar' 'parar' $s.respuesta
  Comprueba 'crea el worktree' (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))
  Igual 'la carpeta del migrado queda limpia (migracion-*/ excluida)' '' (GitEn $e.Migrado @('status', '--porcelain'))
  $r = Migra $e @('-Legacy', $e.Legacy, '-Migrado', $e.Migrado, '-Modelo', 'modelo-x', '-Si')
  Igual 'con -Si sale con 0' 0 $r.Codigo
  Igual 'estado: respuesta corregir' 'corregir' (Estado $e).respuesta
}

$Pruebas['2 aptitud: un Copilot que contesta texto libre para antes de crear tareas'] = {
  $e = Nuevo-Escenario 'aptitud' @('Clase1', 'Clase2')
  $r = Migra $e (Basicos $e) 'texto-libre'
  Igual 'sale con 1' 1 $r.Codigo
  Comprueba 'dice que falla la prueba de aptitud' ($r.Salida -match 'aptitud') (Cola $r.Salida)
  $ll = Llamadas (Get-Ruta $e.Out 'registros/aptitud')
  Igual 'la prueba se intenta dos veces' 2 $ll.Count
  Comprueba 'el reintento lleva la correccion' ($ll.Count -eq 2 -and $ll[1].correccion -eq 'True') (Cola $r.Salida)
  Igual 'no hay tareas' 0 (Tareas $e).Count
  Comprueba 'no hay worktree' (-not (Test-Path -LiteralPath $e.Wt))
  # una ficha valida pero sin ninguna cita que demuestre nada tampoco pasa la aptitud
  $r = Migra $e (Basicos $e) 'sin-datos:^ValidadorImporte$'
  Igual 'una ficha sin datos no pasa la aptitud: sale con 1' 1 $r.Codigo
  Comprueba 'dice por que' ($r.Salida -match 'ningun dato') (Cola $r.Salida)
  # y con un Copilot que responde bien, pasa
  $r = Migra $e (Basicos $e)
  Igual 'con un Copilot que responde bien sale con 0' 0 $r.Codigo
}

$Pruebas['3 fichas: cinco clases con el falso lento, nunca mas de 4 a la vez'] = {
  $e = Nuevo-Escenario 'fichas'
  $r = Migra $e (Basicos $e) 'lento:^Clase'
  Igual 'sale con 0' 0 $r.Codigo
  $t = Tareas $e
  Igual 'hay 5 tareas' 5 $t.Count
  Igual 'las 5 estan hechas' 5 (Cuenta-Estado $t 'hecha')
  $f = Fichas $e
  Igual 'salen 5 fichas' 5 $f.Count
  Comprueba 'cada ficha trae su fichero y sus datos probados' (@($f | Where-Object { $_.fichero -like 'src/main/java/com/acme/old/Clase*.java' -and $_.datos.Count -eq 2 -and @($_.datos | Where-Object { -not $_.probado }).Count -eq 0 }).Count -eq 5) (Cola $r.Salida)
  $ll = Llamadas-De (Llamadas $e.Wt) 'clase-'
  Igual 'cinco llamadas' 5 $ll.Count
  Igual 'como mucho 4 a la vez, y llegan a 4' 4 (Max-Simultaneas $ll)
  Igual 'el worktree queda limpio' '' (GitEn $e.Wt @('status', '--porcelain'))
  Igual 'estado: fase' 'fichas-clase-hechas' (Estado $e).fase
  Comprueba 'las 5 lecturas llevan --no-custom-instructions' (@($ll | Where-Object { $_.flags -match '--no-custom-instructions' }).Count -eq 5) (($ll | ForEach-Object { $_.flags }) -join ' | ')
  $la = @(Llamadas (Get-Ruta $e.Out 'registros/aptitud'))
  Comprueba 'la prueba de aptitud tambien' ($la.Count -eq 1 -and $la[0].flags -match '--no-custom-instructions') (($la | ForEach-Object { $_.flags }) -join ' | ')
  Comprueba 'las 5 lecturas llevan --add-dir del original' (@($ll | Where-Object { $_.flags -match '--add-dir=\S*life-java8' }).Count -eq 5) (($ll | ForEach-Object { $_.flags }) -join ' | ')
}

$Pruebas['4 cita inventada: probado false; con mas de la mitad inventadas, reintento y atascada'] = {
  $e = Nuevo-Escenario 'cita' @('Mixta', 'Falsa', 'Bien')
  $r = Migra $e (Basicos $e) 'cita-inventada:^Mixta$;citas-inventadas:^Falsa$'
  Igual 'sale con 0' 0 $r.Codigo
  $t = Tareas $e
  $m = @(De-Clase (Fichas $e) 'Mixta')
  Igual 'Mixta tiene ficha' 1 $m.Count
  if ($m.Count -eq 1) {
    Igual 'Mixta: lineas' '5 8 3' (($m[0].datos | ForEach-Object { $_.linea }) -join ' ')
    Igual 'Mixta: probado (la cita que sale en otra linea cuenta y la inventada no)' 'True True False' (($m[0].datos | ForEach-Object { $_.probado }) -join ' ')
  }
  $f = @($t | Where-Object { $_.entradas.fichero -like '*/Falsa.java' })
  Igual 'Falsa: atascada' 'atascada' $f[0].estado
  Igual 'Falsa: dos intentos' 2 $f[0].intentos
  Comprueba 'Falsa: el motivo habla de las citas' ($f[0].motivo -match 'citas') $f[0].motivo
  Igual 'Falsa: no tiene ficha' 0 (De-Clase (Fichas $e) 'Falsa').Count
  Igual 'Bien: hecha' 'hecha' @($t | Where-Object { $_.entradas.fichero -like '*/Bien.java' })[0].estado
  $ll = Llamadas-De (Llamadas $e.Wt) $f[0].id
  Igual 'Falsa: dos llamadas' 2 $ll.Count
  Comprueba 'Falsa: el reintento lleva la correccion y esfuerzo high' ($ll.Count -eq 2 -and $ll[1].correccion -eq 'True' -and $ll[1].flags -match '--effort=high' -and $ll[0].flags -notmatch '--effort=high') (($ll | ForEach-Object { $_.flags }) -join ' | ')
}

$Pruebas['5 JSON roto: reintento y atascada; las demas tareas siguen'] = {
  $e = Nuevo-Escenario 'json' @('Roto', 'UnaVez', 'Sana1', 'Sana2')
  $r = Migra $e (Basicos $e) 'json-roto:^Roto$;una-vez-roto:^UnaVez$'
  Igual 'sale con 0' 0 $r.Codigo
  $t = Tareas $e
  $ro = @($t | Where-Object { $_.entradas.fichero -like '*/Roto.java' })[0]
  Igual 'Roto: atascada' 'atascada' $ro.estado
  Igual 'Roto: dos intentos' 2 $ro.intentos
  Comprueba 'Roto: el motivo dice que el JSON no vale' ($ro.motivo -match 'JSON') $ro.motivo
  Igual 'Roto: dos llamadas' 2 (Llamadas-De (Llamadas $e.Wt) $ro.id).Count
  $uv = @($t | Where-Object { $_.entradas.fichero -like '*/UnaVez.java' })[0]
  Igual 'UnaVez: hecha en el segundo intento' 'hecha 2' ("$($uv.estado) $($uv.intentos)")
  $lluv = Llamadas-De (Llamadas $e.Wt) $uv.id
  Comprueba 'UnaVez: el reintento lleva la correccion, esfuerzo high y el modelo' ($lluv.Count -eq 2 -and $lluv[1].correccion -eq 'True' -and $lluv[1].flags -match '--effort=high' -and $lluv[1].flags -match '--model=modelo-x') (($lluv | ForEach-Object { $_.flags }) -join ' | ')
  Igual 'las sanas estan hechas' 2 @($t | Where-Object { $_.entradas.fichero -match '/Sana\d\.java$' -and $_.estado -eq 'hecha' }).Count
  Igual 'hay 3 fichas' 3 (Fichas $e).Count
}

$Pruebas['6 colgada: se mata al pasar el tope y la tarea queda atascada'] = {
  $e = Nuevo-Escenario 'colgada' @('Cuelga', 'Sana1', 'Sana2') @{ SegundosPorLlamada = 5 }
  $reloj = [System.Diagnostics.Stopwatch]::StartNew()
  $r = Migra $e (Basicos $e) 'colgado:^Cuelga$'
  $seg = $reloj.Elapsed.TotalSeconds
  Igual 'sale con 0' 0 $r.Codigo
  Comprueba "no espera a la llamada colgada (tardo $([int]$seg) s)" ($seg -lt 100)
  $t = Tareas $e
  $c = @($t | Where-Object { $_.entradas.fichero -like '*/Cuelga.java' })[0]
  Igual 'Cuelga: atascada' 'atascada' $c.estado
  Comprueba 'Cuelga: el motivo habla del tiempo' ($c.motivo -match 'tiempo') $c.motivo
  $ll = Llamadas-De (Llamadas $e.Wt) $c.id
  Igual 'Cuelga: dos llamadas' 2 $ll.Count
  Comprueba 'ninguna llegara a acabar' (@($ll | Where-Object { $_.fin }).Count -eq 0)
  Comprueba 'y ninguna sigue viva: se mataron' (@($ll | Where-Object { Get-Process -Id ([int]$_.pid) -ErrorAction SilentlyContinue }).Count -eq 0) (($ll | ForEach-Object { $_.pid }) -join ' ')
  Igual 'las sanas estan hechas' 2 (Cuenta-Estado $t 'hecha')
  Comprueba 'queda el registro de la llamada' (Test-Path -LiteralPath (Join-Path (Join-Path $e.Out 'registros') ($c.id + '-1.log')))
}

$Pruebas['7 lectura que toca codigo: se deshace y el worktree queda limpio'] = {
  $e = Nuevo-Escenario 'toca' @('Clase1', 'Clase2', 'Clase3')
  $r = Migra $e (Basicos $e) 'toca-codigo:^Clase'
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'el worktree queda limpio' '' (GitEn $e.Wt @('status', '--porcelain'))
  Igual 'no hay commits nuevos' 'inicial' (GitEn $e.Wt @('log', '--format=%s'))
  Igual 'App.java sigue como estaba' (Lee $e.Migrado 'src/main/java/com/acme/life/App.java') (Lee $e.Wt 'src/main/java/com/acme/life/App.java')
  $t = Tareas $e
  Igual 'las 3 tareas quedan atascadas' 3 (Cuenta-Estado $t 'atascada')
  Comprueba 'el motivo dice que toco ficheros' (@($t | Where-Object { $_.motivo -match 'toco' }).Count -eq 3) $t[0].motivo
  Igual 'no hay fichas (la ronda cuenta como fallida)' 0 (Fichas $e).Count
}

$Pruebas['8 seis fallos seguidos: parada copilot-no-responde con su ayuda'] = {
  $e = Nuevo-Escenario 'fallos' @('Clase1', 'Clase2', 'Clase3', 'Clase4', 'Clase5', 'Clase6', 'Clase7')
  $r = Migra $e (Basicos $e) 'falla-siempre:^Clase'
  Igual 'sale con 2' 2 $r.Codigo
  $s = Estado $e
  Igual 'parada: motivo' 'copilot-no-responde' $s.parada.motivo
  Comprueba 'parada: detalle, registro y ayuda' ($s.parada.detalle -and $s.parada.registro -and $s.parada.ayuda) (Cola $r.Salida)
  Comprueba 'la ayuda nombra el motivo y el registro' ($s.parada.ayuda -match 'copilot-no-responde' -and $s.parada.ayuda.Contains($s.parada.registro))
  Comprueba 'el registro existe' ($s.parada.registro -and (Test-Path -LiteralPath $s.parada.registro))
  $n = (Llamadas-De (Llamadas $e.Wt) 'clase-').Count
  Comprueba "paro tras 6 a 8 llamadas (hubo $n)" ($n -ge 6 -and $n -le 8)
  $t = Tareas $e
  Igual 'ninguna tarea hecha' 0 (Cuenta-Estado $t 'hecha')
  Igual 'ninguna atascada: el fallo es de Copilot, no de la tarea' 0 (Cuenta-Estado $t 'atascada')
  # al relanzar con un Copilot que responde, sigue y limpia la parada
  $r = Migra $e (Basicos $e)
  Igual 'relanzado sale con 0' 0 $r.Codigo
  Igual 'relanzado: 7 hechas' 7 (Cuenta-Estado (Tareas $e) 'hecha')
  Comprueba 'relanzado: sin parada' ($null -eq (Estado $e).parada)
}

$Pruebas['9 corte y relanzar: no se repite ninguna tarea hecha'] = {
  $e = Nuevo-Escenario 'corte' @('Clase1', 'Clase2', 'Clase3', 'Clase4', 'Clase5', 'Clase6')
  $r = Migra $e ((Basicos $e) + @('-MaxHoras', '0.00001'))
  Igual 'con tope de tiempo sale con 0 (no es un error)' 0 $r.Codigo
  Igual 'parada: tope-de-tiempo' 'tope-de-tiempo' (Estado $e).parada.motivo
  $t = Tareas $e
  Igual 'se hace una ronda entera (4 hechas)' 4 (Cuenta-Estado $t 'hecha')
  Igual 'quedan 2 pendientes' 2 (Cuenta-Estado $t 'pendiente')
  $r = Migra $e (Basicos $e)
  Igual 'relanzado sale con 0' 0 $r.Codigo
  $t = Tareas $e
  Igual 'ahora estan las 6 hechas' 6 (Cuenta-Estado $t 'hecha')
  $ll = Llamadas-De (Llamadas $e.Wt) 'clase-'
  Igual 'seis llamadas en total: ninguna tarea se repite' 6 $ll.Count
  Igual 'cada tarea se llamo una vez' 6 @($ll | Select-Object -ExpandProperty id -Unique).Count
  Comprueba 'al relanzar no repite la prueba de aptitud' ($r.Salida -match 'ya pasada') (Cola $r.Salida)
  Igual 'seis fichas' 6 (Fichas $e).Count
  Comprueba 'relanzado: sin parada' ($null -eq (Estado $e).parada)
}

$Pruebas['10 guardas: si cambia el original, parada guardas y el worktree queda limpio'] = {
  $e = Nuevo-Escenario 'guardas' @('Clase1', 'Clase2')
  $r = Migra $e (Basicos $e) 'toca-original:^Clase1$'
  Igual 'sale con 2' 2 $r.Codigo
  Igual 'parada: guardas' 'guardas' (Estado $e).parada.motivo
  Igual 'el worktree queda limpio' '' (GitEn $e.Wt @('status', '--porcelain'))
}

$Pruebas['11 trozos: un fichero largo se trocea y las fichas se juntan'] = {
  $e = Nuevo-Escenario 'trozos' @('Clase1') @{ LineasPorTarea = 6 }
  $r = Migra $e (Basicos $e)
  Igual 'sale con 0' 0 $r.Codigo
  $t = Tareas $e
  Igual 'dos tareas' 2 $t.Count
  Igual 'los rangos' '1-6 7-11' (($t | ForEach-Object { "$($_.entradas.desde)-$($_.entradas.hasta)" }) -join ' ')
  $f = Fichas $e
  Igual 'una ficha' 1 $f.Count
  if ($f.Count -eq 1) { Igual 'con los datos de los dos trozos' '5 8 9' (($f[0].datos | ForEach-Object { $_.linea }) -join ' ') }
  $p = @(Get-ChildItem -LiteralPath (Get-Ruta $e.Wt '.rescate/tareas') -Filter '*.prompt.md' | ForEach-Object { [System.IO.File]::ReadAllText($_.FullName) })
  Comprueba 'cada prompt lleva su rango' (@($p | Where-Object { $_ -match '(?m)^LINEAS: 1-6\r?$' }).Count -eq 1 -and @($p | Where-Object { $_ -match '(?m)^LINEAS: 7-11\r?$' }).Count -eq 1)
}

$Pruebas['14 el banco del motor sigue en 75 de 75'] = {
  $r = Lanzar (Join-Path $aqui 'probar.ps1') @('-Dir', (Join-Path $Dir 'motor'))
  Comprueba 'probar.ps1 pasa sus 75 comprobaciones' ($r.Codigo -eq 0 -and $r.Salida -match 'TODO BIEN: 75 comprobaciones') (Cola $r.Salida)
}

# ============================ BIBLIOTECA Y LANZADOR ============================
# Lanza un script de prueba que carga comun.ps1 y tareas.ps1 (nunca migracion.ps1), como haria un preflight.
function En-Biblioteca([string]$Nombre, [string]$Codigo) {
  $raiz = Split-Path -Parent $Script
  $cab = "`$ErrorActionPreference = 'Stop'`n. '" + (Join-Path $raiz 'comun.ps1') + "'`n. '" + (Join-Path $raiz 'tareas.ps1') + "'`n"
  $carpeta = Join-Path $Dir 'biblioteca'
  Escribe $carpeta "$Nombre.ps1" ($cab + $Codigo)
  return (Lanzar (Join-Path $carpeta "$Nombre.ps1") @())
}

function Funciones-De([string]$Ruta) {
  return @([regex]::Matches([System.IO.File]::ReadAllText($Ruta), '(?m)^function ([\w-]+)') | ForEach-Object { $_.Groups[1].Value })
}

$Pruebas['15 biblioteca: tareas.ps1 se carga sola, nombra sus variables y sirve para la aptitud sin arranque'] = {
  $raiz = Split-Path -Parent $Script
  $lib = Join-Path $raiz 'tareas.ps1'
  Comprueba 'existe tareas.ps1' (Test-Path -LiteralPath $lib)
  if (-not (Test-Path -LiteralPath $lib)) { return }
  $cab = [regex]::Match([System.IO.File]::ReadAllText($lib), '(?s)^<#.*?#>').Value
  foreach ($v in @('$Cfg', '$LegacyRoot', '$Registros', '$ModeloElegido', '$Datos')) {
    Comprueba "la cabecera nombra $v" $cab.Contains($v)
  }
  $deTareas = Funciones-De $lib
  $deMigra = Funciones-De $Script
  foreach ($f in @('Test-Aptitud', 'Invoke-Llamadas', 'Invoke-Ronda', 'Get-Lanzador', 'Get-TareasFichas', 'Test-Ficha', 'Read-Json', 'Write-Json', 'Get-Hash8', 'Stop-Arranque', 'Set-Despierto')) {
    Comprueba "$f esta en tareas.ps1 y no en migracion.ps1" (($deTareas -contains $f) -and ($deMigra -cnotcontains $f))
  }
  $todas = @($deTareas) + @($deMigra) + @(Funciones-De (Join-Path $raiz 'comun.ps1'))
  $dup = @($todas | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
  Comprueba 'ninguna funcion esta definida dos veces entre comun, tareas y migracion' ($dup.Count -eq 0) ($dup -join ', ')
  $e = Nuevo-Escenario 'biblioteca' @('Clase1')
  $codigo = @'
$Cfg.CopilotExe = '{{COPILOT}}'
$Cfg.SegundosPorLlamada = 20
$LegacyRoot = '{{LEGACY}}'
$Registros = '{{REGISTROS}}'
$ModeloElegido = 'modelo-x'
$mal = Test-Aptitud
if ($mal) { 'MAL: ' + $mal; exit 3 }
'APTITUD-OK'
'@
  $codigo = $codigo.Replace('{{COPILOT}}', (Join-Path $falsos 'copilot.ps1')).Replace('{{LEGACY}}', $e.Legacy).Replace('{{REGISTROS}}', (Get-Ruta $e.Out 'registros'))
  $r = En-Biblioteca 'aptitud' $codigo
  Igual 'la aptitud corre con solo esas variables y sale con 0' 0 $r.Codigo
  Comprueba 'dice APTITUD-OK' ($r.Salida -match 'APTITUD-OK') (Cola $r.Salida)
  Igual 'una sola llamada de aptitud' 1 (Llamadas (Get-Ruta $e.Out 'registros/aptitud')).Count
  Comprueba 'no ha creado estado.json (no hay arranque)' ($null -eq (Estado $e))
}

$Pruebas['16 lanzador: sin ExecutionPolicy, comillas para cmd y equipo despierto'] = {
  $raiz = Split-Path -Parent $Script
  if (-not (Test-Path -LiteralPath (Join-Path $raiz 'tareas.ps1'))) { Comprueba 'existe tareas.ps1' $false; return }
  $cmd = Join-Path (Join-Path $Dir 'lanzador') 'ejemplo.cmd'
  Escribe (Join-Path $Dir 'lanzador') 'ejemplo.cmd' "@echo off`n"
  if ($env:OS -ne 'Windows_NT') { & chmod +x $cmd }
  $codigo = @'
'DESPIERTO_SI=' + (Set-Despierto $true)
'DESPIERTO_NO=' + (Set-Despierto $false)
$env:OS = 'Windows_NT'
$env:ComSpec = 'cmd.exe'
'PS1=' + (Get-Lanzador '{{PS1}}' @('-p', 'a&b', 'dos palabras')).Args
'CMD=' + (Get-Lanzador '{{CMD}}' @('-p', 'a&b', 'x(y)', 'z^w', 'a|b', 'c<d', 'e>f', 'dos palabras', 'llano')).Args
'WIN=' + (Set-Despierto $true)
'FIN'
'@
  $codigo = $codigo.Replace('{{PS1}}', (Join-Path $falsos 'copilot.ps1')).Replace('{{CMD}}', $cmd)
  $r = En-Biblioteca 'lanzador' $codigo
  Igual 'el script de prueba sale con 0' 0 $r.Codigo
  Comprueba 'Set-Despierto devuelve True fuera de Windows (activar)' ($r.Salida -match '(?m)^DESPIERTO_SI=True\r?$') (Cola $r.Salida)
  Comprueba 'Set-Despierto devuelve True fuera de Windows (soltar)' ($r.Salida -match '(?m)^DESPIERTO_NO=True\r?$') (Cola $r.Salida)
  Comprueba 'Set-Despierto no lanza ni con un Windows simulado' ($r.Salida -match '(?m)^WIN=(True|False)\r?$' -and $r.Salida -match '(?m)^FIN\r?$') (Cola $r.Salida)
  $ps1 = ''; if ($r.Salida -match '(?m)^PS1=(.*)$') { $ps1 = $Matches[1] }
  Comprueba 'un .ps1 no lleva -ExecutionPolicy: la politica es la del padre' ($ps1 -and $ps1 -notmatch 'ExecutionPolicy' -and $ps1 -notmatch 'Bypass') $ps1
  Comprueba 'un .ps1 no pone comillas a & (no pasa por cmd)' ($ps1.Contains(' a&b ')) $ps1
  $c = ''; if ($r.Salida -match '(?m)^CMD=(.*)$') { $c = $Matches[1] }
  Comprueba 'un .cmd va por cmd /d /s /c' ($c.StartsWith('/d /s /c "')) $c
  foreach ($a in @('a&b', 'x(y)', 'z^w', 'a|b', 'c<d', 'e>f', 'dos palabras')) {
    Comprueba "un .cmd entrecomilla '$a'" ($c.Contains('"' + $a + '"')) $c
  }
  Comprueba 'un .cmd no entrecomilla lo que no hace falta' ($c.EndsWith(' llano"') -and -not $c.Contains('"llano"')) $c
}

# ============================== RELANZAR, ERRORES, ORIGEN, LIMITE ==============================
$Pruebas['17 atascadas: no se repiten al relanzar salvo con -Reintentar o con otro modelo'] = {
  $e = Nuevo-Escenario 'atascadas' @('Rota', 'Sana1')
  $r = Migra $e (Basicos $e) 'json-roto:^Rota$'
  Igual 'primer lanzamiento sale con 0' 0 $r.Codigo
  $ro = @(Tareas $e | Where-Object { $_.entradas.fichero -like '*/Rota.java' })[0]
  $id = $ro.id
  Igual 'Rota: atascada' 'atascada' $ro.estado
  Igual 'Rota: dos llamadas' 2 (Llamadas-De (Llamadas $e.Wt) $id).Count
  # 1: relanzar, mismo modelo: no la llama otra vez
  $r = Migra $e (Basicos $e)
  Igual 'relanzado sale con 0' 0 $r.Codigo
  Igual 'Rota sigue atascada' 'atascada' @(Tareas $e | Where-Object { $_.id -eq $id })[0].estado
  Igual 'no hay ninguna llamada nueva para ella' 2 (Llamadas-De (Llamadas $e.Wt) $id).Count
  Comprueba 'avisa de que la conserva y de -Reintentar' ($r.Salida -match 'Reintentar') (Cola $r.Salida)
  # 2: con -Reintentar si (y como el falso la rompe otra vez, queda atascada de nuevo)
  $r = Migra $e ((Basicos $e) + '-Reintentar') 'json-roto:^Rota$'
  Igual 'con -Reintentar sale con 0' 0 $r.Codigo
  Igual 'con -Reintentar la llama otra vez (dos llamadas mas)' 4 (Llamadas-De (Llamadas $e.Wt) $id).Count
  # 3: con otro modelo si
  $r = Migra $e (Basicos $e 'otro-modelo') 'json-roto:^Rota$'
  Igual 'con otro modelo sale con 0' 0 $r.Codigo
  $ll = Llamadas-De (Llamadas $e.Wt) $id
  Igual 'con otro modelo la llama otra vez (dos llamadas mas)' 6 $ll.Count
  Comprueba 'las nuevas llevan el otro modelo' (@($ll | Where-Object { $_.flags -match '--model=otro-modelo' }).Count -eq 2) (($ll | ForEach-Object { $_.flags }) -join ' | ')
  # con ese mismo modelo otra vez: se conserva
  $r = Migra $e (Basicos $e 'otro-modelo')
  Igual 'con el modelo de la ultima vez no la llama' 6 (Llamadas-De (Llamadas $e.Wt) $id).Count
  Igual 'la sana no se repitio nunca' 1 (Llamadas-De (Llamadas $e.Wt) (@(Tareas $e | Where-Object { $_.entradas.fichero -like '*/Sana1.java' })[0].id)).Count
  # y con -Reintentar y un Copilot que responde, se arregla
  $r = Migra $e ((Basicos $e 'otro-modelo') + '-Reintentar')
  Igual 'con -Reintentar y un Copilot que responde sale con 0' 0 $r.Codigo
  Igual 'Rota queda hecha' 'hecha' @(Tareas $e | Where-Object { $_.id -eq $id })[0].estado
  Igual 'y tiene su ficha' 2 (Fichas $e).Count
}

$Pruebas['18 error interno: una excepcion deja parada error-interno y sale con 2'] = {
  $e = Nuevo-Escenario 'interno' @('Clase1', 'Clase2')
  Escribe $e.Out 'datos/fichas' 'esto es un fichero donde tendria que haber una carpeta'
  $r = Migra $e (Basicos $e)
  Igual 'sale con 2' 2 $r.Codigo
  $s = Estado $e
  Comprueba 'hay estado.json' ($null -ne $s) (Cola $r.Salida)
  if ($null -eq $s) { return }
  Igual 'parada: motivo' 'error-interno' $s.parada.motivo
  Comprueba 'parada: el detalle lleva el mensaje y fichero:linea' ($s.parada.detalle -match '\.ps1:\d+') "$($s.parada.detalle)"
  Igual 'parada: registro es la carpeta de registros' (Get-Ruta $e.Out 'registros') $s.parada.registro
  Comprueba 'parada: la ayuda nombra el motivo' ($s.parada.ayuda -match 'error-interno')
  Comprueba 'la salida dice la parada' ($r.Salida -match 'error-interno') (Cola $r.Salida)
}

$Pruebas['19 original: sin .java falla al arrancar; con varios modulos lee todos'] = {
  $e = Nuevo-Escenario 'vacio' @()
  $r = Migra $e (Basicos $e)
  Igual 'un original sin .java sale con 1' 1 $r.Codigo
  Comprueba 'dice que no hay ficheros .java' ($r.Salida -match 'no hay ningun \.java|No hay ningun \.java') (Cola $r.Salida)
  Igual 'no llega a la prueba de aptitud' 0 (Llamadas (Get-Ruta $e.Out 'registros/aptitud')).Count
  Comprueba 'ni crea el worktree ni el estado' ((-not (Test-Path -LiteralPath $e.Wt)) -and ($null -eq (Estado $e)))
  # dos modulos, con ruido que no se lee
  $e = Nuevo-Escenario 'modulos' @()
  Escribe $e.Legacy 'modA/src/main/java/com/acme/ClaseA.java' (Clase-Juguete 'ClaseA')
  Escribe $e.Legacy 'modB/sub/src/main/java/com/acme/ClaseB.java' (Clase-Juguete 'ClaseB')
  Escribe $e.Legacy 'modA/src/test/java/com/acme/ClaseATest.java' (Clase-Juguete 'ClaseATest')
  Escribe $e.Legacy 'modA/target/gen/src/main/java/com/acme/Generada.java' (Clase-Juguete 'Generada')
  Escribe $e.Legacy 'node_modules/x/src/main/java/Ruido.java' (Clase-Juguete 'Ruido')
  Escribe $e.Legacy 'docs/Suelta.java' (Clase-Juguete 'Suelta')
  [void](GitEn $e.Legacy @('add', '-A'))
  [void](GitEn $e.Legacy @('commit', '-q', '-m', 'modulos'))
  $r = Migra $e (Basicos $e)
  Igual 'con dos modulos sale con 0' 0 $r.Codigo
  $t = Tareas $e
  Igual 'solo hay dos tareas (ni tests, ni target, ni node_modules, ni sueltos)' 2 $t.Count
  $f = Fichas $e
  Igual 'hay una ficha de cada modulo' 'ClaseA ClaseB' ((@($f | ForEach-Object { $_.clase }) | Sort-Object) -join ' ')
  Comprueba 'las rutas son relativas al original' (@($f | Where-Object { $_.fichero -eq 'modA/src/main/java/com/acme/ClaseA.java' }).Count -eq 1) (($f | ForEach-Object { $_.fichero }) -join ' ')
  # sin ningun src/main/java: todos los .java menos src/test, target y .git
  $e = Nuevo-Escenario 'sueltos' @()
  Escribe $e.Legacy 'fuentes/com/acme/Suelta.java' (Clase-Juguete 'Suelta')
  Escribe $e.Legacy 'src/test/java/SoloTest.java' (Clase-Juguete 'SoloTest')
  Escribe $e.Legacy 'target/Generada.java' (Clase-Juguete 'Generada')
  [void](GitEn $e.Legacy @('add', '-A'))
  [void](GitEn $e.Legacy @('commit', '-q', '-m', 'sueltos'))
  $r = Migra $e (Basicos $e)
  Igual 'sin src/main/java sale con 0' 0 $r.Codigo
  Igual 'lee solo el que no es test ni target' 'fuentes/com/acme/Suelta.java' (@(Tareas $e | ForEach-Object { $_.entradas.fichero }) -join ' ')
}

$Pruebas['20 limite: -Limite N hace solo N tareas, sin parada, y relanzar hace el resto'] = {
  $e = Nuevo-Escenario 'limite'
  $r = Migra $e ((Basicos $e) + @('-Limite', '2'))
  Igual 'sale con 0' 0 $r.Codigo
  $t = Tareas $e
  Igual 'dos hechas' 2 (Cuenta-Estado $t 'hecha')
  Igual 'tres pendientes' 3 (Cuenta-Estado $t 'pendiente')
  Igual 'dos fichas' 2 (Fichas $e).Count
  Igual 'dos llamadas' 2 (Llamadas-De (Llamadas $e.Wt) 'clase-').Count
  Comprueba 'sin parada' ($null -eq (Estado $e).parada)
  Igual 'la fase sigue en lectura' 'fichas-clase' (Estado $e).fase
  Comprueba 'el mensaje dice cuantas quedan' ($r.Salida -match 'quedan 3 ') (Cola $r.Salida)
  $r = Migra $e (Basicos $e)
  Igual 'relanzado sin limite sale con 0' 0 $r.Codigo
  Igual 'ahora estan las 5 hechas' 5 (Cuenta-Estado (Tareas $e) 'hecha')
  Igual 'cinco llamadas en total: las dos primeras no se repiten' 5 (Llamadas-De (Llamadas $e.Wt) 'clase-').Count
  Igual 'la fase acaba' 'fichas-clase-hechas' (Estado $e).fase
}

$Pruebas['21 racha: una llamada buena la pone a 0 y un tiempo agotado cuenta como fallo'] = {
  $e = Nuevo-Escenario 'racha' @('Clase1', 'Clase2', 'Clase3', 'Clase4') @{ FallosSeguidos = 2 }
  $r = Migra $e (Basicos $e) 'falla-una-vez:^Clase[13]$'
  Igual 'fallo, bien, fallo, bien con tope 2: no para (sale con 0)' 0 $r.Codigo
  Comprueba 'sin parada' ($null -eq (Estado $e).parada) (Cola $r.Salida)
  Igual 'las 4 acaban hechas' 4 (Cuenta-Estado (Tareas $e) 'hecha')
  Igual 'seis llamadas: las dos que fallaron se repiten' 6 (Llamadas-De (Llamadas $e.Wt) 'clase-').Count
  $e = Nuevo-Escenario 'racha-tiempo' @('Clase1', 'Clase2', 'Clase3', 'Clase4') @{ FallosSeguidos = 2; SegundosPorLlamada = 3 }
  $r = Migra $e (Basicos $e) 'colgado:^Clase'
  Igual 'cuatro llamadas colgadas con tope 2: sale con 2' 2 $r.Codigo
  Igual 'parada: copilot-no-responde' 'copilot-no-responde' (Estado $e).parada.motivo
  Igual 'ninguna tarea atascada (el fallo es de Copilot)' 0 (Cuenta-Estado (Tareas $e) 'atascada')
}

$Pruebas['22 ficha invalida: cita larga, papel o tipo fuera de la lista, linea y JSON que no valen'] = {
  $e = Nuevo-Escenario 'validacion' @('Larga', 'PapelX', 'TipoX', 'LTexto', 'LCero', 'LDec', 'Lista', 'Texto', 'Bien')
  $g = 'cita-larga:^Larga$;papel-libre:^PapelX$;tipo-libre:^TipoX$;linea-texto:^LTexto$;linea-cero:^LCero$;linea-decimal:^LDec$;json-lista:^Lista$;json-texto:^Texto$'
  $r = Migra $e (Basicos $e) $g
  Igual 'sale con 0' 0 $r.Codigo
  $t = Tareas $e
  $casos = @(@('Larga', 'pasa de 120'), @('PapelX', "papel' vale"), @('TipoX', 'tipo vale'), @('LTexto', 'linea tiene que ser'), @('LCero', 'linea tiene que ser'), @('LDec', 'linea tiene que ser'), @('Lista', 'tiene que ser un objeto'), @('Texto', 'tiene que ser un objeto'))
  foreach ($c in $casos) {
    $x = @($t | Where-Object { $_.entradas.fichero -like "*/$($c[0]).java" })[0]
    Comprueba "$($c[0]): atascada con su motivo" (($x.estado -eq 'atascada') -and ($x.motivo -match $c[1])) "$($x.estado): $($x.motivo)"
  }
  Igual 'Bien: hecha' 'hecha' @($t | Where-Object { $_.entradas.fichero -like '*/Bien.java' })[0].estado
  Igual 'solo hay la ficha de Bien' 1 (Fichas $e).Count
}

$Pruebas['23 salida vieja: lo que escribio un intento anterior no vale para el siguiente'] = {
  $e = Nuevo-Escenario 'vieja' @('Clase1')
  $r = Migra $e (Basicos $e) 'toca-y-calla:^Clase'
  Igual 'sale con 0' 0 $r.Codigo
  $t = @(Tareas $e)[0]
  Igual 'la tarea queda atascada' 'atascada' $t.estado
  Comprueba 'el motivo es que no escribio el fichero' ($t.motivo -match 'No has escrito') $t.motivo
  $ll = Llamadas-De (Llamadas $e.Wt) $t.id
  Igual 'dos llamadas' 2 $ll.Count
  Comprueba 'el segundo intento lleva la correccion (el primero toco codigo)' ($ll.Count -eq 2 -and $ll[1].correccion -eq 'True')
  Igual 'no hay fichas' 0 (Fichas $e).Count
  Igual 'el worktree queda limpio' '' (GitEn $e.Wt @('status', '--porcelain'))
}

$Pruebas['24 reintento tras un fallo de Copilot: el mismo prompt, sin la seccion de correccion'] = {
  $e = Nuevo-Escenario 'reintento' @('Clase1')
  $r = Migra $e (Basicos $e) 'falla-una-vez:^Clase'
  Igual 'sale con 0' 0 $r.Codigo
  $t = @(Tareas $e)[0]
  Igual 'la tarea acaba hecha en el segundo intento' 'hecha 2' "$($t.estado) $($t.intentos)"
  $ll = Llamadas-De (Llamadas $e.Wt) $t.id
  Igual 'dos llamadas' 2 $ll.Count
  Comprueba 'el primer prompt no lleva correccion' ($ll.Count -eq 2 -and $ll[0].correccion -eq 'False')
  Comprueba 'el segundo tampoco: el fallo es de Copilot, no de la ficha' ($ll.Count -eq 2 -and $ll[1].correccion -eq 'False')
  Comprueba 'pero el esfuerzo sube' ($ll.Count -eq 2 -and $ll[1].flags -match '--effort=high' -and $ll[0].flags -notmatch '--effort=high')
  $p = [System.IO.File]::ReadAllText((Get-Ruta $e.Wt (".rescate/tareas/" + $t.id + '.prompt.md')))
  Comprueba 'el prompt guardado del segundo intento no tiene la seccion' ($p -notmatch 'CORRECCI')
}

$Pruebas['25 aptitud sin Copilot: si sale con error no se reintenta y el arranque dice por que'] = {
  $e = Nuevo-Escenario 'sinmodelo' @('Clase1') @{ SegundosPorLlamada = 3 }
  $r = Migra $e (Basicos $e) 'falla-siempre:^Validador'
  Igual 'sale con 1' 1 $r.Codigo
  Comprueba 'dice que Copilot no ha podido responder' ($r.Salida -match 'Copilot no ha podido responder') (Cola $r.Salida)
  Comprueba 'con la ultima linea de lo que dijo' ($r.Salida -match 'no hay sesion iniciada') (Cola $r.Salida)
  Igual 'una sola llamada de aptitud' 1 (Llamadas (Get-Ruta $e.Out 'registros/aptitud')).Count
  Comprueba 'sin estado ni worktree' ((-not (Test-Path -LiteralPath $e.Wt)) -and ($null -eq (Estado $e)))
  $r = Migra $e (Basicos $e) 'colgado:^Validador'
  Igual 'una llamada colgada en la aptitud: sale con 1' 1 $r.Codigo
  Comprueba 'tambien dice que Copilot no ha podido responder' ($r.Salida -match 'Copilot no ha podido responder') (Cola $r.Salida)
  Igual 'y tampoco se repite' 1 (Llamadas (Get-Ruta $e.Out 'registros/aptitud')).Count
}

# ================================ LANZADOR ================================
Invoke-Banco $Pruebas $Script
