<#
prueba-local.ps1 - Prueba en local, caso a caso: el batch original frente al migrado, con las mismas entradas.
Compatible con Windows PowerShell 5.1 y PowerShell 7. Solo ASCII a proposito.
Necesita comun.ps1, tareas.ps1, regresion.ps1 y las carpetas tareas\ y regresion\ junto a este script, y los casos que deja migracion.ps1.

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
     El script deshace lo que toque fuera de eso (lo dice) y, del pom.xml, deja el del original con solo las dependencias nuevas
     de la IA, todas con <scope>test</scope>; despues comprueba que compila y que, con un caso vacio, cada job deja su estado.txt
     y que su base de prueba tiene las tablas que usa el codigo (las de src\main, sacadas con regex: Get-TablasBatch) y, en el migrado, las de la base
     del test del original (las de su caso vacio, sin BATCH_ ni TASK_; su primer intento ya lleva la lista). Un intento sin ellas se
     rechaza con la tabla y su fichero:linea (o con el nombre de la tabla del original); el ultimo, o un arnes guardado, se acepta con un aviso.
     Un fallo se repite una vez con el motivo; si vuelve a fallar, se para.
     Si la llamada se pasa del tope (SegundosArnes) o sale mal pero deja el test, se comprueba igual: si vale, se usa. Si no
     vale, el motivo lleva los dos fallos y, si fue por tiempo, el reintento sigue desde lo escrito. La IA solo puede lanzar
     mvn -q test-compile y mvn test -Dtest=PruebaLocalTest con -Dsurefire.timeout=SegundosTestArnes (la comprobacion tambien).
     Un arnes guardado de otro lanzamiento se comprueba antes de llamar a la IA, aunque su tarea no este hecha (la plantilla
     cambio, o el reintento quedo atascado): si sigue valiendo se usa, sin llamar a Copilot. Con -RehacerArnes, el del migrado
     se escribe otra vez (el del original no se toca); con -RehacerOriginal, el del original (por ejemplo, si su base
     de prueba no crea las tablas del codigo) y, con el, el del migrado. Lo mismo, sin pedirlo, si el guardado se escribio con otra
     plantilla (tareas\arnes-local.md) que la de ahora, o con una de antes de que la tarea la apuntara. Si el del original se
     escribe otra vez (por eso, o porque ya no vale en este commit), tambien el del migrado, que traduce el nuevo; esto vale
     tambien con -RehacerArnes. El primer intento de un test que se escribe otra vez lleva lo que fallo la otra vez: el ultimo
     motivo de su tarea de antes y, en el del original, las pistas de los casos que no se pudieron preparar y una linea por cada job (3 como
     mucho) cuyo caso vacio guardado no acabo COMPLETED, con su causa (Get-PrevioArnes): la de salidas\vacio\causas.json o, en uno guardado antes de M69, la del
     registro de Maven mas reciente del caso vacio del original (registros\mvn-<n>-arnes-original--caso-vacio.log), que se apunta al empezar (Save-Anterior); en el
     del migrado, las causas de fallo que se repiten y una linea por cada pareja de carpetas (3 como mucho) con 2 casos o mas donde el original y el migrado
     dejaban un fichero en carpetas distintas.
     El test que se escribe otra vez no se borra: pasa a prueba-local\arnes-anterior\<lado> (y el caso vacio del original, a
     salidas\vacio-anterior), pisando el de la vez anterior (Save-Anterior).
     El test del original que se escribe otra vez no puede quedar peor que el de antes con un caso vacio (el estado del job, las tablas y las columnas de
     su base): se rechaza con lo que falta y, en el ultimo intento, se vuelve al de antes (con su caso vacio) y el del migrado, si solo se escribia otra vez
     porque cambiaba el original, tambien; los casos hechos no se ejecutan otra vez. Tampoco puede dejar sin crear las columnas que el prueba-local.json de
     antes decia que no creaba (en el ultimo intento se acepta con un aviso).
     Si con un caso vacio el original arranca un job y el migrado no, el test del migrado se rechaza y, en el ultimo intento, se acepta con un aviso:
     de ese job se ejecuta solo el primer caso y, si acaba EXCEPCION con la misma clase, los demas salen sin probar (no se ejecutan); la linea
     final dice que puede ser el codigo del migrado y que se lo preguntes a Copilot en el repo del migrado, sin aconsejar -RehacerArnes.
     Si la causa del migrado es un error del codigo (una clase final con proxy, una referencia circular, un bean repetido: $ErroresCodigo, cada uno con su regla del paso
     de calidad de rescate.ps1), el test no se rechaza (otro intento no lo arregla): se acepta al primer intento con un aviso, tambien uno guardado, y la linea final dice
     que es el codigo del migrado, con la regla, sin aconsejar -RehacerArnes.
     Si el original falla igual (la misma causa) en los primeros 3 casos de un job ($CasosParaParar: no arranca, EXCEPCION o FAILED), los demas casos de ese job no se
     ejecutan ni en el original ni en el migrado y salen sin probar; la linea final dice que es el test del original y aconseja -RehacerOriginal (tambien si falla igual en
     todos los casos comparados, 2 o mas). Si es una ruta fija fuera del caso (NoSuchFileException...), el test que se escribe otra vez lleva la pista de su propiedad.
     Si el test de antes dejaba un job asi, no se vuelve a el aunque el nuevo quede peor con un caso vacio: se queda el nuevo y una Info lo dice. prueba-local.json
     lleva, por cada uno de esos jobs (y los del migrado con error del codigo), 'falloIgual' con el lado, el estado, la clase, la causa, la regla y si se paro.
  3. Entradas: una tarea de IA por caso (hasta 4 a la vez) escribe en la copia del original
     src\test\resources\prueba-local\<job>\<caso>\ (ficheros\, datos.sql, parametros.properties), o no-aplica.txt si
     el caso pide cambiar la configuracion. El script comprueba que solo escribe ahi y que el caso corre en el original.
     Si el job ni arranca en el original (estado=EXCEPCION), se lo dice a la IA una vez (si el caso no busca justo eso, que
     corrija las entradas) y despues lo acepta; igual con un caso hecho de antes cuya salida guardada del original dice eso.
     Si el caso no corre en el original porque su base no tiene una tabla o una columna (H2: Tabla "X" no encontrada), una tabla del codigo
     queda sin preparar y sin mas intentos (la IA no ve la base del test); una inventada o una columna se le dicen en el reintento.
  4. Ejecuta, sin IA: el original dos veces y el migrado una (un job y un caso por llamada de Maven: mvn surefire:test -Dtest=PruebaLocalTest, o
     mvn test con MavenCasoDirecto en false). El migrado se ejecuta
     siempre; el original (y el original-2) de un caso, solo si ha cambiado algo de lo que entra en su ejecucion (la lista, en el comentario
     de 'EL ORIGINAL NO SE REPITE'): si no, se reutilizan sus salidas de otro lanzamiento y la consola dice cuantos casos son. El original se
     ejecuta con UTF-8, como en el servidor (sus Maven llevan JAVA_TOOL_OPTIONS=-Dfile.encoding=UTF-8 y, con el, lo que ya hubiera). Para obligar a
     repetirlo todo, borra prueba-local\salidas. Antes de ejecutar un caso (en el original, en el migrado y al prepararlo), cada CREATE de su
     datos.sql (tabla, secuencia, indice, esquema, vista...) y cada ALTER TABLE ... ADD (columna, restriccion) que acepta IF NOT EXISTS lo lleva en la copia
     que se ejecuta (el test y Spring Batch ya crean cosas en su base y H2 dice 'ya existe'; lo guardado en casos\ no cambia), y el original de un caso
     hecho de antes cuyo error.txt guardado dice que algo ya existe se ejecuta otra vez. Cada caso, en su Maven
     (una JVM nueva, como en produccion), va sin red (-o) y sin los plugins de MavenCasoRapido (checkstyle, enforcer...); si sin red Maven
     no llega a ejecutar el test y su salida dice que es por la red (offline), se repite con red y esa copia sigue con red.
     Con MavenCasoDirecto (por defecto) cada copia se compila una vez (mvn test-compile) y cada caso va con mvn surefire:test, sin el ciclo
     de Maven (que repetia en cada caso validate, resources, compile y test-compile: mas de la mitad del tiempo de un caso): si cambia algo en
     el src\ de la copia (fuera de la carpeta de los casos) o en su pom.xml, se compila otra vez antes del siguiente caso. Si un caso no llega
     a ejecutarse asi (la salida de Maven con @{argLine}: se repite con -DargLine=), ese caso y los demas de esa copia van con mvn test, y la
     consola lo dice una vez. No promete: un plugin del pom ligado a la fase test que no sea surefire no se ejecuta en el modo directo
     (MavenCasoDirecto en false de ajustes.json lo deja todo con mvn test). De cada Maven de un caso apunta los segundos del Maven y los del
     test, y su modo (directo o ciclo), en datos\prueba-local-tiempos.json (una fila por ejecucion, se anade; la compilacion de una copia es
     otra fila, (compilar), y no entra en la media por caso) y, al acabar, dice cuanto es test y cuanto Maven, y cuantas veces y cuanto se compilo.
     En cuanto acaba el migrado de un caso, la consola dice una linea (Format-VeredictoCaso): 'caso-07: el migrado acaba EXCEPCION (<clase>: <causa>); el original, COMPLETED' o
     'caso-07: los dos acaban COMPLETED (la comparacion de ficheros, al final)' (sale de los estado.txt y de la causa de Maven; no adelanta la comparacion de ficheros). Si los
     3 primeros casos de un job ($CasosParaParar) acaban en el migrado FAILED o EXCEPCION con la misma causa (Get-FirmaFallo, como el original) y el original de ninguno falla con ella,
     los demas casos del job no se ejecutan en el migrado: salen sin probar, con su motivo, la consola lo dice una vez y prueba-local.json lleva su falloIgual con lado 'migrado'.
     Un job de menos de 3 casos no se para.
  5. Compara cada caso (estado.txt, ficheros\, tablas\ y envios\; no los ficheros de CompararIgnorar, por defecto los .log, el log por job del
     framework nuevo, ni cuentan como sin guardar si no se pudieron copiar), sin contar las horas sueltas ni las fechas con hora
     de la ejecucion (hoy, en hora local y en UTC; una fecha con hora de otro dia es un dato del negocio y cuenta) ni la
     fecha de hoy (en cada lado, los dias de su propia ejecucion: los de hoy en el migrado y los de cuando se ejecuto el original, que
     puede ser de otro dia; un caso distinto cuyo original es de otro dia se confirma ejecutandolo otra vez; un caso cuyo migrado no deja ni
     estado.txt sale distinto, con el motivo de que no lo corrio): igual, distinto,
     no determinista (el original da dos salidas distintas: no cuenta), no se pudo preparar
     o sin probar en local. Si un fichero solo cambia de codificacion o de formato de numeros, lo apunta como posible
     diferencia del JDK, sin esconderlo. Un caso que deja lo mismo que el caso vacio del arnes sale igual, con su aviso;
     pero si es asi con todos los casos de un job (y ninguno sale distinto), el test no le pasa las entradas al job: esos casos pasan a
     'no se pudo preparar' con ese motivo (no cuentan como iguales: el -Cierre no pasa), la prueba sigue con los demas jobs, guarda
     prueba-local.json como siempre y acaba con 2, como con casos distintos. Al final lo dice en rojo, una vez por job. Los tests guardados no se
     tocan: el usuario los arregla en prueba-local\arnes\<lado> y relanza sin -Rehacer, o relanza con -RehacerOriginal (el test del original y, con el, el del migrado) y la IA recibe ese motivo (Get-PrevioArnes).
     Una tabla (tablas\X.csv) sin filas de datos, o con solo la cabecera, en
     un solo lado es lo mismo que una tabla que no esta. Un fichero que el original deja en una carpeta y el migrado, con el mismo nombre (normalizado), en
     otra es una sola diferencia, de tipo otraCarpeta, y no un '(no esta)' por cada copia: dice las carpetas de cada lado y si el contenido es igual al de
     alguna copia del original o, si no, la primera linea distinta (Join-OtraCarpeta). Lo que solo esta en un lado y las tablas\ no se emparejan. Los casos
     con esa diferencia, aunque el nombre lleve otra fecha, son un solo grupo (la pareja de carpetas) y la consola dice que suele ser el test del migrado.
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
     diferencia tiene una clave (el nombre de su fichero, normalizado; la pareja de carpetas, si es otraCarpeta); se arregla primero la clave con mas casos distintos, y
     despues de cada arreglo se recalcula. Una tarea de IA por clave escribe, en la copia del migrado y solo en src\main\, el
     arreglo; el script lo da por bueno si pasa seis puertas, de la mas barata a la mas cara: la llamada acaba bien; la IA no
     dice que no se arregla (.rescate\reparar-no.txt: si la diferencia solo es de lo simulado en local); algo cambia en src\main\
     (lo que cambie fuera se deshace y se sigue con lo que quede); el caso de la tarea mejora; la suite de tests unitarios, sin
     el arnes, no falla mas ni se ejecuta menos que al empezar; y ningun otro caso empeora (ni claves nuevas, ni mas lineas distintas, ni
     deja de ejecutarse). Los tests van antes que los demas casos porque tardan mucho menos. Si tras el arreglo la clave sigue
     distinta en el caso (con menos lineas, pero no igual), la reparacion es 'mejorado' y no 'arreglado'. Un arreglo que pasa va a la
     rama de rescate (un commit por arreglo: 'rescate(local): <job>/<caso> <clave>'); uno que no pasa se deshace y se
     reintenta una vez con el motivo y el diff rechazado. Tu carpeta y tu rama no se tocan: revisa los commits de la rama de
     rescate antes del git merge. Como mucho MaxReparaciones claves por lanzamiento; lo que no se prueba se dice. Una clave
     que sale 'no se arregla' no se vuelve a probar con el mismo test del migrado: con -RehacerArnes (otro test), si. Un caso
     cuyo original da estado=EXCEPCION no se repara (se dice cuantos se saltan) y su resultado no cambia.
  8. Solo con -Regresion (hace falta el worktree de rescate, y su carpeta sin cambios sin commit): los casos que salen
     iguales se quedan en la rama de rescate como tests de JUnit, en un solo commit: sus entradas, lo que dejo el original
     (sin las tablas BATCH_ ni TASK_), el arnes del migrado y RegresionLocalTest, que corre despues y falla si lo que sale
     cambia. Antes del commit se prueba en una copia desechable (<Migrado>-regresion): pasa, y con un byte cambiado falla; un caso
     que no pasa o que lleva la fecha, la hora o la ruta de hoy se quita (datos\regresion.json lo cuenta). No cambia la salida.
  9. Solo con -Rapida (no se combina con -Reparar, -Regresion ni -Desde): para saber en minutos si un arreglo vale, sin esperar a todos los casos. Mismo arranque (las copias, los
     arneses, las comprobaciones y el caso vacio) y, de cada job, solo el primer caso (en el orden de siempre). Al acabar, la tabla y los grupos de esos casos y una linea: 'Prueba
     rapida: N casos de M. No vale para -Cierre'. No escribe ni borra datos\prueba-local.json (lo que lee -Cierre; ni prueba-local-grupos.jsonl): deja su resultado en
     datos\prueba-local-rapida.json. Un job cuyo caso deja lo mismo que el caso vacio se trata como en el paso 5, en ese json. Las salidas del original que
     guarda se reutilizan en la prueba entera (la clave de cada original ya cuenta lo que entra en su ejecucion).
  Lo de la IA queda en <Migrado>\migracion-<batch>\prueba-local\ (arnes\, casos\ y tareas\), con las salidas
  (salidas\original, original-2 y migrado, y originales.json con la clave y los dias de cada original) y los registros; el
  resultado, en datos\prueba-local.json. Al relanzar no se repite lo hecho (si no han cambiado sus entradas): se vuelve a ejecutar
  el migrado y a comparar, y el original solo si ha cambiado algo de lo que entra en su ejecucion.
  Rutas largas: un fichero cuya ruta en salidas pasa de 259 letras se guarda con un nombre corto (20 letras, ~ y un hash), el mismo en todos los
  lados, y si ni asi cabe, sin las carpetas de en medio (<primera carpeta>/<nombre corto>); uno que ni asi cabe no se guarda y su caso sale distinto,
  con ese fichero. Cuando un lado de un caso acaba FAILED, EXCEPCION o sin
  estado.txt, el resultado (campo fallos), la consola, la pagina 3 y el prompt de -Reparar llevan la causa que dejo su Maven (nunca la de una linea
  de aviso: TRACE, DEBUG, INFO, WARN o WARNING, salvo el aviso de Spring 'cancelling refresh attempt: <excepcion>' de un contexto que no arranca; sin
  excepcion, el mensaje del '[ERROR] Failed to execute goal'; sin estado.txt y con Maven en 0, que el test no ha dejado salida); sin causa, la consola dice
  en que registros\mvn-<n>-<que>.log mirar, y el fallo lleva 'registro'.
  Con -Job, el JSON lleva ademas lo de los demas jobs tal como estaba (casos, jobs, reparaciones y culpables) si se probo con el mismo
  commit del migrado y del original; con otro commit se descarta y lo dice. La consola solo ensena los jobs de ahora.

USO
  .\prueba-local.ps1 -Legacy C:\ruta\life-java8 -Migrado C:\ruta\batch-life
  .\prueba-local.ps1 ... -Modelo <id>          # sin esto, el que uso migracion.ps1
  .\prueba-local.ps1 ... -JavaLegacy C:\jdk8   # el JDK del original, si no compila con el de Maven
  .\prueba-local.ps1 ... -Job cargaRecibosJob  # solo los casos de ese job
  .\prueba-local.ps1 ... -Rapida              # solo el primer caso de cada job, en minutos: para comprobar un arreglo (no vale para -Cierre ni deja prueba-local.json)
  .\prueba-local.ps1 ... -Si                   # no pregunta antes de llamar a Copilot
  .\prueba-local.ps1 ... -Desde <commit>       # y, de cada caso distinto, el commit de la rama que lo rompe
  .\prueba-local.ps1 ... -Desde <commit> -Deshacer   # y deshace esos commits con git revert (solo commits nuevos encima)
  .\prueba-local.ps1 ... -Reparar             # y arregla el migrado (en la rama de rescate) hasta que los casos distintos salgan iguales
  .\prueba-local.ps1 ... -Regresion          # y deja los casos que salen iguales como tests de JUnit en la rama de rescate (un commit)
  .\prueba-local.ps1 ... -RehacerArnes        # escribe otra vez con la IA el test del migrado: si la IA de -Reparar dice que la diferencia es del test del migrado
  .\prueba-local.ps1 ... -RehacerOriginal     # escribe otra vez con la IA el test del original (y, traduciendolo, el del migrado): si su base de prueba no crea las tablas del codigo

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
  [switch]$Rapida,            # solo el primer caso de cada job; su resultado va a prueba-local-rapida.json y no toca prueba-local.json (no con -Reparar, -Regresion ni -Desde)
  [string]$Desde = '',        # un commit de la rama que se prueba: busca el commit que rompe cada caso distinto
  [switch]$Deshacer,          # con -Desde: deshace con git revert los commits que rompen (la unica vez que se toca tu rama)
  [switch]$Reparar,           # arregla el migrado, en la rama de rescate, hasta que los casos distintos salgan iguales (no con -Desde)
  [switch]$Regresion,         # deja los casos que salen iguales como tests de JUnit (RegresionLocalTest) en la rama de rescate, en un commit
  [switch]$RehacerArnes,      # escribe otra vez con la IA el test del migrado (el de antes pasa a arnes-anterior), traduciendo el del original (que no se toca)
  [switch]$RehacerOriginal,   # escribe otra vez con la IA el test del original (el de antes pasa a arnes-anterior), y con el el del migrado, que lo traduce
  [switch]$Si                 # no preguntar antes de llamar a Copilot
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'comun.ps1')
. (Join-Path $PSScriptRoot 'tareas.ps1')
. (Join-Path $PSScriptRoot 'regresion.ps1')

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
  # Cada caso con 'mvn surefire:test' (solo el test, sobre lo que 'mvn test-compile' dejo compilado en la copia: Invoke-Compilar compila una vez por copia y por estado de su
  # src\ y su pom.xml) en lugar de 'mvn test' (el ciclo entero: validate, generacion de codigo, resources, compile y test-compile en cada caso, mas de la mitad del tiempo).
  # En false (en ajustes.json: "MavenCasoDirecto": false), cada caso con mvn test como antes. Lo que no promete: un plugin del pom ligado a la fase test que no sea surefire
  # no se ejecuta en el modo directo.
  MavenCasoDirecto = $true
  # Propiedades que saltan plugins que no influyen en el test: Invoke-Job las pasa en cada caso y en el test-compile de la copia (no en el arnes ni en los
  # tests unitarios). Sin JaCoCo: su argLine lo usa surefire. Vacia la lista (en ajustes.json: "MavenCasoRapido": []) para no saltar ninguno.
  MavenCasoRapido = @('-Dcheckstyle.skip', '-Denforcer.skip', '-Dspotbugs.skip', '-Dpmd.skip', '-Dmaven.javadoc.skip', '-Dmaven.source.skip', '-Dmaven.gitcommitid.skip', '-Dlicense.skip')
  # Ficheros de la salida de un caso que no se comparan, en ninguno de los dos lados (Test-Ignorado): patrones como -like sobre el nombre del fichero. El framework nuevo
  # deja un log por job en ficheros\logs\ y el original no: no es salida del batch. Vacia la lista (en ajustes.json: "CompararIgnorar": []) para compararlo todo.
  CompararIgnorar = @('*.log')
}
$Casos = 'src/test/resources/prueba-local'   # donde van los casos dentro de cada copia
# Una linea de una plantilla cuya clave {{SI_...}} vale esto no sale en el prompt (Invoke-Lote): asi una plantilla lleva dos variantes
# de un parrafo y cada tarea elige una. Ninguna otra linea de las plantillas empieza asi.
$MarcaNo = '<!--no-->'
# El aviso de un caso igual que deja lo mismo que el caso vacio del arnes (Get-Resultado); Get-JobsVacios lo busca.
$MotivoVacio = 'Sale lo mismo que con el caso vacio del arnes: si el caso tiene entradas, mira que lleguen al job.'
# Lo que dicen los casos de un job donde todos dejan lo mismo que el caso vacio (Get-JobsVacios): no se pudieron preparar, que el test no les pasa las entradas.
$MotivoSinEntradas = 'El test no le pasa las entradas al job: ningun caso deja nada distinto del caso vacio.'
$MotivoNoArranca = 'el migrado no arranca el job con este test'
# Lo que dice un caso que no se ejecuta porque el original de su job falla igual en los primeros $CasosParaParar casos (Invoke-Originales); Get-Resultado lo pone como motivo.
$MotivoNoArrancaOriginal = 'el original falla igual en los primeros casos de este job con este test y no se ejecutan los demas: relanza con -RehacerOriginal'
# Lo mismo con el migrado (Invoke-Salidas): sus primeros $CasosParaParar casos fallan igual y el original de esos casos no falla con esa causa.
$MotivoMigradoFallaIgual = 'el migrado falla igual en los primeros casos de este job con este test y no se ejecutan los demas: arreglalo y relanza (con -Rapida para comprobarlo)'
# Los errores del CODIGO del migrado que hacen que su job no arranque (Get-ErrorCodigo): otro test no los arregla. Cada uno con el patron de su clase o su causa, la regla del
# paso de calidad de rescate.ps1 que lo detecta y una frase. Las fuentes (spring-framework, descargadas en fuentes-m77): 'Cannot subclass final class' es el texto de
# Enhancer (cglib/Enhancer.java:653, y CglibAopProxy.java:221-223 lo envuelve en 'Common causes of this problem include using a final class'); BeanCurrentlyInCreationException
# (spring-beans/.../BeanCurrentlyInCreationException.java:23-25) dice 'unresolvable circular reference'; BeanDefinitionOverrideException (spring-beans/.../support/
# BeanDefinitionOverrideException.java:22) y ConflictingBeanDefinitionException (ClassPathBeanDefinitionScanner.java:350 la lanza; su clase, spring-context/.../annotation/
# ConflictingBeanDefinitionException.java:16) son dos beans con el mismo nombre. Una NoSuchBeanDefinitionException o una BeanCreationException sin mas puede ser el test (le falta un bean): no estan.
$ErroresCodigo = @(
  [pscustomobject]@{ patron = 'Cannot subclass final class'; regla = 'clase-final-proxy'; frase = 'una clase final que Spring tiene que envolver con un proxy' }
  [pscustomobject]@{ patron = 'BeanCurrentlyInCreationException|unresolvable circular reference'; regla = 'referencia-circular'; frase = 'beans que se necesitan unos a otros en circulo' }
  [pscustomobject]@{ patron = 'BeanDefinitionOverrideException|ConflictingBeanDefinitionException'; regla = 'bean-repetido'; frase = 'dos beans con el mismo nombre' }
)
# Cuantos casos seguidos de un job (los primeros) tienen que acabar en el original FAILED o EXCEPCION con la misma causa (Get-FirmaFallo) para que sus demas casos no se ejecuten
# ni en el original ni en el migrado (Invoke-Originales): el original funciona en produccion, asi que si falla igual en todos es su test, no su codigo.
$CasosParaParar = 3
# Las clases de excepcion con las que un contexto de Spring no se puede montar (Test-ExcepcionArranque): la jerarquia de BeansException de spring-framework (spring-beans/src/main/java/
# org/springframework/beans/BeansException.java:23 y las que la heredan, una a una; ConflictingBeanDefinitionException e ImplicitlyAppearedSingletonException heredan de
# IllegalStateException y NoSuchMessageException de RuntimeException: no entran), ApplicationContextException (spring-context/.../context/ApplicationContextException.java:16, hereda
# de FatalBeanException) y ConfigurationPropertiesBindException de spring-boot (fuentes-m77/spring-boot/ConfigurationPropertiesBindException.java:18, hereda de
# BeanCreationException). Una JobParametersInvalidException, una IllegalArgumentException del negocio o un FAILED no estan: un caso puede buscar justo eso.
$ExcepcionesArranque = @(
  'ApplicationContextException', 'BeanCreationException', 'BeanCreationNotAllowedException', 'BeanCurrentlyInCreationException', 'BeanDefinitionOverrideException',
  'BeanDefinitionParsingException', 'BeanDefinitionStoreException', 'BeanDefinitionValidationException', 'BeanExpressionException', 'BeanInitializationException',
  'BeanInstantiationException', 'BeanIsAbstractException', 'BeanIsNotAFactoryException', 'BeanNotOfRequiredTypeException', 'BeansException', 'CannotLoadBeanClassException',
  'ConfigurationPropertiesBindException', 'ConversionNotSupportedException', 'FactoryBeanNotInitializedException', 'FatalBeanException', 'InvalidPropertyException',
  'InvalidPropertyPathException', 'MethodInvocationException', 'NoSuchBeanDefinitionException', 'NoUniqueBeanDefinitionException', 'NotReadablePropertyException',
  'NotWritablePropertyException', 'NullValueInNestedPathException', 'PropertyAccessException', 'PropertyBatchUpdateException', 'ScopeNotActiveException',
  'TypeMismatchException', 'UnsatisfiedDependencyException', 'XmlBeanDefinitionStoreException'
)
# La causa de un lado sin estado.txt cuyo Maven acabo con 0 y sin otra causa (Get-Fallos): el test no encontro la carpeta del caso (arnes\migrado, regla 1).
$MotivoMavenSinSalida = 'Maven acaba bien, pero el test no ha dejado salida: no ha ejecutado el caso (mira si ve su carpeta en src\test\resources\prueba-local)'
# Lo que dice el motivo de un caso cuyo original no corre porque la base del test no tiene una tabla del codigo (Get-MotivoBase): la cuenta del final de la
# prueba lo busca. $PatronTablaFalta es el error de H2 de una tabla o una columna que no esta (Get-MotivoBase y Get-PistaArnes).
$PrefijoSinTabla = 'La base de prueba no tiene la tabla '
$PatronTablaFalta = '(?i)\b(Table|Tabla|Column|Columna)\s+"([^"]+)"\s+(?:not found|no encontrada)'
# El error.txt de un caso cuyo datos.sql crea algo que ya esta en la base del test (o que Spring Batch crea solo en el migrado): H2 dice 'Tabla "X" ya existe' o
# 'Sequence "X" already exists' y el codigo ([42101-...], [90035-...]). Lo que dicen los _messages_*.prop de H2 (1.4.193, 1.4.200 y 2.x) y su ErrorCode.java: ya existe
# o already exists (tabla 42101, indice 42111, usuario 90033, secuencia 90035, vista 90038, trigger 90041, restriccion 90045, rol 90069, alias de funcion y
# agregado 90076, esquema 90078, constante 90114, dominio 90119) y la columna repetida (42121: 'Duplicate column name' o 'Nombre de columna Duplicada'), que solo
# cuenta si el error trae un ALTER TABLE (un CREATE TABLE con dos columnas iguales es un error del SQL, no de la base y no se arregla ejecutandolo otra vez).
# Reset-OriginalesYaExiste lo busca en el error.txt guardado de un original.
$CodigosYaExiste = '(?<!\d)(?:42101|42111|90033|90035|90038|90041|90045|90069|90076|90078|90114|90119)(?!\d)'
$ColumnaRepetida = '(?:duplicate column name|nombre de columna duplicada|(?<!\d)42121(?!\d))'
$PatronYaExiste = '(?i)ya existe|already exists|' + $CodigosYaExiste + '|(?s:ALTER\s+TABLE.*' + $ColumnaRepetida + '|' + $ColumnaRepetida + '.*ALTER\s+TABLE)'
# Lo que dice el motivo de un caso cuyo original no corre porque el test crea mal una tabla (Get-MotivoTablaMal): la cuenta del final de la prueba lo busca.
# $PatronCreateTabla es el CREATE TABLE que H2 rechaza (grupo s, la sentencia): el error de H2 (Get-PistaArnes y Get-MotivoTablaMal) o ese motivo ya dicho
# (Get-PistaArnes sobre el prueba-local.json de antes, donde el motivo ya no trae el error).
$PrefijoTablaMal = 'El test del original crea mal una tabla: '
$PatronCreateTabla = '(?im)(?:(?:Syntax error in SQL statement|Error de Sintaxis en sentencia SQL)\s+"|' + [regex]::Escape($PrefijoTablaMal) + ')(?<s>CREATE TABLE.*?)(?:"\s*;|$)'
# Lo que dice el motivo de un caso cuyo original no corre porque el test no crea una columna que usa el codigo (Get-MotivoColumna): la cuenta del final de la prueba
# lo busca. $PatronColumnaSinCrear es ese motivo ya dicho (grupos t, la tabla si se sabe; c, la columna; s, el sitio: Get-PistaArnes sobre el prueba-local.json
# de antes, donde el motivo ya no trae el error de H2).
$PrefijoSinColumna = 'El test del original no crea la columna '
$PatronColumnaSinCrear = [regex]::Escape($PrefijoSinColumna) + '(?:(?<t>\w+)\.)?(?<c>\w+) \(la usa (?<s>.+?:\d+)\)'
# Un DROP TABLE que H2 rechaza porque otra tabla depende de la que se borra (grupo 1, la tabla): 'Cannot drop "X" because' o 'Imposible eliminar "X" debido a que'.
$PatronDrop = '(?i)(?:Cannot drop|Imposible eliminar)\s+"([^"]+)"\s+(?:because|debido a que)'
# Una propiedad sin valor en el test (Get-PistaArnes), por su clave (grupo k): los mensajes de Spring y de Spring Boot ('Could not resolve placeholder 'x'',
# 'Failed to bind properties under 'x''; la clave, lo que haya entre comillas) y, sin comillas, '<clave> is not configured|is not set|must be set|is required|is
# missing' o en espanol 'no esta configurad|es obligatori', con la clave de al menos un punto (app.export.dir): una palabra suelta o una clase no cuentan.
$PatronPropiedad = '(?i)(?:Could not resolve placeholder|Failed to bind properties under) ''(?<k>[^'']+)''|(?<k>[A-Za-z][\w-]*(?:\.[\w-]+)+)[ \t]+(?:is not configured|is not set|must be set|is required|is missing|no est\S+ configurad|es obligatori)'
# Una ruta fija que el original no encuentra o no puede abrir (Get-PistaCarpeta), por su clase (grupo c) y su ruta absoluta (grupo r: 'C:\x\y' o '/x/y', hasta el
# primer espacio, parentesis o comilla): NoSuchFileException, FileNotFoundException y AccessDeniedException de java.nio.file y java.io.
$PatronRutaFija = '(?<c>NoSuchFileException|FileNotFoundException|AccessDeniedException):\s*(?<r>(?:[A-Za-z]:[\\/]|/)[^\s()''"]+)'
# Lo que se anade a JAVA_TOOL_OPTIONS en cada Maven del original (Invoke-Maven; lo leen Maven, javac y la JVM de surefire, y no pisa el argLine del pom): el original
# es Java 8 u 11 y en Windows lee y escribe con la codificacion del sistema (Cp1252); en el servidor (Linux) y en el migrado (Java 18 o mas, JEP 400) es UTF-8.
$OpcionJvmOriginal = '-Dfile.encoding=UTF-8'
$NoPromete = 'Lo que esto no promete: las entradas son inventadas y lo de fuera (base de datos, SFTP, correo, HTTP) esta simulado. La conexion de verdad se prueba en pre, con el guion de cada job.'
$Inv = [System.Globalization.CultureInfo]::InvariantCulture
$Latin = [System.Text.Encoding]::GetEncoding(28591)
$Utf8Estricto = New-Object System.Text.UTF8Encoding($false, $true)
$RutasCopia = @()   # las rutas de las dos copias, en sus formas: Get-Normal las cambia por <copia>
$Hoy = @()          # las fechas de la ejecucion (Get-Hoy): Get-Resultado las pone al dia en cada comparacion
# Windows PowerShell 5.1 no pasa de 260 letras en una ruta (MAX_PATH: 259 y el fin de cadena). La misma regla vale en todos los sistemas, para
# que se pruebe en Linux y no cambie de una maquina a otra (ver Get-RelSalida).
$LimiteRuta = 259
# Un metodo de un test que prepara algo antes de lanzar el job: la anotacion (JUnit 5 o 4; \b: @BeforeTransaction no), otras anotaciones de por medio, los
# modificadores y el tipo (grupo 1: el nombre del metodo). Lo usa Get-PreparaEjemplos.
$PatronPrepara = '@(?:BeforeEach|BeforeAll|BeforeClass|Before)\b(?:\s*\([^)]*\))?(?:\s*@\w+(?:\s*\([^)]*\))?)*\s*(?:(?:public|protected|private|static|final|synchronized)\s+)*[\w<>\[\].,?]+\s+(\w+)\s*\('
# Las causas de lo que fallo de antes que lleva el prompt del test que se escribe otra vez (Get-LineasFallo): las que tienen
# al menos CausasMinimas casos y hasta CausasMaximas, de 200 letras como mucho cada una.
$CausasMinimas = 2
$CausasMaximas = 3
# Si se esta en Windows: lo lee Get-RutaLarga (es una variable para que las pruebas lo simulen en Linux).
$SoWindows = ([System.IO.Path]::DirectorySeparatorChar -eq '\')
# La version del formato de lo que se guarda en prueba-local\salidas (los nombres de sus ficheros, ver Get-RelSalida): va en la clave del original
# (Get-ClaveBaseOriginal). Sube cada vez que cambia ese formato: lo guardado con otro se ejecuta otra vez, una vez, y no se compara con lo de ahora.
$VersionSalidas = 2
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

# Avisa (en amarillo, sin parar) si $Dir tiene cambios sin commit en src o pom.xml: la copia de la prueba sale de su ultimo commit ($Head) y no los ve.
# Lo de fuera de src y pom.xml (migracion-*/, ficheros sueltos) no cuenta.
function Write-AvisoSinCommit([string]$Dir, [string]$Head) {
  $r = Invoke-Git $Dir @('status', '--porcelain', '--', 'src', 'pom.xml')
  if ($r.Codigo -ne 0 -or @($r.Salida | Where-Object { $_ }).Count -eq 0) { return }
  Aviso "$Dir tiene cambios sin commit en src o pom.xml: la prueba usa su ultimo commit ($($Head.Substring(0, [Math]::Min(7, $Head.Length)))) y no los ve. Si son parte del arreglo, haz commit y vuelve a lanzar."
}

# Rehace la copia desechable $Dir de $Repo en $Commit (un worktree sin rama). Una carpeta que ya existe solo se borra
# si es un worktree de ese mismo repo. La copia no trae lo que git no tiene: de .mvn/wrapper/ (maven-wrapper.properties suele no estar
# en git) se llevan los ficheros de $Repo que la copia no tiene, para que su mvnw arranque sin bajarse nada. Devuelve '' o el motivo.
function New-Copia([string]$Repo, [string]$Commit, [string]$Dir) {
  if (Test-Path -LiteralPath $Dir) {
    if (-not (Test-CopiaDe $Repo $Dir)) { return "La carpeta $Dir ya existe y no es una copia de la prueba local de $Repo. Muevela o borrala y vuelve a lanzar." }
    $r = Invoke-Git $Repo @('worktree', 'remove', '--force', $Dir)
    if ($r.Codigo -ne 0) { return ("No he podido borrar la copia anterior ($Dir): " + ($r.Salida -join ' ')) }
  }
  # -f: vale aunque git aun tenga apuntada una copia anterior que alguien borro a mano
  $r = Invoke-Git $Repo @('worktree', 'add', '-q', '-f', '--detach', $Dir, $Commit)
  if ($r.Codigo -ne 0) { return ("No he podido crear la copia ${Dir}: " + ($r.Salida -join ' ')) }
  $wrapper = Join-Path (Join-Path $Repo '.mvn') 'wrapper'
  if (Test-Path -LiteralPath $wrapper) {
    foreach ($f in @(Get-ChildItem -LiteralPath $wrapper -Recurse -File)) {
      $a = Join-Ruta $Dir ('.mvn/wrapper/' + (Get-Rel $wrapper $f.FullName))
      if (-not (Test-Path -LiteralPath $a)) { Copy-Fichero $f.FullName $a }
    }
  }
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

# Borra una carpeta con lo que lleva. En Windows, si Remove-Item no puede (una ruta de mas de 259 letras, de un fichero que dejo un job), lo
# intenta con 'rd /s /q' y la ruta con el prefijo \\?\, que no tiene ese limite; si tampoco, lo dice en un aviso y sigue.
function Remove-Carpeta([string]$Dir) {
  if (-not (Test-Path -LiteralPath $Dir)) { return }
  try { Remove-Item -LiteralPath $Dir -Recurse -Force }
  catch {
    $error1 = $_.Exception.Message
    if ([System.IO.Path]::DirectorySeparatorChar -ne '\') { throw }
    $largo = '\\?\' + ([System.IO.Path]::GetFullPath($Dir) -replace '/', '\')
    try { $null = & cmd.exe /c ('rd /s /q "' + $largo + '"') 2>&1 } catch { }
    if (Test-Path -LiteralPath $Dir) { Aviso "No he podido borrar ${Dir}: $error1" }
  }
}

# La ruta de origen $Ruta (la completa, FullName) para leer un fichero: en Windows, si pasa de $LimiteRuta letras, con el prefijo \\?\ (o \\?\UNC\ y la ruta sin
# las dos barras, si es de red), que no tiene el limite de 259 letras de Windows PowerShell 5.1 (y .NET Framework 4.6.2 o posterior lo admite). Con \\?\ Windows no
# normaliza la ruta: las / pasan a \. Sin cambio si es corta, si ya lleva el prefijo o si no se esta en Windows ($EsWindows, por defecto $SoWindows).
function Get-RutaLarga([string]$Ruta, [bool]$EsWindows = $SoWindows) {
  if (-not $EsWindows -or $Ruta.Length -le $LimiteRuta -or $Ruta.StartsWith('\\?\')) { return $Ruta }
  $r = $Ruta -replace '/', '\'
  if ($r.StartsWith('\\')) { return '\\?\UNC\' + $r.Substring(2) }
  return '\\?\' + $r
}

# Copia $De a $A con .NET: el segundo intento de Copy-Fichero con una ruta larga (File.Copy admite el prefijo \\?\ en .NET Framework 4.6.2 o posterior, pero depende de
# como arranque el host el manejo de rutas antiguas). Es una funcion para que las pruebas la cambien.
function Copy-ConDotNet([string]$De, [string]$A) { [System.IO.File]::Copy($De, $A, $true) }

# Copia $De a $A. Con un origen de mas de 259 letras en Windows (Get-RutaLarga) prueba Copy-Item con la ruta con prefijo (el proveedor de ficheros de Windows
# PowerShell 5.1 suele aceptarla) y, si lanza, Copy-ConDotNet con la misma; si fallan las dos, sale el error de la segunda.
function Copy-Fichero([string]$De, [string]$A) {
  $d = Split-Path $A -Parent
  if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -Force) }
  $origen = Get-RutaLarga $De
  if ($origen -ceq $De) { Copy-Item -LiteralPath $De -Destination $A -Force; return }
  try { Copy-Item -LiteralPath $origen -Destination $A -Force -ErrorAction Stop }
  catch { Copy-ConDotNet $origen $A }
}

# Copia los ficheros de la carpeta $De (con sus subcarpetas) a $A, pisando los que haya. Sin $De, nada.
function Copy-Carpeta([string]$De, [string]$A) {
  if (-not (Test-Path -LiteralPath $De)) { return }
  foreach ($f in @(Get-ChildItem -LiteralPath $De -Recurse -File)) { Copy-Fichero $f.FullName (Join-Ruta $A (Get-Rel $De $f.FullName)) }
}

# ============================ NOMBRES DE SALIDAS ============================
# Lo que se guarda en prueba-local\salidas\<lado>\<job>\<caso>\ puede pasar de 259 letras: el job escribe un fichero con la fecha en el nombre y la carpeta
# del usuario ya es profunda. Un fichero que no cabe se guarda en la misma carpeta con un nombre corto, '<20 primeras letras del nombre>~<hash de
# su ruta><extension>'; si ni asi cabe, aplanado, sin las carpetas de en medio: '<primera carpeta de la ruta>/<ese mismo nombre corto>' (un job que escribe en
# ficheros/<carpeta>/<nombre del job>/<fecha-hora>/<hash>.xlsx deja de depender de lo larga que sea esa ruta); y uno que ni asi cabe no se guarda: se apunta y
# el caso sale distinto (Copy-Salida y Get-Resultado).
# LA MISMA REGLA EN TODOS LOS LADOS: lo que decide si un fichero cabe no es el lado donde se guarda (original, original-2, migrado, vacio...),
# sino la ruta mas larga que puede tener en salidas: salidas\culpable\<12 letras>\<job>\caso-000\<ruta>. Si cabe ahi, cabe en todos y se guarda
# con su nombre; si no, se guarda con el nombre corto en todos. Asi un mismo fichero tiene el mismo nombre en todos los lados y se empareja
# al comparar. El hash y el prefijo salen de la ruta ya normalizada (Get-Normal, con los dias de la ejecucion que dejo el fichero): un original de
# otro dia y el migrado de hoy, con la fecha de su dia en el nombre (o en una carpeta que el aplanado quita), dan el mismo nombre corto.
# Coste: un fichero que cabria en original o migrado pero no en esa ruta (hasta ~12 letras de margen) tambien se guarda con el nombre corto.

# Las letras de la ruta mas larga de salidas de un fichero de $Rel del job $Job, con el prefijo de la carpeta del proyecto ($Local).
function Get-LargoRuta([string]$Job, [string]$Rel) {
  return ($Local.Length + $Job.Length + 41 + $Rel.Length)   # <Local>/salidas/culpable/000000000000/<Job>/caso-000/<Rel>
}

# $Rel con su nombre acortado: '<20 primeras letras del nombre normalizado, sin los signos que Windows no admite>~<Get-Hash8 de la ruta normalizada>
# <extension>' (la extension, si no pasa de 10 letras), en su carpeta; con $Plano, solo en la primera carpeta de $Rel (sin las de en medio). $Dias son los
# dias de la ejecucion que dejo el fichero (Get-Normal).
function Get-NombreCorto([string]$Rel, $Dias, [bool]$Plano = $false) {
  $normal = Get-Normal $Rel $Dias
  $i = $normal.LastIndexOf('/')
  $nombre = $normal.Substring($i + 1)
  $ext = ''
  $m = [regex]::Match($nombre, '\.[^.]*$')
  if ($m.Success) { $ext = $m.Value; $nombre = $nombre.Substring(0, $m.Index) }
  $limpia = '[<>:"|?*\\/]'
  $nombre = $nombre -replace $limpia, ''
  $ext = $ext -replace $limpia, ''
  if ($nombre.Length -gt 20) { $nombre = $nombre.Substring(0, 20) }
  if ($ext.Length -gt 11) { $ext = '' }
  $j = $Rel.LastIndexOf('/')
  if ($Plano) { $j = [Math]::Min($j, $Rel.IndexOf('/')) }
  return ($Rel.Substring(0, $j + 1) + $nombre + '~' + (Get-Hash8 $normal) + $ext)
}

# Es $Rel un nombre de los de Get-NombreCorto (con sus carpetas o aplanado)? (regresion.ps1: ese fichero no se puede dejar como test, ver Get-MotivoCambiante)
function Test-NombreCorto([string]$Rel) { return ($Rel -cmatch '~[0-9a-f]{8}(\.[^/.]*)?$') }

# La ruta con la que se guarda en salidas el fichero $Rel del job $Job: la misma si cabe (ver arriba), la del nombre corto si no, el nombre corto en la
# primera carpeta si ni asi, o $null si ni aplanado. El hash es el de la ruta entera: dos ficheros distintos no chocan al aplanar.
function Get-RelSalida([string]$Job, [string]$Rel, $Dias) {
  if ((Get-LargoRuta $Job $Rel) -le $LimiteRuta) { return $Rel }
  $corto = Get-NombreCorto $Rel $Dias
  if ((Get-LargoRuta $Job $corto) -le $LimiteRuta) { return $corto }
  $plano = Get-NombreCorto $Rel $Dias $true
  if ((Get-LargoRuta $Job $plano) -le $LimiteRuta) { return $plano }
  return $null
}

# Copia los ficheros de la carpeta $De a $A (una carpeta de prueba-local\salidas del job $Job), con la ruta de Get-RelSalida, y devuelve los que no ha
# podido guardar: un objeto con fichero (su ruta), clave (la normal, con los dias $Dias), destino (la clave de donde iria, o '' si no cabe) y motivo.
# Un fichero que no se guarda no para nada: se apunta, se dice en la consola ($Donde: de que caso y lado) y sigue con el siguiente. La primera
# vez que no cabe uno, la consola sugiere una carpeta mas corta.
function Copy-Salida([string]$De, [string]$A, [string]$Job, [string]$Donde, $Dias) {
  $no = @()
  if (-not (Test-Path -LiteralPath $De)) { return $no }
  foreach ($f in @(Get-ChildItem -LiteralPath $De -Recurse -File)) {
    $rel = Get-Rel $De $f.FullName
    $destino = Get-RelSalida $Job $rel $Dias
    $motivo = ''
    if ($null -eq $destino) {
      $motivo = 'ruta de ' + (Get-LargoRuta $Job (Get-NombreCorto $rel $Dias $true)) + ' letras'
      if (-not $script:AvisoCarpetaCorta) {
        $script:AvisoCarpetaCorta = $true
        Aviso "Hay ficheros que no caben en una ruta de $LimiteRuta letras ni con nombre corto. Mueve el proyecto a una carpeta mas corta (o usa un -Migrado con una ruta menos profunda) y repite."
      }
    }
    else {
      try { Copy-Fichero $f.FullName (Join-Ruta $A $destino) }
      catch { $motivo = ($_.Exception.Message -replace '\s+', ' ').Trim() }
    }
    if (-not $motivo) { continue }
    Aviso "${Donde}: ${rel}: no se ha podido guardar: $motivo"
    $d = ''
    if ($null -ne $destino) { $d = Get-Normal $destino $Dias }
    $no += [pscustomobject]@{ fichero = $rel; clave = (Get-Normal $rel $Dias); destino = $d; motivo = $motivo }
  }
  return $no
}

# Es $Rel (la ruta de un fichero de la salida de un caso) de los que no se comparan ($Cfg.CompararIgnorar: patrones como -like sobre el nombre del fichero)?
function Test-Ignorado([string]$Rel) {
  $nombre = $Rel.Substring($Rel.LastIndexOf('/') + 1)
  return (@($Cfg.CompararIgnorar | Where-Object { $_ -and $nombre -like $_ }).Count -gt 0)
}

# Lo que no se pudo guardar de un lado de un caso en este lanzamiento (lo de Copy-Salida), o nada. Un fichero que no se compara (Test-Ignorado) no cuenta.
function Get-NoGuardados([string]$Nombre, [string]$Job, [string]$Caso) {
  $k = "$Nombre|$Job|$Caso"
  if ($script:NoGuardados.ContainsKey($k)) { return @($script:NoGuardados[$k] | Where-Object { -not (Test-Ignorado $_.fichero) }) }
  return @()
}

# ================================ MAVEN ================================
# Maven en una copia (en la del original, con JAVA_HOME = -JavaLegacy, si se ha dado, y con UTF-8: $OpcionJvmOriginal), con latido, con tope (MinutosMaven) y sin
# saltarse los tests aunque el pom lo pida. Lo que Maven deja fuera de target (un log, una base en fichero) se borra al acabar
# (Remove-Ruido, de comun.ps1): no es de la IA y la siguiente ejecucion empieza igual. Deja lo que dice en registros\mvn-<n>-<que>.log y devuelve
# Codigo, Salida, Tope (Invoke-MavenTope, de comun.ps1), Causa (Get-CausaMaven, tambien con Codigo 0: un caso cuyo job falla o no arranca acaba con
# Maven en 0 y su causa esta en la salida de Maven) y Registro (la ruta de ese registro relativa a prueba-local: registros\mvn-<n>-<que>.log).
function Invoke-Maven([string]$Dir, [bool]$EsOriginal, [string[]]$A, [string]$Que) {
  $script:Mavens++
  $previos = @(Get-Cambios $Dir)
  $antes = $env:JAVA_HOME
  $antesJvm = $env:JAVA_TOOL_OPTIONS
  $desde = [DateTime]::UtcNow
  if ($EsOriginal -and $JavaLegacy) { $env:JAVA_HOME = $JavaLegacy }
  if ($EsOriginal) { $env:JAVA_TOOL_OPTIONS = ("$antesJvm $OpcionJvmOriginal").Trim() }
  $registro = 'mvn-' + $script:Mavens + '-' + ($Que -replace '[^\w\-]', '-') + '.log'
  try { $r = Invoke-MavenTope $Dir (@('-B', '-DskipTests=false', '-Dmaven.test.skip=false') + $A) "Maven, $Que" (Join-Path $Registros $registro) }
  finally { $env:JAVA_HOME = $antes; $env:JAVA_TOOL_OPTIONS = $antesJvm }
  Add-Member -InputObject $r -NotePropertyName Causa -NotePropertyValue (Get-CausaMaven $Dir $desde $r.Salida)
  Add-Member -InputObject $r -NotePropertyName Registro -NotePropertyValue ('registros\' + $registro)
  [void](Remove-Ruido $Dir $previos)
  return $r
}

# La causa de un Maven que ha fallado, recortada a 300 caracteres ('' si no hay): el ultimo 'Caused by:' de los informes de surefire de la
# copia $Dir escritos desde $Desde (los de antes pueden ser de otro caso), en el primero que tenga <<< ERROR! o <<< FAILURE!; si no hay, el
# ultimo 'Caused by:' de $Salida (la de Maven: surefire recorta la traza del informe y Spring la escribe entera en la salida); y si
# tampoco, la primera linea con texto tras la marca del informe; y si tampoco, la primera linea de $Salida con una excepcion
# (<paquete>.<Clase>Exception o ...Error), desde la clase, o con la marca 'cancelling refresh attempt: ' (lo que va despues); y si tampoco, el mensaje de la
# primera linea '[ERROR] Failed to execute goal ... on project <p>: <mensaje> -> [Help 1]' de Maven (sin el -> [Help 1]). Un informe que no se puede leer
# cuenta como si no estuviera.
# Una linea de la salida solo da la causa si no es de aviso (Test-SinNivelDeAviso, sobre lo que hay antes de la causa): Spring escribe como WARN las
# excepciones que ve al mirar las condiciones de una libreria y sigue, y la causa de verdad esta en una linea ERROR (o sin nivel) mas abajo. La unica
# linea WARN que si da causa es la de Spring que dice que el contexto no arranca ('Exception encountered during context initialization - cancelling
# refresh attempt: <excepcion>'): es la causa de verdad, y a veces la unica que escribe.
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
  if (-not $causa) {
    foreach ($x in @($Salida)) {
      if ($x -match 'Caused by:.*$' -and (Test-SinNivelDeAviso $x.Substring(0, $x.Length - $Matches[0].Length))) { $causa = $Matches[0] }
    }
  }
  if (-not $causa) { $causa = $primera }
  if (-not $causa) {
    $marcaContexto = 'cancelling refresh attempt: '
    foreach ($x in @($Salida)) {
      $dondeMarca = ([string]$x).IndexOf($marcaContexto, [StringComparison]::Ordinal)
      if ($dondeMarca -ge 0) { $causa = ([string]$x).Substring($dondeMarca + $marcaContexto.Length); break }
      $m = [regex]::Match([string]$x, '\b(?:[A-Za-z_$][\w$]*\.)+[A-Za-z_$][\w$]*(?:Exception|Error)\b')
      if ($m.Success -and (Test-SinNivelDeAviso ([string]$x).Substring(0, $m.Index))) { $causa = ([string]$x).Substring($m.Index); break }
    }
  }
  if (-not $causa.Trim()) {
    foreach ($x in @($Salida)) {
      $m = [regex]::Match([string]$x, '\[ERROR\]\s+Failed to execute goal\b.*?\bon project \S+?:\s+(.+?)(?:\s+->\s+\[Help \d+\])?\s*$')
      if ($m.Success) { $causa = $m.Groups[1].Value; break }
    }
  }
  $causa = $causa.Trim()
  if ($causa.Length -gt 300) { $causa = $causa.Substring(0, 300) }
  return $causa
}

# $true si el texto $Antes (lo que hay en una linea de log antes de la causa) no lleva un nivel de aviso: el primer nivel que sale (TRACE, DEBUG, INFO,
# WARN, WARNING, ERROR, FATAL o SEVERE, en mayusculas y entero, sin letra, cifra, _, . ni $ pegados; sirve para '[WARN ]', '  WARN 2192 ---' y
# '"logLevel":"WARN"') no es TRACE, DEBUG, INFO, WARN ni WARNING. Sin nivel, vale.
function Test-SinNivelDeAviso([string]$Antes) {
  $n = [regex]::Match($Antes, '(?<![\w.$])(?:TRACE|DEBUG|INFO|WARNING|WARN|ERROR|FATAL|SEVERE)(?![\w.$])')
  return (-not $n.Success -or $n.Value -cmatch '^(?:ERROR|FATAL|SEVERE)$')
}

# La causa de Get-CausaMaven sin el 'Caused by: ' del principio (lo que se ensena y se guarda en el resultado: 'java.lang.X: mensaje').
function Get-CausaCorta([string]$Causa) { return ($Causa -replace '^\s*Caused by:\s*', '').Trim() }

# Lo que sirve para entender un fallo de Maven (lo que da Invoke-Maven): pasado el tope, el mensaje; si no, las primeras
# lineas [ERROR] o, si no hay, las ultimas, y, si hay, la causa de verdad, de su informe de surefire o de la salida (Get-CausaMaven).
function Get-FalloMaven($Maven) {
  if ($Maven.Tope) { return $Maven.Tope }
  $e = @($Maven.Salida | Where-Object { $_ -match '^\[ERROR\]' } | Select-Object -First ([int]$Cfg.LineasError))
  if ($e.Count -eq 0) { $e = @($Maven.Salida | Select-Object -Last ([int]$Cfg.LineasError)) }
  if ($Maven.Causa) { $e += "Causa: $($Maven.Causa)" }
  return ($e -join "`n")
}

# Los segundos del test de un caso: el time del testsuite del TEST-*PruebaLocalTest.xml de surefire de $Dir escrito desde $Desde (el de
# antes es de otro Maven), o $null si no hay o no se lee.
function Get-SegundosTest([string]$Dir, [DateTime]$Desde) {
  try {
    $f = @(Get-ChildItem -LiteralPath (Join-Ruta $Dir 'target/surefire-reports') -Filter 'TEST-*PruebaLocalTest.xml' -File | Where-Object { $_.LastWriteTimeUtc -ge $Desde } | Sort-Object LastWriteTimeUtc)
    if ($f.Count -eq 0) { return $null }
    $xml = New-Object System.Xml.XmlDocument
    $xml.Load($f[-1].FullName)
    return [double]::Parse($xml.DocumentElement.GetAttribute('time'), $Inv)
  }
  catch { return $null }
}

# Un Maven de un caso de un job (con -o si $SinRed), cronometrado: apunta en $script:Tiempos una fila con los segundos de Maven y los de su test.
# $Modo: 'ciclo' (mvn test: el ciclo entero hasta el test), 'directo' (mvn surefire:test: solo el test, sobre lo compilado por Invoke-Compilar; con -DargLine= si la copia lo
# necesita, ver Invoke-Job) o 'compilar' (el mvn test-compile de la copia que necesita el modo directo: su fila lleva caso '(compilar)', sin job ni segundosTest, y no entra en
# la media por caso, Show-Tiempos). Cada fila lleva su modo: directo (tambien la de compilar) o ciclo.
function Invoke-MavenCaso([string]$Dir, [bool]$EsOriginal, [string]$Job, [string]$Caso, [bool]$SinRed, [string]$Que, [string]$Modo = 'ciclo') {
  $rapido = @($Cfg.MavenCasoRapido | Where-Object { $_ })
  if ($Modo -eq 'compilar') { $Job = ''; $Caso = '(compilar)'; $a = @('test-compile') + $rapido }
  else {
    $a = @('test', '-Dtest=PruebaLocalTest', "-Dprueba.local.job=$Job", "-Dprueba.local.caso=$Caso") + $rapido
    if ($Modo -eq 'directo') {
      $a[0] = 'surefire:test'
      if ($script:ArgLineVacio.ContainsKey($Dir)) { $a += '-DargLine=' }
    }
  }
  if ($SinRed) { $a += '-o' }
  $lado = 'migrado'
  if ($EsOriginal) { $lado = 'original' }
  $modoFila = 'directo'
  if ($Modo -eq 'ciclo') { $modoFila = 'ciclo' }
  $desde = [DateTime]::UtcNow
  $cron = [System.Diagnostics.Stopwatch]::StartNew()
  $r = Invoke-Maven $Dir $EsOriginal $a $Que
  $segundos = [Math]::Round($cron.Elapsed.TotalSeconds, 1)
  $segundosTest = $null
  if ($Modo -ne 'compilar') {
    $segundosTest = Get-SegundosTest $Dir $desde
    # Informe: surefire escribio el informe de PruebaLocalTest desde que empezo este Maven, es decir, el test llego a ejecutarse (Invoke-Job lo usa en el modo directo).
    Add-Member -InputObject $r -NotePropertyName Informe -NotePropertyValue ($null -ne $segundosTest) -Force
  }
  $script:Tiempos += [pscustomobject][ordered]@{ lado = $lado; job = $Job; caso = $Caso; modo = $modoFila; segundosMaven = $segundos; segundosTest = $segundosTest; offline = $SinRed; cuando = (Get-Date).ToString('s') }
  return $r
}

# La huella del estado de $Dir que decide si lo compilado vale (Invoke-Compilar): la ruta, el tamano y la fecha de modificacion (LastWriteTimeUtc) de todo lo que hay en src\ salvo la
# carpeta de los casos ($Casos: el caso lee sus entradas por el sistema de ficheros, no del classpath, y Edit-DatosSql o un caso nuevo no cambian lo compilado) y del pom.xml, en un
# hash. Un test que se instala otra vez cambia la huella aunque su fecha sea mas vieja (otro fichero con la misma ruta y otra fecha o tamano).
function Get-HuellaCopia([string]$Dir) {
  $ficheros = New-Object System.Collections.Generic.List[System.IO.FileInfo]
  $pom = Join-Path $Dir 'pom.xml'
  if (Test-Path -LiteralPath $pom -PathType Leaf) { $ficheros.Add((New-Object System.IO.FileInfo $pom)) }
  $pila = New-Object System.Collections.Generic.Stack[System.IO.DirectoryInfo]
  $src = Join-Path $Dir 'src'
  if (Test-Path -LiteralPath $src) { $pila.Push((New-Object System.IO.DirectoryInfo $src)) }
  while ($pila.Count -gt 0) {
    $d = $pila.Pop()
    foreach ($sub in $d.GetDirectories()) { if ((Get-Rel $Dir $sub.FullName) -cne $Casos) { $pila.Push($sub) } }
    $ficheros.AddRange($d.GetFiles())
  }
  $l = @($ficheros | ForEach-Object { (Get-Rel $Dir $_.FullName) + '|' + $_.Length + '|' + $_.LastWriteTimeUtc.Ticks })
  return (Get-Hash256 ($Utf8.GetBytes((Sort-Ordinal $l) -join "`n")))
}

# Compila la copia $Dir (mvn test-compile, con las propiedades de MavenCasoRapido y -o como los casos) si lo compilado no es su estado de ahora: $script:Compilada guarda, por copia,
# la huella (Get-HuellaCopia) con la que se compilo por ultima vez, y no depende del orden del flujo (un test que el arnes o -Reparar escriben, -Desde en otro commit...): lo que
# cambie en src\ o en el pom.xml se compila otra vez antes del siguiente caso. Si sin red Maven no compila y su salida dice que es por la red (Test-FalloSinRed), otra vez con red y
# esa copia sigue con red (como en Invoke-Job). Devuelve $null si la copia queda compilada, o el Maven que ha fallado (un error de compilacion, el tope): el caso sale como saldria con
# mvn test, y la copia no queda como compilada.
# Solo cuando compila de verdad, y justo antes del test-compile, borra target\classes, target\test-classes y target\maven-status de la copia (nada mas de target: ni
# target\prueba-local ni los informes de surefire): Copy-Fichero conserva la fecha de un fichero (Copy-Item en Windows), asi que un test guardado con fecha vieja que se copia
# encima de otro ya compilado cambia la huella, pero el maven-compiler-plugin solo recompila una fuente mas nueva que su .class y dejaria la clase de antes: se ejecutaria un
# test que no es el que hay en src\ sin que nadie lo viera. Sin las clases ni el estado del compilador, Maven lo compila todo.
function Invoke-Compilar([string]$Dir, [bool]$EsOriginal, [string]$Que) {
  $huella = Get-HuellaCopia $Dir
  if ($script:Compilada[$Dir] -ceq $huella) { return $null }
  foreach ($c in @('target/classes', 'target/test-classes', 'target/maven-status')) { Remove-Carpeta (Join-Ruta $Dir $c) }
  $sinRed = -not $script:ConRed.ContainsKey($Dir)
  $r = Invoke-MavenCaso $Dir $EsOriginal '' '' $sinRed $Que 'compilar'
  if ($sinRed -and $r.Codigo -ne 0 -and -not $r.Tope -and (Test-FalloSinRed $r)) {
    Info 'Sin red Maven no ha podido compilar: repito con red y sigo con red en esta copia.'
    $r = Invoke-MavenCaso $Dir $EsOriginal '' '' $false $Que 'compilar'
    if ($r.Codigo -eq 0) { $script:ConRed[$Dir] = $true }
  }
  if ($r.Codigo -ne 0 -or $r.Tope) {
    $script:Compilada.Remove($Dir)
    return $r
  }
  $script:Compilada[$Dir] = $huella
  return $null
}

# Ha llegado Maven a ejecutar el test del caso? Si, si ha dejado su estado.txt (aunque el job acabe FAILED) o su error.txt.
function Test-CasoEjecutado([string]$Sal) { return ((Test-Path -LiteralPath (Join-Path $Sal 'estado.txt')) -or (Test-Path -LiteralPath (Join-Path $Sal 'error.txt'))) }

# Ha llegado el surefire:test del caso a ejecutar el test? Si Maven se paro por el tope (colgado: no se repite), si surefire escribio el informe de PruebaLocalTest desde que empezo
# ese Maven ($R.Informe, Invoke-MavenCaso) o si el caso dejo su estado.txt o su error.txt. Sin ninguna de las tres cosas el test no corrio (la JVM no arranco, no hay nada que ejecutar).
function Test-DirectoEjecutado($R, [string]$Sal) { return [bool]($R.Tope -or $R.Informe -or (Test-CasoEjecutado $Sal)) }

# Dice la salida de Maven que ha fallado por estar sin red (-o)? Lo dice con 'Cannot access <repo> in offline mode and the artifact ... has not
# been downloaded from it before' o con 'The repository system is offline but the artifact ... is not available'. Sin esa palabra el fallo es
# otro (por ejemplo, el contexto de Spring no arranca: el arnes solo deja error.txt si el caso no se puede preparar) y repetir con red no lo arregla.
function Test-FalloSinRed($Maven) { return (@($Maven.Salida | Where-Object { $_ -match '(?i)\boffline\b' }).Count -gt 0) }

# Un caso en $Modo (Invoke-MavenCaso) con -o si la copia sigue sin red. Si sin red Maven no llega a ejecutar el test y su salida dice que es por la red (Test-FalloSinRed), se repite
# una vez con red y, si asi si llega, esa copia sigue con red el resto del lanzamiento. Un caso que ya dejo estado.txt o error.txt no se repite; tampoco uno parado por el tope de
# Maven (colgado, no por la red).
function Invoke-CasoConRed([string]$Dir, [bool]$EsOriginal, [string]$Job, [string]$Caso, [string]$Que, [string]$Modo) {
  $sal = Join-Ruta $Dir "target/prueba-local/$Job/$Caso"
  $sinRed = -not $script:ConRed.ContainsKey($Dir)
  $r = Invoke-MavenCaso $Dir $EsOriginal $Job $Caso $sinRed $Que $Modo
  if ($sinRed -and -not $r.Tope -and -not (Test-CasoEjecutado $sal) -and (Test-FalloSinRed $r)) {
    Info 'Sin red Maven no ha podido: repito el caso con red y sigo con red en esta copia.'
    Remove-Carpeta $sal
    $r = Invoke-MavenCaso $Dir $EsOriginal $Job $Caso $false $Que $Modo
    if (Test-CasoEjecutado $sal) { $script:ConRed[$Dir] = $true }
  }
  return $r
}

# Ejecuta en una copia un caso de un job (con su salida anterior borrada), en su propio Maven: cada caso en una JVM
# nueva, como cada ejecucion en produccion. En la misma JVM, lo que el batch deja en campos static (un fichero abierto,
# un contador) pasaria de un caso al siguiente. Va sin red (-o: no mira los repositorios remotos) y sin los plugins de
# $Cfg.MavenCasoRapido (Invoke-CasoConRed).
# Con $Cfg.MavenCasoDirecto (por defecto), el caso va con mvn surefire:test, sin el ciclo de Maven, sobre lo que Invoke-Compilar ha dejado compilado en la copia. Si el caso no
# llega a ejecutarse (Test-DirectoEjecutado: ni informe de surefire de PruebaLocalTest, ni estado.txt, ni error.txt, ni tope de Maven, ni fallo por la red): si la salida de Maven
# lleva @{argLine} (surefire lo deja sin sustituir cuando la propiedad argLine no existe, como con JaCoCo sin prepare-agent, y la JVM no arranca: no hay informe), una vez mas con
# -DargLine= (la propiedad no existia: no se pierde nada) y la copia sigue con -DargLine= ($script:ArgLineVacio); si sigue sin ejecutarse, ese caso va con mvn test como siempre y
# esa copia sigue con mvn test el resto del lanzamiento ($script:ConCiclo), con una Info una sola vez. Si hay informe, el test se ejecuto (un contexto de Spring del migrado que no
# arranca deja el informe y ni estado.txt ni error.txt): el resultado vale tal cual, con mvn test saldria lo mismo, y la copia sigue en directo. Un test-compile que falla
# (Invoke-Compilar) es el resultado del caso: mvn test fallaria igual.
# Mientras Maven ejecuta el caso, su datos.sql lleva IF NOT EXISTS en cada CREATE y ADD que lo acepta (Edit-DatosSql); al acabar queda como estaba.
function Invoke-Job([string]$Dir, [bool]$EsOriginal, [string]$Job, [string]$Caso, [string]$Que) {
  $sal = Join-Ruta $Dir "target/prueba-local/$Job/$Caso"
  Remove-Carpeta $sal
  $sql = Join-Ruta $Dir "$Casos/$Job/$Caso/datos.sql"
  $bytes = Edit-DatosSql $sql
  try {
    $r = $null
    if ([bool]$Cfg.MavenCasoDirecto -and -not $script:ConCiclo.ContainsKey($Dir)) {
      $r = Invoke-Compilar $Dir $EsOriginal 'compilar para los casos'
      if ($null -eq $r) {
        $r = Invoke-CasoConRed $Dir $EsOriginal $Job $Caso $Que 'directo'
        if (-not (Test-DirectoEjecutado $r $sal) -and -not $script:ArgLineVacio.ContainsKey($Dir) -and @($r.Salida | Where-Object { ([string]$_).Contains('@{argLine}') }).Count -gt 0) {
          $script:ArgLineVacio[$Dir] = $true
          Remove-Carpeta $sal
          $r = Invoke-CasoConRed $Dir $EsOriginal $Job $Caso $Que 'directo'
        }
        if (-not (Test-DirectoEjecutado $r $sal)) {
          $script:ConCiclo[$Dir] = $true
          $linea = [string](@((Get-FalloMaven $r) -split "`n") | Where-Object { $_.Trim() } | Select-Object -First 1)
          if (-not $linea) { $linea = 'sin mensaje de Maven' }
          if ($linea.Length -gt 200) { $linea = $linea.Substring(0, 200) }
          Info "En $(Split-Path $Dir -Leaf) no puedo ejecutar los casos sin el ciclo de Maven ($linea): sigo con mvn test, mas lento."
          Remove-Carpeta $sal
          $r = $null
        }
      }
    }
    if ($null -eq $r) { $r = Invoke-CasoConRed $Dir $EsOriginal $Job $Caso $Que 'ciclo' }
  }
  finally { if ($null -ne $bytes) { [System.IO.File]::WriteAllBytes($sql, $bytes) } }
  return $r
}

# Pone IF NOT EXISTS al datos.sql $Ruta en cada CREATE y cada ALTER TABLE ... ADD que lo lleva en las tres gramaticas de H2 (1.4.193, 1.4.200 y 2.x; help.csv de cada
# etiqueta de h2database/h2database, h2database.com/html/commands.html): CREATE [CACHED | MEMORY] [TEMP | [GLOBAL | LOCAL] TEMPORARY] TABLE, CREATE [FORCE] [[GLOBAL | LOCAL]
# TEMPORARY] LINKED TABLE, SEQUENCE, [UNIQUE | HASH | SPATIAL] INDEX <nombre>, SCHEMA <nombre>, [FORCE] VIEW, ROLE, USER, CONSTANT, DOMAIN, ALIAS, AGGREGATE, TRIGGER, y
# ALTER TABLE <tabla> ADD [COLUMN] <columna> y ADD CONSTRAINT <nombre>. No lo lleva (se deja como esta): CREATE OR REPLACE VIEW (con los dos, H2 deja la vista de antes y no la
# reemplaza), un indice sin nombre, CREATE PRIMARY KEY, CREATE SCHEMA AUTHORIZATION sin nombre y CREATE MATERIALIZED VIEW (solo 2.x), ADD PRIMARY KEY / UNIQUE / FOREIGN KEY /
# CHECK sin CONSTRAINT <nombre> y ADD ( lista de columnas ) (sin nombre o sin IF NOT EXISTS en la gramatica). El test del arnes ya crea cosas en su base (la del calendario en el
# original; las de Spring Batch en el migrado, que las crea solo) y un datos.sql que las crea otra vez da 'ya existe': el caso no se pudo preparar o sale distinto sin que el
# batch tenga la culpa. Lo que va en un comentario (-- o /* */), en un texto ('...' o $$...$$) o entre comillas dobles no se toca (Get-MascaraSql). Lo que ya lleva IF NOT EXISTS,
# tampoco. Devuelve los bytes de antes, para dejar el fichero como estaba al acabar el caso (lo guardado en casos\ no cambia), o $null si no hay fichero o no cambia nada. Se lee
# y se escribe en Latin-1, byte a byte: lo demas del fichero no cambia, sea cual sea su codificacion.
function Edit-DatosSql([string]$Ruta) {
  if (-not (Test-Path -LiteralPath $Ruta -PathType Leaf)) { return $null }
  $bytes = [System.IO.File]::ReadAllBytes($Ruta)
  $texto = $Latin.GetString($bytes)
  $mascara = Get-MascaraSql $texto
  $ya = '(?!IF\s+NOT\s+EXISTS\b)'
  $alter = 'ALTER\s+TABLE\s+(?:IF\s+EXISTS\s+)?[^\s;(]+\s+ADD'
  $patrones = @(
    ('\bCREATE\s+(?:(?:CACHED|MEMORY)\s+)?(?:(?:TEMP|TEMPORARY|(?:GLOBAL|LOCAL)\s+TEMPORARY)\s+)?TABLE(?>\s+)(?<p>)' + $ya),
    ('\bCREATE\s+(?:FORCE\s+)?(?:(?:GLOBAL|LOCAL)\s+)?(?:TEMPORARY\s+)?LINKED\s+TABLE(?>\s+)(?<p>)' + $ya),
    ('\bCREATE\s+(?:(?:UNIQUE|HASH|SPATIAL|NULLS\s+(?:ALL\s+|NOT\s+)?DISTINCT)\s+)*INDEX(?>\s+)(?<p>)' + $ya + '(?!ON\b)'),
    ('\bCREATE\s+(?:SEQUENCE|SCHEMA|ROLE|USER|CONSTANT|DOMAIN|ALIAS|AGGREGATE|TRIGGER)(?>\s+)(?<p>)' + $ya + '(?!AUTHORIZATION\b)'),
    ('\bCREATE\s+(?:FORCE\s+)?VIEW(?>\s+)(?<p>)' + $ya),
    ('\b' + $alter + '(?>\s+)(?:(?>COLUMN\s+)|(?!COLUMN\b))(?<p>)' + $ya + '(?!CONSTRAINT\b|PRIMARY\b|UNIQUE\b|FOREIGN\b|CHECK\b|\()'),
    ('\b' + $alter + '\s+CONSTRAINT(?>\s+)(?<p>)' + $ya)
  )
  $puestos = New-Object System.Collections.Generic.SortedSet[int]
  foreach ($p in $patrones) { foreach ($m in [regex]::Matches($mascara, $p, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) { [void]$puestos.Add($m.Groups['p'].Index) } }
  if ($puestos.Count -eq 0) { return $null }
  $nuevo = $texto
  foreach ($i in @($puestos | Sort-Object -Descending)) { $nuevo = $nuevo.Insert($i, 'IF NOT EXISTS ') }
  [System.IO.File]::WriteAllBytes($Ruta, $Latin.GetBytes($nuevo))
  return , $bytes
}

# $Texto con lo que no es SQL por dentro tapado, del mismo largo (para buscar sentencias sin leer un comentario o un texto como si fuera una): un comentario (-- hasta el final de la
# linea, /* */) pasa a espacios; un texto ('...' con '' dentro, $$...$$) o un nombre entre comillas dobles conserva sus delimitadores y lleva x por dentro.
function Get-MascaraSql([string]$Texto) {
  $tapa = [System.Text.RegularExpressions.MatchEvaluator] {
    param($m)
    $v = $m.Value
    if ($v.StartsWith('--') -or $v.StartsWith('/*')) { return (' ' * $v.Length) }
    $d = 1
    if ($v.StartsWith('$$')) { $d = 2 }
    return ($v.Substring(0, $d) + ('x' * ($v.Length - 2 * $d)) + $v.Substring($v.Length - $d))
  }
  return [regex]::Replace($Texto, '--[^\r\n]*|/\*.*?\*/|''(?:[^'']|'''')*''|"(?:[^"]|"")*"|\$\$.*?\$\$', $tapa, [System.Text.RegularExpressions.RegexOptions]::Singleline)
}

# Anade las filas de este lanzamiento a datos\prueba-local-tiempos.json (se anade, no se pisa). Un fallo al guardar no para la prueba.
function Save-Tiempos {
  if ($script:Tiempos.Count -eq 0) { return }
  $ruta = Join-Path $DatosMig 'prueba-local-tiempos.json'
  try {
    $antes = @()
    if (Test-Path -LiteralPath $ruta) { $antes = @(Read-Json $ruta) }
    Write-Json $ruta (@($antes) + @($script:Tiempos))
  }
  catch { Aviso "No he podido guardar los tiempos en ${ruta}: $($_.Exception.Message)" }
}

# De las ejecuciones de este lanzamiento que tienen segundosTest: lo que tarda Maven por caso y cuanto de eso es el test.
# La compilacion de las copias (modo directo, caso '(compilar)') no entra en la media por caso: va aparte, 'Compilar: <veces>, <segundos>'.
function Show-Tiempos {
  $f = @($script:Tiempos | Where-Object { $_.caso -ne '(compilar)' -and $null -ne $_.segundosTest })
  if ($f.Count -eq 0) { return }
  $maven = ($f | Measure-Object -Property segundosMaven -Average).Average
  $test = ($f | Measure-Object -Property segundosTest -Average).Average
  $compilar = ''
  $c = @($script:Tiempos | Where-Object { $_.caso -eq '(compilar)' })
  if ($c.Count -gt 0) {
    $veces = 'veces'
    if ($c.Count -eq 1) { $veces = 'vez' }
    $compilar = " Compilar: $($c.Count) $veces, $([Math]::Round(($c | Measure-Object -Property segundosMaven -Sum).Sum, 1)) s."
  }
  Info ("Maven por caso: $([Math]::Round($maven, 1)) s de media; el test $([Math]::Round($test, 1)) s y Maven $([Math]::Round($maven - $test, 1)) s (arranque, plugins y red).$compilar Detalle: " + (Join-Path $DatosMig 'prueba-local-tiempos.json'))
}

# Por que un caso no ha dejado estado.txt en $Sal: su error.txt o, si no hay, el error de Maven.
function Get-Porque([string]$Sal, $Maven) {
  $err = Join-Path $Sal 'error.txt'
  if (Test-Path -LiteralPath $err) { return ('error.txt: ' + (@([System.IO.File]::ReadAllLines($err) | Select-Object -First ([int]$Cfg.LineasError)) -join "`n")) }
  if ($null -eq $Maven) { return 'no ha dejado estado.txt.' }
  return ("no ha dejado estado.txt. Maven dice:`n" + (Get-FalloMaven $Maven))
}

# '' si el job arranco en $Sal; si su estado.txt dice estado=EXCEPCION (lanzarlo lanzo una excepcion antes de tener ejecucion), la clase de la
# excepcion (la linea salida=) o 'una excepcion' si no la dice.
function Get-Excepcion([string]$Sal) {
  $ruta = Join-Path $Sal 'estado.txt'
  if (-not (Test-Path -LiteralPath $ruta)) { return '' }
  $l = @([System.IO.File]::ReadAllLines($ruta) | ForEach-Object { $_.Trim() })
  if ($l -cnotcontains 'estado=EXCEPCION') { return '' }
  $clase = ((@($l | Where-Object { $_ -cmatch '^salida=' } | Select-Object -First 1) -join '') -replace '^salida=', '')
  if ($clase) { return $clase }
  return 'una excepcion'
}

# $true si $Clase (la de Get-Excepcion, o una con su paquete) es una de $ExcepcionesArranque: lanzar el job no pudo ni montar el contexto de Spring.
function Test-ExcepcionArranque([string]$Clase) {
  return ($ExcepcionesArranque -ccontains (($Clase -split '\.')[-1]))
}

# El error del codigo (una fila de $ErroresCodigo: regla y frase) que dicen la clase $Clase (la de Get-Excepcion) o la causa $Causa de un job que no arranca, o $null si no
# es ninguno: entonces puede ser el test.
function Get-ErrorCodigo([string]$Clase, [string]$Causa) {
  foreach ($e in $ErroresCodigo) { if ("$Clase $Causa" -cmatch $e.patron) { return $e } }
  return $null
}

# Lo que dice de un error del codigo $E (Get-ErrorCodigo): 'Es el codigo del migrado, no el test: <frase> (regla <regla> del paso de calidad).'
function Format-ErrorCodigo($E) { return "Es el codigo del migrado, no el test: $($E.frase) (regla $($E.regla) del paso de calidad)." }

# El estado (la linea estado=) del estado.txt de $Sal, o '' si no hay fichero o no lo dice.
function Get-Estado([string]$Sal) {
  $ruta = Join-Path $Sal 'estado.txt'
  if (-not (Test-Path -LiteralPath $ruta)) { return '' }
  $l = @([System.IO.File]::ReadAllLines($ruta) | ForEach-Object { $_.Trim() } | Where-Object { $_ -cmatch '^estado=' } | Select-Object -First 1)
  return (($l -join '') -replace '^estado=', '')
}

# La causa (corta) de un lado de un caso ($Lado: 'original' o el nombre de salidas del migrado): la de su Maven de este lanzamiento y, si el original
# no se ha ejecutado ahora (se reutiliza, Invoke-Originales), la que se guardo con el en originales.json. '' si no la hay.
function Get-CausaLado([string]$Lado, [string]$Job, [string]$Caso) {
  $m = $script:Maven["$Lado|$Job|$Caso"]
  if ($m) { return (Get-CausaCorta $m.Causa) }
  if ($Lado -ceq 'original') {
    $g = (Get-Originales)["$Job|$Caso"]
    if ($g -and $null -ne $g.PSObject.Properties['causa']) { return [string]$g.causa }
  }
  return ''
}

# Los lados de un caso que acaban mal (original y $Nombre, el migrado): uno por cada Get-FalloLado. Es lo que lleva el resultado de un caso en 'fallos', fuera de las
# carpetas que se comparan.
function Get-Fallos([string]$Nombre, [string]$Job, [string]$Caso) {
  $fallos = @()
  foreach ($lado in @('original', $Nombre)) {
    $f = Get-FalloLado $lado $Job $Caso
    if ($f) { $fallos += $f }
  }
  return $fallos
}

# Como acaba mal el lado $Lado (original o el nombre de salidas del migrado) de un caso, o $null si acaba bien: estado=FAILED, estado=EXCEPCION o sin estado.txt, con su
# causa (la del Maven de esa ejecucion, Get-CausaLado; sin estado.txt, sin causa y con Maven en 0, $MotivoMavenSinSalida), su registro (el mvn-*.log de esa ejecucion,
# relativo a prueba-local, haya causa o no; '' si el lado no se ha ejecutado ahora: un original reutilizado) y, con EXCEPCION, su clase (Get-Excepcion).
function Get-FalloLado([string]$Lado, [string]$Job, [string]$Caso) {
  $sal = Join-Ruta $Local "salidas/$Lado/$Job/$Caso"
  $estado = 'sin estado.txt'
  if (Test-Path -LiteralPath (Join-Path $sal 'estado.txt')) {
    $estado = Get-Estado $sal
    if ($estado -cne 'FAILED' -and $estado -cne 'EXCEPCION') { return $null }
  }
  $nombreLado = 'migrado'
  if ($Lado -ceq 'original') { $nombreLado = 'original' }
  $registro = ''
  $mvn = $script:Maven["$Lado|$Job|$Caso"]
  if ($mvn) { $registro = [string]$mvn.Registro }
  $causa = Get-CausaLado $Lado $Job $Caso
  if (-not $causa -and $estado -ceq 'sin estado.txt' -and $mvn -and $mvn.Codigo -eq 0) { $causa = $MotivoMavenSinSalida }
  $f = [ordered]@{ lado = $nombreLado; estado = $estado; causa = $causa; registro = $registro }
  if ($estado -ceq 'EXCEPCION') { $f.clase = Get-Excepcion $sal }
  return $f
}

# La clase de excepcion de un fallo $F de Get-FalloLado: la suya (clase) o, en un prueba-local.json de antes, la que abre su causa ('org.x.NoSuchBeanDefinitionException: ...'
# da NoSuchBeanDefinitionException); '' si no la hay.
function Get-ClaseFallo($F) {
  if ($F.clase) { return [string]$F.clase }   # (un fallo de este lanzamiento es un diccionario y uno leido del json, un objeto: los dos dan $null si no la tienen)
  $m = [regex]::Match([string]$F.causa, '^(?:[\w$]+\.)*([\w$]+(?:Exception|Error))\b')
  return $m.Groups[1].Value
}

# $true si el fallo $F es el de un job que no arranca: EXCEPCION con una de las clases de $ExcepcionesArranque (Test-ExcepcionArranque).
function Test-FalloArranque($F) { return ($F.estado -ceq 'EXCEPCION' -and (Test-ExcepcionArranque (Get-ClaseFallo $F))) }

# Lo que tienen en comun los casos de un job que fallan igual: el estado y la causa del fallo $F sin lo que cambia de un caso a otro (Get-CausaNormal, con el nombre del
# caso $Caso). '' si el fallo no es FAILED ni EXCEPCION o no dice su causa: sin causa no se sabe si dos fallos son el mismo.
function Get-FirmaFallo($F, [string]$Caso) {
  if (-not $F -or ($F.estado -cne 'FAILED' -and $F.estado -cne 'EXCEPCION') -or -not $F.causa) { return '' }
  return $F.estado + '|' + (Get-CausaNormal ([string]$F.causa) $Caso)
}

# El fallo del original de un caso que ya se ha ejecutado (o se reutiliza) si acaba FAILED o EXCEPCION con causa, o $null.
function Get-FalloOriginal([string]$Job, [string]$Caso) {
  $f = Get-FalloLado 'original' $Job $Caso
  if ($f -and (Get-FirmaFallo $f $Caso)) { return $f }
  return $null
}

# 'el migrado acaba FAILED: <causa>' (lo que ensenan la consola y el prompt de -Reparar de un fallo de Get-Fallos). Sin causa, con $ConRegistro (la
# consola; el prompt de -Reparar no lo lleva) y con registro, dice donde mirar: 'sin causa en la salida de Maven: mira registros\mvn-<n>-<que>.log'.
function Format-Fallo($F, [switch]$ConRegistro) {
  $que = "el $($F.lado) acaba $($F.estado)"
  if ($F.estado -ceq 'sin estado.txt') { $que = "el $($F.lado) no deja estado.txt" }
  if ($F.causa) { return "${que}: $($F.causa)" }
  if ($ConRegistro -and $F.registro) { return "${que}: sin causa en la salida de Maven: mira $($F.registro)" }
  return $que
}

# La causa de un fallo $F de Get-FalloLado como la dicen la consola y el veredicto de cada caso: 'clase: causa' si es una excepcion, la causa si no; '' si no dice nada.
function Format-DetalleFallo($F) {
  if ($F.clase -and $F.causa) { return "$($F.clase): $($F.causa)" }
  if ($F.clase) { return [string]$F.clase }
  return [string]$F.causa
}

# La linea de un caso del migrado en cuanto acaba su Maven (Invoke-Salidas), sin esperar a la comparacion de ficheros: como acaba el migrado (con el detalle de su fallo $Fallo,
# el de Get-FalloLado, o $null si acaba bien) y como acaba el original (su estado.txt, que ya esta: el original se ejecuta antes que el migrado o se reutiliza). Si los dos acaban
# igual y bien, lo dice y deja la comparacion para el final. Un original sin estado.txt no se ha probado.
function Format-VeredictoCaso([string]$Job, [string]$Caso, $Fallo) {
  $m = Get-Estado (Join-Ruta $Local "salidas/migrado/$Job/$Caso")
  if (-not $m) { $m = 'sin estado.txt' }
  $o = Get-Estado (Join-Ruta $Local "salidas/original/$Job/$Caso")
  if (-not $o) { $o = 'sin probar (no ha dejado estado.txt)' }
  if (-not $Fallo -and $m -ceq $o) { return "${Caso}: los dos acaban $m (la comparacion de ficheros, al final)" }
  $detalle = ''
  if ($Fallo -and (Format-DetalleFallo $Fallo)) { $detalle = " ($(Format-DetalleFallo $Fallo))" }
  return "${Caso}: el migrado acaba $m$detalle; el original, $o"
}

# Lo que se le dice a la IA de un caso cuyo original no arranca ($Clase es lo de Get-Excepcion de $Sal): la primera linea de la causa (error.txt),
# si hay; si no, $Causa (la de Maven de esa ejecucion, Get-CausaCorta), si hay.
function Get-MotivoExcepcion([string]$Sal, [string]$Clase, [string]$Causa = '') {
  $detalle = ''   # (ojo: $detalle y no $causa: PowerShell no distingue $Causa de $causa)
  if (Test-Path -LiteralPath (Join-Path $Sal 'error.txt')) {
    $p = (((Get-Porque $Sal $null) -split "`n")[0]).TrimEnd()
    if ($p -cne 'error.txt:') { $detalle = " ($p)" }
  }
  if (-not $detalle -and $Causa) { $detalle = " ($Causa)" }
  return "En el original el job no llega a arrancar: lanzarlo da $Clase$detalle. Si el caso no busca justo eso, corrige las entradas (parametros, datos.sql...) para que el job arranque y haga lo que dice el titulo."
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
    elseif ($t.entradas.PSObject.Properties['previo']) { $motivo = [string]$t.entradas.previo }   # el primer intento de un test que se escribe otra vez: lo que fallo antes (Set-PrevioArnes)
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
    # Una linea 'error: option ...' de la ultima llamada es Copilot rechazando los argumentos que le pasa el script: el fallo es nuestro, no de su sesion, cuota o red
    $rechazo = @(@($ll[-1].Texto -split "`r?`n") | Where-Object { $_.Trim() -cmatch '^error: option' } | Select-Object -First 1)
    $consejo = 'Mira que Copilot funciona (sesion, cuota, red) y vuelve a lanzar el mismo comando: lo hecho se conserva.'
    if ($rechazo.Count -gt 0) { $consejo = 'Copilot rechaza los argumentos que le pasa el script (es un fallo del script, no de Copilot): ' + (Get-UltimaLinea $rechazo[0]) + "`nCuando se arregle, vuelve a lanzar el mismo comando: lo hecho se conserva." }
    Stop-Arranque ("Copilot no responde: $($script:Racha) llamadas seguidas han fallado. La ultima: " + (Get-UltimaLinea $ll[-1].Texto) + "`n" + $consejo)
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
# quedan intentos o si $SinReintento (un motivo que la IA no puede arreglar: otro intento gastaria una llamada sin arreglar nada).
function Set-Intento($T, [string]$Motivo, [bool]$SinReintento = $false) {
  $T.intentos++
  $T.motivo = $Motivo
  if (-not $Motivo) { $T.estado = 'hecha'; $T.ultimoEstado = 'ok' }
  else {
    $T.ultimoEstado = 'invalida'
    if ($SinReintento -or $T.intentos -ge [int]$Cfg.Intentos) { $T.estado = 'atascada' }
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

# Lo que preparan los tests de ejemplo $Ejemplos (rutas completas) de la copia $Dir antes de lanzar el job: un parrafo con 'fichero:linea (metodo)' de cada
# metodo con @BeforeEach, @BeforeAll, @Before o @BeforeClass (el fichero relativo a la copia; la linea, la del nombre del metodo; 5 como mucho, en el orden
# de los ejemplos y del fichero), o '' si no hay ninguno. Va detras de la lista de ejemplos del test del migrado (Get-TareaArnes): el test del original
# puede ser de una version del framework que no lo necesita y el del migrado, que lo traduce, se queda sin prepararlo.
function Get-PreparaEjemplos([string[]]$Ejemplos, [string]$Dir) {
  $metodos = @()
  foreach ($f in $Ejemplos) {
    $texto = [System.IO.File]::ReadAllText($f)
    foreach ($m in [regex]::Matches($texto, $PatronPrepara)) {
      $nombre = $m.Groups[1]
      $metodos += ((Get-Rel $Dir $f) + ':' + @($texto.Substring(0, $nombre.Index) -split "`n").Count + ' (' + $nombre.Value + ')')
    }
  }
  if ($metodos.Count -eq 0) { return '' }
  return 'Estos tests preparan algo antes de lanzar el job: ' + (@($metodos | Select-Object -First 5) -join ', ') + '. El test del original puede ser de otra version del framework y no hacerlo. Si este repositorio lo necesita (por ejemplo, un contexto que en produccion pone el arranque de la aplicacion), haz lo mismo en tu test antes de lanzar cada job. No lo uses para tapar un fallo del codigo de src/main.'
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

# El hash de la plantilla del arnes de ahora. La tarea lo guarda en entradas.plantilla: la plantilla con que se escribio el test guardado.
# Va aparte de la huella, que cambia tambien con los jobs y el test del original y no debe rehacer nada por eso.
function Get-HashPlantillaArnes { return (Get-Hash8 (Get-Plantilla 'arnes-local')) }

# El test guardado del arnes $T (el del original o el del migrado) se escribio con otra plantilla que la de ahora, o con una de antes de
# que la tarea la apuntara.
function Test-PlantillaVieja($T) {
  return ((Test-Path -LiteralPath (Join-Ruta $Local "arnes/$($T.entradas.repo)")) -and $T.entradas.plantilla -ne (Get-HashPlantillaArnes))
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
  if ($TestOriginal) {   # el del migrado: lo que preparan los ejemplos de su copia (no los de la referencia)
    $prepara = Get-PreparaEjemplos @($ejemplos | Where-Object { -not $PlantillaRoot -or -not $_.StartsWith($PlantillaRoot) }) $Dir
    if ($prepara) { $lista += "`n`n" + $prepara }
  }
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
  $e = [pscustomobject]@{ repo = $Repo; test = $Test; testOriginal = $TestOriginal; hashOriginal = $hashOriginal; copia = $Dir; dirs = $dirs; huella = $huella; plantilla = (Get-HashPlantillaArnes); prompt = $prompt }
  $guardada = Join-Path (Join-Path $Datos 'tareas') ('arnes-' + $Repo + '.json')
  $antes = $null
  if (Test-Path -LiteralPath $guardada) { try { $antes = Read-Json $guardada } catch { } }
  # Con un test guardado, la plantilla de la tarea es la de la tarea de antes (o '' si no la apuntaba), no la de ahora: sigue asi hasta que
  # se escriba otro test (Invoke-Arneses). Un no a la pregunta o un corte no dan por bueno en el siguiente lanzamiento un test de otra plantilla.
  if (Test-Path -LiteralPath (Join-Ruta $Local "arnes/$Repo")) {
    $e.plantilla = ''
    if ($antes -and $antes.entradas.plantilla) { $e.plantilla = [string]$antes.entradas.plantilla }
  }
  $t = Restore-Tarea (New-TareaTipo 'arnes-local' ('arnes-' + $Repo) '' ('prueba-local/arnes/' + $Repo) $e) $false
  if (-not $t.entradas.PSObject.Properties['plantilla']) { $t.entradas | Add-Member -NotePropertyName plantilla -NotePropertyValue '' }   # una tarea de antes de M37
  # Un arnes invalidado (un reintento que un corte dejo a medias) no empieza de cero: sigue por su intento y su
  # motivo, y la IA recibe ese motivo en su prompt de correccion. Restore-Tarea solo conserva las tareas hechas. Que el test del
  # original ya no este en arnes\ no cuenta: la huella se compara con el hash del original de entonces.
  if ($t.estado -eq 'pendiente' -and $antes -and $antes.estado -eq 'pendiente' -and $antes.intentos -gt 0 -and $antes.motivo -and $antes.entradas.huella -eq (Get-HuellaArnes $Test $Jobs ([string]$antes.entradas.hashOriginal))) {
    $t.intentos = $antes.intentos; $t.motivo = $antes.motivo; $t.ultimoEstado = $antes.ultimoEstado
    Save-Tarea $t
  }
  $t.entradas.copia = $Dir   # la de ahora, aunque la tarea venga de otro lanzamiento
  return (Test-Guardada $t (Join-Ruta $Local "arnes/$Repo"))
}

# Lo que fallo de antes en un lado, para el test de ese lado que se escribe otra vez: de los casos del prueba-local.json de antes ($Anterior) cuyo $Lado acaba FAILED o
# EXCEPCION (su 'fallos', Get-FalloLado: la causa es la que ensena la consola), las causas con $CausasMinimas casos o mas, agrupadas como los grupos de la consola
# (Get-CausaNormal), la de mas casos primero y $CausasMaximas como mucho, la causa del primer caso en 200 letras como mucho. Sin ninguna, @().
#  - Del migrado: los casos distintos donde el original no falla: 'En N casos el migrado acaba FAILED y el original no: <causa>.'
#  - Del original: los casos comparados (Test-Ejecutable), falle o no el migrado: 'En N casos el original acaba FAILED: <causa>.' El original funciona en produccion.
function Get-LineasFallo([string]$Lado) {
  $por = New-Object System.Collections.Hashtable ([System.StringComparer]::Ordinal)
  foreach ($c in @(@($Anterior.casos) | Where-Object { $_.resultado -ceq 'distinto' -or ($Lado -ceq 'original' -and (Test-Ejecutable $_)) })) {
    $propios = @(@($c.fallos) | Where-Object { $_.lado -ceq $Lado -and ($_.estado -ceq 'FAILED' -or $_.estado -ceq 'EXCEPCION') -and $_.causa })
    if ($propios.Count -eq 0 -or ($Lado -ceq 'migrado' -and @(@($c.fallos) | Where-Object { $_.lado -ceq 'original' }).Count -gt 0)) { continue }
    $firma = $propios[0].estado + '|' + (Get-CausaNormal ([string]$propios[0].causa) $c.caso)
    if (-not $por.ContainsKey($firma)) { $por[$firma] = [pscustomobject]@{ casos = 0; estado = $propios[0].estado; causa = [string]$propios[0].causa } }
    $por[$firma].casos++
  }
  $y = ''
  if ($Lado -ceq 'migrado') { $y = ' y el original no' }
  $lineas = @()
  foreach ($g in @(Get-MasRepetidas $por)) {
    $causa = $g.causa
    if ($causa.Length -gt 200) { $causa = $causa.Substring(0, 200) }
    $lineas += "- En $($g.casos) casos el $Lado acaba $($g.estado)${y}: $causa."
  }
  return $lineas
}

# Lo que el original y el migrado dejaban en carpetas distintas en el migrado de antes, para el test del migrado que se escribe otra vez: de los casos distintos del
# prueba-local.json de antes ($Anterior) con diferencias otraCarpeta (Join-OtraCarpeta), cada pareja de carpetas (su clave: un caso cuenta una vez por pareja, aunque
# deje varios ficheros en ella) con $CausasMinimas casos o mas, la de mas casos primero y $CausasMaximas como mucho: 'En N casos el original deja sus ficheros en A
# y el migrado en B: da a las propiedades de carpetas del test del migrado los mismos valores que les da el test del original.' Sin ninguna, @().
function Get-LineasOtraCarpeta {
  $por = New-Object System.Collections.Hashtable ([System.StringComparer]::Ordinal)
  foreach ($c in @(@($Anterior.casos) | Where-Object { $_.resultado -ceq 'distinto' })) {
    foreach ($d in @(@($c.diferencias) | Where-Object { $_.otraCarpeta } | Group-Object -Property clave -CaseSensitive | ForEach-Object { $_.Group[0] })) {
      if (-not $por.ContainsKey($d.clave)) { $por[$d.clave] = [pscustomobject]@{ casos = 0; original = (Format-Carpetas $d.carpetasOriginal); migrado = (Format-Carpetas $d.carpetasMigrado) } }
      $por[$d.clave].casos++
    }
  }
  return @(Get-MasRepetidas $por | ForEach-Object { "- En $($_.casos) casos el original deja sus ficheros en $($_.original) y el migrado en $($_.migrado): da a las propiedades de carpetas del test del migrado los mismos valores que les da el test del original." })
}

# Las entradas de $Por (firma -> objeto con 'casos', cuantos casos) con $CausasMinimas casos o mas: la de mas casos primero, a igualdad por la firma en orden
# ordinal, y $CausasMaximas como mucho.
function Get-MasRepetidas($Por) {
  $orden = New-Object System.Collections.Hashtable ([System.StringComparer]::Ordinal)
  foreach ($firma in $Por.Keys) { if ($Por[$firma].casos -ge $CausasMinimas) { $orden[(999999 - $Por[$firma].casos).ToString('D6') + '|' + $firma] = $Por[$firma] } }
  return @(Sort-Ordinal @($orden.Keys) | Select-Object -First $CausasMaximas | ForEach-Object { $orden[$_] })
}

# Lo que fallo la otra vez, para el primer intento de un test que se escribe otra vez ($T no esta hecha: se rehace con -RehacerOriginal o -RehacerArnes, se
# cambio la plantilla, o su tarea de antes quedo atascada y Restore-Tarea no la conserva). $Antes es su tarea del lanzamiento anterior (Get-TareaGuardada, antes
# de que Get-TareaArnes la pise) o $null. Lleva, en este orden:
#  - el ultimo motivo de la tarea de antes, si no estaba hecha (el de un test atascado ya lleva las pistas de Get-PistaArnes);
#  - para los dos, una linea por cada job (3 como mucho) cuyos casos del prueba-local.json de antes ($Anterior) salieron 'no se pudo preparar' porque el test no le pasa las
#    entradas ($MotivoSinEntradas, Get-FraseSinEntradas): esos tests no se invalidan, y asi la IA sabe por que se rehacen;
#  - para el del original, las pistas (Get-PistaArnes sobre cada motivo, sin repetir y 3 como mucho) de los casos 'no se pudo preparar' del prueba-local.json de
#    antes ($Anterior): casi todos esos motivos vienen del test del original.
#  - para el del original, una linea por cada job (3 como mucho) cuyo caso vacio guardado (salidas\vacio) no acabo COMPLETED, con su estado, la clase de la excepcion
#    y la primera linea de su causa (Get-LineasVacio): el test nuevo no debe dejarlo peor (Test-ArnesEscrito);
#  - para el del original, las causas por las que el original acababa FAILED o EXCEPCION en esos casos (Get-LineasFallo 'original'), con una frase encima: el original
#    funciona en produccion, asi que al test le falta lo que en produccion prepara el arranque (un bean, una propiedad, una carpeta);
#  - para el del migrado, las causas por las que el migrado acababa FAILED o EXCEPCION y el original no en ese prueba-local.json (Get-LineasFallo 'migrado'), con una
#    frase encima: si viene de una libreria es que al test le falta lo que en produccion prepara el arranque (como lo preparan los ejemplos, Get-PreparaEjemplos);
#    si viene de src/main, es un fallo del migrado y no se tapa;
#  - para el del migrado, una linea por cada pareja de carpetas (3 como mucho) con 2 casos o mas donde el original dejaba un fichero en una carpeta y el migrado en
#    otra (otraCarpeta) en ese prueba-local.json (Get-LineasOtraCarpeta): la linea pide dar a las propiedades de carpetas del test los mismos valores que les da el del original.
# Sin nada de eso es '' y el prompt no cambia. Invoke-Lote lo pone como la correccion del primer intento, por el mismo camino que el motivo de un reintento; la
# huella (Get-HuellaArnes) no lo lleva: un test que no se rehace no se escribe otra vez por esto. Una tarea que aun no ha llamado a la IA (se dijo que no a
# la pregunta de llamar a Copilot) conserva el de antes si ahora no hay otro.
function Get-PrevioArnes($T, $Antes) {
  $partes = @()
  if ($Antes -and $Antes.estado -ne 'hecha' -and $Antes.motivo) { $partes += "El ultimo motivo del test de antes: $($Antes.motivo)" }
  if ($Anterior) {
    foreach ($j in @(@($Anterior.casos) | Where-Object { $_.resultado -ceq 'no se pudo preparar' -and $_.motivo -ceq $MotivoSinEntradas } | ForEach-Object { [string]$_.job } | Select-Object -Unique | Select-Object -First 3)) { $partes += (Get-FraseSinEntradas $j) }
  }
  if ($T.entradas.repo -eq 'original' -and $Anterior) {
    $pistas = @()
    foreach ($m in @(@($Anterior.casos) | Where-Object { $_.resultado -ceq 'no se pudo preparar' -and $_.motivo } | ForEach-Object { [string]$_.motivo } | Select-Object -Unique)) {
      $p = Get-PistaArnes $T @($m -split "`n")
      if ($p -and $pistas -cnotcontains $p) { $pistas += $p }
      if ($pistas.Count -ge 3) { break }
    }
    if ($pistas.Count -gt 0) { $partes += "Los casos que no se pudieron preparar con el test del original de antes dicen:`n" + (@($pistas | ForEach-Object { "- $_" }) -join "`n") }
    $lineas = @(Get-LineasFallo 'original')
    if ($lineas.Count -gt 0) { $partes += 'Con el test de antes, estos casos acababan mal en el original, que en produccion funciona: al test le falta lo que en produccion prepara el arranque (un bean, una propiedad, una carpeta). Preparalo como los tests de ejemplo, sin tocar src/main.' + "`n" + ($lineas -join "`n") }
    $carpeta = Get-PistaCarpeta $T $lineas
    if ($carpeta) { $partes += $carpeta }
  }
  if ($T.entradas.repo -eq 'original') {
    $vacio = @(Get-LineasVacio)
    if ($vacio.Count -gt 0) { $partes += (@($vacio) -join "`n") }
  }
  if ($T.entradas.repo -eq 'migrado' -and $Anterior) {
    $lineas = @(Get-LineasFallo 'migrado')
    if ($lineas.Count -gt 0) { $partes += 'Si viene de una clase de una libreria porque al test le falta algo que en produccion prepara el arranque, preparalo como los tests de ejemplo. Si viene del codigo de src/main, no lo tapes: es un fallo del migrado.' + "`n" + ($lineas -join "`n") }
    $carpetas = @(Get-LineasOtraCarpeta)
    if ($carpetas.Count -gt 0) { $partes += ($carpetas -join "`n") }
  }
  if ($partes.Count -gt 0) { return "Lo que fallo la otra vez (de un lanzamiento anterior):`n" + ($partes -join "`n") }
  if ($Antes -and $Antes.estado -eq 'pendiente' -and $Antes.intentos -eq 0 -and $Antes.entradas.PSObject.Properties['previo']) { return [string]$Antes.entradas.previo }
  return ''
}

# Los ficheros que puede escribir el arnes de una copia.
function Get-Permitidos($T) {
  $p = @($T.entradas.test, 'src/test/resources/application-prueba-local.yml')
  if ($T.entradas.repo -eq 'original') { $p += 'pom.xml' }
  return $p
}

# Deshace en la copia $Dir lo que la IA cambio fuera de lo permitido: de $Cambios (Get-Cambios), lo que no es ninguna de las rutas de
# $Permitidos (una ruta, o una carpeta si acaba en /). Lo nuevo se borra y lo que git ya tenia vuelve a su base; lo permitido no se toca. Lo
# dice con una linea y devuelve la frase que va al principio del motivo si despues algo falla ('' si no ha deshecho nada). Lo usan
# Test-Arnes y Test-Arreglo: una sola regla.
function Undo-Fuera([string]$Dir, [string[]]$Cambios, [string[]]$Permitidos) {
  [string[]]$fuera = @($Cambios | Where-Object { $c = $_; @($Permitidos | Where-Object { $c -eq $_ -or ($_.EndsWith('/') -and $c.StartsWith($_)) }).Count -eq 0 })
  if ($fuera.Count -eq 0) { return '' }
  [System.Array]::Sort($fuera, [System.StringComparer]::Ordinal)   # en un orden que no depende de lo que git dice primero
  Invoke-GitRutas $Dir @('clean', '-fdq') $fuera
  Invoke-GitRutas $Dir @('checkout', '-q') @(Get-Cambios $Dir | Where-Object { $fuera -contains $_ })
  $lista = (@($fuera | Select-Object -First 5) -join ', ')
  if ($fuera.Count -gt 5) { $lista += " (y $($fuera.Count - 5) mas)" }
  Info "Deshago lo que la IA ha tocado fuera de lo suyo: $lista"
  return "He deshecho lo que tocaste fuera de $($Permitidos -join ', '): $lista."
}

# git $Orden -- <rutas>, de 100 en 100 (un jar descomprimido son miles de rutas, y Windows no admite una linea de mas de 32.767 caracteres).
function Invoke-GitRutas([string]$Dir, [string[]]$Orden, [string[]]$Rutas) {
  for ($i = 0; $i -lt $Rutas.Count; $i += 100) { [void](Invoke-Git $Dir ($Orden + '--' + @($Rutas | Select-Object -Skip $i -First 100))) }
}

# Las dependencias del proyecto de un pom (<project><dependencies>, no las de un plugin ni las de dependencyManagement), por groupId:artifactId.
function Get-DependenciasPom($Doc) {
  $h = [ordered]@{}
  foreach ($n in @($Doc.SelectNodes("/*[local-name()='project']/*[local-name()='dependencies']/*[local-name()='dependency']"))) {
    $h[((Get-HijoPom $n 'groupId') + ':' + (Get-HijoPom $n 'artifactId'))] = $n
  }
  return $h
}

function Get-HijoPom($N, [string]$Nombre) {
  $h = $N.SelectSingleNode("*[local-name()='$Nombre']")
  if ($h) { return $h.InnerText.Trim() }
  return ''
}

# Que cambio la IA en una dependencia que ya estaba: '' o una frase por hijo ('<version> 1.16.20 -> 1.18.30', '<scope> quitado').
function Get-CambioDependencia($Antes, $Despues) {
  $cambios = @()
  foreach ($nombre in @(@($Antes.ChildNodes) + @($Despues.ChildNodes) | Where-Object { $_.NodeType -eq 'Element' } | ForEach-Object { $_.LocalName } | Select-Object -Unique)) {
    $a = $Antes.SelectSingleNode("*[local-name()='$nombre']")
    $d = $Despues.SelectSingleNode("*[local-name()='$nombre']")
    if (-not $d) { $cambios += "<$nombre> quitado" }
    elseif (-not $a) { $cambios += "<$nombre> anadido" }
    elseif (($a.OuterXml -replace '\s', '') -cne ($d.OuterXml -replace '\s', '')) {
      if ($a.SelectNodes('*').Count -gt 0 -or $d.SelectNodes('*').Count -gt 0) { $cambios += "<$nombre> cambiado" }
      else { $cambios += "<$nombre> $($a.InnerText.Trim()) -> $($d.InnerText.Trim())" }
    }
  }
  return ($cambios -join ', ')
}

# La dependencia $Dep con <scope>test</scope>: el que tenga lo cambia; si no lleva, lo anade tras su ultimo hijo, con la sangria de ese hijo.
function Set-ScopeTest($Dep) {
  $s = $Dep.SelectSingleNode("*[local-name()='scope']")
  if ($s) { $s.InnerText = 'test'; return }
  $s = $Dep.OwnerDocument.CreateElement('scope', $Dep.NamespaceURI)
  $s.InnerText = 'test'
  $ultimo = @($Dep.ChildNodes | Where-Object { $_.NodeType -eq 'Element' } | Select-Object -Last 1)[0]
  if (-not $ultimo) { [void]$Dep.AppendChild($s); return }
  $antes = $ultimo.PreviousSibling
  if ($antes -and $antes.NodeType -match 'Whitespace') { $antes = $Dep.InsertAfter($antes.Clone(), $ultimo); [void]$Dep.InsertAfter($s, $antes) }
  else { [void]$Dep.InsertAfter($s, $ultimo) }
}

# La posicion, en $Texto, del '<' de la etiqueta de cierre del primer elemento $Nombre de profundidad $Profundidad (-1 si no hay).
function Get-IndiceCierre([string]$Texto, [int]$Profundidad, [string]$Nombre) {
  $r = New-Object System.Xml.XmlTextReader((New-Object System.IO.StringReader($Texto)))
  try {
    while ($r.Read()) {
      if ($r.NodeType -ne [System.Xml.XmlNodeType]::EndElement -or $r.Depth -ne $Profundidad -or $r.LocalName -ne $Nombre) { continue }
      $i = 0
      for ($linea = 1; $linea -lt $r.LineNumber; $linea++) {   # el LinePosition de un cierre es el de su nombre, tras '</'
        $i = $Texto.IndexOfAny([char[]]@("`r", "`n"), $i)
        if ($Texto[$i] -eq "`r" -and $i + 1 -lt $Texto.Length -and $Texto[$i + 1] -eq "`n") { $i++ }
        $i++
      }
      return $Texto.LastIndexOf('<', $i + $r.LinePosition - 1)
    }
  }
  finally { $r.Close() }
  return -1
}

# El texto de un elemento tal como lo escribio la IA, sin el xmlns que le pone OuterXml.
function Get-TextoElemento($N) { return $N.OuterXml.Replace(' xmlns="' + $N.NamespaceURI + '"', '') }

# Deja en $Ruta (el pom.xml de la copia del original, que la IA ha podido cambiar) el pom del original, $Antes (su texto, tal cual), mas
# las dependencias nuevas de la IA: las de <project><dependencies> con un groupId:artifactId que no estaba, todas con <scope>test</scope>.
# Lo demas que cambio la IA se pierde. Del original no cambia ni un byte (sus espacios, sus CRLF, sus comentarios): lo anadido va justo
# antes del cierre de sus <dependencies> (o, si no tiene, del de <project>), con la sangria de la IA. Lo escribe en UTF-8 sin BOM.
# Devuelve lo que ha deshecho, una frase por cosa: de cada dependencia que ya estaba y cambio, su groupId:artifactId y que cambio; 'algo mas
# del pom.xml fuera de <dependencies>' si cambio otra cosa; si el pom de la IA no es XML valido, vuelve al original y lo dice.
function Repair-PomSoloTest([string]$Antes, [string]$Ruta) {
  $deshecho = @()
  $final = $Antes
  try {
    $a = New-Object System.Xml.XmlDocument; $a.PreserveWhitespace = $true; $a.LoadXml($Antes)
    $d = New-Object System.Xml.XmlDocument; $d.PreserveWhitespace = $true; $d.LoadXml([System.IO.File]::ReadAllText($Ruta))
  }
  catch { $a = $null; $deshecho += 'tu pom.xml no era un XML valido: ' + $_.Exception.Message }
  if ($a) {
    $viejas = Get-DependenciasPom $a
    $ahora = Get-DependenciasPom $d
    foreach ($k in $viejas.Keys) {
      if (-not $ahora.Contains($k)) { $deshecho += "${k}: quitada"; continue }
      $c = Get-CambioDependencia $viejas[$k] $ahora[$k]
      if ($c) { $deshecho += "${k}: $c" }
    }
    $sinDependencias = @()
    foreach ($doc in @($a, $d)) {
      $copia = $doc.CloneNode($true)
      foreach ($n in @($copia.SelectNodes("/*[local-name()='project']/*[local-name()='dependencies']"))) { [void]$n.ParentNode.RemoveChild($n) }
      $sinDependencias += ($copia.DocumentElement.OuterXml -replace '\s', '')
    }
    if ($sinDependencias[0] -cne $sinDependencias[1]) { $deshecho += 'algo mas del pom.xml fuera de <dependencies>' }
    $nuevas = @($ahora.Keys | Where-Object { -not $viejas.Contains($_) } | ForEach-Object { $ahora[$_] })
    foreach ($n in $nuevas) { Set-ScopeTest $n }
    $cierre = Get-IndiceCierre $Antes 1 'dependencies'
    $anadir = ''
    if ($nuevas.Count -gt 0 -and $cierre -ge 0) {
      foreach ($n in $nuevas) {
        if ($n.PreviousSibling -and $n.PreviousSibling.NodeType -match 'Whitespace') { $anadir += $n.PreviousSibling.Value }
        $anadir += Get-TextoElemento $n
      }
    }
    elseif ($nuevas.Count -gt 0) {   # el original no tiene <dependencies>: las de la IA (todas nuevas) van enteras, antes del cierre de <project>
      $bloque = $d.SelectSingleNode("/*[local-name()='project']/*[local-name()='dependencies']")
      if ($bloque.PreviousSibling -and $bloque.PreviousSibling.NodeType -match 'Whitespace') { $anadir += $bloque.PreviousSibling.Value }
      $anadir += Get-TextoElemento $bloque
      $cierre = Get-IndiceCierre $Antes 0 'project'
    }
    if ($anadir) {
      $sitio = $cierre - [regex]::Match($Antes.Substring(0, $cierre), '\s*$').Length   # tras el ultimo hijo, antes de la sangria del cierre
      $final = $Antes.Substring(0, $sitio) + $anadir + $Antes.Substring($sitio)
    }
  }
  [System.IO.File]::WriteAllText($Ruta, $final, (New-Object System.Text.UTF8Encoding($false)))
  return $deshecho
}

# Los ficheros donde el batch de $Dir (una copia) puede nombrar tablas y columnas: los .java, .sql, .xml, .properties y .yml/.yaml de su src/main, por su ruta
# relativa (Get-Rel) -> la ruta completa.
function Get-FicherosConSql([string]$Dir) {
  $ficheros = @{}
  $raiz = Join-Ruta $Dir 'src/main'
  if (-not (Test-Path -LiteralPath $raiz)) { return $ficheros }
  foreach ($f in @(Get-ChildItem -LiteralPath $raiz -Recurse -File | Where-Object { $_.Extension -match '^\.(java|sql|xml|properties|ya?ml)$' })) { $ficheros[(Get-Rel $Dir $f.FullName)] = $f.FullName }
  return $ficheros
}

# El primer sitio (fichero:linea, el fichero por su ruta ordenada) donde el codigo de $Dir (una copia) nombra la columna $Columna: como palabra entera (COD_ZONA
# no esta en COD_ZONA_OLD), sin distinguir mayusculas y en cualquier texto de Get-FicherosConSql, con o sin comentarios. '' si no la nombra. Una vez por copia y
# columna ($script:SitiosColumna): recorre src/main.
function Get-SitioColumna([string]$Dir, [string]$Columna) {
  $clave = $Dir + '|' + $Columna.ToUpperInvariant()
  if (-not $script:SitiosColumna.ContainsKey($clave)) {
    $sitio = ''
    $ficheros = Get-FicherosConSql $Dir
    foreach ($rel in (Sort-Ordinal @($ficheros.Keys))) {
      $texto = [System.IO.File]::ReadAllText($ficheros[$rel])
      $m = [regex]::Match($texto, '(?i)(?<!\w)' + [regex]::Escape($Columna) + '(?!\w)')
      if ($m.Success) { $sitio = $rel + ':' + @($texto.Substring(0, $m.Index) -split "`n").Count; break }
    }
    $script:SitiosColumna[$clave] = $sitio
  }
  return $script:SitiosColumna[$clave]
}

# El inventario de tablas del batch de $Dir (una copia): las que su codigo nombra en SQL, cada una con su primer sitio (fichero:linea, el fichero
# ordenado por su ruta), por orden de nombre. Se buscan en src/main: dentro de las cadenas entre comillas dobles de los .java (no en sus
# comentarios) y en @Table(name = "X"), y en el texto de los .sql, .xml, .properties y .yml/.yaml (sin sus lineas de comentario). Las cadenas de
# los .java tambien son mensajes de log ("Error reading from file {}" no nombra la tabla FILE): una tabla de una cadena solo cuenta si la cadena
# lleva otra palabra de SQL (SELECT, INSERT, DELETE, MERGE, WHERE, VALUES, SET u ORDER BY) o si su nombre va todo en mayusculas (" FROM T_X ", un
# trozo de SQL partido con +). Es aproximado, con regex y sin Java: puede dar alguna que no es y no ve las que se arman con variables.
function Get-TablasBatch([string]$Dir) {
  $ficheros = Get-FicherosConSql $Dir
  $sitios = @{}
  foreach ($rel in (Sort-Ordinal @($ficheros.Keys))) {
    $texto = [System.IO.File]::ReadAllText($ficheros[$rel])
    $hay = @()
    if ($rel -match '(?i)\.java$') {
      # Los comentarios y los caracteres ('"') se leen enteros para que lo que llevan no cuente como cadena
      foreach ($m in [regex]::Matches($texto, '(?s)//[^\r\n]*|/\*.*?\*/|''(?:[^''\\\r\n]|\\.)+''|""".*?"""|"(?:[^"\\\r\n]|\\.)*"')) {
        if ($m.Value.StartsWith('"')) {
          $esSql = $m.Value -match '(?i)\b(?:SELECT|INSERT|DELETE|MERGE|WHERE|VALUES|SET)\b|\bORDER\s+BY\b'
          foreach ($h in @(Get-TablasSql $m.Value)) { if ($esSql -or $h.mayus) { $hay += [pscustomobject]@{ tabla = $h.tabla; indice = $m.Index + $h.indice } } }
        }
      }
      foreach ($m in [regex]::Matches($texto, '@Table\s*\(\s*name\s*=\s*"([^"]+)"')) {
        $n = Get-NombreTabla $m.Groups[1].Value
        if ($n) { $hay += [pscustomobject]@{ tabla = $n; indice = $m.Groups[1].Index } }
      }
    }
    else {
      # Sin los comentarios (<!-- --> y las lineas que empiezan por # o --), pero con sus saltos de linea: las lineas siguen contando igual
      $texto = [regex]::Replace($texto, '<!--[\s\S]*?-->|^[ \t]*(?:#|--).*$', [System.Text.RegularExpressions.MatchEvaluator]{ param($c) $c.Value -replace '[^\r\n]', '' }, [System.Text.RegularExpressions.RegexOptions]::Multiline)
      $hay = @(Get-TablasSql $texto)
    }
    foreach ($h in @($hay | Sort-Object indice)) {
      if (-not $sitios.ContainsKey($h.tabla)) { $sitios[$h.tabla] = $rel + ':' + @($texto.Substring(0, $h.indice) -split "`n").Count }
    }
  }
  return @(Sort-Ordinal @($sitios.Keys) | ForEach-Object { [pscustomobject]@{ tabla = $_; sitio = $sitios[$_] } })
}

# Las tablas de $Tablas (las de Get-TablasBatch) para un motivo: 'T_A (fichero:linea), T_B (fichero:linea)' y, pasadas las 10 primeras, ' y N mas'.
function Get-ListaTablas($Tablas) {
  $l = (@($Tablas | Select-Object -First 10 | ForEach-Object { "$($_.tabla) ($($_.sitio))" }) -join ', ')
  if (@($Tablas).Count -gt 10) { $l += " y $(@($Tablas).Count - 10) mas" }
  return $l
}

# Las tablas que usa el codigo de $Dir (Get-TablasBatch) y la base de prueba no tiene: las que no son ningun tablas\<TABLA>.csv de la salida del
# caso vacio (target\prueba-local\<job>\vacio, ya ejecutado) de ninguno de los $Jobs. El arnes deja uno por cada tabla de su base.
function Get-TablasFaltan([string]$Dir, [string[]]$Jobs) {
  $hay = Get-NombresTablas @($Jobs | ForEach-Object { Join-Ruta $Dir "target/prueba-local/$_/vacio/tablas" })
  return @(Get-TablasBatch $Dir | Where-Object { -not $hay.ContainsKey($_.tabla) })
}

# Los nombres, en mayusculas, de los <TABLA>.csv de las carpetas $Carpetas (las que existan), como las claves de una tabla hash; el valor es la ruta del .csv.
function Get-NombresTablas([string[]]$Carpetas) {
  $n = @{}
  foreach ($d in $Carpetas) {
    if (Test-Path -LiteralPath $d) { foreach ($f in @(Get-ChildItem -LiteralPath $d -File -Filter '*.csv')) { $n[$f.BaseName.ToUpperInvariant()] = $f.FullName } }
  }
  return $n
}

# Las columnas de la primera linea (separadas por ';') de un tablas\<TABLA>.csv, sin espacios alrededor ni vacias; @() si no esta.
function Get-Columnas([string]$Csv) {
  if (-not (Test-Path -LiteralPath $Csv)) { return @() }
  $l = @([System.IO.File]::ReadAllLines($Csv))
  if ($l.Count -eq 0) { return @() }
  return @($l[0] -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

# Que tan bien acaba el caso vacio de la carpeta de salida $Sal: 0 COMPLETED, 1 otro estado del job (FAILED, STOPPED...), 2 EXCEPCION (el job ni arranca), 3 sin estado.
function Get-RangoEstado([string]$Sal) {
  $estado = Get-Estado $Sal
  if (-not $estado) { return 3 }
  if ($estado -ceq 'COMPLETED') { return 0 }
  if ($estado -ceq 'EXCEPCION') { return 2 }
  return 1
}

# Como acaba el caso vacio de $Sal: su estado y, si no es COMPLETED, entre parentesis la clase de la excepcion (Get-Excepcion) y la primera linea de la causa
# ($Causa): 'FAILED (java.nio.file.NoSuchFileException: /datos/salida/RESUMEN.txt)' o 'EXCEPCION (BeanCreationException)'. Sin estado, 'sin estado'.
function Get-ComoAcaba([string]$Sal, [string]$Causa) {
  $estado = Get-Estado $Sal
  if (-not $estado) { return 'sin estado' }
  $detalle = Get-DetalleVacio $Sal $Causa
  if ($estado -ceq 'COMPLETED' -or -not $detalle) { return $estado }
  return "$estado ($detalle)"
}

# El detalle de un caso vacio que no acabo COMPLETED: la clase de la excepcion si el job ni arranco (Get-Excepcion) y la primera linea de la causa ($Causa), unidas con ': '; '' si no hay ninguna.
function Get-DetalleVacio([string]$Sal, [string]$Causa) {
  $partes = @()
  $clase = Get-Excepcion $Sal
  if ($clase) { $partes += $clase }
  $linea = (($Causa -split "`n")[0]).Trim()
  if ($linea) { $partes += $linea }
  return ($partes -join ': ')
}

# Las lineas del previo del original (Get-PrevioArnes) sobre su caso vacio guardado (salidas\vacio): por cada job cuyo caso no acabo COMPLETED (con estado), por orden de
# nombre y 3 como mucho, 'Con el test de antes, el caso vacio de <job> acababa <estado>: <clase y causa>.' La causa es la de salidas\vacio\causas.json (Save-CausasVacio).
function Get-LineasVacio {
  $base = Join-Ruta $Local 'salidas/vacio'
  $lineas = @()
  if (-not (Test-Path -LiteralPath $base)) { return $lineas }
  foreach ($d in @(Sort-Ordinal @(Get-ChildItem -LiteralPath $base -Directory | ForEach-Object { $_.Name }))) {
    $sal = Join-Path $base $d
    if ((Get-RangoEstado $sal) -in 0, 3) { continue }
    $detalle = Get-DetalleVacio $sal (Get-CausaVacio $base $d)
    $linea = "Con el test de antes, el caso vacio de $d acababa $(Get-Estado $sal)"
    if ($detalle) { $linea += ": $detalle" }
    $lineas += "$linea."
    if ($lineas.Count -ge 3) { break }
  }
  return $lineas
}

# La causa con que acabo un job el caso vacio guardado en la carpeta $Carpeta (salidas\vacio o salidas\vacio-anterior), de su causas.json (Save-CausasVacio); si la carpeta
# no tiene causas.json (se guardo antes de M69), la del registro de Maven mas reciente del caso vacio del original (Get-CausaRegistroVacio). '' si no la hay. Con causas.json manda
# el, aunque no diga nada del job.
function Get-CausaVacio([string]$Carpeta, [string]$Job) {
  $f = Join-Path $Carpeta 'causas.json'
  if (-not (Test-Path -LiteralPath $f)) { return (Get-CausaRegistroVacio) }
  try { $causas = Read-Json $f } catch { return '' }
  $p = $causas.PSObject.Properties[$Job]
  if ($p) { return [string]$p.Value }
  return ''
}

# La causa (primera linea) del registro de Maven mas reciente por fecha de escritura del caso vacio del arnes del original (registros\mvn-<n>-arnes-original--caso-vacio.log: el nombre
# de Invoke-Maven con 'arnes original, caso vacio'; el contador <n> vuelve a 1 en cada lanzamiento, por eso no vale para ordenarlos), sacada de sus lineas con Get-CausaMaven y sin
# informes de surefire (un $Desde que ninguno cumple). '' si no hay registro o no dice la causa.
function Get-CausaRegistroVacio {
  $carpeta = Join-Ruta $Local 'registros'
  if (-not (Test-Path -LiteralPath $carpeta)) { return '' }
  $registro = @(Get-ChildItem -LiteralPath $carpeta -File -Filter 'mvn-*-arnes-original--caso-vacio.log' | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1)
  if ($registro.Count -eq 0) { return '' }
  $causa = Get-CausaCorta (Get-CausaMaven $carpeta ([DateTime]::MaxValue) @([System.IO.File]::ReadAllLines($registro[0].FullName)))
  return (($causa -split "`n")[0]).Trim()
}

# Apunta en $Carpeta\causas.json (salidas\vacio) la primera linea de la causa de Maven ($Causa) de cada job de $Jobs cuyo caso vacio guardado no acabo COMPLETED: estado.txt dice como
# acabo y no por que, y el test nuevo se compara con esto (Get-PeorQueAntes) y el primer intento de uno que se escribe otra vez lo sabe (Get-PrevioArnes). Lo escribe siempre, aunque
# vaya vacio: su presencia dice que ya se miro y Get-CausaVacio no busca en los registros, que el test nuevo pisa.
function Save-CausasVacio([string]$Carpeta, [string[]]$Jobs, [string]$Causa) {
  $causas = [ordered]@{}
  $linea = (($Causa -split "`n")[0]).Trim()
  if ($linea) { foreach ($j in $Jobs) { if ((Get-RangoEstado (Join-Path $Carpeta $j)) -ne 0) { $causas[$j] = $linea } } }
  Write-Json (Join-Path $Carpeta 'causas.json') $causas
}

# Las frases de lo que es peor en el caso vacio que ha dejado el test nuevo de la copia $Dir ($Causa: la de su Maven) que en el del test de antes (salidas\vacio-anterior),
# job a job: el estado (Get-RangoEstado: no puede bajar), las tablas que ya no estan (sin BATCH_ ni TASK_, como Get-TablasOriginal) y las columnas de la cabecera
# de antes que ya no estan en las tablas que siguen (sin distinguir mayusculas). Un job sin caso vacio de antes no cuenta. @() si no es peor en nada.
function Get-PeorQueAntes([string]$Dir, [string[]]$Jobs, [string]$Causa) {
  $frases = @()
  $carpetaAntes = Join-Ruta $Local 'salidas/vacio-anterior'
  foreach ($j in $Jobs) {
    $antes = Join-Ruta $carpetaAntes $j
    if (-not (Test-Path -LiteralPath $antes)) { continue }
    $ahora = Join-Ruta $Dir "target/prueba-local/$j/vacio"
    if ((Get-RangoEstado $ahora) -gt (Get-RangoEstado $antes)) {
      $frases += "Con tu test, el caso vacio de $j acaba $(Get-ComoAcaba $ahora $Causa) y con el test de antes acababa $(Get-ComoAcaba $antes (Get-CausaVacio $carpetaAntes $j))."
    }
    $tablasAntes = Get-NombresTablas @(Join-Ruta $antes 'tablas')
    $tablasAhora = Get-NombresTablas @(Join-Ruta $ahora 'tablas')
    $habia = @(Sort-Ordinal @($tablasAntes.Keys | Where-Object { $_ -cnotmatch '^(BATCH|TASK)_' }))
    $faltan = @($habia | Where-Object { -not $tablasAhora.ContainsKey($_) })
    if ($faltan.Count -gt 0) { $frases += "En el caso vacio de $j, tu base no tiene estas tablas que si tenia la del test de antes: $($faltan -join ', ')." }
    foreach ($t in @($habia | Where-Object { $tablasAhora.ContainsKey($_) })) {
      $siguen = @(Get-Columnas $tablasAhora[$t] | ForEach-Object { $_.ToUpperInvariant() })
      $sin = @(Get-Columnas $tablasAntes[$t] | Where-Object { $siguen -cnotcontains $_.ToUpperInvariant() })
      if ($sin.Count -gt 0) { $frases += "En el caso vacio de $j, la tabla $t de tu base ya no tiene estas columnas que si tenia la del test de antes: $($sin -join ', ')." }
    }
  }
  return $frases
}

# Las columnas que el prueba-local.json de antes ($Anterior) daba como no creadas por el test del original ($PatronColumnaSinCrear en el motivo de sus casos), sin
# repetir: objetos con nombre ('TABLA.COLUMNA', o solo la columna si el motivo no trae la tabla), tabla ('' si no), columna y sitio (donde la usa el codigo).
function Get-ColumnasPedidas {
  $pedidas = @()
  if (-not $Anterior) { return $pedidas }
  foreach ($motivo in @(@($Anterior.casos) | ForEach-Object { [string]$_.motivo } | Where-Object { $_ })) {
    foreach ($m in [regex]::Matches($motivo, $PatronColumnaSinCrear)) {
      $t = $m.Groups['t'].Value
      $c = $m.Groups['c'].Value
      if (@($pedidas | Where-Object { $_.tabla -ieq $t -and $_.columna -ieq $c }).Count -gt 0) { continue }
      $nombre = $c
      if ($t) { $nombre = "$t.$c" }
      $pedidas += [pscustomobject]@{ nombre = $nombre; tabla = $t; columna = $c; sitio = $m.Groups['s'].Value }
    }
  }
  return $pedidas
}

# De las columnas $Pedidas (Get-ColumnasPedidas), las que no estan en la cabecera de ningun tablas\<TABLA>.csv de las carpetas $Carpetas: el de su tabla si el motivo la dice y,
# si no, el de cualquiera.
function Get-ColumnasFaltan([string[]]$Carpetas, $Pedidas) {
  $tablas = Get-NombresTablas $Carpetas
  $faltan = @()
  foreach ($p in @($Pedidas)) {
    $esta = $false
    foreach ($k in @($tablas.Keys | Where-Object { -not $p.tabla -or $_ -ceq $p.tabla.ToUpperInvariant() })) {
      if (@(Get-Columnas $tablas[$k] | Where-Object { $_ -ieq $p.columna }).Count -gt 0) { $esta = $true }
    }
    if (-not $esta) { $faltan += $p }
  }
  return $faltan
}

# Las columnas de Get-ColumnasPedidas para un motivo: 'T.C (fichero:linea), U.D (fichero:linea)'.
function Get-ListaColumnas($Columnas) { return (@($Columnas | ForEach-Object { "$($_.nombre) ($($_.sitio))" }) -join ', ') }

# Las tablas de la base del test del original: las de tablas\ de su caso vacio de cada uno de los $Jobs (salidas\vacio\<job>, las que dejo Test-ArnesEscrito del
# original), por orden de nombre y sin las de Spring Batch (BATCH_) ni las de Spring Cloud Task (TASK_), que cada lado trae a su manera (Compare-Caso las salta).
function Get-TablasOriginal([string[]]$Jobs) {
  $n = Get-NombresTablas @($Jobs | ForEach-Object { Join-Ruta $Local "salidas/vacio/$_/tablas" })
  return @(Sort-Ordinal @($n.Keys | Where-Object { $_ -cnotmatch '^(BATCH|TASK)_' }))
}

# Comprueba el arnes que acaba de escribir la IA en su copia. Antes lo deja en lo que se puede probar: lo que cambio fuera de lo que
# puede escribir (Get-Permitidos) se deshace (Undo-Fuera) y el pom.xml del original queda como estaba con sus dependencias nuevas de test
# (Repair-PomSoloTest), y cada cosa se dice. Despues, Test-ArnesEscrito. Devuelve '' o el motivo; si hubo algo que deshacer, el motivo
# empieza por ello: la IA tiene que saber que lo que tocaste ya no esta.
function Test-Arnes($T, [string[]]$Jobs, [bool]$SoloAviso = $false) {
  $dir = $T.entradas.copia
  Remove-Carpeta (Join-Ruta $dir $Casos)
  $avisos = @()
  $a = Undo-Fuera $dir @(Get-Cambios $dir) @(Get-Permitidos $T)
  if ($a) { $avisos += $a }
  if (@(Get-Cambios $dir) -contains 'pom.xml') {
    $deshecho = @(Repair-PomSoloTest $PomOriginal (Join-Ruta $dir 'pom.xml'))
    if ($deshecho.Count -gt 0) {
      $a = 'Dejo el pom.xml del original como estaba, con tus dependencias nuevas de test: ' + ($deshecho -join '; ')
      Info $a
      $avisos += $a
    }
  }
  $m = Test-ArnesEscrito $T $Jobs $SoloAviso
  if ($m -and $avisos.Count -gt 0) { return (($avisos -join ' ') + " $m") }
  return $m
}

# '' si el arnes de la copia, ya sin lo de fuera, vale; si no, el motivo: escrito el test, compila y, con un caso vacio por job, cada job
# deja estado.txt (la salida del vacio del original se guarda en salidas\vacio: se compara con la de cada caso) y la base de prueba tiene las
# tablas que usa el codigo (Get-TablasFaltan) y, en el del migrado, las que tiene la base del test del original (Get-TablasOriginal): la que el codigo arma en
# tiempo de ejecucion no sale del inventario, pero el original ya la crea. Esas puertas rechazan el intento mientras queden otros, y no el ultimo ni uno guardado
# ($SoloAviso): el inventario es aproximado y puede dar tablas que no son, asi que un arnes sin ellas se acepta con un aviso.
# Un test del original que se escribe otra vez (hay uno de antes en salidas\vacio-anterior: Save-Anterior) tampoco puede dejar el caso vacio peor que el de antes
# (estado, tablas y columnas: Get-PeorQueAntes) ni sin las columnas que el prueba-local.json de antes decia que no creaba (Get-ColumnasPedidas); en el ultimo intento, si
# queda peor, no se guarda y se vuelve al de antes ($script:VueltaAlDeAntes; lo hace Invoke-Arneses), salvo que el de antes dejara un job sin probar (ver abajo).
function Test-ArnesEscrito($T, [string[]]$Jobs, [bool]$SoloAviso = $false) {
  $dir = $T.entradas.copia
  $esOrig = ($T.entradas.repo -eq 'original')
  if (-not (Test-Path -LiteralPath (Join-Ruta $dir $T.entradas.test))) { return "No has escrito el test $($T.entradas.test)." }
  $r = Invoke-Maven $dir $esOrig @('test-compile') "arnes $($T.entradas.repo), compilar"
  if ($r.Codigo -ne 0) { return ("El test no compila (mvn test-compile). Maven dice:`n" + (Get-FalloMaven $r)) }
  foreach ($j in $Jobs) { foreach ($c in @('vacio', 'otro')) { [void](New-Item -ItemType Directory -Path (Join-Ruta $dir "$Casos/$j/$c") -Force) } }
  Remove-Carpeta (Join-Ruta $dir 'target/prueba-local')
  $desdeVacio = Get-Date
  $r = Invoke-Maven $dir $esOrig @('test', '-Dtest=PruebaLocalTest', '-Dprueba.local.caso=vacio', "-Dsurefire.timeout=$($Cfg.SegundosTestArnes)") "arnes $($T.entradas.repo), caso vacio"
  Remove-Carpeta (Join-Ruta $dir $Casos)
  # Surefire mata el fork pasado el tiempo y Maven acaba con 'There was a timeout in the fork' (en Surefire 2.x, '... timeout or other error in the fork'): SurefireHelper.createErrorMessage
  if ($r.Codigo -ne 0 -and (@($r.Salida) -join "`n") -match 'There was a timeout( or other error)? in the fork') {
    return "Con un caso vacio, el test no termina en $($Cfg.SegundosTestArnes) s: el job intenta conectar con algo de verdad (base de datos, SFTP, correo, HTTP). Simulalo en el test."
  }
  foreach ($j in $Jobs) {
    $sal = Join-Ruta $dir "target/prueba-local/$j/vacio"
    if (-not (Test-Path -LiteralPath (Join-Path $sal 'estado.txt'))) {
      $porque = Get-Porque $sal $r
      $m = "Con un caso vacio ($Casos/$j/vacio, una carpeta sin nada), el job $j $porque"
      $pista = Get-PistaArnes $T (@($r.Salida) + @($r.Causa) + @($porque -split "`n"))   # en el orden de la salida de Maven: es el de las claves de la pista de la propiedad
      if ($pista) { $m += "`n$pista" }
      return $m
    }
    if (Test-Path -LiteralPath (Join-Ruta $dir "target/prueba-local/$j/otro")) { return "Con -Dprueba.local.caso=vacio, el test ha ejecutado tambien $Casos/$j/otro. Si la propiedad prueba.local.caso tiene valor, ejecuta solo los casos con ese nombre: cada caso se lanza en su propio Maven." }
  }
  # Con un caso vacio, el original arranca el job y el migrado no (estado=EXCEPCION): el test del migrado no simula lo que el job necesita, o le pasa
  # mal las propiedades. Como la puerta de las tablas: se rechaza mientras quedan intentos y, en el ultimo o con un test guardado, se acepta con un
  # aviso (puede ser el codigo del migrado). Uno rechazado antes por esto y aceptado en el ultimo intento se apunta en $script:NoArranca. Si es un error del codigo
  # (Get-ErrorCodigo), no se rechaza nunca y siempre se apunta (ver abajo).
  if (-not $esOrig) {
    foreach ($j in $Jobs) {
      $estadoOrig = Get-Estado (Join-Ruta $Local "salidas/vacio/$j")
      $clase = Get-Excepcion (Join-Ruta $dir "target/prueba-local/$j/vacio")
      if (-not $estadoOrig -or $estadoOrig -ceq 'EXCEPCION' -or -not $clase) { continue }
      $causa = Get-CausaCorta $r.Causa
      $detalle = $clase
      if ($causa) { $detalle = "$clase ($causa)" }
      # Un error del codigo del migrado (Get-ErrorCodigo: clase final, referencia circular, bean repetido): otro intento no lo arregla. Se acepta aunque queden intentos, con un
      # aviso que lo dice, y el job se prueba con un solo caso (Invoke-Salidas) aunque el test este guardado ($SoloAviso).
      $codigo = Get-ErrorCodigo $clase $causa
      if ($codigo) {
        Aviso "Con un caso vacio, el original arranca el job $j (estado=$estadoOrig) y con tu test el migrado no: $detalle. $(Format-ErrorCodigo $codigo) Otro intento no lo arregla: corre el paso de calidad de rescate.ps1."
        $script:NoArranca[$j] = [pscustomobject]@{ clase = $clase; veces = $T.intentos + 1 }
        continue
      }
      $roto = "Con un caso vacio, el original arranca el job $j (estado=$estadoOrig) y con tu test el migrado no: $detalle. Revisa lo que simula el test y las propiedades que le pasa."
      if (-not $SoloAviso -and ($T.intentos + 1) -lt [int]$Cfg.Intentos) { return $roto }
      Aviso $roto
      # Aceptado en el ultimo intento tras rechazarlo por esto (no uno guardado): el job se prueba con un solo caso (Invoke-Salidas) y la consola dice cuantas veces se escribio
      if (-not $SoloAviso -and $T.motivo.Contains("el original arranca el job $j (estado=")) { $script:NoArranca[$j] = [pscustomobject]@{ clase = $clase; veces = $T.intentos + 1 } }
    }
  }
  $faltanOrig = @()
  if (-not $esOrig) {
    $hay = Get-NombresTablas @($Jobs | ForEach-Object { Join-Ruta $dir "target/prueba-local/$_/vacio/tablas" })
    $faltanOrig = @(Get-TablasOriginal $Jobs | Where-Object { -not $hay.ContainsKey($_) })
    if ($faltanOrig.Count -gt 0 -and -not $SoloAviso -and ($T.intentos + 1) -lt [int]$Cfg.Intentos) {
      return "La base de tu test no tiene estas tablas que si tiene la del test del original: $($faltanOrig -join ', '). Crealas con las mismas columnas que en el test del original."
    }
  }
  $faltan = @(Get-TablasFaltan $dir $Jobs)
  if ($faltan.Count -gt 0 -and -not $SoloAviso -and ($T.intentos + 1) -lt [int]$Cfg.Intentos) {
    return "La base de prueba no tiene estas tablas que usa el batch: $(Get-ListaTablas $faltan). Crealas en el paso de la base limpia con las columnas que usa el codigo."
  }
  # El test del original que se escribe otra vez no puede quedar peor que el de antes (salidas\vacio-anterior: Get-PeorQueAntes) y tiene que crear las columnas que el
  # prueba-local.json de antes decia que le faltaban (Get-ColumnasPedidas). Se rechaza mientras quedan intentos. En el ultimo, si queda peor se vuelve al de antes
  # ($script:VueltaAlDeAntes: no se guarda nada y Invoke-Arneses lo restaura; salvo que el de antes dejara algun job sin probar, con el original FAILED o EXCEPCION igual en
  # todos sus casos en el prueba-local.json de antes: Get-JobsFalloOriginal; entonces se queda el nuevo y una Info lo dice) y, si solo faltan columnas, se acepta con un
  # aviso. Uno guardado ($SoloAviso) no pasa por
  # aqui. El del migrado tampoco: su caso vacio no se guarda (nada con que compararlo) y las columnas pedidas son las del test del original (las tablas del original
  # ya las pide la puerta de arriba).
  $sinCrear = @()
  if ($esOrig -and -not $SoloAviso) {
    $peor = @()
    if ($script:Anteriores['original']) { $peor = @(Get-PeorQueAntes $dir $Jobs (Get-CausaCorta $r.Causa)) }
    $sinCrear = @(Get-ColumnasFaltan @($Jobs | ForEach-Object { Join-Ruta $dir "target/prueba-local/$_/vacio/tablas" }) @(Get-ColumnasPedidas))
    if ($peor.Count -gt 0 -or $sinCrear.Count -gt 0) {
      $frases = @($peor)
      if ($sinCrear.Count -gt 0) { $frases += "Tu base no crea estas columnas que usa el codigo: $(Get-ListaColumnas $sinCrear)." }
      if (($T.intentos + 1) -lt [int]$Cfg.Intentos) { return ($frases -join ' ') }
      if ($peor.Count -gt 0) {
        # Volver al de antes no arregla un job que con ese test el original no podia probar (Get-JobsFalloOriginal sobre el prueba-local.json de antes): se queda el nuevo.
        $sinProbar = @(Get-JobsFalloOriginal $Anterior.casos | ForEach-Object { $_.job })
        if ($sinProbar.Count -eq 0) {
          $script:VueltaAlDeAntes = "El test nuevo del original quedaba peor que el de antes ($((@($peor) -join ' ').TrimEnd('.'))): sigo con el de antes."
          return ''
        }
        Info "Me quedo con el test nuevo del original: queda peor que el de antes en el caso vacio ($((@($peor) -join ' ').TrimEnd('.'))), pero el de antes dejaba $(if ($sinProbar.Count -eq 1) { 'el job' } else { 'los jobs' }) $($sinProbar -join ', ') sin probar (el original fallaba igual en todos sus casos)."
      }
    }
  }
  if ($esOrig) {
    Remove-Carpeta (Join-Ruta $Local 'salidas/vacio')
    foreach ($j in $Jobs) { [void](Copy-Salida (Join-Ruta $dir "target/prueba-local/$j/vacio") (Join-Ruta $Local "salidas/vacio/$j") $j "$j/vacio" @(Get-Hoy $desdeVacio (Get-Date))) }
    Save-CausasVacio (Join-Ruta $Local 'salidas/vacio') $Jobs (Get-CausaCorta $r.Causa)
  }
  # Los tres avisos dicen el lado que toca y ofrecen primero editar el test guardado ($arreglo) y, si no, escribirlo otra vez con la IA
  $lado = 'migrado'; $falla = 'EXCEPCION'; $rehaz = '-RehacerArnes'
  if ($esOrig) { $lado = 'original'; $falla = 'FAILED'; $rehaz = '-RehacerOriginal' }
  $arreglo = "tu test guardado (prueba-local\arnes\$lado) y relanza sin -Rehacer, o relanza con $rehaz para que lo escriba otra vez."
  if ($faltanOrig.Count -gt 0) { Aviso "La base de tu test sigue sin estas tablas que si tiene la del test del original: $($faltanOrig -join ', '). Los casos que las usen saldran EXCEPCION en el migrado. Anadelas a $arreglo" }
  if ($faltan.Count -gt 0) { Aviso "La base de prueba sigue sin estas tablas: $(Get-ListaTablas $faltan). Los casos que las usen saldran $falla en el $lado. Anadelas a $arreglo" }
  if ($sinCrear.Count -gt 0) { Aviso "La base de tu test sigue sin crear estas columnas que usa el codigo: $(Get-ListaColumnas $sinCrear). Los casos que las usen saldran FAILED en el original. Crealas en $arreglo" }
  return ''
}

# Lo que se le dice a la IA de un arnes rechazado cuando el test falla de una de cinco maneras que el motivo solo no explica: '' o una frase por pista.
# $Lineas son las del fallo: lo que ya trae el motivo (error.txt del caso vacio o lo que dice Maven), la salida de Maven y su causa (sale de los informes
# de surefire): los mismos sitios de donde sale hoy el motivo.
#  - Una propiedad sin valor ($PatronPropiedad): el job o el bean lee una propiedad que en el servidor llega por el configmap o por una variable de entorno y el
#    test no se la da. Se nombran hasta 3 claves, sin repetir y en el orden en que salen, y se dice que se le de un valor (@TestPropertySource,
#    @DynamicPropertySource, src/test/resources, @TempDir para una ruta). Con una clave no hay pista del bean: el bean falla por la propiedad (a veces es el propio job
#    que se prueba) y sustituirlo por un mock despistaria. La pista del CREATE TABLE sigue aparte.
#  - Un bean que falla al crearse (Spring: 'Error creating bean with name' y, en la misma linea, 'Factory method ... threw exception', 'Failed to instantiate'
#    o BeanInstantiationException): casi siempre llama fuera al arrancar. Se nombra el ultimo bean de la linea, el mas interno, con el mensaje de su excepcion.
#    Si en lo que sea sale una tabla o una columna que no esta ($PatronTablaFalta), no hay pista: eso lo cubre Get-MotivoBase.
#  - Un CREATE TABLE que H2 rechaza (el test saca las tablas del SQL del codigo con un parser suyo y toma una palabra de la sentencia, IF, por el nombre de
#    la tabla): se le dan las tablas del codigo (Get-TablasBatch de la copia del arnes) para que escriba un CREATE TABLE fijo de cada una.
#  - Un DROP TABLE que H2 rechaza ($PatronDrop: el test borra las tablas una a una antes de crearlas y una depende de otra): se le dice que no borre tablas y
#    que use una base H2 en memoria con un nombre unico en cada ejecucion o, si tiene que limpiar, DROP ALL OBJECTS al principio. Va con las demas.
#  - Una columna que la base limpia no tiene y que usa el codigo (Get-PistaColumnas): el test crea la tabla sin ella. Va con las demas.
function Get-PistaArnes($T, [string[]]$Lineas) {
  $pistas = @()
  $texto = $Lineas -join "`n"
  $claves = @([regex]::Matches($texto, $PatronPropiedad) | ForEach-Object { $_.Groups['k'].Value } | Select-Object -Unique | Select-Object -First 3)
  $bean = @($Lineas | Where-Object { $_ -match "Error creating bean with name '[^']+'" -and $_ -match "Factory method '[^']*' threw exception|Failed to instantiate|BeanInstantiationException" })
  if ($claves.Count -gt 0) {
    $pistas += "Falta una propiedad en el test: $($claves -join ', '). En el servidor llega por el configmap o por una variable de entorno; en el test nadie le da valor. Dale un valor en el test (@TestPropertySource, @DynamicPropertySource o src/test/resources); si es una carpeta o un fichero, usa una carpeta temporal del test (@TempDir). No la sustituyas por un mock y no toques src/main."
  }
  elseif ($bean.Count -gt 0 -and @($Lineas | Where-Object { $_ -match $PatronTablaFalta }).Count -eq 0) {
    $nombre = [regex]::Match($bean[0], "^.*Error creating bean with name '([^']+)'").Groups[1].Value
    $detalle = ([regex]::Match($bean[0], '^.*threw exception with message: (.*)$').Groups[1].Value).Trim()
    if (-not $detalle) { $detalle = ($bean[0] -replace "^.*Error creating bean with name '[^']+'", '').Trim(' :') }
    if ($detalle.Length -gt 120) { $detalle = $detalle.Substring(0, 120) }
    $pistas += "El contexto de Spring no arranca: el bean $nombre falla al crearse ($detalle). Si llama fuera al arrancar (base de datos, Mongo, REST, ficheros), sustituyelo en el test por un @MockBean (@MockitoBean en Spring Boot 3.4 o posterior) o por un @Bean @Primary de prueba que no llame fuera. No toques src/main."
  }
  $sentencia = Get-SentenciaCreate $texto
  if ($sentencia) {
    $tablas = @(Get-TablasBatch $T.entradas.copia)
    $cuales = 'cada tabla que use el batch, con las columnas que usa el codigo.'
    if ($tablas.Count -gt 0) { $cuales = "cada una de estas, con las columnas que usa el codigo: $(Get-ListaTablas $tablas)." }
    $pistas += "El test crea mal una tabla ($sentencia). No saques las tablas del SQL del codigo: escribe un CREATE TABLE fijo para $cuales"
  }
  $drop = [regex]::Match($texto, $PatronDrop)
  if ($drop.Success) {
    $pistas += "El test borra las tablas una a una y una depende de otra ($($drop.Groups[1].Value)). No borres tablas: usa una base H2 en memoria con un nombre unico en cada ejecucion (jdbc:h2:mem:<nombre>;DB_CLOSE_DELAY=-1) o, si tiene que limpiar, DROP ALL OBJECTS al principio."
  }
  $columnas = Get-PistaColumnas $T $texto
  if ($columnas) { $pistas += $columnas }
  $carpeta = Get-PistaCarpeta $T $Lineas
  if ($carpeta) { $pistas += $carpeta }
  return ($pistas -join ' ')
}

# La pista de una ruta fija, de $Lineas (las de un fallo del test del ORIGINAL: otro lado no tiene pista), hasta 2 rutas distintas: el original acaba con una
# NoSuchFileException, FileNotFoundException o AccessDeniedException ($PatronRutaFija) sobre una ruta absoluta que no es de la copia ni de la carpeta de un caso
# (target\prueba-local): el original funciona en produccion y usa esa carpeta, asi que el test tiene que dar a la propiedad que la define una carpeta del caso, como hace
# el test del migrado. Si un grep sencillo la encuentra (la ruta, su carpeta o la de arriba, en cualquiera de sus formas: como esta, con / o con \\, en
# src/main/resources/application*.properties, .yml o .yaml de la copia del arnes), dice donde: fichero:linea y la clave. '' si no hay ninguna.
function Get-PistaCarpeta($T, [string[]]$Lineas) {
  if ($T.entradas.repo -ne 'original') { return '' }
  $copia = ([string]$T.entradas.copia).Replace('\', '/').TrimEnd('/')
  $frases = @()
  $vistas = @{}
  foreach ($m in [regex]::Matches(($Lineas -join "`n"), $PatronRutaFija)) {
    $ruta = $m.Groups['r'].Value.TrimEnd('.', ',', ';', ':')
    $normal = $ruta.Replace('\', '/')
    if ($vistas.ContainsKey($ruta) -or $normal.Contains('prueba-local') -or $normal.StartsWith($copia + '/')) { continue }
    $vistas[$ruta] = $true
    $sitio = Get-SitioRuta $T.entradas.copia $ruta
    $donde = ''
    if ($sitio) { $donde = " Ese valor esta en $sitio." }
    $frases += "El original usa la ruta fija $ruta ($($m.Groups['c'].Value)), que no es una carpeta del caso. Da a la propiedad que la define una carpeta del caso, como hace el test del migrado (la misma que le da el test del migrado, o un @TempDir), y no dejes esa ruta.$donde"
    if ($frases.Count -ge 2) { break }
  }
  return ($frases -join ' ')
}

# 'fichero:linea (clave)' del primer sitio de los application*.properties, .yml y .yaml de src/main/resources de $Dir (Get-FicherosConSql, por su ruta en orden
# ordinal) donde sale $Ruta o, si no, su carpeta o la de arriba (esas dos solo si les quedan dos tramos o mas, para no dar con una raiz), en cualquiera de sus formas:
# como esta, con / o con \\ (un .properties de Windows). Sin clave, 'fichero:linea'. '' si ninguno la tiene.
function Get-SitioRuta([string]$Dir, [string]$Ruta) {
  $ficheros = Get-FicherosConSql $Dir
  $candidatas = @($Ruta)
  foreach ($i in 1, 2) {
    $corte = [Math]::Max($candidatas[-1].LastIndexOf('/'), $candidatas[-1].LastIndexOf('\'))
    if ($corte -le 0) { break }
    $arriba = $candidatas[-1].Substring(0, $corte)
    if (@($arriba -split '[\\/]' | Where-Object { $_ -and $_ -notmatch '^[A-Za-z]:$' }).Count -lt 2) { break }
    $candidatas += $arriba
  }
  foreach ($c in $candidatas) {
    foreach ($forma in @($c, $c.Replace('\', '/'), $c.Replace('/', '\').Replace('\', '\\'))) {
      foreach ($rel in (Sort-Ordinal @($ficheros.Keys | Where-Object { $_ -match '^src/main/resources/(?:.*/)?application[^/]*\.(?:properties|ya?ml)$' }))) {
        $lineas = [System.IO.File]::ReadAllLines($ficheros[$rel])
        for ($n = 0; $n -lt $lineas.Count; $n++) {
          if (-not $lineas[$n].ToUpperInvariant().Contains($forma.ToUpperInvariant())) { continue }
          $clave = [regex]::Match($lineas[$n], '^\s*([^=:#\s]+)\s*[=:]').Groups[1].Value
          if ($clave) { return "${rel}:$($n + 1) ($clave)" }
          return "${rel}:$($n + 1)"
        }
      }
    }
  }
  return ''
}

# La pista de las columnas que le faltan a la base limpia del test y que usa el codigo, de $Texto (las lineas de un fallo): una frase por columna, hasta 3
# distintas (tabla y columna) y en el orden en que salen, todas en una sola pista. Salen de dos sitios: el error de H2 (Column o Columna "X" not found o
# no encontrada: solo si el codigo de la copia del arnes la usa, con la tabla del SQL de su linea o de la de abajo; sin SQL, 'Una tabla') y el motivo de
# Get-MotivoColumna (el prueba-local.json de un lanzamiento con M62, donde el motivo ya no trae el error). '' si no hay ninguna.
function Get-PistaColumnas($T, [string]$Texto) {
  $hay = @()
  foreach ($m in [regex]::Matches($Texto, $PatronColumnaSinCrear)) {
    $hay += [pscustomobject]@{ indice = $m.Index; tabla = $m.Groups['t'].Value; columna = $m.Groups['c'].Value; sitio = $m.Groups['s'].Value }
  }
  foreach ($m in [regex]::Matches($Texto, $PatronTablaFalta)) {
    if ($m.Groups[1].Value -notmatch '(?i)^columna?$') { continue }
    $columna = ($m.Groups[2].Value -split '\.')[-1]
    $sitio = Get-SitioColumna $T.entradas.copia $columna
    if (-not $sitio) { continue }
    $ini = $Texto.LastIndexOf([char]10, $m.Index) + 1
    $fin = $Texto.IndexOf([char]10, $m.Index)
    if ($fin -ge 0) { $fin = $Texto.IndexOf([char]10, $fin + 1) }
    if ($fin -lt 0) { $fin = $Texto.Length }
    $tabla = [string]@(Get-TablasSql $Texto.Substring($ini, $fin - $ini) | ForEach-Object { $_.tabla })[0]
    $hay += [pscustomobject]@{ indice = $m.Index; tabla = $tabla; columna = $columna; sitio = $sitio }
  }
  $vistas = @{}
  $frases = @()
  foreach ($h in @($hay | Sort-Object indice)) {
    $clave = $h.tabla + '|' + $h.columna.ToUpperInvariant()
    if ($vistas.ContainsKey($clave)) { continue }
    $vistas[$clave] = $true
    $de = 'Una tabla'
    if ($h.tabla) { $de = "La tabla $($h.tabla)" }
    $frases += "$de de la base limpia no tiene la columna $($h.columna), que usa el codigo ($($h.sitio)): anadela en su CREATE TABLE."
    if ($frases.Count -ge 3) { break }
  }
  return ($frases -join ' ')
}

# Los 60 primeros caracteres del CREATE TABLE que H2 rechaza en $Texto ($PatronCreateTabla), o '' si no hay.
function Get-SentenciaCreate([string]$Texto) {
  $m = [regex]::Match($Texto, $PatronCreateTabla)
  if (-not $m.Success) { return '' }
  return $m.Groups['s'].Value.Substring(0, [Math]::Min(60, $m.Groups['s'].Length))
}

# 'El test del original crea mal una tabla: <la sentencia>' si $Texto (el error de un caso en el original) trae el CREATE TABLE que H2 rechaza, y '' si no.
# El caso no tiene la culpa: es el test del original, y se arregla con -RehacerOriginal. Lo usan Get-MotivoBase (un caso que la IA prepara) y Get-Resultado (uno
# hecho de antes cuyo original ya no corre); la cuenta del final de la prueba busca $PrefijoTablaMal.
function Get-MotivoTablaMal([string]$Texto) {
  $sentencia = Get-SentenciaCreate $Texto
  if (-not $sentencia) { return '' }
  return $PrefijoTablaMal + $sentencia
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

# El test de $Lado ('original' o 'migrado') que se va a escribir otra vez no se borra: pasa de prueba-local\arnes\<lado> a prueba-local\arnes-anterior\<lado>,
# pisando el de la vez anterior, y el del original lleva con el su caso vacio (salidas\vacio pasa a salidas\vacio-anterior: el nuevo lo pisa). Sin un test
# guardado (un lanzamiento anterior se corto con el de antes ya movido), no se toca nada: sigue el que hubiera. Apunta en $script:Anteriores si hay un test de
# antes con el que comparar el nuevo (Test-ArnesEscrito) o al que volver (Restore-Anterior).
function Save-Anterior([string]$Lado) {
  $actual = Join-Ruta $Local "arnes/$Lado"
  $anterior = Join-Ruta $Local "arnes-anterior/$Lado"
  if (Test-Path -LiteralPath $actual) {
    Remove-Carpeta $anterior
    Copy-Carpeta $actual $anterior
    if ($Lado -eq 'original') {
      # Un caso vacio guardado antes de M69 no tiene causas.json: se apunta ahora, con el registro de Maven que lo dejo (el mas reciente, mientras el test nuevo no ha corrido)
      $vacio = Join-Ruta $Local 'salidas/vacio'
      if ((Test-Path -LiteralPath $vacio) -and -not (Test-Path -LiteralPath (Join-Path $vacio 'causas.json'))) {
        Save-CausasVacio $vacio @(Get-ChildItem -LiteralPath $vacio -Directory | ForEach-Object { $_.Name }) (Get-CausaRegistroVacio)
      }
      Remove-Carpeta (Join-Ruta $Local 'salidas/vacio-anterior')
      Copy-Carpeta $vacio (Join-Ruta $Local 'salidas/vacio-anterior')
    }
    Remove-Carpeta $actual
  }
  $script:Anteriores[$Lado] = (Test-Path -LiteralPath $anterior)
}

# Vuelve al test de antes del arnes $T (el del original, cuando el nuevo ha quedado peor: Test-ArnesEscrito): arnes-anterior\<lado> vuelve a arnes\<lado> y a la copia de $T,
# y salidas\vacio-anterior a salidas\vacio. Se fia del test de antes sin volver a comprobarlo: el nuevo es el que no valia. Lo compilado del nuevo se borra (target\test-classes):
# el de antes llega con la fecha de cuando se escribio y Maven no veria que hay que compilarlo otra vez.
function Restore-Anterior($T) {
  $lado = $T.entradas.repo
  $dir = $T.entradas.copia
  Remove-Carpeta (Join-Ruta $Local "arnes/$lado")
  Copy-Carpeta (Join-Ruta $Local "arnes-anterior/$lado") (Join-Ruta $Local "arnes/$lado")
  if ($lado -eq 'original') {
    Remove-Carpeta (Join-Ruta $Local 'salidas/vacio')
    Copy-Carpeta (Join-Ruta $Local 'salidas/vacio-anterior') (Join-Ruta $Local 'salidas/vacio')
  }
  Undo-Copia $dir
  Remove-Carpeta (Join-Ruta $dir 'target/test-classes')
  Copy-Carpeta (Join-Ruta $Local "arnes/$lado") $dir
  Save-Copia $dir
}

# Pone en su copia el arnes guardado de otro lanzamiento y le pasa la misma comprobacion que a uno nuevo (el commit puede ser
# otro), antes de llamar a la IA: aunque su tarea no este hecha (la plantilla cambio y con ella la huella, o el reintento quedo
# atascado), un test que sigue valiendo se usa y la tarea queda hecha, sin llamar a Copilot. Si ya no vale, se deshace y se avisa siempre
# (aunque la tarea no estuviera hecha: el usuario puede haberlo arreglado a mano); una tarea hecha vuelve a empezar, una que ya
# estaba por hacer sigue como estaba. Que le falten tablas a su base de prueba no lo
# invalida (un arnes que ya sale todo igual no se rehace por eso): solo se avisa.
function Use-ArnesGuardado($T, [string[]]$Jobs) {
  $estabaHecha = ($T.estado -eq 'hecha')
  Copy-Carpeta (Join-Ruta $Local "arnes/$($T.entradas.repo)") $T.entradas.copia
  $m = Test-Arnes $T $Jobs $true
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
  Aviso "El test PruebaLocalTest del $($T.entradas.repo) de otro lanzamiento ya no vale en este commit ($(($m -split "`n")[0])): se vuelve a escribir."
  if (-not $estabaHecha) { return }
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

# Las tareas de arnes pendientes, una detras de otra: primero la del original y, solo cuando esta hecha, la del migrado (que traduce
# su test: se vuelve a calcular su huella con el test del original que acaba de quedar guardado y su previo lleva las tablas de su base). Cada una con su comprobacion y,
# si falla, su reintento con el motivo. Si la del original queda atascada, la del migrado no se lanza: lo para el arranque.
function Invoke-Arneses($Tareas, [string[]]$Jobs) {
  foreach ($repo in @('original', 'migrado')) {
    foreach ($t in @($Tareas | Where-Object { $_.entradas.repo -eq $repo })) {
      if ($repo -eq 'migrado') {
        if ($ArnesOrig.estado -ne 'hecha') { return }
        # El del original ha vuelto al de antes y el del migrado solo se escribia otra vez porque cambiaba el del original: vuelve tambien al suyo (Use-ArnesGuardado lo
        # comprueba; si ya no vale, se escribe otra vez como siempre)
        if ($script:VueltaAlDeAntes -and $script:MigradoPorOriginal -and (Test-Path -LiteralPath (Join-Ruta $Local 'arnes-anterior/migrado'))) {
          Copy-Carpeta (Join-Ruta $Local 'arnes-anterior/migrado') (Join-Ruta $Local 'arnes/migrado')
          Use-ArnesGuardado $t $Jobs
          if ($t.estado -eq 'hecha') { continue }
        }
        $t.entradas.hashOriginal = Get-HashGuardado 'original' $t.entradas.testOriginal
        $t.entradas.huella = Get-HuellaArnes $t.entradas.test $Jobs $t.entradas.hashOriginal
        # Su primer intento sabe ya que tablas tiene la base del test del original (Test-ArnesEscrito pide las mismas): no se supo hasta que se escribio el del original
        $tablas = @(Get-TablasOriginal $Jobs)
        if ($t.intentos -eq 0 -and $tablas.Count -gt 0) {
          $t.entradas.previo = (@([string]$t.entradas.previo, "La base del test del original tiene estas tablas: $($tablas -join ', '). La base de tu test tiene que tener las mismas, con las mismas columnas.") | Where-Object { $_ }) -join "`n"
        }
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
        if (-not $m) {
          if ($repo -eq 'original' -and $script:VueltaAlDeAntes) { Restore-Anterior $t } else { Save-Arnes $t }
          $t.entradas.plantilla = Get-HashPlantillaArnes   # tambien al volver al de antes: no se escribe otra vez en cada lanzamiento por la plantilla
        }
        elseif (-not $sigue) { Undo-Copia $t.entradas.copia }   # con $sigue, lo escrito se queda: Test-Arnes ya ha deshecho lo de fuera
        $t.entradas.prompt.SI_CORTADO = $MarcaNo
        $t.entradas.prompt.SI_DESHECHO = ''
        if ($sigue) { $t.entradas.prompt.SI_CORTADO = ''; $t.entradas.prompt.SI_DESHECHO = $MarcaNo }
        Set-Intento $t $m
        if ($m) { Aviso "Arnes del $repo rechazado: $(($m -split "`n")[0])" }
        elseif ($repo -eq 'original' -and $script:VueltaAlDeAntes) { $t.motivo = $script:VueltaAlDeAntes; Save-Tarea $t; Aviso $script:VueltaAlDeAntes }
        else { Bien "Arnes del ${repo}: bien." }
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
    # excepcionPedida: ya se le ha dicho a la IA que el job no arrancaba en el original (Invoke-Casos); las tareas de antes no la llevan
    if ($null -eq $t.entradas.PSObject.Properties['excepcionPedida']) { Add-Member -InputObject $t.entradas -NotePropertyName excepcionPedida -NotePropertyValue $false }
    # hashArnesOriginal: el hash del arnes del original con que se hizo un caso no-aplica ('' en los demas y en los hechos antes de M59)
    if ($null -eq $t.entradas.PSObject.Properties['hashArnesOriginal']) { Add-Member -InputObject $t.entradas -NotePropertyName hashArnesOriginal -NotePropertyValue '' }
    $tareas += , (Test-Guardada $t (Join-Ruta $Local "casos/$($Prueba.job)/$caso"))
  }
  return $tareas
}

# Un caso hecho en otro lanzamiento cuyo original dejo estado=EXCEPCION (su salida guardada) y al que nunca se le ha pedido que el job
# arranque vuelve a pendiente con ese motivo: se rehace una vez (Invoke-Casos acepta la segunda), y su original se ejecuta otra vez (se quita su
# entrada de originales.json). Dice cuantos son.
function Reset-CasosExcepcion($Tareas) {
  $n = 0
  foreach ($t in @($Tareas | Where-Object { $_.estado -eq 'hecha' -and -not $_.entradas.excepcionPedida })) {
    $sal = Join-Ruta $Local "salidas/original/$($t.entradas.job)/$($t.entradas.caso)"
    $clase = Get-Excepcion $sal
    if (-not $clase) { continue }
    $guardado = (Get-Originales)["$($t.entradas.job)|$($t.entradas.caso)"]
    $causa = ''
    if ($guardado -and $null -ne $guardado.PSObject.Properties['causa']) { $causa = [string]$guardado.causa }   # la de Maven, guardada con su original (Invoke-Originales)
    $t.estado = 'pendiente'; $t.intentos = 1; $t.ultimoEstado = 'invalida'; $t.motivo = Get-MotivoExcepcion $sal $clase $causa
    $t.entradas.excepcionPedida = $true
    Save-Tarea $t
    (Get-Originales).Remove("$($t.entradas.job)|$($t.entradas.caso)")   # su original se ejecuta otra vez aunque nada de la clave haya cambiado
    $n++
  }
  if ($n -gt 0) { Save-Originales; Info "Se rehacen $n caso(s) hecho(s) en otro lanzamiento: su original no llego a arrancar (estado=EXCEPCION) y nunca se les ha pedido que el job arranque. Se rehacen una vez." }
}

# Un caso hecho en otro lanzamiento cuyo original guardo un error.txt que dice que algo ya existe ($PatronYaExiste: su datos.sql crea una tabla, una secuencia, un indice... que el
# test del original ya crea; ahora el script lo crea con IF NOT EXISTS, Edit-DatosSql) vuelve a ejecutar su original, sin IA y sin -Rehacer: se quita su entrada de originales.json (un original sin
# estado.txt ya se ejecuta en cada lanzamiento; este trae el estado.txt de un job que corrio igualmente). Los demas casos no se tocan. Dice cuantos son.
function Reset-OriginalesYaExiste($Tareas) {
  $o = Get-Originales
  $n = 0
  foreach ($t in @($Tareas | Where-Object { $_.estado -eq 'hecha' })) {
    $j = $t.entradas.job
    $c = $t.entradas.caso
    $dicen = @('original', 'original-2' | Where-Object { $f = Join-Ruta $Local "salidas/$_/$j/$c/error.txt"; (Test-Path -LiteralPath $f) -and [System.IO.File]::ReadAllText($f) -match $PatronYaExiste })
    if ($dicen.Count -eq 0) { continue }
    $o.Remove("$j|$c")
    $n++
  }
  if ($n -gt 0) { Info "Se ejecuta otra vez el original de $n caso(s) hecho(s) en otro lanzamiento: su error.txt dice que algo ya existe (una tabla, una secuencia, un indice...: su datos.sql lo crea y la base del test ya lo tiene)." }
}

# Un caso hecho como no-aplica (sin probar en local: la IA no lo vio correr en el original, por ejemplo por unas tablas que el test no creaba) se decidio con el test
# del original de entonces. Si el que hay ahora es otro (su hash ya no es el que guardo la tarea), vuelve a pendiente con 0 intentos y se prepara otra vez. Uno de antes
# de M59, que no guardo hash, cuenta como de otro test solo si el del original se escribe otra vez en este lanzamiento ($EscribeOriginal). Los casos con entradas no se
# tocan: su original se ejecuta otra vez por la clave de las salidas. Dice cuantos son.
function Reset-CasosSinProbar($Tareas, [bool]$EscribeOriginal) {
  $actual = Get-HashArnesOriginal
  $n = 0
  foreach ($t in @($Tareas | Where-Object { $_.estado -eq 'hecha' -and (Test-Path -LiteralPath (Join-Ruta $Local "casos/$($_.entradas.job)/$($_.entradas.caso)/no-aplica.txt")) })) {
    $antes = [string]$t.entradas.hashArnesOriginal
    if ($antes -ceq $actual -or (-not $antes -and -not $EscribeOriginal)) { continue }
    $t.estado = 'pendiente'; $t.intentos = 0; $t.motivo = ''; $t.ultimoEstado = ''
    $t.entradas.hashArnesOriginal = ''
    Save-Tarea $t
    $n++
  }
  if ($n -gt 0) { Info "$n caso(s) sin probar se vuelven a preparar: el test del original ha cambiado." }
}

# Guarda un caso que ha pasado la comprobacion (en prueba-local\casos\<job>\<caso>); si es no-aplica, lo quita de la
# copia (no se ejecuta).
function Save-Caso($T) {
  $dirCaso = Join-Ruta $CopiaOrig $T.entradas.carpeta
  $dest = Join-Ruta $Local "casos/$($T.entradas.job)/$($T.entradas.caso)"
  Remove-Carpeta $dest
  Copy-Carpeta $dirCaso $dest
  if (Test-Path -LiteralPath (Join-Path $dirCaso 'no-aplica.txt')) {
    $T.entradas.hashArnesOriginal = Get-HashArnesOriginal   # con que test del original se decidio: si cambia, se prepara otra vez (Reset-CasosSinProbar)
    Remove-Carpeta $dirCaso
  }
}

# La tabla de un error de columna ($Texto, el de un caso en el original): la primera del SQL del error que tiene su tablas\<TABLA>.csv en el caso vacio del job
# $Job o, si ninguna, la primera; '' si el error no trae SQL.
function Get-TablaDelError([string]$Texto, [string]$Job) {
  $tablas = @(Get-TablasSql $Texto | ForEach-Object { $_.tabla })
  foreach ($t in $tablas) { if (Test-Path -LiteralPath (Join-Ruta $Local "salidas/vacio/$Job/tablas/$t.csv")) { return $t } }
  if ($tablas.Count -eq 0) { return '' }
  return $tablas[0]
}

# 'El test del original no crea la columna <TABLA>.<COLUMNA> (la usa <fichero:linea>).' si $Texto (el error de un caso en el original) dice que falta una columna
# (Column o Columna "X" not found / no encontrada) y el codigo del original la usa (Get-SitioColumna): el caso no tiene la culpa, es el test del original, y se
# arregla con -RehacerOriginal. Sin la tabla (el error no trae SQL), sale la columna sola. '' si no es eso. Lo usan Get-MotivoBase (un caso que la IA prepara) y
# Get-Resultado (uno hecho de antes cuyo original ya no corre); la cuenta del final de la prueba busca $PrefijoSinColumna.
function Get-MotivoColumna([string]$Texto, [string]$Job) {
  $m = [regex]::Match($Texto, $PatronTablaFalta)
  if (-not $m.Success -or $m.Groups[1].Value -notmatch '(?i)^columna?$') { return '' }
  $nombre = ($m.Groups[2].Value -split '\.')[-1]
  $sitio = Get-SitioColumna $CopiaOrig $nombre
  if (-not $sitio) { return '' }
  $tabla = Get-TablaDelError $Texto $Job
  if ($tabla) { $nombre = "$tabla.$nombre" }
  return "$PrefijoSinColumna$nombre (la usa $sitio)."
}

# Lo que se le dice a la IA de un caso que no corre en el original por la base de prueba: $Texto es su motivo (con el error de Maven o de su
# error.txt) y lleva 'Table "X" not found', 'Tabla "X" no encontrada' o lo mismo con Column o Columna (H2 acaba esa linea con 42102, 42S02,
# 42122 o 42S22, pero sin el nombre no hay nada que decir), o el CREATE TABLE que H2 rechaza. $null si no es eso. Si no, un objeto con el Motivo y si es
# Definitivo (otro intento no lo arregla):
#  - un CREATE TABLE rechazado (Get-MotivoTablaMal): el test del original crea mal una tabla, y la IA de los casos no lo ve ni puede arreglarlo; definitivo;
#  - una tabla del inventario del original (Get-TablasBatch): el test no la crea y la IA no lo ve ni puede crearla; definitivo;
#  - una tabla que el codigo no usa: inventada; la IA la corrige;
#  - una columna que el codigo usa (Get-MotivoColumna): el test del original no la crea, y la IA de los casos no lo ve ni puede crearla; definitivo;
#  - una columna que el codigo no usa: la tabla es la primera del SQL del error que tiene su tablas\<TABLA>.csv en el caso vacio del job (o la primera) y, si esta, se
#    dicen las columnas de su primera linea; la IA la corrige.
function Get-MotivoBase([string]$Texto, [string]$Job) {
  $m = [regex]::Match($Texto, $PatronTablaFalta)
  if (-not $m.Success) {
    $mal = Get-MotivoTablaMal $Texto
    if ($mal) { return [pscustomobject]@{ Motivo = $mal; Definitivo = $true } }
    return $null
  }
  $nombre = ($m.Groups[2].Value -split '\.')[-1]
  if ($m.Groups[1].Value -match '(?i)^(table|tabla)$') {
    $tabla = $nombre.ToUpperInvariant()
    if ($null -eq $script:InventarioOrig) { $script:InventarioOrig = @(Get-TablasBatch $CopiaOrig) }   # una vez por lanzamiento: recorre src/main
    $sitio = @($script:InventarioOrig | Where-Object { $_.tabla -ceq $tabla })
    if ($sitio.Count -gt 0) { return [pscustomobject]@{ Motivo = "$PrefijoSinTabla$tabla (el test no la crea; la usa $($sitio[0].sitio))."; Definitivo = $true } }
    return [pscustomobject]@{ Motivo = "La tabla $tabla no existe en el batch: usa solo tablas que use su codigo."; Definitivo = $false }
  }
  $sinCrear = Get-MotivoColumna $Texto $Job
  if ($sinCrear) { return [pscustomobject]@{ Motivo = $sinCrear; Definitivo = $true } }
  $tabla = Get-TablaDelError $Texto $Job
  if (-not $tabla) { return [pscustomobject]@{ Motivo = "La columna $nombre no existe en la base de prueba."; Definitivo = $false } }
  $frase = "La tabla $tabla no tiene la columna $nombre."
  $csv = Join-Ruta $Local "salidas/vacio/$Job/tablas/$tabla.csv"
  $columnas = @(Get-Columnas $csv)
  if ($columnas.Count -gt 0) { $frase += ' Sus columnas en la base de prueba son: ' + ($columnas -join ', ') + '.' }
  return [pscustomobject]@{ Motivo = $frase; Definitivo = $false }
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
    $sinReintento = @{}   # los casos cuyo motivo la IA no puede arreglar (Get-MotivoBase)
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
      if (-not (Test-Path -LiteralPath (Join-Path $sal 'estado.txt'))) {
        $motivos[$t.id] = 'El caso no corre en el original: ' + (Get-Porque $sal $r)
        $base = Get-MotivoBase $motivos[$t.id] $j
        if ($base) { $motivos[$t.id] = $base.Motivo; $sinReintento[$t.id] = $base.Definitivo }
      }
      else {
        # Un job que no arranca en el original no prueba nada, salvo que sea justo lo que busca el caso: se lo digo una vez (si queda un reintento)
        # y despues se acepta tal cual.
        $clase = Get-Excepcion $sal
        if ($clase) {
          if (-not $t.entradas.excepcionPedida -and ($t.intentos + 1) -lt [int]$Cfg.Intentos) { $motivos[$t.id] = Get-MotivoExcepcion $sal $clase (Get-CausaCorta $r.Causa) }
          $t.entradas.excepcionPedida = $true
        }
      }
    }
    foreach ($t in $lote) {
      $m = $motivos[$t.id]
      if ($m) { Remove-Carpeta (Join-Ruta $CopiaOrig $t.entradas.carpeta); Aviso "$($t.id) rechazado: $(($m -split "`n")[0])" } else { Save-Caso $t }
      Set-Intento $t $m ([bool]$sinReintento[$t.id])
    }
    Save-Copia $CopiaOrig   # los casos buenos de la ronda, por buenos en la copia
  }
}

# ================================ EJECUCION ================================
# El fallo del primero de los casos $Nombres de un job (sus fallos en el migrado, $Fallos, en el mismo orden: Get-FalloLado) si los $CasosParaParar acaban FAILED o EXCEPCION con la
# misma causa (Get-FirmaFallo) y el original de ninguno de ellos falla con ella (si el original falla igual en alguno, es lo que hace ese caso y no una prueba de que el migrado
# este roto: o lo para Invoke-Originales o se ejecutan todos); $null si no.
function Get-ParadaMigrado([string]$Job, [string[]]$Nombres, $Fallos) {
  $firmas = @(0..($Nombres.Count - 1) | ForEach-Object { Get-FirmaFallo $Fallos[$_] $Nombres[$_] })
  if (-not $firmas[0] -or @($firmas | Where-Object { $_ -cne $firmas[0] }).Count -gt 0) { return $null }
  $delOriginal = @(0..($Nombres.Count - 1) | ForEach-Object { Get-FirmaFallo (Get-FalloLado 'original' $Job $Nombres[$_]) $Nombres[$_] })
  if ($delOriginal -ccontains $firmas[0]) { return $null }
  return $Fallos[0]
}

# Ejecuta en una copia los casos de $Listas, uno a uno, y guarda lo que dejan en prueba-local\salidas\<Nombre>\<job>. Con $Limpiar
# en $false no se borra antes lo que ya hubiera en salidas\<Nombre> (-Reparar mide en dos veces lo de un mismo arreglo). De un job del migrado cuyo test se
# acepto con el aviso de que no arranca ($script:NoArranca) se ejecuta solo el primer caso: si acaba EXCEPCION con la misma clase que su caso vacio, los demas
# no se ejecutan y salen sin probar ($script:SinProbar, con $MotivoNoArranca); si arranca, sigue como siempre. Los casos de un job del original que Invoke-Originales dejo
# sin probar ($script:SinProbar['original|job|caso'], con $MotivoNoArrancaOriginal) no se ejecutan en ningun lado.
# En la prueba de siempre (Nombre 'migrado'; no en la busqueda de -Desde ni en -Reparar) la consola dice, en cuanto acaba cada caso, como acaba el migrado y el original
# (Format-VeredictoCaso) y, si los primeros $CasosParaParar casos de un job acaban en el migrado FAILED o EXCEPCION con la misma causa y el original de ninguno falla con ella
# (Get-ParadaMigrado), los demas casos del job no se ejecutan: salen sin probar ($script:SinProbar, con $MotivoMigradoFallaIgual) y el job queda en $script:ParadaMigrado.
function Invoke-Salidas([string]$Dir, [bool]$EsOriginal, [string]$Nombre, $Listas, [bool]$Limpiar = $true) {
  $dest = Join-Ruta $Local "salidas/$Nombre"
  if ($Limpiar) { Remove-Carpeta $dest }
  foreach ($j in @($Listas | ForEach-Object { $_.entradas.job } | Select-Object -Unique)) {
    Info "Ejecutando los casos de $j ($Nombre)..."
    $primero = $true
    $noArranca = $false
    $parada = $false
    $vistos = @()    # los primeros casos del job (hasta $CasosParaParar) y como acabo cada uno en el migrado
    $fallos = @()
    foreach ($t in @($Listas | Where-Object { $_.entradas.job -eq $j })) {
      $c = $t.entradas.caso
      if ($script:SinProbar.ContainsKey("original|$j|$c")) { $script:SinProbar["$Nombre|$j|$c"] = $MotivoNoArrancaOriginal; continue }
      if ($noArranca) { $script:SinProbar["$Nombre|$j|$c"] = $MotivoNoArranca; continue }
      if ($parada) { $script:SinProbar["$Nombre|$j|$c"] = $MotivoMigradoFallaIgual; continue }
      Invoke-SalidaCaso $Dir $EsOriginal $Nombre $j $c
      if ($Nombre -ceq 'migrado') {
        $fallo = Get-FalloLado $Nombre $j $c
        $linea = '  ' + (Format-VeredictoCaso $j $c $fallo)
        if ($fallo) { Aviso $linea } else { Info $linea }
        if ($vistos.Count -lt $CasosParaParar) {
          $vistos += $c
          $fallos += , $fallo
          $primerFallo = $null
          if ($vistos.Count -eq $CasosParaParar) { $primerFallo = Get-ParadaMigrado $j $vistos $fallos }
          if ($primerFallo) {
            $parada = $true
            $script:ParadaMigrado[$j] = $primerFallo
            Aviso "El migrado falla igual en los $CasosParaParar primeros casos del job $j ($(Format-DetalleFallo $primerFallo)): no ejecuto sus demas casos. Arreglalo y relanza (con -Rapida para comprobarlo en minutos)."
          }
        }
      }
      if ($primero -and $Nombre -ceq 'migrado' -and $script:NoArranca.ContainsKey($j)) {
        $noArranca = ((Get-Excepcion (Join-Ruta $Local "salidas/$Nombre/$j/$c")) -ceq $script:NoArranca[$j].clase)
        if ($noArranca) { Info "El migrado no arranca el job $j con este test ($($script:NoArranca[$j].clase)): no ejecuto sus demas casos." }
      }
      $primero = $false
    }
  }
}

# Ejecuta un caso en la copia $Dir y guarda lo que deja en prueba-local\salidas\<Nombre>\<job>\<caso> (con los nombres de Get-RelSalida; lo que no
# se pueda guardar queda en $script:NoGuardados).
function Invoke-SalidaCaso([string]$Dir, [bool]$EsOriginal, [string]$Nombre, [string]$Job, [string]$Caso) {
  $desde = Get-Date
  $script:Maven["$Nombre|$Job|$Caso"] = Invoke-Job $Dir $EsOriginal $Job $Caso "$Nombre $Job $Caso"
  $script:NoGuardados["$Nombre|$Job|$Caso"] = @(Copy-Salida (Join-Ruta $Dir "target/prueba-local/$Job/$Caso") (Join-Ruta $Local "salidas/$Nombre/$Job/$Caso") $Job "$Job/$Caso ($Nombre)" @(Get-Hoy $desde (Get-Date)))
}

# Ejecuta en la copia del migrado, con el arnes que ya lleva, los casos de $Listas (con sus entradas guardadas) y guarda lo que
# dejan en prueba-local\salidas\<Nombre>.
function Invoke-Migrado([string]$Nombre, $Listas) {
  Remove-Carpeta (Join-Ruta $CopiaMig $Casos)
  foreach ($t in $Listas) { Copy-Carpeta (Join-Ruta $Local "casos/$($t.entradas.job)/$($t.entradas.caso)") (Join-Ruta $CopiaMig $t.entradas.carpeta) }
  Invoke-Salidas $CopiaMig $false $Nombre $Listas
}

# ================================ EL ORIGINAL NO SE REPITE ================================
# Las salidas del original y del original-2 de un caso (prueba-local\salidas\original y \original-2) se guardan con la clave de lo que entro en su
# ejecucion y los dias en que se ejecuto, en prueba-local\salidas\originales.json. Un lanzamiento con la misma clave no vuelve a ejecutarlas
# (como la cache de acciones de Bazel o Gradle: la clave es el contenido de todo lo que puede cambiar la salida). El migrado se ejecuta siempre.
# LO QUE INVALIDA LA REUTILIZACION (lo que lleva la clave; todo lo que llega a la linea de Maven del original, Invoke-MavenCaso):
#  - $HeadOrig, el commit del original (su codigo, su pom.xml, sus recursos y su .mvn);
#  - el arnes guardado del original (todos los ficheros de prueba-local\arnes\original: el test PruebaLocalTest y lo que cambia del pom.xml);
#  - las entradas del caso: toda su carpeta en la copia del original (parametros, ficheros\entrada, datos.sql...);
#  - el formato de lo que se guarda en salidas ($VersionSalidas) y la longitud de la ruta de prueba-local (los nombres de Get-RelSalida dependen de ella);
#  - el JDK del original: -JavaLegacy o, sin el, JAVA_HOME, y el fichero release de esa carpeta (otra version en la misma ruta);
#  - lo que dice 'mvn -v' (Maven, Java y la configuracion regional: cubre el mvnw con otro Maven y el java del PATH);
#  - el Maven que se lanza (Get-Mvn: -MvnExe, mvnw o mvn) y $Cfg.MavenCasoRapido (las propiedades de cada caso);
#  - las variables de entorno que Maven y la JVM leen (Get-EntornoMaven) y la codificacion con que se ejecuta el original ($OpcionJvmOriginal): lo guardado
#    de antes de ponerla es de un original que leia con la codificacion del sistema;
#  - que falte lo guardado: la carpeta del caso en salidas\original o en salidas\original-2, o su estado.txt (borrar prueba-local\salidas lo repite
#    todo), o que el original dejara estado=EXCEPCION y el caso vuelva a pendiente (Reset-CasosExcepcion).
# NO lleva, y no se ve: ~/.m2/settings.xml, los jar de ~/.m2 (un SNAPSHOT que cambia) ni lo que hay fuera (base de datos, SFTP, correo: simulado).
# NO lleva $Cfg.MavenCasoDirecto: con mvn surefire:test (sobre lo que Invoke-Compilar compilo con el mismo codigo, pom.xml y propiedades de MavenCasoRapido) corre la
# misma clase PruebaLocalTest, con las mismas entradas y en una JVM nueva por caso, que con mvn test; las salidas guardadas con el ciclo entero siguen valiendo.
# Un original que no llega a dejar estado.txt, o que se pasa del tope de Maven, o con un fichero que no se pudo guardar en salidas (Copy-Salida), no
# se guarda: se ejecuta en el siguiente lanzamiento. Con cada original se guarda la causa de su Maven (la de un job que no arranca o que falla: Get-CausaLado).
# $VersionSalidas (la version del formato de lo que se guarda en salidas) y la longitud de la ruta de prueba-local (cambia los nombres de Get-RelSalida)
# van en la clave: lo guardado con otro formato o en otra carpeta se ejecuta otra vez.
# LAS FECHAS: la salida de un original de otro dia lleva la fecha de su ejecucion. Con la salida se guardan los dias de su ejecucion (desde antes
# del primer Maven del caso hasta despues del ultimo, Get-Hoy) y Get-Resultado normaliza cada lado con los suyos (Get-DiasOriginal para el
# original, $Hoy para el migrado): una fecha de la ejecucion del original sigue siendo 'de la ejecucion', y un migrado que escribe una fecha
# de otro dia (la del original, si no es hoy) sale distinto, que es lo que es. Lo que no se puede normalizar (un valor que sale de la fecha, como
# los dias de retraso, o un formato de fecha que Get-Normal no conoce) saldria distinto sin serlo: un caso distinto cuyo original es de otro
# dia se confirma ejecutando el original otra vez (Confirm-OriginalesDeOtroDia) y comparando con lo nuevo.

# El hash (SHA-256, en hexadecimal) de unos bytes.
function Get-Hash256([byte[]]$Bytes) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { $b = $sha.ComputeHash($Bytes) } finally { $sha.Dispose() }
  return ((@($b) | ForEach-Object { $_.ToString('x2') }) -join '')
}

# El hash de lo que hay en una carpeta: cada fichero con su contenido y cada carpeta (una carpeta vacia tambien cambia lo que ve el job), por su
# ruta relativa y en orden. '' si la carpeta no esta.
function Get-HashCarpeta([string]$Dir) {
  if (-not (Test-Path -LiteralPath $Dir)) { return '' }
  $l = @(Get-ChildItem -LiteralPath $Dir -Recurse | ForEach-Object {
      $rel = Get-Rel $Dir $_.FullName
      if ($_.PSIsContainer) { $rel + '/' } else { $rel + '=' + (Get-Hash256 ([System.IO.File]::ReadAllBytes($_.FullName))) }
    })
  return (Get-Hash256 ($Utf8.GetBytes((Sort-Ordinal $l) -join "`n")))
}

# Las variables de entorno que leen Maven y la JVM (opciones, argumentos, zona horaria): cambian lo que sale del original, y la clave las lleva.
function Get-EntornoMaven {
  return @('MAVEN_OPTS', 'MAVEN_ARGS', 'MAVEN_CONFIG', 'JAVA_TOOL_OPTIONS', 'JDK_JAVA_OPTIONS', '_JAVA_OPTIONS', 'TZ' | ForEach-Object { $_ + '=' + [Environment]::GetEnvironmentVariable($_) })
}

# El hash de lo que hay guardado del arnes del original (su test y lo que cambia del pom.xml): lo lleva la clave del original y cada caso sin probar,
# que se decidio con el test de entonces.
function Get-HashArnesOriginal { return (Get-HashCarpeta (Join-Ruta $Local 'arnes/original')) }

# Lo que entra en la ejecucion del original y es igual para todos sus casos (ver arriba), en un hash. Lanza un 'mvn -v' en la copia del original.
function Get-ClaveBaseOriginal {
  $v = Invoke-Maven $CopiaOrig $true @('-v') 'la version de Maven y de Java del original'
  $jdk = $JavaLegacy
  if (-not $jdk) { $jdk = $env:JAVA_HOME }
  $release = ''
  if ($jdk -and (Test-Path -LiteralPath (Join-Path $jdk 'release'))) { $release = [System.IO.File]::ReadAllText((Join-Path $jdk 'release')) }
  $partes = @($HeadOrig, (Get-HashArnesOriginal), [string]$jdk, $release, (Get-Mvn $CopiaOrig), ($Cfg.MavenCasoRapido -join ' '))
  $partes += @($v.Salida | Where-Object { $_ -cmatch '^(Apache Maven|Maven home|Java version|Default locale)' })
  $partes += Get-EntornoMaven
  $partes += "jvm-original=$OpcionJvmOriginal"
  $partes += @("salidas-v$VersionSalidas", "ruta-local=$($Local.Length)/$LimiteRuta")   # el formato de los nombres de salidas (Get-RelSalida) y lo que lo decide
  return (Get-Hash256 ($Utf8.GetBytes($partes -join "`n")))
}

# Lo guardado de los originales: 'job|caso' -> clave y dias (prueba-local\salidas\originales.json), leido una vez por lanzamiento. Un fichero que no
# se lee es como si no estuviera: nada se reutiliza.
function Get-Originales {
  if ($null -eq $script:Originales) {
    $script:Originales = New-Object System.Collections.Hashtable ([System.StringComparer]::Ordinal)
    $f = Join-Ruta $Local 'salidas/originales.json'
    if (Test-Path -LiteralPath $f) {
      try { foreach ($e in @((Read-Json $f).casos)) { $script:Originales["$($e.job)|$($e.caso)"] = $e } }
      catch { $script:Originales.Clear() }
    }
  }
  return $script:Originales
}

function Save-Originales {
  $o = Get-Originales
  Write-Json (Join-Ruta $Local 'salidas/originales.json') ([ordered]@{ version = 1; casos = @(Sort-Ordinal @($o.Keys) | ForEach-Object { $o[$_] }) })
}

# Los dias en que se ejecuto el original de un caso (Get-Hoy de su ejecucion), o $null si no se sabe (con $null, Get-Normal usa los de hoy).
function Get-DiasOriginal([string]$Job, [string]$Caso) {
  $e = (Get-Originales)["$Job|$Caso"]
  if (-not $e) { return $null }
  return @($e.dias | ForEach-Object { [datetime]::ParseExact([string]$_, 'yyyy-MM-dd', $Inv) })
}

# Ejecuta el original y el original-2 de los casos de $Listas que no tienen guardado lo mismo (clave y carpetas, ver arriba), uno detras de otro:
# cada caso queda guardado en cuanto acaba, y un corte no pierde lo que ya estaba hecho. Dice cuantos casos se reutilizan y cuantos se ejecutan.
# Con $Parar, si los primeros $CasosParaParar casos de un job (se hayan ejecutado ahora o se reutilicen) acaban en el original FAILED o EXCEPCION con la misma causa
# (Get-FirmaFallo), los demas casos del job no se ejecutan: el original funciona en produccion, asi que si falla igual en todos es su test, no su codigo. Salen sin
# probar ($script:SinProbar con el lado 'original', que Invoke-Salidas respeta tambien en el migrado y Get-Resultado cuenta, con $MotivoNoArrancaOriginal) y el job
# queda en $script:ParadaOriginal (el fallo del primero de los casos). Un job de menos de $CasosParaParar casos no se para. Confirm-OriginalesDeOtroDia repite
# unos pocos casos de varios jobs: ahi no se para ($Parar en $false).
function Invoke-Originales($Listas, [bool]$Parar = $true) {
  $o = Get-Originales
  $base = Get-ClaveBaseOriginal
  $claves = @{}
  $ejecutar = @()
  foreach ($t in $Listas) {
    $j = $t.entradas.job; $c = $t.entradas.caso
    $claves["$j|$c"] = Get-Hash256 ($Utf8.GetBytes($base + "`n" + (Get-HashCarpeta (Join-Ruta $CopiaOrig $t.entradas.carpeta))))
    $hecho = @('original', 'original-2' | Where-Object { Test-Path -LiteralPath (Join-Ruta $Local "salidas/$_/$j/$c/estado.txt") }).Count -eq 2
    if (-not ($hecho -and $o["$j|$c"] -and $o["$j|$c"].clave -ceq $claves["$j|$c"])) { $ejecutar += $t }
  }
  Info "Original: se reutilizan las salidas de $($Listas.Count - $ejecutar.Count) caso(s) y se ejecutan $($ejecutar.Count)."
  if ($ejecutar.Count -eq 0) { return }
  # Lo que se va a ejecutar deja de estar guardado antes de empezar: un corte en medio no deja una clave que ya no es de lo que hay.
  foreach ($t in $ejecutar) {
    $o.Remove("$($t.entradas.job)|$($t.entradas.caso)")
    foreach ($n in @('original', 'original-2')) { Remove-Carpeta (Join-Ruta $Local "salidas/$n/$($t.entradas.job)/$($t.entradas.caso)") }
  }
  Save-Originales
  foreach ($j in @($ejecutar | ForEach-Object { $_.entradas.job } | Select-Object -Unique)) {
    Info "Ejecutando los casos de $j (original y original-2)..."
    $firmas = @()
    $primero = $null
    $parada = $false
    foreach ($t in @($Listas | Where-Object { $_.entradas.job -eq $j })) {
      $c = $t.entradas.caso
      $nuevo = ($ejecutar -contains $t)
      if ($parada) {
        if ($nuevo) { $script:SinProbar["original|$j|$c"] = $MotivoNoArrancaOriginal }
        continue
      }
      if ($nuevo) {
        $desde = Get-Date
        foreach ($n in @('original', 'original-2')) { Invoke-SalidaCaso $CopiaOrig $true $n $j $c }
        $completo = @('original', 'original-2' | Where-Object { -not $script:Maven["$_|$j|$c"].Tope -and (Test-Path -LiteralPath (Join-Ruta $Local "salidas/$_/$j/$c/estado.txt")) }).Count -eq 2
        # Un caso con un fichero que no se pudo guardar no queda reutilizable: se ejecuta otra vez en el siguiente lanzamiento
        if (@('original', 'original-2' | Where-Object { @(Get-NoGuardados $_ $j $c).Count -gt 0 }).Count -gt 0) { $completo = $false }
        if ($completo) {
          $causa = Get-CausaCorta $script:Maven["original|$j|$c"].Causa
          if (-not $causa) { $causa = Get-CausaCorta $script:Maven["original-2|$j|$c"].Causa }
          $o["$j|$c"] = [pscustomobject][ordered]@{ job = $j; caso = $c; clave = $claves["$j|$c"]; dias = @(Get-Hoy $desde (Get-Date) | ForEach-Object { $_.ToString('yyyy-MM-dd', $Inv) }); causa = $causa }
          Save-Originales
        }
      }
      if ($Parar -and $firmas.Count -lt $CasosParaParar) {
        $f = Get-FalloOriginal $j $c
        if ($firmas.Count -eq 0) { $primero = $f }
        $firmas += (Get-FirmaFallo $f $c)
        if ($firmas.Count -eq $CasosParaParar -and $firmas[0] -and @($firmas | Where-Object { $_ -cne $firmas[0] }).Count -eq 0) {
          $parada = $true
          $script:ParadaOriginal[$j] = $primero
          Info (Format-ParadaOriginal $j $primero)
        }
      }
    }
  }
}

# Lo que dice la consola cuando el original del job $Job falla igual en los primeros casos (el fallo $F del primero) y deja de ejecutar los demas.
function Format-ParadaOriginal([string]$Job, $F) {
  if (Test-FalloArranque $F) { return "El original no arranca el job $Job con este test ($(Get-ClaseFallo $F)): no ejecuto sus demas casos." }
  return "El original falla igual en los $CasosParaParar primeros casos del job $Job con este test ($($F.estado)): no ejecuto sus demas casos."
}

# Los casos de $Tareas que salen distintos ($Res, uno por tarea, en el mismo orden) con un original de otro dia (alguno de sus dias no es de hoy): su
# original se ejecuta otra vez y se comparan de nuevo. Un valor que sale de la fecha de la ejecucion (los dias de retraso, un formato de fecha que
# Get-Normal no conoce) sale distinto de un original de otro dia sin que el migrado haya hecho nada mal: con el original de hoy se ve si lo es.
# Devuelve $Res con esos casos al dia.
function Confirm-OriginalesDeOtroDia($Tareas, $Res) {
  $dudosos = @()
  for ($i = 0; $i -lt $Tareas.Count; $i++) {
    $dias = @(Get-DiasOriginal $Tareas[$i].entradas.job $Tareas[$i].entradas.caso)
    if ($Res[$i].resultado -eq 'distinto' -and @($dias | Where-Object { $_ -and $Hoy -notcontains $_ }).Count -gt 0) { $dudosos += $i }
  }
  if ($dudosos.Count -eq 0) { return $Res }
  Info "Original de otro dia: $($dudosos.Count) caso(s) sale(n) distinto(s); los ejecuto otra vez para confirmarlo."
  $o = Get-Originales
  foreach ($i in $dudosos) { $o.Remove("$($Tareas[$i].entradas.job)|$($Tareas[$i].entradas.caso)") }
  Invoke-Originales @($dudosos | ForEach-Object { $Tareas[$_] }) $false
  foreach ($i in $dudosos) { $Res[$i] = Get-Resultado $Tareas[$i] }
  return $Res
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

# Un texto sin lo que cambia de una ejecucion a otra ni de una copia a otra, en el contenido de un fichero y en su ruta (la clave con la que se emparejan los
# ficheros de los dos lados es la ruta normalizada, Compare-Caso): la ruta de cada copia (<copia>); una marca de tiempo Unix de un dia de la ejecucion (10 cifras en segundos o
# 13 en milisegundos, en UTC o en hora local: <hora>; un numero de 10 o 13 cifras de otro dia, no); la fecha de hoy en cada formato (<hoy:formato>: cada formato con su marca,
# un cambio de formato se sigue viendo) y, si lleva detras una hora HH?mm?ss (el separador de las horas, de los minutos y de los segundos, el mismo: - _ . : o ninguno; entre la
# fecha y la hora, - _ . : T, una coma o un espacio, o nada; con fraccion .123 ,123 -123 o 123 pegada), <hoy:formato><hora> (HH:mm sin segundos tambien, solo con dos puntos);
# las horas sueltas (HH:mm:ss y sus fracciones, sin una fecha de otro dia delante) pasan a <hora>. Una fecha con hora que no es de $Dias es un dato del negocio y se queda
# como esta, hora incluida: si el migrado la cambia (otra zona horaria, un dia de mas), sale distinta. Los formatos de fecha no son los de texto (Nov 22, 2026) ni los de dos
# cifras de anio. $Dias son los dias de la ejecucion que dejo ese texto (por defecto, $Hoy): el original de otro dia se normaliza con los suyos (Get-DiasOriginal).
function Get-Normal([string]$Texto, $Dias = $null) {
  if ($null -eq $Dias) { $Dias = $Hoy }
  $t = $Texto
  foreach ($r in $RutasCopia) { $t = $t.Replace($r, '<copia>') }
  $ticks = @($Dias | ForEach-Object { $_.Date.Ticks })
  $epoca = New-Object System.DateTime 1970, 1, 1, 0, 0, 0, ([System.DateTimeKind]::Utc)
  $marcas = [regex]::Matches($t, '(?<![\d.])\d{10}(?:\d{3})?(?!\d)')
  for ($i = $marcas.Count - 1; $i -ge 0; $i--) {
    $segundos = [double]$marcas[$i].Value
    if ($marcas[$i].Length -eq 13) { $segundos = [Math]::Floor($segundos / 1000) }
    $utc = $epoca.AddSeconds($segundos)
    if ($ticks -contains $utc.Date.Ticks -or $ticks -contains $utc.ToLocalTime().Date.Ticks) { $t = $t.Remove($marcas[$i].Index, $marcas[$i].Length).Insert($marcas[$i].Index, '<hora>') }
  }
  $h = '(?:[01]\d|2[0-3])'
  $m = '[0-5]\d'
  $hora = '(?:' + $h + '(?<s>[-_.:])' + $m + '\k<s>' + $m + '(?:[.,]\d+|[-_]\d{3}(?!\d))?|' + $h + $m + $m + '(?:\d{3})?(?!\d)|' + $h + ':' + $m + '(?![\d:]))'
  foreach ($d in $Dias) {
    foreach ($f in @('yyyy-MM-dd', 'dd/MM/yyyy', 'yyyyMMdd', 'ddMMyyyy', 'yyyy_MM_dd', 'yyyy/MM/dd', 'dd-MM-yyyy', 'dd.MM.yyyy', 'yyyy.MM.dd', 'dd_MM_yyyy', 'MM/dd/yyyy', 'MM-dd-yyyy')) {
      $fecha = $d.ToString($f, $Inv)
      if (-not $t.Contains($fecha)) { continue }
      $t = [regex]::Replace($t, [regex]::Escape($fecha) + '(?:[Tt_\-.:]|,?[ ]+)?' + $hora, "<hoy:$f><hora>")
      $t = $t.Replace($fecha, "<hoy:$f>")
    }
  }
  return ($t -replace '(?<!\d{4}[-/._]\d{2}[-/._]\d{2}[ Tt]|\d{2}[-/._]\d{2}[-/._]\d{4}[ Tt])\b\d{2}:\d{2}:\d{2}(\.\d+)?\b', '<hora>')
}

# El tipo de un contenido ($Bytes, de un fichero o de una entrada con el nombre $Nombre): xlsx (un zip con extension .xlsx o .xlsm), zip (los demas: .zip, .docx, .jar...), gz,
# pdf, binario (un byte 0 en los primeros 8 KB, o una extension de las que son siempre binarias) o texto. El tipo se decide por los bytes y la extension, no por si se
# lee bien: un libro roto sigue siendo xlsx y Get-LineasContenido decide que hace con el.
function Get-TipoContenido([string]$Nombre, [byte[]]$Bytes) {
  $n = $Bytes.Length
  if ($n -ge 4 -and $Bytes[0] -eq 0x50 -and $Bytes[1] -eq 0x4B -and (($Bytes[2] -eq 3 -and $Bytes[3] -eq 4) -or ($Bytes[2] -eq 5 -and $Bytes[3] -eq 6))) {
    if (@('.xlsx', '.xlsm') -contains [System.IO.Path]::GetExtension($Nombre).ToLowerInvariant()) { return 'xlsx' }
    return 'zip'
  }
  if ($n -ge 2 -and $Bytes[0] -eq 0x1F -and $Bytes[1] -eq 0x8B) { return 'gz' }
  if ($n -ge 5 -and $Latin.GetString($Bytes, 0, 5) -ceq '%PDF-') { return 'pdf' }
  $binarias = @('.pdf', '.png', '.jpg', '.jpeg', '.gif', '.bmp', '.ico', '.tif', '.tiff', '.webp', '.class', '.xls', '.doc', '.ppt', '.7z', '.rar', '.tar', '.bz2', '.xz', '.so', '.dll', '.exe', '.ser', '.mp3', '.mp4', '.wav', '.avi', '.mov', '.woff', '.woff2', '.ttf', '.otf', '.p12', '.pfx', '.jks')
  if ($binarias -contains [System.IO.Path]::GetExtension($Nombre).ToLowerInvariant()) { return 'binario' }
  if ([System.Array]::IndexOf($Bytes, [byte]0, 0, [Math]::Min($n, 8192)) -ge 0) { return 'binario' }
  return 'texto'
}

# La linea de un binario: binario: <n> bytes, sha256 <hash>. Dos binarios son iguales si sus bytes lo son. Un PDF generado lleva dentro su fecha de creacion y de
# modificacion y un identificador distinto en cada ejecucion: sin comprimir (los de un PDF antiguo o simple; en un PDF con objetos comprimidos no se ven), /CreationDate,
# /ModDate, /ID y las fechas y ids del XMP se sustituyen por un valor fijo del mismo largo antes de contar y de sacar el hash (con $Crudo, no).
function Get-LineaBinaria([byte[]]$Bytes, [bool]$Crudo = $false) {
  $b = $Bytes
  if (-not $Crudo -and $b.Length -ge 5 -and $Latin.GetString($b, 0, 5) -ceq '%PDF-') {
    $t = $Latin.GetString($b)
    $t = [regex]::Replace($t, '/(CreationDate|ModDate)\s*\(D:[^)]*\)', [System.Text.RegularExpressions.MatchEvaluator]{ param($m) '/' + $m.Groups[1].Value + ' (D:' + ('0' * 14) + ')' })
    $t = [regex]::Replace($t, '/ID\s*\[\s*<[0-9A-Fa-f]*>\s*<[0-9A-Fa-f]*>\s*\]', '/ID [<00><00>]')
    $t = [regex]::Replace($t, '(<(?:xmp|pdf|xmpMM):(?:CreateDate|ModifyDate|MetadataDate)>)[^<]*', '$1')
    $t = [regex]::Replace($t, '(?i)uuid:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', 'uuid:00000000-0000-0000-0000-000000000000')
    $b = $Latin.GetBytes($t)
  }
  return ('binario: ' + $b.Length + ' bytes, sha256 ' + (Get-Hash256 $b))
}

# Un .xlsx o .xlsm leido sin Excel (ECMA-376: xl/workbook.xml con las hojas, xl/_rels/workbook.xml.rels con el fichero de cada una, xl/sharedStrings.xml con los textos y
# xl/worksheets/*.xml con las celdas <c r= t=> con <v>, <is> o <f>): una linea por celda con valor, '<hoja>!<celda>: <valor>', las hojas en su orden y las celdas en el del fichero.
# Una formula sale como =<formula> y su ultimo valor (-> valor). Un numero que es una fecha de Excel de uno de los $Dias (sin tener en cuenta la hora) sale <hoy:excel><hora>
# si lleva fraccion de dia y <hoy:excel> si no, y el resto de valores pasan por Get-Normal; las fechas y estilos de docProps/ y xl/styles.xml no cuentan. Un salto de linea dentro
# de un valor sale como \n. Con $Crudo, sin normalizar nada (ni las fechas de Excel ni Get-Normal). Lanza una excepcion si no es un libro que se pueda leer.
function Get-LineasExcel([byte[]]$Bytes, $Dias = $null, [bool]$Crudo = $false) {
  if ($null -eq $Dias) { $Dias = $Hoy }
  Add-Type -AssemblyName System.IO.Compression
  $nsR = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
  $inv = [System.Globalization.CultureInfo]::InvariantCulture
  $ticks = @($Dias | ForEach-Object { $_.Date.Ticks })
  $zip = New-Object System.IO.Compression.ZipArchive((New-Object System.IO.MemoryStream (, $Bytes)), [System.IO.Compression.ZipArchiveMode]::Read)
  try {
    $abre = {
      param([string]$Parte)
      $e = $zip.GetEntry($Parte)
      if ($null -eq $e) { return $null }
      $cfg = New-Object System.Xml.XmlReaderSettings
      $cfg.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
      $cfg.XmlResolver = $null
      $cfg.CloseInput = $true
      $lector = [System.Xml.XmlReader]::Create($e.Open(), $cfg)
      try { $d = New-Object System.Xml.XmlDocument; $d.XmlResolver = $null; $d.Load($lector); return $d } finally { $lector.Dispose() }
    }
    $texto = {
      param($Nodo)
      $s = ''
      foreach ($h in $Nodo.ChildNodes) {
        if ($h.LocalName -ceq 't') { $s += $h.InnerText }
        elseif ($h.LocalName -ceq 'r') { foreach ($t in $h.ChildNodes) { if ($t.LocalName -ceq 't') { $s += $t.InnerText } } }
      }
      return $s
    }
    $libro = & $abre 'xl/workbook.xml'
    if ($null -eq $libro) { throw 'no hay xl/workbook.xml' }
    $base = [datetime]'1899-12-30'
    foreach ($p in $libro.GetElementsByTagName('workbookPr', '*')) { if (@('1', 'true') -contains $p.GetAttribute('date1904')) { $base = [datetime]'1904-01-01' } }
    $destinos = @{}
    $rels = & $abre 'xl/_rels/workbook.xml.rels'
    if ($rels) { foreach ($n in $rels.GetElementsByTagName('Relationship', '*')) { $destinos[$n.GetAttribute('Id')] = $n.GetAttribute('Target') } }
    $comp = New-Object 'System.Collections.Generic.List[string]'
    $ss = & $abre 'xl/sharedStrings.xml'
    if ($ss) { foreach ($si in $ss.GetElementsByTagName('si', '*')) { $comp.Add((& $texto $si)) } }
    $lineas = New-Object 'System.Collections.Generic.List[string]'
    foreach ($h in $libro.GetElementsByTagName('sheet', '*')) {
      $dest = [string]$destinos[$h.GetAttribute('id', $nsR)]
      if (-not $dest) { continue }
      $parte = 'xl/' + $dest
      if ($dest.StartsWith('/')) { $parte = $dest.TrimStart('/') }
      $hoja = & $abre $parte
      if ($null -eq $hoja) { continue }
      $nombre = $h.GetAttribute('name')
      foreach ($c in $hoja.GetElementsByTagName('c', '*')) {
        $tipo = $c.GetAttribute('t')
        $v = $null; $f = ''; $dentro = $null
        foreach ($x in $c.ChildNodes) {
          if ($x.LocalName -ceq 'v') { $v = $x.InnerText } elseif ($x.LocalName -ceq 'f') { $f = $x.InnerText } elseif ($x.LocalName -ceq 'is') { $dentro = & $texto $x }
        }
        $valor = $v
        $i = 0
        if ($tipo -ceq 's' -and $null -ne $v -and [int]::TryParse($v, [ref]$i) -and $i -ge 0 -and $i -lt $comp.Count) { $valor = $comp[$i] }
        elseif ($tipo -ceq 'inlineStr') { $valor = $dentro }
        elseif ($tipo -ceq 'b') { if ($v -ceq '1') { $valor = 'TRUE' } elseif ($v -ceq '0') { $valor = 'FALSE' } }
        elseif ((-not $tipo -or $tipo -ceq 'n') -and -not $Crudo) {
          $num = 0.0
          if ($null -ne $v -and [double]::TryParse($v, [System.Globalization.NumberStyles]::Float, $inv, [ref]$num) -and $num -ge 1 -and $num -lt 2958466) {
            $dia = [Math]::Floor($num)
            if ($ticks -contains $base.AddDays($dia).Ticks) { if ($num -gt $dia) { $valor = '<hoy:excel><hora>' } else { $valor = '<hoy:excel>' } }
          }
        }
        if ($f) { $valor = '=' + $f + $(if ($valor) { ' -> ' + $valor } else { '' }) }
        if (-not $valor) { continue }
        $lineas.Add($nombre + '!' + $c.GetAttribute('r') + ': ' + ($valor -replace "\r\n|\r|\n", '\n'))
      }
    }
  } finally { $zip.Dispose() }
  if ($lineas.Count -eq 0) { return @() }
  # Una sola pasada de Get-Normal para todas las lineas (sin saltos dentro de una linea, nada cruza de una a otra), en la forma de los ficheros: bytes UTF-8 vistos como Latin-1.
  $todo = $Latin.GetString($Utf8.GetBytes(($lineas -join "`n")))
  if (-not $Crudo) { $todo = Get-Normal $todo $Dias }
  return @($todo -split "`n")
}

# Las lineas de un zip o de un docx, jar...: una por linea de cada entrada (las carpetas no cuentan) con el nombre de la entrada, normalizado, delante, y las entradas en el orden de
# ese nombre (un zip con las mismas entradas en otro orden es el mismo contenido). Cada entrada se lee segun su tipo (Get-LineasContenido): texto, un libro, otro zip (hasta
# 3 niveles) o un binario. Una entrada vacia sale como '<nombre>: (vacio)' para que sobre o falte. Con $Crudo, sin normalizar nada. Lanza una excepcion si no se puede abrir.
function Get-LineasZip([byte[]]$Bytes, $Dias = $null, [int]$Nivel = 0, [bool]$Crudo = $false) {
  Add-Type -AssemblyName System.IO.Compression
  $zip = New-Object System.IO.Compression.ZipArchive((New-Object System.IO.MemoryStream (, $Bytes)), [System.IO.Compression.ZipArchiveMode]::Read)
  $claves = New-Object 'System.Collections.Generic.List[string]'
  $trozos = New-Object 'System.Collections.Generic.List[object]'
  try {
    foreach ($e in $zip.Entries) {
      if ($e.FullName.EndsWith('/')) { continue }
      $ms = New-Object System.IO.MemoryStream
      $s = $e.Open()
      try { $s.CopyTo($ms) } finally { $s.Dispose() }
      $nombre = $Latin.GetString($Utf8.GetBytes($e.FullName))
      if (-not $Crudo) { $nombre = Get-Normal $nombre $Dias }
      $l = @(Get-LineasContenido $e.FullName $ms.ToArray() $Dias ($Nivel + 1) $Crudo)
      if ($l.Count -eq 0) { $l = @('(vacio)') }
      $claves.Add($nombre + [char]0 + $trozos.Count.ToString('D6'))
      $trozos.Add(@($l | ForEach-Object { $nombre + ': ' + $_ }))
    }
  } finally { $zip.Dispose() }
  $k = $claves.ToArray()
  $orden = New-Object 'int[]' $k.Length
  for ($i = 0; $i -lt $k.Length; $i++) { $orden[$i] = $i }
  [System.Array]::Sort($k, $orden, [System.StringComparer]::Ordinal)
  $todo = @()
  foreach ($i in $orden) { $todo += @($trozos[$i]) }
  return $todo
}

# Las lineas de un contenido ya leido ($Bytes de un fichero o de una entrada con el nombre $Nombre), segun su tipo (Get-TipoContenido): un libro de Excel, una linea por celda
# (Get-LineasExcel); un zip o un gz, las de lo que lleva dentro, cada entrada con su nombre (Get-LineasZip; un gz lleva el nombre del fichero sin .gz); un binario (y un
# libro o un zip que no se pueden abrir), la linea binario: <n> bytes, sha256 <hash> (Get-LineaBinaria); un texto, sus lineas normalizadas (Get-Normal; los saltos \r\n cuentan
# como \n y el ultimo salto no cuenta como linea; se leen byte a byte, Latin-1: dos ficheros solo son iguales si sus bytes lo son, este en la codificacion que este). Con $Crudo, sin
# normalizar nada: las mismas lineas tal cual salen (Get-MotivoCambiante, de regresion.ps1, compara las dos para saber si el contenido lleva algo de esta ejecucion).
function Get-LineasContenido([string]$Nombre, [byte[]]$Bytes, $Dias = $null, [int]$Nivel = 0, [bool]$Crudo = $false) {
  $tipo = Get-TipoContenido $Nombre $Bytes
  if ($Nivel -ge 3 -and (@('xlsx', 'zip', 'gz') -contains $tipo)) { return @(Get-LineaBinaria $Bytes $Crudo) }
  if ($tipo -ceq 'xlsx') {
    try { return @(Get-LineasExcel $Bytes $Dias $Crudo) } catch { $tipo = 'zip' }
  }
  if ($tipo -ceq 'zip') {
    try { return @(Get-LineasZip $Bytes $Dias $Nivel $Crudo) } catch { return @(Get-LineaBinaria $Bytes $Crudo) }
  }
  if ($tipo -ceq 'gz') {
    try {
      $ms = New-Object System.IO.MemoryStream
      $g = New-Object System.IO.Compression.GZipStream((New-Object System.IO.MemoryStream (, $Bytes)), [System.IO.Compression.CompressionMode]::Decompress)
      try { $g.CopyTo($ms) } finally { $g.Dispose() }
      $dentro = [System.IO.Path]::GetFileName($Nombre) -replace '(?i)\.gz$', ''
      $l = @(Get-LineasContenido $dentro $ms.ToArray() $Dias ($Nivel + 1) $Crudo)
      if ($l.Count -eq 0) { $l = @('(vacio)') }
      $nom = $Latin.GetString($Utf8.GetBytes($dentro))
      if (-not $Crudo) { $nom = Get-Normal $nom $Dias }
      return @($l | ForEach-Object { $nom + ': ' + $_ })
    } catch { return @(Get-LineaBinaria $Bytes $Crudo) }
  }
  if ($tipo -ceq 'pdf' -or $tipo -ceq 'binario') { return @(Get-LineaBinaria $Bytes $Crudo) }
  $t = $Latin.GetString($Bytes)
  if (-not $Crudo) { $t = Get-Normal $t $Dias }
  $l = @($t -split '\r?\n')
  if ($l.Count -gt 0 -and $l[$l.Count - 1] -eq '') { $l = @($l | Select-Object -First ($l.Count - 1)) }
  return $l
}

# Las lineas de un fichero, normalizadas (Get-LineasContenido).
function Get-LineasNormales([string]$Ruta, $Dias = $null) {
  return @(Get-LineasContenido $Ruta ([System.IO.File]::ReadAllBytes($Ruta)) $Dias)
}

# Las lineas $L de una tabla (un .csv de tablas\: campos separados por ';', la primera linea con los nombres de las columnas) con las
# columnas ordenadas por su nombre (ordinal; a igual nombre, como estaban) y las filas ordenadas (String.CompareOrdinal): cada lado crea la
# tabla con su DDL y lee las filas en el orden que sea, y eso no es una diferencia del batch. $null si una fila no tiene tantos campos
# como la cabecera. Con $Col (el nombre de una columna), una fila con campos de mas los lleva a la primera columna con ese nombre: su valor
# lleva ';' dentro (la IA escribe los valores tal cual, sin comillas) y esa columna se queda con tantos campos como sobran; una fila con
# menos campos que la cabecera sigue sin valer.
function Sort-Tabla([string[]]$L, [string]$Col = '') {
  $cab = $L[0].Split(';')
  $c = -1
  if ($Col) { $c = [System.Array]::IndexOf($cab, $Col) }
  $filas = @()
  foreach ($x in @($L | Select-Object -Skip 1)) {
    $f = $x.Split(';')
    $mas = $f.Count - $cab.Count
    if ($mas -ne 0 -and ($c -lt 0 -or $mas -lt 0)) { return $null }
    if ($mas -gt 0) {
      $celdas = New-Object 'System.Collections.Generic.List[string]'
      for ($i = 0; $i -lt $f.Count; $i++) {
        if ($i -gt $c -and $i -le $c + $mas) { $celdas[$celdas.Count - 1] += ';' + $f[$i] } else { $celdas.Add($f[$i]) }
      }
      $f = $celdas.ToArray()
    }
    $filas += , $f
  }
  $claves = New-Object 'string[]' $cab.Count
  $orden = New-Object 'int[]' $cab.Count
  for ($i = 0; $i -lt $cab.Count; $i++) { $claves[$i] = $cab[$i] + [char]0 + $i.ToString('D6'); $orden[$i] = $i }
  [System.Array]::Sort($claves, $orden, [System.StringComparer]::Ordinal)
  $cuerpo = [string[]]@($filas | ForEach-Object { $f = $_; (@($orden | ForEach-Object { $f[$_] }) -join ';') })
  [System.Array]::Sort($cuerpo, [System.StringComparer]::Ordinal)
  return @((@($orden | ForEach-Object { $cab[$_] }) -join ';')) + $cuerpo
}

# Las lineas de las dos tablas $X (original) e $Y (migrado), ordenadas (Sort-Tabla), y la nota que dice por que no se han podido ordenar, si es
# el caso: X, Y y Nota. Una tabla con una fila que no tiene tantos campos como su cabecera se queda como esta, como siempre. Salvo si las dos
# cabeceras tienen los mismos nombres y alguna fila tiene campos de mas (un valor con ';' dentro, como una lista de correos a@x;b@x): se
# prueba cada nombre de columna, en orden ordinal, como la columna que se lleva los de mas en todas las filas de las dos tablas, y se queda
# la primera con la que las dos salen iguales. El supuesto: los ';' de mas de todas las filas son de la misma columna, en los dos lados. Si
# ninguna sirve, las tablas se quedan como estan y la nota dice la primera fila con otro numero de campos (del original o, si no, del migrado).
function Resolve-ParTablas([string[]]$X, [string[]]$Y) {
  $sx = $null; $sy = $null
  if ($X.Count -gt 0) { $sx = Sort-Tabla $X }
  if ($Y.Count -gt 0) { $sy = Sort-Tabla $Y }
  $r = [pscustomobject]@{ X = $X; Y = $Y; Nota = '' }
  if ($null -ne $sx) { $r.X = $sx }
  if ($null -ne $sy) { $r.Y = $sy }
  if ($X.Count -eq 0 -or $Y.Count -eq 0 -or ($null -ne $sx -and $null -ne $sy)) { return $r }
  $nombres = [string[]]@($X[0].Split(';'))
  $otros = [string[]]@($Y[0].Split(';'))
  if ((@(Sort-Ordinal $nombres) -join ';') -cne (@(Sort-Ordinal $otros) -join ';')) { return $r }
  $ancha = $false
  foreach ($lado in @(@{ L = $X; N = $nombres.Count }, @{ L = $Y; N = $otros.Count })) {
    for ($i = 1; $i -lt $lado.L.Count; $i++) {
      $m = $lado.L[$i].Split(';').Count
      if ($m -gt $lado.N) { $ancha = $true }
      if ($m -ne $lado.N -and -not $r.Nota) { $r.Nota = "la tabla tiene ';' dentro de algun valor (fila $($i + 1): $m campos; la cabecera, $($lado.N)): no se han podido ordenar sus columnas" }
    }
  }
  if (-not $ancha) { $r.Nota = ''; return $r }
  $orden = @(Sort-Ordinal $nombres)
  for ($i = 0; $i -lt $orden.Count; $i++) {
    if ($i -gt 0 -and $orden[$i] -ceq $orden[$i - 1]) { continue }
    $tx = Sort-Tabla $X $orden[$i]
    $ty = Sort-Tabla $Y $orden[$i]
    if ($null -ne $tx -and $null -ne $ty -and (@($tx) -join "`n") -ceq (@($ty) -join "`n")) { return [pscustomobject]@{ X = $tx; Y = $ty; Nota = '' } }
  }
  return $r
}

# Una linea leida byte a byte, para ensenarla: en UTF-8 si lo es; si no, tal cual (Latin-1).
function Get-Legible([string]$Linea) {
  try { return $Utf8Estricto.GetString($Latin.GetBytes($Linea)) } catch { return $Linea }
}

# Si dos ficheros distintos solo cambian en la codificacion (JEP 400: UTF-8 por defecto desde Java 18) o en el formato
# de numeros o fechas (JEP 252: datos de CLDR desde Java 9), la nota que lo dice; si no, ''. Un binario, un libro o un zip no son texto: no tienen codificacion ni formato de numeros que mirar.
function Get-NotaJdk([string]$A, [string]$B, $DiasA = $null, $DiasB = $null) {
  $ba = [System.IO.File]::ReadAllBytes($A)
  $bb = [System.IO.File]::ReadAllBytes($B)
  if ((Get-TipoContenido $A $ba) -cne 'texto' -or (Get-TipoContenido $B $bb) -cne 'texto') { return '' }
  $limpio = { param([string]$s, $d) ((Get-Normal $s.TrimStart([char]0xFEFF) $d) -replace '\r\n', "`n").TrimEnd("`n") }
  $ua = & $limpio ($Utf8.GetString($ba)) $DiasA
  $ub = & $limpio ($Utf8.GetString($bb)) $DiasB
  if ($ua -ceq $ub -or $ua -ceq (& $limpio ($Latin.GetString($bb)) $DiasB) -or (& $limpio ($Latin.GetString($ba)) $DiasA) -ceq $ub) {
    return 'posible diferencia del JDK: codificacion (JEP 400)'
  }
  $formato = { param([string]$s) (($s -replace '[\u00a0\u202f]', ' ') -replace "(?<=\d)[\.,' ](?=\d)", '' -replace '(?<=[A-Za-z])\.', '').ToLowerInvariant() }
  if ((& $formato $ua) -ceq (& $formato $ub)) { return 'posible diferencia del JDK: formato de numeros o fechas (JEP 252)' }
  return ''
}

# Compara dos ficheros ('' si falta uno) linea a linea, normalizados (con $Tabla, una tabla sin orden de columnas ni de filas, y con un
# valor con ';' dentro si hace falta: Resolve-ParTablas; la linea que se ensena es la ya ordenada). $null si son iguales; si no, Lineas
# (cuantas son distintas, posicion a posicion), Linea (la primera, desde 1), Original y Migrado (esa linea en cada lado) y Nota (la de la
# tabla, si la hay, y la del JDK). $DiasA y $DiasB son los dias de la ejecucion de cada lado (por defecto, $Hoy).
function Compare-Fichero([string]$A, [string]$B, [bool]$Tabla = $false, $DiasA = $null, $DiasB = $null) {
  $x = @(); $y = @()
  if ($A) { $x = @(Get-LineasNormales $A $DiasA) }
  if ($B) { $y = @(Get-LineasNormales $B $DiasB) }
  $notaTabla = ''
  if ($Tabla) {
    $t = Resolve-ParTablas $x $y
    $x = @($t.X); $y = @($t.Y); $notaTabla = $t.Nota
  }
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
  if ($A -and $B) { $nota = Get-NotaJdk $A $B $DiasA $DiasB }
  $original = & $lado $x $A
  $migrado = & $lado $y $B
  # Lo que se compara entero (un binario) y un PDF, que lleva dentro su fecha de creacion, lo dicen.
  $notaBin = ''
  if ($original -clike 'binario: *' -or $migrado -clike 'binario: *') { $notaBin = 'binario: se compara entero (sha256), no por dentro' }
  if (($A -match '(?i)\.pdf$' -or $B -match '(?i)\.pdf$') -and $notaBin) { $notaBin += '; un PDF lleva su fecha de creacion dentro: si solo cambia eso, es la fecha de creacion (se ignoran /CreationDate, /ModDate y /ID cuando estan sin comprimir)' }
  $nota = (@($notaTabla, $nota, $notaBin) | Where-Object { $_ }) -join '; '
  return [pscustomobject]@{ Lineas = [Math]::Max($n, 1); Linea = ($primera + 1); Original = $original; Migrado = $migrado; Nota = $nota }
}

# Las diferencias entre lo que dejo un caso en dos carpetas: una por fichero que no coincide (con su ruta relativa).
# Los ficheros se emparejan por la ruta normalizada (un nombre con la fecha de hoy vale en los dos lados), distinguiendo
# mayusculas. No se comparan tablas\BATCH_*.csv ni tablas\TASK_*.csv (en ninguno de los dos lados): son tablas del framework (Spring Batch,
# Spring Cloud Task), no del batch, y cada lado las deja a su manera (el migrado trae las de Spring Cloud Task, el original no). Tampoco los ficheros
# de $Cfg.CompararIgnorar (Test-Ignorado: por defecto los .log, el log por job del framework nuevo). Los demas
# .csv de tablas\ se comparan sin orden de columnas ni de filas (Resolve-ParTablas), y uno que esta en un solo lado y no tiene ninguna fila
# de datos no es una diferencia. $DiasA y $DiasB son los dias de la ejecucion de cada lado (por defecto, $Hoy): un original de otro dia no
# lleva las fechas de hoy. Cada diferencia lleva su clave (Get-Normal de la ruta, con los dias de su lado): la de las diferencias de un mismo
# fichero en casos con originales de dias distintos es la misma.
function Compare-Caso([string]$A, [string]$B, $DiasA = $null, $DiasB = $null) {
  $pares = New-Object System.Collections.Hashtable ([System.StringComparer]::Ordinal)
  foreach ($lado in @(@('A', $A, $DiasA), @('B', $B, $DiasB))) {
    if (-not (Test-Path -LiteralPath $lado[1])) { continue }
    foreach ($f in @(Get-ChildItem -LiteralPath $lado[1] -Recurse -File)) {
      $rel = Get-Rel $lado[1] $f.FullName
      if ($rel -cmatch '^tablas/(BATCH|TASK)_[^/]*\.csv$' -or (Test-Ignorado $rel)) { continue }
      $k = Get-Normal $rel $lado[2]
      if (-not $pares.ContainsKey($k)) { $pares[$k] = @{ A = (New-Object System.Collections.Hashtable ([System.StringComparer]::Ordinal)); B = (New-Object System.Collections.Hashtable ([System.StringComparer]::Ordinal)) } }
      $pares[$k][$lado[0]][$rel] = $f.FullName
    }
  }
  # Dos ficheros de un lado con la misma clave y otra ruta (la carpeta con la hora de dos ejecuciones del job) se emparejan, por orden de ruta, con los del otro lado.
  $emparejados = @()
  foreach ($k in @($pares.Keys | Sort-Object)) {
    $ra = [string[]]@($pares[$k].A.Keys)
    $rb = [string[]]@($pares[$k].B.Keys)
    [System.Array]::Sort($ra, [System.StringComparer]::Ordinal)
    [System.Array]::Sort($rb, [System.StringComparer]::Ordinal)
    for ($i = 0; $i -lt [Math]::Max($ra.Count, $rb.Count); $i++) {
      $p = @{ Clave = $k; A = ''; B = ''; Rel = '' }
      if ($i -lt $ra.Count) { $p.A = $pares[$k].A[$ra[$i]]; $p.Rel = $ra[$i] }
      if ($i -lt $rb.Count) { $p.B = $pares[$k].B[$rb[$i]]; if (-not $p.Rel) { $p.Rel = $rb[$i] } }
      $emparejados += , $p
    }
  }
  $dif = @()
  foreach ($p in $emparejados) {
    $k = $p.Clave
    $tabla = ($p.Rel -cmatch '^tablas/.+\.csv$')
    # Una tabla en un solo lado sin ninguna fila de datos (vacia, solo la cabecera o lineas en blanco) es como una tabla que no esta.
    if ($tabla -and -not ($p.A -and $p.B) -and @(Get-LineasNormales ($p.A + $p.B) | Where-Object { $_.Trim() }).Count -le 1) { continue }
    $c = Compare-Fichero $p.A $p.B $tabla $DiasA $DiasB
    if ($c) { $dif += [ordered]@{ fichero = $p.Rel; clave = $k; lineas = $c.Lineas; linea = $c.Linea; original = $c.Original; migrado = $c.Migrado; nota = $c.Nota } }
  }
  return $dif
}

# El tipo de una diferencia de Compare-Caso (o de las que cambian Get-Resultado y Join-OtraCarpeta): noGuardado, otraCarpeta, falta (no esta en el migrado), sobra
# (solo esta en el migrado) o contenido.
function Get-TipoDif($D) {
  if ($D.noGuardado) { return 'noGuardado' }
  if ($D.otraCarpeta) { return 'otraCarpeta' }
  if ($D.migrado -ceq '(no esta)') { return 'falta' }
  if ($D.original -ceq '(no esta)') { return 'sobra' }
  return 'contenido'
}

# Una lista de carpetas en una frase: 'A', 'A y B' o 'A, B y C'.
function Format-Carpetas($Carpetas) {
  $l = @($Carpetas)
  if ($l.Count -le 1) { return ($l -join '') }
  return ((@($l | Select-Object -First ($l.Count - 1)) -join ', ') + ' y ' + $l[$l.Count - 1])
}

# Las diferencias $Dif de un caso (Compare-Caso) con un fichero que cada lado deja en otra carpeta como una sola. Si el original deja un fichero en una carpeta y el
# migrado, con el mismo nombre (normalizado, como su clave), en otra, Compare-Caso da una diferencia suelta por cada copia (falta en el migrado, sobra en el original) y
# la causa es una: la carpeta. Las faltas y las sobras de ese nombre pasan a una sola, de tipo otraCarpeta (New-DifOtraCarpeta), en el sitio de la primera. Un nombre que solo
# esta en un lado, un fichero de tablas\ y un fichero con el mismo nombre en la misma carpeta (se compara como siempre) quedan como estaban. $A es la salida del caso en el
# original y $B en el migrado, con sus dias ($DiasA y $DiasB, como en Compare-Caso).
function Join-OtraCarpeta($Dif, [string]$A, [string]$B, $DiasA = $null, $DiasB = $null) {
  # El nombre normalizado de una falta o una sobra que puede estar en otra carpeta (no las de tablas\); '' si no
  $nombreDe = {
    param($d)
    if (@('falta', 'sobra') -cnotcontains (Get-TipoDif $d) -or $d.fichero -cmatch '^tablas/') { return '' }
    return $d.clave.Substring($d.clave.LastIndexOf('/') + 1)
  }
  $por = New-Object System.Collections.Hashtable ([System.StringComparer]::Ordinal)
  foreach ($d in @($Dif)) {
    $n = & $nombreDe $d
    if (-not $n) { continue }
    if (-not $por.ContainsKey($n)) { $por[$n] = @{ falta = @(); sobra = @() } }
    $por[$n][(Get-TipoDif $d)] += $d
  }
  $res = @()
  $hechos = @{}
  foreach ($d in @($Dif)) {
    $n = & $nombreDe $d
    if (-not $n -or @($por[$n].falta).Count -eq 0 -or @($por[$n].sobra).Count -eq 0) { $res += $d; continue }
    if ($hechos.ContainsKey($n)) { continue }
    $hechos[$n] = $true
    $res += New-DifOtraCarpeta $por[$n].falta $por[$n].sobra $A $B $DiasA $DiasB
  }
  return $res
}

# La diferencia de un fichero que el original deja en las carpetas de $Faltas (sus diferencias de falta en el migrado) y el migrado en las de $Sobras (de sobra): fichero (el
# nombre), carpetasOriginal y carpetasMigrado (las de la clave de cada una, en orden ordinal; (raiz) si es la de la salida del caso), original y migrado ('en <carpetas>'), y por
# clave la pareja de carpetas, que comparten los casos con la misma pareja aunque su nombre lleve otra fecha. Su nota dice si el contenido es igual al de alguna copia del
# original (la primera) o, si no, la primera linea distinta del primer par (Compare-Fichero); lineas y linea, las de esa comparacion o 1.
function New-DifOtraCarpeta($Faltas, $Sobras, [string]$A, [string]$B, $DiasA = $null, $DiasB = $null) {
  $carpeta = { param($d) $i = $d.clave.LastIndexOf('/'); if ($i -lt 0) { '(raiz)' } else { $d.clave.Substring(0, $i) } }
  $deOrig = @(Sort-Ordinal @(@($Faltas) | ForEach-Object { & $carpeta $_ } | Select-Object -Unique))
  $deMig = @(Sort-Ordinal @(@($Sobras) | ForEach-Object { & $carpeta $_ } | Select-Object -Unique))
  $cmp = @(foreach ($f in @($Faltas)) { foreach ($s in @($Sobras)) { [pscustomobject]@{ De = $f.fichero; C = (Compare-Fichero (Join-Ruta $A $f.fichero) (Join-Ruta $B $s.fichero) $false $DiasA $DiasB) } } })
  $lineas = 1; $linea = 1
  $igual = @($cmp | Where-Object { $null -eq $_.C })[0]
  if ($igual) { $nota = "el contenido es igual al de $($igual.De), del original" }
  else {
    $c = $cmp[0].C
    $lineas = $c.Lineas; $linea = $c.Linea
    $nota = "el contenido es distinto: la primera linea distinta, la $($c.Linea): original [$($c.Original)]; migrado [$($c.Migrado)]"
    if ($c.Nota) { $nota += " ($($c.Nota))" }
  }
  $nombre = $Faltas[0].fichero.Substring($Faltas[0].fichero.LastIndexOf('/') + 1)
  return [ordered]@{
    fichero = $nombre; clave = ($deOrig -join ',') + ' -> ' + ($deMig -join ','); lineas = $lineas; linea = $linea; original = 'en ' + (Format-Carpetas $deOrig); migrado = 'en ' + (Format-Carpetas $deMig)
    nota = $nota; otraCarpeta = $true; carpetasOriginal = $deOrig; carpetasMigrado = $deMig
  }
}

# Lo que no se pudo guardar de un caso en sus lados (original, original-2 y $Nombre, el migrado; Copy-Salida): uno por fichero (por su ruta
# normalizada, que es la misma en todos los lados), con fichero, clave, destino (la clave de donde habria ido, para quitar la diferencia que
# Compare-Caso ve por faltar en un lado) y, en original y migrado, el motivo del lado que fallo o '(guardado)'.
function Get-SinGuardar([string]$Nombre, [string]$Job, [string]$Caso) {
  $por = [ordered]@{}
  foreach ($lado in @('original', 'original-2', $Nombre)) {
    foreach ($n in @(Get-NoGuardados $lado $Job $Caso)) {
      if (-not $por.Contains($n.clave)) { $por[$n.clave] = [pscustomobject]@{ fichero = $n.fichero; clave = $n.clave; destino = $n.destino; original = ''; migrado = '' } }
      $x = $por[$n.clave]
      $texto = "no se ha podido guardar: $($n.motivo)"
      if ($lado -ceq $Nombre) { $x.migrado = $texto } elseif (-not $x.original) { $x.original = $texto }
    }
  }
  foreach ($x in @($por.Values)) {
    if (-not $x.original) { $x.original = '(guardado)' }
    if (-not $x.migrado) { $x.migrado = '(guardado)' }
  }
  return @($por.Values)
}

# El resultado de un caso: igual, distinto (con sus diferencias), no determinista, no se pudo preparar o sin probar en
# local, con su motivo. Los ficheros que cambian entre las dos ejecuciones del original no se comparan; el resto, si.
# Un caso igual que deja lo mismo que el caso vacio del arnes lleva un aviso: puede que su entrada no llegue al job.
# Si Maven se ha pasado del tope en una de sus tres ejecuciones, no se pudo preparar y el motivo es el mensaje del tope.
# 'fallos' dice, de original y migrado, cual acaba FAILED, EXCEPCION o sin estado.txt y por que (Get-Fallos). Un caso con un fichero que no se
# pudo guardar sale distinto, con ese fichero entre las diferencias (noGuardado). Un caso que no se ejecuto en el migrado porque su job no arranca con
# su test (Invoke-Salidas) sale sin probar en local.
# $Nombre es donde esta lo del migrado: salidas\<Nombre> (el migrado de siempre, o el de un commit de la busqueda de -Desde). Lo del original
# se normaliza con los dias de su ejecucion (Get-DiasOriginal: puede ser de otro dia) y lo del migrado, con los de hoy.
function Get-Resultado($T, [string]$Nombre = 'migrado') {
  $script:Hoy = @(Get-Hoy $Inicio (Get-Date))   # la busqueda de -Desde puede pasar de medianoche
  $j = $T.entradas.job
  $c = $T.entradas.caso
  $o = [ordered]@{ job = $j; caso = $c; titulo = $T.entradas.titulo; resultado = 'no se pudo preparar'; motivo = ''; diferencias = @(); fallos = @() }
  $s1 = Join-Ruta $Local "salidas/original/$j/$c"
  $noAplica = Join-Ruta $Local "casos/$j/$c/no-aplica.txt"
  $parado = @(@('original', 'original-2', $Nombre) | ForEach-Object { $script:Maven["$_|$j|$c"] } | Where-Object { $_ -and $_.Tope })
  if ($parado.Count -gt 0) { $o.motivo = $parado[0].Tope; return $o }
  if ($T.estado -ne 'hecha') { $o.motivo = "La IA no ha podido preparar sus entradas: $($T.motivo)"; return $o }
  if (Test-Path -LiteralPath $noAplica) { $o.resultado = 'sin probar en local'; $o.motivo = ([System.IO.File]::ReadAllText($noAplica, $Utf8) -replace '\s+', ' ').Trim(); return $o }
  if ($script:SinProbar.ContainsKey("original|$j|$c")) { $o.resultado = 'sin probar en local'; $o.motivo = $script:SinProbar["original|$j|$c"]; return $o }
  if (-not (Test-Path -LiteralPath (Join-Path $s1 'estado.txt'))) {
    $porque = Get-Porque $s1 $script:Maven["original|$j|$c"]
    $o.motivo = Get-MotivoTablaMal $porque
    if (-not $o.motivo) { $o.motivo = Get-MotivoColumna $porque $j }
    if (-not $o.motivo) { $o.motivo = 'En el original ' + $porque }
    return $o
  }
  if ($ArnesMig.estado -ne 'hecha') { $o.motivo = 'El migrado no tiene su test PruebaLocalTest (el arnes ha quedado atascado).'; return $o }
  if ($script:SinProbar.ContainsKey("$Nombre|$j|$c")) { $o.resultado = 'sin probar en local'; $o.motivo = $script:SinProbar["$Nombre|$j|$c"]; return $o }
  $o.fallos = @(Get-Fallos $Nombre $j $c)
  $diasOrig = Get-DiasOriginal $j $c
  $azar = @(Compare-Caso $s1 (Join-Ruta $Local "salidas/original-2/$j/$c") $diasOrig $diasOrig)
  $sinContar = @($azar | ForEach-Object { $_.clave })
  if ($azar.Count -gt 0) { $o.motivo = 'No se comparan, porque el original da dos salidas distintas: ' + (@($azar | Select-Object -First 3 | ForEach-Object { $_.fichero }) -join ', ') + '.' }
  $d = @(Compare-Caso $s1 (Join-Ruta $Local "salidas/$Nombre/$j/$c") $diasOrig | Where-Object { $sinContar -notcontains $_.clave })
  # Un fichero que no se pudo guardar en algun lado no se puede comparar: el caso nunca sale igual. Su diferencia sustituye a la de que falte en un lado.
  $sg = @(Get-SinGuardar $Nombre $j $c)
  if ($sg.Count -gt 0) {
    $destinos = @($sg | ForEach-Object { $_.destino } | Where-Object { $_ })
    $d = @($sg | ForEach-Object { [ordered]@{ fichero = $_.fichero; clave = $_.clave; lineas = 1; linea = 1; original = $_.original; migrado = $_.migrado; nota = ''; noGuardado = $true } }) + @($d | Where-Object { $destinos -notcontains $_.clave })
    $o.motivo = ($o.motivo + " No se han podido guardar $($sg.Count) fichero(s) de salidas: el caso no se da por igual.").Trim()
  }
  # Un fichero que el original deja en una carpeta y el migrado en otra es una sola diferencia (despues de lo que no se pudo guardar: esas faltas no son de verdad)
  $d = @(Join-OtraCarpeta $d $s1 (Join-Ruta $Local "salidas/$Nombre/$j/$c") $diasOrig)
  if ($d.Count -gt 0) {
    $o.resultado = 'distinto'; $o.diferencias = $d
    # Un migrado que no ha dejado ni estado.txt no ha corrido el caso: la consola lo dice antes de las diferencias, que son todas (no esta)
    $salidaMig = Join-Ruta $Local "salidas/$Nombre/$j/$c"
    if (-not (Test-Path -LiteralPath (Join-Path $salidaMig 'estado.txt'))) { $o.motivo = 'El migrado no corrio este caso: ' + (Get-Porque $salidaMig $script:Maven["$Nombre|$j|$c"]) }
    return $o
  }
  if ($azar.Count -gt 0) { $o.resultado = 'no determinista'; return $o }
  $o.resultado = 'igual'
  $vacio = Join-Ruta $Local "salidas/vacio/$j"
  if ((Test-Path -LiteralPath $vacio) -and @(Compare-Caso $s1 $vacio $diasOrig $diasOrig).Count -eq 0) { $o.motivo = $MotivoVacio }
  return $o
}

# ======================== GRUPOS POR CAUSA ========================
# Los casos distintos de un batch suelen ser pocas causas repetidas (una dependencia mal puesta, un test del migrado que no arranca, una columna
# que cambia): se agrupan, sin IA, por la firma de su causa, y la consola y prueba-local.json cuentan causas y no casos. Cada grupo lleva ademas
# lo que se mide de el (Add-Hechos). Solo los casos distintos entran en un grupo.

# La causa $Causa del caso $Caso sin lo que cambia de un caso a otro: el nombre del caso (<caso>), @ y hexadecimal (@<id>), las fechas y horas de
# hoy (Get-Normal), las rutas (<ruta>: una palabra con \, o que empieza por / y lleva otra /, o con letra de unidad (C:\ o C:/), o file:, o la de una
# copia) y los numeros de dos cifras o mas (<n>); en 200 letras como mucho. org/x/Clase (el nombre de una clase que falta, NoClassDefFoundError) no es una ruta.
function Get-CausaNormal([string]$Causa, [string]$Caso) {
  $t = $Causa
  if ($Caso) { $t = $t.Replace($Caso, '<caso>') }
  $t = (Get-Normal $t) -replace '@[0-9a-fA-F]+\b', '@<id>'
  $t = $t -replace '(?<!\S)(?:\S*\\\S*|[A-Za-z]:[\\/]\S*|file:\S*|/\S*/\S*|<copia>/\S*)', '<ruta>'
  $t = $t -replace '\d{2,}', '<n>'
  if ($t.Length -gt 200) { $t = $t.Substring(0, 200) }
  return $t
}

# Los grupos de los casos distintos de $Res, numerados desde 1: primero los de fallo, despues los de mas casos y, a igualdad, por la firma (en orden
# ordinal). Cada uno: numero, tipo, firma, casos ('job/caso', por job y caso), descripcion (la cabecera de la consola, sin 'Grupo <n>: ') y hechos (vacio).
# - De fallo: el migrado acaba FAILED, EXCEPCION o sin estado.txt y el original no. Firma 'fallo|<estado>|<causa normalizada>' (Get-CausaNormal).
# - De fichero: los demas. Firma 'fichero|' y la lista ordenada de '<clave>:<tipo>' de sus diferencias; el tipo es falta (no esta en el migrado), sobra
#   (solo esta en el migrado), noGuardado, otraCarpeta (un fichero que cada lado deja en otra carpeta, Join-OtraCarpeta: su clave es la pareja de carpetas
#   y no el nombre, que lleva la fecha del caso, y su cabecera dice las carpetas de cada lado) o contenido.
function Get-Grupos($Res) {
  $por = New-Object System.Collections.Hashtable ([System.StringComparer]::Ordinal)
  foreach ($r in @($Res | Where-Object { $_.resultado -eq 'distinto' })) {
    $mig = @($r.fallos | Where-Object { $_.lado -ceq 'migrado' })
    $orig = @($r.fallos | Where-Object { $_.lado -ceq 'original' })
    $ent = New-Object System.Collections.Hashtable ([System.StringComparer]::Ordinal)
    if ($mig.Count -gt 0 -and $orig.Count -eq 0) {
      $tipo = 'fallo'
      $firma = 'fallo|' + $mig[0].estado + '|' + (Get-CausaNormal ([string]$mig[0].causa) $r.caso)
    }
    else {
      $tipo = 'fichero'
      foreach ($d in @($r.diferencias)) {
        $ent[$d.clave + ':' + (Get-TipoDif $d)] = $d
      }
      $firma = 'fichero|' + ((Sort-Ordinal @($ent.Keys)) -join '|')
    }
    if (-not $por.ContainsKey($firma)) { $por[$firma] = [pscustomobject]@{ tipo = $tipo; firma = $firma; miembros = @() } }
    $por[$firma].miembros += [pscustomobject]@{ clave = ($r.job + "`t" + $r.caso); caso = $r; ent = $ent }
  }
  $claves = New-Object System.Collections.Hashtable ([System.StringComparer]::Ordinal)
  foreach ($g in $por.Values) {
    $m = @($g.miembros)
    $k = [string[]]@($m | ForEach-Object { $_.clave })
    [System.Array]::Sort($k, [object[]]$m, [System.StringComparer]::Ordinal)
    $cuantos = "$($m.Count) casos distintos"
    if ($m.Count -eq 1) { $cuantos = '1 caso distinto' }
    if ($g.tipo -ceq 'fallo') { $desc = "$cuantos, " + (Format-Fallo @($m[0].caso.fallos | Where-Object { $_.lado -ceq 'migrado' })[0] -ConRegistro) }
    else {
      $lista = @(Sort-Ordinal @($m[0].ent.Keys))
      $primera = $m[0].ent[$lista[0]]
      if ($primera.otraCarpeta) { $desc = "$cuantos, el migrado deja sus ficheros en $(Format-Carpetas $primera.carpetasMigrado) y el original en $(Format-Carpetas $primera.carpetasOriginal)" }
      else { $desc = "$cuantos, en $($primera.fichero): " + $lista[0].Substring($lista[0].LastIndexOf(':') + 1) }
      if ($lista.Count -eq 2) { $desc += ' y 1 fichero mas' }
      if ($lista.Count -gt 2) { $desc += " y $($lista.Count - 1) ficheros mas" }
    }
    $orden = '1'
    if ($g.tipo -ceq 'fallo') { $orden = '0' }
    $claves[$orden + '|' + (999999 - $m.Count).ToString('D6') + '|' + $g.firma] = [ordered]@{
      numero = 0; tipo = $g.tipo; firma = $g.firma; casos = @($m | ForEach-Object { $_.caso.job + '/' + $_.caso.caso }); descripcion = $desc; hechos = @()
    }
  }
  $grupos = @()
  foreach ($k in @(Sort-Ordinal @($claves.Keys))) {
    $g = $claves[$k]
    $g.numero = $grupos.Count + 1
    $grupos += $g
  }
  return $grupos
}

# El resultado del caso 'job/caso' de $Res.
function Get-CasoDe($Res, [string]$Clave) { return @($Res | Where-Object { ($_.job + '/' + $_.caso) -ceq $Clave })[0] }

# El prueba-local.json que hay ahora en datos\ ($null si no hay o no se lee).
function Get-JsonPrueba {
  $json = Join-Path $DatosMig 'prueba-local.json'
  if (-not (Test-Path -LiteralPath $json)) { return $null }
  try { return (Read-Json $json) } catch { return $null }
}

# El arbol de dependencias del migrado (mvn dependency:tree en su copia), una sola vez por lanzamiento y solo si un grupo lo pide (Add-Hechos). Lo deja
# en prueba-local\dependencias.txt. Devuelve Lineas, Ruta (de dependencias.txt) y Motivo (corto; '' si Maven ha dado el arbol). Si Maven falla o se
# pasa del tope no se guarda nada y no se vuelve a intentar.
function Get-ArbolDependencias {
  if ($null -eq $script:Arbol) {
    $r = Invoke-Maven $CopiaMig $false @('dependency:tree') 'el arbol de dependencias del migrado'
    $a = [pscustomobject]@{ Lineas = @(); Ruta = ''; Motivo = '' }
    if ($r.Codigo -eq 0 -and -not $r.Tope) {
      $a.Lineas = @($r.Salida)
      $a.Ruta = Join-Path $Local 'dependencias.txt'
      [System.IO.File]::WriteAllText($a.Ruta, ((@($r.Salida) -join "`n") + "`n"), $Utf8)
    }
    else {
      $m = $r.Tope
      if (-not $m) { $m = (@($r.Salida | Where-Object { $_ -match '^\[ERROR\]' } | Select-Object -First 1) -join '') -replace '^\[ERROR\]\s*', '' }
      if (-not $m) { $m = "Maven acaba con el codigo $($r.Codigo)" }
      $a.Motivo = $m.Substring(0, [Math]::Min($m.Length, 200))
    }
    $script:Arbol = $a
  }
  return $script:Arbol
}

# Lo que se ha medido de cada grupo de $Grupos (sus 'hechos', uno por cadena), con los casos de $Res; $Codigo y $Hash son el codigo y el test del migrado
# de ahora (codigoMigrado y hashArnesMigrado de prueba-local.json). Dos hechos:
# - De dependencias: la causa de un grupo de fallo dice que falta una clase o un metodo (TypeNotPresentException, NoClassDefFoundError...). Del
#   nombre de la clase que falta (el primero con tres segmentos o mas tras el nombre de la excepcion; no el de la excepcion) se buscan en el arbol de
#   dependencias del migrado (Get-ArbolDependencias) las lineas con sus tres primeros segmentos y, si no hay ninguna, con los dos primeros.
# - Cambio con el test: el prueba-local.json de antes de este lanzamiento ($script:Anterior) es del mismo codigo del migrado y de otro test del migrado, y
#   al menos la mitad de los casos del grupo eran iguales en el. Sin esos dos campos en el de antes (el primer lanzamiento con ellos), no se dice nada.
function Add-Hechos($Grupos, $Res, [string]$Codigo, [string]$Hash) {
  $antes = $script:Anterior
  foreach ($g in @($Grupos)) {
    $h = @()
    if ($g.tipo -ceq 'fallo') {
      $fallo = @((Get-CasoDe $Res $g.casos[0]).fallos | Where-Object { $_.lado -ceq 'migrado' })[0]
      $falta = [regex]::Match([string]$fallo.causa, '(?s)(TypeNotPresentException|NoClassDefFoundError|ClassNotFoundException|NoSuchMethodError|NoSuchFieldError|AbstractMethodError|IncompatibleClassChangeError)(?<resto>.*)')
      $clase = [regex]::Match($falta.Groups['resto'].Value, '[A-Za-z_$][\w$]*([./][A-Za-z_$][\w$]*){2,}')
      if ($falta.Success -and $clase.Success) {
        $seg = @($clase.Value.Replace('/', '.').Split('.'))
        $arbol = Get-ArbolDependencias
        if ($arbol.Motivo) { $h += "de dependencias, sin arbol: $($arbol.Motivo)" }
        else {
          $prefijo = ($seg | Select-Object -First 3) -join '.'
          $lineas = @($arbol.Lineas | Where-Object { $_.Contains($prefijo) })
          if ($lineas.Count -eq 0) { $prefijo = ($seg | Select-Object -First 2) -join '.'; $lineas = @($arbol.Lineas | Where-Object { $_.Contains($prefijo) }) }
          $texto = (@($lineas | Select-Object -First 5 | ForEach-Object { ($_ -replace '^\[INFO\]\s*', '') -replace '^[|+\\\-\s]+', '' }) -join '; ')
          if (-not $texto) { $texto = "ninguna linea con $prefijo" }
          $h += "de dependencias: falta una clase o un metodo de $prefijo. En el arbol del migrado: $texto. Arbol completo: $($arbol.Ruta)"
        }
      }
    }
    if ($antes -and $antes.PSObject.Properties['codigoMigrado'] -and $antes.PSObject.Properties['hashArnesMigrado'] -and $antes.codigoMigrado -ceq $Codigo -and $antes.hashArnesMigrado -cne $Hash) {
      $iguales = 0
      foreach ($c in @($g.casos)) { if (@($antes.casos | Where-Object { ($_.job + '/' + $_.caso) -ceq $c -and $_.resultado -ceq 'igual' }).Count -gt 0) { $iguales++ } }
      if ($iguales * 2 -ge @($g.casos).Count) { $h += "cambio con el test: $iguales de $(@($g.casos).Count) casos eran iguales con el test del migrado anterior y el mismo codigo" }
    }
    $g.hechos = $h
  }
}

# Los jobs de $Casos (los de un resultado, Get-Resultado, o los del prueba-local.json de antes) cuyo original acaba FAILED o EXCEPCION con la misma causa
# (Get-FirmaFallo) en todos sus casos comparados (Test-Ejecutable: igual, distinto o no determinista; si los dos lados fallan igual el caso sale igual y tambien cuenta),
# 2 como minimo: el original funciona en produccion, asi que es su test. Uno por job: job y fallo (el del primer caso).
function Get-JobsFalloOriginal($Casos) {
  $jobs = @()
  foreach ($j in @($Casos | ForEach-Object { $_.job } | Select-Object -Unique)) {
    $comparados = @($Casos | Where-Object { $_.job -ceq $j -and (Test-Ejecutable $_) })
    if ($comparados.Count -lt 2) { continue }
    $firmas = @()
    $primero = $null
    foreach ($c in $comparados) {
      $f = @(@($c.fallos) | Where-Object { $_.lado -ceq 'original' })[0]
      if ($firmas.Count -eq 0) { $primero = $f }
      $firmas += (Get-FirmaFallo $f $c.caso)
    }
    if ($firmas[0] -and @($firmas | Where-Object { $_ -cne $firmas[0] }).Count -eq 0) { $jobs += [pscustomobject]@{ job = $j; fallo = $primero } }
  }
  return $jobs
}

# La linea de la consola de un job de Get-JobsFalloOriginal: si el original no arranca (Test-FalloArranque), dice la clase y la causa; si no, el estado y la causa.
function Format-LineaOriginal([string]$Job, $F) {
  if (Test-FalloArranque $F) { return "El original no arranca el job $Job ($(Get-ClaseFallo $F): $($F.causa)). Es el test del original, no el codigo: relanza con -RehacerOriginal." }
  return "El original falla igual en todos los casos de $Job ($($F.estado): $($F.causa)). El original funciona en produccion: es su test, no el codigo. Relanza con -RehacerOriginal."
}

# Los jobs cuyo migrado acaba EXCEPCION en todos los casos que se han comparado y con lo mismo (todos esos casos estan en un mismo grupo de fallo EXCEPCION de $Grupos):
# lo normal es que sea el test del migrado (arnes\migrado) y no su codigo. Uno por job: su grupo (numero), la clase y la causa del primer caso, el detalle ('clase: causa') y
# su error del codigo (Get-ErrorCodigo; $null si no lo es). Lo usan la consola (Show-Resultado) y prueba-local.json (Get-PorJob).
function Get-JobsMigradoNoArranca($Res, $Grupos) {
  $jobs = @()
  foreach ($g in @($Grupos | Where-Object { $_.firma -cmatch '^fallo\|EXCEPCION\|' })) {
    $lista = @($g.casos)
    foreach ($j in @($lista | ForEach-Object { (Get-CasoDe $Res $_).job } | Select-Object -Unique)) {
      $casos = @($Res | Where-Object { $_.job -ceq $j -and (Test-Ejecutable $_) })
      if (@($casos | Where-Object { $lista -ccontains ($_.job + '/' + $_.caso) }).Count -ne $casos.Count) { continue }
      $clase = Get-Excepcion (Join-Ruta $Local "salidas/migrado/$j/$($casos[0].caso)")
      $causa = [string]@($casos[0].fallos | Where-Object { $_.lado -eq 'migrado' })[0].causa
      $detalle = $clase
      if ($causa) { $detalle = "${clase}: $causa" }
      $jobs += [pscustomobject]@{ job = $j; grupo = $g.numero; clase = $clase; causa = $causa; detalle = $detalle; error = (Get-ErrorCodigo $clase $causa) }
    }
  }
  return $jobs
}

# La tabla por consola, los casos distintos por grupo (Get-Grupos: la cabecera, los casos, lo medido y el detalle de los dos primeros) y, despues, lo que
# no es igual de los demas, caso a caso. Si un grupo de fallo EXCEPCION cubre todos los casos que se han comparado de un job, lo normal es que sea el
# test del migrado (arnes\migrado) y no su codigo, y se arregla con -RehacerArnes: una linea por job, con la clase y la causa del primer caso. Si el test se
# escribio varias veces con ese error ($script:NoArranca), la linea dice que puede ser el codigo y no aconseja -RehacerArnes. Si es un error del codigo
# (Get-ErrorCodigo: clase final con proxy, referencia circular, bean repetido), la linea lo dice con su regla del paso de calidad y tampoco aconseja -RehacerArnes.
# Los jobs cuyo original falla igual en todos sus casos (Get-JobsFalloOriginal) salen aparte, al final (Format-LineaOriginal), y no llevan la linea de -RehacerArnes.
function Show-Resultado($Res, $PorJob, $Grupos) {
  Info ''
  Info 'Prueba en local: el original frente al migrado, con las mismas entradas'
  $ancho = [Math]::Max(32, [int](@($PorJob | ForEach-Object { $_.job.Length } | Measure-Object -Maximum).Maximum))   # el nombre mas largo, con un minimo
  $fmt = "{0,-$ancho} {1,6} {2,8} {3,10} {4,11}"
  Info ($fmt -f 'Job', 'Casos', 'Iguales', 'Distintos', 'Sin probar')
  foreach ($p in $PorJob) { Info ($fmt -f $p.job, $p.casos, $p.iguales, $p.distintos, $p.sinProbar) }
  $noArrancan = @(Get-JobsMigradoNoArranca $Res $Grupos)
  foreach ($g in @($Grupos)) {
    $lista = @($g.casos)
    $miembros = @($lista | ForEach-Object { Get-CasoDe $Res $_ })
    Fallo "  Grupo $($g.numero): $($g.descripcion)"
    $texto = (@($lista | Select-Object -First 10) -join ', ')
    if ($lista.Count -gt 10) { $texto += " y $($lista.Count - 10) mas" }
    Info "    casos: $texto"
    foreach ($h in @($g.hechos)) { Info "    medido: $h" }
    if ($g.firma -cmatch ':otraCarpeta(\||$)') { Aviso '    Suele ser el test del migrado, que da a su propiedad de carpeta otro valor: relanza con -RehacerArnes. Si no, mira la propiedad en el application.yml del migrado o un cambio del codigo.' }
    foreach ($n in @($noArrancan | Where-Object { $_.grupo -eq $g.numero })) {
      if ($n.error) { Aviso "    El migrado no arranca el job $($n.job) en ningun caso ($($n.detalle)). $(Format-ErrorCodigo $n.error) Corre el paso de calidad de rescate.ps1 y vuelve a lanzar la prueba." }
      elseif ($script:NoArranca.ContainsKey($n.job)) { Aviso "    El migrado no arranca el job $($n.job) ($($n.detalle)). El test ya se escribio $($script:NoArranca[$n.job].veces) veces con este error: puede ser el codigo del migrado. Pregunta a Copilot, en el repo del migrado, si el job arrancaria igual fuera del test." }
      else { Aviso "    El migrado no arranca el job $($n.job) en ningun caso ($($n.detalle)). Casi siempre es el test del migrado, no el codigo: relanza con -RehacerArnes." }
    }
    foreach ($r in @($miembros | Select-Object -First 2)) {
      Fallo "    distinto: $($r.job)/$($r.caso) ($($r.titulo))"
      if ($r.motivo) { Aviso "      $($r.motivo)" }
      foreach ($f in @($r.fallos)) { Aviso "      $(Format-Fallo $f -ConRegistro)" }
      foreach ($d in @($r.diferencias | Select-Object -First 3)) {
        if ($d.noGuardado) { Info "      $($d.fichero): original: $($d.original); migrado: $($d.migrado)"; continue }
        if ($d.otraCarpeta) { Info "      $($d.fichero): el original lo deja $($d.original); el migrado, $($d.migrado)"; if ($d.nota) { Aviso "        ($($d.nota))" }; continue }
        Info "      $($d.fichero): lineas distintas: $($d.lineas); la primera, la $($d.linea):"
        Info "        original: $($d.original)"
        Info "        migrado:  $($d.migrado)"
        if ($d.nota) { Aviso "        ($($d.nota))" }
      }
    }
  }
  foreach ($r in @($Res | Where-Object { $_.resultado -ne 'distinto' -and ($_.resultado -ne 'igual' -or $_.motivo) })) {
    Aviso "  $($r.resultado): $($r.job)/$($r.caso) ($($r.titulo)). $(($r.motivo -split "`n")[0])"
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
  Invoke-SalidaCaso $CopiaMig $false $nombre $j $c
  $mvn = $script:Maven["$nombre|$j|$c"]
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
function Get-Claves($R) { return @(@($R.diferencias) | ForEach-Object { $_.clave } | Select-Object -Unique) }

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

# El codigo del migrado en $Commit que cuenta para la clave de una tarea de reparar: el arbol de src/main y el pom.xml (los dos en la raiz de
# la carpeta, que es donde los busca todo este script: Test-Arreglo solo deja cambiar src/main/ y Save-Arreglo solo lleva src/main). Un commit
# que solo toca src/test no los cambia. Si falta alguno, vale el commit entero: la clave cambia con cualquier commit, nunca vale de mas.
function Get-CodigoMigrado([string]$Commit) {
  $r = Invoke-Git $DirRama @('rev-parse', "${Commit}:src/main", "${Commit}:pom.xml")
  if ($r.Codigo -ne 0 -or @($r.Salida).Count -ne 2) { return $Commit }
  return (@($r.Salida) -join '|')
}

# La tarea de IA que arregla la clave $C en su primer caso, con el resultado $R de ahora, o la de otro lanzamiento si quedo atascada con
# este mismo codigo del migrado (Get-CodigoMigrado) y con este mismo test del migrado (el id lleva los dos: con otro arnes, una clave que salio
# 'no se arregla' se vuelve a probar). Trabaja en la copia del migrado y puede leer el original y las salidas y entradas del caso.
function Get-TareaReparar($C, $R, $S) {
  $tc = Get-TareaCaso $C.job $C.caso
  $d = @($R.diferencias | Where-Object { $_.clave -ceq $C.clave })[0]
  # Si un lado del caso acaba FAILED o EXCEPCION (o sin estado.txt), la causa de su Maven (Get-Fallos): una linea mas en el prompt
  $fallo = (@($R.fallos | ForEach-Object { Format-Fallo $_ }) -join '; ')
  $siCausa = ''
  if (-not $fallo) { $siCausa = $MarcaNo }
  $otras = @($R.diferencias | Where-Object { $_.clave -cne $C.clave } | Select-Object -First 5 | ForEach-Object { '- `{0}`: {1} lineas distintas; la primera, la {2}: original [{3}], migrado [{4}]' -f $_.fichero, $_.lineas, $_.linea, $_.original, $_.migrado })
  if ($otras.Count -eq 0) { $otras = @('(No hay otras diferencias en este caso.)') }
  $salOrig = Join-Ruta $Local "salidas/original/$($C.job)/$($C.caso)"
  $salMig = Join-Ruta $Local "salidas/$($S.Salidas)/$($C.job)/$($C.caso)"
  $entradas = Join-Ruta $Local "casos/$($C.job)/$($C.caso)"
  $resto = "$($C.job)|$($C.caso)|$($C.clave)|$(Get-HashGuardado 'migrado' $ArnesMig.entradas.test)"
  $id = 'reparar-' + (Get-Hash8 ((Get-CodigoMigrado $headMig) + '|' + $resto))
  $prompt = [pscustomobject]@{
    JOB = $C.job; CASO = $C.caso; TITULO = [string]$tc.entradas.titulo; ENTRADA = [string]$tc.entradas.prompt.ENTRADA; ESPERADO = [string]$tc.entradas.prompt.ESPERADO
    FICHERO = $d.fichero; LINEAS = "$($d.lineas)"; LINEA = "$($d.linea)"; ORIGINAL = [string]$d.original; MIGRADO = [string]$d.migrado; SI_CAUSA = $siCausa; CAUSA = $fallo; OTRAS = ($otras -join "`n")
    RUTA_ORIGINAL = $LegacyRoot; SAL_ORIGINAL = $salOrig; SAL_MIGRADO = $salMig; ENTRADAS = $entradas; DIFF = ''
  }
  $e = [pscustomobject]@{ job = $C.job; caso = $C.caso; clave = $C.clave; copia = $CopiaMig; dirs = @($LegacyRoot, $salOrig, $salMig, $entradas); huella = (Get-Hash8 ((Get-Plantilla 'reparar') + '|' + $id)); prompt = $prompt }
  $t = New-TareaTipo 'reparar' $id '' "prueba-local/reparar/$id" $e
  # Puente de M43: hasta M43 el id llevaba el HEAD en vez del codigo del migrado. Una tarea guardada con ese id del HEAD de ahora (y la plantilla de
  # ahora: su huella la lleva) es del mismo codigo: se guarda con el id nuevo, con su veredicto, y Restore-Tarea la reutiliza. Quitalo cuando ningun
  # batch tenga tareas de reparar de antes de M43 (con otro HEAD no vale: no se sabe si el codigo era el mismo).
  $idViejo = 'reparar-' + (Get-Hash8 "$headMig|$resto")
  $viejo = Get-TareaGuardada $idViejo
  if ($idViejo -cne $id -and $viejo -and -not (Get-TareaGuardada $id) -and $viejo.entradas.huella -ceq (Get-Hash8 ((Get-Plantilla 'reparar') + '|' + $idViejo))) {
    $viejo.id = $id
    $viejo.salida = $t.salida
    $viejo.entradas = $e
    Save-Tarea $viejo
  }
  $t = Restore-Tarea $t $true
  $t.entradas.copia = $CopiaMig   # la de ahora, aunque la tarea venga de otro lanzamiento
  return $t
}

# Ejecuta en la copia la suite de tests unitarios, sin el arnes ni la regresion (Surefire sin **/PruebaLocalTest* ni **/RegresionLocalTest*,
# que solo valen tras el arnes, y sin parar por los fallos), y cuenta lo
# que dicen sus TEST-*.xml: Fallos (failures + errors), Ejecutados (tests - skipped), Nombres (los tests que fallan) y Mensaje (por que falla el primero:
# la primera linea de su message o, si esta vacio, la primera con texto del cuerpo de su <failure> o <error>; 300 letras como mucho; '' si no dice nada).
# Con Motivo, Maven no ha podido (no compila, se paso del tope...).
function Measure-Tests([string]$Que) {
  $excluir = Join-Path $Local 'reparar-excluir.txt'
  [System.IO.File]::WriteAllText($excluir, "**/PruebaLocalTest*`n**/RegresionLocalTest*`n", $Utf8)
  $informes = Join-Ruta $CopiaMig 'target/surefire-reports'
  Remove-Carpeta $informes
  $r = Invoke-Maven $CopiaMig $false @('test', "-Dsurefire.excludesFile=$excluir", '-Dmaven.test.failure.ignore=true') $Que
  $m = [pscustomobject]@{ Motivo = ''; Fallos = 0; Ejecutados = 0; Nombres = @(); Mensaje = '' }
  if ($r.Codigo -ne 0 -or $r.Tope) { $m.Motivo = "Los tests unitarios no se pueden ejecutar. Maven dice:`n" + (Get-FalloMaven $r); return $m }
  if (-not (Test-Path -LiteralPath $informes)) { return $m }
  foreach ($f in @(Get-ChildItem -LiteralPath $informes -File -Filter 'TEST-*.xml')) {
    $x = ([xml][System.IO.File]::ReadAllText($f.FullName, $Utf8)).DocumentElement
    $m.Fallos += [int]$x.GetAttribute('failures') + [int]$x.GetAttribute('errors')
    $m.Ejecutados += [int]$x.GetAttribute('tests') - [int]$x.GetAttribute('skipped')
    foreach ($t in @($x.SelectNodes('testcase[failure or error]'))) {
      $m.Nombres += ($t.GetAttribute('classname') + '.' + $t.GetAttribute('name'))
      if ($m.Nombres.Count -eq 1) {
        $fe = $t.SelectSingleNode('failure | error')
        $texto = $fe.GetAttribute('message')
        if (-not $texto.Trim()) { $texto = $fe.InnerText }
        $primera = @(@($texto -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -First 1)
        if ($primera.Count -gt 0) { $m.Mensaje = $primera[0].Trim() }
        if ($m.Mensaje.Length -gt 300) { $m.Mensaje = $m.Mensaje.Substring(0, 300) }
      }
    }
  }
  return $m
}

# Que hay peor en $Despues que en $Antes (dos resultados del mismo caso, que se podia ejecutar): '' si nada; si no, como y cual.
function Get-Empeora($Antes, $Despues) {
  $caso = "$($Antes.job)/$($Antes.caso)"
  if (-not (Test-Ejecutable $Despues)) { return "El caso $caso ya no se puede ejecutar ($($Despues.resultado)): $(Get-Resumen $Despues.motivo)" }
  $viejas = @(Get-Claves $Antes)
  $nueva = @($Despues.diferencias | Where-Object { $viejas -cnotcontains $_.clave })[0]
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

# Pasa lo que ha dejado la IA en la copia tras la llamada $Ll de la tarea $T por las puertas, de la mas barata a la mas cara (el caso de la
# tarea, los tests unitarios y, por ultimo, los demas casos: son un Maven cada uno). Devuelve:
# Tipo ('rechazado', 'no se arregla' o 'bien'), Motivo, ConDiff (si hay un diff que ensenar en el reintento: no, si fallo la llamada) y,
# si es bueno, Nuevos (los resultados medidos de ahora, por posicion en $S.Res). Las salidas medidas quedan en salidas\reparar\<n>.
function Test-Arreglo($T, $Ll, $S) {
  $v = [pscustomobject]@{ Tipo = 'rechazado'; Motivo = ''; ConDiff = $true; Nuevos = @{}; Deshecho = '' }
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
  # 3. algo cambiado en src/main/ (lo nuevo fuera de src/ lo ha dejado la ejecucion del batch: se quita y no cuenta; lo que la IA cambio fuera
  #    de src/main/ se deshace y se sigue con lo que quede)
  $ruido = @(Remove-NuevosFueraDeSrc $CopiaMig)
  if ($ruido.Count -gt 0) {
    $nombres = (@($ruido | Select-Object -First 5) -join ', ')
    if ($ruido.Count -gt 5) { $nombres += " y $($ruido.Count - 5) mas" }
    Info "Quito lo que ha dejado la ejecucion fuera de src/: $nombres"
  }
  $v.Deshecho = Undo-Fuera $CopiaMig @(Get-Cambios $CopiaMig) @('src/main/')
  if (@(Get-Cambios $CopiaMig).Count -eq 0) { $v.Motivo = 'No has cambiado ningun fichero de src/main/.'; return $v }
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
  # 5. la suite de tests unitarios: ni mas fallos ni menos tests que al empezar (antes que los demas casos: cada uno es un Maven, y la suite
  #    tarda mucho menos que todos ellos juntos)
  $t = Measure-Tests "reparar $($S.N), tests unitarios"
  if ($t.Motivo) { $v.Motivo = $t.Motivo; return $v }
  if ($t.Fallos -gt $S.Base.Fallos) {
    $v.Motivo = 'Tu cambio arregla el caso, pero rompe estos tests (esperan el comportamiento de ahora?): ' + (@($t.Nombres | Select-Object -First 5) -join ', ') + ". Fallan $($t.Fallos) y antes fallaban $($S.Base.Fallos)."
    if ($t.Mensaje) { $v.Motivo += " El primero falla con: $($t.Mensaje)." }
    return $v
  }
  if ($t.Ejecutados -lt $S.Base.Ejecutados) { $v.Motivo = "Con tu cambio se ejecutan menos tests unitarios: $($t.Ejecutados) y antes eran $($S.Base.Ejecutados)."; return $v }
  # 6. todos los demas casos que se pueden ejecutar: ninguno peor
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
  $i = Get-IndiceCaso $S.Res $C.job $C.caso
  $r = $S.Res[$i]
  $t = Get-TareaReparar $C $r $S
  $o = [ordered]@{ clave = $C.clave; job = $C.job; caso = $C.caso; casos = $C.casos; resultado = 'no arreglado'; commit = ''; asunto = ''; intentos = 0; motivo = '' }
  if ($t.estado -eq 'atascada') {
    $o.intentos = $t.intentos
    if ($t.ultimoEstado -eq 'no se arregla') { $o.resultado = 'no se arregla'; $o.motivo = $t.motivo } else { $o.motivo = "ya probado con este codigo del migrado: $($t.motivo)" }
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
        $donde = "$($C.job)/$($C.caso) $($C.clave) en el commit $($o.commit.Substring(0, 7))"
        if (@(Get-Claves $S.Res[$i]) -ccontains $C.clave) { $o.resultado = 'mejorado'; Aviso "Mejorado ${donde}: sigue distinta, con menos lineas." }
        else { Bien "Arreglado $donde." }
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
    if ($v.Deshecho) { $v.Motivo = "$($v.Deshecho) $($v.Motivo)" }
    Set-Intento $t $v.Motivo
    Aviso "Arreglo de $($C.job)/$($C.caso) rechazado (intento $($t.intentos) de $($Cfg.Intentos)): $(($v.Motivo -split "`n")[0])"
  }
  $o.intentos = $t.intentos; $o.motivo = $t.motivo
  return $o
}

# Los resultados de $S.Res que -Reparar puede arreglar: todos menos los de los casos de $S.Saltar ('job<tab>caso': su original no arranca).
function Get-Reparables($S) { return @($S.Res | Where-Object { $S.Saltar -cnotcontains "$($_.job)`t$($_.caso)" }) }

# Con -Reparar y casos distintos: arregla las claves, de la que tiene mas casos a la que menos, hasta MaxReparaciones, y deja en $Res (en su
# sitio) lo medido tras el ultimo arreglo bueno, cuyas salidas pasan a ser las del migrado. Devuelve las entradas de reparaciones.
function Invoke-Reparaciones($Res) {
  Info ''
  Info "Reparando en la rama de rescate ($(Get-Rama $DirRama)): hasta $($Cfg.MaxReparaciones) claves de diferencia, con $($Cfg.Intentos) intentos cada una..."
  # Con estado=EXCEPCION en el original el job ni arranca: no hay salida que copiar. Esos casos no se reparan y su resultado no cambia.
  $saltar = @($Res | Where-Object { $_.resultado -eq 'distinto' -and (Get-Excepcion (Join-Ruta $Local "salidas/original/$($_.job)/$($_.caso)")) } | ForEach-Object { "$($_.job)`t$($_.caso)" })
  if ($saltar.Count -gt 0) { Info "Salto $($saltar.Count) caso(s) distinto(s) cuyo original da estado=EXCEPCION: el job no arranca en el original y no hay salida que copiar." }
  # Con un fichero que no se pudo guardar en salidas tampoco: la diferencia es de la ruta y no del codigo del migrado, y no hay salida que copiar.
  $sinGuardar = @($Res | Where-Object { $_.resultado -eq 'distinto' -and @($_.diferencias | Where-Object { $_.noGuardado }).Count -gt 0 } | ForEach-Object { "$($_.job)`t$($_.caso)" } | Where-Object { $saltar -cnotcontains $_ })
  if ($sinGuardar.Count -gt 0) { Info "Salto $($sinGuardar.Count) caso(s) distinto(s) con un fichero que no se ha podido guardar en salidas: no hay salida que comparar ni copiar." }
  $saltar = @($saltar) + @($sinGuardar)
  if (@($Res | Where-Object { $_.resultado -eq 'distinto' }).Count -eq $saltar.Count) { return @() }
  Remove-Carpeta (Join-Ruta $Local 'salidas/reparar')
  Save-Copia $CopiaMig   # la copia ya lleva el arnes y los casos que dejo Invoke-Migrado: son su base
  $base = Measure-Tests 'tests unitarios de partida'
  if ($base.Motivo) { Aviso "No reparo nada: no he podido medir los tests unitarios de partida. $($base.Motivo)"; return @() }
  Info "Tests unitarios de partida: $($base.Ejecutados) ejecutados, $($base.Fallos) fallan."
  $s = [pscustomobject]@{ Res = $Res; Salidas = 'migrado'; N = 0; Base = $base; Probadas = @{}; Saltar = $saltar }
  $reps = @()
  while ($s.Probadas.Count -lt [int]$Cfg.MaxReparaciones) {
    $c = Find-Clave (Get-Reparables $s) $s.Probadas
    if (-not $c) { break }
    $s.Probadas[$c.clave] = $true
    $reps += , (Repair-Clave $c $s)
  }
  $quedan = @(@(Get-Reparables $s | Where-Object { $_.resultado -eq 'distinto' } | ForEach-Object { Get-Claves $_ }) | Where-Object { -not $s.Probadas.ContainsKey($_) } | Select-Object -Unique)
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
    elseif ($r.resultado -eq 'mejorado') { Aviso "  mejorado: $donde en $($r.commit.Substring(0, 7)) ($($r.asunto))" }
    elseif ($r.resultado -eq 'no se arregla') { Aviso "  no se arregla: ${donde}: $motivo" }
    else { Fallo "  no arreglado: ${donde}: $motivo" }
  }
}

# ================================ RESULTADO ================================
# Los jobs donde ningun caso deja nada distinto del caso vacio del arnes (el aviso de Get-Resultado) y ninguno sale distinto ni no
# determinista: el test no le pasa las entradas al job y lo que sale igual no se ha probado: sus casos pasan a 'no se pudo preparar' ($MotivoSinEntradas), no a un fallo
# que pare la prueba, y los tests guardados no se tocan. Los casos sin probar o sin preparar no cuentan. Si solo algunos casos del job salen como el vacio, el job no
# esta aqui: sigue como siempre, con el aviso en cada uno.
function Get-JobsVacios($Res) {
  $vacios = @()
  foreach ($j in @($Res | ForEach-Object { $_.job } | Select-Object -Unique)) {
    $comparados = @($Res | Where-Object { $_.job -ceq $j -and @('igual', 'distinto', 'no determinista') -contains $_.resultado })
    if ($comparados.Count -gt 0 -and @($comparados | Where-Object { $_.resultado -ne 'igual' -or $_.motivo -ne $MotivoVacio }).Count -eq 0) { $vacios += $j }
  }
  return $vacios
}

# Lo que se dice de un job de Get-JobsVacios: a la IA, al rehacer su test (Get-PrevioArnes), y al usuario, al final de la consola (con lo que puede hacer).
function Get-FraseSinEntradas([string]$Job) {
  return "En $Job, ningun caso deja nada distinto del caso vacio: el test no le pasa las entradas al job."
}

# Por job: sus casos, iguales, distintos y sin probar y, si no arranca o falla igual en todos sus casos, 'falloIgual' (para quien lea el json despues): el lado (original o
# migrado), el estado, la clase de la excepcion (Get-ClaseFallo), la causa del primer caso, la regla del paso de calidad si es un error del codigo del migrado
# (Get-ErrorCodigo) y si no se ejecutaron todos sus casos ('parado': Invoke-Originales dejo los demas sin probar, o su test del migrado no arranca y solo se ejecuto el
# primero, o el migrado fallo igual en los primeros casos y Invoke-Salidas dejo los demas sin probar). Son los jobs de Get-JobsFalloOriginal, los de Get-JobsMigradoNoArranca con
# un error del codigo y los que Invoke-Salidas paro porque el migrado falla igual ($script:ParadaMigrado: el estado, la clase y la causa de su primer caso).
function Get-PorJob($Res, $Grupos) {
  $originales = @(Get-JobsFalloOriginal $Res)
  $migrados = @(Get-JobsMigradoNoArranca $Res $Grupos | Where-Object { $_.error })
  $porJob = @()
  foreach ($p in $pruebas) {
    $rs = @($Res | Where-Object { $_.job -ceq $p.job })
    $ig = @($rs | Where-Object { $_.resultado -eq 'igual' }).Count
    $di = @($rs | Where-Object { $_.resultado -eq 'distinto' }).Count
    $o = [ordered]@{ job = $p.job; casos = $rs.Count; iguales = $ig; distintos = $di; sinProbar = ($rs.Count - $ig - $di) }
    $orig = @($originales | Where-Object { $_.job -ceq $p.job })[0]
    $mig = @($migrados | Where-Object { $_.job -ceq $p.job })[0]
    if ($orig) { $o.falloIgual = [ordered]@{ lado = 'original'; estado = $orig.fallo.estado; clase = (Get-ClaseFallo $orig.fallo); causa = [string]$orig.fallo.causa; parado = $script:ParadaOriginal.ContainsKey($p.job) } }
    elseif ($mig) { $o.falloIgual = [ordered]@{ lado = 'migrado'; estado = 'EXCEPCION'; clase = $mig.clase; causa = $mig.causa; regla = $mig.error.regla; parado = ($script:NoArranca.ContainsKey($p.job) -or $script:ParadaMigrado.ContainsKey($p.job)) } }
    elseif ($script:ParadaMigrado.ContainsKey($p.job)) { $f = $script:ParadaMigrado[$p.job]; $o.falloIgual = [ordered]@{ lado = 'migrado'; estado = $f.estado; clase = (Get-ClaseFallo $f); causa = [string]$f.causa; parado = $true } }
    $porJob += $o
  }
  return $porJob
}

# Las entradas de $Nuevas para el job de -Job y las de $Viejas para los demas, en el orden de $todosJobs.
function Join-PorJob($Nuevas, $Viejas) {
  $r = @()
  foreach ($j in $todosJobs) {
    $de = $Viejas
    if ($j -ceq $Job) { $de = $Nuevas }
    $r += @(@($de) | Where-Object { $null -ne $_ -and $_.job -ceq $j })
  }
  return $r
}

# Con -Job: $O (lo de este lanzamiento) mas lo de los otros jobs del prueba-local.json de antes (casos, jobs, reparaciones y culpables),
# si se probaron con el mismo commit del migrado y del original. Con otro, se descartan y se dice: se probaron con otro codigo.
function Merge-OtrosJobs($O) {
  $antes = Get-JsonPrueba
  if (-not $antes -or @($antes.jobs | Where-Object { $null -ne $_ -and $_.job -cne $Job }).Count -eq 0) { return $O }
  if ($antes.commitMigrado -cne $O.commitMigrado -or $antes.commitOriginal -cne $O.commitOriginal) {
    Info 'Los otros jobs se probaron con otro commit: no los guardo. Lanza sin -Job para probarlos todos.'
    return $O
  }
  $f = [ordered]@{}
  foreach ($k in $O.Keys) { $f[$k] = $O[$k] }
  foreach ($k in @('casos', 'jobs', 'reparaciones', 'culpables')) {
    $m = @(Join-PorJob $O[$k] $antes.$k)
    if ($m.Count -gt 0 -or $O.Contains($k)) { $f[$k] = $m }
  }
  # Los grupos (grupos[] y el 'grupo' de cada caso) son solo de este lanzamiento, de los casos de -Job: el 'grupo' de un caso de otro job que se
  # conserva apuntaria a un grupo de otro lanzamiento.
  foreach ($c in @($f.casos | Where-Object { $_.job -cne $Job })) { [void]$c.PSObject.Properties.Remove('grupo') }
  return $f
}

# Escribe datos\prueba-local.json con $Res (y, con -Desde, los culpables; con -Reparar, las reparaciones) y devuelve lo de este lanzamiento. Con -Rapida lo escribe en
# datos\prueba-local-rapida.json ($NombreJson) y deja prueba-local.json como esta.
# Con -Job, el fichero lleva ademas lo de los otros jobs (Merge-OtrosJobs); lo devuelto, solo lo de ahora: es lo que ensena la consola.
function Save-Resultado($Res, $Culpables, $Reparaciones = @()) {
  $grupos = @(Get-Grupos $Res)
  $codigo = Get-CodigoMigrado $headMig
  $hash = Get-Hash8 (Get-HashCarpeta (Join-Ruta $Local 'arnes/migrado'))
  Add-Hechos $grupos $Res $codigo $hash
  $numero = New-Object System.Collections.Hashtable ([System.StringComparer]::Ordinal)
  foreach ($g in $grupos) { foreach ($c in @($g.casos)) { $numero[$c] = $g.numero } }
  foreach ($r in @($Res)) {
    $r.Remove('grupo')
    if ($numero.ContainsKey($r.job + '/' + $r.caso)) { $r['grupo'] = $numero[$r.job + '/' + $r.caso] }
  }
  $o = [ordered]@{
    version = 1; original = $LegacyRoot; commitOriginal = $HeadOrig; migrado = $MigradoRoot; commitMigrado = $headMig; codigoMigrado = $codigo; hashArnesMigrado = $hash
    modelo = $ModeloElegido; inicio = $Inicio.ToString('s'); fin = (Get-Date).ToString('s'); minutos = [Math]::Round($reloj.Elapsed.TotalMinutes, 1); llamadas = $script:Llamadas
    arneses = [ordered]@{ original = $ArnesOrig.estado; migrado = $ArnesMig.estado }; jobs = @(Get-PorJob $Res $grupos); casos = $Res; grupos = $grupos; noPromete = $NoPromete
  }
  if ($Desde) { $o.culpables = @($Culpables | ForEach-Object { [ordered]@{ job = $_.job; caso = $_.caso; commit = $_.commit; asunto = $_.asunto; deshecho = $_.deshecho } }) }
  if ($Reparar) { $o.reparaciones = @($Reparaciones) }
  $f = $o
  if ($Job -and -not $Rapida) { $f = Merge-OtrosJobs $o }
  Write-Json (Join-Path $DatosMig $NombreJson) $f
  return $o
}

# ================================= MAIN =================================
$reloj = [System.Diagnostics.Stopwatch]::StartNew()
$Inicio = Get-Date
if (-not $Legacy) { Stop-Arranque 'Falta -Legacy: la carpeta del batch original.' }
if ($Reparar -and ($Desde -or $Deshacer)) { Stop-Arranque '-Reparar no se combina con -Desde ni con -Deshacer: o buscas el commit que rompe un caso, o arreglas lo que venia mal de la migracion.' }
if ($Rapida -and ($Reparar -or $Regresion -or $Desde)) { Stop-Arranque '-Rapida no se combina con -Reparar, -Regresion ni -Desde: la prueba rapida solo ejecuta el primer caso de cada job y no deja resultado para -Cierre, y esas opciones necesitan todos los casos.' }
$NombreJson = 'prueba-local.json'   # donde deja su resultado: con -Rapida otro, para no pisar el que lee -Cierre
if ($Rapida) { $NombreJson = 'prueba-local-rapida.json' }
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
$casosEnTotal = @($pruebas | ForEach-Object { @($_.casos) } | Where-Object { $_ }).Count
if ($casosEnTotal -eq 0) { Stop-Arranque 'Los guiones de migracion.ps1 no traen ningun caso que probar.' }
if ($Rapida) { foreach ($unJob in $pruebas) { $unJob.casos = @(@($unJob.casos) | Select-Object -First 1) } }
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
if ($Regresion -and (Get-MotivoRegresion $hayRescate)) { Stop-Arranque (Get-MotivoRegresion $hayRescate) }
$intocables = @($LegacyRoot, $MigradoRoot)
if ($hayRescate) { $intocables += $dirRescate }
if ($PlantillaRoot) { $intocables += $PlantillaRoot }
$H0 = @($intocables | ForEach-Object { Get-Huella $_ })

$script:Llamadas = 0
$script:Racha = 0
$script:Mavens = 0
$script:Maven = @{}
$script:NoGuardados = @{}   # por (lado|job|caso): los ficheros que no se pudieron guardar en salidas (Copy-Salida)
$script:NoArranca = @{}   # por job: su test del migrado se rechazo porque con el caso vacio el migrado no arranca y el original si, y se acepto en el ultimo intento (clase, veces escrito)
$script:ParadaOriginal = @{}   # por job: el fallo del primero de los casos (Get-FalloLado) de un job cuyos primeros casos fallan igual en el original y que por eso no ejecuta los demas (Invoke-Originales)
$script:ParadaMigrado = @{}   # por job: el fallo del primero de los casos (Get-FalloLado) de un job cuyos primeros casos fallan igual en el migrado y que por eso no ejecuta los demas (Invoke-Salidas)
$script:SinProbar = @{}   # por (lado|job|caso): el motivo de un caso que no se ha ejecutado porque su job no arranca con ese test (Invoke-Salidas)
$script:AvisoCarpetaCorta = $false   # la sugerencia de una carpeta mas corta sale una sola vez
$script:ConRed = @{}    # las copias que ya han hecho un caso con red porque sin ella Maven no llegaba al test: siguen con red (Invoke-Job)
$script:Tiempos = @()   # una fila por Maven de un caso (y por test-compile de una copia) en este lanzamiento (Invoke-MavenCaso); Save-Tiempos las guarda
$script:Compilada = @{}   # por copia: la huella de su src\ y su pom.xml con la que se compilo por ultima vez para los casos en modo directo (Invoke-Compilar)
$script:ConCiclo = @{}   # las copias donde un caso no se pudo ejecutar con surefire:test: siguen con mvn test el resto del lanzamiento (Invoke-Job)
$script:ArgLineVacio = @{}   # las copias donde surefire:test dejo @{argLine} sin sustituir: sus casos van con -DargLine= (Invoke-Job)
$script:InventarioOrig = $null   # las tablas que usa el codigo del original (Get-TablasBatch), la primera vez que hacen falta (Get-MotivoBase)
$script:SitiosColumna = @{}   # por (copia|COLUMNA): el sitio donde el codigo la nombra o '' (Get-SitioColumna)
$script:Estados = @{}   # -Desde: lo visto por (commit|job|caso), para no repetir ejecuciones
$script:Propios = @()   # los commits que ha hecho en $DirRama: los reverts de -Deshacer y los arreglos de -Reparar
$script:Arbol = $null   # el arbol de dependencias del migrado (Get-ArbolDependencias), la primera vez que un grupo lo pide
$script:Anterior = Get-JsonPrueba   # el prueba-local.json de antes de este lanzamiento: Save-Resultado lo pisa y Add-Hechos lo compara
$script:VueltaAlDeAntes = ''   # el aviso de que el test nuevo del original quedaba peor y se vuelve al de antes (Test-ArnesEscrito); '' si no
$script:MigradoPorOriginal = $false   # el test del migrado se escribe otra vez solo porque cambia el del original, no porque se pida (-RehacerArnes): si el del original vuelve al de antes, vuelve tambien el suyo
$script:Anteriores = @{}   # por lado (original, migrado): hay un test de antes en arnes-anterior con el que comparar el que se escribe otra vez en este lanzamiento (Save-Anterior)
try {
  if (-not (Set-Despierto $true)) { Aviso 'No he podido pedir a Windows que no suspenda el equipo: si lo dejas solo, compruebalo.' }
  # 1. Copias desechables y que compilen
  $CopiaOrig = $LegacyRoot + '-prueba-local'
  $CopiaMig = $MigradoRoot + '-prueba-local'
  $HeadOrig = Get-Head $LegacyRoot
  $headMig = Get-Head $MigradoRoot
  if ($hayRescate) { $headMig = Get-Head $dirRescate; Info "El migrado se prueba en el ultimo commit de su rama de rescate ($(Get-Rama $dirRescate))." }
  foreach ($x in @(@($LegacyRoot, $HeadOrig), @($DirRama, $headMig))) { Write-AvisoSinCommit $x[0] $x[1] }
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
  $PomOriginal = ''   # el pom.xml del original tal cual (leido como fichero, no por git): Repair-PomSoloTest
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
  $rehacer = @{ original = [bool]$RehacerOriginal; migrado = [bool]$RehacerArnes }   # los que se escriben otra vez sin pasar por Use-ArnesGuardado
  $testOriginal = ''   # donde va el test del original: el del migrado lo traduce
  foreach ($x in @(@('original', $CopiaOrig), @('migrado', $CopiaMig))) {
    $test = Get-RutaTest $x[1]
    if (-not $test) { Stop-Arranque "No encuentro en el $($x[0]) la clase con @SpringBootApplication (en src/main/java): el test PruebaLocalTest va en su paquete." }
    $antes = Get-TareaGuardada ('arnes-' + $x[0])   # la de antes de este lanzamiento: Get-TareaArnes la pisa
    $t = Get-TareaArnes $x[0] $x[1] $test $todosJobs $testOriginal
    # El test guardado se escribio con otra plantilla: se escribe otra vez, como con -RehacerArnes pero sin que lo pida nadie. Una sola Info:
    # ninguna si ya se rehace el del migrado (-RehacerArnes) y, con el original viejo, la del original y no la del migrado.
    if (-not $rehacer[$x[0]] -and (Test-PlantillaVieja $t)) {
      if (-not $rehacer.migrado -and $x[0] -eq 'original') { Info 'La plantilla del test ha cambiado desde que se escribio el del original: escribo otra vez los dos (el del migrado traduce el nuevo).' }
      if (-not $rehacer.migrado -and $x[0] -eq 'migrado') { Info 'La plantilla del test ha cambiado desde que se escribio el del migrado: lo escribo otra vez traduciendo el del original.' }
      $rehacer[$x[0]] = $true
    }
    # Lo que se rehace vuelve a empezar sin pasar por Use-ArnesGuardado; lo guardado pasa a arnes-anterior tras la pregunta
    if ($rehacer[$x[0]]) { $t.estado = 'pendiente'; $t.intentos = 0; $t.motivo = ''; $t.ultimoEstado = '' }
    elseif (Test-Path -LiteralPath (Join-Ruta $Local "arnes/$($x[0])")) { Use-ArnesGuardado $t $todosJobs }
    # Si el del original no queda hecho (la plantilla, o ya no vale en este commit), se escribe otra vez y el del migrado guardado tambien: lo
    # traduce (Use-ArnesGuardado lo daria por bueno aunque cambie el test del original). Sin migrado guardado no hay que dejar de fiarse de nada:
    # su tarea sigue por su intento y su motivo, como hoy.
    if ($x[0] -eq 'original' -and $t.estado -ne 'hecha' -and (Test-Path -LiteralPath (Join-Ruta $Local 'arnes/migrado'))) {
      $script:MigradoPorOriginal = -not $rehacer.migrado
      $rehacer.migrado = $true
    }
    if ($t.estado -ne 'hecha') {   # el que se va a escribir sabe, en su primer intento, lo que fallo antes (Get-PrevioArnes)
      $t.entradas | Add-Member -NotePropertyName previo -NotePropertyValue (Get-PrevioArnes $t $antes) -Force
      Save-Tarea $t
    }
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
  Reset-CasosExcepcion $tareasCasos
  Reset-OriginalesYaExiste $tareasCasos
  $pendientes = @(@($arneses) + @($tareasCasos) | Where-Object { $_.estado -ne 'hecha' }).Count
  Info "Casos: $($tareasCasos.Count) de $($pruebas.Count) jobs; tareas de IA por hacer: $pendientes (las hechas en otro lanzamiento no se repiten)."
  if ($pendientes -gt 0 -and -not (Confirmar "Llamar a Copilot para esas $pendientes tareas?")) { Stop-Arranque 'No se ha hecho nada.' }
  foreach ($repo in @('original', 'migrado')) { if ($rehacer[$repo]) { Save-Anterior $repo } }

  # 3. Arneses (sin el del original no se sigue) y entradas de los casos (las hechas de antes, a la copia del original)
  $escribeOriginal = ($ArnesOrig.estado -ne 'hecha')
  Invoke-Arneses @($arneses | Where-Object { $_.estado -ne 'hecha' }) $todosJobs
  if ($ArnesOrig.estado -ne 'hecha') { Show-Atascado $ArnesOrig; exit 1 }
  Reset-CasosSinProbar $tareasCasos ($escribeOriginal -and -not $script:VueltaAlDeAntes)
  if ($ArnesMig.estado -ne 'hecha') { Show-Atascado $ArnesMig; Aviso 'Sigo con el original: los casos quedan hechos para el proximo lanzamiento.' }
  foreach ($t in @($tareasCasos | Where-Object { $_.estado -eq 'hecha' })) {
    $guardado = Join-Ruta $Local "casos/$($t.entradas.job)/$($t.entradas.caso)"
    if (-not (Test-Path -LiteralPath (Join-Path $guardado 'no-aplica.txt'))) { Copy-Carpeta $guardado (Join-Ruta $CopiaOrig $t.entradas.carpeta) }
  }
  Save-Copia $CopiaOrig
  Invoke-Casos @($tareasCasos | Where-Object { $_.estado -ne 'hecha' })

  # 4. Ejecutar: el original dos veces (salvo el que no ha cambiado) y el migrado una, con los mismos casos
  $listas = @($tareasCasos | Where-Object { $_.estado -eq 'hecha' -and -not (Test-Path -LiteralPath (Join-Ruta $Local "casos/$($_.entradas.job)/$($_.entradas.caso)/no-aplica.txt")) })
  Invoke-Originales $listas
  if ($ArnesMig.estado -eq 'hecha') { Invoke-Migrado 'migrado' $listas }

  # 5. Comparar y contar
  $res = @($tareasCasos | ForEach-Object { Get-Resultado $_ })
  $res = @(Confirm-OriginalesDeOtroDia $tareasCasos $res)
  $vacios = @(Get-JobsVacios $res)
  foreach ($r in @($res | Where-Object { $vacios -ccontains $_.job -and $_.resultado -ceq 'igual' -and $_.motivo -ceq $MotivoVacio })) { $r.resultado = 'no se pudo preparar'; $r.motivo = $MotivoSinEntradas }
  $o = Save-Resultado $res @()
  foreach ($g in @($o.grupos | Where-Object { -not $Rapida })) {   # una linea por grupo y lanzamiento (no de una -Rapida: son pocos casos): cuantas causas hay y de que clase
    $linea = [ordered]@{ fecha = (Get-Date).ToString('s'); numero = $g.numero; tipo = $g.tipo; firma = $g.firma; casos = @($g.casos).Count; hechos = @($g.hechos) }
    [System.IO.File]::AppendAllText((Join-Path $DatosMig 'prueba-local-grupos.jsonl'), ((ConvertTo-Json -InputObject $linea -Compress) + "`n"), $Utf8)
  }
  Show-Resultado $res $o.jobs $o.grupos

  # 6. Con -Desde: el commit que rompe cada caso distinto y, con -Deshacer, su git revert; el resultado y la salida son los de despues
  if ($Desde) {
    $culpables = @(Find-Culpables $res)
    if ($Deshacer) { Undo-Culpables $culpables $res }
    $o = Save-Resultado $res $culpables
    if ($Deshacer -and @($script:Propios).Count -gt 0) { Info ''; Info 'Despues de deshacer:'; Show-Resultado $res $o.jobs $o.grupos }
  }
  # 7. Con -Reparar: arregla la rama de rescate hasta que los casos distintos salgan iguales; el resultado y la salida son los de despues
  if ($Reparar) {
    $reparaciones = @()
    if (@($res | Where-Object { $_.resultado -eq 'distinto' }).Count -eq 0) { Info ''; Info 'Con -Reparar: no hay casos distintos que arreglar.' }
    elseif (Confirmar "Llamar a Copilot para arreglar hasta $($Cfg.MaxReparaciones) causas de los casos distintos (cada una, hasta $($Cfg.Intentos) llamadas)?") { $reparaciones = @(Invoke-Reparaciones $res) }
    else { Info ''; Info 'No se repara nada.' }
    $o = Save-Resultado $res @() $reparaciones
    if ($reparaciones.Count -gt 0) {
      if (@($reparaciones | Where-Object { $_.commit }).Count -gt 0) { Info ''; Info 'Despues de reparar:'; Show-Resultado $res $o.jobs $o.grupos }
      Show-Reparaciones $reparaciones
      if (@($reparaciones | Where-Object { $_.resultado -eq 'no se arregla' }).Count -gt 0) { Info 'Si la IA dice que la diferencia es del test del migrado y no del codigo, relanza con -RehacerArnes.' }
    }
  }
  # 8. Con -Regresion: los casos que salen iguales se quedan como tests en la rama de rescate (un commit); no cambia la salida
  if ($Regresion) { Invoke-Regresion $res }
  Info ''
  foreach ($c in @(@($PrefijoSinTabla, 'no crea sus tablas'), @($PrefijoTablaMal, 'crea mal sus tablas'), @($PrefijoSinColumna, 'no crea una columna que usa el codigo'))) {   # una linea por causa
    $n = @($res | Where-Object { $_.resultado -eq 'no se pudo preparar' -and $_.motivo.Contains($c[0]) }).Count
    if ($n -gt 0) { Aviso "$n caso(s) no se pudieron preparar porque el test del original $($c[1]): relanza con -RehacerOriginal." }
  }
  foreach ($f in @(Get-JobsFalloOriginal $res)) { Aviso (Format-LineaOriginal $f.job $f.fallo) }   # una linea por job donde el original falla igual en todos los casos
  Show-Tiempos
  if ($Rapida) { Info "Prueba rapida: $($res.Count) casos de $casosEnTotal. No vale para -Cierre: cuando salga igual, lanza sin -Rapida." }
  Info "Llamadas a Copilot: $($script:Llamadas). Tiempo: $($o.minutos) min. Resultado en $(Join-Path $DatosMig $NombreJson)"
  Info $NoPromete
  foreach ($v in $vacios) { Fallo ((Get-FraseSinEntradas $v) + ' Arreglalo en tus tests guardados (prueba-local\arnes\original y arnes\migrado) y relanza sin -Rehacer, o relanza con -RehacerOriginal para que la IA los escriba otra vez (el del original y, con el, el del migrado).') }

  # Lo que no se podia tocar sigue igual
  $H1 = @($intocables | ForEach-Object { Get-Huella $_ })
  if (@(0..($intocables.Count - 1) | Where-Object { -not (Test-MismaHuella $intocables[$_] $H0[$_] $H1[$_]) }).Count -gt 0) { Stop-Arranque ('Ha cambiado durante la prueba alguna de estas carpetas: ' + ($intocables -join ', ') + '. Miralo con git status y git diff.') }
  if ($vacios.Count -gt 0 -or @($res | Where-Object { $_.resultado -eq 'distinto' }).Count -gt 0) { exit 2 }
  if ($ArnesMig.estado -ne 'hecha' -or @($res | Where-Object { $_.resultado -eq 'igual' }).Count -eq 0) { exit 1 }
  exit 0
}
finally {
  Save-Tiempos
  [void](Set-Despierto $false)
}
