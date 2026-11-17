# Paso 2. Diagnóstico

**Qué se consigue:** la lista de lo que le falta al repo, paso a paso, comparado con la plantilla.
**¿Cambia algo?** No toca código. Solo escribe en la carpeta `.rescate`, que git ignora.

## Qué hacer

`.\rescate.ps1 -Repo <REPO> -Plantilla <PLANTILLA>`

Ejecuta Maven con los tests, así que puede tardar.

## Qué mirar

- La tabla del final: errores y avisos por paso.
- `<REPO>\.rescate\diagnostico.md`: el detalle, fichero a fichero.
- Explica qué significa cada paso que tenga errores, con un ejemplo sacado del informe.
- Comprueba una muestra leyendo el código: unos 5 hallazgos de `calidad` y 3 de los otros pasos. ¿Son reales? Apunta los que no lo sean.
- La línea «Siguiente paso recomendado» dice por dónde empezar.

Si una regla de `calidad` da muchos hallazgos falsos, se puede bajar de error a aviso para que no bloquee. Se hace en `.rescate\config.json`, con la clave `CalidadErrores`: la lista que trae el script en su bloque `CONFIGURACION`, sin esa regla. Antes de bajarla, apunta el caso para el informe.

## Cuándo está cerrado

- La persona puede decir con sus palabras qué pasos tienen errores y por qué.
- La muestra está comprobada y los hallazgos falsos, apuntados.
- Sabe cuál es el primer paso que hay que arreglar.

Apúntalo en la bitácora, con la tabla. Siguiente: `guia/paso-3-lista-de-jobs.md`.
