<#
comun.ps1 - Lo que comparten rescate.ps1 y migracion.ps1. No se ejecuta solo:
cada script lo carga con '. (Join-Path $PSScriptRoot 'comun.ps1')'. Solo ASCII.
Las funciones usan variables del script que las carga: $Cfg, $Si, $Worktree,
$OrigenRoot (la carpeta del usuario) y $RepoRoot (la carpeta donde se trabaja:
el worktree de rescate). Cada script las define antes de llamarlas.
Los flags de Copilot y la ruta de Maven se ajustan aqui o en .rescate/config.json.
Tambien lanza programas con tope de tiempo (Invoke-Proceso, con el lanzador de Copilot).
#>

# ============================ CONFIGURACION ============================
# Claves que valen para los dos scripts; cada script anade las suyas con '$Cfg += @{...}'.
$Cfg = @{
  # Copilot CLI. Si tu version no conoce algun flag, quitalo de aqui.
  CopilotExe    = 'copilot'
  CopilotArgs   = @('-s', '--allow-all-tools', '--no-ask-user', '--deny-tool=shell(git push)')
  CommitArgs    = @()     # p.ej. @('--no-verify') si un hook local bloquea
  MvnExe        = ''      # vacio = mvnw del repo o, si no hay, mvn del PATH
  DirsIgnorados = @('.git', 'target', '.rescate', 'node_modules', '.idea', '.vscode', '.github', '.mvn')
  SegundosLatido = 60     # cada cuantos segundos escribe '... sigue' mientras espera a Copilot o a Maven (0 = nunca)
  MinutosMaven   = 30     # tope de cada llamada a Maven, en minutos (admite decimales); pasado, se para Maven con sus procesos hijos y la llamada cuenta como fallida
  MinutosCopilot = 20     # tope de cada llamada a Copilot de rescate.ps1, en minutos (admite decimales); pasado, se para Copilot con sus procesos hijos
}

# ============================== UTILIDADES ==============================
$Utf8 = New-Object System.Text.UTF8Encoding($false)

function Info([string]$m) { Write-Host $m }
function Bien([string]$m) { Write-Host $m -ForegroundColor Green }
function Aviso([string]$m) { Write-Host $m -ForegroundColor Yellow }
function Fallo([string]$m) { Write-Host $m -ForegroundColor Red }

# Ejecuta un programa externo sin que su stderr rompa el script (PS 5.1).
function Invoke-Nativo {
  param([string]$Exe, [string[]]$Argumentos = @(), [string]$Dir = '')
  $ErrorActionPreference = 'Continue'
  $out = $null
  $code = 0
  if ($Dir) { Push-Location -LiteralPath $Dir }
  try {
    $out = & $Exe @Argumentos 2>&1 | ForEach-Object { "$_" }
    $code = $LASTEXITCODE
  }
  finally { if ($Dir) { Pop-Location } }
  if ($null -eq $code) { $code = 0 }
  if ($null -eq $out) { $out = @() }
  return [pscustomobject]@{ Codigo = $code; Salida = @($out) }
}

# De lo que PowerShell encuentra con un nombre (Get-Command -All, en su orden: CommandType y Source), el fichero que se
# lanza, o $null. Solo cuentan los ficheros (Application, ExternalScript): una funcion o un alias no tienen ruta. En
# Windows el fichero tiene que acabar en una extension que se pueda lanzar (el 'copilot' sin extension que deja npm no);
# fuera de Windows vale el primer fichero, porque ahi un ejecutable no lleva extension.
function Select-Lanzable($Candidatos, [bool]$EsWindows) {
  foreach ($c in $Candidatos) {
    if (@('Application', 'ExternalScript') -notcontains "$($c.CommandType)") { continue }
    $ruta = "$($c.Source)"
    if (-not $ruta) { continue }
    if (-not $EsWindows) { return $ruta }
    if (@('.exe', '.com', '.cmd', '.bat', '.ps1') -contains [System.IO.Path]::GetExtension($ruta).ToLowerInvariant()) { return $ruta }
  }
  return $null
}

# El fichero que se lanza con un nombre o una ruta (Select-Lanzable sobre lo que da Get-Command): su Ruta, o $null y un
# Mensaje que dice que es lo que hay. Lo usan Get-Lanzador, el preflight y rescate.ps1: una sola regla.
function Get-Lanzable([string]$Exe) {
  $encontrados = @()
  if ($Exe) { $encontrados = @(Get-Command $Exe -All -ErrorAction SilentlyContinue) }
  $ruta = Select-Lanzable $encontrados ($env:OS -eq 'Windows_NT')
  $mensaje = ''
  if (-not $ruta) {
    $hay = 'nada'
    if ($encontrados.Count -gt 0) {
      $tipo = "$($encontrados[0].CommandType)"
      if ($tipo -eq 'Function') { $hay = 'funcion' }
      elseif ($tipo -eq 'Alias') { $hay = 'alias' }
      elseif ($tipo -eq 'Cmdlet') { $hay = 'cmdlet' }
      elseif ([System.IO.Path]::GetExtension("$($encontrados[0].Source)")) { $hay = 'fichero con otra extension' }
      else { $hay = 'fichero sin extension' }
    }
    $mensaje = "No puedo lanzar '" + (($Exe -replace '\\', '/') -split '/')[-1] + "': aqui es $hay. Pon la ruta entera del .cmd o del .exe en CopilotExe de ajustes.json."
  }
  return [pscustomobject]@{ Ruta = $ruta; Mensaje = $mensaje }
}

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
    else { $P.Kill($true) }   # fuera de Windows, el arbol entero, como taskkill /T
  }
  catch { }
}

# Lo que ha escrito una tuberia; si un nieto la mantiene abierta no espera para siempre.
function Get-TextoPipe($Tarea) {
  if ($Tarea.Wait(3000)) { return $Tarea.Result }
  return ''
}

# Un programa con tope de tiempo. Lo lanza con Get-Lanzador (un .ps1 va por PowerShell, un .cmd por cmd), como a Copilot, y
# devuelve Codigo, Texto (salida y errores), Agotado y Segundos. Con $ComoNativo se comporta como Invoke-Nativo en lo que ve el
# programa: hereda la entrada del script (no la cierra) y su salida se decodifica con la codificacion de la consola.
function Invoke-Proceso([string]$Exe, [string[]]$A, [string]$Dir, [int]$Segundos, [bool]$ComoNativo = $false) {
  $v = [pscustomobject]@{ Codigo = -1; Texto = ''; Agotado = $false; Segundos = 0 }
  $reloj = [System.Diagnostics.Stopwatch]::StartNew()
  $l = Get-Lanzador $Exe $A
  $pi = New-Object System.Diagnostics.ProcessStartInfo
  $pi.FileName = $l.Exe
  $pi.Arguments = $l.Args
  if ($Dir) { $pi.WorkingDirectory = $Dir }
  $pi.UseShellExecute = $false
  $pi.CreateNoWindow = $true
  $pi.RedirectStandardInput = -not $ComoNativo
  $pi.RedirectStandardOutput = $true
  $pi.RedirectStandardError = $true
  $codificacion = $Utf8
  if ($ComoNativo) { $codificacion = [Console]::OutputEncoding }
  $pi.StandardOutputEncoding = $codificacion
  $pi.StandardErrorEncoding = $codificacion
  $p = [System.Diagnostics.Process]::Start($pi)
  if (-not $ComoNativo) { $p.StandardInput.Close() }
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

# Latido: mientras un programa largo corre, una linea cada $Cada segundos para que se vea que el script sigue vivo
# ("  ... sigue: <que> (lleva N min M s)"). Corre en un runspace aparte, asi no cambia como se lanzan los programas.
# Devuelve $null si no se puede crear (y Stop-Latido $null no hace nada): el latido nunca rompe nada. Usar con try/finally.
function Start-Latido([string]$Que, [int]$Cada) {
  if ($Cada -lt 1) { return $null }
  try {
    $cuerpo = {
      param([string]$Que, [int]$Cada)
      $reloj = [System.Diagnostics.Stopwatch]::StartNew()
      while ($true) {
        Start-Sleep -Seconds $Cada
        $s = [int][Math]::Floor($reloj.Elapsed.TotalSeconds)
        [Console]::WriteLine('  ... sigue: ' + $Que + ' (lleva ' + [Math]::Floor($s / 60) + ' min ' + ($s % 60) + ' s)')
      }
    }
    $ps = [powershell]::Create()
    [void]$ps.AddScript($cuerpo.ToString()).AddArgument($Que).AddArgument($Cada)
    [void]$ps.BeginInvoke()
    return $ps
  }
  catch { return $null }
}

# Para el latido y libera su runspace. Cuando vuelve no sale ninguna linea mas.
function Stop-Latido($Latido) {
  if ($null -eq $Latido) { return }
  try { $Latido.Stop() } catch { $null = $_ }
  try { $Latido.Dispose() } catch { $null = $_ }
}

function Invoke-Git([string]$Dir, [string[]]$A) { return Invoke-Nativo 'git' (@('-C', $Dir) + $A) }

function Get-Rel([string]$Raiz, [string]$Completa) {
  return (($Completa.Substring($Raiz.Length).TrimStart('\', '/')) -replace '\\', '/')
}

function Join-Ruta([string]$Raiz, [string]$Rel) {
  $p = $Raiz
  foreach ($s in $Rel.Split('/')) { if ($s) { $p = Join-Path $p $s } }
  return $p
}

function Resolve-Dir([string]$p) {
  if (-not $p) { return '' }
  if (-not (Test-Path -LiteralPath $p)) { throw "No existe la carpeta: $p" }
  return (Resolve-Path -LiteralPath $p).Path.TrimEnd('\', '/')
}

function Get-JavaFiles([string]$Dir) {
  if (-not (Test-Path -LiteralPath $Dir)) { return @() }
  return @(Get-ChildItem -LiteralPath $Dir -Recurse -File -Filter '*.java')
}

function Confirmar([string]$Pregunta) {
  if ($Si) { return $true }
  $r = Read-Host "$Pregunta (s/n)"
  return ($r -match '^[sSyY]')
}

# Argumentos de 'copilot -p': el texto, los flags comunes, modelo, esfuerzo y
# las carpetas que puede leer. Vacio = lo que tenga configurado Copilot.
function Get-ArgsCopilot([string]$Texto, [string]$Mod, [string]$Esf, [string[]]$Dirs, [bool]$SinInstr) {
  $a = @('-p', $Texto) + $Cfg.CopilotArgs
  if ($Mod) { $a += "--model=$Mod" }
  if ($Esf) { $a += "--effort=$Esf" }
  if ($SinInstr) { $a += '--no-custom-instructions' }
  foreach ($d in $Dirs) { if ($d) { $a += "--add-dir=$d" } }
  return $a
}

# Los esfuerzos que se prueban, del mas alto al mas bajo, si el modelo no admite el pedido (preflight y rescate).
function Get-EsfuerzosMenores([string]$Esfuerzo) {
  if ($Esfuerzo -ceq 'max') { return @('xhigh', 'high') }
  if ($Esfuerzo -ceq 'xhigh') { return @('high') }
  return @()
}

# Maven del repo: el de -MvnExe, el mvnw de la raiz o el mvn del PATH.
function Get-Mvn([string]$Raiz) {
  if ($Cfg.MvnExe) { return $Cfg.MvnExe }
  if ([System.IO.Path]::DirectorySeparatorChar -eq '\') { $w = Join-Path $Raiz 'mvnw.cmd' } else { $w = Join-Path $Raiz 'mvnw' }
  if (Test-Path -LiteralPath $w) { return $w }
  return 'mvn'
}

# Maven en $Dir con los argumentos $A, con latido ($Que) y con tope: pasados $Cfg.MinutosMaven minutos se para Maven con sus
# procesos hijos (Stop-Proceso) y la llamada cuenta como fallida (Codigo -1). Lo que haya escrito queda en $Registro. Devuelve
# Codigo, Salida (las lineas: las de la salida y despues las de errores) y Tope: '' o el mensaje que dice que se ha pasado, que
# sale tambien por la consola. Lo usan rescate.ps1, la cobertura de tareas.ps1 y prueba-local.ps1: una sola regla.
function Invoke-MavenTope([string]$Dir, [string[]]$A, [string]$Que, [string]$Registro) {
  $latido = Start-Latido $Que $Cfg.SegundosLatido
  try { $p = Invoke-Proceso (Get-Mvn $Dir) $A $Dir ([int][Math]::Ceiling([double]$Cfg.MinutosMaven * 60)) }
  finally { Stop-Latido $latido }
  $salida = @()
  if ($p.Texto) { $salida = @(($p.Texto -replace '\r?\n$', '') -split '\r?\n') }
  [System.IO.File]::WriteAllText($Registro, (($salida -join "`n") + "`n"), $Utf8)
  $r = [pscustomobject]@{ Codigo = $p.Codigo; Salida = $salida; Tope = '' }
  if ($p.Agotado) {
    $r.Tope = "Maven se ha pasado del tope de $($Cfg.MinutosMaven) min y se ha parado ($Que). Registro: $Registro."
    Aviso $r.Tope
  }
  return $r
}

# Huella de una carpeta de solo lectura, para detectar si alguien la toca.
function Get-Huella([string]$Dir) {
  if (-not $Dir) { return '' }
  if (Test-Path -LiteralPath (Join-Path $Dir '.git')) {
    $a = (Invoke-Git $Dir @('rev-parse', 'HEAD')).Salida -join ''
    $b = (Invoke-Git $Dir @('status', '--porcelain')).Salida -join "`n"
    $c = (Invoke-Git $Dir @('diff', 'HEAD', '--numstat')).Salida -join "`n"
    return "$a`n$b`n$c"
  }
  $fs = @(Get-ChildItem -LiteralPath $Dir -Recurse -File)
  $max = ($fs | Measure-Object -Property LastWriteTimeUtc -Maximum).Maximum
  return "$($fs.Count)|$max"
}

# Deshace en $RepoRoot (la carpeta de trabajo) todo lo hecho desde el commit $Check.
function Undo-Lote([string]$Rama, [string]$Check) {
  [void](Invoke-Git $RepoRoot @('checkout', '-q', '-f', $Rama))
  [void](Invoke-Git $RepoRoot @('reset', '-q', '--hard', $Check))
  [void](Invoke-Git $RepoRoot @('clean', '-fdq'))
}

# Lo cambiado en una carpeta de git desde lo ultimo que se dio por bueno (su indice): rutas relativas, sin .rescate (los
# prompts) ni target.
function Get-Cambios([string]$Dir) {
  $r = Invoke-Git $Dir @('-c', 'core.quotepath=off', 'status', '--porcelain', '--untracked-files=all', '--', '.', ':(exclude).rescate', ':(exclude)target')
  return @($r.Salida | Where-Object { $_.Length -gt 3 -and $_[1] -ne ' ' } | ForEach-Object { $_.Substring(3).Trim('"') })
}

# Lo que Maven deja fuera de target (un log, una base en fichero, la salida de un test) no es de la IA. Tras una ejecucion
# de Maven: borra lo que ha aparecido en ella (lo que no estaba en $Previos, el Get-Cambios de antes de lanzarla) y deshace
# lo que ha cambiado de lo que git ya tenia. Lo de antes no se toca. Devuelve las rutas que ha quitado.
function Remove-Ruido([string]$Dir, [string[]]$Previos) {
  $ruido = @(Get-Cambios $Dir | Where-Object { $Previos -notcontains $_ })
  if ($ruido.Count -eq 0) { return @() }
  [void](Invoke-Git $Dir (@('clean', '-fdq', '--') + $ruido))
  $quedan = @(Get-Cambios $Dir | Where-Object { $ruido -contains $_ })
  if ($quedan.Count -gt 0) { [void](Invoke-Git $Dir (@('checkout', '-q', '--') + $quedan)) }
  return $ruido
}

function Get-Rama([string]$Dir) { return ((Invoke-Git $Dir @('rev-parse', '--abbrev-ref', 'HEAD')).Salida -join '').Trim() }

function Get-Head([string]$Dir) { return ((Invoke-Git $Dir @('rev-parse', 'HEAD')).Salida -join '').Trim() }

# ============================== WORKTREE ==============================
# .rescate, target y migracion-* se ignoran solo en local (no toca .gitignore).
# info/exclude lo comparten el repo y todos sus worktrees.
function Set-Excluidos([string]$Dir) {
  $exc = ((Invoke-Git $Dir @('rev-parse', '--git-path', 'info/exclude')).Salida -join '').Trim()
  if (-not $exc) { return }
  if (-not [System.IO.Path]::IsPathRooted($exc)) { $exc = Join-Path $Dir $exc }
  $dirExc = Split-Path $exc -Parent
  if (-not (Test-Path -LiteralPath $dirExc)) { [void](New-Item -ItemType Directory -Path $dirExc) }
  $ya = ''
  if (Test-Path -LiteralPath $exc) { $ya = [System.IO.File]::ReadAllText($exc) }
  if ($ya -notmatch '(?m)^\.rescate/') { [System.IO.File]::AppendAllText($exc, "`n.rescate/`ntarget/`n") }
  if ($ya -notmatch '(?m)^migracion-\*/') { [System.IO.File]::AppendAllText($exc, "`nmigracion-*/`n") }
}

# Donde esta ajustes.json: RESCATE_HOME o la carpeta .rescate del usuario.
function Get-RutaAjustes {
  if ($env:RESCATE_HOME) { return (Join-Path $env:RESCATE_HOME 'ajustes.json') }
  return (Join-Path (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.rescate') 'ajustes.json')
}

# Lee un .json de ajustes y pisa las claves de $Cfg. Las claves de $Aparte las
# trata quien llama (aqui no se avisa de ellas) y con $Avisar en $false no se avisa
# de ninguna desconocida (ajustes.json lleva claves de otros scripts). Devuelve el objeto leido o $null.
function Read-CfgFile([string]$Ruta, [string[]]$Aparte = @(), [bool]$Avisar = $true) {
  if (-not (Test-Path -LiteralPath $Ruta)) { return $null }
  try {
    $o = [System.IO.File]::ReadAllText($Ruta) | ConvertFrom-Json
    foreach ($pr in $o.PSObject.Properties) {
      if ($Cfg.ContainsKey($pr.Name)) { $Cfg[$pr.Name] = $pr.Value }
      elseif ($Avisar -and ($Aparte -notcontains $pr.Name)) { Aviso ((Split-Path $Ruta -Leaf) + ": clave desconocida '$($pr.Name)'") }
    }
    return $o
  }
  catch { Fallo ("No puedo leer $Ruta" + ': ' + $_.Exception.Message); exit 1 }
}

# Ajustes propios de un repo: su .rescate/config.json pisa las claves de $Cfg.
function Read-Config([string]$Raiz) {
  [void](Read-CfgFile (Join-Path (Join-Path $Raiz '.rescate') 'config.json'))
}

function Get-DirRescate {
  if ($Worktree) { return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Worktree).TrimEnd('\', '/') }
  return ($OrigenRoot + '-rescate')
}

# Es $Dir un worktree de ESTE repo en una rama rescate/?
# (la rama es de este repo si aqui apunta al mismo commit que alli)
function Test-WorktreeRescate([string]$Dir) {
  if (-not (Test-Path -LiteralPath (Join-Path $Dir '.git'))) { return $false }
  $rama = Get-Rama $Dir
  if (-not $rama.StartsWith('rescate/')) { return $false }
  $alli = Get-Head $Dir
  $aqui = ((Invoke-Git $OrigenRoot @('rev-parse', '--verify', '-q', "refs/heads/$rama")).Salida -join '').Trim()
  return [bool]($alli -and ($alli -eq $aqui))
}

# Copia al worktree lo que hay sin commit en la carpeta original, sin tocarla,
# y lo guarda en un commit 'foto'. Devuelve '' o el motivo del fallo.
function Copy-Sucio([string]$Dir, [bool]$HaySeguidos) {
  if ($HaySeguidos) {
    # stash create hace un commit con el estado actual y no cambia nada
    $w = (@((Invoke-Git $OrigenRoot @('stash', 'create')).Salida | Where-Object { $_ -match '^[0-9a-f]{40,64}$' } | Select-Object -Last 1) -join '')
    if (-not $w) { return 'git stash create no ha devuelto nada' }
    $r = Invoke-Git $Dir @('read-tree', '--reset', '-u', $w)
    if ($r.Codigo -ne 0) { return ('git read-tree: ' + ($r.Salida -join ' ')) }
  }
  foreach ($rel in @((Invoke-Git $OrigenRoot @('-c', 'core.quotepath=off', 'ls-files', '--others', '--exclude-standard')).Salida | Where-Object { $_ })) {
    $de = Join-Ruta $OrigenRoot $rel
    if (-not (Test-Path -LiteralPath $de -PathType Leaf)) { return "no encuentro el fichero sin seguimiento '$rel'" }
    $a = Join-Ruta $Dir $rel
    $carpeta = Split-Path $a -Parent
    if (-not (Test-Path -LiteralPath $carpeta)) { [void](New-Item -ItemType Directory -Path $carpeta -Force) }
    Copy-Item -LiteralPath $de -Destination $a -Force
  }
  [void](Invoke-Git $Dir @('add', '-A'))
  $r = Invoke-Git $Dir (@('commit', '-q', '-m', 'rescate: foto del estado antes de empezar') + $Cfg.CommitArgs)
  if ($r.Codigo -ne 0) { return ('git commit: ' + ($r.Salida -join ' ')) }
  return ''
}

# Lo que git ignora (configuracion local, .env...) no viaja al worktree.
function Show-Ignorados {
  $ign = @((Invoke-Git $OrigenRoot @('-c', 'core.quotepath=off', 'ls-files', '--others', '--ignored', '--exclude-standard', '--directory')).Salida | Where-Object { $_ } | Where-Object {
      $p = $_.TrimEnd('/')
      $enIgnorada = @($p.Split('/') | Where-Object { $Cfg.DirsIgnorados -contains $_ }).Count -gt 0
      (-not $enIgnorada) -and ($p -notmatch '\.(class|log|iml)$') -and ($p -notmatch '^migracion-[^/]*$') })
  if ($ign.Count -eq 0) { return }
  Aviso 'Ojo: git ignora estos ficheros de tu carpeta y por eso NO estan en el worktree.'
  Aviso 'Si el build o los tests los necesitan, copialos a mano:'
  $ign | Select-Object -First 12 | ForEach-Object { Info "  $_" }
}

# Crea el worktree de rescate al lado del repo. La carpeta original no se toca.
function New-WorktreeRescate([string]$Dir) {
  $rama = Get-Rama $OrigenRoot
  if ($rama -eq 'HEAD' -or -not $rama) { Fallo 'El repo no esta en una rama (detached HEAD).'; exit 1 }
  if (Test-Path -LiteralPath $Dir) { Fallo "La carpeta '$Dir' ya existe y no es un worktree de rescate de este repo. Borrala o elige otra con -Worktree."; exit 1 }
  $nueva = 'rescate/' + ($rama -replace '[^\w\.\-]', '-') + '-' + (Get-Date -Format 'yyyyMMdd-HHmm')
  $sucio = @((Invoke-Git $OrigenRoot @('status', '--porcelain')).Salida | Where-Object { $_ })
  Info "El rescate trabaja en una carpeta aparte (worktree de git): $Dir"
  Info "Rama nueva: '$nueva'. Tu carpeta y tu rama '$rama' no se tocan."
  if ($sucio.Count -gt 0) {
    Aviso "Tienes $($sucio.Count) cambios sin commit. Se copian al worktree en un commit 'foto':"
    $sucio | Select-Object -First 15 | ForEach-Object { Info "  $_" }
  }
  if (-not (Confirmar 'Seguir?')) { exit 0 }
  $r = Invoke-Git $OrigenRoot @('worktree', 'add', '-q', '-b', $nueva, $Dir, 'HEAD')
  if ($r.Codigo -ne 0) { Fallo ('No pude crear el worktree: ' + ($r.Salida -join ' ')); exit 1 }
  if ($sucio.Count -gt 0) {
    $haySeguidos = (@($sucio | Where-Object { $_ -notmatch '^\?\?' }).Count -gt 0)
    $motivo = Copy-Sucio $Dir $haySeguidos
    if ($motivo) {
      # un worktree sin tus cambios daria un diagnostico falso: mejor no dejarlo
      [void](Invoke-Git $OrigenRoot @('worktree', 'remove', '--force', $Dir))
      [void](Invoke-Git $OrigenRoot @('branch', '-D', $nueva))
      Fallo "No pude copiar al worktree tus cambios sin commit ($motivo). He borrado el worktree."
      Fallo 'Haz commit de tus cambios y vuelve a lanzar.'
      exit 3
    }
  }
  # lo ya hecho en .rescate (contrato del pre, ajustes, planes) viaja al worktree
  $de = Join-Path $OrigenRoot '.rescate'
  if (Test-Path -LiteralPath $de) {
    $a = Join-Path $Dir '.rescate'
    if (-not (Test-Path -LiteralPath $a)) { [void](New-Item -ItemType Directory -Path $a) }
    foreach ($f in @(Get-ChildItem -LiteralPath $de -File | Where-Object { $_.Name -match '^(contrato\.json|config\.json|plan-.+\.md)$' })) {
      Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $a $f.Name) -Force
    }
  }
  Show-Ignorados
  Bien "Worktree creado: $Dir"
}

# Lo que ha gastado una llamada de Copilot, del fichero que escribe --usage-output-file. Devuelve Creditos (totalNanoAiu / 1e9),
# NanoAiu, Premium, MsApi y los tokens: la suma, dentro de modelMetrics, de toda hoja numerica cuyo nombre case con
# input.*tokens, output.*tokens, cache.*tokens o reasoning.*tokens (sin distinguir mayusculas; cada hoja cuenta en un solo
# grupo, mirando primero cache y reasoning). Campos son los nombres de las hojas numericas de modelMetrics. Sin fichero, con
# un JSON ilegible o sin el dato, el valor es $null: nunca 0 (un dato que falta no es un gasto de cero).
function Read-Uso([string]$Ruta) {
  $u = [pscustomobject]@{ Creditos = $null; NanoAiu = $null; Premium = $null; MsApi = $null; TokensEntrada = $null; TokensSalida = $null; TokensCache = $null; TokensRazonamiento = $null; Campos = @() }
  function Test-Numero($V) { return ($V -is [int] -or $V -is [long] -or $V -is [double] -or $V -is [decimal] -or $V -is [single]) }
  function Get-Hojas($Nodo, [string]$Nombre) {
    if ($Nodo -is [System.Management.Automation.PSCustomObject]) {
      foreach ($p in $Nodo.PSObject.Properties) { Get-Hojas $p.Value $p.Name }
    }
    elseif ($Nodo -is [System.Collections.IEnumerable] -and $Nodo -isnot [string]) {
      foreach ($x in $Nodo) { Get-Hojas $x $Nombre }
    }
    elseif (Test-Numero $Nodo) { [pscustomobject]@{ Nombre = $Nombre; Valor = [double]$Nodo } }
  }
  try { $o = [System.IO.File]::ReadAllText($Ruta) | ConvertFrom-Json }
  catch { return $u }
  if ($o -isnot [System.Management.Automation.PSCustomObject]) { return $u }
  if (Test-Numero $o.totalNanoAiu) { $u.NanoAiu = [long]$o.totalNanoAiu; $u.Creditos = [double]$o.totalNanoAiu / 1e9 }
  if (Test-Numero $o.totalPremiumRequestCost) { $u.Premium = [double]$o.totalPremiumRequestCost }
  if (Test-Numero $o.totalApiDurationMs) { $u.MsApi = [long]$o.totalApiDurationMs }
  $suma = @{}
  $campos = New-Object System.Collections.Generic.List[string]
  foreach ($h in @(Get-Hojas $o.modelMetrics '')) {
    if (-not $campos.Contains($h.Nombre)) { $campos.Add($h.Nombre) }
    $g = ''
    if ($h.Nombre -match '(?i)cache.*tokens') { $g = 'Cache' }
    elseif ($h.Nombre -match '(?i)reasoning.*tokens') { $g = 'Razonamiento' }
    elseif ($h.Nombre -match '(?i)input.*tokens') { $g = 'Entrada' }
    elseif ($h.Nombre -match '(?i)output.*tokens') { $g = 'Salida' }
    if ($g) { $suma[$g] = [double]$suma[$g] + $h.Valor }
  }
  foreach ($g in $suma.Keys) { $u."Tokens$g" = [long]$suma[$g] }
  $u.Campos = $campos.ToArray()
  return $u
}
