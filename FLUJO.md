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
| 5 | `rescate.ps1 -Sonar` | Cuando tienes el xlsx de Sonar | Commits en `rescate/...` y `.rescate\sonar-faltan.md` |
| 6 | Tú, en pre | Antes de dar el batch por bueno | El guion de cada job, en la página 1 |
| 7 | `git push` y Sonar en tu CI | Al final | Un xlsx nuevo: vuelves al paso 5 |

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
- Abre `C:\ruta\migrado\migracion-<batch>\index.html`. `<batch>` es el `artifactId` del `pom.xml` del migrado. La portada dice cómo ha ido y qué te toca. Desde ahí llegas a las otras cuatro páginas.

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

## Paso 6. Pre

En `1-batch-original.html`, cada job tiene «Cómo probarlo en pre»: qué lanzar, con qué datos y qué tiene que salir. La prueba en local simula lo de fuera (base de datos, SFTP, correo). La conexión de verdad solo se prueba en pre.

## Paso 7. Subir y otra vuelta de Sonar

1. `git push` de tu rama.
2. Sonar pasa en tu CI. Si dice que la rama es `main` cuando no lo es, no pasa nada: el script no mira la rama.
3. Descarga el xlsx nuevo y vuelve al paso 5 con él.

## Si te pierdes

### ¿En qué punto estoy?

| Pregunta | Dónde mirar |
|---|---|
| ¿Qué ha hecho `migracion.ps1` y qué me toca? | `migracion-<batch>\index.html`, o `datos\estado.json` (`fase` y `parada`) |
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
