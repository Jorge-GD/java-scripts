# copilot.ps1 - Copilot CLI de mentira para tests/probar.ps1.
# Lee .rescate/prompt.md, como haria el de verdad, y hace cambios fijos segun
# el paso. La variable de entorno RESCATE_FALSO elige el guion:
#   (vacio)            arregla bien
#   nada               no cambia nada
#   sin-javadoc        arregla, pero el codigo nuevo va sin Javadoc hasta que
#                      el script se lo reclama en la correccion
#   toca-plantilla     ademas escribe en la plantilla (prohibido)
#   plan-toca-codigo   en la revision previa toca codigo (prohibido)
#   lento              tarda 3 s antes de hacer nada (para probar el latido de rescate.ps1)
#   mueve-a-infrastructure   en 'estructura' mueve las clases a infrastructure/util, un subpaquete que la plantilla no tiene
# Paso 'sonar' (cada incidencia del prompt, '- fichero:linea - detalle', se "corrige" cambiando su linea marcada):
#   (vacio)            le anade un comentario a la linea marcada
#   sonar-nosonar      solo le anade '// NOSONAR'
#   sonar-suppress     cambia la linea y anade @SuppressWarnings al final del fichero
#   sonar-disabled     cambia la linea y anade @Disabled a un test
#   sonar-borra-test   cambia la linea y borra un fichero de src/test
#   sonar-sin-tocar    no toca la linea marcada: cambia otra cosa del fichero
#   sonar-atasca       no toca las incidencias cuyo detalle lleva ATASCA y corrige las demas
#   sonar-deja         no toca las que llevan DEJAME en el detalle: las apunta con su motivo en .rescate/sonar-sin-arreglar.txt
#                      (y una linea que no casa con ninguna) y corrige las demas
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
#   tipos-variados     ficha con un tipo de dato distinto en cada dato (reparte los diez tipos)
# Los tres tipos de tarea del negocio llevan una linea TIPO: en el prompt y el falso escribe
# lo que corresponde. La clave de los regex es 'tipo:nombre' (definicion-job:<fichero sin .java>,
# ficha-job:<job>, resumen:); la de la ficha de clase sigue siendo el nombre de la clase:
#   (vacio)            definicion-job: los jobs de la linea JOBS, cada paso (stepBuilderFactory.get("x"))
#                      en el job cuya linea le precede, con las clases de la lista CLASES que
#                      empiezan por el nombre del paso sin 'Step'. ficha-job: dos pasos con la
#                      primera y la ultima referencia del prompt. resumen: todos los jobs en orden.
#   job-clase-fuera    definicion-job con una clase que no esta en la lista cerrada
#   job-ref-mixta      ficha-job con un paso bien referenciado y otro con una referencia que no existe
#   job-ref-mala       ficha-job con todas las referencias inventadas
#   job-clase-en-texto ficha-job con el nombre de una clase en el titulo (solo en el primer intento)
#   resumen-sin-job    resumen cuyo orden no nombra el ultimo job
# La prueba en pre (TIPO: prueba-pre; la clave de los regex es prueba-pre:<job>) escribe un caso por cada tres
# hechos regla o error del prompt, mas un elemento en preparar y otro en comprobar:
#   (vacio)                  guion correcto: todos los hechos regla y error salen en algun caso
#   prueba-ref-mala          el primer caso lleva una referencia que no existe (siempre)
#   prueba-falta-una-vez     deja sin caso el ultimo hecho regla o error, solo en el primer intento
#   prueba-falta-siempre     deja sin caso el ultimo hecho regla o error, en todos los intentos
#   prueba-clase-en-texto    el titulo del primer caso nombra la clase CargaReader (solo en el primer intento)
#   prueba-de-mas            41 casos (siempre)
# La comparacion con el migrado (TIPO: comparar-pieza; la clave de los regex es comparar-pieza:<clase del original>) cita las
# lineas de la primera ruta MIGRADO del prompt, una por dato, y dice igual en todos:
#   comparar-distinto        el primer dato sale distinto, con nota
#   comparar-sin-nota        el primer dato sale distinto, sin nota
#   comparar-inventada       todas las citas inventadas
#   comparar-falta-dato      deja el ultimo dato sin elemento
#   comparar-fichero-ajeno   cita un fichero que no se le dio
# Un dato de la ficha de clase que nombra una clase (para las paginas de negocio; clave: el nombre de la clase):
#   dato-con-clase           ficha correcta, pero el texto de su primer dato dice 'Delega el envio de la remesa en la
#                            clase CargaValidator.' (con su cita buena)
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
# ---- Examen de modelos (bloque 9 del preflight): llamadas con id pf-exa-<k>-<L1 | L2-<n> | E1 | E2> ----
# Todo lo del examen vive en este bloque. La clave de cada llamada es 'modelo:esfuerzo:tarea' (por ejemplo
# 'gpt-6-luna:max:L2-1'). Los guiones de RESCATE_FALSO ('nombre:regex', separados por ';') valen para las llamadas
# cuya clave cumple su regex, y valen todos los que encajan:
#   exa-no-existe       sale con 1 diciendo que el modelo no esta disponible, sin escribir nada
#   exa-sin-esfuerzo    sale con 1 diciendo que ese esfuerzo no vale
#   exa-error-privado   sale con 1 y escribe el texto de la variable RESCATE_ERROR_TEXTO
#   exa-espera-<n>      espera n segundos antes de hacer nada
#   exa-ficha-mala      L1 y L2: JSON cortado
#   exa-ficha-secreta   L1 y L2: todas las citas inventadas, con un texto con comillas simples
#   exa-e1-nada         E1 no cambia nada
#   exa-e1-no-compila   E1 arregla, pero deja un NO_COMPILA en el codigo
#   exa-e1-test-falla   E1 arregla, pero deja un TEST_FALLA en el codigo (el Maven de mentira falla en 'test')
#   exa-e1-toca-test    E1 arregla y ademas cambia un test
#   exa-e1-toca-pom     E1 arregla y ademas cambia el pom.xml
#   exa-e2-nada         E2 no cambia nada
#   exa-e2-codigo       E2 pone el Javadoc y cambia una linea de codigo
#   exa-e2-falta        E2 pone el Javadoc a todo menos a un metodo
# Sin guion: L1 y L2 escriben una ficha con los datos de RESCATE_EXAMEN_DATOS ('regex=lista' separados por ';', gana la
# primera cuya regex cumple la clave; la lista es de 'linea[:tipo]' separados por comas, el tipo por defecto es regla y
# una linea negativa lleva una cita inventada; sin regla, las dos primeras lineas del rango que acaban en ';');
# E1 arregla bien y E2 pone el Javadoc.
# Si la llamada trae --usage-output-file=<ruta>, al acabar bien escribe ahi un JSON de uso como el del Copilot real, con
# los valores de RESCATE_EXAMEN_USO ('regex=nanoAiu,entrada,salida' separados por ';', gana la primera cuya regex cumple
# la clave; 'regex=-' no escribe nada y 'regex=basura' escribe un fichero que no es JSON). Sin regla: 1000000000,1000,100.
# Cada llamada deja .rescate/falso/<id>-<pid>.txt (y su copia en RESCATE_LLAMADAS) con id, pid, flags, uso (si lleva la
# bandera de uso), guion, clave, lineas (el rango de una lectura) e inicio y fin.
if ($texto -match '\.rescate/tareas/(pf-exa-[^/\s]+?)\.prompt\.md') {
  $idE = $Matches[1]
  $raizE = (Get-Location).Path
  $modeloE = ''; $esfuerzoE = ''; $usoE = ''
  foreach ($a in $args) {
    if ("$a" -match '^--model=(.*)$') { $modeloE = $Matches[1] }
    elseif ("$a" -match '^--effort=(.*)$') { $esfuerzoE = $Matches[1] }
    elseif ("$a" -match '^--usage-output-file=(.*)$') { $usoE = $Matches[1] }
  }
  $tareaE = $idE -replace '^pf-exa-\d+-', ''
  $claveE = "${modeloE}:${esfuerzoE}:${tareaE}"
  $gsE = @()
  foreach ($g in ("$env:RESCATE_FALSO" -split ';')) {
    $nE, $reE = ($g -split ':', 2)
    if (-not $reE) { $reE = '.' }
    if ($nE -like 'exa-*' -and $claveE -match $reE) { $gsE += $nE }
  }
  $promptE = [System.IO.File]::ReadAllText((Join-Path (Join-Path (Join-Path $raizE '.rescate') 'tareas') ($idE + '.prompt.md')))
  $rangoE = [regex]::Match($promptE, '(?m)^LINEAS: (\d+)-(\d+)\s*$')
  $lineasE = ''
  if ($rangoE.Success) { $lineasE = $rangoE.Groups[1].Value + '-' + $rangoE.Groups[2].Value }
  $dirE = Join-Path (Join-Path $raizE '.rescate') 'falso'
  [void](New-Item -ItemType Directory -Path $dirE -Force)
  $regE = Join-Path $dirE ($idE + '-' + $PID + '.txt')
  $flagsE = (@($args | Where-Object { "$_" -match '^--(model=|effort=|add-dir=|available-tools=|no-custom-instructions$)' }) -join ' ')
  $conUsoE = 'no'
  if ($usoE) { $conUsoE = 'si' }
  [System.IO.File]::WriteAllLines($regE, [string[]]@("id=$idE", "pid=$PID", "flags=$flagsE", "uso=$conUsoE", ('guion=' + ($gsE -join ',')), "clave=$claveE", "lineas=$lineasE", ('inicio=' + [DateTime]::UtcNow.Ticks)))
  $copiarE = {
    if ($env:RESCATE_LLAMADAS) {
      [void](New-Item -ItemType Directory -Path $env:RESCATE_LLAMADAS -Force)
      Copy-Item -LiteralPath $regE -Destination (Join-Path $env:RESCATE_LLAMADAS (Split-Path $regE -Leaf)) -Force
    }
  }
  & $copiarE
  $cierraE = {
    [System.IO.File]::AppendAllText($regE, ('fin=' + [DateTime]::UtcNow.Ticks + "`n"))
    & $copiarE
  }
  foreach ($g in $gsE) { if ($g -match '^exa-espera-(\d+)$') { Start-Sleep -Seconds ([int]$Matches[1]) } }
  if ($gsE -contains 'exa-no-existe') { "Error: model '$modeloE' is not available"; & $cierraE; exit 1 }
  if ($gsE -contains 'exa-sin-esfuerzo') { "error: invalid value '$esfuerzoE' for '--effort <level>'"; & $cierraE; exit 1 }
  if ($gsE -contains 'exa-error-privado') { "$env:RESCATE_ERROR_TEXTO"; & $cierraE; exit 1 }
  function Ruta-E([string]$Rel) { return [System.IO.Path]::Combine([string[]](@($raizE) + $Rel.Split('/'))) }
  function Cambia-E([string]$Rel, [string[]]$Pares) {
    $t = [System.IO.File]::ReadAllText((Ruta-E $Rel))
    for ($i = 0; $i -lt $Pares.Count; $i += 2) {
      if (-not $t.Contains($Pares[$i])) { 'el falso no reconoce el proyecto'; exit 1 }
      $t = $t.Replace($Pares[$i], $Pares[$i + 1])
    }
    [System.IO.File]::WriteAllText((Ruta-E $Rel), $t)
  }
  function Anade-E([string]$Rel, [string]$Texto) { [System.IO.File]::AppendAllText((Ruta-E $Rel), $Texto) }
  $factura = 'src/main/java/com/ejemplo/facturas/Factura.java'
  if ($tareaE -match '^L') {
    $leerE = ([regex]::Match($promptE, '(?m)^LEER: (.+?)\s*$')).Groups[1].Value
    $salidaE = ([regex]::Match($promptE, '(?m)^ESCRIBIR: (.+?)\s*$')).Groups[1].Value
    $fuenteE = [System.IO.File]::ReadAllLines($leerE)
    $desdeE = [int]$rangoE.Groups[1].Value; $hastaE = [int]$rangoE.Groups[2].Value
    $pedidosE = @()
    $listaE = ''
    foreach ($r in ("$env:RESCATE_EXAMEN_DATOS" -split ';')) {
      $reD, $valD = ($r -split '=', 2)
      if ($reD -and $valD -and $claveE -match $reD) { $listaE = $valD; break }
    }
    if ($listaE) { $pedidosE = @($listaE -split ',') }
    else { $pedidosE = @(for ($n = $desdeE; $n -le [Math]::Min($hastaE, $fuenteE.Count); $n++) { if ($fuenteE[$n - 1] -match ';\s*$' -and $fuenteE[$n - 1] -notmatch '^\s*(package|import)\b') { "$n" } }) | Select-Object -First 2
    }
    $datosE = @()
    foreach ($p in $pedidosE) {
      $lE, $tE = ("$p" -split ':', 2)
      $nE = [int]$lE
      $inventada = ($nE -lt 0 -or $gsE -contains 'exa-ficha-secreta')
      $nE = [Math]::Abs($nE)
      if ($nE -lt $desdeE -or $nE -gt $hastaE) { continue }
      if (-not $tE) { $tE = 'regla' }
      $citaE = $fuenteE[$nE - 1].Trim()
      if ($inventada) { $citaE = "SECRETO-ZORBA 'cita $nE' no sale en el fichero" }
      $datosE += [ordered]@{ tipo = $tE; texto = "Linea $nE"; linea = $nE; cita = $citaE }
    }
    $claseE = [System.IO.Path]::GetFileNameWithoutExtension($leerE)
    $fichaE = [ordered]@{ fichero = (Split-Path $leerE -Leaf); clase = $claseE; papel = 'otro'; queHace = "Ficha de prueba de $claseE."; datos = $datosE }
    $jsonE = ConvertTo-Json -InputObject $fichaE -Depth 6
    if ($gsE -contains 'exa-ficha-mala') { $jsonE = $jsonE.Substring(0, [int]($jsonE.Length / 2)) }
    [System.IO.File]::WriteAllText((Ruta-E $salidaE), $jsonE)
  }
  elseif ($tareaE -eq 'E1' -and $gsE -notcontains 'exa-e1-nada') {
    Cambia-E $factura @('return Tarifa.aplicar(base);', 'return Tarifa.aplicar(base, IVA, java.math.RoundingMode.HALF_UP);',
      'Date vence = Calendario.vencimiento(emision, DIAS_DE_PAGO);', 'LocalDate vence = Calendario.vencimiento(emision, DIAS_DE_PAGO);',
      'return new SimpleDateFormat("dd/MM/yyyy").format(vence);', 'return vence.format(java.time.format.DateTimeFormatter.ofPattern("dd/MM/yyyy"));')
    if ($gsE -contains 'exa-e1-no-compila') { Anade-E $factura "`n// NO_COMPILA`n" }
    if ($gsE -contains 'exa-e1-test-falla') { Anade-E $factura "`n// TEST_FALLA`n" }
    if ($gsE -contains 'exa-e1-toca-test') { Anade-E 'src/test/java/com/ejemplo/facturas/FacturaTest.java' "`n// tocado`n" }
    if ($gsE -contains 'exa-e1-toca-pom') { Anade-E 'pom.xml' "`n<!-- tocado -->`n" }
  }
  elseif ($tareaE -eq 'E2' -and $gsE -notcontains 'exa-e2-nada') {
    $almacen = 'src/main/java/com/ejemplo/inventario/Almacen.java'
    $lineasJ = [System.IO.File]::ReadAllLines((Ruta-E $almacen))
    $salidaJ = @()
    foreach ($l in $lineasJ) {
      $sangria = [regex]::Match($l, '^\s*').Value
      if ($l -match '^\s*public ' -and -not ($gsE -contains 'exa-e2-falta' -and $l -match 'public int total\(')) { $salidaJ += ($sangria + '/** Documentado. */') }
      $salidaJ += $l
    }
    [System.IO.File]::WriteAllLines((Ruta-E $almacen), [string[]]$salidaJ)
    if ($gsE -contains 'exa-e2-codigo') { Cambia-E $almacen @('MAXIMO_POR_REFERENCIA = 500;', 'MAXIMO_POR_REFERENCIA = 501;') }
  }
  if ($usoE) {
    $reglaE = '1000000000,1000,100'
    foreach ($r in ("$env:RESCATE_EXAMEN_USO" -split ';')) {
      $reU, $valU = ($r -split '=', 2)
      if ($reU -and $valU -and $claveE -match $reU) { $reglaE = $valU; break }
    }
    if ($reglaE -eq 'basura') { [System.IO.File]::WriteAllText($usoE, 'esto no es json {') }
    elseif ($reglaE -ne '-') {
      $nanoE, $entE, $salE = ($reglaE -split ',')
      if (-not $modeloE) { $modeloE = 'modelo' }
      $usoJson = [ordered]@{
        totalPremiumRequestCost = 0; totalUserRequests = 1; totalNanoAiu = [long]$nanoE; totalApiDurationMs = 1234
        sessionStartTime = '2026-11-17T10:00:00Z'; codeChanges = [ordered]@{}
        modelMetrics = [ordered]@{ $modeloE = [ordered]@{ usage = [ordered]@{ inputTokens = [long]$entE; outputTokens = [long]$salE; cacheReadTokens = 7; reasoningTokens = 3 } } }
        agentMetrics = [ordered]@{}; providerModelMetrics = @(); lastCallInputTokens = 5; lastCallOutputTokens = 6
      }
      [System.IO.File]::WriteAllText($usoE, (ConvertTo-Json -InputObject $usoJson -Depth 8))
    }
  }
  & $cierraE
  'hecho'
  exit 0
}
if ($texto -match '\.rescate/tareas/\S+\.prompt\.md') {
  $raiz = (Get-Location).Path
  $prompt = [System.IO.File]::ReadAllText((Join-Path (Join-Path (Join-Path $raiz '.rescate') 'tareas') (Split-Path $Matches[0] -Leaf)))
  $leer = ([regex]::Match($prompt, '(?m)^LEER: (.+?)\s*$')).Groups[1].Value
  $salida = ([regex]::Match($prompt, '(?m)^ESCRIBIR: (.+?)\s*$')).Groups[1].Value
  $rango = [regex]::Match($prompt, '(?m)^LINEAS: (\d+)-(\d+)\s*$')
  $id = [System.IO.Path]::GetFileName($salida) -replace '\.json$', ''
  $correccion = ($prompt -match '## CORRECCI')
  $efecto = (@($args | Where-Object { "$_" -match '^--(model=|effort=|add-dir=|available-tools=|no-custom-instructions$)' }) -join ' ')
  $tipo = 'ficha-clase'
  if ($prompt -match '(?m)^TIPO: (\S+)') { $tipo = $Matches[1] }
  $job = ([regex]::Match($prompt, '(?m)^JOB: (.+?)\s*$')).Groups[1].Value
  $clase = [System.IO.Path]::GetFileNameWithoutExtension($leer)
  if ($tipo -eq 'ficha-job') { $clase = $job }
  if ($tipo -eq 'prueba-pre') { $clase = $job }
  if ($tipo -eq 'resumen') { $clase = '' }
  if ($tipo -ne 'ficha-clase') { $clase = $tipo + ':' + $clase }
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

  $json = ''
  if ($tipo -eq 'definicion-job') {
    $lineas = [System.IO.File]::ReadAllLines($leer)
    $nombres = @(([regex]::Match($prompt, '(?m)^JOBS: (.+?)\s*$')).Groups[1].Value -split ',\s*' | Where-Object { $_ })
    $cerradas = @(([regex]::Match($prompt, '(?m)^CLASES: (.+?)\s*$')).Groups[1].Value -split ',\s*' | Where-Object { $_ })
    function Linea-De([string]$Nombre) {
      for ($n = 1; $n -le $lineas.Count; $n++) { if ($lineas[$n - 1].Contains('get("' + $Nombre + '")')) { return $n } }
      return 1
    }
    function Cita-De([int]$N) { $c = $lineas[$N - 1].Trim(); return $c.Substring(0, [Math]::Min(120, $c.Length)) }
    $jobs = @()
    foreach ($nj in $nombres) { $jobs += [ordered]@{ job = $nj; linea = (Linea-De $nj); cita = (Cita-De (Linea-De $nj)); pasos = @() } }
    for ($n = 1; $n -le $lineas.Count; $n++) {
      if (-not ($lineas[$n - 1] -match 'stepBuilder\w*\.get\("(\w+)"\)')) { continue }
      $paso = $Matches[1]
      $dueno = $jobs[0]
      foreach ($j in $jobs) { if ($j.linea -le $n -and $j.linea -ge $dueno.linea) { $dueno = $j } }
      $prefijo = $paso -replace 'Step$', ''
      $cl = @($cerradas | Where-Object { $_ -like ($prefijo + '*') })
      if ($guion -eq 'job-clase-fuera') { $cl += 'NoExiste' }
      $dueno.pasos += [ordered]@{ paso = $paso; linea = $n; cita = (Cita-De $n); clases = $cl }
    }
    $json = ConvertTo-Json -InputObject ([ordered]@{ jobs = $jobs }) -Depth 8
  }
  elseif ($tipo -eq 'ficha-job') {
    $refs = @([regex]::Matches($prompt, '(?m)^(clase-[0-9a-f]{8}#\d+) \[') | ForEach-Object { $_.Groups[1].Value })
    $primera = ([regex]::Match($prompt, '(?m)^### (\w+) \(')).Groups[1].Value
    $malo = 'clase-00000000#9'
    $r1 = $refs[0]; $r2 = $refs[$refs.Count - 1]
    if ($guion -eq 'job-ref-mixta') { $r2 = $malo }
    if ($guion -eq 'job-ref-mala') { $r1 = $malo; $r2 = $malo }
    $titulo = "Titulo de $job"
    if ($guion -eq 'job-clase-en-texto' -and -not $correccion) { $titulo = "Carga con $primera" }
    $pasos = @([ordered]@{ titulo = 'Primer paso'; texto = 'Hace lo primero.'; refs = @($r1) }, [ordered]@{ titulo = 'Segundo paso'; texto = 'Hace lo segundo.'; refs = @($r2) })
    $json = ConvertTo-Json -InputObject ([ordered]@{ job = $job; titulo = $titulo; paraQue = "Sirve para probar $job."; pasos = $pasos; dudas = @() }) -Depth 8
  }
  elseif ($tipo -eq 'prueba-pre') {
    $hechos = @([regex]::Matches($prompt, '(?m)^(clase-[0-9a-f]{8}#\d+) \[([\w\-]+)\] ') | ForEach-Object { [pscustomobject]@{ ref = $_.Groups[1].Value; tipo = $_.Groups[2].Value } })
    $cubrir = @($hechos | Where-Object { $_.tipo -eq 'regla' -or $_.tipo -eq 'error' } | ForEach-Object { $_.ref })
    if ($guion -eq 'prueba-falta-siempre' -or ($guion -eq 'prueba-falta-una-vez' -and -not $correccion)) { $cubrir = @($cubrir | Select-Object -First ($cubrir.Count - 1)) }
    $casos = @()
    for ($n = 0; $n -lt $cubrir.Count; $n += 3) {
      $k = $casos.Count + 1
      $casos += [ordered]@{ titulo = "Caso $k de $job"; entrada = "Lo que se mete en el caso $k."; esperado = "Lo que tiene que pasar en el caso $k."; refs = @($cubrir[$n..([Math]::Min($n + 2, $cubrir.Count - 1))]) }
    }
    if ($guion -eq 'prueba-de-mas') { $casos = @(1..41 | ForEach-Object { [ordered]@{ titulo = "Caso $_"; entrada = 'Algo.'; esperado = 'Otra cosa.'; refs = @($hechos[0].ref) } }) }
    if ($guion -eq 'prueba-ref-mala' -and $casos.Count -gt 0) { $casos[0].refs = @($casos[0].refs) + 'clase-00000000#9' }
    if ($guion -eq 'prueba-clase-en-texto' -and -not $correccion -and $casos.Count -gt 0) { $casos[0].titulo = 'Carga con CargaReader' }
    $json = ConvertTo-Json -InputObject ([ordered]@{
        job = $job
        preparar = @([ordered]@{ texto = 'Deja listo lo que el job necesita.'; refs = @($hechos[0].ref) })
        casos = $casos
        comprobar = @([ordered]@{ texto = 'Mira lo que el job deja al acabar.'; refs = @($hechos[$hechos.Count - 1].ref) })
      }) -Depth 8
  }
  elseif ($tipo -eq 'resumen') {
    $orden = @([regex]::Matches($prompt, '(?m)^JOB: (.+?)\s*$') | ForEach-Object { [ordered]@{ job = $_.Groups[1].Value; motivo = ('Va en su sitio: ' + $_.Groups[1].Value + '.') } })
    if ($guion -eq 'resumen-sin-job' -and $orden.Count -gt 0) { $orden = @($orden | Select-Object -First ($orden.Count - 1)) }
    $json = ConvertTo-Json -InputObject ([ordered]@{ resumen = 'El batch hace cosas para quien las necesita.'; orden = $orden; glosario = @([ordered]@{ termino = 'remesa'; definicion = 'Un grupo de recibos.' }) }) -Depth 8
  }
  elseif ($tipo -eq 'comparar-pieza') {
    $nDatos = @([regex]::Matches($prompt, '(?m)^\d+\. \[')).Count
    $migrados = @([regex]::Matches($prompt, '(?m)^MIGRADO: (.+?)\s*$') | ForEach-Object { $_.Groups[1].Value })
    $rutaM = $raiz
    foreach ($s in $migrados[0].Split('/')) { $rutaM = Join-Path $rutaM $s }
    $lineasM = [System.IO.File]::ReadAllLines($rutaM)
    $realesM = @(for ($n = 1; $n -le $lineasM.Count; $n++) {
        if ($lineasM[$n - 1] -match ';\s*$' -and $lineasM[$n - 1] -notmatch '^\s*(package|import)\b') { $n }
      })
    $comp = @()
    for ($k = 0; $k -lt $nDatos; $k++) {
      $n = $realesM[$k % $realesM.Count]
      $comp += [ordered]@{ dato = $k; estado = 'igual'; fichero = $migrados[0]; linea = $n; cita = $lineasM[$n - 1].Trim(); nota = '' }
    }
    # los guiones de comparar se aplican sobre la lista ya montada
    if ($guion -eq 'comparar-distinto' -or $guion -eq 'comparar-sin-nota') {
      $comp[0].estado = 'distinto'
      if ($guion -eq 'comparar-distinto') { $comp[0].nota = 'El migrado usa una constante en vez del literal.' }
    }
    if ($guion -eq 'comparar-inventada') { foreach ($c in $comp) { $c.cita = "esta cita no sale en el fichero $($c.dato)" } }
    if ($guion -eq 'comparar-falta-dato') { $comp = @($comp | Select-Object -First ($comp.Count - 1)) }
    if ($guion -eq 'comparar-fichero-ajeno') { foreach ($c in $comp) { $c.fichero = 'src/main/java/com/acme/life/NoMeHanDado.java' } }
    $json = ConvertTo-Json -InputObject ([ordered]@{ comparacion = $comp }) -Depth 6
  }
  else {
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
    if ($guion -eq 'tipos-variados') {
      $tipos = @('entrada-fichero', 'salida-fichero', 'sftp', 'error', 'tabla-lee', 'regla', 'parametro', 'tabla-escribe', 'externo', 'config')
      $datos = @()
      foreach ($n in $reales) { $d = Nuevo-Dato $n $lineas[$n - 1].Trim(); $d.tipo = $tipos[$datos.Count % $tipos.Count]; $datos += $d }
    }
    if ($guion -eq 'dato-con-clase') { $datos[0].texto = 'Delega el envio de la remesa en la clase CargaValidator.' }
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
  }
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
if ($guion -eq 'lento') { Start-Sleep -Seconds 3 }

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
  if ($l -match '^## (Hallazgos|Ficheros del lote)') { $dentro = $true; continue }
  if ($dentro -and $l -match '^## ') { break }
  if ($dentro -and $l -match '^- (\S+?)(:\d+)?( - |$)') { $fichs += $Matches[1] }
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
    # mueve cada clase a application/usecases (o a infrastructure/util) y le cambia el package
    $destino = 'application/usecases'
    if ($guion -eq 'mueve-a-infrastructure') { $destino = 'infrastructure/util' }
    foreach ($f in $fichs) {
      if (-not $f.StartsWith($base) -or -not $f.EndsWith('.java') -or -not (Test-Path -LiteralPath (Get-Ruta $f))) { continue }
      $nombre = $f.Split('/')[-1]
      $texto = (Leer $f) -replace '(?m)^package [^;]*;', ('package com.acme.life.' + $destino.Replace('/', '.') + ';')
      Remove-Item -LiteralPath (Get-Ruta $f) -Force
      Escribir ($base + $destino + '/' + $nombre) $texto
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
  'sonar' {
    $dentroS = $false
    $dejadas = @()
    foreach ($l in ($prompt -split "`r?`n")) {
      if ($l -match '^## (Hallazgos|Ficheros del lote)') { $dentroS = $true; continue }
      if ($dentroS -and $l -match '^## ') { break }
      if (-not ($dentroS -and $l -match '^- (\S+?):(\d+) - ')) { continue }
      $f = $Matches[1]; $n = [int]$Matches[2]
      if ($guion -eq 'sonar-sin-tocar') { Escribir $f ((Leer $f) + "`n// otro cambio: la linea marcada no se toca`n"); continue }
      if ($guion -eq 'sonar-atasca' -and $l -match 'ATASCA') { continue }   # no toca nada de esa incidencia: el lote no baja
      if ($guion -eq 'sonar-deja' -and $l -match 'DEJAME') { $dejadas += "${f}:${n} | cambiaria la API publica"; continue }
      $t = @((Leer $f) -split "`r?`n")
      $marca = ' // corregido'
      if ($guion -eq 'sonar-nosonar') { $marca = ' // NOSONAR' }
      $t[$n - 1] = $t[$n - 1].TrimEnd() + $marca
      $texto = $t -join "`n"
      if ($guion -eq 'sonar-suppress') { $texto += "`n@SuppressWarnings(`"all`")`nclass Otra {`n}`n" }
      Escribir $f $texto
    }
    if ($dejadas.Count -gt 0) {   # las que deja, con su motivo, y una linea que no casa con ninguna incidencia
      Escribir '.rescate/sonar-sin-arreglar.txt' ((($dejadas + @('src/main/java/com/acme/plantillabatch/NoExiste.java:99 | esta no es de ningun lote')) -join "`n") + "`n")
    }
    if ($guion -eq 'sonar-disabled' -or $guion -eq 'sonar-borra-test') {
      $test = @(Get-ChildItem -LiteralPath (Get-Ruta 'src/test') -Recurse -File -Filter '*.java')[0]
      if ($guion -eq 'sonar-disabled') { [System.IO.File]::WriteAllText($test.FullName, ([System.IO.File]::ReadAllText($test.FullName) -replace '@Test', "@Disabled`n    @Test")) }
      else { Remove-Item -LiteralPath $test.FullName -Force }
    }
  }
}
'hecho'
exit 0
