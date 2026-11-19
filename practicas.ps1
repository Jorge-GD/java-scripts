<#
practicas.ps1 - Mide las buenas practicas del repo migrado, sin IA, y deja datos\practicas-<Cuando>.json (el formato esta en
BP-datos.md). No se ejecuta solo: solo funciones. Se carga con '. (Join-Path $PSScriptRoot 'practicas.ps1')' despues de comun.ps1,
tareas.ps1 (Write-Json, Read-Json, Get-Hash8) y analisis.ps1 (Invoke-Analisis, Get-RelRepo). Solo ASCII. Vale para Windows
PowerShell 5.1 y para PowerShell 7.

  Invoke-Practicas <repo> <referencia> <cuando> <datos> <registros> <hallazgos del motor>
      Mide el repo migrado con 6 detectores y escribe <datos>\practicas-<cuando>.json y <registros>\practicas-<cuando>.log
      (la salida de Maven de javac y, al final, un resumen). Nunca lanza una excepcion ni para el diagnostico: un detector que falla
      queda en 'no se pudo medir' con su motivo y los demas siguen. El JSON se escribe siempre.
        javac            mvn -B compile (sin -q ni clean; antes se borran solo target\classes y target\maven-status). Cada
                         '[WARNING] <fichero>.java:[<linea>,<col>] ... marked for removal' es una incidencia S5738 (area
                         boot3-batch5 si el tipo es org.springframework.*, java21 si no). 100 avisos justos: corte (javac para ahi).
        lombok-a-mano    Solo si la referencia usa Lombok. javap -c -l -p (en lotes) sobre target\classes: getters y setters
                         triviales que ademas estan escritos en el .java (los que genera Lombok solo estan en el .class).
        lombok-qualifier Solo leyendo el codigo: clase con @RequiredArgsConstructor o @AllArgsConstructor y un campo con @Qualifier
                         o @Value sin 'lombok.copyableAnnotations +=' de esa anotacion en ningun lombok.config (carpeta y ancestros).
        pmd, spotbugs    Invoke-Analisis (analisis.ps1). Las claves de Sonar de PMD salen de analisis\pmd-sonar.xml.
        java21-texto     Solo leyendo el codigo de src\main\java, sin comentarios: lo que cambia de texto en Java 21. charset-por-defecto
                         (JEP 400, Java 18: el juego de caracteres por defecto pasa a UTF-8) y formato-cldr (Java 9: los nombres de mes y
                         dia y los separadores de numeros salen de CLDR). Solo avisa donde mirar; el arreglo depende del servidor.
  Tope: $Cfg.SegundosPracticas en total. Orden: javac, Lombok y, al final, Invoke-Analisis con lo que quede; si quedan menos de
  $Cfg.SegundosMinAnalisis s, pmd y spotbugs quedan en 'no medido (tope)'.
  Cache: la clave es el HEAD del migrado mas su git status --porcelain (sin target, .rescate ni migracion-*) y la huella de cada fichero
  cambiado; si el JSON de ese <cuando> ya tiene la misma clave, no se mide.
  queHago de cada incidencia: paso2 si el motor ya dice ese fichero y esa linea en sus hallazgos; si no, sonar (origen sonar o
  spotbugs) o mano (origen referencia). 'notoca' es de BP-1.
#>

# ============================ CONFIGURACION ============================
$Cfg += @{
  SegundosPracticas   = 300    # tope de toda la medida
  SegundosMinAnalisis = 30     # con menos segundos que estos, PMD y SpotBugs no se lanzan
  JavapExe            = ''     # javap; vacio = el de JAVA_HOME
  LineaMaxJavap       = 7500   # caracteres de argumentos de cada llamada a javap (Windows corta la linea de comandos en 8.191)
  SonarReglasWay      = 608    # reglas del perfil Sonar way de Java: cita [c7] de buenas-practicas/PROPUESTA-fable.md
}

# ============================== UTILIDADES ==============================
function New-Incidencia([string]$Area, [string]$Fichero, [int]$Linea, [string]$Herramienta, [string]$Regla, [string]$Origen, [string]$Sonar, [string]$Texto) {
  if ($Texto.Length -gt 300) { $Texto = $Texto.Substring(0, 300) }
  return [ordered]@{ area = $Area; fichero = $Fichero; linea = $Linea; herramienta = $Herramienta; regla = $Regla; origen = $Origen; sonar = $Sonar; texto = $Texto; queHago = '' }
}

# Corre un detector: $Cuerpo devuelve @{ Estado; Motivo; Corte; Incidencias } (lo que falte se queda en ok, '', false, ninguna). Si lanza una
# excepcion, el detector queda en 'no se pudo medir' con su mensaje. Devuelve el detector tal como va al JSON y sus incidencias.
function Measure-Detector([string]$Id, [scriptblock]$Cuerpo, [double]$Segundos = -1) {
  $reloj = [System.Diagnostics.Stopwatch]::StartNew()
  $r = @{ Estado = 'ok'; Motivo = ''; Corte = $false; Incidencias = @() }
  try {
    $x = & $Cuerpo
    foreach ($k in @($x.Keys)) { $r[$k] = $x[$k] }
  }
  catch { $r = @{ Estado = 'no se pudo medir'; Motivo = $_.Exception.Message; Corte = $false; Incidencias = @() } }
  if ($Segundos -lt 0) { $Segundos = $reloj.Elapsed.TotalSeconds }
  $d = [ordered]@{ id = $Id; estado = $r.Estado; motivo = "$($r.Motivo)"; segundos = [Math]::Round($Segundos, 1); corte = [bool]$r.Corte }
  return [pscustomobject]@{ Detector = $d; Incidencias = @($r.Incidencias) }
}

function Get-Quedan([datetime]$Fin) { return ($Fin - (Get-Date)).TotalSeconds }

# Corre $Cuerpo con el tope de Maven ($Cfg.MinutosMaven) en lo que queda de tiempo (al menos 1 s) y lo deja como estaba.
function Invoke-ConTope([double]$Segundos, [scriptblock]$Cuerpo) {
  $minutosAntes = $Cfg.MinutosMaven
  $Cfg.MinutosMaven = [Math]::Max($Segundos, 1) / 60
  try { return (& $Cuerpo) }
  finally { $Cfg.MinutosMaven = $minutosAntes }
}

# Las claves de Sonar de pmd-sonar.xml: nombre de la regla de PMD -> 'S1234'. Cada regla lleva en la linea de encima un comentario
# '<!-- java:S1234 ... -->'. Ese fichero es la fuente; no se copia la lista a otro sitio.
function Get-ClavesSonar {
  $claves = @{}
  $actual = ''
  foreach ($l in [System.IO.File]::ReadAllLines($Cfg.PmdReglas)) {
    if ($l -match '<!--\s*java:(S\d+)\b') { $actual = $Matches[1]; continue }
    if ($l -match '<rule\s+ref="[^"]*/(\w+)"') {
      if ($actual) { $claves[$Matches[1]] = $actual }
      $actual = ''
    }
  }
  return $claves
}

# El paquete comun a todos los .java de src/main/java (por sus carpetas), o '' si no hay.
function Get-PaqueteBase([string]$Repo) {
  $base = $null
  foreach ($f in @(Get-JavaFiles $Repo)) {
    $m = [regex]::Match((Get-RelRepo $Repo $f.FullName), '(^|/)src/main/java/(?<d>.+)/[^/]+\.java$')
    if (-not $m.Success) { continue }
    $p = $m.Groups['d'].Value.Split('/')
    if ($null -eq $base) { $base = $p; continue }
    $n = 0
    while ($n -lt $base.Count -and $n -lt $p.Count -and $base[$n] -ceq $p[$n]) { $n++ }
    $base = @($base | Select-Object -First $n)
  }
  if ($null -eq $base) { return '' }
  return (@($base) -join '.')
}

# La clave de la cache: el HEAD y los cambios sin confirmar del migrado. Sin target, .rescate ni migracion-* (cambian solos), y con la huella
# (tamano y fecha) de cada fichero cambiado: el mismo fichero editado dos veces da el mismo status.
function Get-ClavePracticas([string]$Repo) {
  $cambios = @()
  $st = Invoke-Git $Repo @('-c', 'core.quotepath=off', 'status', '--porcelain', '--untracked-files=all')
  foreach ($l in @($st.Salida)) {
    if ("$l".Length -le 3) { continue }
    $ruta = "$l".Substring(3).Trim('"')
    if ($ruta -match '(^|/)target/' -or $ruta -match '^\.rescate(/|$)' -or $ruta -match '^migracion-[^/]*(/|$)') { continue }
    $huella = ''
    $f = Join-Ruta $Repo $ruta
    if (Test-Path -LiteralPath $f -PathType Leaf) { $i = Get-Item -LiteralPath $f; $huella = "$($i.Length):$($i.LastWriteTimeUtc.Ticks)" }
    $cambios += ("$l".Substring(0, 2) + ' ' + $ruta + ' ' + $huella)
  }
  return (Get-Hash8 ((Get-Head $Repo) + "`n" + ((@($cambios) | Sort-Object) -join "`n")))
}

# ================================ JAVAC ================================
# De la salida de Maven: Crudos (los avisos '[WARNING] <fichero>.java:[l,c] ...', de cualquier tipo: javac para en 100) e Incidencias (los
# 'marked for removal', sin repetidos: javac repite el mismo aviso).
function Read-AvisosJavac([string[]]$Salida, [string]$Repo) {
  $crudos = 0
  $inc = @()
  $vistos = @{}
  foreach ($l in @($Salida)) {
    $m = [regex]::Match("$l", '^\[WARNING\]\s+(?<f>.+?\.java):\[(?<l>\d+),\d+\]\s+(?<t>.*)$')
    if (-not $m.Success) { continue }
    $crudos++
    $texto = $m.Groups['t'].Value.Trim()
    if ($texto -notmatch 'marked for removal') { continue }
    $fichero = Get-RelRepo $Repo $m.Groups['f'].Value
    $linea = [int]$m.Groups['l'].Value
    $k = "$fichero|$linea|$texto"
    if ($vistos.ContainsKey($k)) { continue }
    $vistos[$k] = $true
    # el tipo es lo que va detras de ' in ': 'Integer(int) in java.lang.Integer has been deprecated and marked for removal'
    $area = 'java21'
    $t = [regex]::Match($texto, '\bin (\S+) has been deprecated and marked for removal')
    if ($t.Success -and $t.Groups[1].Value.StartsWith('org.springframework.')) { $area = 'boot3-batch5' }
    $inc += , (New-Incidencia $area $fichero $linea 'javac' 'removal' 'sonar' 'S5738' $texto)
  }
  return [pscustomobject]@{ Crudos = $crudos; Incidencias = $inc }
}

# Compila sin clean (E8: solo se borran target\classes y target\maven-status) y lee los avisos. La salida de Maven queda en $Registro.
function Get-ResultadoJavac([string]$Repo, [string]$Registro, [datetime]$Fin) {
  foreach ($d in @('target/classes', 'target/maven-status')) {
    $p = Join-Ruta $Repo $d
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force }
  }
  $mvn = Invoke-ConTope (Get-Quedan $Fin) { Invoke-MavenTope $Repo @('-B', 'compile') 'Maven (javac)' $Registro }
  if ($mvn.Tope) { return @{ Estado = 'no medido (tope)' } }
  if ($mvn.Codigo -ne 0) {
    # la primera linea [ERROR] con informacion: 'COMPILATION ERROR :' solo es el titulo
    $e = @(@($mvn.Salida) | Where-Object { "$_" -match '^\[ERROR\]\s*(?!COMPILATION ERROR)\S' } | Select-Object -First 1)
    $motivo = "Maven ha salido con codigo $($mvn.Codigo)"
    if ($e.Count -gt 0) { $motivo = ("$($e[0])" -replace '^\[ERROR\]\s*', '').Trim() }
    return @{ Estado = 'no se pudo medir'; Motivo = $motivo }
  }
  $a = Read-AvisosJavac $mvn.Salida $Repo
  return @{ Estado = 'ok'; Corte = ($a.Crudos -eq 100); Incidencias = $a.Incidencias }
}

# ============================ LOMBOK A MANO ============================
# La referencia usa Lombok: su pom lo tiene y algun .java suyo hace 'import lombok.'.
function Test-ReferenciaLombok([string]$Referencia) {
  if (-not $Referencia -or -not (Test-Path -LiteralPath $Referencia -PathType Container)) { return $false }
  $pom = Join-Path $Referencia 'pom.xml'
  if (-not (Test-Path -LiteralPath $pom -PathType Leaf)) { return $false }
  if ([System.IO.File]::ReadAllText($pom) -notmatch 'org\.projectlombok') { return $false }
  foreach ($f in @(Get-JavaFiles $Referencia)) {
    if ([System.IO.File]::ReadAllText($f.FullName) -match '(?m)^\s*import\s+(static\s+)?lombok\.') { return $true }
  }
  return $false
}

function Get-JavapExe {
  if ($Cfg.JavapExe) { return $Cfg.JavapExe }
  if (-not $env:JAVA_HOME) { throw 'JAVA_HOME no esta definido y JavapExe esta vacio: no se sabe donde esta javap' }
  $nombre = 'javap'
  if ($env:OS -eq 'Windows_NT') { $nombre = 'javap.exe' }
  $ruta = Join-Path (Join-Path $env:JAVA_HOME 'bin') $nombre
  if (-not (Test-Path -LiteralPath $ruta)) { throw "no encuentro javap en $ruta (JAVA_HOME)" }
  return $ruta
}

# Reparte las rutas en lotes: cada uno, con sus 'ruta + 3' caracteres sumados, cabe en $Max.
function Get-LotesJavap([string[]]$Rutas, [int]$Max) {
  $lotes = @()
  $lote = @()
  $largo = 0
  foreach ($r in @($Rutas)) {
    if ($lote.Count -gt 0 -and ($largo + $r.Length + 3) -gt $Max) { $lotes += , $lote; $lote = @(); $largo = 0 }
    $lote += $r
    $largo += $r.Length + 3
  }
  if ($lote.Count -gt 0) { $lotes += , $lote }
  return $lotes
}

# Anota en $Clase el metodo $Metodo si es un getter trivial (aload_0, getfield, xreturn) o un setter trivial (aload_0, xload_1, putfield, return).
function Add-Accesor($Clase, $Metodo) {
  if ($null -eq $Clase -or $null -eq $Metodo) { return }
  $ops = $Metodo.Ops -join ' '
  if ($Metodo.Args -ceq '' -and $ops -cmatch '^aload_0 getfield [ilfda]return$') { $Clase.Getters += $Metodo.Nombre }
  elseif ($Metodo.Args -cne '' -and $ops -cmatch '^aload_0 [ilfda]load_1 putfield return$') { $Clase.Setters += $Metodo.Nombre }
}

# De lo que saca 'javap -c -l -p': por clase, los nombres de sus getters y setters triviales.
function Get-AccesoresJavap([string]$Texto) {
  $res = @()
  $clase = $null
  $metodo = $null
  foreach ($l in ($Texto -split '\r?\n')) {
    if ($l.Length -lt 3) { continue }
    if ($l[0] -ne ' ') {
      $c = [regex]::Match($l, '^(?:\w+ )*(?:class|interface|enum|record) (?<n>[^\s<{]+)')
      if ($c.Success) {
        Add-Accesor $clase $metodo
        $metodo = $null
        $clase = @{ Nombre = $c.Groups['n'].Value; Getters = @(); Setters = @() }
        $res += , $clase
      }
    }
    elseif ($l[2] -ne ' ') {
      # una cabecera de metodo ('  public java.lang.String getId();'); un campo o 'static {};' cierra el metodo anterior sin abrir otro
      Add-Accesor $clase $metodo
      $metodo = $null
      $h = [regex]::Match($l, '^  (?:[\w<>\[\]?,.$ ]+ )?(?<n>[\w$]+)\((?<a>[^)]*)\)(?: throws [^;]+)?;\s*$')
      if ($h.Success) { $metodo = @{ Nombre = $h.Groups['n'].Value; Args = $h.Groups['a'].Value; Ops = @() } }
    }
    elseif ($null -ne $metodo -and $metodo.Ops.Count -lt 6) {
      $o = [regex]::Match($l, '^\s+\d+: (?<o>[a-z]\w*)')
      if ($o.Success) { $metodo.Ops += $o.Groups['o'].Value }
    }
  }
  Add-Accesor $clase $metodo
  return $res
}

# La linea (1, 2...) donde el .java declara el metodo $Nombre con cuerpo, o 0 si no lo escribe: un metodo que solo esta en el .class lo
# genera Lombok.
function Get-LineaDeclaracion([string]$Fuente, [string]$Nombre) {
  $p = '(?m)^[ \t]*(?:@\w+(?:\([^)]*\))?[ \t]+)*(?:(?:public|protected|private|static|final|synchronized)[ \t]+)*[\w<>\[\],.? ]+?[ \t]+' + [regex]::Escape($Nombre) + '[ \t]*\([^)]*\)[ \t]*(?:throws [\w., ]+)?[ \t]*\{'
  $m = [regex]::Match($Fuente, $p)
  if (-not $m.Success) { return 0 }
  return ($Fuente.Substring(0, $m.Index).Split("`n").Count)
}

function Get-ResultadoLombokAMano([string]$Repo, [string]$Referencia, [datetime]$Fin) {
  if (-not (Test-ReferenciaLombok $Referencia)) { return @{ Estado = 'no aplica'; Motivo = 'la referencia no usa Lombok' } }
  $dirClases = Join-Ruta $Repo 'target/classes'
  $clases = @()
  if (Test-Path -LiteralPath $dirClases -PathType Container) {
    $clases = @(Get-ChildItem -LiteralPath $dirClases -Recurse -File -Filter '*.class' | Where-Object { $_.Name -cne 'module-info.class' -and $_.Name -cne 'package-info.class' } | Sort-Object FullName | ForEach-Object { $_.FullName })
  }
  if ($clases.Count -eq 0) { return @{ Estado = 'no se pudo medir'; Motivo = 'no hay clases compiladas en target/classes' } }
  $javap = Get-JavapExe
  $texto = ''
  foreach ($lote in @(Get-LotesJavap $clases ([int]$Cfg.LineaMaxJavap))) {
    $p = Invoke-Proceso $javap (@('-c', '-l', '-p') + $lote) $Repo ([int][Math]::Ceiling([Math]::Max(1, (Get-Quedan $Fin))))
    if ($p.Agotado) { return @{ Estado = 'no medido (tope)' } }
    if ($p.Codigo -ne 0) {
      $primeras = (@("$($p.Texto)" -split '\r?\n' | Where-Object { $_.Trim() } | Select-Object -First 3) -join ' / ')
      return @{ Estado = 'no se pudo medir'; Motivo = "javap ha salido con codigo $($p.Codigo): $primeras" }
    }
    $texto += $p.Texto + "`n"
  }
  $inc = @()
  $fuentes = @{}
  foreach ($c in @(Get-AccesoresJavap $texto)) {
    if ($c.Getters.Count -eq 0 -and $c.Setters.Count -eq 0) { continue }
    $rel = 'src/main/java/' + (($c.Nombre -replace '\$.*$', '').Replace('.', '/')) + '.java'
    $ruta = Join-Ruta $Repo $rel
    if (-not (Test-Path -LiteralPath $ruta -PathType Leaf)) { continue }
    if (-not $fuentes.ContainsKey($ruta)) { $fuentes[$ruta] = [System.IO.File]::ReadAllText($ruta) }
    $lineas = @()
    $getters = 0
    $setters = 0
    foreach ($n in $c.Getters) { $x = Get-LineaDeclaracion $fuentes[$ruta] $n; if ($x -gt 0) { $getters++; $lineas += $x } }
    foreach ($n in $c.Setters) { $x = Get-LineaDeclaracion $fuentes[$ruta] $n; if ($x -gt 0) { $setters++; $lineas += $x } }
    if ($lineas.Count -eq 0) { continue }
    $inc += , (New-Incidencia 'lombok' $rel (@($lineas | Sort-Object)[0]) 'lombok' 'getter-setter-a-mano' 'referencia' '' "$getters getters y $setters setters escritos a mano: con Lombok son @Getter y @Setter")
  }
  return @{ Estado = 'ok'; Incidencias = $inc }
}

# ============================ LOMBOK QUALIFIER ============================
# Los FQN que los lombok.config de $Dir y de las carpetas de encima (hasta la raiz del repo) dan en 'lombok.copyableAnnotations +='.
function Get-CopiablesLombok([string]$Repo, [string]$Dir, [hashtable]$Cache) {
  $dirs = @($Repo)
  $rel = Get-RelRepo $Repo $Dir
  if ($rel -cne (ConvertTo-RutaBarra $Dir)) {
    $acum = ''
    foreach ($s in $rel.Split('/')) { if ($s) { $acum += $s + '/'; $dirs += (Join-Ruta $Repo $acum) } }
  }
  $res = @()
  foreach ($d in $dirs) {
    if (-not $Cache.ContainsKey($d)) {
      $lista = @()
      $cfg = Join-Path $d 'lombok.config'
      if (Test-Path -LiteralPath $cfg -PathType Leaf) {
        foreach ($l in [System.IO.File]::ReadAllLines($cfg)) { if ($l -match '^\s*lombok\.copyableAnnotations\s*\+=\s*([\w.$]+)\s*$') { $lista += $Matches[1] } }
      }
      $Cache[$d] = $lista
    }
    $res += $Cache[$d]
  }
  return $res
}

function Get-ResultadoLombokQualifier([string]$Repo) {
  $inc = @()
  $cache = @{}
  $campo = '@(?<a>Qualifier|Value)\s*\((?:[^()]|\([^()]*\))*\)\s*(?:@\w+(?:\([^)]*\))?\s*)*(?<mod>(?:(?:private|protected|public|static|final|transient|volatile)\s+)*)[\w.\[\]]+(?:<[^;=(){}]*>)?\s+(?<n>\w+)\s*[;=]'
  foreach ($f in @(Get-JavaFiles $Repo)) {
    $rel = Get-RelRepo $Repo $f.FullName
    if ($rel -notmatch '(^|/)src/main/java/') { continue }
    $t = [System.IO.File]::ReadAllText($f.FullName)
    $todos = ($t -match '@AllArgsConstructor\b')
    if (-not ($todos -or $t -match '@RequiredArgsConstructor\b')) { continue }
    $copiables = $null
    foreach ($m in [regex]::Matches($t, $campo)) {
      $mod = $m.Groups['mod'].Value
      if ($mod -match '\bstatic\b') { continue }
      if (-not $todos -and $mod -notmatch '\bfinal\b') { continue }   # @RequiredArgsConstructor solo mete los final
      if ($null -eq $copiables) { $copiables = @(Get-CopiablesLombok $Repo $f.DirectoryName $cache) }
      $a = $m.Groups['a'].Value
      if (@($copiables | Where-Object { $_ -ceq $a -or $_.EndsWith('.' + $a) }).Count -gt 0) { continue }
      $consecuencia = 'Spring puede inyectar otro bean'
      if ($a -ceq 'Value') { $consecuencia = 'Spring no inyecta la propiedad' }
      $linea = $t.Substring(0, $m.Groups['n'].Index).Split("`n").Count
      $inc += , (New-Incidencia 'lombok' $rel $linea 'lombok' 'qualifier-sin-copiar' 'referencia' '' "Lombok no copia @$a al constructor: $consecuencia. Falta lombok.copyableAnnotations")
    }
  }
  return @{ Estado = 'ok'; Incidencias = $inc }
}

# ============================ JAVA 21: TEXTO ============================
# El codigo de un .java sin comentarios (// y /* */), con los mismos saltos de linea. Las cadenas y los caracteres se dejan tal cual (dentro de
# una cadena un // o un /* no es un comentario) o, con -SinCadenas, se les rellena de espacios lo de dentro, con sus comillas: un nombre que sale en un
# mensaje no es una llamada. Con o sin -SinCadenas, el mismo indice es el mismo sitio.
function Get-JavaSinComentarios([string]$Texto, [switch]$SinCadenas) {
  $rx = '/\*[\s\S]*?\*/|//[^\n]*|"""[\s\S]*?"""|"(?:\\.|[^"\\\n])*"|''(?:\\.|[^''\\\n])*'''
  return [regex]::Replace($Texto, $rx, {
      param($m)
      if ($m.Value.StartsWith('/')) { return ("`n" * ($m.Value.Split("`n").Count - 1)) }
      if ($SinCadenas) { return ($m.Value.Substring(0, 1) + ($m.Value.Substring(1, $m.Value.Length - 2) -replace '[^\n]', ' ') + $m.Value.Substring($m.Value.Length - 1)) }
      return $m.Value
    })
}

# Los argumentos de primer nivel (sin los espacios de los lados) de la llamada cuyo '(' esta en $Abre, sobre un texto sin comentarios. @() si no
# lleva ninguno y $null si el parentesis no se cierra.
function Get-ArgumentosJava([string]$Texto, [int]$Abre) {
  $lista = @()
  $nivel = 0
  $ini = $Abre + 1
  for ($i = $Abre; $i -lt $Texto.Length; $i++) {
    $c = $Texto[$i]
    if ($c -eq '"' -or $c -eq "'") {
      $i++
      while ($i -lt $Texto.Length -and $Texto[$i] -ne $c) { if ($Texto[$i] -eq '\') { $i++ }; $i++ }
    }
    elseif ($c -eq '(' -or $c -eq '[' -or $c -eq '{') { $nivel++ }
    elseif ($c -eq ')' -or $c -eq ']' -or $c -eq '}') {
      $nivel--
      if ($nivel -eq 0) {
        $ultimo = $Texto.Substring($ini, $i - $ini).Trim()
        if ($ultimo -or $lista.Count -gt 0) { $lista += $ultimo }
        return , $lista
      }
    }
    elseif ($c -eq ',' -and $nivel -eq 1) { $lista += $Texto.Substring($ini, $i - $ini).Trim(); $ini = $i + 1 }
  }
  return $null
}

# Donde los .java de src/main/java usan algo que en Java 21 cambia de texto, sin Maven. Una incidencia por linea y regla; el arreglo (que juego de
# caracteres, que formato) lo sabe el equipo. S1943 (el juego de caracteres por defecto) no esta en el perfil Sonar way, asi que el origen es referencia.
function Get-ResultadoJava21Texto([string]$Repo) {
  $textoCharset = 'Usa el juego de caracteres por defecto. En Java 8 era el del servidor; desde Java 18 es UTF-8. Si el fichero no es UTF-8 (n con tilde, acentos), sale distinto. Pon el juego de caracteres de forma explicita, o lanza con -Dfile.encoding=COMPAT mientras lo decidis.'
  $textoCldr = 'Desde Java 9 los nombres de mes y dia y los separadores de numeros salen de CLDR y pueden cambiar. Comprueba la salida, o lanza con -Djava.locale.providers=COMPAT.'
  # un argumento que ya dice el juego de caracteres: StandardCharsets.X, Charset.forName(...) o una variable (o su metodo) que acaba en charset
  $rxCharset = '(?i)\bStandardCharsets\s*\.|\bCharset\s*\.\s*forName\s*\(|\w*charset\s*(?:\(\s*\))?$'
  # PrintWriter y PrintStream con un solo argumento solo son de fichero si este lo parece (sin tipos no se sabe mas): una cadena, new File(...),
  # algo.toFile() o un nombre con file, path, ruta o fichero que no acaba en writer, stream ni out
  $rxFichero = '(?i)^"|^new\s+(?:java\.io\.)?File\s*\(|\.toFile\s*\(\s*\)$|^(?![\w.]*(?:writer|stream|out)$)[\w.]*(?:file|path|ruta|fichero)\w*$'
  $ficheros = @(Get-JavaFiles $Repo | Where-Object { (Get-RelRepo $Repo $_.FullName) -match '(^|/)src/main/java/' })
  if ($ficheros.Count -eq 0) { return @{ Estado = 'no aplica'; Motivo = 'no hay src/main/java' } }
  $inc = @()
  foreach ($f in $ficheros) {
    $rel = Get-RelRepo $Repo $f.FullName
    $crudo = [System.IO.File]::ReadAllText($f.FullName)
    $t = Get-JavaSinComentarios $crudo                # con las cadenas: de ahi salen los argumentos
    $b = Get-JavaSinComentarios $crudo -SinCadenas    # sin ellas: donde se busca
    $hallados = @()   # { Indice; Regla }
    foreach ($m in [regex]::Matches($b, '\bnew\s+(?:java\.io\.)?(?<c>FileReader|FileWriter|InputStreamReader|OutputStreamWriter|PrintWriter|PrintStream)\s*\(')) {
      $a = Get-ArgumentosJava $t ($m.Index + $m.Length - 1)
      if ($null -eq $a) { continue }
      $clase = $m.Groups['c'].Value
      if ($clase -ceq 'FileWriter') { $sin = (@($a | Where-Object { $_ -match $rxCharset }).Count -eq 0) }
      elseif ($clase -ceq 'PrintWriter' -or $clase -ceq 'PrintStream') { $sin = ($a.Count -eq 1 -and $a[0] -match $rxFichero) }
      else { $sin = ($a.Count -eq 1) }
      if ($sin) { $hallados += [pscustomobject]@{ Indice = $m.Index; Regla = 'charset-por-defecto' } }
    }
    foreach ($m in [regex]::Matches($b, '\.\s*getBytes\s*\(\s*\)')) { $hallados += [pscustomobject]@{ Indice = $m.Index; Regla = 'charset-por-defecto' } }
    if ($b -cnotmatch '\.\s*encoding\s*\(|\bsetEncoding\s*\(') {
      foreach ($m in [regex]::Matches($b, '\bnew\s+FlatFileItem(?:Reader|Writer)(?:Builder)?\b')) { $hallados += [pscustomobject]@{ Indice = $m.Index; Regla = 'charset-por-defecto' } }
    }
    foreach ($m in [regex]::Matches($b, '\b(?:new\s+(?:java\.text\.)?SimpleDateFormat|DateTimeFormatter\s*\.\s*ofPattern)\s*\(')) {
      $a = Get-ArgumentosJava $t ($m.Index + $m.Length - 1)
      if ($null -ne $a -and $a.Count -gt 0 -and $a[0] -cmatch '^"(?:[^"\\]|\\.)*(?:MMM|EEE)') { $hallados += [pscustomobject]@{ Indice = $m.Index; Regla = 'formato-cldr' } }
    }
    foreach ($m in [regex]::Matches($b, '\bNumberFormat\s*\.\s*get|\bnew\s+(?:java\.text\.)?DecimalFormat\s*\(')) { $hallados += [pscustomobject]@{ Indice = $m.Index; Regla = 'formato-cldr' } }
    $vistos = @{}
    foreach ($h in @($hallados | Sort-Object Indice)) {
      $linea = $b.Substring(0, $h.Indice).Split("`n").Count
      if ($vistos.ContainsKey("$linea|$($h.Regla)")) { continue }
      $vistos["$linea|$($h.Regla)"] = $true
      $texto = $textoCldr
      if ($h.Regla -ceq 'charset-por-defecto') { $texto = $textoCharset }
      $inc += , (New-Incidencia 'java21' $rel $linea 'java21-texto' $h.Regla 'referencia' '' $texto)
    }
  }
  return @{ Estado = 'ok'; Incidencias = $inc }
}

# ============================ PMD Y SPOTBUGS ============================
# Lo que Invoke-Analisis ($A) da de una herramienta ('pmd' o 'spotbugs'). Sin $A (no cabia en el tope) o con tope, no medido (tope); con
# cualquier otro estado, el estado es el motivo.
function Get-ResultadoAnalisis($A, [string]$Herramienta) {
  if ($null -eq $A -or $A.Estado -ceq 'no disponible: tope') { return @{ Estado = 'no medido (tope)' } }
  if ($A.Estado -cne 'ok') { return @{ Estado = 'no se pudo medir'; Motivo = $A.Estado } }
  $claves = @{}
  if ($Herramienta -ceq 'pmd') { $claves = Get-ClavesSonar }
  $inc = @()
  foreach ($h in @($A.Hallazgos | Where-Object { $_.Herramienta -ceq $Herramienta })) {
    $sonar = ''
    $origen = 'spotbugs'   # SpotBugs y fb-contrib: el Sonar del equipo tambien los lanza
    if ($Herramienta -ceq 'pmd') {
      $origen = 'referencia'
      if ($claves.ContainsKey($h.Regla)) { $sonar = $claves[$h.Regla]; $origen = 'sonar' }
    }
    $inc += , (New-Incidencia 'java21' $h.Fichero $h.Linea $Herramienta $h.Regla $origen $sonar $h.Mensaje)
  }
  return @{ Estado = 'ok'; Incidencias = $inc }
}

# queHago: paso2 si los hallazgos del motor dicen el mismo fichero y la misma linea; si no, sonar (origen sonar o spotbugs) o mano.
# ('notoca' es de BP-1.) Los hallazgos del motor son una matriz de {Cat, Sev, Fichero, Linea, Detalle}; si no se pueden leer, ninguna es paso2.
function Set-QueHago($Incidencias, [string]$HallazgosMotor) {
  $motor = @{}
  if ($HallazgosMotor -and (Test-Path -LiteralPath $HallazgosMotor -PathType Leaf)) {
    try {
      foreach ($h in @([System.IO.File]::ReadAllText($HallazgosMotor, $Utf8) | ConvertFrom-Json)) { $motor[(ConvertTo-RutaBarra "$($h.Fichero)") + '|' + [int]$h.Linea] = $true }
    }
    catch { $motor = @{} }
  }
  foreach ($i in @($Incidencias)) {
    if ($motor.ContainsKey("$($i.fichero)|$($i.linea)")) { $i.queHago = 'paso2' }
    elseif ($i.origen -ceq 'sonar' -or $i.origen -ceq 'spotbugs') { $i.queHago = 'sonar' }
    else { $i.queHago = 'mano' }
  }
}

# ================================ MEDIR ================================
function Invoke-Practicas([string]$Repo, [string]$Referencia, [string]$Cuando, [string]$Datos, [string]$Registros, [string]$HallazgosMotor) {
  $reloj = [System.Diagnostics.Stopwatch]::StartNew()
  $ids = @('javac', 'pmd', 'spotbugs', 'lombok-a-mano', 'lombok-qualifier', 'java21-texto')   # el orden del JSON
  $json = Join-Path $Datos "practicas-$Cuando.json"
  $registro = Join-Path $Registros "practicas-$Cuando.log"
  $res = @{}
  $clave = ''
  $fallo = ''
  try {
    $clave = Get-ClavePracticas $Repo
    if ($clave -and (Test-Path -LiteralPath $json -PathType Leaf)) {
      $previo = $null
      try { $previo = Read-Json $json } catch { $previo = $null }
      if ($null -ne $previo -and "$($previo.clave)" -ceq $clave) {
        Info "Buenas practicas ($Cuando): ya medidas con este mismo codigo (clave $clave); no se vuelven a medir."
        return
      }
    }
    foreach ($d in @($Datos, $Registros)) { if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -Force) } }
    if (Test-Path -LiteralPath $registro) { Remove-Item -LiteralPath $registro -Force }
    $fin = (Get-Date).AddSeconds([double]$Cfg.SegundosPracticas)
    $res['javac'] = Measure-Detector 'javac' { Get-ResultadoJavac $Repo $registro $fin }
    $res['lombok-a-mano'] = Measure-Detector 'lombok-a-mano' { Get-ResultadoLombokAMano $Repo $Referencia $fin }
    $res['lombok-qualifier'] = Measure-Detector 'lombok-qualifier' { Get-ResultadoLombokQualifier $Repo }
    $res['java21-texto'] = Measure-Detector 'java21-texto' { Get-ResultadoJava21Texto $Repo }
    # PMD y SpotBugs, al final y con el tiempo que quede. Invoke-Analisis no dice cuanto tardo cada uno: SpotBugs deja su registro al acabar.
    $analisis = $null
    $segSpotbugs = 0
    $segPmd = 0
    $quedan = Get-Quedan $fin
    if ($quedan -ge [double]$Cfg.SegundosMinAnalisis) {
      $inicio = Get-Date
      $analisis = Invoke-ConTope $quedan { Invoke-Analisis $Repo }
      $total = ((Get-Date) - $inicio).TotalSeconds
      $segSpotbugs = $total
      $logSpotbugs = Join-Ruta $Repo 'target/analisis/spotbugs.log'
      if (Test-Path -LiteralPath $logSpotbugs) {
        $hasta = ((Get-Item -LiteralPath $logSpotbugs).LastWriteTime - $inicio).TotalSeconds
        if ($hasta -ge 0 -and $hasta -le $total) { $segSpotbugs = $hasta }
      }
      $segPmd = $total - $segSpotbugs
    }
    $res['spotbugs'] = Measure-Detector 'spotbugs' { Get-ResultadoAnalisis $analisis 'spotbugs' } $segSpotbugs
    $res['pmd'] = Measure-Detector 'pmd' { Get-ResultadoAnalisis $analisis 'pmd' } $segPmd
  }
  catch {
    $fallo = $_.Exception.Message
    Aviso "Buenas practicas ($Cuando): la medida se ha cortado: $fallo"
  }
  try {
    $detectores = @()
    $incidencias = @()
    foreach ($id in $ids) {
      if (-not $res.ContainsKey($id)) {
        $res[$id] = [pscustomobject]@{ Detector = [ordered]@{ id = $id; estado = 'no se pudo medir'; motivo = "no se llego a medir: $fallo"; segundos = 0; corte = $false }; Incidencias = @() }
      }
      $detectores += , $res[$id].Detector
      $incidencias += @($res[$id].Incidencias)
    }
    Set-QueHago $incidencias $HallazgosMotor
    $nombreReferencia = ''
    if ($Referencia) { $nombreReferencia = Split-Path ($Referencia.TrimEnd('\', '/')) -Leaf }
    $claves = @{}
    try { $claves = Get-ClavesSonar } catch { $claves = @{} }
    $segundos = [Math]::Round($reloj.Elapsed.TotalSeconds, 1)
    $datosJson = [ordered]@{
      version      = 1
      cuando       = $Cuando
      clave        = $clave
      medido       = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
      segundos     = $segundos
      paquete      = (Get-PaqueteBase $Repo)
      referencia   = $nombreReferencia
      detectores   = @($detectores)
      sonar        = [ordered]@{ reglasWay = [int]$Cfg.SonarReglasWay; reglasAqui = @(@($claves.Values) + 'S5738' | Select-Object -Unique).Count }
      incidencias  = @($incidencias)
      arquitectura = $null
    }
    try { Write-Json $json $datosJson }
    catch { Aviso "Buenas practicas ($Cuando): no he podido escribir ${json}: $($_.Exception.Message)" }
    $resumen = @('', "== Buenas practicas ($Cuando): $($incidencias.Count) incidencias en $segundos s (clave $clave) ==")
    foreach ($d in $detectores) { $resumen += ("$($d.id): $($d.estado) $($d.motivo) ($($d.segundos) s)").Replace('  ', ' ') }
    try { [System.IO.File]::AppendAllText($registro, ($resumen -join "`n") + "`n", $Utf8) } catch { $null = $_ }

    $porArea = @()
    foreach ($a in @('java21', 'boot3-batch5', 'lombok', 'arquitectura')) {
      $n = @($incidencias | Where-Object { $_.area -ceq $a }).Count
      if ($n -gt 0) { $porArea += "${a}: $n" }
    }
    $detalle = ''
    if ($porArea.Count -gt 0) { $detalle = ' (' + ($porArea -join ', ') + ')' }
    $textoSegundos = $segundos.ToString('0.0', [System.Globalization.CultureInfo]::InvariantCulture).Replace('.', ',')
    Info "Buenas practicas ($Cuando): $($incidencias.Count) incidencias$detalle en $textoSegundos s."
    foreach ($d in $detectores) {
      if ($d.estado -cne 'ok' -and $d.estado -cne 'no aplica') {
        $porque = ''
        if ($d.motivo) { $porque = ': ' + $d.motivo }
        Aviso "Buenas practicas ($Cuando): $($d.id): $($d.estado)$porque"
      }
    }
  }
  catch { Aviso "Buenas practicas ($Cuando): no he podido dejar el resultado: $($_.Exception.Message)" }
}
