# Guía para la IA: scripts que terminan migraciones de batchs

En esta carpeta hay scripts de PowerShell que terminan la migración de un batch de Spring Batch a Java 21. Quien te habla está migrando uno o varios batchs a la vez. Los scripts y los batchs están en carpetas hermanas.

## Si te pregunta en qué punto está o qué comando lanzar

1. Ejecuta en esta carpeta:
   - para todos los batchs, `.\donde-estoy.ps1`;
   - para uno, `.\donde-estoy.ps1 -Migrado "C:\ruta\del\migrado"`.
   Es rápido y solo lee: no cambia nada.
2. Contesta con lo que dice el script, en este orden:
   - en qué punto está;
   - el siguiente paso, con su comando;
   - lo de «Después», si sale.
3. Copia cada comando tal cual: sin cambiar parámetros ni rutas. No inventes comandos. Si el script no da ninguno, dilo.
4. Si te pregunta qué hace un paso, la explicación está en `FLUJO.md`. Lee solo la sección de ese paso.

Cuando el script habla de «la página 1, 2, 3 o 4», se refiere al informe del batch, en `<migrado>\migracion-<batch>\`:

| Página | Fichero | Qué tiene |
|---|---|---|
| Portada | `index.html` | Cómo ha ido, el siguiente paso y qué es cada fichero |
| 1 | `1-batch-original.html` | Qué hace el batch original y el guion para probar cada job en pre |
| 2 | `2-problemas.html` | Los problemas del migrado |
| 3 | `3-original-vs-migrado.html` | El original frente al migrado: la prueba en local y la lectura de la IA |
| 4 | `4-correcciones.html` | Lo corregido y lo que queda |

## Si algo ha fallado

- El script que falló dice dónde está su registro, en la consola y en la portada (`migracion-<batch>\index.html`).
- Lee solo el final del registro, unas 60 líneas. Resume en 3 frases qué estaba haciendo y dónde se paró.
- Relanzar el mismo comando siempre es seguro: salta lo hecho y sigue donde se quedó.

## Lo que no haces

- No lances tú `migracion.ps1`, `prueba-local.ps1` ni `rescate.ps1`. Tardan horas y llaman a Copilot. Da el comando y que lo lance la persona.
- No cambies el código de los batchs ni el de estos scripts.
- No hagas `git push`, `git merge` ni `git reset`, y no borres carpetas ni worktrees. Si hace falta, da el comando.
- No copies fuera de este equipo datos del trabajo: contraseñas, hosts, nombres de clientes o rutas.
