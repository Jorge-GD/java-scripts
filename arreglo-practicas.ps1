<#
arreglo-practicas.ps1 - BP-4: pasar a Lombok los getters y setters escritos a mano (la fase 'practicas' de migracion.ps1, con -Practicas).
No se ejecuta solo: solo funciones. Se carga con '. (Join-Path $PSScriptRoot 'arreglo-practicas.ps1')' despues de comun.ps1, tareas.ps1, practicas.ps1
y huella.ps1. Usa las variables del script que lo carga ($RepoRoot, el worktree del migrado; $Datos, $Registros, $Cfg, $ModeloElegido y $Estado; y,
si estan, $MaxHoras y $reloj) y sus funciones Save-Estado, Save-Informes y Set-Parada. Solo ASCII. Vale para Windows PowerShell 5.1 y para PowerShell 7.

  Invoke-FasePracticas <conservar>   La fase. Devuelve $true si se puede seguir con lo que viene despues (no hay parada). Con $conservar, las tareas
                                     atascadas de un lanzamiento anterior no se repiten.

Que hace: una tarea por cada fichero con getters y setters escritos a mano (la incidencia getter-setter-a-mano del detector lombok-a-mano) de
datos\practicas-despues.json, si existe, o de datos\practicas-antes.json. La IA solo cambia ese fichero (tareas\practica-lombok.md). Como Lombok
genera lo que se quita, lo compilado tiene que quedar igual: antes de empezar se compila el migrado (mvn -B compile, sin clean) y se guarda una
copia de target\classes en .rescate\practicas\antes\ (una vez por HEAD de partida: el HEAD sin los commits 'practica(lombok): ...' de antes). Tras
cada ronda (hasta $Cfg.Paralelo ficheros a la vez, en el mismo worktree) se deshace lo que la IA haya tocado fuera de su fichero, se compila una vez
y se compara con la foto (Compare-Huella). Cada fichero cuyas clases (X.class y X$*.class) son iguales se commitea ('practica(lombok): <ruta>'); el
que no, se deja como estaba y vuelve a pendiente con el motivo (las partes de la huella que cambian); al segundo fallo queda atascado. Si la ronda
no compila, o la diferencia no es de ningun fichero suyo, se prueba cada fichero con su cambio solo. Un fichero que la IA no cambia queda hecho 'sin
cambios'. Sin getters ni setters a mano no hay llamadas. Sin Lombok en el pom, un aviso y nada mas. Deja datos\practicas-arreglos.json (por fichero:
estado, commit y motivo) y la linea 'Buenas practicas: N ficheros pasados a Lombok, M atascados, K sin cambios'. Paradas: no-compila (el migrado
no compila antes de empezar), git (un commit falla), copilot-no-responde, tope-de-tiempo (-MaxHoras) y otro (no hay javap).
#>

# ================================ DATOS ================================
# El asunto del commit de un fichero pasado a Lombok. Con '' es el comienzo que tienen todos (para reconocerlos).
function Get-AsuntoLombok([string]$Fichero) { return ('practica(lombok): ' + $Fichero) }

# Los ficheros con getters y setters a mano segun datos\practicas-despues.json (si existe) o datos\practicas-antes.json: ruta relativa -> texto de la
# primera incidencia del fichero, en el orden del JSON. $null si no hay ninguno de los dos JSON.
function Get-FicherosLombok {
  $json = ''
  foreach ($n in @('practicas-despues.json', 'practicas-antes.json')) {
    if (-not $json -and (Test-Path -LiteralPath (Join-Path $Datos $n) -PathType Leaf)) { $json = Join-Path $Datos $n }
  }
  if (-not $json) { return $null }
  $por = [ordered]@{}
  foreach ($i in @((Read-Json $json).incidencias | Where-Object { $_ -and $_.regla -ceq 'getter-setter-a-mano' })) {
    if (-not $por.Contains([string]$i.fichero)) { $por[[string]$i.fichero] = [string]$i.texto }
  }
  return $por
}

# El migrado usa Lombok: algun pom.xml suyo (el de la raiz o el de un modulo) lo declara como dependencia.
function Test-PomLombok {
  $pila = New-Object System.Collections.Generic.Stack[string]
  $pila.Push($RepoRoot)
  while ($pila.Count -gt 0) {
    $d = $pila.Pop()
    $pom = Join-Path $d 'pom.xml'
    if ((Test-Path -LiteralPath $pom -PathType Leaf) -and [System.IO.File]::ReadAllText($pom) -match '(?s)<groupId>\s*org\.projectlombok\s*</groupId>\s*<artifactId>\s*lombok\s*</artifactId>') { return $true }
    foreach ($s in @(Get-ChildItem -LiteralPath $d -Directory)) {
      if (@('.git', '.rescate', 'target', 'node_modules', 'src') -notcontains $s.Name) { $pila.Push($s.FullName) }
    }
  }
  return $false
}

# El HEAD de partida: el primer commit, yendo hacia atras desde HEAD, que no es de una pasada anterior de esta fase. Los commits 'practica(lombok): ...'
# de un lanzamiento anterior no lo cambian: ni el id de las tareas ni la foto dependen de ellos.
function Get-HeadPartida {
  foreach ($l in @((Invoke-Git $RepoRoot @('log', '-n', '1000', '--format=%H%x09%s')).Salida)) {
    $p = "$l" -split "`t", 2
    if ($p.Count -eq 2 -and $p[1] -cnotlike ((Get-AsuntoLombok '') + '*')) { return $p[0] }
  }
  return (Get-Head $RepoRoot)
}

# Las tareas: una por fichero, con su id (hash de la ruta y del contenido del fichero en el HEAD de partida; el commit de Lombok no lo cambia).
function Get-TareasLombok($Ficheros, [string]$Partida, [bool]$Conservar) {
  $tareas = @()
  foreach ($f in $Ficheros.Keys) {
    $blob = ((Invoke-Git $RepoRoot @('rev-parse', '--verify', '-q', ($Partida + ':' + $f))).Salida -join '').Trim()
    if ($blob -notmatch '^[0-9a-f]{40,64}$') { continue }
    $entradas = [pscustomobject]@{ fichero = $f; huella = $blob; prompt = [pscustomobject]@{ FICHERO = $f; DETALLE = $Ficheros[$f] } }
    $tareas += , (Restore-Tarea (New-TareaTipo 'practica-lombok' ('lombok-' + (Get-Hash8 ($f + '|' + $blob))) '' '' $entradas) $Conservar)
  }
  return $tareas
}

# ============================== COMPILAR Y COMPARAR ==============================
function Get-DirFotoLombok { return (Join-Path (Join-Path (Join-Path $RepoRoot '.rescate') 'practicas') 'antes') }

# mvn -B compile (sin clean) en el worktree. Lo que Maven deje fuera de target no es de la IA y se quita. Devuelve '' si compila; si no, por que
# (sus primeras lineas [ERROR] o el tope de tiempo).
function Invoke-CompilarLombok([string]$Que, [string]$Registro) {
  $previos = @(Get-Cambios $RepoRoot)
  $m = Invoke-MavenTope $RepoRoot @('-B', 'compile') $Que (Join-Path $Registros $Registro)
  [void](Remove-Ruido $RepoRoot $previos)
  if ($m.Tope) { return $m.Tope }
  if ($m.Codigo -eq 0) { return '' }
  $err = @($m.Salida | Where-Object { $_ -match '^\[ERROR\]' } | Select-Object -First 3 | ForEach-Object { $_ -replace '^\[ERROR\]\s*', '' })
  if ($err.Count -eq 0) { $err = @(Get-UltimaLinea ($m.Salida -join "`n")) }
  return ('No compila: ' + ($err -join ' / '))
}

# La foto de lo compilado antes de tocar nada. Si ya es la de este HEAD de partida (partida.txt), se deja. Devuelve '' si hay foto; si no, por que no.
function Save-FotoLombok([string]$Partida) {
  $marca = Join-Path (Join-Path (Join-Path $RepoRoot '.rescate') 'practicas') 'partida.txt'
  $antes = Get-DirFotoLombok
  if ((Test-Path -LiteralPath $antes -PathType Container) -and (Test-Path -LiteralPath $marca) -and ([System.IO.File]::ReadAllText($marca).Trim() -ceq $Partida)) { return '' }
  $motivo = Invoke-CompilarLombok 'compilar el migrado antes de pasar a Lombok (foto de lo compilado)' 'practicas-foto.log'
  if ($motivo) { return $motivo }
  $clases = Join-Path (Join-Path $RepoRoot 'target') 'classes'
  if (-not (Test-Path -LiteralPath $clases -PathType Container)) { return 'Maven no ha dejado target/classes' }
  if (Test-Path -LiteralPath $antes) { Remove-Item -LiteralPath $antes -Recurse -Force }
  [void](New-Item -ItemType Directory -Path $antes -Force)
  Copy-Item -Path (Join-Path $clases '*') -Destination $antes -Recurse -Force
  [System.IO.File]::WriteAllText($marca, $Partida + "`n", $Utf8)
  return ''
}

# Si la clase compilada $Clase (ruta relativa de un .class en target/classes) es de $Fichero: X.class y X$*.class son de .../src/main/java/.../X.java.
function Test-ClaseDeFichero([string]$Clase, [string]$Fichero) {
  $m = [regex]::Match($Fichero, '(^|/)src/main/java/(?<c>.+)\.java$')
  if (-not $m.Success) { return $false }
  $base = $m.Groups['c'].Value
  if ($Clase -ceq ($base + '.class')) { return $true }
  return ($Clase.StartsWith(($base + '$'), [System.StringComparison]::Ordinal) -and $Clase.EndsWith('.class', [System.StringComparison]::Ordinal))
}

# Compila el worktree y lo compara con la foto: Motivo ('' si compila) y Diferencias (vacias si lo compilado es igual).
function Test-CompiladoLombok([string]$Registro) {
  $v = [pscustomobject]@{ Motivo = (Invoke-CompilarLombok 'compilar el migrado para comprobar lo compilado' $Registro); Diferencias = @() }
  if ($v.Motivo) { return $v }
  $c = Compare-Huella (Get-DirFotoLombok) (Join-Path (Join-Path $RepoRoot 'target') 'classes') (Get-JavapExe)
  $v.Diferencias = @($c.Diferencias)
  return $v
}

# El motivo, para el prompt del reintento, de un fichero cuyo compilado ya no es igual: por clase, las partes de la huella que cambian.
function Get-MotivoHuella($Diferencias) {
  $t = 'Lo compilado ya no es igual al de antes de tu cambio. Pasar a Lombok no puede cambiar lo que hace el programa. Diferencias: ' + ((@($Diferencias) | ForEach-Object { "$($_.Clase) ($(@($_.Partes) -join '; '))" }) -join ' | ')
  if ($t.Length -gt 800) { $t = $t.Substring(0, 800) + '...' }
  return $t
}

# ================================ RONDAS ================================
# Deja un fichero como esta en el HEAD.
function Undo-FicheroLombok([string]$Fichero) { [void](Invoke-Git $RepoRoot @('checkout', '-q', '--', $Fichero)) }

# Commit de un fichero ya comprobado. Si git lo rechaza, el fichero vuelve a como estaba y el resultado queda en 'git'.
function Save-CommitLombok($R) {
  $f = $R.Tarea.entradas.fichero
  $c = Invoke-Git $RepoRoot (@('commit', '-q') + @($Cfg.CommitArgs) + @('-m', (Get-AsuntoLombok $f), '--', $f))
  if ($c.Codigo -eq 0) { $R.Commit = Get-Head $RepoRoot; return }
  Undo-FicheroLombok $f
  $R.Estado = 'git'
  $R.Motivo = (@($c.Salida) -join ' / ')
}

# Un fichero con su cambio solo en el worktree: compila, compara y lo commitea, o lo deja como estaba con su motivo.
function Confirm-FicheroLombok($R) {
  $f = $R.Tarea.entradas.fichero
  $v = Test-CompiladoLombok ('practicas-' + $R.Tarea.id + '.log')
  if ($v.Motivo -or $v.Diferencias.Count -gt 0) {
    Undo-FicheroLombok $f
    $R.Estado = 'invalida'
    $R.Motivo = $v.Motivo
    if (-not $R.Motivo) { $R.Motivo = Get-MotivoHuella $v.Diferencias }
    Info "Vuelve atras $f`: $($R.Motivo)"
    return
  }
  Save-CommitLombok $R
}

# La ronda entera, con los cambios de todos sus ficheros puestos: una compilacion y una comparacion. Los ficheros cuyas clases son iguales se
# commitean; los que no, vuelven atras con su motivo. Devuelve $false, sin tocar nada, si no se puede dar por buena en bloque: no compila o hay
# diferencias que no son de ningun fichero de la ronda.
function Confirm-RondaLombok($Cand) {
  $v = Test-CompiladoLombok 'practicas-ronda.log'
  $sueltas = @()
  if (-not $v.Motivo) {
    foreach ($d in $v.Diferencias) {
      $dueno = @($Cand | Where-Object { Test-ClaseDeFichero $d.Clase $_.Tarea.entradas.fichero })
      if ($dueno.Count -eq 0) { $sueltas += , $d } else { $dueno[0].Dif += , $d }
    }
  }
  if ($v.Motivo -or $sueltas.Count -gt 0) {
    $que = $v.Motivo
    if (-not $que) { $que = 'hay diferencias en clases que no son de ningun fichero de la ronda: ' + ((@($sueltas | ForEach-Object { "$($_.Clase) ($(@($_.Partes) -join '; '))" })) -join ' | ') }
    Info "La ronda no se puede dar por buena en bloque ($que): pruebo los ficheros de uno en uno."
    return $false
  }
  foreach ($c in $Cand) {
    $f = $c.Tarea.entradas.fichero
    if ($c.Dif.Count -eq 0) { Save-CommitLombok $c; continue }
    Undo-FicheroLombok $f
    $c.Estado = 'invalida'
    $c.Motivo = Get-MotivoHuella $c.Dif
    Info "Vuelve atras $f`: $($c.Motivo)"
  }
  return $true
}

# Da por bueno, o no, el cambio de cada fichero de $Cand (los de la ronda que la IA ha cambiado bien). Uno solo se comprueba directamente; varios, en
# bloque, y si no se puede, deshaciendo la ronda y poniendo el cambio de cada uno por separado.
function Confirm-CandidatosLombok($Cand) {
  if ($Cand.Count -eq 1) { Confirm-FicheroLombok $Cand[0]; return }
  if (Confirm-RondaLombok $Cand) { return }
  $guardado = @{}
  foreach ($c in $Cand) { $guardado[$c.Tarea.entradas.fichero] = [System.IO.File]::ReadAllBytes((Join-Ruta $RepoRoot $c.Tarea.entradas.fichero)) }
  foreach ($c in $Cand) { Undo-FicheroLombok $c.Tarea.entradas.fichero }
  foreach ($c in $Cand) {
    $f = $c.Tarea.entradas.fichero
    [System.IO.File]::WriteAllBytes((Join-Ruta $RepoRoot $f), $guardado[$f])
    Confirm-FicheroLombok $c
  }
}

# Una ronda: una llamada por tarea de $Lote, todas a la vez, en el mismo worktree. Despues: lo que la IA haya hecho fuera de su fichero se deshace,
# lo que no ha cambiado queda 'sin cambios' y el resto se comprueba. Devuelve por tarea: Tarea, Estado (ok, sin-cambios, invalida, fallo, tiempo o
# git), Motivo y Commit.
function Invoke-RondaLombok($Lote) {
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
    $r = [pscustomobject]@{ Tarea = $Lote[$i]; Estado = 'ok'; Motivo = ''; Commit = ''; Dif = @() }
    if ($c.Agotado) { $r.Estado = 'tiempo'; $r.Motivo = "Tiempo agotado: la llamada pasaba de $($Cfg.SegundosPorLlamada) s y se mato." }
    elseif ($c.Codigo -ne 0) { $r.Estado = 'fallo'; $r.Motivo = "Copilot salio con codigo $($c.Codigo): " + (Get-UltimaLinea $c.Texto) }
    $res += , $r
  }
  if ((Get-Head $RepoRoot) -cne $head -or (Get-Rama $RepoRoot) -cne $rama) {
    Undo-Lote $rama $head
    foreach ($r in $res) { if ($r.Estado -eq 'ok') { $r.Estado = 'invalida'; $r.Motivo = 'Has hecho un commit en el repositorio. Solo cambias el fichero: el commit lo hace el script.' } }
  }
  # un 'git add' de la IA dejaria sus cambios en el indice, donde Get-Cambios no los ve
  [void](Invoke-Git $RepoRoot @('reset', '-q'))
  $ajenos = @(Remove-Ruido $RepoRoot @($Lote | ForEach-Object { $_.entradas.fichero }))
  if ($ajenos.Count -gt 0) { Info ('Deshago lo que la IA ha tocado fuera de lo suyo: ' + ($ajenos -join ', ')) }
  $cambios = @(Get-Cambios $RepoRoot)
  foreach ($r in $res) {
    $f = $r.Tarea.entradas.fichero
    if ($cambios -notcontains $f) {
      if ($r.Estado -eq 'ok') { $r.Estado = 'sin-cambios'; $r.Motivo = 'sin cambios' }
      continue
    }
    if ($r.Estado -ne 'ok') { Undo-FicheroLombok $f; continue }
    if (-not (Test-Path -LiteralPath (Join-Ruta $RepoRoot $f) -PathType Leaf)) {
      Undo-FicheroLombok $f
      $r.Estado = 'invalida'
      $r.Motivo = 'Has borrado el fichero. Solo cambias su contenido.'
    }
  }
  $cand = @($res | Where-Object { $_.Estado -eq 'ok' })
  if ($cand.Count -gt 0) { Confirm-CandidatosLombok $cand }
  return $res
}

# ================================ FASE ================================
# datos\practicas-arreglos.json y la linea de consola con los numeros.
function Save-ResultadoLombok($Tareas) {
  $filas = @()
  foreach ($t in $Tareas) {
    $commit = ''
    $motivo = [string]$t.motivo
    if ($t.estado -eq 'hecha') {
      $commit = [string]$t.resultado.commit
      if ($t.resultado.sinCambios) { $motivo = 'sin cambios' }
    }
    $filas += , ([ordered]@{ fichero = $t.entradas.fichero; estado = $t.estado; commit = $commit; motivo = $motivo })
  }
  $pasados = @($Tareas | Where-Object { $_.estado -eq 'hecha' -and -not $_.resultado.sinCambios }).Count
  $atascados = @($Tareas | Where-Object { $_.estado -eq 'atascada' }).Count
  $sin = @($Tareas | Where-Object { $_.estado -eq 'hecha' -and $_.resultado.sinCambios }).Count
  Write-Json (Join-Path $Datos 'practicas-arreglos.json') ([ordered]@{ version = 1; cuando = (Get-Date).ToString('s'); pasados = $pasados; atascados = $atascados; sinCambios = $sin; tareas = $filas })
  Info "Buenas practicas: $pasados ficheros pasados a Lombok, $atascados atascados, $sin sin cambios"
}

# Toda la fase salvo el estado y el informe: devuelve Parada ('' o el motivo), Detalle, Registro y Tareas.
function Invoke-PracticasLombok([bool]$Conservar) {
  $out = [pscustomobject]@{ Parada = ''; Detalle = ''; Registro = ''; Tareas = @() }
  $ficheros = Get-FicherosLombok
  if ($null -eq $ficheros) { Aviso 'No hay datos/practicas-antes.json: no se sabe que ficheros pasar a Lombok.'; return $out }
  if ($ficheros.Count -gt 0 -and -not (Test-PomLombok)) { Aviso 'El migrado no usa Lombok: anadelo al pom.xml y vuelve a lanzar'; return $out }
  if ($ficheros.Count -gt 0) {
    try { [void](Get-JavapExe) }
    catch { $out.Parada = 'otro'; $out.Detalle = 'No se puede comparar lo compilado: ' + $_.Exception.Message; $out.Registro = $Registros; return $out }
    $mal = Move-SinCommitAStash 'practicas: cambios sin commit de antes'
    if ($mal) { $out.Parada = 'git'; $out.Detalle = "No he podido apartar con git stash lo que habia sin confirmar en el worktree: $mal"; $out.Registro = $Registros; return $out }
  }
  $partida = Get-HeadPartida
  $tareas = @(Get-TareasLombok $ficheros $partida $Conservar)
  $out.Tareas = $tareas
  if (@($tareas | Where-Object { $_.estado -eq 'pendiente' }).Count -gt 0) {
    $motivo = Save-FotoLombok $partida
    if ($motivo) { $out.Parada = 'no-compila'; $out.Detalle = "El migrado no compila antes de empezar: $motivo"; $out.Registro = Join-Path $Registros 'practicas-foto.log' }
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
    Info ('Ronda de buenas practicas: ' + $lote.Count + ' llamadas a la vez (quedan ' + $pend.Count + ' ficheros)...')
    $rondas++
    $res = @(Invoke-RondaLombok $lote)
    foreach ($o in $res) {
      if ($o.Estado -eq 'git') { continue }
      $t = $o.Tarea
      if ($o.Estado -in @('fallo', 'tiempo')) { $racha++ } else { $racha = 0 }
      $t.intentos++
      $t.motivo = $o.Motivo
      $t.ultimoEstado = $o.Estado
      if ($o.Estado -in @('ok', 'sin-cambios')) {
        $t.estado = 'hecha'
        $t.ultimoEstado = 'ok'
        $t.resultado = [pscustomobject]@{ commit = $o.Commit; sinCambios = ($o.Estado -eq 'sin-cambios') }
      }
      elseif ($t.intentos -ge [int]$Cfg.Intentos) {
        $t.estado = 'atascada'
        Aviso "Atascada: $($t.entradas.fichero): $($o.Motivo)"
      }
      Save-Tarea $t
    }
    $git = @($res | Where-Object { $_.Estado -eq 'git' })
    if ($git.Count -gt 0) {
      $out.Parada = 'git'; $out.Detalle = "git commit ha fallado en $($git[0].Tarea.entradas.fichero): $($git[0].Motivo)"; $out.Registro = $Registros
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
  if ($out.Tareas.Count -gt 0 -or -not $out.Parada) { Save-ResultadoLombok $tareas }
  return $out
}

# La fase 'practicas' de migracion.ps1: el estado, el informe y la parada alrededor de Invoke-PracticasLombok. Devuelve si se puede seguir.
function Invoke-FasePracticas([bool]$Conservar) {
  $Estado['fase'] = 'practicas'
  Save-Estado
  Save-Informes
  $r = Invoke-PracticasLombok $Conservar
  $script:Todas += @($r.Tareas)
  Save-Informes
  if ($r.Parada) {
    Set-Parada $r.Parada $r.Detalle $r.Registro
    $script:Parada = $true
    return $false
  }
  return $true
}
