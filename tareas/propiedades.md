# Tarea: poner en el yml del migrado las propiedades del original que faltan

Un batch Spring Batch de Java 8 se ha migrado a Java 21 y Spring Boot 3. Un script ha comparado las propiedades del original con las del migrado y estas faltan en el migrado. Vas a añadirlas a sus ficheros de configuración, en este repositorio.

TIPO: propiedades
ESCRIBIR: {{SALIDA}}

## Las claves que faltan

Una por línea. «original» dice dónde está la clave en el original: es solo una pista, no puedes leer ese fichero. El perfil `default` es el de los `application.*` a secas; otro perfil va en `application-<perfil>.*`. Si lleva «nombre nuevo», Spring Boot 3 la renombró: escribe ese nombre y no el viejo.

{{CLAVES}}

## Dónde puedes escribir

Solo en estos ficheros de este repositorio. Los marcados «nuevo» no existen todavía y puedes crearlos:

{{FICHEROS}}

Ejemplo de estilo, solo para leer (la configuración del batch de referencia; no la copies, mira cómo escribe las claves):

{{REFERENCIA}}

## Qué tienes que hacer

1. Añade cada clave con el nombre nuevo si lo lleva, en el fichero de su perfil y con el formato de ese fichero: en un `.yml`, anidada con la indentación y el orden que ya tiene el fichero; en un `.properties`, una línea.
2. Una clave marcada «secreto» va como `${NOMBRE}`, con el nombre que se te da, y nunca con su valor: no lo copies de ningún sitio.
3. No cambies ni borres nada de lo que ya está en los ficheros. Solo añades.
4. Si una clave ya no aplica (el código del migrado ya no la lee, o la sustituye otra que ya está), no la añadas y ponla en `noAplica` con el motivo.
5. No toques ningún otro fichero: ni `.java`, ni `pom.xml`, ni tests. Lo que cambies fuera de los ficheros de arriba se deshace.
6. No ejecutes Maven ni ningún otro comando, y no hagas ningún commit: el script compila, comprueba y hace el commit.
7. Escribe en el fichero de ESCRIBIR un único objeto JSON, sin texto antes ni después y sin bloques de código (nada de comillas invertidas). Si dudas de una clave, ponla en `noAplica` con tu motivo.
8. Termina tu respuesta con una sola palabra: hecho.

## Campos del JSON

- `anadidas`: una lista con una entrada por cada clave que has añadido: `clave` (la del original, tal cual aparece arriba, también si lleva nombre nuevo) y `fichero` (el fichero donde la has puesto).
- `noAplica`: una lista con una entrada por cada clave que no has añadido: `clave` (la del original) y `motivo` (una frase, no vacía).

Cada clave de la lista de arriba tiene que salir en una de las dos listas, y en una sola. Las listas vacías son `[]`.

## Ejemplo de salida

Para un fichero `application.yml` donde has añadido una clave y otra no aplica:

```json
{
  "anadidas": [ { "clave": "batch.reintentos", "fichero": "src/main/resources/application.yml" } ],
  "noAplica": [ { "clave": "batch.hilos", "motivo": "El código del migrado ya no la lee: usa el pool por defecto." } ]
}
```
<!--CORRECCION-->

## CORRECCIÓN: tu intento anterior no pasó la comprobación

El script ha revisado lo que hiciste y ha encontrado esto:

{{MOTIVO}}

Tus cambios se han deshecho: el repositorio está como al empezar. Vuelve a hacerlo desde cero, corrige eso y escribe otra vez el fichero de ESCRIBIR.
