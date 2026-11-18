<#
informe.ps1 - Las paginas HTML del informe de migracion: la portada (index.html), que hace el batch original
(1-batch-original.html) y los problemas del migrado (2-problemas.html). Las monta el script con los datos de datos\ (sin IA,
sin JavaScript y sin nada externo: se abren con doble clic). Compatible con Windows PowerShell 5.1 y PowerShell 7. Solo ASCII a proposito: todo el texto
que ve la persona (con sus acentos) esta en las plantillas de informe\ (marco.html, index.html,
1-batch-original.html y 2-problemas.html; estilo.css se incrusta dentro de cada pagina).
Se carga con '. (Join-Path $PSScriptRoot 'informe.ps1')' despues de comun.ps1 y tareas.ps1, desde migracion.ps1 o
desde cualquier script que lo necesite. Cargarlo no ejecuta nada.

FUNCION PUBLICA
  Write-Informes -Salida <carpeta migracion-<batch>>
    Lee <Salida>\datos (estado.json, tareas\, fichas\, mapa.json, jobs\, resumen.json, pruebas\, variables.json,
    hallazgos-antes.json y diagnostico-antes.md) y escribe <Salida>\index.html, <Salida>\1-batch-original.html y
    <Salida>\2-problemas.html con lo que haya. Un dato que falta (una fase sin hacer)
    sale como "todavia no hay datos: la fase X no ha terminado". Volver a llamarla con los mismos datos deja los mismos
    bytes (las paginas no dependen de la hora). Todo texto que viene de los datos se escapa.

  Read-Diagnostico -Datos <carpeta datos>
    Los problemas del migrado (hallazgos-antes.json y diagnostico-antes.md): por area, en el orden de la tabla del .md, con
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
$FasesInforme = @(@('fichas-clase', 'ficha-clase'), @('mapa', 'definicion-job'), @('fichas-job', 'ficha-job'), @('resumen', 'resumen'), @('pruebas-pre', 'prueba-pre'))
# Los cinco textos que el motor escribe en la linea "- Estado:" de diagnostico.md y el trozo de la frase de cada uno
$TextosBuild = @(
  @('compila: no comprobado', 'no-comprobado'), @('compila: NO', 'no'), @('compila: SI | tests: no ejecutados', 'sin-tests'),
  @('compila: SI | tests: OK', 'ok'), @('compila: SI | tests: FALLAN', 'fallan')
)
# Los ficheros de la carpeta del informe: ruta, trozo que lo explica, icono y si es una pagina del informe
$FicherosInforme = @(
  @('index.html', 'f-index', 'f-fichero', $true), @('1-batch-original.html', 'f-original', 'f-fichero', $true),
  @('datos', 'f-datos', 'f-carpeta', $false), @('datos/estado.json', 'f-estado', 'f-fichero', $false),
  @('datos/mapa.json', 'f-mapa', 'f-fichero', $false), @('datos/resumen.json', 'f-resumen', 'f-fichero', $false),
  @('datos/variables.json', 'f-variables', 'f-fichero', $false), @('datos/jobs', 'f-jobs', 'f-carpeta', $false),
  @('datos/pruebas', 'f-pruebas', 'f-carpeta', $false), @('datos/fichas', 'f-fichas', 'f-carpeta', $false),
  @('datos/tareas', 'f-tareas', 'f-carpeta', $false), @('registros', 'f-registros', 'f-carpeta', $false)
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
  if ($ficha) {
    if ($hecha) { $titulo = $ficha.titulo; $paraQue = $ficha.paraQue }
    $dudas = @($ficha.dudas | Where-Object { $null -ne $_ })
    $sinFicha = @($ficha.sinFicha | Where-Object { $null -ne $_ })
  }
  $sinCaso = @()
  if ($pruebas) { $sinCaso = @($pruebas.sinCaso | Where-Object { $null -ne $_ -and -not (Test-HechoTecnico $tecnicos $_) }) }
  $motivo = ''
  if ($D.Resumen) { $m = @($D.Resumen.orden | Where-Object { $_.job -ceq $J.job })[0]; if ($m) { $motivo = $m.motivo } }
  return [pscustomobject]@{
    Job = $J.job; Id = $id; Ficha = $ficha; Pruebas = $pruebas; Hecha = $hecha; Titulo = $titulo; ParaQue = $paraQue; Motivo = $motivo
    Pasos = $pasos; Citados = $citados; Otros = $otros; Necesita = $necesita; Produce = $produce; Dudas = $dudas; SinFicha = $sinFicha
    DatosTecnicos = $datosTecnicos; SinCaso = $sinCaso
  }
}

# Los problemas del migrado que dejo la fase diagnostico: hallazgos-antes.json y diagnostico-antes.md. El orden de las areas es el
# de la tabla del .md (las que solo salen en los hallazgos, al final). $null si falta alguno de los dos o el .json no se lee.
function Read-Diagnostico([string]$Datos) {
  $rj = Join-Path $Datos 'hallazgos-antes.json'
  $rm = Join-Path $Datos 'diagnostico-antes.md'
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
  $estado = [regex]::Match($md, '(?m)^- Estado: (.*)$').Groups[1].Value.Trim()
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
    Tareas = $tareas; Indice = (Get-IndiceHechos $Salida); Vistas = @(); Diag = (Read-Diagnostico $datos)
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
  if ($est -eq 'lectura-hecha' -or [array]::IndexOf($nombres, $Fase) -lt [array]::IndexOf($nombres, $est)) { $e = 'hecha' }
  elseif ($Fase -eq $est) { $e = 'curso' }
  $ts = @($D.Tareas | Where-Object { $_.tipo -eq $Tipo })
  $cuenta = Format-Trozo $T 'cuenta-ninguna'
  if ($ts.Count -gt 0) {
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

# "Lo que te toca": tareas atascadas, clases sin ficha, dudas de las fichas de job, reglas sin caso de prueba y datos
# que nombran clases (los que la pagina de negocio no pinta).
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
  }
  if ($conClase.Count -gt 0) { $grupos += (Get-GrupoToca $T 'tecnicos' $conClase "$($conClase.Count)") }
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

# ============================ LA PAGINA DE PROBLEMAS ============================
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
      ID = $A.Id; NOMBRE = (Get-NombreArea $T $A.Id); ERRORES = "$(@($A.Errores).Count)"; AVISOS = "$(@($A.Avisos).Count)"
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
      ETIQUETA_BUILD = $build.Etiqueta; FRASE = $build.Frase; REFERENCIA = $ref; ETIQUETA = (Format-Trozo $T 'et-medido'); ERRORES = "$($D.Diag.Errores)"; AVISOS = "$($D.Diag.Avisos)"
      RESPUESTA = $respuesta; GRUPOS = ((@($conErrores) + @($soloAvisos) | ForEach-Object { Get-GrupoProblemasHtml $T $_ }) -join "`n"); SINPROB = $sinProblemas
    }
  }
  return (Expand-Plantilla $Cuerpo @{ MIGRADO = (Get-Hoja $D.Estado.migrado); PLANTILLA = (Get-Hoja $D.Estado.plantilla); DIAGNOSTICO = $diag })
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
      TOCA = (Get-TocaHtml $D $T); FASES = $fases; FICHEROS = (Get-FicherosHtml $D $T)
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
    @{ Fichero = '2-problemas.html'; Actual = 'ACTUAL_PROBLEMAS'; Titulo = 'titulo-problemas'; Cuerpo = { param($D, $T, $C) Get-CuerpoProblemas $D $T $C } }
  )
  foreach ($p in $paginas) {
    $plantilla = Split-Plantilla (Read-PlantillaInforme $p.Fichero)
    $T = Merge-Trozos $marco.Trozos $plantilla.Trozos
    $v = @{ TITULO = (Format-Trozo $T $p.Titulo @{ BATCH = $batch }); ESTILO = $estilo; BATCH = $batch; CUERPO = (& $p.Cuerpo $D $T $plantilla.Cuerpo); ACTUAL_INDEX = ''; ACTUAL_ORIGINAL = ''; ACTUAL_PROBLEMAS = '' }
    $v[$p.Actual] = Format-Trozo $T 'actual'
    Save-PaginaInforme (Join-Path $Salida $p.Fichero) (Expand-Plantilla $marco.Cuerpo $v)
  }
}
