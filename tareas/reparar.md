# Tarea: arreglar en el migrado una diferencia con el original

Un batch Java se ha migrado. Un script ha ejecutado el mismo caso de prueba en el batch original y en el migrado (este repositorio), con las mismas entradas, y ha comparado lo que deja cada uno. Lo que deja el original es lo correcto. Vas a cambiar el código del migrado, en `src/main/`, para que el caso deje lo mismo que el original.

TIPO: reparar
JOB: {{JOB}}
CASO: {{CASO}}

## El caso

TÍTULO: {{TITULO}}
ENTRADA: {{ENTRADA}}
ESPERADO: {{ESPERADO}}

ESPERADO solo sirve para que entiendas el caso. Lo que vale es lo que hace el original.

## La diferencia que tienes que arreglar

En el fichero `{{FICHERO}}` hay {{LINEAS}} líneas distintas. La primera, la {{LINEA}}:

- original: {{ORIGINAL}}
- migrado: {{MIGRADO}}
{{SI_CAUSA}}- fallo: {{CAUSA}}

Otras diferencias de este mismo caso (hasta 5; si arreglas la causa, es probable que se arreglen también):

{{OTRAS}}

## Dónde mirar (solo leer)

- El código del batch original: `{{RUTA_ORIGINAL}}`
- Lo que dejó el original en este caso: `{{SAL_ORIGINAL}}`
- Lo que deja ahora el migrado en este caso: `{{SAL_MIGRADO}}`
- Las entradas del caso: `{{ENTRADAS}}`

Busca en el original qué hace distinto y mira el código del migrado que escribe ese fichero. La causa suele estar en una sola pieza: la ruta de salida, el formato de una línea, un redondeo o un fallo del job en este caso.

## Qué puedes lanzar

Solo estos dos comandos de Maven, desde la carpeta de este repositorio, y ningún otro:

- `mvn -q test-compile`
- `mvn test -Dtest=PruebaLocalTest -Dprueba.local.job={{JOB}} -Dprueba.local.caso={{CASO}}`

El segundo ejecuta este caso en el migrado y deja lo suyo en `target/prueba-local/{{JOB}}/{{CASO}}`. Compáralo con lo que dejó el original (la ruta de arriba) para saber si has llegado.

Prohibido: `mvn test` sin `-Dtest`, `mvn verify`, `mvn package`, `mvn install`, `mvn spring-boot:run` y `java -jar`.

## Reglas

- Solo cambias ficheros de `src/main/`. No toques los tests, el arnés `PruebaLocalTest`, las carpetas de los casos ni el `pom.xml`: si cambias algo fuera de `src/main/`, el script lo deja como estaba y prueba tu arreglo sin ese cambio.
- El migrado tiene que hacer lo mismo que el original. No escribas en el código valores sacados del caso (una fecha, un importe, un nombre de fichero concreto): arregla la causa, no este caso.
- Después de tu arreglo, el script ejecuta también todos los demás casos y los tests del proyecto. Si alguno empeora, tu arreglo se rechaza: cambia lo mínimo.
- Si la diferencia solo existe porque la prueba local simula algo (una base de datos H2 en vez de la de verdad, el correo o el SFTP simulados) y en el entorno real el migrado ya está bien, no cambies nada. Escribe `.rescate/reparar-no.txt` con el motivo, en una línea.
- Termina tu respuesta con una sola palabra: hecho.
<!--CORRECCION-->

## CORRECCIÓN: tu intento anterior no pasó la comprobación

El script ha revisado lo que escribiste y ha encontrado esto:

{{MOTIVO}}

{{DIFF}}

Tus cambios se han deshecho. Vuelve a empezar desde el código de antes y corrige eso.
