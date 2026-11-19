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
# Lanza migracion.ps1 con RESCATE_HOME en la carpeta del escenario: nunca toca los ajustes reales. Sin la orden de la prueba en local de
# mentira ($env:PRUEBA_LOCAL_FALSA, ver Migra-Motor) agrega -SinPruebaLocal: el banco no ejecuta nunca el prueba-local.ps1 de verdad.
function Migra($E, [string[]]$A, [string]$Guion = '', [string[]]$Entrada = @(''), [string]$Programa = '') {
  if (-not $Programa) { $Programa = $Script }
  if (-not $env:PRUEBA_LOCAL_FALSA -and $A -notcontains '-SinPruebaLocal') { $A = $A + '-SinPruebaLocal' }
  $env:RESCATE_HOME = $E.Home
  try { return Lanzar $Programa $A $Guion $Entrada }
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

# Las tareas de un tipo (por defecto, las fichas de clase) de datos/tareas.
function Tareas($E, [string]$Tipo = 'ficha-clase') {
  $d = Get-Ruta $E.Out 'datos/tareas'
  if (-not (Test-Path -LiteralPath $d)) { return @() }
  return @(Get-ChildItem -LiteralPath $d -File -Filter '*.json' | Sort-Object Name | ForEach-Object { Lee-Json $_.FullName } | Where-Object { $_.tipo -eq $Tipo })
}

# El prompt que se le dio a Copilot en el ultimo intento de una tarea.
function Prompt-De($E, $Tarea) { return [System.IO.File]::ReadAllText((Get-Ruta $E.Wt ('.rescate/tareas/' + $Tarea.id + '.prompt.md'))) }

function Mapa($E) { return (Lee-Json (Get-Ruta $E.Out 'datos/mapa.json')) }

function Job-De($E, [string]$Job) { return (Lee-Json (Get-Ruta $E.Out ('datos/jobs/' + $Job + '.json'))) }

function Del-Job($Mapa, [string]$Job) { return @($Mapa.jobs | Where-Object { $_.job -eq $Job })[0] }

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
  # rescate.ps1 (el diagnostico que lanza migracion.ps1) lee el Maven y el Copilot de .rescate/config.json del repo, no de ajustes.json
  Escribe $mig '.rescate/config.json' (ConvertTo-Json -InputObject ([ordered]@{ CopilotExe = $aj['CopilotExe']; MvnExe = $aj['MvnExe'] }))
  return [pscustomobject]@{
    Raiz = $raiz; Legacy = $leg; Plantilla = $pl; Migrado = $mig; Home = $casa
    Wt = ($mig + '-rescate'); Out = (Join-Path $mig 'migracion-batch')
  }
}

# Una clase que usa a otras por su nombre (mismo paquete, sin imports) y, ademas, $Extra lineas de campo.
function Clase-Con([string]$Nombre, [string[]]$Usa = @(), [int]$Extra = 0) {
  $campos = ''
  foreach ($u in $Usa) { $campos += "    private $u campo$u;`n" }
  for ($i = 1; $i -le $Extra; $i++) { $campos += "    private int extra$i;`n" }
  return "package com.acme.old;`n`n/** Clase $Nombre. */`npublic class $Nombre {`n    private int valor = 1;`n$campos    public int dobla(int x) {`n        int r = x * 2;`n        return r;`n    }`n}`n"
}

# Un fichero que define jobs y pasos. Cada definicion es 'job:paso1,paso2'. No nombra ninguna clase salvo las de $Usa.
function Jobs-Config([string[]]$Defs, [string[]]$Usa = @()) {
  $t = "package com.acme.old;`n`npublic class JobsConfig {`n"
  foreach ($u in $Usa) { $t += "    private $u campo$u;`n" }
  foreach ($d in $Defs) {
    $job, $pasos = $d -split ':', 2
    $t += "    Job $job() {`n        return jobBuilderFactory.get(""$job"")`n            .build();`n    }`n"
    foreach ($p in ($pasos -split ',')) {
      $t += "    Step $p() {`n        return stepBuilderFactory.get(""$p"")`n            .build();`n    }`n"
    }
  }
  return ($t + "}`n")
}

# Anade ficheros .java al original (nombre de clase -> texto) y los commitea.
function Escribe-Original($E, $Clases) {
  foreach ($k in $Clases.Keys) { Escribe $E.Legacy "src/main/java/com/acme/old/$k.java" $Clases[$k] }
  [void](GitEn $E.Legacy @('add', '-A'))
  [void](GitEn $E.Legacy @('commit', '-q', '-m', 'original'))
}

# Dos jobs en un mismo fichero. Los pasos sacan sus clases por el prefijo (cargaStep: CargaReader y CargaValidator).
# CargaReader -> Auxiliar1 -> Auxiliar2 -> Auxiliar3 (la cadena de referencias); Suelta no cuelga de nadie.
function Escenario-Dos([string]$Nombre, [string[]]$UsaConfig = @(), [hashtable]$Ajustes = @{}) {
  $e = Nuevo-Escenario $Nombre @() $Ajustes
  Escribe-Original $e @{
    JobsConfig = (Jobs-Config @('cargaJob:cargaStep', 'informeJob:informeStep') $UsaConfig)
    CargaReader = (Clase-Con 'CargaReader' @('Auxiliar1') 4)
    CargaValidator = (Clase-Con 'CargaValidator')
    InformeWriter = (Clase-Con 'InformeWriter')
    Auxiliar1 = (Clase-Con 'Auxiliar1' @('Auxiliar2'))
    Auxiliar2 = (Clase-Con 'Auxiliar2' @('Auxiliar3'))
    Auxiliar3 = (Clase-Con 'Auxiliar3')
    Suelta = (Clase-Con 'Suelta')
  }
  return $e
}

$script:Corridas = @{}
# Una corrida entera del escenario de dos jobs con ese guion. Se hace una vez y la comparten los tests que la miran.
function Corrida-Dos([string]$Guion) {
  if (-not $script:Corridas.ContainsKey($Guion)) {
    $e = Escenario-Dos ('dos' + $script:Corridas.Count)
    $script:Corridas[$Guion] = [pscustomobject]@{ E = $e; R = (Migra $e (Basicos $e) $Guion) }
  }
  return $script:Corridas[$Guion]
}
$GuionBase = 'tipos-variados:^CargaReader$'
$DirJava = 'src/main/java/com/acme/old'

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
  Igual 'estado: fase' 'hecha' (Estado $e).fase
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

$Pruebas['14 el banco del motor sigue pasando entero'] = {
  $r = Lanzar (Join-Path $aqui 'probar.ps1') @('-Dir', (Join-Path $Dir 'motor'))
  Comprueba 'probar.ps1 pasa todas sus comprobaciones (75 o mas)' ($r.Codigo -eq 0 -and $r.Salida -match 'TODO BIEN: (\d+) comprobaciones' -and [int]$Matches[1] -ge 75) (Cola $r.Salida)
}

# ============================ BIBLIOTECA Y LANZADOR ============================
# Lanza un script de prueba que carga comun.ps1 y tareas.ps1 (nunca migracion.ps1), como haria un preflight; con -ConInforme, tambien informe.ps1.
function En-Biblioteca([string]$Nombre, [string]$Codigo, [switch]$ConInforme) {
  $raiz = Split-Path -Parent $Script
  $cab = "`$ErrorActionPreference = 'Stop'`n. '" + (Join-Path $raiz 'comun.ps1') + "'`n. '" + (Join-Path $raiz 'tareas.ps1') + "'`n"
  if (Test-Path -LiteralPath (Join-Path $raiz 'lanzadores.ps1')) { $cab += ". '" + (Join-Path $raiz 'lanzadores.ps1') + "'`n" }
  if ($ConInforme) { $cab += ". '" + (Join-Path $raiz 'informe.ps1') + "'`n" }
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
  foreach ($f in @('Test-Aptitud', 'Invoke-Llamadas', 'Invoke-Ronda', 'Get-TareasFichas', 'Test-Ficha', 'Read-Json', 'Write-Json', 'Get-Hash8', 'Stop-Arranque', 'Set-Despierto')) {
    Comprueba "$f esta en tareas.ps1 y no en migracion.ps1" (($deTareas -contains $f) -and ($deMigra -cnotcontains $f))
  }
  $todas = @($deTareas) + @($deMigra) + @(Funciones-De (Join-Path $raiz 'comun.ps1')) + @(Funciones-De (Join-Path $raiz 'informe.ps1'))
  if (Test-Path -LiteralPath (Join-Path $raiz 'lanzadores.ps1')) { $todas += @(Funciones-De (Join-Path $raiz 'lanzadores.ps1')) }
  $dup = @($todas | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
  Comprueba 'ninguna funcion esta definida dos veces entre comun, tareas, migracion, informe y lanzadores' ($dup.Count -eq 0) ($dup -join ', ')
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
  Comprueba 'fin es una hora tambien con un error interno' (Es-Hora $s.fin) "$($s.fin)"
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
  Igual 'la fase acaba' 'hecha' (Estado $e).fase
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

# ============================== NEGOCIO: MAPA, FICHA DE JOB, RESUMEN, VARIABLES ==============================
$Pruebas['26 mapa: dos jobs en un fichero, con pasos, clases por nombre simple, profundidad 2 y sinJob'] = {
  $c = Corrida-Dos $GuionBase
  $e = $c.E
  Igual 'sale con 0' 0 $c.R.Codigo
  $m = Mapa $e
  Comprueba 'hay datos/mapa.json' ($null -ne $m) (Cola $c.R.Salida)
  if ($null -eq $m) { return }
  Igual 'los jobs del contrato, en orden' 'cargaJob informeJob' (@($m.jobs | ForEach-Object { $_.job }) -join ' ')
  $a = Del-Job $m 'cargaJob'
  $b = Del-Job $m 'informeJob'
  Igual 'cargaJob: definidoEn' "$DirJava/JobsConfig.java" $a.definidoEn
  $texto = [System.IO.File]::ReadAllLines((Get-Ruta $e.Legacy "$DirJava/JobsConfig.java"))
  $donde = 0
  for ($i = 0; $i -lt $texto.Count; $i++) { if ($texto[$i].Contains('get("cargaJob")')) { $donde = $i + 1 } }
  Igual 'cargaJob: la linea donde se define' $donde $a.linea
  Igual 'cargaJob: probado' 'True' "$($a.probado)"
  Igual 'cargaJob: un paso con las clases que le da el modelo' 'cargaStep: CargaReader CargaValidator' ((@($a.pasos | ForEach-Object { $_.paso + ': ' + (@($_.clases) -join ' ') })) -join '; ')
  Igual 'informeJob: su paso' 'informeStep: InformeWriter' ((@($b.pasos | ForEach-Object { $_.paso + ': ' + (@($_.clases) -join ' ') })) -join '; ')
  Igual 'cargaJob: sus clases (pasos, fichero que lo define y referencias hasta profundidad 2)' 'CargaReader CargaValidator JobsConfig Auxiliar1 Auxiliar2' (@($a.clases | ForEach-Object { $_.clase }) -join ' ')
  Igual 'cargaJob: por que sale cada una' 'paso paso definicion referencia referencia' (@($a.clases | ForEach-Object { $_.por }) -join ' ')
  Igual 'informeJob: sus clases' 'InformeWriter JobsConfig' (@($b.clases | ForEach-Object { $_.clase }) -join ' ')
  $f = Fichas $e
  $r1 = @($a.clases)[0]
  Comprueba 'cada clase lleva fichero, la ficha que existe y tieneFicha' ($r1.fichero -eq "$DirJava/CargaReader.java" -and $r1.ficha -match '^clase-[0-9a-f]{8}$' -and @($f | Where-Object { $_.id -eq $r1.ficha }).Count -eq 1 -and $r1.tieneFicha -eq $true) ($r1 | ConvertTo-Json -Compress)
  Igual 'sinJob: lo que no cuelga de ningun job' "$DirJava/Auxiliar3.java $DirJava/Suelta.java" (@($m.sinJob) -join ' ')
  $d = Llamadas-De (Llamadas $e.Wt) 'definicion-'
  Igual 'una sola llamada de definicion para los dos jobs del fichero' 1 $d.Count
  $t = @(Tareas $e 'definicion-job')
  $p = ''
  if ($t.Count -eq 1) { $p = Prompt-De $e $t[0] }
  Comprueba 'su prompt lleva los dos jobs y la lista cerrada de clases' ($p -match '(?m)^JOBS: cargaJob, informeJob\r?$' -and $p -match '(?m)^CLASES: .*CargaReader.*Suelta') (($t | ForEach-Object { $_.id }) -join ' ')
  Comprueba 'la definicion lee el original (--add-dir) con esfuerzo de lectura' ($d.Count -eq 1 -and $d[0].flags -match '--add-dir=\S*life-java8' -and $d[0].flags -match '--effort=medium') (($d | ForEach-Object { $_.flags }) -join ' | ')
}

$Pruebas['27 definicion con una clase fuera de la lista: reintento con correccion, atascada y el job sale sin pasos'] = {
  $e = Escenario-Dos 'indefinido' @('CargaReader')
  $r = Migra $e (Basicos $e) 'job-clase-fuera:^definicion-job:'
  Igual 'sale con 0' 0 $r.Codigo
  $t = @(Tareas $e 'definicion-job')
  Igual 'hay una tarea de definicion' 1 $t.Count
  if ($t.Count -ne 1) { return }
  Igual 'queda atascada con dos intentos' 'atascada 2' "$($t[0].estado) $($t[0].intentos)"
  Comprueba 'el motivo nombra la clase que sobra' ($t[0].motivo -match 'NoExiste') $t[0].motivo
  $ll = Llamadas-De (Llamadas $e.Wt) $t[0].id
  Igual 'dos llamadas' 2 $ll.Count
  Comprueba 'el reintento lleva la correccion y esfuerzo high' ($ll.Count -eq 2 -and $ll[1].correccion -eq 'True' -and $ll[0].correccion -eq 'False' -and $ll[1].flags -match '--effort=high' -and $ll[0].flags -notmatch '--effort=high') (($ll | ForEach-Object { $_.flags }) -join ' | ')
  Comprueba 'la seccion de correccion del prompt dice la clase' ((Prompt-De $e $t[0]) -match '(?s)## CORRECCI.*NoExiste')
  $m = Mapa $e
  Comprueba 'hay mapa.json con los dos jobs' ($null -ne $m -and @($m.jobs).Count -eq 2) (Cola $r.Salida)
  if ($null -eq $m) { return }
  foreach ($n in @('cargaJob', 'informeJob')) {
    $j = Del-Job $m $n
    Igual "$n sin pasos" 0 @($j.pasos).Count
    Igual "$n con las clases a las que llega desde el fichero que lo define" 'JobsConfig CargaReader Auxiliar1' (@($j.clases | ForEach-Object { $_.clase }) -join ' ')
    Comprueba "$n lleva una duda que lo dice" (@($j.dudas).Count -eq 1 -and "$($j.dudas[0])" -match 'pasos') "$($j.dudas -join ' / ')"
    Comprueba "$n sin probar y sin linea" ($j.probado -eq $false -and $j.linea -eq 0)
  }
  Igual 'las fases siguientes se hacen igual' 'hecha' (Estado $e).fase
}

$Pruebas['28 contrato sin jobs: un solo job con el nombre del batch, todas las clases (con tope) y su duda'] = {
  $e = Nuevo-Escenario 'sinjobs' @('Clase1', 'Clase2', 'Clase3', 'Clase4', 'Clase5') @{ ClasesPorJob = 3 }
  $r = Migra $e (Basicos $e)
  Igual 'sale con 0' 0 $r.Codigo
  Comprueba 'el motor ha escrito .rescate/contrato.json en el worktree, sin jobs' ((Test-Path -LiteralPath (Get-Ruta $e.Wt '.rescate/contrato.json')) -and @((Lee-Json (Get-Ruta $e.Wt '.rescate/contrato.json')).jobs).Count -eq 0) (Cola $r.Salida)
  $m = Mapa $e
  Comprueba 'hay mapa.json con un job' ($null -ne $m -and @($m.jobs).Count -eq 1) (Cola $r.Salida)
  if ($null -eq $m) { return }
  $j = @($m.jobs)[0]
  Igual 'el job se llama como el batch' (Estado $e).batch $j.job
  Igual 'sin fichero que lo defina' '' "$($j.definidoEn)"
  Igual 'sin pasos' 0 @($j.pasos).Count
  Igual 'sus clases, con el tope' 'Clase1 Clase2 Clase3' (@($j.clases | ForEach-Object { $_.clase }) -join ' ')
  Comprueba 'lleva una duda' (@($j.dudas).Count -ge 1) "$($j.dudas -join ' / ')"
  Igual 'sinJob: las que no caben' 'Clase4 Clase5' (@($m.sinJob | ForEach-Object { (Split-Path $_ -Leaf) -replace '\.java$', '' }) -join ' ')
  Igual 'no hay tareas de definicion' 0 (Llamadas-De (Llamadas $e.Wt) 'definicion-').Count
  Comprueba 'la ficha del job existe' ($null -ne (Job-De $e $j.job))
}

$Pruebas['29 contrato que ya existe: se respeta y no se llama al motor'] = {
  $e = Escenario-Dos 'contrato'
  $r = Migra $e ((Basicos $e) + @('-Limite', '1'))
  Igual 'el primer lanzamiento (corto) sale con 0' 0 $r.Codigo
  Comprueba 'el contrato ya lo dejo la fase diagnostico (la primera)' (Test-Path -LiteralPath (Get-Ruta $e.Wt '.rescate/contrato.json'))
  $mio = '{ "generado": "a mano", "original": "x", "jobs": [ { "nombre": "trabajoManual", "origen": "confirmado", "definidoEn": "' + $DirJava + '/JobsConfig.java", "entrada": "", "salida": "" } ] }'
  Escribe $e.Wt '.rescate/contrato.json' $mio
  $r = Migra $e (Basicos $e)
  Igual 'el segundo sale con 0' 0 $r.Codigo
  Igual 'el contrato queda tal cual (el motor no lo toca)' $mio (Lee $e.Wt '.rescate/contrato.json')
  $m = Mapa $e
  Igual 'los jobs del mapa son los del contrato, no los que veria el motor' 'trabajoManual' (@($m.jobs | ForEach-Object { $_.job }) -join ' ')
  Igual 'con su fichero' "$DirJava/JobsConfig.java" (@($m.jobs)[0]).definidoEn
}

$Pruebas['30 ficha de job: el prompt lleva los datos con su referencia y no manda leer nada; sale datos/jobs/<job>.json'] = {
  $c = Corrida-Dos $GuionBase
  $e = $c.E
  $t = @(Tareas $e 'ficha-job' | Where-Object { $_.entradas.job -eq 'cargaJob' })
  Igual 'hay una tarea de ficha-job para cargaJob' 1 $t.Count
  if ($t.Count -ne 1) { return }
  $p = Prompt-De $e $t[0]
  $f = @(Fichas $e | Where-Object { $_.fichero -like '*/CargaReader.java' })[0]
  Comprueba 'el prompt lleva un dato con su referencia, tipo y texto' ($p.Contains($f.id + '#0 [' + $f.datos[0].tipo + '] ' + $f.datos[0].texto)) (($p -split "`n" | Select-Object -First 3) -join ' / ')
  Comprueba 'lleva la clase con su papel y lo que hace' ($p -match ('(?m)^### CargaReader \(' + $f.id + ', ' + $f.papel + '\): ' + [regex]::Escape($f.queHace)))
  Comprueba 'lleva los pasos del mapa' ($p -match 'cargaStep' -and $p -match 'CargaValidator')
  Comprueba 'no manda leer ningun fichero (sin LEER ni ruta del original)' ($p -notmatch '(?m)^LEER:' -and -not $p.Contains($e.Legacy))
  $ll = Llamadas-De (Llamadas $e.Wt) $t[0].id
  Igual 'una llamada' 1 $ll.Count
  Comprueba 'sin --add-dir y con esfuerzo high' ($ll.Count -eq 1 -and $ll[0].flags -notmatch '--add-dir' -and $ll[0].flags -match '--effort=high' -and $ll[0].flags -match '--no-custom-instructions') (($ll | ForEach-Object { $_.flags }) -join ' | ')
  $j = Job-De $e 'cargaJob'
  Comprueba 'existe datos/jobs/cargaJob.json' ($null -ne $j)
  if ($null -eq $j) { return }
  Igual 'job' 'cargaJob' $j.job
  Igual 'titulo del modelo' 'Titulo de cargaJob' $j.titulo
  Comprueba 'paraQue con texto' ("$($j.paraQue)".Length -gt 0)
  Igual 'dos pasos del modelo' 2 @($j.pasos).Count
  Comprueba 'cada paso con titulo, texto, una referencia y probado' (@($j.pasos | Where-Object { $_.titulo -and $_.texto -and @($_.refs).Count -eq 1 -and $_.probado -eq $true }).Count -eq 2) ($j.pasos | ConvertTo-Json -Compress -Depth 4)
  Igual 'redaccion' 'hecha' $j.redaccion
  Comprueba 'trae las cinco listas, sinFicha y dudas' (@('necesita', 'produce', 'conexiones', 'reglas', 'siFalla', 'sinFicha', 'dudas' | Where-Object { $j.PSObject.Properties.Name -notcontains $_ }).Count -eq 0) (($j.PSObject.Properties.Name) -join ' ')
  Igual 'el job no tiene clases sin ficha' 0 @($j.sinFicha).Count
  Comprueba 'y las demas clases del job estan en el prompt (Auxiliar2 tambien)' ($p -match '(?m)^### Auxiliar2 \(')
}

$Pruebas['31 listas del script: cada dato de las fichas sale una vez, aunque el modelo no lo nombre'] = {
  $c = Corrida-Dos $GuionBase
  $e = $c.E
  $m = Mapa $e
  $j = Job-De $e 'cargaJob'
  if ($null -eq $m -or $null -eq $j) { Comprueba 'hay mapa y ficha de job' $false (Cola $c.R.Salida); return }
  $ids = @((Del-Job $m 'cargaJob').clases | ForEach-Object { $_.ficha })
  $fichas = @(Fichas $e | Where-Object { $ids -contains $_.id })
  $listas = [ordered]@{ necesita = @('entrada-fichero', 'tabla-lee', 'parametro', 'config'); produce = @('salida-fichero', 'tabla-escribe'); conexiones = @('sftp', 'externo'); reglas = @('regla'); siFalla = @('error') }
  $repetidos = 0
  foreach ($k in $listas.Keys) {
    $crudos = @($fichas | ForEach-Object { $_.datos } | Where-Object { $listas[$k] -contains $_.tipo })
    $esperado = @{}
    foreach ($d in $crudos) { $esperado[$d.tipo + '|' + (($d.texto -replace '\s', '').ToLowerInvariant())] = $true }
    $real = @($j.$k | ForEach-Object { $_.tipo + '|' + (($_.texto -replace '\s', '').ToLowerInvariant()) })
    Comprueba "$k lleva datos" ($real.Count -gt 0)
    Igual "$k : tantos como datos distintos hay en las fichas" $esperado.Count $real.Count
    Igual "$k : ninguno repetido" $real.Count @($real | Select-Object -Unique).Count
    Comprueba "$k : todos vienen de las fichas, del tipo que toca" (@($real | Where-Object { -not $esperado.ContainsKey($_) }).Count -eq 0)
    $repetidos += ($crudos.Count - $esperado.Count)
  }
  Comprueba 'las fichas tienen datos repetidos entre clases (la prueba junta algo)' ($repetidos -gt 0) "$repetidos"
  Comprueba 'hay mas reglas que referencias nombra el modelo (2): las pone el script' (@($j.reglas).Count -gt 2) "$(@($j.reglas).Count)"
  $x = @($j.reglas)[0]
  Comprueba 'cada elemento lleva tipo, texto, ref, clase, fichero, linea, cita y probado' (@('tipo', 'texto', 'ref', 'clase', 'fichero', 'linea', 'cita', 'probado' | Where-Object { $x.PSObject.Properties.Name -notcontains $_ }).Count -eq 0 -and $x.ref -match '^clase-[0-9a-f]{8}#\d+$') ($x | ConvertTo-Json -Compress)
  $ref = $x.ref -split '#'
  $fx = @($fichas | Where-Object { $_.id -eq $ref[0] })[0]
  Comprueba 'la ref apunta al dato de esa ficha' ($null -ne $fx -and $fx.datos[[int]$ref[1]].texto -eq $x.texto -and $fx.clase -eq $x.clase -and $fx.fichero -eq $x.fichero) ($x | ConvertTo-Json -Compress)
}

$Pruebas['32 referencia que no existe: ese paso queda sin probar; con mas de la mitad, invalida'] = {
  $c = Corrida-Dos 'job-ref-mixta:^ficha-job:cargaJob$;job-ref-mala:^ficha-job:informeJob$'
  $e = $c.E
  Igual 'sale con 0' 0 $c.R.Codigo
  $j = Job-De $e 'cargaJob'
  Comprueba 'cargaJob: hecha, con un paso probado y otro no' ($null -ne $j -and $j.redaccion -eq 'hecha' -and (@($j.pasos | ForEach-Object { "$($_.probado)" }) -join ' ') -eq 'True False') ($j.pasos | ConvertTo-Json -Compress -Depth 4)
  $t = @(Tareas $e 'ficha-job' | Where-Object { $_.entradas.job -eq 'informeJob' })[0]
  Igual 'informeJob: atascada tras dos intentos' 'atascada 2' "$($t.estado) $($t.intentos)"
  Comprueba 'el motivo habla de las referencias' ($t.motivo -match 'referencias') $t.motivo
  $ll = Llamadas-De (Llamadas $e.Wt) $t.id
  Comprueba 'el reintento lleva la correccion' ($ll.Count -eq 2 -and $ll[1].correccion -eq 'True' -and $ll[0].correccion -eq 'False') (($ll | ForEach-Object { $_.correccion }) -join ' ')
}

$Pruebas['33 nombre de clase en un texto de negocio: invalida, el motivo lo nombra y el reintento lo corrige'] = {
  $c = Corrida-Dos 'job-clase-en-texto:^ficha-job:cargaJob$'
  $e = $c.E
  Igual 'sale con 0' 0 $c.R.Codigo
  $t = @(Tareas $e 'ficha-job' | Where-Object { $_.entradas.job -eq 'cargaJob' })[0]
  Igual 'cargaJob: hecha en el segundo intento' 'hecha 2' "$($t.estado) $($t.intentos)"
  $p = Prompt-De $e $t
  Comprueba 'la correccion del segundo prompt nombra la clase' ($p -match '(?s)## CORRECCI.*CargaReader') ((($p -split "`n") | Select-Object -Last 6) -join ' / ')
  Comprueba 'y dice que es el titulo' ($p -match '(?s)## CORRECCI.*titulo')
  $j = Job-De $e 'cargaJob'
  Igual 'el fichero lleva el titulo corregido' 'Titulo de cargaJob' $j.titulo
}

$Pruebas['34 ficha de job atascada: el fichero existe, con las listas y redaccion atascada'] = {
  $c = Corrida-Dos 'json-roto:^ficha-job:informeJob$;resumen-sin-job'
  $e = $c.E
  Igual 'sale con 0' 0 $c.R.Codigo
  $t = @(Tareas $e 'ficha-job' | Where-Object { $_.entradas.job -eq 'informeJob' })[0]
  Igual 'la tarea queda atascada' 'atascada' $t.estado
  $j = Job-De $e 'informeJob'
  Comprueba 'existe datos/jobs/informeJob.json' ($null -ne $j) (Cola $c.R.Salida)
  if ($null -eq $j) { return }
  Igual 'redaccion' 'atascada' $j.redaccion
  Comprueba 'sin titulo, paraQue ni pasos' (@('titulo', 'paraQue', 'pasos' | Where-Object { $j.PSObject.Properties.Name -contains $_ }).Count -eq 0) (($j.PSObject.Properties.Name) -join ' ')
  Comprueba 'con las listas del script (la regla de InformeWriter)' (@($j.reglas).Count -ge 1 -and @($j.reglas)[0].clase -eq 'InformeWriter') ($j | ConvertTo-Json -Compress -Depth 5)
  Igual 'el otro job sigue hecho' 'hecha' (Job-De $e 'cargaJob').redaccion
}

$Pruebas['35 resumen: valido; si falta un job en el orden es invalido; sin redacciones hechas no hay tarea'] = {
  $c = Corrida-Dos $GuionBase
  $e = $c.E
  $t = @(Tareas $e 'resumen')
  Igual 'valido: una tarea de resumen hecha' 'hecha' "$($t[0].estado)"
  $p = ''
  if ($t.Count -eq 1) { $p = Prompt-De $e $t[0] }
  Comprueba 'su prompt lleva de cada job el titulo, el para que y los titulos de los pasos' ($p -match '(?m)^JOB: cargaJob\r?$' -and $p -match 'Titulo de cargaJob' -and $p -match 'Sirve para probar cargaJob' -and $p -match 'Primer paso' -and $p -match '(?m)^JOB: informeJob\r?$')
  Comprueba 'no manda leer nada' ($p -notmatch '(?m)^LEER:' -and -not $p.Contains($e.Legacy))
  $ll = Llamadas-De (Llamadas $e.Wt) 'resumen'
  Comprueba 'una llamada, sin --add-dir y con esfuerzo high' ($ll.Count -eq 1 -and $ll[0].flags -notmatch '--add-dir' -and $ll[0].flags -match '--effort=high') (($ll | ForEach-Object { $_.flags }) -join ' | ')
  $r = Lee-Json (Get-Ruta $e.Out 'datos/resumen.json')
  Comprueba 'datos/resumen.json con resumen, orden y glosario' ($null -ne $r -and "$($r.resumen)".Length -gt 0 -and @($r.glosario).Count -eq 1) (Cola $c.R.Salida)
  Igual 'orden: cada job una vez' 'cargaJob informeJob' (@($r.orden | ForEach-Object { $_.job }) -join ' ')
  # falta un job en el orden: invalida con el nombre, y sin resumen.json
  $c2 = Corrida-Dos 'json-roto:^ficha-job:informeJob$;resumen-sin-job'
  $t2 = @(Tareas $c2.E 'resumen')
  Igual 'sin un job en el orden: atascada tras dos intentos' 'atascada 2' "$($t2[0].estado) $($t2[0].intentos)"
  Comprueba 'el motivo nombra el job que falta (aunque no tenga redaccion: el orden es de los jobs del mapa)' ($t2[0].motivo -match 'informeJob') $t2[0].motivo
  Comprueba 'no se escribe resumen.json' (-not (Test-Path -LiteralPath (Get-Ruta $c2.E.Out 'datos/resumen.json')))
  Igual 'y la fase acaba' 'hecha' (Estado $c2.E).fase
  # ninguna redaccion hecha: no hay tarea
  $c3 = Corrida-Dos 'json-roto:^ficha-job:'
  Igual 'sin ninguna ficha de job hecha: ninguna llamada de resumen' 0 (Llamadas-De (Llamadas $c3.E.Wt) 'resumen').Count
  Comprueba 'ni resumen.json' (-not (Test-Path -LiteralPath (Get-Ruta $c3.E.Out 'datos/resumen.json')))
  Igual 'ni tarea' 0 @(Tareas $c3.E 'resumen').Count
  Igual 'la fase acaba' 'hecha' (Estado $c3.E).fase
}

$Pruebas['36 variables.json: yml, yaml y properties del worktree, con y sin valor por defecto'] = {
  $e = Nuevo-Escenario 'variables' @('Clase1')
  Escribe $e.Migrado 'src/main/resources/application.yml' "spring:`n  datasource:`n    url: `${DB_URL:jdbc:oracle:thin:@host:1521/x}`n    user: `${DB_USER}`n# no cuenta `${EN_COMENTARIO}`nbatch:`n  ruta: `${RUTA_ENTRADA:}`n"
  Escribe $e.Migrado 'src/main/resources/application-pre.properties' "sftp.host=`${SFTP_HOST}`nsftp.port=`${SFTP_PORT:22}`n"
  Escribe $e.Migrado 'src/main/resources/application-local.yaml' "local: `${LOCAL_VAR:abc}`n"
  Escribe $e.Migrado 'src/main/resources/otro.yml' "x: `${NO_SE_LEE}`n"
  [void](GitEn $e.Migrado @('add', '-A'))
  [void](GitEn $e.Migrado @('commit', '-q', '-m', 'recursos'))
  $r = Migra $e ((Basicos $e) + @('-Limite', '1'))
  Igual 'sale con 0' 0 $r.Codigo
  $v = @(Lee-Json (Get-Ruta $e.Out 'datos/variables.json'))
  Comprueba 'hay datos/variables.json con las 6 variables' ($v.Count -eq 6) (($v | ForEach-Object { $_.variable }) -join ' ')
  $x = @($v | Where-Object { $_.variable -eq 'DB_URL' })[0]
  Igual 'DB_URL: valor por defecto (con ":" dentro)' 'jdbc:oracle:thin:@host:1521/x' $x.porDefecto
  Igual 'DB_URL: fichero' 'src/main/resources/application.yml' $x.fichero
  Igual 'DB_URL: linea' 3 $x.linea
  Comprueba 'DB_USER: sin valor por defecto (null)' ($null -eq @($v | Where-Object { $_.variable -eq 'DB_USER' })[0].porDefecto)
  $x = @($v | Where-Object { $_.variable -eq 'RUTA_ENTRADA' })[0]
  Comprueba 'RUTA_ENTRADA: valor por defecto vacio, que no es null' ($x.porDefecto -is [string] -and $x.porDefecto -eq '')
  $x = @($v | Where-Object { $_.variable -eq 'SFTP_PORT' })[0]
  Igual 'SFTP_PORT: properties, con valor' '22 src/main/resources/application-pre.properties 2' "$($x.porDefecto) $($x.fichero) $($x.linea)"
  Comprueba 'SFTP_HOST: sin valor' ($null -eq @($v | Where-Object { $_.variable -eq 'SFTP_HOST' })[0].porDefecto)
  Igual 'LOCAL_VAR: .yaml' 'abc' @($v | Where-Object { $_.variable -eq 'LOCAL_VAR' })[0].porDefecto
  Comprueba 'ni las de un comentario ni las de un fichero que no es application*' (@($v | Where-Object { @('EN_COMENTARIO', 'NO_SE_LEE') -contains $_.variable }).Count -eq 0)
  # sin ficheros: lista vacia
  $e0 = Nuevo-Escenario 'variables0' @('Clase1')
  $r = Migra $e0 ((Basicos $e0) + @('-Limite', '1'))
  $ruta = Get-Ruta $e0.Out 'datos/variables.json'
  Comprueba 'sin ficheros de configuracion: variables.json es una lista vacia' ((Test-Path -LiteralPath $ruta) -and ([System.IO.File]::ReadAllText($ruta).Trim() -eq '[]')) (Cola $r.Salida)
}

$Pruebas['36b variables.json: tambien las de src/main/resources/config, con su ruta real y despues de las de la raiz'] = {
  # (a) un yml solo en config/, con una variable con punto, otra con valor y una linea de comentario
  $e = Nuevo-Escenario 'variables-config' @('Clase1')
  Escribe $e.Migrado 'src/main/resources/config/application.yml' "app:`n  uno: `${env.uno}`n  dos: `${DOS:x}`n# no cuenta `${EN_COMENTARIO}`n"
  [void](GitEn $e.Migrado @('add', '-A'))
  [void](GitEn $e.Migrado @('commit', '-q', '-m', 'config'))
  $r = Migra $e ((Basicos $e) + @('-Limite', '1'))
  Igual 'sale con 0' 0 $r.Codigo
  $v = @(Lee-Json (Get-Ruta $e.Out 'datos/variables.json'))
  Igual 'solo config/: salen las dos variables, en el orden del fichero' 'env.uno DOS' (($v | ForEach-Object { $_.variable }) -join ' ')
  Igual 'env.uno: fichero de config/ y linea' 'src/main/resources/config/application.yml 2' "$($v[0].fichero) $($v[0].linea)"
  Comprueba 'env.uno: sin valor por defecto (null)' ($v.Count -gt 0 -and $null -eq $v[0].porDefecto)
  Igual 'DOS: fichero de config/, linea y valor por defecto' 'src/main/resources/config/application.yml 3 x' "$($v[1].fichero) $($v[1].linea) $($v[1].porDefecto)"
  # (c) la linea de comentario de config/ no cuenta
  Comprueba 'una linea de comentario de config/ no cuenta' (@($v | Where-Object { $_.variable -eq 'EN_COMENTARIO' }).Count -eq 0)
  # (b) uno en la raiz y dos en config/ (escritos al reves que su orden por nombre): primero la raiz, luego config/ por nombre
  $e2 = Nuevo-Escenario 'variables-raiz-config' @('Clase1')
  Escribe $e2.Migrado 'src/main/resources/application.yml' "raiz: `${RAIZ_VAR:r}`n"
  Escribe $e2.Migrado 'src/main/resources/config/application-b.yml' "b: `${B_VAR}`n"
  Escribe $e2.Migrado 'src/main/resources/config/application-a.properties' "a=`${A_VAR:1}`n"
  [void](GitEn $e2.Migrado @('add', '-A'))
  [void](GitEn $e2.Migrado @('commit', '-q', '-m', 'raiz y config'))
  $r = Migra $e2 ((Basicos $e2) + @('-Limite', '1'))
  Igual 'raiz y config/: sale con 0' 0 $r.Codigo
  $v = @(Lee-Json (Get-Ruta $e2.Out 'datos/variables.json'))
  Igual 'salen las tres, primero la de la raiz y luego las de config/ por nombre' 'RAIZ_VAR A_VAR B_VAR' (($v | ForEach-Object { $_.variable }) -join ' ')
  Igual 'ficheros: cada una con su ruta real' 'src/main/resources/application.yml src/main/resources/config/application-a.properties src/main/resources/config/application-b.yml' (($v | ForEach-Object { $_.fichero }) -join ' ')
}

$Pruebas['37 reanudar: cortar tras el mapa no repite llamadas; cinco jobs, nunca mas de 4 a la vez'] = {
  $e = Escenario-Dos 'reanuda'
  $r = Migra $e ((Basicos $e) + @('-Limite', '9'))
  Igual 'cortado tras el mapa sale con 0' 0 $r.Codigo
  Comprueba 'hay mapa.json y aun no hay fichas de job' ($null -ne (Mapa $e) -and $null -eq (Job-De $e 'cargaJob')) (Cola $r.Salida)
  Igual 'la fase es fichas-job' 'fichas-job' (Estado $e).fase
  Igual 'una llamada de definicion hasta aqui' 1 (Llamadas-De (Llamadas $e.Wt) 'definicion-').Count
  $r = Migra $e (Basicos $e)
  Igual 'relanzado sale con 0' 0 $r.Codigo
  $ll = Llamadas $e.Wt
  Igual 'catorce llamadas en total (8 clases, 1 definicion, 2 jobs, 1 resumen, 2 pruebas)' 14 $ll.Count
  Igual 'ninguna tarea se repitio' 14 @($ll | Select-Object -ExpandProperty id -Unique).Count
  Igual 'la fase acaba' 'hecha' (Estado $e).fase
  # cinco jobs con el falso lento
  $e = Nuevo-Escenario 'cinco' @('Clase1')
  Escribe-Original $e @{ JobsConfig = (Jobs-Config @('job1:p1Step', 'job2:p2Step', 'job3:p3Step', 'job4:p4Step', 'job5:p5Step')) }
  $r = Migra $e (Basicos $e) 'lento:^ficha-job:'
  Igual 'cinco jobs: sale con 0' 0 $r.Codigo
  $ll = Llamadas-De (Llamadas $e.Wt) 'job-'
  Igual 'cinco llamadas de ficha-job' 5 $ll.Count
  $max = Max-Simultaneas $ll
  Comprueba "a lo sumo 4 a la vez (hubo $max)" ($max -le 4 -and $max -ge 2)
  Igual 'las cinco hechas' 5 @(Tareas $e 'ficha-job' | Where-Object { $_.estado -eq 'hecha' }).Count
}

$Pruebas['38 guardas en los tipos nuevos: lo que ensucia el worktree se deshace y cuenta como invalido'] = {
  # la guarda mira el worktree tras la ronda entera: no sabe cual de las tareas de la ronda lo ensucio, asi que
  # todas las de esa ronda cuentan como invalidas (como en las fichas de clase). Por eso los dos jobs tocan a la vez.
  $c = Corrida-Dos 'toca-codigo:^definicion-job:;toca-codigo:^ficha-job:'
  $e = $c.E
  Igual 'sale con 0' 0 $c.R.Codigo
  Igual 'el worktree queda limpio' '' (GitEn $e.Wt @('status', '--porcelain'))
  Igual 'no hay commits nuevos' 'inicial' (GitEn $e.Wt @('log', '--format=%s'))
  Igual 'App.java sigue como estaba' (Lee $e.Migrado 'src/main/java/com/acme/life/App.java') (Lee $e.Wt 'src/main/java/com/acme/life/App.java')
  $quedan = @('definicion-job', 'ficha-job' | ForEach-Object { @(Tareas $e $_ | Where-Object { $_.estado -eq 'atascada' -and $_.intentos -eq 2 -and $_.motivo -match 'toco' }).Count })
  Igual 'atascadas con el motivo (la definicion y los dos jobs)' '1 2' ($quedan -join ' ')
  $m = Mapa $e
  Comprueba 'el mapa sale sin pasos (la definicion no valio)' ($null -ne $m -and @((Del-Job $m 'cargaJob').pasos).Count -eq 0)
  Igual 'los dos jobs salen con redaccion atascada' 'atascada atascada' ((Job-De $e 'cargaJob').redaccion + ' ' + (Job-De $e 'informeJob').redaccion)
  Igual 'sin ninguna redaccion hecha no hay tarea de resumen' 0 @(Tareas $e 'resumen').Count
  # el resumen que toca el worktree
  $c = Corrida-Dos 'toca-codigo:^resumen:'
  $e = $c.E
  Igual 'resumen: sale con 0' 0 $c.R.Codigo
  Igual 'resumen: el worktree queda limpio' '' (GitEn $e.Wt @('status', '--porcelain'))
  $t = @(Tareas $e 'resumen')[0]
  Comprueba 'resumen: atascada con el motivo' ($t.estado -eq 'atascada' -and $t.motivo -match 'toco') "$($t.estado): $($t.motivo)"
  Comprueba 'no hay resumen.json' (-not (Test-Path -LiteralPath (Get-Ruta $e.Out 'datos/resumen.json')))
  Igual 'las fichas de job siguen hechas' 'hecha hecha' ((Job-De $e 'cargaJob').redaccion + ' ' + (Job-De $e 'informeJob').redaccion)
}

$Pruebas['39 fases: fichas-clase, mapa, fichas-job, resumen, pruebas-pre y hecha; con una clase atascada se hacen igual'] = {
  $e = Escenario-Dos 'fases'
  $g = 'json-roto:^Auxiliar1$'
  $esperadas = @(@('2', 'fichas-clase'), @('6', 'mapa'), @('1', 'fichas-job'), @('2', 'resumen'), @('1', 'pruebas-pre'), @('', 'hecha'))
  foreach ($x in $esperadas) {
    $a = Basicos $e
    if ($x[0]) { $a += @('-Limite', $x[0]) }
    $r = Migra $e $a $g
    Igual ("lanzamiento con limite '" + $x[0] + "' sale con 0") 0 $r.Codigo
    Igual ('la fase es ' + $x[1]) $x[1] (Estado $e).fase
  }
  $c = Tareas $e
  Igual 'una clase atascada y siete hechas' '1 7' ("$(Cuenta-Estado $c 'atascada') $(Cuenta-Estado $c 'hecha')")
  Comprueba 'hay mapa, dos fichas de job y resumen' ($null -ne (Mapa $e) -and $null -ne (Job-De $e 'cargaJob') -and $null -ne (Job-De $e 'informeJob') -and (Test-Path -LiteralPath (Get-Ruta $e.Out 'datos/resumen.json')))
  $j = Job-De $e 'cargaJob'
  Comprueba 'cargaJob dice que Auxiliar1 no tiene ficha' (@($j.sinFicha) -contains 'Auxiliar1') ($j | ConvertTo-Json -Compress -Depth 4)
  $cl = @((Del-Job (Mapa $e) 'cargaJob').clases | Where-Object { $_.clase -eq 'Auxiliar1' })[0]
  Comprueba 'y el mapa la marca sin ficha' ($null -ne $cl -and $cl.tieneFicha -eq $false)
  Igual 'las llamadas: 8 clases (+1 reintento), 1 definicion, 2 jobs, 1 resumen, 2 pruebas' 15 (Llamadas $e.Wt).Count
}

$Pruebas['40 definicion de un fichero demasiado largo: sin tarea, el job sale sin pasos y con su duda'] = {
  $e = Nuevo-Escenario 'largo' @()
  $t = (Jobs-Config @('largoJob:largoStep')).TrimEnd().TrimEnd('}')
  for ($i = 1; $i -le 950; $i++) { $t += "    private int campo$i;`n" }
  Escribe-Original $e @{ JobsConfig = ($t + "}`n"); LargoReader = (Clase-Con 'LargoReader') }
  $r = Migra $e (Basicos $e)
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'no hay tarea de definicion' 0 @(Tareas $e 'definicion-job').Count
  Igual 'ni llamada de definicion' 0 (Llamadas-De (Llamadas $e.Wt) 'definicion-').Count
  $j = Del-Job (Mapa $e) 'largoJob'
  Comprueba 'el job sale sin pasos, con la duda que dice por que' ($null -ne $j -and @($j.pasos).Count -eq 0 -and @($j.dudas).Count -eq 1 -and "$($j.dudas[0])" -match 'pasan? de 900 lineas') "$($j.dudas -join ' / ')"
  Igual 'y con las clases a las que llega desde el fichero' 'JobsConfig' (@($j.clases | ForEach-Object { $_.clase }) -join ' ')
}

$Pruebas['41 mapa: las clases de los pasos de los otros jobs no entran ni se atraviesan; una clase de paso de dos jobs entra en los dos'] = {
  $e = Nuevo-Escenario 'ajenas' @()
  $usa = @('CargaTasklet', 'InformeTasklet', 'CompartidoTasklet', 'ListenerJob')
  Escribe-Original $e @{
    JobsConfig = (Jobs-Config @('cargaJob:cargaStep,compartidoStep', 'informeJob:informeStep,compartidoStep') $usa)
    CargaTasklet = (Clase-Con 'CargaTasklet' @('LectorPropio'))
    LectorPropio = (Clase-Con 'LectorPropio')
    InformeTasklet = (Clase-Con 'InformeTasklet' @('EscritorPropio'))
    EscritorPropio = (Clase-Con 'EscritorPropio')
    CompartidoTasklet = (Clase-Con 'CompartidoTasklet')
    ListenerJob = (Clase-Con 'ListenerJob')
  }
  $r = Migra $e ((Basicos $e) + @('-Limite', '8'))
  Igual 'sale con 0' 0 $r.Codigo
  $m = Mapa $e
  Comprueba 'hay mapa.json con los dos jobs' ($null -ne $m -and @($m.jobs).Count -eq 2) (Cola $r.Salida)
  if ($null -eq $m -or @($m.jobs).Count -ne 2) { return }
  $a = Del-Job $m 'cargaJob'
  $b = Del-Job $m 'informeJob'
  Igual 'cargaJob: sus pasos' 'cargaStep: CargaTasklet; compartidoStep: CompartidoTasklet' ((@($a.pasos | ForEach-Object { $_.paso + ': ' + (@($_.clases) -join ' ') })) -join '; ')
  Igual 'cargaJob: su paso, el compartido, su colaborador, el listener y el fichero que lo define; ni el paso ni el colaborador del otro' 'CargaTasklet CompartidoTasklet JobsConfig LectorPropio ListenerJob' ((@($a.clases | ForEach-Object { $_.clase } | Sort-Object)) -join ' ')
  Igual 'informeJob: lo mismo, con lo suyo' 'CompartidoTasklet EscritorPropio InformeTasklet JobsConfig ListenerJob' ((@($b.clases | ForEach-Object { $_.clase } | Sort-Object)) -join ' ')
  Igual 'el fichero que define el job sigue siendo semilla (definicion) y por el llega el listener (referencia)' 'definicion referencia' ((@($a.clases | Where-Object { $_.clase -in @('ListenerJob', 'JobsConfig') } | Sort-Object clase | ForEach-Object { $_.por })) -join ' ')
  Igual 'sinJob: todas las clases cuelgan de algun job' 0 @($m.sinJob).Count
}

$Pruebas['42 lenguaje de negocio: solo valen los nombres sencillos; el compuesto o el .java se rechaza, tambien en el orden y el glosario del resumen'] = {
  $codigo = @'
$Fuentes = @('Recibo', 'Estado', 'IBAN', 'GestorRecibos', 'SFTPClient', 'ParserCsv') | ForEach-Object { [pscustomobject]@{ BaseName = $_ } }
function Prueba([string]$Texto) {
  $m = Test-LenguajeNegocio ([ordered]@{ titulo = $Texto })
  if ($m) { return ('MAL ' + $m) }
  return 'BIEN'
}
'T1=' + (Prueba 'Recibo con importe minimo')
'T2=' + (Prueba 'Estado del envio')
'T3=' + (Prueba 'El IBAN tiene que ser valido')
'T4=' + (Prueba 'Carga con GestorRecibos')
'T5=' + (Prueba 'Mira Recibo.java')
'T6=' + (Prueba 'Lo envia SFTPClient')
'T7=' + (Prueba 'Lo lee ParserCsv')
'T8=' + (Prueba 'Mira Inventada.java')
'T9=' + (Prueba 'Los gestores de recibos y el estado')
function Resumen([string]$Orden, [string]$Termino, [string]$Definicion) {
  $dir = Join-Path '{{DIR}}' ('r' + [guid]::NewGuid().ToString('N').Substring(0, 6))
  [void](New-Item -ItemType Directory -Path (Join-Path $dir '.rescate/tareas') -Force)
  $o = [ordered]@{ resumen = 'El batch hace cosas.'; orden = @([ordered]@{ job = 'cargaJob'; motivo = $Orden }); glosario = @([ordered]@{ termino = $Termino; definicion = $Definicion }) }
  [System.IO.File]::WriteAllText((Join-Path $dir '.rescate/tareas/resumen.json'), (ConvertTo-Json -InputObject $o -Depth 5))
  $t = [pscustomobject]@{ id = 'resumen'; entradas = [pscustomobject]@{ jobs = @('cargaJob') } }
  $r = Test-Resumen $t $dir
  if ($r.Ok) { return 'BIEN' }
  return ('MAL ' + $r.Motivo)
}
'R1=' + (Resumen 'Va primero.' 'remesa' 'Un grupo de recibos.')
'R2=' + (Resumen 'Va primero.' 'recibo' 'El Recibo es un cobro y el Estado dice como va.')
'R3=' + (Resumen 'Lo hace GestorRecibos.' 'remesa' 'Un grupo de recibos.')
'R4=' + (Resumen 'Va primero.' 'ParserCsv' 'Un grupo de recibos.')
'R5=' + (Resumen 'Va primero.' 'remesa' 'Lo prepara SFTPClient.')
'FIN'
'@
  $codigo = $codigo.Replace('{{DIR}}', (Join-Path $Dir 'lenguaje'))
  $r = En-Biblioteca 'lenguaje' $codigo
  Igual 'el script de prueba sale con 0' 0 $r.Codigo
  $v = @{}
  foreach ($l in ($r.Salida -split "`n")) { if ($l -match '^([TR]\d)=(.*?)\r?$') { $v[$Matches[1]] = $Matches[2] } }
  foreach ($k in @('T1', 'T2', 'T3', 'T9', 'R1', 'R2')) { Igual "$k vale" 'BIEN' $v[$k] }
  Comprueba 'el titulo con un nombre compuesto no vale y el motivo lo nombra' ($v['T4'] -match '^MAL' -and $v['T4'] -match 'titulo' -and $v['T4'] -match 'GestorRecibos') $v['T4']
  Comprueba 'un nombre sencillo seguido de .java no vale' ($v['T5'] -match '^MAL' -and $v['T5'] -match 'Recibo\.java') $v['T5']
  Comprueba 'SFTPClient (mayusculas seguidas) es compuesto' ($v['T6'] -match '^MAL' -and $v['T6'] -match 'SFTPClient') $v['T6']
  Comprueba 'ParserCsv es compuesto' ($v['T7'] -match '^MAL') $v['T7']
  Comprueba 'cualquier fichero .java sobra, sea o no del original' ($v['T8'] -match '^MAL' -and $v['T8'] -match 'Inventada\.java') $v['T8']
  Comprueba 'un compuesto en orden[].motivo invalida el resumen y el motivo dice el campo' ($v['R3'] -match '^MAL' -and $v['R3'] -match 'orden\[0\]\.motivo' -and $v['R3'] -match 'GestorRecibos') $v['R3']
  Comprueba 'un compuesto en el termino del glosario, igual' ($v['R4'] -match '^MAL' -and $v['R4'] -match 'glosario\[0\]\.termino') $v['R4']
  Comprueba 'un compuesto en la definicion del glosario, igual' ($v['R5'] -match '^MAL' -and $v['R5'] -match 'glosario\[0\]\.definicion' -and $v['R5'] -match 'SFTPClient') $v['R5']
}

# ============================== NEGOCIO: PRUEBA EN PRE Y PAGINAS ==============================
function Pruebas-De($E, [string]$Job) { return (Lee-Json (Get-Ruta $E.Out ('datos/pruebas/' + $Job + '.json'))) }

# Una pagina del informe (UTF-8) de la carpeta de salida de un escenario, o de una copia (con $Salida).
function Pagina([string]$Salida, [string]$Nombre) {
  $r = Get-Ruta $Salida $Nombre
  if (-not (Test-Path -LiteralPath $r)) { return '' }
  return [System.IO.File]::ReadAllText($r, (New-Object System.Text.UTF8Encoding($false)))
}

# La seccion de un job (un <article id="job-<job>">) de la pagina del batch original.
function Articulo([string]$Html, [string]$Job) {
  $m = [regex]::Match($Html, '(?s)<article[^>]*id="job-' + [regex]::Escape($Job) + '".*?</article>')
  return $m.Value
}

# Los ficheros de la corrida de un escenario, en otra carpeta, para tocar los datos sin afectar a los demas tests.
function Copia-Salida($E, [string]$Nombre) {
  $raiz = Join-Path $Dir $Nombre
  if (Test-Path -LiteralPath $raiz) { Remove-Item -LiteralPath $raiz -Recurse -Force }
  [void](New-Item -ItemType Directory -Path $raiz -Force)
  $dest = Join-Path $raiz 'migracion-batch'
  Copy-Item -LiteralPath $E.Out -Destination $dest -Recurse
  return $dest
}

# Llama a Write-Informes sobre una carpeta de salida, cargando comun.ps1, tareas.ps1 e informe.ps1 como migracion.ps1.
function Genera-Informes([string]$Salida) {
  $raiz = Split-Path -Parent $Script
  $cab = "`$ErrorActionPreference = 'Stop'`n. '" + (Join-Path $raiz 'comun.ps1') + "'`n. '" + (Join-Path $raiz 'tareas.ps1') + "'`n"
  if (Test-Path -LiteralPath (Join-Path $raiz 'lanzadores.ps1')) { $cab += ". '" + (Join-Path $raiz 'lanzadores.ps1') + "'`n" }
  $cab += ". '" + (Join-Path $raiz 'informe.ps1') + "'`n"
  Escribe (Join-Path $Dir 'biblioteca') 'informes.ps1' ($cab + "Write-Informes -Salida '" + $Salida + "'`n'INFORMES-OK'`n")
  return (Lanzar (Join-Path (Join-Path $Dir 'biblioteca') 'informes.ps1') @())
}

function Hash-De([string]$Ruta) { return (Get-FileHash -LiteralPath $Ruta -Algorithm SHA256).Hash }

function Guarda-Json([string]$Ruta, $Objeto) { [System.IO.File]::WriteAllText($Ruta, (ConvertTo-Json -InputObject $Objeto -Depth 8)) }

# Las refs de regla y error que lleva un prompt de prueba-pre (lineas "clase-xxxxxxxx#n [regla] texto"), en orden.
function Refs-A-Cubrir([string]$Prompt) {
  return @([regex]::Matches($Prompt, '(?m)^(clase-[0-9a-f]{8}#\d+) \[(?:regla|error)\] ') | ForEach-Object { $_.Groups[1].Value })
}

$Pruebas['43 prueba-pre: el prompt lleva los pasos, los hechos que citan y las variables, sin leer codigo; sale datos/pruebas/<job>.json con redaccion hecha'] = {
  $e = Escenario-Dos 'pre-vars'
  Escribe $e.Migrado 'src/main/resources/application.yml' "batch:`n  ruta: `${RUTA_ENTRADA:/entrada}`n  clave: `${CLAVE_BANCO}`n"
  [void](GitEn $e.Migrado @('add', '-A'))
  [void](GitEn $e.Migrado @('commit', '-q', '-m', 'recursos'))
  $r = Migra $e (Basicos $e) $GuionBase
  Igual 'sale con 0' 0 $r.Codigo
  $t = @(Tareas $e 'prueba-pre' | Where-Object { $_.entradas.job -eq 'cargaJob' })
  Igual 'hay una tarea prueba-pre para cargaJob' 1 $t.Count
  if ($t.Count -ne 1) { return }
  Igual 'hecha en un intento' 'hecha 1' "$($t[0].estado) $($t[0].intentos)"
  $p = Prompt-De $e $t[0]
  $j = Job-De $e 'cargaJob'
  $citados = @($j.pasos | ForEach-Object { $_.refs } | Select-Object -Unique)
  $todos = @(@($j.necesita) + @($j.produce) + @($j.conexiones) + @($j.reglas) + @($j.siFalla) | ForEach-Object { $_.ref })
  $otros = @($todos | Where-Object { $citados -notcontains $_ })
  Comprueba 'la ficha del job cita algo y hay hechos que no cita (la prueba distingue)' ($citados.Count -gt 0 -and $otros.Count -gt 0) "$($citados.Count) citados, $($otros.Count) otros"
  $faltan = @($citados | Where-Object { $p -notmatch ('(?m)^' + [regex]::Escape($_) + ' \[') })
  Comprueba 'el prompt lleva cada hecho que citan los pasos, con su referencia y su tipo' ($faltan.Count -eq 0) ($faltan -join ' ')
  $sobran = @($otros | Where-Object { $p -match ('(?m)^' + [regex]::Escape($_) + ' \[') })
  Comprueba 'y ninguno de los que no citan' ($sobran.Count -eq 0) ($sobran -join ' ')
  Comprueba 'lleva el titulo y el texto de los pasos' ($p.Contains('Primer paso') -and $p.Contains('Hace lo primero.') -and $p.Contains('Segundo paso'))
  Comprueba 'lleva los nombres de las variables' ($p.Contains('RUTA_ENTRADA') -and $p.Contains('CLAVE_BANCO'))
  Comprueba 'no manda leer ningun fichero ni nombra el original' ($p -notmatch '(?m)^LEER:' -and -not $p.Contains($e.Legacy))
  Comprueba 'no lleva nombres de clase (ni como cabecera de los datos)' ($p -notmatch '(?m)^### ' -and $p -notmatch 'CargaReader')
  $ll = Llamadas-De (Llamadas $e.Wt) $t[0].id
  Igual 'una llamada' 1 $ll.Count
  Comprueba 'sin --add-dir y con esfuerzo high' ($ll.Count -eq 1 -and $ll[0].flags -notmatch '--add-dir' -and $ll[0].flags -match '--effort=high' -and $ll[0].flags -match '--no-custom-instructions') (($ll | ForEach-Object { $_.flags }) -join ' | ')
  $x = Pruebas-De $e 'cargaJob'
  Comprueba 'existe datos/pruebas/cargaJob.json' ($null -ne $x) (Cola $r.Salida)
  if ($null -eq $x) { return }
  Igual 'job' 'cargaJob' $x.job
  Igual 'redaccion' 'hecha' $x.redaccion
  Comprueba 'preparar y comprobar con texto y referencias' (@($x.preparar).Count -ge 1 -and @($x.comprobar).Count -ge 1 -and @(@($x.preparar) + @($x.comprobar) | Where-Object { $_.texto -and @($_.refs).Count -ge 1 }).Count -eq (@($x.preparar).Count + @($x.comprobar).Count)) ($x | ConvertTo-Json -Compress -Depth 5)
  Comprueba 'cada caso con titulo, entrada, esperado y referencias' (@($x.casos).Count -ge 1 -and @($x.casos | Where-Object { $_.titulo -and $_.entrada -and $_.esperado -and @($_.refs).Count -ge 1 }).Count -eq @($x.casos).Count) ($x.casos | ConvertTo-Json -Compress -Depth 4)
  $aCubrir = @(Refs-A-Cubrir $p)
  $cubiertas = @($x.casos | ForEach-Object { $_.refs })
  Comprueba 'cada regla y error del prompt sale en las refs de algun caso' ($aCubrir.Count -ge 1 -and @($aCubrir | Where-Object { $cubiertas -notcontains $_ }).Count -eq 0) ($aCubrir -join ' ')
  Igual 'sinCaso vacio' 0 @($x.sinCaso).Count
  Comprueba 'el otro job tambien tiene su guion' ($null -ne (Pruebas-De $e 'informeJob'))
}

$Pruebas['44 prueba-pre: una referencia que no existe se reintenta con el motivo; dos veces, atascada y guion minimo sin IA'] = {
  $c = Corrida-Dos 'prueba-ref-mala:^prueba-pre:informeJob$'
  $e = $c.E
  Igual 'sale con 0' 0 $c.R.Codigo
  $t = @(Tareas $e 'prueba-pre' | Where-Object { $_.entradas.job -eq 'informeJob' })
  if ($t.Count -ne 1) { Comprueba 'hay una tarea prueba-pre para informeJob' $false (Cola $c.R.Salida); return }
  Igual 'atascada tras dos intentos' 'atascada 2' "$($t[0].estado) $($t[0].intentos)"
  Comprueba 'el motivo nombra la referencia que no existe' ($t[0].motivo -match 'clase-00000000#9') $t[0].motivo
  $ll = Llamadas-De (Llamadas $e.Wt) $t[0].id
  Comprueba 'el reintento lleva la correccion, con esa referencia, y esfuerzo high' ($ll.Count -eq 2 -and $ll[1].correccion -eq 'True' -and $ll[0].correccion -eq 'False' -and $ll[1].flags -match '--effort=high' -and (Prompt-De $e $t[0]) -match '(?s)## CORRECCI.*clase-00000000#9') (($ll | ForEach-Object { $_.correccion }) -join ' ')
  $x = Pruebas-De $e 'informeJob'
  Comprueba 'existe datos/pruebas/informeJob.json' ($null -ne $x)
  if ($null -eq $x) { return }
  Igual 'redaccion' 'atascada' $x.redaccion
  $reglas = @((Job-De $e 'informeJob').reglas | ForEach-Object { $_.texto })
  Comprueba 'guion minimo: un caso por regla, con la regla como titulo y entrada y esperado vacios' (@($x.casos).Count -ge 1 -and @($x.casos | Where-Object { $reglas -contains $_.titulo -and "$($_.entrada)" -eq '' -and "$($_.esperado)" -eq '' -and @($_.refs).Count -eq 1 }).Count -eq @($x.casos).Count) ($x.casos | ConvertTo-Json -Compress -Depth 4)
  Igual 'sin llamadas de mas: solo las dos de la tarea' 2 (Llamadas-De (Llamadas $e.Wt) 'prueba-informeJob').Count
  Igual 'el otro job queda hecho' 'hecha' (Pruebas-De $e 'cargaJob').redaccion
}

$Pruebas['45 prueba-pre: una regla sin caso se pide en el reintento; si sigue faltando, sinCaso la trae y la tarea vale'] = {
  $c = Corrida-Dos 'json-roto:^ficha-job:cargaJob$;prueba-falta-una-vez:^prueba-pre:cargaJob$;prueba-falta-siempre:^prueba-pre:informeJob$'
  $e = $c.E
  Igual 'sale con 0' 0 $c.R.Codigo
  Igual 'cargaJob: su ficha esta atascada' 'atascada' (Job-De $e 'cargaJob').redaccion
  $t = @(Tareas $e 'prueba-pre' | Where-Object { $_.entradas.job -eq 'cargaJob' })[0]
  Igual 'cargaJob: hecha en el segundo intento' 'hecha 2' "$($t.estado) $($t.intentos)"
  $p = Prompt-De $e $t
  $aCubrir = @(Refs-A-Cubrir $p)
  Comprueba 'sin ficha de job, el prompt lleva todas las reglas del job (tambien las de clases que ningun paso cita)' (@((Job-De $e 'cargaJob').reglas | Where-Object { $aCubrir -notcontains $_.ref }).Count -eq 0 -and $aCubrir.Count -ge 5) "$($aCubrir.Count)"
  $falta = $aCubrir[$aCubrir.Count - 1]
  Comprueba 'el reintento lleva el identificador de la regla que faltaba' ($p -match ('(?s)## CORRECCI.*' + [regex]::Escape($falta))) $falta
  $x = Pruebas-De $e 'cargaJob'
  Igual 'cargaJob: redaccion hecha y sinCaso vacio' 'hecha 0' "$($x.redaccion) $(@($x.sinCaso).Count)"
  Comprueba 'cargaJob: ahora la regla que faltaba sale en un caso' (@($x.casos | ForEach-Object { $_.refs }) -contains $falta)
  # siempre falta: la tarea vale y sinCaso la trae
  $t = @(Tareas $e 'prueba-pre' | Where-Object { $_.entradas.job -eq 'informeJob' })[0]
  Igual 'informeJob: hecha tras dos intentos, no atascada' 'hecha 2' "$($t.estado) $($t.intentos)"
  $falta = (@(Refs-A-Cubrir (Prompt-De $e $t)))[-1]
  $x = Pruebas-De $e 'informeJob'
  Igual 'informeJob: redaccion hecha' 'hecha' $x.redaccion
  Igual 'informeJob: sinCaso trae una regla' 1 @($x.sinCaso).Count
  Comprueba 'con su referencia, su tipo y su texto, y la regla no sale en ningun caso' ($x.sinCaso[0].ref -eq $falta -and $x.sinCaso[0].tipo -eq 'regla' -and $x.sinCaso[0].texto -and @($x.casos | ForEach-Object { $_.refs }) -notcontains $falta) ($x.sinCaso | ConvertTo-Json -Compress)
  Igual 'el texto de sinCaso es el de la regla del job' (@((Job-De $e 'informeJob').reglas | Where-Object { $_.ref -eq $falta })[0]).texto $x.sinCaso[0].texto
}

$Pruebas['46 prueba-pre: un nombre de clase en un texto no pasa; mas de 40 casos tampoco'] = {
  $c = Corrida-Dos 'prueba-clase-en-texto:^prueba-pre:cargaJob$;prueba-de-mas:^prueba-pre:informeJob$'
  $e = $c.E
  Igual 'sale con 0' 0 $c.R.Codigo
  $t = @(Tareas $e 'prueba-pre' | Where-Object { $_.entradas.job -eq 'cargaJob' })[0]
  Igual 'cargaJob: hecha en el segundo intento' 'hecha 2' "$($t.estado) $($t.intentos)"
  $p = Prompt-De $e $t
  Comprueba 'la correccion nombra la clase y el campo' ($p -match '(?s)## CORRECCI.*CargaReader' -and $p -match '(?s)## CORRECCI.*casos\[0\]\.titulo') ((($p -split "`n") | Select-Object -Last 6) -join ' / ')
  Comprueba 'el guion final ya no la lleva' ((Get-Content -LiteralPath (Get-Ruta $e.Out 'datos/pruebas/cargaJob.json') -Raw) -notmatch 'CargaReader')
  $t = @(Tareas $e 'prueba-pre' | Where-Object { $_.entradas.job -eq 'informeJob' })[0]
  Igual 'informeJob: 41 casos, atascada tras dos intentos' 'atascada 2' "$($t.estado) $($t.intentos)"
  Comprueba 'el motivo habla de los 40 casos' ($t.motivo -match '40') $t.motivo
}

$Pruebas['47 prueba-pre: un job sin reglas ni errores no llama al modelo y deja el guion minimo con lo que necesita y produce'] = {
  $e = Escenario-Dos 'pre-sin-reglas'
  Escribe-Original $e @{ InformeWriter = "package com.acme.old;`n`npublic class InformeWriter {`n    private int a = 1;`n    private int b = 2;`n}`n" }
  $r = Migra $e (Basicos $e) 'tipos-variados:^InformeWriter$;sin-datos:^JobsConfig$'
  Igual 'sale con 0' 0 $r.Codigo
  $j = Job-De $e 'informeJob'
  Comprueba 'informeJob: la ficha cita un fichero de entrada y uno de salida y ninguna regla ni error' ($null -ne $j -and @($j.necesita).Count -eq 1 -and @($j.produce).Count -eq 1 -and @($j.reglas).Count -eq 0 -and @($j.siFalla).Count -eq 0) (Cola $r.Salida)
  Igual 'ninguna llamada de prueba-pre para informeJob' 0 (Llamadas-De (Llamadas $e.Wt) 'prueba-informeJob').Count
  Igual 'ni tarea' 0 @(Tareas $e 'prueba-pre' | Where-Object { $_.entradas.job -eq 'informeJob' }).Count
  $x = Pruebas-De $e 'informeJob'
  Comprueba 'existe datos/pruebas/informeJob.json' ($null -ne $x)
  if ($null -eq $x) { return }
  Igual 'redaccion' 'hecha' $x.redaccion
  Igual 'sin casos' 0 @($x.casos).Count
  Igual 'sinCaso vacio' 0 @($x.sinCaso).Count
  Comprueba 'preparar sale de lo que necesita (con su referencia)' (@($x.preparar).Count -eq 1 -and @($x.preparar)[0].texto -eq @($j.necesita)[0].texto -and @(@($x.preparar)[0].refs)[0] -eq @($j.necesita)[0].ref) ($x.preparar | ConvertTo-Json -Compress -Depth 4)
  Comprueba 'comprobar sale de lo que produce (con su referencia)' (@($x.comprobar).Count -eq 1 -and @($x.comprobar)[0].texto -eq @($j.produce)[0].texto -and @(@($x.comprobar)[0].refs)[0] -eq @($j.produce)[0].ref) ($x.comprobar | ConvertTo-Json -Compress -Depth 4)
  Igual 'cargaJob, que si tiene reglas, si llama al modelo' 1 (Llamadas-De (Llamadas $e.Wt) 'prueba-cargaJob').Count
}

$Pruebas['48 prueba-pre: la fase va despues del resumen; relanzar no repite las tareas hechas'] = {
  $e = Escenario-Dos 'pre-reanuda'
  $r = Migra $e ((Basicos $e) + @('-Limite', '12'))
  Igual 'cortado tras el resumen sale con 0' 0 $r.Codigo
  Igual 'la fase es pruebas-pre' 'pruebas-pre' (Estado $e).fase
  Igual 'todavia ninguna llamada de prueba-pre' 0 (Llamadas-De (Llamadas $e.Wt) 'prueba-').Count
  Comprueba 'ni datos/pruebas' (-not (Test-Path -LiteralPath (Get-Ruta $e.Out 'datos/pruebas')) -or @(Get-ChildItem -LiteralPath (Get-Ruta $e.Out 'datos/pruebas') -File).Count -eq 0)
  $r = Migra $e (Basicos $e)
  Igual 'relanzado sale con 0' 0 $r.Codigo
  Igual 'la fase acaba' 'hecha' (Estado $e).fase
  Igual 'dos llamadas de prueba-pre, una por job' 2 (Llamadas-De (Llamadas $e.Wt) 'prueba-').Count
  Igual 'catorce en total (8 clases, 1 definicion, 2 jobs, 1 resumen, 2 pruebas)' 14 (Llamadas $e.Wt).Count
  $r = Migra $e (Basicos $e)
  Igual 'otra vez: sale con 0' 0 $r.Codigo
  Igual 'no hay ninguna llamada nueva' 14 (Llamadas $e.Wt).Count
  Igual 'cada tarea se llamo una sola vez' 14 @((Llamadas $e.Wt) | Select-Object -ExpandProperty id -Unique).Count
  Igual 'las dos pruebas hechas' 2 @(Tareas $e 'prueba-pre' | Where-Object { $_.estado -eq 'hecha' }).Count
}

$Pruebas['49 paginas: con todos los datos salen index.html y 1-batch-original.html; cada job con su seccion, su dibujo y su guion de prueba en pre con todos sus casos'] = {
  $c = Corrida-Dos $GuionBase
  $e = $c.E
  $i = Pagina $e.Out 'index.html'
  $o = Pagina $e.Out '1-batch-original.html'
  Comprueba 'existen index.html y 1-batch-original.html' ($i -and $o) (Cola $c.R.Salida)
  if (-not ($i -and $o)) { return }
  foreach ($h in @($i, $o)) {
    Igual 'un solo h1' 1 ([regex]::Matches($h, '<h1[ >]').Count)
    Comprueba 'lang="es" y charset utf-8' ($h -match '<html lang="es"' -and $h -match '<meta charset="utf-8">')
  }
  $bytes = [System.IO.File]::ReadAllBytes((Get-Ruta $e.Out 'index.html'))
  Comprueba 'UTF-8 sin BOM' (-not ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB))
  Comprueba 'la portada enlaza a la pagina del batch original' ($i -match 'href="1-batch-original\.html"')
  Comprueba 'la pagina del batch original enlaza a la portada' ($o -match 'href="index\.html"')
  $r = Lee-Json (Get-Ruta $e.Out 'datos/resumen.json')
  Comprueba 'el resumen sale' ($o.Contains([System.Net.WebUtility]::HtmlEncode($r.resumen)) -or $o.Contains($r.resumen)) $r.resumen
  $orden = @($r.orden | ForEach-Object { $_.job })
  foreach ($job in $orden) {
    $a = Articulo $o $job
    Comprueba "$job : tiene su seccion" ($a.Length -gt 0)
    if (-not $a) { continue }
    $f = Job-De $e $job
    $x = Pruebas-De $e $job
    Comprueba "$job : lleva su titulo" ($a.Contains($f.titulo))
    Comprueba "$job : lleva el dibujo del flujo" ($a -match 'class="flujo"')
    Igual "$job : un paso dibujado por cada paso de la ficha" @($f.pasos).Count ([regex]::Matches($a, 'class="paso"').Count)
    Comprueba "$job : lleva el bloque de como probarlo en pre" ($a -match ('id="pre-' + $job + '"'))
    Igual "$job : todos sus casos" @($x.casos).Count ([regex]::Matches($a, 'class="caso"').Count)
    Comprueba "$job : cada caso con lo que se mete y lo que tiene que pasar" (@($x.casos | Where-Object { $a.Contains($_.titulo) -and $a.Contains($_.entrada) -and $a.Contains($_.esperado) }).Count -eq @($x.casos).Count)
    Comprueba "$job : lleva antes de lanzarlo y que mirar al acabar" (@($x.preparar | Where-Object { $a.Contains($_.texto) }).Count -eq @($x.preparar).Count -and @($x.comprobar | Where-Object { $a.Contains($_.texto) }).Count -eq @($x.comprobar).Count)
    Comprueba "$job : las pruebas van plegadas" ($a -match '(?s)<details[^>]*>\s*<summary>[^<]*d.nde lo dice el c.digo')
  }
  Comprueba 'los jobs salen en el orden del resumen' ($o.IndexOf('id="job-' + $orden[0] + '"') -lt $o.IndexOf('id="job-' + $orden[1] + '"'))
  Comprueba 'el glosario sale' ($o -match 'Palabras que se usan' -and $o.Contains('remesa'))
}

$Pruebas['50 paginas: todo texto de los datos sale escapado (un script es texto, no codigo)'] = {
  $c = Corrida-Dos $GuionBase
  $s = Copia-Salida $c.E 'escapa'
  $mal = '<script>alert(1)</script>'
  $d = Join-Path $s 'datos'
  $j = Lee-Json (Join-Path $d 'jobs/cargaJob.json')
  $j.titulo = $mal
  $j.pasos[0].texto = 'Mira <b>esto</b> y ' + $mal
  $j.reglas[0].texto = 'Importe "A" & ''B'' <i>x</i>'
  $j.dudas = @($mal)
  Guarda-Json (Join-Path $d 'jobs/cargaJob.json') $j
  $x = Lee-Json (Join-Path $d 'pruebas/cargaJob.json')
  $x.casos[0].titulo = $mal
  $x.casos[0].entrada = 'a & b "c"'
  Guarda-Json (Join-Path $d 'pruebas/cargaJob.json') $x
  $r = Lee-Json (Join-Path $d 'resumen.json')
  $r.glosario[0].definicion = '<img src=x onerror=alert(1)>'
  Guarda-Json (Join-Path $d 'resumen.json') $r
  Guarda-Json (Join-Path $d 'variables.json') @([ordered]@{ variable = 'X_Y'; porDefecto = 'a&b "c"'; fichero = 'src/main/resources/application.yml'; linea = 1 })
  $st = Lee-Json (Join-Path $d 'estado.json')
  $st.modelo = $mal
  Guarda-Json (Join-Path $d 'estado.json') $st
  $g = Genera-Informes $s
  Igual 'Write-Informes sale con 0' 0 $g.Codigo
  Comprueba 'dice INFORMES-OK' ($g.Salida -match 'INFORMES-OK') (Cola $g.Salida)
  $o = Pagina $s '1-batch-original.html'
  $i = Pagina $s 'index.html'
  Comprueba 'hay paginas' ($o -and $i) (Cola $g.Salida)
  foreach ($h in @($o, $i)) { Comprueba 'ninguna etiqueta <script en la pagina' ($h -notmatch '(?i)<script') }
  Comprueba 'el script de un titulo sale como texto' ($o.Contains('&lt;script&gt;alert(1)&lt;/script&gt;'))
  Comprueba 'el modelo con un script sale escapado en la portada' ($i.Contains('&lt;script&gt;alert(1)&lt;/script&gt;'))
  Comprueba '& y comillas salen escapados' ($o.Contains('Importe &quot;A&quot; &amp; &#39;B&#39; &lt;i&gt;x&lt;/i&gt;') -and $o.Contains('a &amp; b &quot;c&quot;'))
  Comprueba 'una etiqueta img de un dato sale como texto' ($o -notmatch '(?i)<img' -and $o.Contains('&lt;img src=x onerror=alert(1)&gt;'))
  Comprueba 'un valor por defecto con & y comillas, igual' ($o.Contains('a&amp;b &quot;c&quot;'))
  Comprueba 'una duda con un script, igual' (-not ($o -match '(?i)<script') -and $o.Contains('&lt;script&gt;'))
}

$Pruebas['51 paginas: sin nada externo (ni http, ni script, ni import) y sus enlaces llevan a sitios que existen'] = {
  $c = Corrida-Dos $GuionBase
  foreach ($n in @('index.html', '1-batch-original.html', '2-problemas.html', '3-original-vs-migrado.html', '4-correcciones.html', '5-buenas-practicas.html')) {
    $h = Pagina $c.E.Out $n
    Comprueba "$n : existe" ($h.Length -gt 0)
    Comprueba "$n : ni http:// ni https://" ($h -notmatch 'https?://')
    Comprueba "$n : ni <script ni @import ni <link ni <img ni <iframe" ($h -notmatch '(?i)<script|@import|<link|<img|<iframe')
    Comprueba "$n : ningun src ni href que no sea del propio informe" (@([regex]::Matches($h, '(?i)\b(?:src|href)\s*=\s*"(?!#)([^"]*)"') | Where-Object { -not (Test-Path -LiteralPath (Get-Ruta $c.E.Out $_.Groups[1].Value)) }).Count -eq 0) (@([regex]::Matches($h, '(?i)\b(?:src|href)\s*=\s*"(?!#)([^"]*)"') | ForEach-Object { $_.Groups[1].Value }) -join ' ')
    Comprueba "$n : sin url() externas" ($h -notmatch '(?i)url\(\s*[''"]?(https?:|//)')
    $dentro = @([regex]::Matches($h, '(?i)href="#([^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Where-Object { $h -notmatch ('id="' + [regex]::Escape($_) + '"') })
    Comprueba "$n : los enlaces #ancla llevan a un id que existe" ($dentro.Count -eq 0) ($dentro -join ' ')
  }
}

$Pruebas['52 paginas: a medias se generan y dicen que fase falta; tambien al parar'] = {
  $e = Escenario-Dos 'pre-medias'
  $r = Migra $e ((Basicos $e) + @('-Limite', '8'))
  Igual 'solo con las fichas de clase: sale con 0' 0 $r.Codigo
  $o = Pagina $e.Out '1-batch-original.html'
  $i = Pagina $e.Out 'index.html'
  Comprueba 'las dos paginas existen' ($o -and $i) (Cola $r.Salida)
  Comprueba 'el batch original dice que la fase mapa no ha terminado' ($o -match 'la fase mapa no ha terminado') 
  Comprueba 'la portada dice en que fase va' ($i -match 'mapa')
  $r = Migra $e ((Basicos $e) + @('-Limite', '1'))
  Igual 'con el mapa hecho: sale con 0' 0 $r.Codigo
  $o = Pagina $e.Out '1-batch-original.html'
  Comprueba 'cada job del mapa sale con su seccion' ((Articulo $o 'cargaJob') -and (Articulo $o 'informeJob'))
  Comprueba 'y dicen que la fase fichas-job no ha terminado' ((Articulo $o 'cargaJob') -match 'la fase fichas-job no ha terminado')
  Comprueba 'el recorrido tambien' ($o -match 'la fase resumen no ha terminado')
  # al parar: la portada trae el motivo y el texto para pegar
  $f = Nuevo-Escenario 'pre-parada' @('Clase1', 'Clase2', 'Clase3', 'Clase4', 'Clase5', 'Clase6', 'Clase7')
  $r = Migra $f (Basicos $f) 'falla-siempre:^Clase'
  Igual 'la parada sale con 2' 2 $r.Codigo
  $s = Estado $f
  $i = Pagina $f.Out 'index.html'
  Comprueba 'la portada existe y dice el motivo de la parada' ($i -match 'copilot-no-responde') (Cola $r.Salida)
  Comprueba 'lleva el texto de ayuda listo para pegar' ($i.Contains([System.Net.WebUtility]::HtmlEncode($s.parada.ayuda).Replace('&#39;', '&#39;')) -or $i -match 'Estoy ejecutando migracion\.ps1')
}

$Pruebas['53 paginas: dos llamadas seguidas dejan los mismos bytes'] = {
  $c = Corrida-Dos $GuionBase
  $s = Copia-Salida $c.E 'idempotente'
  $paginas = @('index.html', '1-batch-original.html', '2-problemas.html', '3-original-vs-migrado.html', '4-correcciones.html', '5-buenas-practicas.html')
  $g = Genera-Informes $s
  Igual 'la primera sale con 0' 0 $g.Codigo
  $antes = @{}
  foreach ($n in $paginas) { $antes[$n] = Hash-De (Join-Path $s $n) }
  $g = Genera-Informes $s
  Igual 'la segunda sale con 0' 0 $g.Codigo
  foreach ($n in $paginas) { Igual "$n igual" $antes[$n] (Hash-De (Join-Path $s $n)) }
  Comprueba 'y es lo mismo que dejo migracion.ps1' ((Hash-De (Join-Path $c.E.Out '1-batch-original.html')) -eq $antes['1-batch-original.html'] -and (Hash-De (Join-Path $c.E.Out '2-problemas.html')) -eq $antes['2-problemas.html'])
  Comprueba 'no deja ficheros temporales' (@(Get-ChildItem -LiteralPath $s -File | Where-Object { $_.Name -notmatch '\.html$' }).Count -eq 0)
}

$Pruebas['54 paginas: etiquetas Medido, Leido por la IA con prueba y Sin comprobar donde toca'] = {
  $c = Corrida-Dos 'json-roto:^ficha-job:informeJob$;json-roto:^Auxiliar1$'
  $e = $c.E
  $o = Pagina $e.Out '1-batch-original.html'
  $i = Pagina $e.Out 'index.html'
  $a = Articulo $o 'cargaJob'
  $b = Articulo $o 'informeJob'
  Comprueba 'hay las dos secciones' ($a -and $b) (Cola $c.R.Salida)
  if (-not ($a -and $b)) { return }
  $cabA = [regex]::Match($a, '(?s)<header class="job-cab".*?</header>').Value
  $cabB = [regex]::Match($b, '(?s)<header class="job-cab".*?</header>').Value
  Comprueba 'cargaJob (redaccion hecha): su cabecera dice Leido por la IA, con prueba' ($cabA -match 'Le.do por la IA, con prueba' -and $cabA -notmatch 'Sin comprobar')
  Comprueba 'informeJob (redaccion atascada): su cabecera dice Sin comprobar' ($cabB -match 'Sin comprobar' -and $cabB -notmatch 'Le.do por la IA')
  Comprueba 'un hecho con su cita sale como leido por la IA con prueba (el job de redaccion atascada tambien)' ([regex]::Matches($b, 'Le.do por la IA, con prueba').Count -ge 1)
  Comprueba 'el job atascado dice que no se ha podido redactar' ($b -match 'No se ha podido redactar')
  Comprueba 'las cifras que cuenta el script salen como Medido (portada)' ($i -match 'Medido')
  Comprueba 'las dudas salen como Sin comprobar' ($a -match '(?s)Dudas.*Sin comprobar' -or $b -match '(?s)Dudas.*Sin comprobar')
}

$Pruebas['55 paginas: la portada pone en lo que te toca una tarea atascada, una clase sin ficha, una duda y una regla sin caso'] = {
  $c = Corrida-Dos 'json-roto:^ficha-job:informeJob$;json-roto:^Auxiliar1$'
  $e = $c.E
  $i = Pagina $e.Out 'index.html'
  $toca = [regex]::Match($i, '(?s)<section[^>]*id="lo-que-te-toca".*?</section>').Value
  Comprueba 'la portada tiene la seccion lo que te toca' ($toca.Length -gt 0) (Cola $c.R.Salida)
  if (-not $toca) { return }
  $t = @(Tareas $e 'ficha-job' | Where-Object { $_.entradas.job -eq 'informeJob' })[0]
  Comprueba 'la tarea atascada de la ficha de job, con su motivo' ($toca.Contains($t.id) -and $toca.Contains([System.Net.WebUtility]::HtmlEncode($t.motivo.Substring(0, 30)))) $t.motivo
  $a = @(Tareas $e | Where-Object { $_.estado -eq 'atascada' })[0]
  Comprueba 'la ficha de clase atascada' ($a -and $toca.Contains('Auxiliar1.java')) ($a.entradas.fichero)
  Comprueba 'la clase sin ficha de cargaJob' ($toca -match 'cargaJob' -and $toca -match 'Auxiliar1')
  Comprueba 'una duda de una ficha de job (la de informeJob, que no se pudo redactar)' ($toca.Contains('No se ha podido redactar este job'))
  # una regla sin caso de prueba
  $d = Corrida-Dos 'prueba-falta-siempre:^prueba-pre:informeJob$'
  $x = Pruebas-De $d.E 'informeJob'
  $toca = [regex]::Match((Pagina $d.E.Out 'index.html'), '(?s)<section[^>]*id="lo-que-te-toca".*?</section>').Value
  Comprueba 'una regla sin caso de prueba (sinCaso)' ($x.sinCaso.Count -eq 1 -and $toca.Contains($x.sinCaso[0].texto)) ($x.sinCaso | ConvertTo-Json -Compress)
  $o = Pagina $d.E.Out '1-batch-original.html'
  Comprueba 'y en la pagina del job sale aparte, como regla sin caso de prueba, sin comprobar' ((Articulo $o 'informeJob') -match '(?s)sin caso de prueba.*Sin comprobar' -and (Articulo $o 'informeJob').Contains($x.sinCaso[0].texto))
}

# ================================ RELANZAR: FECHA DE CREADO ================================
$Pruebas['56 relanzar: creado sigue siendo el texto ISO de la primera vez y la portada da cuando empezo y cuanto lleva'] = {
  $e = Nuevo-Escenario 'relanza-fecha' @('Clase1')
  $rx = '"creado":\s*"([^"]*)"'
  $r = Migra $e (Basicos $e)
  Igual 'primer lanzamiento sale con 0' 0 $r.Codigo
  $creado = [regex]::Match((Lee $e.Out 'datos/estado.json'), $rx).Groups[1].Value
  Comprueba 'la primera vez creado es un texto ISO' ($creado -match '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d$') $creado
  $r = Migra $e (Basicos $e)
  Igual 'relanzado sale con 0' 0 $r.Codigo
  $de = [regex]::Match((Lee $e.Out 'datos/estado.json'), $rx).Groups[1].Value
  Igual 'tras relanzar creado es el mismo texto, en el fichero' $creado $de
  $i = Pagina $e.Out 'index.html'
  $esperada = [datetime]::ParseExact($creado, 's', [System.Globalization.CultureInfo]::InvariantCulture).ToString('dd-MM-yyyy HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
  Igual 'Empezo lleva la fecha de creado' $esperada ([regex]::Match($i, '<dt>Empez[^<]*</dt><dd>([^<]*)</dd>').Groups[1].Value)
  Comprueba 'la pasada acabada dice Duro y da una duracion' ([regex]::Match($i, '<dt>Dur.</dt><dd>([^<]*)</dd>').Groups[1].Value -match '^\d+ (min|h \d+ min)$') (Cola $r.Salida)
}

# ============================ NEGOCIO: DATOS CON NOMBRE DE CLASE ============================
# El dato de una ficha de clase que nombra otra clase (guion dato-con-clase de CargaReader): es el primero de la ficha,
# asi que es el que cita el primer paso de cargaJob.
$TextoClase = 'Delega el envio de la remesa en la clase CargaValidator.'
$ListasJob = @('necesita', 'produce', 'conexiones', 'reglas', 'siFalla')
$GuionClase = 'dato-con-clase:^CargaReader$'

# Los elementos de las listas de una ficha de job.
function Elementos-De($Job) { return @(foreach ($k in $ListasJob) { @($Job.$k) }) }

# La seccion de lo que te toca de una portada.
function Toca-De([string]$Html) { return [regex]::Match($Html, '(?s)<section[^>]*id="lo-que-te-toca".*?</section>').Value }

$Pruebas['57 dato con nombre de clase: lleva tecnico en datos/jobs, no sale en la pagina de negocio, sale en la portada y los prompts lo llevan'] = {
  $c = Corrida-Dos $GuionClase
  $e = $c.E
  $j = Job-De $e 'cargaJob'
  Comprueba 'hay ficha de job' ($null -ne $j) (Cola $c.R.Salida)
  if ($null -eq $j) { return }
  $todos = Elementos-De $j
  $tec = @($todos | Where-Object { $_.texto -ceq $TextoClase })
  Igual 'el dato con la clase esta una vez en las listas del job' 1 $tec.Count
  if ($tec.Count -ne 1) { return }
  Comprueba 'lleva tecnico: true' ($tec[0].tecnico -eq $true) ($tec[0] | ConvertTo-Json -Compress)
  Igual 'ningun otro elemento lleva el campo' 0 @($todos | Where-Object { $_.texto -cne $TextoClase -and $_.PSObject.Properties.Name -contains 'tecnico' }).Count
  Comprueba 'y hay otros elementos' ($todos.Count -gt 1) "$($todos.Count)"
  $ref = $tec[0].ref -split '#'
  $ficha = @(Fichas $e | Where-Object { $_.id -eq $ref[0] })[0]
  $dato = $ficha.datos[[int]$ref[1]]
  Comprueba 'la ficha de clase no cambia: mismo texto y sin el campo tecnico' ($dato.texto -ceq $TextoClase -and $dato.PSObject.Properties.Name -notcontains 'tecnico') ($dato | ConvertTo-Json -Compress)
  Comprueba 'el primer paso cita ese dato (la prueba pasa por los pasos)' (@($j.pasos[0].refs) -contains $tec[0].ref) ($j.pasos[0] | ConvertTo-Json -Compress)
  $o = Pagina $e.Out '1-batch-original.html'
  $a = Articulo $o 'cargaJob'
  Comprueba 'la pagina de negocio no lleva el texto del dato en ninguna parte' (-not $o.Contains($TextoClase) -and -not $o.Contains([System.Net.WebUtility]::HtmlEncode($TextoClase))) (Cola $c.R.Salida)
  $faltan = @($todos | Where-Object { $_.texto -cne $TextoClase -and -not $a.Contains([System.Net.WebUtility]::HtmlEncode($_.texto)) })
  Comprueba 'el job lleva todos los demas hechos' ($a.Length -gt 0 -and $faltan.Count -eq 0) (($faltan | ForEach-Object { $_.texto }) -join ' | ')
  $cifras = [regex]::Match($a, '(\d+) pasos, (\d+) datos que citan los pasos y (\d+) m')
  Comprueba 'las cifras del job no cuentan el dato tecnico' ($cifras.Success -and ([int]$cifras.Groups[2].Value + [int]$cifras.Groups[3].Value) -eq ($todos.Count - 1)) "$($cifras.Value) y $($todos.Count) elementos"
  $i = Pagina $e.Out 'index.html'
  $toca = Toca-De $i
  $grupo = [regex]::Match($toca, '(?s)<h3>Datos con nombres de clase \(1\)</h3>.*?</div>').Value
  Comprueba 'la portada tiene el grupo Datos con nombres de clase (1)' ($grupo.Length -gt 0) $toca
  Comprueba 'el grupo lleva el job, el texto del dato y fichero:linea' ($grupo.Contains('cargaJob') -and $grupo.Contains($TextoClase) -and $grupo.Contains('CargaReader.java:' + $tec[0].linea)) $grupo
  Comprueba 'el grupo explica donde estan los datos y va como Sin comprobar' ($grupo.Contains('datos/jobs/') -and $grupo.Contains('tecnico: true') -and $grupo -match 'Sin comprobar') $grupo
  $tf = @(Tareas $e 'ficha-job' | Where-Object { $_.entradas.job -eq 'cargaJob' })[0]
  Comprueba 'el prompt de ficha-job sigue llevando el dato' ((Prompt-De $e $tf).Contains($TextoClase))
  $tp = @(Tareas $e 'prueba-pre' | Where-Object { $_.entradas.job -eq 'cargaJob' })[0]
  Comprueba 'el prompt de prueba-pre sigue llevando el dato' ((Prompt-De $e $tp).Contains($TextoClase))
  # sin datos tecnicos, ni grupo ni mencion
  $b = Corrida-Dos $GuionBase
  Comprueba 'sin datos tecnicos la portada no tiene el grupo' ((Toca-De (Pagina $b.E.Out 'index.html')) -notmatch 'nombres de clase \(')
  $n = Nuevo-Escenario 'sin-tecnicos' @('Clase1')
  [void](Migra $n (Basicos $n))
  $toca = Toca-De (Pagina $n.Out 'index.html')
  Comprueba 'sin nada que revisar, la portada lo dice y nombra los datos con clases' ($toca -match 'Nada que revisar' -and $toca -match 'ning.n dato con nombres de clase') $toca
}

$Pruebas['58 dato con nombre de clase: el guion minimo del script no lo usa'] = {
  $c = Corrida-Dos ($GuionClase + ';prueba-ref-mala:^prueba-pre:cargaJob$')
  $e = $c.E
  $j = Job-De $e 'cargaJob'
  $x = Pruebas-De $e 'cargaJob'
  Comprueba 'hay ficha de job y guion de prueba' ($null -ne $j -and $null -ne $x) (Cola $c.R.Salida)
  if ($null -eq $j -or $null -eq $x) { return }
  Igual 'la prueba en pre de cargaJob queda atascada (guion minimo)' 'atascada' $x.redaccion
  Comprueba 'la ficha del job sigue teniendo el dato tecnico' (@(Elementos-De $j | Where-Object { $_.texto -ceq $TextoClase -and $_.tecnico -eq $true }).Count -eq 1)
  Comprueba 'el guion minimo no lleva el texto del dato' (-not (Lee $e.Out 'datos/pruebas/cargaJob.json').Contains($TextoClase))
  $reglas = @($j.reglas | Where-Object { $_.tecnico -ne $true })
  Comprueba 'lleva un caso por cada regla que no es tecnica' ($reglas.Count -gt 0 -and @($x.casos).Count -eq $reglas.Count) "$(@($x.casos).Count) casos y $($reglas.Count) reglas"
}

$Pruebas['59 dato con nombre de clase: tampoco sale por otra ref con el mismo texto ni como regla sin caso'] = {
  $c = Corrida-Dos $GuionClase
  $s = Copia-Salida $c.E 'tecnico-ref'
  $d = Join-Path $s 'datos'
  $j = Lee-Json (Join-Path $d 'jobs/cargaJob.json')
  $tec = @(Elementos-De $j | Where-Object { $_.texto -ceq $TextoClase })[0]
  $otro = @(Elementos-De $j | Where-Object { $_.texto -cne $TextoClase })[0]
  # otra ficha de clase con el mismo dato (mismo tipo y texto), citada por el segundo paso con su propia ref
  $copia = @(Fichas $c.E | Where-Object { $_.id -ne ($tec.ref -split '#')[0] })[0]
  $copia.datos[0].texto = $TextoClase
  Guarda-Json (Join-Path $d ('fichas/' + $copia.id + '.json')) $copia
  $j.pasos[1].refs = @($copia.id + '#0')
  Guarda-Json (Join-Path $d 'jobs/cargaJob.json') $j
  $x = Lee-Json (Join-Path $d 'pruebas/cargaJob.json')
  $x.sinCaso = @([ordered]@{ ref = $tec.ref; tipo = 'regla'; texto = $TextoClase }, [ordered]@{ ref = $otro.ref; tipo = 'regla'; texto = $otro.texto })
  Guarda-Json (Join-Path $d 'pruebas/cargaJob.json') $x
  $g = Genera-Informes $s
  Comprueba 'Write-Informes sale bien' ($g.Codigo -eq 0 -and $g.Salida -match 'INFORMES-OK') (Cola $g.Salida)
  $a = Articulo (Pagina $s '1-batch-original.html') 'cargaJob'
  Comprueba 'la pagina no lleva el texto del dato, ni por la ref de la otra ficha ni como regla sin caso' ($a.Length -gt 0 -and -not $a.Contains($TextoClase)) (Cola $g.Salida)
  $sin = [regex]::Match($a, '(?s)<div class="job-sec sincaso">.*?</div>').Value
  Comprueba 'la otra regla sin caso si sale, y es la unica' ($sin.Contains([System.Net.WebUtility]::HtmlEncode($otro.texto)) -and ([regex]::Matches($sin, '<li>').Count -eq 1)) $sin
}

# ============================ DIAGNOSTICO: LA FASE Y LA PAGINA DE PROBLEMAS ============================
$AreasMotor = @('build', 'estructura', 'hexagonal', 'ficheros', 'config', 'paridad', 'e2e', 'tests', 'calidad')

function Hallazgo([string]$Cat, [string]$Sev, [string]$Fichero, [int]$Linea, [string]$Detalle) {
  return [ordered]@{ Cat = $Cat; Sev = $Sev; Fichero = $Fichero; Linea = $Linea; Detalle = $Detalle }
}

# El diagnostico.md que escribe el motor: la linea de estado (si hay), lineas extra y la tabla de areas en su orden.
function Md-Diagnostico([string]$Estado, [string]$Extra = '', [string[]]$Areas = $AreasMotor) {
  $t = "# Diagnostico de rescate: batch-life`n`n- Fecha: 2026-01-01 00:00`n- Paquete base: com.acme.life`n- Plantilla: x`n"
  if ($Estado) { $t += "- Estado: $Estado`n" }
  if ($Extra) { $t += "$Extra`n" }
  $t += "`n| Paso | Errores | Avisos |`n|---|---|---|`n"
  foreach ($a in $Areas) { $t += "| $a | 0 | 0 |`n" }
  return $t
}

# Una copia de la salida de una corrida con estos datos de diagnostico, con sus paginas montadas otra vez.
function Problemas-Con($E, [string]$Nombre, $Hallazgos, [string]$Md) {
  $s = Copia-Salida $E $Nombre
  Guarda-Json (Join-Path $s 'datos/hallazgos-antes.json') @($Hallazgos)
  Escribe $s 'datos/diagnostico-antes.md' $Md
  $g = Genera-Informes $s
  Comprueba "$Nombre : Write-Informes sale bien" ($g.Codigo -eq 0 -and $g.Salida -match 'INFORMES-OK') (Cola $g.Salida)
  return [pscustomobject]@{ Dir = $s; P = (Pagina $s '2-problemas.html'); I = (Pagina $s 'index.html') }
}

function Html([string]$Texto) { return [System.Net.WebUtility]::HtmlEncode($Texto) }

# "1 error", "2 errores", "0 errores": la cuenta con la palabra en singular o en plural.
function Cuenta-Es([int]$N, [string]$Uno, [string]$Otros) { if ($N -eq 1) { return "1 $Uno" } return "$N $Otros" }

# El grupo de un area de la pagina de problemas, y un panel por su id.
function Grupo-De([string]$Html, [string]$Area) {
  return [regex]::Match($Html, '(?s)<section class="prob-grupo" aria-labelledby="g-' + [regex]::Escape($Area) + '">.*?</section>').Value
}
function Panel-De([string]$Html, [string]$Id) { return [regex]::Match($Html, '(?s)<section[^>]*id="' + $Id + '".*?</section>').Value }

$Pruebas['60 diagnostico: la corrida deja hallazgos-antes.json igual al del motor, diagnostico-antes.md, el registro y 2-problemas.html'] = {
  $c = Corrida-Dos $GuionBase
  $e = $c.E
  Igual 'sale con 0' 0 $c.R.Codigo
  $h = Get-Ruta $e.Out 'datos/hallazgos-antes.json'
  Comprueba 'existe datos/hallazgos-antes.json' (Test-Path -LiteralPath $h) (Cola $c.R.Salida)
  if (-not (Test-Path -LiteralPath $h)) { return }
  Igual 'es el hallazgos.json del motor, tal cual' (Lee $e.Wt '.rescate/hallazgos.json') (Lee $e.Out 'datos/hallazgos-antes.json')
  Igual 'diagnostico-antes.md es el diagnostico.md del motor' (Lee $e.Wt '.rescate/diagnostico.md') (Lee $e.Out 'datos/diagnostico-antes.md')
  $log = Get-Ruta $e.Out 'registros/diagnostico-antes.log'
  Comprueba 'existe el registro' (Test-Path -LiteralPath $log)
  $texto = ''
  if (Test-Path -LiteralPath $log) { $texto = [System.IO.File]::ReadAllText($log) }
  Comprueba 'el registro lleva lo que dijo el motor y ningun codigo de color' ($texto -match 'Diagnostico' -and $texto -notmatch '\x1b\[') $texto
  Comprueba 'existe 2-problemas.html' (Test-Path -LiteralPath (Get-Ruta $e.Out '2-problemas.html'))
  $hall = @(Lee-Json $h)
  $n = @($hall | Where-Object { $_.Sev -eq 'error' }).Count
  $m = @($hall | Where-Object { $_.Sev -ne 'error' }).Count
  $l = [regex]::Match($c.R.Salida, 'Diagnostico: (\d+) errores y (\d+) avisos\. Detalle: (\S*2-problemas\.html)')
  Comprueba 'la consola dice cuantos errores y avisos y donde esta el detalle' ($l.Success -and [int]$l.Groups[1].Value -eq $n -and [int]$l.Groups[2].Value -eq $m -and $l.Groups[3].Value -eq (Get-Ruta $e.Out '2-problemas.html')) (Cola $c.R.Salida)
  Comprueba 'no deja temporales en datos' (@(Get-ChildItem -LiteralPath (Get-Ruta $e.Out 'datos') -File -Filter '*.tmp').Count -eq 0)
}

$Pruebas['61 diagnostico: es la primera fase: con -Limite 1 ya estan los hallazgos y la pagina, y se cuenta antes de la lectura'] = {
  $e = Nuevo-Escenario 'diag-primero' @('Clase1', 'Clase2', 'Clase3')
  $r = Migra $e ((Basicos $e) + @('-Limite', '1'))
  Igual 'sale con 0' 0 $r.Codigo
  Comprueba 'estan los hallazgos' (Test-Path -LiteralPath (Get-Ruta $e.Out 'datos/hallazgos-antes.json')) (Cola $r.Salida)
  Comprueba 'y la pagina de problemas' (Test-Path -LiteralPath (Get-Ruta $e.Out '2-problemas.html'))
  Igual 'la lectura sigue limitada a una tarea' 1 (Cuenta-Estado (Tareas $e) 'hecha')
  $d = $r.Salida.IndexOf('Diagnostico: ')
  Comprueba 'la consola cuenta el diagnostico antes que las tareas de lectura' ($d -ge 0 -and $d -lt $r.Salida.IndexOf('Tareas de lectura')) (Cola $r.Salida)
}

$Pruebas['62 diagnostico: relanzar no lo repite'] = {
  $e = Nuevo-Escenario 'diag-relanza' @('Clase1')
  $r = Migra $e (Basicos $e)
  Igual 'el primer lanzamiento sale con 0' 0 $r.Codigo
  $h = Get-Ruta $e.Out 'datos/hallazgos-antes.json'
  Comprueba 'deja los hallazgos' (Test-Path -LiteralPath $h) (Cola $r.Salida)
  if (-not (Test-Path -LiteralPath $h)) { return }
  $antes = Hash-De $h
  $log = Hash-De (Get-Ruta $e.Out 'registros/diagnostico-antes.log')
  Remove-Item -LiteralPath (Get-Ruta $e.Wt '.rescate/hallazgos.json') -Force
  $r = Migra $e (Basicos $e)
  Igual 'el segundo sale con 0' 0 $r.Codigo
  Comprueba 'el motor no vuelve a escribir hallazgos.json en el worktree' (-not (Test-Path -LiteralPath (Get-Ruta $e.Wt '.rescate/hallazgos.json')))
  Igual 'datos/hallazgos-antes.json no cambia' $antes (Hash-De $h)
  Igual 'el registro no cambia' $log (Hash-De (Get-Ruta $e.Out 'registros/diagnostico-antes.log'))
  Comprueba 'la consola no cuenta otro diagnostico' ($r.Salida -notmatch 'Diagnostico: ') (Cola $r.Salida)
}

$Pruebas['63 diagnostico: un motor que falla para con motivo motor, el codigo y el registro, y la portada lo ensena'] = {
  $e = Nuevo-Escenario 'diag-motor' @('Clase1', 'Clase2')
  # copia del sistema con un rescate.ps1 de mentira: en -Modo pre deja un contrato vacio; el diagnostico escribe una linea y sale con 3
  $sis = Join-Path $Dir 'sistema-falso'
  $raiz = Split-Path -Parent $Script
  [void](New-Item -ItemType Directory -Path $sis -Force)
  foreach ($f in @('migracion.ps1', 'comun.ps1', 'tareas.ps1', 'informe.ps1', 'lanzadores.ps1', 'analisis.ps1', 'practicas.ps1', 'huella.ps1', 'arreglo-practicas.ps1', 'tests-reglas.ps1', 'informe', 'tareas', 'analisis')) { Copy-Item -LiteralPath (Join-Path $raiz $f) -Destination (Join-Path $sis $f) -Recurse }
  Escribe $sis 'rescate.ps1' @'
param([string]$Modo = '', [string]$Repo = '', [string]$Plantilla = '', [string]$Legacy = '', [switch]$SinIA, [switch]$Si)
if ($Modo -eq 'pre') {
  New-Item -ItemType Directory -Path (Join-Path $Repo '.rescate') -Force | Out-Null
  [System.IO.File]::WriteAllText((Join-Path (Join-Path $Repo '.rescate') 'contrato.json'), '{ "jobs": [] }')
  exit 0
}
Write-Host 'el motor de mentira se niega a diagnosticar'
exit 3
'@
  $r = Migra $e (Basicos $e) '' @('') (Join-Path $sis 'migracion.ps1')
  Igual 'sale con 2' 2 $r.Codigo
  $s = Estado $e
  Comprueba 'hay estado.json' ($null -ne $s) (Cola $r.Salida)
  if ($null -eq $s) { return }
  Igual 'parada: motivo motor' 'motor' $s.parada.motivo
  Comprueba 'parada: el detalle lleva el codigo 3 y la ultima linea del motor' ($s.parada.detalle -match 'codigo 3' -and $s.parada.detalle -match 'se niega a diagnosticar') "$($s.parada.detalle)"
  Igual 'parada: el registro es registros/diagnostico-antes.log' (Get-Ruta $e.Out 'registros/diagnostico-antes.log') $s.parada.registro
  Comprueba 'el registro lleva lo que escribio el motor' ((Lee $e.Out 'registros/diagnostico-antes.log') -match 'se niega a diagnosticar')
  Igual 'la fase en que se paro es diagnostico' 'diagnostico' $s.fase
  Comprueba 'no hay hallazgos-antes.json ni se empezo a leer' ((-not (Test-Path -LiteralPath (Get-Ruta $e.Out 'datos/hallazgos-antes.json'))) -and @(Tareas $e).Count -eq 0)
  $i = Pagina $e.Out 'index.html'
  Comprueba 'la portada ensena la parada con su motivo y la ayuda' ($i -match 'Por qu. se ha parado' -and $i -match '<code>motor</code>' -and $i -match 'Estoy ejecutando migracion\.ps1') (Cola $r.Salida)
}

$Pruebas['64 pagina de problemas: cada hallazgo en el grupo de su area con fichero:linea y detalle; cada grupo con sus numeros; las areas sin nada, aparte'] = {
  $c = Corrida-Dos $GuionBase
  $e = $c.E
  $p = Pagina $e.Out '2-problemas.html'
  Comprueba 'existe la pagina' ($p.Length -gt 0) (Cola $c.R.Salida)
  if (-not $p) { return }
  $hall = @(Lee-Json (Get-Ruta $e.Out 'datos/hallazgos-antes.json'))
  Comprueba 'el juguete tiene hallazgos que pintar' ($hall.Count -gt 0)
  Igual 'un solo h1' 1 ([regex]::Matches($p, '<h1[ >]').Count)
  $faltan = @($hall | Where-Object {
      $g = Grupo-De $p $_.Cat
      $donde = ''
      if ($_.Fichero) { $donde = $_.Fichero; if ($_.Linea -gt 0) { $donde += ':' + $_.Linea } }
      -not ($g.Length -gt 0 -and $g.Contains((Html $_.Detalle)) -and ((-not $donde) -or $g.Contains((Html $donde))))
    })
  Igual 'todos los hallazgos salen en su grupo, con su fichero:linea y su detalle' 0 $faltan.Count
  $cats = @($hall | ForEach-Object { $_.Cat } | Select-Object -Unique)
  $malos = @($cats | Where-Object {
      $cat = $_
      $n = @($hall | Where-Object { $_.Cat -eq $cat -and $_.Sev -eq 'error' }).Count
      $m = @($hall | Where-Object { $_.Cat -eq $cat -and $_.Sev -ne 'error' }).Count
      -not ((Grupo-De $p $cat).Contains((Cuenta-Es $n 'error' 'errores') + ', ' + (Cuenta-Es $m 'aviso' 'avisos')))
    })
  Igual 'cada grupo dice sus errores y sus avisos' 0 $malos.Count
  Igual 'un grupo por cada area con hallazgos' $cats.Count ([regex]::Matches($p, 'class="prob-grupo"').Count)
  $md = Lee $e.Out 'datos/diagnostico-antes.md'
  $tabla = @([regex]::Matches($md, '(?m)^\| (\w+) \| \d+ \| \d+ \|\s*$') | ForEach-Object { $_.Groups[1].Value })
  $vacias = @($tabla | Where-Object { $cats -notcontains $_ })
  $sin = [regex]::Match($p, '(?s)<div class="sin-prob">.*?</div>').Value
  Comprueba 'las areas sin hallazgos estan en Sin problemas' ($vacias.Count -eq 0 -or ($sin -match 'Sin problemas:' -and [regex]::Matches($sin, '<li>').Count -eq $vacias.Count)) $sin
  Comprueba 'enlaza a la portada y al batch original' ($p -match 'href="index\.html"' -and $p -match 'href="1-batch-original\.html"')
  Comprueba 'ningun enlace a un fichero que no existe' (@([regex]::Matches($p, '(?i)\b(?:src|href)\s*=\s*"(?!#)([^"]*)"') | Where-Object { -not (Test-Path -LiteralPath (Get-Ruta $e.Out $_.Groups[1].Value)) }).Count -eq 0)
  Comprueba 'cada area con una frase de como se arregla' (@($cats | Where-Object { (Grupo-De $p $_) -notmatch 'C.mo se arregla' }).Count -eq 0)
}

$Pruebas['65 pagina de problemas: errores antes que avisos, areas con errores antes que las que solo tienen avisos, linea 0 sin :0, sin fichero sin codigo, area rara con su id'] = {
  $c = Corrida-Dos $GuionBase
  $hall = @(
    (Hallazgo 'hexagonal' 'aviso' 'src/main/java/com/acme/Aviso1.java' 7 'DETALLE-AVISO-HEX'),
    (Hallazgo 'hexagonal' 'error' 'src/main/java/com/acme/Error1.java' 12 'DETALLE-ERROR-HEX'),
    (Hallazgo 'estructura' 'aviso' 'src/main/java/com/acme/Solo.java' 3 'DETALLE-SOLO-AVISOS'),
    (Hallazgo 'tests' 'error' 'src/test/java/com/acme/T.java' 4 'DETALLE-TESTS'),
    (Hallazgo 'build' 'error' 'pom.xml' 0 'DETALLE-POM'),
    (Hallazgo 'e2e' 'error' '' 0 'DETALLE-SIN-FICHERO'),
    (Hallazgo 'rara' 'error' 'x.txt' 1 'DETALLE-RARA')
  )
  $x = Problemas-Con $c.E 'diag-orden' $hall (Md-Diagnostico 'compila: SI | tests: OK' '' ($AreasMotor + @('rara')))
  $p = $x.P
  Comprueba 'dentro de un area, el error va antes que el aviso (aunque en los datos va despues)' ($p.IndexOf('DETALLE-ERROR-HEX') -ge 0 -and $p.IndexOf('DETALLE-ERROR-HEX') -lt $p.IndexOf('DETALLE-AVISO-HEX'))
  $orden = (@([regex]::Matches($p, 'class="prob-grupo" aria-labelledby="g-(\w+)"') | ForEach-Object { $_.Groups[1].Value })) -join ' '
  Igual 'los grupos: primero los que tienen errores en el orden de la tabla, despues los de solo avisos' 'build hexagonal e2e tests rara estructura' $orden
  Comprueba 'linea 0 sale sin :0' ($p.Contains('pom.xml') -and -not $p.Contains('pom.xml:0'))
  Comprueba 'con linea sale fichero:linea' ($p.Contains('src/main/java/com/acme/Error1.java:12'))
  $fila = [regex]::Match($p, '(?s)<li class="fila[^"]*">(?:(?!</li>).)*DETALLE-SIN-FICHERO.*?</li>').Value
  Comprueba 'sin fichero no sale codigo, solo el detalle' ($fila.Length -gt 0 -and $fila -notmatch '<code')
  $err = [regex]::Match($p, '(?s)<li class="fila[^"]*">(?:(?!</li>).)*DETALLE-ERROR-HEX.*?</li>').Value
  $avi = [regex]::Match($p, '(?s)<li class="fila[^"]*">(?:(?!</li>).)*DETALLE-AVISO-HEX.*?</li>').Value
  Comprueba 'cada fila lleva su marca de gravedad con su texto' ($err -match 'sev-error' -and $err -match '>Error<' -and $avi -match 'sev-aviso' -and $avi -match '>Aviso<') "$err $avi"
  Comprueba 'un area que la plantilla no nombra sale con su identificador' ($p -match '<h2 id="g-rara">rara</h2>')
  Comprueba 'cada grupo dice sus numeros' ((Grupo-De $p 'hexagonal').Contains('1 error, 1 aviso') -and (Grupo-De $p 'estructura').Contains('0 errores, 1 aviso'))
  $sin = [regex]::Match($p, '(?s)<div class="sin-prob">.*?</div>').Value
  Igual 'Sin problemas lleva las cuatro areas sin hallazgos (ficheros, config, paridad y calidad)' 4 ([regex]::Matches($sin, '<li>').Count)
}

$Pruebas['66 pagina de problemas: todo texto de los datos sale escapado'] = {
  $c = Corrida-Dos $GuionBase
  $mal = '<script>alert(1)</script>'
  $hall = @(
    (Hallazgo 'build' 'error' 'a<b>.java' 5 ($mal + ' Importe "A" & ''B''')),
    (Hallazgo '<i>x</i>' 'aviso' 'x.txt' 1 'otra')
  )
  $x = Problemas-Con $c.E 'diag-escapa' $hall (Md-Diagnostico ('<b>' + $mal))
  foreach ($h in @($x.P, $x.I)) { Comprueba 'ninguna etiqueta <script en la pagina' ($h -notmatch '(?i)<script') }
  Comprueba 'el detalle sale escapado' ($x.P.Contains('&lt;script&gt;alert(1)&lt;/script&gt; Importe &quot;A&quot; &amp; &#39;B&#39;'))
  Comprueba 'el fichero, igual' ($x.P.Contains('a&lt;b&gt;.java:5'))
  Comprueba 'un area con markup en su id sale como texto' ($x.P -notmatch '<i>x' -and $x.I -notmatch '<i>x' -and $x.P.Contains('&lt;i&gt;x&lt;/i&gt;'))
  Comprueba 'un estado desconocido no se pinta' (-not (Panel-De $x.P 'estado-build').Contains('alert'))
}

$Pruebas['67 pagina de problemas: lo que incumple la referencia sale de la linea del motor, solo con digitos; si no, no se sabe'] = {
  $c = Corrida-Dos $GuionBase
  $hall = @((Hallazgo 'build' 'error' 'pom.xml' 0 'x'))
  $x = Problemas-Con $c.E 'inc-ok' $hall (Md-Diagnostico 'compila: SI | tests: OK' '- La plantilla incumple: capas 1 | ficheros 2 | calidad 3 | secretos 4')
  $r = Panel-De $x.P 'referencia'
  Comprueba 'hay panel de la referencia' ($r.Length -gt 0)
  Comprueba 'capas 1, ficheros 2, calidad 3 y secretos 4 en su sitio' ($r -match '<b>1</b>\s*capas' -and $r -match '<b>2</b>\s*ficheros' -and $r -match '<b>3</b>\s*calidad' -and $r -match '<b>4</b>\s*secretos') $r
  Comprueba 'dice que lo que la referencia hace se permite, salvo el Javadoc' ($r -match 'salvo el Javadoc')
  Comprueba 'con la linea, no dice no se sabe' ($r -notmatch 'no se sabe')
  $x = Problemas-Con $c.E 'inc-sin' $hall (Md-Diagnostico 'compila: SI | tests: OK')
  $r = Panel-De $x.P 'referencia'
  Comprueba 'sin la linea: no se sabe y ningun numero' ($r -match 'no se sabe' -and $r -notmatch '<b>')
  foreach ($linea in @('- La plantilla incumple: capas x1 | ficheros 2 | calidad 3 | secretos 4', '- La plantilla incumple: capas 1 | ficheros 2 | calidad 3 | secretos 4x', '- La plantilla incumple: capas 1 | ficheros 2 | calidad 3')) {
    $x = Problemas-Con $c.E 'inc-mal' $hall (Md-Diagnostico 'compila: SI | tests: OK' $linea)
    $r = Panel-De $x.P 'referencia'
    Comprueba "con '$linea': no se sabe y ningun numero" ($r -match 'no se sabe' -and $r -notmatch '<b>') $r
  }
}

$Pruebas['68 pagina de problemas: el estado del build, una frase por cada texto del motor; otro texto o ninguno, no se sabe'] = {
  $c = Corrida-Dos $GuionBase
  $hall = @((Hallazgo 'build' 'error' 'pom.xml' 0 'x'))
  $casos = @(
    @('compila: no comprobado', 'No se ha comprobado si el migrado compila'),
    @('compila: NO', 'El migrado no compila'),
    @('compila: SI | tests: no ejecutados', 'no se han ejecutado sus tests'),
    @('compila: SI | tests: OK', 'sus tests pasan'),
    @('compila: SI | tests: FALLAN', 'algunos tests fallan'),
    @('compila: no', 'No se sabe'),
    @('', 'No se sabe')
  )
  $n = 0
  foreach ($caso in $casos) {
    $n++
    $x = Problemas-Con $c.E "diag-build$n" $hall (Md-Diagnostico $caso[0])
    $b = Panel-De $x.P 'estado-build'
    $otras = @($casos | ForEach-Object { $_[1] } | Where-Object { $_ -ne $caso[1] })
    Comprueba "'$($caso[0])' : su frase y ninguna de las otras" ($b.Contains($caso[1]) -and @($otras | Where-Object { $b.Contains($_) }).Count -eq 0) $b
    Comprueba "'$($caso[0])' : la portada dice lo mismo" ((Panel-De $x.I 'problemas-migrado').Contains($caso[1]))
  }
}

$Pruebas['69 pagina de problemas: sin los datos del diagnostico, la pagina y la portada dicen que la fase diagnostico no ha terminado y las demas se generan'] = {
  $c = Corrida-Dos $GuionBase
  $s = Copia-Salida $c.E 'diag-medias'
  Remove-Item -LiteralPath (Join-Path $s 'datos/hallazgos-antes.json') -Force
  foreach ($n in @('index.html', '1-batch-original.html', '2-problemas.html')) { Remove-Item -LiteralPath (Join-Path $s $n) -Force }
  $g = Genera-Informes $s
  Comprueba 'Write-Informes sale bien' ($g.Codigo -eq 0 -and $g.Salida -match 'INFORMES-OK') (Cola $g.Salida)
  foreach ($n in @('index.html', '1-batch-original.html', '2-problemas.html')) { Comprueba "$n : se genera" ((Pagina $s $n).Length -gt 0) }
  Comprueba 'la pagina de problemas lo dice' ((Pagina $s '2-problemas.html') -match 'la fase diagnostico no ha terminado')
  $i = Pagina $s 'index.html'
  Comprueba 'la seccion de la portada, igual' ((Panel-De $i 'problemas-migrado') -match 'la fase diagnostico no ha terminado')
  Comprueba 'y la linea de la fase no cuenta errores' ($i -notmatch 'errores: \d')
  # tambien si lo que falta es el diagnostico.md
  $s = Copia-Salida $c.E 'diag-medias-md'
  Remove-Item -LiteralPath (Join-Path $s 'datos/diagnostico-antes.md') -Force
  $g = Genera-Informes $s
  Comprueba 'sin el .md, igual' ($g.Codigo -eq 0 -and (Pagina $s '2-problemas.html') -match 'la fase diagnostico no ha terminado')
}

$Pruebas['70 portada: seccion de problemas con total, barra por area con errores y enlace; diagnostico la primera fase; ficheros nuevos; navegacion'] = {
  $c = Corrida-Dos $GuionBase
  $hall = @(
    (Hallazgo 'build' 'error' 'pom.xml' 0 'uno'), (Hallazgo 'build' 'error' 'pom.xml' 0 'dos'), (Hallazgo 'build' 'error' 'pom.xml' 0 'tres'),
    (Hallazgo 'hexagonal' 'error' 'A.java' 1 'cuatro'), (Hallazgo 'hexagonal' 'aviso' 'A.java' 2 'cinco'), (Hallazgo 'hexagonal' 'aviso' 'A.java' 3 'seis'),
    (Hallazgo 'tests' 'aviso' 'T.java' 1 'siete')
  )
  $x = Problemas-Con $c.E 'diag-portada' $hall (Md-Diagnostico 'compila: SI | tests: OK')
  $i = $x.I
  $sec = Panel-De $i 'problemas-migrado'
  Comprueba 'la portada tiene la seccion Problemas del migrado' ($sec.Length -gt 0 -and $sec -match 'Problemas del migrado')
  Comprueba 'va despues de Lo que te toca' ($i.IndexOf('id="problemas-migrado"') -gt $i.IndexOf('id="lo-que-te-toca"'))
  Comprueba 'dice el total: 4 errores y 3 avisos' ($sec.Contains('4 errores y 3 avisos'))
  Igual 'una linea con barra por cada area con errores' 2 ([regex]::Matches($sec, '<li class="area">').Count)
  Igual 'las demas areas como limpia' 7 ([regex]::Matches($sec, '<li class="area limpia">').Count)
  Comprueba 'la escala es el mayor numero de errores de un area (3)' ($sec -match '--max:3(?!\d)')
  Comprueba 'las barras valen 3 y 1' ($sec -match '--v:3(?!\d)' -and $sec -match '--v:1(?!\d)')
  Comprueba 'enlaza a 2-problemas.html' ($sec -match 'href="2-problemas\.html"')
  $fases = [regex]::Match($i, '(?s)<ol class="fases">.*?</ol>').Value
  $primera = [regex]::Match($fases, '(?s)<li>.*?</li>').Value
  Comprueba 'Que ha hecho el script: la primera linea es el diagnostico del migrado, con su cuenta' ($primera -match 'Diagn.stico del migrado' -and $primera.Contains('errores: 4, avisos: 3')) $primera
  $f = [regex]::Match($i, '(?s)<ul class="ficheros">.*?</ul>').Value
  Comprueba 'Que es cada fichero: 2-problemas.html, hallazgos-antes.json y diagnostico-antes.md' ($f.Contains('2-problemas.html') -and $f.Contains('datos/hallazgos-antes.json') -and $f.Contains('datos/diagnostico-antes.md')) $f
  foreach ($par in @(@('index.html', $i), @('1-batch-original.html', (Pagina $x.Dir '1-batch-original.html')), @('2-problemas.html', $x.P))) {
    $h = $par[1]
    Comprueba "$($par[0]) : la navegacion lleva a las tres paginas" ($h -match 'href="index\.html"' -and $h -match 'href="1-batch-original\.html"' -and $h -match 'href="2-problemas\.html"')
    Igual "$($par[0]) : aria-current solo en su pagina" 1 ([regex]::Matches($h, 'aria-current="page"').Count)
    Comprueba "$($par[0]) : y es el de su enlace" ($h -match ('href="' + [regex]::Escape($par[0]) + '" aria-current="page"'))
  }
}

$Pruebas['71 pagina de problemas: la frase de lo que pasara segun la respuesta (parar o corregir)'] = {
  $c = Corrida-Dos $GuionBase
  $hall = @((Hallazgo 'build' 'error' 'pom.xml' 0 'x'))
  $x = Problemas-Con $c.E 'diag-parar' $hall (Md-Diagnostico 'compila: SI | tests: OK')
  Igual 'la corrida es de -SoloInforme: respuesta parar' 'parar' (Lee-Json (Get-Ruta $x.Dir 'datos/estado.json')).respuesta
  Comprueba 'parar: no se corrige nada' ($x.P.Contains('has pedido parar tras el informe: no se corrige nada') -and -not $x.P.Contains('se corrigen los errores'))
  $s = Copia-Salida $c.E 'diag-corregir'
  $st = Lee-Json (Join-Path $s 'datos/estado.json')
  $st.respuesta = 'corregir'
  Guarda-Json (Join-Path $s 'datos/estado.json') $st
  $g = Genera-Informes $s
  Comprueba 'Write-Informes sale bien' ($g.Codigo -eq 0 -and $g.Salida -match 'INFORMES-OK') (Cola $g.Salida)
  $p = Pagina $s '2-problemas.html'
  Comprueba 'corregir: al acabar la lectura se corrigen los errores' ($p.Contains('al acabar la lectura se corrigen los errores') -and -not $p.Contains('no se corrige nada'))
}

# ============================ CORRECCION: LA FASE, SUS DATOS Y LA PAGINA 4 ============================
$Flecha = [string][char]0x2192

# Argumentos de un arranque normal que contesta "corregir".
function Corrige($E) { return @('-Legacy', $E.Legacy, '-Migrado', $E.Migrado, '-Plantilla', $E.Plantilla, '-Modelo', 'modelo-x', '-Si') }

# Los commits de arreglo de la rama del worktree, en orden: 'hash|segundos|asunto'.
function Commits-Rescate($E) {
  return @((GitEn $E.Wt @('log', '--reverse', '--format=%h|%ct|%s')) -split "`n" | Where-Object { $_ -match '^[0-9a-f]+\|\d+\|rescate\(' })
}

function Errores-De($Hall, [string]$Cat) { return @($Hall | Where-Object { $_.Cat -eq $Cat -and $_.Sev -eq 'error' }).Count }

# Una copia del sistema (solo una vez) con el rescate.ps1 y el prueba-local.ps1 de mentira de tests/falsos en lugar del motor y de la prueba en local.
function Sistema-Motor {
  $sis = Join-Path $Dir 'sistema-motor'
  if (-not (Test-Path -LiteralPath $sis)) {
    [void](New-Item -ItemType Directory -Path $sis -Force)
    $raiz = Split-Path -Parent $Script
    foreach ($f in @('migracion.ps1', 'comun.ps1', 'tareas.ps1', 'informe.ps1', 'lanzadores.ps1', 'analisis.ps1', 'practicas.ps1', 'huella.ps1', 'arreglo-practicas.ps1', 'tests-reglas.ps1', 'informe', 'tareas', 'analisis')) { Copy-Item -LiteralPath (Join-Path $raiz $f) -Destination (Join-Path $sis $f) -Recurse }
    Copy-Item -LiteralPath (Join-Path $falsos 'rescate.ps1') -Destination (Join-Path $sis 'rescate.ps1')
    Copy-Item -LiteralPath (Join-Path $falsos 'prueba-local.ps1') -Destination (Join-Path $sis 'prueba-local.ps1')
  }
  return (Join-Path $sis 'migracion.ps1')
}

# Lanza migracion.ps1 con el motor falso; $Orden dice que hace (ver tests/falsos/rescate.ps1). Con $Local, tambien la prueba en local
# de mentira hace lo que diga (ver tests/falsos/prueba-local.ps1); sin $Local no tiene orden y sale con 1.
function Migra-Motor($E, $Orden, [string[]]$A, [string]$Programa = '', $Local = $null) {
  if (-not $Programa) { $Programa = Sistema-Motor }
  $ctrl = Get-Ruta $E.Raiz 'motor-falso.json'
  Guarda-Json $ctrl $Orden
  $env:MOTOR_FALSO = $ctrl
  if ($null -ne $Local) {
    Guarda-Json (Get-Ruta $E.Raiz 'prueba-local-falsa.json') $Local
    $env:PRUEBA_LOCAL_FALSA = Get-Ruta $E.Raiz 'prueba-local-falsa.json'
  }
  try { return (Migra $E $A '' @('') $Programa) }
  finally { $env:MOTOR_FALSO = ''; $env:PRUEBA_LOCAL_FALSA = '' }
}

# El mismo sistema, con el motor de mentira esperando 3 s antes de arreglar (la correccion dura algo).
function Sistema-Motor-Lento {
  $sis = Join-Path $Dir 'sistema-motor-lento'
  if (-not (Test-Path -LiteralPath $sis)) {
    Copy-Item -LiteralPath (Split-Path -Parent (Sistema-Motor)) -Destination $sis -Recurse
    $motor = Join-Path $sis 'rescate.ps1'
    $t = [System.IO.File]::ReadAllText($motor)
    [System.IO.File]::WriteAllText($motor, $t.Replace('if ($orden.ficheros) {', "Start-Sleep -Seconds 3`nif (`$orden.ficheros) {"))
  }
  return (Join-Path $sis 'migracion.ps1')
}

# Las lineas que el motor falso apunto de ese modo (una por llamada).
function Llamadas-Motor($E, [string]$Modo) {
  $l = Get-Ruta $E.Raiz 'motor-falso.json.llamadas'
  if (-not (Test-Path -LiteralPath $l)) { return @() }
  return @([System.IO.File]::ReadAllLines($l) | Where-Object { $_ -like ($Modo + '|*') })
}

# Las ordenes de un motor falso que arregla algo: de 3 errores y 1 aviso a 1 error y el mismo aviso, y sale con 0.
function Orden-Base {
  $md = Md-Diagnostico 'compila: SI | tests: OK'
  $aviso = Hallazgo 'tests' 'aviso' 'src/test/java' 0 'no hay tests'
  return [ordered]@{
    codigo = 0; salida = @(); commits = @(); atascados = @()
    antes = [ordered]@{ md = $md; hallazgos = @((Hallazgo 'estructura' 'error' 'src/main/java/A.java' 3 'clase suelta A'), (Hallazgo 'estructura' 'error' 'src/main/java/B.java' 5 'clase suelta B'), (Hallazgo 'config' 'error' 'src/main/resources/application.yml' 2 'secreto en claro'), $aviso) }
    despues = [ordered]@{ md = $md; hallazgos = @((Hallazgo 'estructura' 'error' 'src/main/java/B.java' 9 'clase suelta B'), $aviso) }
  }
}

# Una copia de la salida de una corrida con estos datos de antes, de despues y de correcciones.json, con las paginas montadas otra vez.
function Correccion-Con($E, [string]$Nombre, $Antes, $Despues, $Corr, [string]$MdAntes = '', [string]$MdDespues = '') {
  if (-not $MdAntes) { $MdAntes = Md-Diagnostico 'compila: NO' }
  if (-not $MdDespues) { $MdDespues = Md-Diagnostico 'compila: SI | tests: OK' }
  $s = Copia-Salida $E $Nombre
  Guarda-Json (Join-Path $s 'datos/hallazgos-antes.json') @($Antes)
  Escribe $s 'datos/diagnostico-antes.md' $MdAntes
  Guarda-Json (Join-Path $s 'datos/hallazgos-despues.json') @($Despues)
  Escribe $s 'datos/diagnostico-despues.md' $MdDespues
  Guarda-Json (Join-Path $s 'datos/correcciones.json') $Corr
  Escribe $s 'registros/correccion.log' 'registro'
  $g = Genera-Informes $s
  Comprueba "$Nombre : Write-Informes sale bien" ($g.Codigo -eq 0 -and $g.Salida -match 'INFORMES-OK') (Cola $g.Salida)
  return [pscustomobject]@{ Dir = $s; P2 = (Pagina $s '2-problemas.html'); P4 = (Pagina $s '4-correcciones.html'); I = (Pagina $s 'index.html') }
}

# Los numeros de las barras antes y despues de un trozo de pagina: 'antes=3 desp=1'.
function Barras-De([string]$Html) {
  return ((@([regex]::Matches($Html, '(?s)class="barra (antes|desp)">.*?--v:(\d+)') | ForEach-Object { $_.Groups[1].Value + '=' + $_.Groups[2].Value })) -join ' ')
}

# Los datos de mentira de las paginas: de 6 errores y 1 aviso a 1 error y el mismo aviso, con detalles y motivos con markup.
$MalTexto = '<script>alert(1)</script> Importe "A" & ''B'''
function Datos-Pagina4 {
  $aviso = Hallazgo 'tests' 'aviso' 'src/test/java' 0 'no hay tests'
  return [pscustomobject]@{
    Antes = @((Hallazgo 'build' 'error' 'pom.xml' 0 'pom uno'), (Hallazgo 'build' 'error' 'pom.xml' 0 'pom dos'), (Hallazgo 'build' 'error' 'pom.xml' 0 'pom tres'),
      (Hallazgo 'estructura' 'error' 'src/main/java/A.java' 3 'A suelta'), (Hallazgo 'estructura' 'error' 'src/main/java/B.java' 5 'B suelta'),
      (Hallazgo 'hexagonal' 'error' 'src/main/java/C.java' 1 'C depende de Spring'), $aviso)
    Despues = @((Hallazgo 'estructura' 'error' 'src/main/java/B.java' 5 $MalTexto), $aviso)
    Corr = [ordered]@{
      completa = $true; codigo = 2; rama = 'rescate/main-20260101-0000'; base = 'main'
      commits = @(
        [ordered]@{ hash = 'abc1234'; paso = 'build'; asunto = 'rescate(build): lote 1, hallazgos 3 a 0' },
        [ordered]@{ hash = 'def5678'; paso = 'estructura'; asunto = 'rescate(estructura): lote 1, hallazgos 2 a 1' },
        [ordered]@{ hash = '9999999'; paso = 'hexagonal'; asunto = 'rescate(hexagonal): lote 1, hallazgos 1 a 0' })
      atascados = @(
        [ordered]@{ paso = 'estructura'; fichero = 'src/main/java/B.java'; motivo = $MalTexto },
        [ordered]@{ paso = ''; fichero = ''; motivo = 'linea rara <b>sin formato</b>' })
      resueltos = @()
      variablesNuevas = @([ordered]@{ variable = 'CLAVE_NUEVA'; fichero = 'src/main/resources/application.yml'; linea = 4 })
    }
  }
}

$Pruebas['72 correccion con el motor de verdad: commits rescate( con su paso, correcciones.json, hallazgos-despues.json con menos errores, 2-problemas.html sigue con los de antes'] = {
  $e = Nuevo-Escenario 'corrige' @('Clase1')
  # con una clase de arranque, la clase suelta (App) es lo unico que el Copilot falso arregla: la mueve a una capa
  Escribe $e.Migrado 'src/main/java/com/acme/life/LifeApplication.java' "package com.acme.life;`n`nimport org.springframework.boot.autoconfigure.SpringBootApplication;`n`n/** Arranque. */`n@SpringBootApplication`npublic class LifeApplication {`n}`n"
  [void](GitEn $e.Migrado @('add', '-A'))
  [void](GitEn $e.Migrado @('commit', '-q', '-m', 'arranque'))
  $r = Migra $e (Corrige $e)
  Igual 'sale con 0' 0 $r.Codigo
  $commits = @(Commits-Rescate $e)
  Comprueba 'hay al menos un commit rescate( en la rama del worktree' ($commits.Count -ge 1) (Cola $r.Salida)
  $c = Lee-Json (Get-Ruta $e.Out 'datos/correcciones.json')
  Comprueba 'existe correcciones.json y esta completa' ($c -and $c.completa -eq $true) (Cola $r.Salida)
  if (-not $c -or $commits.Count -eq 0) { return }
  Comprueba 'correcciones.json lista el commit de estructura con su paso y su asunto' (@($c.commits | Where-Object { $_.paso -eq 'estructura' -and $_.asunto -like 'rescate(estructura)*' }).Count -ge 1) ($c | ConvertTo-Json -Compress -Depth 5)
  $h = Get-Ruta $e.Out 'datos/hallazgos-antes.json'
  $antes = @(Lee-Json $h)
  $hd = Get-Ruta $e.Out 'datos/hallazgos-despues.json'
  Comprueba 'existe datos/hallazgos-despues.json' (Test-Path -LiteralPath $hd)
  Comprueba 'existe datos/diagnostico-despues.md y registros/correccion.log' ((Test-Path -LiteralPath (Get-Ruta $e.Out 'datos/diagnostico-despues.md')) -and (Test-Path -LiteralPath (Get-Ruta $e.Out 'registros/correccion.log')))
  if (-not (Test-Path -LiteralPath $hd)) { return }
  $despues = @(Lee-Json $hd)
  Comprueba 'estructura tiene menos errores despues que antes' ((Errores-De $despues 'estructura') -lt (Errores-De $antes 'estructura')) "$(Errores-De $antes 'estructura') antes, $(Errores-De $despues 'estructura') despues"
  $escrito = [DateTimeOffset]::new((Get-Item -LiteralPath $h).LastWriteTimeUtc).ToUnixTimeSeconds()
  Comprueba 'el primer commit rescate( es posterior a la escritura de hallazgos-antes.json' ([long]($commits[0].Split('|')[1]) -ge $escrito) "$($commits[0]) y $escrito"
  Comprueba 'la consola cuenta el diagnostico antes que la correccion' ($r.Salida.IndexOf('Diagnostico: ') -ge 0 -and $r.Salida.IndexOf('Diagnostico: ') -lt $r.Salida.IndexOf('Correccion')) (Cola $r.Salida)
  $detalle = @($antes | Where-Object { $_.Cat -eq 'estructura' })[0].Detalle
  Comprueba '2-problemas.html sigue ensenando los hallazgos de antes' ((Pagina $e.Out '2-problemas.html').Contains((Html $detalle)))
  $p = Pagina $e.Out '4-correcciones.html'
  Comprueba '4-correcciones.html lleva el commit y la rama' ($p.Contains($commits[0].Split('|')[0]) -and $p.Contains((Html $c.rama))) (Cola $r.Salida)
  Igual 'estado.json: la fase acaba en hecha y no hay parada' 'hecha ' ((Estado $e).fase + ' ' + (Estado $e).parada)
}

$Pruebas['73 correccion: con -SoloInforme (parar) no se corrige nada, no hay registro ni correcciones.json y la pagina 4 dice que pediste parar'] = {
  $c = Corrida-Dos $GuionBase
  $e = $c.E
  Igual 'sale con 0' 0 $c.R.Codigo
  Igual 'ningun commit rescate(' 0 @(Commits-Rescate $e).Count
  Comprueba 'sin registros/correccion.log' (-not (Test-Path -LiteralPath (Get-Ruta $e.Out 'registros/correccion.log')))
  Comprueba 'sin datos/correcciones.json ni hallazgos-despues.json' ((-not (Test-Path -LiteralPath (Get-Ruta $e.Out 'datos/correcciones.json'))) -and (-not (Test-Path -LiteralPath (Get-Ruta $e.Out 'datos/hallazgos-despues.json'))))
  Comprueba 'la consola dice que no se corrige y como pedirlo (-Si)' ($c.R.Salida -match 'No se corrige' -and $c.R.Salida -match '-Si') (Cola $c.R.Salida)
  $p = Pagina $e.Out '4-correcciones.html'
  Comprueba 'existe la pagina 4 y tiene un solo h1' ($p.Length -gt 0 -and [regex]::Matches($p, '<h1[ >]').Count -eq 1) (Cola $c.R.Salida)
  Comprueba 'dice que has pedido parar y como corregir' ($p -match 'has pedido parar' -and $p.Contains('-Si'))
  Comprueba 'no dice que la fase no ha terminado' ($p -notmatch 'no ha terminado')
}

$Pruebas['74 correccion: cada codigo del motor, el motivo de parada que toca, correcciones.json, el registro y la portada'] = {
  $filas = @(
    @{ N = 'codigo 0'; Cambia = { param($o) }; Motivo = ''; Completa = $true; Codigo = 0; Registro = '' },
    @{ N = 'codigo 2 y compila: NO'; Cambia = { param($o) $o.codigo = 2; $o.despues.md = (Md-Diagnostico 'compila: NO') }; Motivo = 'no-compila'; Completa = $false; Codigo = 2; Registro = 'registros/correccion.log' },
    @{ N = 'codigo 2 y PARO:'; Cambia = { param($o) $o.codigo = 2; $o.salida = @('lote 3 deshecho', 'PARO: 6 lotes deshechos seguidos.') }; Motivo = 'lotes-deshechos'; Completa = $false; Codigo = 2; Registro = 'registros/correccion.log' },
    @{ N = 'codigo 2 con atascados'; Cambia = { param($o) $o.codigo = 2; $o.atascados = @('- [estructura] src/main/java/B.java: no pasa (registro: .rescate/lote-1.log)') }; Motivo = ''; Completa = $true; Codigo = 2; Registro = '' },
    @{ N = 'codigo 3'; Cambia = { param($o) $o.codigo = 3; $o.salida = @('git commit ha fallado') }; Motivo = 'git'; Completa = $false; Codigo = 3; Registro = 'registros/correccion.log' },
    @{ N = 'codigo 4'; Cambia = { param($o) $o.codigo = 4 }; Motivo = 'guardas'; Completa = $false; Codigo = 4; Registro = 'registros/correccion.log' },
    @{ N = 'codigo 1'; Cambia = { param($o) $o.codigo = 1; $o.salida = @('uno', 'dos', 'tres', 'No encuentro git') }; Motivo = 'motor'; Completa = $false; Codigo = 1; Registro = 'registros/correccion.log' },
    @{ N = 'el diagnostico de despues falla'; Cambia = { param($o) $o.Remove('despues') }; Motivo = 'motor'; Completa = $false; Codigo = 0; Registro = 'registros/diagnostico-despues.log' }
  )
  $n = 0
  foreach ($f in $filas) {
    $n++
    $e = Nuevo-Escenario "cod$n" @('Clase1')
    $o = Orden-Base
    & $f.Cambia $o
    $r = Migra-Motor $e $o (Corrige $e)
    $s = Estado $e
    $c = Lee-Json (Get-Ruta $e.Out 'datos/correcciones.json')
    $portada = Pagina $e.Out 'index.html'
    $sale = 0
    if ($f.Motivo) { $sale = 2 }
    Igual "$($f.N) : sale con $sale" $sale $r.Codigo
    Comprueba "$($f.N) : hay correcciones.json" ($null -ne $c) (Cola $r.Salida)
    if ($null -eq $c) { continue }
    Igual "$($f.N) : completa y codigo del motor en correcciones.json" "$($f.Completa) $($f.Codigo)" "$($c.completa) $($c.codigo)"
    if ($f.Motivo) {
      Igual "$($f.N) : parada $($f.Motivo)" $f.Motivo $s.parada.motivo
      Igual "$($f.N) : el registro de la parada" (Get-Ruta $e.Out $f.Registro) $s.parada.registro
      Comprueba "$($f.N) : la portada ensena la parada" ($portada -match "<code>$($f.Motivo)</code>" -and $portada -match 'Por qu. se ha parado')
    }
    else {
      Comprueba "$($f.N) : sin parada" ($null -eq $s.parada)
      Comprueba "$($f.N) : la portada no ensena parada" ($portada -notmatch 'Por qu. se ha parado')
    }
    if ($f.Motivo -eq 'lotes-deshechos') { Comprueba 'lotes-deshechos: el detalle dice 6 lotes seguidos deshechos' ($s.parada.detalle -match '6 lotes seguidos deshechos') $s.parada.detalle }
    if ($f.N -eq 'codigo 1') {
      Comprueba 'codigo 1: el detalle lleva el codigo y las 3 ultimas lineas' ($s.parada.detalle -match 'codigo 1' -and $s.parada.detalle -match 'dos / tres / No encuentro git' -and $s.parada.detalle -notmatch 'uno') $s.parada.detalle
      Comprueba 'codigo 1: no hay diagnostico de despues' (-not (Test-Path -LiteralPath (Get-Ruta $e.Out 'datos/hallazgos-despues.json')))
    }
    if ($f.N -eq 'codigo 0') {
      $fix = @(Llamadas-Motor $e 'fix')
      Igual 'codigo 0 : el motor se lanza una vez con -Todo -Si -Lote 1, el modelo y los esfuerzos, sobre el worktree' "fix|modelo-x|medium|high|1|True|True|$($e.Wt)" ($fix -join ' ')
      Comprueba 'codigo 0 : el registro lleva lo que dijo el motor' ((Test-Path -LiteralPath (Get-Ruta $e.Out 'registros/correccion.log')))
    }
    if ($f.Motivo -eq 'no-compila') { Comprueba 'no-compila: el diagnostico de despues esta en datos' (Test-Path -LiteralPath (Get-Ruta $e.Out 'datos/hallazgos-despues.json')) }
  }
}

$Pruebas['75 correccion: tras una corrida completa el motor no se lanza para fix; tras una parada si, y atascados.md se vacia antes; las variables nuevas no se pierden'] = {
  $e = Nuevo-Escenario 'corrige-relanza' @('Clase1')
  $o = Orden-Base
  $r = Migra-Motor $e $o (Corrige $e)
  Igual 'la primera corrida sale con 0' 0 $r.Codigo
  Igual 'un fix' 1 @(Llamadas-Motor $e 'fix').Count
  $r = Migra-Motor $e $o (Corrige $e)
  Igual 'relanzar sale con 0' 0 $r.Codigo
  Igual 'el motor no se vuelve a lanzar para fix' 1 @(Llamadas-Motor $e 'fix').Count
  Igual 'ni para el diagnostico (antes y despues, una vez cada uno)' 2 @(Llamadas-Motor $e 'diagnostico').Count
  Comprueba 'la consola no cuenta otra correccion' ($r.Salida -notmatch 'Corrigiendo') (Cola $r.Salida)
  # tras una parada
  $f = Nuevo-Escenario 'corrige-parada' @('Clase1')
  Escribe $f.Migrado 'src/main/resources/application.yml' "batch:`n  vieja: `${CLAVE_VIEJA}`n"
  [void](GitEn $f.Migrado @('add', '-A'))
  [void](GitEn $f.Migrado @('commit', '-q', '-m', 'recursos'))
  $o = Orden-Base
  $o.codigo = 3
  $o.commits = @('rescate(config): lote 1, hallazgos 1 a 0')
  $o.atascados = @('- [estructura] VIEJO.java: no pasa (registro: x)')
  $o.ficheros = [ordered]@{ 'src/main/resources/application.yml' = "batch:`n  vieja: `${CLAVE_VIEJA}`n  nueva: `${CLAVE_NUEVA}`n" }
  $r = Migra-Motor $f $o (Corrige $f)
  Igual 'la parada sale con 2' 2 $r.Codigo
  Comprueba 'atascados.md tiene la linea de la primera corrida' ((Lee $f.Wt '.rescate/atascados.md') -match 'VIEJO\.java')
  $o = Orden-Base
  $r = Migra-Motor $f $o (Corrige $f)
  Igual 'relanzar sale con 0' 0 $r.Codigo
  Igual 'el motor se lanza otra vez para fix' 2 @(Llamadas-Motor $f 'fix').Count
  Comprueba 'atascados.md se vacio antes de la segunda' (-not (Test-Path -LiteralPath (Get-Ruta $f.Wt '.rescate/atascados.md')))
  $c = Lee-Json (Get-Ruta $f.Out 'datos/correcciones.json')
  Comprueba 'correcciones.json es de la segunda: completa y sin atascados' ($c.completa -eq $true -and @($c.atascados).Count -eq 0 -and $c.codigo -eq 0) ($c | ConvertTo-Json -Compress -Depth 5)
  Igual 'la variable nueva de la primera corrida no se pierde' 'CLAVE_NUEVA' (@($c.variablesNuevas | ForEach-Object { $_.variable }) -join ' ')
  Comprueba 'estado.json ya no lleva la parada' ($null -eq (Estado $f).parada)
}

$Pruebas['76 correcciones.json: commits en orden con su paso, atascados leidos (uno normal y uno raro), resueltos sin contar la linea, variables nuevas sin valor por defecto'] = {
  $e = Nuevo-Escenario 'corrige-datos' @('Clase1')
  Escribe $e.Migrado 'src/main/resources/application.yml' "batch:`n  vieja: `${CLAVE_VIEJA}`n"
  [void](GitEn $e.Migrado @('add', '-A'))
  [void](GitEn $e.Migrado @('commit', '-q', '-m', 'recursos'))
  $o = Orden-Base
  $o.commits = @('rescate: foto del estado antes de empezar', 'rescate(estructura): lote 1, hallazgos 2 a 1', 'un commit que no es de arreglo', 'rescate(config): lote 1, hallazgos 1 a 0')
  $o.atascados = @('- [estructura] src/main/java/com/acme/life/B.java: no pasa los tests (registro: .rescate/lote-estructura-2-1.log)', 'una linea rara sin formato')
  $o.ficheros = [ordered]@{ 'src/main/resources/application.yml' = "batch:`n  vieja: `${CLAVE_VIEJA}`n  nueva: `${CLAVE_NUEVA}`n  otra: `${CON_DEFECTO:x}`n" }
  $r = Migra-Motor $e $o (Corrige $e)
  Igual 'sale con 0' 0 $r.Codigo
  $c = Lee-Json (Get-Ruta $e.Out 'datos/correcciones.json')
  Comprueba 'hay correcciones.json' ($null -ne $c) (Cola $r.Salida)
  if ($null -eq $c) { return }
  $git = @(Commits-Rescate $e)
  Igual 'commits: solo los de rescate( y en orden, con su paso' 'estructura config' (@($c.commits | ForEach-Object { $_.paso }) -join ' ')
  Igual 'commits: el hash es el corto de git' (($git | ForEach-Object { $_.Split('|')[0] }) -join ' ') (@($c.commits | ForEach-Object { $_.hash }) -join ' ')
  Igual 'commits: el asunto entero' 'rescate(estructura): lote 1, hallazgos 2 a 1' $c.commits[0].asunto
  Igual 'rama: la del worktree' (GitEn $e.Wt @('rev-parse', '--abbrev-ref', 'HEAD')) $c.rama
  Igual 'base: la rama del migrado' 'main' $c.base
  Igual 'atascados: dos' 2 @($c.atascados).Count
  Igual 'atascados: la linea normal, con paso, fichero y motivo' 'estructura|src/main/java/com/acme/life/B.java|no pasa los tests' ($c.atascados[0].paso + '|' + $c.atascados[0].fichero + '|' + $c.atascados[0].motivo)
  Igual 'atascados: la rara entera en motivo y sin paso' '||una linea rara sin formato' ($c.atascados[1].paso + '|' + $c.atascados[1].fichero + '|' + $c.atascados[1].motivo)
  Igual 'resueltos: A y el secreto; B solo cambia de linea y no cuenta' 'clase suelta A|secreto en claro' (@($c.resueltos | ForEach-Object { $_.Detalle }) -join '|')
  Igual 'variablesNuevas: solo la que no tiene valor por defecto y no estaba antes' 'CLAVE_NUEVA src/main/resources/application.yml 3' (@($c.variablesNuevas | ForEach-Object { "$($_.variable) $($_.fichero) $($_.linea)" }) -join '|')
  Comprueba 'el consumo de variables.json no cambia: sigue sin la nueva' (-not (Lee $e.Out 'datos/variables.json').Contains('CLAVE_NUEVA'))
}

$Pruebas['77 pagina 4: numeros antes y despues por area, commits y hallazgos que quedan del area, atascados con su motivo, variables nuevas, donde esta el codigo; todo escapado'] = {
  $c = Corrida-Dos $GuionBase
  $d = Datos-Pagina4
  $x = Correccion-Con $c.E 'p4-datos' $d.Antes $d.Despues $d.Corr
  $p = $x.P4
  Igual 'un solo h1: Que se ha corregido' 1 ([regex]::Matches($p, '<h1[ >]').Count)
  Comprueba 'el h1 dice Que se ha corregido' ($p -match '<h1[^>]*>Qu. se ha corregido</h1>')
  $b = Panel-De $p 'estado-build'
  Comprueba 'estado del build antes y despues, con las frases de la pagina 2' ($b.Contains('El migrado no compila.') -and $b.Contains('El migrado compila y sus tests pasan.') -and $b -match 'Medido') $b
  $r = Panel-De $p 'resumen'
  Comprueba 'resumen: errores y avisos antes -> despues' ($r.Contains('6 errores y 1 aviso ' + $Flecha + ' 1 error y 1 aviso')) $r
  Comprueba 'resumen: 3 commits de arreglo y 2 atascados' ($r -match '<b>3</b>\s*commits de arreglo' -and $r -match '<b>2</b>\s*atascados' -and $r -match 'Medido') $r
  Igual 'build: barras 3 antes y 0 despues' 'antes=3 desp=0' (Barras-De (Grupo-De $p 'build'))
  Igual 'estructura: barras 2 antes y 1 despues' 'antes=2 desp=1' (Barras-De (Grupo-De $p 'estructura'))
  Igual 'hexagonal: barras 1 antes y 0 despues' 'antes=1 desp=0' (Barras-De (Grupo-De $p 'hexagonal'))
  $g = Grupo-De $p 'estructura'
  Comprueba 'estructura: su commit con hash y asunto' ($g.Contains('def5678') -and $g.Contains('rescate(estructura): lote 1, hallazgos 2 a 1'))
  Comprueba 'estructura: no lleva los commits de otras areas' (-not $g.Contains('abc1234') -and -not $g.Contains('9999999'))
  Comprueba 'estructura: el hallazgo que queda, escapado, con su fichero:linea' ($g.Contains((Html $MalTexto)) -and $g.Contains('src/main/java/B.java:5')) $g
  Comprueba 'estructura: el atascado con su motivo, escapado' (([regex]::Matches($g, [regex]::Escape((Html $MalTexto))).Count) -ge 2) $g
  Comprueba 'estructura: no lleva el hallazgo resuelto de A' (-not $g.Contains('A suelta'))
  Comprueba 'build: su commit y no los hallazgos resueltos' ((Grupo-De $p 'build').Contains('abc1234') -and -not (Grupo-De $p 'build').Contains('pom uno'))
  Comprueba 'estado de cada area: Resuelta en build y Queda 1 en estructura' ((Grupo-De $p 'build') -match 'Resuelta' -and $g -match 'Queda 1')
  Comprueba 'el atascado sin paso sale en la pagina, escapado' ($p.Contains('linea rara &lt;b&gt;sin formato&lt;/b&gt;'))
  $sin = [regex]::Match($p, '(?s)<div class="sin-prob">.*?</div>').Value
  Comprueba 'las areas limpias antes y despues, en una linea (ficheros, config, paridad, e2e y calidad)' ([regex]::Matches($sin, '<li>').Count -eq 5 -and $sin -match 'Sin problemas') $sin
  Comprueba 'el area de solo avisos (tests) sale con su aviso' ((Grupo-De $p 'tests') -match 'no hay tests')
  $v = Panel-De $p 'variables-nuevas'
  Comprueba 'variables nuevas: la variable con fichero:linea y la frase de darlas como variable de entorno' ($v.Contains('CLAVE_NUEVA') -and $v.Contains('src/main/resources/application.yml:4') -and $v -match 'variable de entorno' -and $v -match 'Medido') $v
  $co = Panel-De $p 'codigo'
  $st = Lee-Json (Get-Ruta $x.Dir 'datos/estado.json')
  Comprueba 'donde esta el codigo: la rama y el worktree' ($co.Contains('rescate/main-20260101-0000') -and $co.Contains((Html $st.worktree))) $co
  Comprueba 'las tres ordenes de git (diff, merge y worktree remove), escapadas' ($co.Contains('diff --stat main...rescate/main-20260101-0000') -and $co.Contains('merge rescate/main-20260101-0000') -and $co.Contains('worktree remove') -and $co -match 'Nada se ha subido') $co
  Comprueba 'sin JavaScript ni nada externo' ($p -notmatch '(?i)<script' -and $p -notmatch 'https?://' -and $p -notmatch '<link|<img|@import')
  Comprueba 'enlaces a las otras paginas y todos llevan a un sitio que existe' ($p -match 'href="index\.html"' -and $p -match 'href="1-batch-original\.html"' -and $p -match 'href="2-problemas\.html"' -and (@([regex]::Matches($p, '(?i)\b(?:src|href)\s*=\s*"(?!#)([^"]*)"') | Where-Object { -not (Test-Path -LiteralPath (Get-Ruta $x.Dir $_.Groups[1].Value)) }).Count -eq 0))
  # la corrida incompleta lo avisa; sin variables nuevas no sale la seccion
  $d.Corr.completa = $false
  $d.Corr.variablesNuevas = @()
  $y = Correccion-Con $c.E 'p4-parcial' $d.Antes $d.Despues $d.Corr
  Comprueba 'una corrida sin terminar lo dice' ($y.P4 -match 'no ha terminado')
  Comprueba 'sin variables nuevas, la seccion no sale' ($y.P4 -notmatch 'variables-nuevas')
  # sin los datos de despues
  $z = Copia-Salida $c.E 'p4-sin-despues'
  Guarda-Json (Join-Path $z 'datos/correcciones.json') $d.Corr
  $g2 = Genera-Informes $z
  Comprueba 'con correcciones.json pero sin el diagnostico de despues, la pagina dice que falta y se genera' ($g2.Codigo -eq 0 -and (Pagina $z '4-correcciones.html') -match 'no ha terminado')
  # respuesta corregir y sin datos: la fase correccion no ha terminado
  $w = Copia-Salida $c.E 'p4-corregir-sin-datos'
  $st = Lee-Json (Join-Path $w 'datos/estado.json')
  $st.respuesta = 'corregir'
  Guarda-Json (Join-Path $w 'datos/estado.json') $st
  $g3 = Genera-Informes $w
  Comprueba 'con respuesta corregir y sin datos: la fase correccion no ha terminado' ($g3.Codigo -eq 0 -and (Pagina $w '4-correcciones.html') -match 'la fase correccion no ha terminado')
}

$Pruebas['78 portada: barras antes y despues, total antes -> despues, linea de correccion, grupos de arreglos atascados y de variables, ficheros nuevos y navegacion'] = {
  $c = Corrida-Dos $GuionBase
  $d = Datos-Pagina4
  $x = Correccion-Con $c.E 'p4-portada' $d.Antes $d.Despues $d.Corr
  $i = $x.I
  $sec = Panel-De $i 'problemas-migrado'
  Igual 'una barra despues por cada barra antes (3 areas con errores)' 3 ([regex]::Matches($sec, 'class="barra desp"').Count)
  Igual 'y 3 barras antes' 3 ([regex]::Matches($sec, 'class="barra antes"').Count)
  Comprueba 'los valores: build 3 -> 0, estructura 2 -> 1, hexagonal 1 -> 0' ((Barras-De $sec) -eq 'antes=3 desp=0 antes=2 desp=1 antes=1 desp=0') (Barras-De $sec)
  Comprueba 'el total pasa a antes -> despues' ($sec.Contains('6 errores y 1 aviso ' + $Flecha + ' 1 error y 1 aviso')) $sec
  Comprueba 'estado de cada area: Resuelta y Queda 1' ($sec -match 'Resuelta' -and $sec -match 'Queda 1')
  $fases = [regex]::Match($i, '(?s)<ol class="fases">.*?</ol>').Value
  $ultima = @([regex]::Matches($fases, '(?s)<li>.*?</li>') | Where-Object { $_.Value -match 'Correcci.n del migrado' })[0].Value
  Comprueba 'Que ha hecho el script: la linea de la correccion lleva commits y atascados' ($ultima.Length -gt 0 -and $ultima.Contains('commits: 3, atascados: 2')) $ultima
  $toca = Toca-De $i
  $ga = [regex]::Match($toca, '(?s)<h3>Arreglos atascados \(2\)</h3>.*?</div>').Value
  Comprueba 'Lo que te toca: el grupo Arreglos atascados (2) con un elemento por atascado (paso, fichero y motivo)' ($ga.Length -gt 0 -and [regex]::Matches($ga, '<li>').Count -eq 2 -and $ga.Contains('estructura') -and $ga.Contains('src/main/java/B.java') -and $ga.Contains((Html $MalTexto))) $toca
  $gv = [regex]::Match($toca, '(?s)<h3>Variables que tienes que dar al lanzar \(1\)</h3>.*?</div>').Value
  Comprueba 'y el grupo de variables que tienes que dar al lanzar (1)' ($gv.Contains('CLAVE_NUEVA') -and $gv.Contains('application.yml:4') -and [regex]::Matches($gv, '<li>').Count -eq 1) $toca
  $f = [regex]::Match($i, '(?s)<ul class="ficheros">.*?</ul>').Value
  Comprueba 'Que es cada fichero: los cinco nuevos' ($f.Contains('4-correcciones.html') -and $f.Contains('datos/correcciones.json') -and $f.Contains('datos/hallazgos-despues.json') -and $f.Contains('datos/diagnostico-despues.md') -and $f.Contains('registros/correccion.log')) $f
  foreach ($par in @(@('index.html', $i), @('1-batch-original.html', (Pagina $x.Dir '1-batch-original.html')), @('2-problemas.html', $x.P2), @('4-correcciones.html', $x.P4))) {
    $h = $par[1]
    Comprueba "$($par[0]) : la navegacion lleva a Correcciones" ($h -match 'href="4-correcciones\.html"' -and $h -match '>Correcciones<')
    Igual "$($par[0]) : aria-current solo en su pagina" 1 ([regex]::Matches($h, 'aria-current="page"').Count)
    Comprueba "$($par[0]) : y es el de su enlace" ($h -match ('href="' + [regex]::Escape($par[0]) + '" aria-current="page"'))
  }
  # sin atascados y sin variables nuevas, los grupos no salen y lo que te toca lo dice
  $d.Corr.atascados = @()
  $d.Corr.variablesNuevas = @()
  $y = Correccion-Con $c.E 'p4-portada-limpia' $d.Antes $d.Despues $d.Corr
  $t2 = Toca-De $y.I
  Comprueba 'sin atascados ni variables nuevas no salen los grupos' ($t2 -notmatch 'Arreglos atascados' -and $t2 -notmatch 'Variables que tienes')
  Comprueba 'la linea de la correccion dice atascados: 0' ($y.I -match 'commits: 3, atascados: 0')
  $n = Nuevo-Escenario 'sin-correccion-toca' @('Clase1')
  [void](Migra $n (Basicos $n))
  $t3 = Toca-De (Pagina $n.Out 'index.html')
  Comprueba 'sin nada que revisar, lo que te toca nombra tambien los arreglos atascados y las variables nuevas' ($t3 -match 'Nada que revisar' -and $t3 -match 'ning.n arreglo atascado y ninguna variable nueva') $t3
}

$Pruebas['79 singular y plural: 1 error y 1 aviso, 2 errores y 0 avisos en las paginas 2 y 4 y en la portada'] = {
  $c = Corrida-Dos $GuionBase
  $aviso = Hallazgo 'tests' 'aviso' 'T.java' 1 'un aviso'
  $corr = [ordered]@{ completa = $true; codigo = 0; rama = 'rescate/x'; base = 'main'; commits = @(); atascados = @(); resueltos = @(); variablesNuevas = @() }
  $uno = @((Hallazgo 'build' 'error' 'pom.xml' 0 'un error'), $aviso)
  $x = Correccion-Con $c.E 'plural-uno' $uno $uno $corr
  foreach ($par in @(@('2-problemas.html', $x.P2), @('4-correcciones.html', $x.P4), @('index.html', $x.I))) {
    Comprueba "$($par[0]) : dice 1 error y 1 aviso" ($par[1].Contains('1 error y 1 aviso')) $par[0]
    Comprueba "$($par[0]) : ni 1 errores ni 1 avisos" ($par[1] -notmatch '\b1 errores\b' -and $par[1] -notmatch '\b1 avisos\b')
  }
  Comprueba 'pagina 2: el grupo dice 1 error, 0 avisos y el de tests 0 errores, 1 aviso' ((Grupo-De $x.P2 'build').Contains('1 error, 0 avisos') -and (Grupo-De $x.P2 'tests').Contains('0 errores, 1 aviso'))
  $dos = @((Hallazgo 'build' 'error' 'pom.xml' 0 'uno'), (Hallazgo 'build' 'error' 'pom.xml' 0 'dos'))
  $y = Correccion-Con $c.E 'plural-dos' $dos $dos $corr
  foreach ($par in @(@('2-problemas.html', $y.P2), @('4-correcciones.html', $y.P4), @('index.html', $y.I))) {
    Comprueba "$($par[0]) : dice 2 errores y 0 avisos" ($par[1].Contains('2 errores y 0 avisos'))
  }
  Comprueba 'pagina 2: el grupo dice 2 errores, 0 avisos' ((Grupo-De $y.P2 'build').Contains('2 errores, 0 avisos'))
}

# ============================ COBERTURA DE TESTS ============================
# El texto de un jacoco.csv de mentira: una fila por clase ('nombre', faltan, cubiertas) con las columnas de $Cab, en ese orden. En las
# columnas que no son de lineas va un 7: si algo leyera por posicion y no por nombre, saldria otra cifra.
function Csv-Texto($Filas, [string[]]$Cab = @('GROUP', 'PACKAGE', 'CLASS', 'LINE_MISSED', 'LINE_COVERED')) {
  $t = ($Cab -join ',') + "`n"
  foreach ($f in $Filas) {
    $v = @()
    foreach ($c in $Cab) {
      if ($c -eq 'GROUP') { $v += '' }
      elseif ($c -eq 'PACKAGE') { $v += 'com.acme' }
      elseif ($c -eq 'CLASS') { $v += $f[0] }
      elseif ($c -eq 'LINE_MISSED') { $v += $f[1] }
      elseif ($c -eq 'LINE_COVERED') { $v += $f[2] }
      else { $v += '7' }
    }
    $t += ($v -join ',') + "`n"
  }
  return $t
}

function Csv-Cobertura([string]$Ruta, $Filas, [string[]]$Cab = @('GROUP', 'PACKAGE', 'CLASS', 'LINE_MISSED', 'LINE_COVERED')) {
  [System.IO.File]::WriteAllText($Ruta, (Csv-Texto $Filas $Cab))
  return $Ruta
}

# Pone variables de entorno mientras corre el bloque (el JaCoCo falso de tests/falsos/mvn.ps1 las lee) y las quita al acabar.
function Con-Entorno([hashtable]$Vars, [scriptblock]$Bloque) {
  foreach ($k in $Vars.Keys) { [Environment]::SetEnvironmentVariable($k, [string]$Vars[$k]) }
  try { return (& $Bloque) }
  finally { foreach ($k in $Vars.Keys) { [Environment]::SetEnvironmentVariable($k, $null) } }
}

# Un escenario cuyo Maven apunta cada llamada en mvn-llamadas.txt (una linea por llamada) y sigue con el Maven falso.
function Nuevo-Escenario-Contado([string]$Nombre, [string[]]$Clases = @('Clase1'), [hashtable]$Ajustes = @{}) {
  $aj = @{ MvnExe = (Join-Path (Join-Path $Dir $Nombre) 'mvn-contado.ps1') }
  foreach ($k in $Ajustes.Keys) { $aj[$k] = $Ajustes[$k] }
  $e = Nuevo-Escenario $Nombre $Clases $aj
  $envoltorio = @'
[System.IO.File]::AppendAllText('{{LOG}}', (($args -join ' ') + "`n"))
& '{{MVN}}' @args
exit $LASTEXITCODE
'@
  Escribe $e.Raiz 'mvn-contado.ps1' ($envoltorio.Replace('{{LOG}}', (Join-Path $e.Raiz 'mvn-llamadas.txt')).Replace('{{MVN}}', (Join-Path $falsos 'mvn.ps1')))
  return $e
}

function Llamadas-Mvn($E) {
  $f = Get-Ruta $E.Raiz 'mvn-llamadas.txt'
  if (-not (Test-Path -LiteralPath $f)) { return @() }
  return @([System.IO.File]::ReadAllLines($f) | Where-Object { $_ })
}

function Con-JaCoCo($Llamadas) { return @($Llamadas | Where-Object { $_ -match 'jacoco-maven-plugin' }) }

function Cobertura-De($E, [string]$Cuando) { return (Lee-Json (Get-Ruta $E.Out "datos/cobertura-$Cuando.json")) }

# Repite el diagnostico de antes de un escenario ya corrido (relanzar lo salta mientras estan los hallazgos): quita hallazgos-antes.json y lanza otra vez.
function Re-Diagnostica($E, [hashtable]$Entorno) {
  Remove-Item -LiteralPath (Get-Ruta $E.Out 'datos/hallazgos-antes.json') -Force
  return (Con-Entorno $Entorno { Migra $E (Basicos $E) })
}

# La linea de cobertura de la portada.
function Linea-Cobertura([string]$Html) { return [regex]::Match($Html, '(?s)<p class="cob-linea">.*?</p>').Value }

$Pruebas['80 cobertura: un CSV de dos clases da 62,5 %, 5 de 8 y minimo 80 en cobertura-antes.json, con un solo Maven, su registro y la pagina 2; relanzar no lo repite'] = {
  $e = Nuevo-Escenario-Contado 'cob-dos'
  $csv = Csv-Cobertura (Get-Ruta $e.Raiz 'jacoco.csv') @(@('A', 3, 1), @('B', 0, 4))
  $r = Con-Entorno @{ RESCATE_JACOCO_CSV = $csv } { Migra $e (Basicos $e) }
  Igual 'sale con 0' 0 $r.Codigo
  $c = Cobertura-De $e 'antes'
  Comprueba 'existe datos/cobertura-antes.json' ($null -ne $c) (Cola $r.Salida)
  if ($null -eq $c) { return }
  Igual 'los campos, en su orden' 'medida porcentaje cubiertas total minima motivo' ($c.PSObject.Properties.Name -join ' ')
  Igual 'medida' 'True' "$($c.medida)"
  Igual 'porcentaje con un decimal' '62.5' "$($c.porcentaje)"
  Igual 'cubiertas (1 + 4)' '5' "$($c.cubiertas)"
  Igual 'total (4 + 4)' '8' "$($c.total)"
  Igual 'minima' '80' "$($c.minima)"
  Igual 'motivo vacio' '' "$($c.motivo)"
  Comprueba 'no hay cobertura de despues' (-not (Test-Path -LiteralPath (Get-Ruta $e.Out 'datos/cobertura-despues.json')))
  Comprueba 'el registro del Maven esta en registros/cobertura-antes.log' (Test-Path -LiteralPath (Get-Ruta $e.Out 'registros/cobertura-antes.log'))
  $ll = @(Llamadas-Mvn $e)
  $jc = @(Con-JaCoCo $ll)
  Igual 'un solo Maven con JaCoCo' 1 $jc.Count
  Comprueba 'es prepare-agent, test y report con la version de Cfg.JacocoPlugin' ($jc.Count -eq 1 -and $jc[0] -match '^-B org\.jacoco:jacoco-maven-plugin:0\.8\.16:prepare-agent test org\.jacoco:jacoco-maven-plugin:0\.8\.16:report$') ($jc -join ' | ')
  Comprueba 'ningun proceso mas para la cobertura (ni --version ni -v)' (@($ll | Where-Object { $_ -match '(^|\s)(-v|--version)(\s|$)' }).Count -eq 0) ($ll -join ' | ')
  $p = Pagina $e.Out '2-problemas.html'
  $b = Panel-De $p 'cobertura'
  Comprueba 'la pagina 2 tiene el panel Cobertura de tests' ($b -match '<h2[^>]*>Cobertura de tests</h2>') $b
  Comprueba 'lo etiqueta como Medido' ($b -match 'Medido') $b
  Comprueba 'dice 62,5 % y 5 de 8 lineas' ($b.Contains('62,5 %') -and $b -match '5 de 8 l.neas') $b
  Comprueba 'dice el minimo (80 %) y que esta por debajo' ($b -match 'm.nimo de 80 %' -and $b.Contains('por debajo')) $b
  Comprueba 'lleva el componente: la fila cob-fila con su meter, el relleno y el umbral' ($b.Contains('class="cob-fila') -and $b.Contains('class="meter"') -and $b.Contains('--v:62.5') -and $b.Contains('--u:80')) $b
  Comprueba 'sin JavaScript' ($p -notmatch '(?i)<script')
  $i = Pagina $e.Out 'index.html'
  $l = Linea-Cobertura $i
  Comprueba 'la portada tiene una linea con la cobertura y el minimo' ($l.Contains('62,5 %') -and $l -match 'm.nimo de 80 %' -and $l.Contains('por debajo')) $l
  Comprueba 'y esa linea esta en Problemas del migrado' ((Panel-De $i 'problemas-migrado').Contains($l))
  $fase = @([regex]::Matches([regex]::Match($i, '(?s)<ol class="fases">.*?</ol>').Value, '(?s)<li>.*?</li>'))[0].Value
  Comprueba 'Que ha hecho el script: la linea del diagnostico anade la cobertura' ($fase -match 'Diagn.stico' -and $fase -match 'cobertura: 62,5 %') $fase
  $f = [regex]::Match($i, '(?s)<ul class="ficheros">.*?</ul>').Value
  Comprueba 'Que es cada fichero: el JSON y el registro de antes' ($f.Contains('datos/cobertura-antes.json') -and $f.Contains('registros/cobertura-antes.log')) $f
  Comprueba 'y ninguno de despues' (-not $f.Contains('cobertura-despues')) $f
  # relanzar no repite la medida: va con el diagnostico, que ya esta
  $jh = Hash-De (Get-Ruta $e.Out 'datos/cobertura-antes.json')
  $lh = Hash-De (Get-Ruta $e.Out 'registros/cobertura-antes.log')
  $r2 = Con-Entorno @{ RESCATE_JACOCO_CSV = $csv } { Migra $e (Basicos $e) }
  Igual 'el segundo lanzamiento sale con 0' 0 $r2.Codigo
  Igual 'cobertura-antes.json no cambia' $jh (Hash-De (Get-Ruta $e.Out 'datos/cobertura-antes.json'))
  Igual 'el registro no cambia' $lh (Hash-De (Get-Ruta $e.Out 'registros/cobertura-antes.log'))
  Igual 'y Maven no se lanza otra vez para medir' 1 (@(Con-JaCoCo (Llamadas-Mvn $e))).Count
}

$Pruebas['81 cobertura: las columnas se leen por nombre: en otro orden y con columnas de mas (como el CSV real de JaCoCo) da lo mismo'] = {
  $e = Nuevo-Escenario-Contado 'cob-cols'
  $filas = @(@('A', 3, 1), @('B', 0, 4))
  $real = @('GROUP', 'PACKAGE', 'CLASS', 'INSTRUCTION_MISSED', 'INSTRUCTION_COVERED', 'BRANCH_MISSED', 'BRANCH_COVERED', 'LINE_MISSED', 'LINE_COVERED', 'COMPLEXITY_MISSED', 'COMPLEXITY_COVERED', 'METHOD_MISSED', 'METHOD_COVERED')
  $vuelto = @('METHOD_COVERED', 'LINE_COVERED', 'CLASS', 'LINE_MISSED', 'GROUP', 'INSTRUCTION_MISSED')
  $csv = Csv-Cobertura (Get-Ruta $e.Raiz 'jacoco.csv') $filas $real
  $r = Con-Entorno @{ RESCATE_JACOCO_CSV = $csv } { Migra $e (Basicos $e) }
  Igual 'con las 13 columnas de JaCoCo sale con 0' 0 $r.Codigo
  $c = Cobertura-De $e 'antes'
  Comprueba 'con las 13 columnas: 62,5 %, 5 de 8' ($null -ne $c -and "$($c.porcentaje) $($c.cubiertas) $($c.total)" -ceq '62.5 5 8') (Cola $r.Salida)
  $csv = Csv-Cobertura (Get-Ruta $e.Raiz 'jacoco.csv') $filas $vuelto
  $r = Re-Diagnostica $e @{ RESCATE_JACOCO_CSV = $csv }
  Igual 'con las columnas en otro orden sale con 0' 0 $r.Codigo
  $c = Cobertura-De $e 'antes'
  Comprueba 'en otro orden y con columnas de mas: lo mismo' ($null -ne $c -and "$($c.medida) $($c.porcentaje) $($c.cubiertas) $($c.total)" -ceq 'True 62.5 5 8') (Cola $r.Salida)
  Igual 'cada diagnostico lanza su Maven con JaCoCo' 2 (@(Con-JaCoCo (Llamadas-Mvn $e))).Count
}

$Pruebas['82 cobertura sin medida: sin CSV, CSV sin esas columnas, CSV ilegible, total 0 y Maven con error dejan medida false, porcentaje nulo y su motivo; la pagina no pinta ningun 0 %'] = {
  $e = Nuevo-Escenario-Contado 'cob-sin'
  $r = Migra $e (Basicos $e)
  Igual 'la primera corrida (el JaCoCo de siempre) sale con 0' 0 $r.Codigo
  Igual 'y mide: 100 % con el CSV del falso' '100' "$((Cobertura-De $e 'antes').porcentaje)"
  Comprueba 'deja su CSV en el worktree (es el viejo que hay que borrar antes de medir)' (Test-Path -LiteralPath (Get-Ruta $e.Wt 'target/site/jacoco/jacoco.csv'))
  $sinCols = Csv-Cobertura (Get-Ruta $e.Raiz 'sin-columnas.csv') @(,@('A', 3, 1)) @('GROUP', 'PACKAGE', 'CLASS', 'INSTRUCTION_MISSED', 'INSTRUCTION_COVERED')
  $cero = Csv-Cobertura (Get-Ruta $e.Raiz 'cero.csv') @(@('A', 0, 0), @('B', 0, 0))
  $malo = Csv-Cobertura (Get-Ruta $e.Raiz 'malo.csv') @(,@('A', 'x', 1))
  $casos = @(
    @{ N = 'sin CSV'; Env = @{ RESCATE_JACOCO_SIN_CSV = '1' }; Motivo = 'jacoco\.csv.*hay tests' },
    @{ N = 'CSV sin las columnas de lineas'; Env = @{ RESCATE_JACOCO_CSV = $sinCols }; Motivo = 'LINE_MISSED.*LINE_COVERED' },
    @{ N = 'total de lineas 0'; Env = @{ RESCATE_JACOCO_CSV = $cero }; Motivo = 'ninguna linea medible' },
    @{ N = 'CSV con un valor que no es un numero'; Env = @{ RESCATE_JACOCO_CSV = $malo }; Motivo = 'no se puede leer' },
    @{ N = 'Maven con error'; Env = @{ RESCATE_MVN_ERROR = 'fallo de mentira de Maven' }; Motivo = 'Maven.*fallo de mentira de Maven' }
  )
  foreach ($k in $casos) {
    $r = Re-Diagnostica $e $k.Env
    Igual "$($k.N) : sale con 0" 0 $r.Codigo
    $c = Cobertura-De $e 'antes'
    Comprueba "$($k.N) : hay cobertura-antes.json" ($null -ne $c) (Cola $r.Salida)
    if ($null -eq $c) { continue }
    Igual "$($k.N) : medida false" 'False' "$($c.medida)"
    Comprueba "$($k.N) : porcentaje nulo (nunca un 0 % que no se ha medido)" ($null -eq $c.porcentaje) ($c | ConvertTo-Json -Compress)
    Comprueba "$($k.N) : cubiertas y total nulos" (($null -eq $c.cubiertas) -and ($null -eq $c.total))
    Comprueba "$($k.N) : motivo" ("$($c.motivo)" -match $k.Motivo) "$($c.motivo)"
    $p = Pagina $e.Out '2-problemas.html'
    $b = Panel-De $p 'cobertura'
    Comprueba "$($k.N) : la pagina 2 dice no se ha podido medir y el motivo" ($b.Contains('no se ha podido medir: ' + (Html "$($c.motivo)"))) $b
    Comprueba "$($k.N) : la pagina 2 no pinta ningun porcentaje ni 0 %" ($b -notmatch '\d\s*%' -and $b -notmatch 'meter') $b
    Comprueba "$($k.N) : esta sin comprobar, no medido" ($b -match 'Sin comprobar' -and $b -notmatch 'Medido') $b
    $l = Linea-Cobertura (Pagina $e.Out 'index.html')
    Comprueba "$($k.N) : la portada dice lo mismo, sin porcentaje" ($l.Contains('no se ha podido medir: ' + (Html "$($c.motivo)")) -and $l -notmatch '\d\s*%') $l
    $fase = @([regex]::Matches([regex]::Match((Pagina $e.Out 'index.html'), '(?s)<ol class="fases">.*?</ol>').Value, '(?s)<li>.*?</li>'))[0].Value
    Comprueba "$($k.N) : Que ha hecho el script dice cobertura: sin medir" ($fase -match 'cobertura: sin medir' -and $fase -notmatch '\d\s*%') $fase
  }
}

$Pruebas['83 cobertura: un migrado que no compila no lanza Maven para medir y dice que no compila'] = {
  $e = Nuevo-Escenario-Contado 'cob-nocompila'
  Escribe $e.Migrado 'src/main/java/com/acme/life/Rota.java' "package com.acme.life;`n`n/** NO_COMPILA. */`npublic class Rota {`n}`n"
  [void](GitEn $e.Migrado @('add', '-A'))
  [void](GitEn $e.Migrado @('commit', '-q', '-m', 'rota'))
  $csv = Csv-Cobertura (Get-Ruta $e.Raiz 'jacoco.csv') @(,@('A', 3, 1))
  $r = Con-Entorno @{ RESCATE_JACOCO_CSV = $csv } { Migra $e (Basicos $e) }
  Igual 'sale con 0' 0 $r.Codigo
  Comprueba 'el diagnostico dice compila: NO' ((Lee $e.Out 'datos/diagnostico-antes.md') -match '(?m)^- Estado: compila: NO\s*$') (Cola $r.Salida)
  $ll = @(Llamadas-Mvn $e)
  Comprueba 'el Maven del diagnostico si se lanzo (el registro de llamadas funciona)' ($ll.Count -ge 1) ($ll -join ' | ')
  Igual 'pero Maven no se lanza para medir (ninguna llamada con JaCoCo)' 0 (@(Con-JaCoCo $ll)).Count
  $c = Cobertura-De $e 'antes'
  Comprueba 'hay cobertura-antes.json' ($null -ne $c) (Cola $r.Salida)
  if ($null -eq $c) { return }
  Igual 'medida false' 'False' "$($c.medida)"
  Comprueba 'porcentaje nulo' ($null -eq $c.porcentaje)
  Igual 'motivo: el migrado no compila' 'el migrado no compila' "$($c.motivo)"
  Comprueba 'no hay registro de cobertura (no se lanzo Maven)' (-not (Test-Path -LiteralPath (Get-Ruta $e.Out 'registros/cobertura-antes.log')))
  $b = Panel-De (Pagina $e.Out '2-problemas.html') 'cobertura'
  Comprueba 'la pagina 2 dice no se ha podido medir: el migrado no compila' ($b.Contains('no se ha podido medir: el migrado no compila')) $b
}

$Pruebas['84 cobertura: CoberturaMinima de ajustes.json manda: con 50 y 62,5 % no sale por debajo'] = {
  $e = Nuevo-Escenario-Contado 'cob-min' @('Clase1') @{ CoberturaMinima = 50 }
  $csv = Csv-Cobertura (Get-Ruta $e.Raiz 'jacoco.csv') @(@('A', 3, 1), @('B', 0, 4))
  $r = Con-Entorno @{ RESCATE_JACOCO_CSV = $csv } { Migra $e (Basicos $e) }
  Igual 'sale con 0' 0 $r.Codigo
  Comprueba 'la consola no avisa de claves desconocidas' ($r.Salida -notmatch 'clave desconocida') (Cola $r.Salida)
  $c = Cobertura-De $e 'antes'
  Comprueba 'cobertura-antes.json lleva minima 50 y 62,5 %' ($null -ne $c -and "$($c.minima) $($c.porcentaje)" -ceq '50 62.5') (Cola $r.Salida)
  $b = Panel-De (Pagina $e.Out '2-problemas.html') 'cobertura'
  Comprueba 'la pagina 2 no dice por debajo y cumple el minimo de 50 %' ($b -notmatch 'por debajo' -and $b -match 'm.nimo de 50 %') $b
  Comprueba 'el umbral del medidor esta en 50' ($b.Contains('--u:50')) $b
  $l = Linea-Cobertura (Pagina $e.Out 'index.html')
  Comprueba 'la portada tampoco' ($l.Contains('62,5 %') -and $l -notmatch 'por debajo' -and $l -match 'm.nimo de 50 %') $l
}

$Pruebas['85 cobertura despues de corregir: cobertura-despues.json con su registro; la portada ensena la de despues y la pagina 4, antes -> despues'] = {
  $e = Nuevo-Escenario-Contado 'cob-despues'
  $csv = Csv-Cobertura (Get-Ruta $e.Raiz 'jacoco.csv') @(@('A', 3, 1), @('B', 0, 4))
  # el motor falso "mejora los tests": al arreglar reescribe el CSV (esta junto al worktree) y el diagnostico de despues lo mide
  $o = Orden-Base
  $o['ficheros'] = [ordered]@{ '../jacoco.csv' = (Csv-Texto @(@('A', 1, 3), @('B', 0, 4))) }
  $r = Con-Entorno @{ RESCATE_JACOCO_CSV = $csv } { Migra-Motor $e $o (Corrige $e) }
  Igual 'sale con 0' 0 $r.Codigo
  $a = Cobertura-De $e 'antes'
  $d = Cobertura-De $e 'despues'
  Comprueba 'antes: 62,5 %, 5 de 8' ($null -ne $a -and "$($a.medida) $($a.porcentaje) $($a.cubiertas) $($a.total)" -ceq 'True 62.5 5 8') (Cola $r.Salida)
  Comprueba 'despues: 87,5 %, 7 de 8' ($null -ne $d -and "$($d.medida) $($d.porcentaje) $($d.cubiertas) $($d.total)" -ceq 'True 87.5 7 8') (Cola $r.Salida)
  Comprueba 'los dos registros' ((Test-Path -LiteralPath (Get-Ruta $e.Out 'registros/cobertura-antes.log')) -and (Test-Path -LiteralPath (Get-Ruta $e.Out 'registros/cobertura-despues.log')))
  Igual 'un Maven con JaCoCo por diagnostico' 2 (@(Con-JaCoCo (Llamadas-Mvn $e))).Count
  Comprueba 'el despues se midio sobre el worktree ya corregido, que el motor deja limpio' ((GitEn $e.Wt @('status', '--porcelain')) -eq '')
  $p2 = Pagina $e.Out '2-problemas.html'
  Comprueba 'la pagina 2 sigue con la de antes' ((Panel-De $p2 'cobertura').Contains('62,5 %') -and -not $p2.Contains('87,5 %'))
  $i = Pagina $e.Out 'index.html'
  $l = Linea-Cobertura $i
  Comprueba 'la portada ensena la de despues (87,5 %, que cumple) y no la de antes' ($l.Contains('87,5 %') -and -not $l.Contains('62,5 %') -and $l -match 'despu.s de corregir' -and $l -notmatch 'por debajo' -and $l -match 'm.nimo de 80 %') $l
  $p4 = Panel-De (Pagina $e.Out '4-correcciones.html') 'cobertura'
  Comprueba 'la pagina 4 dice Cobertura: 62,5 % -> 87,5 %' ($p4.Contains('Cobertura: 62,5 % ' + $Flecha + ' 87,5 %')) $p4
  Comprueba 'y que cumple el minimo' ($p4 -match 'Cumple el m.nimo de 80 %' -and $p4 -match 'Medido') $p4
  $f = [regex]::Match($i, '(?s)<ul class="ficheros">.*?</ul>').Value
  Comprueba 'Que es cada fichero: los dos JSON y los dos registros' ($f.Contains('datos/cobertura-antes.json') -and $f.Contains('datos/cobertura-despues.json') -and $f.Contains('registros/cobertura-antes.log') -and $f.Contains('registros/cobertura-despues.log')) $f
}

# Las paginas con estos datos de cobertura (null = sin el fichero) sobre una copia de una corrida, con los datos de la prueba 77 para la pagina 4.
function Cobertura-Con($E, [string]$Nombre, $Antes, $Despues) {
  $d = Datos-Pagina4
  $x = Correccion-Con $E $Nombre $d.Antes $d.Despues $d.Corr
  foreach ($par in @(@('antes', $Antes), @('despues', $Despues))) {
    $f = Join-Path $x.Dir ('datos/cobertura-' + $par[0] + '.json')
    if ($par[1]) { Guarda-Json $f $par[1] } elseif (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force }
  }
  $g = Genera-Informes $x.Dir
  Comprueba "$Nombre : Write-Informes sale bien" ($g.Codigo -eq 0 -and $g.Salida -match 'INFORMES-OK') (Cola $g.Salida)
  return [pscustomobject]@{ Dir = $x.Dir; P2 = (Pagina $x.Dir '2-problemas.html'); P4 = (Pagina $x.Dir '4-correcciones.html'); I = (Pagina $x.Dir 'index.html') }
}

function Cob([double]$Pct, [int]$Cub, [int]$Tot, [int]$Min = 80) {
  return [ordered]@{ medida = $true; porcentaje = $Pct; cubiertas = $Cub; total = $Tot; minima = $Min; motivo = '' }
}

function Cob-Sin([string]$Motivo) {
  return [ordered]@{ medida = $false; porcentaje = $null; cubiertas = $null; total = $null; minima = 80; motivo = $Motivo }
}

$Pruebas['86 paginas de cobertura: casos de los datos (medida, sin medir, ausente, 0 % medido, 100 %), todo escapado'] = {
  $c = Corrida-Dos $GuionBase
  # antes medida y despues sin medir (con markup en el motivo)
  $x = Cobertura-Con $c.E 'cob-a-sin' (Cob 62.5 5 8) (Cob-Sin $MalTexto)
  $b4 = Panel-De $x.P4 'cobertura'
  Comprueba 'pagina 4: 62,5 % -> sin medir (motivo escapado)' ($b4.Contains('Cobertura: 62,5 % ' + $Flecha + ' sin medir (' + (Html $MalTexto) + ')')) $b4
  Comprueba 'pagina 4: sin la frase de por debajo ni de cumple (la de despues no se midio)' ($b4 -notmatch 'por debajo' -and $b4 -notmatch 'Cumple') $b4
  $l = Linea-Cobertura $x.I
  Comprueba 'portada: la de despues, sin medir, con el motivo escapado y sin porcentaje' ($l.Contains('no se ha podido medir: ' + (Html $MalTexto)) -and $l -notmatch '\d\s*%' -and $l -match 'despu.s de corregir') $l
  Comprueba 'pagina 2: sigue con la de antes' ((Panel-De $x.P2 'cobertura').Contains('62,5 %'))
  Comprueba 'el markup del motivo no sale sin escapar en ninguna pagina' (-not $x.P4.Contains('<script>alert(1)') -and -not $x.I.Contains('<script>alert(1)') -and -not $x.P2.Contains('<script>alert(1)'))
  # solo la de antes (no hay de despues): la portada la ensena y la pagina 4 dice sin dato
  $y = Cobertura-Con $c.E 'cob-solo-antes' (Cob 62.5 5 8) $null
  Comprueba 'sin la de despues, la portada ensena la de antes' ((Linea-Cobertura $y.I).Contains('62,5 %') -and (Linea-Cobertura $y.I) -match 'antes de corregir') (Linea-Cobertura $y.I)
  Comprueba 'y la pagina 4 dice sin dato en el despues' ((Panel-De $y.P4 'cobertura').Contains('62,5 % ' + $Flecha + ' sin dato')) (Panel-De $y.P4 'cobertura')
  # sin ninguna: ni panel ni linea, y la linea del diagnostico es la de siempre
  $z = Cobertura-Con $c.E 'cob-ninguna' $null $null
  Comprueba 'sin ficheros de cobertura no hay panel en las paginas 2 y 4 ni linea en la portada' ((Panel-De $z.P2 'cobertura') -eq '' -and (Panel-De $z.P4 'cobertura') -eq '' -and (Linea-Cobertura $z.I) -eq '')
  Comprueba 'y Que ha hecho el script no cuenta cobertura' ($z.I -notmatch 'cobertura: ')
  # un 0 % medido si se pinta; un 100 %, sin coma
  $w = Cobertura-Con $c.E 'cob-cero-cien' (Cob 0 0 8) (Cob 100 8 8)
  $b2 = Panel-De $w.P2 'cobertura'
  Comprueba 'un 0 % medido se pinta como 0 %, con 0 de 8 lineas y por debajo' ($b2.Contains('0 %') -and $b2 -match '0 de 8 l.neas' -and $b2.Contains('por debajo') -and $b2.Contains('--v:0')) $b2
  Comprueba 'un 100 % sale 100 % y cumple' ((Linea-Cobertura $w.I).Contains('100 %') -and (Linea-Cobertura $w.I) -notmatch '100,' -and (Linea-Cobertura $w.I) -notmatch 'por debajo') (Linea-Cobertura $w.I)
  Comprueba 'pagina 4: 0 % -> 100 %' ((Panel-De $w.P4 'cobertura').Contains('Cobertura: 0 % ' + $Flecha + ' 100 %'))
  foreach ($par in @(@('2-problemas.html', $x.P2), @('4-correcciones.html', $x.P4), @('index.html', $x.I))) {
    Comprueba "$($par[0]) : sin JavaScript ni nada externo" ($par[1] -notmatch '(?i)<script' -and $par[1] -notmatch 'https?://' -and $par[1] -notmatch '<link|<img|@import')
  }
}

$Pruebas['123 tope de Maven: cobertura: si el Maven de JaCoCo se pasa del tope (MinutosMaven de ajustes.json), sin medir con el mensaje y migracion sale con 0'] = {
  $e = Nuevo-Escenario 'cob-tope' @('Clase1') @{ MvnExe = (Join-Path $falsos 'mvn-dormido.ps1'); MinutosMaven = 0.05 }
  $carpPids = Join-Path $e.Raiz 'pids'
  $reloj = [System.Diagnostics.Stopwatch]::StartNew()
  $r = Con-Entorno @{ RESCATE_MVN_CUELGA = 'jacoco-maven-plugin'; RESCATE_MVN_PIDS = $carpPids; RESCATE_MVN_SEGUNDOS = 120 } { Migra $e (Basicos $e) }
  $seg = $reloj.Elapsed.TotalSeconds
  Igual 'sale con 0' 0 $r.Codigo
  $c = Cobertura-De $e 'antes'
  Comprueba 'hay cobertura-antes.json' ($null -ne $c) (Cola $r.Salida)
  if ($null -eq $c) { return }
  Igual 'medida false' 'False' "$($c.medida)"
  Comprueba 'porcentaje, cubiertas y total nulos' (($null -eq $c.porcentaje) -and ($null -eq $c.cubiertas) -and ($null -eq $c.total)) ($c | ConvertTo-Json -Compress)
  $motivo = "$($c.motivo)"
  Comprueba 'el motivo es el mensaje del tope (0.05: manda el ajustes.json)' ($motivo.StartsWith('Maven se ha pasado del tope de 0.05 min y se ha parado (Maven (cobertura)). Registro: ')) $motivo
  $reg = [regex]::Match($motivo, 'Registro: (\S+)\.(\s|$)').Groups[1].Value
  Comprueba 'su registro es registros/cobertura-antes.log y existe' ($reg.Replace('\', '/').EndsWith('registros/cobertura-antes.log') -and (Test-Path -LiteralPath $reg)) $motivo
  $b = Panel-De (Pagina $e.Out '2-problemas.html') 'cobertura'
  Comprueba 'la pagina 2 dice no se ha podido medir y el motivo (el del tope)' ($b.Contains('no se ha podido medir: ' + (Html $motivo)) -and $b.Contains('no se ha podido medir: Maven se ha pasado del tope de 0.05 min')) $b
  Comprueba 'y no pinta ningun porcentaje' ($b -notmatch '\d\s*%') $b
  Comprueba-Tope $carpPids $seg 60 $reg
}

$Pruebas['87 dudas de job: las clases que no caben en la redaccion no van a dudas ni a la pagina de negocio; salen en la portada con su job'] = {
  $e = Escenario-Dos 'fuera' @() @{ CaracteresPorTarea = 650 }
  $r = Migra $e (Basicos $e) $GuionBase
  Igual 'sale con 0' 0 $r.Codigo
  $t = @(Tareas $e 'ficha-job' | Where-Object { $_.entradas.job -eq 'cargaJob' })[0]
  Comprueba 'hay tarea de ficha de job de cargaJob' ($null -ne $t) (Cola $r.Salida)
  if ($null -eq $t) { return }
  $fuera = @($t.entradas.fuera)
  Comprueba 'el escenario deja clases fuera del prompt (y no todas)' ($fuera.Count -ge 1 -and $t.estado -eq 'hecha') "fuera: $($fuera -join ', '), estado $($t.estado)"
  if ($fuera.Count -eq 0) { return }
  $j = Job-De $e 'cargaJob'
  $dudas = @($j.dudas) -join ' | '
  foreach ($c in $fuera) { Comprueba "datos/jobs/cargaJob.json: dudas no lleva $c" (-not $dudas.Contains($c)) $dudas }
  Comprueba 'dudas no dice nada de las clases que no caben' ($dudas -notmatch 'No caben') $dudas
  Igual 'la ficha del job guarda las clases en su campo fuera' ($fuera -join ',') (@($j.fuera) -join ',')
  $o = Pagina $e.Out '1-batch-original.html'
  # los nombres de clase de las citas (la ruta del fichero de cada dato) siguen saliendo: es otra cosa; la duda ya no
  Comprueba '1-batch-original.html no lleva la duda de las clases que no caben' ($o -notmatch 'No caben en la redacci') ($o.Length)
  Comprueba '1-batch-original.html no lleva la lista de esas clases' (-not $o.Contains($fuera -join ', '))
  $toca = Toca-De (Pagina $e.Out 'index.html')
  $g = [regex]::Match($toca, '(?s)<h3>Datos con nombres de clase \(\d+\)</h3>.*?</div>').Value
  Comprueba 'la portada tiene el grupo de datos con nombres de clase' ($g.Length -gt 0) $toca
  Comprueba 'el grupo lleva el job y la lista de clases' ($g.Contains('cargaJob') -and $g.Contains($fuera -join ', ')) $g
  Comprueba 'y dice que son las que no caben en la redaccion' ($g -match 'No caben en la redacci.n') $g
  Comprueba 'las clases no salen en el grupo de dudas de la portada' ($toca -notmatch 'Dudas de las fichas de job') $toca
}

# ============================ E: EL ORIGINAL FRENTE AL MIGRADO ============================
$Pruebas['88 consola de la correccion: las lineas del motor salen por la consola mientras corre, antes de la linea final, y el registro sigue entero'] = {
  $e = Nuevo-Escenario 'consola-correccion' @('Clase1')
  $o = Orden-Base
  $o.salida = @('LINEA-VIVA-UNO del motor', 'LINEA-VIVA-DOS del motor')
  $r = Migra-Motor $e $o (Corrige $e)
  Igual 'sale con 0' 0 $r.Codigo
  $a = $r.Salida.IndexOf('LINEA-VIVA-UNO')
  $b = $r.Salida.IndexOf('LINEA-VIVA-DOS')
  $fin = $r.Salida.IndexOf('commits de arreglo')
  Comprueba 'la consola lleva las dos lineas del motor, en orden' ($a -ge 0 -and $b -gt $a) (Cola $r.Salida)
  Comprueba 'y salen antes de la linea final de la correccion' ($b -ge 0 -and $fin -gt $b) (Cola $r.Salida)
  $log = Lee $e.Out 'registros/correccion.log'
  Comprueba 'registros/correccion.log sigue llevando las lineas del motor, sin colores' ($log -match 'LINEA-VIVA-UNO' -and $log -match 'LINEA-VIVA-DOS' -and $log -notmatch '\x1b\[') $log
}

$Pruebas['89 correccion: al acabar el motor se guarda estado.json, y actualizado cuenta la correccion entera'] = {
  $e = Nuevo-Escenario 'estado-correccion' @('Clase1')
  $r = Migra-Motor $e (Orden-Base) (Corrige $e) (Sistema-Motor-Lento)
  Igual 'sale con 0' 0 $r.Codigo
  $s = Estado $e
  $fin = (Get-Item -LiteralPath (Get-Ruta $e.Out 'registros/correccion.log')).LastWriteTime
  $act = [datetime]$s.actualizado
  Comprueba 'actualizado no es anterior al final del motor (el registro de la correccion se escribe al acabar)' ($act -ge $fin.AddSeconds(-1)) "actualizado $($s.actualizado), registro $($fin.ToString('s'))"
}

# ====================== E: EL ORIGINAL FRENTE AL MIGRADO ======================
# Una clase del migrado: 4 lineas que acaban en ; (la 5, la 6, la 9 y la 10).
function Clase-Migrada([string]$Nombre) {
  return "package com.acme.life;`n`n/** Clase $Nombre migrada. */`npublic class $Nombre {`n    private int valor = 1;`n    private int tope = 2;`n`n    public int dobla(int x) {`n        int r = x * 2;`n        return r;`n    }`n}`n"
}

# Clases con esos nombres en el repo migrado (antes de la primera corrida: el worktree sale de el).
function Migrado-Con($E, [string[]]$Nombres) {
  foreach ($n in $Nombres) { Escribe $E.Migrado "src/main/java/com/acme/life/$n.java" (Clase-Migrada $n) }
  [void](GitEn $E.Migrado @('add', '-A'))
  [void](GitEn $E.Migrado @('commit', '-q', '-m', 'clases migradas'))
}

$script:CorridasComparar = @{}
# Una corrida entera del escenario de dos jobs con cuatro clases en el migrado (las otras salen sin pieza) y ese guion de comparar.
# Auxiliar1 a 3 no se migran a proposito: un Auxiliar1.java migrado compartiria la palabra Auxiliar con los tres.
function Corrida-Comparar([string]$Guion = '') {
  if (-not $script:CorridasComparar.ContainsKey($Guion)) {
    $e = Escenario-Dos ('cmp' + $script:CorridasComparar.Count)
    Migrado-Con $e @('CargaReader', 'CargaValidator', 'InformeWriter', 'JobsConfig')
    $g = $GuionBase
    if ($Guion) { $g += ';' + $Guion }
    $script:CorridasComparar[$Guion] = [pscustomobject]@{ E = $e; R = (Migra $e (Basicos $e) $g) }
  }
  return $script:CorridasComparar[$Guion]
}

$RutaMigrado = 'src/main/java/com/acme/life'
$Punto = [string][char]0xB7
function Comparacion-De($E, $Ficha) { return (Lee-Json (Get-Ruta $E.Out ('datos/comparacion/' + $Ficha.id + '.json'))) }
function Grupo-Comp([string]$Html, [string]$Job) { return [regex]::Match($Html, '(?s)<section[^>]*id="comp-' + [regex]::Escape($Job) + '".*?</section>').Value }
function Ficha-De($E, [string]$Clase) { return @(Fichas $E | Where-Object { $_.fichero -like "*/$Clase.java" })[0] }

# Las cuentas de comparacion de un job del mapa, leidas de los datos/comparacion de $Salida, y su texto de cabecera.
function Cuentas-Job([string]$Salida, $Job) {
  $n = [ordered]@{ 'igual' = 0; 'distinto' = 0; 'falta' = 0; 'no-lo-se' = 0; 'sin-pieza' = 0 }
  foreach ($cl in @($Job.clases)) {
    $x = Lee-Json (Get-Ruta $Salida ('datos/comparacion/' + $cl.ficha + '.json'))
    if (-not $x) { continue }
    foreach ($d in @($x.datos)) { $n[[string]$d.estado]++ }
  }
  return $n
}
function Texto-Cuentas($N) {
  return ("igual $($N['igual']) $Punto distinto $($N['distinto']) $Punto falta $($N['falta']) $Punto no lo s$([char]0xE9) $($N['no-lo-se']) $Punto sin pieza $($N['sin-pieza'])")
}

$Pruebas['90 comparar: una tarea por ficha con datos, sin llamar por las clases sin pieza; cada datos/comparacion/<ficha>.json con un elemento por dato; la linea de consola, la fase despues de pruebas-pre y la pagina 3 con sus cuentas'] = {
  $c = Corrida-Comparar ''
  $e = $c.E
  Igual 'sale con 0' 0 $c.R.Codigo
  $fichas = @(Fichas $e | Where-Object { @($_.datos).Count -gt 0 })
  $t = Tareas $e 'comparar-pieza'
  Comprueba 'hay fichas con datos' ($fichas.Count -ge 5) "$($fichas.Count)"
  Igual 'una tarea por ficha con datos' $fichas.Count $t.Count
  Igual 'todas hechas' $t.Count (Cuenta-Estado $t 'hecha')
  Comprueba 'el id es comparar-<ficha> y la salida datos/comparacion/<ficha>.json' (@($t | Where-Object { $_.id -ceq ('comparar-' + $_.ficha) -and $_.salida -ceq ('datos/comparacion/' + $_.ficha + '.json') }).Count -eq $t.Count)
  $conPieza = @('CargaReader', 'CargaValidator', 'InformeWriter', 'JobsConfig')
  foreach ($f in $fichas) {
    $n = $f.clase
    $x = Comparacion-De $e $f
    Comprueba "$n : existe su datos/comparacion" ($null -ne $x)
    if ($null -eq $x) { continue }
    Igual "$n : ficha, clase y fichero original" "$($f.id)|$($f.clase)|$($f.fichero)" "$($x.ficha)|$($x.clase)|$($x.ficheroOriginal)"
    Igual "$n : un elemento por dato, en orden" ((0..(@($f.datos).Count - 1)) -join ',') (@($x.datos | ForEach-Object { $_.dato }) -join ',')
    if ($conPieza -contains $n) {
      Igual "$n : migrado = el fichero del mismo nombre" "$RutaMigrado/$n.java" (@($x.migrado) -join ',')
      Comprueba "$n : todos igual, probados, con fichero, linea y cita del migrado" (@($x.datos | Where-Object { $_.estado -ceq 'igual' -and $_.probado -eq $true -and $_.fichero -ceq "$RutaMigrado/$n.java" -and $_.linea -ge 1 -and $_.cita }).Count -eq @($f.datos).Count) (ConvertTo-Json -InputObject $x -Depth 5 -Compress)
    }
    else {
      Igual "$n : sin ningun fichero del migrado" 0 @($x.migrado).Count
      Comprueba "$n : todos sin-pieza, sin cita" (@($x.datos | Where-Object { $_.estado -ceq 'sin-pieza' -and -not $_.cita -and -not $_.fichero }).Count -eq @($f.datos).Count) (ConvertTo-Json -InputObject $x -Depth 5 -Compress)
    }
  }
  $ll = Llamadas-De (Llamadas $e.Wt) 'comparar-'
  Igual 'solo se llama a la IA por las cuatro clases con pieza' 4 $ll.Count
  Comprueba 'cada llamada lee el original (--add-dir) con esfuerzo de lectura' (@($ll | Where-Object { $_.flags -match '--add-dir=\S*life-java8' -and $_.flags -match '--effort=medium' }).Count -eq 4) (($ll | ForEach-Object { $_.flags }) -join ' | ')
  $p = Prompt-De $e (@($t | Where-Object { $_.entradas.clase -ceq 'CargaReader' })[0])
  $reader = Ficha-De $e 'CargaReader'
  Comprueba 'el prompt lleva el tipo, los ficheros del migrado y un dato numerado por cada dato de la ficha' ($p -match '(?m)^TIPO: comparar-pieza$' -and $p -match "(?m)^MIGRADO: $RutaMigrado/CargaReader\.java$" -and [regex]::Matches($p, '(?m)^\d+\. \[').Count -eq @($reader.datos).Count) $p
  Igual 'la estado.json acaba en hecha' 'hecha' (Estado $e).fase
  Igual 'el worktree queda limpio tras la fase' '' (GitEn $e.Wt @('status', '--porcelain'))
  $sal = $c.R.Salida
  $pre = $sal.IndexOf('Pruebas en pre:')
  $cmp = $sal.IndexOf('Comparacion con el original:')
  Comprueba 'la consola lleva la linea de comparar despues de la de pruebas en pre' ($pre -ge 0 -and $cmp -gt $pre) (Cola $sal)
  $linea = [regex]::Match($sal, 'Comparacion con el original: [^\r\n]*').Value
  $iguales = 0; $sinPieza = 0
  foreach ($f in $fichas) { foreach ($d in @((Comparacion-De $e $f).datos)) { if ($d.estado -ceq 'igual') { $iguales++ } else { $sinPieza++ } } }
  Igual 'la linea cuenta las clases y los datos de cada estado' "Comparacion con el original: $($fichas.Count) clases comparadas. Datos: $iguales igual, 0 distinto, 0 falta, 0 no lo se, $sinPieza sin pieza." $linea
  $mapa = Mapa $e
  $pg = Pagina $e.Out '3-original-vs-migrado.html'
  Comprueba 'la pagina 3 existe con un solo h1' ($pg.Length -gt 0 -and [regex]::Matches($pg, '<h1[ >]').Count -eq 1)
  foreach ($j in @($mapa.jobs)) {
    $g = Grupo-Comp $pg $j.job
    Comprueba "$($j.job) : tiene su grupo en la pagina 3" ($g.Length -gt 0)
    if (-not $g) { continue }
    $cab = Texto-Cuentas (Cuentas-Job $e.Out $j)
    Comprueba "$($j.job) : la cabecera dice las cuentas ($cab)" ($g.Contains($cab)) $g
  }
  $orden = @($mapa.jobs | ForEach-Object { $pg.IndexOf('id="comp-' + $_.job + '"') })
  Comprueba 'los jobs salen en el orden del mapa' ($orden[0] -ge 0 -and $orden[0] -lt $orden[1]) ($orden -join ' ')
}

$Pruebas['91 comparar: eleccion de ficheros del migrado (mismo nombre; si no, por palabras con 3 como mucho; sin ninguno, sin-pieza y sin llamada)'] = {
  $e = Nuevo-Escenario 'cmp-eleccion' @('CargaReader', 'InformeWriter', 'Suelta', 'ProcesoTope')
  Migrado-Con $e @('LectorCarga', 'CargaFichero', 'InformeWriter', 'TopeProceso', 'ProcesoDos', 'ProcesoTres', 'ProcesoUno')
  $r = Migra $e (Basicos $e)
  Igual 'sale con 0' 0 $r.Codigo
  $t = Tareas $e 'comparar-pieza'
  Igual 'cuatro tareas' 4 $t.Count
  $reader = @($t | Where-Object { $_.entradas.clase -ceq 'CargaReader' })[0]
  $writer = @($t | Where-Object { $_.entradas.clase -ceq 'InformeWriter' })[0]
  $suelta = @($t | Where-Object { $_.entradas.clase -ceq 'Suelta' })[0]
  $tope = @($t | Where-Object { $_.entradas.clase -ceq 'ProcesoTope' })[0]
  Igual 'CargaReader: sin el mismo nombre, salen los dos que comparten Carga (por ruta)' (("CargaFichero", "LectorCarga" | ForEach-Object { "$RutaMigrado/$_.java" }) -join ',') (@($reader.entradas.migrado) -join ',')
  Igual 'InformeWriter: con el mismo nombre, solo ese' "$RutaMigrado/InformeWriter.java" (@($writer.entradas.migrado) -join ',')
  Igual 'ProcesoTope: tres como mucho, primero el que comparte dos palabras y despues por ruta' (("TopeProceso", "ProcesoDos", "ProcesoTres" | ForEach-Object { "$RutaMigrado/$_.java" }) -join ',') (@($tope.entradas.migrado) -join ',')
  Igual 'Suelta: sin nada en comun, ninguno' 0 @($suelta.entradas.migrado).Count
  Igual 'Suelta: hecha sin llamar a la IA' 'hecha' $suelta.estado
  Igual 'Suelta: todos sus datos sin-pieza' @($suelta.resultado.comparacion).Count (@($suelta.resultado.comparacion | Where-Object { $_.estado -ceq 'sin-pieza' }).Count)
  $ll = Llamadas-De (Llamadas $e.Wt) 'comparar-'
  Igual 'tres llamadas (CargaReader, InformeWriter y ProcesoTope), ninguna por Suelta' 3 $ll.Count
  Comprueba 'ninguna llamada es de Suelta' (@($ll | Where-Object { $_.id -ceq $suelta.id }).Count -eq 0)
  foreach ($k in @($reader, $tope)) {
    $p = Prompt-De $e $k
    Comprueba "$($k.entradas.clase) : el prompt lista sus ficheros del migrado, uno por linea y en orden" ((([regex]::Matches($p, '(?m)^MIGRADO: (.+?)\s*$') | ForEach-Object { $_.Groups[1].Value }) -join ',') -ceq (@($k.entradas.migrado) -join ',')) $p
  }
}

$Pruebas['92 comparar: citas inventadas, un dato que falta, un fichero que no le dieron y un distinto sin nota se rechazan, con reintento y el motivo; atascada y a la portada'] = {
  $c = Corrida-Comparar 'comparar-inventada:^comparar-pieza:CargaReader$;comparar-falta-dato:^comparar-pieza:CargaValidator$;comparar-fichero-ajeno:^comparar-pieza:InformeWriter$;comparar-sin-nota:^comparar-pieza:JobsConfig$'
  $e = $c.E
  Igual 'sale con 0' 0 $c.R.Codigo
  $t = Tareas $e 'comparar-pieza'
  $esperado = @(
    @('CargaReader', 'Mas de la mitad de las citas'),
    @('CargaValidator', 'Pero faltan'),
    @('InformeWriter', 'NoMeHanDado\.java'),
    @('JobsConfig', 'comparacion\[0\]\.nota')
  )
  foreach ($x in $esperado) {
    $n = $x[0]
    $k = @($t | Where-Object { $_.entradas.clase -ceq $n })[0]
    Igual "$n : atascada" 'atascada' $k.estado
    Igual "$n : dos intentos" 2 $k.intentos
    Comprueba "$n : el motivo dice por que ($($x[1]))" ($k.motivo -match $x[1]) $k.motivo
    $ll = Llamadas-De (Llamadas $e.Wt) $k.id
    Comprueba "$n : el reintento lleva la correccion con el motivo y esfuerzo high" ($ll.Count -eq 2 -and $ll[1].correccion -eq 'True' -and $ll[0].correccion -eq 'False' -and $ll[1].flags -match '--effort=high' -and (Prompt-De $e $k) -match ('(?s)## CORRECCI.*' + $x[1])) (($ll | ForEach-Object { $_.correccion }) -join ' ')
    Comprueba "$n : no deja datos/comparacion" (-not (Test-Path -LiteralPath (Get-Ruta $e.Out ('datos/comparacion/' + $k.ficha + '.json'))))
  }
  Igual 'las otras cuatro clases con datos siguen hechas' 4 (Cuenta-Estado $t 'hecha')
  Comprueba 'la fase termina: estado hecha' ((Estado $e).fase -eq 'hecha')
  $toca = Toca-De (Pagina $e.Out 'index.html')
  Comprueba 'la portada lista las cuatro tareas atascadas de comparar' ($toca -match 'Tareas atascadas \(4\)' -and ([regex]::Matches($toca, 'comparar-clase-[0-9a-f]{8}').Count -eq 4)) $toca
  Comprueba 'la pagina 3 se monta igual' ((Pagina $e.Out '3-original-vs-migrado.html').Length -gt 0)
}

$Pruebas['93 comparar: un dato distinto sale primero en su job, con las dos citas y la nota, y la portada lo lista en Diferencias con el original'] = {
  $c = Corrida-Comparar 'comparar-distinto:^comparar-pieza:CargaReader$'
  $e = $c.E
  Igual 'sale con 0' 0 $c.R.Codigo
  $f = Ficha-De $e 'CargaReader'
  $x = Comparacion-De $e $f
  $d0 = $x.datos[0]
  Comprueba 'el primer dato queda distinto, con nota y la cita encontrada en el migrado' ($d0.estado -ceq 'distinto' -and $d0.nota -match 'constante' -and $d0.probado -eq $true -and $d0.cita -and $d0.fichero -ceq "$RutaMigrado/CargaReader.java") (ConvertTo-Json -InputObject $d0 -Compress)
  $h = $f.datos[0]
  $g = Grupo-Comp (Pagina $e.Out '3-original-vs-migrado.html') 'cargaJob'
  $iDist = $g.IndexOf((Html $d0.nota))
  $iDet = $g.IndexOf('<details')
  Comprueba 'en su job, el distinto sale antes de los iguales plegados' ($iDist -ge 0 -and $iDet -gt $iDist) $g
  $fila = [regex]::Match($g, '(?s)<li class="fila s-error">.*?</li>').Value
  Comprueba 'la fila lleva el texto del dato, el original (fichero:linea y cita), el migrado (fichero:linea y cita) y la nota' ($fila.Contains((Html $h.texto)) -and $fila.Contains((Html "$($f.fichero):$($h.linea)")) -and $fila.Contains((Html $h.cita)) -and $fila.Contains((Html "$($d0.fichero):$($d0.linea)")) -and $fila.Contains((Html $d0.cita)) -and $fila.Contains((Html $d0.nota))) $fila
  Comprueba 'y dice Distinto, con la etiqueta de leido por la IA con prueba' ($fila -match 'Distinto' -and $fila -match 'Le.do por la IA, con prueba') $fila
  Comprueba 'la cabecera del job cuenta 1 distinto' ($g -match ('distinto 1 ' + $Punto))
  $toca = Toca-De (Pagina $e.Out 'index.html')
  $gd = [regex]::Match($toca, '(?s)<h3>Diferencias con el original \(1\)</h3>.*?</div>').Value
  Comprueba 'la portada tiene el grupo Diferencias con el original (1)' ($gd.Length -gt 0) $toca
  Comprueba 'con el job, la clase, el texto del dato y la nota' ($gd.Contains('cargaJob') -and $gd.Contains('CargaReader') -and $gd.Contains((Html $h.texto)) -and $gd.Contains((Html $d0.nota))) $gd
  Comprueba 'sin ningun distinto ni falta (la corrida normal) la portada no lo lleva' ((Toca-De (Pagina (Corrida-Comparar '').E.Out 'index.html')) -notmatch 'Diferencias con el original')
}

$Pruebas['94 comparar: relanzar no repite ninguna tarea hecha aunque el worktree tenga cambios sin commit (un fichero tocado y otro movido): la huella es el commit, no los ficheros'] = {
  $e = Escenario-Dos 'cmp-relanza'
  Migrado-Con $e @('CargaReader', 'CargaValidator', 'InformeWriter')
  $r = Migra $e (Basicos $e) $GuionBase
  Igual 'la primera sale con 0' 0 $r.Codigo
  $antes = @(Llamadas-De (Llamadas $e.Wt) 'comparar-')
  Igual 'la primera vez, tres llamadas de comparar' 3 $antes.Count
  $t0 = Tareas $e 'comparar-pieza'
  Escribe $e.Wt "$RutaMigrado/CargaReader.java" ((Lee $e.Wt "$RutaMigrado/CargaReader.java") + "// cambiado despues`n")
  [void](GitEn $e.Wt @('mv', "$RutaMigrado/InformeWriter.java", "$RutaMigrado/InformeWriterMovido.java"))
  [void](GitEn $e.Wt @('add', '-A'))
  $r = Migra $e (Basicos $e) $GuionBase
  Igual 'la segunda sale con 0' 0 $r.Codigo
  $despues = @(Llamadas-De (Llamadas $e.Wt) 'comparar-')
  Igual 'la segunda vez no hay ninguna llamada mas de comparar' 3 $despues.Count
  $t1 = Tareas $e 'comparar-pieza'
  Igual 'las tareas siguen hechas' $t1.Count (Cuenta-Estado $t1 'hecha')
  Igual 'y con los mismos ficheros del migrado de la primera vez' ((@($t0 | ForEach-Object { @($_.entradas.migrado) -join ',' })) -join ' | ') ((@($t1 | ForEach-Object { @($_.entradas.migrado) -join ',' })) -join ' | ')
  Comprueba 'los datos/comparacion siguen' (@(Get-ChildItem -LiteralPath (Get-Ruta $e.Out 'datos/comparacion') -File).Count -eq $t1.Count)
}

$Pruebas['95 comparar: la lectura no toca codigo: si lo toca se deshace, la tarea se atasca y el worktree queda limpio'] = {
  $e = Nuevo-Escenario 'cmp-toca' @('Primera', 'Segunda')
  Migrado-Con $e @('Primera')
  $r = Migra $e (Basicos $e) 'toca-codigo:^comparar-pieza:Primera$'
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'el worktree queda limpio' '' (GitEn $e.Wt @('status', '--porcelain'))
  Igual 'el fichero del migrado sigue como estaba' (Lee $e.Migrado "$RutaMigrado/Primera.java") (Lee $e.Wt "$RutaMigrado/Primera.java")
  $t = Tareas $e 'comparar-pieza'
  $c1 = @($t | Where-Object { $_.entradas.clase -ceq 'Primera' })[0]
  $c2 = @($t | Where-Object { $_.entradas.clase -ceq 'Segunda' })[0]
  Igual 'Primera: atascada' 'atascada' $c1.estado
  Comprueba 'Primera: el motivo dice que la lectura toco ficheros' ($c1.motivo -match 'toco') $c1.motivo
  Igual 'Segunda (sin pieza): hecha' 'hecha' $c2.estado
}

# Datos de mentira para la pagina 3 y la portada: tres clases (A en cargaJob, B en los dos jobs, C en informeJob) con datos en todos los estados.
$script:Mentira = $null
function Comp-Fake($Ficha, [string[]]$Estados, [string]$Nota, [string]$Cita) {
  $n = @($Ficha.datos).Count
  $ds = @()
  $fichero = ''
  if ($Estados[0] -cne 'sin-pieza') { $fichero = "$RutaMigrado/$($Ficha.clase).java" }
  for ($i = 0; $i -lt $n; $i++) {
    $est = $Estados[[Math]::Min($i, $Estados.Count - 1)]
    $d = [ordered]@{ dato = $i; estado = $est; fichero = ''; linea = 0; cita = ''; nota = ''; probado = $false }
    if ($est -ceq 'igual' -or $est -ceq 'distinto') { $d.fichero = $fichero; $d.linea = 5 + $i; $d.cita = "$Cita $i"; $d.probado = ($i -ne ($n - 1)) }
    if ($est -ceq 'distinto' -or $est -ceq 'no-lo-se') { $d.nota = "$Nota $i" }
    $ds += $d
  }
  $mig = @()
  if ($fichero) { $mig = @($fichero) }
  return [ordered]@{ ficha = $Ficha.id; clase = $Ficha.clase; ficheroOriginal = $Ficha.fichero; migrado = $mig; datos = $ds }
}

function Comparar-Mentira {
  if ($script:Mentira) { return $script:Mentira }
  $c = Corrida-Comparar ''
  $s = Copia-Salida $c.E 'comp-mentira'
  $mapa = Lee-Json (Get-Ruta $s 'datos/mapa.json')
  $todas = @($mapa.jobs | ForEach-Object { @($_.clases) })
  $a = @($todas | Where-Object { $_.clase -ceq 'CargaReader' })[0]
  $b = @($todas | Where-Object { $_.clase -ceq 'CargaValidator' })[0]
  $d = @($todas | Where-Object { $_.clase -ceq 'InformeWriter' })[0]
  $x1 = @($todas | Where-Object { $_.clase -ceq 'Auxiliar1' })[0]
  (Del-Job $mapa 'cargaJob').clases = @($a, $b)
  (Del-Job $mapa 'informeJob').clases = @($b, $d, $x1)
  Guarda-Json (Get-Ruta $s 'datos/mapa.json') $mapa
  $q = [string][char]39
  $fa = Lee-Json (Get-Ruta $s ('datos/fichas/' + $a.ficha + '.json'))
  $fa.datos[0].texto = 'Texto <b>negrita</b> & "comillas" ' + $q + 'simples' + $q
  $fa.datos[0].cita = 'x < y & "z"'
  Guarda-Json (Get-Ruta $s ('datos/fichas/' + $a.ficha + '.json')) $fa
  $fb = Lee-Json (Get-Ruta $s ('datos/fichas/' + $b.ficha + '.json'))
  $fd = Lee-Json (Get-Ruta $s ('datos/fichas/' + $d.ficha + '.json'))
  $fx = Lee-Json (Get-Ruta $s ('datos/fichas/' + $x1.ficha + '.json'))
  $carpeta = Get-Ruta $s 'datos/comparacion'
  if (Test-Path -LiteralPath $carpeta) { Remove-Item -LiteralPath $carpeta -Recurse -Force }
  [void](New-Item -ItemType Directory -Path $carpeta -Force)
  $nota = '<script>alert(1)</script> & "x" nota'
  $cita = 'if (a < b && c == "x") {'
  Guarda-Json (Join-Path $carpeta ($a.ficha + '.json')) (Comp-Fake $fa @('distinto', 'falta', 'igual') $nota $cita)
  Guarda-Json (Join-Path $carpeta ($b.ficha + '.json')) (Comp-Fake $fb @('no-lo-se', 'igual', 'falta') 'nota de B' $cita)
  Guarda-Json (Join-Path $carpeta ($d.ficha + '.json')) (Comp-Fake $fd @('sin-pieza') '' '')
  Guarda-Json (Join-Path $carpeta ($x1.ficha + '.json')) (Comp-Fake $fx @('falta') '' '')
  $g = Genera-Informes $s
  Comprueba 'comparar con datos de mentira: Write-Informes sale bien' ($g.Codigo -eq 0 -and $g.Salida -match 'INFORMES-OK') (Cola $g.Salida)
  $script:Mentira = [pscustomobject]@{ Dir = $s; E = $c.E; Mapa = $mapa; A = $a; B = $b; D = $d; FA = $fa; Nota = $nota; Cita = $cita; P3 = (Pagina $s '3-original-vs-migrado.html'); I = (Pagina $s 'index.html') }
  return $script:Mentira
}

$Pruebas['96 pagina 3 con datos de mentira: orden de estados, etiquetas, iguales plegados, una clase en dos jobs, todo escapado, un solo h1 y sin datos dice que no ha terminado'] = {
  $m = Comparar-Mentira
  $p = $m.P3
  Igual 'un solo h1' 1 ([regex]::Matches($p, '<h1[ >]').Count)
  Comprueba 'sin JavaScript ni nada externo' ($p -notmatch '(?i)<script|<img|<iframe|<link|https?://')
  $g1 = Grupo-Comp $p 'cargaJob'
  $g2 = Grupo-Comp $p 'informeJob'
  Comprueba 'los dos jobs, en su orden' ($g1.Length -gt 0 -and $g2.Length -gt 0 -and $p.IndexOf($g1) -lt $p.IndexOf($g2))
  foreach ($par in @(@('cargaJob', $g1), @('informeJob', $g2))) {
    $j = Del-Job $m.Mapa $par[0]
    $cab = Texto-Cuentas (Cuentas-Job $m.Dir $j)
    Comprueba "$($par[0]) : cabecera con las cuentas ($cab)" ($par[1].Contains($cab)) $par[1]
  }
  $iDis = $g1.IndexOf('Distinto</span>'); $iFal = $g1.IndexOf('Falta</span>'); $iNo = $g1.IndexOf('No lo s'); $iDet = $g1.IndexOf('<details')
  Comprueba 'cargaJob: primero distinto, despues falta, despues no lo se y al final los iguales plegados' ($iDis -ge 0 -and $iFal -gt $iDis -and $iNo -gt $iFal -and $iDet -gt $iNo) "$iDis $iFal $iNo $iDet"
  Comprueba 'los iguales van en un solo details con su cuenta' ([regex]::Matches($g1, '<details').Count -eq 1 -and $g1 -match '<summary>\d+ datos iguales</summary>') $g1
  $nIg = (Cuentas-Job $m.Dir (Del-Job $m.Mapa 'cargaJob'))['igual']
  Comprueba 'y esa cuenta es la de la cabecera' ($g1 -match "<summary>$nIg datos iguales</summary>")
  Comprueba 'informeJob: un solo igual, en su details, en singular' ($g2 -match '<summary>1 dato igual</summary>')
  Comprueba 'etiquetas: Leido por la IA con prueba, Sin comprobar y Medido' ($g1 -match 'Le.do por la IA, con prueba' -and $g1 -match 'Sin comprobar' -and $g2 -match 'Medido')
  $fDis = [regex]::Match($g1, '(?s)<li class="fila s-error">.*?</li>').Value
  Comprueba 'el distinto lleva la etiqueta de con prueba y su nota' ($fDis -match 'Le.do por la IA, con prueba' -and $fDis -match 'nota') $fDis
  $fFal = [regex]::Match($g1, '(?s)<li class="fila s-aviso">(?:(?!</li>).)*Falta</span>.*?</li>').Value
  Comprueba 'la falta lleva Sin comprobar y no tiene migrado' ($fFal -match 'Sin comprobar' -and $fFal -notmatch 'Migrado:') $fFal
  $fSin = [regex]::Match($g2, '(?s)<li class="fila s-aviso">(?:(?!</li>).)*Sin pieza</span>.*?</li>').Value
  Comprueba 'el sin pieza lleva Medido' ($fSin -match 'Medido') $fSin
  $ultimoIgual = [regex]::Matches($g1, '(?s)<details.*?</details>').Value
  Comprueba 'el ultimo dato igual de la clase A no tiene su cita encontrada: sale como Sin comprobar dentro de los iguales' ($ultimoIgual -match 'Sin comprobar') $ultimoIgual
  Comprueba 'una clase en dos jobs sale en los dos (la nota de B, dos veces)' ([regex]::Matches($p, 'nota de B 0').Count -eq 2) ([regex]::Matches($p, 'nota de B 0').Count)
  Comprueba 'la nota con script, & y comillas sale escapada' ($p.Contains((Html ($m.Nota + ' 0'))) -and $p -notmatch '<script')
  Comprueba 'la cita del migrado con < y & y comillas sale escapada' ($p.Contains((Html ($m.Cita + ' 0'))))
  Comprueba 'el texto del dato y la cita del original, tambien' ($p.Contains((Html $m.FA.datos[0].texto)) -and $p.Contains((Html 'x < y & "z"')))
  Comprueba 'la frase de arriba dice que son dos comparaciones y que la lectura de la IA va debajo' ($p -match 'Dos comparaciones del mismo batch' -and $p -match 'la lectura de la IA, dato a dato')
  # sin datos
  $c = Corrida-Comparar ''
  $s = Copia-Salida $c.E 'comp-sin-datos'
  if (Test-Path -LiteralPath (Get-Ruta $s 'datos/comparacion')) { Remove-Item -LiteralPath (Get-Ruta $s 'datos/comparacion') -Recurse -Force }
  $g = Genera-Informes $s
  Comprueba 'sin datos/comparacion: Write-Informes sale bien' ($g.Codigo -eq 0 -and $g.Salida -match 'INFORMES-OK') (Cola $g.Salida)
  $v = Pagina $s '3-original-vs-migrado.html'
  Comprueba 'la pagina dice que la fase comparar no ha terminado y no lleva grupos' ($v -match 'la fase comparar no ha terminado' -and $v -notmatch 'id="comp-') $v
  Igual 'y sigue con un solo h1' 1 ([regex]::Matches($v, '<h1[ >]').Count)
}

$Pruebas['97 portada y marco: navegacion a Original frente a migrado, Diferencias con el original (uno por dato distinto o falta, por job), la fase y los ficheros'] = {
  $m = Comparar-Mentira
  $i = $m.I
  $toca = Toca-De $i
  $gd = [regex]::Match($toca, '(?s)<h3>Diferencias con el original \(\d+\)</h3>.*?</div>').Value
  $a = Cuentas-Job $m.Dir (Del-Job $m.Mapa 'cargaJob')
  $b = Cuentas-Job $m.Dir (Del-Job $m.Mapa 'informeJob')
  $n = $a['distinto'] + $a['falta'] + $b['distinto'] + $b['falta']
  Comprueba "el grupo dice ($n)" ($gd -match "Diferencias con el original \($n\)") $toca
  Igual 'con un elemento por dato' $n ([regex]::Matches($gd, '<li>').Count)
  Comprueba 'cada uno lleva el job, la clase, el texto del dato y la nota' ($gd.Contains('cargaJob') -and $gd.Contains('informeJob') -and $gd.Contains('CargaReader') -and $gd.Contains('Auxiliar1') -and $gd.Contains((Html $m.FA.datos[0].texto)) -and $gd.Contains((Html ($m.Nota + ' 0')))) $gd
  Comprueba 'los sin pieza no salen: InformeWriter no esta' (-not $gd.Contains('InformeWriter'))
  $fases = [regex]::Match($i, '(?s)<ol class="fases">.*?</ol>').Value
  $lis = @([regex]::Matches($fases, '(?s)<li>.*?</li>') | ForEach-Object { $_.Value })
  $ip = @($lis | Where-Object { $_ -match 'Casos de las reglas sin caso' })[0]
  $ic = @($lis | Where-Object { $_ -match 'Comparaci.n con el original' })[0]
  $ir = @($lis | Where-Object { $_ -match 'Correcci.n del migrado' })[0]
  Comprueba 'Que ha hecho el script: la fase va entre los casos de las reglas sin caso (que siguen al guion de prueba) y la correccion' ($ic -and ([array]::IndexOf($lis, $ip) + 1) -eq [array]::IndexOf($lis, $ic) -and ([array]::IndexOf($lis, $ic) + 1) -eq [array]::IndexOf($lis, $ir)) $fases
  $nt = @(Tareas $m.E 'comparar-pieza').Count
  Comprueba 'con su cuenta de tareas' ($ic -match "hechas: $nt, atascadas: 0, pendientes: 0") $ic
  $f = [regex]::Match($i, '(?s)<ul class="ficheros">.*?</ul>').Value
  Comprueba 'Que es cada fichero: la pagina 3 (con enlace) y datos/comparacion' ($f.Contains('href="3-original-vs-migrado.html"') -and $f.Contains('datos/comparacion')) $f
  foreach ($par in @(@('index.html', $i), @('1-batch-original.html', (Pagina $m.Dir '1-batch-original.html')), @('2-problemas.html', (Pagina $m.Dir '2-problemas.html')), @('3-original-vs-migrado.html', $m.P3), @('4-correcciones.html', (Pagina $m.Dir '4-correcciones.html')))) {
    $h = $par[1]
    Comprueba "$($par[0]) : la navegacion lleva a Original frente a migrado" ($h -match 'href="3-original-vs-migrado\.html"' -and $h -match '>Original frente a migrado<')
    Igual "$($par[0]) : aria-current solo en su pagina" 1 ([regex]::Matches($h, 'aria-current="page"').Count)
    Comprueba "$($par[0]) : y es el de su enlace" ($h -match ('href="' + [regex]::Escape($par[0]) + '" aria-current="page"'))
  }
  $n = Nuevo-Escenario 'cmp-nada' @('Clase1')
  [void](Migra $n (Basicos $n))
  $t3 = Toca-De (Pagina $n.Out 'index.html')
  Comprueba 'sin nada que revisar, lo que te toca nombra tambien las diferencias con el original' ($t3 -match 'Nada que revisar' -and $t3 -match 'ninguna diferencia con el original') $t3
}

# ============================ PRUEBA EN PRE: LO QUE FALTABA POR COMPROBAR ============================
$Pruebas['98 prueba-pre: el guion tiene que ser del job de la tarea, con texto en cada campo y alguna referencia en cada caso'] = {
  $codigo = @'
$Fuentes = @('CargaReader') | ForEach-Object { [pscustomobject]@{ BaseName = $_ } }
$hechos = "clase-aaaaaaaa#0 [regla] Rechaza el recibo sin importe.`nclase-aaaaaaaa#1 [error] Si falla el envio, avisa."
function Caso([string]$Titulo, [string]$Entrada, [string]$Esperado, [string[]]$Refs) {
  return [ordered]@{ titulo = $Titulo; entrada = $Entrada; esperado = $Esperado; refs = $Refs }
}
function Guion($Job, $Casos, [string]$Preparar = 'Deja el fichero listo.', [string]$Comprobar = 'Mira el aviso.') {
  return [ordered]@{ job = $Job; preparar = @([ordered]@{ texto = $Preparar; refs = @() }); casos = @($Casos); comprobar = @([ordered]@{ texto = $Comprobar; refs = @() }) }
}
function Valida($Guion) {
  $dir = Join-Path '{{DIR}}' ('g' + [guid]::NewGuid().ToString('N').Substring(0, 6))
  [void](New-Item -ItemType Directory -Path (Join-Path $dir '.rescate/tareas') -Force)
  [System.IO.File]::WriteAllText((Join-Path $dir '.rescate/tareas/prueba-cargaJob.json'), (ConvertTo-Json -InputObject $Guion -Depth 8))
  $t = [pscustomobject]@{ id = 'prueba-cargaJob'; intentos = 0; entradas = [pscustomobject]@{ job = 'cargaJob'; datos = $hechos } }
  $r = Test-PruebaPre $t $dir
  if ($r.Ok) { return 'BIEN' }
  return ('MAL ' + $r.Motivo)
}
$bueno = Caso 'Sin importe' 'Un recibo sin importe.' 'Se rechaza.' @('clase-aaaaaaaa#0', 'clase-aaaaaaaa#1')
'G1=' + (Valida (Guion 'cargaJob' @($bueno)))
'G2=' + (Valida (Guion 'informeJob' @($bueno)))
'G3=' + (Valida (Guion 'cargaJob' @((Caso 'Sin refs' 'Algo.' 'Otra cosa.' @()), $bueno)))
'G4=' + (Valida (Guion 'cargaJob' @((Caso 'Esperado en blanco' 'Algo.' '   ' @('clase-aaaaaaaa#0')), $bueno)))
'G5=' + (Valida (Guion 'cargaJob' @($bueno) 'Deja el fichero listo.' ' '))
'G6=' + (Valida (Guion 'cargaJob' @($bueno) ''))
'FIN'
'@
  $codigo = $codigo.Replace('{{DIR}}', (Join-Path $Dir 'pre-guion'))
  $r = En-Biblioteca 'pre-guion' $codigo
  Igual 'el script de prueba sale con 0' 0 $r.Codigo
  $v = @{}
  foreach ($l in ($r.Salida -split "`n")) { if ($l -match '^(G\d)=(.*?)\r?$') { $v[$Matches[1]] = $Matches[2] } }
  Igual 'un guion con todo en regla vale' 'BIEN' $v['G1']
  Comprueba 'el guion que dice ser de otro job no vale y el motivo dice cual es el job' ($v['G2'] -match '^MAL' -and $v['G2'] -match "'cargaJob'") $v['G2']
  Comprueba 'un caso sin ninguna referencia no vale aunque otro caso cubra todo, y el motivo dice cual' ($v['G3'] -match '^MAL' -and $v['G3'] -match 'casos\[0\]\.refs' -and $v['G3'] -match 'al menos una') $v['G3']
  Comprueba 'un campo de un caso en blanco no vale y el motivo lo nombra' ($v['G4'] -match '^MAL' -and $v['G4'] -match 'casos\[0\]\.esperado') $v['G4']
  Comprueba 'el texto de comprobar en blanco, igual' ($v['G5'] -match '^MAL' -and $v['G5'] -match 'comprobar\[0\]\.texto') $v['G5']
  Comprueba 'el texto de preparar vacio, igual' ($v['G6'] -match '^MAL' -and $v['G6'] -match 'preparar\[0\]\.texto') $v['G6']
}

$Pruebas['99 prueba-pre: una tarea hecha solo se reutiliza si no cambian los hechos ni las variables que recibe'] = {
  $codigo = @'
$Datos = '{{DIR}}'
$mapa = [pscustomobject]@{ jobs = @([pscustomobject]@{ job = 'cargaJob'; clases = @([pscustomobject]@{ ficha = 'clase-aaaaaaaa' }) }) }
function Ficha([string]$Regla) {
  Write-Json (Join-Path $Datos 'fichas/clase-aaaaaaaa.json') ([ordered]@{ id = 'clase-aaaaaaaa'; clase = 'CargaReader'; datos = @([ordered]@{ tipo = 'regla'; texto = $Regla }) })
}
function Ahora {
  $t = @(Get-TareasPrueba $mapa $false)
  if ($t.Count -ne 1) { return ('TAREAS ' + $t.Count) }
  return $t[0].estado
}
function Da-Por-Hecha {
  $t = @(Get-TareasPrueba $mapa $false)[0]
  $t.estado = 'hecha'
  Save-Tarea $t
}
Ficha 'Rechaza el recibo sin importe.'
'A1=' + (Ahora)
Da-Por-Hecha
'A2=' + (Ahora)
Ficha 'Rechaza el recibo sin importe ni fecha.'
'A3=' + (Ahora)
Da-Por-Hecha
'A4=' + (Ahora)
Write-Json (Join-Path $Datos 'variables.json') @([ordered]@{ variable = 'CLAVE_BANCO'; porDefecto = $null; fichero = 'application.yml'; linea = 1 })
'A5=' + (Ahora)
Da-Por-Hecha
'A6=' + (Ahora)
'FIN'
'@
  $codigo = $codigo.Replace('{{DIR}}', (Join-Path $Dir 'pre-huella'))
  $r = En-Biblioteca 'pre-huella' $codigo
  Igual 'el script de prueba sale con 0' 0 $r.Codigo
  $v = @{}
  foreach ($l in ($r.Salida -split "`n")) { if ($l -match '^(A\d)=(.*?)\r?$') { $v[$Matches[1]] = $Matches[2] } }
  Igual 'una tarea nueva esta pendiente' 'pendiente' $v['A1']
  Igual 'hecha y con los mismos hechos, se reutiliza' 'hecha' $v['A2']
  Igual 'con otro texto en una regla, se vuelve a pedir' 'pendiente' $v['A3']
  Igual 'hecha otra vez, se reutiliza' 'hecha' $v['A4']
  Igual 'con otras variables, se vuelve a pedir' 'pendiente' $v['A5']
  Igual 'hecha otra vez, se reutiliza' 'hecha' $v['A6']
}

# ============================ PAGINAS: LO QUE FALTABA POR COMPROBAR ============================
$Pruebas['100 paginas: un dato o un paso sin cita encontrada sale como Sin comprobar y nunca como leido por la IA con prueba'] = {
  $c = Corrida-Dos $GuionBase
  $a = Articulo (Pagina $c.E.Out '1-batch-original.html') 'cargaJob'
  $corte = $a.IndexOf('id="pre-cargaJob"')
  Comprueba 'el job lleva sus datos y, despues, el bloque de la prueba en pre' ($corte -gt 0) (Cola $c.R.Salida)
  if ($corte -lt 0) { return }
  $datos = $a.Substring(0, $corte)
  $n = [regex]::Matches($datos, 'm m-ia').Count
  Comprueba 'con todo probado, sus datos y pasos salen como leidos por la IA y ninguno sin comprobar' ($n -gt 0 -and $datos -notmatch 'm m-sin') "$n"
  $s = Copia-Salida $c.E 'marca-sin'
  $ruta = Get-Ruta $s 'datos/jobs/cargaJob.json'
  $j = Lee-Json $ruta
  foreach ($h in (Elementos-De $j)) { $h.probado = $false }
  foreach ($p in @($j.pasos)) { $p.probado = $false }
  Guarda-Json $ruta $j
  # los pasos tambien citan datos de las fichas de clase
  foreach ($f in @(Get-ChildItem -LiteralPath (Get-Ruta $s 'datos/fichas') -File -Filter 'clase-*.json')) {
    $x = Lee-Json $f.FullName
    foreach ($d in @($x.datos)) { $d.probado = $false }
    Guarda-Json $f.FullName $x
  }
  $g = Genera-Informes $s
  Comprueba 'Write-Informes sale bien' ($g.Codigo -eq 0 -and $g.Salida -match 'INFORMES-OK') (Cola $g.Salida)
  $a = Articulo (Pagina $s '1-batch-original.html') 'cargaJob'
  $datos = $a.Substring(0, $a.IndexOf('id="pre-cargaJob"'))
  Igual 'sin cita probada, ninguno sale como leido por la IA' 0 ([regex]::Matches($datos, 'm m-ia').Count)
  Igual 'y los que salian como leidos salen ahora como sin comprobar' $n ([regex]::Matches($datos, 'm m-sin').Count)
}

$Pruebas['101 paginas: al acabar la lectura la portada dice que ha terminado, aunque no se corrija nada'] = {
  $c = Corrida-Dos $GuionBase
  $s = Estado $c.E
  Igual 'la fase acaba en hecha' 'hecha' $s.fase
  $g = Genera-Informes $c.E.Out
  Comprueba 'Write-Informes sale bien' ($g.Codigo -eq 0 -and $g.Salida -match 'INFORMES-OK') (Cola $g.Salida)
  $i = Pagina $c.E.Out 'index.html'
  Comprueba 'la portada dice que la pasada ha terminado, sin corregir' ($i -match 'La pasada ha terminado, sin corregir') (Cola $c.R.Salida)
  Comprueba 'y no que la pasada va por una fase' ($i -notmatch 'La pasada no ha terminado')
}

# ======================= E2: COMPARAR DESPUES DE CORREGIR Y LA PRUEBA EN LOCAL =======================
# N lineas de 10 o mas caracteres, todas distintas por el prefijo: 'String campoP1 = 1;' ...
function Campos([string]$P, [int]$N) { return ((1..$N | ForEach-Object { "String campo$P$_ = 1;" }) -join "`n") }

$Pruebas['102 (E2) mapa de movidos: renombrados de git, borrados con las lineas que fueron a otros ficheros (minimo 2, mas primero, orden ordinal), cabeceras falsas, sin cambios y git que falla'] = {
  $d = Join-Path $Dir 'mapa-git'
  if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force }
  [void](New-Item -ItemType Directory -Path $d -Force)
  $j = 'src/main/java/a'
  $b1 = 'String compartidaUno = 1;'
  $b2 = 'String compartidaDos = 2;'
  $menos = '-- marca uno aqui'
  $mas = '++ marca dos aqui'
  $e = @('String empateUno = 1;', 'String empateDos = 2;', 'String empateTres = 3;', 'String empateCuatro = 4;')
  Escribe $d "$j/Renombrada.java" (Campos 'R' 6)
  Escribe $d "$j/Borrada.java" ((@($b1, $b2, $menos, $mas, $b1) -join "`n") + "`n")
  Escribe $d "$j/Poca.java" (Campos 'P' 4)
  Escribe $d "$j/Corta.java" "int a;`nint b;`nint c;`n"
  Escribe $d "$j/Empate.java" (($e -join "`n") + "`n")
  Escribe $d "$j/Modificado.java" (Campos 'M' 4)
  Escribe $d "$j/Fuera.txt" "String compartidaUno = 1;`nString compartidaDos = 2;`n"
  Inicia-Repo $d
  # HEAD: Renombrada pasa a Nueva (con un cambio), se borran Borrada, Poca, Corta y Empate, y sus lineas van a otros ficheros
  [void](GitEn $d @('checkout', '-q', '-b', 'rescate'))
  [void](GitEn $d @('mv', "$j/Renombrada.java", "$j/Nueva.java"))
  Escribe $d "$j/Nueva.java" ((Campos 'R' 6).Replace('campoR1', 'campoRX'))
  foreach ($x in @('Borrada', 'Poca', 'Corta', 'Empate')) { [void](GitEn $d @('rm', '-q', "$j/$x.java")) }
  Escribe $d "$j/Modificado.java" ((Campos 'M' 4) + "`n$b1`n$menos`n$mas`n")
  Escribe $d "$j/Aaa.java" ((@($b1, $b2) -join "`n") + "`n" + (Campos 'P' 1) + "`n" + (Campos 'A' 10) + "`n")
  Escribe $d "$j/Mas.java" ((@($e[0], $e[1], $e[2]) -join "`n") + "`n" + (Campos 'N' 10) + "`n")
  Escribe $d "$j/Zeta.java" ((@($e[0], $e[1]) -join "`n") + "`n" + (Campos 'Z' 10) + "`n")
  Escribe $d "$j/alfa.java" ((@($e[2], $e[3]) -join "`n") + "`n" + (Campos 'L' 10) + "`n")
  Escribe $d "$j/Otra.java" ((Campos 'P' 1) + "`n" + (Campos 'O' 10) + "`n")
  Escribe $d "$j/Nuevo.txt" "String compartidaUno = 1;`nString compartidaDos = 2;`n"
  [void](GitEn $d @('add', '-A'))
  [void](GitEn $d @('commit', '-q', '-m', 'rescate(estructura): cambios'))
  $codigo = @'
$m = Get-MapaMovidos '{{DIR}}' 'main'
foreach ($k in $m.Keys) { 'MAPA|' + $k + '|' + (@($m[$k]) -join ',') }
'CLAVES=' + $m.Count
'TIPO=' + $m.GetType().Name
'SIN-CAMBIOS=' + (Get-MapaMovidos '{{DIR}}' 'HEAD').Count
'GIT-FALLA=' + (Get-MapaMovidos '{{DIR}}' 'rama-que-no-existe').Count
'FIN'
'@
  $r = En-Biblioteca 'mapa-movidos' $codigo.Replace('{{DIR}}', $d)
  Igual 'el script de prueba sale con 0' 0 $r.Codigo
  $l = @($r.Salida -split "`n" | ForEach-Object { $_.TrimEnd("`r") } | Where-Object { $_ -like 'MAPA|*' })
  $esperado = @(
    "MAPA|$j/Borrada.java|$j/Modificado.java,$j/Aaa.java",
    "MAPA|$j/Corta.java|",
    "MAPA|$j/Empate.java|$j/Mas.java,$j/Zeta.java,$j/alfa.java",
    "MAPA|$j/Poca.java|",
    "MAPA|$j/Renombrada.java|$j/Nueva.java")
  Igual 'el mapa: renombrado a su nueva ruta; borrados a los ficheros con 2 o mas lineas suyas (mas primero, empates por ruta ordinal); sin los .txt' ($esperado -join ' ; ') ($l -join ' ; ')
  Comprueba 'es un diccionario con orden ordinal (Zeta antes que alfa)' ($r.Salida -match 'TIPO=SortedDictionary') (Cola $r.Salida)
  Comprueba 'sin commits entre la base y HEAD el mapa sale vacio' ($r.Salida -match '(?m)^SIN-CAMBIOS=0\r?$') (Cola $r.Salida)
  Comprueba 'con una base que no existe, vacio y sin romper' ($r.Salida -match '(?m)^GIT-FALLA=0\r?$' -and $r.Salida -match '(?m)^FIN\r?$') (Cola $r.Salida)
}

# Una clase Java de mentira: el paquete, el nombre y una linea con sangria por cada texto.
function Texto-Java([string]$Clase, [string[]]$Lineas, [string]$Paquete = 'com.acme.life') {
  return ("package $Paquete;`n`npublic class $Clase {`n" + (($Lineas | ForEach-Object { "    $_`n" }) -join '') + "}`n")
}

# True si es una hora en formato 's' (PowerShell 7 lee las fechas ISO de un JSON como datetime).
function Es-Hora($V) { return (($V -is [datetime]) -or ("$V" -match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$')) }

# Los 7 primeros caracteres del HEAD de un repo o worktree.
function Head-Corto([string]$D, [string]$Rama = 'HEAD') { return (GitEn $D @('rev-parse', $Rama)).Substring(0, 7) }

# Los datos/comparacion/<ficha>.json de una salida.
function Comparaciones($E) {
  $d = Get-Ruta $E.Out 'datos/comparacion'
  if (-not (Test-Path -LiteralPath $d)) { return @() }
  return @(Get-ChildItem -LiteralPath $d -File -Filter '*.json' | Sort-Object Name | ForEach-Object { Lee-Json $_.FullName })
}

# Las llamadas que apunto la prueba en local de mentira: Legacy|Migrado|Modelo|JavaLegacy|Si.
function Llamadas-Local($E) {
  $l = Get-Ruta $E.Raiz 'prueba-local-falsa.json.llamadas'
  if (-not (Test-Path -LiteralPath $l)) { return @() }
  return @([System.IO.File]::ReadAllLines($l))
}

# Cuantas veces se llamo a Copilot para comparar (una llamada por tarea con pieza y por intento).
function Llamadas-Comparar($E) { return (Llamadas-De (Llamadas $E.Wt) 'comparar-').Count }

# El escenario de los movidos: el original con Utils, Conexion y Parser y el migrado con los mismos tres. El motor falso, al corregir,
# renombra Utils a Formatos, borra Conexion y pone 3 de sus lineas en Repositorio y borra Parser y pone 1 de sus lineas en Varios.
$LineasUtils = @('static String formatoFecha = "dd/MM/yyyy";', 'static String formatoHora = "HH:mm:ss";', 'static String separador = ",";', 'static String decimales = "0.00";', 'static String vacio = "";')
$LineasConexion = @('String servidor = "sftp.ejemplo.invalid";', 'int puerto = 2222;', 'String usuario = "carga-recibos";', 'String carpeta = "/entrada/recibos";', 'int reintentos = 3;')
$LineasParser = @('int cabeceras = 1;', 'char delimitador = ''|'';', 'String comentario = "#";', 'boolean estricto = true;', 'int maxColumnas = 40;')
$script:CorridaMovidos = $null
function Corrida-Movidos {
  if (-not $script:CorridaMovidos) {
    $e = Nuevo-Escenario 'movidos' @('Utils', 'Conexion', 'Parser')
    Escribe $e.Migrado "$RutaMigrado/Utils.java" (Texto-Java 'Utils' $LineasUtils)
    Escribe $e.Migrado "$RutaMigrado/Conexion.java" (Texto-Java 'Conexion' $LineasConexion)
    Escribe $e.Migrado "$RutaMigrado/Parser.java" (Texto-Java 'Parser' $LineasParser)
    [void](GitEn $e.Migrado @('add', '-A'))
    [void](GitEn $e.Migrado @('commit', '-q', '-m', 'clases migradas'))
    $o = Orden-Base
    $o.ficheros = [ordered]@{
      "$RutaMigrado/Formatos.java" = (Texto-Java 'Formatos' $LineasUtils)
      "$RutaMigrado/Repositorio.java" = (Texto-Java 'Repositorio' (@($LineasConexion[0..2]) + @(1..12 | ForEach-Object { "String tabla$_ = ""tabla-$_-recibos"";" })))
      'src/main/java/com/acme/otro/Varios.java' = (Texto-Java 'Varios' (@($LineasParser[0]) + @(1..12 | ForEach-Object { "String varios$_ = ""valor-$_-varios"";" })) 'com.acme.otro')
    }
    $o.borrar = @("$RutaMigrado/Utils.java", "$RutaMigrado/Conexion.java", "$RutaMigrado/Parser.java")
    $o.commits = @('rescate(estructura): lote 1, hallazgos 3 a 1')
    $script:CorridaMovidos = [pscustomobject]@{ E = $e; R = (Migra-Motor $e $o (Corrige $e)) }
  }
  return $script:CorridaMovidos
}

function Tarea-Clase($E, [string]$Clase) { return @(Tareas $E 'comparar-pieza' | Where-Object { $_.entradas.clase -ceq $Clase })[0] }

$Pruebas['103 (E2) comparar sigue los ficheros movidos: un renombrado va a su nuevo nombre, un borrado a donde fueron 2 o mas de sus lineas y el que solo dejo 1 queda sin pieza y sin llamada'] = {
  $c = Corrida-Movidos
  $e = $c.E
  Igual 'sale con 0' 0 $c.R.Codigo
  Igual 'el motor falso corrigio' 1 (Llamadas-Motor $e 'fix').Count
  Comprueba 'el worktree ya no tiene Utils, Conexion ni Parser y si Formatos y Repositorio' ((-not (Test-Path -LiteralPath (Get-Ruta $e.Wt "$RutaMigrado/Utils.java"))) -and (-not (Test-Path -LiteralPath (Get-Ruta $e.Wt "$RutaMigrado/Parser.java"))) -and (Test-Path -LiteralPath (Get-Ruta $e.Wt "$RutaMigrado/Formatos.java")) -and (Test-Path -LiteralPath (Get-Ruta $e.Wt "$RutaMigrado/Repositorio.java"))) (Cola $c.R.Salida)
  $u = Tarea-Clase $e 'Utils'
  $k = Tarea-Clase $e 'Conexion'
  $p = Tarea-Clase $e 'Parser'
  Comprueba 'hay una tarea por clase' ($u -and $k -and $p) (Cola $c.R.Salida)
  if (-not ($u -and $k -and $p)) { return }
  Igual 'Utils (renombrada): migrado = Formatos.java' "$RutaMigrado/Formatos.java" (@($u.entradas.migrado) -join ',')
  Igual 'Conexion (borrada, 3 lineas a Repositorio): migrado = Repositorio.java' "$RutaMigrado/Repositorio.java" (@($k.entradas.migrado) -join ',')
  Igual 'Parser (borrada, 1 linea a Varios): ningun fichero' 0 @($p.entradas.migrado).Count
  Igual 'Parser nace hecha' 'hecha' $p.estado
  Comprueba 'Parser: todos sus datos sin-pieza' (@($p.resultado.comparacion | Where-Object { $_.estado -ceq 'sin-pieza' }).Count -eq [int]$p.entradas.ndatos) (ConvertTo-Json -InputObject $p.resultado -Depth 5 -Compress)
  Igual 'Parser: ninguna llamada' 0 (Llamadas-De (Llamadas $e.Wt) ($p.id)).Count
  Igual 'Utils y Conexion: una llamada cada una' 1 (Llamadas-De (Llamadas $e.Wt) ($u.id)).Count
  Comprueba 'el prompt de Utils da el fichero nuevo' ((Prompt-De $e $u).Contains("MIGRADO: $RutaMigrado/Formatos.java")) (Prompt-De $e $u)
  $x = @(Comparaciones $e | Where-Object { $_.clase -ceq 'Utils' })[0]
  Comprueba 'datos/comparacion de Utils: migrado Formatos y todos igual con su cita' ($x -and @($x.migrado) -join ',' -ceq "$RutaMigrado/Formatos.java" -and @($x.datos | Where-Object { $_.estado -ceq 'igual' -and $_.fichero -ceq "$RutaMigrado/Formatos.java" -and $_.cita }).Count -eq @($x.datos).Count) (ConvertTo-Json -InputObject $x -Depth 5 -Compress)
}

$Pruebas['104 (E2) con corregir, comparar va despues del arreglo: la consola lo cuenta despues, las tareas llevan el commit del worktree y el momento despues-de-corregir'] = {
  $c = Corrida-Movidos
  $e = $c.E
  $cor = $c.R.Salida.IndexOf('Correccion: ')
  $cmp = $c.R.Salida.IndexOf('Comparacion con el original:')
  Comprueba 'la consola cuenta la correccion antes que la comparacion' ($cor -ge 0 -and $cmp -gt $cor) (Cola $c.R.Salida)
  $despues = Head-Corto $e.Wt
  Comprueba 'el HEAD del worktree no es el de antes de corregir' ($despues -ne (Head-Corto $e.Migrado 'main')) $despues
  $cs = @(Comparaciones $e)
  Comprueba 'hay un datos/comparacion por ficha con datos' ($cs.Count -ge 3) "$($cs.Count)"
  Igual 'todos con el momento despues-de-corregir' $cs.Count @($cs | Where-Object { $_.momento -ceq 'despues-de-corregir' }).Count
  Igual 'todos con el commit del HEAD del worktree' $cs.Count @($cs | Where-Object { $_.commit -ceq $despues }).Count
  $t = @(Tareas $e 'comparar-pieza')
  Igual 'las tareas llevan el mismo commit y momento' $t.Count @($t | Where-Object { $_.entradas.commit -ceq $despues -and $_.entradas.momento -ceq 'despues-de-corregir' }).Count
  Igual 'la fase acaba en hecha' 'hecha' (Estado $e).fase
}

$Pruebas['105 (E2) con -SoloInforme, comparar va antes de lectura-hecha y dice antes-de-corregir; si luego se corrige se rehace, y una relanzada con -SoloInforme tras corregir sigue diciendo despues'] = {
  $e = Nuevo-Escenario 'orden' @('Utils', 'Conexion')
  Migrado-Con $e @('Utils', 'Conexion')
  $o = Orden-Base
  $o.commits = @('rescate(estructura): lote 1, hallazgos 3 a 1')
  $r = Migra-Motor $e $o (Basicos $e)
  Igual 'con -SoloInforme sale con 0' 0 $r.Codigo
  $inicio = Head-Corto $e.Migrado 'main'
  $cs = @(Comparaciones $e)
  Comprueba 'hay comparaciones' ($cs.Count -ge 2) (Cola $r.Salida)
  Igual 'momento antes-de-corregir' $cs.Count @($cs | Where-Object { $_.momento -ceq 'antes-de-corregir' }).Count
  Igual 'con el commit de partida' $cs.Count @($cs | Where-Object { $_.commit -ceq $inicio }).Count
  Igual 'ninguna llamada fix del motor' 0 (Llamadas-Motor $e 'fix').Count
  $cmp = $r.Salida.IndexOf('Comparacion con el original:')
  $par = $r.Salida.IndexOf('No se corrige nada')
  Comprueba 'la comparacion sale antes que el paso de la correccion, que va despues de lectura-hecha' ($cmp -ge 0 -and $par -gt $cmp) (Cola $r.Salida)
  Igual 'la fase acaba en hecha' 'hecha' (Estado $e).fase
  $antes = Llamadas-Comparar $e
  # ahora se corrige: la comparacion se rehace con el HEAD nuevo y dice despues
  $r = Migra-Motor $e $o (Corrige $e)
  Igual 'corregir despues sale con 0' 0 $r.Codigo
  $fin = Head-Corto $e.Wt
  $cs = @(Comparaciones $e)
  Igual 'ahora el momento es despues-de-corregir' $cs.Count @($cs | Where-Object { $_.momento -ceq 'despues-de-corregir' -and $_.commit -ceq $fin }).Count
  Comprueba 'se llamo otra vez a Copilot para comparar' ((Llamadas-Comparar $e) -gt $antes) "$antes -> $(Llamadas-Comparar $e)"
  $antes = Llamadas-Comparar $e
  # relanzada con -SoloInforme tras una correccion completa: el momento sale de git, no del orden de las fases
  $r = Migra-Motor $e $o (Basicos $e)
  Igual 'con -SoloInforme otra vez sale con 0' 0 $r.Codigo
  $cs = @(Comparaciones $e)
  Igual 'sigue diciendo despues-de-corregir' $cs.Count @($cs | Where-Object { $_.momento -ceq 'despues-de-corregir' -and $_.commit -ceq $fin }).Count
  Igual 'y no vuelve a llamar a Copilot' $antes (Llamadas-Comparar $e)
}

$Pruebas['106 (E2) relanzar: el mismo comando no vuelve a comparar; con un commit nuevo en el worktree la comparacion se rehace'] = {
  $e = Nuevo-Escenario 'relanza' @('Utils', 'Conexion')
  Migrado-Con $e @('Utils', 'Conexion')
  $o = Orden-Base
  $o.commits = @('rescate(estructura): lote 1, hallazgos 3 a 1')
  $r = Migra-Motor $e $o (Corrige $e)
  Igual 'la primera sale con 0' 0 $r.Codigo
  $n1 = Llamadas-Comparar $e
  Comprueba 'compara con Copilot' ($n1 -ge 2) "$n1"
  $r = Migra-Motor $e $o (Corrige $e)
  Igual 'la segunda sale con 0' 0 $r.Codigo
  Igual 'la segunda no llama a Copilot para comparar' $n1 (Llamadas-Comparar $e)
  Igual 'ni vuelve a corregir' 1 (Llamadas-Motor $e 'fix').Count
  [void](GitEn $e.Wt @('commit', '-q', '--allow-empty', '-m', 'rescate(estructura): otro arreglo'))
  $r = Migra-Motor $e $o (Corrige $e)
  Igual 'la tercera sale con 0' 0 $r.Codigo
  Igual 'con un commit nuevo se vuelven a llamar las mismas tareas' (2 * $n1) (Llamadas-Comparar $e)
  $cs = @(Comparaciones $e)
  Igual 'y llevan el commit nuevo' $cs.Count @($cs | Where-Object { $_.commit -ceq (Head-Corto $e.Wt) }).Count
}

$Pruebas['107 (E2) parada en la correccion: no hay comparar despues, sale con 2 y fin lleva la hora'] = {
  $e = Nuevo-Escenario 'para-correccion' @('Utils')
  Migrado-Con $e @('Utils')
  $o = Orden-Base
  $o.codigo = 3
  $o.salida = @('git commit ha fallado')
  $r = Migra-Motor $e $o (Corrige $e) '' ([ordered]@{ codigo = 0; salida = @('no deberia llamarse') })
  Igual 'sale con 2' 2 $r.Codigo
  $s = Estado $e
  Igual 'parada: git' 'git' $s.parada.motivo
  Igual 'la prueba en local no se llama' 0 @(Llamadas-Local $e).Count
  Comprueba 'y su estado sigue en null' ($s.PSObject.Properties.Name -contains 'pruebaLocal' -and $null -eq $s.pruebaLocal)
  Igual 'ninguna tarea de comparar' 0 @(Tareas $e 'comparar-pieza').Count
  Igual 'ningun datos/comparacion' 0 @(Comparaciones $e).Count
  Comprueba 'la consola no cuenta la comparacion' ($r.Salida -notmatch 'Comparacion con el original:') (Cola $r.Salida)
  Comprueba 'fin es una hora' (Es-Hora $s.fin) "$($s.fin)"
  Comprueba 'la fase no es hecha' ($s.fase -ne 'hecha') $s.fase
}

$Pruebas['108 (E2) fin: vale vacio mientras corre y una hora al acabar, con parada, con -Limite y con error interno'] = {
  $e = Nuevo-Escenario 'fin' @('Clase1')
  $ctrl = Get-Ruta $e.Raiz 'motor-falso.json'
  Guarda-Json $ctrl (Orden-Base)
  $lista = @(@('-NoProfile', '-File', (Sistema-Motor-Lento)) + (Corrige $e) | ForEach-Object { '"' + $_ + '"' })
  $env:RESCATE_HOME = $e.Home
  $env:MOTOR_FALSO = $ctrl
  try {
    $p = Start-Process -FilePath $ps -ArgumentList $lista -RedirectStandardOutput (Get-Ruta $e.Raiz 'fin-salida.txt') -RedirectStandardError (Get-Ruta $e.Raiz 'fin-error.txt') -PassThru
    $vista = $null
    for ($i = 0; $i -lt 480 -and -not $p.HasExited; $i++) {
      Start-Sleep -Milliseconds 250
      $s = $null
      try { $s = Estado $e } catch { $s = $null }
      if ($s -and $s.fase -eq 'correccion') { $vista = $s; break }
    }
    $p.WaitForExit()
  }
  finally { $env:RESCATE_HOME = ''; $env:MOTOR_FALSO = '' }
  Comprueba 'se vio el estado.json mientras el motor corregia' ($null -ne $vista) (Get-Content -LiteralPath (Get-Ruta $e.Raiz 'fin-salida.txt') -Tail 8 | Out-String)
  if ($null -ne $vista) { Comprueba 'mientras corre, fin vale vacio' ($vista.PSObject.Properties.Name -contains 'fin' -and "$($vista.fin)" -ceq '') "'$($vista.fin)'" }
  $s = Estado $e
  Comprueba 'al acabar bien, fin es una hora' (Es-Hora $s.fin) "$($s.fin)"
  Igual 'y la fase es hecha' 'hecha' $s.fase
  $f = Nuevo-Escenario 'fin-limite' @('Clase1', 'Clase2')
  $r = Migra $f ((Basicos $f) + @('-Limite', '1'))
  Igual 'con -Limite sale con 0' 0 $r.Codigo
  $s = Estado $f
  Comprueba 'con -Limite, fin es una hora' (Es-Hora $s.fin) "$($s.fin)"
  Comprueba 'y la fase no es hecha: quedan tareas' ($s.fase -ne 'hecha') $s.fase
}

$JobsLocal = @([ordered]@{ job = 'cargaJob'; casos = 3; iguales = 2; distintos = 1; sinProbar = 0 }, [ordered]@{ job = 'informeJob'; casos = 2; iguales = 1; distintos = 1; sinProbar = 0 })

$Pruebas['109 (E2) fase prueba-local: una llamada con -Si, el modelo y las carpetas de la pasada, despues de comparar; el codigo 2 es hecha, deja registro y la consola da las cuentas'] = {
  $e = Nuevo-Escenario 'local' @('Utils')
  Migrado-Con $e @('Utils')
  $o = Orden-Base
  $o.commits = @('rescate(estructura): lote 1, hallazgos 3 a 1')
  $l = [ordered]@{ codigo = 2; salida = @('LINEA-DEL-FALSO'); json = [ordered]@{ jobs = $JobsLocal } }
  $r = Migra-Motor $e $o (Corrige $e) '' $l
  Igual 'sale con 0' 0 $r.Codigo
  $s = Estado $e
  $ll = @(Llamadas-Local $e)
  Igual 'el falso se llama una vez' 1 $ll.Count
  Igual 'con el -Legacy y el -Migrado de la pasada, el modelo, sin -JavaLegacy y con -Si' "$($s.legacy)|$($s.migrado)|modelo-x||True" $ll[0]
  Comprueba 'estado.pruebaLocal es un objeto' ($null -ne $s.pruebaLocal) (Cola $r.Salida)
  if ($null -eq $s.pruebaLocal) { return }
  Igual 'resultado hecha' 'hecha' $s.pruebaLocal.resultado
  Igual 'codigo 2' 2 $s.pruebaLocal.codigo
  Comprueba 'minutos es un numero' ($s.pruebaLocal.minutos -is [double] -or $s.pruebaLocal.minutos -is [int] -or $s.pruebaLocal.minutos -is [decimal]) "$($s.pruebaLocal.minutos)"
  Igual 'sin detalle (solo se cuenta en un fallo)' '' "$($s.pruebaLocal.detalle)"
  Igual 'el registro es registros/prueba-local.log' 'registros/prueba-local.log' $s.pruebaLocal.registro
  Comprueba 'el registro existe y lleva la salida del falso' ((Test-Path -LiteralPath (Get-Ruta $e.Out 'registros/prueba-local.log')) -and (Lee $e.Out 'registros/prueba-local.log').Contains('LINEA-DEL-FALSO'))
  Igual 'la fase acaba en hecha' 'hecha' $s.fase
  $cmp = $r.Salida.IndexOf('Comparacion con el original:')
  $viva = $r.Salida.IndexOf('LINEA-DEL-FALSO')
  $linea = $r.Salida.IndexOf('Prueba en local: 5 casos, 3 iguales, 2 distintos (')
  Comprueba 'la consola: primero la comparacion, luego la salida en vivo del falso y al final la linea con las cuentas' ($cmp -ge 0 -and $viva -gt $cmp -and $linea -gt $viva) (Cola $r.Salida)
  Comprueba 'la linea acaba con el detalle: la pagina 3' ($r.Salida -match 'min\)\. Detalle: [^\r\n]*3-original-vs-migrado\.html') (Cola $r.Salida)
  Comprueba 'el falso dejo datos/prueba-local.json' (Test-Path -LiteralPath (Get-Ruta $e.Out 'datos/prueba-local.json'))
}

$Pruebas['110 (E2) prueba-local que falla: un aviso con el codigo, las tres ultimas lineas con texto y el registro; resultado fallo, fase hecha y salida 0'] = {
  $e = Nuevo-Escenario 'local-falla' @('Clase1')
  $l = [ordered]@{ codigo = 1; salida = @('uno', 'dos', '', 'tres', 'no compila') }
  $r = Migra-Motor $e (Orden-Base) (Corrige $e) '' $l
  Igual 'sale con 0' 0 $r.Codigo
  $s = Estado $e
  Comprueba 'estado.pruebaLocal es un objeto' ($null -ne $s.pruebaLocal) (Cola $r.Salida)
  if ($null -eq $s.pruebaLocal) { return }
  Igual 'resultado fallo' 'fallo' $s.pruebaLocal.resultado
  Igual 'codigo 1' 1 $s.pruebaLocal.codigo
  Igual 'detalle: las tres ultimas lineas con texto' 'dos / tres / no compila' $s.pruebaLocal.detalle
  Igual 'la fase acaba en hecha: un fallo no para la pasada' 'hecha' $s.fase
  Comprueba 'la consola avisa con el codigo, el detalle y el registro' ($r.Salida -match 'Prueba en local: [^\r\n]*codigo 1[^\r\n]*dos / tres / no compila[^\r\n]*prueba-local\.log') (Cola $r.Salida)
  Comprueba 'y no da cuentas: no hay datos/prueba-local.json' ($r.Salida -notmatch 'Prueba en local: \d+ casos')
}

$Pruebas['111 (E2) prueba-local: -SinPruebaLocal no llama al falso y deja saltada; -JavaLegacy llega al falso'] = {
  $e = Nuevo-Escenario 'local-saltada' @('Clase1')
  $o = Orden-Base
  $l = [ordered]@{ codigo = 0; salida = @('LINEA-DEL-FALSO') }
  $r = Migra-Motor $e $o ((Corrige $e) + '-SinPruebaLocal') '' $l
  Igual 'con -SinPruebaLocal sale con 0' 0 $r.Codigo
  Igual 'el falso no se llama' 0 @(Llamadas-Local $e).Count
  $s = Estado $e
  Comprueba 'estado.pruebaLocal es un objeto' ($null -ne $s.pruebaLocal) (Cola $r.Salida)
  if ($null -eq $s.pruebaLocal) { return }
  Igual 'resultado saltada' 'saltada' $s.pruebaLocal.resultado
  Comprueba 'codigo null' ($null -eq $s.pruebaLocal.codigo)
  Igual 'la fase acaba en hecha' 'hecha' $s.fase
  Comprueba 'no hay registro de la prueba en local' (-not (Test-Path -LiteralPath (Get-Ruta $e.Out 'registros/prueba-local.log')))
  # sin -SinPruebaLocal, y con el JDK del original, se lanza aunque ya hubiera una pasada: siempre se llama
  $r = Migra-Motor $e $o ((Corrige $e) + @('-JavaLegacy', 'jdk8-x')) '' $l
  Igual 'con -JavaLegacy sale con 0' 0 $r.Codigo
  $ll = @(Llamadas-Local $e)
  Igual 'el falso se llama una vez y recibe el -JavaLegacy tal cual' "$((Estado $e).legacy)|$((Estado $e).migrado)|modelo-x|jdk8-x|True" ($ll -join ';')
  Igual 'ahora el resultado es hecha' 'hecha' (Estado $e).pruebaLocal.resultado
}

# ======================= P2: LAS PAGINAS DE LA PRUEBA EN LOCAL, LA PORTADA Y LA PAGINA 4 =======================
# Una copia de la corrida de dos jobs, para cambiar sus datos sin afectar a los demas tests.
function Local-Salida([string]$Nombre) { return (Copia-Salida (Corrida-Dos $GuionBase).E $Nombre) }

# Cambia estado.json de la copia $S con esos campos (nombre -> valor; por defecto, una pasada hecha con la respuesta corregir y sin prueba
# en local), deja $Local como su datos/prueba-local.json (si es $null, lo borra) y monta las paginas otra vez.
function Local-Con([string]$S, $Cambios = @{}, $Local = $null) {
  $e = Lee-Json (Get-Ruta $S 'datos/estado.json')
  $campos = @{ creado = '2026-11-18T05:00:00'; actualizado = '2026-11-18T05:20:00'; fin = ''; fase = 'hecha'; respuesta = 'corregir'; pruebaLocal = $null }
  foreach ($k in $Cambios.Keys) { $campos[$k] = $Cambios[$k] }
  foreach ($k in $campos.Keys) { Add-Member -InputObject $e -NotePropertyName $k -NotePropertyValue $campos[$k] -Force }
  Guarda-Json (Get-Ruta $S 'datos/estado.json') $e
  $ruta = Get-Ruta $S 'datos/prueba-local.json'
  if ($null -ne $Local) { Guarda-Json $ruta $Local } elseif (Test-Path -LiteralPath $ruta) { Remove-Item -LiteralPath $ruta }
  $g = Genera-Informes $S
  Comprueba 'Write-Informes sale bien' ($g.Codigo -eq 0 -and $g.Salida -match 'INFORMES-OK') (Cola $g.Salida)
  return [pscustomobject]@{ I = (Pagina $S 'index.html'); P3 = (Pagina $S '3-original-vs-migrado.html'); P4 = (Pagina $S '4-correcciones.html') }
}

# El texto de un trozo de pagina, sin etiquetas y con los espacios juntos.
function Texto-De([string]$Html) { return ([regex]::Replace($Html, '<[^>]+>', ' ') -replace '\s+', ' ').Trim() }

$PlNota = 'Posible diferencia del JDK <b>nota</b> & "q"'
$PlResultado = [ordered]@{ resultado = 'hecha'; codigo = 2; minutos = 16.9; detalle = ''; registro = 'registros/prueba-local.log' }
$PlFallo = [ordered]@{ resultado = 'fallo'; codigo = 1; minutos = 3.5; detalle = 'dos / tres <b>&</b>'; registro = 'registros/prueba-local.log' }
$PlSaltada = [ordered]@{ resultado = 'saltada'; codigo = $null; minutos = 0; detalle = ''; registro = '' }

function Caso-Local([string]$Job, [string]$Caso, [string]$Titulo, [string]$Resultado, [string]$Motivo = '', $Dif = @()) {
  return [ordered]@{ job = $Job; caso = $Caso; titulo = $Titulo; resultado = $Resultado; motivo = $Motivo; diferencias = @($Dif) }
}

function Dif-Local([string]$Fichero, [int]$Lineas, [int]$Linea, [string]$Original, [string]$Migrado, [string]$Nota = '') {
  return [ordered]@{ fichero = $Fichero; lineas = $Lineas; linea = $Linea; original = $Original; migrado = $Migrado; nota = $Nota }
}

# Un datos/prueba-local.json de mentira: 6 casos de 2 jobs (3 iguales, 1 distinto con dos diferencias y 2 sin probar), un igual con motivo
# y un no determinista; con markup en un titulo, una linea original y un motivo.
function Local-Json([string]$Migrado = 'hecha') {
  return [ordered]@{
    version = 1; modelo = 'modelo-x'; inicio = '2026-11-18T05:28:58'; fin = '2026-11-18T05:45:51'; minutos = 16.9; llamadas = 49
    arneses = [ordered]@{ original = 'hecha'; migrado = $Migrado }
    jobs = @([ordered]@{ job = 'cargaJob'; casos = 4; iguales = 1; distintos = 1; sinProbar = 2 }, [ordered]@{ job = 'informeJob'; casos = 2; iguales = 2; distintos = 0; sinProbar = 0 })
    casos = @(
      (Caso-Local 'cargaJob' 'caso-01' 'Recibo correcto' 'igual'),
      (Caso-Local 'cargaJob' 'caso-02' $MalTexto 'distinto' '' @((Dif-Local 'tablas/R.csv' 3 2 $MalTexto '(no hay)'), (Dif-Local 'envios/correo.txt' 1 5 'uno' 'dos' $PlNota))),
      (Caso-Local 'cargaJob' 'caso-03' 'Carpeta que no existe' 'sin probar en local' $MalTexto),
      (Caso-Local 'cargaJob' 'caso-04' 'La hora de hoy' 'no determinista'),
      (Caso-Local 'informeJob' 'caso-01' 'Informe vacio' 'igual'),
      (Caso-Local 'informeJob' 'caso-02' 'Informe del dia' 'igual' 'El informe lleva la fecha de hoy'))
    noPromete = 'Lo que esto no promete: las entradas son inventadas <i>y</i> & "simuladas".'
  }
}

$Pruebas['113 (P2) pagina 3 con prueba-local.json: la seccion va antes de Leido por la IA, con su etiqueta, la linea de cuentas, la tabla por job, un grupo por caso distinto con sus diferencias y su nota, el resto plegado, lo que no promete, un solo h1 y todo escapado'] = {
  $x = Local-Con (Local-Salida 'p2-pagina3') @{ pruebaLocal = $PlResultado } (Local-Json)
  $p = $x.P3
  $sec = Panel-De $p 'prueba-local'
  Comprueba 'la seccion prueba-local existe, con su h2' ($sec.Length -gt 0 -and $sec -match '<h2[^>]*>Probado ejecutando los dos</h2>') $p
  $ia = [regex]::Match($p, '<h2[^>]*>Le.do por la IA</h2>')
  Comprueba 'va antes del h2 Leido por la IA' ($ia.Success -and $p.IndexOf('id="prueba-local"') -ge 0 -and $p.IndexOf('id="prueba-local"') -lt $ia.Index)
  Comprueba 'la entradilla dice las dos comparaciones, la de ejecutar primero y la lectura de la IA debajo' ($p -match 'Dos comparaciones del mismo batch\. Arriba, la m.s fiable: el original y el migrado ejecutados con las mismas entradas\. Debajo, la lectura de la IA, dato a dato\.')
  Comprueba 'la etiqueta: medido, con entradas que escribio la IA' ($sec -match 'class="et et-medido"' -and $sec -match 'Medido, con entradas que escribi. la IA')
  Comprueba 'la linea de cuentas, con los minutos con coma y la fecha de fin' ((Texto-De $sec) -match '6 casos de 2 jobs: 3 iguales, 1 distintos y 2 sin probar\. 49 llamadas a la IA y 16,9 min, el 18-11-2026 05:45\.') (Texto-De $sec)
  Comprueba 'con el test del migrado hecho no hay aviso' ($sec -notmatch 'no tiene su test de prueba')
  Comprueba 'la tabla: Job, Casos, Iguales, Distintos y Sin probar' ($sec -match '(?s)<table.*?</table>' -and (Texto-De ([regex]::Match($sec, '(?s)<thead>.*?</thead>').Value)) -ceq 'Job Casos Iguales Distintos Sin probar') $sec
  $filas = @([regex]::Matches($sec, '(?s)<tr>.*?</tr>') | ForEach-Object { Texto-De $_.Value })
  Comprueba 'una fila por job, con sus cuentas' ($filas -contains 'cargaJob 4 1 1 2' -and $filas -contains 'informeJob 2 2 0 0') ($filas -join ' / ')
  Igual 'solo el numero de distintos mayor que 0 va en --mal' 1 ([regex]::Matches($sec, 'class="mal"').Count)
  Comprueba 'y es el de cargaJob' ([regex]::Match($sec, '(?s)<tr>(?:(?!</tr>).)*cargaJob.*?</tr>').Value -match 'class="mal">1<')
  $g = [regex]::Match($sec, '(?s)<article class="prob-grupo.*?</article>').Value
  Igual 'un grupo por caso distinto' 1 ([regex]::Matches($sec, '<article class="prob-grupo').Count)
  Comprueba 'su cabecera lleva el job, el caso y el titulo escapado' ($g -match '(?s)<header class="pg-cab">.*cargaJob.*caso-02.*</header>' -and $g.Contains((Html $MalTexto))) $g
  $lis = @([regex]::Matches($g, '(?s)<li class="fila s-error">.*?</li>') | ForEach-Object { $_.Value })
  Igual 'una fila por diferencia' 2 $lis.Count
  if ($lis.Count -eq 2) {
    Comprueba 'la primera: fichero, lineas, la primera linea y las dos lineas en code' ((Texto-De $lis[0]) -match '^Distinto tablas/R\.csv ?: 3 l.neas distintas; la primera, la 2 Original: .* Migrado: \(no hay\)$' -and $lis[0].Contains('<b>Original:</b> <code>' + (Html $MalTexto) + '</code>') -and $lis[0].Contains('<b>Migrado:</b> <code>(no hay)</code>')) $lis[0]
    Comprueba 'sin nota, no lleva aviso' ($lis[0] -notmatch 'class="aviso"')
    Comprueba 'la segunda: su fichero, sus lineas y su linea' ((Texto-De $lis[1]) -match 'envios/correo\.txt ?: 1 l.nea distinta; la primera, la 5 Original: uno Migrado: dos') $lis[1]
    Comprueba 'y su nota va despues, como aviso y escapada' ($lis[1] -match ('(?s)Migrado:.*<p class="aviso">' + [regex]::Escape((Html $PlNota)) + '</p>')) $lis[1]
  }
  $d = [regex]::Match($sec, '(?s)<details.*?</details>').Value
  Comprueba 'un details con 3 casos sin comparar o con aviso' ($d.Length -gt 0 -and $d -match '<summary>3 casos sin comparar o con aviso</summary>' -and [regex]::Matches($d, '<li class="fila').Count -eq 3) $d
  Comprueba 'va plegado (sin open)' ($d -notmatch '<details[^>]*open')
  Comprueba 'el sin probar: job, caso, titulo, resultado y motivo escapado' ($d -match 'cargaJob</code> <code>caso-03</code> Carpeta que no existe' -and $d -match 'sin probar en local' -and $d.Contains((Html $MalTexto))) $d
  Comprueba 'el no determinista: con su resultado' ($d -match 'caso-04</code> La hora de hoy' -and $d -match 'no determinista')
  Comprueba 'el igual con motivo: con su motivo' ($d -match 'informeJob</code> <code>caso-02</code> Informe del dia' -and $d.Contains('El informe lleva la fecha de hoy'))
  Comprueba 'los iguales sin motivo no estan' ($d -notmatch 'Recibo correcto' -and $d -notmatch 'Informe vacio')
  Comprueba 'lo que no promete va en un parrafo muted, escapado' ($sec.Contains('<p class="muted">' + (Html 'Lo que esto no promete: las entradas son inventadas <i>y</i> & "simuladas".') + '</p>')) $sec
  Comprueba 'sin fallo no hay linea de prueba-local.ps1' ($sec -notmatch 'ha salido con c.digo')
  Igual 'un solo h1' 1 ([regex]::Matches($p, '<h1[ >]').Count)
  Comprueba 'ni un <script> sin escapar en la pagina' ($p -notmatch '(?i)<script|<b>nota|<i>y')
  Comprueba 'Leido por la IA: panel con su etiqueta y la frase de las citas' ($p -match '(?s)id="leido-ia".*et-ia.*Para cada dato que se ley. del original, dice si el migrado lo hace igual, distinto o no lo hace\. El script comprueba que las citas existen en los ficheros\.')
  Comprueba 'los jobs de la lectura, debajo, con h3 y sin h2' ($p -match '<h3 id="g-comp-cargaJob">cargaJob</h3>' -and $p -notmatch '<h2 id="g-comp-' -and $p.IndexOf('<h3 id="g-comp-cargaJob">') -gt $ia.Index)
  Comprueba 'el CSS da a los h3 de la cabecera el aspecto de los h2' ($p -match '\.pg-cab h2,\.pg-cab h3')
}

$Pruebas['114 (P2) pagina 3: sin el test del migrado avisa de que sus casos no se ejecutaron, y con un fallo y un JSON de antes lo dice al final'] = {
  $s = Local-Salida 'p2-pagina3-aviso'
  $x = Local-Con $s @{ pruebaLocal = $PlFallo } (Local-Json 'fallo')
  $sec = Panel-De $x.P3 'prueba-local'
  $aviso = $sec.IndexOf('El migrado no tiene su test de prueba (la IA no pudo escribirlo): sus casos no se han ejecutado.')
  Comprueba 'el aviso del migrado va despues de la linea de cuentas y antes de la tabla' ($aviso -gt $sec.IndexOf('casos de 2 jobs') -and $aviso -lt $sec.IndexOf('<table')) (Texto-De $sec)
  $linea = [regex]::Match($sec, '<p class="aviso">prueba-local\.ps1 ha salido con c.digo 1: (.*?)\. Registro: (.*?)\.</p>')
  Comprueba 'y la linea del fallo: codigo, detalle escapado y registro' ($linea.Success -and $linea.Groups[1].Value -ceq (Html 'dos / tres <b>&</b>') -and $linea.Groups[2].Value -ceq 'registros/prueba-local.log') $sec
  Comprueba 'va la ultima, despues de lo que no promete' ($linea.Index -gt $sec.IndexOf('class="muted"'))
  $x = Local-Con $s @{ pruebaLocal = $PlResultado } (Local-Json)
  $sec = Panel-De $x.P3 'prueba-local'
  Comprueba 'con la prueba hecha y el arnes hecho, ni aviso ni fallo' ($sec -notmatch 'no tiene su test' -and $sec -notmatch 'ha salido con c.digo')
}

$Pruebas['115 (P2) pagina 3 sin prueba-local.json: el fallo en su caja con el detalle y el registro, saltada y el sin-datos de la fase prueba-local'] = {
  $s = Local-Salida 'p2-pagina3-sin'
  $x = Local-Con $s @{ pruebaLocal = $PlFallo }
  $sec = Panel-De $x.P3 'prueba-local'
  Comprueba 'fallo: la caja dice el codigo, el detalle escapado y el registro' ((Texto-De $sec) -match ('No se ha podido hacer la prueba en local \(c.digo 1\): ' + [regex]::Escape((Html 'dos / tres <b>&</b>')) + '\. Registro: registros/prueba-local\.log\.')) (Texto-De $sec)
  Comprueba 'y sin tabla, sin etiqueta de medido' ($sec -notmatch '<table' -and $sec -notmatch 'Medido')
  $x = Local-Con $s @{ pruebaLocal = $PlSaltada }
  $sec = Panel-De $x.P3 'prueba-local'
  Comprueba 'saltada: no se ha hecho, la pasada se lanzo con -SinPruebaLocal' ((Texto-De $sec) -match 'No se ha hecho: la pasada se lanz. con -SinPruebaLocal\.') (Texto-De $sec)
  $x = Local-Con $s @{ fase = 'comparar' }
  $sec = Panel-De $x.P3 'prueba-local'
  Comprueba 'sin nada: el sin-datos de siempre con la fase prueba-local' ($sec -match 'class="sin-datos"' -and (Texto-De $sec) -match 'Todav.a no hay datos: la fase prueba-local no ha terminado\.') (Texto-De $sec)
  Comprueba 'en los tres, debajo sigue la lectura de la IA con sus jobs' ($x.P3 -match '<h2[^>]*>Le.do por la IA</h2>' -and $x.P3 -match 'id="comp-cargaJob"')
}

$Pruebas['116 (P2) pagina 3: la linea de momento sale del primer datos/comparacion que lleve momento, con su commit; sin momento no hay linea'] = {
  $s = Local-Salida 'p2-momento'
  $fs = @(Get-ChildItem -LiteralPath (Get-Ruta $s 'datos/comparacion') -File -Filter 'clase-*.json' | Sort-Object Name)
  Comprueba 'hay al menos dos comparaciones' ($fs.Count -ge 2) "$($fs.Count)"
  foreach ($f in $fs) {
    $j = Lee-Json $f.FullName
    $j.PSObject.Properties.Remove('momento')
    $j.PSObject.Properties.Remove('commit')
    Guarda-Json $f.FullName $j
  }
  $x = Local-Con $s
  Comprueba 'sin momento en ninguna, no hay linea' ($x.P3 -notmatch 'Sobre el migrado')
  $segunda = Lee-Json $fs[1].FullName
  Add-Member -InputObject $segunda -NotePropertyName momento -NotePropertyValue 'antes-de-corregir' -Force
  Add-Member -InputObject $segunda -NotePropertyName commit -NotePropertyValue 'abc1234' -Force
  Guarda-Json $fs[1].FullName $segunda
  $x = Local-Con $s
  Comprueba 'antes-de-corregir en la segunda: sale su commit' ($x.P3 -match 'Sobre el migrado tal como lleg., antes de corregir \(commit abc1234\)\.')
  $primera = Lee-Json $fs[0].FullName
  Add-Member -InputObject $primera -NotePropertyName momento -NotePropertyValue 'despues-de-corregir' -Force
  Add-Member -InputObject $primera -NotePropertyName commit -NotePropertyValue 'def5678' -Force
  Guarda-Json $fs[0].FullName $primera
  $x = Local-Con $s
  Comprueba 'despues-de-corregir en la primera: gana la primera' ($x.P3 -match 'Sobre el migrado ya corregido \(commit def5678 de la rama de rescate\)\.' -and $x.P3 -notmatch 'abc1234')
  $ia = $x.P3.IndexOf('id="leido-ia"')
  Comprueba 'la linea va en Leido por la IA, antes de la frase de las citas' ($x.P3.IndexOf('Sobre el migrado ya corregido') -gt $ia -and $x.P3.IndexOf('Sobre el migrado ya corregido') -lt $x.P3.IndexOf('Para cada dato'))
}

$Pruebas['117 (P2) portada, Lo que te toca: el grupo de distintos va el primero, antes de las atascadas, con la etiqueta de medido y un elemento por caso; con un fallo y sin JSON sale Prueba en local sin hacer'] = {
  $c = Corrida-Dos $GuionBase
  $s = Local-Salida 'p2-toca'
  $t = @(Tareas $c.E)[0]
  $ruta = Get-Ruta $s ('datos/tareas/' + $t.id + '.json')
  $j = Lee-Json $ruta
  $j.estado = 'atascada'
  $j.motivo = 'no sale'
  Guarda-Json $ruta $j
  $x = Local-Con $s @{ pruebaLocal = $PlResultado } (Local-Json)
  $toca = Toca-De $x.I
  $titulos = @([regex]::Matches($toca, '<h3>(.*?)</h3>') | ForEach-Object { $_.Groups[1].Value })
  Comprueba 'el primer grupo es Distintos al ejecutar los dos (1) y despues van las atascadas' ($titulos.Count -ge 2 -and $titulos[0] -ceq 'Distintos al ejecutar los dos (1)' -and $titulos[1] -ceq 'Tareas atascadas (1)') ($titulos -join ' | ')
  $g = [regex]::Match($toca, '(?s)<h3>Distintos al ejecutar los dos \(1\)</h3>.*?</div>').Value
  Comprueba 'lleva la etiqueta de medido con entradas de la IA, no la de sin comprobar' ($g -match 'Medido, con entradas que escribi. la IA' -and $g -notmatch 'Sin comprobar') $g
  Comprueba 'y el texto del grupo' ((Texto-De $g) -match 'Casos en los que el migrado deja algo distinto que el original con las mismas entradas\. Es lo m.s fiable del informe: m.ralos primero\. El detalle est. en la p.gina Original frente a migrado\.') (Texto-De $g)
  Igual 'un elemento por caso distinto' 1 ([regex]::Matches($g, '<li>').Count)
  $izq = [string][char]0xAB
  $der = [string][char]0xBB
  Comprueba 'el elemento: job y caso en la cabecera; el titulo y el fichero con original y migrado de la primera diferencia, escapado' ($g.Contains('<code>cargaJob</code> <code>caso-02</code>') -and $g.Contains((Html $MalTexto) + '. tablas/R.csv: original ' + $izq + (Html $MalTexto) + $der + ', migrado ' + $izq + '(no hay)' + $der)) $g
  $ga = [regex]::Match($toca, '(?s)<h3>Tareas atascadas \(1\)</h3>.*?</div>').Value
  Comprueba 'el grupo de atascadas sigue con sin comprobar' ($ga -match 'Sin comprobar' -and $ga -notmatch 'Medido') $ga
  $sin = Local-Json
  $sin.casos = @($sin.casos | Where-Object { $_.resultado -cne 'distinto' })
  $x = Local-Con $s @{ pruebaLocal = $PlResultado } $sin
  Comprueba 'sin ningun caso distinto no hay grupo' ((Toca-De $x.I) -notmatch 'Distintos al ejecutar')
  $x = Local-Con $s @{ pruebaLocal = $PlFallo }
  $toca = Toca-De $x.I
  $titulos = @([regex]::Matches($toca, '<h3>(.*?)</h3>') | ForEach-Object { $_.Groups[1].Value })
  Comprueba 'con fallo y sin JSON, el primero es Prueba en local sin hacer (1), antes de las atascadas' ($titulos.Count -ge 2 -and $titulos[0] -ceq 'Prueba en local sin hacer (1)' -and $titulos[1] -ceq 'Tareas atascadas (1)') ($titulos -join ' | ')
  $g = [regex]::Match($toca, '(?s)<h3>Prueba en local sin hacer \(1\)</h3>.*?</div>').Value
  Comprueba 'con el codigo y el detalle escapado' ($g -match 'c.digo 1' -and $g.Contains((Html 'dos / tres <b>&</b>'))) $g
  $x = Local-Con $s @{ pruebaLocal = $PlFallo } (Local-Json)
  Comprueba 'con fallo y con JSON, solo el grupo de distintos' ((Toca-De $x.I) -match 'Distintos al ejecutar los dos \(1\)' -and (Toca-De $x.I) -notmatch 'sin hacer')
}

# Las lineas de Que ha hecho el script de una portada: la clave de la fase, su estado, su texto y su cuenta, en su orden.
function Clave-Fase([string]$Nombre) {
  foreach ($k in @(@('diagnostico', 'Diagn.stico'), @('clases', 'Lectura de las clases'), @('mapa', 'Mapa de jobs'), @('lanzadores', 'C.mo se lanza cada job'), @('jobs', 'Redacci.n de cada job'), @('resumen', 'Resumen y glosario'),
      @('pre', 'Guion de prueba'), @('casos', 'Casos de las reglas sin caso'), @('correccion', 'Correcci.n del migrado'), @('comparar', 'Comparaci.n con el original'), @('local', 'Prueba en local'))) {
    if ($Nombre -match $k[1]) { return $k[0] }
  }
  return $Nombre
}
function Fases-De([string]$Html) {
  $ol = [regex]::Match($Html, '(?s)<ol class="fases">.*?</ol>').Value
  return @([regex]::Matches($ol, '<span class="fase-n">(.*?)</span><span class="fase-e" data-e="(\w+)">(.*?)</span><span class="fase-c">(.*?)</span>') | ForEach-Object {
      [pscustomobject]@{ Clave = (Clave-Fase $_.Groups[1].Value); E = $_.Groups[2].Value; Texto = $_.Groups[3].Value; Cuenta = $_.Groups[4].Value }
    })
}

$Pruebas['118 (P2) portada, Que ha hecho el script: el orden segun la respuesta, los estados de prueba-local con su cuenta, lectura-hecha en su sitio y el estado de arriba'] = {
  $d = Datos-Pagina4
  $con = (Correccion-Con (Corrida-Dos $GuionBase).E 'p2-fases-con' $d.Antes $d.Despues $d.Corr).Dir
  $sin = Local-Salida 'p2-fases-sin'
  $corregir = 'diagnostico clases mapa lanzadores jobs resumen pre casos correccion comparar local'
  $parar = 'diagnostico clases mapa lanzadores jobs resumen pre casos comparar correccion local'
  $antes = 'diagnostico=hecha clases=hecha mapa=hecha lanzadores=hecha jobs=hecha resumen=hecha pre=hecha'
  $parada = [ordered]@{ motivo = 'tope-de-tiempo'; detalle = 'detalle'; registro = 'registro'; ayuda = 'ayuda' }
  $filas = @(
    @{ N = 'corregir, comparando, con la correccion completa'; S = $con; C = @{ fase = 'comparar' }; L = $null; Orden = $corregir; E = "$antes correccion=hecha comparar=curso local=espera"; Arriba = 'La pasada no ha terminado: va por la fase comparar\.' },
    @{ N = 'corregir, en la prueba en local'; S = $con; C = @{ fase = 'prueba-local' }; L = $null; Orden = $corregir; E = "$antes correccion=hecha comparar=hecha local=curso"; Arriba = 'va por la fase prueba-local\.' },
    @{ N = 'corregir, hecha y con la correccion completa; la prueba en local con fallo'; S = $con; C = @{ pruebaLocal = $PlFallo }; L = $null; Orden = $corregir; E = "$antes correccion=hecha comparar=hecha local=hecha"; Arriba = 'La pasada ha terminado: lectura, correcci.n y pruebas\.'; Cuenta = 'no se ha podido: mira la p.gina 3' },
    @{ N = 'parar, hecha y sin correccion; la prueba en local hecha'; S = $sin; C = @{ respuesta = 'parar'; pruebaLocal = $PlResultado }; L = (Local-Json); Orden = $parar; E = "$antes comparar=hecha correccion=espera local=hecha"; Arriba = 'La pasada ha terminado, sin corregir\.'; Cuenta = '6 casos: 3 iguales, 1 distintos, 2 sin probar' },
    @{ N = 'corregir, hecha y sin correccion; la prueba en local saltada'; S = $sin; C = @{ pruebaLocal = $PlSaltada }; L = $null; Orden = $corregir; E = "$antes correccion=espera comparar=hecha local=saltada"; Arriba = 'La pasada ha terminado, sin corregir\.'; Cuenta = '-SinPruebaLocal'; Texto = 'Saltada' },
    @{ N = 'corregir, lectura-hecha'; S = $sin; C = @{ fase = 'lectura-hecha' }; L = $null; Orden = $corregir; E = "$antes correccion=espera comparar=espera local=espera"; Arriba = 'La lectura del original ha terminado\.'; Texto = 'Sin empezar' },
    @{ N = 'parar, lectura-hecha'; S = $sin; C = @{ respuesta = 'parar'; fase = 'lectura-hecha' }; L = $null; Orden = $parar; E = "$antes comparar=hecha correccion=espera local=espera"; Arriba = 'La lectura del original ha terminado\.' },
    @{ N = 'con parada, el estado de siempre'; S = $con; C = @{ fase = 'comparar'; parada = $parada }; L = $null; Orden = $corregir; E = "correccion=hecha comparar=curso"; Arriba = 'La pasada se ha parado en la fase comparar: tope-de-tiempo\.' }
  )
  foreach ($f in $filas) {
    $x = Local-Con $f.S $f.C $f.L
    $fases = @(Fases-De $x.I)
    Igual "$($f.N) : el orden" $f.Orden (($fases | ForEach-Object { $_.Clave }) -join ' ')
    foreach ($par in @($f.E -split ' ')) {
      $k, $e = $par -split '='
      $l = @($fases | Where-Object { $_.Clave -ceq $k })[0]
      Igual "$($f.N) : $k" $e $l.E
    }
    if ($f.Texto) { Igual "$($f.N) : el texto de prueba-local" $f.Texto (@($fases | Where-Object { $_.Clave -ceq 'local' })[0].Texto) }
    if ($f.Cuenta) { Comprueba "$($f.N) : la cuenta de prueba-local" (@($fases | Where-Object { $_.Clave -ceq 'local' })[0].Cuenta -match ('^' + $f.Cuenta + '$')) (@($fases | Where-Object { $_.Clave -ceq 'local' })[0].Cuenta) }
    $est = [regex]::Match($x.I, '(?s)<div class="estado[^"]*">.*?</div>').Value
    Comprueba "$($f.N) : el estado de arriba" ($est -match $f.Arriba) $est
    if ($f.N -like 'corregir, comparando*') { Comprueba 'y no dice que la pasada ha terminado' ($est -notmatch 'La pasada ha terminado') $est }
  }
}

$Pruebas['119 (P2) portada: con fin sale Duro y la duracion de creado a fin; sin fin, Lleva como siempre'] = {
  $s = Local-Salida 'p2-duro'
  $x = Local-Con $s @{ fin = '2026-11-18T06:35:00' }
  Comprueba 'con fin: Duro, de creado a fin' ($x.I -match '<dt>Dur.</dt><dd>1 h 35 min</dd>' -and $x.I -notmatch '<dt>Lleva</dt>') ([regex]::Match($x.I, '(?s)<dl class="ficha">.*?</dl>').Value)
  $x = Local-Con $s @{ fin = '' }
  Comprueba 'sin fin: Lleva, de creado a actualizado' ($x.I -match '<dt>Lleva</dt><dd>20 min</dd>' -and $x.I -notmatch '<dt>Dur') ([regex]::Match($x.I, '(?s)<dl class="ficha">.*?</dl>').Value)
}

$Pruebas['120 (P2) portada, Que es cada fichero: datos/prueba-local.json, la carpeta prueba-local y registros/prueba-local.log, cada uno con su frase y solo si existen'] = {
  $s = Local-Salida 'p2-ficheros'
  $x = Local-Con $s
  $f = [regex]::Match($x.I, '(?s)<ul class="ficheros">.*?</ul>').Value
  Comprueba 'sin ellos no salen' ($f -notmatch 'prueba-local') $f
  Escribe $s 'prueba-local/arnes/dejado.txt' 'x'
  Escribe $s 'registros/prueba-local.log' 'registro'
  $x = Local-Con $s @{} (Local-Json)
  $f = [regex]::Match($x.I, '(?s)<ul class="ficheros">.*?</ul>').Value
  foreach ($n in @('datos/prueba-local.json', 'prueba-local', 'registros/prueba-local.log')) {
    Comprueba "$n sale con su frase" ($f -match ('(?s)<li>(?:(?!</li>).)*<code>' + [regex]::Escape($n) + '</code></p><p>[^<]{20,}</p>')) $f
  }
  $p3 = [regex]::Match($f, '(?s)<li>(?:(?!</li>).)*3-original-vs-migrado\.html.*?</li>').Value
  Comprueba 'la frase de la pagina 3 dice las dos comparaciones, no "tal como llego"' ($p3 -match 'ejecutando los dos' -and $p3 -match 'lectura de la IA' -and $p3 -notmatch 'tal como lleg') $p3
}

$Pruebas['121 (P2) pagina 4: cada area con commits dice con cuantos hallazgos empezo y con cuantos acabo, y lo que aparecio o se fue con los arreglos de otros pasos; sin asuntos que casen no hay linea'] = {
  $antes = @(1..113 | ForEach-Object { Hallazgo 'calidad' 'error' "src/main/java/C$_.java" $_ "calidad $_" }) + @((Hallazgo 'estructura' 'error' 'src/main/java/A.java' 1 'A suelta'), (Hallazgo 'estructura' 'error' 'src/main/java/B.java' 2 'B suelta'))
  $despues = @(Hallazgo 'tests' 'aviso' 'src/test/java' 0 'no hay tests')
  function Commit([string]$Paso, [string]$Asunto) { return [ordered]@{ hash = 'abc1234'; paso = $Paso; asunto = $Asunto } }
  $corr = [ordered]@{
    completa = $true; codigo = 0; rama = 'rescate/main-20260101-0000'; base = 'main'
    commits = @(
      (Commit 'hexagonal' 'rescate(hexagonal): lote 1, hallazgos 5 a 4'), (Commit 'hexagonal' 'rescate(hexagonal): lote 2, hallazgos 4 a 3'), (Commit 'hexagonal' 'rescate(hexagonal): lote 3, hallazgos 3 a 2'),
      (Commit 'hexagonal' 'rescate(hexagonal): lote 4, hallazgos 2 a 1'), (Commit 'hexagonal' 'rescate(hexagonal): lote 5, hallazgos 1 a 0'),
      (Commit 'calidad' 'rescate(calidad): lote 1, hallazgos 32 a 30'), (Commit 'calidad' 'rescate(calidad): lote 2, hallazgos 30 a 1'), (Commit 'calidad' 'rescate(calidad): lote 3, hallazgos 1 a 0'),
      (Commit 'estructura' 'rescate(estructura): lote 1, hallazgos 2 a 1'),
      (Commit 'config' 'arreglo a mano de la configuracion'), (Commit 'config' 'rescate(config): sin lote'))
    atascados = @(); resueltos = @(); variablesNuevas = @()
  }
  $x = Correccion-Con (Corrida-Dos $GuionBase).E 'p2-durante' $antes $despues $corr
  $h = Grupo-De $x.P4 'hexagonal'
  Comprueba 'hexagonal (0 errores antes): empezo con 5, acabo con 0, en 5 commits, y los 5 aparecieron con otros pasos' ((Texto-De $h) -match 'Durante la correcci.n, este paso empez. con 5 y acab. con 0, en 5 commits\. 5 aparecieron con los arreglos de otros pasos\.') (Texto-De $h)
  Comprueba 'la linea va bajo la cabecera y antes de los arreglos' ($h.IndexOf('</header>') -ge 0 -and $h.IndexOf('</header>') -lt $h.IndexOf('Durante la correcci') -and $h.IndexOf('Durante la correcci') -lt $h.IndexOf('Arreglos hechos')) $h
  $q = Grupo-De $x.P4 'calidad'
  Comprueba 'calidad (113 antes): empezo con 32, acabo con 0, en 3 commits, y 81 se fueron antes' ((Texto-De $q) -match 'Durante la correcci.n, este paso empez. con 32 y acab. con 0, en 3 commits\. 81 se fueron antes, con los arreglos de otros pasos\.' -and $q -notmatch 'aparecieron') (Texto-De $q)
  $e = Grupo-De $x.P4 'estructura'
  Comprueba 'estructura (2 antes, empezo con 2): sin frase de otros pasos y con un commit en singular' ((Texto-De $e) -match 'Durante la correcci.n, este paso empez. con 2 y acab. con 1, en 1 commit\.' -and $e -notmatch 'aparecieron|se fueron') (Texto-De $e)
  $c = Grupo-De $x.P4 'config'
  Comprueba 'config (asuntos que no casan): sin linea' ($c.Length -gt 0 -and $c -notmatch 'Durante la correcci') $c
}

$Pruebas['122 (P2) pagina 4: con uno solo que aparecio o se fue, la frase va en singular'] = {
  $antes = @((Hallazgo 'estructura' 'error' 'src/main/java/A.java' 1 'A suelta'), (Hallazgo 'estructura' 'error' 'src/main/java/B.java' 2 'B suelta'))
  $despues = @(Hallazgo 'tests' 'aviso' 'src/test/java' 0 'no hay tests')
  function Commit([string]$Paso, [string]$Asunto) { return [ordered]@{ hash = 'abc1234'; paso = $Paso; asunto = $Asunto } }
  $corr = [ordered]@{
    completa = $true; codigo = 0; rama = 'rescate/main-20260101-0000'; base = 'main'
    commits = @((Commit 'hexagonal' 'rescate(hexagonal): lote 1, hallazgos 1 a 0'), (Commit 'estructura' 'rescate(estructura): lote 1, hallazgos 1 a 0'))
    atascados = @(); resueltos = @(); variablesNuevas = @()
  }
  $x = Correccion-Con (Corrida-Dos $GuionBase).E 'p2-durante-uno' $antes $despues $corr
  $h = Texto-De (Grupo-De $x.P4 'hexagonal')
  Comprueba 'hexagonal (0 antes, empezo con 1): 1 aparecio' ($h -match 'en 1 commit\. 1 apareci. con los arreglos de otros pasos\.') $h
  $e = Texto-De (Grupo-De $x.P4 'estructura')
  Comprueba 'estructura (2 antes, empezo con 1): 1 se fue antes' ($e -match 'en 1 commit\. 1 se fue antes, con los arreglos de otros pasos\.') $e
}

$Pruebas['112 (E2) el banco nunca ejecuta el prueba-local.ps1 de verdad: ninguna carpeta *-prueba-local en el banco ni debajo de los escenarios'] = {
  $c = @(Get-ChildItem -LiteralPath $Dir -Directory -Recurse -Depth 2 -Filter '*-prueba-local')
  Igual 'ninguna carpeta *-prueba-local' '' ($c | ForEach-Object { $_.FullName }) 
}

# ============================ M16: EL SIGUIENTE PASO EN LA PORTADA ============================
# Lo que dice Get-SiguientePaso (informe.ps1) de un estado.json ($Est, tabla) y de los datos del informe ($D: Correccion, PruebaLocal y
# Diag.Errores), con un script de prueba que carga las tres bibliotecas. Devuelve el objeto que da la funcion.
function Siguiente($Est, $D = @{}) {
  $carpeta = Join-Path $Dir 'siguiente'
  Escribe $carpeta 'est.json' (ConvertTo-Json -InputObject $Est -Depth 8)
  Escribe $carpeta 'd.json' (ConvertTo-Json -InputObject $D -Depth 8)
  $codigo = "`$est = Read-Json '" + (Join-Path $carpeta 'est.json') + "'`n`$d = Read-Json '" + (Join-Path $carpeta 'd.json') + "'`n'SIGUIENTE=' + (ConvertTo-Json -InputObject (Get-SiguientePaso `$est `$d) -Compress -Depth 4)`n"
  $r = En-Biblioteca 'siguiente' $codigo -ConInforme
  $l = @($r.Salida -split "`n" | Where-Object { $_ -match '^SIGUIENTE=' })
  if ($l.Count -eq 0) { Comprueba 'Get-SiguientePaso devuelve algo' $false (Cola $r.Salida); return [pscustomobject]@{ Caso = ''; N = 0; Comando = ''; Fase = ''; Motivo = ''; Detalle = '' } }
  return ($l[0].Substring(10).TrimEnd("`r") | ConvertFrom-Json)
}

# Un estado.json de una pasada acabada con la respuesta parar y la prueba en local hecha; $Cambios lo pisa campo a campo.
function Estado-Siguiente([hashtable]$Cambios = @{}) {
  $e = [ordered]@{
    version = 1; batch = 'batch-recibos'; legacy = 'C:\ruta\original'; migrado = 'C:\ruta\migrado'; plantilla = 'C:\ruta\referencia'
    worktree = 'C:\ruta\migrado-rescate'; rama = 'rescate/feat-recibos-20261118-0900'; ramaOrigen = 'feat/recibos'; javaLegacy = ''
    modelo = 'claude-sonnet-5.5'; aptitud = 'claude-sonnet-5.5'; respuesta = 'parar'; fase = 'hecha'
    creado = '2026-11-18T09:00:00'; actualizado = '2026-11-18T10:00:00'; fin = '2026-11-18T10:00:00'; parada = $null
    pruebaLocal = [ordered]@{ resultado = 'hecha'; codigo = 0; minutos = 3.2; detalle = ''; registro = 'registros/prueba-local.log' }
  }
  foreach ($k in $Cambios.Keys) { $e[$k] = $Cambios[$k] }
  return $e
}

$ComandoSiguiente = '.\migracion.ps1 -Legacy "C:\ruta\original" -Migrado "C:\ruta\migrado" -Plantilla "C:\ruta\referencia" -Modelo claude-sonnet-5.5'

# Los datos del informe: la prueba en local con $Distintos casos distintos y 2 iguales, la correccion (o $null) y los errores del diagnostico.
function Datos-Siguiente([int]$Distintos = 0, $Correccion = $null, [int]$Errores = 0, [int]$Avisos = 0) {
  $casos = @((Caso-Local 'cargaJob' 'caso-01' 'Recibo correcto' 'igual'), (Caso-Local 'cargaJob' 'caso-02' 'Recibo sin importe' 'igual'))
  for ($i = 1; $i -le $Distintos; $i++) { $casos += (Caso-Local 'cargaJob' ('caso-d' + $i) ('Distinto ' + $i) 'distinto') }
  return [ordered]@{
    Correccion = $Correccion
    PruebaLocal = [ordered]@{ jobs = @([ordered]@{ job = 'cargaJob'; casos = $casos.Count; iguales = 2; distintos = $Distintos; sinProbar = 0 }); casos = $casos }
    Diag = [ordered]@{ Errores = $Errores; Avisos = $Avisos }
  }
}

function Correccion-Siguiente([bool]$Completa = $true, [int]$Commits = 2) {
  return [ordered]@{
    completa = $Completa; codigo = 0; rama = 'rescate/feat-recibos-20261118-0900'; base = 'feat/recibos'
    commits = @(if ($Commits -gt 0) { 1..$Commits | ForEach-Object { [ordered]@{ hash = ('abc123' + $_); paso = 'estructura'; asunto = 'rescate(estructura): lote 1' } } }); atascados = @(); resueltos = @(); variablesNuevas = @()
  }
}

$Pruebas['m16 siguiente: fila 1, fin vacio: sigue trabajando, con la fase y el comando de la pasada (comillas en las rutas, -Si o -SoloInforme, -JavaLegacy); gana a todo lo demas'] = {
  $s = Siguiente (Estado-Siguiente @{ fin = ''; fase = 'mapa' }) (Datos-Siguiente)
  Igual 'caso corriendo' 'corriendo' $s.Caso
  Igual 'dice la fase' 'mapa' $s.Fase
  Igual 'el comando de la pasada, con -SoloInforme' ($ComandoSiguiente + ' -SoloInforme') $s.Comando
  $s = Siguiente (Estado-Siguiente @{ fin = ''; fase = 'correccion'; respuesta = 'corregir'; javaLegacy = 'C:\jdk 8' }) (Datos-Siguiente)
  Igual 'con la respuesta corregir, -Si, y -JavaLegacy con comillas' ($ComandoSiguiente + ' -Si -JavaLegacy "C:\jdk 8"') $s.Comando
  $s = Siguiente (Estado-Siguiente @{ fin = ''; modelo = ''; migrado = 'C:\mi ruta\migrado' }) (Datos-Siguiente)
  Igual 'sin modelo no hay -Modelo, y una ruta con espacios va entre comillas' '.\migracion.ps1 -Legacy "C:\ruta\original" -Migrado "C:\mi ruta\migrado" -Plantilla "C:\ruta\referencia" -SoloInforme' $s.Comando
  $p = [ordered]@{ motivo = 'copilot-no-responde'; detalle = 'x'; registro = 'r'; ayuda = 'a' }
  $s = Siguiente (Estado-Siguiente @{ fin = ''; parada = $p }) (Datos-Siguiente 2 (Correccion-Siguiente) 3)
  Igual 'con parada y casos distintos, todavia gana corriendo' 'corriendo' $s.Caso
}

$Pruebas['m16 siguiente: fila 2, parada: el motivo y el comando de la pasada, para cada motivo de la tabla de FLUJO.md y uno que no esta'] = {
  foreach ($m in @('copilot-no-responde', 'tope-de-tiempo', 'no-compila', 'lotes-deshechos', 'guardas', 'git', 'motor', 'error-interno', 'motivo-nuevo')) {
    $p = [ordered]@{ motivo = $m; detalle = "detalle de $m"; registro = "C:\ruta\registro-$m.log"; ayuda = 'ayuda' }
    $s = Siguiente (Estado-Siguiente @{ parada = $p; respuesta = 'corregir' }) (Datos-Siguiente 2 (Correccion-Siguiente))
    Comprueba "$m : caso parada con su motivo y el comando de la pasada" ($s.Caso -ceq 'parada' -and $s.Motivo -ceq $m -and $s.Comando -ceq ($ComandoSiguiente + ' -Si')) ($s | ConvertTo-Json -Compress)
  }
  $s = Siguiente (Estado-Siguiente @{ parada = [ordered]@{ motivo = 'no-compila'; detalle = 'd'; registro = 'C:\r.log'; ayuda = 'a' } }) (Datos-Siguiente)
  Igual 'lleva el detalle y el registro de la parada' 'd|C:\r.log|C:\ruta\migrado-rescate' "$($s.Detalle)|$($s.Registro)|$($s.Worktree)"
}

$Pruebas['m16 siguiente: fila 3, casos distintos y hubo correccion: deshacer con prueba-local.ps1 -Desde <ramaOrigen> -Deshacer (y -JavaLegacy si lo hay)'] = {
  $s = Siguiente (Estado-Siguiente @{ respuesta = 'corregir' }) (Datos-Siguiente 2 (Correccion-Siguiente))
  Igual 'caso distinto-corregido' 'distinto-corregido' $s.Caso
  Igual 'cuenta los casos distintos' 2 $s.N
  Igual 'el comando' '.\prueba-local.ps1 -Legacy "C:\ruta\original" -Migrado "C:\ruta\migrado" -Desde feat/recibos -Deshacer' $s.Comando
  $s = Siguiente (Estado-Siguiente @{ respuesta = 'corregir'; javaLegacy = 'C:\jdk8' }) (Datos-Siguiente 1 (Correccion-Siguiente))
  Igual 'con -JavaLegacy' '.\prueba-local.ps1 -Legacy "C:\ruta\original" -Migrado "C:\ruta\migrado" -Desde feat/recibos -Deshacer -JavaLegacy "C:\jdk8"' $s.Comando
  $s = Siguiente (Estado-Siguiente @{ respuesta = 'corregir'; ramaOrigen = '' }) (Datos-Siguiente 1 (Correccion-Siguiente))
  Igual 'un estado.json de antes, sin ramaOrigen: la base de correcciones.json' 'feat/recibos' ([regex]::Match($s.Comando, '-Desde (\S+)').Groups[1].Value)
}

$Pruebas['m16 siguiente: fila 4, casos distintos sin correccion: mirarlos en la pagina 3, sin comando'] = {
  $s = Siguiente (Estado-Siguiente) (Datos-Siguiente 3)
  Igual 'caso distinto' 'distinto' $s.Caso
  Igual 'cuenta los casos' 3 $s.N
  Igual 'sin comando' '' $s.Comando
  $s = Siguiente (Estado-Siguiente @{ respuesta = 'corregir' }) (Datos-Siguiente 1 (Correccion-Siguiente $true 0))
  Igual 'con una correccion sin ningun commit tambien es sin correccion' 'distinto' $s.Caso
  $s = Siguiente (Estado-Siguiente) (Datos-Siguiente 2 $null 4)
  Igual 'gana a los problemas de la pagina 2' 'distinto' $s.Caso
}

$Pruebas['m16 siguiente: fila 5, la prueba en local fallo o se salto: su detalle; con el JDK del original, -JavaLegacy con la ruta del JDK'] = {
  $fallo = [ordered]@{ resultado = 'fallo'; codigo = 1; minutos = 1.5; detalle = 'dos / tres'; registro = 'registros/prueba-local.log' }
  $s = Siguiente (Estado-Siguiente @{ pruebaLocal = $fallo }) (@{})
  Igual 'caso local-fallo' 'local-fallo' $s.Caso
  Igual 'con su detalle' 'dos / tres' $s.Detalle
  Igual 'el comando de la pasada' ($ComandoSiguiente + ' -SoloInforme') $s.Comando
  $jdk = [ordered]@{ resultado = 'fallo'; codigo = 1; minutos = 1.5; detalle = 'no compila'; jdkOriginal = $true; registro = 'registros/prueba-local.log' }
  $s = Siguiente (Estado-Siguiente @{ pruebaLocal = $jdk }) (@{})
  Igual 'caso local-jdk' 'local-jdk' $s.Caso
  Igual 'el comando de la pasada con -JavaLegacy y la ruta del JDK del original' ($ComandoSiguiente + ' -SoloInforme -JavaLegacy "C:\ruta\jdk-del-original"') $s.Comando
  $s = Siguiente (Estado-Siguiente @{ pruebaLocal = $fallo; javaLegacy = 'C:\jdk8' }) (@{})
  Igual 'con -JavaLegacy ya dado, el comando lo mantiene' ($ComandoSiguiente + ' -SoloInforme -JavaLegacy "C:\jdk8"') $s.Comando
  $salto = [ordered]@{ resultado = 'saltada'; codigo = $null; minutos = 0; detalle = ''; registro = '' }
  $s = Siguiente (Estado-Siguiente @{ pruebaLocal = $salto; respuesta = 'corregir' }) (Datos-Siguiente 0 (Correccion-Siguiente))
  Igual 'saltada: caso local-saltada' 'local-saltada' $s.Caso
  Igual 'y el comando de la pasada, que la hace' ($ComandoSiguiente + ' -Si') $s.Comando
  $s = Siguiente (Estado-Siguiente @{ pruebaLocal = $fallo }) (Datos-Siguiente 0 $null 5)
  Igual 'gana a los problemas de la pagina 2' 'local-fallo' $s.Caso
}

$Pruebas['m16 siguiente: fila 6, respuesta parar y quedan problemas: corregirlos con el comando de la pasada con -Si en vez de -SoloInforme'] = {
  $s = Siguiente (Estado-Siguiente) (Datos-Siguiente 0 $null 3 2)
  Igual 'caso parar-con-problemas' 'parar-con-problemas' $s.Caso
  Igual 'cuenta los errores de la pagina 2' 3 $s.N
  Igual 'el comando, con -Si' ($ComandoSiguiente + ' -Si') $s.Comando
  Comprueba 'y sin -SoloInforme' ($s.Comando -notmatch 'SoloInforme')
  $s = Siguiente (Estado-Siguiente @{ javaLegacy = 'C:\jdk8' }) (Datos-Siguiente 0 $null 1)
  Igual 'con -JavaLegacy' ($ComandoSiguiente + ' -Si -JavaLegacy "C:\jdk8"') $s.Comando
  $s = Siguiente (Estado-Siguiente) (Datos-Siguiente 0 $null 0 4)
  Igual 'con solo avisos no hay nada que corregir: cae a pre' 'pre' $s.Caso
}

$Pruebas['m16 siguiente: fila 7, correccion completa: las 3 lineas de git del paso 4 de FLUJO.md con la rama de origen y la de rescate reales'] = {
  $s = Siguiente (Estado-Siguiente @{ respuesta = 'corregir' }) (Datos-Siguiente 0 (Correccion-Siguiente) 0)
  Igual 'caso corregido' 'corregido' $s.Caso
  $esperado = @(
    'git -C "C:\ruta\migrado" log --oneline feat/recibos..rescate/feat-recibos-20261118-0900',
    'git -C "C:\ruta\migrado" diff --stat feat/recibos...rescate/feat-recibos-20261118-0900',
    'git -C "C:\ruta\migrado" merge rescate/feat-recibos-20261118-0900') -join "`n"
  Igual 'las 3 lineas de git' $esperado ($s.Comando -replace "`r", '')
  $s = Siguiente (Estado-Siguiente @{ respuesta = 'corregir'; ramaOrigen = '' }) (Datos-Siguiente 0 (Correccion-Siguiente))
  Comprueba 'sin ramaOrigen, la base de correcciones.json' ($s.Comando -match 'log --oneline feat/recibos\.\.rescate') $s.Comando
  $s = Siguiente (Estado-Siguiente @{ respuesta = 'corregir' }) (Datos-Siguiente 2 (Correccion-Siguiente) 0)
  Igual 'con casos distintos gana la fila 3' 'distinto-corregido' $s.Caso
  $s = Siguiente (Estado-Siguiente @{ respuesta = 'corregir' }) (Datos-Siguiente 0 (Correccion-Siguiente $true 0))
  Igual 'completa pero sin ningun commit: no hay nada que traer, cae a pre' 'pre' $s.Caso
}

$Pruebas['m16 siguiente: fila 8 y casos sin fila: nada de lo anterior es probarlo en pre; una pasada cortada con -Limite dice que se relance'] = {
  $s = Siguiente (Estado-Siguiente) (Datos-Siguiente 0 $null 0 0)
  Igual 'caso pre' 'pre' $s.Caso
  Igual 'sin comando' '' $s.Comando
  $s = Siguiente (Estado-Siguiente @{ respuesta = 'corregir' }) (Datos-Siguiente 0 (Correccion-Siguiente $false 0) 0 0)
  Igual 'una correccion no completa, sin parada, tambien' 'pre' $s.Caso
  $s = Siguiente (Estado-Siguiente @{ fase = 'resumen'; pruebaLocal = $null }) (@{})
  Igual 'fin escrito y fase sin acabar (-Limite): caso cortada' 'cortada' $s.Caso
  Igual 'con la fase' 'resumen' $s.Fase
  Igual 'y el comando de la pasada' ($ComandoSiguiente + ' -SoloInforme') $s.Comando
}

$Pruebas['m16 siguiente: migracion.ps1 guarda ramaOrigen y javaLegacy en estado.json, y si el original no compila con el JDK de Maven, pruebaLocal.jdkOriginal'] = {
  $e = Nuevo-Escenario 'siguiente-estado' @('Clase1')
  $r = Migra $e (Basicos $e)
  Igual 'sale con 0' 0 $r.Codigo
  $s = Estado $e
  Igual 'ramaOrigen es la rama del migrado' 'main' $s.ramaOrigen
  Comprueba 'javaLegacy vacio sin -JavaLegacy' ($null -ne $s.javaLegacy -and $s.javaLegacy -ceq '') ($s | ConvertTo-Json -Compress)
  $r = Migra $e ((Basicos $e) + @('-JavaLegacy', 'C:\jdk8'))
  Igual 'con -JavaLegacy sale con 0' 0 $r.Codigo
  Igual 'javaLegacy es el valor dado' 'C:\jdk8' (Estado $e).javaLegacy
  $o = Orden-Base
  $l = [ordered]@{ codigo = 1; salida = @('El original no compila con el JDK de Maven. Vuelve a lanzar con -JavaLegacy <carpeta del JDK del original (8 u 11)>. Maven dice:', 'uno', 'dos', 'tres') }
  $r = Migra-Motor $e $o (Corrige $e) '' $l
  Igual 'con el JDK mal sale con 0' 0 $r.Codigo
  $p = (Estado $e).pruebaLocal
  Igual 'fallo' 'fallo' $p.resultado
  Igual 'jdkOriginal true' 'True' "$($p.jdkOriginal)"
  Igual 'y el detalle sigue siendo las 3 ultimas lineas' 'uno / dos / tres' $p.detalle
  $l = [ordered]@{ codigo = 1; salida = @('Otro fallo', 'uno') }
  $r = Migra-Motor $e $o (Corrige $e) '' $l
  Igual 'otro fallo: jdkOriginal false' 'False' "$((Estado $e).pruebaLocal.jdkOriginal)"
}

# El texto de un trozo de pagina, sin etiquetas, con las entidades HTML decodificadas y los espacios juntos.
function Texto-Plano([string]$Html) { return [System.Net.WebUtility]::HtmlDecode((Texto-De $Html)) }

# Una carpeta de salida minima (solo datos\estado.json y los datos que se den) para montar la portada sin una corrida.
function Salida-Siguiente([string]$Nombre, $Est, $Datos = @{}) {
  $s = Join-Path (Join-Path $Dir $Nombre) 'migracion-batch'
  Escribe $s 'datos/estado.json' (ConvertTo-Json -InputObject $Est -Depth 8)
  foreach ($k in $Datos.Keys) { Escribe $s ('datos/' + $k) $(if ($Datos[$k] -is [string]) { $Datos[$k] } else { ConvertTo-Json -InputObject $Datos[$k] -Depth 8 }) }
  $g = Genera-Informes $s
  Comprueba "$Nombre : Write-Informes sale bien" ($g.Codigo -eq 0 -and $g.Salida -match 'INFORMES-OK') (Cola $g.Salida)
  return (Pagina $s 'index.html')
}

$Pruebas['m16 siguiente: la portada lleva el recuadro arriba (antes de la ficha y de Lo que te toca), uno solo, con el comando escapado, la linea de FLUJO.md y sin JavaScript'] = {
  $migrado = 'C:\ruta\a&b <x>'
  $est = Estado-Siguiente @{ fin = ''; fase = 'mapa'; migrado = $migrado }
  $i = Salida-Siguiente 'siguiente-corriendo' $est
  $sec = Panel-De $i 'siguiente-paso'
  Comprueba 'hay un recuadro con id siguiente-paso y su h2' ($sec.Length -gt 0 -and $sec -match '<h2[^>]*>Siguiente paso</h2>') $i
  Igual 'y solo uno' 1 ([regex]::Matches($i, 'id="siguiente-paso"').Count)
  $a = $i.IndexOf('id="siguiente-paso"')
  Comprueba 'va antes de la ficha y de Lo que te toca' ($a -gt 0 -and $a -lt $i.IndexOf('<dl class="ficha">') -and $a -lt $i.IndexOf('id="lo-que-te-toca"')) "$a"
  $t = Texto-Plano $sec
  Comprueba 'dice que sigue trabajando, la fase y que no hagas nada' ($t -match 'Sigue trabajando: va por la fase mapa\. No hagas nada\. Si la consola se ha cerrado, lanza el mismo comando') $t
  $cmd = [regex]::Match($sec, '(?s)<pre class="cmd">(.*?)</pre>').Groups[1].Value
  Igual 'el comando va en un pre.cmd y escapado' ('.\migracion.ps1 -Legacy &quot;C:\ruta\original&quot; -Migrado &quot;C:\ruta\a&amp;b &lt;x&gt;&quot; -Plantilla &quot;C:\ruta\referencia&quot; -Modelo claude-sonnet-5.5 -SoloInforme') $cmd
  Comprueba 'debajo, la linea del flujo completo' ($i -match '(?s)</section>\s*<p[^>]*>El flujo completo est. en <code>FLUJO\.md</code>, junto a los scripts\.</p>' -and $i.IndexOf('FLUJO.md') -lt $i.IndexOf('<dl class="ficha">'))
  Comprueba 'sin JavaScript ni nada externo' ($i -notmatch '<script' -and $i -notmatch 'https?://')
}

$Pruebas['m16 siguiente: la portada de una parada, de una pasada con problemas por corregir y de una corregida dicen su paso, con acentos y con su comando'] = {
  $parada = [ordered]@{ motivo = 'no-compila'; detalle = 'Despues de corregir no compila.'; registro = 'C:\ruta\migrado\migracion-batch\registros\correccion.log'; ayuda = 'Pega esto.' }
  $i = Salida-Siguiente 'siguiente-parada' (Estado-Siguiente @{ parada = $parada; respuesta = 'corregir' })
  $t = Texto-Plano (Panel-De $i 'siguiente-paso')
  Comprueba 'parada no-compila: el motivo y que arregles en la copia de rescate' ($t -match 'no compila' -and $t -match 'C:\\ruta\\migrado-rescate' -and $t -match 'haz commit' -and $t -match 'relanza') $t
  Comprueba 'con el comando de la pasada con -Si' ($t -match '-Migrado "C:\\ruta\\migrado" .* -Si$') $t
  $h = Hallazgo 'estructura' 'error' 'src/main/java/A.java' 3 'clase suelta A'
  $i = Salida-Siguiente 'siguiente-parar' (Estado-Siguiente) @{ 'hallazgos-antes.json' = @($h, $h, $h); 'diagnostico-antes.md' = (Md-Diagnostico 'compila: SI | tests: OK'); 'prueba-local.json' = (Datos-Siguiente 0).PruebaLocal }
  $t = Texto-Plano (Panel-De $i 'siguiente-paso')
  Comprueba 'parar con 3 problemas: lo dice y propone -Si' ($t -match 'Tu c.digo da lo mismo que el original\. Para corregir los 3 problemas de la p.gina 2' -and $t -match ' -Si$' -and $t -notmatch 'SoloInforme') $t
  Comprueba 'y la pagina 2 enlazada' ((Panel-De $i 'siguiente-paso') -match 'href="2-problemas\.html"')
  $c = Correccion-Siguiente
  $i = Salida-Siguiente 'siguiente-corregido' (Estado-Siguiente @{ respuesta = 'corregir' }) @{ 'correcciones.json' = $c; 'prueba-local.json' = (Datos-Siguiente 0).PruebaLocal }
  $t = Texto-Plano (Panel-De $i 'siguiente-paso')
  Comprueba 'corregido: revisa y trae los cambios, con las 3 lineas de git' ($t -match 'Revisa los cambios y tr.elos a tu rama' -and $t -match 'log --oneline feat/recibos\.\.rescate/feat-recibos-20261118-0900' -and $t -match 'diff --stat feat/recibos\.\.\.rescate' -and $t -match 'merge rescate/feat-recibos-20261118-0900') $t
  $i = Salida-Siguiente 'siguiente-pre' (Estado-Siguiente) @{ 'prueba-local.json' = (Datos-Siguiente 0).PruebaLocal }
  $s = Panel-De $i 'siguiente-paso'
  Comprueba 'pre: sin comando y con la pagina 1' ($s -notmatch '<pre' -and (Texto-Plano $s) -match 'Pru.balo en pre: cada job tiene su guion en la p.gina 1' -and $s -match 'href="1-batch-original\.html"') $s
}

# ===================== M15: RESUMEN Y FICHAS DE JOB CONCRETOS =====================
# Lo que lleva el resumen de cada job (de datos\jobs\<job>.json), el tope por job y las frases de relleno.
$Pruebas['m15 resumen: el prompt lleva por job lo que necesita, lo que deja, a quien lo envia y sus reglas, y no lo tecnico'] = {
  $codigo = @'
$Datos = '{{DIR}}'
$mapa = [pscustomobject]@{ jobs = @([pscustomobject]@{ job = 'cargaRecibosJob' }, [pscustomobject]@{ job = 'informeCobrosJob' }, [pscustomobject]@{ job = 'avisosJob' }) }
function Item([string]$Texto, [string]$Tipo, [bool]$Tecnico = $false) {
  $x = [ordered]@{ tipo = $Tipo; texto = $Texto; ref = 'clase-aaaaaaaa#0'; clase = 'CargaReader'; fichero = 'a.java'; linea = 1; cita = 'x'; probado = $true }
  if ($Tecnico) { $x['tecnico'] = $true }
  return $x
}
function Job([string]$Nombre, [bool]$Hecha, $L) {
  $o = [ordered]@{ job = $Nombre }
  if ($Hecha) { $o['titulo'] = "Titulo $Nombre"; $o['paraQue'] = "Sirve para $Nombre."; $o['pasos'] = @([ordered]@{ titulo = 'Leer el fichero'; texto = 'Lee.'; refs = @() }) }
  foreach ($k in @('necesita', 'produce', 'conexiones', 'reglas', 'siFalla')) { $o[$k] = @(); if ($L.ContainsKey($k)) { $o[$k] = @($L[$k]) } }
  $o['dudas'] = @()
  if ($Hecha) { $o['redaccion'] = 'hecha' } else { $o['redaccion'] = 'atascada' }
  Write-Json (Get-RutaJob $Nombre) $o
}
Job 'cargaRecibosJob' $true @{
  necesita = @((Item 'Fichero de recibos del banco en la carpeta de entrada' 'entrada-fichero'), (Item 'Tabla de clientes' 'tabla-lee'), (Item 'Lee el parametro RUTA_ENTRADA con GestorRecibos' 'parametro' $true))
  produce = @((Item 'Tabla de recibos pendientes de cobro' 'tabla-escribe'), (Item 'Fichero de recibos rechazados' 'salida-fichero'))
  conexiones = @((Item 'Envia el fichero de rechazados al servidor del banco por SFTP' 'sftp'))
  reglas = @((Item 'Rechaza el recibo cuyo importe es menor de 5 euros' 'regla'), (Item 'Un recibo duplicado se descarta' 'regla'))
  siFalla = @((Item 'Si falla el envio avisa por correo al equipo de cobros' 'error'))
}
Job 'informeCobrosJob' $true @{}
Job 'avisosJob' $false @{ reglas = @((Item 'Avisa solo a los clientes con deuda' 'regla')) }
$t = @(Get-TareasResumen $mapa $false)
'TAREAS=' + $t.Count
[System.IO.File]::WriteAllText((Join-Path $Datos 'datos-resumen.txt'), [string]$t[0].entradas.datos)
'FIN'
'@
  $d = Join-Path $Dir 'resumen-datos'
  $r = En-Biblioteca 'resumen-datos' $codigo.Replace('{{DIR}}', $d)
  Igual 'el script de prueba sale con 0' 0 $r.Codigo
  $txt = ''
  if (Test-Path -LiteralPath (Join-Path $d 'datos-resumen.txt')) { $txt = [System.IO.File]::ReadAllText((Join-Path $d 'datos-resumen.txt')) }
  Comprueba 'hay una tarea con los datos de los jobs' ($txt -match '(?m)^JOB: cargaRecibosJob\r?$' -and $txt -match '(?m)^JOB: informeCobrosJob\r?$') (Cola $r.Salida)
  $b = [regex]::Match($txt, '(?ms)^JOB: cargaRecibosJob.*?(?=\r?\nJOB: |\z)').Value
  Comprueba 'lo que necesita, con sus tablas y ficheros' ($b -match '(?m)^NECESITA:\r?$' -and $b.Contains('Fichero de recibos del banco en la carpeta de entrada') -and $b.Contains('Tabla de clientes')) $b
  Comprueba 'lo que deja' ($b -match '(?m)^DEJA:\r?$' -and $b.Contains('Tabla de recibos pendientes de cobro') -and $b.Contains('Fichero de recibos rechazados')) $b
  Comprueba 'a quien lo envia' ($b -match '(?m)^SE ENVIA A:\r?$' -and $b.Contains('servidor del banco por SFTP')) $b
  Comprueba 'sus reglas' ($b -match '(?m)^REGLAS:\r?$' -and $b.Contains('menor de 5 euros') -and $b.Contains('duplicado')) $b
  Comprueba 'cada dato en su linea corta (con guion)' ($b -match '(?m)^- Tabla de clientes\r?$') $b
  Comprueba 'un dato tecnico (que nombra una clase) no va' (-not $b.Contains('GestorRecibos') -and -not $b.Contains('RUTA_ENTRADA')) $b
  Comprueba 'de lo que pasa si falla no se manda nada (no esta en lo que se pide)' (-not $b.Contains('avisa por correo')) $b
  Comprueba 'lleva tambien el titulo, el para que y los pasos de antes' ($b.Contains('Titulo cargaRecibosJob') -and $b.Contains('Sirve para cargaRecibosJob') -and $b.Contains('Leer el fichero')) $b
  $c = [regex]::Match($txt, '(?ms)^JOB: informeCobrosJob.*?(?=\r?\nJOB: |\z)').Value
  Comprueba 'lo que no hay se dice "no consta", no se deja en blanco' ($c -match '(?m)^NECESITA: no consta\r?$' -and $c -match '(?m)^DEJA: no consta\r?$' -and $c -match '(?m)^SE ENVIA A: no consta\r?$' -and $c -match '(?m)^REGLAS: no consta\r?$') $c
  $e = [regex]::Match($txt, '(?ms)^JOB: avisosJob.*?(?=\r?\nJOB: |\z)').Value
  Comprueba 'un job sin redaccion lleva igual sus listas del script' ($e.Contains('Sin redaccion') -and $e.Contains('Avisa solo a los clientes con deuda')) $e
}

$Pruebas['m15 resumen: el tope de caracteres por job se cumple y ninguna lista se queda sin sitio'] = {
  $codigo = @'
$Datos = '{{DIR}}'
$mapa = [pscustomobject]@{ jobs = @([pscustomobject]@{ job = 'cargaRecibosJob' }) }
'CFG=' + $Cfg.ResumenCaracteresJob
function Items([string]$Tipo, [string]$Que) {
  return @(1..30 | ForEach-Object { [ordered]@{ tipo = $Tipo; texto = ($Que + ' numero ' + $_ + ' ' + ('x' * 90)); ref = 'clase-aaaaaaaa#0'; clase = 'A'; fichero = 'a.java'; linea = 1; cita = 'x'; probado = $true } })
}
$o = [ordered]@{ job = 'cargaRecibosJob'; titulo = 'Carga'; paraQue = 'Carga.'; pasos = @([ordered]@{ titulo = 'Uno'; texto = 'Uno.'; refs = @() })
  necesita = (Items 'tabla-lee' 'Necesita'); produce = (Items 'tabla-escribe' 'Deja'); conexiones = (Items 'sftp' 'Envia'); reglas = (Items 'regla' 'Regla'); siFalla = @(); dudas = @(); redaccion = 'hecha' }
Write-Json (Get-RutaJob 'cargaRecibosJob') $o
foreach ($tope in @($Cfg.ResumenCaracteresJob, 500)) {
  $Cfg.ResumenCaracteresJob = $tope
  $t = @(Get-TareasResumen $mapa $false)
  $txt = [string]$t[0].entradas.datos
  $desde = $txt.IndexOf('NECESITA:')
  'TOPE' + $tope + '=' + ($txt.Length - $desde)
  'LISTAS' + $tope + '=' + (@('NECESITA:', 'DEJA:', 'SE ENVIA A:', 'REGLAS:' | Where-Object { $txt -match ('(?m)^' + $_ + '\r?$') }).Count)
  'PRIMERAS' + $tope + '=' + (@('Necesita numero 1 ', 'Deja numero 1 ', 'Envia numero 1 ', 'Regla numero 1 ' | Where-Object { $txt.Contains($_) }).Count)
}
'FIN'
'@
  $r = En-Biblioteca 'resumen-tope' $codigo.Replace('{{DIR}}', (Join-Path $Dir 'resumen-tope'))
  Igual 'el script de prueba sale con 0' 0 $r.Codigo
  $v = @{}
  foreach ($l in ($r.Salida -split "`n")) { if ($l -match '^(\w+)=(.*?)\r?$') { $v[$Matches[1]] = $Matches[2] } }
  Comprueba 'hay un tope por defecto (ResumenCaracteresJob) de entre 800 y 4000 caracteres' ($v['CFG'] -match '^\d+$' -and [int]$v['CFG'] -ge 800 -and [int]$v['CFG'] -le 4000) $v['CFG']
  $t0 = [int]$v['CFG']
  Comprueba 'con el tope por defecto, las listas del job caben' ($v["TOPE$t0"] -match '^\d+$' -and [int]$v["TOPE$t0"] -le $t0 -and [int]$v["TOPE$t0"] -gt 0) $v["TOPE$t0"]
  Comprueba 'con 500, las listas del job caben en 500 caracteres' ($v['TOPE500'] -match '^\d+$' -and [int]$v['TOPE500'] -gt 0 -and [int]$v['TOPE500'] -le 500) $v['TOPE500']
  Igual 'y con 500 salen las cuatro listas' '4' $v['LISTAS500']
  Igual 'y de cada una, su primer dato (ninguna se queda fuera por culpa de otra)' '4' $v['PRIMERAS500']
}

$Pruebas['m15 resumen: el resumen y la ficha de un job con una frase de relleno no valen y el motivo pide el dato concreto'] = {
  $codigo = @'
$Fuentes = @('CargaReader', 'GestorRecibos') | ForEach-Object { [pscustomobject]@{ BaseName = $_ } }
$o = [char]0xF3
$base = Join-Path '{{DIR}}' ([guid]::NewGuid().ToString('N').Substring(0, 6))
function Resumen([string]$Texto, [string]$Motivo = 'Va primero.', [string]$Definicion = 'Un grupo de recibos.') {
  $dir = Join-Path $base ('r' + [guid]::NewGuid().ToString('N').Substring(0, 6))
  [void](New-Item -ItemType Directory -Path (Join-Path $dir '.rescate/tareas') -Force)
  $x = [ordered]@{ resumen = $Texto; orden = @([ordered]@{ job = 'cargaRecibosJob'; motivo = $Motivo }); glosario = @([ordered]@{ termino = 'remesa'; definicion = $Definicion }) }
  [System.IO.File]::WriteAllText((Join-Path $dir '.rescate/tareas/resumen.json'), (ConvertTo-Json -InputObject $x -Depth 5))
  $t = [pscustomobject]@{ id = 'resumen'; entradas = [pscustomobject]@{ jobs = @('cargaRecibosJob') } }
  $r = Test-Resumen $t $dir
  if ($r.Ok) { return 'BIEN' }
  return ('MAL ' + $r.Motivo)
}
function Ficha([string]$ParaQue, [string]$Texto = 'Se lee el fichero que deja el banco.') {
  $dir = Join-Path $base ('f' + [guid]::NewGuid().ToString('N').Substring(0, 6))
  [void](New-Item -ItemType Directory -Path (Join-Path $dir '.rescate/tareas') -Force)
  $x = [ordered]@{ job = 'cargaRecibosJob'; titulo = 'Carga de recibos'; paraQue = $ParaQue; pasos = @([ordered]@{ titulo = 'Leer el fichero'; texto = $Texto; refs = @('clase-aaaaaaaa#0') }); dudas = @() }
  [System.IO.File]::WriteAllText((Join-Path $dir '.rescate/tareas/job-cargaRecibosJob.json'), (ConvertTo-Json -InputObject $x -Depth 5))
  $t = [pscustomobject]@{ id = 'job-cargaRecibosJob'; entradas = [pscustomobject]@{ job = 'cargaRecibosJob'; datos = 'clase-aaaaaaaa#0 [regla] Rechaza el recibo sin importe.' } }
  $r = Test-FichaJob $t $dir
  if ($r.Ok) { return 'BIEN' }
  return ('MAL ' + $r.Motivo)
}
'R1=' + (Resumen 'Lee el fichero de recibos que deja el banco en la carpeta de entrada y rechaza los de menos de 5 euros. Deja la tabla de recibos pendientes y envia los rechazados al banco por SFTP.')
'R2=' + (Resumen 'Reune los recibos y deja el resultado de forma clara y ordenada.')
'R3=' + (Resumen "Deja TODA LA INFORMACI${o}N DISPONIBLE en una tabla.")
'R4=' + (Resumen 'Lee el fichero de recibos del banco.' 'Optimiza el cobro.')
'R5=' + (Resumen 'Lee el fichero de recibos del banco.' 'Va primero.' 'Un grupo de recibos que facilita el cobro.')
'R6=' + (Resumen 'Reune diversos ficheros y los pasa por distintos procesos.')
'R7=' + (Resumen 'Deja el resultado LISTO PARA REVISARSE por las personas responsables.')
'R8=' + (Resumen 'Lee el fichero de recibos del banco; no se facilitara nada que no conste y nadie lo garantizado.')
'R9=' + (Resumen 'Lee el fichero de recibos del banco y reoptimiza la carga de la tabla de pendientes.')
'F1=' + (Ficha 'Lee los recibos que deja el banco cada dia y los guarda como pendientes de cobro.')
'F5=' + (Ficha 'Lee los recibos del banco y reoptimiza el orden de la carga.')
'F2=' + (Ficha 'Carga los recibos y garantiza que todo queda bien.')
'F3=' + (Ficha 'Lee los recibos del banco.' 'Se hace de manera eficiente.')
'F4=' + (Ficha 'Recoge los recibos de forma clara y ordenada.')
'FIN'
'@
  $codigo = $codigo.Replace('{{DIR}}', (Join-Path $Dir 'relleno'))
  $r = En-Biblioteca 'relleno' $codigo
  Igual 'el script de prueba sale con 0' 0 $r.Codigo
  $v = @{}
  foreach ($l in ($r.Salida -split "`n")) { if ($l -match '^([RF]\d)=(.*?)\r?$') { $v[$Matches[1]] = $Matches[2] } }
  Igual 'un resumen concreto vale' 'BIEN' $v['R1']
  Comprueba 'con "de forma clara y ordenada" no vale y el motivo dice la frase' ($v['R2'] -match '^MAL' -and $v['R2'] -match 'de forma clara' -and $v['R2'] -match 'clara y ordenada') $v['R2']
  Comprueba 'el motivo pide cambiarla por el dato concreto' ($v['R2'] -match 'concret' -and $v['R2'] -match 'no consta') $v['R2']
  Comprueba 'sin distinguir mayusculas ni acentos: TODA LA INFORMACION DISPONIBLE' ($v['R3'] -match '^MAL' -and $v['R3'] -match 'toda la informacion disponible') $v['R3']
  Comprueba 'tambien en el motivo de orden[]' ($v['R4'] -match '^MAL' -and $v['R4'] -match 'optimiza' -and $v['R4'] -match 'orden\[0\]\.motivo') $v['R4']
  Comprueba 'y en la definicion del glosario' ($v['R5'] -match '^MAL' -and $v['R5'] -match 'facilita' -and $v['R5'] -match 'glosario\[0\]\.definicion') $v['R5']
  Comprueba 'el motivo nombra todas las frases que hay: diversos y distintos procesos' ($v['R6'] -match '^MAL' -and $v['R6'] -match 'diversos' -and $v['R6'] -match 'distintos procesos') $v['R6']
  Comprueba 'listo para revisarse y las personas responsables, con mayusculas' ($v['R7'] -match '^MAL' -and $v['R7'] -match 'listo para revisarse' -and $v['R7'] -match 'las personas responsables') $v['R7']
  Igual 'una palabra que solo contiene la del relleno (facilitara, garantizado) no cuenta' 'BIEN' $v['R8']
  Igual 'ni la que empieza por letras de mas (reoptimiza no es optimiza), en un resumen' 'BIEN' $v['R9']
  Igual 'una ficha de job concreta vale' 'BIEN' $v['F1']
  Igual 'ni en el para que de una ficha (reoptimiza)' 'BIEN' $v['F5']
  Comprueba 'una ficha con "garantiza" en el para que no vale y el motivo dice el campo' ($v['F2'] -match '^MAL' -and $v['F2'] -match 'paraQue' -and $v['F2'] -match 'garantiza') $v['F2']
  Comprueba 'una ficha con relleno en el texto de un paso, igual' ($v['F3'] -match '^MAL' -and $v['F3'] -match 'pasos\[0\]\.texto' -and $v['F3'] -match 'de manera eficiente') $v['F3']
  Comprueba 'y la frase de forma clara y ordenada, en el para que' ($v['F4'] -match '^MAL' -and $v['F4'] -match 'de forma clara' -and $v['F4'] -match 'concret') $v['F4']
}

$Pruebas['m15 resumen: los prompts piden los cinco datos, "no consta" si falta, traen un ejemplo nuevo y la lista de frases prohibidas'] = {
  $c = Corrida-Dos $GuionBase
  $e = $c.E
  $t = @(Tareas $e 'resumen')
  if ($t.Count -ne 1) { Comprueba 'hay una tarea de resumen' $false (Cola $c.R.Salida); return }
  $p = Prompt-De $e $t[0]
  $j = Job-De $e 'cargaJob'
  $textos = @(@($j.necesita) + @($j.produce) + @($j.conexiones) + @($j.reglas) | Where-Object { -not $_.tecnico } | ForEach-Object { $_.texto })
  $faltan = @($textos | Where-Object { -not $p.Contains($_) })
  Comprueba 'con el escenario real: el prompt lleva cada dato de lista del job que no es tecnico' ($textos.Count -ge 4 -and $faltan.Count -eq 0) ("$($textos.Count) datos; faltan: " + ($faltan -join ' | '))
  Comprueba 'el resumen que se pide: que datos lee y de donde, que hace, que deja y donde, a quien le llega y cuando se lanza' ($p -match '(?i)qu. datos lee' -and $p -match '(?i)de d.nde' -and $p -match '(?i)qu. hace' -and $p -match '(?i)qu. deja' -and $p -match '(?i)a qui.n' -and $p -match '(?i)cu.ndo') ($p.Substring(0, [Math]::Min(300, $p.Length)))
  Comprueba 'dice que lo que no esta se escribe "no consta"' ($p -match 'no consta') ''
  Comprueba 'el ejemplo de antes (recibos del banco, administracion) ya no esta' ($p -notmatch 'equipo de administraci.n' -and $p -notmatch 'prepara el cobro') ''
  Comprueba 'lleva la lista de frases prohibidas (las del Cfg)' ($p.Contains('de forma clara') -and $p.Contains('toda la informacion disponible') -and $p.Contains('distintos procesos')) ''
  $f = @(Tareas $e 'ficha-job')
  Comprueba 'hay fichas de job' ($f.Count -ge 1) ''
  if ($f.Count -ge 1) {
    $q = Prompt-De $e $f[0]
    Comprueba 'la ficha del job: el para que dice que lee, que hace, que deja y para quien, y "no consta"' ($q -match '(?i)qu. datos lee' -and $q -match '(?i)qu. deja' -and $q -match '(?i)a qui.n' -and $q -match 'no consta') ''
    Comprueba 'y lleva las frases prohibidas' ($q.Contains('de forma clara') -and $q.Contains('garantiza')) ''
  }
}

# ===================== M13: UN CASO POR CADA REGLA SIN CASO =====================
# Las reglas que prueba-pre dejo en sinCaso: una tarea caso-pre por cada una (fase casos-pre, justo despues de pruebas-pre). El Copilot falso de
# estas pruebas es copilot-m6.ps1, que escribe el caso y le pasa lo demas a copilot.ps1.
$script:CorridasCasos = @{}
function Corrida-Casos([string]$Guion) {
  if (-not $script:CorridasCasos.ContainsKey($Guion)) {
    $e = Escenario-Dos ('casos' + $script:CorridasCasos.Count) @() @{ CopilotExe = (Join-Path $falsos 'copilot-m6.ps1') }
    $script:CorridasCasos[$Guion] = [pscustomobject]@{ E = $e; R = (Migra $e (Basicos $e) $Guion) }
  }
  return $script:CorridasCasos[$Guion]
}
$FaltaUna = 'prueba-falta-siempre:^prueba-pre:'

$Pruebas['m13 casos: una tarea caso-pre por cada regla o error de sinCaso, con la regla, el guion que ya hay y los hechos; la huella sigue a lo que recibe'] = {
  $codigo = @'
$Datos = '{{DIR}}'
$mapa = [pscustomobject]@{ jobs = @(
    [pscustomobject]@{ job = 'cargaRecibosJob'; clases = @([pscustomobject]@{ ficha = 'clase-aaaaaaaa' }) },
    [pscustomobject]@{ job = 'informeCobrosJob'; clases = @([pscustomobject]@{ ficha = 'clase-bbbbbbbb' }) },
    [pscustomobject]@{ job = 'avisosJob'; clases = @() }) }
Write-Json (Join-Path $Datos 'fichas/clase-aaaaaaaa.json') ([ordered]@{ id = 'clase-aaaaaaaa'; clase = 'CargaReader'; datos = @(
      [ordered]@{ tipo = 'entrada-fichero'; texto = 'Lee el fichero de recibos del banco.' },
      [ordered]@{ tipo = 'regla'; texto = 'Rechaza el recibo cuyo importe es menor de 5 euros.' },
      [ordered]@{ tipo = 'error'; texto = 'Si el fichero no existe, avisa y no sigue.' }) })
Write-Json (Join-Path $Datos 'fichas/clase-bbbbbbbb.json') ([ordered]@{ id = 'clase-bbbbbbbb'; clase = 'InformeWriter'; datos = @([ordered]@{ tipo = 'regla'; texto = 'El informe solo lleva los recibos cobrados.' }) })
function Pruebas([string]$Job, $SinCaso) {
  Write-Json (Join-Path $Datos ('pruebas/' + $Job + '.json')) ([ordered]@{ job = $Job
      preparar = @([ordered]@{ texto = 'Deja el fichero de recibos en la carpeta de entrada.'; refs = @('clase-aaaaaaaa#0') })
      casos = @([ordered]@{ titulo = 'Recibo correcto'; entrada = 'Un recibo de 20 euros.'; esperado = 'Se carga.'; refs = @('clase-aaaaaaaa#0') })
      comprobar = @([ordered]@{ texto = 'Mira la tabla de recibos pendientes.'; refs = @('clase-aaaaaaaa#0') })
      sinCaso = @($SinCaso); redaccion = 'hecha' })
}
function Falta([string]$Ref, [string]$Tipo, [string]$Texto) { return [ordered]@{ ref = $Ref; tipo = $Tipo; texto = $Texto } }
Pruebas 'cargaRecibosJob' @((Falta 'clase-aaaaaaaa#1' 'regla' 'Rechaza el recibo cuyo importe es menor de 5 euros.'), (Falta 'clase-aaaaaaaa#2' 'error' 'Si el fichero no existe, avisa y no sigue.'))
Pruebas 'informeCobrosJob' @((Falta 'clase-bbbbbbbb#0' 'regla' 'El informe solo lleva los recibos cobrados.'))
Pruebas 'avisosJob' @()
$t = @(Get-TareasCaso $mapa $false)
'N=' + $t.Count
'TIPOS=' + (@($t | ForEach-Object { $_.tipo } | Select-Object -Unique) -join ',')
'IDS=' + (@($t | ForEach-Object { $_.id } | Select-Object -Unique).Count)
'JOBS=' + (@($t | ForEach-Object { $_.entradas.job }) -join ',')
'REFS=' + (@($t | ForEach-Object { $_.entradas.ref }) -join ',')
'SALIDA=' + $t[0].salida
$p = Get-Prompt $t[1] '' ''
[System.IO.File]::WriteAllText((Join-Path $Datos 'prompt.txt'), $p)
function Huellas { return (@(Get-TareasCaso $mapa $false | ForEach-Object { $_.entradas.huella }) -join ',') }
$h0 = Huellas
'H0=' + $h0
Write-Json (Join-Path $Datos 'tareas/prueba-x.json') ([ordered]@{ id = 'prueba-x' })
'IGUAL=' + ((Huellas) -eq $h0)
Pruebas 'informeCobrosJob' @((Falta 'clase-bbbbbbbb#0' 'regla' 'El informe solo lleva los recibos cobrados y los pendientes.'))
$h1 = (Huellas) -split ','
'CAMBIA=' + (@(0..2 | Where-Object { $h1[$_] -ne ($h0 -split ',')[$_] }) -join ',')
$t = @(Get-TareasCaso $mapa $false)
$t[0].estado = 'hecha'
Save-Tarea $t[0]
'HECHA=' + (@(Get-TareasCaso $mapa $false)[0].estado)
'FIN'
'@
  $d = Join-Path $Dir 'casos-tareas'
  $r = En-Biblioteca 'casos-tareas' $codigo.Replace('{{DIR}}', $d)
  Igual 'el script de prueba sale con 0' 0 $r.Codigo
  $v = @{}
  foreach ($l in ($r.Salida -split "`n")) { if ($l -match '^(\w+)=(.*?)\r?$') { $v[$Matches[1]] = $Matches[2] } }
  Igual 'tres reglas sin caso (dos en un job, una en otro, ninguna en el tercero): tres tareas' '3' $v['N']
  Igual 'todas del tipo caso-pre' 'caso-pre' $v['TIPOS']
  Igual 'con ids distintos' '3' $v['IDS']
  Igual 'por job y por regla, en el orden de sinCaso' 'cargaRecibosJob,cargaRecibosJob,informeCobrosJob' $v['JOBS']
  Igual 'cada una con la referencia de su regla' 'clase-aaaaaaaa#1,clase-aaaaaaaa#2,clase-bbbbbbbb#0' $v['REFS']
  $p = ''
  if (Test-Path -LiteralPath (Join-Path $d 'prompt.txt')) { $p = [System.IO.File]::ReadAllText((Join-Path $d 'prompt.txt')) }
  Comprueba 'el prompt de la segunda: TIPO, job, regla con su referencia y su texto' ($p -match '(?m)^TIPO: caso-pre\r?$' -and $p -match '(?m)^JOB: cargaRecibosJob\r?$' -and $p -match '(?m)^REGLA: clase-aaaaaaaa#2\r?$' -and $p -match '(?m)^clase-aaaaaaaa#2 \[error\] Si el fichero no existe') ($p.Substring(0, [Math]::Min(400, $p.Length)))
  Comprueba 'lleva el guion que ya tiene: lo que se prepara, los casos con su titulo y lo que se comprueba' ($p.Contains('Deja el fichero de recibos en la carpeta de entrada.') -and $p -match '(?m)^- Recibo correcto\r?$' -and $p.Contains('Mira la tabla de recibos pendientes.')) ''
  Comprueba 'lleva los hechos del job para las referencias' ($p -match '(?m)^clase-aaaaaaaa#0 \[entrada-fichero\]' -and $p -match '(?m)^clase-aaaaaaaa#1 \[regla\]') ''
  Comprueba 'no manda leer nada ni lleva nombres de clase' ($p -notmatch '(?m)^LEER:' -and $p -notmatch 'CargaReader') ''
  Comprueba 'con las tareas hechas de antes no cambia la huella; con otro texto en una regla, solo cambia la de esa' ($v['IGUAL'] -eq 'True' -and $v['CAMBIA'] -eq '2') "$($v['IGUAL']) $($v['CAMBIA'])"
  Igual 'una tarea hecha con la misma huella se reutiliza' 'hecha' $v['HECHA']
}

$Pruebas['m13 casos: un caso vale si lleva la referencia de la regla, usa hechos que existen, no nombra clases ni repite un titulo'] = {
  $codigo = @'
$Fuentes = @('CargaReader', 'GestorRecibos') | ForEach-Object { [pscustomobject]@{ BaseName = $_ } }
$base = Join-Path '{{DIR}}' ([guid]::NewGuid().ToString('N').Substring(0, 6))
function Caso($Caso) {
  $dir = Join-Path $base ('c' + [guid]::NewGuid().ToString('N').Substring(0, 6))
  [void](New-Item -ItemType Directory -Path (Join-Path $dir '.rescate/tareas') -Force)
  [System.IO.File]::WriteAllText((Join-Path $dir '.rescate/tareas/casopre-x.json'), (ConvertTo-Json -InputObject $Caso -Depth 5))
  $datos = "clase-aaaaaaaa#0 [entrada-fichero] Lee el fichero.`nclase-aaaaaaaa#1 [regla] Rechaza menos de 5 euros.`nclase-aaaaaaaa#2 [error] Avisa si falta el fichero."
  $t = [pscustomobject]@{ id = 'casopre-x'; tipo = 'caso-pre'; intentos = 0; entradas = [pscustomobject]@{ job = 'cargaRecibosJob'; ref = 'clase-aaaaaaaa#1'; tipo = 'regla'; datos = $datos; titulos = @('Recibo correcto', 'Fichero sin recibos') } }
  $r = Test-Salida $t $dir ''
  if ($r.Ok) { return ('BIEN ' + $r.Ficha.ref + ' ' + $r.Ficha.caso.titulo + ' ' + (@($r.Ficha.caso.refs) -join '+')) }
  return ('MAL ' + $r.Motivo)
}
function Buen([hashtable]$Cambios = @{}) {
  $c = [ordered]@{ titulo = 'Recibo de 4,99 euros'; entrada = 'Un recibo de 4,99 euros.'; esperado = 'Se rechaza y queda en el fichero de rechazados.'; refs = @('clase-aaaaaaaa#1') }
  foreach ($k in $Cambios.Keys) { $c[$k] = $Cambios[$k] }
  return $c
}
'C1=' + (Caso (Buen))
'C2=' + (Caso (Buen @{ refs = @('clase-aaaaaaaa#1', 'clase-aaaaaaaa#2') }))
'C3=' + (Caso (Buen @{ refs = @('clase-aaaaaaaa#2') }))
'C4=' + (Caso (Buen @{ refs = @('clase-aaaaaaaa#1', 'clase-00000000#9') }))
'C5=' + (Caso (Buen @{ refs = @() }))
'C6=' + (Caso (Buen @{ titulo = 'Caso con GestorRecibos' }))
'C7=' + (Caso (Buen @{ titulo = '  RECIBO CORRECTO ' }))
'C8=' + (Caso (Buen @{ esperado = '   ' }))
'C9=' + (Caso (Buen @{ refs = 'clase-aaaaaaaa#1' }))
'C10=' + (Caso (Buen @{ entrada = 'Mira Recibo.java' }))
'FIN'
'@
  $r = En-Biblioteca 'caso-valida' $codigo.Replace('{{DIR}}', (Join-Path $Dir 'caso-valida'))
  Igual 'el script de prueba sale con 0' 0 $r.Codigo
  $v = @{}
  foreach ($l in ($r.Salida -split "`n")) { if ($l -match '^(C\d+)=(.*?)\r?$') { $v[$Matches[1]] = $Matches[2] } }
  Igual 'un caso bueno vale y devuelve la regla, el titulo y las refs' 'BIEN clase-aaaaaaaa#1 Recibo de 4,99 euros clase-aaaaaaaa#1' $v['C1']
  Comprueba 'con refs de mas (otros hechos que si existen) tambien vale' ($v['C2'] -match '^BIEN' -and $v['C2'] -match 'clase-aaaaaaaa#1\+clase-aaaaaaaa#2') $v['C2']
  Comprueba 'sin la referencia de la regla no vale y el motivo la dice' ($v['C3'] -match '^MAL' -and $v['C3'] -match 'clase-aaaaaaaa#1' -and $v['C3'] -match 'regla') $v['C3']
  Comprueba 'una referencia que no existe no vale y el motivo la dice' ($v['C4'] -match '^MAL' -and $v['C4'] -match 'clase-00000000#9') $v['C4']
  Comprueba 'sin ninguna referencia, tampoco' ($v['C5'] -match '^MAL' -and $v['C5'] -match 'refs') $v['C5']
  Comprueba 'un nombre de clase en el titulo no vale y el motivo lo nombra' ($v['C6'] -match '^MAL' -and $v['C6'] -match 'GestorRecibos') $v['C6']
  Comprueba 'un titulo igual a uno que ya hay (sin mayusculas ni espacios de mas) no vale' ($v['C7'] -match '^MAL' -and $v['C7'] -match 'titulo' -and $v['C7'] -match 'Recibo correcto') $v['C7']
  Comprueba 'un campo en blanco no vale y el motivo lo nombra' ($v['C8'] -match '^MAL' -and $v['C8'] -match 'esperado') $v['C8']
  Comprueba 'refs que no es una lista no vale' ($v['C9'] -match '^MAL' -and $v['C9'] -match 'refs') $v['C9']
  Comprueba 'un fichero .java en un texto no vale' ($v['C10'] -match '^MAL' -and $v['C10'] -match 'Recibo\.java') $v['C10']
}

$Pruebas['m13 casos: una salida buena anade el caso a datos/pruebas/<job>.json y la regla sale de sinCaso; el resto del guion queda como estaba'] = {
  $c = Corrida-Casos $FaltaUna
  $e = $c.E
  Igual 'sale con 0' 0 $c.R.Codigo
  $t = @(Tareas $e 'caso-pre')
  Igual 'dos reglas sin caso (una en cada job): dos tareas caso-pre' 2 $t.Count
  Igual 'las dos hechas, en un intento' 'hecha 1 hecha 1' (@($t | ForEach-Object { "$($_.estado) $($_.intentos)" }) -join ' ')
  Igual 'dos llamadas de caso-pre, ni una mas' 2 (Llamadas-De (Llamadas $e.Wt) 'casopre-').Count
  Comprueba 'sin ficha de job que acote los hechos, el prompt lleva la regla de la tarea' ((Prompt-De $e $t[0]) -match ('(?m)^REGLA: ' + [regex]::Escape($t[0].entradas.ref) + '\r?$')) ''
  Igual 'sin esfuerzo de lectura ni --add-dir: solo redacta, con high' 'True' (@(Llamadas-De (Llamadas $e.Wt) 'casopre-' | Where-Object { $_.flags -notmatch '--add-dir' -and $_.flags -match '--effort=high' }).Count -eq 2)
  foreach ($job in @('cargaJob', 'informeJob')) {
    $x = Pruebas-De $e $job
    $tj = @($t | Where-Object { $_.entradas.job -eq $job })
    Igual "${job}: una tarea" 1 $tj.Count
    if ($tj.Count -ne 1) { continue }
    Igual "${job}: sinCaso vacio" 0 @($x.sinCaso).Count
    $nuevo = @($x.casos | Where-Object { @($_.refs) -contains $tj[0].entradas.ref })
    Comprueba "${job}: el caso nuevo lleva la referencia de la regla, esta al final y tiene titulo, entrada y esperado" ($nuevo.Count -ge 1 -and $x.casos[-1].titulo -match [regex]::Escape($tj[0].entradas.ref) -and $x.casos[-1].entrada -and $x.casos[-1].esperado) ($x.casos | ConvertTo-Json -Compress -Depth 4)
    Igual "${job}: redaccion hecha, y preparar y comprobar como estaban" 'hecha True' "$($x.redaccion) $(@($x.preparar).Count -ge 1 -and @($x.comprobar).Count -ge 1)"
  }
  Igual 'la fase acaba en hecha' 'hecha' (Estado $e).fase
  $i = Pagina $e.Out 'index.html'
  Comprueba 'la portada tiene la fase de los casos y cuenta sus dos tareas hechas' ($i -match 'Casos de las reglas sin caso' -and $i -notmatch '(?s)Reglas sin caso de prueba \(\d') ''
  $u = Pagina $e.Out '1-batch-original.html'
  Comprueba 'la pagina 1 ya no lista reglas sin caso' ($u -notmatch 'Reglas sin caso de prueba') ''
}

$Pruebas['m13 casos: un caso sin la referencia de la regla o con un titulo repetido no vale (el motivo lo dice) y la regla se queda en sinCaso'] = {
  $c = Corrida-Casos "$FaltaUna;caso-sin-ref:^caso-pre:cargaJob`$;caso-titulo-repetido:^caso-pre:informeJob`$"
  $e = $c.E
  Igual 'sale con 0' 0 $c.R.Codigo
  $t = @(Tareas $e 'caso-pre')
  Igual 'dos tareas, las dos atascadas tras dos intentos' 'atascada 2 atascada 2' (@($t | Sort-Object { $_.entradas.job } | ForEach-Object { "$($_.estado) $($_.intentos)" }) -join ' ')
  $a = @($t | Where-Object { $_.entradas.job -eq 'cargaJob' })[0]
  $b = @($t | Where-Object { $_.entradas.job -eq 'informeJob' })[0]
  Comprueba 'cargaJob: el motivo pide la referencia de la regla' ($a.motivo -match [regex]::Escape($a.entradas.ref) -and $a.motivo -match 'regla') $a.motivo
  Comprueba 'cargaJob: el reintento lleva esa correccion' ((Prompt-De $e $a) -match ('(?s)## CORRECCI.*' + [regex]::Escape($a.entradas.ref))) ''
  Comprueba 'informeJob: el motivo habla del titulo repetido' ($b.motivo -match 'titulo' -and $b.motivo -match 'ya hay') $b.motivo
  foreach ($job in @('cargaJob', 'informeJob')) {
    $x = Pruebas-De $e $job
    $tj = @($t | Where-Object { $_.entradas.job -eq $job })[0]
    Igual "${job}: la regla se queda en sinCaso" $tj.entradas.ref (@($x.sinCaso | ForEach-Object { $_.ref }) -join ',')
    Comprueba "${job}: y ningun caso nuevo (el guion es el que dio prueba-pre)" (@($x.casos | Where-Object { @($_.refs) -contains $tj.entradas.ref }).Count -eq 0) ($x.casos | ConvertTo-Json -Compress -Depth 4)
  }
  Igual 'la fase acaba aunque se atasquen' 'hecha' (Estado $e).fase
  $u = Pagina $e.Out '1-batch-original.html'
  Comprueba 'la pagina 1 sigue listando las dos reglas sin caso' ([regex]::Matches($u, 'Reglas sin caso de prueba').Count -eq 2) ''
}

$Pruebas['m13 casos: un nombre de clase en el titulo o la referencia que falta en el primer intento se corrigen en el reintento y el caso entra'] = {
  $c = Corrida-Casos "$FaltaUna;caso-sin-ref-una-vez:^caso-pre:cargaJob`$;caso-clase-en-texto:^caso-pre:informeJob`$"
  $e = $c.E
  Igual 'sale con 0' 0 $c.R.Codigo
  $t = @(Tareas $e 'caso-pre')
  Igual 'las dos hechas en el segundo intento' 'hecha 2 hecha 2' (@($t | ForEach-Object { "$($_.estado) $($_.intentos)" }) -join ' ')
  $b = @($t | Where-Object { $_.entradas.job -eq 'informeJob' })[0]
  Comprueba 'el reintento de informeJob nombra la clase y lleva el esfuerzo high' ((Prompt-De $e $b) -match '(?s)## CORRECCI.*CargaReader') ''
  foreach ($job in @('cargaJob', 'informeJob')) {
    $x = Pruebas-De $e $job
    Igual "${job}: sinCaso vacio y el caso dentro" '0 True' "$(@($x.sinCaso).Count) $(@($x.casos | Where-Object { $_.titulo -match 'Caso de la regla' }).Count -eq 1)"
  }
}

$Pruebas['m13 casos: al relanzar no se repite ninguna tarea hecha ni se duplica el caso; un batch con pruebas-pre hecha de antes tambien genera las tareas'] = {
  $c = Corrida-Casos $FaltaUna
  $e = $c.E
  $antes = (Llamadas $e.Wt).Count
  $casos0 = @((Pruebas-De $e 'cargaJob').casos).Count
  $r = Migra $e (Basicos $e) $FaltaUna
  Igual 'relanzar sale con 0' 0 $r.Codigo
  Igual 'sin ninguna llamada nueva' $antes (Llamadas $e.Wt).Count
  Igual 'el guion de cargaJob sigue igual: el caso no se duplica' $casos0 @((Pruebas-De $e 'cargaJob').casos).Count
  Igual 'y sinCaso sigue vacio' 0 @((Pruebas-De $e 'cargaJob').sinCaso).Count
  # un batch que paso por pruebas-pre antes de que hubiera casos-pre: sin tareas caso-pre, pero con sus pruebas hechas
  foreach ($f in @(Get-ChildItem -LiteralPath (Get-Ruta $e.Out 'datos/tareas') -File -Filter 'casopre-*.json')) { Remove-Item -LiteralPath $f.FullName }
  Igual 'sin tareas caso-pre' 0 @(Tareas $e 'caso-pre').Count
  $antes = (Llamadas $e.Wt).Count
  $pre0 = (Llamadas-De (Llamadas $e.Wt) 'prueba-').Count
  $r = Migra $e (Basicos $e) $FaltaUna
  Igual 'relanzar sale con 0' 0 $r.Codigo
  Igual 'dos tareas caso-pre nuevas, hechas' 'hecha hecha' (@(Tareas $e 'caso-pre' | ForEach-Object { $_.estado }) -join ' ')
  Igual 'dos llamadas nuevas, las de caso-pre' 2 ((Llamadas $e.Wt).Count - $antes)
  Igual 'y ninguna nueva de prueba-pre (sus tareas estaban hechas)' $pre0 (Llamadas-De (Llamadas $e.Wt) 'prueba-').Count
  Igual 'cargaJob: el caso esta una sola vez y sinCaso sigue vacio' "$casos0 0" "$(@((Pruebas-De $e 'cargaJob').casos).Count) $(@((Pruebas-De $e 'cargaJob').sinCaso).Count)"
}

$Pruebas['m13 casos: prueba-local.ps1 sigue leyendo los casos de datos/pruebas/<job>.json, asi que el caso nuevo sale entre los que va a preparar'] = {
  $c = Corrida-Casos $FaltaUna
  $e = $c.E
  $x = Pruebas-De $e 'cargaJob'
  $nuevo = @($x.casos | Where-Object { $_.titulo -match 'Caso de la regla' })
  Comprueba 'hay un caso de caso-pre en el guion de cargaJob' ($nuevo.Count -eq 1) ($x.casos | ConvertTo-Json -Compress -Depth 4)
  # lo mismo que hace prueba-local.ps1 con la carpeta: todos los .json con job, y un caso-NN por cada elemento de casos
  $dir = Get-Ruta $e.Out 'datos/pruebas'
  $pruebas = @(Get-ChildItem -LiteralPath $dir -File -Filter '*.json' | Sort-Object Name | ForEach-Object { Lee-Json $_.FullName } | Where-Object { $_.job })
  $p = @($pruebas | Where-Object { $_.job -eq 'cargaJob' })[0]
  $titulos = @(@($p.casos) | ForEach-Object { [string]$_.titulo })
  Comprueba 'entre los casos que prepara, con su numero, esta el nuevo' ($nuevo.Count -eq 1 -and $titulos -contains $nuevo[0].titulo) ($titulos -join ' | ')
  Igual 'y son uno mas que los que dio prueba-pre' (@($x.casos).Count) $titulos.Count
  $src = [System.IO.File]::ReadAllText((Join-Path (Split-Path -Parent $Script) 'prueba-local.ps1'))
  Comprueba 'prueba-local.ps1 lee la carpeta datos/pruebas y recorre $Prueba.casos (si cambia, esta prueba hay que mirarla)' ($src -match "datos/pruebas'\) -File -Filter '\*\.json'" -and $src -match '(?m)foreach \(\$c in @\(\$Prueba\.casos\)\)') ''
}

# Save-Casos, sin pasar por las llamadas: tareas caso-pre hechas a mano sobre datos/pruebas/<job>.json. Tres jobs (uno por situacion).
$script:PreludioSave = @'
$Datos = '{{DIR}}'
$mapa = [pscustomobject]@{ jobs = @([pscustomobject]@{ job = 'cargaRecibosJob' }, [pscustomobject]@{ job = 'informeCobrosJob' }, [pscustomobject]@{ job = 'avisosJob' }) }
function Pruebas([string]$Job, $Casos, $SinCaso) {
  Write-Json (Join-Path $Datos ('pruebas/' + $Job + '.json')) ([ordered]@{ job = $Job; preparar = @(); casos = @($Casos); comprobar = @(); sinCaso = @($SinCaso); redaccion = 'hecha' })
}
function Caso([string]$Titulo, [string]$Ref) { return [ordered]@{ titulo = $Titulo; entrada = 'Un recibo.'; esperado = 'Se carga.'; refs = @($Ref) } }
function Falta([string]$Ref) { return [ordered]@{ ref = $Ref; tipo = 'regla'; texto = 'Una regla.' } }
function Hecha([string]$Job, $Caso) { return [pscustomobject]@{ estado = 'hecha'; entradas = [pscustomobject]@{ job = $Job }; resultado = [pscustomobject]@{ caso = [pscustomobject]$Caso } } }
function Veo([string]$Job) {
  $p = Read-Json (Join-Path $Datos ('pruebas/' + $Job + '.json'))
  return ((@($p.casos | ForEach-Object { $_.titulo }) -join '|') + ' / ' + (@($p.sinCaso | ForEach-Object { $_.ref }) -join ','))
}
'@
function Salida-Save([string]$Nombre, [string]$Cuerpo) {
  $r = En-Biblioteca $Nombre ($script:PreludioSave.Replace('{{DIR}}', (Join-Path $Dir $Nombre)) + $Cuerpo)
  Igual 'el script de prueba sale con 0' 0 $r.Codigo
  $v = @{}
  foreach ($l in ($r.Salida -split "`n")) { if ($l -match '^(\w+)=(.*?)\r?$') { $v[$Matches[1]] = $Matches[2] } }
  return $v
}

$Pruebas['m13 casos: dos tareas hechas del mismo job con el mismo titulo (o uno que el guion ya tiene) meten un solo caso y la otra regla se queda en sinCaso'] = {
  $v = Salida-Save 'save-titulos' @'
Pruebas 'cargaRecibosJob' @((Caso 'Recibo correcto' 'clase-aaaaaaaa#0')) @((Falta 'clase-aaaaaaaa#1'), (Falta 'clase-aaaaaaaa#2'), (Falta 'clase-aaaaaaaa#3'))
$t = @((Hecha 'cargaRecibosJob' (Caso 'Recibo pequeno' 'clase-aaaaaaaa#1')), (Hecha 'cargaRecibosJob' (Caso ' RECIBO PEQUENO ' 'clase-aaaaaaaa#2')), (Hecha 'cargaRecibosJob' (Caso 'recibo CORRECTO' 'clase-aaaaaaaa#3')))
Save-Casos $mapa $t
'A1=' + (Veo 'cargaRecibosJob')
Save-Casos $mapa $t
'A2=' + (Veo 'cargaRecibosJob')
'FIN'
'@
  Igual 'el titulo repetido (sin mayusculas ni espacios de mas) y el que ya estaba en el guion no entran: queda un caso nuevo y las dos reglas siguen en sinCaso' 'Recibo correcto|Recibo pequeno / clase-aaaaaaaa#2,clase-aaaaaaaa#3' $v['A1']
  Igual 'aplicarlo otra vez no cambia nada' $v['A1'] $v['A2']
}

$Pruebas['m13 casos: con el guion ya en CasosMax el caso nuevo no entra y su regla se queda en sinCaso; con sitio para uno, entra el primero y el otro no'] = {
  $v = Salida-Save 'save-tope' @'
$Cfg.CasosMax = 2
Pruebas 'informeCobrosJob' @((Caso 'Uno' 'clase-bbbbbbbb#0'), (Caso 'Dos' 'clase-bbbbbbbb#1')) @((Falta 'clase-bbbbbbbb#2'))
Save-Casos $mapa @((Hecha 'informeCobrosJob' (Caso 'Tres' 'clase-bbbbbbbb#2')))
'B=' + (Veo 'informeCobrosJob')
Pruebas 'avisosJob' @((Caso 'Uno' 'clase-cccccccc#0')) @((Falta 'clase-cccccccc#1'), (Falta 'clase-cccccccc#2'))
Save-Casos $mapa @((Hecha 'avisosJob' (Caso 'Dos' 'clase-cccccccc#1')), (Hecha 'avisosJob' (Caso 'Tres' 'clase-cccccccc#2')))
'C=' + (Veo 'avisosJob')
'FIN'
'@
  Igual 'con 2 casos y CasosMax 2: no entra el nuevo y su regla sigue en sinCaso' 'Uno|Dos / clase-bbbbbbbb#2' $v['B']
  Igual 'con 1 caso y CasosMax 2: entra el primero, el segundo no y su regla sigue en sinCaso' 'Uno|Dos / clase-cccccccc#2' $v['C']
}

# ===================== M20c: LA PORTADA NO PROMETE DE MAS, SIN CONTRASENAS EN LA PAGINA 1 Y SIN COMMITS DE LA IA =====================
# Los datos del informe con una prueba en local de $Iguales casos iguales, $Distintos distintos, $SinPreparar que no se pudieron preparar (con su
# motivo) y uno por cada resultado de $Otros (no determinista, sin probar en local...), mas la correccion (o $null) y los errores del diagnostico.
function Datos-Incompleta([int]$SinPreparar, [int]$Iguales = 1, [int]$Distintos = 0, $Correccion = $null, [int]$Errores = 0, [string[]]$Otros = @()) {
  $casos = @()
  for ($i = 1; $i -le $Iguales; $i++) { $casos += (Caso-Local 'cargaJob' ('caso-i' + $i) ('Igual ' + $i) 'igual') }
  for ($i = 1; $i -le $Distintos; $i++) { $casos += (Caso-Local 'cargaJob' ('caso-d' + $i) ('Distinto ' + $i) 'distinto') }
  for ($i = 1; $i -le $SinPreparar; $i++) { $casos += (Caso-Local 'cargaJob' ('caso-s' + $i) ('Sin preparar ' + $i) 'no se pudo preparar' 'La IA no ha podido preparar sus entradas: atascada.') }
  for ($i = 0; $i -lt $Otros.Count; $i++) { $casos += (Caso-Local 'cargaJob' ('caso-o' + $i) ('Otro ' + $i) $Otros[$i]) }
  return [ordered]@{
    Correccion = $Correccion
    PruebaLocal = [ordered]@{ jobs = @([ordered]@{ job = 'cargaJob'; casos = $casos.Count; iguales = $Iguales; distintos = $Distintos; sinProbar = ($casos.Count - $Iguales - $Distintos) }); casos = $casos }
    Diag = [ordered]@{ Errores = $Errores; Avisos = 0 }
  }
}

$Pruebas['m20c siguiente (a): casos sin preparar y ninguno distinto: local-incompleta con N y M y el comando de la pasada; gana a parar-con-problemas, a corregido y a local-saltada; pierde con local-fallo y local-jdk'] = {
  $s = Siguiente (Estado-Siguiente) (Datos-Incompleta 3 1)
  Igual 'caso local-incompleta' 'local-incompleta' $s.Caso
  Igual 'N es lo que no se pudo preparar' 3 $s.N
  Igual 'M es el total de casos' 4 $s.M
  Igual 'el comando es el de la pasada' ($ComandoSiguiente + ' -SoloInforme') $s.Comando
  $s = Siguiente (Estado-Siguiente @{ respuesta = 'corregir' }) (Datos-Incompleta 3 1)
  Igual 'con la respuesta corregir, el de la pasada con -Si' ($ComandoSiguiente + ' -Si') $s.Comando
  $s = Siguiente (Estado-Siguiente @{ javaLegacy = 'C:\jdk8' }) (Datos-Incompleta 3 1)
  Igual 'con -JavaLegacy, el de la pasada con -JavaLegacy' ($ComandoSiguiente + ' -SoloInforme -JavaLegacy "C:\jdk8"') $s.Comando
  $s = Siguiente (Estado-Siguiente) (Datos-Incompleta 2 1 0 $null 5)
  Igual 'con problemas en la pagina 2 y respuesta parar: gana local-incompleta, no parar-con-problemas' 'local-incompleta' $s.Caso
  Igual 'y el comando sigue siendo el de la pasada (no pasa a -Si)' ($ComandoSiguiente + ' -SoloInforme') $s.Comando
  $s = Siguiente (Estado-Siguiente @{ respuesta = 'corregir' }) (Datos-Incompleta 2 1 0 (Correccion-Siguiente))
  Igual 'con la correccion completa y commits: gana local-incompleta, no el git merge de corregido' 'local-incompleta' $s.Caso
  $salto = [ordered]@{ resultado = 'saltada'; codigo = $null; minutos = 0; detalle = ''; registro = '' }
  $s = Siguiente (Estado-Siguiente @{ pruebaLocal = $salto }) (Datos-Incompleta 2 1)
  Igual 'va antes de local-saltada' 'local-incompleta' $s.Caso
  $fallo = [ordered]@{ resultado = 'fallo'; codigo = 1; minutos = 1.5; detalle = 'dos / tres'; registro = 'registros/prueba-local.log' }
  $s = Siguiente (Estado-Siguiente @{ pruebaLocal = $fallo }) (Datos-Incompleta 2 1)
  Igual 'va despues de local-fallo' 'local-fallo' $s.Caso
  $jdk = [ordered]@{ resultado = 'fallo'; codigo = 1; minutos = 1.5; detalle = 'no compila'; jdkOriginal = $true; registro = 'registros/prueba-local.log' }
  $s = Siguiente (Estado-Siguiente @{ pruebaLocal = $jdk }) (Datos-Incompleta 2 1)
  Igual 'va despues de local-jdk' 'local-jdk' $s.Caso
  $s = Siguiente (Estado-Siguiente @{ fin = ''; fase = 'prueba-local' }) (Datos-Incompleta 2 1)
  Igual 'va despues de corriendo' 'corriendo' $s.Caso
}

$Pruebas['m20c siguiente (c, d): lo demas sigue como hoy: todo igual o con otros resultados (no determinista, sin probar en local) no es local-incompleta, y los distintos ganan a lo sin preparar'] = {
  $s = Siguiente (Estado-Siguiente) (Datos-Incompleta 0 3 0 $null 2)
  Igual '(c) todo igual y problemas en la pagina 2: sigue parar-con-problemas' 'parar-con-problemas' $s.Caso
  $s = Siguiente (Estado-Siguiente) (Datos-Incompleta 0 3)
  Igual '(c) todo igual y nada que corregir: sigue pre' 'pre' $s.Caso
  $s = Siguiente (Estado-Siguiente) (Datos-Incompleta 0 2 0 $null 1 @('no determinista', 'sin probar en local'))
  Igual '(c) no determinista y sin probar en local no son no se pudo preparar: sigue parar-con-problemas' 'parar-con-problemas' $s.Caso
  $s = Siguiente (Estado-Siguiente) (Datos-Incompleta 2 1 1)
  Igual '(d) un distinto y dos sin preparar: gana distinto' 'distinto' $s.Caso
  Igual '(d) y N cuenta solo los distintos' 1 $s.N
  $s = Siguiente (Estado-Siguiente @{ respuesta = 'corregir' }) (Datos-Incompleta 2 1 2 (Correccion-Siguiente))
  Igual '(d) con correccion: gana distinto-corregido' 'distinto-corregido' $s.Caso
  Igual '(d) y N cuenta solo los distintos' 2 $s.N
}

$Pruebas['m20c portada (a, b): local-incompleta no dice que el codigo da lo mismo; dice cuantos casos faltan, que relances el mismo comando y, con uno solo, su variante'] = {
  $i = Salida-Siguiente 'm20c-incompleta' (Estado-Siguiente) @{ 'prueba-local.json' = (Datos-Incompleta 3 1).PruebaLocal }
  $sec = Panel-De $i 'siguiente-paso'
  $t = Texto-Plano $sec
  Comprueba '3 de 4 casos no se han podido probar' ($t -match '3 de 4 casos no se han podido probar\.') $t
  Comprueba 'hasta que se prueben no se puede asegurar que haga lo mismo' ($t -match 'Hasta que se prueben, no se puede asegurar que tu c.digo haga lo mismo que el original\.') $t
  Comprueba 'dice que relances el mismo comando y que lo hecho no se repite' ($t -match 'Relanza el mismo comando: lo hecho no se repite') $t
  Comprueba 'la frase da lo mismo no sale en la portada' ($i -notmatch 'da lo mismo') ([regex]::Match($i, '.{60}da lo mismo.{60}').Value)
  $cmd = [regex]::Match($sec, '(?s)<pre class="cmd">(.*?)</pre>').Groups[1].Value
  Igual 'el comando es el de la pasada, con -SoloInforme' ('.\migracion.ps1 -Legacy &quot;C:\ruta\original&quot; -Migrado &quot;C:\ruta\migrado&quot; -Plantilla &quot;C:\ruta\referencia&quot; -Modelo claude-sonnet-5.5 -SoloInforme') $cmd
  Comprueba 'enlaza a la pagina 3' ($sec -match 'href="3-original-vs-migrado\.html"')
  $i = Salida-Siguiente 'm20c-incompleta-uno' (Estado-Siguiente) @{ 'prueba-local.json' = (Datos-Incompleta 1 3).PruebaLocal }
  $t = Texto-Plano (Panel-De $i 'siguiente-paso')
  Comprueba '(b) con uno solo, la variante en singular: 1 de 4 casos no se ha podido probar' ($t -match '1 de 4 casos no se ha podido probar\.' -and $t -match 'Hasta que se pruebe, no se puede asegurar') $t
  Comprueba '(b) y tampoco dice da lo mismo' ($i -notmatch 'da lo mismo')
  # lo que ya decia, igual: con todo igual y problemas por corregir, la portada de siempre
  $i = Salida-Siguiente 'm20c-incompleta-igual' (Estado-Siguiente) @{ 'prueba-local.json' = (Datos-Incompleta 0 3).PruebaLocal; 'hallazgos-antes.json' = @((Hallazgo 'estructura' 'error' 'src/main/java/A.java' 3 'clase suelta A')); 'diagnostico-antes.md' = (Md-Diagnostico 'compila: SI | tests: OK') }
  Comprueba '(c) con todo igual y un problema, la portada dice lo de siempre' ((Texto-Plano (Panel-De $i 'siguiente-paso')) -match 'Tu c.digo da lo mismo que el original\. Para corregir el problema') (Texto-Plano (Panel-De $i 'siguiente-paso'))
}

$Pruebas['m20c portada: la frase da lo mismo que el original solo esta en los trozos de parar-con-problemas, que local-incompleta deja atras; y Lo que te toca lista los casos que no se pudieron preparar'] = {
  $raiz = Split-Path -Parent $Script
  foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $raiz 'informe') -File -Filter '*.html')) {
    $l = @([System.IO.File]::ReadAllLines($f.FullName, (New-Object System.Text.UTF8Encoding($false))) | Where-Object { $_ -match 'da lo mismo' -and $_ -notmatch '^<!--TROZO siguiente-parar-con-problemas(-uno)?-->' })
    Comprueba ($f.Name + ': no promete que da lo mismo fuera de parar-con-problemas') ($l.Count -eq 0) ($l -join ' / ')
  }
  $i = Salida-Siguiente 'm20c-toca' (Estado-Siguiente) @{ 'prueba-local.json' = (Datos-Incompleta 3 1).PruebaLocal }
  $toca = Toca-De $i
  Comprueba 'Lo que te toca tiene el grupo de casos sin probar, con su cuenta' ((Texto-De $toca) -match 'Casos sin probar en local \(3\)') (Texto-De $toca)
  Comprueba 'con un item por caso: job, caso, titulo y el motivo' ([regex]::Matches($toca, 'caso-s\d').Count -eq 3 -and (Texto-De $toca) -match 'Sin preparar 1\. La IA no ha podido preparar sus entradas: atascada\.') (Texto-De $toca)
  Comprueba 'y ya no dice Nada que revisar' ($toca -notmatch 'Nada que revisar')
  $i = Salida-Siguiente 'm20c-toca-nada' (Estado-Siguiente) @{ 'prueba-local.json' = (Datos-Incompleta 0 3).PruebaLocal }
  $toca = Toca-De $i
  Comprueba 'con todo igual no hay grupo de casos sin probar' ($toca -notmatch 'Casos sin probar' -and $toca -match 'Nada que revisar') (Texto-De $toca)
}

# El migrado con tres secretos con valor por defecto (en un yml anidado, en un yml con la clave plana y en un .properties) y tres variables normales.
function Escenario-Secretos([string]$Nombre) {
  $e = Escenario-Dos $Nombre
  Escribe $e.Migrado 'src/main/resources/application.yml' "spring:`n  datasource:`n    url: `${DB_URL:jdbc:h2:mem:batch}`n    password: `${DB_PASSWORD:Dev2024!}`nbatch:`n  chunk: `${CHUNK:100}`n  ttl: `${PASSWORD_TTL:300}`n"
  Escribe $e.Migrado 'src/main/resources/application-pre.yml' "spring.datasource.password: `${DB_PASS:x-valor-2}`n"
  Escribe $e.Migrado 'src/main/resources/application-pre.properties' "api.token=`${API_VALOR:tkn-3}`nsftp.port=`${SFTP_PORT:22}`n"
  [void](GitEn $e.Migrado @('add', '-A'))
  [void](GitEn $e.Migrado @('commit', '-q', '-m', 'recursos'))
  return $e
}

$Pruebas['m20c secretos (e, f): el valor por defecto de un secreto no esta en variables.json ni en la pagina 1, que dice que no se ensena; una variable normal sigue con su valor'] = {
  $e = Escenario-Secretos 'm20c-secretos'
  $r = Migra $e (Basicos $e) $GuionBase
  Igual 'sale con 0' 0 $r.Codigo
  $crudo = Lee $e.Out 'datos/variables.json'
  foreach ($valor in @('Dev2024!', 'x-valor-2', 'tkn-3')) { Comprueba "variables.json no lleva $valor" (-not $crudo.Contains($valor)) }
  $v = @(Lee-Json (Get-Ruta $e.Out 'datos/variables.json'))
  Igual 'estan las 7 variables' 7 $v.Count
  foreach ($n in @('DB_PASSWORD', 'DB_PASS', 'API_VALOR')) {
    $x = @($v | Where-Object { $_.variable -eq $n })[0]
    Comprueba "$n : secreto true y sin valor por defecto" ($null -ne $x -and $x.secreto -eq $true -and $null -eq $x.porDefecto) ($x | ConvertTo-Json -Compress)
    Comprueba "$n : conserva su fichero y su linea" ($x.fichero -match '^src/main/resources/application' -and [int]$x.linea -ge 1) ($x | ConvertTo-Json -Compress)
  }
  Igual 'DB_PASSWORD por el nombre de la variable, en application.yml' 'src/main/resources/application.yml 4' (@($v | Where-Object { $_.variable -eq 'DB_PASSWORD' })[0].fichero + ' ' + @($v | Where-Object { $_.variable -eq 'DB_PASSWORD' })[0].linea)
  Igual 'CHUNK sigue con su 100 y sin marca de secreto' '100|False' (@($v | Where-Object { $_.variable -eq 'CHUNK' })[0].porDefecto + '|' + ($null -ne @($v | Where-Object { $_.variable -eq 'CHUNK' })[0].secreto))
  Igual 'PASSWORD_TTL (empieza por password, no acaba) sigue con su 300' '300' @($v | Where-Object { $_.variable -eq 'PASSWORD_TTL' })[0].porDefecto
  Igual 'DB_URL sigue con su valor' 'jdbc:h2:mem:batch' @($v | Where-Object { $_.variable -eq 'DB_URL' })[0].porDefecto
  Igual 'SFTP_PORT (properties) sigue con su 22' '22' @($v | Where-Object { $_.variable -eq 'SFTP_PORT' })[0].porDefecto
  $o = Pagina $e.Out '1-batch-original.html'
  foreach ($valor in @('Dev2024!', 'x-valor-2', 'tkn-3')) { Comprueba "la pagina 1 no lleva $valor" (-not $o.Contains($valor)) }
  foreach ($n in @('DB_PASSWORD', 'DB_PASS', 'API_VALOR')) {
    Comprueba "la pagina 1 dice de $n que no se ensena" ((Texto-Plano $o) -match ($n + ' con valor por defecto \(no se ense.a: parece una contrase.a\)')) (Texto-Plano $o)
  }
  Comprueba '(f) CHUNK: con valor por defecto 100 en la pagina 1' ($o -match '<code>CHUNK</code> con valor por defecto <code>100</code>')
  Comprueba 'PASSWORD_TTL: con valor por defecto 300' ($o -match '<code>PASSWORD_TTL</code> con valor por defecto <code>300</code>')
  Comprueba 'DB_URL y SFTP_PORT, igual' ($o -match '<code>DB_URL</code> con valor por defecto <code>jdbc:h2:mem:batch</code>' -and $o -match '<code>SFTP_PORT</code> con valor por defecto <code>22</code>')
  $todas = (@('index.html', '2-problemas.html', '3-original-vs-migrado.html', '4-correcciones.html', '5-buenas-practicas.html') | ForEach-Object { Pagina $e.Out $_ }) -join "`n"
  Comprueba 'ninguna otra pagina lleva un valor secreto' ($todas -notmatch 'Dev2024|x-valor-2|tkn-3')
}

$Pruebas['m20c secretos: un variables.json de antes (con el valor y sin la marca secreto) se limpia al montar la pagina 1, por el nombre de la variable'] = {
  $e = Escenario-Secretos 'm20c-secretos-viejo'
  $r = Migra $e (Basicos $e) $GuionBase
  Igual 'sale con 0' 0 $r.Codigo
  $s = Copia-Salida $e 'm20c-secretos-viejo-copia'
  Guarda-Json (Join-Path $s 'datos/variables.json') @(
    [ordered]@{ variable = 'DB_PASSWORD'; porDefecto = 'Dev2024!'; fichero = 'src/main/resources/application.yml'; linea = 4 },
    [ordered]@{ variable = 'CHUNK'; porDefecto = '100'; fichero = 'src/main/resources/application.yml'; linea = 6 },
    [ordered]@{ variable = 'DB_USER'; porDefecto = $null; fichero = 'src/main/resources/application.yml'; linea = 3 })
  $g = Genera-Informes $s
  Comprueba 'Write-Informes sale bien' ($g.Codigo -eq 0 -and $g.Salida -match 'INFORMES-OK') (Cola $g.Salida)
  $o = Pagina $s '1-batch-original.html'
  Comprueba 'la pagina 1 no lleva el valor de un variables.json de antes' (-not $o.Contains('Dev2024!'))
  Comprueba 'dice que no se ensena' ((Texto-Plano $o) -match 'DB_PASSWORD con valor por defecto \(no se ense.a: parece una contrase.a\)') (Texto-Plano $o)
  Comprueba 'CHUNK sigue con su 100 y DB_USER sin valor' ($o -match '<code>CHUNK</code> con valor por defecto <code>100</code>' -and $o -match '<code>DB_USER</code> sin valor por defecto')
}

$Pruebas['m20c secretos: una variable nueva de la correccion que es un secreto con valor por defecto no sale como variable que falta dar'] = {
  $e = Nuevo-Escenario 'm20c-nuevas' @('Clase1')
  Escribe $e.Migrado 'src/main/resources/application.yml' "batch:`n  vieja: `${CLAVE_VIEJA}`n"
  [void](GitEn $e.Migrado @('add', '-A'))
  [void](GitEn $e.Migrado @('commit', '-q', '-m', 'recursos'))
  $o = Orden-Base
  $o.ficheros = [ordered]@{ 'src/main/resources/application.yml' = "batch:`n  vieja: `${CLAVE_VIEJA}`n  nueva: `${CLAVE_NUEVA}`n  pwd: `${NUEVA_PASSWORD:dev-pw}`n  otra: `${CON_DEFECTO:x}`n" }
  $r = Migra-Motor $e $o (Corrige $e)
  Igual 'sale con 0' 0 $r.Codigo
  $c = Lee-Json (Get-Ruta $e.Out 'datos/correcciones.json')
  Comprueba 'hay correcciones.json' ($null -ne $c) (Cola $r.Salida)
  if ($null -eq $c) { return }
  Igual 'variablesNuevas: solo la que no tiene valor por defecto; la contrasena con valor por defecto no cuenta como sin valor' 'CLAVE_NUEVA' (@($c.variablesNuevas | ForEach-Object { $_.variable }) -join '|')
}

$Pruebas['m20c commit de la IA (g): una lectura que hace git commit se deshace, el HEAD vuelve al de antes y la tarea queda invalida con su motivo'] = {
  $e = Nuevo-Escenario 'm20c-commit' @('Clase1', 'Clase2') @{ CopilotExe = (Join-Path $falsos 'm20c-copilot-commit.ps1') }
  $antes = GitEn $e.Migrado @('rev-parse', 'HEAD')
  $r = Migra $e (Basicos $e)
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'el HEAD del worktree es el de antes de las rondas' $antes (GitEn $e.Wt @('rev-parse', 'HEAD'))
  Igual 'no hay commits nuevos' 'inicial' (GitEn $e.Wt @('log', '--format=%s'))
  Igual 'el worktree queda limpio' '' (GitEn $e.Wt @('status', '--porcelain'))
  Comprueba 'el fichero del commit ya no esta' (@(Get-ChildItem -LiteralPath $e.Wt -Recurse -File -Filter 'commit-de-la-ia-*.txt' -ErrorAction SilentlyContinue).Count -eq 0)
  Igual 'sigue en la rama de rescate' ((Estado $e).rama) (GitEn $e.Wt @('rev-parse', '--abbrev-ref', 'HEAD'))
  $t = Tareas $e
  Igual 'las dos tareas quedan atascadas tras sus dos intentos' 2 (Cuenta-Estado $t 'atascada')
  Comprueba 'su ultimo intento es invalida' (@($t | Where-Object { $_.ultimoEstado -eq 'invalida' }).Count -eq 2) (($t | ForEach-Object { $_.ultimoEstado }) -join ' ')
  Comprueba 'con el motivo del commit' (@($t | Where-Object { $_.motivo -ceq 'La lectura hizo un commit en el repositorio. Lee sin cambiar nada: solo escribes el fichero de salida.' }).Count -eq 2) $t[0].motivo
  Igual 'no hay fichas (la ronda cuenta como fallida)' 0 (Fichas $e).Count
  # el commit en una rama nueva: el worktree vuelve a la rama y al HEAD de antes
  $e2 = Nuevo-Escenario 'm20c-commit-rama' @('Clase1') @{ CopilotExe = (Join-Path $falsos 'm20c-copilot-commit.ps1') }
  $antes2 = GitEn $e2.Migrado @('rev-parse', 'HEAD')
  $r2 = Con-Entorno @{ M20C_COMMIT = 'rama' } { Migra $e2 (Basicos $e2) }
  Igual 'rama nueva: sale con 0' 0 $r2.Codigo
  Igual 'rama nueva: vuelve a la rama de rescate' ((Estado $e2).rama) (GitEn $e2.Wt @('rev-parse', '--abbrev-ref', 'HEAD'))
  Igual 'rama nueva: el HEAD es el de antes' $antes2 (GitEn $e2.Wt @('rev-parse', 'HEAD'))
  Igual 'rama nueva: la tarea queda invalida con el motivo del commit' '1|invalida' ((Cuenta-Estado (Tareas $e2) 'atascada').ToString() + '|' + (Tareas $e2)[0].ultimoEstado)
  Comprueba 'rama nueva: con el motivo' ((Tareas $e2)[0].motivo -match 'hizo un commit')
  # solo cambia de rama, sin commit: el HEAD es el mismo, pero el worktree ya no esta en la rama de rescate
  $e3 = Nuevo-Escenario 'm20c-solo-rama' @('Clase1') @{ CopilotExe = (Join-Path $falsos 'm20c-copilot-commit.ps1') }
  $r3 = Con-Entorno @{ M20C_COMMIT = 'solo-rama' } { Migra $e3 (Basicos $e3) }
  Igual 'solo rama: sale con 0' 0 $r3.Codigo
  Igual 'solo rama: vuelve a la rama de rescate' ((Estado $e3).rama) (GitEn $e3.Wt @('rev-parse', '--abbrev-ref', 'HEAD'))
  Igual 'solo rama: la tarea queda invalida' '1|invalida' ((Cuenta-Estado (Tareas $e3) 'atascada').ToString() + '|' + (Tareas $e3)[0].ultimoEstado)
}

# ===================== M17: LO QUE HACEN LOS .sh QUE LANZAN EL BATCH =====================
# Los scripts que lanzan el jar (lanzadores.ps1): su inventario sin IA, el enlace con el job, la ficha de cada uno (ficha-sh) y su comparacion
# con el migrado (comparar-sh). Las formas de los scripts son inventadas: una larga en ksh (la A) y una de cuatro lineas en bash (la B).
$FormaA = @'
#!/bin/ksh
# Lanza la carga de cuotas con el modo y la fecha que le pidan
display_usage() {
  echo "Uso: cargas.ksh -f|--fecha dd/MM/yyyy -m|--modo ALTA|BAJA|CUOTA_IN|CUOTA_OUT|PAGOS"
  echo "  -f|--fecha  fecha de proceso (dd/MM/yyyy)"
  echo "  -m|--modo   ALTA, BAJA, CUOTA_IN, CUOTA_OUT o PAGOS"
}
FECHA=""
MODO=""
while [ "$1" != "" ]; do
  case $1 in
    -f | --fecha ) shift
                   FECHA=$1
                   ;;
    -m | --modo )  shift
                   MODO=$1
                   ;;
    * )            echo "Ejecucion incorrecta"
                   display_usage
                   exit 1
  esac
  shift
done
if [ -z "$FECHA" ]; then
  display_usage
  exit 1
fi
RUN_DAY=`date +%Y%m%d%H%M%S`
# antes de java se aparta lo que dejo la carga anterior (con mv)
cd /opt/acme/cargas/outbox
case $MODO in
  ALTA ) for j in `ls -rt SALIDA_ALTA_*.TXT 2>/dev/null`; do mv -f ${j} /opt/acme/cargas/outbox/backup/${j}.${RUN_DAY}; done ;;
  CUOTA_IN ) for j in `ls -rt SALIDA_CUOTAS_*.TXT 2>/dev/null`; do mv -f ${j} /opt/acme/cargas/outbox/backup/${j}.${RUN_DAY}; done ;;
esac
cd /opt/acme/cargas
java -jar ./jar/cargas-acme.jar ${MODO} ${FECHA}
if [ ! -f log/log-cargas-${MODO}.log ]; then
  echo "No existe el log de cargas"
fi
cp log/log-cargas-${MODO}.log logs/log-cargas-${MODO}-${RUN_DAY}.log
find /opt/acme/cargas/logs -type f -mtime +30 -print0 | xargs -0 rm
for f in `ls /opt/acme/cargas/inbox/ENTRADA_${MODO}_*.TXT 2>/dev/null`; do
  mv -f ${f} /opt/acme/cargas/inbox/backup/`basename ${f}`.${RUN_DAY}
done
exit 0
'@
$FormaB = @'
#!/usr/bin/env bash
cd /opt/acme/recibos/batch || exit
export spring_profiles_active=exportar_recibos
java -jar ./jar/batch-recibos.jar > ./logs/batch-recibos-exportar-recibos.log 2>&1
'@
$ScriptCuotas = @'
#!/usr/bin/env bash
export SPRING_PROFILES_ACTIVE=cargar_cuotas
exec java -Dfile.encoding=UTF-8 -jar ./jar/batch-cuotas.jar
'@
$ScriptImpagos = @'
#!/bin/sh
cd /opt/acme/impagos
java -jar ./jar/batch-impagos.jar --spring.batch.job.name=avisarImpagosJob
'@
$ScriptAvisos = @'
#!/bin/sh
java -jar ./jar/batch-impagos.jar --spring.profiles.active=avisar_impagos
'@
$ScriptRaro = @'
#!/bin/sh
export spring_profiles_active=inexistente
java -jar ./jar/batch-raro.jar
'@
# Los scripts que no cuentan para nada de arriba, uno por cada manera de saltarse un fichero, mas los ficheros de relleno
$ScriptsLanzadores = [ordered]@{
  'bin/cargas.ksh' = $FormaA; 'bin/recibos.sh' = $FormaB; 'bin/arranque' = $ScriptCuotas; 'bin/impagos.sh' = $ScriptImpagos
  'bin/avisos.sh' = $ScriptAvisos; 'bin/perfil-raro.sh' = $ScriptRaro
}
$ContratoTres = @(
  [pscustomobject]@{ nombre = 'cargarCuotasJob'; definidoEn = 'src/main/java/com/acme/old/CargarCuotasConfig.java' },
  [pscustomobject]@{ nombre = 'exportarRecibosJob'; definidoEn = 'src/main/java/com/acme/old/ExportarRecibosConfig.java' },
  [pscustomobject]@{ nombre = 'avisarImpagosJob'; definidoEn = 'src/main/java/com/acme/old/AvisarImpagosConfig.java' })

# Una clase de configuracion que define un job (con su paso) y, si se pide, lleva la anotacion de perfil.
function Config-Job([string]$Clase, [string]$Job, [string]$Paso, [string]$Perfil = '') {
  $t = (Jobs-Config @("${Job}:$Paso")).Replace('class JobsConfig', "class $Clase")
  if ($Perfil) { $t = $t.Replace("public class $Clase", "$Perfil`npublic class $Clase") }
  return $t
}

# El original con tres jobs (cada uno en su clase de configuracion) y los scripts de arriba. El perfil cargar_cuotas lleva a su job por @Profile,
# exportar_recibos por un application-<perfil>.yml y avisar_impagos por un @Profile con dos perfiles.
function Escenario-Lanzadores([string]$Nombre, [hashtable]$Ajustes = @{}, $Scripts = $null) {
  $e = Nuevo-Escenario $Nombre @() $Ajustes
  Escribe-Original $e @{
    CargarCuotasConfig = (Config-Job 'CargarCuotasConfig' 'cargarCuotasJob' 'cargarStep' '@Profile("cargar_cuotas")')
    ExportarRecibosConfig = (Config-Job 'ExportarRecibosConfig' 'exportarRecibosJob' 'exportarStep')
    AvisarImpagosConfig = (Config-Job 'AvisarImpagosConfig' 'avisarImpagosJob' 'avisarStep' '@Profile({"avisar_impagos", "pruebas"})')
    CargarReader = (Clase-Con 'CargarReader' @() 2)
    ExportarWriter = (Clase-Con 'ExportarWriter')
    AvisarSender = (Clase-Con 'AvisarSender')
  }
  Escribe $e.Legacy 'src/main/resources/application-exportar_recibos.yml' "spring:`n  batch:`n    job:`n      name: exportarRecibosJob`n"
  if ($null -eq $Scripts) { $Scripts = $ScriptsLanzadores }
  foreach ($k in $Scripts.Keys) { Escribe $e.Legacy $k $Scripts[$k] }
  [void](GitEn $e.Legacy @('add', '-A'))
  [void](GitEn $e.Legacy @('commit', '-q', '-m', 'lanzadores'))
  return $e
}

# El numero (desde 1) de la primera linea de $Texto que cumple $Rx.
function Linea-Con([string]$Texto, [string]$Rx) {
  $l = @($Texto -split "`r?`n")
  for ($i = 0; $i -lt $l.Count; $i++) { if ($l[$i] -match $Rx) { return ($i + 1) } }
  return 0
}

# Lo que escribe un script de prueba como clave=valor, por clave.
function Claves-De([string]$Salida) {
  $v = @{}
  foreach ($l in ($Salida -split "`n")) { if ($l -match '^(\w+)=(.*?)\r?$') { $v[$Matches[1]] = $Matches[2] } }
  return $v
}

$Pruebas['m17 lanzadores: lanzadores.ps1 solo define funciones, esta en ASCII y ninguna esta definida en otro fichero'] = {
  $raiz = Split-Path -Parent $Script
  $lib = Join-Path $raiz 'lanzadores.ps1'
  Comprueba 'existe lanzadores.ps1 junto a migracion.ps1' (Test-Path -LiteralPath $lib)
  if (-not (Test-Path -LiteralPath $lib)) { return }
  $t = [System.IO.File]::ReadAllText($lib)
  Comprueba 'solo ASCII' ($t -notmatch '[^\x00-\x7F]') ''
  Comprueba 'su cabecera lo explica (empieza con un comentario de bloque que nombra el fichero)' ($t -match '(?s)^<#.*?lanzadores\.ps1.*?#>') ''
  $r = En-Biblioteca 'lanzadores-carga' "'FUNCIONES=' + (@(Get-Command Get-FicherosLanzador, Get-InventarioLanzador, Get-JobLanzador, Get-Lanzadores, Get-IndicePerfiles -ErrorAction SilentlyContinue).Count)`n'FIN'"
  Igual 'cargarlo no ejecuta nada y sale con 0' 0 $r.Codigo
  Igual 'define las funciones del inventario y del enlace' '5' (Claves-De $r.Salida)['FUNCIONES']
  $otras = @($Script, (Join-Path $raiz 'comun.ps1'), (Join-Path $raiz 'tareas.ps1'), (Join-Path $raiz 'informe.ps1')) | ForEach-Object { Funciones-De $_ }
  $mias = @(Funciones-De $lib)
  $repetidas = @($mias | Where-Object { $otras -contains $_ })
  Comprueba 'sus funciones no estan en comun, tareas, migracion ni informe' ($repetidas.Count -eq 0) ($repetidas -join ', ')
}

$Pruebas['m17 lanzadores: el inventario encuentra .sh, .ksh, .bash y el script sin extension con #!; salta mvnw, gradlew, target, .git y node_modules'] = {
  $e = Escenario-Lanzadores 'lanz-ficheros'
  Escribe $e.Legacy 'bin/viejo.bash' "echo viejo`n"
  Escribe $e.Legacy 'mvnw' "#!/bin/sh`necho mvnw`n"
  Escribe $e.Legacy 'gradlew' "#!/usr/bin/env sh`necho gradlew`n"
  Escribe $e.Legacy 'target/generado.sh' "#!/bin/sh`necho generado`n"
  Escribe $e.Legacy 'node_modules/x/y.sh' "#!/bin/sh`necho y`n"
  Escribe $e.Legacy '.git-no/z.sh' "echo z`n"
  Escribe $e.Legacy 'bin/LEEME' "Esto no es un script.`n"
  Escribe $e.Legacy 'bin/herramienta' "#!/usr/bin/python3`nprint('no es un shell')`n"
  Escribe $e.Legacy 'bin/ksh-sin-extension' "#!/bin/ksh`necho ksh sin extension`n"
  $r = En-Biblioteca 'lanz-ficheros' ("foreach (`$f in @(Get-FicherosLanzador '" + $e.Legacy + "')) { 'F=' + `$f.Rel + '|' + `$f.Interprete }`n'FIN'")
  Igual 'el script de prueba sale con 0' 0 $r.Codigo
  $f = @($r.Salida -split "`n" | Where-Object { $_ -match '^F=' } | ForEach-Object { ($_ -replace '^F=', '').Trim() })
  Igual 'los scripts, por ruta relativa con / y en orden, cada uno con su interprete' '.git-no/z.sh|sh,bin/arranque|bash,bin/avisos.sh|sh,bin/cargas.ksh|ksh,bin/impagos.sh|sh,bin/ksh-sin-extension|ksh,bin/perfil-raro.sh|sh,bin/recibos.sh|bash,bin/viejo.bash|bash' ($f -join ',')
  Comprueba 'ni mvnw ni gradlew ni lo de target ni node_modules' (@($f | Where-Object { $_ -match 'mvnw|gradlew|target|node_modules' }).Count -eq 0) ($f -join ',')
  Comprueba 'ni un fichero sin extension que no empieza por #! de un shell' (@($f | Where-Object { $_ -match 'LEEME|herramienta' }).Count -eq 0) ($f -join ',')
}

$Pruebas['m17 lanzadores: el inventario de la forma A da las lineas java, parametro, fichero, fecha y salida con su numero; los comentarios y los echo no cuentan'] = {
  $dir = Join-Path $Dir 'lanz-inv-a'
  Escribe $dir 'cargas.ksh' $FormaA
  $codigo = @'
$lineas = [System.IO.File]::ReadAllLines('{{RUTA}}')
foreach ($x in @(Get-InventarioLanzador $lineas)) { 'I=' + $x.linea + '|' + $x.tipo + '|' + $x.detalle }
$j = @(Get-InventarioLanzador $lineas | Where-Object { $_.tipo -eq 'java' })[0]
'JAR=' + $j.jar
'ARGS=' + (@($j.argumentos) -join ' ')
'PROPS=' + (@($j.propiedades) -join ' ')
'FIN'
'@
  $r = En-Biblioteca 'lanz-inv-a' $codigo.Replace('{{RUTA}}', (Join-Path $dir 'cargas.ksh'))
  Igual 'el script de prueba sale con 0' 0 $r.Codigo
  $inv = @($r.Salida -split "`n" | Where-Object { $_ -match '^I=' } | ForEach-Object { ($_ -replace '^I=', '').Trim() })
  $v = Claves-De $r.Salida
  $tiene = { param($Linea, $Tipo) @($inv | Where-Object { $_ -match ('^' + $Linea + '\|' + $Tipo + '\|') }).Count -gt 0 }
  $n = { param($Rx) Linea-Con $FormaA $Rx }
  $todo = $inv -join ' ; '
  Comprueba 'java: la linea de java -jar' (& $tiene (& $n '^java -jar') 'java') $todo
  Igual 'java: el jar' './jar/cargas-acme.jar' $v['JAR']
  Igual 'java: los argumentos de detras del jar' '${MODO} ${FECHA}' $v['ARGS']
  Igual 'java: sin -D' '' $v['PROPS']
  Comprueba 'parametro: las dos opciones del case' ((& $tiene (& $n '^\s+-f \| --fecha') 'parametro') -and (& $tiene (& $n '^\s+-m \| --modo') 'parametro')) $todo
  Comprueba 'parametro: el $1 del bucle y del case' ((& $tiene (& $n 'while \[ "\$1"') 'parametro') -and (& $tiene (& $n 'case \$1 in') 'parametro')) $todo
  Comprueba 'fecha: el date +...' (& $tiene (& $n 'RUN_DAY=`date') 'fecha') $todo
  Comprueba 'salida: los dos exit 1 y el exit 0, cada uno en su linea' ((@($inv | Where-Object { $_ -match '\|salida\|' }).Count -eq 3) -and (& $tiene (Linea-Con $FormaA '^exit 0') 'salida')) $todo
  Comprueba 'fichero: el mv del bucle de ALTA (con su ls en la misma linea), el cp, el find con xargs rm y el mv final' ((& $tiene (& $n 'ALTA \) for') 'fichero') -and (& $tiene (& $n '^cp ') 'fichero') -and (& $tiene (& $n '^find ') 'fichero') -and (& $tiene (& $n '^  mv -f') 'fichero')) $todo
  Comprueba 'fichero: los dos cd tambien salen' ((& $tiene (& $n '^cd /opt/acme/cargas/outbox') 'fichero') -and (& $tiene (& $n '^cd /opt/acme/cargas$') 'fichero')) $todo
  Comprueba 'el comentario que dice mv y los echo con texto no dan fichero ni nada' (-not (& $tiene (& $n '^# antes de java') 'fichero') -and -not (& $tiene (& $n 'echo "Ejecucion incorrecta"') 'fichero') -and -not (& $tiene (& $n 'echo "Uso: cargas') 'parametro')) $todo
  Comprueba 'sin envio, lanza, cerrojo, perfil ni job' (@($inv | Where-Object { $_ -match '\|(envio|lanza|cerrojo|perfil|job)\|' }).Count -eq 0) $todo
}

$Pruebas['m17 lanzadores: el inventario de la forma B y de los otros da el perfil, el job, el envio, el lanza y el cerrojo, con su valor y su linea'] = {
  $dir = Join-Path $Dir 'lanz-inv-b'
  $lineasE = @('#!/bin/sh', 'export JAVA_OPTS="-Xmx1g -Dspring.profiles.active=p1,p2"', '# sftp en un comentario', 'sftp -b lote.txt usuario@host', 'echo resumen | mailx -s aviso a@acme.test',
    'curl -s http://acme.test/ok', './otro.sh', 'ksh /opt/acme/b.ksh', '. ./comun.sh', 'source ./ajustes.sh', "flock -n /var/run/batch.lock -c 'true'", 'PID=/tmp/batch.pid',
    'java -Dspring.batch.job.names=uno,dos -Dotra=1 -jar a.jar \', '   --fecha=2026-01-01')
  $textoE = $lineasE -join "`n"
  Escribe $dir 'b.sh' $FormaB
  Escribe $dir 'c.sh' $ScriptCuotas
  Escribe $dir 'd.sh' $ScriptImpagos
  Escribe $dir 'e.sh' ($textoE + "`n")
  $codigo = @'
foreach ($n in @('b', 'c', 'd', 'e')) {
  foreach ($x in @(Get-InventarioLanzador ([System.IO.File]::ReadAllLines('{{DIR}}/' + $n + '.sh')))) { 'I' + $n + '=' + $x.linea + '|' + $x.tipo + '|' + $x.detalle }
}
$j = @(Get-InventarioLanzador ([System.IO.File]::ReadAllLines('{{DIR}}/e.sh')) | Where-Object { $_.tipo -eq 'java' })[0]
'EPROPS=' + (@($j.propiedades) -join ' ')
'EARGS=' + (@($j.argumentos) -join ' ')
'EJAR=' + $j.jar
$j = @(Get-InventarioLanzador ([System.IO.File]::ReadAllLines('{{DIR}}/b.sh')) | Where-Object { $_.tipo -eq 'java' })[0]
'BJAR=' + $j.jar
'BARGS=' + (@($j.argumentos) -join ' ')
$j = @(Get-InventarioLanzador ([System.IO.File]::ReadAllLines('{{DIR}}/c.sh')) | Where-Object { $_.tipo -eq 'java' })[0]
'CPROPS=' + (@($j.propiedades) -join ' ')
'FIN'
'@
  $r = En-Biblioteca 'lanz-inv-b' $codigo.Replace('{{DIR}}', $dir)
  Igual 'el script de prueba sale con 0' 0 $r.Codigo
  $v = Claves-De $r.Salida
  $de = { param($P) @($r.Salida -split "`n" | Where-Object { $_ -match ('^I' + $P + '=') } | ForEach-Object { ($_ -replace '^I\w=', '').Trim() }) }
  Igual 'forma B: el cd, el perfil con su valor y java con su jar, y nada mas (el exit sin codigo no cuenta)' '2|fichero|cd,3|perfil|exportar_recibos,4|java|./jar/batch-recibos.jar' ((& $de 'b') -join ',')
  Igual 'forma B: el redireccionamiento no es un argumento' './jar/batch-recibos.jar|' ($v['BJAR'] + '|' + $v['BARGS'])
  Igual 'SPRING_PROFILES_ACTIVE en mayusculas tambien vale, y exec java' '2|perfil|cargar_cuotas,3|java|./jar/batch-cuotas.jar' ((& $de 'c') -join ',')
  Igual 'java con un -D antes del jar' '-Dfile.encoding=UTF-8' $v['CPROPS']
  Igual '--spring.batch.job.name= en los argumentos da una linea job con el nombre' '2|fichero|cd,3|java|./jar/batch-impagos.jar,3|job|avisarImpagosJob' ((& $de 'd') -join ',')
  $n = { param($Rx) Linea-Con $textoE $Rx }
  $esperado = @("$(& $n 'JAVA_OPTS')|perfil|p1,p2", "$(& $n '^sftp')|envio|sftp", "$(& $n 'mailx')|envio|mailx", "$(& $n '^curl')|envio|curl", "$(& $n '^\./otro')|lanza|./otro.sh", "$(& $n '^ksh ')|lanza|/opt/acme/b.ksh",
    "$(& $n '^\. \./comun')|lanza|./comun.sh", "$(& $n '^source ')|lanza|./ajustes.sh", "$(& $n '^flock')|cerrojo|flock", "$(& $n '^PID=')|cerrojo|.pid", "$(& $n '^java ')|java|a.jar", "$(& $n '^java ')|job|uno,dos")
  Igual 'el script mezclado: exactamente estas lineas (el sftp comentado y la linea del #! no cuentan)' (($esperado | Sort-Object) -join ' ; ') ((& $de 'e' | Sort-Object) -join ' ; ')
  Igual 'java con dos -D antes del jar' '-Dspring.batch.job.names=uno,dos -Dotra=1' $v['EPROPS']
  Igual 'y el argumento de la linea de seguida' '--fecha=2026-01-01' $v['EARGS']
  Igual 'y el jar' 'a.jar' $v['EJAR']
}

# El original de las pruebas del enlace: los dos ficheros de perfil, las clases con @Profile y una copia en target que no cuenta.
function Original-Enlace([string]$Nombre) {
  $d = Join-Path $Dir $Nombre
  Escribe $d 'src/main/resources/application-exportar_recibos.yml' "spring:`n  batch:`n    job:`n      name: exportarRecibosJob`n"
  Escribe $d 'src/main/resources/application-lote.properties' "# dos jobs a la vez`nspring.batch.job.names=cargarCuotasJob,exportarRecibosJob`n"
  Escribe $d 'src/main/resources/application-doble.yaml' "server:`n  port: 1`nspring.batch.job.name: exportarRecibosJob # el de recibos`n"
  Escribe $d 'target/classes/application-trampa.yml' "spring:`n  batch:`n    job:`n      name: cargarCuotasJob`n"
  Escribe $d 'src/main/java/com/acme/old/CargarCuotasConfig.java' (Config-Job 'CargarCuotasConfig' 'cargarCuotasJob' 'cargarStep' '@Profile("cargar_cuotas")')
  Escribe $d 'src/main/java/com/acme/old/ExportarRecibosConfig.java' ((Config-Job 'ExportarRecibosConfig' 'exportarRecibosJob' 'exportarStep').Replace('public class', "// antes: @Profile(`"trampa`")`n/* y @Profile(`"trampa`") */`npublic class"))
  Escribe $d 'src/main/java/com/acme/old/AvisarImpagosConfig.java' (Config-Job 'AvisarImpagosConfig' 'avisarImpagosJob' 'avisarStep' '@Profile({"avisar_impagos", "pruebas"})')
  Escribe $d 'src/main/java/com/acme/old/DobleConfig.java' (Config-Job 'DobleConfig' 'avisarImpagosJob' 'otroStep' '@Profile("doble")')
  Escribe $d 'bin/trampa.sh' "export SPRING_PROFILES_ACTIVE=trampa`njava -jar t.jar`n"
  foreach ($k in $ScriptsLanzadores.Keys) { Escribe $d $k $ScriptsLanzadores[$k] }
  Escribe $d 'bin/lote.sh' "export spring_profiles_active=lote`njava -jar l.jar`n"
  Escribe $d 'bin/doble.sh' "export spring_profiles_active=doble`njava -jar l.jar`n"
  return $d
}

$Pruebas['m17 lanzadores: el enlace con el job sale por argumento, por yml (o .properties) del perfil, por @Profile, por ser el unico, o queda sin enlazar; cada uno con su fichero y su linea'] = {
  $d = Original-Enlace 'lanz-enlace'
  $codigo = @'
$d = '{{DIR}}'
$jobs = @(
  [pscustomobject]@{ nombre = 'cargarCuotasJob'; definidoEn = 'src/main/java/com/acme/old/CargarCuotasConfig.java' },
  [pscustomobject]@{ nombre = 'exportarRecibosJob'; definidoEn = 'src/main/java/com/acme/old/ExportarRecibosConfig.java' },
  [pscustomobject]@{ nombre = 'avisarImpagosJob'; definidoEn = 'src/main/java/com/acme/old/AvisarImpagosConfig.java' })
$indice = Get-IndicePerfiles $d
function Enlace([string]$Script, $Jobs) {
  $rel = 'bin/' + $Script
  $inv = @(Get-InventarioLanzador ([System.IO.File]::ReadAllLines((Join-Path $d $rel))))
  $e = Get-JobLanzador $rel $inv $Jobs $indice
  return ($e.como + '|' + (@($e.jobs) -join '+') + '|' + $e.fichero + '|' + $e.linea)
}
foreach ($s in @('recibos.sh', 'arranque', 'impagos.sh', 'avisos.sh', 'perfil-raro.sh', 'cargas.ksh', 'lote.sh', 'doble.sh', 'trampa.sh')) { 'E_' + ($s -replace '\W', '_') + '=' + (Enlace $s $jobs) }
'E_UNICO=' + (Enlace 'cargas.ksh' @($jobs[1]))
'E_UNICO_PERFIL_AJENO=' + (Enlace 'arranque' @($jobs[1]))
'E_PERFIL_GANA_AL_UNICO=' + (Enlace 'arranque' @($jobs[0]))
'E_VACIO=' + (Enlace 'cargas.ksh' @())
'FIN'
'@
  $r = En-Biblioteca 'lanz-enlace' $codigo.Replace('{{DIR}}', $d)
  Igual 'el script de prueba sale con 0' 0 $r.Codigo
  $v = Claves-De $r.Salida
  $cfg = 'src/main/java/com/acme/old/'
  $n = { param($Fichero, $Rx) Linea-Con (Lee $d $Fichero) $Rx }
  Igual 'perfil con application-<perfil>.yml: ese job, con el fichero y la linea de name' ('yml|exportarRecibosJob|src/main/resources/application-exportar_recibos.yml|4') $v['E_recibos_sh']
  Igual 'perfil (en mayusculas, SPRING_PROFILES_ACTIVE) con una clase @Profile("..."): los jobs que define esa clase' "profile|cargarCuotasJob|${cfg}CargarCuotasConfig.java|$(& $n ($cfg + 'CargarCuotasConfig.java') '@Profile')" $v['E_arranque']
  Igual 'job en un argumento --spring.batch.job.name=: el del argumento, con el script y su linea' 'argumento|avisarImpagosJob|bin/impagos.sh|3' $v['E_impagos_sh']
  Igual '@Profile({"a", "perfil"}) con el perfil en un argumento --spring.profiles.active=' "profile|avisarImpagosJob|${cfg}AvisarImpagosConfig.java|$(& $n ($cfg + 'AvisarImpagosConfig.java') '@Profile')" $v['E_avisos_sh']
  Igual 'un perfil que no lleva a nada, con tres jobs: sin enlazar y sin fichero' 'sin-enlazar|||0' $v['E_perfil_raro_sh']
  Igual 'un script sin perfil ni job, con tres jobs: sin enlazar' 'sin-enlazar|||0' $v['E_cargas_ksh']
  Igual 'names= en un .properties: los dos jobs, con la linea de la propiedad' 'yml|cargarCuotasJob+exportarRecibosJob|src/main/resources/application-lote.properties|2' $v['E_lote_sh']
  Igual 'un application-<perfil>.yaml (con la clave plana y un comentario detras) gana a la clase @Profile del mismo perfil' 'yml|exportarRecibosJob|src/main/resources/application-doble.yaml|3' $v['E_doble_sh']
  Igual 'ni un application-<perfil>.yml en target ni un @Profile en un comentario cuentan' 'sin-enlazar|||0' $v['E_trampa_sh']
  Igual 'con un solo job en el batch y nada que lo enlace, ese job y su fichero' 'unico|exportarRecibosJob|src/main/java/com/acme/old/ExportarRecibosConfig.java|0' $v['E_UNICO']
  Igual 'un perfil que lleva a una clase que no es de ningun job del contrato no impide el unico' 'unico|exportarRecibosJob|src/main/java/com/acme/old/ExportarRecibosConfig.java|0' $v['E_UNICO_PERFIL_AJENO']
  Igual 'y un perfil que si enlaza gana a ser el unico' "profile|cargarCuotasJob|${cfg}CargarCuotasConfig.java|$(& $n ($cfg + 'CargarCuotasConfig.java') '@Profile')" $v['E_PERFIL_GANA_AL_UNICO']
  Igual 'sin ningun job en el contrato: sin enlazar' 'sin-enlazar|||0' $v['E_VACIO']
}

$Pruebas['m17 lanzadores: Get-Lanzadores junta los de la carpeta del original y los de -Lanzadores, cada uno con su id, su inventario y su enlace; los de fuera se distinguen'] = {
  $d = Original-Enlace 'lanz-todo'
  $fuera = Join-Path $Dir 'lanz-fuera'
  Escribe $fuera 'otro/importar.sh' "#!/bin/sh`nexport spring_profiles_active=lote`njava -jar x.jar`n"
  Escribe $fuera 'mvnw' "#!/bin/sh`n"
  $codigo = @'
$jobs = @(
  [pscustomobject]@{ nombre = 'cargarCuotasJob'; definidoEn = 'src/main/java/com/acme/old/CargarCuotasConfig.java' },
  [pscustomobject]@{ nombre = 'exportarRecibosJob'; definidoEn = 'src/main/java/com/acme/old/ExportarRecibosConfig.java' },
  [pscustomobject]@{ nombre = 'avisarImpagosJob'; definidoEn = 'src/main/java/com/acme/old/AvisarImpagosConfig.java' })
$l = @(Get-Lanzadores '{{DIR}}' '' $jobs)
'SIN=' + $l.Count
$l = @(Get-Lanzadores '{{DIR}}' '{{FUERA}}' $jobs)
'CON=' + $l.Count
'RELS=' + (@($l | ForEach-Object { $_.rel }) -join ',')
'IDS=' + (@($l | ForEach-Object { $_.id } | Select-Object -Unique).Count)
$x = @($l | Where-Object { $_.rel -eq 'bin/recibos.sh' })[0]
'RECIBOS=' + $x.interprete + '|' + $x.lineas + '|' + $x.enlace.como + '|' + (@($x.enlace.jobs) -join '+') + '|' + @($x.inventario).Count + '|' + $x.ruta
$y = @($l | Where-Object { $_.rel -like '*importar.sh' })[0]
'FUERA=' + $y.rel + '|' + $y.enlace.como + '|' + (@($y.enlace.jobs) -join '+') + '|' + $y.ruta
'ID=' + $x.id
'MISMOS=' + ((@($l | ForEach-Object { $_.id }) -join ',') -eq (@(Get-Lanzadores '{{DIR}}' '{{FUERA}}' $jobs | ForEach-Object { $_.id }) -join ','))
'FIN'
'@
  $r = En-Biblioteca 'lanz-todo' $codigo.Replace('{{DIR}}', $d).Replace('{{FUERA}}', $fuera)
  Igual 'el script de prueba sale con 0' 0 $r.Codigo
  $v = Claves-De $r.Salida
  Igual 'solo la carpeta del original: sus 9 scripts (cargas, recibos, arranque, impagos, avisos, perfil-raro, lote, doble y trampa)' '9' $v['SIN']
  Igual 'con -Lanzadores, uno mas (el mvnw de fuera tampoco cuenta)' '10' $v['CON']
  Comprueba 'los de la carpeta de fuera salen al final, con su prefijo para distinguirlos' ($v['RELS'] -match ',-Lanzadores/otro/importar\.sh$') $v['RELS']
  Igual 'ids distintos' '10' $v['IDS']
  Igual 'el de recibos: interprete, lineas, como se enlaza, el job, cuantas lineas de inventario (cd, perfil, java) y su ruta' ('bash|4|yml|exportarRecibosJob|3|' + (Join-Path $d 'bin/recibos.sh')) $v['RECIBOS']
  Igual 'el de fuera: el perfil lote lo enlaza con los dos jobs del .properties del original, y su ruta es la de fuera' ('-Lanzadores/otro/importar.sh|yml|cargarCuotasJob+exportarRecibosJob|' + (Join-Path $fuera 'otro/importar.sh')) $v['FUERA']
  Comprueba 'el id es sh- y ocho cifras hex, y es el mismo en otra pasada (sale de la ruta relativa)' ($v['ID'] -match '^sh-[0-9a-f]{8}$' -and $v['MISMOS'] -eq 'True') "$($v['ID']) $($v['MISMOS'])"
}

# ---- (c) ficha-sh: la tarea que cuenta lo que hace cada .sh ----
# Un original con los scripts de las formas A y B y el yml que enlaza al segundo, y su lanzador para las pruebas de la ficha.
function Original-Fichas([string]$Nombre, [string[]]$Scripts = @('cargas.ksh', 'recibos.sh')) {
  $d = Join-Path $Dir $Nombre
  Escribe $d 'src/main/resources/application-exportar_recibos.yml' "spring:`n  batch:`n    job:`n      name: exportarRecibosJob`n"
  if ($Scripts -contains 'cargas.ksh') { Escribe $d 'bin/cargas.ksh' $FormaA }
  if ($Scripts -contains 'recibos.sh') { Escribe $d 'bin/recibos.sh' $FormaB }
  return $d
}
$script:PreludioFicha = @'
$Datos = '{{DIR}}/datos'
$Fuentes = @('CargarReader', 'GestorRecibos') | ForEach-Object { [pscustomobject]@{ BaseName = $_ } }
$jobs = @(
  [pscustomobject]@{ nombre = 'cargarCuotasJob'; definidoEn = 'src/main/java/com/acme/old/CargarCuotasConfig.java' },
  [pscustomobject]@{ nombre = 'exportarRecibosJob'; definidoEn = 'src/main/java/com/acme/old/ExportarRecibosConfig.java' })
$l = @(Get-Lanzadores '{{LEG}}' '' $jobs)
'@

$Pruebas['m17 lanzadores: una tarea ficha-sh por script, con el texto numerado, el inventario, las lineas obligatorias y el job enlazado; la huella sigue al script; uno demasiado largo nace atascado'] = {
  $d = Original-Fichas 'ficha-tareas'
  $codigo = $script:PreludioFicha + "`n" + @'
$t = @(Get-TareasFichaSh $l $false)
'N=' + $t.Count
$a = @($t | Where-Object { $_.entradas.script -eq 'bin/cargas.ksh' })[0]
$b = @($t | Where-Object { $_.entradas.script -eq 'bin/recibos.sh' })[0]
'A=' + $a.id + '|' + $a.tipo + '|' + $a.estado + '|' + $a.salida + '|' + $a.entradas.lineas + '|' + $a.entradas.ruta
'B=' + $b.id + '|' + $b.estado + '|' + $b.salida
'REQ_A=' + ((@($a.entradas.requeridas | ForEach-Object { $_.tipo }) | Group-Object | Sort-Object Name | ForEach-Object { $_.Name + ':' + $_.Count }) -join ' ')
'REQ_B=' + (@($b.entradas.requeridas | ForEach-Object { '' + $_.linea + $_.tipo }) -join ',')
'JOB_A=' + $a.entradas.job
'JOB_B=' + $b.entradas.job
[System.IO.File]::WriteAllText('{{DIR}}/prompt-a.txt', (Get-Prompt $a '' ''))
[System.IO.File]::WriteAllText('{{DIR}}/prompt-b-reintento.txt', (Get-Prompt $b '' 'MOTIVO-DE-PRUEBA'))
$h0 = $a.entradas.huella
$a.estado = 'hecha'; $a.resultado = [pscustomobject]@{ x = 1 }; Save-Tarea $a
$t2 = @(Get-TareasFichaSh $l $false)
'REUSA=' + @($t2 | Where-Object { $_.entradas.script -eq 'bin/cargas.ksh' })[0].estado + '|' + @($t2 | Where-Object { $_.entradas.script -eq 'bin/recibos.sh' })[0].estado
[System.IO.File]::AppendAllText('{{LEG}}/bin/cargas.ksh', "# una linea mas`n")
$l3 = @(Get-Lanzadores '{{LEG}}' '' $jobs)
$a3 = @(Get-TareasFichaSh $l3 $false | Where-Object { $_.entradas.script -eq 'bin/cargas.ksh' })[0]
'CAMBIA=' + ($a3.entradas.huella -ne $h0) + '|' + $a3.estado
$Cfg.LineasPorTarea = 10
$t4 = @(Get-TareasFichaSh $l3 $false)
'LARGO_A=' + @($t4 | Where-Object { $_.entradas.script -eq 'bin/cargas.ksh' })[0].estado + '|' + @($t4 | Where-Object { $_.entradas.script -eq 'bin/cargas.ksh' })[0].motivo
'LARGO_B=' + @($t4 | Where-Object { $_.entradas.script -eq 'bin/recibos.sh' })[0].estado
'FIN'
'@
  $r = En-Biblioteca 'ficha-tareas' $codigo.Replace('{{DIR}}', (Join-Path $Dir 'ficha-tareas-datos')).Replace('{{LEG}}', $d)
  Igual 'el script de prueba sale con 0' 0 $r.Codigo
  $v = Claves-De $r.Salida
  $dd = Join-Path $Dir 'ficha-tareas-datos'
  Igual 'dos scripts, dos tareas' '2' $v['N']
  $ha = ($v['A'] -split '\|')
  Comprueba 'la de cargas.ksh: id fichash-<hash>, tipo ficha-sh, pendiente, su salida en datos/fichas-sh, sus lineas y su ruta' ($ha[0] -match '^fichash-[0-9a-f]{8}$' -and $ha[1] -eq 'ficha-sh' -and $ha[2] -eq 'pendiente' -and $ha[3] -eq ('datos/fichas-sh/sh-' + $ha[0].Substring(8) + '.json') -and $ha[4] -eq ('' + @($FormaA -split "`r?`n").Count) -and $ha[5] -eq (Join-Path $d 'bin/cargas.ksh')) $v['A']
  Igual 'las lineas obligatorias de la forma A: cinco de fichero (los mv, el cp y el find; sin los cd ni el ls) y tres de salida' 'fichero:5 salida:3' $v['REQ_A']
  Igual 'las de la forma B: el perfil y nada mas (el cd no obliga y el java no es una accion)' ('3perfil') $v['REQ_B']
  Comprueba 'el job de la A: sin enlazar; el de la B: el del yml, con su fichero y linea' ($v['JOB_A'] -match '^ninguno' -and $v['JOB_B'] -match 'exportarRecibosJob' -and $v['JOB_B'] -match 'application-exportar_recibos\.yml:4') "$($v['JOB_A']) // $($v['JOB_B'])"
  $p = ''
  if (Test-Path -LiteralPath (Join-Path $dd 'prompt-a.txt')) { $p = [System.IO.File]::ReadAllText((Join-Path $dd 'prompt-a.txt')) }
  Comprueba 'el prompt: TIPO, SCRIPT y ESCRIBIR, sin LEER ni nada que leer en disco' ($p -match '(?m)^TIPO: ficha-sh\r?$' -and $p -match '(?m)^SCRIPT: bin/cargas\.ksh\r?$' -and $p -match '(?m)^ESCRIBIR: \.rescate/tareas/fichash-[0-9a-f]{8}\.json\r?$' -and $p -notmatch '(?m)^LEER:') ($p.Substring(0, [Math]::Min(300, $p.Length)))
  Comprueba 'el prompt lleva el script entero con el numero de cada linea' ($p -match '(?m)^\s+1\| #!/bin/ksh\r?$' -and $p -match ('(?m)^\s+' + (Linea-Con $FormaA '^exit 0') + '\| exit 0\r?$') -and $p.Contains('java -jar ./jar/cargas-acme.jar ${MODO} ${FECHA}')) ''
  Comprueba 'el inventario con su linea y su tipo, las lineas obligatorias y el job' ($p -match ('(?m)^' + (Linea-Con $FormaA '^java -jar') + ' \[java\] \./jar/cargas-acme\.jar\r?$') -and $p -match '(?m)^OBLIGATORIAS: \d+(, \d+)+\r?$' -and $p -match '(?m)^JOB ENLAZADO: ninguno') ''
  Comprueba 'lleva la lista de frases de relleno y el maximo de la cita' ($p.Contains('"de forma clara"') -and $p -match 'ximo 120 caracteres') ''
  $q = ''
  if (Test-Path -LiteralPath (Join-Path $dd 'prompt-b-reintento.txt')) { $q = [System.IO.File]::ReadAllText((Join-Path $dd 'prompt-b-reintento.txt')) }
  Comprueba 'el reintento lleva la correccion con el motivo' ($q -match '(?s)## CORRECCI.*MOTIVO-DE-PRUEBA') ''
  Igual 'una tarea hecha con la misma huella se reutiliza y la otra sigue pendiente' 'hecha|pendiente' $v['REUSA']
  Igual 'con una linea mas en el script la huella cambia y la tarea vuelve a pendiente' 'True|pendiente' $v['CAMBIA']
  Comprueba 'un script de mas de 3 * LineasPorTarea lineas nace atascado, con el motivo; el corto no' ($v['LARGO_A'] -match '^atascada\|' -and $v['LARGO_A'] -match 'pasa de 30 lineas' -and $v['LARGO_A'] -match 'bin/cargas\.ksh' -and $v['LARGO_B'] -eq 'pendiente') "$($v['LARGO_A']) // $($v['LARGO_B'])"
}

$Pruebas['m17 lanzadores: Test-FichaSh - una salida buena vale; una cita inventada no; si faltan las lineas de un mv y un exit 1 el motivo las nombra y en el ultimo intento quedan en sinExplicar'] = {
  $d = Original-Fichas 'ficha-valida' @('cargas.ksh')
  $codigo = $script:PreludioFicha + "`n" + @'
$t = @(Get-TareasFichaSh $l $false)[0]
$lin = [System.IO.File]::ReadAllLines($t.entradas.ruta)
$base = Join-Path '{{DIR}}' 'w'
function Cita([int]$N) { $x = $lin[$N - 1].Trim(); return $x.Substring(0, [Math]::Min(100, $x.Length)) }
$nf = @(1..$lin.Count | Where-Object { $lin[$_ - 1] -match '-f \| --fecha' })[0]
function Buena {
  $acc = @(); $sal = @()
  foreach ($r in $t.entradas.requeridas) {
    if ($r.tipo -eq 'salida') { $sal += [ordered]@{ codigo = [int]$r.detalle; cuando = 'Cuando acaba la carga o la llamada esta mal.'; linea = $r.linea; cita = (Cita $r.linea) } }
    else { $acc += [ordered]@{ cuando = 'antes'; condicion = ''; que = 'mueve'; detalle = 'Aparta los ficheros que dejo la carga anterior.'; linea = $r.linea; cita = (Cita $r.linea) } }
  }
  return [ordered]@{ paraQue = 'Lanza la carga de cuotas del dia.'; parametros = @([ordered]@{ nombre = '--fecha'; obligatorio = $true; valores = 'una fecha'; formato = 'dd/MM/yyyy'; linea = $nf; cita = (Cita $nf) }); acciones = $acc; salidas = $sal }
}
function Prueba([string]$Nombre, $Ficha, [int]$Intentos = 0) {
  $dir = Join-Path $base $Nombre
  [void](New-Item -ItemType Directory -Path (Join-Path $dir '.rescate/tareas') -Force)
  [System.IO.File]::WriteAllText((Join-Path $dir ('.rescate/tareas/' + $t.id + '.json')), (ConvertTo-Json -InputObject $Ficha -Depth 6))
  $t.intentos = $Intentos
  $r = Test-FichaSh $t $dir
  if ($r.Ok) { return ('BIEN acc=' + @($r.Ficha.acciones).Count + ' sal=' + @($r.Ficha.salidas).Count + ' par=' + @($r.Ficha.parametros).Count + ' probados=' + @(@($r.Ficha.acciones) + @($r.Ficha.salidas) + @($r.Ficha.parametros) | Where-Object { $_.probado }).Count + ' sin=' + (@($r.Ficha.sinExplicar | ForEach-Object { '' + $_.linea + ':' + $_.tipo }) -join '+') + ' paraQue=' + $r.Ficha.paraQue + ' script=' + $r.Ficha.script) }
  return ('MAL ' + $r.Motivo)
}
function Sin-Esas($Ficha) {
  $mv = @($t.entradas.requeridas | Where-Object { $_.tipo -eq 'fichero' -and $_.detalle -match 'mv' })[0].linea
  $ex = @($t.entradas.requeridas | Where-Object { $_.tipo -eq 'salida' -and $_.detalle -eq '1' })[0].linea
  $Ficha.acciones = @($Ficha.acciones | Where-Object { $_.linea -ne $mv })
  $Ficha.salidas = @($Ficha.salidas | Where-Object { $_.linea -ne $ex })
  return $Ficha
}
'V1=' + (Prueba 'v1' (Buena))
$f = Buena; foreach ($x in @($f.acciones) + @($f.salidas) + @($f.parametros)) { $x.cita = 'esta cita no sale en el script ' + $x.linea }
'V2=' + (Prueba 'v2' $f)
'V3=' + (Prueba 'v3' (Sin-Esas (Buena)))
'V4=' + (Prueba 'v4' (Sin-Esas (Buena)) 1)
$f = Buena; $cp = @($f.acciones | Where-Object { $_.cita -like 'cp *' })[0]; $cp.cita = 'cp esto-no-esta-en-el-script x y'
'V5=' + (Prueba 'v5' $f)
'V5B=' + (Prueba 'v5b' $f 1)
$f = Buena; $f.acciones[0].detalle = 'Mueve lo que deja GestorRecibos.'
'V6=' + (Prueba 'v6' $f)
$f = Buena; $f.acciones[0].cuando = 'nunca'
'V7=' + (Prueba 'v7' $f)
$f = Buena; $f.acciones[0].que = 'inventado'
'V8=' + (Prueba 'v8' $f)
$f = Buena; $f.parametros[0].obligatorio = 'si'
'V9=' + (Prueba 'v9' $f)
$f = Buena; $f.salidas[0].codigo = 'uno'
'V10=' + (Prueba 'v10' $f)
$f = Buena; $f.parametros = 'fecha'
'V11=' + (Prueba 'v11' $f)
$f = Buena; $f.paraQue = '   '
'V12=' + (Prueba 'v12' $f)
$f = Buena; $f.acciones[0].linea = 0
'V13=' + (Prueba 'v13' $f)
$f = Buena; $f.Remove('salidas')
'V14=' + (Prueba 'v14' $f)
$f = Buena; $f.salidas[0].codigo = 0; $f.acciones[1].condicion = 'Si el modo es ALTA.'
'V15=' + (Prueba 'v15' $f)
'FIN'
'@
  $r = En-Biblioteca 'ficha-valida' $codigo.Replace('{{DIR}}', (Join-Path $Dir 'ficha-valida-datos')).Replace('{{LEG}}', $d)
  Igual 'el script de prueba sale con 0' 0 $r.Codigo
  $v = Claves-De $r.Salida
  $mv = Linea-Con $FormaA '^\s+ALTA \) for'
  $ex = Linea-Con $FormaA '^\s+exit 1$'
  Igual 'una salida buena vale: las ocho lineas obligatorias contadas (5 acciones y 3 salidas), el parametro, todo con su cita comprobada, y trae el script y el paraQue' 'BIEN acc=5 sal=3 par=1 probados=9 sin= paraQue=Lanza la carga de cuotas del dia. script=bin/cargas.ksh' $v['V1']
  Comprueba 'con todas las citas inventadas se rechaza y el motivo dice que son las citas' ($v['V2'] -match '^MAL ' -and $v['V2'] -match 'citas' -and $v['V2'] -match 'no salen') $v['V2']
  Comprueba 'sin las lineas de un mv y de un exit 1 se rechaza y el motivo nombra las dos lineas, con su texto' ($v['V3'] -match '^MAL Te faltan las lineas' -and $v['V3'] -match "\b$mv\b" -and $v['V3'] -match "\b$ex\b" -and $v['V3'] -match 'mv' -and $v['V3'] -match 'exit 1') $v['V3']
  $esperadas = (@([pscustomobject]@{ L = $mv; T = 'fichero' }, [pscustomobject]@{ L = $ex; T = 'salida' }) | Sort-Object L | ForEach-Object { '' + $_.L + ':' + $_.T }) -join '+'
  Igual 'en el ultimo intento vale y las dos lineas quedan en sinExplicar, por orden de linea (la del mv como fichero y la del exit como salida)' "BIEN acc=4 sal=2 par=1 probados=7 sin=$esperadas paraQue=Lanza la carga de cuotas del dia. script=bin/cargas.ksh" $v['V4']
  Comprueba 'una sola cita inventada (de nueve) no tumba la ficha, pero esa linea no cuenta como explicada: el motivo la nombra' ($v['V5'] -match '^MAL Te faltan las lineas' -and $v['V5'] -match ('\b' + (Linea-Con $FormaA '^cp ') + '\b')) $v['V5']
  Comprueba 'y en el ultimo intento queda en sinExplicar y esa accion se guarda sin probar' ($v['V5B'] -match 'probados=8 ' -and $v['V5B'] -match ('sin=' + (Linea-Con $FormaA '^cp ') + ':fichero ')) $v['V5B']
  Comprueba 'un nombre de clase en un detalle no vale y el motivo lo nombra' ($v['V6'] -match '^MAL ' -and $v['V6'] -match 'GestorRecibos') $v['V6']
  Comprueba 'cuando fuera de la lista: el motivo lo dice' ($v['V7'] -match '^MAL ' -and $v['V7'] -match 'cuando' -and $v['V7'] -match 'antes') $v['V7']
  Comprueba 'que fuera de la lista: el motivo lo dice' ($v['V8'] -match '^MAL ' -and $v['V8'] -match 'que' -and $v['V8'] -match 'mueve') $v['V8']
  Comprueba 'obligatorio que no es true ni false' ($v['V9'] -match '^MAL ' -and $v['V9'] -match 'obligatorio') $v['V9']
  Comprueba 'codigo de salida que no es un numero' ($v['V10'] -match '^MAL ' -and $v['V10'] -match 'codigo') $v['V10']
  Comprueba 'parametros que no es una lista' ($v['V11'] -match '^MAL ' -and $v['V11'] -match 'parametros') $v['V11']
  Comprueba 'paraQue en blanco' ($v['V12'] -match '^MAL ' -and $v['V12'] -match 'paraQue') $v['V12']
  Comprueba 'una linea que no es un entero desde 1' ($v['V13'] -match '^MAL ' -and $v['V13'] -match 'acciones\[0\]\.linea') $v['V13']
  Comprueba 'sin el campo salidas' ($v['V14'] -match '^MAL ' -and $v['V14'] -match 'salidas') $v['V14']
  Comprueba 'un codigo de salida 0 y una condicion con texto valen' ($v['V15'] -match '^BIEN ') $v['V15']
}

$Pruebas['m17 lanzadores: Save-Lanzadores escribe datos/lanzadores.json y Save-FichasSh la ficha de cada tarea hecha en datos/fichas-sh'] = {
  $d = Original-Fichas 'ficha-guardar'
  $codigo = $script:PreludioFicha + "`n" + @'
Save-Lanzadores $l
$j = Read-Json (Join-Path $Datos 'lanzadores.json')
'N=' + @($j.lanzadores).Count
$x = @($j.lanzadores | Where-Object { $_.rel -eq 'bin/recibos.sh' })[0]
'X=' + $x.id + '|' + $x.interprete + '|' + $x.lineas + '|' + (@($x.jobs) -join '+') + '|' + $x.enlace.como + '|' + $x.enlace.fichero + '|' + $x.enlace.linea + '|' + @($x.inventario).Count + '|' + $x.ruta
$java = @($x.inventario | Where-Object { $_.tipo -eq 'java' })[0]
'JAVA=' + $java.jar + '|' + @($java.argumentos).Count + '|' + @($java.propiedades).Count
'LEIDOS=' + @(Read-Lanzadores).Count + '|' + @(Read-Lanzadores)[0].rel
$t = @(Get-TareasFichaSh $l $false)
$t[0].estado = 'hecha'
$t[0].resultado = [ordered]@{ id = $t[0].ficha; script = $t[0].entradas.script; paraQue = 'Algo.'; parametros = @(); acciones = @(); salidas = @(); sinExplicar = @() }
Save-FichasSh $t
'FICHAS=' + (@(Get-ChildItem (Join-Path $Datos 'fichas-sh') -Filter '*.json' | ForEach-Object { $_.Name }) -join ',')
'ID0=' + $t[0].ficha
'F0=' + (Read-Json (Join-Path $Datos ('fichas-sh/' + $t[0].ficha + '.json'))).script
'FIN'
'@
  $r = En-Biblioteca 'ficha-guardar' $codigo.Replace('{{DIR}}', (Join-Path $Dir 'ficha-guardar-datos')).Replace('{{LEG}}', $d)
  Igual 'el script de prueba sale con 0' 0 $r.Codigo
  $v = Claves-De $r.Salida
  Igual 'dos lanzadores en lanzadores.json' '2' $v['N']
  Igual 'el de recibos: id, interprete, lineas, jobs, como, fichero y linea del enlace, cuantas lineas de inventario y su ruta' ('' + ($v['X'] -split '\|')[0] + '|bash|4|exportarRecibosJob|yml|src/main/resources/application-exportar_recibos.yml|4|3|' + (Join-Path $d 'bin/recibos.sh')) $v['X']
  Comprueba 'el id empieza por sh-' (($v['X'] -split '\|')[0] -match '^sh-[0-9a-f]{8}$') $v['X']
  Igual 'el java del inventario lleva su jar, sin argumentos ni -D' './jar/batch-recibos.jar|0|0' $v['JAVA']
  Igual 'Read-Lanzadores lee lo guardado' '2|bin/cargas.ksh' $v['LEIDOS']
  Igual 'solo la ficha de la tarea hecha, con el id de la ficha' ($v['ID0'] + '.json') $v['FICHAS']
  Igual 'y es la de ese script' 'bin/cargas.ksh' $v['F0']
}

# ---- (d) comparar-sh: lo que hacia el .sh frente al codigo del migrado ----
# Un migrado con tres Java del mismo paquete (para que 'acme' sea una palabra comun) y un yml, y fichas de dos scripts ya hechas en datos/fichas-sh.
function Migrado-Sh([string]$Nombre) {
  $e = Nuevo-Escenario $Nombre @('Clase1')
  Escribe $e.Migrado 'src/main/resources/application.yml' "acme:`n  limpieza:`n    carpeta-logs: logs`n    dias: 30`n"
  Escribe $e.Migrado 'src/main/java/com/acme/life/ArchivadorSalidas.java' "package com.acme.life;`n`n/** Aparta las salidas de la carga anterior. */`npublic class ArchivadorSalidas {`n    static final String PATRON_ALTA = `"SALIDA_ALTA_`";`n}`n"
  foreach ($n in @('Otra1', 'Otra2')) { Escribe $e.Migrado "src/main/java/com/acme/life/$n.java" "package com.acme.life;`n`n/** Otra clase. */`npublic class $n {`n}`n" }
  [void](GitEn $e.Migrado @('add', '-A'))
  [void](GitEn $e.Migrado @('commit', '-q', '-m', 'migrado con configuracion'))
  return $e
}
$script:PreludioComparaSh = @'
$RepoRoot = '{{MIG}}'
$Datos = '{{DIR}}/datos'
$Base = Get-Rama $RepoRoot
function Accion([string]$Que, [int]$Linea, [string]$Cita, [string]$Detalle, [bool]$Probado = $true) {
  return [ordered]@{ cuando = 'antes'; condicion = ''; que = $Que; detalle = $Detalle; linea = $Linea; cita = $Cita; probado = $Probado }
}
$a0 = Accion 'mueve' 31 'ALTA ) for j in `ls -rt SALIDA_ALTA_*.TXT 2>/dev/null`; do mv -f ${j} /opt/acme/cargas/outbox/backup/${j}.${RUN_DAY}; done ;;' 'Aparta a la carpeta backup los ficheros de salida de alta.'
$a1 = Accion 'borra' 41 'find /opt/acme/cargas/logs -type f -mtime +30 -print0 | xargs -0 rm' 'Borra los registros de mas de 30 dias.'
$a2 = Accion 'mueve' 44 'mv -f ${f} /opt/acme/cargas/inbox/backup/`basename ${f}`.${RUN_DAY}' 'Aparta los ficheros de entrada ya cargados.'
$a3 = Accion 'otro' 46 'esta cita no sale en el script' 'Algo que no se pudo comprobar.' $false
Write-Json (Join-Path $Datos 'fichas-sh/sh-aaaaaaaa.json') ([ordered]@{ id = 'sh-aaaaaaaa'; script = 'bin/cargas.ksh'; paraQue = 'Lanza la carga.'; parametros = @(); acciones = @($a0, $a1, $a2, $a3); salidas = @(); sinExplicar = @() })
$b0 = Accion 'elige-job' 3 'export spring_profiles_active=exportar_recibos' 'Elige el perfil de exportar recibos.'
Write-Json (Join-Path $Datos 'fichas-sh/sh-bbbbbbbb.json') ([ordered]@{ id = 'sh-bbbbbbbb'; script = 'bin/recibos.sh'; paraQue = 'Lanza la exportacion.'; parametros = @(); acciones = @($b0); salidas = @(); sinExplicar = @() })
Write-Json (Join-Path $Datos 'fichas-sh/sh-cccccccc.json') ([ordered]@{ id = 'sh-cccccccc'; script = 'bin/vacio.sh'; paraQue = 'No hace nada mas.'; parametros = @(); acciones = @(); salidas = @(); sinExplicar = @() })
'@

$Pruebas['m17 lanzadores: Get-TareasCompararSh - elige sin IA de uno a tres ficheros del migrado por accion; sin candidatos es falta sin llamada; las acciones sin comprobar no se comparan'] = {
  $e = Migrado-Sh 'comparar-sh-tareas'
  $codigo = $script:PreludioComparaSh + "`n" + @'
$t = @(Get-TareasCompararSh $false $Base)
'N=' + $t.Count
$a = @($t | Where-Object { $_.entradas.script -eq 'bin/cargas.ksh' })[0]
$b = @($t | Where-Object { $_.entradas.script -eq 'bin/recibos.sh' })[0]
'A=' + $a.id + '|' + $a.tipo + '|' + $a.estado + '|' + $a.ficha + '|' + $a.salida + '|' + $a.entradas.ndatos
'IND=' + (@($a.entradas.indices) -join ',') + '|' + (@($a.entradas.sinCandidatos) -join ',')
'MIG=' + (@($a.entradas.migrado) -join ',')
'B=' + $b.id + '|' + $b.estado + '|' + @($b.resultado.comparacion).Count + '|' + $b.resultado.comparacion[0].estado + '|' + $b.resultado.comparacion[0].accion + '|' + $b.resultado.comparacion[0].busqueda + '|' + $b.resultado.comparacion[0].nota
'MOMENTO=' + $a.entradas.momento + '|' + ($a.entradas.commit -eq (Get-Head $RepoRoot).Substring(0, 7))
[System.IO.File]::WriteAllText('{{DIR}}/prompt.txt', (Get-Prompt $a '' ''))
$h0 = $a.entradas.huella
$a.estado = 'hecha'; $a.resultado = [pscustomobject]@{ x = 1 }; Save-Tarea $a
'REUSA=' + @(Get-TareasCompararSh $false $Base | Where-Object { $_.entradas.script -eq 'bin/cargas.ksh' })[0].estado
[System.IO.File]::AppendAllText((Join-Path $RepoRoot 'src/main/resources/application.yml'), "  otro: 1`n")
[void](& git -C $RepoRoot add -A)
[void](& git -C $RepoRoot commit -q -m 'cambia el migrado')
$a2 = @(Get-TareasCompararSh $false $Base | Where-Object { $_.entradas.script -eq 'bin/cargas.ksh' })[0]
'CAMBIA=' + ($a2.entradas.huella -ne $h0) + '|' + $a2.estado
'FIN'
'@
  $r = En-Biblioteca 'comparar-sh-tareas' $codigo.Replace('{{DIR}}', (Join-Path $Dir 'comparar-sh-tareas-datos')).Replace('{{MIG}}', $e.Migrado)
  Igual 'el script de prueba sale con 0' 0 $r.Codigo
  $v = Claves-De $r.Salida
  Igual 'dos tareas: la del script con acciones que buscar y la del que no tiene candidatos; el tercero no tiene acciones y no da tarea' '2' $v['N']
  $ha = ($v['A'] -split '\|')
  Comprueba 'la de cargas.ksh: id comparash-<hash>, tipo comparar-sh, pendiente, ficha sh-aaaaaaaa, su salida en datos/comparacion-sh y dos acciones por buscar' ($ha[0] -match '^comparash-[0-9a-f]{8}$' -and $ha[1] -eq 'comparar-sh' -and $ha[2] -eq 'pendiente' -and $ha[3] -eq 'sh-aaaaaaaa' -and $ha[4] -eq 'datos/comparacion-sh/sh-aaaaaaaa.json' -and $ha[5] -eq '2') $v['A']
  Igual 'se buscan las acciones 0 y 1; la 2 no tiene candidatos (acme sale en todos los ficheros y no cuenta) y la 3 no se compara por no estar comprobada' '0,1|2' $v['IND']
  Igual 'los ficheros del migrado: el Java con el patron de la 0 y el yml de la 1 (logs y el 30)' 'src/main/java/com/acme/life/ArchivadorSalidas.java,src/main/resources/application.yml' $v['MIG']
  $hb = ($v['B'] -split '\|')
  Comprueba 'la de recibos.sh nace hecha con la accion en falta, marcada sin candidatos y sin nota' ($hb[0] -match '^comparash-[0-9a-f]{8}$' -and $hb[1] -eq 'hecha' -and $hb[2] -eq '1' -and $hb[3] -eq 'falta' -and $hb[4] -eq '0' -and $hb[5] -eq 'sin-candidatos' -and $hb[6] -eq '') $v['B']
  Igual 'momento y commit con que se eligieron' 'antes-de-corregir|True' $v['MOMENTO']
  $p = ''
  $fp = Join-Path (Join-Path $Dir 'comparar-sh-tareas-datos') 'prompt.txt'
  if (Test-Path -LiteralPath $fp) { $p = [System.IO.File]::ReadAllText($fp) }
  Comprueba 'el prompt: TIPO, SCRIPT, ESCRIBIR, los dos ficheros del migrado, un dato numerado por accion buscada y el sitio del original de cada una' ($p -match '(?m)^TIPO: comparar-sh\r?$' -and $p -match '(?m)^SCRIPT: bin/cargas\.ksh\r?$' -and $p -match '(?m)^ESCRIBIR: \.rescate/tareas/comparash-[0-9a-f]{8}\.json\r?$' -and $p -match '(?m)^MIGRADO: src/main/resources/application\.yml\r?$' -and $p -match '(?m)^MIGRADO: src/main/java/com/acme/life/ArchivadorSalidas\.java\r?$' -and [regex]::Matches($p, '(?m)^\d+\. \[').Count -eq 2 -and $p -match '(?m)^0\. \[mueve\]' -and $p -match '(?m)^1\. \[borra\]' -and $p -match '(?m)^\s+Original: bin/cargas\.ksh:31 \| cita: ALTA \)' -and $p -notmatch '(?m)^LEER:') $p
  Igual 'una tarea hecha con la misma huella se reutiliza' 'hecha' $v['REUSA']
  Igual 'con otro commit del migrado la huella cambia y la tarea vuelve a pendiente' 'True|pendiente' $v['CAMBIA']
}

$Pruebas['m17 lanzadores: Test-CompararSh - una accion con cita en los dos lados vale; una cita inventada en el migrado no; las que no se buscaron salen en falta'] = {
  $e = Migrado-Sh 'comparar-sh-valida'
  $codigo = $script:PreludioComparaSh + "`n" + @'
$t = @(Get-TareasCompararSh $false $Base | Where-Object { $_.entradas.script -eq 'bin/cargas.ksh' })[0]
$arch = 'src/main/java/com/acme/life/ArchivadorSalidas.java'
$yml = 'src/main/resources/application.yml'
function El([int]$Dato, [string]$Estado, [string]$Fichero, [int]$Linea, [string]$Cita, [string]$Nota = '') {
  $x = [ordered]@{ dato = $Dato; estado = $Estado }
  if ($Fichero) { $x.fichero = $Fichero; $x.linea = $Linea; $x.cita = $Cita }
  if ($Nota) { $x.nota = $Nota }
  return $x
}
function Prueba([string]$Nombre, $Lista) {
  [void](New-Item -ItemType Directory -Path (Join-Path $RepoRoot '.rescate/tareas') -Force)
  [System.IO.File]::WriteAllText((Join-Path $RepoRoot ('.rescate/tareas/' + $t.id + '.json')), (ConvertTo-Json -InputObject ([ordered]@{ comparacion = $Lista }) -Depth 6))
  $r = Test-CompararSh $t $RepoRoot
  if ($r.Ok) { return ('BIEN ' + ((@($r.Ficha.comparacion) | ForEach-Object { '' + $_.accion + ':' + $_.estado + ':' + $_.busqueda + ':' + $_.probado }) -join ',')) }
  return ('MAL ' + $r.Motivo)
}
$buena = @((El 0 'igual' $arch 5 'static final String PATRON_ALTA = "SALIDA_ALTA_";'), (El 1 'distinto' $yml 4 'dias: 30' 'El migrado lo lee de la configuracion.'))
'V1=' + (Prueba 'v1' $buena)
'V2=' + (Prueba 'v2' @((El 0 'igual' $arch 5 'esta cita no sale en el migrado'), (El 1 'igual' $yml 4 'tampoco esta')))
'V3=' + (Prueba 'v3' @((El 0 'igual' 'src/main/java/com/acme/life/App.java' 3 'public class App {'), (El 1 'falta' '' 0 '' 'No lo encuentro.')))
'V4=' + (Prueba 'v4' @((El 0 'igual' $arch 5 'static final String PATRON_ALTA = "SALIDA_ALTA_";')))
'V5=' + (Prueba 'v5' @((El 0 'falta' '' 0 '' 'No esta.'), (El 1 'falta' '' 0 '' '')))
$t.resultado = (Test-CompararSh $t $RepoRoot).Ficha
'FIN'
'@
  $r = En-Biblioteca 'comparar-sh-valida' $codigo.Replace('{{DIR}}', (Join-Path $Dir 'comparar-sh-valida-datos')).Replace('{{MIG}}', $e.Migrado)
  Igual 'el script de prueba sale con 0' 0 $r.Codigo
  $v = Claves-De $r.Salida
  Igual 'una accion igual (cita en el Java) y otra distinta (cita en el yml, con nota) valen; la tercera, que no se busco, sale en falta sin busqueda, y todas con la cita probada' 'BIEN 0:igual:modelo:True,1:distinto:modelo:True,2:falta:sin-candidatos:False' $v['V1']
  Comprueba 'con las citas del migrado inventadas se rechaza y el motivo lo dice' ($v['V2'] -match '^MAL ' -and $v['V2'] -match 'Mas de la mitad' -and $v['V2'] -match 'migrado') $v['V2']
  Comprueba 'un fichero que no se le dio se rechaza y el motivo nombra los que si' ($v['V3'] -match '^MAL ' -and $v['V3'] -match 'ArchivadorSalidas\.java' -and $v['V3'] -match 'application\.yml') $v['V3']
  Comprueba 'una accion sin elemento se rechaza' ($v['V4'] -match '^MAL ' -and $v['V4'] -match 'faltan 1') $v['V4']
  Igual 'dos acciones en falta valen, y la que se busco y no se encontro se distingue de la que no se busco' 'BIEN 0:falta:modelo:False,1:falta:modelo:False,2:falta:sin-candidatos:False' $v['V5']
}

$Pruebas['m17 lanzadores: Save-ComparacionesSh escribe datos/comparacion-sh/<ficha>.json de cada tarea hecha, con el script, los ficheros, el momento y el commit'] = {
  $e = Migrado-Sh 'comparar-sh-guardar'
  $codigo = $script:PreludioComparaSh + "`n" + @'
$t = @(Get-TareasCompararSh $false $Base)
Save-ComparacionesSh $t
'FICHEROS=' + (@(Get-ChildItem (Join-Path $Datos 'comparacion-sh') -Filter '*.json' | ForEach-Object { $_.Name }) -join ',')
$j = Read-Json (Join-Path $Datos 'comparacion-sh/sh-bbbbbbbb.json')
'B=' + $j.ficha + '|' + $j.script + '|' + $j.momento + '|' + $j.commit.Length + '|' + @($j.acciones).Count + '|' + $j.acciones[0].estado + '|' + $j.acciones[0].accion
'FIN'
'@
  $r = En-Biblioteca 'comparar-sh-guardar' $codigo.Replace('{{DIR}}', (Join-Path $Dir 'comparar-sh-guardar-datos')).Replace('{{MIG}}', $e.Migrado)
  Igual 'el script de prueba sale con 0' 0 $r.Codigo
  $v = Claves-De $r.Salida
  Igual 'solo la de la tarea hecha (la otra sigue pendiente)' 'sh-bbbbbbbb.json' $v['FICHEROS']
  Igual 'ficha, script, momento, commit corto y la accion en falta' 'sh-bbbbbbbb|bin/recibos.sh|antes-de-corregir|7|1|falta|0' $v['B']
}

# ---- (f, g, h) la pasada entera: la fase lanzadores, comparar-sh dentro de comparar, relanzar y -Lanzadores ----
# El Copilot falso de estas pruebas es copilot-m6.ps1: escribe la ficha de un script y su comparacion con el migrado, y le pasa lo demas a copilot.ps1.
$ScriptLimpia = @'
#!/bin/sh
cd /opt/zeta/tmp
rm -f /opt/zeta/tmp/zork_*.dat
'@
function Escenario-Pasada([string]$Nombre, $Scripts) {
  $e = Escenario-Lanzadores $Nombre @{ CopilotExe = (Join-Path $falsos 'copilot-m6.ps1') } $Scripts
  Escribe $e.Migrado 'src/main/resources/application.yml' "spring:`n  profiles: exportar_recibos`n"
  [void](GitEn $e.Migrado @('add', '-A'))
  [void](GitEn $e.Migrado @('commit', '-q', '-m', 'configuracion'))
  Migrado-Con $e @('CargarReader')
  return $e
}
function Lanzadores-De($E) { return @((Lee-Json (Get-Ruta $E.Out 'datos/lanzadores.json')).lanzadores | Where-Object { $null -ne $_ }) }

$Pruebas['m17 lanzadores: sin ningun .sh en el original no hay tareas ni fase rota; la consola dice como pasar la carpeta con -Lanzadores y estado.json lo deja vacio'] = {
  $e = Escenario-Pasada 'm17-sin-sh' ([ordered]@{})
  $r = Migra $e (Basicos $e)
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'la fase acaba en hecha' 'hecha' (Estado $e).fase
  Igual 'ninguna tarea ficha-sh' 0 (Tareas $e 'ficha-sh').Count
  Igual 'ninguna tarea comparar-sh' 0 (Tareas $e 'comparar-sh').Count
  Comprueba 'las demas fases siguen: hay tareas de comparar-pieza hechas' ((Tareas $e 'comparar-pieza').Count -ge 1) (Cola $r.Salida)
  Igual 'datos/lanzadores.json existe y no lleva ninguno' 0 (Lanzadores-De $e).Count
  Comprueba 'no hay carpeta datos/fichas-sh con nada dentro' (-not (Test-Path -LiteralPath (Get-Ruta $e.Out 'datos/fichas-sh')) -or @(Get-ChildItem -LiteralPath (Get-Ruta $e.Out 'datos/fichas-sh') -File).Count -eq 0)
  $sal = $r.Salida
  $linea = [regex]::Match($sal, 'Lanzadores: [^\r\n]*').Value
  Comprueba 'la consola lleva la linea de Lanzadores con el texto de -Lanzadores <carpeta>' ($linea -match 'no hay' -and $linea.Contains('relanza con -Lanzadores <carpeta>')) $linea
  $m = $sal.IndexOf('Mapa:')
  $l = $sal.IndexOf('Lanzadores: ')
  $f = $sal.IndexOf('Fichas de job:')
  Comprueba 'y sale despues del mapa y antes de las fichas de job' ($m -ge 0 -and $l -gt $m -and $f -gt $l) (Cola $sal)
  Comprueba 'no hay linea de comparar-sh' ($sal -notmatch 'Lanzadores frente al migrado') (Cola $sal)
  Comprueba 'estado.json lleva lanzadores vacio' ((Estado $e).PSObject.Properties.Name -contains 'lanzadores' -and [string](Estado $e).lanzadores -eq '') ''
}

$Pruebas['m17 lanzadores: relanzar un batch que ya paso por mapa y comparar crea y hace solo las tareas nuevas (ficha-sh y comparar-sh); la tercera vez no repite ninguna'] = {
  $e = Escenario-Pasada 'm17-relanza' ([ordered]@{})
  $r1 = Migra $e (Basicos $e)
  Igual 'la primera pasada, sin scripts, sale con 0' 0 $r1.Codigo
  $antes = @(Llamadas $e.Wt)
  $piezas = @(Tareas $e 'comparar-pieza')
  Comprueba 'ya hay una pasada completa: fichas de clase y comparar-pieza hechas' ($antes.Count -ge 5 -and $piezas.Count -ge 1 -and (Cuenta-Estado $piezas 'hecha') -eq $piezas.Count) "$($antes.Count) llamadas"
  # llegan dos scripts: el de recibos (su perfil esta en el application.yml del migrado) y uno que no se parece a nada del migrado
  Escribe $e.Legacy 'bin/recibos.sh' $FormaB
  Escribe $e.Legacy 'bin/limpia.sh' $ScriptLimpia
  [void](GitEn $e.Legacy @('add', '-A'))
  [void](GitEn $e.Legacy @('commit', '-q', '-m', 'llegan los scripts'))
  $r2 = Migra $e (Basicos $e)
  Igual 'la segunda pasada sale con 0' 0 $r2.Codigo
  $ll2 = @(Llamadas $e.Wt)
  Igual 'llamadas nuevas: una ficha-sh por script y una comparar-sh (la del script sin candidatos no llama)' ($antes.Count + 3) $ll2.Count
  Igual 'dos de ficha-sh' 2 (Llamadas-De $ll2 'fichash-').Count
  Igual 'una de comparar-sh' 1 (Llamadas-De $ll2 'comparash-').Count
  Comprueba 'las llamadas de antes no se repiten (mismos ids y pids)' ((@($antes | ForEach-Object { $_.id + '/' + $_.pid }) -join ',') -ceq (@($ll2 | Where-Object { $_.id -notlike 'fichash-*' -and $_.id -notlike 'comparash-*' } | ForEach-Object { $_.id + '/' + $_.pid }) -join ',')) ''
  $fi = @(Tareas $e 'ficha-sh')
  $cs = @(Tareas $e 'comparar-sh')
  Igual 'dos tareas ficha-sh hechas' '2|2' "$($fi.Count)|$(Cuenta-Estado $fi 'hecha')"
  Igual 'dos tareas comparar-sh hechas' '2|2' "$($cs.Count)|$(Cuenta-Estado $cs 'hecha')"
  $cfi = @(Llamadas-De $ll2 'fichash-')
  Comprueba 'la ficha-sh se escribe con esfuerzo alto y sin leer el original (el script va en el prompt)' (@($cfi | Where-Object { $_.flags -match '--effort=high' -and $_.flags -notmatch '--add-dir' }).Count -eq 2) (($cfi | ForEach-Object { $_.flags }) -join ' / ')
  $ccs = @(Llamadas-De $ll2 'comparash-')
  Comprueba 'la comparar-sh es una lectura: esfuerzo de lectura' ($ccs[0].flags -match '--effort=medium') $ccs[0].flags
  $sin = @($cs | Where-Object { @($_.entradas.indices).Count -eq 0 })
  Igual 'la de limpia.sh nacio hecha, sin llamada, con su accion en falta sin candidatos' '1|True|falta|sin-candidatos' "$($sin.Count)|$(@($ll2 | Where-Object { $_.id -ceq $sin[0].id }).Count -eq 0)|$($sin[0].resultado.comparacion[0].estado)|$($sin[0].resultado.comparacion[0].busqueda)"
  Comprueba 'datos/fichas-sh y datos/comparacion-sh llevan los dos ficheros' (@(Get-ChildItem -LiteralPath (Get-Ruta $e.Out 'datos/fichas-sh') -File).Count -eq 2 -and @(Get-ChildItem -LiteralPath (Get-Ruta $e.Out 'datos/comparacion-sh') -File).Count -eq 2)
  $sal = $r2.Salida
  Comprueba 'la consola cuenta los dos scripts, uno enlazado con su job, y las fichas hechas' ($sal -match 'Lanzadores: 2 scripts, 1 enlazados con un job\. Fichas: 2 hechas, 0 atascadas') (Cola $sal)
  Comprueba 'y la comparacion de los scripts: dos comparados, una igual y una falta' ($sal -match 'Lanzadores frente al migrado: 2 scripts comparados\. Acciones: 1 igual, 0 distinto, 1 falta, 0 no lo se\.') (Cola $sal)
  Comprueba 'la linea de comparar de las clases sigue contando solo las clases' ($sal -match 'Comparacion con el original: \d+ clases comparadas\. Datos: ') (Cola $sal)
  $r3 = Migra $e (Basicos $e)
  Igual 'la tercera pasada sale con 0' 0 $r3.Codigo
  Igual 'y no llama a nadie mas' $ll2.Count (@(Llamadas $e.Wt)).Count
  Comprueba 'las tareas de lanzadores siguen hechas' ((Cuenta-Estado (Tareas $e 'ficha-sh') 'hecha') -eq 2 -and (Cuenta-Estado (Tareas $e 'comparar-sh') 'hecha') -eq 2) ''
}

$Pruebas['m17 lanzadores: -Lanzadores <carpeta> suma los scripts de fuera (ruta -Lanzadores/...), se enlaza con los jobs del original y se guarda en estado.json; relanzar sin el parametro lo mantiene'] = {
  $e = Escenario-Pasada 'm17-fuera' ([ordered]@{})
  $fuera = Join-Path $e.Raiz 'scripts-fuera'
  Escribe $fuera 'importar.sh' $FormaB
  $r = Migra $e ((Basicos $e) + @('-Lanzadores', $fuera))
  Igual 'sale con 0' 0 $r.Codigo
  $z = @(Lanzadores-De $e)
  Igual 'un lanzador, con la ruta de fuera' '1|-Lanzadores/importar.sh' "$($z.Count)|$($z[0].rel)"
  Igual 'enlazado por el yml del original con su job' 'yml|exportarRecibosJob' "$($z[0].enlace.como)|$(@($z[0].jobs) -join ',')"
  $fi = @(Tareas $e 'ficha-sh')
  Igual 'una tarea ficha-sh hecha de ese script' '1|1|-Lanzadores/importar.sh' "$($fi.Count)|$(Cuenta-Estado $fi 'hecha')|$($fi[0].entradas.script)"
  Igual 'estado.json guarda la carpeta' $fuera ([string](Estado $e).lanzadores)
  $n1 = @(Llamadas $e.Wt).Count
  $r2 = Migra $e (Basicos $e)
  Igual 'relanzar sin el parametro sale con 0' 0 $r2.Codigo
  Igual 'sigue habiendo el mismo script, sin llamadas nuevas' "1|$n1" "$((Lanzadores-De $e).Count)|$(@(Llamadas $e.Wt).Count)"
  Igual 'y estado.json sigue guardando la carpeta' $fuera ([string](Estado $e).lanzadores)
  $r3 = Migra $e ((Basicos $e) + @('-Lanzadores', (Join-Path $e.Raiz 'no-existe')))
  Igual 'una carpeta que no existe no deja arrancar' 1 $r3.Codigo
  Comprueba 'y el mensaje nombra -Lanzadores' ($r3.Salida -match '-Lanzadores') (Cola $r3.Salida)
}

# ---- (e) el informe: Como se lanza (pagina 1), Lanzadores (pagina 3), el grupo de la portada y el texto sin .sh ----
$MalSh = 'cuota <b>alta</b> & "baja"'
function Lanzador-Json([string]$Id, [string]$Rel, [string[]]$Jobs, [string]$Como) {
  return [ordered]@{ id = $Id; rel = $Rel; ruta = ('/orig/' + $Rel); interprete = 'ksh'; lineas = 46; jobs = @($Jobs); enlace = [ordered]@{ como = $Como; fichero = 'bin/x.yml'; linea = 3 }; inventario = @() }
}
function Item-Sh([string]$Cuando, [string]$Que, [int]$Linea, [string]$Cita, [string]$Detalle, [string]$Condicion = '', [bool]$Probado = $true) {
  return [ordered]@{ cuando = $Cuando; condicion = $Condicion; que = $Que; detalle = $Detalle; linea = $Linea; cita = $Cita; probado = $Probado }
}
function Elem-Comp([int]$Accion, [string]$Estado, [string]$Fichero, [int]$Linea, [string]$Cita, [string]$Nota, [bool]$Probado, [string]$Busqueda) {
  return [ordered]@{ accion = $Accion; estado = $Estado; fichero = $Fichero; linea = $Linea; cita = $Cita; nota = $Nota; probado = $Probado; busqueda = $Busqueda }
}

# Una salida con tres lanzadores: el de cargaJob (ficha y comparacion), el de informeJob (solo ficha, enlace unico) y uno suelto (sin ficha).
function Salida-Lanzadores([string]$Nombre, [bool]$Con = $true) {
  $s = Local-Salida $Nombre
  $d = Get-Ruta $s 'datos'
  if (-not $Con) { Guarda-Json (Join-Path $d 'lanzadores.json') ([ordered]@{ lanzadores = @() }); return $s }
  Guarda-Json (Join-Path $d 'lanzadores.json') ([ordered]@{ lanzadores = @(
        (Lanzador-Json 'sh-aaaaaaaa' 'bin/cargas.ksh' @('cargaJob') 'argumento'),
        (Lanzador-Json 'sh-bbbbbbbb' 'bin/informe.sh' @('informeJob') 'unico'),
        (Lanzador-Json 'sh-cccccccc' 'bin/raro.sh' @() 'sin-enlazar')) })
  [void](New-Item -ItemType Directory -Path (Join-Path $d 'fichas-sh') -Force)
  [void](New-Item -ItemType Directory -Path (Join-Path $d 'comparacion-sh') -Force)
  $a = @(
    (Item-Sh 'antes' 'mueve' 31 'ALTA ) for j in ls SALIDA_ALTA_*.TXT' ('Aparta a backup los ficheros de salida de alta. ' + $MalSh) 'Si el modo es ALTA.'),
    (Item-Sh 'despues' 'borra' 41 'find /opt/acme/cargas/logs -mtime +30' 'Borra los registros de mas de 30 dias.'),
    (Item-Sh 'despues' 'otro' 46 'esta cita no sale' 'Algo que no se pudo comprobar.' '' $false))
  Guarda-Json (Join-Path $d 'fichas-sh/sh-aaaaaaaa.json') ([ordered]@{ id = 'sh-aaaaaaaa'; script = 'bin/cargas.ksh'; paraQue = ('Lanza la carga de cuotas ' + $MalSh)
      parametros = @([ordered]@{ nombre = '--fecha'; obligatorio = $true; valores = 'una fecha'; formato = 'dd/MM/yyyy'; linea = 12; cita = '-f | --fecha )'; probado = $true },
        [ordered]@{ nombre = '--modo'; obligatorio = $false; valores = 'ALTA, BAJA o PAGOS'; formato = ''; linea = 14; cita = '-m | --modo )'; probado = $true })
      acciones = $a
      salidas = @([ordered]@{ codigo = 1; cuando = 'Si falta la fecha.'; linea = 20; cita = 'exit 1'; probado = $true }, [ordered]@{ codigo = 0; cuando = 'Cuando todo ha ido bien.'; linea = 47; cita = 'exit 0'; probado = $true })
      sinExplicar = @([ordered]@{ linea = 33; tipo = 'fichero'; detalle = 'cp'; texto = 'cp log/log-cargas.log logs/' }) })
  Guarda-Json (Join-Path $d 'comparacion-sh/sh-aaaaaaaa.json') ([ordered]@{ ficha = 'sh-aaaaaaaa'; script = 'bin/cargas.ksh'; migrado = @('src/main/java/com/acme/life/Archivador.java'); momento = 'antes-de-corregir'; commit = 'abc1234'
      acciones = @((Elem-Comp 0 'igual' 'src/main/java/com/acme/life/Archivador.java' 12 'static final String PATRON_ALTA' '' $true 'modelo'),
        (Elem-Comp 1 'falta' '' 0 '' '' $false 'sin-candidatos')) })
  Guarda-Json (Join-Path $d 'fichas-sh/sh-bbbbbbbb.json') ([ordered]@{ id = 'sh-bbbbbbbb'; script = 'bin/informe.sh'; paraQue = 'Lanza el informe de cobros.'; parametros = @()
      acciones = @((Item-Sh 'antes' 'elige-job' 3 'export spring_profiles_active=informe' 'Elige el perfil del informe.')); salidas = @(); sinExplicar = @() })
  return $s
}
function Pagina-Uno([string]$S) { return (Pagina $S '1-batch-original.html') }

$Pruebas['m17 lanzadores: pagina 1 - la tabla lanzador a job con unico y sin-enlazar marcados, y en cada job su Como se lanza con parametros, antes y despues y codigos de salida'] = {
  $s = Salida-Lanzadores 'm17-informe-uno'
  $x = Local-Con $s
  $p = Pagina-Uno $s
  $pan = Panel-De $p 'lanzadores'
  Comprueba 'hay un panel de lanzadores en la pagina 1' ($pan.Length -gt 0) ''
  $filas = @([regex]::Matches($pan, '(?s)<tr><td>.*?</tr>') | ForEach-Object { Texto-De $_.Value })
  Igual 'la tabla tiene una fila por lanzador' 3 $filas.Count
  Comprueba 'cargas.ksh -> cargaJob, enlazado por su propio argumento' ($filas.Count -ge 1 -and $filas[0] -match '^bin/cargas\.ksh cargaJob ' -and $filas[0] -match 'dice el propio script') ($filas -join ' | ')
  Comprueba 'informe.sh -> informeJob, marcado como unico job' ($filas.Count -ge 2 -and $filas[1] -match '^bin/informe\.sh informeJob .*.nico job') ($filas -join ' | ')
  Comprueba 'raro.sh sin job, marcado como sin enlazar' ($filas.Count -ge 3 -and $filas[2] -match '^bin/raro\.sh .*Sin enlazar') ($filas -join ' | ')
  $j = [regex]::Match($p, '(?s)<article class="job" id="job-cargaJob">.*?</article>').Value
  $l = [regex]::Match($j, '(?s)<div class="job-sec lanza">.*?</div>').Value
  Comprueba 'el job cargaJob lleva su bloque Como se lanza' ($l -match '<h4>C.mo se lanza</h4>' -and $l.Contains('bin/cargas.ksh')) $j
  $t = Texto-De $l
  Comprueba 'el para que, escapado' ($l.Contains((Html ('Lanza la carga de cuotas ' + $MalSh))) -and $l -notmatch '<b>alta') $t
  Comprueba 'los parametros: --fecha obligatorio con sus valores y su formato; --modo opcional' ($t -match '--fecha obligatorio . valores: una fecha . formato dd/MM/yyyy' -and $t -match '--modo opcional . valores: ALTA, BAJA o PAGOS') $t
  Comprueba 'lo de antes del java, con su condicion y escapado' ($t -match 'Antes de lanzar el job Si el modo es ALTA\. Aparta a backup los ficheros de salida de alta\.' -and $l.Contains((Html $MalSh))) $t
  Comprueba 'lo de despues: borra los de mas de 30 dias' ($t -match 'Despu.s de lanzar el job .*Borra los registros de mas de 30 dias\.') $t
  Comprueba 'lo que no se pudo comprobar sale marcado sin comprobar' ($l -match '(?s)Algo que no se pudo comprobar\..*?Sin comprobar') $l
  Comprueba 'los codigos de salida: 1 si falta la fecha y 0 si va bien' ($t -match 'C.mo acaba 1 Si falta la fecha\. .*0 Cuando todo ha ido bien\.') $t
  $ji = [regex]::Match($p, '(?s)<article class="job" id="job-informeJob">.*?</article>').Value
  Comprueba 'informeJob lleva el suyo (elige el perfil) y sin parametros' ((Texto-De $ji) -match 'bin/informe\.sh' -and (Texto-De $ji) -match 'No recibe par.metros' -and (Texto-De $ji) -match 'Elige el perfil del informe\.') (Texto-De $ji)
  Comprueba 'el unico job lo dice en su bloque' ((Texto-De $ji) -match '.nico job') ''
  Comprueba 'el lanzador sin enlazar no sale dentro de ningun job' ($j -notmatch 'raro\.sh' -and $ji -notmatch 'raro\.sh') ''
  Comprueba 'pero sale suelto en el panel, con su nombre escapado y su aviso de que no hay ficha' ((Texto-De $pan) -match 'Lanzadores sin job .*bin/raro\.sh' -and (Texto-De $pan) -match 'Todav.a no hay datos: la fase lanzadores no ha terminado') (Texto-De $pan)
  Comprueba 'ni un <script> ni una etiqueta sin escapar' ($p -notmatch '(?i)<script|<b>alta') ''
}

$Pruebas['m17 lanzadores: pagina 3 - la seccion Lanzadores con la linea fija, una fila por accion y su estado, el texto de falta, lo sin comparar y lo sin explicar'] = {
  $s = Salida-Lanzadores 'm17-informe-tres'
  $x = Local-Con $s
  $sec = Panel-De $x.P3 'lanzadores'
  Comprueba 'hay seccion Lanzadores' ($sec.Length -gt 0 -and $sec -match '<h2[^>]*>Lanzadores</h2>') ''
  Comprueba 'lleva la linea fija: la prueba en local no pasa por los .sh' ((Texto-De $sec).Contains('La prueba en local lanza los dos jar directamente: no pasa por los .sh')) (Texto-De $sec)
  Comprueba 'va despues de Leido por la IA' ($x.P3.IndexOf('id="lanzadores"') -gt $x.P3.IndexOf('id="leido-ia"')) ''
  $g = [regex]::Match($sec, '(?s)<article[^>]*id="lanz-sh-aaaaaaaa".*?</article>').Value
  Comprueba 'un grupo por lanzador con ficha: cargas.ksh con sus cuentas (1 igual, 1 falta, 1 sin comparar)' ($g -match '<h3[^>]*><code>bin/cargas\.ksh</code></h3>' -and (Texto-De $g) -match 'igual 1 . distinto 0 . falta 1 . no lo s. 0 . sin comparar 1') (Texto-De $g)
  Igual 'una fila por accion (3)' 3 ([regex]::Matches($g, '<li class="fila').Count)
  Comprueba 'la falta lleva el texto de la plataforma y va marcada como medida, sin llamada' ($g -match '(?s)Falta.*Borra los registros de mas de 30 dias\..*No est. en el c.digo del migrado\. Si lo hace la plataforma \(la planificaci.n o el configmap\), compru.balo all.' -and $g -match 'class="m m-medido"') (Texto-De $g)
  Comprueba 'la que no se comparo (cita inventada) sale Sin comparar' ((Texto-De $g) -match 'Sin comparar Algo que no se pudo comprobar\.') (Texto-De $g)
  Comprueba 'la igual, plegada, con la linea del script y la del migrado' ($g -match '(?s)<details>.*Archivador\.java:12.*PATRON_ALTA' -and $g.Contains('bin/cargas.ksh:31')) $g
  Comprueba 'lo sin explicar sale en el grupo' ((Texto-De $g) -match 'no explic. estas l.neas del script: 33') (Texto-De $g)
  Comprueba 'el texto escapado' ($g.Contains((Html $MalSh)) -and $g -notmatch '<b>alta') ''
  $h = [regex]::Match($sec, '(?s)<article[^>]*id="lanz-sh-bbbbbbbb".*?</article>').Value
  Comprueba 'informe.sh: ficha pero sin comparar: su unica accion, Sin comparar' ($h -match 'sin comparar 1' -and (Texto-De $h) -match 'Sin comparar Elige el perfil del informe\.') (Texto-De $h)
  Comprueba 'raro.sh, sin ficha, sale con su aviso' ($sec -match 'lanz-sh-cccccccc' -and (Texto-De ([regex]::Match($sec, '(?s)<article[^>]*id="lanz-sh-cccccccc".*?</article>').Value)) -match 'Todav.a no hay datos: la fase lanzadores no ha terminado') ''
  Comprueba 'la pagina sigue con su unico h1' ([regex]::Matches($x.P3, '<h1[ >]').Count -eq 1) ''
}

$Pruebas['m17 lanzadores: la portada - el grupo Cosas que hacian los .sh cuenta lo que falta o esta distinto mas lo sin explicar, y la fase y los ficheros de lanzadores salen'] = {
  $s = Salida-Lanzadores 'm17-informe-portada'
  $x = Local-Con $s
  $toca = Toca-De $x.I
  $titulos = @([regex]::Matches($toca, '<h3>(.*?)</h3>') | ForEach-Object { $_.Groups[1].Value })
  Comprueba 'el grupo sale: 2 cosas (1 falta y 1 sin explicar)' (@($titulos | Where-Object { $_ -ceq ('Cosas que hac' + [char]0xED + 'an los .sh y no est' + [char]0xE1 + 'n en el migrado (2)') }).Count -eq 1) ($titulos -join ' | ')
  $g = [regex]::Match($toca, '(?s)<h3>Cosas que hac.an los \.sh.*?</div>').Value
  Igual 'un elemento por cosa' 2 ([regex]::Matches($g, '<li>').Count)
  Comprueba 'la falta: el script, el estado y lo que hacia' ($g -match '(?s)<code>bin/cargas\.ksh</code>.*Falta.*Borra los registros de mas de 30 dias\.') (Texto-De $g)
  Comprueba 'lo sin explicar: script:linea, Sin explicar y la linea' ($g -match '(?s)<code>bin/cargas\.ksh:33</code>.*Sin explicar.*cp log/log-cargas\.log logs/') (Texto-De $g)
  Comprueba 'el texto del grupo manda a la plataforma' ((Texto-De $g) -match 'la planificaci.n o el configmap') ''
  $fases = [regex]::Match($x.I, '(?s)<ol class="fases".*?</ol>').Value
  Comprueba 'la lista de fases lleva la de lanzadores, despues del mapa y antes de las fichas de job' ($fases -match '(?s)Mapa de jobs.*C.mo se lanza cada job.*Redacci.n de cada job') (Texto-De $fases)
  Comprueba 'los ficheros: lanzadores.json, fichas-sh y comparacion-sh con su frase' ($x.I -match 'datos/lanzadores\.json' -and $x.I -match 'datos/fichas-sh' -and $x.I -match 'datos/comparacion-sh') ''
  $y = Local-Con (Salida-Lanzadores 'm17-informe-portada-sin' $false)
  Comprueba 'sin lanzadores no hay grupo ni cosas en la portada' ((Toca-De $y.I) -notmatch 'los \.sh') (Toca-De $y.I)
}

$Pruebas['m17 lanzadores: sin .sh la pagina 1 y la 3 dicen como pasar la carpeta; sin datos de la fase, el aviso de siempre'] = {
  $s = Salida-Lanzadores 'm17-informe-ninguno' $false
  $x = Local-Con $s
  $t1 = Texto-Plano (Panel-De (Pagina-Uno $s) 'lanzadores')
  $t3 = Texto-Plano (Panel-De $x.P3 'lanzadores')
  $frase = 'No hay lanzadores en el original. Si se lanzan con scripts que est'
  Comprueba 'pagina 1: No hay lanzadores en el original y relanza con -Lanzadores <carpeta>' ($t1.Contains($frase) -and $t1.Contains('relanza con -Lanzadores <carpeta>')) $t1
  Comprueba 'pagina 3: lo mismo, y la linea fija de la prueba en local' ($t3.Contains($frase) -and $t3.Contains('relanza con -Lanzadores <carpeta>') -and $t3.Contains('no pasa por los .sh')) $t3
  Remove-Item -LiteralPath (Get-Ruta $s 'datos/lanzadores.json') -Force
  $x = Local-Con $s
  $t1 = Texto-Plano (Panel-De (Pagina-Uno $s) 'lanzadores')
  $t3 = Texto-Plano (Panel-De $x.P3 'lanzadores')
  Comprueba 'sin lanzadores.json: Todavia no hay datos, la fase lanzadores no ha terminado, en las dos' ($t1 -match 'Todav.a no hay datos: la fase lanzadores no ha terminado' -and $t3 -match 'Todav.a no hay datos: la fase lanzadores no ha terminado') "$t1 | $t3"
  Comprueba 'y no dicen que no hay lanzadores' ($t1 -notmatch 'No hay lanzadores' -and $t3 -notmatch 'No hay lanzadores') ''
}

$Pruebas['m24 config.json del repo: las claves de rescate.ps1 (PalabrasConfigAntigua, PasosSoloCompila) no avisan de desconocidas en la consola de migracion.ps1'] = {
  $e = Nuevo-Escenario 'm24-claves-de-rescate' @('Clase1')
  # el config.json del migrado es de rescate.ps1: lleva sus claves y la compartida CopilotExe/MvnExe que migracion.ps1 si conoce
  $cfg = Lee-Json (Get-Ruta $e.Migrado '.rescate/config.json')
  Escribe $e.Migrado '.rescate/config.json' (ConvertTo-Json -InputObject ([ordered]@{
    CopilotExe = $cfg.CopilotExe; MvnExe = $cfg.MvnExe; PalabrasConfigAntigua = @('inventory'); PasosSoloCompila = @('sonar'); PasosTestsElegidos = @('sonar') }))
  $r = Migra $e (Basicos $e)
  Igual 'sale con 0' 0 $r.Codigo
  Comprueba 'la consola no dice clave desconocida' ($r.Salida -notmatch 'clave desconocida') (Cola $r.Salida)
  Comprueba 'y lo que si comparte (el Maven falso del config.json) se sigue leyendo: el diagnostico llega a la pagina 2' (Test-Path -LiteralPath (Get-Ruta $e.Out '2-problemas.html')) (Cola $r.Salida)
}

# ===================== LOS COMANDOS DEL FINAL SE PEGAN ENTEROS (m27) =====================
$Pruebas['m27 pagina 4: las tres ordenes de git, cada una en su linea con git -C "<carpeta del migrado>" delante y la explicacion detras de #'] = {
  $c = Corrida-Dos $GuionBase
  $d = Datos-Pagina4
  $x = Correccion-Con $c.E 'm27-p4' $d.Antes $d.Despues $d.Corr
  $st = Lee-Json (Get-Ruta $x.Dir 'datos/estado.json')
  $co = Panel-De $x.P4 'codigo'
  $lineas = @([regex]::Match($co, '(?s)<pre class="cmd">(.*?)</pre>').Groups[1].Value -split "`r?`n" | Where-Object { $_ })
  Igual 'tres lineas' 3 $lineas.Count
  Comprueba 'cada una empieza por git -C " (nada delante)' (@($lineas | Where-Object { $_.StartsWith('git -C "') }).Count -eq 3) ($lineas -join ' / ')
  Comprueba 'con la carpeta del migrado entre comillas' (@($lineas | Where-Object { $_.StartsWith('git -C "' + (Html $st.migrado) + '" ') }).Count -eq 3) ($lineas -join ' / ')
  Comprueba 'y la explicacion detras de #, tras una orden que acaba antes' (@($lineas | Where-Object { $_ -match '^git -C "[^"]+" \S.*\S\s+# \S' }).Count -eq 3) ($lineas -join ' / ')
  Comprueba 'ver: diff --stat con la base y la rama' ($lineas[0] -match '^git -C "[^"]+" diff --stat main\.\.\.rescate/main-20260101-0000\s+# ver qu. ha cambiado$') $lineas[0]
  Comprueba 'traer: merge, con la alternativa del PR en el comentario' ($lineas[1] -match '^git -C "[^"]+" merge rescate/main-20260101-0000\s+# traerlo a tu rama \(o sube la rama y abre un PR\)$') $lineas[1]
  Comprueba 'borrar: worktree remove del worktree, al acabar con prueba-local.ps1, y la rama se conserva' ($lineas[2] -match ('^git -C "[^"]+" worktree remove "' + [regex]::Escape((Html $st.worktree)) + '"\s+# borrar el worktree cuando acabes con prueba-local\.ps1 \(la rama se conserva\)$')) $lineas[2]
  Comprueba 'antes de ellas, la frase que dice que se copia cada linea entera' ($co -match 'Copia cada l.nea entera; lo que va detr.s de <code>#</code> es solo la explicaci.n') $co
  Comprueba 'sigue sin JavaScript ni nada externo' ($x.P4 -notmatch '(?i)<script' -and $x.P4 -notmatch 'https?://')
}

$Pruebas['bp0 practicas: migracion.ps1 deja datos/practicas-antes.json con sus cinco detectores; relanzar no lo repite y una medida que falla no para la migracion'] = {
  $e = Nuevo-Escenario 'bp0-prac' @('Clase1') @{ MvnExe = (Join-Path $falsos 'analisis-mvn.ps1') }
  $r = Migra $e (Basicos $e)
  Igual 'sale con 0' 0 $r.Codigo
  $ruta = Get-Ruta $e.Out 'datos/practicas-antes.json'
  $p = Lee-Json $ruta
  Comprueba 'existe datos/practicas-antes.json' ($null -ne $p) (Cola $r.Salida)
  if ($null -eq $p) { return }
  Igual 'version y cuando' '1 antes' "$($p.version) $($p.cuando)"
  Igual 'los seis detectores, en el orden del formato' 'javac pmd spotbugs lombok-a-mano lombok-qualifier java21-texto' (@($p.detectores | ForEach-Object { $_.id }) -join ' ')
  Igual 'sus estados: la referencia no usa Lombok, lo demas se mide' 'ok ok ok no aplica ok ok' (@($p.detectores | ForEach-Object { $_.estado }) -join ' ')
  Igual 'las 9 incidencias de PMD y SpotBugs (los XML de mentira), todas java21' 9 @($p.incidencias | Where-Object { $_.area -ceq 'java21' }).Count
  Comprueba 'su registro esta en registros/practicas-antes.log' (Test-Path -LiteralPath (Get-Ruta $e.Out 'registros/practicas-antes.log'))
  Comprueba 'la consola dice las buenas practicas' ($r.Salida -match 'Buenas practicas \(antes\): 9 incidencias \(java21: 9\)') (Cola $r.Salida)
  Comprueba 'hallazgos-antes.json sigue siendo lo ultimo del diagnostico: esta' (Test-Path -LiteralPath (Get-Ruta $e.Out 'datos/hallazgos-antes.json'))
  Comprueba 'no hay practicas de despues (no se corrigio)' (-not (Test-Path -LiteralPath (Get-Ruta $e.Out 'datos/practicas-despues.json')))
  # relanzar no repite el diagnostico y, con el, tampoco la medida
  $h = Hash-De $ruta
  $r2 = Migra $e (Basicos $e)
  Igual 'el segundo lanzamiento sale con 0' 0 $r2.Codigo
  Igual 'practicas-antes.json no cambia' $h (Hash-De $ruta)
  # una medida que falla (no se puede escribir el JSON) no para la migracion
  $f = Nuevo-Escenario 'bp0-falla' @('Clase1') @{ MvnExe = (Join-Path $falsos 'analisis-mvn.ps1') }
  [void](New-Item -ItemType Directory -Path (Get-Ruta $f.Out 'datos/practicas-antes.json.tmp') -Force)
  $rf = Migra $f (Basicos $f)
  Igual 'con la medida rota, la migracion sale con 0' 0 $rf.Codigo
  Comprueba 'dice que no ha podido escribir practicas-antes.json' ($rf.Salida -match 'no he podido escribir .*practicas-antes\.json') (Cola $rf.Salida)
  Comprueba 'no hay practicas-antes.json' (-not (Test-Path -LiteralPath (Get-Ruta $f.Out 'datos/practicas-antes.json') -PathType Leaf))
  Comprueba 'el diagnostico sigue: hay hallazgos-antes.json y cobertura-antes.json' ((Test-Path -LiteralPath (Get-Ruta $f.Out 'datos/hallazgos-antes.json')) -and (Test-Path -LiteralPath (Get-Ruta $f.Out 'datos/cobertura-antes.json')))
  Comprueba 'y la portada se hizo' (Test-Path -LiteralPath (Get-Ruta $f.Out 'index.html'))
}

# ================== BP-2: LA PAGINA 5, BUENAS PRACTICAS ==================
# Un practicas-<Cuando>.json inventado, con el formato de BP-datos.md: 10 incidencias de las 4 areas, con los 4 queHago y los 3 origenes (4 con regla de
# Sonar o SpotBugs y 6 de la referencia). javac tiene corte, spotbugs no se midio (tope) y un texto, un motivo y una regla llevan markup. Sin sonar.xlsx.
function Bp2-Incidencia([string]$Area, [string]$Fichero, [int]$Linea, [string]$Herramienta, [string]$Regla, [string]$Origen, [string]$Sonar, [string]$Texto, [string]$QueHago) {
  return [ordered]@{ area = $Area; fichero = $Fichero; linea = $Linea; herramienta = $Herramienta; regla = $Regla; origen = $Origen; sonar = $Sonar; texto = $Texto; queHago = $QueHago }
}

function Bp2-Practicas([string]$Cuando = 'antes', [string]$Paquete = 'com.acme.recibos') {
  $p = 'src/main/java/com/acme/recibos/'
  return [ordered]@{
    version = 1; cuando = $Cuando; clave = 'a1b2c3d4'; medido = '2026-11-19T11:42:05'; segundos = 14.2; paquete = $Paquete; referencia = 'batch-referencia'
    detectores = @(
      [ordered]@{ id = 'javac'; estado = 'ok'; motivo = ''; segundos = 2.7; corte = $true },
      [ordered]@{ id = 'pmd'; estado = 'ok'; motivo = ''; segundos = 3.3; corte = $false },
      [ordered]@{ id = 'spotbugs'; estado = 'no medido (tope)'; motivo = ''; segundos = 0; corte = $false },
      [ordered]@{ id = 'lombok-a-mano'; estado = 'no aplica'; motivo = 'la referencia no usa <i>Lombok</i> & su config'; segundos = 0.6; corte = $false },
      [ordered]@{ id = 'lombok-qualifier'; estado = 'ok'; motivo = ''; segundos = 0.1; corte = $false }
    )
    sonar = [ordered]@{ reglasWay = 608; reglasAqui = 15 }
    incidencias = @(
      (Bp2-Incidencia 'java21' ($p + 'infrastructure/sftp/SubidaTasklet.java') 63 'pmd' 'CloseResource' 'sonar' 'S2095' 'El InputStream de la remesa no se cierra si falla la subida.' 'mano'),
      (Bp2-Incidencia 'java21' ($p + 'infrastructure/persistence/ReciboDao.java') 58 'pmd' 'EmptyCatchBlock' 'sonar' 'S108' 'Un catch vacio se traga el error.' 'paso2'),
      (Bp2-Incidencia 'java21' ($p + 'application/usecase/ConciliacionService.java') 77 'spotbugs' 'NP_NULL_ON_SOME_PATH' 'spotbugs' '' 'Cierra <u>antes</u> & <b>despues</b>: puede ser null.' 'sonar'),
      (Bp2-Incidencia 'java21' ($p + 'domain/service/ReciboValidator.java') 88 'pmd' 'Unused<i>Local</i>Variable' 'referencia' '' 'La variable local pendientes no se usa.' 'mano'),
      (Bp2-Incidencia 'boot3-batch5' ($p + 'infrastructure/config/CargaJobConfig.java') 31 'javac' 'removal' 'sonar' 'S5738' 'JobBuilderFactory se borrara en Batch 5.' 'paso2'),
      (Bp2-Incidencia 'boot3-batch5' ($p + 'infrastructure/config/BatchConfig.java') 14 'arquitectura' 'EnableBatchProcessing' 'referencia' '' 'EnableBatchProcessing apaga la configuracion automatica de Boot 3.' 'mano'),
      (Bp2-Incidencia 'lombok' ($p + 'domain/model/Recibo.java') 18 'lombok' 'getter-a-mano' 'referencia' '' '14 metodos get y set escritos a mano.' 'paso2'),
      (Bp2-Incidencia 'lombok' ($p + 'application/usecase/EnviarRemesaUseCase.java') 24 'lombok' 'qualifier-sin-copiar' 'referencia' '' 'RequiredArgsConstructor no copia el Qualifier al constructor.' 'mano'),
      (Bp2-Incidencia 'arquitectura' ($p + 'application/usecase/ReciboService.java') 0 'arquitectura' 'ciclo-entre-paquetes' 'referencia' '' 'Ciclo entre application.usecase e infrastructure.persistence.' 'notoca'),
      (Bp2-Incidencia 'arquitectura' ($p + 'application/usecase/ReciboService.java') 14 'arquitectura' 'nombre-usecase' 'referencia' '' 'Se llama ReciboService: en la referencia seria ReciboUseCase.' 'paso2')
    )
    arquitectura = $null
  }
}

# Una carpeta de salida sin correr migracion.ps1 (solo el estado, el diagnostico y los practicas-*.json que se le den, o ninguno) con las seis paginas
# montadas. Sin rutas con \ en el estado: asi las paginas son las mismas en Windows y en Linux.
function Bp2-Salida([string]$Nombre, $Antes = $null, $Despues = $null) {
  $raiz = Join-Path $Dir $Nombre
  if (Test-Path -LiteralPath $raiz) { Remove-Item -LiteralPath $raiz -Recurse -Force }
  $s = Join-Path $raiz 'migracion-batch-recibos'
  [void](New-Item -ItemType Directory -Path (Join-Path $s 'datos') -Force)
  Guarda-Json (Join-Path $s 'datos/estado.json') ([ordered]@{ batch = 'batch-recibos'; legacy = 'acme/recibos-java8'; migrado = 'acme/batch-recibos'; plantilla = 'acme/batch-referencia'; modelo = 'modelo-x'; creado = '2026-11-19T10:00:00'; actualizado = '2026-11-19T11:00:00'; fin = '2026-11-19T11:00:00'; fase = 'hecha'; respuesta = 'parar' })
  Guarda-Json (Join-Path $s 'datos/hallazgos-antes.json') @((Hallazgo 'build' 'error' 'pom.xml' 0 'pom uno'), (Hallazgo 'estructura' 'error' 'src/main/java/A.java' 3 'A suelta'), (Hallazgo 'tests' 'aviso' 'src/test/java' 0 'no hay tests'))
  Escribe $s 'datos/diagnostico-antes.md' (Md-Diagnostico 'compila: SI | tests: OK')
  if ($null -ne $Antes) { Guarda-Json (Join-Path $s 'datos/practicas-antes.json') $Antes }
  if ($null -ne $Despues) { Guarda-Json (Join-Path $s 'datos/practicas-despues.json') $Despues }
  $g = Genera-Informes $s
  Comprueba "$Nombre : Write-Informes sale bien" ($g.Codigo -eq 0 -and $g.Salida -match 'INFORMES-OK') (Cola $g.Salida)
  $p5 = Pagina $s '5-buenas-practicas.html'
  Comprueba "$Nombre : monta 5-buenas-practicas.html" ($p5.Length -gt 0) (Cola $g.Salida)
  return [pscustomobject]@{ Dir = $s; P5 = $p5 }
}

# Una vista de la lista de incidencias de la pagina 5 ('que' o 'area'): del id de su <div> hasta el de la otra vista o el final.
function Bp2-Vista([string]$Html, [string]$Cual) {
  $q = $Html.IndexOf('id="vista-que"')
  $a = $Html.IndexOf('id="vista-area"')
  if ($q -lt 0 -or $a -lt 0) { return '' }
  if ($Cual -eq 'que') { return $Html.Substring($q, $a - $q) }
  return $Html.Substring($a)
}

$Pruebas['bp2 (a) la pagina 5 existe, su enlace esta en la navegacion de las seis paginas con aria-current solo en la suya y la portada la explica'] = {
  $x = Bp2-Salida 'bp2-nav' (Bp2-Practicas)
  foreach ($n in @('index.html', '1-batch-original.html', '2-problemas.html', '3-original-vs-migrado.html', '4-correcciones.html', '5-buenas-practicas.html')) {
    $h = Pagina $x.Dir $n
    Comprueba "$n : existe" ($h.Length -gt 0)
    Comprueba "$n : la navegacion lleva a Buenas practicas" ($h -match 'href="5-buenas-practicas\.html"[^>]*>Buenas pr.cticas<')
    Igual "$n : aria-current solo en su pagina" 1 ([regex]::Matches($h, 'aria-current="page"').Count)
    Comprueba "$n : y es el de su enlace" ($h -match ('href="' + [regex]::Escape($n) + '" aria-current="page"'))
  }
  Comprueba 'el titulo de la pagina 5 lleva el batch' ($x.P5 -match '<title>Buenas pr.cticas del batch migrado batch-recibos</title>')
  $f = [regex]::Match((Pagina $x.Dir 'index.html'), '(?s)<ul class="ficheros">.*?</ul>').Value
  Comprueba 'la portada: Que es cada fichero lleva 5-buenas-practicas.html, con enlace, y datos/practicas-antes.json' ($f.Contains('href="5-buenas-practicas.html"') -and $f.Contains('datos/practicas-antes.json')) $f
}

$Pruebas['bp2 (b) los indicadores traen las cifras del JSON: por area, con Sonar, reglasAqui y reglasWay; el del .xlsx solo si el JSON lo trae'] = {
  $p = Bp2-Practicas
  $x = Bp2-Salida 'bp2-cifras' $p
  $areas = Panel-De $x.P5 'ind-areas'
  Comprueba 'incidencias por area: el total (10)' ($areas.Contains('<p class="bp-ind-n">10</p>')) $areas
  foreach ($a in @('java21', 'boot3-batch5', 'lombok', 'arquitectura')) {
    $n = @($p.incidencias | Where-Object { $_.area -ceq $a }).Count
    Comprueba "incidencias por area: $a lleva $n en la leyenda" ($areas -match ('(?s)<li class="bp-ley-' + $a + '">(?:(?!</li>).)*<b class="bp-ley-n">' + $n + '</b>')) $areas
    Comprueba "incidencias por area: $a lleva su tramo en la barra" ($areas.Contains('<span class="bp-ar-' + $a + '" style="flex:' + $n + ' 1 0"></span>'))
  }
  $son = @($p.incidencias | Where-Object { $_.origen -cne 'referencia' }).Count
  $ref = @($p.incidencias).Count - $son
  $s = Panel-De $x.P5 'ind-sonar'
  Comprueba "con regla de Sonar: $son de 10 (Sonar y SpotBugs, que el Sonar del equipo lanza)" ($s.Contains("<p class=`"bp-ind-sub`"><b>$son</b> de 10</p>") -and $s.Contains("<b>$son</b></div>")) $s
  Comprueba "con regla de Sonar: la leyenda dice $son y $ref de la referencia" ($s -match ('(?s)Con regla de Sonar<b class="bp-ley-n">' + $son + '</b>.*De la referencia<b class="bp-ley-n">' + $ref + '</b>')) $s
  $r = Panel-De $x.P5 'ind-reglas'
  Comprueba 'reglas de Sonar way: reglasAqui de reglasWay (15 de 608)' ($r.Contains('15 <small>de 608</small>')) $r
  Comprueba 'y la frase: cero incidencias aqui no es un Sonar limpio' ($r -match 'Cero incidencias aqu. no es un Sonar limpio') $r
  Comprueba 'sin sonar.xlsx en el JSON: el indicador del .xlsx no sale, y la fila de indicadores es de tres' ($x.P5 -notmatch 'id="ind-xlsx"' -and $x.P5.Contains('class="bp-ind-fila bp-ind-n3"'))
  $p['sonar']['xlsx'] = [ordered]@{ fichero = 'sonar-2026-11-12.xlsx'; total = 41; resueltas = 30; siguen = 11 }
  $y = Bp2-Salida 'bp2-cifras-xlsx' $p
  $xl = Panel-De $y.P5 'ind-xlsx'
  Comprueba 'con sonar.xlsx en el JSON: sale el indicador, con 30 de 41 resueltas y 11 abiertas, y la fila es de cuatro' ($xl.Contains('<span class="bp-ok">30</span>') -and $xl.Contains('de 41 resueltas') -and $xl.Contains('<b class="bp-mal">11</b>') -and $y.P5.Contains('class="bp-ind-fila bp-ind-n4"')) $xl
  Comprueba 'y el panel de como leer lo de Sonar dice las cifras del .xlsx' ((Panel-De $y.P5 'sonar') -match '41 incidencias, 30 resueltas, 11 siguen') (Panel-De $y.P5 'sonar')
}

$Pruebas['bp2 (c) cada incidencia sale una vez en cada vista, con su fichero y su linea, su origen, su texto y su regla; las rutas llevan <wbr> detras de cada /'] = {
  $p = Bp2-Practicas
  $x = Bp2-Salida 'bp2-lista' $p
  $q = Bp2-Vista $x.P5 'que'
  $a = Bp2-Vista $x.P5 'area'
  Comprueba 'las dos vistas existen' ($q.Length -gt 0 -and $a.Length -gt 0)
  Igual 'por que hago: 10 filas' 10 ([regex]::Matches($q, '<li class="bp-fila ').Count)
  Igual 'por area: 10 filas' 10 ([regex]::Matches($a, '<li class="bp-fila ').Count)
  foreach ($i in @($p.incidencias)) {
    $donde = (($i.fichero -split '/' | ForEach-Object { Html $_ }) -join '/<wbr>')
    if ($i.linea -gt 0) { $donde += ':' + $i.linea }
    $cita = $i.fichero.Split('/')[-1] + ':' + $i.linea
    foreach ($v in @(@('por que hago', $q), @('por area', $a))) {
      Igual "$($v[0]): $cita sale una vez" 1 ([regex]::Matches($v[1], [regex]::Escape('<code class="bp-donde">' + $donde + '</code>')).Count)
      Igual "$($v[0]): $cita lleva su texto una vez" 1 ([regex]::Matches($v[1], [regex]::Escape('<p class="bp-fb-p">' + (Html $i.texto) + '</p>')).Count)
      Igual "$($v[0]): $cita lleva su regla una vez" 1 ([regex]::Matches($v[1], [regex]::Escape('<span class="bp-regla">' + (Html ($i.herramienta + ' ' + $i.regla)) + '</span>')).Count)
    }
  }
  Comprueba 'una linea 0 no sale como :0' (-not $q.Contains('ReciboService.java:0<') -and $q.Contains('ReciboService.java</code>'))
  $rutas = @([regex]::Matches($x.P5, '<code class="bp-donde">(.*?)</code>') | ForEach-Object { $_.Groups[1].Value })
  Igual 'hay 20 rutas (10 por vista)' 20 $rutas.Count
  Igual 'ninguna / sin su <wbr> detras' 0 @($rutas | Where-Object { $_ -match '/(?!<wbr>)' }).Count
  Comprueba 'el origen: Sonar con su clave, Sonar (SpotBugs) y de la referencia' ($q.Contains('Sonar S2095') -and $q.Contains('Sonar S5738') -and $q.Contains('Sonar (SpotBugs)') -and $q.Contains('de la referencia'))
  # los grupos: por que hago en su orden (4, 4, 1 y 1) y por area en el suyo (4, 2, 2 y 2)
  Igual 'grupos por que hago, en orden' 'gq-mano=4 gq-paso2=4 gq-sonar=1 gq-notoca=1' ((@([regex]::Matches($q, '(?s)<section class="bp-grupo" aria-labelledby="(gq-\w+)">.*?<span class="bp-num">(\d+)</span>') | ForEach-Object { $_.Groups[1].Value + '=' + $_.Groups[2].Value })) -join ' ')
  Igual 'grupos por area, en orden' 'ga-java21=4 ga-boot3-batch5=2 ga-lombok=2 ga-arquitectura=2' ((@([regex]::Matches($a, '(?s)<section class="bp-grupo" aria-labelledby="(ga-[\w-]+)">.*?<span class="bp-num">(\d+)</span>') | ForEach-Object { $_.Groups[1].Value + '=' + $_.Groups[2].Value })) -join ' ')
  Comprueba 'las explicaciones de la maqueta: A mano, paso 2, -Sonar y la referencia tampoco' ($q.Contains('Esto lo haces t') -and $q.Contains('Se arregla solo al lanzar el paso 2.') -and $q.Contains('Se arregla con -Sonar, si la regla sale en tu informe de Sonar.') -and $q.Contains('No se toca: la referencia tampoco lo cumple.'))
  Comprueba 'y las de cada area' ($a.Contains('PMD y SpotBugs sobre el c') -and $a.Contains('Sonar no tiene reglas de Lombok'))
  Comprueba 'el selector de vista es de radios, sin JavaScript' ($x.P5.Contains('id="bp-m-que"') -and $x.P5.Contains('id="bp-m-area"') -and $x.P5 -notmatch '(?i)<script')
}

$Pruebas['bp2 (d) un detector no medido sale con su estado y su motivo y javac con corte dice 100 o mas; si todos midieron, la seccion no sale'] = {
  $p = Bp2-Practicas
  $x = Bp2-Salida 'bp2-detectores' $p
  $d = Panel-De $x.P5 'detectores'
  Comprueba 'hay seccion de detectores' ($d.Length -gt 0)
  Comprueba 'spotbugs sale con su estado: no medido (tope)' ($d -match '<code>spotbugs</code> <b>no medido \(tope\)</b>') $d
  Comprueba 'javac sale con corte: 100 o mas' ($d -match '<code>javac</code> <b>100 o m.s</b>') $d
  Comprueba 'lombok-a-mano sale con su estado y su motivo, escapado' ($d.Contains('<code>lombok-a-mano</code> <b>no aplica</b>: la referencia no usa &lt;i&gt;Lombok&lt;/i&gt; &amp; su config')) $d
  Comprueba 'los que midieron (pmd y lombok-qualifier) no salen' ($d -notmatch '<code>pmd</code>' -and $d -notmatch '<code>lombok-qualifier</code>')
  Igual 'son tres lineas' 3 ([regex]::Matches($d, '<p class="bp-nota">').Count)
  Comprueba 'la ficha dice los que midieron: javac, pmd y lombok-qualifier' ($x.P5 -match '(?s)<dt>Midieron</dt>.*?javac.*?pmd.*?lombok-qualifier.*?</dl>')
  # todos midieron y javac no corta: la seccion no sale
  $p['detectores'] = @(@($p.detectores) | ForEach-Object { [ordered]@{ id = $_.id; estado = 'ok'; motivo = ''; segundos = 1; corte = $false } })
  $y = Bp2-Salida 'bp2-detectores-ok' $p
  Comprueba 'con todos los detectores en ok y sin corte, no hay seccion de detectores' ($y.P5.Length -gt 0 -and $y.P5 -notmatch 'id="detectores"')
}

$Pruebas['bp2 (e) con practicas-despues.json se pinta ese y no el de antes; sin ninguno la pagina existe y dice que no se ha medido'] = {
  $antes = Bp2-Practicas 'antes'
  $despues = Bp2-Practicas 'despues' 'com.acme.otro'
  $despues['incidencias'] = @($despues.incidencias | Select-Object -First 3)
  $a = Bp2-Salida 'bp2-solo-antes' $antes
  Comprueba 'solo el de antes: 10 incidencias, su paquete y "antes de corregir"' ((Panel-De $a.P5 'ind-areas').Contains('<p class="bp-ind-n">10</p>') -and $a.P5.Contains('com.acme.recibos') -and $a.P5 -match 'antes de corregir')
  $b = Bp2-Salida 'bp2-los-dos' $antes $despues
  Comprueba 'con los dos: se pinta el de despues (3 incidencias, su paquete y "despues de corregir")' ((Panel-De $b.P5 'ind-areas').Contains('<p class="bp-ind-n">3</p>') -and $b.P5.Contains('com.acme.otro') -and $b.P5 -match 'despu.s de corregir')
  Comprueba 'y nada del de antes' ($b.P5 -notmatch 'com\.acme\.recibos' -and $b.P5 -notmatch 'antes de corregir' -and $b.P5 -notmatch 'ReciboValidator')
  Igual 'con los dos: 3 filas por vista' 3 ([regex]::Matches((Bp2-Vista $b.P5 'que'), '<li class="bp-fila ').Count)
  $c = Bp2-Salida 'bp2-solo-despues' $null $despues
  Comprueba 'solo el de despues: tambien se pinta' ((Panel-De $c.P5 'ind-areas').Contains('<p class="bp-ind-n">3</p>'))
  $n = Bp2-Salida 'bp2-ninguno'
  Comprueba 'sin ninguno: la pagina existe' ($n.P5.Length -gt 0)
  Comprueba 'dice que no se ha medido y por que: el diagnostico no ha llegado ahi' ($n.P5 -match 'no se han medido las buenas pr.cticas' -and $n.P5 -match 'el diagn.stico no ha llegado')
  Comprueba 'y no pinta indicadores, ni lista, ni detectores' ($n.P5 -notmatch 'class="bp-ind-fila' -and $n.P5 -notmatch 'id="lista"' -and $n.P5 -notmatch 'id="detectores"')
  Igual 'con su navegacion y un solo h1' 1 ([regex]::Matches($n.P5, '<h1').Count)
  Comprueba 'con su navegacion: el enlace actual es el suyo' ($n.P5 -match 'href="5-buenas-practicas\.html" aria-current="page"')
  # un JSON que no se lee equivale a no tenerlo
  $m = Bp2-Salida 'bp2-roto' $antes
  Escribe $m.Dir 'datos/practicas-despues.json' '{ esto no es json'
  $g = Genera-Informes $m.Dir
  Comprueba 'con un practicas-despues.json roto se sigue con el de antes' ($g.Codigo -eq 0 -and (Panel-De (Pagina $m.Dir '5-buenas-practicas.html') 'ind-areas').Contains('<p class="bp-ind-n">10</p>')) (Cola $g.Salida)
}

$Pruebas['bp2 (f) el texto de las herramientas sale escapado: un <b>, un <u> y un & no se pintan como HTML'] = {
  $x = Bp2-Salida 'bp2-escapa' (Bp2-Practicas)
  Comprueba 'el texto de una incidencia, escapado' ($x.P5.Contains('Cierra &lt;u&gt;antes&lt;/u&gt; &amp; &lt;b&gt;despues&lt;/b&gt;: puede ser null.'))
  Comprueba 'la regla de una incidencia, escapada' ($x.P5.Contains('pmd Unused&lt;i&gt;Local&lt;/i&gt;Variable'))
  Comprueba 'el motivo de un detector, escapado' ($x.P5.Contains('no usa &lt;i&gt;Lombok&lt;/i&gt; &amp; su config'))
  Comprueba 'ninguna etiqueta <u> ni <i> que no sea de la pagina' ($x.P5 -notmatch '<u>' -and $x.P5 -notmatch '<i>')
  Comprueba 'ni un & suelto' ($x.P5 -notmatch '&(?!amp;|lt;|gt;|quot;|#39;)')
}

$Pruebas['bp2 (g) la pagina 5 no lleva nada externo: ni http, ni script, ni import, ni emojis, y un solo h1 y lang es'] = {
  $x = Bp2-Salida 'bp2-limpia' (Bp2-Practicas)
  $h = $x.P5
  Comprueba 'ni http:// ni https://' ($h -notmatch 'https?://')
  Comprueba 'ni <script ni @import ni <link ni <img ni <iframe' ($h -notmatch '(?i)<script|@import|<link|<img|<iframe')
  Comprueba 'ninguna url() externa' ($h -notmatch '(?i)url\(\s*[''"]?(https?:|//)')
  Comprueba 'ningun src ni href que no sea del propio informe' (@([regex]::Matches($h, '(?i)\b(?:src|href)\s*=\s*"(?!#)([^"]*)"') | Where-Object { -not (Test-Path -LiteralPath (Get-Ruta $x.Dir $_.Groups[1].Value)) }).Count -eq 0)
  $dentro = @([regex]::Matches($h, '(?i)href="#([^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Where-Object { $h -notmatch ('id="' + [regex]::Escape($_) + '"') })
  Comprueba 'los iconos y enlaces #ancla llevan a un id que existe' ($dentro.Count -eq 0) ($dentro -join ' ')
  Igual 'un solo h1' 1 ([regex]::Matches($h, '<h1[ >]').Count)
  Comprueba 'lang="es"' ($h -match '<html lang="es">')
  $emoji = '[' + [char]0x2600 + '-' + [char]0x27BF + ']|[' + [char]0xD83C + '-' + [char]0xD83E + '][' + [char]0xDC00 + '-' + [char]0xDFFF + ']'
  Comprueba 'sin emojis' ($h -notmatch $emoji)
  Comprueba 'sin saltos de nivel: tras el h1 vienen h2 y despues h3' ($h -notmatch '<h4' -and $h.IndexOf('<h1') -lt $h.IndexOf('<h2') -and $h.IndexOf('<h2') -lt $h.IndexOf('<h3'))
}

$Pruebas['bp2 (h) la pagina 2 sigue igual: los mismos bytes que antes de la pagina 5, salvo el enlace nuevo de la navegacion y el CSS de la pagina 5'] = {
  $x = Bp2-Salida 'bp2-pagina2' (Bp2-Practicas)
  $h = Pagina $x.Dir '2-problemas.html'
  $h = [regex]::Replace($h, '(?m)^ *<li><a href="5-buenas-practicas\.html"[^>]*>[^<]*</a></li>\r?\n', '')
  $h = [regex]::Replace($h, '(?s)/\* pagina 5: [^\n]*\n.*(?=\n</style>)', '')
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { $hash = (($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($h)) | ForEach-Object { $_.ToString('X2') }) -join '') } finally { $sha.Dispose() }
  # el SHA-256 de la pagina 2 de estos datos montada con 2a5e279 (antes de la pagina 5). Si cambia a proposito la pagina 2 o su CSS, hay que recalcularlo.
  Igual 'SHA-256 de la pagina 2' '300C5530C4ACB6AB733AB9CBB471B6E922E289440F58B7EAF0631C8DBE74D677' $hash
  Comprueba 'la pagina 2 sigue con sus cinco enlaces de siempre' ((@([regex]::Matches($h, '<li><a href="[^"]+\.html"') | ForEach-Object { $_.Value }).Count) -eq 5)
}

$Pruebas['bp2 integracion: una corrida real deja la pagina 5 con las incidencias del practicas-antes.json que escribe el diagnostico'] = {
  $e = Nuevo-Escenario 'bp2-integra' @('Clase1') @{ MvnExe = (Join-Path $falsos 'analisis-mvn.ps1') }
  $r = Migra $e (Basicos $e)
  Igual 'sale con 0' 0 $r.Codigo
  $p = Lee-Json (Get-Ruta $e.Out 'datos/practicas-antes.json')
  Comprueba 'hay practicas-antes.json con incidencias' ($null -ne $p -and @($p.incidencias).Count -gt 0) (Cola $r.Salida)
  if ($null -eq $p) { return }
  $h = Pagina $e.Out '5-buenas-practicas.html'
  Comprueba 'la pagina 5 existe' ($h.Length -gt 0) (Cola $r.Salida)
  $n = @($p.incidencias).Count
  Comprueba "y dice $n incidencias, las del JSON" ((Panel-De $h 'ind-areas').Contains("<p class=`"bp-ind-n`">$n</p>")) (Panel-De $h 'ind-areas')
  Igual 'cada incidencia sale una vez en la vista por area' $n ([regex]::Matches((Bp2-Vista $h 'area'), '<li class="bp-fila ').Count)
  Comprueba 'y la consola no dice que no pudo escribir las paginas' ($r.Salida -notmatch 'No he podido escribir las paginas')
}

# ============ BP-5: EL INFORME CONOCE LA FASE practicas Y LA PAGINA 5 MARCA LO ARREGLADO ============
# Los nombres de las fases de la portada, en su orden, con corregir y sin la fase practicas (como hasta BP-4). '.' donde hay una letra con acento.
$Bp5Fases = @('Diagn.stico del migrado', 'Lectura de las clases', 'Mapa de jobs, pasos y variables', 'C.mo se lanza cada job', 'Redacci.n de cada job', 'Resumen y glosario',
  'Guion de prueba en pre', 'Casos de las reglas sin caso', 'Correcci.n del migrado', 'Comparaci.n con el original', 'Prueba en local')
$Bp5FasesParar = @('Diagn.stico del migrado', 'Lectura de las clases', 'Mapa de jobs, pasos y variables', 'C.mo se lanza cada job', 'Redacci.n de cada job', 'Resumen y glosario',
  'Guion de prueba en pre', 'Casos de las reglas sin caso', 'Comparaci.n con el original', 'Correcci.n del migrado', 'Prueba en local')

# Los practicas-despues.json de BP-2 con los getters y setters a mano de 4 ficheros (la regla que busca BP-4) y una incidencia de otra regla en uno de ellos.
function Bp5-Practicas {
  $p = Bp2-Practicas 'despues'
  $d = 'src/main/java/com/acme/recibos/domain/model/'
  $mas = @(
    (Bp2-Incidencia 'lombok' ($d + 'Pedido.java') 12 'lombok' 'getter-setter-a-mano' 'referencia' '' '6 getters y 6 setters escritos a mano: con Lombok son @Getter y @Setter' 'paso2'),
    (Bp2-Incidencia 'java21' ($d + 'Pedido.java') 40 'pmd' 'UnusedPrivateField' 'referencia' '' 'El campo observaciones no se usa.' 'mano'),
    (Bp2-Incidencia 'lombok' ($d + 'Remesa.java') 9 'lombok' 'getter-setter-a-mano' 'referencia' '' '3 getters y 3 setters escritos a mano: con Lombok son @Getter y @Setter' 'paso2'),
    (Bp2-Incidencia 'lombok' ($d + 'Cliente.java') 7 'lombok' 'getter-setter-a-mano' 'referencia' '' '4 getters y 4 setters escritos a mano: con Lombok son @Getter y @Setter' 'paso2'),
    (Bp2-Incidencia 'lombok' ($d + 'Tarifa.java') 5 'lombok' 'getter-setter-a-mano' 'referencia' '' '2 getters y 2 setters escritos a mano: con Lombok son @Getter y @Setter' 'paso2')
  )
  $p['incidencias'] = @($p['incidencias']) + $mas
  return $p
}

# El practicas-arreglos.json que deja BP-4: 2 hechas con commit (Pedido y Remesa), 1 atascada (Cliente) y 1 sin cambios (Tarifa, hecha sin commit).
function Bp5-Arreglos {
  $d = 'src/main/java/com/acme/recibos/domain/model/'
  return [ordered]@{
    version = 1; cuando = '2026-11-19T12:30:00'; pasados = 2; atascados = 1; sinCambios = 1
    tareas = @(
      [ordered]@{ fichero = ($d + 'Pedido.java'); estado = 'hecha'; commit = '1a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d'; motivo = '' },
      [ordered]@{ fichero = ($d + 'Remesa.java'); estado = 'hecha'; commit = '9f8e7d6c5b4a39281706f5e4d3c2b1a098765432'; motivo = '' },
      [ordered]@{ fichero = ($d + 'Cliente.java'); estado = 'atascada'; commit = ''; motivo = 'lo compilado cambia' },
      [ordered]@{ fichero = ($d + 'Tarifa.java'); estado = 'hecha'; commit = ''; motivo = 'sin cambios' }
    )
  }
}

# Una carpeta de salida sin correr migracion.ps1, con el estado en $Fase y la respuesta $Respuesta, una correccion completa y los JSON que se le den. Monta las paginas.
function Bp5-Salida([string]$Nombre, [string]$Fase, $Practicas = $null, $Arreglos = $null, [string]$Respuesta = 'corregir') {
  $raiz = Join-Path $Dir $Nombre
  if (Test-Path -LiteralPath $raiz) { Remove-Item -LiteralPath $raiz -Recurse -Force }
  $s = Join-Path $raiz 'migracion-batch-recibos'
  [void](New-Item -ItemType Directory -Path (Join-Path $s 'datos') -Force)
  Guarda-Json (Join-Path $s 'datos/estado.json') ([ordered]@{ batch = 'batch-recibos'; legacy = 'acme/recibos-java8'; migrado = 'acme/batch-recibos'; plantilla = 'acme/batch-referencia'; modelo = 'modelo-x'; creado = '2026-11-19T10:00:00'; actualizado = '2026-11-19T11:00:00'; fase = $Fase; respuesta = $Respuesta })
  Guarda-Json (Join-Path $s 'datos/hallazgos-antes.json') @((Hallazgo 'build' 'error' 'pom.xml' 0 'pom uno'), (Hallazgo 'tests' 'aviso' 'src/test/java' 0 'no hay tests'))
  Escribe $s 'datos/diagnostico-antes.md' (Md-Diagnostico 'compila: SI | tests: OK')
  Guarda-Json (Join-Path $s 'datos/correcciones.json') ([ordered]@{ completa = $true; codigo = 0; rama = 'rescate/main-20261119-1000'; base = 'main'; commits = @(); atascados = @(); resueltos = @(); variablesNuevas = @() })
  if ($null -ne $Practicas) { Guarda-Json (Join-Path $s 'datos/practicas-despues.json') $Practicas }
  if ($null -ne $Arreglos) { Guarda-Json (Join-Path $s 'datos/practicas-arreglos.json') $Arreglos }
  $g = Genera-Informes $s
  Comprueba "$Nombre : Write-Informes sale bien" ($g.Codigo -eq 0 -and $g.Salida -match 'INFORMES-OK') (Cola $g.Salida)
  return [pscustomobject]@{ Dir = $s; I = (Pagina $s 'index.html'); P5 = (Pagina $s '5-buenas-practicas.html') }
}

# Las lineas de "Que ha hecho el script" de la portada: Nombre, E (data-e) y Cuenta.
function Bp5-Lineas([string]$Portada) {
  $ol = [regex]::Match($Portada, '(?s)<ol class="fases">.*?</ol>').Value
  return @([regex]::Matches($ol, '(?s)<li><span class="fase-n">(.*?)</span><span class="fase-e" data-e="(.*?)">.*?</span><span class="fase-c">(.*?)</span></li>') | ForEach-Object {
      [pscustomobject]@{ Nombre = $_.Groups[1].Value; E = $_.Groups[2].Value; Cuenta = $_.Groups[3].Value }
    })
}

# Los nombres de las lineas contra los patrones esperados, en orden (la misma cuenta y cada uno en su sitio).
function Bp5-Orden($Lineas, [string[]]$Patrones) {
  $l = @($Lineas)
  if ($l.Count -ne $Patrones.Count) { return $false }
  for ($k = 0; $k -lt $l.Count; $k++) { if ($l[$k].Nombre -notmatch ('^' + $Patrones[$k] + '$')) { return $false } }
  return $true
}

# La pagina sin su CSS (que cambia por motivos que no son de esta prueba), en su SHA-256.
function Bp5-HashPagina([string]$Html) {
  $sin = [regex]::Replace($Html, '(?s)<style>.*?</style>', '')
  $sha = [System.Security.Cryptography.SHA256]::Create()
  return ([System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($sin))) -replace '-', '')
}

# La pagina 5 de la Bp5-Practicas de despues, sin practicas-arreglos.json, medida con el codigo de antes de BP-5 (9a732e2): cada cambio de la pagina 5 o del marco la cambia.
# BP-6 cambio la frase bp-area-java21-expl: con la frase de antes da 2DCE51F6...D722 (comprobado el 19-11).
$Bp5HashSinArreglos = '664229772750EE8F89F4D8BCFFFB9758F2DB07E58412A752B72FE8A50A113003'

$Pruebas['bp5 (a) con el estado en la fase practicas la portada la pone en curso, las de antes hechas y prueba-local en espera; va despues de la correccion y de comparar y antes de prueba-local'] = {
  $x = Bp5-Salida 'bp5-curso' 'practicas'
  $l = @(Bp5-Lineas $x.I)
  Igual 'la portada lista 12 fases' 12 $l.Count
  $pr = @($l | Where-Object { $_.Nombre -match 'Buenas pr.cticas' })
  Igual 'una de ellas es la de las buenas practicas' 1 $pr.Count
  if ($pr.Count -ne 1) { return }
  Igual 'esa fase esta en curso' 'curso' $pr[0].E
  $n = [array]::IndexOf(@($l | ForEach-Object { $_.Nombre }), $pr[0].Nombre)
  Comprueba 'va despues de Comparacion con el original, que va despues de la correccion' ($n -ge 2 -and $l[$n - 1].Nombre -match 'Comparaci.n con el original' -and $l[$n - 2].Nombre -match 'Correcci.n del migrado') (($l | ForEach-Object { $_.Nombre }) -join ' / ')
  Comprueba 'y justo antes de la prueba en local' ($n + 1 -lt $l.Count -and $l[$n + 1].Nombre -match 'Prueba en local')
  Igual 'las fases de antes salen hechas (diagnostico, lecturas, correccion y comparacion)' ((@('hecha') * 10) -join ' ') ((@($l | Select-Object -First $n | ForEach-Object { $_.E })) -join ' ')
  Igual 'la prueba en local esta en espera' 'espera' $l[$n + 1].E
  Comprueba 'sin practicas-arreglos.json la cuenta no tiene numeros inventados' ($pr[0].Cuenta -notmatch 'pasados a Lombok') $pr[0].Cuenta
  # con parar, comparar va antes de la correccion, y practicas sigue a la correccion
  $y = Bp5-Salida 'bp5-curso-parar' 'practicas' $null $null 'parar'
  $m = @(Bp5-Lineas $y.I)
  Comprueba 'con la respuesta parar: ... Comparacion, Correccion, Buenas practicas, Prueba en local' ((Bp5-Orden $m ($Bp5FasesParar[0..9] + @('Buenas pr.cticas.*') + @($Bp5FasesParar[10])))) (($m | ForEach-Object { $_.Nombre }) -join ' / ')
}

$Pruebas['bp5 (b) sin practicas-arreglos.json y con el estado en otra fase la lista de fases de la portada es la de antes, con corregir y con parar'] = {
  foreach ($fase in @('prueba-local', 'hecha', 'correccion')) {
    $x = Bp5-Salida "bp5-sin-$fase" $fase
    Comprueba "corregir, fase $fase : las 11 fases de siempre, sin la de las buenas practicas" (Bp5-Orden (Bp5-Lineas $x.I) $Bp5Fases) ((Bp5-Lineas $x.I | ForEach-Object { $_.Nombre }) -join ' / ')
  }
  $y = Bp5-Salida 'bp5-sin-parar' 'hecha' $null $null 'parar'
  Comprueba 'parar, fase hecha: las 11 fases de siempre, con Comparacion antes de la correccion' (Bp5-Orden (Bp5-Lineas $y.I) $Bp5FasesParar) ((Bp5-Lineas $y.I | ForEach-Object { $_.Nombre }) -join ' / ')
  $z = Bp5-Salida 'bp5-roto' 'hecha'
  Escribe $z.Dir 'datos/practicas-arreglos.json' '{ esto no es json'
  $g = Genera-Informes $z.Dir
  Comprueba 'con un practicas-arreglos.json roto se monta igual y la lista es la de siempre' ($g.Salida -match 'INFORMES-OK' -and (Bp5-Orden (Bp5-Lineas (Pagina $z.Dir 'index.html')) $Bp5Fases)) (Cola $g.Salida)
}

$Pruebas['bp5 (c) con practicas-arreglos.json la portada cuenta 2, 1 y 1 y la pagina 5 pone Arreglado: en las dos filas getter-setter-a-mano de los ficheros hechos con commit, y en ninguna mas'] = {
  $x = Bp5-Salida 'bp5-arreglos' 'hecha' (Bp5-Practicas) (Bp5-Arreglos)
  $l = @(Bp5-Lineas $x.I)
  Igual 'la portada lista 12 fases' 12 $l.Count
  $pr = @($l | Where-Object { $_.Nombre -match 'Buenas pr.cticas' })
  Igual 'con una linea de buenas practicas' 1 $pr.Count
  if ($pr.Count -eq 1) {
    Igual 'su cuenta, con los numeros del JSON' '2 pasados a Lombok, 1 atascados, 1 sin cambios' $pr[0].Cuenta
    Igual 'su estado: hecha (la pasada acabo)' 'hecha' $pr[0].E
    $n = [array]::IndexOf(@($l | ForEach-Object { $_.Nombre }), $pr[0].Nombre)
    Comprueba 'justo antes de la prueba en local' ($n + 1 -lt $l.Count -and $l[$n + 1].Nombre -match 'Prueba en local')
  }
  # la pagina 5: cada vista lleva las 15 incidencias; Arreglado: solo en las 2 de lombok de Pedido y Remesa
  foreach ($vista in @('que', 'area')) {
    $v = Bp2-Vista $x.P5 $vista
    $filas = @([regex]::Matches($v, '(?s)<li class="bp-fila .*?</li>') | ForEach-Object { $_.Value })
    Igual "vista $vista : las 15 incidencias" 15 $filas.Count
    $con = @($filas | Where-Object { $_ -match 'Arreglado:' })
    Igual "vista $vista : Arreglado: en 2 filas" 2 $con.Count
    Comprueba "vista $vista : son las de getter-setter-a-mano de Pedido y de Remesa" ($con.Count -eq 2 -and @($con | Where-Object { $_ -match 'getter-setter-a-mano' -and $_ -match '(Pedido|Remesa)\.java' }).Count -eq 2)
    Comprueba "vista $vista : con el commit en 7 caracteres" (@($con | Where-Object { $_ -match 'Arreglado: <code>(1a2b3c4|9f8e7d6)</code>' }).Count -eq 2) ($con -join "`n")
    $pedido = @($filas | Where-Object { $_ -match 'Pedido\.java' })
    Igual "vista $vista : Pedido tiene 2 filas y solo la de Lombok va arreglada" '2 1' ("$($pedido.Count) $(@($pedido | Where-Object { $_ -match 'Arreglado:' }).Count)")
    $sin = @($filas | Where-Object { $_ -match '(Cliente|Tarifa)\.java' })
    Igual "vista $vista : ni la atascada ni la sin cambios (2 filas) llevan la etiqueta" '2 0' ("$($sin.Count) $(@($sin | Where-Object { $_ -match 'Arreglado:' }).Count)")
  }
  Igual 'y en toda la pagina, 4 veces (2 filas en cada una de las 2 vistas)' 4 ([regex]::Matches($x.P5, 'Arreglado:').Count)
}

$Pruebas['bp5 (d) sin practicas-arreglos.json la pagina 5 es la de antes de BP-5, byte a byte; con uno que no arregla ningun getter-setter, tambien'] = {
  $x = Bp5-Salida 'bp5-igual' 'hecha' (Bp5-Practicas)
  $h = Bp5-HashPagina $x.P5
  if ($Bp5HashSinArreglos -ceq 'PENDIENTE') { Write-Host "  HASH $h" }
  Igual 'sin el JSON: el mismo SHA-256 (sin el CSS) que la pagina de antes del cambio' $Bp5HashSinArreglos $h
  Comprueba 'y no dice Arreglado:' (-not $x.P5.Contains('Arreglado:'))
  $a = Bp5-Arreglos
  $a['tareas'] = @($a['tareas'] | Where-Object { $_.estado -ne 'hecha' -or -not $_.commit })
  $y = Bp5-Salida 'bp5-igual-sin-hechas' 'hecha' (Bp5-Practicas) $a
  Igual 'con un JSON sin ninguna hecha con commit: la misma pagina, byte a byte' $x.P5 $y.P5
}

# ============================ M34b: LO QUE EJECUTARON LOS CASOS, EN LA PAGINA 3 ============================
# Una salida hecha a mano (sin migracion.ps1: sus datos no cambian de una corrida a otra, para poder fijar un SHA-256): un job con dos clases del
# original y datos en todos los estados. Las lineas de Validador.java son 12 20 30 40 50 60 70 y las de Lector.java 5, 9 y 15 (la 15 es una anotacion:
# no es codigo para JaCoCo y no esta en ninguna de las tres listas del JSON).
$M34bValidador = 'src/main/java/com/acme/recibos/Validador.java'
$M34bLector = 'src/main/java/com/acme/recibos/Lector.java'
$M34bEstados = @{ V = @('distinto', 'distinto', 'distinto', 'falta', 'falta', 'no-lo-se', 'igual'); L = @('no-lo-se', 'sin-pieza', 'no-lo-se') }
$M34bHashSinJson = '308DEE0ED2B35DEAAD3D61E9A7C460B3E999579648A80AB4C58C9F673F7E279A'

function M34b-Comparacion([string]$Id, [string]$Clase, [string]$Fichero, [int[]]$Lineas, [string[]]$Estados) {
  $ficha = [ordered]@{ id = $Id; fichero = $Fichero; clase = $Clase; papel = 'otro'; queHace = "Ficha de $Clase."; datos = @() }
  $comp = [ordered]@{ ficha = $Id; clase = $Clase; ficheroOriginal = $Fichero; migrado = @("src/main/java/com/acme/batch/$Clase.java"); datos = @() }
  for ($i = 0; $i -lt $Lineas.Count; $i++) {
    $ficha.datos += [ordered]@{ tipo = 'regla'; texto = "Regla de la linea $($Lineas[$i])"; linea = $Lineas[$i]; cita = "cita $($Lineas[$i])"; probado = $true }
    $d = [ordered]@{ dato = $i; estado = $Estados[$i]; fichero = ''; linea = 0; cita = ''; nota = ''; probado = $false }
    if ($Estados[$i] -ceq 'igual' -or $Estados[$i] -ceq 'distinto') { $d.fichero = "src/main/java/com/acme/batch/$Clase.java"; $d.linea = 5 + $i; $d.cita = "migrado $i"; $d.probado = $true }
    if ($Estados[$i] -ceq 'distinto' -or $Estados[$i] -ceq 'no-lo-se') { $d.nota = "nota $i" }
    $comp.datos += $d
  }
  return @{ Ficha = $ficha; Comp = $comp }
}

# El JSON de cobertura de los casos (punto 1 del encargo M34): Validador recorrido por los casos iguales en 10-14, 30, 40 y 70 y por los distintos en 30 y 48-52,
# sin recorrer en 1-9, 20, 60 y 100-125; Lector, por los iguales en 5-7 y sin recorrer en 9 y 100-109. De 64 lineas con codigo se recorren 16 (la 30 esta en las
# dos listas y cuenta una vez): el 25 %.
function M34b-Cobertura([string]$Estado = 'ok', [string]$Motivo = '') {
  return [ordered]@{
    version = 1; cuando = '2026-11-19T18:00:00'; estado = $Estado; motivo = $Motivo; lineasTotal = 64; lineasIgual = 11; lineasDistinto = 6
    ficheros = [ordered]@{
      'src/main/java/com/acme/recibos/Validador.java' = [ordered]@{ total = 50; igual = '10-14,30,40,70'; distinto = '30,48-52'; sinCubrir = '1-9,20,60,100-125' }
      'src/main/java/com/acme/recibos/Lector.java' = [ordered]@{ total = 14; igual = '5-7'; distinto = ''; sinCubrir = '9,100-109' }
    }
  }
}

function M34b-Salida([string]$Nombre, $Cobertura = $null, [string]$Texto = '', $Estados = $null) {
  if ($null -eq $Estados) { $Estados = $M34bEstados }
  $raiz = Join-Path $Dir $Nombre
  if (Test-Path -LiteralPath $raiz) { Remove-Item -LiteralPath $raiz -Recurse -Force }
  $s = Join-Path $raiz 'migracion-batch-recibos'
  foreach ($sub in @('fichas', 'comparacion')) { [void](New-Item -ItemType Directory -Path (Join-Path (Join-Path $s 'datos') $sub) -Force) }
  Guarda-Json (Join-Path $s 'datos/estado.json') ([ordered]@{ batch = 'batch-recibos'; legacy = 'acme/recibos-java8'; migrado = 'acme/batch-recibos'; plantilla = 'acme/batch-referencia'; modelo = 'modelo-x'; creado = '2026-11-19T10:00:00'; actualizado = '2026-11-19T11:00:00'; fase = 'hecha'; respuesta = 'parar' })
  $v = M34b-Comparacion 'clase-aaaa1111' 'Validador' $M34bValidador @(12, 20, 30, 40, 50, 60, 70) $Estados.V
  $l = M34b-Comparacion 'clase-bbbb2222' 'Lector' $M34bLector @(5, 9, 15) $Estados.L
  Guarda-Json (Join-Path $s 'datos/mapa.json') ([ordered]@{ jobs = @([ordered]@{ job = 'cargaJob'; clases = @([ordered]@{ ficha = 'clase-aaaa1111'; clase = 'Validador' }, [ordered]@{ ficha = 'clase-bbbb2222'; clase = 'Lector' }) }); sinJob = @() })
  foreach ($x in @($v, $l)) {
    Guarda-Json (Join-Path $s ('datos/fichas/' + $x.Ficha.id + '.json')) $x.Ficha
    Guarda-Json (Join-Path $s ('datos/comparacion/' + $x.Ficha.id + '.json')) $x.Comp
  }
  if ($null -ne $Cobertura) { Guarda-Json (Join-Path $s 'datos/prueba-local-cobertura.json') $Cobertura }
  if ($Texto) { Escribe $s 'datos/prueba-local-cobertura.json' $Texto }
  $g = Genera-Informes $s
  Comprueba "$Nombre : Write-Informes sale bien" ($g.Codigo -eq 0 -and $g.Salida -match 'INFORMES-OK') (Cola $g.Salida)
  return [pscustomobject]@{ Dir = $s; P3 = (Pagina $s '3-original-vs-migrado.html'); I = (Pagina $s 'index.html') }
}

function M34b-SinCss([string]$Html) { return [regex]::Replace($Html, '(?s)<style>.*?</style>', '') }

# Las filas de la pagina, en su orden, con la clave Clase:linea del dato del original (el primer fichero:linea de la fila) y su HTML.
function M34b-Filas([string]$Html) {
  $r = @()
  foreach ($m in [regex]::Matches((M34b-SinCss $Html), '(?s)<li class="fila[^"]*">.*?</li>')) {
    $d = [regex]::Match($m.Value, 'Original:</b> <code>[^<]*</code><code class="donde">[^<]*?(\w+)\.java:(\d+)</code>')
    $r += [pscustomobject]@{ Clave = ($d.Groups[1].Value + ':' + $d.Groups[2].Value); Html = $m.Value }
  }
  return $r
}

# Las cajas del resumen (una en Probado ejecutando los dos, otra en Leido por la IA), una detras de otra.
function M34b-Resumen([string]$Html) { return (@([regex]::Matches((M34b-SinCss $Html), '(?s)<div class="m34-resumen".*?</div>') | ForEach-Object { $_.Value }) -join "`n") }

$Pruebas['m34b (a) con la cobertura de los casos cada fila lleva su etiqueta (salio distinto, salio igual o ningun caso lo recorre) y las primeras filas van, dentro de cada estado, ejecutado-distinto, sin-ejecutar, las sin etiqueta y ejecutado-igual'] = {
  $x = M34b-Salida 'm34b-a' (M34b-Cobertura)
  $filas = @(M34b-Filas $x.P3)
  Igual 'diez filas, las de los diez datos' 10 $filas.Count
  $ant = @(M34b-Filas (M34b-Salida 'm34b-a-antes' $null).P3)
  Igual 'sin JSON, el orden de siempre: por estado y, dentro, el del dato' 'Validador:12 Validador:20 Validador:30 Validador:40 Validador:50 Validador:60 Lector:5 Lector:15 Lector:9 Validador:70' (($ant | ForEach-Object { $_.Clave }) -join ' ')
  Igual 'con JSON, dentro de cada estado: lo que salio distinto, lo que ningun caso recorre y lo que salio igual; los iguales plegados, al final' 'Validador:30 Validador:20 Validador:12 Validador:50 Validador:40 Validador:60 Lector:15 Lector:5 Lector:9 Validador:70' (($filas | ForEach-Object { $_.Clave }) -join ' ')
  $esperado = @{ 'Validador:12' = 'igual'; 'Validador:20' = 'ninguno'; 'Validador:30' = 'distinto'; 'Validador:40' = 'igual'; 'Validador:50' = 'distinto'; 'Validador:60' = 'ninguno'; 'Lector:5' = 'igual'; 'Lector:9' = 'ninguno'; 'Lector:15' = 'sin'; 'Validador:70' = 'igual' }
  $texto = @{ distinto = 'Ejecutado: sali. distinto'; igual = 'Ejecutado: sali. igual'; ninguno = 'Ning.n caso lo recorre' }
  foreach ($f in @($filas | Where-Object { $esperado[$_.Clave] -ceq 'sin' })) {
    Comprueba "$($f.Clave) : una linea que no esta en ninguna de las tres listas no lleva etiqueta" ($f.Html -notmatch 'm34-ejec|Ejecutado:|Ning.n caso lo recorre') $f.Html
  }
  foreach ($f in @($filas | Where-Object { $esperado[$_.Clave] -cne 'sin' })) {
    $e = $esperado[$f.Clave]
    $otras = @($texto.Keys | Where-Object { $_ -cne $e })
    Comprueba "$($f.Clave) : lleva la etiqueta de $e y ninguna de las otras" ($f.Html -match ('<span class="m34-ejec m34-ejec-' + $e + '">' + $texto[$e] + '</span>') -and @($otras | Where-Object { $f.Html -match $texto[$_] }).Count -eq 0 -and [regex]::Matches($f.Html, 'm34-ejec ').Count -eq 1) $f.Html
  }
  $p = M34b-SinCss $x.P3
  Comprueba 'el CSS de la etiqueta va en la pagina, con su prefijo' ($x.P3 -match '\.m34-ejec' -and $p -notmatch '(?i)<script|https?://| style=')
  Igual 'y sigue con un solo h1' 1 ([regex]::Matches($p, '<h1[ >]').Count)
}

$Pruebas['m34b (b) una linea que esta en igual y en distinto sale ejecutado-distinto'] = {
  $x = M34b-Salida 'm34b-b' (M34b-Cobertura)
  $f = @(M34b-Filas $x.P3 | Where-Object { $_.Clave -ceq 'Validador:30' })
  Igual 'la linea 30 de Validador sale una vez' 1 $f.Count
  Comprueba 'con Ejecutado: salio distinto y sin salio igual' ($f.Count -eq 1 -and $f[0].Html -match 'm34-ejec-distinto' -and $f[0].Html -notmatch 'm34-ejec-igual') ($f.Html -join ' ')
  $g = M34b-Cobertura
  $g.ficheros['src/main/java/com/acme/recibos/Validador.java'].igual = '12'
  $g.ficheros['src/main/java/com/acme/recibos/Validador.java'].distinto = '12'
  $y = M34b-Salida 'm34b-b2' $g
  $f2 = @(M34b-Filas $y.P3 | Where-Object { $_.Clave -ceq 'Validador:12' })
  Comprueba 'lo mismo con la linea 12, que es un rango de un solo numero en las dos listas' ($f2.Count -eq 1 -and $f2[0].Html -match 'm34-ejec-distinto' -and $f2[0].Html -notmatch 'm34-ejec-igual') ($f2.Html -join ' ')
}

$Pruebas['m34b (c) el resumen: el porcentaje de lineas que recorren los casos (cada linea una vez) y, de los datos que la IA no dio por iguales, cuantos ejecuto un caso que salio igual y cuantos no recorre ninguno'] = {
  $x = M34b-Salida 'm34b-c' (M34b-Cobertura)
  $r = M34b-Resumen $x.P3
  Comprueba 'hay un resumen' ($r.Length -gt 0)
  Comprueba 'dice que los casos recorren el 25 % de las lineas del original (16 de 64)' ($r -match 'Los casos recorren el 25 % de las l.neas del original\.') $r
  Comprueba 'de los 8 datos sin dar por iguales, 3 los ejecuto un caso que salio igual y 2 no los recorre ninguno (la 15 no cuenta en ninguno)' ($r -match 'De los 8 datos que la IA no ha podido dar por iguales \(distinto, falta o no lo s.\), 3 los ejecut. un caso que sali. igual en los dos; 2 no los recorre ning.n caso: empieza por esos\.') $r
  $g = M34b-Cobertura
  $g.ficheros['src/main/java/com/acme/recibos/Validador.java'].igual = '12,40,70-71'
  $g.ficheros['src/main/java/com/acme/recibos/Validador.java'].distinto = ''
  $g.ficheros['src/main/java/com/acme/recibos/Lector.java'].igual = '5'
  $y = M34b-Resumen (M34b-Salida 'm34b-c2' $g).P3
  Comprueba 'con otros rangos, los numeros cambian: 5 lineas de 64 son el 7,8 %; 3 ejecutados igual y 2 sin recorrer; ninguno distinto' ($y -match 'recorren el 7,8 % de' -and $y -match 'De los 8 datos .* 3 los ejecut. .* 2 no los recorre') $y
  $todos = @{ V = @('igual', 'igual', 'igual', 'igual', 'igual', 'igual', 'igual'); L = @('igual', 'igual', 'igual') }
  $z = M34b-Resumen (M34b-Salida 'm34b-c3' (M34b-Cobertura) $null $todos).P3
  Comprueba 'si la IA dio todo por igual no se habla de datos que revisar' ($z -match 'Los casos recorren el 25 %' -and $z -match 'no ha dejado ning.n dato' -and $z -notmatch 'empieza por esos') $z
}

$Pruebas['m34b (d) sin datos/prueba-local-cobertura.json la pagina 3 es la de antes, byte a byte (SHA-256 sin el CSS); con un JSON roto o de un estado que no se conoce, tambien'] = {
  $x = M34b-Salida 'm34b-d' $null
  $h = Bp5-HashPagina $x.P3
  Igual 'sin el JSON: el mismo SHA-256 (sin el CSS) que la pagina de antes del cambio' $M34bHashSinJson $h
  Comprueba 'y ni etiqueta ni resumen' ((M34b-SinCss $x.P3) -notmatch 'm34-|Ejecutado:')
  $roto = M34b-Salida 'm34b-d-roto' $null '{ "estado": "ok", "ficheros": '
  Igual 'con un JSON que no se puede leer: la misma pagina, byte a byte' $x.P3 $roto.P3
  $raro = M34b-Cobertura 'a medias'
  Igual 'con un estado que no es ok ni no medido: la misma pagina, byte a byte' $x.P3 (M34b-Salida 'm34b-d-raro' $raro).P3
}

$Pruebas['m34b (e) con estado no medido la pagina dice el motivo (escapado), no lleva ninguna etiqueta y las filas salen como sin JSON'] = {
  $sin = M34b-Salida 'm34b-e-sin' $null
  $x = M34b-Salida 'm34b-e' (M34b-Cobertura 'no medido' 'no hay .exec: <script>alert(1)</script> & "x".')
  $r = M34b-Resumen $x.P3
  Comprueba 'hay una frase con el motivo, con el HTML escapado y sin un punto de mas al final' ($r.Length -gt 0 -and $r.Contains((Html 'no hay .exec: <script>alert(1)</script> & "x"') + '.</p>')) $r
  Comprueba 'y no dice cuanto recorren los casos ni da numeros' ($r -notmatch ' % ' -and $r -notmatch 'empieza por esos') $r
  Comprueba 'sin <script> en la pagina' ((M34b-SinCss $x.P3) -notmatch '(?i)<script')
  Igual 'una sola caja, la de Probado ejecutando los dos, y ninguna en Leido por la IA' 1 ([regex]::Matches((M34b-SinCss $x.P3), '<div class="m34-resumen"').Count)
  Comprueba 'justo despues del titulo de Probado ejecutando los dos' ((M34b-SinCss $x.P3) -match '(?s)<section class="panel" id="prueba-local"[^>]*>\s*<h2 id="t-prueba-local">[^<]*</h2>\s*<div class="m34-resumen"[^>]*>\s*<p>No se ha medido')
  Comprueba 'ninguna fila lleva etiqueta' ((M34b-SinCss $x.P3) -notmatch 'm34-ejec|Ejecutado:|Ning.n caso lo recorre')
  Igual 'y las filas son las de sin JSON, las mismas y en el mismo orden' ((@(M34b-Filas $sin.P3) | ForEach-Object { $_.Html }) -join "`n") ((@(M34b-Filas $x.P3) | ForEach-Object { $_.Html }) -join "`n")
  $y = M34b-Resumen (M34b-Salida 'm34b-e-vacio' (M34b-Cobertura 'no medido' '')).P3
  Comprueba 'sin motivo, la frase sale igual y dice que no se dijo por que' ($y -match 'no se ha dicho por qu.') $y
}

$Pruebas['m34b (f) un fichero que el JSON no trae sale sin etiqueta y no cuenta ni entre los que ejecuto un caso ni entre los que ninguno recorre'] = {
  $g = M34b-Cobertura
  $g.ficheros.Remove('src/main/java/com/acme/recibos/Lector.java')
  $x = M34b-Salida 'm34b-f' $g
  $f = @(M34b-Filas $x.P3 | Where-Object { $_.Clave -ceq 'Lector:5' })
  Comprueba 'Lector:5, que antes salia igual, ya no lleva etiqueta' ($f.Count -eq 1 -and $f[0].Html -notmatch 'm34-ejec') ($f.Html -join ' ')
  $r = M34b-Resumen $x.P3
  Comprueba 'el resumen cuenta 8 datos, 2 ejecutados igual y 2 sin recorrer' ($r -match 'De los 8 datos .* 2 los ejecut. .* 2 no los recorre') $r
}

$Pruebas['m34b (g) una linea que no esta en igual, distinto ni sinCubrir sale sin etiqueta, no cuenta como ejecutada ni como sin recorrer y queda entre las sin recorrer y las ejecutadas iguales'] = {
  $x = M34b-Salida 'm34b-g' (M34b-Cobertura)
  $f = @(M34b-Filas $x.P3 | Where-Object { $_.Clave -ceq 'Lector:15' })
  Comprueba 'Lector:15 (no-lo-se de una anotacion) sale una vez y sin etiqueta' ($f.Count -eq 1 -and $f[0].Html -notmatch 'm34-ejec') ($f.Html -join ' ')
  $r = M34b-Resumen $x.P3
  Comprueba 'pero cuenta entre los 8 datos que la IA no dio por iguales y no en los 3 ni en los 2' ($r -match 'De los 8 datos .* 3 los ejecut. .* 2 no los recorre') $r
  $g = M34b-Cobertura
  $g.ficheros['src/main/java/com/acme/recibos/Validador.java'].Remove('sinCubrir')
  $y = M34b-Salida 'm34b-g2' $g
  Comprueba 'con un JSON sin sinCubrir ninguna fila sale como sin recorrer' (@(M34b-Filas $y.P3 | Where-Object { $_.Html -match 'm34-ejec-ninguno' -and $_.Clave -like 'Validador:*' }).Count -eq 0)
}

$Pruebas['m34b (h) el resumen en singular: con 1 dato que la IA no dio por igual, con 1 ejecutado igual y con 1 sin recorrer'] = {
  $solo = @{ V = @('distinto', 'igual', 'igual', 'igual', 'igual', 'igual', 'igual'); L = @('igual', 'igual', 'igual') }
  $r = M34b-Resumen (M34b-Salida 'm34b-h1' (M34b-Cobertura) $null $solo).P3
  Comprueba 'un dato y 1 lo ejecuto un caso que salio igual (la 12), 0 sin recorrer' ($r -match 'De 1 dato que la IA no ha podido dar por igual \(distinto, falta o no lo s.\), 1 lo ejecut. un caso que sali. igual en los dos; 0 no los recorre ning.n caso: empieza por esos\.') $r
  $solo.V[0] = 'igual'; $solo.V[1] = 'distinto'
  $r = M34b-Resumen (M34b-Salida 'm34b-h2' (M34b-Cobertura) $null $solo).P3
  Comprueba 'un dato que ningun caso recorre (la 20): 0 los ejecuto, 1 no lo recorre, empieza por ese' ($r -match 'De 1 dato que la IA no ha podido dar por igual \(distinto, falta o no lo s.\), 0 los ejecut. un caso que sali. igual en los dos; 1 no lo recorre ning.n caso: empieza por ese\.') $r
  $r = M34b-Resumen (M34b-Salida 'm34b-h3' (M34b-Cobertura)).P3
  Comprueba 'con varios, el plural de siempre' ($r -match 'De los 8 datos que la IA no ha podido dar por iguales' -and $r -match '3 los ejecut. un caso' -and $r -match '2 no los recorre ning.n caso: empieza por esos\.') $r
}

$Pruebas['m34b (i) portada, Que es cada fichero: datos/prueba-local-cobertura.json sale con su frase y solo si existe'] = {
  $sin = M34b-Salida 'm34b-i-sin' $null
  $f = [regex]::Match($sin.I, '(?s)<ul class="ficheros">.*?</ul>').Value
  Comprueba 'sin el JSON no sale' ($f.Length -gt 0 -and $f -notmatch 'prueba-local-cobertura') $f
  $x = M34b-Salida 'm34b-i' (M34b-Cobertura)
  $f = [regex]::Match($x.I, '(?s)<ul class="ficheros">.*?</ul>').Value
  Comprueba 'con el JSON sale con su frase, que dice de donde salen las etiquetas y el resumen de la pagina 3' ($f -match '(?s)<li>(?:(?!</li>).)*<code>datos/prueba-local-cobertura\.json</code></p><p>[^<]{20,}</p>' -and $f -match 'prueba-local-cobertura\.json</code></p><p>[^<]*Ejecutado[^<]*p.gina 3') $f
}

$Pruebas['m34b (j) el sitio de las cajas: lo que recorren los casos, al principio de Probado ejecutando los dos y justo tras su titulo; los datos que la IA no dio por iguales, en Leido por la IA tras su parrafo de explicacion y antes del primer job; ninguna en la cabecera'] = {
  $x = M34b-Salida 'm34b-j' (M34b-Cobertura)
  $p = M34b-SinCss $x.P3
  Igual 'dos cajas, ni mas ni menos' 2 ([regex]::Matches($p, '<div class="m34-resumen"').Count)
  $c1 = [regex]::Match($p, '(?s)<section class="panel" id="prueba-local"[^>]*>\s*<h2 id="t-prueba-local">[^<]*</h2>\s*(<div class="m34-resumen".*?</div>)').Groups[1].Value
  Comprueba 'la primera, dentro de Probado ejecutando los dos y justo tras su titulo, dice lo que recorren los casos y nada mas' ($c1 -match 'Los casos recorren el 25 %' -and $c1 -notmatch 'De los ') $c1
  $c2 = [regex]::Match($p, '(?s)id="t-leido-ia".*?citas existen en los ficheros\.</p>\s*(<div class="m34-resumen".*?</div>)\s*<section class="prob-grupo comp-grupo" id="comp-').Groups[1].Value
  Comprueba 'la segunda, en Leido por la IA tras su parrafo de explicacion y antes del primer job, dice los datos y nada mas' ($c2 -match 'De los 8 datos' -and $c2 -notmatch 'Los casos recorren') $c2
  Comprueba 'la cabecera de la pagina no lleva ninguna' ($p -notmatch '(?s)<header class="cab-prob">(?:(?!</header>).)*m34-resumen')
  Comprueba 'las dos son la misma caja, cada una con su id' ($c1 -match 'class="m34-resumen" id="m34-recorren"' -and $c2 -match 'class="m34-resumen" id="m34-dudosos"')
  $todos = @{ V = @('igual', 'igual', 'igual', 'igual', 'igual', 'igual', 'igual'); L = @('igual', 'igual', 'igual') }
  $z = M34b-SinCss (M34b-Salida 'm34b-j-igual' (M34b-Cobertura) $null $todos).P3
  Comprueba 'si la IA dio todo por igual, "no ha dejado ningun dato" va en la caja de Leido por la IA' ($z -match '(?s)id="t-leido-ia".*?<div class="m34-resumen"[^>]*>\s*<p>La IA no ha dejado ning.n dato')
}

# ============ M35b: EL INFORME CONOCE LA FASE reglas ============
# El nombre de la fase en la portada. Va despues de las buenas practicas (si la pasada las tiene) y antes de la prueba en local.
$M35bFase = 'Tests de las reglas de negocio'
# Los nombres de las fases de la portada, en su orden, con la fase reglas y sin la de las buenas practicas, con corregir y con parar.
$M35bFases = @($Bp5Fases[0..9] + @($M35bFase) + @($Bp5Fases[10]))
$M35bFasesParar = @($Bp5FasesParar[0..9] + @($M35bFase) + @($Bp5FasesParar[10]))
# La portada de la salida de Bp5-Salida en la fase hecha, sin practicas-arreglos.json ni tests-reglas.json, sin el CSS, medida con el codigo de antes de M35b (35973df).
$M35bHashSinJson = 'CEB94C1CC174B9D6BF2EE788FE1567CA953010C58CF414B0376B4108C4C0B58C'

# El tests-reglas.json que deja M35 (tests-reglas.ps1, Save-ResultadoReglas): 2 clases con test (Pedido con 2 reglas vigiladas y Remesa con 1), 1 atascada (Cliente) y 0 saltadas.
function M35b-Reglas {
  $d = 'src/main/java/com/acme/recibos/domain/model/'
  $t = 'src/test/java/com/acme/recibos/domain/model/'
  return [ordered]@{
    version = 1; cuando = '2026-11-19T20:00:00'; conTest = 2; reglasVigiladas = 3; atascadas = 1; saltadas = 0
    tareas = @(
      [ordered]@{ clase = 'Pedido'; fichero = ($d + 'Pedido.java'); test = ($t + 'PedidoReglasTest.java'); estado = 'hecha'; commit = '1a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d'; motivo = ''
        reglas = @([ordered]@{ texto = 'Un pedido sin lineas no se factura'; linea = 20; resultado = 'vigilada'; motivo = '' }, [ordered]@{ texto = 'El importe no puede ser negativo'; linea = 31; resultado = 'vigilada'; motivo = '' }) },
      [ordered]@{ clase = 'Remesa'; fichero = ($d + 'Remesa.java'); test = ($t + 'RemesaReglasTest.java'); estado = 'hecha'; commit = '9f8e7d6c5b4a39281706f5e4d3c2b1a098765432'; motivo = ''
        reglas = @([ordered]@{ texto = 'La remesa cierra el ultimo dia habil'; linea = 15; resultado = 'vigilada'; motivo = '' }) },
      [ordered]@{ clase = 'Cliente'; fichero = ($d + 'Cliente.java'); test = ($t + 'ClienteReglasTest.java'); estado = 'atascada'; commit = ''; motivo = 'el test no compila'; reglas = @() }
    )
  }
}

# Una salida de Bp5-Salida (estado en $Fase, correccion completa) a la que se le anade tests-reglas.json si se da y se vuelve a montar la portada.
function M35b-Salida([string]$Nombre, [string]$Fase, $Reglas = $null, $Arreglos = $null, [string]$Respuesta = 'corregir') {
  $x = Bp5-Salida $Nombre $Fase $null $Arreglos $Respuesta
  if ($null -eq $Reglas) { return $x }
  Guarda-Json (Join-Path $x.Dir 'datos/tests-reglas.json') $Reglas
  $g = Genera-Informes $x.Dir
  Comprueba "$Nombre : Write-Informes con tests-reglas.json sale bien" ($g.Codigo -eq 0 -and $g.Salida -match 'INFORMES-OK') (Cola $g.Salida)
  return [pscustomobject]@{ Dir = $x.Dir; I = (Pagina $x.Dir 'index.html'); P5 = (Pagina $x.Dir '5-buenas-practicas.html') }
}

# Sin la fase de las buenas practicas, con la de las reglas la portada lista 12 fases y la de las reglas va entre la comparacion y la prueba en local.
function M35b-Comprueba-Sitio([string]$Nombre, $L, [string]$Antes) {
  $r = @($L | Where-Object { $_.Nombre -match $M35bFase })
  Igual "$Nombre : una linea de la fase de las reglas" 1 $r.Count
  if ($r.Count -ne 1) { return $null }
  $n = [array]::IndexOf(@($L | ForEach-Object { $_.Nombre }), $r[0].Nombre)
  Comprueba "$Nombre : justo despues de $Antes y justo antes de la prueba en local" ($n -ge 1 -and $n + 1 -lt @($L).Count -and $L[$n - 1].Nombre -match $Antes -and $L[$n + 1].Nombre -match 'Prueba en local') (($L | ForEach-Object { $_.Nombre }) -join ' / ')
  return $r[0]
}

$Pruebas['m35b (a) con tests-reglas.json la portada pone la fase de las reglas despues de las buenas practicas (o de la comparacion) y antes de prueba-local, con la cuenta del JSON'] = {
  $x = M35b-Salida 'm35b-a' 'hecha' (M35b-Reglas) (Bp5-Arreglos)
  $l = @(Bp5-Lineas $x.I)
  Igual 'con las buenas practicas, la portada lista 13 fases' 13 $l.Count
  $r = M35b-Comprueba-Sitio 'con practicas' $l 'Buenas pr.cticas'
  if ($r) {
    Igual 'su cuenta, con los numeros del JSON' '2 clases con test (3 reglas vigiladas), 1 atascadas, 0 saltadas' $r.Cuenta
    Igual 'su estado: hecha (la pasada acabo)' 'hecha' $r.E
  }
  $y = M35b-Salida 'm35b-a-sin-practicas' 'hecha' (M35b-Reglas)
  $m = @(Bp5-Lineas $y.I)
  Igual 'sin las buenas practicas, la portada lista 12 fases' 12 $m.Count
  Comprueba 'las 12 en su orden: la de las reglas despues de la correccion y de la comparacion' (Bp5-Orden $m $M35bFases) (($m | ForEach-Object { $_.Nombre }) -join ' / ')
  [void](M35b-Comprueba-Sitio 'sin practicas' $m 'Comparaci.n con el original')
  $z = M35b-Salida 'm35b-a-parar' 'hecha' (M35b-Reglas) $null 'parar'
  Comprueba 'con la respuesta parar: ... Comparacion, Correccion, Tests de las reglas, Prueba en local' (Bp5-Orden (Bp5-Lineas $z.I) $M35bFasesParar) ((Bp5-Lineas $z.I | ForEach-Object { $_.Nombre }) -join ' / ')
  $w = M35b-Salida 'm35b-a-parar-practicas' 'hecha' (M35b-Reglas) (Bp5-Arreglos) 'parar'
  $o = @($Bp5FasesParar[0..9] + @('Buenas pr.cticas con Lombok') + @($M35bFase) + @($Bp5FasesParar[10]))
  Comprueba 'con parar, practicas-arreglos.json y tests-reglas.json a la vez: ... Correccion, Buenas practicas, Tests de las reglas, Prueba en local' (Bp5-Orden (Bp5-Lineas $w.I) $o) ((Bp5-Lineas $w.I | ForEach-Object { $_.Nombre }) -join ' / ')
  $h = M35b-Salida 'm35b-a-cero' 'hecha' ([ordered]@{ version = 1; cuando = '2026-11-19T20:00:00'; conTest = 0; reglasVigiladas = 0; atascadas = 0; saltadas = 4; tareas = @() })
  $c = @(Bp5-Lineas $h.I | Where-Object { $_.Nombre -match $M35bFase })
  Igual 'con 0 clases con test y 4 saltadas: la cuenta sigue al JSON' '0 clases con test (0 reglas vigiladas), 0 atascadas, 4 saltadas' ($c | ForEach-Object { $_.Cuenta })
}

$Pruebas['m35b (b) con el estado de la pasada en reglas y sin tests-reglas.json la fase sale en curso, con las de antes hechas y prueba-local en espera'] = {
  $x = M35b-Salida 'm35b-b' 'reglas' $null (Bp5-Arreglos)
  $l = @(Bp5-Lineas $x.I)
  Igual 'con las buenas practicas, la portada lista 13 fases' 13 $l.Count
  $r = M35b-Comprueba-Sitio 'curso' $l 'Buenas pr.cticas'
  if ($r) {
    Igual 'su estado: en curso' 'curso' $r.E
    Comprueba 'su cuenta no inventa numeros' ($r.Cuenta -notmatch 'clases con test') $r.Cuenta
    $n = [array]::IndexOf(@($l | ForEach-Object { $_.Nombre }), $r.Nombre)
    Igual 'las fases de antes salen hechas' ((@('hecha') * $n) -join ' ') ((@($l | Select-Object -First $n | ForEach-Object { $_.E })) -join ' ')
    Igual 'la prueba en local esta en espera' 'espera' $l[$n + 1].E
  }
  $y = M35b-Salida 'm35b-b-sin-practicas' 'reglas'
  $m = @(Bp5-Lineas $y.I)
  Comprueba 'sin las buenas practicas: las 12 fases con la de las reglas en su sitio' (Bp5-Orden $m $M35bFases) (($m | ForEach-Object { $_.Nombre }) -join ' / ')
  $e = @($m | Where-Object { $_.Nombre -match $M35bFase })
  Comprueba 'y en curso' ($e.Count -eq 1 -and $e[0].E -ceq 'curso') (($m | ForEach-Object { "$($_.Nombre)=$($_.E)" }) -join ' / ')
  $z = M35b-Salida 'm35b-b-parar' 'reglas' $null $null 'parar'
  Comprueba 'con la respuesta parar tambien: ... Correccion, Tests de las reglas, Prueba en local' (Bp5-Orden (Bp5-Lineas $z.I) $M35bFasesParar) ((Bp5-Lineas $z.I | ForEach-Object { $_.Nombre }) -join ' / ')
}

$Pruebas['m35b (c) sin tests-reglas.json y con el estado en otra fase la portada es la de antes, byte a byte (SHA-256 sin el CSS); con un JSON roto, las fases son las de antes'] = {
  $x = M35b-Salida 'm35b-c' 'hecha'
  $h = Bp5-HashPagina $x.I
  if ($M35bHashSinJson -ceq 'PENDIENTE') { Write-Host "  HASH $h" }
  Igual 'sin el JSON: el mismo SHA-256 (sin el CSS) que la portada de antes del cambio' $M35bHashSinJson $h
  Comprueba 'y no nombra la fase ni el JSON' ($x.I -notmatch 'Tests de las reglas' -and -not $x.I.Contains('tests-reglas.json'))
  foreach ($fase in @('prueba-local', 'correccion', 'practicas')) {
    $y = M35b-Salida "m35b-c-$fase" $fase
    $esperado = if ($fase -ceq 'practicas') { @($Bp5Fases[0..9] + @('Buenas pr.cticas con Lombok') + @($Bp5Fases[10])) } else { $Bp5Fases }
    Comprueba "fase $fase : las fases de siempre, sin la de las reglas" (Bp5-Orden (Bp5-Lineas $y.I) $esperado) ((Bp5-Lineas $y.I | ForEach-Object { $_.Nombre }) -join ' / ')
  }
  $z = M35b-Salida 'm35b-c-roto' 'hecha'
  Escribe $z.Dir 'datos/tests-reglas.json' '{ esto no es json'
  $g = Genera-Informes $z.Dir
  $t = Pagina $z.Dir 'index.html'
  Comprueba 'con un tests-reglas.json roto se monta igual y la lista de fases es la de siempre' ($g.Salida -match 'INFORMES-OK' -and (Bp5-Orden (Bp5-Lineas $t) $Bp5Fases)) (Cola $g.Salida)
}

$Pruebas['m35b (d) portada, Que es cada fichero: datos/tests-reglas.json sale con su frase y solo si existe'] = {
  $sin = M35b-Salida 'm35b-d-sin' 'hecha'
  $f = [regex]::Match($sin.I, '(?s)<ul class="ficheros">.*?</ul>').Value
  Comprueba 'sin el JSON no sale' ($f.Length -gt 0 -and $f -notmatch 'tests-reglas') $f
  $x = M35b-Salida 'm35b-d' 'hecha' (M35b-Reglas)
  $f = [regex]::Match($x.I, '(?s)<ul class="ficheros">.*?</ul>').Value
  Comprueba 'con el JSON sale con su frase, que dice que son los tests de las reglas' ($f -match '(?s)<li>(?:(?!</li>).)*<code>datos/tests-reglas\.json</code></p><p>[^<]{20,}</p>' -and $f -match 'tests-reglas\.json</code></p><p>[^<]*tests[^<]*reglas') $f
}

# ================================ LANZADOR ================================
Invoke-Banco $Pruebas $Script
