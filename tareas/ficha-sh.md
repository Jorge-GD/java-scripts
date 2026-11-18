# Tarea: contar lo que hace un script de shell

Vas a leer UN script de shell (.sh, .ksh) que lanza un batch de Spring y a contar lo que hace con datos que otra persona pueda comprobar: con qué parámetros se lanza, qué hace antes y después del java y con qué códigos acaba. No tienes que leer ningún fichero: el script entero está más abajo, con el número de cada línea. No cambies ningún fichero del repositorio: tu única escritura es el fichero de salida.

TIPO: ficha-sh
SCRIPT: {{SCRIPT}}
JOB ENLAZADO: {{JOB}}
OBLIGATORIAS: {{OBLIGATORIAS}}
ESCRIBIR: {{SALIDA}}

## El script, con el número de cada línea

{{TEXTO}}

## Lo que el script ya ha encontrado sin leerlo

Una línea por cosa, con su número de línea, su tipo entre corchetes y el dato: `java` (el jar que se lanza), `perfil` y `job` (qué se lanza), `parametro` (lo que recibe), `fichero` (lo que mueve, copia o borra), `envio` (lo que manda fuera), `fecha`, `salida` (un `exit`), `lanza` (otro script) y `cerrojo` (lo que impide dos ejecuciones a la vez).

{{INVENTARIO}}

## Qué tienes que hacer

1. Lee el script de arriba y cuenta lo que hace. Las líneas se cuentan como en el texto de arriba.
2. Escribe en el fichero de ESCRIBIR un único objeto JSON. Sin texto antes ni después y sin bloques de código (nada de comillas invertidas).
3. Termina tu respuesta con una sola palabra: hecho.

## Campos del JSON

- `paraQue`: una o dos frases: qué lanza el script y para qué. Lo que no se sepa con el script de arriba: «no consta».
- `parametros`: lista de lo que hay que darle al script para lanzarlo (puede estar vacía). Cada uno tiene:
  - `nombre`: como se escribe (`--fecha`, `-m`, el primer argumento...).
  - `obligatorio`: `true` si sin él el script para, `false` si no.
  - `valores`: qué valores admite, en palabras normales. Texto vacío si vale cualquiera.
  - `formato`: cómo se escribe el valor (por ejemplo `dd/MM/yyyy`). Texto vacío si no hay un formato.
  - `linea` y `cita`: la línea del script donde se ve y el trozo de esa línea, copiado TAL CUAL. Máximo {{CITA_MAX}} caracteres.
- `acciones`: lista de lo que hace el script además de lanzar el java (puede estar vacía). Cada una tiene:
  - `cuando`: `antes` o `despues` del java, `siempre` o `si-falla`.
  - `condicion`: si solo ocurre en un caso, cuál (por ejemplo «si el modo es ALTA»). Texto vacío si ocurre siempre.
  - `que`: `mueve`, `copia`, `borra`, `comprime`, `envia`, `avisa`, `comprueba`, `lanza`, `elige-job` u `otro`.
  - `detalle`: qué ficheros, carpetas o servidores toca y para qué, con los nombres tal como salen en el script.
  - `linea` y `cita`: como en los parámetros.
- `salidas`: lista de los `exit` del script. Cada una tiene:
  - `codigo`: el número del `exit`. Si el código no es un número fijo (por ejemplo `exit $?`), pon -1 y cuéntalo en `cuando`.
  - `cuando`: en qué caso el script acaba con ese código.
  - `linea` y `cita`: como en los parámetros.

## Reglas

- Cada elemento lleva su `cita`, copiada del script. Si no puedes citarlo, no lo escribas. Una cita inventada se rechaza, y si más de la mitad lo son, se rechaza todo.
- Las líneas de OBLIGATORIAS tienen que salir cada una en la `linea` de alguna acción o de alguna salida: son los ficheros que se mueven o se borran, lo que se envía fuera, los `exit`, los scripts que se lanzan, los cerrojos y el perfil o el job que se elige. Si falta alguna, se te pedirá repetirlo. Si una no hace nada que importe, cuéntala como acción con `que` igual a `otro`.
- Una línea larga con varias cosas (un `for` que mueve ficheros, un `find` con un `rm`) se cuenta una vez, con la línea donde empieza.
- Lenguaje de negocio: en `paraQue`, `condicion`, `detalle` y `cuando` no puede salir el nombre de ninguna clase Java. Di lo que hace, no cómo se llama.
- Sin relleno: nada de frases que valgan para cualquier script, como {{RELLENO}}. El script las rechaza. En su lugar, el dato concreto: qué fichero, qué carpeta, cuántos días, a quién.
- Cuenta solo lo que ves en el script. No supongas lo que hacen los otros scripts ni el programa java.

## Ejemplo de salida

Para un script que mueve los ficheros de la carga anterior, lanza el java con una fecha y borra los registros de más de 30 días, el fichero de salida contiene:

```json
{
  "paraQue": "Lanza la carga de cuotas del día con la fecha que se le dé y limpia los registros viejos.",
  "parametros": [
    { "nombre": "--fecha", "obligatorio": true, "valores": "una fecha", "formato": "dd/MM/yyyy", "linea": 12, "cita": "-f | --fecha ) shift" }
  ],
  "acciones": [
    { "cuando": "antes", "condicion": "Si el modo es ALTA.", "que": "mueve", "detalle": "Aparta a la carpeta backup los ficheros SALIDA_ALTA_*.TXT que dejó la carga anterior.", "linea": 31, "cita": "mv -f ${j} /opt/acme/cargas/outbox/backup/${j}.${RUN_DAY}" },
    { "cuando": "despues", "condicion": "", "que": "borra", "detalle": "Borra los registros de más de 30 días de la carpeta logs.", "linea": 41, "cita": "find /opt/acme/cargas/logs -type f -mtime +30" }
  ],
  "salidas": [
    { "codigo": 1, "cuando": "Si falta la fecha o llega un parámetro que no existe.", "linea": 20, "cita": "exit 1" },
    { "codigo": 0, "cuando": "Cuando todo ha ido bien.", "linea": 47, "cita": "exit 0" }
  ]
}
```
<!--CORRECCION-->

## CORRECCIÓN: tu intento anterior no pasó la comprobación

El script ha revisado lo que escribiste y ha encontrado esto:

{{MOTIVO}}

Vuelve a leer el script de arriba, corrige solo eso y escribe el JSON completo otra vez en el fichero de ESCRIBIR. Las citas se copian TAL CUAL del script, los textos son para gente de negocio y sin frases de relleno: el dato concreto o «no consta».
