<#
migracion.ps1 - Migracion desatendida de un batch Java, con un modelo pequeno.
Compatible con Windows PowerShell 5.1 y PowerShell 7. Solo ASCII a proposito.
Necesita comun.ps1 y la carpeta tareas\ junto a este script.

QUE HACE (esta version: solo la primera parte, la lectura de clases)
  Un comando. Das el batch original (-Legacy) y el migrado (-Migrado), contestas
  dos preguntas (modelo y que hacer al acabar el informe) y te vas. Cada llamada
  a Copilot CLI es una tarea cerrada y pequena; el script la comprueba. El
  trabajo va a <Migrado>\migracion-<batch>\ (git la ignora en local) y la IA lee
  en un worktree aparte (<Migrado>-rescate), nunca en tu carpeta.

  Arranque: herramientas y repos, batch de referencia (-Plantilla, o el guardado
  en %USERPROFILE%\.rescate\ajustes.json, o se pregunta), modelo, prueba de
  aptitud (una ficha de clase sobre un fichero de juguete), pregunta y worktree.
  Lectura: una ficha por clase del original, hasta 4 llamadas a la vez. Tras
  cada ronda el worktree tiene que estar limpio y el original y la referencia sin
  cambios. Una salida invalida se repite una vez, con el motivo y esfuerzo alto;
  si falla otra vez la tarea queda atascada y se sigue.
  Si algo se atasca, el script para y lo deja en datos\estado.json (parada) con un
  texto de ayuda listo para pegar en Copilot. Al relanzar el mismo comando salta
  las tareas hechas y sigue donde se quedo.

USO
  .\migracion.ps1 -Legacy C:\ruta\life-java8 -Migrado C:\ruta\batch-life
  .\migracion.ps1 -Legacy ... -Migrado ... -Plantilla C:\ruta\batch-terminado -Modelo <id>
  .\migracion.ps1 ... -SoloInforme     # contesta "parar" a la pregunta del final
  .\migracion.ps1 ... -Si              # contesta "corregir"
  .\migracion.ps1 ... -MaxHoras 6      # no empieza rondas nuevas pasado ese tiempo

  Salida: 0 bien (o tope de tiempo), 1 no pudo arrancar, 2 se paro (ver estado.json).
  Los ajustes de ajustes.json (y de .rescate\config.json del migrado) pisan las claves
  del bloque CONFIGURACION; la carpeta de ajustes se cambia con la variable de
  entorno RESCATE_HOME. Antes de darlo por bueno, pasa tests\probar-migracion.ps1.
#>
[CmdletBinding()]
param(
  [string]$Legacy = '',       # carpeta del batch original (repo git)
  [string]$Migrado = '.',     # carpeta del batch migrado (repo git, en una rama)
  [string]$Plantilla = '',    # batch de referencia: ya migrado y aprobado (repo git)
  [string]$Modelo = '',       # id del modelo de Copilot; sin esto se pregunta
  [switch]$SoloInforme,       # al acabar el informe, parar (no corregir)
  [switch]$Si,                # al acabar el informe, corregir
  [double]$MaxHoras = 0       # 0 = sin tope
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'comun.ps1')

# ============================ CONFIGURACION ============================
$Cfg += @{
  Modelos            = @('claude-sonnet-5.5', 'gpt-6-luna', 'gpt-6.1-terra', 'gpt-6.1-sol', 'gpt-6-astra', 'claude-haiku-5.5', 'gemini-3.8-flash')
  JavaExe            = 'java'
  Paralelo           = 4      # llamadas a Copilot a la vez
  SegundosPorLlamada = 900    # pasado este tiempo, la llamada se mata
  FallosSeguidos     = 6      # llamadas fallidas seguidas antes de parar
  Intentos           = 2      # el primero y un reintento con el motivo
  LineasPorTarea     = 300    # un fichero mas largo se trocea por rangos de lineas
  CitaMax            = 120    # caracteres de una cita
  CitaCerca          = 3      # una cita a esta distancia (o menos) de su linea cuenta como bien situada
  EsfuerzoLectura    = 'medium'
  EsfuerzoReintento  = 'high'
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

function Get-Repo([string]$Ruta, [string]$Que) {
  if (-not (Test-Path -LiteralPath $Ruta)) { Stop-Arranque "$Que no existe: $Ruta" }
  $r = Resolve-Dir $Ruta
  if (-not (Test-Path -LiteralPath (Join-Path $r '.git'))) { Stop-Arranque "$Que no es la raiz de un repo git: $r" }
  return $r
}

# artifactId del pom; si no hay, el nombre de la carpeta. Vale como nombre de carpeta.
function Get-Batch([string]$Raiz) {
  $id = ''
  $p = Join-Path $Raiz 'pom.xml'
  if (Test-Path -LiteralPath $p) {
    $x = New-Object System.Xml.XmlDocument
    try {
      $x.Load($p)
      foreach ($n in $x.DocumentElement.ChildNodes) { if ($n.LocalName -eq 'artifactId') { $id = $n.InnerText.Trim() } }
    }
    catch { $id = '' }
  }
  if (-not $id) { $id = Split-Path $Raiz -Leaf }
  return ($id -replace '[^\w\.\-]', '-')
}

function Get-Hash8([string]$Texto) {
  $sha = [System.Security.Cryptography.SHA1]::Create()
  try { $b = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Texto)) } finally { $sha.Dispose() }
  return ((@($b[0..3]) | ForEach-Object { $_.ToString('x2') }) -join '')
}

# ============================ AJUSTES Y ESTADO ============================
function Get-RutaAjustes {
  if ($env:RESCATE_HOME) { return (Join-Path $env:RESCATE_HOME 'ajustes.json') }
  return (Join-Path (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.rescate') 'ajustes.json')
}

# Guarda la referencia en ajustes.json sin tocar el resto de claves.
function Save-Plantilla([string]$Ruta) {
  $f = Get-RutaAjustes
  $o = [ordered]@{}
  if (Test-Path -LiteralPath $f) { foreach ($pr in (Read-Json $f).PSObject.Properties) { $o[$pr.Name] = $pr.Value } }
  $o['Plantilla'] = $Ruta
  Write-Json $f $o
}

function Save-Estado {
  $Estado['actualizado'] = (Get-Date).ToString('s')
  Write-Json (Join-Path $Datos 'estado.json') $Estado
}

# Para el trabajo y lo deja en estado.json con un texto de ayuda para pegar en Copilot.
function Set-Parada([string]$Motivo, [string]$Detalle, [string]$Registro) {
  $ayuda = "Estoy ejecutando migracion.ps1 (migracion desatendida de un batch Java con GitHub Copilot CLI) y se ha parado. Motivo: $Motivo. Detalle: $Detalle. El registro esta en: $Registro. Dime que ha pasado y que tengo que hacer para arreglarlo. Despues vuelvo a lanzar el mismo comando y sigue donde se quedo."
  $Estado['parada'] = [ordered]@{ motivo = $Motivo; detalle = $Detalle; registro = $Registro; ayuda = $ayuda }
  Save-Estado
  if ($Motivo -eq 'tope-de-tiempo') { Aviso "Parada ($Motivo): $Detalle" } else { Fallo "Parada ($Motivo): $Detalle" }
}

function Select-Modelo {
  $l = @($Cfg.Modelos)
  Info 'Modelo de Copilot para las lecturas y los arreglos:'
  for ($i = 0; $i -lt $l.Count; $i++) { Info ('  ' + ($i + 1) + ') ' + $l[$i]) }
  $otro = $l.Count + 2
  Info ('  ' + ($l.Count + 1) + ') el que tenga Copilot (Enter)')
  Info "  $otro) otro (lo escribes tu)"
  $r = "$(Read-Host 'Numero')".Trim()
  if ($r -match '^\d+$' -and [int]$r -ge 1 -and [int]$r -le $l.Count) { return [string]$l[[int]$r - 1] }
  if ($r -eq "$otro") { return "$(Read-Host 'Id del modelo')".Trim() }
  return ''
}

# ================================ LLAMADAS ================================
# Comillas para la linea de comandos de Windows (valen tambien en Linux).
function ConvertTo-ArgWin([string]$A) {
  if ($A -ne '' -and $A -notmatch '[\s"]') { return $A }
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
    $pre = @('-NoProfile')
    if ($env:OS -eq 'Windows_NT') { $pre += @('-ExecutionPolicy', 'Bypass') }
    return [pscustomobject]@{ Exe = (Get-PowerShellExe); Args = ((($pre + @('-File', $ruta) + $A) | ForEach-Object { ConvertTo-ArgWin $_ }) -join ' ') }
  }
  if ($ext -eq '.cmd' -or $ext -eq '.bat') {
    return [pscustomobject]@{ Exe = $env:ComSpec; Args = ('/d /s /c "' + ((@($ruta) + $A | ForEach-Object { ConvertTo-ArgWin $_ }) -join ' ') + '"') }
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
    $vivos += , (Start-Llamada $it.Dir (Get-ArgsCopilot $texto $it.Modelo $it.Esfuerzo @($LegacyRoot) $false))
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
    id = $Id; ficha = $Ficha; tipo = 'ficha-clase'; salida = "datos/fichas/$Ficha.json"; estado = 'pendiente'; intentos = 0; motivo = ''
    entradas = [pscustomobject]@{ fichero = $Rel; desde = $Desde; hasta = $Hasta }; resultado = $null
  }
}

function Save-Tarea($T) { Write-Json (Join-Path (Join-Path $Datos 'tareas') ($T.id + '.json')) $T }

# Una ficha de clase por fichero del original (troceada si pasa de LineasPorTarea).
# Las que ya estan hechas (de un lanzamiento anterior) se conservan tal cual; el resto empieza de cero.
function Get-TareasFichas {
  $tareas = @()
  $main = Join-Ruta $LegacyRoot 'src/main/java'
  foreach ($f in @(Get-JavaFiles $main | Sort-Object FullName)) {
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
        try { $p = Read-Json $previa; if ($p.estado -eq 'hecha') { $t = $p } } catch { }
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
# Devuelve, por tarea: Tarea, Estado (ok, invalida, fallo, tiempo), Motivo, Ficha y Registro.
function Invoke-Ronda($Lote, [string]$Dir, [string]$RaizOrig) {
  $items = @()
  foreach ($t in $Lote) {
    $leer = Join-Ruta $RaizOrig $t.entradas.fichero
    if ($t.intentos -gt 0) { $motivo = $t.motivo; $esf = $Cfg.EsfuerzoReintento } else { $motivo = ''; $esf = $Cfg.EsfuerzoLectura }
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
    $r = [pscustomobject]@{ Tarea = $t; Estado = 'ok'; Motivo = ''; Ficha = $null; Registro = $registro }
    if ($c.Agotado) { $r.Estado = 'tiempo'; $r.Motivo = "Tiempo agotado: la llamada pasaba de $($Cfg.SegundosPorLlamada) s y se mato." }
    elseif ($c.Codigo -ne 0) { $r.Estado = 'fallo'; $r.Motivo = "Copilot salio con codigo $($c.Codigo): " + (Get-UltimaLinea $c.Texto) }
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
# menos una cita correcta. Devuelve '' si pasa o el motivo del ultimo fallo.
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
    $t.intentos++
    $t.motivo = $o.Motivo
    $motivo = $o.Motivo
  }
  return $motivo
}

# ================================= MAIN =================================
$reloj = [System.Diagnostics.Stopwatch]::StartNew()
if (-not $Legacy) { Stop-Arranque 'Falta -Legacy: la carpeta del batch original (Java 8).' }
if ($SoloInforme -and $Si) { Stop-Arranque 'Usa -SoloInforme o -Si, no los dos.' }
$respondeSi = [bool]$Si

# 1. Herramientas y repos (antes, los ajustes: pueden cambiar donde estan)
$ajustes = Read-CfgFile (Get-RutaAjustes) @('Plantilla')
foreach ($x in @(@('git', 'git'), @('java', $Cfg.JavaExe), @('Copilot', $Cfg.CopilotExe))) {
  if (-not (Get-Command $x[1] -ErrorAction SilentlyContinue)) { Stop-Arranque "No encuentro $($x[0]) ('$($x[1])') en el PATH." }
}
$LegacyRoot = Get-Repo $Legacy '-Legacy'
$MigradoRoot = Get-Repo $Migrado '-Migrado'
$rama = Get-Rama $MigradoRoot
if (-not $rama -or $rama -eq 'HEAD') { Stop-Arranque "El migrado no esta en una rama (HEAD suelto): $MigradoRoot. Cambia a una rama y vuelve a lanzar." }
Read-Config $MigradoRoot
$mvn = Get-Mvn $MigradoRoot
if (-not (Test-Path -LiteralPath $mvn) -and -not (Get-Command $mvn -ErrorAction SilentlyContinue)) { Stop-Arranque "No encuentro Maven ('$mvn'). Instalalo o pon MvnExe en los ajustes." }
Set-Excluidos $MigradoRoot

# 2. Batch de referencia: -Plantilla, el guardado o se pregunta; se guarda
$guardada = ''
if ($ajustes -and $ajustes.Plantilla) { $guardada = [string]$ajustes.Plantilla }
$ref = $Plantilla
if (-not $ref -and $guardada -and (Test-Path -LiteralPath $guardada)) { $ref = $guardada }
if (-not $ref) { $ref = "$(Read-Host 'Carpeta del batch de referencia (un batch ya migrado y aprobado)')".Trim() }
if (-not $ref) { Stop-Arranque 'Falta la referencia: pasa -Plantilla o contesta con la carpeta del batch de referencia.' }
$PlantillaRoot = Get-Repo $ref 'La referencia'
if ($PlantillaRoot -ne $guardada) { Save-Plantilla $PlantillaRoot }

# Carpetas de salida y estado anterior (si se relanza)
$batch = Get-Batch $MigradoRoot
$Salida = Join-Path $MigradoRoot ('migracion-' + $batch)
$Datos = Join-Path $Salida 'datos'
$Registros = Join-Path $Salida 'registros'
foreach ($d in @($Datos, $Registros)) { if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -Force) } }
$previo = $null
if (Test-Path -LiteralPath (Join-Path $Datos 'estado.json')) { try { $previo = Read-Json (Join-Path $Datos 'estado.json') } catch { $previo = $null } }

# 3. Modelo: -Modelo, el del lanzamiento anterior o el menu
if ($PSBoundParameters.ContainsKey('Modelo')) { $ModeloElegido = $Modelo }
elseif ($previo -and ($null -ne $previo.modelo)) { $ModeloElegido = [string]$previo.modelo }
else { $ModeloElegido = Select-Modelo }
if ($ModeloElegido) { Info "Modelo: $ModeloElegido" } else { Info 'Modelo: el que tenga Copilot' }
$H0 = [pscustomobject]@{ Legacy = (Get-Huella $LegacyRoot); Plantilla = (Get-Huella $PlantillaRoot) }

# 4. Prueba de aptitud (se salta si ya paso con este modelo)
if ($previo -and ($null -ne $previo.aptitud) -and ([string]$previo.aptitud -eq $ModeloElegido)) { Info 'Prueba de aptitud: ya pasada con este modelo.' }
else {
  Info 'Prueba de aptitud (una ficha de clase sobre un fichero de juguete)...'
  $mal = Test-Aptitud
  if ($mal) { Stop-Arranque ("La prueba de aptitud ha fallado dos veces con este modelo: $mal`nRegistros: $Registros`nPrueba con otro modelo (-Modelo) o mira que Copilot responde.") }
  Bien 'Prueba de aptitud: bien.'
}

# 5. Pregunta: que hacer al acabar el informe
if ($SoloInforme) { $respuesta = 'parar' }
elseif ($respondeSi) { $respuesta = 'corregir' }
elseif ($previo -and $previo.respuesta) { $respuesta = [string]$previo.respuesta }
else {
  $r = "$(Read-Host 'Al acabar el informe, corregir el codigo del migrado? Enter = si, n = parar')".Trim()
  if ($r -match '^[nN]') { $respuesta = 'parar' } else { $respuesta = 'corregir' }
}
$Si = [switch]$true    # las preguntas ya estan contestadas: Confirmar no vuelve a preguntar

# 6. Worktree y estado
$OrigenRoot = $MigradoRoot
$Worktree = ''
$dirWt = Get-DirRescate
if (-not (Test-WorktreeRescate $dirWt)) { New-WorktreeRescate $dirWt }
$RepoRoot = $dirWt
Read-Config $RepoRoot
$Estado = [ordered]@{
  version = 1; batch = $batch; legacy = $LegacyRoot; migrado = $MigradoRoot; plantilla = $PlantillaRoot
  worktree = $RepoRoot; rama = (Get-Rama $RepoRoot); modelo = $ModeloElegido; aptitud = $ModeloElegido; respuesta = $respuesta
  fase = 'fichas-clase'; creado = (Get-Date).ToString('s'); actualizado = ''; parada = $null
}
if ($previo -and $previo.creado) { $Estado['creado'] = [string]$previo.creado }
foreach ($d in @((Join-Path $Datos 'tareas'), (Join-Path $Datos 'fichas'))) { if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -Force) } }
$Tareas = @(Get-TareasFichas)
Save-Estado
$hechas0 = @($Tareas | Where-Object { $_.estado -eq 'hecha' }).Count
$ficheros = @($Tareas | Group-Object { $_.ficha }).Count
Info "Tareas de lectura: $($Tareas.Count) (fichas de clase de $ficheros ficheros del original; $hechas0 ya hechas)."

# Lectura: fichas de clase, en rondas de hasta Paralelo llamadas
$racha = 0
$parada = $false
while ($true) {
  $pend = @($Tareas | Where-Object { $_.estado -eq 'pendiente' })
  if ($pend.Count -eq 0) { break }
  $lote = @($pend | Select-Object -First ([int]$Cfg.Paralelo))
  $head = Get-Head $RepoRoot
  $rondaRama = Get-Rama $RepoRoot
  Info ('Ronda: ' + $lote.Count + ' llamadas a la vez (quedan ' + $pend.Count + ' tareas)...')
  $res = @(Invoke-Ronda $lote $RepoRoot $LegacyRoot)

  # comprobacion tras la ronda: worktree limpio y original y referencia sin cambios
  $sucio = @((Invoke-Git $RepoRoot @('status', '--porcelain')).Salida | Where-Object { $_ })
  if ($sucio.Count -gt 0) { Undo-Lote $rondaRama $head }
  if ((Get-Huella $LegacyRoot) -ne $H0.Legacy -or (Get-Huella $PlantillaRoot) -ne $H0.Plantilla) {
    Set-Parada 'guardas' 'Ha cambiado el original o la referencia durante una lectura. Esa carpeta no se deshace desde aqui: mira con git status y git diff, y vuelve a lanzar.' $res[0].Registro
    $parada = $true
    break
  }
  foreach ($o in $res) {
    if ($o.Estado -in @('fallo', 'tiempo')) { $racha++ } else { $racha = 0 }
    if ($sucio.Count -gt 0 -and $o.Estado -in @('ok', 'invalida')) {
      $o.Estado = 'invalida'
      $o.Motivo = 'La lectura toco ficheros del repositorio (' + (($sucio | Select-Object -First 3) -join '; ') + '). Lee sin cambiar nada: solo escribes el fichero de salida.'
    }
    $t = $o.Tarea
    $t.intentos++
    $t.motivo = $o.Motivo
    if ($o.Estado -eq 'ok') { $t.estado = 'hecha'; $t.resultado = $o.Ficha }
    elseif ($t.intentos -ge [int]$Cfg.Intentos) { $t.estado = 'atascada'; Aviso "Atascada: $($t.entradas.fichero): $($o.Motivo)" }
    Save-Tarea $t
  }
  Save-Fichas $Tareas
  if ($racha -ge [int]$Cfg.FallosSeguidos) {
    # el fallo es de Copilot, no de las tareas: vuelven a empezar al relanzar
    foreach ($o in $res) {
      if ($o.Estado -in @('fallo', 'tiempo')) { $o.Tarea.estado = 'pendiente'; $o.Tarea.intentos = 0; Save-Tarea $o.Tarea }
    }
    $ultimo = @($res | Where-Object { $_.Estado -in @('fallo', 'tiempo') } | Select-Object -Last 1)[0]
    Set-Parada 'copilot-no-responde' "$racha llamadas seguidas han fallado (sesion, cuota o red). Ultimo error: $($ultimo.Motivo)" $ultimo.Registro
    $parada = $true
    break
  }
  if ($MaxHoras -gt 0 -and $reloj.Elapsed.TotalHours -ge $MaxHoras -and @($Tareas | Where-Object { $_.estado -eq 'pendiente' }).Count -gt 0) {
    Set-Parada 'tope-de-tiempo' "Se ha llegado al tope de -MaxHoras $MaxHoras. Relanza el mismo comando para seguir." $Registros
    $parada = $true
    break
  }
}
Save-Fichas $Tareas
if (-not $parada) { $Estado['fase'] = 'fichas-clase-hechas'; Save-Estado }

$hechas = @($Tareas | Where-Object { $_.estado -eq 'hecha' }).Count
$atascadas = @($Tareas | Where-Object { $_.estado -eq 'atascada' }).Count
Info ''
Info "Lectura de clases: $hechas hechas, $atascadas atascadas, $($Tareas.Count - $hechas - $atascadas) pendientes de $($Tareas.Count) tareas."
Info "Datos en: $Salida"
if ($atascadas -gt 0) { Aviso "Las tareas atascadas estan en $(Join-Path $Datos 'tareas') (estado 'atascada', con su motivo)." }
if ($parada -and $Estado['parada'].motivo -ne 'tope-de-tiempo') { exit 2 }
exit 0
