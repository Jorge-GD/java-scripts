<#
lanzadores.ps1 - Lo que hacen los scripts de shell (.sh, .ksh, .bash) que lanzan el batch: de que ficheros se trata, que hay en
cada linea de cada uno, con que job se enlazan, su ficha (ficha-sh) y su comparacion con el migrado (comparar-sh).
Se carga con '. (Join-Path $PSScriptRoot 'lanzadores.ps1')' despues de comun.ps1 y tareas.ps1, desde migracion.ps1 o desde
cualquier script que necesite lo mismo sin pasar por el arranque. Cargarlo no ejecuta nada: solo define funciones. Solo ASCII a proposito.

EL INVENTARIO NO USA IA. Son expresiones regulares sobre el texto del script (ksh incluido, que ningun parser publicado lee). Cada
linea del inventario lleva su numero, su tipo y un detalle: java (el jar, los -D de antes y los argumentos de detras), perfil, job,
parametro, fichero (mv, cp, rm, find, gzip, zip, tar, touch, ls, cd), envio (sftp, scp, ftp, curl, mail, mailx, sendmail), fecha (date +...),
salida (exit N), lanza (otro script) y cerrojo (flock, .lock, .pid). Un comentario o un texto entre comillas no cuenta; un exit sin
numero tampoco. Lo que no se ve con regex (un java lanzado desde una variable, un script que se genera) no sale: la ficha lo cuenta si lo ve.

EL ENLACE CON EL JOB (Get-JobLanzador), en este orden: el job que dice un argumento; el perfil de Spring con un application-<perfil>
(.yml, .yaml o .properties) que dice spring.batch.job.name(s); el perfil con una clase @Profile("<perfil>") que define jobs (los del contrato:
nombre y definidoEn); si el batch solo tiene un job, ese; si no, sin enlazar. Cada enlace dice como se hizo (argumento, yml, profile,
unico o sin-enlazar) y su fichero y linea.

DEFINE: las claves de $Cfg de abajo (LanzadorSaltar, LanzadorNoScripts) y las funciones. Usa las de comun.ps1 (Get-Rel, Join-Ruta) y de
tareas.ps1 (Get-Hash8, Read-Json, Write-Json, Find-Cita, Test-Citas...).
#>

# ============================ CONFIGURACION ============================
$Cfg += @{
  LanzadorSaltar    = @('.git', 'target', 'node_modules')   # carpetas en las que no se entra
  LanzadorNoScripts = @('mvnw', 'gradlew')                   # los scripts de la herramienta de construccion no lanzan el batch
}

# ================================ FICHEROS ================================
# Todos los ficheros de $Raiz (Rel con /, Ruta, Nombre y Ext en minusculas), en orden ordinal de Rel, sin entrar en LanzadorSaltar.
function Get-ArbolLanzador([string]$Raiz) {
  $res = New-Object System.Collections.Generic.List[object]
  $pila = New-Object System.Collections.Generic.Stack[string]
  $pila.Push($Raiz)
  while ($pila.Count -gt 0) {
    $d = $pila.Pop()
    foreach ($f in @(Get-ChildItem -LiteralPath $d -File -Force)) {
      $res.Add([pscustomobject]@{ Rel = (Get-Rel $Raiz $f.FullName); Ruta = $f.FullName; Nombre = $f.Name; Ext = $f.Extension.ToLowerInvariant() })
    }
    foreach ($s in @(Get-ChildItem -LiteralPath $d -Directory -Force)) {
      if ($Cfg.LanzadorSaltar -cnotcontains $s.Name) { $pila.Push($s.FullName) }
    }
  }
  $porRel = New-Object 'System.Collections.Generic.Dictionary[string,object]'
  foreach ($f in $res) { $porRel[$f.Rel] = $f }
  $claves = [string[]]@($porRel.Keys)
  [System.Array]::Sort($claves, [System.StringComparer]::Ordinal)
  return @($claves | ForEach-Object { $porRel[$_] })
}

# El interprete (sh, bash o ksh) de la linea #! de un fichero, o '' si no empieza por #! de uno de ellos.
function Get-Shebang([string]$Ruta) {
  $fs = [System.IO.File]::OpenRead($Ruta)
  try {
    $b = New-Object byte[] 200
    $n = $fs.Read($b, 0, 200)
  }
  finally { $fs.Dispose() }
  $primera = ([System.Text.Encoding]::GetEncoding(28591).GetString($b, 0, $n) -split "`n")[0]
  $m = [regex]::Match($primera, '^#!\s*(?:\S*/)?(?:env\s+(?:-\S+\s+)*)?(sh|bash|ksh)(?:\s|$)')
  if ($m.Success) { return $m.Groups[1].Value }
  return ''
}

# Los scripts de $Raiz: los .sh, .ksh y .bash (con el interprete de su #! si lo dice y, si no, el de la extension) y los ficheros sin extension
# cuya primera linea es #! de sh, bash o ksh. Rel lleva $Prefijo delante (los de -Lanzadores se distinguen asi).
function Get-FicherosLanzador([string]$Raiz, [string]$Prefijo = '') {
  $res = @()
  foreach ($f in @(Get-ArbolLanzador $Raiz)) {
    if ($Cfg.LanzadorNoScripts -ccontains $f.Nombre) { continue }
    $porExt = @{ '.sh' = 'sh'; '.ksh' = 'ksh'; '.bash' = 'bash' }
    if ($porExt.ContainsKey($f.Ext)) {
      $i = Get-Shebang $f.Ruta
      if (-not $i) { $i = $porExt[$f.Ext] }
    }
    elseif ($f.Nombre -notmatch '\.') {
      $i = Get-Shebang $f.Ruta
      if (-not $i) { continue }
    }
    else { continue }
    $res += [pscustomobject]@{ Rel = ($Prefijo + $f.Rel); Ruta = $f.Ruta; Interprete = $i }
  }
  return $res
}

# Las lineas de un script, leidas como las lee el indice de citas (UTF-8 y, si no vale, Latin-1): asi coinciden los numeros de linea.
function Get-LineasShell([string]$Ruta) {
  try { return @([System.IO.File]::ReadAllLines($Ruta, (New-Object System.Text.UTF8Encoding($false, $true)))) }
  catch { return @([System.IO.File]::ReadAllLines($Ruta, [System.Text.Encoding]::GetEncoding(28591))) }
}

# ============================== INVENTARIO ==============================
# Los trozos de expresion regular de abajo: el sitio donde empieza una orden (principio de linea, despues de ; & | ( { ` $( ) o de then, do,
# else, elif, if, while, until), lo que puede ir delante de la orden (exec, sudo...) y la orden misma.
$script:RxPos = '(?<=(?:^|[;&|(`{]|\)|\$\(|\b(?:then|do|else|elif|if|while|until)\b)\s*)'
$script:RxMod = '(?:(?:exec|sudo|nohup|time|command|!)\s+)*'
$script:RxOrden = $script:RxPos + $script:RxMod + '([^\s;|&()<>]+)'
$script:RxSalida = $script:RxPos + $script:RxMod + 'exit\s+([^\s;|&)]+)'
$script:RxInterprete = $script:RxPos + $script:RxMod + '(?:sh|bash|ksh|source|\.)\s+(?:-\w+\s+)*([^\s;|&()<>''"\-][^\s;|&()<>]*)'
$script:RxTextoShell = '''[^'']*''|"(?:\\.|[^"\\])*"|\\.|(?<=^|[\s;&|(])#.*$'
$script:OrdenTipos = @('java', 'perfil', 'job', 'parametro', 'fichero', 'envio', 'fecha', 'salida', 'lanza', 'cerrojo')

# Las lineas de un script con las que acaban en \ unidas a la siguiente: Ini y Fin (lineas fisicas, desde 1) y Texto.
function Get-LineasLogicas($Lineas) {
  $res = @()
  $i = 0
  while ($i -lt $Lineas.Count) {
    $ini = $i + 1
    $t = [string]$Lineas[$i]
    while ($t.EndsWith('\') -and $t.TrimStart() -notlike '#*' -and ($i + 1) -lt $Lineas.Count) {
      $i++
      $t = $t.Substring(0, $t.Length - 1) + ' ' + $Lineas[$i]
    }
    $res += [pscustomobject]@{ Ini = $ini; Fin = ($i + 1); Texto = $t }
    $i++
  }
  return $res
}

# Los -D y los argumentos de lo que va entre java y -jar y de lo que va detras del jar (sin redirecciones ni lo que viene tras un ; | o &&).
function Get-ArgumentosJava([string]$Antes, [string]$Despues) {
  $rx = '(?:[^\s"'']|"[^"]*"|''[^'']*'')+'
  $props = @([regex]::Matches($Antes, $rx) | ForEach-Object { $_.Value } | Where-Object { $_ -like '-D*' })
  $corte = ([regex]::Split($Despues, '\s&&|\s&(?=\s|$)'))[0]
  $args2 = @()
  $salta = $false
  foreach ($m in [regex]::Matches($corte, $rx)) {
    $t = $m.Value
    if ($salta) { $salta = $false; continue }
    if ($t -match '^(\d*|&)[<>]+$') { $salta = $true; continue }
    if ($t -match '^(\d*|&)[<>]') { continue }
    if ($t -eq '&') { continue }
    $args2 += $t
  }
  return [pscustomobject]@{ Propiedades = $props; Argumentos = $args2 }
}

# Los valores de todas las coincidencias de $Rx en $Texto (grupo 1), separados por comas y sin repetir.
function Get-ValoresShell([string]$Texto, [string]$Rx) {
  $v = @()
  foreach ($m in [regex]::Matches($Texto, $Rx, 'IgnoreCase')) { foreach ($x in ($m.Groups[1].Value -split ',')) { if ($x -and $v -cnotcontains $x) { $v += $x } } }
  return ($v -join ',')
}

# El inventario de un script ($Lineas: sus lineas): por cada linea logica, los items { linea, fin, tipo, detalle } que lleva (uno por tipo);
# los de java llevan ademas jar, propiedades y argumentos. Sin IA: expresiones regulares sobre el texto sin comentarios (crudo) y sin el
# contenido de las comillas (limpio, para saber donde empieza cada orden).
function Get-InventarioLanzador($Lineas) {
  $items = @()
  foreach ($l in @(Get-LineasLogicas $Lineas)) {
    $crudo = [regex]::Replace($l.Texto, $script:RxTextoShell, { param($m) if ($m.Value.StartsWith('#')) { '' } else { $m.Value } })
    $limpio = [regex]::Replace($crudo, $script:RxTextoShell, { param($m) if ($m.Value.Length -ge 2 -and ($m.Value.StartsWith('"') -or $m.Value.StartsWith("'"))) { $m.Value.Substring(0, 1) + (' ' * ($m.Value.Length - 2)) + $m.Value.Substring($m.Value.Length - 1) } else { $m.Value } })
    $hallado = @{}
    $j = [regex]::Match($limpio, '(?<![\w.-])java\s+(?<antes>(?:[^;|&]*?\s)?)-jar\s+(?<jar>[^\s;|&]+)(?<despues>[^;|]*)')
    if ($j.Success) {
      $a = Get-ArgumentosJava $crudo.Substring($j.Groups['antes'].Index, $j.Groups['antes'].Length) $crudo.Substring($j.Groups['despues'].Index, $j.Groups['despues'].Length)
      $jar = $crudo.Substring($j.Groups['jar'].Index, $j.Groups['jar'].Length).Trim('"', "'")
      $hallado['java'] = [ordered]@{ detalle = $jar; jar = $jar; propiedades = @($a.Propiedades); argumentos = @($a.Argumentos) }
    }
    $v = Get-ValoresShell $crudo 'spring[._]profiles[._]active\s*=\s*["'']?([^\s"'';|&)]+)'
    if ($v) { $hallado['perfil'] = [ordered]@{ detalle = $v } }
    $v = Get-ValoresShell $crudo '(?:spring\.batch\.job|(?<![\w.])job)\.names?\s*=\s*["'']?([^\s"'';|&)]+)'
    if ($v) { $hallado['job'] = [ordered]@{ detalle = $v } }
    $p = ''
    $m = [regex]::Match($limpio, '^\s*(-{1,2}[\w-]+(?:\s*\|\s*-{1,2}[\w-]+)*)\s*\)')
    if ($m.Success) { $p = $m.Groups[1].Value }
    if (-not $p) { $m = [regex]::Match($limpio, '(?<=^|[\s;&|(`{])getopts\s+(\S+)'); if ($m.Success) { $p = 'getopts ' + $m.Groups[1].Value } }
    if (-not $p) { $m = [regex]::Match($crudo, '\$\{?[1-9]\b'); if ($m.Success) { $p = $m.Value } }
    if ($p) { $hallado['parametro'] = [ordered]@{ detalle = $p } }
    $ordenes = @([regex]::Matches($limpio, $script:RxOrden) | ForEach-Object { $_.Groups[1].Value })
    $f = @($ordenes | Where-Object { @('mv', 'cp', 'rm', 'find', 'gzip', 'zip', 'tar', 'touch', 'ls', 'cd') -ccontains $_ } | Select-Object -Unique)
    if ($f.Count -gt 0) { $hallado['fichero'] = [ordered]@{ detalle = ($f -join ',') } }
    $e = @($ordenes | Where-Object { @('sftp', 'scp', 'ftp', 'curl', 'mail', 'mailx', 'sendmail') -ccontains $_ } | Select-Object -Unique)
    if ($e.Count -gt 0) { $hallado['envio'] = [ordered]@{ detalle = ($e -join ',') } }
    $m = [regex]::Match($crudo, '\bdate\s+(?:-\w+\s+)*["'']?\+[^\s"''`)]*')
    if ($m.Success) { $hallado['fecha'] = [ordered]@{ detalle = $m.Value } }
    $s = @([regex]::Matches($limpio, $script:RxSalida) | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
    if ($s.Count -gt 0) { $hallado['salida'] = [ordered]@{ detalle = ($s -join ',') } }
    $z = @($ordenes | Where-Object { $_ -match '^(?:\.{1,2}/.*|.*\.(?:sh|ksh|bash))$' })
    $z += @([regex]::Matches($limpio, $script:RxInterprete) | ForEach-Object { $_.Groups[1].Value })
    $z = @($z | Select-Object -Unique)
    if ($z.Count -gt 0) { $hallado['lanza'] = [ordered]@{ detalle = ($z -join ',') } }
    foreach ($c in @('\bflock\b', '\.lock\b', '\.pid\b')) {
      $m = [regex]::Match($crudo, $c)
      if ($m.Success) { $hallado['cerrojo'] = [ordered]@{ detalle = $m.Value }; break }
    }
    foreach ($tipo in $script:OrdenTipos) {
      if (-not $hallado.ContainsKey($tipo)) { continue }
      $it = [ordered]@{ linea = $l.Ini; fin = $l.Fin; tipo = $tipo }
      foreach ($k in $hallado[$tipo].Keys) { $it[$k] = $hallado[$tipo][$k] }
      $items += , $it
    }
  }
  return $items
}

# ================================== ENLACE ==================================
# Los nombres de job y la linea de spring.batch.job.name(s) de un application-<perfil>.yml, .yaml o .properties; $null si no lo dice.
function Get-JobEnConfiguracion([string]$Ruta) {
  $lineas = Get-LineasShell $Ruta
  $propiedades = $Ruta -match '\.properties$'
  $pila = New-Object System.Collections.Generic.List[object]
  for ($i = 0; $i -lt $lineas.Count; $i++) {
    $t = [string]$lineas[$i]
    if ($t -match '^\s*(#|!|$)') { continue }
    $valor = $null
    if ($propiedades) {
      $m = [regex]::Match($t, '^\s*spring\.batch\.job\.names?\s*[=:]\s*(.*?)\s*$')
      if ($m.Success) { $valor = $m.Groups[1].Value }
    }
    else {
      if ($t -match '^---') { $pila.Clear(); continue }
      $m = [regex]::Match($t, '^(\s*)([\w.\-]+)\s*:(?:\s+(.*))?$')
      if (-not $m.Success) { continue }
      $sangria = $m.Groups[1].Length
      while ($pila.Count -gt 0 -and $pila[$pila.Count - 1].Sangria -ge $sangria) { $pila.RemoveAt($pila.Count - 1) }
      $ruta = (@($pila | ForEach-Object { $_.Clave }) + $m.Groups[2].Value) -join '.'
      if ($ruta -cmatch '^spring\.batch\.job\.names?$') { $valor = $m.Groups[3].Value }
      else { $pila.Add([pscustomobject]@{ Sangria = $sangria; Clave = $m.Groups[2].Value }) }
    }
    if ($null -eq $valor) { continue }
    $valor = ([regex]::Replace($valor, '\s+#.*$', '')).Trim().Trim('"', "'")
    $nombres = @($valor -split '\s*,\s*' | Where-Object { $_ -and $_ -notmatch '^\$\{' })
    if ($nombres.Count -gt 0) { return [pscustomobject]@{ Nombres = $nombres; Linea = ($i + 1) } }
  }
  return $null
}

# Los perfiles de Spring del original: los application-<perfil> (yml, yaml, properties) y las clases con @Profile("<perfil>") o
# @Profile({"a", "<perfil>"}), con su fichero y su linea. Un @Profile en un comentario no cuenta.
function Get-IndicePerfiles([string]$Raiz) {
  $yml = @{}
  $clases = @{}
  foreach ($f in @(Get-ArbolLanzador $Raiz)) {
    $m = [regex]::Match($f.Nombre, '^application-(.+)\.(?:yml|yaml|properties)$')
    if ($m.Success) {
      $p = $m.Groups[1].Value
      if (-not $yml.ContainsKey($p)) { $yml[$p] = @() }
      $yml[$p] += $f
      continue
    }
    if ($f.Ext -ne '.java') { continue }
    $t = [System.IO.File]::ReadAllText($f.Ruta)
    if (-not $t.Contains('@Profile')) { continue }
    $t = [regex]::Replace($t, '/\*.*?\*/|//[^\n]*', { param($x) [regex]::Replace($x.Value, '[^\r\n]', ' ') }, 'Singleline')
    foreach ($a in [regex]::Matches($t, '@Profile\s*\(([^)]*)\)')) {
      $linea = ($t.Substring(0, $a.Index) -split "`n").Count
      foreach ($n in [regex]::Matches($a.Groups[1].Value, '"([\w.\-]+)"')) {
        $p = $n.Groups[1].Value
        if (-not $clases.ContainsKey($p)) { $clases[$p] = @() }
        if (@($clases[$p] | Where-Object { $_.Rel -ceq $f.Rel }).Count -eq 0) { $clases[$p] += [pscustomobject]@{ Rel = $f.Rel; Linea = $linea } }
      }
    }
  }
  return [pscustomobject]@{ Yml = $yml; Clases = $clases }
}

# Con que job se enlaza un script ($Rel, su inventario) y como: jobs, como (argumento, yml, profile, unico o sin-enlazar), fichero y linea.
# $Jobs son los del contrato (nombre y definidoEn); $Indice, el de Get-IndicePerfiles.
function Get-JobLanzador([string]$Rel, $Inventario, $Jobs, $Indice) {
  $enlace = { param($Nombres, [string]$Como, [string]$Fichero, [int]$Linea) return [ordered]@{ jobs = @($Nombres); como = $Como; fichero = $Fichero; linea = $Linea } }
  $explicito = @($Inventario | Where-Object { $_.tipo -eq 'job' })
  if ($explicito.Count -gt 0) { return (& $enlace @($explicito[0].detalle -split ',') 'argumento' $Rel $explicito[0].linea) }
  $perfiles = @()
  foreach ($i in @($Inventario | Where-Object { $_.tipo -eq 'perfil' })) { $perfiles += @($i.detalle -split ',' | Where-Object { $_ -and $_ -notmatch '\$' }) }
  foreach ($p in $perfiles) {
    if (-not $Indice.Yml.ContainsKey($p)) { continue }
    foreach ($f in @($Indice.Yml[$p])) {
      $c = Get-JobEnConfiguracion $f.Ruta
      if ($c) { return (& $enlace $c.Nombres 'yml' $f.Rel $c.Linea) }
    }
  }
  foreach ($p in $perfiles) {
    if (-not $Indice.Clases.ContainsKey($p)) { continue }
    foreach ($c in @($Indice.Clases[$p])) {
      $definen = @($Jobs | Where-Object { ("$($_.definidoEn)" -replace '\\', '/') -ceq $c.Rel } | ForEach-Object { $_.nombre })
      if ($definen.Count -gt 0) { return (& $enlace $definen 'profile' $c.Rel $c.Linea) }
    }
  }
  if (@($Jobs).Count -eq 1) { return (& $enlace @(@($Jobs)[0].nombre) 'unico' ("$(@($Jobs)[0].definidoEn)" -replace '\\', '/') 0) }
  return (& $enlace @() 'sin-enlazar' '' 0)
}

# Los lanzadores del original ($Raiz) y de la carpeta de -Lanzadores ($Extra, si la hay), cada uno con su id (sh-<hash de su ruta relativa>),
# su inventario y su enlace. $Jobs son los del contrato (Get-JobsContrato).
function Get-Lanzadores([string]$Raiz, [string]$Extra, $Jobs) {
  $indice = Get-IndicePerfiles $Raiz
  $ficheros = @(Get-FicherosLanzador $Raiz)
  if ($Extra) { $ficheros += @(Get-FicherosLanzador $Extra '-Lanzadores/') }
  $res = @()
  foreach ($f in $ficheros) {
    $lineas = @(Get-LineasShell $f.Ruta)
    $inv = @(Get-InventarioLanzador $lineas)
    $res += [pscustomobject]@{
      id = ('sh-' + (Get-Hash8 $f.Rel)); rel = $f.Rel; ruta = $f.Ruta; interprete = $f.Interprete; lineas = $lineas.Count
      inventario = $inv; enlace = [pscustomobject](Get-JobLanzador $f.Rel $inv $Jobs $indice)
    }
  }
  return $res
}
