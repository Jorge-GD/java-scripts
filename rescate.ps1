<#
rescate.ps1 - Primeros auxilios para repos Java batch migrados a medias
(Java 8 -> Java 21 + arquitectura hexagonal + SFTP + configuracion externa).
Compatible con Windows PowerShell 5.1 y PowerShell 7. Solo ASCII a proposito.

COMO FUNCIONA
  1. DIAGNOSTICO (sin IA, no toca codigo). Compara el repo con una PLANTILLA
     (un repo ya migrado y aprobado) y lista hallazgos por paso, en este orden:
       build -> estructura -> hexagonal -> ficheros -> config -> paridad -> e2e -> tests -> calidad
     La plantilla manda: lo que la plantilla hace se considera permitido.
     paridad = estan todos los jobs del batch original (necesita -Modo pre).
     e2e     = cada job tiene un test que lo lanza entero y acaba en COMPLETED.
     calidad = Javadoc en los tipos y metodos publicos y buenas practicas de
               Java 21 (sin @Autowired en campos, sin System.out, sin catch
               vacios...). El Javadoc se exige aunque la plantilla no lo tenga.
  2. WORKTREE. El arreglo no se hace en tu carpeta. El script crea al lado un
     worktree de git (<repo>-rescate) con una rama rescate/... y trabaja ahi.
     Tu carpeta y tu rama no se tocan. Si tienes cambios sin commit, se copian
     al worktree en un commit 'foto'. Mientras ese worktree exista, todos los
     modos trabajan en el (para mirar tu carpeta original: -SinWorktree).
  3. PLAN (con Copilot CLI, solo lectura). Antes de arreglar un paso, la IA lee
     TODOS los ficheros con hallazgos y la plantilla, y escribe
     .rescate/plan-<paso>.md: que se hara con cada fichero y que piezas comunes
     (puertos, adaptadores) van a compartir. Lo lees y lo corriges antes de seguir.
  4. FIX (con Copilot CLI). Arregla UN paso en lotes pequenos, siguiendo el plan.
     Tras cada lote se repite el diagnostico entero y es el script (no la IA)
     quien decide si vale:
       - compila
       - bajan los hallazgos del paso
       - no empeoran los pasos anteriores
       - el codigo nuevo no anade hallazgos de calidad (Javadoc incluido)
       - no baja el numero de catch de src/main/java (llevar uno a otro
         fichero vale; quitarlo cambia como se tratan los errores)
       - no se han borrado ni desactivado tests
       - no se ha tocado la plantilla ni el repo original
     Si vale -> commit. Si no -> reintento con el error y, si sigue mal, se
     deshace el lote entero. Nunca hace push.

USO
  # 0) Pre, una vez por repo: lista de jobs del original -> .rescate/contrato.json
  #    (lo unico que hay que revisar a mano: que esa lista de jobs es la buena)
  .\rescate.ps1 -Modo pre -Repo C:\ruta\batch-life -Legacy C:\ruta\life-java8

  # 1) Diagnostico (seguro, no cambia codigo)
  .\rescate.ps1 -Repo C:\ruta\batch-life -Plantilla C:\ruta\batch-terminado

  # 2) Plan del siguiente paso pendiente (no cambia codigo). Crea el worktree
  #    C:\ruta\batch-life-rescate y escribe alli .rescate\plan-<paso>.md
  .\rescate.ps1 -Modo plan -Repo C:\ruta\batch-life -Plantilla C:\ruta\batch-terminado `
                -Legacy C:\ruta\life-java8 -Modelo <id-del-modelo>

  # 3) Arreglar el siguiente paso pendiente, lote a lote, con pausa para revisar.
  #    Si el paso aun no tiene plan, lo hace primero y te deja leerlo.
  .\rescate.ps1 -Modo fix -Repo C:\ruta\batch-life -Plantilla C:\ruta\batch-terminado `
                -Legacy C:\ruta\life-java8 -Modelo <id-del-modelo>

  # Comprobar (sin Maven, sin escribir nada): lo que el arbol de trabajo ha roto frente al commit de partida del lote en curso.
  # Los prompts de los lotes se la piden a la IA antes de terminar; sale con 1 si hay algo nuevo roto.
  .\rescate.ps1 -Modo comprobar -Repo C:\ruta\batch-life -Plantilla C:\ruta\batch-terminado

  # Todo seguido, sin parar: se detiene solo si un lote no pasa las comprobaciones.
  # Sin .rescate\contrato.json (y con -Legacy) hace antes lo del modo pre.
  .\rescate.ps1 -Modo fix ... -Todo

  # Con el informe de Sonar (.xlsx): paso 'sonar' el ultimo, para cualquier repo Maven de Java (sin -Plantilla ni -Legacy).
  # Solo con -Repo y -Sonar: -Modo fix, -Paso sonar y -Auto. Deja .rescate\sonar-faltan.md con lo que no ha podido arreglar.
  .\rescate.ps1 -Repo C:\ruta\batch -Sonar C:\ruta\informe.xlsx

  # Con -Cobertura: paso 'cobertura' el ultimo. Escribe solo tests (nada fuera de src/test), una clase por lote, hasta CoberturaMinima (80 %).
  # Solo con -Repo y -Cobertura: -Modo fix, -Paso cobertura y -Auto. Deja .rescate\cobertura-faltan.md con lo que falta y los // OJO.
  .\rescate.ps1 -Repo C:\ruta\batch -Cobertura

  # Con modelo de reserva: si el principal se atasca con un fichero, prueba el otro
  .\rescate.ps1 -Modo fix ... -Todo -Modelo <principal> -ModeloB <reserva>

  # Modelo y esfuerzo. Cada llamada es 'copilot -p' con --model y --effort.
  # -Modelo es el id que ensena /model dentro de Copilot. El esfuerzo va en dos
  # mandos: la revision previa (pensar) y los lotes (escribir). Niveles: low,
  # medium, high, xhigh, max; no todos los modelos admiten todos. Sin estos
  # parametros se usa lo que tengas configurado en Copilot.
  .\rescate.ps1 -Modo fix ... -Modelo <id-del-modelo> -EsfuerzoPlan high -Esfuerzo medium

  # Si un lote falla: se deshace, se reintenta fichero a fichero, luego con el
  # modelo de reserva y, si tampoco, se pide consejo al modelo de las dudas: si la
  # duda es de codigo, un intento mas con el consejo; si no pasa, o la tiene que
  # decidir una persona, se apunta en .rescate/atascados.md (y .json) y sigue.
  # La pasada siguiente no vuelve a intentar un atascado si su fichero no ha
  # cambiado y no hay commits tuyos desde entonces (-Reintentar lo fuerza).
  # Con "Reflexionar" (por defecto "repetido"; "siempre" o "nunca" en
  # .rescate/config.json; true y false valen como siempre y nunca), el modelo de las
  # dudas reflexiona (por que no paso, que hacer) tras un intento que falla con los mismos
  # NO PASA que el anterior del lote, y el siguiente intento lo lleva. Con -Auto, las dudas del plan
  # tambien las resuelve el (las de codigo van al plan, en ## Decisiones).
  # Todo queda en .rescate/decisiones.md; lo que le toca a una persona sale al
  # final en "Te toca decidir".
  .\rescate.ps1 -Modo fix ... -Todo -ModeloDudas <id-fuerte> -EsfuerzoDudas max

  # Elegir paso, lotes mas pequenos, saltar ficheros que se atascan
  .\rescate.ps1 -Modo fix ... -Paso hexagonal -Lote 3 -Saltar 2

  # Deshacer el ultimo lote
  .\rescate.ps1 -Modo deshacer -Repo C:\ruta\batch-life

  # 4) Al acabar. Los cambios estan en la rama rescate/... (el script te dice
  #    el nombre). Revisalos y juntalos con tu rama con -Cierre de migracion.ps1
  #    (fast-forward, despues de las puertas; sin migracion.ps1 no hay -Cierre),
  #    o sube la rama y abre un PR:
  git -C C:\ruta\batch-life diff --stat <tu-rama>...<rama-rescate>
  .\migracion.ps1 -Legacy C:\ruta\original -Migrado C:\ruta\batch-life -Plantilla C:\ruta\referencia -Cierre
  git -C C:\ruta\batch-life worktree remove C:\ruta\batch-life-rescate

  Si PowerShell bloquea el script:
  powershell -ExecutionPolicy Bypass -File .\rescate.ps1 -Repo ...

SI HAY QUE REPARAR ESTE SCRIPT
  Lo normal es tocar solo el bloque CONFIGURACION (reglas, comandos de Maven) o
  el de comun.ps1 (flags de Copilot, ruta de Maven). rescate.ps1 necesita
  comun.ps1 en su misma carpeta. No quites las puertas de Invoke-Fix: son lo que evita que
  la IA estropee el repo. Antes de darlo por bueno, pasa tests\probar.ps1.

LIMITES
  Proyectos Maven de un solo modulo. Las comprobaciones son por imports y
  texto: avisan de lo evidente, no sustituyen la revision de una persona ni
  a Sonar. En calidad solo se miran los tipos de primer nivel y sus metodos.
  El worktree no trae los ficheros que git ignora (config local, .env): el
  script los lista al crearlo, por si el build o los tests los necesitan.
#>
[CmdletBinding()]
param(
  [ValidateSet('diagnostico', 'pre', 'plan', 'fix', 'deshacer', 'comprobar')][string]$Modo = 'diagnostico',
  [string]$Repo = '.',
  [string]$Plantilla = '',
  [string]$Legacy = '',
  [string]$Sonar = '',       # informe de Sonar (.xlsx, hoja Issues Breakdown): anade el paso 'sonar' al final y arregla sus incidencias; sin -Modo hace el fix entero
  [switch]$Cobertura,        # anade el paso 'cobertura' al final: escribe tests, clase a clase, hasta llegar a CoberturaMinima; sin -Modo hace el fix entero
  [ValidateSet('', 'build', 'estructura', 'hexagonal', 'ficheros', 'config', 'paridad', 'e2e', 'tests', 'calidad', 'sonar', 'cobertura')][string]$Paso = '',
  [string]$Modelo = '',
  [string]$ModeloB = '',     # modelo de reserva cuando el principal se atasca con un fichero (vacio = ModeloB de la config)
  # Esfuerzo de razonamiento de Copilot (--effort). Vacio = el que tenga Copilot.
  [ValidateSet('', 'low', 'medium', 'high', 'xhigh', 'max')][string]$Esfuerzo = '',      # en los lotes de arreglo
  [ValidateSet('', 'low', 'medium', 'high', 'xhigh', 'max')][string]$EsfuerzoPlan = '',  # en la revision previa y en el modo pre (vacio = el de -Esfuerzo)
  [string]$ModeloDudas = '', # modelo del consejo y la reflexion (vacio = ModeloDudas de la config o, si no, -Modelo)
  [ValidateSet('', 'low', 'medium', 'high', 'xhigh', 'max')][string]$EsfuerzoDudas = '', # su esfuerzo (vacio = EsfuerzoDudas de la config: max)
  [switch]$Reintentar,      # fix: vuelve a intentar los atascados de pasadas anteriores aunque su fichero no haya cambiado
  [string]$Worktree = '',    # carpeta del worktree de rescate (por defecto <repo>-rescate, al lado del repo)
  [int]$Lote = 5,           # ficheros por llamada a Copilot (pequeno = mas fiable)
  [int]$Saltar = 0,         # salta los N primeros ficheros pendientes del paso
  [int]$MaxIntentos = 3,    # intentos por lote antes de deshacerlo
  [int]$MaxLotes = 200,
  [switch]$SinBuild,        # diagnostico rapido: no ejecuta Maven
  [switch]$SinTests,        # no ejecuta tests (solo compila)
  [switch]$SinWorktree,     # trabaja en la carpeta de -Repo, sin worktree (fix crea ahi la rama rescate/)
  [switch]$SinPlan,         # fix: no hace ni usa la revision previa (plan) del paso
  [switch]$Auto,            # no para entre lotes
  [switch]$Todo,            # fix: encadena todos los pasos sin parar (implica -Auto)
  [switch]$Si,              # responde "si" a las confirmaciones
  [switch]$SinInstrucciones,# Copilot no carga AGENTS.md / instrucciones del repo
  [switch]$SinIA            # modo pre: solo busqueda por texto, sin Copilot
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'comun.ps1')
# Las reglas del paso sonar (prompt, recetas, mensajes que no se automatizan y puertas del diff) estan en sonar-reglas.ps1, junto a este script.
# Sin ese fichero rescate.ps1 sigue funcionando; solo -Sonar lo necesita.
$ReglasSonar = Join-Path $PSScriptRoot 'sonar-reglas.ps1'
$HayReglasSonar = Test-Path -LiteralPath $ReglasSonar
if ($HayReglasSonar) { . $ReglasSonar }
else { $SonarPromptReal = ''; $SonarRecetasReal = @(); $SonarNoAutomatizarReal = @(); $SonarProhibidoReal = @() }

# ============================ CONFIGURACION ============================
# Los flags de Copilot, la ruta de Maven y las carpetas ignoradas estan en comun.ps1.
$Cfg += @{
  Orden  = @('build', 'estructura', 'hexagonal', 'ficheros', 'config', 'paridad', 'e2e', 'tests', 'calidad', 'sonar', 'cobertura')   # sonar solo existe con -Sonar; cobertura, con -Cobertura
  Capas  = @('domain', 'application', 'infrastructure')   # si no hay plantilla
  # Reglas de dependencias. En = carpeta (relativa al paquete base).
  # No = regex sobre el import; {base} es el paquete base del proyecto.
  Reglas = @(
    @{ En = 'domain/'; No = '^\{base\}\.(application|infrastructure)\.'
       Por = 'el dominio no depende de application ni de infrastructure' },
    @{ En = 'domain/'; No = '^(org\.springframework|jakarta\.persistence|javax\.persistence|java\.sql|javax\.sql|java\.net\.http|org\.apache\.sshd|com\.jcraft|org\.apache\.http|okhttp3|com\.fasterxml)\.'
       Por = 'el dominio no depende de frameworks ni de entrada/salida' },
    @{ En = 'application/'; No = '^\{base\}\.infrastructure\.'
       Por = 'application no depende de infrastructure' },
    @{ En = 'application/'; No = '^(org\.springframework\.(batch|integration|jdbc|web|http)|java\.sql|javax\.sql|java\.net\.http|org\.apache\.sshd|com\.jcraft|org\.apache\.http|okhttp3)\.'
       Por = 'application no usa tecnologia concreta: va detras de un puerto' },
    @{ En = 'infrastructure/adapters/input/'; No = '^\{base\}\.infrastructure\.adapters\.output\.'
       Por = 'un adaptador de entrada no importa uno de salida: usa la interfaz de su puerto (application/ports/output) o un caso de uso, como en la PLANTILLA' }
  )
  SubpaquetesEstrictos  = $true   # domain/x, application/x... deben existir en la plantilla
  # Acceso a ficheros locales (lo que debe ir por el puerto de ficheros / SFTP). Path y Paths no abren nada: son un dato y no se marcan.
  FicheroImport         = '^(java\.io\.(File|FileReader|FileWriter|FileInputStream|FileOutputStream|RandomAccessFile)|java\.nio\.file\.(?!Paths?$).+|org\.springframework\.core\.io\.(FileSystemResource|PathResource|FileUrlResource))$'
  FicheroToken          = '\b(File|FileReader|FileWriter|FileInputStream|FileOutputStream|RandomAccessFile)\b'
  FicheroPermitidoEn    = @('infrastructure/adapters/output/file', 'infrastructure/adapters/output/sftp')
  # Un batch que maneja ficheros tiene que traer el adaptador SFTP y su configuracion, tenga lo que tenga la plantilla.
  # En false solo se exige lo que la plantilla tiene.
  ExigirSftp            = $true
  # Palabras que delatan la configuracion antigua. AJUSTALAS a tu repo.
  PalabrasConfigAntigua = @('inventory')
  # API antigua: se marca solo si la plantilla ya no la usa
  ApiAntigua            = @('JobBuilderFactory', 'StepBuilderFactory')
  # Las palabras que hacen secreta una clave: la lista unica esta en comun.ps1 ($PalabrasSecreto)
  PalabrasSecreto       = $PalabrasSecreto
  JavaxAntiguo          = '^javax\.(annotation|persistence|validation|servlet|inject|batch|transaction|ws\.rs|jms|mail|xml\.bind)\.'
  ExtTexto              = @('.java', '.yml', '.yaml', '.properties', '.xml', '.sh', '.bat', '.cmd', '.json', '.conf', '.cfg', '.ini')
  # Como se reconoce un job en el ORIGINAL (grupo 1 = nombre del job)
  JobRegex              = @(
    '(?i)jobBuilder\w*\s*\.\s*get\(\s*"([^"]+)"',
    'new\s+JobBuilder\(\s*"([^"]+)"',
    '<(?:\w+:)?job(?=[\s>])[^>]*\bid="([^"]+)"'
  )
  # Como se reconoce un test que lanza un job de verdad
  LanzaJob              = 'launchJob\s*\(|JobLauncherTestUtils|[jJ]obLauncher\s*\.\s*run\s*\(|[jJ]obOperator\s*\.\s*start\s*\(|SpringApplication\s*\.\s*run\s*\('
  PasosDeUnoEnUno       = @('paridad', 'e2e', 'cobertura')   # un job (o una clase) por llamada a Copilot
  PasosSoloCompila      = @('sonar')   # pasos en los que el modelo solo compila (MvnCompilar) y los tests los pasa el script en sus puertas
  PasosTestsElegidos    = @('sonar')   # pasos en los que cada lote pasa solo los tests ligeros (sin los de contexto de Spring) y la suite entera va en un control
  LotesEntreControles   = 10           # cada cuantos lotes buenos se pasa la suite entera (el control); tambien al final del paso y al empezar si la pasada anterior se corto
  ControlRondas         = 3            # veces que un control rojo busca el lote culpable y lo revierte antes de revertir todos los lotes desde la ultima marca
  # Pasos en los que la IA revisa antes todos los ficheros y escribe un plan
  PasosConPlan          = @('estructura', 'hexagonal', 'ficheros', 'config')
  # Calidad. Reglas que cuentan como error (el fix las arregla y las exige en
  # el codigo nuevo). El resto de reglas se queda en aviso. Para apagar una,
  # quitala de aqui. Reglas: javadoc-tipo, javadoc-metodo, inyeccion-campo,
  # salida-consola, catch-vacio, envoltorio-new, instanceof-cast,
  # fecha-antigua, coleccion-antigua. Las de Spring salen de Sonar way:
  # constructores-sin-autowired (S6829), autowired-varios (S6818),
  # inyeccion-estatica (S7178), value-sin-expresion (S6804). Las de estilo
  # miran todo el batch: estilo-constructor y estilo-logger. Las de proxy
  # (clase-final-proxy y metodo-final-proxy) no son de Sonar: Spring no puede
  # envolver una clase o un metodo final y el job no arranca.
  CalidadErrores        = @('javadoc-tipo', 'javadoc-metodo', 'inyeccion-campo', 'salida-consola', 'catch-vacio', 'envoltorio-new',
    'constructores-sin-autowired', 'autowired-varios', 'inyeccion-estatica', 'value-sin-expresion', 'estilo-constructor', 'estilo-logger',
    'clase-final-proxy', 'metodo-final-proxy')
  # Reglas que se exigen aunque la plantilla tampoco las cumpla (el resto, si la plantilla tambien las incumple, se queda en aviso)
  CalidadSiempre        = @('javadoc-tipo', 'javadoc-metodo', 'constructores-sin-autowired', 'autowired-varios', 'inyeccion-estatica', 'value-sin-expresion',
    'clase-final-proxy', 'metodo-final-proxy', 'estilo-constructor', 'estilo-logger')
  # Metodos publicos de una clase que no necesitan Javadoc (en una interfaz, todos lo llevan)
  MetodosSinJavadoc     = '^(main|equals|hashCode|toString|(get|set|is)[A-Z0-9_]\w*)$'
  MaxFallosSeguidos     = 6     # ficheros atascados seguidos (sin un lote bueno entre medias) antes de parar (no gastar llamadas en balde)
  # El modelo de las dudas (consejo y reflexion). Vacio = el de -Modelo. Su esfuerzo: si Copilot no admite max, baja
  # a xhigh y luego a high.
  ModeloDudas           = ''
  EsfuerzoDudas         = 'max'
  # El modelo de reserva si no se pasa -ModeloB (migracion.ps1 lanza el fix sin el). Vacio = sin reserva.
  ModeloB               = ''
  # Tras un intento que no pasa, el modelo de las dudas explica por que y que hacer, y el siguiente intento lo lleva.
  # 'repetido' (por defecto, decision del usuario del 18-11): solo cuando el intento falla con los mismos NO PASA que el
  # anterior del mismo lote (la misma lista sin las cifras, o los mismos hallazgos nuevos); asi no se paga una reflexion
  # por un fallo que el siguiente intento arregla solo (la medida del M6, el caso de dos ficheros que necesitan la misma
  # pieza comun, no tuvo ningun atasco y con reflexion la pasada tardo de 3 a 4 veces mas y costo de 5 a 8 veces mas).
  # 'siempre' (o true) reflexiona tras cada intento que no pasa; 'nunca' (o false), nunca.
  Reflexionar           = 'repetido'
  # Esfuerzo de los reintentos (decision del usuario del 18-11): los intentos 2 y siguientes de un lote y los escalones
  # (de uno en uno, modelo de reserva, consejo) van con este si es mayor que el de -Esfuerzo; si no, con el de -Esfuerzo.
  # Vacio = como hasta ahora. Si Copilot no admite el esfuerzo, baja con Get-EsfuerzosMenores (max -> xhigh -> high).
  EsfuerzoReintento     = 'high'
  LineasDiff            = 300   # lineas del diff del intento que recibe la reflexion
  # Sonar. El paso 'sonar' (el ultimo) arregla las incidencias del informe que se pasa con -Sonar. Se arreglan las de estas severidades, o las
  # de estos tipos con una severidad que no sea MINOR ni INFO; solo Java.
  SonarTipos            = @('BUG', 'VULNERABILITY')
  SonarSeveridades      = @('BLOCKER', 'CRITICAL', 'MAJOR')
  # Las columnas de la hoja del informe: nombre -> alias (da igual mayusculas, tildes y espacios de los bordes; el nombre mismo vale siempre).
  # Obligatorias: Severity, Message, Issue Type y Path.
  SonarColumnas         = @{
    'Severity'    = @('Severity', 'Severidad', 'Gravedad')
    'Message'     = @('Message', 'Mensaje', 'Descripcion')
    'Issue Type'  = @('Issue Type', 'Type', 'Tipo', 'Tipo de incidencia')
    'Path'        = @('Path', 'Ruta', 'Component', 'Componente', 'File', 'Fichero', 'Archivo')
    'Line Number' = @('Line Number', 'Line', 'Linea', 'Numero de linea')
    'Resource'    = @('Resource', 'Recurso')
    'Tags'        = @('Tags', 'Etiquetas')
    'Language'    = @('Language', 'Lenguaje', 'Idioma')
  }
  # Lo que se le pide al modelo en cada lote de Sonar, las recetas por regla (SonarRecetas; con Avisar = $true lo arreglado asi se lista al final),
  # los mensajes que no se mandan al modelo (SonarNoAutomatizar) y lo que un intento no puede hacer, mirado en el diff entero del lote
  # (SonarProhibido; Modo anadida, neto+, neto- o neto0; Si y Salvo condicionan la entrada a los mensajes del lote): los valores por defecto
  # salen de sonar-reglas.ps1. Las Rx se aplican a la linea sin su + o - y sin distinguir mayusculas.
  SonarPrompt           = $SonarPromptReal
  SonarRecetas          = $SonarRecetasReal
  SonarNoAutomatizar    = $SonarNoAutomatizarReal
  SonarProhibido        = $SonarProhibidoReal
  # Maven
  MvnCompilar           = @('-q', '-B', '-DskipTests', 'test-compile')
  # con tests: siempre se ejecutan y un fallo no se ignora (como prueba-local.ps1); un <skipTests> en la <configuration> del pom gana al -D:
  # por eso Invoke-Build lee tambien los informes de surefire cuando Maven sale con 0
  MvnTests              = @('-q', '-B', '-DskipTests=false', '-Dmaven.test.skip=false', '-Dmaven.test.failure.ignore=false', 'test')
}

# ============================== UTILIDADES ==============================
# Ficheros de un arbol, sin entrar en carpetas ignoradas.
function Get-Arbol([string]$Dir, [int]$Prof = 99) {
  $out = New-Object System.Collections.Generic.List[object]
  $pila = New-Object System.Collections.Stack
  $pila.Push(@($Dir, 0))
  while ($pila.Count -gt 0) {
    $it = $pila.Pop()
    foreach ($e in @(Get-ChildItem -LiteralPath $it[0] -Force)) {
      if ($e.PSIsContainer) {
        if (($Cfg.DirsIgnorados -notcontains $e.Name) -and ($it[1] -lt $Prof)) { $pila.Push(@($e.FullName, ($it[1] + 1))) }
      }
      else { $out.Add($e) }
    }
  }
  return $out.ToArray()
}

function Get-Imports([string]$Ruta) {
  $res = New-Object System.Collections.Generic.List[object]
  $n = 0
  foreach ($l in [System.IO.File]::ReadAllLines($Ruta)) {
    $n++
    if ($l -match '^\s*import\s+(static\s+)?([\w\.]+(\.\*)?)\s*;') { $res.Add([pscustomobject]@{ Linea = $n; Fqn = $Matches[2] }) }
    elseif ($l -match '^\s*(public\s+|final\s+|abstract\s+)*(class|interface|enum|record)\s') { break }
  }
  return $res.ToArray()
}

# Paquete base = carpeta de la clase con @SpringBootApplication.
function Get-BaseDir([string]$Raiz) {
  $main = Join-Ruta $Raiz 'src/main/java'
  if (-not (Test-Path -LiteralPath $main)) { return $null }
  foreach ($f in (Get-JavaFiles $main)) {
    if ([System.IO.File]::ReadAllText($f.FullName) -match '@SpringBootApplication') { return $f.DirectoryName }
  }
  $d = $main
  while ($true) {
    $subs = @(Get-ChildItem -LiteralPath $d -Directory)
    $javas = @(Get-ChildItem -LiteralPath $d -File -Filter '*.java')
    if ($subs.Count -eq 1 -and $javas.Count -eq 0) { $d = $subs[0].FullName } else { break }
  }
  return $d
}

# Datos en crudo de un repo (sirve para el repo y para la plantilla).
function Get-Hechos([string]$Raiz) {
  $baseDir = Get-BaseDir $Raiz
  $lista = New-Object System.Collections.Generic.List[object]
  $basePkg = ''
  if ($baseDir) {
    $basePkg = (Get-Rel (Join-Ruta $Raiz 'src/main/java') $baseDir) -replace '/', '.'
    foreach ($f in (Get-JavaFiles $baseDir)) {
      $lista.Add([pscustomobject]@{
          Rel     = Get-Rel $baseDir $f.FullName
          RelRaiz = Get-Rel $Raiz $f.FullName
          Texto   = [System.IO.File]::ReadAllText($f.FullName)
          Imports = @(Get-Imports $f.FullName)
        })
    }
  }
  $tests = New-Object System.Collections.Generic.List[object]
  foreach ($f in (Get-JavaFiles (Join-Ruta $Raiz 'src/test/java'))) {
    $tests.Add([pscustomobject]@{ RelRaiz = Get-Rel $Raiz $f.FullName; Texto = [System.IO.File]::ReadAllText($f.FullName); Imports = @(Get-Imports $f.FullName) })
  }
  $yml = ''
  $ymls = New-Object System.Collections.Generic.List[object]
  # Spring Boot carga application* de classpath:/ y de classpath:/config/
  foreach ($sub in @('src/main/resources', 'src/main/resources/config')) {
    $res = Join-Ruta $Raiz $sub
    if (-not (Test-Path -LiteralPath $res)) { continue }
    foreach ($f in @(Get-ChildItem -LiteralPath $res -File | Where-Object { $_.Name -match '^application.*\.(ya?ml|properties)$' })) {
      $t = [System.IO.File]::ReadAllText($f.FullName)
      $yml += $t + "`n"
      $ymls.Add([pscustomobject]@{ Rel = Get-Rel $Raiz $f.FullName; Nombre = $f.Name; Texto = $t })
    }
  }
  return [pscustomobject]@{ Raiz = $Raiz; BaseDir = $baseDir; BasePkg = $basePkg; Ficheros = $lista.ToArray(); Tests = $tests.ToArray(); Yml = $yml; YmlFicheros = $ymls.ToArray() }
}

function Get-Norm([string]$Fqn, [string]$BasePkg) {
  if ($BasePkg -and $Fqn.StartsWith($BasePkg + '.')) { return '{base}' + $Fqn.Substring($BasePkg.Length) }
  return $Fqn
}
function Get-Paquete([string]$Fqn) {
  $i = $Fqn.LastIndexOf('.')
  if ($i -lt 0) { return $Fqn }
  return $Fqn.Substring(0, $i)
}
function Get-Carpeta([string]$Rel) {
  $i = $Rel.LastIndexOf('/')
  if ($i -lt 0) { return '' }
  return $Rel.Substring(0, $i)
}

# Imports que rompen las reglas de capas.
function Get-ViolImports($Hechos) {
  $out = New-Object System.Collections.Generic.List[object]
  foreach ($f in $Hechos.Ficheros) {
    foreach ($r in $Cfg.Reglas) {
      if (-not $f.Rel.StartsWith($r.En)) { continue }
      foreach ($imp in $f.Imports) {
        $norm = Get-Norm $imp.Fqn $Hechos.BasePkg
        if ($norm -match $r.No) {
          $out.Add([pscustomobject]@{ RelRaiz = $f.RelRaiz; Linea = $imp.Linea; Fqn = $imp.Fqn; Clave = ($r.En + '|' + (Get-Paquete $norm)); Por = $r.Por })
        }
      }
    }
  }
  return $out.ToArray()
}

# Uso de ficheros locales.
function Get-UsoFicheros($Hechos) {
  $out = New-Object System.Collections.Generic.List[object]
  foreach ($f in $Hechos.Ficheros) {
    $dir = Get-Carpeta $f.Rel
    foreach ($imp in $f.Imports) {
      $fqn = ''
      if ($imp.Fqn -match $Cfg.FicheroImport) { $fqn = $imp.Fqn }
      elseif ($imp.Fqn -eq 'java.io.*' -and $f.Texto -match $Cfg.FicheroToken) { $fqn = 'java.io.File' }
      if ($fqn) { $out.Add([pscustomobject]@{ RelRaiz = $f.RelRaiz; Dir = $dir; Linea = $imp.Linea; Fqn = $fqn; Clave = ($dir + '|' + (Get-Paquete $fqn)) }) }
    }
  }
  return $out.ToArray()
}

# Si una carpeta (relativa al paquete base) es de las que pueden abrir ficheros locales.
function Test-FicheroPermitido([string]$Dir) {
  foreach ($p in $Cfg.FicheroPermitidoEn) { if ($Dir -eq $p -or $Dir.StartsWith($p + '/')) { return $true } }
  return $false
}

# Secretos escritos en claro en application*.yml|properties: claves cuyo ultimo trozo acaba en una
# palabra de PalabrasSecreto y cuyo valor es un literal o una variable con valor por defecto.
# Error en application.(yml|yaml|properties); aviso en los de un perfil. El valor no se guarda.
function Get-SecretosEnClaro($Hechos) {
  $out = New-Object System.Collections.Generic.List[object]
  $palabras = @($Cfg.PalabrasSecreto | Where-Object { $_ } | ForEach-Object { [regex]::Escape([string]$_) })
  if ($palabras.Count -eq 0) { return @() }
  $rxClave = '(?i)(' + ($palabras -join '|') + ')$'
  foreach ($y in $Hechos.YmlFicheros) {
    $props = ($y.Nombre -match '\.properties$')
    if ($props) { $sep = '[=:]'; $coment = '^\s*[#!]' } else { $sep = ':'; $coment = '^\s*#' }
    $rxLinea = '^\s*(?:-\s+)?["'']?([^\s:="'']+)["'']?\s*' + $sep + '\s*(.*)$'
    if ($y.Nombre -match '^application\.(ya?ml|properties)$') { $sev = 'error' } else { $sev = 'aviso' }
    $n = 0
    foreach ($l in @($y.Texto -split "`r?`n")) {
      $n++
      if ($l -match $coment -or -not ($l -match $rxLinea)) { continue }
      $clave = $Matches[1]; $v = $Matches[2].Trim()
      if ($clave.Split('.')[-1] -notmatch $rxClave) { continue }
      if ($v -match '^(["''])(.*?)\1(\s|$)') { $v = $Matches[2] }
      elseif (-not $props) { $v = ($v -replace '(^|\s+)#.*$', '').Trim() }
      $literal = ($v -ne '' -and $v -notmatch '\$\{')
      $conDefecto = ($v -match '^\$\{[^:}]*:([^}]*)\}$' -and $Matches[1].Trim() -ne '')
      if ($literal -or $conDefecto) { $out.Add([pscustomobject]@{ Rel = $y.Rel; Sev = $sev; Linea = $n; Clave = $clave }) }
    }
  }
  return $out.ToArray()
}

# El bloque sftp: del yml de una plantilla (solo .yml/.yaml). $null, o un objeto con Rel (el yml), Ruta (las claves padre y sftp,
# unidas con punto) y Claves (los hijos directos de sftp:, en orden y sin repetir). Vale la primera linea que sea solo 'sftp:' (primero
# en application.yml, luego en los de perfil); los padres salen subiendo por la indentacion; los hijos son las lineas con la
# indentacion del primero, hasta volver a la de sftp: o a una menor. Nunca se copia un valor.
function Get-SftpYml($Hechos) {
  $rxClave = '^\s*["'']?([^\s:"''#]+)["'']?\s*:'
  $rxVacia = '^\s*(#|$)'
  $yamls = @($Hechos.YmlFicheros | Where-Object { $_.Nombre -match '^application\.ya?ml$' }) + @($Hechos.YmlFicheros | Where-Object { $_.Nombre -match '^application.+\.ya?ml$' -and $_.Nombre -notmatch '^application\.ya?ml$' })
  foreach ($y in $yamls) {
    $l = @($y.Texto -split "`r?`n")
    for ($i = 0; $i -lt $l.Count; $i++) {
      if ($l[$i] -notmatch '^(\s*)sftp:\s*$') { continue }
      $sangria = ([regex]::Match($l[$i], '^\s*')).Length
      $ruta = @('sftp')
      $actual = $sangria
      for ($k = $i - 1; $k -ge 0 -and $actual -gt 0; $k--) {
        if ($l[$k] -match $rxVacia) { continue }
        $n = ([regex]::Match($l[$k], '^\s*')).Length
        if ($n -ge $actual) { continue }
        $actual = $n
        if ($l[$k] -match $rxClave) { $ruta = @($Matches[1]) + $ruta }
      }
      $claves = New-Object System.Collections.Generic.List[string]
      $hijo = -1
      for ($k = $i + 1; $k -lt $l.Count; $k++) {
        if ($l[$k] -match $rxVacia) { continue }
        $n = ([regex]::Match($l[$k], '^\s*')).Length
        if ($n -le $sangria) { break }
        if ($hijo -lt 0) { $hijo = $n }
        if ($n -eq $hijo -and $l[$k] -match $rxClave -and -not $claves.Contains($Matches[1])) { $claves.Add($Matches[1]) }
      }
      if ($claves.Count -gt 0) { return [pscustomobject]@{ Rel = $y.Rel; Ruta = ($ruta -join '.'); Claves = $claves.ToArray() } }
    }
  }
  return $null
}

# Texto de todos los ficheros de texto de una carpeta (para buscar literales).
function Get-TextoArbol([string]$Dir) {
  if (-not $Dir -or -not (Test-Path -LiteralPath $Dir)) { return '' }
  $sb = New-Object System.Text.StringBuilder
  foreach ($f in @(Get-Arbol $Dir)) {
    if ($Cfg.ExtTexto -notcontains $f.Extension.ToLower()) { continue }
    if ($f.Length -gt 1MB) { continue }
    [void]$sb.AppendLine([System.IO.File]::ReadAllText($f.FullName))
  }
  return $sb.ToString()
}

# Jobs del original detectados por texto: nombre -> fichero. Se busca sin los
# comentarios (un job comentado no es un job) y con las cadenas, que es donde van los nombres.
function Get-JobsPorRegex([string]$Raiz) {
  $res = @{}
  foreach ($f in @(Get-Arbol $Raiz)) {
    $ext = $f.Extension.ToLower()
    if (($ext -ne '.java' -and $ext -ne '.xml') -or $f.Length -gt 1MB) { continue }
    $t = [System.IO.File]::ReadAllText($f.FullName)
    if ($ext -eq '.xml') { $t = [regex]::Replace($t, '<!--.*?-->', '', [System.Text.RegularExpressions.RegexOptions]::Singleline) }
    else { $t = Get-SinComentarios $t }
    foreach ($rx in $Cfg.JobRegex) {
      foreach ($m in [regex]::Matches($t, $rx)) {
        $n = $m.Groups[1].Value
        if (-not $res.ContainsKey($n)) { $res[$n] = Get-Rel $Raiz $f.FullName }
      }
    }
  }
  return $res
}

function Read-Contrato {
  $p = Join-Path $Work 'contrato.json'
  if (-not (Test-Path -LiteralPath $p)) { return $null }
  try { return ([System.IO.File]::ReadAllText($p) | ConvertFrom-Json) } catch { Aviso 'contrato.json no es JSON valido: lo ignoro.'; return $null }
}

function Get-XmlTextos($Doc, [string]$Ruta) {
  $xp = ''
  foreach ($s in $Ruta.Split('/')) { $xp += "/*[local-name()='$s']" }
  $res = @()
  foreach ($n in $Doc.SelectNodes($xp)) { $res += $n.InnerText.Trim() }
  return $res
}

function Get-Pom([string]$Raiz) {
  $p = Join-Path $Raiz 'pom.xml'
  if (-not (Test-Path -LiteralPath $p)) { return $null }
  $x = New-Object System.Xml.XmlDocument
  try { $x.Load($p) } catch { return [pscustomobject]@{ Valido = $false; Parent = ''; Java = @(); Deps = @() } }
  $par = (@(Get-XmlTextos $x 'project/parent/groupId') + @(Get-XmlTextos $x 'project/parent/artifactId') + @(Get-XmlTextos $x 'project/parent/version')) -join ':'
  $java = @()
  foreach ($k in @('java.version', 'maven.compiler.release', 'maven.compiler.source', 'maven.compiler.target')) { $java += @(Get-XmlTextos $x "project/properties/$k") }
  $deps = @(Get-XmlTextos $x 'project/dependencies/dependency/artifactId')
  return [pscustomobject]@{ Valido = $true; Parent = $par; Java = @($java | Select-Object -Unique); Deps = $deps }
}

# ============================== CALIDAD ==============================
# Comprobaciones por texto. Las de Javadoc siguen el criterio de Checkstyle
# (MissingJavadocType y MissingJavadocMethod: solo lo publico, @Override
# exento), con dos diferencias a proposito: no se pide Javadoc en
# constructores ni en getters y setters. No sustituyen a Sonar.
$RxLexico = New-Object System.Text.RegularExpressions.Regex ('/\*.*?\*/|//[^\n]*|"""[\s\S]*?"""|"(?:\\.|[^"\\\n])*"|''(?:\\.|[^''\\\n])*''', [System.Text.RegularExpressions.RegexOptions]::Singleline)
$RxTipo = '^\s*((?:(?:public|protected|private|abstract|final|static|sealed|non-sealed|strictfp)\s+)*)(class|interface|enum|record|@interface)\s+(\w+)'
$RxMetodoPublico = '^\s*public(?>\s+)(?>(?:(?:static|final|abstract|synchronized|default|native|strictfp)\s+)*)(?!(?:class|interface|enum|record)\b)(?:<[^>]+>\s*)?(?:[\w\.\[\]<>,\?&\s]+?\s+)?(\w+)\s*\('
$RxMetodoInterfaz = '^(?>\s*)(?>(?:(?:public|abstract|default|static)\s+)*)(?!(?:private|protected|class|interface|enum|record|return|throw|new|if|for|while|switch|else|case)\b)(?:<[^>]+>\s*)?[\w\.\[\]<>,\?&\s]+?\s+(\w+)\s*\('
# Un campo con @Autowired, @Inject o @Value. Grupos: 1 la anotacion, 2 los modificadores y el tipo, 3 el nombre (con su valor inicial, si lo tiene)
$RxInyeccion = New-Object System.Text.RegularExpressions.Regex '@(Autowired|Inject|Value)\b(?:\s*\([^)]*\))?(?:\s*@\w+(?:\s*\([^)]*\))?)*\s+((?:(?:private|protected|public|transient|volatile)\s+)*[\w\.\[\]<>,\?\s]+?)\s+(\w+)\s*(?:=[^;]*)?;'
$RxValorValue = '@Value\s*\(\s*(?:value\s*=\s*)?"((?:\\.|[^"\\])*)"\s*\)'
# Clases (class) con sus anotaciones y su cuerpo. Una anotacion pegada: @Nombre o @Nombre(...), con parentesis dentro hasta tres niveles
$RxAnot = '@[\w.]+(?:\s*\((?:[^()]|\((?:[^()]|\([^()]*\))*\))*\))?\s+'
$RxClaseDecl = New-Object System.Text.RegularExpressions.Regex ('(?<anot>(?:' + $RxAnot + ')*)(?<mods>(?:(?:public|protected|private|abstract|final|static|sealed|non-sealed|strictfp)\s+)*)(?<![.\w])class\s+(?<nombre>\w+)(?=[^{;]*(?<cuerpo>\{(?:[^{}]|(?<o>\{)|(?<-o>\}))*(?(o)(?!))\}))')
$RxHoja = New-Object System.Text.RegularExpressions.Regex '\{[^{}]*\}'
$RxLombokCtor = New-Object System.Text.RegularExpressions.Regex '@(?:[\w.]+\.)?(?:NoArgsConstructor|RequiredArgsConstructor|AllArgsConstructor)\b(?:\s*\((?:[^()]|\((?:[^()]|\([^()]*\))*\))*\))?'
$RxComponente = '@(?:[\w.]+\.)?(?:Component|Service|Repository|Controller|RestController|Configuration)\b'
$RxAutowiredOInject = '@(?:[\w.]+\.)?(?:Autowired|Inject)\b'
$RxAutowiredObligatorio = '@(?:[\w.]+\.)?Autowired\b(?!\s*\(\s*required\s*=\s*false\s*\))'
# Una anotacion suelta (con sus argumentos, que no se miran por dentro: @Caching(evict = @CacheEvict(...)) es una) y un metodo con sus anotaciones,
# sus modificadores, su tipo de retorno y su nombre (el cuerpo de la clase ya trae las llaves reducidas a \x01)
$RxAnotUna = New-Object System.Text.RegularExpressions.Regex '@(?<n>[\w.]+)(?<arg>\s*\((?:[^()]|\((?:[^()]|\([^()]*\))*\))*\))?'
$RxMetodo = New-Object System.Text.RegularExpressions.Regex ('(?<![^;\x01])\s*(?<anot>(?:' + $RxAnot + ')+)(?<mods>(?>(?:(?:public|protected|private|static|abstract|final|synchronized|native|strictfp|default)\s+)*))(?:<[^;\x01()]*>\s*)?(?<tipo>[\w.]+)(?:\s*<[^;\x01()]*>)?(?:\s*\[\s*\])*\s+(?<nombre>\w+)\s*\(')
# Las anotaciones con las que Spring envuelve un bean con un proxy de clase (CGLIB: una subclase, que una clase final no admite). En un metodo
# basta una de estas; en la clase, tambien las de abajo, @Configuration (salvo con proxyBeanMethods = false) y los scopes de proxy (@StepScope,
# @JobScope y @Scope con TARGET_CLASS, que valen tambien en el @Bean que devuelve la clase).
$ProxyMetodo = @('Transactional', 'Async', 'Retryable', 'Cacheable', 'CachePut', 'CacheEvict', 'Caching')
$ProxyClase = @('Repository', 'Validated') + $ProxyMetodo
$RxConsola = New-Object System.Text.RegularExpressions.Regex '\bSystem\s*\.\s*(?:out|err)\s*\.\s*print\w*\s*\(|\.\s*printStackTrace\s*\(\s*\)'
$RxCatchVacio = New-Object System.Text.RegularExpressions.Regex 'catch\s*\([^)]*\)\s*\{\s*\}'
$RxCatch = New-Object System.Text.RegularExpressions.Regex '\bcatch\s*\('
$RxEnvoltorio = New-Object System.Text.RegularExpressions.Regex '\bnew\s+(Integer|Long|Double|Float|Short|Byte|Boolean|Character)\s*\('
$RxInstanceof = New-Object System.Text.RegularExpressions.Regex 'instanceof\s+([\w\.]+)\s*\)\s*\{?\s*(?:final\s+)?\1\s+\w+\s*=\s*\(\s*\1\s*\)'
$RxColeccion = New-Object System.Text.RegularExpressions.Regex '\b(StringBuffer|Vector|Hashtable)\b'
$RxFechaAntigua = '^java\.(util\.(Date|Calendar|GregorianCalendar)|text\.SimpleDateFormat)$'

# Codigo sin comentarios ni literales, con los mismos saltos de linea.
# Donde acaba un Javadoc deja /*JD*/ y donde habia otro comentario, /*C*/.
function Get-Limpio([string]$Texto) {
  return $script:RxLexico.Replace($Texto, [System.Text.RegularExpressions.MatchEvaluator] {
      param($m)
      $v = $m.Value
      $nl = "`n" * ($v.Split("`n").Count - 1)
      if ($v.StartsWith('/**') -and $v.Length -gt 4) { return $nl + '/*JD*/' }
      if ($v.StartsWith('/')) { return $nl + '/*C*/' }
      if ($v.StartsWith('"')) { return $nl + '""' }
      return "''"
    })
}

# Que hay pegado encima de la declaracion de la linea $I: 'doc' (un Javadoc),
# 'override' (@Override sin Javadoc) o '' (nada). Entre el Javadoc y la
# declaracion solo puede haber anotaciones y lineas en blanco.
function Get-Encima([string[]]$Cod, [bool[]]$Jd, [int]$I) {
  if ($Jd[$I]) { return 'doc' }
  $ov = $false
  for ($k = $I - 1; $k -ge 0; $k--) {
    $t = $Cod[$k].Trim()
    if ($Jd[$k]) {
      if (-not $t -or $t.StartsWith('@')) { return 'doc' }
      break
    }
    if (-not $t) { continue }
    if ($t.StartsWith('@')) {
      if ($t -cmatch '^@Override\b') { $ov = $true }
      continue
    }
    if ($t -cmatch '[;{}]$') { break }
  }
  if ($ov) { return 'override' }
  return ''
}

function Add-Cal($Lista, [string]$Rel, [int]$Linea, [string]$Regla, [string]$Detalle) {
  [void]$Lista.Add([pscustomobject]@{ RelRaiz = $Rel; Linea = $Linea; Regla = $Regla; Detalle = $Detalle })
}

function Get-LineaDe([string]$Texto, [int]$Indice) { return $Texto.Substring(0, $Indice).Split("`n").Count }

# Las clases de un texto sin comentarios ni cadenas (Get-Limpio), tambien las anidadas, cada una con su linea, sus anotaciones, si es final y lo que
# tiene en su primer nivel (Top): el cuerpo con lo que va entre llaves (metodos, bloques, clases anidadas) reducido a un \x01 seguido de los saltos
# de linea que tenia (asi se sabe la linea de cada cosa: LineaCuerpo es la de la llave que abre la clase).
$EvalHoja = [System.Text.RegularExpressions.MatchEvaluator] { param($h) return ([string][char]1) + ("`n" * ($h.Value.Split("`n").Count - 1)) }
function Get-Clases([string]$Limpio) {
  $res = New-Object System.Collections.Generic.List[object]
  foreach ($m in $script:RxClaseDecl.Matches($Limpio)) {
    $top = $m.Groups['cuerpo'].Value
    $top = $top.Substring(1, $top.Length - 2)
    do { $antes = $top; $top = $script:RxHoja.Replace($top, $script:EvalHoja) } while ($top -ne $antes)
    [void]$res.Add([pscustomobject]@{
        Nombre = $m.Groups['nombre'].Value; Linea = (Get-LineaDe $Limpio $m.Groups['nombre'].Index); LineaCuerpo = (Get-LineaDe $Limpio $m.Groups['cuerpo'].Index)
        Anot = $m.Groups['anot'].Value; Final = ($m.Groups['mods'].Value -cmatch '\bfinal\b'); Top = $top
      })
  }
  return $res.ToArray()
}

# Los constructores de una clase: los escritos (con su anotacion y si llevan parametros) y los que genera Lombok (@NoArgsConstructor,
# @RequiredArgsConstructor, @AllArgsConstructor; su Anot es la propia anotacion, que puede llevar onConstructor_ = @__(@Autowired)).
# Quedan fuera los que implica @Data, @Value o @Builder de Lombok y los de un record o un enum.
function Get-Constructores($Clase) {
  $res = New-Object System.Collections.Generic.List[object]
  $rx = '(?<![^;\x01])\s*(?<anot>(?:' + $script:RxAnot + ')*)(?:(?:public|protected|private)\s+)?' + [regex]::Escape($Clase.Nombre) + '\s*\((?<params>(?:[^()]|\((?:[^()]|\([^()]*\))*\))*)\)\s*(?:throws\s+[^;\x01(]+)?\x01'
  foreach ($m in [regex]::Matches($Clase.Top, $rx)) {
    [void]$res.Add([pscustomobject]@{ Anot = $m.Groups['anot'].Value; Escrito = $true; Params = ($m.Groups['params'].Value.Trim() -ne '') })
  }
  foreach ($m in $script:RxLombokCtor.Matches($Clase.Anot)) {
    [void]$res.Add([pscustomobject]@{ Anot = $m.Value; Escrito = $false; Params = ($m.Value -cnotmatch 'NoArgsConstructor') })
  }
  return $res.ToArray()
}

# Las anotaciones de un texto, cada una con su nombre sin paquete y sus argumentos tal cual.
function Get-Anotaciones([string]$Anot) {
  return @($script:RxAnotUna.Matches($Anot) | ForEach-Object { [pscustomobject]@{ Nombre = $_.Groups['n'].Value.Split('.')[-1]; Arg = $_.Groups['arg'].Value } })
}

# Los metodos de una clase que llevan alguna anotacion: sus anotaciones (Get-Anotaciones), si son final, su tipo de retorno (sin paquete), su
# nombre y la linea de su declaracion.
function Get-Metodos($Clase) {
  $res = New-Object System.Collections.Generic.List[object]
  foreach ($m in $script:RxMetodo.Matches($Clase.Top)) {
    $linea = $Clase.LineaCuerpo + $Clase.Top.Substring(0, $m.Groups['mods'].Index).Split("`n").Count - 1
    [void]$res.Add([pscustomobject]@{ Anots = @(Get-Anotaciones $m.Groups['anot'].Value); Final = ($m.Groups['mods'].Value -cmatch '\bfinal\b'); Tipo = $m.Groups['tipo'].Value.Split('.')[-1]; Nombre = $m.Groups['nombre'].Value; Linea = $linea })
  }
  return $res.ToArray()
}

# De unas anotaciones (Get-Anotaciones), las que hacen que Spring envuelva el bean con un proxy de clase (CGLIB: una subclase, y una clase final no
# se puede heredar), con su @. $Donde: 'metodo' (las de $ProxyMetodo), 'bean' (los scopes de proxy, que valen en el @Bean que devuelve la clase) o
# 'clase' (todas, mas @Configuration salvo con proxyBeanMethods = false).
# Fuentes (fuentes-m72, 22-11): Spring Framework, core/aop/proxying.adoc: "final classes cannot be proxied, because they cannot be extended" y "final
# methods cannot be advised, because they cannot be overridden"; Configuration.java: "Configuration classes must be non-final (allowing for subclasses
# at runtime), unless the proxyBeanMethods flag is set to false"; PersistenceExceptionTranslationPostProcessor.java: proxy para los beans con
# @Repository, y Spring Boot (AopAutoConfiguration y PersistenceExceptionTranslationAutoConfiguration): spring.aop.proxy-target-class es true por
# defecto; StepScope.java y JobScope.java (Spring Batch): son @Scope(proxyMode = TARGET_CLASS). @Transactional, @Async, @Cacheable (y las de cache),
# @Validated y @Retryable los aplica el mismo proxy automatico (EnableTransactionManagement, EnableAsync, EnableCaching, MethodValidationPostProcessor,
# EnableResilientMethods). Sonar way no tiene una regla que lo mida.
function Get-AnotacionesProxy($Anots, [string]$Donde) {
  $res = @()
  foreach ($a in $Anots) {
    $scope = ($a.Nombre -ceq 'StepScope' -or $a.Nombre -ceq 'JobScope' -or ($a.Nombre -ceq 'Scope' -and $a.Arg -cmatch '\bTARGET_CLASS\b'))
    $vale = $false
    if ($Donde -eq 'metodo') { $vale = ($script:ProxyMetodo -ccontains $a.Nombre) }
    elseif ($Donde -eq 'bean') { $vale = $scope }
    else { $vale = ($scope -or ($script:ProxyClase -ccontains $a.Nombre) -or ($a.Nombre -ceq 'Configuration' -and $a.Arg -cnotmatch '\bproxyBeanMethods\s*=\s*false')) }
    if ($vale) { $res += '@' + $a.Nombre }
  }
  return $res
}

# Codigo sin comentarios y con las cadenas, con los mismos saltos de linea que el texto.
function Get-SinComentarios([string]$Texto) {
  return $script:RxLexico.Replace($Texto, [System.Text.RegularExpressions.MatchEvaluator] {
      param($m)
      if ($m.Value.StartsWith('/')) { return "`n" * ($m.Value.Split("`n").Count - 1) }
      return $m.Value
    })
}

# Las dos reglas de estilo coherente (miran todo el batch). Hecho: de donde salen las clases contadas. ConLombok y SinLombok: el orden en que
# se elige el estilo que manda si empatan, segun el pom del migrado tenga Lombok o no.
$EstiloReglas = @(
  @{ Regla = 'estilo-constructor'; Hecho = 'Ctor'; Unidad = 'clase'; ConLombok = @('lombok', 'mano'); SinLombok = @('mano', 'lombok') },
  @{ Regla = 'estilo-logger'; Hecho = 'Logger'; Unidad = 'logger'; ConLombok = @('slf4j', 'factory', 'otro'); SinLombok = @('factory', 'slf4j', 'otro') }
)
# De cada estilo: su nombre, como se describe una clase que lo usa y que hay que hacer en otra clase para pasarla a ese estilo
$EstiloTextos = @{
  lombok  = @{ Nombre = 'Lombok'; Es = 'Constructor con Lombok'; Pasa = 'Pasala a @RequiredArgsConstructor de Lombok con los campos private final, en el mismo orden.' }
  mano    = @{ Nombre = 'el constructor a mano'; Es = 'Constructor escrito a mano'; Pasa = 'Escribe el constructor a mano con los campos private final, en el mismo orden, y quita la anotacion de Lombok.' }
  slf4j   = @{ Nombre = '@Slf4j'; Es = 'Logger con @Slf4j'; Pasa = 'Pasalo a @Slf4j de Lombok (el campo se llama log) y quita el campo del logger.' }
  factory = @{ Nombre = 'LoggerFactory'; Es = 'Logger con LoggerFactory'; Pasa = 'Pasalo a LoggerFactory.getLogger(...) en un campo private static final y quita @Slf4j.' }
  otro    = @{ Nombre = 'otro logger (LogManager, java.util.logging...)'; Es = 'Logger con LogManager, java.util.logging u otro'; Pasa = 'Usa el mismo logger que el resto del batch.' }
}

# Estilo coherente. $Datos trae, por regla (Ctor y Logger), una fila por clase contada (RelRaiz, Linea, Estilo) y $Plantilla las cuentas de la
# plantilla (estilo -> clases), o $null si lo que se mira es la propia plantilla. Si el migrado mezcla estilos, manda el de la plantilla cuando
# usa uno solo; si la plantilla mezcla o no tiene clases que contar, manda el que mas usa el migrado (asi una plantilla que mezcla no obliga a
# cambiar la mayoria del migrado); si empatan, Lombok cuando el pom del migrado lo tiene. Cada clase de otro estilo sale en $Out. Devuelve las
# cuentas del migrado (para que sean las de la plantilla) y, si hay mezcla, la linea de la consola (solo con los estilos que tienen clases).
function Add-CalEstilo($Out, $Hechos, $Datos, $Plantilla) {
  $pom = Get-Pom $Hechos.Raiz
  $conLombok = [bool]($pom -and $pom.Valido -and ($pom.Deps -contains 'lombok'))
  $cuentas = @{}
  $mezcla = @()
  foreach ($r in $script:EstiloReglas) {
    $filas = $Datos[$r.Hecho].ToArray()
    $mias = @{}
    foreach ($x in $filas) { $mias[$x.Estilo] = 1 + [int]$mias[$x.Estilo] }
    $cuentas[$r.Hecho] = $mias
    if ($mias.Count -lt 2) { continue }
    $base = $mias
    $enPlantilla = ($Plantilla -and $Plantilla[$r.Hecho].Count -eq 1)
    if ($enPlantilla) { $base = $Plantilla[$r.Hecho] }
    $orden = $r.SinLombok
    if ($conLombok) { $orden = $r.ConLombok }
    $tope = ($base.Values | Measure-Object -Maximum).Maximum
    $manda = @($orden | Where-Object { [int]$base[$_] -eq $tope })[0]
    $n = [int]$mias[$manda]
    $total = ($mias.Values | Measure-Object -Sum).Sum
    $donde = @()
    if ($n -gt 0) { $donde += "en el resto del batch ($n de $total clases)" }
    if ($enPlantilla) { $donde += 'en la plantilla' }
    foreach ($x in @($filas | Where-Object { $_.Estilo -ne $manda })) {
      Add-Cal $Out $x.RelRaiz $x.Linea $r.Regla ($script:EstiloTextos[$x.Estilo].Es + '; ' + ($donde -join ' y ') + ' se usa ' + $script:EstiloTextos[$manda].Nombre + '. ' + $script:EstiloTextos[$manda].Pasa)
    }
    $otros = @()
    foreach ($s in @($orden | Where-Object { $_ -ne $manda -and $mias.ContainsKey($_) })) {
      $c = [int]$mias[$s]
      if ($otros.Count -eq 0) {
        $unidad = $r.Unidad
        if ($c -ne 1) { $unidad += 's' }
        $otros += "$c $unidad con " + $script:EstiloTextos[$s].Nombre
      }
      else { $otros += "$c con " + $script:EstiloTextos[$s].Nombre }
    }
    $texto = ($otros -join ' y ')
    if ($n -gt 0) { $texto += " frente a $n con " + $script:EstiloTextos[$manda].Nombre }
    $mezcla += $texto
  }
  $linea = ''
  if ($mezcla.Count -gt 0) { $linea = 'Estilo: ' + ($mezcla -join '; ') }
  return [pscustomobject]@{ Cuentas = $cuentas; Linea = $linea }
}

# Faltas de calidad del codigo de src/main (sin decidir aun si son error o aviso). $EstiloPlantilla: las cuentas de estilo de la plantilla
# (Cuentas de lo que devolvio esta funcion para ella), o $null para la propia plantilla. Devuelve los hallazgos, las cuentas de estilo y la
# linea de la consola sobre el estilo ('' si no hay mezcla).
function Get-Calidad($Hechos, $EstiloPlantilla = $null) {
  $out = New-Object System.Collections.Generic.List[object]
  $datos = @{ Ctor = (New-Object System.Collections.Generic.List[object]); Logger = (New-Object System.Collections.Generic.List[object]) }
  $finales = New-Object System.Collections.Generic.List[object]   # las clases final (RelRaiz, Linea, Nombre, Motivos por los que Spring las envolveria)
  $tiposProxy = @{}                                              # tipo devuelto por un @Bean con scope de proxy -> sus motivos
  foreach ($f in $Hechos.Ficheros) {
    $marcado = Get-Limpio $f.Texto
    $limpio = $marcado.Replace('/*JD*/', '').Replace('/*C*/', '')
    $lin = $marcado.Split("`n")
    $n = $lin.Count
    $cod = New-Object string[] $n
    $jd = New-Object bool[] $n
    for ($i = 0; $i -lt $n; $i++) {
      $jd[$i] = $lin[$i].Contains('/*JD*/')
      $cod[$i] = $lin[$i].Replace('/*JD*/', '').Replace('/*C*/', '')
    }
    # Javadoc en los tipos publicos de primer nivel y en sus metodos publicos
    $prof = 0; $tipo = ''; $nombre = ''; $publico = $false
    for ($i = 0; $i -lt $n; $i++) {
      $l = $cod[$i]
      if ($prof -eq 0 -and $l -cmatch $RxTipo) {
        $mods = $Matches[1]; $tipo = $Matches[2]; $nombre = $Matches[3]
        $publico = ($mods -cmatch '\bpublic\b')
        if ($publico -and (Get-Encima $cod $jd $i) -ne 'doc') { Add-Cal $out $f.RelRaiz ($i + 1) 'javadoc-tipo' "$tipo publico '$nombre' sin Javadoc" }
      }
      elseif ($prof -eq 1 -and $publico -and $tipo -ne '@interface') {
        $met = ''
        if ($tipo -eq 'interface') { if ($l -cmatch $RxMetodoInterfaz) { $met = $Matches[1] } }
        elseif ($l -cmatch $RxMetodoPublico) { $met = $Matches[1] }
        if ($met -and $met -cne $nombre -and ($tipo -eq 'interface' -or $met -cnotmatch $Cfg.MetodosSinJavadoc)) {
          if ((Get-Encima $cod $jd $i) -eq '') { Add-Cal $out $f.RelRaiz ($i + 1) 'javadoc-metodo' "metodo publico '$met' sin Javadoc" }
        }
      }
      $prof += ($l.Split('{').Count - $l.Split('}').Count)
    }
    # Practicas que se ven en el texto
    # Campos con @Autowired, @Inject o @Value. Uno static no se inyecta (S7178) y no cuenta ademas como inyeccion por campo; un @Value se
    # lee con sus cadenas (un @Value("...") sin ${...} ni #{...} es una constante, S6804) y solo cuando es de un campo, no de un metodo o parametro.
    $conCadenas = $null
    foreach ($m in $script:RxInyeccion.Matches($limpio)) {
      $anot = $m.Groups[1].Value
      $campo = $m.Groups[3].Value
      $linea = Get-LineaDe $limpio $m.Index
      if ($m.Groups[2].Value -cmatch '\bstatic\b') {
        Add-Cal $out $f.RelRaiz $linea 'inyeccion-estatica' ('@' + $anot + " en el campo '" + $campo + "': Spring no inyecta campos static: queda a null (Sonar S7178). Quita static o la anotacion.")
      }
      elseif ($anot -cne 'Value') {
        Add-Cal $out $f.RelRaiz $linea 'inyeccion-campo' ('@' + $anot + " en el campo '" + $campo + "': usa inyeccion por constructor con campos private final; sin estado mutable en el componente: si un campo guarda estado entre llamadas, no lo conviertas en final ni lo inicialices en el constructor; dilo")
      }
      else {
        if ($null -eq $conCadenas) { $conCadenas = (Get-SinComentarios $f.Texto).Split("`n") }
        if ($conCadenas[$linea - 1] -cmatch $script:RxValorValue -and $Matches[1] -notmatch '[$#]\{') {
          Add-Cal $out $f.RelRaiz $linea 'value-sin-expresion' ("@Value sin `${...} ni #{...}: es una constante (Sonar S6804). Si es una propiedad, falta el `${...}.")
        }
      }
    }
    # Constructores y logger de cada clase (las anidadas cuentan aparte)
    foreach ($c in @(Get-Clases $limpio)) {
      $ctores = @(Get-Constructores $c)
      $componente = ($c.Anot -cmatch $script:RxComponente)
      # S6829: con varios constructores, Spring necesita que uno lleve @Autowired o @Inject
      if ($componente -and $ctores.Count -ge 2 -and @($ctores | Where-Object { $_.Anot -cmatch $script:RxAutowiredOInject }).Count -eq 0) {
        Add-Cal $out $f.RelRaiz $c.Linea 'constructores-sin-autowired' ("$($ctores.Count) constructores y ninguno con @Autowired: Spring no sabe cual usar y el bean puede no crearse (Sonar S6829). Deja un solo constructor (sin @Autowired, sobra) o marca con @Autowired el que debe usar Spring.")
      }
      # S6818: solo uno puede llevar @Autowired sin required = false
      $marcados = @($ctores | Where-Object { $_.Anot -cmatch $script:RxAutowiredObligatorio }).Count
      if ($marcados -ge 2) { Add-Cal $out $f.RelRaiz $c.Linea 'autowired-varios' "@Autowired en $marcados constructores: solo uno puede llevarlo (Sonar S6818)." }
      # Spring envuelve con un proxy de clase lo que lleva @Repository, @Transactional...: una clase final no se puede heredar y el bean no se crea.
      # Una clase final sale cuando acabe el recorrido (un @Bean con scope de proxy de otro fichero puede devolverla); un metodo final, aqui.
      $motivos = @(Get-AnotacionesProxy @(Get-Anotaciones $c.Anot) 'clase')
      foreach ($mt in @(Get-Metodos $c)) {
        $enMetodo = @(Get-AnotacionesProxy $mt.Anots 'metodo')
        if ($enMetodo.Count -gt 0 -and $c.Final) { $motivos += @($enMetodo | ForEach-Object { "$_ en un metodo" }) }
        elseif ($enMetodo.Count -gt 0 -and $mt.Final) { Add-Cal $out $f.RelRaiz $mt.Linea 'metodo-final-proxy' ('Metodo final con ' + ($enMetodo -join ', ') + ': Spring no lo puede interceptar y la anotacion no hace nada. Quita final.') }
        $enBean = @(Get-AnotacionesProxy $mt.Anots 'bean')
        if ($enBean.Count -gt 0 -and @($mt.Anots | Where-Object { $_.Nombre -ceq 'Bean' }).Count -gt 0) {
          if (-not $tiposProxy.ContainsKey($mt.Tipo)) { $tiposProxy[$mt.Tipo] = @() }
          $tiposProxy[$mt.Tipo] += ($enBean[0] + ' en el @Bean ' + $mt.Nombre + '()')
        }
      }
      if ($c.Final) { [void]$finales.Add([pscustomobject]@{ RelRaiz = $f.RelRaiz; Linea = $c.Linea; Nombre = $c.Nombre; Motivos = $motivos }) }
      # estilo: las clases con anotacion de componente que reciben dependencias por constructor (Lombok o a mano), y las que declaran un logger
      if ($componente) {
        $escritos = @($ctores | Where-Object { $_.Escrito })
        $estilo = ''
        if (@($escritos | Where-Object { $_.Params }).Count -gt 0) { $estilo = 'mano' }
        elseif ($escritos.Count -eq 0 -and @($ctores | Where-Object { $_.Params }).Count -gt 0) { $estilo = 'lombok' }
        if ($estilo) { [void]$datos.Ctor.Add([pscustomobject]@{ RelRaiz = $f.RelRaiz; Linea = $c.Linea; Estilo = $estilo }) }
      }
      $estilo = ''
      if ($c.Anot -cmatch '@(?:[\w.]+\.)?Slf4j\b') { $estilo = 'slf4j' }
      elseif ($c.Top -cmatch '\bLoggerFactory\s*\.\s*getLogger\s*\(') { $estilo = 'factory' }
      elseif ($c.Anot -cmatch '@(?:[\w.]+\.)?(?:Log4j2?|CommonsLog|JBossLog|Flogger|XSlf4j|CustomLog)\b' -or $c.Top -cmatch '\b(?:LogManager|Logger|LogFactory)\s*\.\s*getLog(?:ger)?\s*\(') { $estilo = 'otro' }
      if ($estilo) { [void]$datos.Logger.Add([pscustomobject]@{ RelRaiz = $f.RelRaiz; Linea = $c.Linea; Estilo = $estilo }) }
    }
    foreach ($m in $script:RxConsola.Matches($limpio)) {
      Add-Cal $out $f.RelRaiz (Get-LineaDe $limpio $m.Index) 'salida-consola' 'System.out, System.err o printStackTrace: usa el logger'
    }
    foreach ($m in $script:RxCatchVacio.Matches($marcado)) {
      Add-Cal $out $f.RelRaiz (Get-LineaDe $marcado $m.Index) 'catch-vacio' 'catch vacio: registra la excepcion o explica en un comentario por que se ignora'
    }
    foreach ($m in $script:RxEnvoltorio.Matches($limpio)) {
      $cls = $m.Groups[1].Value
      Add-Cal $out $f.RelRaiz (Get-LineaDe $limpio $m.Index) 'envoltorio-new' ('new ' + $cls + '(...) esta marcado para eliminarse: usa ' + $cls + '.valueOf(...) o autoboxing')
    }
    foreach ($m in $script:RxInstanceof.Matches($limpio)) {
      Add-Cal $out $f.RelRaiz (Get-LineaDe $limpio $m.Index) 'instanceof-cast' "instanceof seguido de cast: en Java 21 se escribe 'x instanceof Tipo t'"
    }
    $viejas = @($f.Imports | Where-Object { $_.Fqn -cmatch $RxFechaAntigua })
    if ($viejas.Count -gt 0) {
      Add-Cal $out $f.RelRaiz $viejas[0].Linea 'fecha-antigua' ('usa ' + ((@($viejas | ForEach-Object { $_.Fqn })) -join ', ') + ' (API antigua de fechas). Pasarlo a java.time puede cambiar el formato o la zona: hazlo solo con un test delante')
    }
    $mc = $script:RxColeccion.Match($limpio)
    if ($mc.Success) {
      Add-Cal $out $f.RelRaiz (Get-LineaDe $limpio $mc.Index) 'coleccion-antigua' ($mc.Value + ': usa StringBuilder, ArrayList o HashMap si no hace falta sincronizar')
    }
  }
  foreach ($x in $finales) {
    $motivos = @($x.Motivos)
    if ($tiposProxy.ContainsKey($x.Nombre)) { $motivos += @($tiposProxy[$x.Nombre]) }
    if ($motivos.Count -gt 0) {
      Add-Cal $out $x.RelRaiz $x.Linea 'clase-final-proxy' ('Clase final que Spring tiene que envolver con un proxy (por ' + (($motivos | Select-Object -Unique) -join ', ') + '): el bean no se crea y el job no arranca ("Cannot subclass final class"). Quita final de la clase.')
    }
  }
  $estilo = Add-CalEstilo $out $Hechos $datos $EstiloPlantilla
  return [pscustomobject]@{ Hallazgos = $out.ToArray(); Estilo = $estilo.Cuentas; Linea = $estilo.Linea }
}

# Los ficheros de la plantilla fuera de src/ (hasta 2 niveles) que el repo tiene que tener tambien: si es un repo de git, solo los que
# estan en git (git ls-files); si no, los que haya. En ambos casos, sin los de datos o informes (los que deja una herramienta o un
# proceso: .txt, .csv, .json, .html, .md, .log, .dat, .xls, .xlsx, .pdf, .png, .jpg, .svg). Ordenados, para que el aviso sea estable.
function Get-FicherosDePlantilla([string]$Raiz) {
  $rx = '\.(txt|csv|json|html|md|log|dat|xls|xlsx|pdf|png|jpg|svg)$'
  $rels = @()
  if (Test-Path -LiteralPath (Join-Path $Raiz '.git')) {
    $g = Invoke-Git $Raiz @('-c', 'core.quotepath=off', 'ls-files')
    if ($g.Codigo -eq 0) { $rels = @($g.Salida | Where-Object { $_ }) }
  }
  else { $rels = @(Get-Arbol $Raiz 2 | ForEach-Object { Get-Rel $Raiz $_.FullName }) }
  $extra = @()
  foreach ($rel in $rels) {
    $seg = $rel.Split('/')
    if ($rel.StartsWith('src/') -or $seg.Count -gt 3 -or $rel -match $rx) { continue }
    if ($seg.Count -gt 1 -and @($seg[0..($seg.Count - 2)] | Where-Object { $Cfg.DirsIgnorados -contains $_ }).Count -gt 0) { continue }
    $extra += $rel
  }
  [Array]::Sort($extra, [System.StringComparer]::Ordinal)
  return $extra
}

# Lo que se aprende de la plantilla.
function Get-Calibracion([string]$Raiz) {
  $h = Get-Hechos $Raiz
  $capas = @(); $sub2 = @{}; $dirs3 = @{}; $paquetes = @{}
  $excImp = @{}; $excFic = @{}; $tokens = @{}
  foreach ($f in $h.Ficheros) {
    $seg = $f.Rel.Split('/')
    if ($seg.Count -ge 2 -and ($capas -notcontains $seg[0])) { $capas += $seg[0] }
    if ($seg.Count -ge 3) {
      if (-not $sub2.ContainsKey($seg[0])) { $sub2[$seg[0]] = @() }
      if ($sub2[$seg[0]] -notcontains $seg[1]) { $sub2[$seg[0]] += $seg[1] }
    }
    $n = [Math]::Min($seg.Count - 1, 3)
    if ($n -ge 1) { $dirs3[($seg[0..($n - 1)] -join '/')] = $true }
    if ($seg.Count -ge 2) {   # paquete (ruta relativa al paquete base) -> nombres de sus clases
      $dir = $seg[0..($seg.Count - 2)] -join '/'
      if (-not $paquetes.ContainsKey($dir)) { $paquetes[$dir] = @() }
      $paquetes[$dir] += [System.IO.Path]::GetFileNameWithoutExtension($seg[-1])
    }
  }
  foreach ($v in @(Get-ViolImports $h)) { $excImp[$v.Clave] = $true }
  foreach ($u in @(Get-UsoFicheros $h)) { if (-not (Test-FicheroPermitido $u.Dir)) { $excFic[$u.Clave] = $true } }
  $todo = (@($h.Ficheros | ForEach-Object { $_.Texto }) -join "`n")
  foreach ($t in $Cfg.ApiAntigua) { $tokens[$t] = ($todo -match ('\b' + $t + '\b')) }
  $jakarta = $false
  foreach ($f in (@($h.Ficheros) + @($h.Tests))) { foreach ($i in $f.Imports) { if ($i.Fqn.StartsWith('jakarta.')) { $jakarta = $true } } }
  $extra = @(Get-FicherosDePlantilla $Raiz)
  $calReglas = @{}
  $calidad = Get-Calidad $h
  foreach ($q in $calidad.Hallazgos) { $calReglas[$q.Regla] = $true }
  return [pscustomobject]@{
    Capas = $capas; Sub2 = $sub2; Dirs3 = @($dirs3.Keys | Sort-Object); Paquetes = $paquetes
    ExcImports = $excImp; ExcFicheros = $excFic; Tokens = $tokens; UsaJakarta = $jakarta
    Calidad = $calReglas; Estilo = $calidad.Estilo; Secretos = @(Get-SecretosEnClaro $h | Where-Object { $_.Sev -eq 'error' }).Count
    UsaConfigProps = ($todo -match '@ConfigurationProperties'); UsaValue = ($todo -match '@Value\s*\(')
    TieneSftp = (@($h.Ficheros | Where-Object { $_.Rel -match '(^|/)sftp/' }).Count -gt 0)
    YmlSftp = ($h.Yml -match 'sftp'); SftpYml = (Get-SftpYml $h); Pom = (Get-Pom $Raiz); Extra = $extra
  }
}

# El mapa de paquetes de la plantilla para el prompt de un plan o de un lote: una linea por paquete con hasta 4 clases (60 lineas como
# mucho, con la ultima diciendo cuantos faltan). Sin paquetes, nada.
function Get-TextoMapaPaquetes($Cal) {
  $dirs = @($Cal.Paquetes.Keys | Sort-Object)
  if ($dirs.Count -eq 0) { return @() }
  $l = @('## Mapa de paquetes', 'Paquetes de la PLANTILLA. Cada clase nueva va en el paquete de su equivalente de esta lista. No crees paquetes que no esten aqui.')
  $mostrar = $dirs
  if ($dirs.Count -gt 60) { $mostrar = @($dirs | Select-Object -First 59) }
  foreach ($d in $mostrar) {
    $clases = @($Cal.Paquetes[$d] | Sort-Object)
    $l += "- ${d}: " + (($clases | Select-Object -First 4) -join ', ') + $(if ($clases.Count -gt 4) { ', ...' } else { '' })
  }
  if ($dirs.Count -gt 60) { $l += "(y $($dirs.Count - 59) paquetes mas en la PLANTILLA)" }
  return ($l + '')
}

# Cuanto incumple la propia plantilla (lo que se permite en el repo porque ella lo hace), en una linea.
function Get-TextoIncumple($Cal) {
  return "capas $($Cal.ExcImports.Count) | ficheros $($Cal.ExcFicheros.Count) | calidad $($Cal.Calidad.Count) | secretos $($Cal.Secretos)"
}

# ================================ SONAR ================================
# El paso 'sonar' arregla las incidencias de un informe de Sonar (.xlsx, hoja Issues Breakdown). Vale para cualquier repo Maven de
# Java: no necesita plantilla ni original. Aqui van, primero, las funciones puras (leer el xlsx, filtrar, la "unidad" de una
# incidencia y las puertas del diff), que prueba el banco sin lanzar el script, y despues lo que cuelga del repo (la base, el estado de
# cada incidencia, los prompts, las puertas del intento y la lista de lo que falta).

# Un texto sin tildes, en minusculas y con los espacios de los bordes fuera y los de dentro en uno: para comparar cabeceras.
function Get-SonarPlegado([string]$Texto) {
  $t = "$Texto".Normalize([System.Text.NormalizationForm]::FormD)
  $sb = New-Object System.Text.StringBuilder
  foreach ($c in $t.ToCharArray()) {
    if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($c) -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($c) }
  }
  return (($sb.ToString().ToLowerInvariant()) -replace '\s+', ' ').Trim()
}

# El texto de un <si> o un <is>: sus <t> y los <t> de sus <r> (texto enriquecido). La fonetica (<rPh>) no cuenta.
function Get-SonarTextoRico($Nodo) {
  $sb = New-Object System.Text.StringBuilder
  foreach ($c in $Nodo.ChildNodes) {
    if ($c.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }
    if ($c.LocalName -eq 't') { [void]$sb.Append($c.InnerText) }
    elseif ($c.LocalName -eq 'r') {
      foreach ($t in $c.ChildNodes) {
        if ($t.NodeType -eq [System.Xml.XmlNodeType]::Element -and $t.LocalName -eq 't') { [void]$sb.Append($t.InnerText) }
      }
    }
  }
  return $sb.ToString()
}

# Un miembro XML del zip, sin DTD ni recursos externos. $null si el miembro no esta.
function Read-SonarXml($Zip, [string]$Nombre) {
  $e = $Zip.GetEntry($Nombre)
  if ($null -eq $e) { return $null }
  $ajustes = New-Object System.Xml.XmlReaderSettings
  $ajustes.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
  $ajustes.XmlResolver = $null
  $flujo = $e.Open()
  try {
    $lector = [System.Xml.XmlReader]::Create($flujo, $ajustes)
    try {
      $doc = New-Object System.Xml.XmlDocument
      $doc.PreserveWhitespace = $true
      $doc.Load($lector)
    }
    finally { $lector.Dispose() }
  }
  finally { $flujo.Dispose() }
  return , $doc
}

# Las celdas de una hoja: numero de fila -> (numero de columna, desde 1 -> texto). Las celdas se leen por su referencia (B7), no por su
# orden. $Compartidas: las cadenas compartidas del libro.
function Get-SonarCeldasHoja($Doc, $Compartidas) {
  $filas = @{}
  $datos = $null
  foreach ($c in $Doc.DocumentElement.ChildNodes) {
    if ($c.NodeType -eq [System.Xml.XmlNodeType]::Element -and $c.LocalName -eq 'sheetData') { $datos = $c; break }
  }
  if ($null -eq $datos) { return $filas }
  $ultima = 0
  foreach ($fila in $datos.ChildNodes) {
    if ($fila.NodeType -ne [System.Xml.XmlNodeType]::Element -or $fila.LocalName -ne 'row') { continue }
    $num = $ultima + 1
    $r = 0
    if ([int]::TryParse($fila.GetAttribute('r'), [ref]$r) -and $r -ge 1) { $num = $r }
    $ultima = $num
    $celdas = @{}
    $pos = 0
    foreach ($celda in $fila.ChildNodes) {
      if ($celda.NodeType -ne [System.Xml.XmlNodeType]::Element -or $celda.LocalName -ne 'c') { continue }
      $pos++
      $ref = $celda.GetAttribute('r')
      $m = [regex]::Match($ref, '^([A-Za-z]+)')
      if ($m.Success) {
        $pos = 0
        foreach ($ch in $m.Groups[1].Value.ToUpperInvariant().ToCharArray()) { $pos = $pos * 26 + ([int]$ch - 64) }
      }
      $tipo = $celda.GetAttribute('t')
      $texto = $null
      if ($tipo -eq 'inlineStr') {
        foreach ($h in $celda.ChildNodes) {
          if ($h.NodeType -eq [System.Xml.XmlNodeType]::Element -and $h.LocalName -eq 'is') { $texto = Get-SonarTextoRico $h }
        }
      }
      else {
        foreach ($h in $celda.ChildNodes) {
          if ($h.NodeType -ne [System.Xml.XmlNodeType]::Element -or $h.LocalName -ne 'v') { continue }
          $t = $h.InnerText
          if ($tipo -eq 's') {
            $idx = 0
            if (-not [int]::TryParse($t, [ref]$idx) -or $idx -lt 0 -or $idx -ge @($Compartidas).Count) { throw "Cadena compartida invalida en la celda $ref." }
            $texto = $Compartidas[$idx]
          }
          elseif ($tipo -eq '' -or $tipo -eq 'n') {
            # un numero entero sale sin decimales (7 y no 7.0)
            $x = 0.0
            if ([double]::TryParse($t, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$x) -and $x -eq [math]::Floor($x) -and [math]::Abs($x) -lt 1e15) {
              $texto = ([long]$x).ToString([System.Globalization.CultureInfo]::InvariantCulture)
            }
            else { $texto = $t }
          }
          else { $texto = $t }
        }
      }
      if ($null -ne $texto) { $celdas[$pos] = $texto }
    }
    $filas[$num] = $celdas
  }
  return $filas
}

# La fila de cabecera de una hoja: la que lleva mas columnas obligatorias (Severity, Message, Issue Type, Path), buscadas por sus alias
# ($Columnas: nombre -> alias; el nombre mismo vale siempre; da igual mayusculas, tildes y espacios de los bordes). Devuelve Fila,
# Cols (nombre -> columna) y Faltan (las obligatorias que no estan), o $null si la hoja no tiene ninguna.
function Get-SonarCabecera($Filas, $Columnas) {
  $nombres = @('Severity', 'Message', 'Issue Type', 'Path', 'Line Number', 'Resource', 'Tags', 'Language')
  $obligatorias = @('Severity', 'Message', 'Issue Type', 'Path')
  $alias = @{}
  foreach ($n in $nombres) {
    $lista = New-Object System.Collections.Generic.List[string]
    $lista.Add((Get-SonarPlegado $n))
    $v = $null
    if ($Columnas -is [System.Collections.IDictionary]) { if ($Columnas.Contains($n)) { $v = $Columnas[$n] } }
    elseif ($null -ne $Columnas) { $p = $Columnas.PSObject.Properties[$n]; if ($null -ne $p) { $v = $p.Value } }
    foreach ($a in @($v)) { if ($null -ne $a) { $lista.Add((Get-SonarPlegado "$a")) } }
    $alias[$n] = $lista
  }
  $mejor = $null
  foreach ($num in @($Filas.Keys | Sort-Object { [int]$_ })) {
    $celdas = $Filas[$num]
    $cols = @{}
    $usadas = @{}
    foreach ($n in $nombres) {
      foreach ($col in @($celdas.Keys | Sort-Object { [int]$_ })) {
        if ($usadas.ContainsKey($col)) { continue }
        if ($alias[$n] -contains (Get-SonarPlegado $celdas[$col])) { $cols[$n] = $col; $usadas[$col] = $true; break }
      }
    }
    $faltan = @($obligatorias | Where-Object { -not $cols.ContainsKey($_) })
    $buenas = $obligatorias.Count - $faltan.Count
    if ($buenas -eq 0) { continue }
    if ($null -eq $mejor -or $buenas -gt $mejor.Buenas -or ($buenas -eq $mejor.Buenas -and $cols.Count -gt $mejor.Cols.Count)) {
      $mejor = [pscustomobject]@{ Fila = [int]$num; Cols = $cols; Faltan = $faltan; Buenas = $buenas }
    }
  }
  return $mejor
}

# El numero de linea de una celda: 'L32', '32L' o 32 dan 32; el guion, vacio o lo que no trae numero, 0.
function Get-SonarNumeroLinea([string]$Texto) {
  $m = [regex]::Match("$Texto", '\d+')
  if ($m.Success) { return [int]$m.Value }
  return 0
}

# Las incidencias de un informe de Sonar (.xlsx): objetos con Fila (la fila de la hoja, desde 1), Severidad, Mensaje, Lenguaje, Tipo,
# Recurso, Ruta, Linea y Etiquetas. La hoja es 'Issues Breakdown' o, si no esta o no sirve, la primera con las columnas obligatorias. Si
# ninguna sirve, lanza un error que dice cual falta.
function Read-SonarXlsx([string]$Ruta, $Columnas) {
  Add-Type -AssemblyName System.IO.Compression
  $nombre = Split-Path $Ruta -Leaf
  $fs = [System.IO.File]::Open($Ruta, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
  $zip = $null
  try {
    try { $zip = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Read) }
    catch { throw "$nombre no es un .xlsx (no es un zip)." }
    $libro = Read-SonarXml $zip 'xl/workbook.xml'
    if ($null -eq $libro) { throw "$nombre no es un .xlsx (le falta xl/workbook.xml)." }
    $hojas = New-Object System.Collections.Generic.List[object]
    foreach ($n in $libro.GetElementsByTagName('*')) {
      if ($n.LocalName -ne 'sheet') { continue }
      $id = ''
      foreach ($a in $n.Attributes) { if ($a.LocalName -eq 'id') { $id = $a.Value } }
      $hojas.Add([pscustomobject]@{ Nombre = $n.GetAttribute('name'); Id = $id; Pos = ($hojas.Count + 1) })
    }
    # relaciones del libro: id -> miembro del zip (la ruta del Target, contra xl/)
    $rels = @{}
    $compartidasEn = 'xl/sharedStrings.xml'
    $docRels = Read-SonarXml $zip 'xl/_rels/workbook.xml.rels'
    if ($null -ne $docRels) {
      foreach ($n in $docRels.GetElementsByTagName('*')) {
        if ($n.LocalName -ne 'Relationship') { continue }
        $t = $n.GetAttribute('Target')
        if ($t.StartsWith('/')) { $t = $t.TrimStart('/') } else { $t = 'xl/' + $t }
        $partes = New-Object System.Collections.Generic.List[string]
        foreach ($s in $t.Split('/')) {
          if ($s -eq '..') { if ($partes.Count -gt 0) { $partes.RemoveAt($partes.Count - 1) } }
          elseif ($s -and $s -ne '.') { $partes.Add($s) }
        }
        $t = ($partes -join '/')
        $rels[$n.GetAttribute('Id')] = $t
        if ($n.GetAttribute('Type') -like '*/sharedStrings') { $compartidasEn = $t }
      }
    }
    $compartidas = New-Object System.Collections.Generic.List[string]
    $docComp = Read-SonarXml $zip $compartidasEn
    if ($null -ne $docComp) {
      foreach ($n in $docComp.DocumentElement.ChildNodes) {
        if ($n.NodeType -eq [System.Xml.XmlNodeType]::Element -and $n.LocalName -eq 'si') { $compartidas.Add((Get-SonarTextoRico $n)) }
      }
    }
    # la hoja: Issues Breakdown primero, y si no sirve, la primera con las columnas obligatorias
    $buscada = Get-SonarPlegado 'Issues Breakdown'
    $orden = @(@($hojas | Where-Object { (Get-SonarPlegado $_.Nombre) -eq $buscada }) + @($hojas | Where-Object { (Get-SonarPlegado $_.Nombre) -ne $buscada }))
    $elegida = $null
    $falloBuscada = ''
    foreach ($h in $orden) {
      $miembro = "xl/worksheets/sheet$($h.Pos).xml"
      if ($h.Id -and $rels.ContainsKey($h.Id)) { $miembro = $rels[$h.Id] }
      $doc = Read-SonarXml $zip $miembro
      if ($null -eq $doc) { continue }
      $celdas = Get-SonarCeldasHoja $doc $compartidas
      $cab = Get-SonarCabecera $celdas $Columnas
      $faltan = @('Severity', 'Message', 'Issue Type', 'Path')
      if ($null -ne $cab) { $faltan = @($cab.Faltan) }
      if ($faltan.Count -eq 0) { $elegida = [pscustomobject]@{ Celdas = $celdas; Cab = $cab }; break }
      if ((Get-SonarPlegado $h.Nombre) -eq $buscada) { $falloBuscada = "la hoja '$($h.Nombre)' no sirve: " + ((@($faltan | ForEach-Object { "falta la columna obligatoria '$_'" })) -join ', ') }
    }
    if ($null -eq $elegida) {
      if ($falloBuscada) { throw "En $nombre $falloBuscada." }
      throw "En $nombre no hay ninguna hoja 'Issues Breakdown' ni otra con las columnas obligatorias: Severity, Message, Issue Type y Path."
    }
    $cols = $elegida.Cab.Cols
    $coger = {
      param($c, [string]$n)
      if ($cols.ContainsKey($n) -and $c.ContainsKey($cols[$n])) { return [string]$c[$cols[$n]] }
      return ''
    }
    $res = New-Object System.Collections.Generic.List[object]
    foreach ($num in @($elegida.Celdas.Keys | Sort-Object { [int]$_ })) {
      if ([int]$num -le $elegida.Cab.Fila) { continue }
      $c = $elegida.Celdas[$num]
      $sev = (& $coger $c 'Severity').Trim()
      $msg = & $coger $c 'Message'
      $rut = & $coger $c 'Path'
      if (-not $sev -and -not $msg -and -not $rut) { continue }
      $tags = @((& $coger $c 'Tags').Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
      $res.Add([pscustomobject]@{
          Fila = [int]$num; Severidad = $sev; Mensaje = $msg; Lenguaje = (& $coger $c 'Language').Trim(); Tipo = (& $coger $c 'Issue Type').Trim()
          Recurso = (& $coger $c 'Resource').Trim(); Ruta = $rut; Linea = (Get-SonarNumeroLinea (& $coger $c 'Line Number')); Etiquetas = $tags })
    }
    return $res.ToArray()
  }
  finally {
    if ($null -ne $zip) { $zip.Dispose() }
    $fs.Dispose()
  }
}

# Las incidencias que se arreglan: Java (por su lenguaje o, si no lo trae, por acabar en .java) y, o de una severidad de
# $Cfg.SonarSeveridades, o de un tipo de $Cfg.SonarTipos con una severidad que no sea MINOR ni INFO.
function Get-SonarFiltradas($Filas) {
  $tipos = @($Cfg.SonarTipos | ForEach-Object { "$_".Trim().ToUpperInvariant() })
  $sevs = @($Cfg.SonarSeveridades | ForEach-Object { "$_".Trim().ToUpperInvariant() })
  foreach ($f in @($Filas)) {
    $esJava = ("$($f.Lenguaje)".Trim() -ieq 'Java') -or (-not "$($f.Lenguaje)".Trim() -and "$($f.Ruta)".Trim() -match '(?i)\.java$')
    if (-not $esJava) { continue }
    $sev = "$($f.Severidad)".Trim().ToUpperInvariant()
    $tipo = "$($f.Tipo)".Trim().ToUpperInvariant()
    if (($sevs -contains $sev) -or (($tipos -contains $tipo) -and @('MINOR', 'INFO') -notcontains $sev)) { $f }
  }
}

# Codigo sin comentarios que no sean Javadoc y sin ningun espacio: lo que queda es lo que hace el codigo (y su Javadoc). Reformatear no
# lo cambia; cambiar el codigo o anadir un Javadoc, si.
function Get-SonarNormal([string]$Texto) {
  $sin = $script:RxLexico.Replace($Texto, [System.Text.RegularExpressions.MatchEvaluator] {
      param($m)
      $v = $m.Value
      if ($v.StartsWith('/**') -and $v.Length -gt 4) { return $v }
      if ($v.StartsWith('/')) { return '' }
      return $v
    })
  return ($sin -replace '\s+', '')
}

# La unidad de una incidencia: su linea marcada o, si esa linea abre un bloque { que no cierra en ella, el bloque entero hasta su llave de
# cierre, con las anotaciones y el Javadoc que lleva pegados encima. Normalizada (Get-SonarNormal). SinDoc dice que un bloque no tenia
# Javadoc (si despues aparece uno encima, la incidencia ya no esta). Sin linea (0) o fuera de rango, el fichero entero.
function Get-SonarUnidad([string]$Texto, [int]$Linea) {
  $orig = @($Texto -split "`r?`n")
  $entero = [pscustomobject]@{ Unidad = (Get-SonarNormal $Texto); SinDoc = $false }
  if ($Linea -lt 1 -or $Linea -gt $orig.Count) { return $entero }
  $limp = @((Get-Limpio $Texto) -split "`r?`n")
  if ($limp.Count -ne $orig.Count) { return $entero }
  $i = $Linea - 1
  $abiertas = 0
  foreach ($ch in $limp[$i].ToCharArray()) {
    if ($ch -eq '{') { $abiertas++ }
    elseif ($ch -eq '}' -and $abiertas -gt 0) { $abiertas-- }
  }
  if ($abiertas -eq 0) {
    $u = Get-SonarNormal $orig[$i]
    if (-not $u) { return $entero }   # una linea sin codigo (en blanco, de comentario): cualquier cambio del fichero vale
    return [pscustomobject]@{ Unidad = $u; SinDoc = $false }
  }
  # hasta la llave que cierra el bloque (la linea entera)
  $fin = $i
  $d = $abiertas
  for ($k = $i + 1; $k -lt $limp.Count -and $d -gt 0; $k++) {
    foreach ($ch in $limp[$k].ToCharArray()) {
      if ($ch -eq '{') { $d++ }
      elseif ($ch -eq '}') { $d--; if ($d -eq 0) { break } }
    }
    $fin = $k
  }
  # hacia arriba: las anotaciones, y encima de ellas, si lo hay, el Javadoc
  $ini = $i
  $k = $i - 1
  while ($k -ge 0 -and $limp[$k].Trim().StartsWith('@')) { $ini = $k; $k-- }
  while ($k -ge 0 -and $limp[$k].Trim() -eq '') { $k-- }
  $sinDoc = $true
  if ($k -ge 0 -and $limp[$k].Trim().EndsWith('/*JD*/')) {
    foreach ($m in $script:RxLexico.Matches($Texto)) {
      if (-not $m.Value.StartsWith('/**') -or $m.Value.Length -le 4) { continue }
      $antes = $Texto.Substring(0, $m.Index)
      $l0 = $antes.Length - $antes.Replace("`n", '').Length
      $l1 = $l0 + $m.Value.Length - $m.Value.Replace("`n", '').Length
      if ($l1 -eq $k) { $ini = $l0; $sinDoc = $false; break }
    }
  }
  return [pscustomobject]@{ Unidad = (Get-SonarNormal ($orig[$ini..$fin] -join "`n")); SinDoc = $sinDoc }
}

# Sigue en el fichero la unidad de una incidencia? $Normal es el fichero normalizado. $Indice: si la misma unidad esta varias veces (una
# linea corriente como 'return null;'), la de orden $Indice sigue ahi mientras haya mas de $Indice. Con SinDoc, una aparicion pegada a un
# Javadoc ('*/' justo antes) no cuenta: el Javadoc se ha anadido encima.
function Test-SonarSigueAhi([string]$Unidad, [bool]$SinDoc, [string]$Normal, [int]$Indice = 0) {
  if (-not $Unidad) { return $false }
  $n = 0
  $pos = 0
  while ($true) {
    $p = $Normal.IndexOf($Unidad, $pos, [System.StringComparison]::Ordinal)
    if ($p -lt 0) { break }
    $pos = $p + $Unidad.Length
    if ($SinDoc -and $p -ge 2 -and $Normal.Substring($p - 2, 2) -eq '*/') { continue }
    $n++
    if ($n -gt $Indice) { return $true }
  }
  return $false
}

# Las entradas de SonarProhibido que el diff de un intento incumple: sus motivos, en el orden de la lista y sin repetir. $Diff es un
# diff de git (-U0). $Entradas: @{ Rx; Modo; Motivo; Si }, con el Rx sobre el texto de la linea sin su + o -. Modo: 'anadida' (falla si
# alguna linea + casa), 'neto+' (casan mas + que -), 'neto-' (menos) o 'neto0' (distinto). Las cuentas son de todo el diff, no por
# fichero: mover algo de un fichero a otro da 0. Si una entrada lleva Si (un regex), solo cuenta si algun mensaje de $Mensajes lo cumple.
function Get-SonarProhibidas([string]$Diff, $Entradas, [string[]]$Mensajes = @()) {
  $mas = New-Object System.Collections.Generic.List[string]
  $menos = New-Object System.Collections.Generic.List[string]
  foreach ($l in ($Diff -split "`r?`n")) {
    if ($l -match '^\+\+\+ (b/|/dev/null)' -or $l -match '^--- (a/|/dev/null)') { continue }
    if ($l.StartsWith('+')) { $mas.Add($l.Substring(1)) }
    elseif ($l.StartsWith('-')) { $menos.Add($l.Substring(1)) }
  }
  $res = New-Object System.Collections.Generic.List[string]
  foreach ($e in @($Entradas)) {
    if ($null -eq $e -or -not $e.Rx) { continue }
    if ($e.Si) {
      $aplica = $false
      foreach ($m in @($Mensajes)) { if ([regex]::IsMatch("$m", "$($e.Si)", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) { $aplica = $true; break } }
      if (-not $aplica) { continue }
    }
    if ($e.Salvo) {   # lo contrario de Si: un mensaje del lote que casa la deja sin efecto
      $exenta = $false
      foreach ($m in @($Mensajes)) { if ([regex]::IsMatch("$m", "$($e.Salvo)", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) { $exenta = $true; break } }
      if ($exenta) { continue }
    }
    $a = @($mas | Where-Object { [regex]::IsMatch($_, "$($e.Rx)", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) }).Count
    $b = @($menos | Where-Object { [regex]::IsMatch($_, "$($e.Rx)", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) }).Count
    $modo = "$($e.Modo)"
    if (-not $modo) { $modo = 'anadida' }
    $falla = $false
    if ($modo -eq 'anadida') { $falla = ($a -gt 0) }
    elseif ($modo -eq 'neto+') { $falla = ($a -gt $b) }
    elseif ($modo -eq 'neto-') { $falla = ($a -lt $b) }
    elseif ($modo -eq 'neto0') { $falla = ($a -ne $b) }
    if ($falla -and -not $res.Contains("$($e.Motivo)")) { $res.Add("$($e.Motivo)") }
  }
  return $res.ToArray()
}

# ----- lo que cuelga del repo -----
# La base de las incidencias (.rescate/sonar-base.json): el hash del xlsx y, por cada incidencia, su fichero (el de verdad, tras buscar un
# fichero movido), su linea, su unidad normalizada (Get-SonarUnidad) y, si el modelo la dejo con motivo, 'dejada'. Se rehace cuando
# el xlsx es otro (otro hash); con el mismo, se conserva: lo resuelto lo dice el codigo de ahora frente a la unidad de entonces.
# $script:SonarFilas son las incidencias que se arreglan (filtradas); $script:SonarPorFila, por su numero de fila; $script:SonarHash,
# el SHA256 del xlsx; $script:SonarBase (fila -> entrada), la base en memoria ($null = hay que leerla del disco).

# El fichero de una incidencia: su Path si existe; si no (se movio), el unico fichero de src/main/java o src/test/java con el nombre
# de su Resource. '' si no hay o hay varios.
function Find-SonarFichero($Fila) {
  $rel = (("$($Fila.Ruta)" -replace '\\', '/') -replace '^\./', '').TrimStart('/')
  if ($rel -and (Test-Path -LiteralPath (Join-Ruta $RepoRoot $rel) -PathType Leaf)) { return $rel }
  $nombre = "$($Fila.Recurso)".Trim()
  if (-not $nombre) { $nombre = $rel.Split('/')[-1] }
  if (-not $nombre) { return '' }
  $esta = @()
  foreach ($sub in @('src/main/java', 'src/test/java')) { $esta += @(Get-JavaFiles (Join-Ruta $RepoRoot $sub) | Where-Object { $_.Name -eq $nombre }) }
  if ($esta.Count -eq 1) { return (Get-Rel $RepoRoot $esta[0].FullName) }
  return ''
}

function Save-SonarBase {
  $json = ConvertTo-Json -InputObject ([pscustomobject]@{ hash = $script:SonarHash; incidencias = @($script:SonarBase.Values) }) -Depth 5
  [System.IO.File]::WriteAllText((Join-Path $Work 'sonar-base.json'), $json)
}

function Initialize-SonarBase {
  if ($null -ne $script:SonarBase) { return }
  $ruta = Join-Path $Work 'sonar-base.json'
  $base = $null
  if (Test-Path -LiteralPath $ruta) {
    try { $b = [System.IO.File]::ReadAllText($ruta) | ConvertFrom-Json } catch { $b = $null }
    if ($b -and "$($b.hash)" -ceq $script:SonarHash) {
      $base = [ordered]@{}
      foreach ($x in @($b.incidencias)) { $base["$($x.fila)"] = $x }
    }
    else {
      # otro xlsx: la base de antes no se pierde (quien compare dos pasadas la necesita), pasa a sonar-base-anterior.json y machaca la anterior
      Move-Item -LiteralPath $ruta -Destination (Join-Path $Work 'sonar-base-anterior.json') -Force
    }
  }
  $rehecha = ($null -eq $base)
  if ($rehecha) { $base = [ordered]@{} }
  # las incidencias que la base no tiene (la primera vez, o si ha cambiado el filtro) salen de los ficheros de ahora
  $nuevas = New-Object System.Collections.Generic.List[object]
  foreach ($f in $script:SonarFilas) {
    if ($base.Contains("$($f.Fila)")) { continue }
    $d = Find-SonarFichero $f
    $u = ''; $sd = $false
    if ($d) {
      $un = Get-SonarUnidad ([System.IO.File]::ReadAllText((Join-Ruta $RepoRoot $d))) $f.Linea
      $u = $un.Unidad; $sd = $un.SinDoc
    }
    $e = [pscustomobject]@{ fila = $f.Fila; fichero = $d; linea = $f.Linea; mensaje = $f.Mensaje; tipo = $f.Tipo; severidad = $f.Severidad; unidad = $u; sinDoc = $sd; indice = 0; resuelta = $false; regla = ''; commit = '' }
    $base["$($f.Fila)"] = $e
    $nuevas.Add($e)
  }
  # la misma unidad en varias lineas de un fichero: cada linea lleva su orden (0, 1, ...) para no dar por vistas todas con una sola
  # que quede; las incidencias de una misma linea comparten orden
  $orden = @{}
  foreach ($x in $base.Values) {
    if ($nuevas.Contains($x)) { continue }
    $k = "$($x.fichero)|$($x.unidad)"
    if (-not $orden.ContainsKey($k)) { $orden[$k] = @{} }
    $orden[$k]["$($x.linea)"] = [int]$x.indice
  }
  foreach ($x in @($nuevas | Sort-Object linea, fila)) {
    $k = "$($x.fichero)|$($x.unidad)"
    if (-not $orden.ContainsKey($k)) { $orden[$k] = @{} }
    if (-not $orden[$k].ContainsKey("$($x.linea)")) { $orden[$k]["$($x.linea)"] = $orden[$k].Count }
    $x.indice = $orden[$k]["$($x.linea)"]
  }
  $script:SonarBase = $base
  if ($rehecha -or $nuevas.Count -gt 0) { Save-SonarBase }
}

# El motivo de la primera entrada de SonarNoAutomatizar cuyo Rx casa con el mensaje; '' si ninguna.
function Get-SonarNoAutomatizar([string]$Mensaje) {
  foreach ($x in @($Cfg.SonarNoAutomatizar)) {
    if ($null -eq $x -or -not $x.Rx) { continue }
    if ([regex]::IsMatch($Mensaje, "$($x.Rx)", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
      $m = "$($x.Motivo)"
      if (-not $m) { $m = 'sin motivo' }
      return $m
    }
  }
  return ''
}

# Las recetas de SonarRecetas cuyo Rx casa con el mensaje.
function Get-SonarRecetasDe([string]$Mensaje) {
  foreach ($r in @($Cfg.SonarRecetas)) {
    if ($null -ne $r -and $r.Rx -and [regex]::IsMatch($Mensaje, "$($r.Rx)", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) { $r }
  }
}

# Un campo de un .tsv: los tabuladores y los saltos de linea pasan a un espacio y, con $Max > 0, se corta a $Max caracteres.
function Get-CampoTsv([string]$Texto, [int]$Max = 0) {
  $t = ($Texto -replace '[\t\r\n]+', ' ').Trim()
  if ($Max -gt 0 -and $t.Length -gt $Max) { $t = $t.Substring(0, $Max) }
  return $t
}

# La familia de un mensaje de Sonar (el xlsx no trae la clave de la regla): con receta, su Nombre o, si no lo lleva, 'receta-N' con N su lugar en
# SonarRecetas (el '# N.' de sonar-reglas.ps1); sin receta, el mensaje con lo que va entre comillas y las cifras cambiados por #, cortado a 80.
# Devuelve Familia y Receta (si la tiene). Es la clave de la tabla por familia y de la columna reglas de intentos.tsv.
function Get-SonarFamilia([string]$Mensaje) {
  $rs = @(Get-SonarRecetasDe $Mensaje)
  if ($rs.Count -gt 0) {
    $nombre = "$($rs[0].Nombre)"
    if (-not $nombre) { $nombre = 'receta-' + ([array]::IndexOf(@($Cfg.SonarRecetas), $rs[0]) + 1) }
    return [pscustomobject]@{ Familia = $nombre; Receta = $true }
  }
  $t = ([regex]::Replace($Mensaje, '"[^"]*"|''[^'']*''|\d+', '#') -replace '\s+', ' ').Trim()
  if ($t.Length -gt 80) { $t = $t.Substring(0, 80) }
  return [pscustomobject]@{ Familia = $t; Receta = $false }
}

# Al empezar el paso sonar: las incidencias pendientes ($Pend, hallazgos con su Fila) por familia, de mas a menos, en .rescate/sonar-por-familia.tsv
# (familia, incidencias, ficheros, receta); en la consola, las 10 primeras y una linea con el total y la ruta. Si no puede escribir, avisa y sigue.
function Write-SonarPorFamilia($Pend) {
  $filas = @($Pend | ForEach-Object {
      $f = Get-SonarFamilia "$($script:SonarPorFila[$_.Fila].Mensaje)"
      [pscustomobject]@{ Familia = $f.Familia; Receta = $f.Receta; Fichero = $_.Fichero }
    })
  $grupos = @($filas | Group-Object -Property Familia | ForEach-Object {
      [pscustomobject]@{ Familia = $_.Name; Incidencias = $_.Count; Ficheros = @($_.Group | ForEach-Object { $_.Fichero } | Select-Object -Unique).Count; Receta = $(if ($_.Group[0].Receta) { 'si' } else { 'no' }) }
    } | Sort-Object @{ Expression = 'Incidencias'; Descending = $true }, 'Familia')
  $txt = @("familia`tincidencias`tficheros`treceta") + @($grupos | ForEach-Object { (Get-CampoTsv $_.Familia) + "`t$($_.Incidencias)`t$($_.Ficheros)`t$($_.Receta)" })
  try { [System.IO.File]::WriteAllText((Join-Path $Work 'sonar-por-familia.tsv'), (($txt -join "`n") + "`n"), $Utf8) }
  catch { Aviso "No he podido escribir .rescate/sonar-por-familia.tsv ($($_.Exception.Message)): sigo sin la tabla." }
  $fmt = '  {0,6} {1,5} {2,-6} {3}'
  Info 'Incidencias pendientes de sonar por familia (las 10 primeras):'
  Info ($fmt -f 'inc.', 'fich.', 'receta', 'familia')
  foreach ($g in @($grupos | Select-Object -First 10)) { Info ($fmt -f $g.Incidencias, $g.Ficheros, $g.Receta, $g.Familia) }
  Info "Total: $(@($Pend).Count) incidencias en $($grupos.Count) familias (detalle: .rescate/sonar-por-familia.tsv)"
}

# Tras el commit de un lote: apunta en la base cada incidencia que el codigo de ahora da por resuelta y que aun no constaba, con la regla (el Rx de la
# receta que le tocaba, o vacio si no tenia) y el commit del lote. Es lo que conserva sonar-base-anterior.json.
function Set-SonarResueltas([string]$Commit) {
  foreach ($x in @(Get-SonarEstado)) {
    if ($x.Estado -ne 'resuelta') { continue }
    $b = $script:SonarBase["$($x.Fila)"]
    if ($b.resuelta -eq $true) { continue }
    $regla = ''
    $rs = @(Get-SonarRecetasDe "$($x.Mensaje)")
    if ($rs.Count -gt 0) { $regla = "$($rs[0].Rx)" }
    Add-Member -InputObject $b -NotePropertyName resuelta -NotePropertyValue $true -Force
    Add-Member -InputObject $b -NotePropertyName regla -NotePropertyValue $regla -Force
    Add-Member -InputObject $b -NotePropertyName commit -NotePropertyValue $Commit -Force
  }
}

# El estado de cada incidencia que se arregla, segun el codigo de ahora: Estado = resuelta (su unidad ya no esta en el fichero, o el
# fichero ya no existe), pendiente, dejada (el modelo la dejo con motivo), noauto (SonarNoAutomatizar) o sinfichero (no se encontro).
function Get-SonarEstado {
  Initialize-SonarBase
  $normales = @{}
  $res = New-Object System.Collections.Generic.List[object]
  foreach ($f in $script:SonarFilas) {
    $b = $script:SonarBase["$($f.Fila)"]
    $estado = 'pendiente'
    $motivo = ''
    if (-not $b.fichero) { $estado = 'sinfichero' }
    else {
      $ruta = Join-Ruta $RepoRoot $b.fichero
      if (-not (Test-Path -LiteralPath $ruta -PathType Leaf)) { $estado = 'resuelta' }
      else {
        if (-not $normales.ContainsKey($b.fichero)) { $normales[$b.fichero] = Get-SonarNormal ([System.IO.File]::ReadAllText($ruta)) }
        if (-not (Test-SonarSigueAhi "$($b.unidad)" ([bool]$b.sinDoc) $normales[$b.fichero] ([int]$b.indice))) { $estado = 'resuelta' }
      }
    }
    if ($estado -eq 'pendiente') {
      $no = Get-SonarNoAutomatizar $f.Mensaje
      if ($b.dejada) { $estado = 'dejada'; $motivo = "$($b.dejada)" }
      elseif ($no) { $estado = 'noauto'; $motivo = $no }
    }
    $res.Add([pscustomobject]@{ Fila = $f.Fila; Fichero = "$($b.fichero)"; Linea = [int]$b.linea; Ruta = $f.Ruta; Mensaje = $f.Mensaje; Tipo = $f.Tipo; Sev = $f.Severidad; Estado = $estado; Motivo = $motivo })
  }
  return $res.ToArray()
}

# 'ruta:linea - mensaje [TIPO SEV]' de una incidencia (la ruta del xlsx si no se encontro el fichero).
function Get-SonarLineaItem($x) {
  $donde = $x.Fichero
  if (-not $donde) { $donde = $x.Ruta }
  if ($x.Linea -gt 0) { $donde += ':' + $x.Linea }
  return "$donde - $($x.Mensaje) [$($x.Tipo) $($x.Sev)]"
}

# La seccion de Sonar del diagnostico: un error por cada incidencia pendiente y un aviso por las que no se arreglan (dejadas por el modelo,
# no automatizables, sin fichero).
function Add-SonarHallazgos {
  foreach ($x in @(Get-SonarEstado)) {
    $d = "$($x.Mensaje) [$($x.Tipo) $($x.Sev)]"
    $sev = 'aviso'
    $fich = $x.Fichero
    if ($x.Estado -eq 'resuelta') { continue }
    elseif ($x.Estado -eq 'pendiente') { $sev = 'error' }
    elseif ($x.Estado -eq 'dejada') { $d = "dejada por el modelo: $($x.Motivo) - $d" }
    elseif ($x.Estado -eq 'noauto') { $d = "no se automatiza: $($x.Motivo) - $d" }
    else { $fich = $x.Ruta; $d = "no encuentro el fichero $($x.Ruta) - $d" }
    Add-Hallazgo 'sonar' $sev $fich $x.Linea $d
    Add-Member -InputObject $script:H[$script:H.Count - 1] -NotePropertyName Fila -NotePropertyValue $x.Fila
  }
}

# Cuantas incidencias de este lote ha dejado ya el modelo con motivo.
function Get-SonarDejadas($LoteH) {
  return @($LoteH | Where-Object { $script:SonarBase["$($_.Fila)"].dejada }).Count
}

# Tras una llamada al modelo: lee .rescate/sonar-sin-arreglar.txt ('<ruta>:<linea> | <motivo>' por linea), lo borra y apunta como dejada cada incidencia
# del lote que nombra. Una linea que no casa con ninguna incidencia del lote se ignora.
function Read-SonarSinArreglar($LoteH) {
  $ruta = Join-Path $Work 'sonar-sin-arreglar.txt'
  if (-not (Test-Path -LiteralPath $ruta)) { return }
  $lineas = @([System.IO.File]::ReadAllLines($ruta))
  Remove-Item -LiteralPath $ruta -Force
  Initialize-SonarBase
  foreach ($l in $lineas) {
    $m = [regex]::Match($l, '^\s*(?<f>.+?):(?<n>\d+)\s*\|\s*(?<m>.*?)\s*$')
    if (-not $m.Success) { continue }
    $f = (($m.Groups['f'].Value.Trim() -replace '\\', '/') -replace '^\./', '')
    $n = [int]$m.Groups['n'].Value
    $motivo = $m.Groups['m'].Value
    if (-not $motivo) { $motivo = 'sin motivo' }
    foreach ($x in @($LoteH | Where-Object { $_.Fichero -eq $f -and $_.Linea -eq $n })) {
      Add-Member -InputObject $script:SonarBase["$($x.Fila)"] -NotePropertyName dejada -NotePropertyValue $motivo -Force
    }
  }
}

# Las recetas del lote: por cada receta cuyo Rx casa con algun mensaje, 'RECETA para <ruta>:<linea>, ...:' (las incidencias del lote a las que se aplica)
# y debajo su texto. Una vez por receta.
function Get-SonarTextoRecetas($LoteH) {
  $l = New-Object System.Collections.Generic.List[string]
  foreach ($r in @($Cfg.SonarRecetas)) {
    if ($null -eq $r -or -not $r.Rx) { continue }
    $donde = @($LoteH | Where-Object { [regex]::IsMatch("$($script:SonarPorFila[$_.Fila].Mensaje)", "$($r.Rx)", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) } | ForEach-Object {
        $x = $_.Fichero
        if ($_.Linea -gt 0) { $x += ':' + $_.Linea }
        $x })
    if ($donde.Count -eq 0) { continue }
    $l.Add('RECETA para ' + ($donde -join ', ') + ':')
    $l.Add("$($r.Texto)".TrimEnd())
    $l.Add('')
  }
  return $l.ToArray()
}

# El prompt de un lote de Sonar (primer intento, o el de reparacion si hay CORRECCION). Las incidencias van antes que las recetas.
function New-PromptSonar($LoteH, [string]$Correccion, $Consejo, $Reflexiones) {
  Initialize-SonarBase
  $vivas = @($LoteH | Where-Object { -not $script:SonarBase["$($_.Fila)"].dejada })
  $l = New-Object System.Collections.Generic.List[string]
  $l.Add("# Tarea de Sonar: paso 'sonar'")
  $l.Add('')
  if ($Correccion) {
    $l.Add('Tu intento anterior sigue en el arbol de trabajo. No vuelvas a explorar el repo: arregla solo esto.')
    $l.Add('')
    $l.Add('## CORRECCION: tu intento anterior no paso las comprobaciones')
    $l.Add('Corrige esto sin deshacer lo que estaba bien:')
    $l.Add($Correccion)
    foreach ($x in (Get-TextoReflexiones $Reflexiones $true)) { $l.Add($x) }
    $l.Add('')
  }
  else {
    $l.Add('Trabaja SOLO en el repositorio actual (un proyecto Maven de Java).')
    $l.Add('')
    $l.Add('## Que hay que hacer')
    $l.Add("$($Cfg.SonarPrompt)".TrimEnd())
    $l.Add('')
  }
  $l.Add('## Hallazgos de este lote (resuelve estos y nada mas)')
  foreach ($x in $vivas) {
    $s = $script:SonarPorFila[$x.Fila]
    $l.Add('- ' + (Get-SonarLineaItem ([pscustomobject]@{ Fichero = $x.Fichero; Ruta = $x.Fichero; Linea = $x.Linea; Mensaje = $s.Mensaje; Tipo = $s.Tipo; Sev = $s.Severidad })))
  }
  $l.Add('')
  if ($Consejo) { foreach ($x in (Get-TextoConsejoLote $Consejo)) { $l.Add($x) } }
  $recetas = @(Get-SonarTextoRecetas $vivas)
  if ($recetas.Count -gt 0) {
    $l.Add('## Recetas (siguelas para las incidencias que nombran)')
    foreach ($x in $recetas) { $l.Add($x) }
  }
  $l.Add('## Reglas obligatorias')
  foreach ($x in $TextoReglas) { $l.Add($x) }
  $l.Add('')
  $l.Add('## Al terminar')
  foreach ($x in (Get-TextoAlTerminar (Get-OrdenMaven) 'sonar')) { $l.Add($x) }
  if (-not $Correccion) { foreach ($x in (Get-TextoReflexiones $Reflexiones $false)) { $l.Add($x) } }
  return ($l -join "`n")
}

# Lo que un intento de Sonar no puede hacer, como lista de problemas (cada uno sale como su linea NO PASA):
#  - tocar algo que no sea un .java de src/main/java o src/test/java (crear .java nuevos si vale);
#  - borrar o renombrar nada de src/test;
#  - borrar o renombrar un .java de src/main/java cuyo nombre de clase aparece en un fichero de src/main/resources (se cablea por nombre);
#  - lo que diga SonarProhibido sobre el diff entero del intento (lo cambiado frente a $Check mas los .java nuevos, sus lineas como +).
# $Cambios: las lineas de git status --porcelain del intento.
function Get-SonarProblemas($Cambios, [string]$Check, $LoteH) {
  $p = New-Object System.Collections.Generic.List[string]
  $ajenos = New-Object System.Collections.Generic.List[string]
  $tests = New-Object System.Collections.Generic.List[string]
  $mains = New-Object System.Collections.Generic.List[string]
  $nuevos = New-Object System.Collections.Generic.List[string]
  $carpetas = @{}   # carpetas de los .java que ya existian y el intento ha cambiado
  foreach ($c in @($Cambios)) {
    if ("$c".Length -lt 4) { continue }
    $xy = "$c".Substring(0, 2)
    $rutas = @(("$c".Substring(3) -replace '^"|"$', '') -split ' -> ')
    for ($i = 0; $i -lt $rutas.Count; $i++) {
      $r = $rutas[$i].Trim('"')
      if ($r -match '^\.rescate/') { continue }   # ahi escribe el modelo sonar-sin-arreglar.txt
      # con un renombrado la primera ruta es la de antes (se va) y la segunda la de despues
      $sale = (($xy.Contains('D')) -or ($rutas.Count -gt 1 -and $i -eq 0))
      if ($r -notmatch '^src/(main|test)/java/.+\.java$') { if (-not $ajenos.Contains($r)) { $ajenos.Add($r) }; continue }
      if ($sale -and $r.StartsWith('src/test/')) { $tests.Add($r) }
      elseif ($sale) { $mains.Add($r) }
      if ($xy -eq '??' -or $xy.Contains('A')) { $nuevos.Add($r) } else { $carpetas[$r.Substring(0, $r.LastIndexOf('/'))] = $true }
    }
  }
  if ($ajenos.Count -gt 0) { $p.Add('Has tocado ficheros que no son .java de src/main/java o src/test/java: ' + (($ajenos | Select-Object -First 6) -join ', ') + '. En este paso solo se cambian ficheros .java (crear uno nuevo si vale).') }
  $lejos = @($nuevos | Where-Object { -not $carpetas.ContainsKey($_.Substring(0, $_.LastIndexOf('/'))) })
  if ($lejos.Count -gt 0) { $p.Add('Has creado clases nuevas fuera de la carpeta de las que arreglas: ' + (($lejos | Select-Object -First 6) -join ', ') + ': crea la clase nueva en el mismo paquete que la clase que arreglas.') }
  if ($tests.Count -gt 0) { $p.Add('No se puede borrar ni renombrar nada de src/test: ' + (($tests | Select-Object -First 6) -join ', ') + '. Restauralo.') }
  if ($mains.Count -gt 0) {
    $recursos = @(Get-ChildItem -LiteralPath (Join-Ruta $RepoRoot 'src/main/resources') -Recurse -File -ErrorAction SilentlyContinue)
    foreach ($r in $mains) {
      $clase = [System.IO.Path]::GetFileNameWithoutExtension($r.Split('/')[-1])
      $rx = '\b' + [regex]::Escape($clase) + '\b'
      foreach ($f in $recursos) {
        if ($f.Length -gt 2MB) { continue }
        if ([regex]::IsMatch([System.IO.File]::ReadAllText($f.FullName), $rx)) {
          $p.Add("Has borrado o renombrado $clase.java, pero $clase aparece en $(Get-Rel $RepoRoot $f.FullName): se cablea por nombre y no se puede quitar. Restauralo.")
          break
        }
      }
    }
  }
  $entradas = @($Cfg.SonarProhibido)
  if ($entradas.Count -gt 0) {
    $diff = New-Object System.Collections.Generic.List[string]
    $d = Invoke-Git $RepoRoot @('diff', '--no-color', '-U0', '--no-renames', $Check)
    foreach ($x in @($d.Salida)) { $diff.Add("$x") }
    foreach ($r in $nuevos) {
      $diff.Add("+++ b/$r")
      $t = [System.IO.File]::ReadAllText((Join-Ruta $RepoRoot $r))
      foreach ($x in @($t -split "`r?`n")) { $diff.Add('+' + $x) }
    }
    $mensajes = @($LoteH | ForEach-Object { "$($script:SonarPorFila[$_.Fila].Mensaje)" })
    foreach ($m in @(Get-SonarProhibidas ($diff -join "`n") $entradas $mensajes)) { $p.Add("Cambio no permitido: $m") }
  }
  return $p.ToArray()
}

# Las lineas de la lista de lo que falta de Sonar (la misma para la consola y para .rescate/sonar-faltan.md). $Tope: cuantas incidencias
# por grupo salen (0 = todas).
function Get-SonarLineasFaltan($Estado, [int]$Tope) {
  $atascados = @()
  if ($script:Atascados.ContainsKey('sonar')) { $atascados = @($script:Atascados['sonar']) }
  $faltan = @($Estado | Where-Object { $_.Estado -ne 'resuelta' })
  $grupos = [ordered]@{}
  $orden = @('atascada tras los intentos', 'dejada por el modelo', 'no se automatiza', 'no encuentro el fichero', 'sin intentar (el pase paro antes de llegar)')
  foreach ($x in $faltan) {
    if ($x.Estado -eq 'pendiente' -and ($atascados -contains $x.Fichero)) { $g = 'atascada tras los intentos' }
    elseif ($x.Estado -eq 'pendiente') { $g = 'sin intentar (el pase paro antes de llegar)' }
    elseif ($x.Estado -eq 'dejada') { $g = 'dejada por el modelo: ' + $x.Motivo }
    elseif ($x.Estado -eq 'noauto') { $g = 'no se automatiza: ' + $x.Motivo }
    else { $g = 'no encuentro el fichero' }
    if (-not $grupos.Contains($g)) { $grupos[$g] = New-Object System.Collections.Generic.List[object] }
    $grupos[$g].Add($x)
  }
  $l = New-Object System.Collections.Generic.List[string]
  if ($faltan.Count -gt 0) {
    $l.Add("Faltan $($faltan.Count) de Sonar:")
    foreach ($base in $orden) {
      foreach ($g in @($grupos.Keys | Where-Object { $_ -eq $base -or $_.StartsWith($base + ':') })) {
        $l.Add("$g ($($grupos[$g].Count)):")
        $n = 0
        foreach ($x in $grupos[$g]) {
          $n++
          if ($Tope -gt 0 -and $n -gt $Tope) { $l.Add("  ... y $($grupos[$g].Count - $Tope) mas (la lista entera esta en .rescate/sonar-faltan.md)"); break }
          $l.Add('  - ' + (Get-SonarLineaItem $x))
        }
      }
    }
  }
  else { $l.Add('Sonar: no falta ninguna de las listadas; la prueba de verdad es volver a pasar Sonar') }
  # arregladas con una receta que cambia el resultado a proposito
  $aviso = @($Estado | Where-Object { $_.Estado -eq 'resuelta' -and @(Get-SonarRecetasDe "$($_.Mensaje)" | Where-Object { $_.Avisar -eq $true -or "$($_.Avisar)" -eq 'true' }).Count -gt 0 })
  if ($aviso.Count -gt 0) {
    $l.Add('')
    $l.Add('Arregladas que cambian el resultado a proposito (revisalas):')
    foreach ($x in $aviso) { $l.Add('  - ' + (Get-SonarLineaItem $x)) }
  }
  # mensajes que no tienen ni receta ni exclusion, contados
  $sin = @($Estado | Where-Object { @(Get-SonarRecetasDe "$($_.Mensaje)").Count -eq 0 -and -not (Get-SonarNoAutomatizar "$($_.Mensaje)") } | Group-Object -Property Mensaje -CaseSensitive | Sort-Object @{ Expression = 'Count'; Descending = $true }, Name)
  if ($sin.Count -gt 0) {
    $l.Add('')
    $l.Add('Mensajes sin receta ni exclusion (para ampliar), con cuantas veces salen:')
    $n = 0
    foreach ($g in $sin) {
      $n++
      if ($Tope -gt 0 -and $n -gt $Tope) { $l.Add("  ... y $($sin.Count - $Tope) mas (la lista entera esta en .rescate/sonar-faltan.md)"); break }
      $l.Add("  - $($g.Count) x $($g.Name)")
    }
  }
  return $l.ToArray()
}

# Al acabar el paso sonar: lo que falta, agrupado por motivo, en la consola y en .rescate/sonar-faltan.md, y lo que se ha arreglado a proposito
# de otra forma que merece una mirada.
function Write-SonarFaltan {
  $estado = @(Get-SonarEstado)
  $ruta = Join-Path $Work 'sonar-faltan.md'
  [System.IO.File]::WriteAllText($ruta, ((@('# Sonar: lo que falta', '') + @(Get-SonarLineasFaltan $estado 0)) -join "`n") + "`n")
  Info ''
  foreach ($x in @(Get-SonarLineasFaltan $estado 30)) {
    if ($x -match '^Faltan ') { Aviso $x } elseif ($x -match '^Sonar: no falta') { Bien $x } else { Info $x }
  }
  Info ('Lista de Sonar: ' + $ruta)
}

# =============================== COBERTURA ===============================
# El paso 'cobertura' (-Cobertura) escribe tests, una clase por lote, hasta que la cobertura de lineas llega a $Cfg.CoberturaMinima. La medida
# es Get-Cobertura (comun.ps1, JaCoCo por coordenadas, sin tocar el pom); $script:Cob guarda la ultima (con sinCubrir: fichero -> lineas sin
# cubrir, del jacoco.xml). Solo se mide en el paso cobertura (o en el diagnostico con -Cobertura): $script:MedirCobertura.

# Un porcentaje para el texto: un decimal como mucho y coma.
function Format-Pct([double]$V) { return ("$([math]::Round($V, 1, [System.MidpointRounding]::AwayFromZero))").Replace('.', ',') }

# Las lineas sin cubrir de cada fuente segun target/site/jacoco/jacoco.xml: fichero ('src/main/java/...') -> numeros de linea. Vacio si no hay XML.
function Get-CoberturaSinCubrir([string]$Dir) {
  $res = @{}
  $ruta = Join-Ruta $Dir 'target/site/jacoco/jacoco.xml'
  if (-not (Test-Path -LiteralPath $ruta)) { return $res }
  $doc = New-Object System.Xml.XmlDocument
  try {
    $ajustes = New-Object System.Xml.XmlReaderSettings
    $ajustes.DtdProcessing = [System.Xml.DtdProcessing]::Ignore   # el XML de JaCoCo declara un DTD (report.dtd) que no esta a mano
    $ajustes.XmlResolver = $null
    $lector = [System.Xml.XmlReader]::Create($ruta, $ajustes)
    try { $doc.Load($lector) } finally { $lector.Close() }
  }
  catch { return $res }
  foreach ($p in @($doc.SelectNodes('//package'))) {
    foreach ($sf in @($p.SelectNodes('sourcefile'))) {
      $l = New-Object System.Collections.Generic.List[int]
      foreach ($ln in @($sf.SelectNodes('line'))) {
        if ([int]$ln.GetAttribute('ci') -eq 0 -and [int]$ln.GetAttribute('mi') -gt 0) { $l.Add([int]$ln.GetAttribute('nr')) }
      }
      $res['src/main/java/' + $p.GetAttribute('name') + '/' + $sf.GetAttribute('name')] = $l.ToArray()
    }
  }
  return $res
}

# Los numeros de linea como rangos: 3, 5, 6, 7, 10 -> '3, 5-7, 10'.
function Get-RangosLineas([int[]]$Lineas) {
  $l = @($Lineas | Sort-Object -Unique)
  $out = New-Object System.Collections.Generic.List[string]
  $i = 0
  while ($i -lt $l.Count) {
    $j = $i
    while ($j + 1 -lt $l.Count -and $l[$j + 1] -eq $l[$j] + 1) { $j++ }
    if ($j -gt $i) { $out.Add("$($l[$i])-$($l[$j])") } else { $out.Add("$($l[$i])") }
    $i = $j + 1
  }
  return ($out -join ', ')
}

# Mide la cobertura del arbol de trabajo (los tests tienen que pasar): Get-Cobertura con las filas por clase y, si midio, las lineas sin cubrir.
function Measure-Cobertura {
  $previos = @(Get-Cambios $RepoRoot)
  $c = Invoke-ContandoMaven { Get-Cobertura $RepoRoot (Join-Path $Work 'cobertura.log') $true $true }
  [void](Remove-Ruido $RepoRoot $previos)   # lo que deja Maven fuera de target no entra en los commits
  $c['sinCubrir'] = @{}
  if ($c.medida) { $c['sinCubrir'] = Get-CoberturaSinCubrir $RepoRoot }
  return $c
}

# Un record sin ningun metodo (solo componentes, y como mucho un constructor compacto): no tiene comportamiento que probar.
function Test-RecordSinMetodos([string]$Texto) {
  $l = Get-Limpio $Texto
  $m = [regex]::Match($l, '(?m)^\s*(?:(?:public|protected|private|static|final|sealed|strictfp)\s+)*record\s+\w+\s*(?:<[^>]*>)?\s*\(')
  if (-not $m.Success) { return $false }
  $prof = 1
  $i = $m.Index + $m.Length
  while ($i -lt $l.Length -and $prof -gt 0) {
    if ($l[$i] -eq '(') { $prof++ } elseif ($l[$i] -eq ')') { $prof-- }
    $i++
  }
  $cuerpo = $l.Substring($i)
  $llave = $cuerpo.IndexOf('{')
  if ($llave -lt 0) { return $true }
  return (-not [regex]::IsMatch($cuerpo.Substring($llave), '\)\s*(?:throws\s+[\w.,\s]+)?\{'))
}

# Una clase de CoberturaExcluir? $Rel: su ruta relativa (src/main/java/...).
function Test-CoberturaExcluida([string]$Rel) {
  $texto = $null
  foreach ($x in @($Cfg.CoberturaExcluir | ForEach-Object { "$_" } | Where-Object { $_ })) {
    if ($x -ceq 'records-sin-metodos' -or $x.StartsWith('texto:')) {
      if ($null -eq $texto) {
        $texto = ''
        $p = Join-Ruta $RepoRoot $Rel
        if (Test-Path -LiteralPath $p -PathType Leaf) { $texto = [System.IO.File]::ReadAllText($p) }
      }
      if ($x -ceq 'records-sin-metodos') { if (Test-RecordSinMetodos $texto) { return $true } }
      elseif ([regex]::IsMatch($texto, $x.Substring(6))) { return $true }
    }
    elseif ([regex]::IsMatch($Rel, $x, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) { return $true }
  }
  return $false
}

# La seccion de cobertura del diagnostico. Con $PuedeMedir (hay Maven con tests) y en el paso cobertura, mide; si no, usa la ultima medida.
# Hallazgos: ninguno si el total llega al objetivo; si no, un error por fuente con lineas sin cubrir (sumando sus clases internas), de las que
# mas faltan a las que menos, sin las excluidas. Sin medida, un aviso con el motivo. $script:CobExcluidas: las excluidas que tenian lineas sin cubrir.
function Add-CoberturaHallazgos([bool]$PuedeMedir) {
  $script:CobFresca = $false
  if ($PuedeMedir -and $script:MedirCobertura -and $script:Build.Compila -and $script:Build.TestsOk) {
    $script:Cob = Measure-Cobertura
    $script:CobFresca = $true
    $script:CobCommit = Get-Head $RepoRoot
  }
  $c = $script:Cob
  $script:CobExcluidas = @()
  if (-not $c) { return }
  if (-not $c.medida) { Add-Hallazgo 'cobertura' 'aviso' '' 0 "no se ha podido medir la cobertura: $($c.motivo)"; return }
  $filas = New-Object System.Collections.Generic.List[object]
  $excluidas = New-Object System.Collections.Generic.List[string]
  foreach ($g in @($c.clases | Where-Object { $_.Fichero } | Group-Object -Property Fichero)) {
    $faltan = [long](($g.Group | Measure-Object -Property Faltan -Sum).Sum)
    $cubiertas = [long](($g.Group | Measure-Object -Property Cubiertas -Sum).Sum)
    if ($faltan -le 0) { continue }
    if (Test-CoberturaExcluida $g.Name) { $excluidas.Add($g.Name); continue }
    $filas.Add([pscustomobject]@{ Fichero = $g.Name; Faltan = $faltan; Cubiertas = $cubiertas })
  }
  $script:CobExcluidas = @($excluidas | Sort-Object)
  if ($c.porcentaje -ge [double]$Cfg.CoberturaMinima) { return }
  foreach ($f in @($filas | Sort-Object @{ Expression = 'Faltan'; Descending = $true }, Fichero)) {
    $total = $f.Faltan + $f.Cubiertas
    Add-Hallazgo 'cobertura' 'error' $f.Fichero 0 ("$($f.Cubiertas)/$total lineas (" + (Format-Pct (100.0 * $f.Cubiertas / $total)) + ' %)')
  }
}

# Cubiertas y total de lineas de una fuente segun la medida $Cob (sumando sus clases internas); $null si no esta o no hay medida.
function Get-CoberturaDeFichero($Cob, [string]$Fichero) {
  if (-not $Cob -or -not $Cob.medida) { return $null }
  $f = @($Cob.clases | Where-Object { $_.Fichero -eq $Fichero })
  if ($f.Count -eq 0) { return $null }
  $cub = [long](($f | Measure-Object -Property Cubiertas -Sum).Sum)
  $falt = [long](($f | Measure-Object -Property Faltan -Sum).Sum)
  return [pscustomobject]@{ Cubiertas = $cub; Total = $cub + $falt }
}

# Los metodos de test (@Test, @ParameterizedTest, @RepeatedTest, @TestFactory) de un texto: nombre -> cuerpo, sin comentarios ni literales.
function Get-MetodosTest([string]$Texto) {
  $l = (Get-Limpio $Texto).Replace("`r", '')
  $res = [ordered]@{}
  foreach ($m in [regex]::Matches($l, '@(?:Test|ParameterizedTest|RepeatedTest|TestFactory)\b')) {
    $ini0 = $m.Index + $m.Length
    $s = [regex]::Match($l.Substring($ini0), '(\w+)\s*\([^)]*\)\s*(?:throws\s+[\w.,\s]+)?\{')
    if (-not $s.Success) { continue }
    $ini = $ini0 + $s.Index + $s.Length   # justo despues de la llave
    $prof = 1
    $i = $ini
    while ($i -lt $l.Length -and $prof -gt 0) {
      if ($l[$i] -eq '{') { $prof++ } elseif ($l[$i] -eq '}') { $prof-- }
      $i++
    }
    $clave = $s.Groups[1].Value
    $k = 2
    while ($res.Contains($clave)) { $clave = $s.Groups[1].Value + '#' + $k; $k++ }
    $res[$clave] = $l.Substring($ini, [math]::Max(0, $i - $ini - 1))
  }
  return $res
}

# Los tests nuevos o cambiados (frente a $Viejo) sin una asercion de verdad: @{ Nombre; Vacio } (Vacio: solo hay assertTrue(true) y parecidos).
function Get-TestsSinAsercion([string]$Nuevo, [string]$Viejo) {
  $antes = Get-MetodosTest $Viejo
  $out = @()
  $rxAsercion = '\b(?:assert\w*|verify\w*|fail)\s*\(|\.\s*should\w*\s*\('
  $rxVacia = '\bassertTrue\s*\(\s*true\s*[,)]|\bassertFalse\s*\(\s*false\s*[,)]'
  $ahora = Get-MetodosTest $Nuevo
  foreach ($k in @($ahora.Keys)) {
    $cuerpo = $ahora[$k]
    if ($antes.Contains($k) -and $antes[$k] -ceq $cuerpo) { continue }
    $nombre = ($k -replace '#\d+$', '')
    if (-not [regex]::IsMatch($cuerpo, $rxAsercion)) { $out += [pscustomobject]@{ Nombre = $nombre; Vacio = $false } }
    elseif (-not [regex]::IsMatch([regex]::Replace($cuerpo, $rxVacia, ''), $rxAsercion)) { $out += [pscustomobject]@{ Nombre = $nombre; Vacio = $true } }
  }
  return $out
}

# Lo que un intento de cobertura no puede hacer sin Maven, como lista de problemas (cada uno sale como su linea NO PASA):
#  (P1) tocar algo que no sea de src/test/ (src/main, el pom...): la logica de negocio no cambia;
#       no escribir <Clase>Test.java, que es el que se repite en P2;
#  (P4) un test nuevo sin asercion de verdad, o con @Disabled/@Ignore, Thread.sleep o un catch vacio anadidos.
# $Tocados: las rutas del git status del intento; $Check: el commit bueno; $LoteH: el hallazgo (la clase) del lote.
function Get-CoberturaProblemas([string[]]$Tocados, [string]$Check, $LoteH) {
  $p = New-Object System.Collections.Generic.List[string]
  $fuera = @($Tocados | Where-Object { -not $_.StartsWith('src/test/') })
  if ($fuera.Count -gt 0) { $p.Add('Has tocado ficheros que no son de src/test/: ' + (($fuera | Select-Object -First 8) -join ', ') + '. Este paso solo escribe tests: la logica de negocio no se toca. Deshaz esos cambios.') }
  $clase = [System.IO.Path]::GetFileNameWithoutExtension("$(@($LoteH)[0].Fichero)")
  if (@($Tocados | Where-Object { $_ -match ('(^|/)' + [regex]::Escape($clase) + 'Test\.java$') }).Count -eq 0) {
    $p.Add("No has escrito ${clase}Test.java: escribe o amplia src/test/java/<mismo paquete>/${clase}Test.java.")
  }
  $rxDes = '@(?:[\w.]+\.)?(?:Disabled|Ignore)\b'
  $rxSleep = '\.\s*sleep\s*\('
  $rxCatch = '\bcatch\s*\([^)]*\)\s*\{\s*(?:/\*C\*/\s*)*\}'
  foreach ($t in @($Tocados | Where-Object { $_.StartsWith('src/test/') -and $_.EndsWith('.java') })) {
    $ruta = Join-Ruta $RepoRoot $t
    if (-not (Test-Path -LiteralPath $ruta -PathType Leaf)) { continue }
    $nuevo = [System.IO.File]::ReadAllText($ruta)
    $viejo = ''
    $r = Invoke-Git $RepoRoot @('show', "${Check}:$t")
    if ($r.Codigo -eq 0) { $viejo = ($r.Salida -join "`n") }
    $ln = Get-Limpio $nuevo
    $lv = Get-Limpio $viejo
    foreach ($x in @(Get-TestsSinAsercion $nuevo $viejo)) {
      if ($x.Vacio) { $p.Add("El test $($x.Nombre) ($t) no tiene ninguna asercion de verdad: assertTrue(true) no prueba nada. Comprueba un valor concreto con assertEquals, assertThrows, assertThat o verify.") }
      else { $p.Add("El test $($x.Nombre) ($t) no tiene ninguna asercion (assert*, verify, assertThrows, assertThat...). Comprueba un valor concreto.") }
    }
    if ([regex]::Matches($ln, $rxDes).Count -gt [regex]::Matches($lv, $rxDes).Count) { $p.Add("Has anadido un test desactivado (@Disabled o @Ignore) en $t. Quitalo: un test desactivado no cubre nada.") }
    if ([regex]::Matches($ln, $rxSleep).Count -gt [regex]::Matches($lv, $rxSleep).Count) { $p.Add("Has anadido Thread.sleep en $t. Un test no espera tiempo: sincroniza por el resultado.") }
    if ([regex]::Matches($ln, $rxCatch).Count -gt [regex]::Matches($lv, $rxCatch).Count) { $p.Add("Has anadido un catch vacio en $t. Un catch sin cuerpo se traga el fallo: deja que el test falle.") }
  }
  return $p.ToArray()
}

# (P2) Los tests de la clase pasan $Cfg.CoberturaRepeticiones veces seguidas (mvn test -Dtest=<Clase>Test). Devuelve $null si pasan todas o
# @{ Motivo; Detalle } con la primera que falla: un test que a veces falla es inestable y el lote no vale.
function Test-CoberturaRepeticiones([string]$Clase) {
  $n = [int]$Cfg.CoberturaRepeticiones
  $previos = @(Get-Cambios $RepoRoot)
  try {
    for ($k = 1; $k -le $n; $k++) {
      $reg = Join-Path $Work "cobertura-rep-$k.log"
      Info "  Repeticion $k de $n de ${Clase}Test (Maven)..."
      $r = Invoke-ContandoMaven { Invoke-MavenTope $RepoRoot (@($Cfg.MvnTests) + @("-Dtest=${Clase}Test")) "Maven (repeticion $k de $n de ${Clase}Test)" $reg }
      if ($r.Codigo -ne 0 -or $r.Tope) {
        $det = @($r.Salida | Where-Object { $_ -match '\[ERROR\]|FAIL' } | Select-Object -First 6 | ForEach-Object { '  - ' + $_.Trim() })
        $motivo = "Los tests de $Clase son inestables: fallan en la repeticion $k de $n de 'mvn test -Dtest=${Clase}Test' (registro: .rescate/cobertura-rep-$k.log). Quita lo que dependa del orden, del reloj, de la red o del azar."
        return [pscustomobject]@{ Motivo = $motivo; Detalle = $det }
      }
    }
  }
  finally { [void](Remove-Ruido $RepoRoot $previos) }
  return $null
}

# Prompt de un lote de cobertura: una clase. Con $Correccion es el de reparacion (el intento anterior sigue en el arbol; la clase no se repite).
function New-PromptCobertura($LoteH, [string]$Correccion, $Consejo, $Reflexiones) {
  $h = @($LoteH)[0]
  $fichero = "$($h.Fichero)"
  $clase = [System.IO.Path]::GetFileNameWithoutExtension($fichero)
  $rel = $fichero -replace '^src/main/java/', ''
  $dir = ''
  if ($rel.Contains('/')) { $dir = $rel.Substring(0, $rel.LastIndexOf('/')) }
  $rutaTest = 'src/test/java/' + $(if ($dir) { $dir + '/' } else { '' }) + $clase + 'Test.java'
  $sin = ''
  if ($script:Cob -and $script:Cob.sinCubrir -and $script:Cob.sinCubrir.ContainsKey($fichero)) { $sin = Get-RangosLineas ([int[]]@($script:Cob.sinCubrir[$fichero])) }
  $l = New-Object System.Collections.Generic.List[string]
  $l.Add("# Tarea de cobertura: paso 'cobertura'")
  $l.Add('')
  if ($Correccion) {
    $l.Add('Tu intento anterior sigue en el arbol de trabajo. No vuelvas a explorar el repo: arregla solo esto.')
    $l.Add('')
    $l.Add('## CORRECCION: tu intento anterior no paso las comprobaciones')
    $l.Add('Corrige esto sin deshacer lo que estaba bien:')
    $l.Add($Correccion)
    foreach ($x in (Get-TextoReflexiones $Reflexiones $true)) { $l.Add($x) }
    $l.Add('')
  }
  else {
    $l.Add('Trabaja SOLO en el repositorio actual (un proyecto Maven de Java).')
    $l.Add('')
    $l.Add('## Que hay que hacer')
    $l.Add("$($Cfg.CoberturaPrompt)".TrimEnd())
    $l.Add('')
  }
  $l.Add('## Hallazgos de este lote (resuelve estos y nada mas)')
  $l.Add((Get-LineaHallazgo $h))
  if ($sin) { $l.Add("Lineas que JaCoCo da como no cubiertas: $sin") }
  $l.Add("Tu test: $rutaTest")
  $l.Add('')
  if ($Consejo) { foreach ($x in (Get-TextoConsejoLote $Consejo)) { $l.Add($x) } }
  if (-not $Correccion) {
    $l.Add("## La clase ($fichero)")
    $l.Add('```java')
    $l.Add(([System.IO.File]::ReadAllText((Join-Ruta $RepoRoot $fichero))).TrimEnd())
    $l.Add('```')
    $l.Add('')
    $pt = Join-Ruta $RepoRoot $rutaTest
    if (Test-Path -LiteralPath $pt -PathType Leaf) {
      $l.Add("## Su test, que ya existe ($rutaTest): amplialo, no lo reescribas")
      $l.Add('```java')
      $l.Add(([System.IO.File]::ReadAllText($pt)).TrimEnd())
      $l.Add('```')
    }
    else { $l.Add("## Su test no existe todavia: crea $rutaTest") }
    $l.Add('')
  }
  $l.Add('## Reglas obligatorias')
  foreach ($x in $TextoReglas) { $l.Add($x) }
  $l.Add('')
  $l.Add('## Al terminar')
  foreach ($x in (Get-TextoAlTerminar (Get-OrdenMaven) 'cobertura')) { $l.Add($x) }
  if (-not $Correccion) { foreach ($x in (Get-TextoReflexiones $Reflexiones $false)) { $l.Add($x) } }
  return ($l -join "`n")
}

# Las lineas de 'Faltan estas clases' (una por clase pendiente, con su motivo), las de las excluidas y los // OJO de los tests, como lista de textos.
function Get-CoberturaLineasFaltan([int]$Tope) {
  $l = New-Object System.Collections.Generic.List[string]
  $c = $script:Cob
  $pend = @($script:Hall | Where-Object { $_.Cat -eq 'cobertura' -and $_.Sev -eq 'error' })
  if ($c -and $c.medida -and $c.porcentaje -lt [double]$Cfg.CoberturaMinima) {
    if ($pend.Count -eq 0) { $l.Add('Lo que falta esta en clases que CoberturaExcluir no propone: no hay clase que probar.') }
    else {
      $l.Add("Faltan estas clases ($($pend.Count)):")
      $k = 0
      foreach ($x in $pend) {
        $k++
        if ($Tope -gt 0 -and $k -gt $Tope) { $l.Add("  ... y $($pend.Count - $Tope) mas (todas en .rescate/cobertura-faltan.md)"); break }
        $motivo = 'sin intentar en esta pasada'
        $info = $script:AtascadosInfo["cobertura|$($x.Fichero)"]
        if ($info) { $motivo = "atascada tras los intentos: $($info.motivo)" }
        elseif ($script:CobHechas -contains $x.Fichero) { $motivo = 'probada y mejorada, pero aun le faltan lineas' }
        elseif ($script:CobTope) { $u = [int]$Cfg.CoberturaClasesMax; $motivo = "sin intentar: tope de $u " + $(if ($u -eq 1) { 'clase' } else { 'clases' }) + ' por pasada (CoberturaClasesMax)' }
        $l.Add("  - $($x.Fichero) - $($x.Detalle): $motivo")
      }
    }
  }
  $ex = @($script:CobExcluidas)
  if ($ex.Count -gt 0) {
    $l.Add("No se proponen (CoberturaExcluir): $($ex.Count) " + $(if ($ex.Count -eq 1) { 'clase' } else { 'clases' }) + ' con lineas sin cubrir:')
    foreach ($x in $ex) { $l.Add("  - $x") }
  }
  $ojos = New-Object System.Collections.Generic.List[string]
  foreach ($f in @(Get-JavaFiles (Join-Ruta $RepoRoot 'src/test/java'))) {
    $rel = Get-Rel $RepoRoot $f.FullName
    $n = 0
    foreach ($linea in [System.IO.File]::ReadAllLines($f.FullName)) {
      $n++
      if ($linea -match '//\s*OJO:\s*parece un error') { $ojos.Add("  - ${rel}:$n - " + $linea.Trim()) }
    }
  }
  if ($ojos.Count -gt 0) {
    $l.Add('Comportamientos que parecen un error del codigo (fijados tal cual en el test, a revisar por una persona):')
    foreach ($x in $ojos) { $l.Add($x) }
  }
  return $l.ToArray()
}

# Al acabar el paso cobertura: 'Cobertura: X % -> Y % (objetivo Z %)', lo que falta con su motivo, las excluidas y los // OJO; en la consola y en
# .rescate/cobertura-faltan.md.
function Write-CoberturaFaltan {
  $c = $script:Cob
  $obj = [double]$Cfg.CoberturaMinima
  if (-not $c -or -not $c.medida) {
    $motivo = 'los tests no pasan o el proyecto no compila'
    if ($c) { $motivo = "$($c.motivo)" }
    $cab = "Cobertura: sin medir ($motivo)."
  }
  else {
    $ini = $c.porcentaje
    if ($null -ne $script:CobInicial) { $ini = $script:CobInicial }
    $cab = "Cobertura: $(Format-Pct $ini) % -> $(Format-Pct $c.porcentaje) % (objetivo $(Format-Pct $obj) %)"
  }
  $ruta = Join-Path $Work 'cobertura-faltan.md'
  [System.IO.File]::WriteAllText($ruta, ((@('# Cobertura: lo que falta', '', $cab, '') + @(Get-CoberturaLineasFaltan 0)) -join "`n") + "`n")
  Info ''
  if ($c -and $c.medida -and $c.porcentaje -ge $obj) { Bien $cab } else { Aviso $cab }
  foreach ($x in @(Get-CoberturaLineasFaltan 30)) { if ($x -match '^Faltan ') { Aviso $x } else { Info $x } }
  Info ('Lista de cobertura: ' + $ruta)
}

# ============================== DIAGNOSTICO ==============================
# $Motivo (opcional) va en una propiedad aparte, solo si lo hay: no entra en el detalle ni en la clave del hallazgo (Get-ClaveHallazgo), y un
# hallazgo sin motivo es igual que siempre en hallazgos.json.
function Add-Hallazgo([string]$Cat, [string]$Sev, [string]$Fichero, [int]$Linea, [string]$Detalle, [string]$Motivo = '') {
  $x = [pscustomobject]@{ Cat = $Cat; Sev = $Sev; Fichero = $Fichero; Linea = $Linea; Detalle = $Detalle }
  if ($Motivo) { Add-Member -InputObject $x -NotePropertyName Motivo -NotePropertyValue $Motivo }
  [void]$script:H.Add($x)
}

# El motivo del primer fallo de un informe de surefire: las primeras lineas despues de la '<<< FAILURE!' o '<<< ERROR!' de un metodo (no la de
# resumen de la clase, que empieza por 'Tests run:'), sin las lineas 'at ...' de la pila ni 'Time elapsed'. Hasta 3 lineas y 400 caracteres,
# unidas con ' | '. Vacio si el informe no trae motivo.
function Get-MotivoFallo([string]$Texto) {
  $lineas = @($Texto -split "`r?`n")
  $i = 0
  while ($i -lt $lineas.Count -and -not ($lineas[$i] -match '<<< (FAILURE|ERROR)!' -and $lineas[$i] -notmatch '^\s*Tests run:')) { $i++ }
  $motivo = @()
  for ($j = $i + 1; $j -lt $lineas.Count -and $motivo.Count -lt 3; $j++) {
    $l = $lineas[$j].Trim()
    if ($l -match '<<< (FAILURE|ERROR)!' -or $l -match '^Tests run:') { break }   # el siguiente metodo u otra clase: ya no es el primer fallo
    if (-not $l -or $l -match '^at\s+\S+\(.*\)$' -or $l -match '^\.\.\. \d+ (more|common frames omitted)$' -or $l -match 'Time elapsed') { continue }
    $motivo += $l
  }
  $t = ($motivo -join ' | ')
  if ($t.Length -gt 400) { $t = $t.Substring(0, 400) }
  return $t
}

# Lo que dicen los informes de surefire de $Rep: cuantos tests se ejecutan (los que corren, sin los saltados) y, por cada test que falla, un hallazgo
# 'tests' (el motivo, de Get-MotivoFallo, va aparte). Se lee el TEST-<clase>.xml, con un <testcase> por metodo: 'falla <metodo> en <clase>'. Sin XML
# (o ilegible) se lee el <clase>.txt, que no trae los metodos: 'test <k> de <n> que fallan en <clase>', para que dos hallazgos no tengan la misma
# clave (Get-ClaveHallazgo). Devuelve Ejecutados y Fallan.
function Read-InformesTests([string]$Rep) {
  $ejecutados = 0; $fallan = 0
  $vistas = @{}
  if (-not (Test-Path -LiteralPath $Rep)) { return [pscustomobject]@{ Ejecutados = 0; Fallan = 0 } }
  foreach ($f in @(Get-ChildItem -LiteralPath $Rep -File -Filter 'TEST-*.xml')) {
    $doc = New-Object System.Xml.XmlDocument
    try { $doc.Load($f.FullName) } catch { continue }
    $clase = ([System.IO.Path]::GetFileNameWithoutExtension($f.Name) -replace '^TEST-', '')
    $vistas[$clase] = $true
    $rel = 'src/test/java/' + ($clase -replace '\.', '/') + '.java'
    if (-not (Test-Path -LiteralPath (Join-Ruta $RepoRoot $rel))) { $rel = $clase }
    $rotos = 0; $nombres = @{}
    foreach ($tc in @($doc.SelectNodes('//testcase'))) {
      if ($tc.SelectSingleNode('skipped')) { continue }
      $ejecutados++
      $fallo = $tc.SelectSingleNode('failure | error')
      if (-not $fallo) { continue }
      $nombre = $tc.GetAttribute('name')
      if ($nombres.ContainsKey($nombre)) { $nombres[$nombre]++; $nombre += " ($($nombres[$nombre]))" } else { $nombres[$nombre] = 1 }
      $texto = $fallo.InnerText
      if (-not $texto.Trim()) { $texto = $fallo.GetAttribute('message') }
      Add-Hallazgo 'tests' 'error' $rel 0 "falla $nombre en $clase" (Get-MotivoFallo ("<<< FAILURE!`n" + $texto))
      $rotos++
    }
    # un fallo de la clase entera (sin <testcase> que lo lleve) tambien cuenta
    $total = [int]$doc.DocumentElement.GetAttribute('failures') + [int]$doc.DocumentElement.GetAttribute('errors')
    for ($k = $rotos + 1; $k -le $total; $k++) { Add-Hallazgo 'tests' 'error' $rel 0 "test $k de $total que fallan en $clase" }
    $fallan += [Math]::Max($rotos, $total)
  }
  foreach ($f in @(Get-ChildItem -LiteralPath $Rep -File -Filter '*.txt')) {
    $clase = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
    if ($vistas.ContainsKey($clase)) { continue }
    $t = [System.IO.File]::ReadAllText($f.FullName)
    $m = [regex]::Match($t, 'Tests run:\s*(\d+),\s*Failures:\s*(\d+),\s*Errors:\s*(\d+)(?:,\s*Skipped:\s*(\d+))?')
    if (-not $m.Success) { continue }
    $nf = [int]$m.Groups[2].Value + [int]$m.Groups[3].Value
    $saltados = 0
    if ($m.Groups[4].Success) { $saltados = [int]$m.Groups[4].Value }
    $ejecutados += [int]$m.Groups[1].Value - $saltados
    $rel = 'src/test/java/' + ($clase -replace '\.', '/') + '.java'
    if (-not (Test-Path -LiteralPath (Join-Ruta $RepoRoot $rel))) { $rel = $clase }
    for ($k = 1; $k -le $nf; $k++) {
      $motivo = ''
      if ($k -eq 1) { $motivo = Get-MotivoFallo $t }
      Add-Hallazgo 'tests' 'error' $rel 0 "test $k de $nf que fallan en $clase" $motivo
    }
    $fallan += $nf
  }
  return [pscustomobject]@{ Ejecutados = $ejecutados; Fallan = $fallan }
}

# Corre $Bloque (una llamada de Maven del script) y suma lo que tarda a $script:SegMaven: los segundos de Maven de cada intento en
# .rescate/intentos.tsv. Cada intento pone SegMaven a 0 al empezar.
function Invoke-ContandoMaven([scriptblock]$Bloque) {
  $reloj = [System.Diagnostics.Stopwatch]::StartNew()
  try { return (& $Bloque) }
  finally { $script:SegMaven += $reloj.Elapsed.TotalSeconds }
}

function Invoke-Build([bool]$ConTests) {
  $b = [pscustomobject]@{ Ejecutado = $true; Compila = $true; TestsEjecutados = $false; TestsOk = $false; TestsN = 0 }
  $rep = Join-Ruta $RepoRoot 'target/surefire-reports'
  if ($ConTests -and (Test-Path -LiteralPath $rep)) { Remove-Item -LiteralPath $rep -Recurse -Force }
  if ($ConTests) { $a = @($Cfg.MvnTests) + @($script:TestsExtra | Where-Object { $_ }) } else { $a = $Cfg.MvnCompilar }   # TestsExtra: lo que pide el lote (el excludesFile de los tests de contexto)
  if ($ConTests) { $que = 'Maven (tests)' } else { $que = 'Maven (compilar)' }
  $previos = @(Get-Cambios $RepoRoot)
  $r = Invoke-ContandoMaven { Invoke-MavenTope $RepoRoot $a $que (Join-Path $Work 'build.log') }
  # lo que deja Maven fuera de target se quita (Remove-Ruido, la regla de prueba-local.ps1): no entra en los commits
  $ruido = @(Remove-Ruido $RepoRoot $previos)
  if ($ruido.Count -gt 0 -and -not $script:RuidoDicho) {
    $script:RuidoDicho = $true
    Info ('Maven deja ficheros fuera de target (' + (($ruido | Select-Object -First 3) -join ', ') + '): los quito despues de cada ejecucion, no entran en los commits.')
  }
  # es un build que falla: el detalle entra en la correccion del lote porque casa con ^(no compila|el build falla)
  if ($r.Tope) { $b.Compila = $false; Add-Hallazgo 'build' 'error' 'pom.xml' 0 ('el build falla: ' + $r.Tope); return $b }
  if ($r.Codigo -eq 0) {
    if ($ConTests) {
      # Maven con 0 no dice que los tests pasen (testFailureIgnore, skipTests en la configuracion del plugin): se miran los informes
      $inf = Read-InformesTests $rep
      $b.TestsEjecutados = $true; $b.TestsN = $inf.Ejecutados; $b.TestsOk = ($inf.Fallan -eq 0)
      # con TestsExtra el lote ha dejado fuera tests a proposito (los de contexto): que no ejecute ninguno lo cubre el control, que pasa la suite entera
      if ($inf.Fallan -eq 0 -and $inf.Ejecutados -eq 0 -and @($script:TestsExtra | Where-Object { $_ }).Count -eq 0 -and @(Get-JavaFiles (Join-Ruta $RepoRoot 'src/test/java')).Count -gt 0) {
        $b.TestsOk = $false
        Add-Hallazgo 'tests' 'error' 'pom.xml' 0 'Hay tests en src/test/java, pero Maven no ha ejecutado ninguno: mira skipTests, testFailureIgnore, excludes o el perfil del pom'
      }
    }
    return $b
  }
  # 1) errores de compilacion
  $raiz = ($RepoRoot -replace '\\', '/')
  $porFichero = @{}
  foreach ($l in $r.Salida) {
    if ($l -match '\[ERROR\]\s+(.*?\.java):\[(\d+),\d+\]\s*(.*)$') {
      $ln = [int]$Matches[2]; $msg = $Matches[3]
      $p = (($Matches[1] -replace '\\', '/') -replace '^/([A-Za-z]:/)', '$1')
      if ($p.ToLower().StartsWith($raiz.ToLower() + '/')) { $p = $p.Substring($raiz.Length + 1) }
      if (-not $porFichero.ContainsKey($p)) { $porFichero[$p] = 0 }
      $porFichero[$p]++
      if ($porFichero[$p] -le 3) { Add-Hallazgo 'build' 'error' $p $ln ('no compila: ' + $msg) }
    }
  }
  $texto = ($r.Salida -join "`n")
  if ($porFichero.Count -gt 0 -or $texto -match 'COMPILATION ERROR') {
    $b.Compila = $false
    if ($porFichero.Count -eq 0) { Add-Hallazgo 'build' 'error' 'pom.xml' 0 'no compila (ver .rescate/build.log)' }
    return $b
  }
  # 2) tests que fallan
  $fallan = 0
  if ($ConTests) { $inf = Read-InformesTests $rep; $fallan = $inf.Fallan; $b.TestsN = $inf.Ejecutados }
  if ($fallan -gt 0) { $b.TestsEjecutados = $true; $b.TestsOk = $false; return $b }
  # 3) otra cosa (parent que no resuelve, plugin, etc.)
  $primera = @($r.Salida | Where-Object { $_ -match '\[ERROR\]' } | Select-Object -First 1) -join ''
  $b.Compila = $false
  Add-Hallazgo 'build' 'error' 'pom.xml' 0 ('el build falla y no es compilacion ni tests: ' + $primera)
  return $b
}

function Invoke-Diagnostico([bool]$ConBuild, [bool]$ConTests) {
  $script:H = New-Object System.Collections.Generic.List[object]
  $script:Build = [pscustomobject]@{ Ejecutado = $false; Compila = $true; TestsEjecutados = $false; TestsOk = $false; TestsN = 0 }
  $cal = $script:Cal
  $h = Get-Hechos $RepoRoot
  $script:BasePkg = $h.BasePkg

  # ---------- build ----------
  $pom = Get-Pom $RepoRoot
  if ($null -eq $pom) { Add-Hallazgo 'build' 'error' 'pom.xml' 0 'no hay pom.xml en la raiz' }
  elseif (-not $pom.Valido) { Add-Hallazgo 'build' 'error' 'pom.xml' 0 'pom.xml no es XML valido' }
  else {
    if ($cal -and $cal.Pom -and $cal.Pom.Parent -and ($pom.Parent -ne $cal.Pom.Parent)) {
      # cambiar el parent (p. ej. a otra version mayor de Spring Boot) no es un arreglo mecanico: lo decide el equipo
      Add-Hallazgo 'build' 'aviso' 'pom.xml' 0 "parent distinto al de la plantilla (aqui: '$($pom.Parent)'; plantilla: '$($cal.Pom.Parent)'): decision del equipo: no se cambia solo"
    }
    foreach ($v in $pom.Java) {
      $num = 0
      if ([int]::TryParse(($v -replace '^1\.', ''), [ref]$num) -and $num -lt 21) { Add-Hallazgo 'build' 'error' 'pom.xml' 0 "version de Java '$v' en el pom (objetivo: 21)" }
    }
    if ($cal -and $cal.Pom -and $cal.Pom.Valido) {
      $sobran = @($pom.Deps | Where-Object { $cal.Pom.Deps -notcontains $_ } | Select-Object -Unique)
      $faltan = @($cal.Pom.Deps | Where-Object { $pom.Deps -notcontains $_ } | Select-Object -Unique)
      if ($sobran.Count -gt 0) { Add-Hallazgo 'build' 'aviso' 'pom.xml' 0 ('dependencias que la plantilla no usa: ' + (($sobran | Select-Object -First 12) -join ', ')) }
      if ($faltan.Count -gt 0) { Add-Hallazgo 'build' 'aviso' 'pom.xml' 0 ('dependencias de la plantilla que aqui no estan: ' + (($faltan | Select-Object -First 12) -join ', ')) }
    }
  }
  if ($cal -and $cal.UsaJakarta) {
    foreach ($f in (@($h.Ficheros) + @($h.Tests))) {
      $jx = @($f.Imports | Where-Object { $_.Fqn -match $Cfg.JavaxAntiguo })
      if ($jx.Count -gt 0) { Add-Hallazgo 'build' 'error' $f.RelRaiz $jx[0].Linea ('imports javax que la plantilla ya tiene en jakarta: ' + ((@($jx | ForEach-Object { $_.Fqn }) | Select-Object -First 4) -join ', ')) }
    }
  }
  if ($cal) {
    foreach ($t in $Cfg.ApiAntigua) {
      if ($cal.Tokens[$t]) { continue }
      foreach ($f in $h.Ficheros) { if ($f.Texto -match ('\b' + $t + '\b')) { Add-Hallazgo 'build' 'error' $f.RelRaiz 0 "usa $t, que la plantilla ya no usa" } }
    }
  }
  if ($ConBuild -and $pom -and $pom.Valido) { $script:Build = Invoke-Build $ConTests }

  # ---------- estructura ----------
  if (-not $h.BaseDir) { Add-Hallazgo 'estructura' 'error' 'src/main/java' 0 'no encuentro src/main/java ni el paquete base' }
  if ($cal -and $cal.Capas.Count -gt 0) { $capas = @($Cfg.Capas | Where-Object { $cal.Capas -contains $_ }) + @($cal.Capas | Where-Object { $Cfg.Capas -notcontains $_ }) } else { $capas = $Cfg.Capas }
  foreach ($f in $h.Ficheros) {
    $seg = $f.Rel.Split('/')
    if ($seg.Count -eq 1) {
      if ($f.Texto -notmatch '@SpringBootApplication') { Add-Hallazgo 'estructura' 'error' $f.RelRaiz 0 ('clase suelta en el paquete base: debe ir a una capa (' + ($capas -join ', ') + ')') }
      continue
    }
    if ($capas -notcontains $seg[0]) {
      Add-Hallazgo 'estructura' 'error' $f.RelRaiz 0 ("paquete '" + $seg[0] + "' fuera de las capas (" + ($capas -join ', ') + ')')
      continue
    }
    if ($cal -and $Cfg.SubpaquetesEstrictos -and $seg.Count -ge 3 -and $cal.Sub2.ContainsKey($seg[0]) -and ($cal.Sub2[$seg[0]] -notcontains $seg[1])) {
      Add-Hallazgo 'estructura' 'error' $f.RelRaiz 0 ("subpaquete '" + $seg[0] + '/' + $seg[1] + "' no existe en la plantilla (alli: " + ($cal.Sub2[$seg[0]] -join ', ') + ')')
    }
  }
  if ($cal -and $h.BaseDir) {
    $faltanDirs = @($cal.Dirs3 | Where-Object { -not (Test-Path -LiteralPath (Join-Ruta $h.BaseDir $_)) })
    if ($faltanDirs.Count -gt 0) { Add-Hallazgo 'estructura' 'aviso' '' 0 ('paquetes de la plantilla que aqui no existen: ' + ($faltanDirs -join ', ')) }
  }

  # ---------- hexagonal ----------
  $viol = @(Get-ViolImports $h)
  if ($cal) { $viol = @($viol | Where-Object { -not $cal.ExcImports.ContainsKey($_.Clave) }) }
  foreach ($g in @($viol | Group-Object RelRaiz)) {
    $imps = (@($g.Group | ForEach-Object { $_.Fqn }) | Select-Object -Unique | Select-Object -First 5) -join ', '
    $por = (@($g.Group | ForEach-Object { $_.Por }) | Select-Object -Unique) -join '; '
    Add-Hallazgo 'hexagonal' 'error' $g.Name $g.Group[0].Linea "importa $imps ($por)"
  }
  foreach ($f in $h.Ficheros) {
    if ($f.Rel.StartsWith('application/ports/') -and $f.Texto -notmatch '\binterface\s') { Add-Hallazgo 'hexagonal' 'aviso' $f.RelRaiz 0 'esta en ports pero no es una interfaz' }
  }

  # ---------- ficheros (SFTP) ----------
  $uso = @(Get-UsoFicheros $h)
  $usaFicheros = ($uso.Count -gt 0)   # si el batch no toca ficheros, no se le exige SFTP
  $uso = @($uso | Where-Object { -not ((Test-FicheroPermitido $_.Dir) -or ($cal -and $cal.ExcFicheros.ContainsKey($_.Clave))) })
  foreach ($g in @($uso | Group-Object RelRaiz)) {
    $imps = (@($g.Group | ForEach-Object { $_.Fqn }) | Select-Object -Unique | Select-Object -First 5) -join ', '
    Add-Hallazgo 'ficheros' 'error' $g.Name $g.Group[0].Linea "acceso directo a ficheros locales ($imps): debe ir por el puerto de ficheros, una interfaz de application/ports/output que implementa un adaptador de infrastructure/adapters/output/file o sftp; fuera de esos adaptadores no se abre, lee, escribe, lista ni borra ningun fichero (pasar un Path como dato si vale)"
  }
  if ($usaFicheros -and (@($h.Ficheros | Where-Object { $_.Rel -match '(^|/)sftp/' }).Count -eq 0) -and ($Cfg.ExigirSftp -or ($cal -and $cal.TieneSftp))) {
    if ($cal -and $cal.TieneSftp) { $donde = 'la plantilla lo tiene en infrastructure/adapters/output/sftp' } else { $donde = 'va en infrastructure/adapters/output/sftp' }
    Add-Hallazgo 'ficheros' 'error' '' 0 "no hay adaptador SFTP ($donde)"
  }
  $ymlSinSftp = ($usaFicheros -and ($h.Yml -notmatch 'sftp') -and ($Cfg.ExigirSftp -or ($cal -and $cal.YmlSftp)))
  if ($ymlSinSftp) {
    # la configuracion tambien cuenta si entra por una clase de src/main/java: un @ConfigurationProperties con prefijo sftp
    # o un @Value con una clave sftp (Spring une SFTP_HOST con sftp.host sin tocar el yml). Sin comentarios, con las cadenas.
    $rxSftpJava = '(?i)@ConfigurationProperties\s*\([^)]*"[^"]*sftp|@Value\s*\(\s*"[^"]*\$\{[^}"]*sftp'
    foreach ($f in @($h.Ficheros | Where-Object { $_.Texto -match '(?i)sftp' })) {
      if ((Get-SinComentarios $f.Texto) -match $rxSftpJava) { $ymlSinSftp = $false; break }
    }
  }
  if ($ymlSinSftp) {
    if ($cal -and $cal.SftpYml) {
      $b = $cal.SftpYml
      $textoYml = 'application.yml no tiene configuracion sftp: copia el bloque ''' + $b.Ruta + ''' de la PLANTILLA (' + $b.Rel + ') con sus claves (' + ($b.Claves -join ', ') + '), bajo el prefijo propio de este batch, con valores ${...} como los suyos (salen del configmap); ningun valor real (la plantilla si)'
    }
    else {
      $textoYml = 'application.yml no tiene configuracion sftp: anade un bloque ''sftp:'' (servidor, puerto, usuario, contrasena y rutas) con valores ${...} que salgan de la configuracion externa, como el resto de este application.yml; ningun valor real'
    }
    Add-Hallazgo 'ficheros' 'error' 'src/main/resources' 0 $textoYml
  }

  # ---------- config ----------
  $patron = '(?i)(' + (($Cfg.PalabrasConfigAntigua | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')'
  $restos = @{}
  foreach ($f in @(Get-Arbol $RepoRoot)) {
    $rel = Get-Rel $RepoRoot $f.FullName
    if ($rel -match '(?i)(^|/)inventor(y|ies)') { $restos[($rel.Split('/')[0])] = $true; continue }
    if ($Cfg.ExtTexto -notcontains $f.Extension.ToLower()) { continue }
    if ($f.Length -gt 1MB) { continue }
    $n = 0
    foreach ($l in [System.IO.File]::ReadAllLines($f.FullName)) {
      $n++
      if ($l -match $patron) {
        if ($rel.StartsWith('src/test/')) { $sev = 'aviso' } else { $sev = 'error' }
        Add-Hallazgo 'config' $sev $rel $n ("referencia a la configuracion antigua ('" + $Matches[1] + "')")
        break
      }
    }
  }
  if ($restos.Count -gt 0) { Add-Hallazgo 'config' 'aviso' '' 0 ('siguen en el repo ficheros/carpetas de inventory: ' + (($restos.Keys | Sort-Object) -join ', ') + ' (decide tu si se borran)') }
  foreach ($s in @(Get-SecretosEnClaro $h)) {
    Add-Hallazgo 'config' $s.Sev $s.Rel $s.Linea ("secreto escrito en claro ('" + $s.Clave + "'): tiene que entrar por una variable de entorno, sin valor por defecto")
  }
  $todo = (@($h.Ficheros | ForEach-Object { $_.Texto }) -join "`n")
  if ($cal -and $cal.UsaConfigProps -and ($todo -notmatch '@ConfigurationProperties')) {
    Add-Hallazgo 'config' 'error' '' 0 'no hay ninguna clase @ConfigurationProperties (la plantilla centraliza ahi la configuracion)'
  }
  if ($cal -and -not $cal.UsaValue) {
    foreach ($f in $h.Ficheros) { if ($f.Texto -match '@Value\s*\(') { Add-Hallazgo 'config' 'aviso' $f.RelRaiz 0 'usa @Value; la plantilla no lo usa' } }
  }
  if ($cal) {
    $faltanExtra = @($cal.Extra | Where-Object { -not (Test-Path -LiteralPath (Join-Ruta $RepoRoot $_)) } | Select-Object -First 15)
    if ($faltanExtra.Count -gt 0) { Add-Hallazgo 'config' 'aviso' '' 0 ('ficheros que la plantilla tiene y aqui faltan: ' + ($faltanExtra -join ', ')) }
  }

  # ---------- paridad y e2e (usan el contrato que genera -Modo pre) ----------
  $con = Read-Contrato
  if ($null -eq $con) {
    Add-Hallazgo 'paridad' 'aviso' '' 0 'sin contrato: lanza -Modo pre -Legacy <original> para comprobar que estan todos los jobs y que cada uno tiene prueba de extremo a extremo'
  }
  else {
    $textoMain = (@($h.Ficheros | ForEach-Object { $_.Texto }) -join "`n") + "`n" + (Get-TextoArbol (Join-Ruta $RepoRoot 'src/main/resources'))
    foreach ($j in @($con.jobs)) {
      $n = "$($j.nombre)".Trim()
      if (-not $n) { continue }
      $rx = '(?<![\w])' + [regex]::Escape($n) + '(?![\w])'
      $clave = 'job:' + $n
      if ($textoMain -notmatch $rx) {
        if ("$($j.origen)" -eq 'ia') { $sev = 'aviso' } else { $sev = 'error' }
        Add-Hallazgo 'paridad' $sev $clave 0 "el job '$n' del original no aparece en este repo (en el original: $($j.definidoEn))"
        continue
      }
      $clases = @($h.Ficheros | Where-Object { $_.Texto -match $rx } | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Rel.Split('/')[-1]) })
      $tiene = $false
      foreach ($t in $h.Tests) {
        if ($t.Texto -notmatch $Cfg.LanzaJob -or $t.Texto -notmatch 'COMPLETED') { continue }
        $menciona = ($t.Texto -match $rx)
        foreach ($c in $clases) { if ($t.Texto -match ('\b' + [regex]::Escape($c) + '\b')) { $menciona = $true } }
        if ($menciona) { $tiene = $true; break }
      }
      if (-not $tiene) { Add-Hallazgo 'e2e' 'error' $clave 0 "el job '$n' no tiene un test que lo lance entero y compruebe COMPLETED. Entrada: $($j.entrada) Salida: $($j.salida)" }
    }
  }

  # ---------- tests ----------
  if ($h.Tests.Count -eq 0) { Add-Hallazgo 'tests' 'aviso' 'src/test/java' 0 'no hay tests' }

  # ---------- calidad (Javadoc y buenas practicas de Java 21) ----------
  $estiloPlantilla = $null
  if ($cal) { $estiloPlantilla = $cal.Estilo }
  $calidad = Get-Calidad $h $estiloPlantilla
  $script:LineaEstilo = $calidad.Linea
  foreach ($q in $calidad.Hallazgos) {
    $sev = 'aviso'; $nota = ''
    if ($Cfg.CalidadErrores -contains $q.Regla) {
      if ($cal -and $cal.Calidad.ContainsKey($q.Regla) -and ($Cfg.CalidadSiempre -notcontains $q.Regla)) { $nota = ' (se queda en aviso: la plantilla tambien lo hace)' }
      else { $sev = 'error' }
    }
    Add-Hallazgo 'calidad' $sev $q.RelRaiz $q.Linea ('[' + $q.Regla + '] ' + $q.Detalle + $nota)
  }

  # ---------- sonar (solo con -Sonar) ----------
  if ($Sonar) { Add-SonarHallazgos }

  # ---------- cobertura (solo con -Cobertura) ----------
  if ($Cobertura) { Add-CoberturaHallazgos ([bool]($ConBuild -and $ConTests)) }

  return $script:H.ToArray()
}

function Get-Cuenta($Hall, [string]$Cat, [string]$Sev = 'error') {
  return @($Hall | Where-Object { $_.Cat -eq $Cat -and $_.Sev -eq $Sev }).Count
}

# Primer paso con errores pendientes (sin contar lo que ya se dio por atascado).
function Get-SiguientePasoMotor($Hall) {
  foreach ($c in $Cfg.Orden) {
    if ($c -eq 'cobertura' -and $script:CobHecha) { continue }   # una pasada por ejecucion: lo que le falte sale en su resumen
    $f = @($Hall | Where-Object { $_.Cat -eq $c -and $_.Sev -eq 'error' } | ForEach-Object { $_.Fichero } | Select-Object -Unique)
    if ($script:Atascados.ContainsKey($c)) { $f = @($f | Where-Object { $script:Atascados[$c] -notcontains $_ }) }
    if ($f.Count -gt 0) { return $c }
  }
  # con -Cobertura, el paso que falta aunque aun no haya hallazgos: la cobertura solo se mide en su paso (una vez por ejecucion)
  if ($Cobertura -and -not $script:CobHecha -and (-not $script:Cob -or (Get-Cuenta $Hall 'cobertura') -gt 0)) { return 'cobertura' }
  return ''
}

function Get-TextoBuild {
  $b = $script:Build
  if (-not $b.Ejecutado) { return 'compila: no comprobado' }
  if (-not $b.Compila) { return 'compila: NO' }
  if (-not $b.TestsEjecutados) { return 'compila: SI | tests: no ejecutados' }
  if ($b.TestsOk) { return 'compila: SI | tests: OK' }
  return 'compila: SI | tests: FALLAN'
}

function Write-Informe($Hall) {
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine('# Diagnostico de rescate: ' + (Split-Path $RepoRoot -Leaf))
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('- Fecha: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm'))
  [void]$sb.AppendLine('- Paquete base: ' + $script:BasePkg)
  [void]$sb.AppendLine('- Plantilla: ' + $PlantillaRoot)
  if ($script:Cal) { [void]$sb.AppendLine('- La plantilla incumple: ' + (Get-TextoIncumple $script:Cal)) }
  [void]$sb.AppendLine('- Estado: ' + (Get-TextoBuild))
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('| Paso | Errores | Avisos |')
  [void]$sb.AppendLine('|---|---|---|')
  foreach ($c in $Cfg.Orden) { [void]$sb.AppendLine("| $c | $(Get-Cuenta $Hall $c) | $(Get-Cuenta $Hall $c 'aviso') |") }
  foreach ($c in $Cfg.Orden) {
    $it = @($Hall | Where-Object { $_.Cat -eq $c } | Sort-Object @{Expression = 'Sev'; Descending = $true }, Fichero)
    if ($it.Count -eq 0) { continue }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("## $c")
    foreach ($x in $it) {
      $donde = $x.Fichero
      if ($x.Linea -gt 0) { $donde += ':' + $x.Linea }
      if ($donde) { $donde = '`' + $donde + '` - ' }
      [void]$sb.AppendLine("- [$($x.Sev)] $donde$($x.Detalle)")
    }
  }
  if ($script:Cal) {
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Permitido porque la plantilla tambien lo hace')
    $ex = @(@($script:Cal.ExcImports.Keys) + @($script:Cal.ExcFicheros.Keys) | Sort-Object)
    if ($ex.Count -eq 0) { [void]$sb.AppendLine('- (nada: la plantilla cumple todas las reglas)') }
    foreach ($k in $ex) { [void]$sb.AppendLine('- ' + ($k -replace '\|', ' -> ')) }
  }
  [System.IO.File]::WriteAllText((Join-Path $Work 'diagnostico.md'), $sb.ToString())
  [System.IO.File]::WriteAllText((Join-Path $Work 'hallazgos.json'), (ConvertTo-Json -InputObject @($Hall) -Depth 4))
}

function Show-Resumen($Hall) {
  Info ''
  Info ('== ' + (Split-Path $RepoRoot -Leaf) + ' | ' + (Get-TextoBuild) + ' ==')
  Info ('{0,-12} {1,8} {2,8}' -f 'paso', 'errores', 'avisos')
  foreach ($c in $Cfg.Orden) {
    $e = Get-Cuenta $Hall $c
    $linea = ('{0,-12} {1,8} {2,8}' -f $c, $e, (Get-Cuenta $Hall $c 'aviso'))
    if ($e -gt 0) { Aviso $linea } else { Bien $linea }
  }
  if ($Sonar) { Info ('Sonar: ' + @(Get-SonarEstado | Where-Object { $_.Estado -eq 'resuelta' }).Count + ' resueltas aqui. La prueba de verdad es volver a pasar Sonar y relanzar con el xlsx nuevo.') }
  if ($script:LineaEstilo) { Aviso $script:LineaEstilo }
  Info ('Informe: ' + (Join-Path $Work 'diagnostico.md'))
}

# ================================= FIX =================================
# La regla de dependencias entre capas y la de adaptadores: las llevan los prompts de todos los pasos (lote y plan) y el texto del paso hexagonal.
$TextoCapas = 'El dominio no depende de nada externo. La aplicacion solo depende del dominio y de sus puertos (interfaces en application/ports).'
$TextoAdaptadores = 'El adaptador de entrada depende del puerto, nunca de un adaptador de salida. Si la pieza comun necesita otra operacion, anadela al puerto y a todos sus adaptadores.'

$TextoPaso = @{
  build      = 'Haz que el proyecto compile con Java 21 usando las mismas propiedades y plugins que el pom.xml de la PLANTILLA, sin cambiar el parent: si hace falta otro, apuntalo como duda. No copies dependencias de negocio que este repo no necesite. Corrige los errores de compilacion listados. No reestructures paquetes en este paso.'
  estructura = 'Mueve las clases listadas a la capa y paquete que les corresponde, copiando exactamente la estructura de paquetes y la convencion de nombres de la PLANTILLA. Solo mover: no cambies logica. Actualiza el package de cada clase movida y los imports de TODOS los ficheros que la usan, tambien los que no estan en la lista: las clases que estaban en su mismo paquete no tenian import y ahora lo necesitan. Mueve tambien sus tests al paquete equivalente. Si falla un test de arquitectura del repo (ArchUnit), su motivo dice que regla rompes: cambia el destino de la clase, no el test.'
  hexagonal  = 'Elimina las dependencias prohibidas listadas. ' + $TextoCapas + ' Si una clase de dominio o aplicacion necesita infraestructura, crea un puerto y lleva la implementacion a un adaptador en infrastructure/adapters/output/<tecnologia>, con los nombres al estilo de la PLANTILLA.'
  ficheros   = 'Sustituye el acceso directo a ficheros locales por puertos de ficheros, igual que la PLANTILLA: puerto para listar y leer, puerto para el ciclo de vida del fichero, un adaptador SFTP y otro local, y seleccion por propiedad de configuracion. Usa la misma libreria SFTP que la PLANTILLA; si la PLANTILLA no tiene SFTP, crea igualmente el adaptador SFTP en infrastructure/adapters/output/sftp (con la libreria SFTP que ya use este repo) y su bloque sftp en application.yml. No dejes rutas fijas en el codigo.'
  config     = 'Elimina las referencias a la configuracion antigua (inventory). Toda la configuracion debe entrar por una clase @ConfigurationProperties validada al arranque y por application.yml leyendo variables de entorno, igual que la PLANTILLA. Ningun secreto (contrasena, token, clave) puede quedar escrito en application.yml o application.properties, ni como valor por defecto: se leen de una variable de entorno (`${NOMBRE}`). No escribas el valor en ningun otro fichero del repo; si un test lo necesita, usa un valor inventado en src/test/resources.'
  paridad    = 'Migra desde el ORIGINAL el job listado, que falta en este repo. Conserva EXACTAMENTE su nombre de job (con ese nombre lo lanza el planificador). Sigue la estructura de la PLANTILLA: adaptador de entrada (job y step), caso de uso, puertos y adaptadores de salida. Reutiliza los puertos y adaptadores que ya existan en este repo. Misma logica que el original.'
  e2e        = 'Crea un test de integracion para el job listado, copiando el patron de los tests de integracion de la PLANTILLA. El test lanza el job real de principio a fin con los adaptadores locales (sftp desactivado), base de datos en memoria y los servicios externos simulados; comprueba que termina en COMPLETED y que la salida es la esperada. Usa los datos de src/test/resources/e2e/<nombre-del-job>/ si existen; si no, crea alli datos sinteticos minimos (nunca datos reales). La salida esperada se deduce de la logica del ORIGINAL, no de ejecutar el codigo nuevo. El test debe contener el nombre del job. Si el test falla porque el codigo migrado no hace lo mismo que el original, corrige el codigo, no el test.'
  tests      = 'Haz que los tests listados pasen. Si fallan por la reestructuracion (paquetes, puertos, mocks), adapta el test. Si destapan un fallo real de la migracion, corrige el codigo. No borres tests ni relajes aserciones.'
  cobertura  = 'Escribe o amplia el test de la clase listada hasta cubrir sus lineas sin cubrir, sin tocar nada fuera de src/test/ (el detalle va en el prompt del lote).'
  sonar      = 'Corrige las incidencias de Sonar listadas SIN cambiar el comportamiento ni la API publica (el detalle de lo que se pide va en el prompt del lote).'
  calidad    = 'Resuelve los hallazgos de calidad listados SIN cambiar el comportamiento. Javadoc: lee antes el codigo y escribe que hace la clase y que papel tiene en su capa; en cada metodo, que hace, @param, @return y @throws; no te lo inventes ni repitas el nombre. @Autowired en un campo: pasa a inyeccion por constructor con campos private final y adapta los tests que construyan la clase. System.out y printStackTrace: usa el logger que usa la PLANTILLA, con el mismo mensaje. catch vacio: no cambies el flujo; registra la excepcion con el logger o deja un comentario que explique por que se ignora. new Integer(...) y similares: valueOf. Varios constructores sin @Autowired: deja uno solo o marca con @Autowired el que Spring debe usar. @Value o @Autowired en un campo static, o @Value sin ${...}: quita static o la anotacion, o pon la propiedad con ${...}. Estilo (constructor, logger): pasa la clase al estilo que dice el hallazgo. Clase o metodo final que Spring envuelve con un proxy: quita final y nada mas. No toques nada mas de esos ficheros.'
}

# Lo que se le pide al codigo que la IA escribe en cualquier paso.
$TextoCalidad = @(
  'Vale para el codigo NUEVO de este lote y para los metodos que modifiques. No es permiso para refactorizar lo demas.',
  '- Javadoc, en el idioma de los comentarios de la PLANTILLA. Cada clase, interfaz, record o enum publico que crees lleva un Javadoc que dice que es y que papel tiene en su capa (puerto, adaptador, caso de uso...). Cada metodo publico que crees, y todos los de una interfaz, llevan Javadoc: que hace, @param, @return y @throws cuando existan. No hace falta en metodos con @Override, getters, setters ni constructores. Un Javadoc que solo repite el nombre no vale.',
  '- Inyeccion por constructor con campos private final. Nada de @Autowired ni @Inject en campos: inyeccion por un unico constructor, campos final, sin estado mutable en el componente.',
  '- Un solo constructor por componente de Spring (si hay varios, @Autowired en el que debe usar Spring). @Value solo con ${...} o #{...} y nunca en un campo static. Constructor y logger con el mismo estilo que el resto del batch y la PLANTILLA (Lombok o a mano, @Slf4j o LoggerFactory). Sin final en una clase ni en un metodo que Spring envuelve con un proxy (@Repository, @Configuration, @Transactional, @Async, @StepScope...): el bean no se crea.',
  '- Para datos inmutables nuevos (valores, DTO, propiedades de configuracion) usa record si la PLANTILLA tambien los usa.',
  '- Usa el logger de la PLANTILLA. Nunca System.out, System.err ni printStackTrace. Ningun catch vacio: registra la excepcion con el logger y sigue como hasta ahora, o explica en un comentario por que se ignora. No la relances ni quites el catch: cambia el comportamiento.',
  '- try-with-resources para todo lo que se cierra. Optional solo como valor de retorno. Colecciones inmutables (List.of, Stream.toList) cuando no se modifican.',
  '- Sintaxis de Java 21 solo donde simplifica codigo que ya estas escribiendo: switch con flechas, instanceof con patron, bloques de texto. var solo si el tipo se ve en la misma linea.',
  '- Fechas nuevas con java.time. No conviertas en este lote las fechas que ya existen: puede cambiar el comportamiento.',
  'Despues del lote el script vuelve a contar los hallazgos de calidad (Javadoc, inyeccion en campos, constructores, estilo, System.out, catch vacios). Si tu codigo anade alguno, el lote no pasa.'
)

# Un hallazgo en una linea de prompt: '- fichero:linea - detalle' ('(repo)' si no es de un fichero), y ' - motivo: <motivo>' si lo tiene.
function Get-LineaHallazgo($x) {
  $donde = $x.Fichero
  if ($x.Linea -gt 0) { $donde += ':' + $x.Linea }
  if (-not $donde) { $donde = '(repo)' }
  $t = "- $donde - $($x.Detalle)"
  if ($x.Motivo) { $t += " - motivo: $($x.Motivo)" }
  return $t
}

# La clave con la que se reconoce un hallazgo aunque el intento cambie el fichero de paquete: categoria, nombre del fichero
# (sin su ruta) y detalle.
function Get-ClaveHallazgo($x) { return ($x.Cat + '|' + $x.Fichero.Split('/')[-1] + '|' + $x.Detalle) }

# Los errores de estas categorias que no estaban antes del intento ($Antes: las claves de los de antes).
function Get-HallazgosNuevos($Hall, [string[]]$Cats, $Antes) {
  return @($Hall | Where-Object { $_.Sev -eq 'error' -and $Cats -contains $_.Cat -and -not $Antes.ContainsKey((Get-ClaveHallazgo $_)) })
}

# Las lineas de un detalle para pantalla (y para atascados.md): hasta 8, con sangria, y si hay mas, cuantas faltan y en que
# fichero estan todas ($Ruta: la correccion completa del intento).
function Get-LineasDetalle([string[]]$Detalle, [string]$Ruta) {
  $l = @(@($Detalle) | Select-Object -First 8 | ForEach-Object { '    ' + "$_".Trim() })
  if (@($Detalle).Count -gt 8) { $l += "    ($(@($Detalle).Count - 8) mas en $Ruta)" }
  return $l
}

# La correccion completa de un intento que no paso (la que recibe el siguiente, con su detalle) en
# .rescate/intento-<paso>-<lote>-<i>.md. Devuelve su ruta relativa a la raiz.
function Save-CorreccionIntento([string]$PasoId, [int]$N, [int]$I, [string[]]$Sel, [string]$Correccion) {
  $cab = @("# Paso '$PasoId', lote $N, intento ${I}: no paso", ('Ficheros: ' + ($Sel -join ', ')), '')
  [System.IO.File]::WriteAllText((Join-Path $Work "intento-$PasoId-$N-$I.md"), ((($cab + $Correccion) -join "`n") + "`n"))
  return ".rescate/intento-$PasoId-$N-$I.md"
}

# La opcion que ha elegido el consejo en una duda.
function Get-Elegida($Duda) { return "$(@($Duda.opciones)[[int]$Duda.elegida - 1])" }

# Las referencias de una llamada de solo lectura (revision previa, consejo, reflexion).
function Get-TextoReferencias {
  $l = @('## Referencias (SOLO LECTURA)')
  if ($PlantillaRoot) { $l += @("- PLANTILLA: $PlantillaRoot", '  Repo ya migrado y aprobado. Es la fuente de verdad para paquetes, nombres de puertos y adaptadores, configuracion y tests.') }
  if ($LegacyRoot) { $l += @("- ORIGINAL JAVA 8: $LegacyRoot", '  Referencia de comportamiento.') }
  return ($l + '')
}

# En cada lote se ejecutan los tests (salvo -SinTests); en 'tests', 'e2e' y 'cobertura', siempre.
function Get-ConTests([string]$PasoId) { return [bool]((-not $SinTests) -or ($PasoId -eq 'tests') -or ($PasoId -eq 'e2e') -or ($PasoId -eq 'cobertura')) }

# La orden que la IA ejecuta dentro de su sesion para ver, sin Maven, lo que ha roto: este mismo script en -Modo comprobar, con el
# mismo PowerShell (5.1 o 7) y los parametros que deciden donde se trabaja.
function Get-OrdenComprobar {
  $exe = [System.IO.Path]::GetFileNameWithoutExtension((Get-Process -Id $PID).Path)
  if ($exe -notmatch '^(pwsh|powershell)$') { $exe = 'pwsh' }
  $o = "$exe -NoProfile -File `"$PSCommandPath`" -Modo comprobar -Repo `"$OrigenRoot`""
  if ($PlantillaRoot) { $o += " -Plantilla `"$PlantillaRoot`"" }
  if ($SinWorktree) { $o += ' -SinWorktree' }
  if ($Worktree) { $o += " -Worktree `"$Worktree`"" }
  return $o
}

# La orden de Maven para un prompt: relativa (./mvnw) si esta dentro del repo; si no, la ruta tal cual, entre comillas si tiene espacios.
function Get-OrdenMaven {
  $sep = [System.IO.Path]::DirectorySeparatorChar
  $mvn = Get-Mvn $RepoRoot
  if ($mvn.StartsWith($RepoRoot + $sep, [System.StringComparison]::OrdinalIgnoreCase)) { $mvn = '.' + $sep + $mvn.Substring($RepoRoot.Length + 1) }
  if ($mvn -match '\s') { $mvn = '"' + $mvn + '"' }
  return $mvn
}

# Las reglas que llevan todos los prompts de un lote.
$TextoReglas = @(
  '1. No cambies la logica de negocio: mismo comportamiento que el original.',
  '2. No toques nada fuera de este repositorio. No hagas commit ni push ni cambies de rama: de git se encarga el script.',
  '3. No borres tests, no los desactives (@Disabled, @Ignore), no relajes aserciones ni bajes umbrales de cobertura. Si mueves una clase, mueve su test.',
  "4. No cambies el pom.xml salvo que el paso sea 'build' o sea imprescindible. Nunca anadas dependencias que la plantilla no use.",
  '5. No escribas contrasenas, tokens ni hosts reales en ningun fichero.',
  '6. No hagas mejoras ni refactors que este lote no pide.',
  '7. Si un hallazgo no se puede resolver sin romper estas reglas, dejalo como esta y explicalo al final.'
)

# Lo que el prompt de un lote pide hacer al terminar.
function Get-TextoAlTerminar([string]$Mvn, [string]$PasoId) {
  $a = $Cfg.MvnCompilar; $fin = 'y corrige hasta que compile.'
  if (Get-ConTests $PasoId) {
    # en PasosSoloCompila el modelo solo compila: la suite la pasa el script en sus puertas (una vez por intento, no dos)
    if ($Cfg.PasosSoloCompila -contains $PasoId) { $fin += ' Los tests los pasa el script despues.' }
    else { $a = $Cfg.MvnTests; $fin = 'y corrige los tests que fallen.' }
  }
  $l1 = "- Ejecuta: $(Get-OrdenComprobar)  y corrige lo que liste (como mucho 3 veces)."
  # PowerShell parte -Dmaven.test.skip=false en dos argumentos si no va entre comillas
  $a = @($a | ForEach-Object { if ($_ -match '^-D.*\.') { '"' + $_ + '"' } else { $_ } })
  $l2 = "- Ejecuta: $Mvn $($a -join ' ')  $fin"
  return @($l1, $l2, '- Responde solo con: ficheros cambiados (lista corta) y hallazgos sin resolver con el motivo.')
}

# Prompt de un lote. $Consejo: la decision del modelo de las dudas para un atascado (va tras los hallazgos).
# $Reflexiones: las de los intentos anteriores de estos ficheros (dentro de la CORRECCION, si la hay).
# Con CORRECCION es el prompt corto de reparacion: el intento anterior sigue en el arbol y no hay que explorar de nuevo.
function New-Prompt([string]$PasoId, $LoteH, [string]$Correccion, $Consejo = $null, $Reflexiones = @()) {
  if ($PasoId -eq 'sonar') { return (New-PromptSonar $LoteH $Correccion $Consejo $Reflexiones) }
  if ($PasoId -eq 'cobertura') { return (New-PromptCobertura $LoteH $Correccion $Consejo $Reflexiones) }
  if ($Correccion) { return (New-PromptReparacion $PasoId $LoteH $Correccion $Consejo $Reflexiones) }
  $mvn = Get-OrdenMaven
  $l = New-Object System.Collections.Generic.List[string]
  $l.Add("# Tarea de rescate de migracion: paso '$PasoId'")
  $l.Add('')
  $l.Add('Trabaja SOLO en el repositorio actual. Es una migracion a medias de un batch Java 8 a Java 21 con arquitectura hexagonal.')
  $l.Add('')
  $l.Add('## Referencias (SOLO LECTURA: no las modifiques)')
  if ($PlantillaRoot) {
    $l.Add("- PLANTILLA: $PlantillaRoot")
    $l.Add('  Repo ya migrado y aprobado. Es la fuente de verdad para estructura de paquetes, nombres de puertos y adaptadores, configuracion y tests. Antes de cambiar nada, lee alli las clases equivalentes y copia su estilo.')
  }
  if ($LegacyRoot) {
    $l.Add("- ORIGINAL JAVA 8: $LegacyRoot")
    $l.Add('  Referencia de comportamiento: el resultado debe hacer exactamente lo mismo.')
  }
  $l.Add('')
  if ($script:Cal) { foreach ($x in (Get-TextoMapaPaquetes $script:Cal)) { $l.Add($x) } }
  $l.Add('## Antes de tocar nada')
  $l.Add('1. Lee enteros los ficheros del lote y busca quien los usa: imports, inyeccion, configuracion y tests.')
  $l.Add('2. Lee en la PLANTILLA las clases equivalentes y copia su paquete, sus nombres y su estilo.')
  $l.Add('3. Si en este repo ya existe un puerto, un adaptador o una clase de configuracion que sirve, reutilizalo. No crees otro parecido.')
  $l.Add('4. Respeta las dependencias entre capas. ' + $TextoCapas + ' ' + $TextoAdaptadores)
  $l.Add('')
  $rutaPlan = Get-RutaPlan $PasoId
  if (-not $SinPlan -and (Test-Path -LiteralPath $rutaPlan)) {
    $l.Add('## Plan aprobado de este paso (solo la parte de este lote)')
    $l.Add('Si una pieza comun del plan ya existe en el repo, reutilizala. Si aun no existe y este lote la necesita, creala como dice el plan. Si un fichero del lote no esta en el plan, aplica el mismo criterio que con los demas.')
    $l.Add('El plan completo tiene mas ficheros. Los hara otro lote: no los muevas ni los cambies. Toca otro fichero solo si hace falta para que compile (su import o la llamada que cambia).')
    $l.Add('')
    $fichsLote = @($LoteH | ForEach-Object { $_.Fichero } | Where-Object { $_ } | Select-Object -Unique)
    foreach ($linea in (Get-PlanDelLote ([System.IO.File]::ReadAllText($rutaPlan)) $fichsLote)) { $l.Add('> ' + $linea) }
    $l.Add('')
  }
  $l.Add('## Que hay que hacer')
  $l.Add($TextoPaso[$PasoId])
  $l.Add('')
  $l.Add('## Hallazgos de este lote (resuelve estos y nada mas)')
  foreach ($x in $LoteH) { $l.Add((Get-LineaHallazgo $x)) }
  $l.Add('')
  if ($Consejo) { foreach ($x in (Get-TextoConsejoLote $Consejo)) { $l.Add($x) } }
  $l.Add('## Reglas obligatorias')
  foreach ($x in $TextoReglas) { $l.Add($x) }
  $l.Add('')
  $l.Add('## Calidad del codigo que escribas (Java 21)')
  foreach ($x in $TextoCalidad) { $l.Add($x) }
  $l.Add('')
  $l.Add('## Al terminar')
  foreach ($x in (Get-TextoAlTerminar $mvn $PasoId)) { $l.Add($x) }
  foreach ($x in (Get-TextoReflexiones $Reflexiones $false)) { $l.Add($x) }
  return ($l -join "`n")
}

# El consejo de un revisor para un fichero atascado, para un prompt.
function Get-TextoConsejoLote($Consejo) {
  return @('## Consejo para este fichero (lo ha decidido un revisor: siguelo)', "Duda: $($Consejo.duda)", ('Decision: ' + (Get-Elegida $Consejo)), "Por que: $($Consejo.porque)", '')
}

# Prompt de un intento 2, 3... (o de un escalon que parte del arbol del mejor intento): el arbol ya tiene el intento anterior, asi que
# arriba va lo que hay que arreglar, con su detalle, y debajo, en corto, los ficheros del lote, la orden de Maven y las reglas.
function New-PromptReparacion([string]$PasoId, $LoteH, [string]$Correccion, $Consejo, $Reflexiones) {
  $l = New-Object System.Collections.Generic.List[string]
  $l.Add("# Tarea de rescate de migracion: paso '$PasoId'")
  $l.Add('')
  $l.Add('Tu intento anterior sigue en el arbol de trabajo. No vuelvas a explorar el repo: arregla solo esto.')
  $l.Add('')
  $l.Add('## CORRECCION: tu intento anterior no paso las comprobaciones')
  $l.Add('Corrige esto sin deshacer lo que estaba bien:')
  $l.Add($Correccion)
  foreach ($x in (Get-TextoReflexiones $Reflexiones $true)) { $l.Add($x) }
  $l.Add('')
  if ($Consejo) { foreach ($x in (Get-TextoConsejoLote $Consejo)) { $l.Add($x) } }
  $l.Add('## Ficheros del lote')
  $fichs = @($LoteH | ForEach-Object { $_.Fichero } | Where-Object { $_ } | Select-Object -Unique)
  if ($fichs.Count -eq 0) { $fichs = @('(repo)') }
  foreach ($f in $fichs) { $l.Add("- $f") }
  $l.Add('')
  $l.Add('## Al terminar')
  foreach ($x in (Get-TextoAlTerminar (Get-OrdenMaven) $PasoId)) { $l.Add($x) }
  $l.Add('')
  $l.Add('## Reglas obligatorias')
  foreach ($x in $TextoReglas) { $l.Add($x) }
  $l.Add('')
  $l.Add('## Calidad del codigo que escribas (Java 21)')
  foreach ($x in $TextoCalidad) { $l.Add($x) }
  return ($l -join "`n")
}

# Los titulos markdown (#...) de un texto, cambiados por $Como ('$1' es el titulo sin almohadillas).
function Convert-Titulos([string]$Texto, [string]$Como) { return ($Texto.Trim() -replace '(?m)^[ \t]*#+[ \t]*(.*?)[ \t\r]*$', $Como) }

# Las reflexiones de los intentos que no pasaron, para un prompt: una seccion (dentro de la CORRECCION si $Dentro). Los
# titulos de cada reflexion pasan a lineas normales, para no romper las secciones del prompt.
function Get-TextoReflexiones($Reflexiones, [bool]$Dentro) {
  if (@($Reflexiones).Count -eq 0) { return @() }
  $h = '##'
  if ($Dentro) { $h = '###' }
  $l = @('', "$h Lo que ya se intento y por que fallo", 'Un revisor ha leido los intentos de estos ficheros que no pasaron. No repitas lo que dice que no hay que hacer.')
  foreach ($r in $Reflexiones) { $l += @('', "$h# $($r.Titulo)", (Convert-Titulos $r.Texto '$1:')) }
  return $l
}

# El programa de Copilot, buscado con la regla de comun.ps1 (Get-Lanzable: la misma del preflight y de migracion.ps1).
# Se busca al empezar un modo que lo usa, antes de tocar el repo; Test-Copilot lo repite solo si CopilotExe ha cambiado.
# En pre (que sin Copilot sigue con la busqueda por texto) no es un error; en plan y fix, si.
$script:Copilot = $null
$script:CopilotDe = $null
function Test-Copilot {
  if (($Modo -ne 'plan') -and ($Modo -ne 'fix') -and (($Modo -ne 'pre') -or $SinIA)) { return }
  if ($script:CopilotDe -ceq $Cfg.CopilotExe) { return }
  $script:Copilot = Get-Lanzable $Cfg.CopilotExe
  $script:CopilotDe = $Cfg.CopilotExe
  if (-not $script:Copilot.Ruta -and $Modo -ne 'pre') { Fallo $script:Copilot.Mensaje; exit 1 }
}

# Lo ultimo que dijo Copilot al salir con un codigo distinto de 0 (hasta 5 lineas no vacias), para ver el motivo sin abrir
# el registro.
function Write-FinCopilot($R) {
  foreach ($x in @(@($R.Salida) | Where-Object { "$_".Trim() } | Select-Object -Last 5)) {
    $t = "$x".TrimEnd()
    if ($t.Length -gt 200) { $t = $t.Substring(0, 200) + '...' }
    Aviso "    $t"
  }
}

# Llama a Copilot CLI sin sesion interactiva (copilot -p). El modelo y el
# esfuerzo de razonamiento son los de -Modelo y -Esfuerzo, salvo que la
# llamada pida otros (modelo de reserva, esfuerzo de la revision previa).
# $Que es lo que dice el latido mientras Copilot trabaja. Con tope ($Cfg.MinutosCopilot): pasado, se para Copilot con sus
# procesos hijos (Invoke-Proceso, que lo lanza como Invoke-Nativo: misma entrada y misma codificacion) y la llamada sale con
# Codigo -1 y Tope, el mensaje que dice que se ha pasado (tambien por la consola); sin tope, Tope vale ''. Devuelve Codigo,
# Salida (las lineas: las de la salida y despues las de errores) y Tope; la salida queda tambien en $Log.
function Invoke-Copilot([string]$Log, [string]$Mod = '', [string]$Esf = '', [string]$Que = 'Copilot') {
  if (-not $Mod) { $Mod = $Modelo }
  if (-not $Esf) { $Esf = $Esfuerzo }
  $a = Get-ArgsCopilot 'Lee el fichero .rescate/prompt.md y sigue sus instrucciones al pie de la letra.' $Mod $Esf @($PlantillaRoot, $LegacyRoot) ([bool]$SinInstrucciones)
  $latido = Start-Latido $Que $Cfg.SegundosLatido
  try { $p = Invoke-Proceso $script:Copilot.Ruta $a $RepoRoot ([int][Math]::Ceiling([double]$Cfg.MinutosCopilot * 60)) $true }
  finally { Stop-Latido $latido }
  $salida = @()
  if ($p.Texto) { $salida = @(($p.Texto -replace '\r?\n$', '') -split '\r?\n') }
  [System.IO.File]::WriteAllLines($Log, [string[]]$salida)
  $r = [pscustomobject]@{ Codigo = $p.Codigo; Salida = $salida; Tope = ''; Segundos = $p.Segundos }
  if ($p.Agotado) {
    $r.Tope = "Copilot se ha pasado del tope de $($Cfg.MinutosCopilot) min y se ha parado ($Que)."
    Aviso $r.Tope
  }
  return $r
}

# Reflexionar ('repetido', 'siempre' o 'nunca'; true y false valen como siempre y nunca) y EsfuerzoReintento (low a max, o vacio):
# normaliza los dos valores de la config y avisa de los que no valen.
function Initialize-ConfigReintentos {
  $modos = @{ 'true' = 'siempre'; 'false' = 'nunca'; 'siempre' = 'siempre'; 'nunca' = 'nunca'; 'repetido' = 'repetido' }
  $modo = $modos["$($Cfg.Reflexionar)".Trim().ToLowerInvariant()]
  if (-not $modo) { Aviso "Reflexionar '$($Cfg.Reflexionar)' no vale (repetido, siempre, nunca, true o false): uso 'repetido'."; $modo = 'repetido' }
  $Cfg.Reflexionar = $modo
  $e = "$($Cfg.EsfuerzoReintento)".Trim()
  if ($e -and @('low', 'medium', 'high', 'xhigh', 'max') -cnotcontains $e) { Aviso "EsfuerzoReintento '$e' no vale (low, medium, high, xhigh o max): lo dejo vacio."; $e = '' }
  $script:EsfReintento = $e
}

# El esfuerzo de un reintento (intento 2 o siguiente, o un escalon): el de EsfuerzoReintento si es mayor que el de -Esfuerzo; si no,
# vacio (el de -Esfuerzo).
function Get-EsfuerzoReintento {
  $r = $script:EsfReintento
  if (-not $r) { return '' }
  $niveles = @('low', 'medium', 'high', 'xhigh', 'max')
  if ($Esfuerzo -and [array]::IndexOf($niveles, $r) -le [array]::IndexOf($niveles, $Esfuerzo)) { return '' }
  return $r
}

# La forma de un fallo, para compararlo con el del intento anterior: sus NO PASA sin las cifras y las claves de sus hallazgos nuevos.
function Get-ClaveFallo([string[]]$Problemas, $Nuevos) {
  return [pscustomobject]@{
    Problemas = (@($Problemas | ForEach-Object { $_ -replace '\d+', '#' } | Sort-Object) -join '|')
    Nuevos    = (@($Nuevos | ForEach-Object { Get-ClaveHallazgo $_ } | Sort-Object) -join '|')
  }
}

# Es el mismo fallo? Los mismos NO PASA (sin cifras) o, si los hay, los mismos hallazgos nuevos.
function Test-FalloRepetido($A, $B) { return [bool]($A.Problemas -ceq $B.Problemas -or ($A.Nuevos -and $A.Nuevos -ceq $B.Nuevos)) }

# Para pantalla: con que modelo y que esfuerzo se va a llamar a Copilot.
function Get-TextoModelo {
  $m = $Modelo; $e = $Esfuerzo; $p = $EsfuerzoPlan
  if (-not $m) { $m = 'el que tenga Copilot' }
  if (-not $e) { $e = 'el que tenga Copilot' }
  if (-not $p) { $p = $e }
  $t = "Copilot (copilot -p): modelo $m | esfuerzo en los lotes: $e | en la revision previa: $p"
  if ($ModeloB) { $t += " | modelo de reserva: $ModeloB" }
  $md = $script:ModDudas
  if (-not $md) { $md = $m }
  $t += " | modelo de las dudas (consejo y reflexion): $md, esfuerzo $($script:EsfDudas)"
  $er = Get-EsfuerzoReintento
  if ($er) { $t += " | en los reintentos: $er" }
  if ($Cfg.Reflexionar -eq 'nunca') { $t += ' (sin reflexion)' }
  elseif ($Cfg.Reflexionar -eq 'repetido') { $t += ' (reflexion solo si el fallo se repite)' }
  return $t
}

function Get-Guardas {
  $tests = @(Get-JavaFiles (Join-Ruta $RepoRoot 'src/test/java'))
  $des = 0; $ase = 0; $met = 0
  foreach ($f in $tests) {
    $t = [System.IO.File]::ReadAllText($f.FullName)
    $des += [regex]::Matches($t, '@(Disabled|Ignore)\b').Count
    $ase += [regex]::Matches($t, '\b(assert\w*|verify)\s*\(').Count
    # los metodos de test, sin comentarios ni textos (un @Test comentado no cuenta): borrar o comentar uno baja la cuenta aunque el fichero se quede
    $met += [regex]::Matches((Get-Limpio $t), '@(?:\w+\.)*(?:Test|ParameterizedTest|RepeatedTest|TestFactory)\b').Count
  }
  # los catch de src/main/java, sin comentarios ni textos (ruta -> cuenta): quitar uno cambia como se tratan los errores
  $catchDe = @{}; $nc = 0
  foreach ($f in @(Get-JavaFiles (Join-Ruta $RepoRoot 'src/main/java'))) {
    $k = $script:RxCatch.Matches((Get-Limpio ([System.IO.File]::ReadAllText($f.FullName)))).Count
    if ($k -gt 0) { $catchDe[(Get-Rel $RepoRoot $f.FullName)] = $k; $nc += $k }
  }
  return [pscustomobject]@{ Tests = $tests.Count; Metodos = $met; Desactivados = $des; Aserciones = $ase; Catch = $nc; CatchDe = $catchDe; Plantilla = (Get-Huella $PlantillaRoot); Legacy = (Get-Huella $LegacyRoot) }
}

# ================================ PLAN ================================
function Get-RutaPlan([string]$PasoId) { return (Join-Path $Work "plan-$PasoId.md") }

# Como se nombra un fichero en un plan: el nombre de su clase, como palabra entera.
function Get-RxClase([string]$Fichero) {
  return '(?<![\w])' + [regex]::Escape([System.IO.Path]::GetFileNameWithoutExtension($Fichero.Split('/')[-1])) + '(?![\w])'
}

# Ficheros con hallazgos que el plan no nombra.
function Get-SinPlan([string]$Ruta, $Fichs) {
  if (-not (Test-Path -LiteralPath $Ruta)) { return @($Fichs) }
  $t = [System.IO.File]::ReadAllText($Ruta)
  return @($Fichs | Where-Object { $t -notmatch (Get-RxClase $_) })
}

# El titulo de una linea '## ...' de lo que escribe la IA (plan, reflexion), para compararlo sin distinguir mayusculas:
# sin '*', sin acentos, sin espacios de mas y sin ':' ni '.' al final. $null si la linea no es un titulo '## '.
function Get-TituloPlan([string]$Linea) {
  if ($Linea -notmatch '^\s*##\s') { return $null }
  $t = (((($Linea -replace '^\s*##\s+', '') -replace '\*', '' -replace '\s+', ' ').Trim()) -replace '\s*[:.]+$', '').Normalize([System.Text.NormalizationForm]::FormD)
  return (-join @($t.ToCharArray() | Where-Object { [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne [System.Globalization.UnicodeCategory]::NonSpacingMark }))
}

# Las lineas de una seccion '## <Titulo>' (sin el titulo), o @() si no esta.
function Get-SeccionPlan([string]$Texto, [string]$Titulo) {
  $sal = @(); $dentro = $false
  foreach ($x in ($Texto -split "`r?`n")) {
    $t = Get-TituloPlan $x
    if ($null -ne $t) { $dentro = ($t -eq $Titulo); continue }
    if ($dentro) { $sal += $x }
  }
  return $sal
}

# Las cuatro secciones de una reflexion, con el titulo con el que se comparan (como Get-TituloPlan).
$TitulosReflexion = @('Que se intento', 'Por que no paso', 'Que hacer ahora', 'Que no hacer')

# El titulo de una linea de la reflexion tal como esta escrito, sin adornos: una linea '#' a '####' o una linea entera en
# negrita, con o sin numero delante ('1.', '1)'), sin '*', sin signos de pregunta y sin ':' ni '.' al final. $null si la
# linea no es un titulo.
function Get-TituloEscrito([string]$Linea) {
  $t = $null
  if ($Linea -match '^\s*#{1,4}\s+(\S.*)$') { $t = $Matches[1] }
  elseif ($Linea -match '^\s*(?:\d+[.)]\s*)?(\*\*[^*]+\*\*[:.]?)\s*$') { $t = $Matches[1] }
  if ($null -eq $t) { return $null }
  $t = ($t -replace '[*\u00BF?]', '').Trim()
  $t = ($t -replace '^\d+[.)]\s*', '' -replace '\s*#+$', '' -replace '\s*[:.]+$', '' -replace '\s+', ' ').Trim()
  if (-not $t) { return $null }
  return $t
}

# Las lineas de una seccion de la reflexion, o @() si no esta. Un titulo que no es de los cuatro es texto de la seccion en
# la que esta.
function Get-SeccionReflexion([string]$Texto, [string]$Titulo) {
  $sal = @(); $dentro = $false
  foreach ($x in ($Texto -split "`r?`n")) {
    $t = Get-TituloEscrito $x
    if ($null -ne $t) {
      $k = Get-TituloPlan "## $t"
      if ($TitulosReflexion -contains $k) { $dentro = ($k -eq $Titulo); continue }
    }
    if ($dentro) { $sal += $x }
  }
  return $sal
}

# Del plan, lo que toca a un lote: su primera linea, '## Piezas comunes' y '## Decisiones' enteras y, de
# '## Ficheros', las lineas que nombran un fichero del lote. Sin '## Ficheros' (formato que
# no conozco) devuelve el plan entero. Los titulos, como los compara Get-TituloPlan; en el prompt se citan tal como
# los escribio el plan.
function Get-PlanDelLote([string]$Plan, [string[]]$Fichs) {
  $todo = @($Plan.Trim() -split "`r?`n")
  $rx = @($Fichs | ForEach-Object { Get-RxClase $_ })
  $sal = New-Object System.Collections.Generic.List[string]
  $sec = ''; $posF = -1; $suyas = 0
  foreach ($x in $todo) {
    $t = Get-TituloPlan $x
    $titulo = ($null -ne $t)
    if ($titulo) { $sec = $t }
    if ($sec -eq '') { if ($sal.Count -eq 0) { $sal.Add($x); $sal.Add('') } }
    elseif ($sec -eq 'Piezas comunes' -or $sec -eq 'Decisiones') { $sal.Add($x) }
    elseif ($sec -eq 'Ficheros') {
      if ($titulo) { $posF = $sal.Count; $sal.Add($x) }
      elseif (@($rx | Where-Object { $x -match $_ }).Count -gt 0) { $sal.Add($x); $suyas++ }
    }
  }
  if ($posF -lt 0) { return $todo }
  if ($suyas -eq 0) { $sal.Insert($posF + 1, '(el plan no nombra los ficheros de este lote: aplica el mismo criterio que con los demas)') }
  return $sal
}

# El paquete (ruta relativa al paquete base, con '/') de un nombre que la IA escribe en un plan: un nombre de clase completo, un
# paquete o una ruta, con '.' o con '/'. $null si no se puede leer o no cuelga de una capa de la plantilla (no se comprueba).
function Get-PaqueteDePlan([string]$Nombre, $Cal) {
  $n = ($Nombre.Trim() -replace '[`"''*]', '')
  if ($n -match '\.(ya?ml|xml|properties|json|md|txt|csv|sql)$') { return $null }
  $seg = @(($n -replace '\.java$', '') -split '[./]' | Where-Object { $_ })
  if ($seg.Count -ge 2 -and $seg[-1] -cmatch '^[A-Z]') { $seg = @($seg[0..($seg.Count - 2)]) }
  for ($k = 0; $k -lt $seg.Count; $k++) {
    if ($Cal.Capas -contains $seg[$k]) { return ($seg[$k..($seg.Count - 1)] -join '/') }
  }
  return $null
}

# Esta en la plantilla un paquete? Si tiene clases o es la carpeta de un paquete que las tiene.
function Test-PaqueteEnPlantilla([string]$Rel, $Cal) {
  foreach ($k in $Cal.Paquetes.Keys) { if ($k -eq $Rel -or $k.StartsWith($Rel + '/')) { return $true } }
  return $false
}

# Existe un paquete en el repo que se migra? Si su carpeta esta bajo el paquete base (src/main/java/<paquete base>/): lo que ya
# esta alli lo dio por bueno el paso 'estructura'. El paquete base es el del ultimo diagnostico ($script:BasePkg): no se recorre
# el repo otra vez. Antes del primer diagnostico no hay paquete base y no se encuentra nada.
function Test-PaqueteEnRepo([string]$Rel) {
  $base = Join-Ruta (Join-Ruta $RepoRoot 'src/main/java') ($script:BasePkg -replace '\.', '/')
  return (Test-Path -LiteralPath (Join-Ruta $base $Rel) -PathType Container)
}

# Los paquetes que un plan nombra y ni la plantilla ni el repo tienen, como 'paquete (en <nombre tal como esta escrito>)': los de
# '## Piezas comunes' (nombres completos de clase, con '.' o con '/') y los de las lineas 'destino:' de '## Ficheros'. Lee con
# tolerancia: lo que no se entiende, no se comprueba. Sin plantilla, nada.
function Get-PaquetesFueraDePlantilla([string]$Plan, $Cal) {
  if (-not $Cal -or $Cal.Paquetes.Count -eq 0) { return @() }
  $nombres = New-Object System.Collections.Generic.List[string]
  foreach ($x in (Get-SeccionPlan $Plan 'Piezas comunes')) {
    foreach ($m in [regex]::Matches($x, '(?<![\w.])(?:[a-z][a-z0-9_]*\.)+[A-Z]\w*')) { $nombres.Add($m.Value) }
    foreach ($m in [regex]::Matches($x, '(?<![\w/.])(?:[a-z][a-z0-9_]*/)+[A-Z]\w*')) { $nombres.Add($m.Value) }
  }
  foreach ($x in (Get-SeccionPlan $Plan 'Ficheros')) {
    $m = [regex]::Match($x, 'destino:\s*([^|]*)')
    if (-not $m.Success) { continue }
    $d = @(($m.Groups[1].Value -replace '[`"''*]', '').Trim() -split '\s+')[0]
    if ($d -and $d -ne '-') { $nombres.Add($d) }
  }
  $fuera = [ordered]@{}
  foreach ($n in $nombres) {
    $rel = Get-PaqueteDePlan $n $Cal
    if ($rel -and -not $fuera.Contains($rel) -and -not (Test-PaqueteEnPlantilla $rel $Cal) -and -not (Test-PaqueteEnRepo $rel)) { $fuera[$rel] = $n }
  }
  return @($fuera.Keys | ForEach-Object { "$_ (en $($fuera[$_]))" })
}

# Una llamada a Copilot que solo debe leer (revision previa, consejo, reflexion) y escribir su fichero en .rescate. Si
# toca la PLANTILLA o el ORIGINAL, para (exit 4). Si toca codigo de este repo: si estaba limpio, lo deshace; si no, avisa.
function Invoke-SoloLectura([string]$Log, [string]$Mod, [string]$Esf, [string]$Que) {
  $antes = (Invoke-Git $RepoRoot @('status', '--porcelain')).Salida -join "`n"
  $check = Get-Head $RepoRoot
  $rama = Get-Rama $RepoRoot
  $hp = Get-Huella $PlantillaRoot; $h0 = Get-Huella $LegacyRoot
  $r = Invoke-Copilot $Log $Mod $Esf $Que
  if ((Get-Huella $PlantillaRoot) -ne $hp -or (Get-Huella $LegacyRoot) -ne $h0) {
    Fallo "ALTO: se ha modificado la PLANTILLA o el repo ORIGINAL durante una llamada de solo lectura ($Que). Restauralos antes de seguir."
    exit 4
  }
  $despues = (Invoke-Git $RepoRoot @('status', '--porcelain')).Salida -join "`n"
  if ($despues -ne $antes -or (Get-Head $RepoRoot) -ne $check) {
    if (-not $antes) {
      Undo-Lote $rama $check
      Aviso "La llamada era de solo lectura ($Que) y Copilot ha tocado codigo: lo he deshecho."
    }
    else { Aviso "Ojo: Copilot ha tocado ficheros en una llamada de solo lectura ($Que). Mira git status." }
  }
  return $r
}

# El prompt de la revision previa de un paso, en .rescate/prompt.md. $Correccion: el motivo, si es la repeticion de un plan que no valia.
function Save-PromptPlan([string]$PasoId, $Pend, [string]$Correccion) {
  $l = New-Object System.Collections.Generic.List[string]
  $l.Add("# Tarea: revision previa del paso '$PasoId' (SOLO LECTURA)")
  $l.Add('')
  $l.Add('Vas a preparar el plan de un paso de una migracion a medias de un batch Java 8 a Java 21 con arquitectura hexagonal.')
  $l.Add("No modifiques NINGUN fichero de codigo, ni aqui ni en las referencias. Tu unica salida es crear el fichero .rescate/plan-$PasoId.md en el repositorio actual.")
  $l.Add('')
  foreach ($x in (Get-TextoReferencias)) { $l.Add($x) }
  if ($script:Cal) { foreach ($x in (Get-TextoMapaPaquetes $script:Cal)) { $l.Add($x) } }
  $l.Add('## Lo que se hara despues en este paso (ahora NO lo hagas)')
  $l.Add($TextoPaso[$PasoId])
  $l.Add('')
  $l.Add('## Hallazgos del paso (todos)')
  foreach ($x in $Pend) { $l.Add((Get-LineaHallazgo $x)) }
  $l.Add('')
  $l.Add('## Que tienes que revisar')
  $l.Add('1. Lee entero cada fichero de la lista. Busca quien lo usa: imports, inyeccion, configuracion y tests.')
  $l.Add('2. Lee en la PLANTILLA las clases equivalentes: en que paquete estan, como se llaman y que puertos y adaptadores usan.')
  $l.Add('3. Decide que se hara con cada fichero. Las decisiones tienen que ser coherentes entre si: si varios ficheros necesitan lo mismo (un puerto, un adaptador, una clase de configuracion), se crea UNA sola pieza comun y todos la usan.')
  $l.Add('4. Si algo no se puede resolver sin cambiar el comportamiento, no lo fuerces: apuntalo en Dudas.')
  $l.Add('5. Como se tratan los errores (capturar y seguir, o propagar) es comportamiento: el plan no lo cambia.')
  $l.Add('6. Respeta las dependencias entre capas. ' + $TextoCapas + ' ' + $TextoAdaptadores)
  $l.Add('')
  $l.Add("## Formato de .rescate/plan-$PasoId.md")
  $l.Add("Empieza con la linea: # Plan del paso '$PasoId'")
  $l.Add('Despues, estas cuatro secciones, con estos titulos:')
  $l.Add('- "## Piezas comunes": una linea por cada pieza nueva que van a compartir varios ficheros, con su nombre completo (paquete incluido, uno de la lista de paquetes de la PLANTILLA), que es (puerto, adaptador, configuracion...) y para que sirve. Si no hace falta ninguna, escribe "ninguna".')
  $l.Add('- "## Ficheros": una linea por cada fichero de la lista de hallazgos, asi:')
  $l.Add('  - `ruta/del/Fichero.java` -> que se hace | destino: paquete o clase de destino, o "-" | riesgo: bajo, medio o alto, y por que')
  $l.Add('- "## Orden": en que orden conviene hacerlos y por que (primero lo que otros necesitan).')
  $l.Add('- "## Dudas": lo que deberia decidir una persona. Si no hay, escribe "ninguna".')
  $l.Add('')
  $l.Add('No escribas contrasenas, hosts ni datos reales. No inventes: si no has podido leer un fichero, dilo en Dudas.')
  if ($Correccion) {
    $l.Add('')
    $l.Add('## CORRECCION: tu plan anterior no paso la comprobacion')
    $l.Add($Correccion)
  }
  [System.IO.File]::WriteAllText((Join-Path $Work 'prompt.md'), ($l -join "`n"))
}

# Revision previa de un paso: la IA lee todos los ficheros con hallazgos y la
# plantilla, y escribe el plan. No debe tocar codigo; si lo toca, se deshace.
# Devuelve 'nuevo', 'existente' o '' (no hay plan).
function Invoke-Plan([string]$PasoId, $Hall, [bool]$Forzar) {
  $ruta = Get-RutaPlan $PasoId
  $pend = @($Hall | Where-Object { $_.Cat -eq $PasoId -and $_.Sev -eq 'error' })
  if ($pend.Count -eq 0) { return '' }
  $fichs = @($pend | ForEach-Object { $_.Fichero } | Where-Object { $_ } | Select-Object -Unique)
  $viejo = ''
  if (Test-Path -LiteralPath $ruta) {
    if (-not $Forzar) {
      $falta = @(Get-SinPlan $ruta $fichs)
      if ($falta.Count -eq 0) { Info "Plan del paso '$PasoId': $ruta (ya existia)"; return 'existente' }
      Info "El plan que habia no nombra $($falta.Count) fichero(s) con hallazgos: lo rehago."
    }
    $viejo = [System.IO.File]::ReadAllText($ruta)
    Remove-Item -LiteralPath $ruta -Force
  }
  Save-PromptPlan $PasoId $pend ''

  Info "Revision previa del paso '$PasoId': Copilot lee $($fichs.Count) fichero(s) y la plantilla..."
  [void](Invoke-SoloLectura (Join-Path $Work "plan-$PasoId.log") '' $EsfuerzoPlan "Copilot (revision previa, paso $PasoId)")
  if (-not (Test-Path -LiteralPath $ruta)) {
    if ($viejo) {
      [System.IO.File]::WriteAllText($ruta, $viejo)
      Aviso "Copilot no ha escrito el plan (ver .rescate/plan-$PasoId.log). Me quedo con el que habia."
      return 'existente'
    }
    Aviso "Copilot no ha escrito el plan (ver .rescate/plan-$PasoId.log). Sigo sin plan."
    return ''
  }
  $fuera = @(Get-PaquetesFueraDePlantilla ([System.IO.File]::ReadAllText($ruta)) $script:Cal)
  if ($fuera.Count -gt 0) {
    $lista = $fuera -join '; '
    Info "El plan nombra paquetes que la plantilla no tiene ($lista): lo repito una vez con el motivo."
    $malo = [System.IO.File]::ReadAllText($ruta)
    Remove-Item -LiteralPath $ruta -Force
    Save-PromptPlan $PasoId $pend ("Tu plan anterior nombra paquetes que la PLANTILLA no tiene: $lista. Cada pieza comun y cada destino tiene que estar en un paquete del 'Mapa de paquetes' de arriba: si no hay equivalente, elige el paquete mas parecido o apuntalo en Dudas. Escribe el plan entero otra vez.")
    [void](Invoke-SoloLectura (Join-Path $Work "plan-$PasoId-repeticion.log") '' $EsfuerzoPlan "Copilot (revision previa, paso $PasoId, repeticion)")
    if (-not (Test-Path -LiteralPath $ruta)) {
      [System.IO.File]::WriteAllText($ruta, $malo)
      Aviso "Copilot no ha escrito el plan repetido (ver .rescate/plan-$PasoId-repeticion.log). Me quedo con el primero."
    }
    $fuera = @(Get-PaquetesFueraDePlantilla ([System.IO.File]::ReadAllText($ruta)) $script:Cal)
    if ($fuera.Count -gt 0) { Aviso ('El plan sigue nombrando paquetes que la plantilla no tiene: ' + ($fuera -join '; ') + '. Sigo con el.') }
  }
  $falta = @(Get-SinPlan $ruta $fichs)
  if ($falta.Count -gt 0) { Aviso ('El plan no nombra: ' + (($falta | Select-Object -First 8) -join ', ')) }
  Bien "Plan escrito: $ruta"
  return 'nuevo'
}

# ========================== CONSEJO Y REFLEXION ==========================
# El modelo de las dudas ($script:ModDudas con $script:EsfDudas) hace dos cosas, en llamadas de solo lectura:
# - consejo: ante una duda (las del plan, o un fichero atascado) da 3 opciones, elige una y dice si la puede aplicar el
#   motor (codigo) o la tiene que decidir una persona. Escribe .rescate/consejo-<n>.json.
# - reflexion: tras un intento que no pasa, dice por que y que hacer en el siguiente. Escribe
#   .rescate/reflexion-<paso>-<lote>-<intento>.md.
# Todo queda en .rescate/decisiones.md. Si la llamada falla o lo que escribe no vale, se sigue sin ello.

function Add-Decisiones([string[]]$Lineas) { [System.IO.File]::AppendAllText((Join-Path $Work 'decisiones.md'), (($Lineas -join "`n") + "`n`n")) }

# Si Copilot sale con error sin escribir $Salida, prueba el esfuerzo siguiente (Get-EsfuerzosMenores, la regla del
# preflight). El ultimo probado se queda para las demas llamadas.
function Invoke-Fuerte([string]$Log, [string]$Salida, [string]$Que) {
  $lista = @($script:EsfDudas) + @(Get-EsfuerzosMenores $script:EsfDudas)
  for ($k = 0; $k -lt $lista.Count; $k++) {
    if ($k -gt 0) { Aviso ("  Copilot ha fallado con el esfuerzo '$($lista[$k - 1])' del modelo de las dudas (puede que no lo admita; " + (@($r.Salida) | Select-Object -Last 1) + "): pruebo '$($lista[$k])'.") }
    $script:EsfDudas = $lista[$k]
    $r = Invoke-SoloLectura $Log $script:ModDudas $script:EsfDudas $Que
    if ($r.Codigo -eq 0 -or (Test-Path -LiteralPath $Salida)) { break }
  }
  return $r
}

# '' si el consejo tiene la forma pedida; si no, el motivo (va en la CORRECCION del reintento).
function Test-Consejo($J, [bool]$Una) {
  $d = @($J.dudas | Where-Object { $null -ne $_ })
  if ($d.Count -eq 0) { return 'falta "dudas" con al menos una duda' }
  if ($Una -and $d.Count -ne 1) { return "tiene que traer una sola duda (trae $($d.Count))" }
  foreach ($x in $d) {
    if (-not "$($x.duda)".Trim()) { return 'hay una duda con el texto vacio' }
    $q = "la duda '$($x.duda)'"
    $o = @($x.opciones | Where-Object { $null -ne $_ })
    if ($o.Count -ne 3 -or @($o | Where-Object { "$_".Trim() }).Count -ne 3) { return "$q tiene que tener exactamente 3 opciones no vacias (tiene $($o.Count))" }
    if ("$($x.elegida)" -notmatch '^[1-3]$') { return "en $q, elegida tiene que ser 1, 2 o 3 (es $($x.elegida))" }
    if (-not "$($x.porque)".Trim()) { return "en $q falta el porque" }
    if (@('codigo', 'persona') -notcontains "$($x.tipo)") { return "en $q, tipo tiene que ser codigo o persona (es '$($x.tipo)')" }
  }
  return ''
}

# Una llamada de consejo ($Contexto: las lineas del prompt sobre la duda). Si lo que escribe no vale, se repite una vez
# con el motivo. Devuelve N, Dudas, Modelo y Esfuerzo, o $null (se sigue sin consejo).
function Invoke-Consejo([string[]]$Contexto, [bool]$Una, [string]$Que) {
  $n = 1
  while (Test-Path -LiteralPath (Join-Path $Work "consejo-$n.json")) { $n++ }
  $ruta = Join-Path $Work "consejo-$n.json"
  $motivo = ''
  for ($k = 1; $k -le 2; $k++) {
    $l = @('# Tarea: consejo sobre dudas de una migracion (SOLO LECTURA)', '',
      'Eres el revisor experto de una migracion a medias de un batch Java 8 a Java 21 con arquitectura hexagonal.',
      "No modifiques NINGUN fichero de codigo, ni aqui ni en las referencias. Tu unica salida es crear el fichero .rescate/consejo-$n.json en el repositorio actual.", '')
    $l += @(Get-TextoReferencias) + $Contexto
    $l += @('', '## Que tienes que hacer',
      '1. Lee los ficheros que se nombran, la PLANTILLA y, si lo hay, el plan.',
      '2. Para cada duda da exactamente 3 opciones distintas y realistas, elige la mejor y di por que en una o dos frases.',
      '3. tipo "persona" si la opcion elegida cambia el comportamiento de negocio, sube versiones de framework o del parent, toca credenciales o entornos, o pide informacion que no esta en los repos. Si no, tipo "codigo": la aplica el motor.',
      '', "## Formato de .rescate/consejo-$n.json", 'JSON valido, sin comentarios ni texto alrededor:',
      '{ "dudas": [ { "duda": "...", "opciones": ["...", "...", "..."], "elegida": 1, "porque": "...", "tipo": "codigo" } ] }',
      '- opciones: exactamente 3. elegida: el numero de la opcion (1, 2 o 3). porque: no vacio. tipo: "codigo" o "persona".',
      'No escribas contrasenas, hosts ni datos reales.')
    if ($Una) { $l += 'Una sola duda: la decision que falta para poder arreglar el fichero.' }
    if ($motivo) { $l += @('', '## CORRECCION: tu respuesta anterior no vale', "- $motivo", "Vuelve a escribir .rescate/consejo-$n.json entero.") }
    [System.IO.File]::WriteAllText((Join-Path $Work 'prompt.md'), ($l -join "`n"))
    Info "  Pido consejo al modelo de las dudas ($Que)..."
    $r = Invoke-Fuerte (Join-Path $Work "consejo-$n.log") $ruta "Copilot (consejo, $Que)"
    if (-not (Test-Path -LiteralPath $ruta)) {
      if ($r.Codigo -ne 0) { Aviso "  Copilot ha fallado (codigo $($r.Codigo), ver .rescate/consejo-$n.log): sigo sin consejo."; Write-FinCopilot $r; return $null }
      $motivo = "no has escrito .rescate/consejo-$n.json"
      continue
    }
    $j = $null
    try { $j = [System.IO.File]::ReadAllText($ruta) | ConvertFrom-Json; $motivo = Test-Consejo $j $Una }
    catch { $motivo = 'no es JSON valido: ' + $_.Exception.Message }
    if (-not $motivo) { return [pscustomobject]@{ N = $n; Dudas = @($j.dudas); Modelo = $script:ModDudas; Esfuerzo = $script:EsfDudas } }
    Remove-Item -LiteralPath $ruta -Force
  }
  Aviso "  El consejo no vale ($motivo): sigo sin consejo."
  return $null
}

# Apunta un consejo en decisiones.md: de donde viene y, por duda, las 3 opciones, la elegida, el porque, el tipo y si se
# ha aplicado ($Aplicada: una por duda).
function Write-Consejo($Con, [string]$Origen, [string[]]$Aplicada) {
  $m = $Con.Modelo
  if (-not $m) { $m = 'el que tenga Copilot' }
  $l = @("## Consejo $($Con.N): $Origen ($(Get-Date -Format 'yyyy-MM-dd HH:mm'))", "Modelo: $m | esfuerzo: $($Con.Esfuerzo) | respuesta: .rescate/consejo-$($Con.N).json")
  for ($k = 0; $k -lt $Con.Dudas.Count; $k++) {
    $d = $Con.Dudas[$k]
    $l += @('', "### Duda: $($d.duda)")
    for ($o = 1; $o -le 3; $o++) {
      $t = "$o. " + @($d.opciones)[$o - 1]
      if ($o -eq [int]$d.elegida) { $t += ' (elegida)' }
      $l += $t
    }
    $l += @("Por que: $($d.porque)", "Tipo: $($d.tipo) | Aplicada: $($Aplicada[$k])")
  }
  Add-Decisiones $l
}

# Dudas del plan, con -Auto (sin -Auto las lee la persona al revisar el plan, como siempre). Si el plan tiene Dudas que no
# son 'ninguna' y aun no tiene '## Decisiones', un consejo: las de codigo van al plan en '## Decisiones' (cada lote recibe
# esa seccion); las de persona, a $script:Decidir para el final.
function Invoke-ConsejoPlan([string]$PasoId, $Pend) {
  $ruta = Get-RutaPlan $PasoId
  $texto = [System.IO.File]::ReadAllText($ruta)
  $dudas = @(Get-SeccionPlan $texto 'Dudas' | Where-Object { $_.Trim() })
  if ($dudas.Count -eq 0 -or ($dudas.Count -eq 1 -and $dudas[0] -match '^\W*(ninguna|no hay)\b')) { return }
  if (@($texto -split "`r?`n" | Where-Object { (Get-TituloPlan $_) -eq 'Decisiones' }).Count -gt 0) { return }
  $todas = $dudas -join "`n"
  $fichs = @($Pend | ForEach-Object { $_.Fichero } | Where-Object { $_ } | Select-Object -Unique | Where-Object { $todas -match (Get-RxClase $_) })
  $ctx = @("## Dudas del plan del paso '$PasoId'", "El plan esta en .rescate/plan-$PasoId.md: leelo entero. Resuelve todas sus dudas:") + $dudas
  if ($fichs.Count -gt 0) { $ctx += @('', '## Ficheros que nombran las dudas') + @($fichs | ForEach-Object { "- $_" }) }
  $con = Invoke-Consejo $ctx $false "dudas del plan de '$PasoId'"
  if (-not $con) { return }
  $dec = @('', '## Decisiones', 'Las ha tomado un revisor sobre las Dudas de arriba: siguelas.')
  $apl = @()
  foreach ($d in $con.Dudas) {
    if ($d.tipo -eq 'codigo') { $dec += "- $($d.duda) -> $(Get-Elegida $d) (por que: $($d.porque))"; $apl += 'en el plan' }
    else { $script:Decidir += "[plan de '$PasoId'] $($d.duda) -> recomendada: $(Get-Elegida $d) (por que: $($d.porque))"; $apl += 'no, la decide una persona' }
  }
  $persona = @($apl | Where-Object { $_ -ne 'en el plan' }).Count
  if ($persona -gt 0) { $dec += 'Las demas dudas del plan las decide una persona: no las resuelvas por tu cuenta.' }
  [System.IO.File]::AppendAllText($ruta, (($dec -join "`n") + "`n"))
  Write-Consejo $con "dudas del plan del paso '$PasoId'" $apl
  Info "  Dudas del plan: $($apl.Count - $persona) decidida(s) en '## Decisiones' de $ruta y $persona para una persona (salen al final)."
}

# Consejo para un fichero atascado, despues del modelo de reserva: el fichero, el paso, sus hallazgos, por que no pasaron
# sus lotes y las reflexiones de sus intentos. Una sola duda.
function Invoke-ConsejoAtascado([string]$PasoId, [string]$Fichero, $Hall, [string[]]$Motivos, $Reflexiones) {
  $ctx = @("## Fichero atascado en el paso '$PasoId'", "El script no ha conseguido arreglar $Fichero ni en su lote, ni solo, ni con el modelo de reserva (si lo hay).", '',
    '## Que hay que hacer en el paso', $TextoPaso[$PasoId], '', '## Hallazgos del fichero')
  $ctx += @($Hall | Where-Object { $_.Cat -eq $PasoId -and $_.Sev -eq 'error' -and $_.Fichero -eq $Fichero } | ForEach-Object { Get-LineaHallazgo $_ })
  $ctx += @('', '## Por que no pasaron sus lotes') + @($Motivos | ForEach-Object { "- $_" })
  $ctx += @(Get-TextoReflexiones $Reflexiones $false)
  if (-not $SinPlan -and (Test-Path -LiteralPath (Get-RutaPlan $PasoId))) { $ctx += @('', "El plan del paso esta en .rescate/plan-$PasoId.md.") }
  return (Invoke-Consejo $ctx $true "atascado $Fichero")
}

# Reflexion tras el intento $I del lote $N, que no ha pasado ($Correccion: los NO PASA con su detalle). Recibe el objetivo
# del paso, los hallazgos del lote, el plan, el diff del intento (contra $Check, hasta LineasDiff lineas) y los ficheros
# nuevos. Solo se comprueba la forma: las cuatro secciones con texto. Devuelve Titulo, Texto y Ficheros, o nada.
function Invoke-Reflexion([string]$PasoId, [int]$N, [int]$I, $LoteH, [string[]]$Sel, [string]$Check, [string]$Correccion) {
  $id = "$PasoId-$N-$I"
  $ruta = Join-Path $Work "reflexion-$id.md"
  if (Test-Path -LiteralPath $ruta) { Remove-Item -LiteralPath $ruta -Force }
  $max = [int]$Cfg.LineasDiff
  $diff = @((Invoke-Git $RepoRoot @('-c', 'core.quotepath=off', 'diff', $Check)).Salida)
  if ($diff.Count -gt $max) { $diff = @($diff | Select-Object -First $max) + "... (el diff sigue: $($diff.Count - $max) lineas mas)" }
  $nuevos = @((Invoke-Git $RepoRoot @('-c', 'core.quotepath=off', 'ls-files', '--others', '--exclude-standard')).Salida | Where-Object { $_ })
  $l = @('# Tarea: reflexion sobre un intento que no ha pasado (SOLO LECTURA)', '',
    'Un modelo ha intentado arreglar unos ficheros de una migracion a medias (batch Java 8 a Java 21 con arquitectura hexagonal) y las comprobaciones del script han rechazado el intento. Explica por que y que hay que hacer en el siguiente.',
    "No modifiques NINGUN fichero de codigo, ni aqui ni en las referencias. Tu unica salida es crear el fichero .rescate/reflexion-$id.md en el repositorio actual.", '')
  $l += @(Get-TextoReferencias) + @("## Objetivo del paso '$PasoId'", $TextoPaso[$PasoId], '', '## Hallazgos del lote') + @($LoteH | ForEach-Object { Get-LineaHallazgo $_ })
  $rutaPlan = Get-RutaPlan $PasoId
  if (-not $SinPlan -and (Test-Path -LiteralPath $rutaPlan)) { $l += @('', '## Plan del paso (la parte de este lote)') + @(Get-PlanDelLote ([System.IO.File]::ReadAllText($rutaPlan)) $Sel | ForEach-Object { '> ' + $_ }) }
  $l += @('', '## Por que no ha pasado (lo dicen las comprobaciones del script)', $Correccion, '', '## Lo que cambio el intento (git diff; los cambios siguen en el arbol de trabajo)')
  if ($diff.Count -gt 0) { $l += @('```diff') + $diff + '```' } else { $l += '(ningun cambio en los ficheros que git ya seguia)' }
  if ($nuevos.Count -gt 0) { $l += @('Ficheros nuevos (leelos si hace falta):') + @($nuevos | ForEach-Object { "- $_" }) }
  $l += @('', "## Formato de .rescate/reflexion-$id.md", 'Cuatro secciones con estos titulos, cada una con al menos una linea. Breve y concreto: ficheros, clases, paquetes.',
    '## Que se intento', '## Por que no paso', '## Que hacer ahora', '## Que no hacer')
  [System.IO.File]::WriteAllText((Join-Path $Work 'prompt.md'), ($l -join "`n"))
  Info '  El modelo de las dudas reflexiona sobre el intento...'
  [void](Invoke-Fuerte (Join-Path $Work "reflexion-$id.log") $ruta "Copilot (reflexion, paso $PasoId, lote $N, intento $I)")
  if (-not (Test-Path -LiteralPath $ruta)) { Aviso "  No hay reflexion (ver .rescate/reflexion-$id.log): sigo sin ella."; return }
  $texto = [System.IO.File]::ReadAllText($ruta)
  $falta = @($TitulosReflexion | Where-Object { @(Get-SeccionReflexion $texto $_ | Where-Object { $_.Trim() }).Count -eq 0 })
  if ($falta.Count -gt 0) {
    $trae = @($texto -split "`r?`n" | ForEach-Object { Get-TituloEscrito $_ } | Where-Object { $_ } | Select-Object -First 8)
    $queTrae = 'No trae ningun titulo'
    if ($trae.Count -gt 0) { $queTrae = "Trae los titulos '" + ($trae -join "', '") + "'" }
    Aviso ("  A la reflexion le falta '" + ($falta -join "', '") + "': sigo sin ella. $queTrae (ver .rescate/reflexion-$id.md).")
    return
  }
  Add-Decisiones (@("## Reflexion: paso '$PasoId', lote $N, intento $I ($(Get-Date -Format 'yyyy-MM-dd HH:mm'))", ('Ficheros: ' + ($Sel -join ', ')), "Esfuerzo: $($script:EsfDudas) | fichero: .rescate/reflexion-$id.md", '') + (Convert-Titulos $texto '### $1'))
  return [pscustomobject]@{ Titulo = "Lote $N, intento $I"; Texto = $texto; Ficheros = $Sel }
}

# ================================= PRE =================================
# Saca del ORIGINAL la lista de jobs (el "contrato") para poder comprobar
# despues, sin IA, que no falta ninguno y que todos tienen prueba e2e.
function Invoke-Pre {
  if (-not $LegacyRoot) { Fallo 'El modo pre necesita -Legacy (carpeta del batch original).'; exit 1 }
  Info 'Buscando jobs en el original por texto...'
  $det = Get-JobsPorRegex $LegacyRoot
  $ia = @()
  if (-not $SinIA) {
    if (-not $script:Copilot.Ruta) { Aviso ($script:Copilot.Mensaje + ' Sigo solo con la busqueda por texto.') }
    else {
      $antes = (Invoke-Git $RepoRoot @('status', '--porcelain')).Salida -join "`n"
      $h0 = Get-Huella $LegacyRoot; $hp = Get-Huella $PlantillaRoot
      $tmp = Join-Path $Work 'contrato-ia.json'
      if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
      $l = @(
        '# Tarea: inventario de jobs del batch ORIGINAL (solo lectura)',
        '',
        "Lee el repositorio ORIGINAL en: $LegacyRoot",
        'No modifiques NINGUN fichero de codigo, ni alli ni aqui. Tu unica salida es crear el fichero .rescate/contrato-ia.json en el repositorio actual.',
        '',
        'Busca TODOS los jobs batch que define el original (Spring Batch por Java o por XML, clases con main, scripts que lanzan jobs). Para cada uno:',
        '- nombre: el nombre exacto con el que se lanza el job, literal, tal cual aparece en el codigo.',
        '- definidoEn: ruta relativa del fichero donde se define.',
        '- entrada: que lee (ficheros y formato, tablas, servicios), en una frase.',
        '- salida: que produce (ficheros, tablas, llamadas), en una frase.',
        '',
        'Formato exacto, JSON valido, sin comentarios ni texto alrededor:',
        '{ "jobs": [ { "nombre": "", "definidoEn": "", "entrada": "", "salida": "" } ] }',
        '',
        ('Pistas encontradas por busqueda de texto (comprueba que son jobs y anade los que falten): ' + ((@($det.Keys) | Sort-Object) -join ', ')),
        'No inventes: si dudas de que algo sea un job, no lo incluyas. No incluyas contrasenas, hosts ni datos reales.'
      )
      [System.IO.File]::WriteAllText((Join-Path $Work 'prompt.md'), ($l -join "`n"))
      Info 'Copilot leyendo el original...'
      [void](Invoke-Copilot (Join-Path $Work 'pre.log') '' $EsfuerzoPlan 'Copilot (pre)')
      if ((Get-Huella $LegacyRoot) -ne $h0 -or (Get-Huella $PlantillaRoot) -ne $hp) { Fallo 'ALTO: se ha modificado el ORIGINAL o la PLANTILLA durante el pre. Restauralos antes de seguir.'; exit 4 }
      $despues = (Invoke-Git $RepoRoot @('status', '--porcelain')).Salida -join "`n"
      if ($despues -ne $antes) { Aviso 'Ojo: Copilot ha tocado ficheros de este repo durante el pre (solo debia escribir en .rescate). Mira git status.' }
      if (Test-Path -LiteralPath $tmp) {
        try { $ia = @(([System.IO.File]::ReadAllText($tmp) | ConvertFrom-Json).jobs) } catch { Aviso 'contrato-ia.json no es JSON valido: sigo solo con la busqueda por texto.' }
      }
      else { Aviso 'Copilot no ha escrito .rescate/contrato-ia.json: sigo solo con la busqueda por texto.' }
    }
  }
  # Fusion. Lo que dice la IA solo vale si ese nombre aparece literal en el original.
  $texto = Get-TextoArbol $LegacyRoot
  $jobs = New-Object System.Collections.Generic.List[object]
  $vistos = @{}
  foreach ($j in $ia) {
    if ($null -eq $j) { continue }
    $n = "$($j.nombre)".Trim()
    if (-not $n -or $vistos.ContainsKey($n)) { continue }
    $vistos[$n] = $true
    if ($texto -notmatch ('(?<![\w])' + [regex]::Escape($n) + '(?![\w])')) { Aviso "  descartado '$n': la IA lo propone pero ese nombre no aparece en el original"; continue }
    if ($det.ContainsKey($n)) { $origen = 'texto+ia' } else { $origen = 'ia' }
    $jobs.Add([pscustomobject]@{ nombre = $n; origen = $origen; definidoEn = "$($j.definidoEn)"; entrada = "$($j.entrada)"; salida = "$($j.salida)" })
  }
  foreach ($n in @($det.Keys | Sort-Object)) {
    if ($vistos.ContainsKey($n)) { continue }
    $jobs.Add([pscustomobject]@{ nombre = $n; origen = 'texto'; definidoEn = $det[$n]; entrada = ''; salida = '' })
  }
  $contrato = [pscustomobject]@{ generado = (Get-Date -Format 'yyyy-MM-dd HH:mm'); original = $LegacyRoot; jobs = $jobs.ToArray() }
  [System.IO.File]::WriteAllText((Join-Path $Work 'contrato.json'), (ConvertTo-Json -InputObject $contrato -Depth 5))
  $cfgRepo = Join-Path $Work 'config.json'
  if (-not (Test-Path -LiteralPath $cfgRepo)) { [System.IO.File]::WriteAllText($cfgRepo, (ConvertTo-Json -InputObject ([pscustomobject]@{ PalabrasConfigAntigua = $Cfg.PalabrasConfigAntigua }))) }
  Info ''
  Info "Jobs del original: $($jobs.Count)"
  foreach ($j in $jobs) {
    $linea = ('  {0,-34} [{1}] {2}' -f $j.nombre, $j.origen, $j.definidoEn)
    if ($j.origen -eq 'ia') { Aviso ($linea + '   <- solo lo dice la IA: si es un job de verdad, cambia origen a "confirmado"') } else { Info $linea }
  }
  Info ''
  Info 'UNICA revision manual: comprueba que esa lista es la de jobs reales del batch antiguo.'
  Info ('Si sobra o falta alguno, edita ' + (Join-Path $Work 'contrato.json'))
  Info ('Ajustes propios de este repo (palabras de la config antigua, comandos Maven...): ' + $cfgRepo)
}

# ============================== ATASCADOS ==============================
# Lo que la IA no ha sabido arreglar queda en .rescate/atascados.json (paso, fichero, motivo, huella del contenido del
# fichero, commit en el que se atasco y, si lo hay, el consejo) para no gastar llamadas en el en la pasada siguiente:
# se vuelve a intentar con -Reintentar, si el fichero ha cambiado o si desde entonces hay un commit que no es de un
# lote del script (la pieza que faltaba la puede poner una persona en otro fichero). $script:Atascados (paso ->
# ficheros) es lo que saltan los lotes y Get-SiguientePasoMotor; $script:AtascadosInfo ('paso|fichero' -> entrada) es lo
# que se guarda.
function Get-HuellaFichero([string]$Rel) {
  $p = Join-Ruta $RepoRoot $Rel
  if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return '' }
  return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash
}

function Save-Atascados { [System.IO.File]::WriteAllText((Join-Path $Work 'atascados.json'), (ConvertTo-Json -InputObject @($script:AtascadosInfo.Values) -Depth 6)) }

function Add-Atascado([string]$PasoId, [string]$Fichero, [string]$Motivo, $Duda) {
  if (-not $script:Atascados.ContainsKey($PasoId)) { $script:Atascados[$PasoId] = @() }
  if ($script:Atascados[$PasoId] -notcontains $Fichero) { $script:Atascados[$PasoId] += $Fichero }
  $script:AtascadosInfo["$PasoId|$Fichero"] = [pscustomobject]@{ paso = $PasoId; fichero = $Fichero; motivo = $Motivo; huella = (Get-HuellaFichero $Fichero); commit = (Get-Head $RepoRoot); consejo = $Duda }
}

# Si desde el commit $Desde hay alguno que no es de un lote del script (sin commit apuntado o si git no lo encuentra,
# tambien: mejor gastar un intento que dejar un fichero sin tocar).
function Test-CommitsAjenos([string]$Desde) {
  if (-not $Desde) { return $true }
  $r = Invoke-Git $RepoRoot @('log', '--format=%s', "$Desde..HEAD")
  if ($r.Codigo -ne 0) { return $true }
  return (@($r.Salida | Where-Object { $_ -and $_ -notmatch '^rescate\([\w\-]+\): lote ' }).Count -gt 0)
}

# Al empezar el fix (despues de la foto, que cuenta como commit ajeno): los atascados de pasadas anteriores cuyo
# fichero no ha cambiado y sin commits ajenos desde entonces no se vuelven a intentar (salvo -Reintentar). Los demas
# salen de la lista: si se vuelven a atascar, se apuntan de nuevo.
function Read-Atascados {
  $p = Join-Path $Work 'atascados.json'
  if (-not (Test-Path -LiteralPath $p)) { return }
  try { $todos = @([System.IO.File]::ReadAllText($p) | ConvertFrom-Json | ForEach-Object { $_ }) }
  catch { Aviso 'atascados.json no es JSON valido: lo ignoro.'; return }
  foreach ($a in $todos) {
    $fi = "$($a.fichero)"   # vacio si el hallazgo no es de un fichero (no hay adaptador SFTP...)
    if ($Reintentar -or -not $a.paso -or (Get-HuellaFichero $fi) -ne "$($a.huella)" -or (Test-CommitsAjenos "$($a.commit)")) { continue }
    Add-Atascado $a.paso $fi "$($a.motivo)" $a.consejo
  }
  Save-Atascados
  if ($script:AtascadosInfo.Count -gt 0) { Info "$($script:AtascadosInfo.Count) ficheros atascados de antes: no los reintento (usa -Reintentar)" }
}

# Al acabar: fuera de la lista lo que ya no tiene errores en su paso (lo ha arreglado otro lote, o una persona). Los de
# 'tests' solo si los tests se han ejecutado.
function Remove-AtascadosResueltos {
  if ($null -eq $script:Hall) { return }
  foreach ($k in @($script:AtascadosInfo.Keys)) {
    $a = $script:AtascadosInfo[$k]
    if ($a.paso -eq 'tests' -and -not $script:Build.TestsEjecutados) { continue }
    if (@($script:Hall | Where-Object { $_.Cat -eq $a.paso -and $_.Sev -eq 'error' -and $_.Fichero -eq $a.fichero }).Count -gt 0) { continue }
    $script:AtascadosInfo.Remove($k)
    $script:Atascados[$a.paso] = @($script:Atascados[$a.paso] | Where-Object { $_ -ne $a.fichero })
    if ($script:Atascados[$a.paso].Count -eq 0) { $script:Atascados.Remove($a.paso) }
  }
  Save-Atascados
}

# Lo que dice el script cuando ya no hay paso que arreglar: que no quedan errores, o, si hay atascados, que no quedan
# pasos que arregle solo (lo atascado le toca al usuario y sale en la lista del final).
function Show-SinPasos([string]$Pie) {
  if ($script:Atascados.Count -gt 0) { Info 'No quedan pasos que el script pueda arreglar solo.' }
  else { Bien "No quedan errores. $Pie" }
}

# ============================ INTENTO EN CURSO ============================
# La marca (.rescate/intento-en-curso.json): su ruta, Save-Intento, su borrado y Undo-IntentoCortado, que la lee al arrancar, estan en comun.ps1:
# tambien las usan migracion.ps1 y las rondas de practicas y de reglas.

# El arbol de trabajo de un intento (con los ficheros nuevos, sin lo ignorado) como un commit suelto sobre HEAD, que no esta en ninguna
# rama ni toca el indice ni el arbol. Devuelve su sha, o '' si no se pudo.
function Save-ArbolIntento {
  $idx = Join-Path $Work 'arbol.index'
  $env:GIT_INDEX_FILE = $idx
  try {
    [void](Invoke-Git $RepoRoot @('read-tree', 'HEAD'))
    [void](Invoke-Git $RepoRoot @('add', '-A'))
    $t = Invoke-Git $RepoRoot @('write-tree')
    $c = $null
    if ($t.Codigo -eq 0) { $c = Invoke-Git $RepoRoot @('commit-tree', (($t.Salida -join '').Trim()), '-p', 'HEAD', '-m', 'rescate: arbol de un intento') }
    if (-not $c -or $c.Codigo -ne 0) { Aviso '  No he podido guardar el arbol de este intento: sigo sin el.'; return '' }
    return (($c.Salida -join '').Trim())
  }
  finally {
    Remove-Item Env:GIT_INDEX_FILE -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $idx -Force -ErrorAction SilentlyContinue
  }
}

# Deja el arbol de trabajo como el de un intento guardado: vuelve al commit bueno y pone encima lo del intento (HEAD no cambia).
function Restore-ArbolIntento([string]$Rama, [string]$Check, [string]$Sha) {
  Undo-Lote $Rama $Check
  $r = Invoke-Git $RepoRoot @('read-tree', '--reset', '-u', $Sha)
  if ($r.Codigo -ne 0) { Aviso ('  No he podido volver a ese arbol: ' + ($r.Salida -join ' ')); Undo-Lote $Rama $Check; return }
  [void](Invoke-Git $RepoRoot @('reset', '-q', '--mixed', $Check))
}

$ColumnasIntentos = @('fecha', 'paso', 'lote', 'intento', 'ficheros', 'hallazgos', 'reglas', 'seg_copilot', 'seg_maven', 'resultado', 'puerta')

# Al decidir si un intento pasa: una linea en .rescate/intentos.tsv (con su cabecera si el fichero es nuevo), que tambien suma a los tiempos del paso.
# $SegCopilot: los segundos de las llamadas de Copilot del intento (repeticion incluida); los de Maven son los de $script:SegMaven. $Problemas: lo que
# lo para si no pasa (el primero va en la columna puerta). Nunca para el script: si no puede escribir, avisa una vez por ejecucion.
function Add-Intento([string]$PasoId, [int]$N, [int]$I, $LoteH, $Sel, [double]$SegCopilot, [bool]$Pasa, $Problemas) {
  $t = $script:TiemposPaso
  $t.Intentos++; $t.SegCopilot += $SegCopilot; $t.SegMaven += $script:SegMaven
  $reglas = '-'
  if ($PasoId -eq 'sonar') { $reglas = (@($LoteH | ForEach-Object { (Get-SonarFamilia "$($script:SonarPorFila[$_.Fila].Mensaje)").Familia } | Sort-Object -Unique) -join ';') }
  $resultado = 'no pasa'; $puerta = ''
  if ($Pasa) { $resultado = 'pasa' } else { $puerta = "$(@($Problemas)[0])" }
  Write-FilaIntento @($PasoId, $N, $I, @($Sel).Count, @($LoteH).Count, $reglas, [int][Math]::Round($SegCopilot), [int][Math]::Round($script:SegMaven), $resultado) $puerta
}

# Una linea de .rescate/intentos.tsv: la fecha de ahora, los otros 9 campos de $ColumnasIntentos y la puerta (cortada a 200). Nunca para el script.
function Write-FilaIntento([object[]]$Campos, [string]$Puerta) {
  $fecha = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
  $fila = (@(@($fecha) + @($Campos) | ForEach-Object { Get-CampoTsv "$_" }) + (Get-CampoTsv $Puerta 200)) -join "`t"
  $ruta = Join-Path $Work 'intentos.tsv'
  try {
    if (-not (Test-Path -LiteralPath $ruta)) { $fila = ($ColumnasIntentos -join "`t") + "`n" + $fila }
    [System.IO.File]::AppendAllText($ruta, $fila + "`n", $Utf8)
  }
  catch {
    if (-not $script:IntentosAvisado) { $script:IntentosAvisado = $true; Aviso "No he podido apuntar el intento en .rescate/intentos.tsv ($($_.Exception.Message)): sigo sin apuntar los intentos." }
  }
}

# ============================ TESTS ELEGIDOS Y CONTROL ============================
# En los pasos de PasosTestsElegidos (sonar) cada lote pasa solo los tests ligeros: los de contexto de Spring (los que arrancan el contexto o lanzan el
# job, y los que heredan de ellos) quedan fuera con Surefire -Dsurefire.excludesFile, salvo los que el propio lote toca. La suite entera va en un
# control: cada LotesEntreControles lotes buenos, al final del paso y al empezar si la pasada anterior se corto. La marca refs/rescate/control-ok
# apunta al ultimo commit que paso la suite entera y .rescate/control.json lleva lo que fallaba y cuantos tests corrian entonces.
$RefControl = 'refs/rescate/control-ok'

# Las clases de src/test/java: Nombre, Rel (ruta bajo src/test/java), Padre (de quien hereda) y Ctx ($true si arrancan el contexto de Spring o lanzan un
# job, o heredan de una que si, hasta que no salgan mas).
function Get-TestsDeContexto {
  $base = Join-Ruta $RepoRoot 'src/test/java'
  $rx = '@SpringBootTest|@SpringBatchTest|@SpringJUnitConfig|@ContextConfiguration|SpringExtension|' + $Cfg.LanzaJob
  $cls = @()
  foreach ($f in @(Get-JavaFiles $base)) {
    $t = [System.IO.File]::ReadAllText($f.FullName)
    $m = [regex]::Match($t, '\bclass\s+\w+(?:<[^>{]*>)?\s+extends\s+(\w+)')
    $padre = ''
    if ($m.Success) { $padre = $m.Groups[1].Value }
    $cls += [pscustomobject]@{ Nombre = $f.BaseName; Rel = (Get-Rel $base $f.FullName); Padre = $padre; Ctx = [regex]::IsMatch($t, $rx) }
  }
  do {
    $cambio = $false
    foreach ($c in $cls) {
      if ($c.Ctx -or -not $c.Padre) { continue }
      if (@($cls | Where-Object { $_.Ctx -and $_.Nombre -eq $c.Padre }).Count -gt 0) { $c.Ctx = $true; $cambio = $true }
    }
  } while ($cambio)
  return $cls
}

# Escribe en .rescate/$Nombre una linea por clase de contexto de $Clases, como la entiende excludesFile ('com/acme/FooTest.*'). Devuelve la ruta.
function Write-ExcludesContexto($Clases, [string]$Nombre) {
  $ruta = Join-Path $Work $Nombre
  $lineas = @($Clases | Where-Object { $_.Ctx } | ForEach-Object { $_.Rel -replace '\.java$', '.*' })
  $texto = ''
  if ($lineas.Count -gt 0) { $texto = ($lineas -join "`n") + "`n" }
  [System.IO.File]::WriteAllText($ruta, $texto)
  return $ruta
}

# El excludesFile de un lote: la lista de contexto de todo el paso o, si el lote toca algun test de contexto ($Tocados: sus rutas), otra sin ese test.
function Get-ExcludesLote($Clases, [string[]]$Tocados) {
  $tocadas = @($Clases | Where-Object { $_.Ctx -and $Tocados -contains ('src/test/java/' + $_.Rel) })
  if ($tocadas.Count -eq 0) { return (Join-Path $Work 'tests-de-contexto.txt') }
  return (Write-ExcludesContexto @($Clases | Where-Object { $tocadas -notcontains $_ }) 'tests-de-contexto-lote.txt')
}

# Los tests que fallan en un diagnostico, por su texto ('falla <metodo> en <Clase>').
function Get-FallosTests($Hall) { return @($Hall | Where-Object { $_.Cat -eq 'tests' -and $_.Sev -eq 'error' } | ForEach-Object { "$($_.Detalle)" }) }

function Get-MarcaControl { return ((Invoke-Git $RepoRoot @('rev-parse', '--verify', '-q', $RefControl)).Salida -join '').Trim() }

# Pone la marca en el HEAD y apunta en .rescate/control.json cuantos tests corrian y cuales fallaban en esa suite entera.
function Save-Control([int]$TestsN, [string[]]$Fallos) {
  $head = Get-Head $RepoRoot
  [void](Invoke-Git $RepoRoot @('update-ref', $RefControl, $head))
  $script:Control = [pscustomobject]@{ commit = $head; testsN = $TestsN; fallos = @($Fallos) }
  try { [System.IO.File]::WriteAllText((Join-Path $Work 'control.json'), (ConvertTo-Json -InputObject $script:Control -Depth 3), $Utf8) }
  catch { Aviso "No he podido escribir .rescate/control.json ($($_.Exception.Message)): la marca queda, pero sin lo que fallaba." }
}

# Lo que dejo el ultimo control en verde (control.json) o $null.
function Read-Control {
  $ruta = Join-Path $Work 'control.json'
  if (-not (Test-Path -LiteralPath $ruta)) { return $null }
  try { $o = [System.IO.File]::ReadAllText($ruta) | ConvertFrom-Json } catch { return $null }
  if (-not $o -or -not $o.commit) { return $null }
  return [pscustomobject]@{ commit = "$($o.commit)"; testsN = [int]$o.testsN; fallos = @($o.fallos | ForEach-Object { "$_" }) }
}

# Los commits entre la marca y el HEAD, del mas viejo al mas nuevo: Commit, Asunto y Lote ($true si es el commit de un lote de un paso).
function Get-CommitsDesdeMarca([string]$Marca) {
  $o = @()
  foreach ($l in @((Invoke-Git $RepoRoot @('log', '--reverse', '--format=%H%x09%s', "$Marca..HEAD")).Salida | Where-Object { $_ })) {
    $p = "$l" -split "`t", 2
    $o += [pscustomobject]@{ Commit = $p[0]; Asunto = $p[1]; Lote = [bool]($p[1] -match '^rescate\(\w+\): lote \d+') }
  }
  return $o
}

# La marca vale si esta detras del HEAD y todo lo que hay entre las dos es de lotes de este paso o de controles. Si no, la suite entera de ahora
# (el diagnostico del principio) es el control de partida.
function Test-MarcaVigente([string]$Marca, [string]$PasoId) {
  if ((Invoke-Git $RepoRoot @('merge-base', '--is-ancestor', $Marca, 'HEAD')).Codigo -ne 0) { return $false }
  $rx = '^rescate\((' + [regex]::Escape($PasoId) + '|control)\): '
  return (@(Get-CommitsDesdeMarca $Marca | Where-Object { $_.Asunto -notmatch $rx }).Count -eq 0)
}

# Con $Marca ya sin comprobar, lo dice la consola: hasta donde esta comprobado con la suite entera y cuantos lotes quedan sin comprobar.
function Write-SinComprobar {
  $marca = Get-MarcaControl
  if (-not $marca -or $marca -eq (Get-Head $RepoRoot)) { return }
  $n = @(Get-CommitsDesdeMarca $marca | Where-Object { $_.Lote }).Count
  $corto = ((Invoke-Git $RepoRoot @('rev-parse', '--short=7', $marca)).Salida -join '').Trim()
  Aviso "Paso cortado: comprobado con la suite entera hasta $corto; $n lotes sin comprobar. La siguiente pasada empieza con un control."
}

# Deshace con git revert los commits de $Commits (del mas nuevo al mas viejo) en un solo commit con el mensaje $Mensaje. Con un conflicto lo aborta: el HEAD y
# el arbol quedan como estaban y devuelve $false.
function Undo-LotesGit([string[]]$Commits, [string]$Mensaje) {
  $antes = ((Invoke-Git $RepoRoot @('rev-parse', 'HEAD')).Salida -join '').Trim()
  $r = Invoke-Git $RepoRoot (@('revert', '--no-commit') + $Commits)
  $bien = ($r.Codigo -eq 0)
  if ($bien -and (Invoke-Git $RepoRoot @('diff', '--cached', '--quiet')).Codigo -ne 0) {
    $bien = ((Invoke-Git $RepoRoot (@('commit', '-q', '-m', $Mensaje) + $Cfg.CommitArgs)).Codigo -eq 0)
  }
  if (-not $bien) {
    [void](Invoke-Git $RepoRoot @('revert', '--abort'))
    [void](Invoke-Git $RepoRoot @('reset', '-q', '--hard', $antes))
  }
  return $bien
}

# Las clases de $Clases solas (-Dtest) en la carpeta $Dir: $true si algo falla (o Maven no acaba bien).
function Test-ClasesFallan([string]$Dir, [string[]]$Clases) {
  $rep = Join-Ruta $Dir 'target/surefire-reports'
  if (Test-Path -LiteralPath $rep) { Remove-Item -LiteralPath $rep -Recurse -Force }
  $a = @($Cfg.MvnTests) + @(('-Dtest=' + ($Clases -join ',')), '-Dsurefire.failIfNoSpecifiedTests=false')
  $previos = @(Get-Cambios $Dir)
  $r = Invoke-ContandoMaven { Invoke-MavenTope $Dir $a "Maven ($($Clases.Count) clase(s) sola(s))" (Join-Path $Work 'control-build.log') }
  [void](Remove-Ruido $Dir $previos)
  $hAntes = $script:H
  $script:H = New-Object System.Collections.Generic.List[object]
  $inf = Read-InformesTests $rep
  $script:H = $hAntes
  return [bool]($r.Tope -or $r.Codigo -ne 0 -or $inf.Fallan -gt 0)
}

function Remove-WorktreeControl([string]$Dir) {
  if (Test-Path -LiteralPath $Dir) { [void](Invoke-Git $RepoRoot @('worktree', 'remove', '--force', $Dir)) }
  if (Test-Path -LiteralPath $Dir) { Remove-Item -LiteralPath $Dir -Recurse -Force -ErrorAction SilentlyContinue }
  [void](Invoke-Git $RepoRoot @('worktree', 'prune'))
}

# El primer commit de $Commits (del mas viejo al mas nuevo, el ultimo ya falla) con el que fallan $Clases solas, por biseccion. Cada prueba va en un
# worktree temporal (git worktree add --detach) que se borra al acabar. '' si no puede.
function Find-CulpableControl([string[]]$Commits, [string[]]$Clases) {
  $dir = Join-Path $Work 'control-wt'
  Remove-WorktreeControl $dir
  $creado = $false
  $g = -1; $b = $Commits.Count - 1
  try {
    while ($b - $g -gt 1) {
      $mid = [int][Math]::Floor(($g + $b) / 2)
      if ($creado) { $r = Invoke-Git $dir @('checkout', '-q', '--detach', $Commits[$mid]) }
      else { $r = Invoke-Git $RepoRoot @('worktree', 'add', '-q', '--detach', $dir, $Commits[$mid]); $creado = ($r.Codigo -eq 0) }
      if ($r.Codigo -ne 0) { Aviso ('  No he podido probar el commit ' + $Commits[$mid].Substring(0, 7) + ': ' + ($r.Salida -join ' ')); return '' }
      Info ('  Biseccion: pruebo ' + $Commits[$mid].Substring(0, 7) + ' (' + ($mid + 1) + ' de ' + $Commits.Count + ')...')
      if (Test-ClasesFallan $dir $Clases) { $b = $mid } else { $g = $mid }
    }
  }
  finally { Remove-WorktreeControl $dir }
  return $Commits[$b]
}

# Lo que dice una suite entera frente al ultimo control en verde ($Ctl): Rojo, Motivos, los fallos de ahora (Fallos), los nuevos (Nuevos) y sus clases.
function Get-EvaluacionControl($Hall, $Build, $Ctl) {
  $fallos = @(Get-FallosTests $Hall)
  $nuevos = @($fallos | Where-Object { $Ctl.fallos -notcontains $_ })
  $clases = @($nuevos | ForEach-Object { if ($_ -match ' en ([\w.$]+)$') { $Matches[1] } } | Select-Object -Unique)
  $motivos = @()
  if (-not $Build.Compila) { $motivos += 'el proyecto no compila' }
  if ($nuevos.Count -gt 0) { $motivos += ('fallan tests que no fallaban: ' + (($nuevos | Select-Object -First 3) -join '; ')) }
  if ($Build.TestsEjecutados -and $Build.TestsN -lt $Ctl.testsN) { $motivos += "se ejecutan menos tests que en el ultimo control ($($Ctl.testsN) -> $($Build.TestsN))" }
  return [pscustomobject]@{ Rojo = ($motivos.Count -gt 0); Motivos = $motivos; Fallos = $fallos; Nuevos = $nuevos; Clases = $clases }
}

# Los lotes de $Commits que un control ha revertido: sus ficheros no se vuelven a intentar en esta pasada y sus incidencias de Sonar vuelven a pendientes.
function Set-LotesRevertidos($Lotes, [string]$PasoId, [string]$Motivo) {
  foreach ($l in $Lotes) {
    $fich = @((Invoke-Git $RepoRoot @('diff-tree', '--no-commit-id', '--name-only', '-r', $l.Commit)).Salida | Where-Object { $_ -match '^src/.*\.java$' })
    $script:NoReintentar += $fich
    foreach ($f in @($fich | Select-Object -First 5)) { Info "  ${f}: no se vuelve a intentar en esta pasada ($Motivo)." }
  }
  if ($Sonar -and $PasoId -eq 'sonar') {
    Initialize-SonarBase
    $cambio = $false
    foreach ($b in @($script:SonarBase.Values)) {
      if ($b.resuelta -eq $true -and @($Lotes | Where-Object { $_.Commit -eq "$($b.commit)" }).Count -gt 0) {
        Add-Member -InputObject $b -NotePropertyName resuelta -NotePropertyValue $false -Force
        Add-Member -InputObject $b -NotePropertyName regla -NotePropertyValue '' -Force
        Add-Member -InputObject $b -NotePropertyName commit -NotePropertyValue '' -Force
        $cambio = $true
      }
    }
    if ($cambio) { Save-SonarBase }
  }
}

# Un control: la suite entera en el HEAD frente a lo que fallaba en el ultimo control en verde ($script:Control). $N es el lote tras el que se hace (0 al
# empezar). $Hall y $Build: la suite entera que ya se ha pasado en el HEAD (el diagnostico del principio) y $SegPrevios lo que tardo; sin ellos se pasa ahora.
#   Verde: la marca pasa al HEAD. Rojo: se pasan solas las clases que fallan; si pasan, se repite la suite y, si entonces pasa, es un test inestable.
#   Si no, biseccion entre la marca y el HEAD, git revert del lote culpable (con un conflicto, los lotes desde el, del mas nuevo al mas viejo) y la suite otra vez,
#   hasta ControlRondas veces. Si sigue en rojo, se revierten todos los lotes desde la marca. La suite que sale del control es la del HEAD que queda.
# Devuelve Resultado (verde, revertido N o rojo), Hall y Build (los de la ultima suite entera). Un resultado rojo pone $script:ControlRojo.
function Invoke-Control([string]$PasoId, [int]$N, $Hall = $null, $Build = $null, [double]$SegPrevios = 0) {
  $script:TestsExtra = @()
  $script:SegMaven = $SegPrevios
  $ctl = $script:Control
  $marca = Get-MarcaControl
  $lotes = @(Get-CommitsDesdeMarca $marca | Where-Object { $_.Lote })
  Info ''
  Info "--- Control (tras el lote $N): la suite entera en el HEAD; $($lotes.Count) lote(s) sin comprobar desde la marca ---"
  if ($null -eq $Hall) { Info '  Suite entera (Maven)...'; $Hall = @(Invoke-Diagnostico $true $true); $Build = $script:Build }
  $revertidos = @{}      # commit -> el lote que el control ha revertido
  $ev = Get-EvaluacionControl $Hall $Build $ctl
  $primero = $ev
  $inestable = ''
  $ronda = 0
  while ($ev.Rojo -and -not $inestable) {
    foreach ($m in $ev.Motivos) { Aviso "  Control en rojo: $m." }
    $todo = ($ronda -ge [int]$Cfg.ControlRondas -or $ev.Clases.Count -eq 0)
    if (-not $todo) {
      $ronda++
      if (-not (Test-ClasesFallan $RepoRoot $ev.Clases)) {
        Info '  Solas pasan: repito la suite entera una vez.'
        $Hall = @(Invoke-Diagnostico $true $true); $Build = $script:Build
        $ev = Get-EvaluacionControl $Hall $Build $ctl
        if (-not $ev.Rojo) { $inestable = ($primero.Clases -join ', ') }
        else { $todo = $true }
      }
      else {
        $ventana = @(Get-CommitsDesdeMarca $marca)
        $cul = Find-CulpableControl @($ventana | ForEach-Object { $_.Commit }) $ev.Clases
        $rec = @($ventana | Where-Object { $_.Commit -eq $cul })[0]
        if (-not $cul -or -not $rec.Lote -or $revertidos.ContainsKey($cul)) { $todo = $true }
        else {
          $cuales = $ev.Clases -join ', '
          Aviso "  Control: el lote '$($rec.Asunto)' rompe $cuales en el control: lo revierto."
          $hechos = @($rec)
          $bien = Undo-LotesGit @($cul) "rescate(control): revierto un lote que rompe $cuales"
          if (-not $bien) {
            $desde = [array]::IndexOf(@($ventana | ForEach-Object { $_.Commit }), $cul)
            $hechos = @($ventana[$desde..($ventana.Count - 1)] | Where-Object { $_.Lote -and -not $revertidos.ContainsKey($_.Commit) })
            Aviso "  El revert da conflicto con los lotes que vienen despues: revierto los $($hechos.Count) lote(s) desde ese hasta el HEAD, del mas nuevo al mas viejo."
            [array]::Reverse($hechos)
            $bien = Undo-LotesGit @($hechos | ForEach-Object { $_.Commit }) "rescate(control): revierto los lotes desde uno que rompe $cuales"
          }
          if (-not $bien) { $todo = $true }
          else {
            foreach ($h in $hechos) { $revertidos[$h.Commit] = $h }
            Set-LotesRevertidos $hechos $PasoId "rompe $cuales en el control"
            Info '  Suite entera otra vez (Maven)...'
            $Hall = @(Invoke-Diagnostico $true $true); $Build = $script:Build
            $ev = Get-EvaluacionControl $Hall $Build $ctl
          }
        }
      }
    }
    if ($todo) {
      $ventana = @(Get-CommitsDesdeMarca $marca)
      if ($ventana.Count -eq 0) { Fallo '  Control en rojo y la marca es el HEAD: no hay lotes que revertir.'; break }
      Fallo "  Control: sigue en rojo y no hay un lote que lo explique: revierto todos los lotes desde la marca ($($lotes.Count))."
      [array]::Reverse($ventana)
      if (-not (Undo-LotesGit @($ventana | ForEach-Object { $_.Commit }) 'rescate(control): revierto todos los lotes desde la marca')) { Fallo '  No he podido revertirlos.'; break }
      $nuevos = @($lotes | Where-Object { -not $revertidos.ContainsKey($_.Commit) })
      foreach ($l in $lotes) { $revertidos[$l.Commit] = $l }
      Set-LotesRevertidos $nuevos $PasoId 'el control seguia en rojo'
      Info '  Suite entera otra vez (Maven)...'
      $Hall = @(Invoke-Diagnostico $true $true); $Build = $script:Build
      $ev = Get-EvaluacionControl $Hall $Build $ctl
      break
    }
  }
  if ($inestable) { Aviso "  Control: $inestable es inestable (falla en la suite entera y pasa sola): lo dejo pasar." }
  $resultado = 'verde'
  if ($revertidos.Count -gt 0) { $resultado = "revertido $($revertidos.Count)" }
  $puerta = ''
  if ($primero.Rojo) { $puerta = ($primero.Motivos -join ' ') }
  if ($inestable) { $puerta = "inestable: $inestable" }
  if ($ev.Rojo) {
    $resultado = 'rojo'
    $script:ControlRojo = $true
    Fallo ('  El HEAD no ha pasado la suite entera: ' + ($ev.Motivos -join ' ') + ' La marca se queda en ' + (Get-MarcaControl).Substring(0, 7) + '.')
  }
  else {
    Save-Control $Build.TestsN $ev.Fallos
    Bien "  Control en verde: la marca pasa al HEAD ($((Get-MarcaControl).Substring(0, 7)))."
  }
  Write-FilaIntento @('control', $N, '-', $lotes.Count, $primero.Nuevos.Count, '-', 0, [int][Math]::Round($script:SegMaven), $resultado) $puerta
  $script:TiemposPaso.SegMaven += $script:SegMaven
  Write-Informe $Hall
  return [pscustomobject]@{ Resultado = $resultado; Hall = $Hall; Build = $Build }
}

function Invoke-Fix {
  if (-not $PlantillaRoot -and -not (($Sonar -and $Paso -eq 'sonar') -or $Paso -eq 'cobertura')) { Aviso 'Sin -Plantilla el arreglo va a ciegas. Muy recomendable pasarla.' }

  # --- rama de rescate y foto del estado actual: nada se pierde ---
  # Con worktree ya estamos en su rama rescate/. Solo con -SinWorktree se crea aqui.
  $rama = Get-Rama $RepoRoot
  if ($rama -eq 'HEAD' -or -not $rama) { Fallo 'El repo no esta en una rama (detached HEAD).'; exit 1 }
  if ($rama.StartsWith('rescate/')) { Undo-IntentoCortado $rama }   # antes de la foto: lo de un intento cortado no es del usuario
  else {
    $nueva = 'rescate/' + ($rama -replace '[^\w\.\-]', '-') + '-' + (Get-Date -Format 'yyyyMMdd-HHmm')
    if (-not (Confirmar "Creo la rama '$nueva' desde '$rama' ('$rama' no se toca). Seguir?")) { exit 0 }
    $r = Invoke-Git $RepoRoot @('checkout', '-q', '-b', $nueva)
    if ($r.Codigo -ne 0) { Fallo ('No pude crear la rama: ' + ($r.Salida -join ' ')); exit 1 }
    $rama = $nueva
  }
  $sucio = @((Invoke-Git $RepoRoot @('status', '--porcelain')).Salida | Where-Object { $_ })
  if ($sucio.Count -gt 0) {
    Aviso "Hay $($sucio.Count) cambios sin commit:"
    $sucio | Select-Object -First 15 | ForEach-Object { Info "  $_" }
    if (-not (Confirmar "Los guardo en un commit 'foto' en la rama '$rama' para poder volver atras. Seguir?")) { exit 0 }
    [void](Invoke-Git $RepoRoot @('add', '-A'))
    $r = Invoke-Git $RepoRoot (@('commit', '-q', '-m', 'rescate: foto del estado antes de empezar') + $Cfg.CommitArgs)
    if ($r.Codigo -ne 0) { Fallo ('git commit ha fallado: ' + ($r.Salida -join ' ')); exit 3 }
  }
  if (-not $script:AtascadosLeidos) { Read-Atascados; $script:AtascadosLeidos = $true }

  # --- diagnostico inicial ---
  $script:SegMaven = 0.0   # lo que tarda el diagnostico inicial: si hace de control (tests elegidos), son los segundos de su linea de intentos.tsv
  # Si es el mismo commit del ultimo diagnostico con Maven (el del ultimo lote del paso anterior) y el arbol esta limpio, sirven sus hallazgos.
  $head0 = ((Invoke-Git $RepoRoot @('rev-parse', 'HEAD')).Salida -join '').Trim()
  $cache = $script:HallCache
  if ($Paso -eq 'cobertura') { $script:MedirCobertura = $true }   # el diagnostico inicial ya mide: el paso necesita sus tests y su cobertura
  if ($cache -and $cache.Commit -eq $head0 -and (-not $script:MedirCobertura -or $script:CobCommit -eq $head0) -and @((Invoke-Git $RepoRoot @('status', '--porcelain')).Salida | Where-Object { $_ }).Count -eq 0) {
    Info 'Diagnostico inicial: mismo commit y arbol limpio que en el ultimo diagnostico con Maven: reutilizo sus hallazgos.'
    $hall = @($cache.Hall)
    $script:Build = $cache.Build
  }
  else {
    Info 'Diagnostico inicial (compilando)...'
    $hall = @(Invoke-Diagnostico $true ((-not $SinTests) -or $script:MedirCobertura))
  }
  $script:Hall = $hall
  Write-Informe $hall
  Show-Resumen $hall

  $paso = $Paso
  if (-not $paso) { $paso = Get-SiguientePasoMotor $hall }
  if (-not $paso) { $script:Siguiente = ''; Show-SinPasos 'Revisa los avisos del informe y pasa tu pipeline.'; if ($Sonar) { Write-SonarFaltan }; return }
  if ($paso -ne 'build' -and -not $script:Build.Compila) {
    if ($script:Atascados.ContainsKey('build')) { Fallo "El proyecto no compila y 'build' se ha quedado atascado: no sigo con '$paso'."; $script:Parar = $true; return }
    Fallo "El proyecto no compila: primero hay que hacer -Paso build."; exit 2
  }
  $esSonar = ($paso -eq 'sonar')
  $esCob = ($paso -eq 'cobertura')
  $indep = ($esSonar -or $esCob)   # sonar y cobertura no dependen de los pasos anteriores: no avisan de ellos
  foreach ($c in $Cfg.Orden) {
    if ($c -eq $paso) { break }
    $q = Get-Cuenta $hall $c
    if ($q -gt 0 -and -not $indep) { Aviso "Ojo: quedan $q errores en el paso anterior '$c'." }
  }
  # cobertura: mide con los tests al empezar (una vez por pasada) y apunta el punto de partida del resumen
  if ($esCob) {
    $script:MedirCobertura = $true
    $script:CobHechas = @()
    $script:CobTope = $false
    if (-not $script:Cob -or $script:CobCommit -ne (Get-Head $RepoRoot)) {
      Info 'Midiendo la cobertura (Maven con JaCoCo)...'
      $hall = @(Invoke-Diagnostico $true $true)
      $script:Hall = $hall
    }
    if (-not $script:Build.Compila) { Fallo 'El proyecto no compila: primero hay que hacer -Paso build.'; exit 2 }
    if (-not $script:Build.TestsOk) { Fallo 'Los tests no pasan: sin ellos no se puede medir la cobertura. Primero -Paso tests.'; exit 2 }
    if (-not $script:Cob -or -not $script:Cob.medida) { Fallo "No se ha podido medir la cobertura: $($script:Cob.motivo)"; exit 2 }
    if ($null -eq $script:CobInicial) { $script:CobInicial = $script:Cob.porcentaje }
    Info "Cobertura de partida: $(Format-Pct $script:Cob.porcentaje) % (objetivo $(Format-Pct ([double]$Cfg.CoberturaMinima)) %)."
  }
  # En cada lote se ejecutan los tests (salvo -SinTests); en 'tests', 'e2e' y 'cobertura', siempre.
  $conTests = (Get-ConTests $paso)
  if ($conTests -and $script:Build.Compila -and -not $script:Build.TestsEjecutados) { $hall = @(Invoke-Diagnostico $true $true) }
  $loteEf = $Lote
  if ($Cfg.PasosDeUnoEnUno -contains $paso) { $loteEf = 1 }
  Info ''
  Info "=== Paso '$paso' en lotes de $loteEf ==="
  if ($esSonar) { Write-SonarPorFamilia @($hall | Where-Object { $_.Cat -eq 'sonar' -and $_.Sev -eq 'error' }) }

  # --- revision previa: un plan para todo el paso, antes del primer lote ---
  if (-not $SinPlan -and ($Cfg.PasosConPlan -contains $paso)) {
    $plan = Invoke-Plan $paso $hall $false
    if ($plan -and $Auto) { Invoke-ConsejoPlan $paso @($hall | Where-Object { $_.Cat -eq $paso -and $_.Sev -eq 'error' }) }
    if ($plan -eq 'nuevo' -and -not $Auto) {
      $resp = Read-Host 'Lee el plan (puedes corregirlo). [Enter] seguir con los lotes | n = parar aqui'
      if ($resp -eq 'n') { $script:Parar = $true; return }
    }
  }

  $unoAUno = @{}       # ficheros de un lote deshecho que se reintentan de uno en uno: los demas vuelven al tamano del paso
  $mejorDe = @{}       # fichero -> el mejor intento de su ultimo lote deshecho, si compilaba y bajaba los hallazgos del paso (el escalon siguiente parte de su arbol)
  $planB = @{}
  $consejoDe = @{}     # fichero atascado -> el consejo (de codigo) para su ultimo intento
  $motivos = @{}       # fichero -> por que no pasaron sus lotes (para el consejo)
  $reflexiones = @()   # las reflexiones del paso (Titulo, Texto, Ficheros)
  $segInicial = $script:SegMaven
  $script:TiemposPaso = @{ Intentos = 0; SegCopilot = 0.0; SegMaven = 0.0 }   # lo que suman los intentos de esta pasada (Add-Intento)
  # tests elegidos: con tests de contexto, cada lote pasa solo los ligeros (si todos son de contexto, ninguno) y la suite entera va en un control. Sin tests de contexto cada lote
  # ya pasa la suite entera: no hay control y la marca se mueve con cada lote bueno. El diagnostico de arriba es la suite entera del HEAD: hace de control.
  $script:TestsExtra = @(); $script:NoReintentar = @()
  $marcaActiva = (($Cfg.PasosTestsElegidos -contains $paso) -and $conTests)
  $elegidos = $false
  $clasesTest = @()
  $lotesDesdeControl = 0
  $ultimoLote = 0
  if ($marcaActiva) {
    $clasesTest = @(Get-TestsDeContexto)
    $nCtx = @($clasesTest | Where-Object { $_.Ctx }).Count
    $elegidos = ($nCtx -gt 0)
    $marca = Get-MarcaControl
    $previo = Read-Control
    $vigente = [bool]($marca -and $previo -and $previo.commit -eq $marca -and (Test-MarcaVigente $marca $paso))
    if ($marca -and -not $vigente) { Info 'La marca del ultimo control ya no vale (la rama tiene commits que no son de este paso): la pongo en el HEAD.' }
    if ($elegidos) {
      [void](Write-ExcludesContexto $clasesTest 'tests-de-contexto.txt')
      Info "Tests elegidos: cada lote pasa las $($clasesTest.Count - $nCtx) clases de test ligeras y deja fuera las $nCtx de contexto (lista: .rescate/tests-de-contexto.txt); la suite entera va en un control cada $($Cfg.LotesEntreControles) lotes y al final."
    }
    if ($elegidos -and $vigente -and $marca -ne (Get-Head $RepoRoot)) {
      $script:Control = $previo
      $sin = @(Get-CommitsDesdeMarca $marca | Where-Object { $_.Lote }).Count
      Aviso "La pasada anterior se corto con $sin lote(s) sin comprobar con la suite entera: empiezo con un control."
      $res = Invoke-Control $paso 0 $hall $script:Build $segInicial
      $hall = $res.Hall
    }
    else { Save-Control $script:Build.TestsN (Get-FallosTests $hall) }
  }
  $completo = $false   # el paso ha llegado a su final sin cortarse (con tests elegidos, si no, el finally dice hasta donde esta comprobado)
  try {
  for ($n = 1; $n -le $MaxLotes -and -not $script:ControlRojo; $n++) {
    $pend = @($hall | Where-Object { $_.Cat -eq $paso -and $_.Sev -eq 'error' })
    if ($pend.Count -eq 0) { break }
    $stuck = @()
    if ($script:Atascados.ContainsKey($paso)) { $stuck = @($script:Atascados[$paso]) }
    $fichs = @($pend | ForEach-Object { $_.Fichero } | Select-Object -Unique | Where-Object { $stuck -notcontains $_ -and $script:CobHechas -notcontains $_ -and $script:NoReintentar -notcontains $_ })
    $cand = @($fichs | Select-Object -Skip $Saltar)
    $tam = $loteEf
    if ($cand.Count -gt 0 -and $unoAUno.ContainsKey($cand[0])) { $tam = 1 }
    $sel = @($cand | Select-Object -First $tam)
    if ($sel.Count -eq 0) { break }
    if ($esCob -and $script:CobHechas.Count -ge [int]$Cfg.CoberturaClasesMax) {
      $script:CobTope = $true
      $u = [int]$Cfg.CoberturaClasesMax
      Info ''
      Aviso ("Tope de gasto: $u " + $(if ($u -eq 1) { 'clase' } else { 'clases' }) + " en esta pasada (CoberturaClasesMax); las que quedan no se intentan.")
      break
    }
    # el intento con el consejo va con -Modelo, una sola vez y sin reflexion (despues no hay otro)
    $conIntento = ($sel.Count -eq 1 -and $consejoDe.ContainsKey($sel[0]))
    $mod = ''; $duda = $null; $intentos = $MaxIntentos
    if ($conIntento) { $duda = $consejoDe[$sel[0]].Dudas[0]; $intentos = 1 }
    elseif ($sel.Count -eq 1 -and $planB.ContainsKey($sel[0])) { $mod = $ModeloB }
    $reflexionar = ($Cfg.Reflexionar -ne 'nunca' -and -not $conIntento)
    $escalon = ($sel.Count -eq 1 -and ($unoAUno.ContainsKey($sel[0]) -or $planB.ContainsKey($sel[0]) -or $conIntento))   # de uno en uno, reserva o consejo
    $falloAntes = $null   # la forma del fallo del intento anterior de este lote
    $buildAntes = $script:Build
    $loteH = @($pend | Where-Object { $sel -contains $_.Fichero })
    $antes = @{}
    foreach ($c in $Cfg.Orden) { $antes[$c] = Get-Cuenta $hall $c }
    $antes['calidad'] = Get-Cuenta $hall 'calidad'
    # los errores que ya habia, para reconocerlos si el intento mueve su fichero
    $hallAntes = @{}
    foreach ($x in @($hall | Where-Object { $_.Sev -eq 'error' })) { $hallAntes[(Get-ClaveHallazgo $x)] = $true }
    $antesCompila = $script:Build.Compila
    $cobAntes = $script:Cob   # la medida del commit bueno: el lote la compara con la de cada intento
    $check = ((Invoke-Git $RepoRoot @('rev-parse', 'HEAD')).Salida -join '').Trim()
    Info ''
    Info "--- Lote $n : $($loteH.Count) hallazgo(s) en $($sel.Count) fichero(s); pendientes del paso: $($pend.Count) ---"
    $sel | ForEach-Object { Info "  $_" }

    $ok = $false; $correccion = ''; $hall2 = @(); $blandos = @(); $problemas = @()
    $sinCambios = $false   # sonar: el modelo ha dejado todo el lote con su motivo y no hay nada que guardar
    $detalle = @(); $rutaCorr = ''   # los del ultimo intento que no paso (para el aviso del lote deshecho y para atascados.md)
    $g0 = Get-Guardas   # una vez por lote: los reintentos se comparan con el estado bueno
    Save-Intento $paso $n $check $sel $hallAntes   # hasta que el lote se da por bueno o se deshace: si el script se corta, el arranque lo deshace
    # el mejor intento del lote que no ha pasado: Sha del arbol, Peso (Problemas y Nuevos), Correccion, Intento, Lote, Base (el commit bueno), Sirve, Ref
    $mejor = $null
    if ($sel.Count -eq 1 -and $mejorDe.ContainsKey($sel[0])) {
      $ini = $mejorDe[$sel[0]]
      if ($ini.Base -eq $check) {   # si la rama ha avanzado desde que se guardo, ese arbol ya no vale
        $mejor = $ini
        Info "  Parto del mejor intento de antes ($($ini.Ref)): su arbol ya esta puesto."
        Restore-ArbolIntento $rama $check $ini.Sha
        $correccion = $ini.Correccion
      }
      else { $mejorDe.Remove($sel[0]) }
    }
    for ($i = 1; $i -le $intentos; $i++) {
      $detalle = @(); $rutaCorr = ''
      $script:SegMaven = 0.0   # los segundos de Maven de este intento (Invoke-ContandoMaven); Add-Intento los apunta
      $refl = @($reflexiones | Where-Object { @($_.Ficheros | Where-Object { $sel -contains $_ }).Count -gt 0 })
      [System.IO.File]::WriteAllText((Join-Path $Work 'prompt.md'), (New-Prompt $paso $loteH $correccion $duda $refl))
      Info "  Copilot trabajando (intento $i de $intentos)..."
      $estadoAntes = ((Invoke-Git $RepoRoot @('status', '--porcelain', '--untracked-files=all')).Salida -join "`n")
      $esf = ''
      if ($i -ge 2 -or $escalon) { $esf = Get-EsfuerzoReintento }
      $rc = Invoke-Copilot (Join-Path $Work "lote-$paso-$n-$i.log") $mod $esf "Copilot (paso $paso, lote $n, intento $i)"
      $segCop = $rc.Segundos
      # pasado el tope (Copilot se ha parado y la consola ya lo ha dicho) el intento se evalua tal cual: ni se repite ni cuenta como un fallo de Copilot
      if ($rc.Codigo -ne 0 -and -not $rc.Tope) {
        Aviso "  Copilot termino con codigo $($rc.Codigo) (ver .rescate/lote-$paso-$n-$i.log)"; Write-FinCopilot $rc
        # un fallo de Copilot sin tocar nada no es un intento del modelo: se repite la llamada una vez
        $nada = (((Invoke-Git $RepoRoot @('rev-parse', 'HEAD')).Salida -join '').Trim() -eq $check) -and (((Invoke-Git $RepoRoot @('status', '--porcelain', '--untracked-files=all')).Salida -join "`n") -eq $estadoAntes)
        if ($nada) {
          Aviso '  No ha cambiado nada: repito la llamada una vez (no cuenta como intento).'
          # si iba con el esfuerzo de los reintentos, puede que el modelo no lo admita: se prueba el siguiente (la regla de siempre) y se queda
          $menor = @(); if ($esf) { $menor = @(Get-EsfuerzosMenores $esf) }
          if ($menor.Count -gt 0) {
            Aviso "  Copilot ha fallado con el esfuerzo '$esf' de los reintentos (puede que el modelo no lo admita): pruebo '$($menor[0])'."
            $esf = $menor[0]; $script:EsfReintento = $esf
          }
          $rc = Invoke-Copilot (Join-Path $Work "lote-$paso-$n-$i-repeticion.log") $mod $esf "Copilot (paso $paso, lote $n, intento $i, repeticion)"
          $segCop += $rc.Segundos
          if ($rc.Codigo -ne 0 -and -not $rc.Tope) { Aviso "  Copilot termino otra vez con codigo $($rc.Codigo) (ver .rescate/lote-$paso-$n-$i-repeticion.log)"; Write-FinCopilot $rc }
        }
      }

      # -- guardas duras: si saltan, no hay reintento --
      $g1 = Get-Guardas
      if ($g1.Plantilla -ne $g0.Plantilla -or $g1.Legacy -ne $g0.Legacy) {
        Undo-Lote $rama $check
        Remove-Intento
        Fallo 'ALTO: se ha modificado la PLANTILLA o el repo ORIGINAL. He deshecho el lote en este repo.'
        Fallo 'Revisa esas carpetas con git status y restauralas antes de seguir.'
        exit 4
      }
      $ramaAhora = ((Invoke-Git $RepoRoot @('rev-parse', '--abbrev-ref', 'HEAD')).Salida -join '').Trim()
      if ($ramaAhora -ne $rama) { $problemas = @('Copilot cambio de rama.'); Add-Intento $paso $n $i $loteH $sel $segCop $false $problemas; break }
      $head = ((Invoke-Git $RepoRoot @('rev-parse', 'HEAD')).Salida -join '').Trim()
      if ($head -ne $check) { [void](Invoke-Git $RepoRoot @('reset', '-q', '--mixed', $check)) }   # si hizo commit, lo deshago y conservo los cambios
      if ($esSonar) { Read-SonarSinArreglar $loteH }   # lo que el modelo deja con motivo no cuenta para bajar ni se reintenta

      $cambios = @((Invoke-Git $RepoRoot @('status', '--porcelain', '--untracked-files=all')).Salida | Where-Object { $_ })
      if ($cambios.Count -eq 0 -and $esSonar -and @($loteH | Where-Object { -not $script:SonarBase["$($_.Fila)"].dejada }).Count -eq 0) {
        # el modelo ha dejado con motivo todo lo del lote: no hay nada que arreglar ni que guardar
        $sinCambios = $true
        $problemas = @()
        $hall2 = @(Invoke-Diagnostico $false $false)
        $script:Build = $buildAntes
        $ok = $true
        Add-Intento $paso $n $i $loteH $sel $segCop $true @()
        break
      }
      if ($cambios.Count -eq 0) {
        $problemas = @('No has cambiado ningun fichero.')
        Add-Intento $paso $n $i $loteH $sel $segCop $false $problemas
        $correccion = '- No has cambiado ningun fichero. Resuelve los hallazgos del lote.'
        $rutaCorr = Save-CorreccionIntento $paso $n $i $sel $correccion
        $falloAhora = Get-ClaveFallo $problemas @()
        if ($reflexionar -and ($Cfg.Reflexionar -eq 'siempre' -or ($falloAntes -and (Test-FalloRepetido $falloAntes $falloAhora)))) { $reflexiones += @(Invoke-Reflexion $paso $n $i $loteH $sel $check $correccion) }
        $falloAntes = $falloAhora
        continue
      }

      # -- puertas: decide el script, no la IA --
      $problemas = @(); $blandos = @()
      if ($g1.Tests -lt $g0.Tests) { $problemas += "Has borrado tests ($($g0.Tests) -> $($g1.Tests) ficheros). Restauralos." }
      if ($g1.Metodos -lt $g0.Metodos) { $problemas += "Has borrado $($g0.Metodos - $g1.Metodos) metodos de test ($($g0.Metodos) -> $($g1.Metodos)). Restauralos." }
      if ($g1.Desactivados -gt $g0.Desactivados) { $problemas += 'Has desactivado tests con @Disabled/@Ignore. Quitalo.' }
      if ($g1.Aserciones -lt $g0.Aserciones) { $blandos += "hay menos aserciones en los tests ($($g0.Aserciones) -> $($g1.Aserciones))" }
      # cuenta de todo el repo: llevar un catch a otro fichero no la baja
      $catchMenos = @()
      if ($g1.Catch -lt $g0.Catch) {
        $problemas += "Has quitado $($g0.Catch - $g1.Catch) catch ($($g0.Catch) -> $($g1.Catch)). El original sigue tras esos errores: manten el mismo tratamiento."
        $catchMenos = @($g0.CatchDe.Keys | Sort-Object | Where-Object { [int]$g1.CatchDe[$_] -lt $g0.CatchDe[$_] } | ForEach-Object { "  - $_ - catch: $($g0.CatchDe[$_]) -> $([int]$g1.CatchDe[$_])" })
      }
      $tocados = @($cambios | ForEach-Object { ($_.Substring(3) -replace '^"|"$', '') })
      # solo un aviso: lo que un pom roto haga a los tests ya lo cazan los informes de surefire (Invoke-Build) y la puerta de tests ejecutados; bloquearlo pararia lotes legitimos
      if ($paso -ne 'build' -and ($tocados -contains 'pom.xml')) { $blandos += 'ha tocado pom.xml' }
      $fuera = @($tocados | Where-Object { -not $_.StartsWith('src/') -and $_ -ne 'pom.xml' })
      if ($fuera.Count -gt 0) { $blandos += ('ha tocado ficheros fuera de src: ' + (($fuera | Select-Object -First 6) -join ', ')) }

      # sonar y cobertura: lo que el intento no puede hacer (ficheros, tests, diff). Si ya incumple algo, el intento no vale y Maven no cambia nada.
      $reglasMal = @()
      if ($esSonar) { $reglasMal = @(Get-SonarProblemas $cambios $check $loteH); $problemas += $reglasMal }
      if ($esCob) { $reglasMal = @(Get-CoberturaProblemas $tocados $check $loteH); $problemas += $reglasMal }
      if ($reglasMal.Count -gt 0) {
        Info '  Sin Maven: el intento ya incumple las reglas del paso.'
        $hall2 = @(Invoke-Diagnostico $false $false)
      }
      else {
        Info '  Comprobando (Maven)...'
        if ($elegidos) { $script:TestsExtra = @('-Dsurefire.excludesFile=' + (Get-ExcludesLote $clasesTest $tocados)) }
        try { $hall2 = @(Invoke-Diagnostico $true $conTests) }
        finally { $script:TestsExtra = @() }
      }
      $d = Get-Cuenta $hall2 $paso
      $antesPaso = $antes[$paso]
      if ($esSonar) { $antesPaso -= (Get-SonarDejadas $loteH) }   # las dejadas con motivo no cuentan para bajar
      if (-not $script:Build.Compila -and ($paso -ne 'build' -or $antesCompila)) { $problemas += 'El proyecto no compila.' }
      if (-not $esCob -and $d -ge $antesPaso) { $problemas += "Los hallazgos de '$paso' no han bajado ($antesPaso -> $d)." }
      $empeorados = @()   # los pasos que el intento ha empeorado: sus hallazgos nuevos salen en el detalle
      foreach ($c in $Cfg.Orden) {
        if ($c -eq $paso) { break }
        # sonar vale para cualquier repo Java: build, tests, hexagonal (reglas del codigo) y calidad (la comprueba despues, con su propio aviso) cuentan siempre;
        # la colocacion (estructura, ficheros, config, paridad, e2e) solo si hay plantilla
        if ($indep -and $c -eq 'calidad') { continue }
        if ($indep -and -not $PlantillaRoot -and @('estructura', 'ficheros', 'config', 'paridad', 'e2e') -contains $c) { continue }
        if ($elegidos -and $c -eq 'tests') { continue }   # con tests elegidos no se comparan cuentas de suites distintas: va por nombre, mas abajo
        $q = Get-Cuenta $hall2 $c
        if ($q -gt $antes[$c]) { $problemas += "Has empeorado el paso anterior '$c' ($($antes[$c]) -> $q hallazgos)."; $empeorados += $c }
      }
      $ft = Get-Cuenta $hall2 'tests'
      # con tests elegidos el lote pasa solo los ligeros: lo que cuenta es un test que fallaba en el ultimo control en verde y que ahora falla (por su texto);
      # que se ejecuten menos tests que antes se mira en el control
      if ($elegidos) {
        $rotos = @(Get-FallosTests $hall2 | Where-Object { $script:Control.fallos -notcontains $_ })
        if ($rotos.Count -gt 0) { $problemas += ('Falla un test que no fallaba en el ultimo control: ' + (($rotos | Select-Object -First 3) -join '; ') + '.') }
      }
      # sin 'tests' en Orden no hay cuenta de antes: no se compara
      elseif ($conTests -and $paso -ne 'tests' -and $antes.ContainsKey('tests') -and $ft -gt $antes['tests']) { $problemas += "Hay mas tests fallando que antes ($($antes['tests']) -> $ft)." }
      # con tests antes y despues, no se ejecutan menos: borrar, saltar (@DisabledOnOs, assumeTrue) o excluir un test baja los fallos pero tambien los que corren
      if ($conTests -and -not $elegidos -and $buildAntes.TestsEjecutados -and $script:Build.TestsEjecutados -and $script:Build.TestsN -lt $buildAntes.TestsN) {
        $problemas += "Se ejecutan menos tests que antes ($($buildAntes.TestsN) -> $($script:Build.TestsN)). No borres, saltes ni excluyas tests."
      }
      # el codigo nuevo sale ya con Javadoc y sin malas practicas: la cuenta de calidad no sube
      $qc = Get-Cuenta $hall2 'calidad'
      if ($paso -ne 'calidad' -and $qc -gt $antes['calidad']) {
        $problemas += "Tu codigo anade hallazgos de calidad ($($antes['calidad']) -> $qc). Lo que escribas lleva Javadoc y sigue las reglas de calidad."
        $empeorados += 'calidad'
      }
      # cobertura: (P2) los tests de la clase pasan CoberturaRepeticiones veces seguidas y (P3) su cobertura sube sin que baje el total.
      # Solo si lo demas va bien: cada comprobacion es un Maven.
      $cobSube = $false; $cobDetalle = @()
      if ($esCob -and $problemas.Count -eq 0) {
        $claseCob = [System.IO.Path]::GetFileNameWithoutExtension($sel[0])
        $rep = Test-CoberturaRepeticiones $claseCob
        if ($rep) { $problemas += $rep.Motivo; $cobDetalle = @($rep.Detalle) }
        else {
          $c1 = $script:Cob
          if (-not $script:CobFresca -or -not $c1 -or -not $c1.medida) { $problemas += "No he podido medir la cobertura tras tu intento: $($c1.motivo)" }
          else {
            $a = Get-CoberturaDeFichero $cobAntes $sel[0]
            $b = Get-CoberturaDeFichero $c1 $sel[0]
            if (-not $b -or -not $a -or $b.Cubiertas -le $a.Cubiertas) {
              $txt = '?'
              if ($a -and $b) { $txt = "$($a.Cubiertas)/$($a.Total) -> $($b.Cubiertas)/$($b.Total) lineas" }
              $problemas += "La cobertura de $claseCob no sube ($txt). Tus tests tienen que ejecutar lineas que hoy no ejecuta ninguno: mira las lineas sin cubrir del prompt."
            }
            else {
              $cobSube = $true
              if ($c1.cubiertas -lt $cobAntes.cubiertas) { $problemas += "La cobertura total baja ($($cobAntes.cubiertas) -> $($c1.cubiertas) lineas cubiertas): tu cambio ha dejado sin cubrir lineas que antes cubria un test. Restaura lo que cambiaste de los otros tests." }
            }
          }
        }
      }
      $mejoraPaso = ($d -lt $antesPaso)
      if ($esCob) { $mejoraPaso = $cobSube }
      $nuevos = @(Get-HallazgosNuevos $hall2 $empeorados $hallAntes | Select-Object -First 20)

      Add-Intento $paso $n $i $loteH $sel $segCop ($problemas.Count -eq 0) $problemas
      if ($problemas.Count -eq 0) { $ok = $true; break }
      $problemas | ForEach-Object { Aviso "  NO PASA: $_" }
      # lo del paso en los ficheros del lote y en los que el intento ha tocado o creado (un fichero movido deja un hallazgo nuevo en la ruta nueva),
      # y lo nuevo de los pasos que ha empeorado (y de calidad)
      $detalle = @((@($nuevos) + @($hall2 | Where-Object { $_.Sev -eq 'error' -and (
                ($_.Cat -eq 'build' -and $_.Detalle -match '^(no compila|el build falla)') -or
                ($_.Cat -eq 'tests' -and $conTests) -or
                ($_.Cat -eq $paso -and (($sel -contains $_.Fichero) -or ($tocados -contains $_.Fichero)))) } | Select-Object -First 20)) | ForEach-Object { '  ' + (Get-LineaHallazgo $_) } | Select-Object -Unique) + $catchMenos + $cobDetalle
      if ($reglasMal.Count -gt 0) { $detalle += ('  - ficheros que has tocado: ' + (($tocados | Select-Object -First 12) -join ', ')) }
      $correccion = ((@($problemas | ForEach-Object { "- $_" }) + @('Detalle:') + $detalle) -join "`n")
      # por pantalla, lo que se ha roto primero; el resto, y la correccion completa, en el fichero del intento
      $rutaCorr = Save-CorreccionIntento $paso $n $i $sel $correccion
      @(Get-LineasDetalle $detalle $rutaCorr) | ForEach-Object { Aviso $_ }
      $falloAhora = Get-ClaveFallo $problemas $nuevos
      if ($reflexionar -and ($Cfg.Reflexionar -eq 'siempre' -or ($falloAntes -and (Test-FalloRepetido $falloAntes $falloAhora)))) { $reflexiones += @(Invoke-Reflexion $paso $n $i $loteH $sel $check $correccion) }
      $falloAntes = $falloAhora
      # el mejor intento, con una cuenta: los NO PASA y, con los mismos, los hallazgos nuevos. Uno peor se descarta antes del siguiente.
      $peso = $problemas.Count * 100 + $nuevos.Count
      if (-not $mejor -or $peso -le $mejor.Peso) {
        $sha = Save-ArbolIntento
        if ($sha) {
          $mejor = @{ Sha = $sha; Peso = $peso; Problemas = $problemas.Count; Nuevos = $nuevos.Count; Correccion = $correccion; Intento = $i; Lote = $n; Base = $check; Ref = ''
            Sirve = ($script:Build.Compila -and $reglasMal.Count -eq 0 -and $mejoraPaso) }
        }
      }
      elseif ($i -lt $intentos) {
        $cual = "el intento $($mejor.Intento)"
        if ($mejor.Lote -ne $n) { $cual += " del lote $($mejor.Lote)" }
        Aviso "  El intento $i es peor que $cual ($($problemas.Count) NO PASA y $($nuevos.Count) hallazgos nuevos, frente a $($mejor.Problemas) y $($mejor.Nuevos)): vuelvo a su arbol."
        Restore-ArbolIntento $rama $check $mejor.Sha
        $correccion = $mejor.Correccion
      }
    }

    if (-not $ok) {
      # Nada se queda a medias: el arbol del mejor intento se guarda en una ref (ni rama ni commit de la rama) y se deshace.
      $refMejor = ''
      if ($mejor) {
        $refMejor = "refs/rescate/$paso-$n"
        [void](Invoke-Git $RepoRoot @('update-ref', $refMejor, $mejor.Sha))
      }
      Undo-Lote $rama $check
      Remove-Intento   # la marca se va cuando el lote ya esta deshecho, no antes
      $script:Build = $buildAntes
      if ($esSonar) { $script:SonarBase = $null }   # las dejadas de un lote que no pasa no valen: la base se vuelve a leer del disco
      if ($esCob) { $script:Cob = $cobAntes }   # la medida del intento deshecho no vale
      Aviso "Lote $n DESHECHO: no paso las comprobaciones tras $intentos intento(s)."
      $problemas | ForEach-Object { Aviso "  - $_" }
      @(Get-LineasDetalle $detalle $rutaCorr) | ForEach-Object { Aviso $_ }
      if ($rutaCorr) { Aviso "  Correccion completa del ultimo intento: $rutaCorr" }
      if ($refMejor) { Aviso "  El mejor intento esta guardado en git: $refMejor (para verlo: git diff $refMejor^ $refMejor)." }
      # el escalon siguiente parte de ese arbol si compilaba y bajaba los hallazgos del paso; si no, del commit bueno
      foreach ($x in $sel) {
        if ($mejor -and $mejor.Sirve) { $mejorDe[$x] = @{ Sha = $mejor.Sha; Peso = $mejor.Peso; Problemas = $mejor.Problemas; Nuevos = $mejor.Nuevos; Correccion = $mejor.Correccion; Intento = $mejor.Intento; Lote = $mejor.Lote; Base = $check; Ref = $refMejor; Sirve = $true } }
        else { $mejorDe.Remove($x) }
      }
      $conMod = ''
      if ($mod) { $conMod = ", con $mod" }
      foreach ($f in $sel) {
        if (-not $motivos.ContainsKey($f)) { $motivos[$f] = @() }
        $motivos[$f] += "lote $n ($($sel.Count) fichero(s)$conMod): " + ($problemas -join ' ')
      }
      if ($sel.Count -gt 1) { Info '  -> lo reintento de uno en uno.'; foreach ($f in $sel) { $unoAUno[$f] = $true }; continue }
      $f = $sel[0]
      if ($ModeloB -and -not $planB.ContainsKey($f)) { Info "  -> lo reintento con el modelo de reserva ($ModeloB)."; $planB[$f] = $true; continue }
      # consejo del modelo de las dudas: si es de codigo, un intento mas con el; si no, o si ese intento no pasa, atascado
      $con = $null
      if ($conIntento) { $con = $consejoDe[$f]; Write-Consejo $con "atascado en '$paso': $f" @('se intento y no paso') }
      else {
        $con = Invoke-ConsejoAtascado $paso $f $hall $motivos[$f] @($reflexiones | Where-Object { $_.Ficheros -contains $f })
        if ($con -and $con.Dudas[0].tipo -eq 'codigo') {
          Info ('  -> consejo: ' + (Get-Elegida $con.Dudas[0]).TrimEnd('.') + '. Lo intento una vez mas con el (modelo de -Modelo).')
          $consejoDe[$f] = $con
          continue
        }
        if ($con) {
          Write-Consejo $con "atascado en '$paso': $f" @('no, la decide una persona')
          Info '  -> el consejo dice que esta duda la tiene que decidir una persona: sale al final, en Te toca decidir.'
        }
      }
      Fallo "ATASCADO en '$paso': $f. Lo apunto y sigo con el resto."
      $d0 = $null
      $nota = "- [$paso] ${f}: " + ($problemas -join ' ') + " (registro: .rescate/lote-$paso-$n-*.log)"
      if ($rutaCorr) { $nota += "`n  Ultimo intento (correccion completa en ${rutaCorr}):`n" + (@(Get-LineasDetalle $detalle $rutaCorr) -join "`n") }
      if ($con) {
        $d0 = $con.Dudas[0]
        $nota += "`n  Consejo (.rescate/consejo-$($con.N).json): $($d0.duda)"
        for ($o = 1; $o -le 3; $o++) { $nota += "`n    $o. " + @($d0.opciones)[$o - 1] }
        $nota += "`n    recomendada: $($d0.elegida) (tipo $($d0.tipo)). Por que: $($d0.porque)"
      }
      Add-Atascado $paso $f ($problemas -join ' ') $d0
      if ($esCob) { $script:CobHechas += $f }
      Save-Atascados
      [System.IO.File]::AppendAllText((Join-Path $Work 'atascados.md'), $nota + "`n")
      foreach ($x in $sel) { $unoAUno.Remove($x); $mejorDe.Remove($x) }
      # la cascada de un fichero (de uno en uno, reserva, consejo) cuenta una vez, al quedar atascado, no una por escalon
      $script:Fallos++
      if (-not $esSonar -and $script:Fallos -ge $Cfg.MaxFallosSeguidos) {
        if ($esCob) { $script:Hall = $hall; $script:CobHecha = $true; Write-CoberturaFaltan }   # en sonar un fichero atascado no para la pasada: todo sale contado al final
        Fallo "PARO: $($script:Fallos) ficheros atascados seguidos, sin ningun lote bueno entre medias. Puede ser un problema de Copilot, de Maven o de un flag, no del codigo."
        Info "Ultimas lineas de Copilot (.rescate/lote-$paso-$n-*.log):"
        $rc.Salida | Select-Object -Last 8 | ForEach-Object { Info "  $_" }
        exit 2
      }
      continue
    }

    $d = Get-Cuenta $hall2 $paso
    if ($sinCambios) { $r = [pscustomobject]@{ Codigo = 0; Salida = @() } }
    else {
      [void](Invoke-Git $RepoRoot @('add', '-A'))
      $r = Invoke-Git $RepoRoot (@('commit', '-q', '-m', "rescate($paso): lote $n, hallazgos $($antes[$paso]) a $d") + $Cfg.CommitArgs)
    }
    Remove-Intento   # la marca se va cuando el lote ya esta commiteado (o ha fallado el commit y los cambios son del usuario), no antes
    if ($r.Codigo -ne 0) { Fallo ('git commit ha fallado; los cambios siguen en el arbol de trabajo: ' + ($r.Salida -join ' ')); exit 3 }
    if ($esCob) { $script:CobHechas += $sel[0]; $script:CobCommit = Get-Head $RepoRoot }   # esa clase no se vuelve a proponer en esta pasada; la medida es la de este commit
    if ($esSonar) {   # lo que el modelo ha dejado con motivo y lo que este lote ha resuelto (con su commit) queda en la base
      if (-not $sinCambios) { Set-SonarResueltas (Get-Head $RepoRoot) }
      Save-SonarBase
    }
    if ($conIntento) {
      Write-Consejo $consejoDe[$sel[0]] "atascado en '$paso': $($sel[0])" @('si, commit ' + ((Invoke-Git $RepoRoot @('log', '-1', '--format=%h')).Salida -join '').Trim())
      $consejoDe.Remove($sel[0])   # si al fichero le quedan hallazgos, su lote siguiente va como uno normal
    }
    $hall = $hall2
    $script:Fallos = 0
    $ultimoLote = $n
    if ($elegidos -and -not $sinCambios) { $lotesDesdeControl++ }
    elseif ($marcaActiva -and -not $elegidos) { Save-Control $script:Build.TestsN (Get-FallosTests $hall) }   # el lote ha pasado la suite entera: la marca va con el
    foreach ($f in $sel) { $unoAUno.Remove($f); $mejorDe.Remove($f) }
    Write-Informe $hall
    if ($sinCambios) { Bien "Lote $n OK: '$paso' $($antes[$paso]) -> $d. Sin cambios que guardar: el modelo ha dejado con su motivo todo lo del lote." }
    else {
      $cobTxt = ''
      if ($esCob -and $cobAntes -and $script:Cob -and $script:Cob.medida) { $cobTxt = " Cobertura total: $(Format-Pct $cobAntes.porcentaje) % -> $(Format-Pct $script:Cob.porcentaje) %." }
      Bien "Lote $n OK: '$paso' $($antes[$paso]) -> $d. Commit hecho.$cobTxt"
      (Invoke-Git $RepoRoot @('show', '--stat', '--oneline', '--format=%h %s', 'HEAD')).Salida | Select-Object -First 25 | ForEach-Object { Info "  $_" }
    }
    $blandos | ForEach-Object { Aviso "  REVISA: $_" }

    if (-not $Auto -and $d -gt 0) {
      $resp = Read-Host '[Enter] siguiente lote | n = parar aqui | d = deshacer este lote y parar'
      if ($resp -eq 'd') { $script:Parar = $true; Undo-Lote $rama $check; Aviso 'Lote deshecho.'; return }
      if ($resp -eq 'n') { $script:Parar = $true; break }
    }
    # tests elegidos: cada LotesEntreControles lotes buenos, la suite entera
    if ($elegidos -and $lotesDesdeControl -ge [int]$Cfg.LotesEntreControles -and (Get-MarcaControl) -ne (Get-Head $RepoRoot)) {
      $res = Invoke-Control $paso $n
      $hall = $res.Hall
      $lotesDesdeControl = 0
    }
  }

  # tests elegidos: al acabar, el HEAD ha pasado la suite entera o el paso sale en rojo; si el paso se corta, la consola dice hasta donde esta comprobado
  if ($elegidos -and -not $script:Parar -and -not $script:ControlRojo -and (Get-MarcaControl) -ne (Get-Head $RepoRoot)) {
    $res = Invoke-Control $paso $ultimoLote
    $hall = $res.Hall
  }
  $completo = (-not $script:Parar)
  }
  finally { if ($elegidos -and -not $completo) { Write-SinComprobar } }

  $t = $script:TiemposPaso
  Info "Tiempos del paso ${paso}: $($t.Intentos) intentos, Copilot $(Format-Pct ($t.SegCopilot / 60)) min, Maven $(Format-Pct ($t.SegMaven / 60)) min (detalle: .rescate/intentos.tsv)"
  $script:Hall = $hall
  $script:HallCache = @{ Commit = ((Invoke-Git $RepoRoot @('rev-parse', 'HEAD')).Salida -join '').Trim(); Hall = $hall; Build = $script:Build }
  if ($elegidos -and (Get-MarcaControl) -ne (Get-Head $RepoRoot)) { $script:HallCache = $null }   # el diagnostico del ultimo lote no pasa los tests de contexto: no vale para el paso siguiente
  if ($esCob) { $script:CobHecha = $true }
  Show-Resumen $hall
  if ($esSonar) { Write-SonarFaltan }
  if ($esCob) { Write-CoberturaFaltan }
  $sig = Get-SiguientePasoMotor $hall
  $script:Siguiente = $sig
  if ($sig) { Info "Siguiente paso pendiente: $sig  ->  vuelve a lanzar con -Modo fix (o -Paso $sig)" }
  elseif (-not $esCob) { Show-SinPasos 'Revisa los avisos del informe, el diff completo de la rama y pasa tu pipeline.' }
}

# ================================ COMPROBAR ================================
# Modo comprobar: sin Maven y sin escribir nada, lo que el arbol de trabajo ha roto frente al commit de partida del lote en curso (la
# marca de .rescate/intento-en-curso.json lleva los errores de antes) y lo que sigue sin resolver en sus ficheros. Devuelve 0 si no hay
# nada nuevo roto y 1 si lo hay. Lo ejecuta la IA dentro de su sesion; las puertas del fix cuentan lo nuevo con la misma funcion.
function Invoke-Comprobar {
  $m = $null
  if (Test-Path -LiteralPath (Get-RutaIntento)) { try { $m = [System.IO.File]::ReadAllText((Get-RutaIntento)) | ConvertFrom-Json } catch { $m = $null } }
  if (-not $m -or -not ($m.PSObject.Properties.Name -contains 'base')) {
    Info 'No hay un intento en curso (.rescate/intento-en-curso.json con los errores de partida): no se que has roto tu. Para ver todos los hallazgos: -Modo diagnostico.'
    return 0
  }
  $antes = @{}
  foreach ($k in @($m.base)) { $antes["$k"] = $true }
  $hall = @(Invoke-Diagnostico $false $false)
  $cats = @($hall | ForEach-Object { $_.Cat } | Select-Object -Unique)
  $rotos = @(Get-HallazgosNuevos $hall $cats $antes)
  $fich = @($m.ficheros)
  $siguen = @($hall | Where-Object { $_.Sev -eq 'error' -and $_.Cat -eq $m.paso -and ($fich -contains $_.Fichero) })
  Info "Comprobacion rapida, sin Maven (paso '$($m.paso)', lote $($m.lote))."
  if ($rotos.Count -gt 0) {
    Aviso "HAS ROTO ($($rotos.Count) hallazgos nuevos desde el commit de partida):"
    foreach ($x in ($rotos | Select-Object -First 30)) { Info ('  ' + (Get-LineaHallazgo $x)) }
    if ($rotos.Count -gt 30) { Info "  ($($rotos.Count - 30) mas)" }
  }
  else { Bien 'No has roto nada nuevo.' }
  if ($siguen.Count -gt 0) {
    Info "Siguen sin resolver en los ficheros del lote ($($siguen.Count)):"
    foreach ($x in ($siguen | Select-Object -First 20)) { Info ('  ' + (Get-LineaHallazgo $x)) }
  }
  if ($rotos.Count -gt 0) { return 1 }
  return 0
}

# ================================= MAIN =================================
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Fallo "No encuentro 'git' en el PATH."; exit 1 }
# Con -Sonar o -Cobertura y sin -Modo: el fix entero de ese paso, sin parar a preguntar entre lotes
if ($Sonar -or $Cobertura) {
  if (-not $PSBoundParameters.ContainsKey('Modo')) {
    $Modo = 'fix'
    if (-not $Paso -and -not $Todo) {
      if ($Sonar) {
        $Paso = 'sonar'
        if ($Cobertura) { Aviso "Con -Sonar y -Cobertura sin -Paso ni -Todo solo hago el paso 'sonar': despues lanza -Cobertura sola (o usa -Todo)." }
      }
      else { $Paso = 'cobertura' }
    }
  }
  $Auto = [switch]$true
}
if ($Paso -eq 'sonar' -and -not $Sonar) { Fallo "El paso 'sonar' necesita -Sonar <informe.xlsx>."; exit 1 }
if ($Paso -eq 'cobertura' -and -not $Cobertura) { Fallo "El paso 'cobertura' necesita -Cobertura."; exit 1 }
if ($Sonar) {
  $Sonar = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Sonar)
  if (-not (Test-Path -LiteralPath $Sonar -PathType Leaf)) { Fallo "No existe el informe de Sonar: $Sonar"; exit 1 }
  if (-not $HayReglasSonar) { Fallo "Falta sonar-reglas.ps1 junto a rescate.ps1 ($ReglasSonar): lleva las reglas del paso sonar."; exit 1 }
}
$RepoRoot = Resolve-Dir $Repo
$PlantillaRoot = Resolve-Dir $Plantilla
$LegacyRoot = Resolve-Dir $Legacy
if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot '.git'))) { Fallo "No es la raiz de un repo git: $RepoRoot"; exit 1 }
$soloLee = ($Modo -eq 'comprobar')   # no escribe nada ni necesita Copilot
if ($PlantillaRoot -and ($PlantillaRoot -eq $RepoRoot)) { Aviso 'Repo y plantilla son la misma carpeta: todo saldra permitido.' }

# Carpeta de trabajo. $OrigenRoot es la carpeta que has pasado en -Repo.
# Si ya hay worktree de rescate, se trabaja en el; fix y plan lo crean si falta.
$OrigenRoot = $RepoRoot
if (-not $soloLee) { Set-Excluidos $OrigenRoot }
[void](Read-CfgFile (Get-RutaAjustes) @() $false)   # ajustes.json: lleva claves de otros scripts, ninguna avisa; el del repo manda
Read-Config $OrigenRoot    # antes del worktree: CommitArgs vale tambien para el commit 'foto'
# El informe de Sonar se lee entero antes de crear nada: si no sirve, se dice ahora. Solo se arreglan las incidencias filtradas.
$script:SonarBase = $null
if ($Sonar) {
  try { $script:SonarFilas = @(Get-SonarFiltradas @(Read-SonarXlsx $Sonar $Cfg.SonarColumnas)) }
  catch { Fallo $_.Exception.Message; exit 1 }
  $script:SonarPorFila = @{}
  foreach ($f in $script:SonarFilas) { $script:SonarPorFila[$f.Fila] = $f }
  $script:SonarHash = (Get-FileHash -LiteralPath $Sonar -Algorithm SHA256).Hash
}
if (-not $soloLee) { Test-Copilot }   # antes del worktree: sin Copilot que lanzar no se toca el repo
if (-not $SinWorktree -and -not (Get-Rama $OrigenRoot).StartsWith('rescate/')) {
  $dirWt = Get-DirRescate
  if (-not (Test-WorktreeRescate $dirWt) -and ($Modo -eq 'fix' -or $Modo -eq 'plan')) { New-WorktreeRescate $dirWt }
  if (Test-WorktreeRescate $dirWt) {
    $RepoRoot = $dirWt
    if (-not $soloLee) { Info "Carpeta de trabajo: $RepoRoot (worktree de rescate, rama '$(Get-Rama $RepoRoot)')" }
    if ($Modo -eq 'diagnostico' -or $Modo -eq 'pre') { Info 'Para mirar tu carpeta original en vez del worktree: -SinWorktree' }
    Read-Config $RepoRoot
    if (-not $soloLee) { Test-Copilot }
  }
}

# El paso sonar solo existe con -Sonar, y el de cobertura con -Cobertura (detras de sonar): van los ultimos
$Cfg.Orden = @($Cfg.Orden | Where-Object { $_ -ne 'sonar' -and $_ -ne 'cobertura' })
if ($Sonar) { $Cfg.Orden += 'sonar' }
if ($Cobertura) { $Cfg.Orden += 'cobertura' }

$Work = Join-Path $RepoRoot '.rescate'
if (-not $soloLee -and -not (Test-Path -LiteralPath $Work)) { [void](New-Item -ItemType Directory -Path $Work) }

$script:Atascados = @{}   # paso -> ficheros que la IA no ha sabido arreglar
$script:AtascadosInfo = [ordered]@{}   # 'paso|fichero' -> lo que se guarda en atascados.json
$script:Hall = $null      # los hallazgos del ultimo estado bueno del fix
$script:HallCache = $null # el ultimo diagnostico con Maven y el commit al que corresponde (el siguiente paso lo reutiliza si nada ha cambiado)
$script:Decidir = @()     # dudas de persona de los consejos del plan (las de los atascados van en AtascadosInfo)
# El modelo de las dudas: -ModeloDudas, si no el de la config, si no el de -Modelo. Su esfuerzo: -EsfuerzoDudas o el de
# la config (Invoke-Fuerte lo baja si Copilot no lo admite).
if (-not $ModeloB) { $ModeloB = "$($Cfg.ModeloB)" }   # -ModeloB manda; si no, el de la config
$script:ModDudas = $ModeloDudas
if (-not $script:ModDudas) { $script:ModDudas = "$($Cfg.ModeloDudas)" }
if (-not $script:ModDudas) { $script:ModDudas = $Modelo }
$script:EsfDudas = $EsfuerzoDudas
if (-not $script:EsfDudas) { $script:EsfDudas = "$($Cfg.EsfuerzoDudas)" }
$script:Fallos = 0        # ficheros atascados seguidos
$script:Control = $null      # el ultimo control en verde: commit, testsN (tests que corrian) y fallos (los que ya fallaban); lo escribe Save-Control
$script:ControlRojo = $false # un control ha acabado en rojo: el HEAD no ha pasado la suite entera
$script:TestsExtra = @()     # argumentos de Maven que Invoke-Build anade a los tests (los pone el lote y los quita al acabar)
$script:NoReintentar = @()   # ficheros de lotes que un control ha revertido: esta pasada no los vuelve a intentar
$script:SegMaven = 0.0    # los segundos de Maven del intento en curso (Invoke-ContandoMaven)
$script:IntentosAvisado = $false   # Add-Intento ya ha avisado de que no puede escribir intentos.tsv
Initialize-ConfigReintentos
$script:H = $null
$script:Build = $null
$script:BasePkg = ''
$script:Cob = $null            # la ultima medida de cobertura (Measure-Cobertura); solo con -Cobertura
$script:CobCommit = ''         # el commit al que corresponde
$script:CobHecha = $false      # el paso cobertura ya se ha hecho en esta ejecucion
$script:CobHechas = @()        # las fuentes que esta pasada ya ha intentado (cada una, una vez por pasada)
$script:CobInicial = $null     # el porcentaje al empezar el paso (el X de 'Cobertura: X % -> Y %')
$script:CobTope = $false       # la pasada se ha parado en CoberturaClasesMax
$script:CobExcluidas = @()     # las clases con lineas sin cubrir que CoberturaExcluir no propone
$script:MedirCobertura = $false
$script:Cal = $null
$script:LineaEstilo = ''       # la linea de la consola sobre el estilo del ultimo diagnostico ('' si no hay mezcla)
if ($PlantillaRoot) {
  if (-not $soloLee) { Info 'Leyendo la plantilla...' }
  $script:Cal = Get-Calibracion $PlantillaRoot
  if (-not $soloLee) { Info ('Plantilla incumple: ' + (Get-TextoIncumple $script:Cal)) }
}

switch ($Modo) {
  'comprobar' { exit @(Invoke-Comprobar)[-1] }
  'diagnostico' {
    if ($SinBuild) { Info 'Diagnostico sin Maven...' } else { Info 'Diagnostico (ejecutando Maven, puede tardar)...' }
    $script:MedirCobertura = [bool]$Cobertura   # con -Cobertura el diagnostico mide la cobertura (un Maven mas, con los tests)
    $hall = @(Invoke-Diagnostico (-not $SinBuild) (-not $SinTests))
    Write-Informe $hall
    Show-Resumen $hall
    $sig = Get-SiguientePasoMotor $hall
    if ($sig) { Info "Siguiente paso recomendado: $sig  ->  -Modo fix -Paso $sig" } else { Bien 'Sin errores.' }
  }
  'pre' { Invoke-Pre }
  'plan' {
    Info (Get-TextoModelo)
    if ($SinBuild) { Info 'Diagnostico sin Maven...' } else { Info 'Diagnostico (compilando)...' }
    $hall = @(Invoke-Diagnostico (-not $SinBuild) $false)
    Write-Informe $hall
    Show-Resumen $hall
    # sin -Paso: el primer paso con errores de los que llevan plan
    $p = $Paso
    if (-not $p) { $p = (@($Cfg.Orden | Where-Object { ($Cfg.PasosConPlan -contains $_) -and ((Get-Cuenta $hall $_) -gt 0) } | Select-Object -First 1) -join '') }
    if (-not $p) { Bien ('No hay errores en los pasos que llevan plan (' + ($Cfg.PasosConPlan -join ', ') + ').') }
    elseif ($Cfg.PasosConPlan -notcontains $p) { Aviso "El paso '$p' no lleva plan: se arregla hallazgo a hallazgo." }
    elseif ((Get-Cuenta $hall $p) -eq 0) { Bien "El paso '$p' no tiene errores: no hay nada que planificar." }
    else {
      $plan = Invoke-Plan $p $hall $true
      if ($plan) { Info "Leelo y corrigelo si hace falta. Despues: -Modo fix -Paso $p" }
    }
  }
  'fix' {
    if ($Todo) { $Auto = [switch]$true }
    Info (Get-TextoModelo)
    $script:Parar = $false
    $script:Siguiente = ''
    $previo = ''
    # -Todo sin lista de jobs: primero lo del modo pre (sin -Legacy no se puede; paridad lo avisa en el informe)
    $sinRevisar = ''
    if ($Todo -and $LegacyRoot -and -not (Test-Path -LiteralPath (Join-Path $Work 'contrato.json'))) {
      Info 'No hay lista de jobs del original (.rescate/contrato.json): hago antes lo del modo pre.'
      Invoke-Pre
      $sinRevisar = 'La lista de jobs no la ha revisado nadie: ' + (Join-Path $Work 'contrato.json') + ' (si sobra o falta alguno, editala).'
      Aviso ($sinRevisar + ' Sigo con el arreglo.')
    }
    while ($true) {
      Invoke-Fix
      if (-not $Todo -or $Paso -or $script:Parar -or -not $script:Siguiente) { break }
      if ($script:Siguiente -eq $previo) { Aviso "El paso '$previo' no avanza: paro aqui."; break }
      $previo = $script:Siguiente
    }
    $ramaFin = Get-Rama $RepoRoot
    if ($ramaFin.StartsWith('rescate/')) {
      Info ''
      Info "Los cambios estan en la rama '$ramaFin', en commits locales. El script no hace push."
      if ($RepoRoot -ne $OrigenRoot) {
        $ro = Get-Rama $OrigenRoot
        Info "Tu carpeta '$OrigenRoot' sigue como estaba. Copia cada linea entera; lo que va detras de # es solo la explicacion:"
        $ordenGit = "  git -C `"$OrigenRoot`" "
        Info "${ordenGit}diff --stat ${ro}...$ramaFin   # ver que ha cambiado"
        Info "${ordenGit}merge $ramaFin   # traerlo a tu rama (o sube la rama y abre un PR)"
        Info "${ordenGit}worktree remove `"$RepoRoot`"   # borrar el worktree cuando acabes con prueba-local.ps1 (la rama se conserva)"
        if (@((Invoke-Git $OrigenRoot @('status', '--porcelain')).Salida | Where-Object { $_ }).Count -gt 0) {
          Info '  Ojo: si tenias cambios sin commit al crear el worktree, ya van dentro de esa rama (commit foto). Guardalos o descartalos antes del merge.'
        }
      }
    }
    if ($sinRevisar) { Info ''; Aviso $sinRevisar }
    Remove-AtascadosResueltos
    if ($script:Atascados.Count -gt 0) {
      Fallo ''
      Fallo 'Se ha quedado sin arreglar (lo unico que te toca mirar):'
      foreach ($k in $Cfg.Orden) { if ($script:Atascados.ContainsKey($k)) { $script:Atascados[$k] | ForEach-Object { if ($_) { Fallo "  [$k] $_" } else { Fallo "  [$k] (repo)" } } } }
      Info ('Detalle: ' + (Join-Path $Work 'atascados.md'))
    }
    $decidir = @($script:Decidir) + @($script:AtascadosInfo.Values | Where-Object { $_.consejo -and $_.consejo.tipo -eq 'persona' } | ForEach-Object {
        "[$($_.paso)] $($_.fichero): $($_.consejo.duda) -> recomendada: $(Get-Elegida $_.consejo) (por que: $($_.consejo.porque))" })
    if ($decidir.Count -gt 0) {
      Info ''
      Aviso 'Te toca decidir (el modelo de las dudas recomienda una opcion; el script no la ha aplicado):'
      $decidir | ForEach-Object { Aviso "  $_" }
      Info ('Las 3 opciones de cada duda, con su porque: ' + (Join-Path $Work 'decisiones.md'))
    }
    if ($script:ControlRojo) {
      Fallo ''
      Fallo 'Un control ha salido en rojo: el HEAD no ha pasado la suite entera (la marca refs/rescate/control-ok no se ha movido). Mira .rescate/intentos.tsv y la salida de arriba.'
    }
    if ($script:Atascados.Count -gt 0) { Info 'Opciones: otro modelo (-Modelo / -ModeloB), arreglarlo a mano (la pasada siguiente lo intenta si el fichero cambia o si haces un commit), o volver a lanzar con -Reintentar.' }
    if ($script:ControlRojo -or $script:Atascados.Count -gt 0) { exit 2 }
  }
  'deshacer' {
    $asunto = ((Invoke-Git $RepoRoot @('log', '-1', '--format=%s')).Salida -join '')
    if ($asunto -notmatch '^rescate\(') { Fallo "El ultimo commit no es un lote de rescate ('$asunto'). No hago nada."; exit 1 }
    if (Confirmar "Deshago el commit '$asunto'?") {
      [void](Invoke-Git $RepoRoot @('reset', '-q', '--hard', 'HEAD~1'))
      [void](Invoke-Git $RepoRoot @('clean', '-fdq'))
      Bien 'Hecho.'
    }
  }
}
