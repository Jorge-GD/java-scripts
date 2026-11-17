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
function Escenario-Dos([string]$Nombre, [string[]]$UsaConfig = @()) {
  $e = Nuevo-Escenario $Nombre @()
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
  Igual 'estado: fase' 'lectura-hecha' (Estado $e).fase
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
  Igual 'la fase acaba' 'lectura-hecha' (Estado $e).fase
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
  Igual 'las fases siguientes se hacen igual' 'lectura-hecha' (Estado $e).fase
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
  Comprueba 'todavia no hay contrato' (-not (Test-Path -LiteralPath (Get-Ruta $e.Wt '.rescate/contrato.json')))
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
  Igual 'y la fase acaba' 'lectura-hecha' (Estado $c2.E).fase
  # ninguna redaccion hecha: no hay tarea
  $c3 = Corrida-Dos 'json-roto:^ficha-job:'
  Igual 'sin ninguna ficha de job hecha: ninguna llamada de resumen' 0 (Llamadas-De (Llamadas $c3.E.Wt) 'resumen').Count
  Comprueba 'ni resumen.json' (-not (Test-Path -LiteralPath (Get-Ruta $c3.E.Out 'datos/resumen.json')))
  Igual 'ni tarea' 0 @(Tareas $c3.E 'resumen').Count
  Igual 'la fase acaba' 'lectura-hecha' (Estado $c3.E).fase
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
  Igual 'doce llamadas en total (8 clases, 1 definicion, 2 jobs, 1 resumen)' 12 $ll.Count
  Igual 'ninguna tarea se repitio' 12 @($ll | Select-Object -ExpandProperty id -Unique).Count
  Igual 'la fase acaba' 'lectura-hecha' (Estado $e).fase
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

$Pruebas['39 fases: fichas-clase, mapa, fichas-job, resumen y lectura-hecha; con una clase atascada se hacen igual'] = {
  $e = Escenario-Dos 'fases'
  $g = 'json-roto:^Auxiliar1$'
  $esperadas = @(@('2', 'fichas-clase'), @('6', 'mapa'), @('1', 'fichas-job'), @('2', 'resumen'), @('', 'lectura-hecha'))
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
  Igual 'las llamadas: 8 clases (+1 reintento), 1 definicion, 2 jobs, 1 resumen' 13 (Llamadas $e.Wt).Count
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

# ================================ LANZADOR ================================
Invoke-Banco $Pruebas $Script
