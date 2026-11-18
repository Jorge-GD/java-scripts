# Tarea: el test que ejecuta los casos de la prueba en local

Vas a escribir UN test de JUnit, `PruebaLocalTest`, en este repositorio: {{REPO}}. El test no comprueba nada: ejecuta los jobs del batch con unas entradas que ya están preparadas en carpetas y guarda lo que sale. Después, un script compara lo que sale aquí con lo que sale en la otra versión del mismo batch, que tendrá un test hecho con estas mismas reglas. Por eso tienes que seguir esta tarea al pie de la letra: lo que hagas de otra forma saldrá como una diferencia falsa.

TIPO: arnes-local
ESCRIBIR: {{TEST}}
JOBS: {{JOBS}}
POM: {{POM}}

## Qué ficheros puedes tocar

- `{{TEST}}`: el test, con todo lo que necesite dentro (clases internas incluidas). Es el único fichero de Java que escribes.
- `src/test/resources/application-prueba-local.yml`, solo si te hace falta configuración para este test (perfil de Spring `prueba-local`).
- Si POM es `si`, puedes añadir al `pom.xml` las dependencias que falten para el test, todas con `<scope>test</scope>` (por ejemplo `spring-boot-starter-test` o `spring-batch-test`). Nada más del `pom.xml`. Si POM es `no`, el `pom.xml` no se toca.

Nada más: ni el código de `src/main`, ni otros tests, ni la configuración del batch. Si cambias otra cosa, el script lo deshace y rechaza el test entero. Puedes lanzar `mvn` para probarlo y crear casos de prueba en `src/test/resources/prueba-local/`: el script los borra al acabar.

## Tests de ejemplo

Copia de estos tests la forma de arrancar el batch (anotaciones, cómo se lanza un job, cómo se simula lo de fuera):

{{EJEMPLOS}}

Pueden ser de otra versión de Spring Boot o de Java: usa solo lo que exista en la versión de este repositorio (mira su `pom.xml`) y escribe Java que compile con la versión de Java de ese `pom.xml` (por ejemplo, en Java 8 no hay `var` ni `List.of`).

## Qué hace el test

1. Busca las carpetas `src/test/resources/prueba-local/<job>/<caso>/` (ruta relativa a la carpeta del proyecto, la del `pom.xml`) en orden alfabético. `<job>` es el nombre de un job del batch (uno de JOBS). Si la propiedad de sistema `prueba.local.job` tiene valor, solo las de ese job. Si la propiedad `prueba.local.caso` tiene valor, solo las carpetas `<caso>` con ese nombre: el script lanza cada caso en su propio Maven, en una JVM nueva, como cada ejecución en producción. Si no hay ninguna carpeta, el test acaba bien sin hacer nada.
2. Para cada caso, en este orden:
   1. **Base de datos limpia**: cada tabla del batch como recién creada (sin filas y con los contadores autonuméricos desde el principio) y con los datos que el batch carga al arrancar (su `data.sql` o lo que use). Las tablas de Spring Batch (`BATCH_...`) se pueden quedar como estén. Usa una base en memoria; si el código abre su propia conexión con una URL fija, usa esa misma base, dentro de `target/`.
   2. Si el caso tiene `datos.sql`, ejecútalo en esa base.
   3. **Carpetas de trabajo vacías**: todas las carpetas de las que el job lee o en las que escribe ficheros (entrada, salida, errores, procesados, enviados...), dentro de una carpeta de trabajo bajo `target/`. Si el caso tiene `ficheros/`, copia cada subcarpeta `ficheros/<carpeta>/` a la carpeta de trabajo del job que se llama `<carpeta>` (la última parte de su ruta en la configuración o en el código; por ejemplo, `ficheros/entrada/` va a la carpeta de entrada). Si el código lee la carpeta raíz una sola vez (por ejemplo en campos `static`), usa una sola carpeta de trabajo para todo el test, fijada antes de arrancar Spring (por ejemplo en un bloque `static` del test), y vacíala entre caso y caso.
   4. Lanza el job `<job>` con los parámetros de `parametros.properties`, si el caso lo tiene (`clave=valor` por línea), más uno que haga única cada ejecución (por ejemplo `prueba.local.ejecucion` con la hora en milisegundos).
   5. Guarda la salida en `target/prueba-local/<job>/<caso>/` (formato abajo).
3. Si un caso no se puede preparar (un `datos.sql` que falla, una carpeta que no se puede crear), escribe el motivo en `target/prueba-local/<job>/<caso>/error.txt`, sigue con el siguiente y, al acabar todos, haz fallar el test diciendo qué casos fallaron. Que el job acabe mal (FAILED o una excepción) NO es un fallo del test: es una salida más y va a `estado.txt`.
4. El test no compara nada: no lleva ningún `assert` sobre lo que sale.

## Lo de fuera, simulado

Nada sale del equipo. La configuración del batch se queda como viene por defecto: lo que por defecto está apagado (por ejemplo, un envío de correo que solo se hace con una propiedad encendida) sigue apagado, y lo que el batch deja en la consola o en el log no es un envío. Lo que con esa configuración intentaría conectarse fuera (una base de datos de verdad, SFTP, correo, HTTP, colas) se simula: si el batch ya tiene un modo local (carpetas en vez de SFTP), usa ese; si no, sustituye la pieza que conecta por una de prueba que guarde lo que recibe en `envios/`. Las contraseñas y las variables que el batch pide para arrancar, con valores inventados en `application-prueba-local.yml` o en el test.

## Formato de la salida

En `target/prueba-local/<job>/<caso>/`, en UTF-8 y con saltos de línea `\n`:

- `estado.txt`: dos líneas, `estado=<BatchStatus de la ejecución>` y `salida=<código de ExitStatus>`; por ejemplo, `estado=COMPLETED` y `salida=COMPLETED`. Si lanzar el job lanza una excepción antes de tener ejecución: `estado=EXCEPCION` y `salida=<nombre simple de la clase de la excepción>`.
- `ficheros/<carpeta>/...`: una copia de cada carpeta de trabajo del job tal como queda al acabar (también la de entrada), con el mismo nombre de carpeta que en los `ficheros/` de los casos. Las carpetas vacías no se copian.
- `tablas/<TABLA>.csv`: uno por cada tabla que no es de Spring Batch, con el nombre de la tabla en mayúsculas. Primera línea: los nombres de las columnas en mayúsculas, en el orden de la tabla, separados por `;`. Después, una línea por fila: el valor de cada columna con `ResultSet.getString` (vacío si es null), separados por `;`. Lee las filas sin `ORDER BY`, une cada fila en su línea y ordena las líneas con `String.compareTo`.
- `envios/<n>-<tipo>.txt`: uno por cada envío que llegó a un simulado, en orden (`1-sftp.txt`, `2-correo.txt`...). Primero las líneas que digan a dónde iba, las que tenga: `destino=<carpeta o ruta remota y nombre del fichero>`, `para=<destinatarios separados por comas>`, `asunto=<asunto>`; después una línea vacía y lo que se envió (el contenido del fichero o el cuerpo del correo). Si no hubo ninguno, no hay carpeta.

## Cuando acabes

Comprueba con `mvn test-compile` que compila. Termina tu respuesta con una sola palabra: hecho.
<!--CORRECCION-->

## CORRECCIÓN: tu intento anterior no pasó la comprobación

El script ha revisado lo que escribiste y ha encontrado esto:

{{MOTIVO}}

Lo que habías cambiado se ha deshecho. Vuelve a escribir el test completo en ESCRIBIR (y lo demás que te haga falta de lo permitido), corrigiendo eso.
