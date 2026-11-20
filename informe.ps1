<#
informe.ps1 - Las paginas HTML del informe de migracion: la portada (index.html), que hace el batch original
(1-batch-original.html), los problemas del migrado (2-problemas.html), el original frente al migrado (3-original-vs-migrado.html),
lo que se ha corregido (4-correcciones.html) y las buenas practicas del migrado (5-buenas-practicas.html). Las monta el script con los datos de datos\ (sin IA,
sin JavaScript y sin nada externo: se abren con doble clic). Compatible con Windows PowerShell 5.1 y PowerShell 7. Solo ASCII a proposito: todo el texto
que ve la persona (con sus acentos) esta en las plantillas de informe\ (marco.html, index.html,
1-batch-original.html, 2-problemas.html, 3-original-vs-migrado.html, 4-correcciones.html y 5-buenas-practicas.html; estilo.css se incrusta dentro de cada pagina).
Se carga con '. (Join-Path $PSScriptRoot 'informe.ps1')' despues de comun.ps1 y tareas.ps1, desde migracion.ps1 o
desde cualquier script que lo necesite. Cargarlo no ejecuta nada.

FUNCION PUBLICA
  Write-Informes -Salida <carpeta migracion-<batch>>
    Lee <Salida>\datos (estado.json, tareas\, fichas\, mapa.json, lanzadores.json, fichas-sh\, comparacion-sh\, jobs\, resumen.json, pruebas\, comparacion\, variables.json,
    hallazgos-antes.json, diagnostico-antes.md, hallazgos-despues.json, diagnostico-despues.md, correcciones.json, prueba-local.json y practicas-<Cuando>.json) y escribe
    <Salida>\index.html, 1-batch-original.html, 2-problemas.html, 3-original-vs-migrado.html, 4-correcciones.html y 5-buenas-practicas.html con lo que haya. Un dato que falta (una fase sin hacer)
    sale como "todavia no hay datos: la fase X no ha terminado". Volver a llamarla con los mismos datos deja los mismos
    bytes (las paginas no dependen de la hora). Todo texto que viene de los datos se escapa.

  Get-SiguientePaso -Est <estado.json> -D <datos del informe>
    Lo unico que le toca hacer ahora a la persona, y su comando listo para copiar: la primera de ocho situaciones que se cumple (ver FLUJO.md,
    "Siguiente paso"). Devuelve Caso (el nombre de la situacion; la portada tiene un texto por cada una), Comando y los datos que el texto
    usa. La portada lo pone en un recuadro arriba del todo. $D lleva Correccion, PruebaLocal y Diag; sin ellos, cuentan como vacios.

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
# De que tipo son las tareas de cada fase del script (las demas fases no tienen tareas)
$TipoFase = @{ 'fichas-clase' = 'ficha-clase'; 'mapa' = 'definicion-job'; 'fichas-job' = 'ficha-job'; 'lanzadores' = 'ficha-sh'; 'resumen' = 'resumen'; 'pruebas-pre' = 'prueba-pre'; 'casos-pre' = 'caso-pre'; 'comparar' = 'comparar-pieza' }
# Los cinco textos que el motor escribe en la linea "- Estado:" de diagnostico.md y el trozo de la frase de cada uno
$TextosBuild = @(
  @('compila: no comprobado', 'no-comprobado'), @('compila: NO', 'no'), @('compila: SI | tests: no ejecutados', 'sin-tests'),
  @('compila: SI | tests: OK', 'ok'), @('compila: SI | tests: FALLAN', 'fallan')
)
# Los ficheros de la carpeta del informe: ruta, trozo que lo explica, icono y si es una pagina del informe
$FicherosInforme = @(
  @('index.html', 'f-index', 'f-fichero', $true), @('1-batch-original.html', 'f-original', 'f-fichero', $true), @('2-problemas.html', 'f-problemas', 'f-fichero', $true),
  @('3-original-vs-migrado.html', 'f-comparar', 'f-fichero', $true), @('4-correcciones.html', 'f-correcciones', 'f-fichero', $true), @('5-buenas-practicas.html', 'f-practicas', 'f-fichero', $true),
  @('datos', 'f-datos', 'f-carpeta', $false), @('datos/estado.json', 'f-estado', 'f-fichero', $false),
  @('datos/hallazgos-antes.json', 'f-hallazgos', 'f-fichero', $false), @('datos/diagnostico-antes.md', 'f-diagnostico', 'f-fichero', $false),
  @('datos/hallazgos-despues.json', 'f-hallazgos-despues', 'f-fichero', $false), @('datos/diagnostico-despues.md', 'f-diagnostico-despues', 'f-fichero', $false),
  @('datos/cobertura-antes.json', 'f-cobertura-antes', 'f-fichero', $false), @('datos/cobertura-despues.json', 'f-cobertura-despues', 'f-fichero', $false),
  @('datos/practicas-antes.json', 'f-practicas-antes-json', 'f-fichero', $false), @('datos/practicas-despues.json', 'f-practicas-despues-json', 'f-fichero', $false),
  @('datos/tests-reglas.json', 'f-tests-reglas-json', 'f-fichero', $false),
  @('datos/correcciones.json', 'f-correcciones-json', 'f-fichero', $false), @('datos/prueba-local.json', 'f-prueba-local-json', 'f-fichero', $false),
  @('datos/prueba-local-cobertura.json', 'f-prueba-local-cobertura-json', 'f-fichero', $false),
  @('datos/mapa.json', 'f-mapa', 'f-fichero', $false), @('datos/resumen.json', 'f-resumen', 'f-fichero', $false),
  @('datos/variables.json', 'f-variables', 'f-fichero', $false), @('datos/jobs', 'f-jobs', 'f-carpeta', $false),
  @('datos/pruebas', 'f-pruebas', 'f-carpeta', $false), @('datos/comparacion', 'f-comparacion', 'f-carpeta', $false), @('datos/fichas', 'f-fichas', 'f-carpeta', $false),
  @('datos/lanzadores.json', 'f-lanzadores-json', 'f-fichero', $false), @('datos/fichas-sh', 'f-fichas-sh', 'f-carpeta', $false),
  @('datos/comparacion-sh', 'f-comparacion-sh', 'f-carpeta', $false),
  @('datos/tareas', 'f-tareas', 'f-carpeta', $false), @('registros', 'f-registros', 'f-carpeta', $false),
  @('registros/correccion.log', 'f-correccion-log', 'f-fichero', $false), @('prueba-local', 'f-prueba-local', 'f-carpeta', $false),
  @('registros/prueba-local.log', 'f-prueba-local-log', 'f-fichero', $false),
  @('registros/cobertura-antes.log', 'f-cobertura-antes-log', 'f-fichero', $false), @('registros/cobertura-despues.log', 'f-cobertura-despues-log', 'f-fichero', $false),
  @('registros/practicas-antes.log', 'f-practicas-antes-log', 'f-fichero', $false), @('registros/practicas-despues.log', 'f-practicas-despues-log', 'f-fichero', $false)
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
  $r = [ordered]@{}
  $dir = Join-Path $Carpeta 'comparacion'
  if (-not (Test-Path -LiteralPath $dir)) { return $r }
  foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -Filter 'clase-*.json' | Sort-Object Name)) {
    $x = Read-JsonSuave $f.FullName
    if ($x) { $r[[string]$x.ficha] = $x }
  }
  return $r
}

# Los JSON de datos\<Sub>\sh-*.json (fichas-sh o comparacion-sh), por el campo $Clave: el id del lanzador.
function Read-PorLanzador([string]$Carpeta, [string]$Sub, [string]$Clave) {
  $r = [ordered]@{}
  $dir = Join-Path $Carpeta $Sub
  if (-not (Test-Path -LiteralPath $dir)) { return $r }
  foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -Filter 'sh-*.json' | Sort-Object Name)) {
    $x = Read-JsonSuave $f.FullName
    if ($x) { $r[[string]$x.$Clave] = $x }
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
    Correccion = (Read-JsonSuave (Join-Path $datos 'correcciones.json')); PruebaLocal = (Read-JsonSuave (Join-Path $datos 'prueba-local.json'))
    CobAntes = (Read-JsonSuave (Join-Path $datos 'cobertura-antes.json')); CobDespues = (Read-JsonSuave (Join-Path $datos 'cobertura-despues.json'))
    Practicas = (Read-Practicas $datos); Arreglos = (Read-JsonSuave (Join-Path $datos 'practicas-arreglos.json'))
    Reglas = (Read-JsonSuave (Join-Path $datos 'tests-reglas.json'))
    Comparacion = (Read-Comparaciones $datos); CoberturaCasos = (Read-JsonSuave (Join-Path $datos 'prueba-local-cobertura.json')); LineasCasos = $null
    Lanzadores = @(); LanzadoresLeidos = $false
    FichasSh = (Read-PorLanzador $datos 'fichas-sh' 'id'); ComparacionSh = (Read-PorLanzador $datos 'comparacion-sh' 'ficha')
  }
  if ($D.CoberturaCasos -and [string]$D.CoberturaCasos.estado -ceq 'ok') { $D.LineasCasos = Get-LineasCasos $D.CoberturaCasos }
  $lz = Read-JsonSuave (Join-Path $datos 'lanzadores.json')
  if ($lz) { $D.LanzadoresLeidos = $true; $D.Lanzadores = @($lz.lanzadores | Where-Object { $null -ne $_ }) }
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
      # un secreto con valor por defecto no se ensena (un variables.json de antes no lleva la marca: vale el nombre de la variable)
      if ($x.secreto -eq $true -or ($null -ne $x.porDefecto -and (Test-NombreSecreto @($x.variable)))) { @{ NOMBRE = $x.variable; VALOR = (Format-Trozo $T 'var-secreto') } }
      elseif ($null -ne $x.porDefecto) { @{ NOMBRE = $x.variable; VALOR = (Format-Trozo $T 'var-defecto' @{ VALOR = $x.porDefecto }) } }
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
    return (Format-Trozo $T 'job-pendiente' @{ ID = $V.Id; N = "$N"; JOB = $V.Job; SINDATOS = (Format-Trozo $T 'sin-datos' @{ FASE = 'fichas-job'; ETIQUETA = (Format-Trozo $T 'et-sin') }); LANZA = (Get-LanzaJobHtml $D $T $V.Job) })
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
      PRE = (Get-PreHtml $D $T $V); LANZA = (Get-LanzaJobHtml $D $T $V.Job)
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
  return (Expand-Plantilla $Cuerpo @{ BATCH = (Get-BatchInforme $D); ORIGINAL = (Get-Hoja $D.Estado.legacy); ETIQUETA = $et; RESUMEN = $resumen; RECORRIDO = $recorrido; LANZADORES = (Get-LanzadoresOriginal $D $T); JOBS = $jobs; GLOSARIO = $glosario })
}

# ============================== EL ORIGINAL FRENTE AL MIGRADO ==============================
# Las lineas de una lista de rangos ordenados ("12-15,18,30-41") como un conjunto. Un trozo que no se entiende se salta.
function ConvertTo-ConjuntoLineas([string]$Rangos) {
  $c = New-Object 'System.Collections.Generic.HashSet[int]'
  foreach ($t in @($Rangos.Split(',') | Where-Object { $_.Trim() })) {
    $p = $t.Trim().Split('-')
    $a = 0; $b = 0
    if ($p.Count -gt 2 -or -not [int]::TryParse($p[0], [ref]$a)) { continue }
    if ($p.Count -eq 1) { $b = $a } elseif (-not [int]::TryParse($p[1], [ref]$b)) { continue }
    for ($i = $a; $i -le $b; $i++) { [void]$c.Add($i) }
  }
  return ,$c
}

# Lo que recorrieron los casos, por fichero del original (datos\prueba-local-cobertura.json): las lineas de los casos que salieron iguales en los dos
# lados, las de los que salieron distintos (una linea puede estar en las dos) y las que no recorrio ninguno.
function Get-LineasCasos($Cob) {
  $r = @{}
  if ($Cob.ficheros) {
    foreach ($f in $Cob.ficheros.PSObject.Properties) {
      $r[$f.Name] = @{
        Igual = (ConvertTo-ConjuntoLineas ([string]$f.Value.igual)); Distinto = (ConvertTo-ConjuntoLineas ([string]$f.Value.distinto)); SinCubrir = (ConvertTo-ConjuntoLineas ([string]$f.Value.sinCubrir))
      }
    }
  }
  return $r
}

# Que hicieron los casos con la linea de un dato del original: ejecutado-distinto (alguno que salio distinto la ejecuto, aunque otros salieran iguales),
# ejecutado-igual o sin-ejecutar (esta en sinCubrir). Vacio si los casos no se midieron, si el fichero no viene en el JSON o si la linea no esta en ninguna
# de las tres listas: no es codigo para JaCoCo (una anotacion, una declaracion) y no se puede decir que ningun caso la recorra.
function Get-EjecucionLinea($D, [string]$Fichero, [int]$Linea) {
  $f = $null
  if ($null -ne $D.LineasCasos) { $f = $D.LineasCasos[$Fichero] }
  if (-not $f) { return '' }
  if ($f.Distinto.Contains($Linea)) { return 'ejecutado-distinto' }
  if ($f.Igual.Contains($Linea)) { return 'ejecutado-igual' }
  if ($f.SinCubrir.Contains($Linea)) { return 'sin-ejecutar' }
  return ''
}

# Las filas de la comparacion de un job del mapa: por cada clase del job (en su orden) y cada dato de su comparacion, lo que dijo
# la IA (o el script, en sin-pieza) junto al dato del original y lo que hicieron los casos con su linea.
function Get-DatosComparar($D, $J) {
  $filas = @()
  foreach ($cl in @($J.clases)) {
    $c = $D.Comparacion[[string]$cl.ficha]
    if (-not $c) { continue }
    foreach ($dato in @($c.datos)) {
      $h = $D.Indice["$($cl.ficha)#$($dato.dato)"]
      $texto = ''; $original = ''; $citaOriginal = ''; $ejecucion = ''
      if ($h) { $texto = $h.texto; $original = "$($h.fichero):$($h.linea)"; $citaOriginal = $h.cita; $ejecucion = Get-EjecucionLinea $D ([string]$h.fichero) ([int]$h.linea) }
      $migrado = ''
      if ($dato.fichero) { $migrado = "$($dato.fichero):$($dato.linea)" }
      $filas += [pscustomobject]@{
        Job = $J.job; Clase = $c.clase; Estado = [string]$dato.estado; Texto = $texto; Original = $original; CitaOriginal = $citaOriginal
        Migrado = $migrado; CitaMigrado = [string]$dato.cita; Nota = [string]$dato.nota; Probado = ($dato.probado -eq $true); Ejecucion = $ejecucion
      }
    }
  }
  return $filas
}

# Medido (lo cuenta el script) en sin-pieza; leido por la IA con prueba si la cita salio en el fichero; sin comprobar en lo demas.
function Get-MarcaComparar($T, $R) {
  if ($R.Estado -ceq 'sin-pieza' -or $R.Medido) { return (Format-Trozo $T 'marca-medido') }
  return (Get-MarcaHecho $T ($R.Probado -and $R.Migrado))
}

function Get-FilaComparar($T, $R) {
  $clase = ''
  if ($R.Estado -ceq 'distinto') { $clase = 's-error' } elseif ($R.Estado -cne 'igual') { $clase = 's-aviso' }
  $migrado = ''
  if ($R.Migrado) { $migrado = Format-Trozo $T 'comp-migrado' @{ DONDE = $R.Migrado; CITA = $R.CitaMigrado } }
  $nota = ''
  if ($R.Nota) { $nota = Format-Trozo $T 'comp-nota' @{ NOTA = $R.Nota } }
  $ejecucion = ''
  if ($R.Ejecucion) { $ejecucion = Format-Trozo $T "comp-$($R.Ejecucion)" }
  return (Format-Trozo $T 'comp-fila' @{
      CLASE = $clase; ESTADO = (Format-Trozo $T "comp-est-$($R.Estado)"); TEXTO = $R.Texto; MARCA = (Get-MarcaComparar $T $R); EJECUCION = $ejecucion
      NOMBRE = $R.Clase; ORIGINAL = $R.Original; CITA = $R.CitaOriginal; MIGRADO = $migrado; NOTA = $nota
    })
}

# Las filas de un estado: primero las que ejecuto algun caso que salio distinto, despues las que ningun caso recorre, las que no llevan etiqueta y al final
# las que salieron iguales. Sin medida la ejecucion va vacia en todas y el orden es el de siempre.
function Sort-PorEjecucion($Filas) {
  return @(foreach ($e in @('ejecutado-distinto', 'sin-ejecutar', '', 'ejecutado-igual')) { @($Filas | Where-Object { [string]$_.Ejecucion -ceq $e }) })
}

# Un job: la cabecera con sus cuentas, primero los distintos, las faltas, los que no sabe y los sin pieza, y los iguales plegados.
function Get-GrupoComparar($D, $T, $J) {
  $filas = @(Get-DatosComparar $D $J)
  $n = @{ 'igual' = 0; 'distinto' = 0; 'falta' = 0; 'no-lo-se' = 0; 'sin-pieza' = 0 }
  foreach ($f in $filas) { $n[$f.Estado]++ }
  $primeras = @(foreach ($e in @('distinto', 'falta', 'no-lo-se', 'sin-pieza')) { Sort-PorEjecucion @($filas | Where-Object { $_.Estado -ceq $e }) })
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

# La linea de momento de la lectura de la IA: sale de la primera comparacion que lleve momento (antes o despues de corregir) y su commit.
function Get-MomentoComparar($D, $T) {
  foreach ($c in @($D.Comparacion.Values)) {
    if ($c.momento -ceq 'antes-de-corregir') { return (Format-Trozo $T 'comp-momento-antes' @{ COMMIT = [string]$c.commit }) }
    if ($c.momento -ceq 'despues-de-corregir') { return (Format-Trozo $T 'comp-momento-despues' @{ COMMIT = [string]$c.commit }) }
  }
  return ''
}

# ============================== LOS LANZADORES (.sh) ==============================
# Todo lo que las paginas cuentan de un lanzador: su ficha, lo que dijo la comparacion de cada accion y como va su tarea.
function Get-VistaLanzador($D, $Z) {
  $id = [string]$Z.id
  $ficha = $D.FichasSh[$id]
  $comp = $D.ComparacionSh[$id]
  $motivo = ''
  $tarea = @($D.Tareas | Where-Object { $_.tipo -eq 'ficha-sh' -and [string]$_.ficha -ceq $id })
  if ($tarea.Count -gt 0 -and $tarea[0].estado -eq 'atascada') { $motivo = Get-PrimeraLinea ([string]$tarea[0].motivo) }
  $porAccion = @{}
  if ($comp) { foreach ($c in @($comp.acciones | Where-Object { $null -ne $_ })) { $porAccion[[int]$c.accion] = $c } }
  return [pscustomobject]@{
    Id = $id; Rel = [string]$Z.rel; Jobs = @($Z.jobs | Where-Object { $null -ne $_ }); Como = [string]$Z.enlace.como; Linea = $Z.enlace.linea
    Donde = "$($Z.enlace.fichero):$($Z.enlace.linea)"; Ficha = $ficha; PorAccion = $porAccion; Motivo = $motivo
    Acciones = @($ficha.acciones | Where-Object { $null -ne $_ })
  }
}

# Como se supo a que job lanza un script (la tabla de la pagina 1): el unico job del batch lleva su marca.
function Get-ComoLanzador($T, $V) {
  switch ($V.Como) {
    'argumento' { return (Format-Trozo $T 'lanz-como-argumento' @{ LINEA = "$($V.Linea)" }) }
    'yml' { return (Format-Trozo $T 'lanz-como-yml' @{ DONDE = $V.Donde }) }
    'profile' { return (Format-Trozo $T 'lanz-como-profile' @{ DONDE = $V.Donde }) }
    'unico' { return (Format-Trozo $T 'lanz-como-unico' @{ MARCA = (Format-Trozo $T 'lanz-marca-unico') }) }
    default { return (Format-Trozo $T 'lanz-como-sin-enlazar') }
  }
}

# Lo que cuenta un script de como se lanza: para que, parametros, lo de antes y despues del java y los codigos de salida.
function Get-CuerpoLanzador($D, $T, $V) {
  if (-not $V.Ficha) {
    if ($V.Motivo) { return (Format-Trozo $T 'lanza-atascada' @{ MOTIVO = $V.Motivo }) }
    return (Format-Trozo $T 'sin-datos' @{ FASE = 'lanzadores'; ETIQUETA = (Format-Trozo $T 'et-sin') })
  }
  $f = $V.Ficha
  $params = Format-Trozo $T 'lanza-sin-params'
  $ps = @($f.parametros | Where-Object { $null -ne $_ })
  if ($ps.Count -gt 0) {
    $params = Format-Trozo $T 'lanza-params' @{ ITEMS = (Format-Lista $T 'lanza-param' $ps { param($x)
          $obl = 'lanza-opcional'
          if ($x.obligatorio -eq $true) { $obl = 'lanza-obligatorio' }
          $val = ''
          if ($x.valores) { $val = Format-Trozo $T 'lanza-valores' @{ VALORES = $x.valores } }
          $fmt = ''
          if ($x.formato) { $fmt = Format-Trozo $T 'lanza-formato' @{ FORMATO = $x.formato } }
          @{ NOMBRE = $x.nombre; OBLIGATORIO = (Format-Trozo $T $obl); VALORES = $val; FORMATO = $fmt; MARCA = (Get-MarcaHecho $T ($x.probado -eq $true)) }
        }) }
  }
  $grupos = @()
  foreach ($c in @('antes', 'despues', 'siempre', 'si-falla')) {
    $as = @($V.Acciones | Where-Object { [string]$_.cuando -ceq $c })
    if ($as.Count -eq 0) { continue }
    $grupos += (Format-Trozo $T 'lanza-acciones' @{ TITULO = (Format-Trozo $T "lanza-cuando-$c"); ITEMS = (Format-Lista $T 'lanza-accion' $as { param($x)
            $cond = ''
            if ($x.condicion) { $cond = Format-Trozo $T 'lanza-condicion' @{ TEXTO = $x.condicion } }
            @{ CONDICION = $cond; DETALLE = $x.detalle; MARCA = (Get-MarcaHecho $T ($x.probado -eq $true)); DONDE = "$($V.Rel):$($x.linea)" }
          }) })
  }
  $salidas = ''
  $ss = @($f.salidas | Where-Object { $null -ne $_ })
  if ($ss.Count -gt 0) {
    $items = @($ss | ForEach-Object {
        $marca = Get-MarcaHecho $T ($_.probado -eq $true)
        if ([int]$_.codigo -lt 0) { Format-Trozo $T 'lanza-salida-variable' @{ CUANDO = $_.cuando; MARCA = $marca } }
        else { Format-Trozo $T 'lanza-salida' @{ CODIGO = "$($_.codigo)"; CUANDO = $_.cuando; MARCA = $marca } }
      })
    $salidas = Format-Trozo $T 'lanza-salidas' @{ ITEMS = ($items -join "`n") }
  }
  return (Format-Trozo $T 'lanza-cuerpo' @{ PARAQUE = $f.paraQue; PARAMETROS = $params; ACCIONES = ($grupos -join "`n"); SALIDAS = $salidas })
}

function Get-ScriptLanzadorHtml($D, $T, $V, [string]$Enlace) {
  return (Format-Trozo $T 'lanza-script' @{ SCRIPT = $V.Rel; ENLACE = $Enlace; CUERPO = (Get-CuerpoLanzador $D $T $V) })
}

# El bloque Como se lanza de un job: sus scripts, uno detras de otro. Sin scripts enlazados con el job, nada.
function Get-LanzaJobHtml($D, $T, [string]$Job) {
  $vs = @($D.Lanzadores | Where-Object { @($_.jobs) -ccontains $Job } | ForEach-Object { Get-VistaLanzador $D $_ })
  if ($vs.Count -eq 0) { return '' }
  $scripts = @($vs | ForEach-Object {
      $enlace = ''
      if ($_.Como -ceq 'unico') { $enlace = Format-Trozo $T 'lanz-marca-unico' }
      Get-ScriptLanzadorHtml $D $T $_ $enlace
    })
  return (Format-Trozo $T 'lanza' @{ SCRIPTS = ($scripts -join "`n") })
}

# El panel de la pagina 1: la tabla lanzador -> job y, debajo, lo de los scripts que no se pudieron enlazar con ningun job.
function Get-LanzadoresOriginal($D, $T) {
  if (-not $D.LanzadoresLeidos) { return (Format-Trozo $T 'sin-datos' @{ FASE = 'lanzadores'; ETIQUETA = (Format-Trozo $T 'et-sin') }) }
  if ($D.Lanzadores.Count -eq 0) { return (Format-Trozo $T 'lanz-ninguno') }
  $vs = @($D.Lanzadores | ForEach-Object { Get-VistaLanzador $D $_ })
  $filas = @($vs | ForEach-Object {
      $jobs = Format-Trozo $T 'lanz-marca-sin-enlazar'
      if ($_.Jobs.Count -gt 0) { $jobs = (@($_.Jobs | ForEach-Object { Format-Trozo $T 'lanz-job' @{ JOB = $_ } }) -join ', ') }
      Format-Trozo $T 'lanz-fila' @{ SCRIPT = $_.Rel; JOBS = $jobs; COMO = (Get-ComoLanzador $T $_) }
    })
  $sueltos = @($vs | Where-Object { $_.Jobs.Count -eq 0 })
  $suelto = ''
  if ($sueltos.Count -gt 0) {
    $marca = Format-Trozo $T 'lanz-marca-sin-enlazar'
    $suelto = Format-Trozo $T 'lanza-sueltos' @{ SCRIPTS = (@($sueltos | ForEach-Object { Get-ScriptLanzadorHtml $D $T $_ $marca }) -join "`n") }
  }
  return (Format-Trozo $T 'lanz-tabla' @{ ETIQUETA = (Format-Trozo $T 'et-medido'); FILAS = ($filas -join "`n"); SUELTOS = $suelto })
}

# Una fila por accion de la ficha de un script, con lo que dijo la comparacion de ella (o que no se ha comparado): con la forma de las filas de
# comparar una clase. Lo que no esta en el migrado lleva el aviso de la plataforma, y lo que el script midio sin llamar a la IA va marcado medido.
function Get-FilasLanzador($T, $V) {
  $filas = @()
  $i = 0
  foreach ($a in @($V.Acciones)) {
    $c = $V.PorAccion[$i]
    $estado = 'sin-comparar'; $migrado = ''; $citaM = ''; $notaIa = ''; $medido = $false; $probado = $false
    if ($c) {
      $estado = [string]$c.estado; $notaIa = [string]$c.nota; $citaM = [string]$c.cita; $probado = ($c.probado -eq $true)
      if ($c.fichero) { $migrado = "$($c.fichero):$($c.linea)" }
      $medido = ([string]$c.busqueda -ceq 'sin-candidatos')
    }
    $nota = $notaIa
    if ($estado -ceq 'falta') { $nota = (($notaIa + ' ' + (Format-Trozo $T 'lanz-falta-plataforma')).Trim()) }
    $filas += [pscustomobject]@{
      Job = ''; Clase = [string]$a.que; Estado = $estado; Texto = (([string]$a.condicion + ' ' + [string]$a.detalle).Trim()); Original = "$($V.Rel):$($a.linea)"
      CitaOriginal = [string]$a.cita; Migrado = $migrado; CitaMigrado = $citaM; Nota = $nota; NotaIa = $notaIa; Probado = $probado; Medido = $medido
    }
    $i++
  }
  return $filas
}

# Un script en la pagina 3: sus cuentas, primero lo distinto, lo que falta, lo que no se sabe y lo sin comparar, los iguales plegados y las lineas
# que la IA no supo explicar.
function Get-GrupoLanzador($D, $T, $V) {
  $filas = @(Get-FilasLanzador $T $V)
  $n = @{ 'igual' = 0; 'distinto' = 0; 'falta' = 0; 'no-lo-se' = 0; 'sin-comparar' = 0 }
  foreach ($f in $filas) { $n[$f.Estado]++ }
  $cuenta = ''
  $cuerpo = ''
  if (-not $V.Ficha) { $cuerpo = Get-CuerpoLanzador $D $T $V }
  else {
    $cuenta = Format-Trozo $T 'lanz-cuenta' @{ IGUAL = "$($n['igual'])"; DISTINTO = "$($n['distinto'])"; FALTA = "$($n['falta'])"; NOLOSE = "$($n['no-lo-se'])"; SINCOMPARAR = "$($n['sin-comparar'])" }
    $primeras = @(foreach ($e in @('distinto', 'falta', 'no-lo-se', 'sin-comparar')) { @($filas | Where-Object { $_.Estado -ceq $e }) })
    $iguales = @($filas | Where-Object { $_.Estado -ceq 'igual' })
    if ($primeras.Count -gt 0) { $cuerpo = Format-Trozo $T 'comp-filas' @{ FILAS = (@($primeras | ForEach-Object { Get-FilaComparar $T $_ }) -join "`n") } }
    if ($iguales.Count -gt 0) {
      $texto = Format-Trozo $T 'comp-iguales-otros' @{ N = "$($iguales.Count)" }
      if ($iguales.Count -eq 1) { $texto = Format-Trozo $T 'comp-iguales-uno' }
      $cuerpo += Format-Trozo $T 'comp-iguales' @{ TEXTO = $texto; FILAS = (@($iguales | ForEach-Object { Get-FilaComparar $T $_ }) -join "`n") }
    }
    if (-not $cuerpo) { $cuerpo = Format-Trozo $T 'lanz-grupo-vacio' }
    $se = @($V.Ficha.sinExplicar | Where-Object { $null -ne $_ })
    if ($se.Count -gt 0) { $cuerpo += Format-Trozo $T 'lanz-sin-explicar' @{ LINEAS = (@($se | ForEach-Object { "$($_.linea)" }) -join ', ') } }
  }
  return (Format-Trozo $T 'lanz-grupo' @{ ID = $V.Id; SCRIPT = $V.Rel; CUENTA = $cuenta; CUERPO = $cuerpo })
}

# La seccion Lanzadores de la pagina 3.
function Get-LanzadoresComparar($D, $T) {
  $cuerpo = Format-Trozo $T 'sin-datos' @{ FASE = 'lanzadores'; ETIQUETA = (Format-Trozo $T 'et-sin') }
  if ($D.LanzadoresLeidos) {
    if ($D.Lanzadores.Count -eq 0) { $cuerpo = Format-Trozo $T 'lanz-ninguno' }
    else { $cuerpo = (@($D.Lanzadores | ForEach-Object { Get-GrupoLanzador $D $T (Get-VistaLanzador $D $_) }) -join "`n") }
  }
  return (Format-Trozo $T 'lanz-seccion' @{ CUERPO = $cuerpo })
}

# Lo que va a la portada: cada accion que falta o esta distinta en el migrado y cada linea que la IA no supo explicar.
function Get-ItemsLanzadores($D, $T) {
  $items = @()
  foreach ($z in @($D.Lanzadores)) {
    $v = Get-VistaLanzador $D $z
    foreach ($f in @(Get-FilasLanzador $T $v | Where-Object { $_.Estado -ceq 'falta' -or $_.Estado -ceq 'distinto' })) {
      $cab = Format-Trozo $T 'cab-lanzador' @{ SCRIPT = $v.Rel; ESTADO = (Format-Trozo $T "comp-est-$($f.Estado)") }
      $items += (Format-Trozo $T 'toca-item' @{ CABECERA = $cab; TEXTO = (($f.Texto + ' ' + $f.NotaIa).Trim()) })
    }
    foreach ($x in @($v.Ficha.sinExplicar | Where-Object { $null -ne $_ })) {
      $items += (Format-Trozo $T 'toca-item' @{ CABECERA = (Format-Trozo $T 'cab-lanzador-sin' @{ SCRIPT = $v.Rel; LINEA = "$($x.linea)" }); TEXTO = (Get-PrimeraLinea ([string]$x.texto)) })
    }
  }
  return $items
}

# ============================== LA PRUEBA EN LOCAL ==============================
# Lo que dice la pasada de su ultima fase (estado.json, pruebaLocal.resultado): hecha, fallo, saltada o '' si aun no hay nada.
function Get-ResultadoLocal($D) {
  if ($D.Estado -and $D.Estado.pruebaLocal) { return [string]$D.Estado.pruebaLocal.resultado }
  return ''
}

# Los casos que dio por distintos el original ejecutado frente al migrado ejecutado (datos\prueba-local.json).
function Get-CasosDistintos($PL) {
  return @($PL.casos | Where-Object { $null -ne $_ -and $_.resultado -ceq 'distinto' })
}

# Los casos que no se pudieron preparar ni ejecutar: de esos no se sabe si dan lo mismo.
function Get-CasosSinPreparar($PL) {
  return @($PL.casos | Where-Object { $null -ne $_ -and $_.resultado -ceq 'no se pudo preparar' })
}

# Las cuentas de todos los jobs de prueba-local.json.
function Get-CuentasLocal($PL) {
  $c = @{ Jobs = 0; Casos = 0; Iguales = 0; Distintos = 0; Sin = 0 }
  foreach ($j in @($PL.jobs | Where-Object { $null -ne $_ })) {
    $c.Jobs++; $c.Casos += [int]$j.casos; $c.Iguales += [int]$j.iguales; $c.Distintos += [int]$j.distintos; $c.Sin += [int]$j.sinProbar
  }
  return $c
}

function Get-DifLocalHtml($T, $Dif) {
  $nota = ''
  if ($Dif.nota) { $nota = Format-Trozo $T 'pl-nota' @{ NOTA = $Dif.nota } }
  $lineas = Format-Trozo $T 'pl-lineas-otras'
  if ([int]$Dif.lineas -eq 1) { $lineas = Format-Trozo $T 'pl-lineas-una' }
  return (Format-Trozo $T 'pl-dif' @{
      ESTADO = (Format-Trozo $T 'comp-est-distinto'); FICHERO = $Dif.fichero; LINEAS = "$($Dif.lineas)"; LINEAS_TEXTO = $lineas; LINEA = "$($Dif.linea)"
      ORIGINAL = $Dif.original; MIGRADO = $Dif.migrado; NOTA = $nota
    })
}

function Get-CasoLocalHtml($T, $C) {
  $difs = @($C.diferencias | Where-Object { $null -ne $_ } | ForEach-Object { Get-DifLocalHtml $T $_ })
  return (Format-Trozo $T 'pl-caso' @{ JOB = $C.job; CASO = $C.caso; TITULO = $C.titulo; DIFERENCIAS = ($difs -join "`n") })
}

# Los casos que no son iguales (sin probar, no deterministas...) y los iguales que traen un motivo, plegados.
function Get-RestoLocalHtml($T, $PL) {
  $resto = @($PL.casos | Where-Object { $null -ne $_ -and $_.resultado -cne 'distinto' -and ($_.resultado -cne 'igual' -or $_.motivo) })
  if ($resto.Count -eq 0) { return '' }
  $filas = @()
  foreach ($c in $resto) {
    $v = @{ CLASE = 's-aviso'; SEV = 'sev-aviso'; ICONO = 'e-aviso' }
    if ($c.resultado -ceq 'igual') { $v = @{ CLASE = ''; SEV = ''; ICONO = 'e-ia' } }
    $motivo = ''
    if ($c.motivo) { $motivo = Format-Trozo $T 'pl-motivo' @{ MOTIVO = $c.motivo } }
    $filas += (Format-Trozo $T 'pl-resto-fila' @{
        CLASE = $v.CLASE; SEV = $v.SEV; ICONO = $v.ICONO; RESULTADO = $c.resultado; JOB = $c.job; CASO = $c.caso; TITULO = $c.titulo; MOTIVO = $motivo
      })
  }
  $texto = Format-Trozo $T 'pl-resto-otros' @{ N = "$($resto.Count)" }
  if ($resto.Count -eq 1) { $texto = Format-Trozo $T 'pl-resto-uno' }
  return (Format-Trozo $T 'pl-resto' @{ TEXTO = $texto; FILAS = ($filas -join "`n") })
}

# Lo que lleva la seccion cuando hay datos\prueba-local.json.
function Get-DatosLocalHtml($D, $T) {
  $pl = $D.PruebaLocal
  $c = Get-CuentasLocal $pl
  $minutos = ([math]::Round([double]$pl.minutos, 1)).ToString([System.Globalization.CultureInfo]::InvariantCulture).Replace('.', ',')
  $aviso = ''
  if ($pl.arneses.migrado -cne 'hecha') { $aviso = Format-Trozo $T 'pl-aviso-arnes' }
  $filas = Format-Lista $T 'pl-fila' @($pl.jobs | Where-Object { $null -ne $_ }) {
    param($j)
    $mal = ''
    if ([int]$j.distintos -gt 0) { $mal = Format-Trozo $T 'pl-mal' }
    @{ JOB = $j.job; CASOS = "$($j.casos)"; IGUALES = "$($j.iguales)"; DISTINTOS = "$($j.distintos)"; SIN = "$($j.sinProbar)"; MAL = $mal }
  }
  $noPromete = ''
  if ($pl.noPromete) { $noPromete = Format-Trozo $T 'pl-no-promete' @{ TEXTO = $pl.noPromete } }
  $fallo = ''
  if ((Get-ResultadoLocal $D) -ceq 'fallo') {
    $e = $D.Estado.pruebaLocal
    $fallo = Format-Trozo $T 'pl-fallo-linea' @{ CODIGO = "$($e.codigo)"; DETALLE = $e.detalle; REGISTRO = $e.registro }
  }
  return (Format-Trozo $T 'pl-datos' @{
      ETIQUETA = (Format-Trozo $T 'et-medido-ia'); CASOS = "$($c.Casos)"; JOBS = "$($c.Jobs)"; IGUALES = "$($c.Iguales)"; DISTINTOS = "$($c.Distintos)"; SIN = "$($c.Sin)"
      LLAMADAS = "$($pl.llamadas)"; MINUTOS = $minutos; FECHA = (Get-TextoFecha $T $pl.fin); AVISO = $aviso
      TABLA = (Format-Trozo $T 'pl-tabla' @{ FILAS = $filas })
      CASOSDISTINTOS = (@(Get-CasosDistintos $pl | ForEach-Object { Get-CasoLocalHtml $T $_ }) -join "`n")
      RESTO = (Get-RestoLocalHtml $T $pl); NOPROMETE = $noPromete; FALLO = $fallo
    })
}

# La seccion "Probado ejecutando los dos": con datos, el fallo de la fase sin datos, saltada, o el sin-datos de siempre.
function Get-PruebaLocalHtml($D, $T) {
  $r = Get-ResultadoLocal $D
  $cuerpo = Format-Trozo $T 'sin-datos' @{ FASE = 'prueba-local'; ETIQUETA = (Format-Trozo $T 'et-sin') }
  if ($D.PruebaLocal) { $cuerpo = Get-DatosLocalHtml $D $T }
  elseif ($r -ceq 'fallo') {
    $e = $D.Estado.pruebaLocal
    $cuerpo = Format-Trozo $T 'pl-sin-fallo' @{ CODIGO = "$($e.codigo)"; DETALLE = $e.detalle; REGISTRO = $e.registro }
  }
  elseif ($r -ceq 'saltada') { $cuerpo = Format-Trozo $T 'pl-saltada' @{ ETIQUETA = (Format-Trozo $T 'et-sin') } }
  return (Format-Trozo $T 'pl-seccion' @{ CASOS = (Get-CajaRecorren $D $T); CUERPO = $cuerpo })
}

# El trozo en singular ($Base-uno) si la cuenta es 1 y el plural ($Base-varios) si no.
function Get-TrozoPorCuenta($T, [string]$Base, [int]$N, $Valores) {
  $sufijo = 'varios'
  if ($N -eq 1) { $sufijo = 'uno' }
  return (Format-Trozo $T "$Base-$sufijo" $Valores)
}

# La caja de la pagina 3 con lo que dicen los casos: una o mas frases; sin frases, nada.
function Get-CajaCasos($T, [string]$Id, $Frases) {
  if (@($Frases).Count -eq 0) { return '' }
  return (Format-Trozo $T 'm34-resumen' @{ ID = $Id; FRASES = (@($Frases) -join "`n") })
}

# La caja de Probado ejecutando los dos: cuanto del original recorren los casos (las lineas de la union de igual y distinto entre lineasTotal) o, con los casos
# sin medir, el motivo. Sin JSON, nada.
function Get-CajaRecorren($D, $T) {
  $frases = @()
  if ($D.CoberturaCasos -and [string]$D.CoberturaCasos.estado -ceq 'no medido') {
    $motivo = ([string]$D.CoberturaCasos.motivo).Trim().TrimEnd('.')
    if (-not $motivo) { $motivo = Format-Trozo $T 'm34-sin-motivo' }
    $frases += Format-Trozo $T 'm34-no-medido' @{ MOTIVO = $motivo }
  }
  elseif ($null -ne $D.LineasCasos) {
    $recorridas = 0
    foreach ($f in $D.LineasCasos.Values) {
      $u = New-Object 'System.Collections.Generic.HashSet[int]'
      $u.UnionWith($f.Igual); $u.UnionWith($f.Distinto)
      $recorridas += $u.Count
    }
    $pct = "$(Get-PorcentajePractica $recorridas $D.CoberturaCasos.lineasTotal)".Replace('.', ',')
    $frases += Format-Trozo $T 'm34-recorren' @{ PCT = $pct }
  }
  return (Get-CajaCasos $T 'm34-recorren' $frases)
}

# La caja de Leido por la IA: de los datos que la IA no pudo dar por iguales, cuantos ejecuto un caso que salio igual y cuantos no recorre ninguno. Solo con los casos
# medidos y la comparacion hecha.
function Get-CajaDudosos($D, $T) {
  $frases = @()
  if ($null -ne $D.LineasCasos -and $D.Mapa -and $D.Comparacion.Count -gt 0) {
    $dudosos = @(foreach ($j in @($D.Mapa.jobs)) { @(Get-DatosComparar $D $j | Where-Object { @('distinto', 'falta', 'no-lo-se') -ccontains $_.Estado }) })
    if ($dudosos.Count -eq 0) { $frases += Format-Trozo $T 'm34-sin-dudosos' }
    else {
      $igual = @($dudosos | Where-Object { $_.Ejecucion -ceq 'ejecutado-igual' }).Count
      $ninguno = @($dudosos | Where-Object { $_.Ejecucion -ceq 'sin-ejecutar' }).Count
      $frases += Format-Trozo $T 'm34-dudosos' @{
        DATOS = (Get-TrozoPorCuenta $T 'm34-datos' $dudosos.Count @{ N = "$($dudosos.Count)" }); IGUAL = (Get-TrozoPorCuenta $T 'm34-igual' $igual @{ N = "$igual" })
        NINGUNO = (Get-TrozoPorCuenta $T 'm34-ninguno' $ninguno @{ N = "$ninguno" })
      }
    }
  }
  return (Get-CajaCasos $T 'm34-dudosos' $frases)
}

function Get-CuerpoComparar($D, $T, [string]$Cuerpo) {
  $jobs = Format-Trozo $T 'sin-datos' @{ FASE = 'comparar'; ETIQUETA = (Format-Trozo $T 'et-sin') }
  if (-not $D.Mapa) { $jobs = Format-Trozo $T 'sin-datos' @{ FASE = 'mapa'; ETIQUETA = (Format-Trozo $T 'et-sin') } }
  elseif ($D.Comparacion.Count -gt 0) { $jobs = (@($D.Mapa.jobs | ForEach-Object { Get-GrupoComparar $D $T $_ }) -join "`n") }
  return (Expand-Plantilla $Cuerpo @{
      DUDOSOS = (Get-CajaDudosos $D $T); PRUEBALOCAL = (Get-PruebaLocalHtml $D $T); ETIQUETA = (Format-Trozo $T 'et-ia'); MOMENTO = (Get-MomentoComparar $D $T); JOBS = $jobs; LANZADORES = (Get-LanzadoresComparar $D $T)
    })
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

# Las fases de la pasada en el orden en que se hacen, que depende de la respuesta: con corregir, la comparacion y la prueba en local van
# despues de la correccion; si no, la comparacion va antes. lectura-hecha y hecha no se pintan: marcan el sitio de esos dos estados.
# practicas (-Practicas) va despues de la correccion y de comparar y antes de prueba-local, y solo si la pasada la tiene: el estado esta en ella
# o hay datos\practicas-arreglos.json. reglas (-Reglas) va despues de practicas y antes de prueba-local, con la misma regla: el estado esta en ella o hay
# datos\tests-reglas.json.
function Get-OrdenFases($D) {
  $lectura = @('diagnostico', 'fichas-clase', 'mapa', 'lanzadores', 'fichas-job', 'resumen', 'pruebas-pre', 'casos-pre')
  $practicas = @()
  if (($D.Estado -and [string]$D.Estado.fase -ceq 'practicas') -or $D.Arreglos) { $practicas = @('practicas') }
  $reglas = @()
  if (($D.Estado -and [string]$D.Estado.fase -ceq 'reglas') -or $D.Reglas) { $reglas = @('reglas') }
  if ($D.Estado -and [string]$D.Estado.respuesta -ceq 'corregir') { return @($lectura + @('lectura-hecha', 'correccion', 'comparar') + $practicas + $reglas + @('prueba-local', 'hecha')) }
  return @($lectura + @('comparar', 'lectura-hecha', 'correccion') + $practicas + $reglas + @('prueba-local', 'hecha'))
}

# Una linea de una fase: su estado (segun la fase en que va la pasada) y lo que cuentan sus tareas.
function Get-FaseHtml($D, $T, [string]$Fase) {
  $est = if ($D.Estado) { [string]$D.Estado.fase } else { '' }
  $orden = @(Get-OrdenFases $D)
  $Tipo = [string]$TipoFase[$Fase]
  $e = 'espera'
  if ($Fase -eq 'correccion') {
    if ($D.Correccion -and $D.Correccion.completa -eq $true) { $e = 'hecha' }
    elseif ($est -eq 'correccion') { $e = 'curso' }
  }
  elseif ($Fase -eq 'prueba-local') {
    $r = Get-ResultadoLocal $D
    if ($est -eq 'prueba-local') { $e = 'curso' }
    elseif ($r -ceq 'hecha' -or $r -ceq 'fallo') { $e = 'hecha' }
    elseif ($r -ceq 'saltada') { $e = 'saltada' }
  }
  elseif ([array]::IndexOf($orden, $Fase) -lt [array]::IndexOf($orden, $est)) { $e = 'hecha' }
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
  elseif ($Fase -eq 'prueba-local') {
    $r = Get-ResultadoLocal $D
    $cuenta = Format-Trozo $T 'sin-valor'
    if ($r -ceq 'fallo') { $cuenta = Format-Trozo $T 'cuenta-local-fallo' }
    elseif ($r -ceq 'saltada') { $cuenta = Format-Trozo $T 'cuenta-local-saltada' }
    elseif ($D.PruebaLocal) {
      $c = Get-CuentasLocal $D.PruebaLocal
      $cuenta = Format-Trozo $T 'cuenta-local' @{ CASOS = "$($c.Casos)"; IGUALES = "$($c.Iguales)"; DISTINTOS = "$($c.Distintos)"; SIN = "$($c.Sin)" }
    }
  }
  elseif ($Fase -eq 'correccion') {
    $cuenta = Format-Trozo $T 'sin-valor'
    if ($D.Correccion) { $cuenta = Format-Trozo $T 'cuenta-correccion' @{ COMMITS = "$(@($D.Correccion.commits).Count)"; ATASCADOS = "$(@($D.Correccion.atascados).Count)" } }
  }
  elseif ($Fase -eq 'practicas') {
    $cuenta = Format-Trozo $T 'sin-valor'
    if ($D.Arreglos) { $cuenta = Format-Trozo $T 'cuenta-practicas' @{ PASADOS = "$([int]$D.Arreglos.pasados)"; ATASCADOS = "$([int]$D.Arreglos.atascados)"; SIN = "$([int]$D.Arreglos.sinCambios)" } }
  }
  elseif ($Fase -eq 'reglas') {
    $cuenta = Format-Trozo $T 'sin-valor'
    if ($D.Reglas) { $cuenta = Format-Trozo $T 'cuenta-reglas' @{ CLASES = "$([int]$D.Reglas.conTest)"; VIGILADAS = "$([int]$D.Reglas.reglasVigiladas)"; ATASCADAS = "$([int]$D.Reglas.atascadas)"; SALTADAS = "$([int]$D.Reglas.saltadas)" } }
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

function Get-GrupoToca($T, [string]$Nombre, $Items, [string]$N, [string]$Etiqueta = 'et-sin') {
  return (Format-Trozo $T 'toca-grupo' @{
      TITULO = (Format-Trozo $T "toca-$Nombre-titulo" @{ N = $N }); TEXTO = (Format-Trozo $T "toca-$Nombre-texto"); ETIQUETA = (Format-Trozo $T $Etiqueta)
      ITEMS = (@($Items) -join "`n")
    })
}

# "Lo que te toca": primero lo mas fiable (los casos distintos al ejecutar los dos, o la prueba en local que no se hizo), luego las tareas atascadas, clases sin ficha, dudas de las fichas de job, reglas sin caso de prueba, datos
# que nombran clases (los que la pagina de negocio no pinta, y las clases que no cupieron en la redaccion de un job) y
# los datos que el migrado hace distinto o no hace (uno por job y dato) y lo que hacian los .sh y el migrado no hace igual o la IA no supo explicar.
function Get-TocaHtml($D, $T) {
  $grupos = @()
  $distintos = @()
  if ($D.PruebaLocal) { $distintos = @(Get-CasosDistintos $D.PruebaLocal) }
  if ($distintos.Count -gt 0) {
    $items = @($distintos | ForEach-Object {
        $dif = @($_.diferencias | Where-Object { $null -ne $_ } | Select-Object -First 1)
        $valores = @{ CABECERA = (Format-Trozo $T 'cab-caso' @{ JOB = $_.job; CASO = $_.caso }); TITULO = $_.titulo; FICHERO = ''; ORIGINAL = ''; MIGRADO = '' }
        if ($dif.Count -gt 0) { $valores.FICHERO = $dif[0].fichero; $valores.ORIGINAL = (Get-PrimeraLinea ([string]$dif[0].original)); $valores.MIGRADO = (Get-PrimeraLinea ([string]$dif[0].migrado)) }
        Format-Trozo $T 'toca-distinto' $valores
      })
    $grupos += (Get-GrupoToca $T 'distintos' $items "$($distintos.Count)" 'et-medido-ia')
  }
  elseif (-not $D.PruebaLocal -and (Get-ResultadoLocal $D) -ceq 'fallo') {
    $e = $D.Estado.pruebaLocal
    $grupos += (Get-GrupoToca $T 'localfallo' @(Format-Trozo $T 'toca-localfallo' @{ CODIGO = "$($e.codigo)"; DETALLE = $e.detalle }) '1')
  }
  $sinPreparar = @()
  if ($D.PruebaLocal) { $sinPreparar = @(Get-CasosSinPreparar $D.PruebaLocal) }
  if ($sinPreparar.Count -gt 0) {
    $items = @($sinPreparar | ForEach-Object { Format-Trozo $T 'toca-item' @{ CABECERA = (Format-Trozo $T 'cab-caso' @{ JOB = $_.job; CASO = $_.caso }); TEXTO = ($_.titulo + '. ' + (Get-PrimeraLinea ([string]$_.motivo))) } })
    $grupos += (Get-GrupoToca $T 'sinprobar' $items "$($sinPreparar.Count)")
  }
  $atascadas = @($D.Tareas | Where-Object { $_.estado -eq 'atascada' })
  if ($atascadas.Count -gt 0) {
    $items = @($atascadas | ForEach-Object { Format-Trozo $T 'toca-item' @{ CABECERA = (Format-Trozo $T 'cab-tarea' @{ ID = $_.id; DONDE = @($_.entradas.fichero, $_.entradas.script, '' | Where-Object { $_ })[0] }); TEXTO = (Get-PrimeraLinea $_.motivo) } })
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
  $lanzadores = @(Get-ItemsLanzadores $D $T)
  if ($lanzadores.Count -gt 0) { $grupos += (Get-GrupoToca $T 'lanzadores' $lanzadores "$($lanzadores.Count)") }
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
# Lo que paso en un area durante la correccion, segun los asuntos de sus commits ("rescate(<paso>): lote N, hallazgos X a Y"): con cuantos
# hallazgos empezo y con cuantos acabo, y lo que aparecio o se fue con los arreglos de otros pasos (la diferencia con los del diagnostico).
function Get-DuranteHtml($T, $A) {
  $x = @(); $y = @()
  foreach ($c in $A.Commits) {
    $m = [regex]::Match([string]$c.asunto, '^rescate\([^)]*\): lote [0-9]+, hallazgos ([0-9]+) a ([0-9]+)')
    if ($m.Success) { $x += [int]$m.Groups[1].Value; $y += [int]$m.Groups[2].Value }
  }
  if ($x.Count -eq 0) { return '' }
  $antes = @($A.Antes.Errores).Count
  $dif = ''
  if ($x[0] - $antes -eq 1) { $dif = Format-Trozo $T 'durante-aparecio' }
  elseif ($x[0] -gt $antes) { $dif = Format-Trozo $T 'durante-aparecieron' @{ N = "$($x[0] - $antes)" } }
  elseif ($antes - $x[0] -eq 1) { $dif = Format-Trozo $T 'durante-se-fue' }
  elseif ($x[0] -lt $antes) { $dif = Format-Trozo $T 'durante-se-fueron' @{ N = "$($antes - $x[0])" } }
  $commits = Format-Trozo $T 'durante-commit-otros' @{ N = "$($A.Commits.Count)" }
  if ($A.Commits.Count -eq 1) { $commits = Format-Trozo $T 'durante-commit-uno' }
  return (Format-Trozo $T 'area-durante' @{ X = "$($x[0])"; Y = "$($y[$y.Count - 1])"; COMMITS = $commits; DIF = $dif })
}

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
      BARRAS = $barras; COMMITS = $commits; ATASCADOS = $atascados; QUEDA = $queda; DURANTE = (Get-DuranteHtml $T $A)
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

# ============================== LAS BUENAS PRACTICAS (PAGINA 5) ==============================
# El orden de las areas y de los "que hago" es el de la maqueta: primero lo que tiene que hacer la persona.
$AreasPractica = @('java21', 'boot3-batch5', 'lombok', 'arquitectura')
$QueHagoPractica = @('mano', 'paso2', 'sonar', 'notoca')

# datos\practicas-despues.json si existe y se lee y, si no, datos\practicas-antes.json (otro que falte o este roto equivale a no tenerlo). $null si no hay ninguno.
function Read-Practicas([string]$Datos) {
  foreach ($cuando in @('despues', 'antes')) {
    $p = Read-JsonSuave (Join-Path $Datos "practicas-$cuando.json")
    if ($p) { return $p }
  }
  return $null
}

# Las incidencias del JSON con lo que las vistas necesitan: Area, Que (un queHago que no se conoce es "mano": todo lo demas), ConSonar
# (origen sonar o spotbugs: el Sonar del equipo tambien lanza SpotBugs), Commit (los 7 primeros caracteres del commit con que arreglo-practicas.ps1
# paso a Lombok el fichero de una incidencia getter-setter-a-mano; '' si no, o si no hay datos\practicas-arreglos.json) e I, la incidencia tal cual.
function Get-IncidenciasPractica($P, $Arreglos) {
  $commits = @{}
  foreach ($t in @($Arreglos.tareas)) {
    if ($t -and [string]$t.estado -ceq 'hecha' -and [string]$t.commit) { $commits[[string]$t.fichero] = ([string]$t.commit).Substring(0, [math]::Min(7, ([string]$t.commit).Length)) }
  }
  $r = @()
  foreach ($i in @($P.incidencias)) {
    if ($null -eq $i) { continue }
    $que = [string]$i.queHago
    if ($QueHagoPractica -cnotcontains $que) { $que = 'mano' }
    $commit = ''
    if ([string]$i.regla -ceq 'getter-setter-a-mano' -and $commits.ContainsKey([string]$i.fichero)) { $commit = $commits[[string]$i.fichero] }
    $r += [pscustomobject]@{ Area = [string]$i.area; Que = $que; ConSonar = (@('sonar', 'spotbugs') -ccontains [string]$i.origen); Commit = $commit; I = $i }
  }
  return $r
}

# Las areas conocidas y, al final, las que traiga el JSON y la pagina no conozca.
function Get-AreasPractica($Incs) {
  $r = @($AreasPractica)
  foreach ($x in @($Incs)) { if ($r -cnotcontains $x.Area) { $r += $x.Area } }
  return $r
}

# El nombre o la explicacion de un area ($Trozo = 'bp-area' o 'bp-area-expl'): el de la plantilla o, si no lo tiene, el identificador (o nada).
function Get-TextoAreaPractica($T, [string]$Id, [bool]$Explicacion) {
  if ($Explicacion) {
    if ($T.ContainsKey("bp-area-$Id-expl")) { return (Format-Trozo $T "bp-area-$Id-expl") }
    return ''
  }
  if ($T.ContainsKey("bp-area-$Id")) { return (Format-Trozo $T "bp-area-$Id") }
  return (ConvertTo-TextoHtml $Id)
}

# fichero:linea con un <wbr> detras de cada / (la ruta no se parte a mitad de palabra); sin linea, solo el fichero.
function Get-DondePractica($T, $I) {
  $d = ((([string]$I.fichero).Split('/') | ForEach-Object { ConvertTo-TextoHtml $_ }) -join (Format-Trozo $T 'bp-barra'))
  if ([int]$I.linea -gt 0) { $d += ':' + [int]$I.linea }
  return $d
}

function Get-OrigenPractica($T, $I) {
  if ($I.origen -ceq 'sonar') { return (Format-Trozo $T 'bp-origen-sonar' @{ CLAVE = [string]$I.sonar }) }
  if ($I.origen -ceq 'spotbugs') { return (Format-Trozo $T 'bp-origen-spotbugs') }
  return (Format-Trozo $T 'bp-origen-referencia')
}

# Una incidencia: donde esta, de donde sale, si ya esta arreglada, la regla, lo que dice y, aparte, $Extra (en la vista por "que hago", el area; en la otra, el "que hago").
function Get-FilaPractica($T, $X, [string]$Extra) {
  $arreglado = ''
  if ($X.Commit) { $arreglado = Format-Trozo $T 'bp-arreglado' @{ COMMIT = $X.Commit } }
  return (Format-Trozo $T 'bp-fila' @{
      QUE = $X.Que; DONDE = (Get-DondePractica $T $X.I); ORIGEN = (Get-OrigenPractica $T $X.I); ARREGLADO = $arreglado
      REGLA = ([string]$X.I.herramienta + ' ' + [string]$X.I.regla); TEXTO = [string]$X.I.texto; EXTRA = $Extra
    })
}

function Get-GrupoPractica($T, [string]$Id, [string]$Titulo, [string]$Explicacion, $Filas) {
  return (Format-Trozo $T 'bp-grupo' @{ ID = $Id; TITULO = $Titulo; N = "$(@($Filas).Count)"; EXPLICACION = $Explicacion; FILAS = (@($Filas) -join "`n") })
}

# Las dos vistas de la misma lista: por "que hago" (el area va aparte en cada fila) y por area (el "que hago" va aparte). Un grupo sin incidencias no sale.
function Get-VistaQuePractica($T, $Incs) {
  $grupos = @()
  foreach ($q in $QueHagoPractica) {
    $filas = @()
    foreach ($a in (Get-AreasPractica $Incs)) {
      foreach ($x in @($Incs | Where-Object { $_.Que -ceq $q -and $_.Area -ceq $a })) { $filas += (Get-FilaPractica $T $x (Get-TextoAreaPractica $T $a $false)) }
    }
    if ($filas.Count -gt 0) { $grupos += (Get-GrupoPractica $T "gq-$q" (Format-Trozo $T "bp-queHago-$q") (Format-Trozo $T "bp-queHago-$q-expl") $filas) }
  }
  return ($grupos -join "`n")
}

function Get-VistaAreaPractica($T, $Incs) {
  $grupos = @()
  foreach ($a in (Get-AreasPractica $Incs)) {
    $filas = @()
    foreach ($q in $QueHagoPractica) {
      foreach ($x in @($Incs | Where-Object { $_.Que -ceq $q -and $_.Area -ceq $a })) { $filas += (Get-FilaPractica $T $x (Format-Trozo $T "bp-queHago-$q")) }
    }
    if ($filas.Count -gt 0) { $grupos += (Get-GrupoPractica $T "ga-$a" (Get-TextoAreaPractica $T $a $false) (Get-TextoAreaPractica $T $a $true) $filas) }
  }
  return ($grupos -join "`n")
}

function Get-ListaPractica($T, $Incs) {
  $et = Format-Trozo $T 'et-medido'
  if (@($Incs).Count -eq 0) { return (Format-Trozo $T 'bp-lista-vacia' @{ ETIQUETA = $et }) }
  $titulo = 'bp-lista-titulo-otros'
  if (@($Incs).Count -eq 1) { $titulo = 'bp-lista-titulo-uno' }
  return (Format-Trozo $T 'bp-lista' @{
      TITULO = (Format-Trozo $T $titulo @{ N = "$(@($Incs).Count)" }); ETIQUETA = $et; QUE = (Get-VistaQuePractica $T $Incs); AREA = (Get-VistaAreaPractica $T $Incs)
    })
}

# Un porcentaje de $Parte sobre $Todo con una cifra decimal (0 si no hay todo), con punto: va dentro de un estilo.
function Get-PorcentajePractica($Parte, $Todo) {
  if ([double]$Todo -le 0) { return 0 }
  return [math]::Round([double]$Parte / [double]$Todo * 100, 1)
}

# Los cuatro indicadores de la maqueta; cada uno se dibuja distinto. El del .xlsx solo sale si el JSON trae sonar.xlsx.
function Get-IndAreasPractica($T, $Incs) {
  $areas = @(Get-AreasPractica $Incs)
  $segmentos = @()
  $ley = @()
  $resumen = @()
  foreach ($a in $areas) {
    $n = @($Incs | Where-Object { $_.Area -ceq $a }).Count
    $nombre = Get-TextoAreaPractica $T $a $false
    if ($n -gt 0) { $segmentos += (Format-Trozo $T 'bp-ind-seg' @{ ID = $a; N = "$n" }) }
    $ley += (Format-Trozo $T 'bp-ind-ley' @{ ID = $a; NOMBRE = $nombre; N = "$n" })
    $resumen += (Format-Trozo $T 'bp-ind-resumen' @{ NOMBRE = $nombre; N = "$n" })
  }
  return (Format-Trozo $T 'bp-ind-areas' @{ TOTAL = "$(@($Incs).Count)"; RESUMEN = ($resumen -join ', '); SEGMENTOS = ($segmentos -join ''); LEYENDA = ($ley -join "`n") })
}

function Get-IndSonarPractica($T, $Incs) {
  $total = @($Incs).Count
  $s = @($Incs | Where-Object { $_.ConSonar }).Count
  $c = 2 * [math]::PI * 42
  $arco = 0
  if ($total -gt 0) { $arco = [math]::Round($s / $total * $c, 1) }
  return (Format-Trozo $T 'bp-ind-sonar' @{ TOTAL = "$total"; S = "$s"; R = "$($total - $s)"; C = "$([math]::Round($c, 1))"; ARCO = "$arco"; RESTO = "$([math]::Round($c - $arco, 1))" })
}

function Get-IndReglasPractica($T, $S) {
  $pct = Get-PorcentajePractica $S.reglasAqui $S.reglasWay
  return (Format-Trozo $T 'bp-ind-reglas' @{ AQUI = "$([int]$S.reglasAqui)"; WAY = "$([int]$S.reglasWay)"; PCT = "$pct"; PCT_TXT = "$pct".Replace('.', ',') })
}

function Get-IndXlsxPractica($T, $S) {
  if (-not $S.xlsx) { return '' }
  $x = $S.xlsx
  return (Format-Trozo $T 'bp-ind-xlsx' @{ TOTAL = "$([int]$x.total)"; RESUELTAS = "$([int]$x.resueltas)"; SIGUEN = "$([int]$x.siguen)"; PCT = "$(Get-PorcentajePractica $x.resueltas $x.total)" })
}

function Get-IndicadoresPractica($T, $P, $Incs) {
  $inds = @((Get-IndAreasPractica $T $Incs), (Get-IndSonarPractica $T $Incs), (Get-IndReglasPractica $T $P.sonar), (Get-IndXlsxPractica $T $P.sonar)) | Where-Object { $_ }
  return @{ Html = (@($inds) -join "`n"); N = @($inds).Count }
}

# Una linea por cada detector que no midio (su estado y su motivo) y, si javac paro en 100 avisos, otra que dice "100 o mas". Sin ninguna, no hay seccion.
function Get-DetectoresPractica($T, $P) {
  $notas = @()
  foreach ($d in @($P.detectores)) {
    if ($null -eq $d) { continue }
    $sin = Format-Trozo $T 'et-sin'
    if ($d.corte -eq $true) { $notas += (Format-Trozo $T 'bp-det-corte' @{ ETIQUETA = $sin; ID = [string]$d.id }) }
    if ([string]$d.estado -cne 'ok') {
      $motivo = ''
      if ($d.motivo) { $motivo = Format-Trozo $T 'bp-det-motivo' @{ MOTIVO = [string]$d.motivo } }
      $notas += (Format-Trozo $T 'bp-det-estado' @{ ETIQUETA = $sin; ID = [string]$d.id; ESTADO = [string]$d.estado; MOTIVO = $motivo })
    }
  }
  if ($notas.Count -eq 0) { return '' }
  return (Format-Trozo $T 'bp-detectores' @{ NOTAS = ($notas -join "`n") })
}

# "Como leer lo de Sonar": las frases de la maqueta con las cifras del JSON.
function Get-PanelSonarPractica($T, $P, $Incs) {
  $total = @($Incs).Count
  $con = @($Incs | Where-Object { $_.ConSonar }).Count
  $ref = $total - $con
  $frase = ''
  foreach ($par in @(@('total', $total), @('con', $con), @('ref', $ref))) {
    $forma = 'otros'
    if ($par[1] -eq 1) { $forma = 'uno' }
    $frase += Format-Trozo $T ('bp-sonar-' + $par[0] + '-' + $forma) @{ N = "$($par[1])" }
  }
  $xlsx = ''
  if ($P.sonar.xlsx) { $xlsx = Format-Trozo $T 'bp-sonar-xlsx' @{ TOTAL = "$([int]$P.sonar.xlsx.total)"; RESUELTAS = "$([int]$P.sonar.xlsx.resueltas)"; SIGUEN = "$([int]$P.sonar.xlsx.siguen)" } }
  return (Format-Trozo $T 'bp-sonar' @{ FRASE = $frase; ETIQUETA = (Format-Trozo $T 'et-sin'); AQUI = "$([int]$P.sonar.reglasAqui)"; WAY = "$([int]$P.sonar.reglasWay)"; XLSX = $xlsx })
}

# La cabecera de la pagina: que se midio, con que y cuando. Los detectores que midieron (ok) son "las herramientas".
function Get-CabeceraPractica($D, $T, $P) {
  $midieron = @(@($P.detectores) | Where-Object { $_ -and [string]$_.estado -ceq 'ok' } | ForEach-Object { Format-Trozo $T 'bp-herramienta' @{ ID = [string]$_.id } })
  $herramientas = Format-Trozo $T 'bp-ninguno'
  if ($midieron.Count -gt 0) { $herramientas = Format-Trozo $T 'bp-herramientas' @{ ITEMS = ($midieron -join "`n") } }
  $cuando = 'bp-cuando-antes'
  if ($P.cuando -ceq 'despues') { $cuando = 'bp-cuando-despues' }
  return (Format-Trozo $T 'bp-cabecera' @{
      SEGUNDOS = "$([math]::Round([double]$P.segundos, 1))".Replace('.', ','); CUANDO = (Format-Trozo $T $cuando); ETIQUETA = (Format-Trozo $T 'et-medido')
      BATCH = (Get-BatchInforme $D); REFERENCIA = [string]$P.referencia; MEDIDO = (Get-TextoFecha $T $P.medido); PAQUETE = [string]$P.paquete; MIDIERON = $herramientas
    })
}

function Get-CuerpoPracticas($D, $T, [string]$Cuerpo) {
  $P = $D.Practicas
  $cabecera = ''
  $practicas = Format-Trozo $T 'bp-sin-datos' @{ ETIQUETA = (Format-Trozo $T 'et-sin') }
  if ($P) {
    $incs = @(Get-IncidenciasPractica $P $D.Arreglos)
    $ind = Get-IndicadoresPractica $T $P $incs
    $arq = ''
    if ($null -eq $P.arquitectura) { $arq = Format-Trozo $T 'bp-arquitectura-sin' @{ ETIQUETA = (Format-Trozo $T 'et-sin') } }
    $cabecera = Get-CabeceraPractica $D $T $P
    $practicas = Format-Trozo $T 'bp-datos' @{
      N_IND = "$($ind.N)"; INDICADORES = $ind.Html; DETECTORES = (Get-DetectoresPractica $T $P); SONAR = (Get-PanelSonarPractica $T $P $incs)
      ARQUITECTURA = $arq; LISTA = (Get-ListaPractica $T $incs)
    }
  }
  return (Expand-Plantilla $Cuerpo @{ BATCH = (Get-BatchInforme $D); CABECERA = $cabecera; PRACTICAS = $practicas })
}

# ============================== EL SIGUIENTE PASO ==============================
# Un valor en la linea de comandos: tal cual si es una palabra sencilla (un modelo, una rama) y, si no, entre comillas.
function Format-ArgComando([string]$Valor) {
  if ($Valor -match '^[\w\.\-/]+$') { return $Valor }
  return ('"' + $Valor + '"')
}

# La linea con la que se lanzo la pasada, montada con estado.json: las rutas entre comillas, el modelo si lo hay, -SoloInforme o -Si segun
# $Respuesta (parar o corregir), las opciones del lanzamiento que guarda migracion.ps1 (-Practicas, -Reglas, -MaxHoras y -Limite si no son 0,
# -SinPruebaLocal; un estado.json de antes no las trae y no salen) y -JavaLegacy si hay ($Java). -Reintentar no: es de una sola vez. Con
# $ConPruebaLocal no sale -SinPruebaLocal: es el comando que hace la prueba en local que se salto.
function Get-ComandoPasada($Est, [string]$Respuesta, [string]$Java, [switch]$ConPruebaLocal) {
  $c = '.\migracion.ps1 -Legacy "' + $Est.legacy + '" -Migrado "' + $Est.migrado + '" -Plantilla "' + $Est.plantilla + '"'
  if ($Est.modelo) { $c += ' -Modelo ' + (Format-ArgComando ([string]$Est.modelo)) }
  if ($Respuesta -ceq 'parar') { $c += ' -SoloInforme' } elseif ($Respuesta -ceq 'corregir') { $c += ' -Si' }
  if ($Est.practicas -eq $true) { $c += ' -Practicas' }
  if ($Est.reglas -eq $true) { $c += ' -Reglas' }
  if ([double]$Est.maxHoras -ne 0) { $c += ' -MaxHoras ' + [string]$Est.maxHoras }
  if ([int]$Est.limite -ne 0) { $c += ' -Limite ' + [string]$Est.limite }
  if ($Est.sinPruebaLocal -eq $true -and -not $ConPruebaLocal) { $c += ' -SinPruebaLocal' }
  if ($Java) { $c += ' -JavaLegacy "' + $Java + '"' }
  return $c
}

# Lo que hay que hacer ahora: la primera de estas situaciones que se cumple. Devuelve Caso (corriendo, parada, cortada, distinto-corregido,
# distinto, local-jdk, local-fallo, local-incompleta, local-saltada, parar-con-problemas, corregido o pre), Comando ('' si no hay), y lo que dicen los textos: Fase, Motivo,
# Detalle, Registro, Worktree, N y M (con local-incompleta, los casos sin preparar y el total de casos). $Est es estado.json; $D, los datos del informe (Correccion, PruebaLocal y Diag.Errores).
#   1 fin vacio: sigue corriendo        2 parada      (extra: fin escrito pero la fase sin acabar, por -Limite: cortada)
#   3 distintos y hubo correccion       4 distintos sin correccion
#   5 la prueba en local fallo (con el JDK del original: local-jdk), o tiene casos que no se pudieron preparar y ninguno distinto (local-incompleta), o se salto
#   6 respuesta parar y quedan errores en la pagina 2        7 correccion completa con commits        8 lo demas: pre
function Get-SiguientePaso($Est, $D) {
  $r = [ordered]@{ Caso = ''; Fase = [string]$Est.fase; Motivo = ''; Detalle = ''; Registro = ''; Worktree = [string]$Est.worktree; N = 0; M = 0; Comando = '' }
  $respuesta = [string]$Est.respuesta
  $java = [string]$Est.javaLegacy
  $pasada = Get-ComandoPasada $Est $respuesta $java
  $origen = [string]$Est.ramaOrigen
  if (-not $origen -and $D.Correccion) { $origen = [string]$D.Correccion.base }
  if (-not $origen) { $origen = '<tu-rama>' }
  $distintos = 0
  if ($D.PruebaLocal) { $distintos = @(Get-CasosDistintos $D.PruebaLocal).Count }
  $sinPreparar = 0
  $casos = 0
  if ($D.PruebaLocal) { $sinPreparar = @(Get-CasosSinPreparar $D.PruebaLocal).Count; $casos = @($D.PruebaLocal.casos | Where-Object { $null -ne $_ }).Count }
  $corregido = [bool]($D.Correccion -and @($D.Correccion.commits | Where-Object { $null -ne $_ }).Count -gt 0)
  $errores = 0
  if ($D.Diag) { $errores = [int]$D.Diag.Errores }
  $local = ''
  if ($Est.pruebaLocal) { $local = [string]$Est.pruebaLocal.resultado }
  if (-not ([string]$Est.fin).Trim()) { $r.Caso = 'corriendo'; $r.Comando = $pasada }
  elseif ($Est.parada) {
    $r.Caso = 'parada'; $r.Motivo = [string]$Est.parada.motivo; $r.Detalle = [string]$Est.parada.detalle; $r.Registro = [string]$Est.parada.registro; $r.Comando = $pasada
  }
  elseif ([string]$Est.fase -cne 'hecha') { $r.Caso = 'cortada'; $r.Comando = $pasada }
  elseif ($distintos -gt 0 -and $corregido) {
    $r.Caso = 'distinto-corregido'; $r.N = $distintos
    $r.Comando = '.\prueba-local.ps1 -Legacy "' + $Est.legacy + '" -Migrado "' + $Est.migrado + '" -Desde ' + (Format-ArgComando $origen) + ' -Deshacer'
    if ($java) { $r.Comando += ' -JavaLegacy "' + $java + '"' }
  }
  elseif ($distintos -gt 0) { $r.Caso = 'distinto'; $r.N = $distintos }
  elseif ($local -ceq 'fallo' -and $Est.pruebaLocal.jdkOriginal -eq $true -and -not $java) {
    $r.Caso = 'local-jdk'; $r.Detalle = [string]$Est.pruebaLocal.detalle
    $r.Comando = Get-ComandoPasada $Est $respuesta 'C:\ruta\jdk-del-original'
  }
  elseif ($local -ceq 'fallo') { $r.Caso = 'local-fallo'; $r.Detalle = [string]$Est.pruebaLocal.detalle; $r.Comando = $pasada }
  elseif ($sinPreparar -gt 0) { $r.Caso = 'local-incompleta'; $r.N = $sinPreparar; $r.M = $casos; $r.Comando = $pasada }
  elseif ($local -ceq 'saltada') { $r.Caso = 'local-saltada'; $r.Comando = Get-ComandoPasada $Est $respuesta $java -ConPruebaLocal }
  elseif ($respuesta -ceq 'parar' -and $errores -gt 0) { $r.Caso = 'parar-con-problemas'; $r.N = $errores; $r.Comando = Get-ComandoPasada $Est 'corregir' $java }
  elseif ($corregido -and $D.Correccion.completa -eq $true) {
    $rama = [string]$Est.rama
    if (-not $rama) { $rama = [string]$D.Correccion.rama }
    $git = 'git -C "' + $Est.migrado + '" '
    $r.Caso = 'corregido'
    $r.Comando = (@(($git + 'log --oneline ' + (Format-ArgComando ($origen + '..' + $rama))), ($git + 'diff --stat ' + (Format-ArgComando ($origen + '...' + $rama))), ($git + 'merge ' + (Format-ArgComando $rama))) -join "`n")
  }
  else { $r.Caso = 'pre' }
  return [pscustomobject]$r
}

# El recuadro "Siguiente paso" de la portada y, debajo, la linea que manda a FLUJO.md. El texto de cada situacion es un trozo de la plantilla:
# siguiente-<caso> (las paradas, siguiente-parada-<motivo> o siguiente-parada-otro) y, con N = 1, la variante -uno si la hay. '' sin estado.json.
function Get-SiguienteHtml($D, $T) {
  if (-not $D.Estado) { return '' }
  $s = Get-SiguientePaso $D.Estado $D
  $nombre = 'siguiente-' + $s.Caso
  if ($s.Caso -ceq 'parada') {
    $nombre = 'siguiente-parada-' + $s.Motivo
    if (-not $T.ContainsKey($nombre)) { $nombre = 'siguiente-parada-otro' }
  }
  if ($s.N -eq 1 -and $T.ContainsKey("$nombre-uno")) { $nombre += '-uno' }
  $texto = Format-Trozo $T $nombre @{ FASE = $s.Fase; MOTIVO = $s.Motivo; DETALLE = $s.Detalle; REGISTRO = $s.Registro; WORKTREE = $s.Worktree; N = "$($s.N)"; M = "$($s.M)" }
  $comando = ''
  if ($s.Comando) { $comando = Format-Trozo $T 'siguiente-comando' @{ COMANDO = $s.Comando } }
  return (Format-Trozo $T 'siguiente' @{ TEXTO = $texto; COMANDO = $comando })
}

function Get-CuerpoIndex($D, $T, [string]$Cuerpo) {
  $est = $D.Estado
  $fase = ''
  $parada = ''
  $estado = ''
  $e = [pscustomobject]@{ batch = ''; legacy = ''; migrado = ''; plantilla = ''; rama = ''; modelo = ''; creado = $null; actualizado = $null; fin = $null; parada = $null; fase = '' }
  if ($est) { $e = $est }
  $fase = [string]$e.fase
  if ($e.parada) {
    $estado = Format-Trozo $T 'estado-parada' @{ FASE = $fase; MOTIVO = $e.parada.motivo }
    $parada = Format-Trozo $T 'parada' @{ MOTIVO = $e.parada.motivo; DETALLE = $e.parada.detalle; REGISTRO = $e.parada.registro; AYUDA = $e.parada.ayuda }
  }
  elseif ($fase -eq 'hecha' -and $D.Correccion -and $D.Correccion.completa -eq $true) { $estado = Format-Trozo $T 'estado-terminada' }
  elseif ($fase -eq 'hecha') { $estado = Format-Trozo $T 'estado-terminada-sin' }
  elseif ($fase -eq 'lectura-hecha') { $estado = Format-Trozo $T 'estado-hecha' }
  else { $estado = Format-Trozo $T 'estado-curso' @{ FASE = $fase } }
  $modelo = [string]$e.modelo
  if (-not $modelo) { $modelo = Format-Trozo $T 'modelo-defecto' }
  $c = @{}
  foreach ($s in @('hecha', 'atascada', 'pendiente')) { $c[$s] = "$(@($D.Tareas | Where-Object { $_.estado -eq $s }).Count)" }
  $rotulo = Format-Trozo $T 'rotulo-lleva'
  $duracion = Get-TextoDuracion $T $e.creado $e.actualizado
  if ($null -ne (ConvertTo-FechaInforme $e.fin)) { $rotulo = Format-Trozo $T 'rotulo-duro'; $duracion = Get-TextoDuracion $T $e.creado $e.fin }
  $fases = (@(Get-OrdenFases $D | Where-Object { $_ -cne 'lectura-hecha' -and $_ -cne 'hecha' } | ForEach-Object { Get-FaseHtml $D $T $_ }) -join "`n")
  return (Expand-Plantilla $Cuerpo @{
      BATCH = (Get-BatchInforme $D); ESTADO = $estado; MIGRADO = (Get-Hoja $e.migrado); ORIGINAL = (Get-Hoja $e.legacy); PLANTILLA = (Get-Hoja $e.plantilla)
      MODELO = $modelo; EMPEZO = (Get-TextoFecha $T $e.creado); DURACION_ROTULO = $rotulo; DURACION = $duracion
      ETIQUETA = (Format-Trozo $T 'et-medido'); ETIQUETA_FASES = (Format-Trozo $T 'et-medido')
      HECHAS = $c['hecha']; ATASCADAS = $c['atascada']; PENDIENTES = $c['pendiente']; PARADA = $parada; SIGUIENTE = (Get-SiguienteHtml $D $T)
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
    @{ Fichero = '4-correcciones.html'; Actual = 'ACTUAL_CORRECCIONES'; Titulo = 'titulo-correcciones'; Cuerpo = { param($D, $T, $C) Get-CuerpoCorrecciones $D $T $C } },
    @{ Fichero = '5-buenas-practicas.html'; Actual = 'ACTUAL_PRACTICAS'; Titulo = 'titulo-practicas'; Cuerpo = { param($D, $T, $C) Get-CuerpoPracticas $D $T $C } }
  )
  foreach ($p in $paginas) {
    $plantilla = Split-Plantilla (Read-PlantillaInforme $p.Fichero)
    $T = Merge-Trozos $marco.Trozos $plantilla.Trozos
    $v = @{ TITULO = (Format-Trozo $T $p.Titulo @{ BATCH = $batch }); ESTILO = $estilo; BATCH = $batch; CUERPO = (& $p.Cuerpo $D $T $plantilla.Cuerpo); ACTUAL_INDEX = ''; ACTUAL_ORIGINAL = ''; ACTUAL_PROBLEMAS = ''; ACTUAL_COMPARAR = ''; ACTUAL_CORRECCIONES = ''; ACTUAL_PRACTICAS = '' }
    $v[$p.Actual] = Format-Trozo $T 'actual'
    Save-PaginaInforme (Join-Path $Salida $p.Fichero) (Expand-Plantilla $marco.Cuerpo $v)
  }
}
