# Tarea: escribir un test unitario con un caso por cada regla de negocio de una clase

Un batch Java se ha migrado. Un script ha comprobado que esta clase cumple las reglas de negocio del original y ha encontrado en qué línea está cada una. Vas a escribir el test que vigila esas reglas: un test unitario de JUnit 5 con un método por regla.

TIPO: test-reglas
FICHERO: {{FICHERO}}
TEST: {{TEST}}

## Las reglas de la clase

Cada regla lleva su texto de negocio y, debajo, la línea de `{{FICHERO}}` donde está.

{{REGLAS}}

## Qué tienes que hacer

- Escribe un solo fichero nuevo: `{{TEST}}`. La clase se llama `{{TEST_CLASE}}` y su paquete es `{{PAQUETE}}`. No toques ningún otro fichero, ni `{{FICHERO}}`, ni el `pom.xml`: si cambias otro, el script lo deshace.
- Es un test unitario de JUnit 5 (`org.junit.jupiter.api`), sin contexto de Spring: nada de `@SpringBootTest`, `@ContextConfiguration`, `@SpringJUnitConfig` ni `SpringExtension`. Crea los objetos a mano. Si la clase necesita colaboradores, simúlalos con Mockito si el `pom.xml` ya lo tiene; si no, escribe una clase de prueba pequeña dentro del test.
- Un método `@Test` por regla, en el orden de la lista. Pon el texto de la regla en un `@DisplayName`.
- Cada método tiene que fallar si la línea de su regla cambia. El script va a cambiar un operador de esa línea (`==` por `!=`, `>=` por `<`, `&&` por `||`, `true` por `false`, quitar un `!`) y lanzar tu test: si sigue pasando, tu método no comprueba la regla.
- Para eso, comprueba el valor exacto en el límite de la regla: el caso que la cumple y el que no, con un valor justo a cada lado. Un método que solo comprueba que no hay excepción no vale.
- Prueba la regla tal como está escrita en el código. No cambies el código para que el test pase, aunque creas que tiene un error.
- Tiene que compilar y pasar con el código de `{{FICHERO}}` tal como está. No uses ficheros, base de datos, red ni la hora del sistema.
- No ejecutes Maven ni ningún otro comando: el script compila, lanza el test y cambia las líneas.
- Termina tu respuesta con una sola palabra: hecho.
<!--CORRECCION-->

## CORRECCIÓN: tu intento anterior no pasó la comprobación

El script ha revisado tu test y ha encontrado esto:

{{MOTIVO}}

Tu test se ha borrado. Vuelve a escribir `{{TEST}}` desde cero y corrige eso: cada método tiene que fallar cuando la línea de su regla cambia, y el test entero tiene que pasar con el código tal como está.
