<#
analisis.ps1 - Mide las buenas practicas de un repo Java con analizadores reales y sin servidor: SpotBugs con fb-contrib
(los mismos motores que salen en el Sonar del equipo) y PMD (con un ruleset corto, analisis\pmd-sonar.xml). No se ejecuta
solo: solo funciones. Se carga con '. (Join-Path $PSScriptRoot 'analisis.ps1')' despues de comun.ps1, que pone $Cfg, $Utf8,
Invoke-MavenTope, Join-Ruta y Aviso. Solo ASCII. Vale para Windows PowerShell 5.1 y para PowerShell 7.

  Invoke-Analisis <repo> [ficheros]   Maven con tope: compila, copia el jar de fb-contrib y lanza SpotBugs; despues PMD.
                                      Devuelve @{ Estado; Hallazgos; Detalle }. Estado es 'ok' o 'no disponible: <motivo>'
                                      (no compila, no se descarga el plugin, tope...); nunca lanza una excepcion.
                                      Cada hallazgo: @{ Herramienta; Regla; Fichero; Linea; Metodo; Clase; Mensaje }.
                                      Con ficheros (rutas relativas al repo) solo analiza esas clases y esos ficheros.
  Read-SpotbugsXml, Read-PmdXml       Leen los XML que dejan los plugins en target\.
  Compare-Analisis <antes> <despues>  @{ Nuevos; Resueltos }: sin mirar la linea (las lineas se mueven).

Los comandos de Maven, por coordenadas y sin tocar el pom del repo:
  mvn -B compile <DependencyPlugin>:copy -Dartifact=<FbContrib> -DoutputDirectory=<repo>/target/analisis/plugins
      <SpotbugsPlugin>:spotbugs -Dspotbugs.pluginList=<jar de fb-contrib> -Dspotbugs.xmlOutput=true
      -Dspotbugs.failOnError=false [-Dspotbugs.onlyAnalyze=<clases>]
  mvn -B -f analisis/pom-pmd.xml -Danalisis.repo=<repo> -Danalisis.ruleset=<pmd-sonar.xml> -Danalisis.pmd=<version>
      [-Danalisis.includes=<ficheros>] <PmdPlugin>:pmd
Por que dos formas: spotbugs-maven-plugin tiene propiedad de usuario (-D) para lo que hace falta, pero 'plugins' (fb-contrib) no
la tiene, y por eso se copia el jar y se pasa en spotbugs.pluginList. maven-pmd-plugin no la tiene ni para 'rulesets' ni para
'includes': el pom auxiliar analisis\pom-pmd.xml los toma de propiedades -D y no se toca el pom del repo.
#>

# ============================ CONFIGURACION ============================
# Las coordenadas son las mismas que prueba el preflight. Los ajustes las pisan.
$Cfg += @{
  SpotbugsPlugin   = 'com.github.spotbugs:spotbugs-maven-plugin:4.10.5.0'
  FbContrib        = 'com.mebigfatguy.fb-contrib:fb-contrib:7.7.4'
  PmdPlugin        = 'org.apache.maven.plugins:maven-pmd-plugin:3.28.0'
  DependencyPlugin = 'org.apache.maven.plugins:maven-dependency-plugin:3.8.1'   # solo copia el jar de fb-contrib
  PmdReglas        = (Join-Path $PSScriptRoot 'analisis/pmd-sonar.xml')
  PmdPom           = (Join-Path $PSScriptRoot 'analisis/pom-pmd.xml')
}

# ================================ RUTAS ================================
function ConvertTo-RutaBarra([string]$Ruta) { return (($Ruta -replace '\\', '/').TrimEnd('/')) }

# La ruta relativa al repo y con '/', o la misma ruta (con '/') si no cuelga de el.
function Get-RelRepo([string]$Repo, [string]$Ruta) {
  $r = ConvertTo-RutaBarra $Repo
  $x = ConvertTo-RutaBarra $Ruta
  if ($x.StartsWith($r + '/', [System.StringComparison]::OrdinalIgnoreCase)) { return $x.Substring($r.Length + 1) }
  return $x
}

# De los ficheros pedidos, los .java de src/main/java (con '/', sin repetidos). Lo demas no lo miran estos analizadores.
function Get-FicherosMain([string[]]$Ficheros) {
  $res = @()
  foreach ($f in @($Ficheros)) {
    $x = ConvertTo-RutaBarra "$f"
    if ($x -match '(^|/)src/main/java/.+\.java$' -and $res -cnotcontains $x) { $res += $x }
  }
  return $res
}

# Las clases de un .java de main para -Dspotbugs.onlyAnalyze: la suya y sus anidadas (Foo$Bar), que solo entran si se
# nombran una a una. Las anidadas se sacan de target/classes del modulo: lo que ya compilo Maven.
function Get-ClasesAnalisis([string]$Repo, [string]$Rel) {
  $m = [regex]::Match($Rel, '^(?<modulo>(?:.*/)?)src/main/java/(?<fuente>.+)\.java$')
  if (-not $m.Success) { return @() }
  $fuente = $m.Groups['fuente'].Value
  $paquete = ''
  $base = $fuente
  if ($fuente.Contains('/')) {
    $paquete = $fuente.Substring(0, $fuente.LastIndexOf('/')).Replace('/', '.') + '.'
    $base = $fuente.Substring($fuente.LastIndexOf('/') + 1)
  }
  $clases = @($paquete + $base)
  $carpeta = Join-Ruta $Repo ($m.Groups['modulo'].Value + 'target/classes/' + $fuente.Substring(0, $fuente.Length - $base.Length))
  if (Test-Path -LiteralPath $carpeta -PathType Container) {
    foreach ($c in @(Get-ChildItem -LiteralPath $carpeta -File -Filter ($base + '$*.class') | Sort-Object Name)) { $clases += ($paquete + $c.BaseName) }
  }
  return $clases
}

# ============================== LEER LOS XML ==============================
function New-Hallazgo([string]$Herramienta, [string]$Regla, [string]$Fichero, [int]$Linea, [string]$Metodo, [string]$Clase, [string]$Mensaje) {
  return @{ Herramienta = $Herramienta; Regla = $Regla; Fichero = $Fichero; Linea = $Linea; Metodo = $Metodo; Clase = $Clase; Mensaje = $Mensaje }
}

function ConvertTo-Linea([string]$Texto) {
  $n = 0
  if ([int]::TryParse($Texto, [ref]$n)) { return $n }
  return 0
}

# Los hallazgos de target/spotbugsXml.xml (SpotBugs con -Dspotbugs.xmlOutput=true: lleva los mensajes). Fichero sale de la
# carpeta de fuentes del XML (SrcDir, la que no es de target) y el sourcepath de la clase; Metodo es el metodo principal
# (vacio en los fallos de un campo o de una clase, que dan Clase); Mensaje es el LongMessage, el que ensena Sonar.
function Read-SpotbugsXml([string]$Ruta, [string]$Repo) {
  $doc = New-Object System.Xml.XmlDocument
  $doc.Load($Ruta)
  $fuente = ''
  foreach ($s in @($doc.SelectNodes('/BugCollection/Project/SrcDir'))) {
    $d = ConvertTo-RutaBarra $s.InnerText
    if ($d -notmatch '/target/') { $fuente = $d; break }
  }
  $res = @()
  foreach ($b in @($doc.SelectNodes('/BugCollection/BugInstance'))) {
    $clase = $b.SelectSingleNode('Class[@primary="true"]')
    if ($null -eq $clase) { $clase = $b.SelectSingleNode('Class') }
    $metodo = $b.SelectSingleNode('Method[@primary="true"]')
    $linea = $b.SelectSingleNode('SourceLine[@primary="true"]')
    $nombreClase = ''
    $camino = ''
    if ($null -ne $clase) {
      $nombreClase = $clase.GetAttribute('classname')
      $sl = $clase.SelectSingleNode('SourceLine')
      if ($null -ne $sl) { $camino = $sl.GetAttribute('sourcepath') }
    }
    $fichero = $camino
    if ($fuente -and $camino) { $fichero = Get-RelRepo $Repo ($fuente + '/' + $camino) }
    $nombreMetodo = ''
    if ($null -ne $metodo) { $nombreMetodo = $metodo.GetAttribute('name') }
    $n = 0
    if ($null -ne $linea) { $n = ConvertTo-Linea $linea.GetAttribute('start') }
    $texto = $b.SelectSingleNode('LongMessage')
    if ($null -eq $texto) { $texto = $b.SelectSingleNode('ShortMessage') }
    $mensaje = ''
    if ($null -ne $texto) { $mensaje = $texto.InnerText.Trim() }
    $res += , (New-Hallazgo 'spotbugs' $b.GetAttribute('type') $fichero $n $nombreMetodo $nombreClase $mensaje)
  }
  return $res
}

# Los hallazgos de target/pmd.xml (PMD con format xml). Metodo viene en el atributo method de la violacion (vacio en un
# campo o una clase); Mensaje es su texto.
function Read-PmdXml([string]$Ruta, [string]$Repo) {
  $doc = New-Object System.Xml.XmlDocument
  $doc.Load($Ruta)
  $res = @()
  foreach ($f in @($doc.SelectNodes("//*[local-name()='file']"))) {
    $fichero = Get-RelRepo $Repo $f.GetAttribute('name')
    foreach ($v in @($f.SelectNodes("*[local-name()='violation']"))) {
      $paquete = $v.GetAttribute('package')
      $clase = $v.GetAttribute('class')
      if ($paquete -and $clase) { $clase = "$paquete.$clase" }
      $mensaje = ($v.InnerText -replace '\s+', ' ').Trim()
      $res += , (New-Hallazgo 'pmd' $v.GetAttribute('rule') $fichero (ConvertTo-Linea $v.GetAttribute('beginline')) $v.GetAttribute('method') $clase $mensaje)
    }
  }
  return $res
}

# ============================== COMPARAR ==============================
# Herramienta, regla y fichero, y el metodo (o la clase si no hay metodo). La linea no entra: las lineas se mueven.
function Get-ClaveHallazgo($H) {
  $donde = "$($H.Metodo)"
  if (-not $donde) { $donde = "$($H.Clase)" }
  return ((@("$($H.Herramienta)", "$($H.Regla)", "$($H.Fichero)", $donde)) -join '|')
}

# Los hallazgos de una lista, agrupados por clave (en el orden en que salen).
function Group-Hallazgos($Lista) {
  $g = [ordered]@{}
  foreach ($h in @($Lista)) {
    if ($null -eq $h) { continue }
    $k = Get-ClaveHallazgo $h
    if (-not $g.Contains($k)) { $g[$k] = @() }
    $g[$k] = @($g[$k]) + , $h
  }
  return $g
}

# Lo nuevo y lo resuelto entre dos listas de hallazgos. Con la misma clave se compara cuantos hay: los de mas despues son
# nuevos (los ultimos de la lista) y los de mas antes, resueltos.
function Compare-Analisis($Antes, $Despues) {
  $a = Group-Hallazgos $Antes
  $d = Group-Hallazgos $Despues
  $nuevos = @()
  $resueltos = @()
  foreach ($k in (@($d.Keys) + @($a.Keys | Where-Object { -not $d.Contains($_) }))) {
    $antes = @()
    $despues = @()
    if ($a.Contains($k)) { $antes = @($a[$k]) }
    if ($d.Contains($k)) { $despues = @($d[$k]) }
    if ($despues.Count -gt $antes.Count) { $nuevos += @($despues | Select-Object -Skip $antes.Count) }
    if ($antes.Count -gt $despues.Count) { $resueltos += @($antes | Select-Object -Skip $despues.Count) }
  }
  return @{ Nuevos = @($nuevos); Resueltos = @($resueltos) }
}

# ================================ MAVEN ================================
# La razon de que Maven haya fallado, en pocas palabras, y el primer [ERROR] como detalle.
function Get-MotivoMaven($R) {
  $texto = (@($R.Salida) -join "`n")
  $motivo = "Maven ha salido con error (codigo $($R.Codigo))"
  if ($texto -match 'COMPILATION ERROR|Compilation failure') { $motivo = 'no compila' }
  elseif ($texto -match 'could not be resolved|Could not (resolve|transfer|find artifact)|Failed to read artifact descriptor|PluginResolutionException|Non-resolvable') {
    if ($texto -match 'spotbugs|fb-contrib|maven-pmd-plugin|maven-dependency-plugin|net\.sourceforge\.pmd') { $motivo = 'no se descarga el plugin' }
    else { $motivo = 'no se descargan las dependencias del proyecto' }
  }
  $detalle = ''
  $e = @(@($R.Salida) | Where-Object { "$_" -match '^\[ERROR\]\s*\S' } | Select-Object -First 1)
  if ($e.Count -gt 0) { $detalle = ("$($e[0])" -replace '^\[ERROR\]\s*', '').Trim() }
  return [pscustomobject]@{ Motivo = $motivo; Detalle = $detalle }
}

# Una llamada a Maven con tope. Devuelve $null si salio bien, o el Motivo y el Detalle de lo que paso.
function Invoke-PasoAnalisis([string]$Repo, [string[]]$A, [string]$Que, [string]$Registro) {
  try { $r = Invoke-MavenTope $Repo $A $Que $Registro }
  catch { return [pscustomobject]@{ Motivo = 'no se puede lanzar Maven'; Detalle = $_.Exception.Message } }
  if ($r.Tope) { return [pscustomobject]@{ Motivo = 'tope'; Detalle = $r.Tope } }
  if ($r.Codigo -ne 0) { return (Get-MotivoMaven $r) }
  return $null
}

# Los XML de un nombre que hay en las carpetas target del repo.
function Get-XmlAnalisis([string]$Repo, [string]$Nombre) {
  return @(Get-ChildItem -LiteralPath $Repo -Recurse -File -Filter $Nombre -ErrorAction SilentlyContinue | Where-Object { (Split-Path $_.DirectoryName -Leaf) -ceq 'target' })
}

# ============================== ANALISIS ==============================
# Analiza $Repo (con $Ficheros, solo esos .java de src/main/java). Ver la cabecera. Con un Estado distinto de 'ok' no hay
# hallazgos: una medida a medias no sirve para comparar antes y despues.
function Invoke-Analisis([string]$Repo, [string[]]$Ficheros = @()) {
  $res = @{ Estado = 'ok'; Hallazgos = @(); Detalle = '' }
  try {
    if (-not $Repo -or -not (Test-Path -LiteralPath $Repo -PathType Container)) { $res.Estado = 'no disponible: la carpeta no existe'; return $res }
    $Repo = (Resolve-Path -LiteralPath $Repo).Path.TrimEnd('\', '/')
    $pedidos = @()
    if (@($Ficheros).Count -gt 0) {
      $pedidos = @(Get-FicherosMain $Ficheros)
      if ($pedidos.Count -eq 0) { return $res }   # ni un .java de main: no hay nada que medir
    }
    $dirA = Join-Ruta $Repo 'target/analisis'
    [void](New-Item -ItemType Directory -Path $dirA -Force)
    foreach ($n in @('spotbugsXml.xml', 'pmd.xml')) { foreach ($x in @(Get-XmlAnalisis $Repo $n)) { Remove-Item -LiteralPath $x.FullName -Force } }

    # 1. compilar, copiar fb-contrib y SpotBugs
    $fb = @($Cfg.FbContrib -split ':')
    $jar = Join-Ruta $dirA ('plugins/' + $fb[1] + '-' + $fb[2] + '.jar')
    $a = @('-B', 'compile', "$($Cfg.DependencyPlugin):copy", "-Dartifact=$($Cfg.FbContrib)", ('-DoutputDirectory=' + (Join-Ruta $dirA 'plugins')),
      "$($Cfg.SpotbugsPlugin):spotbugs", "-Dspotbugs.pluginList=$jar", '-Dspotbugs.xmlOutput=true', '-Dspotbugs.failOnError=false')
    if ($pedidos.Count -gt 0) {
      $clases = @()
      foreach ($f in $pedidos) { $clases += @(Get-ClasesAnalisis $Repo $f) }
      $a += ('-Dspotbugs.onlyAnalyze=' + ($clases -join ','))
    }
    $fallo = Invoke-PasoAnalisis $Repo $a 'Maven (SpotBugs)' (Join-Path $dirA 'spotbugs.log')
    if ($null -ne $fallo) { $res.Estado = 'no disponible: ' + $fallo.Motivo; $res.Detalle = $fallo.Detalle; return $res }
    $xmlSpotbugs = @(Get-XmlAnalisis $Repo 'spotbugsXml.xml')
    if ($xmlSpotbugs.Count -eq 0) { $res.Estado = 'no disponible: SpotBugs no ha dejado spotbugsXml.xml'; return $res }

    # 2. PMD, con su pom auxiliar (el ruleset y los ficheros no se pueden pasar de otra forma)
    $p = @('-B', '-f', $Cfg.PmdPom, "-Danalisis.repo=$Repo", "-Danalisis.ruleset=$($Cfg.PmdReglas)", ('-Danalisis.pmd=' + @($Cfg.PmdPlugin -split ':')[2]))
    if ($pedidos.Count -gt 0) { $p += ('-Danalisis.includes=' + ($pedidos -join ',')) }
    $p += "$($Cfg.PmdPlugin):pmd"
    $fallo = Invoke-PasoAnalisis $Repo $p 'Maven (PMD)' (Join-Path $dirA 'pmd.log')
    if ($null -ne $fallo) { $res.Estado = 'no disponible: ' + $fallo.Motivo; $res.Detalle = $fallo.Detalle; return $res }
    $xmlPmd = Join-Ruta $Repo 'target/pmd.xml'
    if (-not (Test-Path -LiteralPath $xmlPmd)) { $res.Estado = 'no disponible: PMD no ha dejado pmd.xml'; return $res }

    $todos = @()
    foreach ($x in $xmlSpotbugs) { $todos += @(Read-SpotbugsXml $x.FullName $Repo) }
    $todos += @(Read-PmdXml $xmlPmd $Repo)
    if ($pedidos.Count -gt 0) { $todos = @($todos | Where-Object { $pedidos -contains $_.Fichero }) }
    $res.Hallazgos = @($todos)
    return $res
  }
  catch {
    return @{ Estado = ('no disponible: ' + $_.Exception.Message); Hallazgos = @(); Detalle = '' }
  }
}
