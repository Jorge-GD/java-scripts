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
| `-ModeloB <id>` | Modelo de reserva cuando el principal se atasca con un fichero. | No hay reserva. |

Niveles: `low`, `medium`, `high`, `xhigh`, `max`. No todos los modelos admiten todos.

```powershell
.\rescate.ps1 -Modo fix -Repo ... -Plantilla ... -Modelo <id-del-modelo> -EsfuerzoPlan high -Esfuerzo medium
```

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
