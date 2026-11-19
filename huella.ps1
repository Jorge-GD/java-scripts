<#
huella.ps1 - La huella de lo compilado (BP-3): la prueba de que un arreglo automatico no cambia lo que hace el programa.
Se compila antes y despues, y se compara todo target\classes con 'javap -v -p' sin lo que no cambia el comportamiento. Es el port a PowerShell
de la huella v2 de la propuesta de buenas practicas (el prototipo e7-huella.py, 22 de 22 en E7). No se ejecuta solo: solo funciones. Se carga
con '. (Join-Path $PSScriptRoot 'huella.ps1')' despues de comun.ps1, que pone $Utf8, Invoke-Proceso, Get-Rel y Join-Ruta. Todavia no lo carga
ningun script. Solo ASCII. Vale para Windows PowerShell 5.1 y para PowerShell 7.

  Get-HuellaClase <javap>                   El texto de 'javap -v -p' de una clase, normalizado y en sus partes: @{ Cabecera; Campos; Metodos; Atributos }.
                                            Metodos es una lista de @{ Texto; Generado } (Generado: lo marca lombok.Generated).
  Compare-HuellaJavap <antes> <despues>     Dos tablas ruta relativa -> texto. Devuelve @{ Igual; Diferencias }; cada diferencia es @{ Clase; Partes }.
                                            Una ruta que acaba en .class lleva el texto de javap y se compara por su huella; cualquier otra lleva el
                                            SHA-256 del fichero y cuenta si cambia ('contenido'). Una ruta que solo esta en un lado es 'solo antes' o
                                            'solo despues'. Las partes de una clase: cabecera; campos (o su orden); metodos: <los que cambian>; orden de
                                            los metodos escritos a mano; atributos de clase.
  Compare-Huella <clasesAntes> <clasesDespues> [javap]
                                            Dos carpetas target\classes. Mismo conjunto de ficheros, mismo SHA-256 en los que no son .class y misma huella
                                            en cada .class. Llama a javap del JAVA_HOME (bin\javap.exe en Windows, bin/javap fuera de Windows) o, si se da,
                                            al tercer argumento, en lotes de menos de 8.000 caracteres de linea de comandos. Si no puede medir (sin
                                            JAVA_HOME, sin javap, javap con error o con menos clases de las pedidas, una carpeta que no existe) devuelve
                                            Igual = $false con la diferencia 'no se pudo medir: <motivo>': nunca da igual sin haber mirado.

Que cuenta: el codigo y las constantes; las anotaciones de clase, miembro, parametro y tipo; Signature, MethodParameters y las excepciones; los
nombres de los parametros; BootstrapMethods, resuelto dentro de cada invokedynamic; los campos en orden; el orden relativo de los metodos que no
genera Lombok. Que no cuenta: los indices del pool (solo donde son indices), LineNumberTable, los nombres de las variables locales que no son
parametros, LocalVariableTypeTable, SourceFile, la marca lombok.Generated, el 'final' de un parametro y donde esta cada metodo de Lombok.
javap imprime: no es un formato canonico y cambia entre versiones del JDK. Antes y despues, siempre el mismo JDK.
La salida de javap se pide en UTF-8 (-J-Dstdout.encoding=UTF-8) y se lee como UTF-8: sin eso, un literal con tilde saldria con '?' y dos literales
distintos parecerian iguales.
#>

# Parte $T en lo que hay antes y despues de $Sep, como partition (la primera) y rpartition (la ultima, con $Ultima) de Python: si no esta, partition
# da (todo, nada) y rpartition da (nada, todo).
function Split-HuellaTexto([string]$T, [string]$Sep, [bool]$Ultima = $false) {
  $opciones = [System.Text.RegularExpressions.RegexOptions]::None
  if ($Ultima) { $opciones = [System.Text.RegularExpressions.RegexOptions]::RightToLeft }
  $m = [regex]::Match($T, [regex]::Escape($Sep), $opciones)
  if ($m.Success) { return [pscustomobject]@{ Antes = $T.Substring(0, $m.Index); Despues = $T.Substring($m.Index + $m.Length) } }
  if ($Ultima) { return [pscustomobject]@{ Antes = ''; Despues = $T } }
  return [pscustomobject]@{ Antes = $T; Despues = '' }
}

function Get-HuellaSangria([string]$L) { return ($L.Length - $L.TrimStart(' ').Length) }

# La lista de textos, ordenada por codigo de caracter (no por cultura): el orden tiene que ser el mismo en todos los equipos.
function Sort-HuellaTexto($Lista) {
  $a = [string[]]@($Lista)
  [System.Array]::Sort($a, [System.StringComparer]::Ordinal)
  return , $a
}

function Test-HuellaIgual($Una, $Otra) {
  $x = @($Una); $y = @($Otra)
  if ($x.Count -ne $y.Count) { return $false }
  for ($i = 0; $i -lt $x.Count; $i++) { if ($x[$i] -cne $y[$i]) { return $false } }
  return $true
}

# Cada texto con las veces que sale.
function Get-HuellaCuenta($Textos) {
  $c = New-Object 'System.Collections.Generic.Dictionary[string,int]'
  foreach ($t in @($Textos)) { if ($c.ContainsKey($t)) { $c[$t]++ } else { $c[$t] = 1 } }
  return $c
}

# BootstrapMethods de la cola de la clase: numero -> sus lineas sin el indice del pool, unidas con ' | '.
function Get-HuellaBootstrap([string]$Cola) {
  $tabla = @{}
  $k = $null
  $dentro = $false
  foreach ($l in ($Cola -split "`n")) {
    if ($l -cmatch '^BootstrapMethods:') { $dentro = $true; continue }
    if ($dentro -and $l -and $l -cnotmatch '^ ') { break }
    if (-not $dentro) { continue }
    $e = [regex]::Match($l, '^  (\d+): #\d+ (.*)$')
    if ($e.Success) {
      $k = $e.Groups[1].Value
      $tabla[$k] = New-Object System.Collections.ArrayList
      [void]$tabla[$k].Add($e.Groups[2].Value)
    }
    elseif ($null -ne $k -and $l.Trim()) { [void]$tabla[$k].Add([regex]::Replace($l, '^\s*#\d+ ', '')) }
  }
  $res = @{}
  foreach ($k in $tabla.Keys) { $res[$k] = ($tabla[$k] -join ' | ') }
  return $res
}

# Una linea sin los indices del pool: una instruccion o un atributo con indice y comentario deja el comentario (las constantes) tal cual, y un
# invokedynamic lleva dentro su BootstrapMethods; una entrada de anotacion solo pierde sus indices.
function ConvertTo-HuellaLinea([string]$L, $Boot) {
  $p = $L -split '//', 2
  if ($p.Count -eq 2 -and $p[0] -match '#\d') {
    $pre = (($p[0] -replace '#\d+(,\s*\d+)?', '#') -replace '\s+', ' ').Trim()
    $post = $p[1]
    $m = [regex]::Match($post, '^( ?(?:InvokeDynamic|Dynamic) )#(\d+):')
    if ($m.Success) {
      $b = '?'
      if ($Boot.ContainsKey($m.Groups[2].Value)) { $b = $Boot[$m.Groups[2].Value] }
      $post = $m.Groups[1].Value + '{' + $b + '}:' + $post.Substring($m.Length)
    }
    return ($pre + ' //' + $post)
  }
  if ($L -match '^\s*\d+: #\d+\(') { return (($L -replace '#\d+', '#').Trim()) }
  return $L.Trim()
}

# Un metodo, un campo o un atributo de clase: sin LineNumberTable ni LocalVariableTypeTable; de LocalVariableTable solo los parametros (los de la
# fila que empieza en 0 y cuyo numero es menor que args_size); sin la marca lombok.Generated (Generado lo dice); sin el 'final' de MethodParameters.
function ConvertTo-HuellaBloque([string]$B, $Boot) {
  $ls = $B -split "`n"
  $out = New-Object System.Collections.ArrayList
  $i = 0
  $gen = $false
  $nArgs = $null
  while ($i -lt $ls.Count) {
    $l = $ls[$i]
    $s = $l.Trim()
    $ind = Get-HuellaSangria $l
    $m = [regex]::Match($l, 'args_size=(\d+)')
    if ($m.Success) { $nArgs = [int]$m.Groups[1].Value }
    if (@('LineNumberTable:', 'LocalVariableTypeTable:', 'LocalVariableTable:') -ccontains $s) {
      $j = $i + 1
      $filas = New-Object System.Collections.ArrayList
      while ($j -lt $ls.Count -and $ls[$j].Trim() -and (Get-HuellaSangria $ls[$j]) -gt $ind) { [void]$filas.Add($ls[$j]); $j++ }
      if ($s -ceq 'LocalVariableTable:' -and $null -ne $nArgs) {
        $params = New-Object System.Collections.ArrayList
        foreach ($f in $filas) {
          $r = [regex]::Match($f, '^\s*(\d+)\s+(\d+)\s+(\d+)\s+(\S+)\s+(\S+)\s*$')
          if ($r.Success -and $r.Groups[1].Value -ceq '0' -and [int]$r.Groups[3].Value -lt $nArgs) { [void]$params.Add($r.Groups[3].Value + '=' + $r.Groups[4].Value) }
        }
        [void]$out.Add('Parametros: ' + ((Sort-HuellaTexto $params) -join ' '))
      }
      $i = $j
      continue
    }
    if ($s -ceq 'RuntimeInvisibleAnnotations:' -and ($i + 2) -lt $ls.Count -and $ls[$i + 2].Trim() -ceq 'lombok.Generated' -and
        $ls[$i + 1] -cmatch '^\s*0: #\d+\(\)$' -and -not ((($i + 3) -lt $ls.Count) -and $ls[$i + 3] -cmatch '^\s*1: #')) {
      $gen = $true
      $i += 3
      continue
    }
    if ($s -ceq 'MethodParameters:') {
      [void]$out.Add($s)
      $j = $i + 1
      while ($j -lt $ls.Count -and $ls[$j].Trim() -and (Get-HuellaSangria $ls[$j]) -gt $ind) { [void]$out.Add(($ls[$j].Trim() -creplace '\s+final$', '')); $j++ }
      $i = $j
      continue
    }
    if ($s) { [void]$out.Add((ConvertTo-HuellaLinea $l $Boot)) }
    $i++
  }
  return [pscustomobject]@{ Texto = ($out -join "`n"); Generado = $gen }
}

# La huella de una clase, en sus partes: la cabecera (declaracion, flags, superclase), los campos en orden, los metodos y los atributos de clase
# (anotaciones, Record, InnerClasses...) sin SourceFile ni BootstrapMethods (este va dentro de cada invokedynamic).
function Get-HuellaClase([string]$Javap) {
  $t = $Javap -replace "`r`n", "`n"
  $p1 = Split-HuellaTexto $t "`nConstant pool:`n"
  $p2 = Split-HuellaTexto $p1.Despues "`n{`n"
  $resto = $p2.Despues
  if ($resto -cmatch '^}\n') { $cuerpo = ''; $cola = $resto.Substring(2) }
  else { $p3 = Split-HuellaTexto $resto "`n}`n" $true; $cuerpo = $p3.Antes; $cola = $p3.Despues }
  $boot = Get-HuellaBootstrap $cola
  $cabecera = New-Object System.Collections.ArrayList
  foreach ($l in ($p1.Antes -split "`n")) {
    if ($l.Trim() -and $l -cnotmatch '^\s*(Last modified|SHA-256|Compiled from|minor version|major version|interfaces: \d)') { [void]$cabecera.Add((ConvertTo-HuellaLinea $l $boot)) }
  }
  $campos = New-Object System.Collections.ArrayList
  $metodos = New-Object System.Collections.ArrayList
  foreach ($b in [regex]::Split("`n" + $cuerpo, '\n(?=  \S)')) {
    if (-not $b.Trim()) { continue }
    $n = ConvertTo-HuellaBloque $b $boot
    $primera = ($n.Texto -split "`n")[0]
    if ($primera.Contains('(') -or $primera -ceq 'static {};') { [void]$metodos.Add($n) } else { [void]$campos.Add($n.Texto) }
  }
  $atributos = New-Object System.Collections.ArrayList
  $actual = $null
  $trozos = New-Object System.Collections.ArrayList
  foreach ($l in ($cola -split "`n")) {
    if ($l -and $l -cnotmatch '^ ') { $actual = New-Object System.Collections.ArrayList; [void]$actual.Add($l); [void]$trozos.Add($actual) }
    elseif ($null -ne $actual -and $l.Trim()) { [void]$actual.Add($l) }
  }
  foreach ($a in $trozos) {
    $nombre = ($a[0] -split ':')[0]
    if ($nombre -ceq 'SourceFile' -or $nombre -ceq 'BootstrapMethods') { continue }
    $texto = (ConvertTo-HuellaBloque ($a -join "`n") $boot).Texto
    if ($nombre -ceq 'InnerClasses' -or $nombre -ceq 'NestMembers') { $texto = ((Sort-HuellaTexto ($texto -split "`n")) -join "`n") }
    [void]$atributos.Add($texto)
  }
  return [pscustomobject]@{
    Cabecera = [string[]]$cabecera.ToArray()
    Campos = [string[]]$campos.ToArray()
    Metodos = $metodos.ToArray()
    Atributos = (Sort-HuellaTexto $atributos)
  }
}

# Lo que cambia entre dos clases (textos de javap): las partes de la huella que no coinciden; ninguna si coinciden todas.
function Get-HuellaPartes([string]$Antes, [string]$Despues) {
  $a = Get-HuellaClase $Antes
  $d = Get-HuellaClase $Despues
  $partes = New-Object System.Collections.ArrayList
  if (-not (Test-HuellaIgual $a.Cabecera $d.Cabecera)) { [void]$partes.Add('cabecera') }
  if (-not (Test-HuellaIgual $a.Campos $d.Campos)) { [void]$partes.Add('campos (o su orden)') }
  $textosA = @($a.Metodos | ForEach-Object { $_.Texto })
  $textosD = @($d.Metodos | ForEach-Object { $_.Texto })
  $ca = Get-HuellaCuenta $textosA
  $cd = Get-HuellaCuenta $textosD
  $cambian = New-Object System.Collections.ArrayList
  foreach ($k in $ca.Keys) { $otras = 0; if ($cd.ContainsKey($k)) { $otras = $cd[$k] }; if ($ca[$k] -gt $otras) { [void]$cambian.Add($k) } }
  foreach ($k in $cd.Keys) { $otras = 0; if ($ca.ContainsKey($k)) { $otras = $ca[$k] }; if ($cd[$k] -gt $otras) { [void]$cambian.Add($k) } }
  if ($cambian.Count -gt 0) {
    $firmas = @($cambian | ForEach-Object { $f = ($_ -split "`n")[0]; if ($f.Length -gt 60) { $f = $f.Substring(0, 60) }; $f } | Select-Object -Unique)
    [void]$partes.Add('metodos: ' + ((Sort-HuellaTexto $firmas) -join ', '))
  }
  else {
    # los metodos son los mismos: el orden que cuenta es el de los escritos a mano (los de Lombok van donde Lombok quiera)
    $mano = @($d.Metodos | Where-Object { -not $_.Generado } | ForEach-Object { $_.Texto })
    $quedan = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($m in $mano) { [void]$quedan.Add($m) }
    $antesOrden = @($textosA | Where-Object { $quedan.Contains($_) })
    if (-not (Test-HuellaIgual $antesOrden $mano)) { [void]$partes.Add('orden de los metodos escritos a mano') }
  }
  if (-not (Test-HuellaIgual $a.Atributos $d.Atributos)) { [void]$partes.Add('atributos de clase') }
  return $partes.ToArray()
}

function Compare-HuellaJavap($Antes, $Despues) {
  $todas = New-Object 'System.Collections.Generic.HashSet[string]'
  $enAntes = New-Object 'System.Collections.Generic.HashSet[string]'
  $enDespues = New-Object 'System.Collections.Generic.HashSet[string]'
  foreach ($k in $Antes.Keys) { [void]$enAntes.Add([string]$k); [void]$todas.Add([string]$k) }
  foreach ($k in $Despues.Keys) { [void]$enDespues.Add([string]$k); [void]$todas.Add([string]$k) }
  $dif = New-Object System.Collections.ArrayList
  foreach ($k in (Sort-HuellaTexto $todas)) {
    $partes = @()
    if (-not $enAntes.Contains($k)) { $partes = @('solo despues') }
    elseif (-not $enDespues.Contains($k)) { $partes = @('solo antes') }
    elseif ($k -cnotmatch '\.class$') { if ($Antes[$k] -ne $Despues[$k]) { $partes = @('contenido') } }
    else { $partes = @(Get-HuellaPartes $Antes[$k] $Despues[$k]) }
    if ($partes.Count -gt 0) { [void]$dif.Add([pscustomobject]@{ Clase = $k; Partes = $partes }) }
  }
  return [pscustomobject]@{ Igual = ($dif.Count -eq 0); Diferencias = $dif.ToArray() }
}

# El javap del JAVA_HOME; sin el, un motivo en la excepcion.
function Get-HuellaJavap {
  if (-not $env:JAVA_HOME) { throw 'no hay JAVA_HOME, y sin el no se puede llamar a javap' }
  $nombre = 'javap'
  if ([System.IO.Path]::DirectorySeparatorChar -eq '\') { $nombre = 'javap.exe' }
  $ruta = Join-Path (Join-Path $env:JAVA_HOME 'bin') $nombre
  if (-not (Test-Path -LiteralPath $ruta -PathType Leaf)) { throw "no hay bin/$nombre en JAVA_HOME ($env:JAVA_HOME)" }
  return $ruta
}

# La tabla de una carpeta target\classes: ruta relativa (con '/') -> el texto de javap de cada .class, o el SHA-256 de lo que no es .class.
# javap va en lotes que no pasan de unos 7.500 caracteres de linea de comandos (el limite de cmd es 8.191) y con tope de tiempo cada uno; sus
# clases salen en el orden en que se le dan. Si algo no cuadra, lanza una excepcion con el motivo.
function Get-HuellaTabla([string]$Carpeta, [string]$Javap) {
  if (-not (Test-Path -LiteralPath $Carpeta -PathType Container)) { throw "no existe la carpeta $Carpeta" }
  $base = (Resolve-Path -LiteralPath $Carpeta).Path.TrimEnd('\', '/')
  $tabla = New-Object 'System.Collections.Generic.Dictionary[string,string]'
  $clases = New-Object System.Collections.ArrayList
  foreach ($f in @(Get-ChildItem -LiteralPath $base -Recurse -File -Force)) {
    $rel = Get-Rel $base $f.FullName
    if ($rel -cmatch '\.class$') { [void]$clases.Add($rel) }
    else { $tabla[$rel] = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
  }
  $clases = Sort-HuellaTexto $clases
  $i = 0
  while ($i -lt $clases.Count) {
    $lote = @()
    $largo = $Javap.Length + 60
    while ($i -lt $clases.Count) {
      $ruta = Join-Ruta $base $clases[$i]
      $largo += $ruta.Length + 3
      if ($lote.Count -gt 0 -and $largo -gt 7500) { break }
      $lote += $ruta
      $i++
    }
    $p = Invoke-Proceso $Javap (@('-J-Dstdout.encoding=UTF-8', '-v', '-p') + $lote) $base 300
    if ($p.Agotado) { throw 'javap ha tardado mas de 300 s en un lote' }
    if ($p.Codigo -ne 0) { throw ("javap ha salido con el codigo $($p.Codigo): " + ($p.Texto.Trim() -replace '\s+', ' ')) }
    $trozos = @([regex]::Split(($p.Texto -replace "`r`n", "`n"), '(?m)^Classfile ') | Select-Object -Skip 1)
    if ($trozos.Count -ne $lote.Count) { throw "javap ha dado $($trozos.Count) clases de las $($lote.Count) que se le pidieron" }
    for ($k = 0; $k -lt $lote.Count; $k++) {
      $salto = $trozos[$k].IndexOf([char]10)
      $texto = ''
      if ($salto -ge 0) { $texto = $trozos[$k].Substring($salto + 1) }
      $tabla[(Get-Rel $base $lote[$k])] = $texto
    }
  }
  return $tabla
}

function Compare-Huella([string]$ClasesAntes, [string]$ClasesDespues, [string]$Javap = '') {
  try {
    if (-not $Javap) { $Javap = Get-HuellaJavap }
    $antes = Get-HuellaTabla $ClasesAntes $Javap
    $despues = Get-HuellaTabla $ClasesDespues $Javap
    return (Compare-HuellaJavap $antes $despues)
  }
  catch {
    return [pscustomobject]@{ Igual = $false; Diferencias = @([pscustomobject]@{ Clase = ''; Partes = @('no se pudo medir: ' + $_.Exception.Message) }) }
  }
}
