<#
tareas.ps1 - Las piezas de migracion.ps1 que no son el arranque: las llamadas a Copilot
en paralelo, las tareas (ficha de clase, definicion de job, ficha de job, resumen, prueba en pre y comparacion con el
migrado) con su comprobacion, el mapa de jobs, las variables del migrado y la prueba de aptitud.
Se carga con '. (Join-Path $PSScriptRoot 'tareas.ps1')' despues de comun.ps1, desde
migracion.ps1 o desde cualquier script que necesite lo mismo (un preflight) sin pasar
por el arranque. Cargarlo no ejecuta nada. Solo ASCII a proposito.
Necesita la carpeta tareas\ (plantilla del prompt y fichero de la prueba) junto a este script.

DEFINE al cargarse: las claves de $Cfg de abajo (CONFIGURACION: Paralelo,
SegundosPorLlamada, Intentos, LineasPorTarea, CitaMax, CitaCerca, EsfuerzoLectura,
EsfuerzoRedaccion, EsfuerzoReintento, CaracteresPorTarea, ClasesPorJob, ProfundidadJob,
PasosDefinicionMax, PasosFichaMax, GlosarioMax, ResumenCaracteresJob, ResumenCaracteresDato, RellenoProhibido, CasosMax, FicherosComparar, EstadosComparar, ListasJob, Papeles, TiposDato y JavaExe) y
las funciones. El lanzador de programas (Get-Lanzador y lo que usa), $Utf8 y la cobertura (Get-Cobertura, JacocoPlugin y CoberturaMinima) son de comun.ps1.

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
  ResumenCaracteresJob = 1500  # lo que se le da al resumen de cada job: sus listas (lo que necesita, deja, envia y sus reglas), todas juntas
  ResumenCaracteresDato = 160  # una linea de esas listas se corta a esto
  # Frases que no dicen nada: un texto que las lleva no vale (sin mayusculas ni acentos, solo palabras enteras)
  RellenoProhibido   = @('de forma clara', 'clara y ordenada', 'de manera eficiente', 'toda la informacion disponible', 'facilita', 'garantiza', 'optimiza',
    'listo para revisarse', 'las personas responsables', 'diversos', 'distintos procesos')
  CasosMax           = 40     # casos de la prueba en pre de un job
  FicherosComparar   = 3      # ficheros del migrado que se le dan a la comparacion de una clase del original
  EstadosComparar    = @('igual', 'distinto', 'falta', 'no-lo-se')   # lo que puede decir la IA de un dato (sin-pieza lo pone el script)
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

# Una llamada por elemento de $Lote (Id, Dir, Prompt, Modelo, Esfuerzo, Dirs: las carpetas que puede leer y, si lo lleva, JavaHome:
# el JAVA_HOME con el que arranca Copilot, para los mvn que ejecuta la IA), todas a la vez.
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
    $antes = $env:JAVA_HOME
    try {
      if ($it.JavaHome) { $env:JAVA_HOME = $it.JavaHome }
      $vivos += , (Start-Llamada $it.Dir (Get-ArgsCopilot $texto $it.Modelo $it.Esfuerzo @($it.Dirs) $true))
    }
    finally { $env:JAVA_HOME = $antes }
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

# Las frases de relleno que no valen, para el prompt: entre comillas y separadas por comas.
function Get-TextoRelleno { return ((@($Cfg.RellenoProhibido) | ForEach-Object { '"' + $_ + '"' }) -join ', ') }

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
    'ficha-job' { $v.JOB = $e.job; $v.PASOS = $e.pasos; $v.DATOS = $e.datos; $v.PASOS_MAX = "$($Cfg.PasosFichaMax)"; $v.RELLENO = Get-TextoRelleno }
    'prueba-pre' { $v.JOB = $e.job; $v.PASOS = $e.pasos; $v.DATOS = $e.datos; $v.VARIABLES = $e.variables; $v.CASOS_MAX = "$($Cfg.CasosMax)" }
    'caso-pre' { $v.JOB = $e.job; $v.PASOS = $e.pasos; $v.DATOS = $e.datos; $v.REGLA = $e.regla; $v.REGLA_REF = $e.ref; $v.GUION = $e.guion }
    'resumen' { $v.JOBS = $e.datos; $v.GLOSARIO_MAX = "$($Cfg.GlosarioMax)"; $v.RELLENO = Get-TextoRelleno }
    'ficha-sh' {
      $v.SCRIPT = $e.script; $v.TEXTO = $e.texto; $v.INVENTARIO = $e.inventario; $v.OBLIGATORIAS = $e.obligatorias; $v.JOB = $e.job
      $v.RELLENO = Get-TextoRelleno
    }
    'comparar-sh' {
      $v.SCRIPT = $e.script; $v.DATOS = $e.datos
      $v.MIGRADO = ((@($e.migrado) | ForEach-Object { "MIGRADO: $_" }) -join "`n")
    }
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

# Las frases de relleno (RellenoProhibido) que lleva cada texto: sin mayusculas ni acentos y solo como palabras enteras
# ('facilita' no salta con 'facilitara'). Devuelve '' si no hay ninguna; si la hay, el motivo, que pide el dato concreto.
function Test-Relleno($Campos) {
  $mal = @()
  foreach ($k in $Campos.Keys) {
    $plano = ConvertTo-Plano ([string]$Campos[$k])
    foreach ($f in @($Cfg.RellenoProhibido)) {
      if ($plano -match ('(?<![\p{L}\p{N}])' + [regex]::Escape((ConvertTo-Plano $f)) + '(?![\p{L}\p{N}])')) { $mal += "$k lleva '$f'" }
    }
  }
  if ($mal.Count -eq 0) { return '' }
  return ('Hay frases de relleno, que no cuentan nada: ' + ($mal -join '; ') + '. Cambialas por el dato concreto (que datos lee y de donde, que hace con ellos, que deja y a quien le llega). Si ese dato no esta en lo que te he dado, escribe: no consta.')
}

function ConvertTo-Plano([string]$Texto) {
  return ([regex]::Replace($Texto.Normalize([System.Text.NormalizationForm]::FormD), '\p{Mn}', '')).ToLowerInvariant()
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
  $m = Test-Relleno $campos
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
  $m = Test-Relleno $campos
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

# Comprueba el caso de una regla sin caso (entradas.ref es la regla; entradas.datos, los hechos con su referencia; entradas.titulos, los
# titulos de los casos que ya hay): titulo, entrada y esperado con texto; refs con al menos una referencia, todas de los hechos (o la de la
# regla), y la de la regla entre ellas; sin nombres de clase; y un titulo que no repita (sin mayusculas ni espacios de mas) el de un caso.
function Test-CasoPre($T, [string]$Dir) {
  $s = Read-Salida $T $Dir
  if (-not $s.Ok) { return $s }
  $o = $s.Ficha
  $campos = [ordered]@{}
  foreach ($c in @('titulo', 'entrada', 'esperado')) {
    if (-not (Test-Texto $o.$c)) { return (New-Resultado $false "Falta el campo '$c' (o esta vacio)." $null) }
    $campos[$c] = $o.$c
  }
  if (($o.refs -isnot [array]) -or @($o.refs).Count -eq 0) { return (New-Resultado $false "El campo 'refs' tiene que ser una lista con al menos una referencia: la de la regla, $($T.entradas.ref)." $null) }
  $validas = @{ $T.entradas.ref = $true }
  foreach ($m in [regex]::Matches([string]$T.entradas.datos, '(?m)^(clase-[0-9a-f]{8}#\d+) \[')) { $validas[$m.Groups[1].Value] = $true }
  $malas = @($o.refs | Where-Object { ($_ -isnot [string]) -or -not $validas.ContainsKey($_) })
  if ($malas.Count -gt 0) { return (New-Resultado $false "refs lleva referencias que no estan en los hechos de arriba: $(@($malas | ForEach-Object { "$_" }) -join ', '). Copia las referencias tal cual." $null) }
  if (@($o.refs) -cnotcontains $T.entradas.ref) { return (New-Resultado $false "refs tiene que llevar la referencia de la regla que falta: $($T.entradas.ref) ($($T.entradas.regla -replace '^\S+ \[[^\]]*\] ', ''))." $null) }
  $repetido = @($T.entradas.titulos | Where-Object { (ConvertTo-Plano ([string]$_).Trim()) -ceq (ConvertTo-Plano $o.titulo.Trim()) })
  if ($repetido.Count -gt 0) { return (New-Resultado $false "El titulo '$($o.titulo)' es el de un caso que ya hay en el guion ('$($repetido[0])'): ponle uno que diga que prueba este." $null) }
  $m = Test-LenguajeNegocio $campos
  if ($m) { return (New-Resultado $false $m $null) }
  return (New-Resultado $true '' ([ordered]@{ ref = $T.entradas.ref; caso = [ordered]@{ titulo = $o.titulo; entrada = $o.entrada; esperado = $o.esperado; refs = @($o.refs) } }))
}

# Comprueba lo que ha escrito Copilot segun el tipo de la tarea.
function Test-Salida($T, [string]$Dir, [string]$Leer) {
  switch ($T.tipo) {
    'definicion-job' { return (Test-DefinicionJob $T $Dir $Leer) }
    'ficha-job' { return (Test-FichaJob $T $Dir) }
    'resumen' { return (Test-Resumen $T $Dir) }
    'prueba-pre' { return (Test-PruebaPre $T $Dir) }
    'caso-pre' { return (Test-CasoPre $T $Dir) }
    'comparar-pieza' { return (Test-Comparar $T $Dir) }
    'ficha-sh' { return (Test-FichaSh $T $Dir) }
    'comparar-sh' { return (Test-CompararSh $T $Dir) }
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

# Cuantas tareas hay hechas, atascadas y pendientes.
function Get-CuentasTareas($Tareas) {
  $n = @{}
  foreach ($e in @('hecha', 'atascada', 'pendiente')) { $n[$e] = @($Tareas | Where-Object { $_.estado -eq $e }).Count }
  return $n
}

function Save-Tarea($T) { Write-Json (Join-Path (Join-Path $Datos 'tareas') ($T.id + '.json')) $T }

# La tarea que hay guardada con ese id (de un lanzamiento anterior), o $null si no hay o no se puede leer.
function Get-TareaGuardada([string]$Id) {
  $f = Join-Path (Join-Path $Datos 'tareas') ($Id + '.json')
  if (-not (Test-Path -LiteralPath $f)) { return $null }
  try { return (Read-Json $f) } catch { return $null }
}

# Guarda la tarea y devuelve la que queda: la de un lanzamiento anterior si esta hecha (o atascada, con
# $ConservarAtascadas) y sus entradas siguen siendo las mismas (huella); si no, la nueva.
function Restore-Tarea($T, [bool]$ConservarAtascadas) {
  $p = Get-TareaGuardada $T.id
  if ($p -and ($p.estado -eq 'hecha' -or ($ConservarAtascadas -and $p.estado -eq 'atascada')) -and $p.entradas.huella -eq $T.entradas.huella) { $T = $p }
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
    elseif ($t.tipo -eq 'comparar-sh') { $esf = $Cfg.EsfuerzoLectura }   # lee los ficheros del migrado, que ya son su carpeta de trabajo
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
# Las listas de un job que se le dan al resumen, de datos\jobs\<job>.json: lo que necesita, lo que deja, a quien lo envia y sus reglas,
# un dato por linea (sin los tecnicos, que nombran clases) y cada linea cortada a ResumenCaracteresDato. Entre las cuatro, hasta
# ResumenCaracteresJob caracteres: se reparte dato a dato (el primero de cada lista, luego el segundo...) para que ninguna se quede sin sitio.
# Una lista sin datos dice "no consta".
function Get-ListasResumen([string]$Job) {
  $cab = [ordered]@{ necesita = 'NECESITA'; produce = 'DEJA'; conexiones = 'SE ENVIA A'; reglas = 'REGLAS' }
  $ruta = Get-RutaJob $Job
  $f = $null
  if (Test-Path -LiteralPath $ruta) { $f = Read-Json $ruta }
  $lineas = [ordered]@{}
  $cogidas = @{}
  $gastado = 0
  foreach ($k in $cab.Keys) {
    $lineas[$k] = @()
    $cogidas[$k] = @()
    if ($f) {
      foreach ($x in @($f.$k)) {
        if ($x -and -not $x.tecnico -and (Test-Texto $x.texto)) {
          $l = ($x.texto -replace '\s+', ' ').Trim()
          if ($l.Length -gt [int]$Cfg.ResumenCaracteresDato) { $l = $l.Substring(0, [int]$Cfg.ResumenCaracteresDato - 3) + '...' }
          $lineas[$k] += ('- ' + $l)
        }
      }
    }
    if ($lineas[$k].Count -eq 0) { $gastado += ($cab[$k] + ': no consta').Length + 1 } else { $gastado += ($cab[$k] + ':').Length + 1 }
  }
  $abiertas = @($cab.Keys | Where-Object { $lineas[$_].Count -gt 0 })
  for ($i = 0; $abiertas.Count -gt 0; $i++) {
    foreach ($k in @($abiertas)) {
      if ($i -ge $lineas[$k].Count) { $abiertas = @($abiertas | Where-Object { $_ -ne $k }); continue }
      $coste = $lineas[$k][$i].Length + 1
      if (($gastado + $coste) -gt [int]$Cfg.ResumenCaracteresJob) { $abiertas = @($abiertas | Where-Object { $_ -ne $k }); continue }
      $cogidas[$k] += $lineas[$k][$i]
      $gastado += $coste
    }
  }
  $b = ''
  foreach ($k in $cab.Keys) {
    if ($lineas[$k].Count -eq 0) { $b += $cab[$k] + ": no consta`n" }
    else { $b += $cab[$k] + ":`n" + ((@($cogidas[$k]) | ForEach-Object { "$_`n" }) -join '') }
  }
  return $b
}

# La tarea del resumen: de cada job del mapa, el titulo, el para que y los pasos de su redaccion, si esta hecha (si no, solo su
# nombre), y las listas del job (Get-ListasResumen). Sin ninguna redaccion hecha no hay tarea.
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
    else { $b += "(Sin redaccion: de este job no hay titulo, ni para que, ni pasos.)`n" }
    $b += Get-ListasResumen $j.job
    $bloques += $b
  }
  if ($hechas -eq 0) { return @() }
  $texto = ($bloques -join "`n").TrimEnd()
  $entradas = [pscustomobject]@{ jobs = @($Mapa.jobs | ForEach-Object { $_.job }); datos = $texto; huella = (Get-Hash8 $texto) }
  return @(Restore-Tarea (New-TareaTipo 'resumen' 'resumen' '' 'datos/resumen.json' $entradas) $ConservarAtascadas)
}

# ============================== VARIABLES ==============================
# Algun nombre de $Nombres (el de una variable, el ultimo trozo de una clave) ACABA en una palabra de $PalabrasSecreto (comun.ps1), sin
# distinguir mayusculas: la misma regla que Get-SecretosEnClaro de rescate.ps1.
function Test-NombreSecreto([string[]]$Nombres) {
  foreach ($n in $Nombres) {
    foreach ($p in $PalabrasSecreto) { if ($p -and $n.EndsWith([string]$p, [System.StringComparison]::OrdinalIgnoreCase)) { return $true } }
  }
  return $false
}

# Cada ${NOMBRE} y ${NOMBRE:valor} de los application*.yml, .yaml y .properties de src/main/resources y de
# src/main/resources/config del worktree, en ese orden y cada carpeta por nombre (sin las lineas de comentario):
# variable, porDefecto (null si no lleva), fichero (la ruta real) y linea. Si el valor por defecto es de un secreto no se guarda:
# porDefecto es null y la variable lleva secreto = $true (la pagina 1 dice que tiene valor pero no lo ensena).
function Get-Variables {
  $rxClave = '^\s*(?:-\s+)?["'']?([^\s:="''$]+)["'']?\s*[=:]'
  $res = @()
  foreach ($rel in @('src/main/resources', 'src/main/resources/config')) {
    $dir = Join-Ruta $RepoRoot $rel
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.Name -match '^application.*\.(yml|yaml|properties)$' } | Sort-Object Name)) {
      $lineas = [System.IO.File]::ReadAllLines($f.FullName)
      for ($i = 0; $i -lt $lineas.Count; $i++) {
        if ($lineas[$i].TrimStart().StartsWith('#')) { continue }
        $clave = ''
        if ($lineas[$i] -match $rxClave) { $clave = ($Matches[1] -split '\.')[-1] }
        foreach ($m in [regex]::Matches($lineas[$i], '\$\{([\w\.\-]+)(?::([^}]*))?\}')) {
          $defecto = $null
          if ($m.Groups[2].Success) { $defecto = $m.Groups[2].Value }
          $v = [ordered]@{ variable = $m.Groups[1].Value; porDefecto = $defecto; fichero = ($rel + '/' + $f.Name); linea = ($i + 1) }
          if ($null -ne $defecto -and (Test-NombreSecreto @($v.variable, $clave))) { $v.porDefecto = $null; $v.secreto = $true }
          $res += $v
        }
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

# ============================ UN CASO POR REGLA SIN CASO ============================
# El guion de un job (datos\pruebas\<job>.json) como texto para el prompt: lo que se prepara, los casos (solo su titulo) y lo que se comprueba.
function Get-TextoGuion($Prueba) {
  $lista = {
    param($Items, [string]$Campo)
    $l = @($Items | Where-Object { $null -ne $_ } | ForEach-Object { '- ' + (($_.$Campo -replace '\s+', ' ').Trim()) })
    if ($l.Count -eq 0) { return '(nada)' }
    return ($l -join "`n")
  }
  return ("Antes de lanzar el job:`n" + (& $lista $Prueba.preparar 'texto') + "`nCasos que ya hay:`n" + (& $lista $Prueba.casos 'titulo') + "`nAl acabar, lo que se mira:`n" + (& $lista $Prueba.comprobar 'texto'))
}

# Una tarea caso-pre por cada regla o error que prueba-pre dejo en sinCaso (datos\pruebas\<job>.json, escrito por Save-Pruebas): recibe la regla,
# el guion que ya tiene el job y los hechos de Get-ContextoPrueba. La huella sigue a todo eso: si prueba-pre rehace el guion, se piden otra vez.
function Get-TareasCaso($Mapa, [bool]$ConservarAtascadas) {
  $tareas = @()
  foreach ($j in @($Mapa.jobs)) {
    $n = Get-NombreJob $j.job
    $ruta = Join-Path (Join-Path $Datos 'pruebas') ($n + '.json')
    if (-not (Test-Path -LiteralPath $ruta)) { continue }
    $p = Read-Json $ruta
    $faltan = @($p.sinCaso | Where-Object { $null -ne $_ })
    if ($faltan.Count -eq 0) { continue }
    $c = Get-ContextoPrueba $j
    $guion = Get-TextoGuion $p
    $titulos = @($p.casos | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_.titulo })
    foreach ($x in $faltan) {
      $regla = "$($x.ref) [$($x.tipo)] $($x.texto -replace '\s+', ' ')"
      $entradas = [pscustomobject]@{ job = $j.job; ref = $x.ref; tipo = $x.tipo; regla = $regla; pasos = $c.Pasos; datos = $c.Datos; guion = $guion; titulos = $titulos
        huella = (Get-Hash8 ($regla + "`n" + $c.Pasos + "`n" + $c.Datos + "`n" + $guion)) }
      $tareas += , (Restore-Tarea (New-TareaTipo 'caso-pre' ('casopre-' + $n + '-' + (Get-Hash8 $x.ref)) '' ('datos/pruebas/' + $n + '.json') $entradas) $ConservarAtascadas)
    }
  }
  return $tareas
}

# Pone en datos\pruebas\<job>.json el caso de cada tarea caso-pre hecha (al final de casos, sin pasar de CasosMax ni repetir un titulo) y
# deja en sinCaso solo las reglas que ningun caso cubre. Las atascadas no cambian nada: su regla se queda en sinCaso. Se puede aplicar
# otra vez sobre el mismo fichero: no duplica nada.
function Save-Casos($Mapa, $Tareas) {
  foreach ($j in @($Mapa.jobs)) {
    $hechas = @($Tareas | Where-Object { $_.estado -eq 'hecha' -and $_.entradas.job -ceq $j.job })
    if ($hechas.Count -eq 0) { continue }
    $ruta = Join-Path (Join-Path $Datos 'pruebas') ((Get-NombreJob $j.job) + '.json')
    $p = Read-Json $ruta
    $casos = @($p.casos | Where-Object { $null -ne $_ })
    $vistos = @{}
    foreach ($c in $casos) { $vistos[(ConvertTo-Plano ([string]$c.titulo).Trim())] = $true }
    foreach ($t in $hechas) {
      $c = $t.resultado.caso
      $k = ConvertTo-Plano ([string]$c.titulo).Trim()
      if ($vistos.ContainsKey($k) -or $casos.Count -ge [int]$Cfg.CasosMax) { continue }
      $vistos[$k] = $true
      $casos += [ordered]@{ titulo = $c.titulo; entrada = $c.entrada; esperado = $c.esperado; refs = @($c.refs) }
    }
    $cubiertas = @{}
    foreach ($c in $casos) { foreach ($r in @($c.refs)) { $cubiertas[[string]$r] = $true } }
    $p.casos = $casos
    $p.sinCaso = @($p.sinCaso | Where-Object { $null -ne $_ -and -not $cubiertas.ContainsKey([string]$_.ref) })
    Write-Json $ruta $p
  }
}

# ======================= EL ORIGINAL FRENTE AL MIGRADO =======================
# Las palabras del nombre de una clase: sus partes en mayuscula de cuatro letras o mas (GestorRecibos -> Gestor, Recibos).
function Get-PalabrasClase([string]$Nombre) {
  return @([regex]::Matches($Nombre, '\p{Lu}\p{Ll}{3,}') | ForEach-Object { $_.Value } | Select-Object -Unique)
}

# Que fue de cada .java que la correccion renombro o borro, entre <Base> y HEAD de $Dir: la ruta de partida (relativa, con /) -> las
# rutas de ahora. Un renombrado (git diff -M) va a su nueva ruta. De un borrado se sigue lo que tenia: va a los ficheros donde aparecen
# anadidas 2 o mas de sus lineas (de 10 caracteres o mas, sin repetir), las que mas comparten primero y luego por ruta; sin ninguno,
# la lista sale vacia. Con orden ordinal. Sin cambios o si git falla, el mapa sale vacio: nunca para la pasada.
function Get-MapaMovidos([string]$Dir, [string]$Base) {
  $mapa = New-Object 'System.Collections.Generic.SortedDictionary[string,string[]]' ([System.StringComparer]::Ordinal)
  $rango = "$Base...HEAD"
  $r = Invoke-Git $Dir @('-c', 'core.quotepath=off', 'diff', '--name-status', '-M', '--no-color', '--no-ext-diff', $rango, '--', '*.java')
  if ($r.Codigo -ne 0) { return , $mapa }
  $borrados = @()
  foreach ($l in $r.Salida) {
    $c = $l.Split("`t")
    if ($c[0] -clike 'R*' -and $c.Count -ge 3) { $mapa[$c[1]] = @($c[2]) }
    elseif ($c[0] -ceq 'D' -and $c.Count -ge 2) { $borrados += $c[1] }
  }
  if ($borrados.Count -eq 0) { return , $mapa }
  $r = Invoke-Git $Dir @('-c', 'core.quotepath=off', 'diff', '-U0', '--no-renames', '--no-color', '--no-ext-diff', '--src-prefix=a/', '--dst-prefix=b/', $rango, '--', '*.java')
  if ($r.Codigo -ne 0) { return , $mapa }
  # las lineas quitadas de cada fichero de partida y las puestas en cada fichero de ahora; despues del primer @@ de un fichero
  # todo lo que empieza por - o + es una linea (una quitada que empiece por -- no es una cabecera)
  $quitadas = New-Object 'System.Collections.Generic.Dictionary[string,System.Collections.Generic.HashSet[string]]'
  $puestas = New-Object 'System.Collections.Generic.Dictionary[string,System.Collections.Generic.HashSet[string]]'
  $a = ''
  $b = ''
  $dentro = $false
  foreach ($l in $r.Salida) {
    if ($l.StartsWith('diff --git ')) { $a = ''; $b = ''; $dentro = $false }
    elseif (-not $dentro) {
      if ($l.StartsWith('--- a/')) { $a = $l.Substring(6).TrimEnd("`t") }
      elseif ($l.StartsWith('+++ b/')) { $b = $l.Substring(6).TrimEnd("`t") }
      elseif ($l.StartsWith('@@')) { $dentro = $true }
    }
    elseif (($l.StartsWith('-') -and $a) -or ($l.StartsWith('+') -and $b)) {
      $t = $l.Substring(1).Trim()
      if ($t.Length -lt 10) { continue }
      $lado = $puestas
      $ruta = $b
      if ($l.StartsWith('-')) { $lado = $quitadas; $ruta = $a }
      if (-not $lado.ContainsKey($ruta)) { $lado[$ruta] = New-Object 'System.Collections.Generic.HashSet[string]' }
      [void]$lado[$ruta].Add($t)
    }
  }
  foreach ($d in $borrados) {
    $claves = @()
    if ($quitadas.ContainsKey($d)) {
      foreach ($p in $puestas.Keys) {
        $n = 0
        foreach ($t in $quitadas[$d]) { if ($puestas[$p].Contains($t)) { $n++ } }
        if ($n -ge 2) { $claves += ((999999 - $n).ToString('D6') + $p) }
      }
    }
    $claves = [string[]]$claves
    [System.Array]::Sort($claves, [System.StringComparer]::Ordinal)
    $mapa[$d] = @($claves | ForEach-Object { $_.Substring(6) })
  }
  return , $mapa
}

# Los ficheros del migrado (de $Java, los .java del worktree) que lee la comparacion de una clase del original: los que se
# llaman como ella; si no hay ninguno, los de ahora a los que fue el fichero que se llamaba como ella (el mapa de lo que movio la
# correccion, en su orden); si sigue sin haber, los que comparten alguna palabra de su nombre, los que mas primero y luego por ruta.
# FicherosComparar como mucho. Sin ninguno, la clase no se compara con IA.
function Select-FicherosMigrado([string]$Clase, $Java, $Mapa) {
  $rutas = @($Java | ForEach-Object { Get-Rel $RepoRoot $_.FullName })
  $mismos = @($Java | Where-Object { $_.BaseName -ceq $Clase } | ForEach-Object { Get-Rel $RepoRoot $_.FullName } | Sort-Object)
  if ($mismos.Count -gt 0) { return @($mismos | Select-Object -First ([int]$Cfg.FicherosComparar)) }
  $movidos = @()
  foreach ($vieja in $Mapa.Keys) {
    if ([System.IO.Path]::GetFileNameWithoutExtension($vieja) -ceq $Clase) { $movidos += @($Mapa[$vieja] | Where-Object { $rutas -ccontains $_ }) }
  }
  if ($movidos.Count -gt 0) { return @($movidos | Select-Object -Unique | Select-Object -First ([int]$Cfg.FicherosComparar)) }
  $palabras = @(Get-PalabrasClase $Clase)
  $candidatos = @()
  foreach ($f in $Java) {
    $comunes = @(Get-PalabrasClase $f.BaseName | Where-Object { $palabras -ccontains $_ }).Count
    if ($comunes -gt 0) { $candidatos += [pscustomobject]@{ N = $comunes; Rel = (Get-Rel $RepoRoot $f.FullName) } }
  }
  return @($candidatos | Sort-Object @{ Expression = 'N'; Descending = $true }, Rel | Select-Object -First ([int]$Cfg.FicherosComparar) | ForEach-Object { $_.Rel })
}

# Si la rama del worktree ya lleva commits de arreglo (rescate(<paso>): ...) desde $Base: 'despues-de-corregir'; si no, 'antes-de-corregir'.
function Get-MomentoRama([string]$Base) {
  if (@((Invoke-Git $RepoRoot @('log', '--format=%s', "$Base..HEAD")).Salida | Where-Object { $_ -match '^rescate\(' }).Count -gt 0) { return 'despues-de-corregir' }
  return 'antes-de-corregir'
}

# Ruta -> hash de blob de todo lo que lleva HEAD en $Dir, con una sola llamada a git (ls-tree -r) para todos los ficheros. Vacio si git no contesta.
function Get-BlobsHead([string]$Dir) {
  $blobs = @{}
  $ls = Invoke-Git $Dir @('-c', 'core.quotepath=off', 'ls-tree', '-r', 'HEAD')
  if ($ls.Codigo -eq 0) {
    foreach ($l in @($ls.Salida)) { if ($l -match '^\d+ blob ([0-9a-f]+)\t(.+)$') { $blobs[$Matches[2]] = $Matches[1] } }
  }
  return $blobs
}

# Lo que vale un fichero de $Dir en una clave que sigue al contenido: ruta=blob (su hash en HEAD). Si HEAD no lo tiene (sin seguimiento, o git sin
# contestar), ruta=fuera-<hash de lo que hay en el disco>: cambia con el contenido y nunca vale de mas. Si ya no esta, ruta=ausente.
function Get-ClaveFichero($Blobs, [string]$Dir, [string]$Rel) {
  if ($Blobs.ContainsKey($Rel)) { return "$Rel=$($Blobs[$Rel])" }
  $ruta = Join-Ruta $Dir $Rel
  if (Test-Path -LiteralPath $ruta -PathType Leaf) { return "$Rel=fuera-" + (Get-Hash8 ([System.IO.File]::ReadAllText($ruta))) }
  return "$Rel=ausente"
}

# El final comun de las tareas de comparar (comparar-pieza y comparar-sh), con $T ya montada: su huella lleva el hash de blob de cada fichero del
# migrado ($Claves, de Get-ClaveFichero) y su commit y su momento son los de ahora. Devuelve la tarea que queda (Restore-Tarea). La tarea guardada
# se reutiliza si esta hecha con esa huella; el commit y el momento no entran en ella, asi que de una reutilizada se ponen al de ahora.
# Puente de M43 y M44: hasta entonces la huella era Hash8(texto | HEAD) y $HuellaVieja es esa, con el HEAD de ahora. Una tarea guardada con ella,
# con los mismos ficheros del migrado y todos en HEAD, es de este mismo codigo: se guarda con la huella nueva y Restore-Tarea la reutiliza. Quitalo
# cuando ningun batch tenga tareas de comparar de antes de M44 (con otro HEAD no vale: no se sabe si los ficheros eran los mismos).
function Restore-TareaComparar($T, [string]$HuellaVieja, $Claves, [bool]$ConservarAtascadas) {
  $previa = Get-TareaGuardada $T.id
  if ($previa -and $previa.entradas.huella -ceq $HuellaVieja -and (@($previa.entradas.migrado) -join '|') -ceq (@($T.entradas.migrado) -join '|') -and @($Claves | Where-Object { $_ -match '=(fuera-|ausente)' }).Count -eq 0) {
    $previa.entradas.huella = $T.entradas.huella
    Save-Tarea $previa
  }
  $r = Restore-Tarea $T $ConservarAtascadas
  if ($r.entradas.commit -cne $T.entradas.commit -or $r.entradas.momento -cne $T.entradas.momento) {
    $r.entradas.commit = $T.entradas.commit
    $r.entradas.momento = $T.entradas.momento
    Save-Tarea $r
  }
  return $r
}

# Una tarea por ficha de clase con datos. Los ficheros del migrado los elige el script y quedan en las entradas de la tarea, con el
# commit del worktree con el que se eligieron y el momento: despues-de-corregir si hay algun commit rescate( entre <Base> y HEAD (lo
# dice git, no el orden de las fases), antes-de-corregir si no. Sin ficheros no hay llamada: la tarea nace hecha, con todos sus datos
# 'sin-pieza'. La huella lleva los datos de la ficha y, de cada fichero del migrado elegido, su hash de blob en HEAD (Get-ClaveFichero), no el
# HEAD: un commit que no toca esos ficheros no rehace la comparacion, y si cambia la lista de ficheros o uno de ellos, si. El commit y el momento
# no entran en la huella: una tarea que se reutiliza los pone al de ahora, porque lo que dice vale tambien para este HEAD.
function Get-TareasComparar([bool]$ConservarAtascadas, [string]$Base) {
  $java = @(Get-JavaOriginal $RepoRoot)
  $mapa = Get-MapaMovidos $RepoRoot $Base
  $head = Get-Head $RepoRoot
  $momento = Get-MomentoRama $Base
  $blobs = Get-BlobsHead $RepoRoot
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
    $migrado = @(Select-FicherosMigrado $x.clase $java $mapa)
    $claves = @($migrado | ForEach-Object { Get-ClaveFichero $blobs $RepoRoot $_ })
    $entradas = [pscustomobject]@{
      clase = $x.clase; fichero = $x.fichero; migrado = $migrado; ndatos = $lista.Count; datos = $texto
      huella = (Get-Hash8 ($texto + '|' + ($claves -join '|'))); commit = $head.Substring(0, 7); momento = $momento
    }
    $t = New-TareaTipo 'comparar-pieza' ('comparar-' + $x.id) $x.id ('datos/comparacion/' + $x.id + '.json') $entradas
    if ($migrado.Count -eq 0) {
      $t.estado = 'hecha'
      $t.resultado = [ordered]@{ comparacion = @(0..($lista.Count - 1) | ForEach-Object { [ordered]@{ dato = $_; estado = 'sin-pieza'; fichero = ''; linea = 0; cita = ''; nota = ''; probado = $false } }) }
    }
    $tareas += , (Restore-TareaComparar $t (Get-Hash8 ($texto + '|' + $head)) $claves $ConservarAtascadas)
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

# Escribe datos\comparacion\<ficha>.json de cada tarea hecha: la clase, su fichero del original, los del migrado, el momento y el commit con que se
# eligieron y, por dato, lo que se dijo.
function Save-Comparaciones($Tareas) {
  foreach ($t in @($Tareas | Where-Object { $_.estado -eq 'hecha' })) {
    $o = [ordered]@{ ficha = $t.ficha; clase = $t.entradas.clase; ficheroOriginal = $t.entradas.fichero; migrado = @($t.entradas.migrado); momento = $t.entradas.momento; commit = $t.entradas.commit; datos = @($t.resultado.comparacion) }
    Write-Json (Join-Path (Join-Path $Datos 'comparacion') ($t.ficha + '.json')) $o
  }
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
