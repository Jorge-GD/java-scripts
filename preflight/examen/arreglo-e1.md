# Tarea: arreglar un proyecto que ya no compila

Este proyecto Maven (la carpeta donde estás) dejó de compilar cuando se actualizó su librería interna, el paquete `com.ejemplo.lib`. La librería ya está en su versión nueva y es la que manda: no la cambies. Adapta el código que la usa.

## Qué tienes que hacer

1. Compila con `mvn -q test` y lee los errores.
2. Arregla el código hasta que `mvn -q test` pase.
3. Termina tu respuesta con una sola palabra: hecho.

## Reglas

- Cambia solo ficheros de `src/main`. No toques los tests (`src/test`), ni el `pom.xml`, ni ningún otro fichero.
- Los tests dicen cuál es el comportamiento correcto.
- No instales nada.
