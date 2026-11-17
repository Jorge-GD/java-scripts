# Tarea: pasos de los jobs de un fichero

Vas a leer UN fichero del batch original y a decir qué pasos tiene cada uno de los jobs que define. No cambies ningún fichero del repositorio: tu única escritura es el fichero de salida.

TIPO: definicion-job
LEER: {{FICHERO}}
LINEAS: {{LINEAS}}
ESCRIBIR: {{SALIDA}}
JOBS: {{JOBS}}
CLASES: {{CLASES}}

## Qué tienes que hacer

1. Lee el fichero de LEER entero. Las líneas se cuentan desde 1.
2. Los jobs de JOBS son los que define ese fichero. Describe exactamente esos: ni uno más ni uno menos, y cada uno una sola vez.
3. Un job se define, por ejemplo, con `jobBuilderFactory.get("nombre")` o `new JobBuilder("nombre", ...)`; en un XML, con `<job id="nombre">`. Sus pasos son los `step` que arranca y encadena (`.start(...)`, `.next(...)`, `.flow(...)`): `stepBuilderFactory.get("nombre")`, `new StepBuilder("nombre", ...)` o `<step id="nombre">`. Si el fichero define varios jobs, cada paso va en el job que lo usa.
4. De cada paso, di qué clases del original usa (lector, procesador, escritor, tarea, listeners...). Copia sus nombres de la lista CLASES, tal cual y sin paquete. Si el paso no usa ninguna clase de esa lista, pon `"clases": []`.
5. Escribe en el fichero de ESCRIBIR un único objeto JSON. Sin texto antes ni después y sin bloques de código (nada de comillas invertidas).
6. Termina tu respuesta con una sola palabra: hecho.

## Campos del JSON

- `jobs`: una entrada por cada job de JOBS. Cada entrada tiene:
  - `job`: el nombre, tal cual está en JOBS.
  - `linea`: la línea donde se define el job.
  - `cita`: el trozo de código de esa línea que lo demuestra, copiado TAL CUAL. Máximo {{CITA_MAX}} caracteres.
  - `pasos`: de 1 a {{PASOS_MAX}} pasos. Cada paso tiene:
    - `paso`: su nombre, tal cual está en el código.
    - `linea` y `cita`: la línea donde se define el paso y el trozo de código que lo demuestra, igual que arriba.
    - `clases`: la lista de nombres de clase de CLASES que usa ese paso. Puede estar vacía.

## Reglas

- Cada `cita` se copia del código. Una cita inventada hace que se rechace la respuesta entera, y se te pedirá repetirla.
- En `clases` solo valen nombres de la lista CLASES. Un nombre que no esté en esa lista hace que se rechace la respuesta.
- Cuenta solo lo que ves en este fichero. No supongas lo que hacen otras clases.

## Ejemplo de salida

Para un fichero que define el job `cargaRecibosJob`, el fichero de salida contiene:

```json
{
  "jobs": [
    {
      "job": "cargaRecibosJob",
      "linea": 41,
      "cita": "jobBuilderFactory.get(\"cargaRecibosJob\")",
      "pasos": [
        {
          "paso": "cargaStep",
          "linea": 55,
          "cita": "stepBuilderFactory.get(\"cargaStep\")",
          "clases": ["ReciboReader", "ReciboValidator"]
        }
      ]
    }
  ]
}
```
<!--CORRECCION-->

## CORRECCIÓN: tu intento anterior no pasó la comprobación

El script ha revisado lo que escribiste y ha encontrado esto:

{{MOTIVO}}

Vuelve a leer el fichero, corrige solo eso y escribe el JSON completo otra vez en el fichero de ESCRIBIR. Las citas se copian TAL CUAL del código y los nombres de clase salen de la lista CLASES.
