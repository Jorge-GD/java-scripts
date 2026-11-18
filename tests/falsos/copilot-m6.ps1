# copilot-m6.ps1 - Copilot de mentira para las pruebas del M6 de tests/probar.ps1 (consejo, reflexion, atascados).
# Hace lo suyo y lo demas se lo pasa a copilot.ps1, que con estos guiones arregla como siempre.
# Cada llamada deja una linea en .rescate/llamadas-m6.log ('<k> | <tipo> | <flags> | <que>'; tipo: plan, consejo,
# reflexion, lote, pre, rechazo u otro) y una copia de su prompt en .rescate/falso-m6/<k>.md.
# RESCATE_FALSO lleva sus guiones separados por ';':
#   duda-plan          la revision previa escribe el plan de copilot.ps1 con dos dudas; la primera nombra Suelta
#   consejo-codigo     el consejo: una duda de codigo con la opcion 2 elegida (OPCION-B-MARCA)
#   consejo-persona    el consejo: una duda de persona con la opcion 3 elegida (OPCION-C-MARCA)
#   consejo-mixto      el consejo: la duda de codigo y otra de persona (DUDA-PERSONA-MARCA, OPCION-F-MARCA)
#   consejo-dos        el consejo trae 2 opciones (siempre)
#   consejo-elegida-4  el consejo elige la opcion 4; en el reintento (con CORRECCION), bien y de codigo
#   consejo-nada       no escribe el consejo y sale con 0
#   reflexion-mala     la reflexion trae solo dos de las cuatro secciones
#   sin-max            con --effort=max sale con 1 sin escribir nada (un Copilot que no admite ese esfuerzo)
#   atasca             un lote que lleva Suelta.java no cambia nada, salvo que el prompt traiga el consejo
#   atasca-siempre     un lote que lleva Suelta.java no cambia nada nunca
#   nada-sin-correccion  un lote sin CORRECCION no cambia nada
#   crea-fichero       un lote crea ademas output/de-la-ia.csv
#   quita-catch        un lote sin CORRECCION quita el segundo catch de CalidadMuestra (el error se propaga);
#                      con CORRECCION lo deja como estaba
#   mueve-catch        un lote quita ese catch y lo lleva, igual, a una clase nueva (TamanoSeguro)
#   catch-en-comentario  como quita-catch, y deja 'catch (' en un comentario y en un texto
#   mueve-a-util       un lote sin CORRECCION mueve LeerFichero a infrastructure/util, un subpaquete que la plantilla
#                      no tiene (el paso 'estructura' gana un hallazgo en la ruta nueva); con CORRECCION no cambia nada
$todos = $args
$guiones = @("$env:RESCATE_FALSO" -split ';' | Where-Object { $_ })
$flags = (@($args | Where-Object { "$_" -match '^--(model|effort)=' }) -join ' ')
$raiz = (Get-Location).Path
$rescate = Join-Path $raiz '.rescate'
$prompt = [System.IO.File]::ReadAllText((Join-Path $rescate 'prompt.md'))
$titulo = ($prompt -split "`r?`n")[0]
$log = Join-Path $rescate 'llamadas-m6.log'

function Apunta([string]$Tipo, [string]$Que) {
  $k = 1
  if (Test-Path -LiteralPath $log) { $k = @([System.IO.File]::ReadAllLines($log)).Count + 1 }
  $dir = Join-Path $rescate 'falso-m6'
  if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
  [System.IO.File]::WriteAllText((Join-Path $dir "$k.md"), $prompt)
  [System.IO.File]::AppendAllText($log, "$k | $Tipo | $flags | $Que`n")
}
function Escribir([string]$Rel, [string]$Texto) {
  $p = $raiz
  foreach ($s in $Rel.Split('/')) { if ($s) { $p = Join-Path $p $s } }
  $d = Split-Path $p -Parent
  if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -Force) }
  [System.IO.File]::WriteAllText($p, $Texto)
}

if ($guiones -contains 'sin-max' -and $args -contains '--effort=max') {
  Apunta 'rechazo' $titulo
  "error: invalid value 'max' for '--effort <level>'"
  exit 1
}

# ---- consejo: escribe .rescate/consejo-<n>.json ----
if ($titulo -match 'consejo') {
  $salida = [regex]::Match($prompt, '\.rescate/(consejo-\d+\.json)').Groups[1].Value
  Apunta 'consejo' ((@([regex]::Matches($prompt, 'src/[\w/.-]+\.java') | ForEach-Object { $_.Value } | Select-Object -Unique)) -join ',')
  if ($guiones -contains 'consejo-nada') { 'no tengo consejo'; exit 0 }
  $correccion = ($prompt -match '## CORRECCION')
  $tipo = 'codigo'; $eleg = 2
  if ($guiones -contains 'consejo-persona') { $tipo = 'persona'; $eleg = 3 }
  if ($guiones -contains 'consejo-elegida-4' -and -not $correccion) { $eleg = 4 }
  $ops = @('OPCION-A-MARCA', 'OPCION-B-MARCA: mueve la clase como la plantilla', 'OPCION-C-MARCA')
  if ($guiones -contains 'consejo-dos') { $ops = @($ops[0], $ops[1]) }
  $dudas = @([ordered]@{ duda = 'DUDA-MARCA'; opciones = $ops; elegida = $eleg; porque = 'PORQUE-MARCA'; tipo = $tipo })
  if ($guiones -contains 'consejo-mixto') {
    $dudas += [ordered]@{ duda = 'DUDA-PERSONA-MARCA'; opciones = @('OPCION-D-MARCA', 'OPCION-E-MARCA', 'OPCION-F-MARCA'); elegida = 3; porque = 'PORQUE-PERSONA-MARCA'; tipo = 'persona' }
  }
  Escribir ".rescate/$salida" (ConvertTo-Json -InputObject ([ordered]@{ dudas = $dudas }) -Depth 5)
  'consejo escrito'
  exit 0
}

# ---- reflexion: escribe .rescate/reflexion-<paso>-<lote>-<intento>.md ----
if ($titulo -match 'reflexion') {
  $m = [regex]::Match($prompt, '\.rescate/(reflexion-([\w-]+)\.md)')
  Apunta 'reflexion' $m.Groups[2].Value
  $marca = 'REFLEXION-MARCA-' + $m.Groups[2].Value
  $t = @('## Que se intento', "$marca mover las clases.", '', '## Por que no paso', 'No cambio nada.')
  if ($guiones -notcontains 'reflexion-mala') { $t += @('', '## Que hacer ahora', 'Mover la clase a application/usecases.', '', '## Que no hacer', 'No tocar el pom.xml.') }
  Escribir ".rescate/$($m.Groups[1].Value)" ($t -join "`n")
  'reflexion escrita'
  exit 0
}

if ($titulo -match 'revision previa') {
  Apunta 'plan' ''
  & (Join-Path $PSScriptRoot 'copilot.ps1') @todos
  $codigo = $LASTEXITCODE
  if ($guiones -contains 'duda-plan') {
    $ruta = @(Get-ChildItem -LiteralPath $rescate -Filter 'plan-*.md')[0].FullName
    $plan = [System.IO.File]::ReadAllText($ruta) -replace '(?s)## Dudas.*$', "## Dudas`n- DUDA-PLAN-MARCA: Suelta va en application o en domain?`n- Hay que cambiar el parent del pom?`n"
    [System.IO.File]::WriteAllText($ruta, $plan)
  }
  exit $codigo
}

if ($titulo -match 'inventario de jobs') { Apunta 'pre' ''; 'sin jobs'; exit 0 }

if ($titulo -notmatch "rescate de migracion: paso '(\w+)'") {
  Apunta 'otro' $titulo
  & (Join-Path $PSScriptRoot 'copilot.ps1') @todos
  exit $LASTEXITCODE
}

# ---- lote ----
$fichs = @()
$dentro = $false
foreach ($l in ($prompt -split "`r?`n")) {
  if ($l -match '^## Hallazgos') { $dentro = $true; continue }
  if ($dentro -and $l -match '^## ') { break }
  if ($dentro -and $l -match '^- (\S+?)(:\d+)? - ') { $fichs += $Matches[1] }
}
$fichs = @($fichs | Select-Object -Unique)
Apunta 'lote' ($fichs -join ',')
$conSuelta = (@($fichs | Where-Object { $_ -match 'Suelta\.java$' }).Count -gt 0)
if ($guiones -contains 'atasca-siempre' -and $conSuelta) { 'no hago nada'; exit 0 }
if ($guiones -contains 'atasca' -and $conSuelta -and $prompt -notmatch '## Consejo') { 'no hago nada'; exit 0 }
if ($guiones -contains 'nada-sin-correccion' -and $prompt -notmatch '## CORRECCION') { 'no hago nada'; exit 0 }
if ($guiones -contains 'crea-fichero') { Escribir 'output/de-la-ia.csv' "id;nota`n1;de la IA`n" }
& (Join-Path $PSScriptRoot 'copilot.ps1') @todos
$codigo = $LASTEXITCODE
if ($guiones -contains 'mueve-a-util' -and $prompt -notmatch '## CORRECCION') {
  $ruta = Join-Path $raiz 'src/main/java/com/acme/life/application/usecases/LeerFichero.java'
  if (Test-Path -LiteralPath $ruta) {
    $t = [System.IO.File]::ReadAllText($ruta) -replace '(?m)^package [^;]*;', 'package com.acme.life.infrastructure.util;'
    Remove-Item -LiteralPath $ruta -Force
    Escribir 'src/main/java/com/acme/life/infrastructure/util/LeerFichero.java' $t
  }
}
$deCatch = @($guiones | Where-Object { @('quita-catch', 'mueve-catch', 'catch-en-comentario') -contains $_ })
if ($deCatch.Count -gt 0) {
  $cm = 'src/main/java/com/acme/life/application/usecases/CalidadMuestra.java'
  if ($prompt -match '## CORRECCION') { [void](& git checkout -q HEAD -- $cm) }
  else {
    $sin = "`n        datos.size();"
    if ($deCatch -contains 'catch-en-comentario') { $sin = "`n        // antes: catch (RuntimeException e)`n        String nota = `"catch (RuntimeException e)`";" + $sin }
    $ruta = Join-Path $raiz $cm
    $t = [regex]::Replace([System.IO.File]::ReadAllText($ruta), '\n        try \{\s*datos\.size\(\);\s*\} catch \(RuntimeException e\) \{\s*// se ignora a proposito\s*\}', $sin)
    [System.IO.File]::WriteAllText($ruta, $t)
    if ($deCatch -contains 'mueve-catch') {
      Escribir 'src/main/java/com/acme/life/application/usecases/TamanoSeguro.java' (@(
          'package com.acme.life.application.usecases;', '', 'import java.util.List;', '',
          '/** Mira el tamano de una lista y sigue aunque falle, como antes en CalidadMuestra. */',
          'final class TamanoSeguro {', '', '    private TamanoSeguro() {', '    }', '',
          '    static void mira(List<String> datos) {', '        try {', '            datos.size();',
          '        } catch (RuntimeException e) {', '            // se ignora a proposito', '        }', '    }', '}', '') -join "`n")
    }
  }
}
exit $codigo
