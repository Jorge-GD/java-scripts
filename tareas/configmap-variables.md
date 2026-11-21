# Tarea: emparejar las variables del batch migrado con las claves de su inventario

El batch migrado lee variables de entorno (`${...}`) en sus ficheros de configuración. El batch original se desplegaba con un inventario de propiedades, y de ese inventario solo ves los nombres de las claves, nunca sus valores. Tienes que decir, para cada variable, qué clave del inventario le corresponde. Solo lees: no cambies ningún fichero. Tu única escritura es el fichero de salida.

TIPO: configmap-variables
ESCRIBIR: {{SALIDA}}

## Las variables

Una por línea: su nombre, el fichero y la línea donde sale y esa línea tal cual:

{{VARIABLES}}

## Las claves del inventario

Esta es la lista cerrada. No hay más, y no sabes ni quieres saber sus valores:

{{CLAVES}}

## Qué tienes que hacer

1. Para cada variable, busca en la lista la clave que guarda lo mismo. Fíjate en el nombre y en el sentido: puede cambiar el separador (`.`, `-`, `_`), el orden de los trozos, un prefijo o un sufijo, o estar escrita de otra forma. Si hace falta, mira el código y la configuración del batch migrado, que tienes a la vista en {{MIGRADO}}, para entender qué guarda cada variable.
2. La clave de tu respuesta se copia tal cual de la lista. Si ninguna le corresponde, escribe `ninguna`. Si dudas entre dos, elige la más probable; si no hay una más probable, `ninguna`.
3. Marca `secreto` con `true` si la variable guarda una contraseña, un usuario, un token, una clave o cualquier cosa que no debe verse en claro, aunque su nombre no lo diga; si no, `false`.
4. Da una respuesta por cada variable de arriba, ni una más ni una menos y sin repetir ninguna.
5. Escribe en el fichero de ESCRIBIR un único objeto JSON. Sin texto antes ni después y sin bloques de código (nada de comillas invertidas).
6. Termina tu respuesta con una sola palabra: hecho.

## Campos del JSON

El objeto tiene un solo campo, `variables`: una lista con un elemento por variable:

- `variable`: el nombre de la variable, copiado tal cual de arriba.
- `clave`: una clave de la lista del inventario, copiada tal cual, o `ninguna`.
- `secreto`: `true` o `false`.
- `porque`: una frase corta que dice por qué.

## Ejemplo de salida

```json
{
  "variables": [
    { "variable": "env.ejemplo-ruta", "clave": "ejemplo.ruta.entrada", "secreto": false, "porque": "Las dos guardan la carpeta de entrada." },
    { "variable": "env.ejemplo-clave", "clave": "ejemplo.pass", "secreto": true, "porque": "Es la contraseña de la misma conexión." },
    { "variable": "env.ejemplo-nueva", "clave": "ninguna", "secreto": false, "porque": "Ninguna clave del inventario guarda algo parecido." }
  ]
}
```
<!--CORRECCION-->

## CORRECCIÓN: tu intento anterior no pasó la comprobación

El script ha revisado lo que escribiste y ha encontrado esto:

{{MOTIVO}}

Vuelve a mirar las variables y las claves de arriba y escribe el JSON completo otra vez en el fichero de ESCRIBIR: una respuesta por cada variable, con una clave copiada tal cual de la lista o `ninguna`.
