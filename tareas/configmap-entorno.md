# Tarea: escribir la configuración de un entorno en el repo de configmap

Trabajas en la carpeta del repo de configmap nuevo de un batch ya migrado. Tienes que escribir los ficheros de `{{CARPETA}}/` (el entorno `{{ENTORNO}}`), adaptándolos del repo de configmap del batch de referencia. Solo escribes esos ficheros y el fichero de salida: no toques nada más.

TIPO: configmap-entorno

Los ficheros que tienes que escribir, una ruta por línea, desde la carpeta donde trabajas:

{{FICHEROS}}

## Las variables de este entorno

Una por línea. Cada una lleva su valor, `<PENDIENTE>` si no se sabe, o la marca `(secreto, sin valor)`:

{{TABLA}}

## Así son los ficheros del batch de referencia

Ya llevan el nombre del batch nuevo. Cada fichero va con su ruta y su contenido entre `=====`:

{{REFERENCIA}}

## Qué tienes que hacer

1. Escribe cada fichero de la lista con el mismo formato, el mismo orden y las mismas convenciones que el de referencia: lo único que cambia es su contenido. Copia el formato de la referencia; no lo inventes.
2. Cada variable de la tabla que lleva un valor sale en alguno de los ficheros, en su línea y con ese valor exactamente. Usa el formato que la referencia usa para las variables.
3. Cada variable `<PENDIENTE>` sale en el mismo sitio con el valor `<PENDIENTE>`. Nunca inventes un valor.
4. Cada variable `(secreto, sin valor)` sale solo como referencia a un Secret, con el formato que la referencia usa para los secretos. El nombre del Secret y su clave no los sabes: escribe `<PENDIENTE: nombre del Secret>` y `<PENDIENTE: clave del Secret>`. Nunca escribas el valor de un secreto, ni en ese fichero ni en ningún otro, y no busques ese valor en ningún sitio.
5. Lo que en la referencia es propio de la plataforma y no del batch (el entorno, los montajes, los recursos de cpu y memoria) se copia, cambiando solo lo que dependa del batch o del entorno. Lo que en la referencia es propio del batch de referencia y el nuevo no usa, no va.
6. Todo lo que necesite el batch nuevo y no puedas saber lleva `<PENDIENTE: qué falta>`. Pon una marca por cada cosa que falte.
7. No dejes ningún nombre del batch de referencia: todo lo que lleve el nombre del batch ya viene cambiado en la referencia y así tiene que quedar.
8. Escribe solo los ficheros de la lista: la salida de esta tarea son los ficheros.
9. Termina tu respuesta con una sola palabra: hecho.
<!--CORRECCION-->

## CORRECCIÓN: tu intento anterior no pasó la comprobación

El script ha revisado lo que escribiste y ha encontrado esto:

{{MOTIVO}}

Vuelve a escribir los ficheros de la lista y corrige solo eso. Lo que se pide arriba sigue igual: cada variable de la tabla, con su valor, `<PENDIENTE>` o como referencia a un Secret, y sin ningún valor de un secreto.
