<#
propiedades.ps1 - Compara las propiedades del original con las del migrado, sin IA, y deja datos\propiedades.json (pieza C6a). No se
ejecuta solo: solo funciones. Se carga con '. (Join-Path $PSScriptRoot 'propiedades.ps1')' despues de comun.ps1 y tareas.ps1 (Write-Json,
Read-Json, Get-Hash8, Test-NombreSecreto). Solo ASCII. Vale para Windows PowerShell 5.1 y para PowerShell 7.

  Invoke-Propiedades <original> <migrado> <referencia> <datos> <registros>
      Escribe <datos>\propiedades.json y <registros>\propiedades.log y dice una linea en la consola (mas los ficheros que ha leido de
      cada lado). Nunca lanza una excepcion ni para: lo que no se pueda medir lo dice el JSON (renombres.estado = 'no se pudo medir').
      Un secreto (el ultimo trozo de la clave, o la variable ${...} de su valor, acaba en una palabra de $PalabrasSecreto) lleva
      secreto = true y su valor no se escribe en el JSON, ni en el log ni en la consola; su estado se calcula igual.

  Que lee
      Original   src/main/resources, recursivo: *.properties, *.yml y *.yaml, menos $Cfg.PropiedadesExcluir (se compara con la ruta desde
                 src/main/resources y con el nombre del fichero). Todos dan el perfil default salvo application-<p>.* (perfil p).
      Migrado    application*.properties|yml|yaml de src/main/resources y de src/main/resources/config (los que carga Spring Boot).
      Referencia lo mismo que el migrado; solo sirve para decir que una clave del migrado no esta sin leer.
      Un documento yml con spring.config.activate.on-profile o spring.profiles toma ese perfil. Dos claves son la misma si lo son con el
      relaxed binding de Spring Boot: en minusculas y sin '-' ni '_' (los [n] se quedan). Un valor con '${NOMBRE...}' va por variable.
      Original y migrado son carpetas de un solo modulo: no se buscan resources en submodulos.

  Estado de cada clave del original (gana el primero que se cumple; el valor solo se compara dentro del mismo perfil)
      igual, por-variable, distinto, renombrada (la vieja esta en los metadatos de Spring con replacement R y el migrado tiene R),
      renombrada-falta (con R y el migrado no tiene ni la vieja ni R), ya-no-existe (level error y sin replacement) y falta.
      Los metadatos salen de META-INF/spring-configuration-metadata.json de los jars del classpath del migrado (Maven
      dependency:build-classpath): la misma fuente que spring-boot-properties-migrator, pero sin tocar el pom del usuario. Se guardan en
      <datos>\propiedades-metadatos.json con la huella de pom.xml: con el mismo pom no se lanza Maven. Un fallo no se guarda.
      renombres = { estado, motivo, jars (los que traen metadatos), claves (las que Spring da por obsoletas) }.

  Claves solo del migrado (migrado[]): nueva (no casa con ninguna del original, ni con su nombre nuevo), nombreViejo (su nombre es el
      viejo de una renombrada: con replacement) y sinLeer (nadie la lee: ni los metadatos de los jars, ni la referencia, ni el codigo
      del migrado con ${clave, getProperty("clave", @ConfigurationProperties o @ConditionalOnProperty; mira una clave y sus prefijos).
      Las que empiezan por spring., logging., management., server., info., debug o trace no se miran.

  Cache: la clave de propiedades.json es la huella de los ficheros leidos (de los tres lados, mas el codigo del migrado) y la de los
  metadatos. Con la misma clave no se mide: solo sale la linea de la consola y no se toca ni el JSON ni el log.
#>

# ============================ CONFIGURACION ============================
$Cfg += @{
  # lo que no se lee del original: se compara (-like) con la ruta desde src/main/resources y con el nombre del fichero
  PropiedadesExcluir = @('META-INF/*', 'log4j*', 'logback*', 'messages*.properties', 'ValidationMessages*.properties')
}

# ============================== CLAVES ==============================
function ConvertTo-ClaveCanonica([string]$Clave) { return ($Clave.ToLowerInvariant() -replace '[-_]', '') }

# La clave canonica sin los [n]: a.b[0].c cuelga de a.b.
function Get-ClaveSinIndices([string]$Canonica) { return ($Canonica -replace '\[[^\]]*\]', '') }

function Get-VariablePropiedad([string]$Valor) {
  $m = [regex]::Match($Valor, '\$\{\s*([^}:\s]+)')
  if ($m.Success) { return $m.Groups[1].Value }
  return $null
}

# application-<p>.* da p; cualquier otro fichero, default.
function Get-PerfilFichero([string]$Rel) {
  $m = [regex]::Match((Split-Path $Rel -Leaf), '^application-(?<p>.+)\.(?:properties|ya?ml)$', 'IgnoreCase')
  if ($m.Success) { return $m.Groups['p'].Value }
  return 'default'
}

function New-Propiedad([string]$Clave, [string]$Valor, [string]$Fichero, [int]$Linea, [string]$Perfil) {
  return [pscustomobject]@{ clave = $Clave; valor = $Valor; fichero = $Fichero; linea = $Linea; perfil = $Perfil }
}

# ============================== LECTOR DE .PROPERTIES ==============================
# La linea sigue en la de abajo si acaba en un numero impar de '\'.
function Test-Continua([string]$T) {
  $n = 0
  for ($k = $T.Length - 1; $k -ge 0 -and $T[$k] -ceq '\'; $k--) { $n++ }
  return (($n % 2) -eq 1)
}

# \uXXXX, \n, \t, \r, \f y, de cualquier otro '\x', la x (\: \= \\ ...).
function ConvertFrom-EscapesProperties([string]$T) {
  if ($T.IndexOf('\') -lt 0) { return $T }
  $sb = New-Object System.Text.StringBuilder
  for ($i = 0; $i -lt $T.Length; $i++) {
    $c = [string]$T[$i]
    if ($c -cne '\' -or $i + 1 -ge $T.Length) { [void]$sb.Append($c); continue }
    $i++
    $e = [string]$T[$i]
    if ($e -ceq 'u' -and $i + 4 -lt $T.Length -and $T.Substring($i + 1, 4) -match '^[0-9a-fA-F]{4}$') {
      [void]$sb.Append([char][Convert]::ToInt32($T.Substring($i + 1, 4), 16))
      $i += 4
    }
    elseif ($e -ceq 'n') { [void]$sb.Append("`n") }
    elseif ($e -ceq 't') { [void]$sb.Append("`t") }
    elseif ($e -ceq 'r') { [void]$sb.Append("`r") }
    elseif ($e -ceq 'f') { [void]$sb.Append("`f") }
    else { [void]$sb.Append($e) }
  }
  return $sb.ToString()
}

function Read-PropiedadesProperties([string]$Rel, [string[]]$Lineas, [string]$Perfil) {
  $res = New-Object System.Collections.Generic.List[object]
  $i = 0
  while ($i -lt $Lineas.Count) {
    $inicio = $i + 1
    $t = $Lineas[$i].TrimStart()
    $i++
    if ($t.Length -eq 0 -or $t[0] -ceq '#' -or $t[0] -ceq '!') { continue }
    while ((Test-Continua $t) -and $i -lt $Lineas.Count) { $t = $t.Substring(0, $t.Length - 1) + $Lineas[$i].TrimStart(); $i++ }
    if (Test-Continua $t) { $t = $t.Substring(0, $t.Length - 1) }
    # la clave llega hasta el primer '=', ':' o blanco sin escapar; el separador puede llevar blancos a los lados
    $k = 0
    while ($k -lt $t.Length) {
      $c = [string]$t[$k]
      if ($c -ceq '\') { $k += 2; continue }
      if ($c -ceq '=' -or $c -ceq ':' -or $c -match '\s') { break }
      $k++
    }
    if ($k -gt $t.Length) { $k = $t.Length }
    if ($k -eq 0) { continue }
    $resto = $t.Substring($k).TrimStart()
    if ($resto.Length -gt 0 -and ($resto[0] -ceq '=' -or $resto[0] -ceq ':')) { $resto = $resto.Substring(1).TrimStart() }
    $res.Add((New-Propiedad (ConvertFrom-EscapesProperties $t.Substring(0, $k)) (ConvertFrom-EscapesProperties $resto.TrimEnd()) $Rel $inicio $Perfil))
  }
  return $res.ToArray()
}

# ============================== LECTOR DE YML ==============================
# El valor de una clave (lo que va detras de 'clave:'): sin comillas ni comentario.
function Read-ValorYml([string]$T) {
  $T = $T.Trim()
  if ($T.Length -eq 0) { return '' }
  $q = [string]$T[0]
  if ($q -ceq '"' -or $q -ceq "'") {
    $sb = New-Object System.Text.StringBuilder
    for ($i = 1; $i -lt $T.Length; $i++) {
      $c = [string]$T[$i]
      if ($q -ceq '"' -and $c -ceq '\' -and $i + 1 -lt $T.Length) {
        $i++
        $e = [string]$T[$i]
        if ($e -ceq 'n') { $e = "`n" } elseif ($e -ceq 't') { $e = "`t" }
        [void]$sb.Append($e)
        continue
      }
      if ($c -ceq $q) {
        if ($q -ceq "'" -and $i + 1 -lt $T.Length -and $T[$i + 1] -ceq "'") { [void]$sb.Append("'"); $i++; continue }
        break
      }
      [void]$sb.Append($c)
    }
    return $sb.ToString()
  }
  return ($T -replace '\s+#.*$', '').TrimEnd()
}

# Corchetes y llaves abiertos y sin cerrar de un texto en flujo ('[a, b' = 1).
function Get-DesbalanceFlujo([string]$T) {
  return ([regex]::Matches($T, '[\[{]').Count - [regex]::Matches($T, '[\]}]').Count)
}

# La clave de arriba deja de estar vacia en cuanto tiene un hijo: su entrada vacia (la ultima del documento) sobra.
function Set-HijoYml($Doc, $Padre) {
  if ($null -ne $Padre -and $Padre.Vacia) { $Doc.RemoveAt($Doc.Count - 1); $Padre.Vacia = $false }
}

# El yml por lineas, con una pila de sangrias. Cada frame es una clave con hijos (clave) o un elemento de lista (item).
function Read-PropiedadesYml([string]$Rel, [string[]]$Lineas, [string]$PerfilFichero) {
  $rxClave = '^(?:"(?<k>(?:[^"\\]|\\.)*)"|''(?<k>(?:[^'']|'''')*)''|(?<k>[^"''\s].*?))\s*:(?=\s|$)\s*(?<v>.*)$'
  $res = New-Object System.Collections.Generic.List[object]
  $doc = New-Object System.Collections.Generic.List[object]
  $pila = New-Object System.Collections.Generic.List[object]
  $i = 0
  while ($i -le $Lineas.Count) {
    $l = ''
    if ($i -lt $Lineas.Count) { $l = $Lineas[$i].TrimEnd() }
    if ($i -ge $Lineas.Count -or $l -cmatch '^---\s*(#.*)?$') {
      # fin del documento: su perfil lo dice spring.config.activate.on-profile o spring.profiles
      $perfil = $PerfilFichero
      foreach ($e in $doc) {
        $c = ConvertTo-ClaveCanonica $e.clave
        if (($c -ceq 'spring.config.activate.onprofile' -or $c -ceq 'spring.profiles') -and $e.valor) { $perfil = $e.valor }
      }
      foreach ($e in $doc) { $e.perfil = $perfil; $res.Add($e) }
      $doc.Clear()
      $pila.Clear()
      $i++
      continue
    }
    $linea = $i + 1
    $i++
    $t = $l.TrimStart()
    if ($t.Length -eq 0 -or $t[0] -ceq '#') { continue }
    $n = $l.Length - $t.Length
    if ($t -cmatch '^-(\s|$)') {
      # elemento de lista: cuelga de la clave de arriba, tambien si va a su misma sangria
      while ($pila.Count -gt 0 -and ($pila[$pila.Count - 1].Indent -gt $n -or ($pila[$pila.Count - 1].Indent -eq $n -and $pila[$pila.Count - 1].Tipo -ceq 'item'))) { $pila.RemoveAt($pila.Count - 1) }
      if ($pila.Count -eq 0 -or $pila[$pila.Count - 1].Tipo -cne 'clave') { continue }
      $dueno = $pila[$pila.Count - 1]
      Set-HijoYml $doc $dueno
      $ruta = $dueno.Path + '[' + $dueno.Items + ']'
      $dueno.Items++
      $resto = $t.Substring(1)
      $t = $resto.TrimStart()
      $sangria = $n
      $n = $n + 1 + ($resto.Length - $t.Length)
      if ($t.Length -gt 0 -and $t[0] -cne '#' -and $t -cnotmatch $rxClave) {
        $doc.Add((New-Propiedad $ruta (Read-ValorYml $t) $Rel $linea $PerfilFichero))
        continue
      }
      $pila.Add([pscustomobject]@{ Indent = $sangria; Path = $ruta; Tipo = 'item'; Items = 0; Vacia = $false })
      if ($t.Length -eq 0 -or $t[0] -ceq '#') { continue }
    }
    $m = [regex]::Match($t, $rxClave)
    if (-not $m.Success) { continue }
    $clave = $m.Groups['k'].Value
    if ($clave.Length -gt 2 -and $clave[0] -ceq '[' -and $clave[$clave.Length - 1] -ceq ']') { $clave = $clave.Substring(1, $clave.Length - 2) }
    while ($pila.Count -gt 0 -and $pila[$pila.Count - 1].Indent -ge $n) { $pila.RemoveAt($pila.Count - 1) }
    $padre = $null
    if ($pila.Count -gt 0) { $padre = $pila[$pila.Count - 1] }
    Set-HijoYml $doc $padre
    $ruta = $clave
    if ($null -ne $padre) { $ruta = $padre.Path + '.' + $clave }
    $v = $m.Groups['v'].Value.Trim()
    if ($v.Length -eq 0 -or $v[0] -ceq '#') {
      $doc.Add((New-Propiedad $ruta '' $Rel $linea $PerfilFichero))
      $pila.Add([pscustomobject]@{ Indent = $n; Path = $ruta; Tipo = 'clave'; Items = 0; Vacia = $true })
      continue
    }
    if ($v -cmatch '^([|>])[+-]?[0-9]*\s*(#.*)?$') {
      # bloque | (lineas con su salto) o > (unidas con un espacio): las lineas con mas sangria que la clave
      $union = "`n"
      if ($Matches[1] -ceq '>') { $union = ' ' }
      $bloque = New-Object System.Collections.Generic.List[string]
      while ($i -lt $Lineas.Count) {
        $b = $Lineas[$i].TrimEnd()
        $quitado = $b.TrimStart()
        if ($quitado.Length -gt 0 -and ($b.Length - $quitado.Length) -le $n) { break }
        $bloque.Add($quitado)
        $i++
      }
      $doc.Add((New-Propiedad $ruta (($bloque -join $union).Trim()) $Rel $linea $PerfilFichero))
      continue
    }
    if ($v[0] -ceq '[' -or $v[0] -ceq '{') {
      # coleccion en linea, tal cual como texto; si no cierra en la linea, sigue en las de abajo (hasta el final del documento)
      $texto = ($v -replace '\s+#.*$', '').Trim()
      while ((Get-DesbalanceFlujo $texto) -gt 0 -and $i -lt $Lineas.Count -and $Lineas[$i] -cnotmatch '^---') {
        $texto = $texto + ' ' + (($Lineas[$i] -replace '(^|\s)#.*$', '').Trim())
        $i++
      }
      $doc.Add((New-Propiedad $ruta $texto $Rel $linea $PerfilFichero))
      continue
    }
    $doc.Add((New-Propiedad $ruta (Read-ValorYml $v) $Rel $linea $PerfilFichero))
  }
  return $res.ToArray()
}

# Las claves planas de un fichero (.properties o yml/yaml): clave, valor, fichero, linea y perfil. $Rel es su ruta relativa al repo.
function Read-PropiedadesFichero([string]$Rel, [string]$Texto, [string]$Perfil) {
  $lineas = @($Texto -split '\r?\n')
  if ($Rel -match '\.properties$') { return (Read-PropiedadesProperties $Rel $lineas $Perfil) }
  return (Read-PropiedadesYml $Rel $lineas $Perfil)
}

# ============================== FICHEROS ==============================
# Los ficheros de configuracion de un lado, por ruta: Rel (desde la raiz del repo, con '/') y Texto. $Recursivo = el original: todo
# src/main/resources menos $Cfg.PropiedadesExcluir. Si no, el migrado y la referencia: application* de resources y de resources/config.
function Get-FicherosPropiedades([string]$Raiz, [bool]$Recursivo, $Fallos) {
  $res = New-Object System.Collections.Generic.List[object]
  if (-not $Raiz -or -not (Test-Path -LiteralPath $Raiz -PathType Container)) { return $res.ToArray() }
  $carpetas = @('src/main/resources')
  if (-not $Recursivo) { $carpetas += 'src/main/resources/config' }
  foreach ($c in $carpetas) {
    $d = Join-Ruta $Raiz $c
    if (-not (Test-Path -LiteralPath $d -PathType Container)) { continue }
    if ($Recursivo) { $fs = @(Get-ChildItem -LiteralPath $d -Recurse -File) } else { $fs = @(Get-ChildItem -LiteralPath $d -File) }
    foreach ($f in $fs) {
      if ($f.Extension -notmatch '^\.(properties|ya?ml)$') { continue }
      $rel = Get-Rel $Raiz $f.FullName
      $dentro = Get-Rel $d $f.FullName
      if ($Recursivo) {
        $fuera = $false
        foreach ($p in @($Cfg.PropiedadesExcluir)) { if ($p -and ($dentro -like $p -or $f.Name -like $p)) { $fuera = $true } }
        if ($fuera) { continue }
      }
      elseif ($f.Name -notlike 'application*') { continue }
      try { $res.Add([pscustomobject]@{ Rel = $rel; Texto = [System.IO.File]::ReadAllText($f.FullName) }) }
      catch { $Fallos.Add("No he podido leer ${rel}: $($_.Exception.Message)") }
    }
  }
  $res.Sort([System.Comparison[object]]{ param($a, $b) [string]::CompareOrdinal($a.Rel, $b.Rel) })
  return $res.ToArray()
}

# Todas las claves de los ficheros de un lado.
function Read-PropiedadesLado($Ficheros, $Fallos) {
  $res = New-Object System.Collections.Generic.List[object]
  foreach ($f in @($Ficheros)) {
    try { foreach ($p in @(Read-PropiedadesFichero $f.Rel $f.Texto (Get-PerfilFichero $f.Rel))) { $res.Add($p) } }
    catch { $Fallos.Add("No he podido interpretar $($f.Rel): $($_.Exception.Message)") }
  }
  return $res.ToArray()
}

# Lo que puede leer una clave en el migrado: los .java de src/main/java y los .xml, .yml, .yaml y .properties de src/main/resources.
function Get-FicherosCodigo([string]$Raiz, $Fallos) {
  $res = New-Object System.Collections.Generic.List[object]
  if (-not $Raiz) { return $res.ToArray() }
  foreach ($c in @('src/main/java', 'src/main/resources')) {
    $d = Join-Ruta $Raiz $c
    if (-not (Test-Path -LiteralPath $d -PathType Container)) { continue }
    foreach ($f in @(Get-ChildItem -LiteralPath $d -Recurse -File)) {
      if ($f.Extension -notmatch '^\.(java|xml|ya?ml|properties)$') { continue }
      $rel = Get-Rel $Raiz $f.FullName
      try { $res.Add([pscustomobject]@{ Rel = $rel; Texto = [System.IO.File]::ReadAllText($f.FullName) }) }
      catch { $Fallos.Add("No he podido leer ${rel}: $($_.Exception.Message)") }
    }
  }
  return $res.ToArray()
}

function Add-Lectura($Lecturas, [string]$Clave) {
  $c = (Get-ClaveSinIndices (ConvertTo-ClaveCanonica $Clave)).Trim('.')
  if ($c) { [void]$Lecturas.Add($c) }
}

# Las claves (y prefijos) que lee el codigo, en forma canonica y sin [n]: ${clave}, getProperty("clave"), @ConfigurationProperties y
# @ConditionalOnProperty (con prefix, solo el prefijo: cubre todo lo que cuelga de el).
function Get-LecturasCodigo($Codigo) {
  $lee = New-Object 'System.Collections.Generic.HashSet[string]'
  foreach ($f in @($Codigo)) {
    $t = $f.Texto
    foreach ($m in [regex]::Matches($t, '\$\{\s*([^}:\s]+)')) { Add-Lectura $lee $m.Groups[1].Value }
    foreach ($m in [regex]::Matches($t, 'get(?:Required)?Property\(\s*"([^"]+)"')) { Add-Lectura $lee $m.Groups[1].Value }
    foreach ($m in [regex]::Matches($t, '@ConfigurationProperties\s*\(([^)]*)\)')) {
      foreach ($s in [regex]::Matches($m.Groups[1].Value, '"([^"]*)"')) { Add-Lectura $lee $s.Groups[1].Value }
    }
    foreach ($m in [regex]::Matches($t, '@ConditionalOnProperty\s*\(([^)]*)\)')) {
      $cuerpo = $m.Groups[1].Value
      $prefijo = [regex]::Match($cuerpo, 'prefix\s*=\s*"([^"]*)"')
      if ($prefijo.Success) { Add-Lectura $lee $prefijo.Groups[1].Value; continue }
      $cuerpo = $cuerpo -replace 'havingValue\s*=\s*"[^"]*"', ''
      foreach ($s in [regex]::Matches($cuerpo, '"([^"]*)"')) { Add-Lectura $lee $s.Groups[1].Value }
    }
  }
  return , $lee
}

# ============================== METADATOS DE SPRING ==============================
# Lo que dicen los jars: Nombres (canonicos) y Grupos de todas las propiedades, y Deprecadas (canonica -> nombre, reemplazo y nivel).
function New-Metadatos([string]$Estado, [string]$Motivo, [int]$Jars, $Nombres, $Grupos, $Deprecadas, [string]$Huella, $Salida) {
  $n = New-Object 'System.Collections.Generic.HashSet[string]'
  $g = New-Object 'System.Collections.Generic.HashSet[string]'
  $d = @{}
  foreach ($x in @($Nombres)) { if ($x) { [void]$n.Add([string]$x) } }
  foreach ($x in @($Grupos)) { if ($x) { [void]$g.Add([string]$x) } }
  foreach ($x in @($Deprecadas)) { if ($x -and $x.nombre) { $d[(ConvertTo-ClaveCanonica ([string]$x.nombre))] = $x } }
  return [pscustomobject]@{ Estado = $Estado; Motivo = $Motivo; Jars = $Jars; Claves = $d.Count; Nombres = $n; Grupos = $g; Deprecadas = $d; Huella = $Huella; Salida = @($Salida) }
}

# Los metadatos guardados con la misma huella de pom.xml, o $null.
function Read-CacheMetadatos([string]$Datos, [string]$PomHash) {
  $f = Join-Path $Datos 'propiedades-metadatos.json'
  if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { return $null }
  try {
    $c = Read-Json $f
    if ("$($c.pom)" -cne $PomHash) { return $null }
    return (New-Metadatos 'ok' '' ([int]$c.jars) @($c.nombres) @($c.grupos) @($c.deprecadas) "$($c.huella)" @())
  }
  catch { return $null }
}

# El texto de META-INF/spring-configuration-metadata.json de un jar, o $null si no lo tiene.
function Read-MetadatosJar([string]$Jar) {
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip = [System.IO.Compression.ZipFile]::OpenRead($Jar)
  try {
    $e = $zip.GetEntry('META-INF/spring-configuration-metadata.json')
    if ($null -eq $e) { return $null }
    $r = New-Object System.IO.StreamReader($e.Open(), $Utf8)
    try { return $r.ReadToEnd() } finally { $r.Dispose() }
  }
  finally { $zip.Dispose() }
}

# Saca el classpath del migrado con Maven y lee los metadatos de sus jars. Si todo va bien los deja en <datos>\propiedades-metadatos.json;
# un fallo no se guarda (la siguiente vez se vuelve a intentar). Nunca lanza.
function Get-MetadatosSpring([string]$Migrado, [string]$Datos, [string]$Registros, [string]$PomHash) {
  $salida = @()
  try {
    if (-not $PomHash) { return (New-Metadatos 'no se pudo medir' 'El migrado no tiene pom.xml: sin el no se puede sacar el classpath con Maven' 0 @() @() @() '' @()) }
    $cp = Join-Path $Registros 'propiedades-classpath.txt'
    $registroMaven = Join-Path $Registros 'propiedades-maven.log'
    foreach ($f in @($cp, $registroMaven)) { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force } }
    try { $mvn = Invoke-MavenTope $Migrado @('-B', '-q', 'dependency:build-classpath', "-Dmdep.outputFile=$cp") 'Maven (classpath)' $registroMaven }
    catch { return (New-Metadatos 'no se pudo medir' "No he podido lanzar Maven: $($_.Exception.Message)" 0 @() @() @() '' @()) }
    $salida = @($mvn.Salida)
    if (Test-Path -LiteralPath $registroMaven) { Remove-Item -LiteralPath $registroMaven -Force }
    if ($mvn.Tope) { return (New-Metadatos 'no se pudo medir' $mvn.Tope 0 @() @() @() '' $salida) }
    if ($mvn.Codigo -ne 0) {
      $causa = @($salida | Where-Object { "$_" -match '^\[ERROR\]\s*\S' -and "$_" -notmatch 'Help|For more information|Re-run Maven|^\[ERROR\]\s*->' } | Select-Object -First 2)
      if ($causa.Count -eq 0) { $causa = @($salida | Where-Object { "$_".Trim() } | Select-Object -Last 3) }
      $texto = (($causa | ForEach-Object { ("$_" -replace '^\[ERROR\]\s*', '').Trim() }) -join ' / ')
      if ($texto.Length -gt 500) { $texto = $texto.Substring(0, 500) }
      return (New-Metadatos 'no se pudo medir' "Maven ha salido con codigo $($mvn.Codigo): $texto" 0 @() @() @() '' $salida)
    }
    if (-not (Test-Path -LiteralPath $cp -PathType Leaf) -or -not ([System.IO.File]::ReadAllText($cp).Trim())) {
      return (New-Metadatos 'no se pudo medir' 'Maven no ha dejado el classpath (propiedades-classpath.txt) o esta vacio' 0 @() @() @() '' $salida)
    }
    $nombres = New-Object 'System.Collections.Generic.HashSet[string]'
    $grupos = New-Object 'System.Collections.Generic.HashSet[string]'
    $deprecadas = @{}
    $conMetadatos = 0
    $jars = @([System.IO.File]::ReadAllText($cp).Trim().Split([System.IO.Path]::PathSeparator) | Where-Object { $_ -and $_.EndsWith('.jar') -and (Test-Path -LiteralPath $_ -PathType Leaf) })
    foreach ($jar in $jars) {
      try {
        $t = Read-MetadatosJar $jar
        if ($null -eq $t) { continue }
        $o = $t | ConvertFrom-Json
      }
      catch { $salida += "No he podido leer los metadatos de ${jar}: $($_.Exception.Message)"; continue }
      $conMetadatos++
      foreach ($g in @($o.groups)) { if ($g.name) { [void]$grupos.Add((Get-ClaveSinIndices (ConvertTo-ClaveCanonica ([string]$g.name)))) } }
      foreach ($p in @($o.properties)) {
        if (-not $p.name) { continue }
        $c = ConvertTo-ClaveCanonica ([string]$p.name)
        [void]$nombres.Add($c)
        if ($p.deprecation) { $deprecadas[$c] = [ordered]@{ nombre = [string]$p.name; reemplazo = "$($p.deprecation.replacement)"; nivel = "$($p.deprecation.level)" } }
      }
    }
    if ($conMetadatos -eq 0) {
      return (New-Metadatos 'no se pudo medir' "Ninguno de los $($jars.Count) jars del classpath trae META-INF/spring-configuration-metadata.json: sin esos metadatos no se saben los renombres" 0 @() @() @() '' $salida)
    }
    $nombresOrd = New-Object System.Collections.Generic.List[string]($nombres)
    $nombresOrd.Sort([System.StringComparer]::Ordinal)
    $gruposOrd = New-Object System.Collections.Generic.List[string]($grupos)
    $gruposOrd.Sort([System.StringComparer]::Ordinal)
    $depOrd = @($deprecadas.Keys | Sort-Object { $_ } | ForEach-Object { $deprecadas[$_] })
    $huella = Get-Hash8 (($nombresOrd -join ',') + '|' + ($gruposOrd -join ',') + '|' + (@($depOrd | ForEach-Object { "$($_.nombre)>$($_.reemplazo)>$($_.nivel)" }) -join ','))
    try {
      Write-Json (Join-Path $Datos 'propiedades-metadatos.json') ([ordered]@{
          pom = $PomHash; huella = $huella; jars = $conMetadatos
          nombres = $nombresOrd.ToArray(); grupos = $gruposOrd.ToArray(); deprecadas = @($depOrd)
        })
    }
    catch { $salida += "No he podido guardar la cache de metadatos: $($_.Exception.Message)" }
    return (New-Metadatos 'ok' '' $conMetadatos $nombresOrd.ToArray() $gruposOrd.ToArray() $depOrd $huella $salida)
  }
  catch { return (New-Metadatos 'no se pudo medir' "No he podido sacar los metadatos: $($_.Exception.Message)" 0 @() @() @() '' $salida) }
}

# ============================== COMPARAR ==============================
# Las claves del migrado por su forma canonica (todas las entradas de cada una).
function New-IndicePropiedades($Entradas) {
  $indice = @{}
  foreach ($e in @($Entradas)) {
    $c = ConvertTo-ClaveCanonica $e.clave
    if (-not $indice.ContainsKey($c)) { $indice[$c] = New-Object System.Collections.Generic.List[object] }
    $indice[$c].Add($e)
  }
  return $indice
}

# Donde esta una clave en el migrado, por este orden: la entrada del mismo perfil; la del perfil default (en Spring Boot lo de
# application vale tambien con otro perfil, salvo que application-<p> lo cambie); y la de otro perfil que va por variable. Las dos primeras
# se comparan con el valor del original (Comparable); la tercera no. Sin ninguna, Otros dice los perfiles en los que si esta.
function Find-EnMigrado($Indice, [string]$Canonica, [string]$Perfil) {
  $r = [pscustomobject]@{ Entrada = $null; Variable = $null; Comparable = $false; Otros = @() }
  if (-not $Indice.ContainsKey($Canonica)) { return $r }
  $lista = $Indice[$Canonica].ToArray()
  foreach ($p in @($Perfil, 'default')) {
    foreach ($e in $lista) {
      if ($e.perfil -ceq $p) { $r.Entrada = $e; $r.Variable = Get-VariablePropiedad $e.valor; $r.Comparable = $true; return $r }
    }
  }
  foreach ($e in $lista) {
    $v = Get-VariablePropiedad $e.valor
    if ($v) { $r.Entrada = $e; $r.Variable = $v; return $r }
  }
  $r.Otros = @($lista | ForEach-Object { $_.perfil } | Select-Object -Unique)
  return $r
}

# El ultimo trozo de una clave, sin su [n]: db.password -> password.
function Get-UltimoTrozo([string]$Clave) { return (($Clave -replace '\[[^\]]*\]$', '').Split('.')[-1]) }

# Un secreto por el ultimo trozo de la clave o por el nombre de alguna de las variables de sus valores.
function Test-ClaveSecreta([string]$Clave, [string[]]$Variables) {
  return (Test-NombreSecreto @(@((Get-UltimoTrozo $Clave)) + @($Variables | Where-Object { $_ })))
}

# La entrada de propiedades.json de una clave del original.
function Get-EstadoPropiedad($L, $Indice, $Meta) {
  $c = ConvertTo-ClaveCanonica $L.clave
  $f = Find-EnMigrado $Indice $c $L.perfil
  $estado = 'falta'
  $texto = ''
  $destino = $null
  $variable = $null
  $renombradaA = $null
  $valorIgual = $null
  if ($null -ne $f.Entrada) {
    $destino = $f.Entrada
    if ($f.Comparable -and $destino.valor -ceq $L.valor) { $estado = 'igual' }
    elseif ($f.Variable) {
      $estado = 'por-variable'
      $variable = $f.Variable
      $texto = "Va por la variable $($f.Variable): es lo esperado con configmap"
    }
    else { $estado = 'distinto'; $texto = 'El valor del migrado no es el del original' }
  }
  else {
    $dep = $Meta.Deprecadas[$c]
    if ($dep -and $dep.reemplazo) {
      $renombradaA = $dep.reemplazo
      $r = Find-EnMigrado $Indice (ConvertTo-ClaveCanonica $dep.reemplazo) $L.perfil
      if ($null -ne $r.Entrada) {
        $estado = 'renombrada'
        $destino = $r.Entrada
        $variable = $r.Variable
        if (-not $variable) { $valorIgual = ($destino.valor -ceq $L.valor) }
        $texto = "En Spring Boot 3 se llama $renombradaA y el migrado ya la tiene con ese nombre"
        if ($valorIgual -eq $false) { $texto += ', pero con otro valor' }
      }
      else { $estado = 'renombrada-falta'; $texto = "En Spring Boot 3 se llama $renombradaA y no esta en el migrado" }
    }
    elseif ($dep -and $dep.nivel -ieq 'error') { $estado = 'ya-no-existe'; $texto = 'Spring Boot 3 ya no la tiene: quitala o busca que la sustituye' }
    elseif ($f.Otros.Count -gt 0) { $texto = 'Esta en el migrado solo con otro perfil (' + ($f.Otros -join ', ') + ')' }
    else { $texto = 'No esta en el migrado' }
  }
  $secreto = Test-ClaveSecreta $L.clave @((Get-VariablePropiedad $L.valor), $variable)
  $enMigrado = $null
  $valorLegacy = $L.valor
  $valorMigrado = $null
  if ($null -ne $destino) {
    $enMigrado = [ordered]@{ clave = $destino.clave; fichero = $destino.fichero; linea = $destino.linea }
    $valorMigrado = $destino.valor
  }
  if ($secreto) { $valorLegacy = $null; $valorMigrado = $null }
  return [ordered]@{
    clave = $L.clave; perfil = $L.perfil; fichero = $L.fichero; linea = $L.linea; estado = $estado; enMigrado = $enMigrado
    valorLegacy = $valorLegacy; valorMigrado = $valorMigrado; variable = $variable; renombradaA = $renombradaA; valorIgual = $valorIgual
    secreto = $secreto; texto = $texto
  }
}

# Nadie la lee: ni ella ni nada de lo que cuelga de sus prefijos esta en los metadatos de los jars o en el codigo, ni esta en la referencia.
function Test-SinLeer([string]$Canonica, $Leidas, $Referencia) {
  if ($Canonica -cmatch '^(spring\.|logging\.|management\.|server\.|info\.|debug|trace)') { return $false }
  $s = Get-ClaveSinIndices $Canonica
  if ($Referencia.Contains($s)) { return $false }
  while ($true) {
    if ($Leidas.Contains($s)) { return $false }
    $k = $s.LastIndexOf('.')
    if ($k -lt 0) { return $true }
    $s = $s.Substring(0, $k)
  }
}

# Las claves del original con su estado, las solo del migrado (nueva, sinLeer, nombreViejo) y la cuenta de cada estado.
function Compare-Propiedades($Legacy, $Migrado, $Referencia, $Meta, $Lecturas) {
  $indice = New-IndicePropiedades $Migrado
  $delOriginal = New-Object 'System.Collections.Generic.HashSet[string]'
  $leg = New-Object System.Collections.Generic.List[object]
  foreach ($l in @($Legacy)) {
    $c = ConvertTo-ClaveCanonica $l.clave
    [void]$delOriginal.Add($c)
    $dep = $Meta.Deprecadas[$c]
    if ($dep -and $dep.reemplazo) { [void]$delOriginal.Add((ConvertTo-ClaveCanonica $dep.reemplazo)) }
    $leg.Add((Get-EstadoPropiedad $l $indice $Meta))
  }
  $leidas = New-Object 'System.Collections.Generic.HashSet[string]'
  $leidas.UnionWith($Meta.Nombres)
  $leidas.UnionWith($Meta.Grupos)
  $leidas.UnionWith($Lecturas)
  $enReferencia = New-Object 'System.Collections.Generic.HashSet[string]'
  foreach ($r in @($Referencia)) { [void]$enReferencia.Add((Get-ClaveSinIndices (ConvertTo-ClaveCanonica $r.clave))) }
  $mig = New-Object System.Collections.Generic.List[object]
  foreach ($e in @($Migrado)) {
    $c = ConvertTo-ClaveCanonica $e.clave
    $nueva = -not $delOriginal.Contains($c)
    $dep = $Meta.Deprecadas[$c]
    $viejo = [bool]($dep -and $dep.reemplazo)
    $sinLeer = Test-SinLeer $c $leidas $enReferencia
    if (-not ($nueva -or $sinLeer -or $viejo)) { continue }
    $textos = @()
    if ($viejo -and $dep.nivel -ieq 'error') { $textos += "Con este nombre Spring Boot 3 no la lee: se llama $($dep.reemplazo)" }
    elseif ($viejo) { $textos += "Con este nombre Spring Boot 3 la lee pero esta obsoleta: se llama $($dep.reemplazo)" }
    if ($nueva) { $textos += 'No esta en el original' }
    if ($sinLeer) { $textos += 'Sobra: ni el codigo ni las librerias ni la referencia la leen' }
    $secreto = Test-ClaveSecreta $e.clave @((Get-VariablePropiedad $e.valor))
    $valor = $e.valor
    if ($secreto) { $valor = $null }
    $renombradaA = $null
    if ($viejo) { $renombradaA = $dep.reemplazo }
    $mig.Add([ordered]@{
        clave = $e.clave; perfil = $e.perfil; fichero = $e.fichero; linea = $e.linea; valor = $valor; secreto = $secreto
        nueva = $nueva; sinLeer = $sinLeer; nombreViejo = $viejo; renombradaA = $renombradaA; texto = ($textos -join ' ')
      })
  }
  $resumen = [ordered]@{ total = $leg.Count }
  foreach ($s in @('igual', 'por-variable', 'distinto', 'renombrada', 'renombrada-falta', 'ya-no-existe', 'falta')) {
    $resumen[$s] = @($leg | Where-Object { $_.estado -ceq $s }).Count
  }
  $resumen['nueva'] = @($mig | Where-Object { $_.nueva }).Count
  $resumen['sinLeer'] = @($mig | Where-Object { $_.sinLeer }).Count
  $resumen['nombreViejo'] = @($mig | Where-Object { $_.nombreViejo }).Count
  return [pscustomobject]@{ Legacy = $leg.ToArray(); Migrado = $mig.ToArray(); Resumen = $resumen }
}

# ================================ MEDIR ================================
# La linea de la consola, con las cuentas de un resumen (el que acaba de salir o el de propiedades.json). 'faltan' cuenta tambien las
# renombradas que no estan en el migrado.
function Get-LineaPropiedades($Resumen, [string]$Ruta) {
  $faltan = [int]$Resumen.falta + [int]$Resumen.'renombrada-falta'
  return "Propiedades: $($Resumen.total) del original: $($Resumen.igual) iguales, $($Resumen.'por-variable') por variable, $($Resumen.renombrada) renombradas, $faltan faltan, $($Resumen.distinto) distintas, $($Resumen.'ya-no-existe') ya no existen; $($Resumen.sinLeer) del migrado sin leer. Detalle en ${Ruta}."
}

function Get-TextoFicheros([string]$Lado, $Ficheros) {
  $rels = @(@($Ficheros) | ForEach-Object { $_.Rel })
  if ($rels.Count -eq 0) { return "Ficheros leidos del ${Lado}: ninguno" }
  return "Ficheros leidos del $Lado ($($rels.Count)): $($rels -join ', ')"
}

# La huella de este mismo script: si cambia la logica, la cache de la medida deja de valer y se rehace sola.
function Get-HuellaScriptPropiedades {
  try { return (Get-Hash8 ([System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'propiedades.ps1')))) }
  catch { return 'sin-script' }
}

# La clave de la cache: los ficheros leidos (con su huella), el codigo del migrado, la lista de exclusiones, la huella de los metadatos y
# la de este script.
function Get-ClavePropiedades($Lados, $Codigo, [string]$HuellaMetadatos) {
  $lineas = @('exclusiones|' + (@($Cfg.PropiedadesExcluir) -join ','), "metadatos|$HuellaMetadatos", ('script|' + (Get-HuellaScriptPropiedades)))
  foreach ($l in $Lados.Keys) { foreach ($f in @($Lados[$l])) { $lineas += "$l|$($f.Rel)|$(Get-Hash8 $f.Texto)" } }
  foreach ($f in @($Codigo)) { $lineas += "codigo|$($f.Rel)|$(Get-Hash8 $f.Texto)" }
  return (Get-Hash8 (($lineas | Sort-Object { $_ }) -join "`n"))
}

function Invoke-Propiedades([string]$Legacy, [string]$Migrado, [string]$Referencia, [string]$Datos, [string]$Registros) {
  $json = Join-Path $Datos 'propiedades.json'
  $registro = Join-Path $Registros 'propiedades.log'
  try {
    foreach ($d in @($Datos, $Registros)) { if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -Force) } }
    $fallos = New-Object System.Collections.Generic.List[string]
    $ficheros = [ordered]@{
      legacy = @(Get-FicherosPropiedades $Legacy $true $fallos)
      migrado = @(Get-FicherosPropiedades $Migrado $false $fallos)
      referencia = @(Get-FicherosPropiedades $Referencia $false $fallos)
    }
    $codigo = @(Get-FicherosCodigo $Migrado $fallos)
    $pomHash = ''
    $pom = Join-Path $Migrado 'pom.xml'
    if (Test-Path -LiteralPath $pom -PathType Leaf) { $pomHash = Get-Hash8 ([System.IO.File]::ReadAllText($pom)) }
    $meta = $null
    if ($pomHash) { $meta = Read-CacheMetadatos $Datos $pomHash }
    if ($null -eq $meta) { $meta = Get-MetadatosSpring $Migrado $Datos $Registros $pomHash }
    $huellaMetadatos = $meta.Huella
    if ($meta.Estado -cne 'ok') { $huellaMetadatos = 'sin-metadatos' }
    $clave = Get-ClavePropiedades $ficheros $codigo $huellaMetadatos
    if ($meta.Estado -ceq 'ok' -and (Test-Path -LiteralPath $json -PathType Leaf)) {
      $previo = $null
      try { $previo = Read-Json $json } catch { $previo = $null }
      if ($null -ne $previo -and "$($previo.clave)" -ceq $clave) { Info (Get-LineaPropiedades $previo.resumen $json); return }
    }
    $propiedades = [ordered]@{}
    foreach ($lado in @('legacy', 'migrado', 'referencia')) { $propiedades[$lado] = @(Read-PropiedadesLado $ficheros[$lado] $fallos) }
    $cmp = Compare-Propiedades $propiedades.legacy $propiedades.migrado $propiedades.referencia $meta (Get-LecturasCodigo $codigo)
    $rels = [ordered]@{}
    foreach ($lado in $ficheros.Keys) { $rels[$lado] = [string[]]@(@($ficheros[$lado]) | ForEach-Object { $_.Rel }) }
    $datosJson = [ordered]@{
      clave = $clave
      ficheros = $rels
      renombres = [ordered]@{ estado = $meta.Estado; motivo = $meta.Motivo; jars = $meta.Jars; claves = $meta.Claves }
      legacy = @($cmp.Legacy)
      migrado = @($cmp.Migrado)
      resumen = $cmp.Resumen
    }
    $linea = Get-LineaPropiedades $cmp.Resumen $json
    $textos = @(
      (Get-TextoFicheros 'original' $ficheros.legacy), (Get-TextoFicheros 'migrado' $ficheros.migrado), (Get-TextoFicheros 'referencia' $ficheros.referencia)
    )
    $log = @($meta.Salida | ForEach-Object { "$_" }) + $textos + @("Codigo leido del migrado: $($codigo.Count) ficheros")
    if ($meta.Estado -ceq 'ok') { $log += "Renombres de Spring Boot 3: ok ($($meta.Jars) jars con metadatos, $($meta.Claves) claves obsoletas)" }
    else { $log += "Renombres de Spring Boot 3: no se pudo medir: $($meta.Motivo)" }
    $log += @($fallos) + @('', $linea)
    try { Write-Json $json $datosJson }
    catch { Aviso "Propiedades: no he podido escribir ${json}: $($_.Exception.Message)" }
    try { [System.IO.File]::WriteAllText($registro, (($log -join "`n") + "`n"), $Utf8) } catch { $null = $_ }
    foreach ($t in $textos) { Info $t }
    foreach ($f in $fallos) { Aviso $f }
    if ($meta.Estado -cne 'ok') { Aviso "Renombres de Spring Boot 3 sin medir: $($meta.Motivo)" }
    Info $linea
  }
  catch {
    $porque = $_.Exception.Message
    Aviso "Propiedades: la medida se ha cortado: $porque"
    try {
      Write-Json $json ([ordered]@{
          clave = ''
          ficheros = [ordered]@{ legacy = @(); migrado = @(); referencia = @() }
          renombres = [ordered]@{ estado = 'no se pudo medir'; motivo = "la medida se ha cortado: $porque"; jars = 0; claves = 0 }
          legacy = @(); migrado = @(); resumen = $null
        })
    }
    catch { $null = $_ }
  }
}
