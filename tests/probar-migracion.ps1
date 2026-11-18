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
  $todas = @($deTareas) + @($deMigra) + @(Funciones-De (Join-Path $raiz 'comun.ps1')) + @(Funciones-De (Join-Path $raiz 'informe.ps1'))
  $dup = @($todas | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
  Comprueba 'ninguna funcion esta definida dos veces entre comun, tareas, migracion e informe' ($dup.Count -eq 0) ($dup -join ', ')
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
  $cab = "`$ErrorActionPreference = 'Stop'`n. '" + (Join-Path $raiz 'comun.ps1') + "'`n. '" + (Join-Path $raiz 'tareas.ps1') + "'`n. '" + (Join-Path $raiz 'informe.ps1') + "'`n"
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
  foreach ($n in @('index.html', '1-batch-original.html', '2-problemas.html', '3-original-vs-migrado.html', '4-correcciones.html')) {
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
  $paginas = @('index.html', '1-batch-original.html', '2-problemas.html', '3-original-vs-migrado.html', '4-correcciones.html')
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
  foreach ($f in @('migracion.ps1', 'comun.ps1', 'tareas.ps1', 'informe.ps1', 'informe', 'tareas')) { Copy-Item -LiteralPath (Join-Path $raiz $f) -Destination (Join-Path $sis $f) -Recurse }
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
    foreach ($f in @('migracion.ps1', 'comun.ps1', 'tareas.ps1', 'informe.ps1', 'informe', 'tareas')) { Copy-Item -LiteralPath (Join-Path $raiz $f) -Destination (Join-Path $sis $f) -Recurse }
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
  $ip = @($lis | Where-Object { $_ -match 'Guion de prueba en pre' })[0]
  $ic = @($lis | Where-Object { $_ -match 'Comparaci.n con el original' })[0]
  $ir = @($lis | Where-Object { $_ -match 'Correcci.n del migrado' })[0]
  Comprueba 'Que ha hecho el script: la fase va entre el guion de prueba y la correccion' ($ic -and ([array]::IndexOf($lis, $ip) + 1) -eq [array]::IndexOf($lis, $ic) -and ([array]::IndexOf($lis, $ic) + 1) -eq [array]::IndexOf($lis, $ir)) $fases
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
  foreach ($k in @(@('diagnostico', 'Diagn.stico'), @('clases', 'Lectura de las clases'), @('mapa', 'Mapa de jobs'), @('jobs', 'Redacci.n de cada job'), @('resumen', 'Resumen y glosario'),
      @('pre', 'Guion de prueba'), @('correccion', 'Correcci.n del migrado'), @('comparar', 'Comparaci.n con el original'), @('local', 'Prueba en local'))) {
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
  $corregir = 'diagnostico clases mapa jobs resumen pre correccion comparar local'
  $parar = 'diagnostico clases mapa jobs resumen pre comparar correccion local'
  $antes = 'diagnostico=hecha clases=hecha mapa=hecha jobs=hecha resumen=hecha pre=hecha'
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

# ================================ LANZADOR ================================
Invoke-Banco $Pruebas $Script
