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

1. **Tu carpeta y tu rama no se tocan.** Los arreglos van a una copia al lado, `C:\ruta\migrado-rescate`, con su rama `rescate/...`. Tú decides cuándo traerlos con un `git merge`. La única excepción es `prueba-local.ps1 -Deshacer` cuando no existe la carpeta `-rescate` (ver el paso 3).
2. **Nada hace push.** Subir es siempre cosa tuya.

## El mapa

| Paso | Qué lanzas | Cuándo | Qué te deja |
|---|---|---|---|
| 0 | `preflight.ps1` | Una vez por equipo | `preflight-resultado.txt` |
| 1 | `migracion.ps1 -SoloInforme` | Al empezar con un batch | Las 5 páginas del informe, sin cambiar código |
| 2 | `migracion.ps1 -Si` | Para arreglar lo que dice el informe | Commits en la rama `rescate/...` y la página 4 |
| 3 | Va dentro del paso 2; `prueba-local.ps1 -Desde` si sale «distinto» | Después de cada corrección | La página 3: original y migrado ejecutados con las mismas entradas |
| 4 | `git merge` | Cuando estás conforme | Los arreglos en tu rama |
| 5 | `rescate.ps1 -Sonar` y `rescate.ps1 -Cobertura` | Cuando tienes el xlsx de Sonar, o la cobertura no llega al 80 % | Commits en `rescate/...`, `.rescate\sonar-faltan.md` y `.rescate\cobertura-faltan.md` |
| 6 | Tú, en pre | Antes de dar el batch por bueno | El guion de cada job, en la página 1 |
| 7 | `git push` y Sonar en tu CI | Al final | Un xlsx nuevo: vuelves al paso 5 |

## Si todavía no hay migrado: empezar desde cero

Si el batch aún no se ha migrado, el migrado empieza siendo una copia del original en una rama nueva:

```powershell
git clone C:\ruta\original C:\ruta\migrado
git -C C:\ruta\migrado switch -c migracion-java21
```

Después, los pasos de siempre. El paso 2 lo acerca a la referencia: Java 21, Spring Boot 3, `jakarta`, la API nueva de Spring Batch, la estructura de carpetas, el SFTP y la configuración. El paso 3 comprueba que sigue haciendo lo mismo que el original.

- Ojo: así solo se ha probado con un batch inventado. Con uno real, espera más ficheros atascados que en un batch ya migrado.
- Si tu equipo crea los repos de otra forma (un repo nuevo, otro `artifactId`), créalo así y copia dentro el código del original antes del paso 1.

## Paso 0. Preflight, una vez por equipo

```powershell
.\preflight.ps1 -Legacy C:\ruta\original -Migrado C:\ruta\migrado -Plantilla C:\ruta\referencia -Modelo <id>
```

Comprueba que PowerShell, Copilot, Maven, SpotBugs y PMD funcionan en tu equipo. Si algo falla, pega `preflight-resultado.txt` en el chat. Quita rutas, usuario, equipo y correos, pero léelo antes de pegarlo.

Usa en todos los pasos el mismo `-Modelo <id>` del preflight. Sin él, la primera vez `migracion.ps1` te pregunta con un menú.

## Paso 1. La foto de cómo está

```powershell
.\migracion.ps1 -Legacy C:\ruta\original -Migrado C:\ruta\migrado -Plantilla C:\ruta\referencia -SoloInforme
```

- Lee el original, mide el migrado, compara los dos leyendo el código y los ejecuta con las mismas entradas (la prueba en local).
- No cambia código.
- Si el original no compila con el JDK de Maven, añade `-JavaLegacy C:\ruta\jdk-del-original`. Sin eso, la prueba en local se queda sin hacer.
- Si el original se lanza con scripts `.sh` que no están en su carpeta, añade `-Lanzadores C:\ruta\scripts`. Sin ningún `.sh`, la página 1 y la 3 lo dicen.
- Abre `C:\ruta\migrado\migracion-<batch>\index.html`. `<batch>` es el `artifactId` del `pom.xml` del migrado. La portada dice cómo ha ido y qué te toca. Arriba del todo, el recuadro «Siguiente paso» dice qué hacer ahora, con el comando listo para copiar. Desde ahí llegas a las otras cuatro páginas.

| Página | Qué cuenta | Para quién |
|---|---|---|
| `1-batch-original.html` | Qué hace el batch, job a job, y cómo probar cada job en pre | Negocio y tú |
| `2-problemas.html` | Los problemas del migrado: estructura, hexagonal, SFTP, configuración, Javadoc, cobertura | Tú |
| `3-original-vs-migrado.html` | Caso a caso, si el migrado da lo mismo que el original | Tú |
| `4-correcciones.html` | Qué se ha corregido y qué queda | Tú |

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
- Opcional: para que la corrección de `calidad` vaya como la de Sonar (la IA solo compila, cada lote pasa los tests ligeros y un control pasa la suite entera), pon en `C:\ruta\migrado-rescate\.rescate\config.json` (el que lee la corrección; antes de crear la copia vale el de `C:\ruta\migrado\.rescate\config.json`) `{"PasosSoloCompila": ["sonar", "calidad"], "PasosTestsElegidos": ["sonar", "calidad"]}`. Por defecto no cambia nada: mide el paso en `.rescate\intentos.tsv` antes y después, y `migracion.ps1` solo avisa de claves «desconocidas».
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
| `distinto` ya en el paso 1 | Venía así de la migración. Mira la diferencia que enseña la página 3 y arréglalo tú |
| `no determinista` | El original da dos salidas distintas con la misma entrada. No cuenta |
| `no se pudo preparar` o `sin probar en local` | Ese caso se prueba en pre |

Para encontrar el commit que rompe un caso:

```powershell
.\prueba-local.ps1 -Legacy C:\ruta\original -Migrado C:\ruta\migrado -Desde <tu-rama>
.\prueba-local.ps1 -Legacy C:\ruta\original -Migrado C:\ruta\migrado -Desde <tu-rama> -Deshacer
```

- `-Desde <tu-rama>` busca entre los commits que la rama de rescate tiene encima de la tuya.
- Dice «el caso X era igual en <commit> y se rompe en <commit> (<asunto>)».
- Con `-Deshacer`, hace `git revert` de ese commit (nunca un reset) y vuelve a ejecutar el caso. Si no existe `C:\ruta\migrado-rescate`, el revert va a tu rama.
- `prueba-local.ps1` lanzado así no rehace las páginas. Para ver la página 3 al día, relanza `migracion.ps1` con las mismas opciones. Con un commit nuevo en la rama de rescate, repite la comparación leyendo código (tarda y gasta Copilot) y la prueba en local. Las páginas 2 y 4 no cambian.

### Volver a comprobar, cuando quieras

Después de cualquier cambio (tuyo, de Sonar, de la cobertura o de un merge), lanza otra vez la prueba en local:

```powershell
.\prueba-local.ps1 -Legacy C:\ruta\original -Migrado C:\ruta\migrado
```

- Ejecuta los mismos casos en el original y en el migrado, y los compara. No vuelve a pedir a Copilot lo que ya hizo (los casos y sus entradas); solo ejecuta y compara.
- **Prueba el último commit, no lo que tengas sin commit.** Haz commit antes.
- **Si existe `C:\ruta\migrado-rescate`, prueba esa copia y no tu rama.** Si ya trajiste sus cambios (paso 4), bórrala antes con `git -C C:\ruta\migrado worktree remove C:\ruta\migrado-rescate`.
- La respuesta sale en la consola y en `migracion-<batch>\datos\prueba-local.json`. Para ver también la página 3 al día, relanza `migracion.ps1 -SoloInforme` con las mismas opciones del paso 1.

## Paso 4. Revisar y traer los cambios

```powershell
git -C C:\ruta\migrado log --oneline <tu-rama>..<rama-rescate>
git -C C:\ruta\migrado diff --stat <tu-rama>...<rama-rescate>
git -C C:\ruta\migrado merge <rama-rescate>
git -C C:\ruta\migrado worktree remove C:\ruta\migrado-rescate
```

El nombre de la rama de rescate sale por consola al crearla (`Rama nueva: 'rescate/...'`). Si lo has perdido: `git -C C:\ruta\migrado worktree list`, o `rama` en `migracion-<batch>\datos\estado.json`. Si un commit no te convence, quítalo antes del merge con `git -C C:\ruta\migrado-rescate revert <commit>`.

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

**Relanzar el mismo comando siempre es seguro:** salta lo hecho y sigue donde se quedó.

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

- Arréglalo a mano en `C:\ruta\migrado-rescate` y haz commit allí.
- O reinténtalo: el comando de `rescate.ps1` del paso 2 con `-Reintentar`, y `-ModeloB <id>` si quieres un modelo de reserva.
| `ALTO:` | Ha cambiado la referencia o el original | Sí: ver `guardas` arriba |

### Volver atrás

| Quiero | Cómo |
|---|---|
| Deshacer el último lote | `.\rescate.ps1 -Modo deshacer -Repo C:\ruta\migrado`. Solo mientras exista `C:\ruta\migrado-rescate`: después del paso 4 no lo uses, porque actuaría sobre tu rama |
| Quitar un commit concreto | `git -C C:\ruta\migrado-rescate revert <commit>` |
| Empezar de cero los arreglos | `git -C C:\ruta\migrado worktree remove --force C:\ruta\migrado-rescate`, `git -C C:\ruta\migrado branch -D <rama-rescate>` y borra `migracion-<batch>\datos\correcciones.json` (si no, `-Si` se salta la corrección). Tu rama queda como estaba |
| Rehacer el informe desde cero | Borra `C:\ruta\migrado\migracion-<batch>\`. Se vuelve a pagar toda la lectura |
| Rehacer un caso de la prueba en local | Borra su carpeta en `migracion-<batch>\prueba-local\casos\` |

### Si Copilot rechaza un parámetro

Pon en `%USERPROFILE%\.rescate\ajustes.json` la lista `CopilotArgs` sin ese parámetro. No quites nunca `--deny-tool=shell(git push)`: es lo que impide que Copilot haga push.

### Códigos de salida

| Script | 0 | 1 | 2 | 3 | 4 |
|---|---|---|---|---|---|
| `migracion.ps1` | Bien, o tope de tiempo | No pudo arrancar | Se ha parado (ver la portada) | No pudo copiar tus cambios sin commit: haz commit y relanza | |
| `rescate.ps1` | Bien | Falta algo o un parámetro está mal | Atascados, no compila o demasiados lotes deshechos | Git no pudo hacer el commit | Ha cambiado la referencia o el original |
| `prueba-local.ps1` | Todo lo comparado es igual | No ha podido | Hay casos distintos | | |
