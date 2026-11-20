<#
preflight.ps1 - Una sola pasada, antes de migracion.ps1, para saber si este equipo, Copilot y
Maven sirven para lo que viene. Mide y cuenta; no arregla ni cambia ningun repo tuyo.
Compatible con Windows PowerShell 5.1 y PowerShell 7. Solo ASCII a proposito.
Necesita comun.ps1, tareas.ps1, analisis.ps1 y las carpetas tareas\, preflight\, analisis\ y tests\ junto a este script.

USO (todo es opcional)
  .\preflight.ps1 -Legacy C:\ruta\original -Migrado C:\ruta\migrado -Plantilla C:\ruta\referencia -Modelo <id>
  .\preflight.ps1 -Modelos claude-haiku-5.5,gpt-6-luna,mai-code-2-flash        # examen de modelos (bloque 9)
  .\preflight.ps1 -Solo 1,3        # solo esos bloques
  .\preflight.ps1 -SinCopilot      # salta los bloques 4, 5, 8 y 9 (los que llaman al modelo)
  .\preflight.ps1 -SinMaven        # salta el 6 y el diagnostico del 7
Una ruta de -Legacy, -Migrado o -Plantilla que no es una carpeta se dice al instante (sin repetirla) y sale con 1.

BLOQUES (cada uno en su try; el fichero se reescribe al acabar cada bloque)
  1 entorno       modo de lenguaje, versiones, politica de ejecucion, suspension, disco
  2 bancos        tests\probar.ps1 como proceso hijo (probar-migracion es un banco de desarrollo y no entra)
  3 copilot       que banderas conoce (sin llamar a ningun modelo)
  4 aptitud       la ficha de un fichero de juguete, 3 veces + esfuerzo alto + herramientas limitadas
  5 paralelo      4 fichas de juguete a la vez
  6 maven         compilar, JaCoCo, OpenRewrite, y SpotBugs con PMD, sobre preflight\juguete (Maven de los
                  ajustes, el mvn del PATH o el mvnw de -Migrado, por este orden; la linea 'maven usado' dice
                  cual). Si SpotBugs y PMD no se descargan es un aviso, no un fallo: el paso sonar va sin ellos
  7 forma         numeros de los repos (git, tests, pom, sftp, config, ficheros locales) y el
                  diagnostico de rescate.ps1, con cuantas reglas incumple la propia referencia
                  (solo numeros y palabras fijas). El diagnostico corre sobre un clon temporal del
                  ultimo commit del migrado (sin tus cambios sin commitear), que se borra al acabar:
                  tu carpeta no se toca mientras sigues trabajando en ella. Tope: MinutosDiagnostico
  8 clases reales 5 clases del original por tamano: la ficha de cada una
  9 examen        con cada modelo de -Modelos y cada esfuerzo de -Esfuerzos (medium por defecto): la ficha de
                  una clase corta y de una larga, y arreglar un Maven de juguete y ponerle Javadoc. Cuenta
                  creditos y segundos, y recomienda uno. Una sola pasada por combinacion: es orientativo.
                  Los ids son los que ensena /model dentro de Copilot.

RESULTADO preflight-resultado.txt junto al script. Por consola, al final, dice donde esta y si lo copio
al portapapeles (solo en Windows y si puede); esas dos lineas no van al fichero.
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
  [string]$Modelo = '',        # id del modelo de Copilot; sin esto, el primero de -Modelos o el que tenga Copilot
  [string[]]$Modelos = @(),    # modelos del examen (bloque 9): claude-haiku-5.5,gpt-6-luna,mai-code-2-flash (con -File llega como un solo texto)
  [string[]]$Esfuerzos = @(),  # esfuerzos del examen; por defecto solo medium (se puede pedir medium,max)
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
$script:MavenBien = $null   # el primer paso del bloque 6: $true, $false o $null si no se midio
try {
  . (Join-Path $PSScriptRoot 'comun.ps1')
  . (Join-Path $PSScriptRoot 'tareas.ps1')
  . (Join-Path $PSScriptRoot 'analisis.ps1')
}
catch {
  $l = @($Cabecera, '== 1 entorno', "modo de lenguaje: $modo", ('fallo: no se pudo cargar la biblioteca (' + $_.Exception.GetType().Name + ')'), '== fin', 'bloques con fallo: 1', 'duracion: 0 min')
  try { Set-Content -LiteralPath $Salida -Value $l -Encoding ASCII } catch { }
  $l | ForEach-Object { Write-Host $_ }
  exit 1
}

# ================================== SALIDA ==================================
function Add-Linea([string]$Texto) { $script:Lineas.Add($Texto) }

function Save-ResultadoPreflight {
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

# La politica de ejecucion es la del equipo: los procesos hijo no la cambian.
function Get-ArgsPowerShell([string[]]$Mas) {
  return (@('-NoProfile', '-File') + $Mas)
}

# El numero de version que sale en la salida de '<exe> <args>'.
function Get-Version([string]$Exe, [string[]]$A, [string]$Patron, [string]$Dir = $PSScriptRoot) {
  try {
    $r = Invoke-Proceso $Exe $A $Dir 60
    if ($r.Agotado) { return 'tiempo agotado' }
    $m = [regex]::Match($r.Texto, $Patron)
    if ($m.Success) { return $m.Groups[1].Value }
    return 'desconocida'
  }
  catch { return 'no disponible' }
}

# El Maven del preflight: el de los ajustes (MvnExe), si no el mvn del PATH y si no el mvnw de -Migrado.
# Origen: ajustes, mvn, envoltorio o ninguno.
function Get-MavenElegido {
  if ($Cfg.MvnExe) { return [pscustomobject]@{ Exe = $Cfg.MvnExe; Origen = 'ajustes' } }
  if (@(Get-Command mvn -CommandType Application -ErrorAction SilentlyContinue).Count -gt 0) { return [pscustomobject]@{ Exe = 'mvn'; Origen = 'mvn' } }
  $raiz = Resolve-Param $Migrado
  if ($raiz) {
    $w = Get-Mvn $raiz
    if ($w -ne 'mvn') { return [pscustomobject]@{ Exe = $w; Origen = 'envoltorio' } }
  }
  return [pscustomobject]@{ Exe = ''; Origen = 'ninguno' }
}

# Si Copilot conoce esa bandera, sin llamar a ningun modelo: si, no o no se pudo probar.
function Get-EstadoBandera([string[]]$A) {
  try {
    $r = Invoke-Proceso $Cfg.CopilotExe ($A + '--version') $PSScriptRoot 60
    if (-not $r.Agotado) { return (Get-SiNo ($r.Texto -notmatch 'unexpected argument')) }
  }
  catch { }
  return 'no se pudo probar'
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

# El Maven para trabajar en la carpeta $Dir: el elegido; un mvnw funciona desde su carpeta y se lleva con su .mvn.
function Get-MvnProyecto($Elegido, [string]$Dir) {
  if ($Elegido.Origen -ne 'envoltorio') { return $Elegido.Exe }
  $origen = Split-Path $Elegido.Exe -Parent
  foreach ($f in @('mvnw', 'mvnw.cmd', '.mvn')) {
    $de = Join-Path $origen $f
    if (Test-Path -LiteralPath $de) { Copy-Item -LiteralPath $de -Destination (Join-Path $Dir $f) -Recurse -Force }
  }
  return (Get-Mvn $Dir)
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

# Un valor de un pom solo se escribe si tiene forma de version; si no, 'otro' (puede ser ${revision} o un texto suyo).
function Get-ValorPom([string]$Texto) {
  $t = "$Texto".Trim()
  if (-not $t) { return 'ninguno' }
  if ($t -cmatch '^[0-9][0-9A-Za-z.\-]{0,20}$') { return $t }
  return 'otro'
}

# El primer hijo de un nodo XML con ese nombre local (sin mirar el espacio de nombres).
function Get-HijoXml($Nodo, [string]$Nombre) {
  if ($null -eq $Nodo) { return $null }
  foreach ($h in $Nodo.ChildNodes) { if ($h.NodeType -eq 'Element' -and $h.LocalName -ceq $Nombre) { return $h } }
  return $null
}

# 'java <v> | spring-boot <v> | padre <spring-boot|propio|ninguno>' del pom.xml de la raiz, 'sin pom' o 'ilegible'.
# De un padre que no es spring-boot-starter-parent no sale ni el nombre ni la version.
function Get-LineaPom([string]$Raiz) {
  $ruta = Join-Path $Raiz 'pom.xml'
  if (-not (Test-Path -LiteralPath $ruta -PathType Leaf)) { return 'sin pom' }
  $doc = New-Object System.Xml.XmlDocument
  $flujo = $null
  $lector = $null
  try {
    $ajustes = New-Object System.Xml.XmlReaderSettings
    $ajustes.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $flujo = [System.IO.File]::OpenRead($ruta)
    $lector = [System.Xml.XmlReader]::Create($flujo, $ajustes)
    $doc.Load($lector)
  }
  catch { return 'ilegible' }
  finally {
    if ($lector) { $lector.Close() }
    if ($flujo) { $flujo.Close() }
  }
  $java = 'ninguno'
  $props = Get-HijoXml $doc.DocumentElement 'properties'
  foreach ($n in @('java.version', 'maven.compiler.release', 'maven.compiler.source')) {
    $h = Get-HijoXml $props $n
    if ($h) { $java = Get-ValorPom $h.InnerText; break }
  }
  $boot = 'ninguno'
  $padre = 'ninguno'
  $p = Get-HijoXml $doc.DocumentElement 'parent'
  if ($p) {
    $art = Get-HijoXml $p 'artifactId'
    if ($art -and $art.InnerText.Trim() -ceq 'spring-boot-starter-parent') {
      $padre = 'spring-boot'
      $boot = Get-ValorPom (Get-HijoXml $p 'version').InnerText
    }
    else { $padre = 'propio' }
  }
  return "java $java | spring-boot $boot | padre $padre"
}

# 'si' si HEAD apunta a una rama, 'no' si esta suelta y 'desconocido' si git no contesta.
function Get-EnRama([string]$Raiz) {
  try {
    $r = Invoke-Git $Raiz @('symbolic-ref', '-q', 'HEAD')
    if ($r.Codigo -eq 0) { return 'si' }
    if ($r.Codigo -eq 1) { return 'no' }
  }
  catch { }
  return 'desconocido'
}

# Lo que se cuenta de un repo, solo numeros y palabras fijas: nunca un nombre ni un texto suyo.
function Add-DatosRepo([string]$Nombre, [string]$Raiz) {
  $git = Test-Path -LiteralPath (Join-Path $Raiz '.git')
  Add-Linea "$Nombre repo git: $(Get-SiNo $git)"
  if ($git) { Add-Linea "$Nombre en una rama: $(Get-EnRama $Raiz)" }
  $codigo = New-Object 'System.Collections.Generic.HashSet[string]'
  foreach ($j in @(Get-JavaOriginal $Raiz)) { [void]$codigo.Add($j.FullName) }
  $c = [ordered]@{ tests = 0; jsch = 0; sshd = 0; integracion = 0; sshj = 0; valor = 0; propiedades = 0; getenv = 0; locales = 0 }
  foreach ($j in @(Get-Ficheros $Raiz '*.java')) {
    if ((Get-Rel $Raiz $j.FullName) -match '(^|/)src/test/') { $c.tests++ }
    $t = [System.IO.File]::ReadAllText($j.FullName)
    if ($t -cmatch 'import\s+(?:static\s+)?com\.jcraft\.jsch\b') { $c.jsch++ }
    if ($t -cmatch 'import\s+(?:static\s+)?org\.apache\.sshd\b') { $c.sshd++ }
    if ($t -cmatch 'import\s+(?:static\s+)?org\.springframework\.integration\.sftp\b') { $c.integracion++ }
    if ($t -cmatch 'import\s+(?:static\s+)?net\.schmizz\.sshj\b') { $c.sshj++ }
    if ($t -cmatch '@Value\b') { $c.valor++ }
    if ($t -cmatch '@ConfigurationProperties\b') { $c.propiedades++ }
    if ($t -cmatch '\bgetenv\s*\(') { $c.getenv++ }
    if ($codigo.Contains($j.FullName) -and $t -cmatch 'java\.io\.File\b|\bFileReader\b|\bFileWriter\b|\bFileInputStream\b|\bFileOutputStream\b|java\.nio\.file\.Files\b') { $c.locales++ }
  }
  $aplicacion = @(Get-Ficheros $Raiz 'application*' | Where-Object { $_.Name -match '^application.*\.(yml|yaml|properties)$' }).Count
  Add-Linea "$Nombre tests: $($c.tests) ficheros"
  Add-Linea "$Nombre pom: $(Get-LineaPom $Raiz)"
  Add-Linea "$Nombre sftp: jsch $($c.jsch) | sshd $($c.sshd) | spring-integration $($c.integracion) | sshj $($c.sshj)"
  Add-Linea "$Nombre config: @Value $($c.valor) | @ConfigurationProperties $($c.propiedades) | getenv $($c.getenv) | ficheros application $aplicacion"
  Add-Linea "$Nombre ficheros locales: $($c.locales)"
}

# De un fichero, su extension si es de las que se lanzan (.exe, .cmd, .bat, .ps1, .com), 'sin extension' o 'otra'.
function Get-TipoFichero([string]$Ruta) {
  $ext = [System.IO.Path]::GetExtension($Ruta).ToLowerInvariant()
  if (-not $ext) { return 'sin extension' }
  if (@('.exe', '.cmd', '.bat', '.ps1', '.com') -contains $ext) { return $ext }
  return 'otra'
}

# Los bloques: cada uno en su try; el fichero se reescribe al acabar cada uno.
function Invoke-Bloque([int]$N, [string]$Nombre, [int]$Minutos, [scriptblock]$Cuerpo, [bool]$SinMensaje = $false) {
  if ($SoloN.Count -gt 0 -and $SoloN -notcontains $N) { return }
  Write-Host "== $N $Nombre (hasta $Minutos min)..."
  Add-Linea "== $N $Nombre"
  $bien = $true
  $latido = Start-Latido "bloque $N, $Nombre" $Cfg.SegundosLatido
  try { & $Cuerpo }
  catch {
    $bien = $false
    Add-Linea ('fallo: ' + (Get-Fallo $_ $SinMensaje))
    $script:Fallos += $N
  }
  finally { Stop-Latido $latido }
  if ($bien) { Write-Host 'hecho' } else { Write-Host 'fallo' }
  Save-ResultadoPreflight
}

# ============================ EXAMEN DE MODELOS (bloque 9) ============================
# Las pruebas de preflight\examen\ con cada modelo y cada esfuerzo, una detras de otra (el tiempo de una llamada tiene que
# poderse comparar con el de las demas): L1 y L2 son la ficha de una clase corta y la de una larga (troceada como la trocea el
# sistema); E1 y E2 son arreglar dos errores de compilacion y poner Javadoc, en un proyecto Maven de juguete.

# Los trozos en que el sistema parte la clase larga del examen (Get-TareasFichas, segun LineasPorTarea).
function Get-TrozosExamen {
  $fichero = Get-Item -LiteralPath (Join-Ruta $PSScriptRoot 'preflight/examen/GestorRecibos.java')
  $legacyAntes = $script:LegacyRoot
  $datosAntes = $script:Datos
  $script:LegacyRoot = $fichero.DirectoryName
  $script:Datos = New-Carpeta (Join-Path $Tmp 'examen-datos')
  try { $tareas = @(Get-TareasFichas @($fichero) $false) }
  finally { $script:LegacyRoot = $legacyAntes; $script:Datos = $datosAntes }
  return @($tareas | ForEach-Object { [pscustomobject]@{ Desde = [int]$_.entradas.desde; Hasta = [int]$_.entradas.hasta } })
}

# Minutos que puede durar una llamada: 2 con low y medium; con otro esfuerzo (max puede tardar lo que el tope), el tope de
# una llamada (SegundosPorLlamada) redondeado hacia arriba.
function Get-MinutosPorLlamada([string]$Esfuerzo) {
  if ($Esfuerzo -ceq 'low' -or $Esfuerzo -ceq 'medium') { return 2 }
  return [int][math]::Ceiling([double]$Cfg.SegundosPorLlamada / 60)
}

# Los trozos, las llamadas y los minutos de todo el examen, y si las pruebas E tienen Maven.
function Get-PlanExamen {
  $plan = [pscustomobject]@{ Trozos = @(Get-TrozosExamen); ConMaven = $false; Llamadas = 0; Minutos = 1 }
  $plan.ConMaven = (-not $SinMaven -and $script:Fallos -notcontains 6 -and $script:MavenBien -ne $false -and (Get-MavenElegido).Origen -ne 'ninguno')
  $por = 1 + $plan.Trozos.Count
  if ($plan.ConMaven) { $por += 2 }
  $plan.Llamadas = $ModelosN.Count * $EsfuerzosN.Count * $por
  $minutos = 0
  foreach ($e in $EsfuerzosN) { $minutos += $ModelosN.Count * $por * (Get-MinutosPorLlamada $e) }
  $plan.Minutos = [math]::Max(1, $minutos)
  return $plan
}

function Format-Creditos($C) {
  if ($null -eq $C) { return 'desconocido' }
  return ([double]$C).ToString('0.000', [System.Globalization.CultureInfo]::InvariantCulture).Replace('.', ',')
}

# Una combinacion cumple si sus dos lecturas valen, acierta al menos el 90 % de la clave, el 90 % de sus citas se prueban y
# pasan todos los arreglos que se intentaron.
function Test-Cumple($C) {
  if (-not $C.LecturaValida -or $C.ClaveTotal -le 0 -or $C.Datos -le 0) { return $false }
  if (($C.Clave * 10) -lt ($C.ClaveTotal * 9) -or ($C.Citas * 10) -lt ($C.Datos * 9)) { return $false }
  return ($C.Arreglos -eq $C.Intentados)
}

# Las lineas de la recomendacion: entre las que cumplen, la de menos creditos (la de menos segundos si falta el dato o
# empatan); si ninguna cumple, la mejor por arreglos que pasan y despues por clave. Sin IA.
function Get-Recomendacion($Combos) {
  $todas = @($Combos)
  if ($todas.Count -eq 0) { return @('recomendado: sin datos') }
  $cumplen = @($todas | Where-Object { Test-Cumple $_ })
  if ($cumplen.Count -eq 0) {
    $m = $todas[0]
    foreach ($c in $todas) { if ($c.Arreglos -gt $m.Arreglos -or ($c.Arreglos -eq $m.Arreglos -and $c.Clave -gt $m.Clave)) { $m = $c } }
    $arreglos = 'sin maven'
    if ($m.Intentados -gt 0) { $arreglos = "$($m.Arreglos) de $($m.Intentados)" }
    return @('recomendado: ninguno cumple', "la mejor: $($m.Modelo) con esfuerzo $($m.Esfuerzo) (clave $($m.Clave) de $($m.ClaveTotal), arreglos $arreglos)", 'todo con uno: no')
  }
  $elegida = $cumplen[0]
  $sinDato = (@($cumplen | Where-Object { $null -eq $_.Creditos }).Count -gt 0)
  if ($cumplen.Count -eq 1) {
    $dato = 'sin dato de creditos'
    if ($null -ne $elegida.Creditos) { $dato = (Format-Creditos $elegida.Creditos) + ' creditos' }
    $motivo = "cumple y es la unica que cumple ($dato)"
  }
  elseif ($sinDato) {
    foreach ($c in $cumplen) { if ($c.Segundos -lt $elegida.Segundos) { $elegida = $c } }
    $motivo = 'cumple y es la mas rapida (sin dato de creditos)'
  }
  else {
    $menor = ($cumplen | ForEach-Object { [math]::Round([double]$_.Creditos, 3) } | Measure-Object -Minimum).Minimum
    $empatan = @($cumplen | Where-Object { [math]::Round([double]$_.Creditos, 3) -eq $menor })
    if ($empatan.Count -gt 1) {
      $elegida = $empatan[0]
      foreach ($c in $empatan) { if ($c.Segundos -lt $elegida.Segundos) { $elegida = $c } }
      $motivo = 'cumple y es la mas rapida (empatan en creditos: ' + (Format-Creditos $menor) + ')'
    }
    else {
      $elegida = $empatan[0]
      $siguiente = ($cumplen | ForEach-Object { [math]::Round([double]$_.Creditos, 3) } | Where-Object { $_ -ne $menor } | Measure-Object -Minimum).Minimum
      $motivo = 'cumple y es la mas barata (' + (Format-Creditos $menor) + ' creditos; la siguiente, ' + (Format-Creditos $siguiente) + ')'
    }
  }
  $todoUno = 'si'
  if ($elegida.Intentados -eq 0) { $todoUno = 'sin dato de arreglos' }
  return @("recomendado: $($elegida.Modelo) con esfuerzo $($elegida.Esfuerzo)", "motivo: $motivo", "todo con uno: $todoUno")
}

# La suma de un campo de Read-Uso en varias llamadas; $null si falta en alguna (una suma a medias engana).
function Get-SumaUso($Usos, [string]$Campo) {
  $suma = [double]0
  $n = 0
  foreach ($u in @($Usos)) {
    if ($null -eq $u.$Campo) { return $null }
    $suma += [double]$u.$Campo
    $n++
  }
  if ($n -eq 0) { return $null }
  return $suma
}

# Reparte los datos de la ficha entre las condiciones de la clave: un dato vale para una sola condicion (Kuhn).
function Test-Emparejar([int]$I, $Candidatos, [bool[]]$Vistos, [int[]]$DeDato) {
  foreach ($j in $Candidatos[$I]) {
    if ($Vistos[$j]) { continue }
    $Vistos[$j] = $true
    if ($DeDato[$j] -lt 0 -or (Test-Emparejar $DeDato[$j] $Candidatos $Vistos $DeDato)) { $DeDato[$j] = $I; return $true }
  }
  return $false
}

# De las condiciones de la clave (tipo, desde, hasta), cuantas trae la ficha: un dato con la cita probada, del mismo tipo
# (regla y error valen lo mismo) y con la linea entre desde-CitaCerca y hasta+CitaCerca.
function Get-ClaveEncontrada($Datos, $Clave) {
  $buenos = @($Datos | Where-Object { $_.probado })
  $cerca = [int]$Cfg.CitaCerca
  $condiciones = @($Clave)
  $candidatos = New-Object 'object[]' $condiciones.Count
  for ($i = 0; $i -lt $condiciones.Count; $i++) {
    $c = $condiciones[$i]
    $tipo = $c.tipo -replace '^error$', 'regla'
    $lista = @()
    for ($j = 0; $j -lt $buenos.Count; $j++) {
      $t = $buenos[$j].tipo -replace '^error$', 'regla'
      if ($t -ceq $tipo -and $buenos[$j].linea -ge ($c.desde - $cerca) -and $buenos[$j].linea -le ($c.hasta + $cerca)) { $lista += $j }
    }
    $candidatos[$i] = @($lista)
  }
  $deDato = New-Object 'int[]' $buenos.Count
  for ($j = 0; $j -lt $deDato.Count; $j++) { $deDato[$j] = -1 }
  $hallados = 0
  for ($i = 0; $i -lt $condiciones.Count; $i++) {
    $vistos = New-Object 'bool[]' $buenos.Count
    if (Test-Emparejar $i $candidatos $vistos $deDato) { $hallados++ }
  }
  return $hallados
}

# Cadenas, caracteres y comentarios de Java, de izquierda a derecha en una sola pasada: solo los comentarios se tratan.
$script:PatronJava = '"""[\s\S]*?"""|"(?:\\.|[^"\\\r\n])*"|''(?:\\.|[^''\\\r\n])*''|/\*[\s\S]*?\*/|//[^\r\n]*'

# El codigo de un .java sin comentarios ni espacios: lo que tiene que quedar igual al poner Javadoc.
function Get-CodigoJava([string]$Texto) {
  $sin = [regex]::Replace($Texto, $script:PatronJava, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) if ($m.Value.StartsWith('/')) { '' } else { $m.Value } })
  return ([regex]::Replace($sin, '\s+', ''))
}

# El codigo de los .java de src/main de una carpeta, cada uno con su ruta.
function Get-CodigoMain([string]$Dir) {
  $partes = @()
  foreach ($f in @(Get-Ficheros $Dir '*.java')) {
    $rel = Get-Rel $Dir $f.FullName
    if ($rel -like 'src/main/*') { $partes += ($rel + '|' + (Get-CodigoJava ([System.IO.File]::ReadAllText($f.FullName)))) }
  }
  return ((@($partes | Sort-Object)) -join "`n")
}

# Si cada tipo y cada metodo o constructor publico de un .java lleva su comentario /** ... */ justo encima (salvo anotaciones).
function Test-Javadoc([string]$Texto) {
  $lineas = @($Texto -split "`r?`n")
  # el mismo texto con cadenas y comentarios en blanco, para no confundir un 'public' que no es una declaracion
  $blanco = [System.Text.RegularExpressions.MatchEvaluator]{ param($m) [regex]::Replace($m.Value, '[^\r\n]', ' ') }
  $limpio = @([regex]::Replace($Texto, $script:PatronJava, $blanco) -split "`r?`n")
  for ($i = 0; $i -lt $limpio.Count; $i++) {
    $l = $limpio[$i].Trim()
    if ($l -notmatch '^public\s') { continue }
    $esTipo = ($l -match '^public\s+(?:[\w<>\[\],.?@\s]+\s)?(?:class|interface|enum|record)\s+\w')
    $esMetodo = ($l -match '^public\s+[^=;(]*\w\s*\(')
    if (-not ($esTipo -or $esMetodo)) { continue }
    $j = $i - 1
    while ($j -ge 0 -and ($lineas[$j].Trim() -eq '' -or $lineas[$j].Trim().StartsWith('@'))) { $j-- }
    if ($j -lt 0 -or -not $lineas[$j].Trim().EndsWith('*/')) { return $false }
    while ($j -ge 0 -and $lineas[$j] -notmatch '/\*') { $j-- }
    if ($j -lt 0 -or $lineas[$j] -notmatch '/\*\*') { return $false }
  }
  return $true
}

function Test-JavadocMain([string]$Dir) {
  foreach ($f in @(Get-Ficheros $Dir '*.java')) {
    if ((Get-Rel $Dir $f.FullName) -like 'src/main/*' -and -not (Test-Javadoc ([System.IO.File]::ReadAllText($f.FullName)))) { return $false }
  }
  return $true
}

# Ruta relativa -> huella de cada fichero de una carpeta (sin .git, target ni .rescate): lo que cambia entre antes y despues.
function Get-HuellasPorFichero([string]$Dir) {
  $arbol = @{}
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { foreach ($f in @(Get-Ficheros $Dir '*')) { $arbol[(Get-Rel $Dir $f.FullName)] = [System.BitConverter]::ToString($sha.ComputeHash([System.IO.File]::ReadAllBytes($f.FullName))) } }
  finally { $sha.Dispose() }
  return $arbol
}

# Una lectura (la ficha de una tarea) con ese modelo y esfuerzo, y su gasto. Invoke-Ronda usa $ModeloElegido y el esfuerzo de lectura.
function Invoke-Lectura($Tarea, [string]$Dir, [string]$Modelo, [string]$Esfuerzo, [bool]$ConUso) {
  $archivo = Join-Path $Tmp ('uso-' + $Tarea.id + '-' + $Esfuerzo + '.json')
  $modeloAntes = $script:ModeloElegido
  $esfuerzoAntes = $Cfg.EsfuerzoLectura
  $argsAntes = @($Cfg.CopilotArgs)
  $script:ModeloElegido = $Modelo
  $Cfg.EsfuerzoLectura = $Esfuerzo
  if ($ConUso) { $Cfg.CopilotArgs = $argsAntes + "--usage-output-file=$archivo" }
  try { $o = @(Invoke-Ronda @($Tarea) $Dir $Dir)[0] }
  finally { $script:ModeloElegido = $modeloAntes; $Cfg.EsfuerzoLectura = $esfuerzoAntes; $Cfg.CopilotArgs = $argsAntes }
  return [pscustomobject]@{ Res = $o; Uso = (Read-Uso $archivo) }
}

# Por que no pasa un arreglo ('' si pasa): una palabra del vocabulario cerrado. $Antes es el arbol antes de llamar a Copilot.
function Get-MotivoArreglo([string]$Prueba, $Llamada, [string]$Dir, $Antes, [string]$Mvn) {
  if ($Llamada.Agotado) { return 'tiempo' }
  if ($Llamada.Codigo -ne 0) { return 'fallo de copilot' }
  $despues = Get-HuellasPorFichero $Dir
  $cambios = @(@($Antes.Keys) + @($despues.Keys) | Select-Object -Unique | Where-Object { $Antes[$_] -cne $despues[$_] })
  if ($cambios.Count -eq 0) { return 'sin cambios' }
  if (@($cambios | Where-Object { $_ -like 'src/test/*' }).Count -gt 0) { return 'toco tests' }
  if (@($cambios | Where-Object { $_ -notlike 'src/main/*' }).Count -gt 0) { return 'toco fuera de src/main' }
  $r = Invoke-Proceso $Mvn @('-B', '-q', 'test') $Dir 1500
  if ($r.Agotado) { return 'tiempo' }
  if ($r.Codigo -ne 0) {
    if ($r.Texto -match 'COMPILATION ERROR|Compilation failure|cannot find symbol') { return 'no compila' }
    return 'test falla'
  }
  if ($Prueba -eq 'E2') {
    if ((Get-CodigoMain $Dir) -cne (Get-CodigoMain (Join-Ruta $PSScriptRoot 'preflight/examen/e2'))) { return 'cambio codigo' }
    if (-not (Test-JavadocMain $Dir)) { return 'sin javadoc' }
  }
  return ''
}

# Un arreglo (E1 o E2): copia el proyecto, pide el arreglo con ese modelo y esfuerzo y dice si pasa.
function Invoke-Arreglo([int]$K, [string]$Prueba, [string]$Modelo, [string]$Esfuerzo, [bool]$ConUso) {
  $carpeta = $Prueba.ToLowerInvariant()
  $dir = Join-Path $Tmp "examen-$K-$carpeta"
  [void](New-Carpeta $dir)
  foreach ($h in @(Get-ChildItem -LiteralPath (Join-Ruta $PSScriptRoot "preflight/examen/$carpeta") -Force)) { Copy-Item -LiteralPath $h.FullName -Destination $dir -Recurse }
  $mvn = Get-MvnProyecto (Get-MavenElegido) $dir
  $antes = Get-HuellasPorFichero $dir
  $prompt = [System.IO.File]::ReadAllText((Join-Ruta $PSScriptRoot "preflight/examen/arreglo-$carpeta.md"), $Utf8) -replace "`r`n", "`n"
  $archivo = Join-Path $Tmp "uso-pf-exa-$K-$Prueba.json"
  $argsAntes = @($Cfg.CopilotArgs)
  if ($ConUso) { $Cfg.CopilotArgs = $argsAntes + "--usage-output-file=$archivo" }
  try { $c = @(Invoke-Llamadas @([pscustomobject]@{ Id = "pf-exa-$K-$Prueba"; Dir = $dir; Modelo = $Modelo; Esfuerzo = $Esfuerzo; Prompt = $prompt }))[0] }
  finally { $Cfg.CopilotArgs = $argsAntes }
  $motivo = Get-MotivoArreglo $Prueba $c $dir $antes $mvn
  return [pscustomobject]@{ Pasa = ($motivo -eq ''); Motivo = $motivo; Segundos = $c.Segundos; Uso = (Read-Uso $archivo) }
}

# Una prueba de lectura ya hecha, en una linea: json, citas, clave, segundos y creditos. Devuelve sus cuentas.
function Add-LineaLectura([string]$Nombre, $Hechas, $Clave) {
  $res = @($Hechas | ForEach-Object { $_.Res })
  $datos = @()
  foreach ($o in $res) { if ($o.Estado -eq 'ok') { $datos += @($o.Ficha.datos) } }
  $mal = @($res | Where-Object { $_.Estado -ne 'ok' })
  $citas = @($datos | Where-Object { $_.probado }).Count
  $seg = 0
  foreach ($o in $res) { $seg += [int]$o.Segundos }
  $r = [pscustomobject]@{ Valida = ($mal.Count -eq 0); Citas = $citas; Datos = $datos.Count; Clave = (Get-ClaveEncontrada $datos $Clave); ClaveTotal = @($Clave).Count; Segundos = $seg; Usos = @($Hechas | ForEach-Object { $_.Uso }) }
  Add-Linea ("${Nombre}: json " + (Get-SiNo $r.Valida) + " | citas $citas de $($datos.Count) | clave $($r.Clave) de $($r.ClaveTotal) | $seg s | creditos " + (Format-Creditos (Get-SumaUso $r.Usos 'Creditos')))
  if ($mal.Count -gt 0) { Add-Linea ('motivo: ' + (Get-Seguro (Get-MotivoCorto $mal[0].Motivo))) }
  return $r
}

# Una combinacion de modelo y esfuerzo entera. Escribe sus lineas y devuelve sus cuentas (SinModelo si Copilot no contesta
# ni con los esfuerzos mas bajos). $Vista es el id ya filtrado, para escribirlo.
function Invoke-Combinacion([int]$K, [string]$Modelo, [string]$Vista, [string]$Esfuerzo, [bool]$ConUso, $Claves, $Plan) {
  $dir = New-Carpeta (Join-Path $Tmp "examen-$K")
  foreach ($f in @('GeneradorRemesa.java', 'GestorRecibos.java')) { Copy-Item -LiteralPath (Join-Ruta $PSScriptRoot "preflight/examen/$f") -Destination (Join-Path $dir $f) }
  $c = [pscustomobject]@{ Modelo = $Vista; Esfuerzo = $Esfuerzo; SinModelo = $false; LecturaValida = $false; Clave = 0; ClaveTotal = 0; Citas = 0; Datos = 0; Arreglos = 0; Intentados = 0; Creditos = $null; Segundos = 0; Usos = @() }
  $t1 = New-Tarea "pf-exa-$K-L1" 'examen-L1' 'GeneradorRemesa.java' 1 (Get-Lineas (Join-Path $dir 'GeneradorRemesa.java'))
  # L1 hace de sonda: si Copilot sale con error sin escribir su ficha, se prueba un esfuerzo mas bajo
  $rechazo = ''
  $sinSalida = $true
  foreach ($e in (@($Esfuerzo) + @(Get-EsfuerzosMenores $Esfuerzo))) {
    $c.Esfuerzo = $e
    $h1 = Invoke-Lectura $t1 $dir $Modelo $e $ConUso
    $sinSalida = ($h1.Res.Estado -eq 'fallo' -and -not (Test-Path -LiteralPath (Join-Ruta $dir ".rescate/tareas/$($t1.id).json")))
    if (-not $sinSalida) { break }
    if (-not $rechazo) { $rechazo = $h1.Res.Linea }
  }
  if ($sinSalida) {
    Add-Linea ('sin modelo: ' + (Get-Seguro $h1.Res.Linea))
    $c.SinModelo = $true
    return $c
  }
  if ($c.Esfuerzo -ne $Esfuerzo) {
    Add-Linea ('esfuerzo usado: ' + $c.Esfuerzo + " ($Esfuerzo no admitido)")
    Add-Linea ('motivo del esfuerzo: ' + (Get-Seguro $rechazo))
  }
  $l1 = Add-LineaLectura 'L1' @($h1) $Claves.L1
  $hechas = @()
  $n = 0
  foreach ($trozo in $Plan.Trozos) {
    $n++
    $hechas += , (Invoke-Lectura (New-Tarea "pf-exa-$K-L2-$n" 'examen-L2' 'GestorRecibos.java' $trozo.Desde $trozo.Hasta) $dir $Modelo $c.Esfuerzo $ConUso)
  }
  $l2 = Add-LineaLectura 'L2' $hechas $Claves.L2
  $c.LecturaValida = ($l1.Valida -and $l2.Valida)
  $c.Clave = $l1.Clave + $l2.Clave
  $c.ClaveTotal = $l1.ClaveTotal + $l2.ClaveTotal
  $c.Citas = $l1.Citas + $l2.Citas
  $c.Datos = $l1.Datos + $l2.Datos
  $c.Segundos = $l1.Segundos + $l2.Segundos
  $c.Usos = @($l1.Usos) + @($l2.Usos)
  foreach ($prueba in @('E1', 'E2')) {
    if (-not $Plan.ConMaven) { Add-Linea "${prueba}: sin maven"; continue }
    $a = Invoke-Arreglo $K $prueba $Modelo $c.Esfuerzo $ConUso
    $dicho = 'si'
    if (-not $a.Pasa) { $dicho = 'no (' + $a.Motivo + ')' }
    Add-Linea ("${prueba}: pasa $dicho | $($a.Segundos) s | creditos " + (Format-Creditos $a.Uso.Creditos))
    $c.Intentados++
    if ($a.Pasa) { $c.Arreglos++ }
    $c.Usos += $a.Uso
    $c.Segundos += [int]$a.Segundos
  }
  $c.Creditos = Get-SumaUso $c.Usos 'Creditos'
  $entrada = Get-SumaUso $c.Usos 'TokensEntrada'
  $salida = Get-SumaUso $c.Usos 'TokensSalida'
  $tokens = 'tokens desconocido'
  if ($null -ne $entrada -and $null -ne $salida) { $tokens = "tokens entrada $([long]$entrada) salida $([long]$salida)" }
  $arreglos = 'sin maven'
  if ($c.Intentados -gt 0) { $arreglos = "$($c.Arreglos) de $($c.Intentados)" }
  Add-Linea ("total: clave $($c.Clave) de $($c.ClaveTotal) | arreglos $arreglos | $($c.Segundos) s | creditos " + (Format-Creditos $c.Creditos) + " | $tokens")
  return $c
}

# ============================ RUTAS DE ENTRADA ============================
# Una ruta mal escrita se dice al instante y no se lanza nada. Sin repetir la ruta: puede llevar nombres.
$noExisten = @()
foreach ($par in @(@('-Legacy', $Legacy), @('-Migrado', $Migrado), @('-Plantilla', $Plantilla))) {
  if (-not $par[1]) { continue }
  $esCarpeta = $false
  try { $esCarpeta = [bool](Test-Path -LiteralPath $par[1] -PathType Container) } catch { }
  if (-not $esCarpeta) { $noExisten += $par[0] }
}
if ($noExisten.Count -gt 0) {
  Add-Linea $Cabecera
  foreach ($n in $noExisten) {
    Add-Linea "para: no existe la carpeta de $n"
    Write-Host "No existe la carpeta de $n. Revisa la ruta y vuelve a lanzar."
  }
  Add-Linea '== fin'
  Save-ResultadoPreflight
  exit 1
}

# ================================== ARRANQUE ==================================
$SoloN = @()
foreach ($s in @($Solo)) {
  foreach ($p in ("$s" -split '[,;\s]+')) { if ($p -match '^\d+$') { $SoloN += [int]$p } }
}
# -Modelos y -Esfuerzos: ids separados por comas, sin repetir y en el orden que se dan
function Get-Lista($Valores) {
  $lista = @()
  foreach ($v in @($Valores)) {
    foreach ($p in ("$v" -split '[,;\s]+')) { if ($p -match '^[A-Za-z0-9][A-Za-z0-9._\-]*$' -and $lista -notcontains $p) { $lista += $p } }
  }
  return $lista
}
$ModelosN = @(Get-Lista $Modelos)
$EsfuerzosN = @(Get-Lista $Esfuerzos)
if ($EsfuerzosN.Count -eq 0) { $EsfuerzosN = @('medium') }
$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('preflight-' + [System.Guid]::NewGuid().ToString('N').Substring(0, 8))
[void](New-Item -ItemType Directory -Path $Tmp -Force)
$Registros = New-Carpeta (Join-Path $Tmp 'registros')
$ModeloElegido = $Modelo
if (-not $ModeloElegido -and $ModelosN.Count -gt 0) { $ModeloElegido = $ModelosN[0] }
$LegacyRoot = ''

# Las claves de solo el preflight (comun.ps1 lleva las de los dos scripts): hay que declararlas antes de leer ajustes.json.
$Cfg += @{
  MinutosDiagnostico = 30   # tope del diagnostico de rescate.ps1 del bloque 7, en minutos (admite decimales); pasado, se para con sus procesos hijos
}

# ajustes.json pisa $Cfg. Read-CfgFile sale con 1 si el JSON no vale: se mira antes.
$AjustesEstado = 'no hay'
$rutaAjustes = Get-RutaAjustes
if (Test-Path -LiteralPath $rutaAjustes) {
  try {
    $null = ([System.IO.File]::ReadAllText($rutaAjustes) | ConvertFrom-Json)
    [void](Read-CfgFile $rutaAjustes (Get-ClavesAjustes $PSScriptRoot))
    $AjustesEstado = 'leidos'
  }
  catch { $AjustesEstado = 'ilegibles' }
}
# un preflight no espera 15 minutos a una llamada: pasados 10 se da por colgada
if ([int]$Cfg.SegundosPorLlamada -gt 600) { $Cfg.SegundosPorLlamada = 600 }
try { Initialize-Filtro } catch { Add-Linea ('aviso: el filtro de privacidad no se cargo entero (' + $_.Exception.GetType().Name + ')') }
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
    $mvnElegido = Get-MavenElegido
    if ($mvnElegido.Origen -eq 'ninguno') { Add-Linea 'maven: no disponible' }
    else {
      # un mvnw busca su .mvn desde la carpeta de trabajo: se mide desde la suya
      $carpetaMvn = $PSScriptRoot
      if ($mvnElegido.Origen -eq 'envoltorio') { $carpetaMvn = Split-Path $mvnElegido.Exe -Parent }
      Add-Linea ('maven: ' + (Get-Version $mvnElegido.Exe @('--version') 'Apache Maven (\d+(?:\.\d+)+)' $carpetaMvn))
    }
    Add-Linea ('copilot: ' + (Get-Version $Cfg.CopilotExe @('--version') '(\d+\.\d+(?:\.\d+)*)'))
    # lo primero que encuentra PowerShell con el nombre del Copilot (funcion, alias o fichero y su extension) y lo que se
    # lanza de verdad: la misma eleccion que hace Get-Lanzador
    $tipo = 'no encontrado'; $seLanza = 'nada'
    try {
      $c = @(Get-Command $Cfg.CopilotExe -All -ErrorAction SilentlyContinue)
      if ($c.Count -gt 0) {
        $k = "$($c[0].CommandType)"
        if ($k -eq 'Function') { $tipo = 'funcion' }
        elseif ($k -eq 'Alias') { $tipo = 'alias' }
        elseif ($k -eq 'Cmdlet') { $tipo = 'cmdlet' }
        else { $tipo = Get-TipoFichero "$($c[0].Source)" }
      }
      $lanzable = (Get-Lanzable $Cfg.CopilotExe).Ruta
      if ($lanzable) { $seLanza = Get-TipoFichero $lanzable }
    }
    catch { }
    Add-Linea "tipo de copilot: $tipo | se lanza: $seLanza"
    $suelta = Set-Despierto $false
    [void](Set-Despierto $true)
    Add-Linea ('impide la suspension: ' + (Get-SiNo $despierto) + ' | al soltar ' + (Get-SiNo $suelta))
    $cp = 'desconocida'
    try { $cp = "$([Console]::OutputEncoding.CodePage)" } catch { }
    Add-Linea "pagina de codigos: $cp"
    $gb = 'desconocido'
    try {
      # el disco de -Migrado (con su ruta completa: una relativa no tiene raiz) o el del script
      $enDisco = Resolve-Param $Migrado
      if (-not $enDisco) { $enDisco = $PSScriptRoot }
      $disco = New-Object System.IO.DriveInfo ([System.IO.Path]::GetPathRoot($enDisco))
      $gb = ([math]::Round($disco.AvailableFreeSpace / 1GB, 1)).ToString('0.0', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    catch { }
    Add-Linea "GB libres: $gb"
    Add-Linea "ajustes: $AjustesEstado"
  }

  # ----------------------------------- 2 -----------------------------------
  Invoke-Bloque 2 'bancos' 30 {
    $fallan = @()
    foreach ($b in @('probar')) {
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
      '--usage-output-file'      = @('--usage-output-file=' + (Join-Path $Tmp 'uso-sonda.json'))
    }
    foreach ($k in $sondas.Keys) { Add-Linea ("bandera ${k}: " + (Get-EstadoBandera @($sondas[$k]))) }
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
    if ($ModeloElegido) { Add-Linea ('modelo: ' + (Get-Seguro $ModeloElegido)) } else { Add-Linea 'modelo: el de Copilot' }
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
    $elegido = Get-MavenElegido
    Add-Linea ('maven usado: ' + $elegido.Origen)
    if ($elegido.Origen -eq 'ninguno') { Add-Linea 'saltado: no hay Maven (ni en los ajustes, ni mvn en el PATH, ni mvnw en -Migrado)'; return }
    $dir = Join-Path $Tmp 'juguete'
    Copy-Item -LiteralPath (Join-Path (Join-Path $PSScriptRoot 'preflight') 'juguete') -Destination $dir -Recurse
    $mvn = Get-MvnProyecto $elegido $dir
    $jacoco = $Cfg.JacocoPlugin
    $rewrite = 'org.openrewrite.maven:rewrite-maven-plugin:6.46.1'
    $r = Invoke-Proceso $mvn @('-B', 'test') $dir 1500
    $script:MavenBien = (-not $r.Agotado -and $r.Codigo -eq 0)
    Add-PasoMaven 'compila y pasa el test' $script:MavenBien $r.Segundos (Get-ErrorMaven $r.Texto)
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
    # SpotBugs (con fb-contrib) y PMD por coordenadas, como el paso sonar de rescate.ps1: si no se descargan es un aviso, no un fallo
    $reloj = [System.Diagnostics.Stopwatch]::StartNew()
    $a = Invoke-Analisis $dir
    Add-Linea ('spotbugs y pmd: ' + (Get-SiNo ($a.Estado -ceq 'ok')) + " | $([int]$reloj.Elapsed.TotalSeconds) s")
    if ($a.Estado -cne 'ok') {
      Add-Linea ('aviso: ' + (Get-Seguro ($a.Estado -replace '^no disponible: ', '')) + '; el paso sonar funcionara sin ellos')
      if ($a.Detalle) { Add-Linea ('detalle: ' + (Get-Seguro $a.Detalle)) }
    }
  }

  # ----------------------------------- 7 -----------------------------------
  Invoke-Bloque 7 'forma de los repos' 30 {
    if (-not $Legacy -and -not $Migrado -and -not $Plantilla) { Add-Linea 'saltado: sin repos (-Legacy, -Migrado, -Plantilla)'; return }
    $repos = @()
    if ($Legacy) {
      $raiz = Resolve-Dir $Legacy
      $repos += , @('original', $raiz)
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
      $raizPar = Resolve-Dir $par[1]
      $repos += , @($par[0], $raizPar)
      $f = Get-FormaRepo $raizPar
      Add-Linea ("$($par[0]) ficheros java: $($f.Ficheros) | lineas: $($f.Lineas) | modulos: $($f.Modulos)")
    }
    foreach ($r in $repos) { Add-DatosRepo $r[0] $r[1] }
    if ($SinMaven) { Add-Linea 'diagnostico: saltado (-SinMaven)'; return }
    if (-not $Migrado -or -not $Plantilla) { Add-Linea 'diagnostico: saltado (faltan -Migrado y -Plantilla)'; return }
    # El diagnostico va sobre un clon temporal del migrado, no sobre la carpeta de la persona: rescate.ps1 escribe .rescate/ y
    # .git/info/exclude, y su Maven pasa Remove-Ruido (git clean y git checkout) mientras ella sigue trabajando en su IDE.
    # El nombre es corto por el limite de 260 caracteres de las rutas de Windows. Se borra siempre (finally).
    $raizMigrado = Resolve-Dir $Migrado
    $clon = Join-Path ([System.IO.Path]::GetTempPath()) ('pf-' + [System.Guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
      $c = Invoke-Nativo 'git' @('clone', '--quiet', '--no-hardlinks', $raizMigrado, $clon)
      if ($c.Codigo -ne 0) {
        $motivo = @($c.Salida | Where-Object { "$_" -match '^(fatal|error):' } | Select-Object -First 1)
        if ($motivo.Count -eq 0) { $motivo = @($c.Salida | Where-Object { "$_".Trim() } | Select-Object -First 1) }
        Add-Linea ('diagnostico: no se pudo clonar el migrado: ' + (Get-Seguro "$($motivo -join '')"))
        return
      }
      # lo que la persona ha puesto en su .rescate/config.json (Maven, reglas) manda tambien en la copia
      $configMigrado = Join-Path (Join-Path $raizMigrado '.rescate') 'config.json'
      if (Test-Path -LiteralPath $configMigrado) {
        $rescateClon = New-Carpeta (Join-Path $clon '.rescate')
        Copy-Item -LiteralPath $configMigrado -Destination $rescateClon
      }
      $a = Get-ArgsPowerShell @((Join-Path $PSScriptRoot 'rescate.ps1'), '-Repo', $clon, '-Plantilla', (Resolve-Dir $Plantilla), '-SinWorktree')
      $r = Invoke-Proceso (Get-PowerShellExe) $a $PSScriptRoot ([int][Math]::Ceiling([double]$Cfg.MinutosDiagnostico * 60))
      if ($r.Agotado) { Add-Linea 'diagnostico: tiempo agotado'; return }
      Add-Linea "diagnostico: codigo $($r.Codigo) en $($r.Segundos) s | del ultimo commit, sin los cambios sin commitear"
      $t = [regex]::Replace($r.Texto, '\x1b\[[0-9;]*m', '')
      foreach ($m in [regex]::Matches($t, '(?m)^([a-z0-9]+)\s+(\d+)\s+(\d+)\s*$')) {
        Add-Linea ("$($m.Groups[1].Value): $($m.Groups[2].Value) errores, $($m.Groups[3].Value) avisos")
      }
      # cuanto incumple la propia referencia (lo que ella hace se permite en el migrado): solo digitos
      $ref = [regex]::Match($t, '(?m)^Plantilla incumple: capas ([0-9]+) \| ficheros ([0-9]+) \| calidad ([0-9]+) \| secretos ([0-9]+)\s*$')
      if ($ref.Success) { Add-Linea "plantilla incumple: capas $($ref.Groups[1].Value) | ficheros $($ref.Groups[2].Value) | calidad $($ref.Groups[3].Value) | secretos $($ref.Groups[4].Value)" }
      else { Add-Linea 'plantilla incumple: desconocido' }
    }
    finally {
      # los objetos de .git son de solo lectura en Windows: -Force. Si no se puede, la linea dice cual es (sin ruta: lleva el usuario)
      try { Remove-Item -LiteralPath $clon -Recurse -Force -ErrorAction Stop }
      catch { if (Test-Path -LiteralPath $clon) { Add-Linea ('diagnostico: no se pudo borrar la copia temporal; borra a mano la carpeta ' + (Split-Path $clon -Leaf) + ' de la carpeta temporal del sistema (TEMP)') } }
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

  # ----------------------------------- 9 -----------------------------------
  # El plan se hace antes: la cabecera del bloque dice cuantos minutos puede durar
  $plan = [pscustomobject]@{ Trozos = @(); ConMaven = $false; Llamadas = 0; Minutos = 1 }
  if (($SoloN.Count -eq 0 -or $SoloN -contains 9) -and $ModelosN.Count -gt 0 -and -not $SinCopilot) {
    try { $plan = Get-PlanExamen } catch { }
  }
  Invoke-Bloque 9 'examen de modelos' $plan.Minutos {
    if ($ModelosN.Count -eq 0) { Add-Linea 'sin -Modelos'; return }
    if ($SinCopilot) { Add-Linea 'saltado: -SinCopilot'; return }
    if ($plan.Trozos.Count -eq 0) { throw 'no se pudo preparar el examen' }
    $bandera = Get-EstadoBandera @('--usage-output-file=' + (Join-Path $Tmp 'uso-sonda.json'))
    Add-Linea "bandera de uso: $bandera"
    Write-Host "$($plan.Llamadas) llamadas, hasta $($plan.Minutos) min"
    $claves = Read-Json (Join-Ruta $PSScriptRoot 'preflight/examen/claves.json')
    $combos = @()
    $campos = New-Object System.Collections.Generic.List[string]
    $k = 0
    foreach ($m in $ModelosN) {
      foreach ($e in $EsfuerzosN) {
        $k++
        $vista = Get-Seguro $m
        Add-Linea "modelo $vista | esfuerzo $e"
        $c = Invoke-Combinacion $k $m $vista $e ($bandera -eq 'si') $claves $plan
        Save-ResultadoPreflight
        # un modelo que no existe se salta entero: sus otros esfuerzos no se prueban
        if ($c.SinModelo) { break }
        $combos += $c
        foreach ($u in $c.Usos) { foreach ($campo in $u.Campos) { if ($campo -match '^[A-Za-z]{1,40}$' -and -not $campos.Contains($campo) -and $campos.Count -lt 30) { $campos.Add($campo) } } }
      }
    }
    if ($campos.Count -gt 0) { Add-Linea ('campos de uso: ' + ($campos -join ', ')) } else { Add-Linea 'campos de uso: ninguno' }
    foreach ($l in (Get-Recomendacion $combos)) { Add-Linea $l }
  }
}
finally {
  # ---------------------------------- fin ----------------------------------
  Add-Linea '== fin'
  $conFallo = 'ninguno'
  if ($script:Fallos.Count -gt 0) { $conFallo = ($script:Fallos -join ' ') }
  Add-Linea "bloques con fallo: $conFallo"
  Add-Linea ('duracion: ' + [int]((Get-Date) - $Inicio).TotalMinutes + ' min')
  Save-ResultadoPreflight
  [void](Set-Despierto $false)
  try { Remove-Item -LiteralPath $Tmp -Recurse -Force } catch { }
  Write-Host ''
  foreach ($l in $script:Lineas) { Write-Host $l }
  $copiado = $false
  if ($env:OS -eq 'Windows_NT') {
    try { Set-Clipboard -Value ($script:Lineas -join "`r`n"); $copiado = $true } catch { }
  }
  Write-Host ''
  Write-Host 'Resultado en preflight-resultado.txt, junto al script.'
  Write-Host ('Copiado al portapapeles: ' + (Get-SiNo $copiado))
}
if ($script:NoEscribe) { exit 1 }
exit 0
