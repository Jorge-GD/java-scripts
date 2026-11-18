<#
probar-donde.ps1 - Banco de pruebas de donde-estoy.ps1 (M19).
No necesita Maven, Java ni Copilot, y no los llama nunca: monta carpetas migracion-<batch> de juguete (con datos inventados) junto a
una copia de los scripts, y repos de juguete con git. Solo hace falta git.
Vale para Windows PowerShell 5.1 y para PowerShell 7. Solo ASCII a proposito.

  .\tests\probar-donde.ps1                          # todas las pruebas
  .\tests\probar-donde.ps1 -Solo cobertura          # las que llevan 'cobertura' en el nombre
  .\tests\probar-donde.ps1 -Dir D:\tmp\x -Conservar # deja las carpetas de juguete para mirarlas
  .\tests\probar-donde.ps1 -Script C:\otra\donde-estoy.ps1

Cada escenario es una carpeta con los scripts (una copia) en java-scripts\ y los batchs de juguete al lado, como los tiene el usuario.
Sale con 0 si todo pasa y con 1 si algo falla.
#>
param(
  [string]$Dir = '',
  [string]$Script = '',
  [string]$Solo = '',
  [switch]$Conservar
)
$ErrorActionPreference = 'Stop'
$aqui = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $Script) { $Script = Join-Path (Split-Path -Parent $aqui) 'donde-estoy.ps1' }
$origen = Split-Path -Parent $Script
. (Join-Path $aqui 'comun-banco.ps1')
$e_ = [string][char]0xE9   # la e con tilde: el script no lleva tildes en el codigo, pero si en lo que dice
$a_ = [string][char]0xE1
$i_ = [string][char]0xED

# ============================== UTILIDADES ==============================
# Un escenario: <Raiz>\java-scripts (una copia de los scripts) y, al lado, los batchs de juguete.
function Nuevo-Escenario([string]$Nombre) {
  $raiz = Join-Path $Dir $Nombre
  $sc = Join-Path $raiz 'java-scripts'
  [void](New-Item -ItemType Directory -Path $sc -Force)
  foreach ($f in @('comun.ps1', 'tareas.ps1', 'informe.ps1')) { Copy-Item -LiteralPath (Join-Path $origen $f) -Destination (Join-Path $sc $f) }
  Copy-Item -LiteralPath (Join-Path $origen 'informe') -Destination (Join-Path $sc 'informe') -Recurse
  if (Test-Path -LiteralPath $Script) { Copy-Item -LiteralPath $Script -Destination (Join-Path $sc 'donde-estoy.ps1') }
  return [pscustomobject]@{ Raiz = $raiz; Scripts = $sc }
}

function Escribe-Json([string]$Raiz, [string]$Rel, $Objeto) { Escribe $Raiz $Rel (ConvertTo-Json -InputObject $Objeto -Depth 8) }

# Un estado.json de una pasada acabada con la respuesta parar y la prueba en local hecha; $Cambios lo pisa campo a campo.
function Estado-Base([string]$Batch, [string]$Migrado, [hashtable]$Cambios = @{}) {
  $e = [ordered]@{
    version = 1; batch = $Batch; legacy = (Join-Path (Split-Path -Parent $Migrado) 'original-acme'); migrado = $Migrado
    plantilla = (Join-Path (Split-Path -Parent $Migrado) 'referencia-acme'); worktree = ($Migrado + '-rescate')
    rama = 'rescate/feat-recibos-20261118-0900'; ramaOrigen = 'feat/recibos'; javaLegacy = ''
    modelo = 'claude-sonnet-5.5'; aptitud = 'claude-sonnet-5.5'; respuesta = 'parar'; fase = 'hecha'
    creado = '2026-11-18T09:00:00'; actualizado = '2026-11-18T10:00:00'; fin = '2026-11-18T10:00:00'; parada = $null
    pruebaLocal = [ordered]@{ resultado = 'hecha'; codigo = 0; minutos = 3.2; detalle = ''; registro = 'registros/prueba-local.log' }
  }
  foreach ($k in $Cambios.Keys) { $e[$k] = $Cambios[$k] }
  return $e
}

# Un batch de juguete: un repo git en <Raiz>\<Nombre> con su carpeta migracion-<Nombre>\datos\ (git la ignora, como en local).
# $Estado es el estado.json (o $null: sin empezar); $Datos, los demas ficheros de datos\ (ruta relativa -> objeto, que se guarda como json,
# o texto, que se guarda tal cual). Devuelve la carpeta del batch y su carpeta de salida.
function Nuevo-Batch($E, [string]$Nombre, $Estado, $Datos = @{}, [string]$Salida = '') {
  $d = Join-Path $E.Raiz $Nombre
  Escribe $d 'pom.xml' "<project><groupId>com.acme</groupId><artifactId>$Nombre</artifactId></project>`n"
  Escribe $d 'src/main/java/com/acme/Recibo.java' "package com.acme;`npublic class Recibo { }`n"
  Inicia-Repo $d
  [System.IO.File]::AppendAllText((Join-Path $d '.git/info/exclude'), "`nmigracion-*/`n")
  if (-not $Salida) { $Salida = 'migracion-' + $Nombre }
  $s = Join-Path $d $Salida
  if ($Estado) { Escribe-Json $s 'datos/estado.json' $Estado }
  foreach ($k in $Datos.Keys) {
    if ($Datos[$k] -is [string]) { Escribe $s ('datos/' + $k) $Datos[$k] } else { Escribe-Json $s ('datos/' + $k) $Datos[$k] }
  }
  return [pscustomobject]@{ Dir = $d; Salida = $s; Nombre = $Nombre }
}

function Donde($E, [string[]]$A = @()) { return (Lanzar (Join-Path $E.Scripts 'donde-estoy.ps1') $A) }

# La salida partida en bloques: el nombre del batch (de su cabecera '=== <batch> ===') -> sus lineas.
function Bloques([string]$Salida) {
  $r = [ordered]@{}
  $actual = $null
  foreach ($l in ($Salida -split "\r?\n")) {
    if ($l -match '^=== (.+) ===$') { $actual = $Matches[1]; $r[$actual] = New-Object System.Collections.Generic.List[string]; continue }
    if ($null -ne $actual) { $r[$actual].Add($l) }
  }
  return $r
}

# Un campo de un bloque ('Punto', 'Siguiente' o 'Despues'): su texto (una linea) y las lineas sangradas de su comando. $null si no esta.
function Campo-De($Lineas, [string]$Etiqueta) {
  $texto = $null
  $cmd = @()
  $dentro = $false
  foreach ($l in $Lineas) {
    if ($l -match ('^' + $Etiqueta + ':\s+(.*)$')) { $texto = $Matches[1]; $dentro = $true; continue }
    if ($dentro -and $l.StartsWith('    ')) { $cmd += $l.Substring(4); continue }
    $dentro = $false
  }
  if ($null -eq $texto) { return $null }
  return [pscustomobject]@{ Texto = $texto; Comando = @($cmd) }
}

$Despues_ = 'Despu' + $e_ + 's'

# La portada de verdad: el recuadro del siguiente paso que monta Get-SiguienteHtml con Read-DatosInforme entero (como Write-Informes), de cada carpeta
# de salida, en <Destino>\<carpeta>.html. La prueba lo compara con lo que dice donde-estoy.ps1.
function Portadas($E, [string[]]$Salidas) {
  $dest = Join-Path $Dir ('portadas-' + (Split-Path -Leaf $E.Raiz))
  [void](New-Item -ItemType Directory -Path $dest -Force)
  $cod = @(
    '$ErrorActionPreference = ''Stop'''
    '. (Join-Path $PSScriptRoot ''comun.ps1'')'
    '. (Join-Path $PSScriptRoot ''tareas.ps1'')'
    '. (Join-Path $PSScriptRoot ''informe.ps1'')'
    '$marco = Split-Plantilla (Read-PlantillaInforme ''marco.html'')'
    '$pl = Split-Plantilla (Read-PlantillaInforme ''index.html'')'
    '$T = Merge-Trozos $marco.Trozos $pl.Trozos'
    'foreach ($s in @($args | Select-Object -Skip 1)) {'
    '  $D = Read-DatosInforme $s'
    '  [System.IO.File]::WriteAllText((Join-Path $args[0] ((Split-Path $s -Leaf) + ''.html'')), (Get-SiguienteHtml $D $T))'
    '}'
  ) -join "`n"
  Escribe $E.Scripts 'portada-prueba.ps1' $cod
  $r = Lanzar (Join-Path $E.Scripts 'portada-prueba.ps1') (@($dest) + $Salidas)
  if ($r.Codigo -ne 0) { Comprueba 'la portada de juguete se monta' $false (Cola $r.Salida) }
  return $dest
}

# Lo que dice la portada, ya en texto plano segun la prueba: el texto del parrafo y las lineas del comando. Es la prueba, no el script: lo mismo por otro camino.
function Esperado-De([string]$Html) {
  $m = [regex]::Match($Html, '(?s)<p class="lede">(.*?)</p>')
  $texto = ''
  if ($m.Success) { $texto = [System.Net.WebUtility]::HtmlDecode(([regex]::Replace($m.Groups[1].Value, '<[^>]+>', '')).Trim()) }
  $c = [regex]::Match($Html, '(?s)<pre class="cmd">(.*?)</pre>')
  $cmd = @()
  if ($c.Success) { $cmd = @([System.Net.WebUtility]::HtmlDecode($c.Groups[1].Value) -split "\r?\n") }
  return [pscustomobject]@{ Texto = $texto; Comando = @($cmd) }
}

# El codigo de un script sin su cabecera de ayuda ni sus comentarios de linea entera.
function Codigo-De([string]$Ruta) { return ([System.IO.File]::ReadAllText($Ruta) -replace '(?s)^<#.*?#>', '' -replace '(?m)^\s*#.*$', '') }

# Una foto de una carpeta: cada fichero con su tamano y su fecha, ordenados. Las fechas se ponen antiguas antes, para que cualquier escritura se note.
function Envejece([string]$Carpeta) {
  foreach ($f in @(Get-ChildItem -LiteralPath $Carpeta -Recurse -File)) { [System.IO.File]::SetLastWriteTimeUtc($f.FullName, [datetime]::new(2026, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc)) }
}
function Foto([string]$Carpeta) {
  $base = (Resolve-Path -LiteralPath $Carpeta).Path
  return ((@(Get-ChildItem -LiteralPath $Carpeta -Recurse -File | ForEach-Object { $_.FullName.Substring($base.Length) + '|' + $_.Length + '|' + $_.LastWriteTimeUtc.Ticks } | Sort-Object)) -join "`n")
}

function Diag-Error([string]$Batch, [int]$Errores) {
  $h = @()
  for ($i = 1; $i -le $Errores; $i++) { $h += [ordered]@{ Cat = 'estructura'; Sev = 'error'; Fichero = 'src/main/java/com/acme/Recibo.java'; Linea = $i; Detalle = "Falta la capa de servicio $i" } }
  $md = "# Diagnostico de rescate: $Batch`n`n- Fecha: 2026-11-18 09:00`n- Paquete base: com.acme`n- Estado: compila`n`n| Paso | Errores | Avisos |`n|---|---|---|`n| estructura | $Errores | 0 |`n"
  return @{ 'hallazgos-antes.json' = @($h); 'diagnostico-antes.md' = $md }
}

function Correccion-Datos([bool]$Completa = $true) {
  return [ordered]@{
    completa = $Completa; codigo = 0; rama = 'rescate/feat-recibos-20261118-0900'; base = 'feat/recibos'
    commits = @([ordered]@{ hash = 'abc1234'; paso = 'estructura'; asunto = 'rescate(estructura): lote 1' }); atascados = @(); resueltos = @(); variablesNuevas = @()
  }
}

function Local-Datos([int]$Distintos) {
  $casos = @([ordered]@{ job = 'cargaJob'; caso = 'caso-01'; titulo = 'Recibo correcto'; resultado = 'igual' })
  for ($i = 1; $i -le $Distintos; $i++) { $casos += [ordered]@{ job = 'cargaJob'; caso = "caso-d$i"; titulo = "Distinto $i"; resultado = 'distinto' } }
  return [ordered]@{ jobs = @([ordered]@{ job = 'cargaJob'; casos = $casos.Count; iguales = 1; distintos = $Distintos; sinProbar = 0 }); casos = $casos }
}

function Cobertura-Datos([double]$Pct, [bool]$Medida = $true) {
  if ($Medida) { return [ordered]@{ medida = $true; porcentaje = $Pct; cubiertas = [int]($Pct * 10); total = 1000; minima = 80; motivo = '' } }
  return [ordered]@{ medida = $false; porcentaje = $null; cubiertas = $null; total = $null; minima = 80; motivo = 'el migrado no compila' }
}

# ============================== PRUEBAS ==============================
$Pruebas = [ordered]@{}

$Pruebas['a) sin estado.json: Sin empezar y el comando de migracion.ps1 con -SoloInforme y las rutas entre comillas'] = {
  $E = Nuevo-Escenario 'a'
  $b = Nuevo-Batch $E 'batch-recibos' $null
  $r = Donde $E @('-Migrado', $b.Dir)
  Igual 'sale con 0' 0 $r.Codigo
  $bl = Bloques $r.Salida
  Comprueba 'hay un bloque, el del batch' (@($bl.Keys).Count -eq 1 -and @($bl.Keys)[0] -ceq 'batch-recibos') (Cola $r.Salida)
  $p = Campo-De $bl['batch-recibos'] 'Punto'
  Comprueba 'el punto dice Sin empezar' ($p -and $p.Texto -match 'Sin empezar') (Cola $r.Salida)
  $s = Campo-De $bl['batch-recibos'] 'Siguiente'
  Comprueba 'hay un siguiente con su comando' ($s -and $s.Comando.Count -eq 1) (Cola $r.Salida)
  if ($s -and $s.Comando.Count -eq 1) {
    Igual 'sin -Legacy, la ruta de ejemplo del original' ('.\migracion.ps1 -Legacy "C:\ruta\original" -Migrado "' + $b.Dir + '" -SoloInforme') $s.Comando[0]
  }
  $r2 = Donde $E @('-Migrado', $b.Dir, '-Legacy', (Join-Path $E.Raiz 'original acme'))
  $s2 = Campo-De (Bloques $r2.Salida)['batch-recibos'] 'Siguiente'
  Comprueba 'con -Legacy, su ruta (con espacios) entre comillas' ($s2 -and $s2.Comando.Count -eq 1 -and $s2.Comando[0] -ceq ('.\migracion.ps1 -Legacy "' + (Join-Path $E.Raiz 'original acme') + '" -Migrado "' + $b.Dir + '" -SoloInforme')) (Cola $r2.Salida)
  Comprueba 'sin estado no hay linea Despues' ($null -eq (Campo-De $bl['batch-recibos'] $Despues_))
  # una carpeta migracion-* sin datos\estado.json tambien es sin empezar
  $c = Nuevo-Batch $E 'batch-vacio' $null @{} 'migracion-batch-vacio'
  [void](New-Item -ItemType Directory -Path (Join-Path $c.Salida 'registros') -Force)
  $r3 = Donde $E @('-Migrado', $c.Dir)
  $p3 = Campo-De (Bloques $r3.Salida)['batch-vacio'] 'Punto'
  Comprueba 'una carpeta migracion-* sin estado.json: Sin empezar' ($p3 -and $p3.Texto -match 'Sin empezar') (Cola $r3.Salida)
  $r4 = Donde $E @('-Migrado', (Join-Path $E.Raiz 'no-existe'))
  Comprueba 'una ruta que no existe no es Sin empezar: falla y lo dice' ($r4.Codigo -ne 0 -and $r4.Salida -match 'no-existe' -and $r4.Salida -notmatch 'Sin empezar') (Cola $r4.Salida)
}

# Los casos de la portada: nombre del batch -> estado y datos. Cada uno es un batch del escenario de la prueba b.
function Casos-Siguiente([string]$Raiz) {
  $c = [ordered]@{}
  $c['b-corriendo'] = @{ Estado = @{ fin = ''; fase = 'mapa' }; Datos = @{ } }
  $c['b-parada'] = @{ Estado = @{ fase = 'correccion'; parada = [ordered]@{ motivo = 'copilot-no-responde'; detalle = '6 llamadas seguidas han fallado'; registro = 'registros/correccion.log'; ayuda = 'Pega esto en Copilot' } }; Datos = @{ } }
  $c['b-cortada'] = @{ Estado = @{ fase = 'comparar' }; Datos = @{ } }
  $c['b-distinto-corregido'] = @{ Estado = @{ respuesta = 'corregir' }; Datos = @{ 'prueba-local.json' = (Local-Datos 2); 'correcciones.json' = (Correccion-Datos $true) } }
  $c['b-local-fallo'] = @{ Estado = @{ pruebaLocal = [ordered]@{ resultado = 'fallo'; codigo = 1; minutos = 1.5; detalle = 'Maven no arranca'; registro = 'registros/prueba-local.log' } }; Datos = @{ } }
  $c['b-parar-con-problemas'] = @{ Estado = @{ respuesta = 'parar' }; Datos = (Diag-Error 'b-parar-con-problemas' 2) }
  $c['b-corregido'] = @{ Estado = @{ respuesta = 'corregir' }; Datos = @{ 'correcciones.json' = (Correccion-Datos $true) } }
  $c['b-pre'] = @{ Estado = @{ respuesta = 'parar' }; Datos = @{ } }
  return $c
}

$Pruebas['b) cada caso: el texto y el comando son los de la portada (Get-SiguienteHtml), sin HTML'] = {
  $E = Nuevo-Escenario 'b'
  $casos = Casos-Siguiente $E.Raiz
  $batches = @{}
  foreach ($n in $casos.Keys) {
    $d = Join-Path $E.Raiz $n
    $batches[$n] = Nuevo-Batch $E $n (Estado-Base $n $d $casos[$n].Estado) $casos[$n].Datos
  }
  $dest = Portadas $E @($casos.Keys | ForEach-Object { $batches[$_].Salida })
  $r = Donde $E
  Igual 'sale con 0' 0 $r.Codigo
  $bl = Bloques $r.Salida
  Igual 'un bloque por batch' $casos.Count @($bl.Keys).Count
  foreach ($n in $casos.Keys) {
    $esp = Esperado-De ([System.IO.File]::ReadAllText((Join-Path $dest ('migracion-' + $n + '.html'))))
    $s = $null
    if ($bl.Contains($n)) { $s = Campo-De $bl[$n] 'Siguiente' }
    Comprueba "$n : tiene su Siguiente" ($null -ne $s) (Cola $r.Salida)
    if ($null -eq $s) { continue }
    Igual "$n : el texto es el de la portada sin HTML" $esp.Texto $s.Texto
    Igual "$n : el comando es el de la portada, linea a linea" ($esp.Comando -join ' / ') ($s.Comando -join ' / ')
    Comprueba "$n : no queda ninguna etiqueta HTML" ($s.Texto -notmatch '<[a-z/]') $s.Texto
  }
  # los literales de la portada, para que la prueba no dependa solo de repetir la misma conversion
  $c = Campo-De $bl['b-corriendo'] 'Siguiente'
  Comprueba 'corriendo: dice la fase y el comando de la pasada' ($c.Texto -cmatch '^Sigue trabajando: va por la fase mapa\.' -and $c.Comando.Count -eq 1 -and $c.Comando[0] -ceq ('.\migracion.ps1 -Legacy "' + (Join-Path $E.Raiz 'original-acme') + '" -Migrado "' + (Join-Path $E.Raiz 'b-corriendo') + '" -Plantilla "' + (Join-Path $E.Raiz 'referencia-acme') + '" -Modelo claude-sonnet-5.5 -SoloInforme')) ($c.Texto + ' // ' + ($c.Comando -join ' / '))
  $c = Campo-De $bl['b-parada'] 'Siguiente'
  Comprueba 'parada: Copilot no responde' ($c.Texto -cmatch '^Se ha parado porque Copilot no responde') $c.Texto
  $c = Campo-De $bl['b-corregido'] 'Siguiente'
  Igual 'corregido: tres comandos de git, cada uno en su linea' 3 $c.Comando.Count
  Comprueba 'corregido: el ultimo es el merge de la rama de rescate' ($c.Comando.Count -eq 3 -and $c.Comando[2] -ceq ('git -C "' + (Join-Path $E.Raiz 'b-corregido') + '" merge rescate/feat-recibos-20261118-0900')) ($c.Comando -join ' / ')
  $c = Campo-De $bl['b-pre'] 'Siguiente'
  Comprueba 'pre: texto y ningun comando' ($c.Texto -cmatch 'Pru.balo en pre' -and $c.Comando.Count -eq 0) ($c.Texto + ' // ' + ($c.Comando -join ' / '))
  $c = Campo-De $bl['b-parar-con-problemas'] 'Siguiente'
  Comprueba 'parar-con-problemas: cuenta los 2 problemas y manda a corregir con -Si' ($c.Texto -cmatch 'corregir los 2 problemas' -and $c.Comando.Count -eq 1 -and $c.Comando[0].EndsWith(' -Si')) ($c.Texto + ' // ' + ($c.Comando -join ' / '))
  $c = Campo-De $bl['b-local-fallo'] 'Siguiente'
  Comprueba 'local-fallo: dice el detalle' ($c.Texto -match 'Maven no arranca') $c.Texto
}

$Pruebas['c) cobertura: por debajo del minimo sale Despues con -Cobertura; por encima o sin medida, no'] = {
  $E = Nuevo-Escenario 'c'
  $b70 = Nuevo-Batch $E 'cob-70' (Estado-Base 'cob-70' (Join-Path $E.Raiz 'cob-70')) @{ 'cobertura-antes.json' = (Cobertura-Datos 70) }
  [void](Nuevo-Batch $E 'cob-85' (Estado-Base 'cob-85' (Join-Path $E.Raiz 'cob-85')) @{ 'cobertura-antes.json' = (Cobertura-Datos 85) })
  [void](Nuevo-Batch $E 'cob-sin-medir' (Estado-Base 'cob-sin-medir' (Join-Path $E.Raiz 'cob-sin-medir')) @{ 'cobertura-antes.json' = (Cobertura-Datos 0 $false) })
  [void](Nuevo-Batch $E 'cob-ninguna' (Estado-Base 'cob-ninguna' (Join-Path $E.Raiz 'cob-ninguna')) @{ })
  [void](Nuevo-Batch $E 'cob-despues-sube' (Estado-Base 'cob-despues-sube' (Join-Path $E.Raiz 'cob-despues-sube')) @{ 'cobertura-antes.json' = (Cobertura-Datos 70); 'cobertura-despues.json' = (Cobertura-Datos 85) })
  [void](Nuevo-Batch $E 'cob-despues-baja' (Estado-Base 'cob-despues-baja' (Join-Path $E.Raiz 'cob-despues-baja')) @{ 'cobertura-antes.json' = (Cobertura-Datos 90); 'cobertura-despues.json' = (Cobertura-Datos 60) })
  [void](Nuevo-Batch $E 'cob-decimal' (Estado-Base 'cob-decimal' (Join-Path $E.Raiz 'cob-decimal')) @{ 'cobertura-antes.json' = (Cobertura-Datos 79.5) })
  $r = Donde $E
  Igual 'sale con 0' 0 $r.Codigo
  $bl = Bloques $r.Salida
  $d = Campo-De $bl['cob-70'] $Despues_
  Comprueba 'al 70 %: La cobertura es 70 % (minimo 80 %)' ($d -and $d.Texto -cmatch ('^La cobertura es 70 % \(m' + $i_ + 'nimo 80 %\)')) (Cola $r.Salida)
  Comprueba 'al 70 %: el comando es rescate.ps1 -Repo con la ruta entre comillas y -Cobertura' ($d -and $d.Comando.Count -eq 1 -and $d.Comando[0] -ceq ('.\rescate.ps1 -Repo "' + (Join-Path $E.Raiz 'cob-70') + '" -Cobertura')) (Cola $r.Salida)
  Comprueba 'al 85 %: no sale Despues' ($null -eq (Campo-De $bl['cob-85'] $Despues_))
  Comprueba 'sin medir (con su motivo): no sale Despues' ($null -eq (Campo-De $bl['cob-sin-medir'] $Despues_))
  Comprueba 'sin fichero de cobertura: no sale Despues' ($null -eq (Campo-De $bl['cob-ninguna'] $Despues_))
  Comprueba 'antes 70 y despues 85: manda la de despues, no sale' ($null -eq (Campo-De $bl['cob-despues-sube'] $Despues_))
  $d = Campo-De $bl['cob-despues-baja'] $Despues_
  Comprueba 'antes 90 y despues 60: manda la de despues, sale con 60 %' ($d -and $d.Texto -match 'es 60 %') (Cola $r.Salida)
  $d = Campo-De $bl['cob-decimal'] $Despues_
  Comprueba 'al 79,5 %: sale, con coma decimal como la portada' ($d -and $d.Texto -match 'es 79,5 %') (Cola $r.Salida)
  # el minimo es el de $Cfg.CoberturaMinima, no el que traiga el json
  $E2 = Nuevo-Escenario 'c2'
  $x = Cobertura-Datos 70
  $x.minima = 50
  [void](Nuevo-Batch $E2 'cob-min-50' (Estado-Base 'cob-min-50' (Join-Path $E2.Raiz 'cob-min-50')) @{ 'cobertura-antes.json' = $x })
  $r2 = Donde $E2
  $d = Campo-De (Bloques $r2.Salida)['cob-min-50'] $Despues_
  Comprueba 'el minimo que dice es el de Cfg (80), no el del json (50)' ($d -and $d.Texto -match ('m' + $i_ + 'nimo 80 %')) (Cola $r2.Salida)
}

$Pruebas['d) un estado.json antiguo, sin ramaOrigen ni javaLegacy: no falla y da su punto'] = {
  $E = Nuevo-Escenario 'd'
  $d = Join-Path $E.Raiz 'batch-antiguo'
  $viejo = [ordered]@{
    version = 1; batch = 'batch-antiguo'; legacy = (Join-Path $E.Raiz 'original-acme'); migrado = $d; plantilla = (Join-Path $E.Raiz 'referencia-acme')
    modelo = 'claude-sonnet-5.5'; respuesta = 'parar'; fase = 'fichas-clase'; creado = '2026-11-10T09:00:00'; actualizado = '2026-11-10T09:30:00'; fin = '2026-11-10T09:30:00'
  }
  $b = Nuevo-Batch $E 'batch-antiguo' $viejo
  $r = Donde $E @('-Migrado', $b.Dir)
  Igual 'sale con 0' 0 $r.Codigo
  Comprueba 'no escribe ningun error' ($r.Salida -notmatch '(?i)exception|cannot |at line|error:') (Cola $r.Salida)
  $bl = Bloques $r.Salida
  $p = Campo-De $bl['batch-antiguo'] 'Punto'
  Comprueba 'da su punto: la fase y la fecha del fin' ($p -and $p.Texto -match 'fichas-clase' -and $p.Texto -match '10-11-2026 09:30') (Cola $r.Salida)
  $s = Campo-De $bl['batch-antiguo'] 'Siguiente'
  Comprueba 'da su siguiente: cortada, con el comando de la pasada' ($s -and $s.Texto -match 'cortado' -and $s.Comando.Count -eq 1 -and $s.Comando[0].StartsWith('.\migracion.ps1 -Legacy ')) (Cola $r.Salida)
  # el estado mas viejo posible: casi vacio
  $E2 = Nuevo-Escenario 'd2'
  $b2 = Nuevo-Batch $E2 'batch-nada' ([ordered]@{ version = 1; batch = 'batch-nada'; migrado = (Join-Path $E2.Raiz 'batch-nada'); fase = 'mapa' })
  $r2 = Donde $E2 @('-Migrado', $b2.Dir)
  Comprueba 'un estado casi vacio tampoco falla' ($r2.Codigo -eq 0 -and $null -ne (Campo-De (Bloques $r2.Salida)['batch-nada'] 'Siguiente')) (Cola $r2.Salida)
  # un estado.json roto se dice y no tumba a los demas
  $E3 = Nuevo-Escenario 'd3'
  [void](Nuevo-Batch $E3 'batch-a' (Estado-Base 'batch-a' (Join-Path $E3.Raiz 'batch-a')))
  [void](Nuevo-Batch $E3 'batch-b' $null @{ 'estado.json' = '{ esto no es json' })
  $r3 = Donde $E3
  $bl3 = Bloques $r3.Salida
  Comprueba 'un estado.json roto: el otro batch sale igual y el roto lo dice' ($r3.Codigo -eq 0 -and $bl3.Contains('batch-a') -and $bl3.Contains('batch-b') -and (($bl3['batch-b'] -join ' ') -match 'estado\.json')) (Cola $r3.Salida)
}

$Pruebas['e) sin -Migrado: un bloque por batch con estado.json, en orden alfabetico'] = {
  $E = Nuevo-Escenario 'e'
  [void](Nuevo-Batch $E 'batch-b' (Estado-Base 'batch-b' (Join-Path $E.Raiz 'batch-b')))
  [void](Nuevo-Batch $E 'batch-c' $null)
  [void](Nuevo-Batch $E 'batch-a' (Estado-Base 'batch-a' (Join-Path $E.Raiz 'batch-a') @{ fase = 'mapa'; fin = '' }))
  Escribe $E.Raiz 'otra-carpeta/leeme.txt' 'no es un batch'
  $r = Donde $E
  Igual 'sale con 0' 0 $r.Codigo
  $bl = Bloques $r.Salida
  Igual 'dos bloques (el batch sin estado.json no sale)' 2 @($bl.Keys).Count
  Igual 'en orden alfabetico' 'batch-a|batch-b' (@($bl.Keys) -join '|')
  Comprueba 'el que corre dice que corre' ((Campo-De $bl['batch-a'] 'Punto').Texto -match 'mapa' -and (Campo-De $bl['batch-a'] 'Punto').Texto -match 'corriendo') (Cola $r.Salida)
  Comprueba 'el que acabo dice terminado' ((Campo-De $bl['batch-b'] 'Punto').Texto -match 'terminado') (Cola $r.Salida)
  $lineas = @($r.Salida -split "\r?\n" | Where-Object { $_.Trim() })
  Comprueba 'la ultima linea manda a FLUJO.md' ($lineas[-1] -cmatch ('^Los pasos completos est' + $a_ + 'n en FLUJO\.md\.?$')) $lineas[-1]
  # con -Migrado solo sale ese
  $r2 = Donde $E @('-Migrado', (Join-Path $E.Raiz 'batch-b'))
  Igual 'con -Migrado, solo ese bloque' 'batch-b' (@((Bloques $r2.Salida).Keys) -join '|')
  # ningun batch
  $E0 = Nuevo-Escenario 'e0'
  Escribe $E0.Raiz 'otra-carpeta/leeme.txt' 'no es un batch'
  $r0 = Donde $E0
  Comprueba 'sin ningun batch lo dice y apunta a -Migrado' ($r0.Codigo -eq 0 -and $r0.Salida -match '-Migrado' -and @((Bloques $r0.Salida).Keys).Count -eq 0) (Cola $r0.Salida)
}

$Pruebas['f) solo lectura: ni un fichero de migracion-* ni el repo cambian'] = {
  $E = Nuevo-Escenario 'f'
  $b1 = Nuevo-Batch $E 'batch-uno' (Estado-Base 'batch-uno' (Join-Path $E.Raiz 'batch-uno') @{ respuesta = 'corregir' }) (@{ 'correcciones.json' = (Correccion-Datos $true); 'cobertura-antes.json' = (Cobertura-Datos 70); 'prueba-local.json' = (Local-Datos 0) })
  $b2 = Nuevo-Batch $E 'batch-dos' (Estado-Base 'batch-dos' (Join-Path $E.Raiz 'batch-dos') @{ fin = ''; fase = 'mapa' })
  $b3 = Nuevo-Batch $E 'batch-tres' $null
  Escribe $b1.Salida 'index.html' '<html>portada</html>'
  Escribe $b1.Salida 'registros/correccion.log' 'linea'
  $todos = @($b1, $b2, $b3)
  foreach ($b in $todos) { Envejece $b.Dir }
  $antes = @{}
  $gitAntes = @{}
  foreach ($b in $todos) { $antes[$b.Nombre] = Foto $b.Salida; $gitAntes[$b.Nombre] = GitEn $b.Dir @('status', '--porcelain', '--ignored') }
  $r1 = Donde $E
  $r2 = Donde $E @('-Migrado', $b1.Dir)
  $r3 = Donde $E @('-Migrado', $b3.Dir, '-Legacy', (Join-Path $E.Raiz 'original-acme'))
  Comprueba 'las tres llamadas salen con 0' ($r1.Codigo -eq 0 -and $r2.Codigo -eq 0 -and $r3.Codigo -eq 0) (Cola $r1.Salida)
  foreach ($b in $todos) {
    Igual ($b.Nombre + ' : mismos ficheros, tamanos y fechas') $antes[$b.Nombre] (Foto $b.Salida)
    Igual ($b.Nombre + ' : mismo git status --porcelain --ignored') $gitAntes[$b.Nombre] (GitEn $b.Dir @('status', '--porcelain', '--ignored'))
  }
  Comprueba 'no deja nada nuevo junto a los scripts' (@(Get-ChildItem -LiteralPath $E.Scripts -File | Where-Object { $_.Name -notin @('comun.ps1', 'tareas.ps1', 'informe.ps1', 'donde-estoy.ps1') }).Count -eq 0)
  # y el script no llama a nada que escriba, ni a Copilot ni a Maven
  if (Test-Path -LiteralPath $Script) {
    $t = Codigo-De $Script
    Comprueba 'el codigo no llama a git, mvn ni copilot' ($t -notmatch '(?i)(^|[\s;(&|])(git|mvn|mvnw|copilot)(\.exe|\.cmd)?\s+-' -and $t -notmatch 'Invoke-Nativo|Invoke-Proceso|Get-Lanzador|Invoke-Llamadas|Invoke-Ronda|Start-Process')
    Comprueba 'el codigo no escribe: nada de Save/Write/Set/Out/Add/New/Remove/Move/Copy' ($t -notmatch 'Save-Json|Write-Json|Write-Informes|Save-Pagina|Set-Content|Out-File|Add-Content|New-Item|Remove-Item|Move-Item|Copy-Item|Rename-Item|WriteAll|AppendAll|\.Delete\(|SetLastWrite')
  }
}

$Pruebas['g) preflight: sin preflight-resultado.txt junto a los scripts sale la linea del preflight; con el, no'] = {
  $E = Nuevo-Escenario 'g'
  [void](Nuevo-Batch $E 'batch-a' (Estado-Base 'batch-a' (Join-Path $E.Raiz 'batch-a')))
  $r = Donde $E
  Igual 'sale con 0' 0 $r.Codigo
  $lineas = @($r.Salida -split "\r?\n")
  $i = -1
  for ($k = 0; $k -lt $lineas.Count; $k++) { if ($lineas[$k] -match 'No has pasado el preflight en este equipo') { $i = $k; break } }
  Comprueba 'sale No has pasado el preflight en este equipo' ($i -ge 0) (Cola $r.Salida)
  Comprueba 'va al principio, antes del primer batch' ($i -ge 0 -and $i -lt (@($lineas | Where-Object { $_ -match '^=== ' } | ForEach-Object { [array]::IndexOf($lineas, $_) })[0])) (Cola $r.Salida)
  Comprueba 'con su comando, sangrado y en su linea: .\preflight.ps1' ($i -ge 0 -and @($lineas | Where-Object { $_ -ceq '    .\preflight.ps1' }).Count -eq 1) (Cola $r.Salida)
  Escribe $E.Scripts 'preflight-resultado.txt' "resultado inventado`n"
  $r2 = Donde $E
  Comprueba 'con preflight-resultado.txt no sale la linea ni el comando' ($r2.Codigo -eq 0 -and $r2.Salida -notmatch 'preflight') (Cola $r2.Salida)
  Comprueba 'y el bloque del batch sale igual' ($r2.Salida -match '=== batch-a ===') (Cola $r2.Salida)
}

$Pruebas['h) entidades HTML: &quot;, &amp;, &lt; y &gt; salen como " & < >'] = {
  $E = Nuevo-Escenario 'h'
  $n = 'lote&recibos'
  $dir = Join-Path $E.Raiz $n
  [void](Nuevo-Batch $E $n (Estado-Base $n $dir @{ fin = ''; fase = 'mapa' }))
  # sin ramaOrigen ni base de correccion: la rama de origen es el texto <tu-rama>, que el HTML escribe con &lt; y &gt;
  $m2 = 'lote-sin-origen'
  $dir2 = Join-Path $E.Raiz $m2
  [void](Nuevo-Batch $E $m2 (Estado-Base $m2 $dir2 @{ respuesta = 'corregir'; ramaOrigen = ''; rama = '' }) @{ 'correcciones.json' = [ordered]@{ completa = $true; codigo = 0; rama = 'rescate/x'; base = ''; commits = @([ordered]@{ hash = 'abc'; paso = 'estructura'; asunto = 'x' }); atascados = @(); resueltos = @(); variablesNuevas = @() } })
  # un detalle con comillas, & y < >: va al texto, no al comando
  $m3 = 'lote-detalle'
  [void](Nuevo-Batch $E $m3 (Estado-Base $m3 (Join-Path $E.Raiz $m3) @{ pruebaLocal = [ordered]@{ resultado = 'fallo'; codigo = 1; minutos = 1; detalle = 'Maven dice <fallo> & "algo"'; registro = 'x.log' } }))
  $r = Donde $E
  Igual 'sale con 0' 0 $r.Codigo
  Comprueba 'no queda ninguna entidad sin decodificar' ($r.Salida -notmatch '&(quot|amp|lt|gt|#39);') (Cola $r.Salida)
  $bl = Bloques $r.Salida
  $s = Campo-De $bl[$n] 'Siguiente'
  Comprueba 'una ruta con & sale con & y las comillas del comando con "' ($s -and $s.Comando.Count -eq 1 -and $s.Comando[0].Contains('-Migrado "' + $dir + '"')) (Cola $r.Salida)
  $s2 = Campo-De $bl[$m2] 'Siguiente'
  Comprueba 'la rama <tu-rama> sale con < y >' ($s2 -and $s2.Comando.Count -eq 3 -and $s2.Comando[0].Contains('"<tu-rama>..rescate/x"')) (Cola $r.Salida)
  $s3 = Campo-De $bl[$m3] 'Siguiente'
  Comprueba 'el detalle del texto sale con <fallo>, & y las comillas dobles, y no se confunde con una etiqueta' ($s3 -and $s3.Texto.Contains('Maven dice <fallo> & "algo"')) (Cola $r.Salida)
}

$Pruebas['i) varias carpetas migracion-*: se usa la del estado.json mas reciente; la fecha es la de fin o la del fichero'] = {
  $E = Nuevo-Escenario 'i'
  $d = Join-Path $E.Raiz 'batch-doble'
  $b = Nuevo-Batch $E 'batch-doble' (Estado-Base 'batch-doble' $d @{ fase = 'mapa'; fin = '' }) @{} 'migracion-viejo'
  Escribe-Json $d 'migracion-nuevo/datos/estado.json' (Estado-Base 'batch-doble' $d @{ fase = 'hecha'; fin = '2026-11-18T12:00:00' })
  [System.IO.File]::SetLastWriteTime((Join-Path $d 'migracion-viejo/datos/estado.json'), [datetime]::new(2026, 11, 1, 8, 30, 0))
  [System.IO.File]::SetLastWriteTime((Join-Path $d 'migracion-nuevo/datos/estado.json'), [datetime]::new(2026, 11, 18, 12, 0, 0))
  $r = Donde $E @('-Migrado', $d)
  $bl = Bloques $r.Salida
  $p = Campo-De $bl['batch-doble'] 'Punto'
  Comprueba 'con -Migrado usa la carpeta nueva: terminado, con la fecha de su fin' ($p -and $p.Texto -match 'terminado' -and $p.Texto -match '18-11-2026 12:00') (Cola $r.Salida)
  $r2 = Donde $E
  $p2 = Campo-De (Bloques $r2.Salida)['batch-doble'] 'Punto'
  Comprueba 'sin -Migrado tambien, y un solo bloque' ($p2 -and $p2.Texto -match 'terminado' -and @((Bloques $r2.Salida).Keys).Count -eq 1) (Cola $r2.Salida)
  # al reves: la vieja pasa a ser la mas reciente y, sin fin, su fecha es la del fichero
  [System.IO.File]::SetLastWriteTime((Join-Path $d 'migracion-viejo/datos/estado.json'), [datetime]::new(2026, 11, 19, 7, 45, 0))
  $r3 = Donde $E @('-Migrado', $d)
  $p3 = Campo-De (Bloques $r3.Salida)['batch-doble'] 'Punto'
  Comprueba 'ahora manda la otra: fase mapa, corriendo, con la fecha del fichero (sin fin)' ($p3 -and $p3.Texto -match 'mapa' -and $p3.Texto -match 'corriendo' -and $p3.Texto -match '19-11-2026 07:45') (Cola $r3.Salida)
}

$Pruebas['j) cabecera y forma del script: ASCII, USO con ejemplos, sin sintaxis que 5.1 no conoce'] = {
  Comprueba 'existe donde-estoy.ps1' (Test-Path -LiteralPath $Script)
  if (-not (Test-Path -LiteralPath $Script)) { return }
  $bytes = [System.IO.File]::ReadAllBytes($Script)
  Comprueba 'donde-estoy.ps1 es ASCII puro' (@($bytes | Where-Object { $_ -gt 127 }).Count -eq 0)
  Comprueba 'este banco tambien' (@([System.IO.File]::ReadAllBytes($MyInvocation.MyCommand.Path) | Where-Object { $_ -gt 127 }).Count -eq 0)
  $t = [System.IO.File]::ReadAllText($Script)
  Comprueba 'empieza por un bloque de ayuda con USO' ($t -match '(?s)^<#.*\bUSO\b.*#>')
  Comprueba 'la cabecera da ejemplos con y sin -Migrado' ($t -match '(?m)^\s+\.\\donde-estoy\.ps1\s*(#.*)?$' -and $t -match '(?m)^\s+\.\\donde-estoy\.ps1 -Migrado ')
  $codigo = Codigo-De $Script
  Comprueba 'sin ?? ni ?. ni -replace con scriptblock' ($codigo -notmatch '\?\?' -and $codigo -notmatch '\w\?\.' -and $codigo -notmatch '-replace\s+[^|]*,\s*\{')
  Comprueba 'carga comun.ps1 e informe.ps1 con un punto y no carga rescate.ps1' ($t -match "\.\s+\(Join-Path \`$PSScriptRoot 'comun\.ps1'\)" -and $t -match "\.\s+\(Join-Path \`$PSScriptRoot 'informe\.ps1'\)" -and $t -notmatch "\.\s+\(Join-Path \`$PSScriptRoot 'rescate\.ps1'\)")
}

# ================================ LANZADOR ================================
Invoke-Banco $Pruebas $Script
