# Tarea: explicar un job a negocio

Vas a explicar UN job de un batch a una persona de negocio que no programa. No tienes que leer ningún fichero de código: todo lo que necesitas está más abajo. No cambies ningún fichero del repositorio: tu única escritura es el fichero de salida.

TIPO: ficha-job
JOB: {{JOB}}
ESCRIBIR: {{SALIDA}}

## Pasos del job

{{PASOS}}

## Clases del job y lo que se sabe de ellas

De cada clase: su nombre, su papel y lo que hace. Debajo, sus datos, uno por línea: primero la referencia (por ejemplo `clase-ab12cd34#3`), después el tipo entre corchetes y la frase que lo cuenta.

{{DATOS}}

## Qué tienes que hacer

1. Con los pasos y los datos de arriba, cuenta el job como lo contaría alguien del equipo a una persona de negocio: qué pasa de principio a fin, con palabras normales.
2. Escribe en el fichero de ESCRIBIR un único objeto JSON. Sin texto antes ni después y sin bloques de código (nada de comillas invertidas).
3. Termina tu respuesta con una sola palabra: hecho.

## Campos del JSON

- `job`: `{{JOB}}`.
- `titulo`: una frase corta que diga qué hace el job.
- `paraQue`: dos o tres frases, con los nombres de los datos de arriba (las tablas, los ficheros y las carpetas tal como salen). Dicen qué datos lee y de dónde, qué hace con ellos (las dos o tres reglas que más pesan), y qué deja, dónde y a quién le llega. Lo que no se sepa con los datos de arriba: «no consta».
- `pasos`: de 1 a {{PASOS_MAX}} pasos, en el orden en que ocurren. Cada paso tiene:
  - `titulo`: una frase corta.
  - `texto`: qué pasa en ese paso, sin jerga.
  - `refs`: la lista de referencias de los datos de arriba en los que te apoyas, copiadas TAL CUAL (por ejemplo `clase-ab12cd34#0`). Al menos una por paso.
- `dudas`: lista de frases con lo que NO se puede saber con los datos de arriba. Puede estar vacía.

## Reglas

- Lenguaje de negocio: en `titulo`, `paraQue` y en el `titulo` y el `texto` de los pasos no puede salir el nombre de ninguna clase (las líneas que empiezan por ### de arriba). Di lo que hace, no cómo se llama.
- Sin relleno: nada de frases que valgan para cualquier job, como {{RELLENO}}. El script las rechaza. En su lugar, el dato concreto: qué fichero, qué tabla, qué regla, a quién.
- Cada paso se apoya en datos de arriba. No inventes: lo que no se sepa va a `dudas`.
- Una referencia que no esté en los datos de arriba no cuenta, y si la mayoría de los pasos no tiene ninguna buena se rechaza la ficha entera.

## Ejemplo de salida

Para un job `cargaRecibosJob`, el fichero de salida contiene:

```json
{
  "job": "cargaRecibosJob",
  "titulo": "Carga de recibos",
  "paraQue": "Lee el fichero de recibos que deja el banco cada día en la carpeta de entrada y la tabla de clientes. Rechaza los recibos de menos de 5 euros y los duplicados, y deja los buenos en la tabla de recibos pendientes de cobro. Los rechazados quedan en un fichero de texto que se envía al banco por SFTP.",
  "pasos": [
    {
      "titulo": "Leer los ficheros de recibos",
      "texto": "Se lee el fichero que deja el banco y se toma cada línea como un recibo.",
      "refs": ["clase-ab12cd34#0"]
    },
    {
      "titulo": "Descartar los recibos con importe cero",
      "texto": "Un recibo solo se acepta si su importe es mayor que cero.",
      "refs": ["clase-ef56ab78#3"]
    }
  ],
  "dudas": ["No se sabe a qué hora se lanza el job."]
}
```
<!--CORRECCION-->

## CORRECCIÓN: tu intento anterior no pasó la comprobación

El script ha revisado lo que escribiste y ha encontrado esto:

{{MOTIVO}}

Vuelve a mirar los datos de arriba, corrige solo eso y escribe el JSON completo otra vez en el fichero de ESCRIBIR. Las referencias se copian TAL CUAL de los datos de arriba, los textos son para gente de negocio y sin frases de relleno: el dato concreto o «no consta».
