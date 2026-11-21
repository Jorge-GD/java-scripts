<#
migracion.ps1 - Migracion desatendida de un batch Java, con un modelo pequeno.
Compatible con Windows PowerShell 5.1 y PowerShell 7. Solo ASCII a proposito.
Necesita comun.ps1, tareas.ps1, lanzadores.ps1, informe.ps1, practicas.ps1, propiedades.ps1, huella.ps1, arreglo-practicas.ps1, tests-reglas.ps1, rescate.ps1, prueba-local.ps1 y las carpetas tareas\ e informe\ junto a este script.

QUE HACE (la lectura del original, los datos para explicarlo a negocio, la correccion del migrado, su comparacion y la prueba en local)
  Un comando. Das el batch original (-Legacy) y el migrado (-Migrado), contestas
  dos preguntas (modelo y que hacer al acabar el informe) y te vas. Cada llamada
  a Copilot CLI es una tarea cerrada y pequena; el script la comprueba. El
  trabajo va a <Migrado>\migracion-<batch>\ (git la ignora en local) y la IA lee
  en un worktree aparte (<Migrado>-rescate), nunca en tu carpeta.

  Arranque: herramientas y repos, batch de referencia (-Plantilla, o el guardado
  en %USERPROFILE%\.rescate\ajustes.json, o se pregunta), modelo, carpeta de rescate (si ya existe: lo que tenga sin commit se mira antes de
  gastar nada), prueba de aptitud (una ficha de clase sobre un fichero de juguete), pregunta y worktree (si no existe, se crea). No borra nunca lo
  que haya sin commit en el worktree: lo de un intento cortado va a un git stash y lo demas, o una rama rescate/ sin unir a tu rama, para el
  arranque (salida 1) sin tocar nada; si es lo primero, la parada (motivo cambios-sin-commit) queda en estado.json.
  Diagnostico (sin IA, la primera fase): rescate.ps1 -Modo diagnostico mide el migrado y deja datos\hallazgos-antes.json y
  datos\diagnostico-antes.md; su pagina es 2-problemas.html. Lleva el commit del migrado que midio (datos\diagnostico-antes.json): con el
  mismo commit relanzar no repite Maven; con otro (o sin ese dato) se hace otra vez, con cobertura y buenas practicas, y el diagnostico
  viejo y la correccion anterior se apartan en datos\anterior-<commit7>\. Lo que no tiene commit en tu carpeta no cuenta.
  Lectura: una ficha por clase del original, hasta 4 llamadas a la vez. Tras
  cada ronda el worktree tiene que estar limpio y el original y la referencia sin
  cambios. Una salida invalida se repite una vez, con el motivo y esfuerzo alto;
  si falla otra vez la tarea queda atascada y se sigue.
  Orden de las fases (datos\estado.json lleva la fase en que va; cada tarea hecha se salta al relanzar, y una fase se
  hace aunque la anterior tenga atascadas). Con la respuesta "corregir":
    fichas-clase, mapa, lanzadores, fichas-job, resumen, pruebas-pre, casos-pre, lectura-hecha, correccion, comparar y prueba-local.
  Con "parar" (o -SoloInforme): las mismas fases de lectura, comparar, lectura-hecha y prueba-local. Si la correccion
  se para, o hay tareas pendientes (-Limite), no se sigue con nada mas. Al acabar todo, sin parada ni pendientes, la
  fase es hecha, y estado.json lleva fin (vacio mientras corre; la hora al salir, de cualquier forma).
    mapa        jobs del original (contrato de rescate.ps1 -Modo pre -SinIA, o el que ya haya en
                .rescate\contrato.json), sus pasos (una tarea de definicion por fichero que
                define jobs) y sus clases, que calcula el script: datos\mapa.json; y las
                variables de application*.yml/.properties del migrado: datos\variables.json
    lanzadores  los .sh, .ksh y .bash que lanzan el batch (y los ficheros sin extension que empiezan por #! de sh, bash o ksh): el
                script los busca en el original y, si das -Lanzadores <carpeta>, tambien en esa carpeta (datos\lanzadores.json: su
                inventario sin IA y el job con el que se enlazan) y una tarea ficha-sh por script cuenta, con citas del propio script, sus
                parametros, lo que hace antes y despues del java y sus codigos de salida: datos\fichas-sh\<id>.json. Sin ningun .sh
                no hay tareas y la consola dice como pasar la carpeta. Va detras de mapa y se hace tambien en un batch que ya paso por
                el; las tareas hechas no se repiten
    fichas-job  una redaccion por job, sin leer codigo, con las listas que monta el script
                con los datos de las fichas de clase: datos\jobs\<job>.json
    resumen     una tarea con todos los jobs: datos\resumen.json
    pruebas-pre una tarea por job con reglas o errores (sin leer codigo): el guion de prueba en pre,
                datos\pruebas\<job>.json; los jobs sin reglas ni errores lo llevan montado por el script
    casos-pre   una tarea por cada regla o error que pruebas-pre dejo en sinCaso: un caso de prueba para esa regla. Si vale, entra
                en datos\pruebas\<job>.json y la regla sale de sinCaso; si no, se queda ahi. Va despues de pruebas-pre y se hace
                tambien en un batch que ya paso por ella; las tareas hechas no se repiten
    lectura-hecha
    correccion  si contestaste "corregir": rescate.ps1 -Modo fix -Todo arregla el worktree (registros\correccion.log), se vuelve a
                diagnosticar (datos\hallazgos-despues.json) y datos\correcciones.json cuenta que se ha corregido y que no.
                Con "parar" (o -SoloInforme) no se corrige nada. Se salta si la correccion ya esta completa; si dejo ficheros atascados, solo
                se repite con -Reintentar (y rescate.ps1 los vuelve a intentar).
    comparar    una tarea por clase del original con datos: la IA lee los ficheros del migrado que elige el script (los del
                mismo nombre; si la correccion los renombro, partio o borro, los que git dice que los recogieron, por el
                renombrado o por las lineas que se llevaron; y si no, los que comparten palabras con la clase) y dice, dato a
                dato, si estan igual, distintos o faltan; las citas las comprueba el script: datos\comparacion\<ficha>.json, con el
                commit del worktree y el momento (antes-de-corregir o despues-de-corregir, segun git). Sin ficheros del migrado
                no hay llamada y sus datos salen 'sin-pieza'. Es una lectura sin cambiar nada. Se rehace solo si cambian los
                ficheros del migrado que mira (o cuales son), no por cualquier commit nuevo. Con lanzadores hay ademas una tarea por script: la IA busca en el migrado lo que hacia cada accion
                del .sh (los ficheros donde buscar los elige el script) y dice igual, distinto, falta o no lo se, con citas de los dos
                lados: datos\comparacion-sh\<id>.json. Las acciones que no se parecen a nada del migrado salen en falta sin llamada. La de un script se
                rehace con la misma regla: solo si cambian los ficheros del migrado que mira (o cuales son), no por cualquier commit nuevo.
    practicas   solo con -Practicas, despues de la correccion (y de comparar) y antes de prueba-local: pasa a Lombok los getters y setters
                escritos a mano (los de datos\practicas-despues.json, o de practicas-antes.json), una tarea por fichero, y solo se
                queda con el cambio de un fichero si lo compilado queda igual que antes (arreglo-practicas.ps1): un commit por
                fichero; datos\practicas-arreglos.json. Sin -Practicas la fase no existe. Si el pom no usa Lombok, avisa y no
                llama a nadie
    reglas      solo con -Reglas, despues de practicas y antes de prueba-local: un test unitario por clase con un caso por cada regla de
                negocio que la comparacion da por igual (tests-reglas.ps1). El script cambia la linea de cada regla (un operador) y solo
                se queda con el test si falla con el cambio: un commit por test; datos\tests-reglas.json. Sin -Reglas la fase no existe
    prueba-local  prueba-local.ps1 -Si (con el mismo modelo, y -JavaLegacy si lo das) ejecuta el original y el migrado con las
                mismas entradas: datos\prueba-local.json y registros\prueba-local.log; su salida sale por la consola mientras
                corre. Siempre se lanza (al relanzar reutiliza lo hecho) salvo con -SinPruebaLocal. Un fallo se avisa y la
                pasada sigue: el codigo de salida no depende de esta fase. estado.json lleva pruebaLocal (resultado hecha,
                fallo o saltada, codigo, minutos, detalle, jdkOriginal -true si el original no compila con el JDK de Maven- y registro); hasta llegar
                a la fase vale null. estado.json lleva tambien ramaOrigen (la rama del migrado de la que sale la de rescate) y javaLegacy (el
                valor de -JavaLegacy, o vacio): con ellos la portada monta el comando del siguiente paso. Y las opciones de ese lanzamiento: practicas, reglas,
                maxHoras, limite y sinPruebaLocal (-Reintentar no se guarda: es de una sola vez); relanzar sin una de ellas la quita del comando.
  Informe: tras cada fase y al parar, el script monta en <Salida>\ index.html (la portada: como ha ido y
  que te toca), 1-batch-original.html (que hace el batch, job a job), 2-problemas.html (los problemas del
  migrado), 3-original-vs-migrado.html (el original frente al migrado, dato a dato), 4-correcciones.html (que se ha
  corregido y que queda) y 5-buenas-practicas.html (las buenas practicas del migrado y que hacer con cada una), con
  informe.ps1 y las plantillas de informe\.
  Se abren con doble clic: sin IA, sin JavaScript y sin nada externo.
  Si algo se atasca, el script para y lo deja en datos\estado.json (parada) con un
  texto de ayuda listo para pegar en Copilot. Al relanzar el mismo comando salta
  las tareas hechas y sigue donde se quedo. Las tareas de lectura atascadas tampoco
  se repiten (salvo con -Reintentar o con otro modelo), y los ficheros que la
  correccion no pudo arreglar tampoco (salvo con -Reintentar).

USO
  .\migracion.ps1 -Legacy C:\ruta\life-java8 -Migrado C:\ruta\batch-life
  .\migracion.ps1 -Legacy ... -Migrado ... -Plantilla C:\ruta\batch-terminado -Modelo <id>
  .\migracion.ps1 ... -SoloInforme     # contesta "parar" a la pregunta del final
  .\migracion.ps1 ... -Si              # contesta "corregir"
  .\migracion.ps1 ... -MaxHoras 6      # no empieza rondas nuevas pasado ese tiempo
  .\migracion.ps1 ... -Limite 5        # ensayo corto: solo las 5 primeras tareas pendientes
  .\migracion.ps1 ... -Reintentar      # repite las tareas de lectura atascadas y los ficheros atascados de la correccion
  .\migracion.ps1 ... -Practicas       # antes de la prueba en local, pasa a Lombok los getters y setters escritos a mano (un commit por fichero)
  .\migracion.ps1 ... -Reglas          # antes de la prueba en local, un test unitario por regla de negocio, comprobado cambiando su linea (un commit por test)
  .\migracion.ps1 ... -SinPruebaLocal # no hace la ultima fase (ejecutar el original y el migrado)
  .\migracion.ps1 ... -JavaLegacy C:\jdk8   # el JDK del original para prueba-local.ps1, si no compila con el de Maven
  .\migracion.ps1 ... -Lanzadores C:\ruta\scripts   # los .sh que lanzan el batch estan fuera del repo del original; se guarda en estado.json
  .\migracion.ps1 -Legacy ... -Migrado ... -Plantilla ... -Cierre   # sin IA: junta la correccion con tu rama (fast-forward) si todo esta probado

  Cierre (-Cierre, solo, sin IA): lo unico que avanza tu rama. Comprueba que la pasada esta corregida y probada (todos los jobs con casos iguales y
  ninguno distinto, sobre el codigo de ahora) y que tu carpeta no tiene cambios sin commit; si tu rama avanzo, la junta con la de rescate en la
  carpeta de rescate (un conflicto lo deja como estaba y para con el texto para Copilot); mide lo juntado (compila, tests y ningun error nuevo
  frente a tu rama) y, si el codigo cambio, repite la prueba en local; solo entonces avanza tu rama con merge --ff-only y dice como deshacerlo.
  Si algo falla, nada se mueve (parada cierre-<motivo>). Los commits que tocan src/main/resources se listan para revisarlos. No hace push.
  estado.json lleva cierre (antes, sha, cuando, juntada, hecho, deshacer, avisos y revisar) y relanzar la pasada no lo deshace.

  Salida: 0 bien (o tope de tiempo), 1 no pudo arrancar, 2 se paro (ver estado.json).
  Los ajustes de ajustes.json (y de .rescate\config.json del migrado) pisan las claves
  de CONFIGURACION (la de aqui y la de tareas.ps1); la carpeta de ajustes se cambia con
  la variable de entorno RESCATE_HOME. Antes de darlo por bueno, pasa tests\probar-migracion.ps1.
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
  [switch]$Reintentar,        # volver a intentar las tareas de lectura atascadas y los ficheros atascados de la correccion de un lanzamiento anterior
  [switch]$Practicas,         # antes de la prueba en local, pasar a Lombok los getters y setters escritos a mano (la fase practicas)
  [switch]$Reglas,            # antes de la prueba en local, escribir un test unitario por cada regla de negocio (la fase reglas)
  [switch]$SinPruebaLocal,    # no ejecutar el original y el migrado al final (la fase prueba-local)
  [string]$JavaLegacy = '',   # JAVA_HOME del original para prueba-local.ps1, si no compila con el JDK de Maven
  [string]$Lanzadores = '',   # carpeta con los .sh que lanzan el batch, si no estan en el repo del original (se guarda en estado.json)
  [switch]$Cierre             # sin IA: juntar la correccion con tu rama, por fast-forward y despues de las puertas (Invoke-Cierre); va solo
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'comun.ps1')
. (Join-Path $PSScriptRoot 'tareas.ps1')
. (Join-Path $PSScriptRoot 'informe.ps1')
. (Join-Path $PSScriptRoot 'lanzadores.ps1')
. (Join-Path $PSScriptRoot 'practicas.ps1')
. (Join-Path $PSScriptRoot 'propiedades.ps1')
. (Join-Path $PSScriptRoot 'huella.ps1')
. (Join-Path $PSScriptRoot 'arreglo-practicas.ps1')
. (Join-Path $PSScriptRoot 'tests-reglas.ps1')

# ============================ CONFIGURACION ============================
$Cfg += @{
  Modelos            = @('claude-sonnet-5.5', 'gpt-6-luna', 'gpt-6.1-terra', 'gpt-6.1-sol', 'gpt-6-astra', 'claude-haiku-5.5', 'gemini-3.8-flash')
  FallosSeguidos     = 6      # llamadas fallidas seguidas antes de parar
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

# Una hora de estado.json como texto 's': PowerShell 7 lee las fechas ISO de un JSON como fecha y al escribirlas cambiaria el formato.
function Get-HoraTexto($V) {
  if ($V -is [datetime]) { return $V.ToString('s') }
  return [string]$V
}

# ============================ AJUSTES Y ESTADO ============================
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

# Las seis paginas del informe (index.html, 1-batch-original.html, 2-problemas.html, 3-original-vs-migrado.html, 4-correcciones.html y 5-buenas-practicas.html) con lo que haya hasta ahora. Si no se pueden montar,
# se avisa y la pasada sigue: son una vista de los datos, no parte del trabajo.
function Save-Informes {
  try { Write-Informes -Salida $Salida }
  catch { Aviso ('No he podido escribir las paginas del informe: ' + $_.Exception.Message) }
}

# Para el trabajo y lo deja en estado.json con un texto de ayuda para pegar en Copilot.
function Set-Parada([string]$Motivo, [string]$Detalle, [string]$Registro) {
  $ayuda = "Estoy ejecutando migracion.ps1 (migracion desatendida de un batch Java con GitHub Copilot CLI) y se ha parado. Motivo: $Motivo. Detalle: $Detalle. El registro esta en: $Registro. Dime que ha pasado y que tengo que hacer para arreglarlo. Despues vuelvo a lanzar el mismo comando y sigue donde se quedo."
  $Estado['parada'] = [ordered]@{ motivo = $Motivo; detalle = $Detalle; registro = $Registro; ayuda = $ayuda }
  Save-Estado
  Save-Informes
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

# ================================= FASES =================================
# El diagnostico (sin IA): rescate.ps1 -Modo diagnostico lee el migrado en el worktree y sus hallazgos se copian a datos\ como
# hallazgos-<Cuando>.json y diagnostico-<Cuando>.md ($Cuando es antes o despues), con su registro. A continuacion se mide la cobertura de
# tests (datos\cobertura-<Cuando>.json y su registro; un Maven mas, salvo que el migrado no compile) y las buenas practicas
# (datos\practicas-<Cuando>.json y su registro, con Invoke-Practicas de practicas.ps1: javac, Lombok y el texto de Java 21, hasta
# $Cfg.SegundosPracticas s; nunca para el diagnostico: lo que no se pueda medir lo dice el JSON). Si el motor falla, parada 'motor'
# y devuelve $false.
function Invoke-DiagnosticoMotor([string]$Cuando) {
  $hMotor = Join-Ruta $RepoRoot '.rescate/hallazgos.json'
  $mMotor = Join-Ruta $RepoRoot '.rescate/diagnostico.md'
  if (Test-Path -LiteralPath $hMotor) { Remove-Item -LiteralPath $hMotor -Force }
  $r = Invoke-Nativo (Get-PowerShellExe) @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'rescate.ps1'), '-Modo', 'diagnostico', '-Repo', $RepoRoot, '-Plantilla', $PlantillaRoot, '-Si')
  $registro = Join-Path $Registros "diagnostico-$Cuando.log"
  Save-Registro $registro $r.Salida
  if ($r.Codigo -ne 0 -or -not (Test-Path -LiteralPath $hMotor) -or -not (Test-Path -LiteralPath $mMotor)) {
    $ultimas = Get-UltimasLineas $r.Salida
    $que = 'el diagnostico'
    $motivo = 'motor'
    if ($Cuando -eq 'despues') { $que = 'el diagnostico de despues' }
    elseif ($Cuando -eq 'cierre') { $que = 'el diagnostico del cierre'; $motivo = 'cierre-motor' }
    Set-Parada $motivo "$que (rescate.ps1 -Modo diagnostico) ha salido con codigo $($r.Codigo): $ultimas" $registro
    $script:Parada = $true
    return $false
  }
  # la cobertura va antes que los hallazgos: si se corta aqui, relanzar repite el diagnostico entero
  $compila = ((Get-EstadoBuild ([System.IO.File]::ReadAllText($mMotor, $Utf8))) -cne 'compila: NO')
  $cob = Get-Cobertura $RepoRoot (Join-Path $Registros "cobertura-$Cuando.log") $compila
  Write-Json (Join-Path $Datos "cobertura-$Cuando.json") $cob
  if ($cob.medida) { Info "Cobertura ($Cuando): $("$($cob.porcentaje)".Replace('.', ',')) % de las lineas ($($cob.cubiertas) de $($cob.total))." }
  else { Aviso "Cobertura ($Cuando): no se ha podido medir: $($cob.motivo)" }
  # las buenas practicas van despues de la cobertura y antes de los hallazgos (el motor aun los tiene en .rescate\: paso2 los lee de ahi)
  Invoke-Practicas $RepoRoot $PlantillaRoot $Cuando $Datos $Registros $hMotor
  # el .json el ultimo: es el que dice que la fase esta hecha
  foreach ($par in @(@($mMotor, "diagnostico-$Cuando.md"), @($hMotor, "hallazgos-$Cuando.json"))) {
    $destino = Join-Path $Datos $par[1]
    Copy-Item -LiteralPath $par[0] -Destination ($destino + '.tmp') -Force
    Move-Item -LiteralPath ($destino + '.tmp') -Destination $destino -Force
  }
  return $true
}

# La salida de un proceso sin los colores de la consola.
function Get-SinColor($Salida) { return @($Salida | ForEach-Object { [regex]::Replace("$_", '\x1b\[[0-9;]*m', '') }) }

# Las 3 ultimas lineas con texto de la salida de un proceso, sin colores y unidas con ' / '.
function Get-UltimasLineas($Salida) { return (@(Get-SinColor $Salida | Where-Object { $_.Trim() } | Select-Object -Last 3) -join ' / ') }

# Lanza un script de esta carpeta con PowerShell y deja que su salida salga por la consola linea a linea mientras corre (Invoke-Nativo la
# guardaria hasta el final). Devuelve su codigo y su salida.
function Invoke-EnVivo([string]$Nombre, [string[]]$Argumentos) {
  $a = @('-NoProfile', '-File', (Join-Path $PSScriptRoot $Nombre)) + $Argumentos
  $eap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $lineas = @(& (Get-PowerShellExe) @a 2>&1 | ForEach-Object { $l = "$_"; Write-Host $l; $l })
    return [pscustomobject]@{ Codigo = $LASTEXITCODE; Salida = $lineas }
  }
  finally { $ErrorActionPreference = $eap }
}

function Save-Registro([string]$Ruta, $Salida) {
  [System.IO.File]::WriteAllText($Ruta, ((Get-SinColor $Salida) -join "`n") + "`n", $Utf8)
}

# Lo que se aparta (rutas desde la carpeta de salida) cuando la correccion se hace otra vez: la correccion anterior con sus datos de despues y sus
# registros. Cuando se hace otra vez el diagnostico de antes ($ApartarAlRehacer), tambien el diagnostico viejo. Un informe con una correccion
# de otro punto de partida mezclaria dos cosas.
$ApartarCorreccion = @(
  'datos/correcciones.json', 'datos/hallazgos-despues.json', 'datos/diagnostico-despues.md', 'datos/cobertura-despues.json', 'datos/practicas-despues.json',
  'registros/correccion.log', 'registros/diagnostico-despues.log', 'registros/cobertura-despues.log', 'registros/practicas-despues.log'
)
$ApartarAlRehacer = @(
  'datos/diagnostico-antes.json', 'datos/hallazgos-antes.json', 'datos/diagnostico-antes.md', 'datos/cobertura-antes.json', 'datos/practicas-antes.json'
) + $ApartarCorreccion

# Mueve lo que haya de $Rels a datos\anterior-<$V7> (con -2, -3... si ya existe) y devuelve esa carpeta como 'datos\anterior-...'.
function Move-Apartado([string[]]$Rels, [string]$V7) {
  $apartado = Join-Path $Datos "anterior-$V7"
  for ($n = 2; Test-Path -LiteralPath $apartado; $n++) { $apartado = Join-Path $Datos "anterior-$V7-$n" }
  [void](New-Item -ItemType Directory -Path $apartado)
  foreach ($rel in $Rels) {
    $de = Join-Ruta $Salida $rel
    if (Test-Path -LiteralPath $de) { Move-Item -LiteralPath $de -Destination (Join-Path $apartado (Split-Path $rel -Leaf)) -Force }
  }
  return ('datos\' + (Split-Path $apartado -Leaf))
}

# La fase diagnostico: el diagnostico de antes, con el commit del migrado que midio (datos\diagnostico-antes.json). Se salta si ya esta con el
# mismo commit (relanzar no repite Maven). Con otro commit, o sin el dato (de antes de guardarlo), se hace otra vez y lo de antes y la
# correccion anterior quedan en datos\anterior-<commit7>\. El worktree, donde se mide, avanza hasta tu commit si puede (solo hacia delante).
function Invoke-FaseDiagnostico {
  $commit = Get-Head $MigradoRoot
  if (Test-Path -LiteralPath (Join-Path $Datos 'hallazgos-antes.json')) {
    $sucio = @((Invoke-Git $MigradoRoot @('status', '--porcelain')).Salida | Where-Object { $_ })
    if ($sucio.Count -gt 0) { Aviso "Tienes $($sucio.Count) cambios sin commit en ${MigradoRoot}: el diagnostico mide tu ultimo commit ($($commit.Substring(0, 7))) y no los cuenta. Haz commit para que cuenten." }
    $viejo = ''
    $guardado = Join-Path $Datos 'diagnostico-antes.json'
    if (Test-Path -LiteralPath $guardado) { try { $viejo = [string](Read-Json $guardado).commit } catch { $viejo = '' } }
    if ($viejo -ceq $commit) { return }
    if ($previo.cierre.hecho -eq $true -and $commit -ceq [string]$previo.cierre.sha) { return }   # el commit que junto -Cierre no es un cambio tuyo
    $v7 = 'sin-commit'
    if ($viejo.Length -ge 7) { $v7 = $viejo.Substring(0, 7) }
    $donde = Move-Apartado $ApartarAlRehacer $v7
    if ($viejo) { Info "Tu rama ha cambiado desde el ultimo diagnostico ($v7 -> $($commit.Substring(0, 7))): lo hago otra vez y lo de la correccion anterior queda en $donde." }
    else { Info "El ultimo diagnostico no dice con que commit se hizo: lo hago otra vez y lo de la correccion anterior queda en $donde." }
    $wt = Get-Head $RepoRoot
    if ($wt -cne $commit) {
      [void](Invoke-Git $RepoRoot @('merge', '--ff-only', $commit))
      $wt = Get-Head $RepoRoot
      if ($wt -cne $commit) { Aviso "El worktree de rescate no esta en tu commit ($($wt.Substring(0, 7)) frente a $($commit.Substring(0, 7))): lo que se mide es el worktree, con los arreglos de su rama. Une la rama de rescate a la tuya para que midan lo mismo." }
    }
  }
  $Estado['fase'] = 'diagnostico'
  Save-Estado
  [void](Get-JobsContrato)
  if (-not (Invoke-DiagnosticoMotor 'antes')) { return }
  Write-Json (Join-Path $Datos 'diagnostico-antes.json') ([ordered]@{ commit = $commit })
  Save-Informes
  $d = Read-Diagnostico $Datos
  Info "Diagnostico: $($d.Errores) errores y $($d.Avisos) avisos. Detalle: $(Join-Path $Salida '2-problemas.html')"
}

# Una fase: rondas de hasta Paralelo llamadas hasta que no quedan tareas pendientes, hay una parada o se llega
# al -Limite (que cuenta tareas de todas las fases). Tras cada ronda: worktree limpio y sin commits de la IA, y original y referencia
# sin cambios. Los contadores son del script ($script:Parada, Racha, Rondas e Iniciadas): las fases los comparten.
function Invoke-Fase($Tareas) {
  while (-not $script:Parada) {
    $pend = @($Tareas | Where-Object { $_.estado -eq 'pendiente' })
    if ($pend.Count -eq 0) { break }
    if ($MaxHoras -gt 0 -and $script:Rondas -gt 0 -and $reloj.Elapsed.TotalHours -ge $MaxHoras) {
      Set-Parada 'tope-de-tiempo' "Se ha llegado al tope de -MaxHoras $MaxHoras. Relanza el mismo comando para seguir." $Registros
      $script:Parada = $true
      break
    }
    $lote = @($pend | Select-Object -First ([int]$Cfg.Paralelo))
    if ($Limite -gt 0) {
      # -Limite cuenta tareas, no llamadas: una que se reintenta sigue siendo la misma
      $dentro = @()
      foreach ($x in $lote) {
        if ($script:Iniciadas.ContainsKey($x.id) -or $script:Iniciadas.Count -lt $Limite) { $script:Iniciadas[$x.id] = $true; $dentro += $x }
      }
      $lote = $dentro
      if ($lote.Count -eq 0) { break }
    }
    $head = Get-Head $RepoRoot
    $rondaRama = Get-Rama $RepoRoot
    Info ('Ronda: ' + $lote.Count + ' llamadas a la vez (quedan ' + $pend.Count + ' tareas)...')
    Save-Intento 'lectura' ($script:Rondas + 1) $head   # si el script se corta con la IA leyendo, lo que haya tocado no es de nadie: el arranque siguiente lo aparta
    $res = @(Invoke-Ronda $lote $RepoRoot $LegacyRoot)
    $script:Rondas++

    # comprobacion tras la ronda: worktree limpio y original y referencia sin cambios
    $sucio = @((Invoke-Git $RepoRoot @('status', '--porcelain')).Salida | Where-Object { $_ })
    # un commit de la IA deja el worktree limpio: se ve porque el HEAD o la rama ya no son los de antes de la ronda
    $movido = ((Get-Head $RepoRoot) -cne $head -or (Get-Rama $RepoRoot) -cne $rondaRama)
    if ($sucio.Count -gt 0 -or $movido) { Undo-Lote $rondaRama $head }
    Remove-Intento   # todo deshecho o limpio; nunca en un finally (con Ctrl+C se ejecuta y la marca tiene que quedar)
    if ((Get-Huella $LegacyRoot) -ne $H0.Legacy -or (Get-Huella $PlantillaRoot) -ne $H0.Plantilla) {
      Set-Parada 'guardas' 'Ha cambiado el original o la referencia durante una lectura. Esa carpeta no se deshace desde aqui: mira con git status y git diff, y vuelve a lanzar.' $res[0].Registro
      $script:Parada = $true
      break
    }
    foreach ($o in $res) {
      if ($o.Estado -in @('fallo', 'tiempo')) { $script:Racha++ } else { $script:Racha = 0 }
      if ($movido -and $o.Estado -in @('ok', 'invalida')) {
        $o.Estado = 'invalida'
        $o.Motivo = 'La lectura hizo un commit en el repositorio. Lee sin cambiar nada: solo escribes el fichero de salida.'
      }
      elseif ($sucio.Count -gt 0 -and $o.Estado -in @('ok', 'invalida')) {
        $o.Estado = 'invalida'
        $o.Motivo = 'La lectura toco ficheros del repositorio (' + (($sucio | Select-Object -First 3) -join '; ') + '). Lee sin cambiar nada: solo escribes el fichero de salida.'
      }
      $t = $o.Tarea
      $t.intentos++
      $t.motivo = $o.Motivo
      $t.ultimoEstado = $o.Estado
      if ($o.Estado -eq 'ok') { $t.estado = 'hecha'; $t.resultado = $o.Ficha }
      elseif ($t.intentos -ge [int]$Cfg.Intentos) {
        $t.estado = 'atascada'
        $donde = $t.entradas.fichero
        if (-not $donde) { $donde = $t.id }
        Aviso "Atascada: ${donde}: $($o.Motivo)"
      }
      Save-Tarea $t
    }
    if ($script:Racha -ge [int]$Cfg.FallosSeguidos) {
      # el fallo es de Copilot, no de las tareas: vuelven a empezar al relanzar
      foreach ($o in $res) {
        if ($o.Estado -in @('fallo', 'tiempo')) { $o.Tarea.estado = 'pendiente'; $o.Tarea.intentos = 0; Save-Tarea $o.Tarea }
      }
      $ultimo = @($res | Where-Object { $_.Estado -in @('fallo', 'tiempo') } | Select-Object -Last 1)[0]
      Set-Parada 'copilot-no-responde' "$($script:Racha) llamadas seguidas han fallado (sesion, cuota o red). Ultimo error: $($ultimo.Motivo)" $ultimo.Registro
      $script:Parada = $true
      break
    }
  }
}

function Get-TareasFase([string]$Fase, [bool]$Conservar) {
  switch ($Fase) {
    'fichas-clase' { return @(Get-TareasFichas $Fuentes $Conservar) }
    'mapa' {
      # la foto de antes de corregir: una vez escrita no se toca (la correccion cambia los ficheros de configuracion)
      if (-not (Test-Path -LiteralPath (Join-Path $Datos 'variables.json'))) { Write-Json (Join-Path $Datos 'variables.json') @(Get-Variables) }
      return @(Get-TareasDefinicion @(Get-JobsContrato) $Conservar)
    }
    'lanzadores' {
      # el inventario se escribe siempre (aunque no haya ninguno): el informe y la consola lo leen de datos\lanzadores.json
      $z = @(Get-Lanzadores $LegacyRoot $LanzadoresRoot @(Get-JobsContrato))
      Save-Lanzadores $z
      return @(Get-TareasFichaSh $z $Conservar)
    }
    'fichas-job' { return @(Get-TareasJob (Read-Json (Join-Path $Datos 'mapa.json')) $Conservar) }
    'resumen' { return @(Get-TareasResumen (Read-Json (Join-Path $Datos 'mapa.json')) $Conservar) }
    'pruebas-pre' { return @(Get-TareasPrueba (Read-Json (Join-Path $Datos 'mapa.json')) $Conservar) }
    'casos-pre' { return @(Get-TareasCaso (Read-Json (Join-Path $Datos 'mapa.json')) $Conservar) }
    'comparar' { return @(@(Get-TareasComparar $Conservar $RamaMigrado) + @(Get-TareasCompararSh $Conservar $RamaMigrado)) }
  }
}

# Lo que sale de una fase en datos\ (el mapa, solo cuando no queda ninguna tarea de definicion pendiente).
function Save-Fase([string]$Fase, $Tareas) {
  $pendientes = @($Tareas | Where-Object { $_.estado -eq 'pendiente' }).Count
  switch ($Fase) {
    'fichas-clase' { Save-Fichas $Tareas }
    'mapa' { if ($pendientes -eq 0) { Write-Json (Join-Path $Datos 'mapa.json') (Get-Mapa @(Get-JobsContrato) $Tareas $batch) } }
    'lanzadores' { Save-FichasSh $Tareas }
    'fichas-job' { Save-Jobs (Read-Json (Join-Path $Datos 'mapa.json')) $Tareas }
    'resumen' { if (@($Tareas | Where-Object { $_.estado -eq 'hecha' }).Count -gt 0) { Write-Json (Join-Path $Datos 'resumen.json') $Tareas[0].resultado } }
    'pruebas-pre' { Save-Pruebas (Read-Json (Join-Path $Datos 'mapa.json')) $Tareas }
    'casos-pre' { Save-Casos (Read-Json (Join-Path $Datos 'mapa.json')) $Tareas }
    'comparar' {
      Save-Comparaciones @($Tareas | Where-Object { $_.tipo -eq 'comparar-pieza' })
      Save-ComparacionesSh @($Tareas | Where-Object { $_.tipo -eq 'comparar-sh' })
    }
  }
}

# La linea de consola de una fase.
function Get-LineaFase([string]$Fase, $Tareas) {
  $n = Get-CuentasTareas $Tareas
  switch ($Fase) {
    'fichas-clase' { return "Lectura de clases: $($n.hecha) hechas, $($n.atascada) atascadas, $($n.pendiente) pendientes de $(@($Tareas).Count) tareas." }
    'mapa' {
      if ($n.pendiente -gt 0) { return "Mapa: $($n.pendiente) tareas de definicion pendientes." }
      $m = Read-Json (Join-Path $Datos 'mapa.json')
      $sin = @($m.sinJob).Count
      return "Mapa: $(@($m.jobs).Count) jobs, $($Fuentes.Count - $sin) clases con job, $sin sin job"
    }
    'lanzadores' { return (Get-LineaLanzadores @(Read-Lanzadores) $n) }
    'fichas-job' {
      $l = "Fichas de job: $($n.hecha) hechas, $($n.atascada) atascadas"
      if ($n.pendiente -gt 0) { $l += ", $($n.pendiente) pendientes" }
      return $l
    }
    'resumen' {
      if (@($Tareas).Count -eq 0) { return 'Resumen: ningun job redactado, nada que resumir' }
      if ($n.hecha -gt 0) { return 'Resumen: hecho' }
      if ($n.atascada -gt 0) { return 'Resumen: atascado' }
      return 'Resumen: pendiente'
    }
    'pruebas-pre' {
      if (@($Tareas).Count -eq 0) { return 'Pruebas en pre: ningun job con reglas ni errores que probar con IA' }
      $l = "Pruebas en pre: $($n.hecha) hechas, $($n.atascada) atascadas"
      if ($n.pendiente -gt 0) { $l += ", $($n.pendiente) pendientes" }
      return $l
    }
    'casos-pre' {
      if (@($Tareas).Count -eq 0) { return 'Casos de las reglas sin caso: ninguna regla sin caso' }
      $l = "Casos de las reglas sin caso: $($n.hecha) hechos, $($n.atascada) atascados"
      if ($n.pendiente -gt 0) { $l += ", $($n.pendiente) pendientes" }
      return $l
    }
    'comparar' {
      $sh = @($Tareas | Where-Object { $_.tipo -eq 'comparar-sh' })
      $Tareas = @($Tareas | Where-Object { $_.tipo -eq 'comparar-pieza' })
      $n = Get-CuentasTareas $Tareas
      if (@($Tareas).Count -eq 0) { $l = 'Comparacion con el original: ninguna clase con datos que comparar'; if ($sh.Count -gt 0) { $l += "`n" + (Get-LineaCompararSh $sh) }; return $l }
      $l = "Comparacion con el original: $($n.hecha) clases comparadas"
      if ($n.atascada -gt 0) { $l += ", $($n.atascada) atascadas" }
      if ($n.pendiente -gt 0) { $l += ", $($n.pendiente) pendientes" }
      $c = [ordered]@{ 'igual' = 0; 'distinto' = 0; 'falta' = 0; 'no-lo-se' = 0; 'sin-pieza' = 0 }
      foreach ($t in @($Tareas | Where-Object { $_.estado -eq 'hecha' })) { foreach ($d in @($t.resultado.comparacion)) { $c[[string]$d.estado]++ } }
      $l = "$l. Datos: $($c['igual']) igual, $($c['distinto']) distinto, $($c['falta']) falta, $($c['no-lo-se']) no lo se, $($c['sin-pieza']) sin pieza."
      if ($sh.Count -gt 0) { $l += "`n" + (Get-LineaCompararSh $sh) }
      return $l
    }
  }
}

# Una fase de tareas (las de lectura y comparar): sus tareas, las rondas, lo que deja en datos\, el informe y la linea de consola. Devuelve
# si se puede seguir con lo que viene despues: sin parada y sin tareas pendientes (-Limite). $script:Todas y $script:Quedan acumulan lo que
# hay al salir.
function Invoke-FaseTareas([string]$Fase) {
  $Estado['fase'] = $Fase
  Save-Estado
  $tareas = @(Get-TareasFase $Fase $conservar)
  $script:Todas += $tareas
  if ($Fase -eq 'fichas-clase') {
    $hechas0 = @($tareas | Where-Object { $_.estado -eq 'hecha' }).Count
    $ficheros = @($tareas | Group-Object { $_.ficha }).Count
    Info "Tareas de lectura: $($tareas.Count) (fichas de clase de $ficheros ficheros del original; $hechas0 ya hechas)."
    $atascadas0 = @($tareas | Where-Object { $_.estado -eq 'atascada' }).Count
    if ($atascadas0 -gt 0) { Aviso "$atascadas0 tareas atascadas de un lanzamiento anterior se conservan sin repetir. Para volver a intentarlas: -Reintentar (o cambia de modelo)." }
  }
  Invoke-Fase $tareas
  Save-Fase $Fase $tareas
  Save-Informes
  Info (Get-LineaFase $Fase $tareas)
  $script:Quedan = @($tareas | Where-Object { $_.estado -eq 'pendiente' }).Count
  return (-not $script:Parada -and $script:Quedan -eq 0)
}

# ============================== CORRECCION ==============================
# Los hallazgos de $De (un .json de datos\) que no estan en $En, comparando area, fichero y detalle (no la linea: cambiar de linea no es arreglarse
# ni estropear). Con (despues, antes) son los resueltos; con (antes, cierre), lo que el cierre trae de nuevo.
function Get-Faltantes([string]$En, [string]$De) {
  $quedan = @{}
  foreach ($h in @(Read-Json (Join-Path $Datos $En) | Where-Object { $null -ne $_ })) {
    $k = "$($h.Cat)|$($h.Fichero)|$($h.Detalle)"
    $quedan[$k] = 1 + [int]$quedan[$k]
  }
  $res = @()
  foreach ($h in @(Read-Json (Join-Path $Datos $De) | Where-Object { $null -ne $_ })) {
    $k = "$($h.Cat)|$($h.Fichero)|$($h.Detalle)"
    if ([int]$quedan[$k] -gt 0) { $quedan[$k] = [int]$quedan[$k] - 1 } else { $res += $h }
  }
  return $res
}

# Los commits de arreglo (rescate(<paso>): ...) de la rama del worktree desde la rama del migrado, en orden.
function Get-CommitsRescate {
  $res = @()
  foreach ($l in @((Invoke-Git $RepoRoot @('log', '--reverse', '--format=%h|%s', "$RamaMigrado..HEAD")).Salida)) {
    $m = [regex]::Match("$l", '^([0-9a-f]+)\|(rescate\(([^)]*)\).*)$')
    if ($m.Success) { $res += [ordered]@{ hash = $m.Groups[1].Value; paso = $m.Groups[3].Value; asunto = $m.Groups[2].Value } }
  }
  return $res
}

# Lo que el motor no pudo arreglar: una linea "- [paso] fichero: motivo (registro: ruta)" de .rescate\atascados.md. Una linea que no
# case se guarda entera en el motivo.
function Get-Atascados {
  $ruta = Join-Ruta $RepoRoot '.rescate/atascados.md'
  $res = @()
  if (-not (Test-Path -LiteralPath $ruta)) { return $res }
  foreach ($l in [System.IO.File]::ReadAllLines($ruta, $Utf8)) {
    if (-not $l.Trim()) { continue }
    $m = [regex]::Match($l, '^- \[([^\]]*)\] (.+?): (.*?)(?: \(registro: [^)]*\))?\s*$')
    if ($m.Success) { $res += [ordered]@{ paso = $m.Groups[1].Value; fichero = $m.Groups[2].Value; motivo = $m.Groups[3].Value } }
    else { $res += [ordered]@{ paso = ''; fichero = ''; motivo = $l.Trim() } }
  }
  return $res
}

# Las variables sin valor por defecto que hay ahora en el worktree y no estaban en datos\variables.json (la foto de antes de corregir).
function Get-VariablesNuevas {
  $conocidas = @()
  $f = Join-Path $Datos 'variables.json'
  if (Test-Path -LiteralPath $f) { $conocidas = @(Read-Json $f | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_.variable }) }
  $res = @()
  foreach ($v in @(Get-Variables)) {
    if ($null -ne $v.porDefecto -or $v.secreto -eq $true) { continue }
    if (($conocidas -ccontains [string]$v.variable) -or (@($res | Where-Object { $_.variable -ceq $v.variable }).Count -gt 0)) { continue }
    $res += [ordered]@{ variable = $v.variable; fichero = $v.fichero; linea = $v.linea }
  }
  return $res
}

# datos\correcciones.json: lo que paso en la corrida, con parada o sin ella.
function Save-Correcciones([int]$Codigo, [bool]$Completa) {
  $resueltos = @()
  if (Test-Path -LiteralPath (Join-Path $Datos 'hallazgos-despues.json')) { $resueltos = @(Get-Faltantes 'hallazgos-despues.json' 'hallazgos-antes.json') }
  $c = [ordered]@{
    completa = $Completa; codigo = $Codigo; rama = (Get-Rama $RepoRoot); base = $RamaMigrado
    commits = @(Get-CommitsRescate); atascados = @(Get-Atascados); resueltos = $resueltos; variablesNuevas = @(Get-VariablesNuevas)
  }
  Write-Json (Join-Path $Datos 'correcciones.json') $c
  return $c
}

# La fase correccion (tras lectura-hecha): rescate.ps1 -Modo fix -Todo arregla el worktree, se vuelve a diagnosticar y datos\correcciones.json
# lo cuenta. Con la respuesta 'parar' no se lanza. Si ya hay una correccion completa, se salta, salvo con -Reintentar y ficheros atascados: se
# lanza otra vez y rescate.ps1 recibe -Reintentar. Parada segun el codigo del motor:
# 0 completa; 2 sin compilar -> no-compila, con PARO: -> lotes-deshechos, si no completa con atascados; 3 git; 4 guardas; otro motor.
function Invoke-FaseCorreccion {
  $ruta = Join-Path $Datos 'correcciones.json'
  if (Test-Path -LiteralPath $ruta) {
    $previa = $null
    try { $previa = Read-Json $ruta } catch { $previa = $null }
    if ($previa -and $previa.completa -eq $true) {
      # completa solo vale si sus commits estan en la carpeta de rescate: si el worktree se rehizo sin unir su rama, los arreglos se quedaron en otra
      $perdidos = @(@($previa.commits) | Where-Object { $_ -and $_.hash -and (Invoke-Git $RepoRoot @('merge-base', '--is-ancestor', [string]$_.hash, 'HEAD')).Codigo -ne 0 })
      $rehacer = ($perdidos.Count -gt 0 -and $respuesta -eq 'corregir')
      if ($rehacer) {
        $h7 = ([string]$perdidos[0].hash)
        $donde = Move-Apartado $ApartarCorreccion $h7.Substring(0, [Math]::Min(7, $h7.Length))
        Info "La correccion anterior hizo sus commits en otra rama ($($previa.rama)), que no esta en la carpeta de rescate: la hago otra vez."
        Info "Lo de esa correccion queda en $donde."
      }
      $quedan = @($previa.atascados | Where-Object { $null -ne $_ }).Count
      if (-not ($rehacer -or ($Reintentar -and $quedan -gt 0))) {
        $Estado['fase'] = 'correccion'
        Save-Estado
        if ($quedan -gt 0) { Info "La correccion anterior dejo ficheros atascados ($quedan). Para volver a intentarlos: -Reintentar." }
        return
      }
    }
  }
  if ($respuesta -ne 'corregir') { Info 'No se corrige nada: has pedido parar tras el informe. Para corregir, relanza el mismo comando con -Si.'; return }
  $Estado['fase'] = 'correccion'
  Save-Estado
  $atascadas = Join-Ruta $RepoRoot '.rescate/atascados.md'
  if (Test-Path -LiteralPath $atascadas) { Remove-Item -LiteralPath $atascadas -Force }
  Info 'Correccion: corrigiendo el migrado con rescate.ps1 -Modo fix (un fichero por llamada; puede tardar horas)...'
  $a = @('-Modo', 'fix', '-Todo', '-Si', '-Lote', '1', '-Repo', $RepoRoot, '-Plantilla', $PlantillaRoot, '-Legacy', $LegacyRoot, '-Esfuerzo', 'medium', '-EsfuerzoPlan', 'high')
  if ($ModeloElegido) { $a += @('-Modelo', $ModeloElegido) }
  if ($Reintentar) { $a += '-Reintentar' }
  $r = Invoke-EnVivo 'rescate.ps1' $a
  $registro = Join-Path $Registros 'correccion.log'
  Save-Registro $registro $r.Salida
  $diagnosticado = $true
  if ($r.Codigo -ne 1) { $diagnosticado = Invoke-DiagnosticoMotor 'despues' }
  $motivo = ''
  $detalle = ''
  switch ($r.Codigo) {
    0 { }
    2 {
      $d = Read-Diagnostico $Datos 'despues'
      if ($d -and $d.Estado -ceq 'compila: NO') { $motivo = 'no-compila'; $detalle = 'Despues de corregir, el migrado no compila. Los arreglos estan en la rama del worktree: mira el registro.' }
      elseif (@(Get-SinColor $r.Salida | Where-Object { $_ -match '^\s*PARO:' }).Count -gt 0) { $motivo = 'lotes-deshechos'; $detalle = '6 lotes seguidos deshechos: suele ser Copilot, Maven o un flag, no el codigo.' }
    }
    3 { $motivo = 'git'; $detalle = 'El motor no ha podido hacer un commit de arreglo (git commit ha fallado).' }
    4 { $motivo = 'guardas'; $detalle = 'El motor ha visto cambiar el original o la referencia durante los arreglos. Mira con git status y git diff, y vuelve a lanzar.' }
    default {
      $motivo = 'motor'
      $detalle = "el motor de arreglos (rescate.ps1 -Modo fix) ha salido con codigo $($r.Codigo): $(Get-UltimasLineas $r.Salida)"
    }
  }
  $c = Save-Correcciones $r.Codigo ($diagnosticado -and -not $motivo)
  if ($motivo) { Set-Parada $motivo $detalle $registro; $script:Parada = $true }
  # 'actualizado' se escribio al empezar: sin esto la portada dice que la pasada llevo lo de antes de corregir
  Save-Estado
  Save-Informes
  if ($diagnosticado -and -not $motivo) {
    Info "Correccion: $(@($c.commits).Count) commits de arreglo y $(@($c.atascados).Count) atascados. Detalle: $(Join-Path $Salida '4-correcciones.html')"
    if (@($c.atascados).Count -gt 0) { Aviso "Lo que el motor no ha podido arreglar esta en la pagina 4-correcciones.html y en $(Join-Path $Salida 'datos/correcciones.json')." }
  }
}

# ============================== PRUEBA EN LOCAL ==============================
# La fase prueba-local (la ultima): prueba-local.ps1 ejecuta el original y el migrado con las mismas entradas y deja datos\prueba-local.json;
# su salida sale por la consola y queda en registros\prueba-local.log. Siempre se lanza (al relanzar, prueba-local.ps1 ya reutiliza lo
# hecho); con -SinPruebaLocal se salta. Sale con 0 (todo igual) o 2 (hay distintos): las dos son hecha. Un fallo no para la pasada: se avisa
# y se sigue. estado.pruebaLocal lo cuenta.
function Invoke-FasePruebaLocal {
  if ($SinPruebaLocal) {
    $Estado['pruebaLocal'] = [ordered]@{ resultado = 'saltada'; codigo = $null; minutos = 0; detalle = ''; jdkOriginal = $false; registro = '' }
    return
  }
  $Estado['fase'] = 'prueba-local'
  Save-Estado
  Save-Informes
  Info 'Prueba en local: ejecutando el original y el migrado con las mismas entradas (prueba-local.ps1; puede tardar)...'
  $a = @('-Legacy', $LegacyRoot, '-Migrado', $MigradoRoot, '-Si')
  if ($ModeloElegido) { $a += @('-Modelo', $ModeloElegido) }
  if ($JavaLegacy) { $a += @('-JavaLegacy', $JavaLegacy) }
  $cronometro = [System.Diagnostics.Stopwatch]::StartNew()
  $r = Invoke-EnVivo 'prueba-local.ps1' $a
  $minutos = [Math]::Round($cronometro.Elapsed.TotalMinutes, 1)
  $registro = Join-Path $Registros 'prueba-local.log'
  Save-Registro $registro $r.Salida
  $hecha = ($r.Codigo -eq 0 -or $r.Codigo -eq 2)
  $detalle = ''
  if (-not $hecha) { $detalle = Get-UltimasLineas $r.Salida }
  $resultado = 'fallo'
  if ($hecha) { $resultado = 'hecha' }
  # el original que no compila con el JDK de Maven: prueba-local.ps1 lo dice en su primera linea de error y el detalle solo guarda las ultimas
  $jdk = ((-not $hecha) -and (@(Get-SinColor $r.Salida | Where-Object { $_ -match 'no compila con el JDK de Maven' }).Count -gt 0))
  $Estado['pruebaLocal'] = [ordered]@{ resultado = $resultado; codigo = $r.Codigo; minutos = $minutos; detalle = $detalle; jdkOriginal = $jdk; registro = 'registros/prueba-local.log' }
  $json = Join-Path $Datos 'prueba-local.json'
  if (-not $hecha) { Aviso "Prueba en local: ha salido con codigo $($r.Codigo): $detalle. Registro: $registro" }
  elseif (Test-Path -LiteralPath $json) {
    $jobs = @((Read-Json $json).jobs)
    $n = @{}
    foreach ($k in @('casos', 'iguales', 'distintos')) { $n[$k] = [int](($jobs | Measure-Object -Property $k -Sum).Sum) }
    Info "Prueba en local: $($n.casos) casos, $($n.iguales) iguales, $($n.distintos) distintos ($("$minutos".Replace('.', ',')) min). Detalle: $(Join-Path $Salida '3-original-vs-migrado.html')"
  }
}

# ================================== CIERRE ==================================
# migracion.ps1 -Cierre: juntar la correccion con tu rama sin IA. Como la cola de merge de GitHub, se prueba el resultado en una rama aparte (aqui, la
# carpeta de rescate) y solo si pasa todo avanza tu rama, por fast-forward. Propiedad: si una puerta falla, no se mueve ni tu rama ni la de rescate.
# Las areas del diagnostico donde un error nuevo para el cierre; lo demas se avisa.
$AreasPuertas = @('build', 'estructura', 'hexagonal', 'ficheros', 'config', 'tests')

# Deja la carpeta de rescate en $Sha, como estaba antes de juntar (aborta un merge a medias). Dice si ha quedado en $Sha y limpia.
function Restore-Rescate([string]$Sha) {
  [void](Invoke-Git $RepoRoot @('merge', '--abort'))
  [void](Invoke-Git $RepoRoot @('reset', '--hard', $Sha))
  return ((Get-Head $RepoRoot) -ceq $Sha -and @(Get-SinCommit $RepoRoot).Count -eq 0)
}

# Para el cierre (parada cierre-$Motivo) y sale con 2. Con $AntesWt, deja antes la carpeta de rescate en ese commit.
function Stop-Cierre([string]$Motivo, [string]$Detalle, [string]$AntesWt = '', [string]$Registro = '') {
  if ($AntesWt -and -not (Restore-Rescate $AntesWt)) { $Detalle += " ATENCION: no he podido dejar la carpeta de rescate en $($AntesWt.Substring(0, 7)) y limpia: mira git -C `"$RepoRoot`" status." }
  if (-not $Registro) { $Registro = $Registros }
  Set-Parada "cierre-$Motivo" $Detalle $Registro
  return 2
}

# Hay cambios en src/main o en el pom entre el commit que probo la prueba en local y el HEAD de la carpeta de rescate? Un commit que git no conoce, o
# sin dato, cuenta como cambio.
function Test-CodigoCambiado([string]$Probado) {
  if (-not $Probado) { return $true }
  return ((Invoke-Git $RepoRoot @('diff', '--quiet', $Probado, 'HEAD', '--', 'src/main', 'pom.xml')).Codigo -ne 0)
}

# Lo que falta para dar por buena la prueba en local: sus dos arneses hechos y, en cada job de mapa.json, algun caso igual y ninguno distinto.
function Get-FallosPruebaLocal($Pl, $Mapa) {
  if (-not $Pl) { return @('no hay datos\prueba-local.json: la pasada no hizo la prueba en local') }
  $f = @()
  foreach ($a in @('original', 'migrado')) { if ([string]$Pl.arneses.$a -cne 'hecha') { $f += "el arnes del $a no esta hecho" } }
  foreach ($j in @($Mapa.jobs | Where-Object { $null -ne $_ })) {
    $p = @($Pl.jobs | Where-Object { [string]$_.job -ceq [string]$j.job })
    if ($p.Count -eq 0 -or [int]$p[0].iguales -lt 1) { $f += "el job $($j.job) no tiene ningun caso igual" }
    if ($p.Count -gt 0 -and [int]$p[0].distintos -gt 0) { $f += "el job $($j.job) tiene $([int]$p[0].distintos) casos distintos" }
  }
  return $f
}

function Get-TextoHallazgo($H) { return "$($H.Cat): $($H.Fichero):$($H.Linea) $($H.Detalle)" }

# El cierre entero. Devuelve el codigo de salida: 0 si ha juntado o ya estaba juntado (o no habia nada), 2 si para.
function Invoke-Cierre {
  $previa = $Estado['cierre']
  if ($previa -and $previa.hecho -eq $true -and (Get-Head $MigradoRoot) -ceq [string]$previa.sha) {
    Info "Ya esta juntado ($(([string]$previa.sha).Substring(0, 7))). Para deshacer: $($previa.deshacer)"
    return 0
  }
  # 1. Precondiciones: la primera que falla para sin tocar nada
  $D = Read-DatosInforme $Salida
  $paso = Get-SiguientePaso $Estado $D
  if ($paso.Caso -cne 'corregido' -and $paso.Caso -cne 'pre') {
    $t = "La pasada no esta lista para juntar (caso $($paso.Caso))."
    if ($paso.Comando) { $t += " Lo que toca antes:`n$($paso.Comando)" }
    return (Stop-Cierre 'pendiente' $t)
  }
  if ([int]((Invoke-Git $RepoRoot @('rev-list', '--count', "$RamaMigrado..HEAD")).Salida -join '') -eq 0) {
    Info "No hay nada que juntar: la rama de rescate no tiene commits que no esten ya en tu rama ($RamaMigrado)."
    return 0
  }
  $mal = @(Get-FallosPruebaLocal $D.PruebaLocal $D.Mapa)
  if ($mal.Count -gt 0) { return (Stop-Cierre 'prueba-local' ('La prueba en local no da para juntar: ' + ($mal -join '; ') + '.')) }
  # si tu rama ya estaba en lo probado y el codigo ha cambiado, lo cambio alguien en la carpeta de rescate; si tu rama avanzo (o se junto a mano), se repite la prueba mas abajo
  $probado = [string]$D.PruebaLocal.commitMigrado
  $cambiado = Test-CodigoCambiado $probado
  if ($cambiado -and (Invoke-Git $RepoRoot @('merge-base', '--is-ancestor', $RamaMigrado, $probado)).Codigo -eq 0) {
    return (Stop-Cierre 'prueba-local' 'el codigo ha cambiado desde la prueba en local: relanza la pasada.')
  }
  $sucio = @(Get-SinCommit $MigradoRoot)
  if ($sucio.Count -gt 0) { return (Stop-Cierre 'cambios-sin-commit' "Tu carpeta tiene cambios sin commit ($(Get-ListaFicheros $sucio)): haz commit o stash y vuelve a lanzar.") }

  # 2. Si tu rama avanzo, se junta en la carpeta de rescate, nunca en la tuya
  $antesWt = Get-Head $RepoRoot
  $juntada = ((Invoke-Git $RepoRoot @('merge-base', '--is-ancestor', $RamaMigrado, 'HEAD')).Codigo -ne 0)
  if ($juntada) {
    Info "Tu rama ($RamaMigrado) ha avanzado desde la pasada: la junto con la de rescate en $RepoRoot, no en tu carpeta."
    $m = Invoke-Git $RepoRoot @('merge', '--no-ff', '--no-edit', $RamaMigrado)
    if ($m.Codigo -ne 0) {
      $choques = @((Invoke-Git $RepoRoot @('diff', '--name-only', '--diff-filter=U')).Salida | Where-Object { $_ })
      $que = Get-UltimasLineas $m.Salida
      if ($choques.Count -gt 0) { $que = Get-ListaFicheros $choques }
      return (Stop-Cierre 'conflicto' ("Al juntar tu rama ($RamaMigrado) con la de rescate no se puede solo: $que. No he cambiado nada. Para pegar en Copilot: junta la rama $RamaMigrado en la carpeta $RepoRoot " +
        "(git merge $RamaMigrado), respeta los cambios de los dos lados, haz commit y lanza otra vez: .\migracion.ps1 -Legacy `"$LegacyRoot`" -Migrado `"$MigradoRoot`" -Plantilla `"$PlantillaRoot`" -Cierre") $antesWt)
    }
    $cambiado = Test-CodigoCambiado $probado
  }

  # 3. Las puertas, sobre el HEAD de la carpeta de rescate: no peor que tu rama
  Info 'Puertas: mido lo que se va a juntar (diagnostico, cobertura y buenas practicas)...'
  if (-not (Invoke-DiagnosticoMotor 'cierre')) { [void](Restore-Rescate $antesWt); return 2 }
  $estadoCierre = Get-EstadoBuild ([System.IO.File]::ReadAllText((Join-Path $Datos 'diagnostico-cierre.md'), $Utf8))
  $estadoAntes = Get-EstadoBuild ([System.IO.File]::ReadAllText((Join-Path $Datos 'diagnostico-antes.md'), $Utf8))
  $fallos = @()
  if ($estadoCierre -cnotlike 'compila: SI*') { $fallos += "no compila o no se ha podido comprobar (el diagnostico dice '$estadoCierre')" }
  if ($estadoCierre -ceq 'compila: SI | tests: FALLAN' -and $estadoAntes -cne $estadoCierre) { $fallos += 'los tests fallan y en tu rama no fallaban' }
  foreach ($h in @(Get-Faltantes 'hallazgos-antes.json' 'hallazgos-cierre.json' | Where-Object { $_.Sev -ceq 'error' -and $AreasPuertas -ccontains [string]$_.Cat })) { $fallos += ('error nuevo: ' + (Get-TextoHallazgo $h)) }
  if ($fallos.Count -gt 0) { return (Stop-Cierre 'puertas' ('Lo juntado no pasa las puertas: ' + ($fallos -join '; ') + '. No he movido nada.') $antesWt (Join-Path $Registros 'diagnostico-cierre.log')) }
  if ($cambiado) {
    if ($SinPruebaLocal) { return (Stop-Cierre 'puertas' 'Lo juntado cambia el codigo y hay que repetir la prueba en local: lanza -Cierre sin -SinPruebaLocal.' $antesWt) }
    Info 'Lo juntado cambia el codigo que se probo: repito la prueba en local.'
    $fase = $Estado['fase']
    Invoke-FasePruebaLocal
    $Estado['fase'] = $fase
    $mal = @("la prueba en local ha salido con fallo: $($Estado['pruebaLocal'].detalle)")
    if ([string]$Estado['pruebaLocal'].resultado -ceq 'hecha') { $mal = @(Get-FallosPruebaLocal (Read-JsonSuave (Join-Path $Datos 'prueba-local.json')) $D.Mapa) }
    if ($mal.Count -gt 0) { return (Stop-Cierre 'puertas' ('La prueba en local repetida con lo juntado no sale igual: ' + ($mal -join '; ') + '. No he movido nada.') $antesWt) }
  }
  # lo que no para se avisa: los errores que ya estaban o de otras areas y las incidencias de limpieza
  $avisos = @(@(Read-Json (Join-Path $Datos 'hallazgos-cierre.json') | Where-Object { $_.Sev -ceq 'error' }) | ForEach-Object { Get-TextoHallazgo $_ })
  $prac = Read-JsonSuave (Join-Path $Datos 'practicas-cierre.json')
  foreach ($i in @($prac.incidencias | Where-Object { $_ -and $_.area -ceq 'limpieza' })) { $avisos += "limpieza: $($i.fichero):$($i.linea) $($i.texto)" }
  if ($avisos.Count -gt 0) {
    Aviso "Avisos que no paran el cierre ($($avisos.Count); todos en estado.json, cierre.avisos):"
    foreach ($a in @($avisos | Select-Object -First 10)) { Info "  $a" }
  }

  # 4. Avanzar tu rama: antes se apunta como deshacerlo
  $sha = Get-Head $RepoRoot
  $antes = Get-Head $MigradoRoot
  $revisar = @()
  foreach ($l in @((Invoke-Git $RepoRoot @('log', '--format=%h|%s', "$antes..$sha", '--', 'src/main/resources')).Salida)) {
    $r = [regex]::Match("$l", '^([0-9a-f]+)\|(.*)$')
    if ($r.Success) { $revisar += [ordered]@{ hash = $r.Groups[1].Value; asunto = $r.Groups[2].Value } }
  }
  $deshacer = 'git -C "' + $MigradoRoot + '" reset --hard ' + $antes
  $Estado['cierre'] = [ordered]@{ antes = $antes; sha = $sha; cuando = (Get-Date).ToString('s'); juntada = $juntada; hecho = $false; deshacer = $deshacer; avisos = @($avisos); revisar = @($revisar) }
  Save-Estado
  $ff = Invoke-Git $MigradoRoot @('merge', '--ff-only', (Get-Rama $RepoRoot))
  if ($ff.Codigo -ne 0 -or (Get-Head $MigradoRoot) -cne $sha) {
    $Estado['cierre'] = $previa
    return (Stop-Cierre 'no-ff' ("Tu rama ($RamaMigrado) ha cambiado mientras se median las puertas y ya no avanza por fast-forward: " + (Get-UltimasLineas $ff.Salida) + ". Tu carpeta no ha cambiado. Vuelve a lanzar -Cierre.") $antesWt)
  }
  $Estado['cierre']['hecho'] = $true
  Save-Estado

  # 5. Lo que hay que revisar antes del push, y como acaba
  $n = [int]((Invoke-Git $RepoRoot @('rev-list', '--count', "$antes..$sha")).Salida -join '')
  if ($revisar.Count -gt 0) {
    Aviso 'Estos commits tocan la configuracion: revisalos antes de hacer push:'
    foreach ($c in $revisar) { Info "  $($c.hash) $($c.asunto)" }
  }
  Bien "Juntado: $n commits en $RamaMigrado ($($antes.Substring(0, 7))..$($sha.Substring(0, 7)))."
  Info "Para deshacerlo: $deshacer"
  Info 'No hago push: el push es tuyo.'
  Save-Informes
  return 0
}

# Una excepcion que nadie esperaba: se deja en estado.json para que el relanzamiento no sea a ciegas, y sale con 2.
function Stop-ErrorInterno($Ex) {
  $donde = ''
  if ($Ex.InvocationInfo -and $Ex.InvocationInfo.ScriptName) { $donde = ' (' + (Split-Path $Ex.InvocationInfo.ScriptName -Leaf) + ':' + $Ex.InvocationInfo.ScriptLineNumber + ')' }
  try { $Estado['fin'] = (Get-Date).ToString('s'); Set-Parada 'error-interno' ($Ex.Exception.Message + $donde) $Registros }
  catch { Fallo ('Error interno: ' + $Ex.Exception.Message + $donde + ' (y no he podido escribir estado.json: ' + $_.Exception.Message + ')') }
  exit 2
}

# ================================= MAIN =================================
$reloj = [System.Diagnostics.Stopwatch]::StartNew()
if (-not $Legacy) { Stop-Arranque 'Falta -Legacy: la carpeta del batch original (Java 8).' }
if ($SoloInforme -and $Si) { Stop-Arranque 'Usa -SoloInforme o -Si, no los dos.' }
if ($Cierre -and ($SoloInforme -or $Si -or $Practicas -or $Reglas -or $Reintentar)) { Stop-Arranque '-Cierre va solo: no lo mezcles con -SoloInforme, -Si, -Practicas, -Reglas ni -Reintentar.' }
$respondeSi = [bool]$Si

# 1. Herramientas y repos (antes, los ajustes: pueden cambiar donde estan)
$ajustes = Read-CfgFile (Get-RutaAjustes) (Get-ClavesAjustes $PSScriptRoot)   # ajustes.json es de todos los scripts: solo avisa de lo que no es de ninguno
foreach ($x in @(@('git', 'git'), @('java', $Cfg.JavaExe), @('Copilot', $Cfg.CopilotExe))) {
  if (-not (Get-Command $x[1] -ErrorAction SilentlyContinue)) { Stop-Arranque "No encuentro $($x[0]) ('$($x[1])') en el PATH." }
}
$LegacyRoot = Get-Repo $Legacy '-Legacy'
$MigradoRoot = Get-Repo $Migrado '-Migrado'
$RamaMigrado = Get-Rama $MigradoRoot
if (-not $RamaMigrado -or $RamaMigrado -eq 'HEAD') { Stop-Arranque "El migrado no esta en una rama (HEAD suelto): $MigradoRoot. Cambia a una rama y vuelve a lanzar." }
Read-Config $MigradoRoot $false    # config.json es de rescate.ps1: lleva claves que migracion.ps1 no conoce
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
# la carpeta de rescate, si ya existe (la de este repo y su rama rescate/)
$OrigenRoot = $MigradoRoot
$Worktree = ''
$dirWt = Get-DirRescate
$hayWt = Test-WorktreeRescate $dirWt
# -Cierre junta lo que dejo una pasada: sin su estado o sin su carpeta de rescate no hay nada que juntar (antes de preguntar nada)
if ($Cierre -and (-not $previo -or -not $hayWt)) { Stop-Arranque 'No hay nada que juntar: lanza antes la pasada.' }
# la carpeta de los .sh: la que se da, o la del lanzamiento anterior si ya no esta en la linea de comandos
$LanzadoresRoot = ''
if ($Lanzadores) {
  if (-not (Test-Path -LiteralPath $Lanzadores -PathType Container)) { Stop-Arranque "-Lanzadores no es una carpeta que exista: $Lanzadores" }
  $LanzadoresRoot = Resolve-Dir $Lanzadores
}
elseif ($previo -and $previo.lanzadores) {
  $LanzadoresRoot = [string]$previo.lanzadores
  if (-not (Test-Path -LiteralPath $LanzadoresRoot -PathType Container)) { Aviso "La carpeta de -Lanzadores del lanzamiento anterior ya no existe ($LanzadoresRoot): sigo sin ella."; $LanzadoresRoot = '' }
}

# 3. Modelo: -Modelo, el del lanzamiento anterior o el menu
if ($PSBoundParameters.ContainsKey('Modelo')) { $ModeloElegido = $Modelo }
elseif ($previo -and ($null -ne $previo.modelo)) { $ModeloElegido = [string]$previo.modelo }
else { $ModeloElegido = Select-Modelo }
if ($ModeloElegido) { Info "Modelo: $ModeloElegido" } else { Info 'Modelo: el que tenga Copilot' }
# las tareas atascadas de antes se conservan si el modelo es el mismo y no se pide -Reintentar
$conservar = [bool]((-not $Reintentar) -and $previo -and ([string]$previo.modelo -ceq $ModeloElegido))
$H0 = [pscustomobject]@{ Legacy = (Get-Huella $LegacyRoot); Plantilla = (Get-Huella $PlantillaRoot) }

# 4. La carpeta de rescate, si ya existe. Lo que haya sin commit en ella no se borra nunca: lo de un intento cortado va a un git stash (como en
# rescate.ps1) y todo lo demas (un arreglo a mano, lo de otra herramienta) para el arranque sin tocar nada. Se mira ANTES de la prueba de aptitud
# y de la pregunta: con otro modelo, la aptitud gasta una llamada a Copilot, y parar despues la tira. Si no existe, no hay nada que mirar y se
# crea mas abajo. El estado de este lanzamiento se arma aqui para que la parada quede en estado.json (donde-estoy.ps1 no dira "terminado"); hasta
# que se decidan, el modelo, la aptitud y la respuesta son los del lanzamiento anterior: una parada no da por pasado lo que no se ha probado.
$cierreAnterior = $null
if ($previo -and $previo.cierre) { $cierreAnterior = $previo.cierre; $cierreAnterior.cuando = Get-HoraTexto $cierreAnterior.cuando }
$Estado = [ordered]@{
  version = 1; batch = $batch; legacy = $LegacyRoot; migrado = $MigradoRoot; plantilla = $PlantillaRoot
  worktree = $dirWt; rama = $(if ($hayWt) { Get-Rama $dirWt }); ramaOrigen = $RamaMigrado; javaLegacy = $JavaLegacy; lanzadores = $LanzadoresRoot
  modelo = $previo.modelo; aptitud = $previo.aptitud; respuesta = $previo.respuesta
  fase = 'fichas-clase'; creado = (Get-Date).ToString('s'); actualizado = ''; fin = ''; parada = $null; pruebaLocal = $null; cierre = $cierreAnterior
}
if ($previo -and $previo.creado) { $Estado['creado'] = Get-HoraTexto $previo.creado }
if ($Cierre) {
  # -Cierre no es una pasada: lo suyo (fase, fin, parada, prueba en local y opciones) se queda como estaba; solo se quita la parada de un cierre anterior, que se vuelve a intentar
  foreach ($k in @('fase', 'pruebaLocal', 'practicas', 'reglas', 'maxHoras', 'limite', 'sinPruebaLocal')) { $Estado[$k] = $previo.$k }
  if (-not $JavaLegacy) { $JavaLegacy = [string]$previo.javaLegacy }   # la prueba en local que repite el cierre usa el JDK del original de la pasada
  $Estado['javaLegacy'] = $JavaLegacy
  $Estado['fin'] = Get-HoraTexto $previo.fin
  if ([string]$previo.parada.motivo -notlike 'cierre-*') { $Estado['parada'] = $previo.parada }
}
else {
  # las opciones de la pasada, con lo dado en ESTE lanzamiento (-Reintentar no: es de una sola vez): Get-ComandoPasada las repite en la portada
  $Estado['practicas'] = [bool]$Practicas; $Estado['reglas'] = [bool]$Reglas; $Estado['maxHoras'] = $MaxHoras; $Estado['limite'] = $Limite; $Estado['sinPruebaLocal'] = [bool]$SinPruebaLocal
}
if ($hayWt) {
  $RepoRoot = $dirWt
  Undo-IntentoCortado $Estado['rama']
  $sinCommit = @(Get-SinCommit $RepoRoot)
  if ($sinCommit.Count -gt 0) {
    $Estado['fin'] = (Get-Date).ToString('s')
    Set-Parada 'cambios-sin-commit' ("La carpeta de rescate tiene cambios sin commit: $(Get-ListaFicheros $sinCommit). No sigo, para no perderlos.`n" +
      "Si son tuyos y los quieres:  git -C `"$RepoRoot`" add -A ; git -C `"$RepoRoot`" commit -m `"arreglo a mano`"`n" +
      "Si no los quieres:           git -C `"$RepoRoot`" stash push -u -m `"aparte`"`n" +
      'Despues, lanza el mismo comando.') $Registros
    exit 1
  }
}

# -Cierre (sin IA): ni prueba de aptitud (5) ni pregunta (6); la carpeta de rescate ya existe y el estado de la pasada se conserva (arriba)
if ($Cierre) {
  Read-Config $RepoRoot $false
  [void](Set-Despierto $true)
  try { exit (Invoke-Cierre) }
  catch { Stop-ErrorInterno $_ }
  finally { [void](Set-Despierto $false) }
}

# 5. Prueba de aptitud (se salta si ya paso con este modelo)
if ($previo -and ($null -ne $previo.aptitud) -and ([string]$previo.aptitud -eq $ModeloElegido)) { Info 'Prueba de aptitud: ya pasada con este modelo.' }
else {
  Info 'Prueba de aptitud (una ficha de clase sobre un fichero de juguete)...'
  $mal = Test-Aptitud
  if ($mal) { Stop-Arranque ("$mal`nRegistros: $Registros`nPrueba con otro modelo (-Modelo) o mira que Copilot responde.") }
  Bien 'Prueba de aptitud: bien.'
}

# 6. Pregunta: que hacer al acabar el informe
if ($SoloInforme) { $respuesta = 'parar' }
elseif ($respondeSi) { $respuesta = 'corregir' }
elseif ($previo -and $previo.respuesta) { $respuesta = [string]$previo.respuesta }
else {
  $r = "$(Read-Host 'Al acabar el informe, corregir el codigo del migrado? Enter = si, n = parar')".Trim()
  if ($r -match '^[nN]') { $respuesta = 'parar' } else { $respuesta = 'corregir' }
}
$Si = [switch]$true    # las preguntas ya estan contestadas: Confirmar no vuelve a preguntar

# 7. Worktree y estado: lo decidido pasa a estado.json
if (-not $hayWt) { New-WorktreeRescate $dirWt; $Estado['rama'] = Get-Rama $dirWt }
$RepoRoot = $dirWt
Read-Config $RepoRoot $false
$Estado['modelo'] = $ModeloElegido; $Estado['aptitud'] = $ModeloElegido; $Estado['respuesta'] = $respuesta
try {
  foreach ($d in @((Join-Path $Datos 'tareas'), (Join-Path $Datos 'fichas'))) { if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -Force) } }
  Save-Estado
  if (-not (Set-Despierto $true)) { Aviso 'No he podido pedir a Windows que no suspenda el equipo: si lo dejas solo, compruebalo.' }
  $script:Parada = $false
  $script:Racha = 0
  $script:Rondas = 0
  $script:Iniciadas = @{}
  $script:Todas = @()
  $script:Quedan = 0
  Invoke-FaseDiagnostico
  if (-not $script:Parada) { Invoke-Propiedades $LegacyRoot $RepoRoot $PlantillaRoot $Datos $Registros }   # en cada lanzamiento, aunque el diagnostico no se repita; nunca para
  # con la respuesta corregir, comparar va despues de la correccion; con parar, antes de lectura-hecha
  $fases = @('fichas-clase', 'mapa', 'lanzadores', 'fichas-job', 'resumen', 'pruebas-pre', 'casos-pre')
  if ($respuesta -ne 'corregir') { $fases += 'comparar' }
  $sigue = -not $script:Parada
  foreach ($fase in $fases) { if ($sigue) { $sigue = Invoke-FaseTareas $fase } }
  if ($sigue) {
    $Estado['fase'] = 'lectura-hecha'
    Save-Estado
    Save-Informes
    Invoke-FaseCorreccion
    $sigue = -not $script:Parada
    if ($sigue -and $respuesta -eq 'corregir') { $sigue = Invoke-FaseTareas 'comparar' }
  }
  if ($sigue -and $Practicas) { $sigue = Invoke-FasePracticas $conservar }
  if ($sigue -and $Reglas) { $sigue = Invoke-FaseReglas $conservar }
  if ($sigue) {
    Invoke-FasePruebaLocal
    $Estado['fase'] = 'hecha'
  }

  Info ''
  if (-not $script:Parada -and $script:Quedan -gt 0) { Info "Limite de -Limite $Limite alcanzado: quedan $($script:Quedan) tareas pendientes. Relanza el mismo comando sin -Limite para seguir." }
  Info "Datos en: $Salida"
  if (@($script:Todas | Where-Object { $_.estado -eq 'atascada' }).Count -gt 0) { Aviso "Las tareas atascadas estan en $(Join-Path $Datos 'tareas') (estado 'atascada', con su motivo)." }
  $Estado['fin'] = (Get-Date).ToString('s')
  Save-Estado
  Save-Informes
  if ($script:Parada -and $Estado['parada'].motivo -ne 'tope-de-tiempo') { exit 2 }
  exit 0
}
catch { Stop-ErrorInterno $_ }
finally {
  [void](Set-Despierto $false)
}
