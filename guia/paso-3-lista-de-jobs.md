# Paso 3. Lista de jobs del original

**Qué se consigue:** la lista de jobs que tenía el batch de Java 8. Con ella el script puede comprobar que no falta ninguno (`paridad`) y que cada uno tiene una prueba de extremo a extremo (`e2e`).
**¿Cambia algo?** No toca código. Escribe `.rescate\contrato.json`.

## Si no hay repo original

Este paso se salta. Apunta en la bitácora que `paridad` y `e2e` se quedarán sin comprobar, y pasa al siguiente.

## Qué hacer

`.\rescate.ps1 -Modo pre -Repo <REPO> -Legacy <ORIGINAL>`

Busca los jobs por texto y usa Copilot para los que no se ven a simple vista. Con `-SinIA` solo busca por texto.

## Qué mirar

Abre `.rescate\contrato.json` y revísalo con la persona, job a job:

- ¿Están todos los jobs que lanza el planificador?
- ¿Los nombres son exactamente los que usa el planificador?
- ¿Sobra alguno que ya no se use?

Es lo único de todo el proceso que hay que validar a mano, y solo lo sabe quien conoce el batch. Si falta o sobra un job, se corrige en ese fichero respetando su formato.

## Cuándo está cerrado

- La persona confirma que la lista es la buena.

Apúntalo en la bitácora. Siguiente: `guia/paso-4-plan.md`.
