<#
probar-arreglo-propiedades.ps1 - Banco de pruebas de arreglo-propiedades.ps1 (C6b: poner en el yml del migrado las propiedades del original que faltan, con
una llamada a Copilot). Usa el Copilot de mentira tests/falsos/c6b-copilot.ps1 (un plan por llamada), el Maven de mentira tests/falsos/c6-mvn.ps1 (solo lo
llama propiedades.ps1, para el classpath de los metadatos de Spring) y un Invoke-DiagnosticoMotor de mentira que escribe diagnostico-propiedades.md con el
estado que pida cada prueba. Nunca llama al Copilot ni al Maven reales. Datos inventados (com.acme, batch-recibos).
Vale para Windows PowerShell 5.1 y para PowerShell 7. Solo ASCII a proposito.

  .\tests\probar-arreglo-propiedades.ps1                       # todas las pruebas
  .\tests\probar-arreglo-propiedades.ps1 -Solo cache           # las que llevan 'cache' en el nombre
  .\tests\probar-arreglo-propiedades.ps1 -Dir D:\tmp\x -Conservar

Sale con 0 si todo pasa y con 1 si algo falla.
#>
param(
  [string]$Dir = '',
  [string]$Solo = '',
  [switch]$Conservar
)
$ErrorActionPreference = 'Stop'
$aqui = Split-Path -Parent $MyInvocation.MyCommand.Path
$raiz = Split-Path -Parent $aqui
$falsos = Join-Path $aqui 'falsos'
. (Join-Path $aqui 'comun-banco.ps1')
. (Join-Path $raiz 'comun.ps1')
. (Join-Path $raiz 'tareas.ps1')
. (Join-Path $raiz 'informe.ps1')
. (Join-Path $raiz 'propiedades.ps1')
. (Join-Path $raiz 'arreglo-propiedades.ps1')
Add-Type -AssemblyName System.IO.Compression.FileSystem
$Cfg.CopilotExe = Join-Path $falsos 'c6b-copilot.ps1'
$Cfg.MvnExe = Join-Path $falsos 'c6-mvn.ps1'
$Cfg.SegundosPorLlamada = 120
$Cfg.SegundosLatido = 0

# ================================ UTILIDADES ================================
$RR = 'src/main/resources/'
$Yml = $RR + 'application.yml'
$Secreto = 'SECRETO-INVENTADO-42'

function Pom { return "<project><modelVersion>4.0.0</modelVersion><groupId>com.acme</groupId><artifactId>batch-recibos</artifactId><version>1</version></project>`n" }

# Un jar de prueba: un zip con el spring-configuration-metadata.json que dice que spring.batch.initialize-schema ahora es spring.batch.jdbc.initialize-schema.
$MetaSpring = '{"groups":[],"properties":[{"name":"spring.batch.initialize-schema","deprecation":{"level":"error","replacement":"spring.batch.jdbc.initialize-schema"}},{"name":"spring.batch.jdbc.initialize-schema","type":"java.lang.String"}]}'
function Nuevo-Jar([string]$Ruta) {
  [void](New-Item -ItemType Directory -Path (Split-Path $Ruta -Parent) -Force)
  $zip = [System.IO.Compression.ZipFile]::Open($Ruta, 'Create')
  try {
    foreach ($par in @(@('com/acme/Falsa.class', 'x'), @('META-INF/spring-configuration-metadata.json', $MetaSpring))) {
      $w = New-Object System.IO.StreamWriter($zip.CreateEntry($par[0]).Open())
      try { $w.Write($par[1]) } finally { $w.Dispose() }
    }
  }
  finally { $zip.Dispose() }
}

# Un escenario: el original ($Legacy), el migrado ($Migrado, con su pom.xml, en un repo git en la rama rescate), la referencia, las carpetas de datos y
# de registros, el diagnostico de despues (compila y tests bien) y los planes del Copilot de mentira. Cada hashtable es ruta relativa -> texto.
function Nuevo-Escenario([string]$Nombre, [hashtable]$Legacy, [hashtable]$Migrado, $Ref = $null) {
  if ($null -eq $Ref) { $Ref = @{ ($Yml) = "app:`n  ejemplo: si`n" } }
  $r = Join-Path $Dir $Nombre
  if (Test-Path -LiteralPath $r) { Remove-Item -LiteralPath $r -Recurse -Force }
  $leg = Join-Path $r 'life-java8'
  $mig = Join-Path $r 'batch-recibos'
  $dirRef = Join-Path $r 'batch-ejemplo'
  foreach ($par in @(@($leg, $Legacy), @($mig, $Migrado), @($dirRef, $Ref))) {
    [void](New-Item -ItemType Directory -Path $par[0] -Force)
    foreach ($k in $par[1].Keys) { Escribe $par[0] $k $par[1][$k] }
  }
  Escribe $mig 'pom.xml' (Pom)
  Inicia-Repo $mig
  Set-Excluidos $mig
  [void](GitEn $mig @('checkout', '-q', '-b', 'rescate'))
  $e = [pscustomobject]@{
    Raiz = $r; Legacy = $leg; Repo = $mig; Ref = $dirRef; Datos = (Join-Path $r 'datos'); Registros = (Join-Path $r 'registros')
    Planes = (Join-Path $r 'planes'); Prompts = (Join-Path $r 'prompts'); Llamadas = (Join-Path $r 'copilot-llamadas.txt')
    Mvn = (Join-Path $r 'mvn-llamadas.txt'); Classpath = (Join-Path (Join-Path $r 'jars') 'dep.jar'); Iniciales = $Migrado
  }
  foreach ($d in @($e.Datos, $e.Registros, $e.Planes, $e.Prompts)) { [void](New-Item -ItemType Directory -Path $d -Force) }
  Nuevo-Jar $e.Classpath
  Escribe $e.Datos 'diagnostico-despues.md' "# Diagnostico`n`n- Estado: compila: SI | tests: OK`n"
  return $e
}

# El plan de la llamada $N del Copilot de mentira (ver c6b-copilot.ps1).
function Plan($E, [int]$N, [hashtable]$P) { [System.IO.File]::WriteAllText((Join-Path $E.Planes "$N.json"), (ConvertTo-Json -InputObject $P -Depth 8)) }

# Lo que pone migracion.ps1 y aqui se simula: la parada y el diagnostico (rescate.ps1 -Modo diagnostico), que escribe datos\diagnostico-<Cuando>.md con
# el estado que toque (una lista: cada llamada gasta uno y el ultimo se repite) o, con DiagCae, para como la parada 'motor' de verdad.
$script:Paradas = @()
$script:DiagEstados = @('compila: SI | tests: OK')
$script:DiagCae = $false
$script:DiagLlamadas = @()
function Set-Parada([string]$Motivo, [string]$Detalle, [string]$Registro) { $script:Paradas += , @($Motivo, $Detalle, $Registro) }
function Invoke-DiagnosticoMotor([string]$Cuando) {
  $script:DiagLlamadas += $Cuando
  if ($script:DiagCae) {
    Set-Parada 'motor' 'el diagnostico (rescate.ps1 -Modo diagnostico) ha salido con codigo 1: de mentira' (Join-Path $Registros "diagnostico-$Cuando.log")
    $script:Parada = $true
    return $false
  }
  $estado = $script:DiagEstados[0]
  if ($script:DiagEstados.Count -gt 1) { $script:DiagEstados = @($script:DiagEstados | Select-Object -Skip 1) }
  Escribe $Datos "diagnostico-$Cuando.md" "# Diagnostico`n`n- Estado: $estado`n"
  return $true
}

function Lee-Json([string]$Ruta) {
  if (-not (Test-Path -LiteralPath $Ruta)) { return $null }
  return ([System.IO.File]::ReadAllText($Ruta) | ConvertFrom-Json)
}

function Llamadas-De([string]$Fichero) {
  if (-not (Test-Path -LiteralPath $Fichero)) { return , @() }
  return , @([System.IO.File]::ReadAllLines($Fichero) | Where-Object { $_ })
}

# Invoke-FasePropiedades sobre el escenario, con los falsos y las variables del script que la carga. Devuelve lo que dijo (Sigue), la consola (Texto y
# Avisos), el JSON de resultados, la tarea guardada, los commits del migrado (el asunto de cada uno, el ultimo primero) y los estados que pidio al
# diagnostico (Diag: el Cuando de cada llamada).
function Fase($E, [bool]$Mantener = $true, [string[]]$Diag = @('compila: SI | tests: OK'), [bool]$Cae = $false) {
  $RepoRoot = $E.Repo
  $LegacyRoot = $E.Legacy
  $PlantillaRoot = $E.Ref
  $Datos = $E.Datos
  $Registros = $E.Registros
  $ModeloElegido = 'modelo-x'
  $script:Parada = $false
  $script:Paradas = @()
  $script:Todas = @()
  $script:DiagEstados = @($Diag)
  $script:DiagCae = $Cae
  $script:DiagLlamadas = @()
  $entorno = @{ C6B_PLANES = $E.Planes; C6B_LLAMADAS = $E.Llamadas; C6B_PROMPTS = $E.Prompts; C6_LLAMADAS = $E.Mvn; C6_CLASSPATH = $E.Classpath }
  foreach ($k in $entorno.Keys) { [Environment]::SetEnvironmentVariable($k, $entorno[$k]) }
  $salida = @(Invoke-FasePropiedades $Mantener 6>&1)
  $info = @($salida | Where-Object { $_ -is [System.Management.Automation.InformationRecord] })
  return [pscustomobject]@{
    Sigue = (@($salida | Where-Object { $_ -is [bool] })[0])
    Texto = (@($info | ForEach-Object { "$_" }) -join "`n")
    Avisos = @($info | Where-Object { "$($_.MessageData.ForegroundColor)" -ceq 'Yellow' } | ForEach-Object { "$_" })
    Json = (Lee-Json (Join-Path $E.Datos 'propiedades-arreglo.json'))
    Tarea = (Lee-Json (Join-Path (Join-Path $E.Datos 'tareas') 'propiedades.json'))
    Commits = @((GitEn $E.Repo @('log', '--format=%s')) -split "`n")
    Diag = @($script:DiagLlamadas)
  }
}

function Prompt-De($E, [int]$N) { return [System.IO.File]::ReadAllText((Join-Path $E.Prompts "$N.md")) }
function Estado-Git($E) { return (GitEn $E.Repo @('status', '--short')) }

# El migrado esta como al empezar: sin cambios en git y con el texto de cada fichero de $E.Iniciales.
function Como-Antes($E) {
  if (Estado-Git $E) { return $false }
  foreach ($k in $E.Iniciales.Keys) { if ((Lee $E.Repo $k) -cne $E.Iniciales[$k]) { return $false } }
  return $true
}

# Donde sale $Valor: la consola, los ficheros de datos, de registros y del migrado (con .rescate, sin .git) y la historia de git.
function Donde-Esta([string]$Valor, $E, [string]$Consola) {
  $res = @()
  if ($Consola.Contains($Valor)) { $res += 'consola' }
  foreach ($d in @($E.Datos, $E.Registros, $E.Repo)) {
    foreach ($f in @(Get-ChildItem -LiteralPath $d -Recurse -File -Force | Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' })) {
      if ([System.IO.File]::ReadAllText($f.FullName).Contains($Valor)) { $res += $f.FullName }
    }
  }
  if ((GitEn $E.Repo @('log', '-p', '--all')).Contains($Valor)) { $res += 'git log' }
  return $res
}

# Lo que tiene que cumplir toda tarea que se queda atascada: la pasada sigue, dos llamadas (la segunda con la correccion y su motivo), el migrado como
# estaba, ningun commit nuevo, el JSON y la tarea atascadas y el aviso.
function Comprueba-Atascada($E, $X, [string]$Motivo, [int]$Commits = 1, [switch]$SinCorreccion) {
  Igual 'la pasada sigue' $true $X.Sigue
  Igual 'dos llamadas' 2 (Llamadas-De $E.Llamadas).Count
  $p2 = ''
  if (Test-Path -LiteralPath (Join-Path $E.Prompts '2.md')) { $p2 = Prompt-De $E 2 }
  if ($SinCorreccion) { Comprueba 'el prompt del reintento (tras un fallo de la llamada) no lleva la correccion: no hay nada que corregir' ($p2 -notmatch 'CORRECCI') $p2 }
  else {
    Comprueba 'el prompt del reintento lleva la correccion' ($p2 -match 'CORRECCI') 'sin CORRECCI'
    Comprueba "el prompt del reintento lleva el motivo ($Motivo)" ($p2 -match $Motivo) $p2
  }
  Comprueba 'el migrado esta como al empezar' (Como-Antes $E) (Estado-Git $E)
  Igual 'ningun commit nuevo' $Commits $X.Commits.Count
  Igual 'JSON: atascada' 'atascada' $X.Json.estado
  Comprueba "JSON: el motivo ($Motivo)" ([string]$X.Json.motivo -match $Motivo) $X.Json.motivo
  Igual 'JSON: sin commit' '' $X.Json.commit
  Igual 'tarea: atascada con dos intentos' 'atascada 2' "$($X.Tarea.estado) $($X.Tarea.intentos)"
  Comprueba 'la consola avisa de que esta atascada' (@($X.Avisos | Where-Object { $_ -match '^Propiedades al yml: atascada: ' }).Count -eq 1) ($X.Avisos -join ' / ')
  Comprueba 'el rastro del intento (.rescate/intento-en-curso.json) ya no esta' (-not (Test-Path -LiteralPath (Join-Path (Join-Path $E.Repo '.rescate') 'intento-en-curso.json')))
}

# ================================ DATOS ================================
# Dos claves que faltan, una renombrada por Spring Boot 3 (spring.batch.initialize-schema), y lo que el Copilot de mentira deja bien hecho.
$LegA = "app.ruta=/datos/in`napp.lote=100`nspring.batch.initialize-schema=always`n"
$YmlBase = "app:`n  ruta: /datos/in`n"
$MigA = @{ ($Yml) = $YmlBase }
$YmlA2 = "app:`n  ruta: /datos/in`n  lote: 100`nspring:`n  batch:`n    jdbc:`n      initialize-schema: always`n"
$AnadeLote = @{ clave = 'app.lote'; fichero = $Yml }
$AnadeBatch = @{ clave = 'spring.batch.initialize-schema'; fichero = $Yml }
$SalidaA2 = @{ anadidas = @($AnadeLote, $AnadeBatch); noAplica = @() }
$PlanA2 = @{ ficheros = @{ ($Yml) = $YmlA2 }; salida = $SalidaA2 }
# Lo mismo y un secreto (db.password), que va como variable
$LegS = $LegA + "db.password=$Secreto`n"
$YmlS = $YmlA2 + "db:`n  password: `${DB_PASSWORD}`n"
$SalidaS = @{ anadidas = @($AnadeLote, $AnadeBatch, @{ clave = 'db.password'; fichero = $Yml }); noAplica = @() }
$JavaAjustes = "package com.acme.recibos;`n`npublic class Ajustes {`n}`n"
$RJava = 'src/main/java/com/acme/recibos/Ajustes.java'

$Pruebas = [ordered]@{}

# ================================ (a) LO QUE HACE ================================
$Pruebas['1 a) dos claves que faltan, una renombrada: el Copilot las anade; un commit solo con el yml, JSON hecha, el prompt con las claves y la consola'] = {
  $E = Nuevo-Escenario 'a' @{ ($RR + 'application.properties') = $LegA } $MigA
  Plan $E 1 $PlanA2
  $antes = @((GitEn $E.Repo @('log', '--format=%H')) -split "`n").Count
  $X = Fase $E
  Igual 'la pasada sigue' $true $X.Sigue
  $llamadas = Llamadas-De $E.Llamadas
  Igual 'una llamada' 1 $llamadas.Count
  Comprueba 'con el modelo, el esfuerzo medio y la referencia (y no el original) para leer' (($llamadas[0] -match '--model=modelo-x') -and ($llamadas[0] -match '--effort=medium') -and ($llamadas[0].Contains('--add-dir=' + $E.Ref)) -and (-not $llamadas[0].Contains($E.Legacy))) $llamadas[0]
  Comprueba 'trabaja en el worktree del migrado' ($llamadas[0].EndsWith('|' + $E.Repo)) $llamadas[0]
  Igual 'un commit nuevo' ($antes + 1) $X.Commits.Count
  Igual 'el asunto del commit' 'rescate(propiedades): 2 claves del original en el yml' $X.Commits[0]
  Igual 'el commit solo toca el yml' $Yml ((GitEn $E.Repo @('show', '--name-only', '--format=', 'HEAD')).Trim())
  Igual 'el yml del migrado es el que dejo el Copilot' $YmlA2 (Lee $E.Repo $Yml)
  Igual 'nada sin confirmar en el worktree' '' (Estado-Git $E)
  Comprueba 'sin la marca del intento en curso' (-not (Test-Path -LiteralPath (Join-Path (Join-Path $E.Repo '.rescate') 'intento-en-curso.json')))
  $j = $X.Json
  Igual 'JSON: los campos, en su orden' 'estado commit pedidas anadidas noAplica motivo huella' ($j.PSObject.Properties.Name -join ' ')
  Igual 'JSON: hecha' 'hecha' $j.estado
  Igual 'JSON: el commit es el HEAD' (GitEn $E.Repo @('rev-parse', 'HEAD')) $j.commit
  Igual 'JSON: pedidas' 2 $j.pedidas
  Igual 'JSON: anadidas' 'app.lote spring.batch.initialize-schema' (@($j.anadidas | ForEach-Object { $_.clave }) -join ' ')
  Igual 'JSON: anadidas llevan su fichero' "$Yml $Yml" (@($j.anadidas | ForEach-Object { $_.fichero }) -join ' ')
  Igual 'JSON: ninguna noAplica' 0 @($j.noAplica).Count
  Comprueba 'JSON: huella de 8 caracteres' ($j.huella -match '^[0-9a-f]{8}$') $j.huella
  Igual 'tarea: hecha con un intento' 'hecha 1' "$($X.Tarea.estado) $($X.Tarea.intentos)"
  Igual 'tarea: el tipo' 'propiedades' $X.Tarea.tipo
  Comprueba 'la consola acaba con el commit de 7 caracteres' (($X.Texto -split "`n" | Where-Object { $_ -like 'Propiedades al yml: *' }) -match ('^Propiedades al yml: 2 anadidas, 0 no aplican \(commit ' + $j.commit.Substring(0, 7) + '\)\.$')) $X.Texto
  Igual 'el diagnostico, una vez y como propiedades' 'propiedades' ($X.Diag -join ' ')
  Comprueba 'el diagnostico de propiedades queda en datos' (Test-Path -LiteralPath (Join-Path $E.Datos 'diagnostico-propiedades.md'))
  $pj = Lee-Json (Join-Path $E.Datos 'propiedades.json')
  Igual 'propiedades.json es el de despues: ya no falta ninguna' '0 0 1' "$($pj.resumen.falta) $($pj.resumen.'renombrada-falta') $($pj.resumen.renombrada)"
  $p = Prompt-De $E 1
  Comprueba 'el prompt: sin marcas {{ sin rellenar' (-not $p.Contains('{{')) $p
  Comprueba 'el prompt: el tipo y donde escribir' (($p -match '(?m)^TIPO: propiedades\r?$') -and $p.Contains('.rescate/tareas/propiedades.json')) $p
  Comprueba 'el prompt: la clave app.lote con su perfil, su fichero:linea y su valor' ($p -match 'app\.lote.*default.*src/main/resources/application\.properties:2.*100') $p
  Comprueba 'el prompt: la renombrada con su nombre nuevo' ($p -match 'spring\.batch\.initialize-schema.*spring\.batch\.jdbc\.initialize-schema') $p
  Comprueba 'el prompt: no pide la que ya esta (app.ruta)' (-not $p.Contains('app.ruta')) $p
  Comprueba 'el prompt: el fichero donde puede escribir' ($p.Contains($Yml)) $p
  Comprueba 'el prompt: el yml de la referencia, con su ruta' ($p.Contains((Join-Ruta $E.Ref $Yml))) $p
}

$Pruebas['2 b) sin claves que faltan: ninguna llamada, ni diagnostico ni tarea, JSON sin-faltan y la consola'] = {
  $E = Nuevo-Escenario 'b' @{ ($RR + 'application.properties') = "app.ruta=/datos/in`n" } $MigA
  $X = Fase $E
  Igual 'la pasada sigue' $true $X.Sigue
  Igual 'ninguna llamada a Copilot' 0 (Llamadas-De $E.Llamadas).Count
  Igual 'ni al diagnostico' 0 $X.Diag.Count
  Comprueba 'ninguna tarea guardada' ($null -eq $X.Tarea)
  Igual 'ningun commit nuevo' 1 $X.Commits.Count
  Igual 'JSON: sin-faltan' 'sin-faltan' $X.Json.estado
  Igual 'JSON: 0 pedidas, sin commit y sin huella' '0 |' "$($X.Json.pedidas) $($X.Json.commit)|$($X.Json.huella)"
  Igual 'JSON: listas vacias' '0 0' "$(@($X.Json.anadidas).Count) $(@($X.Json.noAplica).Count)"
  Comprueba 'la consola dice que no falta ninguna' ($X.Texto -split "`n" -contains 'Propiedades al yml: ninguna falta') $X.Texto
  Comprueba 'compara antes de nada: deja propiedades.json' (Test-Path -LiteralPath (Join-Path $E.Datos 'propiedades.json'))
  $E2 = Nuevo-Escenario 'b2' @{} @{}
  $X2 = Fase $E2
  Igual 'un original sin ficheros de propiedades: sin-faltan' 'sin-faltan' $X2.Json.estado
}

$Pruebas['3 c) el motor del diagnostico se cae: la fase devuelve false y pone la parada, el migrado queda como estaba y al relanzar sigue'] = {
  $E = Nuevo-Escenario 'c' @{ ($RR + 'application.properties') = $LegA } $MigA
  Plan $E 1 $PlanA2
  $X = Fase $E -Cae $true
  Igual 'la fase devuelve false' $false $X.Sigue
  Igual 'una parada' 1 $script:Paradas.Count
  Igual 'la parada es motor' 'motor' $script:Paradas[0][0]
  Igual 'la pasada queda parada' $true $script:Parada
  Comprueba 'el migrado esta como al empezar' (Como-Antes $E) (Estado-Git $E)
  Igual 'ningun commit nuevo' 1 $X.Commits.Count
  Comprueba 'sin JSON de resultados: la fase no ha terminado' ($null -eq $X.Json)
  Igual 'la tarea sigue pendiente y sin gastar el intento' 'pendiente 0' "$($X.Tarea.estado) $($X.Tarea.intentos)"
  Comprueba 'sin la marca del intento en curso' (-not (Test-Path -LiteralPath (Join-Path (Join-Path $E.Repo '.rescate') 'intento-en-curso.json')))
  $Y = Fase $E
  Igual 'al relanzar con el motor bien: sigue' $true $Y.Sigue
  Igual 'y queda hecha' 'hecha' $Y.Json.estado
  Igual 'con una llamada mas' 2 (Llamadas-De $E.Llamadas).Count
}

# ================================ (d) LAS PUERTAS ================================
# Cada puerta: un test. Si falla, se deshace todo lo de la tarea, se reintenta con el motivo, y al segundo fallo queda atascada y la pasada sigue.
$Pruebas['4 d1) el JSON nombra una clave que no se pidio: atascada, con el motivo en el reintento y todo deshecho'] = {
  $E = Nuevo-Escenario 'd1' @{ ($RR + 'application.properties') = $LegA } $MigA
  Plan $E 1 @{ ficheros = @{ ($Yml) = $YmlA2 }; salida = @{ anadidas = @($AnadeLote, $AnadeBatch, @{ clave = 'app.inventada'; fichero = $Yml }); noAplica = @() } }
  $X = Fase $E
  Comprueba-Atascada $E $X 'app\.inventada'
  Igual 'ni siquiera llega al diagnostico' 0 $X.Diag.Count
  Comprueba 'el prompt del reintento sube el esfuerzo' ((Llamadas-De $E.Llamadas)[1] -match '--effort=high') ((Llamadas-De $E.Llamadas) -join ' / ')
}

$Pruebas['5 d2) toca un .java: todo se deshace (tambien lo bueno del yml) y el motivo nombra el fichero'] = {
  $mig = @{ ($Yml) = $YmlBase; ($RJava) = $JavaAjustes }
  $E = Nuevo-Escenario 'd2' @{ ($RR + 'application.properties') = $LegA } $mig
  Plan $E 1 @{ ficheros = @{ ($Yml) = $YmlA2; ($RJava) = ($JavaAjustes + "// tocado`n") }; salida = $SalidaA2 }
  $X = Fase $E
  Comprueba-Atascada $E $X 'Ajustes\.java'
  Igual 'el .java como estaba' $JavaAjustes (Lee $E.Repo $RJava)
  Igual 'el yml como estaba' $YmlBase (Lee $E.Repo $Yml)
}

$Pruebas['6 d2b) crea un fichero que no esta permitido (otro perfil sin pedir): se deshace y el motivo lo nombra'] = {
  $E = Nuevo-Escenario 'd2b' @{ ($RR + 'application.properties') = $LegA } $MigA
  Plan $E 1 @{ ficheros = @{ ($Yml) = $YmlA2; ($RR + 'application-otro.yml') = "app:`n  x: 1`n" }; salida = $SalidaA2 }
  $X = Fase $E
  Comprueba-Atascada $E $X 'application-otro\.yml'
  Comprueba 'el fichero nuevo ya no esta' (-not (Test-Path -LiteralPath (Get-Ruta $E.Repo ($RR + 'application-otro.yml'))))
}

$Pruebas['7 d3) escribe el valor de un secreto: se deshace, el motivo nombra la clave y el valor no sale en ningun sitio'] = {
  $E = Nuevo-Escenario 'd3' @{ ($RR + 'application.properties') = $LegS } $MigA
  $conSecreto = $YmlA2 + "db:`n  password: $Secreto`n"
  Plan $E 1 @{ ficheros = @{ ($Yml) = $conSecreto }; salida = $SalidaS; texto = "he copiado $Secreto como pedias" }
  $X = Fase $E
  Comprueba-Atascada $E $X 'db\.password'
  Igual 'no llega al diagnostico' 0 $X.Diag.Count
  $donde = @(Donde-Esta $Secreto $E ($X.Texto + "`n" + ($X.Avisos -join "`n")))
  Igual 'el valor del secreto no sale en la consola, los datos, los registros, el migrado ni git' '' ($donde -join ' | ')
  $log = [System.IO.File]::ReadAllText((Join-Path $E.Registros 'propiedades-1.log'))
  Comprueba 'el registro de la llamada tapa lo que dijo el Copilot' ($log.Contains('he copiado *** como pedias')) $log
}

$Pruebas['8 d4) deja una clave sin anadir y sin noAplica: atascada y el motivo nombra la clave'] = {
  $E = Nuevo-Escenario 'd4' @{ ($RR + 'application.properties') = $LegA } $MigA
  Plan $E 1 @{ ficheros = @{ ($Yml) = "app:`n  ruta: /datos/in`n  lote: 100`n" }; salida = $SalidaA2 }
  $X = Fase $E
  Comprueba-Atascada $E $X 'spring\.batch\.initialize-schema'
  Igual 'no llega al diagnostico' 0 $X.Diag.Count
}

$Pruebas['9 d4b) una renombrada puesta con su nombre viejo no vale: tiene que quedar con el nombre nuevo'] = {
  $E = Nuevo-Escenario 'd4b' @{ ($RR + 'application.properties') = $LegA } $MigA
  $viejo = "app:`n  ruta: /datos/in`n  lote: 100`nspring:`n  batch:`n    initialize-schema: always`n"
  Plan $E 1 @{ ficheros = @{ ($Yml) = $viejo }; salida = $SalidaA2 }
  $X = Fase $E
  Comprueba-Atascada $E $X 'spring\.batch\.initialize-schema'
}

$Pruebas['10 d5) no compila: atascada y el migrado como estaba'] = {
  $E = Nuevo-Escenario 'd5' @{ ($RR + 'application.properties') = $LegA } $MigA
  Plan $E 1 $PlanA2
  $X = Fase $E -Diag @('compila: NO')
  Comprueba-Atascada $E $X 'compila'
  Igual 'el diagnostico se pidio en los dos intentos' 'propiedades propiedades' ($X.Diag -join ' ')
}

$Pruebas['11 d6) los tests fallan y antes no: atascada; si ya fallaban antes (no peor), vale'] = {
  $E = Nuevo-Escenario 'd6' @{ ($RR + 'application.properties') = $LegA } $MigA
  Plan $E 1 $PlanA2
  $X = Fase $E -Diag @('compila: SI | tests: FALLAN')
  Comprueba-Atascada $E $X 'tests'
  $E2 = Nuevo-Escenario 'd6b' @{ ($RR + 'application.properties') = $LegA } $MigA
  Plan $E2 1 $PlanA2
  Escribe $E2.Datos 'diagnostico-despues.md' "# Diagnostico`n`n- Estado: compila: SI | tests: FALLAN`n"
  $Y = Fase $E2 -Diag @('compila: SI | tests: FALLAN')
  Igual 'con los tests fallando ya antes: hecha' 'hecha' $Y.Json.estado
  Igual 'con un commit' 2 $Y.Commits.Count
  $E3 = Nuevo-Escenario 'd6c' @{ ($RR + 'application.properties') = $LegA } $MigA
  Plan $E3 1 $PlanA2
  $Z = Fase $E3 -Diag @('compila: SI | tests: no ejecutados')
  Igual 'sin tests ejecutados (no es FALLAN): hecha' 'hecha' $Z.Json.estado
}

$Pruebas['12 d7) la IA hace un commit: se deshace, el motivo lo dice y el reintento tambien se deshace'] = {
  $E = Nuevo-Escenario 'd7' @{ ($RR + 'application.properties') = $LegA } $MigA
  Plan $E 1 @{ ficheros = @{ ($Yml) = $YmlA2 }; salida = $SalidaA2; commit = $true }
  $X = Fase $E
  Comprueba-Atascada $E $X 'commit'
  Comprueba 'la historia sin el commit de la IA' (-not (($X.Commits -join '|').Contains('la IA commitea')))
}

$Pruebas['13 d8) Copilot sale con codigo 1 despues de cambiar el yml: se deshace, atascada con el codigo y la pasada sigue (no para)'] = {
  $E = Nuevo-Escenario 'd8' @{ ($RR + 'application.properties') = $LegA } $MigA
  Plan $E 1 @{ ficheros = @{ ($Yml) = $YmlA2 }; salida = $SalidaA2; sale = 1; texto = 'sin sesion' }
  $X = Fase $E
  Comprueba-Atascada $E $X 'codigo 1' -SinCorreccion
  Igual 'sin parada' 0 $script:Paradas.Count
}

$Pruebas['14 d9) el primer intento falla y el reintento, con el motivo y mas esfuerzo, lo hace bien: hecha con dos intentos'] = {
  $E = Nuevo-Escenario 'd9' @{ ($RR + 'application.properties') = $LegA } $MigA
  Plan $E 1 @{ ficheros = @{ ($Yml) = $YmlA2 }; salida = @{ anadidas = @($AnadeLote, $AnadeBatch, @{ clave = 'app.inventada'; fichero = $Yml }); noAplica = @() } }
  Plan $E 2 $PlanA2
  $X = Fase $E
  Igual 'la pasada sigue' $true $X.Sigue
  Igual 'dos llamadas' 2 (Llamadas-De $E.Llamadas).Count
  $p1 = Prompt-De $E 1
  $p2 = Prompt-De $E 2
  Comprueba 'el primer prompt sin correccion' ($p1 -notmatch 'CORRECCI') $p1
  Comprueba 'el segundo con la correccion y el motivo' (($p2 -match 'CORRECCI') -and ($p2 -match 'app\.inventada')) $p2
  Igual 'hecha con dos intentos' 'hecha 2' "$($X.Tarea.estado) $($X.Tarea.intentos)"
  Igual 'JSON: hecha' 'hecha' $X.Json.estado
  Igual 'un commit' 2 $X.Commits.Count
  Igual 'el yml bueno' $YmlA2 (Lee $E.Repo $Yml)
}

# ================================ (e) noAplica ================================
$Pruebas['15 e) noAplica con motivo vale; sin motivo, no; una clave que no se pidio, tampoco; todas noAplica y nada que cambiar: sin-cambios'] = {
  $E = Nuevo-Escenario 'e' @{ ($RR + 'application.properties') = $LegA } $MigA
  $unaClave = "app:`n  ruta: /datos/in`n  lote: 100`n"
  Plan $E 1 @{ ficheros = @{ ($Yml) = $unaClave }; salida = @{ anadidas = @($AnadeLote); noAplica = @(@{ clave = 'spring.batch.initialize-schema'; motivo = 'el codigo del migrado ya no la lee' }) } }
  $X = Fase $E
  Igual 'con motivo: hecha' 'hecha' $X.Json.estado
  Igual 'el asunto cuenta las anadidas' 'rescate(propiedades): 1 claves del original en el yml' $X.Commits[0]
  Igual 'JSON: una anadida y una noAplica con su motivo' 'app.lote|spring.batch.initialize-schema|el codigo del migrado ya no la lee' "$(@($X.Json.anadidas)[0].clave)|$(@($X.Json.noAplica)[0].clave)|$(@($X.Json.noAplica)[0].motivo)"
  Comprueba 'la consola: 1 anadidas, 1 no aplican' ($X.Texto -match 'Propiedades al yml: 1 anadidas, 1 no aplican \(commit [0-9a-f]{7}\)\.') $X.Texto
  $E2 = Nuevo-Escenario 'e2' @{ ($RR + 'application.properties') = $LegA } $MigA
  Plan $E2 1 @{ ficheros = @{ ($Yml) = $unaClave }; salida = @{ anadidas = @($AnadeLote); noAplica = @(@{ clave = 'spring.batch.initialize-schema'; motivo = '  ' }) } }
  $Y = Fase $E2
  Comprueba-Atascada $E2 $Y 'motivo'
  $E3 = Nuevo-Escenario 'e3' @{ ($RR + 'application.properties') = $LegA } $MigA
  Plan $E3 1 @{ salida = @{ anadidas = @(); noAplica = @(@{ clave = 'app.lote'; motivo = 'no se usa' }, @{ clave = 'spring.batch.initialize-schema'; motivo = 'no se usa' }) } }
  $Z = Fase $E3
  Igual 'todas noAplica: sin-cambios' 'sin-cambios' $Z.Json.estado
  Igual 'sin commit' '' $Z.Json.commit
  Igual 'ningun commit nuevo' 1 $Z.Commits.Count
  Igual 'sin diagnostico: no hay nada que medir' 0 $Z.Diag.Count
  Igual 'tarea hecha' 'hecha' $Z.Tarea.estado
  Comprueba 'la consola' ($Z.Texto -match 'Propiedades al yml: 0 anadidas, 2 no aplican \(sin cambios\)\.') $Z.Texto
}

# ================================ (f) CACHE ================================
$Pruebas['16 f) cache: relanzar sin cambios no llama y deja el resultado; cambiar la plantilla, un fichero permitido o un valor del original, si'] = {
  $E = Nuevo-Escenario 'f' @{ ($RR + 'application.properties') = $LegA } $MigA
  # una atascada con la misma huella no se repite (Conservar); la huella son las claves pedidas con su valor, los ficheros permitidos y la plantilla
  Plan $E 1 @{ ficheros = @{ ($Yml) = $YmlA2 }; salida = @{ anadidas = @($AnadeLote, $AnadeBatch, @{ clave = 'app.inventada'; fichero = $Yml }); noAplica = @() } }
  $a = Fase $E
  Igual 'primer lanzamiento: atascada, dos llamadas' 'atascada 2' "$($a.Json.estado) $((Llamadas-De $E.Llamadas).Count)"
  $huella = $a.Json.huella
  $b = Fase $E
  Igual 'relanzar con la misma huella y atascada: ninguna llamada nueva' 2 (Llamadas-De $E.Llamadas).Count
  Igual 'sigue atascada, con la misma huella' "atascada $huella" "$($b.Json.estado) $($b.Json.huella)"
  Comprueba 'la consola lo repite' (@($b.Avisos | Where-Object { $_ -match '^Propiedades al yml: atascada: ' }).Count -eq 1) ($b.Avisos -join ' / ')
  $c = Fase $E -Mantener $false
  Igual 'sin conservar las atascadas (-Reintentar): vuelve a llamar' 4 (Llamadas-De $E.Llamadas).Count
  # cambiar la plantilla
  [void](Get-Plantilla 'propiedades')
  $plantilla = $script:Plantillas['propiedades']
  try {
    $script:Plantillas['propiedades'] = $plantilla + "`nUna linea mas.`n"
    $d = Fase $E
  }
  finally { $script:Plantillas['propiedades'] = $plantilla }
  Igual 'cambiar la plantilla: vuelve a llamar' 6 (Llamadas-De $E.Llamadas).Count
  Comprueba 'y la huella cambia' ($d.Json.huella -cne $huella) $d.Json.huella
  # cambiar un fichero permitido (el usuario anade otra clave y la confirma)
  Escribe $E.Repo $Yml ($YmlBase + "otra:`n  cosa: 1`n")
  [void](GitEn $E.Repo @('commit', '-q', '-a', '-m', 'otra clave'))
  $e1 = Fase $E
  Igual 'cambiar un fichero permitido: vuelve a llamar' 8 (Llamadas-De $E.Llamadas).Count
  # cambiar el valor de una clave pedida en el original
  Escribe $E.Legacy ($RR + 'application.properties') ($LegA -replace 'lote=100', 'lote=200')
  $f1 = Fase $E
  Igual 'cambiar el valor de una clave pedida: vuelve a llamar' 10 (Llamadas-De $E.Llamadas).Count
  Comprueba 'y el prompt trae el valor nuevo' ((Prompt-De $E 10) -match 'app\.lote.*200') (Prompt-De $E 10)
  # una hecha tampoco se repite y su resultado queda aunque ya no falte nada
  $E2 = Nuevo-Escenario 'f2' @{ ($RR + 'application.properties') = $LegA } $MigA
  Plan $E2 1 $PlanA2
  $g = Fase $E2
  $h = Fase $E2
  Igual 'hecha: relanzar no llama' 1 (Llamadas-De $E2.Llamadas).Count
  Igual 'ni vuelve a hacer commit' $g.Commits.Count $h.Commits.Count
  Igual 'el resultado sigue: hecha con su commit y sus claves' "hecha $($g.Json.commit) 2" "$($h.Json.estado) $($h.Json.commit) $(@($h.Json.anadidas).Count)"
  Comprueba 'la consola repite la linea del commit' ($h.Texto -match 'Propiedades al yml: 2 anadidas, 0 no aplican \(commit [0-9a-f]{7}\)\.') $h.Texto
  Igual 'sin diagnostico al relanzar' 0 $h.Diag.Count
}

# ================================ (g) PERFILES SIN FICHERO ================================
$Pruebas['17 g) un perfil sin fichero: crea application-<perfil>.yml; sin ningun fichero de configuracion crea application.yml; con config/ usa el que hay'] = {
  $legPro = @{ ($RR + 'application.properties') = "app.ruta=/datos/in`n"; ($RR + 'application-pro.properties') = "app.timeout=30`n" }
  $E = Nuevo-Escenario 'g' $legPro $MigA
  Plan $E 1 @{ ficheros = @{ ($RR + 'application-pro.yml') = "app:`n  timeout: 30`n" }; salida = @{ anadidas = @(@{ clave = 'app.timeout'; fichero = ($RR + 'application-pro.yml') }); noAplica = @() } }
  $X = Fase $E
  Igual 'hecha' 'hecha' $X.Json.estado
  Igual 'el commit crea solo application-pro.yml' ($RR + 'application-pro.yml') ((GitEn $E.Repo @('show', '--name-only', '--format=', 'HEAD')).Trim())
  $p = Prompt-De $E 1
  Comprueba 'el prompt dice el perfil y que el fichero es nuevo' (($p -match 'app\.timeout.*pro') -and ($p -match 'application-pro\.yml.*nuevo')) $p
  Comprueba 'y el yml que ya esta, como existente' ($p -match 'application\.yml.*existe') $p
  # sin ningun fichero de configuracion en el migrado, el default se crea como application.yml
  $E2 = Nuevo-Escenario 'g2' @{ ($RR + 'application.properties') = "app.lote=100`n" } @{ 'LEEME.txt' = "nada`n" }
  Plan $E2 1 @{ ficheros = @{ ($Yml) = "app:`n  lote: 100`n" }; salida = @{ anadidas = @($AnadeLote); noAplica = @() } }
  $Y = Fase $E2
  Igual 'sin ficheros: hecha' 'hecha' $Y.Json.estado
  Igual 'y crea application.yml' $Yml ((GitEn $E2.Repo @('show', '--name-only', '--format=', 'HEAD')).Trim())
  # un application.yml en resources/config tambien es del migrado: no se crea otro
  $E3 = Nuevo-Escenario 'g3' @{ ($RR + 'application.properties') = "app.lote=100`n" } @{ ($RR + 'config/application.yml') = $YmlBase }
  Plan $E3 1 @{ ficheros = @{ ($RR + 'config/application.yml') = ($YmlBase + "  lote: 100`n") }; salida = @{ anadidas = @(@{ clave = 'app.lote'; fichero = ($RR + 'config/application.yml') }); noAplica = @() } }
  $Z = Fase $E3
  Igual 'con config/application.yml: hecha' 'hecha' $Z.Json.estado
  $pz = Prompt-De $E3 1
  Comprueba 'el prompt lista el de config y no ofrece crear application.yml' (($pz -match 'config/application\.yml.*existe') -and ($pz -notmatch 'application\.yml \(nuevo')) $pz
}

# ================================ (i) PIEZAS ================================
$Pruebas['18 i) Test-SalidaPropiedades: el JSON que vale y los que no'] = {
  $E = Nuevo-Escenario 'i' @{} @{}
  $t = New-TareaTipo 'propiedades' 'propiedades' '' '' ([pscustomobject]@{ claves = @('app.lote', 'db.password') })
  function Prueba-Salida([string]$Texto, [bool]$Ok, [string]$Motivo, [string]$Que) {
    $rutaJson = Join-Ruta $E.Repo '.rescate/tareas/propiedades.json'
    if (Test-Path -LiteralPath $rutaJson) { Remove-Item -LiteralPath $rutaJson -Force }
    if ($Texto -cne 'SIN-FICHERO') { Escribe $E.Repo '.rescate/tareas/propiedades.json' $Texto }
    $v = Test-SalidaPropiedades $t $E.Repo
    Igual "$Que`: Ok" $Ok $v.Ok
    if ($Motivo) { Comprueba "$Que`: el motivo ($Motivo)" ([string]$v.Motivo -match $Motivo) $v.Motivo }
    return $v
  }
  $bien = '{"anadidas":[{"clave":"app.lote","fichero":"src/main/resources/application.yml"}],"noAplica":[{"clave":"db.password","motivo":"ya no se usa"}]}'
  $v = Prueba-Salida $bien $true '' 'valido'
  Igual 'la ficha trae anadidas y noAplica' '1 1' "$(@($v.Ficha.anadidas).Count) $(@($v.Ficha.noAplica).Count)"
  [void](Prueba-Salida '{"anadidas":[],"noAplica":[]}' $true '' 'dos listas vacias')
  [void](Prueba-Salida '{"anadidas":[{"clave":"app.lote","fichero":"x.yml"}]}' $true '' 'sin noAplica es una lista vacia')
  [void](Prueba-Salida 'SIN-FICHERO' $false 'No has escrito' 'sin fichero')
  [void](Prueba-Salida 'esto no es json' $false 'JSON' 'texto que no es JSON')
  [void](Prueba-Salida '[1,2]' $false 'objeto' 'una lista en vez de un objeto')
  [void](Prueba-Salida '{"anadidas":"app.lote","noAplica":[]}' $false 'anadidas.*lista' 'anadidas que no es una lista')
  [void](Prueba-Salida '{"anadidas":[{"clave":"otra.clave","fichero":"x.yml"}],"noAplica":[]}' $false 'otra\.clave' 'una clave que no se pidio en anadidas')
  [void](Prueba-Salida '{"anadidas":[],"noAplica":[{"clave":"otra.clave","motivo":"x"}]}' $false 'otra\.clave' 'una clave que no se pidio en noAplica')
  [void](Prueba-Salida '{"anadidas":[{"clave":"app.lote"}],"noAplica":[]}' $false 'fichero' 'anadidas sin fichero')
  [void](Prueba-Salida '{"anadidas":[],"noAplica":[{"clave":"app.lote"}]}' $false 'motivo' 'noAplica sin motivo')
  [void](Prueba-Salida '{"anadidas":[],"noAplica":[{"clave":"app.lote","motivo":""}]}' $false 'motivo' 'noAplica con el motivo vacio')
  [void](Prueba-Salida '{"anadidas":[{"clave":"app.lote","fichero":"x.yml"}],"noAplica":[{"clave":"app.lote","motivo":"y"}]}' $false 'app\.lote.*(las dos|dos listas)' 'una clave en las dos listas')
}

$Pruebas['19 i) Get-NombreVariableSecreto: la clave en mayusculas con _'] = {
  Igual 'db.password' 'DB_PASSWORD' (Get-NombreVariableSecreto 'db.password')
  Igual 'una con guion' 'APP_API_KEY' (Get-NombreVariableSecreto 'app.api-key')
  Igual 'una con indice' 'APP_ITEMS_0_TOKEN' (Get-NombreVariableSecreto 'app.items[0].token')
  Igual 'una con camel case y guion bajo' 'SPRING_DATASOURCE_MI_CLAVE' (Get-NombreVariableSecreto 'spring.datasource.mi_clave')
}

$Pruebas['20 i) el valor de un secreto no sale ni cuando el Copilot lo hace bien: consola, datos, registros, migrado y git sin el valor, y el prompt lo pide como variable'] = {
  $E = Nuevo-Escenario 'i2' @{ ($RR + 'application.properties') = $LegS } $MigA
  Plan $E 1 @{ ficheros = @{ ($Yml) = $YmlS }; salida = $SalidaS }
  $X = Fase $E
  Igual 'hecha' 'hecha' $X.Json.estado
  Comprueba 'el yml lleva el secreto como variable' ((Lee $E.Repo $Yml).Contains('password: ${DB_PASSWORD}'))
  $p = Prompt-De $E 1
  Comprueba 'el prompt dice que es un secreto, no se copia y va como ${DB_PASSWORD}' ($p -match 'db\.password.*secreto: no lo copies.*\$\{DB_PASSWORD\}') $p
  Igual 'el valor no sale en ningun sitio' '' (@(Donde-Esta $Secreto $E $X.Texto) -join ' | ')
  $pj = Lee-Json (Join-Path $E.Datos 'propiedades.json')
  Comprueba 'propiedades.json marca el secreto y no lo guarda' ((@($pj.legacy | Where-Object { $_.clave -eq 'db.password' })[0].secreto -eq $true) -and ($null -eq @($pj.legacy | Where-Object { $_.clave -eq 'db.password' })[0].valorLegacy))
}

# ================================ (h) FICHEROS ================================
$Pruebas['21 h) arreglo-propiedades.ps1: solo funciones, cabecera, ASCII, nada de PowerShell 7, ninguna funcion repetida; la plantilla y las lineas de tareas.ps1'] = {
  $ruta = Join-Path $raiz 'arreglo-propiedades.ps1'
  Comprueba 'existe junto a migracion.ps1' (Test-Path -LiteralPath $ruta)
  if (-not (Test-Path -LiteralPath $ruta)) { return }
  $codigo = [System.IO.File]::ReadAllText($ruta)
  Comprueba 'empieza con su cabecera de ayuda' ($codigo.TrimStart().StartsWith('<#'))
  Comprueba 'nada de PowerShell 7 (??, ?. ni ?[)' ($codigo -notmatch '\?\?|[\w\)\]]\?\.\w|\w\?\[')
  Comprueba 'sin -AsHashtable ni ConvertFrom-Json -Depth' ($codigo -notmatch 'AsHashtable|ConvertFrom-Json[^|\r\n]*-Depth')
  Comprueba 'sin Join-Path de tres rutas' ($codigo -notmatch 'Join-Path\s+[^\s|)]+\s+[^\s|)]+\s+[^\s|)]+\s*\)')
  foreach ($f in @('arreglo-propiedades.ps1', 'tests/probar-arreglo-propiedades.ps1', 'tests/falsos/c6b-copilot.ps1')) {
    $t = [System.IO.File]::ReadAllText((Get-Ruta $raiz $f))
    Comprueba "$f : solo ASCII" ($t -notmatch '[^\x09\x0A\x0D\x20-\x7E]')
  }
  $ast = [System.Management.Automation.Language.Parser]::ParseInput($codigo, [ref]$null, [ref]$null)
  $sueltas = @($ast.EndBlock.Statements | Where-Object { $_ -isnot [System.Management.Automation.Language.FunctionDefinitionAst] })
  Igual 'nada fuera de las funciones' 0 $sueltas.Count
  $suyas = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Name })
  $deMas = @(Get-ChildItem -LiteralPath $raiz -File -Filter '*.ps1' | Where-Object { $_.Name -cne 'arreglo-propiedades.ps1' } | ForEach-Object {
      [regex]::Matches([System.IO.File]::ReadAllText($_.FullName), '(?m)^function ([\w-]+)') | ForEach-Object { $_.Groups[1].Value }
    })
  $repetidas = @($suyas | Where-Object { $deMas -contains $_ })
  Comprueba 'ninguna de sus funciones esta definida en otro .ps1 de la raiz' ($repetidas.Count -eq 0) ($repetidas -join ', ')
  foreach ($n in @('Invoke-FasePropiedades', 'Test-SalidaPropiedades', 'Get-NombreVariableSecreto')) { Comprueba "define $n" ($suyas -contains $n) }
  # la plantilla
  $md = Get-Ruta $raiz 'tareas/propiedades.md'
  Comprueba 'existe tareas/propiedades.md' (Test-Path -LiteralPath $md)
  if (Test-Path -LiteralPath $md) {
    $bytes = [System.IO.File]::ReadAllBytes($md)
    $p = [System.Text.Encoding]::UTF8.GetString($bytes)
    Comprueba 'esta en UTF-8 (con acentos, sin bytes sueltos)' (($bytes | Where-Object { $_ -gt 127 }).Count -gt 0 -and $p -notmatch [string][char]0xFFFD)
    foreach ($k in @('CLAVES', 'FICHEROS', 'REFERENCIA', 'SALIDA', 'MOTIVO')) { Comprueba "la plantilla lleva {{$k}}" ($p.Contains('{{' + $k + '}}')) }
    Comprueba 'lleva TIPO: propiedades' ($p -match '(?m)^TIPO: propiedades\r?$')
    Comprueba 'y la parte de reintento tras <!--CORRECCION--> con {{MOTIVO}}' ($p -match '(?s)<!--CORRECCION-->.*\{\{MOTIVO\}\}')
    Comprueba 'el ejemplo de salida lleva anadidas y noAplica' ($p.Contains('"anadidas"') -and $p.Contains('"noAplica"') -and $p.Contains('"motivo"'))
    Comprueba 'dice que un secreto va como variable y nunca con su valor' ($p -match 'nunca con su valor|nunca su valor')
    Comprueba 'dice que no se cambia ni se borra lo que ya esta' ($p -match 'no cambies ni borres' -or $p -match 'No cambies ni borres')
  }
  # tareas.ps1: Test-Salida llama a la comprobacion de este tipo
  $lineas = @([System.IO.File]::ReadAllLines((Join-Path $raiz 'tareas.ps1')) | Where-Object { $_ -match "'propiedades'" })
  Comprueba 'tareas.ps1 tiene el caso propiedades en Test-Salida' (@($lineas | Where-Object { $_ -match "^\s*'propiedades' \{ return \(Test-SalidaPropiedades" }).Count -eq 1) ($lineas -join ' / ')
}

# ================================ (f) NINGUNA CLAVE EMPEORA ================================
# El valor nuevo que la IA mete en una clave que ya estaba bien; ni el nuevo ni el viejo pueden salir en el motivo.
$ValorNuevo = '/datos/otro-sitio'
$Pruebas['22 f1) cambia el valor de una clave que estaba igual: invalido antes de compilar, el motivo nombra la clave y no su valor'] = {
  $E = Nuevo-Escenario 'f1' @{ ($RR + 'application.properties') = $LegA } $MigA
  $cambiada = $YmlA2.Replace('/datos/in', $ValorNuevo)
  Plan $E 1 @{ ficheros = @{ ($Yml) = $cambiada }; salida = $SalidaA2 }
  $X = Fase $E
  Comprueba-Atascada $E $X 'app\.ruta'
  Igual 'no llega al diagnostico' 0 $X.Diag.Count
  Comprueba 'el motivo dice que ya estaba bien y ahora no (igual, distinto)' ([string]$X.Json.motivo -match 'igual.*distinto') $X.Json.motivo
  Comprueba 'el motivo no lleva ningun valor' (-not ([string]$X.Json.motivo).Contains($ValorNuevo) -and -not ([string]$X.Json.motivo).Contains('/datos/in')) $X.Json.motivo
  Comprueba 'ni el prompt del reintento' (-not (Prompt-De $E 2).Contains($ValorNuevo)) (Prompt-De $E 2)
}

$Pruebas['23 f2) borra una clave que estaba igual: invalido antes de compilar y el motivo nombra la clave'] = {
  $E = Nuevo-Escenario 'f2b' @{ ($RR + 'application.properties') = $LegA } $MigA
  $sinRuta = "app:`n  lote: 100`nspring:`n  batch:`n    jdbc:`n      initialize-schema: always`n"
  Plan $E 1 @{ ficheros = @{ ($Yml) = $sinRuta }; salida = $SalidaA2 }
  $X = Fase $E
  Comprueba-Atascada $E $X 'app\.ruta'
  Igual 'no llega al diagnostico' 0 $X.Diag.Count
  Comprueba 'el motivo dice que ya estaba bien y ahora falta (igual, falta)' ([string]$X.Json.motivo -match 'igual.*falta') $X.Json.motivo
}

$Pruebas['24 f3) lo que ya estaba mal y sigue igual de mal (distinto) no para: hecha; y el reintento que deja las claves buenas vale'] = {
  $leg = @{ ($RR + 'application.properties') = ($LegA + "app.otro=1`n") }
  $E = Nuevo-Escenario 'f3' $leg @{ ($Yml) = ($YmlBase + "  otro: 2`n") }
  Plan $E 1 @{ ficheros = @{ ($Yml) = ($YmlA2 + "  otro: 2`n") }; salida = $SalidaA2 }
  $X = Fase $E
  Igual 'hecha con una llamada' 'hecha 1' "$($X.Tarea.estado) $($X.Tarea.intentos)"
  Igual 'con su commit' 2 $X.Commits.Count
  Igual 'sin motivo' '' $X.Json.motivo
  # primer intento borra una clave buena; el segundo la deja: hecha con dos intentos
  $E2 = Nuevo-Escenario 'f3b' @{ ($RR + 'application.properties') = $LegA } $MigA
  Plan $E2 1 @{ ficheros = @{ ($Yml) = "app:`n  lote: 100`nspring:`n  batch:`n    jdbc:`n      initialize-schema: always`n" }; salida = $SalidaA2 }
  Plan $E2 2 $PlanA2
  $Y = Fase $E2
  Igual 'hecha con dos intentos' 'hecha 2' "$($Y.Tarea.estado) $($Y.Tarea.intentos)"
  Comprueba 'el segundo prompt nombra la clave que se borro' ((Prompt-De $E2 2) -match 'app\.ruta') (Prompt-De $E2 2)
  Igual 'el yml bueno' $YmlA2 (Lee $E2.Repo $Yml)
}

# ================================ REGLA DEL BUILD (una sola vez, en informe.ps1) ================================
$Pruebas['25 i) Get-FallosBuild: compila SI; los tests fallan solo si antes no fallaban (la regla de Invoke-Cierre)'] = {
  $ok = 'compila: SI | tests: OK'
  $mal = 'compila: SI | tests: FALLAN'
  Igual 'compila y tests OK: sin fallos' 0 @(Get-FallosBuild $ok $ok 'tu rama').Count
  Igual 'compila y tests no ejecutados: sin fallos' 0 @(Get-FallosBuild 'compila: SI | tests: no ejecutados' $ok 'tu rama').Count
  Igual 'tests FALLAN y ya fallaban: sin fallos' 0 @(Get-FallosBuild $mal $mal 'tu rama').Count
  Igual 'tests FALLAN y antes OK: un fallo con el texto de Invoke-Cierre' 'los tests fallan y en tu rama no fallaban' (@(Get-FallosBuild $mal $ok 'tu rama') -join '|')
  Igual 'el sitio de antes lo pone quien llama' 'los tests fallan y en el migrado de antes no fallaban' (@(Get-FallosBuild $mal $ok 'el migrado de antes') -join '|')
  Igual 'tests FALLAN y sin estado de antes: un fallo' 1 @(Get-FallosBuild $mal '' 'tu rama').Count
  Igual 'no compila: un fallo con el texto de Invoke-Cierre' "no compila o no se ha podido comprobar (el diagnostico dice 'compila: NO')" (@(Get-FallosBuild 'compila: NO' $ok 'tu rama') -join '|')
  Igual 'sin estado (no se pudo medir): no compila' "no compila o no se ha podido comprobar (el diagnostico dice '')" (@(Get-FallosBuild '' $ok 'tu rama') -join '|')
  Igual 'no compila y antes tampoco: sigue siendo un fallo' 1 @(Get-FallosBuild 'compila: NO' 'compila: NO' 'tu rama').Count
}

$Pruebas['26 i) la regla del build esta una sola vez fuera de migracion.ps1: en informe.ps1, y arreglo-propiedades.ps1 la usa'] = {
  $con = @(Get-ChildItem -LiteralPath $raiz -File -Filter '*.ps1' | Where-Object { $_.Name -cne 'migracion.ps1' } | Where-Object { [System.IO.File]::ReadAllText($_.FullName).Contains("-cnotlike 'compila: SI*'") } | ForEach-Object { $_.Name })
  Igual 'el -cnotlike de compila: SI* solo en informe.ps1' 'informe.ps1' ($con -join ',')
  $codigo = [System.IO.File]::ReadAllText((Join-Path $raiz 'arreglo-propiedades.ps1'))
  Comprueba 'arreglo-propiedades.ps1 llama a Get-FallosBuild' ($codigo -match 'Get-FallosBuild \$')
  Comprueba 'y no lleva el texto de los tests fallan' (-not $codigo.Contains('tests: FALLAN'))
  $inf = [System.IO.File]::ReadAllText((Join-Path $raiz 'informe.ps1'))
  Igual 'informe.ps1 define Get-FallosBuild una vez' 1 ([regex]::Matches($inf, '(?m)^function Get-FallosBuild\b')).Count
}

Invoke-Banco $Pruebas 'tests/probar-arreglo-propiedades.ps1'
