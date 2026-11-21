<#
probar-huella.ps1 - Banco de pruebas de huella.ps1 (BP-3): la huella de lo compilado.
No necesita Java ni Maven ni Copilot, y no los llama nunca: usa los textos de 'javap -v -p' que dejaron los 22 casos de E7 sobre un
juguete (tests/datos/huella, datos inventados: com.ejemplo) y un javap de mentira, tests/falsos/bp3-javap.ps1.
Vale para Windows PowerShell 5.1 y para PowerShell 7. Solo ASCII a proposito.

  .\tests\probar-huella.ps1                       # todas las pruebas
  .\tests\probar-huella.ps1 -Solo '(b)'           # las que llevan '(b)' en el nombre
  .\tests\probar-huella.ps1 -Dir D:\tmp\x -Conservar

Cada carpeta de tests/datos/huella es un caso: antes\ y despues\ con un <ruta>.class.javap por cada clase que cambia de bytes, recursos-antes.txt y
recursos-despues.txt ('<sha256>  <ruta>' de lo que no es .class) y esperado.txt (IGUAL o DISTINTO, de e7-resultado.txt).
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
$falso = Join-Path (Join-Path $aqui 'falsos') 'bp3-javap.ps1'
$datos = Join-Path (Join-Path $aqui 'datos') 'huella'
. (Join-Path $aqui 'comun-banco.ps1')
. (Join-Path $raiz 'comun.ps1')
. (Join-Path $raiz 'huella.ps1')

# ============================== UTILIDADES ==============================
# Un caso: sus dos tablas (ruta -> texto de javap si es .class; ruta -> SHA-256 si no) y lo que esperaba E7.
function Lee-Caso([string]$Nombre) {
  $c = Get-ChildItem -LiteralPath $datos -Directory | Where-Object { $_.Name -like "$Nombre-*" }
  if (@($c).Count -ne 1) { throw "el caso $Nombre no esta en $datos" }
  $caso = [pscustomobject]@{ Nombre = $c.Name; Esperado = ([System.IO.File]::ReadAllText((Join-Path $c.FullName 'esperado.txt'))).Trim(); Antes = $null; Despues = $null }
  foreach ($lado in @('antes', 'despues')) {
    $t = New-Object 'System.Collections.Generic.Dictionary[string,string]'
    $base = Join-Path $c.FullName $lado
    if (Test-Path -LiteralPath $base) {
      foreach ($f in @(Get-ChildItem -LiteralPath $base -Recurse -File -Filter '*.javap')) {
        $rel = Get-Rel $base $f.FullName
        $t[$rel.Substring(0, $rel.Length - '.javap'.Length)] = [System.IO.File]::ReadAllText($f.FullName)
      }
    }
    foreach ($l in [System.IO.File]::ReadAllLines((Join-Path $c.FullName "recursos-$lado.txt"))) {
      if ($l -match '^([0-9a-f]{64})  (.+)$') { $t[$Matches[2]] = $Matches[1] }
    }
    if ($lado -ceq 'antes') { $caso.Antes = $t } else { $caso.Despues = $t }
  }
  return $caso
}

# Una carpeta como la target\classes de un proyecto: una clase de mentira por entrada .class de $Tabla (su contenido es el texto de javap)
# y un fichero por cada ruta de $Recursos (ruta -> contenido).
function Nuevo-Target([string]$Nombre, $Tabla, [hashtable]$Recursos = @{}) {
  $r = Join-Path $Dir $Nombre
  [void](New-Item -ItemType Directory -Path $r -Force)
  foreach ($k in @($Tabla.Keys | Where-Object { $_ -like '*.class' })) { Escribe $r $k $Tabla[$k] }
  foreach ($k in $Recursos.Keys) { Escribe $r $k $Recursos[$k] }
  return $r
}

# Corre $Bloque con las variables de entorno de $Vars ($null: sin esa variable); al salir deja todo como estaba.
function Con-Entorno([hashtable]$Vars, [scriptblock]$Bloque) {
  $ant = @{}
  foreach ($k in $Vars.Keys) { $ant[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $Vars[$k]) }
  try { return (& $Bloque) }
  finally { foreach ($k in $Vars.Keys) { [Environment]::SetEnvironmentVariable($k, $ant[$k]) } }
}

# Lo que dice una comparacion de la clase cuya ruta acaba en $Sufijo: sus partes, unidas con '; '.
function Partes-De($R, [string]$Sufijo) {
  return ((@($R.Diferencias | Where-Object { $_.Clase -like "*$Sufijo" } | ForEach-Object { $_.Partes -join '; ' })) -join ' ;; ')
}

# Las diferencias de una comparacion en una linea, para ver que dos comparaciones dicen lo mismo.
function Resumen-De($R) {
  return ("$($R.Igual)|" + ((@($R.Diferencias | ForEach-Object { $_.Clase + '=' + ($_.Partes -join ';') })) -join '|'))
}

# El texto de javap -v -p de una clase pequena con un literal: lo justo para que la huella tenga cabecera, un metodo y atributos.
function Texto-Clase([string]$Nombre, [string]$Literal) {
  $l = @(
    '  Last modified Nov 19, 2026; size 100 bytes', '  SHA-256 checksum 00', "  Compiled from `"$Nombre.java`"", "public class com.ejemplo.$Nombre",
    '  minor version: 0', '  major version: 65', '  flags: (0x0021) ACC_PUBLIC, ACC_SUPER', "  this_class: #7                          // com/ejemplo/$Nombre",
    '  super_class: #2                         // java/lang/Object', '  interfaces: 0, fields: 0, methods: 1, attributes: 1',
    'Constant pool:', '   #1 = Utf8               x', '{', '  public java.lang.String v();', '    descriptor: ()Ljava/lang/String;',
    '    flags: (0x0001) ACC_PUBLIC', '    Code:', '      stack=1, locals=1, args_size=1',
    "         0: ldc           #3                  // String $Literal", '         2: areturn', '      LineNumberTable:', '        line 5: 0',
    '}', "SourceFile: `"$Nombre.java`""
  )
  return (($l -join "`n") + "`n")
}

# Compare-Huella con el javap falso y $Vars en el entorno.
function Compara-Con-Falso([string]$A, [string]$D, [hashtable]$Vars = @{}) {
  return (Con-Entorno $Vars { Compare-Huella $A $D $falso })
}

$Pruebas = [ordered]@{}

# ================================== (a) ==================================
$Pruebas['bp3 huella (a): los 22 casos de E7 con Compare-HuellaJavap dan el veredicto esperado (6 IGUAL y 16 DISTINTO)'] = {
  $casos = @(Get-ChildItem -LiteralPath $datos -Directory | Sort-Object Name)
  Igual 'hay 22 casos' 22 $casos.Count
  $iguales = 0; $distintos = 0
  foreach ($c in $casos) {
    $k = Lee-Caso ($c.Name.Substring(0, 2))
    $r = Compare-HuellaJavap $k.Antes $k.Despues
    $v = 'DISTINTO'
    if ($r.Igual) { $v = 'IGUAL' }
    Igual $c.Name $k.Esperado $v
    if ($v -ceq 'IGUAL') { $iguales++ } else { $distintos++ }
    if ($v -ceq 'IGUAL') { Igual "$($c.Name): ninguna diferencia" 0 @($r.Diferencias).Count }
    else { Comprueba "$($c.Name): dice cual es la diferencia (la clase y la parte)" (@($r.Diferencias).Count -ge 1 -and @($r.Diferencias | Where-Object { -not $_.Clase -or -not $_.Partes }).Count -eq 0) (Resumen-De $r) }
  }
  Igual 'los de E7 con veredicto IGUAL' 6 $iguales
  Igual 'los de E7 con veredicto DISTINTO' 16 $distintos
}

$Pruebas['bp3 huella (a): cada DISTINTO dice la parte que cambia, como el prototipo (metodos, campos, orden, atributos, solo despues, contenido)'] = {
  $k = Lee-Caso '07'
  Comprueba '07 Lombok cambia el nombre del parametro: los metodos de GenerarRemesa' ((Partes-De (Compare-HuellaJavap $k.Antes $k.Despues) 'GenerarRemesa.class') -like 'metodos: public com.ejemplo.application.usecase.GenerarRemesa(*')
  $k = Lee-Caso '11'
  Igual '11 literal dentro de una concatenacion' 'metodos: public java.lang.String primera();' (Partes-De (Compare-HuellaJavap $k.Antes $k.Despues) 'GenerarRemesa.class')
  $k = Lee-Caso '16'
  Igual '16 orden de dos metodos' 'orden de los metodos escritos a mano' (Partes-De (Compare-HuellaJavap $k.Antes $k.Despues) 'GenerarRemesa.class')
  $k = Lee-Caso '17'
  Igual '17 orden de dos campos' 'campos (o su orden)' (Partes-De (Compare-HuellaJavap $k.Antes $k.Despues) 'GenerarRemesa.class')
  $k = Lee-Caso '18'
  Igual '18 anotacion de clase' 'atributos de clase' (Partes-De (Compare-HuellaJavap $k.Antes $k.Despues) 'GenerarRemesa.class')
  $r = Compare-HuellaJavap (Lee-Caso '19').Antes (Lee-Caso '19').Despues
  Comprueba '19 constante copiada a otra clase: los metodos de GenerarRemesa' ((Partes-De $r 'GenerarRemesa.class') -like 'metodos: public java.lang.String sql();*')
  Igual '19 constante copiada a otra clase: los campos de Remesa' 'campos (o su orden)' (Partes-De $r 'domain/Remesa.class')
  $k = Lee-Caso '21'
  Igual '21 package-info nuevo: solo despues' 'solo despues' (Partes-De (Compare-HuellaJavap $k.Antes $k.Despues) 'package-info.class')
  Igual '21 al reves, package-info solo antes' 'solo antes' (Partes-De (Compare-HuellaJavap $k.Despues $k.Antes) 'package-info.class')
  $k = Lee-Caso '22'
  Igual '22 recurso con otro contenido' 'contenido' (Partes-De (Compare-HuellaJavap $k.Antes $k.Despues) 'application.properties')
}

# ================================== (b) ==================================
$Pruebas['bp3 huella (b): Compare-Huella con carpetas y un javap falso - lo mismo da IGUAL; un fichero de mas o de menos y un recurso con otro contenido dan DISTINTO'] = {
  $k = Lee-Caso '05'
  $rec = @{ 'application.properties' = "batch.ruta=/a`n"; 'META-INF/aviso.txt' = "uno`n" }
  $a = Nuevo-Target 'b-antes' $k.Antes $rec
  $d = Nuevo-Target 'b-igual' $k.Antes $rec
  $r = Compara-Con-Falso $a $d
  Comprueba 'lo mismo: IGUAL' ($r.Igual -eq $true) (Resumen-De $r)
  Igual 'lo mismo: ninguna diferencia' 0 @($r.Diferencias).Count
  $rec2 = @{ 'application.properties' = "batch.ruta=/a`n"; 'META-INF/aviso.txt' = "uno`n"; 'otro.txt' = "x`n" }
  $d = Nuevo-Target 'b-de-mas' $k.Antes $rec2
  $r = Compara-Con-Falso $a $d
  Comprueba 'un fichero de mas: DISTINTO' ($r.Igual -eq $false) (Resumen-De $r)
  Igual 'un fichero de mas: dice cual y que es nuevo' 'solo despues' (Partes-De $r 'otro.txt')
  $d = Nuevo-Target 'b-de-menos' $k.Antes @{ 'application.properties' = "batch.ruta=/a`n" }
  $r = Compara-Con-Falso $a $d
  Comprueba 'un fichero de menos: DISTINTO' ($r.Igual -eq $false) (Resumen-De $r)
  Igual 'un fichero de menos: dice cual' 'solo antes' (Partes-De $r 'aviso.txt')
  $d = Nuevo-Target 'b-clase-de-mas' $k.Antes $rec
  Escribe $d 'com/ejemplo/Nueva.class' (Texto-Clase 'Nueva' 'x')
  $r = Compara-Con-Falso $a $d
  Comprueba 'una clase de mas: DISTINTO' ($r.Igual -eq $false) (Resumen-De $r)
  Igual 'una clase de mas: dice cual' 'solo despues' (Partes-De $r 'Nueva.class')
  $d = Nuevo-Target 'b-recurso' $k.Antes @{ 'application.properties' = "batch.ruta=/b`n"; 'META-INF/aviso.txt' = "uno`n" }
  $r = Compara-Con-Falso $a $d
  Comprueba 'un recurso con otro contenido: DISTINTO' ($r.Igual -eq $false) (Resumen-De $r)
  Igual 'un recurso con otro contenido: dice cual' 'contenido' (Partes-De $r 'application.properties')
  Igual 'un recurso con otro contenido: solo ese' 1 @($r.Diferencias).Count
  $d = Nuevo-Target 'b-igual-fecha' $k.Antes $rec
  (Get-Item -LiteralPath (Join-Path $d 'application.properties')).LastWriteTime = (Get-Date).AddDays(-3)
  $r = Compara-Con-Falso $a $d
  Comprueba 'el mismo recurso con otra fecha: IGUAL (cuenta el contenido, no la fecha)' ($r.Igual -eq $true) (Resumen-De $r)
}

$Pruebas['bp3 huella (b): Compare-Huella mira cada clase con la huella - un literal distinto dentro de una clase da DISTINTO y lo dice; un cambio que no cuenta da IGUAL'] = {
  $k = Lee-Caso '11'
  $r = Compara-Con-Falso (Nuevo-Target 'b2-antes' $k.Antes) (Nuevo-Target 'b2-despues' $k.Despues)
  Comprueba 'literal dentro de una concatenacion: DISTINTO' ($r.Igual -eq $false) (Resumen-De $r)
  Igual 'literal dentro de una concatenacion: la parte' 'metodos: public java.lang.String primera();' (Partes-De $r 'GenerarRemesa.class')
  $k = Lee-Caso '05'
  $r = Compara-Con-Falso (Nuevo-Target 'b2-lombok-antes' $k.Antes) (Nuevo-Target 'b2-lombok-despues' $k.Despues)
  Comprueba 'constructor a Lombok: IGUAL' ($r.Igual -eq $true) (Resumen-De $r)
}

# ================================== M65 (f) ==================================
$Pruebas['m65 f) la huella no mira META-INF/spring-configuration-metadata.json (solo lo lee la ayuda del IDE) y si additional-spring-configuration-metadata.json (lo escribe la persona)'] = {
  $meta = 'META-INF/spring-configuration-metadata.json'
  $extra = 'META-INF/additional-spring-configuration-metadata.json'
  Igual 'HuellaIgnorar por defecto: solo esa ruta' $meta (@($Cfg.HuellaIgnorar) -join '|')
  $k = Lee-Caso '05'
  $json1 = "{ `"properties`": [ { `"name`": `"acme.lote.a`" }, { `"name`": `"acme.lote.b`" } ] }`n"
  $json2 = "{ `"properties`": [ { `"name`": `"acme.lote.b`", `"description`": `"otra`" }, { `"name`": `"acme.lote.a`" } ] }`n"
  $adicional = "{ `"properties`": [ { `"name`": `"acme.lote.c`" } ] }`n"
  $a = Nuevo-Target 'm65f-antes' $k.Antes @{ 'application.properties' = "batch.ruta=/a`n"; $extra = $adicional; $meta = $json1 }
  $d = Nuevo-Target 'm65f-otro-orden' $k.Antes @{ 'application.properties' = "batch.ruta=/a`n"; $extra = $adicional; $meta = $json2 }
  $r = Compara-Con-Falso $a $d
  Comprueba 'el metadato con otro orden y otras descripciones: IGUAL' ($r.Igual -eq $true) (Resumen-De $r)
  $d = Nuevo-Target 'm65f-sin-metadato' $k.Antes @{ 'application.properties' = "batch.ruta=/a`n"; $extra = $adicional }
  $r = Compara-Con-Falso $a $d
  Comprueba 'el metadato solo en un lado: IGUAL' ($r.Igual -eq $true) (Resumen-De $r)
  $d = Nuevo-Target 'm65f-adicional' $k.Antes @{ 'application.properties' = "batch.ruta=/a`n"; $extra = "{ `"properties`": [] }`n"; $meta = $json1 }
  $r = Compara-Con-Falso $a $d
  Comprueba 'solo cambia additional-spring-configuration-metadata.json: DISTINTO' ($r.Igual -eq $false) (Resumen-De $r)
  Igual 'dice cual y que cambia el contenido' 'contenido' (Partes-De $r 'additional-spring-configuration-metadata.json')
  Igual 'y solo ese' 1 @($r.Diferencias).Count
  $d = Nuevo-Target 'm65f-otro-recurso' $k.Antes @{ 'application.properties' = "batch.ruta=/b`n"; $extra = $adicional; $meta = $json2 }
  $r = Compara-Con-Falso $a $d
  Igual 'con el metadato distinto y otro recurso que cambia: solo el recurso' 'False|application.properties=contenido' (Resumen-De $r)
  # la lista se puede cambiar (ajustes.json): vacia, el metadato cuenta
  $antes = $Cfg.HuellaIgnorar
  try {
    $Cfg.HuellaIgnorar = @()
    $d = Nuevo-Target 'm65f-vacia' $k.Antes @{ 'application.properties' = "batch.ruta=/a`n"; $extra = $adicional; $meta = $json2 }
    $r = Compara-Con-Falso $a $d
    Igual 'con HuellaIgnorar vacia el metadato cuenta' 'contenido' (Partes-De $r 'spring-configuration-metadata.json')
  }
  finally { $Cfg.HuellaIgnorar = $antes }
}

# ================================== (c) ==================================
$Pruebas['bp3 huella (c): sin JAVA_HOME, o sin javap, o si javap falla o se salta una clase, Compare-Huella no da IGUAL y dice que no se pudo medir'] = {
  $k = Lee-Caso '05'
  $a = Nuevo-Target 'c-antes' $k.Antes
  $d = Nuevo-Target 'c-despues' $k.Antes
  $r = Con-Entorno @{ JAVA_HOME = $null } { Compare-Huella $a $d }
  Comprueba 'sin JAVA_HOME: no es IGUAL' ($r.Igual -eq $false) (Resumen-De $r)
  Comprueba 'sin JAVA_HOME: dice no se pudo medir y por que' ((Partes-De $r '') -like 'no se pudo medir: *JAVA_HOME*') (Resumen-De $r)
  $vacio = Join-Path $Dir 'c-jdk-vacio'
  [void](New-Item -ItemType Directory -Path (Join-Path $vacio 'bin') -Force)
  $r = Con-Entorno @{ JAVA_HOME = $vacio } { Compare-Huella $a $d }
  Comprueba 'JAVA_HOME sin bin/javap: no es IGUAL' ($r.Igual -eq $false) (Resumen-De $r)
  Comprueba 'JAVA_HOME sin bin/javap: dice no se pudo medir y por que' ((Partes-De $r '') -like 'no se pudo medir: *javap*') (Resumen-De $r)
  $r = Compara-Con-Falso $a $d @{ BP3_JAVAP_RC = '1' }
  Comprueba 'javap sale con error: no es IGUAL' ($r.Igual -eq $false) (Resumen-De $r)
  Comprueba 'javap sale con error: dice no se pudo medir' ((Partes-De $r '') -like 'no se pudo medir: *') (Resumen-De $r)
  $r = Compara-Con-Falso $a $d @{ BP3_JAVAP_SALTA = '1' }
  Comprueba 'javap se salta una clase: no es IGUAL' ($r.Igual -eq $false) (Resumen-De $r)
  Comprueba 'javap se salta una clase: dice no se pudo medir' ((Partes-De $r '') -like 'no se pudo medir: *') (Resumen-De $r)
  $r = Compara-Con-Falso $a $d
  Comprueba 'y con el javap que funciona, las mismas carpetas dan IGUAL' ($r.Igual -eq $true) (Resumen-De $r)
}

$Pruebas['bp3 huella (c): con JAVA_HOME usa bin/javap (bin\javap.exe en Windows)'] = {
  if ($env:OS -eq 'Windows_NT') { Comprueba 'en Windows no se puede hacer un javap.exe de mentira: se salta' $true; return }
  $k = Lee-Caso '05'
  $a = Nuevo-Target 'c2-antes' $k.Antes
  $d = Nuevo-Target 'c2-despues' $k.Antes
  $jdk = Join-Path $Dir 'c2-jdk'
  $ps = Get-PowerShellExe
  Escribe $jdk 'bin/javap' ("#!/bin/sh`nexec `"$ps`" -NoProfile -File `"$falso`" `"`$@`"`n")
  [void](Invoke-Nativo 'chmod' @('+x', (Join-Path (Join-Path $jdk 'bin') 'javap')))
  $log = Join-Path $Dir 'c2-llamadas.txt'
  $r = Con-Entorno @{ JAVA_HOME = $jdk; BP3_JAVAP_LOG = $log } { Compare-Huella $a $d }
  Comprueba 'con JAVA_HOME: IGUAL' ($r.Igual -eq $true) (Resumen-De $r)
  Comprueba 'con JAVA_HOME: llamo a su javap (una llamada por carpeta)' ((Test-Path -LiteralPath $log) -and @([System.IO.File]::ReadAllLines($log)).Count -eq 2) ''
}

# ================================== (d) ==================================
$Pruebas['bp3 huella (d): con mas clases de las que caben en una linea de comandos, javap se llama en varios lotes de menos de 8.000 caracteres y el resultado es el mismo'] = {
  $largo = 'com/ejemplo/un/paquete/con/un/nombre/bastante/largo/para/llenar/la/linea/de/comandos'
  $n = 120
  $ta = New-Object 'System.Collections.Generic.Dictionary[string,string]'
  $td = New-Object 'System.Collections.Generic.Dictionary[string,string]'
  for ($i = 1; $i -le $n; $i++) {
    $c = 'C{0:D3}' -f $i
    $ta["$largo/$c.class"] = Texto-Clase $c 'uno'
    $lit = 'uno'
    if ($i -eq $n) { $lit = 'dos' }
    $td["$largo/$c.class"] = Texto-Clase $c $lit
  }
  $a = Nuevo-Target 'd-antes' $ta
  $d = Nuevo-Target 'd-despues' $td
  $log = Join-Path $Dir 'd-llamadas.txt'
  $r = Compara-Con-Falso $a $d @{ BP3_JAVAP_LOG = $log }
  $ll = @([System.IO.File]::ReadAllLines($log) | Where-Object { $_ })
  $clases = 0; $maximo = 0; $opciones = @{}
  foreach ($l in $ll) { $p = $l.Split('|'); $clases += [int]$p[0]; if ([int]$p[1] -gt $maximo) { $maximo = [int]$p[1] }; $opciones[$p[2]] = $true }
  Comprueba 'javap se llama en varios lotes (al menos 2 por carpeta)' ($ll.Count -ge 4) "$($ll.Count) llamadas"
  Igual 'entre todos los lotes pasan las 240 clases, ni una mas ni una menos' ($n * 2) $clases
  Comprueba 'ninguna linea de comandos llega a 8.000 caracteres' ($maximo -gt 0 -and $maximo -lt 8000) "la mayor: $maximo"
  Comprueba 'javap lleva -v -p y pide la salida en UTF-8' ($opciones.Count -eq 1 -and ($opciones.Keys -join '') -ceq '-J-Dstdout.encoding=UTF-8 -v -p') ($opciones.Keys -join ' / ')
  $esperado = Compare-HuellaJavap $ta $td
  Comprueba 'el resultado es el mismo que sin lotes' ((Resumen-De $r) -ceq (Resumen-De $esperado)) ((Resumen-De $r) + ' frente a ' + (Resumen-De $esperado))
  Igual 'y es una sola diferencia: la ultima clase' 1 @($r.Diferencias).Count
  Igual 'la ultima clase: lo que cambia' 'metodos: public java.lang.String v();' (Partes-De $r "C$n.class")
  $r = Compara-Con-Falso $a (Nuevo-Target 'd-igual' $ta)
  Comprueba 'lo mismo en tantas clases da IGUAL' ($r.Igual -eq $true) (Resumen-De $r)
}

# ================================== (e) ==================================
$Pruebas['bp3 huella (e): un literal que solo cambia en una letra con tilde da DISTINTO (la salida de javap se lee como UTF-8)'] = {
  $n1 = 'ni' + [char]0xF1 + 'o'
  $n2 = 'ni' + [char]0xE9 + 'o'
  $a = Nuevo-Target 'e-antes' @{ 'com/ejemplo/A.class' = (Texto-Clase 'A' $n1) }
  $d = Nuevo-Target 'e-despues' @{ 'com/ejemplo/A.class' = (Texto-Clase 'A' $n2) }
  $r = Compara-Con-Falso $a $d
  Comprueba 'n con tilde frente a e con tilde: DISTINTO' ($r.Igual -eq $false) (Resumen-De $r)
  Igual 'dice los metodos de A' 'metodos: public java.lang.String v();' (Partes-De $r 'A.class')
  $r = Compara-Con-Falso $a (Nuevo-Target 'e-igual' @{ 'com/ejemplo/A.class' = (Texto-Clase 'A' $n1) })
  Comprueba 'el mismo literal con tilde: IGUAL' ($r.Igual -eq $true) (Resumen-De $r)
}

# ================================== el fichero ==================================
$Pruebas['bp3 huella: el fichero huella.ps1 - solo ASCII, nada de PowerShell 7 y las tres funciones del contrato'] = {
  foreach ($f in @('huella.ps1', 'tests/probar-huella.ps1', 'tests/falsos/bp3-javap.ps1')) {
    $t = [System.IO.File]::ReadAllText((Get-Ruta $raiz $f))
    Comprueba "$f`: solo ASCII" ($t -notmatch '[^\x09\x0A\x0D\x20-\x7E]')
  }
  $codigo = [System.IO.File]::ReadAllText((Join-Path $raiz 'huella.ps1'))
  Comprueba 'huella.ps1: nada de PowerShell 7 (??, ?. ni ?[)' ($codigo -notmatch '\?\?|[\w\)\]]\?\.\w|\w\?\[')
  Comprueba 'las tres funciones del contrato existen' ((@('Get-HuellaClase', 'Compare-HuellaJavap', 'Compare-Huella') | Where-Object { Get-Command $_ -CommandType Function -ErrorAction SilentlyContinue }).Count -eq 3)
}

# ================================ LANZADOR ================================
Invoke-Banco $Pruebas 'tests/probar-huella.ps1'
