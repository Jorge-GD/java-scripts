# java-scripts

Scripts sueltos para trabajar con proyectos Java.

**¿Por dónde empiezo?** [FLUJO.md](FLUJO.md): qué lanzar, en qué orden y qué hacer si te pierdes.

**¿En qué punto va cada batch?** `.\donde-estoy.ps1`. Solo lee y te da el siguiente comando de cada batch. Copilot, abierto en esta carpeta, lo lanza por ti: sigue `AGENTS.md`.

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
Es un script de PowerShell (Windows PowerShell 5.1 o PowerShell 7). Necesita `git`, Maven y, para arreglar, GitHub Copilot CLI. Si lo copias a otra máquina, lleva también `comun.ps1` (y `sonar-reglas.ps1`, si vas a usar `-Sonar`): `rescate.ps1` los carga desde su misma carpeta.

Compara tu repo con una **plantilla** (un repo ya migrado y aprobado) y trabaja en cuatro fases:

| Fase | Usa IA | Qué hace |
|---|---|---|
| Diagnóstico | no | Cuenta los hallazgos por paso: `build`, `estructura`, `hexagonal`, `ficheros`, `config`, `paridad`, `e2e`, `tests`, `calidad` (y `sonar` con `-Sonar`, `cobertura` con `-Cobertura`). No toca código. |
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

# 3 bis) Forma corta con un informe de Sonar: arregla sus incidencias, sin plantilla ni parar entre lotes
.\rescate.ps1 -Repo C:\ruta\batch -Sonar C:\ruta\informe.xlsx

# 3 ter) Forma corta para subir la cobertura: escribe tests, una clase por lote, hasta el objetivo (80 %)
.\rescate.ps1 -Repo C:\ruta\batch -Cobertura

# 4) Al acabar: revisar y traer los cambios a tu rama
git -C C:\ruta\batch-life diff --stat <tu-rama>...<rama-rescate>
git -C C:\ruta\batch-life merge <rama-rescate>
git -C C:\ruta\batch-life worktree remove C:\ruta\batch-life-rescate
```

El resto de opciones (elegir paso, tamaño del lote, deshacer, modelo de reserva) está en la cabecera del script.

### Modelo y esfuerzo

Cada llamada a la IA es `copilot -p` con `--model` y `--effort`
([referencia de Copilot CLI](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference)). Los eliges tú:

| Parámetro | Para qué | Si no lo pasas |
|---|---|---|
| `-Modelo <id>` | Modelo de todas las llamadas. El id es el que enseña `/model` dentro de Copilot. | El que tenga Copilot. |
| `-EsfuerzoPlan <nivel>` | Esfuerzo de la revisión previa (pensar). | El de `-Esfuerzo`. |
| `-Esfuerzo <nivel>` | Esfuerzo de los lotes de arreglo (escribir). | El que tenga Copilot. |
| `EsfuerzoReintento` (solo en `.rescate/config.json`) | Esfuerzo de los intentos 2 y siguientes de un lote y de los reintentos de uno en uno, con el modelo de reserva y con el consejo, si es mayor que el de `-Esfuerzo`. Vacío = como antes. | `high`; si Copilot no lo acepta, baja con la misma regla que el modelo de las dudas. |
| `MinutosMaven` (en `ajustes.json` o `.rescate/config.json`) | Tope de cada llamada a Maven (build y tests de cada lote, cobertura y cada caso de la prueba en local). Pasado, se para Maven con sus procesos hijos y la llamada cuenta como fallida: «Maven se ha pasado del tope de N min y se ha parado». Así un test colgado no se come la noche. | `30` |
| `MinutosCopilot` (en `ajustes.json` o `.rescate/config.json`) | Tope de cada llamada a Copilot de `rescate.ps1` (lotes de arreglo, revisión previa, consejo y reflexión). Pasado, se para Copilot con sus procesos hijos: «Copilot se ha pasado del tope de N min y se ha parado». Un lote se evalúa como cualquier otro con lo que haya dejado en el árbol y no se repite la llamada; una llamada de solo lectura cuenta como fallida. Así una llamada colgada no se come la noche. | `20` |
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

### El paso `sonar`

Opcional y para cualquier proyecto Maven de Java: no necesita `-Plantilla` ni `-Legacy`. Sin `-Sonar` el paso no existe (ni fila en la tabla ni cuenta).

| Parámetro | Para qué |
|---|---|
| `-Sonar <informe.xlsx>` | El informe de Sonar (la hoja `Issues Breakdown`; si no está, la primera hoja que tenga `Severity`, `Message`, `Issue Type` y `Path`). Añade el paso `sonar` el último. Solo con `-Repo` y `-Sonar`, hace el arreglo entero del paso `sonar`, sin parar entre lotes (`-Modo fix`, `-Paso sonar` y `-Auto` quedan puestos). Con `-Todo`, va detrás de los demás pasos. |

- Arregla solo Java y solo lo que dicen `SonarTipos` (por defecto `BUG` y `VULNERABILITY`, salvo `MINOR` e `INFO`) y `SonarSeveridades` (`BLOCKER`, `CRITICAL`, `MAJOR`). Las columnas se buscan por nombre y alias (`SonarColumnas`). Del xlsx solo se lee la hoja de incidencias.
- Lo sagrado es no cambiar la lógica de negocio. En un lote se pueden cambiar `.java` y crear `.java` nuevos en `src/main/java` y `src/test/java`, pero una clase nueva va en el mismo paquete que una clase que el lote arregla. No valen tocar otros ficheros, borrar o renombrar nada de `src/test`, ni borrar o renombrar una clase de `src/main/java` cuyo nombre aparece en `src/main/resources`. `SonarProhibido` (en `.rescate/config.json`) añade reglas sobre el diff entero del lote, con las líneas de las clases nuevas como añadidas: silenciar a Sonar, desactivar tests, quitar `@Test`, `catch` genéricos. Cada entrada puede llevar `Si` (solo se aplica si algún mensaje del lote casa) y `Salvo` (no se aplica si algún mensaje del lote casa).
- Las reglas (el prompt general, `SonarRecetas`, `SonarNoAutomatizar` y `SonarProhibido`) están en `sonar-reglas.ps1`, junto a `rescate.ps1`; `.rescate/config.json` puede sustituir cada una. Las `Rx` de `SonarProhibido` se aplican a la línea sin su `+` o `-` y sin distinguir mayúsculas (`(?-i:...)` las distingue).
- `SonarRecetas`: texto por regla que se añade al prompt del lote cuando algún mensaje la cumple (`Avisar` lista al final lo que cambia el resultado a propósito). `SonarNoAutomatizar`: mensajes que no se mandan al modelo.
- El modelo puede dejar una incidencia con su motivo en `.rescate/sonar-sin-arreglar.txt`: no se reintenta ni cuenta como atasco. Un fichero atascado tampoco para la pasada.
- Al acabar, «Faltan N de Sonar» con la lista agrupada por motivo, también en `.rescate/sonar-faltan.md`, y los mensajes sin receta ni exclusión con su cuenta.
- `.rescate/sonar-base.json` guarda el hash del xlsx y, por incidencia, su unidad de código y si esta pasada la resolvió (regla y commit del lote). Con otro xlsx la base se rehace y la anterior queda en `.rescate/sonar-base-anterior.json`.

El ciclo: pasada con `-Sonar`, push, Sonar en tu CI, xlsx nuevo, otra pasada.

### El paso `cobertura`

Opcional y para cualquier proyecto Maven de Java con tests que pasan: no necesita `-Plantilla` ni `-Legacy`. Sin `-Cobertura` el paso no existe. Sonar pide un 80 % de cobertura en el código nuevo y una migración cambia casi todo: este paso escribe **solo tests**, una clase por lote, hasta llegar a `CoberturaMinima` (80). La lógica de negocio no se toca.

| Parámetro | Para qué |
|---|---|
| `-Cobertura` | Añade el paso `cobertura` el último. Solo con `-Repo` y `-Cobertura`, hace el arreglo entero del paso (`-Modo fix`, `-Paso cobertura` y `-Auto` quedan puestos). Con `-Todo`, va detrás de los demás pasos y de `sonar`. Con `-Sonar` y `-Cobertura` a la vez y sin `-Paso` ni `-Todo`, solo hace `sonar`: lanza después `-Cobertura` sola. |

- Mide con JaCoCo por coordenadas (sin tocar el pom), con los tests. Si no compila o los tests fallan, para: primero `-Paso build` o `-Paso tests`.
- Un hallazgo por clase con líneas sin cubrir (sumando sus clases internas), de las que más faltan a las que menos: «`<cubiertas>/<total> lineas (<pct> %)`». Si el total ya llega al objetivo, ninguno.
- No propone lo de `CoberturaExcluir` (por defecto `config/`, `dto/`, `model/`, la clase `@SpringBootApplication` y los records sin métodos); lo dice al final.
- El lote es una clase. El prompt (`CoberturaPrompt`) lleva la clase entera, su test si existe y las líneas que JaCoCo da como no cubiertas. Pide ampliar `src/test/java/<paquete>/<Clase>Test.java`, solo con lo que ya hay en el pom.
- Puertas del lote, además de las de siempre (compila, no se borran ni se desactivan tests, plantilla y original intactos). Las adoptamos de los filtros de TestGen-LLM de Meta (compila, pasa de forma fiable, sube la cobertura):

| Puerta | Qué exige | Cuándo se mira |
|---|---|---|
| P1 | Solo se crean o cambian ficheros bajo `src/test/`: nada en `src/main/`, ni el `pom.xml`. Y el lote escribe `<Clase>Test.java`. | Antes de Maven |
| P4 | Cada `@Test` nuevo o cambiado tiene una aserción de verdad (`assert*`, `verify`, `assertThrows`, `assertThat`...). No valen `assertTrue(true)`, `@Disabled`, `Thread.sleep` ni un `catch` vacío añadidos. | Antes de Maven |
| P5 | No pasan más tests a fallar que antes. | Con Maven |
| P2 | Los tests de la clase pasan 3 veces seguidas (`mvn test -Dtest=<Clase>Test`, `CoberturaRepeticiones`). Si una falla, son inestables. | Si lo anterior pasa |
| P3 | La cobertura de líneas de la clase sube y el total no baja. | Si lo anterior pasa |

- Una clase se intenta una vez por pasada. Como mucho `CoberturaClasesMax` (40) clases por pasada; se para antes si llega al objetivo.
- Si el modelo cree que el código tiene un error, no lo arregla ni lo esconde: deja el test fijado tal cual y escribe `// OJO: parece un error: <motivo>`.
- Al acabar: «Cobertura: X % -> Y % (objetivo Z %)». Si no llega, «Faltan estas clases» con su motivo (atascada, sin intentar por el tope, mejorada pero incompleta), las excluidas y los `// OJO:` con su fichero y línea. Todo también en `.rescate/cobertura-faltan.md`.
- Cada lote cuesta un Maven más (JaCoCo) y las repeticiones de P2.

### Quién ya lo hizo

Antes de escribir estas comprobaciones miramos lo que ya existe (noviembre de 2026):

| Herramienta | Qué hace | Aquí |
|---|---|---|
| Checkstyle: [MissingJavadocType](https://checkstyle.org/checks/javadoc/missingjavadoctype.html) y [MissingJavadocMethod](https://checkstyle.org/checks/javadoc/missingjavadocmethod.html) | Exige Javadoc en lo público. | **Adaptado**: mismo criterio, escrito por texto para que el script no necesite instalar nada. |
| OpenRewrite: [UpgradeToJava21](https://docs.openrewrite.org/recipes/java/migrate/upgradetojava21) y [SpringBatch4To5Migration](https://docs.openrewrite.org/recipes/java/spring/batch/springbatch4to5migration) | Recetas que hacen solas la parte mecánica de la migración. | Recomendado **antes** de este script: lo mecánico lo hace mejor una receta que una IA. |
| [ArchUnit](https://www.archunit.org/userguide/html/000_Index.html) (`onionArchitecture()`) | Tests que vigilan las capas. | Recomendado **después**, para que la arquitectura no se vuelva a romper. |
| Sonar | Análisis de calidad completo. | Este script no lo sustituye: con `-Sonar` arregla las incidencias de un informe suyo. |

### Pruebas

`tests\probar.ps1` comprueba el script con repos de juguete, un Maven de mentira y un Copilot de mentira. Solo necesita `git`.

```powershell
.\tests\probar.ps1                 # todas
.\tests\probar.ps1 -Solo calidad   # solo las que llevan "calidad" en el nombre
```

### Límites

- Proyectos Maven de un solo módulo.
- Sin Sonar en local, «resuelta» quiere decir que la línea marcada ha cambiado; la prueba de verdad es volver a pasar Sonar y relanzar con el xlsx nuevo.
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
.\prueba-local.ps1 ... -Desde <tu-rama>          # de cada caso distinto, el commit de la rama de rescate que lo rompe
.\prueba-local.ps1 ... -Desde <tu-rama> -Deshacer   # y lo deshace con git revert (solo commits nuevos encima)
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

**El commit que rompe un caso (`-Desde`).** Para cada caso `distinto`, ejecuta el migrado en `<Desde>` y, si allí era `igual`, busca por bisección (`git rev-list --first-parent`) el primer commit donde deja de serlo. Cada commit se prueba en una copia desechable con el arnés ya guardado; el original no se repite y no se llama a Copilot. Un commit donde el caso no se puede ejecutar cuenta como malo, y se dice. Con `-Deshacer`, hace `git revert` de cada culpable, del más nuevo al más viejo, en la carpeta de la rama que se prueba (`<Migrado>-rescate` si existe; si no, la tuya), y vuelve a ejecutar esos casos. No deshace si hay cambios sin commit, si el commit es un merge o si el revert da conflicto (lo aborta). `datos\prueba-local.json` lo guarda en `culpables`.

Banco de pruebas: `tests\probar-local.ps1`, con un Copilot y un Maven de mentira. Solo necesita `git`.

## analisis.ps1

Mide las buenas prácticas de un repo Java con analizadores reales y sin servidor: SpotBugs con fb-contrib (los mismos motores que salen en Sonar) y PMD con un ruleset corto (`analisis\pmd-sonar.xml`, cada regla con la de Sonar a la que equivale). Se lanzan por coordenadas de Maven, sin tocar el pom del repo. Solo son funciones: el preflight comprueba que se pueden descargar y el paso `sonar` las usará para comprobar que un arreglo no crea incidencias nuevas.

Banco de pruebas: `tests\probar-analisis.ps1`, con un Maven de mentira y XML de un análisis real.
