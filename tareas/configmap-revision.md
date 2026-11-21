# Tarea: revisar lo escrito en el repo de configmap

Vas a revisar los ficheros que ya se han escrito en el repo de configmap nuevo de un batch migrado, contra los del batch de referencia y contra lo que lee el batch migrado. Solo lees: no cambies ningún fichero del repositorio. Tu única escritura es el fichero de salida.

TIPO: configmap-revision
UNIDAD: {{UNIDAD}}
ESCRIBIR: {{SALIDA}}

El batch migrado está en {{MIGRADO}}. Lee sus ficheros de configuración (`src/main/resources`) para ver qué variables lee.

Los ficheros de la unidad son estos, una ruta por línea, desde la carpeta donde trabajas. Lee todos:

{{FICHEROS}}

## Lo que se esperaba

{{TABLA}}

## Los ficheros del batch de referencia

Ya llevan el nombre del batch nuevo:

{{REFERENCIA}}

## Qué tienes que hacer

1. Lee los ficheros de la unidad y compáralos con los de referencia y con lo que se esperaba: busca una variable que falta o que sobra, un valor que parece de otro entorno, un formato que no es el de la referencia, un valor secreto en claro, un nombre del batch de referencia que ha quedado o algo que no cuadra con lo que lee el batch migrado.
2. Un hallazgo es solo lo que ves en esos ficheros. No des un hallazgo por una sospecha ni por el estilo. Si dudas, no lo des.
3. Da como mucho {{HALLAZGOS_MAX}} hallazgos, los más seguros. Si no hay nada que decir, el campo `hallazgos` es una lista vacía: `"hallazgos": []`.
4. Escribe en el fichero de ESCRIBIR un único objeto JSON. Sin texto antes ni después y sin bloques de código (nada de comillas invertidas).
5. Termina tu respuesta con una sola palabra: hecho.

## Campos del JSON

El objeto tiene un solo campo, `hallazgos`: una lista, vacía si no hay nada. Cada hallazgo tiene:

- `fichero`: una de las rutas de la unidad, copiada tal cual.
- `linea`: el número de la línea (desde 1) de ese fichero donde está el problema.
- `cita`: un trozo corto (como mucho {{CITA_MAX}} caracteres) de esa línea, copiado tal cual del fichero, que se pueda buscar en él.
- `problema`: una o dos frases que dicen qué falla y por qué.

## Reglas

- Las citas se comprueban buscándolas en el fichero. Cópialas tal cual y no inventes ninguna: lo que no se puede comprobar se descarta, y si se descarta más de la mitad se rechaza todo lo que has escrito.
- No escribas ni copies el valor de un secreto, aunque lo veas.

## Ejemplo de salida

```json
{
  "hallazgos": [
    { "fichero": "config/ejemplo/variables", "linea": 3, "cita": "ejemplo.ruta=/data/otro", "problema": "La ruta es la de otro entorno." }
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

Vuelve a mirar los ficheros de la unidad (sin cambiar ninguno) y escribe el JSON completo otra vez en el fichero de ESCRIBIR. Las citas se copian tal cual de una línea de un fichero de la unidad.
