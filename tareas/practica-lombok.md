# Tarea: pasar a Lombok los getters y setters escritos a mano de un fichero

Un batch Java se ha migrado y el batch de referencia usa Lombok. Un script ha encontrado en este fichero getters y setters escritos a mano. Vas a cambiarlos por las anotaciones de Lombok, en este repositorio, sin cambiar lo que hace el programa.

TIPO: practica-lombok
FICHERO: {{FICHERO}}

## Lo que ha encontrado el script

{{DETALLE}}

## Qué tienes que hacer

- Cambia solo el fichero `{{FICHERO}}`. No toques ningún otro fichero, ni el `pom.xml`, ni los tests: si cambias otro, el script lo deshace.
- Quita los getters y setters triviales (el getter que solo devuelve el campo y el setter que solo lo asigna) y pon `@Getter` y `@Setter` en el campo, o en la clase si todos los campos los llevan. Añade los `import lombok.*` que hagan falta.
- Deja a mano los métodos que hacen algo más que devolver o asignar el campo (una conversión, una comprobación, una copia defensiva), los que no se llaman como Lombok los nombraría, los que tienen anotaciones propias y los que cambian la visibilidad. También el resto del código, sin tocarlo.
- Si el getter o el setter tenía Javadoc, pasa lo que decía al campo. No quites ningún comentario que no sea del método que borras.
- No cambies el orden de los campos ni los nombres, los tipos o las anotaciones del resto de la clase.
- No ejecutes Maven ni ningún otro comando: el script compila y comprueba que lo compilado queda igual. Si lo compilado cambia, tus cambios se deshacen.
- Si no hay nada que se pueda pasar a Lombok sin riesgo, no cambies nada.
- Termina tu respuesta con una sola palabra: hecho.
<!--CORRECCION-->

## CORRECCIÓN: tu intento anterior no pasó la comprobación

El script ha revisado lo que hiciste y ha encontrado esto:

{{MOTIVO}}

Tus cambios se han deshecho. Vuelve a empezar desde el código de antes y corrige eso: cambia solo lo que Lombok genera igual que estaba escrito.
