# Tarea: comparar una clase del original con el migrado

Vas a comprobar, dato a dato, si lo que hace una clase del batch original sigue estando en el código del migrado. Cada dato de abajo ya se sacó del original, con su línea y su cita. Tú buscas ese mismo dato en los ficheros del migrado y dices si está igual, si está distinto, si falta o si no lo sabes. No cambies ningún fichero del repositorio: tu única escritura es el fichero de salida.

TIPO: comparar-pieza
LEER: {{FICHERO}}
ESCRIBIR: {{SALIDA}}

La clase del original es `{{CLASE}}` (el fichero de LEER). No hace falta que la releas: sus datos están más abajo. Los ficheros del migrado que tienes que leer son estos, una ruta por línea, desde la carpeta donde trabajas:

{{MIGRADO}}

## Datos del original

Uno por dato, con su número. Ese número es el que va en el campo `dato` de tu respuesta. Debajo de cada tipo y texto va el sitio del original donde sale (fichero, línea y cita).

{{DATOS}}

## Qué tienes que hacer

1. Para cada dato, busca en los ficheros del migrado el código que hace lo mismo y elige un estado:
   - `igual`: el migrado hace lo mismo que cuenta el dato.
   - `distinto`: el migrado hace algo parecido, pero cambia algo (un valor, una condición, un nombre, un orden).
   - `falta`: no encuentras nada que lo haga en esos ficheros.
   - `no-lo-se`: con lo que ves no puedes decidirlo (por ejemplo, porque depende de otra clase que no te han dado).
2. Escribe en el fichero de ESCRIBIR un único objeto JSON. Sin texto antes ni después y sin bloques de código (nada de comillas invertidas).
3. Termina tu respuesta con una sola palabra: hecho.

## Campos del JSON

El objeto tiene un solo campo, `comparacion`: una lista con un elemento por cada dato de arriba, ni uno más ni uno menos, cada número una sola vez. Cada elemento tiene:

- `dato`: el número del dato.
- `estado`: `igual`, `distinto`, `falta` o `no-lo-se`.
- `fichero`: en `igual` y `distinto`, una de las rutas de MIGRADO, copiada tal cual. En `falta` y `no-lo-se`, no lo pongas.
- `linea`: en `igual` y `distinto`, el número de la línea (desde 1) de ese fichero donde está el código.
- `cita`: en `igual` y `distinto`, un trozo corto (como mucho {{CITA_MAX}} caracteres) de ese código, copiado tal cual del fichero, que se pueda buscar en él.
- `nota`: obligatoria en `distinto` (qué cambia respecto al original) y en `no-lo-se` (por qué no puedes decidirlo); opcional en `falta`.

## Reglas

- Las citas se comprueban buscándolas en el fichero. Cópialas tal cual del código y no inventes ninguna: si más de la mitad no se encuentran, se rechaza todo lo que has escrito.
- Si dudas entre `igual` y `distinto`, elige `distinto` y cuenta en la nota qué te hace dudar.
- No leas nada más que esos ficheros y, si lo necesitas, el original.

## Ejemplo de salida

Para una clase con tres datos, 0, 1 y 2, el fichero de salida contiene:

```json
{
  "comparacion": [
    { "dato": 0, "estado": "igual", "fichero": "src/main/java/com/acme/RecibosReader.java", "linea": 12, "cita": "if (importe < MINIMO) {", "nota": "" },
    { "dato": 1, "estado": "distinto", "fichero": "src/main/java/com/acme/RecibosReader.java", "linea": 20, "cita": "return Estado.PENDIENTE;", "nota": "El original dejaba el recibo en estado pagado." },
    { "dato": 2, "estado": "falta", "nota": "No hay nada que escriba el fichero de errores." }
  ]
}
```
<!--CORRECCION-->

## CORRECCIÓN: tu intento anterior no pasó la comprobación

El script ha revisado lo que escribiste y ha encontrado esto:

{{MOTIVO}}

Vuelve a mirar los datos y los ficheros de arriba, corrige solo eso y escribe el JSON completo otra vez en el fichero de ESCRIBIR. Las citas se copian tal cual del código del migrado.
