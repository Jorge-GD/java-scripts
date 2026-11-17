# Tarea: resumen de un batch para negocio

Vas a resumir un batch entero para una persona de negocio que no programa. No tienes que leer ningún fichero de código: todo lo que necesitas está más abajo. No cambies ningún fichero del repositorio: tu única escritura es el fichero de salida.

TIPO: resumen
ESCRIBIR: {{SALIDA}}

## Los jobs del batch

De cada job: su nombre (la línea que empieza por JOB) y, si se ha podido redactar, su título, para qué sirve y los títulos de sus pasos.

{{JOBS}}

## Qué tienes que hacer

1. Con los jobs de arriba, cuenta qué hace el batch entero y en qué orden conviene contar sus jobs, con palabras normales.
2. Escribe en el fichero de ESCRIBIR un único objeto JSON. Sin texto antes ni después y sin bloques de código (nada de comillas invertidas).
3. Termina tu respuesta con una sola palabra: hecho.

## Campos del JSON

- `resumen`: de cinco a diez frases: qué hace el batch entero, para quién y con qué resultado.
- `orden`: una entrada por cada job de arriba, en el orden en que tiene sentido contarlos o ejecutarlos. Todos los jobs, cada uno una sola vez, y ninguno que no esté arriba. Cada entrada tiene:
  - `job`: el nombre del job, tal cual está en la línea JOB.
  - `motivo`: una frase que explique por qué va en ese sitio.
- `glosario`: de 0 a {{GLOSARIO_MAX}} palabras del negocio que una persona nueva podría no conocer. Cada una tiene `termino` y `definicion`. Puede estar vacía.

## Reglas

- Lenguaje de negocio: en `resumen` no puede salir el nombre de ninguna clase del código. Di lo que hace, no cómo se llama.
- No inventes: cuenta solo lo que sale en los jobs de arriba.

## Ejemplo de salida

```json
{
  "resumen": "El batch recoge cada día los recibos que llegan del banco, comprueba que son válidos y prepara el cobro. Al final deja un informe con lo cobrado y lo rechazado para el equipo de administración.",
  "orden": [
    { "job": "cargaRecibosJob", "motivo": "Va primero porque sin recibos cargados no hay nada que cobrar." },
    { "job": "informeCobrosJob", "motivo": "Va al final porque cuenta el resultado de lo anterior." }
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

Vuelve a mirar los jobs de arriba, corrige solo eso y escribe el JSON completo otra vez en el fichero de ESCRIBIR. Todos los jobs, cada uno una vez, y el resumen sin nombres de clases.
