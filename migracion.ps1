<#
migracion.ps1 - Migracion desatendida de un batch Java, con un modelo pequeno.
Compatible con Windows PowerShell 5.1 y PowerShell 7. Solo ASCII a proposito.
Necesita comun.ps1, tareas.ps1 y la carpeta tareas\ junto a este script.

QUE HACE (esta version: solo la primera parte, la lectura de clases)
  Un comando. Das el batch original (-Legacy) y el migrado (-Migrado), contestas
  dos preguntas (modelo y que hacer al acabar el informe) y te vas. Cada llamada
  a Copilot CLI es una tarea cerrada y pequena; el script la comprueba. El
  trabajo va a <Migrado>\migracion-<batch>\ (git la ignora en local) y la IA lee
  en un worktree aparte (<Migrado>-rescate), nunca en tu carpeta.

  Arranque: herramientas y repos, batch de referencia (-Plantilla, o el guardado
  en %USERPROFILE%\.rescate\ajustes.json, o se pregunta), modelo, prueba de
  aptitud (una ficha de clase sobre un fichero de juguete), pregunta y worktree.
  Lectura: una ficha por clase del original, hasta 4 llamadas a la vez. Tras
  cada ronda el worktree tiene que estar limpio y el original y la referencia sin
  cambios. Una salida invalida se repite una vez, con el motivo y esfuerzo alto;
  si falla otra vez la tarea queda atascada y se sigue.
  Si algo se atasca, el script para y lo deja en datos\estado.json (parada) con un
  texto de ayuda listo para pegar en Copilot. Al relanzar el mismo comando salta
  las tareas hechas y sigue donde se quedo. Las atascadas tampoco se repiten (salvo
  con -Reintentar o con otro modelo).

USO
  .\migracion.ps1 -Legacy C:\ruta\life-java8 -Migrado C:\ruta\batch-life
  .\migracion.ps1 -Legacy ... -Migrado ... -Plantilla C:\ruta\batch-terminado -Modelo <id>
  .\migracion.ps1 ... -SoloInforme     # contesta "parar" a la pregunta del final
  .\migracion.ps1 ... -Si              # contesta "corregir"
  .\migracion.ps1 ... -MaxHoras 6      # no empieza rondas nuevas pasado ese tiempo
  .\migracion.ps1 ... -Limite 5        # ensayo corto: solo las 5 primeras tareas pendientes
  .\migracion.ps1 ... -Reintentar      # vuelve a llamar a las tareas atascadas de antes

  Salida: 0 bien (o tope de tiempo), 1 no pudo arrancar, 2 se paro (ver estado.json).
  Los ajustes de ajustes.json (y de .rescate\config.json del migrado) pisan las claves
  del bloque CONFIGURACION; la carpeta de ajustes se cambia con la variable de
  entorno RESCATE_HOME. Antes de darlo por bueno, pasa tests\probar-migracion.ps1.
#>
[CmdletBinding()]
param(
  [string]$Legacy = '',       # carpeta del batch original (repo git)
  [string]$Migrado = '.',     # carpeta del batch migrado (repo git, en una rama)
  [string]$Plantilla = '',    # batch de referencia: ya migrado y aprobado (repo git)
  [string]$Modelo = '',       # id del modelo de Copilot; sin esto se pregunta
  [switch]$SoloInforme,       # al acabar el informe, parar (no corregir)
  [switch]$Si,                # al acabar el informe, corregir
  [double]$MaxHoras = 0,      # 0 = sin tope
  [int]$Limite = 0,           # 0 = sin limite; N = en este lanzamiento solo las N primeras tareas pendientes
  [switch]$Reintentar         # volver a intentar las tareas atascadas de un lanzamiento anterior
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'comun.ps1')
. (Join-Path $PSScriptRoot 'tareas.ps1')

# ============================ CONFIGURACION ============================
$Cfg += @{
  Modelos            = @('claude-sonnet-5.5', 'gpt-6-luna', 'gpt-6.1-terra', 'gpt-6.1-sol', 'gpt-6-astra', 'claude-haiku-5.5', 'gemini-3.8-flash')
  JavaExe            = 'java'
  Paralelo           = 4      # llamadas a Copilot a la vez
  SegundosPorLlamada = 900    # pasado este tiempo, la llamada se mata
  FallosSeguidos     = 6      # llamadas fallidas seguidas antes de parar
  Intentos           = 2      # el primero y un reintento con el motivo
  LineasPorTarea     = 300    # un fichero mas largo se trocea por rangos de lineas
  CitaMax            = 120    # caracteres de una cita
  CitaCerca          = 3      # una cita a esta distancia (o menos) de su linea cuenta como bien situada
  EsfuerzoLectura    = 'medium'
  EsfuerzoReintento  = 'high'
  Papeles            = @('lector', 'procesador', 'escritor', 'tarea', 'validador', 'configuracion', 'acceso-datos', 'sftp', 'modelo', 'otro')
  TiposDato          = @('entrada-fichero', 'salida-fichero', 'sftp', 'tabla-lee', 'tabla-escribe', 'parametro', 'config', 'regla', 'error', 'externo')
}

# ============================== UTILIDADES ==============================
function Get-Repo([string]$Ruta, [string]$Que) {
  if (-not (Test-Path -LiteralPath $Ruta)) { Stop-Arranque "$Que no existe: $Ruta" }
  $r = Resolve-Dir $Ruta
  if (-not (Test-Path -LiteralPath (Join-Path $r '.git'))) { Stop-Arranque "$Que no es la raiz de un repo git: $r" }
  return $r
}

# artifactId del pom; si no hay, el nombre de la carpeta. Vale como nombre de carpeta.
function Get-Batch([string]$Raiz) {
  $id = ''
  $p = Join-Path $Raiz 'pom.xml'
  if (Test-Path -LiteralPath $p) {
    $x = New-Object System.Xml.XmlDocument
    try {
      $x.Load($p)
      foreach ($n in $x.DocumentElement.ChildNodes) { if ($n.LocalName -eq 'artifactId') { $id = $n.InnerText.Trim() } }
    }
    catch { $id = '' }
  }
  if (-not $id) { $id = Split-Path $Raiz -Leaf }
  return ($id -replace '[^\w\.\-]', '-')
}

# ============================ AJUSTES Y ESTADO ============================
function Get-RutaAjustes {
  if ($env:RESCATE_HOME) { return (Join-Path $env:RESCATE_HOME 'ajustes.json') }
  return (Join-Path (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.rescate') 'ajustes.json')
}

# Guarda la referencia en ajustes.json sin tocar el resto de claves.
function Save-Plantilla([string]$Ruta) {
  $f = Get-RutaAjustes
  $o = [ordered]@{}
  if (Test-Path -LiteralPath $f) { foreach ($pr in (Read-Json $f).PSObject.Properties) { $o[$pr.Name] = $pr.Value } }
  $o['Plantilla'] = $Ruta
  Write-Json $f $o
}

function Save-Estado {
  $Estado['actualizado'] = (Get-Date).ToString('s')
  Write-Json (Join-Path $Datos 'estado.json') $Estado
}

# Para el trabajo y lo deja en estado.json con un texto de ayuda para pegar en Copilot.
function Set-Parada([string]$Motivo, [string]$Detalle, [string]$Registro) {
  $ayuda = "Estoy ejecutando migracion.ps1 (migracion desatendida de un batch Java con GitHub Copilot CLI) y se ha parado. Motivo: $Motivo. Detalle: $Detalle. El registro esta en: $Registro. Dime que ha pasado y que tengo que hacer para arreglarlo. Despues vuelvo a lanzar el mismo comando y sigue donde se quedo."
  $Estado['parada'] = [ordered]@{ motivo = $Motivo; detalle = $Detalle; registro = $Registro; ayuda = $ayuda }
  Save-Estado
  if ($Motivo -eq 'tope-de-tiempo') { Aviso "Parada ($Motivo): $Detalle" } else { Fallo "Parada ($Motivo): $Detalle" }
}

function Select-Modelo {
  $l = @($Cfg.Modelos)
  Info 'Modelo de Copilot para las lecturas y los arreglos:'
  for ($i = 0; $i -lt $l.Count; $i++) { Info ('  ' + ($i + 1) + ') ' + $l[$i]) }
  $otro = $l.Count + 2
  Info ('  ' + ($l.Count + 1) + ') el que tenga Copilot (Enter)')
  Info "  $otro) otro (lo escribes tu)"
  $r = "$(Read-Host 'Numero')".Trim()
  if ($r -match '^\d+$' -and [int]$r -ge 1 -and [int]$r -le $l.Count) { return [string]$l[[int]$r - 1] }
  if ($r -eq "$otro") { return "$(Read-Host 'Id del modelo')".Trim() }
  return ''
}

# ================================= MAIN =================================
$reloj = [System.Diagnostics.Stopwatch]::StartNew()
if (-not $Legacy) { Stop-Arranque 'Falta -Legacy: la carpeta del batch original (Java 8).' }
if ($SoloInforme -and $Si) { Stop-Arranque 'Usa -SoloInforme o -Si, no los dos.' }
$respondeSi = [bool]$Si

# 1. Herramientas y repos (antes, los ajustes: pueden cambiar donde estan)
$ajustes = Read-CfgFile (Get-RutaAjustes) @('Plantilla')
foreach ($x in @(@('git', 'git'), @('java', $Cfg.JavaExe), @('Copilot', $Cfg.CopilotExe))) {
  if (-not (Get-Command $x[1] -ErrorAction SilentlyContinue)) { Stop-Arranque "No encuentro $($x[0]) ('$($x[1])') en el PATH." }
}
$LegacyRoot = Get-Repo $Legacy '-Legacy'
$MigradoRoot = Get-Repo $Migrado '-Migrado'
$rama = Get-Rama $MigradoRoot
if (-not $rama -or $rama -eq 'HEAD') { Stop-Arranque "El migrado no esta en una rama (HEAD suelto): $MigradoRoot. Cambia a una rama y vuelve a lanzar." }
Read-Config $MigradoRoot
$mvn = Get-Mvn $MigradoRoot
if (-not (Test-Path -LiteralPath $mvn) -and -not (Get-Command $mvn -ErrorAction SilentlyContinue)) { Stop-Arranque "No encuentro Maven ('$mvn'). Instalalo o pon MvnExe en los ajustes." }
Set-Excluidos $MigradoRoot
$Fuentes = @(Get-JavaOriginal $LegacyRoot)
if ($Fuentes.Count -eq 0) { Stop-Arranque "No hay ningun .java que leer en el original: $LegacyRoot`nBusco los de src/main/java de cualquier modulo y, si no hay, todos menos los de src/test, target y .git. Mira que -Legacy es la carpeta correcta." }

# 2. Batch de referencia: -Plantilla, el guardado o se pregunta; se guarda
$guardada = ''
if ($ajustes -and $ajustes.Plantilla) { $guardada = [string]$ajustes.Plantilla }
$ref = $Plantilla
if (-not $ref -and $guardada -and (Test-Path -LiteralPath $guardada)) { $ref = $guardada }
if (-not $ref) { $ref = "$(Read-Host 'Carpeta del batch de referencia (un batch ya migrado y aprobado)')".Trim() }
if (-not $ref) { Stop-Arranque 'Falta la referencia: pasa -Plantilla o contesta con la carpeta del batch de referencia.' }
$PlantillaRoot = Get-Repo $ref 'La referencia'
if ($PlantillaRoot -ne $guardada) { Save-Plantilla $PlantillaRoot }

# Carpetas de salida y estado anterior (si se relanza)
$batch = Get-Batch $MigradoRoot
$Salida = Join-Path $MigradoRoot ('migracion-' + $batch)
$Datos = Join-Path $Salida 'datos'
$Registros = Join-Path $Salida 'registros'
foreach ($d in @($Datos, $Registros)) { if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -Force) } }
$previo = $null
if (Test-Path -LiteralPath (Join-Path $Datos 'estado.json')) { try { $previo = Read-Json (Join-Path $Datos 'estado.json') } catch { $previo = $null } }

# 3. Modelo: -Modelo, el del lanzamiento anterior o el menu
if ($PSBoundParameters.ContainsKey('Modelo')) { $ModeloElegido = $Modelo }
elseif ($previo -and ($null -ne $previo.modelo)) { $ModeloElegido = [string]$previo.modelo }
else { $ModeloElegido = Select-Modelo }
if ($ModeloElegido) { Info "Modelo: $ModeloElegido" } else { Info 'Modelo: el que tenga Copilot' }
# las tareas atascadas de antes se conservan si el modelo es el mismo y no se pide -Reintentar
$conservar = [bool]((-not $Reintentar) -and $previo -and ([string]$previo.modelo -ceq $ModeloElegido))
$H0 = [pscustomobject]@{ Legacy = (Get-Huella $LegacyRoot); Plantilla = (Get-Huella $PlantillaRoot) }

# 4. Prueba de aptitud (se salta si ya paso con este modelo)
if ($previo -and ($null -ne $previo.aptitud) -and ([string]$previo.aptitud -eq $ModeloElegido)) { Info 'Prueba de aptitud: ya pasada con este modelo.' }
else {
  Info 'Prueba de aptitud (una ficha de clase sobre un fichero de juguete)...'
  $mal = Test-Aptitud
  if ($mal) { Stop-Arranque ("$mal`nRegistros: $Registros`nPrueba con otro modelo (-Modelo) o mira que Copilot responde.") }
  Bien 'Prueba de aptitud: bien.'
}

# 5. Pregunta: que hacer al acabar el informe
if ($SoloInforme) { $respuesta = 'parar' }
elseif ($respondeSi) { $respuesta = 'corregir' }
elseif ($previo -and $previo.respuesta) { $respuesta = [string]$previo.respuesta }
else {
  $r = "$(Read-Host 'Al acabar el informe, corregir el codigo del migrado? Enter = si, n = parar')".Trim()
  if ($r -match '^[nN]') { $respuesta = 'parar' } else { $respuesta = 'corregir' }
}
$Si = [switch]$true    # las preguntas ya estan contestadas: Confirmar no vuelve a preguntar

# 6. Worktree y estado
$OrigenRoot = $MigradoRoot
$Worktree = ''
$dirWt = Get-DirRescate
if (-not (Test-WorktreeRescate $dirWt)) { New-WorktreeRescate $dirWt }
$RepoRoot = $dirWt
Read-Config $RepoRoot
$Estado = [ordered]@{
  version = 1; batch = $batch; legacy = $LegacyRoot; migrado = $MigradoRoot; plantilla = $PlantillaRoot
  worktree = $RepoRoot; rama = (Get-Rama $RepoRoot); modelo = $ModeloElegido; aptitud = $ModeloElegido; respuesta = $respuesta
  fase = 'fichas-clase'; creado = (Get-Date).ToString('s'); actualizado = ''; parada = $null
}
if ($previo -and $previo.creado) { $Estado['creado'] = [string]$previo.creado }
try {
  foreach ($d in @((Join-Path $Datos 'tareas'), (Join-Path $Datos 'fichas'))) { if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -Force) } }
  $Tareas = @(Get-TareasFichas $Fuentes $conservar)
  Save-Estado
  $hechas0 = @($Tareas | Where-Object { $_.estado -eq 'hecha' }).Count
  $ficheros = @($Tareas | Group-Object { $_.ficha }).Count
  Info "Tareas de lectura: $($Tareas.Count) (fichas de clase de $ficheros ficheros del original; $hechas0 ya hechas)."
  $atascadas0 = @($Tareas | Where-Object { $_.estado -eq 'atascada' }).Count
  if ($atascadas0 -gt 0) { Aviso "$atascadas0 tareas atascadas de un lanzamiento anterior se conservan sin repetir. Para volver a intentarlas: -Reintentar (o cambia de modelo)." }

  # Lectura: fichas de clase, en rondas de hasta Paralelo llamadas
  if (-not (Set-Despierto $true)) { Aviso 'No he podido pedir a Windows que no suspenda el equipo: si lo dejas solo, compruebalo.' }
  $racha = 0
  $parada = $false
  $iniciadas = @{}
  while ($true) {
    $pend = @($Tareas | Where-Object { $_.estado -eq 'pendiente' })
    if ($pend.Count -eq 0) { break }
    $lote = @($pend | Select-Object -First ([int]$Cfg.Paralelo))
    if ($Limite -gt 0) {
      # -Limite cuenta tareas, no llamadas: una que se reintenta sigue siendo la misma
      $dentro = @()
      foreach ($x in $lote) {
        if ($iniciadas.ContainsKey($x.id) -or $iniciadas.Count -lt $Limite) { $iniciadas[$x.id] = $true; $dentro += $x }
      }
      $lote = $dentro
      if ($lote.Count -eq 0) { break }
    }
    $head = Get-Head $RepoRoot
    $rondaRama = Get-Rama $RepoRoot
    Info ('Ronda: ' + $lote.Count + ' llamadas a la vez (quedan ' + $pend.Count + ' tareas)...')
    $res = @(Invoke-Ronda $lote $RepoRoot $LegacyRoot)

    # comprobacion tras la ronda: worktree limpio y original y referencia sin cambios
    $sucio = @((Invoke-Git $RepoRoot @('status', '--porcelain')).Salida | Where-Object { $_ })
    if ($sucio.Count -gt 0) { Undo-Lote $rondaRama $head }
    if ((Get-Huella $LegacyRoot) -ne $H0.Legacy -or (Get-Huella $PlantillaRoot) -ne $H0.Plantilla) {
      Set-Parada 'guardas' 'Ha cambiado el original o la referencia durante una lectura. Esa carpeta no se deshace desde aqui: mira con git status y git diff, y vuelve a lanzar.' $res[0].Registro
      $parada = $true
      break
    }
    foreach ($o in $res) {
      if ($o.Estado -in @('fallo', 'tiempo')) { $racha++ } else { $racha = 0 }
      if ($sucio.Count -gt 0 -and $o.Estado -in @('ok', 'invalida')) {
        $o.Estado = 'invalida'
        $o.Motivo = 'La lectura toco ficheros del repositorio (' + (($sucio | Select-Object -First 3) -join '; ') + '). Lee sin cambiar nada: solo escribes el fichero de salida.'
      }
      $t = $o.Tarea
      $t.intentos++
      $t.motivo = $o.Motivo
      $t.ultimoEstado = $o.Estado
      if ($o.Estado -eq 'ok') { $t.estado = 'hecha'; $t.resultado = $o.Ficha }
      elseif ($t.intentos -ge [int]$Cfg.Intentos) { $t.estado = 'atascada'; Aviso "Atascada: $($t.entradas.fichero): $($o.Motivo)" }
      Save-Tarea $t
    }
    Save-Fichas $Tareas
    if ($racha -ge [int]$Cfg.FallosSeguidos) {
      # el fallo es de Copilot, no de las tareas: vuelven a empezar al relanzar
      foreach ($o in $res) {
        if ($o.Estado -in @('fallo', 'tiempo')) { $o.Tarea.estado = 'pendiente'; $o.Tarea.intentos = 0; Save-Tarea $o.Tarea }
      }
      $ultimo = @($res | Where-Object { $_.Estado -in @('fallo', 'tiempo') } | Select-Object -Last 1)[0]
      Set-Parada 'copilot-no-responde' "$racha llamadas seguidas han fallado (sesion, cuota o red). Ultimo error: $($ultimo.Motivo)" $ultimo.Registro
      $parada = $true
      break
    }
    if ($MaxHoras -gt 0 -and $reloj.Elapsed.TotalHours -ge $MaxHoras -and @($Tareas | Where-Object { $_.estado -eq 'pendiente' }).Count -gt 0) {
      Set-Parada 'tope-de-tiempo' "Se ha llegado al tope de -MaxHoras $MaxHoras. Relanza el mismo comando para seguir." $Registros
      $parada = $true
      break
    }
  }
  Save-Fichas $Tareas
  $quedan = @($Tareas | Where-Object { $_.estado -eq 'pendiente' }).Count
  if (-not $parada -and $quedan -eq 0) { $Estado['fase'] = 'fichas-clase-hechas'; Save-Estado }

  $hechas = @($Tareas | Where-Object { $_.estado -eq 'hecha' }).Count
  $atascadas = @($Tareas | Where-Object { $_.estado -eq 'atascada' }).Count
  Info ''
  Info "Lectura de clases: $hechas hechas, $atascadas atascadas, $quedan pendientes de $($Tareas.Count) tareas."
  if (-not $parada -and $quedan -gt 0) { Info "Limite de -Limite $Limite alcanzado: quedan $quedan tareas pendientes. Relanza el mismo comando sin -Limite para seguir." }
  Info "Datos en: $Salida"
  if ($atascadas -gt 0) { Aviso "Las tareas atascadas estan en $(Join-Path $Datos 'tareas') (estado 'atascada', con su motivo)." }
  if ($parada -and $Estado['parada'].motivo -ne 'tope-de-tiempo') { exit 2 }
  exit 0
}
catch {
  # una excepcion que nadie esperaba: se deja en estado.json para que el relanzamiento no sea a ciegas
  $ex = $_
  $donde = ''
  if ($ex.InvocationInfo -and $ex.InvocationInfo.ScriptName) { $donde = ' (' + (Split-Path $ex.InvocationInfo.ScriptName -Leaf) + ':' + $ex.InvocationInfo.ScriptLineNumber + ')' }
  try { Set-Parada 'error-interno' ($ex.Exception.Message + $donde) $Registros }
  catch { Fallo ('Error interno: ' + $ex.Exception.Message + $donde + ' (y no he podido escribir estado.json: ' + $_.Exception.Message + ')') }
  exit 2
}
finally {
  [void](Set-Despierto $false)
}
