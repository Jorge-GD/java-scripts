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

  # Todo seguido, sin parar: se detiene solo si un lote no pasa las comprobaciones.
  # Sin .rescate\contrato.json (y con -Legacy) hace antes lo del modo pre.
  .\rescate.ps1 -Modo fix ... -Todo

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
  # Con "Reflexionar" (encendido por defecto; "Reflexionar": false en
  # .rescate/config.json lo apaga), tras cada intento que no pasa el modelo de las
  # dudas reflexiona (por que no paso, que hacer) y el siguiente intento lo lleva. Con -Auto, las dudas del plan
  # tambien las resuelve el (las de codigo van al plan, en ## Decisiones).
  # Todo queda en .rescate/decisiones.md; lo que le toca a una persona sale al
  # final en "Te toca decidir".
  .\rescate.ps1 -Modo fix ... -Todo -ModeloDudas <id-fuerte> -EsfuerzoDudas max

  # Elegir paso, lotes mas pequenos, saltar ficheros que se atascan
  .\rescate.ps1 -Modo fix ... -Paso hexagonal -Lote 3 -Saltar 2

  # Deshacer el ultimo lote
  .\rescate.ps1 -Modo deshacer -Repo C:\ruta\batch-life

  # 4) Al acabar. Los cambios estan en la rama rescate/... (el script te dice
  #    el nombre). Revisalos y traelos a tu rama, o sube la rama y abre un PR:
  git -C C:\ruta\batch-life diff --stat <tu-rama>...<rama-rescate>
  git -C C:\ruta\batch-life merge <rama-rescate>
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
  [ValidateSet('diagnostico', 'pre', 'plan', 'fix', 'deshacer')][string]$Modo = 'diagnostico',
  [string]$Repo = '.',
  [string]$Plantilla = '',
  [string]$Legacy = '',
  [ValidateSet('', 'build', 'estructura', 'hexagonal', 'ficheros', 'config', 'paridad', 'e2e', 'tests', 'calidad')][string]$Paso = '',
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

# ============================ CONFIGURACION ============================
# Los flags de Copilot, la ruta de Maven y las carpetas ignoradas estan en comun.ps1.
$Cfg += @{
  Orden  = @('build', 'estructura', 'hexagonal', 'ficheros', 'config', 'paridad', 'e2e', 'tests', 'calidad')
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
       Por = 'un adaptador de entrada no llama a uno de salida: pasa por un caso de uso' }
  )
  SubpaquetesEstrictos  = $true   # domain/x, application/x... deben existir en la plantilla
  # Acceso a ficheros locales (lo que debe ir por el puerto de ficheros / SFTP)
  FicheroImport         = '^(java\.io\.(File|FileReader|FileWriter|FileInputStream|FileOutputStream|RandomAccessFile)|java\.nio\.file\..+|org\.springframework\.core\.io\.(FileSystemResource|PathResource|FileUrlResource))$'
  FicheroToken          = '\b(File|FileReader|FileWriter|FileInputStream|FileOutputStream|RandomAccessFile)\b'
  FicheroPermitidoEn    = @('infrastructure/adapters/output/file')
  # Un batch que maneja ficheros tiene que traer el adaptador SFTP y su configuracion, tenga lo que tenga la plantilla.
  # En false solo se exige lo que la plantilla tiene.
  ExigirSftp            = $true
  # Palabras que delatan la configuracion antigua. AJUSTALAS a tu repo.
  PalabrasConfigAntigua = @('inventory')
  # API antigua: se marca solo si la plantilla ya no la usa
  ApiAntigua            = @('JobBuilderFactory', 'StepBuilderFactory')
  # Una clave de application*.yml|properties es un secreto si su ultimo trozo ACABA en una de estas
  # palabras (sin distinguir mayusculas). Lista vacia = no se busca. Idea de SonarJava S2068.
  PalabrasSecreto       = @('password', 'passwd', 'pwd', 'passphrase', 'secret', 'token', 'clave', 'contrasena', 'apikey', 'api-key', 'private-key')
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
  PasosDeUnoEnUno       = @('paridad', 'e2e')   # un job por llamada a Copilot
  # Pasos en los que la IA revisa antes todos los ficheros y escribe un plan
  PasosConPlan          = @('estructura', 'hexagonal', 'ficheros', 'config')
  # Calidad. Reglas que cuentan como error (el fix las arregla y las exige en
  # el codigo nuevo). El resto de reglas se queda en aviso. Para apagar una,
  # quitala de aqui. Reglas: javadoc-tipo, javadoc-metodo, inyeccion-campo,
  # salida-consola, catch-vacio, envoltorio-new, instanceof-cast,
  # fecha-antigua, coleccion-antigua.
  CalidadErrores        = @('javadoc-tipo', 'javadoc-metodo', 'inyeccion-campo', 'salida-consola', 'catch-vacio', 'envoltorio-new')
  # Reglas que se exigen aunque la plantilla tampoco las cumpla
  CalidadSiempre        = @('javadoc-tipo', 'javadoc-metodo')
  # Metodos publicos de una clase que no necesitan Javadoc (en una interfaz, todos lo llevan)
  MetodosSinJavadoc     = '^(main|equals|hashCode|toString|(get|set|is)[A-Z0-9_]\w*)$'
  MaxFallosSeguidos     = 6     # lotes deshechos seguidos antes de parar (no gastar llamadas en balde)
  # El modelo de las dudas (consejo y reflexion). Vacio = el de -Modelo. Su esfuerzo: si Copilot no admite max, baja
  # a xhigh y luego a high.
  ModeloDudas           = ''
  EsfuerzoDudas         = 'max'
  # El modelo de reserva si no se pasa -ModeloB (migracion.ps1 lanza el fix sin el). Vacio = sin reserva.
  ModeloB               = ''
  # Tras cada intento que no pasa, el modelo de las dudas explica por que y que hacer, y el siguiente intento lo lleva.
  # Encendida por decision del usuario el 18-11, al ver atascos reales con las mismas cuentas en los tres intentos. La
  # medida del M6 (el caso de dos ficheros que necesitan la misma pieza comun) no tuvo ningun atasco en ninguno de sus
  # brazos (0 y 0 con y sin ella, dos pasadas de cada), y con ella la pasada tardo de 3 a 4 veces mas y costo de 5 a 8
  # veces mas. Se apaga con "Reflexionar": false.
  Reflexionar           = $true
  LineasDiff            = 300   # lineas del diff del intento que recibe la reflexion
  # Maven
  MvnCompilar           = @('-q', '-B', '-DskipTests', 'test-compile')
  MvnTests              = @('-q', '-B', 'test')
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
  $res = Join-Ruta $Raiz 'src/main/resources'
  if (Test-Path -LiteralPath $res) {
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
    else { $t = $script:RxLexico.Replace($t, [System.Text.RegularExpressions.MatchEvaluator] { param($m) if ($m.Value.StartsWith('/')) { return '' } else { return $m.Value } }) }
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
$RxInyeccion = New-Object System.Text.RegularExpressions.Regex '@(Autowired|Inject)\b(?:\s*\([^)]*\))?(?:\s*@\w+(?:\s*\([^)]*\))?)*\s+(?:(?:private|protected|public|transient|volatile)\s+)*[\w\.\[\]<>,\?\s]+?\s+(\w+)\s*;'
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

# Faltas de calidad del codigo de src/main (sin decidir aun si son error o aviso).
function Get-Calidad($Hechos) {
  $out = New-Object System.Collections.Generic.List[object]
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
    foreach ($m in $script:RxInyeccion.Matches($limpio)) {
      Add-Cal $out $f.RelRaiz (Get-LineaDe $limpio $m.Index) 'inyeccion-campo' ('@' + $m.Groups[1].Value + " en el campo '" + $m.Groups[2].Value + "': usa inyeccion por constructor con campos private final")
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
      Add-Cal $out $f.RelRaiz $viejas[0].Linea 'fecha-antigua' ('usa java.time en vez de ' + ((@($viejas | ForEach-Object { $_.Fqn })) -join ', ') + ' (con un test delante: puede cambiar el formato o la zona)')
    }
    $mc = $script:RxColeccion.Match($limpio)
    if ($mc.Success) {
      Add-Cal $out $f.RelRaiz (Get-LineaDe $limpio $mc.Index) 'coleccion-antigua' ($mc.Value + ': usa StringBuilder, ArrayList o HashMap si no hace falta sincronizar')
    }
  }
  return $out.ToArray()
}

# Lo que se aprende de la plantilla.
function Get-Calibracion([string]$Raiz) {
  $h = Get-Hechos $Raiz
  $capas = @(); $sub2 = @{}; $dirs3 = @{}
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
  }
  foreach ($v in @(Get-ViolImports $h)) { $excImp[$v.Clave] = $true }
  foreach ($u in @(Get-UsoFicheros $h)) { if (-not (Test-FicheroPermitido $u.Dir)) { $excFic[$u.Clave] = $true } }
  $todo = (@($h.Ficheros | ForEach-Object { $_.Texto }) -join "`n")
  foreach ($t in $Cfg.ApiAntigua) { $tokens[$t] = ($todo -match ('\b' + $t + '\b')) }
  $jakarta = $false
  foreach ($f in (@($h.Ficheros) + @($h.Tests))) { foreach ($i in $f.Imports) { if ($i.Fqn.StartsWith('jakarta.')) { $jakarta = $true } } }
  $extra = @()
  foreach ($f in @(Get-Arbol $Raiz 2)) {
    $rel = Get-Rel $Raiz $f.FullName
    if (-not $rel.StartsWith('src/')) { $extra += $rel }
  }
  $calReglas = @{}
  foreach ($q in @(Get-Calidad $h)) { $calReglas[$q.Regla] = $true }
  return [pscustomobject]@{
    Capas = $capas; Sub2 = $sub2; Dirs3 = @($dirs3.Keys | Sort-Object)
    ExcImports = $excImp; ExcFicheros = $excFic; Tokens = $tokens; UsaJakarta = $jakarta
    Calidad = $calReglas; Secretos = @(Get-SecretosEnClaro $h | Where-Object { $_.Sev -eq 'error' }).Count
    UsaConfigProps = ($todo -match '@ConfigurationProperties'); UsaValue = ($todo -match '@Value\s*\(')
    TieneSftp = (@($h.Ficheros | Where-Object { $_.Rel -match '(^|/)sftp/' }).Count -gt 0)
    YmlSftp = ($h.Yml -match 'sftp'); Pom = (Get-Pom $Raiz); Extra = $extra
  }
}

# Cuanto incumple la propia plantilla (lo que se permite en el repo porque ella lo hace), en una linea.
function Get-TextoIncumple($Cal) {
  return "capas $($Cal.ExcImports.Count) | ficheros $($Cal.ExcFicheros.Count) | calidad $($Cal.Calidad.Count) | secretos $($Cal.Secretos)"
}

# ============================== DIAGNOSTICO ==============================
function Add-Hallazgo([string]$Cat, [string]$Sev, [string]$Fichero, [int]$Linea, [string]$Detalle) {
  [void]$script:H.Add([pscustomobject]@{ Cat = $Cat; Sev = $Sev; Fichero = $Fichero; Linea = $Linea; Detalle = $Detalle })
}

function Invoke-Build([bool]$ConTests) {
  $b = [pscustomobject]@{ Ejecutado = $true; Compila = $true; TestsEjecutados = $false; TestsOk = $false }
  $rep = Join-Ruta $RepoRoot 'target/surefire-reports'
  if ($ConTests -and (Test-Path -LiteralPath $rep)) { Remove-Item -LiteralPath $rep -Recurse -Force }
  if ($ConTests) { $a = $Cfg.MvnTests } else { $a = $Cfg.MvnCompilar }
  if ($ConTests) { $que = 'Maven (tests)' } else { $que = 'Maven (compilar)' }
  $previos = @(Get-Cambios $RepoRoot)
  $latido = Start-Latido $que $Cfg.SegundosLatido
  try { $r = Invoke-Nativo (Get-Mvn $RepoRoot) $a $RepoRoot }
  finally { Stop-Latido $latido }
  # lo que deja Maven fuera de target se quita (Remove-Ruido, la regla de prueba-local.ps1): no entra en los commits
  $ruido = @(Remove-Ruido $RepoRoot $previos)
  if ($ruido.Count -gt 0 -and -not $script:RuidoDicho) {
    $script:RuidoDicho = $true
    Info ('Maven deja ficheros fuera de target (' + (($ruido | Select-Object -First 3) -join ', ') + '): los quito despues de cada ejecucion, no entran en los commits.')
  }
  [System.IO.File]::WriteAllLines((Join-Path $Work 'build.log'), [string[]]$r.Salida)
  if ($r.Codigo -eq 0) {
    if ($ConTests) { $b.TestsEjecutados = $true; $b.TestsOk = $true }
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
  if ($ConTests -and (Test-Path -LiteralPath $rep)) {
    foreach ($f in @(Get-ChildItem -LiteralPath $rep -File -Filter '*.txt')) {
      $t = [System.IO.File]::ReadAllText($f.FullName)
      if ($t -match 'Tests run:\s*(\d+),\s*Failures:\s*(\d+),\s*Errors:\s*(\d+)') {
        $nf = [int]$Matches[2] + [int]$Matches[3]
        if ($nf -gt 0) {
          $clase = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
          $rel = 'src/test/java/' + ($clase -replace '\.', '/') + '.java'
          if (-not (Test-Path -LiteralPath (Join-Ruta $RepoRoot $rel))) { $rel = $clase }
          Add-Hallazgo 'tests' 'error' $rel 0 "$nf test(s) fallan en $clase (ver target/surefire-reports)"
          $fallan++
        }
      }
    }
  }
  if ($fallan -gt 0) { $b.TestsEjecutados = $true; $b.TestsOk = $false; return $b }
  # 3) otra cosa (parent que no resuelve, plugin, etc.)
  $primera = @($r.Salida | Where-Object { $_ -match '\[ERROR\]' } | Select-Object -First 1) -join ''
  $b.Compila = $false
  Add-Hallazgo 'build' 'error' 'pom.xml' 0 ('el build falla y no es compilacion ni tests: ' + $primera)
  return $b
}

function Invoke-Diagnostico([bool]$ConBuild, [bool]$ConTests) {
  $script:H = New-Object System.Collections.Generic.List[object]
  $script:Build = [pscustomobject]@{ Ejecutado = $false; Compila = $true; TestsEjecutados = $false; TestsOk = $false }
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
    Add-Hallazgo 'ficheros' 'error' $g.Name $g.Group[0].Linea "acceso directo a ficheros locales ($imps): debe ir por el puerto de ficheros"
  }
  if ($usaFicheros -and (@($h.Ficheros | Where-Object { $_.Rel -match '(^|/)sftp/' }).Count -eq 0) -and ($Cfg.ExigirSftp -or ($cal -and $cal.TieneSftp))) {
    if ($cal -and $cal.TieneSftp) { $donde = 'la plantilla lo tiene en infrastructure/adapters/output/sftp' } else { $donde = 'va en infrastructure/adapters/output/sftp' }
    Add-Hallazgo 'ficheros' 'error' '' 0 "no hay adaptador SFTP ($donde)"
  }
  if ($usaFicheros -and ($h.Yml -notmatch 'sftp') -and ($Cfg.ExigirSftp -or ($cal -and $cal.YmlSftp))) {
    if ($cal -and $cal.YmlSftp) { $deLaPlantilla = ' (la plantilla si)' } else { $deLaPlantilla = '' }
    Add-Hallazgo 'ficheros' 'error' 'src/main/resources' 0 ('application.yml no tiene configuracion sftp' + $deLaPlantilla)
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
  foreach ($q in @(Get-Calidad $h)) {
    $sev = 'aviso'; $nota = ''
    if ($Cfg.CalidadErrores -contains $q.Regla) {
      if ($cal -and $cal.Calidad.ContainsKey($q.Regla) -and ($Cfg.CalidadSiempre -notcontains $q.Regla)) { $nota = ' (se queda en aviso: la plantilla tambien lo hace)' }
      else { $sev = 'error' }
    }
    Add-Hallazgo 'calidad' $sev $q.RelRaiz $q.Linea ('[' + $q.Regla + '] ' + $q.Detalle + $nota)
  }

  return $script:H.ToArray()
}

function Get-Cuenta($Hall, [string]$Cat, [string]$Sev = 'error') {
  return @($Hall | Where-Object { $_.Cat -eq $Cat -and $_.Sev -eq $Sev }).Count
}

# Primer paso con errores pendientes (sin contar lo que ya se dio por atascado).
function Get-SiguientePaso($Hall) {
  foreach ($c in $Cfg.Orden) {
    $f = @($Hall | Where-Object { $_.Cat -eq $c -and $_.Sev -eq 'error' } | ForEach-Object { $_.Fichero } | Select-Object -Unique)
    if ($script:Atascados.ContainsKey($c)) { $f = @($f | Where-Object { $script:Atascados[$c] -notcontains $_ }) }
    if ($f.Count -gt 0) { return $c }
  }
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
  Info ('Informe: ' + (Join-Path $Work 'diagnostico.md'))
}

# ================================= FIX =================================
$TextoPaso = @{
  build      = 'Haz que el proyecto compile con Java 21 usando las mismas propiedades y plugins que el pom.xml de la PLANTILLA, sin cambiar el parent: si hace falta otro, apuntalo como duda. No copies dependencias de negocio que este repo no necesite. Corrige los errores de compilacion listados. No reestructures paquetes en este paso.'
  estructura = 'Mueve las clases listadas a la capa y paquete que les corresponde, copiando exactamente la estructura de paquetes y la convencion de nombres de la PLANTILLA. Solo mover y actualizar package e imports: no cambies logica. Mueve tambien sus tests al paquete equivalente.'
  hexagonal  = 'Elimina las dependencias prohibidas listadas. El dominio no depende de nada externo. La aplicacion solo depende del dominio y de sus puertos (interfaces en application/ports). Si una clase de dominio o aplicacion necesita infraestructura, crea un puerto y lleva la implementacion a un adaptador en infrastructure/adapters/output/<tecnologia>, con los nombres al estilo de la PLANTILLA.'
  ficheros   = 'Sustituye el acceso directo a ficheros locales por puertos de ficheros, igual que la PLANTILLA: puerto para listar y leer, puerto para el ciclo de vida del fichero, un adaptador SFTP y otro local, y seleccion por propiedad de configuracion. Usa la misma libreria SFTP que la PLANTILLA; si la PLANTILLA no tiene SFTP, crea igualmente el adaptador SFTP en infrastructure/adapters/output/sftp (con la libreria SFTP que ya use este repo) y su bloque sftp en application.yml. No dejes rutas fijas en el codigo.'
  config     = 'Elimina las referencias a la configuracion antigua (inventory). Toda la configuracion debe entrar por una clase @ConfigurationProperties validada al arranque y por application.yml leyendo variables de entorno, igual que la PLANTILLA. Ningun secreto (contrasena, token, clave) puede quedar escrito en application.yml o application.properties, ni como valor por defecto: se leen de una variable de entorno (`${NOMBRE}`). No escribas el valor en ningun otro fichero del repo; si un test lo necesita, usa un valor inventado en src/test/resources.'
  paridad    = 'Migra desde el ORIGINAL el job listado, que falta en este repo. Conserva EXACTAMENTE su nombre de job (con ese nombre lo lanza el planificador). Sigue la estructura de la PLANTILLA: adaptador de entrada (job y step), caso de uso, puertos y adaptadores de salida. Reutiliza los puertos y adaptadores que ya existan en este repo. Misma logica que el original.'
  e2e        = 'Crea un test de integracion para el job listado, copiando el patron de los tests de integracion de la PLANTILLA. El test lanza el job real de principio a fin con los adaptadores locales (sftp desactivado), base de datos en memoria y los servicios externos simulados; comprueba que termina en COMPLETED y que la salida es la esperada. Usa los datos de src/test/resources/e2e/<nombre-del-job>/ si existen; si no, crea alli datos sinteticos minimos (nunca datos reales). La salida esperada se deduce de la logica del ORIGINAL, no de ejecutar el codigo nuevo. El test debe contener el nombre del job. Si el test falla porque el codigo migrado no hace lo mismo que el original, corrige el codigo, no el test.'
  tests      = 'Haz que los tests listados pasen. Si fallan por la reestructuracion (paquetes, puertos, mocks), adapta el test. Si destapan un fallo real de la migracion, corrige el codigo. No borres tests ni relajes aserciones.'
  calidad    = 'Resuelve los hallazgos de calidad listados SIN cambiar el comportamiento. Javadoc: lee antes el codigo y escribe que hace la clase y que papel tiene en su capa; en cada metodo, que hace, @param, @return y @throws; no te lo inventes ni repitas el nombre. @Autowired en un campo: pasa a inyeccion por constructor con campos private final y adapta los tests que construyan la clase. System.out y printStackTrace: usa el logger que usa la PLANTILLA, con el mismo mensaje. catch vacio: no cambies el flujo; registra la excepcion con el logger o deja un comentario que explique por que se ignora. new Integer(...) y similares: valueOf. No toques nada mas de esos ficheros.'
}

# Lo que se le pide al codigo que la IA escribe en cualquier paso.
$TextoCalidad = @(
  'Vale para el codigo NUEVO de este lote y para los metodos que modifiques. No es permiso para refactorizar lo demas.',
  '- Javadoc, en el idioma de los comentarios de la PLANTILLA. Cada clase, interfaz, record o enum publico que crees lleva un Javadoc que dice que es y que papel tiene en su capa (puerto, adaptador, caso de uso...). Cada metodo publico que crees, y todos los de una interfaz, llevan Javadoc: que hace, @param, @return y @throws cuando existan. No hace falta en metodos con @Override, getters, setters ni constructores. Un Javadoc que solo repite el nombre no vale.',
  '- Inyeccion por constructor con campos private final. Nada de @Autowired ni @Inject en campos.',
  '- Para datos inmutables nuevos (valores, DTO, propiedades de configuracion) usa record si la PLANTILLA tambien los usa.',
  '- Usa el logger de la PLANTILLA. Nunca System.out, System.err ni printStackTrace. Ningun catch vacio: registra la excepcion con el logger y sigue como hasta ahora, o explica en un comentario por que se ignora. No la relances ni quites el catch: cambia el comportamiento.',
  '- try-with-resources para todo lo que se cierra. Optional solo como valor de retorno. Colecciones inmutables (List.of, Stream.toList) cuando no se modifican.',
  '- Sintaxis de Java 21 solo donde simplifica codigo que ya estas escribiendo: switch con flechas, instanceof con patron, bloques de texto. var solo si el tipo se ve en la misma linea.',
  '- Fechas nuevas con java.time. No conviertas en este lote las fechas que ya existen: puede cambiar el comportamiento.',
  'Despues del lote el script vuelve a contar los hallazgos de calidad (Javadoc, inyeccion en campos, System.out, catch vacios). Si tu codigo anade alguno, el lote no pasa.'
)

# Un hallazgo en una linea de prompt: '- fichero:linea - detalle' ('(repo)' si no es de un fichero).
function Get-LineaHallazgo($x) {
  $donde = $x.Fichero
  if ($x.Linea -gt 0) { $donde += ':' + $x.Linea }
  if (-not $donde) { $donde = '(repo)' }
  return "- $donde - $($x.Detalle)"
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

# Prompt de un lote. $Consejo: la decision del modelo de las dudas para un atascado (va tras los hallazgos).
# $Reflexiones: las de los intentos anteriores de estos ficheros (dentro de la CORRECCION, si la hay).
function New-Prompt([string]$PasoId, $LoteH, [string]$Correccion, $Consejo = $null, $Reflexiones = @()) {
  # La orden de Maven: relativa (./mvnw) si esta dentro del repo; si no, la ruta tal cual, entre comillas si tiene espacios.
  $sep = [System.IO.Path]::DirectorySeparatorChar
  $mvn = Get-Mvn $RepoRoot
  if ($mvn.StartsWith($RepoRoot + $sep, [System.StringComparison]::OrdinalIgnoreCase)) { $mvn = '.' + $sep + $mvn.Substring($RepoRoot.Length + 1) }
  if ($mvn -match '\s') { $mvn = '"' + $mvn + '"' }
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
  $l.Add('## Antes de tocar nada')
  $l.Add('1. Lee enteros los ficheros del lote y busca quien los usa: imports, inyeccion, configuracion y tests.')
  $l.Add('2. Lee en la PLANTILLA las clases equivalentes y copia su paquete, sus nombres y su estilo.')
  $l.Add('3. Si en este repo ya existe un puerto, un adaptador o una clase de configuracion que sirve, reutilizalo. No crees otro parecido.')
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
  if ($Consejo) {
    $l.Add('## Consejo para este fichero (lo ha decidido un revisor: siguelo)')
    $l.Add("Duda: $($Consejo.duda)")
    $l.Add('Decision: ' + (Get-Elegida $Consejo))
    $l.Add("Por que: $($Consejo.porque)")
    $l.Add('')
  }
  $l.Add('## Reglas obligatorias')
  $l.Add('1. No cambies la logica de negocio: mismo comportamiento que el original.')
  $l.Add('2. No toques nada fuera de este repositorio. No hagas commit ni push ni cambies de rama: de git se encarga el script.')
  $l.Add('3. No borres tests, no los desactives (@Disabled, @Ignore), no relajes aserciones ni bajes umbrales de cobertura. Si mueves una clase, mueve su test.')
  $l.Add("4. No cambies el pom.xml salvo que el paso sea 'build' o sea imprescindible. Nunca anadas dependencias que la plantilla no use.")
  $l.Add('5. No escribas contrasenas, tokens ni hosts reales en ningun fichero.')
  $l.Add('6. No hagas mejoras ni refactors que este lote no pide.')
  $l.Add('7. Si un hallazgo no se puede resolver sin romper estas reglas, dejalo como esta y explicalo al final.')
  $l.Add('')
  $l.Add('## Calidad del codigo que escribas (Java 21)')
  foreach ($x in $TextoCalidad) { $l.Add($x) }
  $l.Add('')
  $l.Add('## Al terminar')
  $l.Add("- Ejecuta: $mvn " + ($Cfg.MvnCompilar -join ' ') + '  y corrige hasta que compile.')
  $l.Add('- Responde solo con: ficheros cambiados (lista corta) y hallazgos sin resolver con el motivo.')
  if ($Correccion) {
    $l.Add('')
    $l.Add('## CORRECCION: tu intento anterior no paso las comprobaciones')
    $l.Add('Tus cambios siguen en el arbol de trabajo. Corrige esto sin deshacer lo que estaba bien:')
    $l.Add($Correccion)
  }
  foreach ($x in (Get-TextoReflexiones $Reflexiones ([bool]$Correccion))) { $l.Add($x) }
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
# $Que es lo que dice el latido mientras Copilot trabaja.
function Invoke-Copilot([string]$Log, [string]$Mod = '', [string]$Esf = '', [string]$Que = 'Copilot') {
  if (-not $Mod) { $Mod = $Modelo }
  if (-not $Esf) { $Esf = $Esfuerzo }
  $a = Get-ArgsCopilot 'Lee el fichero .rescate/prompt.md y sigue sus instrucciones al pie de la letra.' $Mod $Esf @($PlantillaRoot, $LegacyRoot) ([bool]$SinInstrucciones)
  $latido = Start-Latido $Que $Cfg.SegundosLatido
  try { $r = Invoke-Nativo $script:Copilot.Ruta $a $RepoRoot }
  finally { Stop-Latido $latido }
  [System.IO.File]::WriteAllLines($Log, [string[]]$r.Salida)
  return $r
}

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
  if (-not $Cfg.Reflexionar) { $t += ' (sin reflexion)' }
  return $t
}

function Get-Guardas {
  $tests = @(Get-JavaFiles (Join-Ruta $RepoRoot 'src/test/java'))
  $des = 0; $ase = 0
  foreach ($f in $tests) {
    $t = [System.IO.File]::ReadAllText($f.FullName)
    $des += [regex]::Matches($t, '@(Disabled|Ignore)\b').Count
    $ase += [regex]::Matches($t, '\b(assert\w*|verify)\s*\(').Count
  }
  # los catch de src/main/java, sin comentarios ni textos (ruta -> cuenta): quitar uno cambia como se tratan los errores
  $catchDe = @{}; $nc = 0
  foreach ($f in @(Get-JavaFiles (Join-Ruta $RepoRoot 'src/main/java'))) {
    $k = $script:RxCatch.Matches((Get-Limpio ([System.IO.File]::ReadAllText($f.FullName)))).Count
    if ($k -gt 0) { $catchDe[(Get-Rel $RepoRoot $f.FullName)] = $k; $nc += $k }
  }
  return [pscustomobject]@{ Tests = $tests.Count; Desactivados = $des; Aserciones = $ase; Catch = $nc; CatchDe = $catchDe; Plantilla = (Get-Huella $PlantillaRoot); Legacy = (Get-Huella $LegacyRoot) }
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
  $l = New-Object System.Collections.Generic.List[string]
  $l.Add("# Tarea: revision previa del paso '$PasoId' (SOLO LECTURA)")
  $l.Add('')
  $l.Add('Vas a preparar el plan de un paso de una migracion a medias de un batch Java 8 a Java 21 con arquitectura hexagonal.')
  $l.Add("No modifiques NINGUN fichero de codigo, ni aqui ni en las referencias. Tu unica salida es crear el fichero .rescate/plan-$PasoId.md en el repositorio actual.")
  $l.Add('')
  foreach ($x in (Get-TextoReferencias)) { $l.Add($x) }
  $l.Add('## Lo que se hara despues en este paso (ahora NO lo hagas)')
  $l.Add($TextoPaso[$PasoId])
  $l.Add('')
  $l.Add('## Hallazgos del paso (todos)')
  foreach ($x in $pend) { $l.Add((Get-LineaHallazgo $x)) }
  $l.Add('')
  $l.Add('## Que tienes que revisar')
  $l.Add('1. Lee entero cada fichero de la lista. Busca quien lo usa: imports, inyeccion, configuracion y tests.')
  $l.Add('2. Lee en la PLANTILLA las clases equivalentes: en que paquete estan, como se llaman y que puertos y adaptadores usan.')
  $l.Add('3. Decide que se hara con cada fichero. Las decisiones tienen que ser coherentes entre si: si varios ficheros necesitan lo mismo (un puerto, un adaptador, una clase de configuracion), se crea UNA sola pieza comun y todos la usan.')
  $l.Add('4. Si algo no se puede resolver sin cambiar el comportamiento, no lo fuerces: apuntalo en Dudas.')
  $l.Add('5. Como se tratan los errores (capturar y seguir, o propagar) es comportamiento: el plan no lo cambia.')
  $l.Add('')
  $l.Add("## Formato de .rescate/plan-$PasoId.md")
  $l.Add("Empieza con la linea: # Plan del paso '$PasoId'")
  $l.Add('Despues, estas cuatro secciones, con estos titulos:')
  $l.Add('- "## Piezas comunes": una linea por cada pieza nueva que van a compartir varios ficheros, con su nombre completo (paquete incluido), que es (puerto, adaptador, configuracion...) y para que sirve. Si no hace falta ninguna, escribe "ninguna".')
  $l.Add('- "## Ficheros": una linea por cada fichero de la lista de hallazgos, asi:')
  $l.Add('  - `ruta/del/Fichero.java` -> que se hace | destino: paquete o clase de destino, o "-" | riesgo: bajo, medio o alto, y por que')
  $l.Add('- "## Orden": en que orden conviene hacerlos y por que (primero lo que otros necesitan).')
  $l.Add('- "## Dudas": lo que deberia decidir una persona. Si no hay, escribe "ninguna".')
  $l.Add('')
  $l.Add('No escribas contrasenas, hosts ni datos reales. No inventes: si no has podido leer un fichero, dilo en Dudas.')
  [System.IO.File]::WriteAllText((Join-Path $Work 'prompt.md'), ($l -join "`n"))

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
# ficheros) es lo que saltan los lotes y Get-SiguientePaso; $script:AtascadosInfo ('paso|fichero' -> entrada) es lo
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
# Mientras un lote puede dejar cambios sin commit en el arbol, .rescate/intento-en-curso.json apunta su paso, su lote y el
# commit del que parte (.rescate no se versiona: la marca no entra en ningun commit). Si el script se corta (Ctrl+C, la
# ventana, la luz), esos cambios a medias no son de nadie: el arranque siguiente los deshace en vez de guardarlos en la foto.
function Get-RutaIntento { return (Join-Path $Work 'intento-en-curso.json') }

function Save-Intento([string]$PasoId, [int]$N, [string]$Commit) {
  [System.IO.File]::WriteAllText((Get-RutaIntento), (ConvertTo-Json -Compress -InputObject ([ordered]@{ paso = $PasoId; lote = $N; commit = $Commit })))
}

function Remove-Intento { Remove-Item -LiteralPath (Get-RutaIntento) -Force -ErrorAction SilentlyContinue }

# Si hay marca, vuelve al commit de partida (lo cambiado sin commit y lo creado se va) y la borra.
function Undo-IntentoCortado([string]$Rama) {
  $p = Get-RutaIntento
  if (-not (Test-Path -LiteralPath $p)) { return }
  try { $m = [System.IO.File]::ReadAllText($p) | ConvertFrom-Json } catch { $m = $null }
  Remove-Intento
  $c = "$($m.commit)"
  if (-not $c -or (Invoke-Git $RepoRoot @('cat-file', '-e', $c)).Codigo -ne 0) { Aviso 'La marca del intento en curso no vale: la ignoro.'; return }
  Info "Habia un intento cortado (paso $($m.paso), lote $($m.lote)): lo deshago y sigo desde $($c.Substring(0, [Math]::Min(7, $c.Length)))."
  Undo-Lote $Rama $c
}

function Invoke-Fix {
  if (-not $PlantillaRoot) { Aviso 'Sin -Plantilla el arreglo va a ciegas. Muy recomendable pasarla.' }

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
  Info 'Diagnostico inicial (compilando)...'
  $hall = @(Invoke-Diagnostico $true (-not $SinTests))
  $script:Hall = $hall
  Write-Informe $hall
  Show-Resumen $hall

  $paso = $Paso
  if (-not $paso) { $paso = Get-SiguientePaso $hall }
  if (-not $paso) { $script:Siguiente = ''; Show-SinPasos 'Revisa los avisos del informe y pasa tu pipeline.'; return }
  if ($paso -ne 'build' -and -not $script:Build.Compila) {
    if ($script:Atascados.ContainsKey('build')) { Fallo "El proyecto no compila y 'build' se ha quedado atascado: no sigo con '$paso'."; $script:Parar = $true; return }
    Fallo "El proyecto no compila: primero hay que hacer -Paso build."; exit 2
  }
  foreach ($c in $Cfg.Orden) {
    if ($c -eq $paso) { break }
    $q = Get-Cuenta $hall $c
    if ($q -gt 0) { Aviso "Ojo: quedan $q errores en el paso anterior '$c'." }
  }
  # En cada lote se ejecutan los tests (salvo -SinTests); en 'tests' y 'e2e', siempre.
  $conTests = ((-not $SinTests) -or ($paso -eq 'tests') -or ($paso -eq 'e2e'))
  if ($conTests -and $script:Build.Compila -and -not $script:Build.TestsEjecutados) { $hall = @(Invoke-Diagnostico $true $true) }
  $loteEf = $Lote
  if ($Cfg.PasosDeUnoEnUno -contains $paso) { $loteEf = 1 }
  Info ''
  Info "=== Paso '$paso' en lotes de $loteEf ==="

  # --- revision previa: un plan para todo el paso, antes del primer lote ---
  if (-not $SinPlan -and ($Cfg.PasosConPlan -contains $paso)) {
    $plan = Invoke-Plan $paso $hall $false
    if ($plan -and $Auto) { Invoke-ConsejoPlan $paso @($hall | Where-Object { $_.Cat -eq $paso -and $_.Sev -eq 'error' }) }
    if ($plan -eq 'nuevo' -and -not $Auto) {
      $resp = Read-Host 'Lee el plan (puedes corregirlo). [Enter] seguir con los lotes | n = parar aqui'
      if ($resp -eq 'n') { $script:Parar = $true; return }
    }
  }

  $planB = @{}
  $consejoDe = @{}     # fichero atascado -> el consejo (de codigo) para su ultimo intento
  $motivos = @{}       # fichero -> por que no pasaron sus lotes (para el consejo)
  $reflexiones = @()   # las reflexiones del paso (Titulo, Texto, Ficheros)
  for ($n = 1; $n -le $MaxLotes; $n++) {
    $pend = @($hall | Where-Object { $_.Cat -eq $paso -and $_.Sev -eq 'error' })
    if ($pend.Count -eq 0) { break }
    $stuck = @()
    if ($script:Atascados.ContainsKey($paso)) { $stuck = @($script:Atascados[$paso]) }
    $fichs = @($pend | ForEach-Object { $_.Fichero } | Select-Object -Unique | Where-Object { $stuck -notcontains $_ })
    $sel = @($fichs | Select-Object -Skip $Saltar -First $loteEf)
    if ($sel.Count -eq 0) { break }
    # el intento con el consejo va con -Modelo, una sola vez y sin reflexion (despues no hay otro)
    $conIntento = ($sel.Count -eq 1 -and $consejoDe.ContainsKey($sel[0]))
    $mod = ''; $duda = $null; $intentos = $MaxIntentos
    if ($conIntento) { $duda = $consejoDe[$sel[0]].Dudas[0]; $intentos = 1 }
    elseif ($sel.Count -eq 1 -and $planB.ContainsKey($sel[0])) { $mod = $ModeloB }
    $reflexionar = ($Cfg.Reflexionar -and -not $conIntento)
    $buildAntes = $script:Build
    $loteH = @($pend | Where-Object { $sel -contains $_.Fichero })
    $antes = @{}
    foreach ($c in $Cfg.Orden) { $antes[$c] = Get-Cuenta $hall $c }
    $antes['calidad'] = Get-Cuenta $hall 'calidad'
    # los errores que ya habia, para reconocerlos si el intento mueve su fichero
    $hallAntes = @{}
    foreach ($x in @($hall | Where-Object { $_.Sev -eq 'error' })) { $hallAntes[(Get-ClaveHallazgo $x)] = $true }
    $antesCompila = $script:Build.Compila
    $check = ((Invoke-Git $RepoRoot @('rev-parse', 'HEAD')).Salida -join '').Trim()
    Info ''
    Info "--- Lote $n : $($loteH.Count) hallazgo(s) en $($sel.Count) fichero(s); pendientes del paso: $($pend.Count) ---"
    $sel | ForEach-Object { Info "  $_" }

    $ok = $false; $correccion = ''; $hall2 = @(); $blandos = @(); $problemas = @()
    $detalle = @(); $rutaCorr = ''   # los del ultimo intento que no paso (para el aviso del lote deshecho y para atascados.md)
    $g0 = Get-Guardas   # una vez por lote: los reintentos se comparan con el estado bueno
    Save-Intento $paso $n $check   # hasta que el lote se da por bueno o se deshace: si el script se corta, el arranque lo deshace
    for ($i = 1; $i -le $intentos; $i++) {
      $detalle = @(); $rutaCorr = ''
      $refl = @($reflexiones | Where-Object { @($_.Ficheros | Where-Object { $sel -contains $_ }).Count -gt 0 })
      [System.IO.File]::WriteAllText((Join-Path $Work 'prompt.md'), (New-Prompt $paso $loteH $correccion $duda $refl))
      Info "  Copilot trabajando (intento $i de $intentos)..."
      $rc = Invoke-Copilot (Join-Path $Work "lote-$paso-$n-$i.log") $mod '' "Copilot (paso $paso, lote $n, intento $i)"
      if ($rc.Codigo -ne 0) { Aviso "  Copilot termino con codigo $($rc.Codigo) (ver .rescate/lote-$paso-$n-$i.log)"; Write-FinCopilot $rc }

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
      if ($ramaAhora -ne $rama) { $problemas = @('Copilot cambio de rama.'); break }
      $head = ((Invoke-Git $RepoRoot @('rev-parse', 'HEAD')).Salida -join '').Trim()
      if ($head -ne $check) { [void](Invoke-Git $RepoRoot @('reset', '-q', '--mixed', $check)) }   # si hizo commit, lo deshago y conservo los cambios

      $cambios = @((Invoke-Git $RepoRoot @('status', '--porcelain', '--untracked-files=all')).Salida | Where-Object { $_ })
      if ($cambios.Count -eq 0) {
        $problemas = @('No has cambiado ningun fichero.')
        $correccion = '- No has cambiado ningun fichero. Resuelve los hallazgos del lote.'
        $rutaCorr = Save-CorreccionIntento $paso $n $i $sel $correccion
        if ($reflexionar) { $reflexiones += @(Invoke-Reflexion $paso $n $i $loteH $sel $check $correccion) }
        continue
      }

      # -- puertas: decide el script, no la IA --
      $problemas = @(); $blandos = @()
      if ($g1.Tests -lt $g0.Tests) { $problemas += "Has borrado tests ($($g0.Tests) -> $($g1.Tests) ficheros). Restauralos." }
      if ($g1.Desactivados -gt $g0.Desactivados) { $problemas += 'Has desactivado tests con @Disabled/@Ignore. Quitalo.' }
      if ($g1.Aserciones -lt $g0.Aserciones) { $blandos += "hay menos aserciones en los tests ($($g0.Aserciones) -> $($g1.Aserciones))" }
      # cuenta de todo el repo: llevar un catch a otro fichero no la baja
      $catchMenos = @()
      if ($g1.Catch -lt $g0.Catch) {
        $problemas += "Has quitado $($g0.Catch - $g1.Catch) catch ($($g0.Catch) -> $($g1.Catch)). El original sigue tras esos errores: manten el mismo tratamiento."
        $catchMenos = @($g0.CatchDe.Keys | Sort-Object | Where-Object { [int]$g1.CatchDe[$_] -lt $g0.CatchDe[$_] } | ForEach-Object { "  - $_ - catch: $($g0.CatchDe[$_]) -> $([int]$g1.CatchDe[$_])" })
      }
      $tocados = @($cambios | ForEach-Object { ($_.Substring(3) -replace '^"|"$', '') })
      if ($paso -ne 'build' -and ($tocados -contains 'pom.xml')) { $blandos += 'ha tocado pom.xml' }
      $fuera = @($tocados | Where-Object { -not $_.StartsWith('src/') -and $_ -ne 'pom.xml' })
      if ($fuera.Count -gt 0) { $blandos += ('ha tocado ficheros fuera de src: ' + (($fuera | Select-Object -First 6) -join ', ')) }

      Info '  Comprobando (Maven)...'
      $hall2 = @(Invoke-Diagnostico $true $conTests)
      $d = Get-Cuenta $hall2 $paso
      if (-not $script:Build.Compila -and ($paso -ne 'build' -or $antesCompila)) { $problemas += 'El proyecto no compila.' }
      if ($d -ge $antes[$paso]) { $problemas += "Los hallazgos de '$paso' no han bajado ($($antes[$paso]) -> $d)." }
      $empeorados = @()   # los pasos que el intento ha empeorado: sus hallazgos nuevos salen en el detalle
      foreach ($c in $Cfg.Orden) {
        if ($c -eq $paso) { break }
        $q = Get-Cuenta $hall2 $c
        if ($q -gt $antes[$c]) { $problemas += "Has empeorado el paso anterior '$c' ($($antes[$c]) -> $q hallazgos)."; $empeorados += $c }
      }
      $ft = Get-Cuenta $hall2 'tests'
      # sin 'tests' en Orden no hay cuenta de antes: no se compara
      if ($conTests -and $paso -ne 'tests' -and $antes.ContainsKey('tests') -and $ft -gt $antes['tests']) { $problemas += "Hay mas tests fallando que antes ($($antes['tests']) -> $ft)." }
      # el codigo nuevo sale ya con Javadoc y sin malas practicas: la cuenta de calidad no sube
      $qc = Get-Cuenta $hall2 'calidad'
      if ($paso -ne 'calidad' -and $qc -gt $antes['calidad']) {
        $problemas += "Tu codigo anade hallazgos de calidad ($($antes['calidad']) -> $qc). Lo que escribas lleva Javadoc y sigue las reglas de calidad."
        $empeorados += 'calidad'
      }
      $nuevos = @(Get-HallazgosNuevos $hall2 $empeorados $hallAntes | Select-Object -First 20)

      if ($problemas.Count -eq 0) { $ok = $true; break }
      $problemas | ForEach-Object { Aviso "  NO PASA: $_" }
      # lo del paso en los ficheros del lote y en los que el intento ha tocado o creado (un fichero movido deja un hallazgo nuevo en la ruta nueva),
      # y lo nuevo de los pasos que ha empeorado (y de calidad)
      $detalle = @((@($nuevos) + @($hall2 | Where-Object { $_.Sev -eq 'error' -and (
                ($_.Cat -eq 'build' -and $_.Detalle -match '^(no compila|el build falla)') -or
                ($_.Cat -eq 'tests' -and $conTests) -or
                ($_.Cat -eq $paso -and (($sel -contains $_.Fichero) -or ($tocados -contains $_.Fichero)))) } | Select-Object -First 20)) | ForEach-Object { '  ' + (Get-LineaHallazgo $_) } | Select-Object -Unique) + $catchMenos
      $correccion = ((@($problemas | ForEach-Object { "- $_" }) + @('Detalle:') + $detalle) -join "`n")
      # por pantalla, lo que se ha roto primero; el resto, y la correccion completa, en el fichero del intento
      $rutaCorr = Save-CorreccionIntento $paso $n $i $sel $correccion
      @(Get-LineasDetalle $detalle $rutaCorr) | ForEach-Object { Aviso $_ }
      if ($reflexionar) { $reflexiones += @(Invoke-Reflexion $paso $n $i $loteH $sel $check $correccion) }
    }
    Remove-Intento   # pase o no, ya se commitea o se deshace

    if (-not $ok) {
      # Nada se queda a medias: se deshace y se prueba algo mas facil.
      Undo-Lote $rama $check
      $script:Build = $buildAntes
      Aviso "Lote $n DESHECHO: no paso las comprobaciones tras $intentos intento(s)."
      $problemas | ForEach-Object { Aviso "  - $_" }
      @(Get-LineasDetalle $detalle $rutaCorr) | ForEach-Object { Aviso $_ }
      if ($rutaCorr) { Aviso "  Correccion completa del ultimo intento: $rutaCorr" }
      $conMod = ''
      if ($mod) { $conMod = ", con $mod" }
      foreach ($f in $sel) {
        if (-not $motivos.ContainsKey($f)) { $motivos[$f] = @() }
        $motivos[$f] += "lote $n ($($sel.Count) fichero(s)$conMod): " + ($problemas -join ' ')
      }
      if (-not $conIntento) {   # el intento del consejo no cuenta como lote deshecho seguido
        $script:Fallos++
        if ($script:Fallos -ge $Cfg.MaxFallosSeguidos) {
          Fallo "PARO: $($script:Fallos) lotes deshechos seguidos. Puede ser un problema de Copilot, de Maven o de un flag, no del codigo."
          Info "Ultimas lineas de Copilot (.rescate/lote-$paso-$n-*.log):"
          $rc.Salida | Select-Object -Last 8 | ForEach-Object { Info "  $_" }
          exit 2
        }
      }
      if ($sel.Count -gt 1) { Info '  -> lo reintento de uno en uno.'; $loteEf = 1; continue }
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
      Save-Atascados
      [System.IO.File]::AppendAllText((Join-Path $Work 'atascados.md'), $nota + "`n")
      continue
    }

    [void](Invoke-Git $RepoRoot @('add', '-A'))
    $d = Get-Cuenta $hall2 $paso
    $r = Invoke-Git $RepoRoot (@('commit', '-q', '-m', "rescate($paso): lote $n, hallazgos $($antes[$paso]) a $d") + $Cfg.CommitArgs)
    if ($r.Codigo -ne 0) { Fallo ('git commit ha fallado; los cambios siguen en el arbol de trabajo: ' + ($r.Salida -join ' ')); exit 3 }
    if ($conIntento) {
      Write-Consejo $consejoDe[$sel[0]] "atascado en '$paso': $($sel[0])" @('si, commit ' + ((Invoke-Git $RepoRoot @('log', '-1', '--format=%h')).Salida -join '').Trim())
      $consejoDe.Remove($sel[0])   # si al fichero le quedan hallazgos, su lote siguiente va como uno normal
    }
    $hall = $hall2
    $script:Fallos = 0
    Write-Informe $hall
    Bien "Lote $n OK: '$paso' $($antes[$paso]) -> $d. Commit hecho."
    (Invoke-Git $RepoRoot @('show', '--stat', '--oneline', '--format=%h %s', 'HEAD')).Salida | Select-Object -First 25 | ForEach-Object { Info "  $_" }
    $blandos | ForEach-Object { Aviso "  REVISA: $_" }

    if (-not $Auto -and $d -gt 0) {
      $resp = Read-Host '[Enter] siguiente lote | n = parar aqui | d = deshacer este lote y parar'
      if ($resp -eq 'd') { $script:Parar = $true; Undo-Lote $rama $check; Aviso 'Lote deshecho.'; return }
      if ($resp -eq 'n') { $script:Parar = $true; break }
    }
  }

  $script:Hall = $hall
  Show-Resumen $hall
  $sig = Get-SiguientePaso $hall
  $script:Siguiente = $sig
  if ($sig) { Info "Siguiente paso pendiente: $sig  ->  vuelve a lanzar con -Modo fix (o -Paso $sig)" }
  else { Show-SinPasos 'Revisa los avisos del informe, el diff completo de la rama y pasa tu pipeline.' }
}

# ================================= MAIN =================================
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Fallo "No encuentro 'git' en el PATH."; exit 1 }
$RepoRoot = Resolve-Dir $Repo
$PlantillaRoot = Resolve-Dir $Plantilla
$LegacyRoot = Resolve-Dir $Legacy
if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot '.git'))) { Fallo "No es la raiz de un repo git: $RepoRoot"; exit 1 }
if ($PlantillaRoot -and ($PlantillaRoot -eq $RepoRoot)) { Aviso 'Repo y plantilla son la misma carpeta: todo saldra permitido.' }

# Carpeta de trabajo. $OrigenRoot es la carpeta que has pasado en -Repo.
# Si ya hay worktree de rescate, se trabaja en el; fix y plan lo crean si falta.
$OrigenRoot = $RepoRoot
Set-Excluidos $OrigenRoot
[void](Read-CfgFile (Get-RutaAjustes) @() $false)   # ajustes.json: lleva claves de otros scripts, ninguna avisa; el del repo manda
Read-Config $OrigenRoot    # antes del worktree: CommitArgs vale tambien para el commit 'foto'
Test-Copilot               # antes del worktree: sin Copilot que lanzar no se toca el repo
if (-not $SinWorktree -and -not (Get-Rama $OrigenRoot).StartsWith('rescate/')) {
  $dirWt = Get-DirRescate
  if (-not (Test-WorktreeRescate $dirWt) -and ($Modo -eq 'fix' -or $Modo -eq 'plan')) { New-WorktreeRescate $dirWt }
  if (Test-WorktreeRescate $dirWt) {
    $RepoRoot = $dirWt
    Info "Carpeta de trabajo: $RepoRoot (worktree de rescate, rama '$(Get-Rama $RepoRoot)')"
    if ($Modo -eq 'diagnostico' -or $Modo -eq 'pre') { Info 'Para mirar tu carpeta original en vez del worktree: -SinWorktree' }
    Read-Config $RepoRoot
    Test-Copilot
  }
}

$Work = Join-Path $RepoRoot '.rescate'
if (-not (Test-Path -LiteralPath $Work)) { [void](New-Item -ItemType Directory -Path $Work) }

$script:Atascados = @{}   # paso -> ficheros que la IA no ha sabido arreglar
$script:AtascadosInfo = [ordered]@{}   # 'paso|fichero' -> lo que se guarda en atascados.json
$script:Hall = $null      # los hallazgos del ultimo estado bueno del fix
$script:Decidir = @()     # dudas de persona de los consejos del plan (las de los atascados van en AtascadosInfo)
# El modelo de las dudas: -ModeloDudas, si no el de la config, si no el de -Modelo. Su esfuerzo: -EsfuerzoDudas o el de
# la config (Invoke-Fuerte lo baja si Copilot no lo admite).
if (-not $ModeloB) { $ModeloB = "$($Cfg.ModeloB)" }   # -ModeloB manda; si no, el de la config
$script:ModDudas = $ModeloDudas
if (-not $script:ModDudas) { $script:ModDudas = "$($Cfg.ModeloDudas)" }
if (-not $script:ModDudas) { $script:ModDudas = $Modelo }
$script:EsfDudas = $EsfuerzoDudas
if (-not $script:EsfDudas) { $script:EsfDudas = "$($Cfg.EsfuerzoDudas)" }
$script:Fallos = 0        # lotes deshechos seguidos
$script:H = $null
$script:Build = $null
$script:BasePkg = ''
$script:Cal = $null
if ($PlantillaRoot) {
  Info 'Leyendo la plantilla...'
  $script:Cal = Get-Calibracion $PlantillaRoot
  Info ('Plantilla incumple: ' + (Get-TextoIncumple $script:Cal))
}

switch ($Modo) {
  'diagnostico' {
    if ($SinBuild) { Info 'Diagnostico sin Maven...' } else { Info 'Diagnostico (ejecutando Maven, puede tardar)...' }
    $hall = @(Invoke-Diagnostico (-not $SinBuild) (-not $SinTests))
    Write-Informe $hall
    Show-Resumen $hall
    $sig = Get-SiguientePaso $hall
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
        Info "Tu carpeta '$OrigenRoot' sigue como estaba. Desde ella:"
        Info "  ver que ha cambiado:  git diff --stat ${ro}...$ramaFin"
        Info "  traerlo a tu rama:    git merge $ramaFin      (o sube la rama y abre un PR)"
        Info "  borrar el worktree:   git worktree remove `"$RepoRoot`"      (la rama se conserva)"
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
    if ($script:Atascados.Count -gt 0) {
      Info 'Opciones: otro modelo (-Modelo / -ModeloB), arreglarlo a mano (la pasada siguiente lo intenta si el fichero cambia o si haces un commit), o volver a lanzar con -Reintentar.'
      exit 2
    }
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
