<#
tareas.ps1 - Las piezas de migracion.ps1 que no son el arranque: las llamadas a Copilot
en paralelo, las tareas (ficha de clase, definicion de job, ficha de job, resumen, prueba en pre y comparacion con el
migrado) con su comprobacion, el mapa de jobs, las variables del migrado y la prueba de aptitud.
Se carga con '. (Join-Path $PSScriptRoot 'tareas.ps1')' despues de comun.ps1, desde
migracion.ps1 o desde cualquier script que necesite lo mismo (un preflight) sin pasar
por el arranque. Cargarlo no ejecuta nada. Solo ASCII a proposito.
Necesita la carpeta tareas\ (plantilla del prompt y fichero de la prueba) junto a este script.

DEFINE al cargarse: $Utf8, las claves de $Cfg de abajo (CONFIGURACION: Paralelo,
SegundosPorLlamada, Intentos, LineasPorTarea, CitaMax, CitaCerca, EsfuerzoLectura,
EsfuerzoRedaccion, EsfuerzoReintento, CaracteresPorTarea, ClasesPorJob, ProfundidadJob,
PasosDefinicionMax, PasosFichaMax, GlosarioMax, CasosMax, FicherosComparar, EstadosComparar, ListasJob, Papeles, TiposDato, JavaExe, JacocoPlugin y
CoberturaMinima) y
las funciones. Get-Lanzador usa Get-Lanzable, de comun.ps1.

ESPERA que quien lo carga haya puesto, antes de llamar a sus funciones:
  $Cfg            el de comun.ps1 (este fichero le anade sus claves al cargarse)
  $LegacyRoot     carpeta del batch original: Invoke-Llamadas se la da a Copilot (--add-dir)
                  y Get-TareasFichas saca de ahi las rutas relativas
  $Registros      carpeta de registros: Invoke-Ronda y Test-Aptitud escriben ahi
  $ModeloElegido  id del modelo ('' = el que tenga Copilot): Invoke-Ronda
  $Datos          carpeta datos\: Save-Tarea, Get-TareasFichas y Save-Fichas
Las tareas del negocio (mapa, ficha de job, resumen, prueba en pre y variables) necesitan ademas $RepoRoot
(el worktree: de ahi salen .rescate\contrato.json, las variables y los ficheros del migrado que se comparan) y $Fuentes (los .java del
original que se leen); Get-JobsContrato llama a rescate.ps1 (junto a este script) si falta el contrato.
Test-Aptitud solo usa $Cfg, $LegacyRoot, $Registros y $ModeloElegido.
Invoke-Ronda devuelve, por tarea, tambien Segundos y Codigo de la llamada (para medir sin
leer el registro).
Stop-Arranque termina el script que lo llame con la salida 1.
#>

# ============================ CONFIGURACION ============================
# Las claves de las tareas. Los ajustes (ajustes.json, .rescate\config.json) las pisan.
$Cfg += @{
  JavaExe            = 'java'
  Paralelo           = 4      # llamadas a Copilot a la vez
  SegundosPorLlamada = 900    # pasado este tiempo, la llamada se mata
  Intentos           = 2      # el primero y un reintento con el motivo
  LineasPorTarea     = 300    # un fichero mas largo se trocea por rangos de lineas
  CitaMax            = 120    # caracteres de una cita
  CitaCerca          = 3      # una cita a esta distancia (o menos) de su linea cuenta como bien situada
  EsfuerzoLectura    = 'medium'
  EsfuerzoRedaccion  = 'high'     # ficha de job y resumen: no leen codigo, solo redactan
  EsfuerzoReintento  = 'high'
  CaracteresPorTarea = 24000  # lo que cabe de datos de clases en el prompt de una ficha de job
  ClasesPorJob       = 40     # clases de un job (con sus referencias)
  ProfundidadJob     = 2      # niveles de referencias desde los pasos y el fichero que define el job
  PasosDefinicionMax = 20     # pasos de un job en la definicion
  PasosFichaMax      = 12     # pasos de una ficha de job
  GlosarioMax        = 15
  CasosMax           = 40     # casos de la prueba en pre de un job
  FicherosComparar   = 3      # ficheros del migrado que se le dan a la comparacion de una clase del original
  EstadosComparar    = @('igual', 'distinto', 'falta', 'no-lo-se')   # lo que puede decir la IA de un dato (sin-pieza lo pone el script)
  JacocoPlugin       = 'org.jacoco:jacoco-maven-plugin:0.8.16'   # el preflight prueba en el equipo estas mismas coordenadas
  CoberturaMinima    = 80     # por ciento de lineas cubiertas por los tests por debajo del cual la cobertura se marca como baja
  # Que datos de las fichas de clase van a cada lista de la ficha de job (cada tipo de dato, a una)
  ListasJob          = [ordered]@{
    necesita   = @('entrada-fichero', 'tabla-lee', 'parametro', 'config')
    produce    = @('salida-fichero', 'tabla-escribe')
    conexiones = @('sftp', 'externo')
    reglas     = @('regla')
    siFalla    = @('error')
  }
  Papeles            = @('lector', 'procesador', 'escritor', 'tarea', 'validador', 'configuracion', 'acceso-datos', 'sftp', 'modelo', 'otro')
  TiposDato          = @('entrada-fichero', 'salida-fichero', 'sftp', 'tabla-lee', 'tabla-escribe', 'parametro', 'config', 'regla', 'error', 'externo')
}

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
  $l = Get-Lanzable $Exe
  if (-not $l.Ruta) { throw $l.Mensaje }
  $ruta = $l.Ruta
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

# Una llamada por elemento de $Lote (Id, Dir, Prompt, Modelo, Esfuerzo, Dirs: las carpetas que puede leer), todas a la vez.
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
    $vivos += , (Start-Llamada $it.Dir (Get-ArgsCopilot $texto $it.Modelo $it.Esfuerzo @($it.Dirs) $true))
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

# ================================ PROMPTS ================================
# La plantilla de cada tipo de tarea es tareas\<tipo>.md.
function Get-Plantilla([string]$Tipo) {
  if (-not $script:Plantillas) { $script:Plantillas = @{} }
  if (-not $script:Plantillas.ContainsKey($Tipo)) {
    $ruta = Join-Ruta $PSScriptRoot "tareas/$Tipo.md"
    if (-not (Test-Path -LiteralPath $ruta)) { Stop-Arranque "Falta la plantilla del prompt: $ruta" }
    $script:Plantillas[$Tipo] = [System.IO.File]::ReadAllText($ruta, $Utf8) -replace "`r`n", "`n"
  }
  return $script:Plantillas[$Tipo]
}

# Lo que va en cada {{CLAVE}} de la plantilla de una tarea. $Leer es el fichero del original que se lee.
# Una tarea con entradas.prompt (las de prueba-local.ps1) trae ahi sus claves.
function Get-VariablesPrompt($T, [string]$Leer) {
  $e = $T.entradas
  $v = @{ SALIDA = ".rescate/tareas/$($T.id).json"; CITA_MAX = "$($Cfg.CitaMax)" }
  if ($e.prompt) { foreach ($p in $e.prompt.PSObject.Properties) { $v[$p.Name] = [string]$p.Value }; return $v }
  switch ($T.tipo) {
    'definicion-job' {
      $v.FICHERO = $Leer; $v.RELATIVO = $e.fichero; $v.LINEAS = "$($e.desde)-$($e.hasta)"
      $v.JOBS = (@($e.jobs) -join ', '); $v.CLASES = ((Get-NombresClases) -join ', '); $v.PASOS_MAX = "$($Cfg.PasosDefinicionMax)"
    }
    'ficha-job' { $v.JOB = $e.job; $v.PASOS = $e.pasos; $v.DATOS = $e.datos; $v.PASOS_MAX = "$($Cfg.PasosFichaMax)" }
    'prueba-pre' { $v.JOB = $e.job; $v.PASOS = $e.pasos; $v.DATOS = $e.datos; $v.VARIABLES = $e.variables; $v.CASOS_MAX = "$($Cfg.CasosMax)" }
    'resumen' { $v.JOBS = $e.datos; $v.GLOSARIO_MAX = "$($Cfg.GlosarioMax)" }
    'comparar-pieza' {
      $v.FICHERO = $Leer; $v.CLASE = $e.clase; $v.DATOS = $e.datos
      $v.MIGRADO = ((@($e.migrado) | ForEach-Object { "MIGRADO: $_" }) -join "`n")
    }
    default {
      $v.FICHERO = $Leer; $v.RELATIVO = $e.fichero; $v.LINEAS = "$($e.desde)-$($e.hasta)"
      $v.PAPELES = ($Cfg.Papeles -join ', '); $v.TIPOS = ($Cfg.TiposDato -join ', ')
    }
  }
  return $v
}

# El prompt de una tarea. Con $Motivo (reintento) lleva ademas la seccion de correccion.
function Get-Prompt($T, [string]$Leer, [string]$Motivo) {
  $partes = (Get-Plantilla $T.tipo) -split '<!--CORRECCION-->\n', 2
  $p = $partes[0]
  if ($Motivo) { $p += $partes[1].Replace('{{MOTIVO}}', $Motivo) }
  $v = Get-VariablesPrompt $T $Leer
  return [regex]::Replace($p, '\{\{(\w+)\}\}', { param($m) $v[$m.Groups[1].Value] })
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

# Lo que ha escrito Copilot en .rescate\tareas\<id>.json, como objeto en Ficha, o el motivo de que no valga.
function Read-Salida($T, [string]$Dir) {
  $ruta = Join-Ruta $Dir ".rescate/tareas/$($T.id).json"
  if (-not (Test-Path -LiteralPath $ruta)) { return (New-Resultado $false "No has escrito el fichero de salida .rescate/tareas/$($T.id).json. Escribe ahi el JSON." $null) }
  try { $o = Read-Json $ruta } catch { return (New-Resultado $false ('El JSON no es valido: ' + $_.Exception.Message) $null) }
  if ($o -isnot [System.Management.Automation.PSCustomObject]) { return (New-Resultado $false 'El JSON no es valido: tiene que ser un objeto { ... }.' $null) }
  return (New-Resultado $true '' $o)
}

# La linea y la cita de $D, que se llama $Pre en los motivos. Devuelve '' si valen o el motivo.
function Test-LineaCita($D, [string]$Pre) {
  if (-not (Test-Entero $D.linea)) { return "$Pre.linea tiene que ser un numero entero desde 1." }
  if (-not (Test-Texto $D.cita) -or (($D.cita -replace '\s', '') -eq '')) { return "$Pre.cita falta o esta vacia." }
  if ($D.cita.Length -gt [int]$Cfg.CitaMax) { return "$Pre.cita pasa de $($Cfg.CitaMax) caracteres: copia solo un trozo corto." }
  return ''
}

# Busca la cita de cada elemento de $Lista (con linea, cita y probado) en el fichero $Leer: corrige la
# linea y marca probado los que salen. Devuelve las citas que no salen.
function Set-CitasProbadas($Lista, [string]$Leer) {
  $indice = Get-IndiceCitas $Leer
  $inventadas = @()
  foreach ($d in $Lista) {
    $donde = @(Find-Cita $indice $d.cita)
    if ($donde.Count -eq 0) { $inventadas += $d.cita; continue }
    $cerca = @($donde | Where-Object { [math]::Abs($_ - $d.linea) -le [int]$Cfg.CitaCerca })
    if ($cerca.Count -eq 0) { $d.linea = [int](@($donde | Sort-Object { [math]::Abs($_ - $d.linea) })[0]) }
    $d.probado = $true
  }
  return $inventadas
}

# Las citas de $Lista en el fichero $Leer (Set-CitasProbadas): si mas de la mitad no salen devuelve el motivo; si no, ''.
function Test-Citas($Lista, [string]$Leer) {
  $inventadas = @(Set-CitasProbadas $Lista $Leer)
  if (($inventadas.Count * 2) -gt $Lista.Count) {
    return "Mas de la mitad de las citas ($($inventadas.Count) de $($Lista.Count)) no salen en el fichero, por ejemplo: '$($inventadas[0])'. Copia las citas tal cual del codigo y no inventes ninguna."
  }
  return ''
}

# Comprueba lo que ha escrito Copilot: JSON, campos, vocabularios y citas.
# Si vale, devuelve la ficha con 'probado' en cada dato y la linea corregida.
function Test-Ficha($T, [string]$Dir, [string]$Leer) {
  $s = Read-Salida $T $Dir
  if (-not $s.Ok) { return $s }
  $o = $s.Ficha
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
    $m = Test-LineaCita $d $pre
    if ($m) { return (New-Resultado $false $m $null) }
    $lista += [ordered]@{ tipo = $d.tipo; texto = $d.texto; linea = [int]$d.linea; cita = $d.cita; probado = $false }
    $i++
  }
  $m = Test-Citas $lista $Leer
  if ($m) { return (New-Resultado $false $m $null) }
  $ficha = [ordered]@{ fichero = $T.entradas.fichero; clase = $o.clase; papel = $o.papel; queHace = $o.queHace; datos = $lista }
  return (New-Resultado $true '' $ficha)
}

# Los nombres simples de las clases del original (la lista cerrada que se le da al modelo).
function Get-NombresClases { return @($Fuentes | ForEach-Object { $_.BaseName } | Sort-Object -Unique) }

# '' si $Dados son exactamente los $Pedidos, cada uno una vez; si no, el motivo ($Donde dice de que lista se habla).
function Compare-Nombres($Pedidos, $Dados, [string]$Donde) {
  $faltan = @($Pedidos | Where-Object { $Dados -cnotcontains $_ })
  $sobran = @($Dados | Where-Object { $Pedidos -cnotcontains $_ } | Select-Object -Unique)
  $repes = @($Dados | Group-Object -CaseSensitive | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
  $partes = @()
  if ($faltan.Count -gt 0) { $partes += 'faltan ' + ($faltan -join ', ') }
  if ($sobran.Count -gt 0) { $partes += 'sobran ' + ($sobran -join ', ') }
  if ($repes.Count -gt 0) { $partes += 'estan repetidos ' + ($repes -join ', ') }
  if ($partes.Count -eq 0) { return '' }
  return "En $Donde tiene que estar exactamente cada uno de estos, una sola vez: $($Pedidos -join ', '). Pero " + ($partes -join '; ') + '.'
}

# Un texto de negocio no puede llevar el nombre compuesto de una clase del original (dos o mas mayusculas y alguna
# minuscula: GestorRecibos, SFTPClient) como palabra entera, ni el nombre de ningun fichero .java. Recibo, Estado o
# IBAN, sueltos, son palabras de negocio y valen. $Campos es nombre del campo -> texto. Devuelve '' si valen o el
# motivo, que dice cual sobra y en que campo.
function Test-LenguajeNegocio($Campos) {
  $nombres = @(Get-NombresClases | Where-Object { $_ -cmatch '^(?=(?:[^A-Z]*[A-Z]){2})(?=.*[a-z])' } | ForEach-Object { [regex]::Escape($_) })
  $rx = '(?<!\w)[\w\-]+\.java(?!\w)'
  if ($nombres.Count -gt 0) { $rx = '(?<!\w)(?:' + ($nombres -join '|') + ')(?!\w)|' + $rx }
  $mal = @()
  foreach ($k in $Campos.Keys) {
    foreach ($n in @([regex]::Matches([string]$Campos[$k], $rx) | ForEach-Object { $_.Value } | Select-Object -Unique)) { $mal += "$k lleva el nombre de la clase $n" }
  }
  if ($mal.Count -eq 0) { return '' }
  return ('Esto es para gente de negocio y no puede llevar nombres de clases: ' + ($mal -join '; ') + '. Cuenta lo que hace con palabras normales.')
}

# Comprueba la definicion de los jobs de un fichero: exactamente los jobs pedidos, de 1 a PasosDefinicionMax
# pasos cada uno, clases de la lista cerrada del original y citas que salen en el fichero.
function Test-DefinicionJob($T, [string]$Dir, [string]$Leer) {
  $s = Read-Salida $T $Dir
  if (-not $s.Ok) { return $s }
  $o = $s.Ficha
  if ($o.jobs -isnot [array]) { return (New-Resultado $false "Falta el campo 'jobs': una lista con un elemento por job." $null) }
  $max = [int]$Cfg.PasosDefinicionMax
  $cerradas = @(Get-NombresClases)
  $jobs = @(); $citas = @(); $nombres = @(); $fuera = @()
  $i = 0
  foreach ($j in $o.jobs) {
    $pre = "jobs[$i]"
    if ($j -isnot [System.Management.Automation.PSCustomObject]) { return (New-Resultado $false "$pre tiene que ser un objeto con job, linea, cita y pasos." $null) }
    if (-not (Test-Texto $j.job)) { return (New-Resultado $false "$pre.job falta o esta vacio." $null) }
    $m = Test-LineaCita $j $pre
    if ($m) { return (New-Resultado $false $m $null) }
    if (($j.pasos -isnot [array]) -or @($j.pasos).Count -lt 1 -or @($j.pasos).Count -gt $max) { return (New-Resultado $false "$pre.pasos tiene que ser una lista de 1 a $max pasos." $null) }
    $ej = [ordered]@{ job = $j.job; linea = [int]$j.linea; cita = $j.cita; probado = $false; pasos = @() }
    $nombres += $j.job
    $citas += $ej
    $k = 0
    foreach ($p in $j.pasos) {
      $pp = "$pre.pasos[$k]"
      if ($p -isnot [System.Management.Automation.PSCustomObject]) { return (New-Resultado $false "$pp tiene que ser un objeto con paso, linea, cita y clases." $null) }
      if (-not (Test-Texto $p.paso)) { return (New-Resultado $false "$pp.paso falta o esta vacio." $null) }
      $m = Test-LineaCita $p $pp
      if ($m) { return (New-Resultado $false $m $null) }
      if ($p.clases -isnot [array]) { return (New-Resultado $false "$pp.clases tiene que ser una lista de nombres de clase (vacia si el paso no usa ninguna de CLASES)." $null) }
      foreach ($c in $p.clases) { if (($c -isnot [string]) -or ($cerradas -cnotcontains $c)) { $fuera += "$c" } }
      $ep = [ordered]@{ paso = $p.paso; linea = [int]$p.linea; cita = $p.cita; probado = $false; clases = @($p.clases | ForEach-Object { "$_" }) }
      $ej.pasos += $ep
      $citas += $ep
      $k++
    }
    $jobs += $ej
    $i++
  }
  $m = Compare-Nombres @($T.entradas.jobs) $nombres "'jobs'"
  if ($m) { return (New-Resultado $false $m $null) }
  if ($fuera.Count -gt 0) { return (New-Resultado $false ("En 'clases' hay nombres que no estan en la lista CLASES: " + (($fuera | Select-Object -Unique) -join ', ') + '. Usa solo nombres de esa lista, tal cual.') $null) }
  $m = Test-Citas $citas $Leer
  if ($m) { return (New-Resultado $false $m $null) }
  return (New-Resultado $true '' ([ordered]@{ jobs = $jobs }))
}

# Comprueba la ficha de un job: el job pedido, titulo, paraQue y de 1 a PasosFichaMax pasos con sus referencias
# (las que estan en el prompt), y sin nombres de clase en ningun texto. Un paso sin referencia valida queda
# probado: false; con mas de la mitad asi, no vale.
function Test-FichaJob($T, [string]$Dir) {
  $s = Read-Salida $T $Dir
  if (-not $s.Ok) { return $s }
  $o = $s.Ficha
  if ($o.job -cne $T.entradas.job) { return (New-Resultado $false "El campo 'job' tiene que valer '$($T.entradas.job)'." $null) }
  foreach ($c in @('titulo', 'paraQue')) {
    if (-not (Test-Texto $o.$c)) { return (New-Resultado $false "Falta el campo '$c' (o esta vacio)." $null) }
  }
  $max = [int]$Cfg.PasosFichaMax
  if (($o.pasos -isnot [array]) -or @($o.pasos).Count -lt 1 -or @($o.pasos).Count -gt $max) { return (New-Resultado $false "El campo 'pasos' tiene que ser una lista de 1 a $max pasos." $null) }
  if ($null -ne $o.dudas -and $o.dudas -isnot [array]) { return (New-Resultado $false "El campo 'dudas' tiene que ser una lista de frases (vacia si no hay dudas)." $null) }
  $validas = @{}
  foreach ($m in [regex]::Matches($T.entradas.datos, '(?m)^(clase-[0-9a-f]{8}#\d+) \[')) { $validas[$m.Groups[1].Value] = $true }
  $campos = [ordered]@{ titulo = $o.titulo; paraQue = $o.paraQue }
  $pasos = @()
  $sinRef = 0
  $i = 0
  foreach ($p in $o.pasos) {
    $pre = "pasos[$i]"
    if ($p -isnot [System.Management.Automation.PSCustomObject]) { return (New-Resultado $false "$pre tiene que ser un objeto con titulo, texto y refs." $null) }
    foreach ($c in @('titulo', 'texto')) {
      if (-not (Test-Texto $p.$c)) { return (New-Resultado $false "$pre.$c falta o esta vacio." $null) }
    }
    if (($p.refs -isnot [array]) -or @($p.refs).Count -eq 0) { return (New-Resultado $false "$pre.refs tiene que ser una lista con al menos una referencia." $null) }
    $refs = @($p.refs | Where-Object { ($_ -is [string]) -and $validas.ContainsKey($_) })
    if ($refs.Count -eq 0) { $sinRef++ }
    $campos["$pre.titulo"] = $p.titulo
    $campos["$pre.texto"] = $p.texto
    $pasos += [ordered]@{ titulo = $p.titulo; texto = $p.texto; refs = $refs; probado = ($refs.Count -gt 0) }
    $i++
  }
  if (($sinRef * 2) -gt $pasos.Count) {
    return (New-Resultado $false "Mas de la mitad de los pasos ($sinRef de $($pasos.Count)) no llevan ninguna referencia valida. Las referencias son las de los datos del prompt (clase-xxxxxxxx#n), copiadas tal cual; no se inventan." $null)
  }
  $m = Test-LenguajeNegocio $campos
  if ($m) { return (New-Resultado $false $m $null) }
  $dudas = @($o.dudas | Where-Object { Test-Texto $_ })
  return (New-Resultado $true '' ([ordered]@{ job = $o.job; titulo = $o.titulo; paraQue = $o.paraQue; pasos = $pasos; dudas = $dudas }))
}

# Comprueba el resumen: todos los textos sin nombres de clase, todos los jobs del mapa una vez en 'orden' y de 0 a
# GlosarioMax terminos.
function Test-Resumen($T, [string]$Dir) {
  $s = Read-Salida $T $Dir
  if (-not $s.Ok) { return $s }
  $o = $s.Ficha
  if (-not (Test-Texto $o.resumen)) { return (New-Resultado $false "Falta el campo 'resumen' (o esta vacio)." $null) }
  $campos = [ordered]@{ resumen = $o.resumen }
  if ($o.orden -isnot [array]) { return (New-Resultado $false "Falta el campo 'orden': una lista con un elemento por job." $null) }
  $orden = @()
  $i = 0
  foreach ($x in $o.orden) {
    if (($x -isnot [System.Management.Automation.PSCustomObject]) -or -not (Test-Texto $x.job)) { return (New-Resultado $false "orden[$i] tiene que ser un objeto con job y motivo." $null) }
    $orden += [ordered]@{ job = $x.job; motivo = "$($x.motivo)" }
    $campos["orden[$i].motivo"] = "$($x.motivo)"
    $i++
  }
  $m = Compare-Nombres @($T.entradas.jobs) @($orden | ForEach-Object { $_.job }) "'orden'"
  if ($m) { return (New-Resultado $false $m $null) }
  if (($o.glosario -isnot [array]) -or @($o.glosario).Count -gt [int]$Cfg.GlosarioMax) { return (New-Resultado $false "El campo 'glosario' tiene que ser una lista de 0 a $($Cfg.GlosarioMax) terminos (vacia si no hay)." $null) }
  $glosario = @()
  $i = 0
  foreach ($g in $o.glosario) {
    if (($g -isnot [System.Management.Automation.PSCustomObject]) -or -not (Test-Texto $g.termino) -or -not (Test-Texto $g.definicion)) { return (New-Resultado $false "glosario[$i] tiene que ser un objeto con termino y definicion, los dos con texto." $null) }
    $glosario += [ordered]@{ termino = $g.termino; definicion = $g.definicion }
    $campos["glosario[$i].termino"] = $g.termino
    $campos["glosario[$i].definicion"] = $g.definicion
    $i++
  }
  $m = Test-LenguajeNegocio $campos
  if ($m) { return (New-Resultado $false $m $null) }
  return (New-Resultado $true '' ([ordered]@{ resumen = $o.resumen; orden = $orden; glosario = $glosario }))
}

# Comprueba el guion de prueba en pre de un job (entradas.datos son los hechos que recibio, uno por linea con su
# referencia): formato, referencias que existen en esos hechos, de 0 a CasosMax casos, textos sin nombres de clase y
# cada hecho de tipo regla y error en las refs de algun caso. Si faltan y es el ultimo intento, la tarea vale y los que
# faltan van a sinCaso; si no, el motivo los lleva todos, para el reintento.
function Test-PruebaPre($T, [string]$Dir) {
  $s = Read-Salida $T $Dir
  if (-not $s.Ok) { return $s }
  $o = $s.Ficha
  if ($o.job -cne $T.entradas.job) { return (New-Resultado $false "El campo 'job' tiene que valer '$($T.entradas.job)'." $null) }
  $hechos = [ordered]@{}
  foreach ($m in [regex]::Matches($T.entradas.datos, '(?m)^(clase-[0-9a-f]{8}#\d+) \[([\w\-]+)\] (.*)$')) {
    $hechos[$m.Groups[1].Value] = [ordered]@{ ref = $m.Groups[1].Value; tipo = $m.Groups[2].Value; texto = $m.Groups[3].Value.Trim() }
  }
  $campos = [ordered]@{}
  $listas = @{}
  foreach ($k in @('preparar', 'casos', 'comprobar')) {
    if ($o.$k -isnot [array]) { return (New-Resultado $false "El campo '$k' tiene que ser una lista (vacia si no hay nada)." $null) }
    $textos = @('texto')
    if ($k -eq 'casos') { $textos = @('titulo', 'entrada', 'esperado') }
    $lista = @()
    $i = 0
    foreach ($x in $o.$k) {
      $pre = "$k[$i]"
      if ($x -isnot [System.Management.Automation.PSCustomObject]) { return (New-Resultado $false "$pre tiene que ser un objeto con $($textos -join ', ') y refs." $null) }
      $item = [ordered]@{}
      foreach ($c in $textos) {
        if (-not (Test-Texto $x.$c)) { return (New-Resultado $false "$pre.$c falta o esta vacio." $null) }
        $item[$c] = $x.$c
        $campos["$pre.$c"] = $x.$c
      }
      if ($x.refs -isnot [array] -or ($k -eq 'casos' -and @($x.refs).Count -eq 0)) { return (New-Resultado $false "$pre.refs tiene que ser una lista de referencias (en los casos, al menos una)." $null) }
      $malas = @($x.refs | Where-Object { ($_ -isnot [string]) -or -not $hechos.Contains($_) })
      if ($malas.Count -gt 0) { return (New-Resultado $false "$pre.refs lleva referencias que no estan en los hechos de arriba: $(@($malas | ForEach-Object { "$_" }) -join ', '). Copia las referencias tal cual." $null) }
      $item['refs'] = @($x.refs)
      $lista += $item
      $i++
    }
    $listas[$k] = $lista
  }
  $max = [int]$Cfg.CasosMax
  if ($listas['casos'].Count -gt $max) { return (New-Resultado $false "Hay $($listas['casos'].Count) casos y el maximo es ${max}: junta los que se prueben con la misma entrada." $null) }
  $m = Test-LenguajeNegocio $campos
  if ($m) { return (New-Resultado $false $m $null) }
  $cubiertas = @{}
  foreach ($c in $listas['casos']) { foreach ($r in $c.refs) { $cubiertas[$r] = $true } }
  $faltan = @($hechos.Values | Where-Object { ($_.tipo -ceq 'regla' -or $_.tipo -ceq 'error') -and -not $cubiertas.ContainsKey($_.ref) })
  $sinCaso = @()
  if ($faltan.Count -gt 0) {
    if (($T.intentos + 1) -lt [int]$Cfg.Intentos) {
      $lineas = @($faltan | ForEach-Object { "- $($_.ref) ($($_.tipo)): $($_.texto)" })
      return (New-Resultado $false ("Cada regla y cada error de los hechos tiene que salir en las refs de algun caso, y faltan estos $($faltan.Count):`n" + ($lineas -join "`n")) $null)
    }
    $sinCaso = @($faltan | ForEach-Object { [ordered]@{ ref = $_.ref; tipo = $_.tipo; texto = $_.texto } })
  }
  return (New-Resultado $true '' ([ordered]@{ job = $o.job; preparar = @($listas['preparar']); casos = @($listas['casos']); comprobar = @($listas['comprobar']); sinCaso = $sinCaso }))
}

# Comprueba lo que ha escrito Copilot segun el tipo de la tarea.
function Test-Salida($T, [string]$Dir, [string]$Leer) {
  switch ($T.tipo) {
    'definicion-job' { return (Test-DefinicionJob $T $Dir $Leer) }
    'ficha-job' { return (Test-FichaJob $T $Dir) }
    'resumen' { return (Test-Resumen $T $Dir) }
    'prueba-pre' { return (Test-PruebaPre $T $Dir) }
    'comparar-pieza' { return (Test-Comparar $T $Dir) }
    default { return (Test-Ficha $T $Dir $Leer) }
  }
}

# ================================ TAREAS ================================
function New-TareaTipo([string]$Tipo, [string]$Id, [string]$Ficha, [string]$Salida, $Entradas) {
  return [pscustomobject]@{
    id = $Id; ficha = $Ficha; tipo = $Tipo; salida = $Salida; estado = 'pendiente'; intentos = 0; ultimoEstado = ''; motivo = ''
    entradas = $Entradas; resultado = $null
  }
}

# La ficha de clase de un fichero (o de un trozo de sus lineas).
function New-Tarea([string]$Id, [string]$Ficha, [string]$Rel, [int]$Desde, [int]$Hasta) {
  return (New-TareaTipo 'ficha-clase' $Id $Ficha "datos/fichas/$Ficha.json" ([pscustomobject]@{ fichero = $Rel; desde = $Desde; hasta = $Hasta }))
}

function Save-Tarea($T) { Write-Json (Join-Path (Join-Path $Datos 'tareas') ($T.id + '.json')) $T }

# Guarda la tarea y devuelve la que queda: la de un lanzamiento anterior si esta hecha (o atascada, con
# $ConservarAtascadas) y sus entradas siguen siendo las mismas (huella); si no, la nueva.
function Restore-Tarea($T, [bool]$ConservarAtascadas) {
  $previa = Join-Path (Join-Path $Datos 'tareas') ($T.id + '.json')
  if (Test-Path -LiteralPath $previa) {
    try {
      $p = Read-Json $previa
      if (($p.estado -eq 'hecha' -or ($ConservarAtascadas -and $p.estado -eq 'atascada')) -and $p.entradas.huella -eq $T.entradas.huella) { $T = $p }
    }
    catch { }
  }
  Save-Tarea $T
  return $T
}

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
      $tareas += , (Restore-Tarea (New-Tarea $id $ficha $rel $desde $hasta) $ConservarAtascadas)
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

# Una ronda: llama a Copilot para cada tarea de $Lote (del tipo que sea) y comprueba lo que escribe.
# $Dir es la carpeta de trabajo de Copilot; $RaizOrig la carpeta de donde salen los ficheros. Las tareas
# con un fichero que leer (ficha de clase, definicion de job) pueden leer el original, con EsfuerzoLectura;
# las que solo redactan (ficha de job, resumen) no leen nada, con EsfuerzoRedaccion.
# Devuelve, por tarea: Tarea, Estado (ok, invalida, fallo, tiempo), Motivo, Linea (la ultima linea
# de lo que dijo Copilot si fallo), Ficha, Registro, Segundos y Codigo (los de la llamada).
function Invoke-Ronda($Lote, [string]$Dir, [string]$RaizOrig) {
  $items = @()
  foreach ($t in $Lote) {
    $leer = ''
    $dirs = @()
    $esf = $Cfg.EsfuerzoRedaccion
    if ($t.entradas.fichero) { $leer = Join-Ruta $RaizOrig $t.entradas.fichero; $dirs = @($LegacyRoot); $esf = $Cfg.EsfuerzoLectura }
    $motivo = ''
    if ($t.intentos -gt 0) {
      $esf = $Cfg.EsfuerzoReintento
      # la correccion es para una ficha que no paso la comprobacion; tras un fallo de Copilot se repite el prompt tal cual
      if ($t.ultimoEstado -eq 'invalida') { $motivo = $t.motivo }
    }
    $items += , ([pscustomobject]@{ Id = $t.id; Dir = $Dir; Modelo = $ModeloElegido; Esfuerzo = $esf; Dirs = $dirs; Leer = $leer; Prompt = (Get-Prompt $t $leer $motivo) })
  }
  $llamadas = @(Invoke-Llamadas $items)
  $res = @()
  for ($i = 0; $i -lt $Lote.Count; $i++) {
    $t = $Lote[$i]; $c = $llamadas[$i]
    $registro = Join-Path $Registros ($t.id + '-' + ($t.intentos + 1) + '.log')
    $cab = "# salida (codigo $($c.Codigo), $($c.Segundos) s"
    if ($c.Agotado) { $cab += ', tiempo agotado' }
    [System.IO.File]::WriteAllText($registro, ("# prompt`n" + $items[$i].Prompt + "`n`n" + $cab + ")`n" + $c.Texto + "`n"), $Utf8)
    $r = [pscustomobject]@{ Tarea = $t; Estado = 'ok'; Motivo = ''; Linea = ''; Ficha = $null; Registro = $registro; Segundos = $c.Segundos; Codigo = $c.Codigo }
    if ($c.Agotado) { $r.Estado = 'tiempo'; $r.Motivo = "Tiempo agotado: la llamada pasaba de $($Cfg.SegundosPorLlamada) s y se mato." }
    elseif ($c.Codigo -ne 0) { $r.Estado = 'fallo'; $r.Linea = Get-UltimaLinea $c.Texto; $r.Motivo = "Copilot salio con codigo $($c.Codigo): " + $r.Linea }
    else {
      $v = Test-Salida $t $Dir ($items[$i].Leer)
      if ($v.Ok) { $r.Ficha = $v.Ficha } else { $r.Estado = 'invalida'; $r.Motivo = $v.Motivo }
    }
    $res += $r
  }
  return $res
}

# ================================== MAPA ==================================
# Los jobs del contrato (.rescate\contrato.json del worktree). Si no esta, lo escribe rescate.ps1 (-Modo pre -SinIA).
function Get-JobsContrato {
  $ruta = Join-Ruta $RepoRoot '.rescate/contrato.json'
  if (-not (Test-Path -LiteralPath $ruta)) {
    $r = Invoke-Nativo (Get-PowerShellExe) @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'rescate.ps1'), '-Modo', 'pre', '-Repo', $RepoRoot, '-Legacy', $LegacyRoot, '-SinIA', '-Si')
    if ($r.Codigo -ne 0 -or -not (Test-Path -LiteralPath $ruta)) { throw ("rescate.ps1 -Modo pre no ha escrito el contrato (codigo $($r.Codigo)): " + (@($r.Salida | Select-Object -Last 3) -join ' / ')) }
  }
  return @((Read-Json $ruta).jobs | Where-Object { $_ -and $_.nombre })
}

# El fichero que define un job: Rel, Existe y Motivo (vacio si se puede leer de una vez, y si no, por que).
function Get-FicheroDefinicion($Job) {
  $rel = ("$($Job.definidoEn)" -replace '\\', '/').Trim()
  $d = [pscustomobject]@{ Rel = $rel; Existe = $false; Lineas = 0; Motivo = '' }
  if ($rel -and (Test-Path -LiteralPath (Join-Ruta $LegacyRoot $rel) -PathType Leaf)) {
    $d.Existe = $true
    $d.Lineas = [math]::Max(1, @([System.IO.File]::ReadAllLines((Join-Ruta $LegacyRoot $rel))).Count)
    if ($d.Lineas -gt (3 * [int]$Cfg.LineasPorTarea)) { $d.Motivo = "el fichero que lo define ($rel) pasa de $(3 * [int]$Cfg.LineasPorTarea) lineas" }
  }
  elseif ($rel) { $d.Motivo = "el fichero que lo define ($rel) no esta en el original" }
  else { $d.Motivo = 'el contrato no dice en que fichero se define' }
  return $d
}

# Una tarea de definicion por cada fichero (que se pueda leer) que define jobs.
function Get-TareasDefinicion($Jobs, [bool]$ConservarAtascadas) {
  $porFichero = [ordered]@{}
  foreach ($j in $Jobs) {
    $d = Get-FicheroDefinicion $j
    if ($d.Motivo) { continue }
    if (-not $porFichero.Contains($d.Rel)) { $porFichero[$d.Rel] = @{ Lineas = $d.Lineas; Jobs = @() } }
    $porFichero[$d.Rel].Jobs += $j.nombre
  }
  $tareas = @()
  foreach ($rel in $porFichero.Keys) {
    $x = $porFichero[$rel]
    $huella = Get-Hash8 ($rel + '|' + ($x.Jobs -join ',') + '|' + ((Get-NombresClases) -join ','))
    $entradas = [pscustomobject]@{ fichero = $rel; desde = 1; hasta = $x.Lineas; jobs = @($x.Jobs); huella = $huella }
    $tareas += , (Restore-Tarea (New-TareaTipo 'definicion-job' ('definicion-' + (Get-Hash8 $rel)) '' 'datos/mapa.json' $entradas) $ConservarAtascadas)
  }
  return $tareas
}

# Las palabras enteras del texto de un fichero del original (para ver a quien nombra).
function Get-Palabras([string]$Rel) {
  if (-not $script:Palabras.ContainsKey($Rel)) {
    $p = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($m in [regex]::Matches([System.IO.File]::ReadAllText((Join-Ruta $LegacyRoot $Rel)), '\w+')) { [void]$p.Add($m.Value) }
    $script:Palabras[$Rel] = $p
  }
  return , $script:Palabras[$Rel]
}

# Las clases de un job: las semillas (Rel, Por: primero los pasos, luego el fichero que define el job) y, desde
# ellas, las clases del original cuyo nombre simple sale como palabra entera en su texto, hasta ProfundidadJob
# niveles. Las clases de $Ajenas (las de los pasos de los otros jobs) no entran ni se atraviesan. Devuelve las
# primeras ClasesPorJob que son .java del original ($Rutas), en el orden en que se encuentran.
function Get-ClasesJob($Semillas, $PorNombre, $Rutas, $Ajenas) {
  $nodos = New-Object System.Collections.Generic.List[object]
  $vistos = @{}
  foreach ($rel in $Ajenas.Keys) { $vistos[$rel] = $true }
  foreach ($s in $Semillas) {
    if (-not $vistos.ContainsKey($s.Rel)) { $vistos[$s.Rel] = $true; $nodos.Add([pscustomobject]@{ Rel = $s.Rel; Prof = 0; Por = $s.Por }) }
  }
  $nombres = @($PorNombre.Keys | Sort-Object)
  for ($i = 0; $i -lt $nodos.Count; $i++) {
    if ($nodos[$i].Prof -ge [int]$Cfg.ProfundidadJob) { continue }
    $palabras = Get-Palabras $nodos[$i].Rel
    foreach ($n in $nombres) {
      if (-not $palabras.Contains($n)) { continue }
      foreach ($rel in $PorNombre[$n]) {
        if (-not $vistos.ContainsKey($rel)) { $vistos[$rel] = $true; $nodos.Add([pscustomobject]@{ Rel = $rel; Prof = ($nodos[$i].Prof + 1); Por = 'referencia' }) }
      }
    }
  }
  return @($nodos | Where-Object { $Rutas.ContainsKey($_.Rel) } | Select-Object -First ([int]$Cfg.ClasesPorJob))
}

# El mapa: de cada job, sus pasos (los de la tarea de definicion, si esta hecha), sus clases y sus dudas; y los
# ficheros del original que no cuelgan de ningun job. Sin ningun job en el contrato, un solo job con el nombre
# del batch y las primeras clases del original.
function Get-Mapa($Jobs, $Tareas, [string]$Batch) {
  $script:Palabras = @{}
  $rutas = @{}
  $porNombre = @{}
  foreach ($f in @($Fuentes | Sort-Object FullName)) {
    $rel = Get-Rel $LegacyRoot $f.FullName
    $rutas[$rel] = $f.BaseName
    if ($porNombre.ContainsKey($f.BaseName)) { $porNombre[$f.BaseName] += $rel } else { $porNombre[$f.BaseName] = @($rel) }
  }
  $sinContrato = (@($Jobs).Count -eq 0)
  if ($sinContrato) { $Jobs = @([pscustomobject]@{ nombre = $Batch; definidoEn = '' }) }
  $lecturas = @()
  foreach ($j in $Jobs) {
    $d = Get-FicheroDefinicion $j
    $def = $null
    $dudas = @()
    if ($sinContrato) { $dudas += 'No se ha detectado ningun job en el original: se cuenta el batch entero como un solo job, sin pasos.' }
    else {
      $porque = $d.Motivo
      if (-not $porque) {
        $t = @($Tareas | Where-Object { $_.entradas.fichero -eq $d.Rel })[0]
        if ($t.estado -eq 'hecha') { $def = @($t.resultado.jobs | Where-Object { $_.job -ceq $j.nombre })[0] }
        if (-not $def) { $porque = 'la lectura del fichero que lo define se ha atascado' }
      }
      if ($porque) { $dudas += "No se han podido sacar los pasos de este job: $porque." }
    }
    $semillas = @()
    $pasos = @()
    $deLosPasos = @{}
    if ($sinContrato) { foreach ($rel in $rutas.Keys | Sort-Object) { $semillas += [pscustomobject]@{ Rel = $rel; Por = 'referencia' } } }
    if ($def) {
      foreach ($p in @($def.pasos)) {
        $pasos += [ordered]@{ paso = $p.paso; clases = @($p.clases) }
        foreach ($c in @($p.clases)) { foreach ($rel in @($porNombre[$c])) { if ($rel) { $semillas += [pscustomobject]@{ Rel = $rel; Por = 'paso' }; $deLosPasos[$rel] = $true } } }
      }
    }
    if ($d.Existe) { $semillas += [pscustomobject]@{ Rel = $d.Rel; Por = 'definicion' } }
    $lecturas += [pscustomobject]@{ Job = $j; D = $d; Def = $def; Dudas = $dudas; Semillas = $semillas; Pasos = $pasos; DeLosPasos = $deLosPasos }
  }
  $conJob = @{}
  $mapa = @()
  foreach ($x in $lecturas) {
    $ajenas = @{}
    foreach ($y in $lecturas) {
      if ($y.Job.nombre -cne $x.Job.nombre) { foreach ($rel in $y.DeLosPasos.Keys) { if (-not $x.DeLosPasos.ContainsKey($rel)) { $ajenas[$rel] = $true } } }
    }
    $clases = @()
    foreach ($n in @(Get-ClasesJob $x.Semillas $porNombre $rutas $ajenas)) {
      $ficha = 'clase-' + (Get-Hash8 $n.Rel)
      $clases += [ordered]@{ clase = $rutas[$n.Rel]; fichero = $n.Rel; ficha = $ficha; por = $n.Por; tieneFicha = (Test-Path -LiteralPath (Join-Path (Join-Path $Datos 'fichas') ($ficha + '.json'))) }
      $conJob[$n.Rel] = $true
    }
    $linea = 0
    $probado = $false
    if ($x.Def) { $linea = [int]$x.Def.linea; $probado = [bool]$x.Def.probado }
    $mapa += [ordered]@{ job = $x.Job.nombre; definidoEn = $x.D.Rel; linea = $linea; probado = $probado; pasos = $x.Pasos; clases = $clases; dudas = $x.Dudas }
  }
  $sinJob = @($rutas.Keys | Where-Object { -not $conJob.ContainsKey($_) } | Sort-Object)
  return [ordered]@{ jobs = $mapa; sinJob = $sinJob }
}

# ============================== FICHAS DE JOB ==============================
# El nombre del job vale para un fichero y para un id de tarea.
function Get-NombreJob([string]$Job) { return ($Job -replace '[^\w\.\-]', '-') }

function Get-RutaJob([string]$Job) { return (Join-Path (Join-Path $Datos 'jobs') ((Get-NombreJob $Job) + '.json')) }

# Las fichas de clase (las que existen) de las clases de un job, en el orden del mapa.
function Get-FichasJob($JobMapa) {
  $fichas = @()
  foreach ($c in @($JobMapa.clases)) {
    $ruta = Join-Path (Join-Path $Datos 'fichas') ($c.ficha + '.json')
    if (Test-Path -LiteralPath $ruta) { $fichas += Read-Json $ruta }
  }
  return $fichas
}

# Lo que lleva el prompt de la ficha de un job: Pasos (los del mapa) y Datos (de cada clase con ficha, lo que hace
# y sus datos con su referencia clase-xxxxxxxx#n, que es el lugar del dato en su ficha), las de los pasos primero,
# hasta CaracteresPorTarea. Fuera: las clases que no caben. Refs: cuantos datos hay en el prompt.
function Get-ContextoJob($JobMapa) {
  $pasos = @($JobMapa.pasos | ForEach-Object { '- ' + $_.paso + ' (clases: ' + (@($_.clases) -join ', ') + ')' })
  if ($pasos.Count -eq 0) { $pasos = @('(No se han podido sacar los pasos de este job: agrupa tu las clases en pasos con sentido para negocio.)') }
  $texto = ''   # no se llama $datos: taparia el $Datos del script a las funciones que llama
  $fuera = @()
  $refs = 0
  foreach ($f in @(Get-FichasJob $JobMapa)) {
    $b = "### $($f.clase) ($($f.id), $($f.papel)): $($f.queHace -replace '\s+', ' ')`n"
    $n = 0
    foreach ($d in @($f.datos)) { $b += "$($f.id)#$n [$($d.tipo)] $($d.texto -replace '\s+', ' ')`n"; $n++ }
    if (($texto.Length + $b.Length) -gt [int]$Cfg.CaracteresPorTarea) { $fuera += $f.clase; continue }
    $texto += $b + "`n"
    $refs += $n
  }
  return [pscustomobject]@{ Pasos = ($pasos -join "`n"); Datos = $texto.TrimEnd(); Fuera = $fuera; Refs = $refs }
}

# Una tarea de ficha de job por cada job del mapa que tenga algun dato que contar.
function Get-TareasJob($Mapa, [bool]$ConservarAtascadas) {
  $tareas = @()
  foreach ($j in @($Mapa.jobs)) {
    $c = Get-ContextoJob $j
    if ($c.Refs -eq 0) { continue }
    $entradas = [pscustomobject]@{ job = $j.job; pasos = $c.Pasos; datos = $c.Datos; fuera = @($c.Fuera); huella = (Get-Hash8 ($c.Pasos + "`n" + $c.Datos)) }
    $tareas += , (Restore-Tarea (New-TareaTipo 'ficha-job' ('job-' + (Get-NombreJob $j.job)) '' ('datos/jobs/' + (Get-NombreJob $j.job) + '.json') $entradas) $ConservarAtascadas)
  }
  return $tareas
}

# Las listas de un job que monta el script con los datos de las fichas de sus clases (ListasJob: a que lista va
# cada tipo de dato), sin repetir: mismo tipo y mismo texto sin contar espacios ni mayusculas. Un dato cuyo texto no
# pasa Test-LenguajeNegocio lleva tecnico = $true: sigue en la lista, pero las paginas de negocio no lo pintan.
function Get-ListasJob($JobMapa) {
  $listas = [ordered]@{}
  foreach ($k in $Cfg.ListasJob.Keys) { $listas[$k] = @() }
  $vistos = @{}
  foreach ($f in @(Get-FichasJob $JobMapa)) {
    $n = -1
    foreach ($d in @($f.datos)) {
      $n++
      $clave = $d.tipo + '|' + (($d.texto -replace '\s', '').ToLowerInvariant())
      if ($vistos.ContainsKey($clave)) { continue }
      foreach ($k in $Cfg.ListasJob.Keys) {
        if ($Cfg.ListasJob[$k] -ccontains $d.tipo) {
          $vistos[$clave] = $true
          $x = [ordered]@{ tipo = $d.tipo; texto = $d.texto; ref = "$($f.id)#$n"; clase = $f.clase; fichero = $f.fichero; linea = $d.linea; cita = $d.cita; probado = $d.probado }
          if (Test-LenguajeNegocio @{ texto = $d.texto }) { $x['tecnico'] = $true }
          $listas[$k] += $x
        }
      }
    }
  }
  return $listas
}

# Escribe datos\jobs\<job>.json de cada job cuya redaccion ha acabado (hecha o atascada, tenga tarea o no):
# lo que dijo el modelo y, siempre, las listas del script.
function Save-Jobs($Mapa, $Tareas) {
  foreach ($j in @($Mapa.jobs)) {
    $t = @($Tareas | Where-Object { $_.entradas.job -ceq $j.job })[0]
    if ($t -and $t.estado -eq 'pendiente') { continue }
    $hecha = ($t -and $t.estado -eq 'hecha')
    $dudas = @()
    $o = [ordered]@{ job = $j.job }
    if ($hecha) { $o['titulo'] = $t.resultado.titulo; $o['paraQue'] = $t.resultado.paraQue; $o['pasos'] = @($t.resultado.pasos); $dudas += @($t.resultado.dudas) }
    else { $dudas += 'No se ha podido redactar este job: la tarea ha quedado atascada o no hay datos de clases que contar.' }
    foreach ($e in (Get-ListasJob $j).GetEnumerator()) { $o[$e.Key] = @($e.Value) }
    $o['sinFicha'] = @(@($j.clases | Where-Object { -not (Test-Path -LiteralPath (Join-Path (Join-Path $Datos 'fichas') ($_.ficha + '.json'))) }) | ForEach-Object { $_.clase })
    # las clases que no caben en la redaccion nombran clases: van aparte, no a dudas (que pinta la pagina de negocio)
    $o['fuera'] = @(if ($t) { $t.entradas.fuera })
    $o['dudas'] = $dudas
    if ($hecha) { $o['redaccion'] = 'hecha' } else { $o['redaccion'] = 'atascada' }
    Write-Json (Get-RutaJob $j.job) $o
  }
}

# ================================== RESUMEN ==================================
# La tarea del resumen: de cada job del mapa, el titulo, el para que y los pasos de su redaccion, si esta hecha
# (si no, solo su nombre). Sin ninguna redaccion hecha no hay tarea.
function Get-TareasResumen($Mapa, [bool]$ConservarAtascadas) {
  $bloques = @()
  $hechas = 0
  foreach ($j in @($Mapa.jobs)) {
    $b = "JOB: $($j.job)`n"
    $ruta = Get-RutaJob $j.job
    $f = $null
    if (Test-Path -LiteralPath $ruta) { $f = Read-Json $ruta }
    if ($f -and $f.redaccion -eq 'hecha') {
      $hechas++
      $b += "TITULO: $($f.titulo)`nPARA QUE: $($f.paraQue -replace '\s+', ' ')`nPASOS: " + ((@($f.pasos) | ForEach-Object { $_.titulo }) -join '; ') + "`n"
    }
    else { $b += "(Sin redaccion: de este job solo se sabe el nombre.)`n" }
    $bloques += $b
  }
  if ($hechas -eq 0) { return @() }
  $texto = ($bloques -join "`n").TrimEnd()
  $entradas = [pscustomobject]@{ jobs = @($Mapa.jobs | ForEach-Object { $_.job }); datos = $texto; huella = (Get-Hash8 $texto) }
  return @(Restore-Tarea (New-TareaTipo 'resumen' 'resumen' '' 'datos/resumen.json' $entradas) $ConservarAtascadas)
}

# ============================== VARIABLES ==============================
# Cada ${NOMBRE} y ${NOMBRE:valor} de los application*.yml, .yaml y .properties de src/main/resources del
# worktree (sin las lineas de comentario): variable, porDefecto (null si no lleva), fichero y linea.
function Get-Variables {
  $res = @()
  $dir = Join-Ruta $RepoRoot 'src/main/resources'
  if (-not (Test-Path -LiteralPath $dir)) { return $res }
  foreach ($f in @(Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.Name -match '^application.*\.(yml|yaml|properties)$' } | Sort-Object Name)) {
    $lineas = [System.IO.File]::ReadAllLines($f.FullName)
    for ($i = 0; $i -lt $lineas.Count; $i++) {
      if ($lineas[$i].TrimStart().StartsWith('#')) { continue }
      foreach ($m in [regex]::Matches($lineas[$i], '\$\{([\w\.\-]+)(?::([^}]*))?\}')) {
        $defecto = $null
        if ($m.Groups[2].Success) { $defecto = $m.Groups[2].Value }
        $res += [ordered]@{ variable = $m.Groups[1].Value; porDefecto = $defecto; fichero = ('src/main/resources/' + $f.Name); linea = ($i + 1) }
      }
    }
  }
  return $res
}

# =============================== PRUEBA EN PRE ===============================
# Los hechos que recibe la prueba de un job, con su referencia (clase-xxxxxxxx#n): los que citan los pasos de su ficha
# si la redaccion esta hecha, o todos los del job si no, hasta CaracteresPorTarea. Pasos: titulo y texto de cada paso de
# la ficha (nada que nombre clases); Datos: una linea por hecho; ACubrir: cuantos son de tipo regla o error.
function Get-ContextoPrueba($JobMapa) {
  $todos = [ordered]@{}
  foreach ($f in @(Get-FichasJob $JobMapa)) {
    $n = 0
    foreach ($d in @($f.datos)) { $todos["$($f.id)#$n"] = [pscustomobject]@{ ref = "$($f.id)#$n"; tipo = $d.tipo; texto = ($d.texto -replace '\s+', ' ') }; $n++ }
  }
  $ficha = $null
  if (Test-Path -LiteralPath (Get-RutaJob $JobMapa.job)) { $ficha = Read-Json (Get-RutaJob $JobMapa.job) }
  $pasos = '(La redaccion de este job no esta hecha: no hay pasos. Te apoyas solo en los hechos de abajo, que son todos los que se conocen del job.)'
  $refs = @($todos.Keys)
  if ($ficha -and $ficha.redaccion -eq 'hecha') {
    $i = 0
    $pasos = (@($ficha.pasos | ForEach-Object { $i++; "$i. $($_.titulo): $($_.texto -replace '\s+', ' ')" }) -join "`n")
    $citadas = @()
    foreach ($p in @($ficha.pasos)) { foreach ($r in @($p.refs)) { if ($todos.Contains($r) -and ($citadas -cnotcontains $r)) { $citadas += $r } } }
    $refs = $citadas
  }
  $texto = ''
  $aCubrir = 0
  foreach ($r in $refs) {
    $h = $todos[$r]
    $linea = "$($h.ref) [$($h.tipo)] $($h.texto)`n"
    if (($texto.Length + $linea.Length) -gt [int]$Cfg.CaracteresPorTarea) { break }
    $texto += $linea
    if ($h.tipo -ceq 'regla' -or $h.tipo -ceq 'error') { $aCubrir++ }
  }
  return [pscustomobject]@{ Pasos = $pasos; Datos = $texto.TrimEnd(); ACubrir = $aCubrir }
}

# Una tarea de prueba en pre por cada job con alguna regla o error entre los hechos que recibe. Los demas no llaman al
# modelo: su guion lo monta el script (Save-Pruebas).
function Get-TareasPrueba($Mapa, [bool]$ConservarAtascadas) {
  $vars = @()
  $rutaVars = Join-Path $Datos 'variables.json'
  if (Test-Path -LiteralPath $rutaVars) { $vars = @(@(Read-Json $rutaVars) | ForEach-Object { $_.variable } | Select-Object -Unique) }
  $nombres = '(Este batch no usa variables de configuracion.)'
  if ($vars.Count -gt 0) { $nombres = ($vars -join ', ') }
  $tareas = @()
  foreach ($j in @($Mapa.jobs)) {
    $c = Get-ContextoPrueba $j
    if ($c.ACubrir -eq 0) { continue }
    $entradas = [pscustomobject]@{ job = $j.job; pasos = $c.Pasos; datos = $c.Datos; variables = $nombres; huella = (Get-Hash8 ($c.Pasos + "`n" + $c.Datos + "`n" + $nombres)) }
    $n = Get-NombreJob $j.job
    $tareas += , (Restore-Tarea (New-TareaTipo 'prueba-pre' ('prueba-' + $n) '' ('datos/pruebas/' + $n + '.json') $entradas) $ConservarAtascadas)
  }
  return $tareas
}

# El guion que monta el script sin IA, de las listas del job: "Antes de lanzarlo" con lo que necesita, "Que mirar al
# acabar" con lo que produce y, con $ConCasos, un caso por regla (su texto de titulo; entrada y esperado, vacios).
# Es texto para negocio: no usa los datos tecnicos de las listas.
function Get-GuionMinimo($JobMapa, [bool]$ConCasos) {
  $l = Get-ListasJob $JobMapa
  foreach ($k in @($l.Keys)) { $l[$k] = @($l[$k] | Where-Object { -not $_.tecnico }) }
  $casos = @()
  if ($ConCasos) { $casos = @($l['reglas'] | ForEach-Object { [ordered]@{ titulo = $_.texto; entrada = ''; esperado = ''; refs = @($_.ref) } }) }
  return [ordered]@{
    preparar = @($l['necesita'] | ForEach-Object { [ordered]@{ texto = $_.texto; refs = @($_.ref) } })
    casos = $casos
    comprobar = @($l['produce'] | ForEach-Object { [ordered]@{ texto = $_.texto; refs = @($_.ref) } })
  }
}

# Escribe datos\pruebas\<job>.json de cada job de la fase: lo que dijo el modelo si la tarea esta hecha (con sinCaso),
# el guion minimo si esta atascada y, sin tarea, el guion minimo de lo que necesita y produce. redaccion: hecha | atascada.
function Save-Pruebas($Mapa, $Tareas) {
  foreach ($j in @($Mapa.jobs)) {
    $t = @($Tareas | Where-Object { $_.entradas.job -ceq $j.job })[0]
    if ($t -and $t.estado -eq 'pendiente') { continue }
    $o = [ordered]@{ job = $j.job }
    if ($t -and $t.estado -eq 'hecha') {
      $o['preparar'] = @($t.resultado.preparar); $o['casos'] = @($t.resultado.casos); $o['comprobar'] = @($t.resultado.comprobar); $o['sinCaso'] = @($t.resultado.sinCaso); $o['redaccion'] = 'hecha'
    }
    else {
      $atascada = ($null -ne $t)
      foreach ($e in (Get-GuionMinimo $j $atascada).GetEnumerator()) { $o[$e.Key] = $e.Value }
      $o['sinCaso'] = @()
      if ($atascada) { $o['redaccion'] = 'atascada' } else { $o['redaccion'] = 'hecha' }
    }
    Write-Json (Join-Path (Join-Path $Datos 'pruebas') ((Get-NombreJob $j.job) + '.json')) $o
  }
}

# ======================= EL ORIGINAL FRENTE AL MIGRADO =======================
# Las palabras del nombre de una clase: sus partes en mayuscula de cuatro letras o mas (GestorRecibos -> Gestor, Recibos).
function Get-PalabrasClase([string]$Nombre) {
  return @([regex]::Matches($Nombre, '\p{Lu}\p{Ll}{3,}') | ForEach-Object { $_.Value } | Select-Object -Unique)
}

# Los ficheros del migrado (de $Java, los .java del worktree) que lee la comparacion de una clase del original: los que se
# llaman como ella; si no hay ninguno, los que comparten alguna palabra de su nombre, los que mas primero y luego por ruta.
# FicherosComparar como mucho. Sin ninguno, la clase no se compara con IA.
function Select-FicherosMigrado([string]$Clase, $Java) {
  $mismos = @($Java | Where-Object { $_.BaseName -ceq $Clase } | ForEach-Object { Get-Rel $RepoRoot $_.FullName } | Sort-Object)
  if ($mismos.Count -gt 0) { return @($mismos | Select-Object -First ([int]$Cfg.FicherosComparar)) }
  $palabras = @(Get-PalabrasClase $Clase)
  $candidatos = @()
  foreach ($f in $Java) {
    $comunes = @(Get-PalabrasClase $f.BaseName | Where-Object { $palabras -ccontains $_ }).Count
    if ($comunes -gt 0) { $candidatos += [pscustomobject]@{ N = $comunes; Rel = (Get-Rel $RepoRoot $f.FullName) } }
  }
  return @($candidatos | Sort-Object @{ Expression = 'N'; Descending = $true }, Rel | Select-Object -First ([int]$Cfg.FicherosComparar) | ForEach-Object { $_.Rel })
}

# Una tarea por ficha de clase con datos. Los ficheros del migrado los elige el script y quedan en las entradas de la tarea. Sin ninguno
# no hay llamada: la tarea nace hecha, con todos sus datos 'sin-pieza'. La huella es la de los datos de la ficha, no la de las rutas:
# una tarea hecha sigue valiendo aunque la correccion mueva ficheros del worktree.
function Get-TareasComparar([bool]$ConservarAtascadas) {
  $java = @(Get-JavaOriginal $RepoRoot)
  $tareas = @()
  foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $Datos 'fichas') -File -Filter 'clase-*.json' | Sort-Object Name)) {
    $x = Read-Json $f.FullName
    $lista = @($x.datos)
    if ($lista.Count -eq 0) { continue }
    $lineas = @()
    for ($k = 0; $k -lt $lista.Count; $k++) {
      $lineas += "$k. [$($lista[$k].tipo)] $($lista[$k].texto)"
      $lineas += "   Original: $($x.fichero):$($lista[$k].linea) | cita: $($lista[$k].cita)"
    }
    $texto = $lineas -join "`n"
    $migrado = @(Select-FicherosMigrado $x.clase $java)
    $entradas = [pscustomobject]@{ clase = $x.clase; fichero = $x.fichero; migrado = $migrado; ndatos = $lista.Count; datos = $texto; huella = (Get-Hash8 $texto) }
    $t = New-TareaTipo 'comparar-pieza' ('comparar-' + $x.id) $x.id ('datos/comparacion/' + $x.id + '.json') $entradas
    if ($migrado.Count -eq 0) {
      $t.estado = 'hecha'
      $t.resultado = [ordered]@{ comparacion = @(0..($lista.Count - 1) | ForEach-Object { [ordered]@{ dato = $_; estado = 'sin-pieza'; fichero = ''; linea = 0; cita = ''; nota = ''; probado = $false } }) }
    }
    $tareas += , (Restore-Tarea $t $ConservarAtascadas)
  }
  return $tareas
}

# Comprueba lo que ha escrito Copilot: un elemento por dato (cada numero una vez), con su estado; en igual y distinto, uno de los
# ficheros dados con linea y cita (la cita se busca en ese fichero del worktree); nota en distinto y no-lo-se.
function Test-Comparar($T, [string]$Dir) {
  $s = Read-Salida $T $Dir
  if (-not $s.Ok) { return $s }
  $o = $s.Ficha
  if ($o.comparacion -isnot [array]) { return (New-Resultado $false "Falta el campo 'comparacion': una lista con un elemento por dato." $null) }
  $n = [int]$T.entradas.ndatos
  $lista = @()
  $i = 0
  foreach ($c in $o.comparacion) {
    $pre = "comparacion[$i]"
    if ($c -isnot [System.Management.Automation.PSCustomObject]) { return (New-Resultado $false "$pre tiene que ser un objeto con dato, estado, fichero, linea, cita y nota." $null) }
    $numero = (($c.dato -is [int]) -or ($c.dato -is [long]) -or (($c.dato -is [double]) -and ($c.dato -eq [math]::Floor($c.dato))))
    if (-not $numero -or $c.dato -lt 0 -or $c.dato -ge $n) { return (New-Resultado $false "$pre.dato tiene que ser el numero de un dato, de 0 a $($n - 1)." $null) }
    if ($Cfg.EstadosComparar -cnotcontains $c.estado) { return (New-Resultado $false ("$pre.estado vale '$($c.estado)' y tiene que ser uno de: " + ($Cfg.EstadosComparar -join ', ') + '.') $null) }
    $x = [ordered]@{ dato = [int]$c.dato; estado = $c.estado; fichero = ''; linea = 0; cita = ''; nota = ''; probado = $false }
    if ($c.estado -ceq 'igual' -or $c.estado -ceq 'distinto') {
      if (@($T.entradas.migrado) -cnotcontains $c.fichero) { return (New-Resultado $false ("$pre.fichero vale '$($c.fichero)' y tiene que ser uno de: " + (@($T.entradas.migrado) -join ', ') + '.') $null) }
      $m = Test-LineaCita $c $pre
      if ($m) { return (New-Resultado $false $m $null) }
      $x.fichero = $c.fichero; $x.linea = [int]$c.linea; $x.cita = $c.cita
    }
    if (Test-Texto $c.nota) { $x.nota = $c.nota }
    elseif ($c.estado -ceq 'distinto' -or $c.estado -ceq 'no-lo-se') { return (New-Resultado $false "$pre.nota falta o esta vacia: en $($c.estado) cuenta que cambia o por que no puedes decidirlo." $null) }
    $lista += $x
    $i++
  }
  $m = Compare-Nombres @(0..($n - 1) | ForEach-Object { "$_" }) @($lista | ForEach-Object { "$($_.dato)" }) 'comparacion (el campo dato de cada elemento)'
  if ($m) { return (New-Resultado $false $m $null) }
  # las citas: cada una en su fichero; si mas de la mitad de todas no salen, se rechaza
  $conCita = @($lista | Where-Object { $_.cita })
  $inventadas = @()
  foreach ($g in @($conCita | Group-Object { $_.fichero })) {
    $ruta = Join-Ruta $Dir $g.Name
    if (Test-Path -LiteralPath $ruta) { $inventadas += @(Set-CitasProbadas $g.Group $ruta) }
    else { $inventadas += @($g.Group | ForEach-Object { $_.cita }) }
  }
  if (($inventadas.Count * 2) -gt $conCita.Count) {
    return (New-Resultado $false "Mas de la mitad de las citas ($($inventadas.Count) de $($conCita.Count)) no salen en los ficheros del migrado, por ejemplo: '$($inventadas[0])'. Copia las citas tal cual del codigo y no inventes ninguna." $null)
  }
  return (New-Resultado $true '' ([ordered]@{ comparacion = @($lista | Sort-Object { $_.dato }) }))
}

# Escribe datos\comparacion\<ficha>.json de cada tarea hecha: la clase, su fichero del original, los del migrado y, por dato, lo que se dijo.
function Save-Comparaciones($Tareas) {
  foreach ($t in @($Tareas | Where-Object { $_.estado -eq 'hecha' })) {
    $o = [ordered]@{ ficha = $t.ficha; clase = $t.entradas.clase; ficheroOriginal = $t.entradas.fichero; migrado = @($t.entradas.migrado); datos = @($t.resultado.comparacion) }
    Write-Json (Join-Path (Join-Path $Datos 'comparacion') ($t.ficha + '.json')) $o
  }
}

# ============================== COBERTURA ==============================
# La cobertura de lineas de los tests del migrado ($Dir, el worktree), con JaCoCo por coordenadas y sin tocar el pom: un solo Maven
# (prepare-agent, test y report) con su salida en $Registro. Lee target\site\jacoco\jacoco.csv por el nombre de sus columnas y suma
# todas las filas. Sin medida (medida false y porcentaje nulo) el motivo dice por que: nunca sale un 0 % que no se ha medido.
# Con $Compila en $false (el diagnostico dice que no compila) no lanza Maven.
function Get-Cobertura([string]$Dir, [string]$Registro, [bool]$Compila) {
  $o = [ordered]@{ medida = $false; porcentaje = $null; cubiertas = $null; total = $null; minima = $Cfg.CoberturaMinima; motivo = '' }
  if (-not $Compila) { $o.motivo = 'el migrado no compila'; return $o }
  $csv = Join-Ruta $Dir 'target/site/jacoco/jacoco.csv'
  if (Test-Path -LiteralPath $csv) { Remove-Item -LiteralPath $csv -Force }
  $j = $Cfg.JacocoPlugin
  $latido = Start-Latido 'Maven (cobertura)' $Cfg.SegundosLatido
  try { $r = Invoke-Nativo (Get-Mvn $Dir) @('-B', "${j}:prepare-agent", 'test', "${j}:report") $Dir }
  finally { Stop-Latido $latido }
  [System.IO.File]::WriteAllText($Registro, ((@($r.Salida) -join "`n") + "`n"), $Utf8)
  if ($r.Codigo -ne 0) {
    $e = @($r.Salida | Where-Object { "$_" -match '^\[ERROR\]\s*\S' } | Select-Object -First 1)
    $o.motivo = "Maven ha salido con error (codigo $($r.Codigo))"
    if ($e.Count -gt 0) { $o.motivo = 'Maven ha salido con error: ' + ("$($e[0])" -replace '^\[ERROR\]\s*', '').Trim() }
    return $o
  }
  if (-not (Test-Path -LiteralPath $csv)) { $o.motivo = 'Maven no ha dejado target/site/jacoco/jacoco.csv: hay tests?'; return $o }
  $lineas = @([System.IO.File]::ReadAllLines($csv, $Utf8) | Where-Object { $_.Trim() })
  $cab = @()
  if ($lineas.Count -gt 0) { $cab = @($lineas[0] -split ',' | ForEach-Object { $_.Trim().Trim('"') }) }
  if (($cab -cnotcontains 'LINE_MISSED') -or ($cab -cnotcontains 'LINE_COVERED')) { $o.motivo = 'el CSV de JaCoCo no tiene las columnas LINE_MISSED y LINE_COVERED'; return $o }
  $faltan = [long]0
  $cubiertas = [long]0
  try { foreach ($f in @($lineas | ConvertFrom-Csv)) { $faltan += [long]$f.LINE_MISSED; $cubiertas += [long]$f.LINE_COVERED } }
  catch { $o.motivo = 'el CSV de JaCoCo no se puede leer: ' + $_.Exception.Message; return $o }
  if ($faltan + $cubiertas -eq 0) { $o.motivo = 'ninguna linea medible'; return $o }
  $o.medida = $true
  $o.cubiertas = $cubiertas
  $o.total = $faltan + $cubiertas
  $o.porcentaje = [math]::Round(100.0 * $cubiertas / $o.total, 1, [System.MidpointRounding]::AwayFromZero)
  return $o
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
