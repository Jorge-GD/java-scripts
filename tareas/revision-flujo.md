# Tarea: revisar un flujo del batch migrado

Vas a revisar una pieza del batch ya migrado (un step con sus clases, o un fichero suelto) contra un catálogo cerrado de reglas. Solo lees: no cambies ningún fichero del repositorio. Tu única escritura es el fichero de salida.

TIPO: revision-flujo
UNIDAD: {{UNIDAD}}
ESCRIBIR: {{SALIDA}}

Los ficheros de la unidad son estos, una ruta por línea, desde la carpeta donde trabajas. Lee todos:

{{FICHEROS}}

Candidatas a código muerto de esta unidad (la regla CAND-MUERTA solo vale en estas; si dice «ninguna», no la uses):

{{CANDIDATAS}}

## Catálogo de reglas

Una por línea, con su id. Solo puedes dar hallazgos de estas reglas. Detrás de cada una va el texto del código del que tu cita lleva al menos uno.

{{REGLAS}}

## Qué tienes que hacer

1. Lee los ficheros de la unidad y mira, regla por regla, si alguna se cumple en ese código.
2. Un hallazgo es solo lo que se ve en el código de esos ficheros. Si una regla te pide buscar un nombre en todo el repositorio antes de darlo, hazlo (puedes leer cualquier fichero para descartarlo), pero el hallazgo va siempre en un fichero de la unidad.
3. No des un hallazgo por una sospecha, por el estilo ni por algo que no está en el catálogo. Si dudas, no lo des.
4. Da como mucho {{HALLAZGOS_MAX}} hallazgos, los más seguros. Si no hay nada que decir, el campo `hallazgos` es una lista vacía: `"hallazgos": []`.
5. Escribe en el fichero de ESCRIBIR un único objeto JSON. Sin texto antes ni después y sin bloques de código (nada de comillas invertidas).
6. Termina tu respuesta con una sola palabra: hecho.

## Campos del JSON

El objeto tiene un solo campo, `hallazgos`: una lista, vacía si no hay nada. Cada hallazgo tiene:

- `regla`: el id de una regla del catálogo, copiado tal cual.
- `fichero`: una de las rutas de la unidad, copiada tal cual.
- `linea`: el número de la línea (desde 1) de ese fichero donde está el código.
- `cita`: un trozo corto (como mucho {{CITA_MAX}} caracteres) de esa línea, copiado tal cual del fichero, que se pueda buscar en él y que lleve uno de los textos de su regla.
- `texto`: una o dos frases que dicen qué falla y por qué.

## Reglas

- Las citas se comprueban buscándolas en el fichero. Cópialas tal cual y no inventes ninguna: lo que no se puede comprobar se descarta, y si se descarta más de la mitad se rechaza todo lo que has escrito.
- Una regla del catálogo que no se cumple en el código no es un hallazgo: no la menciones.
- No leas ni des hallazgos de nada que no sea código Java de este repositorio.

## Ejemplo de salida

Para una unidad con un solo problema, el fichero de salida contiene:

```json
{
  "hallazgos": [
    { "regla": "SB-STEPSCOPE", "fichero": "src/main/java/com/acme/pedidos/PasosPedidos.java", "linea": 42, "cita": "public ItemReader<Pedido> lectorPedidos()", "texto": "El bean está en @StepScope y devuelve ItemReader, pero lo que crea es un FlatFileItemReader, que es un ItemStream: el proxy no deja que Spring Batch llame a open ni a close." }
  ]
}
```

Y para una unidad sin nada que decir:

```json
{ "hallazgos": [] }
```
<!--CORRECCION-->

## CORRECCIÓN: tu intento anterior no pasó la comprobación

El script ha revisado lo que escribiste y ha encontrado esto:

{{MOTIVO}}

Vuelve a mirar los ficheros de arriba, corrige solo eso y escribe el JSON completo otra vez en el fichero de ESCRIBIR. Las citas se copian tal cual del código, de una línea de un fichero de la unidad, y llevan uno de los textos de su regla.
