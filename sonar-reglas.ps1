# Reglas del paso sonar de rescate.ps1 (prompt general, recetas, mensajes que no se automatizan y puertas del diff). rescate.ps1 las carga como valores por defecto.
# Cada una se puede sustituir en .rescate/config.json con SonarPrompt, SonarRecetas, SonarNoAutomatizar y SonarProhibido. Solo ASCII.
# Generado por m10/genera-cfg.py desde m10/sonar-recetas.md (Fable, 18-11). No editar a mano: regenerar.
$SonarPromptReal = @'
Corrige cada incidencia de Sonar listada (fichero, linea, mensaje). Hay UNA regla dura: NO cambies la logica de negocio. Mismos calculos, mismos datos leidos y escritos, mismos errores (que se lanza y que se captura), misma transaccion y mismos nombres de todo lo que se lee por nombre: propiedades de las clases de datos (BeanPropertyRowMapper, BeanWrapperFieldSetMapper, Jackson, @ConfigurationProperties), nombres de bean y claves de yml.
Todo lo demas se puede cambiar para arreglarla de verdad: extraer metodos, cambiar firmas adaptando TODAS las llamadas (buscalas en el repo, en main y en test) y crear clases nuevas, cada una en un fichero nuevo del mismo paquete. Que el arreglo sea grande o toque varios ficheros no es motivo para dejarla.
Una clase nueva es una clase normal, no un bean: sin anotaciones de Spring y sin @Transactional; quien la usa la crea con new. No anadas anotaciones de Spring ni quites o muevas las que hay, salvo que una receta lo diga. Un metodo con anotaciones (@Transactional, @Bean, @Scheduled, @BeforeStep...) se queda en su clase con su nombre y sus anotaciones; su cuerpo si puede salir a otro metodo.
Antes de tocar, lee el metodo entero; si cambias un campo, un constructor o una firma, lee tambien la clase y quien la usa.
El mensaje dice el sintoma, no siempre el arreglo correcto. Si abajo hay una RECETA para ese mensaje, siguela. Si no la hay, aplica el cambio que quite la causa.
Arregla lo listado y nada mas: no reformatees, no reordenes y no renombres lo que la incidencia no pide.
No cambies que pasa con null, con colecciones vacias ni con errores: no anadas if que salten codigo en silencio, valores por defecto, catch ni throw nuevos. &&, || y ?: solo evaluan lo necesario: no saques a una variable una parte que hoy no se ejecuta siempre.
No guardes en campos lo que hoy es una variable local ni crees campos static que cambian: es estado compartido entre llamadas y entre hilos.
Trampas prohibidas: NOSONAR, @SuppressWarnings, @Generated o excluir ficheros; cambiar el problema de sitio sin arreglarlo (trozos sin sentido propio como Parte1 y Parte2, un objeto saco); reescribir o renombrar para que Sonar no lo reconozca; un uso falso para algo sin uso; comentarios de relleno; borrar, desactivar o relajar tests.
Tests: adapta los que dejen de compilar por tu cambio, sin tocar lo que comprueban. No anadas tests salvo que la incidencia sea de un test.
APUNTA una incidencia, sin tocarla, SOLO si no hay forma de arreglarla sin cambiar la logica de negocio, o si pide una decision de negocio (cual era la intencion, que hacer cuando falta un dato, que error lanzar). Las recetas dicen en que casos.
Apuntarla es dejarla como esta y anadir una linea al final de .rescate/sonar-sin-arreglar.txt (crealo si no existe; no borres lo que tenga): <ruta>:<linea> | <motivo en una frase>, con la ruta y la linea de la lista. Despues arregla las demas.
'@
$SonarRecetasReal = @(
  # 1. complejidad
  @{ Nombre = 'complejidad'; Rx = '^(Refactor this method to reduce its Cognitive Complexity|The Cyclomatic Complexity of this method|This method has \d+ lines, which is greater|Refactor this code to not nest more than \d+|Reduce this (switch case|lambda expression) number of lines|Extract this nested try block)'; Avisar = $false; Texto = @'
Extrae a metodos private bloques completos con un solo proposito: el cuerpo de un bucle, una rama larga de un if, un case, el cuerpo de un try o de una lambda. Repite hasta que el metodo marcado y los nuevos queden bajo el limite del mensaje, aunque salgan muchos metodos.
Mismo orden de llamadas y mismas condiciones: no las inviertas ni las fusiones, no anadas return ni else, no cambies bucles por streams.
Bloque que calcula UN valor: el metodo lo devuelve. Bloque que cambia varias variables locales: devuelve un record nuevo con ellas y asignalas a la vuelta, o extrae trozos mas pequenos que cambien una sola.
Un break, un continue o un return del metodo original se queda donde esta: extrae lo que va antes o despues.
Metodo extraido: private; static si no usa la instancia; nombre con verbo que diga que hace; el mismo throws que necesitaba el bloque. Si recibe muchos parametros, agrupa en un record los que viajan juntos.
Trampa: pasar variables locales a campos para poder extraer crea estado compartido. Partir el metodo en parte1 y parte2, o llevarlo entero a otra clase, no arregla nada.
'@ }
  # 2. constantes
  @{ Nombre = 'constantes'; Rx = '^(Define a constant instead of duplicating this (literal|text block)|Use already-defined constant|Assign this magic number)'; Avisar = $false; Texto = @'
Crea una constante private static final en la misma clase, junto a las demas, y usala donde el valor significa lo mismo. Si el mensaje nombra una constante que ya existe, usa esa.
Mismo tipo y mismo valor exacto que el literal: 12 es int, 12L long, 12.0 double; un texto, con sus espacios y mayusculas.
El nombre dice que significa en este codigo (MESES_POR_EJERCICIO, COLUMNA_IMPORTE, SEPARADOR_CSV), nunca el valor (DOCE, NUM_12, TEXTO_1). Sacalo de donde se usa: la columna, el campo, la clave o el mensaje al que pertenece.
Dos literales iguales con significados distintos son dos constantes.
Trampa: cambiar el tipo (int por long o double) cambia divisiones y desbordamientos. Una constante con nombre de numero no arregla nada.
'@ }
  # 3. sin-uso
  @{ Nombre = 'sin-uso'; Rx = '(^Remove (this|these) (unused|useless assignment)|Dead store to .+ in |^Unread field:)'; Avisar = $false; Texto = @'
Borra lo que no se usa. Si lo que se asignaba, se inicializaba o se pasaba como argumento es una llamada a un metodo, deja la llamada sola como sentencia: puede tener efectos.
Valor inicial que siempre se pisa (int n = 0;): deja la declaracion sin valor (int n;).
Parametro sin uso: quitalo de la firma y de TODAS las llamadas, en main y en test. Si el metodo es @Override o lo llama Spring (lleva anotaciones), su firma no la decides tu: apuntala.
Campo asignado en el constructor desde un parametro: quita tambien el parametro y adapta todos los new, en main y en test.
Campo o metodo con anotaciones, o usado por nombre desde XML, yml o reflexion: apuntala; alguien lo lee por su nombre.
Trampa: borrar la llamada junto con la variable quita un efecto (rs.next(), it.next(), repo.save()). Anadir un uso falso (un log, x = x) es trampa.
'@ }
  # 4. logs
  @{ Nombre = 'logs'; Rx = '(Invoke method\(s\) only conditionally|Use the built-in formatting to construct this argument|Format specifiers should be used instead of string concatenation|^Replace this use of System\.(out|err) by a logger)'; Avisar = $false; Texto = @'
Concatenacion en un log: pasa a plantilla con {} y argumentos, mismo texto y mismo orden: log.info("Leidos " + n) -> log.info("Leidos {}", n).
Si el ultimo argumento es la excepcion, dejala la ultima y sin {} para ella: asi se sigue escribiendo la traza.
Invoke method(s) only conditionally: si las llamadas del argumento no tienen efectos (getters, calculos), mete el log en if (log.isDebugEnabled()), o el nivel que sea. Si pueden tenerlos (it.next(), contador++, repo.save()), saca antes la llamada a una variable local y pasa la variable al log.
System.out y System.err: usa el logger que ya tiene la clase, o uno como el de las demas clases, con el mismo texto; out es info y err es error. Si es la salida que lee otro programa (un main que imprime su resultado), apuntala.
Trampa: una llamada con efecto metida dentro del if del log deja de ejecutarse cuando ese nivel esta apagado.
'@ }
  # 5. vacios
  @{ Nombre = 'vacios'; Rx = '^(Add a nested comment explaining why this method is empty|Either remove or fill this block of code|Remove this block of code, fill it in|Add a default case to this switch|Complete cases by adding the missing enum constants|.if \.\.\. else if. constructs should end with .else. clauses)'; Avisar = $false; Texto = @'
Metodo vacio: pon dentro un comentario que diga POR QUE no hace nada en este caso concreto (por ejemplo: la interfaz obliga a declararlo y este listener solo actua al terminar el job).
switch sin default, o cadena if / else if sin else: anade el default o el else con un comentario que diga por que los demas valores no requieren accion.
Bloque vacio: no cambies el flujo. En un catch, registra la excepcion con el logger de la clase o explica en un comentario por que se ignora; en otro bloque, comentario con el motivo.
Trampa: lanzar una excepcion (UnsupportedOperationException, IllegalStateException), como propone el mensaje, rompe a quien hoy llama a ese metodo o pasa por ese caso. Un comentario que no explica el motivo es relleno.
'@ }
  # 6. inyeccion
  @{ Nombre = 'inyeccion'; Rx = '^(Annotate this member with .@Autowired|Remove this field injection and use constructor injection|Use constructor injection for this field)'; Avisar = $false; Texto = @'
NO anadas @Autowired, @Inject, @Resource ni @Value al campo, aunque el mensaje lo proponga, y no borres el campo.
Dependencia (otro bean, puerto, repositorio, propiedades): campo private final asignado desde un parametro del UNICO constructor (con @RequiredArgsConstructor basta con final); @Qualifier y @Value van en el parametro, en la misma linea que su tipo. Adapta los tests que hagan new.
Varios constructores que solo asignan campos: deja uno con todas las dependencias; quien usaba otro pasa null en las que antes no daba. Si hacen algo mas, apuntala: hay que elegir cual usa Spring.
Valor fijo e inmutable creado en la declaracion (String, numero, Pattern, DateTimeFormatter): private static final.
Valor de trabajo que cada metodo escribe antes de leer: variable local.
Apuntala solo si el campo guarda estado entre llamadas (contador, lista, mapa, iterador o fecha que un metodo escribe y otro, o la llamada siguiente, lee), o si dos clases se inyectan entre si (con constructor la aplicacion no arranca).
Trampa: inicializar el estado en el constructor (this.total = 0; this.lineas = new ArrayList<>()), hacerlo static o cambiar el scope calla a Sonar y el estado compartido sigue ahi. Con @Autowired en el campo vuelve la inyeccion por campo.
'@ }
  # 7. genericos
  @{ Nombre = 'genericos'; Rx = '^Provide the parametrized type for this generic'; Avisar = $false; Texto = @'
Pon el tipo real de los elementos, deducido de lo que se mete y se saca: List -> List<Cliente>. No anadas casts.
Si el tipo esta en una firma (parametro, retorno, campo), cambiala y adapta a quien la usa: los genericos no cambian nada al ejecutar.
Si la coleccion mezcla tipos, usa su tipo comun mas concreto (Map<String, Object> para un mapa de valores sueltos). Si lo unico comun es Object, apuntala.
Trampa: List<Object> o List<?> compilan y callan a Sonar sin arreglar nada.
'@ }
  # 8. javadoc
  @{ Nombre = 'javadoc'; Rx = '^Document (the parameter\(s\)|this method thrown exception\(s\)|this method return value|this public )'; Avisar = $false; Texto = @'
Completa el Javadoc que ya hay encima; no lo reescribas. Anade lo que nombra el mensaje: @param, @return, @throws o la descripcion.
Lee el cuerpo y di que es ese dato para este metodo y en que caso concreto se lanza la excepcion. Mismo idioma que el resto.
No toques la firma: no quites el throws ni envuelvas el cuerpo en try/catch.
Trampa: repetir el nombre (@param ruta la ruta) es relleno.
'@ }
  # 9. expresiones
  @{ Nombre = 'expresiones'; Rx = '^(Reduce the number of conditional operators \(\d+\) used in the expression|Extract this nested ternary operation)'; Avisar = $false; Texto = @'
Extrae un grupo completo de la condicion (lo que va entre parentesis) o el ternario interior a un metodo private con nombre que diga que comprueba o que calcula. Deja el resto igual.
No lo saques a una variable local: se evaluaria siempre, y hoy solo se evalua si hace falta.
Respeta parentesis y precedencia (&& antes que ||). No simplifiques ni inviertas condiciones.
Trampa: en a != null && a.esValido(), la segunda parte depende de la primera; evaluada por separado da NullPointerException.
'@ }
  # 10. duplicados
  @{ Nombre = 'duplicados'; Rx = '^(This (branch|case).s code block is the same as the block for the|Update this method so that its implementation is not identical to)'; Avisar = $false; Texto = @'
Metodos identicos: haz que uno llame al otro (return otro(args);). No cambies ninguno para que parezcan distintos.
Ramas identicas y seguidas: une sus condiciones con || en el orden en que estaban (en un switch, case A, B).
Ramas identicas con otra rama en medio: no unas las condiciones; extrae el cuerpo repetido a un metodo private y llamalo desde las dos.
Trampa: unir dos condiciones saltandose la rama de en medio cambia el resultado cuando esa rama tambien se cumple.
'@ }
  # 11. recursos
  @{ Nombre = 'recursos'; Rx = '(^Use try-with-resources or close this .+ in a .finally. clause|may fail to close stream)'; Avisar = $false; Texto = @'
Usa try-with-resources solo si el recurso se abre, se usa y se termina dentro de ese metodo. Varios recursos: en el mismo try y en el orden en que se abrian.
Si el metodo lo devuelve, lo guarda en un campo o lo cierra otro metodo (open y close de un ItemStream, un @PreDestroy), apuntala: cerrarlo aqui se lo quita a quien lo sigue usando.
Trampa: cerrar un recurso que otro sigue usando (el reader que devuelve el metodo, la conexion que gestiona Spring) falla despues y lejos de aqui.
'@ }
  # 12. mutable
  @{ Nombre = 'mutable'; Rx = '(^(Store|Return) a copy of |may expose internal representation by (returning|storing))'; Avisar = $false; Texto = @'
Antes de copiar, busca en el repo quien modifica lo que se devuelve o se recibe: getX().add(...), getX().put(...), getX()[i] = ..., o cambiar la lista despues de pasarla.
Si alguien lo hace, apuntala: con la copia ese cambio dejaria de verse y el resultado seria otro.
Si nadie lo hace: devuelve o guarda una copia que respete null: new ArrayList<>(x), x.clone() en arrays, new Date(x.getTime()).
Si lo guardado es un bean de Spring, la coleccion de una entidad JPA o un objeto compartido a proposito, no lo copies: apuntala.
Trampa: con la copia no falla nada: solo cambia el resultado. List.copyOf y List.of ademas fallan con null.
'@ }
  # 13. sombra
  @{ Nombre = 'sombra'; Rx = '^Rename .+ which hides the field declared at line \d+'; Avisar = $false; Texto = @'
Renombra la variable local, no el campo, y TODOS sus usos dentro del metodo. Despues repasa el metodo: cada uso del nombre antiguo que quede tiene que ser el campo a proposito.
Trampa: un uso que se te escape sigue compilando, porque ahora apunta al campo, y cambia el resultado.
'@ }
  # 14. returns
  @{ Nombre = 'returns'; Rx = '^(Reduce the number of returns of this method|This method has \d+ returns, which is more than)'; Avisar = $false; Texto = @'
Cadena de if que compara UNA variable con constantes y devuelve un valor por caso: cambiala por un switch con flechas que da el valor, con un solo return. Si la variable puede ser null, pon case null con lo que hoy devuelve ese caso.
Varias condiciones seguidas que devuelven lo mismo: agrupalas en un metodo private boolean y deja un return para todas.
Si no encaja: corta el metodo por un punto natural (acaban las validaciones, empieza el calculo). Lo que va desde ahi hasta el final pasa a un metodo private con nombre propio, y el original termina en return eseMetodo(...).
No uses una variable resultado con if anidados ni cambies el orden de las comprobaciones.
Trampa: un switch sobre null lanza NullPointerException y la cadena de if con equals no. Juntar returns con if anidados sube la complejidad cognitiva.
'@ }
  # 15. map-compute
  @{ Nombre = 'map-compute'; Rx = '^Replace this .Map\.(containsKey|get)\(\). .*with a call to .Map\.computeIfAbsent'; Avisar = $false; Texto = @'
Cambialo por computeIfAbsent solo si se cumple todo: la funcion que crea el valor no toca ese mismo mapa, no lanza excepciones marcadas y nunca da null, y el mapa no guarda valores null.
Si falla algo de eso, o el bloque hace algo mas que crear y guardar el valor, apuntala: el resultado cambiaria.
Trampa: computeIfAbsent no guarda un valor null, trata una clave con valor null como ausente y, si la funcion modifica el mapa, HashMap lanza ConcurrentModificationException.
'@ }
  # 16. condicion-fija
  @{ Nombre = 'condicion-fija'; Rx = '^(Change this condition so that it does not always evaluate to|Remove this expression which always evaluates to)'; Avisar = $false; Texto = @'
No cambies la condicion para que deje de ser fija: eso cambia la logica.
Localiza la linea anterior que hace que siempre valga eso. Si la ves: siempre true, quita esa comprobacion y deja su cuerpo; siempre false, quita la comprobacion y el bloque que nunca se ejecuta.
Si no ves por que es fija, o parece que la condicion deberia ser otra, apuntala: hay que saber cual era la intencion.
Trampa: el mensaje pide cambiar la condicion; hacerlo activa codigo que hoy no se ejecuta nunca.
'@ }
  # 17. equals
  @{ Nombre = 'equals'; Rx = '(^Strings and Boxed types should be compared using .equals|Comparison of String objects using == or != in )'; Avisar = $true; Texto = @'
Cambia a == b por Objects.equals(a, b), y a != b por !Objects.equals(a, b).
Trampa: a.equals(b) lanza NullPointerException si a es null; == no la lanzaba.
'@ }
  # 18. serializable
  @{ Nombre = 'serializable'; Rx = '(^Make .+ (transient or serializable|private or transient)|defines non-transient non-serializable instance field)'; Avisar = $false; Texto = @'
No pongas transient: el campo dejaria de guardarse y llegaria null al deserializar o al reanudar un job.
Si la clase del campo (o la de sus elementos) es del proyecto, hazla implements Serializable con su serialVersionUID, y lo mismo con las clases de sus campos.
Si no es del proyecto y no es serializable, apuntala: hay que decidir si ese dato se guarda o se pierde.
Trampa: transient compila, calla a Sonar y pierde el dato.
'@ }
  # 19. sincronizadas
  @{ Nombre = 'sincronizadas'; Rx = '^Replace the synchronized class .+ by an unsynchronized one'; Avisar = $false; Texto = @'
StringBuffer -> StringBuilder y Vector -> ArrayList: cambialo si el objeto no se comparte entre hilos (variable local; parametro o retorno de metodos que lo reciben de una local; campo de un objeto que se crea en cada uso). Adapta firmas y llamadas.
Hashtable -> HashMap y Stack -> ArrayDeque: ademas, solo si el codigo no lo recorre (for, keySet, values, elements, get(i)) ni le mete null.
Campo static, campo de un bean de Spring, o un Hashtable o Stack que se recorre: apuntala; cambiaria el orden de los datos o quien puede tocarlos a la vez.
Trampa: un campo compartido pierde la sincronizacion; Hashtable y HashMap se recorren en distinto orden, y Stack y ArrayDeque en orden contrario.
'@ }
  # 20. tolist
  @{ Nombre = 'tolist'; Rx = '^Replace this usage of .Stream\.collect\(Collectors\.'; Avisar = $false; Texto = @'
Stream.toList() da una lista que no se puede modificar. Sigue la lista alla donde vaya: variable, retorno, campo, argumento.
Si nadie la modifica (add, remove, set, sort, clear, addAll, Collections.sort): cambia a .toList().
Si alguien la modifica, va a una entidad JPA o sale a codigo que no ves: cambia a .collect(Collectors.toCollection(ArrayList::new)), que da la misma lista de antes y dice a las claras que se modifica.
Trampa: con .toList(), modificarla falla en ejecucion con UnsupportedOperationException, lejos del cambio.
'@ }
  # 21. resultado-ignorado
  @{ Nombre = 'resultado-ignorado'; Rx = '(^Do something with the .+ value returned by|^Use .java\.nio\.file\.Files#delete. here|Exceptional return value of .+ ignored in )'; Avisar = $false; Texto = @'
Guarda el valor devuelto y, si indica fallo (false), registra un aviso con el logger de la clase. No lances excepcion ni cambies el flujo.
Files#delete: usa Files.delete(fichero.toPath()) dentro de un try con catch (IOException e) que registre el aviso y siga, para que el flujo sea el de antes.
Trampa: Files.delete lanza excepcion donde File.delete devolvia false (no existe, esta en uso): sin ese catch, el proceso se para.
'@ }
  # 22. test-sin-asercion
  @{ Nombre = 'test-sin-asercion'; Rx = '^Add at least one assertion to this test case'; Avisar = $false; Texto = @'
Anade una asercion sobre lo que el test ya ejecuta: el valor devuelto, el estado que cambia o un verify del mock.
Si el test solo comprueba que no falla, envuelve la llamada en assertDoesNotThrow(() -> ...).
Trampa: assertTrue(true), assertNotNull(new X()) o comparar algo consigo mismo no comprueban nada.
'@ }
  # 23. interrupcion
  @{ Nombre = 'interrupcion'; Rx = '^Either re-interrupt this method or rethrow the .+ that can be caught here'; Avisar = $true; Texto = @'
Anade Thread.currentThread().interrupt(); como primera linea de ese catch y deja el resto igual. Si el catch es de Exception, hazlo solo cuando sea InterruptedException (instanceof).
Trampa: relanzar la excepcion, como tambien propone el mensaje, cambia el flujo y la firma del metodo.
'@ }
  # 24. fecha-estatica
  @{ Nombre = 'fecha-estatica'; Rx = '^Make .+ an instance variable'; Avisar = $false; Texto = @'
Quita el campo static y crea el objeto (SimpleDateFormat, Calendar) como variable local en cada metodo que lo usa, con el mismo patron, Locale, zona horaria y setLenient.
Si lo usan otras clases, cambia el campo por un metodo static que devuelve uno nuevo cada vez y adapta todos los usos.
No lo cambies por DateTimeFormatter ni lo dejes como campo de instancia.
Si es un Calendar que un metodo ajusta y otro lee despues, es estado compartido: apuntala.
Trampa: DateTimeFormatter no lee los patrones igual (YYYY, fechas imposibles que SimpleDateFormat acepta); y un campo de instancia en un singleton sigue compartido entre hilos.
'@ }
  # 25. campo-local
  @{ Nombre = 'campo-local'; Rx = '(defines fields that are used only as locals|^Remove the .+ field and declare it as a local variable)'; Avisar = $false; Texto = @'
El mensaje de SpotBugs nombra la clase (Externa$Interna es la clase Interna dentro de Externa), no el campo: revisa cada campo private de esa clase.
Campo que en todos los metodos que lo usan se escribe antes de leerse: declaralo como variable local en cada metodo y borra el campo.
Campo que solo se escribe y nunca se lee: borra el campo y sus asignaciones (si se asignaba una llamada, deja la llamada); si venia de un parametro del constructor, quita el parametro y sus argumentos.
Si algun metodo lo lee sin haberlo escrito antes en esa misma llamada, es estado: apuntala. Si la clase lleva anotaciones que generan o leen campos (Lombok, Jackson, JPA), apuntala: alguien lo lee por su nombre.
Trampa: un campo que un metodo escribe y otro lee despues es estado, no una variable local: al pasarlo a local, el segundo metodo deja de ver el valor.
'@ }
  # 26. incremento
  @{ Nombre = 'incremento'; Rx = '^Extract this increment or decrement operator into a dedicated statement'; Avisar = $false; Texto = @'
Saca el ++ o -- a su propia sentencia, pegada a la linea donde estaba: con sufijo (i++), primero la linea que usa i y despues i++; con prefijo (++i), primero ++i y despues la linea.
Si la linea cuelga de un if, else o bucle sin llaves, pon llaves para que las dos sentencias queden dentro.
Si esta en la condicion de un bucle, en un ternario, detras de && u ||, o la variable sale dos veces en la expresion, apuntala: ahi el momento del incremento decide el resultado.
Trampa: sin llaves, el i++ queda fuera del if y se ejecuta siempre.
'@ }
  # 27. tipo-lambda
  @{ Nombre = 'tipo-lambda'; Rx = '^Specify a type for:'; Avisar = $false; Texto = @'
Escribe el tipo exacto de cada parametro de la lambda, sacado de la interfaz funcional o del generico (Stream<Fila> da Fila): (Fila fila) -> ... Si hay varios parametros, tipalos todos.
No uses var ni un tipo mas general.
Trampa: (Object fila) compila en muchos streams y cambia a que sobrecarga se llama dentro.
'@ }
  # 28. optional-parametro
  @{ Nombre = 'optional-parametro'; Rx = '^Specify (an? .+ parameter|a type) instead'; Avisar = $false; Texto = @'
El parametro es Optional<T>. Declaralo como @Nullable T (org.springframework.lang.Nullable) y, dentro, donde se usaba el parametro, pon Optional.ofNullable(parametro).
Si lo inyecta Spring (constructor de un componente o metodo @Bean), no hay mas que hacer: Spring pasa null cuando el bean no existe. Adapta los tests que construyen la clase: pasan el objeto o null.
En un metodo normal, adapta TODAS las llamadas: Optional.of(x) -> x; Optional.empty() -> null; una variable opt -> opt.orElse(null).
No lo dejes como T sin @Nullable y no anadas @Autowired para callar la regla.
Trampa: con T a secas, la aplicacion no arranca en los entornos donde ese bean no existe, y los tests no lo ven.
'@ }
  # 29. record-array
  @{ Nombre = 'record-array'; Rx = '^Override .+ to consider array.s content in the method'; Avisar = $true; Texto = @'
Escribe a mano en el record los metodos que nombra el mensaje (equals, hashCode, toString), con TODOS los componentes y en su orden.
equals: instanceof del mismo record; Arrays.equals para el array, Objects.equals para objetos, == para primitivos (Double.compare en double y float). hashCode: 31 * Objects.hash(los demas) + Arrays.hashCode(array).
toString: mismo formato que el del record, Nombre[a=..., b=...], con Arrays.toString para el array.
No cambies el array por List, no lo clones y no toques el constructor ni los accesores.
Trampa: olvidar un componente en equals hace iguales dos objetos distintos.
'@ }
  # 30. reboxing
  @{ Nombre = 'reboxing'; Rx = 'Boxed value is unboxed and then immediately reboxed'; Avisar = $false; Texto = @'
El mensaje nombra el metodo; lambda$<metodo>$N es una lambda dentro de <metodo>. Busca donde un valor envuelto (Double, Integer, Long) se mezcla con un primitivo; casi siempre un ternario: c ? valor : 0.0.
Da el mismo tipo envuelto a las dos ramas: c ? valor : Double.valueOf(0.0). Si es un cast o un doubleValue() que se vuelve a envolver, usa el valor tal cual.
No cambies tipos de parametros, campos ni retornos, y no anadas casts.
Trampa: con las dos ramas envueltas, un null que antes fallaba ahi con NullPointerException ahora sigue adelante. Solo es igual si la condicion ya descarta el null; si no, apuntala.
'@ }
  # 31. excepcion-generica
  @{ Nombre = 'excepcion-generica'; Rx = '^(Define and throw a dedicated exception instead of using a generic one|Replace generic exceptions with specific library exceptions)'; Avisar = $false; Texto = @'
throw new RuntimeException(...), Exception, Error o Throwable: lanza en su lugar una excepcion propia que HEREDE de la misma que se lanzaba (extends RuntimeException si era RuntimeException), con los mismos argumentos: mensaje y causa.
Si el proyecto ya tiene una excepcion propia que hereda de esa misma, usa esa. Si no, creala en un fichero nuevo del mismo paquete, con nombre de lo que falla (ImportacionException) y los constructores que hagan falta para pasar esos argumentos.
throws Exception o throws Throwable en la firma: declara en su lugar las excepciones concretas que lanza el cuerpo. Si el cuerpo llama a algo que declara throws Exception (una libreria, una interfaz), apuntala: para quitarlo habria que envolver el error.
No envuelvas ni captures nada nuevo, y no cambies el mensaje.
Trampa: una excepcion que no hereda de la que se lanzaba cambia quien la captura y si la transaccion se deshace (Spring solo deshace con las no marcadas); el batch puede dejar de saltar o de reintentar ese error.
'@ }
  # 32. parametros
  @{ Nombre = 'parametros'; Rx = '^(Constructor|Method) has \d+ parameters, which is greater than'; Avisar = $false; Texto = @'
Quita primero los parametros que el metodo no usa, tambien de todas las llamadas.
Agrupa los que viajan juntos y son una sola cosa (un periodo, una direccion, los datos de una fila) en un record nuevo, en un fichero nuevo del mismo paquete y con nombre de esa cosa. El metodo recibe el record y lee sus componentes; adapta TODAS las llamadas, en main y en test, pasando los mismos valores en el mismo orden.
Constructor de una clase de datos: recibe esos records y reparte sus valores en los mismos campos de siempre; no cambies los campos ni sus getters y setters.
Metodo que llama Spring (constructor de un @Component, @Service, @Repository o @Configuration; metodo @Bean): sus parametros son beans inyectados. Quita los que no use; si aun sobran, apuntala: agruparlos pide un bean nuevo y cambia el cableado.
Trampa: un record saco con todo (Parametros, Datos, Contexto), un Map o un Object[] solo cambian el problema de sitio. No anadas @Autowired al constructor para callar la regla.
'@ }
  # 33. partir-clase
  @{ Nombre = 'partir-clase'; Rx = '(^Split this class into smaller and more specialized ones|has \d+( \w+)? methods, which is greater than the \d+ authorized|^Refactor this class so it has no more than \d+ (\w+ )?fields|^This file has \d+ lines, which is greater than)'; Avisar = $false; Texto = @'
Busca un grupo de metodos private que hacen juntos una sola tarea (validar, calcular importes, montar un fichero, dar formato) y llevalos TAL CUAL, con las constantes y los campos que solo usan ellos, a una clase nueva en un fichero nuevo del mismo paquete, con nombre de esa tarea. Repite con otro grupo hasta bajar del limite del mensaje.
La clase nueva es normal: sin anotaciones de Spring ni @Transactional. Lo que necesite de la original (repositorios, puertos, valores) lo recibe por su constructor y lo guarda en campos private final; la original la crea con new DENTRO de su constructor y la guarda en un campo private final.
Si los metodos del grupo no usan campos de la instancia, hazlos static en una clase final con constructor private: no hace falta crearla.
Se quedan en la original, con su firma y sus anotaciones: los metodos public, los @Override y todo metodo o campo con anotaciones (@Transactional, @Bean, @Value, @BeforeStep...). Su cuerpo puede llamar a la clase nueva.
Demasiados campos en una clase de datos cuyas propiedades se leen por nombre (mapper, Jackson, yml): apuntala; agruparlos cambia esos nombres.
Trampa: si Spring inyecta los campos de la original (@Autowired o @Value en el campo), dentro del constructor todavia valen null: pasa el dato como parametro de cada metodo de la clase nueva. Repartir por orden (Parte1, Parte2) no arregla nada.
'@ }
  # 34. campo-publico
  @{ Nombre = 'campo-publico'; Rx = '^Make \S+ a static final constant or non-public and provide accessors'; Avisar = $false; Texto = @'
Si al campo solo se le da valor en su declaracion o en el constructor: anade final y nada mas.
Si no: hazlo private y crea su get y su set con el nombre exacto del campo (nombre -> getNombre y setNombre; boolean activo -> isActivo y setActivo). Cambia TODOS los usos en el repo: obj.nombre -> obj.getNombre(); obj.nombre = v -> obj.setNombre(v); obj.n++ -> obj.setN(obj.getN() + 1).
No cambies el nombre ni el tipo del campo y no lo hagas static.
Si el nombre empieza por mayuscula o su segunda letra es mayuscula (NIF, eMail), apuntala: con get y set la propiedad pasa a llamarse de otra forma para Jackson y los mappers.
Trampa: quien lee el dato por nombre (Jackson, mappers, plantillas) sigue viendo la misma propiedad solo si get y set respetan el nombre exacto.
'@ }
  # 35. interfaz-constantes
  @{ Nombre = 'interfaz-constantes'; Rx = '^Move constants defined in this interfaces? to another class or enum'; Avisar = $false; Texto = @'
En el mismo fichero y con el mismo nombre, cambia interface por final class. Anade un constructor private con un comentario dentro que diga que es una clase de constantes y no se crea.
Escribe public static final delante de cada constante: en la interface iba implicito.
En las clases que hacian implements de esa interface: quita el implements y, donde usaban una constante sin prefijo, pon el nombre de la clase delante (Constantes.X) o un import static.
Mismos nombres, tipos y valores, y en el mismo orden.
Trampa: sin public static final, cada constante pasa a ser un campo de instancia visible solo en su paquete.
'@ }
  # 36. static-desde-instancia
  @{ Nombre = 'static-desde-instancia'; Rx = '(^Make the enclosing method .static. or remove this set|Write to static field .+ from instance method )'; Avisar = $false; Texto = @'
Si el metodo que escribe el campo static no usa nada de la instancia (ni campos, ni metodos no static, ni this) y no es @Override: hazlo static y adapta las llamadas a Clase.metodo(...).
Si usa la instancia, es @Override o lo llama Spring (lleva anotaciones, o es el set de una propiedad): apuntala; hay que decidir de quien es ese dato compartido.
No quites static del campo ni lo cambies de sitio.
Trampa: sin static en el campo, cada objeto tendria su copia y el dato dejaria de compartirse: cambia el resultado sin fallar.
'@ }
  # 37. constructor-sobrescribible
  @{ Nombre = 'constructor-sobrescribible'; Rx = '^Remove this call from a constructor to the overridable'; Avisar = $false; Texto = @'
Busca en el repo si alguna clase hereda de esta y sobrescribe ese metodo. Si alguna lo hace, apuntala: el constructor dejaria de ejecutar el codigo de la subclase.
Si nadie lo sobrescribe: pasa el cuerpo del metodo a un metodo private nuevo; el constructor llama al private, y el metodo original se queda con una sola linea que tambien lo llama. Si es un set simple (solo this.x = x), en el constructor basta la asignacion.
No lo arregles poniendo final al metodo ni a la clase.
Trampa: con final, Spring y Hibernate no pueden envolver la clase (transacciones, carga perezosa) y falla al ejecutar, no al compilar.
'@ }
  # 38. throws-multiple
  @{ Nombre = 'throws-multiple'; Rx = '^Refactor this method to throw at most one checked exception'; Avisar = $false; Texto = @'
Deja en el throws UNA sola excepcion marcada sin cambiar lo que se lanza:
Si una de las declaradas es hija de otra (FileNotFoundException e IOException), deja solo la madre.
Quita las que el cuerpo ya no puede lanzar. Si entonces el compilador protesta en un catch de quien llama, ese catch no hacia nada: quitalo.
Si aun quedan dos o mas de familias distintas (IOException y SQLException), apuntala: juntarlas exige envolverlas, y eso cambia el error que recibe quien llama.
Trampa: throws Exception, o envolver en RuntimeException, cambia quien captura el error y si la transaccion se deshace.
'@ }
  # 39. clase-interna
  @{ Nombre = 'clase-interna'; Rx = '^Reduce this (class from \d+ lines to the maximum allowed|anonymous class number of lines from)'; Avisar = $false; Texto = @'
Clase interna con nombre que es static, o que no usa campos ni metodos private de la clase que la contiene: llevala TAL CUAL a su propio fichero en el mismo paquete, con el mismo nombre, y adapta a quien la nombraba (Externa.Interna -> Interna).
En otro caso, y en las anonimas: deja la clase donde esta y saca el cuerpo de sus metodos largos a metodos private de la clase que la contiene; cada metodo de la interna queda en una linea que llama al nuevo y le pasa lo que necesita.
Si la clase es Serializable o se guarda en el ExecutionContext, no la muevas ni le cambies el nombre: usa la segunda via.
Trampa: al sacarla a su fichero cambia su nombre real (Externa$Interna), y lo ya guardado con ese nombre (un job a medias) deja de poder leerse. Dentro de una anonima, this es la anonima; fuera es otro objeto: pasalo como argumento.
'@ }
  # 40. switch-largo
  @{ Nombre = 'switch-largo'; Rx = '^Reduce the number of non-empty switch cases from'; Avisar = $false; Texto = @'
Si cada case solo da un valor fijo para su clave: cambia el switch por un mapa constante, private static final Map<K, V> hecho con Map.ofEntries(Map.entry(clave, valor), ...), y lee con getOrDefault(clave, valor del default). Usa Map.ofEntries y no HashMap: con una clave null lanza NullPointerException, igual que el switch.
Si los case ejecutan codigo: junta en un solo case los que hacen exactamente lo mismo (case A, B ->). Si aun sobran, saca el cuerpo de cada case a un metodo private con los mismos parametros y usa un mapa constante de clave a metodo (Map<K, BiFunction<Clase, Dato, Resultado>> con Clase::metodo), que se llama con this.
Si hay case sin break que siguen en el siguiente, o los case cambian variables locales que se usan despues, apuntala: en un mapa ese flujo se pierde.
Trampa: sin default, el switch no hacia nada con una clave desconocida; con el mapa, get da null y lo que viene despues falla o hace otra cosa. Comprueba antes con containsKey.
'@ }
  # 41. tests-parametrizados
  @{ Nombre = 'tests-parametrizados'; Rx = '^Replace these \d+ tests with a single Parameterized one'; Avisar = $false; Texto = @'
Une esos tests en UNO con @ParameterizedTest y @MethodSource: un metodo static que devuelve Stream<Arguments> con un Arguments.of(...) por cada test que habia, UNO POR LINEA, con los valores que cambiaban; el test los recibe como parametros.
El cuerpo y las aserciones quedan como estaban, con el parametro donde estaba el literal. El nombre del test dice lo que tienen en comun.
Si falta junit-jupiter-params (el import no compila) o los tests son de JUnit 4 (org.junit.Test), apuntala: hace falta una dependencia.
Trampa: borrar los tests repetidos, o dejar menos Arguments.of que tests habia, quita casos de prueba.
'@ }
  # 42. demasiadas-aserciones
  @{ Nombre = 'demasiadas-aserciones'; Rx = '^Refactor this method to reduce the number of assertions from'; Avisar = $false; Texto = @'
Reparte el test en varios, uno por cada cosa que se comprueba (la cabecera, los importes, los errores), cada uno con su @Test y un nombre que lo diga.
La preparacion comun y la llamada que se prueba van a un metodo private que devuelve el resultado; cada test nuevo lo llama y hace sus aserciones.
Todas las aserciones que habia siguen estando, repartidas; no quites ni fusiones ninguna.
Trampa: si unas aserciones dependen de pasos anteriores del mismo test (llama, comprueba, vuelve a llamar), cada test nuevo tiene que repetir esos pasos en el mismo orden.
'@ }
  # 43. clase-vacia
  @{ Nombre = 'clase-vacia'; Rx = '^Remove this empty class, write its code or make it an'; Avisar = $false; Texto = @'
Busca el nombre de la clase en todo el repo (java, xml, yml, properties).
Si nadie la usa: borra el fichero.
Si solo se usa como tipo (nunca con new): cambia class por interface, y extends por implements en quien la heredaba.
Si se crea con new o se cita por nombre en un xml o un yml, apuntala: hay que decidir que debe contener.
Trampa: anadir un campo, un metodo o un constructor vacio para que deje de estar vacia es relleno.
'@ }
)
$SonarNoAutomatizarReal = @(
  @{ Rx = '^Return an empty .+ instead of null'; Motivo = 'Cambia lo que recibe quien llama. En un lector de Spring Batch, null significa "no hay mas datos": una lista vacia es un bucle infinito.' }  # S1168
  @{ Rx = '^Refactor this class declaration to use .record '; Motivo = 'Un record compara por valor (equals y hashCode), cambia los accesores (getX() pasa a x()) y como lo leen los mappers y Jackson.' }  # S6206
  @{ Rx = '^Either log this exception and handle it, or rethrow it'; Motivo = 'Hay que elegir entre el log y el relanzamiento: uno cambia las trazas y el otro, el flujo.' }  # S2139
  @{ Rx = '(^Catch Exception instead of |Exception is caught when Exception is not thrown in )'; Motivo = 'Capturar menos deja escapar errores que hoy se recogen: un job que hoy termina con su estado puede pasar a abortar.' }  # S1181, SpotBugs REC_CATCH_EXCEPTION
  @{ Rx = '^(Remove this call to a deprecated .+, it has been marked for removal|Don.t override this deprecated method)'; Motivo = 'Migrar a la API nueva puede cambiar el comportamiento: hay que leer la guia de la libreria.' }  # S5738
  @{ Rx = '(methods via an injected dependency instead of directly via .this|@Transactional requirement is incompatible with the one for this method)'; Motivo = 'Llamar a traves del proxy de Spring abre una transaccion (o un @Async, o una cache) que hoy no se abre.' }  # S6809 S2229
  @{ Rx = '^This accessibility (bypass|update) should be removed'; Motivo = 'Quitar el acceso por reflexion exige decidir otra forma de llegar al dato.' }  # S3011
  @{ Rx = '(^A .NullPointerException. could be thrown|^Call .Optional#isPresent\(\). or .!Optional#isEmpty\(\). before accessing the value|Possible null pointer dereference of )'; Motivo = 'Hay que decidir que pasa cuando el dato falta: saltarse el codigo en silencio esconde el error.' }  # S2259 (m) S3655 (m), SpotBugs NP_NULL_ON_SOME_PATH
  @{ Rx = '(^Use .(BigDecimal\.valueOf|new BigDecimal\(String, MathContext\)). instead|^Cast one of the operands of this|^Equality tests should not be made with floating point values)'; Motivo = 'El arreglo cambia el resultado numerico (decimales, desbordamiento, comparacion): lo aprueba una persona con un caso de prueba.' }  # S2111 S2184 S1244
  @{ Rx = '(^Correct one of the identical (argument )?sub-expressions|^Remove (or correct )?this useless self-assignment|^Remove this conditional structure or edit its code blocks|^This conditional operation returns the same value|^This (line|statement) will not be executed (conditionally|in a loop)|^The return value of |extract the right operand to a variable if it should always be evaluated|^End this switch case with an unconditional break|where one case falls through to the next case|^Refactor this method to not always return the same value)'; Motivo = 'Sonar dice que el codigo hace algo raro, no que deberia hacer: cualquier arreglo cambia el resultado.' }  # Logica: S1764 S1656 S3923 S2681 S2201 S2178 S128, S3516 (m), SpotBugs SF_SWITCH_FALLTHROUGH
  @{ Rx = 'Found reliance on default encoding in '; Motivo = 'Hay que decidir la codificacion de los ficheros: el modelo pondria UTF-8 y, si hoy son ISO-8859-1, saldrian con las tildes rotas.' }  # SpotBugs DM_DEFAULT_ENCODING
  @{ Rx = '^Simplify this regular expression to reduce its complexity'; Motivo = 'Reescribir una expresion regular cambia que textos acepta.' }  # S5843 (m)
  @{ Rx = '^Take the required action to fix the issue indicated by this comment'; Motivo = 'Hay que hacer lo que pide el FIXME; borrar el comentario es trampa.' }  # S1134
  @{ Rx = '^Add some tests to this class'; Motivo = 'Faltan los tests: hay que escribirlos sabiendo que debe hacer la clase.' }  # S2187
  @{ Rx = '^Either add an explanation about why this test is skipped'; Motivo = 'Alguien tiene que saber por que esta desactivado; activarlo puede romper el build.' }  # S1607
  @{ Rx = '^Remove this use of .+\.sleep\(\)'; Motivo = 'Quitar la espera exige decidir otra forma de sincronizar el test, y a veces una dependencia nueva.' }  # S2925
  @{ Rx = '(^Use (a secure (cipher mode|padding scheme)|another cipher mode or disable padding|a strong cipher algorithm)|detected in this expression, review this potentially hard-coded|^Disable access to external entities in XML parsing|prepared statement is generated from a nonconstant String)'; Motivo = 'El arreglo cambia que entradas se aceptan, donde vive un secreto o como se habla con un tercero.' }  # S5542 S5547 S2068, S2755 (m), SpotBugs SQL
)
# Puertas del diff del paso sonar (seccion D de sonar-recetas.md, v2 del 18-11), a mano. Rx sobre el texto de la linea SIN el + o - del diff.
# Modos, contando en TODO el lote: anadida = ninguna linea nueva casa; neto+ = no entran mas de las que salen; neto- = no salen mas de las que entran; neto0 = entran las que salen.
# Si = la entrada solo cuenta si algun mensaje del lote lo cumple. Salvo (NUEVA en la v2) = la entrada NO cuenta si algun mensaje del lote lo cumple.
# v2: lo que era anadida pasa a neto+ (el codigo se mueve entre ficheros y una linea movida no es nueva), menos las anotaciones que Spring solo atiende en sus beans: esas no pueden cambiar de fichero.
# Fuera a proposito: firma publica (la v2 deja cambiar firmas; lo cubren compilar y tests).
$SonarProhibidoReal = @(
  # --- supresion
  @{ Modo = 'neto+'; Rx = '(NOSONAR|NOPMD|CHECKSTYLE:OFF|@SuppressWarnings|@SuppressFBWarnings|@(\w+\.)*Generated\b)'; Motivo = 'no se vale silenciar a Sonar (NOSONAR, @SuppressWarnings, @Generated): corrige el codigo o apunta la incidencia' }
  # --- tests
  @{ Modo = 'neto+'; Rx = '^\s*@(Disabled|Ignore)\b'; Motivo = 'no se vale desactivar tests' }
  @{ Modo = 'neto-'; Rx = '(^\s*@(Test|ParameterizedTest|RepeatedTest|TestFactory)\b|\bArguments\.of\s*\()'; Motivo = 'no se vale quitar tests; si unes varios en uno parametrizado, cada test que habia es un Arguments.of(...) de su @MethodSource, uno por linea' }
  @{ Modo = 'neto-'; Salvo = '^Replace these \d+ tests with a single Parameterized one'; Rx = '\b(assert\w*|verify|fail)\s*\('; Motivo = 'no se vale quitar aserciones de los tests' }
  @{ Modo = 'neto+'; Rx = '\bassert(?:True\s*\(\s*true|False\s*\(\s*false|NotNull\s*\(\s*new\b|(?:Equals|Same)\s*\(\s*([\w.]+)\s*,\s*\1\s*\))'; Motivo = 'una asercion que no comprueba nada (assertTrue(true), comparar algo consigo mismo) es trampa' }
  # --- cableado de Spring y transaccion: ni entran, ni cambian de fichero, ni se pierden. Se libra la linea cuyo unico argumento es una constante (arreglo de S1192)
  @{ Modo = 'anadida'; Rx = '^\s*@(Component|Service|Repository|Controller|RestController|Configuration|ConfigurationProperties|Bean|Scope|StepScope|JobScope|Lazy|Primary|Profile|Transactional|Scheduled|EventListener|Async|PostConstruct|PreDestroy|(Before|After)(Step|Job|Chunk|Read|Process|Write))\b(?!\s*\(\s*(?-i:[A-Z][A-Z0-9_]*)\s*\)\s*$)'; Motivo = 'no anadas anotaciones de Spring ni las cambies de fichero: una clase nueva es una clase normal (sin @Component, @Service, @Bean ni @Transactional) y los metodos anotados se quedan en su clase' }
  @{ Modo = 'neto-'; Rx = '^\s*@(Component|Service|Repository|Controller|RestController|Configuration|ConfigurationProperties|Bean|Scope|StepScope|JobScope|Lazy|Primary|Profile|Transactional|Scheduled|EventListener|Async|PostConstruct|PreDestroy|(Before|After)(Step|Job|Chunk|Read|Process|Write))\b'; Motivo = 'no quites anotaciones de Spring: deciden los beans, la transaccion y cuando se ejecuta cada metodo' }
  @{ Modo = 'anadida'; Rx = '^\s*@(Autowired|Inject|Resource)\b'; Motivo = 'no anadas ni muevas @Autowired, @Inject ni @Resource: inyecta por el unico constructor o apunta la incidencia' }
  @{ Modo = 'anadida'; Rx = '^\s*@(Value|Qualifier)\s*\((?!\s*(?-i:[A-Z][A-Z0-9_]*)\s*\)).*\)\s*((private|protected|public|static|final)\b.*)?$'; Motivo = 'no anadas ni muevas @Value ni @Qualifier sobre un campo o un metodo: Spring solo los atiende en sus beans; con inyeccion por constructor van en el parametro, en la misma linea que su tipo' }
  # --- estado nuevo
  @{ Modo = 'neto+'; Rx = '^\s*(?:private|protected|public)?\s*static\s+(?!final\b)[\w<>\[\],.? ]+\s+\w+\s*[=;]'; Motivo = 'no crees campos static que no son final: es estado compartido' }
  @{ Modo = 'neto+'; Rx = 'ThreadLocal<'; Motivo = 'no uses ThreadLocal para esconder estado' }
  @{ Modo = 'neto+'; Rx = '^\s*(?:private|protected|public)\s+(?!static\b|final\b)(?:(?:transient|volatile)\s+)*[\w<>\[\],.? ]+\s+\w+\s*(?:=[^;]*)?;'; Motivo = 'no anadas campos que no son final: lo que era una variable local no se guarda en un campo. Varios resultados van en un record; una clase nueva guarda lo que recibe en campos private final' }
  @{ Modo = 'neto+'; Si = 'Annotate this member with|field injection|constructor injection'; Rx = '^\s*this\.\w+\s*=\s*(new\s+(java\.util\.)?((Array|Linked|CopyOnWriteArray)List|(Hash|LinkedHash|Tree|ConcurrentHash)(Map|Set)|ArrayDeque|Vector|Stack|Hashtable|StringBuilder|StringBuffer|Date|GregorianCalendar|Atomic\w+)\b|new\s+\w+\s*\[|null\b|true\b|false\b|-?\d|")'; Motivo = 'inicializar el estado en el constructor calla a Sonar y el estado sigue ahi: si el campo guarda estado entre llamadas, apunta la incidencia' }
  # --- excepciones
  @{ Modo = 'neto+'; Rx = '\bcatch\s*\(\s*(?:final\s+)?(Exception|Throwable|RuntimeException)\b'; Motivo = 'no anadas catch genericos: cambian que errores se recogen' }
  @{ Modo = 'neto+'; Si = 'method is empty|fill this block|fill it in|default case|missing enum constants|should end with .else.'; Rx = '\bthrow new (UnsupportedOperation|IllegalState)Exception\b'; Motivo = 'no lances excepciones nuevas en metodos o ramas vacias: rompe a quien hoy pasa por ahi; explica con un comentario por que no hace nada' }
  # --- relleno
  @{ Modo = 'neto+'; Rx = '^\s*(?:private\s+)?(?:static\s+final|final\s+static)\s+[\w<>\[\]]+\s+((N|NUM|NUMERO|NUMBER|CONST|CONSTANTE|VALOR|VALUE|MAGIC|LITERAL|TEXTO|TEXT|STRING|STR|INT)_?\d+|(NUM(ERO|BER)?_)?(ZERO|ONE|TWO|THREE|FOUR|FIVE|SIX|SEVEN|EIGHT|NINE|TEN|CERO|UNO|DOS|TRES|CUATRO|CINCO|SEIS|SIETE|OCHO|NUEVE|DIEZ|DOCE|CIEN|MIL))\s*='; Motivo = 'el nombre de una constante dice que significa, no su valor (DOCE, NUM_12 no valen)' }
  @{ Modo = 'neto+'; Rx = '(^\s*\*\s*@param\s+(\w+)\s+((the|el|la|los|las)\s+)?\2\.?\s*$|^\s*\*\s*@(param|throws|exception)\s+\S+\s*$|^\s*\*\s*@return\s*$)'; Motivo = 'un Javadoc que repite el nombre o va vacio es relleno: di que es ese dato para este metodo' }
  @{ Modo = 'neto+'; Rx = '^\s*((?:this\.)?\w+)\s*=\s*\1\s*;'; Motivo = 'x = x es un uso falso: borra lo que no se usa o apunta la incidencia' }
  @{ Modo = 'neto+'; Rx = '^\s*(//|/\*)\s*(empty|vacio|nothing|nada|no-?op|intentionally( left)? (empty|blank)|sonar)\W*$'; Motivo = 'un comentario que no explica el motivo es relleno' }
  @{ Modo = 'neto+'; Si = 'parametrized type for this generic'; Rx = '\b(Collection|Iterator|Iterable|Optional|Stream|\w*(List|Set|Map|Queue|Deque))<\s*(Object|\?)\s*(,\s*(Object|\?)\s*)?>'; Motivo = 'List<Object> o List<?> callan a Sonar sin arreglar nada: pon el tipo real o apunta la incidencia' }
  @{ Modo = 'neto-'; Rx = '\b(TODO|FIXME)\b'; Motivo = 'no borres los TODO ni los FIXME' }
  # --- cambiar el problema de sitio
  @{ Modo = 'neto+'; Rx = '\b(class|record|interface|enum)\s+\w*((Parte|Part)\d+|(?-i:[a-z0-9](Aux|Auxiliar))\d*)\b'; Motivo = 'una clase nueva lleva el nombre de la tarea que hace: Parte2 o Aux es partir sin arreglar' }
  @{ Modo = 'neto+'; Si = '^(Constructor|Method) has \d+ parameters'; Rx = '\(\s*(final\s+)?(Map<\s*String\s*,\s*Object\s*>|Object\s*\[\]|Object\s*\.\.\.)\s+\w+\s*\)'; Motivo = 'meter todos los parametros en un Map o un Object[] cambia el problema de sitio: agrupa en un record los que son una sola cosa' }
)
