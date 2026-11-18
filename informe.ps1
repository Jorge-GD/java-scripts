<#
informe.ps1 - Las paginas HTML del informe de migracion: la portada (index.html), que hace el batch original
(1-batch-original.html), los problemas del migrado (2-problemas.html), el original frente al migrado (3-original-vs-migrado.html)
y que se ha corregido (4-correcciones.html). Las monta el script con los datos de datos\ (sin IA,
sin JavaScript y sin nada externo: se abren con doble clic). Compatible con Windows PowerShell 5.1 y PowerShell 7. Solo ASCII a proposito: todo el texto
que ve la persona (con sus acentos) esta en las plantillas de informe\ (marco.html, index.html,
1-batch-original.html, 2-problemas.html, 3-original-vs-migrado.html y 4-correcciones.html; estilo.css se incrusta dentro de cada pagina).
Se carga con '. (Join-Path $PSScriptRoot 'informe.ps1')' despues de comun.ps1 y tareas.ps1, desde migracion.ps1 o
desde cualquier script que lo necesite. Cargarlo no ejecuta nada.

FUNCION PUBLICA
  Write-Informes -Salida <carpeta migracion-<batch>>
    Lee <Salida>\datos (estado.json, tareas\, fichas\, mapa.json, jobs\, resumen.json, pruebas\, comparacion\, variables.json,
    hallazgos-antes.json, diagnostico-antes.md, hallazgos-despues.json, diagnostico-despues.md y correcciones.json) y escribe
    <Salida>\index.html, 1-batch-original.html, 2-problemas.html, 3-original-vs-migrado.html y 4-correcciones.html con lo que haya. Un dato que falta (una fase sin hacer)
    sale como "todavia no hay datos: la fase X no ha terminado". Volver a llamarla con los mismos datos deja los mismos
    bytes (las paginas no dependen de la hora). Todo texto que viene de los datos se escapa.

  Read-Diagnostico -Datos <carpeta datos> [-Cuando antes|despues]
    Los problemas del migrado (hallazgos-<Cuando>.json y diagnostico-<Cuando>.md): por area, en el orden de la tabla del .md, con
    Errores y Avisos (las listas y sus cuentas), el Estado del build y lo que Incumple la referencia. $null si falta un fichero.

PLANTILLAS
  {{X}} lleva un valor de los datos (se escapa); {{{X}}} lleva un trozo de HTML que viene de una plantilla.
  Los trozos que se repiten (un job, un paso, un caso) estan dentro de cada plantilla, entre <!--TROZO nombre--> y
  <!--FIN-->. El HTML de los .ps1 se limita a elegir y rellenar trozos.
#>

# Que icono y que forma lleva cada tipo de dato en el dibujo de un job
$IconosTipo = @{
  'entrada-fichero' = @('f-fichero', 'fichero')
  'salida-fichero'  = @('f-fichero', 'fichero')
  'sftp'            = @('f-sftp', 'carpeta')
  'tabla-lee'       = @('f-tabla', 'tabla')
  'tabla-escribe'   = @('f-tabla', 'tabla')
  'parametro'       = @('f-param', 'param')
  'config'          = @('f-param', 'param')
  'externo'         = @('f-correo', 'externo')
}
# Las fases del script, en orden, y de que tipo son sus tareas
$FasesInforme = @(@('diagnostico', ''), @('fichas-clase', 'ficha-clase'), @('mapa', 'definicion-job'), @('fichas-job', 'ficha-job'), @('resumen', 'resumen'), @('pruebas-pre', 'prueba-pre'), @('comparar', 'comparar-pieza'), @('correccion', ''))
# Los cinco textos que el motor escribe en la linea "- Estado:" de diagnostico.md y el trozo de la frase de cada uno
$TextosBuild = @(
  @('compila: no comprobado', 'no-comprobado'), @('compila: NO', 'no'), @('compila: SI | tests: no ejecutados', 'sin-tests'),
  @('compila: SI | tests: OK', 'ok'), @('compila: SI | tests: FALLAN', 'fallan')
)
# Los ficheros de la carpeta del informe: ruta, trozo que lo explica, icono y si es una pagina del informe
$FicherosInforme = @(
  @('index.html', 'f-index', 'f-fichero', $true), @('1-batch-original.html', 'f-original', 'f-fichero', $true), @('2-problemas.html', 'f-problemas', 'f-fichero', $true),
  @('3-original-vs-migrado.html', 'f-comparar', 'f-fichero', $true), @('4-correcciones.html', 'f-correcciones', 'f-fichero', $true),
  @('datos', 'f-datos', 'f-carpeta', $false), @('datos/estado.json', 'f-estado', 'f-fichero', $false),
  @('datos/hallazgos-antes.json', 'f-hallazgos', 'f-fichero', $false), @('datos/diagnostico-antes.md', 'f-diagnostico', 'f-fichero', $false),
  @('datos/hallazgos-despues.json', 'f-hallazgos-despues', 'f-fichero', $false), @('datos/diagnostico-despues.md', 'f-diagnostico-despues', 'f-fichero', $false),
  @('datos/cobertura-antes.json', 'f-cobertura-antes', 'f-fichero', $false), @('datos/cobertura-despues.json', 'f-cobertura-despues', 'f-fichero', $false),
  @('datos/correcciones.json', 'f-correcciones-json', 'f-fichero', $false),
  @('datos/mapa.json', 'f-mapa', 'f-fichero', $false), @('datos/resumen.json', 'f-resumen', 'f-fichero', $false),
  @('datos/variables.json', 'f-variables', 'f-fichero', $false), @('datos/jobs', 'f-jobs', 'f-carpeta', $false),
  @('datos/pruebas', 'f-pruebas', 'f-carpeta', $false), @('datos/comparacion', 'f-comparacion', 'f-carpeta', $false), @('datos/fichas', 'f-fichas', 'f-carpeta', $false),
  @('datos/tareas', 'f-tareas', 'f-carpeta', $false), @('registros', 'f-registros', 'f-carpeta', $false),
  @('registros/correccion.log', 'f-correccion-log', 'f-fichero', $false),
  @('registros/cobertura-antes.log', 'f-cobertura-antes-log', 'f-fichero', $false), @('registros/cobertura-despues.log', 'f-cobertura-despues-log', 'f-fichero', $false)
)

# ================================ PLANTILLAS ================================
function ConvertTo-TextoHtml([string]$Texto) {
  return $Texto.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;').Replace("'", '&#39;')
}

function Read-PlantillaInforme([string]$Nombre) {
  $ruta = Join-Ruta $PSScriptRoot ('informe/' + $Nombre)
  if (-not (Test-Path -LiteralPath $ruta)) { throw "Falta la plantilla del informe: $ruta" }
  return ([System.IO.File]::ReadAllText($ruta, $Utf8) -replace "`r`n", "`n")
}

# Una plantilla en su cuerpo y sus trozos (nombre -> texto).
function Split-Plantilla([string]$Texto) {
  $rx = New-Object System.Text.RegularExpressions.Regex('(?s)<!--TROZO ([\w\-]+)-->(.*?)<!--FIN-->\n?')
  $trozos = @{}
  foreach ($m in $rx.Matches($Texto)) { $trozos[$m.Groups[1].Value] = $m.Groups[2].Value }
  return [pscustomobject]@{ Cuerpo = $rx.Replace($Texto, '').Trim(); Trozos = $trozos }
}

# Pone cada {{X}} (escapado) y cada {{{X}}} (tal cual) con su valor. Una sola pasada: un valor no se vuelve a expandir.
$RxHueco = New-Object System.Text.RegularExpressions.Regex('\{\{\{(\w+)\}\}\}|\{\{(\w+)\}\}')
function Expand-Plantilla([string]$Texto, $Valores) {
  $sb = New-Object System.Text.StringBuilder
  $pos = 0
  foreach ($m in $RxHueco.Matches($Texto)) {
    [void]$sb.Append($Texto.Substring($pos, $m.Index - $pos))
    if ($m.Groups[1].Success) { [void]$sb.Append([string]$Valores[$m.Groups[1].Value]) }
    else { [void]$sb.Append((ConvertTo-TextoHtml ([string]$Valores[$m.Groups[2].Value]))) }
    $pos = $m.Index + $m.Length
  }
  [void]$sb.Append($Texto.Substring($pos))
  return $sb.ToString()
}

function Format-Trozo($Trozos, [string]$Nombre, $Valores = @{}) {
  if (-not $Trozos.ContainsKey($Nombre)) { throw "Falta el trozo '$Nombre' en las plantillas del informe." }
  return (Expand-Plantilla $Trozos[$Nombre] $Valores)
}

# Un trozo por cada elemento de $Lista (el bloque saca los valores de cada uno), unidos por saltos de linea.
function Format-Lista($Trozos, [string]$Nombre, $Lista, [scriptblock]$Valores) {
  $partes = @()
  foreach ($x in @($Lista)) { $partes += (Format-Trozo $Trozos $Nombre (& $Valores $x)) }
  return ($partes -join "`n")
}

# ================================== DATOS ==================================
# Las comparaciones de datos\comparacion\<ficha>.json, por ficha.
function Read-Comparaciones([string]$Carpeta) {
  $r = @{}
  $dir = Join-Path $Carpeta 'comparacion'
  if (-not (Test-Path -LiteralPath $dir)) { return $r }
  foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -Filter 'clase-*.json' | Sort-Object Name)) {
    $x = Read-JsonSuave $f.FullName
    if ($x) { $r[[string]$x.ficha] = $x }
  }
  return $r
}

function Read-JsonSuave([string]$Ruta) {
  if (-not (Test-Path -LiteralPath $Ruta)) { return $null }
  try { return (Read-Json $Ruta) } catch { return $null }
}

function Get-ClaveHecho($H) { return ([string]$H.tipo + '|' + (([string]$H.texto -replace '\s', '').ToLowerInvariant())) }

# Un hecho es tecnico (nombra una clase: no va a la pagina de negocio) si lo es su ref o su clave tipo+texto: un paso
# puede citar el mismo dato por la ficha de clase, con otra ref. $Tecnicos lleva las dos cosas de cada dato tecnico.
function Test-HechoTecnico($Tecnicos, $H) { return ($Tecnicos.ContainsKey([string]$H.ref) -or $Tecnicos.ContainsKey((Get-ClaveHecho $H))) }

# referencia (clase-xxxxxxxx#n) -> el dato de la ficha de clase que la tiene
function Get-IndiceHechos([string]$Salida) {
  $indice = @{}
  $dir = Join-Path (Join-Path $Salida 'datos') 'fichas'
  if (-not (Test-Path -LiteralPath $dir)) { return $indice }
  foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -Filter 'clase-*.json' | Sort-Object Name)) {
    $x = Read-JsonSuave $f.FullName
    if (-not $x) { continue }
    $n = 0
    foreach ($d in @($x.datos)) {
      $indice["$($x.id)#$n"] = [pscustomobject]@{ ref = "$($x.id)#$n"; tipo = $d.tipo; texto = $d.texto; fichero = $x.fichero; linea = $d.linea; cita = $d.cita; probado = [bool]$d.probado }
      $n++
    }
  }
  return $indice
}

# Los jobs del mapa: primero en el orden del resumen y despues los demas.
function Get-OrdenJobs($D) {
  $nombres = @($D.Mapa.jobs | ForEach-Object { $_.job })
  $orden = @()
  if ($D.Resumen) {
    foreach ($x in @($D.Resumen.orden)) { if (($nombres -ccontains $x.job) -and ($orden -cnotcontains $x.job)) { $orden += $x.job } }
  }
  foreach ($n in $nombres) { if ($orden -cnotcontains $n) { $orden += $n } }
  return $orden
}

# Todo lo que las paginas cuentan de un job: su ficha, su guion de prueba, los datos que citan sus pasos y los demas.
function Get-VistaJob($D, $J) {
  $id = Get-NombreJob $J.job
  $datos = Join-Path $D.Salida 'datos'
  $ficha = Read-JsonSuave (Join-Path (Join-Path $datos 'jobs') ($id + '.json'))
  $pruebas = Read-JsonSuave (Join-Path (Join-Path $datos 'pruebas') ($id + '.json'))
  $hecha = [bool]($ficha -and $ficha.redaccion -eq 'hecha')
  $listas = @()
  if ($ficha) { foreach ($k in $Cfg.ListasJob.Keys) { $listas += @($ficha.$k | Where-Object { $null -ne $_ }) } }
  # Los datos con tecnico: true no salen en la pagina de negocio (la portada si los cuenta, en lo que te toca).
  $datosTecnicos = @($listas | Where-Object { $_.tecnico })
  $tecnicos = @{}
  foreach ($h in $datosTecnicos) { $tecnicos[[string]$h.ref] = $true; $tecnicos[(Get-ClaveHecho $h)] = $true }
  $listas = @($listas | Where-Object { -not $_.tecnico })
  $porRef = @{}
  foreach ($h in $listas) { $porRef[[string]$h.ref] = $h }
  $citados = @()
  $vistos = @{}
  $claves = @{}
  $pasos = @()
  if ($hecha) {
    foreach ($p in @($ficha.pasos)) {
      $hs = @()
      foreach ($r in @($p.refs)) {
        $h = $null
        if ($porRef.ContainsKey([string]$r)) { $h = $porRef[[string]$r] } elseif ($D.Indice.ContainsKey([string]$r)) { $h = $D.Indice[[string]$r] }
        if ($null -eq $h -or (Test-HechoTecnico $tecnicos $h)) { continue }
        $hs += $h
        if (-not $vistos.ContainsKey($h.ref)) { $vistos[$h.ref] = $true; $claves[(Get-ClaveHecho $h)] = $true; $citados += $h }
      }
      $pasos += [pscustomobject]@{ Titulo = $p.titulo; Texto = $p.texto; Probado = [bool]$p.probado; Hechos = $hs }
    }
  }
  $otros = @($listas | Where-Object { -not $vistos.ContainsKey($_.ref) -and -not $claves.ContainsKey((Get-ClaveHecho $_)) })
  $tN = @($Cfg.ListasJob['necesita'])
  $tP = @($Cfg.ListasJob['produce']) + @($Cfg.ListasJob['conexiones'])
  if ($hecha) {
    $necesita = @($citados | Where-Object { $tN -ccontains $_.tipo })
    $produce = @($citados | Where-Object { $tP -ccontains $_.tipo })
  }
  else {
    $necesita = @($listas | Where-Object { $tN -ccontains $_.tipo } | Select-Object -First 8)
    $produce = @($listas | Where-Object { $tP -ccontains $_.tipo } | Select-Object -First 8)
  }
  $titulo = $J.job
  $paraQue = ''
  $dudas = @()
  $sinFicha = @()
  $fuera = @()
  if ($ficha) {
    if ($hecha) { $titulo = $ficha.titulo; $paraQue = $ficha.paraQue }
    $dudas = @($ficha.dudas | Where-Object { $null -ne $_ })
    $sinFicha = @($ficha.sinFicha | Where-Object { $null -ne $_ })
    $fuera = @($ficha.fuera | Where-Object { $null -ne $_ })
  }
  $sinCaso = @()
  if ($pruebas) { $sinCaso = @($pruebas.sinCaso | Where-Object { $null -ne $_ -and -not (Test-HechoTecnico $tecnicos $_) }) }
  $motivo = ''
  if ($D.Resumen) { $m = @($D.Resumen.orden | Where-Object { $_.job -ceq $J.job })[0]; if ($m) { $motivo = $m.motivo } }
  return [pscustomobject]@{
    Job = $J.job; Id = $id; Ficha = $ficha; Pruebas = $pruebas; Hecha = $hecha; Titulo = $titulo; ParaQue = $paraQue; Motivo = $motivo
    Pasos = $pasos; Citados = $citados; Otros = $otros; Necesita = $necesita; Produce = $produce; Dudas = $dudas; SinFicha = $sinFicha; Fuera = $fuera
    DatosTecnicos = $datosTecnicos; SinCaso = $sinCaso
  }
}

# La linea "- Estado:" de un diagnostico.md (uno de los cinco textos del build de $TextosBuild), o '' si no la tiene.
function Get-EstadoBuild([string]$Md) { return [regex]::Match($Md, '(?m)^- Estado: (.*)$').Groups[1].Value.Trim() }

# Los problemas del migrado que dejo un diagnostico ($Cuando: antes de corregir o despues): hallazgos-<Cuando>.json y
# diagnostico-<Cuando>.md. El orden de las areas es el de la tabla del .md (las que solo salen en los hallazgos, al final).
# $null si falta alguno de los dos o el .json no se lee.
function Read-Diagnostico([string]$Datos, [string]$Cuando = 'antes') {
  $rj = Join-Path $Datos "hallazgos-$Cuando.json"
  $rm = Join-Path $Datos "diagnostico-$Cuando.md"
  if (-not (Test-Path -LiteralPath $rj) -or -not (Test-Path -LiteralPath $rm)) { return $null }
  try { $hall = @(Read-Json $rj | Where-Object { $null -ne $_ }) } catch { return $null }
  $md = [System.IO.File]::ReadAllText($rm, $Utf8) -replace "`r`n", "`n"
  $orden = @([regex]::Matches($md, '(?m)^\| (\w+) \| [0-9]+ \| [0-9]+ \|[ \t]*$') | ForEach-Object { $_.Groups[1].Value })
  foreach ($h in $hall) { if ($orden -cnotcontains [string]$h.Cat) { $orden += [string]$h.Cat } }
  $areas = @()
  foreach ($c in $orden) {
    $de = @($hall | Where-Object { [string]$_.Cat -ceq $c })
    $areas += [pscustomobject]@{ Id = $c; Errores = @($de | Where-Object { $_.Sev -ceq 'error' }); Avisos = @($de | Where-Object { $_.Sev -cne 'error' }) }
  }
  $estado = Get-EstadoBuild $md
  $incumple = $null
  $m = [regex]::Match($md, '(?m)^- La plantilla incumple: capas ([0-9]+) \| ficheros ([0-9]+) \| calidad ([0-9]+) \| secretos ([0-9]+)[ \t]*$')
  if ($m.Success) { $incumple = [pscustomobject]@{ Capas = $m.Groups[1].Value; Ficheros = $m.Groups[2].Value; Calidad = $m.Groups[3].Value; Secretos = $m.Groups[4].Value } }
  return [pscustomobject]@{
    Areas = $areas; Estado = $estado; Incumple = $incumple
    Errores = @($hall | Where-Object { $_.Sev -ceq 'error' }).Count; Avisos = @($hall | Where-Object { $_.Sev -cne 'error' }).Count
  }
}

function Read-DatosInforme([string]$Salida) {
  $datos = Join-Path $Salida 'datos'
  $tareas = @()
  if (Test-Path -LiteralPath (Join-Path $datos 'tareas')) {
    $tareas = @(Get-ChildItem -LiteralPath (Join-Path $datos 'tareas') -File -Filter '*.json' | Sort-Object Name | ForEach-Object { Read-JsonSuave $_.FullName } | Where-Object { $null -ne $_ })
  }
  $D = [pscustomobject]@{
    Salida = $Salida; Estado = (Read-JsonSuave (Join-Path $datos 'estado.json')); Mapa = (Read-JsonSuave (Join-Path $datos 'mapa.json'))
    Resumen = (Read-JsonSuave (Join-Path $datos 'resumen.json')); Variables = @(Read-JsonSuave (Join-Path $datos 'variables.json') | Where-Object { $null -ne $_ })
    Tareas = $tareas; Indice = (Get-IndiceHechos $Salida); Vistas = @(); Diag = (Read-Diagnostico $datos); Despues = (Read-Diagnostico $datos 'despues')
    Correccion = (Read-JsonSuave (Join-Path $datos 'correcciones.json'))
    CobAntes = (Read-JsonSuave (Join-Path $datos 'cobertura-antes.json')); CobDespues = (Read-JsonSuave (Join-Path $datos 'cobertura-despues.json'))
    Comparacion = (Read-Comparaciones $datos)
  }
  if ($D.Mapa) {
    $porNombre = @{}
    foreach ($j in @($D.Mapa.jobs)) { $porNombre[[string]$j.job] = $j }
    $vistas = @()
    foreach ($n in @(Get-OrdenJobs $D)) { $vistas += (Get-VistaJob $D $porNombre[[string]$n]) }
    $D.Vistas = $vistas
  }
  return $D
}

# ============================== PIEZAS DE PAGINA ==============================
function Get-MarcaHecho($T, [bool]$Probado) {
  if ($Probado) { return (Format-Trozo $T 'marca-ia') }
  return (Format-Trozo $T 'marca-sin')
}

function Get-TipoHtml($T, [string]$Tipo) {
  if ($T.ContainsKey("tipo-$Tipo")) { return (Format-Trozo $T "tipo-$Tipo") }
  return (ConvertTo-TextoHtml $Tipo)
}

function Get-NodoHtml($T, $H) {
  $ic = $IconosTipo[[string]$H.tipo]
  if (-not $ic) { $ic = @('f-fichero', 'fichero') }
  return (Format-Trozo $T 'nodo' @{ CLASE = $ic[1]; ICONO = $ic[0]; TEXTO = $H.texto; MARCA = (Get-MarcaHecho $T $H.probado); TIPO = (Get-TipoHtml $T $H.tipo) })
}

function Get-NodosHtml($T, $Hechos) {
  if (@($Hechos).Count -eq 0) { return (Format-Trozo $T 'nodo-vacio') }
  return (Format-Trozo $T 'nodos' @{ ITEMS = (@($Hechos | ForEach-Object { Get-NodoHtml $T $_ }) -join "`n") })
}

function Get-PasoHtml($T, $P, [int]$N) {
  $reglas = @($P.Hechos | Where-Object { $_.tipo -ceq 'regla' })
  $fallos = @($P.Hechos | Where-Object { $_.tipo -ceq 'error' })
  $rh = ''
  $fh = ''
  if ($reglas.Count -gt 0) { $rh = Format-Trozo $T 'reglas' @{ ITEMS = (Format-Lista $T 'regla' $reglas { param($h) @{ TEXTO = $h.texto; MARCA = (Get-MarcaHecho $T $h.probado) } }) } }
  if ($fallos.Count -gt 0) { $fh = Format-Trozo $T 'fallos' @{ ITEMS = (Format-Lista $T 'fallo' $fallos { param($h) @{ TEXTO = $h.texto; MARCA = (Get-MarcaHecho $T $h.probado) } }) } }
  return (Format-Trozo $T 'paso' @{ N = "$N"; TITULO = $P.Titulo; TEXTO = $P.Texto; MARCA = (Get-MarcaHecho $T $P.Probado); REGLAS = $rh; FALLOS = $fh })
}

# Una linea de "donde lo dice el codigo": el tipo, el dato, su marca, fichero:linea y la cita.
function Get-PruebaHtml($T, $H) {
  $donde = ''
  if ($H.fichero) { $donde = "$($H.fichero):$($H.linea)" }
  return (Format-Trozo $T 'prueba' @{ TIPO = (Get-TipoHtml $T $H.tipo); TEXTO = $H.texto; MARCA = (Get-MarcaHecho $T $H.probado); DONDE = $donde; CITA = $H.cita })
}

function Get-ListaPreHtml($T, $Items, [bool]$Redactada) {
  if (@($Items).Count -eq 0) { return (Format-Trozo $T 'pre-vacia') }
  $html = Format-Lista $T 'pre-item' $Items { param($x) @{ TEXTO = $x.texto; MARCA = (Get-MarcaHecho $T ($Redactada -and @($x.refs).Count -gt 0)) } }
  return (Format-Trozo $T 'pre-lista' @{ ITEMS = $html })
}

# "Como probarlo en pre" de un job: lo que dejo la fase pruebas-pre.
function Get-PreHtml($D, $T, $V) {
  $p = $V.Pruebas
  if (-not $p) { return (Format-Trozo $T 'pre-sin-datos' @{ ETIQUETA = (Format-Trozo $T 'et-sin') }) }
  $red = ($p.redaccion -eq 'hecha')
  $casos = @($p.casos | Where-Object { $null -ne $_ })
  $vars = ''
  if ($D.Variables.Count -gt 0) {
    $items = Format-Lista $T 'var' $D.Variables {
      param($x)
      if ($null -ne $x.porDefecto) { @{ NOMBRE = $x.variable; VALOR = (Format-Trozo $T 'var-defecto' @{ VALOR = $x.porDefecto }) } }
      else { @{ NOMBRE = $x.variable; VALOR = (Format-Trozo $T 'var-sin-defecto') } }
    }
    $vars = Format-Trozo $T 'vars' @{ ETIQUETA = (Format-Trozo $T 'et-medido'); ITEMS = $items }
  }
  $casosHtml = Format-Trozo $T 'pre-vacia'
  if ($casos.Count -gt 0) {
    $filas = @()
    foreach ($c in $casos) {
      $nombre = 'caso'
      if ((-not $c.entrada) -and (-not $c.esperado)) { $nombre = 'caso-vacio' }
      $filas += (Format-Trozo $T $nombre @{ TITULO = $c.titulo; ENTRADA = $c.entrada; ESPERADO = $c.esperado; MARCA = (Get-MarcaHecho $T ($red -and @($c.refs).Count -gt 0)) })
    }
    $casosHtml = Format-Trozo $T 'casos' @{ ITEMS = ($filas -join "`n") }
  }
  $sinCaso = ''
  $falta = @($V.SinCaso)
  if ($falta.Count -gt 0) {
    $sinCaso = Format-Trozo $T 'sincaso' @{ ETIQUETA = (Format-Trozo $T 'et-sin'); ITEMS = (Format-Lista $T 'duda' $falta { param($x) @{ TEXTO = $x.texto } }) }
  }
  return (Format-Trozo $T 'pre-contenido' @{
      PREPARAR = (Get-ListaPreHtml $T @($p.preparar | Where-Object { $null -ne $_ }) $red); VARIABLES = $vars; N = "$($casos.Count)"
      CASOS = $casosHtml; COMPROBAR = (Get-ListaPreHtml $T @($p.comprobar | Where-Object { $null -ne $_ }) $red); SINCASO = $sinCaso
    })
}

function Get-JobHtml($D, $T, $V, [int]$N) {
  if (-not $V.Ficha) {
    return (Format-Trozo $T 'job-pendiente' @{ ID = $V.Id; N = "$N"; JOB = $V.Job; SINDATOS = (Format-Trozo $T 'sin-datos' @{ FASE = 'fichas-job'; ETIQUETA = (Format-Trozo $T 'et-sin') }) })
  }
  $et = Format-Trozo $T 'et-sin'
  $aviso = Format-Trozo $T 'job-aviso'
  $pasos = Format-Trozo $T 'paso-sin'
  if ($V.Hecha) {
    $et = Format-Trozo $T 'et-ia'
    $aviso = ''
    $i = 0
    $pasos = Format-Trozo $T 'pasos' @{ ITEMS = (@($V.Pasos | ForEach-Object { $i++; Get-PasoHtml $T $_ $i }) -join "`n") }
  }
  $cifras = Format-Trozo $T 'job-cifras' @{ ETIQUETA = (Format-Trozo $T 'et-medido'); PASOS = "$(@($V.Pasos).Count)"; CITADOS = "$(@($V.Citados).Count)"; OTROS = "$(@($V.Otros).Count)" }
  $dudas = ''
  if (@($V.Dudas).Count -gt 0) { $dudas = Format-Trozo $T 'dudas' @{ ETIQUETA = (Format-Trozo $T 'et-sin'); ITEMS = (Format-Lista $T 'duda' $V.Dudas { param($x) @{ TEXTO = $x } }) } }
  $conPrueba = @($V.Citados | Where-Object { $_.fichero })
  $donde = ''
  if ($conPrueba.Count -gt 0) { $donde = Format-Trozo $T 'donde' @{ N = "$($conPrueba.Count)"; ITEMS = (@($conPrueba | ForEach-Object { Get-PruebaHtml $T $_ }) -join "`n") } }
  $otros = ''
  if (@($V.Otros).Count -gt 0) {
    $abierto = ''
    if (-not $V.Hecha) { $abierto = Format-Trozo $T 'abierto' }
    $otros = Format-Trozo $T 'otros' @{ ABIERTO = $abierto; N = "$(@($V.Otros).Count)"; ITEMS = (@($V.Otros | ForEach-Object { Get-PruebaHtml $T $_ }) -join "`n") }
  }
  return (Format-Trozo $T 'job' @{
      ID = $V.Id; N = "$N"; JOB = $V.Job; TITULO = $V.Titulo; PARAQUE = $V.ParaQue; ETIQUETA = $et; AVISO = $aviso; CIFRAS = $cifras
      NECESITA = (Get-NodosHtml $T $V.Necesita); PASOS = $pasos; PRODUCE = (Get-NodosHtml $T $V.Produce); DUDAS = $dudas; DONDE = $donde; OTROS = $otros
      PRE = (Get-PreHtml $D $T $V)
    })
}

# ============================ LAS DOS PAGINAS ============================
function Get-BatchInforme($D) {
  if ($D.Estado -and $D.Estado.batch) { return [string]$D.Estado.batch }
  return ((Split-Path $D.Salida -Leaf) -replace '^migracion-', '')
}

function Get-Hoja($Ruta) {
  if (-not $Ruta) { return '' }
  return [System.IO.Path]::GetFileName(([string]$Ruta).TrimEnd('\', '/'))
}

function Get-CuerpoOriginal($D, $T, [string]$Cuerpo) {
  $sinResumen = Format-Trozo $T 'sin-datos' @{ FASE = 'resumen'; ETIQUETA = (Format-Trozo $T 'et-sin') }
  $resumen = $sinResumen
  $glosario = $sinResumen
  if ($D.Resumen) {
    $resumen = Format-Trozo $T 'resumen' @{ TEXTO = $D.Resumen.resumen; ETIQUETA = (Format-Trozo $T 'et-ia') }
    $g = @($D.Resumen.glosario | Where-Object { $null -ne $_ })
    if ($g.Count -gt 0) { $glosario = Format-Trozo $T 'glosario' @{ ITEMS = (Format-Lista $T 'termino' $g { param($x) @{ TERMINO = $x.termino; DEFINICION = $x.definicion } }) } }
    else { $glosario = Format-Trozo $T 'glosario-vacio' }
  }
  $recorrido = Format-Trozo $T 'sin-datos' @{ FASE = 'mapa'; ETIQUETA = (Format-Trozo $T 'et-sin') }
  $jobs = $recorrido
  if ($D.Mapa) {
    $jobs = (@($D.Vistas | ForEach-Object { $n = [array]::IndexOf(@($D.Vistas), $_) + 1; Get-JobHtml $D $T $_ $n }) -join "`n")
    $recorrido = $sinResumen
    if ($D.Resumen) {
      $recorrido = Format-Trozo $T 'recorrido' @{ PARADAS = (@($D.Vistas | ForEach-Object { $n = [array]::IndexOf(@($D.Vistas), $_) + 1; Format-Trozo $T 'parada' @{ N = "$n"; ID = $_.Id; TITULO = $_.Titulo; JOB = $_.Job; MOTIVO = $_.Motivo } }) -join "`n") }
    }
  }
  $et = Format-Trozo $T 'et-sin'
  if ($D.Mapa) { $et = Format-Trozo $T 'et-ia' }
  return (Expand-Plantilla $Cuerpo @{ BATCH = (Get-BatchInforme $D); ORIGINAL = (Get-Hoja $D.Estado.legacy); ETIQUETA = $et; RESUMEN = $resumen; RECORRIDO = $recorrido; JOBS = $jobs; GLOSARIO = $glosario })
}

# ============================== EL ORIGINAL FRENTE AL MIGRADO ==============================
# Las filas de la comparacion de un job del mapa: por cada clase del job (en su orden) y cada dato de su comparacion, lo que dijo
# la IA (o el script, en sin-pieza) junto al dato del original.
function Get-DatosComparar($D, $J) {
  $filas = @()
  foreach ($cl in @($J.clases)) {
    $c = $D.Comparacion[[string]$cl.ficha]
    if (-not $c) { continue }
    foreach ($dato in @($c.datos)) {
      $h = $D.Indice["$($cl.ficha)#$($dato.dato)"]
      $texto = ''; $original = ''; $citaOriginal = ''
      if ($h) { $texto = $h.texto; $original = "$($h.fichero):$($h.linea)"; $citaOriginal = $h.cita }
      $migrado = ''
      if ($dato.fichero) { $migrado = "$($dato.fichero):$($dato.linea)" }
      $filas += [pscustomobject]@{
        Job = $J.job; Clase = $c.clase; Estado = [string]$dato.estado; Texto = $texto; Original = $original; CitaOriginal = $citaOriginal
        Migrado = $migrado; CitaMigrado = [string]$dato.cita; Nota = [string]$dato.nota; Probado = ($dato.probado -eq $true)
      }
    }
  }
  return $filas
}

# Medido (lo cuenta el script) en sin-pieza; leido por la IA con prueba si la cita salio en el fichero; sin comprobar en lo demas.
function Get-MarcaComparar($T, $R) {
  if ($R.Estado -ceq 'sin-pieza') { return (Format-Trozo $T 'marca-medido') }
  return (Get-MarcaHecho $T ($R.Probado -and $R.Migrado))
}

function Get-FilaComparar($T, $R) {
  $clase = ''
  if ($R.Estado -ceq 'distinto') { $clase = 's-error' } elseif ($R.Estado -cne 'igual') { $clase = 's-aviso' }
  $migrado = ''
  if ($R.Migrado) { $migrado = Format-Trozo $T 'comp-migrado' @{ DONDE = $R.Migrado; CITA = $R.CitaMigrado } }
  $nota = ''
  if ($R.Nota) { $nota = Format-Trozo $T 'comp-nota' @{ NOTA = $R.Nota } }
  return (Format-Trozo $T 'comp-fila' @{
      CLASE = $clase; ESTADO = (Format-Trozo $T "comp-est-$($R.Estado)"); TEXTO = $R.Texto; MARCA = (Get-MarcaComparar $T $R)
      NOMBRE = $R.Clase; ORIGINAL = $R.Original; CITA = $R.CitaOriginal; MIGRADO = $migrado; NOTA = $nota
    })
}

# Un job: la cabecera con sus cuentas, primero los distintos, las faltas, los que no sabe y los sin pieza, y los iguales plegados.
function Get-GrupoComparar($D, $T, $J) {
  $filas = @(Get-DatosComparar $D $J)
  $n = @{ 'igual' = 0; 'distinto' = 0; 'falta' = 0; 'no-lo-se' = 0; 'sin-pieza' = 0 }
  foreach ($f in $filas) { $n[$f.Estado]++ }
  $primeras = @(foreach ($e in @('distinto', 'falta', 'no-lo-se', 'sin-pieza')) { @($filas | Where-Object { $_.Estado -ceq $e }) })
  $iguales = @($filas | Where-Object { $_.Estado -ceq 'igual' })
  $cuerpo = ''
  if ($primeras.Count -gt 0) { $cuerpo = Format-Trozo $T 'comp-filas' @{ FILAS = (@($primeras | ForEach-Object { Get-FilaComparar $T $_ }) -join "`n") } }
  if ($iguales.Count -gt 0) {
    $texto = Format-Trozo $T 'comp-iguales-otros' @{ N = "$($iguales.Count)" }
    if ($iguales.Count -eq 1) { $texto = Format-Trozo $T 'comp-iguales-uno' }
    $cuerpo += Format-Trozo $T 'comp-iguales' @{ TEXTO = $texto; FILAS = (@($iguales | ForEach-Object { Get-FilaComparar $T $_ }) -join "`n") }
  }
  if (-not $cuerpo) { $cuerpo = Format-Trozo $T 'comp-job-vacio' }
  $cuenta = Format-Trozo $T 'comp-cuenta' @{ IGUAL = "$($n['igual'])"; DISTINTO = "$($n['distinto'])"; FALTA = "$($n['falta'])"; NOLOSE = "$($n['no-lo-se'])"; SINPIEZA = "$($n['sin-pieza'])" }
  return (Format-Trozo $T 'comp-job' @{ ID = (Get-NombreJob $J.job); JOB = $J.job; CUENTA = $cuenta; CUERPO = $cuerpo })
}

function Get-CuerpoComparar($D, $T, [string]$Cuerpo) {
  $jobs = Format-Trozo $T 'sin-datos' @{ FASE = 'comparar'; ETIQUETA = (Format-Trozo $T 'et-sin') }
  if (-not $D.Mapa) { $jobs = Format-Trozo $T 'sin-datos' @{ FASE = 'mapa'; ETIQUETA = (Format-Trozo $T 'et-sin') } }
  elseif ($D.Comparacion.Count -gt 0) { $jobs = (@($D.Mapa.jobs | ForEach-Object { Get-GrupoComparar $D $T $_ }) -join "`n") }
  return (Expand-Plantilla $Cuerpo @{ JOBS = $jobs })
}

function ConvertTo-FechaInforme($V) {
  if ($V -is [datetime]) { return $V }
  try { return [datetime]::ParseExact([string]$V, 's', [System.Globalization.CultureInfo]::InvariantCulture) } catch { return $null }
}

function Get-TextoFecha($T, $V) {
  $f = ConvertTo-FechaInforme $V
  if ($null -eq $f) { return (Format-Trozo $T 'sin-valor') }
  return $f.ToString('dd-MM-yyyy HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
}

function Get-TextoDuracion($T, $Desde, $Hasta) {
  $a = ConvertTo-FechaInforme $Desde
  $b = ConvertTo-FechaInforme $Hasta
  if ($null -eq $a -or $null -eq $b) { return (Format-Trozo $T 'sin-valor') }
  $min = [int][math]::Floor(($b - $a).TotalMinutes)
  if ($min -lt 0) { $min = 0 }
  if ($min -ge 60) { return (Format-Trozo $T 'duracion' @{ H = "$([math]::Floor($min / 60))"; M = "$($min % 60)" }) }
  return (Format-Trozo $T 'duracion-corta' @{ M = "$min" })
}

# Una linea de una fase: su estado (segun la fase en que va la pasada) y lo que cuentan sus tareas.
function Get-FaseHtml($D, $T, [string]$Fase, [string]$Tipo) {
  $est = if ($D.Estado) { [string]$D.Estado.fase } else { '' }
  $nombres = @($FasesInforme | ForEach-Object { $_[0] })
  $e = 'espera'
  if ($Fase -eq 'correccion') {
    if ($D.Correccion -and $D.Correccion.completa -eq $true) { $e = 'hecha' }
    elseif ($est -eq 'correccion') { $e = 'curso' }
  }
  elseif ($est -eq 'lectura-hecha' -or [array]::IndexOf($nombres, $Fase) -lt [array]::IndexOf($nombres, $est)) { $e = 'hecha' }
  elseif ($Fase -eq $est) { $e = 'curso' }
  $ts = @($D.Tareas | Where-Object { $_.tipo -eq $Tipo })
  $cuenta = Format-Trozo $T 'cuenta-ninguna'
  if ($Fase -eq 'diagnostico') {
    $cuenta = Format-Trozo $T 'sin-valor'
    if ($D.Diag) {
      $cuenta = Format-Trozo $T 'cuenta-diagnostico' @{ ERRORES = "$($D.Diag.Errores)"; AVISOS = "$($D.Diag.Avisos)" }
      if ($D.CobAntes) { $cuenta += Format-Trozo $T 'cuenta-cobertura' @{ VALOR = (Get-CobValor $T $D.CobAntes 'cob-sin-medir') } }
    }
  }
  elseif ($Fase -eq 'correccion') {
    $cuenta = Format-Trozo $T 'sin-valor'
    if ($D.Correccion) { $cuenta = Format-Trozo $T 'cuenta-correccion' @{ COMMITS = "$(@($D.Correccion.commits).Count)"; ATASCADOS = "$(@($D.Correccion.atascados).Count)" } }
  }
  elseif ($ts.Count -gt 0) {
    $c = @{}
    foreach ($s in @('hecha', 'atascada', 'pendiente')) { $c[$s] = "$(@($ts | Where-Object { $_.estado -eq $s }).Count)" }
    $cuenta = Format-Trozo $T 'cuenta-tareas' @{ HECHAS = $c['hecha']; ATASCADAS = $c['atascada']; PENDIENTES = $c['pendiente'] }
  }
  elseif ($Fase -eq 'mapa' -and $D.Mapa) { $cuenta = Format-Trozo $T 'cuenta-jobs' @{ JOBS = "$(@($D.Mapa.jobs).Count)"; SINJOB = "$(@($D.Mapa.sinJob).Count)" } }
  return (Format-Trozo $T 'fase-linea' @{ NOMBRE = (Format-Trozo $T "fase-$Fase"); ESTADO = $e; ESTADO_TEXTO = (Format-Trozo $T "estado-fase-$e"); CUENTA = $cuenta })
}

# Una linea corta de un motivo: la primera con texto, con los espacios juntos y de 220 caracteres como mucho.
function Get-PrimeraLinea([string]$Motivo) {
  $l = @($Motivo -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 1)
  if ($l.Count -eq 0) { return '' }
  $s = ($l[0] -replace '\s+', ' ').Trim()
  if ($s.Length -gt 220) { $s = $s.Substring(0, 220) }
  return $s
}

function Get-GrupoToca($T, [string]$Nombre, $Items, [string]$N) {
  return (Format-Trozo $T 'toca-grupo' @{
      TITULO = (Format-Trozo $T "toca-$Nombre-titulo" @{ N = $N }); TEXTO = (Format-Trozo $T "toca-$Nombre-texto"); ETIQUETA = (Format-Trozo $T 'et-sin')
      ITEMS = (@($Items) -join "`n")
    })
}

# "Lo que te toca": tareas atascadas, clases sin ficha, dudas de las fichas de job, reglas sin caso de prueba, datos
# que nombran clases (los que la pagina de negocio no pinta, y las clases que no cupieron en la redaccion de un job) y
# los datos que el migrado hace distinto o no hace (uno por job y dato).
function Get-TocaHtml($D, $T) {
  $grupos = @()
  $atascadas = @($D.Tareas | Where-Object { $_.estado -eq 'atascada' })
  if ($atascadas.Count -gt 0) {
    $items = @($atascadas | ForEach-Object { Format-Trozo $T 'toca-item' @{ CABECERA = (Format-Trozo $T 'cab-tarea' @{ ID = $_.id; DONDE = $_.entradas.fichero }); TEXTO = (Get-PrimeraLinea $_.motivo) } })
    $grupos += (Get-GrupoToca $T 'atascadas' $items "$($atascadas.Count)")
  }
  $sinFicha = @($D.Vistas | Where-Object { @($_.SinFicha).Count -gt 0 })
  if ($sinFicha.Count -gt 0) {
    $items = @($sinFicha | ForEach-Object { Format-Trozo $T 'toca-item' @{ CABECERA = (Format-Trozo $T 'cab-job' @{ JOB = $_.Job }); TEXTO = (@($_.SinFicha) -join ', ') } })
    $grupos += (Get-GrupoToca $T 'sinficha' $items "$(@($sinFicha | ForEach-Object { @($_.SinFicha).Count } | Measure-Object -Sum).Sum)")
  }
  $dudas = @()
  foreach ($v in @($D.Vistas)) { foreach ($x in @($v.Dudas)) { $dudas += (Format-Trozo $T 'toca-item' @{ CABECERA = (Format-Trozo $T 'cab-job' @{ JOB = $v.Job }); TEXTO = $x }) } }
  if ($dudas.Count -gt 0) { $grupos += (Get-GrupoToca $T 'dudas' $dudas "$($dudas.Count)") }
  $sinCaso = @()
  foreach ($v in @($D.Vistas)) {
    if (-not $v.Pruebas) { continue }
    foreach ($x in @($v.Pruebas.sinCaso | Where-Object { $null -ne $_ })) { $sinCaso += (Format-Trozo $T 'toca-item' @{ CABECERA = (Format-Trozo $T 'cab-job' @{ JOB = $v.Job }); TEXTO = $x.texto }) }
  }
  if ($sinCaso.Count -gt 0) { $grupos += (Get-GrupoToca $T 'sincaso' $sinCaso "$($sinCaso.Count)") }
  $conClase = @()
  foreach ($v in @($D.Vistas)) {
    foreach ($h in @($v.DatosTecnicos)) { $conClase += (Format-Trozo $T 'toca-item' @{ CABECERA = (Format-Trozo $T 'cab-dato' @{ JOB = $v.Job; DONDE = "$($h.fichero):$($h.linea)" }); TEXTO = $h.texto }) }
    if (@($v.Fuera).Count -gt 0) { $conClase += (Format-Trozo $T 'toca-fuera' @{ CABECERA = (Format-Trozo $T 'cab-job' @{ JOB = $v.Job }); CLASES = (@($v.Fuera) -join ', ') }) }
  }
  if ($conClase.Count -gt 0) { $grupos += (Get-GrupoToca $T 'tecnicos' $conClase "$($conClase.Count)") }
  $diferencias = @()
  if ($D.Mapa) {
    foreach ($j in @($D.Mapa.jobs)) {
      foreach ($r in @(Get-DatosComparar $D $j | Where-Object { $_.Estado -ceq 'distinto' -or $_.Estado -ceq 'falta' })) {
        $cab = Format-Trozo $T 'cab-diferencia' @{ JOB = $r.Job; CLASE = $r.Clase; ESTADO = (Format-Trozo $T "comp-est-$($r.Estado)") }
        $diferencias += (Format-Trozo $T 'toca-item' @{ CABECERA = $cab; TEXTO = (($r.Texto + ' ' + $r.Nota).Trim()) })
      }
    }
  }
  if ($diferencias.Count -gt 0) { $grupos += (Get-GrupoToca $T 'diferencias' $diferencias "$($diferencias.Count)") }
  if ($D.Correccion) {
    $atascos = @($D.Correccion.atascados | Where-Object { $null -ne $_ })
    if ($atascos.Count -gt 0) {
      $items = @($atascos | ForEach-Object {
          $cab = ''
          if ($_.paso -or $_.fichero) { $cab = Format-Trozo $T 'cab-arreglo' @{ PASO = $_.paso; DONDE = $_.fichero } }
          Format-Trozo $T 'toca-item' @{ CABECERA = $cab; TEXTO = $_.motivo }
        })
      $grupos += (Get-GrupoToca $T 'arreglos' $items "$($atascos.Count)")
    }
    $nuevas = @($D.Correccion.variablesNuevas | Where-Object { $null -ne $_ })
    if ($nuevas.Count -gt 0) {
      $items = @($nuevas | ForEach-Object { Format-Trozo $T 'toca-item' @{ CABECERA = (Format-Trozo $T 'cab-variable' @{ NOMBRE = $_.variable }); TEXTO = "$($_.fichero):$($_.linea)" } })
      $grupos += (Get-GrupoToca $T 'variables' $items "$($nuevas.Count)")
    }
  }
  if ($grupos.Count -eq 0) { return (Format-Trozo $T 'toca-nada') }
  return ($grupos -join "`n")
}

function Get-FicherosHtml($D, $T) {
  $filas = @()
  foreach ($f in $FicherosInforme) {
    if (-not $f[3] -and -not (Test-Path -LiteralPath (Join-Ruta $D.Salida $f[0]))) { continue }
    $nombre = Format-Trozo $T 'nombre-codigo' @{ TEXTO = $f[0] }
    if ($f[3]) { $nombre = Format-Trozo $T 'nombre-enlace' @{ RUTA = $f[0]; TEXTO = $f[0] } }
    $filas += (Format-Trozo $T 'fichero-linea' @{ ICONO = $f[2]; NOMBRE = $nombre; QUE = (Format-Trozo $T $f[1]) })
  }
  return ($filas -join "`n")
}

# ============================== LA COBERTURA ==============================
# Lo que se dice de una medida de cobertura ($C, de datos\cobertura-<antes|despues>.json): su porcentaje con coma decimal o, si no se
# pudo medir, el trozo $SinMedir (con el motivo); sin fichero ($null), "sin dato".
function Get-CobValor($T, $C, [string]$SinMedir) {
  if ($null -eq $C) { return (Format-Trozo $T 'sin-valor') }
  if ($C.medida -eq $true) { return (Format-Trozo $T 'cob-pct' @{ PCT = "$($C.porcentaje)".Replace('.', ',') }) }
  return (Format-Trozo $T $SinMedir @{ MOTIVO = $C.motivo })
}

# La medida es baja si esta por debajo del minimo que tenia al medirse.
function Test-CobBaja($C) { return ([double]$C.porcentaje -lt [double]$C.minima) }

# "Cumple el minimo de N %." o "Esta por debajo del minimo de N %." de una medida hecha.
function Get-CobVeredicto($T, $C) {
  $n = 'cob-cumple'
  if (Test-CobBaja $C) { $n = 'cob-baja' }
  return (Format-Trozo $T $n @{ MIN = "$($C.minima)" })
}

# El panel de la pagina de problemas: el medidor y las lineas, o por que no se pudo medir. Vacio si no hay medida.
function Get-PanelCobertura($T, $C) {
  if ($null -eq $C) { return '' }
  if ($C.medida -ne $true) {
    return (Format-Trozo $T 'cob-panel' @{ ETIQUETA = (Format-Trozo $T 'et-sin'); CUERPO = (Format-Trozo $T 'cob-sin-cuerpo' @{ TEXTO = (Format-Trozo $T 'cob-no-medida' @{ MOTIVO = $C.motivo }) }) })
  }
  $clase = 'cumple'
  if (Test-CobBaja $C) { $clase = 'baja' }
  $pct = "$($C.porcentaje)".Replace('.', ',')
  $cuerpo = Format-Trozo $T 'cob-medida' @{
    CLASE = $clase; PCT = (Get-CobValor $T $C ''); ETIQUETA_PCT = $pct; V = "$($C.porcentaje)"; U = "$($C.minima)"
    CUBIERTAS = "$($C.cubiertas)"; TOTAL = "$($C.total)"; VEREDICTO = (Get-CobVeredicto $T $C)
  }
  return (Format-Trozo $T 'cob-panel' @{ ETIQUETA = (Format-Trozo $T 'et-medido'); CUERPO = $cuerpo })
}

# La linea de la portada: la cobertura de despues de corregir si la hay y, si no, la de antes. Vacia si no hay ninguna.
function Get-LineaCobertura($D, $T) {
  $c = $D.CobDespues
  $cuando = 'despues'
  if ($null -eq $c) { $c = $D.CobAntes; $cuando = 'antes' }
  if ($null -eq $c) { return '' }
  $etiqueta = Format-Trozo $T 'et-sin'
  $texto = Format-Trozo $T 'cob-no-medida' @{ MOTIVO = $c.motivo }
  if ($c.medida -eq $true) {
    $etiqueta = Format-Trozo $T 'et-medido'
    $texto = Format-Trozo $T 'cob-linea-medida' @{ PCT = (Get-CobValor $T $c ''); CUBIERTAS = "$($c.cubiertas)"; TOTAL = "$($c.total)"; VEREDICTO = (Get-CobVeredicto $T $c) }
  }
  return (Format-Trozo $T 'cob-linea' @{ ETIQUETA = $etiqueta; CUANDO = (Format-Trozo $T "cob-cuando-$cuando"); TEXTO = $texto })
}

# El panel de la pagina de correcciones: la cobertura de antes y la de despues y, si la de despues se midio, si cumple el minimo.
function Get-PanelCoberturaCambio($D, $T) {
  $a = $D.CobAntes
  $d = $D.CobDespues
  if ($null -eq $a -and $null -eq $d) { return '' }
  $etiqueta = Format-Trozo $T 'et-sin'
  if (($a -and $a.medida -eq $true) -or ($d -and $d.medida -eq $true)) { $etiqueta = Format-Trozo $T 'et-medido' }
  $veredicto = ''
  if ($d -and $d.medida -eq $true) { $veredicto = Format-Trozo $T 'cob-cambio-veredicto' @{ TEXTO = (Get-CobVeredicto $T $d) } }
  $cambio = Format-Trozo $T 'cuenta-antes-despues' @{ ANTES = (Get-CobValor $T $a 'cob-sin-medir-motivo'); DESPUES = (Get-CobValor $T $d 'cob-sin-medir-motivo') }
  return (Format-Trozo $T 'cob-cambio' @{ ETIQUETA = $etiqueta; CAMBIO = $cambio; VEREDICTO = $veredicto })
}

# ============================ LA PAGINA DE PROBLEMAS ============================
# "1 error y 2 avisos" ($Forma 'total') o "1 error, 2 avisos" ('par'): la palabra va en singular solo cuando el numero es 1.
function Get-CuentaHtml($T, [int]$Errores, [int]$Avisos, [string]$Forma) {
  $e = 'cuenta-error-otros'
  if ($Errores -eq 1) { $e = 'cuenta-error-uno' }
  $a = 'cuenta-aviso-otros'
  if ($Avisos -eq 1) { $a = 'cuenta-aviso-uno' }
  return (Format-Trozo $T "cuenta-$Forma" @{ ERRORES = (Format-Trozo $T $e @{ N = "$Errores" }); AVISOS = (Format-Trozo $T $a @{ N = "$Avisos" }) })
}

# El nombre de un area: el de la plantilla o, si no lo tiene, su identificador.
function Get-NombreArea($T, [string]$Id) {
  if ($T.ContainsKey("area-$Id")) { return (Format-Trozo $T "area-$Id") }
  return (ConvertTo-TextoHtml $Id)
}

# La frase del estado del build y su etiqueta: Medido si el motor dijo uno de sus cinco textos; si no, no se sabe.
function Get-BuildHtml($T, $Diag) {
  foreach ($b in $TextosBuild) {
    if ($Diag.Estado -ceq $b[0]) { return [pscustomobject]@{ Etiqueta = (Format-Trozo $T 'et-medido'); Frase = (Format-Trozo $T ('estado-build-' + $b[1])) } }
  }
  return [pscustomobject]@{ Etiqueta = (Format-Trozo $T 'et-sin'); Frase = (Format-Trozo $T 'estado-build-desconocido') }
}

function Get-FilaProblemaHtml($T, $H, [string]$Sev) {
  $donde = ''
  if ($H.Fichero) {
    $d = [string]$H.Fichero
    if ([int]$H.Linea -gt 0) { $d += ':' + [int]$H.Linea }
    $donde = Format-Trozo $T 'fila-donde' @{ TEXTO = $d }
  }
  return (Format-Trozo $T 'fila-prob' @{ SEV = $Sev; MARCA = (Format-Trozo $T "marca-$Sev"); DONDE = $donde; DETALLE = $H.Detalle })
}

# Un area con sus hallazgos: primero los errores y luego los avisos, y como se arregla si la plantilla lo sabe.
function Get-GrupoProblemasHtml($T, $A) {
  $filas = @($A.Errores | ForEach-Object { Get-FilaProblemaHtml $T $_ 'error' }) + @($A.Avisos | ForEach-Object { Get-FilaProblemaHtml $T $_ 'aviso' })
  $como = ''
  if ($T.ContainsKey("arregla-$($A.Id)")) { $como = Format-Trozo $T 'area-como' @{ TEXTO = (Format-Trozo $T "arregla-$($A.Id)") } }
  return (Format-Trozo $T 'area-grupo' @{
      ID = $A.Id; NOMBRE = (Get-NombreArea $T $A.Id); CUENTA = (Get-CuentaHtml $T (@($A.Errores).Count) (@($A.Avisos).Count) 'par')
      ETIQUETA = (Format-Trozo $T 'et-medido'); COMO = $como; FILAS = ($filas -join "`n")
    })
}

function Get-CuerpoProblemas($D, $T, [string]$Cuerpo) {
  $diag = Format-Trozo $T 'sin-datos' @{ FASE = 'diagnostico'; ETIQUETA = (Format-Trozo $T 'et-sin') }
  if ($D.Diag) {
    $build = Get-BuildHtml $T $D.Diag
    $ref = Format-Trozo $T 'ref-desconocida' @{ ETIQUETA = (Format-Trozo $T 'et-sin') }
    $i = $D.Diag.Incumple
    if ($i) { $ref = Format-Trozo $T 'ref-cifras' @{ ETIQUETA = (Format-Trozo $T 'et-medido'); CAPAS = $i.Capas; FICHEROS = $i.Ficheros; CALIDAD = $i.Calidad; SECRETOS = $i.Secretos } }
    $respuesta = ''
    if ($D.Estado -and $T.ContainsKey("respuesta-$($D.Estado.respuesta)")) { $respuesta = Format-Trozo $T "respuesta-$($D.Estado.respuesta)" }
    $conErrores = @($D.Diag.Areas | Where-Object { @($_.Errores).Count -gt 0 })
    $soloAvisos = @($D.Diag.Areas | Where-Object { @($_.Errores).Count -eq 0 -and @($_.Avisos).Count -gt 0 })
    $vacias = @($D.Diag.Areas | Where-Object { @($_.Errores).Count -eq 0 -and @($_.Avisos).Count -eq 0 })
    $sinProblemas = ''
    if ($vacias.Count -gt 0) {
      $sinProblemas = Format-Trozo $T 'sin-prob' @{ ETIQUETA = (Format-Trozo $T 'et-medido'); ITEMS = (Format-Lista $T 'sin-prob-item' $vacias { param($a) @{ NOMBRE = (Get-NombreArea $T $a.Id) } }) }
    }
    $diag = Format-Trozo $T 'diagnostico' @{
      ETIQUETA_BUILD = $build.Etiqueta; FRASE = $build.Frase; REFERENCIA = $ref; ETIQUETA = (Format-Trozo $T 'et-medido'); TOTAL = (Get-CuentaHtml $T $D.Diag.Errores $D.Diag.Avisos 'total')
      COBERTURA = (Get-PanelCobertura $T $D.CobAntes); RESPUESTA = $respuesta; GRUPOS = ((@($conErrores) + @($soloAvisos) | ForEach-Object { Get-GrupoProblemasHtml $T $_ }) -join "`n"); SINPROB = $sinProblemas
    }
  }
  return (Expand-Plantilla $Cuerpo @{ MIGRADO = (Get-Hoja $D.Estado.migrado); PLANTILLA = (Get-Hoja $D.Estado.plantilla); DIAGNOSTICO = $diag })
}

# Cada area de las dos fotos, en el orden de la tabla de antes (las que solo salen despues, al final): Antes y Despues (sus errores y
# avisos; vacias si no hay foto de despues), sus Commits y Atascados de la correccion y si Tiene algo que contar.
function Get-AreasCorreccion($D) {
  $c = $D.Correccion
  $areasDespues = @()
  if ($D.Despues) { $areasDespues = @($D.Despues.Areas) }
  $ids = @($D.Diag.Areas | ForEach-Object { $_.Id })
  foreach ($a in $areasDespues) { if ($ids -cnotcontains $a.Id) { $ids += $a.Id } }
  $vacia = [pscustomobject]@{ Errores = @(); Avisos = @() }
  $res = @()
  foreach ($id in $ids) {
    $antes = $vacia
    foreach ($a in @($D.Diag.Areas | Where-Object { $_.Id -ceq $id })) { $antes = $a }
    $despues = $vacia
    foreach ($a in @($areasDespues | Where-Object { $_.Id -ceq $id })) { $despues = $a }
    $commits = @()
    $atascados = @()
    if ($c) {
      $commits = @($c.commits | Where-Object { $null -ne $_ -and $_.paso -ceq $id })
      $atascados = @($c.atascados | Where-Object { $null -ne $_ -and $_.paso -ceq $id })
    }
    $cuantos = @($antes.Errores).Count + @($antes.Avisos).Count + @($despues.Errores).Count + @($despues.Avisos).Count + $commits.Count + $atascados.Count
    $res += [pscustomobject]@{ Id = $id; Antes = $antes; Despues = $despues; Commits = $commits; Atascados = $atascados; Tiene = ($cuantos -gt 0) }
  }
  return $res
}

# Como queda un area: resuelta, lo que queda de errores o sin errores.
function Get-EstadoAreaHtml($T, $A) {
  $antes = @($A.Antes.Errores).Count
  $queda = @($A.Despues.Errores).Count
  if ($queda -eq 0 -and $antes -gt 0) { return (Format-Trozo $T 'estado-area-resuelta') }
  if ($queda -eq 1) { return (Format-Trozo $T 'estado-area-queda' @{ N = '1' }) }
  if ($queda -gt 1) { return (Format-Trozo $T 'estado-area-quedan' @{ N = "$queda" }) }
  return (Format-Trozo $T 'estado-area-sin')
}

# El numero mas alto de errores de un area (antes o despues): la escala de las barras.
function Get-MaxErrores($Areas) {
  $max = 1
  foreach ($a in @($Areas)) { foreach ($n in @(@($a.Antes.Errores).Count, @($a.Despues.Errores).Count)) { if ($n -gt $max) { $max = $n } } }
  return $max
}

# La seccion "Problemas del migrado" de la portada: el estado del build, el total y una barra por area con sus errores
# (y, si ya se ha corregido, su barra de despues y como queda).
function Get-ProblemasPortada($D, $T) {
  if (-not $D.Diag) { return (Format-Trozo $T 'sin-datos' @{ FASE = 'diagnostico'; ETIQUETA = (Format-Trozo $T 'et-sin') }) }
  $ultimo = $D.Diag
  $total = Get-CuentaHtml $T $D.Diag.Errores $D.Diag.Avisos 'total'
  $leyenda = ''
  if ($D.Despues) {
    $ultimo = $D.Despues
    $total = Format-Trozo $T 'cuenta-antes-despues' @{ ANTES = $total; DESPUES = (Get-CuentaHtml $T $D.Despues.Errores $D.Despues.Avisos 'total') }
    $leyenda = Format-Trozo $T 'leyenda-barras'
  }
  $build = Get-BuildHtml $T $ultimo
  $areas = @(Get-AreasCorreccion $D)
  $filas = @($areas | ForEach-Object {
      $n = @($_.Antes.Errores).Count
      if ($n -gt 0 -or @($_.Despues.Errores).Count -gt 0) {
        $barras = Format-Trozo $T 'barra-antes' @{ V = "$n" }
        $estado = ''
        if ($D.Despues) {
          $barras += "`n" + (Format-Trozo $T 'barra-despues' @{ V = "$(@($_.Despues.Errores).Count)" })
          $estado = Format-Trozo $T 'area-estado' @{ TEXTO = (Get-EstadoAreaHtml $T $_) }
        }
        Format-Trozo $T 'area-barra' @{ NOMBRE = (Get-NombreArea $T $_.Id); BARRAS = $barras; ESTADO = $estado }
      }
      else { Format-Trozo $T 'area-limpia' @{ NOMBRE = (Get-NombreArea $T $_.Id) } }
    })
  return (Format-Trozo $T 'prob-datos' @{
      ETIQUETA_BUILD = $build.Etiqueta; BUILD = $build.Frase; COBERTURA = (Get-LineaCobertura $D $T); ETIQUETA = (Format-Trozo $T 'et-medido'); LEYENDA = $leyenda; TOTAL = $total
      MAX = "$(Get-MaxErrores $areas)"; AREAS = ($filas -join "`n")
    })
}

# ============================ LA PAGINA DE CORRECCIONES ============================
# Un area de la pagina de correcciones: sus barras de antes y despues, los commits de arreglo, los atascados con su motivo y
# lo que queda (las mismas filas de la pagina de problemas).
function Get-GrupoCorreccionHtml($T, $A, [int]$Max) {
  $filas = @($A.Despues.Errores | ForEach-Object { Get-FilaProblemaHtml $T $_ 'error' }) + @($A.Despues.Avisos | ForEach-Object { Get-FilaProblemaHtml $T $_ 'aviso' })
  $commits = ''
  if ($A.Commits.Count -gt 0) { $commits = Format-Trozo $T 'area-commits' @{ ITEMS = (Format-Lista $T 'area-commit' $A.Commits { param($x) @{ HASH = $x.hash; ASUNTO = $x.asunto } }) } }
  $atascados = ''
  if ($A.Atascados.Count -gt 0) { $atascados = Format-Trozo $T 'area-atascados' @{ ITEMS = (Get-AtascadosItemsHtml $T $A.Atascados) } }
  $queda = ''
  if ($filas.Count -gt 0) { $queda = Format-Trozo $T 'area-queda' @{ FILAS = ($filas -join "`n") } }
  $barras = ''
  if (@($A.Antes.Errores).Count -gt 0 -or @($A.Despues.Errores).Count -gt 0) {
    $dos = (Format-Trozo $T 'barra-antes' @{ V = "$(@($A.Antes.Errores).Count)" }) + "`n" + (Format-Trozo $T 'barra-despues' @{ V = "$(@($A.Despues.Errores).Count)" })
    $barras = Format-Trozo $T 'area-barras' @{ MAX = "$Max"; BARRAS = $dos }
  }
  $cuenta = Format-Trozo $T 'cuenta-antes-despues' @{
    ANTES = (Get-CuentaHtml $T (@($A.Antes.Errores).Count) (@($A.Antes.Avisos).Count) 'par')
    DESPUES = (Get-CuentaHtml $T (@($A.Despues.Errores).Count) (@($A.Despues.Avisos).Count) 'par')
  }
  return (Format-Trozo $T 'area-corr' @{
      ID = $A.Id; NOMBRE = (Get-NombreArea $T $A.Id); CUENTA = $cuenta; ESTADO = (Get-EstadoAreaHtml $T $A)
      BARRAS = $barras; COMMITS = $commits; ATASCADOS = $atascados; QUEDA = $queda
    })
}

function Get-AtascadosItemsHtml($T, $Atascados) {
  return (Format-Lista $T 'area-atascado' $Atascados {
      param($x)
      $donde = ''
      if ($x.fichero) { $donde = (Format-Trozo $T 'fila-donde' @{ TEXTO = $x.fichero }) + ' ' }
      @{ DONDE = $donde; MOTIVO = $x.motivo }
    })
}

# Lo que cuenta la pagina cuando hay correcciones.json y el diagnostico de despues.
function Get-ResultadoCorreccion($D, $T) {
  $c = $D.Correccion
  $medido = Format-Trozo $T 'et-medido'
  $areas = @(Get-AreasCorreccion $D)
  $max = Get-MaxErrores $areas
  $con = @($areas | Where-Object { $_.Tiene })
  $idsCon = @($con | ForEach-Object { $_.Id })
  $vacias = @($areas | Where-Object { -not $_.Tiene })
  $antes = Get-BuildHtml $T $D.Diag
  $despues = Get-BuildHtml $T $D.Despues
  $sinProblemas = ''
  if ($vacias.Count -gt 0) {
    $sinProblemas = Format-Trozo $T 'sin-prob' @{ ETIQUETA = $medido; ITEMS = (Format-Lista $T 'sin-prob-item' $vacias { param($a) @{ NOMBRE = (Get-NombreArea $T $a.Id) } }) }
  }
  $sueltos = ''
  $fuera = @($c.atascados | Where-Object { $null -ne $_ -and ($idsCon -cnotcontains [string]$_.paso) })
  if ($fuera.Count -gt 0) { $sueltos = Format-Trozo $T 'atascados-sueltos' @{ ITEMS = (Get-AtascadosItemsHtml $T $fuera) } }
  $variables = ''
  $nuevas = @($c.variablesNuevas | Where-Object { $null -ne $_ })
  if ($nuevas.Count -gt 0) {
    $variables = Format-Trozo $T 'variables-nuevas' @{ ETIQUETA = $medido; ITEMS = (Format-Lista $T 'variable-item' $nuevas { param($v) @{ NOMBRE = $v.variable; DONDE = "$($v.fichero):$($v.linea)" } }) }
  }
  $incompleta = ''
  if ($c.completa -ne $true) { $incompleta = Format-Trozo $T 'correccion-incompleta' }
  $total = Format-Trozo $T 'cuenta-antes-despues' @{
    ANTES = (Get-CuentaHtml $T $D.Diag.Errores $D.Diag.Avisos 'total'); DESPUES = (Get-CuentaHtml $T $D.Despues.Errores $D.Despues.Avisos 'total')
  }
  return (Format-Trozo $T 'correccion-datos' @{
      INCOMPLETA = $incompleta; COBERTURA = (Get-PanelCoberturaCambio $D $T); ETIQUETA = $medido; BUILD_ANTES = $antes.Frase; ETIQUETA_ANTES = $antes.Etiqueta; BUILD_DESPUES = $despues.Frase; ETIQUETA_DESPUES = $despues.Etiqueta
      TOTAL = $total; COMMITS = "$(@($c.commits).Count)"; ATASCADOS = "$(@($c.atascados).Count)"; LEYENDA = (Format-Trozo $T 'leyenda-barras')
      GRUPOS = (($con | ForEach-Object { Get-GrupoCorreccionHtml $T $_ $max }) -join "`n"); SINPROB = $sinProblemas; SUELTOS = $sueltos; VARIABLES = $variables
      RAMA = $c.rama; BASE = $c.base; WORKTREE = $D.Estado.worktree; MIGRADO = $D.Estado.migrado
    })
}

function Get-CuerpoCorrecciones($D, $T, [string]$Cuerpo) {
  $sinDatos = Format-Trozo $T 'sin-datos' @{ FASE = 'correccion'; ETIQUETA = (Format-Trozo $T 'et-sin') }
  if (-not $D.Diag) { $sinDatos = Format-Trozo $T 'sin-datos' @{ FASE = 'diagnostico'; ETIQUETA = (Format-Trozo $T 'et-sin') } }
  $pagina = $sinDatos
  if ($D.Diag -and $D.Despues -and $D.Correccion) { $pagina = Get-ResultadoCorreccion $D $T }
  elseif ($D.Estado -and $D.Estado.respuesta -eq 'parar' -and -not $D.Correccion) { $pagina = Format-Trozo $T 'sin-correccion-parar' @{ ETIQUETA = (Format-Trozo $T 'et-sin') } }
  return (Expand-Plantilla $Cuerpo @{ MIGRADO = (Get-Hoja $D.Estado.migrado); CORRECCION = $pagina })
}

function Get-CuerpoIndex($D, $T, [string]$Cuerpo) {
  $est = $D.Estado
  $fase = ''
  $parada = ''
  $estado = ''
  $e = [pscustomobject]@{ batch = ''; legacy = ''; migrado = ''; plantilla = ''; rama = ''; modelo = ''; creado = $null; actualizado = $null; parada = $null; fase = '' }
  if ($est) { $e = $est }
  $fase = [string]$e.fase
  if ($e.parada) {
    $estado = Format-Trozo $T 'estado-parada' @{ FASE = $fase; MOTIVO = $e.parada.motivo }
    $parada = Format-Trozo $T 'parada' @{ MOTIVO = $e.parada.motivo; DETALLE = $e.parada.detalle; REGISTRO = $e.parada.registro; AYUDA = $e.parada.ayuda }
  }
  elseif ($D.Correccion -and $D.Correccion.completa -eq $true) { $estado = Format-Trozo $T 'estado-corregida' }
  elseif ($fase -eq 'lectura-hecha') { $estado = Format-Trozo $T 'estado-hecha' }
  else { $estado = Format-Trozo $T 'estado-curso' @{ FASE = $fase } }
  $modelo = [string]$e.modelo
  if (-not $modelo) { $modelo = Format-Trozo $T 'modelo-defecto' }
  $c = @{}
  foreach ($s in @('hecha', 'atascada', 'pendiente')) { $c[$s] = "$(@($D.Tareas | Where-Object { $_.estado -eq $s }).Count)" }
  $fases = (@($FasesInforme | ForEach-Object { Get-FaseHtml $D $T $_[0] $_[1] }) -join "`n")
  return (Expand-Plantilla $Cuerpo @{
      BATCH = (Get-BatchInforme $D); ESTADO = $estado; MIGRADO = (Get-Hoja $e.migrado); ORIGINAL = (Get-Hoja $e.legacy); PLANTILLA = (Get-Hoja $e.plantilla)
      MODELO = $modelo; EMPEZO = (Get-TextoFecha $T $e.creado); LLEVA = (Get-TextoDuracion $T $e.creado $e.actualizado)
      ETIQUETA = (Format-Trozo $T 'et-medido'); ETIQUETA_FASES = (Format-Trozo $T 'et-medido')
      HECHAS = $c['hecha']; ATASCADAS = $c['atascada']; PENDIENTES = $c['pendiente']; PARADA = $parada
      TOCA = (Get-TocaHtml $D $T); PROBLEMAS = (Get-ProblemasPortada $D $T); FASES = $fases; FICHEROS = (Get-FicherosHtml $D $T)
    })
}

function Merge-Trozos($A, $B) {
  $t = @{}
  foreach ($k in $A.Keys) { $t[$k] = $A[$k] }
  foreach ($k in $B.Keys) { $t[$k] = $B[$k] }
  return $t
}

# Escribe a un fichero temporal y lo mueve: un corte no deja una pagina a medias.
function Save-PaginaInforme([string]$Ruta, [string]$Html) {
  [System.IO.File]::WriteAllText(($Ruta + '.tmp'), ($Html + "`n"), $Utf8)
  Move-Item -LiteralPath ($Ruta + '.tmp') -Destination $Ruta -Force
}

# ================================ PUBLICA ================================
function Write-Informes {
  param([Parameter(Mandatory = $true)][string]$Salida)
  $D = Read-DatosInforme $Salida
  $marco = Split-Plantilla (Read-PlantillaInforme 'marco.html')
  $estilo = Read-PlantillaInforme 'estilo.css'
  $batch = Get-BatchInforme $D
  $paginas = @(
    @{ Fichero = 'index.html'; Actual = 'ACTUAL_INDEX'; Titulo = 'titulo-index'; Cuerpo = { param($D, $T, $C) Get-CuerpoIndex $D $T $C } },
    @{ Fichero = '1-batch-original.html'; Actual = 'ACTUAL_ORIGINAL'; Titulo = 'titulo-original'; Cuerpo = { param($D, $T, $C) Get-CuerpoOriginal $D $T $C } },
    @{ Fichero = '2-problemas.html'; Actual = 'ACTUAL_PROBLEMAS'; Titulo = 'titulo-problemas'; Cuerpo = { param($D, $T, $C) Get-CuerpoProblemas $D $T $C } },
    @{ Fichero = '3-original-vs-migrado.html'; Actual = 'ACTUAL_COMPARAR'; Titulo = 'titulo-comparar'; Cuerpo = { param($D, $T, $C) Get-CuerpoComparar $D $T $C } },
    @{ Fichero = '4-correcciones.html'; Actual = 'ACTUAL_CORRECCIONES'; Titulo = 'titulo-correcciones'; Cuerpo = { param($D, $T, $C) Get-CuerpoCorrecciones $D $T $C } }
  )
  foreach ($p in $paginas) {
    $plantilla = Split-Plantilla (Read-PlantillaInforme $p.Fichero)
    $T = Merge-Trozos $marco.Trozos $plantilla.Trozos
    $v = @{ TITULO = (Format-Trozo $T $p.Titulo @{ BATCH = $batch }); ESTILO = $estilo; BATCH = $batch; CUERPO = (& $p.Cuerpo $D $T $plantilla.Cuerpo); ACTUAL_INDEX = ''; ACTUAL_ORIGINAL = ''; ACTUAL_PROBLEMAS = ''; ACTUAL_COMPARAR = ''; ACTUAL_CORRECCIONES = '' }
    $v[$p.Actual] = Format-Trozo $T 'actual'
    Save-PaginaInforme (Join-Path $Salida $p.Fichero) (Expand-Plantilla $marco.Cuerpo $v)
  }
}
