<#
regresion.ps1 - Lo que hace -Regresion de prueba-local.ps1: los casos que salen iguales en el original y en el migrado se quedan en la rama de
rescate como tests de JUnit (en un solo commit), para que el siguiente que toque el batch tenga una red de comportamiento de verdad.
No se ejecuta solo: prueba-local.ps1 lo carga con '. (Join-Path $PSScriptRoot ''regresion.ps1'')' y solo lleva funciones. Compatible con
Windows PowerShell 5.1 y PowerShell 7. Solo ASCII a proposito. Sin llamadas a la IA.

QUE PONE (en la carpeta de la rama de rescate, $DirRama)
  - el arnes del migrado guardado (PruebaLocalTest.java y application-prueba-local.yml, si lo tiene), igual;
  - src/test/resources/prueba-local/<job>/<caso>/: las entradas de cada caso, como las usa el arnes;
  - src/test/resources/prueba-local-esperado/<job>/<caso>/: la salida del original de ese caso, sin tablas\BATCH_*.csv ni tablas\TASK_*.csv;
  - src/test/java/<paquete del arnes>/RegresionLocalTest.java, de la plantilla regresion\RegresionLocalTest.java.txt, que compara lo que sale
    con el esperado con las reglas de la prueba en local;
  - src/test/resources/junit-platform.properties con el orden de las clases (RegresionLocalTest, despues de PruebaLocalTest).
  La rama refleja solo los casos que salen iguales en este lanzamiento, probados juntos: los que ya estaban en ella y ahora salen distintos (o ya
  no estan, o se han quitado) se borran de las dos carpetas en el mismo commit y se cuentan (regresion.json: retirados). Si no hay commit, no se retira nada.
  Antes del commit, todo se prueba en una copia desechable de la rama (<Migrado>-regresion): el Maven de la copia ejecuta los dos tests y tiene que
  pasar (lo que falla en esa JVM se quita, una vez) y, cambiando un byte del esperado, tiene que fallar (sensibilidad).
Lo que usan, del main de prueba-local.ps1: $DirRama, $MigradoRoot, $Local, $DatosMig, $Casos, $ArnesMig, $Propios, $Latin, $Utf8 y $Cfg.
#>

# '' si -Regresion puede lanzarse; si no, el motivo. Como -Reparar, necesita el worktree de rescate y su carpeta sin cambios sin commit.
function Get-MotivoRegresion([bool]$HayRescate) {
  if (-not $HayRescate) { return "-Regresion necesita el worktree de rescate: lanza migracion.ps1 primero: crea $dirRescate." }
  if (Test-RamaSucia) { return "$DirRama tiene cambios sin commit (git status): guardalos o descartalos y vuelve a lanzar con -Regresion." }
  return ''
}

# Los ficheros de la salida de un caso en $Dir que valen como esperado: sin las tablas del framework (Spring Batch y Spring Cloud Task), como
# Compare-Caso. Rutas relativas, con /.
function Get-FicherosEsperados([string]$Dir) {
  if (-not (Test-Path -LiteralPath $Dir)) { return @() }
  return @(Get-ChildItem -LiteralPath $Dir -Recurse -File | ForEach-Object { Get-Rel $Dir $_.FullName } | Where-Object { $_ -cnotmatch '^tablas/(BATCH|TASK)_[^/]*\.csv$' })
}

# Por que la salida del original en $Dir no vale como test fijo ('' si vale): lleva algo de esta ejecucion (la fecha de hoy, una hora o la ruta de una
# copia: lo que Get-Normal quita al comparar), que otro dia ya no saldria igual, y el test de Java compara lo demas byte a byte.
function Get-MotivoCambiante([string]$Dir, [string[]]$Rels) {
  foreach ($rel in $Rels) {
    $texto = $Latin.GetString([System.IO.File]::ReadAllBytes((Join-Ruta $Dir $rel)))
    if ((Get-Normal $rel) -cne $rel -or (Get-Normal $texto) -cne $texto) { return "$rel lleva la fecha de hoy, una hora o la ruta de una copia: no saldria igual en otra ejecucion." }
  }
  return ''
}

function Write-TextoRegresion([string]$Ruta, [string]$Texto) {
  [void](New-Item -ItemType Directory -Path (Split-Path $Ruta -Parent) -Force)
  [System.IO.File]::WriteAllText($Ruta, $Texto, $Utf8)
}

# Pone en la copia $Copia todo lo de -Regresion: el arnes guardado, RegresionLocalTest.java, el orden de las clases y, de cada caso de $S.Casos, sus
# entradas y su esperado (lo que habia de otros lanzamientos en las dos carpetas se quita: solo se prueban los casos de este). Devuelve las rutas
# de lo que no es de un caso, para el commit.
function Set-Regresion([string]$Copia, $S) {
  Remove-Carpeta (Join-Ruta $Copia $Casos)
  Remove-Carpeta (Join-Ruta $Copia ($Casos + '-esperado'))
  $arnes = Join-Ruta $Local "arnes/$($ArnesMig.entradas.repo)"
  Copy-Carpeta $arnes $Copia
  $test = [string]$ArnesMig.entradas.test
  $carpeta = $test.Substring(0, $test.LastIndexOf('/'))
  $paquete = $carpeta.Substring('src/test/java'.Length).Trim('/').Replace('/', '.')
  $decl = ''
  if ($paquete) { $decl = "package $paquete;" }
  $plantilla = [System.IO.File]::ReadAllText((Join-Path (Join-Path $PSScriptRoot 'regresion') 'RegresionLocalTest.java.txt'), $Utf8)
  $propio = "$carpeta/RegresionLocalTest.java"
  Write-TextoRegresion (Join-Ruta $Copia $propio) $plantilla.Replace('package {{PAQUETE}};', $decl)
  # RegresionLocalTest tiene que correr despues de PruebaLocalTest (que deja target/prueba-local): las clases con @Order van por su numero
  $orden = 'src/test/resources/junit-platform.properties'
  $texto = ''
  if (Test-Path -LiteralPath (Join-Ruta $Copia $orden)) { $texto = [System.IO.File]::ReadAllText((Join-Ruta $Copia $orden), $Utf8) }
  if ($texto -notmatch '(?m)^\s*junit\.jupiter\.testclass\.order\.default\s*[=:]') {
    if ($texto -and -not $texto.EndsWith("`n")) { $texto += "`n" }
    Write-TextoRegresion (Join-Ruta $Copia $orden) ($texto + 'junit.jupiter.testclass.order.default=org.junit.jupiter.api.ClassOrderer$OrderAnnotation' + "`n")
  }
  foreach ($c in $S.Casos) {
    Copy-Carpeta (Join-Ruta $Local "casos/$($c.job)/$($c.caso)") (Join-Ruta $Copia "$Casos/$($c.job)/$($c.caso)")
    foreach ($rel in $c.rels) { Copy-Fichero (Join-Ruta $Local "salidas/original/$($c.job)/$($c.caso)/$rel") (Join-Ruta $Copia "$Casos-esperado/$($c.job)/$($c.caso)/$rel") }
  }
  return @(@(Get-ChildItem -LiteralPath $arnes -Recurse -File | ForEach-Object { Get-Rel $arnes $_.FullName }) + @($propio, $orden))
}

# Ejecuta en la copia los dos tests (el arnes y la regresion, en una sola JVM) y devuelve el Maven y los casos que fallan (los que dice
# target/regresion-fallos.txt, una linea por caso: job, caso y mensaje, con tabuladores).
function Invoke-MavenRegresion([string]$Copia, [string]$Que) {
  $f = Join-Ruta $Copia 'target/regresion-fallos.txt'
  if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force }
  $m = Invoke-Maven $Copia $false @('test', '-Dtest=PruebaLocalTest,RegresionLocalTest') $Que
  $fallos = @()
  if (Test-Path -LiteralPath $f) {
    foreach ($l in @([System.IO.File]::ReadAllLines($f, $Utf8))) {
      $p = $l -split "`t", 3
      if ($p.Count -eq 3) { $fallos += [pscustomobject]@{ job = $p[0]; caso = $p[1]; motivo = $p[2] } }
    }
  }
  return [pscustomobject]@{ Maven = $m; Fallos = $fallos }
}

# Quita de la copia y de $S.Casos los casos de $Fallos, con su motivo.
function Remove-CasosRegresion([string]$Copia, $S, $Fallos) {
  foreach ($f in $Fallos) {
    $S.Quitados += [pscustomobject]@{ job = $f.job; caso = $f.caso; motivo = "falla en la copia: $($f.motivo)" }
    Remove-Carpeta (Join-Ruta $Copia "$Casos/$($f.job)/$($f.caso)")
    Remove-Carpeta (Join-Ruta $Copia "$Casos-esperado/$($f.job)/$($f.caso)")
  }
  $S.Casos = @($S.Casos | Where-Object { $c = $_; @($Fallos | Where-Object { $_.job -ceq $c.job -and $_.caso -ceq $c.caso }).Count -eq 0 })
}

# Sensibilidad: se cambia un byte de un fichero del esperado de $Caso y el mismo Maven tiene que fallar, diciendo ese caso; despues el fichero
# vuelve a como estaba. Vale cualquier fichero menos estado.txt (que todos los casos tienen) si hay otro con algo dentro. '' si falla como debe.
function Test-Sensibilidad([string]$Copia, $Caso) {
  $rels = Sort-Ordinal $Caso.rels
  $rel = @($rels | Where-Object { $_ -cne 'estado.txt' -and (Get-Item -LiteralPath (Join-Ruta $Copia "$Casos-esperado/$($Caso.job)/$($Caso.caso)/$_")).Length -gt 0 })[0]
  if (-not $rel) { $rel = $rels[0] }
  $f = Join-Ruta $Copia "$Casos-esperado/$($Caso.job)/$($Caso.caso)/$rel"
  $bytes = [System.IO.File]::ReadAllBytes($f)
  $malo = [byte[]]@(65)
  if ($bytes.Length -gt 0) { $malo = [byte[]]$bytes.Clone(); $malo[0] = $malo[0] -bxor 1 }
  try {
    [System.IO.File]::WriteAllBytes($f, $malo)
    $v = Invoke-MavenRegresion $Copia "regresion: un byte cambiado en $($Caso.job)/$($Caso.caso)"
  }
  finally { [System.IO.File]::WriteAllBytes($f, $bytes) }
  if ($v.Maven.Codigo -ne 0 -and @($v.Fallos | Where-Object { $_.job -ceq $Caso.job -and $_.caso -ceq $Caso.caso }).Count -gt 0) { return '' }
  return "La comprobacion no es sensible: con un byte cambiado en $rel del esperado de $($Caso.job)/$($Caso.caso), Maven no ha fallado en ese caso (codigo $($v.Maven.Codigo))."
}

# Prueba en la copia lo que se va a commitear: los dos tests tienen que pasar (lo que falla se quita y se repite una vez) y la sensibilidad. Deja en
# $S.Casos los casos buenos y, si no se puede, en $S.Motivo el porque.
function Test-Regresion([string]$Copia, $S) {
  $m = New-Copia $MigradoRoot (Get-Head $DirRama) $Copia
  if ($m) { $S.Motivo = $m; return }
  $S.Rutas = @(Set-Regresion $Copia $S)
  $v = Invoke-MavenRegresion $Copia 'regresion: los casos como tests'
  if ($v.Maven.Codigo -ne 0) {
    if ($v.Fallos.Count -eq 0) { $S.Motivo = "Maven falla con los tests de regresion sin decir que caso:`n" + (Get-FalloMaven $v.Maven); return }
    Info "Regresion: $($v.Fallos.Count) caso(s) fallan en la copia y se quitan: $((@($v.Fallos | ForEach-Object { "$($_.job)/$($_.caso)" })) -join ', ')."
    Remove-CasosRegresion $Copia $S $v.Fallos
    if ($S.Casos.Count -eq 0) { $S.Motivo = 'ningun caso pasa en la copia'; return }
    $v = Invoke-MavenRegresion $Copia 'regresion: sin los casos que fallaban'
    if ($v.Maven.Codigo -ne 0) { $S.Motivo = "Sin esos casos, Maven sigue fallando:`n" + (Get-FalloMaven $v.Maven); return }
  }
  $S.Motivo = Test-Sensibilidad $Copia $S.Casos[0]
}

# Los casos que la rama de rescate guarda ya como tests, segun git: job, caso y las carpetas (del esperado y de las entradas) que tiene en git.
function Get-CasosDeRama {
  $r = Invoke-Git $DirRama @('-c', 'core.quotepath=off', 'ls-files', '--', $Casos, "$Casos-esperado")
  $h = [ordered]@{}
  foreach ($l in @($r.Salida)) {
    $m = [regex]::Match("$l", '^(' + [regex]::Escape($Casos) + '(?:-esperado)?)/([^/]+)/([^/]+)/')
    if (-not $m.Success) { continue }
    $k = $m.Groups[2].Value + '/' + $m.Groups[3].Value
    if (-not $h.Contains($k)) { $h[$k] = [pscustomobject]@{ job = $m.Groups[2].Value; caso = $m.Groups[3].Value; dirs = @() } }
    $d = $m.Groups[1].Value + '/' + $k
    if ($h[$k].dirs -notcontains $d) { $h[$k].dirs += $d }
  }
  return @($h.Values)
}

# Borra de la carpeta de la rama los casos que ya estaban en ella y no estan entre los de este lanzamiento (y la carpeta del job si se queda vacia).
# Devuelve los casos retirados, con sus carpetas.
function Remove-CasosDeRama($Actuales) {
  $ahora = @($Actuales | ForEach-Object { "$($_.job)/$($_.caso)" })
  $retirados = @(Get-CasosDeRama | Where-Object { $ahora -notcontains "$($_.job)/$($_.caso)" })
  foreach ($c in $retirados) {
    foreach ($d in $c.dirs) {
      Remove-Carpeta (Join-Ruta $DirRama $d)
      $job = Split-Path (Join-Ruta $DirRama $d) -Parent
      if ((Test-Path -LiteralPath $job) -and @(Get-ChildItem -LiteralPath $job -Force).Count -eq 0) { Remove-Item -LiteralPath $job -Force }
    }
  }
  return $retirados
}

# Lleva a la carpeta de la rama de rescate lo probado en la copia y lo commitea (un commit, con pathspec explicito): los casos iguales de este
# lanzamiento entran y los que ya estaban y ya no valen salen ($S.Retirados). Devuelve '' o el porque no hay commit; si git falla, deja la rama
# como estaba. Si ya estaba todo igual en la rama, no hay commit nuevo: $S.SinCambios.
function Save-Regresion([string]$Copia, $S) {
  $rutas = @($S.Rutas)
  $S.Retirados = @(Remove-CasosDeRama $S.Casos)
  foreach ($c in $S.Retirados) { $rutas += $c.dirs }
  foreach ($c in $S.Casos) {
    foreach ($d in @("$Casos/$($c.job)/$($c.caso)", "$Casos-esperado/$($c.job)/$($c.caso)")) {
      Remove-Carpeta (Join-Ruta $DirRama $d)
      Copy-Carpeta (Join-Ruta $Copia $d) (Join-Ruta $DirRama $d)
      $rutas += $d
    }
  }
  foreach ($rel in @($S.Rutas)) { Copy-Fichero (Join-Ruta $Copia $rel) (Join-Ruta $DirRama $rel) }
  Invoke-GitRutas $DirRama @('add') $rutas
  if ((Invoke-Git $DirRama @('diff', '--cached', '--quiet')).Codigo -eq 0) { $S.SinCambios = $true; $S.Commit = Get-Head $DirRama; return '' }
  $jobs = @($S.Casos | ForEach-Object { $_.job } | Select-Object -Unique).Count
  $r = Invoke-Git $DirRama (@('commit', '-q') + @($Cfg.CommitArgs) + @('-m', "test(regresion): casos de la prueba en local como tests ($($S.Casos.Count) casos, $jobs jobs)"))
  if ($r.Codigo -eq 0) {
    $S.Commit = Get-Head $DirRama
    $script:Propios += $S.Commit
    return ''
  }
  Invoke-GitRutas $DirRama @('reset', '-q') $rutas
  Invoke-GitRutas $DirRama @('clean', '-fdq') $rutas
  Invoke-GitRutas $DirRama @('checkout', '-q') @(Get-Cambios $DirRama)
  $S.Retirados = @()
  return "git commit ha fallado en ${DirRama}: " + (Get-Resumen ($r.Salida -join "`n"))
}

# -Regresion, despues de lo demas (tras -Reparar): los casos de $Res que salen iguales se quedan como tests en la rama de rescate. Deja
# datos\regresion.json y una linea. No cambia el codigo de salida de prueba-local.ps1.
function Invoke-Regresion($Res) {
  $s = [pscustomobject]@{ Casos = @(); Quitados = @(); Retirados = @(); Rutas = @(); Motivo = ''; Commit = ''; SinCambios = $false }
  $iguales = @($Res | Where-Object { $_.resultado -eq 'igual' })
  foreach ($r in $iguales) {
    $esperado = Join-Ruta $Local "salidas/original/$($r.job)/$($r.caso)"
    $rels = @(Get-FicherosEsperados $esperado)
    $motivo = Get-MotivoCambiante $esperado $rels
    if ($motivo) { $s.Quitados += [pscustomobject]@{ job = $r.job; caso = $r.caso; motivo = $motivo } }
    else { $s.Casos += [pscustomobject]@{ job = $r.job; caso = $r.caso; rels = $rels } }
  }
  $copia = $MigradoRoot + '-regresion'
  if ($iguales.Count -eq 0) { $s.Motivo = 'ningun caso sale igual en este lanzamiento' }
  elseif ($s.Casos.Count -eq 0) { $s.Motivo = 'ningun caso vale como test fijo' }
  else { Test-Regresion $copia $s }
  if (-not $s.Motivo) { $s.Motivo = Save-Regresion $copia $s }
  $casos = @($s.Casos | ForEach-Object { [ordered]@{ job = $_.job; caso = $_.caso } })
  if ($s.Motivo) { $casos = @() }
  Write-Json (Join-Path $DatosMig 'regresion.json') ([ordered]@{ version = 1; rama = (Get-Rama $DirRama); commit = $s.Commit; casos = $casos; quitados = @($s.Quitados | ForEach-Object { [ordered]@{ job = $_.job; caso = $_.caso; motivo = $_.motivo } }); retirados = @($s.Retirados | ForEach-Object { [ordered]@{ job = $_.job; caso = $_.caso } }); motivo = $s.Motivo })
  Info ''
  $donde = "$(@($casos | ForEach-Object { $_.job } | Select-Object -Unique).Count) jobs"
  $retirados = "Retirados de la rama: $(@($s.Retirados).Count) (ahora salen distintos o ya no estan)."
  if ($s.SinCambios) { Info "Regresion: $($casos.Count) casos de $donde ya estaban como tests en $(Get-Rama $DirRama) ($($s.Commit.Substring(0, 7))), sin cambios: no hay commit nuevo. Quitados: $(@($s.Quitados).Count). $retirados" }
  elseif ($s.Commit) { Info "Regresion: $($casos.Count) casos de $donde quedan como tests en $(Get-Rama $DirRama) ($($s.Commit.Substring(0, 7))). Quitados: $(@($s.Quitados).Count). $retirados" }
  elseif ($iguales.Count -eq 0) { Info "Regresion: $($s.Motivo): no se commitea nada." }
  else { Aviso "Regresion: $($s.Motivo): no se commitea nada. Quitados: $(@($s.Quitados).Count)." }
  foreach ($q in @($s.Quitados)) { Aviso "  quitado: $($q.job)/$($q.caso): $(($q.motivo -split "`n")[0])" }
}
