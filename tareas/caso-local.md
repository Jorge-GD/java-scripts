# Tarea: preparar las entradas de un caso de prueba

Vas a preparar los datos de entrada de UN caso de prueba de un job de un batch Java. Después, otro programa lanzará el job con estos datos en la versión original y en la migrada del batch, y comparará lo que sale. Tú solo preparas la entrada: no decides qué tiene que salir, no lanzas nada y no cambias el código.

TIPO: caso-local
JOB: {{JOB}}
CASO: {{CASO}}
CARPETA: {{CARPETA}}

## El caso

TÍTULO: {{TITULO}}
ENTRADA: {{ENTRADA}}
ESPERADO: {{ESPERADO}}

ESPERADO solo sirve para que entiendas el caso: no lo compruebas tú.

## Qué hace el job

{{PASOS}}

## Hechos que se saben del job

{{HECHOS}}

## Código que lee la entrada del job

Lee estos ficheros del repositorio para saber qué forma tiene la entrada (de qué carpeta lee, qué nombres de fichero acepta, qué columnas y qué separador, qué tablas consulta):

{{LEER}}

Mira también los datos que el batch carga en la base al arrancar (por ejemplo, `src/main/resources/data.sql`), para usar en el caso claves que existan (o que no existan, si el caso va de eso).

## Qué tienes que escribir

Solo dentro de CARPETA (créala). Escribe solo lo que el caso necesite:

- `ficheros/<carpeta>/<fichero>`: los ficheros que el job encuentra al arrancar. `<carpeta>` es el nombre de la carpeta de donde los lee: la última parte de su ruta en el código o en la configuración (por ejemplo, `entrada`). Si el caso necesita ficheros en otra carpeta (por ejemplo, uno que ya estaba en `procesados`), van en `ficheros/procesados/`.
- `datos.sql`: las filas que tiene que haber en la base además de las que carga el batch al arrancar. Solo `INSERT`, una sentencia por línea, acabadas en `;`.
- `parametros.properties`: los parámetros del job, `clave=valor` por línea, si el caso los pide.

## Reglas

- Nada fuera de CARPETA. Si escribes fuera, el script lo deshace y rechaza el caso.
- Datos inventados, nunca reales: nombres, cuentas, NIF y direcciones de ejemplo. Las cuentas bancarias, inventadas pero con el formato que pida el código (con los dígitos de control bien, si los comprueba).
- Lo justo para el caso: los registros que pide ENTRADA, con todo lo demás correcto, para que solo se pruebe lo que dice el caso.
- Si el caso no se puede preparar solo con entradas, porque pide cambiar la configuración del batch (encender el correo, otro tope, un servidor caído, una carpeta que no existe o no se puede crear) o lanzar el job más de una vez, no lo prepares: escribe solo `no-aplica.txt` en CARPETA, con una frase que diga por qué.
- Termina tu respuesta con una sola palabra: hecho.
<!--CORRECCION-->

## CORRECCIÓN: tu intento anterior no pasó la comprobación

El script ha revisado lo que escribiste y ha encontrado esto:

{{MOTIVO}}

La carpeta del caso se ha borrado. Vuelve a escribir el caso completo en CARPETA, corrigiendo eso.
