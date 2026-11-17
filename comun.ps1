<#
comun.ps1 - Lo que comparten rescate.ps1 y migracion.ps1. No se ejecuta solo:
cada script lo carga con '. (Join-Path $PSScriptRoot 'comun.ps1')'. Solo ASCII.
Las funciones usan variables del script que las carga: $Cfg, $Si, $Worktree,
$OrigenRoot (la carpeta del usuario) y $RepoRoot (la carpeta donde se trabaja:
el worktree de rescate). Cada script las define antes de llamarlas.
Los flags de Copilot y la ruta de Maven se ajustan aqui o en .rescate/config.json.
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
}

# ============================== UTILIDADES ==============================
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

# Maven del repo: el de -MvnExe, el mvnw de la raiz o el mvn del PATH.
function Get-Mvn([string]$Raiz) {
  if ($Cfg.MvnExe) { return $Cfg.MvnExe }
  if ([System.IO.Path]::DirectorySeparatorChar -eq '\') { $w = Join-Path $Raiz 'mvnw.cmd' } else { $w = Join-Path $Raiz 'mvnw' }
  if (Test-Path -LiteralPath $w) { return $w }
  return 'mvn'
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

# Lee un .json de ajustes y pisa las claves de $Cfg. Las claves de $Aparte las
# trata quien llama (aqui no se avisa de ellas). Devuelve el objeto leido o $null.
function Read-CfgFile([string]$Ruta, [string[]]$Aparte = @()) {
  if (-not (Test-Path -LiteralPath $Ruta)) { return $null }
  try {
    $o = [System.IO.File]::ReadAllText($Ruta) | ConvertFrom-Json
    foreach ($pr in $o.PSObject.Properties) {
      if ($Cfg.ContainsKey($pr.Name)) { $Cfg[$pr.Name] = $pr.Value }
      elseif ($Aparte -notcontains $pr.Name) { Aviso ((Split-Path $Ruta -Leaf) + ": clave desconocida '$($pr.Name)'") }
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
      (-not $enIgnorada) -and ($p -notmatch '\.(class|log|iml)$') })
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
