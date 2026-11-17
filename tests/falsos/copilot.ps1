# copilot.ps1 - Copilot CLI de mentira para tests/probar.ps1.
# Lee .rescate/prompt.md, como haria el de verdad, y hace cambios fijos segun
# el paso. La variable de entorno RESCATE_FALSO elige el guion:
#   (vacio)            arregla bien
#   nada               no cambia nada
#   sin-javadoc        arregla, pero el codigo nuevo va sin Javadoc hasta que
#                      el script se lo reclama en la correccion
#   toca-plantilla     ademas escribe en la plantilla (prohibido)
#   plan-toca-codigo   en la revision previa toca codigo (prohibido)
# Cada llamada deja una linea en .rescate/llamadas.log, con el modelo y el
# esfuerzo que ha recibido.
$flags = (@($args | Where-Object { "$_" -match '^--(model|effort)=' }) -join ' ')
$raiz = (Get-Location).Path
$rescate = Join-Path $raiz '.rescate'
$prompt = [System.IO.File]::ReadAllText((Join-Path $rescate 'prompt.md'))
$guion = "$env:RESCATE_FALSO"
$titulo = ($prompt -split "`r?`n")[0]
$correccion = ($prompt -match '## CORRECCION')
$conPlan = ($prompt -match '## Plan aprobado')
[System.IO.File]::AppendAllText((Join-Path $rescate 'llamadas.log'), ($titulo + ' | correccion=' + $correccion + ' | plan=' + $conPlan + ' | ' + $flags + "`n"))

function Get-Ruta([string]$Rel) {
  $p = $raiz
  foreach ($s in $Rel.Split('/')) { if ($s) { $p = Join-Path $p $s } }
  return $p
}
function Leer([string]$Rel) { return [System.IO.File]::ReadAllText((Get-Ruta $Rel)) }
function Escribir([string]$Rel, [string]$Texto) {
  $ruta = Get-Ruta $Rel
  $dir = Split-Path $ruta -Parent
  if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
  [System.IO.File]::WriteAllText($ruta, $Texto)
}

# Ficheros de la lista de hallazgos del prompt
$fichs = @()
$dentro = $false
foreach ($l in ($prompt -split "`r?`n")) {
  if ($l -match '^## Hallazgos') { $dentro = $true; continue }
  if ($dentro -and $l -match '^## ') { break }
  if ($dentro -and $l -match '^- (\S+?)(:\d+)? - ') { $fichs += $Matches[1] }
}
$fichs = @($fichs | Where-Object { $_ -ne '(repo)' } | Select-Object -Unique)

# ---- revision previa: solo escribe el plan ----
if ($titulo -match "revision previa del paso '(\w+)'") {
  $p = $Matches[1]
  $t = @("# Plan del paso '$p'", '', '## Piezas comunes', 'ninguna', '', '## Ficheros')
  foreach ($f in $fichs) { $t += ('- `' + $f + '` -> arreglar | destino: - | riesgo: bajo') }
  $t += @('', '## Orden', 'El de la lista.', '', '## Dudas', 'ninguna')
  Escribir ".rescate/plan-$p.md" ($t -join "`n")
  if ($guion -eq 'plan-toca-codigo') {
    $v = @($fichs | Where-Object { $_ -match '\.java$' })[0]
    Escribir $v ((Leer $v) + "`n// tocado en la revision`n")
  }
  'plan escrito'
  exit 0
}

# ---- lote de arreglo ----
if ($titulo -notmatch "paso '(\w+)'") {
  'no entiendo el prompt'
  exit 1
}
$paso = $Matches[1]
if ($guion -eq 'nada') {
  'no hago nada'
  exit 0
}
if ($guion -eq 'toca-plantilla' -and $prompt -match '(?m)^- PLANTILLA: (.+)$') {
  $pl = $Matches[1].Trim()
  [System.IO.File]::AppendAllText((Join-Path $pl 'pom.xml'), "`n<!-- tocado por la IA -->`n")
}
$base = 'src/main/java/com/acme/life/'
switch ($paso) {
  'estructura' {
    # mueve cada clase a application/usecases y le cambia el package
    foreach ($f in $fichs) {
      if (-not $f.StartsWith($base) -or -not $f.EndsWith('.java')) { continue }
      $nombre = $f.Split('/')[-1]
      $texto = (Leer $f) -replace '(?m)^package [^;]*;', 'package com.acme.life.application.usecases;'
      Remove-Item -LiteralPath (Get-Ruta $f) -Force
      Escribir ($base + 'application/usecases/' + $nombre) $texto
    }
  }
  'hexagonal' {
    # quita del dominio lo que depende de Spring y crea un puerto nuevo
    foreach ($f in $fichs) {
      $lineas = @((Leer $f) -split "`r?`n" | Where-Object { $_ -notmatch 'org\.springframework' -and $_ -notmatch '^@Component' })
      Escribir $f ($lineas -join "`n")
    }
    if ($guion -eq 'sin-javadoc') {
      $puerto = @('package com.acme.life.application.ports.output;', '')
      if ($correccion) { $puerto += '/** Puerto de salida para guardar clientes. */' }
      $puerto += 'public interface ClientePort {'
      if ($correccion) {
        $puerto += @('', '    /**', '     * Guarda un cliente.', '     *', '     * @param cliente nombre del cliente', '     */')
      }
      $puerto += @('    void guardar(String cliente);', '}', '')
      Escribir ($base + 'application/ports/output/ClientePort.java') ($puerto -join "`n")
    }
  }
}
'hecho'
exit 0
