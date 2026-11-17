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
function Basicos($E) {
  return @('-Legacy', $E.Legacy, '-Migrado', $E.Migrado, '-Plantilla', $E.Plantilla, '-Modelo', 'modelo-x', '-SoloInforme')
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
  Comprueba 'dice que no esta en una rama' ($r.Salida -match 'rama') (Cola $r.Salida)
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

# ================================ LANZADOR ================================
Invoke-Banco $Pruebas $Script
