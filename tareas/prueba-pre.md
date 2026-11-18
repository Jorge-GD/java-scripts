# Tarea: guion para probar un job en pre

Vas a preparar el guion con el que una persona de negocio, que no programa, probará UN job de un batch en el entorno de pruebas (pre). No tienes que leer ningún fichero de código: todo lo que necesitas está más abajo. No cambies ningún fichero del repositorio: tu única escritura es el fichero de salida.

TIPO: prueba-pre
JOB: {{JOB}}
ESCRIBIR: {{SALIDA}}

## Qué hace el job

{{PASOS}}

## Hechos que se saben del job

Uno por línea: primero la referencia (por ejemplo `clase-ab12cd34#3`), después el tipo entre corchetes y la frase que lo cuenta.

{{DATOS}}

## Variables de configuración del batch

{{VARIABLES}}

## Qué tienes que hacer

1. Con los pasos y los hechos de arriba, escribe el guion de prueba del job: qué hay que dejar preparado, qué casos hay que probar y qué hay que mirar al acabar.
2. Escribe en el fichero de ESCRIBIR un único objeto JSON. Sin texto antes ni después y sin bloques de código (nada de comillas invertidas).
3. Termina tu respuesta con una sola palabra: hecho.

## Campos del JSON

- `job`: `{{JOB}}`.
- `preparar`: lo que hay que dejar listo antes de lanzar el job (un fichero en una carpeta, una tabla con datos, una variable de configuración). Puede estar vacía. Cada elemento tiene:
  - `texto`: una frase corta.
  - `refs`: la lista de referencias de los hechos de arriba en los que te apoyas.
- `casos`: los casos que hay que probar, como mucho {{CASOS_MAX}}. Cada caso tiene:
  - `titulo`: una frase corta que diga qué se prueba.
  - `entrada`: qué mete la persona que prueba (qué fichero, qué datos, qué valor).
  - `esperado`: qué tiene que pasar.
  - `refs`: la lista de referencias de los hechos que cubre el caso. Al menos una.
- `comprobar`: lo que hay que mirar cuando el job acaba (qué queda en una tabla, en un fichero, en un aviso). Puede estar vacía. Mismos campos que `preparar`.

## Reglas

- Cada hecho de tipo `regla` y cada hecho de tipo `error` de arriba tiene que salir en las `refs` de algún caso. Un caso puede cubrir varios hechos: junta los que se prueben con la misma entrada.
- Límites: si un hecho pone un límite (un mínimo, un máximo, un número de días, un tope de rechazos), prueba el valor justo en el límite y el primero que lo pasa. Por ejemplo, con «como mucho 45 días»: un caso con 45 días, que se acepta, y otro con 46, que se rechaza. Los dos valores pueden ir en el mismo caso si se prueban con la misma entrada.
- Opciones de arranque: si un caso necesita encender una opción (por ejemplo, el envío de correo), haz también el mismo caso con la opción apagada, siempre que la regla se vea sin ella. Así se puede probar sin preparar el entorno.
- Las referencias se copian TAL CUAL de los hechos de arriba. Una referencia que no esté en ellos hace que se rechace todo el guion.
- Lenguaje de negocio: frases cortas y palabras normales. En ningún texto puede salir el nombre de una clase (por ejemplo `GestorRecibos`) ni el nombre de un fichero que acabe en `.java`.
- No inventes: pide solo lo que se pueda deducir de los hechos de arriba.

## Ejemplo de salida

Para un job `cargaRecibosJob`, el fichero de salida contiene:

```json
{
  "job": "cargaRecibosJob",
  "preparar": [
    { "texto": "Deja en la carpeta de entrada un fichero de recibos del día.", "refs": ["clase-33430351#2"] }
  ],
  "casos": [
    {
      "titulo": "Recibo con importe por debajo del mínimo",
      "entrada": "Un recibo de 4,99 euros.",
      "esperado": "El recibo se rechaza y aparece en el fichero de errores.",
      "refs": ["clase-33430351#9", "clase-33430351#21"]
    }
  ],
  "comprobar": [
    { "texto": "Los recibos buenos están en la tabla de recibos con estado pendiente.", "refs": ["clase-33430351#19"] }
  ]
}
```
<!--CORRECCION-->

## CORRECCIÓN: tu intento anterior no pasó la comprobación

El script ha revisado lo que escribiste y ha encontrado esto:

{{MOTIVO}}

Vuelve a mirar los hechos de arriba, corrige solo eso y escribe el JSON completo otra vez en el fichero de ESCRIBIR. Las referencias se copian TAL CUAL y los textos son para gente de negocio.
