<#
migracion.ps1 - Migracion desatendida de un batch Java, con un modelo pequeno.
Compatible con Windows PowerShell 5.1 y PowerShell 7. Solo ASCII a proposito.
Necesita comun.ps1, tareas.ps1, informe.ps1, rescate.ps1, prueba-local.ps1 y las carpetas tareas\ e informe\ junto a este script.

QUE HACE (la lectura del original, los datos para explicarlo a negocio, la correccion del migrado, su comparacion y la prueba en local)
  Un comando. Das el batch original (-Legacy) y el migrado (-Migrado), contestas
  dos preguntas (modelo y que hacer al acabar el informe) y te vas. Cada llamada
  a Copilot CLI es una tarea cerrada y pequena; el script la comprueba. El
  trabajo va a <Migrado>\migracion-<batch>\ (git la ignora en local) y la IA lee
  en un worktree aparte (<Migrado>-rescate), nunca en tu carpeta.

  Arranque: herramientas y repos, batch de referencia (-Plantilla, o el guardado
  en %USERPROFILE%\.rescate\ajustes.json, o se pregunta), modelo, prueba de
  aptitud (una ficha de clase sobre un fichero de juguete), pregunta y worktree.
  Diagnostico (sin IA, la primera fase): rescate.ps1 -Modo diagnostico mide el migrado y deja datos\hallazgos-antes.json y
  datos\diagnostico-antes.md; su pagina es 2-problemas.html. Se hace una vez: relanzar no repite Maven.
  Lectura: una ficha por clase del original, hasta 4 llamadas a la vez. Tras
  cada ronda el worktree tiene que estar limpio y el original y la referencia sin
  cambios. Una salida invalida se repite una vez, con el motivo y esfuerzo alto;
  si falla otra vez la tarea queda atascada y se sigue.
  Orden de las fases (datos\estado.json lleva la fase en que va; cada tarea hecha se salta al relanzar, y una fase se
  hace aunque la anterior tenga atascadas). Con la respuesta "corregir":
    fichas-clase, mapa, fichas-job, resumen, pruebas-pre, casos-pre, lectura-hecha, correccion, comparar y prueba-local.
  Con "parar" (o -SoloInforme): las mismas fases de lectura, comparar, lectura-hecha y prueba-local. Si la correccion
  se para, o hay tareas pendientes (-Limite), no se sigue con nada mas. Al acabar todo, sin parada ni pendientes, la
  fase es hecha, y estado.json lleva fin (vacio mientras corre; la hora al salir, de cualquier forma).
    mapa        jobs del original (contrato de rescate.ps1 -Modo pre -SinIA, o el que ya haya en
                .rescate\contrato.json), sus pasos (una tarea de definicion por fichero que
                define jobs) y sus clases, que calcula el script: datos\mapa.json; y las
                variables de application*.yml/.properties del migrado: datos\variables.json
    fichas-job  una redaccion por job, sin leer codigo, con las listas que monta el script
                con los datos de las fichas de clase: datos\jobs\<job>.json
    resumen     una tarea con todos los jobs: datos\resumen.json
    pruebas-pre una tarea por job con reglas o errores (sin leer codigo): el guion de prueba en pre,
                datos\pruebas\<job>.json; los jobs sin reglas ni errores lo llevan montado por el script
    casos-pre   una tarea por cada regla o error que pruebas-pre dejo en sinCaso: un caso de prueba para esa regla. Si vale, entra
                en datos\pruebas\<job>.json y la regla sale de sinCaso; si no, se queda ahi. Va despues de pruebas-pre y se hace
                tambien en un batch que ya paso por ella; las tareas hechas no se repiten
    lectura-hecha
    correccion  si contestaste "corregir": rescate.ps1 -Modo fix -Todo arregla el worktree (registros\correccion.log), se vuelve a
                diagnosticar (datos\hallazgos-despues.json) y datos\correcciones.json cuenta que se ha corregido y que no.
                Con "parar" (o -SoloInforme) no se corrige nada. Se salta si la correccion ya esta completa.
    comparar    una tarea por clase del original con datos: la IA lee los ficheros del migrado que elige el script (los del
                mismo nombre; si la correccion los renombro, partio o borro, los que git dice que los recogieron, por el
                renombrado o por las lineas que se llevaron; y si no, los que comparten palabras con la clase) y dice, dato a
                dato, si estan igual, distintos o faltan; las citas las comprueba el script: datos\comparacion\<ficha>.json, con el
                commit del worktree y el momento (antes-de-corregir o despues-de-corregir, segun git). Sin ficheros del migrado
                no hay llamada y sus datos salen 'sin-pieza'. Es una lectura sin cambiar nada. Se rehace si el worktree tiene un
                commit nuevo.
    prueba-local  prueba-local.ps1 -Si (con el mismo modelo, y -JavaLegacy si lo das) ejecuta el original y el migrado con las
                mismas entradas: datos\prueba-local.json y registros\prueba-local.log; su salida sale por la consola mientras
                corre. Siempre se lanza (al relanzar reutiliza lo hecho) salvo con -SinPruebaLocal. Un fallo se avisa y la
                pasada sigue: el codigo de salida no depende de esta fase. estado.json lleva pruebaLocal (resultado hecha,
                fallo o saltada, codigo, minutos, detalle, jdkOriginal -true si el original no compila con el JDK de Maven- y registro); hasta llegar
                a la fase vale null. estado.json lleva tambien ramaOrigen (la rama del migrado de la que sale la de rescate) y javaLegacy (el
                valor de -JavaLegacy, o vacio): con ellos la portada monta el comando del siguiente paso.
  Informe: tras cada fase y al parar, el script monta en <Salida>\ index.html (la portada: como ha ido y
  que te toca), 1-batch-original.html (que hace el batch, job a job), 2-problemas.html (los problemas del
  migrado), 3-original-vs-migrado.html (el original frente al migrado, dato a dato) y 4-correcciones.html (que se ha
  corregido y que queda), con informe.ps1 y las plantillas de informe\.
  Se abren con doble clic: sin IA, sin JavaScript y sin nada externo.
  Si algo se atasca, el script para y lo deja en datos\estado.json (parada) con un
  texto de ayuda listo para pegar en Copilot. Al relanzar el mismo comando salta
  las tareas hechas y sigue donde se quedo. Las atascadas tampoco se repiten (salvo
  con -Reintentar o con otro modelo).

USO
  .\migracion.ps1 -Legacy C:\ruta\life-java8 -Migrado C:\ruta\batch-life
  .\migracion.ps1 -Legacy ... -Migrado ... -Plantilla C:\ruta\batch-terminado -Modelo <id>
  .\migracion.ps1 ... -SoloInforme     # contesta "parar" a la pregunta del final
  .\migracion.ps1 ... -Si              # contesta "corregir"
  .\migracion.ps1 ... -MaxHoras 6      # no empieza rondas nuevas pasado ese tiempo
  .\migracion.ps1 ... -Limite 5        # ensayo corto: solo las 5 primeras tareas pendientes
  .\migracion.ps1 ... -Reintentar      # vuelve a llamar a las tareas atascadas de antes
  .\migracion.ps1 ... -SinPruebaLocal # no hace la ultima fase (ejecutar el original y el migrado)
  .\migracion.ps1 ... -JavaLegacy C:\jdk8   # el JDK del original para prueba-local.ps1, si no compila con el de Maven

  Salida: 0 bien (o tope de tiempo), 1 no pudo arrancar, 2 se paro (ver estado.json).
  Los ajustes de ajustes.json (y de .rescate\config.json del migrado) pisan las claves
  de CONFIGURACION (la de aqui y la de tareas.ps1); la carpeta de ajustes se cambia con
  la variable de entorno RESCATE_HOME. Antes de darlo por bueno, pasa tests\probar-migracion.ps1.
#>
[CmdletBinding()]
param(
  [string]$Legacy = '',       # carpeta del batch original (repo git)
  [string]$Migrado = '.',     # carpeta del batch migrado (repo git, en una rama)
  [string]$Plantilla = '',    # batch de referencia: ya migrado y aprobado (repo git)
  [string]$Modelo = '',       # id del modelo de Copilot; sin esto se pregunta
  [switch]$SoloInforme,       # al acabar el informe, parar (no corregir)
  [switch]$Si,                # al acabar el informe, corregir
  [double]$MaxHoras = 0,      # 0 = sin tope
  [int]$Limite = 0,           # 0 = sin limite; N = en este lanzamiento solo las N primeras tareas pendientes
  [switch]$Reintentar,        # volver a intentar las tareas atascadas de un lanzamiento anterior
  [switch]$SinPruebaLocal,    # no ejecutar el original y el migrado al final (la fase prueba-local)
  [string]$JavaLegacy = ''    # JAVA_HOME del original para prueba-local.ps1, si no compila con el JDK de Maven
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'comun.ps1')
. (Join-Path $PSScriptRoot 'tareas.ps1')
. (Join-Path $PSScriptRoot 'informe.ps1')

# ============================ CONFIGURACION ============================
$Cfg += @{
  Modelos            = @('claude-sonnet-5.5', 'gpt-6-luna', 'gpt-6.1-terra', 'gpt-6.1-sol', 'gpt-6-astra', 'claude-haiku-5.5', 'gemini-3.8-flash')
  FallosSeguidos     = 6      # llamadas fallidas seguidas antes de parar
}

# ============================== UTILIDADES ==============================
function Get-Repo([string]$Ruta, [string]$Que) {
  if (-not (Test-Path -LiteralPath $Ruta)) { Stop-Arranque "$Que no existe: $Ruta" }
  $r = Resolve-Dir $Ruta
  if (-not (Test-Path -LiteralPath (Join-Path $r '.git'))) { Stop-Arranque "$Que no es la raiz de un repo git: $r" }
  return $r
}

# artifactId del pom; si no hay, el nombre de la carpeta. Vale como nombre de carpeta.
function Get-Batch([string]$Raiz) {
  $id = ''
  $p = Join-Path $Raiz 'pom.xml'
  if (Test-Path -LiteralPath $p) {
    $x = New-Object System.Xml.XmlDocument
    try {
      $x.Load($p)
      foreach ($n in $x.DocumentElement.ChildNodes) { if ($n.LocalName -eq 'artifactId') { $id = $n.InnerText.Trim() } }
    }
    catch { $id = '' }
  }
  if (-not $id) { $id = Split-Path $Raiz -Leaf }
  return ($id -replace '[^\w\.\-]', '-')
}

# ============================ AJUSTES Y ESTADO ============================
# Guarda la referencia en ajustes.json sin tocar el resto de claves.
function Save-Plantilla([string]$Ruta) {
  $f = Get-RutaAjustes
  $o = [ordered]@{}
  if (Test-Path -LiteralPath $f) { foreach ($pr in (Read-Json $f).PSObject.Properties) { $o[$pr.Name] = $pr.Value } }
  $o['Plantilla'] = $Ruta
  Write-Json $f $o
}

function Save-Estado {
  $Estado['actualizado'] = (Get-Date).ToString('s')
  Write-Json (Join-Path $Datos 'estado.json') $Estado
}

# Las cinco paginas del informe (index.html, 1-batch-original.html, 2-problemas.html, 3-original-vs-migrado.html y 4-correcciones.html) con lo que haya hasta ahora. Si no se pueden montar,
# se avisa y la pasada sigue: son una vista de los datos, no parte del trabajo.
function Save-Informes {
  try { Write-Informes -Salida $Salida }
  catch { Aviso ('No he podido escribir las paginas del informe: ' + $_.Exception.Message) }
}

# Para el trabajo y lo deja en estado.json con un texto de ayuda para pegar en Copilot.
function Set-Parada([string]$Motivo, [string]$Detalle, [string]$Registro) {
  $ayuda = "Estoy ejecutando migracion.ps1 (migracion desatendida de un batch Java con GitHub Copilot CLI) y se ha parado. Motivo: $Motivo. Detalle: $Detalle. El registro esta en: $Registro. Dime que ha pasado y que tengo que hacer para arreglarlo. Despues vuelvo a lanzar el mismo comando y sigue donde se quedo."
  $Estado['parada'] = [ordered]@{ motivo = $Motivo; detalle = $Detalle; registro = $Registro; ayuda = $ayuda }
  Save-Estado
  Save-Informes
  if ($Motivo -eq 'tope-de-tiempo') { Aviso "Parada ($Motivo): $Detalle" } else { Fallo "Parada ($Motivo): $Detalle" }
}

function Select-Modelo {
  $l = @($Cfg.Modelos)
  Info 'Modelo de Copilot para las lecturas y los arreglos:'
  for ($i = 0; $i -lt $l.Count; $i++) { Info ('  ' + ($i + 1) + ') ' + $l[$i]) }
  $otro = $l.Count + 2
  Info ('  ' + ($l.Count + 1) + ') el que tenga Copilot (Enter)')
  Info "  $otro) otro (lo escribes tu)"
  $r = "$(Read-Host 'Numero')".Trim()
  if ($r -match '^\d+$' -and [int]$r -ge 1 -and [int]$r -le $l.Count) { return [string]$l[[int]$r - 1] }
  if ($r -eq "$otro") { return "$(Read-Host 'Id del modelo')".Trim() }
  return ''
}

# ================================= FASES =================================
# El diagnostico (sin IA): rescate.ps1 -Modo diagnostico lee el migrado en el worktree y sus hallazgos se copian a datos\ como
# hallazgos-<Cuando>.json y diagnostico-<Cuando>.md ($Cuando es antes o despues), con su registro. A continuacion se mide la cobertura de
# tests (datos\cobertura-<Cuando>.json y su registro; un Maven mas, salvo que el migrado no compile). Si el motor falla, parada 'motor'
# y devuelve $false.
function Invoke-DiagnosticoMotor([string]$Cuando) {
  $hMotor = Join-Ruta $RepoRoot '.rescate/hallazgos.json'
  $mMotor = Join-Ruta $RepoRoot '.rescate/diagnostico.md'
  if (Test-Path -LiteralPath $hMotor) { Remove-Item -LiteralPath $hMotor -Force }
  $r = Invoke-Nativo (Get-PowerShellExe) @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'rescate.ps1'), '-Modo', 'diagnostico', '-Repo', $RepoRoot, '-Plantilla', $PlantillaRoot, '-Si')
  $registro = Join-Path $Registros "diagnostico-$Cuando.log"
  Save-Registro $registro $r.Salida
  if ($r.Codigo -ne 0 -or -not (Test-Path -LiteralPath $hMotor) -or -not (Test-Path -LiteralPath $mMotor)) {
    $ultimas = Get-UltimasLineas $r.Salida
    $que = 'el diagnostico'
    if ($Cuando -eq 'despues') { $que = 'el diagnostico de despues' }
    Set-Parada 'motor' "$que (rescate.ps1 -Modo diagnostico) ha salido con codigo $($r.Codigo): $ultimas" $registro
    $script:Parada = $true
    return $false
  }
  # la cobertura va antes que los hallazgos: si se corta aqui, relanzar repite el diagnostico entero
  $compila = ((Get-EstadoBuild ([System.IO.File]::ReadAllText($mMotor, $Utf8))) -cne 'compila: NO')
  $cob = Get-Cobertura $RepoRoot (Join-Path $Registros "cobertura-$Cuando.log") $compila
  Write-Json (Join-Path $Datos "cobertura-$Cuando.json") $cob
  if ($cob.medida) { Info "Cobertura ($Cuando): $("$($cob.porcentaje)".Replace('.', ',')) % de las lineas ($($cob.cubiertas) de $($cob.total))." }
  else { Aviso "Cobertura ($Cuando): no se ha podido medir: $($cob.motivo)" }
  # el .json el ultimo: es el que dice que la fase esta hecha
  foreach ($par in @(@($mMotor, "diagnostico-$Cuando.md"), @($hMotor, "hallazgos-$Cuando.json"))) {
    $destino = Join-Path $Datos $par[1]
    Copy-Item -LiteralPath $par[0] -Destination ($destino + '.tmp') -Force
    Move-Item -LiteralPath ($destino + '.tmp') -Destination $destino -Force
  }
  return $true
}

# La salida de un proceso sin los colores de la consola.
function Get-SinColor($Salida) { return @($Salida | ForEach-Object { [regex]::Replace("$_", '\x1b\[[0-9;]*m', '') }) }

# Las 3 ultimas lineas con texto de la salida de un proceso, sin colores y unidas con ' / '.
function Get-UltimasLineas($Salida) { return (@(Get-SinColor $Salida | Where-Object { $_.Trim() } | Select-Object -Last 3) -join ' / ') }

# Lanza un script de esta carpeta con PowerShell y deja que su salida salga por la consola linea a linea mientras corre (Invoke-Nativo la
# guardaria hasta el final). Devuelve su codigo y su salida.
function Invoke-EnVivo([string]$Nombre, [string[]]$Argumentos) {
  $a = @('-NoProfile', '-File', (Join-Path $PSScriptRoot $Nombre)) + $Argumentos
  $eap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $lineas = @(& (Get-PowerShellExe) @a 2>&1 | ForEach-Object { $l = "$_"; Write-Host $l; $l })
    return [pscustomobject]@{ Codigo = $LASTEXITCODE; Salida = $lineas }
  }
  finally { $ErrorActionPreference = $eap }
}

function Save-Registro([string]$Ruta, $Salida) {
  [System.IO.File]::WriteAllText($Ruta, ((Get-SinColor $Salida) -join "`n") + "`n", $Utf8)
}

# La fase diagnostico: el diagnostico de antes. Se salta si ya esta (relanzar no repite Maven).
function Invoke-FaseDiagnostico {
  if (Test-Path -LiteralPath (Join-Path $Datos 'hallazgos-antes.json')) { return }
  $Estado['fase'] = 'diagnostico'
  Save-Estado
  [void](Get-JobsContrato)
  if (-not (Invoke-DiagnosticoMotor 'antes')) { return }
  Save-Informes
  $d = Read-Diagnostico $Datos
  Info "Diagnostico: $($d.Errores) errores y $($d.Avisos) avisos. Detalle: $(Join-Path $Salida '2-problemas.html')"
}

# Una fase: rondas de hasta Paralelo llamadas hasta que no quedan tareas pendientes, hay una parada o se llega
# al -Limite (que cuenta tareas de todas las fases). Tras cada ronda: worktree limpio y sin commits de la IA, y original y referencia
# sin cambios. Los contadores son del script ($script:Parada, Racha, Rondas e Iniciadas): las fases los comparten.
function Invoke-Fase($Tareas) {
  while (-not $script:Parada) {
    $pend = @($Tareas | Where-Object { $_.estado -eq 'pendiente' })
    if ($pend.Count -eq 0) { break }
    if ($MaxHoras -gt 0 -and $script:Rondas -gt 0 -and $reloj.Elapsed.TotalHours -ge $MaxHoras) {
      Set-Parada 'tope-de-tiempo' "Se ha llegado al tope de -MaxHoras $MaxHoras. Relanza el mismo comando para seguir." $Registros
      $script:Parada = $true
      break
    }
    $lote = @($pend | Select-Object -First ([int]$Cfg.Paralelo))
    if ($Limite -gt 0) {
      # -Limite cuenta tareas, no llamadas: una que se reintenta sigue siendo la misma
      $dentro = @()
      foreach ($x in $lote) {
        if ($script:Iniciadas.ContainsKey($x.id) -or $script:Iniciadas.Count -lt $Limite) { $script:Iniciadas[$x.id] = $true; $dentro += $x }
      }
      $lote = $dentro
      if ($lote.Count -eq 0) { break }
    }
    $head = Get-Head $RepoRoot
    $rondaRama = Get-Rama $RepoRoot
    Info ('Ronda: ' + $lote.Count + ' llamadas a la vez (quedan ' + $pend.Count + ' tareas)...')
    $res = @(Invoke-Ronda $lote $RepoRoot $LegacyRoot)
    $script:Rondas++

    # comprobacion tras la ronda: worktree limpio y original y referencia sin cambios
    $sucio = @((Invoke-Git $RepoRoot @('status', '--porcelain')).Salida | Where-Object { $_ })
    # un commit de la IA deja el worktree limpio: se ve porque el HEAD o la rama ya no son los de antes de la ronda
    $movido = ((Get-Head $RepoRoot) -cne $head -or (Get-Rama $RepoRoot) -cne $rondaRama)
    if ($sucio.Count -gt 0 -or $movido) { Undo-Lote $rondaRama $head }
    if ((Get-Huella $LegacyRoot) -ne $H0.Legacy -or (Get-Huella $PlantillaRoot) -ne $H0.Plantilla) {
      Set-Parada 'guardas' 'Ha cambiado el original o la referencia durante una lectura. Esa carpeta no se deshace desde aqui: mira con git status y git diff, y vuelve a lanzar.' $res[0].Registro
      $script:Parada = $true
      break
    }
    foreach ($o in $res) {
      if ($o.Estado -in @('fallo', 'tiempo')) { $script:Racha++ } else { $script:Racha = 0 }
      if ($movido -and $o.Estado -in @('ok', 'invalida')) {
        $o.Estado = 'invalida'
        $o.Motivo = 'La lectura hizo un commit en el repositorio. Lee sin cambiar nada: solo escribes el fichero de salida.'
      }
      elseif ($sucio.Count -gt 0 -and $o.Estado -in @('ok', 'invalida')) {
        $o.Estado = 'invalida'
        $o.Motivo = 'La lectura toco ficheros del repositorio (' + (($sucio | Select-Object -First 3) -join '; ') + '). Lee sin cambiar nada: solo escribes el fichero de salida.'
      }
      $t = $o.Tarea
      $t.intentos++
      $t.motivo = $o.Motivo
      $t.ultimoEstado = $o.Estado
      if ($o.Estado -eq 'ok') { $t.estado = 'hecha'; $t.resultado = $o.Ficha }
      elseif ($t.intentos -ge [int]$Cfg.Intentos) {
        $t.estado = 'atascada'
        $donde = $t.entradas.fichero
        if (-not $donde) { $donde = $t.id }
        Aviso "Atascada: ${donde}: $($o.Motivo)"
      }
      Save-Tarea $t
    }
    if ($script:Racha -ge [int]$Cfg.FallosSeguidos) {
      # el fallo es de Copilot, no de las tareas: vuelven a empezar al relanzar
      foreach ($o in $res) {
        if ($o.Estado -in @('fallo', 'tiempo')) { $o.Tarea.estado = 'pendiente'; $o.Tarea.intentos = 0; Save-Tarea $o.Tarea }
      }
      $ultimo = @($res | Where-Object { $_.Estado -in @('fallo', 'tiempo') } | Select-Object -Last 1)[0]
      Set-Parada 'copilot-no-responde' "$($script:Racha) llamadas seguidas han fallado (sesion, cuota o red). Ultimo error: $($ultimo.Motivo)" $ultimo.Registro
      $script:Parada = $true
      break
    }
  }
}

function Get-TareasFase([string]$Fase, [bool]$Conservar) {
  switch ($Fase) {
    'fichas-clase' { return @(Get-TareasFichas $Fuentes $Conservar) }
    'mapa' {
      # la foto de antes de corregir: una vez escrita no se toca (la correccion cambia los ficheros de configuracion)
      if (-not (Test-Path -LiteralPath (Join-Path $Datos 'variables.json'))) { Write-Json (Join-Path $Datos 'variables.json') @(Get-Variables) }
      return @(Get-TareasDefinicion @(Get-JobsContrato) $Conservar)
    }
    'fichas-job' { return @(Get-TareasJob (Read-Json (Join-Path $Datos 'mapa.json')) $Conservar) }
    'resumen' { return @(Get-TareasResumen (Read-Json (Join-Path $Datos 'mapa.json')) $Conservar) }
    'pruebas-pre' { return @(Get-TareasPrueba (Read-Json (Join-Path $Datos 'mapa.json')) $Conservar) }
    'casos-pre' { return @(Get-TareasCaso (Read-Json (Join-Path $Datos 'mapa.json')) $Conservar) }
    'comparar' { return @(Get-TareasComparar $Conservar $RamaMigrado) }
  }
}

# Lo que sale de una fase en datos\ (el mapa, solo cuando no queda ninguna tarea de definicion pendiente).
function Save-Fase([string]$Fase, $Tareas) {
  $pendientes = @($Tareas | Where-Object { $_.estado -eq 'pendiente' }).Count
  switch ($Fase) {
    'fichas-clase' { Save-Fichas $Tareas }
    'mapa' { if ($pendientes -eq 0) { Write-Json (Join-Path $Datos 'mapa.json') (Get-Mapa @(Get-JobsContrato) $Tareas $batch) } }
    'fichas-job' { Save-Jobs (Read-Json (Join-Path $Datos 'mapa.json')) $Tareas }
    'resumen' { if (@($Tareas | Where-Object { $_.estado -eq 'hecha' }).Count -gt 0) { Write-Json (Join-Path $Datos 'resumen.json') $Tareas[0].resultado } }
    'pruebas-pre' { Save-Pruebas (Read-Json (Join-Path $Datos 'mapa.json')) $Tareas }
    'casos-pre' { Save-Casos (Read-Json (Join-Path $Datos 'mapa.json')) $Tareas }
    'comparar' { Save-Comparaciones $Tareas }
  }
}

# La linea de consola de una fase.
function Get-LineaFase([string]$Fase, $Tareas) {
  $n = @{}
  foreach ($e in @('hecha', 'atascada', 'pendiente')) { $n[$e] = @($Tareas | Where-Object { $_.estado -eq $e }).Count }
  switch ($Fase) {
    'fichas-clase' { return "Lectura de clases: $($n.hecha) hechas, $($n.atascada) atascadas, $($n.pendiente) pendientes de $(@($Tareas).Count) tareas." }
    'mapa' {
      if ($n.pendiente -gt 0) { return "Mapa: $($n.pendiente) tareas de definicion pendientes." }
      $m = Read-Json (Join-Path $Datos 'mapa.json')
      $sin = @($m.sinJob).Count
      return "Mapa: $(@($m.jobs).Count) jobs, $($Fuentes.Count - $sin) clases con job, $sin sin job"
    }
    'fichas-job' {
      $l = "Fichas de job: $($n.hecha) hechas, $($n.atascada) atascadas"
      if ($n.pendiente -gt 0) { $l += ", $($n.pendiente) pendientes" }
      return $l
    }
    'resumen' {
      if (@($Tareas).Count -eq 0) { return 'Resumen: ningun job redactado, nada que resumir' }
      if ($n.hecha -gt 0) { return 'Resumen: hecho' }
      if ($n.atascada -gt 0) { return 'Resumen: atascado' }
      return 'Resumen: pendiente'
    }
    'pruebas-pre' {
      if (@($Tareas).Count -eq 0) { return 'Pruebas en pre: ningun job con reglas ni errores que probar con IA' }
      $l = "Pruebas en pre: $($n.hecha) hechas, $($n.atascada) atascadas"
      if ($n.pendiente -gt 0) { $l += ", $($n.pendiente) pendientes" }
      return $l
    }
    'casos-pre' {
      if (@($Tareas).Count -eq 0) { return 'Casos de las reglas sin caso: ninguna regla sin caso' }
      $l = "Casos de las reglas sin caso: $($n.hecha) hechos, $($n.atascada) atascados"
      if ($n.pendiente -gt 0) { $l += ", $($n.pendiente) pendientes" }
      return $l
    }
    'comparar' {
      if (@($Tareas).Count -eq 0) { return 'Comparacion con el original: ninguna clase con datos que comparar' }
      $l = "Comparacion con el original: $($n.hecha) clases comparadas"
      if ($n.atascada -gt 0) { $l += ", $($n.atascada) atascadas" }
      if ($n.pendiente -gt 0) { $l += ", $($n.pendiente) pendientes" }
      $c = [ordered]@{ 'igual' = 0; 'distinto' = 0; 'falta' = 0; 'no-lo-se' = 0; 'sin-pieza' = 0 }
      foreach ($t in @($Tareas | Where-Object { $_.estado -eq 'hecha' })) { foreach ($d in @($t.resultado.comparacion)) { $c[[string]$d.estado]++ } }
      return "$l. Datos: $($c['igual']) igual, $($c['distinto']) distinto, $($c['falta']) falta, $($c['no-lo-se']) no lo se, $($c['sin-pieza']) sin pieza."
    }
  }
}

# Una fase de tareas (las de lectura y comparar): sus tareas, las rondas, lo que deja en datos\, el informe y la linea de consola. Devuelve
# si se puede seguir con lo que viene despues: sin parada y sin tareas pendientes (-Limite). $script:Todas y $script:Quedan acumulan lo que
# hay al salir.
function Invoke-FaseTareas([string]$Fase) {
  $Estado['fase'] = $Fase
  Save-Estado
  $tareas = @(Get-TareasFase $Fase $conservar)
  $script:Todas += $tareas
  if ($Fase -eq 'fichas-clase') {
    $hechas0 = @($tareas | Where-Object { $_.estado -eq 'hecha' }).Count
    $ficheros = @($tareas | Group-Object { $_.ficha }).Count
    Info "Tareas de lectura: $($tareas.Count) (fichas de clase de $ficheros ficheros del original; $hechas0 ya hechas)."
    $atascadas0 = @($tareas | Where-Object { $_.estado -eq 'atascada' }).Count
    if ($atascadas0 -gt 0) { Aviso "$atascadas0 tareas atascadas de un lanzamiento anterior se conservan sin repetir. Para volver a intentarlas: -Reintentar (o cambia de modelo)." }
  }
  Invoke-Fase $tareas
  Save-Fase $Fase $tareas
  Save-Informes
  Info (Get-LineaFase $Fase $tareas)
  $script:Quedan = @($tareas | Where-Object { $_.estado -eq 'pendiente' }).Count
  return (-not $script:Parada -and $script:Quedan -eq 0)
}

# ============================== CORRECCION ==============================
# Los hallazgos de antes que ya no estan despues, comparando area, fichero y detalle (no la linea: cambiar de linea no es arreglarse).
function Get-Resueltos {
  $quedan = @{}
  foreach ($h in @(Read-Json (Join-Path $Datos 'hallazgos-despues.json') | Where-Object { $null -ne $_ })) {
    $k = "$($h.Cat)|$($h.Fichero)|$($h.Detalle)"
    $quedan[$k] = 1 + [int]$quedan[$k]
  }
  $res = @()
  foreach ($h in @(Read-Json (Join-Path $Datos 'hallazgos-antes.json') | Where-Object { $null -ne $_ })) {
    $k = "$($h.Cat)|$($h.Fichero)|$($h.Detalle)"
    if ([int]$quedan[$k] -gt 0) { $quedan[$k] = [int]$quedan[$k] - 1 } else { $res += $h }
  }
  return $res
}

# Los commits de arreglo (rescate(<paso>): ...) de la rama del worktree desde la rama del migrado, en orden.
function Get-CommitsRescate {
  $res = @()
  foreach ($l in @((Invoke-Git $RepoRoot @('log', '--reverse', '--format=%h|%s', "$RamaMigrado..HEAD")).Salida)) {
    $m = [regex]::Match("$l", '^([0-9a-f]+)\|(rescate\(([^)]*)\).*)$')
    if ($m.Success) { $res += [ordered]@{ hash = $m.Groups[1].Value; paso = $m.Groups[3].Value; asunto = $m.Groups[2].Value } }
  }
  return $res
}

# Lo que el motor no pudo arreglar: una linea "- [paso] fichero: motivo (registro: ruta)" de .rescate\atascados.md. Una linea que no
# case se guarda entera en el motivo.
function Get-Atascados {
  $ruta = Join-Ruta $RepoRoot '.rescate/atascados.md'
  $res = @()
  if (-not (Test-Path -LiteralPath $ruta)) { return $res }
  foreach ($l in [System.IO.File]::ReadAllLines($ruta, $Utf8)) {
    if (-not $l.Trim()) { continue }
    $m = [regex]::Match($l, '^- \[([^\]]*)\] (.+?): (.*?)(?: \(registro: [^)]*\))?\s*$')
    if ($m.Success) { $res += [ordered]@{ paso = $m.Groups[1].Value; fichero = $m.Groups[2].Value; motivo = $m.Groups[3].Value } }
    else { $res += [ordered]@{ paso = ''; fichero = ''; motivo = $l.Trim() } }
  }
  return $res
}

# Las variables sin valor por defecto que hay ahora en el worktree y no estaban en datos\variables.json (la foto de antes de corregir).
function Get-VariablesNuevas {
  $conocidas = @()
  $f = Join-Path $Datos 'variables.json'
  if (Test-Path -LiteralPath $f) { $conocidas = @(Read-Json $f | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_.variable }) }
  $res = @()
  foreach ($v in @(Get-Variables)) {
    if ($null -ne $v.porDefecto -or $v.secreto -eq $true) { continue }
    if (($conocidas -ccontains [string]$v.variable) -or (@($res | Where-Object { $_.variable -ceq $v.variable }).Count -gt 0)) { continue }
    $res += [ordered]@{ variable = $v.variable; fichero = $v.fichero; linea = $v.linea }
  }
  return $res
}

# datos\correcciones.json: lo que paso en la corrida, con parada o sin ella.
function Save-Correcciones([int]$Codigo, [bool]$Completa) {
  $resueltos = @()
  if (Test-Path -LiteralPath (Join-Path $Datos 'hallazgos-despues.json')) { $resueltos = @(Get-Resueltos) }
  $c = [ordered]@{
    completa = $Completa; codigo = $Codigo; rama = (Get-Rama $RepoRoot); base = $RamaMigrado
    commits = @(Get-CommitsRescate); atascados = @(Get-Atascados); resueltos = $resueltos; variablesNuevas = @(Get-VariablesNuevas)
  }
  Write-Json (Join-Path $Datos 'correcciones.json') $c
  return $c
}

# La fase correccion (tras lectura-hecha): rescate.ps1 -Modo fix -Todo arregla el worktree, se vuelve a diagnosticar y datos\correcciones.json
# lo cuenta. Con la respuesta 'parar' no se lanza. Si ya hay una correccion completa, se salta. Parada segun el codigo del motor:
# 0 completa; 2 sin compilar -> no-compila, con PARO: -> lotes-deshechos, si no completa con atascados; 3 git; 4 guardas; otro motor.
function Invoke-FaseCorreccion {
  $ruta = Join-Path $Datos 'correcciones.json'
  if (Test-Path -LiteralPath $ruta) {
    $previa = $null
    try { $previa = Read-Json $ruta } catch { $previa = $null }
    if ($previa -and $previa.completa -eq $true) { $Estado['fase'] = 'correccion'; Save-Estado; return }
  }
  if ($respuesta -ne 'corregir') { Info 'No se corrige nada: has pedido parar tras el informe. Para corregir, relanza el mismo comando con -Si.'; return }
  $Estado['fase'] = 'correccion'
  Save-Estado
  $atascadas = Join-Ruta $RepoRoot '.rescate/atascados.md'
  if (Test-Path -LiteralPath $atascadas) { Remove-Item -LiteralPath $atascadas -Force }
  Info 'Correccion: corrigiendo el migrado con rescate.ps1 -Modo fix (un fichero por llamada; puede tardar horas)...'
  $a = @('-Modo', 'fix', '-Todo', '-Si', '-Lote', '1', '-Repo', $RepoRoot, '-Plantilla', $PlantillaRoot, '-Legacy', $LegacyRoot, '-Esfuerzo', 'medium', '-EsfuerzoPlan', 'high')
  if ($ModeloElegido) { $a += @('-Modelo', $ModeloElegido) }
  $r = Invoke-EnVivo 'rescate.ps1' $a
  $registro = Join-Path $Registros 'correccion.log'
  Save-Registro $registro $r.Salida
  $diagnosticado = $true
  if ($r.Codigo -ne 1) { $diagnosticado = Invoke-DiagnosticoMotor 'despues' }
  $motivo = ''
  $detalle = ''
  switch ($r.Codigo) {
    0 { }
    2 {
      $d = Read-Diagnostico $Datos 'despues'
      if ($d -and $d.Estado -ceq 'compila: NO') { $motivo = 'no-compila'; $detalle = 'Despues de corregir, el migrado no compila. Los arreglos estan en la rama del worktree: mira el registro.' }
      elseif (@(Get-SinColor $r.Salida | Where-Object { $_ -match '^\s*PARO:' }).Count -gt 0) { $motivo = 'lotes-deshechos'; $detalle = '6 lotes seguidos deshechos: suele ser Copilot, Maven o un flag, no el codigo.' }
    }
    3 { $motivo = 'git'; $detalle = 'El motor no ha podido hacer un commit de arreglo (git commit ha fallado).' }
    4 { $motivo = 'guardas'; $detalle = 'El motor ha visto cambiar el original o la referencia durante los arreglos. Mira con git status y git diff, y vuelve a lanzar.' }
    default {
      $motivo = 'motor'
      $detalle = "el motor de arreglos (rescate.ps1 -Modo fix) ha salido con codigo $($r.Codigo): $(Get-UltimasLineas $r.Salida)"
    }
  }
  $c = Save-Correcciones $r.Codigo ($diagnosticado -and -not $motivo)
  if ($motivo) { Set-Parada $motivo $detalle $registro; $script:Parada = $true }
  # 'actualizado' se escribio al empezar: sin esto la portada dice que la pasada llevo lo de antes de corregir
  Save-Estado
  Save-Informes
  if ($diagnosticado -and -not $motivo) {
    Info "Correccion: $(@($c.commits).Count) commits de arreglo y $(@($c.atascados).Count) atascados. Detalle: $(Join-Path $Salida '4-correcciones.html')"
    if (@($c.atascados).Count -gt 0) { Aviso "Lo que el motor no ha podido arreglar esta en la pagina 4-correcciones.html y en $(Join-Path $Salida 'datos/correcciones.json')." }
  }
}

# ============================== PRUEBA EN LOCAL ==============================
# La fase prueba-local (la ultima): prueba-local.ps1 ejecuta el original y el migrado con las mismas entradas y deja datos\prueba-local.json;
# su salida sale por la consola y queda en registros\prueba-local.log. Siempre se lanza (al relanzar, prueba-local.ps1 ya reutiliza lo
# hecho); con -SinPruebaLocal se salta. Sale con 0 (todo igual) o 2 (hay distintos): las dos son hecha. Un fallo no para la pasada: se avisa
# y se sigue. estado.pruebaLocal lo cuenta.
function Invoke-FasePruebaLocal {
  if ($SinPruebaLocal) {
    $Estado['pruebaLocal'] = [ordered]@{ resultado = 'saltada'; codigo = $null; minutos = 0; detalle = ''; jdkOriginal = $false; registro = '' }
    return
  }
  $Estado['fase'] = 'prueba-local'
  Save-Estado
  Save-Informes
  Info 'Prueba en local: ejecutando el original y el migrado con las mismas entradas (prueba-local.ps1; puede tardar)...'
  $a = @('-Legacy', $LegacyRoot, '-Migrado', $MigradoRoot, '-Si')
  if ($ModeloElegido) { $a += @('-Modelo', $ModeloElegido) }
  if ($JavaLegacy) { $a += @('-JavaLegacy', $JavaLegacy) }
  $cronometro = [System.Diagnostics.Stopwatch]::StartNew()
  $r = Invoke-EnVivo 'prueba-local.ps1' $a
  $minutos = [Math]::Round($cronometro.Elapsed.TotalMinutes, 1)
  $registro = Join-Path $Registros 'prueba-local.log'
  Save-Registro $registro $r.Salida
  $hecha = ($r.Codigo -eq 0 -or $r.Codigo -eq 2)
  $detalle = ''
  if (-not $hecha) { $detalle = Get-UltimasLineas $r.Salida }
  $resultado = 'fallo'
  if ($hecha) { $resultado = 'hecha' }
  # el original que no compila con el JDK de Maven: prueba-local.ps1 lo dice en su primera linea de error y el detalle solo guarda las ultimas
  $jdk = ((-not $hecha) -and (@(Get-SinColor $r.Salida | Where-Object { $_ -match 'no compila con el JDK de Maven' }).Count -gt 0))
  $Estado['pruebaLocal'] = [ordered]@{ resultado = $resultado; codigo = $r.Codigo; minutos = $minutos; detalle = $detalle; jdkOriginal = $jdk; registro = 'registros/prueba-local.log' }
  $json = Join-Path $Datos 'prueba-local.json'
  if (-not $hecha) { Aviso "Prueba en local: ha salido con codigo $($r.Codigo): $detalle. Registro: $registro" }
  elseif (Test-Path -LiteralPath $json) {
    $jobs = @((Read-Json $json).jobs)
    $n = @{}
    foreach ($k in @('casos', 'iguales', 'distintos')) { $n[$k] = [int](($jobs | Measure-Object -Property $k -Sum).Sum) }
    Info "Prueba en local: $($n.casos) casos, $($n.iguales) iguales, $($n.distintos) distintos ($("$minutos".Replace('.', ',')) min). Detalle: $(Join-Path $Salida '3-original-vs-migrado.html')"
  }
}

# ================================= MAIN =================================
$reloj = [System.Diagnostics.Stopwatch]::StartNew()
if (-not $Legacy) { Stop-Arranque 'Falta -Legacy: la carpeta del batch original (Java 8).' }
if ($SoloInforme -and $Si) { Stop-Arranque 'Usa -SoloInforme o -Si, no los dos.' }
$respondeSi = [bool]$Si

# 1. Herramientas y repos (antes, los ajustes: pueden cambiar donde estan)
$ajustes = Read-CfgFile (Get-RutaAjustes) @('Plantilla')
foreach ($x in @(@('git', 'git'), @('java', $Cfg.JavaExe), @('Copilot', $Cfg.CopilotExe))) {
  if (-not (Get-Command $x[1] -ErrorAction SilentlyContinue)) { Stop-Arranque "No encuentro $($x[0]) ('$($x[1])') en el PATH." }
}
$LegacyRoot = Get-Repo $Legacy '-Legacy'
$MigradoRoot = Get-Repo $Migrado '-Migrado'
$RamaMigrado = Get-Rama $MigradoRoot
if (-not $RamaMigrado -or $RamaMigrado -eq 'HEAD') { Stop-Arranque "El migrado no esta en una rama (HEAD suelto): $MigradoRoot. Cambia a una rama y vuelve a lanzar." }
Read-Config $MigradoRoot
$mvn = Get-Mvn $MigradoRoot
if (-not (Test-Path -LiteralPath $mvn) -and -not (Get-Command $mvn -ErrorAction SilentlyContinue)) { Stop-Arranque "No encuentro Maven ('$mvn'). Instalalo o pon MvnExe en los ajustes." }
Set-Excluidos $MigradoRoot
$Fuentes = @(Get-JavaOriginal $LegacyRoot)
if ($Fuentes.Count -eq 0) { Stop-Arranque "No hay ningun .java que leer en el original: $LegacyRoot`nBusco los de src/main/java de cualquier modulo y, si no hay, todos menos los de src/test, target y .git. Mira que -Legacy es la carpeta correcta." }

# 2. Batch de referencia: -Plantilla, el guardado o se pregunta; se guarda
$guardada = ''
if ($ajustes -and $ajustes.Plantilla) { $guardada = [string]$ajustes.Plantilla }
$ref = $Plantilla
if (-not $ref -and $guardada -and (Test-Path -LiteralPath $guardada)) { $ref = $guardada }
if (-not $ref) { $ref = "$(Read-Host 'Carpeta del batch de referencia (un batch ya migrado y aprobado)')".Trim() }
if (-not $ref) { Stop-Arranque 'Falta la referencia: pasa -Plantilla o contesta con la carpeta del batch de referencia.' }
$PlantillaRoot = Get-Repo $ref 'La referencia'
if ($PlantillaRoot -ne $guardada) { Save-Plantilla $PlantillaRoot }

# Carpetas de salida y estado anterior (si se relanza)
$batch = Get-Batch $MigradoRoot
$Salida = Join-Path $MigradoRoot ('migracion-' + $batch)
$Datos = Join-Path $Salida 'datos'
$Registros = Join-Path $Salida 'registros'
foreach ($d in @($Datos, $Registros)) { if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -Force) } }
$previo = $null
if (Test-Path -LiteralPath (Join-Path $Datos 'estado.json')) { try { $previo = Read-Json (Join-Path $Datos 'estado.json') } catch { $previo = $null } }

# 3. Modelo: -Modelo, el del lanzamiento anterior o el menu
if ($PSBoundParameters.ContainsKey('Modelo')) { $ModeloElegido = $Modelo }
elseif ($previo -and ($null -ne $previo.modelo)) { $ModeloElegido = [string]$previo.modelo }
else { $ModeloElegido = Select-Modelo }
if ($ModeloElegido) { Info "Modelo: $ModeloElegido" } else { Info 'Modelo: el que tenga Copilot' }
# las tareas atascadas de antes se conservan si el modelo es el mismo y no se pide -Reintentar
$conservar = [bool]((-not $Reintentar) -and $previo -and ([string]$previo.modelo -ceq $ModeloElegido))
$H0 = [pscustomobject]@{ Legacy = (Get-Huella $LegacyRoot); Plantilla = (Get-Huella $PlantillaRoot) }

# 4. Prueba de aptitud (se salta si ya paso con este modelo)
if ($previo -and ($null -ne $previo.aptitud) -and ([string]$previo.aptitud -eq $ModeloElegido)) { Info 'Prueba de aptitud: ya pasada con este modelo.' }
else {
  Info 'Prueba de aptitud (una ficha de clase sobre un fichero de juguete)...'
  $mal = Test-Aptitud
  if ($mal) { Stop-Arranque ("$mal`nRegistros: $Registros`nPrueba con otro modelo (-Modelo) o mira que Copilot responde.") }
  Bien 'Prueba de aptitud: bien.'
}

# 5. Pregunta: que hacer al acabar el informe
if ($SoloInforme) { $respuesta = 'parar' }
elseif ($respondeSi) { $respuesta = 'corregir' }
elseif ($previo -and $previo.respuesta) { $respuesta = [string]$previo.respuesta }
else {
  $r = "$(Read-Host 'Al acabar el informe, corregir el codigo del migrado? Enter = si, n = parar')".Trim()
  if ($r -match '^[nN]') { $respuesta = 'parar' } else { $respuesta = 'corregir' }
}
$Si = [switch]$true    # las preguntas ya estan contestadas: Confirmar no vuelve a preguntar

# 6. Worktree y estado
$OrigenRoot = $MigradoRoot
$Worktree = ''
$dirWt = Get-DirRescate
if (-not (Test-WorktreeRescate $dirWt)) { New-WorktreeRescate $dirWt }
$RepoRoot = $dirWt
Read-Config $RepoRoot
$Estado = [ordered]@{
  version = 1; batch = $batch; legacy = $LegacyRoot; migrado = $MigradoRoot; plantilla = $PlantillaRoot
  worktree = $RepoRoot; rama = (Get-Rama $RepoRoot); ramaOrigen = $RamaMigrado; javaLegacy = $JavaLegacy; modelo = $ModeloElegido; aptitud = $ModeloElegido; respuesta = $respuesta
  fase = 'fichas-clase'; creado = (Get-Date).ToString('s'); actualizado = ''; fin = ''; parada = $null; pruebaLocal = $null
}
# En PowerShell 7 ConvertFrom-Json deja el texto ISO como fecha: se vuelve a escribir igual que la primera vez.
if ($previo -and $previo.creado) { $Estado['creado'] = if ($previo.creado -is [datetime]) { $previo.creado.ToString('s') } else { [string]$previo.creado } }
try {
  foreach ($d in @((Join-Path $Datos 'tareas'), (Join-Path $Datos 'fichas'))) { if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -Force) } }
  Save-Estado
  if (-not (Set-Despierto $true)) { Aviso 'No he podido pedir a Windows que no suspenda el equipo: si lo dejas solo, compruebalo.' }
  $script:Parada = $false
  $script:Racha = 0
  $script:Rondas = 0
  $script:Iniciadas = @{}
  $script:Todas = @()
  $script:Quedan = 0
  Invoke-FaseDiagnostico
  # con la respuesta corregir, comparar va despues de la correccion; con parar, antes de lectura-hecha
  $fases = @('fichas-clase', 'mapa', 'fichas-job', 'resumen', 'pruebas-pre', 'casos-pre')
  if ($respuesta -ne 'corregir') { $fases += 'comparar' }
  $sigue = -not $script:Parada
  foreach ($fase in $fases) { if ($sigue) { $sigue = Invoke-FaseTareas $fase } }
  if ($sigue) {
    $Estado['fase'] = 'lectura-hecha'
    Save-Estado
    Save-Informes
    Invoke-FaseCorreccion
    $sigue = -not $script:Parada
    if ($sigue -and $respuesta -eq 'corregir') { $sigue = Invoke-FaseTareas 'comparar' }
  }
  if ($sigue) {
    Invoke-FasePruebaLocal
    $Estado['fase'] = 'hecha'
  }

  Info ''
  if (-not $script:Parada -and $script:Quedan -gt 0) { Info "Limite de -Limite $Limite alcanzado: quedan $($script:Quedan) tareas pendientes. Relanza el mismo comando sin -Limite para seguir." }
  Info "Datos en: $Salida"
  if (@($script:Todas | Where-Object { $_.estado -eq 'atascada' }).Count -gt 0) { Aviso "Las tareas atascadas estan en $(Join-Path $Datos 'tareas') (estado 'atascada', con su motivo)." }
  $Estado['fin'] = (Get-Date).ToString('s')
  Save-Estado
  Save-Informes
  if ($script:Parada -and $Estado['parada'].motivo -ne 'tope-de-tiempo') { exit 2 }
  exit 0
}
catch {
  # una excepcion que nadie esperaba: se deja en estado.json para que el relanzamiento no sea a ciegas
  $ex = $_
  $donde = ''
  if ($ex.InvocationInfo -and $ex.InvocationInfo.ScriptName) { $donde = ' (' + (Split-Path $ex.InvocationInfo.ScriptName -Leaf) + ':' + $ex.InvocationInfo.ScriptLineNumber + ')' }
  try { $Estado['fin'] = (Get-Date).ToString('s'); Set-Parada 'error-interno' ($ex.Exception.Message + $donde) $Registros }
  catch { Fallo ('Error interno: ' + $ex.Exception.Message + $donde + ' (y no he podido escribir estado.json: ' + $_.Exception.Message + ')') }
  exit 2
}
finally {
  [void](Set-Despierto $false)
}
