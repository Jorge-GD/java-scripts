<#
revision.ps1 - Revision del arbol final por flujos (pieza C3 del cierre): una llamada pequena a Copilot por unidad (un step con sus piezas, o un
fichero suelto) que revisa solo contra un catalogo cerrado de reglas y devuelve como mucho 5 hallazgos con cita. El script tira lo que no se puede
comprobar. Solo lee: no cambia codigo (la plantilla lo dice; lo que toque una ronda lo deshace Invoke-Fase). No se ejecuta solo: solo funciones. Se carga con '. (Join-Path $PSScriptRoot 'revision.ps1')' despues de
comun.ps1, tareas.ps1 y practicas.ps1 (Get-JavaFiles, Get-Rel, Join-Ruta, Invoke-Git, Get-Head, Get-NombreJob, Get-ClaveFichero, Get-BlobsHead,
Restore-Tarea, Set-CitasProbadas, Test-LineaCita, Get-JavaSinComentarios, Get-ArgumentosLlamada). Solo ASCII: los textos con tilde van como \uXXXX.
Vale para Windows PowerShell 5.1 y para PowerShell 7. Es un tipo de tarea mas del motor de tareas.ps1: 'revision-flujo' (plantilla tareas\revision-flujo.md).

  Get-ReglasRevision        el catalogo: { id, titulo, que, tokens }. Solo las reglas que nada mas mide: SB-FACTORIAS, J21-FORMATO y
                            J21-SECURITYMANAGER no estan porque ya salen del diagnostico (rescate.ps1) o de las buenas practicas (practicas.ps1).
  Get-UnidadesRevision      las unidades { id, tipo (step o fichero), nombre, ficheros, sinResolver }, en orden estable.
  Get-TareasRevision        las tareas revision-flujo (con huella: una tarea hecha con la misma huella no se vuelve a pedir).
  Test-Revision             la comprobacion de lo que escribe Copilot (la llama Test-Salida de tareas.ps1).
  Save-Revision             datos\revision.json, con un hallazgo por regla, fichero y linea (el de la primera unidad).
  Get-AvisoRevision         el aviso de antes de empezar.
  Get-LineaRevision         la linea de consola de despues.

  Unidades. Un step es cada 'new StepBuilder(' de un .java de src/main/java (sin comentarios): su nombre es el primer argumento si es una cadena
  literal y, si no, <Fichero>-<n>; su cadena va hasta el primer ';' al nivel de la cadena (o hasta el siguiente step), sin contar los de dentro de un
  argumento ni de una lambda. De cada .reader(, .processor(, .writer(, .tasklet( y .listener( de la cadena sale un nombre (de 'new X(...)', X; de 'x(...)' o 'x', x),
  que se resuelve a un fichero por (a) la clase X o x con la primera en mayuscula, (b) un metodo @Bean x (la clase de su tipo de vuelta o, si no esta,
  el fichero del metodo), (c) un campo o parametro 'Tipo x' del mismo fichero; si no, va a sinResolver. Como mucho 6 ficheros por step (el del
  step primero); los demas, si estan en el alcance, van sueltos. Los .java del alcance que no estan en ningun step son unidades 'fichero'.
  Alcance (sin $Todo): lo que cambia en 'git diff --name-only <Base>...HEAD', lo que tiene papel de Spring Batch y las candidatas.
  Huella: Get-Hash8 de las claves de los ficheros de la unidad (Get-ClaveFichero), el hash de la plantilla, las candidatas de la unidad y los ids del catalogo.
#>

# ============================ CONFIGURACION ============================
$Cfg += @{
  RevisionHallazgosMax = 5   # hallazgos que se quedan de cada unidad (los demas cuentan en sobran)
  RevisionFicherosMax  = 6   # ficheros de una unidad de step; los demas de su cadena van sueltos
}

# ============================== CATALOGO ==============================
# Cada regla: id, titulo, lo que busca (una sola linea: va tal cual al prompt) y los textos de los que la cita lleva al menos uno. Los textos con
# tilde llevan \uXXXX y salen por [regex]::Unescape (sin barras inversas que no sean esas). Fuentes: referencia de Spring Batch (late binding),
# guia de migracion de Spring Batch 5.0, guia de Spring Boot 3.0, JEP 403; SB-ESTADO: Sonar S3749 (miembros de un singleton de Spring), Step Scope e
# ItemStream de Spring Batch; ERR-TRAGADA: Configuring Skip Logic de Spring Batch. Un catch vacio no es de ERR-TRAGADA: ya lo mide rescate.ps1 (catch-vacio).
function Get-ReglasRevision {
  $r = @(
    @('SB-LISTENER', 'Listener que nadie registra',
      'Un listener (implementa un *Listener de Spring Batch o usa @BeforeStep, @AfterStep, @BeforeJob, @AfterJob, @OnSkip...) que nadie registra. Antes de dar el hallazgo, busca el nombre del listener en todo el repositorio, no solo en los ficheros de esta unidad: si un job o un step lo registra con .listener(, o es el reader, processor, writer o tasklet de un step, no es hallazgo.',
      @('Listener', '@Before', '@After', '@On')),
    @('SB-STEPSCOPE', '@StepScope que devuelve la interfaz',
      'Un @Bean con @StepScope o @JobScope que devuelve ItemReader, ItemWriter o ItemProcessor y cuyo objeto es tambi\u00e9n un ItemStream (FlatFile, Jdbc, Stax...) o un listener: el proxy solo tiene la interfaz del tipo de vuelta, y Spring Batch no llama a open, update ni close, ni al listener. El tipo de vuelta tiene que ser al menos ItemStream (o el tipo concreto).',
      @('ItemReader', 'ItemWriter', 'ItemProcessor')),
    @('SB-TRANSACCION', 'Gestor de transacciones que no es el de la base',
      'El step recibe un gestor de transacciones que no es el de la base en la que escribe (por ejemplo ResourcelessTransactionManager, o el de otro DataSource): si el chunk falla, lo escrito no se deshace.',
      @('TransactionManager', 'chunk(', 'tasklet(')),
    @('SB-CONTEXTO', 'Objeto no serializable en el ExecutionContext',
      'Guarda en el ExecutionContext (put) un objeto que no es Serializable. Desde Spring Batch 5 el serializador por defecto es el de Java: un objeto que no es Serializable hace fallar el guardado del contexto.',
      @('put')),
    @('BOOT-ENABLEBATCH', '@EnableBatchProcessing apaga la configuraci\u00f3n autom\u00e1tica',
      '@EnableBatchProcessing, o una clase que extiende DefaultBatchConfiguration: en Spring Boot 3 la configuraci\u00f3n autom\u00e1tica de Batch se aparta, as\u00ed que no lanza el job al arrancar ni crea las tablas BATCH_.',
      @('EnableBatchProcessing', 'DefaultBatchConfiguration')),
    @('J21-INTERNOS', 'Acceso a internos del JDK',
      'setAccessible(true) sobre clases del JDK, o uso de APIs internas sun.* o com.sun.*: desde Java 17 el JDK cierra sus internos (JEP 403) y lanza InaccessibleObjectException.',
      @('setAccessible', 'sun.')),
    @('CAND-MUERTA', 'Clase candidata a c\u00f3digo muerto',
      'Solo en las candidatas de la unidad (las que se te dan arriba): una clase que nadie usa, ni por su nombre en la configuraci\u00f3n (.xml, .yml, .properties) ni por reflexi\u00f3n. Antes de dar el hallazgo, busca su nombre en todo el repositorio; si lo encuentras, no es hallazgo.',
      @('class ', 'interface ', 'enum ', 'record ')),
    @('SB-ESTADO', 'Estado en un bean de un paso sin @StepScope',
      'Un lector, procesador, escritor, tasklet o listener que es un bean singleton (ni la clase ni el @Bean que lo crea llevan @StepScope o @JobScope) y guarda en un campo un valor que cambia durante la ejecuci\u00f3n: un contador, una lista o un mapa al que se a\u00f1ade, el fichero o el writer abierto, una fecha del proceso. Ese valor pasa a la siguiente ejecuci\u00f3n del job en la misma JVM y a otros hilos, y la prueba en local no lo ve porque cada caso arranca una JVM nueva. El campo puede ser final si lo que guarda se modifica (una lista final a la que se a\u00f1ade). No cuentan los campos que solo se asignan en el constructor o con @Value, ni los loggers, ni las constantes. Antes de dar el hallazgo, busca d\u00f3nde se crea el bean: si su @Bean o su clase llevan @StepScope o @JobScope, aunque sea en otro fichero, no es hallazgo. Arreglo: @StepScope en el bean, o el valor en el ExecutionContext. La cita es la declaraci\u00f3n del campo o la l\u00ednea que lo cambia.',
      @('private ', '++', '+=', '.add(', '.put(', 'this.')),
    @('ERR-TRAGADA', 'Error tragado en un paso',
      'Un catch en un lector, procesador, escritor, tasklet o listener que registra el error, o lo ignora con un cuerpo que no lo trata (un return null, un continue, un contador), y sigue: no relanza, no usa el skip de Spring Batch (faultTolerant(), skip, SkipPolicy) y no marca el paso como fallido (ExitStatus.FAILED, setStatus, setExitStatus). El job acaba COMPLETED aunque se pierdan registros o no se escriba un fichero. No cuenta un catch vac\u00edo (ya lo mide el diagn\u00f3stico), ni uno que guarda el error donde el job lo mira despu\u00e9s (un fichero de KO o el ExecutionContext, si el c\u00f3digo lo comprueba). Arreglo: relanzar, o declarar el skip si el negocio lo permite. La cita es la l\u00ednea del catch.',
      @('catch'))
  )
  return @($r | ForEach-Object { [pscustomobject]@{ id = $_[0]; titulo = [regex]::Unescape($_[1]); que = [regex]::Unescape($_[2]); tokens = @($_[3]) } })
}

# Lo que va en cada {{CLAVE}} de la plantilla revision-flujo (Get-VariablesPrompt de tareas.ps1 lo llama): la unidad, una linea FICHERO: por fichero,
# las candidatas de la unidad (o 'ninguna'), el catalogo (id: que busca, y los textos de los que la cita lleva uno) y el tope de hallazgos.
function Get-VariablesRevision($T) {
  $e = $T.entradas
  $reglas = @(Get-ReglasRevision | ForEach-Object { $_.id + ': ' + $_.que + ' La cita lleva uno de estos textos: ' + ((@($_.tokens) | ForEach-Object { '`' + $_ + '`' }) -join ', ') + '.' })
  $candidatas = 'ninguna'
  if (@($e.candidatas).Count -gt 0) { $candidatas = (@($e.candidatas) -join ', ') }
  return @{
    UNIDAD        = "$($e.tipoUnidad) $($e.unidad)"
    FICHEROS      = ((@($e.ficheros) | ForEach-Object { "FICHERO: $_" }) -join "`n")
    CANDIDATAS    = $candidatas
    REGLAS        = ($reglas -join "`n")
    HALLAZGOS_MAX = "$($Cfg.RevisionHallazgosMax)"
  }
}

# ============================== UNIDADES ==============================
# Los .java de src/main/java de $Dir en orden ordinal de ruta: Rel (con /), Nombre (el de la clase) y Codigo (sin comentarios, con las cadenas).
function Get-FuentesRevision([string]$Dir) {
  $lista = @()
  foreach ($f in @(Get-JavaFiles $Dir)) {
    $rel = Get-Rel $Dir $f.FullName
    if ($rel -cnotmatch '(^|/)src/main/java/') { continue }
    $lista += [pscustomobject]@{ Rel = $rel; Nombre = [System.IO.Path]::GetFileNameWithoutExtension($rel); Codigo = (Get-JavaSinComentarios ([System.IO.File]::ReadAllText($f.FullName))) }
  }
  $claves = [string[]]@($lista | ForEach-Object { $_.Rel })
  $items = [object[]]@($lista)
  [Array]::Sort($claves, $items, [System.StringComparer]::Ordinal)
  return $items
}

# Las rutas (con /) que cambian en <Base>...HEAD de $Dir, como claves de un hashtable. Sin base o si git no la conoce, ninguna.
function Get-CambiadosRevision([string]$Dir, [string]$Base) {
  $c = @{}
  if (-not $Base) { return $c }
  $d = Invoke-Git $Dir @('-c', 'core.quotepath=off', 'diff', '--name-only', "$Base...HEAD")
  if ($d.Codigo -eq 0) { foreach ($l in @($d.Salida)) { if ("$l".Trim()) { $c["$l".Trim()] = $true } } }
  return $c
}

# Tiene papel en un batch: implementa o extiende un reader, processor, writer, ItemStream*, Tasklet o *Listener, lleva una anotacion de configuracion
# o de listener de Batch, o construye un job o un step. $Codigo va sin comentarios.
function Test-PapelRevision([string]$Codigo) {
  return ($Codigo -cmatch '\b(?:implements|extends)\s+[^{;]*?\b(?:\w*Item(?:Reader|Processor|Writer)|ItemStream\w*|Tasklet|\w*Listener)\b|@(?:Configuration|StepScope|JobScope|BeforeStep|AfterStep|BeforeJob|AfterJob)\b|\bnew\s+(?:StepBuilder|JobBuilder)\s*\(')
}

# Las llamadas .reader(, .processor(, .writer(, .tasklet( y .listener( de la cadena del step que empieza en $Ini (la '(' de 'new StepBuilder(', sobre codigo
# sin comentarios), cada una con el indice de su '('. Solo las del nivel de la cadena (ni las de dentro de un argumento ni las de una lambda cuentan), hasta
# el primer ';' a ese nivel o hasta $Tope.
function Get-CadenaStep([string]$T, [int]$Ini, [int]$Tope) {
  $rxLlamada = [regex]'\G\.\s*(?:reader|processor|writer|tasklet|listener)\s*\('
  $llamadas = @()
  $nivel = 0
  $i = $Ini
  while ($i -lt $Tope) {
    $c = $T[$i]
    if ($c -eq '"' -or $c -eq "'") {
      $i++
      while ($i -lt $Tope -and $T[$i] -ne $c) { if ($T[$i] -eq '\') { $i++ }; $i++ }
    }
    elseif ($c -eq '(' -or $c -eq '[' -or $c -eq '{') { $nivel++ }
    elseif ($c -eq ')' -or $c -eq ']' -or $c -eq '}') { $nivel-- }
    elseif ($nivel -eq 0 -and $c -eq ';') { break }
    elseif ($nivel -eq 0 -and $c -eq '.') {
      $m = $rxLlamada.Match($T, $i)
      if ($m.Success) { $llamadas += $m.Index + $m.Length - 1 }
    }
    $i++
  }
  return $llamadas
}

# El nombre que sale de un argumento: de 'new X(...)', X; de 'x(...)' o 'x' (con o sin 'esto.' delante), x. '' si no es ninguna de las dos formas (una lambda...).
function Get-NombreArgumento([string]$A) {
  $m = [regex]::Match($A, '^new\s+(?:\w+\.)*(?<n>\w+)')
  if ($m.Success) { return $m.Groups['n'].Value }
  $m = [regex]::Match($A, '^(?:\w+\.)*(?<n>\w+)\s*(?:\(|$)')
  if ($m.Success) { return $m.Groups['n'].Value }
  return ''
}

# Los steps de un fuente: { Nombre, Fichero, Nombres (los de las piezas, en el orden de la cadena) }.
function Get-StepsFichero($F) {
  $t = $F.Codigo
  $abre = @([regex]::Matches($t, '\bnew\s+StepBuilder\s*\('))
  $pasos = @()
  for ($i = 0; $i -lt $abre.Count; $i++) {
    $m = $abre[$i]
    $nombre = "$($F.Nombre)-$($i + 1)"
    $a = Get-ArgumentosLlamada $t ($m.Index + $m.Length - 1)
    if ($null -ne $a -and @($a).Count -gt 0 -and $a[0] -cmatch '^"((?:[^"\\]|\\.)*)"$') { $nombre = $Matches[1] }
    $tope = $t.Length
    # la cadena no pasa del siguiente 'new StepBuilder(': acota lo que se recorre (sin ';' al nivel de la cadena seguiria hasta el final del fichero)
    if ($i + 1 -lt $abre.Count) { $tope = $abre[$i + 1].Index }
    $nombres = @()
    foreach ($abrePieza in @(Get-CadenaStep $t $m.Index $tope)) {
      $arg = Get-ArgumentosLlamada $t $abrePieza
      if ($null -eq $arg -or @($arg).Count -eq 0) { continue }
      $n = Get-NombreArgumento $arg[0]
      if ($n) { $nombres += $n }
    }
    $pasos += [pscustomobject]@{ Nombre = $nombre; Fichero = $F.Rel; Nombres = @($nombres) }
  }
  return $pasos
}

# Donde buscar un nombre: PorNombre (clase simple -> ruta; la primera en orden de ruta) y Beans (metodo @Bean -> su tipo de vuelta sin genericos y su fichero).
function Get-ResolucionRevision($Fuentes) {
  $rxBean = '@Bean\b(?:\s*\([^)]*\))?(?:\s*@[\w.]+(?:\s*\([^)]*\))?)*\s*(?:(?:public|protected|private|static|final|synchronized)\s+)*(?<tipo>[\w.]+)\s*(?:<[^;{}()]*>)?(?:\s*\[\s*\])*\s+(?<nombre>\w+)\s*\('
  $porNombre = New-Object 'System.Collections.Generic.Dictionary[string,string]'
  $beans = New-Object 'System.Collections.Generic.Dictionary[string,object]'
  foreach ($f in $Fuentes) {
    if (-not $porNombre.ContainsKey($f.Nombre)) { $porNombre[$f.Nombre] = $f.Rel }
    foreach ($m in [regex]::Matches($f.Codigo, $rxBean)) {
      $n = $m.Groups['nombre'].Value
      if (-not $beans.ContainsKey($n)) { $beans[$n] = [pscustomobject]@{ Tipo = (($m.Groups['tipo'].Value -split '\.')[-1]); Rel = $f.Rel } }
    }
  }
  return [pscustomobject]@{ PorNombre = $porNombre; Beans = $beans }
}

# El fichero de un nombre de una pieza de un step de $F, por este orden: (a) la clase N, o n con la primera en mayuscula; (b) un metodo @Bean n: la clase de su
# tipo de vuelta por (a) o, si no esta, el fichero del metodo; (c) un campo o parametro 'Tipo n' de $F: Tipo por (a). '' si no se resuelve.
function Resolve-NombreRevision([string]$N, $F, $Res) {
  foreach ($c in @($N, ($N.Substring(0, 1).ToUpperInvariant() + $N.Substring(1)))) {
    if ($Res.PorNombre.ContainsKey($c)) { return $Res.PorNombre[$c] }
  }
  if ($Res.Beans.ContainsKey($N)) {
    $b = $Res.Beans[$N]
    if ($Res.PorNombre.ContainsKey($b.Tipo)) { return $Res.PorNombre[$b.Tipo] }
    return $b.Rel
  }
  foreach ($m in [regex]::Matches($F.Codigo, '\b(?:[a-z]\w*\.)*(?<tipo>[A-Z]\w*)\s*(?:<[^;{}()]*>)?\s+' + [regex]::Escape($N) + '\s*[;,)=]')) {
    if ($Res.PorNombre.ContainsKey($m.Groups['tipo'].Value)) { return $Res.PorNombre[$m.Groups['tipo'].Value] }
  }
  return ''
}

# Las unidades de revision de $Dir (el worktree de rescate) en orden estable: primero los steps (por ruta del fichero y orden dentro de el), despues los ficheros
# sueltos (por ruta). $Base es la rama del usuario y $Candidatas son rutas relativas (src/main/java/...) de clases candidatas a codigo muerto.
function Get-UnidadesRevision([string]$Dir, [string]$Base, [bool]$Todo, [string[]]$Candidatas) {
  $fuentes = @(Get-FuentesRevision $Dir)
  $res = Get-ResolucionRevision $fuentes
  $cambiados = Get-CambiadosRevision $Dir $Base
  $cands = @($Candidatas | Where-Object { $_ } | ForEach-Object { $_ -replace '\\', '/' })
  $enAlcance = @{}
  foreach ($f in $fuentes) {
    if ($Todo -or $cambiados.ContainsKey($f.Rel) -or ($cands -ccontains $f.Rel) -or (Test-PapelRevision $f.Codigo)) { $enAlcance[$f.Rel] = $true }
  }
  $crudas = @()
  $enStep = @{}
  foreach ($f in $fuentes) {
    foreach ($s in @(Get-StepsFichero $f)) {
      $ficheros = @($f.Rel)
      $sin = @()
      foreach ($n in $s.Nombres) {
        $r = Resolve-NombreRevision $n $f $res
        if ($r) { if ($ficheros -cnotcontains $r) { $ficheros += $r } }
        elseif ($sin -cnotcontains $n) { $sin += $n }
      }
      $ficheros = @($ficheros | Select-Object -First ([int]$Cfg.RevisionFicherosMax))
      foreach ($x in $ficheros) { $enStep[$x] = $true }
      $crudas += [pscustomobject]@{ tipo = 'step'; nombre = $s.Nombre; ficheros = $ficheros; sinResolver = $sin }
    }
  }
  foreach ($f in $fuentes) {
    if ($enAlcance.ContainsKey($f.Rel) -and -not $enStep.ContainsKey($f.Rel)) { $crudas += [pscustomobject]@{ tipo = 'fichero'; nombre = $f.Nombre; ficheros = @($f.Rel); sinResolver = @() } }
  }
  $usados = @{}
  $unidades = @()
  foreach ($u in $crudas) {
    $base = 'revision-' + (Get-NombreJob $u.nombre)
    $id = $base
    $k = 1
    while ($usados.ContainsKey($id)) { $k++; $id = "$base-$k" }
    $usados[$id] = $true
    $unidades += [pscustomobject]@{ id = $id; tipo = $u.tipo; nombre = $u.nombre; ficheros = @($u.ficheros); sinResolver = @($u.sinResolver) }
  }
  return $unidades
}

# ================================ TAREAS ================================
# Una tarea revision-flujo por unidad. La huella lleva las claves de los ficheros de la unidad (Get-ClaveFichero: su blob en HEAD), el hash de la plantilla, las
# candidatas de la unidad y los ids del catalogo; el commit y el $Todo van en las entradas, fuera de la huella, y una tarea que se reutiliza los pone a los de ahora.
# Las entradas llevan 'ficheros' y no 'fichero': Invoke-Ronda leeria del original el que se llame fichero.
function Get-TareasRevision([string]$Dir, [string]$Base, [bool]$Todo, [string[]]$Candidatas, [bool]$ConservarAtascadas) {
  $unidades = @(Get-UnidadesRevision $Dir $Base $Todo $Candidatas)
  $blobs = Get-BlobsHead $Dir
  $head = Get-Head $Dir
  if ($head.Length -gt 7) { $head = $head.Substring(0, 7) }
  $plantilla = Get-Hash8 (Get-Plantilla 'revision-flujo')
  $ids = (@(Get-ReglasRevision | ForEach-Object { $_.id }) -join ',')
  $cands = @($Candidatas | Where-Object { $_ } | ForEach-Object { $_ -replace '\\', '/' })
  $tareas = @()
  foreach ($u in $unidades) {
    $claves = @($u.ficheros | ForEach-Object { Get-ClaveFichero $blobs $Dir $_ })
    $suyas = @($u.ficheros | Where-Object { $cands -ccontains $_ })
    $entradas = [pscustomobject]@{
      unidad = $u.nombre; tipoUnidad = $u.tipo; ficheros = @($u.ficheros); candidatas = $suyas; sinResolver = @($u.sinResolver)
      huella = (Get-Hash8 (($claves -join ',') + '|' + $plantilla + '|' + ($suyas -join ',') + '|' + $ids)); commit = $head; todo = $Todo
    }
    $r = Restore-Tarea (New-TareaTipo 'revision-flujo' $u.id $u.id 'datos/revision.json' $entradas) $ConservarAtascadas
    if ($r.entradas.commit -cne $head -or [bool]$r.entradas.todo -ne $Todo) {
      $r.entradas.commit = $head
      $r.entradas.todo = $Todo
      Save-Tarea $r
    }
    $tareas += , $r
  }
  return $tareas
}

# ============================ COMPROBACION ============================
# Un hallazgo de lo que ha escrito Copilot ($Pre es como se llama en los motivos): Motivo '' y su ficha en Hallazgo si vale; si no, el motivo por el que se descarta.
function Test-Hallazgo($H, [string]$Pre, $T, [string]$Dir, $Catalogo) {
  $no = { param($m) return [pscustomobject]@{ Motivo = $m; Hallazgo = $null } }
  if ($H -isnot [System.Management.Automation.PSCustomObject]) { return (& $no "$Pre no es un objeto con regla, fichero, linea, cita y texto.") }
  $regla = @($Catalogo | Where-Object { $_.id -ceq $H.regla })
  if ($regla.Count -eq 0) { return (& $no "${Pre}: la regla '$($H.regla)' no esta en el catalogo.") }
  if (@($T.entradas.ficheros) -cnotcontains $H.fichero) { return (& $no "${Pre}: el fichero '$($H.fichero)' no es de la unidad.") }
  $m = Test-LineaCita $H $Pre
  if ($m) { return (& $no $m) }
  if (-not (Test-Texto $H.texto)) { return (& $no "$Pre.texto falta o esta vacio.") }
  $ficha = [ordered]@{ regla = $H.regla; fichero = $H.fichero; linea = [int]$H.linea; cita = $H.cita; texto = $H.texto; probado = $false }
  $ruta = Join-Ruta $Dir $H.fichero
  if (-not (Test-Path -LiteralPath $ruta -PathType Leaf) -or @(Set-CitasProbadas @($ficha) $ruta).Count -gt 0) {
    return (& $no "${Pre}: la cita no sale en el fichero $($H.fichero). Copia la cita tal cual de la linea del codigo.")
  }
  if (@($regla[0].tokens | Where-Object { $H.cita.Contains($_) }).Count -eq 0) {
    return (& $no "${Pre}: la cita no lleva ninguno de los tokens de la regla $($H.regla) ($((@($regla[0].tokens) | ForEach-Object { "'$_'" }) -join ', ')).")
  }
  if ($H.regla -ceq 'CAND-MUERTA' -and @($T.entradas.candidatas) -cnotcontains $H.fichero) { return (& $no "${Pre}: CAND-MUERTA solo vale en una de las candidatas de la unidad.") }
  return [pscustomobject]@{ Motivo = ''; Hallazgo = [pscustomobject]$ficha }
}

# Comprueba lo que ha escrito Copilot en .rescate\tareas\<id>.json: un objeto con 'hallazgos' (una lista, vacia vale). Cada hallazgo se descarta (no invalida) si no se
# puede comprobar (Test-Hallazgo); si se descarta mas de la mitad (y hay al menos 2), es invalida con el motivo del primer descarte. Se quedan los 5 primeros validos.
function Test-Revision($T, [string]$Dir) {
  $s = Read-Salida $T $Dir
  if (-not $s.Ok) { return $s }
  if ($s.Ficha.hallazgos -isnot [array]) { return (New-Resultado $false "Falta el campo 'hallazgos': una lista, vacia si no hay nada que decir." $null) }
  $catalogo = @(Get-ReglasRevision)
  $validos = @()
  $descartados = @()
  $i = 0
  foreach ($h in $s.Ficha.hallazgos) {
    $v = Test-Hallazgo $h "hallazgos[$i]" $T $Dir $catalogo
    $i++
    if ($v.Hallazgo) { $validos += $v.Hallazgo; continue }
    $regla = ''
    $fichero = ''
    if ($h -is [System.Management.Automation.PSCustomObject]) { $regla = "$($h.regla)"; $fichero = "$($h.fichero)" }
    $descartados += [pscustomobject]@{ regla = $regla; fichero = $fichero; motivo = $v.Motivo }
  }
  $total = $validos.Count + $descartados.Count
  if ($total -ge 2 -and ($descartados.Count * 2) -gt $total) {
    return (New-Resultado $false "Mas de la mitad de los hallazgos ($($descartados.Count) de $total) no valen. El primero: $($descartados[0].motivo) Usa solo reglas del catalogo, ficheros de la unidad y citas copiadas tal cual del codigo." $null)
  }
  $max = [int]$Cfg.RevisionHallazgosMax
  return (New-Resultado $true '' ([pscustomobject][ordered]@{ hallazgos = @($validos | Select-Object -First $max); descartados = @($descartados); sobran = [math]::Max(0, $validos.Count - $max) }))
}

# ================================ SALIDA ================================
# Los hallazgos de las tareas hechas para revision.json, en orden de unidad (el de las tareas), de fichero dentro de la unidad y de linea, y uno solo por regla,
# fichero y linea: un fichero que esta en dos steps sale en las dos unidades con el mismo hallazgo, y se queda el de la primera.
function Get-HallazgosRevision($Tareas) {
  $titulos = @{}
  foreach ($r in @(Get-ReglasRevision)) { $titulos[$r.id] = $r.titulo }
  $vistos = New-Object 'System.Collections.Generic.HashSet[string]'
  $lista = @()
  foreach ($t in @($Tareas | Where-Object { $_.estado -eq 'hecha' })) {
    $orden = @($t.entradas.ficheros)
    $suyos = @()
    $n = 0
    foreach ($h in $t.resultado.hallazgos) { $suyos += [pscustomobject]@{ H = $h; F = [array]::IndexOf($orden, [string]$h.fichero); L = [int]$h.linea; N = $n }; $n++ }
    foreach ($x in @($suyos | Sort-Object F, L, N)) {
      $h = $x.H
      if (-not $vistos.Add("$($h.regla)|$($h.fichero)|$([int]$h.linea)")) { continue }
      $lista += [ordered]@{ regla = $h.regla; titulo = $titulos[[string]$h.regla]; fichero = $h.fichero; linea = [int]$h.linea; cita = $h.cita; texto = $h.texto; unidad = $t.id; probado = $true }
    }
  }
  return $lista
}

# Cuantos hallazgos (los que quedan en revision.json) y cuantos descartados llevan las tareas hechas de $Tareas.
function Get-CuentasRevision($Tareas) {
  $d = 0
  foreach ($t in @($Tareas | Where-Object { $_.estado -eq 'hecha' })) { foreach ($x in $t.resultado.descartados) { $d++ } }
  return [pscustomobject]@{ Hallazgos = @(Get-HallazgosRevision $Tareas).Count; Descartados = $d }
}

# Escribe datos\revision.json con lo de las tareas hechas (Get-HallazgosRevision). Sin tareas hechas, los hallazgos van vacios y quedan las cuentas.
function Save-Revision($Tareas) {
  $todas = @($Tareas | Where-Object { $null -ne $_ })
  $cuentas = Get-CuentasTareas $todas
  $commit = ''
  $todo = $false
  if ($todas.Count -gt 0) { $commit = [string]$todas[0].entradas.commit; $todo = [bool]$todas[0].entradas.todo }
  Write-Json (Join-Path $Datos 'revision.json') ([ordered]@{
      commit = $commit; todo = $todo; unidades = $todas.Count; hechas = $cuentas.hecha; atascadas = $cuentas.atascada
      reglas = @(Get-ReglasRevision | ForEach-Object { [ordered]@{ id = $_.id; titulo = $_.titulo } })
      hallazgos = @(Get-HallazgosRevision $todas); descartados = (Get-CuentasRevision $todas).Descartados
    })
}

function Get-AvisoRevision($Tareas) {
  $todas = @($Tareas | Where-Object { $null -ne $_ })
  $steps = @($todas | Where-Object { $_.entradas.tipoUnidad -ceq 'step' }).Count
  $llamadas = @($todas | Where-Object { $_.estado -eq 'pendiente' }).Count
  return "Revision por flujos: $($todas.Count) unidades ($steps steps y $($todas.Count - $steps) ficheros sueltos), unas $llamadas llamadas (las ya hechas con la misma huella no se repiten), hasta $([int]$Cfg.Paralelo) a la vez."
}

function Get-LineaRevision($Tareas) {
  $todas = @($Tareas | Where-Object { $null -ne $_ })
  $n = Get-CuentasTareas $todas
  $c = Get-CuentasRevision $todas
  return "Revision por flujos: $($n.hecha) hechas, $($n.atascada) atascadas, $($n.pendiente) pendientes; $($c.Hallazgos) hallazgos ($($c.Descartados) descartados por no poder comprobarlos)."
}
