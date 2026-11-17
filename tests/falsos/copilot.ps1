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
#
# Tareas de migracion.ps1 (el texto de -p nombra .rescate/tareas/<id>.prompt.md):
# lee del prompt las lineas LEER, LINEAS y ESCRIBIR y escribe una ficha de clase.
# RESCATE_FALSO es 'guion' o 'guion:regex', y varios se separan con ';'. Cada guion
# solo vale para los ficheros cuyo nombre (sin .java) cumple su regex (sin regex,
# para todos); gana el primero que encaja y los demas ficheros salen bien:
#   (vacio)            ficha correcta
#   texto-libre        contesta con texto y no escribe el fichero
#   cita-inventada     tres datos: uno bien, uno en otra linea y uno con la cita inventada
#   citas-inventadas   todas las citas inventadas
#   sin-datos          ficha valida pero con la lista de datos vacia
#   json-roto          JSON cortado
#   una-vez-roto       JSON cortado la primera vez y bien en el reintento
#   lento              tarda 3 s
#   colgado            no acaba nunca
#   toca-codigo        ficha correcta, pero cambia un fichero del repo de trabajo
#   toca-original      ficha correcta, pero cambia el fichero que lee
#   falla-siempre      sale con 1 sin escribir nada
#   falla-una-vez      sale con 1 la primera vez y el reintento sale bien
#   cita-larga         una cita de 130 caracteres
#   papel-libre        un papel que no esta en la lista
#   tipo-libre         un tipo de dato que no esta en la lista
#   linea-texto        la linea es un texto ("31"), no un numero
#   linea-cero         la linea es 0
#   linea-decimal      la linea es 3.5
#   json-lista         el JSON es una lista, no un objeto
#   json-texto         el JSON es un texto, no un objeto
#   toca-y-calla       el primer intento: ficha correcta y cambia el repo; el segundo:
#                      no escribe nada y sale con 0 (la ficha vieja no puede dar el paso por buena)
#   sin-cuota          sale con 1 diciendo que se ha pasado la cuota mensual
#   error-privado      sale con 1 y escribe el texto de la variable RESCATE_ERROR_TEXTO
#   valor-secreto      ficha con un papel que no vale y que lleva un texto con comillas simples
#   cita-secreta       ficha con todas las citas inventadas, con texto y comillas simples
#   borra-carpeta      borra la carpeta de la variable RESCATE_BORRAR antes de leer (la ficha sale bien)
# Cada llamada deja .rescate/falso/<id>-<pid>.txt con sus datos y sus horas
# (ticks UTC de inicio y de fin; un fin ausente es una llamada que nadie vio acabar).
# Con la variable RESCATE_LLAMADAS (una carpeta) deja ademas una copia de ese fichero alli:
# sirve para ver las llamadas de un script que borra su carpeta de trabajo (el preflight).
# Si ademas existe la variable RESCATE_COPIA_RESULTADO (un fichero), deja en esa carpeta una copia
# de ese fichero, tal como estaba en el momento de la llamada, como resultado-<id>.txt.
#
# Sondas del preflight (bloque 3): con --version o --help no llama a ningun modelo. Dice una
# version o una ayuda con modelos. El guion 'rechaza-bandera:<bandera>' hace que rechace esa
# bandera con el mismo error que el Copilot real ("error: unexpected argument '<bandera>' found").
if ($args -contains '--version' -or $args -contains '--help') {
  foreach ($g in ("$env:RESCATE_FALSO" -split ';')) {
    $nombre, $solo = ($g -split ':', 2)
    if ($nombre -eq 'rechaza-bandera' -and $solo) {
      foreach ($a in $args) { if ("$a" -eq $solo -or "$a" -like "$solo=*") { "error: unexpected argument '$a' found"; exit 2 } }
    }
  }
  if ($args -contains '--help') {
    'GitHub Copilot CLI (de mentira)'
    '  --model <model>   Modelo a usar (choices: "gpt-6-luna", "claude-sonnet-5.5", "gemini-3.8-flash")'
    exit 0
  }
  'GitHub Copilot CLI 1.0.112 (de mentira).'
  exit 0
}
$texto = ''
for ($i = 0; $i -lt $args.Count - 1; $i++) { if ("$($args[$i])" -eq '-p') { $texto = "$($args[$i + 1])" } }
if ($texto -match '\.rescate/tareas/\S+\.prompt\.md') {
  $raiz = (Get-Location).Path
  $prompt = [System.IO.File]::ReadAllText((Join-Path (Join-Path (Join-Path $raiz '.rescate') 'tareas') (Split-Path $Matches[0] -Leaf)))
  $leer = ([regex]::Match($prompt, '(?m)^LEER: (.+?)\s*$')).Groups[1].Value
  $salida = ([regex]::Match($prompt, '(?m)^ESCRIBIR: (.+?)\s*$')).Groups[1].Value
  $rango = [regex]::Match($prompt, '(?m)^LINEAS: (\d+)-(\d+)\s*$')
  $id = [System.IO.Path]::GetFileName($salida) -replace '\.json$', ''
  $correccion = ($prompt -match '## CORRECCI')
  $efecto = (@($args | Where-Object { "$_" -match '^--(model=|effort=|add-dir=|available-tools=|no-custom-instructions$)' }) -join ' ')
  $clase = [System.IO.Path]::GetFileNameWithoutExtension($leer)
  $guion = ''
  foreach ($g in ("$env:RESCATE_FALSO" -split ';')) {
    $nombre, $solo = ($g -split ':', 2)
    if (-not $solo) { $solo = '.' }
    if ($nombre -and -not $guion -and $clase -match $solo) { $guion = $nombre }
  }
  $dirFalso = Join-Path (Join-Path $raiz '.rescate') 'falso'
  [void](New-Item -ItemType Directory -Path $dirFalso -Force)
  $registro = Join-Path $dirFalso ($id + '-' + $PID + '.txt')
  $reg = @("id=$id", "pid=$PID", "flags=$efecto", "correccion=$correccion", "guion=$guion", ('inicio=' + [DateTime]::UtcNow.Ticks))
  [System.IO.File]::WriteAllLines($registro, [string[]]$reg)
  $copiar = {
    if ($env:RESCATE_LLAMADAS) {
      [void](New-Item -ItemType Directory -Path $env:RESCATE_LLAMADAS -Force)
      Copy-Item -LiteralPath $registro -Destination (Join-Path $env:RESCATE_LLAMADAS (Split-Path $registro -Leaf)) -Force
      if ($env:RESCATE_COPIA_RESULTADO -and (Test-Path -LiteralPath $env:RESCATE_COPIA_RESULTADO)) {
        $copia = Join-Path $env:RESCATE_LLAMADAS ('resultado-' + $id + '.txt')
        if (-not (Test-Path -LiteralPath $copia)) { Copy-Item -LiteralPath $env:RESCATE_COPIA_RESULTADO -Destination $copia }
      }
    }
  }
  & $copiar
  # que intento es: las llamadas que ha tenido esta tarea, contada la actual
  $patron = '^' + [regex]::Escape($id) + '-\d+\.txt$'
  $intento = @(Get-ChildItem -LiteralPath $dirFalso -File | Where-Object { $_.Name -match $patron }).Count

  if ($guion -eq 'falla-siempre' -or ($guion -eq 'falla-una-vez' -and $intento -eq 1)) { 'Error: no hay sesion iniciada'; exit 1 }
  if ($guion -eq 'sin-cuota') { 'Error: You have exceeded your monthly quota.'; exit 1 }
  if ($guion -eq 'error-privado') { "$env:RESCATE_ERROR_TEXTO"; exit 1 }
  if ($guion -eq 'texto-libre') { 'Claro, el fichero valida importes y es muy sencillo.'; & $copiar; exit 0 }
  if ($guion -eq 'borra-carpeta' -and $env:RESCATE_BORRAR) { Remove-Item -LiteralPath $env:RESCATE_BORRAR -Recurse -Force -ErrorAction SilentlyContinue }
  if ($guion -eq 'colgado') { Start-Sleep -Seconds 120 }
  if ($guion -eq 'lento') { Start-Sleep -Seconds 3 }

  $lineas = [System.IO.File]::ReadAllLines($leer)
  $desde = 1; $hasta = $lineas.Count
  if ($rango.Success) { $desde = [int]$rango.Groups[1].Value; $hasta = [int]$rango.Groups[2].Value }
  $reales = @(for ($n = $desde; $n -le [Math]::Min($hasta, $lineas.Count); $n++) {
      if ($lineas[$n - 1] -match ';\s*$' -and $lineas[$n - 1] -notmatch '^\s*(package|import)\b') { $n }
    })
  function Nuevo-Dato([int]$Linea, [string]$Cita) {
    return [ordered]@{ tipo = 'regla'; texto = "Linea $Linea"; linea = $Linea; cita = $Cita }
  }
  $datos = @()
  foreach ($n in @($reales | Select-Object -First 2)) { $datos += (Nuevo-Dato $n $lineas[$n - 1].Trim()) }
  if ($guion -eq 'citas-inventadas') {
    $datos = @(1..3 | ForEach-Object { Nuevo-Dato $_ "esta cita no sale en el fichero $_" })
  }
  if ($guion -eq 'cita-inventada') {
    $datos = @((Nuevo-Dato $reales[0] $lineas[$reales[0] - 1].Trim()), (Nuevo-Dato ($reales[1] + 40) $lineas[$reales[1] - 1].Trim()), (Nuevo-Dato 3 'esta cita no sale en el fichero'))
  }
  if ($guion -eq 'sin-datos') { $datos = @() }
  if ($guion -eq 'cita-larga') { $datos[0].cita = ('x' * 130) }
  if ($guion -eq 'tipo-libre') { $datos[0].tipo = 'inventado' }
  if ($guion -eq 'linea-texto') { $datos[0].linea = '31' }
  if ($guion -eq 'linea-cero') { $datos[0].linea = 0 }
  if ($guion -eq 'linea-decimal') { $datos[0].linea = 3.5 }
  if ($guion -eq 'cita-secreta') {
    $datos = @(1..3 | ForEach-Object { Nuevo-Dato $_ "SECRETO-ZORBA 'cita $_' no sale en el fichero" })
  }
  $papel = 'otro'
  if ($guion -eq 'papel-libre') { $papel = 'inventado' }
  if ($guion -eq 'valor-secreto') { $papel = "SECRETO-ZORBA'valor'raro" }
  $ficha = [ordered]@{ fichero = (Split-Path $leer -Leaf); clase = $clase; papel = $papel; queHace = "Ficha de prueba de $clase."; datos = $datos }
  $json = ConvertTo-Json -InputObject $ficha -Depth 6
  if ($guion -eq 'json-lista') { $json = '[1, 2, 3]' }
  if ($guion -eq 'json-texto') { $json = '"hola"' }
  if ($guion -eq 'toca-y-calla' -and $intento -gt 1) { 'hecho'; & $copiar; exit 0 }
  if ($guion -eq 'json-roto' -or ($guion -eq 'una-vez-roto' -and -not $correccion)) { $json = $json.Substring(0, [int]($json.Length / 2)) }
  $ruta = $raiz
  foreach ($s in $salida.Split('/')) { $ruta = Join-Path $ruta $s }
  [System.IO.File]::WriteAllText($ruta, $json)
  if ($guion -eq 'toca-codigo' -or $guion -eq 'toca-y-calla') {
    $f = @(Get-ChildItem -LiteralPath (Join-Path $raiz 'src') -Recurse -File -Filter '*.java')[0]
    [System.IO.File]::AppendAllText($f.FullName, "`n// tocado por la lectura`n")
  }
  if ($guion -eq 'toca-original') { [System.IO.File]::AppendAllText($leer, "`n// tocado por la lectura`n") }
  [System.IO.File]::AppendAllText($registro, ('fin=' + [DateTime]::UtcNow.Ticks + "`n"))
  & $copiar
  'hecho'
  exit 0
}

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
