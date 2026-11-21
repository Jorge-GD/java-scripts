<#
probar-entrega.ps1 - Banco de pruebas de la pieza C5a: los informes despues de -Cierre (la portada con su Siguiente paso y su bloque Entrega,
la pagina 2 con el area Propiedades y la pagina 4 con Juntado con tu rama) y los textos que mandaban a juntar a mano.
No necesita Maven, Java ni Copilot: monta carpetas datos\ y estado.json de juguete (com.acme, batch-recibos) y genera las paginas con
Write-Informes en este mismo proceso. Los commits de los cierres salen de un repo git de juguete. Vale para Windows PowerShell 5.1 y para PowerShell 7.
Solo ASCII a proposito: los textos con tilde se escriben con \uXXXX y se pasan por [regex]::Unescape.

  .\tests\probar-entrega.ps1                       # todas las pruebas
  .\tests\probar-entrega.ps1 -Solo '(c)'           # las que llevan '(c)' en el nombre
  .\tests\probar-entrega.ps1 -Dir D:\tmp\x -Conservar

Sale con 0 si todo pasa y con 1 si algo falla.
#>
param(
  [string]$Dir = '',
  [string]$Solo = '',
  [switch]$Conservar
)
$ErrorActionPreference = 'Stop'
$aqui = Split-Path -Parent $MyInvocation.MyCommand.Path
$raiz = Split-Path -Parent $aqui
. (Join-Path $aqui 'comun-banco.ps1')
. (Join-Path $raiz 'comun.ps1')
. (Join-Path $raiz 'tareas.ps1')
. (Join-Path $raiz 'informe.ps1')

# ================================ UTILIDADES ================================
function Es([string]$Ascii) { return [regex]::Unescape($Ascii) }

function Escribe-Json([string]$Ruta, $Objeto) {
  $d = Split-Path $Ruta -Parent
  if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -Force) }
  [System.IO.File]::WriteAllText($Ruta, (ConvertTo-Json -InputObject $Objeto -Depth 8))
}

function Pagina([string]$Salida, [string]$Nombre) {
  $r = Get-Ruta $Salida $Nombre
  if (-not (Test-Path -LiteralPath $r)) { return '' }
  return [System.IO.File]::ReadAllText($r, (New-Object System.Text.UTF8Encoding($false)))
}

# La seccion <section id="..."> de una pagina, o '' si no esta.
function Panel-De([string]$Html, [string]$Id) { return [regex]::Match($Html, '(?s)<section[^>]*id="' + $Id + '".*?</section>').Value }

# El texto de un trozo de pagina, sin etiquetas, con las entidades HTML decodificadas y los espacios juntos.
function Texto-Plano([string]$Html) { return [System.Net.WebUtility]::HtmlDecode(([regex]::Replace($Html, '<[^>]+>', ' ') -replace '\s+', ' ').Trim()) }

# Lo que lleva el <pre class="cmd"> de un trozo, decodificado.
function Comando-De([string]$Html) { return [System.Net.WebUtility]::HtmlDecode([regex]::Match($Html, '(?s)<pre class="cmd">(.*?)</pre>').Groups[1].Value) -replace "`r", '' }

$ComandoCierre = '.\migracion.ps1 -Legacy "C:\ruta\original" -Migrado "C:\ruta\migrado" -Plantilla "C:\ruta\referencia" -Cierre'
$ComandoPasada = '.\migracion.ps1 -Legacy "C:\ruta\original" -Migrado "C:\ruta\migrado" -Plantilla "C:\ruta\referencia" -Modelo claude-sonnet-5.5'

# El estado.json de una pasada con la correccion hecha (respuesta corregir) y la prueba en local hecha; $Cambios lo pisa campo a campo.
function Estado-Base([hashtable]$Cambios = @{}) {
  $e = [ordered]@{
    version = 1; batch = 'batch-recibos'; legacy = 'C:\ruta\original'; migrado = 'C:\ruta\migrado'; plantilla = 'C:\ruta\referencia'
    worktree = 'C:\ruta\migrado-rescate'; rama = 'rescate/feat-recibos-20261121-0900'; ramaOrigen = 'feat/recibos'; javaLegacy = ''
    modelo = 'claude-sonnet-5.5'; aptitud = 'claude-sonnet-5.5'; respuesta = 'corregir'; fase = 'hecha'
    creado = '2026-11-21T09:00:00'; actualizado = '2026-11-21T10:00:00'; fin = '2026-11-21T10:00:00'; parada = $null
    pruebaLocal = [ordered]@{ resultado = 'hecha'; codigo = 0; minutos = 3.2; detalle = ''; registro = 'registros/prueba-local.log' }
    cierre = $null
  }
  foreach ($k in $Cambios.Keys) { $e[$k] = $Cambios[$k] }
  return $e
}

# correcciones.json: completa, con $Commits commits de arreglo.
function Correccion-Base([int]$Commits = 2) {
  return [ordered]@{
    completa = $true; codigo = 0; rama = 'rescate/feat-recibos-20261121-0900'; base = 'feat/recibos'
    commits = @(if ($Commits -gt 0) { 1..$Commits | ForEach-Object { [ordered]@{ hash = ('abc123' + $_); paso = 'estructura'; asunto = 'rescate(estructura): lote 1' } } })
    atascados = @(); resueltos = @(); variablesNuevas = @()
  }
}

function Caso-Local([string]$Job, [string]$Caso, [string]$Resultado) {
  return [ordered]@{ job = $Job; caso = $Caso; titulo = "Titulo $Caso"; resultado = $Resultado; motivo = ''; diferencias = @() }
}

# Los datos de la prueba en local: un objeto por job ($Jobs: nombre -> @(iguales, distintos)) y el estado de sus dos arneses (por defecto, hechos).
function Local-Base($Jobs, $Arneses = $null) {
  if (-not $Arneses) { $Arneses = [ordered]@{ original = 'hecha'; migrado = 'hecha' } }
  $js = @()
  $casos = @()
  foreach ($j in $Jobs.Keys) {
    $js += [ordered]@{ job = $j; casos = ($Jobs[$j][0] + $Jobs[$j][1]); iguales = $Jobs[$j][0]; distintos = $Jobs[$j][1]; sinProbar = 0 }
    for ($i = 1; $i -le $Jobs[$j][0]; $i++) { $casos += (Caso-Local $j "ok$i" 'igual') }
    for ($i = 1; $i -le $Jobs[$j][1]; $i++) { $casos += (Caso-Local $j "mal$i" 'distinto') }
  }
  return [ordered]@{ arneses = $Arneses; jobs = $js; casos = $casos }
}

# mapa.json con estos jobs (nombres), sin clases.
function Mapa-Base([string[]]$Jobs) {
  $js = @($Jobs | ForEach-Object { [ordered]@{ job = $_; definidoEn = 'src/main/java/com/acme/Config.java'; linea = 1; probado = $true; pasos = @(); clases = @(); dudas = @() } })
  return [ordered]@{ jobs = $js; sinJob = @() }
}

# Un repo git de juguete con $Commits commits despues del inicial. Devuelve su ruta y los commits de antes (el inicial) y sha (el ultimo).
function Repo-Cierre([string]$Nombre, [int]$Commits) {
  $r = Join-Path $Dir $Nombre
  [void](New-Item -ItemType Directory -Path $r -Force)
  Escribe $r 'pom.xml' "<project/>`n"
  Inicia-Repo $r
  $antes = (GitEn $r @('rev-parse', 'HEAD')).Trim()
  for ($i = 1; $i -le $Commits; $i++) {
    Escribe $r "f$i.txt" "x$i`n"
    [void](GitEn $r @('add', "f$i.txt"))
    [void](GitEn $r @('commit', '-q', '-m', "arreglo $i"))
  }
  return [pscustomobject]@{ Ruta = $r; Antes = $antes; Sha = (GitEn $r @('rev-parse', 'HEAD')).Trim() }
}

# estado.cierre de un cierre que junto: $Repo da antes y sha.
function Cierre-Hecho($Repo, $Avisos = @(), $Revisar = @(), [bool]$Juntada = $false) {
  return [ordered]@{
    antes = $Repo.Antes; sha = $Repo.Sha; cuando = '2026-11-21T11:30:00'; juntada = $Juntada; hecho = $true
    deshacer = ('git -C "' + $Repo.Ruta + '" reset --hard ' + $Repo.Antes); avisos = @($Avisos); revisar = @($Revisar)
  }
}

# Una carpeta de salida (migracion-batch) con estado.json y los datos que se den ($Datos: nombre de fichero de datos\ -> objeto o texto), con las paginas montadas.
function Nueva-Salida([string]$Nombre, $Est, $Datos = @{}) {
  $s = Join-Path (Join-Path $Dir $Nombre) 'migracion-batch'
  Escribe-Json (Get-Ruta $s 'datos/estado.json') $Est
  foreach ($k in $Datos.Keys) {
    if ($Datos[$k] -is [string]) { Escribe $s ('datos/' + $k) $Datos[$k] } else { Escribe-Json (Get-Ruta $s ('datos/' + $k)) $Datos[$k] }
  }
  Write-Informes -Salida $s
  return $s
}

# Lo que dice Get-SiguientePaso de una salida montada.
function Paso-De([string]$Salida) {
  $d = Read-DatosInforme $Salida
  return (Get-SiguientePaso $d.Estado $d)
}

# Los diagnosticos de antes y despues (sin problemas) que necesita la pagina 4.
function Datos-Pagina4() {
  $md = "# Diagnostico de rescate: batch-recibos`n`n- Estado: compila: SI | tests: OK`n`n| Paso | Errores | Avisos |`n|---|---|---|`n| build | 0 | 0 |`n"
  return [ordered]@{
    'hallazgos-antes.json' = '[]'; 'diagnostico-antes.md' = $md; 'hallazgos-despues.json' = '[]'; 'diagnostico-despues.md' = $md
    'correcciones.json' = (Correccion-Base 2); 'prueba-local.json' = (Local-Base ([ordered]@{ cargaJob = @(2, 0) })); 'mapa.json' = (Mapa-Base @('cargaJob'))
  }
}

# propiedades.json de juguete: forma de la cabecera de propiedades.ps1. $Legacy y $Migrado son las listas de entradas ya hechas.
function Propiedades-Base($Legacy = @(), $Migrado = @(), [string]$Renombres = 'ok') {
  return [ordered]@{
    clave = 'abc12345'; ficheros = [ordered]@{ legacy = @('application.properties'); migrado = @('application.yml'); referencia = @() }
    renombres = [ordered]@{ estado = $Renombres; motivo = 'sin jars con metadatos'; jars = 3; claves = 10 }
    legacy = @($Legacy); migrado = @($Migrado)
    resumen = [ordered]@{ total = @($Legacy).Count; igual = 0; falta = @($Legacy | Where-Object { $_.estado -ceq 'falta' }).Count; 'renombrada-falta' = @($Legacy | Where-Object { $_.estado -ceq 'renombrada-falta' }).Count }
  }
}

function Prop-Legacy([string]$Clave, [string]$Estado, [string]$Fichero = 'src/main/resources/application.properties', [int]$Linea = 1, $Extra = @{}) {
  $p = [ordered]@{ clave = $Clave; perfil = 'default'; fichero = $Fichero; linea = $Linea; estado = $Estado; enMigrado = $null; valorLegacy = $null; valorMigrado = $null; variable = $null; renombradaA = $null; valorIgual = $null; secreto = $false; texto = '' }
  foreach ($k in $Extra.Keys) { $p[$k] = $Extra[$k] }
  return $p
}

function Prop-Migrado([string]$Clave, [bool]$SinLeer, [string]$Fichero = 'src/main/resources/application.yml', [int]$Linea = 1, $Extra = @{}) {
  $p = [ordered]@{ clave = $Clave; perfil = 'default'; fichero = $Fichero; linea = $Linea; valor = $null; secreto = $false; nueva = $true; sinLeer = $SinLeer; nombreViejo = $false; renombradaA = $null; texto = '' }
  foreach ($k in $Extra.Keys) { $p[$k] = $Extra[$k] }
  return $p
}

$TxtJuntalos = Es 'Revisa los cambios y j\u00fantalos con tu rama con -Cierre'
$TxtNoMovida = 'Tu rama no se ha movido'
$TxtMas = Es 'm\u00e1s'

$Pruebas = [ordered]@{}

# ================================ (h) SIGUIENTE PASO: LOS CASO DE SIEMPRE ================================
$Pruebas['c5 (h) Get-SiguientePaso devuelve los mismos Caso que antes en cada una de sus ramas, en su orden'] = {
  $localFallo = [ordered]@{ resultado = 'fallo'; codigo = 1; minutos = 1.5; detalle = 'dos / tres'; registro = 'registros/prueba-local.log' }
  $localJdk = [ordered]@{ resultado = 'fallo'; codigo = 1; minutos = 1.5; detalle = 'no compila'; jdkOriginal = $true; registro = 'registros/prueba-local.log' }
  $localSalta = [ordered]@{ resultado = 'saltada'; codigo = $null; minutos = 0; detalle = ''; registro = '' }
  $parada = [ordered]@{ motivo = 'git'; detalle = 'd'; registro = 'r'; ayuda = 'a' }
  $dBase = [ordered]@{ jobs = @([ordered]@{ job = 'cargaJob'; casos = 2; iguales = 2; distintos = 0; sinProbar = 0 }); casos = @((Caso-Local 'cargaJob' 'a' 'igual'), (Caso-Local 'cargaJob' 'b' 'igual')) }
  $dDistinto = [ordered]@{ jobs = $dBase.jobs; casos = @($dBase.casos) + @(Caso-Local 'cargaJob' 'c' 'distinto') }
  $dIncompleta = [ordered]@{ jobs = $dBase.jobs; casos = @($dBase.casos) + @(Caso-Local 'cargaJob' 'c' 'no se pudo preparar') }
  $tabla = @(
    @('corriendo', (Estado-Base @{ fin = '' }), @{}),
    @('parada', (Estado-Base @{ parada = $parada }), @{}),
    @('cortada', (Estado-Base @{ fase = 'resumen' }), @{}),
    @('distinto-corregido', (Estado-Base), @{ Correccion = (Correccion-Base 2); PruebaLocal = $dDistinto }),
    @('distinto', (Estado-Base), @{ PruebaLocal = $dDistinto }),
    @('local-jdk', (Estado-Base @{ pruebaLocal = $localJdk }), @{}),
    @('local-fallo', (Estado-Base @{ pruebaLocal = $localFallo }), @{}),
    @('local-incompleta', (Estado-Base), @{ PruebaLocal = $dIncompleta }),
    @('local-saltada', (Estado-Base @{ pruebaLocal = $localSalta }), @{}),
    @('parar-con-problemas', (Estado-Base @{ respuesta = 'parar' }), @{ Diag = [ordered]@{ Errores = 3; Avisos = 0 } }),
    @('corregido', (Estado-Base), @{ Correccion = (Correccion-Base 2); PruebaLocal = $dBase }),
    @('pre', (Estado-Base @{ respuesta = 'parar' }), @{ PruebaLocal = $dBase })
  )
  foreach ($f in $tabla) {
    $est = (ConvertTo-Json -InputObject $f[1] -Depth 8) | ConvertFrom-Json
    $d = (ConvertTo-Json -InputObject ([pscustomobject]$f[2]) -Depth 8) | ConvertFrom-Json
    $s = Get-SiguientePaso $est $d
    Igual ('Caso ' + $f[0]) $f[0] $s.Caso
  }
  # el comando de una parada que no es del cierre sigue siendo el de la pasada
  $est = (ConvertTo-Json -InputObject (Estado-Base @{ parada = $parada }) -Depth 8) | ConvertFrom-Json
  Igual 'una parada de la pasada: el comando de la pasada' ($ComandoPasada + ' -Si') (Get-SiguientePaso $est ([pscustomobject]@{})).Comando
}

# ================================ (a) CORREGIDO SIN CIERRE ================================
$Pruebas['c5 (a) corregido sin cierre: el texto manda a juntar con -Cierre y el comando son log, diff --stat y -Cierre, sin git merge'] = {
  $s = Nueva-Salida 'a' (Estado-Base) ([ordered]@{ 'correcciones.json' = (Correccion-Base 2); 'prueba-local.json' = (Local-Base ([ordered]@{ cargaJob = @(2, 0) })); 'mapa.json' = (Mapa-Base @('cargaJob')) })
  $paso = Paso-De $s
  Igual 'caso corregido' 'corregido' $paso.Caso
  $lineas = @($paso.Comando -split "`n" | ForEach-Object { $_.TrimEnd("`r") })
  Igual 'tres lineas de comando' 3 $lineas.Count
  Igual 'la primera, git log' 'git -C "C:\ruta\migrado" log --oneline feat/recibos..rescate/feat-recibos-20261121-0900' $lineas[0]
  Igual 'la segunda, git diff --stat' 'git -C "C:\ruta\migrado" diff --stat feat/recibos...rescate/feat-recibos-20261121-0900' $lineas[1]
  Igual 'la tercera, el de -Cierre' $ComandoCierre $lineas[2]
  $i = Pagina $s 'index.html'
  $sec = Panel-De $i 'siguiente-paso'
  Comprueba 'el texto dice que revises y juntes con -Cierre' ((Texto-Plano $sec).Contains($TxtJuntalos)) (Texto-Plano $sec)
  $cmd = Comando-De $sec
  Igual 'la portada ensena el mismo comando' ($paso.Comando -replace "`r", '') $cmd
  Comprueba 'y no dice git merge' ($cmd -notmatch 'merge' -and (Texto-Plano $sec) -notmatch 'merge') $cmd
  Comprueba 'sin cierre no sale el bloque Entrega' ($i -notmatch 'id="entrega"')
  # con cierre.hecho = false (un cierre a medias) tampoco
  $e = Estado-Base @{ cierre = [ordered]@{ antes = 'a'; sha = 'b'; cuando = '2026-11-21T11:30:00'; juntada = $false; hecho = $false; deshacer = 'x'; avisos = @(); revisar = @() } }
  $s2 = Nueva-Salida 'a-no-hecho' $e ([ordered]@{ 'correcciones.json' = (Correccion-Base 2) })
  Igual 'con hecho = false sigue siendo corregido' 'corregido' (Paso-De $s2).Caso
  Comprueba 'y tampoco sale Entrega' ((Pagina $s2 'index.html') -notmatch 'id="entrega"')
}

# ================================ (b) JUNTADO: corregido y pre ================================
$Pruebas['c5 (b) corregido y pre con cierre.hecho: siguiente-juntado con N, antes..sha y el comando git log'] = {
  $repo = Repo-Cierre 'b-repo' 3
  $antes7 = $repo.Antes.Substring(0, 7)
  $sha7 = $repo.Sha.Substring(0, 7)
  foreach ($caso in @('corregido', 'pre')) {
    $est = Estado-Base @{ migrado = $repo.Ruta; cierre = (Cierre-Hecho $repo) }
    $datos = [ordered]@{ 'prueba-local.json' = (Local-Base ([ordered]@{ cargaJob = @(2, 0) })); 'mapa.json' = (Mapa-Base @('cargaJob')) }
    if ($caso -ceq 'corregido') { $datos['correcciones.json'] = (Correccion-Base 2) } else { $est['respuesta'] = 'parar' }
    $s = Nueva-Salida "b-$caso" $est $datos
    $paso = Paso-De $s
    Igual "$caso : el Caso no cambia" $caso $paso.Caso
    Igual "$caso : N son los commits del rango" 3 $paso.N
    Igual "$caso : el comando es git log antes..sha" ('git -C "' + $repo.Ruta + '" log --oneline ' + $repo.Antes + '..' + $repo.Sha) $paso.Comando
    $sec = Panel-De (Pagina $s 'index.html') 'siguiente-paso'
    $t = Texto-Plano $sec
    Comprueba "$caso : dice que ya esta en tu rama con 3 commits" ($t -match (Es 'Ya est. en tu rama: 3 commits')) $t
    Comprueba "$caso : de antes a sha, con 7 caracteres" ($t.Contains("de $antes7 a $sha7")) $t
    Comprueba "$caso : manda a revisar los commits marcados antes del push" ($t -match 'Revisa los commits marcados' -and $t -match 'antes del push') $t
    Comprueba "$caso : el push es tuyo" ($t -match 'El push es tuyo') $t
    Comprueba "$caso : prueba en pre con el guion de la pagina 1" ($t -match 'prueba en pre' -and $sec -match 'href="1-batch-original\.html"') $t
    Igual "$caso : el comando de la portada" $paso.Comando (Comando-De $sec)
  }
  # un solo commit: en singular; sin git que lo cuente: sin numero
  $uno = Repo-Cierre 'b-uno' 1
  $s = Nueva-Salida 'b-uno-s' (Estado-Base @{ migrado = $uno.Ruta; cierre = (Cierre-Hecho $uno) }) ([ordered]@{ 'correcciones.json' = (Correccion-Base 2) })
  Comprueba 'con 1 commit, en singular' ((Texto-Plano (Panel-De (Pagina $s 'index.html') 'siguiente-paso')) -match 'Ya est. en tu rama: 1 commit,') (Texto-Plano (Panel-De (Pagina $s 'index.html') 'siguiente-paso'))
  $s = Nueva-Salida 'b-sin-git' (Estado-Base @{ cierre = (Cierre-Hecho $repo) }) ([ordered]@{ 'correcciones.json' = (Correccion-Base 2) })
  $t = Texto-Plano (Panel-De (Pagina $s 'index.html') 'siguiente-paso')
  Comprueba 'si git no cuenta los commits, no inventa un numero' ($t -match 'Ya est. en tu rama: los commits' -and $t -notmatch '\b0 commits') $t
}

# ================================ (c) PARADAS DEL CIERRE ================================
$Pruebas['c5 (c) cada parada cierre-*: su texto, su DETALLE y el comando de -Cierre (la prueba en local, el de la pasada); un motivo desconocido cae en otro'] = {
  $frases = [ordered]@{
    'cierre-pendiente'          = (Es 'La pasada todav\u00eda no est\u00e1 lista para juntar')
    'cierre-prueba-local'       = 'La prueba en local no da para juntar'
    'cierre-cambios-sin-commit' = 'Tu carpeta tiene cambios sin commit'
    'cierre-conflicto'          = 'no se pueden juntar solos'
    'cierre-puertas'            = 'no pasa las puertas'
    'cierre-no-ff'              = (Es 'ha cambiado mientras se med\u00edan las puertas')
  }
  foreach ($m in $frases.Keys) {
    $p = [ordered]@{ motivo = $m; detalle = "detalle de $m <b>&</b> en pantalla"; registro = "C:\ruta\registro-$m.log"; ayuda = 'ayuda' }
    $s = Nueva-Salida "c-$m" (Estado-Base @{ parada = $p })
    $paso = Paso-De $s
    Igual "$m : Caso parada" 'parada' $paso.Caso
    Igual "$m : con su motivo" $m $paso.Motivo
    $sec = Panel-De (Pagina $s 'index.html') 'siguiente-paso'
    $t = Texto-Plano $sec
    Comprueba "$m : su propio texto" ($t.Contains($frases[$m])) $t
    Comprueba "$m : dice que tu rama no se ha movido" ($t.Contains($TxtNoMovida)) $t
    Comprueba "$m : lleva el DETALLE, escapado" ($t.Contains("detalle de $m <b>&</b> en pantalla") -and $sec.Contains('&lt;b&gt;&amp;&lt;/b&gt;')) $sec
    if ($m -ceq 'cierre-prueba-local') {
      Igual "$m : el comando es el de la pasada" ($ComandoPasada + ' -Si') (Comando-De $sec)
      Comprueba "$m : y el texto manda a lanzar -Cierre despues" ($t -match 'lanza -Cierre') $t
    }
    else { Igual "$m : el comando es el de -Cierre" $ComandoCierre (Comando-De $sec) }
    Igual "$m : Get-SiguientePaso da el mismo comando" (Comando-De $sec) ($paso.Comando -replace "`r", '')
  }
  # la prueba en local se salto: el comando de la pasada no repite -SinPruebaLocal
  $p = [ordered]@{ motivo = 'cierre-prueba-local'; detalle = 'no hay datos'; registro = 'r'; ayuda = 'a' }
  $s = Nueva-Salida 'c-salto' (Estado-Base @{ parada = $p; sinPruebaLocal = $true })
  Igual 'cierre-prueba-local con -SinPruebaLocal en la pasada: el comando no lo repite' ($ComandoPasada + ' -Si') (Paso-De $s).Comando
  # un motivo del cierre que no conocemos
  $p = [ordered]@{ motivo = 'cierre-otro'; detalle = 'algo raro'; registro = 'r'; ayuda = 'a' }
  $s = Nueva-Salida 'c-otro' (Estado-Base @{ parada = $p })
  $sec = Panel-De (Pagina $s 'index.html') 'siguiente-paso'
  Comprueba 'cierre-otro cae en el texto de otro motivo' ((Texto-Plano $sec) -match 'Ha fallado el propio script \(\s*cierre-otro\s*\)') (Texto-Plano $sec)
  Igual 'y su comando es el de -Cierre' $ComandoCierre (Comando-De $sec)
  # y una parada que no es del cierre no cambia
  $p = [ordered]@{ motivo = 'git'; detalle = 'x'; registro = 'r'; ayuda = 'a' }
  $s = Nueva-Salida 'c-git' (Estado-Base @{ parada = $p })
  Igual 'una parada de la pasada: su comando de siempre' ($ComandoPasada + ' -Si') (Comando-De (Panel-De (Pagina $s 'index.html') 'siguiente-paso'))
}

# ================================ (d) EL BLOQUE ENTREGA ================================
$Pruebas['c5 (d) Entrega sale solo con hecho: lo juntado, como deshacerlo, los commits a revisar y los avisos'] = {
  $repo = Repo-Cierre 'd-repo' 3
  $revisar = @([ordered]@{ hash = 'abc1234'; asunto = 'rescate(config): cambia la url <pre>' }, [ordered]@{ hash = 'def5678'; asunto = 'rescate(config): otra' })
  $est = Estado-Base @{ migrado = $repo.Ruta; cierre = (Cierre-Hecho $repo @('error: uno') $revisar) }
  $s = Nueva-Salida 'd' $est ([ordered]@{ 'correcciones.json' = (Correccion-Base 2) })
  $i = Pagina $s 'index.html'
  $sec = Panel-De $i 'entrega'
  Comprueba 'con hecho, la portada tiene el panel Entrega' ($sec.Length -gt 0) 'sin id="entrega"'
  $t = Texto-Plano $sec
  Comprueba 'dice 3 commits, de antes a sha (7 caracteres) y cuando' ($t -match '3 commits' -and $t.Contains($repo.Antes.Substring(0, 7)) -and $t.Contains($repo.Sha.Substring(0, 7)) -and $t.Contains('21-11-2026 11:30')) $t
  Comprueba 'la etiqueta es Medido' ($sec -match 'et et-medido')
  Comprueba 'dice como deshacerlo, con el comando' ((Comando-De $sec) -ceq ('git -C "' + $repo.Ruta + '" reset --hard ' + $repo.Antes)) (Comando-De $sec)
  Comprueba 'Revisa antes del push, con hash y asunto de cada commit' ($t -match 'Revisa antes del push' -and $t.Contains('abc1234 rescate(config): cambia la url <pre>') -and $t.Contains('def5678 rescate(config): otra')) $t
  Comprueba 'el asunto va escapado' ($sec.Contains('cambia la url &lt;pre&gt;'))
  Comprueba 'un aviso, sin y N mas' ($t.Contains('error: uno') -and $t -notmatch ('y \d+ ' + $TxtMas)) $t
  # sin cierre o con hecho = false: no sale
  $sin = Nueva-Salida 'd-sin' (Estado-Base) ([ordered]@{ 'correcciones.json' = (Correccion-Base 2) })
  Comprueba 'sin cierre no sale Entrega' ((Pagina $sin 'index.html') -notmatch 'id="entrega"' -and (Pagina $sin 'index.html') -notmatch 'Lista de entrega')
}

$Pruebas['c5 (d) Entrega: sin commits que revisar dice que ninguno toca la configuracion; 12 avisos dan 10 y y 2 mas; sin avisos dice ninguno'] = {
  $repo = Repo-Cierre 'd2-repo' 2
  $doce = @(1..12 | ForEach-Object { 'aviso-{0:00}: algo <b>raro</b>' -f $_ })
  $s = Nueva-Salida 'd2' (Estado-Base @{ migrado = $repo.Ruta; cierre = (Cierre-Hecho $repo $doce @()) }) ([ordered]@{ 'correcciones.json' = (Correccion-Base 2) })
  $sec = Panel-De (Pagina $s 'index.html') 'entrega'
  $t = Texto-Plano $sec
  Comprueba 'sin commits de configuracion: lo dice' ($t.Contains((Es 'Ning\u00fan commit toca la configuraci\u00f3n'))) $t
  Comprueba 'salen los 10 primeros avisos' ((1..10 | Where-Object { $t.Contains(('aviso-{0:00}' -f $_)) }).Count -eq 10) $t
  Comprueba 'el 11 y el 12 no salen' (-not $t.Contains('aviso-11') -and -not $t.Contains('aviso-12')) $t
  Comprueba ('y dice y 2 ' + $TxtMas) ($t.Contains("y 2 $TxtMas")) $t
  Comprueba 'el aviso va escapado' ($sec.Contains('algo &lt;b&gt;raro&lt;/b&gt;'))
  Comprueba 'dice donde estan todos' ($t.Contains('cierre.avisos'))
  # exactamente 10: sin y N mas
  $diez = @($doce | Select-Object -First 10)
  $s = Nueva-Salida 'd2-diez' (Estado-Base @{ migrado = $repo.Ruta; cierre = (Cierre-Hecho $repo $diez @()) }) ([ordered]@{ 'correcciones.json' = (Correccion-Base 2) })
  $t = Texto-Plano (Panel-De (Pagina $s 'index.html') 'entrega')
  Comprueba 'con 10 avisos salen los 10 y ningun y N mas' ($t.Contains('aviso-10') -and $t -notmatch ('y \d+ ' + $TxtMas)) $t
  # ninguno
  $s = Nueva-Salida 'd2-cero' (Estado-Base @{ migrado = $repo.Ruta; cierre = (Cierre-Hecho $repo @() @()) }) ([ordered]@{ 'correcciones.json' = (Correccion-Base 2) })
  $t = Texto-Plano (Panel-De (Pagina $s 'index.html') 'entrega')
  Comprueba 'sin avisos dice que no hay ninguno' ($t -match 'Avisos que no paran el cierre Ninguno') $t
  # tu rama habia avanzado: lo dice
  $s = Nueva-Salida 'd2-juntada' (Estado-Base @{ migrado = $repo.Ruta; cierre = (Cierre-Hecho $repo @() @() $true) }) ([ordered]@{ 'correcciones.json' = (Correccion-Base 2) })
  Comprueba 'con juntada = true cuenta que tu rama habia avanzado' ((Texto-Plano (Panel-De (Pagina $s 'index.html') 'entrega')) -match 'Tu rama hab.a avanzado')
}

# ================================ (e) LA LISTA DE ENTREGA ================================
function Fila-De($Lista, [string]$Id) { return @($Lista | Where-Object { $_.Id -ceq $Id })[0] }

$Pruebas['c5 (e) lista de entrega: una fila por punto, con su estado, su etiqueta y su enlace; Get-ListaEntrega las devuelve en orden'] = {
  $repo = Repo-Cierre 'e-repo' 2
  $conv = [ordered]@{ jobs = @([ordered]@{ job = 'cargaJob'; veredicto = 'a-la-vez'; motivos = @(); reponer = @() }, [ordered]@{ job = 'resumenJob'; veredicto = 'en-serie'; motivos = @(); reponer = @() }, [ordered]@{ job = 'avisoJob'; veredicto = 'en-serie'; motivos = @(); reponer = @() }); fijos = [ordered]@{ batch = 'b'; serie = @('uno'); aLaVez = 'v' } }
  $datos = [ordered]@{
    'correcciones.json' = (Correccion-Base 2); 'mapa.json' = (Mapa-Base @('cargaJob', 'resumenJob')); 'prueba-local.json' = (Local-Base ([ordered]@{ cargaJob = @(2, 0); resumenJob = @(1, 0) }))
    'propiedades.json' = (Propiedades-Base @((Prop-Legacy 'a.b' 'igual')) @()); 'convivencia.json' = $conv
  }
  $s = Nueva-Salida 'e-bien' (Estado-Base @{ migrado = $repo.Ruta; cierre = (Cierre-Hecho $repo @('error: uno')) }) $datos
  $d = Read-DatosInforme $s
  $l = @(Get-ListaEntrega $d)
  Igual 'cinco filas' 5 $l.Count
  Igual 'en su orden' 'prueba-local,puertas,limpieza,propiedades,convivencia' (($l | ForEach-Object { $_.Id }) -join ',')
  foreach ($f in $l) { Igual ($f.Id + ' : bien') 'bien' $f.Estado }
  foreach ($f in $l) { Igual ($f.Id + ' : origen medido') 'et-medido' $f.Origen }
  Igual 'convivencia: N a la vez y M uno detras de otro' '1 2' ((Fila-De $l 'convivencia').Valores.N + ' ' + (Fila-De $l 'convivencia').Valores.M)
  $sec = Panel-De (Pagina $s 'index.html') 'entrega'
  $filas = @([regex]::Matches($sec, '(?s)<li class="fila s-(\w+)">.*?</li>'))
  Igual 'la portada tiene una fila por punto' 5 $filas.Count
  Igual 'todas con estado bien' 'bien,bien,bien,bien,bien' (($filas | ForEach-Object { $_.Groups[1].Value }) -join ',')
  Comprueba 'cada fila lleva la etiqueta Medido' (@($filas | Where-Object { $_.Value -match 'et et-medido' }).Count -eq 5)
  $t = Texto-Plano $sec
  Comprueba 'los cinco puntos por su nombre' ($t -match 'Prueba en local' -and $t -match 'Puertas al juntar' -and $t -match 'Limpieza' -and $t -match 'Propiedades' -and $t -match 'Convivencia en pre') $t
  Comprueba 'convivencia dice 1 a la vez, 2 uno detras de otro' ($t.Contains((Es '1 a la vez, 2 uno detr\u00e1s de otro'))) $t
  foreach ($h in @('3-original-vs-migrado.html', '4-correcciones.html#juntado', '5-buenas-practicas.html', '2-problemas.html#g-propiedades', '1-batch-original.html')) {
    Comprueba "enlace a $h" ($sec.Contains('href="' + $h + '"')) $sec
  }
}

$Pruebas['c5 (e) lista de entrega: revisar con la cuenta en prueba en local, limpieza y propiedades'] = {
  $repo = Repo-Cierre 'e2-repo' 2
  $avisos = @('error: uno', 'limpieza: A.java:3 un import sobra', 'limpieza: B.java:9 otro', 'limpieza: no cuenta si no empieza asi: x')
  $avisos[3] = 'aviso: limpieza: no empieza por limpieza:'
  $props = @((Prop-Legacy 'a.uno' 'falta'), (Prop-Legacy 'a.dos' 'renombrada-falta' 'src/main/resources/application.properties' 2 @{ renombradaA = 'a.nuevo' }), (Prop-Legacy 'a.tres' 'distinto'), (Prop-Legacy 'a.cuatro' 'ya-no-existe'))
  $datos = [ordered]@{
    'correcciones.json' = (Correccion-Base 2); 'mapa.json' = (Mapa-Base @('cargaJob', 'resumenJob', 'avisoJob'))
    'prueba-local.json' = (Local-Base ([ordered]@{ cargaJob = @(2, 0); resumenJob = @(0, 0); avisoJob = @(1, 2) }))
    'propiedades.json' = (Propiedades-Base $props @())
  }
  $s = Nueva-Salida 'e-revisar' (Estado-Base @{ migrado = $repo.Ruta; cierre = (Cierre-Hecho $repo $avisos) }) $datos
  $l = @(Get-ListaEntrega (Read-DatosInforme $s))
  $pl = Fila-De $l 'prueba-local'
  Igual 'prueba en local: revisar' 'revisar' $pl.Estado
  Igual 'con 2 fallos de 3 jobs (resumenJob sin caso igual y avisoJob con distintos) y sus textos' '2 3 el job resumenJob no tiene ningun caso igual; el job avisoJob tiene 2 casos distintos' ($pl.Valores.N + ' ' + $pl.Valores.M + ' ' + $pl.Valores.TEXTOS)
  $li = Fila-De $l 'limpieza'
  Igual 'limpieza: revisar' 'revisar' $li.Estado
  Igual 'con la cuenta de los que empiezan por limpieza:' '2' $li.Valores.N
  $pr = Fila-De $l 'propiedades'
  Igual 'propiedades: revisar' 'revisar' $pr.Estado
  Igual 'con la cuenta de falta mas renombrada-falta (no cuentan distinto ni ya-no-existe)' '2' $pr.Valores.N
  Igual 'convivencia sin JSON: falta' 'falta' (Fila-De $l 'convivencia').Estado
  Igual 'puertas: bien' 'bien' (Fila-De $l 'puertas').Estado
  $filas = @([regex]::Matches((Panel-De (Pagina $s 'index.html') 'entrega'), '(?s)<li class="fila s-(\w+)">.*?</li>') | ForEach-Object { $_.Groups[1].Value })
  Igual 'en la pagina: revisar, bien, revisar, revisar, falta' 'revisar,bien,revisar,revisar,falta' ($filas -join ',')
  $t = Texto-Plano (Panel-De (Pagina $s 'index.html') 'entrega')
  Comprueba 'la cuenta y los textos salen en la frase' ($t -match '\(2\)' -and $t -match 'el job resumenJob no tiene ningun caso igual; el job avisoJob tiene 2 casos distintos') $t
  Comprueba 'y los estados en palabras' ($t -match 'Revisar' -and $t -match 'Bien' -and $t -match 'Falta') $t
}

$Pruebas['c5 (e) lista de entrega: cada punto en falta (sin datos), y las filas sueltas'] = {
  $s = Nueva-Salida 'e-falta' (Estado-Base) ([ordered]@{ 'correcciones.json' = (Correccion-Base 2) })
  $l = @(Get-ListaEntrega (Read-DatosInforme $s))
  Igual 'cinco filas' 5 $l.Count
  Igual 'prueba en local sin JSON: falta' 'falta' (Fila-De $l 'prueba-local').Estado
  Igual 'puertas sin hecho: falta' 'falta' (Fila-De $l 'puertas').Estado
  Igual 'limpieza sin cierre: falta' 'falta' (Fila-De $l 'limpieza').Estado
  Igual 'propiedades sin JSON: falta' 'falta' (Fila-De $l 'propiedades').Estado
  Igual 'convivencia sin JSON: falta' 'falta' (Fila-De $l 'convivencia').Estado
  # una medida de propiedades cortada (sin resumen) no es un bien
  $cortada = [ordered]@{ clave = ''; ficheros = [ordered]@{ legacy = @(); migrado = @(); referencia = @() }; renombres = [ordered]@{ estado = 'no se pudo medir'; motivo = 'cortada'; jars = 0; claves = 0 }; legacy = @(); migrado = @(); resumen = $null }
  $s = Nueva-Salida 'e-cortada' (Estado-Base) ([ordered]@{ 'correcciones.json' = (Correccion-Base 2); 'propiedades.json' = $cortada })
  Igual 'propiedades con la medida cortada: falta' 'falta' (Fila-De @(Get-ListaEntrega (Read-DatosInforme $s)) 'propiedades').Estado
  # sin mapa no se sabe que jobs mirar
  $s = Nueva-Salida 'e-sin-mapa' (Estado-Base) ([ordered]@{ 'prueba-local.json' = (Local-Base ([ordered]@{ cargaJob = @(2, 0) })) })
  Igual 'prueba en local sin mapa de jobs: falta' 'falta' (Fila-De @(Get-ListaEntrega (Read-DatosInforme $s)) 'prueba-local').Estado
  # con la etiqueta de la fila: lo que devuelve la funcion es el nombre del trozo, y existe en las plantillas
  $marco = Split-Plantilla (Read-PlantillaInforme 'marco.html')
  foreach ($f in $l) { Comprueba ($f.Id + ' : su etiqueta existe en las plantillas') ($marco.Trozos.ContainsKey($f.Origen)) $f.Origen }
}

# ================================ (f) PAGINA 2: PROPIEDADES ================================
$Pruebas['c5 (f) pagina 2, area Propiedades: falta, renombrada-falta, ya-no-existe, distinto y las del migrado sin leer; los demas estados no salen'] = {
  $leg = @(
    (Prop-Legacy 'recibos.ruta' 'falta' 'src/main/resources/application.properties' 4)
    (Prop-Legacy 'recibos.cola' 'renombrada-falta' 'src/main/resources/application.properties' 7 @{ renombradaA = 'recibos.cola-nueva' })
    (Prop-Legacy 'recibos.vieja' 'ya-no-existe' 'src/main/resources/application-pre.properties' 2)
    (Prop-Legacy 'recibos.limite' 'distinto' 'src/main/resources/application.properties' 9)
    (Prop-Legacy 'recibos.igual' 'igual')
    (Prop-Legacy 'recibos.variable' 'por-variable')
    (Prop-Legacy 'recibos.renombrada' 'renombrada' 'src/main/resources/application.properties' 3 @{ renombradaA = 'recibos.renombrada-nueva' })
  )
  $mig = @(
    (Prop-Migrado 'otra.sobra' $true 'src/main/resources/application.yml' 12)
    (Prop-Migrado 'otra.nueva' $false 'src/main/resources/application.yml' 13)
    (Prop-Migrado 'otra.vieja' $false 'src/main/resources/application.yml' 14 @{ nombreViejo = $true; renombradaA = 'otra.vieja-nueva' })
  )
  $s = Nueva-Salida 'f' (Estado-Base) ([ordered]@{ 'propiedades.json' = (Propiedades-Base $leg $mig) })
  $p2 = Pagina $s '2-problemas.html'
  $g = [regex]::Match($p2, '(?s)<section class="prob-grupo" aria-labelledby="g-propiedades">.*?</section>').Value
  Comprueba 'la pagina 2 tiene el area Propiedades' ($g.Length -gt 0) 'sin g-propiedades'
  $t = Texto-Plano $g
  Comprueba 'con su nombre y la etiqueta Medido' ($t -match 'Propiedades' -and $g -match 'et et-medido') $t
  Comprueba 'cuenta 2 errores (falta y renombrada-falta) y 3 avisos' ($t -match '2 errores, 3 avisos') $t
  $filas = @([regex]::Matches($g, '(?s)<li class="fila s-(\w+)">.*?</li>'))
  Igual 'cinco filas' 5 $filas.Count
  foreach ($c in @('recibos.ruta', 'recibos.cola', 'recibos.vieja', 'recibos.limite', 'otra.sobra')) { Comprueba "sale $c" ($g.Contains('<code class="d">' + $c + '</code>')) $g }
  foreach ($c in @('recibos.igual', 'recibos.variable', 'recibos.renombrada', 'otra.nueva', 'otra.vieja')) { Comprueba "no sale $c" (-not $g.Contains($c)) $g }
  $fila = { param($clave) @($filas | Where-Object { $_.Value.Contains('<code class="d">' + $clave + '</code>') })[0].Value }
  $f1 = Texto-Plano (& $fila 'recibos.ruta')
  Comprueba 'falta: estado en palabras y fichero:linea del original' ($f1 -match 'Falta en el migrado' -and $f1.Contains('En el original: src/main/resources/application.properties:4')) $f1
  $f2 = Texto-Plano (& $fila 'recibos.cola')
  Comprueba 'renombrada-falta: lleva el nombre nuevo' ($f2 -match 'Spring Boot 3 la renombra' -and $f2.Contains('Nombre nuevo: recibos.cola-nueva')) $f2
  $f3 = Texto-Plano (& $fila 'recibos.vieja')
  Comprueba 'ya-no-existe: dice que Spring Boot 3 ya no la tiene, con su fichero' ($f3 -match 'Spring Boot 3 ya no la tiene' -and $f3.Contains('application-pre.properties:2')) $f3
  $f4 = Texto-Plano (& $fila 'recibos.limite')
  Comprueba 'distinto: dice que el valor no es el del original' ($f4 -match 'El valor del migrado no es el del original') $f4
  $f5 = Texto-Plano (& $fila 'otra.sobra')
  Comprueba 'sin leer: del migrado, con su fichero' ($f5 -match 'Sobra' -and $f5.Contains('En el migrado: src/main/resources/application.yml:12')) $f5
  Comprueba 'primero los errores y luego los avisos' (($filas | ForEach-Object { $_.Groups[1].Value }) -join ',' -ceq 'error,error,aviso,aviso,aviso')
}

$Pruebas['c5 (f) pagina 2, Propiedades: un secreto no ensena su valor aunque el JSON lo traiga; todo va escapado; sin JSON el area no sale'] = {
  $leg = @(
    (Prop-Legacy 'recibos.clave-api' 'falta' 'src/main/resources/application.properties' 5 @{ secreto = $true; valorLegacy = 'sup3rS3creto-legacy'; valorMigrado = 'sup3rS3creto-migrado' })
    (Prop-Legacy 'recibos.usuario' 'distinto' 'src/main/resources/application.properties' 6 @{ valorLegacy = 'valorVisible1'; valorMigrado = 'valorVisible2' })
    (Prop-Legacy 'x<b>.y' 'falta' 'src/main/resources/a&b.properties' 7)
  )
  $mig = @((Prop-Migrado 'otra.password' $true 'src/main/resources/application.yml' 3 @{ secreto = $true; valor = 'sup3rS3creto-yml' }))
  $s = Nueva-Salida 'f-secreto' (Estado-Base) ([ordered]@{ 'propiedades.json' = (Propiedades-Base $leg $mig) })
  $p2 = Pagina $s '2-problemas.html'
  $g = [regex]::Match($p2, '(?s)<section class="prob-grupo" aria-labelledby="g-propiedades">.*?</section>').Value
  Comprueba 'el area sale' ($g.Length -gt 0)
  Comprueba 'ninguna pagina lleva el valor del secreto' (-not $p2.Contains('sup3rS3creto') -and -not (Pagina $s 'index.html').Contains('sup3rS3creto'))
  $t = Texto-Plano $g
  Comprueba 'el secreto dice que no se ensena su valor, en las dos filas' ((@([regex]::Matches($t, 'no se ense.a su valor')).Count) -eq 2) $t
  Comprueba 'la clave del secreto si sale' ($t.Contains('recibos.clave-api') -and $t.Contains('otra.password')) $t
  Comprueba 'los valores de una clave que no es secreta tampoco se ensenan' (-not $p2.Contains('valorVisible1') -and -not $p2.Contains('valorVisible2'))
  Comprueba 'la clave y el fichero se escapan' ($g.Contains('x&lt;b&gt;.y') -and $g.Contains('a&amp;b.properties:7'))
  # sin propiedades.json el area no sale y la pagina no nombra las propiedades
  $sin = Nueva-Salida 'f-sin' (Estado-Base)
  $p2 = Pagina $sin '2-problemas.html'
  Comprueba 'sin JSON no hay area Propiedades' ($p2 -notmatch 'g-propiedades' -and $p2 -notmatch 'Propiedades')
  # con todo igual: el area sale y lo dice
  $s = Nueva-Salida 'f-igual' (Estado-Base) ([ordered]@{ 'propiedades.json' = (Propiedades-Base @((Prop-Legacy 'a.b' 'igual')) @()) })
  $t = Texto-Plano ([regex]::Match((Pagina $s '2-problemas.html'), '(?s)<section class="prob-grupo" aria-labelledby="g-propiedades">.*?</section>').Value)
  Comprueba 'sin nada que decir, el area dice que no falta ninguna' ($t -match 'Ninguna clave') $t
  # renombres sin medir: lo dice
  $s = Nueva-Salida 'f-sin-renombres' (Estado-Base) ([ordered]@{ 'propiedades.json' = (Propiedades-Base @((Prop-Legacy 'a.b' 'falta')) @() 'no se pudo medir') })
  $t = Texto-Plano ([regex]::Match((Pagina $s '2-problemas.html'), '(?s)<section class="prob-grupo" aria-labelledby="g-propiedades">.*?</section>').Value)
  Comprueba 'si no se pudieron medir los renombres, lo dice' ($t -match 'No se pudo medir' -and $t -match 'Spring Boot 3') $t
}

# ================================ (g) PAGINA 4: JUNTADO CON TU RAMA ================================
$Pruebas['c5 (g) pagina 4 con hecho: Juntado con tu rama con lo mismo que la portada, sin la lista de entrega'] = {
  $repo = Repo-Cierre 'g-repo' 3
  $revisar = @([ordered]@{ hash = 'abc1234'; asunto = 'rescate(config): cambia la url' })
  $est = Estado-Base @{ migrado = $repo.Ruta; cierre = (Cierre-Hecho $repo @('limpieza: A.java:3 sobra') $revisar) }
  $s = Nueva-Salida 'g' $est (Datos-Pagina4)
  $p4 = Pagina $s '4-correcciones.html'
  $sec = Panel-De $p4 'juntado'
  Comprueba 'la pagina 4 tiene el panel Juntado con tu rama' ($sec.Length -gt 0 -and (Texto-Plano $sec).Contains('Juntado con tu rama')) $sec
  $t = Texto-Plano $sec
  Comprueba 'dice 3 commits, de antes a sha y cuando' ($t -match '3 commits' -and $t.Contains($repo.Antes.Substring(0, 7)) -and $t.Contains($repo.Sha.Substring(0, 7)) -and $t.Contains('21-11-2026 11:30')) $t
  Comprueba 'el comando para deshacerlo' ((Comando-De $sec) -ceq ('git -C "' + $repo.Ruta + '" reset --hard ' + $repo.Antes)) (Comando-De $sec)
  Comprueba 'los commits a revisar' ($t.Contains('abc1234 rescate(config): cambia la url')) $t
  Comprueba 'los avisos' ($t.Contains('limpieza: A.java:3 sobra')) $t
  Comprueba 'y no lleva la lista de entrega' ($p4 -notmatch 'Lista de entrega' -and $p4 -notmatch 'class="fila s-bien"')
  # lo mismo que la portada: el contenido del bloque coincide
  $ind = Texto-Plano (Panel-De (Pagina $s 'index.html') 'entrega')
  foreach ($frase in @('Cu.ndo|Se junt. el 21-11-2026 11:30', 'C.mo deshacerlo', 'Revisa antes del push', 'abc1234 rescate\(config\): cambia la url', 'limpieza: A\.java:3 sobra')) {
    Comprueba "la portada y la pagina 4 dicen lo mismo: $frase" ($t -match $frase -and $ind -match $frase) ($frase)
  }
}

$Pruebas['c5 (g) pagina 4 sin hecho: dice que todavia no se ha juntado y da el comando de -Cierre; ya no sale git merge'] = {
  $s = Nueva-Salida 'g-sin' (Estado-Base) (Datos-Pagina4)
  $p4 = Pagina $s '4-correcciones.html'
  $sec = Panel-De $p4 'juntado'
  Comprueba 'tiene el panel Juntado con tu rama' ($sec.Length -gt 0) 'sin id="juntado"'
  $t = Texto-Plano $sec
  Comprueba (Es 'dice que todav\u00eda no se ha juntado') ($t -match 'no se ha juntado' -and $t -match (Es 'Todav\u00eda')) $t
  Igual 'y da el comando de -Cierre' $ComandoCierre (Comando-De $sec)
  Comprueba 'sin deshacer ni commits a revisar' ($t -notmatch 'Revisa antes del push' -and $t -notmatch (Es 'C\u00f3mo deshacerlo')) $t
  # Donde esta el codigo: -Cierre en vez de git merge
  $cod = Panel-De $p4 'codigo'
  $cmd = Comando-De $cod
  Comprueba 'Donde esta el codigo ya no dice git merge' ($cmd -notmatch 'merge' -and $p4 -notmatch 'git -C [^<]*merge') $cmd
  Comprueba 'y trae el comando de -Cierre' ($cmd.Contains($ComandoCierre)) $cmd
  Comprueba 'dejando el diff y el worktree remove' ($cmd.Contains('diff --stat feat/recibos...rescate/feat-recibos-20261121-0900') -and $cmd.Contains('worktree remove "C:\ruta\migrado-rescate"')) $cmd
  # con hecho tambien
  $repo = Repo-Cierre 'g-sin-repo' 1
  $s = Nueva-Salida 'g-hecho' (Estado-Base @{ migrado = $repo.Ruta; cierre = (Cierre-Hecho $repo) }) (Datos-Pagina4)
  $cmd = Comando-De (Panel-De (Pagina $s '4-correcciones.html') 'codigo')
  Comprueba 'con hecho, Donde esta el codigo tampoco dice git merge' ($cmd -notmatch 'merge') $cmd
}

# ================================ (i) LOS TEXTOS QUE MANDABAN A JUNTAR A MANO ================================
$Pruebas['c5 (i) el README, rescate.ps1 y comun.ps1 ya no mandan a juntar con git merge, y dicen -Cierre'] = {
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  $readme = [System.IO.File]::ReadAllText((Join-Path $raiz 'README.md'), $utf8)
  $bloque = [regex]::Match($readme, '(?s)# 4\) Al acabar.*?```').Value
  Comprueba 'el README tiene el paso 4 Al acabar' ($bloque.Length -gt 0)
  Comprueba 'el paso 4 del README no dice git merge' ($bloque -notmatch 'merge') $bloque
  Comprueba 'y dice -Cierre' ($bloque -match '-Cierre') $bloque
  Comprueba 'el README dice que -Cierre junta por fast-forward, despues de las puertas' ($readme -match (Es '-Cierre` junta[^\n]*fast-forward[^\n]*despu\u00e9s de las puertas')) 'sin la linea'
  Comprueba 'y como deshacerlo' ($readme -match (Es '-Cierre`[^\n]*deshacer')) 'sin deshacer'
  $resc = @([System.IO.File]::ReadAllLines((Join-Path $raiz 'rescate.ps1'), $utf8) | Select-Object -First 130)
  Comprueba 'la cabecera de rescate.ps1 no dice git merge' (@($resc | Where-Object { $_ -match 'git -C .* merge ' }).Count -eq 0) (($resc | Where-Object { $_ -match 'merge' }) -join ' / ')
  Comprueba 'y dice -Cierre' (@($resc | Where-Object { $_ -match '^\s+\.\\migracion\.ps1 .* -Cierre' }).Count -eq 1) 'sin la linea de -Cierre'
  $comun = @([System.IO.File]::ReadAllLines((Join-Path $raiz 'comun.ps1'), $utf8) | Where-Object { $_ -match 'Unirla a tu rama' })
  Igual 'comun.ps1 tiene una linea Unirla a tu rama' 1 $comun.Count
  Comprueba 'que no dice git merge' ($comun[0] -notmatch 'merge') $comun[0]
  Comprueba 'y dice -Cierre' ($comun[0] -match '-Cierre') $comun[0]
}

# ================================ (j) C5a-ARREGLOS ================================
$Pruebas['c5 (j) Get-FallosPruebaLocal tiene una sola definicion, en informe.ps1: migracion.ps1 la llama y la fila Prueba en local tambien'] = {
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  $inf = [System.IO.File]::ReadAllText((Join-Path $raiz 'informe.ps1'), $utf8)
  $mig = [System.IO.File]::ReadAllText((Join-Path $raiz 'migracion.ps1'), $utf8)
  Igual 'informe.ps1 la define' 1 ([regex]::Matches($inf, '(?m)^function Get-FallosPruebaLocal\b').Count)
  Igual 'migracion.ps1 ya no la define' 0 ([regex]::Matches($mig, '(?m)^function Get-FallosPruebaLocal\b').Count)
  Comprueba 'migracion.ps1 la sigue llamando (el cierre)' ($mig -match 'Get-FallosPruebaLocal \$') 'sin llamada'
  $fila = [regex]::Match($inf, '(?s)function Get-FilaEntregaLocal\b.*?\r?\n}\r?\n').Value
  Comprueba 'la fila Prueba en local la llama en vez de repetir el bucle de los jobs' ($fila -match 'Get-FallosPruebaLocal' -and $fila -notmatch 'foreach') $fila
}

$Pruebas['c5 (j) Get-FallosPruebaLocal: los arneses sin hacer, el job sin caso igual (o sin fila) y el job con casos distintos; sin datos, una frase'] = {
  $mapa = Mapa-Base @('cargaJob', 'resumenJob', 'avisoJob', 'sinFilaJob')
  $local = Local-Base ([ordered]@{ cargaJob = @(2, 0); resumenJob = @(0, 0); avisoJob = @(1, 2) }) ([ordered]@{ original = 'hecha'; migrado = 'pendiente' })
  $l = (ConvertTo-Json -InputObject $local -Depth 8) | ConvertFrom-Json
  $m = (ConvertTo-Json -InputObject $mapa -Depth 8) | ConvertFrom-Json
  $f = @(Get-FallosPruebaLocal $l $m)
  Igual 'cuatro fallos' 4 $f.Count
  Igual 'el arnes del migrado' 'el arnes del migrado no esta hecho' $f[0]
  Igual 'resumenJob sin caso igual' 'el job resumenJob no tiene ningun caso igual' $f[1]
  Igual 'avisoJob con dos distintos' 'el job avisoJob tiene 2 casos distintos' $f[2]
  Igual 'un job sin fila en prueba-local.json cuenta como sin caso igual' 'el job sinFilaJob no tiene ningun caso igual' $f[3]
  Igual 'sin el JSON, una sola frase que lo nombra' 1 @(Get-FallosPruebaLocal $null $m).Count
  Comprueba 'y dice prueba-local.json' ((@(Get-FallosPruebaLocal $null $m)[0]) -match 'prueba-local\.json')
  $bien = (ConvertTo-Json -InputObject (Local-Base ([ordered]@{ cargaJob = @(2, 0) })) -Depth 8) | ConvertFrom-Json
  $mapa1 = (ConvertTo-Json -InputObject (Mapa-Base @('cargaJob')) -Depth 8) | ConvertFrom-Json
  Igual 'con los dos arneses hechos y el job igual, nada' 0 @(Get-FallosPruebaLocal $bien $mapa1).Count
}

$Pruebas['c5 (j) fila Prueba en local: un arnes sin hacer con todos los jobs iguales da revisar; un job sin fila en prueba-local.json tambien, y lo nombra'] = {
  $repo = Repo-Cierre 'j-local-repo' 1
  $est = Estado-Base @{ migrado = $repo.Ruta; cierre = (Cierre-Hecho $repo) }
  $iguales = [ordered]@{ cargaJob = @(2, 0); resumenJob = @(1, 0) }
  $s = Nueva-Salida 'j-arnes' $est ([ordered]@{ 'correcciones.json' = (Correccion-Base 1); 'mapa.json' = (Mapa-Base @('cargaJob', 'resumenJob')); 'prueba-local.json' = (Local-Base $iguales ([ordered]@{ original = 'hecha'; migrado = 'pendiente' })) })
  $f = Fila-De @(Get-ListaEntrega (Read-DatosInforme $s)) 'prueba-local'
  Igual 'un arnes sin hacer: revisar' 'revisar' $f.Estado
  Igual 'con un fallo, de 2 jobs' '1 2' ($f.Valores.N + ' ' + $f.Valores.M)
  Igual 'y su texto' 'el arnes del migrado no esta hecho' $f.Valores.TEXTOS
  $t = Texto-Plano (Panel-De (Pagina $s 'index.html') 'entrega')
  Comprueba 'la portada lo dice' ($t.Contains('el arnes del migrado no esta hecho')) $t
  $filas = @([regex]::Matches((Panel-De (Pagina $s 'index.html') 'entrega'), '(?s)<li class="fila s-(\w+)">') | ForEach-Object { $_.Groups[1].Value })
  Igual 'y es la primera fila de la portada, en revisar' 'revisar' $filas[0]
  $s = Nueva-Salida 'j-arneses' $est ([ordered]@{ 'correcciones.json' = (Correccion-Base 1); 'mapa.json' = (Mapa-Base @('cargaJob', 'resumenJob')); 'prueba-local.json' = (Local-Base $iguales ([ordered]@{ original = 'pendiente'; migrado = 'pendiente' })) })
  $f = Fila-De @(Get-ListaEntrega (Read-DatosInforme $s)) 'prueba-local'
  Igual 'los dos arneses sin hacer: dos fallos, uno por arnes' 'revisar 2 el arnes del original no esta hecho; el arnes del migrado no esta hecho' ($f.Estado + ' ' + $f.Valores.N + ' ' + $f.Valores.TEXTOS)
  $s = Nueva-Salida 'j-sin-fila' $est ([ordered]@{ 'correcciones.json' = (Correccion-Base 1); 'mapa.json' = (Mapa-Base @('cargaJob', 'resumenJob', 'avisoJob')); 'prueba-local.json' = (Local-Base $iguales) })
  $f = Fila-De @(Get-ListaEntrega (Read-DatosInforme $s)) 'prueba-local'
  Igual 'un job de mapa.json sin fila en prueba-local.json: revisar' 'revisar' $f.Estado
  Igual 'con un fallo, de 3 jobs, que nombra al job' '1 3 el job avisoJob no tiene ningun caso igual' ($f.Valores.N + ' ' + $f.Valores.M + ' ' + $f.Valores.TEXTOS)
  Comprueba 'la portada nombra al job' ((Texto-Plano (Panel-De (Pagina $s 'index.html') 'entrega')).Contains('el job avisoJob no tiene ningun caso igual'))
  $s = Nueva-Salida 'j-todo-bien' $est ([ordered]@{ 'correcciones.json' = (Correccion-Base 1); 'mapa.json' = (Mapa-Base @('cargaJob', 'resumenJob')); 'prueba-local.json' = (Local-Base $iguales) })
  $f = Fila-De @(Get-ListaEntrega (Read-DatosInforme $s)) 'prueba-local'
  Igual 'con los dos arneses hechos y todos los jobs iguales: bien' 'bien' $f.Estado
  Igual 'sin textos de fallo' '' $f.Valores.TEXTOS
}

$Pruebas['c5 (j) fila Propiedades con los renombres sin medir: sigue en bien o en revisar y su frase anade sin medir los renombres de Spring Boot 3; con los renombres medidos no'] = {
  $repo = Repo-Cierre 'j-prop-repo' 1
  $est = Estado-Base @{ migrado = $repo.Ruta; cierre = (Cierre-Hecho $repo) }
  $base = [ordered]@{ 'correcciones.json' = (Correccion-Base 1); 'mapa.json' = (Mapa-Base @('cargaJob')); 'prueba-local.json' = (Local-Base ([ordered]@{ cargaJob = @(2, 0) })) }
  $casos = @(
    @('sin-medir-bien', 'igual', 'no se pudo medir', 'bien', $true),
    @('sin-medir-revisar', 'falta', 'no se pudo medir', 'revisar', $true),
    @('medidos-bien', 'igual', 'ok', 'bien', $false),
    @('medidos-revisar', 'falta', 'ok', 'revisar', $false)
  )
  foreach ($c in $casos) {
    $datos = [ordered]@{}
    foreach ($k in $base.Keys) { $datos[$k] = $base[$k] }
    $datos['propiedades.json'] = (Propiedades-Base @((Prop-Legacy 'a.uno' $c[1])) @() $c[2])
    $s = Nueva-Salida ('j-prop-' + $c[0]) $est $datos
    $f = Fila-De @(Get-ListaEntrega (Read-DatosInforme $s)) 'propiedades'
    Igual ($c[0] + ': el estado de siempre') $c[3] $f.Estado
    $fila = [regex]::Match((Panel-De (Pagina $s 'index.html') 'entrega'), '(?s)<li class="fila s-\w+">(?:(?!</li>).)*Propiedades(?:(?!</li>).)*</li>').Value
    Comprueba ($c[0] + ': esta la fila de Propiedades') ($fila.Length -gt 0) (Panel-De (Pagina $s 'index.html') 'entrega')
    $t = Texto-Plano $fila
    Igual ($c[0] + ': dice sin medir los renombres de Spring Boot 3') $c[4] ($t -match 'sin medir los renombres de Spring Boot 3')
  }
}

$Pruebas['c5 (j) comun.ps1: el aviso de una rama de rescate sin unir da dos caminos, cada uno en su linea: -Cierre si vienes de migracion.ps1, git merge si no'] = {
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  $l = @([System.IO.File]::ReadAllLines((Join-Path $raiz 'comun.ps1'), $utf8))
  $i = @(0..($l.Count - 1) | Where-Object { $l[$_] -match 'Unirla a tu rama' })
  Igual 'una linea Unirla a tu rama' 1 $i.Count
  Comprueba 'la primera es el camino de migracion.ps1: lleva -Cierre y no git merge' ($l[$i[0]] -match '^\s*Info ' -and $l[$i[0]] -match 'migracion\.ps1' -and $l[$i[0]] -match '-Cierre' -and $l[$i[0]] -notmatch 'merge') $l[$i[0]]
  Comprueba 'la siguiente es el otro camino: otra linea Info con git -C ... merge y sin -Cierre' ($l[$i[0] + 1] -match '^\s*Info ' -and $l[$i[0] + 1] -match 'git -C .* merge ' -and $l[$i[0] + 1] -notmatch '-Cierre') $l[$i[0] + 1]
}

$Pruebas['c5 (j) con cierre.hecho de una pasada anterior, una pasada nueva que corre, para o falla sigue diciendo su paso y su comando, no Ya esta en tu rama'] = {
  $repo = Repo-Cierre 'j-nueva-repo' 1
  $cierre = Cierre-Hecho $repo
  $comando = $ComandoPasada.Replace('C:\ruta\migrado', $repo.Ruta)
  $parada = [ordered]@{ motivo = 'git'; detalle = 'd'; registro = 'r'; ayuda = 'a' }
  $localFallo = [ordered]@{ resultado = 'fallo'; codigo = 1; minutos = 1.5; detalle = 'dos / tres'; registro = 'registros/prueba-local.log' }
  $tabla = @(
    @('corriendo', @{ fin = '' }, ($comando + ' -Si')),
    @('parada', @{ parada = $parada }, ($comando + ' -Si')),
    @('local-fallo', @{ pruebaLocal = $localFallo }, ($comando + ' -Si'))
  )
  foreach ($f in $tabla) {
    $est = Estado-Base @{ migrado = $repo.Ruta; cierre = $cierre }
    foreach ($k in $f[1].Keys) { $est[$k] = $f[1][$k] }
    $s = Nueva-Salida ('j-nueva-' + $f[0]) $est ([ordered]@{ 'correcciones.json' = (Correccion-Base 1); 'mapa.json' = (Mapa-Base @('cargaJob')); 'prueba-local.json' = (Local-Base ([ordered]@{ cargaJob = @(2, 0) })) })
    $paso = Paso-De $s
    Igual ($f[0] + ': su Caso, no el de juntado') $f[0] $paso.Caso
    Comprueba ($f[0] + ': no es un juntado') (-not $paso.Juntado)
    Igual ($f[0] + ': su comando') $f[2] $paso.Comando
    $sp = Panel-De (Pagina $s 'index.html') 'siguiente-paso'
    Comprueba ($f[0] + ': la portada no dice Ya esta en tu rama') ((Texto-Plano $sp) -notmatch 'Ya est. en tu rama') (Texto-Plano $sp)
    Igual ($f[0] + ': la portada lleva su comando') $f[2] ((Comando-De $sp).Trim())
  }
}

# ================================ C5b: LA REVISION POR FLUJOS Y LAS PROPIEDADES AL YML EN EL INFORME ================================
# La pagina 2 con la revision por flujos (datos\revision.json de revision.ps1), la pagina 4 con las claves que la fase propiedades puso en el yml
# (datos\propiedades-arreglo.json de arreglo-propiedades.ps1), las dos fases en la portada y -RevisarTodo en el comando de la pasada.
$TxtRevision = Es 'Revisi\u00f3n por flujos'
$TxtNada = Es 'La revisi\u00f3n no ha encontrado nada en'
$TxtTodo = (Es 'revisado todo el c\u00f3digo') + ' \(\s*-RevisarTodo\s*\)'

# La pagina sin el CSS, en SHA-256: lo que mide que una pagina es la de antes (medidas con el codigo de antes de C5b, 3050737).
function Hash-Sin-Css([string]$Html) {
  $sin = [regex]::Replace($Html, '(?s)<style>.*?</style>', '')
  $sha = [System.Security.Cryptography.SHA256]::Create()
  return ([System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($sin))) -replace '-', '')
}

function Hallazgo-Base([string]$Regla, [string]$Titulo, [string]$Fichero, [int]$Linea, [string]$Cita, [string]$Texto) {
  return [ordered]@{ regla = $Regla; titulo = $Titulo; fichero = $Fichero; linea = $Linea; cita = $Cita; texto = $Texto; unidad = 'step-cargaJob'; probado = $true }
}

# Dos reglas y tres hallazgos: dos de la primera y uno de la segunda. La cita del primero lleva < y &.
$C5bHallazgos = @(
  (Hallazgo-Base 'SB-LISTENER' 'Listener que nadie registra' 'src/main/java/com/acme/recibos/listener/RecibosListener.java' 14 'if (total < 0 && saldo > 0) { aviso(); }' 'RecibosListener no se registra en ningun step.')
  (Hallazgo-Base 'SB-LISTENER' 'Listener que nadie registra' 'src/main/java/com/acme/recibos/listener/AuditoriaListener.java' 22 '@AfterStep' 'Nadie registra AuditoriaListener.')
  (Hallazgo-Base 'SB-STEPSCOPE' '@StepScope que devuelve la interfaz' 'src/main/java/com/acme/recibos/config/CargaConfig.java' 41 'public ItemReader<Recibo> reader() {' 'El reader devuelve la interfaz y es un ItemStream.')
)

# revision.json de juguete: la forma de Save-Revision (revision.ps1), con tres reglas (la tercera sin hallazgos). $Cambios lo pisa campo a campo.
function Revision-Base($Hallazgos = @(), [hashtable]$Cambios = @{}) {
  $r = [ordered]@{
    commit = 'abc1234def56'; todo = $false; unidades = 4; hechas = 4; atascadas = 0
    reglas = @([ordered]@{ id = 'SB-LISTENER'; titulo = 'Listener que nadie registra' }, [ordered]@{ id = 'SB-STEPSCOPE'; titulo = '@StepScope que devuelve la interfaz' }, [ordered]@{ id = 'SB-CONTEXTO'; titulo = 'Objeto no serializable en el ExecutionContext' })
    hallazgos = @($Hallazgos); descartados = 2
  }
  foreach ($k in $Cambios.Keys) { $r[$k] = $Cambios[$k] }
  return $r
}

# propiedades-arreglo.json de juguete: la forma de Save-ResultadoPropiedades (arreglo-propiedades.ps1): hecha con dos claves y una que no aplica.
function Arreglo-Base([hashtable]$Cambios = @{}) {
  $r = [ordered]@{
    estado = 'hecha'; commit = '9f8e7d6c5b4a'; pedidas = 3
    anadidas = @([ordered]@{ clave = 'recibos.ruta'; fichero = 'src/main/resources/application.yml' }, [ordered]@{ clave = 'recibos.cola'; fichero = 'src/main/resources/application-pre.yml' })
    noAplica = @([ordered]@{ clave = 'recibos.vieja'; motivo = 'Spring Boot 3 ya no la lee' }); motivo = ''; huella = 'h1'
  }
  foreach ($k in $Cambios.Keys) { $r[$k] = $Cambios[$k] }
  return $r
}

# Una salida con corregir y las paginas completas (la de Datos-Pagina4) y el area Propiedades de la pagina 2; $Extra suma o pisa ficheros de datos\ y $Cambios, el estado.
function C5b-Salida([string]$Nombre, $Extra = @{}, [hashtable]$Cambios = @{}) {
  $datos = Datos-Pagina4
  $datos['propiedades.json'] = (Propiedades-Base @((Prop-Legacy 'recibos.ruta' 'falta' 'src/main/resources/application.properties' 4)))
  foreach ($k in $Extra.Keys) { $datos[$k] = $Extra[$k] }
  return (Nueva-Salida $Nombre (Estado-Base $Cambios) $datos)
}

# Las lineas de fase de la portada: nombre, estado (data-e) y cuenta, en texto plano.
function Lineas-Fase([string]$Html) {
  return @([regex]::Matches($Html, '(?s)<li><span class="fase-n">(.*?)</span><span class="fase-e" data-e="(\w+)">.*?</span><span class="fase-c">(.*?)</span></li>') |
      ForEach-Object { [pscustomobject]@{ Nombre = (Texto-Plano $_.Groups[1].Value); E = $_.Groups[2].Value; Cuenta = (Texto-Plano $_.Groups[3].Value) } })
}

function Fase-De($Lineas, [string]$Nombre) { return @($Lineas | Where-Object { $_.Nombre -ceq $Nombre })[0] }

# El orden de Get-OrdenFases de una salida montada, en una sola linea.
function Orden-De([string]$Salida) { return ((Get-OrdenFases (Read-DatosInforme $Salida)) -join ' ') }

$OrdenLectura = 'diagnostico fichas-clase mapa lanzadores fichas-job resumen pruebas-pre casos-pre'
$JsonPracticas = [ordered]@{ pasados = 1; atascados = 0; sinCambios = 0 }
$JsonReglas = [ordered]@{ conTest = 2; reglasVigiladas = 3; atascadas = 0; saltadas = 0 }

# ================================ (a) LA REVISION EN LA PAGINA 2 ================================
$Pruebas['c5b (a) revision.json con 2 reglas y 3 hallazgos: la pagina 2 tiene la seccion con su etiqueta y sus cuentas, un grupo por regla y una fila por hallazgo con fichero:linea y la cita escapada'] = {
  $s = C5b-Salida 'c5b-a' ([ordered]@{ 'revision.json' = (Revision-Base $C5bHallazgos) })
  $p2 = Pagina $s '2-problemas.html'
  $sec = Panel-De $p2 'revision'
  Comprueba 'hay una seccion Revision por flujos' ($sec.Length -gt 0 -and (Texto-Plano $sec).Contains($TxtRevision)) $sec
  Comprueba 'con la etiqueta Leido por la IA, con prueba' ($sec -match 'et et-ia' -and (Texto-Plano $sec) -match (Es 'Le.do por la IA, con prueba')) $sec
  foreach ($c in @(@('4', 'unidades'), @('4', 'hechas'), @('0', 'atascadas'), @('3', 'hallazgos'), @('2', 'descartados'))) {
    Comprueba ('la cuenta ' + $c[1] + ' vale ' + $c[0]) ($sec -match ('<p[^>]*><b>' + $c[0] + '</b>' + $c[1] + '</p>')) $sec
  }
  Comprueba 'sin -RevisarTodo no lo dice' ((Texto-Plano $sec) -notmatch 'RevisarTodo') (Texto-Plano $sec)
  Comprueba 'con 0 atascadas la cifra no va en rojo (sin cif-mal)' ($sec -notmatch 'cif-mal') $sec
  $grupos = @([regex]::Matches($p2, '(?s)<section class="prob-grupo" aria-labelledby="g-revision-[^"]+">.*?</section>') | ForEach-Object { $_.Value })
  Igual 'dos grupos, uno por cada regla con hallazgos (la tercera, sin ninguno, no sale)' 2 $grupos.Count
  if ($grupos.Count -ne 2) { return }
  $g1 = Texto-Plano $grupos[0]
  $g2 = Texto-Plano $grupos[1]
  Comprueba 'el primero lleva el titulo de la primera regla y 2 hallazgos' ($g1.Contains('Listener que nadie registra') -and $g1.Contains('2 hallazgos')) $g1
  Comprueba 'el segundo, el de la segunda y 1 hallazgo' ($g2.Contains((Es '@StepScope que devuelve la interfaz')) -and $g2.Contains('1 hallazgo') -and -not $g2.Contains('1 hallazgos')) $g2
  Comprueba 'los dos con la etiqueta Leido por la IA' ($grupos[0] -match 'et et-ia' -and $grupos[1] -match 'et et-ia')
  Igual 'dos filas en el primero' 2 @([regex]::Matches($grupos[0], '<li class="fila')).Count
  Igual 'una fila en el segundo' 1 @([regex]::Matches($grupos[1], '<li class="fila')).Count
  Comprueba 'cada fila lleva su fichero:linea' ($grupos[0].Contains('<code class="d">src/main/java/com/acme/recibos/listener/RecibosListener.java:14</code>') -and $grupos[0].Contains('AuditoriaListener.java:22</code>') -and $grupos[1].Contains('CargaConfig.java:41</code>')) ($grupos -join ' // ')
  Comprueba 'y el problema' ($g1.Contains('RecibosListener no se registra en ningun step.') -and $g2.Contains('El reader devuelve la interfaz')) $g1
  Comprueba 'la cita sale escapada: < y & no van sueltos' ($grupos[0].Contains('if (total &lt; 0 &amp;&amp; saldo &gt; 0)') -and $grupos[1].Contains('ItemReader&lt;Recibo&gt;') -and $p2 -notmatch 'total < 0' -and $p2 -notmatch '&& saldo') $grupos[0]
  Comprueba 'y la cita se lee entera en el texto de la pagina' ($g1.Contains('if (total < 0 && saldo > 0) { aviso(); }')) $g1
  Comprueba 'va despues del area Propiedades' ($p2.IndexOf('id="revision"') -gt $p2.IndexOf('aria-labelledby="g-propiedades"') -and $p2.IndexOf('aria-labelledby="g-propiedades"') -gt 0)
}

$Pruebas['c5b (a) con todo = true dice revisado todo el codigo (-RevisarTodo); con atascadas dice cuantas son y que se relanza con -Reintentar'] = {
  $s = C5b-Salida 'c5b-a-todo' ([ordered]@{ 'revision.json' = (Revision-Base $C5bHallazgos @{ todo = $true; unidades = 5; hechas = 3; atascadas = 2 }) })
  $sec = Panel-De (Pagina $s '2-problemas.html') 'revision'
  $t = Texto-Plano $sec
  Comprueba 'con todo: dice revisado todo el codigo (-RevisarTodo)' ($t -match $TxtTodo) $t
  Comprueba 'las cuentas: 5 unidades, 3 hechas y 2 atascadas' ($sec -match '<b>5</b>unidades' -and $sec -match '<b>3</b>hechas' -and $sec -match '<b>2</b>atascadas') $sec
  Comprueba 'con atascadas > 0 la cifra de atascadas va en rojo (cif-mal) y las demas no' ($sec -match '<p class="cif-mal"><b>2</b>atascadas</p>' -and ([regex]::Matches($sec, 'cif-mal')).Count -eq 1) $sec
  Comprueba 'dice que hay 2 unidades atascadas y que se vuelven a intentar relanzando con -Reintentar' ($t -match 'Unidades atascadas: 2' -and $t.Contains('relanza el mismo comando con -Reintentar')) $t
  $s0 = C5b-Salida 'c5b-a-sin-atascos' ([ordered]@{ 'revision.json' = (Revision-Base $C5bHallazgos) })
  Comprueba 'sin atascadas no hay aviso de relanzar' ((Texto-Plano (Panel-De (Pagina $s0 '2-problemas.html') 'revision')) -notmatch 'Reintentar')
}

# ================================ (b) 0 HALLAZGOS Y SIN JSON ================================
$Pruebas['c5b (b) revision.json con 0 hallazgos: la linea no ha encontrado nada en N unidades y ningun grupo'] = {
  $s = C5b-Salida 'c5b-b-cero' ([ordered]@{ 'revision.json' = (Revision-Base @() @{ unidades = 6; hechas = 6; descartados = 0 }) })
  $p2 = Pagina $s '2-problemas.html'
  $sec = Panel-De $p2 'revision'
  $t = Texto-Plano $sec
  Comprueba 'la seccion esta' ($sec.Length -gt 0 -and $t.Contains($TxtRevision)) $sec
  Comprueba 'dice que la revision no ha encontrado nada en 6 unidades' ($t.Contains($TxtNada + ' 6 unidades')) $t
  Comprueba 'las cuentas dicen 0 hallazgos' ($sec -match '<b>0</b>hallazgos') $sec
  Igual 'no hay ningun grupo de regla' 0 @([regex]::Matches($p2, 'aria-labelledby="g-revision-')).Count
  $con = C5b-Salida 'c5b-b-con' ([ordered]@{ 'revision.json' = (Revision-Base $C5bHallazgos) })
  Comprueba 'con hallazgos no sale esa linea' ((Texto-Plano (Panel-De (Pagina $con '2-problemas.html') 'revision')) -notmatch 'no ha encontrado nada')
  $una = C5b-Salida 'c5b-b-una' ([ordered]@{ 'revision.json' = (Revision-Base @() @{ unidades = 1; hechas = 1; descartados = 0 }) })
  $tu = Texto-Plano (Panel-De (Pagina $una '2-problemas.html') 'revision')
  Comprueba 'con 1 unidad lo dice en singular' ($tu.Contains($TxtNada + ' 1 unidad.')) $tu
  $atasc = C5b-Salida 'c5b-b-atasc' ([ordered]@{ 'revision.json' = (Revision-Base @() @{ unidades = 5; hechas = 3; atascadas = 2; descartados = 0 }) })
  Comprueba 'con atascadas la linea cuenta las unidades hechas (3), no las 5' ((Texto-Plano (Panel-De (Pagina $atasc '2-problemas.html') 'revision')).Contains($TxtNada + ' 3 unidades')) 
}

$Pruebas['c5b (b) un hallazgo de una regla que revision.json no lista en reglas sale igual, con su titulo (o con su id si no lo trae)'] = {
  $raros = @((Hallazgo-Base 'SB-OTRA' 'Regla que no esta en la lista' 'src/main/java/com/acme/recibos/Otra.java' 7 'new Otra()' 'Algo raro.'), (Hallazgo-Base 'SB-SINTITULO' '' 'src/main/java/com/acme/recibos/Sin.java' 0 'x' 'Sin titulo ni linea.'))
  $s = C5b-Salida 'c5b-b-raros' ([ordered]@{ 'revision.json' = (Revision-Base $raros) })
  $p2 = Pagina $s '2-problemas.html'
  $t = Texto-Plano (Panel-De $p2 'revision')
  Comprueba 'las cuentas dicen 2 hallazgos' ($p2 -match '<b>2</b>hallazgos')
  Comprueba 'sale el grupo de la regla desconocida, con el titulo del hallazgo y su fichero:linea' ($p2 -match 'aria-labelledby="g-revision-SB-OTRA"' -and $p2.Contains('Regla que no esta en la lista') -and $p2.Contains('<code class="d">src/main/java/com/acme/recibos/Otra.java:7</code>'))
  Comprueba 'y el que no trae titulo, con su id y el fichero sin linea' ($p2 -match '<h2 id="g-revision-SB-SINTITULO">SB-SINTITULO</h2>' -and $p2.Contains('<code class="d">src/main/java/com/acme/recibos/Sin.java</code>'))
}

# Las tres paginas de C5b-Salida sin revision.json ni propiedades-arreglo.json, medidas con el codigo de antes de C5b (3050737).
$C5bHashIndice = 'DCD30B277DE55E398966347AE0F44BA473A64FCF9EC0D92F9DAAB244A196BA1A'
$C5bHashProblemas = '643A626C3B5EF7DC5FA4855E1E466819EE22DA2B180B24234E8A836E489AC875'
$C5bHashCorrecciones = '14FF13619A491D1583D531FA867711841977341860702DD0F4725FCF8EB0637F'

$Pruebas['c5b (b) sin revision.json ni propiedades-arreglo.json la portada y las paginas 2 y 4 son las de antes, byte a byte (SHA-256 sin el CSS); un JSON roto tampoco cambia nada'] = {
  $s = C5b-Salida 'c5b-b-sin'
  $h = [ordered]@{ 'index.html' = $C5bHashIndice; '2-problemas.html' = $C5bHashProblemas; '4-correcciones.html' = $C5bHashCorrecciones }
  foreach ($p in $h.Keys) {
    $real = Hash-Sin-Css (Pagina $s $p)
    if ($h[$p] -ceq 'PENDIENTE') { Write-Host "  HASH $p $real" }
    Igual ($p + ': el mismo SHA-256 que antes del cambio') $h[$p] $real
  }
  $i = Pagina $s 'index.html'
  Comprueba 'y no nombra ni las fases ni los JSON' ($i -notmatch 'Propiedades al yml' -and -not $i.Contains($TxtRevision) -and -not $i.Contains('revision.json') -and -not $i.Contains('propiedades-arreglo.json'))
  $roto = C5b-Salida 'c5b-b-roto' ([ordered]@{ 'revision.json' = '{ esto no es json'; 'propiedades-arreglo.json' = '[[' })
  foreach ($p in @('2-problemas.html', '4-correcciones.html')) { Igual ($p + ' con los dos JSON rotos: la de antes') $h[$p] (Hash-Sin-Css (Pagina $roto $p)) }
  $fases = (Lineas-Fase $i | ForEach-Object { $_.Nombre + '=' + $_.E + '=' + $_.Cuenta }) -join ' / '
  Igual 'la portada con los dos JSON rotos: las mismas fases con las mismas cuentas (los dos ficheros si salen en la lista de ficheros: existen)' $fases ((Lineas-Fase (Pagina $roto 'index.html') | ForEach-Object { $_.Nombre + '=' + $_.E + '=' + $_.Cuenta }) -join ' / ')
}

# ================================ (c) EL ORDEN DE LAS FASES ================================
$Pruebas['c5b (c) Get-OrdenFases con corregir y los dos JSON: ... reglas, propiedades, revision, prueba-local, hecha; sin ellos, el orden de siempre; con parar, ni propiedades ni revision'] = {
  $dos = [ordered]@{ 'revision.json' = (Revision-Base $C5bHallazgos); 'propiedades-arreglo.json' = (Arreglo-Base) }
  $todo = [ordered]@{ 'revision.json' = (Revision-Base $C5bHallazgos); 'propiedades-arreglo.json' = (Arreglo-Base); 'practicas-arreglos.json' = $JsonPracticas; 'tests-reglas.json' = $JsonReglas }
  Igual 'con practicas, reglas y los dos JSON' "$OrdenLectura lectura-hecha correccion comparar practicas reglas propiedades revision prueba-local hecha" (Orden-De (C5b-Salida 'c5b-c-todo' $todo))
  Igual 'con los dos JSON' "$OrdenLectura lectura-hecha correccion comparar propiedades revision prueba-local hecha" (Orden-De (C5b-Salida 'c5b-c-dos' $dos))
  Igual 'sin ellos, el orden de siempre' "$OrdenLectura lectura-hecha correccion comparar prueba-local hecha" (Orden-De (C5b-Salida 'c5b-c-sin'))
  Igual 'sin ellos pero con practicas y reglas, el de siempre' "$OrdenLectura lectura-hecha correccion comparar practicas reglas prueba-local hecha" (Orden-De (C5b-Salida 'c5b-c-pr' ([ordered]@{ 'practicas-arreglos.json' = $JsonPracticas; 'tests-reglas.json' = $JsonReglas })))
  Igual 'solo propiedades-arreglo.json: sale propiedades' "$OrdenLectura lectura-hecha correccion comparar propiedades prueba-local hecha" (Orden-De (C5b-Salida 'c5b-c-prop' ([ordered]@{ 'propiedades-arreglo.json' = (Arreglo-Base) })))
  Igual 'solo revision.json: sale revision' "$OrdenLectura lectura-hecha correccion comparar revision prueba-local hecha" (Orden-De (C5b-Salida 'c5b-c-rev' ([ordered]@{ 'revision.json' = (Revision-Base) })))
  Igual 'con parar y los dos JSON: el orden de parar, sin las dos fases' "$OrdenLectura comparar lectura-hecha correccion prueba-local hecha" (Orden-De (C5b-Salida 'c5b-c-parar' $dos @{ respuesta = 'parar' }))
  Igual 'la pasada en la fase revision, sin su JSON: sale revision y no propiedades' "$OrdenLectura lectura-hecha correccion comparar revision prueba-local hecha" (Orden-De (C5b-Salida 'c5b-c-en-rev' ([ordered]@{}) @{ fase = 'revision'; fin = '' }))
  Igual 'la pasada en la fase propiedades, sin su JSON: sale propiedades y no revision' "$OrdenLectura lectura-hecha correccion comparar propiedades prueba-local hecha" (Orden-De (C5b-Salida 'c5b-c-en-prop' ([ordered]@{}) @{ fase = 'propiedades'; fin = '' }))
}

# ================================ (d) LA LINEA DE CADA FASE ================================
$Pruebas['c5b (d) la portada: la linea de revision lleva unidades, hechas, atascadas, hallazgos y descartados; la de propiedades, las claves anadidas y el commit'] = {
  $s = C5b-Salida 'c5b-d' ([ordered]@{ 'revision.json' = (Revision-Base $C5bHallazgos @{ unidades = 5; hechas = 4; atascadas = 1 }); 'propiedades-arreglo.json' = (Arreglo-Base) })
  $l = Lineas-Fase (Pagina $s 'index.html')
  $nombres = @($l | ForEach-Object { $_.Nombre })
  $i = [array]::IndexOf($nombres, 'Propiedades al yml')
  Comprueba 'las dos lineas salen, propiedades, revision y luego la prueba en local' ($i -ge 0 -and $nombres[$i + 1] -ceq $TxtRevision -and $nombres[$i + 2] -ceq 'Prueba en local') ($nombres -join ' / ')
  $r = Fase-De $l $TxtRevision
  Comprueba 'revision: 5 unidades, 4 hechas, 1 atascadas, 3 hallazgos, 2 descartados' ($r.Cuenta -match '5 unidades' -and $r.Cuenta -match '4 hechas' -and $r.Cuenta -match '1 atascadas' -and $r.Cuenta -match '3 hallazgos' -and $r.Cuenta -match '2 descartados') $r.Cuenta
  Igual 'revision: hecha (la pasada esta en hecha)' 'hecha' $r.E
  $p = Fase-De $l 'Propiedades al yml'
  Comprueba 'propiedades: 2 claves anadidas, 1 no aplica y el commit con 7 caracteres' ($p.Cuenta -match '2 claves a.adidas' -and $p.Cuenta -match 'no aplican: 1' -and $p.Cuenta.Contains('commit 9f8e7d6') -and -not $p.Cuenta.Contains('9f8e7d6c')) $p.Cuenta
  Igual 'propiedades: hecha' 'hecha' $p.E
  # el resto de estados de propiedades-arreglo.json
  $sin = Fase-De (Lineas-Fase (Pagina (C5b-Salida 'c5b-d-sin-faltan' ([ordered]@{ 'propiedades-arreglo.json' = (Arreglo-Base @{ estado = 'sin-faltan'; commit = ''; pedidas = 0; anadidas = @(); noAplica = @() }) })) 'index.html')) 'Propiedades al yml'
  Comprueba 'sin-faltan: ninguna clave faltaba' ($sin.Cuenta -match 'ninguna clave') $sin.Cuenta
  $sc = Fase-De (Lineas-Fase (Pagina (C5b-Salida 'c5b-d-sin-cambios' ([ordered]@{ 'propiedades-arreglo.json' = (Arreglo-Base @{ estado = 'sin-cambios'; commit = ''; anadidas = @() }) })) 'index.html')) 'Propiedades al yml'
  Comprueba 'sin-cambios: 0 claves anadidas y sin commit' ($sc.Cuenta -match '0 claves a.adidas' -and $sc.Cuenta -notmatch 'commit') $sc.Cuenta
  $at = Fase-De (Lineas-Fase (Pagina (C5b-Salida 'c5b-d-atascada' ([ordered]@{ 'propiedades-arreglo.json' = (Arreglo-Base @{ estado = 'atascada'; commit = ''; anadidas = @(); noAplica = @(); motivo = 'la IA no dejo resultado' }) })) 'index.html')) 'Propiedades al yml'
  Comprueba 'atascada: lo dice' ($at.Cuenta -match 'atascada') $at.Cuenta
}

$Pruebas['c5b (d) la fase revision en curso, sin revision.json: su estado es curso y las tareas revision-flujo dan la cuenta; propiedades queda hecha'] = {
  $t1 = [ordered]@{ id = 'rev-1'; tipo = 'revision-flujo'; estado = 'hecha' }
  $t2 = [ordered]@{ id = 'rev-2'; tipo = 'revision-flujo'; estado = 'pendiente' }
  $s = C5b-Salida 'c5b-d-curso' ([ordered]@{ 'propiedades-arreglo.json' = (Arreglo-Base); 'tareas/rev-1.json' = $t1; 'tareas/rev-2.json' = $t2 }) @{ fase = 'revision'; fin = '' }
  $l = Lineas-Fase (Pagina $s 'index.html')
  $r = Fase-De $l $TxtRevision
  Igual 'revision: por aqui va' 'curso' $r.E
  Comprueba 'con las tareas: 1 hecha, 0 atascadas, 1 pendiente' ($r.Cuenta -match 'hechas: 1' -and $r.Cuenta -match 'atascadas: 0' -and $r.Cuenta -match 'pendientes: 1') $r.Cuenta
  Igual 'propiedades: hecha' 'hecha' (Fase-De $l 'Propiedades al yml').E
}

# ================================ (e) LAS PROPIEDADES EN LA PAGINA 4 ================================
$Pruebas['c5b (e) propiedades-arreglo.json con 2 claves: la pagina 4 las nombra con su fichero y el commit, dice las que no aplican y enlaza al area Propiedades de la pagina 2'] = {
  $s = C5b-Salida 'c5b-e' ([ordered]@{ 'propiedades-arreglo.json' = (Arreglo-Base) })
  $p4 = Pagina $s '4-correcciones.html'
  $sec = Panel-De $p4 'propiedades-arreglo'
  Comprueba 'hay un panel de propiedades anadidas' ($sec.Length -gt 0) 'sin id="propiedades-arreglo"'
  $t = Texto-Plano $sec
  Comprueba 'con la etiqueta Medido' ($sec -match 'et et-medido') $sec
  Comprueba 'nombra recibos.ruta con su fichero' ($sec -match '<code>recibos\.ruta</code> <code>src/main/resources/application\.yml</code>') $sec
  Comprueba 'y recibos.cola con el suyo' ($sec -match '<code>recibos\.cola</code> <code>src/main/resources/application-pre\.yml</code>') $sec
  Comprueba 'el commit con 7 caracteres' ($sec.Contains('<code>9f8e7d6</code>') -and -not $sec.Contains('9f8e7d6c')) $sec
  Comprueba 'las que no aplican, con su motivo' ($t.Contains('recibos.vieja') -and $t.Contains('Spring Boot 3 ya no la lee')) $t
  Comprueba 'enlaza al area Propiedades de la pagina 2' ($sec.Contains('href="2-problemas.html#g-propiedades"')) $sec
  Comprueba 'no repite lo que pinta la pagina 2: ninguna fila fila ni la clave que falta' ($sec -notmatch '<li class="fila' -and $t -notmatch 'application\.properties')
  $p2 = Pagina $s '2-problemas.html'
  Comprueba 'y la pagina 2 sigue con su area Propiedades como antes' ($p2 -match 'aria-labelledby="g-propiedades"' -and $p2 -notmatch 'id="propiedades-arreglo"')
}

$Pruebas['c5b (e) propiedades-arreglo.json sin-faltan no pinta panel; sin-cambios dice que no se anadio nada; atascada dice el motivo, todo escapado'] = {
  $nada = C5b-Salida 'c5b-e-sin-faltan' ([ordered]@{ 'propiedades-arreglo.json' = (Arreglo-Base @{ estado = 'sin-faltan'; commit = ''; pedidas = 0; anadidas = @(); noAplica = @() }) })
  Comprueba 'sin-faltan: ni panel' ((Panel-De (Pagina $nada '4-correcciones.html') 'propiedades-arreglo').Length -eq 0)
  $sc = C5b-Salida 'c5b-e-sin-cambios' ([ordered]@{ 'propiedades-arreglo.json' = (Arreglo-Base @{ estado = 'sin-cambios'; commit = ''; anadidas = @() }) })
  $t = Texto-Plano (Panel-De (Pagina $sc '4-correcciones.html') 'propiedades-arreglo')
  Comprueba 'sin-cambios: dice que no se ha anadido ninguna clave, y que no aplican' ($t -match (Es 'ninguna clave') -and $t.Contains('recibos.vieja')) $t
  $at = C5b-Salida 'c5b-e-atascada' ([ordered]@{ 'propiedades-arreglo.json' = (Arreglo-Base @{ estado = 'atascada'; commit = ''; anadidas = @(); noAplica = @(); motivo = 'el yml <roto> & sin cerrar' }) })
  $sec = Panel-De (Pagina $at '4-correcciones.html') 'propiedades-arreglo'
  Comprueba 'atascada: dice el motivo, escapado' ($sec.Contains('el yml &lt;roto&gt; &amp; sin cerrar') -and $sec -notmatch '<roto>') $sec
  Comprueba 'y no lista ninguna clave anadida' ($sec -notmatch '<code>recibos\.ruta</code>')
}

# ================================ (f) -RevisarTodo EN EL COMANDO DE LA PASADA ================================
$Pruebas['c5b (f) Get-ComandoPasada con revisarTodo verdadero lleva -RevisarTodo, despues de -Practicas y -Reglas; sin el, no; la portada lo repite'] = {
  $con = (ConvertTo-Json -InputObject (Estado-Base @{ revisarTodo = $true }) -Depth 8) | ConvertFrom-Json
  Igual 'con revisarTodo: -RevisarTodo al final' ($ComandoPasada + ' -Si -RevisarTodo') (Get-ComandoPasada $con 'corregir' '')
  $sin = (ConvertTo-Json -InputObject (Estado-Base @{ revisarTodo = $false }) -Depth 8) | ConvertFrom-Json
  Igual 'con revisarTodo falso: sin el' ($ComandoPasada + ' -Si') (Get-ComandoPasada $sin 'corregir' '')
  $viejo = (ConvertTo-Json -InputObject (Estado-Base) -Depth 8) | ConvertFrom-Json
  Igual 'sin el campo (un estado.json de antes): sin el' ($ComandoPasada + ' -Si') (Get-ComandoPasada $viejo 'corregir' '')
  $todos = (ConvertTo-Json -InputObject (Estado-Base @{ practicas = $true; reglas = $true; revisarTodo = $true; maxHoras = 2; limite = 5; sinPruebaLocal = $true }) -Depth 8) | ConvertFrom-Json
  Igual 'con las demas opciones: despues de -Reglas y antes de -MaxHoras' ($ComandoPasada + ' -Si -Practicas -Reglas -RevisarTodo -MaxHoras 2 -Limite 5 -SinPruebaLocal') (Get-ComandoPasada $todos 'corregir' '')
  Igual 'con -ConPruebaLocal tambien lo lleva' ($ComandoPasada + ' -Si -RevisarTodo') (Get-ComandoPasada $con 'corregir' '' -ConPruebaLocal)
  $s = Nueva-Salida 'c5b-f' (Estado-Base @{ revisarTodo = $true; fase = 'resumen' }) ([ordered]@{})
  $paso = Paso-De $s
  Igual 'cortada: el comando del siguiente paso lleva -RevisarTodo' 'cortada' $paso.Caso
  Igual 'y es la pasada con -RevisarTodo' ($ComandoPasada + ' -Si -RevisarTodo') $paso.Comando
  Igual 'la portada ensena ese mismo comando' $paso.Comando ((Comando-De (Panel-De (Pagina $s 'index.html') 'siguiente-paso')).Trim())
  $c = Get-ComandoCierre $con
  Comprueba 'el comando de -Cierre no lo lleva (no se mezcla)' ($c -notmatch 'RevisarTodo') $c
}

# ================================ (g) LOS DOS FICHEROS EN LA PORTADA ================================
$Pruebas['c5b (g) portada, Que es cada fichero: datos/revision.json y datos/propiedades-arreglo.json salen con su frase y solo si existen'] = {
  $con = C5b-Salida 'c5b-g' ([ordered]@{ 'revision.json' = (Revision-Base $C5bHallazgos); 'propiedades-arreglo.json' = (Arreglo-Base) })
  $i = Pagina $con 'index.html'
  Comprueba 'datos/revision.json sale con su explicacion' ($i -match '<code>datos/revision\.json</code></p><p>[^<]+') (Texto-Plano $i)
  Comprueba 'datos/propiedades-arreglo.json tambien' ($i -match '<code>datos/propiedades-arreglo\.json</code></p><p>[^<]+')
  $sin = Pagina (C5b-Salida 'c5b-g-sin') 'index.html'
  Comprueba 'sin ellos no salen' (-not $sin.Contains('datos/revision.json') -and -not $sin.Contains('datos/propiedades-arreglo.json'))
}

Invoke-Banco $Pruebas 'probar-entrega.ps1 (C5a: los informes despues de -Cierre)'
