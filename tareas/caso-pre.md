# Tarea: un caso de prueba para una regla sin caso

Vas a escribir UN caso de prueba para una regla (o un error) de un job que el guion de prueba en pre todavía no cubre. El guion lo usará una persona de negocio, que no programa, para probar el job en el entorno de pruebas (pre). No tienes que leer ningún fichero de código: todo lo que necesitas está más abajo. No cambies ningún fichero del repositorio: tu única escritura es el fichero de salida.

TIPO: caso-pre
JOB: {{JOB}}
REGLA: {{REGLA_REF}}
ESCRIBIR: {{SALIDA}}

## Qué hace el job

{{PASOS}}

## La regla que falta

Primero la referencia, después el tipo entre corchetes y la frase que la cuenta. Ningún caso del guion la cubre.

{{REGLA}}

## El guion que ya tiene el job

{{GUION}}

## Hechos que se saben del job

Uno por línea: primero la referencia (por ejemplo `clase-ab12cd34#3`), después el tipo entre corchetes y la frase que lo cuenta.

{{DATOS}}

## Qué tienes que hacer

1. Con la regla de arriba y los hechos, escribe un único caso que la pruebe: qué mete la persona que prueba y qué tiene que pasar. Que encaje con lo que el guion ya deja preparado y comprueba.
2. Escribe en el fichero de ESCRIBIR un único objeto JSON. Sin texto antes ni después y sin bloques de código (nada de comillas invertidas).
3. Termina tu respuesta con una sola palabra: hecho.

## Campos del JSON

- `titulo`: una frase corta que diga qué se prueba. Distinto de los títulos de los casos que ya hay.
- `entrada`: qué mete la persona que prueba (qué fichero, qué datos, qué valor).
- `esperado`: qué tiene que pasar.
- `refs`: la lista de referencias de los hechos que cubre el caso. Tiene que llevar la de la regla, `{{REGLA_REF}}`. Puede llevar más, de los hechos de arriba.

## Reglas

- Límites: si la regla pone un límite (un mínimo, un máximo, un número de días, un tope de rechazos), prueba el valor justo en el límite y el primero que lo pasa. Por ejemplo, con «como mucho 45 días»: 45 días, que se acepta, y 46, que se rechaza. Los dos valores pueden ir en el mismo caso si se prueban con la misma entrada.
- Opciones de arranque: si el caso necesita encender una opción (por ejemplo, el envío de correo) y la regla se ve sin ella, plantéalo con la opción apagada. Así se puede probar sin preparar el entorno.
- Las referencias se copian TAL CUAL de los hechos de arriba. Una referencia que no esté en ellos hace que se rechace el caso.
- Lenguaje de negocio: frases cortas y palabras normales. En ningún texto puede salir el nombre de una clase (por ejemplo `GestorRecibos`) ni el nombre de un fichero que acabe en `.java`.
- No inventes: pide solo lo que se pueda deducir de los hechos de arriba.

## Ejemplo de salida

Para la regla `clase-33430351#9` de un job `cargaRecibosJob` («Rechaza el recibo cuyo importe es menor de 5 euros»), el fichero de salida contiene:

```json
{
  "titulo": "Recibo justo por debajo y justo en el mínimo",
  "entrada": "Dos recibos en el fichero del día: uno de 4,99 euros y otro de 5,00 euros.",
  "esperado": "El de 4,99 euros se rechaza y queda en el fichero de rechazados. El de 5,00 euros se carga en la tabla de recibos pendientes.",
  "refs": ["clase-33430351#9"]
}
```
<!--CORRECCION-->

## CORRECCIÓN: tu intento anterior no pasó la comprobación

El script ha revisado lo que escribiste y ha encontrado esto:

{{MOTIVO}}

Vuelve a mirar la regla y los hechos de arriba, corrige solo eso y escribe el JSON completo otra vez en el fichero de ESCRIBIR. La referencia de la regla va en `refs`, las referencias se copian TAL CUAL y los textos son para gente de negocio.
