# Tarea: resumen de un batch para negocio

Vas a resumir un batch entero para una persona de negocio que no programa. No tienes que leer ningún fichero de código: todo lo que necesitas está más abajo. No cambies ningún fichero del repositorio: tu única escritura es el fichero de salida.

TIPO: resumen
ESCRIBIR: {{SALIDA}}

## Los jobs del batch

De cada job: su nombre (la línea que empieza por JOB) y, si se ha podido redactar, su título, para qué sirve y los títulos de sus pasos. Después, lo que se sabe de sus datos, en cuatro listas:

- `NECESITA`: lo que lee (tablas, ficheros, carpetas, parámetros).
- `DEJA`: lo que escribe y dónde.
- `SE ENVIA A`: a quién o a qué sistema se lo manda.
- `REGLAS`: las reglas de negocio que aplica.

«no consta» quiere decir que el script no ha encontrado ese dato.

{{JOBS}}

## Qué tienes que hacer

1. Con los jobs de arriba, cuenta qué hace el batch entero y en qué orden conviene contar sus jobs, con palabras normales.
2. Escribe en el fichero de ESCRIBIR un único objeto JSON. Sin texto antes ni después y sin bloques de código (nada de comillas invertidas).
3. Termina tu respuesta con una sola palabra: hecho.

## Campos del JSON

- `resumen`: de cinco a diez frases que contesten, con los nombres de los datos de arriba (las tablas, los ficheros y las carpetas tal como salen en las listas):
  1. Qué datos lee y de dónde.
  2. Qué hace con ellos: las dos o tres reglas que más pesan.
  3. Qué deja, dónde y en qué formato.
  4. A quién le llega.
  5. Cuándo o con qué se lanza, si se sabe.
  Lo que no salga en los jobs de arriba se dice así: «no consta». No se rellena.
- `orden`: una entrada por cada job de arriba, en el orden en que tiene sentido contarlos o ejecutarlos. Todos los jobs, cada uno una sola vez, y ninguno que no esté arriba. Cada entrada tiene:
  - `job`: el nombre del job, tal cual está en la línea JOB.
  - `motivo`: una frase que explique por qué va en ese sitio, con el dato que lo enlaza con el job anterior (lo que uno deja y el otro lee).
- `glosario`: de 0 a {{GLOSARIO_MAX}} palabras del negocio que una persona nueva podría no conocer. Cada una tiene `termino` y `definicion`. Puede estar vacía.

## Reglas

- Lenguaje de negocio: en `resumen` no puede salir el nombre de ninguna clase del código. Di lo que hace, no cómo se llama.
- Sin relleno: nada de frases que valgan para cualquier batch, como {{RELLENO}}. El script las rechaza. En su lugar, el dato concreto: qué fichero, qué tabla, qué regla, a quién.
- No inventes: cuenta solo lo que sale en los jobs de arriba. Si falta un dato, «no consta».

## Ejemplo de salida

```json
{
  "resumen": "Lee cada día el fichero de recibos que deja el banco en la carpeta de entrada y la tabla de clientes. Rechaza los recibos de menos de 5 euros y los duplicados. Deja los buenos en la tabla de recibos pendientes de cobro y los rechazados en un fichero de texto, que envía al banco por SFTP. Después prepara un informe con lo cobrado, que llega por correo al equipo de cobros. Cuándo se lanza: no consta.",
  "orden": [
    { "job": "cargaRecibosJob", "motivo": "Va primero: deja la tabla de recibos pendientes que el siguiente job lee." },
    { "job": "informeCobrosJob", "motivo": "Va al final: cuenta lo que ha dejado el job anterior en esa tabla." }
  ],
  "glosario": [
    { "termino": "remesa", "definicion": "Un grupo de recibos que el banco manda junto." }
  ]
}
```
<!--CORRECCION-->

## CORRECCIÓN: tu intento anterior no pasó la comprobación

El script ha revisado lo que escribiste y ha encontrado esto:

{{MOTIVO}}

Vuelve a mirar los jobs de arriba, corrige solo eso y escribe el JSON completo otra vez en el fichero de ESCRIBIR. Todos los jobs, cada uno una vez, el resumen sin nombres de clases y sin frases de relleno.
