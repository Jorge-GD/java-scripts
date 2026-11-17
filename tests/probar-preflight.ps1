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

$Pruebas['1 completo: nueve bloques con los tres repos y los falsos, sin fallos'] = {
  $r = Get-Completo
  $e = $script:E1
  Igual 'sale con 0' 0 $r.Codigo
  Comprueba 'deja preflight-resultado.txt' (Test-Path -LiteralPath $r.Ruta) (Cola $r.Salida)
  $l = Lineas-De $r
  Comprueba 'la primera linea es PREFLIGHT java-scripts y el commit (o sin-git)' ($l.Count -gt 0 -and $l[0] -match '^PREFLIGHT java-scripts (sin-git|[0-9a-f]{4,40})$') $l[0]
  foreach ($n in 1..9) { Comprueba "tiene el bloque $n" ((Cuenta-Lineas $r ("^== $n ")) -gt 0) }
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
  Comprueba 'y cada bloque acaba con hecho' ((@($r.Salida -split "\r?\n" | Where-Object { $_ -eq 'hecho' }).Count) -eq 9) (Cola $r.Salida)

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
  Comprueba '2: probar.ps1 pasa todas sus comprobaciones (N de N en S s, 75 o mas)' ((Valor-De $r 'probar') -match '^(\d+) de \1 en \d+ s$' -and [int]$Matches[1] -ge 75) (Valor-De $r 'probar')
  Comprueba '2: probar-migracion.ps1 pasa todas sus comprobaciones (232 o mas)' ((Valor-De $r 'probar-migracion') -match '^(\d+) de \1 en \d+ s$' -and [int]$Matches[1] -ge 232) (Valor-De $r 'probar-migracion')
  Igual '2: fallan' 'ninguna' (Valor-De $r 'fallan')

  # 3 copilot
  $b3 = @(Bloque-De $r '3')
  foreach ($f in @('-p', '-s', '--allow-all-tools', '--no-ask-user', '--deny-tool', '--model', '--effort', '--reasoning-effort', '--add-dir', '--no-custom-instructions', '--available-tools', '--max-ai-credits', '--usage-output-file')) {
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

  # 9 examen de modelos: sin -Modelos no hace nada
  Igual '9: sin -Modelos' 'sin -Modelos' (@(Bloque-De $r '9') -join ' / ')

  # las llamadas que hizo el falso (el preflight borra sus carpetas)
  $ll = @(Llamadas $e.Llamadas)
  Igual '14 llamadas al modelo: 5 de aptitud, 4 en paralelo y 5 de clases reales (y ninguna del examen)' 14 $ll.Count
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
  Igual 'las otras 12 dicen si' 12 (Cuenta-Lineas $r '^bandera \S+: si$')
  Igual 'una sola dice no' 1 (Cuenta-Lineas $r '^bandera \S+: no$')
  $r2 = Pf $e (Todos $e @('-Solo', '3')) 'rechaza-bandera:-p'
  Igual 'con -p rechazada: -p dice no' 'no' (Valor-De $r2 'bandera -p')
  Igual 'y las otras 12 si' 12 (Cuenta-Lineas $r2 '^bandera \S+: si$')
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

# ====================== EXAMEN DE MODELOS (bloque 9) ======================
$MA = 'gpt-6-luna'
$MB = 'claude-haiku-5.5'
# Claves pequenas (en el repo van las de verdad) para contar a mano lo que trae cada ficha, y los datos que las aciertan todas.
$ClavesPeque = '{"L1":[{"tipo":"regla","desde":151,"hasta":154,"nota":"a"},{"tipo":"regla","desde":155,"hasta":158,"nota":"b"},{"tipo":"tabla-lee","desde":33,"hasta":34,"nota":"c"}],"L2":[{"tipo":"regla","desde":108,"hasta":111,"nota":"d"},{"tipo":"regla","desde":113,"hasta":116,"nota":"e"},{"tipo":"tabla-lee","desde":194,"hasta":194,"nota":"f"}]}'
$DatosPeque = 'L1=152:regla,156:regla,33:tabla-lee;L2=109:regla,114:regla,194:tabla-lee'

function Pon-Claves([string]$Json) {
  Nueva-Instalacion
  Escribe $Inst 'preflight/examen/claves.json' $Json
}

function Restaura-Claves {
  Nueva-Instalacion
  Copy-Item -LiteralPath (Join-Path $origen 'preflight/examen/claves.json') -Destination (Join-Path $Inst 'preflight/examen/claves.json') -Force
}

# Un escenario para el examen: la clase de L2 cabe en un trozo salvo que se pida otra cosa.
function Nuevo-Examen([string]$Nombre, [hashtable]$Ajustes = @{}) {
  $a = @{ LineasPorTarea = 300 }
  foreach ($k in $Ajustes.Keys) { $a[$k] = $Ajustes[$k] }
  return (Nuevo-Escenario $Nombre $a)
}

# El bloque 9 con esos modelos y esfuerzos (separados por comas).
function Pf-Examen($E, [string]$Modelos, [string]$Esfuerzos = '', [string]$Guion = '', $Extra = @{}, [string[]]$Mas = @()) {
  $a = @('-Solo', '9', '-Modelos', $Modelos)
  if ($Esfuerzos) { $a += @('-Esfuerzos', $Esfuerzos) }
  return (Pf $E (Todos $E ($a + $Mas)) $Guion $Extra)
}

function Examen-De($R) { return @(Bloque-De $R '9') }

# Las lineas de una combinacion: desde su cabecera hasta la siguiente cabecera, los campos de uso o la recomendacion.
function Combinacion-De($R, [string]$Modelo, [string]$Esfuerzo) {
  $res = @()
  $dentro = $false
  foreach ($l in (Examen-De $R)) {
    if ($l -match '^(modelo .+ \| esfuerzo .+|campos de uso: .*|recomendado: .*)$') { $dentro = ($l -ceq "modelo $Modelo | esfuerzo $Esfuerzo") }
    if ($dentro) { $res += $l }
  }
  return $res
}

function Linea-Con($Lineas, [string]$Prefijo) {
  foreach ($l in $Lineas) { if ($l.StartsWith($Prefijo)) { return $l } }
  return ''
}

# Los rangos de lineas en que el sistema trocea GestorRecibos.java con ese tamano.
function Trozos-De([int]$Por) {
  $n = @([System.IO.File]::ReadAllLines((Join-Path $origen 'preflight/examen/GestorRecibos.java'))).Count
  $res = @()
  for ($d = 1; $d -le $n; $d += $Por) { $res += ("$d-" + [math]::Min($n, $d + $Por - 1)) }
  return $res
}

$Pruebas['20 bloque 9 sin -Modelos: sin -Modelos y ninguna llamada; los bloques 4, 5 y 8 usan el primer modelo de la lista'] = {
  $e = Nuevo-Examen 'examen-sin'
  $r = Pf $e (Todos $e @('-Solo', '9'))
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'el bloque 9 dice sin -Modelos y nada mas' 'sin -Modelos' ((Examen-De $r) -join ' / ')
  Igual 'ninguna llamada' 0 @(Llamadas $e.Llamadas).Count
  Comprueba 'la consola no anuncia llamadas' ($r.Salida -notmatch 'llamadas, hasta')
  $s = Pf $e (Todos $e @('-Solo', '9', '-SinCopilot', '-Modelos', "$MA,$MB"))
  Igual '-SinCopilot: el bloque 9 queda saltado' 'saltado: -SinCopilot' ((Examen-De $s) -join ' / ')
  Igual '-SinCopilot: ninguna llamada' 0 @(Llamadas $e.Llamadas).Count
  # sin -Modelo el bloque 4 usa el primero de -Modelos; con -Modelo manda este
  $m = Pf $e (Todos $e @('-Solo', '4', '-Modelos', "$MA,$MB"))
  Igual 'sin -Modelo: el bloque 4 usa el primer modelo de -Modelos' $MA (Valor-De $m 'modelo')
  $ll = @(Llamadas $e.Llamadas)
  Comprueba '... y sus 5 llamadas llevan --model=ese' ($ll.Count -eq 5 -and @($ll | Where-Object { $_.flags -match ('--model=' + [regex]::Escape($MA) + '( |$)') }).Count -eq 5) (($ll | ForEach-Object { $_.flags }) -join ' | ')
  $m2 = Pf $e (Todos $e @('-Solo', '4', '-Modelo', 'modelo-x', '-Modelos', "$MA,$MB"))
  Igual 'con -Modelo manda -Modelo' 'modelo-x' (Valor-De $m2 'modelo')
}

$Pruebas['21 bloque 9, dos modelos y dos esfuerzos: las llamadas justas, en serie y con el modelo y el esfuerzo de cada una'] = {
  $e = Nuevo-Examen 'examen-dos' @{ LineasPorTarea = 100 }
  $rangos = @(Trozos-De 100)
  $t = $rangos.Count
  $r = Pf-Examen $e "$MA,$MB" 'medium,max'
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'sin bloques con fallo' 'ninguno' (Valor-De $r 'bloques con fallo')
  $ll = @(Llamadas $e.Llamadas)
  $por = 1 + $t + 2
  Igual "4 combinaciones de $por llamadas (L1, $t trozos de L2, E1 y E2)" (4 * $por) $ll.Count
  $esperadas = @()
  foreach ($m in @($MA, $MB)) {
    foreach ($f in @('medium', 'max')) {
      $esperadas += "${m}:${f}:L1"
      for ($i = 1; $i -le $t; $i++) { $esperadas += "${m}:${f}:L2-$i" }
      $esperadas += "${m}:${f}:E1"
      $esperadas += "${m}:${f}:E2"
    }
  }
  Igual 'en este orden, cada una con la clave modelo:esfuerzo:prueba que toca' ($esperadas -join ' ') ((@($ll | ForEach-Object { $_.clave })) -join ' ')
  Igual 'nunca dos a la vez' 1 (Max-Simultaneas $ll)
  $mal = @($ll | Where-Object { $p = $_.clave -split ':'; -not ($_.flags -match ('--model=' + [regex]::Escape($p[0]) + '( |$)') -and $_.flags -match ('--effort=' + $p[1] + '( |$)')) })
  Comprueba 'cada llamada lleva --model y --effort de su clave' ($mal.Count -eq 0) (($mal | ForEach-Object { $_.clave + ' ' + $_.flags }) -join ' | ')
  Comprueba 'y la bandera de uso (la sonda dice que existe)' (@($ll | Where-Object { $_.uso -eq 'si' }).Count -eq $ll.Count)
  $l2 = @($ll | Where-Object { $_.clave -like "${MA}:medium:L2-*" } | ForEach-Object { $_.lineas })
  Igual "L2 se trocea como el sistema, de 100 en 100 lineas ($t trozos)" ($rangos -join ' ') ($l2 -join ' ')
  $l1 = @($ll | Where-Object { $_.clave -eq "${MA}:medium:L1" })
  Comprueba 'L1 es una sola llamada con la clase entera' ($l1.Count -eq 1 -and $l1[0].lineas -match '^1-\d+$') ($l1 | ForEach-Object { $_.lineas })
  $b = Examen-De $r
  Igual 'la primera linea es la bandera de uso' 'bandera de uso: si' $b[0]
  Igual 'cuatro cabeceras de combinacion' 4 (@($b | Where-Object { $_ -match '^modelo \S+ \| esfuerzo \w+$' }).Count)
  Igual 'campos de uso, una sola vez y con los nombres de las hojas' 'campos de uso: inputTokens, outputTokens, cacheReadTokens, reasoningTokens' (Linea-Con $b 'campos de uso: ')
  Igual '... y una sola linea de campos de uso' 1 (@($b | Where-Object { $_ -match '^campos de uso: ' }).Count)
  $x = @(Combinacion-De $r $MA 'medium')
  Comprueba 'L1: json, citas, clave, segundos y creditos' ((Linea-Con $x 'L1: ') -match '^L1: json si \| citas 2 de 2 \| clave \d+ de 12 \| \d+ s \| creditos 1,000$') (Linea-Con $x 'L1: ')
  $citas = 2 * $t
  Comprueba "L2: los $t trozos sumados" ((Linea-Con $x 'L2: ') -match ('^L2: json si \| citas ' + $citas + ' de ' + $citas + ' \| clave \d+ de 24 \| \d+ s \| creditos ' + $t + ',000$')) (Linea-Con $x 'L2: ')
  Comprueba 'E1: pasa si, segundos y creditos' ((Linea-Con $x 'E1: ') -match '^E1: pasa si \| \d+ s \| creditos 1,000$') (Linea-Con $x 'E1: ')
  Comprueba 'E2: pasa si, segundos y creditos' ((Linea-Con $x 'E2: ') -match '^E2: pasa si \| \d+ s \| creditos 1,000$') (Linea-Con $x 'E2: ')
  $creditos = ($t + 3).ToString() + ',000'
  $entrada = 1000 * ($t + 3)
  $salida = 100 * ($t + 3)
  Comprueba 'total: clave de 36, arreglos 2 de 2, segundos, creditos y tokens' ((Linea-Con $x 'total: ') -match ('^total: clave \d+ de 36 \| arreglos 2 de 2 \| \d+ s \| creditos ' + $creditos + ' \| tokens entrada ' + $entrada + ' salida ' + $salida + '$')) (Linea-Con $x 'total: ')
  Comprueba 'las cuatro combinaciones llevan su total' (@($b | Where-Object { $_ -match '^total: ' }).Count -eq 4)
  # los datos por defecto del falso no aciertan la clave: ninguna cumple
  Igual 'ninguna cumple' 'recomendado: ninguno cumple' (Linea-Con $b 'recomendado: ')
  Comprueba 'y dice la mejor' ((Linea-Con $b 'la mejor: ') -match ('^la mejor: ' + [regex]::Escape($MA) + ' con esfuerzo \w+ \(clave \d+ de 36, arreglos 2 de 2\)$')) (Linea-Con $b 'la mejor: ')
  Igual 'todo con uno: no' 'todo con uno: no' (Linea-Con $b 'todo con uno: ')
  $llamadas = 4 * $por
  $min = 2 * $llamadas
  Comprueba 'la consola cuenta las llamadas y los minutos' ($r.Salida -match ('(?m)^' + $llamadas + ' llamadas, hasta ' + $min + ' min\s*$') -and $r.Salida -match ('== 9 examen de modelos \(hasta ' + $min + ' min\)\.\.\.')) (Cola $r.Salida)
  Sin-Fugas $r 'examen dos'
}

$Pruebas['22 bloque 9, clave: cuenta los datos esperados con cita probada, tipo equivalente y linea cerca; uno por dato'] = {
  $e = Nuevo-Examen 'examen-clave'
  try {
    # a) 5 de 6: el sexto dato lleva la cita inventada y no cuenta
    $kA = '{"L1":[{"tipo":"regla","desde":151,"hasta":154,"nota":"a"},{"tipo":"regla","desde":155,"hasta":158,"nota":"b"},{"tipo":"regla","desde":131,"hasta":133,"nota":"c"},{"tipo":"tabla-lee","desde":33,"hasta":34,"nota":"d"},{"tipo":"tabla-escribe","desde":90,"hasta":91,"nota":"e"},{"tipo":"salida-fichero","desde":74,"hasta":75,"nota":"f"}],"L2":[{"tipo":"regla","desde":108,"hasta":111,"nota":"g"},{"tipo":"regla","desde":113,"hasta":116,"nota":"h"}]}'
    Pon-Claves $kA
    $a = Pf-Examen $e $MA 'medium' '' @{ RESCATE_EXAMEN_DATOS = 'L1=152:regla,156:regla,132:regla,33:tabla-lee,90:tabla-escribe,-75:salida-fichero;L2=109:regla,114:regla' } @('-SinMaven')
    $xa = @(Combinacion-De $a $MA 'medium')
    Comprueba 'a) L1: trae 6 datos, 5 con cita probada y acierta 5 de 6' ((Linea-Con $xa 'L1: ') -match '^L1: json si \| citas 5 de 6 \| clave 5 de 6 \|') (Linea-Con $xa 'L1: ')
    Comprueba 'a) L2: 2 de 2' ((Linea-Con $xa 'L2: ') -match '^L2: json si \| citas 2 de 2 \| clave 2 de 2 \|') (Linea-Con $xa 'L2: ')
    Comprueba 'a) total: clave 7 de 8' ((Linea-Con $xa 'total: ') -match '^total: clave 7 de 8 \|') (Linea-Con $xa 'total: ')
    Sin-Fugas $a 'clave a'
    # b) tipo distinto, linea a mas de CitaCerca (3), en el limite, y regla = error
    $kB = '{"L1":[{"tipo":"tabla-escribe","desde":184,"hasta":184,"nota":"a"},{"tipo":"tabla-lee","desde":33,"hasta":34,"nota":"b"},{"tipo":"tabla-lee","desde":139,"hasta":139,"nota":"c"},{"tipo":"tabla-escribe","desde":90,"hasta":91,"nota":"d"},{"tipo":"regla","desde":151,"hasta":154,"nota":"e"}],"L2":[{"tipo":"regla","desde":108,"hasta":111,"nota":"f"}]}'
    Pon-Claves $kB
    # 187 es hasta+3 (cuenta), 87 es desde-3 (cuenta), 142 es hasta+3 (cuenta), 29 es desde-4 (no) y el 34 con otro tipo (no); 152 como error vale por una regla
    $b = Pf-Examen $e $MA 'medium' '' @{ RESCATE_EXAMEN_DATOS = 'L1=187:tabla-escribe,29:tabla-lee,34:tabla-escribe,142:tabla-lee,87:tabla-escribe,152:error;L2=109:regla' } @('-SinMaven')
    $xb = @(Combinacion-De $b $MA 'medium')
    Comprueba 'b) L1: acierta 4 de 5 (a 3 lineas vale, a 4 no, otro tipo no, error vale por regla)' ((Linea-Con $xb 'L1: ') -match '^L1: json si \| citas 6 de 6 \| clave 4 de 5 \|') (Linea-Con $xb 'L1: ')
    # c) un dato vale para una sola condicion, y se reparten bien: el 153 vale para las dos reglas y el 150 solo para la primera
    $kC = '{"L1":[{"tipo":"regla","desde":151,"hasta":154,"nota":"a"},{"tipo":"regla","desde":155,"hasta":158,"nota":"b"}],"L2":[{"tipo":"regla","desde":108,"hasta":111,"nota":"c"}]}'
    Pon-Claves $kC
    $c = Pf-Examen $e $MA 'medium' '' @{ RESCATE_EXAMEN_DATOS = 'L1=153:regla,150:regla;L2=109:regla,110:regla' } @('-SinMaven')
    $xc = @(Combinacion-De $c $MA 'medium')
    Comprueba 'c) L1: el reparto bueno acierta las 2 (153 para la segunda y 150 para la primera)' ((Linea-Con $xc 'L1: ') -match '^L1: json si \| citas 2 de 2 \| clave 2 de 2 \|') (Linea-Con $xc 'L1: ')
    Comprueba 'c) L2: dos datos para una sola condicion cuentan 1 de 1' ((Linea-Con $xc 'L2: ') -match '^L2: json si \| citas 2 de 2 \| clave 1 de 1 \|') (Linea-Con $xc 'L2: ')
  }
  finally { Restaura-Claves }
}

$Pruebas['23 bloque 9, E1 (dos errores de compilacion): pasa o el motivo, del vocabulario cerrado'] = {
  $e = Nuevo-Examen 'examen-e1' @{ SegundosPorLlamada = 10 }
  # tres esfuerzos = tres combinaciones: el falso arregla, deja un NO_COMPILA o toca un test
  $a = Pf-Examen $e $MA 'low,medium,high' 'exa-e1-no-compila:medium:E1$;exa-e1-toca-test:high:E1$'
  Igual 'a) sale con 0' 0 $a.Codigo
  Igual 'a) low: el falso arregla y pasa' 'E1: pasa si' ((Linea-Con (Combinacion-De $a $MA 'low') 'E1: ') -replace ' \|.*$', '')
  Igual 'a) medium: no compila' 'E1: pasa no (no compila)' ((Linea-Con (Combinacion-De $a $MA 'medium') 'E1: ') -replace ' \|.*$', '')
  Igual 'a) high: toca un test' 'E1: pasa no (toco tests)' ((Linea-Con (Combinacion-De $a $MA 'high') 'E1: ') -replace ' \|.*$', '')
  Comprueba 'a) la linea de E1 con fallo sigue llevando segundos y creditos' ((Linea-Con (Combinacion-De $a $MA 'medium') 'E1: ') -match '^E1: pasa no \(no compila\) \| \d+ s \| creditos 1,000$') (Linea-Con (Combinacion-De $a $MA 'medium') 'E1: ')
  Comprueba 'a) el total cuenta los arreglos que pasan (E1 y E2): 2 de 2, 1 de 2 y 1 de 2' ((Linea-Con (Combinacion-De $a $MA 'low') 'total: ') -match '\| arreglos 2 de 2 \|' -and (Linea-Con (Combinacion-De $a $MA 'medium') 'total: ') -match '\| arreglos 1 de 2 \|' -and (Linea-Con (Combinacion-De $a $MA 'high') 'total: ') -match '\| arreglos 1 de 2 \|')
  Sin-Fugas $a 'e1 a'
  # el resto del vocabulario: test que falla, toca el pom, sin cambios, fallo de Copilot y tiempo agotado
  $guion = 'exa-e1-test-falla:low:E1$;exa-e1-toca-pom:medium:E1$;exa-e1-nada:high:E1$;exa-error-privado:xhigh:E1$;exa-espera-14:max:E1$'
  $b = Pf-Examen $e $MA 'low,medium,high,xhigh,max' $guion @{ RESCATE_ERROR_TEXTO = 'Error: sin sesion de zorbalex en PCZORBA' }
  $motivos = [ordered]@{ low = 'test falla'; medium = 'toco fuera de src/main'; high = 'sin cambios'; xhigh = 'fallo de copilot'; max = 'tiempo' }
  foreach ($k in $motivos.Keys) {
    Igual "b) $k" ('E1: pasa no (' + $motivos[$k] + ')') ((Linea-Con (Combinacion-De $b $MA $k) 'E1: ') -replace ' \|.*$', '')
  }
  Sin-Fugas $b 'e1 b'
}

$Pruebas['24 bloque 9, E2 (Javadoc sin tocar codigo): pasa o el motivo, del vocabulario cerrado'] = {
  $e = Nuevo-Examen 'examen-e2'
  $a = Pf-Examen $e $MA 'low,medium,high,xhigh' 'exa-e2-codigo:medium:E2$;exa-e2-falta:high:E2$;exa-e2-nada:xhigh:E2$'
  Igual 'sale con 0' 0 $a.Codigo
  Igual 'low: Javadoc bien' 'E2: pasa si' ((Linea-Con (Combinacion-De $a $MA 'low') 'E2: ') -replace ' \|.*$', '')
  Igual 'medium: cambia una linea de codigo' 'E2: pasa no (cambio codigo)' ((Linea-Con (Combinacion-De $a $MA 'medium') 'E2: ') -replace ' \|.*$', '')
  Igual 'high: falta el Javadoc de un metodo' 'E2: pasa no (sin javadoc)' ((Linea-Con (Combinacion-De $a $MA 'high') 'E2: ') -replace ' \|.*$', '')
  Igual 'xhigh: no cambia nada' 'E2: pasa no (sin cambios)' ((Linea-Con (Combinacion-De $a $MA 'xhigh') 'E2: ') -replace ' \|.*$', '')
  Comprueba 'las pruebas E1 de las cuatro pasan' (@(Examen-De $a | Where-Object { $_ -match '^E1: pasa si \|' }).Count -eq 4)
  Sin-Fugas $a 'e2'
}

$Pruebas['25 bloque 9, gasto: creditos y tokens del fichero de uso; sin fichero, desconocido; sin bandera, la llamada no la lleva'] = {
  $e = Nuevo-Examen 'examen-gasto'
  try {
    Pon-Claves $ClavesPeque
    $d = @{ RESCATE_EXAMEN_DATOS = $DatosPeque }
    # a) valores conocidos
    $d['RESCATE_EXAMEN_USO'] = 'L1$=412000000,1000,100;L2=655000000,2000,200;E1$=1204000000,3000,300;E2$=980000000,4000,400'
    $a = Pf-Examen $e $MA 'medium' '' $d
    $xa = @(Combinacion-De $a $MA 'medium')
    Comprueba 'a) L1 con 0,412 creditos' ((Linea-Con $xa 'L1: ') -match '\| creditos 0,412$') (Linea-Con $xa 'L1: ')
    Comprueba 'a) L2 con 0,655' ((Linea-Con $xa 'L2: ') -match '\| creditos 0,655$') (Linea-Con $xa 'L2: ')
    Comprueba 'a) E1 con 1,204' ((Linea-Con $xa 'E1: ') -match '\| creditos 1,204$') (Linea-Con $xa 'E1: ')
    Comprueba 'a) E2 con 0,980' ((Linea-Con $xa 'E2: ') -match '\| creditos 0,980$') (Linea-Con $xa 'E2: ')
    Comprueba 'a) el total suma creditos (3,251) y tokens (entrada 10000, salida 1000)' ((Linea-Con $xa 'total: ') -match '\| creditos 3,251 \| tokens entrada 10000 salida 1000$') (Linea-Con $xa 'total: ')
    Igual 'a) campos de uso: solo las hojas de modelMetrics, con nombres' 'campos de uso: inputTokens, outputTokens, cacheReadTokens, reasoningTokens' (Linea-Con (Examen-De $a) 'campos de uso: ')
    Igual 'a) ninguna llamada pierde el fichero de uso: todas llevan la bandera' 4 @(Llamadas $e.Llamadas | Where-Object { $_.uso -eq 'si' }).Count
    # b) sin fichero de uso y c) con un fichero que no es JSON: desconocido, nunca 0
    foreach ($caso in @(@('b) sin fichero', '-'), @('c) fichero ilegible', 'basura'))) {
      $d['RESCATE_EXAMEN_USO'] = '.=' + $caso[1]
      $r = Pf-Examen $e $MA 'medium' '' $d
      $x = @(Combinacion-De $r $MA 'medium')
      foreach ($p in @('L1', 'L2', 'E1', 'E2')) { Comprueba ($caso[0] + ': ' + $p + ' con creditos desconocido') ((Linea-Con $x ($p + ': ')) -match '\| creditos desconocido$') (Linea-Con $x ($p + ': ')) }
      Comprueba ($caso[0] + ': el total dice desconocido, no 0') ((Linea-Con $x 'total: ') -match '\| creditos desconocido \| tokens desconocido$') (Linea-Con $x 'total: ')
      Igual ($caso[0] + ': campos de uso ninguno') 'campos de uso: ninguno' (Linea-Con (Examen-De $r) 'campos de uso: ')
      Comprueba ($caso[0] + ': el bloque no suma ceros') (-not ((Examen-De $r) -join "`n").Contains('creditos 0,000')) ((Examen-De $r) -join ' / ')
    }
    # d) la bandera no existe: la llamada no la lleva y no hay creditos
    $d['RESCATE_EXAMEN_USO'] = ''
    $s = Pf-Examen $e $MA 'medium' 'rechaza-bandera:--usage-output-file' $d
    Igual 'd) bandera de uso: no' 'bandera de uso: no' ((Examen-De $s)[0])
    $ll = @(Llamadas $e.Llamadas)
    Comprueba 'd) las 4 llamadas se hacen y ninguna lleva la bandera' ($ll.Count -eq 4 -and @($ll | Where-Object { $_.uso -eq 'no' }).Count -eq 4) (($ll | ForEach-Object { $_.uso }) -join ' ')
    Comprueba 'd) y los creditos salen desconocidos' ((Linea-Con (Combinacion-De $s $MA 'medium') 'total: ') -match '\| creditos desconocido \|')
  }
  finally { Restaura-Claves }
  # e) el lector de comun.ps1 con ficheros a mano
  $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $origen 'comun.ps1'), [ref]$null, [ref]$null)
  $fu = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | Where-Object { $_.Name -eq 'Read-Uso' })
  Comprueba 'e) comun.ps1 define Read-Uso' ($fu.Count -eq 1)
  if ($fu.Count -eq 1) {
    . ([scriptblock]::Create($fu[0].Extent.Text))
    $car = Join-Path $Dir 'uso-lector'
    [void](New-Item -ItemType Directory -Path $car -Force)
    $lleno = '{"totalPremiumRequestCost":2.5,"totalUserRequests":1,"totalNanoAiu":3251000000,"totalApiDurationMs":4567,"modelMetrics":{"gpt-6-luna":{"usage":{"inputTokens":1000,"OutputTokens":200,"cacheReadTokens":30,"reasoningTokens":4},"requests":{"count":3}},"otro":{"inputTokens":10,"cacheWriteTokens":5,"outputTokens":"mucho","reasoningOutputTokens":2}},"lastCallInputTokens":99,"lastCallOutputTokens":98}'
    Escribe $car 'lleno.json' $lleno
    $u = Read-Uso (Join-Path $car 'lleno.json')
    Igual 'e) creditos = totalNanoAiu / 1e9' 3.251 ([double]$u.Creditos)
    Igual 'e) NanoAiu' 3251000000 ([long]$u.NanoAiu)
    Igual 'e) Premium' 2.5 ([double]$u.Premium)
    Igual 'e) MsApi' 4567 ([long]$u.MsApi)
    Igual 'e) tokens de entrada: input.*tokens dentro de modelMetrics, de todos los modelos y sin distinguir mayusculas' 1010 ([long]$u.TokensEntrada)
    Igual 'e) tokens de salida (un valor que no es numero no cuenta y OutputTokens si)' 200 ([long]$u.TokensSalida)
    Igual 'e) tokens de cache (cacheRead y cacheWrite)' 35 ([long]$u.TokensCache)
    Igual 'e) tokens de razonamiento (reasoningTokens y reasoningOutputTokens, sin contarlos tambien como salida)' 6 ([long]$u.TokensRazonamiento)
    Comprueba 'e) las hojas de fuera de modelMetrics (lastCall...) no cuentan: la entrada no es 1109' ([long]$u.TokensEntrada -ne 1109)
    $esperados = @('OutputTokens', 'cacheReadTokens', 'cacheWriteTokens', 'count', 'inputTokens', 'reasoningOutputTokens', 'reasoningTokens')
    Comprueba 'e) los campos son los nombres de las hojas numericas de modelMetrics, cada uno una vez' (@($u.Campos).Count -eq $esperados.Count -and @($u.Campos | Where-Object { $esperados -ccontains $_ }).Count -eq $esperados.Count) ((@($u.Campos) -join ','))
    $u2 = Read-Uso (Join-Path $car 'no-existe.json')
    Comprueba 'e) sin fichero: todo null' ($null -eq $u2.Creditos -and $null -eq $u2.NanoAiu -and $null -eq $u2.Premium -and $null -eq $u2.MsApi -and $null -eq $u2.TokensEntrada -and $null -eq $u2.TokensSalida -and $null -eq $u2.TokensCache -and $null -eq $u2.TokensRazonamiento)
    Escribe $car 'roto.json' '{"totalNanoAiu": 12, '
    $u3 = Read-Uso (Join-Path $car 'roto.json')
    Comprueba 'e) JSON ilegible: todo null' ($null -eq $u3.Creditos -and $null -eq $u3.NanoAiu -and $null -eq $u3.TokensEntrada)
    Escribe $car 'vacio.json' '{"totalPremiumRequestCost":0,"totalUserRequests":0,"totalNanoAiu":0,"totalApiDurationMs":0,"modelMetrics":{},"agentMetrics":{},"lastCallInputTokens":0}'
    $u4 = Read-Uso (Join-Path $car 'vacio.json')
    Comprueba 'e) la cuota agotada: 0 creditos de verdad, y tokens sin dato (null) porque no hay hojas' ($u4.Creditos -eq 0 -and $null -ne $u4.Creditos -and $null -eq $u4.TokensEntrada -and $null -eq $u4.TokensSalida)
    Escribe $car 'sin-total.json' '{"modelMetrics":{"m":{"inputTokens":5}}}'
    $u5 = Read-Uso (Join-Path $car 'sin-total.json')
    Comprueba 'e) sin totalNanoAiu: creditos null (no 0) pero los tokens salen' ($null -eq $u5.Creditos -and [long]$u5.TokensEntrada -eq 5)
  }
}

$Pruebas['26 bloque 9, recomendacion: regla fija (menos creditos, si no menos segundos, y solo entre las que cumplen)'] = {
  $ast = [System.Management.Automation.Language.Parser]::ParseFile($Script, [ref]$null, [ref]$null)
  $todas = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
  foreach ($nombre in @('Format-Creditos', 'Test-Cumple', 'Get-Recomendacion')) {
    $f = @($todas | Where-Object { $_.Name -eq $nombre })
    Comprueba "preflight.ps1 define $nombre" ($f.Count -eq 1)
    if ($f.Count -eq 1) { . ([scriptblock]::Create($f[0].Extent.Text)) }
  }
  if (@($todas | Where-Object { $_.Name -eq 'Get-Recomendacion' }).Count -eq 1) {
    # modelo, esfuerzo, clave X de Y, citas X de Y, arreglos X de Y, creditos, segundos, lectura valida
    function Combo([string]$M, [string]$E, [int]$Cl, [int]$ClDe, [int]$Ci, [int]$CiDe, [int]$Ar, [int]$ArDe, $Cred, [int]$Seg, [bool]$Lec = $true) {
      return [pscustomobject]@{ Modelo = $M; Esfuerzo = $E; LecturaValida = $Lec; Clave = $Cl; ClaveTotal = $ClDe; Citas = $Ci; Datos = $CiDe; Arreglos = $Ar; Intentados = $ArDe; Creditos = $Cred; Segundos = $Seg }
    }
    $buena = @(36, 36, 20, 20, 2, 2)
    # 1) dos cumplen: la de menos creditos
    $a = Combo 'A' 'medium' 36 36 20 20 2 2 3.251 100
    $b = Combo 'B' 'max' 36 36 20 20 2 2 5.870 50
    $l = @(Get-Recomendacion @($b, $a))
    Igual '1) dos cumplen: la de menos creditos, aunque sea mas lenta' 'recomendado: A con esfuerzo medium | motivo: cumple y es la mas barata (3,251 creditos; la siguiente, 5,870) | todo con uno: si' ($l -join ' | ')
    # 2) sin creditos: la mas rapida
    $a = Combo 'A' 'medium' 36 36 20 20 2 2 $null 100
    $b = Combo 'B' 'medium' 36 36 20 20 2 2 $null 50
    $l = @(Get-Recomendacion @($a, $b))
    Igual '2) sin creditos: la mas rapida' 'recomendado: B con esfuerzo medium | motivo: cumple y es la mas rapida (sin dato de creditos) | todo con uno: si' ($l -join ' | ')
    # 2b) a una le falta el dato: no se pueden comparar creditos
    $a = Combo 'A' 'medium' 36 36 20 20 2 2 1.0 100
    $b = Combo 'B' 'medium' 36 36 20 20 2 2 $null 50
    $l = @(Get-Recomendacion @($a, $b))
    Igual '2b) a una le falta el dato de creditos: la mas rapida' 'recomendado: B con esfuerzo medium | motivo: cumple y es la mas rapida (sin dato de creditos) | todo con uno: si' ($l -join ' | ')
    # 3) empatan en creditos: la mas rapida
    $a = Combo 'A' 'medium' 36 36 20 20 2 2 3.251 100
    $b = Combo 'B' 'medium' 36 36 20 20 2 2 3.251 50
    $l = @(Get-Recomendacion @($a, $b))
    Igual '3) empatan en creditos: la mas rapida' 'recomendado: B con esfuerzo medium | motivo: cumple y es la mas rapida (empatan en creditos: 3,251) | todo con uno: si' ($l -join ' | ')
    # 4) una sola cumple
    $a = Combo 'A' 'medium' 36 36 20 20 2 2 3.251 100
    $b = Combo 'B' 'medium' 10 36 20 20 2 2 1.0 10
    $l = @(Get-Recomendacion @($b, $a))
    Igual '4) una sola cumple' 'recomendado: A con esfuerzo medium | motivo: cumple y es la unica que cumple (3,251 creditos) | todo con uno: si' ($l -join ' | ')
    $a = Combo 'A' 'medium' 36 36 20 20 2 2 $null 100
    $l = @(Get-Recomendacion @($a))
    Igual '4b) una sola y sin creditos' 'recomendado: A con esfuerzo medium | motivo: cumple y es la unica que cumple (sin dato de creditos) | todo con uno: si' ($l -join ' | ')
    # 5) ninguna cumple: la mejor por arreglos que pasan y despues por clave
    $a = Combo 'A' 'medium' 20 36 20 20 2 2 3.0 100
    $b = Combo 'B' 'max' 35 36 20 20 1 2 1.0 10
    $l = @(Get-Recomendacion @($b, $a))
    Igual '5) ninguna cumple: la mejor, por arreglos que pasan antes que por clave' 'recomendado: ninguno cumple | la mejor: A con esfuerzo medium (clave 20 de 36, arreglos 2 de 2) | todo con uno: no' ($l -join ' | ')
    $a = Combo 'A' 'medium' 20 36 20 20 2 2 3.0 100
    $b = Combo 'B' 'max' 30 36 20 20 2 2 1.0 10
    $l = @(Get-Recomendacion @($a, $b))
    Igual '5b) con los mismos arreglos, la de mas clave' 'recomendado: ninguno cumple | la mejor: B con esfuerzo max (clave 30 de 36, arreglos 2 de 2) | todo con uno: no' ($l -join ' | ')
    # 6) la mas barata falla un arreglo: no se recomienda
    $a = Combo 'A' 'medium' 36 36 20 20 1 2 0.5 10
    $b = Combo 'B' 'medium' 36 36 20 20 2 2 5.870 90
    $l = @(Get-Recomendacion @($a, $b))
    Igual '6) la mas barata falla un arreglo: se recomienda la otra' 'recomendado: B con esfuerzo medium | motivo: cumple y es la unica que cumple (5,870 creditos) | todo con uno: si' ($l -join ' | ')
    # 7) lectura no valida, citas bajas y el limite del 90 %
    $a = Combo 'A' 'medium' 36 36 20 20 2 2 0.5 10 $false
    $b = Combo 'B' 'medium' 36 36 17 20 2 2 0.6 10
    $c = Combo 'C' 'medium' 9 10 18 20 2 2 9.0 10
    $l = @(Get-Recomendacion @($a, $b, $c))
    Igual '7) lectura no valida y citas al 85 % no cumplen; clave y citas justo al 90 % si' 'recomendado: C con esfuerzo medium | motivo: cumple y es la unica que cumple (9,000 creditos) | todo con uno: si' ($l -join ' | ')
    $d = Combo 'D' 'medium' 8 9 18 20 2 2 0.1 10
    $l = @(Get-Recomendacion @($d))
    Igual '7b) clave 8 de 9 (88,9 %) no cumple' 'recomendado: ninguno cumple' ($l[0])
    $e0 = Combo 'E' 'medium' 0 0 0 0 2 2 0.1 10
    $l = @(Get-Recomendacion @($e0))
    Igual '7c) sin datos ni clave no cumple' 'recomendado: ninguno cumple' ($l[0])
    # 8) solo lecturas (sin Maven): se recomienda, pero no se sabe si vale para todo
    $a = Combo 'A' 'medium' 36 36 20 20 0 0 3.0 10
    $l = @(Get-Recomendacion @($a))
    Igual '8) sin arreglos: recomienda y dice sin dato de arreglos' 'recomendado: A con esfuerzo medium | motivo: cumple y es la unica que cumple (3,000 creditos) | todo con uno: sin dato de arreglos' ($l -join ' | ')
    # 9) nada que comparar
    $l = @(Get-Recomendacion @())
    Igual '9) sin combinaciones' 'recomendado: sin datos' ($l -join ' | ')
  }
  # extremo a extremo con el falso
  $e = Nuevo-Examen 'examen-reco'
  try {
    Pon-Claves $ClavesPeque
    $d = @{ RESCATE_EXAMEN_DATOS = $DatosPeque }
    # el B (claude) es mas barato pero su E1 no compila: se recomienda el A
    $d['RESCATE_EXAMEN_USO'] = '^gpt=2000000000,1,1;^claude=1000000000,1,1'
    $r1 = Pf-Examen $e "$MA,$MB" 'medium' 'exa-e1-no-compila:^claude.*:E1$' $d
    $b1 = Examen-De $r1
    Igual 'e2e 1) el mas barato falla un arreglo: no se recomienda' "recomendado: $MA con esfuerzo medium" (Linea-Con $b1 'recomendado: ')
    Igual 'e2e 1) y es la unica que cumple' 'motivo: cumple y es la unica que cumple (8,000 creditos)' (Linea-Con $b1 'motivo: ')
    Igual 'e2e 1) todo con uno: si' 'todo con uno: si' (Linea-Con $b1 'todo con uno: ')
    Comprueba 'e2e 1) la fila de B dice que no compila' ((Linea-Con (Combinacion-De $r1 $MB 'medium') 'E1: ') -match '^E1: pasa no \(no compila\)')
    # los dos cumplen y A cuesta la mitad
    $d['RESCATE_EXAMEN_USO'] = '^claude=2000000000,1,1'
    $r2 = Pf-Examen $e "$MA,$MB" 'medium' '' $d
    $b2 = Examen-De $r2
    Igual 'e2e 2) los dos cumplen: el mas barato' "recomendado: $MA con esfuerzo medium" (Linea-Con $b2 'recomendado: ')
    Igual 'e2e 2) con la siguiente' 'motivo: cumple y es la mas barata (4,000 creditos; la siguiente, 8,000)' (Linea-Con $b2 'motivo: ')
    # sin creditos: gana el mas rapido (A espera 10 s en L1)
    $d['RESCATE_EXAMEN_USO'] = '.=-'
    $r3 = Pf-Examen $e "$MA,$MB" 'medium' 'exa-espera-10:^gpt.*:L1$' $d
    $b3 = Examen-De $r3
    Igual 'e2e 3) sin creditos: el mas rapido' "recomendado: $MB con esfuerzo medium" (Linea-Con $b3 'recomendado: ')
    Igual 'e2e 3) con su motivo' 'motivo: cumple y es la mas rapida (sin dato de creditos)' (Linea-Con $b3 'motivo: ')
    # ninguna cumple: con los datos por defecto del falso no se acierta la clave
    $r4 = Pf-Examen $e "$MA,$MB" 'medium'
    $b4 = Examen-De $r4
    Igual 'e2e 4) ninguna cumple' 'recomendado: ninguno cumple' (Linea-Con $b4 'recomendado: ')
    Comprueba 'e2e 4) y la mejor' ((Linea-Con $b4 'la mejor: ') -match ('^la mejor: ' + [regex]::Escape($MA) + ' con esfuerzo medium \(clave 0 de 6, arreglos 2 de 2\)$')) (Linea-Con $b4 'la mejor: ')
  }
  finally { Restaura-Claves }
}

$Pruebas['27 bloque 9, esfuerzo no admitido: baja de max a xhigh y a high y lo dice'] = {
  $e = Nuevo-Examen 'examen-esfuerzo'
  try {
    Pon-Claves $ClavesPeque
    $d = @{ RESCATE_EXAMEN_DATOS = $DatosPeque }
    # a) max no vale; medium si
    $a = Pf-Examen $e $MA 'medium,max' ('exa-sin-esfuerzo:' + $MA + ':max:L1$') $d
    Igual 'a) sale con 0' 0 $a.Codigo
    $xa = @(Combinacion-De $a $MA 'max')
    Igual 'a) la cabecera sigue diciendo el esfuerzo pedido' "modelo $MA | esfuerzo max" $xa[0]
    Igual 'a) esfuerzo usado: xhigh' 'esfuerzo usado: xhigh (max no admitido)' $xa[1]
    Comprueba 'a) y el motivo corto, filtrado, del rechazo' ((Linea-Con $xa 'motivo del esfuerzo: ') -match "^motivo del esfuerzo: .*invalid value 'max'") (Linea-Con $xa 'motivo del esfuerzo: ')
    Igual 'a) la combinacion de medium no lleva esa linea' 0 @(Combinacion-De $a $MA 'medium' | Where-Object { $_ -match '^esfuerzo usado' }).Count
    $claves = @((Llamadas $e.Llamadas) | ForEach-Object { $_.clave })
    Igual 'a) las llamadas: medium entera, max (que falla), y xhigh entera' ("${MA}:medium:L1 ${MA}:medium:L2-1 ${MA}:medium:E1 ${MA}:medium:E2 ${MA}:max:L1 ${MA}:xhigh:L1 ${MA}:xhigh:L2-1 ${MA}:xhigh:E1 ${MA}:xhigh:E2") ($claves -join ' ')
    Comprueba 'a) la recomendacion nunca dice max, que no se uso' ((Linea-Con (Examen-De $a) 'recomendado: ') -notmatch 'esfuerzo max$') (Linea-Con (Examen-De $a) 'recomendado: ')
    Sin-Fugas $a 'esfuerzo a'
    # b) ni max ni xhigh valen: se llega a high
    $b = Pf-Examen $e $MA 'max' ('exa-sin-esfuerzo:' + $MA + ':(max|xhigh):L1$') $d
    $xb = @(Combinacion-De $b $MA 'max')
    Igual 'b) esfuerzo usado: high' 'esfuerzo usado: high (max no admitido)' $xb[1]
    Igual 'b) tres llamadas a L1 hasta dar con uno que vale' "${MA}:max:L1 ${MA}:xhigh:L1 ${MA}:high:L1" ((@((Llamadas $e.Llamadas) | ForEach-Object { $_.clave }) | Select-Object -First 3) -join ' ')
    Comprueba 'b) la combinacion se hace entera con high' ((Linea-Con $xb 'total: ') -match '^total: clave 6 de 6 \| arreglos 2 de 2 \|') (Linea-Con $xb 'total: ')
    Igual 'b) se recomienda con high' "recomendado: $MA con esfuerzo high" (Linea-Con (Examen-De $b) 'recomendado: ')
  }
  finally { Restaura-Claves }
}

$Pruebas['28 bloque 9, modelo que no existe: su fila se salta y el otro se examina entero'] = {
  $e = Nuevo-Examen 'examen-nomodelo'
  try {
    Pon-Claves $ClavesPeque
    $d = @{ RESCATE_EXAMEN_DATOS = $DatosPeque }
    $r = Pf-Examen $e "$MA,$MB" 'medium,max' 'exa-no-existe:^gpt' $d
    Igual 'sale con 0' 0 $r.Codigo
    Igual 'sin bloques con fallo' 'ninguno' (Valor-De $r 'bloques con fallo')
    $b = Examen-De $r
    Comprueba 'el modelo que no existe sale con sin modelo y el principio de lo que dijo Copilot' ((Linea-Con $b 'sin modelo: ') -match "^sin modelo: Error: model '$MA' is not available$") (Linea-Con $b 'sin modelo: ')
    Igual 'y solo se intenta una vez (su fila se salta entera, tambien con max)' 0 @($b | Where-Object { $_ -ceq "modelo $MA | esfuerzo max" }).Count
    $claves = @((Llamadas $e.Llamadas) | ForEach-Object { $_.clave })
    Igual 'una sola llamada al modelo que no existe' 1 @($claves | Where-Object { $_ -like "${MA}:*" }).Count
    Igual 'y las 8 del otro: dos combinaciones de 4' 8 @($claves | Where-Object { $_ -like "${MB}:*" }).Count
    foreach ($f in @('medium', 'max')) {
      $x = @(Combinacion-De $r $MB $f)
      Comprueba "$MB con $f : L1, L2, E1, E2 y total" ($x.Count -ge 6 -and (Linea-Con $x 'L1: ') -ne '' -and (Linea-Con $x 'L2: ') -ne '' -and (Linea-Con $x 'E1: ') -ne '' -and (Linea-Con $x 'E2: ') -ne '' -and (Linea-Con $x 'total: ') -ne '') ($x -join ' / ')
    }
    Comprueba 'se recomienda el que existe' ((Linea-Con $b 'recomendado: ') -match ('^recomendado: ' + [regex]::Escape($MB) + ' con esfuerzo (medium|max)$')) (Linea-Con $b 'recomendado: ')
    # un solo modelo con max y que no existe: tres intentos (max, xhigh, high) y sin modelo; nada que recomendar
    $r2 = Pf-Examen $e $MA 'max' 'exa-no-existe:.' $d
    Igual 'solo ese modelo con max: tres llamadas fallidas' "${MA}:max:L1 ${MA}:xhigh:L1 ${MA}:high:L1" ((@((Llamadas $e.Llamadas) | ForEach-Object { $_.clave })) -join ' ')
    Comprueba 'dice sin modelo y no hay nada que recomendar' ((Linea-Con (Examen-De $r2) 'sin modelo: ') -ne '' -and (Linea-Con (Examen-De $r2) 'recomendado: ') -ceq 'recomendado: sin datos') ((Examen-De $r2) -join ' / ')
    Igual 'y no es un fallo del bloque' 'ninguno' (Valor-De $r2 'bloques con fallo')
  }
  finally { Restaura-Claves }
}

$Pruebas['29 bloque 9 sin Maven: solo L1 y L2, sin maven en E y todo con uno: sin dato de arreglos'] = {
  $e = Nuevo-Examen 'examen-sinmaven'
  try {
    Pon-Claves $ClavesPeque
    $d = @{ RESCATE_EXAMEN_DATOS = $DatosPeque }
    # a) -SinMaven, con el esfuerzo por defecto (solo medium)
    $a = Pf-Examen $e "$MA,$MB" '' '' $d @('-SinMaven')
    Igual 'a) sale con 0' 0 $a.Codigo
    $ll = @(Llamadas $e.Llamadas)
    Igual 'a) 2 modelos x 1 esfuerzo por defecto x (L1 + 1 trozo de L2) = 4 llamadas' 4 $ll.Count
    Igual 'a) ninguna es de E1 ni de E2' 0 @($ll | Where-Object { $_.clave -match ':E[12]$' }).Count
    $b = Examen-De $a
    Comprueba 'a) el esfuerzo por defecto es solo medium' (@($b | Where-Object { $_ -match '^modelo \S+ \| esfuerzo medium$' }).Count -eq 2 -and @($b | Where-Object { $_ -match '^modelo \S+ \| esfuerzo ' }).Count -eq 2) (@($b | Where-Object { $_ -match '^modelo ' }) -join ' / ')
    $x = @(Combinacion-De $a $MA 'medium')
    Igual 'a) E1: sin maven' 'E1: sin maven' (Linea-Con $x 'E1: ')
    Igual 'a) E2: sin maven' 'E2: sin maven' (Linea-Con $x 'E2: ')
    Comprueba 'a) el total no cuenta arreglos' ((Linea-Con $x 'total: ') -match '^total: clave 6 de 6 \| arreglos sin maven \| \d+ s \| creditos 2,000 \| tokens entrada 2000 salida 200$') (Linea-Con $x 'total: ')
    Comprueba 'a) se recomienda igual' ((Linea-Con $b 'recomendado: ') -match '^recomendado: \S+ con esfuerzo \w+$') (Linea-Con $b 'recomendado: ')
    Igual 'a) todo con uno: sin dato de arreglos' 'todo con uno: sin dato de arreglos' (Linea-Con $b 'todo con uno: ')
    Comprueba 'a) la consola cuenta 4 llamadas (sin las de E)' ($a.Salida -match '(?m)^4 llamadas, hasta 8 min\s*$') (Cola $a.Salida)
    # b) el bloque 6 falla (no hay Maven donde dicen los ajustes): el 9 tampoco se arriesga con E
    Pon-Ajustes $e @{ MvnExe = (Join-Path $Dir 'no-existe-zorba/mvn.ps1') }
    $c = Pf $e (Todos $e @('-Solo', '6,9', '-Modelos', $MA, '-Esfuerzos', 'medium')) '' $d
    Igual 'b) bloques con fallo: el 6' '6' (Valor-De $c 'bloques con fallo')
    $y = @(Combinacion-De $c $MA 'medium')
    Comprueba 'b) E1 y E2 salen sin maven' ((Linea-Con $y 'E1: ') -ceq 'E1: sin maven' -and (Linea-Con $y 'E2: ') -ceq 'E2: sin maven') ($y -join ' / ')
    Igual 'b) y solo se llamo para L1 y L2' 2 @(Llamadas $e.Llamadas).Count
    Igual 'b) todo con uno: sin dato de arreglos' 'todo con uno: sin dato de arreglos' (Linea-Con (Examen-De $c) 'todo con uno: ')
  }
  finally { Restaura-Claves }
}

$Pruebas['30 bloque 9, privacidad: nada de la empresa en el examen (errores de Copilot, citas y textos del modelo con de todo)'] = {
  $e = Nuevo-Examen 'examen-privado'
  try {
    Pon-Claves $ClavesPeque
    $secreto = 'usuario zorbalex equipo PCZORBA dominio DOMZORBA zorba.local correo jefe.zorba@zorba-corp.com ip 10.77.88.99 url https://nexus.zorba-interno.local:8443/repo/x ' + $e.Legacy + ' ' + $e.Migrado + ' ' + [Environment]::GetFolderPath('UserProfile') + ' clase ZorbaCorta ' + $Dir
    $guion = 'exa-error-privado:^gpt;exa-ficha-secreta:^claude.*:L[12];exa-error-privado:^claude.*:E1$'
    $r = Pf-Examen $e "$MA,$MB" 'medium' $guion @{ RESCATE_ERROR_TEXTO = $secreto; RESCATE_EXAMEN_DATOS = $DatosPeque }
    Igual 'sale con 0' 0 $r.Codigo
    $b = Examen-De $r
    Comprueba 'el modelo que falla sale con sin modelo y el error ya filtrado' ((Linea-Con $b 'sin modelo: ') -match '<usuario>' -and (Linea-Con $b 'sin modelo: ') -match '<equipo>') (Linea-Con $b 'sin modelo: ')
    Comprueba 'las lecturas con citas inventadas dicen json no y el principio del motivo, sin la cita' ((Linea-Con (Combinacion-De $r $MB 'medium') 'L1: ') -match '^L1: json no \|' -and ((Combinacion-De $r $MB 'medium') -join ' / ') -match 'motivo: Mas de la mitad de las citas') ((Combinacion-De $r $MB 'medium') -join ' / ')
    Igual 'un fallo de Copilot en E1 es solo fallo de copilot' 'E1: pasa no (fallo de copilot)' ((Linea-Con (Combinacion-De $r $MB 'medium') 'E1: ') -replace ' \|.*$', '')
    Sin-Fugas $r 'examen'
    Comprueba 'y es ASCII puro' ((Es-Ascii $r.Fichero) -and (Es-Ascii $r.Salida))
    Comprueba 'ni el texto inventado del modelo ni su secreto salen' (($r.Fichero + $r.Salida) -notmatch 'SECRETO' -and ($r.Fichero + $r.Salida) -notmatch 'nexus')
  }
  finally { Restaura-Claves }
}

# La referencia de juguete del escenario con lo que incumple: 2 capas (dominio y application importan infrastructure), 1 fichero
# (una clase abre ficheros a pelo), 3 reglas de calidad (Javadoc, consola y catch vacio) y 4 secretos en claro.
$SecretosRef = @('zorba-pw-uno', 'zorba-tk-dos', 'zorba-ak-tres', 'zorba-cl-cuatro')
function Pon-Referencia-Que-Incumple($E) {
  $b = 'src/main/java/com/zorba/plantilla/'
  $inf = 'com.zorba.plantilla.infrastructure.config.Ajustes'
  Escribe $E.Plantilla ($b + 'infrastructure/config/Ajustes.java') (Clase-Con 'Ajustes' 'com.zorba.plantilla.infrastructure.config' @() @('int a = 1;'))
  Escribe $E.Plantilla ($b + 'domain/Modelo.java') (Clase-Con 'Modelo' 'com.zorba.plantilla.domain' @($inf) @('int a = 1;'))
  Escribe $E.Plantilla ($b + 'application/Caso.java') (Clase-Con 'Caso' 'com.zorba.plantilla.application' @($inf) @('int a = 1;', 'void m() { System.out.println("x"); }'))
  Escribe $E.Plantilla ($b + 'infrastructure/adapters/output/sftp/Local.java') (Clase-Con 'Local' 'com.zorba.plantilla.infrastructure.adapters.output.sftp' @('java.io.FileReader') @('Object r = null;', 'void m() { try { r = null; } catch (Exception e) { } }'))
  Escribe $E.Plantilla 'src/main/resources/application.yml' ("sftp:`n  password: zorba-pw-uno`n  token: zorba-tk-dos`n  api-key: zorba-ak-tres`n  clave: zorba-cl-cuatro`n")
}

$Pruebas['31 bloque 7, referencia que incumple: cuenta capas, ficheros, calidad y secretos de la referencia, sin el valor de los secretos'] = {
  $e = Nuevo-Escenario 'referencia'
  Pon-Referencia-Que-Incumple $e
  $r = Pf $e (Todos $e @('-Solo', '7'))
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'la linea dice los numeros de la referencia de juguete' 'capas 2 | ficheros 1 | calidad 3 | secretos 4' (Valor-De $r 'plantilla incumple')
  Igual 'una sola linea' 1 (Cuenta-Lineas $r '^plantilla incumple: ')
  $l = Lineas-De $r
  $iLinea = [array]::IndexOf($l, @($l | Where-Object { $_ -match '^plantilla incumple: ' })[0])
  $iDiag = [array]::IndexOf($l, @($l | Where-Object { $_ -match '^calidad: ' })[0])
  Comprueba 'va tras las lineas del diagnostico' ($iDiag -ge 0 -and $iLinea -gt $iDiag) "$iDiag $iLinea"
  Comprueba 'es el bloque 7 quien la escribe' (@(Bloque-De $r '7') -contains ('plantilla incumple: capas 2 | ficheros 1 | calidad 3 | secretos 4'))
  $todo = $r.Fichero + "`n" + $r.Salida
  foreach ($s in $SecretosRef) { Comprueba ('el valor del secreto ' + $s.Substring(6, 2) + ' no sale') (-not $todo.Contains($s)) }
  Sin-Fugas $r 'referencia'
  Comprueba 'y es ASCII puro' ((Es-Ascii $r.Fichero) -and (Es-Ascii $r.Salida))
}

$Pruebas['32 bloque 7, referencia que incumple: si el diagnostico corre y no trae la linea o la trae con otra cosa que digitos, desconocido'] = {
  $e = Nuevo-Escenario 'referencia-sin-linea'
  Nueva-Instalacion
  $real = Join-Path $origen 'rescate.ps1'
  $falso = Join-Path $Inst 'rescate.ps1'
  try {
    # a) un rescate.ps1 que hace su diagnostico y no dice nada de la referencia
    Escribe $Inst 'rescate.ps1' ("param([string]`$Repo, [string]`$Plantilla, [switch]`$SinWorktree)`nWrite-Host 'build               0        0'`nexit 0`n")
    $a = Pf $e (Todos $e @('-Solo', '7'))
    Igual 'a) sale con 0' 0 $a.Codigo
    Igual 'a) el diagnostico corrio' 'codigo 0' ((Valor-De $a 'diagnostico') -replace ' en \d+ s$', '')
    Igual 'a) build sale' '0 errores, 0 avisos' (Valor-De $a 'build')
    Igual 'a) la linea dice desconocido' 'desconocido' (Valor-De $a 'plantilla incumple')
    # b) la linea trae algo que no son digitos (una ruta con nombres): no pasa nada de eso
    Escribe $Inst 'rescate.ps1' ("param([string]`$Repo, [string]`$Plantilla, [switch]`$SinWorktree)`nWrite-Host 'build               0        0'`nWrite-Host 'Plantilla incumple: capas C:\Users\zorbalex | ficheros 1 | calidad 2 | secretos 3'`nexit 0`n")
    $b = Pf $e (Todos $e @('-Solo', '7'))
    Igual 'b) la linea dice desconocido' 'desconocido' (Valor-De $b 'plantilla incumple')
    Sin-Fugas $b 'referencia b'
  }
  finally { Copy-Item -LiteralPath $real -Destination $falso -Force }
}

$Pruebas['33 bloque 7, referencia que incumple: sin -Plantilla, o con el diagnostico saltado, no hay linea'] = {
  $e = Nuevo-Escenario 'referencia-sin'
  Pon-Referencia-Que-Incumple $e
  $a = Pf $e @('-Legacy', $e.Legacy, '-Migrado', $e.Migrado, '-Solo', '7')
  Igual 'a) sale con 0' 0 $a.Codigo
  Comprueba 'a) sin -Plantilla el diagnostico se salta' ((Valor-De $a 'diagnostico') -match '^saltado') ((Bloque-De $a '7') -join ' / ')
  Igual 'a) no hay linea de la referencia' 0 (Cuenta-Lineas $a 'incumple')
  Sin-Fugas $a 'referencia a'
  $b = Pf $e (Todos $e @('-Solo', '7', '-SinMaven'))
  Comprueba 'b) con -SinMaven el diagnostico se salta' ((Valor-De $b 'diagnostico') -match '^saltado') ((Bloque-De $b '7') -join ' / ')
  Igual 'b) no hay linea de la referencia' 0 (Cuenta-Lineas $b 'incumple')
  Sin-Fugas $b 'referencia b'
}

# ================================ LANZADOR ================================
Invoke-Banco $Pruebas $Script
