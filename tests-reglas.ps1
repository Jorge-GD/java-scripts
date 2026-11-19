<#
tests-reglas.ps1 - M35: un test unitario por cada regla de negocio, comprobado con mutantes en la linea de la regla (la fase 'reglas' de
migracion.ps1, con -Reglas). No se ejecuta solo: solo funciones (y un ajuste de $Cfg). Se carga con '. (Join-Path $PSScriptRoot 'tests-reglas.ps1')'
despues de comun.ps1, tareas.ps1 e informe.ps1 (Read-Comparaciones). Usa las variables del script que lo carga ($RepoRoot, el worktree del migrado;
$Datos, $Registros, $Cfg, $ModeloElegido y $Estado; y, si estan, $MaxHoras y $reloj) y sus funciones Save-Estado, Save-Informes y Set-Parada. Solo
ASCII. Vale para Windows PowerShell 5.1 y para PowerShell 7. Tiene la misma forma que arreglo-practicas.ps1 (BP-4): rondas, tareas, reintento con
motivo y un commit por fichero.

  Invoke-FaseReglas <conservar>   La fase. Devuelve $true si se puede seguir con lo que viene despues (no hay parada). Con $conservar, las tareas
                                  atascadas de un lanzamiento anterior no se repiten.

Que hace: una tarea por cada clase del migrado (un .java de src/main/java) con al menos una regla de negocio que la comparacion da por igual: un dato de
tipo 'regla' de datos\fichas\<ficha>.json cuyo estado en datos\comparacion\<ficha>.json es igual, con su fichero y su linea en el migrado (la linea se
corrige con la cita, como hace la comparacion). La IA escribe, con tareas\test-reglas.md, un test JUnit 5 sin Spring llamado <Clase>ReglasTest (mismo
paquete, bajo src/test/java) con un metodo por regla. Una clase cuyo test ya existe, o cuyas reglas no tienen ningun operador que cambiar, se salta.
Tras cada ronda (hasta $Cfg.Paralelo clases a la vez, en el mismo worktree): se deshace lo que la IA haya tocado fuera de su test; se rechaza el test
que arranca Spring y el que no compila (una compilacion por ronda; si falla, de uno en uno); cada test se lanza solo (mvn -B test
-Dtest=<Clase>ReglasTest) y tiene que pasar; y se cambia la linea de cada regla (Get-MutanteLinea: ==/!=, >=, <=, >, <, &&, ||, true/false, quitar
un ! o, si no hay nada de eso, poner un ! tras 'if (' o 'while ('), como mucho $Cfg.MutantesPorClase lineas por clase: con cada cambio el test tiene que fallar, y despues la linea vuelve a como estaba (se
comprueba byte a byte). Resultado de cada regla: vigilada (el test falla con el cambio), no-vigilada (pasa igual) o sin-mutante (nada que cambiar,
el cambio no compila, no se pudo medir o se paso del tope). Se acepta el test si hay alguna regla vigilada y ninguna no-vigilada: se commitea
('test(reglas): <ruta del test>'). Si no, se borra y vuelve a pendiente con el motivo ('Tu test no falla si en la linea N cambio ... por ...: no
comprueba la regla ...'); al segundo fallo queda atascado. Deja datos\tests-reglas.json (por clase: estado, commit, motivo y reglas con su resultado)
y la linea 'Tests de reglas: N clases con test (R reglas vigiladas), M atascadas, K saltadas'. Paradas: no-compila (el migrado no compila antes de
empezar), git (un commit falla o un fichero de src/main no se puede dejar como estaba), copilot-no-responde y tope-de-tiempo (-MaxHoras).
#>

# ============================ CONFIGURACION ============================
$Cfg += @{
  MutantesPorClase = 6    # como mucho, estas lineas de reglas se cambian por clase (el resto queda sin-mutante)
}

# ================================ DATOS ================================
# El asunto del commit de un test.
function Get-AsuntoReglas([string]$Test) { return ('test(reglas): ' + $Test) }

# Donde va el test de un fichero de src/main/java: el mismo paquete bajo src/test/java (del mismo modulo) y <Clase>ReglasTest. '' si el fichero
# no es de src/main/java.
function Get-RutaTestReglas([string]$Fichero) {
  $m = [regex]::Match($Fichero, '^((?:.*/)?)src/main/java/((?:[^/]+/)*)([^/]+)\.java$')
  if (-not $m.Success) { return '' }
  return ($m.Groups[1].Value + 'src/test/java/' + $m.Groups[2].Value + $m.Groups[3].Value + 'ReglasTest.java')
}

# Los cambios que se prueban en la linea de una regla, en este orden: el primero que encaja con la linea es el que se aplica. Patron busca el operador
# (sobre la linea sin textos ni comentarios) y Por dice con que se cambia.
function Get-CambiosReglas {
  return @(
    @{ Patron = '(?<![=!<>+\-*/%&|^])==(?!=)|!=(?!=)'; Por = @{ '==' = '!='; '!=' = '==' } },
    @{ Patron = '(?<!>)>=(?!=)'; Por = @{ '>=' = '<' } },
    @{ Patron = '(?<!<)<=(?!=)'; Por = @{ '<=' = '>' } },
    @{ Patron = '(?<=\s)>(?=\s)'; Por = @{ '>' = '<=' } },
    @{ Patron = '(?<=\s)<(?=\s)'; Por = @{ '<' = '>=' } },
    @{ Patron = '&&'; Por = @{ '&&' = '||' } },
    @{ Patron = '\|\|'; Por = @{ '||' = '&&' } },
    @{ Patron = '\b(?:true|false)\b'; Por = @{ 'true' = 'false'; 'false' = 'true' } },
    @{ Patron = '!(?=[(A-Za-z_])'; Por = @{ '!' = '' } },
    # la condicion sin operador (una sola llamada, un nombre): se niega, con un ! tras el parentesis
    @{ Patron = '\b(?:if|while) ?\((?!\s*!)'; Por = @{ 'if (' = 'if (!'; 'if(' = 'if(!'; 'while (' = 'while (!'; 'while(' = 'while(!' } }
  )
}

# El primer cambio de la lista que aplica a una linea de codigo: Linea (la linea cambiada), Antes y Despues (el operador y por que se cambia). Los
# textos entre comillas y los comentarios no cuentan. $null si no aplica ninguno.
function Get-MutanteLinea([string]$Linea) {
  $sin = [regex]::Replace($Linea, '"(?:[^"\\]|\\.)*"|''(?:[^''\\]|\\.)*''|//.*|/\*.*?\*/', { param($t) '_' * $t.Length })
  foreach ($c in @(Get-CambiosReglas)) {
    $m = [regex]::Match($sin, $c.Patron)
    if (-not $m.Success) { continue }
    $por = [string]$c.Por[$m.Value]
    return [pscustomobject]@{ Linea = ($Linea.Substring(0, $m.Index) + $por + $Linea.Substring($m.Index + $m.Length)); Antes = $m.Value; Despues = $por }
  }
  return $null
}

# Las reglas que la comparacion da por iguales, por fichero del migrado (en el orden de la comparacion): una lista de reglas con texto (el de la ficha),
# linea (la de la comparacion), cita (la del migrado) y ubicada.
function Get-ReglasComparadas {
  $por = [ordered]@{}
  $comparaciones = Read-Comparaciones $Datos
  foreach ($id in @($comparaciones.Keys)) {
    $ficha = Read-JsonSuave (Join-Path (Join-Path $Datos 'fichas') ($id + '.json'))
    if (-not $ficha) { continue }
    $dichos = @($ficha.datos)
    foreach ($d in @($comparaciones[$id].datos)) {
      if ($d.estado -cne 'igual' -or -not $d.fichero -or [int]$d.linea -lt 1) { continue }
      $h = $dichos[[int]$d.dato]
      if (-not $h -or $h.tipo -cne 'regla') { continue }
      $f = [string]$d.fichero
      if (-not $por.Contains($f)) { $por[$f] = @() }
      $regla = [ordered]@{ texto = ([string]$h.texto -replace '\s+', ' ').Trim(); linea = [int]$d.linea; cita = ([string]$d.cita -replace '\s+', ' ').Trim(); ubicada = $true }
      if (@($por[$f] | Where-Object { $_.linea -eq $regla.linea -and $_.texto -ceq $regla.texto }).Count -eq 0) { $por[$f] += , $regla }
    }
  }
  return $por
}

# Las lineas de un fichero como se cambian: byte a byte (ISO-8859-1), cortadas por \n (con \r al final si es CRLF).
function Get-LineasReglas([byte[]]$Bytes) { return [System.Text.Encoding]::GetEncoding(28591).GetString($Bytes).Split("`n") }

# La linea de una regla segun su cita: la mas cercana a la de la comparacion donde sale la cita. Sin cita no se corrige; si la cita no sale en el
# fichero, la regla queda sin ubicar (con la linea de la comparacion).
function Set-UbicacionRegla($Regla, $Indice) {
  if (-not $Regla.cita) { return }
  $donde = @(Find-Cita $Indice $Regla.cita)
  if ($donde.Count -eq 0) { $Regla.ubicada = $false; return }
  $Regla.linea = [int](@($donde | Sort-Object { [math]::Abs($_ - $Regla.linea) })[0])
}

# Las tareas: una por clase del migrado con reglas iguales, con su id (hash de la ruta) y su huella (el fichero en HEAD y sus reglas con su linea; no
# depende del HEAD). Una clase cuyo test ya existe, o cuyas reglas no tienen nada que cambiar, nace hecha y saltada.
function Get-TareasReglas([bool]$Conservar) {
  $tareas = @()
  $por = Get-ReglasComparadas
  foreach ($f in @($por.Keys)) {
    $test = Get-RutaTestReglas $f
    $ruta = Join-Ruta $RepoRoot $f
    if (-not $test -or -not (Test-Path -LiteralPath $ruta -PathType Leaf)) { continue }
    $blob = ((Invoke-Git $RepoRoot @('rev-parse', '--verify', '-q', ('HEAD:' + $f))).Salida -join '').Trim()
    if ($blob -notmatch '^[0-9a-f]{40,64}$') { continue }
    $indice = Get-IndiceCitas $ruta
    $lineas = Get-LineasReglas ([System.IO.File]::ReadAllBytes($ruta))
    $reglas = @($por[$f])
    foreach ($r in $reglas) { Set-UbicacionRegla $r $indice }
    $texto = @()
    for ($i = 0; $i -lt $reglas.Count; $i++) {
      $texto += ('REGLA ' + ($i + 1) + ': ' + $reglas[$i].texto)
      $texto += ('  Linea ' + $reglas[$i].linea + ': ' + $reglas[$i].cita)
    }
    $testClase = [System.IO.Path]::GetFileNameWithoutExtension($test)
    $paquete = ''
    if ($test -match '/src/test/java/(.+)/[^/]+$' -or $test -match '^src/test/java/(.+)/[^/]+$') { $paquete = $Matches[1].Replace('/', '.') }
    $huella = Get-Hash8 ($blob + '|' + ((@($reglas | ForEach-Object { "$($_.linea)|$($_.texto)|$($_.cita)" })) -join "`n"))
    $entradas = [pscustomobject]@{
      clase = [System.IO.Path]::GetFileNameWithoutExtension($f); fichero = $f; test = $test; testClase = $testClase; paquete = $paquete
      reglas = $reglas; huella = $huella
      prompt = [pscustomobject]@{ FICHERO = $f; TEST = $test; TEST_CLASE = $testClase; PAQUETE = $paquete; REGLAS = ($texto -join "`n") }
    }
    $t = New-TareaTipo 'test-reglas' ('reglas-' + (Get-Hash8 $f)) '' '' $entradas
    $saltada = ''
    if (Test-Path -LiteralPath (Join-Ruta $RepoRoot $test)) { $saltada = 'ya existe ' + $test }
    elseif (@($reglas | Where-Object { $_.ubicada -and $_.linea -le $lineas.Count -and (Get-MutanteLinea $lineas[$_.linea - 1]) }).Count -eq 0) {
      $saltada = 'ningun cambio posible en las lineas de sus reglas: no se puede comprobar un test'
    }
    if ($saltada) {
      $t.estado = 'hecha'
      $t.resultado = [pscustomobject]@{ commit = ''; saltada = $true; motivo = $saltada; reglas = @() }
    }
    $tareas += , (Restore-Tarea $t $Conservar)
  }
  return $tareas
}

# ============================== MAVEN ==============================
# Las primeras lineas [ERROR] de la salida de Maven (o la ultima linea), en una sola.
function Get-MotivoMavenReglas($M) {
  $err = @($M.Salida | Where-Object { $_ -match '^\[ERROR\]' } | Select-Object -First 3 | ForEach-Object { $_ -replace '^\[ERROR\]\s*', '' })
  if ($err.Count -eq 0) { $err = @(Get-UltimaLinea ($M.Salida -join "`n")) }
  $t = $err -join ' / '
  if ($t.Length -gt 300) { $t = $t.Substring(0, 300) + '...' }
  return $t
}

# mvn -B test-compile (compila src/main y src/test) en el worktree. Lo que Maven deje fuera de target no es de la IA y se quita. Devuelve '' si
# compila; si no, por que (sus primeras lineas [ERROR] o el tope de tiempo).
function Invoke-CompilarReglas([string]$Que, [string]$Registro) {
  $previos = @(Get-Cambios $RepoRoot)
  $m = Invoke-MavenTope $RepoRoot @('-B', 'test-compile') $Que (Join-Path $Registros $Registro)
  [void](Remove-Ruido $RepoRoot $previos)
  if ($m.Tope) { return $m.Tope }
  if ($m.Codigo -eq 0) { return '' }
  return ('No compila: ' + (Get-MotivoMavenReglas $m))
}

# mvn -B test -Dtest=<Clase> en el worktree. Estado: pasa (ha ejecutado tests y pasan), falla (algun test falla), no-compila, no-corre (no ha
# ejecutado ningun test), tope (se paso del tiempo) u otro (Maven falla por otra cosa); y su Motivo.
function Invoke-TestReglas([string]$Clase, [string]$Que, [string]$Registro) {
  $previos = @(Get-Cambios $RepoRoot)
  $m = Invoke-MavenTope $RepoRoot @('-B', 'test', "-Dtest=$Clase", '-Dsurefire.failIfNoSpecifiedTests=false', '-DfailIfNoSpecifiedTests=false') $Que (Join-Path $Registros $Registro)
  [void](Remove-Ruido $RepoRoot $previos)
  $texto = $m.Salida -join "`n"
  $r = [pscustomobject]@{ Estado = 'otro'; Motivo = ('Maven ha fallado: ' + (Get-MotivoMavenReglas $m)) }
  if ($m.Tope) { $r.Estado = 'tope'; $r.Motivo = $m.Tope }
  elseif ($texto -match 'COMPILATION ERROR|Compilation failure') { $r.Estado = 'no-compila'; $r.Motivo = 'No compila: ' + (Get-MotivoMavenReglas $m) }
  elseif ($m.Codigo -eq 0) {
    $corrio = @([regex]::Matches($texto, 'Tests run: (\d+), Failures: \d+, Errors: \d+, Skipped: (\d+)') | Where-Object { [int]$_.Groups[1].Value -gt [int]$_.Groups[2].Value }).Count -gt 0
    if ($corrio) { $r.Estado = 'pasa'; $r.Motivo = '' }
    else { $r.Estado = 'no-corre'; $r.Motivo = 'Maven no ha ejecutado ningun test de ' + $Clase + ': tiene que ser una clase de JUnit 5 con metodos @Test.' }
  }
  elseif ($texto -match 'Tests run:[^\r\n]*(Failures: [1-9]|Errors: [1-9])|There are test failures') { $r.Estado = 'falla'; $r.Motivo = Get-MotivoMavenReglas $m }
  return $r
}

# ================================ MUTANTES ================================
# Si $Ruta es un fichero con exactamente $Bytes.
function Test-FicheroReglas([string]$Ruta, [byte[]]$Bytes) {
  if (-not (Test-Path -LiteralPath $Ruta -PathType Leaf)) { return $false }
  $l = [System.Text.Encoding]::GetEncoding(28591)
  return [string]::Equals($l.GetString([System.IO.File]::ReadAllBytes($Ruta)), $l.GetString($Bytes), [System.StringComparison]::Ordinal)
}

# Deja un fichero de src/main con sus bytes de antes. Devuelve '' si queda byte a byte igual; si no, por que no (lo ultimo que dijo git).
function Restore-FicheroReglas([string]$Fichero, [byte[]]$Bytes) {
  $ruta = Join-Ruta $RepoRoot $Fichero
  try { [System.IO.File]::WriteAllBytes($ruta, $Bytes) } catch { }
  if (Test-FicheroReglas $ruta $Bytes) { return '' }
  $g = Invoke-Git $RepoRoot @('checkout', '-q', '--', $Fichero)
  if (Test-FicheroReglas $ruta $Bytes) { return '' }
  return ("No he podido dejar $Fichero como estaba: " + (@($g.Salida) -join ' / '))
}

# El cambio de la linea $Linea de la clase de $R: lo escribe, lanza el test (que tiene que fallar) y deja la linea como estaba. Devuelve Resultado
# (vigilada, no-vigilada o sin-mutante), Antes y Despues (el cambio), Motivo (el de un sin-mutante), Aplicado (se lanzo el test) y Git ('' o por que
# el fichero no ha quedado como estaba).
function Measure-MutanteReglas($R, [int]$Linea, [string[]]$Lineas, [byte[]]$Bytes, [bool]$SinCupo) {
  $o = [pscustomobject]@{ Resultado = 'sin-mutante'; Antes = ''; Despues = ''; Motivo = ''; Aplicado = $false; Git = '' }
  $m = $null
  if ($Linea -ge 1 -and $Linea -le $Lineas.Count) { $m = Get-MutanteLinea $Lineas[$Linea - 1] }
  if (-not $m) { $o.Motivo = "ningun cambio posible en la linea $Linea"; return $o }
  $o.Antes = $m.Antes; $o.Despues = $m.Despues
  if ($SinCupo) { $o.Motivo = "fuera del tope de $($Cfg.MutantesPorClase) lineas cambiadas por clase"; return $o }
  $o.Aplicado = $true
  $e = $R.Tarea.entradas
  $copia = [string[]]$Lineas.Clone()
  $copia[$Linea - 1] = $m.Linea
  [System.IO.File]::WriteAllBytes((Join-Ruta $RepoRoot $e.fichero), [System.Text.Encoding]::GetEncoding(28591).GetBytes(($copia -join "`n")))
  try { $p = Invoke-TestReglas $e.testClase "lanzar $($e.testClase) con un cambio en la linea $Linea" ('reglas-' + $R.Tarea.id + '-l' + $Linea + '.log') }
  finally { $o.Git = Restore-FicheroReglas $e.fichero $Bytes }
  $cambio = '`' + $m.Antes + '` por `' + $m.Despues + '`'
  if ($p.Estado -ceq 'falla') { $o.Resultado = 'vigilada' }
  elseif ($p.Estado -ceq 'tope') { $o.Resultado = 'vigilada'; $o.Motivo = "con el cambio de la linea $Linea el test se pasa del tiempo" }
  elseif ($p.Estado -ceq 'pasa') { $o.Resultado = 'no-vigilada' }
  elseif ($p.Estado -ceq 'no-compila') { $o.Motivo = "el cambio ($cambio) en la linea $Linea no compila" }
  else { $o.Motivo = "no se ha podido medir el cambio ($cambio) en la linea $Linea`: " + $p.Motivo }
  return $o
}

# Lo que se le dice a la IA de una regla que su test no vigila.
function Get-MotivoNoVigiladaReglas([int]$Linea, $Medida, [string]$Texto) {
  $cambio = 'cambio `' + $Medida.Antes + '` por `' + $Medida.Despues + '`'
  if ($Medida.Despues -ceq '') { $cambio = 'quito el `!`' }
  return ("Tu test no falla si en la linea $Linea $cambio`: no comprueba la regla `"$Texto`"")
}

# Los cambios de las reglas de una clase (hasta $Cfg.MutantesPorClase lineas distintas; una linea con dos reglas se prueba una vez). Devuelve Reglas
# (por regla: texto, linea, resultado y motivo) y Git ('' o por que se paro).
function Test-MutantesReglas($R) {
  $e = $R.Tarea.entradas
  $bytes = [System.IO.File]::ReadAllBytes((Join-Ruta $RepoRoot $e.fichero))
  $lineas = Get-LineasReglas $bytes
  $medidas = @{}
  $aplicados = 0
  $filas = @()
  foreach ($regla in @($e.reglas)) {
    $k = [int]$regla.linea
    $fila = [ordered]@{ texto = [string]$regla.texto; linea = $k; resultado = 'sin-mutante'; motivo = '' }
    $filas += , $fila
    if (-not $regla.ubicada) { $fila.motivo = 'la cita no sale en el fichero: no se sabe en que linea esta la regla'; continue }
    if (-not $medidas.ContainsKey($k)) {
      $medidas[$k] = Measure-MutanteReglas $R $k $lineas $bytes ($aplicados -ge [int]$Cfg.MutantesPorClase)
      if ($medidas[$k].Aplicado) { $aplicados++ }
      if ($medidas[$k].Git) { return [pscustomobject]@{ Reglas = $filas; Git = $medidas[$k].Git } }
    }
    $fila.resultado = $medidas[$k].Resultado
    if ($fila.resultado -ceq 'no-vigilada') { $fila.motivo = Get-MotivoNoVigiladaReglas $k $medidas[$k] $fila.texto } else { $fila.motivo = $medidas[$k].Motivo }
  }
  return [pscustomobject]@{ Reglas = $filas; Git = '' }
}

# Lo que hay que decirle a la IA si el test no vale ('' si vale): alguna regla no vigilada, o ninguna vigilada.
function Get-VeredictoReglas($Reglas) {
  $no = @($Reglas | Where-Object { $_.resultado -ceq 'no-vigilada' })
  $t = ''
  if ($no.Count -gt 0) { $t = (@($no | ForEach-Object { $_.motivo }) -join ' | ') }
  elseif (@($Reglas | Where-Object { $_.resultado -ceq 'vigilada' }).Count -eq 0) {
    $t = 'No he podido comprobar que tu test vigile ninguna regla: ' + ((@($Reglas | ForEach-Object { $_.motivo }) | Where-Object { $_ }) -join ' | ')
  }
  if ($t.Length -gt 800) { $t = $t.Substring(0, 800) + '...' }
  return $t
}

# ================================ RONDAS ================================
# Borra el fichero de un test (si esta).
function Remove-TestReglas([string]$Test) {
  $ruta = Join-Ruta $RepoRoot $Test
  if (Test-Path -LiteralPath $ruta) { Remove-Item -LiteralPath $ruta -Force }
}

# El test no vale: se borra, y la tarea vuelve con su motivo.
function Set-InvalidaReglas($R, [string]$Motivo) {
  Remove-TestReglas $R.Tarea.entradas.test
  $R.Estado = 'invalida'
  $R.Motivo = $Motivo
  Info "Vuelve atras $($R.Tarea.entradas.test): $Motivo"
}

# Commit de un test ya comprobado. Si git lo rechaza, el test se borra y el resultado queda en 'git'.
function Save-CommitReglas($R) {
  $f = $R.Tarea.entradas.test
  $c = Invoke-Git $RepoRoot @('add', '--', $f)
  if ($c.Codigo -eq 0) { $c = Invoke-Git $RepoRoot (@('commit', '-q') + @($Cfg.CommitArgs) + @('-m', (Get-AsuntoReglas $f), '--', $f)) }
  if ($c.Codigo -eq 0) { $R.Commit = Get-Head $RepoRoot; return }
  [void](Invoke-Git $RepoRoot @('reset', '-q', '--', $f))
  Remove-TestReglas $f
  $R.Estado = 'git'
  $R.Motivo = (@($c.Salida) -join ' / ')
}

# Un test con su fichero ya en el worktree: compila (si no se ha compilado ya con la ronda), pasa, vigila sus reglas (los cambios) y se commitea; o se
# borra con su motivo.
function Confirm-TestReglas($R, [bool]$Compilado) {
  $t = $R.Tarea
  $e = $t.entradas
  if (-not $Compilado) {
    $c = Invoke-CompilarReglas "compilar $($e.testClase)" ('reglas-' + $t.id + '-compila.log')
    if ($c) { Set-InvalidaReglas $R $c; return }
  }
  $p = Invoke-TestReglas $e.testClase "lanzar $($e.testClase)" ('reglas-' + $t.id + '.log')
  if ($p.Estado -cne 'pasa') {
    $que = 'Tu test no pasa con el codigo tal como esta: '
    if ($p.Estado -cin @('no-compila', 'no-corre', 'otro')) { $que = '' }
    Set-InvalidaReglas $R ($que + $p.Motivo)
    return
  }
  $v = Test-MutantesReglas $R
  $R.Reglas = @($v.Reglas)
  if ($v.Git) { $R.Estado = 'git'; $R.Motivo = $v.Git; return }
  $mal = Get-VeredictoReglas $R.Reglas
  if ($mal) { Set-InvalidaReglas $R $mal; return }
  Save-CommitReglas $R
}

# Da por bueno, o no, el test de cada tarea de $Cand (los de la ronda que la IA ha escrito bien). Uno solo se compila y comprueba directamente; varios,
# con una compilacion para todos y, si no compila, poniendo cada test solo. Si algo para la fase (git), los que quedan no se tocan.
function Confirm-CandidatosReglas($Cand) {
  $solos = ($Cand.Count -eq 1)
  if (-not $solos) {
    $c = Invoke-CompilarReglas 'compilar los tests de la ronda' 'reglas-ronda.log'
    if ($c) { Info "La ronda no compila ($c): pruebo los tests de uno en uno."; $solos = $true }
  }
  $guardado = @{}
  if ($solos -and $Cand.Count -gt 1) {
    foreach ($x in $Cand) { $guardado[$x.Tarea.entradas.test] = [System.IO.File]::ReadAllBytes((Join-Ruta $RepoRoot $x.Tarea.entradas.test)) }
    foreach ($x in $Cand) { Remove-TestReglas $x.Tarea.entradas.test }
  }
  $parar = $false
  foreach ($x in $Cand) {
    $f = $x.Tarea.entradas.test
    if ($parar) { $x.Estado = 'git'; $x.Motivo = 'no se ha comprobado: la ronda se paro antes'; continue }
    if ($guardado.ContainsKey($f)) { [System.IO.File]::WriteAllBytes((Join-Ruta $RepoRoot $f), $guardado[$f]) }
    Confirm-TestReglas $x (-not $solos)
    if ($x.Estado -ceq 'git') { $parar = $true }
  }
}

# Lo que dice que un test arranca el contexto de Spring (no es un test unitario), o ''.
function Get-SpringReglas([string]$Texto) {
  $m = [regex]::Match($Texto, '@(?:SpringBootTest|ContextConfiguration|SpringJUnitConfig|SpringBatchTest|WebMvcTest|DataJpaTest|JdbcTest)\b|\bSpringExtension\b')
  if ($m.Success) { return $m.Value }
  return ''
}

# Una ronda: una llamada por tarea de $Lote, todas a la vez, en el mismo worktree. Despues: lo que la IA haya hecho fuera de su test se deshace, el
# test que falta o que arranca Spring se rechaza y el resto se comprueba. Devuelve por tarea: Tarea, Estado (ok, invalida, fallo, tiempo o git), Motivo,
# Commit y Reglas (el resultado de cada regla, si se llego a los cambios).
function Invoke-RondaReglas($Lote) {
  $items = @()
  foreach ($t in $Lote) {
    $motivo = ''
    if ($t.intentos -gt 0 -and $t.ultimoEstado -eq 'invalida') { $motivo = $t.motivo }
    $items += , ([pscustomobject]@{ Id = $t.id; Dir = $RepoRoot; Modelo = $ModeloElegido; Esfuerzo = 'medium'; Dirs = @(); Prompt = (Get-Prompt $t '' $motivo) })
  }
  $head = Get-Head $RepoRoot
  $rama = Get-Rama $RepoRoot
  $llamadas = @(Invoke-Llamadas $items)
  $res = @()
  for ($i = 0; $i -lt $Lote.Count; $i++) {
    $c = $llamadas[$i]
    $cab = "# salida (codigo $($c.Codigo), $($c.Segundos) s"
    if ($c.Agotado) { $cab += ', tiempo agotado' }
    [System.IO.File]::WriteAllText((Join-Path $Registros ($Lote[$i].id + '-' + ($Lote[$i].intentos + 1) + '.log')), ("# prompt`n" + $items[$i].Prompt + "`n`n" + $cab + ")`n" + $c.Texto + "`n"), $Utf8)
    $r = [pscustomobject]@{ Tarea = $Lote[$i]; Estado = 'ok'; Motivo = ''; Commit = ''; Reglas = @() }
    if ($c.Agotado) { $r.Estado = 'tiempo'; $r.Motivo = "Tiempo agotado: la llamada pasaba de $($Cfg.SegundosPorLlamada) s y se mato." }
    elseif ($c.Codigo -ne 0) { $r.Estado = 'fallo'; $r.Motivo = "Copilot salio con codigo $($c.Codigo): " + (Get-UltimaLinea $c.Texto) }
    $res += , $r
  }
  if ((Get-Head $RepoRoot) -cne $head -or (Get-Rama $RepoRoot) -cne $rama) {
    Undo-Lote $rama $head
    foreach ($r in $res) { if ($r.Estado -eq 'ok') { $r.Estado = 'invalida'; $r.Motivo = 'Has hecho un commit en el repositorio. Solo escribes el test: el commit lo hace el script.' } }
  }
  # un 'git add' de la IA dejaria sus cambios en el indice, donde Get-Cambios no los ve
  [void](Invoke-Git $RepoRoot @('reset', '-q'))
  $ajenos = @(Remove-Ruido $RepoRoot @($Lote | ForEach-Object { $_.entradas.test }))
  if ($ajenos.Count -gt 0) { Info ('Deshago lo que la IA ha tocado fuera de lo suyo: ' + ($ajenos -join ', ')) }
  $cambios = @(Get-Cambios $RepoRoot)
  foreach ($r in $res) {
    $f = $r.Tarea.entradas.test
    if ($cambios -notcontains $f) {
      if ($r.Estado -eq 'ok') { $r.Estado = 'invalida'; $r.Motivo = "No has escrito el fichero $f. Escribe ahi el test." }
      continue
    }
    if ($r.Estado -ne 'ok') { Remove-TestReglas $f; continue }
    $spring = Get-SpringReglas ([System.IO.File]::ReadAllText((Join-Ruta $RepoRoot $f)))
    if ($spring) { Set-InvalidaReglas $r "Tu test arranca el contexto de Spring ($spring). Tiene que ser un test unitario sin Spring: crea las dependencias a mano o simulalas con Mockito." }
  }
  $cand = @($res | Where-Object { $_.Estado -eq 'ok' })
  if ($cand.Count -gt 0) { Confirm-CandidatosReglas $cand }
  foreach ($r in $res) { if (-not $r.Commit) { Remove-TestReglas $r.Tarea.entradas.test } }
  return $res
}

# ================================ FASE ================================
# datos\tests-reglas.json y la linea de consola con los numeros.
function Save-ResultadoReglas($Tareas) {
  $filas = @()
  foreach ($t in $Tareas) {
    $r = $t.resultado
    $estado = [string]$t.estado
    $commit = ''
    $motivo = [string]$t.motivo
    $reglas = @()
    if ($r) {
      $commit = [string]$r.commit
      $reglas = @($r.reglas)
      if ($r.motivo) { $motivo = [string]$r.motivo }
      if ($r.saltada) { $estado = 'saltada' }
    }
    $filas += , ([ordered]@{
        clase = [string]$t.entradas.clase; fichero = [string]$t.entradas.fichero; test = [string]$t.entradas.test; estado = $estado; commit = $commit; motivo = $motivo
        reglas = @($reglas | ForEach-Object { [ordered]@{ texto = [string]$_.texto; linea = [int]$_.linea; resultado = [string]$_.resultado; motivo = [string]$_.motivo } })
      })
  }
  $con = @($filas | Where-Object { $_.estado -ceq 'hecha' })
  $vigiladas = 0
  foreach ($f in $con) { $vigiladas += @($f.reglas | Where-Object { $_.resultado -ceq 'vigilada' }).Count }
  $atascadas = @($filas | Where-Object { $_.estado -ceq 'atascada' }).Count
  $saltadas = @($filas | Where-Object { $_.estado -ceq 'saltada' }).Count
  Write-Json (Join-Path $Datos 'tests-reglas.json') ([ordered]@{ version = 1; cuando = (Get-Date).ToString('s'); conTest = $con.Count; reglasVigiladas = $vigiladas; atascadas = $atascadas; saltadas = $saltadas; tareas = $filas })
  Info "Tests de reglas: $($con.Count) clases con test ($vigiladas reglas vigiladas), $atascadas atascadas, $saltadas saltadas"
}

# Toda la fase salvo el estado y el informe: devuelve Parada ('' o el motivo), Detalle, Registro y Tareas.
function Invoke-TestsReglas([bool]$Conservar) {
  $out = [pscustomobject]@{ Parada = ''; Detalle = ''; Registro = ''; Tareas = @() }
  if (-not (Test-Path -LiteralPath (Join-Path $Datos 'comparacion') -PathType Container)) { Aviso 'No hay datos/comparacion: no se sabe donde esta cada regla en el migrado.'; return $out }
  if ((Get-ReglasComparadas).Count -gt 0) {
    $sucio = @(Get-Cambios $RepoRoot)
    if ($sucio.Count -gt 0) {
      Info ('Deshago lo que habia sin confirmar en el worktree: ' + ($sucio -join ', '))
      Undo-Lote (Get-Rama $RepoRoot) (Get-Head $RepoRoot)
    }
  }
  $tareas = @(Get-TareasReglas $Conservar)
  $out.Tareas = $tareas
  if (@($tareas | Where-Object { $_.estado -eq 'pendiente' }).Count -gt 0) {
    $motivo = Invoke-CompilarReglas 'compilar el migrado antes de escribir los tests' 'reglas-previo.log'
    if ($motivo) { $out.Parada = 'no-compila'; $out.Detalle = "El migrado no compila antes de empezar: $motivo"; $out.Registro = Join-Path $Registros 'reglas-previo.log' }
  }
  $racha = 0
  $rondas = 0
  while (-not $out.Parada) {
    $pend = @($tareas | Where-Object { $_.estado -eq 'pendiente' })
    if ($pend.Count -eq 0) { break }
    if ($MaxHoras -gt 0 -and $rondas -gt 0 -and $reloj.Elapsed.TotalHours -ge $MaxHoras) {
      $out.Parada = 'tope-de-tiempo'; $out.Detalle = "Se ha llegado al tope de -MaxHoras $MaxHoras. Relanza el mismo comando para seguir."; $out.Registro = $Registros
      break
    }
    $lote = @($pend | Select-Object -First ([int]$Cfg.Paralelo))
    Info ('Ronda de tests de reglas: ' + $lote.Count + ' llamadas a la vez (quedan ' + $pend.Count + ' clases)...')
    $rondas++
    $res = @(Invoke-RondaReglas $lote)
    foreach ($o in $res) {
      if ($o.Estado -eq 'git') { continue }
      $t = $o.Tarea
      if ($o.Estado -in @('fallo', 'tiempo')) { $racha++ } else { $racha = 0 }
      $t.intentos++
      $t.motivo = $o.Motivo
      $t.ultimoEstado = $o.Estado
      if ($o.Estado -eq 'ok') {
        $t.estado = 'hecha'
        $t.resultado = [pscustomobject]@{ commit = $o.Commit; saltada = $false; motivo = ''; reglas = @($o.Reglas) }
      }
      elseif ($t.intentos -ge [int]$Cfg.Intentos) {
        $t.estado = 'atascada'
        $t.resultado = [pscustomobject]@{ commit = ''; saltada = $false; motivo = $o.Motivo; reglas = @($o.Reglas) }
        Aviso "Atascada: $($t.entradas.test): $($o.Motivo)"
      }
      Save-Tarea $t
    }
    $git = @($res | Where-Object { $_.Estado -eq 'git' })
    if ($git.Count -gt 0) {
      $out.Parada = 'git'; $out.Detalle = "git ha fallado con $($git[0].Tarea.entradas.test): $($git[0].Motivo)"; $out.Registro = $Registros
    }
    elseif ($racha -ge [int]$Cfg.FallosSeguidos) {
      # el fallo es de Copilot, no de las tareas: vuelven a empezar al relanzar
      foreach ($o in $res) {
        if ($o.Estado -in @('fallo', 'tiempo')) { $o.Tarea.estado = 'pendiente'; $o.Tarea.intentos = 0; Save-Tarea $o.Tarea }
      }
      $ultimo = @($res | Where-Object { $_.Estado -in @('fallo', 'tiempo') } | Select-Object -Last 1)[0]
      $out.Parada = 'copilot-no-responde'
      $out.Detalle = "$racha llamadas seguidas han fallado (sesion, cuota o red). Ultimo error: $($ultimo.Motivo)"
      $out.Registro = Join-Path $Registros ($ultimo.Tarea.id + '-' + ($ultimo.Tarea.intentos + 1) + '.log')
    }
  }
  if ($out.Tareas.Count -gt 0 -or -not $out.Parada) { Save-ResultadoReglas $tareas }
  return $out
}

# La fase 'reglas' de migracion.ps1: el estado, el informe y la parada alrededor de Invoke-TestsReglas. Devuelve si se puede seguir.
function Invoke-FaseReglas([bool]$Conservar) {
  $Estado['fase'] = 'reglas'
  Save-Estado
  Save-Informes
  $r = Invoke-TestsReglas $Conservar
  $script:Todas += @($r.Tareas)
  Save-Informes
  if ($r.Parada) {
    Set-Parada $r.Parada $r.Detalle $r.Registro
    $script:Parada = $true
    return $false
  }
  return $true
}
