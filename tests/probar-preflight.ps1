<#
probar-preflight.ps1 - Banco de pruebas de preflight.ps1.
No necesita Maven, Java ni Copilot reales: usa los programas de mentira de tests/falsos y
repos de juguete que crea en una carpeta temporal. Solo hace falta git. No llama nunca al
Copilot real: el preflight recibe el falso por ajustes.json (CopilotExe).
Vale para Windows PowerShell 5.1 y para PowerShell 7. Solo ASCII a proposito.

  .\tests\probar-preflight.ps1                        # todas las pruebas
  .\tests\probar-preflight.ps1 -Solo privacidad       # las que llevan 'privacidad' en el nombre
  .\tests\probar-preflight.ps1 -Dir D:\tmp\x -Conservar
  .\tests\probar-preflight.ps1 -Script C:\otra\preflight.ps1

La prueba 1 lanza de verdad los otros dos bancos (unos 2 minutos); las demas usan -Solo.
Cada lanzamiento corre sobre una copia de los scripts en la carpeta temporal, para que
preflight-resultado.txt no se mezcle con el del repo.
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
$raiz = Split-Path -Parent $aqui
if (-not $Script) { $Script = Join-Path $raiz 'preflight.ps1' }
$origen = Split-Path -Parent $Script
$falsos = Join-Path $aqui 'falsos'
. (Join-Path $aqui 'comun-banco.ps1')
$Inst = Join-Path $Dir 'instalacion'

# ============================== UTILIDADES ==============================
# Una copia de los scripts (sin .git) donde se lanza el preflight.
function Nueva-Instalacion {
  if (Test-Path -LiteralPath $Inst) { return }
  [void](New-Item -ItemType Directory -Path $Inst -Force)
  foreach ($f in @('preflight.ps1', 'comun.ps1', 'tareas.ps1', 'rescate.ps1', 'migracion.ps1')) {
    $de = Join-Path $origen $f
    if ($f -eq 'preflight.ps1') { $de = $Script }
    if (Test-Path -LiteralPath $de) { Copy-Item -LiteralPath $de -Destination (Join-Path $Inst $f) }
  }
  foreach ($d in @('tareas', 'preflight', 'tests')) {
    $de = Join-Path $origen $d
    if (Test-Path -LiteralPath $de) { Copy-Item -LiteralPath $de -Destination (Join-Path $Inst $d) -Recurse }
  }
}

# Identidad reconocible: todo lo que lleva 'zorba' es de la empresa y no puede salir.
$Identidad = [ordered]@{ USERNAME = 'zorbalex'; COMPUTERNAME = 'PCZORBA'; USERDOMAIN = 'DOMZORBA'; USERDNSDOMAIN = 'zorba.local'; DISPLAY = ''; WAYLAND_DISPLAY = '' }

# Lanza el preflight con los ajustes y la carpeta de llamadas del escenario. Devuelve el codigo,
# lo que escribe por consola y el fichero de resultado.
function Pf($E, [string[]]$A, [string]$Guion = '', $Extra = @{}) {
  Nueva-Instalacion
  $vars = [ordered]@{}
  foreach ($k in $Identidad.Keys) { $vars[$k] = $Identidad[$k] }
  $vars['RESCATE_HOME'] = $E.Home
  $vars['RESCATE_LLAMADAS'] = $E.Llamadas
  foreach ($k in $Extra.Keys) { $vars[$k] = $Extra[$k] }
  $ant = @{}
  foreach ($k in $vars.Keys) { $ant[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $vars[$k]) }
  $f = Join-Path $Inst 'preflight-resultado.txt'
  if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force }
  if (Test-Path -LiteralPath $E.Llamadas) { Remove-Item -LiteralPath $E.Llamadas -Recurse -Force }
  try { $r = Lanzar (Join-Path $Inst 'preflight.ps1') $A $Guion }
  finally { foreach ($k in $vars.Keys) { [Environment]::SetEnvironmentVariable($k, $ant[$k]) } }
  $txt = ''
  if (Test-Path -LiteralPath $f) { $txt = [System.IO.File]::ReadAllText($f) }
  return [pscustomobject]@{ Codigo = $r.Codigo; Salida = $r.Salida; Fichero = $txt; Ruta = $f }
}

# Las lineas del fichero de resultado.
function Lineas-De($R) { return @($R.Fichero -split "\r?\n" | Where-Object { $_ -ne '' }) }

# Las lineas de un bloque (entre su cabecera y la siguiente).
function Bloque-De($R, [string]$Prefijo) {
  $dentro = $false
  $res = @()
  foreach ($l in (Lineas-De $R)) {
    if ($l -match '^== ') { $dentro = $l.StartsWith('== ' + $Prefijo); continue }
    if ($dentro) { $res += $l }
  }
  return $res
}

# Una linea 'clave: valor' del fichero ('' si no esta).
function Valor-De($R, [string]$Clave) {
  foreach ($l in (Lineas-De $R)) { if ($l.StartsWith($Clave + ': ')) { return $l.Substring($Clave.Length + 2) } }
  return ''
}

function Cuenta-Lineas($R, [string]$Patron) { return @((Lineas-De $R) | Where-Object { $_ -match $Patron }).Count }

# Lo que dejo cada llamada del Copilot falso (RESCATE_LLAMADAS), por hora de inicio. Solo las del
# preflight (ids pf-*): los bancos que lanza el bloque 2 usan los mismos falsos y dejan las suyas.
function Llamadas([string]$Carpeta) {
  if (-not (Test-Path -LiteralPath $Carpeta)) { return @() }
  $todas = @(Get-ChildItem -LiteralPath $Carpeta -File -Filter 'pf-*' | ForEach-Object {
      $o = [ordered]@{}
      foreach ($l in [System.IO.File]::ReadAllLines($_.FullName)) { $k, $v = ($l -split '=', 2); $o[$k] = $v }
      [pscustomobject]$o
    })
  return @($todas | Sort-Object { [long]$_.inicio })
}

function Llamadas-De($Llamadas, [string]$Prefijo) { return @($Llamadas | Where-Object { $_.id -like ($Prefijo + '*') }) }

function Max-Simultaneas($Llamadas) {
  $ev = @()
  foreach ($l in $Llamadas) {
    if ($l.inicio -and $l.fin) {
      $ev += [pscustomobject]@{ T = [long]$l.inicio; D = 1 }
      $ev += [pscustomobject]@{ T = [long]$l.fin; D = -1 }
    }
  }
  $max = 0; $cur = 0
  foreach ($x in @($ev | Sort-Object T, D)) { $cur += $x.D; if ($cur -gt $max) { $max = $cur } }
  return $max
}

# Nada de la empresa en el fichero ni en la consola: todo lo reconocible lleva 'zorba'.
function Sin-Fugas($R, [string]$Que) {
  $todo = $R.Fichero + "`n" + $R.Salida
  Comprueba "$Que`: no sale nada con 'zorba' (repos, clases, usuario, equipo, dominio, correo, url, textos del modelo)" ($todo -notmatch '(?i)zorba') (($todo -split "`n" | Where-Object { $_ -match '(?i)zorba' } | Select-Object -First 3) -join ' / ')
  Comprueba "$Que`: no sale la carpeta del usuario" (-not $todo.Contains([Environment]::GetFolderPath('UserProfile')))
  Comprueba "$Que`: no sale la carpeta de pruebas" (-not $todo.Contains($Dir))
}

function Es-Ascii([string]$Texto) { return ($Texto -notmatch '[^\x09\x0A\x0D\x20-\x7E]') }

# ============================ REPOS DE JUGUETE ============================
function Pom([string]$Id) {
  return @"
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.zorba</groupId>
  <artifactId>$Id</artifactId>
  <version>1.0.0</version>
</project>
"@
}

# Una clase de $Lineas lineas; las que acaban en ; (sin package) empiezan en la 5.
function Clase-Zorba([string]$Nombre, [int]$Lineas, [string]$Paquete = 'com.zorba.legado', [string]$Extra = '') {
  $t = @("package $Paquete;", '', "/** Clase $Nombre. */", "public class $Nombre {")
  for ($i = 1; $i -le ($Lineas - 5); $i++) { $t += "    private int campo$i = $i;" }
  if ($Extra) { $t[4] = '    ' + $Extra }
  $t += '}'
  return (($t -join "`n") + "`n")
}

# Una clase con esos imports y esas lineas dentro.
function Clase-Con([string]$Nombre, [string]$Paquete, [string[]]$Imports, [string[]]$Cuerpo) {
  $t = @("package $Paquete;", '') + @($Imports | ForEach-Object { "import $_;" }) + @('', "public class $Nombre {") + @($Cuerpo | ForEach-Object { "    $_" }) + @('}')
  return (($t -join "`n") + "`n")
}

# Un pom con padre (artifactId y version) y propiedades (elementos ya escritos) si se piden.
function Pom-Con([string]$ArtifactPadre = '', [string]$VersionPadre = '', [string]$Props = '') {
  $t = '<project xmlns="http://maven.apache.org/POM/4.0.0">' + "`n" + '  <modelVersion>4.0.0</modelVersion>' + "`n"
  if ($ArtifactPadre) { $t += '  <parent><groupId>g</groupId><artifactId>' + $ArtifactPadre + '</artifactId><version>' + $VersionPadre + '</version></parent>' + "`n" }
  if ($Props) { $t += '  <properties>' + $Props + '</properties>' + "`n" }
  return ($t + '</project>' + "`n")
}

# El original tiene 9 ficheros .java (697 lineas, 2 modulos, 2 pom.xml, 3 jobs en 2 xml, 2 clases de
# batch, 1 fichero que no es UTF-8) y el migrado y la referencia uno o dos cada uno.
function Nuevo-Escenario([string]$Nombre, [hashtable]$Ajustes = @{}) {
  $raizE = Join-Path $Dir $Nombre
  if (Test-Path -LiteralPath $raizE) { Remove-Item -LiteralPath $raizE -Recurse -Force }
  $leg = Join-Path $raizE 'zorba-legado-xq'
  $mig = Join-Path $raizE 'zorba-migrado-xq'
  $pl = Join-Path $raizE 'zorba-plantilla-xq'
  $casa = Join-Path $raizE 'ajustes'
  Escribe $leg 'pom.xml' (Pom 'zorba-legado')
  $base = 'src/main/java/com/zorba/legado/'
  Escribe $leg ($base + 'ZorbaMini.java') (Clase-Zorba 'ZorbaMini' 15)
  Escribe $leg ($base + 'ZorbaCorta.java') (Clase-Zorba 'ZorbaCorta' 25)
  Escribe $leg ($base + 'ZorbaMedia.java') (Clase-Zorba 'ZorbaMedia' 30 'com.zorba.legado' '@EnableBatchProcessing')
  Escribe $leg ($base + 'ZorbaAncha.java') (Clase-Zorba 'ZorbaAncha' 55 'com.zorba.legado' 'private JobBuilderFactory jobs;')
  Escribe $leg ($base + 'ZorbaLarga.java') (Clase-Zorba 'ZorbaLarga' 80)
  Escribe $leg ($base + 'ZorbaGrande.java') (Clase-Zorba 'ZorbaGrande' 120)
  Escribe $leg ($base + 'ZorbaEnorme.java') (Clase-Zorba 'ZorbaEnorme' 350)
  $latin = ((@('package com.zorba.legado;', '', ('// caf' + [char]0xE9), 'public class ZorbaLatin1 {', '    private int a = 1;', '    private int b = 2;', '    private int c = 3;', '    private int d = 4;', '    private int e = 5;', '}') -join "`n") + "`n")
  [void](New-Item -ItemType Directory -Path (Join-Path $leg 'src/main/java/com/zorba/legado') -Force)
  [System.IO.File]::WriteAllBytes((Get-Ruta $leg ($base + 'ZorbaLatin1.java')), [System.Text.Encoding]::GetEncoding(28591).GetBytes($latin))
  Escribe $leg 'zorba-mod2/pom.xml' (Pom 'zorba-mod2')
  Escribe $leg 'zorba-mod2/src/main/java/com/zorba/mod2/ZorbaDos.java' (Clase-Zorba 'ZorbaDos' 12 'com.zorba.mod2')
  Escribe $leg 'src/main/resources/batch/zorba-jobs.xml' "<beans>`n  <batch:job id=`"zorbaJobUno`">`n  </batch:job>`n  <batch:job id=`"zorbaJobDos`">`n  </batch:job>`n</beans>`n"
  Escribe $leg 'src/main/resources/zorba-otro.xml' "<beans>`n  <job id=`"zorbaJobTres`"/>`n  <batch:job-repository id=`"zorbaRepo`"/>`n</beans>`n"
  Escribe $mig 'pom.xml' (Pom 'zorba-migrado')
  Escribe $mig 'src/main/java/com/zorba/migrado/ZorbaNuevaUno.java' (Clase-Zorba 'ZorbaNuevaUno' 8 'com.zorba.migrado')
  Escribe $mig 'src/main/java/com/zorba/migrado/ZorbaNuevaDos.java' (Clase-Zorba 'ZorbaNuevaDos' 9 'com.zorba.migrado')
  Escribe $pl 'pom.xml' (Pom 'zorba-plantilla')
  Escribe $pl 'src/main/java/com/zorba/plantilla/App.java' "package com.zorba.plantilla;`n`n/** Arranque. */`npublic class App {`n}`n"
  foreach ($d in @($leg, $mig, $pl)) { Inicia-Repo $d }
  $aj = [ordered]@{
    CopilotExe = (Join-Path $falsos 'copilot.ps1'); MvnExe = (Join-Path $falsos 'mvn.ps1'); JavaExe = (Join-Path $falsos 'java.ps1')
    SegundosPorLlamada = 30
  }
  foreach ($k in $Ajustes.Keys) { $aj[$k] = $Ajustes[$k] }
  Escribe $casa 'ajustes.json' (ConvertTo-Json -InputObject $aj)
  # rescate.ps1 lee el Maven de .rescate/config.json del repo (no de ajustes.json)
  Escribe $mig '.rescate/config.json' (ConvertTo-Json -InputObject ([ordered]@{ MvnExe = $aj['MvnExe'] }))
  return [pscustomobject]@{ Raiz = $raizE; Legacy = $leg; Migrado = $mig; Plantilla = $pl; Home = $casa; Llamadas = (Join-Path $raizE 'llamadas'); Ajustes = $aj }
}

# Cambia ajustes.json de un escenario (lo demas se queda como estaba).
function Pon-Ajustes($E, [hashtable]$Cambios) {
  foreach ($k in $Cambios.Keys) { $E.Ajustes[$k] = $Cambios[$k] }
  Escribe $E.Home 'ajustes.json' (ConvertTo-Json -InputObject $E.Ajustes)
}

# Un programa de mentira en un fichero (un .sh que lanza el falso con este PowerShell); solo fuera de Windows.
function Nuevo-Lanzador([string]$Ruta, [string]$Falso, [string]$Antes = '') {
  $d = Split-Path $Ruta -Parent
  if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -Force) }
  $t = "#!/bin/sh`n" + $Antes + "exec '" + $ps + "' -NoProfile -File '" + $Falso + "' `"`$@`"`n"
  [System.IO.File]::WriteAllText($Ruta, $t)
  & chmod +x $Ruta
}

# El bloque 6 con un Maven que falla con ese texto; devuelve el resultado.
function Pf-ErrorMaven($E, [string]$Texto, [hashtable]$Extra = @{}) {
  $v = @{ RESCATE_MVN_ERROR = $Texto }
  foreach ($k in $Extra.Keys) { $v[$k] = $Extra[$k] }
  return (Pf $E (Todos $E @('-Solo', '6')) '' $v)
}

# Todo seguido, con los tres repos: lo que usan las pruebas que no miran un detalle concreto.
function Todos($E, [string[]]$Mas = @()) {
  return (@('-Legacy', $E.Legacy, '-Migrado', $E.Migrado, '-Plantilla', $E.Plantilla) + $Mas)
}

# El primer lanzamiento completo se guarda: lo usan las pruebas 1, 3 y 10.
$script:R1 = $null
$script:E1 = $null
function Get-Completo {
  if ($null -eq $script:R1) {
    $script:E1 = Nuevo-Escenario 'completo'
    $script:R1 = Pf $script:E1 (Todos $script:E1 @('-Modelo', 'modelo-x')) 'lento:^ValidadorImporte[1-4]$'
  }
  return $script:R1
}

# ================================ PRUEBAS ================================
$Pruebas = [ordered]@{}

$Pruebas['1 completo: ocho bloques con los tres repos y los falsos, sin fallos'] = {
  $r = Get-Completo
  $e = $script:E1
  Igual 'sale con 0' 0 $r.Codigo
  Comprueba 'deja preflight-resultado.txt' (Test-Path -LiteralPath $r.Ruta) (Cola $r.Salida)
  $l = Lineas-De $r
  Comprueba 'la primera linea es PREFLIGHT java-scripts y el commit (o sin-git)' ($l.Count -gt 0 -and $l[0] -match '^PREFLIGHT java-scripts (sin-git|[0-9a-f]{4,40})$') $l[0]
  foreach ($n in 1..8) { Comprueba "tiene el bloque $n" ((Cuenta-Lineas $r ("^== $n ")) -gt 0) }
  Comprueba 'acaba con == fin' ($l -contains '== fin')
  Igual 'bloques con fallo: ninguno' 'ninguno' (Valor-De $r 'bloques con fallo')
  Comprueba 'dice la duracion' ((Valor-De $r 'duracion') -match '^\d+ min$') (Valor-De $r 'duracion')
  Comprueba 'ningun bloque escribe fallo:' ((Cuenta-Lineas $r '^fallo:') -eq 0) (($l | Where-Object { $_ -match '^fallo:' }) -join ' / ')
  Comprueba 'la consola ensena el resultado al final' ($r.Salida -match '(?m)^== fin') (Cola $r.Salida)
  Comprueba 'la consola avisa de cada bloque con lo que puede tardar (los bancos, hasta 30 min)' ($r.Salida -match '== 2 bancos \(hasta 30 min\)\.\.\.' -and $r.Salida -match '== 8 clases reales \(hasta \d+ min\)\.\.\.') (Cola $r.Salida)
  $fin = @($r.Salida -split "\r?\n" | Where-Object { $_.Trim() -ne '' } | Select-Object -Last 2)
  Comprueba 'la consola acaba diciendo donde esta el resultado, sin ruta' ($fin.Count -eq 2 -and $fin[0] -ceq 'Resultado en preflight-resultado.txt, junto al script.') ($fin -join ' / ')
  Comprueba 'y si lo copio al portapapeles (si o no)' ($fin.Count -eq 2 -and $fin[1] -cmatch '^Copiado al portapapeles: (si|no)$') ($fin -join ' / ')
  Comprueba 'esas dos lineas no van al fichero' ($r.Fichero -notmatch 'portapapeles' -and $r.Fichero -notmatch 'Resultado en')
  Comprueba 'y cada bloque acaba con hecho' ((@($r.Salida -split "\r?\n" | Where-Object { $_ -eq 'hecho' }).Count) -eq 8) (Cola $r.Salida)

  # 1 entorno
  Igual '1: modo de lenguaje' 'FullLanguage' (Valor-De $r 'modo de lenguaje')
  Comprueba '1: version y edicion de PowerShell' ((Valor-De $r 'powershell') -match '^\d+\.\d+\.\d+(\.\d+)? (Core|Desktop)$') (Valor-De $r 'powershell')
  Comprueba '1: politica de ejecucion efectiva y por ambito' ((Valor-De $r 'politica de ejecucion') -match 'efectiva \w+ \| .*Process=') (Valor-De $r 'politica de ejecucion')
  Comprueba '1: version de Windows en numeros' ((Valor-De $r 'windows') -match '^\d+\.\d+\.\d+') (Valor-De $r 'windows')
  Comprueba '1: versiones de git, java, maven y copilot (solo el numero)' (((Valor-De $r 'git') -match '^\d+\.\d+') -and ((Valor-De $r 'java') -eq '21.0.0') -and ((Valor-De $r 'maven') -eq '3.9.8') -and ((Valor-De $r 'copilot') -eq '1.0.112')) (((Bloque-De $r '1') | Select-Object -First 12) -join ' / ')
  Igual '1: tipo de copilot' '.ps1' (Valor-De $r 'tipo de copilot')
  Igual '1: impide la suspension' 'si' ((Valor-De $r 'impide la suspension') -replace ' .*$', '')
  Comprueba '1: pagina de codigos' ((Valor-De $r 'pagina de codigos') -match '^\d+') (Valor-De $r 'pagina de codigos')
  Comprueba '1: GB libres' ((Valor-De $r 'GB libres') -match '^\d+(\.\d+)?$') (Valor-De $r 'GB libres')

  # 2 bancos y 10 los otros dos bancos siguen igual
  Comprueba '2: probar.ps1 pasa sus 75 comprobaciones (N de M en S s)' ((Valor-De $r 'probar') -match '^75 de 75 en \d+ s$') (Valor-De $r 'probar')
  Comprueba '2: probar-migracion.ps1 pasa sus 232 comprobaciones' ((Valor-De $r 'probar-migracion') -match '^232 de 232 en \d+ s$') (Valor-De $r 'probar-migracion')
  Igual '2: fallan' 'ninguna' (Valor-De $r 'fallan')

  # 3 copilot
  $b3 = @(Bloque-De $r '3')
  foreach ($f in @('-p', '-s', '--allow-all-tools', '--no-ask-user', '--deny-tool', '--model', '--effort', '--reasoning-effort', '--add-dir', '--no-custom-instructions', '--available-tools', '--max-ai-credits')) {
    Igual "3: bandera $f" 'si' (Valor-De $r "bandera $f")
  }
  Igual '3: la ayuda lista modelos' 'si' (Valor-De $r 'ayuda lista modelos')
  Comprueba '3: y dice los ids con forma de modelo' ((Valor-De $r 'modelos en la ayuda') -match 'gpt-6-luna' -and (Valor-De $r 'modelos en la ayuda') -match 'claude-sonnet-5\.5') (Valor-De $r 'modelos en la ayuda')

  # 4 aptitud
  Igual '4: modelo' 'modelo-x' (Valor-De $r 'modelo')
  foreach ($k in 1..3) { Comprueba "4: intento $k valido" ((Valor-De $r "intento $k") -match '^json si \| datos 2 \| citas 2 de 2 \| \d+ s$') (Valor-De $r "intento $k") }
  Comprueba '4: esfuerzo alto' ((Valor-De $r 'esfuerzo alto') -match '^json si \| datos 2 \| citas 2 de 2 \| \d+ s$') (Valor-De $r 'esfuerzo alto')
  Comprueba '4: herramientas limitadas' ((Valor-De $r 'herramientas limitadas') -match '^json si \| datos 2 \| citas 2 de 2 \| \d+ s$') (Valor-De $r 'herramientas limitadas')

  # 5 paralelo
  Comprueba '5: 4 de 4 validas con el total y la mas lenta' ((Valor-De $r 'validas') -match '^4 de 4 \| \d+ s en total \| la mas lenta \d+ s$') (Valor-De $r 'validas')
  Comprueba '5: frente a serie' ((Valor-De $r 'frente a serie') -match '^\d+,\d$') (Valor-De $r 'frente a serie')

  # 6 maven de juguete
  Comprueba '6: compila y pasa el test' ((Valor-De $r 'compila y pasa el test') -match '^si \| \d+ s$') (Valor-De $r 'compila y pasa el test')
  Comprueba '6: jacoco' ((Valor-De $r 'jacoco') -match '^si \| \d+ s$') (Valor-De $r 'jacoco')
  Comprueba '6: openrewrite' ((Valor-De $r 'openrewrite') -match '^si \| \d+ s$') (Valor-De $r 'openrewrite')
  Igual '6: maven usado (el de los ajustes)' 'ajustes' (Valor-De $r 'maven usado')

  # 7 forma de los repos (solo numeros)
  Igual '7: ficheros java del original' '9' (Valor-De $r 'original ficheros java')
  Igual '7: lineas del original' '697' (Valor-De $r 'original lineas')
  Igual '7: ficheros de mas de 300 lineas' '1' (Valor-De $r 'original ficheros de mas de 300 lineas')
  Igual '7: el mas largo' '350 lineas' (Valor-De $r 'original fichero mas largo')
  Igual '7: modulos' '2' (Valor-De $r 'original modulos (src/main/java)')
  Igual '7: pom.xml' '2' (Valor-De $r 'original pom.xml')
  Igual '7: xml con jobs y cuantos jobs' '2 (jobs: 3)' (Valor-De $r 'original xml con jobs')
  Igual '7: clases con JobBuilder o EnableBatchProcessing' '2' (Valor-De $r 'original clases con JobBuilder o EnableBatchProcessing')
  Igual '7: ficheros que no son UTF-8' '1' (Valor-De $r 'original ficheros no UTF-8')
  Igual '7: migrado' '2 | lineas: 17 | modulos: 1' (Valor-De $r 'migrado ficheros java')
  Igual '7: referencia' '1 | lineas: 5 | modulos: 1' (Valor-De $r 'plantilla ficheros java')
  # la forma de los tres repos, con un repo sin nada de lo que se cuenta
  foreach ($n in @('original', 'migrado', 'plantilla')) {
    Igual "7: $n repo git" 'si' (Valor-De $r "$n repo git")
    Igual "7: $n en una rama" 'si' (Valor-De $r "$n en una rama")
    Igual "7: $n tests" '0 ficheros' (Valor-De $r "$n tests")
    Igual "7: $n pom" 'java ninguno | spring-boot ninguno | padre ninguno' (Valor-De $r "$n pom")
    Igual "7: $n sftp" 'jsch 0 | sshd 0 | spring-integration 0 | sshj 0' (Valor-De $r "$n sftp")
    Igual "7: $n config" '@Value 0 | @ConfigurationProperties 0 | getenv 0 | ficheros application 0' (Valor-De $r "$n config")
    Igual "7: $n ficheros locales" '0' (Valor-De $r "$n ficheros locales")
  }
  $iNuevo = [array]::IndexOf($l, ('original repo git: si'))
  $iDiag = [array]::IndexOf($l, @($l | Where-Object { $_ -match '^diagnostico: ' })[0])
  Comprueba '7: las lineas nuevas van tras las de siempre y antes del diagnostico' ($iNuevo -gt [array]::IndexOf($l, 'plantilla ficheros java: 1 | lineas: 5 | modulos: 1') -and $iNuevo -lt $iDiag) "$iNuevo $iDiag"
  foreach ($p in @('build', 'estructura', 'hexagonal', 'ficheros', 'config', 'paridad', 'e2e', 'tests', 'calidad')) {
    Comprueba "7: diagnostico, paso $p" ((Valor-De $r $p) -match '^\d+ errores, \d+ avisos$') (Valor-De $r $p)
  }
  Comprueba '7: diagnostico con su codigo y su tiempo' ((Valor-De $r 'diagnostico') -match '^codigo 0 en \d+ s$') (Valor-De $r 'diagnostico')

  # 8 clases reales
  Igual '8: cinco clases' 5 (Cuenta-Lineas $r '^clase \d: ')
  Comprueba '8: de las cinco por tamano, con json, datos y citas' ((Cuenta-Lineas $r '^clase \d: \d+ lineas \| json si \| datos 2 \| citas 2 de 2 \| \d+ s$') -eq 5) (($l | Where-Object { $_ -match '^clase ' }) -join ' / ')
  Igual '8: del mas corto al mas largo que cabe en una tarea' '25 30 55 80 120' ((@($l | Where-Object { $_ -match '^clase \d: (\d+) lineas' } | ForEach-Object { $Matches[1] })) -join ' ')
  Igual '8: original sin cambios' 'si' (Valor-De $r 'original sin cambios')

  # las llamadas que hizo el falso (el preflight borra sus carpetas)
  $ll = @(Llamadas $e.Llamadas)
  Igual '14 llamadas al modelo: 5 de aptitud, 4 en paralelo y 5 de clases reales' 14 $ll.Count
  Comprueba 'todas llevan el modelo y --no-custom-instructions' (@($ll | Where-Object { $_.flags -match '--model=modelo-x' -and $_.flags -match '--no-custom-instructions' }).Count -eq 14)
  $apt = @(Llamadas-De $ll 'pf-apt-')
  Comprueba 'aptitud: tres con esfuerzo de lectura, una con esfuerzo alto y una con herramientas limitadas' (@($apt | Where-Object { $_.id -match '^pf-apt-\d$' -and $_.flags -match '--effort=medium' }).Count -eq 3 -and @($apt | Where-Object { $_.id -eq 'pf-apt-alto' -and $_.flags -match '--effort=high' }).Count -eq 1 -and @($apt | Where-Object { $_.flags -match '--available-tools=view,create' }).Count -eq 1) (($apt | ForEach-Object { $_.id + ' ' + $_.flags }) -join ' | ')
  Comprueba 'aptitud: ningun prompt lleva la seccion de correccion (el esfuerzo alto sale con el mismo prompt)' (@($ll | Where-Object { $_.correccion -eq 'True' }).Count -eq 0)
  $par = Max-Simultaneas @(Llamadas-De $ll 'pf-par-')
  Comprueba 'paralelo: a lo sumo cuatro llamadas a la vez' ($par -le 4) $par
  Comprueba 'paralelo: y mas de una a la vez (con la maquina cargada no siempre llegan a cuatro)' ($par -ge 2) $par
  $cl = @(Llamadas-De $ll 'pf-cls-')
  Comprueba 'clases reales: 5 llamadas, todas con --add-dir del original' ($cl.Count -eq 5 -and @($cl | Where-Object { $_.flags -match '--add-dir=\S*zorba-legado-xq' }).Count -eq 5) (($cl | ForEach-Object { $_.flags }) -join ' | ')
  $clMax = Max-Simultaneas $cl
  Comprueba 'clases reales: a lo sumo 4 a la vez' ($clMax -le 4) $clMax
  Comprueba 'clases reales: y mas de una a la vez' ($clMax -ge 2) $clMax
  Sin-Fugas $r 'completo'
  Igual 'el original queda limpio' '' (GitEn $e.Legacy @('status', '--porcelain'))
  Comprueba 'el original no recibe carpeta .rescate' (-not (Test-Path -LiteralPath (Join-Path $e.Legacy '.rescate')))
}

$Pruebas['2 privacidad: nada de la empresa en el fichero ni en la consola, con errores que lo llevan todo'] = {
  $e = Nuevo-Escenario 'privacidad'
  $nene = [string][char]0xF1 + [char]0xE9
  # una linea larga: la biblioteca corta a 200 caracteres y el corte cae dentro del nombre del original
  $en = $e.Legacy.IndexOf('zorba-legado-xq') + 5
  $relleno = ('x' * (200 - $en - 1)) + ' '
  $secreto = $relleno + $e.Legacy + ' ' + $e.Migrado + ' ' + $e.Plantilla + ' zorba-legado-xq ZorbaCorta usuario zorbalex equipo PCZORBA dominio DOMZORBA zorba.local ' +
  'correo jefe.zorba@zorba-corp.com ip 10.77.88.99 url https://nexus.zorba-interno.local:8443/repo/x y http://zorba.local/a en [nexus.zorba-interno.local/10.77.88.99] ' +
  'Connect to nexus.zorba-interno.local:8443 failed ' + [Environment]::GetFolderPath('UserProfile') + ' ' + $nene + ' publico https://repo.maven.apache.org/maven2/ y github.com'
  $corto = 'publico https://repo.maven.apache.org/maven2/ https://github.com/x/y ' + $e.Legacy + ' ' + $e.Migrado + ' ' + $e.Plantilla + ' zorbalex PCZORBA DOMZORBA.zorba.local jefe.zorba@zorba-corp.com 10.77.88.99 https://nexus.zorba-interno.local:8443/repo/x [nexus.zorba-interno.local/10.77.88.99] Connect to nexus.zorba-interno.local:8443 ' + [Environment]::GetFolderPath('UserProfile') + ' ' + $nene
  # a) Copilot sale con un error con de todo (bloque 4: sin modelo) y Maven falla con otro (bloque 6)
  $a = Pf $e (Todos $e @('-Solo', '1,4,5,6,7,8')) 'error-privado:^Validador' @{ RESCATE_ERROR_TEXTO = $secreto; RESCATE_MVN_ERROR = $corto }
  Igual 'a) sale con 0' 0 $a.Codigo
  Comprueba 'a) bloque 4: sin modelo' ((Valor-De $a 'sin modelo') -ne '') ((Bloque-De $a '4') -join ' / ')
  Comprueba 'a) lo publico se queda (repo.maven.apache.org, github.com) y lo demas es <ruta> <usuario> <ip> <url-interna>' ((Valor-De $a 'error') -match 'repo\.maven\.apache\.org' -and (Valor-De $a 'error') -match 'github\.com' -and (Valor-De $a 'error') -match '<' ) ((Bloque-De $a '6') -join ' / ')
  Comprueba 'a) bloque 6: el error de Maven lleva etiquetas en vez de datos' ((Valor-De $a 'error') -match '<LEGACY>' -and (Valor-De $a 'error') -match '<usuario>' -and (Valor-De $a 'error') -match '<equipo>' -and (Valor-De $a 'error') -match '<correo>' -and (Valor-De $a 'error') -match '<ip>' -and (Valor-De $a 'error') -match '<url-interna>') (Valor-De $a 'error')
  Comprueba 'a) todo texto cortado a 200 caracteres' (@((Lineas-De $a) | Where-Object { $_.Length -gt 230 }).Count -eq 0)
  Comprueba 'a) los bloques 5 y 8 se saltan: sin modelo' ((Valor-De $a 'saltado') -match 'sin modelo') ((Bloque-De $a '5') -join ' / ')
  Sin-Fugas $a 'a'
  Comprueba 'a) y es ASCII puro' ((Es-Ascii $a.Fichero) -and (Es-Ascii $a.Salida))
  # b) el bloque 5 sin el bloque 4 antes: cuatro llamadas que fallan con ese error
  $b = Pf $e (Todos $e @('-Solo', '5')) 'error-privado:^Validador' @{ RESCATE_ERROR_TEXTO = $secreto }
  Comprueba 'b) bloque 5: 0 de 4 validas y los motivos filtrados' ((Valor-De $b 'validas') -match '^0 de 4' -and (Cuenta-Lineas $b '^motivo \d: ') -eq 4) ((Bloque-De $b '5') -join ' / ')
  Sin-Fugas $b 'b'
  # c) bloque 8: fichas invalidas con textos del modelo con comillas simples y un fallo de Copilot
  $c = Pf $e (Todos $e @('-Solo', '4,8')) 'valor-secreto:^ZorbaCorta;cita-secreta:^ZorbaLarga;falla-siempre:^ZorbaAncha'
  $b8 = @(Bloque-De $c '8')
  Comprueba 'c) bloque 8: cinco clases con numeros y motivos cortos' ((Cuenta-Lineas $c '^clase \d: ') -eq 5) ($b8 -join ' / ')
  Comprueba 'c) el valor invalido deja solo el principio del mensaje' ((@($b8 | Where-Object { $_ -match "^motivo: El campo 'papel' vale$" }).Count) -eq 1) ($b8 -join ' / ')
  Comprueba 'c) la cita inventada deja solo el principio del mensaje' ((@($b8 | Where-Object { $_ -match '^motivo: Mas de la mitad de las citas \(3 de 3\) no salen en el fichero, por ejemplo$' }).Count) -eq 1) ($b8 -join ' / ')
  Comprueba 'c) un fallo de Copilot es solo fallo, codigo N' ((@($b8 | Where-Object { $_ -match '^clase \d: \d+ lineas \| fallo, codigo 1 \| \d+ s$' }).Count) -eq 1) ($b8 -join ' / ')
  Comprueba 'c) la ficha valida de las otras dos sigue contando datos y citas' ((Cuenta-Lineas $c '^clase \d: \d+ lineas \| json si \| datos 2 \| citas 2 de 2') -eq 2) ($b8 -join ' / ')
  Comprueba 'c) las dos fichas que no pasan la comprobacion dicen json no' ((Cuenta-Lineas $c '^clase \d: \d+ lineas \| json no \| datos 0 \| citas 0 de 0 \| \d+ s$') -eq 2) ($b8 -join ' / ')
  Sin-Fugas $c 'c'
  Comprueba 'c) y es ASCII puro' ((Es-Ascii $c.Fichero) -and (Es-Ascii $c.Salida))
  # d) un fichero del original cambia durante la lectura: se dice, sin nombres
  $d = Pf $e (Todos $e @('-Solo', '8')) 'toca-original:^ZorbaMedia'
  Igual 'd) original sin cambios: no' 'no' (Valor-De $d 'original sin cambios')
  Sin-Fugas $d 'd'
  [void](GitEn $e.Legacy @('checkout', '-q', '--', '.'))
}

$Pruebas['3 ASCII: el fichero de resultado es ASCII puro'] = {
  $r = Get-Completo
  $bytes = [System.IO.File]::ReadAllBytes($r.Ruta)
  Comprueba 'ningun byte pasa de 127' (@($bytes | Where-Object { $_ -gt 127 }).Count -eq 0)
  Comprueba 'ni caracteres de control salvo el fin de linea' (@($bytes | Where-Object { $_ -lt 32 -and $_ -ne 10 -and $_ -ne 13 }).Count -eq 0)
  Comprueba 'no empieza con BOM' ($bytes.Count -gt 3 -and $bytes[0] -ne 0xEF)
  $src = [System.IO.File]::ReadAllBytes($Script)
  Comprueba 'preflight.ps1 tambien es ASCII' (@($src | Where-Object { $_ -gt 127 }).Count -eq 0)
}

$Pruebas['4 -Solo y -SinCopilot: solo los bloques pedidos; saltados con su motivo'] = {
  $e = Nuevo-Escenario 'solo'
  $r = Pf $e (Todos $e @('-Solo', '1'))
  Igual '-Solo 1 sale con 0' 0 $r.Codigo
  Comprueba '-Solo 1: el bloque 1 y el fin, nada mas' ((Cuenta-Lineas $r '^== ') -eq 2 -and (Cuenta-Lineas $r '^== 1 entorno') -eq 1 -and (Cuenta-Lineas $r '^== fin') -eq 1) ((Lineas-De $r | Where-Object { $_ -match '^== ' }) -join ' / ')
  Igual '-Solo 1: la primera linea sin git' 'PREFLIGHT java-scripts sin-git' ((Lineas-De $r)[0])
  Comprueba '-Solo 1: llama a cero modelos' (@(Llamadas $e.Llamadas).Count -eq 0)
  $r2 = Pf $e (Todos $e @('-Solo', '1,3'))
  Comprueba '-Solo 1,3: los bloques 1 y 3' ((Cuenta-Lineas $r2 '^== ') -eq 3 -and (Cuenta-Lineas $r2 '^== 3 copilot') -eq 1) ((Lineas-De $r2 | Where-Object { $_ -match '^== ' }) -join ' / ')
  Comprueba '-Solo 3: el bloque 3 no llama a ningun modelo' (@(Llamadas $e.Llamadas).Count -eq 0)
  # con el repo en git, la primera linea lleva el commit corto
  Nueva-Instalacion
  if (Test-Path -LiteralPath $r.Ruta) { Remove-Item -LiteralPath $r.Ruta -Force }
  Inicia-Repo $Inst
  $corto = (GitEn $Inst @('rev-parse', '--short', 'HEAD')).Trim()
  $r3 = Pf $e (Todos $e @('-Solo', '1'))
  Igual 'en un repo git la primera linea lleva el commit corto' "PREFLIGHT java-scripts $corto" ((Lineas-De $r3)[0])
  Remove-Item -LiteralPath (Join-Path $Inst '.git') -Recurse -Force
  # -SinCopilot: 4, 5 y 8 saltados y ninguna llamada
  $s = Pf $e (Todos $e @('-Solo', '1,3,4,5,8', '-SinCopilot'))
  Igual '-SinCopilot sale con 0' 0 $s.Codigo
  foreach ($n in @('4', '5', '8')) {
    $b = @(Bloque-De $s $n)
    Comprueba "-SinCopilot: el bloque $n queda saltado" ($b.Count -eq 1 -and $b[0] -match '^saltado: ') ($b -join ' / ')
  }
  Comprueba '-SinCopilot: el bloque 3 se hace' ((Valor-De $s 'bandera -p') -eq 'si')
  Comprueba '-SinCopilot: no hay ni una llamada al modelo' (@(Llamadas $e.Llamadas).Count -eq 0)
  Igual '-SinCopilot: bloques con fallo' 'ninguno' (Valor-De $s 'bloques con fallo')
  # -SinMaven: 6 saltado y sin diagnostico en el 7
  $m = Pf $e (Todos $e @('-Solo', '6,7', '-SinMaven'))
  Comprueba '-SinMaven: el bloque 6 queda saltado' ((@(Bloque-De $m '6') -join '') -match '^saltado: ') ((Bloque-De $m '6') -join ' / ')
  Comprueba '-SinMaven: el 7 sigue con los numeros y salta solo el diagnostico' ((Valor-De $m 'original ficheros java') -eq '9' -and (Valor-De $m 'diagnostico') -match '^saltado') ((Bloque-De $m '7') -join ' / ')
  Sin-Fugas $m 'sinmaven'
}

$Pruebas['5 un bloque que revienta deja fallo: y los siguientes se hacen'] = {
  $e = Nuevo-Escenario 'revienta' @{ MvnExe = (Join-Path $Dir 'no-existe-zorba/mvn.ps1') }
  $r = Pf $e (Todos $e @('-Solo', '1,6,7,8'))
  Igual 'sale con 0 (pudo escribir el fichero)' 0 $r.Codigo
  $b6 = @(Bloque-De $r '6')
  Comprueba 'el bloque 6 dice que Maven uso y deja fallo:' ($b6.Count -ge 2 -and $b6[0] -ceq 'maven usado: ajustes' -and @($b6 | Where-Object { $_ -match '^fallo: .+' }).Count -eq 1) ($b6 -join ' / ')
  Comprueba 'los siguientes se hacen: hay bloque 7 con numeros y bloque 8 con sus 5 clases' ((Valor-De $r 'original ficheros java') -eq '9' -and (Cuenta-Lineas $r '^clase \d: ') -eq 5) (Cola $r.Salida)
  Comprueba 'bloques con fallo nombra el 6' ((Valor-De $r 'bloques con fallo') -match '(^| )6( |$)') (Valor-De $r 'bloques con fallo')
  Comprueba 'acaba con == fin' ((Lineas-De $r) -contains '== fin')
  $b7 = @(Bloque-De $r '7')
  Comprueba 'el fallo del bloque 7 (si lo hay) no lleva texto del sistema: solo el tipo y el fichero:linea' (@($b7 | Where-Object { $_ -match '^fallo: ' -and $_ -notmatch '^fallo: \w+ \(\w+\.ps1:\d+\)$' }).Count -eq 0) ($b7 -join ' / ')
  Sin-Fugas $r 'revienta'
}

$Pruebas['6 bloque 3: un Copilot que rechaza una bandera sale no en esa y si en las demas'] = {
  $e = Nuevo-Escenario 'banderas'
  $r = Pf $e (Todos $e @('-Solo', '3')) 'rechaza-bandera:--reasoning-effort'
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'bandera --reasoning-effort: no' 'no' (Valor-De $r 'bandera --reasoning-effort')
  Igual 'las otras 11 dicen si' 11 (Cuenta-Lineas $r '^bandera \S+: si$')
  Igual 'una sola dice no' 1 (Cuenta-Lineas $r '^bandera \S+: no$')
  $r2 = Pf $e (Todos $e @('-Solo', '3')) 'rechaza-bandera:-p'
  Igual 'con -p rechazada: -p dice no' 'no' (Valor-De $r2 'bandera -p')
  Igual 'y las otras 11 si' 11 (Cuenta-Lineas $r2 '^bandera \S+: si$')
  Igual 'ninguna sonda llamo a un modelo' 0 @(Llamadas $e.Llamadas).Count
}

$Pruebas['7 bloque 4 sin cuota: sin modelo y ninguna llamada mas'] = {
  $e = Nuevo-Escenario 'cuota'
  $r = Pf $e (Todos $e @('-Solo', '4,5,8')) 'sin-cuota:^Validador'
  Igual 'sale con 0' 0 $r.Codigo
  $sm = Valor-De $r 'sin modelo'
  Comprueba 'dice sin modelo con la ultima linea de lo que dijo Copilot' ($sm -match 'exceeded your monthly quota') $sm
  Igual 'modelo: el de Copilot (sin -Modelo)' 'el de Copilot' (Valor-De $r 'modelo')
  Igual 'no hay intento 2 ni 3' 0 (Cuenta-Lineas $r '^(intento [23]|esfuerzo alto|herramientas limitadas):')
  Igual 'una sola llamada en todo el lanzamiento' 1 @(Llamadas $e.Llamadas).Count
  Comprueba 'los bloques 5 y 8 se saltan por falta de modelo' ((@(Bloque-De $r '5') -join '') -match '^saltado: .*modelo' -and (@(Bloque-De $r '8') -join '') -match '^saltado: .*modelo') ((Lineas-De $r) -join ' / ')
  Comprueba 'sin -Modelo no hay flag de modelo en la llamada' (@(Llamadas $e.Llamadas | Where-Object { $_.flags -match '--model=' }).Count -eq 0)
  Igual 'sin modelo no cuenta como bloque con fallo' 'ninguno' (Valor-De $r 'bloques con fallo')
}

$Pruebas['8 bloque 8: el original queda sin cambios y salen 5 clases'] = {
  $e = Nuevo-Escenario 'clases'
  $r = Pf $e (Todos $e @('-Solo', '8'))
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'cinco lineas clase N:' 5 (Cuenta-Lineas $r '^clase \d: ')
  Igual 'original sin cambios: si' 'si' (Valor-De $r 'original sin cambios')
  Igual 'git status del original, limpio' '' (GitEn $e.Legacy @('status', '--porcelain'))
  $ll = @(Llamadas $e.Llamadas)
  Igual 'cinco llamadas' 5 $ll.Count
  Comprueba 'cuatro a la vez y despues una' ((Max-Simultaneas $ll) -le 4) (Max-Simultaneas $ll)
  Sin-Fugas $r 'clases'
  # sin -Legacy el bloque 8 se salta
  $r2 = Pf $e @('-Solo', '7,8')
  Comprueba 'sin -Legacy: los bloques 7 y 8 quedan saltados' ((@(Bloque-De $r2 '7') -join '') -match '^saltado: ' -and (@(Bloque-De $r2 '8') -join '') -match '^saltado: ') ((Lineas-De $r2) -join ' / ')
}

$Pruebas['9 .gitignore: preflight-resultado.txt no se sube'] = {
  $g = Join-Path $origen '.gitignore'
  Comprueba 'existe .gitignore' (Test-Path -LiteralPath $g)
  if (Test-Path -LiteralPath $g) {
    $t = [System.IO.File]::ReadAllText($g)
    Comprueba 'lista preflight-resultado.txt' ($t -match '(?m)^/?preflight-resultado\.txt\s*$')
  }
}

$Pruebas['10 sin -ExecutionPolicy: la politica es la del equipo, ni en el preflight ni en los bancos'] = {
  $ast = [System.Management.Automation.Language.Parser]::ParseFile($Script, [ref]$null, [ref]$null)
  $f = $ast.Find({ param($n) ($n -is [System.Management.Automation.Language.FunctionDefinitionAst]) -and $n.Name -eq 'Get-ArgsPowerShell' }, $true)
  Comprueba 'preflight.ps1 define Get-ArgsPowerShell' ($null -ne $f)
  if ($f) {
    . ([scriptblock]::Create($f.Extent.Text))
    $so = $env:OS
    $env:OS = 'Windows_NT'
    try { $a = @(Get-ArgsPowerShell @('x.ps1', '-Dir', 'd')) } finally { $env:OS = $so }
    Comprueba 'con un Windows simulado, los argumentos no llevan ExecutionPolicy ni Bypass' (($a -join ' ') -notmatch 'ExecutionPolicy' -and ($a -join ' ') -notmatch 'Bypass') ($a -join ' ')
    Igual 'y son -NoProfile -File y lo que se le pasa' '-NoProfile|-File|x.ps1|-Dir|d' ($a -join '|')
  }
  $src = [System.IO.File]::ReadAllText($Script)
  Comprueba 'preflight.ps1 no pone -ExecutionPolicy ni Bypass en ninguna parte' ($src -notmatch '(?<!Get)-ExecutionPolicy' -and $src -notmatch 'Bypass')
  $banco = [System.IO.File]::ReadAllText((Join-Path $aqui 'comun-banco.ps1'))
  Comprueba 'comun-banco.ps1 (el Lanzar de los tres bancos) tampoco' ($banco -notmatch 'ExecutionPolicy' -and $banco -notmatch 'Bypass')
}

$Pruebas['11 modo de lenguaje restringido: solo el bloque 1 con su aviso, sin cargar nada'] = {
  $e = Nuevo-Escenario 'restringido'
  Nueva-Instalacion
  $f = Join-Path $Inst 'preflight-resultado.txt'
  if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force }
  $env:RESCATE_HOME = $e.Home
  $ErrorActionPreference = 'Continue'
  $pre = @('-NoProfile')
  $cmd = "`$ExecutionContext.SessionState.LanguageMode = 'ConstrainedLanguage'; & '" + (Join-Path $Inst 'preflight.ps1') + "' -Legacy '" + $e.Legacy + "'; exit `$LASTEXITCODE"
  $o = & $ps @pre -Command $cmd 2>&1 | ForEach-Object { "$_" }
  $c = $LASTEXITCODE
  $ErrorActionPreference = 'Stop'
  $env:RESCATE_HOME = ''
  Igual 'sale con 0' 0 $c
  $txt = ''
  if (Test-Path -LiteralPath $f) { $txt = [System.IO.File]::ReadAllText($f) }
  Comprueba 'deja el fichero' ($txt -ne '') ((@($o) | Select-Object -Last 8) -join ' / ')
  Comprueba 'dice el modo de lenguaje' ($txt -match '(?m)^modo de lenguaje: ConstrainedLanguage')
  Comprueba 'dice para: modo de lenguaje restringido' ($txt -match '(?m)^para: modo de lenguaje restringido')
  Comprueba 'solo el bloque 1 y el fin' ((@($txt -split "\r?\n" | Where-Object { $_ -match '^== ' }).Count) -eq 2 -and $txt -match '== fin') $txt
  Comprueba 'y es ASCII puro' (Es-Ascii $txt)
}

$Pruebas['12 ruta mal escrita: se dice al instante, sale con 1, no ejecuta ningun bloque y no repite la ruta'] = {
  $e = Nuevo-Escenario 'rutas'
  $r = Pf $e @('-Legacy', (Join-Path $e.Raiz 'zorba-no-existe'), '-Migrado', $e.Migrado)
  Igual '-Legacy: sale con 1' 1 $r.Codigo
  Comprueba '-Legacy: lo dice por consola' ($r.Salida -match '(?m)^No existe la carpeta de -Legacy\. Revisa la ruta y vuelve a lanzar\.\s*$') (Cola $r.Salida)
  $l = @(Lineas-De $r)
  Comprueba '-Legacy: el fichero lleva la cabecera, el motivo y el fin' ($l.Count -eq 3 -and $l[0] -match '^PREFLIGHT java-scripts ' -and $l[1] -ceq 'para: no existe la carpeta de -Legacy' -and $l[2] -ceq '== fin') ($l -join ' / ')
  Comprueba '-Legacy: no ejecuta ningun bloque (ni en el fichero ni en la consola)' ((Cuenta-Lineas $r '^== \d') -eq 0 -and $r.Salida -notmatch '(?m)^== \d') (Cola $r.Salida)
  Comprueba '-Legacy: no llama a ningun modelo' (@(Llamadas $e.Llamadas).Count -eq 0)
  Sin-Fugas $r '-Legacy'
  # dos mal a la vez (una carpeta que no existe y un fichero): una linea para cada una, en el orden de los parametros
  $r2 = Pf $e @('-Legacy', $e.Legacy, '-Migrado', (Join-Path $e.Raiz 'zorba-otra-ruta-mala'), '-Plantilla', (Join-Path $e.Legacy 'pom.xml'))
  Igual 'dos mal: sale con 1' 1 $r2.Codigo
  $l2 = @(Lineas-De $r2)
  Comprueba 'dos mal: el fichero dice -Migrado y -Plantilla' ($l2.Count -eq 4 -and $l2[1] -ceq 'para: no existe la carpeta de -Migrado' -and $l2[2] -ceq 'para: no existe la carpeta de -Plantilla' -and $l2[3] -ceq '== fin') ($l2 -join ' / ')
  Comprueba 'dos mal: y la consola tambien' ($r2.Salida -match '(?m)^No existe la carpeta de -Migrado\. Revisa la ruta y vuelve a lanzar\.\s*$' -and $r2.Salida -match '(?m)^No existe la carpeta de -Plantilla\. Revisa la ruta y vuelve a lanzar\.\s*$') (Cola $r2.Salida)
  Comprueba 'dos mal: no ejecuta ningun bloque' ((Cuenta-Lineas $r2 '^== \d') -eq 0 -and $r2.Salida -notmatch '(?m)^== \d')
  Sin-Fugas $r2 'dos mal'
}

$Pruebas['13 bloque 1: tipo de copilot (extension, sin extension, no encontrado) y GB libres con una ruta relativa'] = {
  $e = Nuevo-Escenario 'tipo'
  Pon-Ajustes $e @{ CopilotExe = (Join-Path $Dir 'no-existe-zorba/copilot.exe') }
  $r = Pf $e (Todos $e @('-Solo', '1'))
  Igual 'un Copilot que no esta: no encontrado' 'no encontrado' (Valor-De $r 'tipo de copilot')
  Sin-Fugas $r 'tipo'
  if ($env:OS -ne 'Windows_NT') {
    foreach ($c in @(@('copilot-sin-ext', 'sin extension'), @('copilot.cmd', '.cmd'), @('copilot.zorba', 'otra'))) {
      $exe = Join-Path (Join-Path $e.Raiz 'bin') $c[0]
      Nuevo-Lanzador $exe (Join-Path $falsos 'copilot.ps1')
      Pon-Ajustes $e @{ CopilotExe = $exe }
      $x = Pf $e (Todos $e @('-Solo', '1'))
      Igual ('un Copilot ' + $c[0] + ': ' + $c[1]) $c[1] (Valor-De $x 'tipo de copilot')
    }
  }
  Pon-Ajustes $e @{ CopilotExe = (Join-Path $falsos 'copilot.ps1') }
  Push-Location -LiteralPath $e.Raiz
  try { $g = Pf $e @('-Solo', '1', '-Migrado', 'zorba-migrado-xq') } finally { Pop-Location }
  Comprueba 'GB libres con -Migrado en ruta relativa: un numero' ((Valor-De $g 'GB libres') -match '^\d+\.\d$') (Valor-De $g 'GB libres')
}

$Pruebas['14 bloque 6: Maven de los ajustes, mvn del PATH, envoltorio del migrado (mvnw) o ninguno'] = {
  if ($env:OS -eq 'Windows_NT') { return }   # los programas de mentira de esta prueba son scripts de sh
  $fal = Join-Path $falsos 'mvn.ps1'
  $vacia = Join-Path $Dir 'sin-mvn'
  [void](New-Item -ItemType Directory -Path $vacia -Force)
  # b) sin MvnExe, con mvn en el PATH y un mvnw en el migrado que no debe usarse
  $e = Nuevo-Escenario 'maven-path' @{ MvnExe = '' }
  Nuevo-Lanzador (Join-Path $e.Raiz 'bin/mvn') $fal
  Escribe $e.Migrado 'mvnw' "#!/bin/sh`necho '[ERROR] no debia usarse el envoltorio'`nexit 1`n"
  & chmod +x (Get-Ruta $e.Migrado 'mvnw')
  $r = Pf $e (Todos $e @('-Solo', '6')) '' @{ PATH = ((Join-Path $e.Raiz 'bin') + [System.IO.Path]::PathSeparator + $env:PATH) }
  Igual 'b) maven usado: mvn (el del PATH gana al mvnw del migrado)' 'mvn' (Valor-De $r 'maven usado')
  foreach ($p in @('compila y pasa el test', 'jacoco', 'openrewrite')) { Comprueba "b) $p" ((Valor-De $r $p) -match '^si \| \d+ s$') ((Bloque-De $r '6') -join ' / ') }
  # c) sin MvnExe ni mvn en el PATH: el mvnw del migrado, copiado al proyecto de juguete con su carpeta .mvn
  $e2 = Nuevo-Escenario 'maven-envoltorio' @{ MvnExe = '' }
  $w = "#!/bin/sh`n[ -f ./mvnw ] && [ -f ./.mvn/wrapper/maven-wrapper.properties ] || { echo '[ERROR] falta el envoltorio en la carpeta de trabajo'; exit 1; }`nexec '" + $ps + "' -NoProfile -File '" + $fal + "' `"`$@`"`n"
  Escribe $e2.Migrado 'mvnw' $w
  & chmod +x (Get-Ruta $e2.Migrado 'mvnw')
  Escribe $e2.Migrado '.mvn/wrapper/maven-wrapper.properties' "distributionUrl=x`n"
  $r2 = Pf $e2 (Todos $e2 @('-Solo', '1,6')) '' @{ PATH = $vacia }
  Igual 'c) maven usado: envoltorio' 'envoltorio' (Valor-De $r2 'maven usado')
  foreach ($p in @('compila y pasa el test', 'jacoco', 'openrewrite')) { Comprueba "c) $p (con el mvnw y .mvn copiados al juguete)" ((Valor-De $r2 $p) -match '^si \| \d+ s$') ((Bloque-De $r2 '6') -join ' / ') }
  Igual 'c) el bloque 1 mide la version con ese mismo envoltorio' '3.9.8' (Valor-De $r2 'maven')
  Igual 'c) sin fallos' 'ninguno' (Valor-De $r2 'bloques con fallo')
  # d) ni ajustes, ni mvn, ni mvnw
  $e3 = Nuevo-Escenario 'maven-ninguno' @{ MvnExe = '' }
  $r3 = Pf $e3 (Todos $e3 @('-Solo', '1,6')) '' @{ PATH = $vacia }
  Igual 'd) maven usado: ninguno' 'ninguno' (Valor-De $r3 'maven usado')
  Comprueba 'd) el bloque 6 queda saltado con su motivo' (@(Bloque-De $r3 '6' | Where-Object { $_ -match '^saltado: ' }).Count -eq 1) ((Bloque-De $r3 '6') -join ' / ')
  Igual 'd) el bloque 1 dice maven: no disponible' 'no disponible' (Valor-De $r3 'maven')
  Igual 'd) sin fallos' 'ninguno' (Valor-De $r3 'bloques con fallo')
}

$Pruebas['15 bloque 7: git, tests, pom, sftp, config y ficheros locales de cada repo (solo numeros y palabras fijas)'] = {
  $e = Nuevo-Escenario 'forma'
  $leg = $e.Legacy
  $jsch = 'com.jcraft.jsch.JSch'
  $sshd = 'org.apache.sshd.client.SshClient'
  $integ = 'org.springframework.integration.sftp.session.DefaultSftpSessionFactory'
  $sshj = 'net.schmizz.sshj.SSHClient'
  $m = 'src/main/java/com/zorba/legado/'
  $t = 'src/test/java/com/zorba/legado/'
  $pq = 'com.zorba.legado'
  # sftp: jsch 1, sshd 2, spring-integration 3, sshj 4 (el ultimo en un test); config: @Value 3, @ConfigurationProperties 1, getenv 2
  Escribe $leg ($m + 'ZorbaSftpUno.java') (Clase-Con 'ZorbaSftpUno' $pq @($jsch, $sshd, $integ, $sshj, 'java.io.FileReader') @('@Value("${a}") private String a;', 'String e = System.getenv("A");', 'Object r = new FileReader("x");'))
  Escribe $leg ($m + 'ZorbaSftpDos.java') (Clase-Con 'ZorbaSftpDos' $pq @($sshd, $integ, $sshj, 'java.nio.file.Files') @('@ConfigurationProperties("x") private Object p;', 'Object f = Files.readAllBytes(null);'))
  Escribe $leg ($m + 'ZorbaSftpTres.java') (Clase-Con 'ZorbaSftpTres' $pq @($integ, $sshj, 'java.io.FileInputStream') @('@Value("${b}") private String b;', 'Object s = new FileInputStream("x");'))
  Escribe $leg ($t + 'ZorbaSftpPrueba.java') (Clase-Con 'ZorbaSftpPrueba' $pq @($sshj, 'java.io.FileWriter') @('@Value("${c}") private String c;', 'String e = System.getenv("B");', 'Object w = new FileWriter("y");'))
  Escribe $leg ($t + 'ZorbaOtraPrueba.java') (Clase-Con 'ZorbaOtraPrueba' $pq @() @('int a = 1;'))
  # ficheros locales de codigo: uno por cada clase que cuenta (el de FileWriter en un test no cuenta)
  Escribe $leg ($m + 'ZorbaLocalA.java') (Clase-Con 'ZorbaLocalA' $pq @('java.io.File') @('File f = null;'))
  Escribe $leg ($m + 'ZorbaLocalB.java') (Clase-Con 'ZorbaLocalB' $pq @('java.io.FileWriter') @('Object w = null;'))
  Escribe $leg ($m + 'ZorbaLocalC.java') (Clase-Con 'ZorbaLocalC' $pq @('java.io.FileOutputStream') @('Object o = null;'))
  foreach ($f in @('src/main/resources/application.properties', 'src/main/resources/application-dev.yml', 'src/main/resources/application.yaml', 'src/test/resources/application-test.properties', 'zorba-mod2/src/main/resources/application.yml')) { Escribe $leg $f "a: 1`n" }
  foreach ($f in @('src/main/resources/application.json', 'src/main/resources/applicationContext.xml')) { Escribe $leg $f "x`n" }
  Escribe $leg 'pom.xml' (Pom-Con 'zorba-parent-secreto' '9.9.9' '<java.version>${revision}</java.version>')
  # el migrado: un test, spring-boot 3.2.5 y release 21, y la cabeza suelta (no esta en una rama)
  Escribe $e.Migrado 'src/test/java/com/zorba/migrado/ZorbaNuevaPrueba.java' (Clase-Con 'ZorbaNuevaPrueba' 'com.zorba.migrado' @() @('int a = 1;'))
  Escribe $e.Migrado 'pom.xml' (Pom-Con 'spring-boot-starter-parent' '3.2.5' '<maven.compiler.release>21</maven.compiler.release>')
  [void](GitEn $e.Migrado @('checkout', '-q', '--detach'))
  # la referencia: ni pom ni git
  Remove-Item -LiteralPath (Join-Path $e.Plantilla 'pom.xml') -Force
  Remove-Item -LiteralPath (Join-Path $e.Plantilla '.git') -Recurse -Force
  $r = Pf $e (Todos $e @('-Solo', '7', '-SinMaven'))
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'original: repo git' 'si' (Valor-De $r 'original repo git')
  Igual 'original: en una rama' 'si' (Valor-De $r 'original en una rama')
  Igual 'original: tests (.java bajo src/test)' '2 ficheros' (Valor-De $r 'original tests')
  Igual 'original: padre propio sin nombre ni version, y java.version ${revision} es otro' 'java otro | spring-boot ninguno | padre propio' (Valor-De $r 'original pom')
  Igual 'original: sftp, con codigo y test' 'jsch 1 | sshd 2 | spring-integration 3 | sshj 4' (Valor-De $r 'original sftp')
  Igual 'original: config' '@Value 3 | @ConfigurationProperties 1 | getenv 2 | ficheros application 5' (Valor-De $r 'original config')
  Igual 'original: ficheros locales (solo codigo, uno por cada clase de E/S de ficheros)' '6' (Valor-De $r 'original ficheros locales')
  Igual 'migrado: repo git' 'si' (Valor-De $r 'migrado repo git')
  Igual 'migrado: la cabeza suelta no es una rama' 'no' (Valor-De $r 'migrado en una rama')
  Igual 'migrado: tests' '1 ficheros' (Valor-De $r 'migrado tests')
  Igual 'migrado: spring-boot de su padre y java de maven.compiler.release' 'java 21 | spring-boot 3.2.5 | padre spring-boot' (Valor-De $r 'migrado pom')
  Igual 'migrado: sftp' 'jsch 0 | sshd 0 | spring-integration 0 | sshj 0' (Valor-De $r 'migrado sftp')
  Igual 'plantilla: sin git' 'no' (Valor-De $r 'plantilla repo git')
  Comprueba 'plantilla: sin git no hay linea de rama' ((Cuenta-Lineas $r '^plantilla en una rama: ') -eq 0)
  Igual 'plantilla: sin pom' 'sin pom' (Valor-De $r 'plantilla pom')
  Igual 'plantilla: tests' '0 ficheros' (Valor-De $r 'plantilla tests')
  Comprueba 'del padre propio no sale ni el nombre ni la version' (($r.Fichero + $r.Salida) -notmatch 'secreto' -and ($r.Fichero + $r.Salida) -notmatch '9\.9\.9')
  Sin-Fugas $r 'forma'
  Comprueba 'y es ASCII puro' ((Es-Ascii $r.Fichero) -and (Es-Ascii $r.Salida))
}

$Pruebas['16 bloque 7: java y spring-boot del pom (propiedades en orden, versiones con forma de version, pom roto)'] = {
  $e = Nuevo-Escenario 'poms'
  $d = @{}
  foreach ($n in @('a', 'b', 'c', 'd', 'e', 'f')) { $d[$n] = Join-Path $e.Raiz ('pom-' + $n) }
  Escribe $d['a'] 'pom.xml' (Pom-Con 'spring-boot-starter-parent' '${sb.version}' '<maven.compiler.source>1.8</maven.compiler.source>')
  Escribe $d['b'] 'pom.xml' (Pom-Con '' '' '<maven.compiler.source>11</maven.compiler.source><maven.compiler.release>21</maven.compiler.release><java.version>17</java.version>')
  Escribe $d['c'] 'pom.xml' "<project><zorba-secreto></project>`n"
  Escribe $d['d'] 'pom.xml' (Pom-Con '' '' '<maven.compiler.source>11</maven.compiler.source><maven.compiler.release>21</maven.compiler.release>')
  Escribe $d['e'] 'pom.xml' (Pom-Con 'spring-boot-starter-parent' ('1' * 21) '<java.version>v17</java.version>')
  Escribe $d['f'] 'pom.xml' (Pom-Con 'zorba-spring-boot-starter-parent-x' '1.0' ('<java.version>' + ('1' * 22) + '</java.version>'))
  $r = Pf $e @('-Solo', '7', '-SinMaven', '-Legacy', $d['a'], '-Migrado', $d['b'], '-Plantilla', $d['c'])
  Igual 'a) con ${sb.version} y solo maven.compiler.source' 'java 1.8 | spring-boot otro | padre spring-boot' (Valor-De $r 'original pom')
  Igual 'b) java.version gana a maven.compiler.release y este a maven.compiler.source' 'java 17 | spring-boot ninguno | padre ninguno' (Valor-De $r 'migrado pom')
  Igual 'c) un pom que no es XML bueno' 'ilegible' (Valor-De $r 'plantilla pom')
  Sin-Fugas $r 'poms 1'
  $r2 = Pf $e @('-Solo', '7', '-SinMaven', '-Legacy', $d['d'], '-Migrado', $d['e'], '-Plantilla', $d['f'])
  Igual 'd) maven.compiler.release gana a maven.compiler.source' 'java 21 | spring-boot ninguno | padre ninguno' (Valor-De $r2 'original pom')
  Igual 'e) 21 caracteres de version se escriben y java.version v17 es otro' ('java otro | spring-boot ' + ('1' * 21) + ' | padre spring-boot') (Valor-De $r2 'migrado pom')
  Igual 'f) 22 caracteres son otro, y un padre que no se llama exactamente spring-boot-starter-parent es propio' 'java otro | spring-boot ninguno | padre propio' (Valor-De $r2 'plantilla pom')
  Sin-Fugas $r2 'poms 2'
}

$Pruebas['17 filtro: cada regla con un dato que solo ella atrapa'] = {
  # a) repos dentro de una carpeta con espacios: la ruta entera es la etiqueta, sin el nombre de la carpeta
  $e = Nuevo-Escenario 'carpeta zorba con espacio'
  $a = Pf-ErrorMaven $e ($e.Legacy + ' y ' + $e.Migrado + ' y ' + $e.Plantilla)
  Igual 'a) las rutas de los repos salen enteras como <LEGACY>, <MIGRADO> y <PLANTILLA>' '<LEGACY> y <MIGRADO> y <PLANTILLA>' (Valor-De $a 'error')
  Comprueba 'a) y nada del nombre de la carpeta con espacios' (($a.Fichero + $a.Salida) -notmatch 'espacio' -and ($a.Fichero + $a.Salida) -notmatch '(?i)zorba') (Valor-De $a 'error')
  # b) la carpeta personal, con un espacio en el nombre
  $e2 = Nuevo-Escenario 'casa'
  $casa = Join-Path $Dir 'perfil zorba'
  $b = Pf-ErrorMaven $e2 ('No se pudo leer ' + $casa) @{ USERPROFILE = $casa }
  Igual 'b) la carpeta personal sale como <CASA>, sin su nombre' 'No se pudo leer <CASA>' (Valor-De $b 'error')
  # c) nombres sueltos: la carpeta de cada repo y una clase
  $e3 = Nuevo-Escenario 'nombres'
  $c = Pf-ErrorMaven $e3 'zorba-legado-xq y ZorbaCorta y zorba-migrado-xq y zorba-plantilla-xq'
  $vc = Valor-De $c 'error'
  Comprueba 'c) el nombre suelto de la carpeta de un repo sale como etiqueta' ($vc -cmatch '^<LEGACY> y .* y <MIGRADO> y <PLANTILLA>$') $vc
  Comprueba 'c) el nombre suelto de una clase de los repos sale como <clase>' ($vc -cmatch ' y <clase> y ') $vc
  # d) una URL interna, la de Maven Central, tildes y una linea de 560 caracteres
  $e4 = Nuevo-Escenario 'texto'
  $nene = [string][char]0xF1 + [char]0xE9
  $d = Pf-ErrorMaven $e4 ('Fallo en ' + $nene + ' con https://artefactos.interno-zorba.corp/maven/x y https://repo.maven.apache.org/maven2/ ' + ('palabra ' * 70))
  $vd = Valor-De $d 'error'
  Comprueba 'd) una URL interna sale como <url-interna> y la de Maven Central se queda' ($vd.StartsWith('Fallo en ?? con <url-interna> y https://repo.maven.apache.org/maven2/ palabra')) $vd
  Comprueba 'd) las tildes y las enes salen como ? y el fichero es ASCII' ($vd.StartsWith('Fallo en ?? con ') -and (Es-Ascii $d.Fichero)) $vd
  Igual 'd) una linea larga se corta a 200 caracteres' 200 $vd.Length
}

$Pruebas['18 el fichero se guarda al acabar cada bloque: a mitad del lanzamiento ya tiene los anteriores'] = {
  $e = Nuevo-Escenario 'medio'
  $r = Pf $e (Todos $e @('-Solo', '1,4')) '' @{ RESCATE_COPIA_RESULTADO = (Join-Path $Inst 'preflight-resultado.txt') }
  Igual 'sale con 0' 0 $r.Codigo
  $copia = Join-Path $e.Llamadas 'resultado-pf-apt-1.txt'
  Comprueba 'el Copilot de la primera llamada del bloque 4 vio el fichero' (Test-Path -LiteralPath $copia)
  $t = ''
  if (Test-Path -LiteralPath $copia) { $t = [System.IO.File]::ReadAllText($copia) }
  Comprueba 'el fichero ya tenia el bloque 1 entero' ($t -match '(?m)^== 1 entorno' -and $t -match '(?m)^ajustes: ') $t
  Comprueba 'y aun no tenia ni el bloque 4 ni el fin' ($t -notmatch '(?m)^== 4 ' -and $t -notmatch '(?m)^== fin') $t
  Comprueba 'y al acabar si tiene los dos bloques y el fin' ((Cuenta-Lineas $r '^== 1 ') -eq 1 -and (Cuenta-Lineas $r '^== 4 ') -eq 1 -and (Lineas-De $r) -contains '== fin')
}

$Pruebas['19 bloques 7 y 8: si fallan, solo el tipo del fallo y el sitio, sin su mensaje'] = {
  $e = Nuevo-Escenario 'sinmensaje'
  # el Copilot del bloque 4 borra el original: los bloques 7 y 8 no lo encuentran y su fallo lleva la ruta en el mensaje
  $r = Pf $e (Todos $e @('-Solo', '4,7,8')) 'borra-carpeta:^ValidadorImporte$' @{ RESCATE_BORRAR = $e.Legacy }
  Igual 'sale con 0' 0 $r.Codigo
  Comprueba 'fallan el 7 y el 8' ((Valor-De $r 'bloques con fallo') -ceq '7 8') (Valor-De $r 'bloques con fallo')
  foreach ($n in @('7', '8')) {
    $f = @(Bloque-De $r $n | Where-Object { $_ -match '^fallo: ' })
    Comprueba "bloque ${n}: una linea fallo: con solo el tipo y el fichero:linea" ($f.Count -eq 1 -and $f[0] -cmatch '^fallo: \w+ \(\w+\.ps1:\d+\)$') ($f -join ' / ')
  }
  Comprueba 'ni el texto del fallo ni la ruta salen' (($r.Fichero + $r.Salida) -notmatch 'No existe' -and ($r.Fichero + $r.Salida) -notmatch '<LEGACY>')
  Sin-Fugas $r 'sin mensaje'
}

# ================================ LANZADOR ================================
Invoke-Banco $Pruebas $Script
