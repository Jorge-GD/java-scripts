<#
tareas.ps1 - Las piezas de migracion.ps1 que no son el arranque: las llamadas a Copilot
en paralelo, la ficha de clase y su comprobacion, las tareas y la prueba de aptitud.
Se carga con '. (Join-Path $PSScriptRoot 'tareas.ps1')' despues de comun.ps1, desde
migracion.ps1 o desde cualquier script que necesite lo mismo (un preflight) sin pasar
por el arranque. Cargarlo no ejecuta nada. Solo ASCII a proposito.
Necesita la carpeta tareas\ (plantilla del prompt y fichero de la prueba) junto a este script.

DEFINE al cargarse: $Utf8 y las funciones de abajo.

ESPERA que quien lo carga haya puesto, antes de llamar a sus funciones:
  $Cfg            el de comun.ps1 mas estas claves: Paralelo, SegundosPorLlamada, Intentos,
                  LineasPorTarea, CitaMax, CitaCerca, EsfuerzoLectura, EsfuerzoReintento,
                  Papeles y TiposDato (sus valores estan en CONFIGURACION de migracion.ps1)
  $LegacyRoot     carpeta del batch original: Invoke-Llamadas se la da a Copilot (--add-dir)
                  y Get-TareasFichas saca de ahi las rutas relativas
  $Registros      carpeta de registros: Invoke-Ronda y Test-Aptitud escriben ahi
  $ModeloElegido  id del modelo ('' = el que tenga Copilot): Invoke-Ronda
  $Datos          carpeta datos\: Save-Tarea, Get-TareasFichas y Save-Fichas
Test-Aptitud solo usa $Cfg, $LegacyRoot, $Registros y $ModeloElegido.
Stop-Arranque termina el script que lo llame con la salida 1.
#>

# ============================== UTILIDADES ==============================
$Utf8 = New-Object System.Text.UTF8Encoding($false)

function Stop-Arranque([string]$Mensaje) { Fallo $Mensaje; exit 1 }

function Read-Json([string]$Ruta) { return ([System.IO.File]::ReadAllText($Ruta, $Utf8) | ConvertFrom-Json) }

# Escribe a un fichero temporal y lo mueve: un corte no deja un JSON a medias.
function Write-Json([string]$Ruta, $Objeto) {
  $d = Split-Path $Ruta -Parent
  if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -Force) }
  [System.IO.File]::WriteAllText(($Ruta + '.tmp'), (ConvertTo-Json -InputObject $Objeto -Depth 8), $Utf8)
  Move-Item -LiteralPath ($Ruta + '.tmp') -Destination $Ruta -Force
}

function Get-Hash8([string]$Texto) {
  $sha = [System.Security.Cryptography.SHA1]::Create()
  try { $b = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Texto)) } finally { $sha.Dispose() }
  return ((@($b[0..3]) | ForEach-Object { $_.ToString('x2') }) -join '')
}

# ================================ LLAMADAS ================================
# Comillas para la linea de comandos de Windows (valen tambien en Linux). Para cmd, ademas,
# se entrecomilla lo que lleve & | < > ^ ( ), que cmd leeria como suyo.
function ConvertTo-ArgWin([string]$A, [bool]$ParaCmd = $false) {
  $raro = '[\s"]'
  if ($ParaCmd) { $raro = '[\s"&|<>^()]' }
  if ($A -ne '' -and $A -notmatch $raro) { return $A }
  $s = $A -replace '(\\*)"', '$1$1\"'
  $s = $s -replace '(\\+)$', '$1$1'
  return '"' + $s + '"'
}

function Get-PowerShellExe {
  $e = (Get-Process -Id $PID).Path
  if ([System.IO.Path]::GetFileNameWithoutExtension($e) -notmatch '^(pwsh|powershell)') {
    $e = (@(Get-Command pwsh, powershell -ErrorAction SilentlyContinue)[0]).Source
  }
  return $e
}

# Que programa y que argumentos lanzar: un .ps1 va por PowerShell, un .cmd por cmd.
function Get-Lanzador([string]$Exe, [string[]]$A) {
  $ruta = @(Get-Command $Exe)[0].Source
  $ext = [System.IO.Path]::GetExtension($ruta).ToLowerInvariant()
  if ($ext -eq '.ps1') {
    return [pscustomobject]@{ Exe = (Get-PowerShellExe); Args = (((@('-NoProfile', '-File', $ruta) + $A) | ForEach-Object { ConvertTo-ArgWin $_ }) -join ' ') }
  }
  if ($ext -eq '.cmd' -or $ext -eq '.bat') {
    return [pscustomobject]@{ Exe = $env:ComSpec; Args = ('/d /s /c "' + ((@($ruta) + $A | ForEach-Object { ConvertTo-ArgWin $_ $true }) -join ' ') + '"') }
  }
  return [pscustomobject]@{ Exe = $ruta; Args = (($A | ForEach-Object { ConvertTo-ArgWin $_ }) -join ' ') }
}

function Stop-Proceso($P) {
  try {
    if ($env:OS -eq 'Windows_NT') { [void](Invoke-Nativo 'taskkill' @('/F', '/T', '/PID', "$($P.Id)")) }
    else { $P.Kill() }
  }
  catch { }
}

# Lo que ha escrito una tuberia; si un nieto la mantiene abierta no espera para siempre.
function Get-TextoPipe($Tarea) {
  if ($Tarea.Wait(3000)) { return $Tarea.Result }
  return ''
}

function Start-Llamada([string]$Dir, [string[]]$A) {
  $v = [pscustomobject]@{ Proceso = $null; Salida = $null; Error = $null; Reloj = [System.Diagnostics.Stopwatch]::StartNew(); Fin = $false; Agotado = $false; Codigo = -1; Texto = ''; Segundos = 0 }
  try {
    $l = Get-Lanzador $Cfg.CopilotExe $A
    $pi = New-Object System.Diagnostics.ProcessStartInfo
    $pi.FileName = $l.Exe
    $pi.Arguments = $l.Args
    $pi.WorkingDirectory = $Dir
    $pi.UseShellExecute = $false
    $pi.CreateNoWindow = $true
    $pi.RedirectStandardInput = $true
    $pi.RedirectStandardOutput = $true
    $pi.RedirectStandardError = $true
    $pi.StandardOutputEncoding = $Utf8
    $pi.StandardErrorEncoding = $Utf8
    $v.Proceso = [System.Diagnostics.Process]::Start($pi)
    $v.Proceso.StandardInput.Close()
    $v.Salida = $v.Proceso.StandardOutput.ReadToEndAsync()
    $v.Error = $v.Proceso.StandardError.ReadToEndAsync()
  }
  catch { $v.Fin = $true; $v.Texto = "No pude lanzar Copilot: $($_.Exception.Message)" }
  return $v
}

# Una llamada por elemento de $Lote (Id, Dir, Prompt, Modelo, Esfuerzo), todas a la vez.
# Escribe el prompt, lanza, espera (matando las que pasan del tope) y devuelve, en el
# mismo orden: Codigo, Texto (lo que ha escrito), Agotado y Segundos.
function Invoke-Llamadas($Lote) {
  $vivos = @()
  foreach ($it in $Lote) {
    $carpeta = Join-Path (Join-Path $it.Dir '.rescate') 'tareas'
    if (-not (Test-Path -LiteralPath $carpeta)) { [void](New-Item -ItemType Directory -Path $carpeta -Force) }
    [System.IO.File]::WriteAllText((Join-Path $carpeta ($it.Id + '.prompt.md')), $it.Prompt, $Utf8)
    $salida = Join-Path $carpeta ($it.Id + '.json')
    if (Test-Path -LiteralPath $salida) { Remove-Item -LiteralPath $salida -Force }
    $texto = "Lee el fichero .rescate/tareas/$($it.Id).prompt.md y sigue sus instrucciones al pie de la letra."
    $vivos += , (Start-Llamada $it.Dir (Get-ArgsCopilot $texto $it.Modelo $it.Esfuerzo @($LegacyRoot) $true))
  }
  while (@($vivos | Where-Object { -not $_.Fin }).Count -gt 0) {
    foreach ($v in $vivos) {
      if ($v.Fin) { continue }
      if ($v.Proceso.HasExited) {
        $v.Proceso.WaitForExit()
        $v.Codigo = $v.Proceso.ExitCode
        $v.Texto = (Get-TextoPipe $v.Salida) + (Get-TextoPipe $v.Error)
        $v.Fin = $true
      }
      elseif ($v.Reloj.Elapsed.TotalSeconds -gt [int]$Cfg.SegundosPorLlamada) {
        Stop-Proceso $v.Proceso
        [void]$v.Proceso.WaitForExit(5000)
        $v.Agotado = $true
        $v.Texto = (Get-TextoPipe $v.Salida) + (Get-TextoPipe $v.Error)
        $v.Fin = $true
      }
    }
    Start-Sleep -Milliseconds 100
  }
  foreach ($v in $vivos) { $v.Segundos = [int]$v.Reloj.Elapsed.TotalSeconds }
  return $vivos
}

# ============================ FICHA DE CLASE ============================
function Get-PlantillaFicha {
  if (-not $script:PlantillaFicha) {
    $ruta = Join-Ruta $PSScriptRoot 'tareas/ficha-clase.md'
    if (-not (Test-Path -LiteralPath $ruta)) { Stop-Arranque "Falta la plantilla del prompt: $ruta" }
    $script:PlantillaFicha = [System.IO.File]::ReadAllText($ruta, $Utf8) -replace "`r`n", "`n"
  }
  return $script:PlantillaFicha
}

# El prompt de una tarea. Con $Motivo (reintento) lleva ademas la seccion de correccion.
function Get-PromptFicha($T, [string]$Leer, [string]$Motivo) {
  $partes = (Get-PlantillaFicha) -split '<!--CORRECCION-->\n', 2
  $p = $partes[0]
  if ($Motivo) { $p += $partes[1].Replace('{{MOTIVO}}', $Motivo) }
  $rango = "$($T.entradas.desde)-$($T.entradas.hasta)"
  return $p.Replace('{{FICHERO}}', $Leer).Replace('{{LINEAS}}', $rango).Replace('{{SALIDA}}', ".rescate/tareas/$($T.id).json").Replace('{{RELATIVO}}', $T.entradas.fichero).Replace('{{PAPELES}}', ($Cfg.Papeles -join ', ')).Replace('{{TIPOS}}', ($Cfg.TiposDato -join ', ')).Replace('{{CITA_MAX}}', "$($Cfg.CitaMax)")
}

# El fichero sin espacios, y donde empieza cada linea dentro de ese texto.
function Get-IndiceCitas([string]$Ruta) {
  try { $lineas = [System.IO.File]::ReadAllLines($Ruta, (New-Object System.Text.UTF8Encoding($false, $true))) }
  catch { $lineas = [System.IO.File]::ReadAllLines($Ruta, [System.Text.Encoding]::GetEncoding(28591)) }
  $partes = New-Object System.Collections.Generic.List[string]
  $inicios = New-Object System.Collections.Generic.List[int]
  $n = 0
  foreach ($l in $lineas) {
    $s = $l -replace '\s', ''
    $inicios.Add($n)
    $partes.Add($s)
    $n += $s.Length
  }
  return [pscustomobject]@{ Texto = ([string]::Join('', $partes)); Inicios = $inicios.ToArray() }
}

# Lineas (desde 1) donde sale la cita, sin contar espacios. Vacio si no sale.
function Find-Cita($Indice, [string]$Cita) {
  $c = $Cita -replace '\s', ''
  $lineas = New-Object System.Collections.Generic.List[int]
  $pos = $Indice.Texto.IndexOf($c, [System.StringComparison]::Ordinal)
  while ($pos -ge 0 -and $lineas.Count -lt 50) {
    $i = 0
    while (($i + 1) -lt $Indice.Inicios.Count -and $Indice.Inicios[$i + 1] -le $pos) { $i++ }
    $lineas.Add($i + 1)
    $pos = $Indice.Texto.IndexOf($c, $pos + 1, [System.StringComparison]::Ordinal)
  }
  return $lineas.ToArray()
}

function Test-Texto($V) { return (($V -is [string]) -and ($V.Trim().Length -gt 0)) }

function Test-Entero($V) {
  return ((($V -is [int]) -or ($V -is [long]) -or ((($V -is [double]) -or ($V -is [decimal])) -and ($V -eq [math]::Floor($V)))) -and ($V -ge 1))
}

function New-Resultado([bool]$Ok, [string]$Motivo, $Ficha) {
  return [pscustomobject]@{ Ok = $Ok; Motivo = $Motivo; Ficha = $Ficha }
}

# Comprueba lo que ha escrito Copilot: JSON, campos, vocabularios y citas.
# Si vale, devuelve la ficha con 'probado' en cada dato y la linea corregida.
function Test-Ficha($T, [string]$Dir, [string]$Leer) {
  $ruta = Join-Ruta $Dir ".rescate/tareas/$($T.id).json"
  if (-not (Test-Path -LiteralPath $ruta)) { return (New-Resultado $false "No has escrito el fichero de salida .rescate/tareas/$($T.id).json. Escribe ahi el JSON." $null) }
  try { $o = Read-Json $ruta } catch { return (New-Resultado $false ('El JSON no es valido: ' + $_.Exception.Message) $null) }
  if ($o -isnot [System.Management.Automation.PSCustomObject]) { return (New-Resultado $false 'El JSON no es valido: tiene que ser un objeto { ... }.' $null) }
  foreach ($c in @('clase', 'papel', 'queHace')) {
    if (-not (Test-Texto $o.$c)) { return (New-Resultado $false "Falta el campo '$c' (o esta vacio)." $null) }
  }
  if ($Cfg.Papeles -cnotcontains $o.papel) { return (New-Resultado $false ("El campo 'papel' vale '$($o.papel)' y tiene que ser uno de: " + ($Cfg.Papeles -join ', ') + '.') $null) }
  if ($o.datos -isnot [array]) { return (New-Resultado $false "Falta el campo 'datos': una lista, vacia si no hay nada que contar." $null) }
  $lista = @()
  $i = 0
  foreach ($d in $o.datos) {
    $pre = "datos[$i]"
    if ($d -isnot [System.Management.Automation.PSCustomObject]) { return (New-Resultado $false "$pre tiene que ser un objeto con tipo, texto, linea y cita." $null) }
    if ($Cfg.TiposDato -cnotcontains $d.tipo) { return (New-Resultado $false ("$pre.tipo vale '$($d.tipo)' y tiene que ser uno de: " + ($Cfg.TiposDato -join ', ') + '.') $null) }
    if (-not (Test-Texto $d.texto)) { return (New-Resultado $false "$pre.texto falta o esta vacio." $null) }
    if (-not (Test-Entero $d.linea)) { return (New-Resultado $false "$pre.linea tiene que ser un numero entero desde 1." $null) }
    if (-not (Test-Texto $d.cita) -or (($d.cita -replace '\s', '') -eq '')) { return (New-Resultado $false "$pre.cita falta o esta vacia." $null) }
    if ($d.cita.Length -gt [int]$Cfg.CitaMax) { return (New-Resultado $false "$pre.cita pasa de $($Cfg.CitaMax) caracteres: copia solo un trozo corto." $null) }
    $lista += [ordered]@{ tipo = $d.tipo; texto = $d.texto; linea = [int]$d.linea; cita = $d.cita; probado = $false }
    $i++
  }
  $indice = Get-IndiceCitas $Leer
  $inventadas = @()
  foreach ($d in $lista) {
    $donde = @(Find-Cita $indice $d.cita)
    if ($donde.Count -eq 0) { $inventadas += $d.cita; continue }
    $cerca = @($donde | Where-Object { [math]::Abs($_ - $d.linea) -le [int]$Cfg.CitaCerca })
    if ($cerca.Count -eq 0) { $d.linea = [int](@($donde | Sort-Object { [math]::Abs($_ - $d.linea) })[0]) }
    $d.probado = $true
  }
  if (($inventadas.Count * 2) -gt $lista.Count) {
    return (New-Resultado $false ("Mas de la mitad de las citas ($($inventadas.Count) de $($lista.Count)) no salen en el fichero, por ejemplo: '$($inventadas[0])'. Copia las citas tal cual del codigo y no inventes ninguna.") $null)
  }
  $ficha = [ordered]@{ fichero = $T.entradas.fichero; clase = $o.clase; papel = $o.papel; queHace = $o.queHace; datos = $lista }
  return (New-Resultado $true '' $ficha)
}

# ================================ TAREAS ================================
function New-Tarea([string]$Id, [string]$Ficha, [string]$Rel, [int]$Desde, [int]$Hasta) {
  return [pscustomobject]@{
    id = $Id; ficha = $Ficha; tipo = 'ficha-clase'; salida = "datos/fichas/$Ficha.json"; estado = 'pendiente'; intentos = 0; ultimoEstado = ''; motivo = ''
    entradas = [pscustomobject]@{ fichero = $Rel; desde = $Desde; hasta = $Hasta }; resultado = $null
  }
}

function Save-Tarea($T) { Write-Json (Join-Path (Join-Path $Datos 'tareas') ($T.id + '.json')) $T }

# Los .java que se leen del original: los de cada src/main/java (de cualquier modulo y a
# cualquier profundidad, sin entrar en .git, target ni node_modules). Si no hay ninguno,
# todos los que no esten bajo src/test, target ni .git.
function Get-JavaOriginal([string]$Raiz) {
  $principales = @()
  $otros = @()
  $saltar = @('.git', 'target', 'node_modules')
  $pila = New-Object System.Collections.Generic.Stack[object]
  $pila.Push([pscustomobject]@{ Ruta = $Raiz; Rel = ''; EnMain = $false })
  while ($pila.Count -gt 0) {
    $d = $pila.Pop()
    $java = @(Get-ChildItem -LiteralPath $d.Ruta -File -Filter '*.java')
    if ($d.EnMain) { $principales += $java } else { $otros += $java }
    foreach ($s in @(Get-ChildItem -LiteralPath $d.Ruta -Directory)) {
      if (-not $d.EnMain -and ($saltar -contains $s.Name)) { continue }
      $rel = $s.Name
      if ($d.Rel) { $rel = $d.Rel + '/' + $s.Name }
      $main = ($d.EnMain -or $rel -eq 'src/main/java' -or $rel.EndsWith('/src/main/java'))
      if (-not $main -and ($rel -eq 'src/test' -or $rel.EndsWith('/src/test'))) { continue }
      $pila.Push([pscustomobject]@{ Ruta = $s.FullName; Rel = $rel; EnMain = $main })
    }
  }
  if ($principales.Count -gt 0) { return $principales }
  return $otros
}

# Una ficha de clase por fichero de $Ficheros (troceada si pasa de LineasPorTarea).
# Las tareas hechas de un lanzamiento anterior se conservan tal cual, y tambien las atascadas
# con $ConservarAtascadas; el resto empieza de cero.
function Get-TareasFichas($Ficheros, [bool]$ConservarAtascadas) {
  $tareas = @()
  foreach ($f in @($Ficheros | Sort-Object FullName)) {
    $rel = Get-Rel $LegacyRoot $f.FullName
    $ficha = 'clase-' + (Get-Hash8 $rel)
    $n = [math]::Max(1, @([System.IO.File]::ReadAllLines($f.FullName)).Count)
    $trozos = [int][math]::Ceiling($n / [double][int]$Cfg.LineasPorTarea)
    for ($k = 0; $k -lt $trozos; $k++) {
      $desde = $k * [int]$Cfg.LineasPorTarea + 1
      $hasta = [math]::Min($n, ($k + 1) * [int]$Cfg.LineasPorTarea)
      if ($trozos -eq 1) { $id = $ficha } else { $id = $ficha + '-p' + ($k + 1) }
      $t = New-Tarea $id $ficha $rel $desde $hasta
      $previa = Join-Path (Join-Path $Datos 'tareas') ($id + '.json')
      if (Test-Path -LiteralPath $previa) {
        try { $p = Read-Json $previa; if ($p.estado -eq 'hecha' -or ($ConservarAtascadas -and $p.estado -eq 'atascada')) { $t = $p } } catch { }
      }
      Save-Tarea $t
      $tareas += $t
    }
  }
  return $tareas
}

# Cuando todos los trozos de una clase estan hechos, escribe su ficha en datos\fichas.
function Save-Fichas($Tareas) {
  foreach ($g in @($Tareas | Group-Object { $_.ficha })) {
    $ts = @($g.Group | Sort-Object { [int]$_.entradas.desde })
    if (@($ts | Where-Object { $_.estado -ne 'hecha' }).Count -gt 0) { continue }
    $juntos = @()
    foreach ($t in $ts) { foreach ($d in @($t.resultado.datos)) { $juntos += $d } }
    $p = $ts[0].resultado
    $ficha = [ordered]@{ id = $ts[0].ficha; fichero = $p.fichero; clase = $p.clase; papel = $p.papel; queHace = $p.queHace; datos = $juntos }
    Write-Json (Join-Path (Join-Path $Datos 'fichas') ($ts[0].ficha + '.json')) $ficha
  }
}

function Get-UltimaLinea([string]$Texto) {
  $l = @($Texto -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 1)
  if ($l.Count -eq 0) { return '(sin salida)' }
  $s = $l[0].Trim()
  if ($s.Length -gt 200) { $s = $s.Substring(0, 200) }
  return $s
}

# Una ronda de lectura: llama a Copilot para cada tarea de $Lote y comprueba lo que escribe.
# $Dir es la carpeta de trabajo de Copilot; $RaizOrig la carpeta de donde salen los ficheros.
# Devuelve, por tarea: Tarea, Estado (ok, invalida, fallo, tiempo), Motivo, Linea (la ultima linea
# de lo que dijo Copilot si fallo), Ficha y Registro.
function Invoke-Ronda($Lote, [string]$Dir, [string]$RaizOrig) {
  $items = @()
  foreach ($t in $Lote) {
    $leer = Join-Ruta $RaizOrig $t.entradas.fichero
    $motivo = ''
    $esf = $Cfg.EsfuerzoLectura
    if ($t.intentos -gt 0) {
      $esf = $Cfg.EsfuerzoReintento
      # la correccion es para una ficha que no paso la comprobacion; tras un fallo de Copilot se repite el prompt tal cual
      if ($t.ultimoEstado -eq 'invalida') { $motivo = $t.motivo }
    }
    $items += , ([pscustomobject]@{ Id = $t.id; Dir = $Dir; Modelo = $ModeloElegido; Esfuerzo = $esf; Prompt = (Get-PromptFicha $t $leer $motivo) })
  }
  $llamadas = @(Invoke-Llamadas $items)
  $res = @()
  for ($i = 0; $i -lt $Lote.Count; $i++) {
    $t = $Lote[$i]; $c = $llamadas[$i]
    $registro = Join-Path $Registros ($t.id + '-' + ($t.intentos + 1) + '.log')
    $cab = "# salida (codigo $($c.Codigo), $($c.Segundos) s"
    if ($c.Agotado) { $cab += ', tiempo agotado' }
    [System.IO.File]::WriteAllText($registro, ("# prompt`n" + $items[$i].Prompt + "`n`n" + $cab + ")`n" + $c.Texto + "`n"), $Utf8)
    $r = [pscustomobject]@{ Tarea = $t; Estado = 'ok'; Motivo = ''; Linea = ''; Ficha = $null; Registro = $registro }
    if ($c.Agotado) { $r.Estado = 'tiempo'; $r.Motivo = "Tiempo agotado: la llamada pasaba de $($Cfg.SegundosPorLlamada) s y se mato." }
    elseif ($c.Codigo -ne 0) { $r.Estado = 'fallo'; $r.Linea = Get-UltimaLinea $c.Texto; $r.Motivo = "Copilot salio con codigo $($c.Codigo): " + $r.Linea }
    else {
      $v = Test-Ficha $t $Dir (Join-Ruta $RaizOrig $t.entradas.fichero)
      if ($v.Ok) { $r.Ficha = $v.Ficha } else { $r.Estado = 'invalida'; $r.Motivo = $v.Motivo }
    }
    $res += $r
  }
  return $res
}

# ================================ APTITUD ================================
# Una ficha de clase sobre un fichero de juguete. Tiene que salir JSON valido con al
# menos una cita correcta. Devuelve '' si pasa o la frase que explica por que no. Si Copilot
# no responde (sale con error o se pasa de tiempo) no se repite: no es cosa del modelo.
function Test-Aptitud {
  $dir = Join-Path $Registros 'aptitud'
  if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
  [void](New-Item -ItemType Directory -Path $dir -Force)
  Copy-Item -LiteralPath (Join-Ruta $PSScriptRoot 'tareas/aptitud/ValidadorImporte.java') -Destination (Join-Path $dir 'ValidadorImporte.java')
  $n = @([System.IO.File]::ReadAllLines((Join-Path $dir 'ValidadorImporte.java'))).Count
  $t = New-Tarea 'aptitud' 'aptitud' 'ValidadorImporte.java' 1 $n
  $motivo = ''
  for ($k = 0; $k -lt [int]$Cfg.Intentos; $k++) {
    $o = @(Invoke-Ronda @($t) $dir $dir)[0]
    if ($o.Estado -eq 'ok' -and @($o.Ficha.datos | Where-Object { $_.probado }).Count -eq 0) {
      $o.Estado = 'invalida'
      $o.Motivo = 'La ficha no tiene ningun dato con una cita que salga en el fichero. Este fichero tiene reglas que contar.'
    }
    if ($o.Estado -eq 'ok') { return '' }
    if ($o.Estado -eq 'fallo') { return "Copilot no ha podido responder: $($o.Linea)" }
    if ($o.Estado -eq 'tiempo') { return "Copilot no ha podido responder: $($o.Motivo)" }
    $t.intentos++
    $t.motivo = $o.Motivo
    $t.ultimoEstado = $o.Estado
    $motivo = $o.Motivo
  }
  return "La prueba de aptitud ha fallado $($Cfg.Intentos) veces con este modelo: $motivo"
}

# ================================ DESPIERTO ================================
# Pide a Windows que no suspenda el equipo mientras el script trabaja ($true) o lo suelta ($false).
# Devuelve $true si lo consigue (y siempre fuera de Windows) y $false si no; nunca lanza.
function Set-Despierto([bool]$Activar) {
  if ($env:OS -ne 'Windows_NT') { return $true }
  try {
    if (-not ('Rescate.Energia' -as [type])) {
      Add-Type -Namespace Rescate -Name Energia -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint esFlags);'
    }
    $tipo = 'Rescate.Energia' -as [type]
    if ($Activar) { $flags = [uint32]2147483649 } else { $flags = [uint32]2147483648 }
    return ($tipo::SetThreadExecutionState($flags) -ne 0)
  }
  catch { return $false }
}
