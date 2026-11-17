<#
preflight.ps1 - Una sola pasada, antes de migracion.ps1, para saber si este equipo, Copilot y
Maven sirven para lo que viene. Mide y cuenta; no arregla ni cambia ningun repo tuyo.
Compatible con Windows PowerShell 5.1 y PowerShell 7. Solo ASCII a proposito.
Necesita comun.ps1, tareas.ps1 y las carpetas tareas\, preflight\ y tests\ junto a este script.

USO (todo es opcional)
  .\preflight.ps1 -Legacy C:\ruta\original -Migrado C:\ruta\migrado -Plantilla C:\ruta\referencia -Modelo <id>
  .\preflight.ps1 -Solo 1,3        # solo esos bloques
  .\preflight.ps1 -SinCopilot      # salta los bloques 4, 5 y 8 (los que llaman al modelo)
  .\preflight.ps1 -SinMaven        # salta el 6 y el diagnostico del 7

BLOQUES (cada uno en su try; el fichero se reescribe al acabar cada bloque)
  1 entorno       modo de lenguaje, versiones, politica de ejecucion, suspension, disco
  2 bancos        tests\probar.ps1 y tests\probar-migracion.ps1 como procesos hijo
  3 copilot       que banderas conoce (sin llamar a ningun modelo)
  4 aptitud       la ficha de un fichero de juguete, 3 veces + esfuerzo alto + herramientas limitadas
  5 paralelo      4 fichas de juguete a la vez
  6 maven         compilar, JaCoCo y OpenRewrite sobre preflight\juguete
  7 forma         numeros de los repos y diagnostico de rescate.ps1 (solo numeros)
  8 clases reales 5 clases del original por tamano: la ficha de cada una

RESULTADO preflight-resultado.txt junto al script (lo copia al portapapeles en Windows si puede).
Sale con 0 si ha podido escribirlo y con 1 si no. Es para pegarlo en un chat: todo texto libre
pasa por Get-Seguro, que quita rutas, usuario, equipo, dominio, correos, IP y URL internas, nombres
de los repos y de sus clases; corta a 200 caracteres y deja solo ASCII. Del original no sale
ningun nombre ni contenido: solo numeros y el principio de un mensaje nuestro (Get-MotivoCorto).

Los ajustes (CopilotExe, MvnExe, JavaExe...) se leen igual que en migracion.ps1 (RESCATE_HOME).
#>
[CmdletBinding()]
param(
  [string]$Legacy = '',        # carpeta del batch original
  [string]$Migrado = '',       # carpeta del batch migrado
  [string]$Plantilla = '',     # batch de referencia
  [string]$Modelo = '',        # id del modelo de Copilot; sin esto, el que tenga Copilot
  [string[]]$Solo = @(),       # numeros de bloque: 1,3 (con -File llega como un solo texto "1,3")
  [switch]$SinCopilot,
  [switch]$SinMaven
)
$ErrorActionPreference = 'Stop'
$Inicio = Get-Date
$Salida = Join-Path $PSScriptRoot 'preflight-resultado.txt'

# ==================== ANTES DE CARGAR NADA: solo cmdlets ====================
# En modo de lenguaje restringido ni la carga de comun.ps1 ni el uso de .NET funcionan.
function Get-Commit {
  $c = 'sin-git'
  try {
    if ((Test-Path -LiteralPath (Join-Path $PSScriptRoot '.git')) -and (Get-Command git -ErrorAction SilentlyContinue)) {
      $ErrorActionPreference = 'Continue'
      $o = @(& git -C $PSScriptRoot rev-parse --short HEAD 2>&1 | ForEach-Object { "$_" })
      if ($LASTEXITCODE -eq 0 -and $o.Count -gt 0 -and "$($o[0])" -match '^[0-9a-f]{4,40}$') { $c = "$($o[0])" }
    }
  }
  catch { $c = 'sin-git' }
  return $c
}

$Cabecera = 'PREFLIGHT java-scripts ' + (Get-Commit)
$modo = "$($ExecutionContext.SessionState.LanguageMode)"
if ($modo -ne 'FullLanguage') {
  $min = [int]((New-TimeSpan -Start $Inicio -End (Get-Date)).TotalMinutes)
  $l = @($Cabecera, '== 1 entorno', "modo de lenguaje: $modo", "powershell: $($PSVersionTable.PSVersion) $($PSVersionTable.PSEdition)",
    'para: modo de lenguaje restringido', '== fin', 'bloques con fallo: ninguno', "duracion: $min min")
  Set-Content -LiteralPath $Salida -Value $l -Encoding ASCII
  $l | ForEach-Object { Write-Host $_ }
  exit 0
}

# ============================= CARGA DE LA BIBLIOTECA =============================
$script:Lineas = New-Object System.Collections.Generic.List[string]
$script:Fallos = @()
$script:NoEscribe = $false
$script:SinModelo = $false
$script:SegundosIntentos = @()
try {
  . (Join-Path $PSScriptRoot 'comun.ps1')
  . (Join-Path $PSScriptRoot 'tareas.ps1')
}
catch {
  $l = @($Cabecera, '== 1 entorno', "modo de lenguaje: $modo", ('fallo: no se pudo cargar la biblioteca (' + $_.Exception.GetType().Name + ')'), '== fin', 'bloques con fallo: 1', 'duracion: 0 min')
  try { Set-Content -LiteralPath $Salida -Value $l -Encoding ASCII } catch { }
  $l | ForEach-Object { Write-Host $_ }
  exit 1
}

# ================================== SALIDA ==================================
function Add-Linea([string]$Texto) { $script:Lineas.Add($Texto) }

function Save-Resultado {
  try { [System.IO.File]::WriteAllLines($Salida, [string[]]$script:Lineas.ToArray(), $Utf8) }
  catch { $script:NoEscribe = $true }
}

function Get-SiNo([bool]$V) { if ($V) { return 'si' } else { return 'no' } }

# =============================== FILTRO DE PRIVACIDAD ===============================
# Por aqui pasa todo texto que no sea un numero, un si/no o un texto fijo nuestro.
$script:Reglas = New-Object System.Collections.ArrayList
$script:Publicos = @('repo.maven.apache.org', 'repo1.maven.org', 'github.com', 'api.github.com', 'objects.githubusercontent.com')

function Add-Regla([string]$Patron, [string]$Con, [scriptblock]$Evalua = $null) {
  [void]$script:Reglas.Add([pscustomobject]@{ Re = (New-Object System.Text.RegularExpressions.Regex($Patron, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)); Con = $Con; Evalua = $Evalua })
}

# La ruta con \ o / indistintos y, pegado a ella, el resto de la ruta (por debajo hay nombres).
function Get-PatronRuta([string]$Ruta) {
  $partes = @((($Ruta -replace '\\', '/').TrimEnd('/')) -split '/' | ForEach-Object { [regex]::Escape($_) })
  return (($partes -join '[\\/]') + '(?:[\\/][^\s''"<>|*?,;()\[\]]*)?')
}

function Add-ReglasNombres([object[]]$Pares, [string]$Con) {
  foreach ($n in @($Pares | Sort-Object { $_.Length } -Descending)) {
    Add-Regla ('(?<![A-Za-z0-9])' + [regex]::Escape($n) + '(?![A-Za-z0-9])') $Con
  }
}

function Initialize-Filtro {
  $repos = @(@('LEGACY', $Legacy), @('MIGRADO', $Migrado), @('PLANTILLA', $Plantilla))
  $rutas = @()
  foreach ($r in $repos) {
    foreach ($p in @($r[1], (Resolve-Param $r[1]))) {
      if ($p -and $p.Length -ge 3) { $rutas += [pscustomobject]@{ Tag = $r[0]; Ruta = $p } }
    }
  }
  foreach ($x in @($rutas | Sort-Object { $_.Ruta.Length } -Descending)) { Add-Regla (Get-PatronRuta $x.Ruta) ('<' + $x.Tag + '>') }
  foreach ($r in $repos) {
    $nombres = @()
    foreach ($p in @($r[1], (Resolve-Param $r[1]))) {
      if ($p) {
        $hoja = Split-Path ($p.TrimEnd('\', '/')) -Leaf
        if ($hoja -and $hoja.Length -ge 3) { $nombres += $hoja }
      }
    }
    Add-ReglasNombres @($nombres | Select-Object -Unique) ('<' + $r[0] + '>')
  }
  $casas = @([Environment]::GetFolderPath('UserProfile'), $env:USERPROFILE, $HOME | Where-Object { $_ -and $_.Length -ge 4 } | Select-Object -Unique)
  foreach ($c in @($casas | Sort-Object { $_.Length } -Descending)) { Add-Regla (Get-PatronRuta $c) '<CASA>' }
  # nombres de las clases de los tres repos (un mensaje de Copilot puede nombrarlas)
  $clases = @()
  foreach ($p in @($Legacy, $Migrado, $Plantilla)) {
    try {
      $raiz = Resolve-Param $p
      if ($raiz) { $clases += @(Get-JavaOriginal $raiz | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) } | Where-Object { $_.Length -ge 5 }) }
    }
    catch { }
  }
  $clases = @($clases | Select-Object -Unique | Sort-Object { $_.Length } -Descending)
  if ($clases.Count -gt 0) { Add-Regla ('(?<![A-Za-z0-9_])(?:' + ((@($clases | ForEach-Object { [regex]::Escape($_) })) -join '|') + ')(?![A-Za-z0-9_])') '<clase>' }
  # usuario, equipo y dominio (de 3 caracteres en adelante), el mas largo primero
  $ident = @()
  foreach ($v in @($env:USERDNSDOMAIN, $env:USERDOMAIN)) { if ($v -and $v.Length -ge 3) { $ident += [pscustomobject]@{ V = $v; Tag = '<dominio>' } } }
  foreach ($v in @($env:COMPUTERNAME, [Environment]::MachineName)) { if ($v -and $v.Length -ge 3) { $ident += [pscustomobject]@{ V = $v; Tag = '<equipo>' } } }
  foreach ($v in @($env:USERNAME, [Environment]::UserName)) { if ($v -and $v.Length -ge 3) { $ident += [pscustomobject]@{ V = $v; Tag = '<usuario>' } } }
  foreach ($x in @($ident | Sort-Object { $_.V.Length } -Descending)) {
    Add-Regla ('(?<![A-Za-z0-9])' + [regex]::Escape($x.V) + '(?![A-Za-z0-9])') $x.Tag
  }
  Add-Regla '[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}' '<correo>'
  Add-Regla '\b\d{1,3}(?:\.\d{1,3}){3}\b' '<ip>'
  Add-Regla '\b(?:[0-9a-f]{1,4}:){3,7}[0-9a-f]{1,4}\b' '<ip>'
  Add-Regla 'jdbc:[^\s''"<>]+' '<url-interna>'
  Add-Regla '\b[a-z][a-z0-9+.\-]*://([^/\s:?#''"<>()\[\]]*)(?::\d+)?[^\s''"<>()\[\]]*' '' {
    param($m)
    if ($script:Publicos -contains $m.Groups[1].Value.ToLowerInvariant()) { return $m.Value }
    return '<url-interna>'
  }
  # un servidor suelto: host:puerto, host/<ip> (el formato de Java), UnknownHostException y el id de un repositorio
  Add-Regla '(?<![\w.\-])[a-z0-9][a-z0-9\-]*(?:\.[a-z0-9\-]+)+:\d{2,5}\b(?!\.\d)' '<url-interna>'
  Add-Regla '(?<![\w.\-])[a-z0-9][a-z0-9\-]*(?:\.[a-z0-9\-]+)+(?=/<ip>)' '<url-interna>'
  Add-Regla '(?<=UnknownHostException: )\S+' '<url-interna>'
  Add-Regla '(?<=from/to )(?!central\b)[^\s(]+(?= \()' '<repo-id>'
  # lo que quede con forma de ruta: UNC, unidad, absoluta de Unix y relativa de 3 trozos o mas
  Add-Regla '\\\\[^\s''"<>|*?]+' '<ruta>'
  Add-Regla '(?<![A-Za-z0-9])[A-Za-z]:[\\/][^\s''"<>|*?]*' '<ruta>'
  Add-Regla '(?<![\w:/\\.<>\-])/[\w.\-~$@%+]+(?:/[\w.\-~$@%+]+)*' '<ruta>'
  Add-Regla '(?<![\w:/\\<>.\-])[\w.\-$~]+(?:[\\/][\w.\-$~]+){2,}' '<ruta>'
}

function Get-Seguro([string]$Texto) {
  if ($null -eq $Texto) { return '' }
  $t = [regex]::Replace($Texto, '\s+', ' ')
  foreach ($r in $script:Reglas) {
    if ($r.Evalua) { $t = $r.Re.Replace($t, [System.Text.RegularExpressions.MatchEvaluator]$r.Evalua) }
    else { $t = $r.Re.Replace($t, $r.Con) }
  }
  $t = ([regex]::Replace($t, '[^\x20-\x7E]', '?')).Trim()
  if ($t.Length -gt 200) { $t = $t.Substring(0, 200) }
  return $t
}

# Del mensaje de Test-Ficha, solo el principio: hasta el primer ':' o la primera comilla simple
# que no encierre uno de nuestros campos. Lo que sigue es lo que escribio el modelo (codigo de la empresa).
function Get-MotivoCorto([string]$Motivo) {
  $m = [regex]::Replace("$Motivo", 'clase-[0-9a-f]{8}', 'clase-_')
  $corte = $m.IndexOf(':')
  $i = $m.IndexOf("'")
  while ($i -ge 0) {
    $campo = [regex]::Match($m.Substring($i), "^'(?:fichero|clase|papel|queHace|datos|tipo|texto|linea|cita)'(?=\s|[.,;:)\]]|$)")
    if (-not $campo.Success) { if ($corte -lt 0 -or $i -lt $corte) { $corte = $i }; break }
    $i = $m.IndexOf("'", $i + $campo.Length)
  }
  if ($corte -ge 0) { $m = $m.Substring(0, $corte) }
  return $m.Trim()
}

# Un fallo de un bloque: el tipo y donde. En los bloques que tocan los repos del usuario, sin mensaje.
function Get-Fallo($Err, [bool]$SinMensaje) {
  $donde = ''
  if ($Err.InvocationInfo -and $Err.InvocationInfo.ScriptName) { $donde = ' (' + (Split-Path $Err.InvocationInfo.ScriptName -Leaf) + ':' + $Err.InvocationInfo.ScriptLineNumber + ')' }
  $tipo = $Err.Exception.GetType().Name
  if ($SinMensaje) { return ($tipo + $donde) }
  return ($tipo + ': ' + (Get-Seguro (("$($Err.Exception.Message)" -split "`r?`n")[0])) + $donde)
}

# =============================== UTILIDADES ===============================
function Resolve-Param([string]$Ruta) {
  if (-not $Ruta) { return '' }
  try { if (Test-Path -LiteralPath $Ruta) { return (Resolve-Path -LiteralPath $Ruta).Path.TrimEnd('\', '/') } }
  catch { }
  return ''
}

function Get-ArgsPowerShell([string[]]$Mas) {
  $a = @('-NoProfile')
  if ($env:OS -eq 'Windows_NT') { $a += @('-ExecutionPolicy', 'Bypass') }
  return ($a + @('-File') + $Mas)
}

# Un programa con tope de tiempo. Lo lanza como la biblioteca lanza a Copilot (Get-Lanzador: un .ps1 va por
# PowerShell, un .cmd por cmd) y devuelve Codigo, Texto (salida y errores), Agotado y Segundos.
function Invoke-Proceso([string]$Exe, [string[]]$A, [string]$Dir, [int]$Segundos) {
  $v = [pscustomobject]@{ Codigo = -1; Texto = ''; Agotado = $false; Segundos = 0 }
  $reloj = [System.Diagnostics.Stopwatch]::StartNew()
  $l = Get-Lanzador $Exe $A
  $pi = New-Object System.Diagnostics.ProcessStartInfo
  $pi.FileName = $l.Exe
  $pi.Arguments = $l.Args
  if ($Dir) { $pi.WorkingDirectory = $Dir }
  $pi.UseShellExecute = $false
  $pi.CreateNoWindow = $true
  $pi.RedirectStandardInput = $true
  $pi.RedirectStandardOutput = $true
  $pi.RedirectStandardError = $true
  $pi.StandardOutputEncoding = $Utf8
  $pi.StandardErrorEncoding = $Utf8
  $p = [System.Diagnostics.Process]::Start($pi)
  $p.StandardInput.Close()
  $o = $p.StandardOutput.ReadToEndAsync()
  $e = $p.StandardError.ReadToEndAsync()
  while (-not $p.HasExited) {
    if ($reloj.Elapsed.TotalSeconds -gt $Segundos) {
      Stop-Proceso $p
      [void]$p.WaitForExit(5000)
      $v.Agotado = $true
      break
    }
    Start-Sleep -Milliseconds 100
  }
  if (-not $v.Agotado) { $p.WaitForExit(); $v.Codigo = $p.ExitCode }
  $v.Texto = (Get-TextoPipe $o) + (Get-TextoPipe $e)
  $v.Segundos = [int]$reloj.Elapsed.TotalSeconds
  return $v
}

# El numero de version que sale en la salida de '<exe> <args>'.
function Get-Version([string]$Exe, [string[]]$A, [string]$Patron) {
  try {
    $r = Invoke-Proceso $Exe $A $PSScriptRoot 60
    if ($r.Agotado) { return 'tiempo agotado' }
    $m = [regex]::Match($r.Texto, $Patron)
    if ($m.Success) { return $m.Groups[1].Value }
    return 'desconocida'
  }
  catch { return 'no disponible' }
}

function Get-Segundos([double]$S) { return ([int][math]::Floor($S)) }

function New-Carpeta([string]$Ruta) {
  if (Test-Path -LiteralPath $Ruta) { Remove-Item -LiteralPath $Ruta -Recurse -Force }
  [void](New-Item -ItemType Directory -Path $Ruta -Force)
  return $Ruta
}

function Get-Lineas([string]$Ruta) { return @([System.IO.File]::ReadAllLines($Ruta)).Count }

# Una linea por resultado de Invoke-Ronda: json, datos y citas (los de una ficha que paso la comprobacion).
function Get-ResumenFicha($O) {
  if ($O.Estado -eq 'ok') {
    $d = @($O.Ficha.datos)
    $p = @($d | Where-Object { $_.probado }).Count
    return "json si | datos $($d.Count) | citas $p de $($d.Count) | $($O.Segundos) s"
  }
  if ($O.Estado -eq 'invalida') { return "json no | datos 0 | citas 0 de 0 | $($O.Segundos) s" }
  if ($O.Estado -eq 'tiempo') { return "tiempo | $($O.Segundos) s" }
  return "fallo, codigo $($O.Codigo) | $($O.Segundos) s"
}

# La primera linea [ERROR] de la salida de Maven (o la ultima linea), ya filtrada.
function Get-ErrorMaven([string]$Texto) {
  $lineas = @($Texto -split "`r?`n" | Where-Object { $_.Trim() })
  $e = @($lineas | Where-Object { $_ -match '^\[ERROR\]\s*\S' } | Select-Object -First 1)
  if ($e.Count -gt 0) { return (Get-Seguro ($e[0] -replace '^\[ERROR\]\s*', '')) }
  if ($lineas.Count -gt 0) { return (Get-Seguro $lineas[$lineas.Count - 1]) }
  return 'sin salida'
}

function Add-PasoMaven([string]$Nombre, [bool]$Ok, [int]$Segundos, [string]$Error) {
  Add-Linea ("${Nombre}: " + (Get-SiNo $Ok) + " | $Segundos s")
  if (-not $Ok) { Add-Linea ('error: ' + $Error) }
}

# Los numeros de un repo: ficheros .java de codigo, lineas, los que pasan de LineasPorTarea, el mas largo, modulos.
function Get-FormaRepo([string]$Raiz) {
  $java = @(Get-JavaOriginal $Raiz)
  $f = [pscustomobject]@{ Ficheros = $java.Count; Lineas = 0; Largos = 0; Max = 0; Modulos = 0 }
  foreach ($j in $java) {
    $n = Get-Lineas $j.FullName
    $f.Lineas += $n
    if ($n -gt $f.Max) { $f.Max = $n }
    if ($n -gt [int]$Cfg.LineasPorTarea) { $f.Largos++ }
  }
  $f.Modulos = @(Get-ChildItem -LiteralPath $Raiz -Recurse -Directory -Filter 'java' -ErrorAction SilentlyContinue | Where-Object {
      $rel = Get-Rel $Raiz $_.FullName
      ($rel -eq 'src/main/java' -or $rel.EndsWith('/src/main/java')) -and $rel -notmatch '(^|/)(\.git|target|node_modules|\.rescate)/'
    }).Count
  return $f
}

# Ficheros de un repo con ese filtro, sin entrar en .git, target, node_modules ni .rescate.
function Get-Ficheros([string]$Raiz, [string]$Filtro) {
  return @(Get-ChildItem -LiteralPath $Raiz -Recurse -File -Filter $Filtro -ErrorAction SilentlyContinue | Where-Object {
      (Get-Rel $Raiz $_.FullName) -notmatch '(^|/)(\.git|target|node_modules|\.rescate)/'
    })
}

# Los bloques: cada uno en su try; el fichero se reescribe al acabar cada uno.
function Invoke-Bloque([int]$N, [string]$Nombre, [int]$Minutos, [scriptblock]$Cuerpo, [bool]$SinMensaje = $false) {
  if ($SoloN.Count -gt 0 -and $SoloN -notcontains $N) { return }
  Write-Host "== $N $Nombre (hasta $Minutos min)..."
  Add-Linea "== $N $Nombre"
  $bien = $true
  try { & $Cuerpo }
  catch {
    $bien = $false
    Add-Linea ('fallo: ' + (Get-Fallo $_ $SinMensaje))
    $script:Fallos += $N
  }
  if ($bien) { Write-Host 'hecho' } else { Write-Host 'fallo' }
  Save-Resultado
}

# ================================== ARRANQUE ==================================
$SoloN = @()
foreach ($s in @($Solo)) {
  foreach ($p in ("$s" -split '[,;\s]+')) { if ($p -match '^\d+$') { $SoloN += [int]$p } }
}
$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('preflight-' + [System.Guid]::NewGuid().ToString('N').Substring(0, 8))
[void](New-Item -ItemType Directory -Path $Tmp -Force)
$Registros = New-Carpeta (Join-Path $Tmp 'registros')
$ModeloElegido = $Modelo
$LegacyRoot = ''

# ajustes.json pisa $Cfg. Read-CfgFile sale con 1 si el JSON no vale: se mira antes.
$AjustesEstado = 'no hay'
$rutaAjustes = Get-RutaAjustes
if (Test-Path -LiteralPath $rutaAjustes) {
  try {
    $null = ([System.IO.File]::ReadAllText($rutaAjustes) | ConvertFrom-Json)
    [void](Read-CfgFile $rutaAjustes @('Plantilla'))
    $AjustesEstado = 'leidos'
  }
  catch { $AjustesEstado = 'ilegibles' }
}
# un preflight no espera 15 minutos a una llamada: pasados 10 se da por colgada
if ([int]$Cfg.SegundosPorLlamada -gt 600) { $Cfg.SegundosPorLlamada = 600 }
try { Initialize-Filtro } catch { Add-Linea ('aviso: el filtro de privacidad no se cargo entero (' + $_.Exception.GetType().Name + ')') }
$raizMvn = $PSScriptRoot
if ($Migrado) { $raizMvn = $Migrado }
$despierto = Set-Despierto $true

Add-Linea $Cabecera
Write-Host $Cabecera

try {
  # ----------------------------------- 1 -----------------------------------
  Invoke-Bloque 1 'entorno' 2 {
    Add-Linea "modo de lenguaje: $modo"
    Add-Linea "powershell: $($PSVersionTable.PSVersion) $($PSVersionTable.PSEdition)"
    $ambitos = @()
    try { $ambitos = @(Get-ExecutionPolicy -List | ForEach-Object { "$($_.Scope)=$($_.ExecutionPolicy)" }) } catch { }
    Add-Linea ("politica de ejecucion: efectiva $(Get-ExecutionPolicy) | " + ($ambitos -join ', '))
    Add-Linea ('windows: ' + [Environment]::OSVersion.Version.ToString())
    Add-Linea ('git: ' + (Get-Version 'git' @('--version') '(\d+(?:\.\d+)+)'))
    Add-Linea ('java: ' + (Get-Version $Cfg.JavaExe @('-version') 'version "(\d[\d._]*)'))
    Add-Linea ('maven: ' + (Get-Version (Get-Mvn $raizMvn) @('--version') 'Apache Maven (\d+(?:\.\d+)+)'))
    Add-Linea ('copilot: ' + (Get-Version $Cfg.CopilotExe @('--version') '(\d+\.\d+(?:\.\d+)*)'))
    $tipo = 'ninguna'
    try {
      $c = @(Get-Command $Cfg.CopilotExe -ErrorAction SilentlyContinue)
      if ($c.Count -gt 0) {
        $ext = [System.IO.Path]::GetExtension("$($c[0].Source)").ToLowerInvariant()
        if ($ext) { $tipo = $ext }
      }
    }
    catch { }
    Add-Linea "tipo de copilot: $tipo"
    $suelta = Set-Despierto $false
    [void](Set-Despierto $true)
    Add-Linea ('impide la suspension: ' + (Get-SiNo $despierto) + ' | al soltar ' + (Get-SiNo $suelta))
    $cp = 'desconocida'
    try { $cp = "$([Console]::OutputEncoding.CodePage)" } catch { }
    Add-Linea "pagina de codigos: $cp"
    $gb = 'desconocido'
    try {
      $disco = New-Object System.IO.DriveInfo ([System.IO.Path]::GetPathRoot($raizMvn))
      $gb = ([math]::Round($disco.AvailableFreeSpace / 1GB, 1)).ToString('0.0', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    catch { }
    Add-Linea "GB libres: $gb"
    Add-Linea "ajustes: $AjustesEstado"
  }

  # ----------------------------------- 2 -----------------------------------
  Invoke-Bloque 2 'bancos' 15 {
    $fallan = @()
    foreach ($b in @('probar', 'probar-migracion')) {
      $ruta = Join-Path (Join-Path $PSScriptRoot 'tests') ($b + '.ps1')
      if (-not (Test-Path -LiteralPath $ruta)) { Add-Linea "${b}: no esta el fichero"; continue }
      $r = Invoke-Proceso (Get-PowerShellExe) (Get-ArgsPowerShell @($ruta, '-Dir', (Join-Path $Tmp $b))) $PSScriptRoot 1800
      if ($r.Agotado) { Add-Linea "${b}: tiempo agotado"; continue }
      $t = [regex]::Replace($r.Texto, '\x1b\[[0-9;]*m', '')
      $bien = [regex]::Match($t, 'TODO BIEN: (\d+) comprobaciones')
      $mal = [regex]::Match($t, 'FALLAN (\d+) de (\d+) comprobaciones')
      if ($bien.Success) { Add-Linea ("${b}: $($bien.Groups[1].Value) de $($bien.Groups[1].Value) en $($r.Segundos) s") }
      elseif ($mal.Success) { Add-Linea ("${b}: $([int]$mal.Groups[2].Value - [int]$mal.Groups[1].Value) de $($mal.Groups[2].Value) en $($r.Segundos) s") }
      else { Add-Linea "${b}: sin resultado (codigo $($r.Codigo)) en $($r.Segundos) s" }
      foreach ($m in [regex]::Matches($t, '(?m)^\s+FALLA (.+?)\s*$')) { $fallan += (Get-Seguro $m.Groups[1].Value) }
    }
    if ($fallan.Count -eq 0) { Add-Linea 'fallan: ninguna' } else { Add-Linea ('fallan: ' + (@($fallan | Select-Object -First 20) -join ' ; ')) }
  }

  # ----------------------------------- 3 -----------------------------------
  Invoke-Bloque 3 'copilot' 2 {
    $sondas = [ordered]@{
      '-p'                       = @('-p', 'prueba')
      '-s'                       = @('-s')
      '--allow-all-tools'        = @('--allow-all-tools')
      '--no-ask-user'            = @('--no-ask-user')
      '--deny-tool'              = @('--deny-tool=prueba')
      '--model'                  = @('--model=prueba')
      '--effort'                 = @('--effort=low')
      '--reasoning-effort'       = @('--reasoning-effort=low')
      '--add-dir'                = @('--add-dir=' + $PSScriptRoot)
      '--no-custom-instructions' = @('--no-custom-instructions')
      '--available-tools'        = @('--available-tools=view')
      '--max-ai-credits'         = @('--max-ai-credits=1')
    }
    foreach ($k in $sondas.Keys) {
      $v = 'no se pudo probar'
      try {
        $r = Invoke-Proceso $Cfg.CopilotExe (@($sondas[$k]) + '--version') $PSScriptRoot 60
        if (-not $r.Agotado) { $v = Get-SiNo ($r.Texto -notmatch 'unexpected argument') }
      }
      catch { }
      Add-Linea "bandera ${k}: $v"
    }
    $ids = @()
    try {
      $r = Invoke-Proceso $Cfg.CopilotExe @('--help') $PSScriptRoot 60
      foreach ($m in [regex]::Matches($r.Texto, '\b(?:gpt|claude|gemini)-[A-Za-z0-9][A-Za-z0-9._\-]*')) { $ids += (Get-Seguro ($m.Value.TrimEnd('.', '-'))) }
    }
    catch { }
    $ids = @($ids | Select-Object -Unique)
    Add-Linea ('ayuda lista modelos: ' + (Get-SiNo ($ids.Count -gt 0)))
    if ($ids.Count -gt 0) { Add-Linea ('modelos en la ayuda: ' + ($ids -join ', ')) }
  }

  # ----------------------------------- 4 -----------------------------------
  Invoke-Bloque 4 'aptitud' 20 {
    if ($SinCopilot) { Add-Linea 'saltado: -SinCopilot'; return }
    if ($Modelo) { Add-Linea ('modelo: ' + (Get-Seguro $Modelo)) } else { Add-Linea 'modelo: el de Copilot' }
    $dir = New-Carpeta (Join-Path $Tmp 'aptitud')
    Copy-Item -LiteralPath (Join-Ruta $PSScriptRoot 'tareas/aptitud/ValidadorImporte.java') -Destination (Join-Path $dir 'ValidadorImporte.java')
    $n = Get-Lineas (Join-Path $dir 'ValidadorImporte.java')
    $pasos = @(
      @{ Id = 'pf-apt-1'; Nombre = 'intento 1'; Intentos = 0; Extra = @() },
      @{ Id = 'pf-apt-2'; Nombre = 'intento 2'; Intentos = 0; Extra = @() },
      @{ Id = 'pf-apt-3'; Nombre = 'intento 3'; Intentos = 0; Extra = @() },
      @{ Id = 'pf-apt-alto'; Nombre = 'esfuerzo alto'; Intentos = 1; Extra = @() },
      @{ Id = 'pf-apt-herr'; Nombre = 'herramientas limitadas'; Intentos = 0; Extra = @('--available-tools=view,create') }
    )
    foreach ($p in $pasos) {
      $t = New-Tarea $p.Id 'aptitud' 'ValidadorImporte.java' 1 $n
      $t.intentos = $p.Intentos
      $argsAntes = @($Cfg.CopilotArgs)
      $Cfg.CopilotArgs = $argsAntes + $p.Extra
      $reloj = [System.Diagnostics.Stopwatch]::StartNew()
      try { $o = @(Invoke-Ronda @($t) $dir $dir)[0] }
      finally { $Cfg.CopilotArgs = $argsAntes }
      if ($p.Id -match '^pf-apt-\d$') { $script:SegundosIntentos += $reloj.Elapsed.TotalSeconds }
      if ($p.Id -eq 'pf-apt-1' -and ($o.Estado -eq 'fallo' -or $o.Estado -eq 'tiempo')) {
        $script:SinModelo = $true
        if ($o.Estado -eq 'fallo') { Add-Linea ('sin modelo: ' + (Get-Seguro $o.Linea)) } else { Add-Linea ('sin modelo: ' + (Get-Seguro $o.Motivo)) }
        return
      }
      Add-Linea ($p.Nombre + ': ' + (Get-ResumenFicha $o))
      if ($o.Estado -ne 'ok') { Add-Linea ('motivo: ' + (Get-Seguro $o.Motivo)) }
    }
  }

  # ----------------------------------- 5 -----------------------------------
  Invoke-Bloque 5 'paralelo' 15 {
    if ($SinCopilot) { Add-Linea 'saltado: -SinCopilot'; return }
    if ($script:SinModelo) { Add-Linea 'saltado: sin modelo (bloque 4)'; return }
    $dir = New-Carpeta (Join-Path $Tmp 'paralelo')
    $lote = @()
    for ($i = 1; $i -le 4; $i++) {
      $f = "ValidadorImporte$i.java"
      Copy-Item -LiteralPath (Join-Ruta $PSScriptRoot 'tareas/aptitud/ValidadorImporte.java') -Destination (Join-Path $dir $f)
      $lote += , (New-Tarea "pf-par-$i" "pf-par-$i" $f 1 (Get-Lineas (Join-Path $dir $f)))
    }
    $reloj = [System.Diagnostics.Stopwatch]::StartNew()
    $res = @(Invoke-Ronda $lote $dir $dir)
    $total = $reloj.Elapsed.TotalSeconds
    $validas = @($res | Where-Object { $_.Estado -eq 'ok' }).Count
    $lenta = ($res | Measure-Object -Property Segundos -Maximum).Maximum
    Add-Linea ("validas: $validas de 4 | $(Get-Segundos $total) s en total | la mas lenta $lenta s")
    if ($script:SegundosIntentos.Count -gt 0 -and $total -gt 0) {
      $media = ($script:SegundosIntentos | Measure-Object -Average).Average
      $x = ([math]::Round(($media * 4) / $total, 1)).ToString('0.0', [System.Globalization.CultureInfo]::InvariantCulture)
      Add-Linea ('frente a serie: ' + $x.Replace('.', ','))
    }
    else { Add-Linea 'frente a serie: sin medida (falta el bloque 4)' }
    for ($i = 0; $i -lt $res.Count; $i++) {
      if ($res[$i].Estado -ne 'ok') { Add-Linea ('motivo ' + ($i + 1) + ': ' + (Get-Seguro $res[$i].Motivo)) }
    }
  }

  # ----------------------------------- 6 -----------------------------------
  Invoke-Bloque 6 'maven de juguete' 45 {
    if ($SinMaven) { Add-Linea 'saltado: -SinMaven'; return }
    $dir = Join-Path $Tmp 'juguete'
    Copy-Item -LiteralPath (Join-Path (Join-Path $PSScriptRoot 'preflight') 'juguete') -Destination $dir -Recurse
    $mvn = Get-Mvn $raizMvn
    $jacoco = 'org.jacoco:jacoco-maven-plugin:0.8.16'
    $rewrite = 'org.openrewrite.maven:rewrite-maven-plugin:6.46.1'
    $r = Invoke-Proceso $mvn @('-B', 'test') $dir 1500
    Add-PasoMaven 'compila y pasa el test' (-not $r.Agotado -and $r.Codigo -eq 0) $r.Segundos (Get-ErrorMaven $r.Texto)
    $r = Invoke-Proceso $mvn @('-B', "${jacoco}:prepare-agent", 'test', "${jacoco}:report") $dir 1500
    $bien = (-not $r.Agotado -and $r.Codigo -eq 0 -and (Test-Path -LiteralPath (Join-Ruta $dir 'target/site/jacoco/jacoco.csv')))
    Add-PasoMaven 'jacoco' $bien $r.Segundos (Get-ErrorMaven $r.Texto)
    $r = Invoke-Proceso $mvn @('-B', "${rewrite}:run", '-Drewrite.activeRecipes=com.ejemplo.MoverSaludo') $dir 1500
    $seg = $r.Segundos
    $bien = (-not $r.Agotado -and $r.Codigo -eq 0)
    $msg = Get-ErrorMaven $r.Texto
    if ($bien -and -not (Test-Path -LiteralPath (Join-Ruta $dir 'src/main/java/com/ejemplo/application/usecase/Saludo.java'))) { $bien = $false; $msg = 'la clase no se movio' }
    if ($bien) {
      $r = Invoke-Proceso $mvn @('-B', 'test') $dir 1500
      $seg += $r.Segundos
      $bien = (-not $r.Agotado -and $r.Codigo -eq 0)
      $msg = Get-ErrorMaven $r.Texto
    }
    Add-PasoMaven 'openrewrite' $bien $seg $msg
  }

  # ----------------------------------- 7 -----------------------------------
  Invoke-Bloque 7 'forma de los repos' 30 {
    if (-not $Legacy -and -not $Migrado -and -not $Plantilla) { Add-Linea 'saltado: sin repos (-Legacy, -Migrado, -Plantilla)'; return }
    if ($Legacy) {
      $raiz = Resolve-Dir $Legacy
      $f = Get-FormaRepo $raiz
      Add-Linea "original ficheros java: $($f.Ficheros)"
      Add-Linea "original lineas: $($f.Lineas)"
      Add-Linea "original ficheros de mas de $($Cfg.LineasPorTarea) lineas: $($f.Largos)"
      Add-Linea "original fichero mas largo: $($f.Max) lineas"
      Add-Linea "original modulos (src/main/java): $($f.Modulos)"
      Add-Linea ('original pom.xml: ' + (Get-Ficheros $raiz 'pom.xml').Count)
      $xml = 0
      $jobs = 0
      foreach ($x in (Get-Ficheros $raiz '*.xml')) {
        $c = ([regex]::Matches([System.IO.File]::ReadAllText($x.FullName), '<(?:batch:)?job[\s>/]')).Count
        if ($c -gt 0) { $xml++; $jobs += $c }
      }
      Add-Linea "original xml con jobs: $xml (jobs: $jobs)"
      $batch = 0
      $malos = 0
      $estricto = New-Object System.Text.UTF8Encoding($false, $true)
      foreach ($j in @(Get-JavaOriginal $raiz)) {
        $bytes = [System.IO.File]::ReadAllBytes($j.FullName)
        try { $texto = $estricto.GetString($bytes) } catch { $malos++; $texto = [System.Text.Encoding]::GetEncoding(28591).GetString($bytes) }
        if ($texto -match 'JobBuilderFactory|JobBuilder|@EnableBatchProcessing') { $batch++ }
      }
      Add-Linea "original clases con JobBuilder o EnableBatchProcessing: $batch"
      Add-Linea "original ficheros no UTF-8: $malos"
    }
    foreach ($par in @(@('migrado', $Migrado), @('plantilla', $Plantilla))) {
      if (-not $par[1]) { continue }
      $f = Get-FormaRepo (Resolve-Dir $par[1])
      Add-Linea ("$($par[0]) ficheros java: $($f.Ficheros) | lineas: $($f.Lineas) | modulos: $($f.Modulos)")
    }
    if ($SinMaven) { Add-Linea 'diagnostico: saltado (-SinMaven)'; return }
    if (-not $Migrado -or -not $Plantilla) { Add-Linea 'diagnostico: saltado (faltan -Migrado y -Plantilla)'; return }
    $a = Get-ArgsPowerShell @((Join-Path $PSScriptRoot 'rescate.ps1'), '-Repo', (Resolve-Dir $Migrado), '-Plantilla', (Resolve-Dir $Plantilla), '-SinWorktree')
    $r = Invoke-Proceso (Get-PowerShellExe) $a $PSScriptRoot 1800
    if ($r.Agotado) { Add-Linea 'diagnostico: tiempo agotado'; return }
    Add-Linea "diagnostico: codigo $($r.Codigo) en $($r.Segundos) s"
    $t = [regex]::Replace($r.Texto, '\x1b\[[0-9;]*m', '')
    foreach ($m in [regex]::Matches($t, '(?m)^([a-z0-9]+)\s+(\d+)\s+(\d+)\s*$')) {
      Add-Linea ("$($m.Groups[1].Value): $($m.Groups[2].Value) errores, $($m.Groups[3].Value) avisos")
    }
  } $true

  # ----------------------------------- 8 -----------------------------------
  Invoke-Bloque 8 'clases reales' 40 {
    if ($SinCopilot) { Add-Linea 'saltado: -SinCopilot'; return }
    if (-not $Legacy) { Add-Linea 'saltado: falta -Legacy'; return }
    if ($script:SinModelo) { Add-Linea 'saltado: sin modelo (bloque 4)'; return }
    $raiz = Resolve-Dir $Legacy
    # las 5: la mas corta de mas de 20 lineas, los percentiles 25, 50 y 75 y la mas larga que cabe en una tarea
    $cand = @()
    foreach ($j in @(Get-JavaOriginal $raiz)) {
      $n = Get-Lineas $j.FullName
      if ($n -gt 20 -and $n -le [int]$Cfg.LineasPorTarea) { $cand += [pscustomobject]@{ Rel = (Get-Rel $raiz $j.FullName); Lineas = $n } }
    }
    $cand = @($cand | Sort-Object Lineas, Rel)
    if ($cand.Count -eq 0) { Add-Linea ('saltado: ningun fichero entre 21 y ' + $Cfg.LineasPorTarea + ' lineas'); return }
    $k = $cand.Count - 1
    $idx = @(@(0, [int][math]::Floor($k * 0.25), [int][math]::Floor($k * 0.5), [int][math]::Floor($k * 0.75), $k) | Select-Object -Unique)
    $dir = New-Carpeta (Join-Path $Tmp 'clases')
    $lote = @()
    $i = 0
    foreach ($x in $idx) {
      $i++
      $lote += , (New-Tarea "pf-cls-$i" "pf-cls-$i" $cand[$x].Rel 1 $cand[$x].Lineas)
    }
    $antes = Get-Huella $raiz
    $script:LegacyRoot = $raiz
    $res = @()
    try {
      $paso = [int]$Cfg.Paralelo
      for ($d = 0; $d -lt $lote.Count; $d += $paso) {
        $hasta = [math]::Min($d + $paso, $lote.Count) - 1
        $res += @(Invoke-Ronda @($lote[$d..$hasta]) $dir $raiz)
      }
    }
    finally { $script:LegacyRoot = '' }
    for ($i = 0; $i -lt $res.Count; $i++) {
      Add-Linea ('clase ' + ($i + 1) + ': ' + $cand[$idx[$i]].Lineas + ' lineas | ' + (Get-ResumenFicha $res[$i]))
      if ($res[$i].Estado -eq 'invalida') { Add-Linea ('motivo: ' + (Get-Seguro (Get-MotivoCorto $res[$i].Motivo))) }
    }
    Add-Linea ('original sin cambios: ' + (Get-SiNo ((Get-Huella $raiz) -ceq $antes)))
  } $true
}
finally {
  # ---------------------------------- fin ----------------------------------
  Add-Linea '== fin'
  $conFallo = 'ninguno'
  if ($script:Fallos.Count -gt 0) { $conFallo = ($script:Fallos -join ' ') }
  Add-Linea "bloques con fallo: $conFallo"
  Add-Linea ('duracion: ' + [int]((Get-Date) - $Inicio).TotalMinutes + ' min')
  Save-Resultado
  [void](Set-Despierto $false)
  try { Remove-Item -LiteralPath $Tmp -Recurse -Force } catch { }
  Write-Host ''
  foreach ($l in $script:Lineas) { Write-Host $l }
  if ($env:OS -eq 'Windows_NT') {
    try { Set-Clipboard -Value ($script:Lineas -join "`r`n") } catch { }
  }
}
if ($script:NoEscribe) { exit 1 }
exit 0
