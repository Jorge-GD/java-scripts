# java-scripts

Scripts sueltos para trabajar con proyectos Java.

## Antes de la primera vez: preflight

`preflight.ps1` se lanza **una vez**, antes de `migracion.ps1`, en el equipo donde se va a trabajar. Mide si ese equipo, Copilot y Maven sirven: versiones y modo de PowerShell, qué banderas conoce tu Copilot, si el modelo sabe rellenar una ficha de clase (un fichero de juguete y cinco clases tuyas), cuántas llamadas aguanta a la vez y si Maven compila, mide cobertura y refactoriza un proyecto de juguete. Con `-Modelos` hace además un examen de modelos (bloque 9, más abajo). No cambia ningún repo tuyo.

```powershell
.\preflight.ps1 -Legacy C:\ruta\original -Migrado C:\ruta\migrado -Plantilla C:\ruta\referencia -Modelo <id>
.\preflight.ps1 -Modelos claude-haiku-5.5,gpt-6-luna,mai-code-2-flash
```

Todo es opcional. `-Solo 1,3` hace solo esos bloques, `-SinCopilot` salta los que llaman al modelo (4, 5, 8 y 9) y `-SinMaven` salta Maven (6 y el diagnóstico del 7). Cada bloque avisa por consola de lo que puede tardar y, mientras corre, escribe una línea cada minuto (`... sigue: bloque 7, forma de los repos (lleva 3 min 0 s)`; `SegundosLatido` en `ajustes.json`): si deja de salir, se ha colgado. Esas líneas no entran en el fichero de resultado. El bloque 2 lanza el banco de pruebas `tests\probar.ps1` (hasta 30 min; `probar-migracion.ps1` es un banco de desarrollo y no entra). Si una ruta de `-Legacy`, `-Migrado` o `-Plantilla` no es una carpeta, lo dice al instante y no hace nada más. Copilot se lanza con el primer fichero `.exe`, `.com`, `.cmd`, `.bat` o `.ps1` que encuentra PowerShell con ese nombre (no una función, un alias ni el `copilot` sin extensión que deja npm); si no hay ninguno, lo dice y hay que poner la ruta entera del `.cmd` o del `.exe` en `CopilotExe` de `ajustes.json` (el resultado dice `tipo de copilot: ... | se lanza: ...`). Para Maven usa el de `ajustes.json` (`MvnExe`), si no el `mvn` del PATH y si no el `mvnw` de `-Migrado`; el resultado dice cuál (`maven usado`).

Deja `preflight-resultado.txt` junto al script (git lo ignora), lo reescribe al acabar cada bloque, lo enseña al final y lo copia al portapapeles si puede. **Ese fichero es lo que se pega en el chat.** No lleva rutas, usuario, equipo, dominio, correos, IP, URL internas ni nombres de tus repos, de sus clases o de sus ficheros: de tus repos solo salen números y el principio de un mensaje nuestro. Aun así, léelo antes de pegarlo.

**Examen de modelos (bloque 9).** Sin `-Modelos` no hace nada. Con `-Modelos <id>,<id>` pasa cuatro pruebas con cada modelo y cada esfuerzo de `-Esfuerzos` (por defecto solo `medium`; con `-Esfuerzos medium,max` prueba también el máximo), una detrás de otra para que los tiempos se puedan comparar:

- **L1 y L2:** la ficha de una clase de unas 200 líneas y la de otra de casi 300 (troceada como la trocea el sistema, una llamada por trozo). Mide si la ficha vale, cuántas citas se prueban y cuántas de las condiciones esperadas (`preflight\examen\claves.json`) trae.
- **E1 y E2:** arreglar dos errores de compilación y poner Javadoc, en dos proyectos Maven de juguete. Pasan si Maven pasa los tests, no se toca nada fuera de `src\main` y, en E2, el código queda igual y todo lo público lleva Javadoc. Necesitan Maven: con `-SinMaven` o si el bloque 6 falla salen como `sin maven` y no cuentan.

Al final suma créditos (`--usage-output-file`, si tu Copilot lo conoce), segundos y tokens de cada combinación y **recomienda una** con una regla fija: entre las que leen bien y arreglan todo, la de menos créditos. Cuenta de antemano cuántas llamadas son y cuánto puede tardar (2 min por llamada con `low` y `medium`; con otro esfuerzo, el tope de una llamada: `SegundosPorLlamada` de `ajustes.json`, 10 min como mucho en el preflight). Es **una sola pasada por combinación**: orientativo, no una estadística. Los ids de `-Modelos` son los que enseña `/model` dentro de Copilot; si no pasas `-Modelo`, los bloques 4, 5 y 8 usan el primero de la lista. Si un esfuerzo no lo admite el modelo, baja de `max` a `xhigh` y a `high` y lo dice; un modelo que no existe sale como `sin modelo`.

El diagnóstico del bloque 7 usa `rescate.ps1` en modo diagnóstico sobre `-Migrado`: deja allí su carpeta `.rescate`, que git ignora.

Ese mismo bloque cuenta cuántas reglas incumple la propia referencia (`plantilla incumple: capas N | ficheros N | calidad N | secretos N`, solo números), porque lo que ella hace se permite también en el migrado.

Si el resultado dice `original sin cambios: no`, mira `git status` en el original antes de seguir: algo lo tocó durante la lectura.

Si Windows no deja lanzar el script:

- Si bajaste el repo como zip, desbloquea los ficheros: `Get-ChildItem -Recurse | Unblock-File`. Con `git clone` no hace falta.
- Si tu empresa lo permite: `powershell -NoProfile -ExecutionPolicy Bypass -File .\preflight.ps1 -Legacy ... -Migrado ...`.
- Si el script no llega a arrancar, pega el error tal cual: también sirve.

## rescate.ps1

Primeros auxilios para un batch Java migrado a medias (Java 8 → Java 21, arquitectura hexagonal, SFTP y configuración externa).
Es un script de PowerShell (Windows PowerShell 5.1 o PowerShell 7). Necesita `git`, Maven y, para arreglar, GitHub Copilot CLI. Si lo copias a otra máquina, lleva también `comun.ps1`: `rescate.ps1` lo carga desde su misma carpeta.

Compara tu repo con una **plantilla** (un repo ya migrado y aprobado) y trabaja en cuatro fases:

| Fase | Usa IA | Qué hace |
|---|---|---|
| Diagnóstico | no | Cuenta los hallazgos por paso: `build`, `estructura`, `hexagonal`, `ficheros`, `config`, `paridad`, `e2e`, `tests`, `calidad`. No toca código. |
| Worktree | no | Crea al lado una carpeta `<repo>-rescate` con una rama `rescate/...`. Tu carpeta y tu rama no se tocan. |
| Plan | sí, solo lectura | Antes de arreglar un paso, Copilot lee **todos** los ficheros con hallazgos y la plantilla, y escribe `.rescate/plan-<paso>.md`. Tú lo lees y lo corriges. |
| Arreglo | sí | Arregla un paso en lotes pequeños siguiendo el plan. Tras cada lote se repite el diagnóstico entero y el script decide si el lote vale. |

Un lote solo se guarda (commit local, nunca push) si pasa todas las puertas:

- compila;
- bajan los hallazgos del paso;
- no empeoran los pasos anteriores;
- el código nuevo no añade hallazgos de calidad (el Javadoc incluido);
- no baja el número de `catch` de `src/main/java` (sin contar comentarios ni textos): quitar uno cambia cómo se tratan los errores; llevarlo a otro fichero vale;
- no se han borrado ni desactivado tests;
- no se ha tocado la plantilla ni el repo original.

Si no las pasa, el script reintenta con el error y, si sigue mal, deshace el lote entero.

Si el batch maneja ficheros, el paso `ficheros` exige siempre un adaptador SFTP y su bloque `sftp` en `application.yml`, tenga o no SFTP la plantilla. Para exigir solo lo que la plantilla tiene, pon `"ExigirSftp": false` en `.rescate/config.json`.

`rescate.ps1` lee también `ajustes.json` (`%USERPROFILE%\.rescate\ajustes.json`, el mismo del preflight y de `migracion.ps1`) antes que `.rescate/config.json`, que manda; las claves que no son suyas las ignora. Copilot se busca una vez al empezar, con la misma regla del preflight (un `.exe`, `.cmd`, `.bat` o `.ps1`, no una función ni el `copilot` sin extensión de npm): si no hay nada que lanzar, lo dice, pide la ruta entera en `CopilotExe` y sale con 1 antes de tocar el repo.

Mientras espera a Copilot o a Maven escribe una línea cada minuto (`... sigue: Copilot (paso estructura, lote 1, intento 1) (lleva 2 min 0 s)`; `SegundosLatido` en `.rescate/config.json`, 0 la apaga): si deja de salir, se ha colgado.

### Uso

```powershell
# 1) Diagnostico: seguro, no cambia nada
.\rescate.ps1 -Repo C:\ruta\batch-life -Plantilla C:\ruta\batch-terminado

# 2) Plan del siguiente paso pendiente: crea el worktree y escribe el plan
.\rescate.ps1 -Modo plan -Repo C:\ruta\batch-life -Plantilla C:\ruta\batch-terminado

# 3) Arreglar el siguiente paso, lote a lote, con pausa para revisar
.\rescate.ps1 -Modo fix -Repo C:\ruta\batch-life -Plantilla C:\ruta\batch-terminado

# 4) Al acabar: revisar y traer los cambios a tu rama
git -C C:\ruta\batch-life diff --stat <tu-rama>...<rama-rescate>
git -C C:\ruta\batch-life merge <rama-rescate>
git -C C:\ruta\batch-life worktree remove C:\ruta\batch-life-rescate
```

El resto de opciones (elegir paso, tamaño del lote, deshacer, modelo de reserva) está en la cabecera del script.

### Guía con IA

Si es tu primera vez, deja que una IA te acompañe. [GUIA-IA.md](GUIA-IA.md) es un prompt que le dice cómo guiarte paso a paso: comprobar el entorno, leer el diagnóstico, revisar el plan y el primer lote, y qué hacer si algo falla.

La guía va por trozos para que la IA no se adelante: `GUIA-IA.md` tiene las reglas y el mapa, y cada paso está en su fichero de la carpeta [guia/](guia/), que la IA lee solo cuando toca.

### Modelo y esfuerzo

Cada llamada a la IA es `copilot -p` con `--model` y `--effort`
([referencia de Copilot CLI](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference)). Los eliges tú:

| Parámetro | Para qué | Si no lo pasas |
|---|---|---|
| `-Modelo <id>` | Modelo de todas las llamadas. El id es el que enseña `/model` dentro de Copilot. | El que tenga Copilot. |
| `-EsfuerzoPlan <nivel>` | Esfuerzo de la revisión previa (pensar). | El de `-Esfuerzo`. |
| `-Esfuerzo <nivel>` | Esfuerzo de los lotes de arreglo (escribir). | El que tenga Copilot. |
| `EsfuerzoReintento` (solo en `.rescate/config.json`) | Esfuerzo de los intentos 2 y siguientes de un lote y de los reintentos de uno en uno, con el modelo de reserva y con el consejo, si es mayor que el de `-Esfuerzo`. Vacío = como antes. | `high`; si Copilot no lo acepta, baja con la misma regla que el modelo de las dudas. |
| `-ModeloB <id>` | Modelo de reserva cuando el principal se atasca con un fichero. También `ModeloB` en `ajustes.json` o `.rescate/config.json`; así lo usa también `migracion.ps1`, que lanza el fix sin `-ModeloB`. El parámetro manda. | No hay reserva. |
| `-ModeloDudas <id>` | Modelo fuerte de las dudas: el consejo y la reflexión (abajo). También `ModeloDudas` en `ajustes.json` o `.rescate/config.json`. | El de `-Modelo`. |
| `-EsfuerzoDudas <nivel>` | Esfuerzo del modelo de las dudas. También `EsfuerzoDudas` en los ajustes. | `max`; si Copilot no lo acepta, `xhigh` y luego `high`. |

Niveles: `low`, `medium`, `high`, `xhigh`, `max`. No todos los modelos admiten todos.

```powershell
.\rescate.ps1 -Modo fix -Repo ... -Plantilla ... -Modelo <id-del-modelo> -EsfuerzoPlan high -Esfuerzo medium -ModeloDudas <id-fuerte>
```

### Atascados, consejo y reflexión

- **Atascados.** Lo que la IA no sabe arreglar se apunta en `.rescate/atascados.json` (paso, fichero, motivo, huella del fichero y commit). En la pasada siguiente no se vuelve a intentar: el script lo dice una vez («N ficheros atascados de antes: no los reintento (usa -Reintentar)»). Se vuelve a intentar con `-Reintentar`, si el fichero ha cambiado o si desde que se atascó hay un commit que no es de un lote del script (por ejemplo, la pieza común que faltaba, hecha a mano en otro fichero).
- **Consejo.** Cuando un fichero se atasca también con el modelo de reserva, el modelo de las dudas da 3 opciones, elige una y dice si es de `codigo` o de `persona` (cambia el comportamiento de negocio, sube versiones del framework o del parent, toca credenciales o entornos, o pide información que no está en los repos). Si es de código, se hace un intento más con esa opción; si no, el fichero queda atascado con las 3 opciones en `atascados.md`. Con `-Auto`, las dudas del plan se resuelven igual: las de código van al plan como «## Decisiones» y las de persona salen al final en «Te toca decidir». Sin `-Auto`, el plan pregunta como siempre.
- **Reflexión.** Cuando un intento falla con los mismos NO PASA que el anterior del mismo lote (la misma lista sin las cifras, o los mismos hallazgos nuevos), el modelo de las dudas escribe `.rescate/reflexion-<paso>-<lote>-<intento>.md` (qué se intentó, por qué no pasó, qué hacer ahora, qué no hacer). Va en la corrección siguiente, al reintento de uno en uno, al modelo de reserva y al consejo. Por defecto solo reflexiona cuando el fallo se repite (`"Reflexionar": "repetido"`, decisión del usuario del 18-11-2026, al ver atascos reales con las mismas cuentas en los tres intentos); `"siempre"` (o `true`) reflexiona tras cada intento que no pasa y `"nunca"` (o `false`) la apaga, en `.rescate/config.json`. En nuestra medida (noviembre de 2026, Haiku, el caso de dos ficheros que necesitan la misma pieza común) no hubo ningún atasco en ninguno de los dos brazos (0 y 0 con ella y sin ella, en dos pasadas de cada) y la pasada con reflexión tardó de 3 a 4 veces más.
- **Comprobar.** `rescate.ps1 -Modo comprobar -Repo ... -Plantilla ...` (sin Maven, sin escribir nada) lista lo que el árbol ha roto frente al commit de partida del lote y sale con 1 si hay algo nuevo; los prompts de los lotes se lo piden a la IA antes de terminar.
- Todo queda en `.rescate/decisiones.md`.

Tras cada Maven, el script borra los ficheros nuevos sin seguimiento que Maven deja fuera de `target` y `.rescate` (las salidas de algunos tests); los que ha creado la IA se quedan.

Con `-Todo` y sin `.rescate/contrato.json`, el script hace antes lo del modo `pre` (la lista de jobs del original) y avisa de que esa lista no la ha revisado nadie.

### El paso `calidad`

Comprueba, por texto, el código de `src/main`:

| Regla | Cuenta como | Qué mira |
|---|---|---|
| `javadoc-tipo`, `javadoc-metodo` | error | Javadoc en clases, interfaces, records y enums públicos y en sus métodos públicos. Exentos: `@Override`, constructores, getters, setters, `main`, `equals`, `hashCode`, `toString`. |
| `inyeccion-campo` | error | `@Autowired` o `@Inject` en un campo. |
| `salida-consola` | error | `System.out`, `System.err`, `printStackTrace`. |
| `catch-vacio` | error | `catch` sin nada dentro (un comentario que lo explique vale). |
| `envoltorio-new` | error | `new Integer(...)` y similares. |
| `instanceof-cast`, `fecha-antigua`, `coleccion-antigua` | aviso | Sintaxis y API antiguas. No se arreglan solas: pueden cambiar el comportamiento. |

El Javadoc se exige aunque la plantilla no lo tenga. Las demás reglas bajan a aviso si la plantilla también las incumple.
Para apagar una regla, quítala de `CalidadErrores` en `.rescate/config.json`.

### Quién ya lo hizo

Antes de escribir estas comprobaciones miramos lo que ya existe (noviembre de 2026):

| Herramienta | Qué hace | Aquí |
|---|---|---|
| Checkstyle: [MissingJavadocType](https://checkstyle.org/checks/javadoc/missingjavadoctype.html) y [MissingJavadocMethod](https://checkstyle.org/checks/javadoc/missingjavadocmethod.html) | Exige Javadoc en lo público. | **Adaptado**: mismo criterio, escrito por texto para que el script no necesite instalar nada. |
| OpenRewrite: [UpgradeToJava21](https://docs.openrewrite.org/recipes/java/migrate/upgradetojava21) y [SpringBatch4To5Migration](https://docs.openrewrite.org/recipes/java/spring/batch/springbatch4to5migration) | Recetas que hacen solas la parte mecánica de la migración. | Recomendado **antes** de este script: lo mecánico lo hace mejor una receta que una IA. |
| [ArchUnit](https://www.archunit.org/userguide/html/000_Index.html) (`onionArchitecture()`) | Tests que vigilan las capas. | Recomendado **después**, para que la arquitectura no se vuelva a romper. |
| Sonar | Análisis de calidad completo. | Este script no lo sustituye. |

### Pruebas

`tests\probar.ps1` comprueba el script con repos de juguete, un Maven de mentira y un Copilot de mentira. Solo necesita `git`.

```powershell
.\tests\probar.ps1                 # todas
.\tests\probar.ps1 -Solo calidad   # solo las que llevan "calidad" en el nombre
```

### Límites

- Proyectos Maven de un solo módulo.
- Las comprobaciones son por imports y texto: avisan de lo evidente. No sustituyen la revisión de una persona.
- El worktree no trae los ficheros que git ignora (configuración local, `.env`). El script los lista al crearlo.

## migracion.ps1

Migración desatendida de un batch Java: lee el original, mide el migrado, lo corrige, compara y prueba. Un comando, dos preguntas (modelo y qué hacer al acabar el informe) y las cinco páginas del informe en `<Migrado>\migracion-<batch>\`. Las cabeceras del script explican cada fase.

```powershell
.\migracion.ps1 -Legacy C:\ruta\life-java8 -Migrado C:\ruta\batch-life -Si       # lee, corrige, compara y prueba en local
.\migracion.ps1 -Legacy ... -Migrado ... -SoloInforme                                # lee y compara; no corrige
.\migracion.ps1 ... -SinPruebaLocal                                                  # sin la prueba en local del final
.\migracion.ps1 ... -JavaLegacy C:\jdk8                                              # el JDK del original, si no compila con el de Maven
```

El orden con la respuesta `corregir` (`-Si`): diagnóstico, lectura (`fichas-clase`, `mapa`, `fichas-job`, `resumen`, `pruebas-pre`), `lectura-hecha`, `correccion`, **`comparar`** y **`prueba-local`**. Con `parar` (`-SoloInforme`), `comparar` va antes de `lectura-hecha`, sobre el migrado tal como llegó, y no hay corrección. Si la corrección se para, no se sigue con nada más. `comparar` sigue con git lo que la corrección movió: el renombrado de un fichero (`git diff -M`) y, de un fichero borrado, los ficheros donde aparecen 2 o más de sus líneas. Cada comparación dice con qué commit y en qué momento (`antes-de-corregir` o `despues-de-corregir`) se hizo, y se rehace si el worktree tiene un commit nuevo.

La última fase llama a `prueba-local.ps1` (con el mismo modelo y `-Si`) y su salida sale por la consola y queda en `registros\prueba-local.log`. Un fallo se avisa y la pasada sigue: el código de salida de `migracion.ps1` no depende de esta fase (0 bien, 1 no pudo arrancar, 2 se paró). `datos\estado.json` lleva `pruebaLocal` (`resultado`: `hecha`, `fallo` o `saltada`, y el código, los minutos, el detalle y el registro), `fase` (`hecha` al acabar todo, sin parada ni tareas pendientes) y `fin` (vacío mientras corre; la hora al salir, también con parada).

Lo que dicen las páginas de esa última fase: la página 3 (`3-original-vs-migrado.html`) empieza por «Probado ejecutando los dos», que sale de `datos\prueba-local.json` (las cuentas por job, cada caso distinto con sus líneas y lo que no se pudo comparar), y debajo va la lectura de la IA con el momento en que se hizo. La portada pone primero, en «Lo que te toca», los casos distintos al ejecutar los dos; muestra «Duró» cuando la pasada ha acabado (`fin`) y «Lleva» mientras corre; y lista la fase «Prueba en local» con su cuenta. La página 4 dice, por área, con cuántos hallazgos empezó y acabó la corrección.

## prueba-local.ps1

Prueba en local, caso a caso, que el batch migrado hace lo mismo que el original. Se lanza **después** de `migracion.ps1`, que deja los casos de cada job (el camino feliz y los límites) en `<Migrado>\migracion-<batch>\datos\pruebas\<job>.json`. Si no están, para y dice que se lance antes `migracion.ps1`. Necesita `comun.ps1`, `tareas.ps1` y `tareas\` junto al script, `git`, Maven y Copilot CLI.

```powershell
.\prueba-local.ps1 -Legacy C:\ruta\original -Migrado C:\ruta\migrado
.\prueba-local.ps1 ... -JavaLegacy C:\jdk8      # si el original no compila con el JDK de Maven
.\prueba-local.ps1 ... -Job cargaRecibosJob     # solo los casos de ese job
.\prueba-local.ps1 ... -Modelo <id> -Si         # otro modelo que el de migracion.ps1; sin preguntar
```

Lo que tiene que salir lo da el **original** al ejecutarse. La IA solo fabrica las entradas y escribe el test que ejecuta los casos; compara el script.

1. **Copias desechables.** `<Legacy>-prueba-local` (en el HEAD del original) y `<Migrado>-prueba-local` (en el último commit de la rama de rescate, si está el worktree `<Migrado>-rescate`; si no, en el de tu rama). Son worktrees de git sin rama y se rehacen en cada lanzamiento. Tus carpetas y tus ramas no se tocan: el script lo comprueba al acabar.
2. **Arnés.** Una tarea de IA por copia (las dos a la vez, esfuerzo `high`) escribe `PruebaLocalTest` junto a la clase con `@SpringBootApplication` y, si le hace falta, `src\test\resources\application-prueba-local.yml`. En el original puede añadir dependencias al `pom.xml`, solo con `<scope>test</scope>`. El script comprueba que no toca nada más, que compila, que con un caso vacío cada job deja su `estado.txt` y que respeta `prueba.local.caso`. Si falla, lo repite una vez con el motivo. Si vuelve a fallar, para y da un texto para pegar en Copilot.
3. **Entradas.** Una tarea de IA por caso (hasta 4 a la vez, esfuerzo `medium`) escribe en la copia del original `src\test\resources\prueba-local\<job>\<caso>\`: `ficheros\<carpeta>\`, `datos.sql` y `parametros.properties`. Si el caso pide cambiar la configuración (encender el correo, otro tope) o lanzar el job dos veces, escribe `no-aplica.txt` y el caso queda **sin probar en local**. El script comprueba que solo escribe en su carpeta y que el caso corre en el original.
4. **Ejecución, sin IA.** El original dos veces y el migrado una, cada caso en su propio Maven (`mvn test -Dtest=PruebaLocalTest -Dprueba.local.job=<job> -Dprueba.local.caso=<caso>`): una JVM nueva por caso, como cada ejecución en producción. Así lo que el batch guarda en campos `static` (un fichero abierto, un contador) no pasa de un caso al siguiente.
5. **Comparación.** Por cada caso compara `estado.txt`, `ficheros\`, `tablas\` (una por tabla, filas ordenadas) y `envios\` (lo que habría salido del equipo, simulado). No cuentan las horas, la fecha de hoy ni los saltos de línea `\r\n`.

| Resultado | Qué quiere decir |
|---|---|
| `igual` | El migrado deja lo mismo que el original. |
| `distinto` | Algo cambia. Dice el fichero, cuántas líneas y la primera de cada lado. Si solo cambia la codificación (JEP 400) o el formato de números o fechas (JEP 252), lo apunta como **posible diferencia del JDK**, sin esconderlo. |
| `no determinista` | El original da dos salidas distintas con la misma entrada. No cuenta como distinto. |
| `no se pudo preparar` | La IA no consiguió unas entradas válidas, el caso no corre en el original o falta el arnés del migrado. |
| `sin probar en local` | El caso trae `no-aplica.txt`, con el motivo. |

Por consola saca una tabla por job (casos, iguales, distintos, sin probar) y el detalle de lo que no es igual. El resultado queda en `migracion-<batch>\datos\prueba-local.json`. Sale con 0 si todo lo comparado es igual, con 2 si hay casos distintos y con 1 si no ha podido (o no ha podido comparar ninguno).

Lo de la IA queda en `migracion-<batch>\prueba-local\`: `arnes\`, `casos\`, `tareas\`, las salidas (`salidas\original`, `original-2` y `migrado`) y los registros de cada llamada y de cada Maven. Al relanzar no repite lo hecho, si no han cambiado sus entradas: solo vuelve a ejecutar y a comparar. Un arnés de antes se vuelve a comprobar en el commit de ahora (por ejemplo, tras un arreglo en la rama de rescate) y solo se vuelve a escribir si ya no pasa. Para rehacer un caso, borra su carpeta de `prueba-local\casos\`.

**Lo que no promete.** Las entradas son inventadas y lo de fuera (base de datos, SFTP, correo, HTTP) está simulado. La conexión de verdad se prueba en pre, con el guion de cada job que deja `migracion.ps1`.

Banco de pruebas: `tests\probar-local.ps1`, con un Copilot y un Maven de mentira. Solo necesita `git`.
