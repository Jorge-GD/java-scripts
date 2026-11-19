# Tarea: comparar lo que hacía un script de shell con el código migrado

Vas a comprobar, acción a acción, si lo que hacía un script de shell del batch original sigue estando en el código del migrado. Cada acción de abajo ya se sacó del script, con su línea y su cita. Tú buscas ese mismo comportamiento en los ficheros del migrado y dices si está igual, si está distinto, si falta o si no lo sabes. No cambies ningún fichero del repositorio: tu única escritura es el fichero de salida.

TIPO: comparar-sh
SCRIPT: {{SCRIPT}}
ESCRIBIR: {{SALIDA}}

El script del original es `{{SCRIPT}}`. No hace falta que lo leas: lo que hacía está más abajo. Los ficheros del migrado donde buscar son estos, una ruta por línea, desde la carpeta donde trabajas:

{{MIGRADO}}

## Acciones del original

Una por número. Ese número es el que va en el campo `dato` de tu respuesta. Debajo de cada acción van el sitio del script donde sale (línea y cita) y los ficheros del migrado en los que es más probable que esté.

{{DATOS}}

## Qué tienes que hacer

1. Para cada acción, busca en los ficheros del migrado el código o la configuración que hace lo mismo y elige un estado:
   - `igual`: el migrado hace lo mismo que cuenta la acción (mismas carpetas, mismos nombres de fichero, mismos días, mismo destino).
   - `distinto`: el migrado hace algo parecido, pero cambia algo (una carpeta, un número de días, un nombre, un orden).
   - `falta`: no encuentras nada que lo haga en esos ficheros.
   - `no-lo-se`: con lo que ves no puedes decidirlo.
2. Escribe en el fichero de ESCRIBIR un único objeto JSON. Sin texto antes ni después y sin bloques de código (nada de comillas invertidas).
3. Termina tu respuesta con una sola palabra: hecho.

## Campos del JSON

El objeto tiene un solo campo, `comparacion`: una lista con un elemento por cada acción de arriba, ni uno más ni uno menos, cada número una sola vez. Cada elemento tiene:

- `dato`: el número de la acción.
- `estado`: `igual`, `distinto`, `falta` o `no-lo-se`.
- `fichero`: en `igual` y `distinto`, una de las rutas de MIGRADO, copiada tal cual. En `falta` y `no-lo-se`, no lo pongas.
- `linea`: en `igual` y `distinto`, el número de la línea (desde 1) de ese fichero donde está el código o la configuración.
- `cita`: en `igual` y `distinto`, un trozo corto (como mucho {{CITA_MAX}} caracteres) de ese fichero, copiado tal cual, que se pueda buscar en él.
- `nota`: obligatoria en `distinto` (qué cambia respecto al script) y en `no-lo-se` (por qué no puedes decidirlo); opcional en `falta`.

## Reglas

- Las citas se comprueban buscándolas en el fichero. Cópialas tal cual y no inventes ninguna: si más de la mitad no se encuentran, se rechaza todo lo que has escrito.
- Que el script se ejecute en un servidor y el migrado en un contenedor no cuenta. Compara lo que se hace: qué ficheros, qué carpetas, cuántos días, a quién se manda.
- Si lo que hacía el script lo hace ahora la plataforma (una planificación, un configmap) ese código no está en estos ficheros: es `falta`.
- Si dudas entre `igual` y `distinto`, elige `distinto` y cuenta en la nota qué te hace dudar.
- No leas nada más que esos ficheros.

## Ejemplo de salida

Para un script con tres acciones, 0, 1 y 2, el fichero de salida contiene:

```json
{
  "comparacion": [
    { "dato": 0, "estado": "igual", "fichero": "src/main/java/com/acme/ArchivadorSalidas.java", "linea": 12, "cita": "static final String PATRON_ALTA = \"SALIDA_ALTA_\";", "nota": "" },
    { "dato": 1, "estado": "distinto", "fichero": "src/main/resources/application.yml", "linea": 4, "cita": "dias: 15", "nota": "El script borraba lo de más de 30 días y el migrado conserva 15." },
    { "dato": 2, "estado": "falta", "nota": "No hay nada que aparte los ficheros de entrada ya cargados." }
  ]
}
```
<!--CORRECCION-->

## CORRECCIÓN: tu intento anterior no pasó la comprobación

El script ha revisado lo que escribiste y ha encontrado esto:

{{MOTIVO}}

Vuelve a mirar las acciones y los ficheros de arriba, corrige solo eso y escribe el JSON completo otra vez en el fichero de ESCRIBIR. Las citas se copian tal cual del fichero del migrado.
