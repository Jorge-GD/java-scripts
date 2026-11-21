<#
probar-configmap.ps1 - Banco de pruebas de configmap.ps1 (C9: el repo de configmap del batch migrado) y de las opciones -ConfigMap, -Inventario y
-ConfigMapReferencia de migracion.ps1. No necesita Copilot ni Maven: usa el Copilot de mentira tests/falsos/c9-copilot.ps1, que deja rastro de cada
llamada y de cada prompt y escribe lo que le dice el plan de cada prueba. Los repos son de juguete (en una carpeta de pruebas) con datos
inventados (acme-lote-precios, acme-lote-pedidos). Nunca llama al Copilot ni al Maven reales. Vale para Windows PowerShell 5.1 y para PowerShell 7.
Solo ASCII a proposito.

  .\tests\probar-configmap.ps1                     # todas las pruebas
  .\tests\probar-configmap.ps1 -Solo secretos      # las que llevan 'secretos' en el nombre
  .\tests\probar-configmap.ps1 -Dir D:\tmp\x -Conservar

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
. (Join-Path $raiz 'propiedades.ps1')
. (Join-Path $raiz 'configmap.ps1')
$Cfg.CopilotExe = Join-Path $falsos 'c9-copilot.ps1'
$Cfg.SegundosPorLlamada = 120

# ================================ UTILIDADES ================================
$i_ = [string][char]0xED   # la i con tilde de 'si'
$SecretoPre = 'c2VjcmV0bw=='
$SecretoPro = 'cHJvLXNlY3JldG8='
$Valores = @{
  pre = [ordered]@{
    'env.ruta-entrada' = '/data/pre/entrada'; 'env.lote-pedidos-endpoint' = 'https://pedidos.pre.acme.test/api'; 'env.cliente' = '<PENDIENTE>'
    'env.reintentos' = '5'; 'env.url-token' = 'https://auth.pre.acme.test/token'
  }
  pro = [ordered]@{
    'env.ruta-entrada' = '/data/pro/entrada'; 'env.lote-pedidos-endpoint' = 'https://pedidos.acme.test/api'; 'env.cliente' = 'acme-pro'
    'env.reintentos' = '3'; 'env.url-token' = 'https://auth.acme.test/token'
  }
  des = [ordered]@{
    'env.ruta-entrada' = '<PENDIENTE>'; 'env.lote-pedidos-endpoint' = '<PENDIENTE>'; 'env.cliente' = '<PENDIENTE>'
    'env.reintentos' = '<PENDIENTE>'; 'env.url-token' = '<PENDIENTE>'
  }
}
$IdProps = 'configmap-plataforma-plataforma-ci-props-env'
$IdValues = 'configmap-plataforma-plataforma-cd-values-yaml'
$IdCdPre = 'configmap-plataforma-plataforma-cd-pre-cd-yml'
$IdCdPro = 'configmap-plataforma-plataforma-cd-pro-cd-yml'
$IdFlujo = 'configmap-plataforma-github-workflows-cd-yml'
$Plataforma = @('.plataforma/ci/props.env', '.plataforma/cd/values.yaml', '.plataforma/cd/pre/cd.yml', '.plataforma/cd/pro/cd.yml', '.github/workflows/cd.yml')

$YmlBase = @'
spring:
  application:
    name: lote-pedidos
lote:
  entrada: ${env.ruta-entrada}
  endpoint: ${env.lote-pedidos-endpoint}
  cliente: ${env.cliente:acme}
  reintentos: ${env.reintentos:3}
  local: ${lote.entrada}
rest:
  token:
    url: ${env.url-token}
    clave: ${env.url-token-clave}
'@

# El repo de configmap de referencia (con la forma del de verdad y datos inventados): 3 entornos de 4 ficheros, las carpetas de punto y dos ficheros sueltos.
function Ficheros-Referencia {
  $f = [ordered]@{}
  foreach ($e in @('des', 'pre', 'pro')) {
    $f["config/$e/variables"] = "pfx.variables.env.environment=$e`npfx.variables.env.sftp.enabled=true`npfx.variables.env.lote-precios-endpoint=https://precios.$e.acme.test/api`n"
    $f["config/$e/secretos"] = '"variable":"env.rest.token.pass","secreto":"lote-usuario","clave":"pass"' + "`n"
    $f["config/$e/montajes"] = '"name":"krb-conf","mountPath":"/etc/krb","configMap":{"name":"krb-conf"}' + "`n" + '"name":"keytab","mountPath":"/etc/keytab","secret":{"secretName":"lote-precios-keytab"}' + "`n"
    $f["config/$e/recursos"] = "pfx.variables.limits.cpu=500m`npfx.variables.limits.memory=1Gi`n"
  }
  $f['.plataforma/ci/props.env'] = "ANALISIS_CLAVE=`"acme-lote-precios`"`nESCANER_PROYECTO=`"acme-lote-precios`"`nJAVA_VERSION=`"17`"`n"
  $f['.plataforma/cd/values.yaml'] = "configMapType: file`napplicationName: cm-acme-lote-precios`n"
  $f['.plataforma/cd/pre/cd.yml'] = "- id_ci: 41721`n  ficheros_config:`n    - config/pre/variables`n    - config/pre/secretos`n"
  $f['.plataforma/cd/pro/cd.yml'] = "- id_ci: 41722`n  ficheros_config:`n    - config/pro/variables`n    - config/pro/secretos`n- id_ci: 41723`n  ficheros_config:`n    - config/pro/variables`n"
  $f['.github/workflows/cd.yml'] = "name: CD acme-lote-precios`non:`n  workflow_dispatch:`n    inputs:`n      version:`n        required: true`njobs:`n  cd:`n    uses: acme/plataforma-workflows/.github/workflows/cd.yml@v1`n    with:`n      environment: pre`n    secrets: inherit`n"
  $f['README.md'] = "# acme-cm-lote-precios`n`nConfigmap del batch PRECIOS (precios).`n"
  $f['docs/notas.txt'] = "Notas de Precios.`n"
  return $f
}

# Lo que escribe la IA cuando lo hace bien: el texto de referencia con precios cambiado por pedidos (y el id_ci de cada proyecto sin saber).
function Adapta([string]$Texto) { return $Texto.Replace('precios', 'pedidos').Replace('PRECIOS', 'PEDIDOS').Replace('Precios', 'Pedidos') }
function Adapta-Plataforma([string]$Rel, [string]$Texto) {
  $t = Adapta $Texto
  if ($Rel -like '*/cd.yml' -and $Rel -like '.plataforma/*') { $t = $t -replace 'id_ci: \d+', 'id_ci: <PENDIENTE: id_ci>' }
  return $t
}
function Ficheros-Entorno([string]$Env, $Ref, $Vals = $null, [string[]]$ExtraSecretas = @()) {
  if ($null -eq $Vals) { $Vals = $Valores[$Env] }
  $l = @($Vals.Keys | Where-Object { $ExtraSecretas -notcontains $_ } | ForEach-Object { "pfx.variables.$_=$($Vals[$_])" })
  $f = [ordered]@{}
  $f["config/$Env/variables"] = ($l -join "`n") + "`n"
  $s = '"variable":"env.url-token-clave","secreto":"<PENDIENTE: nombre del Secret>","clave":"<PENDIENTE: clave del Secret>"' + "`n"
  foreach ($x in $ExtraSecretas) { $s += '"variable":"' + $x + '","secreto":"<PENDIENTE: nombre del Secret>","clave":"<PENDIENTE: clave del Secret>"' + "`n" }
  $f["config/$Env/secretos"] = $s
  $f["config/$Env/montajes"] = Adapta $Ref["config/$Env/montajes"]
  $f["config/$Env/recursos"] = Adapta $Ref["config/$Env/recursos"]
  return $f
}

# Un escenario: el batch de referencia, el migrado (con su yml), el repo de configmap de referencia y el inventario del original, bajo $Dir\<nombre>.
# Deja el entorno para las pruebas: datos, registros, el Copilot de mentira y sus carpetas de planes, llamadas y prompts.
function Nuevo-Escenario([string]$Nombre, [hashtable]$Op = @{}) {
  $r = Join-Path $Dir $Nombre
  if (Test-Path -LiteralPath $r) { Remove-Item -LiteralPath $r -Recurse -Force }
  $nr = 'acme-lote-precios'; if ($Op.R) { $nr = $Op.R }
  $nm = 'acme-lote-pedidos'; if ($Op.M) { $nm = $Op.M }
  $nc = 'acme-cm-lote-precios'; if ($Op.C) { $nc = $Op.C }
  $yml = $YmlBase; if ($Op.Yml) { $yml = $Op.Yml }
  $e = [pscustomobject]@{
    Raiz = $r; Plantilla = (Join-Path $r $nr); Migrado = (Join-Path $r $nm); Ref = (Join-Path $r $nc); Inv = (Join-Path $r ($nm + '-inventario'))
    Destino = (Join-Path $r 'acme-cm-lote-pedidos'); Planes = (Join-Path $r 'planes'); Prompts = (Join-Path $r 'prompts'); Llamadas = (Join-Path $r 'llamadas.txt')
    Datos = (Join-Path (Join-Path $r 'salida') 'datos'); Registros = (Join-Path (Join-Path $r 'salida') 'registros'); Home = (Join-Path $r 'home')
    Original = (Join-Path $r 'original')
  }
  foreach ($d in @($e.Plantilla, $e.Migrado, $e.Planes, $e.Prompts, $e.Datos, $e.Registros, $e.Home)) { [void](New-Item -ItemType Directory -Path $d -Force) }
  Escribe $e.Plantilla 'pom.xml' "<project><artifactId>$nr</artifactId></project>`n"
  Escribe $e.Migrado 'pom.xml' ("<project xmlns=`"http://maven.apache.org/POM/4.0.0`"><artifactId>$nm</artifactId><properties><java.version>21</java.version></properties></project>`n")
  Escribe $e.Migrado 'src/main/resources/application.yml' ($yml + "`n")
  $ref = Ficheros-Referencia
  foreach ($k in $ref.Keys) { Escribe $e.Ref $k $ref[$k] }
  Escribe $e.Inv 'PRE/app.properties' "ruta.entrada=/data/pre/entrada`nlote.pedidos.endpoint=https://pedidos.pre.acme.test/api`nurl.token=https://auth.pre.acme.test/token`nurl.token.clave=$SecretoPre`nmax.reintentos=5`n"
  Escribe $e.Inv 'PRE/vault' "x=SECRETO_VAULT`n"
  Escribe $e.Inv 'PRE/host' "servidor=HOST_NO_LEER`n"
  Escribe $e.Inv 'PRO/app.properties' "ruta.entrada=/data/pro/entrada`nlote.pedidos.endpoint=https://pedidos.acme.test/api`ncliente=acme-pro`nurl.token=https://auth.acme.test/token`nurl.token.clave=$SecretoPro`nmax.reintentos=3`n"
  Escribe $e.Inv 'PRO/vault.properties' "y=SECRETO_VAULT_PRO`n"
  Escribe $e.Inv 'group_vars/all.yml' "clave_x: SECRETO_GV`n"
  if ($Op.Git) { foreach ($d in @($e.Plantilla, $e.Migrado)) { Inicia-Repo $d } }
  $script:Datos = $e.Datos
  $script:Registros = $e.Registros
  $script:LegacyRoot = $e.Original
  $script:ModeloElegido = ''
  [Environment]::SetEnvironmentVariable('C9_PLANES', $e.Planes)
  [Environment]::SetEnvironmentVariable('C9_LLAMADAS', $e.Llamadas)
  [Environment]::SetEnvironmentVariable('C9_PROMPTS', $e.Prompts)
  return $e
}

# El plan del Copilot de mentira para la tarea $Id: ficheros (ruta -> texto), salida (el texto de .rescate/tareas/<id>.json) y si es el de la llamada con correccion.
function Plan($E, [string]$Id, $Ficheros = $null, [string]$Salida = $null, [bool]$Reintento = $false, [bool]$Falla = $false) {
  $p = [ordered]@{}
  if ($null -ne $Ficheros) { $p['ficheros'] = $Ficheros }
  if ($Salida) { $p['salida'] = $Salida }
  if ($Falla) { $p['falla'] = $true }
  $n = $Id + '.json'
  if ($Reintento) { $n = $Id + '.reintento.json' }
  [System.IO.File]::WriteAllText((Join-Path $E.Planes $n), (ConvertTo-Json -InputObject $p -Depth 6))
}

function Salida-Variables($Lista) {
  return (ConvertTo-Json -InputObject @{ variables = @($Lista | ForEach-Object { [ordered]@{ variable = $_[0]; clave = $_[1]; secreto = [bool]$_[2]; porque = 'Por el nombre.' } }) } -Depth 5)
}

# Lo que contesta la IA a la tarea de variables: cada variable con su clave del inventario (o ninguna). El script no empareja nada por su cuenta.
$ParesBuenos = [ordered]@{
  'env.cliente' = 'cliente'; 'env.lote-pedidos-endpoint' = 'lote.pedidos.endpoint'; 'env.reintentos' = 'max.reintentos'
  'env.ruta-entrada' = 'ruta.entrada'; 'env.url-token' = 'url.token'; 'env.url-token-clave' = 'url.token.clave'
}
function Respuesta-Variables($Pares, [string[]]$Secretas = @()) {
  return (Salida-Variables @($Pares.Keys | ForEach-Object { , @($_, $Pares[$_], ($Secretas -contains $_)) }))
}

# Los planes de una pasada sin fallos: la IA empareja las seis variables del yml de siempre y escribe lo de siempre en cada tarea.
# Las variables de $Pendientes se quedan sin valor (<PENDIENTE>) en todos los entornos.
function Planes-Buenos($E, [string[]]$Pendientes = @()) {
  $ref = Ficheros-Referencia
  Plan $E 'configmap-variables-1' $null (Respuesta-Variables $ParesBuenos)
  foreach ($env in @('des', 'pre', 'pro')) {
    $v = [ordered]@{}
    foreach ($k in $Valores[$env].Keys) { $v[$k] = $Valores[$env][$k] }
    foreach ($k in $Pendientes) { $v[$k] = '<PENDIENTE>' }
    Plan $E "configmap-entorno-$env" (Ficheros-Entorno $env $ref $v)
  }
  $ids = @{ '.plataforma/ci/props.env' = $IdProps; '.plataforma/cd/values.yaml' = $IdValues; '.plataforma/cd/pre/cd.yml' = $IdCdPre; '.plataforma/cd/pro/cd.yml' = $IdCdPro; '.github/workflows/cd.yml' = $IdFlujo }
  foreach ($rel in $Plataforma) { Plan $E $ids[$rel] @{ $rel = (Adapta-Plataforma $rel $ref[$rel]) } }
}

# Una pasada de configmap.ps1 en este proceso. Devuelve el resultado de la fase (Codigo, Ruta...) y lo que sale por la consola.
function Corre($E) {
  $script:Datos = $E.Datos
  $script:Registros = $E.Registros
  $todo = @(Invoke-FaseConfigMap $E.Plantilla $E.Migrado $E.Ref $E.Inv *>&1)
  $res = @($todo | Where-Object { $_ -is [System.Management.Automation.PSCustomObject] })
  $txt = ((@($todo | Where-Object { $_ -isnot [System.Management.Automation.PSCustomObject] }) | ForEach-Object { "$_" }) -join "`n")
  return [pscustomobject]@{ R = $res[0]; Consola = $txt }
}

# Las llamadas que ha recibido el Copilot de mentira: id, reintento, flags y carpeta de trabajo.
function Llamadas-De($E) {
  if (-not (Test-Path -LiteralPath $E.Llamadas)) { return , @() }
  return , @([System.IO.File]::ReadAllLines($E.Llamadas) | Where-Object { $_ } | ForEach-Object {
      $c = $_.Split('|')
      [pscustomobject]@{ Id = $c[0]; Reintento = $c[1]; Flags = $c[2]; Carpeta = $c[3] }
    })
}
function Ids-De($E) { return (@(Llamadas-De $E | ForEach-Object { $_.Id }) -join ',') }
function Ids-Nuevos($E, [int]$Desde) { return ((@(Llamadas-De $E | ForEach-Object { $_.Id }) | Select-Object -Skip $Desde | Sort-Object) -join ',') }

function Lee-Json([string]$Ruta) {
  if (-not (Test-Path -LiteralPath $Ruta)) { return $null }
  return ([System.IO.File]::ReadAllText($Ruta) | ConvertFrom-Json)
}
function Tarea-Guardada($E, [string]$Id) { return (Lee-Json (Join-Path (Join-Path $E.Datos 'tareas') ($Id + '.json'))) }
function Lee-Destino($E, [string]$Rel) { return ([System.IO.File]::ReadAllText((Get-Ruta $E.Destino $Rel), (New-Object System.Text.UTF8Encoding($false)))) }
function Existe-Destino($E, [string]$Rel) { return (Test-Path -LiteralPath (Get-Ruta $E.Destino $Rel)) }
function Pendiente($E) { return (Lee-Destino $E 'PENDIENTE.md') }
function Prompt-De($E, [string]$Id, [int]$N = 1) { return [System.IO.File]::ReadAllText((Join-Path $E.Prompts "$Id-$N.md")) }

# La parte de PENDIENTE.md de una seccion (desde su titulo '## ...' hasta el siguiente).
function Seccion([string]$Texto, [string]$Titulo) {
  $m = [regex]::Match($Texto, '(?ms)^## ' + [regex]::Escape($Titulo) + '\s*$(.*?)(?=^## |\z)')
  return $m.Groups[1].Value
}

# Todos los ficheros de $Carpeta (menos .rescate), con su ruta relativa.
function Ficheros-De([string]$Carpeta) {
  if (-not (Test-Path -LiteralPath $Carpeta)) { return @() }
  return @(Get-ChildItem -LiteralPath $Carpeta -Recurse -File | Where-Object { $_.FullName -notmatch '[\\/]\.rescate[\\/]' })
}

# Cuantas veces sale $Valor en ficheros del repo nuevo, datos, registros, prompts y consola (ni un solo sitio).
function Sale-Valor($E, [string]$Valor, [string]$Consola) {
  $n = 0
  foreach ($c in @($E.Destino, $E.Datos, $E.Registros, $E.Prompts)) {
    if (-not (Test-Path -LiteralPath $c)) { continue }
    foreach ($f in @(Get-ChildItem -LiteralPath $c -Recurse -File)) {
      if ([System.IO.File]::ReadAllText($f.FullName).Contains($Valor)) { $n++ }
    }
  }
  if ($Consola.Contains($Valor)) { $n++ }
  return $n
}

# ================================ PRUEBAS ================================
$Pruebas = [ordered]@{}

# ---- (a) nombres ----
$Pruebas['c9 (a1) nombres: acme-lote-precios y acme-lote-pedidos dan precios y pedidos; acme-cm-lote-precios da acme-cm-lote-pedidos'] = {
  $p = Get-ParteDistintiva 'acme-lote-precios' 'acme-lote-pedidos'
  Igual 'la parte del batch de referencia' 'precios' $p.R
  Igual 'la del migrado' 'pedidos' $p.M
  Igual 'el repo nuevo' 'acme-cm-lote-pedidos' (Get-NombreConfigMap 'acme-cm-lote-precios' $p 'acme-lote-pedidos')
  $q = Get-ParteDistintiva 'lote_precios_diarios_acme' 'lote_pedidos_semanales_acme'
  Igual 'con varios trozos distintos y el mismo final: la de referencia' 'precios_diarios' $q.R
  Igual 'y la del migrado' 'pedidos_semanales' $q.M
  Comprueba 'nombres iguales: no hay parte distintiva' ($null -eq (Get-ParteDistintiva 'acme-lote' 'acme-lote'))
  Comprueba 'uno dentro del otro: tampoco' ($null -eq (Get-ParteDistintiva 'acme-lote' 'acme-lote-pedidos'))
}

$Pruebas['c9 (a2) nombres: si el de referencia no lleva la parte, se llama <migrado>-configmap'] = {
  $p = Get-ParteDistintiva 'acme-lote-precios' 'acme-lote-pedidos'
  Igual 'sin precios en el nombre' 'acme-lote-pedidos-configmap' (Get-NombreConfigMap 'acme-plataforma-config' $p 'acme-lote-pedidos')
}

$Pruebas['c9 (a3) nombres: las mayusculas se respetan dentro de un fichero (PRECIOS pasa a PEDIDOS, Precios a Pedidos)'] = {
  $p = Get-ParteDistintiva 'acme-lote-precios' 'acme-lote-pedidos'
  Igual 'minusculas, MAYUSCULAS y Capital' 'pedidos PEDIDOS Pedidos' (Convert-ParteConfigMap 'precios PRECIOS Precios' $p)
  $q = Get-ParteDistintiva 'lote_precios_diarios_acme' 'lote_pedidos_semanales_acme'
  Igual 'con varios trozos, con su separador' 'pedidos_semanales PEDIDOS_SEMANALES pedidos-semanales' (Convert-ParteConfigMap 'precios_diarios PRECIOS_DIARIOS precios-diarios' $q)
}

$Pruebas['c9 (a4) nombres: una parte de menos de 4 letras para con un mensaje claro y no crea nada'] = {
  $e = Nuevo-Escenario 'a4' @{ R = 'acme-lote-ab'; M = 'acme-lote-cd'; C = 'acme-cm-lote-ab' }
  $x = Corre $e
  Igual 'sale con 1' 1 $x.R.Codigo
  Comprueba 'el mensaje dice que cambiaria trozos de palabras' ($x.Consola -match 'menos de 4 letras' -and $x.Consola -match 'trozos de palabras') $x.Consola
  Comprueba 'no crea el repo nuevo' (-not (Test-Path -LiteralPath (Join-Path $e.Raiz 'acme-cm-lote-cd')))
  Igual 'ni llama a Copilot' 0 @(Llamadas-De $e).Count
}

# ---- (b) variables ----
$Pruebas['c9 (b1) variables: ${env.a} y ${env.b:x} salen, una resuelta dentro del yml no, y sale una por nombre con su fichero y su linea'] = {
  $e = Nuevo-Escenario 'b1' @{ Yml = "a:`n  x: `${env.a}`n  y: `${env.b:x}`n  z: `${a.x}`n  w: `${env.a}`n" }
  Escribe $e.Migrado 'src/main/resources/application-pro.properties' "otra=`${env.c}`n"
  $v = @(Get-VariablesConfigMap $e.Migrado)
  Igual 'los nombres, en orden' 'env.a,env.b,env.c' (($v | ForEach-Object { $_.variable }) -join ',')
  Igual 'env.a: el primer sitio' 'src/main/resources/application.yml:2' "$($v[0].fichero):$($v[0].linea)"
  Igual 'env.b: la linea 3' 3 $v[1].linea
  Igual 'env.c: su fichero' 'src/main/resources/application-pro.properties' $v[2].fichero
}

$Pruebas['c9 (b2) variables: todas van a la tarea de la IA (el script no empareja nada) y la pareja que contesta es la que da los valores'] = {
  $y = "a:`n  x: `${env.ruta-entrada}`n  y: `${env.lote-pedidos-endpoint}`n  z: `${env.url-token-clave}`n"
  $e = Nuevo-Escenario 'b2' @{ Yml = $y }
  Planes-Buenos $e
  Plan $e 'configmap-variables-1' $null (Respuesta-Variables ([ordered]@{ 'env.lote-pedidos-endpoint' = 'lote.pedidos.endpoint'; 'env.ruta-entrada' = 'ruta.entrada'; 'env.url-token-clave' = 'url.token.clave' }))
  $x = Corre $e
  Igual 'sale con 0' 0 $x.R.Codigo
  Igual 'una sola llamada de variables, aunque el nombre case con una clave del inventario' 1 @(Llamadas-De $e | Where-Object { $_.Id -like 'configmap-variables-*' }).Count
  $t = Tarea-Guardada $e 'configmap-variables-1'
  Igual 'con las tres variables' 'env.lote-pedidos-endpoint,env.ruta-entrada,env.url-token-clave' (@($t.entradas.variables) -join ',')
  Comprueba 'el valor de pre sale de la pareja de la IA' ((Prompt-De $e 'configmap-entorno-pre').Contains('- env.ruta-entrada = /data/pre/entrada'))
  $p = Pendiente $e
  Comprueba 'PENDIENTE.md dice que la pareja la puso la IA' ($p -match '(?m)^\| env\.ruta-entrada \|[^|]*`ruta\.entrada`[^|]*IA[^|]*\|') $p
  Comprueba 'y la de lote.pedidos.endpoint tambien' ($p -match '(?m)^\| env\.lote-pedidos-endpoint \|[^|]*`lote\.pedidos\.endpoint`[^|]*IA')
}

$Pruebas['c9 (b3) variables: van en tareas de 10 como mucho, con la lista cerrada de claves sin valores'] = {
  $y = (1..11 | ForEach-Object { 'v' + $_.ToString('00') + ': ${env.v' + $_.ToString('00') + '}' }) -join "`n"
  $e = Nuevo-Escenario 'b3' @{ Yml = $y }
  Plan $e 'configmap-variables-1' $null (Salida-Variables @(1..10 | ForEach-Object { , @('env.v' + $_.ToString('00'), 'ninguna', $false) }))
  Plan $e 'configmap-variables-2' $null (Salida-Variables @(, @('env.v11', 'ninguna', $false)))
  [void](Corre $e)
  $t1 = Tarea-Guardada $e 'configmap-variables-1'
  $t2 = Tarea-Guardada $e 'configmap-variables-2'
  Igual 'la primera lleva 10' 10 @($t1.entradas.variables).Count
  Igual 'la segunda, 1' 1 @($t2.entradas.variables).Count
  Igual 'hay dos llamadas de variables' 2 @(Llamadas-De $e | Where-Object { $_.Id -like 'configmap-variables-*' }).Count
  $p = Prompt-De $e 'configmap-variables-1'
  Comprueba 'el prompt lleva las claves del inventario' ($p.Contains('ruta.entrada') -and $p.Contains('max.reintentos') -and $p.Contains('url.token.clave'))
  Comprueba 'y ningun valor del inventario' (-not $p.Contains('/data/pre/entrada') -and -not $p.Contains($SecretoPre) -and -not $p.Contains('acme-pro'))
  Comprueba 'lleva la linea del yml de la variable' ($p -match 'v03: \$\{env\.v03\}')
  Comprueba 'y el trabajo se hace en el repo nuevo, con el migrado a la vista' ((@(Llamadas-De $e)[0]).Carpeta -eq $e.Destino -and (@(Llamadas-De $e)[0]).Flags.Contains('--add-dir=' + $e.Migrado))
}

$Pruebas['c9 (b4) variables: una respuesta con una clave que no esta en la lista se reintenta con el motivo; la buena se usa'] = {
  $e = Nuevo-Escenario 'b4'
  Planes-Buenos $e
  $mal = [ordered]@{}
  foreach ($k in $ParesBuenos.Keys) { $mal[$k] = $ParesBuenos[$k] }
  $mal['env.reintentos'] = 'no.existe'
  Plan $e 'configmap-variables-1' $null (Respuesta-Variables $mal)
  Plan $e 'configmap-variables-1' $null (Respuesta-Variables $ParesBuenos) $true
  [void](Corre $e)
  $l = @(Llamadas-De $e | Where-Object { $_.Id -eq 'configmap-variables-1' })
  Igual 'dos llamadas, la segunda con correccion' '0,1' (($l | ForEach-Object { $_.Reintento }) -join ',')
  $p2 = Prompt-De $e 'configmap-variables-1' 2
  Comprueba 'el segundo prompt lleva el motivo con la clave mala' ($p2.Contains('no.existe'))
  Igual 'la tarea queda hecha' 'hecha' (Tarea-Guardada $e 'configmap-variables-1').estado
  Comprueba 'el prompt de pre ya lleva el valor de max.reintentos para env.reintentos' ((Prompt-De $e 'configmap-entorno-pre').Contains('- env.reintentos = 5'))
}

$Pruebas['c9 (b5) variables: una respuesta a la que falta una variable, o con una que no se pidio, tambien se reintenta; dos fallos la dejan atascada y las variables quedan sin pareja'] = {
  $e = Nuevo-Escenario 'b5'
  Planes-Buenos $e @('env.reintentos')
  $falta = [ordered]@{}
  foreach ($k in $ParesBuenos.Keys) { if ($k -ne 'env.reintentos') { $falta[$k] = $ParesBuenos[$k] } }
  $falta['env.otra'] = 'max.reintentos'
  Plan $e 'configmap-variables-1' $null (Respuesta-Variables $falta)
  [void](Corre $e)
  $t = Tarea-Guardada $e 'configmap-variables-1'
  Igual 'queda atascada' 'atascada' $t.estado
  Comprueba 'el motivo nombra la variable que faltaba' ($t.motivo.Contains('env.reintentos')) $t.motivo
  Comprueba 'y la que no se pidio' ($t.motivo.Contains('env.otra')) $t.motivo
  Comprueba 'PENDIENTE.md la cuenta entre las atascadas' ((Seccion (Pendiente $e) 'Tareas atascadas').Contains('configmap-variables-1'))
  Comprueba 'sin pareja, todas las variables salen pendientes (menos la secreta)' ((Prompt-De $e 'configmap-entorno-pre').Contains('- env.ruta-entrada = <PENDIENTE>') -and (Prompt-De $e 'configmap-entorno-pre').Contains('- env.url-token-clave (secreto, sin valor)'))
}

# ---- (c) entornos ----
$Pruebas['c9 (c1) entornos: el valor de PRE va a la tabla de pre y el de PRO a la de pro; un entorno sin inventario sale todo pendiente'] = {
  $e = Nuevo-Escenario 'c1'
  Planes-Buenos $e
  [void](Corre $e)
  $pre = Prompt-De $e 'configmap-entorno-pre'
  $pro = Prompt-De $e 'configmap-entorno-pro'
  $des = Prompt-De $e 'configmap-entorno-des'
  Comprueba 'pre: su ruta de entrada' ($pre.Contains('- env.ruta-entrada = /data/pre/entrada') -and -not $pre.Contains('/data/pro/'))
  Comprueba 'pro: la suya' ($pro.Contains('- env.ruta-entrada = /data/pro/entrada') -and -not $pro.Contains('/data/pre/'))
  Comprueba 'pre no tiene cliente: pendiente; pro lo tiene' ($pre.Contains('- env.cliente = <PENDIENTE>') -and $pro.Contains('- env.cliente = acme-pro'))
  Comprueba 'des no tiene inventario: todo pendiente' ($des.Contains('- env.ruta-entrada = <PENDIENTE>') -and $des.Contains('- env.cliente = <PENDIENTE>') -and -not $des.Contains('/data/') -and -not $des.Contains('acme-pro'))
  Comprueba 'la secreta va sin valor, en los tres' ($pre.Contains('- env.url-token-clave (secreto, sin valor)') -and $pro.Contains('- env.url-token-clave (secreto, sin valor)') -and $des.Contains('- env.url-token-clave (secreto, sin valor)'))
  Comprueba 'el valor de pre esta en su variables y el de pro en el suyo' ((Lee-Destino $e 'config/pre/variables').Contains('pfx.variables.env.ruta-entrada=/data/pre/entrada') -and (Lee-Destino $e 'config/pro/variables').Contains('pfx.variables.env.ruta-entrada=/data/pro/entrada'))
  Comprueba 'des tambien tiene sus cuatro ficheros' (@('variables', 'secretos', 'montajes', 'recursos' | Where-Object { Existe-Destino $e "config/des/$_" }).Count -eq 4)
  Comprueba 'la consola no se queda en blanco: dice donde ha quedado' ((Corre $e).Consola.Contains($e.Destino))
}

$Pruebas['c9 (c2) entornos: PENDIENTE.md lleva una tabla por entorno con de donde sale cada variable y su estado'] = {
  $e = Nuevo-Escenario 'c2'
  Planes-Buenos $e
  [void](Corre $e)
  $p = Pendiente $e
  $pre = Seccion $p 'Entorno PRE'
  Comprueba 'hay seccion de PRE, de PRO y de DES' ((Seccion $p 'Entorno PRO') -and (Seccion $p 'Entorno DES') -and $pre)
  Comprueba 'una variable con valor, emparejada por la IA: valor puesto' ($pre -match '(?m)^\| env\.ruta-entrada \|[^|]*`ruta\.entrada`[^|]*IA[^|]*\| valor puesto \|') $pre
  Comprueba 'la secreta: hay que pedir el Secret' ($pre -match '(?m)^\| env\.url-token-clave \|[^|]*\| secreto: hay que pedir el Secret \|') $pre
  Comprueba 'la que el inventario de pre no tiene: pendiente' ($pre -match '(?m)^\| env\.cliente \|[^|]*\| pendiente \|') $pre
  Comprueba 'en DES, todo pendiente (menos la secreta)' ((Seccion $p 'Entorno DES') -match '(?m)^\| env\.ruta-entrada \|[^|]*\| pendiente \|')
  Comprueba 'las diferencias entre entornos dicen que PRE no tiene cliente y PRO si' ((Seccion $p 'Diferencias entre entornos').Contains('PRE no tiene `cliente`; PRO s' + $i_)) (Seccion $p 'Diferencias entre entornos')
  $j = Lee-Json (Join-Path $e.Datos 'configmap.json')
  Comprueba 'datos/configmap.json lleva lo mismo y el hash de cada fichero' ($null -ne $j -and @($j.ficheros).Count -gt 10 -and (@($j.ficheros)[0].hash -match '^[0-9a-f]{64}$')) 'sin configmap.json'
}

# ---- (d) secretos ----
$Pruebas['c9 (d1) secretos: ni el valor del inventario ni el del vault salen en ningun prompt, fichero ni consola; el inventario solo se lee de los *.properties'] = {
  $e = Nuevo-Escenario 'd1'
  Planes-Buenos $e
  $x = Corre $e
  foreach ($v in @($SecretoPre, $SecretoPro, 'SECRETO_VAULT', 'SECRETO_VAULT_PRO', 'SECRETO_GV', 'HOST_NO_LEER')) { Igual "el valor $v no sale en ningun sitio" 0 (Sale-Valor $e $v $x.Consola) }
  Comprueba 'el prompt de pre no tiene ni el secreto de pro, ni vault' (-not (Prompt-De $e 'configmap-entorno-pre').Contains('SECRETO'))
  Comprueba 'sigue habiendo valores no secretos de pre' ((Lee-Destino $e 'config/pre/variables').Contains('/data/pre/entrada'))
  Comprueba 'la variable de la clave es secreta por el nombre, y la linea de secretos la nombra sin valor' ((Lee-Destino $e 'config/pre/secretos').Contains('"variable":"env.url-token-clave"'))
}

$Pruebas['c9 (d2) secretos: la IA marca como secreta una variable que no lo parece: no sale su valor en el prompt y la tarea la pide como secreto'] = {
  $e = Nuevo-Escenario 'd2'
  Planes-Buenos $e
  Plan $e 'configmap-variables-1' $null (Respuesta-Variables $ParesBuenos @('env.reintentos'))
  foreach ($env in @('des', 'pre', 'pro')) { Plan $e "configmap-entorno-$env" (Ficheros-Entorno $env (Ficheros-Referencia) $Valores[$env] @('env.reintentos')) }
  $x = Corre $e
  $pre = Prompt-De $e 'configmap-entorno-pre'
  Comprueba 'el prompt dice que env.reintentos es secreta y no lleva su valor' ($pre.Contains('- env.reintentos (secreto, sin valor)') -and -not $pre.Contains('- env.reintentos = 5')) $pre
  Igual 'pre queda hecha: la secreta sale, sin valor, en secretos' 'hecha' (Tarea-Guardada $e 'configmap-entorno-pre').estado
  Comprueba 'la tabla de PRE dice que hay que pedir el Secret' ((Seccion (Pendiente $e) 'Entorno PRE') -match '(?m)^\| env\.reintentos \|[^|]*\| secreto: hay que pedir el Secret \|')
  Igual 'el valor 5 de la IA no sale como valor en variables' 0 @(Ficheros-De $e.Destino | Where-Object { $_.Name -eq 'variables' -and [System.IO.File]::ReadAllText($_.FullName) -match 'reintentos=' }).Count
}

$Pruebas['c9 (d3) secretos: si el falso escribe el valor del secreto en variables, la tarea es invalida y el fichero se borra; la segunda vez queda atascada y el valor tampoco queda'] = {
  $e = Nuevo-Escenario 'd3'
  Planes-Buenos $e
  $v = [ordered]@{}
  foreach ($k in $Valores['pre'].Keys) { $v[$k] = $Valores['pre'][$k] }
  $v['env.url-token-clave'] = $SecretoPre
  Plan $e 'configmap-entorno-pre' (Ficheros-Entorno 'pre' (Ficheros-Referencia) $v)
  $x = Corre $e
  $t = Tarea-Guardada $e 'configmap-entorno-pre'
  Igual 'queda atascada' 'atascada' $t.estado
  Igual 'con dos llamadas' 2 @(Llamadas-De $e | Where-Object { $_.Id -eq 'configmap-entorno-pre' }).Count
  Comprueba 'el fichero con el valor se ha borrado' (-not (Existe-Destino $e 'config/pre/variables'))
  Comprueba 'el motivo habla del fichero y no lleva el valor' ($t.motivo.Contains('config/pre/variables') -and -not $t.motivo.Contains($SecretoPre)) $t.motivo
  Igual 'el valor no sale en ningun sitio (ni en los registros ni en la consola)' 0 (Sale-Valor $e $SecretoPre $x.Consola)
  Comprueba 'PENDIENTE.md dice que esta atascada' ((Seccion (Pendiente $e) 'Tareas atascadas').Contains('configmap-entorno-pre'))
  Comprueba 'las demas tareas siguen: pro esta hecha' ((Tarea-Guardada $e 'configmap-entorno-pro').estado -eq 'hecha')
}

$Pruebas['c9 (d4) secretos: si lo escribe solo la primera vez, la segunda (con el motivo) vale y no queda el valor'] = {
  $e = Nuevo-Escenario 'd4'
  Planes-Buenos $e
  $v = [ordered]@{}
  foreach ($k in $Valores['pro'].Keys) { $v[$k] = $Valores['pro'][$k] }
  $v['env.url-token-clave'] = $SecretoPro
  Plan $e 'configmap-entorno-pro' (Ficheros-Entorno 'pro' (Ficheros-Referencia) $v)
  Plan $e 'configmap-entorno-pro' (Ficheros-Entorno 'pro' (Ficheros-Referencia)) $null $true
  $x = Corre $e
  Igual 'hecha' 'hecha' (Tarea-Guardada $e 'configmap-entorno-pro').estado
  Comprueba 'el segundo prompt lleva el motivo con el fichero' ((Prompt-De $e 'configmap-entorno-pro' 2).Contains('config/pro/variables'))
  Igual 'el valor no sale en ningun sitio' 0 (Sale-Valor $e $SecretoPro $x.Consola)
}

# ---- (e) cobertura ----
$Pruebas['c9 (e1) cobertura: una variable no secreta que el falso se deja en pre hace la tarea invalida y el motivo la nombra; una secreta que sale con valor tambien'] = {
  $e = Nuevo-Escenario 'e1'
  Planes-Buenos $e
  $v = [ordered]@{}
  foreach ($k in $Valores['pre'].Keys) { if ($k -ne 'env.lote-pedidos-endpoint') { $v[$k] = $Valores['pre'][$k] } }
  Plan $e 'configmap-entorno-pre' (Ficheros-Entorno 'pre' (Ficheros-Referencia) $v)
  $f = Ficheros-Entorno 'pro' (Ficheros-Referencia)
  $f['config/pro/variables'] += "pfx.variables.env.url-token-clave=algo-que-no-es-un-valor-del-inventario`n"
  Plan $e 'configmap-entorno-pro' $f
  [void](Corre $e)
  $t = Tarea-Guardada $e 'configmap-entorno-pre'
  Igual 'pre queda atascada' 'atascada' $t.estado
  Comprueba 'y el motivo nombra la variable que falta' ($t.motivo.Contains('env.lote-pedidos-endpoint')) $t.motivo
  $u = Tarea-Guardada $e 'configmap-entorno-pro'
  Igual 'pro (una secreta con valor) queda atascada' 'atascada' $u.estado
  Comprueba 'y el motivo nombra la secreta' ($u.motivo.Contains('env.url-token-clave')) $u.motivo
}

$Pruebas['c9 (e2) cobertura: una variable con el valor de otro entorno, o un fichero que falta, hacen la tarea invalida'] = {
  $e = Nuevo-Escenario 'e2'
  Planes-Buenos $e
  $malo = Ficheros-Entorno 'pro' (Ficheros-Referencia) $Valores['pre']
  Plan $e 'configmap-entorno-pro' $malo
  Plan $e 'configmap-entorno-pro' (Ficheros-Entorno 'pro' (Ficheros-Referencia)) $null $true
  $sin = Ficheros-Entorno 'des' (Ficheros-Referencia)
  $sin.Remove('config/des/montajes')
  Plan $e 'configmap-entorno-des' $sin
  [void](Corre $e)
  Igual 'pro hecha a la segunda' '0,1' ((@(Llamadas-De $e | Where-Object { $_.Id -eq 'configmap-entorno-pro' }) | ForEach-Object { $_.Reintento }) -join ',')
  Comprueba 'el motivo de pro nombra la variable con el valor de otro entorno' ((Prompt-De $e 'configmap-entorno-pro' 2).Contains('env.ruta-entrada'))
  Comprueba 'des: el motivo nombra el fichero que falta' ((Tarea-Guardada $e 'configmap-entorno-des').motivo.Contains('montajes') -or (Prompt-De $e 'configmap-entorno-des' 2).Contains('montajes'))
}

# ---- (f) plataforma ----
$Pruebas['c9 (f1) plataforma: R* que queda en un fichero, un yml sin una clave de primer nivel o con un elemento sin una clave hacen la tarea invalida; un .env no se mira como yml'] = {
  $e = Nuevo-Escenario 'f1'
  Planes-Buenos $e
  $ref = Ficheros-Referencia
  Plan $e $IdProps @{ '.plataforma/ci/props.env' = $ref['.plataforma/ci/props.env'] }
  Plan $e $IdValues @{ '.plataforma/cd/values.yaml' = "configMapType: file`n" }
  Plan $e $IdCdPro @{ '.plataforma/cd/pro/cd.yml' = "- id_ci: <PENDIENTE: id_ci>`n  ficheros_config:`n    - config/pro/variables`n- id_ci: <PENDIENTE: id_ci>`n" }
  Plan $e $IdCdPre @{ '.plataforma/cd/pre/cd.yml' = "- id_ci: <PENDIENTE: id_ci>`n  ficheros_config:`n    - config/pre/variables`n- id_ci: <PENDIENTE: id_ci>`n  ficheros_config:`n    - config/pre/variables`n    - config/pre/secretos`n" }
  Plan $e $IdFlujo @{ '.github/workflows/cd.yml' = "no es un yml: y da igual`n" }
  foreach ($par in @(@($IdProps, '.plataforma/ci/props.env'), @($IdValues, '.plataforma/cd/values.yaml'), @($IdCdPro, '.plataforma/cd/pro/cd.yml'))) {
    Plan $e $par[0] @{ $par[1] = (Adapta-Plataforma $par[1] $ref[$par[1]]) } $null $true
  }
  [void](Corre $e)
  $n = @{}
  foreach ($l in @(Llamadas-De $e)) { $n[$l.Id] = 1 + [int]$n[$l.Id] }
  Igual 'props.env con precios: dos llamadas' 2 $n[$IdProps]
  Comprueba 'su motivo dice que queda precios' ((Prompt-De $e $IdProps 2) -match 'precios')
  Igual 'values.yaml sin applicationName: dos llamadas' 2 $n[$IdValues]
  Comprueba 'su motivo nombra la clave' ((Prompt-De $e $IdValues 2).Contains('applicationName'))
  Igual 'pro/cd.yml con un elemento sin ficheros_config: dos llamadas' 2 $n[$IdCdPro]
  Comprueba 'su motivo nombra la clave del elemento' ((Prompt-De $e $IdCdPro 2).Contains('ficheros_config'))
  Igual 'pre/cd.yml con dos elementos (el de referencia lleva uno): vale a la primera' 1 $n[$IdCdPre]
  Igual 'el workflow que no es yml valido pero lo mira como yml: dos llamadas' 2 $n[$IdFlujo]
}

$Pruebas['c9 (f2) plataforma: un .env no pasa la comprobacion de yml aunque no tenga las claves de la referencia; un fichero vacio es invalido'] = {
  $e = Nuevo-Escenario 'f2'
  Planes-Buenos $e
  Plan $e $IdProps @{ '.plataforma/ci/props.env' = "OTRA=`"cosa`"`n" }
  Plan $e $IdValues @{ '.plataforma/cd/values.yaml' = '' }
  [void](Corre $e)
  Igual 'props.env: una sola llamada, aunque no tenga las claves de la referencia' 1 @(Llamadas-De $e | Where-Object { $_.Id -eq $IdProps }).Count
  Igual 'values.yaml vacio: dos llamadas y atascada' 'atascada' (Tarea-Guardada $e $IdValues).estado
  Igual 'sus dos llamadas' 2 @(Llamadas-De $e | Where-Object { $_.Id -eq $IdValues }).Count
  Comprueba 'los config/<entorno>/ (que tampoco son yml) pasan a la primera: una llamada por entorno' (@(Llamadas-De $e | Where-Object { $_.Id -like 'configmap-entorno-*' }).Count -eq 3)
}

$Pruebas['c9 (f3) plataforma: los <PENDIENTE: ...> llegan a PENDIENTE.md con fichero:linea; el prompt lleva la referencia con precios ya cambiado'] = {
  $e = Nuevo-Escenario 'f3'
  Planes-Buenos $e
  [void](Corre $e)
  $s = Seccion (Pendiente $e) 'Pendientes en los ficheros'
  Comprueba 'el id_ci de pre, con su fichero y su linea' ($s -match '\.plataforma/cd/pre/cd\.yml:1\b[^\n]*<PENDIENTE: id_ci>') $s
  Comprueba 'los dos de pro, en sus lineas' ($s -match '\.plataforma/cd/pro/cd\.yml:1\b' -and $s -match '\.plataforma/cd/pro/cd\.yml:5\b') $s
  Comprueba 'un valor pendiente de variables, tambien' ($s -match 'config/des/variables:1\b[^\n]*<PENDIENTE>') $s
  $p = Prompt-De $e $IdProps
  Comprueba 'el prompt lleva el texto de referencia ya con pedidos' ($p.Contains('ANALISIS_CLAVE="acme-lote-pedidos"') -and -not ($p -match 'precios'))
  Comprueba 'y el pom del migrado (lo lee de su carpeta)' ($p.Contains($e.Migrado))
  Comprueba 'ningun fichero del repo nuevo lleva precios, con ninguna forma' (@(Ficheros-De $e.Destino | Where-Object { [System.IO.File]::ReadAllText($_.FullName) -match '(?i)precios' }).Count -eq 0)
  Comprueba 'los ficheros sueltos se copian sin IA y con el cambio de nombre' ((Lee-Destino $e 'README.md').Contains('PEDIDOS') -and (Lee-Destino $e 'README.md').Contains('acme-cm-lote-pedidos') -and (Lee-Destino $e 'docs/notas.txt').Contains('Pedidos'))
  Comprueba 'y no hay llamada para ellos' (-not ((Ids-De $e) -match 'readme|notas'))
}

# ---- (g) revision ----
$Pruebas['c9 (g1) revision: un hallazgo con una cita que no sale se descarta y uno bueno llega a PENDIENTE.md'] = {
  $e = Nuevo-Escenario 'g1'
  Planes-Buenos $e
  $malo = [ordered]@{ fichero = 'config/pre/variables'; linea = 1; cita = 'una cita que no esta en ningun sitio'; problema = 'Problema inventado.' }
  $bueno = [ordered]@{ fichero = 'config/pre/variables'; linea = 2; cita = 'env.lote-pedidos-endpoint'; problema = 'El endpoint de pre apunta a otro entorno.' }
  Plan $e 'configmap-revision-pre' $null (ConvertTo-Json -InputObject @{ hallazgos = @($malo, $bueno) } -Depth 4)
  [void](Corre $e)
  Igual 'la revision de pre queda hecha' 'hecha' (Tarea-Guardada $e 'configmap-revision-pre').estado
  $p = Pendiente $e
  Comprueba 'el bueno sale con su fichero y su linea' ($p.Contains('config/pre/variables:2') -and $p.Contains('El endpoint de pre apunta a otro entorno.'))
  Comprueba 'el malo no sale' (-not $p.Contains('Problema inventado.'))
  Comprueba 'la revision va despues de las demas: es lo ultimo que se llama' ((@(Llamadas-De $e | ForEach-Object { $_.Id }) | Select-Object -Last 4 | Where-Object { $_ -like 'configmap-revision-*' }).Count -eq 4)
  Comprueba 'y la primera es la de variables' ((@(Llamadas-De $e)[0]).Id -eq 'configmap-variables-1')
  Comprueba 'el prompt de la revision lleva la tabla y la referencia' ((Prompt-De $e 'configmap-revision-pre').Contains('- env.cliente = <PENDIENTE>') -and (Prompt-De $e 'configmap-revision-pre').Contains('pfx.variables.limits.cpu'))
}

$Pruebas['c9 (g2) revision: una lectura que cambia un fichero lo deja deshecho y la tarea queda invalida (atascada tras el segundo intento)'] = {
  $e = Nuevo-Escenario 'g2'
  Planes-Buenos $e
  $antes = (Ficheros-Entorno 'pre' (Ficheros-Referencia))['config/pre/recursos']
  Plan $e 'configmap-revision-pre' @{ 'config/pre/recursos' = 'tocado por la revision'; 'config/pre/nuevo' = 'otro' } '{"hallazgos": []}'
  [void](Corre $e)
  Igual 'el fichero esta como estaba' $antes (Lee-Destino $e 'config/pre/recursos')
  Comprueba 'y el que creo ya no esta' (-not (Existe-Destino $e 'config/pre/nuevo'))
  Igual 'la tarea queda atascada' 'atascada' (Tarea-Guardada $e 'configmap-revision-pre').estado
  Comprueba 'con un motivo que dice que toco ficheros' ((Tarea-Guardada $e 'configmap-revision-pre').motivo -match 'toc')
  Comprueba 'PENDIENTE.md la lista' ((Seccion (Pendiente $e) 'Tareas atascadas').Contains('configmap-revision-pre'))
}

# ---- (h) relanzar ----
$Pruebas['c9 (h1) relanzar: sin cambios en las entradas no hay ni una llamada; un fichero cambiado a mano se conserva y se dice; un cambio en el inventario solo rehace lo suyo'] = {
  $e = Nuevo-Escenario 'h1'
  Planes-Buenos $e
  [void](Corre $e)
  $n = @(Llamadas-De $e).Count
  Comprueba 'la primera pasada llama' ($n -ge 13) "$n"
  $x = Corre $e
  Igual 'segunda pasada: ninguna llamada nueva' $n @(Llamadas-De $e).Count
  Igual 'sale con 0' 0 $x.R.Codigo
  Escribe $e.Destino 'config/pre/variables' "pfx.variables.env.a-mano=1`n"
  $x = Corre $e
  Igual 'con un fichero cambiado a mano: ninguna llamada' $n @(Llamadas-De $e).Count
  Igual 'el fichero sigue como lo dejo el usuario' "pfx.variables.env.a-mano=1`n" (Lee-Destino $e 'config/pre/variables')
  Comprueba 'la consola lo dice' ($x.Consola -match 'config/pre/variables' -and $x.Consola -match 'cambiado')
  Comprueba 'y PENDIENTE.md' ((Seccion (Pendiente $e) 'Ficheros que has cambiado').Contains('config/pre/variables'))
  Escribe $e.Inv 'PRO/app.properties' "ruta.entrada=/data/pro/nueva`nlote.pedidos.endpoint=https://pedidos.acme.test/api`ncliente=acme-pro`nurl.token=https://auth.acme.test/token`nurl.token.clave=$SecretoPro`nmax.reintentos=3`n"
  $v = [ordered]@{}
  foreach ($k in $Valores['pro'].Keys) { $v[$k] = $Valores['pro'][$k] }
  $v['env.ruta-entrada'] = '/data/pro/nueva'
  Plan $e 'configmap-entorno-pro' (Ficheros-Entorno 'pro' (Ficheros-Referencia) $v)
  $m = @(Llamadas-De $e).Count
  [void](Corre $e)
  Igual 'cambia el inventario de pro: solo se rehacen su entorno y su revision' 'configmap-entorno-pro,configmap-revision-pro' (Ids-Nuevos $e $m)
  Comprueba 'y el valor nuevo esta en su fichero' ((Lee-Destino $e 'config/pro/variables').Contains('/data/pro/nueva'))
  Igual 'lo que cambio el usuario sigue igual' "pfx.variables.env.a-mano=1`n" (Lee-Destino $e 'config/pre/variables')
  Remove-Item -LiteralPath (Get-Ruta $e.Destino '.plataforma/ci/props.env') -Force
  $m = @(Llamadas-De $e).Count
  [void](Corre $e)
  Igual 'un fichero que falta se escribe otra vez: su tarea y la revision de la plataforma' "configmap-plataforma-plataforma-ci-props-env,configmap-revision-plataforma" (Ids-Nuevos $e $m)
  Comprueba 'y esta' (Existe-Destino $e '.plataforma/ci/props.env')
}

$Pruebas['c9 (h2) relanzar: un fichero suelto que cambia el usuario se conserva y se dice; PENDIENTE.md se escribe siempre'] = {
  $e = Nuevo-Escenario 'h2'
  Planes-Buenos $e
  [void](Corre $e)
  Escribe $e.Destino 'README.md' "lo he escrito yo`n"
  Escribe $e.Destino 'PENDIENTE.md' "mis notas`n"
  Escribe $e.Ref 'docs/notas.txt' "Notas nuevas de Precios.`n"
  Escribe $e.Ref 'docs/otras.txt' "Otras de Precios.`n"
  $x = Corre $e
  Igual 'el README del usuario se conserva' "lo he escrito yo`n" (Lee-Destino $e 'README.md')
  Comprueba 'y se dice' ($x.Consola -match 'README\.md' -and (Seccion (Pendiente $e) 'Ficheros que has cambiado').Contains('README.md'))
  Igual 'el suelto que no ha tocado se escribe otra vez' "Notas nuevas de Pedidos.`n" (Lee-Destino $e 'docs/notas.txt')
  Igual 'y el nuevo tambien' "Otras de Pedidos.`n" (Lee-Destino $e 'docs/otras.txt')
  Comprueba 'PENDIENTE.md se escribe otra vez' ((Pendiente $e).StartsWith('# '))
}

$Pruebas['c9 (h3) relanzar: una carpeta que ya existe y no es del script para sin tocar nada'] = {
  $e = Nuevo-Escenario 'h3'
  Planes-Buenos $e
  Escribe $e.Destino 'mio.txt' "mio`n"
  $x = Corre $e
  Igual 'sale con 1' 1 $x.R.Codigo
  Comprueba ('dice "Ya existe <ruta>: mu' + [char]0xE9 + 'vela o b' + [char]0xF3 + 'rrala"') ($x.Consola.Contains('Ya existe ' + $e.Destino + ': mu' + [char]0xE9 + 'vela o b' + [char]0xF3 + 'rrala')) $x.Consola
  Igual 'no hay mas que su fichero' 'mio.txt' ((@(Get-ChildItem -LiteralPath $e.Destino -Force) | ForEach-Object { $_.Name }) -join ',')
  Igual 'ninguna llamada' 0 @(Llamadas-De $e).Count
  Comprueba 'ni datos/configmap.json' (-not (Test-Path -LiteralPath (Join-Path $e.Datos 'configmap.json')))
}

$Pruebas['c9 (h4) sin inventario valido o sin referencia: para con un mensaje y no crea nada'] = {
  $e = Nuevo-Escenario 'h4'
  $x = Corre ([pscustomobject]@{ Plantilla = $e.Plantilla; Migrado = $e.Migrado; Ref = $e.Ref; Inv = (Join-Path $e.Raiz 'no-existe'); Destino = $e.Destino; Datos = $e.Datos; Registros = $e.Registros })
  Igual 'inventario que no existe: sale con 1' 1 $x.R.Codigo
  Comprueba 'y no crea el repo' (-not (Test-Path -LiteralPath $e.Destino))
  $y = Corre ([pscustomobject]@{ Plantilla = $e.Plantilla; Migrado = $e.Migrado; Ref = $e.Inv; Inv = $e.Inv; Destino = $e.Destino; Datos = $e.Datos; Registros = $e.Registros })
  Igual 'una referencia sin config/: sale con 1' 1 $y.R.Codigo
  Comprueba 'y lo dice' ($y.Consola -match 'config') $y.Consola
}

# ---- (i) migracion.ps1 ----
# Un escenario de migracion.ps1: los repos con git, el original con una clase, y los ajustes de la carpeta de la prueba (Copilot, Maven y Java de mentira).
function Migra-Escenario([string]$Nombre) {
  $e = Nuevo-Escenario $Nombre @{ Git = $true }
  Escribe $e.Original 'pom.xml' "<project><artifactId>original</artifactId></project>`n"
  Escribe $e.Original 'src/main/java/com/acme/old/Clase1.java' "package com.acme.old;`n`npublic class Clase1 {`n}`n"
  Inicia-Repo $e.Original
  $aj = [ordered]@{ CopilotExe = (Join-Path $falsos 'c9-copilot.ps1'); MvnExe = (Join-Path $falsos 'mvn.ps1'); JavaExe = (Join-Path $falsos 'java.ps1'); SegundosPorLlamada = 60 }
  Escribe $e.Home 'ajustes.json' (ConvertTo-Json -InputObject $aj)
  Planes-Buenos $e
  return $e
}

# El estado.json de una pasada ya cerrada (a mano: lo minimo que lee migracion.ps1), con el commit del migrado como el del cierre.
function Estado-Cerrado($E) {
  $salida = Join-Path $E.Migrado 'migracion-acme-lote-pedidos'
  $head = (GitEn $E.Migrado @('rev-parse', 'HEAD'))
  [void](GitEn $E.Migrado @('worktree', 'add', '-q', '-b', 'rescate/main-20261121-0000', ($E.Migrado + '-rescate')))
  $s = [ordered]@{
    version = 1; batch = 'acme-lote-pedidos'; legacy = $E.Original; migrado = $E.Migrado; plantilla = $E.Plantilla; worktree = ($E.Migrado + '-rescate')
    rama = 'rescate/main-20261121-0000'; ramaOrigen = 'main'; javaLegacy = ''; lanzadores = ''; modelo = 'modelo-x'; aptitud = 'modelo-x'; respuesta = 'corregir'
    fase = 'hecha'; creado = '2026-11-21T10:00:00'; actualizado = '2026-11-21T10:00:00'; fin = '2026-11-21T10:30:00'; parada = $null; pruebaLocal = $null
    cierre = [ordered]@{ antes = $head; sha = $head; cuando = '2026-11-21T10:30:00'; juntada = $false; hecho = $true; deshacer = 'git reset'; avisos = @(); revisar = @() }
  }
  Escribe $salida 'datos/estado.json' (ConvertTo-Json -InputObject $s -Depth 6)
  return (Join-Path (Join-Path $salida 'datos') 'estado.json')
}

function Migra-C9($E, [string[]]$A, [string[]]$Entrada = @('')) {
  $env:RESCATE_HOME = $E.Home
  try { return (Lanzar (Join-Path $raiz 'migracion.ps1') (@('-Legacy', $E.Original, '-Migrado', $E.Migrado, '-Plantilla', $E.Plantilla, '-Modelo', 'modelo-x') + $A) '' $Entrada) }
  finally { $env:RESCATE_HOME = '' }
}

$Pruebas['c9 (i1) migracion.ps1 -ConfigMap: solo hace esta fase; pregunta la referencia la primera vez y la guarda en ajustes.json; el inventario va a estado.json'] = {
  $e = Migra-Escenario 'i1'
  $est = Estado-Cerrado $e
  $r = Migra-C9 $e @('-ConfigMap', '-Inventario', $e.Inv) @($e.Ref)
  Igual 'sale con 0' 0 $r.Codigo
  Comprueba 'deja el repo nuevo con su PENDIENTE.md' (Test-Path -LiteralPath (Get-Ruta $e.Destino 'PENDIENTE.md')) $r.Salida
  Comprueba 'la consola dice donde ha quedado y cuantos pendientes hay' ($r.Salida.Contains($e.Destino) -and $r.Salida -match 'pendientes') $r.Salida
  $aj = Lee-Json (Join-Path $e.Home 'ajustes.json')
  Igual 'ConfigMapReferencia queda en ajustes.json' $e.Ref "$($aj.ConfigMapReferencia)"
  $s = Lee-Json $est
  Igual 'Inventario queda en estado.json' $e.Inv "$($s.inventario)"
  Igual 'la fase de la pasada sigue siendo hecha' 'hecha' "$($s.fase)"
  Comprueba 'no ha hecho nada mas: ni lecturas de clases ni tareas de otras fases' (@(Get-ChildItem -LiteralPath (Join-Path (Split-Path $est -Parent) 'tareas') -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike 'configmap-*' }).Count -eq 0)
  Comprueba 'las llamadas son solo de configmap' (@(Llamadas-De $e | Where-Object { $_.Id -notlike 'configmap-*' }).Count -eq 0)
  $n = @(Llamadas-De $e).Count
  $r2 = Migra-C9 $e @('-ConfigMap')
  Igual 'sin -Inventario ni referencia: usa lo guardado, sale con 0' 0 $r2.Codigo
  Igual 'y sin cambios, ninguna llamada' $n @(Llamadas-De $e).Count
}

$Pruebas['c9 (i2) migracion.ps1 -ConfigMap: sin inventario (ni guardado) para con un mensaje; con -Cierre o con otro modo no se mezcla'] = {
  $e = Migra-Escenario 'i2'
  [void](Estado-Cerrado $e)
  $r = Migra-C9 $e @('-ConfigMap', '-ConfigMapReferencia', $e.Ref)
  Igual 'sin inventario: sale con 1' 1 $r.Codigo
  Comprueba 'y dice que falta -Inventario' ($r.Salida -match '-Inventario') $r.Salida
  Comprueba 'no crea el repo' (-not (Test-Path -LiteralPath $e.Destino))
  foreach ($f in @('-Cierre', '-SoloInforme', '-Si', '-Practicas', '-Reglas', '-RevisarTodo')) {
    $m = Migra-C9 $e @('-ConfigMap', '-Inventario', $e.Inv, '-ConfigMapReferencia', $e.Ref, $f)
    Comprueba "-ConfigMap con $f : sale con 1 y dice que solo hace esta fase" ($m.Codigo -eq 1 -and $m.Salida -match 'solo hace esta fase') "$($m.Codigo): $(Cola $m.Salida)"
  }
}

$Pruebas['c9 (i3) migracion.ps1 -Cierre: con las dos rutas hace el repo de configmap al final; sin -Inventario dice la linea y no lo hace'] = {
  $e = Migra-Escenario 'i3'
  [void](Estado-Cerrado $e)
  Escribe $e.Home 'ajustes.json' (ConvertTo-Json -InputObject ([ordered]@{ CopilotExe = (Join-Path $falsos 'c9-copilot.ps1'); MvnExe = (Join-Path $falsos 'mvn.ps1'); JavaExe = (Join-Path $falsos 'java.ps1'); SegundosPorLlamada = 60; ConfigMapReferencia = $e.Ref }))
  $r = Migra-C9 $e @('-Cierre')
  Igual 'sin -Inventario: sale con 0' 0 $r.Codigo
  Comprueba 'dice como pedir el repo de configmap' ($r.Salida.Contains('Para el repo de configmap: relanza con -ConfigMap -Inventario <carpeta del inventario del original>')) $r.Salida
  Comprueba 'y no lo crea' (-not (Test-Path -LiteralPath $e.Destino))
  $r2 = Migra-C9 $e @('-Cierre', '-Inventario', $e.Inv)
  Igual 'con las dos rutas: sale con 0' 0 $r2.Codigo
  Comprueba 'el repo esta hecho' (Test-Path -LiteralPath (Get-Ruta $e.Destino 'PENDIENTE.md')) $r2.Salida
  Comprueba 'y no repite la linea de ayuda' (-not $r2.Salida.Contains('Para el repo de configmap'))
  $r3 = Migra-C9 $e @('-Cierre')
  Comprueba 'con el inventario ya guardado (sin -Inventario): lo vuelve a hacer, sin llamadas nuevas' ($r3.Codigo -eq 0 -and -not $r3.Salida.Contains('Para el repo de configmap'))
}

Invoke-Banco $Pruebas 'tests/probar-configmap.ps1'
