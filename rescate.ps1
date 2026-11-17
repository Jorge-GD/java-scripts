<#
rescate.ps1 - Primeros auxilios para repos Java batch migrados a medias
(Java 8 -> Java 21 + arquitectura hexagonal + SFTP + configuracion externa).
Compatible con Windows PowerShell 5.1 y PowerShell 7. Solo ASCII a proposito.

COMO FUNCIONA
  1. DIAGNOSTICO (sin IA, no toca codigo). Compara el repo con una PLANTILLA
     (un repo ya migrado y aprobado) y lista hallazgos por paso, en este orden:
       build -> estructura -> hexagonal -> ficheros -> config -> paridad -> e2e -> tests
     La plantilla manda: lo que la plantilla hace se considera permitido.
     paridad = estan todos los jobs del batch original (necesita -Modo pre).
     e2e     = cada job tiene un test que lo lanza entero y acaba en COMPLETED.
  2. FIX (con Copilot CLI). Arregla UN paso en lotes pequenos. Tras cada lote
     es el script (no la IA) quien decide si vale:
       - compila
       - bajan los hallazgos del paso
       - no empeoran los pasos anteriores
       - no se han borrado ni desactivado tests
       - no se ha tocado la plantilla ni el repo original
     Si vale -> commit. Si no -> reintento con el error y, si sigue mal, se
     deshace el lote entero. Nunca hace push.

USO
  # 0) Pre, una vez por repo: lista de jobs del original -> .rescate/contrato.json
  #    (lo unico que hay que revisar a mano: que esa lista de jobs es la buena)
  .\rescate.ps1 -Modo pre -Repo C:\ruta\batch-life -Legacy C:\ruta\life-java8

  # 1) Diagnostico (seguro, no cambia codigo)
  .\rescate.ps1 -Repo C:\ruta\batch-life -Plantilla C:\ruta\batch-terminado

  # 2) Arreglar el siguiente paso pendiente, lote a lote, con pausa para revisar
  .\rescate.ps1 -Modo fix -Repo C:\ruta\batch-life -Plantilla C:\ruta\batch-terminado `
                -Legacy C:\ruta\life-java8 -Modelo <id-del-modelo>

  # Todo seguido, sin parar: se detiene solo si un lote no pasa las comprobaciones
  .\rescate.ps1 -Modo fix ... -Todo

  # Con modelo de reserva: si el principal se atasca con un fichero, prueba el otro
  .\rescate.ps1 -Modo fix ... -Todo -Modelo <principal> -ModeloB <reserva>

  # Si un lote falla: se deshace, se reintenta fichero a fichero, luego con el
  # modelo de reserva y, si tampoco, se apunta en .rescate/atascados.md y sigue.

  # Elegir paso, lotes mas pequenos, saltar ficheros que se atascan
  .\rescate.ps1 -Modo fix ... -Paso hexagonal -Lote 3 -Saltar 2

  # Deshacer el ultimo lote
  .\rescate.ps1 -Modo deshacer -Repo C:\ruta\batch-life

  Si PowerShell bloquea el script:
  powershell -ExecutionPolicy Bypass -File .\rescate.ps1 -Repo ...

SI HAY QUE REPARAR ESTE SCRIPT
  Lo normal es tocar solo el bloque CONFIGURACION (flags de Copilot, comandos
  de Maven, reglas). No quites las puertas de Invoke-Fix: son lo que evita que
  la IA estropee el repo.

LIMITES
  Proyectos Maven de un solo modulo. Las comprobaciones son por imports y
  texto: avisan de lo evidente, no sustituyen la revision de una persona.
#>
[CmdletBinding()]
param(
  [ValidateSet('diagnostico', 'pre', 'fix', 'deshacer')][string]$Modo = 'diagnostico',
  [string]$Repo = '.',
  [string]$Plantilla = '',
  [string]$Legacy = '',
  [ValidateSet('', 'build', 'estructura', 'hexagonal', 'ficheros', 'config', 'paridad', 'e2e', 'tests')][string]$Paso = '',
  [string]$Modelo = '',
  [string]$ModeloB = '',     # modelo de reserva: se prueba cuando el principal se atasca con un fichero
  [int]$Lote = 5,           # ficheros por llamada a Copilot (pequeno = mas fiable)
  [int]$Saltar = 0,         # salta los N primeros ficheros pendientes del paso
  [int]$MaxIntentos = 2,    # intentos por lote antes de deshacerlo
  [int]$MaxLotes = 200,
  [switch]$SinBuild,        # diagnostico rapido: no ejecuta Maven
  [switch]$SinTests,        # no ejecuta tests (solo compila)
  [switch]$Auto,            # no para entre lotes
  [switch]$Todo,            # fix: encadena todos los pasos sin parar (implica -Auto)
  [switch]$Si,              # responde "si" a las confirmaciones
  [switch]$SinInstrucciones,# Copilot no carga AGENTS.md / instrucciones del repo
  [switch]$SinIA            # modo pre: solo busqueda por texto, sin Copilot
)
$ErrorActionPreference = 'Stop'

# ============================ CONFIGURACION ============================
$Cfg = @{
  Orden  = @('build', 'estructura', 'hexagonal', 'ficheros', 'config', 'paridad', 'e2e', 'tests')
  Capas  = @('domain', 'application', 'infrastructure')   # si no hay plantilla
  # Reglas de dependencias. En = carpeta (relativa al paquete base).
  # No = regex sobre el import; {base} es el paquete base del proyecto.
  Reglas = @(
    @{ En = 'domain/'; No = '^\{base\}\.(application|infrastructure)\.'
       Por = 'el dominio no depende de application ni de infrastructure' },
    @{ En = 'domain/'; No = '^(org\.springframework|jakarta\.persistence|javax\.persistence|java\.sql|javax\.sql|java\.net\.http|org\.apache\.sshd|com\.jcraft|org\.apache\.http|okhttp3|com\.fasterxml)\.'
       Por = 'el dominio no depende de frameworks ni de entrada/salida' },
    @{ En = 'application/'; No = '^\{base\}\.infrastructure\.'
       Por = 'application no depende de infrastructure' },
    @{ En = 'application/'; No = '^(org\.springframework\.(batch|integration|jdbc|web|http)|java\.sql|javax\.sql|java\.net\.http|org\.apache\.sshd|com\.jcraft|org\.apache\.http|okhttp3)\.'
       Por = 'application no usa tecnologia concreta: va detras de un puerto' },
    @{ En = 'infrastructure/adapters/input/'; No = '^\{base\}\.infrastructure\.adapters\.output\.'
       Por = 'un adaptador de entrada no llama a uno de salida: pasa por un caso de uso' }
  )
  SubpaquetesEstrictos  = $true   # domain/x, application/x... deben existir en la plantilla
  # Acceso a ficheros locales (lo que debe ir por el puerto de ficheros / SFTP)
  FicheroImport         = '^(java\.io\.(File|FileReader|FileWriter|FileInputStream|FileOutputStream|RandomAccessFile)|java\.nio\.file\..+|org\.springframework\.core\.io\.(FileSystemResource|PathResource|FileUrlResource))$'
  FicheroToken          = '\b(File|FileReader|FileWriter|FileInputStream|FileOutputStream|RandomAccessFile)\b'
  FicheroPermitidoEn    = @('infrastructure/adapters/output/file')
  # Palabras que delatan la configuracion antigua. AJUSTALAS a tu repo.
  PalabrasConfigAntigua = @('inventory')
  # API antigua: se marca solo si la plantilla ya no la usa
  ApiAntigua            = @('JobBuilderFactory', 'StepBuilderFactory')
  JavaxAntiguo          = '^javax\.(annotation|persistence|validation|servlet|inject|batch|transaction|ws\.rs|jms|mail|xml\.bind)\.'
  ExtTexto              = @('.java', '.yml', '.yaml', '.properties', '.xml', '.sh', '.bat', '.cmd', '.json', '.conf', '.cfg', '.ini')
  DirsIgnorados         = @('.git', 'target', '.rescate', 'node_modules', '.idea', '.vscode', '.github', '.mvn')
  # Como se reconoce un job en el ORIGINAL (grupo 1 = nombre del job)
  JobRegex              = @(
    '(?i)jobBuilder\w*\s*\.\s*get\(\s*"([^"]+)"',
    'new\s+JobBuilder\(\s*"([^"]+)"',
    '<(?:\w+:)?job(?=[\s>])[^>]*\bid="([^"]+)"'
  )
  # Como se reconoce un test que lanza un job de verdad
  LanzaJob              = 'launchJob\s*\(|JobLauncherTestUtils|[jJ]obLauncher\s*\.\s*run\s*\(|[jJ]obOperator\s*\.\s*start\s*\(|SpringApplication\s*\.\s*run\s*\('
  PasosDeUnoEnUno       = @('paridad', 'e2e')   # un job por llamada a Copilot
  MaxFallosSeguidos     = 6     # lotes deshechos seguidos antes de parar (no gastar llamadas en balde)
  # Maven
  MvnCompilar           = @('-q', '-B', '-DskipTests', 'test-compile')
  MvnTests              = @('-q', '-B', 'test')
  # Copilot CLI. Si tu version no conoce algun flag, quitalo de aqui.
  CopilotExe            = 'copilot'
  CopilotArgs           = @('-s', '--allow-all-tools', '--no-ask-user', '--deny-tool=shell(git push)')
  CommitArgs            = @()     # p.ej. @('--no-verify') si un hook local bloquea
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

# Ficheros de un arbol, sin entrar en carpetas ignoradas.
function Get-Arbol([string]$Dir, [int]$Prof = 99) {
  $out = New-Object System.Collections.Generic.List[object]
  $pila = New-Object System.Collections.Stack
  $pila.Push(@($Dir, 0))
  while ($pila.Count -gt 0) {
    $it = $pila.Pop()
    foreach ($e in @(Get-ChildItem -LiteralPath $it[0] -Force)) {
      if ($e.PSIsContainer) {
        if (($Cfg.DirsIgnorados -notcontains $e.Name) -and ($it[1] -lt $Prof)) { $pila.Push(@($e.FullName, ($it[1] + 1))) }
      }
      else { $out.Add($e) }
    }
  }
  return $out.ToArray()
}

function Get-JavaFiles([string]$Dir) {
  if (-not (Test-Path -LiteralPath $Dir)) { return @() }
  return @(Get-ChildItem -LiteralPath $Dir -Recurse -File -Filter '*.java')
}

function Get-Imports([string]$Ruta) {
  $res = New-Object System.Collections.Generic.List[object]
  $n = 0
  foreach ($l in [System.IO.File]::ReadAllLines($Ruta)) {
    $n++
    if ($l -match '^\s*import\s+(static\s+)?([\w\.]+(\.\*)?)\s*;') { $res.Add([pscustomobject]@{ Linea = $n; Fqn = $Matches[2] }) }
    elseif ($l -match '^\s*(public\s+|final\s+|abstract\s+)*(class|interface|enum|record)\s') { break }
  }
  return $res.ToArray()
}

# Paquete base = carpeta de la clase con @SpringBootApplication.
function Get-BaseDir([string]$Raiz) {
  $main = Join-Ruta $Raiz 'src/main/java'
  if (-not (Test-Path -LiteralPath $main)) { return $null }
  foreach ($f in (Get-JavaFiles $main)) {
    if ([System.IO.File]::ReadAllText($f.FullName) -match '@SpringBootApplication') { return $f.DirectoryName }
  }
  $d = $main
  while ($true) {
    $subs = @(Get-ChildItem -LiteralPath $d -Directory)
    $javas = @(Get-ChildItem -LiteralPath $d -File -Filter '*.java')
    if ($subs.Count -eq 1 -and $javas.Count -eq 0) { $d = $subs[0].FullName } else { break }
  }
  return $d
}

# Datos en crudo de un repo (sirve para el repo y para la plantilla).
function Get-Hechos([string]$Raiz) {
  $baseDir = Get-BaseDir $Raiz
  $lista = New-Object System.Collections.Generic.List[object]
  $basePkg = ''
  if ($baseDir) {
    $basePkg = (Get-Rel (Join-Ruta $Raiz 'src/main/java') $baseDir) -replace '/', '.'
    foreach ($f in (Get-JavaFiles $baseDir)) {
      $lista.Add([pscustomobject]@{
          Rel     = Get-Rel $baseDir $f.FullName
          RelRaiz = Get-Rel $Raiz $f.FullName
          Texto   = [System.IO.File]::ReadAllText($f.FullName)
          Imports = @(Get-Imports $f.FullName)
        })
    }
  }
  $tests = New-Object System.Collections.Generic.List[object]
  foreach ($f in (Get-JavaFiles (Join-Ruta $Raiz 'src/test/java'))) {
    $tests.Add([pscustomobject]@{ RelRaiz = Get-Rel $Raiz $f.FullName; Texto = [System.IO.File]::ReadAllText($f.FullName); Imports = @(Get-Imports $f.FullName) })
  }
  $yml = ''
  $res = Join-Ruta $Raiz 'src/main/resources'
  if (Test-Path -LiteralPath $res) {
    foreach ($f in @(Get-ChildItem -LiteralPath $res -File | Where-Object { $_.Name -match '^application.*\.(ya?ml|properties)$' })) { $yml += [System.IO.File]::ReadAllText($f.FullName) + "`n" }
  }
  return [pscustomobject]@{ Raiz = $Raiz; BaseDir = $baseDir; BasePkg = $basePkg; Ficheros = $lista.ToArray(); Tests = $tests.ToArray(); Yml = $yml }
}

function Get-Norm([string]$Fqn, [string]$BasePkg) {
  if ($BasePkg -and $Fqn.StartsWith($BasePkg + '.')) { return '{base}' + $Fqn.Substring($BasePkg.Length) }
  return $Fqn
}
function Get-Paquete([string]$Fqn) {
  $i = $Fqn.LastIndexOf('.')
  if ($i -lt 0) { return $Fqn }
  return $Fqn.Substring(0, $i)
}
function Get-Carpeta([string]$Rel) {
  $i = $Rel.LastIndexOf('/')
  if ($i -lt 0) { return '' }
  return $Rel.Substring(0, $i)
}

# Imports que rompen las reglas de capas.
function Get-ViolImports($Hechos) {
  $out = New-Object System.Collections.Generic.List[object]
  foreach ($f in $Hechos.Ficheros) {
    foreach ($r in $Cfg.Reglas) {
      if (-not $f.Rel.StartsWith($r.En)) { continue }
      foreach ($imp in $f.Imports) {
        $norm = Get-Norm $imp.Fqn $Hechos.BasePkg
        if ($norm -match $r.No) {
          $out.Add([pscustomobject]@{ RelRaiz = $f.RelRaiz; Linea = $imp.Linea; Fqn = $imp.Fqn; Clave = ($r.En + '|' + (Get-Paquete $norm)); Por = $r.Por })
        }
      }
    }
  }
  return $out.ToArray()
}

# Uso de ficheros locales.
function Get-UsoFicheros($Hechos) {
  $out = New-Object System.Collections.Generic.List[object]
  foreach ($f in $Hechos.Ficheros) {
    $dir = Get-Carpeta $f.Rel
    foreach ($imp in $f.Imports) {
      $fqn = ''
      if ($imp.Fqn -match $Cfg.FicheroImport) { $fqn = $imp.Fqn }
      elseif ($imp.Fqn -eq 'java.io.*' -and $f.Texto -match $Cfg.FicheroToken) { $fqn = 'java.io.File' }
      if ($fqn) { $out.Add([pscustomobject]@{ RelRaiz = $f.RelRaiz; Dir = $dir; Linea = $imp.Linea; Fqn = $fqn; Clave = ($dir + '|' + (Get-Paquete $fqn)) }) }
    }
  }
  return $out.ToArray()
}

# Texto de todos los ficheros de texto de una carpeta (para buscar literales).
function Get-TextoArbol([string]$Dir) {
  if (-not $Dir -or -not (Test-Path -LiteralPath $Dir)) { return '' }
  $sb = New-Object System.Text.StringBuilder
  foreach ($f in @(Get-Arbol $Dir)) {
    if ($Cfg.ExtTexto -notcontains $f.Extension.ToLower()) { continue }
    if ($f.Length -gt 1MB) { continue }
    [void]$sb.AppendLine([System.IO.File]::ReadAllText($f.FullName))
  }
  return $sb.ToString()
}

# Jobs del original detectados por texto: nombre -> fichero.
function Get-JobsPorRegex([string]$Raiz) {
  $res = @{}
  foreach ($f in @(Get-Arbol $Raiz)) {
    $ext = $f.Extension.ToLower()
    if (($ext -ne '.java' -and $ext -ne '.xml') -or $f.Length -gt 1MB) { continue }
    $t = [System.IO.File]::ReadAllText($f.FullName)
    foreach ($rx in $Cfg.JobRegex) {
      foreach ($m in [regex]::Matches($t, $rx)) {
        $n = $m.Groups[1].Value
        if (-not $res.ContainsKey($n)) { $res[$n] = Get-Rel $Raiz $f.FullName }
      }
    }
  }
  return $res
}

function Read-Contrato {
  $p = Join-Path $Work 'contrato.json'
  if (-not (Test-Path -LiteralPath $p)) { return $null }
  try { return ([System.IO.File]::ReadAllText($p) | ConvertFrom-Json) } catch { Aviso 'contrato.json no es JSON valido: lo ignoro.'; return $null }
}

function Get-XmlTextos($Doc, [string]$Ruta) {
  $xp = ''
  foreach ($s in $Ruta.Split('/')) { $xp += "/*[local-name()='$s']" }
  $res = @()
  foreach ($n in $Doc.SelectNodes($xp)) { $res += $n.InnerText.Trim() }
  return $res
}

function Get-Pom([string]$Raiz) {
  $p = Join-Path $Raiz 'pom.xml'
  if (-not (Test-Path -LiteralPath $p)) { return $null }
  $x = New-Object System.Xml.XmlDocument
  try { $x.Load($p) } catch { return [pscustomobject]@{ Valido = $false; Parent = ''; Java = @(); Deps = @() } }
  $par = (@(Get-XmlTextos $x 'project/parent/groupId') + @(Get-XmlTextos $x 'project/parent/artifactId') + @(Get-XmlTextos $x 'project/parent/version')) -join ':'
  $java = @()
  foreach ($k in @('java.version', 'maven.compiler.release', 'maven.compiler.source', 'maven.compiler.target')) { $java += @(Get-XmlTextos $x "project/properties/$k") }
  $deps = @(Get-XmlTextos $x 'project/dependencies/dependency/artifactId')
  return [pscustomobject]@{ Valido = $true; Parent = $par; Java = @($java | Select-Object -Unique); Deps = $deps }
}

# Lo que se aprende de la plantilla.
function Get-Calibracion([string]$Raiz) {
  $h = Get-Hechos $Raiz
  $capas = @(); $sub2 = @{}; $dirs3 = @{}
  $excImp = @{}; $excFic = @{}; $tokens = @{}
  foreach ($f in $h.Ficheros) {
    $seg = $f.Rel.Split('/')
    if ($seg.Count -ge 2 -and ($capas -notcontains $seg[0])) { $capas += $seg[0] }
    if ($seg.Count -ge 3) {
      if (-not $sub2.ContainsKey($seg[0])) { $sub2[$seg[0]] = @() }
      if ($sub2[$seg[0]] -notcontains $seg[1]) { $sub2[$seg[0]] += $seg[1] }
    }
    $n = [Math]::Min($seg.Count - 1, 3)
    if ($n -ge 1) { $dirs3[($seg[0..($n - 1)] -join '/')] = $true }
  }
  foreach ($v in @(Get-ViolImports $h)) { $excImp[$v.Clave] = $true }
  foreach ($u in @(Get-UsoFicheros $h)) { $excFic[$u.Clave] = $true }
  $todo = (@($h.Ficheros | ForEach-Object { $_.Texto }) -join "`n")
  foreach ($t in $Cfg.ApiAntigua) { $tokens[$t] = ($todo -match ('\b' + $t + '\b')) }
  $jakarta = $false
  foreach ($f in (@($h.Ficheros) + @($h.Tests))) { foreach ($i in $f.Imports) { if ($i.Fqn.StartsWith('jakarta.')) { $jakarta = $true } } }
  $extra = @()
  foreach ($f in @(Get-Arbol $Raiz 2)) {
    $rel = Get-Rel $Raiz $f.FullName
    if (-not $rel.StartsWith('src/')) { $extra += $rel }
  }
  return [pscustomobject]@{
    Capas = $capas; Sub2 = $sub2; Dirs3 = @($dirs3.Keys | Sort-Object)
    ExcImports = $excImp; ExcFicheros = $excFic; Tokens = $tokens; UsaJakarta = $jakarta
    UsaConfigProps = ($todo -match '@ConfigurationProperties'); UsaValue = ($todo -match '@Value\s*\(')
    TieneSftp = (@($h.Ficheros | Where-Object { $_.Rel -match '(^|/)sftp/' }).Count -gt 0)
    YmlSftp = ($h.Yml -match 'sftp'); Pom = (Get-Pom $Raiz); Extra = $extra
  }
}

# ============================== DIAGNOSTICO ==============================
function Add-Hallazgo([string]$Cat, [string]$Sev, [string]$Fichero, [int]$Linea, [string]$Detalle) {
  [void]$script:H.Add([pscustomobject]@{ Cat = $Cat; Sev = $Sev; Fichero = $Fichero; Linea = $Linea; Detalle = $Detalle })
}

function Get-Mvn {
  if ([System.IO.Path]::DirectorySeparatorChar -eq '\') { $w = Join-Path $RepoRoot 'mvnw.cmd' } else { $w = Join-Path $RepoRoot 'mvnw' }
  if (Test-Path -LiteralPath $w) { return $w }
  return 'mvn'
}

function Invoke-Build([bool]$ConTests) {
  $b = [pscustomobject]@{ Ejecutado = $true; Compila = $true; TestsEjecutados = $false; TestsOk = $false }
  $rep = Join-Ruta $RepoRoot 'target/surefire-reports'
  if ($ConTests -and (Test-Path -LiteralPath $rep)) { Remove-Item -LiteralPath $rep -Recurse -Force }
  if ($ConTests) { $a = $Cfg.MvnTests } else { $a = $Cfg.MvnCompilar }
  $r = Invoke-Nativo (Get-Mvn) $a $RepoRoot
  [System.IO.File]::WriteAllLines((Join-Path $Work 'build.log'), [string[]]$r.Salida)
  if ($r.Codigo -eq 0) {
    if ($ConTests) { $b.TestsEjecutados = $true; $b.TestsOk = $true }
    return $b
  }
  # 1) errores de compilacion
  $raiz = ($RepoRoot -replace '\\', '/')
  $porFichero = @{}
  foreach ($l in $r.Salida) {
    if ($l -match '\[ERROR\]\s+(.*?\.java):\[(\d+),\d+\]\s*(.*)$') {
      $ln = [int]$Matches[2]; $msg = $Matches[3]
      $p = (($Matches[1] -replace '\\', '/') -replace '^/([A-Za-z]:/)', '$1')
      if ($p.ToLower().StartsWith($raiz.ToLower() + '/')) { $p = $p.Substring($raiz.Length + 1) }
      if (-not $porFichero.ContainsKey($p)) { $porFichero[$p] = 0 }
      $porFichero[$p]++
      if ($porFichero[$p] -le 3) { Add-Hallazgo 'build' 'error' $p $ln ('no compila: ' + $msg) }
    }
  }
  $texto = ($r.Salida -join "`n")
  if ($porFichero.Count -gt 0 -or $texto -match 'COMPILATION ERROR') {
    $b.Compila = $false
    if ($porFichero.Count -eq 0) { Add-Hallazgo 'build' 'error' 'pom.xml' 0 'no compila (ver .rescate/build.log)' }
    return $b
  }
  # 2) tests que fallan
  $fallan = 0
  if ($ConTests -and (Test-Path -LiteralPath $rep)) {
    foreach ($f in @(Get-ChildItem -LiteralPath $rep -File -Filter '*.txt')) {
      $t = [System.IO.File]::ReadAllText($f.FullName)
      if ($t -match 'Tests run:\s*(\d+),\s*Failures:\s*(\d+),\s*Errors:\s*(\d+)') {
        $nf = [int]$Matches[2] + [int]$Matches[3]
        if ($nf -gt 0) {
          $clase = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
          $rel = 'src/test/java/' + ($clase -replace '\.', '/') + '.java'
          if (-not (Test-Path -LiteralPath (Join-Ruta $RepoRoot $rel))) { $rel = $clase }
          Add-Hallazgo 'tests' 'error' $rel 0 "$nf test(s) fallan en $clase (ver target/surefire-reports)"
          $fallan++
        }
      }
    }
  }
  if ($fallan -gt 0) { $b.TestsEjecutados = $true; $b.TestsOk = $false; return $b }
  # 3) otra cosa (parent que no resuelve, plugin, etc.)
  $primera = @($r.Salida | Where-Object { $_ -match '\[ERROR\]' } | Select-Object -First 1) -join ''
  $b.Compila = $false
  Add-Hallazgo 'build' 'error' 'pom.xml' 0 ('el build falla y no es compilacion ni tests: ' + $primera)
  return $b
}

function Invoke-Diagnostico([bool]$ConBuild, [bool]$ConTests) {
  $script:H = New-Object System.Collections.Generic.List[object]
  $script:Build = [pscustomobject]@{ Ejecutado = $false; Compila = $true; TestsEjecutados = $false; TestsOk = $false }
  $cal = $script:Cal
  $h = Get-Hechos $RepoRoot
  $script:BasePkg = $h.BasePkg

  # ---------- build ----------
  $pom = Get-Pom $RepoRoot
  if ($null -eq $pom) { Add-Hallazgo 'build' 'error' 'pom.xml' 0 'no hay pom.xml en la raiz' }
  elseif (-not $pom.Valido) { Add-Hallazgo 'build' 'error' 'pom.xml' 0 'pom.xml no es XML valido' }
  else {
    if ($cal -and $cal.Pom -and $cal.Pom.Parent -and ($pom.Parent -ne $cal.Pom.Parent)) {
      Add-Hallazgo 'build' 'error' 'pom.xml' 0 "parent distinto al de la plantilla (aqui: '$($pom.Parent)'; plantilla: '$($cal.Pom.Parent)')"
    }
    foreach ($v in $pom.Java) {
      $num = 0
      if ([int]::TryParse(($v -replace '^1\.', ''), [ref]$num) -and $num -lt 21) { Add-Hallazgo 'build' 'error' 'pom.xml' 0 "version de Java '$v' en el pom (objetivo: 21)" }
    }
    if ($cal -and $cal.Pom -and $cal.Pom.Valido) {
      $sobran = @($pom.Deps | Where-Object { $cal.Pom.Deps -notcontains $_ } | Select-Object -Unique)
      $faltan = @($cal.Pom.Deps | Where-Object { $pom.Deps -notcontains $_ } | Select-Object -Unique)
      if ($sobran.Count -gt 0) { Add-Hallazgo 'build' 'aviso' 'pom.xml' 0 ('dependencias que la plantilla no usa: ' + (($sobran | Select-Object -First 12) -join ', ')) }
      if ($faltan.Count -gt 0) { Add-Hallazgo 'build' 'aviso' 'pom.xml' 0 ('dependencias de la plantilla que aqui no estan: ' + (($faltan | Select-Object -First 12) -join ', ')) }
    }
  }
  if ($cal -and $cal.UsaJakarta) {
    foreach ($f in (@($h.Ficheros) + @($h.Tests))) {
      $jx = @($f.Imports | Where-Object { $_.Fqn -match $Cfg.JavaxAntiguo })
      if ($jx.Count -gt 0) { Add-Hallazgo 'build' 'error' $f.RelRaiz $jx[0].Linea ('imports javax que la plantilla ya tiene en jakarta: ' + ((@($jx | ForEach-Object { $_.Fqn }) | Select-Object -First 4) -join ', ')) }
    }
  }
  if ($cal) {
    foreach ($t in $Cfg.ApiAntigua) {
      if ($cal.Tokens[$t]) { continue }
      foreach ($f in $h.Ficheros) { if ($f.Texto -match ('\b' + $t + '\b')) { Add-Hallazgo 'build' 'error' $f.RelRaiz 0 "usa $t, que la plantilla ya no usa" } }
    }
  }
  if ($ConBuild -and $pom -and $pom.Valido) { $script:Build = Invoke-Build $ConTests }

  # ---------- estructura ----------
  if (-not $h.BaseDir) { Add-Hallazgo 'estructura' 'error' 'src/main/java' 0 'no encuentro src/main/java ni el paquete base' }
  if ($cal -and $cal.Capas.Count -gt 0) { $capas = @($Cfg.Capas | Where-Object { $cal.Capas -contains $_ }) + @($cal.Capas | Where-Object { $Cfg.Capas -notcontains $_ }) } else { $capas = $Cfg.Capas }
  foreach ($f in $h.Ficheros) {
    $seg = $f.Rel.Split('/')
    if ($seg.Count -eq 1) {
      if ($f.Texto -notmatch '@SpringBootApplication') { Add-Hallazgo 'estructura' 'error' $f.RelRaiz 0 ('clase suelta en el paquete base: debe ir a una capa (' + ($capas -join ', ') + ')') }
      continue
    }
    if ($capas -notcontains $seg[0]) {
      Add-Hallazgo 'estructura' 'error' $f.RelRaiz 0 ("paquete '" + $seg[0] + "' fuera de las capas (" + ($capas -join ', ') + ')')
      continue
    }
    if ($cal -and $Cfg.SubpaquetesEstrictos -and $seg.Count -ge 3 -and $cal.Sub2.ContainsKey($seg[0]) -and ($cal.Sub2[$seg[0]] -notcontains $seg[1])) {
      Add-Hallazgo 'estructura' 'error' $f.RelRaiz 0 ("subpaquete '" + $seg[0] + '/' + $seg[1] + "' no existe en la plantilla (alli: " + ($cal.Sub2[$seg[0]] -join ', ') + ')')
    }
  }
  if ($cal -and $h.BaseDir) {
    $faltanDirs = @($cal.Dirs3 | Where-Object { -not (Test-Path -LiteralPath (Join-Ruta $h.BaseDir $_)) })
    if ($faltanDirs.Count -gt 0) { Add-Hallazgo 'estructura' 'aviso' '' 0 ('paquetes de la plantilla que aqui no existen: ' + ($faltanDirs -join ', ')) }
  }

  # ---------- hexagonal ----------
  $viol = @(Get-ViolImports $h)
  if ($cal) { $viol = @($viol | Where-Object { -not $cal.ExcImports.ContainsKey($_.Clave) }) }
  foreach ($g in @($viol | Group-Object RelRaiz)) {
    $imps = (@($g.Group | ForEach-Object { $_.Fqn }) | Select-Object -Unique | Select-Object -First 5) -join ', '
    $por = (@($g.Group | ForEach-Object { $_.Por }) | Select-Object -Unique) -join '; '
    Add-Hallazgo 'hexagonal' 'error' $g.Name $g.Group[0].Linea "importa $imps ($por)"
  }
  foreach ($f in $h.Ficheros) {
    if ($f.Rel.StartsWith('application/ports/') -and $f.Texto -notmatch '\binterface\s') { Add-Hallazgo 'hexagonal' 'aviso' $f.RelRaiz 0 'esta en ports pero no es una interfaz' }
  }

  # ---------- ficheros (SFTP) ----------
  $uso = @(Get-UsoFicheros $h)
  $usaFicheros = ($uso.Count -gt 0)   # si el batch no toca ficheros, no se le exige SFTP
  $uso = @($uso | Where-Object {
      $d = $_.Dir; $ok = $false
      foreach ($p in $Cfg.FicheroPermitidoEn) { if ($d -eq $p -or $d.StartsWith($p + '/')) { $ok = $true } }
      if ($cal -and $cal.ExcFicheros.ContainsKey($_.Clave)) { $ok = $true }
      -not $ok })
  foreach ($g in @($uso | Group-Object RelRaiz)) {
    $imps = (@($g.Group | ForEach-Object { $_.Fqn }) | Select-Object -Unique | Select-Object -First 5) -join ', '
    Add-Hallazgo 'ficheros' 'error' $g.Name $g.Group[0].Linea "acceso directo a ficheros locales ($imps): debe ir por el puerto de ficheros"
  }
  if ($usaFicheros -and $cal -and $cal.TieneSftp -and (@($h.Ficheros | Where-Object { $_.Rel -match '(^|/)sftp/' }).Count -eq 0)) {
    Add-Hallazgo 'ficheros' 'error' '' 0 'no hay adaptador SFTP (la plantilla lo tiene en infrastructure/adapters/output/sftp)'
  }
  if ($usaFicheros -and $cal -and $cal.YmlSftp -and ($h.Yml -notmatch 'sftp')) {
    Add-Hallazgo 'ficheros' 'error' 'src/main/resources' 0 'application.yml no tiene configuracion sftp (la plantilla si)'
  }

  # ---------- config ----------
  $patron = '(?i)(' + (($Cfg.PalabrasConfigAntigua | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')'
  $restos = @{}
  foreach ($f in @(Get-Arbol $RepoRoot)) {
    $rel = Get-Rel $RepoRoot $f.FullName
    if ($rel -match '(?i)(^|/)inventor(y|ies)') { $restos[($rel.Split('/')[0])] = $true; continue }
    if ($Cfg.ExtTexto -notcontains $f.Extension.ToLower()) { continue }
    if ($f.Length -gt 1MB) { continue }
    $n = 0
    foreach ($l in [System.IO.File]::ReadAllLines($f.FullName)) {
      $n++
      if ($l -match $patron) {
        if ($rel.StartsWith('src/test/')) { $sev = 'aviso' } else { $sev = 'error' }
        Add-Hallazgo 'config' $sev $rel $n ("referencia a la configuracion antigua ('" + $Matches[1] + "')")
        break
      }
    }
  }
  if ($restos.Count -gt 0) { Add-Hallazgo 'config' 'aviso' '' 0 ('siguen en el repo ficheros/carpetas de inventory: ' + (($restos.Keys | Sort-Object) -join ', ') + ' (decide tu si se borran)') }
  $todo = (@($h.Ficheros | ForEach-Object { $_.Texto }) -join "`n")
  if ($cal -and $cal.UsaConfigProps -and ($todo -notmatch '@ConfigurationProperties')) {
    Add-Hallazgo 'config' 'error' '' 0 'no hay ninguna clase @ConfigurationProperties (la plantilla centraliza ahi la configuracion)'
  }
  if ($cal -and -not $cal.UsaValue) {
    foreach ($f in $h.Ficheros) { if ($f.Texto -match '@Value\s*\(') { Add-Hallazgo 'config' 'aviso' $f.RelRaiz 0 'usa @Value; la plantilla no lo usa' } }
  }
  if ($cal) {
    $faltanExtra = @($cal.Extra | Where-Object { -not (Test-Path -LiteralPath (Join-Ruta $RepoRoot $_)) } | Select-Object -First 15)
    if ($faltanExtra.Count -gt 0) { Add-Hallazgo 'config' 'aviso' '' 0 ('ficheros que la plantilla tiene y aqui faltan: ' + ($faltanExtra -join ', ')) }
  }

  # ---------- paridad y e2e (usan el contrato que genera -Modo pre) ----------
  $con = Read-Contrato
  if ($null -eq $con) {
    Add-Hallazgo 'paridad' 'aviso' '' 0 'sin contrato: lanza -Modo pre -Legacy <original> para comprobar que estan todos los jobs y que cada uno tiene prueba de extremo a extremo'
  }
  else {
    $textoMain = (@($h.Ficheros | ForEach-Object { $_.Texto }) -join "`n") + "`n" + (Get-TextoArbol (Join-Ruta $RepoRoot 'src/main/resources'))
    foreach ($j in @($con.jobs)) {
      $n = "$($j.nombre)".Trim()
      if (-not $n) { continue }
      $rx = '(?<![\w])' + [regex]::Escape($n) + '(?![\w])'
      $clave = 'job:' + $n
      if ($textoMain -notmatch $rx) {
        if ("$($j.origen)" -eq 'ia') { $sev = 'aviso' } else { $sev = 'error' }
        Add-Hallazgo 'paridad' $sev $clave 0 "el job '$n' del original no aparece en este repo (en el original: $($j.definidoEn))"
        continue
      }
      $clases = @($h.Ficheros | Where-Object { $_.Texto -match $rx } | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Rel.Split('/')[-1]) })
      $tiene = $false
      foreach ($t in $h.Tests) {
        if ($t.Texto -notmatch $Cfg.LanzaJob -or $t.Texto -notmatch 'COMPLETED') { continue }
        $menciona = ($t.Texto -match $rx)
        foreach ($c in $clases) { if ($t.Texto -match ('\b' + [regex]::Escape($c) + '\b')) { $menciona = $true } }
        if ($menciona) { $tiene = $true; break }
      }
      if (-not $tiene) { Add-Hallazgo 'e2e' 'error' $clave 0 "el job '$n' no tiene un test que lo lance entero y compruebe COMPLETED. Entrada: $($j.entrada) Salida: $($j.salida)" }
    }
  }

  # ---------- tests ----------
  if ($h.Tests.Count -eq 0) { Add-Hallazgo 'tests' 'aviso' 'src/test/java' 0 'no hay tests' }

  return $script:H.ToArray()
}

function Get-Cuenta($Hall, [string]$Cat, [string]$Sev = 'error') {
  return @($Hall | Where-Object { $_.Cat -eq $Cat -and $_.Sev -eq $Sev }).Count
}

# Primer paso con errores pendientes (sin contar lo que ya se dio por atascado).
function Get-SiguientePaso($Hall) {
  foreach ($c in $Cfg.Orden) {
    $f = @($Hall | Where-Object { $_.Cat -eq $c -and $_.Sev -eq 'error' } | ForEach-Object { $_.Fichero } | Select-Object -Unique)
    if ($script:Atascados.ContainsKey($c)) { $f = @($f | Where-Object { $script:Atascados[$c] -notcontains $_ }) }
    if ($f.Count -gt 0) { return $c }
  }
  return ''
}

function Get-TextoBuild {
  $b = $script:Build
  if (-not $b.Ejecutado) { return 'compila: no comprobado' }
  if (-not $b.Compila) { return 'compila: NO' }
  if (-not $b.TestsEjecutados) { return 'compila: SI | tests: no ejecutados' }
  if ($b.TestsOk) { return 'compila: SI | tests: OK' }
  return 'compila: SI | tests: FALLAN'
}

function Write-Informe($Hall) {
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine('# Diagnostico de rescate: ' + (Split-Path $RepoRoot -Leaf))
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('- Fecha: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm'))
  [void]$sb.AppendLine('- Paquete base: ' + $script:BasePkg)
  [void]$sb.AppendLine('- Plantilla: ' + $PlantillaRoot)
  [void]$sb.AppendLine('- Estado: ' + (Get-TextoBuild))
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('| Paso | Errores | Avisos |')
  [void]$sb.AppendLine('|---|---|---|')
  foreach ($c in $Cfg.Orden) { [void]$sb.AppendLine("| $c | $(Get-Cuenta $Hall $c) | $(Get-Cuenta $Hall $c 'aviso') |") }
  foreach ($c in $Cfg.Orden) {
    $it = @($Hall | Where-Object { $_.Cat -eq $c } | Sort-Object @{Expression = 'Sev'; Descending = $true }, Fichero)
    if ($it.Count -eq 0) { continue }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("## $c")
    foreach ($x in $it) {
      $donde = $x.Fichero
      if ($x.Linea -gt 0) { $donde += ':' + $x.Linea }
      if ($donde) { $donde = '`' + $donde + '` - ' }
      [void]$sb.AppendLine("- [$($x.Sev)] $donde$($x.Detalle)")
    }
  }
  if ($script:Cal) {
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Permitido porque la plantilla tambien lo hace')
    $ex = @(@($script:Cal.ExcImports.Keys) + @($script:Cal.ExcFicheros.Keys) | Sort-Object)
    if ($ex.Count -eq 0) { [void]$sb.AppendLine('- (nada: la plantilla cumple todas las reglas)') }
    foreach ($k in $ex) { [void]$sb.AppendLine('- ' + ($k -replace '\|', ' -> ')) }
  }
  [System.IO.File]::WriteAllText((Join-Path $Work 'diagnostico.md'), $sb.ToString())
  [System.IO.File]::WriteAllText((Join-Path $Work 'hallazgos.json'), (ConvertTo-Json -InputObject @($Hall) -Depth 4))
}

function Show-Resumen($Hall) {
  Info ''
  Info ('== ' + (Split-Path $RepoRoot -Leaf) + ' | ' + (Get-TextoBuild) + ' ==')
  Info ('{0,-12} {1,8} {2,8}' -f 'paso', 'errores', 'avisos')
  foreach ($c in $Cfg.Orden) {
    $e = Get-Cuenta $Hall $c
    $linea = ('{0,-12} {1,8} {2,8}' -f $c, $e, (Get-Cuenta $Hall $c 'aviso'))
    if ($e -gt 0) { Aviso $linea } else { Bien $linea }
  }
  Info ('Informe: ' + (Join-Path $Work 'diagnostico.md'))
}

# ================================= FIX =================================
$TextoPaso = @{
  build      = 'Haz que el proyecto compile con Java 21 usando el mismo parent, propiedades y plugins que el pom.xml de la PLANTILLA. No copies dependencias de negocio que este repo no necesite. Corrige los errores de compilacion listados. No reestructures paquetes en este paso.'
  estructura = 'Mueve las clases listadas a la capa y paquete que les corresponde, copiando exactamente la estructura de paquetes y la convencion de nombres de la PLANTILLA. Solo mover y actualizar package e imports: no cambies logica. Mueve tambien sus tests al paquete equivalente.'
  hexagonal  = 'Elimina las dependencias prohibidas listadas. El dominio no depende de nada externo. La aplicacion solo depende del dominio y de sus puertos (interfaces en application/ports). Si una clase de dominio o aplicacion necesita infraestructura, crea un puerto y lleva la implementacion a un adaptador en infrastructure/adapters/output/<tecnologia>, con los nombres al estilo de la PLANTILLA.'
  ficheros   = 'Sustituye el acceso directo a ficheros locales por puertos de ficheros, igual que la PLANTILLA: puerto para listar y leer, puerto para el ciclo de vida del fichero, un adaptador SFTP y otro local, y seleccion por propiedad de configuracion. Usa la misma libreria SFTP que la PLANTILLA. No dejes rutas fijas en el codigo.'
  config     = 'Elimina las referencias a la configuracion antigua (inventory). Toda la configuracion debe entrar por una clase @ConfigurationProperties validada al arranque y por application.yml leyendo variables de entorno, igual que la PLANTILLA. Los secretos se quedan como variables de entorno: no escribas ninguno.'
  paridad    = 'Migra desde el ORIGINAL el job listado, que falta en este repo. Conserva EXACTAMENTE su nombre de job (con ese nombre lo lanza el planificador). Sigue la estructura de la PLANTILLA: adaptador de entrada (job y step), caso de uso, puertos y adaptadores de salida. Reutiliza los puertos y adaptadores que ya existan en este repo. Misma logica que el original.'
  e2e        = 'Crea un test de integracion para el job listado, copiando el patron de los tests de integracion de la PLANTILLA. El test lanza el job real de principio a fin con los adaptadores locales (sftp desactivado), base de datos en memoria y los servicios externos simulados; comprueba que termina en COMPLETED y que la salida es la esperada. Usa los datos de src/test/resources/e2e/<nombre-del-job>/ si existen; si no, crea alli datos sinteticos minimos (nunca datos reales). La salida esperada se deduce de la logica del ORIGINAL, no de ejecutar el codigo nuevo. El test debe contener el nombre del job. Si el test falla porque el codigo migrado no hace lo mismo que el original, corrige el codigo, no el test.'
  tests      = 'Haz que los tests listados pasen. Si fallan por la reestructuracion (paquetes, puertos, mocks), adapta el test. Si destapan un fallo real de la migracion, corrige el codigo. No borres tests ni relajes aserciones.'
}

function New-Prompt([string]$PasoId, $LoteH, [string]$Correccion) {
  $mvn = Get-Mvn
  if ($mvn -ne 'mvn') { $mvn = '.' + [System.IO.Path]::DirectorySeparatorChar + (Split-Path $mvn -Leaf) }
  $l = New-Object System.Collections.Generic.List[string]
  $l.Add("# Tarea de rescate de migracion: paso '$PasoId'")
  $l.Add('')
  $l.Add('Trabaja SOLO en el repositorio actual. Es una migracion a medias de un batch Java 8 a Java 21 con arquitectura hexagonal.')
  $l.Add('')
  $l.Add('## Referencias (SOLO LECTURA: no las modifiques)')
  if ($PlantillaRoot) {
    $l.Add("- PLANTILLA: $PlantillaRoot")
    $l.Add('  Repo ya migrado y aprobado. Es la fuente de verdad para estructura de paquetes, nombres de puertos y adaptadores, configuracion y tests. Antes de cambiar nada, lee alli las clases equivalentes y copia su estilo.')
  }
  if ($LegacyRoot) {
    $l.Add("- ORIGINAL JAVA 8: $LegacyRoot")
    $l.Add('  Referencia de comportamiento: el resultado debe hacer exactamente lo mismo.')
  }
  $l.Add('')
  $l.Add('## Que hay que hacer')
  $l.Add($TextoPaso[$PasoId])
  $l.Add('')
  $l.Add('## Hallazgos de este lote (resuelve estos y nada mas)')
  foreach ($x in $LoteH) {
    $donde = $x.Fichero
    if ($x.Linea -gt 0) { $donde += ':' + $x.Linea }
    if (-not $donde) { $donde = '(repo)' }
    $l.Add("- $donde - $($x.Detalle)")
  }
  $l.Add('')
  $l.Add('## Reglas obligatorias')
  $l.Add('1. No cambies la logica de negocio: mismo comportamiento que el original.')
  $l.Add('2. No toques nada fuera de este repositorio. No hagas commit ni push ni cambies de rama: de git se encarga el script.')
  $l.Add('3. No borres tests, no los desactives (@Disabled, @Ignore), no relajes aserciones ni bajes umbrales de cobertura. Si mueves una clase, mueve su test.')
  $l.Add("4. No cambies el pom.xml salvo que el paso sea 'build' o sea imprescindible. Nunca anadas dependencias que la plantilla no use.")
  $l.Add('5. No escribas contrasenas, tokens ni hosts reales en ningun fichero.')
  $l.Add('6. No hagas mejoras ni refactors que este lote no pide.')
  $l.Add('7. Si un hallazgo no se puede resolver sin romper estas reglas, dejalo como esta y explicalo al final.')
  $l.Add('')
  $l.Add('## Al terminar')
  $l.Add("- Ejecuta: $mvn " + ($Cfg.MvnCompilar -join ' ') + '  y corrige hasta que compile.')
  $l.Add('- Responde solo con: ficheros cambiados (lista corta) y hallazgos sin resolver con el motivo.')
  if ($Correccion) {
    $l.Add('')
    $l.Add('## CORRECCION: tu intento anterior no paso las comprobaciones')
    $l.Add('Tus cambios siguen en el arbol de trabajo. Corrige esto sin deshacer lo que estaba bien:')
    $l.Add($Correccion)
  }
  return ($l -join "`n")
}

function Invoke-Copilot([string]$Log, [string]$Mod = '') {
  $a = @('-p', 'Lee el fichero .rescate/prompt.md y sigue sus instrucciones al pie de la letra.') + $Cfg.CopilotArgs
  if (-not $Mod) { $Mod = $Modelo }
  if ($Mod) { $a += "--model=$Mod" }
  if ($SinInstrucciones) { $a += '--no-custom-instructions' }
  foreach ($d in @($PlantillaRoot, $LegacyRoot)) { if ($d) { $a += "--add-dir=$d" } }
  $r = Invoke-Nativo $Cfg.CopilotExe $a $RepoRoot
  [System.IO.File]::WriteAllLines($Log, [string[]]$r.Salida)
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

function Get-Guardas {
  $tests = @(Get-JavaFiles (Join-Ruta $RepoRoot 'src/test/java'))
  $des = 0; $ase = 0
  foreach ($f in $tests) {
    $t = [System.IO.File]::ReadAllText($f.FullName)
    $des += [regex]::Matches($t, '@(Disabled|Ignore)\b').Count
    $ase += [regex]::Matches($t, '\b(assert\w*|verify)\s*\(').Count
  }
  return [pscustomobject]@{ Tests = $tests.Count; Desactivados = $des; Aserciones = $ase; Plantilla = (Get-Huella $PlantillaRoot); Legacy = (Get-Huella $LegacyRoot) }
}

function Undo-Lote([string]$Rama, [string]$Check) {
  [void](Invoke-Git $RepoRoot @('checkout', '-q', '-f', $Rama))
  [void](Invoke-Git $RepoRoot @('reset', '-q', '--hard', $Check))
  [void](Invoke-Git $RepoRoot @('clean', '-fdq'))
}

# ================================= PRE =================================
# Saca del ORIGINAL la lista de jobs (el "contrato") para poder comprobar
# despues, sin IA, que no falta ninguno y que todos tienen prueba e2e.
function Invoke-Pre {
  if (-not $LegacyRoot) { Fallo 'El modo pre necesita -Legacy (carpeta del batch original).'; exit 1 }
  Info 'Buscando jobs en el original por texto...'
  $det = Get-JobsPorRegex $LegacyRoot
  $ia = @()
  if (-not $SinIA) {
    if (-not (Get-Command $Cfg.CopilotExe -ErrorAction SilentlyContinue)) { Aviso 'No encuentro copilot: sigo solo con la busqueda por texto.' }
    else {
      $antes = (Invoke-Git $RepoRoot @('status', '--porcelain')).Salida -join "`n"
      $h0 = Get-Huella $LegacyRoot; $hp = Get-Huella $PlantillaRoot
      $tmp = Join-Path $Work 'contrato-ia.json'
      if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
      $l = @(
        '# Tarea: inventario de jobs del batch ORIGINAL (solo lectura)',
        '',
        "Lee el repositorio ORIGINAL en: $LegacyRoot",
        'No modifiques NINGUN fichero de codigo, ni alli ni aqui. Tu unica salida es crear el fichero .rescate/contrato-ia.json en el repositorio actual.',
        '',
        'Busca TODOS los jobs batch que define el original (Spring Batch por Java o por XML, clases con main, scripts que lanzan jobs). Para cada uno:',
        '- nombre: el nombre exacto con el que se lanza el job, literal, tal cual aparece en el codigo.',
        '- definidoEn: ruta relativa del fichero donde se define.',
        '- entrada: que lee (ficheros y formato, tablas, servicios), en una frase.',
        '- salida: que produce (ficheros, tablas, llamadas), en una frase.',
        '',
        'Formato exacto, JSON valido, sin comentarios ni texto alrededor:',
        '{ "jobs": [ { "nombre": "", "definidoEn": "", "entrada": "", "salida": "" } ] }',
        '',
        ('Pistas encontradas por busqueda de texto (comprueba que son jobs y anade los que falten): ' + ((@($det.Keys) | Sort-Object) -join ', ')),
        'No inventes: si dudas de que algo sea un job, no lo incluyas. No incluyas contrasenas, hosts ni datos reales.'
      )
      [System.IO.File]::WriteAllText((Join-Path $Work 'prompt.md'), ($l -join "`n"))
      Info 'Copilot leyendo el original...'
      [void](Invoke-Copilot (Join-Path $Work 'pre.log'))
      if ((Get-Huella $LegacyRoot) -ne $h0 -or (Get-Huella $PlantillaRoot) -ne $hp) { Fallo 'ALTO: se ha modificado el ORIGINAL o la PLANTILLA durante el pre. Restauralos antes de seguir.'; exit 4 }
      $despues = (Invoke-Git $RepoRoot @('status', '--porcelain')).Salida -join "`n"
      if ($despues -ne $antes) { Aviso 'Ojo: Copilot ha tocado ficheros de este repo durante el pre (solo debia escribir en .rescate). Mira git status.' }
      if (Test-Path -LiteralPath $tmp) {
        try { $ia = @(([System.IO.File]::ReadAllText($tmp) | ConvertFrom-Json).jobs) } catch { Aviso 'contrato-ia.json no es JSON valido: sigo solo con la busqueda por texto.' }
      }
      else { Aviso 'Copilot no ha escrito .rescate/contrato-ia.json: sigo solo con la busqueda por texto.' }
    }
  }
  # Fusion. Lo que dice la IA solo vale si ese nombre aparece literal en el original.
  $texto = Get-TextoArbol $LegacyRoot
  $jobs = New-Object System.Collections.Generic.List[object]
  $vistos = @{}
  foreach ($j in $ia) {
    if ($null -eq $j) { continue }
    $n = "$($j.nombre)".Trim()
    if (-not $n -or $vistos.ContainsKey($n)) { continue }
    $vistos[$n] = $true
    if ($texto -notmatch ('(?<![\w])' + [regex]::Escape($n) + '(?![\w])')) { Aviso "  descartado '$n': la IA lo propone pero ese nombre no aparece en el original"; continue }
    if ($det.ContainsKey($n)) { $origen = 'texto+ia' } else { $origen = 'ia' }
    $jobs.Add([pscustomobject]@{ nombre = $n; origen = $origen; definidoEn = "$($j.definidoEn)"; entrada = "$($j.entrada)"; salida = "$($j.salida)" })
  }
  foreach ($n in @($det.Keys | Sort-Object)) {
    if ($vistos.ContainsKey($n)) { continue }
    $jobs.Add([pscustomobject]@{ nombre = $n; origen = 'texto'; definidoEn = $det[$n]; entrada = ''; salida = '' })
  }
  $contrato = [pscustomobject]@{ generado = (Get-Date -Format 'yyyy-MM-dd HH:mm'); original = $LegacyRoot; jobs = $jobs.ToArray() }
  [System.IO.File]::WriteAllText((Join-Path $Work 'contrato.json'), (ConvertTo-Json -InputObject $contrato -Depth 5))
  $cfgRepo = Join-Path $Work 'config.json'
  if (-not (Test-Path -LiteralPath $cfgRepo)) { [System.IO.File]::WriteAllText($cfgRepo, (ConvertTo-Json -InputObject ([pscustomobject]@{ PalabrasConfigAntigua = $Cfg.PalabrasConfigAntigua }))) }
  Info ''
  Info "Jobs del original: $($jobs.Count)"
  foreach ($j in $jobs) {
    $linea = ('  {0,-34} [{1}] {2}' -f $j.nombre, $j.origen, $j.definidoEn)
    if ($j.origen -eq 'ia') { Aviso ($linea + '   <- solo lo dice la IA: si es un job de verdad, cambia origen a "confirmado"') } else { Info $linea }
  }
  Info ''
  Info 'UNICA revision manual: comprueba que esa lista es la de jobs reales del batch antiguo.'
  Info ('Si sobra o falta alguno, edita ' + (Join-Path $Work 'contrato.json'))
  Info ('Ajustes propios de este repo (palabras de la config antigua, comandos Maven...): ' + $cfgRepo)
}

function Invoke-Fix {
  foreach ($exe in @('git', $Cfg.CopilotExe)) {
    if (-not (Get-Command $exe -ErrorAction SilentlyContinue)) { Fallo "No encuentro '$exe' en el PATH."; exit 1 }
  }
  if (-not $PlantillaRoot) { Aviso 'Sin -Plantilla el arreglo va a ciegas. Muy recomendable pasarla.' }

  # --- rama de rescate y foto del estado actual: nada se pierde ---
  $rama = ((Invoke-Git $RepoRoot @('rev-parse', '--abbrev-ref', 'HEAD')).Salida -join '').Trim()
  if ($rama -eq 'HEAD' -or -not $rama) { Fallo 'El repo no esta en una rama (detached HEAD).'; exit 1 }
  if (-not $rama.StartsWith('rescate/')) {
    $nueva = 'rescate/' + ($rama -replace '[^\w\.\-]', '-') + '-' + (Get-Date -Format 'yyyyMMdd-HHmm')
    if (-not (Confirmar "Creo la rama '$nueva' desde '$rama' ('$rama' no se toca). Seguir?")) { exit 0 }
    $r = Invoke-Git $RepoRoot @('checkout', '-q', '-b', $nueva)
    if ($r.Codigo -ne 0) { Fallo ('No pude crear la rama: ' + ($r.Salida -join ' ')); exit 1 }
    $rama = $nueva
  }
  $sucio = @((Invoke-Git $RepoRoot @('status', '--porcelain')).Salida | Where-Object { $_ })
  if ($sucio.Count -gt 0) {
    Aviso "Hay $($sucio.Count) cambios sin commit:"
    $sucio | Select-Object -First 15 | ForEach-Object { Info "  $_" }
    if (-not (Confirmar "Los guardo en un commit 'foto' en la rama '$rama' para poder volver atras. Seguir?")) { exit 0 }
    [void](Invoke-Git $RepoRoot @('add', '-A'))
    $r = Invoke-Git $RepoRoot (@('commit', '-q', '-m', 'rescate: foto del estado antes de empezar') + $Cfg.CommitArgs)
    if ($r.Codigo -ne 0) { Fallo ('git commit ha fallado: ' + ($r.Salida -join ' ')); exit 3 }
  }

  # --- diagnostico inicial ---
  Info 'Diagnostico inicial (compilando)...'
  $hall = @(Invoke-Diagnostico $true (-not $SinTests))
  Write-Informe $hall
  Show-Resumen $hall

  $paso = $Paso
  if (-not $paso) { $paso = Get-SiguientePaso $hall }
  if (-not $paso) { $script:Siguiente = ''; Bien 'No quedan errores. Revisa los avisos del informe y pasa tu pipeline.'; return }
  if ($paso -ne 'build' -and -not $script:Build.Compila) { Fallo "El proyecto no compila: primero hay que hacer -Paso build."; exit 2 }
  foreach ($c in $Cfg.Orden) {
    if ($c -eq $paso) { break }
    $q = Get-Cuenta $hall $c
    if ($q -gt 0) { Aviso "Ojo: quedan $q errores en el paso anterior '$c'." }
  }
  # En cada lote se ejecutan los tests (salvo -SinTests); en 'tests' y 'e2e', siempre.
  $conTests = ((-not $SinTests) -or ($paso -eq 'tests') -or ($paso -eq 'e2e'))
  if ($conTests -and $script:Build.Compila -and -not $script:Build.TestsEjecutados) { $hall = @(Invoke-Diagnostico $true $true) }
  $loteEf = $Lote
  if ($Cfg.PasosDeUnoEnUno -contains $paso) { $loteEf = 1 }
  Info ''
  Info "=== Paso '$paso' en lotes de $loteEf ==="

  $planB = @{}
  for ($n = 1; $n -le $MaxLotes; $n++) {
    $pend = @($hall | Where-Object { $_.Cat -eq $paso -and $_.Sev -eq 'error' })
    if ($pend.Count -eq 0) { break }
    $stuck = @()
    if ($script:Atascados.ContainsKey($paso)) { $stuck = @($script:Atascados[$paso]) }
    $fichs = @($pend | ForEach-Object { $_.Fichero } | Select-Object -Unique | Where-Object { $stuck -notcontains $_ })
    $sel = @($fichs | Select-Object -Skip $Saltar -First $loteEf)
    if ($sel.Count -eq 0) { break }
    $mod = ''
    if ($sel.Count -eq 1 -and $planB.ContainsKey($sel[0])) { $mod = $ModeloB }
    $buildAntes = $script:Build
    $loteH = @($pend | Where-Object { $sel -contains $_.Fichero })
    $antes = @{}
    foreach ($c in $Cfg.Orden) { $antes[$c] = Get-Cuenta $hall $c }
    $antesCompila = $script:Build.Compila
    $check = ((Invoke-Git $RepoRoot @('rev-parse', 'HEAD')).Salida -join '').Trim()
    Info ''
    Info "--- Lote $n : $($loteH.Count) hallazgo(s) en $($sel.Count) fichero(s); pendientes del paso: $($pend.Count) ---"
    $sel | ForEach-Object { Info "  $_" }

    $ok = $false; $correccion = ''; $hall2 = @(); $blandos = @(); $problemas = @()
    $g0 = Get-Guardas   # una vez por lote: los reintentos se comparan con el estado bueno
    for ($i = 1; $i -le $MaxIntentos; $i++) {
      [System.IO.File]::WriteAllText((Join-Path $Work 'prompt.md'), (New-Prompt $paso $loteH $correccion))
      Info "  Copilot trabajando (intento $i de $MaxIntentos)..."
      $rc = Invoke-Copilot (Join-Path $Work "lote-$paso-$n-$i.log") $mod
      if ($rc.Codigo -ne 0) { Aviso "  Copilot termino con codigo $($rc.Codigo) (ver .rescate/lote-$paso-$n-$i.log)" }

      # -- guardas duras: si saltan, no hay reintento --
      $g1 = Get-Guardas
      if ($g1.Plantilla -ne $g0.Plantilla -or $g1.Legacy -ne $g0.Legacy) {
        Undo-Lote $rama $check
        Fallo 'ALTO: se ha modificado la PLANTILLA o el repo ORIGINAL. He deshecho el lote en este repo.'
        Fallo 'Revisa esas carpetas con git status y restauralas antes de seguir.'
        exit 4
      }
      $ramaAhora = ((Invoke-Git $RepoRoot @('rev-parse', '--abbrev-ref', 'HEAD')).Salida -join '').Trim()
      if ($ramaAhora -ne $rama) { $problemas = @('Copilot cambio de rama.'); break }
      $head = ((Invoke-Git $RepoRoot @('rev-parse', 'HEAD')).Salida -join '').Trim()
      if ($head -ne $check) { [void](Invoke-Git $RepoRoot @('reset', '-q', '--mixed', $check)) }   # si hizo commit, lo deshago y conservo los cambios

      $cambios = @((Invoke-Git $RepoRoot @('status', '--porcelain')).Salida | Where-Object { $_ })
      if ($cambios.Count -eq 0) {
        $problemas = @('No has cambiado ningun fichero.')
        $correccion = '- No has cambiado ningun fichero. Resuelve los hallazgos del lote.'
        continue
      }

      # -- puertas: decide el script, no la IA --
      $problemas = @(); $blandos = @()
      if ($g1.Tests -lt $g0.Tests) { $problemas += "Has borrado tests ($($g0.Tests) -> $($g1.Tests) ficheros). Restauralos." }
      if ($g1.Desactivados -gt $g0.Desactivados) { $problemas += 'Has desactivado tests con @Disabled/@Ignore. Quitalo.' }
      if ($g1.Aserciones -lt $g0.Aserciones) { $blandos += "hay menos aserciones en los tests ($($g0.Aserciones) -> $($g1.Aserciones))" }
      $tocados = @($cambios | ForEach-Object { ($_.Substring(3) -replace '^"|"$', '') })
      if ($paso -ne 'build' -and ($tocados -contains 'pom.xml')) { $blandos += 'ha tocado pom.xml' }
      $fuera = @($tocados | Where-Object { -not $_.StartsWith('src/') -and $_ -ne 'pom.xml' })
      if ($fuera.Count -gt 0) { $blandos += ('ha tocado ficheros fuera de src: ' + (($fuera | Select-Object -First 6) -join ', ')) }

      Info '  Comprobando (Maven)...'
      $hall2 = @(Invoke-Diagnostico $true $conTests)
      $d = Get-Cuenta $hall2 $paso
      if (-not $script:Build.Compila -and ($paso -ne 'build' -or $antesCompila)) { $problemas += 'El proyecto no compila.' }
      if ($d -ge $antes[$paso]) { $problemas += "Los hallazgos de '$paso' no han bajado ($($antes[$paso]) -> $d)." }
      foreach ($c in $Cfg.Orden) {
        if ($c -eq $paso) { break }
        $q = Get-Cuenta $hall2 $c
        if ($q -gt $antes[$c]) { $problemas += "Has empeorado el paso anterior '$c' ($($antes[$c]) -> $q hallazgos)." }
      }
      $ft = Get-Cuenta $hall2 'tests'
      if ($conTests -and $paso -ne 'tests' -and $ft -gt $antes['tests']) { $problemas += "Hay mas tests fallando que antes ($($antes['tests']) -> $ft)." }

      if ($problemas.Count -eq 0) { $ok = $true; break }
      $problemas | ForEach-Object { Aviso "  NO PASA: $_" }
      $detalle = @($hall2 | Where-Object { $_.Sev -eq 'error' -and (
            ($_.Cat -eq 'build' -and $_.Detalle -match '^(no compila|el build falla)') -or
            ($_.Cat -eq 'tests' -and $conTests) -or
            ($_.Cat -eq $paso -and $sel -contains $_.Fichero)) } | Select-Object -First 20 | ForEach-Object {
          $donde = $_.Fichero
          if ($_.Linea -gt 0) { $donde += ':' + $_.Linea }
          "  - $donde - $($_.Detalle)" })
      $correccion = ((@($problemas | ForEach-Object { "- $_" }) + @('Detalle:') + $detalle) -join "`n")
    }

    if (-not $ok) {
      # Nada se queda a medias: se deshace y se prueba algo mas facil.
      Undo-Lote $rama $check
      $script:Build = $buildAntes
      Aviso "Lote $n DESHECHO: no paso las comprobaciones tras $MaxIntentos intento(s)."
      $problemas | ForEach-Object { Aviso "  - $_" }
      $script:Fallos++
      if ($script:Fallos -ge $Cfg.MaxFallosSeguidos) {
        Fallo "PARO: $($script:Fallos) lotes deshechos seguidos. Puede ser un problema de Copilot, de Maven o de un flag, no del codigo."
        Info "Ultimas lineas de Copilot (.rescate/lote-$paso-$n-*.log):"
        $rc.Salida | Select-Object -Last 8 | ForEach-Object { Info "  $_" }
        exit 2
      }
      if ($sel.Count -gt 1) { Info '  -> lo reintento de uno en uno.'; $loteEf = 1; continue }
      if ($ModeloB -and -not $planB.ContainsKey($sel[0])) { Info "  -> lo reintento con el modelo de reserva ($ModeloB)."; $planB[$sel[0]] = $true; continue }
      Fallo "ATASCADO en '$paso': $($sel[0]). Lo apunto y sigo con el resto."
      if (-not $script:Atascados.ContainsKey($paso)) { $script:Atascados[$paso] = @() }
      $script:Atascados[$paso] += $sel[0]
      $nota = "- [$paso] $($sel[0]): " + ($problemas -join ' ') + " (registro: .rescate/lote-$paso-$n-*.log)`n"
      [System.IO.File]::AppendAllText((Join-Path $Work 'atascados.md'), $nota)
      continue
    }

    [void](Invoke-Git $RepoRoot @('add', '-A'))
    $d = Get-Cuenta $hall2 $paso
    $r = Invoke-Git $RepoRoot (@('commit', '-q', '-m', "rescate($paso): lote $n, hallazgos $($antes[$paso]) a $d") + $Cfg.CommitArgs)
    if ($r.Codigo -ne 0) { Fallo ('git commit ha fallado; los cambios siguen en el arbol de trabajo: ' + ($r.Salida -join ' ')); exit 3 }
    $hall = $hall2
    $script:Fallos = 0
    Write-Informe $hall
    Bien "Lote $n OK: '$paso' $($antes[$paso]) -> $d. Commit hecho."
    (Invoke-Git $RepoRoot @('show', '--stat', '--oneline', '--format=%h %s', 'HEAD')).Salida | Select-Object -First 25 | ForEach-Object { Info "  $_" }
    $blandos | ForEach-Object { Aviso "  REVISA: $_" }

    if (-not $Auto -and $d -gt 0) {
      $resp = Read-Host '[Enter] siguiente lote | n = parar aqui | d = deshacer este lote y parar'
      if ($resp -eq 'd') { $script:Parar = $true; Undo-Lote $rama $check; Aviso 'Lote deshecho.'; return }
      if ($resp -eq 'n') { $script:Parar = $true; break }
    }
  }

  Show-Resumen $hall
  $sig = Get-SiguientePaso $hall
  $script:Siguiente = $sig
  if ($sig) { Info "Siguiente paso pendiente: $sig  ->  vuelve a lanzar con -Modo fix (o -Paso $sig)" }
  else { Bien 'No quedan errores. Revisa los avisos del informe, el diff completo de la rama y pasa tu pipeline.' }
}

# ================================= MAIN =================================
$RepoRoot = Resolve-Dir $Repo
$PlantillaRoot = Resolve-Dir $Plantilla
$LegacyRoot = Resolve-Dir $Legacy
if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot '.git'))) { Fallo "No es la raiz de un repo git: $RepoRoot"; exit 1 }
if ($PlantillaRoot -and ($PlantillaRoot -eq $RepoRoot)) { Aviso 'Repo y plantilla son la misma carpeta: todo saldra permitido.' }

$Work = Join-Path $RepoRoot '.rescate'
if (-not (Test-Path -LiteralPath $Work)) { [void](New-Item -ItemType Directory -Path $Work) }
# .rescate y target se ignoran solo en local (no toca .gitignore)
$exc = ((Invoke-Git $RepoRoot @('rev-parse', '--git-path', 'info/exclude')).Salida -join '').Trim()
if ($exc) {
  if (-not [System.IO.Path]::IsPathRooted($exc)) { $exc = Join-Path $RepoRoot $exc }
  $dirExc = Split-Path $exc -Parent
  if (-not (Test-Path -LiteralPath $dirExc)) { [void](New-Item -ItemType Directory -Path $dirExc) }
  $ya = ''
  if (Test-Path -LiteralPath $exc) { $ya = [System.IO.File]::ReadAllText($exc) }
  if ($ya -notmatch '(?m)^\.rescate/') { [System.IO.File]::AppendAllText($exc, "`n.rescate/`ntarget/`n") }
}

# Ajustes propios de este repo: .rescate/config.json pisa las claves de $Cfg
$cfgRepo = Join-Path $Work 'config.json'
if (Test-Path -LiteralPath $cfgRepo) {
  try {
    $o = [System.IO.File]::ReadAllText($cfgRepo) | ConvertFrom-Json
    foreach ($pr in $o.PSObject.Properties) {
      if ($Cfg.ContainsKey($pr.Name)) { $Cfg[$pr.Name] = $pr.Value } else { Aviso "config.json: clave desconocida '$($pr.Name)'" }
    }
  }
  catch { Fallo ('No puedo leer .rescate/config.json: ' + $_.Exception.Message); exit 1 }
}

$script:Atascados = @{}   # paso -> ficheros que la IA no ha sabido arreglar
$script:Fallos = 0        # lotes deshechos seguidos
$script:H = $null
$script:Build = $null
$script:BasePkg = ''
$script:Cal = $null
if ($PlantillaRoot) {
  Info 'Leyendo la plantilla...'
  $script:Cal = Get-Calibracion $PlantillaRoot
}

switch ($Modo) {
  'diagnostico' {
    if ($SinBuild) { Info 'Diagnostico sin Maven...' } else { Info 'Diagnostico (ejecutando Maven, puede tardar)...' }
    $hall = @(Invoke-Diagnostico (-not $SinBuild) (-not $SinTests))
    Write-Informe $hall
    Show-Resumen $hall
    $sig = Get-SiguientePaso $hall
    if ($sig) { Info "Siguiente paso recomendado: $sig  ->  -Modo fix -Paso $sig" } else { Bien 'Sin errores.' }
  }
  'pre' { Invoke-Pre }
  'fix' {
    if ($Todo) { $Auto = [switch]$true }
    $script:Parar = $false
    $script:Siguiente = ''
    $previo = ''
    while ($true) {
      Invoke-Fix
      if (-not $Todo -or $Paso -or $script:Parar -or -not $script:Siguiente) { break }
      if ($script:Siguiente -eq $previo) { Aviso "El paso '$previo' no avanza: paro aqui."; break }
      $previo = $script:Siguiente
    }
    if ($script:Atascados.Count -gt 0) {
      Fallo ''
      Fallo 'Se ha quedado sin arreglar (lo unico que te toca mirar):'
      foreach ($k in $Cfg.Orden) { if ($script:Atascados.ContainsKey($k)) { $script:Atascados[$k] | ForEach-Object { Fallo "  [$k] $_" } } }
      Info ('Detalle: ' + (Join-Path $Work 'atascados.md'))
      Info 'Opciones: otro modelo (-Modelo / -ModeloB), arreglarlo a mano, o volver a lanzar.'
      exit 2
    }
  }
  'deshacer' {
    $asunto = ((Invoke-Git $RepoRoot @('log', '-1', '--format=%s')).Salida -join '')
    if ($asunto -notmatch '^rescate\(') { Fallo "El ultimo commit no es un lote de rescate ('$asunto'). No hago nada."; exit 1 }
    if (Confirmar "Deshago el commit '$asunto'?") {
      [void](Invoke-Git $RepoRoot @('reset', '-q', '--hard', 'HEAD~1'))
      [void](Invoke-Git $RepoRoot @('clean', '-fdq'))
      Bien 'Hecho.'
    }
  }
}
