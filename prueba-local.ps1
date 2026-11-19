<#
prueba-local.ps1 - Prueba en local, caso a caso: el batch original frente al migrado, con las mismas entradas.
Compatible con Windows PowerShell 5.1 y PowerShell 7. Solo ASCII a proposito.
Necesita comun.ps1, tareas.ps1 y la carpeta tareas\ junto a este script, y los casos que deja migracion.ps1.

QUE HACE
  Se lanza despues de rescate.ps1 y de migracion.ps1. Coge los casos de cada job que escribio migracion.ps1
  (<Migrado>\migracion-<batch>\datos\pruebas\<job>.json: el happy path y los limites), los ejecuta en el original y en
  el migrado con las mismas entradas y compara lo que deja cada uno. Lo que tiene que salir lo da el ORIGINAL al
  ejecutarse: la IA solo fabrica las entradas y escribe el test que ejecuta los casos; compara el script.
  1. Copias desechables (worktrees de git sin rama, que se rehacen en cada lanzamiento): <Legacy>-prueba-local, en el
     HEAD del original, y <Migrado>-prueba-local, en el HEAD de la rama de rescate (si esta su worktree
     <Migrado>-rescate) o en el de la rama del migrado. Tus carpetas y tus ramas no se tocan (la unica excepcion es
     -Deshacer, mas abajo).
  2. Arnes: una tarea de IA por copia (esfuerzo alto) escribe el test PruebaLocalTest junto a la clase
     con @SpringBootApplication y, si le hace falta, src\test\resources\application-prueba-local.yml (en el original,
     tambien dependencias de test en el pom.xml). Primero se escribe el del original y, cuando esta hecho, el del migrado,
     que lo traduce: lleva en su prompt la ruta del test del original ya guardado, para simular lo mismo y al mismo nivel.
     El script comprueba que no toca nada mas, que compila y que, con un
     caso vacio, cada job deja su estado.txt. Un fallo se repite una vez con el motivo; si vuelve a fallar, se para.
     Si la llamada se pasa del tope (SegundosArnes) o sale mal pero deja el test, se comprueba igual: si vale, se usa. Si no
     vale, el motivo lleva los dos fallos y, si fue por tiempo, el reintento sigue desde lo escrito. La IA solo puede lanzar
     mvn -q test-compile y mvn test -Dtest=PruebaLocalTest con -Dsurefire.timeout=SegundosTestArnes (la comprobacion tambien).
     Un arnes guardado de otro lanzamiento se comprueba antes de llamar a la IA, aunque su tarea no este hecha (la plantilla
     cambio, o el reintento quedo atascado): si sigue valiendo se usa, sin llamar a Copilot. Con -RehacerArnes, el del migrado
     se borra y se escribe otra vez (el del original no se toca).
  3. Entradas: una tarea de IA por caso (hasta 4 a la vez) escribe en la copia del original
     src\test\resources\prueba-local\<job>\<caso>\ (ficheros\, datos.sql, parametros.properties), o no-aplica.txt si
     el caso pide cambiar la configuracion. El script comprueba que solo escribe ahi y que el caso corre en el original.
  4. Ejecuta, sin IA: el original dos veces y el migrado una (mvn test -Dtest=PruebaLocalTest, un job por llamada).
  5. Compara cada caso (estado.txt, ficheros\, tablas\ y envios\), sin contar las horas sueltas ni las fechas con hora
     de la ejecucion (hoy, en hora local y en UTC; una fecha con hora de otro dia es un dato del negocio y cuenta) ni la
     fecha de hoy: igual, distinto, no determinista (el original da dos salidas distintas: no cuenta), no se pudo preparar
     o sin probar en local. Si un fichero solo cambia de codificacion o de formato de numeros, lo apunta como posible
     diferencia del JDK, sin esconderlo. Un caso que deja lo mismo que el caso vacio del arnes sale igual, con su aviso;
     pero si es asi con todos los casos de un job (y ninguno sale distinto), el test no le pasa las entradas al job: la
     prueba acaba con 1 (fallo), sin prueba-local.json, y los dos arneses guardados se invalidan para que el siguiente
     lanzamiento los escriba otra vez con ese motivo.
  6. Solo con -Desde <commit> (un commit de la rama que se prueba): para cada caso distinto busca, por biseccion entre
     <commit> y el HEAD (git rev-list --first-parent), el primer commit que lo rompe. Ejecuta el caso en el migrado de
     cada commit que prueba (en una copia desechable, con el arnes ya guardado; el original no se vuelve a ejecutar) y
     lo compara con lo que dejo el original, con las mismas reglas del paso 5. Un commit donde el caso no se puede
     ejecutar (no compila, Maven se pasa del tope...) ni es bueno ni es malo: se salta, como git bisect skip, y se dice. Si
     solo quedan commits saltados antes del malo, no se da culpable y no se deshace nada. Con -Deshacer, ademas, revierte
     esos commits con git revert (del mas nuevo al mas viejo) en la carpeta de la rama que se prueba y vuelve a ejecutar
     TODOS los casos en el HEAD nuevo (un revert puede arreglar un caso y romper otro): ahora igual o sigue distinto. Si el
     revert de un commit no arregla ninguno de sus casos, lo quita con otro git revert (y lo dice en rojo). No deshace si
     esa carpeta tiene cambios sin commit, si el commit es un merge o si el revert da conflicto (lo aborta y no deja nada
     a medias). Nunca se llama a Copilot, ni al buscar ni al deshacer.
  7. Solo con -Reparar (no se combina con -Desde ni con -Deshacer; hace falta el worktree de rescate, y su carpeta sin cambios
     sin commit): despues de la prueba de siempre, arregla el migrado hasta que los casos distintos salgan iguales. Cada
     diferencia tiene una clave (el nombre de su fichero, normalizado); se arregla primero la clave con mas casos distintos, y
     despues de cada arreglo se recalcula. Una tarea de IA por clave escribe, en la copia del migrado y solo en src\main\, el
     arreglo; el script lo da por bueno si pasa seis puertas, de la mas barata a la mas cara: la llamada acaba bien; la IA no
     dice que no se arregla (.rescate\reparar-no.txt: si la diferencia solo es de lo simulado en local); solo cambia src\main\;
     el caso de la tarea mejora; ningun otro caso empeora (ni claves nuevas, ni mas lineas distintas, ni deja de ejecutarse); y
     la suite de tests unitarios, sin el arnes, no falla mas ni se ejecuta menos que al empezar. Un arreglo que pasa va a la
     rama de rescate (un commit por arreglo: 'rescate(local): <job>/<caso> <clave>'); uno que no pasa se deshace y se
     reintenta una vez con el motivo y el diff rechazado. Tu carpeta y tu rama no se tocan: revisa los commits de la rama de
     rescate antes del git merge. Como mucho MaxReparaciones claves por lanzamiento; lo que no se prueba se dice. Una clave
     que sale 'no se arregla' no se vuelve a probar con el mismo test del migrado: con -RehacerArnes (otro test), si.
  Lo de la IA queda en <Migrado>\migracion-<batch>\prueba-local\ (arnes\, casos\ y tareas\), con las salidas
  (salidas\original, original-2 y migrado) y los registros; el resultado, en datos\prueba-local.json. Al relanzar no
  se repite lo hecho (si no han cambiado sus entradas): solo se vuelve a ejecutar y a comparar.

USO
  .\prueba-local.ps1 -Legacy C:\ruta\life-java8 -Migrado C:\ruta\batch-life
  .\prueba-local.ps1 ... -Modelo <id>          # sin esto, el que uso migracion.ps1
  .\prueba-local.ps1 ... -JavaLegacy C:\jdk8   # el JDK del original, si no compila con el de Maven
  .\prueba-local.ps1 ... -Job cargaRecibosJob  # solo los casos de ese job
  .\prueba-local.ps1 ... -Si                   # no pregunta antes de llamar a Copilot
  .\prueba-local.ps1 ... -Desde <commit>       # y, de cada caso distinto, el commit de la rama que lo rompe
  .\prueba-local.ps1 ... -Desde <commit> -Deshacer   # y deshace esos commits con git revert (solo commits nuevos encima)
  .\prueba-local.ps1 ... -Reparar             # y arregla el migrado (en la rama de rescate) hasta que los casos distintos salgan iguales
  .\prueba-local.ps1 ... -RehacerArnes        # escribe otra vez con la IA el test del migrado: si la IA de -Reparar dice que la diferencia es del test del migrado

  Salida: 0 todo lo comparado es igual, 2 hay casos distintos, 1 no ha podido (o no ha podido comparar ninguno, o el
  test no le pasa las entradas a un job).
  Con -Deshacer o -Reparar, la salida es la del estado de despues de deshacer o de reparar.
  Antes de darlo por bueno, pasa tests\probar-local.ps1.
#>
[CmdletBinding()]
param(
  [string]$Legacy = '',       # carpeta del batch original (repo git)
  [string]$Migrado = '.',     # carpeta del batch migrado (repo git), con lo que dejo migracion.ps1
  [string]$Modelo = '',       # id del modelo de Copilot; sin esto, el de migracion.ps1 ('' = el que tenga Copilot)
  [string]$JavaLegacy = '',   # JAVA_HOME para el Maven del original
  [string]$Job = '',          # solo los casos de este job
  [string]$Desde = '',        # un commit de la rama que se prueba: busca el commit que rompe cada caso distinto
  [switch]$Deshacer,          # con -Desde: deshace con git revert los commits que rompen (la unica vez que se toca tu rama)
  [switch]$Reparar,           # arregla el migrado, en la rama de rescate, hasta que los casos distintos salgan iguales (no con -Desde)
  [switch]$RehacerArnes,      # borra el test del migrado guardado y lo escribe otra vez con la IA, traduciendo el del original (que no se toca)
  [switch]$Si                 # no preguntar antes de llamar a Copilot
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'comun.ps1')
. (Join-Path $PSScriptRoot 'tareas.ps1')

# ============================ CONFIGURACION ============================
$Cfg += @{
  EsfuerzoArnes  = 'high'
  EsfuerzoCaso   = 'medium'
  SegundosArnes  = 1800   # tope de una llamada que escribe un arnes (las de los casos usan SegundosPorLlamada)
  SegundosTestArnes = 300 # tope del mvn test que prueba el arnes (-Dsurefire.timeout): el de la comprobacion y el que se le pide a la IA
  LeerPorCaso    = 3      # ficheros del original que lee la tarea de un caso
  Ejemplos       = 3      # tests de ejemplo que recibe la tarea de un arnes
  LineasError    = 15     # lineas del error de Maven que van al motivo
  FallosSeguidos = 6      # llamadas fallidas seguidas antes de parar
  EsfuerzoReparar = 'high'
  SegundosReparar = 1800  # tope de una llamada que repara (-Reparar; las demas usan SegundosPorLlamada)
  MaxReparaciones = 8     # claves de diferencia que -Reparar prueba como mucho en un lanzamiento
}
$Casos = 'src/test/resources/prueba-local'   # donde van los casos dentro de cada copia
# Una linea de una plantilla cuya clave {{SI_...}} vale esto no sale en el prompt (Invoke-Lote): asi una plantilla lleva dos variantes
# de un parrafo y cada tarea elige una. Ninguna otra linea de las plantillas empieza asi.
$MarcaNo = '<!--no-->'
# El aviso de un caso igual que deja lo mismo que el caso vacio del arnes (Get-Resultado); Get-JobsVacios lo busca.
$MotivoVacio = 'Sale lo mismo que con el caso vacio del arnes: si el caso tiene entradas, mira que lleguen al job.'
$NoPromete = 'Lo que esto no promete: las entradas son inventadas y lo de fuera (base de datos, SFTP, correo, HTTP) esta simulado. La conexion de verdad se prueba en pre, con el guion de cada job.'
$Inv = [System.Globalization.CultureInfo]::InvariantCulture
$Latin = [System.Text.Encoding]::GetEncoding(28591)
$Utf8Estricto = New-Object System.Text.UTF8Encoding($false, $true)
$RutasCopia = @()   # las rutas de las dos copias, en sus formas: Get-Normal las cambia por <copia>
$Hoy = @()          # las fechas de la ejecucion (Get-Hoy): Get-Resultado las pone al dia en cada comparacion
$script:Base = @{}  # por copia: el commit y el arbol que se dieron por buenos (Save-Copia)

# ================================ COPIAS ================================
# La ruta que guarda un fichero .git de worktree ('gitdir: <ruta>'), completa.
function Get-GitDir([string]$Fichero, [string]$Base) {
  $g = ([System.IO.File]::ReadAllText($Fichero) -replace '^\s*gitdir:\s*', '').Trim()
  if (-not [System.IO.Path]::IsPathRooted($g)) { $g = [System.IO.Path]::GetFullPath((Join-Path $Base $g)) }
  return $g
}

# Es $Dir un worktree de $Repo? Lo dice su fichero .git (se lee como fichero: la salida de git, en PowerShell 5.1, llega
# en la pagina de codigos de la consola y una ruta con tildes no coincidiria).
function Test-CopiaDe([string]$Repo, [string]$Dir) {
  $f = Join-Path $Dir '.git'
  if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { return $false }
  $comun = Join-Path $Repo '.git'
  if (Test-Path -LiteralPath $comun -PathType Leaf) { $comun = Split-Path (Split-Path (Get-GitDir $comun $Repo) -Parent) -Parent }
  $base = (($comun -replace '\\', '/').TrimEnd('/') + '/worktrees/').ToLowerInvariant()
  return ((Get-GitDir $f $Dir) -replace '\\', '/').ToLowerInvariant().StartsWith($base)
}

# Rehace la copia desechable $Dir de $Repo en $Commit (un worktree sin rama). Una carpeta que ya existe solo se borra
# si es un worktree de ese mismo repo. Devuelve '' o el motivo.
function New-Copia([string]$Repo, [string]$Commit, [string]$Dir) {
  if (Test-Path -LiteralPath $Dir) {
    if (-not (Test-CopiaDe $Repo $Dir)) { return "La carpeta $Dir ya existe y no es una copia de la prueba local de $Repo. Muevela o borrala y vuelve a lanzar." }
    $r = Invoke-Git $Repo @('worktree', 'remove', '--force', $Dir)
    if ($r.Codigo -ne 0) { return ("No he podido borrar la copia anterior ($Dir): " + ($r.Salida -join ' ')) }
  }
  # -f: vale aunque git aun tenga apuntada una copia anterior que alguien borro a mano
  $r = Invoke-Git $Repo @('worktree', 'add', '-q', '-f', '--detach', $Dir, $Commit)
  if ($r.Codigo -ne 0) { return ("No he podido crear la copia ${Dir}: " + ($r.Salida -join ' ')) }
  Save-Copia $Dir
  return ''
}

# Lo cambiado en una copia desde lo ultimo que se dio por bueno (su indice de git) lo da Get-Cambios, de comun.ps1.

# Da por bueno lo que hay en la copia (al indice) y apunta su base: el commit y el arbol del indice.
function Save-Copia([string]$Dir) {
  [void](Invoke-Git $Dir @('add', '-A', '--', '.', ':(exclude).rescate', ':(exclude)target'))
  $script:Base[$Dir] = @{ Head = (Get-Head $Dir); Arbol = ((Invoke-Git $Dir @('write-tree')).Salida -join '').Trim() }
}

# Tras una llamada a la IA: la copia vuelve a su base (por si hizo commit o git add), con lo que hizo como cambios sin
# guardar, a la vista de Get-Cambios.
function Restore-Base([string]$Dir) {
  $b = $script:Base[$Dir]
  if ((Get-Head $Dir) -ne $b.Head) { [void](Invoke-Git $Dir @('reset', '-q', '--soft', $b.Head)) }
  [void](Invoke-Git $Dir @('read-tree', $b.Arbol))
}

# Deja la copia como su indice: deshace lo cambiado y borra lo nuevo.
function Undo-Copia([string]$Dir) {
  [void](Invoke-Git $Dir @('checkout', '-q', '--', '.'))
  [void](Invoke-Git $Dir @('clean', '-fdq', '--', '.', ':(exclude).rescate', ':(exclude)target'))
}

function Remove-Carpeta([string]$Dir) { if (Test-Path -LiteralPath $Dir) { Remove-Item -LiteralPath $Dir -Recurse -Force } }

function Copy-Fichero([string]$De, [string]$A) {
  $d = Split-Path $A -Parent
  if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -Force) }
  Copy-Item -LiteralPath $De -Destination $A -Force
}

# Copia los ficheros de la carpeta $De (con sus subcarpetas) a $A, pisando los que haya. Sin $De, nada.
function Copy-Carpeta([string]$De, [string]$A) {
  if (-not (Test-Path -LiteralPath $De)) { return }
  foreach ($f in @(Get-ChildItem -LiteralPath $De -Recurse -File)) { Copy-Fichero $f.FullName (Join-Ruta $A (Get-Rel $De $f.FullName)) }
}

# ================================ MAVEN ================================
# Maven en una copia (en la del original, con JAVA_HOME = -JavaLegacy, si se ha dado), con latido, con tope (MinutosMaven) y sin
# saltarse los tests aunque el pom lo pida. Lo que Maven deja fuera de target (un log, una base en fichero) se borra al acabar
# (Remove-Ruido, de comun.ps1): no es de la IA y la siguiente ejecucion empieza igual. Deja lo que dice en registros\mvn-<n>-<que>.log y devuelve
# Codigo, Salida y Tope (Invoke-MavenTope, de comun.ps1).
function Invoke-Maven([string]$Dir, [bool]$EsOriginal, [string[]]$A, [string]$Que) {
  $script:Mavens++
  $previos = @(Get-Cambios $Dir)
  $antes = $env:JAVA_HOME
  $desde = [DateTime]::UtcNow
  if ($EsOriginal -and $JavaLegacy) { $env:JAVA_HOME = $JavaLegacy }
  try { $r = Invoke-MavenTope $Dir (@('-B', '-DskipTests=false', '-Dmaven.test.skip=false') + $A) "Maven, $Que" (Join-Path $Registros ('mvn-' + $script:Mavens + '-' + ($Que -replace '[^\w\-]', '-') + '.log')) }
  finally { $env:JAVA_HOME = $antes }
  $causa = ''
  if ($r.Codigo -ne 0) { $causa = Get-CausaMaven $Dir $desde $r.Salida }
  Add-Member -InputObject $r -NotePropertyName Causa -NotePropertyValue $causa
  [void](Remove-Ruido $Dir $previos)
  return $r
}

# La causa de un Maven que ha fallado, recortada a 300 caracteres ('' si no hay): el ultimo 'Caused by:' de los informes de surefire de la
# copia $Dir escritos desde $Desde (los de antes pueden ser de otro caso), en el primero que tenga <<< ERROR! o <<< FAILURE!; si no hay, el
# ultimo 'Caused by:' de $Salida (la de Maven: surefire recorta la traza del informe y Spring la escribe entera en la salida); y si
# tampoco, la primera linea con texto tras la marca del informe. Un informe que no se puede leer cuenta como si no estuviera.
function Get-CausaMaven([string]$Dir, [DateTime]$Desde, [string[]]$Salida) {
  $causa = ''
  $primera = ''
  try {
    $carpeta = Join-Ruta $Dir 'target/surefire-reports'
    foreach ($f in @(Get-ChildItem -LiteralPath $carpeta -Filter '*.txt' -File | Where-Object { $_.LastWriteTimeUtc -ge $Desde } | Sort-Object Name)) {
      $l = @([System.IO.File]::ReadAllLines($f.FullName))
      $marca = -1
      for ($i = 0; $i -lt $l.Count -and $marca -lt 0; $i++) { if ($l[$i] -match '<<< (ERROR|FAILURE)!') { $marca = $i } }
      if ($marca -lt 0) { continue }
      foreach ($x in $l) { if ($x -match '^Caused by:') { $causa = $x } }
      for ($i = $marca + 1; $i -lt $l.Count -and -not $primera; $i++) { if ($l[$i].Trim() -and $l[$i] -notmatch '<<<') { $primera = $l[$i] } }
      break
    }
  }
  catch { }
  if (-not $causa) { foreach ($x in @($Salida)) { if ($x -match 'Caused by:.*$') { $causa = $Matches[0] } } }
  if (-not $causa) { $causa = $primera }
  $causa = $causa.Trim()
  if ($causa.Length -gt 300) { $causa = $causa.Substring(0, 300) }
  return $causa
}

# Lo que sirve para entender un fallo de Maven (lo que da Invoke-Maven): pasado el tope, el mensaje; si no, las primeras
# lineas [ERROR] o, si no hay, las ultimas, y, si hay, la causa de verdad, de su informe de surefire o de la salida (Get-CausaMaven).
function Get-FalloMaven($Maven) {
  if ($Maven.Tope) { return $Maven.Tope }
  $e = @($Maven.Salida | Where-Object { $_ -match '^\[ERROR\]' } | Select-Object -First ([int]$Cfg.LineasError))
  if ($e.Count -eq 0) { $e = @($Maven.Salida | Select-Object -Last ([int]$Cfg.LineasError)) }
  if ($Maven.Causa) { $e += "Causa: $($Maven.Causa)" }
  return ($e -join "`n")
}

# Ejecuta en una copia un caso de un job (con su salida anterior borrada), en su propio Maven: cada caso en una JVM
# nueva, como cada ejecucion en produccion. En la misma JVM, lo que el batch deja en campos static (un fichero abierto,
# un contador) pasaria de un caso al siguiente.
function Invoke-Job([string]$Dir, [bool]$EsOriginal, [string]$Job, [string]$Caso, [string]$Que) {
  Remove-Carpeta (Join-Ruta $Dir "target/prueba-local/$Job/$Caso")
  return (Invoke-Maven $Dir $EsOriginal @('test', '-Dtest=PruebaLocalTest', "-Dprueba.local.job=$Job", "-Dprueba.local.caso=$Caso") $Que)
}

# Por que un caso no ha dejado estado.txt en $Sal: su error.txt o, si no hay, el error de Maven.
function Get-Porque([string]$Sal, $Maven) {
  $err = Join-Path $Sal 'error.txt'
  if (Test-Path -LiteralPath $err) { return ('error.txt: ' + (@([System.IO.File]::ReadAllLines($err) | Select-Object -First ([int]$Cfg.LineasError)) -join "`n")) }
  if ($null -eq $Maven) { return 'no ha dejado estado.txt.' }
  return ("no ha dejado estado.txt. Maven dice:`n" + (Get-FalloMaven $Maven))
}

# ================================ TAREAS ================================
# Llama a Copilot para todas las tareas de $Lote a la vez (cada una en la copia de su entradas.copia) y deja un
# registro por llamada. Las de la copia del original arrancan con JAVA_HOME = -JavaLegacy (si se ha dado), como su Maven: la IA
# ejecuta mvn en esa copia. Devuelve las llamadas en el mismo orden. Para el script si fallan FallosSeguidos seguidas.
function Invoke-Lote($Lote, [string]$Esfuerzo) {
  $items = @()
  foreach ($t in $Lote) {
    $esf = $Esfuerzo
    $motivo = ''
    if ($t.intentos -gt 0) { $esf = $Cfg.EsfuerzoReintento; $motivo = $t.motivo }
    $jdk = ''
    if ($JavaLegacy -and $t.entradas.copia -eq $CopiaOrig) { $jdk = $JavaLegacy }
    $items += , ([pscustomobject]@{ Id = $t.id; Dir = $t.entradas.copia; Prompt = ((Get-Prompt $t '' $motivo) -replace ('(?m)^' + [regex]::Escape($MarcaNo) + '.*\n(\n)?'), ''); Modelo = $ModeloElegido; Esfuerzo = $esf; Dirs = @($t.entradas.dirs); JavaHome = $jdk })
  }
  $ll = @(Invoke-Llamadas $items)
  for ($i = 0; $i -lt $items.Count; $i++) {
    $c = $ll[$i]
    $script:Llamadas++
    $cab = "# salida (codigo $($c.Codigo), $($c.Segundos) s"
    if ($c.Agotado) { $cab += ', tiempo agotado' }
    [System.IO.File]::WriteAllText((Join-Path $Registros ($items[$i].Id + '-' + ($Lote[$i].intentos + 1) + '.log')), ("# prompt`n" + $items[$i].Prompt + "`n`n" + $cab + ")`n" + $c.Texto + "`n"), $Utf8)
    if ($c.Codigo -ne 0 -or $c.Agotado) { $script:Racha++ } else { $script:Racha = 0 }
  }
  if ($script:Racha -ge [int]$Cfg.FallosSeguidos) {
    Stop-Arranque ("Copilot no responde: $($script:Racha) llamadas seguidas han fallado. La ultima: " + (Get-UltimaLinea $ll[-1].Texto) + "`nMira que Copilot funciona (sesion, cuota, red) y vuelve a lanzar el mismo comando: lo hecho se conserva.")
  }
  return $ll
}

# '' si la llamada acabo bien; si no, el motivo.
function Get-MotivoLlamada($C) {
  if ($C.Agotado) { return 'Tiempo agotado: la llamada se paso del tope y se mato.' }
  if ($C.Codigo -ne 0) { return ("Copilot salio con codigo $($C.Codigo): " + (Get-UltimaLinea $C.Texto)) }
  return ''
}

# Apunta un intento: sin motivo, la tarea queda hecha; con motivo, pendiente (para el reintento) o atascada si ya no
# quedan intentos.
function Set-Intento($T, [string]$Motivo) {
  $T.intentos++
  $T.motivo = $Motivo
  if (-not $Motivo) { $T.estado = 'hecha'; $T.ultimoEstado = 'ok' }
  else {
    $T.ultimoEstado = 'invalida'
    if ($T.intentos -ge [int]$Cfg.Intentos) { $T.estado = 'atascada' }
  }
  Save-Tarea $T
}

# La tarea de la que sale una hecha de antes si sus ficheros ya no estan guardados en $Guardado: vuelve a empezar.
function Test-Guardada($T, [string]$Guardado) {
  if ($T.estado -eq 'hecha' -and -not (Test-Path -LiteralPath $Guardado)) { $T.estado = 'pendiente'; $T.intentos = 0; $T.motivo = ''; Save-Tarea $T }
  return $T
}

# ================================ ARNESES ================================
# Donde va el test en una copia: src/test/java/<paquete de la clase con @SpringBootApplication>/PruebaLocalTest.java,
# o '' si no hay esa clase.
function Get-RutaTest([string]$Dir) {
  foreach ($f in @(Get-JavaFiles (Join-Ruta $Dir 'src/main/java') | Sort-Object FullName)) {
    $t = [System.IO.File]::ReadAllText($f.FullName)
    if ($t -notmatch '@SpringBootApplication') { continue }
    $paquete = ([regex]::Match($t, '(?m)^\s*package\s+([\w\.]+)\s*;')).Groups[1].Value
    $rel = 'src/test/java/'
    if ($paquete) { $rel += $paquete.Replace('.', '/') + '/' }
    return ($rel + 'PruebaLocalTest.java')
  }
  return ''
}

# Hasta Ejemplos tests que arrancan el batch (@SpringBootTest, JobLauncherTestUtils o @SpringBatchTest): los de la
# copia o, si no tiene, los de la referencia. Rutas completas.
function Get-Ejemplos([string]$Dir) {
  foreach ($raiz in @($Dir, $PlantillaRoot)) {
    if (-not $raiz) { continue }
    $l = @(Get-JavaFiles (Join-Ruta $raiz 'src/test/java') | Sort-Object FullName | Where-Object { [System.IO.File]::ReadAllText($_.FullName) -match '@SpringBootTest|JobLauncherTestUtils|@SpringBatchTest' } | Select-Object -First ([int]$Cfg.Ejemplos))
    if ($l.Count -gt 0) { return @($l | ForEach-Object { $_.FullName }) }
  }
  return @()
}

# El hash del test que dejo guardado el arnes de $Repo (prueba-local\arnes\<repo>\<ruta del test>), o '' si no esta.
function Get-HashGuardado([string]$Repo, [string]$Test) {
  $f = Join-Ruta $Local "arnes/$Repo/$Test"
  if (-not $Test -or -not (Test-Path -LiteralPath $f -PathType Leaf)) { return '' }
  return (Get-Hash8 ([System.IO.File]::ReadAllText($f)))
}

# La huella de la tarea de un arnes: la plantilla, el test y los jobs y, en el migrado, el hash del test del original guardado.
function Get-HuellaArnes([string]$Test, [string[]]$Jobs, [string]$HashOriginal) {
  return (Get-Hash8 ((Get-Plantilla 'arnes-local') + '|' + $Test + '|' + ($Jobs -join ',') + '|' + $HashOriginal))
}

# La tarea del arnes de una copia ($Repo: original o migrado), o la hecha de antes si sus entradas no han cambiado (la
# plantilla, el test, los jobs y, en el migrado, el test del original guardado: $TestOriginal es su ruta dentro del arnes,
# y '' en el original). El commit no entra en la huella: un arnes de antes se vuelve a comprobar en el commit
# de ahora (Use-ArnesGuardado). El migrado traduce el test del original: su prompt lleva esa ruta (SI_ORIGINAL vacio) y la
# carpeta del arnes del original va en sus dirs; el original no lleva la seccion (SI_ORIGINAL = MarcaNo).
function Get-TareaArnes([string]$Repo, [string]$Dir, [string]$Test, [string[]]$Jobs, [string]$TestOriginal) {
  $ejemplos = @(Get-Ejemplos $Dir)
  $lista = '(No hay tests de ejemplo: escribe el test desde cero.)'
  if ($ejemplos.Count -gt 0) { $lista = (@($ejemplos | ForEach-Object { '- ' + $_ }) -join "`n") }
  $dirs = @()
  if ($PlantillaRoot -and @($ejemplos | Where-Object { $_.StartsWith($PlantillaRoot) }).Count -gt 0) { $dirs = @($PlantillaRoot) }
  $pom = 'no'
  if ($Repo -eq 'original') { $pom = 'si' }
  $siOriginal = $MarcaNo
  $rutaOriginal = ''
  $hashOriginal = ''
  if ($TestOriginal) {
    $siOriginal = ''
    $rutaOriginal = Join-Ruta (Join-Ruta $Local 'arnes/original') $TestOriginal
    $dirs += (Join-Ruta $Local 'arnes/original')
    $hashOriginal = Get-HashGuardado 'original' $TestOriginal
  }
  $prompt = [pscustomobject]@{ REPO = "el batch $Repo"; TEST = $Test; JOBS = ($Jobs -join ', '); EJEMPLOS = $lista; POM = $pom; SEGUNDOS_TEST = "$($Cfg.SegundosTestArnes)"; SI_CORTADO = $MarcaNo; SI_DESHECHO = ''; SI_ORIGINAL = $siOriginal; ORIGINAL = $rutaOriginal }
  $huella = Get-HuellaArnes $Test $Jobs $hashOriginal
  $e = [pscustomobject]@{ repo = $Repo; test = $Test; testOriginal = $TestOriginal; hashOriginal = $hashOriginal; copia = $Dir; dirs = $dirs; huella = $huella; prompt = $prompt }
  $guardada = Join-Path (Join-Path $Datos 'tareas') ('arnes-' + $Repo + '.json')
  $antes = $null
  if (Test-Path -LiteralPath $guardada) { try { $antes = Read-Json $guardada } catch { } }
  $t = Restore-Tarea (New-TareaTipo 'arnes-local' ('arnes-' + $Repo) '' ('prueba-local/arnes/' + $Repo) $e) $false
  # Un arnes invalidado (Stop-Vacios, o un reintento que un corte dejo a medias) no empieza de cero: sigue por su intento y su
  # motivo, y la IA recibe ese motivo en su prompt de correccion. Restore-Tarea solo conserva las tareas hechas. Que el test del
  # original ya no este guardado (Stop-Vacios lo borra) no cuenta: la huella se compara con el hash del original de entonces.
  if ($t.estado -eq 'pendiente' -and $antes -and $antes.estado -eq 'pendiente' -and $antes.intentos -gt 0 -and $antes.motivo -and $antes.entradas.huella -eq (Get-HuellaArnes $Test $Jobs ([string]$antes.entradas.hashOriginal))) {
    $t.intentos = $antes.intentos; $t.motivo = $antes.motivo; $t.ultimoEstado = $antes.ultimoEstado
    Save-Tarea $t
  }
  $t.entradas.copia = $Dir   # la de ahora, aunque la tarea venga de otro lanzamiento
  return (Test-Guardada $t (Join-Ruta $Local "arnes/$Repo"))
}

# Los ficheros que puede escribir el arnes de una copia.
function Get-Permitidos($T) {
  $p = @($T.entradas.test, 'src/test/resources/application-prueba-local.yml')
  if ($T.entradas.repo -eq 'original') { $p += 'pom.xml' }
  return $p
}

# '' si el pom $Despues solo anade a $Antes dependencias con <scope>test</scope>; si no, el motivo.
function Test-PomSoloTest([string]$Antes, [string]$Despues) {
  $regla = 'En el pom.xml solo puedes anadir dependencias con <scope>test</scope>'
  try { $a = [xml]$Antes; $d = [xml]$Despues }
  catch { return ('El pom.xml ya no es un XML valido: ' + $_.Exception.Message) }
  $ruta = "/*[local-name()='project']/*[local-name()='dependencies']"
  $ya = @{}
  foreach ($n in @($a.SelectNodes("$ruta/*[local-name()='dependency']"))) { $ya[($n.OuterXml -replace '\s', '')] = $true }
  foreach ($n in @($d.SelectNodes("$ruta/*[local-name()='dependency']"))) {
    if ($ya.ContainsKey(($n.OuterXml -replace '\s', ''))) { continue }
    $s = $n.SelectSingleNode("*[local-name()='scope']")
    if (-not $s -or $s.InnerText.Trim() -ne 'test') {
      $nombre = (@($n.ChildNodes | Where-Object { $_.LocalName -eq 'groupId' -or $_.LocalName -eq 'artifactId' } | ForEach-Object { $_.InnerText.Trim() }) -join ':')
      return "$regla, y $nombre no lo lleva."
    }
    [void]$n.ParentNode.RemoveChild($n)
  }
  $deps = $d.SelectSingleNode($ruta)
  if ($deps -and -not $a.SelectSingleNode($ruta) -and $deps.SelectNodes('*').Count -eq 0) { [void]$deps.ParentNode.RemoveChild($deps) }
  if (($a.DocumentElement.OuterXml -replace '\s', '') -cne ($d.DocumentElement.OuterXml -replace '\s', '')) { return "$regla, y has cambiado algo mas. Deja el resto como estaba." }
  return ''
}

# Comprueba el arnes que acaba de escribir la IA en su copia: solo los ficheros permitidos (y en el pom, solo
# dependencias de test frente a $PomOriginal), compila y, con un caso vacio por job, cada job deja estado.txt (la
# salida del vacio del original se guarda en salidas\vacio: se compara con la de cada caso). Devuelve '' o el motivo.
function Test-Arnes($T, [string[]]$Jobs) {
  $dir = $T.entradas.copia
  $esOrig = ($T.entradas.repo -eq 'original')
  Remove-Carpeta (Join-Ruta $dir $Casos)
  $permitidos = @(Get-Permitidos $T)
  $cambios = @(Get-Cambios $dir)
  $fuera = @($cambios | Where-Object { $permitidos -notcontains $_ })
  if ($fuera.Count -gt 0) { return ('Solo puedes escribir ' + ($permitidos -join ', ') + ', y has cambiado tambien: ' + (@($fuera | Select-Object -First 5) -join ', ') + '. Deja todo lo demas como estaba.') }
  if (-not (Test-Path -LiteralPath (Join-Ruta $dir $T.entradas.test))) { return "No has escrito el test $($T.entradas.test)." }
  if ($cambios -contains 'pom.xml') {
    $m = Test-PomSoloTest $PomOriginal ([System.IO.File]::ReadAllText((Join-Ruta $dir 'pom.xml')))
    if ($m) { return $m }
  }
  $r = Invoke-Maven $dir $esOrig @('test-compile') "arnes $($T.entradas.repo), compilar"
  if ($r.Codigo -ne 0) { return ("El test no compila (mvn test-compile). Maven dice:`n" + (Get-FalloMaven $r)) }
  foreach ($j in $Jobs) { foreach ($c in @('vacio', 'otro')) { [void](New-Item -ItemType Directory -Path (Join-Ruta $dir "$Casos/$j/$c") -Force) } }
  Remove-Carpeta (Join-Ruta $dir 'target/prueba-local')
  $r = Invoke-Maven $dir $esOrig @('test', '-Dtest=PruebaLocalTest', '-Dprueba.local.caso=vacio', "-Dsurefire.timeout=$($Cfg.SegundosTestArnes)") "arnes $($T.entradas.repo), caso vacio"
  Remove-Carpeta (Join-Ruta $dir $Casos)
  # Surefire mata el fork pasado el tiempo y Maven acaba con 'There was a timeout in the fork' (en Surefire 2.x, '... timeout or other error in the fork'): SurefireHelper.createErrorMessage
  if ($r.Codigo -ne 0 -and (@($r.Salida) -join "`n") -match 'There was a timeout( or other error)? in the fork') {
    return "Con un caso vacio, el test no termina en $($Cfg.SegundosTestArnes) s: el job intenta conectar con algo de verdad (base de datos, SFTP, correo, HTTP). Simulalo en el test."
  }
  foreach ($j in $Jobs) {
    $sal = Join-Ruta $dir "target/prueba-local/$j/vacio"
    if (-not (Test-Path -LiteralPath (Join-Path $sal 'estado.txt'))) { return ("Con un caso vacio ($Casos/$j/vacio, una carpeta sin nada), el job $j " + (Get-Porque $sal $r)) }
    if (Test-Path -LiteralPath (Join-Ruta $dir "target/prueba-local/$j/otro")) { return "Con -Dprueba.local.caso=vacio, el test ha ejecutado tambien $Casos/$j/otro. Si la propiedad prueba.local.caso tiene valor, ejecuta solo los casos con ese nombre: cada caso se lanza en su propio Maven." }
  }
  if ($esOrig) {
    Remove-Carpeta (Join-Ruta $Local 'salidas/vacio')
    foreach ($j in $Jobs) { Copy-Carpeta (Join-Ruta $dir "target/prueba-local/$j/vacio") (Join-Ruta $Local "salidas/vacio/$j") }
  }
  return ''
}

# Guarda lo que ha escrito el arnes (en prueba-local\arnes\<repo>) y lo da por bueno en la copia.
function Save-Arnes($T) {
  $dir = $T.entradas.copia
  $dest = Join-Ruta $Local "arnes/$($T.entradas.repo)"
  Remove-Carpeta $dest
  $permitidos = @(Get-Permitidos $T)
  foreach ($rel in @(Get-Cambios $dir | Where-Object { $permitidos -contains $_ })) { Copy-Fichero (Join-Ruta $dir $rel) (Join-Ruta $dest $rel) }
  Save-Copia $dir
}

# Pone en su copia el arnes guardado de otro lanzamiento y le pasa la misma comprobacion que a uno nuevo (el commit puede ser
# otro), antes de llamar a la IA: aunque su tarea no este hecha (la plantilla cambio y con ella la huella, o el reintento quedo
# atascado), un test que sigue valiendo se usa y la tarea queda hecha, sin llamar a Copilot. Si ya no vale, se deshace; una tarea
# hecha vuelve a empezar (y se avisa), una que ya estaba por hacer sigue como estaba.
function Use-ArnesGuardado($T, [string[]]$Jobs) {
  $estabaHecha = ($T.estado -eq 'hecha')
  Copy-Carpeta (Join-Ruta $Local "arnes/$($T.entradas.repo)") $T.entradas.copia
  $m = Test-Arnes $T $Jobs
  if (-not $m) {
    Save-Copia $T.entradas.copia
    if (-not $estabaHecha) {
      $T.estado = 'hecha'; $T.intentos = 0; $T.motivo = ''; $T.ultimoEstado = 'ok'
      Save-Tarea $T
      Bien "Arnes del $($T.entradas.repo): bien (el test de otro lanzamiento sigue valiendo)."
    }
    return
  }
  Undo-Copia $T.entradas.copia
  if (-not $estabaHecha) { return }
  Aviso "El test PruebaLocalTest del $($T.entradas.repo) de otro lanzamiento ya no vale en este commit ($(($m -split "`n")[0])): se vuelve a escribir."
  $T.estado = 'pendiente'; $T.intentos = 0; $T.motivo = ''
  Save-Tarea $T
}

# '' si lo que dejo la IA en la copia del arnes $T tras la llamada $C vale; si no, el motivo. Una llamada que se paso del tope o
# salio con un codigo distinto de 0 puede haber dejado ya un test que vale: si hay test, se comprueba igual (y se avisa de que se usa).
# Si no vale, el motivo junta el de la llamada y el de la comprobacion, para que el reintento sepa que fallo.
function Get-MotivoArnes($T, $C, [string[]]$Jobs) {
  $fallo = Get-MotivoLlamada $C
  if (-not $fallo) { return (Test-Arnes $T $Jobs) }
  if (-not (Test-Path -LiteralPath (Join-Ruta $T.entradas.copia $T.entradas.test))) { return $fallo }
  $m = Test-Arnes $T $Jobs
  if (-not $m) {
    $que = "ha fallado (codigo $($C.Codigo))"
    if ($C.Agotado) { $que = 'se ha pasado del tiempo' }
    Aviso "La IA $que, pero el test que ha dejado vale: lo uso."
    return ''
  }
  return "$fallo Ademas, lo que dejo escrito no vale: $m"
}

# Deshace en la copia del arnes $T lo que la IA cambio fuera de lo permitido (Get-Permitidos) y deja lo permitido como lo dejo: el
# reintento sigue desde ahi.
function Undo-Fuera($T) {
  $dir = $T.entradas.copia
  $permitidos = @(Get-Permitidos $T)
  $dejado = @{}
  foreach ($rel in @(Get-Cambios $dir | Where-Object { $permitidos -contains $_ })) {
    $f = Join-Ruta $dir $rel
    if (Test-Path -LiteralPath $f -PathType Leaf) { $dejado[$rel] = [System.IO.File]::ReadAllBytes($f) }
  }
  Undo-Copia $dir
  foreach ($rel in $dejado.Keys) {
    $f = Join-Ruta $dir $rel
    [void](New-Item -ItemType Directory -Path (Split-Path $f -Parent) -Force)
    [System.IO.File]::WriteAllBytes($f, $dejado[$rel])
  }
}

# Las tareas de arnes pendientes, una detras de otra: primero la del original y, solo cuando esta hecha, la del migrado (que traduce
# su test: se vuelve a calcular su huella con el test del original que acaba de quedar guardado). Cada una con su comprobacion y,
# si falla, su reintento con el motivo. Si la del original queda atascada, la del migrado no se lanza: lo para el arranque.
function Invoke-Arneses($Tareas, [string[]]$Jobs) {
  foreach ($repo in @('original', 'migrado')) {
    foreach ($t in @($Tareas | Where-Object { $_.entradas.repo -eq $repo })) {
      if ($repo -eq 'migrado') {
        if ($ArnesOrig.estado -ne 'hecha') { return }
        $t.entradas.hashOriginal = Get-HashGuardado 'original' $t.entradas.testOriginal
        $t.entradas.huella = Get-HuellaArnes $t.entradas.test $Jobs $t.entradas.hashOriginal
      }
      while ($t.estado -eq 'pendiente') {
        Info "Arnes (el test que ejecuta los casos): $repo..."
        $tope = $Cfg.SegundosPorLlamada
        $Cfg.SegundosPorLlamada = $Cfg.SegundosArnes
        try { $ll = @(Invoke-Lote @($t) $Cfg.EsfuerzoArnes) }
        finally { $Cfg.SegundosPorLlamada = $tope }
        Restore-Base $t.entradas.copia
        $m = Get-MotivoArnes $t $ll[0] $Jobs
        # Una llamada cortada por tiempo que dejo un test que no vale, si queda otro intento: lo escrito se queda para seguir desde ahi
        $sigue = [bool]($m -and $ll[0].Agotado -and ($t.intentos + 1) -lt [int]$Cfg.Intentos -and (Test-Path -LiteralPath (Join-Ruta $t.entradas.copia $t.entradas.test)))
        if (-not $m) { Save-Arnes $t }
        elseif ($sigue) { Undo-Fuera $t }
        else { Undo-Copia $t.entradas.copia }
        $t.entradas.prompt.SI_CORTADO = $MarcaNo
        $t.entradas.prompt.SI_DESHECHO = ''
        if ($sigue) { $t.entradas.prompt.SI_CORTADO = ''; $t.entradas.prompt.SI_DESHECHO = $MarcaNo }
        Set-Intento $t $m
        if ($m) { Aviso "Arnes del $repo rechazado: $(($m -split "`n")[0])" } else { Bien "Arnes del ${repo}: bien." }
      }
    }
  }
}

# El arnes atascado: que ha pasado y el texto para pegar en Copilot en otra ventana.
function Show-Atascado($T) {
  $reg = Join-Path $Registros ($T.id + '-' + $T.intentos + '.log')   # la ultima llamada: su prompt y lo que dijo Copilot
  Fallo "El test PruebaLocalTest del $($T.entradas.repo) ha quedado atascado: $($T.motivo)"
  Info "Lo que dijo Copilot en la ultima llamada esta en ${reg}: abrelo o mandalo."
  Aviso 'Para que te ayude Copilot, pega esto en otra ventana:'
  Info ("Estoy ejecutando prueba-local.ps1 (la prueba en local de un batch Java: el original frente al migrado) y la IA no ha conseguido escribir el test PruebaLocalTest en la copia $($T.entradas.copia). Motivo: $($T.motivo -replace '\s+', ' ') Lo que dijo en la ultima llamada esta en $reg; los demas registros, en $Registros. Dime que falla (por ejemplo, que Maven no descarga las dependencias o que el contexto de Spring no arranca) y como lo arreglo. Despues vuelvo a lanzar el mismo comando.")
}

# ================================ CASOS ================================
# Lo que recibe la tarea de un caso de su job: Pasos y Datos (los hechos que recibio la prueba en pre, de
# Get-ContextoPrueba) y Leer: los ficheros de las clases del job (en el orden del mapa) cuya ficha dice que leen la
# entrada (entrada-fichero o tabla-lee), hasta LeerPorCaso.
function Get-ContextoCaso($JobMapa) {
  $Datos = $DatosMig   # Get-ContextoPrueba y Get-FichasJob (tareas.ps1) leen las fichas de $Datos
  $c = Get-ContextoPrueba $JobMapa
  $leer = @(@(Get-FichasJob $JobMapa | Where-Object { @($_.datos | Where-Object { $_.tipo -eq 'entrada-fichero' -or $_.tipo -eq 'tabla-lee' }).Count -gt 0 }) | Select-Object -First ([int]$Cfg.LeerPorCaso) | ForEach-Object { $_.fichero })
  return [pscustomobject]@{ Pasos = $c.Pasos; Datos = $c.Datos; Leer = $leer }
}

# Las tareas de los casos de un job (caso-01, caso-02... en el orden del guion), o las hechas de antes si sus entradas
# no han cambiado.
function Get-TareasCasos($Prueba, $JobMapa) {
  $ctx = Get-ContextoCaso $JobMapa
  $leer = '(No se sabe que clases leen la entrada de este job: buscalas tu en src/main.)'
  if ($ctx.Leer.Count -gt 0) { $leer = (@($ctx.Leer | ForEach-Object { '- ' + $_ }) -join "`n") }
  if (-not $ctx.Datos) { $ctx.Datos = '(No hay hechos de este job.)' }
  $tareas = @()
  $n = 0
  foreach ($c in @($Prueba.casos)) {
    $n++
    $caso = 'caso-' + $n.ToString('00')
    $carpeta = "$Casos/$($Prueba.job)/$caso"
    $prompt = [pscustomobject]@{ JOB = $Prueba.job; CASO = $caso; CARPETA = $carpeta; TITULO = [string]$c.titulo; ENTRADA = [string]$c.entrada; ESPERADO = [string]$c.esperado; PASOS = $ctx.Pasos; HECHOS = $ctx.Datos; LEER = $leer }
    $huella = Get-Hash8 ((@([string]$c.titulo, [string]$c.entrada, [string]$c.esperado, $ctx.Pasos, $ctx.Datos, $leer, $HeadOrig)) -join "`n")
    $e = [pscustomobject]@{ job = $Prueba.job; caso = $caso; titulo = [string]$c.titulo; carpeta = $carpeta; copia = $CopiaOrig; dirs = @(); huella = $huella; prompt = $prompt }
    $t = Restore-Tarea (New-TareaTipo 'caso-local' ('caso-' + (Get-NombreJob $Prueba.job) + '-' + $n.ToString('00')) '' "prueba-local/casos/$($Prueba.job)/$caso" $e) $false
    $t.entradas.copia = $CopiaOrig   # la de ahora, aunque la tarea venga de otro lanzamiento
    $tareas += , (Test-Guardada $t (Join-Ruta $Local "casos/$($Prueba.job)/$caso"))
  }
  return $tareas
}

# Guarda un caso que ha pasado la comprobacion (en prueba-local\casos\<job>\<caso>); si es no-aplica, lo quita de la
# copia (no se ejecuta).
function Save-Caso($T) {
  $dirCaso = Join-Ruta $CopiaOrig $T.entradas.carpeta
  $dest = Join-Ruta $Local "casos/$($T.entradas.job)/$($T.entradas.caso)"
  Remove-Carpeta $dest
  Copy-Carpeta $dirCaso $dest
  if (Test-Path -LiteralPath (Join-Path $dirCaso 'no-aplica.txt')) { Remove-Carpeta $dirCaso }
}

# Las tareas de los casos pendientes, en rondas de hasta Paralelo llamadas sobre la copia del original. Tras cada ronda:
# si algo se ha escrito fuera de las carpetas de sus casos, se deshace todo y esas tareas se repiten de una en una (sin
# gastar intento: asi se sabe cual fue); si no, cada caso tiene que haber escrito algo y correr en el original, o traer
# no-aplica.txt.
function Invoke-Casos($Tareas) {
  $solas = @{}
  while ($true) {
    $pend = @($Tareas | Where-Object { $_.estado -eq 'pendiente' })
    if ($pend.Count -eq 0) { break }
    $lote = @($pend | Where-Object { -not $solas.ContainsKey($_.id) } | Select-Object -First ([int]$Cfg.Paralelo))
    if ($lote.Count -eq 0) { $lote = @($pend[0]) }
    Info ("Entradas de los casos: preparando $($lote.Count) a la vez (quedan $($pend.Count))...")
    $ll = @(Invoke-Lote $lote $Cfg.EsfuerzoCaso)
    Restore-Base $CopiaOrig
    $suyas = @($lote | ForEach-Object { $_.entradas.carpeta + '/' })
    $fuera = @(Get-Cambios $CopiaOrig | Where-Object { $r = $_; @($suyas | Where-Object { $r.StartsWith($_) }).Count -eq 0 })
    if ($fuera.Count -gt 0) {
      Undo-Copia $CopiaOrig
      $m = 'Has escrito fuera de CARPETA: ' + (@($fuera | Select-Object -First 5) -join ', ') + '. Escribe solo dentro de CARPETA.'
      if ($lote.Count -gt 1) {
        Aviso "Una de estas $($lote.Count) tareas ha escrito fuera de su carpeta ($($fuera[0])): se repiten de una en una."
        foreach ($t in $lote) { $solas[$t.id] = $true }
      }
      else { Set-Intento $lote[0] $m; Aviso "$($lote[0].id) rechazado: $m" }
      continue
    }
    $motivos = @{}
    for ($i = 0; $i -lt $lote.Count; $i++) {
      $t = $lote[$i]
      $dirCaso = Join-Ruta $CopiaOrig $t.entradas.carpeta
      $m = Get-MotivoLlamada $ll[$i]
      if (-not $m -and (-not (Test-Path -LiteralPath $dirCaso) -or @(Get-ChildItem -LiteralPath $dirCaso -Recurse -File).Count -eq 0)) {
        $m = "No has escrito ningun fichero en CARPETA ($($t.entradas.carpeta)); las carpetas vacias no cuentan. Si el caso no necesita ninguna entrada, escribe solo sin-entrada.txt con una frase que lo diga."
      }
      $motivos[$t.id] = $m
    }
    foreach ($t in @($lote | Where-Object { -not $motivos[$_.id] })) {
      if (Test-Path -LiteralPath (Join-Path (Join-Ruta $CopiaOrig $t.entradas.carpeta) 'no-aplica.txt')) { continue }
      $j = $t.entradas.job
      $c = $t.entradas.caso
      $r = Invoke-Job $CopiaOrig $true $j $c "caso $j/$c en el original"
      $sal = Join-Ruta $CopiaOrig "target/prueba-local/$j/$c"
      if (-not (Test-Path -LiteralPath (Join-Path $sal 'estado.txt'))) { $motivos[$t.id] = 'El caso no corre en el original: ' + (Get-Porque $sal $r) }
    }
    foreach ($t in $lote) {
      $m = $motivos[$t.id]
      if ($m) { Remove-Carpeta (Join-Ruta $CopiaOrig $t.entradas.carpeta); Aviso "$($t.id) rechazado: $(($m -split "`n")[0])" } else { Save-Caso $t }
      Set-Intento $t $m
    }
    Save-Copia $CopiaOrig   # los casos buenos de la ronda, por buenos en la copia
  }
}

# ================================ EJECUCION ================================
# Ejecuta en una copia los casos de $Listas, uno a uno, y guarda lo que dejan en prueba-local\salidas\<Nombre>\<job>. Con $Limpiar
# en $false no se borra antes lo que ya hubiera en salidas\<Nombre> (-Reparar mide en dos veces lo de un mismo arreglo).
function Invoke-Salidas([string]$Dir, [bool]$EsOriginal, [string]$Nombre, $Listas, [bool]$Limpiar = $true) {
  $dest = Join-Ruta $Local "salidas/$Nombre"
  if ($Limpiar) { Remove-Carpeta $dest }
  foreach ($j in @($Listas | ForEach-Object { $_.entradas.job } | Select-Object -Unique)) {
    Info "Ejecutando los casos de $j ($Nombre)..."
    foreach ($t in @($Listas | Where-Object { $_.entradas.job -eq $j })) {
      $c = $t.entradas.caso
      $script:Maven["$Nombre|$j|$c"] = Invoke-Job $Dir $EsOriginal $j $c "$Nombre $j $c"
      Copy-Carpeta (Join-Ruta $Dir "target/prueba-local/$j/$c") (Join-Ruta $dest "$j/$c")
    }
  }
}

# Ejecuta en la copia del migrado, con el arnes que ya lleva, los casos de $Listas (con sus entradas guardadas) y guarda lo que
# dejan en prueba-local\salidas\<Nombre>.
function Invoke-Migrado([string]$Nombre, $Listas) {
  Remove-Carpeta (Join-Ruta $CopiaMig $Casos)
  foreach ($t in $Listas) { Copy-Carpeta (Join-Ruta $Local "casos/$($t.entradas.job)/$($t.entradas.caso)") (Join-Ruta $CopiaMig $t.entradas.carpeta) }
  Invoke-Salidas $CopiaMig $false $Nombre $Listas
}

# ================================ COMPARAR ================================
# Las fechas de esta ejecucion: cada dia, en hora local y en UTC, desde $Desde hasta $Hasta. Un job que escribe la fecha en UTC puede
# poner otro dia que el local (a las 00:30 en Espana, el de ayer): las dos cuentan como de hoy.
function Get-Hoy([datetime]$Desde, [datetime]$Hasta) {
  $dias = @()
  foreach ($p in @(@($Desde, $Hasta), @($Desde.ToUniversalTime(), $Hasta.ToUniversalTime()))) {
    for ($d = $p[0].Date; $d -le $p[1].Date; $d = $d.AddDays(1)) { $dias += $d }
  }
  return @($dias | Select-Object -Unique)
}

# Un texto sin lo que cambia de una ejecucion a otra ni de una copia a otra: la ruta de cada copia (<copia>), las fechas con hora de la
# ejecucion ($Hoy: la fecha y la hora juntas pasan a <hora>), las horas sueltas (HH:mm:ss y sus fracciones, sin fecha delante: tambien
# pasan a <hora>) y la fecha de hoy en sus formatos de siempre (cada formato con su marca: un cambio de formato se sigue viendo), con la
# hora pegada detras (aaaammdd_hhmmss). Una fecha con hora que no es de $Hoy es un dato del negocio y se queda como esta, hora incluida:
# si el migrado la cambia (otra zona horaria, un dia de mas), sale distinta.
function Get-Normal([string]$Texto) {
  $t = $Texto
  foreach ($r in $RutasCopia) { $t = $t.Replace($r, '<copia>') }
  foreach ($d in $Hoy) { $t = $t -replace ([regex]::Escape($d.ToString('yyyy-MM-dd', $Inv)) + '[ T]\d{2}:\d{2}:\d{2}(\.\d+)?'), '<hora>' }
  $t = $t -replace '(?<!\d{4}-\d{2}-\d{2}[ T])\b\d{2}:\d{2}:\d{2}(\.\d+)?\b', '<hora>'
  foreach ($d in $Hoy) {
    foreach ($f in @('yyyy-MM-dd', 'dd/MM/yyyy', 'yyyyMMdd', 'ddMMyyyy')) { $t = $t.Replace($d.ToString($f, $Inv), "<hoy:$f>") }
  }
  return ($t -replace '(<hoy:[^>]+>)[_\-T\. ]?\d{6}(\d{3})?(?!\d)', '$1<hora>')
}

# Las lineas de un fichero, normalizadas (los saltos \r\n cuentan como \n y el ultimo salto no cuenta como linea). Se
# leen byte a byte (Latin-1): dos ficheros solo son iguales si sus bytes lo son, este en la codificacion que este.
function Get-LineasNormales([string]$Ruta) {
  $l = @((Get-Normal ($Latin.GetString([System.IO.File]::ReadAllBytes($Ruta)))) -split '\r?\n')
  if ($l.Count -gt 0 -and $l[$l.Count - 1] -eq '') { $l = @($l | Select-Object -First ($l.Count - 1)) }
  return $l
}

# Una linea leida byte a byte, para ensenarla: en UTF-8 si lo es; si no, tal cual (Latin-1).
function Get-Legible([string]$Linea) {
  try { return $Utf8Estricto.GetString($Latin.GetBytes($Linea)) } catch { return $Linea }
}

# Si dos ficheros distintos solo cambian en la codificacion (JEP 400: UTF-8 por defecto desde Java 18) o en el formato
# de numeros o fechas (JEP 252: datos de CLDR desde Java 9), la nota que lo dice; si no, ''.
function Get-NotaJdk([string]$A, [string]$B) {
  $ba = [System.IO.File]::ReadAllBytes($A)
  $bb = [System.IO.File]::ReadAllBytes($B)
  $limpio = { param([string]$s) ((Get-Normal $s.TrimStart([char]0xFEFF)) -replace '\r\n', "`n").TrimEnd("`n") }
  $ua = & $limpio ($Utf8.GetString($ba))
  $ub = & $limpio ($Utf8.GetString($bb))
  if ($ua -ceq $ub -or $ua -ceq (& $limpio ($Latin.GetString($bb))) -or (& $limpio ($Latin.GetString($ba))) -ceq $ub) {
    return 'posible diferencia del JDK: codificacion (JEP 400)'
  }
  $formato = { param([string]$s) (($s -replace '[\u00a0\u202f]', ' ') -replace "(?<=\d)[\.,' ](?=\d)", '' -replace '(?<=[A-Za-z])\.', '').ToLowerInvariant() }
  if ((& $formato $ua) -ceq (& $formato $ub)) { return 'posible diferencia del JDK: formato de numeros o fechas (JEP 252)' }
  return ''
}

# Compara dos ficheros ('' si falta uno) linea a linea, normalizados. $null si son iguales; si no, Lineas (cuantas son
# distintas, posicion a posicion), Linea (la primera, desde 1), Original y Migrado (esa linea en cada lado) y Nota.
function Compare-Fichero([string]$A, [string]$B) {
  $x = @(); $y = @()
  if ($A) { $x = @(Get-LineasNormales $A) }
  if ($B) { $y = @(Get-LineasNormales $B) }
  $n = 0
  $primera = -1
  for ($i = 0; $i -lt [Math]::Max($x.Count, $y.Count); $i++) {
    $va = $null; $vb = $null
    if ($i -lt $x.Count) { $va = $x[$i] }
    if ($i -lt $y.Count) { $vb = $y[$i] }
    if ($va -cne $vb) { $n++; if ($primera -lt 0) { $primera = $i } }
  }
  if ($A -and $B -and $n -eq 0) { return $null }
  if ($primera -lt 0) { $primera = 0 }
  $lado = { param($L, [string]$Ruta) if (-not $Ruta) { '(no esta)' } elseif ($primera -lt $L.Count) { Get-Legible ([string]$L[$primera]) } else { '(no hay)' } }
  $nota = ''
  if ($A -and $B) { $nota = Get-NotaJdk $A $B }
  return [pscustomobject]@{ Lineas = [Math]::Max($n, 1); Linea = ($primera + 1); Original = (& $lado $x $A); Migrado = (& $lado $y $B); Nota = $nota }
}

# Las diferencias entre lo que dejo un caso en dos carpetas: una por fichero que no coincide (con su ruta relativa).
# Los ficheros se emparejan por la ruta normalizada (un nombre con la fecha de hoy vale en los dos lados), distinguiendo
# mayusculas.
function Compare-Caso([string]$A, [string]$B) {
  $pares = New-Object System.Collections.Hashtable ([System.StringComparer]::Ordinal)
  foreach ($lado in @(@('A', $A), @('B', $B))) {
    if (-not (Test-Path -LiteralPath $lado[1])) { continue }
    foreach ($f in @(Get-ChildItem -LiteralPath $lado[1] -Recurse -File)) {
      $rel = Get-Rel $lado[1] $f.FullName
      $k = Get-Normal $rel
      if (-not $pares.ContainsKey($k)) { $pares[$k] = @{ A = ''; B = ''; Rel = $rel } }
      $pares[$k][$lado[0]] = $f.FullName
    }
  }
  $dif = @()
  foreach ($k in @($pares.Keys | Sort-Object)) {
    $p = $pares[$k]
    $c = Compare-Fichero $p.A $p.B
    if ($c) { $dif += [ordered]@{ fichero = $p.Rel; lineas = $c.Lineas; linea = $c.Linea; original = $c.Original; migrado = $c.Migrado; nota = $c.Nota } }
  }
  return $dif
}

# El resultado de un caso: igual, distinto (con sus diferencias), no determinista, no se pudo preparar o sin probar en
# local, con su motivo. Los ficheros que cambian entre las dos ejecuciones del original no se comparan; el resto, si.
# Un caso igual que deja lo mismo que el caso vacio del arnes lleva un aviso: puede que su entrada no llegue al job.
# Si Maven se ha pasado del tope en una de sus tres ejecuciones, no se pudo preparar y el motivo es el mensaje del tope.
# $Nombre es donde esta lo del migrado: salidas\<Nombre> (el migrado de siempre, o el de un commit de la busqueda de -Desde).
function Get-Resultado($T, [string]$Nombre = 'migrado') {
  $script:Hoy = @(Get-Hoy $Inicio (Get-Date))   # la busqueda de -Desde puede pasar de medianoche
  $j = $T.entradas.job
  $c = $T.entradas.caso
  $o = [ordered]@{ job = $j; caso = $c; titulo = $T.entradas.titulo; resultado = 'no se pudo preparar'; motivo = ''; diferencias = @() }
  $s1 = Join-Ruta $Local "salidas/original/$j/$c"
  $noAplica = Join-Ruta $Local "casos/$j/$c/no-aplica.txt"
  $parado = @(@('original', 'original-2', $Nombre) | ForEach-Object { $script:Maven["$_|$j|$c"] } | Where-Object { $_ -and $_.Tope })
  if ($parado.Count -gt 0) { $o.motivo = $parado[0].Tope; return $o }
  if ($T.estado -ne 'hecha') { $o.motivo = "La IA no ha podido preparar sus entradas: $($T.motivo)"; return $o }
  if (Test-Path -LiteralPath $noAplica) { $o.resultado = 'sin probar en local'; $o.motivo = ([System.IO.File]::ReadAllText($noAplica, $Utf8) -replace '\s+', ' ').Trim(); return $o }
  if (-not (Test-Path -LiteralPath (Join-Path $s1 'estado.txt'))) { $o.motivo = 'En el original ' + (Get-Porque $s1 $script:Maven["original|$j|$c"]); return $o }
  if ($ArnesMig.estado -ne 'hecha') { $o.motivo = 'El migrado no tiene su test PruebaLocalTest (el arnes ha quedado atascado).'; return $o }
  $azar = @(Compare-Caso $s1 (Join-Ruta $Local "salidas/original-2/$j/$c"))
  $sinContar = @($azar | ForEach-Object { Get-Normal $_.fichero })
  if ($azar.Count -gt 0) { $o.motivo = 'No se comparan, porque el original da dos salidas distintas: ' + (@($azar | Select-Object -First 3 | ForEach-Object { $_.fichero }) -join ', ') + '.' }
  $d = @(Compare-Caso $s1 (Join-Ruta $Local "salidas/$Nombre/$j/$c") | Where-Object { $sinContar -notcontains (Get-Normal $_.fichero) })
  if ($d.Count -gt 0) { $o.resultado = 'distinto'; $o.diferencias = $d; return $o }
  if ($azar.Count -gt 0) { $o.resultado = 'no determinista'; return $o }
  $o.resultado = 'igual'
  $vacio = Join-Ruta $Local "salidas/vacio/$j"
  if ((Test-Path -LiteralPath $vacio) -and @(Compare-Caso $s1 $vacio).Count -eq 0) { $o.motivo = $MotivoVacio }
  return $o
}

# La tabla por consola y lo que no es igual, caso a caso.
function Show-Resultado($Res, $PorJob) {
  Info ''
  Info 'Prueba en local: el original frente al migrado, con las mismas entradas'
  $fmt = '{0,-32} {1,6} {2,8} {3,10} {4,11}'
  Info ($fmt -f 'Job', 'Casos', 'Iguales', 'Distintos', 'Sin probar')
  foreach ($p in $PorJob) { Info ($fmt -f $p.job, $p.casos, $p.iguales, $p.distintos, $p.sinProbar) }
  foreach ($r in @($Res | Where-Object { $_.resultado -ne 'igual' -or $_.motivo })) {
    $donde = "$($r.job)/$($r.caso) ($($r.titulo))"
    if ($r.resultado -eq 'distinto') {
      Fallo "  distinto: $donde"
      if ($r.motivo) { Aviso "    $($r.motivo)" }
      foreach ($d in @($r.diferencias | Select-Object -First 3)) {
        Info "    $($d.fichero): lineas distintas: $($d.lineas); la primera, la $($d.linea):"
        Info "      original: $($d.original)"
        Info "      migrado:  $($d.migrado)"
        if ($d.nota) { Aviso "      ($($d.nota))" }
      }
    }
    else { Aviso "  $($r.resultado): $donde. $(($r.motivo -split "`n")[0])" }
  }
}

# ======================== CULPABLES (-Desde y -Deshacer) ========================
# De cada caso distinto, el primer commit de la rama que se prueba donde deja de ser igual (con -Desde) y, si se pide, su
# git revert (con -Deshacer). Todo se ejecuta en <Migrado>-prueba-local, rehecha en cada commit, con el arnes y el caso ya
# guardados, y se compara con salidas\original: nunca se llama a Copilot.
# Lo que usan, del main: $DirRama (la carpeta de la rama que se prueba), $DesdeCommit, $headMig, $tareasCasos, $listas y $pruebas.

# El asunto (primera linea del mensaje) de un commit del migrado.
function Get-Asunto([string]$Commit) { return ((Invoke-Git $MigradoRoot @('log', '-1', '--format=%s', $Commit)).Salida -join ' ').Trim() }

# Las primeras lineas con texto de $Texto, en una sola linea.
function Get-Resumen([string]$Texto) {
  return ((@($Texto -split "`n" | Where-Object { $_.Trim() } | Select-Object -First 3) -join ' ') -replace '\s+', ' ').Trim()
}

function Get-TareaCaso([string]$Job, [string]$Caso) {
  return @($tareasCasos | Where-Object { $_.entradas.job -ceq $Job -and $_.entradas.caso -ceq $Caso })[0]
}

# Un resultado de Get-Resultado que no es bueno: igual y no determinista son buenos; todo lo demas, no.
function Test-Malo($Res) { return ($Res.resultado -ne 'igual' -and $Res.resultado -ne 'no determinista') }

# Como esta el caso $T en el migrado de $Commit: Malo ($true si sale distinto o no se puede ejecutar), Motivo (por que no se
# pudo ejecutar, o '': con motivo, el commit ni es bueno ni es malo, Find-Culpable lo salta) y Resultado (lo de Get-Resultado,
# comparado con salidas\original). Lo ya visto de un (commit, job, caso) se guarda en $script:Estados y no se vuelve a ejecutar.
function Get-EstadoEn([string]$Commit, $T) {
  $j = $T.entradas.job
  $c = $T.entradas.caso
  $clave = "$Commit|$j|$c"
  if ($script:Estados.ContainsKey($clave)) { return $script:Estados[$clave] }
  Info "  Probando $j/$c en $($Commit.Substring(0, 7))..."
  $m = New-Copia $MigradoRoot $Commit $CopiaMig
  if ($m) { Stop-Arranque $m }
  Remove-Carpeta (Join-Ruta $CopiaMig $Casos)
  Copy-Carpeta (Join-Ruta $Local 'arnes/migrado') $CopiaMig
  Copy-Carpeta (Join-Ruta $Local "casos/$j/$c") (Join-Ruta $CopiaMig $T.entradas.carpeta)
  $nombre = 'culpable/' + $Commit.Substring(0, 12)
  $dest = Join-Ruta $Local "salidas/$nombre/$j/$c"
  Remove-Carpeta $dest
  $mvn = Invoke-Job $CopiaMig $false $j $c "$nombre $j $c"
  $script:Maven["$nombre|$j|$c"] = $mvn
  Copy-Carpeta (Join-Ruta $CopiaMig "target/prueba-local/$j/$c") $dest
  $res = Get-Resultado $T $nombre
  $malo = (Test-Malo $res)
  $motivo = ''
  if ($malo -and -not (Test-Path -LiteralPath (Join-Path $dest 'estado.txt'))) { $motivo = Get-Resumen (Get-Porque $dest $mvn) }
  elseif ($malo -and $res.resultado -ne 'distinto') { $motivo = Get-Resumen $res.motivo }
  $e = [pscustomobject]@{ Malo = $malo; Motivo = $motivo; Resultado = $res }
  $script:Estados[$clave] = $e
  return $e
}

# El commit que rompe el caso $T, buscado por biseccion en $Commits (los de la rama despues de -Desde, del mas viejo al mas
# nuevo; el ultimo, el HEAD, ya se sabe que es malo). Un commit donde el caso no se pudo ejecutar (no compila, Maven se pasa del
# tope...) ni es bueno ni es malo: se salta, como git bisect skip, y se prueba otro. $null, y sin culpable, si el caso ya era distinto
# en -Desde o si solo quedan commits saltados antes del malo (no se puede decir cual rompe).
function Find-Culpable($T, [string[]]$Commits) {
  $j = $T.entradas.job
  $c = $T.entradas.caso
  $e0 = Get-EstadoEn $DesdeCommit $T
  if ($e0.Malo) {
    $m = "El caso $j/$c ya era distinto en $($DesdeCommit.Substring(0, 7))."
    if ($e0.Motivo) { $m += " (En ese commit no se pudo ejecutar: $($e0.Motivo))" }
    Aviso $m
    return $null
  }
  $lo = 0
  $hi = $Commits.Count - 1
  $saltados = @{}   # indice -> por que no se pudo ejecutar el caso en ese commit
  while ($lo -lt $hi) {
    $libres = @($lo..($hi - 1) | Where-Object { -not $saltados.ContainsKey($_) })
    if ($libres.Count -eq 0) { break }
    $mid = $libres[[int][Math]::Floor($libres.Count / 2)]
    $e = Get-EstadoEn $Commits[$mid] $T
    if ($e.Motivo) { $saltados[$mid] = $e.Motivo }
    elseif ($e.Malo) { $hi = $mid }
    else { $lo = $mid + 1 }
  }
  if ($lo -lt $hi) {
    $lista = (@($lo..$hi | ForEach-Object { $Commits[$_].Substring(0, 7) + ' (' + (Get-Asunto $Commits[$_]) + ')' }) -join ', ')
    Aviso "El caso ${j}/${c}: no se puede decir que commit lo rompe, es uno de estos: $lista. Los saltados son commits donde no se pudo ejecutar el caso (como git bisect skip). No deshago nada."
    foreach ($i in @($saltados.Keys | Sort-Object)) { Info "  En $($Commits[$i].Substring(0, 7)) no se pudo ejecutar el caso: $($saltados[$i])" }
    return $null
  }
  $asunto = Get-Asunto $Commits[$lo]
  Fallo "El caso $j/$c era igual en $($DesdeCommit.Substring(0, 7)) y se rompe en $($Commits[$lo].Substring(0, 7)) ($asunto)."
  if ($saltados.Count -gt 0) { Aviso ('  Commits saltados (no se pudo ejecutar el caso): ' + ((@($saltados.Keys | Sort-Object | ForEach-Object { $Commits[$_].Substring(0, 7) })) -join ', ')) }
  return [pscustomobject]@{ job = $j; caso = $c; commit = $Commits[$lo]; asunto = $asunto; deshecho = $false; indice = $lo }
}

# Los commits que rompen cada caso distinto de $Res (uno por caso, con su posicion en la rama).
function Find-Culpables($Res) {
  $distintos = @($Res | Where-Object { $_.resultado -eq 'distinto' })
  Info ''
  if ($distintos.Count -eq 0) { Info 'Con -Desde: no hay casos distintos que buscar.'; return @() }
  $commits = @((Invoke-Git $DirRama @('rev-list', '--first-parent', '--reverse', ($DesdeCommit + '..' + $headMig))).Salida | Where-Object { $_ })
  Remove-Carpeta (Join-Ruta $Local 'salidas/culpable')
  Remove-Carpeta (Join-Ruta $Local 'salidas/despues')
  Info "Buscando que commit rompe cada caso distinto ($($commits.Count) commits despues de $($DesdeCommit.Substring(0, 7)))..."
  $culpables = @()
  foreach ($r in $distintos) {
    $script:Estados["$headMig|$($r.job)|$($r.caso)"] = [pscustomobject]@{ Malo = $true; Motivo = ''; Resultado = $r }   # el HEAD ya se ha comparado
    $x = Find-Culpable (Get-TareaCaso $r.job $r.caso) $commits
    if ($x) { $culpables += $x }
  }
  return $culpables
}

# Tiene $DirRama cambios sin commit? (-Deshacer y -Reparar no trabajan sobre una carpeta sucia)
function Test-RamaSucia { return (@((Invoke-Git $DirRama @('status', '--porcelain')).Salida | Where-Object { $_ }).Count -gt 0) }

# Por que no se puede deshacer $Commit en $DirRama, o '' si se puede.
function Get-NoDeshacer([string]$Commit) {
  if (Test-RamaSucia) { return "$DirRama tiene cambios sin commit (git status): guardalos o descartalos y vuelve a lanzar con -Deshacer." }
  $linea = ((Invoke-Git $DirRama @('rev-list', '--parents', '-n', '1', $Commit)).Salida -join '').Trim()
  if (@($linea -split '\s+').Count -gt 2) { return 'es un commit de merge: deshazlo a mano (git revert -m 1).' }
  return ''
}

# git revert --no-edit de $Commit en $DirRama (nunca un reset). Si falla, lo aborta y la carpeta queda como estaba.
# Devuelve '' o el motivo.
function Invoke-Revert([string]$Commit) {
  $r = Invoke-Git $DirRama @('revert', '--no-edit', $Commit)
  if ($r.Codigo -eq 0) { return '' }
  $que = 'git revert ha fallado'
  if (@((Invoke-Git $DirRama @('ls-files', '--unmerged')).Salida | Where-Object { $_ }).Count -gt 0) { $que = 'el revert da conflicto' }   # ficheros sin fusionar: no depende del idioma de git
  [void](Invoke-Git $DirRama @('revert', '--abort'))
  return ($que + ' y lo he abortado (el HEAD queda como estaba): ' + (Get-Resumen ($r.Salida -join "`n")))
}

# Vuelve a ejecutar en el migrado de $Commit todos los casos de $listas (solo Maven, nunca Copilot) y pone en $Res, caso a caso,
# lo que sale ahora: nada se da por medido en un commit donde no se ha ejecutado.
function Measure-Migrado([string]$Commit, $Res) {
  $nombre = 'despues/' + $Commit.Substring(0, 12)
  Info "Vuelvo a ejecutar todos los casos del migrado en $($Commit.Substring(0, 7))..."
  $m = New-Copia $MigradoRoot $Commit $CopiaMig
  if ($m) { Stop-Arranque $m }
  Copy-Carpeta (Join-Ruta $Local 'arnes/migrado') $CopiaMig
  Invoke-Migrado $nombre $listas
  for ($i = 0; $i -lt $tareasCasos.Count; $i++) { $Res[$i] = Get-Resultado $tareasCasos[$i] $nombre }
}

function Get-ResultadoDe($Res, $Culpable) { return @($Res | Where-Object { $_.job -ceq $Culpable.job -and $_.caso -ceq $Culpable.caso })[0] }

# Con -Deshacer: revierte los commits de $Culpables (el mas nuevo primero) y vuelve a ejecutar TODOS los casos en el nuevo HEAD
# (Measure-Migrado): un revert puede arreglar un caso y romper otro. Un commit cuyo revert no arregla ninguno de sus casos se
# vuelve a dejar como estaba, con otro git revert del revert (el mas nuevo primero) y otra medida. Apunta en cada culpable si
# queda deshecho y en $script:Propios los commits que ha hecho (los unicos cambios que se dan por buenos en la carpeta). Pone
# en su sitio, en $Res, el resultado de ahora.
function Undo-Culpables($Culpables, $Res) {
  $commits = @($Culpables | Sort-Object -Property indice -Descending | ForEach-Object { $_.commit } | Select-Object -Unique)
  if ($commits.Count -eq 0) { return }
  Info ''
  Info "Deshaciendo con git revert en ${DirRama}: $($commits.Count) commit(s), del mas nuevo al mas viejo..."
  $reverts = @{}   # commit deshecho -> su commit de revert
  foreach ($commit in $commits) {
    $suyos = @($Culpables | Where-Object { $_.commit -eq $commit })
    $m = Get-NoDeshacer $commit
    if (-not $m) { $m = Invoke-Revert $commit }
    if ($m) { Aviso "No deshago $($commit.Substring(0, 7)) ($($suyos[0].asunto)): $m"; continue }
    $nuevo = Get-Head $DirRama
    $script:Propios += $nuevo
    $reverts[$commit] = $nuevo
    foreach ($x in $suyos) { $x.deshecho = $true }
    Bien "Deshecho $($commit.Substring(0, 7)) ($($suyos[0].asunto)) con el commit $($nuevo.Substring(0, 7))."
  }
  if ($reverts.Count -eq 0) { return }
  $script:headMig = Get-Head $DirRama
  Measure-Migrado $script:headMig $Res
  $quitado = $false
  $quitar = @($commits | Where-Object { $reverts.ContainsKey($_) })
  [array]::Reverse($quitar)   # el ultimo revert, primero
  foreach ($commit in $quitar) {
    $corto = $commit.Substring(0, 7)
    $suyos = @($Culpables | Where-Object { $_.commit -eq $commit })
    foreach ($x in $suyos) {
      $r = Get-ResultadoDe $Res $x
      if (-not (Test-Malo $r)) { Bien "El caso $($x.job)/$($x.caso): ahora igual tras deshacer $corto."; continue }
      Fallo "El caso $($x.job)/$($x.caso): sigue sin ser igual tras deshacer ${corto}: $($r.resultado)."
      if ($r.resultado -ne 'distinto' -and $r.motivo) { Aviso "  $(Get-Resumen $r.motivo)" }
    }
    if (@($suyos | Where-Object { -not (Test-Malo (Get-ResultadoDe $Res $_)) }).Count -gt 0) { continue }
    Fallo "Deshacer $corto no arregla $((@($suyos | ForEach-Object { "$($_.job)/$($_.caso)" })) -join ', '): lo vuelvo a dejar como estaba"
    $m = Invoke-Revert $reverts[$commit]
    if ($m) { Aviso "No he podido quitar el revert de ${corto}: $m (el revert se queda)"; continue }
    $script:Propios += (Get-Head $DirRama)
    foreach ($x in $suyos) { $x.deshecho = $false }
    $quitado = $true
  }
  if ($quitado) {
    $script:headMig = Get-Head $DirRama
    Measure-Migrado $script:headMig $Res
  }
}

# Es la huella de $Dir de ahora la de antes? Solo se admite una diferencia: en la carpeta donde -Deshacer ha hecho sus commits
# de revert o -Reparar los de sus arreglos, el HEAD de ahora puede ser el de antes con encima exactamente esos commits (y nada mas:
# lo demas de la huella, los cambios sin commit, tiene que ser igual).
function Test-MismaHuella([string]$Dir, [string]$Antes, [string]$Despues) {
  if ($Antes -ceq $Despues) { return $true }
  if ($Dir -ne $DirRama -or @($script:Propios).Count -eq 0) { return $false }
  $a = $Antes -split "`n", 2
  $d = $Despues -split "`n", 2
  if ($a.Count -ne 2 -or $d.Count -ne 2 -or $a[1] -cne $d[1]) { return $false }
  if ((Invoke-Git $Dir @('merge-base', '--is-ancestor', $a[0], $d[0])).Codigo -ne 0) { return $false }
  $nuevos = @((Invoke-Git $Dir @('rev-list', ($a[0] + '..' + $d[0]))).Salida | Where-Object { $_ })
  return ($nuevos.Count -eq @($script:Propios).Count -and @($nuevos | Where-Object { $script:Propios -notcontains $_ }).Count -eq 0)
}

# ======================== REPARAR (-Reparar) ========================
# Con -Reparar, la clave de diferencia (Get-Normal del fichero) con mas casos distintos se le da a la IA, que escribe un arreglo en la copia
# del migrado (<Migrado>-prueba-local, con el arnes y los casos ya guardados). El script lo da por bueno si pasa seis puertas, de la mas
# barata a la mas cara (Test-Arreglo); lo bueno va a $DirRama (la rama de rescate) en un commit por arreglo, y lo demas se deshace. Tu
# carpeta y tu rama no se tocan. $S es el estado del lanzamiento: Res (los resultados de ahora, uno por tarea de $tareasCasos), Salidas
# (en que carpeta de salidas\ esta lo medido del migrado), N (los intentos hechos), Base (los tests unitarios de partida) y Probadas (las
# claves ya tocadas). Lo que usan, del main: $DirRama, $CopiaMig, $LegacyRoot, $Local, $headMig y $tareasCasos.

# Ordena textos en orden ordinal (el de Sort-Object va por la cultura).
function Sort-Ordinal([string[]]$Textos) {
  $a = [string[]]@($Textos)
  [System.Array]::Sort($a, [System.StringComparer]::Ordinal)
  return $a
}

# Un caso se puede reparar y comparar si se ha podido ejecutar en las tres ejecuciones.
function Test-Ejecutable($R) { return (@('igual', 'distinto', 'no determinista') -contains $R.resultado) }

# Las lineas distintas de un resultado, todas juntas: la puntuacion que un arreglo tiene que bajar.
function Get-Puntuacion($R) {
  $n = 0
  foreach ($d in @($R.diferencias)) { $n += [int]$d.lineas }
  return $n
}

# Las claves de un resultado: el nombre normalizado de cada fichero que sale distinto.
function Get-Claves($R) { return @(@($R.diferencias) | ForEach-Object { Get-Normal $_.fichero } | Select-Object -Unique) }

function Get-IndiceCaso($Res, [string]$Job, [string]$Caso) {
  for ($i = 0; $i -lt @($Res).Count; $i++) { if ($Res[$i].job -ceq $Job -and $Res[$i].caso -ceq $Caso) { return $i } }
  return -1
}

# La clave que toca arreglar: la que tienen mas casos distintos (a igualdad, la menor en orden ordinal) sin contar las ya probadas, con
# su primer caso (por job y caso). $null si no queda ninguna.
function Find-Clave($Res, $Probadas) {
  $casos = @{}
  foreach ($r in @($Res | Where-Object { $_.resultado -eq 'distinto' })) {
    foreach ($k in @(Get-Claves $r)) {
      if ($Probadas.ContainsKey($k)) { continue }
      if (-not $casos.ContainsKey($k)) { $casos[$k] = @() }
      $casos[$k] += ($r.job + "`t" + $r.caso)
    }
  }
  if ($casos.Count -eq 0) { return $null }
  $max = (@($casos.Values | ForEach-Object { @($_).Count }) | Measure-Object -Maximum).Maximum
  $clave = @(Sort-Ordinal @($casos.Keys | Where-Object { @($casos[$_]).Count -eq $max }))[0]
  $j, $c = (@(Sort-Ordinal @($casos[$clave]))[0]) -split "`t", 2
  return [pscustomobject]@{ clave = $clave; job = $j; caso = $c; casos = @($casos[$clave]).Count }
}

# La tarea de IA que arregla la clave $C en su primer caso, con el resultado $R de ahora, o la de otro lanzamiento si quedo atascada con
# este mismo HEAD y con este mismo test del migrado (el id lleva los dos: con otro arnes, una clave que salio 'no se arregla' se vuelve a
# probar). Trabaja en la copia del migrado y puede leer el original y las salidas y entradas del caso.
function Get-TareaReparar($C, $R, $S) {
  $tc = Get-TareaCaso $C.job $C.caso
  $d = @($R.diferencias | Where-Object { (Get-Normal $_.fichero) -ceq $C.clave })[0]
  $otras = @($R.diferencias | Where-Object { (Get-Normal $_.fichero) -cne $C.clave } | Select-Object -First 5 | ForEach-Object { '- `{0}`: {1} lineas distintas; la primera, la {2}: original [{3}], migrado [{4}]' -f $_.fichero, $_.lineas, $_.linea, $_.original, $_.migrado })
  if ($otras.Count -eq 0) { $otras = @('(No hay otras diferencias en este caso.)') }
  $salOrig = Join-Ruta $Local "salidas/original/$($C.job)/$($C.caso)"
  $salMig = Join-Ruta $Local "salidas/$($S.Salidas)/$($C.job)/$($C.caso)"
  $entradas = Join-Ruta $Local "casos/$($C.job)/$($C.caso)"
  $id = 'reparar-' + (Get-Hash8 "$headMig|$($C.job)|$($C.caso)|$($C.clave)|$(Get-HashGuardado 'migrado' $ArnesMig.entradas.test)")
  $prompt = [pscustomobject]@{
    JOB = $C.job; CASO = $C.caso; TITULO = [string]$tc.entradas.titulo; ENTRADA = [string]$tc.entradas.prompt.ENTRADA; ESPERADO = [string]$tc.entradas.prompt.ESPERADO
    FICHERO = $d.fichero; LINEAS = "$($d.lineas)"; LINEA = "$($d.linea)"; ORIGINAL = [string]$d.original; MIGRADO = [string]$d.migrado; OTRAS = ($otras -join "`n")
    RUTA_ORIGINAL = $LegacyRoot; SAL_ORIGINAL = $salOrig; SAL_MIGRADO = $salMig; ENTRADAS = $entradas; DIFF = ''
  }
  $e = [pscustomobject]@{ job = $C.job; caso = $C.caso; clave = $C.clave; copia = $CopiaMig; dirs = @($LegacyRoot, $salOrig, $salMig, $entradas); huella = (Get-Hash8 ((Get-Plantilla 'reparar') + '|' + $id)); prompt = $prompt }
  $t = Restore-Tarea (New-TareaTipo 'reparar' $id '' "prueba-local/reparar/$id" $e) $true
  $t.entradas.copia = $CopiaMig   # la de ahora, aunque la tarea venga de otro lanzamiento
  return $t
}

# Ejecuta en la copia la suite de tests unitarios, sin el arnes (Surefire sin **/PruebaLocalTest*, y sin parar por los fallos), y cuenta lo
# que dicen sus TEST-*.xml: Fallos (failures + errors), Ejecutados (tests - skipped) y Nombres (los tests que fallan). Con Motivo, Maven
# no ha podido (no compila, se paso del tope...).
function Measure-Tests([string]$Que) {
  $excluir = Join-Path $Local 'reparar-excluir.txt'
  [System.IO.File]::WriteAllText($excluir, "**/PruebaLocalTest*`n", $Utf8)
  $informes = Join-Ruta $CopiaMig 'target/surefire-reports'
  Remove-Carpeta $informes
  $r = Invoke-Maven $CopiaMig $false @('test', "-Dsurefire.excludesFile=$excluir", '-Dmaven.test.failure.ignore=true') $Que
  $m = [pscustomobject]@{ Motivo = ''; Fallos = 0; Ejecutados = 0; Nombres = @() }
  if ($r.Codigo -ne 0 -or $r.Tope) { $m.Motivo = "Los tests unitarios no se pueden ejecutar. Maven dice:`n" + (Get-FalloMaven $r); return $m }
  if (-not (Test-Path -LiteralPath $informes)) { return $m }
  foreach ($f in @(Get-ChildItem -LiteralPath $informes -File -Filter 'TEST-*.xml')) {
    $x = ([xml][System.IO.File]::ReadAllText($f.FullName, $Utf8)).DocumentElement
    $m.Fallos += [int]$x.GetAttribute('failures') + [int]$x.GetAttribute('errors')
    $m.Ejecutados += [int]$x.GetAttribute('tests') - [int]$x.GetAttribute('skipped')
    foreach ($t in @($x.SelectNodes('testcase[failure or error]'))) { $m.Nombres += ($t.GetAttribute('classname') + '.' + $t.GetAttribute('name')) }
  }
  return $m
}

# Que hay peor en $Despues que en $Antes (dos resultados del mismo caso, que se podia ejecutar): '' si nada; si no, como y cual.
function Get-Empeora($Antes, $Despues) {
  $caso = "$($Antes.job)/$($Antes.caso)"
  if (-not (Test-Ejecutable $Despues)) { return "El caso $caso ya no se puede ejecutar ($($Despues.resultado)): $(Get-Resumen $Despues.motivo)" }
  $viejas = @(Get-Claves $Antes)
  $nueva = @($Despues.diferencias | Where-Object { $viejas -cnotcontains (Get-Normal $_.fichero) })[0]
  if ($nueva) { return "El caso $caso sale peor: antes era $($Antes.resultado) y ahora es $($Despues.resultado), con una diferencia nueva en $($nueva.fichero) (linea $($nueva.linea): original [$($nueva.original)], migrado [$($nueva.migrado)])." }
  $antes = Get-Puntuacion $Antes
  $ahora = Get-Puntuacion $Despues
  if ($ahora -gt $antes) { return "El caso $caso sale peor: antes tenia $antes lineas distintas y ahora $ahora." }
  return ''
}

# Las lineas del diff de lo que ha cambiado la IA en la copia (lo nuevo tambien) frente a su base. Deja el indice como estaba.
function Get-DiffCopia {
  [void](Invoke-Git $CopiaMig @('add', '-A', '--', '.', ':(exclude).rescate', ':(exclude)target'))
  $d = @((Invoke-Git $CopiaMig @('diff', '--cached', $script:Base[$CopiaMig].Arbol)).Salida)
  Restore-Base $CopiaMig
  return $d
}

# La IA prueba su arreglo ejecutando el batch (mvn test), que puede dejar ficheros nuevos fuera de src/ (un log, una base en fichero, una
# carpeta de salida): no son suyos. Borra de la copia lo nuevo fuera de src/ (sin seguimiento, ni ignorado ni de .rescate ni de target) y
# devuelve las rutas que quita. Lo cambiado o borrado de lo que ya tenia seguimiento, y lo nuevo bajo src/, no se toca.
function Remove-NuevosFueraDeSrc([string]$Dir) {
  $fuera = @('--', '.', ':(exclude)src', ':(exclude).rescate', ':(exclude)target')
  $nuevos = @((Invoke-Git $Dir (@('-c', 'core.quotepath=off', 'ls-files', '--others', '--exclude-standard') + $fuera)).Salida | Where-Object { $_ })
  if ($nuevos.Count -gt 0) { [void](Invoke-Git $Dir (@('clean', '-fdq') + $fuera)) }
  return $nuevos
}

# Pasa lo que ha dejado la IA en la copia tras la llamada $Ll de la tarea $T por las puertas, de la mas barata a la mas cara. Devuelve:
# Tipo ('rechazado', 'no se arregla' o 'bien'), Motivo, ConDiff (si hay un diff que ensenar en el reintento: no, si fallo la llamada) y,
# si es bueno, Nuevos (los resultados medidos de ahora, por posicion en $S.Res). Las salidas medidas quedan en salidas\reparar\<n>.
function Test-Arreglo($T, $Ll, $S) {
  $v = [pscustomobject]@{ Tipo = 'rechazado'; Motivo = ''; ConDiff = $true; Nuevos = @{} }
  $j = $T.entradas.job
  $c = $T.entradas.caso
  # 1. la llamada acabo bien
  $v.Motivo = Get-MotivoLlamada $Ll
  if ($v.Motivo) { $v.ConDiff = $false; return $v }
  # 2. la IA dice que no se arregla
  $no = Join-Ruta $CopiaMig '.rescate/reparar-no.txt'
  if (Test-Path -LiteralPath $no) {
    $v.Tipo = 'no se arregla'
    $v.Motivo = Get-Resumen ([System.IO.File]::ReadAllText($no, $Utf8))
    if (-not $v.Motivo) { $v.Motivo = 'La IA no da el motivo.' }
    return $v
  }
  # 3. algo cambiado y solo en src/main/ (lo nuevo fuera de src/ lo ha dejado la ejecucion del batch: se quita y no cuenta)
  $ruido = @(Remove-NuevosFueraDeSrc $CopiaMig)
  if ($ruido.Count -gt 0) {
    $nombres = (@($ruido | Select-Object -First 5) -join ', ')
    if ($ruido.Count -gt 5) { $nombres += " y $($ruido.Count - 5) mas" }
    Info "Quito lo que ha dejado la ejecucion fuera de src/: $nombres"
  }
  $cambios = @(Get-Cambios $CopiaMig)
  $fuera = @($cambios | Where-Object { -not $_.StartsWith('src/main/') })
  if ($cambios.Count -eq 0) { $v.Motivo = 'No has cambiado ningun fichero de src/main/.'; return $v }
  if ($fuera.Count -gt 0) { $v.Motivo = 'Solo puedes cambiar ficheros de src/main/, y has cambiado tambien: ' + (@($fuera | Select-Object -First 5) -join ', ') + '. Deja todo lo demas como estaba.'; return $v }
  # 4. el caso de la tarea, ejecutado: su puntuacion tiene que bajar
  $nombre = "reparar/$($S.N)"
  $i = Get-IndiceCaso $S.Res $j $c
  Invoke-Salidas $CopiaMig $false $nombre @($tareasCasos[$i])
  $r = Get-Resultado $tareasCasos[$i] $nombre
  if (-not (Test-Ejecutable $r)) { $v.Motivo = "Con tu cambio el caso $j/$c ya no se puede ejecutar ($($r.resultado)): $(Get-Resumen $r.motivo)"; return $v }
  $antes = Get-Puntuacion $S.Res[$i]
  if ((Get-Puntuacion $r) -ge $antes) {
    $v.Motivo = "Con tu cambio el caso $j/$c sigue igual de distinto: $(Get-Puntuacion $r) lineas distintas y antes eran $antes."
    $d = @($r.diferencias)[0]
    if ($d) { $v.Motivo += " La primera, en $($d.fichero), linea $($d.linea): original [$($d.original)] y migrado [$($d.migrado)]." }
    return $v
  }
  $v.Nuevos[$i] = $r
  # 5. todos los demas casos que se pueden ejecutar: ninguno peor
  $otros = @(0..($tareasCasos.Count - 1) | Where-Object { $_ -ne $i -and (Test-Ejecutable $S.Res[$_]) })
  Invoke-Salidas $CopiaMig $false $nombre @($otros | ForEach-Object { $tareasCasos[$_] }) $false
  $peor = @()
  foreach ($k in $otros) {
    $n = Get-Resultado $tareasCasos[$k] $nombre
    $m = Get-Empeora $S.Res[$k] $n
    if ($m) { $peor += $m }
    $v.Nuevos[$k] = $n
  }
  if ($peor.Count -gt 0) { $v.Motivo = (@($peor | Select-Object -First 3) -join "`n"); return $v }
  # 6. la suite de tests unitarios: ni mas fallos ni menos tests que al empezar
  $t = Measure-Tests "reparar $($S.N), tests unitarios"
  if ($t.Motivo) { $v.Motivo = $t.Motivo; return $v }
  if ($t.Fallos -gt $S.Base.Fallos) {
    $v.Motivo = 'Tu cambio arregla el caso, pero rompe estos tests (esperan el comportamiento de ahora?): ' + (@($t.Nombres | Select-Object -First 5) -join ', ') + ". Fallan $($t.Fallos) y antes fallaban $($S.Base.Fallos)."
    return $v
  }
  if ($t.Ejecutados -lt $S.Base.Ejecutados) { $v.Motivo = "Con tu cambio se ejecutan menos tests unitarios: $($t.Ejecutados) y antes eran $($S.Base.Ejecutados)."; return $v }
  $v.Tipo = 'bien'
  return $v
}

# Lleva a $DirRama el arreglo que hay en la copia (el cambio de src/main/ desde su base, con git apply --index) y lo commitea; la base de
# la copia pasa a llevarlo. Devuelve '' o el motivo; si falla, deja la rama como estaba.
function Save-Arreglo([string]$Asunto, [int]$N) {
  $parche = Join-Path $Local "reparar-$N.patch"
  [void](Invoke-Git $CopiaMig @('add', '-A', '--', 'src/main'))
  [void](Invoke-Git $CopiaMig @('diff', '--cached', '--binary', "--output=$parche", $script:Base[$CopiaMig].Arbol))
  $r = Invoke-Git $DirRama @('apply', '--index', $parche)
  if ($r.Codigo -ne 0) { Restore-Base $CopiaMig; return "git apply no ha podido llevar el arreglo a ${DirRama}: " + (Get-Resumen ($r.Salida -join "`n")) }
  $r = Invoke-Git $DirRama (@('commit', '-q') + @($Cfg.CommitArgs) + @('-m', $Asunto))
  if ($r.Codigo -ne 0) {
    [void](Invoke-Git $DirRama @('apply', '-R', '--index', $parche))
    Restore-Base $CopiaMig
    return "git commit ha fallado en ${DirRama}: " + (Get-Resumen ($r.Salida -join "`n"))
  }
  $script:headMig = Get-Head $DirRama
  $script:Propios += $script:headMig
  Save-Copia $CopiaMig
  return ''
}

# Arregla la clave $C: llama a la IA (con reintento) hasta que un arreglo pasa las puertas, hasta que dice que no se arregla o hasta que
# se acaban los intentos. Devuelve la entrada de reparaciones de prueba-local.json.
function Repair-Clave($C, $S) {
  $r = $S.Res[(Get-IndiceCaso $S.Res $C.job $C.caso)]
  $t = Get-TareaReparar $C $r $S
  $o = [ordered]@{ clave = $C.clave; job = $C.job; caso = $C.caso; casos = $C.casos; resultado = 'no arreglado'; commit = ''; asunto = ''; intentos = 0; motivo = '' }
  if ($t.estado -eq 'atascada') {
    $o.intentos = $t.intentos
    if ($t.ultimoEstado -eq 'no se arregla') { $o.resultado = 'no se arregla'; $o.motivo = $t.motivo } else { $o.motivo = "ya probado en este commit: $($t.motivo)" }
    Aviso "$($C.job)/$($C.caso) $($C.clave): $($o.motivo)"
    return $o
  }
  $asunto = "rescate(local): $($C.job)/$($C.caso) $($C.clave)"
  $no = Join-Ruta $CopiaMig '.rescate/reparar-no.txt'
  Info ''
  Info "Arreglando $($C.job)/$($C.caso): la clave $($C.clave) la tienen $($C.casos) caso(s) distinto(s)..."
  while ($t.estado -eq 'pendiente') {
    $S.N++
    $n = $S.N
    Remove-Carpeta $no
    $tope = $Cfg.SegundosPorLlamada
    $Cfg.SegundosPorLlamada = $Cfg.SegundosReparar
    try { $ll = @(Invoke-Lote @($t) $Cfg.EsfuerzoReparar) }
    finally { $Cfg.SegundosPorLlamada = $tope }
    Restore-Base $CopiaMig
    $v = Test-Arreglo $t $ll[0] $S
    if ($v.Tipo -eq 'bien') {
      $m = Save-Arreglo $asunto $n
      if (-not $m) {
        foreach ($k in @($v.Nuevos.Keys)) { $S.Res[$k] = $v.Nuevos[$k] }
        $S.Salidas = "reparar/$n"
        Set-Intento $t ''
        $o.resultado = 'arreglado'; $o.commit = $script:headMig; $o.asunto = $asunto; $o.intentos = $t.intentos
        Bien "Arreglado $($C.job)/$($C.caso) $($C.clave) en el commit $($o.commit.Substring(0, 7))."
        return $o
      }
      $v.Tipo = 'rechazado'; $v.Motivo = $m
    }
    $diff = ''
    if ($v.ConDiff) { $diff = (@(Get-DiffCopia | Select-Object -First 40) -join "`n") }
    Remove-Carpeta (Join-Ruta $Local "salidas/reparar/$n")
    Remove-Carpeta $no
    Undo-Copia $CopiaMig
    if ($v.Tipo -eq 'no se arregla') {
      $t.estado = 'atascada'; $t.ultimoEstado = 'no se arregla'; $t.motivo = $v.Motivo; $t.intentos++
      Save-Tarea $t
      $o.resultado = 'no se arregla'; $o.intentos = $t.intentos; $o.motivo = $v.Motivo
      Aviso "No se arregla $($C.job)/$($C.caso) $($C.clave): $($v.Motivo)"
      return $o
    }
    $t.entradas.prompt.DIFF = ''
    if ($diff) { $t.entradas.prompt.DIFF = "Esto es lo que habias cambiado (las primeras 40 lineas del diff):`n`n$diff" }
    Set-Intento $t $v.Motivo
    Aviso "Arreglo de $($C.job)/$($C.caso) rechazado (intento $($t.intentos) de $($Cfg.Intentos)): $(($v.Motivo -split "`n")[0])"
  }
  $o.intentos = $t.intentos; $o.motivo = $t.motivo
  return $o
}

# Con -Reparar y casos distintos: arregla las claves, de la que tiene mas casos a la que menos, hasta MaxReparaciones, y deja en $Res (en su
# sitio) lo medido tras el ultimo arreglo bueno, cuyas salidas pasan a ser las del migrado. Devuelve las entradas de reparaciones.
function Invoke-Reparaciones($Res) {
  Info ''
  Info "Reparando en la rama de rescate ($(Get-Rama $DirRama)): hasta $($Cfg.MaxReparaciones) claves de diferencia, con $($Cfg.Intentos) intentos cada una..."
  Remove-Carpeta (Join-Ruta $Local 'salidas/reparar')
  Save-Copia $CopiaMig   # la copia ya lleva el arnes y los casos que dejo Invoke-Migrado: son su base
  $base = Measure-Tests 'tests unitarios de partida'
  if ($base.Motivo) { Aviso "No reparo nada: no he podido medir los tests unitarios de partida. $($base.Motivo)"; return @() }
  Info "Tests unitarios de partida: $($base.Ejecutados) ejecutados, $($base.Fallos) fallan."
  $s = [pscustomobject]@{ Res = $Res; Salidas = 'migrado'; N = 0; Base = $base; Probadas = @{} }
  $reps = @()
  while ($s.Probadas.Count -lt [int]$Cfg.MaxReparaciones) {
    $c = Find-Clave $s.Res $s.Probadas
    if (-not $c) { break }
    $s.Probadas[$c.clave] = $true
    $reps += , (Repair-Clave $c $s)
  }
  $quedan = @(@($s.Res | Where-Object { $_.resultado -eq 'distinto' } | ForEach-Object { Get-Claves $_ }) | Where-Object { -not $s.Probadas.ContainsKey($_) } | Select-Object -Unique)
  if ($quedan.Count -gt 0) { Aviso "Tope de MaxReparaciones ($($Cfg.MaxReparaciones)) claves por lanzamiento: quedan sin probar: $($quedan -join ', '). Vuelve a lanzar con -Reparar." }
  if ($s.Salidas -ne 'migrado') {
    Remove-Carpeta (Join-Ruta $Local 'salidas/migrado')
    Copy-Carpeta (Join-Ruta $Local "salidas/$($s.Salidas)") (Join-Ruta $Local 'salidas/migrado')
  }
  return $reps
}

# Una linea por reparacion.
function Show-Reparaciones($Reps) {
  Info ''
  Info 'Reparaciones:'
  foreach ($r in @($Reps)) {
    $donde = "$($r.job)/$($r.caso) $($r.clave) ($($r.casos) casos)"
    $motivo = ($r.motivo -split "`n")[0]
    if ($r.resultado -eq 'arreglado') { Bien "  arreglado: $donde en $($r.commit.Substring(0, 7)) ($($r.asunto))" }
    elseif ($r.resultado -eq 'no se arregla') { Aviso "  no se arregla: ${donde}: $motivo" }
    else { Fallo "  no arreglado: ${donde}: $motivo" }
  }
}

# ================================ RESULTADO ================================
# Los jobs donde ningun caso deja nada distinto del caso vacio del arnes (el aviso de Get-Resultado) y ninguno sale distinto ni no
# determinista: el test no le pasa las entradas al job y lo que sale igual no se ha probado. Los casos sin probar o sin preparar
# no cuentan. Si solo algunos casos del job salen como el vacio, el job no esta aqui: sigue como siempre, con el aviso en cada uno.
function Get-JobsVacios($Res) {
  $vacios = @()
  foreach ($j in @($Res | ForEach-Object { $_.job } | Select-Object -Unique)) {
    $comparados = @($Res | Where-Object { $_.job -ceq $j -and @('igual', 'distinto', 'no determinista') -contains $_.resultado })
    if ($comparados.Count -gt 0 -and @($comparados | Where-Object { $_.resultado -ne 'igual' -or $_.motivo -ne $MotivoVacio }).Count -eq 0) { $vacios += $j }
  }
  return $vacios
}

# Es un fallo, no un igual: invalida los dos arneses guardados (se vuelven a escribir en el siguiente lanzamiento, y la IA recibe
# este motivo por el mismo camino que el de un intento rechazado: la tarea queda pendiente, con su intento y su motivo), borra un
# prueba-local.json de antes (el informe no tiene que dar por buenos casos que no probaron nada) y sale con 1. migracion.ps1
# apunta como detalle las ultimas lineas de esta salida.
function Stop-Vacios([string[]]$Jobs) {
  $detalles = @($Jobs | ForEach-Object { "En $_, ningun caso deja nada distinto del caso vacio: el test no le pasa las entradas al job." })
  foreach ($t in @($ArnesOrig, $ArnesMig)) {
    Remove-Carpeta (Join-Ruta $Local "arnes/$($t.entradas.repo)")
    $t.estado = 'pendiente'; $t.intentos = 1; $t.ultimoEstado = 'invalida'; $t.motivo = ($detalles -join ' ')
    Save-Tarea $t
  }
  $json = Join-Path $DatosMig 'prueba-local.json'
  if (Test-Path -LiteralPath $json) { Remove-Item -LiteralPath $json -Force }
  Stop-Arranque ("No se da por igual lo que no se ha probado: los dos arneses guardados quedan invalidados y el proximo lanzamiento los vuelve a escribir, con este motivo.`n" + ($detalles -join "`n"))
}

function Get-PorJob($Res) {
  $porJob = @()
  foreach ($p in $pruebas) {
    $rs = @($Res | Where-Object { $_.job -ceq $p.job })
    $ig = @($rs | Where-Object { $_.resultado -eq 'igual' }).Count
    $di = @($rs | Where-Object { $_.resultado -eq 'distinto' }).Count
    $porJob += [ordered]@{ job = $p.job; casos = $rs.Count; iguales = $ig; distintos = $di; sinProbar = ($rs.Count - $ig - $di) }
  }
  return $porJob
}

# Escribe datos\prueba-local.json con $Res (y, con -Desde, los culpables; con -Reparar, las reparaciones) y devuelve lo escrito.
function Save-Resultado($Res, $Culpables, $Reparaciones = @()) {
  $o = [ordered]@{
    version = 1; original = $LegacyRoot; commitOriginal = $HeadOrig; migrado = $MigradoRoot; commitMigrado = $headMig
    modelo = $ModeloElegido; inicio = $Inicio.ToString('s'); fin = (Get-Date).ToString('s'); minutos = [Math]::Round($reloj.Elapsed.TotalMinutes, 1); llamadas = $script:Llamadas
    arneses = [ordered]@{ original = $ArnesOrig.estado; migrado = $ArnesMig.estado }; jobs = @(Get-PorJob $Res); casos = $Res; noPromete = $NoPromete
  }
  if ($Desde) { $o.culpables = @($Culpables | ForEach-Object { [ordered]@{ job = $_.job; caso = $_.caso; commit = $_.commit; asunto = $_.asunto; deshecho = $_.deshecho } }) }
  if ($Reparar) { $o.reparaciones = @($Reparaciones) }
  Write-Json (Join-Path $DatosMig 'prueba-local.json') $o
  return $o
}

# ================================= MAIN =================================
$reloj = [System.Diagnostics.Stopwatch]::StartNew()
$Inicio = Get-Date
if (-not $Legacy) { Stop-Arranque 'Falta -Legacy: la carpeta del batch original.' }
if ($Reparar -and ($Desde -or $Deshacer)) { Stop-Arranque '-Reparar no se combina con -Desde ni con -Deshacer: o buscas el commit que rompe un caso, o arreglas lo que venia mal de la migracion.' }
if ($Deshacer -and -not $Desde) { Stop-Arranque '-Deshacer solo vale con -Desde <commit>: dime desde que commit tengo que buscar lo que rompe.' }
$ajustes = Read-CfgFile (Get-RutaAjustes) @('Plantilla') $false
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Stop-Arranque "No encuentro git en el PATH." }
foreach ($x in @(@('-Legacy', $Legacy), @('-Migrado', $Migrado))) {
  if (-not (Test-Path -LiteralPath $x[1]) -or -not (Test-Path -LiteralPath (Join-Path $x[1] '.git'))) { Stop-Arranque "$($x[0]) no es la raiz de un repo git: $($x[1])" }
}
$LegacyRoot = Resolve-Dir $Legacy
$MigradoRoot = Resolve-Dir $Migrado
Read-Config $MigradoRoot $false    # config.json es de rescate.ps1: lleva claves que prueba-local.ps1 no conoce
$PlantillaRoot = ''
if ($ajustes -and $ajustes.Plantilla -and (Test-Path -LiteralPath ([string]$ajustes.Plantilla))) { $PlantillaRoot = Resolve-Dir ([string]$ajustes.Plantilla) }
$l = Get-Lanzable $Cfg.CopilotExe
if (-not $l.Ruta) { Stop-Arranque $l.Mensaje }
$mvn = Get-Mvn $MigradoRoot
if (-not (Test-Path -LiteralPath $mvn) -and -not (Get-Command $mvn -ErrorAction SilentlyContinue)) { Stop-Arranque "No encuentro Maven ('$mvn'). Instalalo o pon MvnExe en los ajustes." }
if ($JavaLegacy -and -not (Test-Path -LiteralPath $JavaLegacy)) { Stop-Arranque "-JavaLegacy no existe: $JavaLegacy" }

# Los casos de migracion.ps1
$salidaMig = @(Get-ChildItem -LiteralPath $MigradoRoot -Directory -Filter 'migracion-*' | Where-Object { Test-Path -LiteralPath (Join-Ruta $_.FullName 'datos/pruebas') } | Sort-Object LastWriteTimeUtc -Descending)
$pruebas = @()
if ($salidaMig.Count -gt 0) { $pruebas = @(Get-ChildItem -LiteralPath (Join-Ruta $salidaMig[0].FullName 'datos/pruebas') -File -Filter '*.json' | Sort-Object Name | ForEach-Object { Read-Json $_.FullName } | Where-Object { $_.job }) }
if ($pruebas.Count -eq 0) { Stop-Arranque "No hay casos que probar: falta $MigradoRoot\migracion-<batch>\datos\pruebas\. Lanza antes migracion.ps1 (la fase de pruebas en pre escribe los casos de cada job)." }
$Salida = $salidaMig[0].FullName
$DatosMig = Join-Path $Salida 'datos'
$Local = Join-Path $Salida 'prueba-local'
$Datos = $Local   # Save-Tarea y Restore-Tarea (tareas.ps1) guardan las tareas en $Datos\tareas
$Registros = Join-Path $Local 'registros'
[void](New-Item -ItemType Directory -Path $Registros -Force)
$todosJobs = @($pruebas | ForEach-Object { [string]$_.job })
if ($Job) {
  $pruebas = @($pruebas | Where-Object { $_.job -ceq $Job })
  if ($pruebas.Count -eq 0) { Stop-Arranque ("-Job ${Job}: no hay casos de ese job. Hay de: " + ($todosJobs -join ', ')) }
}
if (@($pruebas | ForEach-Object { @($_.casos) } | Where-Object { $_ }).Count -eq 0) { Stop-Arranque 'Los guiones de migracion.ps1 no traen ningun caso que probar.' }
$mapa = $null
if (Test-Path -LiteralPath (Join-Path $DatosMig 'mapa.json')) { $mapa = Read-Json (Join-Path $DatosMig 'mapa.json') }

# Modelo: -Modelo o el de migracion.ps1
$ModeloElegido = $Modelo
if (-not $PSBoundParameters.ContainsKey('Modelo') -and (Test-Path -LiteralPath (Join-Path $DatosMig 'estado.json'))) { $ModeloElegido = [string](Read-Json (Join-Path $DatosMig 'estado.json')).modelo }
if ($ModeloElegido) { Info "Modelo: $ModeloElegido" } else { Info 'Modelo: el que tenga Copilot' }

# Huellas de lo que no se puede tocar: el original, el migrado, su worktree de rescate y la referencia. La unica excepcion: con
# -Deshacer o -Reparar, la carpeta de la rama que se prueba puede acabar con sus commits nuevos encima (Test-MismaHuella).
$Worktree = ''
$OrigenRoot = $MigradoRoot
Set-Excluidos $MigradoRoot   # migracion-*/ fuera de git, como hace migracion.ps1
$dirRescate = Get-DirRescate
$hayRescate = Test-WorktreeRescate $dirRescate
$DirRama = $MigradoRoot   # la carpeta de la rama que se prueba (la de rescate, si hay): donde se busca con -Desde y se deshace con -Deshacer
if ($hayRescate) { $DirRama = $dirRescate }
if ($Reparar -and -not $hayRescate) { Stop-Arranque "-Reparar necesita el worktree de rescate: lanza migracion.ps1 primero: crea $dirRescate." }
if ($Reparar -and (Test-RamaSucia)) { Stop-Arranque "$DirRama tiene cambios sin commit (git status): guardalos o descartalos y vuelve a lanzar con -Reparar." }
$intocables = @($LegacyRoot, $MigradoRoot)
if ($hayRescate) { $intocables += $dirRescate }
if ($PlantillaRoot) { $intocables += $PlantillaRoot }
$H0 = @($intocables | ForEach-Object { Get-Huella $_ })

$script:Llamadas = 0
$script:Racha = 0
$script:Mavens = 0
$script:Maven = @{}
$script:Estados = @{}   # -Desde: lo visto por (commit|job|caso), para no repetir ejecuciones
$script:Propios = @()   # los commits que ha hecho en $DirRama: los reverts de -Deshacer y los arreglos de -Reparar
try {
  if (-not (Set-Despierto $true)) { Aviso 'No he podido pedir a Windows que no suspenda el equipo: si lo dejas solo, compruebalo.' }
  # 1. Copias desechables y que compilen
  $CopiaOrig = $LegacyRoot + '-prueba-local'
  $CopiaMig = $MigradoRoot + '-prueba-local'
  $HeadOrig = Get-Head $LegacyRoot
  $headMig = Get-Head $MigradoRoot
  if ($hayRescate) { $headMig = Get-Head $dirRescate; Info "El migrado se prueba en el ultimo commit de su rama de rescate ($(Get-Rama $dirRescate))." }
  $DesdeCommit = ''
  if ($Desde) {
    $DesdeCommit = ((Invoke-Git $DirRama @('rev-parse', '--verify', '-q', ($Desde + '^{commit}'))).Salida -join '').Trim()
    if (-not $DesdeCommit) { Stop-Arranque "-Desde ${Desde}: no es un commit de $DirRama." }
    if ((Invoke-Git $DirRama @('merge-base', '--is-ancestor', $DesdeCommit, $headMig)).Codigo -ne 0) { Stop-Arranque "-Desde ${Desde}: no esta en la historia de la rama que se prueba ($(Get-Rama $DirRama), que acaba en $($headMig.Substring(0, 7)))." }
  }
  foreach ($x in @(@($LegacyRoot, $HeadOrig, $CopiaOrig), @($MigradoRoot, $headMig, $CopiaMig))) {
    $m = New-Copia $x[0] $x[1] $x[2]
    if ($m) { Stop-Arranque $m }
  }
  Info "Copias: $CopiaOrig y $CopiaMig"
  $PomOriginal = ''   # el pom.xml del original tal cual (leido como fichero, no por git): Test-PomSoloTest
  if (Test-Path -LiteralPath (Join-Path $CopiaOrig 'pom.xml')) { $PomOriginal = [System.IO.File]::ReadAllText((Join-Path $CopiaOrig 'pom.xml')) }
  foreach ($c in @($CopiaOrig, $CopiaMig)) {
    foreach ($v in @($c, ($c -replace '\\', '/'), ($c -replace '/', '\'))) { $RutasCopia += $v; $RutasCopia += $Latin.GetString($Utf8.GetBytes($v)) }
  }
  $RutasCopia = @($RutasCopia | Select-Object -Unique | Sort-Object Length -Descending)
  $r = Invoke-Maven $CopiaOrig $true @('test-compile') 'compilar el original'
  if ($r.Codigo -ne 0) {
    if ($JavaLegacy) { Stop-Arranque ("El original no compila ni con -JavaLegacy ${JavaLegacy}:`n" + (Get-FalloMaven $r)) }
    Stop-Arranque ("El original no compila con el JDK de Maven. Vuelve a lanzar con -JavaLegacy <carpeta del JDK del original (8 u 11)>. Maven dice:`n" + (Get-FalloMaven $r))
  }
  $r = Invoke-Maven $CopiaMig $false @('test-compile') 'compilar el migrado'
  if ($r.Codigo -ne 0) { Stop-Arranque ("El migrado no compila. Maven dice:`n" + (Get-FalloMaven $r)) }

  # 2. Tareas: los arneses y los casos (las hechas de antes, a sus copias)
  $arneses = @()
  $testOriginal = ''   # donde va el test del original: el del migrado lo traduce
  foreach ($x in @(@('original', $CopiaOrig), @('migrado', $CopiaMig))) {
    $test = Get-RutaTest $x[1]
    if (-not $test) { Stop-Arranque "No encuentro en el $($x[0]) la clase con @SpringBootApplication (en src/main/java): el test PruebaLocalTest va en su paquete." }
    $t = Get-TareaArnes $x[0] $x[1] $test $todosJobs $testOriginal
    # Con -RehacerArnes el del migrado vuelve a empezar sin pasar por Use-ArnesGuardado; lo guardado se borra tras la pregunta
    if ($RehacerArnes -and $x[0] -eq 'migrado') { $t.estado = 'pendiente'; $t.intentos = 0; $t.motivo = ''; $t.ultimoEstado = '' }
    elseif (Test-Path -LiteralPath (Join-Ruta $Local "arnes/$($x[0])")) { Use-ArnesGuardado $t $todosJobs }
    $arneses += , $t
    if ($x[0] -eq 'original') { $testOriginal = $test }
  }
  $ArnesOrig = $arneses[0]
  $ArnesMig = $arneses[1]
  $tareasCasos = @()
  foreach ($p in $pruebas) {
    $jm = $null
    if ($mapa) { $jm = @($mapa.jobs | Where-Object { $_.job -ceq $p.job })[0] }
    if (-not $jm) { $jm = [pscustomobject]@{ job = $p.job; clases = @() } }
    $tareasCasos += @(Get-TareasCasos $p $jm)
  }
  $pendientes = @(@($arneses) + @($tareasCasos) | Where-Object { $_.estado -ne 'hecha' }).Count
  Info "Casos: $($tareasCasos.Count) de $($pruebas.Count) jobs; tareas de IA por hacer: $pendientes (las hechas en otro lanzamiento no se repiten)."
  if ($pendientes -gt 0 -and -not (Confirmar "Llamar a Copilot para esas $pendientes tareas?")) { Stop-Arranque 'No se ha hecho nada.' }
  if ($RehacerArnes) { Remove-Carpeta (Join-Ruta $Local 'arnes/migrado') }

  # 3. Arneses (sin el del original no se sigue) y entradas de los casos (las hechas de antes, a la copia del original)
  Invoke-Arneses @($arneses | Where-Object { $_.estado -ne 'hecha' }) $todosJobs
  if ($ArnesOrig.estado -ne 'hecha') { Show-Atascado $ArnesOrig; exit 1 }
  if ($ArnesMig.estado -ne 'hecha') { Show-Atascado $ArnesMig; Aviso 'Sigo con el original: los casos quedan hechos para el proximo lanzamiento.' }
  foreach ($t in @($tareasCasos | Where-Object { $_.estado -eq 'hecha' })) {
    $guardado = Join-Ruta $Local "casos/$($t.entradas.job)/$($t.entradas.caso)"
    if (-not (Test-Path -LiteralPath (Join-Path $guardado 'no-aplica.txt'))) { Copy-Carpeta $guardado (Join-Ruta $CopiaOrig $t.entradas.carpeta) }
  }
  Save-Copia $CopiaOrig
  Invoke-Casos @($tareasCasos | Where-Object { $_.estado -ne 'hecha' })

  # 4. Ejecutar: el original dos veces y el migrado una, con los mismos casos
  $listas = @($tareasCasos | Where-Object { $_.estado -eq 'hecha' -and -not (Test-Path -LiteralPath (Join-Ruta $Local "casos/$($_.entradas.job)/$($_.entradas.caso)/no-aplica.txt")) })
  Invoke-Salidas $CopiaOrig $true 'original' $listas
  Invoke-Salidas $CopiaOrig $true 'original-2' $listas
  if ($ArnesMig.estado -eq 'hecha') { Invoke-Migrado 'migrado' $listas }

  # 5. Comparar y contar
  $res = @($tareasCasos | ForEach-Object { Get-Resultado $_ })
  $vacios = @(Get-JobsVacios $res)
  if ($vacios.Count -gt 0) { Stop-Vacios $vacios }
  $o = Save-Resultado $res @()
  Show-Resultado $res $o.jobs

  # 6. Con -Desde: el commit que rompe cada caso distinto y, con -Deshacer, su git revert; el resultado y la salida son los de despues
  if ($Desde) {
    $culpables = @(Find-Culpables $res)
    if ($Deshacer) { Undo-Culpables $culpables $res }
    $o = Save-Resultado $res $culpables
    if ($Deshacer -and @($script:Propios).Count -gt 0) { Info ''; Info 'Despues de deshacer:'; Show-Resultado $res $o.jobs }
  }
  # 7. Con -Reparar: arregla la rama de rescate hasta que los casos distintos salgan iguales; el resultado y la salida son los de despues
  if ($Reparar) {
    $reparaciones = @()
    if (@($res | Where-Object { $_.resultado -eq 'distinto' }).Count -eq 0) { Info ''; Info 'Con -Reparar: no hay casos distintos que arreglar.' }
    elseif (Confirmar "Llamar a Copilot para arreglar hasta $($Cfg.MaxReparaciones) causas de los casos distintos (cada una, hasta $($Cfg.Intentos) llamadas)?") { $reparaciones = @(Invoke-Reparaciones $res) }
    else { Info ''; Info 'No se repara nada.' }
    $o = Save-Resultado $res @() $reparaciones
    if ($reparaciones.Count -gt 0) {
      if (@($reparaciones | Where-Object { $_.resultado -eq 'arreglado' }).Count -gt 0) { Info ''; Info 'Despues de reparar:'; Show-Resultado $res $o.jobs }
      Show-Reparaciones $reparaciones
      if (@($reparaciones | Where-Object { $_.resultado -eq 'no se arregla' }).Count -gt 0) { Info 'Si la IA dice que la diferencia es del test del migrado y no del codigo, relanza con -RehacerArnes.' }
    }
  }
  Info ''
  Info "Llamadas a Copilot: $($script:Llamadas). Tiempo: $($o.minutos) min. Resultado en $(Join-Path $DatosMig 'prueba-local.json')"
  Info $NoPromete

  # Lo que no se podia tocar sigue igual
  $H1 = @($intocables | ForEach-Object { Get-Huella $_ })
  if (@(0..($intocables.Count - 1) | Where-Object { -not (Test-MismaHuella $intocables[$_] $H0[$_] $H1[$_]) }).Count -gt 0) { Stop-Arranque ('Ha cambiado durante la prueba alguna de estas carpetas: ' + ($intocables -join ', ') + '. Miralo con git status y git diff.') }
  if (@($res | Where-Object { $_.resultado -eq 'distinto' }).Count -gt 0) { exit 2 }
  if ($ArnesMig.estado -ne 'hecha' -or @($res | Where-Object { $_.resultado -eq 'igual' }).Count -eq 0) { exit 1 }
  exit 0
}
finally {
  [void](Set-Despierto $false)
}
