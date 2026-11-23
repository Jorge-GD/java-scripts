# El flujo de principio a fin

Qué lanzar, en qué orden y qué hacer si te pierdes. Los detalles de cada script están en el [README](README.md) y en su cabecera.

En los ejemplos:

| Ruta | Qué es |
|---|---|
| `C:\ruta\original` | El batch antiguo (Java 8) |
| `C:\ruta\migrado` | Tu repo migrado, en tu rama |
| `C:\ruta\referencia` | Un batch ya migrado y aprobado, que sirve de modelo |
| `C:\ruta\informe.xlsx` | El informe de Sonar que te descargas |

## Las dos reglas que lo hacen seguro

1. **Tu rama solo avanza con `migracion.ps1 -Cierre`, por fast-forward y después de las puertas.** Se puede deshacer con la línea que te da. Hasta entonces los arreglos viven en una copia al lado, `C:\ruta\migrado-rescate`, con su rama `rescate/...`, y tu carpeta no se toca. La única excepción es `prueba-local.ps1 -Deshacer` cuando no existe la carpeta `-rescate` (ver el paso 3).
2. **Nada hace push.** Subir es siempre cosa tuya.

## El mapa

| Paso | Qué lanzas | Cuándo | Qué te deja |
|---|---|---|---|
| 0 | `preflight.ps1` | Una vez por equipo | `preflight-resultado.txt` |
| 1 | `migracion.ps1 -SoloInforme` | Al empezar con un batch | Las 5 páginas del informe, sin cambiar código |
| 2 | `migracion.ps1 -Si` | Para arreglar lo que dice el informe | Commits en la rama `rescate/...` y la página 4 |
| 3 | Va dentro del paso 2; `prueba-local.ps1 -Desde` si sale «distinto» | Después de cada corrección | La página 3: original y migrado ejecutados con las mismas entradas |
| 4 | `migracion.ps1 -Cierre` | Cuando estás conforme y la prueba en local sale igual | Los arreglos en tu rama, y la línea para deshacerlo |
| 5 | `rescate.ps1 -Sonar` y `rescate.ps1 -Cobertura` | Cuando tienes el xlsx de Sonar, o la cobertura no llega al 80 % | Commits en `rescate/...`, `.rescate\sonar-faltan.md` y `.rescate\cobertura-faltan.md` |
| 6 | Tú, en pre | Antes de dar el batch por bueno | El guion de cada job, en la página 1 |
| 7 | `git push` y Sonar en tu CI | Al final | Un xlsx nuevo: vuelves al paso 5 |

## Si todavía no hay migrado: empezar desde cero

Estos scripts **terminan** una migración: arreglan fichero a fichero y cada arreglo tiene que compilar. No hacen la subida de versión. Pasar a Java 21 y Spring Boot 3 cambia el `pom`, `javax` por `jakarta` en todos los ficheros y la API de Spring Batch a la vez, y hasta que no está todo no compila nada. Con un batch real, lanzar el paso 2 sobre el original da un resultado malo.

Por eso, de cero va en dos fases:

1. **La subida de versión, con GitHub Copilot modernization**, en una copia del original en una rama nueva:

   ```powershell
   git clone C:\ruta\original C:\ruta\migrado
   git -C C:\ruta\migrado switch -c migracion-java21
   copilot plugin marketplace add microsoft/modernize-java
   copilot plugin install modernize-java@modernize-java
   cd C:\ruta\migrado
   copilot --agent modernize-java:modernize-java
   ```

   Pídele: `upgrade to Java 21 + Spring Boot 3.x`, con la versión de Spring Boot de tu referencia. Revisa lo que cambia y haz commit cuando compile y pasen los tests. Comandos del [quickstart de Microsoft](https://learn.microsoft.com/en-us/azure/developer/github-copilot-app-modernization/quickstart-upgrade), comprobados el 19-11-2026. Si el plugin no se instala, la otra página de Microsoft usa `microsoft/github-copilot-modernization` y `--agent=github-copilot-modernization:modernize`.
2. **Después, los pasos de siempre.** El paso 2 lo acerca a la referencia: estructura de carpetas, SFTP y configuración. El paso 3 comprueba que sigue haciendo lo mismo que el original.

- Si tu equipo crea los repos de otra forma (un repo nuevo, otro `artifactId`), créalo así y copia dentro el código del original antes de la fase 1.

## Paso 0. Preflight, una vez por equipo

```powershell
.\preflight.ps1 -Legacy C:\ruta\original -Migrado C:\ruta\migrado -Plantilla C:\ruta\referencia -Modelo <id>
```

Comprueba que PowerShell, Copilot y Maven funcionan en tu equipo. Si algo falla, pega `preflight-resultado.txt` en el chat. Quita rutas, usuario, equipo y correos, pero léelo antes de pegarlo.

Usa en todos los pasos el mismo `-Modelo <id>` del preflight. Sin él, la primera vez `migracion.ps1` te pregunta con un menú.

## Paso 1. La foto de cómo está

```powershell
.\migracion.ps1 -Legacy C:\ruta\original -Migrado C:\ruta\migrado -Plantilla C:\ruta\referencia -SoloInforme
```

- Lee el original, mide el migrado, compara los dos leyendo el código y los ejecuta con las mismas entradas (la prueba en local).
- No cambia código.
- Si el original no compila con el JDK de Maven, añade `-JavaLegacy C:\ruta\jdk-del-original`. Sin eso, la prueba en local se queda sin hacer.
- Si el original se lanza con scripts `.sh` que no están en su carpeta, añade `-Lanzadores C:\ruta\scripts`. Sin ningún `.sh`, la página 1 y la 3 lo dicen.
- Abre `C:\ruta\migrado\migracion-<batch>\index.html`. `<batch>` es el `artifactId` del `pom.xml` del migrado. La portada dice cómo ha ido y qué te toca. Arriba del todo, el recuadro «Siguiente paso» dice qué hacer ahora, con el comando listo para copiar. Desde ahí llegas a las otras cinco páginas.

| Página | Qué cuenta | Para quién |
|---|---|---|
| `1-batch-original.html` | Qué hace el batch, job a job, y cómo probar cada job en pre | Negocio y tú |
| `2-problemas.html` | Los problemas del migrado: estructura, hexagonal, SFTP, configuración, Javadoc, cobertura, y la revisión por flujos con cada hallazgo de la IA (fichero:línea, cita y problema) | Tú |
| `3-original-vs-migrado.html` | Caso a caso, si el migrado da lo mismo que el original | Tú |
| `4-correcciones.html` | Qué se ha corregido y qué queda, y las claves que la fase de propiedades añadió al yml con su commit | Tú |
| `5-buenas-practicas.html` | Las buenas prácticas del migrado (javac, Lombok, el texto que cambia en Java 21 y la limpieza), qué hacer con cada incidencia y cuáles ya están arregladas | Tú |

La calidad de la página 2 (sin IA) cuenta también cuatro reglas de Spring de Sonar way: `constructores-sin-autowired` (un componente con varios constructores y ninguno con `@Autowired`: el job no arranca), `autowired-varios`, `inyeccion-estatica` y `value-sin-expresion`. Son errores aunque la plantilla también las tenga. Si el migrado mezcla estilos de constructor (Lombok o a mano) o de logger (`@Slf4j`, `LoggerFactory` u otro), salen como error las clases que no siguen el estilo: el de la plantilla si usa uno solo; si la plantilla mezcla, el que más usa el migrado. La consola lo resume en una línea `Estilo: ...`. También es error, aunque la plantilla lo tenga, una clase `final` que Spring tiene que envolver con un proxy (`clase-final-proxy`: por `@Repository`, `@Configuration`, `@Transactional`, `@StepScope`, una anotación de caché...). Sin subclase no hay bean, y el job no arranca con `Cannot subclass final class`: quita `final`. Un método `final` con `@Transactional`, `@Async`, `@Retryable` o de caché sale como `metodo-final-proxy`. Las guías oficiales de migración añaden reglas de cosas que compilan y fallan al arrancar, o que cambian sin avisar. Son errores aunque la plantilla también las tenga: una referencia circular entre beans (`referencia-circular`, prohibidas desde Spring Boot 2.6), dos beans con el mismo nombre (`bean-repetido`), un parámetro de job con la notación vieja `nombre(long)=valor` (`parametros-v4`: Spring Batch 5 lo lee como un texto y el job no recibe el parámetro), `getEngineByName("nashorn")` (`nashorn`: Java 15 quitó el motor) y `setCommand("ls -l")` en una sola cadena (`comando-sin-partir`). `@EnableBatchProcessing` o una clase que extiende `DefaultBatchConfiguration` (`enable-batch`) es error salvo que la plantilla también lo haga. Son avisos: varios jobs sin `spring.batch.job.name` (`varios-jobs-sin-nombre`) y un `schema.sql` o `data.sql` con una base que no es en memoria (`sql-init-no-embebida`). **Las reglas nuevas solo se miden si el diagnóstico se hace otra vez**, y la pasada solo lo repite cuando cambia tu commit: en un batch ya corregido, lanza antes `.\rescate.ps1 -Modo fix -Paso calidad -Auto -Si -Lote 1 -Repo C:\ruta\migrado -Plantilla C:\ruta\referencia -Legacy C:\ruta\original`.

La página 5 mide javac (las APIs marcadas «for removal»), las comprobaciones de Lombok, el texto que cambia en Java 21 (juego de caracteres y formatos de fecha y número) y la limpieza: lo que no debería llegar al senior (restos de herramientas que están en git, marcas pendientes TODO, FIXME y XXX, código comentado y clases que nadie nombra en `src/main`). La limpieza solo avisa: no borra nada. PMD y SpotBugs se quitaron el 20-11: en tu equipo acababan siempre en «no se pudo medir» y costaban dos Maven por medida. Lo que se guardó antes con entradas de PMD o SpotBugs no se enseña.

Con `-Practicas`, si el `pom.xml` no declara Lombok, la fase lo añade antes de pasar los getters y setters: copia el bloque de la referencia (o uno por defecto), comprueba que compila y hace un commit `practica(lombok): anade Lombok al pom.xml`; si no compila, deja el pom como estaba y avisa. La huella de lo compilado no mira `META-INF/spring-configuration-metadata.json` (solo lo lee el IDE), pero sí `META-INF/additional-spring-configuration-metadata.json`.

Las propiedades: en cada lanzamiento `migracion.ps1` compara, sin IA, las claves de los `application*.properties` y `.yml` del original con las del migrado y deja el detalle en `datos\propiedades.json` y `registros\propiedades.log`. La consola dice una línea `Propiedades:` con las cuentas. De cada clave del original dice si está igual, si va por variable (lo esperado con configmap), si tiene otro valor, si Spring Boot 3 la renombró o la quitó (lo lee de los metadatos de los jars del migrado, con un `mvn dependency:build-classpath`; si Maven falla, lo dice y sigue) o si falta. Del migrado dice las claves nuevas y las que nadie lee. Los secretos salen sin su valor. Solo mide: no cambia el yml ni el código.

Carpetas que verás aparecer:

| Carpeta | Qué es | ¿Se puede borrar? |
|---|---|---|
| `C:\ruta\migrado\migracion-<batch>\` | El informe y sus datos | No, si quieres relanzar sin repetir el trabajo |
| `C:\ruta\migrado-rescate\` | La copia donde trabaja el script, con su rama | Sí, cuando ya hayas traído los cambios (paso 4) |
| `C:\ruta\original-prueba-local\` y `C:\ruta\migrado-prueba-local\` | Copias desechables de la prueba en local | Sí: se rehacen solas en cada lanzamiento |

**Antes de lanzar, haz commit de lo tuyo.** Lo que tengas sin commit se copia a la rama de rescate en un commit «foto». Si es la salida de una ejecución local (por ejemplo `output/`), añádela a `.gitignore`.

## Paso 2. Corregir lo del informe

```powershell
.\migracion.ps1 -Legacy C:\ruta\original -Migrado C:\ruta\migrado -Plantilla C:\ruta\referencia -Si
```

- No repite la lectura del paso 1.
- Arregla fichero a fichero en `C:\ruta\migrado-rescate`, con un commit por arreglo. Un arreglo solo se queda si compila, no fallan más tests que antes, bajan los problemas y no empeora nada.
- Después vuelve a medir, a comparar y a ejecutar los dos. La página 4 dice qué ha quitado y qué queda.
- Después de corregir y de comparar, si al migrado le faltan claves del original en sus `application*.properties` o `.yml` (las que dice `datos\propiedades.json`), la pasada las pone en el `.yml` con una sola llamada a Copilot y un commit (`rescate(propiedades): ...`). Solo se queda con el cambio si compila, no fallan más tests que antes y ninguna clave empeora, y el valor de un secreto no sale en ningún fichero. Si no sale bien, avisa y la pasada sigue. El resultado va a `datos\propiedades-arreglo.json`.
- Antes de ejecutar los dos, la pasada revisa el árbol final por flujos. La IA solo lee: si toca un fichero, se deshace y esa tarea no vale. Cada llamada revisa una unidad, que es un step con sus piezas (reader, processor, writer, tasklet y listeners) o un fichero suelto, con las 8 reglas del catálogo: listener que nadie registra, `@StepScope` que devuelve la interfaz, gestor de transacciones que no es el de la base, objeto no serializable en el `ExecutionContext`, acceso a los internos del JDK, clase candidata a código muerto, estado en un bean de un paso sin `@StepScope` (un contador, una lista o un fichero abierto guardados en un campo de un lector, procesador, escritor, tasklet o listener) y error tragado en un paso (un `catch` que registra el error y sigue, sin relanzar, sin skip y sin marcar el paso como fallido). Cada hallazgo lleva una cita comprobada por el script en el fichero (lo que no se puede comprobar se descarta) y salen como mucho 5 hallazgos por unidad. Mira lo que ha cambiado frente a tu rama, lo que tiene papel de Spring Batch y las clases sin uso que dicen las buenas prácticas; con `-RevisarTodo`, todos los `.java` de `src/main/java`. Respeta `-Limite` y `-MaxHoras`, y al relanzar no repite las unidades que no han cambiado. El resultado va a `datos\revision.json`.
- Opcional: para que la corrección de `calidad` vaya como la de Sonar (la IA solo compila, cada lote pasa los tests ligeros y un control pasa la suite entera), pon en `C:\ruta\migrado-rescate\.rescate\config.json` (el que lee la corrección; antes de crear la copia vale el de `C:\ruta\migrado\.rescate\config.json`) `{"PasosSoloCompila": ["sonar", "calidad"], "PasosTestsElegidos": ["sonar", "calidad"]}`. Por defecto no cambia nada: mide el paso en `.rescate\intentos.tsv` antes y después.
- Si una pasada anterior ya terminó la corrección, se la salta. Para volver a corregir, lanza el motor directamente:

```powershell
.\rescate.ps1 -Modo fix -Todo -Si -Lote 1 -Repo C:\ruta\migrado -Plantilla C:\ruta\referencia -Legacy C:\ruta\original
```

## Paso 3. Que no cambie la lógica

La prueba en local va al final de cada `migracion.ps1`. Mira la página 3 o el resumen de la consola.

| Resultado | Qué haces |
|---|---|
| Todo `igual` | Sigue al paso 4 |
| `distinto` y antes de corregir era `igual` | Lo ha roto un arreglo. Búscalo y deshazlo (abajo) |
| `distinto` ya en el paso 1 | Venía así de la migración. Mira la diferencia que enseña la página 3 y arréglalo tú, o lanza `-Reparar` (abajo) para que lo intente Copilot |
| `no determinista` | El original da dos salidas distintas con la misma entrada. No cuenta |
| `no se pudo preparar` o `sin probar en local` | Ese caso se prueba en pre |

- **Rutas largas.** Windows no pasa de 259 letras en una ruta: un fichero que no cabe en `prueba-local\salidas` se guarda con un nombre corto (`<20 primeras letras>~<hash><extensión>`, el mismo en el original, el original-2, el migrado y el caso vacío). Si ni así cabe, se guarda sin las carpetas de en medio (`<primera carpeta>/<nombre corto>`): el hash es el de la ruta entera, así que dos ficheros distintos no chocan. Uno que ni aplanado cabe no se guarda: el caso sale `distinto` con ese fichero y su motivo, y la consola te sugiere mover el proyecto a una carpeta más corta. Lo mismo vale para la ruta de origen: si la del fichero que deja el job (la de la copia) pasa de 259 letras, se lee con el prefijo `\\?\` (primero con `Copy-Item` y, si falla, con .NET) y se guarda igual.
- **Por qué falla un caso.** Cuando un lado acaba `FAILED`, `EXCEPCION` o sin `estado.txt`, la consola, la página 3, `prueba-local.json` y el prompt de `-Reparar` llevan la causa que dejó su Maven (`el migrado acaba FAILED: <causa>`); y si el migrado no arranca ningún caso de un job y el original sí, el grupo de esos casos te dice que relances con `-RehacerArnes` (salvo si el test ya se rechazó por eso: mira «Un test del migrado que no arranca el job»). Si la causa es un error del código del migrado (una clase `final` que Spring tiene que envolver con un proxy, una referencia circular entre beans o un bean repetido), la línea lo dice con su regla del paso de calidad (`clase-final-proxy`, `referencia-circular`, `bean-repetido`) y no te aconseja `-RehacerArnes`: corre el paso de calidad de `rescate.ps1`. Y si el original falla igual (la misma causa) en todos los casos comparados de un job (2 o más, también si salen `igual` porque el migrado falla igual), una línea al final dice que es su test y te aconseja `-RehacerOriginal`; para ese job no sale la de `-RehacerArnes`. La causa sale de la salida de Maven (un `Caused by:` o la primera excepción), pero nunca de una línea de aviso: una línea cuyo primer nivel de log antes de la excepción es `TRACE`, `DEBUG`, `INFO`, `WARN` o `WARNING` no cuenta (Spring escribe así las excepciones inocuas que ve al mirar las condiciones de una librería); valen las líneas sin nivel y las de `ERROR`, `FATAL` o `SEVERE`. Hay una excepción a esa regla: el aviso de Spring `Exception encountered during context initialization - cancelling refresh attempt: <excepción>` (el contexto no arranca) da la causa aunque sea `WARN`: lo que va después de los dos puntos. Si no hay ninguna excepción, la causa es el mensaje de la primera línea `[ERROR] Failed to execute goal ... on project <p>: <mensaje>` de Maven (por ejemplo `No tests matching pattern "PruebaLocalTest" were executed!`), sin el `-> [Help 1]` del final. Si un lado no deja `estado.txt`, no hay causa y su Maven acabó con código 0, la causa es `Maven acaba bien, pero el test no ha dejado salida: no ha ejecutado el caso (mira si ve su carpeta en src\test\resources\prueba-local)` (el test no encontró la carpeta del caso). Si no hay causa, la consola dice `sin causa en la salida de Maven: mira registros\mvn-<n>-<que>.log` (ese fichero está en `prueba-local\registros\`), y el fallo de `prueba-local.json` lleva `registro` con esa ruta, también cuando hay causa.
- **Un veredicto por caso, al momento.** En cuanto acaba el Maven del migrado de un caso, la consola dice cómo acaba: `caso-07: el migrado acaba EXCEPCION (<clase>: <causa>); el original, COMPLETED` o `caso-07: los dos acaban COMPLETED (la comparacion de ficheros, al final)`. No hace falta esperar al final para saber qué falla.
- **`-Rapida`: comprobar un arreglo en minutos.** Ejecuta un caso por job, con el mismo arranque: el primero que no lleva `no-aplica.txt` y trae entradas (algo en `ficheros\` o un `datos.sql` con algo) entre los ya preparados; si ninguno las trae, el primero sin `no-aplica.txt`. La consola dice qué caso ha ejecutado en cada job (`Casos ejecutados: JOB_A caso-03, JOB_B caso-01`). Si un job sale sin entradas, el aviso en rojo añade que solo se ha probado un caso y que lo confirmes sin `-Rapida`. Deja su resultado en `datos\prueba-local-rapida.json`: no toca `prueba-local.json` y no vale para `-Cierre`. Cuando salga igual, lanza sin `-Rapida`. No se combina con `-Reparar`, `-Regresion` ni `-Desde`.
- **Casos por causa, no uno a uno.** Los casos `distinto` salen agrupados por causa (`Grupo 1: 20 casos distintos, ...`, con la lista de casos, lo medido de cada grupo y el detalle de los dos primeros), y `prueba-local.json` lleva `grupos` y el `grupo` de cada caso (con `-Job`, solo los de ese lanzamiento).
- **Dato de dependencias.** Si la causa de un grupo dice que falta una clase o un método (`TypeNotPresentException`, `NoSuchMethodError`...), el script lanza una vez `mvn dependency:tree` en la copia del migrado, lo guarda en `prueba-local\dependencias.txt` y el grupo enseña las líneas de esa librería (`medido:`); `datos\prueba-local-grupos.jsonl` guarda una línea por grupo y lanzamiento.
- **Tablas con `;` dentro de un valor.** Una tabla de `tablas\` se compara sin orden de columnas ni de filas; si un valor lleva `;` (una lista de correos `a@x;b@x`, sin comillas), se prueba cada columna como la que lleva los `;` de más, con el supuesto de que los de todas las filas son de la misma columna, en el original y en el migrado, y si ninguna deja las dos tablas iguales la diferencia sale con una nota que lo dice.
- **Lo que ya crea el test.** Antes de ejecutar un caso, su `datos.sql` lleva `IF NOT EXISTS` en la copia que se ejecuta (el test ya crea cosas en su base, y Spring Batch 5 crea las suyas en el migrado). Va en cada `CREATE` (tabla, secuencia, índice con nombre, esquema, vista, rol, usuario, constante, dominio, alias, agregado y trigger) y en cada `ALTER TABLE ... ADD [COLUMN]` o `ADD CONSTRAINT <nombre>`. No se reescriben `CREATE OR REPLACE VIEW`, un índice sin nombre ni `ADD PRIMARY KEY/UNIQUE/FOREIGN KEY/CHECK` sin nombre. Lo guardado del caso no cambia. Un caso de antes cuyo original falló por «ya existe» (en español, en inglés o solo con el código de H2) se ejecuta otra vez solo, sin `-Rehacer...`.
- **Horas de la ejecución.** Una fecha de hoy seguida de su hora, con cualquier separador (`-`, `_`, `.`, `:`, `T`, un espacio o nada), se compara como `<hoy:formato><hora>`, en el contenido y en el nombre de una carpeta o un fichero. Una marca Unix de hoy (10 o 13 cifras), también. Una fecha de otro día con hora es un dato del negocio y sí cuenta.
- **Excel, zip y binarios.** Un `.xlsx` se compara celda a celda (`Hoja1!B3: valor`; una fecha de Excel de hoy sale `<hoy:excel>`). Un `.zip` o un `.gz`, entrada a entrada. Un `.png`, un `.pdf` y los demás binarios, por `binario: <n> bytes, sha256 <hash>`. Un PDF se compara sin su fecha de creación ni su `/ID`. La consola, `prueba-local.json` y el prompt de `-Reparar` enseñan esas líneas, nunca bytes. Con `-Regresion`, un caso cuyo Excel, zip o PDF lleva la fecha de hoy dentro no entra en el test fijo, igual que uno con la fecha en un `.txt`.
- **Los logs no se comparan.** Los `.log` de la salida de un caso no cuentan como diferencia (el framework nuevo deja un log por job y el original no). Para compararlos, `"CompararIgnorar": []` en `ajustes.json`.
- **Las tablas del test del original.** La base del test del migrado tiene que tener las tablas que tiene la del test del original (las de su caso vacío, sin `BATCH_` ni `TASK_`). Su primer intento ya lleva la lista. Un intento sin ellas se rechaza mientras queden otros; el último se acepta con un aviso, y los casos que usen esas tablas saldrán `EXCEPCION` en el migrado. Lo mismo con las columnas: una tabla que está en los dos tests tiene que tener las mismas columnas (sin contar el orden ni las mayúsculas). Si no, la consola lo avisa al principio, con las columnas de cada lado, antes de ejecutar los casos: los que usen esa tabla saldrían distintos. Y en los dos tests, la cabecera de un `tablas\<TABLA>.csv` no puede repetir una columna: pasa cuando el test saca las columnas de los metadatos y la tabla está en dos esquemas, y con filas la exportación falla. Un test nuevo se rechaza; uno guardado sigue con un aviso que dice las tablas y las columnas repetidas. Los avisos de tablas y columnas que faltan dicen el lado y te ofrecen primero el camino corto: añadirlas a tu test guardado (`prueba-local\arnes\<lado>`) y relanzar sin `-Rehacer`. Si no, `-RehacerArnes` (migrado) o `-RehacerOriginal` (original).
- **Un test del migrado que no arranca el job.** Si con un caso vacío el original arranca el job y el migrado acaba `EXCEPCION`, el test del migrado se rechaza mientras queden intentos (el último, o un test guardado, se acepta con un aviso: puede ser el código). Si se acepta así en el mismo lanzamiento, de ese job solo se ejecuta el primer caso: si acaba con la misma excepción, los demás salen `sin probar en local` y la consola dice que el test ya se escribió varias veces con ese error, que puede ser el código del migrado y que se lo preguntes a Copilot en su repo. No te aconseja `-RehacerArnes`. Con un test guardado de otro lanzamiento, se ejecutan todos los casos, como antes. Si la causa es un error del código del migrado (los tres de «Por qué falla un caso»), otro intento no lo arregla: el test se acepta al primer intento con un aviso que lo dice, también uno guardado, y de ese job solo se ejecuta el primer caso.
- **Todos los jobs que fallan, a la vez.** Si con un caso vacío varios jobs no dejan `estado.txt`, o el original arranca varios jobs y el migrado no, el rechazo los lista todos: una primera línea con los nombres (`Con un caso vacio fallan 2 jobs: JOB_A, JOB_B.`) y un párrafo por job, con su pista. Así se arreglan de una vez, sin relanzar para ver el siguiente. Con un solo job, el texto es el de siempre.
- **Tu test guardado no se reescribe a tus espaldas.** Cuando la IA guarda un test, el script apunta su huella. Si un test guardado ya no vale en este commit y lo has cambiado tú (su huella no es la que apuntó el script, o es un test de antes de esta versión), la prueba se para con 1 antes de llamar a Copilot. Dice por qué falla y cómo seguir: arréglalo en `prueba-local\arnes\<lado>` y relanza sin `-Rehacer`, o relanza con `-RehacerArnes` (migrado) o `-RehacerOriginal` (original) para que la IA lo escriba otra vez (el tuyo pasa a `prueba-local\arnes-anterior\<lado>`). Con los dos lados así, un solo mensaje. Un test tal cual lo escribió la IA que ya no vale se escribe otra vez, como siempre.
- **Un test que se escribe otra vez no queda peor.** El de antes no se borra: pasa a `prueba-local\arnes-anterior\<lado>` (y el caso vacío del original, a `salidas\vacio-anterior`). El test nuevo del original no puede acabar el caso vacío peor que el de antes (el estado del job, las tablas y las columnas pedidas): se rechaza mientras queden intentos. En el último, si está peor, se vuelve al de antes sin repetir los casos; si solo le faltan columnas, se acepta con un aviso. Su primer intento lleva hasta 3 líneas de lo que falló en el caso vacío de antes, con la causa de `salidas\vacio\causas.json` o, en un test guardado antes de esta versión, la del registro de Maven más reciente de ese caso vacío. Si un test guardado ya no vale en este commit y se va a escribir otra vez, la consola siempre lo avisa (`El test PruebaLocalTest del <lado> de otro lanzamiento ya no vale en este commit (...): se vuelve a escribir`), también el del migrado cuando cambia el test del original guardado.
- **Un test que no le pasa las entradas al job.** Si en un job ningún caso deja nada distinto del caso vacío, sus casos salen `no se pudo preparar`: no cuentan como iguales y el `-Cierre` no pasa. La prueba sigue con los demás jobs, guarda `prueba-local.json` (o el de `-Rapida`) y acaba con 2. Al final lo dice en rojo, una vez por job. Tus tests guardados no se tocan: arréglalos en `prueba-local\arnes\original` y `arnes\migrado` y relanza sin `-Rehacer`, o relanza con `-RehacerOriginal` (el del original y, con él, el del migrado) y la IA recibe el motivo.
- **Cambios sin commit.** La prueba copia el último commit del original y de la rama que se prueba (la de rescate, si existe). Si su `src` o su `pom.xml` tienen cambios sin commit, la consola lo avisa en amarillo, una vez por carpeta y con el commit que usa, y sigue. Si esos cambios son parte del arreglo, haz commit y relanza. Lo de fuera de `src` y `pom.xml` no avisa.
- **Un fichero en otra carpeta.** Si el original deja un fichero en una carpeta y el migrado, con el mismo nombre, en otra, es una sola diferencia `otraCarpeta` (las carpetas de cada lado y si el contenido es igual), no un `(no esta)` por cada copia. Los casos con esa diferencia salen en un grupo por pareja de carpetas, con la ayuda «Suele ser el test del migrado…: relanza con `-RehacerArnes`». El test del migrado que se escribe otra vez recibe una línea por pareja (3 como mucho) para dar a sus propiedades de carpetas los valores del original. Las tablas no se emparejan así.
- **Ficheros de entrada que un lado quita.** Si el caso trae un fichero de entrada (el mismo nombre en `casos\<job>\<caso>\ficheros\`) y el original lo quita o lo mueve y el migrado no, o al revés, todos los casos así salen en un solo grupo («el migrado deja ficheros de entrada que el original quita») y no uno por nombre de fichero; `medido:` lista los ficheros. No cuentan `tablas\`, `datos.sql`, los de `otraCarpeta` ni los de contenido distinto.

Para encontrar el commit que rompe un caso:

```powershell
.\prueba-local.ps1 -Legacy C:\ruta\original -Migrado C:\ruta\migrado -Desde <tu-rama>
.\prueba-local.ps1 -Legacy C:\ruta\original -Migrado C:\ruta\migrado -Desde <tu-rama> -Deshacer
```

- `-Desde <tu-rama>` busca entre los commits que la rama de rescate tiene encima de la tuya.
- Dice «el caso X era igual en <commit> y se rompe en <commit> (<asunto>)».
- Con `-Deshacer`, hace `git revert` de ese commit (nunca un reset) y vuelve a ejecutar el caso. Si no existe `C:\ruta\migrado-rescate`, el revert va a tu rama.
- `prueba-local.ps1` lanzado así no rehace las páginas. Para ver la página 3 al día, relanza `migracion.ps1` con las mismas opciones. Con un commit nuevo en la rama de rescate, repite la comparación solo de las fichas cuyos ficheros del migrado han cambiado (tarda y gasta Copilot) y la prueba en local entera. Un commit que no toca esos ficheros, como uno solo de `src/test`, no repite ninguna comparación, ni la de las clases ni la de los `.sh`. Las páginas 2 y 4 no cambian.

### Arreglar lo que venía distinto: `-Reparar`

```powershell
.\prueba-local.ps1 -Legacy C:\ruta\original -Migrado C:\ruta\migrado -Reparar
```

- Hace la prueba de siempre y, si hay casos `distinto`, Copilot escribe arreglos en `src/main/` de la copia del migrado. Una diferencia (la clave) cada vez, empezando por la que tienen más casos, y como mucho 8 por lanzamiento (`MaxReparaciones`). Lo que no se prueba, lo dice.
- El script solo da por bueno un arreglo si pasa seis puertas, de la más barata a la más cara: la llamada acaba bien; Copilot no dice que no se arregla; solo cambia `src/main/`; el caso mejora; ningún otro caso empeora; y los tests unitarios del proyecto no fallan más ni se ejecutan menos que al empezar. Si el arreglo rompe un test, el motivo del reintento nombra los tests y dice por qué falla el primero (`El primero falla con: <mensaje del informe de Surefire>`, la primera línea y 300 letras como mucho). A Copilot solo se le dan las carpetas que existen: la salida de un migrado que no ha dejado nada no va en `--add-dir`.
- Lo que pasa va a la rama de rescate, en un commit por arreglo (`rescate(local): <job>/<caso> <clave>`). Lo que no pasa se deshace y se reintenta una vez, con el motivo y el diff rechazado. Tu carpeta y tu rama no se tocan.
- Una clave que ya se probó no se vuelve a probar mientras no cambien `src/main/` ni el `pom.xml` del migrado (ni su test del arnés). Un commit que solo toca `src/test`, como el de `-Regresion`, no la hace volver a gastar Copilot.
- Revisa esos commits (`git log`, `git show`) antes del `git merge` del paso 4. Con `-Job <job>` solo se miran los casos de ese job, también al comprobar que nada empeora. Si un arreglo deja menos líneas distintas pero la clave sigue distinta, sale «Mejorado», no «Arreglado».
- No se combina con `-Desde` ni con `-Deshacer`. Pide que exista `C:\ruta\migrado-rescate` y que no tenga cambios sin commit.
- **No promete nada sobre el entorno real.** Si un caso sale distinto solo porque la prueba local simula algo (la base de datos, el correo, el SFTP), Copilot lo dice y no cambia nada. Un arreglo que iguala la salida de la prueba local se revisa, y se prueba en pre.
- **Si Copilot dice que la diferencia es del test del migrado** (`No se arregla ...: ... el arnés ...`), el que falla es `PruebaLocalTest` del migrado, no tu código. Escríbelo otra vez, traduciendo el del original, y vuelve a reparar:

  ```powershell
  .\prueba-local.ps1 -Legacy C:\ruta\original -Migrado C:\ruta\migrado -RehacerArnes -Reparar
  ```

  El test del original no se toca. Las claves que salieron «no se arregla» se vuelven a probar con el test nuevo.
- **Si casos salen «no se pudo preparar» con «La base de prueba no tiene la tabla X»**, el test guardado del original no crea esa tabla (es de antes de que se comprobaran las tablas). Escríbelo otra vez con `-RehacerOriginal` (y con él el del migrado, que lo traduce); al acabar, la consola cuenta cuántos casos son. Los casos que quedaron «sin probar en local» por lo mismo se vuelven a preparar en ese lanzamiento (la consola dice cuántos). Si un test queda atascado, relanzar el mismo comando lo vuelve a intentar con dos intentos nuevos.
- **Si casos salen «no se pudo preparar» con «El test del original crea mal una tabla»**, el test del original saca mal las tablas del SQL del código: escríbelo otra vez con `-RehacerOriginal`; la consola cuenta cuántos casos son, y el primer intento del test nuevo recibe lo que falló la otra vez (el último motivo de su tarea de antes y las pistas de esos casos).
- **Si casos salen «no se pudo preparar» con «El test del original no crea la columna T.C (la usa fichero:línea)»**, el test del original crea la tabla sin una columna que el código usa y los casos cargan: escríbelo otra vez con `-RehacerOriginal`; la consola cuenta cuántos casos son, y el primer intento del test nuevo recibe la pista con la tabla, la columna y el sitio del código (hasta tres columnas).
- **Si varios casos salen distintos porque el migrado acaba `FAILED` (o `EXCEPCION`) y el original no, con la misma causa** (por ejemplo, una `NullPointerException` porque un listener lee un contexto que en producción pone el arranque de la aplicación), puede ser el test del migrado y no el código: escríbelo otra vez con `-RehacerArnes`. El test nuevo recibe la causa de cada grupo de 2 casos o más (hasta 3) y una frase que le dice que prepare lo que falta como los tests de ejemplo y que no tape un fallo de `src/main`. Además, el test del migrado ya recibe, junto a sus ejemplos, los métodos de preparación (`@BeforeEach`, `@BeforeAll`, `@Before`, `@BeforeClass`, hasta 5, con `fichero:línea`) de los tests de ejemplo de la copia.
- **Si el original falla igual en los 3 primeros casos de un job** (la misma causa: no arranca, `EXCEPCION` o `FAILED`), los demás casos de ese job no se ejecutan en ningún lado y salen `sin probar en local` con el motivo «el original falla igual en los primeros casos de este job con este test…: relanza con -RehacerOriginal». El original funciona en producción: si falla igual en todos, es su test. Un job de 3 casos o menos se ejecuta entero.
  - El primer intento del test nuevo del original lleva esas causas. Si el original falla con `NoSuchFileException`, `FileNotFoundException` o `AccessDeniedException` sobre una ruta absoluta fuera de la carpeta del caso, lleva además una pista: la propiedad que da esa ruta y su `fichero:línea`, para que le dé una carpeta del caso como hace el test del migrado. Solo la busca en los `application*.properties`, `.yml` y `.yaml` de `src/main/resources`, y no ve una ruta con espacios.
  - Si el test nuevo queda peor que el de antes en el caso vacío, pero el de antes dejaba un job así, se queda el nuevo y la consola lo dice.
  - `prueba-local.json` lleva en `jobs[].falloIgual` lo de cada job parado o con error del código: lado, estado, clase, causa, regla (si la hay) y si se paró.
- **Si el migrado falla igual en los 3 primeros casos de un job** (la misma causa) y el original no falla así, los demás casos de ese job no se ejecutan en el migrado y salen `sin probar en local` con su motivo. La consola te dice que lo arregles y relances (con `-Rapida`, para comprobarlo en minutos). En `prueba-local.json`, el job lleva `falloIgual` con `lado = migrado` y `parado`. Un job de 3 casos o menos se ejecuta entero.

### Volver a comprobar, cuando quieras

Después de cualquier cambio (tuyo, de Sonar, de la cobertura o de un merge), lanza otra vez la prueba en local:

```powershell
.\prueba-local.ps1 -Legacy C:\ruta\original -Migrado C:\ruta\migrado
```

- Ejecuta los mismos casos en el original y en el migrado, y los compara. No vuelve a pedir a Copilot lo que ya hizo (los casos y sus entradas); solo ejecuta y compara.
- El migrado se ejecuta siempre. El original no se repite mientras no cambie su commit, su test, las entradas del caso ni el JDK o Maven con que corre: la consola dice cuántos casos reutiliza. Para obligar a repetirlo, borra `migracion-<batch>\prueba-local\salidas`.
- **El original se ejecuta con UTF-8, como en el servidor** (sus Maven llevan `JAVA_TOOL_OPTIONS=-Dfile.encoding=UTF-8`, además de lo que ya tuvieras), y no con la codificación de Windows: un `camión` no sale como `camiÃ³n`. Las salidas guardadas del original de antes se ejecutan otra vez una vez.
- **Cada caso, sin el ciclo entero de Maven.** Cada copia se compila una vez (`mvn test-compile`) y cada caso corre con `mvn surefire:test -Dtest=PruebaLocalTest -Dprueba.local.job=<job> -Dprueba.local.caso=<caso>`, en su propia JVM. Si cambia algo en el `src\` de la copia (menos la carpeta de los casos) o en su `pom.xml`, se compila otra vez antes del siguiente caso, desde cero: así no queda una clase vieja. Si surefire no llega a ejecutar el test (por ejemplo, con `@{argLine}` sin sustituir se repite con `-DargLine=`), esa copia vuelve a `mvn test` el resto del lanzamiento y la consola lo dice una vez. No promete que corra un plugin del pom ligado a la fase `test` que no sea surefire: si lo necesitas, pon `"MavenCasoDirecto": false` en `ajustes.json`. Las salidas guardadas del original siguen valiendo. La línea final dice también cuántas veces se ha compilado y cuánto ha tardado, y `datos\prueba-local-tiempos.json` lleva el modo de cada fila.
- **Prueba el último commit, no lo que tengas sin commit.** Haz commit antes.
- **Si existe `C:\ruta\migrado-rescate`, prueba esa copia y no tu rama.** Si ya trajiste sus cambios (paso 4), bórrala antes con `git -C C:\ruta\migrado worktree remove C:\ruta\migrado-rescate`.
- La respuesta sale en la consola y en `migracion-<batch>\datos\prueba-local.json`. Para ver también la página 3 al día, relanza `migracion.ps1 -SoloInforme` con las mismas opciones del paso 1.

## Paso 4. Revisar y juntar los cambios con tu rama

Primero mira lo que se ha hecho:

```powershell
git -C C:\ruta\migrado log --oneline <tu-rama>..<rama-rescate>
git -C C:\ruta\migrado diff --stat <tu-rama>...<rama-rescate>
```

El nombre de la rama de rescate sale por consola al crearla (`Rama nueva: 'rescate/...'`). Si lo has perdido: `git -C C:\ruta\migrado worktree list`, o `rama` en `migracion-<batch>\datos\estado.json`. Si un commit no te convence, quítalo con `git -C C:\ruta\migrado-rescate revert <commit>` y, si ya hiciste la prueba en local, hazla otra vez.

Cuando estés conforme, lanza el cierre. Va solo (no admite `-SoloInforme`, `-Si`, `-Practicas`, `-Reglas`, `-RevisarTodo` ni `-Reintentar`), no usa IA y no pregunta nada:

```powershell
.\migracion.ps1 -Legacy C:\ruta\original -Migrado C:\ruta\migrado -Plantilla C:\ruta\referencia -Cierre
```

Qué hace, en este orden. Para en la primera cosa que falla, con una parada `cierre-<motivo>` y un texto que dice qué hacer; hasta el último paso no mueve ni tu rama ni la de rescate.

1. **Comprueba que está todo probado.** La pasada tiene que estar corregida y acabada. La prueba en local tiene que estar hecha, con algún caso igual y ninguno distinto en cada job, y sobre el código de ahora. Y tu carpeta no puede tener cambios sin commit (haz commit o `git stash`). Si la rama de rescate no tiene commits que no estén ya en la tuya, dice «No hay nada que juntar» y sale con 0. Si has borrado la carpeta de rescate, `-Cierre` la vuelve a montar desde su rama (y, si la rama tampoco está, recrea la rama desde el commit que probó la prueba en local); si tu rama ya lo tiene todo, lo dice y sale con 0.
2. **Junta en la carpeta de rescate, nunca en la tuya.** Si tu rama ha avanzado desde la pasada, hace allí el `git merge`. Si choca, lo deshace todo y para con `cierre-conflicto`, con un texto para pegar en Copilot: que junte tu rama en la carpeta de rescate, respetando los cambios de los dos lados. Cuando esté hecho (con commit), lanza otra vez `-Cierre`. La IA no resuelve conflictos por su cuenta.
3. **Pasa las puertas sobre lo juntado**, con el mismo diagnóstico de la pasada: tiene que compilar, los tests no pueden fallar si en tu rama no fallaban y no puede haber ningún error nuevo (frente a tu rama) en `build`, `estructura`, `hexagonal`, `ficheros`, `config` ni `tests`. Si lo juntado ha cambiado el código, repite la prueba en local y tiene que seguir saliendo igual. Si falla una puerta (`cierre-puertas`), la carpeta de rescate vuelve a donde estaba. Lo que no para (los errores que ya tenías, las otras áreas y la limpieza: marcas pendientes, código comentado, clases sin uso) sale como aviso en la consola y en `estado.json`, en `cierre.avisos`.
4. **Avanza tu rama** con `git merge --ff-only`, y solo si es un fast-forward. Antes apunta en `estado.json`, en `cierre`, el commit de tu rama de antes y la línea para deshacerlo. Esa línea sale también por consola: `git -C "C:\ruta\migrado" reset --hard <commit-de-antes>`.
5. **Te dice qué revisar antes del push**: los commits que tocan `src/main/resources` (la configuración) salen en la consola y en `cierre.revisar`. No hace push: el push es siempre tuyo.

Relanzar la pasada no deshace el cierre. Y lanzar `-Cierre` otra vez con tu rama ya en el commit del cierre solo dice «Ya está juntado» y cómo deshacerlo, sin lanzar Maven.

| Motivo | Qué ha pasado | Qué haces |
|---|---|---|
| `cierre-pendiente` | La pasada no está lista: sigue corriendo, está parada, hay casos distintos, faltan correcciones... | El texto trae el caso y el comando que toca. Hazlo y vuelve a lanzar `-Cierre` |
| `cierre-prueba-local` | No hay prueba en local, un job no tiene ningún caso igual o tiene distintos, o el código ha cambiado desde que se probó | Relanza la pasada (sin `-SinPruebaLocal`) |
| `cierre-cambios-sin-commit` | Tu carpeta tiene cambios sin commit | `git add` y `git commit`, o `git stash`, y vuelve a lanzar `-Cierre` |
| `cierre-conflicto` | Tu rama y la de rescate cambian lo mismo | Pega el texto en Copilot (o resuélvelo tú en `C:\ruta\migrado-rescate` y haz commit) y vuelve a lanzar `-Cierre` |
| `cierre-puertas` | Lo juntado no compila, hace fallar tests, trae un error nuevo, o la prueba en local repetida no sale igual | Mira el texto: dice cuál. Arregla en la carpeta de rescate (o relanza la pasada) y vuelve a lanzar `-Cierre` |
| `cierre-no-ff` | Tu rama ha avanzado mientras se medían las puertas | Vuelve a lanzar `-Cierre` |
| `cierre-motor` | El diagnóstico del cierre ha fallado | Pega el mensaje y las últimas líneas de `registros\diagnostico-cierre.log` en el chat |

Después, si ya no la quieres, quita la carpeta de rescate: `git -C C:\ruta\migrado worktree remove C:\ruta\migrado-rescate`.

### El repo de configmap

El batch migrado lee sus variables (`${...}`) de un configmap que vive en otro repo. `-ConfigMap` te lo escribe junto a la carpeta del migrado, con la forma del repo de configmap de un batch que ya migraste.

```powershell
.\migracion.ps1 -Legacy C:\ruta\original -Migrado C:\ruta\migrado -Plantilla C:\ruta\referencia -ConfigMap -Inventario C:\ruta\inventario -ConfigMapReferencia C:\ruta\configmap-de-referencia
```

- `-Inventario`: la carpeta del inventario del original, con una carpeta por entorno y sus `.properties`. De ahí salen los valores. No lee nada más: ni el vault ni otros ficheros.
- `-ConfigMapReferencia`: el repo de configmap de referencia. Si no lo das, te lo pregunta la primera vez y lo guarda en `ajustes.json`. Si tiene `.git`, solo cuenta lo que ve git (lo seguido y lo nuevo que no ignora): un `__pycache__` ignorado ni se copia ni es tarea. Cada fichero de sus carpetas de punto (`.github`…) es una tarea de la IA: si alguna no debe ir al repo nuevo, pásale una copia de la referencia sin esa carpeta, con la misma última carpeta (de ella sale el nombre del repo nuevo).
- El inventario y el modelo quedan en `datos\configmap.json`: para relanzar basta `-ConfigMap`. Lo atascado se repite con `-Reintentar`.
- No hace `git init`, commit ni push: eso es tuyo.
- Se lanza solo, sin `-Cierre`, `-SoloInforme`, `-Si`, `-Practicas`, `-Reglas` ni `-RevisarTodo`. Aparte, si ya tiene el inventario y la referencia, `-Cierre` lo hace al final. Nunca para el cierre: si falla, avisa con la ruta de `registros\configmap-error.log`.

La IA empareja cada variable con una clave del inventario (de una lista cerrada), escribe cada entorno y cada fichero de la plataforma, y los revisa. El script comprueba cada respuesta y garantiza siempre esto:
- Cada variable sale en cada entorno con su valor o con `<PENDIENTE>`.
- Un secreto sale sin su valor. Es secreto lo que lo dice su nombre (`password`, `token`, `credencial`, `private`, `apikey`, `user` al final...) o lo que lleva credenciales dentro del valor (`https://usuario:clave@host`, `usuario/clave@host`).
- El valor de un secreto no sale en ningún fichero como palabra entera. Si sale, se borra el fichero; si ese fichero lo has cambiado tú, solo avisa. Si el valor es tan común que sale en los nombres, no se puede vigilar: va a `PENDIENTE.md` para que lo mires.
- El nombre del batch de referencia no queda en ningún sitio.
- Copilot no puede usar la consola, y lo que escribe fuera de su sitio se deshace. Si cambia algo en el migrado, te avisa.

**Lo que te toca:** abre `PENDIENTE.md` en el repo nuevo. Tiene, por entorno, cada variable con su estado (valor puesto, pendiente o secreto que hay que pedir), los `<PENDIENTE: ...>` con fichero y línea, lo que ha encontrado la revisión y lo atascado. Pon lo que falte, haz `git init` y commit. Al relanzar, lo que has cambiado a mano se respeta.

## Paso 5. Sonar

```powershell
.\rescate.ps1 -Repo C:\ruta\migrado -Sonar C:\ruta\informe.xlsx
```

- Funciona con cualquier proyecto Maven de Java. No necesita la referencia ni el original.
- Solo arregla Java: cualquier incidencia `BLOCKER`, `CRITICAL` o `MAJOR`, y los `BUG` y `VULNERABILITY` que no sean `MINOR` ni `INFO`.
- Lo sagrado es no cambiar la lógica de negocio. Lo que no se puede arreglar sin cambiarla no se toca.
- No se para por una incidencia difícil: termina todo y al final dice «Faltan N de Sonar», con el motivo de cada una. La lista queda en `C:\ruta\migrado-rescate\.rescate\sonar-faltan.md`.
- Los arreglos van a la rama de rescate, como en el paso 2. Después repite los pasos 3 y 4: relanza `migracion.ps1 -SoloInforme` para que la prueba en local mire el código nuevo, y `prueba-local.ps1 -Desde <tu-rama>` si algún caso pasa a `distinto`.
- Las reglas del paso están en `sonar-reglas.ps1`.
- Al empezar, la consola enseña cuántas incidencias hay de cada familia (constantes, logs, complejidad…). La tabla entera queda en `.rescate\sonar-por-familia.tsv`.
- La IA solo compila. Los tests los pasa el script, una vez por intento.
- Cada intento deja una línea en `.rescate\intentos.tsv`: paso, lote, segundos de Copilot y de Maven, y si pasa o no. Al acabar, la consola dice cuánto se ha ido en Copilot y cuánto en Maven.
- Cada lote pasa solo los tests ligeros. Los de Spring, que arrancan el contexto o lanzan un job, van en un control: la suite entera cada 10 lotes y al final. La lista de los que se dejan fuera queda en `.rescate\tests-de-contexto.txt`.
- Si un control sale en rojo, el script busca el lote que lo ha roto y lo deshace con `git revert`. Sus ficheros no se vuelven a intentar en esa pasada. Si no lo encuentra, deshace todos los lotes desde el último control en verde. Al final, la rama ha pasado la suite entera, o la consola lo dice en rojo.
- Para cambiar cada cuántos lotes va el control, pon en `.rescate\config.json` `"LotesEntreControles": 5`. Para volver a pasar la suite entera en cada lote: `"PasosTestsElegidos": []`.

### La cobertura

```powershell
.\rescate.ps1 -Repo C:\ruta\migrado -Cobertura
```

- Escribe tests, clase a clase, hasta llegar al 80 % de líneas cubiertas (`CoberturaMinima`). Empieza por las clases a las que más líneas les faltan.
- Solo escribe en `src\test`. Si toca cualquier otra cosa, el intento no vale: así la lógica de negocio no puede cambiar.
- Un test solo se queda si pasa 3 veces seguidas, sube la cobertura de su clase y comprueba un valor de verdad.
- Si un test descubre algo que parece un error del código, no lo arregla: lo deja marcado con `// OJO: parece un error` para que lo mires tú.
- Al final dice «Cobertura: X % -> Y %» y lo que falta, también en `C:\ruta\migrado-rescate\.rescate\cobertura-faltan.md`.
- Como mucho 40 clases por pasada (`CoberturaClasesMax`). Si no llega, relánzalo.

## Paso 6. Pre

En `1-batch-original.html`, cada job tiene «Cómo probarlo en pre»: qué lanzar, con qué datos y qué tiene que salir. La prueba en local simula lo de fuera (base de datos, SFTP, correo). La conexión de verdad solo se prueba en pre.

Antes de lanzar nada en pre, mira en «Cómo probarlo en pre» de cada job si puedes lanzar el viejo y el nuevo a la vez o uno detrás de otro. En cada lanzamiento (y tras `-Cierre`) `migracion.ps1` lo dice, sin IA, con los motivos y qué reponer entre una ejecución y la otra; lo deja en `datos\convivencia.json`. Por defecto es uno detrás de otro: solo sale «a la vez» si ninguno de los dos escribe nada que el otro lea. Las tablas `BATCH_` no se comparten nunca: el nuevo necesita su propio esquema o prefijo.

Si el original no guarda las ejecuciones de Batch (un repositorio Map, un `setDataSource` vacío en `DefaultBatchConfigurer` o una H2 en memoria) y el migrado deja Spring Batch en la base del negocio, el diagnóstico da un error `repositorio-batch`. En pre, el primer arranque fallaría porque faltan las tablas `BATCH_`, o las crearía en la base del negocio. En local no se ve, porque la prueba usa H2. Dale a Batch su propia base en memoria: un `DataSource` H2 con `@BatchDataSource`, como la plantilla si lo tiene. Ojo: así Spring aparta el `DataSource` del negocio. Para no perderlo, con Spring Boot 3.4 o más pon `@Bean(defaultCandidate = false)` en el de Batch; antes, declara el del negocio y márcalo `@Primary`. H2 va en el pom con scope `runtime`, no `test`. Si la plantilla tampoco lo hace, queda en aviso: pregunta a devops cómo lo resuelven en pre.

## Paso 7. Subir y otra vuelta de Sonar

1. `git push` de tu rama.
2. Sonar pasa en tu CI. Si dice que la rama es `main` cuando no lo es, no pasa nada: el script no mira la rama.
3. Descarga el xlsx nuevo y vuelve al paso 5 con él.

## Si te pierdes

### ¿En qué punto estoy?

Lanza `.\donde-estoy.ps1` en la carpeta de los scripts. Solo lee, no cambia nada. Saca un bloque por cada batch que tengas al lado de esa carpeta:
- en qué punto está;
- el siguiente paso, con su comando, que es el mismo que el de la portada;
- el comando de la cobertura, si no llega al mínimo.

Para un solo batch: `.\donde-estoy.ps1 -Migrado C:\ruta\migrado`. También puedes preguntárselo a Copilot en esa carpeta, porque lee `AGENTS.md`: lanza el script y te repite el comando.

| Pregunta | Dónde mirar |
|---|---|
| ¿Qué ha hecho `migracion.ps1` y qué me toca? | `.\donde-estoy.ps1`, `migracion-<batch>\index.html`, o `datos\estado.json` (`fase` y `parada`) |
| ¿Qué commits ha hecho el script? | `git -C C:\ruta\migrado-rescate log --oneline <tu-rama>..` |
| ¿Cuántos problemas quedan? | `.\rescate.ps1 -Repo C:\ruta\migrado -Plantilla C:\ruta\referencia`: solo diagnostica, no cambia nada |
| ¿Qué le pidió a Copilot y qué contestó? | `migracion-<batch>\registros\` y `C:\ruta\migrado-rescate\.rescate\lote-*.log` |

**Relanzar el mismo comando siempre es seguro:** salta lo hecho y sigue donde se quedó. Es seguro porque **para** antes de borrar nada: si `C:\ruta\migrado-rescate` tiene cambios sin commit (salvo los de un intento cortado, que van a un `git stash`), o si hay una rama `rescate/...` con arreglos que no están en tu rama, lo dice y sale con 1 sin tocar nada.

Un corte (Ctrl+C, la ventana, la luz) en mitad de una ronda de lectura, de buenas prácticas o de tests de reglas no hace falta que lo arregles: lo que Copilot dejó a medias en `C:\ruta\migrado-rescate` va a un `git stash` al relanzar (el aviso trae la orden `git -C ... stash apply <hash>` para recuperarlo) y la pasada sigue sola. **Mientras corre una pasada, no edites esa carpeta:** una ronda deshace lo que no reconoce como suyo, y eso incluye lo que tú toques a mano.

### Cuando `migracion.ps1` se para

Sale en rojo (en amarillo si es el tope de tiempo), con el motivo, y la portada trae un texto listo para pegar en Copilot en otra ventana. Arregla la causa y relanza el mismo comando.

| Motivo | Qué ha pasado | Qué haces |
|---|---|---|
| `copilot-no-responde` | Varias llamadas seguidas han fallado: sesión, cuota o red | Comprueba que Copilot responde en otra ventana y relanza |
| `tope-de-tiempo` | Se ha llegado a `-MaxHoras` | Relanza |
| `no-compila` | Después de corregir, el migrado no compila | Mira `registros\correccion.log`. Arregla en `C:\ruta\migrado-rescate`, haz commit ahí y relanza |
| `lotes-deshechos` | 6 ficheros atascados seguidos, sin ningún arreglo bueno entre medias | Casi siempre es Copilot, Maven o un parámetro, no el código. Mira el último `lote-*.log`. Al relanzar no se reintentan esos ficheros: ver «Ficheros atascados» abajo |
| `guardas` | Alguien ha cambiado el original o la referencia | `git status` y `git diff` en esa carpeta, déjala como estaba y relanza |
| `git` | No se ha podido hacer un commit | Mira el mensaje de git en el registro |
| `cambios-sin-commit` | Al arrancar, la carpeta de rescate tiene cambios sin commit que no son de un intento cortado. Para antes de la prueba de aptitud | Si son tuyos, haz commit allí; si no, `git stash`. Los comandos salen en el mensaje. Relanza |
| `motor` o `error-interno` | Fallo del script | Pega el mensaje y las últimas líneas del registro en el chat |

### Mensajes de un lote

| Mensaje | Qué pasa | ¿Tienes que hacer algo? |
|---|---|---|
| `NO PASA:` | El lote no cumple una comprobación | No: reintenta con el motivo |
| `Lote ... DESHECHO` | Ha agotado los intentos | No: lo deshace entero y sigue |
| `ATASCADO` | Un fichero no sale ni solo | Al final: lo apunta en `.rescate\atascados.md` y sigue con los demás. Ver «Ficheros atascados» abajo |
| `PARO:` | 6 ficheros atascados seguidos | Sí: ver `lotes-deshechos` arriba |

### Ficheros atascados

Al acabar, el motor los lista como «lo único que te toca mirar» y sale con 2. Al relanzar no los reintenta, salvo que el fichero haya cambiado. Dos salidas:

- Arréglalo a mano en `C:\ruta\migrado-rescate` y termina con un commit allí (`git -C C:\ruta\migrado-rescate add -A` y `git -C C:\ruta\migrado-rescate commit -m "arreglo a mano"`). Sin ese commit, el relanzamiento se para para no perderlo.
- O reinténtalo: el comando de `rescate.ps1` del paso 2 con `-Reintentar`, y `-ModeloB <id>` si quieres un modelo de reserva.
| `ALTO:` | Ha cambiado la referencia o el original | Sí: ver `guardas` arriba |

### Volver atrás

| Quiero | Cómo |
|---|---|
| Deshacer el último lote | `.\rescate.ps1 -Modo deshacer -Repo C:\ruta\migrado`. Solo mientras exista `C:\ruta\migrado-rescate`: después del paso 4 no lo uses, porque actuaría sobre tu rama |
| Quitar un commit concreto | `git -C C:\ruta\migrado-rescate revert <commit>` |
| Empezar de cero los arreglos | `git -C C:\ruta\migrado worktree remove --force C:\ruta\migrado-rescate`, `git -C C:\ruta\migrado branch -D <rama-rescate>`. Al relanzar con `-Si`, la corrección se hace otra vez porque sus commits ya no están en la carpeta de rescate (y se aparta la de antes en `migracion-<batch>\datos\anterior-<commit>`). Tu rama queda como estaba |
| Deshacer el cierre | La línea `git -C "C:\ruta\migrado" reset --hard <commit-de-antes>` que sale por consola al juntar, y que también está en `migracion-<batch>\datos\estado.json` (`cierre.deshacer`). Relanzar la pasada no lo deshace |
| Rehacer el informe desde cero | Borra `C:\ruta\migrado\migracion-<batch>\`. Se vuelve a pagar toda la lectura |
| Rehacer un caso de la prueba en local | Borra su carpeta en `migracion-<batch>\prueba-local\casos\` |

### Si Copilot rechaza un parámetro

Pon en `%USERPROFILE%\.rescate\ajustes.json` la lista `CopilotArgs` sin ese parámetro. No quites nunca `--deny-tool=shell(git push)`: es lo que impide que Copilot haga push.

### Códigos de salida

| Script | 0 | 1 | 2 | 3 | 4 |
|---|---|---|---|---|---|
| `migracion.ps1` | Bien, o tope de tiempo. Con `-Cierre`: juntado (volviendo a montar la carpeta de rescate si se borró), ya estaba juntado o no había nada que juntar | No pudo arrancar (con `-Cierre`, falta `estado.json` o no queda ni la carpeta de rescate, ni su rama, ni el commit probado) | Se ha parado (ver la portada) | No pudo copiar tus cambios sin commit: haz commit y relanza | |
| `rescate.ps1` | Bien | Falta algo o un parámetro está mal | Atascados, no compila o demasiados lotes deshechos | Git no pudo hacer el commit | Ha cambiado la referencia o el original |
| `prueba-local.ps1` | Todo lo comparado es igual | No ha podido | Hay casos distintos | | |
