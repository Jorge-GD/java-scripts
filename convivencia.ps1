<#
convivencia.ps1 - Dice, por cada job, si en pre se pueden lanzar el batch viejo y el nuevo a la vez o hay que lanzarlos uno detras de otro, sin IA
(pieza C2). No se ejecuta solo: solo funciones. Se carga con '. (Join-Path $PSScriptRoot 'convivencia.ps1')' despues de comun.ps1, tareas.ps1,
lanzadores.ps1 y practicas.ps1 (Write-Json, Read-Json, Get-NombreJob, Get-LineasShell, Get-JavaSinComentarios, Get-JavaFiles, Get-TablasSql, Get-Rel,
Join-Ruta). Solo ASCII: los textos con tilde van como \uXXXX y salen por Get-TextoEs. Vale para Windows PowerShell 5.1 y para PowerShell 7.

  Invoke-Convivencia <original> <migrado> <datos>
      Escribe <datos>\convivencia.json y dice una linea en la consola. Nunca lanza una excepcion ni para. Sin <datos>\mapa.json no escribe nada.
      convivencia.json = { jobs: [ { job, veredicto, motivos[], reponer[] } ], fijos: { batch, serie[], aLaVez } }, con los jobs en el orden de mapa.json.

LA REGLA es 'uno detras de otro' salvo prueba de lo contrario: un falso 'a la vez' estropea datos de pre y un falso 'uno detras de otro' solo cuesta
tiempo. El veredicto es a-la-vez si el job no tiene ningun motivo y en-serie en cualquier otro caso.

QUE MIRA, por job (cada motivo lleva categoria, lado, fichero, linea, cita, texto y ia; los de categoria tabla, ademas, las tablas que nombra el SQL)
  original   las clases del job segun mapa.json, en el codigo Java sin comentarios ni cadenas (el SQL se busca dentro de las cadenas) y sin los import
  migrado    todo src/main/java del worktree de rescate: no se sabe de que job es cada clase, y el texto lo dice
  lanzador   el inventario de datos\lanzadores.json de los lanzadores enlazados con el job (el mismo inventario sin IA de lanzadores.ps1)
  ficha      produce y conexiones de datos\jobs\<job>.json (ia = true: lo leyo la IA); no se repite un motivo que el codigo ya da del mismo fichero
  Varias apariciones de lo mismo en el mismo fichero dan un motivo: el de la primera linea. Lo que no se puede leer (la ficha del job, una clase, el
  src/main/java del migrado) da un motivo sin-datos: no se sabe lo que toca, y eso tambien es uno detras de otro.
  Categorias: tabla, fichero, consume, sftp, mongo, correo, mensajes, http, cerrojo y sin-datos.
#>

# ============================== TEXTOS ==============================
# Un texto con \uXXXX (las tildes) tal como lo ve la persona.
function Get-TextoEs([string]$Ascii) { return [regex]::Unescape($Ascii) }

# La linea de codigo como cita: sin blancos a los lados y como mucho 160 caracteres.
function Get-Cita([string]$Linea) {
  $t = $Linea.Trim()
  if ($t.Length -gt 160) { $t = $t.Substring(0, 160) }
  return $t
}

# El texto de un motivo: lo que hace (categoria) y de donde sale (lado: original, migrado, lanzador o ficha).
function Get-TextoMotivo([string]$Categoria, [string]$Lado) {
  if ($Categoria -ceq 'cerrojo') { return 'comparten cerrojo: el segundo no arranca mientras el primero corre' }
  $que = @{
    tabla = 'escribe en una tabla'; fichero = 'escribe un fichero'; consume = 'mueve o borra ficheros'
    sftp = 'env\u00eda o cambia ficheros en un servidor (SFTP, SCP o FTP)'; mongo = 'escribe en Mongo'; correo = 'env\u00eda correos'
    mensajes = 'env\u00eda mensajes a una cola o a un tema'; http = 'llama a un servicio externo que puede cambiar datos'
  }
  $donde = @{
    original = ', en el original'; migrado = ', en el migrado (no s\u00e9 de qu\u00e9 job)'; lanzador = ', en el lanzador'; ficha = ', seg\u00fan la ficha del job'
  }
  return (Get-TextoEs ([string]$que[$Categoria] + [string]$donde[$Lado]))
}

# Lo que vale para todos los jobs, en el JSON y en la pagina.
function Get-FijosConvivencia {
  return [ordered]@{
    batch = (Get-TextoEs 'El viejo (Spring Batch 4) y el nuevo (Spring Batch 5 o 6) no pueden compartir las tablas BATCH_: Spring Batch 5 cambi\u00f3 las columnas de BATCH_JOB_EXECUTION_PARAMS. En pre, el nuevo necesita su propio esquema o prefijo de tablas. Si el viejo est\u00e1 planificado en pre, p\u00e1ralo mientras pruebas el nuevo.')
    serie = @(
      (Get-TextoEs 'Lanza el viejo con las entradas del caso.')
      (Get-TextoEs 'Guarda lo que deja: ficheros, las filas de las tablas que escribe y los correos.')
      (Get-TextoEs 'Rep\u00f3n lo de \u00abqu\u00e9 reponer\u00bb.')
      (Get-TextoEs 'Lanza el nuevo con las mismas entradas y par\u00e1metros.')
      (Get-TextoEs 'Compara lo que deja cada uno.')
    )
    aLaVez = (Get-TextoEs 'Ninguno de los dos escribe nada que el otro lea: puedes lanzarlos a la vez con las mismas entradas y comparar lo que deja cada uno.')
  }
}

function New-Motivo([string]$Categoria, [string]$Lado, [string]$Fichero, [int]$Linea, [string]$Cita, [string]$Texto, [bool]$Ia = $false) {
  return [ordered]@{ categoria = $Categoria; lado = $Lado; fichero = $Fichero; linea = $Linea; cita = $Cita; texto = $Texto; ia = $Ia }
}

# ============================== CODIGO JAVA ==============================
# Los nombres con los que el codigo llama a un objeto de tipo $Tipo, como alternativa de regex: los declarados ('Tipo x', 'x = (Tipo) ...') y
# cualquiera que acabe en el nombre del tipo (mongoTemplate, secondaryMongoTemplate...).
function Get-Receptores([string]$Texto, [string]$Tipo) {
  $t = [regex]::Escape($Tipo)
  $n = @([regex]::Matches($Texto, "\b$t\s+(\w+)") | ForEach-Object { [regex]::Escape($_.Groups[1].Value) })
  $n += @([regex]::Matches($Texto, "\b(\w+)\s*=\s*\(\s*$t\s*\)") | ForEach-Object { [regex]::Escape($_.Groups[1].Value) })
  $n += "(?i:\w*$t)"
  return (@($n | Select-Object -Unique) -join '|')
}

# Las reglas de un codigo Java (sin comentarios ni cadenas): categoria y regex. Las llamadas a un metodo se miran sobre el objeto que las recibe, para
# que repo.save( no se confunda con mongoTemplate.save( ni restTemplate.delete( con repo.delete(.
function Get-ReglasJava([string]$Codigo) {
  $mongo = Get-Receptores $Codigo 'MongoTemplate'
  $sftp = Get-Receptores $Codigo 'ChannelSftp'
  $rest = Get-Receptores $Codigo 'RestTemplate'
  $web = Get-Receptores $Codigo 'WebClient'
  $http = "$rest|$web"
  $ajenos = "Files|$mongo|$http"
  $reglas = @(
    @('tabla', '\b(?:JdbcBatchItemWriter|JpaItemWriter|HibernateItemWriter|RepositoryItemWriter)'),
    @('tabla', "(?<!\b(?:$ajenos)\s*)\.\s*(?:save|saveAll|deleteAll|deleteById)\s*\("),
    @('tabla', "(?<!\b(?:$ajenos)\s*)\.\s*delete\s*\(\s*[^)\s]"),
    @('tabla', '(?i)\w*jdbcTemplate\s*\.\s*update\s*\('),
    @('tabla', '\.\s*batchUpdate\s*\('),
    @('fichero', '\b(?:FlatFileItemWriter|StaxEventItemWriter|JsonFileItemWriter)'),
    @('fichero', '\bFiles\s*\.\s*(?:writeString|write|newBufferedWriter|newOutputStream|copy)\s*\('),
    @('fichero', '\b(?:FileWriter|FileOutputStream)\b'),
    @('consume', '\bFiles\s*\.\s*(?:move|deleteIfExists|delete)\s*\('),
    @('consume', '\.\s*renameTo\s*\('),
    @('consume', "(?<!\b(?:$http)\s*)\.\s*delete\s*\(\s*\)"),
    @('sftp', "\b(?:$sftp)\s*\.\s*(?:put|rename|rm|mkdir)\s*\("),
    @('sftp', '\bSftpRemoteFileTemplate\b'),
    @('mongo', "\b(?:$mongo)\s*\.\s*(?:insert|save|update\w*|upsert|remove|findAndModify|findAndRemove)\s*\("),
    @('mongo', '\bMongoItemWriter'),
    @('correo', '\b(?:JavaMailSender|MimeMessage|SimpleMailMessage)\b'),
    @('mensajes', '\b(?:KafkaTemplate|JmsTemplate|RabbitTemplate|StreamBridge)\b'),
    @('http', "\b(?:$rest)\s*\.\s*(?:postFor\w*|put|delete|exchange|patchFor\w*)\s*\("),
    @('http', "\b(?:$web)\s*\.\s*(?:post|put|delete|patch)\s*\(\s*\)")
  )
  return @($reglas | ForEach-Object { [pscustomobject]@{ Categoria = $_[0]; Regex = $_[1] } })
}

# Un motivo por categoria de un .java ($Ruta; $Rel es su ruta para el JSON): el de su primera linea. Las tablas que nombra el SQL de sus cadenas
# (INSERT INTO, UPDATE ... SET, DELETE FROM, MERGE INTO, TRUNCATE TABLE) van en 'tablas' de su motivo tabla, las de todas las lineas. Si no se lee,
# un motivo sin-datos.
function Get-MotivosJava([string]$Ruta, [string]$Rel, [string]$Lado) {
  try { $crudo = [System.IO.File]::ReadAllText($Ruta) }
  catch { return @(New-Motivo 'sin-datos' $Lado $Rel 0 '' (Get-TextoEs "no s\u00e9 lo que toca: no he podido leer esta clase del $Lado")) }
  $lineas = @($crudo -split "`n")
  $conCadenas = Get-JavaSinComentarios $crudo
  $codigo = Get-JavaSinComentarios $crudo -SinCadenas
  $codigo = [regex]::Replace($codigo, '(?m)^[ \t]*(?:import|package)\b[^\n]*', { param($m) ' ' * $m.Length })
  $hallados = New-Object System.Collections.Generic.List[object]
  foreach ($r in @(Get-ReglasJava $codigo)) {
    $m = [regex]::Match($codigo, $r.Regex)
    if ($m.Success) { $hallados.Add([pscustomobject]@{ Categoria = $r.Categoria; Indice = $m.Index }) }
  }
  $tablas = New-Object System.Collections.Generic.List[string]
  foreach ($cadena in [regex]::Matches($conCadenas, '"""[\s\S]*?"""|"(?:\\.|[^"\\\n])*"')) {
    foreach ($v in [regex]::Matches($cadena.Value, '(?i)\b(?:INSERT\s+INTO|MERGE\s+INTO|DELETE\s+FROM|TRUNCATE\s+TABLE|UPDATE(?=\s+[^;]*?\bSET\b))')) {
      $hallados.Add([pscustomobject]@{ Categoria = 'tabla'; Indice = $cadena.Index + $v.Index })
      # la tabla del verbo es la primera que da Get-TablasSql, si el nombre sigue al verbo
      $t = @(Get-TablasSql $cadena.Value.Substring($v.Index))
      if ($t.Count -gt 0 -and $t[0].indice -ge $v.Length -and $cadena.Value.Substring($v.Index + $v.Length, $t[0].indice - $v.Length).Trim().Length -eq 0 -and -not $tablas.Contains($t[0].tabla)) { $tablas.Add($t[0].tabla) }
    }
  }
  $res = @()
  foreach ($g in @($hallados | Group-Object Categoria)) {
    $i = @($g.Group | ForEach-Object { $_.Indice } | Sort-Object)[0]
    $n = @($codigo.Substring(0, $i) -split "`n").Count
    $cita = ''
    if ($n -le $lineas.Count) { $cita = Get-Cita $lineas[$n - 1] }
    $m = New-Motivo $g.Name $Lado $Rel $n $cita (Get-TextoMotivo $g.Name $Lado)
    if ($g.Name -ceq 'tabla') { $m['tablas'] = @($tablas) }
    $res += [pscustomobject]@{ Indice = $i; Motivo = $m }
  }
  return @($res | Sort-Object Indice | ForEach-Object { $_.Motivo })
}

# Los motivos del migrado, una vez para todos los jobs: todo src/main/java del worktree (en orden de ruta). No se sabe de que job es cada clase.
function Get-MotivosMigrado([string]$Migrado) {
  $java = Join-Ruta $Migrado 'src/main/java'
  if (-not (Test-Path -LiteralPath $java)) { return @(New-Motivo 'sin-datos' 'migrado' '' 0 '' (Get-TextoEs 'no s\u00e9 lo que toca el migrado: no hay src/main/java')) }
  $rutas = [string[]]@(Get-JavaFiles $java | ForEach-Object { $_.FullName })
  [System.Array]::Sort($rutas, [System.StringComparer]::Ordinal)
  $res = @()
  foreach ($f in $rutas) { $res += @(Get-MotivosJava $f (Get-Rel $Migrado $f) 'migrado') }
  return $res
}

# ============================== LANZADORES Y FICHAS ==============================
# Los motivos de un lanzador de datos\lanzadores.json: de cada orden de su inventario (fichero y envio) y de su cerrojo, uno por categoria.
function Get-MotivosLanzador($Lanzador) {
  $categoria = @{
    cp = 'fichero'; touch = 'fichero'; gzip = 'fichero'; zip = 'fichero'; tar = 'fichero'; mv = 'consume'; rm = 'consume'
    sftp = 'sftp'; scp = 'sftp'; ftp = 'sftp'; mail = 'correo'; mailx = 'correo'; sendmail = 'correo'; curl = 'http'
  }
  $lineas = @()
  try { if (Test-Path -LiteralPath ([string]$Lanzador.ruta)) { $lineas = @(Get-LineasShell ([string]$Lanzador.ruta)) } } catch { $lineas = @() }
  $vistas = @{}
  $res = @()
  foreach ($it in @($Lanzador.inventario | Where-Object { $null -ne $_ })) {
    $cats = @()
    if ($it.tipo -ceq 'cerrojo') { $cats += 'cerrojo' }
    elseif ($it.tipo -ceq 'fichero' -or $it.tipo -ceq 'envio') { foreach ($o in @(([string]$it.detalle) -split ',')) { if ($categoria.ContainsKey($o)) { $cats += $categoria[$o] } } }
    foreach ($c in @($cats | Select-Object -Unique)) {
      if ($vistas.ContainsKey($c)) { continue }
      $vistas[$c] = $true
      $n = [int]$it.linea
      $cita = ''
      if ($n -ge 1 -and $n -le $lineas.Count) { $cita = Get-Cita $lineas[$n - 1] }
      $res += (New-Motivo $c 'lanzador' ([string]$Lanzador.rel) $n $cita (Get-TextoMotivo $c 'lanzador'))
    }
  }
  return $res
}

# Los motivos de la ficha del job: sus datos de produce y conexiones (tabla-escribe, salida-fichero, sftp y externo), con la marca de IA.
function Get-MotivosFicha($Ficha) {
  $categoria = @{ 'tabla-escribe' = 'tabla'; 'salida-fichero' = 'fichero'; 'sftp' = 'sftp'; 'externo' = 'http' }
  $res = @()
  foreach ($d in @(@($Ficha.produce) + @($Ficha.conexiones) | Where-Object { $null -ne $_ })) {
    $c = $categoria[[string]$d.tipo]
    if (-not $c) { continue }
    $res += (New-Motivo $c 'original' ([string]$d.fichero) ([int]$d.linea) (Get-Cita ([string]$d.cita)) (Get-TextoMotivo $c 'ficha') $true)
  }
  return $res
}

# Que dejar como estaba entre una ejecucion y la otra, sin repetir: las entradas que mueve o borra (consume), las tablas que nombra el SQL y las colecciones de Mongo.
function Get-ReponerJob($Motivos) {
  $res = New-Object System.Collections.Generic.List[string]
  $textos = New-Object System.Collections.Generic.List[string]
  foreach ($m in $Motivos) {
    if ($m.categoria -ceq 'consume') {
      $donde = [string]$m.cita
      if (-not $donde) { $donde = "$($m.fichero):$($m.linea)" }
      $textos.Add($donde + (Get-TextoEs ': mueve o borra ficheros. Antes de lanzar el segundo, vuelve a dejar sus entradas como estaban'))
    }
    elseif ($m.categoria -ceq 'tabla') {
      foreach ($t in @($m['tablas'])) { $textos.Add("la tabla $t" + (Get-TextoEs ': deja sus filas como estaban antes del primero (o compara solo lo que a\u00f1ade cada uno)')) }
    }
    elseif ($m.categoria -ceq 'mongo') { $textos.Add('las colecciones de Mongo que escribe: igual que las tablas') }
  }
  foreach ($t in $textos) { if (-not $res.Contains($t)) { $res.Add($t) } }
  return $res.ToArray()
}

# ============================== ENTRADA ==============================
function Invoke-Convivencia([string]$Original, [string]$Migrado, [string]$Datos) {
  $rutaMapa = Join-Path $Datos 'mapa.json'
  $salida = Join-Path $Datos 'convivencia.json'
  if (-not (Test-Path -LiteralPath $rutaMapa)) { Info 'Convivencia: no hay datos\mapa.json: no se mide.'; return }
  try {
    $mapa = Read-Json $rutaMapa
    $lanzadores = @()
    $rutaLanz = Join-Path $Datos 'lanzadores.json'
    if (Test-Path -LiteralPath $rutaLanz) { $lanzadores = @((Read-Json $rutaLanz).lanzadores | Where-Object { $null -ne $_ }) }
    $delMigrado = @(Get-MotivosMigrado $Migrado)
    $delOriginal = @{}
    $jobs = @()
    foreach ($j in @($mapa.jobs | Where-Object { $null -ne $_ })) {
      $motivos = @()
      $rutaFicha = Join-Ruta $Datos ('jobs/' + (Get-NombreJob ([string]$j.job)) + '.json')
      $ficha = $null
      if (Test-Path -LiteralPath $rutaFicha) { try { $ficha = Read-Json $rutaFicha } catch { $ficha = $null } }
      if (-not $ficha -or [string]$ficha.redaccion -cne 'hecha') { $motivos += (New-Motivo 'sin-datos' 'original' '' 0 '' (Get-TextoEs 'no s\u00e9 lo que toca: la ficha del job no est\u00e1 hecha')) }
      foreach ($rel in @(@($j.clases | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_.fichero }) | Select-Object -Unique)) {
        if (-not $delOriginal.ContainsKey($rel)) { $delOriginal[$rel] = @(Get-MotivosJava (Join-Ruta $Original $rel) $rel 'original') }
        $motivos += $delOriginal[$rel]
      }
      $motivos += $delMigrado
      foreach ($z in @($lanzadores | Where-Object { @($_.jobs) -ccontains [string]$j.job })) { $motivos += @(Get-MotivosLanzador $z) }
      if ($ficha) {
        foreach ($f in @(Get-MotivosFicha $ficha)) {
          if (@($motivos | Where-Object { $_.categoria -ceq $f.categoria -and $_.lado -ceq 'original' -and $_.fichero -ceq $f.fichero }).Count -eq 0) { $motivos += $f }
        }
      }
      $veredicto = 'en-serie'
      if ($motivos.Count -eq 0) { $veredicto = 'a-la-vez' }
      $jobs += [ordered]@{ job = [string]$j.job; veredicto = $veredicto; motivos = @($motivos); reponer = @(Get-ReponerJob $motivos) }
    }
    Write-Json $salida ([ordered]@{ jobs = $jobs; fijos = (Get-FijosConvivencia) })
    $aLaVez = @($jobs | Where-Object { $_.veredicto -ceq 'a-la-vez' }).Count
    Info "Convivencia: $($jobs.Count) jobs, $aLaVez a la vez y $($jobs.Count - $aLaVez) uno detras de otro (datos\convivencia.json)."
  }
  catch {
    Remove-Item -LiteralPath $salida -Force -ErrorAction SilentlyContinue
    Info ('Convivencia: no se pudo medir (' + $_.Exception.Message + ').')
  }
}
