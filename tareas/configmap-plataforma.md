# Tarea: adaptar un fichero de plataforma del repo de configmap

Trabajas en la carpeta del repo de configmap nuevo de un batch ya migrado. Tienes que escribir un solo fichero, `{{FICHERO}}`, adaptado del que tiene el batch de referencia. Solo escribes ese fichero: no toques nada más.

TIPO: configmap-plataforma

El batch migrado se llama `{{BATCH}}` y está en {{MIGRADO}}. Su `pom.xml` es {{MIGRADO}}/pom.xml: léelo si el fichero necesita algo de él (por ejemplo la versión de Java).

## El fichero del batch de referencia

Ya lleva el nombre del batch nuevo:

=====
{{REFERENCIA}}
=====

## Qué tienes que hacer

1. Escribe en `{{FICHERO}}` el fichero adaptado, con el mismo formato, el mismo orden y las mismas claves que el de referencia. Si es un fichero de YAML, las claves del primer nivel (o, si el primer nivel es una lista, las claves de cada elemento) son las mismas que las de la referencia.
2. Cambia solo lo que depende del batch: su nombre, la versión de Java del `pom.xml` del migrado y lo que se pueda saber leyendo el batch migrado. Lo demás se copia tal cual.
3. Lo que es propio de cada proyecto y no puedes saber (un identificador que da otra herramienta, por ejemplo) lleva `<PENDIENTE: qué falta>`. Nunca lo inventes ni copies el de la referencia.
4. No dejes ningún nombre del batch de referencia: el fichero que tienes arriba ya lo lleva cambiado y así tiene que quedar.
5. Nunca escribas contraseñas, tokens ni valores secretos.
6. Termina tu respuesta con una sola palabra: hecho.
<!--CORRECCION-->

## CORRECCIÓN: tu intento anterior no pasó la comprobación

El script ha revisado lo que escribiste y ha encontrado esto:

{{MOTIVO}}

Vuelve a escribir `{{FICHERO}}` y corrige solo eso. Lo que se pide arriba sigue igual: mismas claves que la referencia, sin ningún nombre del batch de referencia y con `<PENDIENTE: qué falta>` en lo que no puedas saber.
