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
#   reflexion-formato  la reflexion trae las cuatro secciones con otros titulos: ###, numerado, en negrita, con signos de
#                      pregunta y con acentos
#   reflexion-sin-titulos  la reflexion es un parrafo sin ningun titulo
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
#   muchos-ficheros    un lote que lleva LeerFichero.java: sin CORRECCION crea 10 clases mas que abren ficheros (LeerOtro1..10:
#                      el paso 'ficheros' pasa de 3 hallazgos a 13) y con CORRECCION no cambia nada; los demas lotes, como siempre
#   falla-copilot      un lote sale con 1 tras escribir nueve lineas (dos de ellas vacias o en blanco) y sin cambiar nada
#   primer-lote-falla  el primer lote de la pasada no cambia nada; los demas, como siempre
#   falla-una-vez      el primer lote de la pasada sale con 1 sin cambiar nada (escribe SALIDA-UNICA); los demas, como siempre
#   nada-hasta-reflexion  un lote no cambia nada mientras su prompt no lleve una reflexion (REFLEXION-MARCA)
#   fallos-distintos   un lote sin CORRECCION no cambia nada; con la CORRECCION 'No has cambiado ningun fichero' mueve LeerFichero a
#                      infrastructure/util (el paso 'estructura' no baja); con cualquier otra la deja donde estaba y arregla como siempre
#   mejor-peor         un lote con Suelta.java: el 1.o deja src/main/resources/mejor.txt (los hallazgos no bajan); el 2.o deja
#                      peor.txt y un test que falla (peor que el 1.o); el 3.o apunta en .rescate/arbol-visto.log si ve mejor.txt,
#                      peor.txt y el test, y arregla como siempre
#   parcial-roto       el primer lote (Suelta.java y algo mas) mueve Suelta a application/usecases y deja un test que falla:
#                      los hallazgos bajan y compila, pero no pasa. Los demas lotes apuntan en .rescate/arbol-visto.log si
#                      Suelta ya esta movida, quitan ese test si el prompt lleva CORRECCION y arreglan como siempre
#   comprueba          tras arreglar, un lote ejecuta la orden del modo comprobar que lleva su prompt (la linea 'Ejecuta: ... y corrige lo
#                      que liste') y apunta en .rescate/comprobar-visto.log 'rc=<codigo> rescate-igual=<si no ha cambiado nada en
#                      .rescate>' y su salida, cada linea con '> '
#   plan-paquete-nuevo  la revision previa nombra en 'Piezas comunes' la clase com.acme.life.infrastructure.util.LeerFichero (un
#                      paquete que la plantilla no tiene); con CORRECCION en su prompt, com.acme.life.application.ports.output.LeerFichero
#   plan-paquete-nuevo-siempre  como plan-paquete-nuevo, con o sin CORRECCION
#   plan-paquete-bueno  la revision previa nombra en 'Piezas comunes' un paquete que la plantilla tiene y, con ruta, la carpeta de otro
#                      (application/ports: no tiene clases, pero cuelgan de ella paquetes de la plantilla)
#   plan-destino-nuevo  como plan-paquete-nuevo, pero en el 'destino:' de las lineas de 'Ficheros' (infrastructure/util)
#   plan-ilegible       'Piezas comunes' y 'destino:' sin ningun nombre de paquete que se pueda leer
#   ve-marca           cada lote deja en .rescate/marca-vista.log lo que decia .rescate/intento-en-curso.json al llegar
#                      ('sin marca' si no estaba)
$todos = $args
$guiones = @("$env:RESCATE_FALSO" -split ';' | Where-Object { $_ })
$flags = (@($args | Where-Object { "$_" -match '^--(model|effort)=' }) -join ' ')
$raiz = (Get-Location).Path
$rescate = Join-Path $raiz '.rescate'

# ---- migracion.ps1 (tests/probar-migracion.ps1): sin .rescate/prompt.md. TIPO: caso-pre, ficha-sh y comparar-sh los escribe este falso (un caso por
# regla sin caso; la ficha de un script de shell; su comparacion con el migrado); lo demas es de copilot.ps1. La clave de los regex de RESCATE_FALSO es
# caso-pre:<job>, ficha-sh:<ruta del script> o comparar-sh:<ruta del script>. Cada llamada deja .rescate/falso/<tarea>-<pid>.txt como las de
# copilot.ps1 (id, flags, correccion, guion, inicio, fin). ----
#   (vacio)               el caso bueno: titulo propio, entrada, esperado y la referencia de la regla
#   caso-sin-ref          el caso lleva refs de otros hechos, no la de la regla (siempre)
#   caso-sin-ref-una-vez  como caso-sin-ref, solo en el primer intento
#   caso-clase-en-texto   el titulo nombra la clase CargaReader (solo en el primer intento)
#   caso-titulo-repetido  el titulo es el del primer caso que ya tenia el guion (siempre)
#   (vacio, ficha-sh)     la ficha buena: un parametro por cada opcion del inventario, y una accion o una salida por cada linea de OBLIGATORIAS
#   sh-cita-inventada     todas las citas de la ficha son inventadas (siempre)
#   sh-faltan-una-vez     la ficha deja sin explicar la ultima linea de OBLIGATORIAS, solo en el primer intento
#   sh-faltan-siempre     la ficha deja sin explicar la ultima linea de OBLIGATORIAS, en todos los intentos
#   (vacio, comparar-sh)  cada accion igual, citando las primeras lineas con texto de la primera ruta MIGRADO
#   comparar-sh-inventada todas las citas de la comparacion son inventadas (siempre)
#   comparar-sh-distinto  la primera accion sale distinta, con nota
if (-not (Test-Path -LiteralPath (Join-Path $rescate 'prompt.md'))) {
  $textoM = ''
  for ($i = 0; $i -lt $args.Count - 1; $i++) { if ("$($args[$i])" -eq '-p') { $textoM = "$($args[$i + 1])" } }
  $rutaM = [regex]::Match($textoM, '\.rescate/tareas/\S+\.prompt\.md')
  $promptM = ''
  if ($rutaM.Success) { $promptM = [System.IO.File]::ReadAllText((Join-Path (Join-Path $rescate 'tareas') (Split-Path $rutaM.Value -Leaf))) }
  $tipoM = ([regex]::Match($promptM, '(?m)^TIPO: (\S+)\s*$')).Groups[1].Value
  if (@('caso-pre', 'ficha-sh', 'comparar-sh') -notcontains $tipoM) {
    & (Join-Path $PSScriptRoot 'copilot.ps1') @todos
    exit $LASTEXITCODE
  }
  $salidaM = ([regex]::Match($promptM, '(?m)^ESCRIBIR: (.+?)\s*$')).Groups[1].Value
  $idM = [System.IO.Path]::GetFileName($salidaM) -replace '\.json$', ''
  $jobM = ([regex]::Match($promptM, '(?m)^JOB: (.+?)\s*$')).Groups[1].Value
  $reglaM = ([regex]::Match($promptM, '(?m)^REGLA: (\S+)\s*$')).Groups[1].Value
  $scriptM = ([regex]::Match($promptM, '(?m)^SCRIPT: (.+?)\s*$')).Groups[1].Value
  $claveM = $tipoM + ':' + $jobM
  if ($tipoM -ne 'caso-pre') { $claveM = $tipoM + ':' + $scriptM }
  $correccionM = ($promptM -match '## CORRECCI')
  $guionM = ''
  foreach ($g in $guiones) {
    $nombre, $solo = ($g -split ':', 2)
    if (-not $solo) { $solo = '.' }
    if ($nombre -and -not $guionM -and $claveM -match $solo) { $guionM = $nombre }
  }
  $dirM = Join-Path $rescate 'falso'
  [void](New-Item -ItemType Directory -Path $dirM -Force)
  $regM = Join-Path $dirM ($idM + '-' + $PID + '.txt')
  [System.IO.File]::WriteAllLines($regM, [string[]]@("id=$idM", "pid=$PID", "flags=$flags", "correccion=$correccionM", "guion=$guionM", ('inicio=' + [DateTime]::UtcNow.Ticks)))
  if ($tipoM -eq 'caso-pre') {
    $hechosM = @([regex]::Matches($promptM, '(?m)^(clase-[0-9a-f]{8}#\d+) \[') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
    $otros = @($hechosM | Where-Object { $_ -cne $reglaM })
    $refsM = @($reglaM)
    if ($guionM -eq 'caso-sin-ref' -or ($guionM -eq 'caso-sin-ref-una-vez' -and -not $correccionM)) { $refsM = @($otros | Select-Object -First 1) }
    $tituloM = "Caso de la regla $reglaM de $jobM"
    if ($guionM -eq 'caso-clase-en-texto' -and -not $correccionM) { $tituloM = 'Carga con CargaReader' }
    if ($guionM -eq 'caso-titulo-repetido') { $tituloM = ([regex]::Match($promptM, '(?m)^Casos que ya hay:\s*\r?\n- (.+?)\s*$')).Groups[1].Value }
    $jsonM = ConvertTo-Json -InputObject ([ordered]@{ titulo = $tituloM; entrada = "Lo que se mete para la regla $reglaM."; esperado = "Lo que tiene que pasar con la regla $reglaM."; refs = $refsM }) -Depth 4
  }
  elseif ($tipoM -eq 'ficha-sh') {
    # el texto de cada linea del script, el inventario de cada linea y las lineas obligatorias, como los trae el prompt
    $textoLin = @{}
    foreach ($m in [regex]::Matches($promptM, '(?m)^\s*(\d+)\| (.*?)\r?$')) { $textoLin[[int]$m.Groups[1].Value] = $m.Groups[2].Value.Trim() }
    $invM = @{}
    foreach ($m in [regex]::Matches($promptM, '(?m)^(\d+) \[(\w+)\] (.*?)\r?$')) {
      $n = [int]$m.Groups[1].Value
      if (-not $invM.ContainsKey($n)) { $invM[$n] = @() }
      $invM[$n] += [pscustomobject]@{ Tipo = $m.Groups[2].Value; Det = $m.Groups[3].Value.Trim() }
    }
    $oblM = @(([regex]::Match($promptM, '(?m)^OBLIGATORIAS: (.+?)\s*$')).Groups[1].Value -split ',\s*' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
    if ($oblM.Count -gt 0 -and ($guionM -eq 'sh-faltan-siempre' -or ($guionM -eq 'sh-faltan-una-vez' -and -not $correccionM))) { $oblM = @($oblM | Select-Object -First ($oblM.Count - 1)) }
    $citaDe = { param([int]$N) $t = "$($textoLin[$N])"; if ($guionM -eq 'sh-cita-inventada') { return "esta cita no sale en el script $N" }; if ($t.Length -gt 100) { $t = $t.Substring(0, 100) }; return $t }
    $parM = @(); $accM = @(); $salM = @()
    foreach ($n in @($invM.Keys | Sort-Object)) {
      foreach ($i in $invM[$n]) {
        if ($i.Tipo -eq 'parametro' -and $i.Det -match '^-') { $parM += [ordered]@{ nombre = $i.Det; obligatorio = $false; valores = ''; formato = ''; linea = $n; cita = (& $citaDe $n) } }
      }
    }
    foreach ($n in $oblM) {
      $tipos = @($invM[$n] | ForEach-Object { $_.Tipo })
      if ($tipos -contains 'salida') {
        $cod = -1
        $dd = @($invM[$n] | Where-Object { $_.Tipo -eq 'salida' })[0].Det
        if ($dd -match '^\d+') { $cod = [int]$Matches[0] }
        $salM += [ordered]@{ codigo = $cod; cuando = "Cuando el script acaba por la linea $n."; linea = $n; cita = (& $citaDe $n) }
      }
      $otrosT = @($tipos | Where-Object { $_ -ne 'salida' })
      if ($otrosT.Count -gt 0 -or $tipos.Count -eq 0) {
        $que = 'otro'
        if ($otrosT.Count -gt 0) {
          switch ($otrosT[0]) { 'fichero' { $que = 'mueve' } 'envio' { $que = 'envia' } 'lanza' { $que = 'lanza' } 'cerrojo' { $que = 'comprueba' } 'perfil' { $que = 'elige-job' } 'job' { $que = 'elige-job' } }
        }
        $accM += [ordered]@{ cuando = 'antes'; condicion = ''; que = $que; detalle = "Hace lo que cuenta la linea $n del script."; linea = $n; cita = (& $citaDe $n) }
      }
    }
    $jsonM = ConvertTo-Json -InputObject ([ordered]@{ paraQue = 'Lanza el batch con los parametros que le dan.'; parametros = $parM; acciones = $accM; salidas = $salM }) -Depth 6
  }
  else {
    $nDatosM = @([regex]::Matches($promptM, '(?m)^\d+\. \[')).Count
    $migradosM = @([regex]::Matches($promptM, '(?m)^MIGRADO: (.+?)\s*$') | ForEach-Object { $_.Groups[1].Value })
    $rutaMig = $raiz
    foreach ($s in $migradosM[0].Split('/')) { $rutaMig = Join-Path $rutaMig $s }
    $lineasMig = [System.IO.File]::ReadAllLines($rutaMig)
    $utilesM = @(for ($n = 1; $n -le $lineasMig.Count; $n++) { if ($lineasMig[$n - 1].Trim()) { $n } })
    $compM = @()
    for ($k = 0; $k -lt $nDatosM; $k++) {
      $n = $utilesM[$k % $utilesM.Count]
      $citaM = $lineasMig[$n - 1].Trim()
      if ($citaM.Length -gt 100) { $citaM = $citaM.Substring(0, 100) }
      if ($guionM -eq 'comparar-sh-inventada') { $citaM = "esta cita no sale en el fichero $k" }
      $compM += [ordered]@{ dato = $k; estado = 'igual'; fichero = $migradosM[0]; linea = $n; cita = $citaM; nota = '' }
    }
    if ($guionM -eq 'comparar-sh-distinto' -and $compM.Count -gt 0) { $compM[0].estado = 'distinto'; $compM[0].nota = 'El migrado lo hace con otro valor.' }
    $jsonM = ConvertTo-Json -InputObject ([ordered]@{ comparacion = $compM }) -Depth 6
  }
  $rutaOut = $raiz
  foreach ($s in $salidaM.Split('/')) { if ($s) { $rutaOut = Join-Path $rutaOut $s } }
  [System.IO.File]::WriteAllText($rutaOut, $jsonM)
  [System.IO.File]::AppendAllText($regM, ('fin=' + [DateTime]::UtcNow.Ticks + "`n"))
  'hecho'
  exit 0
}
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
  if ($guiones -contains 'reflexion-sin-titulos') { $t = @("$marca No cambio nada y hay que mover las clases a otro paquete.") }
  if ($guiones -contains 'reflexion-formato') {
    $e = [char]0xE9; $o = [char]0xF3; $q = [char]0xBF
    $t = @("### 1. Qu$e se intent$o", "$marca mover las clases.", '', "## 2) Por qu$e no pas$o", 'No cambio nada.', '',
      "## **Qu$e hacer ahora**", 'Mover la clase a application/usecases.', '', "#### ${q}Qu$e no hacer?", 'No tocar el pom.xml.')
  }
  elseif ($guiones -notcontains 'reflexion-mala' -and $guiones -notcontains 'reflexion-sin-titulos') { $t += @('', '## Que hacer ahora', 'Mover la clase a application/usecases.', '', '## Que no hacer', 'No tocar el pom.xml.') }
  Escribir ".rescate/$($m.Groups[1].Value)" ($t -join "`n")
  'reflexion escrita'
  exit 0
}

if ($titulo -match 'revision previa') {
  Apunta 'plan' ''
  & (Join-Path $PSScriptRoot 'copilot.ps1') @todos
  $codigo = $LASTEXITCODE
  $guionesPlan = @('plan-paquete-nuevo', 'plan-paquete-nuevo-siempre', 'plan-paquete-bueno', 'plan-destino-nuevo', 'plan-ilegible')
  if (@($guiones | Where-Object { $guionesPlan -contains $_ }).Count -gt 0) {
    $ruta = @(Get-ChildItem -LiteralPath $rescate -Filter 'plan-*.md')[0].FullName
    $plan = [System.IO.File]::ReadAllText($ruta)
    $corrige = ($prompt -match '## CORRECCION')
    $malo = ($guiones -contains 'plan-paquete-nuevo-siempre') -or (($guiones -contains 'plan-paquete-nuevo' -or $guiones -contains 'plan-destino-nuevo') -and -not $corrige)
    $fqcn = 'com.acme.life.application.ports.output.LeerFichero'; $dest = 'application/ports/output'
    if ($malo) { $fqcn = 'com.acme.life.infrastructure.util.LeerFichero'; $dest = 'infrastructure/util' }
    if ($guiones -contains 'plan-ilegible') { $plan = $plan -replace 'destino: -', 'destino: por decidir con el equipo' -replace '(?s)## Piezas comunes\r?\nninguna', "## Piezas comunes`n- Una clase nueva que lee los ficheros de entrada" }
    elseif ($guiones -contains 'plan-destino-nuevo') { $plan = $plan -replace 'destino: -', "destino: $dest" }
    else {
      $mas = ''
      if ($guiones -contains 'plan-paquete-bueno') { $mas = "`n- ``application/ports/Marcador`` (ruta con la carpeta de un paquete de la plantilla): marca" }
      $plan = $plan -replace '(?s)## Piezas comunes\r?\nninguna', "## Piezas comunes`n- ``$fqcn`` (puerto): lee los ficheros de entrada$mas"
    }
    [System.IO.File]::WriteAllText($ruta, $plan)
  }
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
  if ($l -match '^## (Hallazgos|Ficheros del lote)') { $dentro = $true; continue }
  if ($dentro -and $l -match '^## ') { break }
  if ($dentro -and $l -match '^- (\S+?)(:\d+)?( - |$)') { $fichs += $Matches[1] }
}
$fichs = @($fichs | Select-Object -Unique)
Apunta 'lote' ($fichs -join ',')
if ($guiones -contains 've-marca') {
  $marca = Join-Path $rescate 'intento-en-curso.json'
  $texto = 'sin marca'
  if (Test-Path -LiteralPath $marca) { $texto = [System.IO.File]::ReadAllText($marca).Trim() }
  [System.IO.File]::AppendAllText((Join-Path $rescate 'marca-vista.log'), "$texto`n")
}
$primero = (@([System.IO.File]::ReadAllLines($log) | Where-Object { $_ -match '^\d+ \| lote \|' }).Count -eq 1)
if ($guiones -contains 'primer-lote-falla' -and $primero) { 'no hago nada'; exit 0 }
if ($guiones -contains 'falla-una-vez' -and $primero) { 'SALIDA-UNICA'; exit 1 }
if ($guiones -contains 'falla-copilot') {
  'SALIDA-A primera'; 'SALIDA-B'; ''; 'SALIDA-C'; 'SALIDA-D'; '   '; 'SALIDA-E'; 'SALIDA-F'; 'SALIDA-G ultima'
  exit 1
}
if ($guiones -contains 'muchos-ficheros' -and @($fichs | Where-Object { $_ -match 'LeerFichero\.java$' }).Count -gt 0) {
  if ($prompt -notmatch '## CORRECCION') {
    foreach ($k in 1..10) {
      Escribir "src/main/java/com/acme/life/application/usecases/LeerOtro$k.java" (@(
          'package com.acme.life.application.usecases;', '', 'import java.io.File;', '', "/** Caso de uso $k que lee un fichero de entrada. */",
          "public class LeerOtro$k {", '', '    /**', '     * Dice si el fichero existe.', '     *', '     * @param ruta ruta del fichero',
          '     * @return true si existe', '     */', '    public boolean existe(String ruta) {', '        return new File(ruta).exists();',
          '    }', '}', '') -join "`n")
    }
  }
  exit 0
}
$conSuelta = (@($fichs | Where-Object { $_ -match 'Suelta\.java$' }).Count -gt 0)
$rompe = 'src/test/java/com/acme/life/RompeTest.java'
$movida = 'src/main/java/com/acme/life/application/usecases/Suelta.java'
function Ve-Arbol([string]$Que) { [System.IO.File]::AppendAllText((Join-Path $rescate 'arbol-visto.log'), "$Que`n") }
if ($guiones -contains 'mejor-peor' -and $conSuelta) {
  $k = @([System.IO.File]::ReadAllLines($log) | Where-Object { $_ -match '^\d+ \| lote \|.*Suelta\.java' }).Count
  if ($k -eq 1) { Escribir 'src/main/resources/mejor.txt' "mejor`n"; exit 0 }
  if ($k -eq 2) { Escribir 'src/main/resources/peor.txt' "peor`n"; Escribir $rompe "class RompeTest { /* TEST_FALLA */ }`n"; exit 0 }
  $dc = $raiz
  Ve-Arbol ('mejor=' + (Test-Path -LiteralPath (Join-Path $dc 'src/main/resources/mejor.txt')) + ' peor=' + (Test-Path -LiteralPath (Join-Path $dc 'src/main/resources/peor.txt')) + ' rompe=' + (Test-Path -LiteralPath (Join-Path $dc $rompe)))
}
if ($guiones -contains 'parcial-roto') {
  if ($primero -and $conSuelta) {
    $orig = Join-Path $raiz 'src/main/java/com/acme/life/Suelta.java'
    $t = [System.IO.File]::ReadAllText($orig) -replace '(?m)^package [^;]*;', 'package com.acme.life.application.usecases;'
    Remove-Item -LiteralPath $orig -Force
    Escribir 'src/main/java/com/acme/life/application/usecases/Suelta.java' $t
    Escribir $rompe "class RompeTest { /* TEST_FALLA */ }`n"
    exit 0
  }
  if (-not $primero) {
    Ve-Arbol ('suelta-movida=' + (Test-Path -LiteralPath (Join-Path $raiz $movida)))
    if ($prompt -match '## CORRECCION' -and (Test-Path -LiteralPath (Join-Path $raiz $rompe))) { Remove-Item -LiteralPath (Join-Path $raiz $rompe) -Force }
  }
}
if ($guiones -contains 'atasca-siempre' -and $conSuelta) { 'no hago nada'; exit 0 }
if ($guiones -contains 'atasca' -and $conSuelta -and $prompt -notmatch '## Consejo') { 'no hago nada'; exit 0 }
if ($guiones -contains 'nada-sin-correccion' -and $prompt -notmatch '## CORRECCION') { 'no hago nada'; exit 0 }
if ($guiones -contains 'nada-hasta-reflexion' -and $prompt -notmatch 'REFLEXION-MARCA') { 'no hago nada'; exit 0 }
if ($guiones -contains 'fallos-distintos') {
  $orig = Join-Path $raiz 'src/main/java/com/acme/life/application/usecases/LeerFichero.java'
  $util = Join-Path $raiz 'src/main/java/com/acme/life/infrastructure/util/LeerFichero.java'
  if ($prompt -notmatch '## CORRECCION') { 'no hago nada'; exit 0 }
  if ($prompt -match 'No has cambiado ningun fichero') {
    $texto = [System.IO.File]::ReadAllText($orig) -replace '(?m)^package [^;]*;', 'package com.acme.life.infrastructure.util;'
    Remove-Item -LiteralPath $orig -Force
    Escribir 'src/main/java/com/acme/life/infrastructure/util/LeerFichero.java' $texto
    'lo muevo a util'; exit 0
  }
  if (Test-Path -LiteralPath $util) { Remove-Item -LiteralPath $util -Force; [void](& git checkout -q HEAD -- $orig) }
}
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
if ($guiones -contains 'comprueba') {
  $v = Join-Path $rescate 'comprobar-visto.log'
  $o = [regex]::Match($prompt, '(?m)^- Ejecuta: (.+?)  y corrige lo que liste')
  if (-not $o.Success) { [System.IO.File]::AppendAllText($v, "sin-orden`n") }
  else {
    function Listado-Rescate { return ((@(Get-ChildItem -LiteralPath $rescate -Recurse -File | Sort-Object FullName | ForEach-Object { $_.FullName + '|' + $_.Length + '|' + $_.LastWriteTimeUtc.Ticks })) -join "`n") }
    $antesR = Listado-Rescate
    $cmd = $o.Groups[1].Value -replace '^(pwsh|powershell)\b', ("& '" + (Get-Process -Id $PID).Path + "'")
    $sal = @(Invoke-Expression $cmd 2>&1 | ForEach-Object { "$_" })
    $rcC = $LASTEXITCODE
    $igual = ((Listado-Rescate) -eq $antesR)
    [System.IO.File]::AppendAllText($v, "rc=$rcC rescate-igual=$igual`n" + (($sal | ForEach-Object { "> $_" }) -join "`n") + "`n")
  }
}
exit $codigo
