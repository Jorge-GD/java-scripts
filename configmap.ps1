<#
configmap.ps1 - El repo de configmap del batch migrado (pieza C9). No se ejecuta solo: solo funciones. Se carga con
'. (Join-Path $PSScriptRoot 'configmap.ps1')' despues de comun.ps1, tareas.ps1 y propiedades.ps1. Solo ASCII. Vale para Windows PowerShell 5.1
y para PowerShell 7.

  Invoke-FaseConfigMap <batch de referencia> <migrado> <repo de configmap de referencia> <inventario del original> [ConservarAtascadas]
      Escribe junto al migrado el repo de configmap nuevo (sin git init ni commit), adaptado del de referencia, y devuelve Codigo (0 bien,
      1 no pudo arrancar), Ruta, Pendientes y Atascadas. Deja datos\configmap.json (lo que ha hecho y el hash de cada fichero escrito) y
      <repo nuevo>\PENDIENTE.md (lo que queda por poner). Sin cambios en las entradas, un relanzamiento no llama a Copilot (huella de cada
      tarea).

  Que hace el script y que hace la IA
      El script solo hace fontaneria y guardas: los nombres (la parte del nombre que cambia entre la referencia y el migrado), leer los
      ${...} del migrado, leer los *.properties del inventario, lanzar las tareas y comprobarlas. NO relaciona nada del inventario con las
      variables ni conoce el formato de los ficheros: copiar, dar formato, emparejar y adaptar lo hacen las tareas de IA (tareas\configmap-*.md).
        configmap-variables   todas las variables, en tandas de 10: cada una con una clave del inventario (de una lista cerrada, sin valores) o
                              'ninguna', y si es secreta
        configmap-entorno     una por entorno (cada carpeta de config\ de la referencia): escribe config\<entorno>\ con la tabla del entorno
        configmap-plataforma  una por fichero de las carpetas de punto de la referencia (menos .git)
        configmap-revision    una por entorno y una para la plataforma: hallazgos con cita comprobada; si toca un fichero, se deshace
      Lo que no esta en config\ ni en una carpeta de punto se copia con el nombre cambiado y sin IA.

  Guardas (las comprueba el script, siempre)
      (a) cada variable no secreta sale en algun fichero del entorno, con su valor en su linea (o con <PENDIENTE> si no se sabe);
      (b) cada variable secreta sale y no lleva valor; (c) ningun valor de un secreto del inventario sale en ningun fichero del repo nuevo
      (si sale, el fichero se borra); (d) el nombre del batch de referencia no queda en ningun sitio. En la plataforma, ademas, el fichero no
      esta vacio y, si es yml, lleva las mismas claves de primer nivel que el de referencia. Una tarea que falla se reintenta una vez con el
      motivo; si vuelve a fallar queda atascada. El valor de un secreto no sale nunca en un prompt, un fichero, un registro ni la consola.
#>

# ============================ CONFIGURACION ============================
$Cfg += @{
  # Una variable o una clave del inventario es secreta si su ultimo trozo (lo que va detras del ultimo punto) cumple esta regex. Es una red de seguridad.
  ConfigMapSecretos          = '(?i)pass|pwd|secret|credential|apikey|clave|contrasen|user(name)?$|usuario$'
  ConfigMapReferencia        = ''     # el repo de configmap de referencia; migracion.ps1 lo pregunta la primera vez y lo guarda en ajustes.json
  ConfigMapVariablesPorTarea = 10     # variables como mucho en cada tarea configmap-variables
  ConfigMapHallazgosMax      = 5      # hallazgos como mucho en cada revision
}
$CmMinLetras = 4        # la parte del nombre que cambia tiene que tener al menos estas letras
$CmMinSecreto = 4       # un valor de un secreto con menos caracteres no se vigila (saldria en cualquier sitio)
$CmMarca = '<PENDIENTE(?::[^>]*)?>'
$CmE = [string][char]0xE9
$CmI = [string][char]0xED
$CmO = [string][char]0xF3
$CmSecretos = New-Object 'System.Collections.Generic.List[string]'   # los valores de los secretos del inventario, de esta pasada
$CmParte = $null                                                     # la parte distintiva (R y M) de esta pasada

# ================================ NOMBRES ================================
# Los trozos de un nombre separados por - o _, con donde empiezan.
function Get-TrozosNombre([string]$Nombre) {
  return @([regex]::Matches($Nombre, '[^-_]+') | ForEach-Object { [pscustomobject]@{ Texto = $_.Value; Indice = $_.Index; Largo = $_.Length } })
}

# La parte distintiva de dos nombres (el de la referencia R y el del migrado M): lo que queda al quitar los trozos iguales del principio y del
# final (sin distinguir mayusculas). Devuelve R y M (con sus separadores) o $null si uno es el otro o esta dentro del otro.
function Get-ParteDistintiva([string]$R, [string]$M) {
  $tr = @(Get-TrozosNombre $R)
  $tm = @(Get-TrozosNombre $M)
  $n = [math]::Min($tr.Count, $tm.Count)
  $ini = 0
  while ($ini -lt $n -and $tr[$ini].Texto -ieq $tm[$ini].Texto) { $ini++ }
  $fin = 0
  while ($fin -lt ($n - $ini) -and $tr[$tr.Count - 1 - $fin].Texto -ieq $tm[$tm.Count - 1 - $fin].Texto) { $fin++ }
  $ur = $tr.Count - 1 - $fin
  $um = $tm.Count - 1 - $fin
  if ($ur -lt $ini -or $um -lt $ini) { return $null }
  return [pscustomobject]@{
    R = $R.Substring($tr[$ini].Indice, $tr[$ur].Indice + $tr[$ur].Largo - $tr[$ini].Indice)
    M = $M.Substring($tm[$ini].Indice, $tm[$um].Indice + $tm[$um].Largo - $tm[$ini].Indice)
  }
}

# La regex (sin distinguir mayusculas) de una parte: sus trozos, con - o _ entre ellos.
function Get-PatronParte([string]$Parte) {
  return ('(?i)' + ((@(Get-TrozosNombre $Parte) | ForEach-Object { [regex]::Escape($_.Texto) }) -join '[-_]'))
}

function Get-FormaTrozo([string]$T) {
  if ($T -ceq $T.ToUpperInvariant() -and $T -cne $T.ToLowerInvariant()) { return 'U' }
  if ($T -ceq $T.ToLowerInvariant()) { return 'L' }
  return 'C'
}

# Cambia R* por M* en $Texto, sin distinguir mayusculas y respetando la forma de cada trozo (minusculas, MAYUSCULAS o Capital) y sus separadores.
function Convert-ParteConfigMap([string]$Texto, $Parte) {
  $tm = @(Get-TrozosNombre $Parte.M | ForEach-Object { $_.Texto })
  $sepsM = @([regex]::Matches($Parte.M, '[-_]') | ForEach-Object { $_.Value })
  $nr = @(Get-TrozosNombre $Parte.R).Count
  $evaluador = [System.Text.RegularExpressions.MatchEvaluator]{
    param($m)
    $orig = @([regex]::Matches($m.Value, '[^-_]+') | ForEach-Object { $_.Value })
    $seps = @([regex]::Matches($m.Value, '[-_]') | ForEach-Object { $_.Value })
    $res = ''
    for ($k = 0; $k -lt $tm.Count; $k++) {
      if ($k -gt 0) {
        if ($nr -eq $tm.Count -and $seps.Count -ge $k) { $res += $seps[$k - 1] }
        elseif ($sepsM.Count -ge $k) { $res += $sepsM[$k - 1] }
        else { $res += '-' }
      }
      $molde = $orig[[math]::Min($k, $orig.Count - 1)]
      $forma = Get-FormaTrozo $molde
      $t = $tm[$k]
      if ($forma -ceq 'U') { $t = $t.ToUpperInvariant() }
      elseif ($forma -ceq 'L') { $t = $t.ToLowerInvariant() }
      else { $t = $t.Substring(0, 1).ToUpperInvariant() + $t.Substring(1).ToLowerInvariant() }
      $res += $t
    }
    return $res
  }
  return [regex]::Replace($Texto, (Get-PatronParte $Parte.R), $evaluador)
}

# El nombre del repo nuevo: el de referencia $C con R* cambiado por M*; si no lleva R*, <migrado>-configmap.
function Get-NombreConfigMap([string]$C, $Parte, [string]$M) {
  if ($Parte -and [regex]::IsMatch($C, (Get-PatronParte $Parte.R))) { return (Convert-ParteConfigMap $C $Parte) }
  return ($M + '-configmap')
}

# ================================ SECRETOS ================================
# Es secreto el nombre cuyo ultimo trozo (lo que va detras del ultimo punto) cumple $Cfg.ConfigMapSecretos.
function Test-NombreSecretoConfigMap([string]$Nombre) {
  if (-not $Nombre) { return $false }
  $ultimo = ($Nombre -split '\.')[-1]
  return [bool]($ultimo -match [string]$Cfg.ConfigMapSecretos)
}

# $Texto sin ningun valor de secreto (cada uno cambia por ***).
function Hide-SecretosConfigMap([string]$Texto) {
  foreach ($v in $CmSecretos) { if ($v) { $Texto = $Texto.Replace($v, '***') } }
  return $Texto
}

# Lee un fichero como texto: UTF-8 y, si no lo es, Latin-1 (los .properties de Java 8 suelen serlo).
function Read-TextoConfigMap([string]$Ruta) {
  $b = [System.IO.File]::ReadAllBytes($Ruta)
  try { $t = (New-Object System.Text.UTF8Encoding($false, $true)).GetString($b) }
  catch { $t = [System.Text.Encoding]::GetEncoding(28591).GetString($b) }
  if ($t.Length -gt 0 -and $t[0] -eq [char]0xFEFF) { $t = $t.Substring(1) }
  return $t
}

function Get-Sha256Hex([byte[]]$Bytes) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { $h = $sha.ComputeHash($Bytes) } finally { $sha.Dispose() }
  return ((@($h) | ForEach-Object { $_.ToString('x2') }) -join '')
}

# Todos los ficheros de $Raiz (rutas con /, en orden), sin entrar en las carpetas de $Saltar.
function Get-FicherosSinGit([string]$Raiz, [string[]]$Saltar = @('.git')) {
  $res = New-Object 'System.Collections.Generic.List[string]'
  if (-not (Test-Path -LiteralPath $Raiz -PathType Container)) { return @() }
  $pila = New-Object 'System.Collections.Generic.Stack[string]'
  $pila.Push($Raiz)
  while ($pila.Count -gt 0) {
    $d = $pila.Pop()
    foreach ($f in @(Get-ChildItem -LiteralPath $d -File -Force)) { $res.Add((Get-Rel $Raiz $f.FullName)) }
    foreach ($s in @(Get-ChildItem -LiteralPath $d -Directory -Force)) { if ($Saltar -notcontains $s.Name) { $pila.Push($s.FullName) } }
  }
  $res.Sort([System.StringComparer]::Ordinal)
  return $res.ToArray()
}

# Ficheros de $Rels (en $Dir) con el valor de un secreto del inventario: se borran. Devuelve un mensaje por fichero (sin el valor).
function Get-ProblemasSecretosConfigMap([string]$Dir, [string[]]$Rels) {
  $res = @()
  foreach ($rel in $Rels) {
    $ruta = Join-Ruta $Dir $rel
    if (-not (Test-Path -LiteralPath $ruta -PathType Leaf)) { continue }
    $t = Read-TextoConfigMap $ruta
    $sale = $false
    foreach ($v in $CmSecretos) { if ($v -and $t.Contains($v)) { $sale = $true; break } }
    if (-not $sale) { continue }
    Remove-Item -LiteralPath $ruta -Force
    $res += "$rel llevaba el valor de un secreto del inventario (no lo copio aqui) y lo he borrado: un secreto va solo como referencia a un Secret, nunca con su valor."
  }
  return $res
}

# ================================ VARIABLES ================================
# Los ${X} del migrado (application*.yml|yaml|properties de src/main/resources) que no se resuelven dentro de esos mismos ficheros: una por nombre, con
# el fichero, la linea y el texto de la linea del primer sitio donde sale (primero los ficheros sin perfil), en orden de nombre.
function Get-VariablesConfigMap([string]$Migrado) {
  $fallos = New-Object 'System.Collections.Generic.List[string]'
  $ficheros = @(Get-FicherosPropiedades $Migrado $false $fallos)
  $props = @(Read-PropiedadesLado $ficheros $fallos)
  $conocidas = New-Object 'System.Collections.Generic.HashSet[string]'
  foreach ($p in $props) { [void]$conocidas.Add((ConvertTo-ClaveCanonica $p.clave)) }
  $lineas = @{}
  foreach ($f in $ficheros) { $lineas[$f.Rel] = @($f.Texto -split '\r?\n') }
  $vistas = New-Object 'System.Collections.Generic.Dictionary[string,object]'
  foreach ($sinPerfil in @($true, $false)) {
    foreach ($p in $props) {
      if (($p.perfil -ceq 'default') -ne $sinPerfil) { continue }
      foreach ($m in [regex]::Matches([string]$p.valor, '\$\{\s*([^}:\s]+)')) {
        $n = $m.Groups[1].Value
        if ($vistas.ContainsKey($n) -or $conocidas.Contains((ConvertTo-ClaveCanonica $n))) { continue }
        $texto = ''
        $ls = $lineas[$p.fichero]
        if ($ls -and $p.linea -ge 1 -and $p.linea -le $ls.Count) { $texto = $ls[$p.linea - 1].Trim() }
        $vistas[$n] = [pscustomobject]@{ variable = $n; fichero = $p.fichero; linea = [int]$p.linea; texto = $texto }
      }
    }
  }
  $res = New-Object 'System.Collections.Generic.List[object]'
  foreach ($v in $vistas.Values) { $res.Add($v) }
  $res.Sort([System.Comparison[object]]{ param($a, $b) [string]::CompareOrdinal($a.variable, $b.variable) })
  return $res.ToArray()
}

# ================================ INVENTARIO ================================
# Por entorno: Tiene (hay carpeta del mismo nombre en el inventario, sin distinguir mayusculas), Claves (clave -> valor) y Secretos (los valores de
# las claves secretas de 4 o mas caracteres). Solo se leen los *.properties de esa carpeta; nunca vault*, group_vars, host ni nada mas.
function Read-InventarioConfigMap([string]$Inv, [string[]]$Entornos) {
  $res = [ordered]@{}
  $carpetas = @(Get-ChildItem -LiteralPath $Inv -Directory)
  foreach ($e in $Entornos) {
    $o = [pscustomobject]@{ Entorno = $e; Tiene = $false; Claves = (New-Object 'System.Collections.Generic.Dictionary[string,string]'); Secretos = (New-Object 'System.Collections.Generic.List[string]') }
    $c = @($carpetas | Where-Object { $_.Name -ieq $e })
    if ($c.Count -gt 0) {
      $o.Tiene = $true
      $fs = @(Get-ChildItem -LiteralPath $c[0].FullName -File | Where-Object { $_.Extension -ieq '.properties' -and $_.Name -notlike 'vault*' } | Sort-Object Name)
      foreach ($f in $fs) {
        $lineas = @((Read-TextoConfigMap $f.FullName) -split '\r?\n')
        foreach ($p in @(Read-PropiedadesProperties ($c[0].Name + '/' + $f.Name) $lineas 'default')) {
          if ($o.Claves.ContainsKey($p.clave)) { continue }
          $o.Claves[$p.clave] = [string]$p.valor
          if ((Test-NombreSecretoConfigMap $p.clave) -and ([string]$p.valor).Length -ge $CmMinSecreto) { $o.Secretos.Add([string]$p.valor) }
        }
      }
    }
    $res[$e] = $o
  }
  return $res
}

# Las claves de todos los entornos del inventario, sin repetir y en orden: la lista cerrada de la tarea de variables (sin valores).
function Get-ClavesInventarioConfigMap($Inv) {
  $l = New-Object 'System.Collections.Generic.List[string]'
  $hs = New-Object 'System.Collections.Generic.HashSet[string]'
  foreach ($o in $Inv.Values) { foreach ($k in $o.Claves.Keys) { if ($hs.Add($k)) { $l.Add($k) } } }
  $l.Sort([System.StringComparer]::Ordinal)
  return $l.ToArray()
}

# ============================ REFERENCIA ============================
# Los ficheros del repo de configmap de referencia: Entornos (carpeta de config\ -> sus ficheros), Punto (los de las carpetas de punto, menos .git) y
# Sueltos (todo lo demas). Rutas con /.
function Get-FicherosReferenciaConfigMap([string]$Ref) {
  $entornos = [ordered]@{}
  $punto = New-Object 'System.Collections.Generic.List[string]'
  $sueltos = New-Object 'System.Collections.Generic.List[string]'
  $dirConfig = Join-Path $Ref 'config'
  if (Test-Path -LiteralPath $dirConfig -PathType Container) {
    foreach ($d in @(Get-ChildItem -LiteralPath $dirConfig -Directory | Sort-Object Name)) { $entornos[$d.Name] = New-Object 'System.Collections.Generic.List[string]' }
  }
  foreach ($rel in @(Get-FicherosSinGit $Ref)) {
    $s = $rel.Split('/')
    if ($s[0] -ceq 'config' -and $s.Count -ge 3 -and $entornos.Contains($s[1])) { $entornos[$s[1]].Add($rel) }
    elseif ($s[0].StartsWith('.') -and $s.Count -ge 2) { $punto.Add($rel) }
    else { $sueltos.Add($rel) }
  }
  return [pscustomobject]@{ Entornos = $entornos; Punto = $punto.ToArray(); Sueltos = $sueltos.ToArray() }
}

# ================================ TABLAS ================================
# Por variable y entorno: estado 'valor' (con su valor), 'secreto' (sin valor) o 'pendiente'. Pares: variable -> clave del inventario (la que ha dicho la IA).
function Get-TablaEntornoConfigMap($Variables, $Pares, $Secretas, $InvEntorno) {
  $res = @()
  foreach ($v in $Variables) {
    $n = $v.variable
    $clave = ''
    if ($Pares.ContainsKey($n)) { $clave = [string]$Pares[$n] }
    $fila = [pscustomobject]@{ variable = $n; clave = $clave; estado = 'pendiente'; valor = '' }
    if ($Secretas.ContainsKey($n)) { $fila.estado = 'secreto' }
    elseif ($clave -and $InvEntorno.Tiene -and $InvEntorno.Claves.ContainsKey($clave)) {
      $val = (([string]$InvEntorno.Claves[$clave]) -replace '\r?\n', ' ').Trim()
      if ($val) { $fila.estado = 'valor'; $fila.valor = $val }
    }
    $res += $fila
  }
  return $res
}

# La tabla de un entorno como texto para el prompt: una variable por linea, sin ningun valor de secreto.
function Get-TextoTablaConfigMap($Tabla) {
  $filas = @($Tabla)
  if ($filas.Count -eq 0) { return '(el batch no lee ninguna variable)' }
  return ((@($filas | ForEach-Object {
          if ($_.estado -ceq 'secreto') { "- $($_.variable) (secreto, sin valor)" }
          elseif ($_.estado -ceq 'valor') { "- $($_.variable) = $($_.valor)" }
          else { "- $($_.variable) = <PENDIENTE>" }
        })) -join "`n")
}

# Las diferencias entre entornos: una clave del inventario que usa alguna variable, que esta en el inventario de unos entornos y no en el de otros.
function Get-DiferenciasConfigMap($Pares, $Inv) {
  $res = @()
  $conInv = @($Inv.Values | Where-Object { $_.Tiene })
  if ($conInv.Count -lt 2) { return @() }
  $claves = New-Object 'System.Collections.Generic.List[string]'
  foreach ($k in @($Pares.Values)) { if ($k -and -not $claves.Contains([string]$k)) { $claves.Add([string]$k) } }
  $claves.Sort([System.StringComparer]::Ordinal)
  foreach ($k in $claves) {
    $tiene = @($conInv | Where-Object { $_.Claves.ContainsKey($k) } | ForEach-Object { $_.Entorno.ToUpperInvariant() })
    $no = @($conInv | Where-Object { -not $_.Claves.ContainsKey($k) } | ForEach-Object { $_.Entorno.ToUpperInvariant() })
    if ($tiene.Count -gt 0 -and $no.Count -gt 0) { $res += (($no -join ', ') + ' no tiene `' + $k + '`; ' + ($tiene -join ', ') + ' s' + $CmI) }
  }
  return $res
}

# ================================ YML ================================
# Lo que se compara de un yml: Tipo ('mapa', 'lista' u 'otro'), Claves (las del primer nivel de un mapa) y Elementos (de una lista, el conjunto de claves
# de cada elemento, sin repetir: no cuenta cuantos elementos hay).
function Get-EstructuraYml([string]$Texto) {
  $rx = '^(?:"([^"]+)"|''([^'']+)''|([^\s"''#\-\[\{][^:]*?))\s*:(?:\s|$)'
  $claves = New-Object 'System.Collections.Generic.List[string]'
  $conjuntos = New-Object 'System.Collections.Generic.List[string]'
  $elem = $null
  $col = 0
  $esLista = $false
  $cierra = {
    if ($null -ne $elem) {
      $c = ((@($elem | Sort-Object -Unique)) -join ',')
      if (-not $conjuntos.Contains($c)) { $conjuntos.Add($c) }
    }
  }
  foreach ($l in @($Texto -split '\r?\n')) {
    if ($l -match '^\s*(#.*)?$' -or $l -match '^(---|\.\.\.)\s*$') { continue }
    if ($l -match '^-(\s|$)') {
      & $cierra
      $esLista = $true
      $elem = New-Object 'System.Collections.Generic.List[string]'
      $resto = $l.Substring(1)
      $corte = $resto.TrimStart()
      $col = 1 + ($resto.Length - $corte.Length)
      $m = [regex]::Match($corte, $rx)
      if ($m.Success) { $elem.Add(($m.Groups[1].Value + $m.Groups[2].Value + $m.Groups[3].Value).Trim()) }
      continue
    }
    if ($l -match '^\S') {
      & $cierra
      $elem = $null
      $m = [regex]::Match($l, $rx)
      if ($m.Success) { $claves.Add(($m.Groups[1].Value + $m.Groups[2].Value + $m.Groups[3].Value).Trim()) }
      continue
    }
    if ($null -ne $elem -and ($l.Length - $l.TrimStart().Length) -eq $col) {
      $m = [regex]::Match($l.Trim(), $rx)
      if ($m.Success) { $elem.Add(($m.Groups[1].Value + $m.Groups[2].Value + $m.Groups[3].Value).Trim()) }
    }
  }
  & $cierra
  $tipo = 'otro'
  if ($esLista) { $tipo = 'lista' } elseif ($claves.Count -gt 0) { $tipo = 'mapa' }
  $ordenadas = @($claves | Sort-Object -Unique)
  $elementos = @($conjuntos | Sort-Object)
  return [pscustomobject]@{ Tipo = $tipo; Claves = $ordenadas; Elementos = $elementos }
}

# '' si $Nuevo tiene la misma estructura que $Ref (Get-EstructuraYml) o el motivo si no. Una referencia sin estructura no compara.
function Compare-EstructuraYml($Ref, $Nuevo) {
  if ($Ref.Tipo -ceq 'otro') { return '' }
  if ($Nuevo.Tipo -cne $Ref.Tipo) {
    if ($Ref.Tipo -ceq 'lista') { return 'el primer nivel de la referencia es una lista y el tuyo no.' }
    return 'el primer nivel de la referencia es un mapa de claves y el tuyo no.'
  }
  if ($Ref.Tipo -ceq 'mapa') {
    $faltan = @($Ref.Claves | Where-Object { @($Nuevo.Claves) -cnotcontains $_ })
    $sobran = @($Nuevo.Claves | Where-Object { @($Ref.Claves) -cnotcontains $_ })
    $m = @()
    if ($faltan.Count -gt 0) { $m += ('falta la clave de primer nivel ' + (($faltan | ForEach-Object { "'$_'" }) -join ', ')) }
    if ($sobran.Count -gt 0) { $m += ('sobra la clave de primer nivel ' + (($sobran | ForEach-Object { "'$_'" }) -join ', ')) }
    if ($m.Count -gt 0) { return (($m -join '; ') + '. Las claves de primer nivel son las de la referencia: ' + ((@($Ref.Claves) | ForEach-Object { "'$_'" }) -join ', ') + '.') }
    return ''
  }
  if ((@($Ref.Elementos) -join '|') -cne (@($Nuevo.Elementos) -join '|')) {
    return ('cada elemento de la lista de primer nivel lleva las claves de la referencia (' + ((@($Ref.Elementos) | ForEach-Object { "[$_]" }) -join ' ') + ') y los tuyos llevan: ' + ((@($Nuevo.Elementos) | ForEach-Object { "[$_]" }) -join ' ') + '.')
  }
  return ''
}

# ============================ COMPROBACIONES ============================
function Test-QuedaParte([string]$Texto) {
  $sin = [regex]::Replace($Texto, (Get-PatronParte $CmParte.M), '')
  return [regex]::IsMatch($sin, (Get-PatronParte $CmParte.R))
}

function New-MotivoConfigMap($Problemas) {
  $p = @($Problemas)
  $m = (@($p | Select-Object -First 8) | ForEach-Object { "- $_" }) -join "`n"
  if ($p.Count -gt 8) { $m += "`n- y $($p.Count - 8) problemas mas." }
  return $m
}

# (a), (b), (c) y (d) de una tarea de entorno: Dir es la carpeta del repo nuevo.
function Test-SalidaEntornoConfigMap($T, [string]$Dir) {
  $e = $T.entradas
  $p = New-Object 'System.Collections.Generic.List[string]'
  $textos = [ordered]@{}
  foreach ($rel in @($e.ficheros)) {
    $ruta = Join-Ruta $Dir $rel
    if (-not (Test-Path -LiteralPath $ruta -PathType Leaf)) { $p.Add("Falta el fichero $rel."); continue }
    $t = Read-TextoConfigMap $ruta
    if (-not $t.Trim() -and @($e.vacios) -cnotcontains $rel) { $p.Add("El fichero $rel esta vacio."); continue }
    $textos[$rel] = $t
  }
  # (c) un valor de un secreto del inventario no sale en ningun fichero de la carpeta del entorno
  $revisar = @($e.ficheros) + @(Get-FicherosSinGit (Join-Ruta $Dir $e.carpeta) | ForEach-Object { $e.carpeta + '/' + $_ })
  foreach ($m in @(Get-ProblemasSecretosConfigMap $Dir @($revisar | Select-Object -Unique))) { $p.Add($m) }
  foreach ($rel in @($textos.Keys)) { if (-not (Test-Path -LiteralPath (Join-Ruta $Dir $rel))) { $textos.Remove($rel) } }
  $lineas = @()
  foreach ($t in $textos.Values) { $lineas += @($t -split '\r?\n') }
  # (a) y (b) cada variable de la tabla sale en algun fichero: la no secreta con su valor (o con <PENDIENTE>) en su linea; la secreta sin valor
  foreach ($f in @($e.tabla)) {
    $re = '(?<![\w\-])' + [regex]::Escape($f.variable) + '(?![\w.\-])'
    $suyas = @($lineas | Where-Object { [regex]::IsMatch($_, $re) })
    if ($suyas.Count -eq 0) { $p.Add("La variable $($f.variable) no sale en ningun fichero de $($e.carpeta)."); continue }
    if ($f.estado -ceq 'secreto') {
      $conValor = @($suyas | Where-Object { [regex]::IsMatch($_, $re + '\s*[=:]\s*(?!<PENDIENTE)\S') })
      if ($conValor.Count -gt 0) { $p.Add("La variable $($f.variable) es secreta y lleva un valor: va solo como referencia a un Secret, sin valor.") }
    }
    elseif ($f.estado -ceq 'valor') {
      if (@($suyas | Where-Object { $_.Contains($f.valor) }).Count -eq 0) { $p.Add("La variable $($f.variable) no lleva su valor ($($f.valor)) en su linea.") }
    }
    elseif (@($suyas | Where-Object { $_ -match '<PENDIENTE' }).Count -eq 0) {
      $p.Add("La variable $($f.variable) no tiene valor conocido: su valor es <PENDIENTE>, no inventes uno.")
    }
  }
  # (d) el nombre del batch de referencia no queda
  foreach ($rel in @($textos.Keys)) {
    if (Test-QuedaParte $textos[$rel]) { $p.Add("$rel todavia lleva el nombre del batch de referencia ($($CmParte.R)): cambialo por $($CmParte.M).") }
  }
  if ($p.Count -gt 0) { return (New-Resultado $false (New-MotivoConfigMap $p) $null) }
  return (New-Resultado $true '' $null)
}

# (c), (d), no vacio y, si es yml, la misma estructura de primer nivel que la referencia.
function Test-SalidaPlataformaConfigMap($T, [string]$Dir) {
  $e = $T.entradas
  $rel = [string]$e.ficheroDestino
  $ruta = Join-Ruta $Dir $rel
  if (-not (Test-Path -LiteralPath $ruta -PathType Leaf)) { return (New-Resultado $false "No has escrito el fichero $rel." $null) }
  $p = New-Object 'System.Collections.Generic.List[string]'
  foreach ($m in @(Get-ProblemasSecretosConfigMap $Dir @($rel))) { $p.Add($m) }
  if (Test-Path -LiteralPath $ruta -PathType Leaf) {
    $t = Read-TextoConfigMap $ruta
    if (-not $t.Trim()) { $p.Add("El fichero $rel esta vacio.") }
    else {
      if (Test-QuedaParte $t) { $p.Add("$rel todavia lleva el nombre del batch de referencia ($($CmParte.R)): cambialo por $($CmParte.M).") }
      if ($e.estructura) {
        $m = Compare-EstructuraYml $e.estructura (Get-EstructuraYml $t)
        if ($m) { $p.Add("${rel}: $m") }
      }
    }
  }
  if ($p.Count -gt 0) { return (New-Resultado $false (New-MotivoConfigMap $p) $null) }
  return (New-Resultado $true '' $null)
}

function ConvertTo-BoolConfigMap($V) {
  if ($V -is [bool]) { return $V }
  $s = ("$V").Trim().ToLowerInvariant()
  if (@('true', 'si', ('s' + $CmI), 's', 'yes') -contains $s) { return $true }
  if (@('false', 'no', 'n') -contains $s) { return $false }
  return $null
}

# Una respuesta por cada variable pedida, con una clave de la lista cerrada o 'ninguna'.
function Test-SalidaVariablesConfigMap($T, [string]$Dir) {
  $s = Read-Salida $T $Dir
  if (-not $s.Ok) { return $s }
  if ($s.Ficha.variables -isnot [array]) { return (New-Resultado $false "Falta el campo 'variables': una lista con una respuesta por variable." $null) }
  $pedidas = @($T.entradas.variables)
  $claves = @($T.entradas.claves)
  $vistas = New-Object 'System.Collections.Generic.HashSet[string]'
  $p = New-Object 'System.Collections.Generic.List[string]'
  $res = @()
  $i = 0
  foreach ($r in $s.Ficha.variables) {
    $pre = "variables[$i]"
    $i++
    if ($r -isnot [System.Management.Automation.PSCustomObject]) { $p.Add("$pre no es un objeto con variable, clave y secreto."); continue }
    $n = [string]$r.variable
    if ($pedidas -cnotcontains $n) { $p.Add("${pre}: la variable '$n' no estaba en la lista de arriba."); continue }
    if (-not $vistas.Add($n)) { $p.Add("La variable '$n' sale dos veces."); continue }
    $k = [string]$r.clave
    if ($k -cne 'ninguna' -and $claves -cnotcontains $k) { $p.Add("${n}: la clave '$k' no esta en la lista de claves del inventario. Copia una clave tal cual de la lista o escribe ninguna."); continue }
    $sec = ConvertTo-BoolConfigMap $r.secreto
    if ($null -eq $sec) { $p.Add("${n}: secreto tiene que ser true o false."); continue }
    $res += [pscustomobject]@{ variable = $n; clave = $k; secreto = [bool]$sec }
  }
  foreach ($n in $pedidas) { if (-not $vistas.Contains([string]$n)) { $p.Add("Falta la respuesta de la variable '$n'.") } }
  if ($p.Count -gt 0) { return (New-Resultado $false (New-MotivoConfigMap $p) $null) }
  return (New-Resultado $true '' ([pscustomobject]@{ variables = $res }))
}

# Un hallazgo de la revision: Motivo '' y su ficha en Hallazgo si vale (la cita sale en el fichero, cerca de su linea); si no, el motivo por el que se descarta.
function Test-HallazgoConfigMap($H, [string]$Pre, $T, [string]$Dir) {
  $no = { param($m) return [pscustomobject]@{ Motivo = $m; Hallazgo = $null } }
  if ($H -isnot [System.Management.Automation.PSCustomObject]) { return (& $no "$Pre no es un objeto con fichero, linea, cita y problema.") }
  if (@($T.entradas.ficheros) -cnotcontains $H.fichero) { return (& $no "${Pre}: el fichero '$($H.fichero)' no es de la unidad.") }
  $m = Test-LineaCita $H $Pre
  if ($m) { return (& $no $m) }
  if (-not (Test-Texto $H.problema)) { return (& $no "$Pre.problema falta o esta vacio.") }
  $ficha = [ordered]@{ fichero = $H.fichero; linea = [int]$H.linea; cita = $H.cita; problema = $H.problema; probado = $false }
  $ruta = Join-Ruta $Dir $H.fichero
  if (-not (Test-Path -LiteralPath $ruta -PathType Leaf) -or @(Set-CitasProbadas @($ficha) $ruta).Count -gt 0) {
    return (& $no "${Pre}: la cita no sale en el fichero $($H.fichero). Copia la cita tal cual de la linea del fichero.")
  }
  return [pscustomobject]@{ Motivo = ''; Hallazgo = [pscustomobject]$ficha }
}

# La revision: un objeto con 'hallazgos'. Un hallazgo que no se puede comprobar se descarta; si se descarta mas de la mitad (y hay al menos 2), la tarea es invalida.
function Test-SalidaRevisionConfigMap($T, [string]$Dir) {
  $s = Read-Salida $T $Dir
  if (-not $s.Ok) { return $s }
  if ($s.Ficha.hallazgos -isnot [array]) { return (New-Resultado $false "Falta el campo 'hallazgos': una lista, vacia si no hay nada que decir." $null) }
  $validos = @()
  $descartados = @()
  $i = 0
  foreach ($h in $s.Ficha.hallazgos) {
    $v = Test-HallazgoConfigMap $h "hallazgos[$i]" $T $Dir
    $i++
    if ($v.Hallazgo) { $validos += $v.Hallazgo } else { $descartados += $v.Motivo }
  }
  $total = $validos.Count + $descartados.Count
  if ($total -ge 2 -and ($descartados.Count * 2) -gt $total) {
    return (New-Resultado $false "Mas de la mitad de los hallazgos ($($descartados.Count) de $total) no valen. El primero: $($descartados[0]) Copia las citas tal cual de una linea de un fichero de la unidad." $null)
  }
  $max = [int]$Cfg.ConfigMapHallazgosMax
  return (New-Resultado $true '' ([pscustomobject][ordered]@{ hallazgos = @($validos | Select-Object -First $max); descartados = $descartados.Count }))
}

function Test-SalidaConfigMap($T, [string]$Dir) {
  switch ($T.tipo) {
    'configmap-variables' { return (Test-SalidaVariablesConfigMap $T $Dir) }
    'configmap-entorno' { return (Test-SalidaEntornoConfigMap $T $Dir) }
    'configmap-plataforma' { return (Test-SalidaPlataformaConfigMap $T $Dir) }
    default { return (Test-SalidaRevisionConfigMap $T $Dir) }
  }
}

# ================================ TAREAS ================================
# Una foto de los ficheros del repo nuevo (sin .git ni .rescate), para deshacer lo que toque una lectura.
function Get-InstantaneaConfigMap([string]$Dir) {
  $res = New-Object 'System.Collections.Generic.Dictionary[string,object]'
  foreach ($rel in @(Get-FicherosSinGit $Dir @('.git', '.rescate'))) {
    $b = [System.IO.File]::ReadAllBytes((Join-Ruta $Dir $rel))
    $res[$rel] = [pscustomobject]@{ Bytes = $b; Hash = (Get-Sha256Hex $b) }
  }
  return $res
}

function Write-BytesConfigMap([string]$Ruta, [byte[]]$Bytes) {
  $d = Split-Path $Ruta -Parent
  if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -Force) }
  [System.IO.File]::WriteAllBytes($Ruta, $Bytes)
}

# Deja el repo nuevo como en la foto y devuelve las rutas que habia cambiado (tocadas, creadas o borradas).
function Restore-InstantaneaConfigMap([string]$Dir, $Antes) {
  $cambios = New-Object 'System.Collections.Generic.List[string]'
  $ahora = @(Get-FicherosSinGit $Dir @('.git', '.rescate'))
  $enAhora = New-Object 'System.Collections.Generic.HashSet[string]'
  foreach ($rel in $ahora) {
    [void]$enAhora.Add($rel)
    $ruta = Join-Ruta $Dir $rel
    if (-not $Antes.ContainsKey($rel)) { Remove-Item -LiteralPath $ruta -Force; $cambios.Add($rel); continue }
    if ((Get-Sha256Hex ([System.IO.File]::ReadAllBytes($ruta))) -cne $Antes[$rel].Hash) { Write-BytesConfigMap $ruta $Antes[$rel].Bytes; $cambios.Add($rel) }
  }
  foreach ($rel in @($Antes.Keys)) {
    if (-not $enAhora.Contains($rel)) { Write-BytesConfigMap (Join-Ruta $Dir $rel) $Antes[$rel].Bytes; $cambios.Add($rel) }
  }
  return $cambios.ToArray()
}

# Las lecturas no escriben en el repo (solo su fichero de salida): el resto de tareas si.
function Test-LecturaConfigMap($T) { return (@('configmap-variables', 'configmap-revision') -contains $T.tipo) }

# Es $Rel de la tarea $T (uno de sus ficheros o algo dentro de su carpeta)?
function Test-DuenoConfigMap($T, [string]$Rel) {
  if (@($T.entradas.ficheros) -ccontains $Rel) { return $true }
  $c = [string]$T.entradas.carpeta
  return [bool]($c -and $Rel.StartsWith($c + '/'))
}

# La tarea que queda para $T: la guardada si el usuario ha cambiado un fichero suyo (no se rehace), o esta hecha con la misma huella y sus ficheros estan, o
# esta atascada con la misma huella (con $Conservar); si no, la nueva ($T), pendiente. $Forzar descarta la guardada (una tarea de la que depende se ha rehecho).
function Get-TareaConfigMap($T, [string[]]$Salidas, $Cambiados, [bool]$Conservar, [bool]$Forzar, [string]$Dir) {
  $p = Get-TareaGuardada $T.id
  if ($p) {
    if (@($Salidas | Where-Object { @($Cambiados) -contains $_ }).Count -gt 0) { return $p }
    if (-not $Forzar -and $p.entradas.huella -ceq $T.entradas.huella) {
      $estan = (@($Salidas | Where-Object { -not (Test-Path -LiteralPath (Join-Ruta $Dir $_) -PathType Leaf) }).Count -eq 0)
      if ($p.estado -eq 'hecha' -and $estan) { return $p }
      if ($Conservar -and $p.estado -eq 'atascada') { return $p }
    }
  }
  Save-Tarea $T
  return $T
}

# Rondas de hasta Paralelo llamadas hasta que no quedan tareas pendientes. $Dir es la carpeta de trabajo de Copilot (el repo nuevo); $Migrado, lo que puede leer.
# Las tareas de lectura (variables y revision) no pueden cambiar nada: lo que toquen se deshace y la tarea es invalida.
function Invoke-TareasConfigMap($Tareas, [string]$Dir, [string]$Migrado) {
  while ($true) {
    $pend = @($Tareas | Where-Object { $_.estado -eq 'pendiente' })
    if ($pend.Count -eq 0) { break }
    $lectura = Test-LecturaConfigMap $pend[0]
    $lote = @($pend | Where-Object { (Test-LecturaConfigMap $_) -eq $lectura } | Select-Object -First ([int]$Cfg.Paralelo))
    Info ('Ronda: ' + $lote.Count + ' llamadas a la vez (quedan ' + $pend.Count + ' tareas)...')
    $antes = $null
    if ($lectura) { $antes = Get-InstantaneaConfigMap $Dir }
    $items = @()
    foreach ($t in $lote) {
      $esf = $Cfg.EsfuerzoRedaccion
      if ($lectura) { $esf = $Cfg.EsfuerzoLectura }
      $motivo = ''
      if ($t.intentos -gt 0) {
        $esf = $Cfg.EsfuerzoReintento
        if ($t.ultimoEstado -eq 'invalida') { $motivo = $t.motivo }
      }
      $items += , ([pscustomobject]@{ Id = $t.id; Dir = $Dir; Modelo = $ModeloElegido; Esfuerzo = $esf; Dirs = @($Migrado); Prompt = (Get-Prompt $t '' $motivo) })
    }
    $llamadas = @(Invoke-Llamadas $items)
    $cambios = @()
    if ($lectura) { $cambios = @(Restore-InstantaneaConfigMap $Dir $antes) }
    $sinDueno = @($cambios | Where-Object { $r = $_; @($lote | Where-Object { Test-DuenoConfigMap $_ $r }).Count -eq 0 })
    for ($i = 0; $i -lt $lote.Count; $i++) {
      $t = $lote[$i]
      $c = $llamadas[$i]
      $registro = Join-Path $Registros ($t.id + '-' + ($t.intentos + 1) + '.log')
      $cab = "# salida (codigo $($c.Codigo), $($c.Segundos) s"
      if ($c.Agotado) { $cab += ', tiempo agotado' }
      [System.IO.File]::WriteAllText($registro, (Hide-SecretosConfigMap ("# prompt`n" + $items[$i].Prompt + "`n`n" + $cab + ")`n" + $c.Texto + "`n")), $Utf8)
      $estado = 'ok'
      $motivo = ''
      $ficha = $null
      if ($c.Agotado) { $estado = 'tiempo'; $motivo = "Tiempo agotado: la llamada pasaba de $($Cfg.SegundosPorLlamada) s y se mato." }
      elseif ($c.Codigo -ne 0) { $estado = 'fallo'; $motivo = "Copilot salio con codigo $($c.Codigo): " + (Get-UltimaLinea $c.Texto) }
      else {
        $suyos = @($cambios | Where-Object { $r = $_; $sinDueno -contains $r -or (Test-DuenoConfigMap $t $r) })
        if ($lectura -and $suyos.Count -gt 0) {
          $estado = 'invalida'
          $motivo = 'La lectura toco ficheros del repositorio (' + (($suyos | Select-Object -First 3) -join '; ') + '): lo he deshecho. Lee sin cambiar nada: solo escribes el fichero de salida.'
        }
        else {
          $v = Test-SalidaConfigMap $t $Dir
          if ($v.Ok) { $ficha = $v.Ficha } else { $estado = 'invalida'; $motivo = $v.Motivo }
        }
      }
      $t.intentos++
      $t.motivo = $motivo
      $t.ultimoEstado = $estado
      if ($estado -eq 'ok') { $t.estado = 'hecha'; $t.resultado = $ficha }
      elseif ($t.intentos -ge [int]$Cfg.Intentos) {
        $t.estado = 'atascada'
        Aviso ("Atascada: $($t.id): " + (Hide-SecretosConfigMap ($motivo -replace '\r?\n', ' ')))
      }
      Save-Tarea $t
    }
  }
}

# El texto de los ficheros de referencia $Rels para un prompt: cada uno con su ruta y su contenido, con el nombre del batch ya cambiado.
function Get-TextoReferenciaConfigMap([string]$Ref, [string[]]$Rels) {
  return ((@($Rels | ForEach-Object { '===== ' + (Convert-ParteConfigMap $_ $CmParte) + " =====`n" + (Convert-ParteConfigMap (Read-TextoConfigMap (Join-Ruta $Ref $_)) $CmParte) })) -join "`n")
}

# Copia los ficheros sueltos de la referencia con el nombre cambiado (en el nombre del fichero y dentro del texto), sin IA y sin tocar los que el usuario ha cambiado.
function Copy-SueltosConfigMap([string]$Ref, [string]$Dir, [string[]]$Sueltos, $Cambiados) {
  foreach ($rel in $Sueltos) {
    $dest = Convert-ParteConfigMap $rel $CmParte
    if (@($Cambiados) -contains $dest) { continue }
    $b = [System.IO.File]::ReadAllBytes((Join-Ruta $Ref $rel))
    if ([array]::IndexOf($b, [byte]0) -lt 0) {
      try { $t = (New-Object System.Text.UTF8Encoding($false, $true)).GetString($b); $enc = New-Object System.Text.UTF8Encoding($false) }
      catch { $enc = [System.Text.Encoding]::GetEncoding(28591); $t = $enc.GetString($b) }
      $b = $enc.GetBytes((Convert-ParteConfigMap $t $CmParte))
    }
    Write-BytesConfigMap (Join-Ruta $Dir $dest) $b
  }
}

# ================================ PENDIENTE.md ================================
# Cada <PENDIENTE...> de los ficheros del repo nuevo (menos PENDIENTE.md), con su fichero y su linea.
function Get-PendientesFicherosConfigMap([string]$Dir) {
  $res = @()
  foreach ($rel in @(Get-FicherosSinGit $Dir @('.git', '.rescate'))) {
    if ($rel -ceq 'PENDIENTE.md') { continue }
    $ls = @((Read-TextoConfigMap (Join-Ruta $Dir $rel)) -split '\r?\n')
    for ($i = 0; $i -lt $ls.Count; $i++) {
      foreach ($m in [regex]::Matches($ls[$i], $CmMarca)) { $res += [pscustomobject]@{ fichero = $rel; linea = $i + 1; marca = $m.Value } }
    }
  }
  return $res
}

function Get-TextoPendienteConfigMap($D) {
  $l = New-Object 'System.Collections.Generic.List[string]'
  $tilde = [string][char]96
  $l.Add("# Pendiente de $($D.nombre)")
  $l.Add('')
  $l.Add("Lo escribe migracion.ps1 -ConfigMap en cada pasada. Resumen: $($D.pendientes.Count) pendientes en los ficheros, $($D.secretas) secretos por pedir, $($D.hallazgos.Count) hallazgos de la revision y $($D.atascadas.Count) tareas atascadas.")
  foreach ($e in $D.entornos) {
    $l.Add('')
    $l.Add('## Entorno ' + $e.nombre.ToUpperInvariant())
    $l.Add('')
    if (-not $e.inventario) { $l.Add('No hay carpeta de este entorno en el inventario: todos los valores quedan pendientes.'); $l.Add('') }
    $l.Add('| Variable | De donde sale | Estado |')
    $l.Add('|---|---|---|')
    foreach ($f in $e.tabla) {
      $origen = '-'
      if ($f.clave) { $origen = $tilde + $f.clave + $tilde + ' (inventario, IA)' }
      $estado = 'pendiente'
      if ($f.estado -ceq 'valor') { $estado = 'valor puesto' } elseif ($f.estado -ceq 'secreto') { $estado = 'secreto: hay que pedir el Secret' }
      $l.Add("| $($f.variable) | $origen | $estado |")
    }
  }
  $l.Add('')
  $l.Add('## Diferencias entre entornos')
  $l.Add('')
  if (@($D.diferencias).Count -eq 0) { $l.Add('Ninguna.') } else { foreach ($x in $D.diferencias) { $l.Add("- $x") } }
  $l.Add('')
  $l.Add('## Pendientes en los ficheros')
  $l.Add('')
  if (@($D.pendientes).Count -eq 0) { $l.Add('Ninguno.') }
  else { foreach ($x in $D.pendientes) { $l.Add("- $tilde$($x.fichero):$($x.linea)$tilde $($x.marca)") } }
  $l.Add('')
  $l.Add('## Hallazgos de la revisi' + $CmO + 'n')
  $l.Add('')
  if (@($D.hallazgos).Count -eq 0) { $l.Add('Ninguno.') }
  else { foreach ($x in $D.hallazgos) { $l.Add("- $tilde$($x.fichero):$($x.linea)$tilde $($x.problema) (cita: $tilde$($x.cita)$tilde)") } }
  $l.Add('')
  $l.Add('## Tareas atascadas')
  $l.Add('')
  if (@($D.atascadas).Count -eq 0) { $l.Add('Ninguna.') }
  else { foreach ($x in $D.atascadas) { $l.Add("- $tilde$($x.id)$tilde $($x.motivo)") } }
  $l.Add('')
  $l.Add('## Ficheros que has cambiado')
  $l.Add('')
  if (@($D.cambiados).Count -eq 0) { $l.Add('Ninguno.') }
  else {
    $l.Add('Los dejo como estan. Si quieres que se escriban otra vez, borralos y relanza.')
    $l.Add('')
    foreach ($x in $D.cambiados) { $l.Add("- $tilde$x$tilde") }
  }
  if (@($D.borrados).Count -gt 0) {
    $l.Add('')
    $l.Add('## Ficheros borrados por llevar el valor de un secreto')
    $l.Add('')
    foreach ($x in $D.borrados) { $l.Add("- $tilde$x$tilde") }
  }
  $l.Add('')
  return (Hide-SecretosConfigMap ($l -join "`n"))
}

# ================================ LA FASE ================================
function New-ResultadoFaseConfigMap([int]$Codigo, [string]$Ruta, [int]$Pendientes = 0, [int]$Atascadas = 0) {
  return [pscustomobject]@{ Codigo = $Codigo; Ruta = $Ruta; Pendientes = $Pendientes; Atascadas = $Atascadas }
}

function Get-IdPlataformaConfigMap([string]$Rel, $Usados) {
  $id = 'configmap-plataforma-' + (($Rel.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-'))
  if ($Usados.Contains($id)) { $id += '-' + (Get-Hash8 $Rel) }
  [void]$Usados.Add($id)
  return $id
}

# La fase entera. Devuelve Codigo (0 bien, 1 no pudo arrancar), Ruta del repo nuevo, Pendientes y Atascadas.
function Invoke-FaseConfigMap([string]$Plantilla, [string]$Migrado, [string]$Referencia, [string]$Inventario, [bool]$ConservarAtascadas = $false) {
  # 1. Lo que se puede comprobar sin crear nada
  if (-not $Inventario -or -not (Test-Path -LiteralPath $Inventario -PathType Container)) { Fallo "No encuentro la carpeta del inventario del original: $Inventario"; return (New-ResultadoFaseConfigMap 1 '') }
  if (-not $Referencia -or -not (Test-Path -LiteralPath $Referencia -PathType Container)) { Fallo "No encuentro el repo de configmap de referencia: $Referencia"; return (New-ResultadoFaseConfigMap 1 '') }
  $ref = Get-FicherosReferenciaConfigMap $Referencia
  if (@($ref.Entornos.Keys).Count -eq 0) { Fallo "El repo de configmap de referencia no tiene carpetas de entorno en config/: $Referencia"; return (New-ResultadoFaseConfigMap 1 '') }
  $nombreR = Split-Path $Plantilla -Leaf
  $nombreM = Split-Path $Migrado -Leaf
  $parte = Get-ParteDistintiva $nombreR $nombreM
  if (-not $parte) { Fallo "No puedo sacar la parte del nombre que cambia entre '$nombreR' y '$nombreM': uno es el otro o esta dentro del otro."; return (New-ResultadoFaseConfigMap 1 '') }
  if (($parte.R -replace '[^\p{L}]', '').Length -lt $CmMinLetras) {
    Fallo "La parte del nombre que cambia ('$($parte.R)', de '$nombreR') tiene menos de $CmMinLetras letras: cambiaria trozos de palabras en los ficheros. No hago nada."
    return (New-ResultadoFaseConfigMap 1 '')
  }
  $script:CmParte = $parte
  $nombre = Get-NombreConfigMap (Split-Path $Referencia -Leaf) $parte $nombreM
  $destino = Join-Path (Split-Path $Migrado -Parent) $nombre
  $rutaJson = Join-Path $Datos 'configmap.json'
  $previo = $null
  if (Test-Path -LiteralPath $rutaJson) { try { $previo = Read-Json $rutaJson } catch { $previo = $null } }
  if (Test-Path -LiteralPath $destino) {
    if (-not ($previo -and "$($previo.destino)" -ieq $destino)) {
      Fallo ("Ya existe ${destino}: mu${CmE}vela o b${CmO}rrala. No he tocado nada.")
      return (New-ResultadoFaseConfigMap 1 $destino)
    }
  }
  else { [void](New-Item -ItemType Directory -Path $destino -Force) }
  foreach ($d in @($Datos, $Registros)) { if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -Force) } }
  # lo que el usuario ha cambiado desde la pasada anterior (su hash ya no es el que se escribio)
  $hashes = [ordered]@{}
  $cambiados = @()
  if ($previo) {
    foreach ($f in @($previo.ficheros)) {
      if (-not $f -or -not $f.ruta) { continue }
      $hashes[[string]$f.ruta] = [string]$f.hash
      $ruta = Join-Ruta $destino $f.ruta
      if ((Test-Path -LiteralPath $ruta -PathType Leaf) -and (Get-Sha256Hex ([System.IO.File]::ReadAllBytes($ruta))) -cne [string]$f.hash) { $cambiados += [string]$f.ruta }
    }
  }
  # que el repo nuevo quede apuntado como del script ya (si se corta, el relanzamiento sabe que es suyo)
  Write-Json $rutaJson ([ordered]@{ version = 1; destino = $destino; referencia = $Referencia; inventario = $Inventario; migrado = $Migrado; ficheros = @($previo.ficheros | Where-Object { $_ }) })
  foreach ($c in $cambiados) { Aviso "Has cambiado $c desde la ultima pasada: lo dejo como esta (si quieres que se escriba otra vez, borralo y relanza)." }
  try { return (Invoke-PasosConfigMap $Plantilla $Migrado $Referencia $Inventario $ConservarAtascadas $ref $parte $nombre $destino $rutaJson $cambiados $hashes) }
  finally {
    $r = Join-Path $destino '.rescate'
    if (Test-Path -LiteralPath $r) { Remove-Item -LiteralPath $r -Recurse -Force -ErrorAction SilentlyContinue }
  }
}

function Invoke-PasosConfigMap([string]$Plantilla, [string]$Migrado, [string]$Referencia, [string]$Inventario, [bool]$ConservarAtascadas, $ref, $parte, [string]$nombre, [string]$destino, [string]$rutaJson, $cambiados, $hashes) {
  $entornos = @($ref.Entornos.Keys)
  $inv = Read-InventarioConfigMap $Inventario $entornos
  $script:CmSecretos.Clear()
  foreach ($o in $inv.Values) { foreach ($s in $o.Secretos) { if (-not $script:CmSecretos.Contains($s)) { $script:CmSecretos.Add($s) } } }
  $vars = @(Get-VariablesConfigMap $Migrado)
  $claves = @(Get-ClavesInventarioConfigMap $inv)
  Info "Repo de configmap: $nombre ($($parte.R) -> $($parte.M); $($vars.Count) variables, $($entornos.Count) entornos, $(@($inv.Values | Where-Object { $_.Tiene }).Count) con inventario)."
  $ejecutadas = New-Object 'System.Collections.Generic.HashSet[string]'
  $todas = New-Object 'System.Collections.Generic.List[object]'
  $tolera = [bool]$ConservarAtascadas

  # 2. Paso 1: las variables, en tandas, con la IA (el script solo comprueba que la clave este en la lista o sea ninguna)
  $tVars = @()
  if ($vars.Count -gt 0 -and $claves.Count -gt 0) {
    $n = [int]$Cfg.ConfigMapVariablesPorTarea
    $k = 0
    for ($i = 0; $i -lt $vars.Count; $i += $n) {
      $k++
      $lote = @($vars[$i..([math]::Min($i + $n, $vars.Count) - 1)])
      $lineas = ($lote | ForEach-Object { "- $($_.variable) ($($_.fichero):$($_.linea)): $($_.texto)" }) -join "`n"
      $listaClaves = ($claves | ForEach-Object { "- $_" }) -join "`n"
      $entradas = [pscustomobject]@{
        variables = @($lote | ForEach-Object { $_.variable }); claves = $claves
        prompt = [pscustomobject]@{ VARIABLES = $lineas; CLAVES = $listaClaves; MIGRADO = $Migrado }
        huella = (Get-Hash8 ($lineas + '#' + $listaClaves))
      }
      $t = Get-TareaConfigMap (New-TareaTipo 'configmap-variables' "configmap-variables-$k" '' '' $entradas) @() $cambiados $tolera $false $destino
      if ($t.estado -eq 'pendiente') { [void]$ejecutadas.Add($t.id) }
      $tVars += $t
    }
    Invoke-TareasConfigMap $tVars $destino $Migrado
    foreach ($t in $tVars) { $todas.Add($t) }
  }
  $pares = @{}
  $secretas = @{}
  foreach ($t in @($tVars | Where-Object { $_.estado -eq 'hecha' })) {
    foreach ($r in @($t.resultado.variables)) {
      if ($r.clave -cne 'ninguna') { $pares[[string]$r.variable] = [string]$r.clave }
      if ($r.secreto) { $secretas[[string]$r.variable] = $true }
    }
  }
  foreach ($v in $vars) {
    $n = $v.variable
    if ((Test-NombreSecretoConfigMap $n) -or ($pares.ContainsKey($n) -and (Test-NombreSecretoConfigMap $pares[$n]))) { $secretas[$n] = $true }
  }

  # 3. Paso 2: un entorno por carpeta de config\ y un fichero por cada uno de las carpetas de punto
  $tablas = [ordered]@{}
  $tEntorno = @()
  $fuente = @($entornos | Where-Object { $ref.Entornos[$_].Count -gt 0 })
  foreach ($e in $entornos) {
    $origen = $e
    if ($ref.Entornos[$e].Count -eq 0) { if ($fuente.Count -eq 0) { continue }; $origen = $fuente[0] }
    $tabla = @(Get-TablaEntornoConfigMap $vars $pares $secretas $inv[$e])
    $tablas[$e] = $tabla
    $relsRef = @($ref.Entornos[$origen])
    $prefijoRef = 'config/' + $origen
    $ficheros = @($relsRef | ForEach-Object { 'config/' + $e + $_.Substring($prefijoRef.Length) } | ForEach-Object { Convert-ParteConfigMap $_ $parte })
    $vacios = @()
    for ($j = 0; $j -lt $relsRef.Count; $j++) { if (-not (Read-TextoConfigMap (Join-Ruta $Referencia $relsRef[$j])).Trim()) { $vacios += $ficheros[$j] } }
    $textoTabla = Get-TextoTablaConfigMap $tabla
    $textoRef = Get-TextoReferenciaConfigMap $Referencia $relsRef
    $entradas = [pscustomobject]@{
      entorno = $e; carpeta = "config/$e"; ficheros = $ficheros; vacios = $vacios; tabla = $tabla
      prompt = [pscustomobject]@{ ENTORNO = $e; CARPETA = "config/$e"; FICHEROS = ($ficheros -join "`n"); TABLA = $textoTabla; REFERENCIA = $textoRef; MIGRADO = $Migrado }
      huella = (Get-Hash8 ($e + '|' + $textoTabla + '|' + $textoRef + '|' + ($ficheros -join ',')))
    }
    $t = Get-TareaConfigMap (New-TareaTipo 'configmap-entorno' "configmap-entorno-$e" '' '' $entradas) $ficheros $cambiados $tolera $false $destino
    if ($t.estado -eq 'pendiente') { [void]$ejecutadas.Add($t.id) }
    $tEntorno += $t
  }
  $pom = Join-Path $Migrado 'pom.xml'
  $huellaPom = ''
  if (Test-Path -LiteralPath $pom -PathType Leaf) { $huellaPom = Get-Hash8 (Read-TextoConfigMap $pom) }
  $tPlat = @()
  $usados = New-Object 'System.Collections.Generic.HashSet[string]'
  $refsPlat = ''
  foreach ($relRef in $ref.Punto) {
    $dest = Convert-ParteConfigMap $relRef $parte
    $textoRef = Convert-ParteConfigMap (Read-TextoConfigMap (Join-Ruta $Referencia $relRef)) $parte
    $estructura = $null
    if ($dest -match '\.ya?ml$') { $estructura = Get-EstructuraYml $textoRef }
    $entradas = [pscustomobject]@{
      ficheroDestino = $dest; estructura = $estructura
      prompt = [pscustomobject]@{ FICHERO = $dest; REFERENCIA = $textoRef; BATCH = $nombreM; MIGRADO = $Migrado }
      huella = (Get-Hash8 ($dest + '|' + $textoRef + '|' + $huellaPom))
    }
    $id = Get-IdPlataformaConfigMap $dest $usados
    $t = Get-TareaConfigMap (New-TareaTipo 'configmap-plataforma' $id '' '' $entradas) @($dest) $cambiados $tolera $false $destino
    if ($t.estado -eq 'pendiente') { [void]$ejecutadas.Add($t.id) }
    $tPlat += $t
    $refsPlat += ('===== ' + $dest + " =====`n" + $textoRef + "`n")
  }
  Invoke-TareasConfigMap (@($tEntorno) + @($tPlat)) $destino $Migrado
  foreach ($t in (@($tEntorno) + @($tPlat))) { $todas.Add($t) }
  Copy-SueltosConfigMap $Referencia $destino $ref.Sueltos $cambiados

  # 4. Paso 3: la revision de cada entorno y de la plataforma (si una tarea de la que depende se ha rehecho, se rehace)
  $tRev = @()
  foreach ($t in $tEntorno) {
    $e = $t.entradas.entorno
    $ficheros = @($t.entradas.ficheros | Where-Object { Test-Path -LiteralPath (Join-Ruta $destino $_) -PathType Leaf })
    if ($ficheros.Count -eq 0) { continue }
    $entradas = [pscustomobject]@{
      unidad = $e; carpeta = "config/$e"; ficheros = $ficheros
      prompt = [pscustomobject]@{ UNIDAD = "entorno $e"; FICHEROS = ($ficheros -join "`n"); TABLA = (Get-TextoTablaConfigMap $t.entradas.tabla); REFERENCIA = $t.entradas.prompt.REFERENCIA; MIGRADO = $Migrado; HALLAZGOS_MAX = "$($Cfg.ConfigMapHallazgosMax)" }
      huella = (Get-Hash8 ($t.entradas.huella + '|' + ($ficheros -join ',')))
    }
    $nueva = Get-TareaConfigMap (New-TareaTipo 'configmap-revision' "configmap-revision-$e" '' '' $entradas) @() $cambiados $tolera ($ejecutadas.Contains($t.id)) $destino
    $tRev += $nueva
  }
  $fPlat = @($tPlat | ForEach-Object { $_.entradas.ficheroDestino } | Where-Object { Test-Path -LiteralPath (Join-Ruta $destino $_) -PathType Leaf })
  if ($fPlat.Count -gt 0) {
    $entradas = [pscustomobject]@{
      unidad = 'plataforma'; carpeta = ''; ficheros = $fPlat
      prompt = [pscustomobject]@{ UNIDAD = 'plataforma'; FICHEROS = ($fPlat -join "`n"); TABLA = '(sin tabla: son los ficheros de la plataforma)'; REFERENCIA = $refsPlat; MIGRADO = $Migrado; HALLAZGOS_MAX = "$($Cfg.ConfigMapHallazgosMax)" }
      huella = (Get-Hash8 (($tPlat | ForEach-Object { $_.entradas.huella }) -join ',') + '|' + ($fPlat -join ','))
    }
    $forzar = (@($tPlat | Where-Object { $ejecutadas.Contains($_.id) }).Count -gt 0)
    $tRev += (Get-TareaConfigMap (New-TareaTipo 'configmap-revision' 'configmap-revision-plataforma' '' '' $entradas) @() $cambiados $tolera $forzar $destino)
  }
  Invoke-TareasConfigMap $tRev $destino $Migrado
  foreach ($t in $tRev) { $todas.Add($t) }

  # 5. Salida: ningun valor de un secreto en el repo nuevo, PENDIENTE.md y datos\configmap.json
  $borrados = @()
  $paraBarrer = @(Get-FicherosSinGit $destino @('.git', '.rescate'))
  foreach ($m in @(Get-ProblemasSecretosConfigMap $destino $paraBarrer)) { $borrados += ($m -replace ' llevaba el valor.*$', '') }
  $pendientes = @(Get-PendientesFicherosConfigMap $destino)
  $hallazgos = @()
  foreach ($t in @($tRev | Where-Object { $_.estado -eq 'hecha' })) { foreach ($h in @($t.resultado.hallazgos)) { if ($h) { $hallazgos += $h } } }
  $atascadas = @($todas | Where-Object { $_.estado -eq 'atascada' } | ForEach-Object { [pscustomobject]@{ id = $_.id; motivo = (Hide-SecretosConfigMap ("$($_.motivo)" -replace '\r?\n', ' / ')) } })
  $datosEntornos = @()
  foreach ($e in $entornos) {
    if (-not $tablas.Contains($e)) { continue }
    $datosEntornos += [pscustomobject]@{ nombre = $e; inventario = [bool]$inv[$e].Tiene; tabla = @($tablas[$e]) }
  }
  $dif = @(Get-DiferenciasConfigMap $pares $inv)
  $nSecretas = @($vars | Where-Object { $secretas.ContainsKey($_.variable) }).Count
  $D = [pscustomobject]@{ nombre = $nombre; entornos = $datosEntornos; diferencias = $dif; pendientes = $pendientes; hallazgos = $hallazgos; atascadas = $atascadas; cambiados = @($cambiados); borrados = $borrados; secretas = $nSecretas }
  [System.IO.File]::WriteAllText((Join-Path $destino 'PENDIENTE.md'), (Get-TextoPendienteConfigMap $D), $Utf8)
  $ficheros = @()
  foreach ($rel in @(Get-FicherosSinGit $destino @('.git', '.rescate'))) {
    if ($rel -ceq 'PENDIENTE.md') { continue }
    $h = Get-Sha256Hex ([System.IO.File]::ReadAllBytes((Join-Ruta $destino $rel)))
    if (@($cambiados) -contains $rel -and $hashes.Contains($rel)) { $h = $hashes[$rel] }
    $ficheros += [ordered]@{ ruta = $rel; hash = $h }
  }
  $datosVars = @($vars | ForEach-Object {
      $c = ''
      if ($pares.ContainsKey($_.variable)) { $c = $pares[$_.variable] }
      [ordered]@{ variable = $_.variable; fichero = $_.fichero; linea = $_.linea; clave = $c; secreta = $secretas.ContainsKey($_.variable) }
    })
  Write-Json $rutaJson ([ordered]@{
      version = 1; destino = $destino; referencia = $Referencia; inventario = $Inventario; migrado = $Migrado
      parte = [ordered]@{ referencia = $parte.R; migrado = $parte.M }; actualizado = (Get-Date).ToString('s')
      variables = $datosVars
      entornos = @($datosEntornos | ForEach-Object { [ordered]@{ nombre = $_.nombre; inventario = $_.inventario; variables = @($_.tabla | ForEach-Object { [ordered]@{ variable = $_.variable; clave = $_.clave; estado = $_.estado } }) } })
      diferencias = $dif
      pendientes = @($pendientes | ForEach-Object { [ordered]@{ fichero = $_.fichero; linea = $_.linea; marca = $_.marca } })
      hallazgos = @($hallazgos | ForEach-Object { [ordered]@{ fichero = $_.fichero; linea = $_.linea; cita = $_.cita; problema = $_.problema } })
      atascadas = @($atascadas | ForEach-Object { [ordered]@{ id = $_.id; motivo = $_.motivo } })
      cambiados = @($cambiados)
      ficheros = $ficheros
    })
  foreach ($m in $borrados) { Aviso "Borrado: $m llevaba el valor de un secreto." }
  Bien "Repo de configmap hecho: $destino"
  Info "  $($pendientes.Count) pendientes en los ficheros, $nSecretas secretos por pedir, $($hallazgos.Count) hallazgos de la revision, $($atascadas.Count) tareas atascadas. Mira $(Join-Path $destino 'PENDIENTE.md')"
  return (New-ResultadoFaseConfigMap 0 $destino $pendientes.Count $atascadas.Count)
}
