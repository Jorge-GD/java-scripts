# Tarea: ficha de clase

Vas a leer UN fichero de código Java y a contar lo que hace con datos que otra persona pueda comprobar. No cambies ningún fichero del repositorio: tu única escritura es el fichero de salida.

LEER: {{FICHERO}}
LINEAS: {{LINEAS}}
ESCRIBIR: {{SALIDA}}

## Qué tienes que hacer

1. Lee las líneas de LINEAS del fichero de LEER. Las líneas se cuentan desde 1.
2. Escribe en el fichero de ESCRIBIR un único objeto JSON. Sin texto antes ni después y sin bloques de código (nada de comillas invertidas).
3. Termina tu respuesta con una sola palabra: hecho.

## Campos del JSON

- `fichero`: `{{RELATIVO}}`.
- `clase`: nombre de la clase principal, sin paquete.
- `papel`: uno de estos: {{PAPELES}}.
- `queHace`: una frase corta y sencilla, en español, de lo que hace la clase.
- `datos`: lista de cosas concretas que se ven en esas líneas. Puede estar vacía. Cada dato tiene:
  - `tipo`: uno de estos: {{TIPOS}}.
  - `texto`: una frase corta, en español, que explica el dato.
  - `linea`: número de la línea del fichero donde se ve.
  - `cita`: el trozo de código que lo demuestra, copiado TAL CUAL de esa línea. Máximo {{CITA_MAX}} caracteres.

Qué es cada `tipo`:

- `entrada-fichero`: lee un fichero (nombre, formato, ruta).
- `salida-fichero`: escribe un fichero.
- `sftp`: usa un servidor SFTP.
- `tabla-lee`: lee una tabla de base de datos.
- `tabla-escribe`: escribe en una tabla de base de datos.
- `parametro`: recibe un parámetro del job o de la línea de comandos.
- `config`: lee una propiedad de configuración.
- `regla`: una condición de negocio (si pasa esto, se hace aquello).
- `error`: cómo reacciona ante un fallo (reintenta, salta el registro, lanza una excepción).
- `externo`: llama a otro sistema que no es un fichero ni una tabla.

## Reglas

- Cada dato lleva su `cita`, copiada del código. Si no puedes citarlo, no lo escribas.
- Una cita inventada hace que se rechace la ficha entera, y se te pedirá repetirla.
- Cuenta solo lo que ves en esas líneas. No supongas lo que hacen otras clases.
- Cuenta cada condición por separado. Si un método comprueba cuatro cosas, son cuatro datos, aunque compartan el mismo código de error. No resumas varias en una.
- Cada sitio donde el código rechaza, salta o para (un `return` o un `throw` con un mensaje) es un dato. También los que parecen obvios: el dato que no existe en una tabla, el formato mal escrito, la fecha fuera de plazo.
- Si no hay nada que contar, escribe `"datos": []`.

## Ejemplo de salida

Para un fichero `ReciboValidator.java` que valida importes, el fichero de salida contiene:

```json
{
  "fichero": "src/main/java/com/acme/ReciboValidator.java",
  "clase": "ReciboValidator",
  "papel": "validador",
  "queHace": "Comprueba cada recibo antes de guardarlo.",
  "datos": [
    {
      "tipo": "regla",
      "texto": "El importe tiene que ser mayor que cero.",
      "linea": 31,
      "cita": "if (recibo.getImporte().signum() <= 0)"
    },
    {
      "tipo": "regla",
      "texto": "Si el cliente del recibo no existe, el recibo no vale.",
      "linea": 36,
      "cita": "if (cliente == null)"
    },
    {
      "tipo": "error",
      "texto": "Si el recibo no vale, lanza una excepción con el número del recibo.",
      "linea": 32,
      "cita": "throw new IllegalArgumentException(\"Recibo invalido: \" + recibo.getNumero());"
    }
  ]
}
```
<!--CORRECCION-->

## CORRECCIÓN: tu intento anterior no pasó la comprobación

El script ha revisado lo que escribiste y ha encontrado esto:

{{MOTIVO}}

Vuelve a leer el fichero, corrige solo eso y escribe el JSON completo otra vez en el fichero de ESCRIBIR. Las citas se copian TAL CUAL del código.
