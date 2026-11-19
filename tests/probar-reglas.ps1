<#
probar-reglas.ps1 - Banco de pruebas de tests-reglas.ps1 (M35: un test unitario por cada regla de negocio, comprobado con mutantes en la linea de la
regla; la fase 'reglas' de migracion.ps1, con -Reglas), con el Maven de mentira m35-mvn.ps1 y el Copilot de mentira m35-copilot.ps1.
Nunca llama al Maven, al JDK ni a Copilot reales. Vale para Windows PowerShell 5.1 y para PowerShell 7. Solo ASCII a proposito.

  .\tests\probar-reglas.ps1                       # todas las pruebas
  .\tests\probar-reglas.ps1 -Solo '(b)'           # las que llevan '(b)' en el nombre
  .\tests\probar-reglas.ps1 -Dir D:\tmp\x -Conservar

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
. (Join-Path $raiz 'tests-reglas.ps1')

# ================================ DATOS ================================
# El migrado de cada escenario: dos clases con reglas (ReciboValidator y RemesaCalculador) y una sin ellas (Recibo). Los numeros de linea de abajo
# son los de estos textos; Nuevo-Escenario35 comprueba que la cita de cada regla sale en su linea.
$Ruta35 = 'src/main/java/com/acme/recibos/'
$Test35 = 'src/test/java/com/acme/recibos/'
$Commit35 = 'test(reglas): '
$Fuentes35 = [ordered]@{
  ReciboValidator = @'
package com.acme.recibos;

public class ReciboValidator {

    public void validar(Recibo recibo) {
        if (recibo.getImporte() <= 0) {
            throw new IllegalArgumentException("Recibo invalido: " + recibo.getNumero());
        }
        if (recibo.getCliente() == null) {
            throw new IllegalArgumentException("Sin cliente: " + recibo.getNumero());
        }
    }
}
'@
  RemesaCalculador = @'
package com.acme.recibos;

public class RemesaCalculador {

    public boolean esUrgente(Remesa remesa) {
        return remesa.getDias() >= 30 && remesa.isActiva();
    }

    public Cliente buscar(String codigo) {
        return repositorio.buscar(codigo);
    }
}
'@
  Recibo = @'
package com.acme.recibos;

public class Recibo {
    private long importe;
}
'@
}
# Los datos de las fichas (cada uno con su clase, tipo, linea en el migrado y cita) y el orden en que van en cada ficha.
$Datos35 = [ordered]@{
  importe = @{ Clase = 'ReciboValidator'; Tipo = 'regla'; Linea = 6; Cita = 'if (recibo.getImporte() <= 0) {'; Texto = 'El importe tiene que ser mayor que cero.' }
  cliente = @{ Clase = 'ReciboValidator'; Tipo = 'regla'; Linea = 9; Cita = 'if (recibo.getCliente() == null) {'; Texto = 'Todo recibo lleva cliente.' }
  error = @{ Clase = 'ReciboValidator'; Tipo = 'error'; Linea = 7; Cita = 'throw new IllegalArgumentException("Recibo invalido: " + recibo.getNumero());'; Texto = 'Un recibo que no vale lanza una excepcion.' }
  plazo = @{ Clase = 'ReciboValidator'; Tipo = 'regla'; Linea = 0; Cita = ''; Texto = 'El recibo no puede estar fuera de plazo.' }
  urgente = @{ Clase = 'RemesaCalculador'; Tipo = 'regla'; Linea = 6; Cita = 'return remesa.getDias() >= 30 && remesa.isActiva();'; Texto = 'Una remesa activa con 30 dias o mas es urgente.' }
  buscar = @{ Clase = 'RemesaCalculador'; Tipo = 'regla'; Linea = 10; Cita = 'return repositorio.buscar(codigo);'; Texto = 'El cliente se busca por su codigo.' }
}
$Fichas35 = [ordered]@{
  'clase-1-validator' = @('ReciboValidator', @('importe', 'cliente', 'error', 'plazo'))
  'clase-2-calculador' = @('RemesaCalculador', @('urgente', 'buscar'))
}

# Lo que pone el script que carga tests-reglas.ps1 (migracion.ps1) y aqui se simula: el estado, su guardado y la parada.
$Estado = [ordered]@{ fase = '' }
$script:Paradas = @()
function Save-Estado { }
function Save-Informes { }
function Set-Parada([string]$Motivo, [string]$Detalle, [string]$Registro) { $script:Paradas += , @($Motivo, $Detalle, $Registro) }

# ============================== UTILIDADES ==============================
function Lee-Json([string]$Ruta) {
  if (-not (Test-Path -LiteralPath $Ruta -PathType Leaf)) { return $null }
  return ([System.IO.File]::ReadAllText($Ruta) | ConvertFrom-Json)
}

function Llamadas-De([string]$Fichero) {
  if (-not (Test-Path -LiteralPath $Fichero)) { return , @() }
  return , @([System.IO.File]::ReadAllLines($Fichero) | Where-Object { $_ })
}

# Un escenario: el migrado (repo git con las tres clases y un pom), las fichas y las comparaciones de $Igual (las reglas que la comparacion da por
# iguales; las demas salen distintas) en datos\. $Opc: Desplaza (suma a la linea de cada dato en la comparacion), Fichero (otra ruta para
# el fichero de cada dato en la comparacion), Extra (ruta -> texto: ficheros que ya estan en el migrado) y Fuentes (nombre de clase -> texto).
function Nuevo-Escenario35([string]$Nombre, [string[]]$Igual = @('importe', 'cliente', 'urgente'), [hashtable]$Opc = @{}) {
  $r = Join-Path $Dir $Nombre
  if (Test-Path -LiteralPath $r) { Remove-Item -LiteralPath $r -Recurse -Force }
  $mig = Join-Path $r 'migrado'
  Escribe $mig 'pom.xml' "<project><modelVersion>4.0.0</modelVersion><groupId>com.acme</groupId><artifactId>recibos</artifactId><version>1</version></project>`n"
  foreach ($c in $Fuentes35.Keys) {
    $fuente = $Fuentes35[$c]
    if ($Opc.Fuentes -and $Opc.Fuentes.ContainsKey($c)) { $fuente = $Opc.Fuentes[$c] }
    Escribe $mig "$Ruta35$c.java" $fuente
  }
  if ($Opc.Extra) { foreach ($k in $Opc.Extra.Keys) { Escribe $mig $k $Opc.Extra[$k] } }
  Inicia-Repo $mig
  Set-Excluidos $mig
  foreach ($d in @('datos/fichas', 'datos/comparacion', 'registros')) { [void](New-Item -ItemType Directory -Path (Get-Ruta $r $d) -Force) }
  $desplaza = 0
  if ($Opc.Desplaza) { $desplaza = [int]$Opc.Desplaza }
  foreach ($id in $Fichas35.Keys) {
    $clase = $Fichas35[$id][0]
    $claves = @($Fichas35[$id][1])
    $datos = @()
    $comp = @()
    for ($i = 0; $i -lt $claves.Count; $i++) {
      $d = $Datos35[$claves[$i]]
      $datos += , ([ordered]@{ tipo = $d.Tipo; texto = $d.Texto; linea = ($d.Linea + 25); cita = $d.Cita })
      $estado = 'distinto'
      if ($claves[$i] -ceq 'error' -or $Igual -contains $claves[$i]) { $estado = 'igual' }
      if ($claves[$i] -ceq 'plazo') { $estado = 'falta' }
      $fichero = "$Ruta35$clase.java"
      if ($Opc.Fichero) { $fichero = $Opc.Fichero }
      $linea = $d.Linea + $desplaza
      if ($estado -ceq 'falta') { $fichero = ''; $linea = 0 }
      else {
        $texto = @([System.IO.File]::ReadAllLines((Get-Ruta $mig "$Ruta35$clase.java")))[$d.Linea - 1]
        if ($texto.Trim() -cne $d.Cita) { throw "El dato $($claves[$i]) no esta en la linea $($d.Linea) de $clase`: '$texto'" }
      }
      $comp += , ([ordered]@{ dato = $i; estado = $estado; fichero = $fichero; linea = $linea; cita = $d.Cita; nota = ''; probado = $true })
    }
    Write-Json (Get-Ruta $r "datos/fichas/$id.json") ([ordered]@{ id = $id; fichero = "src/main/java/com/acme/$clase.java"; clase = $clase; papel = 'validador'; queHace = 'Comprueba recibos.'; datos = $datos })
    Write-Json (Get-Ruta $r "datos/comparacion/$id.json") ([ordered]@{ ficha = $id; clase = $clase; ficheroOriginal = "src/main/java/com/acme/$clase.java"; migrado = @("$Ruta35$clase.java"); momento = 'despues-de-corregir'; commit = 'abc1234'; datos = $comp })
  }
  return [pscustomobject]@{
    Raiz = $r; Repo = $mig; Datos = (Join-Path $r 'datos'); Registros = (Join-Path $r 'registros')
    Mvn = (Join-Path $r 'mvn-llamadas.txt'); Copilot = (Join-Path $r 'copilot-llamadas.txt')
  }
}

$Aj35 = @{
  MvnExe = (Join-Path $falsos 'm35-mvn.ps1'); CopilotExe = (Join-Path $falsos 'm35-copilot.ps1')
  FallosSeguidos = 3; SegundosPorLlamada = 60; SegundosLatido = 0
}

# Corre $Bloque con los falsos y los ajustes de $Ajustes en $Cfg y las variables de entorno de $Entorno; al salir deja todo como estaba.
function Con-Falso35([hashtable]$Entorno, [hashtable]$Ajustes, [scriptblock]$Bloque) {
  $todo = @{}
  foreach ($k in $Aj35.Keys) { $todo[$k] = $Aj35[$k] }
  foreach ($k in $Ajustes.Keys) { $todo[$k] = $Ajustes[$k] }
  $cfgAntes = @{}
  foreach ($k in $todo.Keys) { $cfgAntes[$k] = $Cfg[$k]; $Cfg[$k] = $todo[$k] }
  $envAntes = @{}
  foreach ($k in $Entorno.Keys) { $envAntes[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $Entorno[$k]) }
  try { return (& $Bloque) }
  finally {
    foreach ($k in $Entorno.Keys) { [Environment]::SetEnvironmentVariable($k, $envAntes[$k]) }
    foreach ($k in $cfgAntes.Keys) { $Cfg[$k] = $cfgAntes[$k] }
  }
}

# Invoke-FaseReglas sobre el escenario, con los falsos y las variables del script que la carga. Devuelve lo que dijo (Sigue), la consola (Texto y
# Avisos), el JSON de resultados, las tareas guardadas y los commits del migrado (el asunto de cada uno, el ultimo primero).
function Fase35($E, [hashtable]$Entorno = @{}, [hashtable]$Cambios = @{}, [bool]$Mantener = $true) {
  $Entorno['M35_LLAMADAS'] = $E.Mvn
  $Entorno['M35_COPILOT'] = $E.Copilot
  $RepoRoot = $E.Repo
  $Datos = $E.Datos
  $Registros = $E.Registros
  $ModeloElegido = 'modelo-x'
  $script:Parada = $false
  $script:Paradas = @()
  $script:Todas = @()
  $salida = @(Con-Falso35 $Entorno $Cambios { Invoke-FaseReglas $Mantener } 6>&1)
  $info = @($salida | Where-Object { $_ -is [System.Management.Automation.InformationRecord] })
  $tareas = @()
  if (Test-Path -LiteralPath (Join-Path $E.Datos 'tareas')) { $tareas = @(Get-ChildItem -LiteralPath (Join-Path $E.Datos 'tareas') -Filter '*.json' | ForEach-Object { Lee-Json $_.FullName }) }
  return [pscustomobject]@{
    Sigue = (@($salida | Where-Object { $_ -is [bool] })[0])
    Texto = (@($info | ForEach-Object { "$_" }) -join "`n")
    Avisos = @($info | Where-Object { "$($_.MessageData.ForegroundColor)" -ceq 'Yellow' } | ForEach-Object { "$_" })
    Json = (Lee-Json (Join-Path $E.Datos 'tests-reglas.json'))
    Tareas = $tareas
    Commits = @((GitEn $E.Repo @('log', '--format=%s')) -split "`n")
  }
}

function Tarea35($X, [string]$Clase) { return @($X.Tareas | Where-Object { $_.entradas.clase -ceq $Clase })[0] }
function Fila35($X, [string]$Clase) { return @($X.Json.tareas | Where-Object { $_.clase -ceq $Clase })[0] }
function Regla35($Fila, [string]$Texto) { return @($Fila.reglas | Where-Object { $_.texto -ceq $Texto })[0] }
function Estado-Git35($E) { return (GitEn $E.Repo @('status', '--short')) }
function Test-De([string]$Clase) { return "$Test35${Clase}ReglasTest.java" }
# src/main queda como lo escribio la prueba (byte a byte)
function Main-Igual35($E) {
  foreach ($c in $Fuentes35.Keys) {
    if ((Lee $E.Repo "$Ruta35$c.java") -cne $Fuentes35[$c]) { return $false }
  }
  return $true
}
function Compilaciones35($E) {
  $todas = Llamadas-De $E.Mvn
  return @($todas | Where-Object { $_ -match '\|-B test-compile\|' })
}
# Las llamadas 'test' de una clase de test: de cada una, las lineas de src/main que habia cambiadas (vacio si la llamada va sin mutante).
function Corridas35($E, [string]$Clase) {
  $todas = Llamadas-De $E.Mvn
  return @($todas | Where-Object { $_ -match ('\|-B test -Dtest=' + $Clase + 'ReglasTest ') } | ForEach-Object { ($_ -split '\|', 3)[2].Trim() })
}

# ================================ PRUEBAS ================================
$Pruebas = [ordered]@{}

$Pruebas['1 a) dos clases con reglas y tests buenos: un commit por test, src/main byte a byte igual y cada regla vigilada'] = {
  $E = Nuevo-Escenario35 'a'
  $x = Fase35 $E
  Igual 'la fase deja seguir' $true $x.Sigue
  Igual 'ninguna parada' 0 $script:Paradas.Count
  Igual 'los commits: uno por test, en orden' ("$Commit35$(Test-De 'RemesaCalculador')|$Commit35$(Test-De 'ReciboValidator')|inicial") ($x.Commits -join '|')
  Igual 'el ultimo commit solo toca su test' (Test-De 'RemesaCalculador') ((GitEn $E.Repo @('show', '--name-only', '--format=', 'HEAD')) -split "`n" -join '|')
  Igual 'el anterior, el suyo' (Test-De 'ReciboValidator') ((GitEn $E.Repo @('show', '--name-only', '--format=', 'HEAD~1')) -split "`n" -join '|')
  Igual 'src/main queda byte a byte igual' $true (Main-Igual35 $E)
  Igual 'el worktree queda limpio' '' (Estado-Git35 $E)
  foreach ($c in @('ReciboValidator', 'RemesaCalculador')) {
    $t = Tarea35 $x $c
    Igual "$c`: tarea hecha" 'hecha' $t.estado
    Igual "$c`: con un solo intento" 1 $t.intentos
    Comprueba "$c`: el test esta en el migrado" (Test-Path -LiteralPath (Get-Ruta $E.Repo (Test-De $c)))
  }
  Igual 'dos llamadas a Copilot' 2 (Llamadas-De $E.Copilot).Count
  $j = $x.Json
  Comprueba 'existe datos/tests-reglas.json' ($null -ne $j)
  if ($null -eq $j) { return }
  Igual 'JSON: dos clases con test' 2 $j.conTest
  Igual 'JSON: tres reglas vigiladas' 3 $j.reglasVigiladas
  $v = Fila35 $x 'ReciboValidator'
  Igual 'ReciboValidator: hecha' 'hecha' $v.estado
  Igual 'ReciboValidator: su commit' (GitEn $E.Repo @('rev-parse', 'HEAD~1')) $v.commit
  Igual 'ReciboValidator: su test' (Test-De 'ReciboValidator') $v.test
  Igual 'ReciboValidator: dos reglas' 2 @($v.reglas).Count
  Igual 'importe: vigilada' 'vigilada' (Regla35 $v 'El importe tiene que ser mayor que cero.').resultado
  Igual 'cliente: vigilada' 'vigilada' (Regla35 $v 'Todo recibo lleva cliente.').resultado
  Igual 'importe: con su linea' 6 (Regla35 $v 'El importe tiene que ser mayor que cero.').linea
  Igual 'urgente: vigilada' 'vigilada' (Regla35 (Fila35 $x 'RemesaCalculador') 'Una remesa activa con 30 dias o mas es urgente.').resultado
  Comprueba 'la consola dice los numeros' ($x.Texto -match '(?m)^Tests de reglas: 2 clases con test \(3 reglas vigiladas\), 0 atascadas, 0 saltadas\s*$') $x.Texto
  # Maven: la foto y la ronda entera (2 compilaciones); por clase, la corrida sin cambio y una mutante por regla con el primer cambio de la lista
  Igual 'Maven: dos compilaciones (la de antes de empezar y la de la ronda)' 2 (Compilaciones35 $E).Count
  $cv = @(Corridas35 $E 'ReciboValidator')
  Igual 'ReciboValidator: tres corridas (sin cambio y dos mutantes)' 3 $cv.Count
  if ($cv.Count -eq 3) {
    Igual 'la primera, sin cambio' '' $cv[0]
    Igual 'importe: <= pasa a >' 'if (recibo.getImporte() > 0) {' $cv[1].Trim()
    Igual 'cliente: == pasa a !=' 'if (recibo.getCliente() != null) {' $cv[2].Trim()
  }
  $cc = @(Corridas35 $E 'RemesaCalculador')
  Igual 'RemesaCalculador: dos corridas (sin cambio y un mutante)' 2 $cc.Count
  if ($cc.Count -eq 2) { Igual 'urgente: >= pasa a <' 'return remesa.getDias() < 30 && remesa.isActiva();' $cc[1].Trim() }
}

$Pruebas['1b a2) src/main con CRLF y un byte que no es UTF-8: tras los mutantes queda byte a byte igual'] = {
  $fuente = ($Fuentes35['ReciboValidator'] -replace "`r?`n", "`r`n")
  $E = Nuevo-Escenario35 'a2' @('importe', 'cliente') @{ Fuentes = @{ ReciboValidator = $fuente } }
  # un byte E9 suelto (una e con acento en ISO-8859-1) en un comentario de la ultima linea
  $ruta = Get-Ruta $E.Repo "${Ruta35}ReciboValidator.java"
  $bytes = [System.IO.File]::ReadAllBytes($ruta)
  [System.IO.File]::WriteAllBytes($ruta, ($bytes + [byte[]](0x2F, 0x2F, 0xE9, 0x0D, 0x0A)))
  [void](GitEn $E.Repo @('commit', '-q', '-a', '-m', 'con byte raro'))
  $antes = [System.IO.File]::ReadAllBytes($ruta)
  $x = Fase35 $E
  Igual 'el test de ReciboValidator se commitea' "$Commit35$(Test-De 'ReciboValidator')" $x.Commits[0]
  $despues = [System.IO.File]::ReadAllBytes($ruta)
  Igual 'el fichero mide lo mismo' $antes.Length $despues.Length
  Comprueba 'byte a byte igual' ([System.Convert]::ToBase64String($antes) -ceq [System.Convert]::ToBase64String($despues))
  Igual 'el worktree queda limpio' '' (Estado-Git35 $E)
  $cv = @(Corridas35 $E 'ReciboValidator')
  Igual 'tres corridas' 3 $cv.Count
  if ($cv.Count -eq 3) { Igual 'el mutante de importe conserva el resto de la linea' 'if (recibo.getImporte() > 0) {' $cv[1].Trim() }
}

$Pruebas['2 b) un test que no vigila una regla: el mutante pasa, reintento con el motivo y atascada a la segunda'] = {
  $E = Nuevo-Escenario35 'b'
  $x = Fase35 $E @{ RESCATE_FALSO = 'parcial:ReciboValidator' }
  Igual 'la fase deja seguir (una atascada no para)' $true $x.Sigue
  Igual 'ninguna parada' 0 $script:Paradas.Count
  Igual 'solo se commitea el test de RemesaCalculador' ("$Commit35$(Test-De 'RemesaCalculador')|inicial") ($x.Commits -join '|')
  Igual 'src/main queda byte a byte igual' $true (Main-Igual35 $E)
  Igual 'el worktree queda limpio' '' (Estado-Git35 $E)
  Comprueba 'el test rechazado no se queda en el migrado' (-not (Test-Path -LiteralPath (Get-Ruta $E.Repo (Test-De 'ReciboValidator'))))
  $t = Tarea35 $x 'ReciboValidator'
  Igual 'ReciboValidator: atascada' 'atascada' $t.estado
  Igual 'ReciboValidator: dos intentos' 2 $t.intentos
  $motivo = 'Tu test no falla si en la linea 9 cambio `==` por `!=`: no comprueba la regla "Todo recibo lleva cliente."'
  Comprueba 'el motivo dice la linea, el cambio y la regla' ($t.motivo.Contains($motivo)) $t.motivo
  Comprueba 'el motivo no habla de la regla que si vigila' (-not $t.motivo.Contains('mayor que cero'))
  $log = Lee $E.Registros ($t.id + '-2.log')
  Comprueba 'el segundo prompt lleva la correccion con el motivo' ($log -match 'CORRECCI' -and $log.Contains($motivo)) $log
  Comprueba 'el primer prompt no la lleva' ((Lee $E.Registros ($t.id + '-1.log')) -notmatch 'CORRECCI')
  Igual 'tres llamadas a Copilot: las dos clases y el reintento' 3 (Llamadas-De $E.Copilot).Count
  Comprueba 'avisa de la atascada con su clase' (@($x.Avisos | Where-Object { $_ -match ('Atascada: ' + [regex]::Escape((Test-De 'ReciboValidator'))) }).Count -eq 1) ($x.Avisos -join ' / ')
  $f = Fila35 $x 'ReciboValidator'
  Igual 'JSON: atascada' 'atascada' $f.estado
  Igual 'JSON: sin commit' '' $f.commit
  Igual 'JSON: importe vigilada' 'vigilada' (Regla35 $f 'El importe tiene que ser mayor que cero.').resultado
  $c = Regla35 $f 'Todo recibo lleva cliente.'
  Igual 'JSON: cliente no-vigilada' 'no-vigilada' $c.resultado
  Comprueba 'JSON: con su motivo' ($c.motivo.Contains($motivo)) $c.motivo
  Comprueba 'la consola dice los numeros' ($x.Texto -match '(?m)^Tests de reglas: 1 clases con test \(1 reglas vigiladas\), 1 atascadas, 0 saltadas\s*$') $x.Texto
  # las corridas del primer intento y las del reintento: sin cambio y dos mutantes, dos veces
  Igual 'ReciboValidator: seis corridas (dos intentos de tres)' 6 @(Corridas35 $E 'ReciboValidator').Count
}

$Pruebas['3 b2) el primer intento no vigila una regla y el reintento, con el motivo, si: hecha con dos intentos'] = {
  $E = Nuevo-Escenario35 'b2'
  $x = Fase35 $E @{ RESCATE_FALSO = 'parcial1:ReciboValidator' }
  Igual 'los dos commits: el de RemesaCalculador en la primera ronda y el de ReciboValidator en el reintento' ("$Commit35$(Test-De 'ReciboValidator')|$Commit35$(Test-De 'RemesaCalculador')|inicial") ($x.Commits -join '|')
  $t = Tarea35 $x 'ReciboValidator'
  Igual 'ReciboValidator: hecha' 'hecha' $t.estado
  Igual 'ReciboValidator: dos intentos' 2 $t.intentos
  Igual 'sin avisos de atascadas' 0 @($x.Avisos | Where-Object { $_ -match 'Atascada' }).Count
  Igual 'src/main queda byte a byte igual' $true (Main-Igual35 $E)
  Igual 'las dos reglas, vigiladas en el JSON' 2 @((Fila35 $x 'ReciboValidator').reglas | Where-Object { $_.resultado -ceq 'vigilada' }).Count
}

$Pruebas['4 c) un test con @SpringBootTest se rechaza con su motivo, sin compilarlo ni lanzarlo'] = {
  $E = Nuevo-Escenario35 'c'
  $x = Fase35 $E @{ RESCATE_FALSO = 'spring:ReciboValidator' }
  Igual 'solo se commitea el de RemesaCalculador' ("$Commit35$(Test-De 'RemesaCalculador')|inicial") ($x.Commits -join '|')
  Igual 'el worktree queda limpio' '' (Estado-Git35 $E)
  $t = Tarea35 $x 'ReciboValidator'
  Igual 'ReciboValidator: atascada tras dos intentos' 'atascada' $t.estado
  Comprueba 'el motivo dice @SpringBootTest' ($t.motivo -match '@SpringBootTest') $t.motivo
  Igual 'ni una corrida de Maven de su test' 0 @(Corridas35 $E 'ReciboValidator').Count
  # la de antes de empezar y la de RemesaCalculador sola (la del reintento de ReciboValidator no llega a compilar)
  Igual 'Maven: dos compilaciones' 2 (Compilaciones35 $E).Count
  Igual 'JSON: sin reglas comprobadas en la atascada' 0 @((Fila35 $x 'ReciboValidator').reglas | Where-Object { $_.resultado -ceq 'vigilada' }).Count
}

$Pruebas['5 d) un test que no compila: la ronda cae a de uno en uno y el otro se acepta'] = {
  $E = Nuevo-Escenario35 'd'
  $x = Fase35 $E @{ RESCATE_FALSO = 'no-compila:ReciboValidator' }
  Igual 'la fase deja seguir' $true $x.Sigue
  Igual 'solo se commitea el de RemesaCalculador' ("$Commit35$(Test-De 'RemesaCalculador')|inicial") ($x.Commits -join '|')
  Igual 'el worktree queda limpio' '' (Estado-Git35 $E)
  Comprueba 'lo dice: la ronda no compila y se prueba de uno en uno' ($x.Texto -match 'de uno en uno') $x.Texto
  $t = Tarea35 $x 'ReciboValidator'
  Igual 'ReciboValidator: atascada tras dos intentos' 'atascada' $t.estado
  Comprueba 'el motivo es que no compila, con la linea de Maven' ($t.motivo -match 'No compila' -and $t.motivo -match 'ReciboValidatorReglasTest\.java') $t.motivo
  Igual 'RemesaCalculador: hecha' 'hecha' (Tarea35 $x 'RemesaCalculador').estado
  # la de antes (1) + la ronda entera (1) + cada test solo (2) + el reintento, que va solo (1)
  Igual 'Maven: 5 compilaciones' 5 (Compilaciones35 $E).Count
  Igual 'el que no compila no llega a lanzarse' 0 @(Corridas35 $E 'ReciboValidator').Count
}

$Pruebas['6 e) la IA toca ficheros de src/main: se deshace y su test se prueba igual'] = {
  $E = Nuevo-Escenario35 'e'
  $x = Fase35 $E @{ RESCATE_FALSO = 'otro:ReciboValidator' }
  Igual 'la fase deja seguir' $true $x.Sigue
  Igual 'los dos commits' ("$Commit35$(Test-De 'RemesaCalculador')|$Commit35$(Test-De 'ReciboValidator')|inicial") ($x.Commits -join '|')
  Igual 'src/main queda byte a byte igual' $true (Main-Igual35 $E)
  Igual 'el worktree queda limpio' '' (Estado-Git35 $E)
  Comprueba 'lo dice con Info y las rutas deshechas' ($x.Texto.Contains('Deshago lo que la IA ha tocado fuera de lo suyo:') -and $x.Texto.Contains("${Ruta35}Recibo.java") -and $x.Texto.Contains("${Ruta35}ReciboValidator.java")) $x.Texto
  Igual 'el commit solo lleva su test' (Test-De 'ReciboValidator') ((GitEn $E.Repo @('show', '--name-only', '--format=', 'HEAD~1')) -split "`n" -join '|')
  Igual 'ReciboValidator: hecha con un intento' 1 (Tarea35 $x 'ReciboValidator').intentos
  Comprueba 'las corridas de su test no llevaban lo que toco la IA' ((@(Corridas35 $E 'ReciboValidator') | Select-Object -First 1) -ceq '')
}

$Pruebas['6b e2) la IA deja sus cambios en el indice con git add: se ven igual, se deshace lo ajeno y lo suyo se acepta'] = {
  $E = Nuevo-Escenario35 'e2'
  $x = Fase35 $E @{ RESCATE_FALSO = 'otro-add:ReciboValidator' }
  Igual 'los dos commits' ("$Commit35$(Test-De 'RemesaCalculador')|$Commit35$(Test-De 'ReciboValidator')|inicial") ($x.Commits -join '|')
  Igual 'src/main queda byte a byte igual' $true (Main-Igual35 $E)
  Igual 'ni el indice ni el worktree llevan nada' '' (Estado-Git35 $E)
  Igual 'el commit solo lleva su test' (Test-De 'ReciboValidator') ((GitEn $E.Repo @('show', '--name-only', '--format=', 'HEAD~1')) -split "`n" -join '|')
}

$Pruebas['7 f) una regla sin operadores que cambiar: sin-mutante, y la clase se acepta si otra regla esta vigilada'] = {
  $E = Nuevo-Escenario35 'f' @('importe', 'urgente', 'buscar')
  $x = Fase35 $E
  Igual 'los dos commits' ("$Commit35$(Test-De 'RemesaCalculador')|$Commit35$(Test-De 'ReciboValidator')|inicial") ($x.Commits -join '|')
  $f = Fila35 $x 'RemesaCalculador'
  Igual 'RemesaCalculador: hecha' 'hecha' $f.estado
  Igual 'urgente: vigilada' 'vigilada' (Regla35 $f 'Una remesa activa con 30 dias o mas es urgente.').resultado
  $b = Regla35 $f 'El cliente se busca por su codigo.'
  Igual 'buscar: sin-mutante' 'sin-mutante' $b.resultado
  Comprueba 'buscar: con su motivo' ($b.motivo -match 'ningun cambio' -and $b.motivo -match '10') $b.motivo
  Igual 'dos corridas: sin cambio y el mutante de la otra regla' 2 @(Corridas35 $E 'RemesaCalculador').Count
  Comprueba 'la consola cuenta solo las vigiladas (2)' ($x.Texto -match 'Tests de reglas: 2 clases con test \(2 reglas vigiladas\), 0 atascadas, 0 saltadas') $x.Texto
}

$Pruebas['7b f2) una clase cuyas reglas no tienen ningun operador que cambiar: se salta sin llamar a Copilot'] = {
  $E = Nuevo-Escenario35 'f2' @('buscar')
  $x = Fase35 $E
  Igual 'la fase deja seguir' $true $x.Sigue
  Igual 'ninguna llamada a Copilot' 0 (Llamadas-De $E.Copilot).Count
  Igual 'ninguna llamada a Maven' 0 (Llamadas-De $E.Mvn).Count
  Igual 'ningun commit' 'inicial' ($x.Commits -join '|')
  $f = Fila35 $x 'RemesaCalculador'
  Igual 'JSON: saltada' 'saltada' $f.estado
  Comprueba 'JSON: con su motivo' ($f.motivo -match 'ningun cambio') $f.motivo
  Comprueba 'la consola dice la saltada' ($x.Texto -match '(?m)^Tests de reglas: 0 clases con test \(0 reglas vigiladas\), 0 atascadas, 1 saltadas\s*$') $x.Texto
}

$Pruebas['8 g) relanzar no repite las tareas hechas; con una atascada, tampoco salvo con -Reintentar'] = {
  $E = Nuevo-Escenario35 'g'
  [void](Fase35 $E @{ RESCATE_FALSO = 'parcial:ReciboValidator' })
  $copias = (Llamadas-De $E.Copilot).Count
  $mvn = (Llamadas-De $E.Mvn).Count
  $hash = (GitEn $E.Repo @('rev-parse', 'HEAD'))
  $x = Fase35 $E @{ RESCATE_FALSO = 'parcial:ReciboValidator' }
  Igual 'la fase deja seguir' $true $x.Sigue
  Igual 'ninguna llamada nueva a Copilot' $copias (Llamadas-De $E.Copilot).Count
  Igual 'ninguna llamada nueva a Maven' $mvn (Llamadas-De $E.Mvn).Count
  Igual 'ningun commit nuevo' $hash (GitEn $E.Repo @('rev-parse', 'HEAD'))
  Igual 'la hecha sigue hecha' 'hecha' (Tarea35 $x 'RemesaCalculador').estado
  Igual 'la atascada sigue atascada' 'atascada' (Tarea35 $x 'ReciboValidator').estado
  Comprueba 'la consola sigue diciendo lo mismo' ($x.Texto -match 'Tests de reglas: 1 clases con test \(1 reglas vigiladas\), 1 atascadas, 0 saltadas') $x.Texto
  Igual 'el JSON sigue con el commit de la hecha' (GitEn $E.Repo @('rev-parse', 'HEAD')) (Fila35 $x 'RemesaCalculador').commit
  $x = Fase35 $E @{} @{} $false
  Igual 'con -Reintentar, la atascada vuelve a intentarse: una llamada nueva' ($copias + 1) (Llamadas-De $E.Copilot).Count
  Igual 'y ahora queda hecha' 'hecha' (Tarea35 $x 'ReciboValidator').estado
  Igual 'con su commit' "$Commit35$(Test-De 'ReciboValidator')" $x.Commits[0]
}

$Pruebas['9 g2) migracion.ps1: -Reglas es un switch y la fase solo se llama con el, despues de practicas y antes de la prueba en local'] = {
  $t = [System.IO.File]::ReadAllText((Join-Path $raiz 'migracion.ps1'))
  Comprueba 'parametro [switch]$Reglas' ($t -match '(?m)^\s*\[switch\]\$Reglas\b')
  Comprueba 'carga tests-reglas.ps1 junto a los demas' ($t -match "(?m)^\. \(Join-Path \`$PSScriptRoot 'tests-reglas\.ps1'\)")
  Comprueba 'la ayuda lo dice en el USO' ($t -match '(?m)^\s+\.\\migracion\.ps1 \.\.\. -Reglas\b')
  Comprueba 'la ayuda describe la fase' ($t -match '(?m)^\s+reglas\s+solo con -Reglas')
  Comprueba 'la cabecera nombra el fichero' ($t -match 'Necesita [^\r\n]*tests-reglas\.ps1')
  $llamadas = @([regex]::Matches($t, '(?m)^.*Invoke-FaseReglas.*$'))
  Igual 'la fase se llama en un solo sitio' 1 $llamadas.Count
  if ($llamadas.Count -ne 1) { return }
  Comprueba 'esa llamada solo vale con $Reglas' ($llamadas[0].Value -match 'if \(\$sigue -and \$Reglas\)') $llamadas[0].Value
  $prac = $t.LastIndexOf('Invoke-FasePracticas')
  $prueba = $t.LastIndexOf('Invoke-FasePruebaLocal')
  Comprueba 'va despues de practicas y antes de la prueba en local' ($prac -ge 0 -and $prac -lt $llamadas[0].Index -and $llamadas[0].Index -lt $prueba)
}

$Pruebas['10 h) Get-MutanteLinea: cada cambio de la lista aplicado a una linea de ejemplo'] = {
  $casos = @(
    @('==', '        if (a == b) {', '        if (a != b) {'),
    @('!=', '        if (a != b) {', '        if (a == b) {'),
    @('>=', '        if (x >= 10) {', '        if (x < 10) {'),
    @('<=', '        if (x <= 10) {', '        if (x > 10) {'),
    @('>', '        if (x > 10) {', '        if (x <= 10) {'),
    @('<', '        if (x < 10) {', '        if (x >= 10) {'),
    @('&&', '        if (a && b) {', '        if (a || b) {'),
    @('||', '        if (a || b) {', '        if (a && b) {'),
    @('true', '        return true;', '        return false;'),
    @('false', '        return false;', '        return true;'),
    @('! delante de un nombre', '        if (!found) {', '        if (found) {'),
    @('! delante de una llamada', '        if (!lista.isEmpty()) {', '        if (lista.isEmpty()) {'),
    @('! delante de un parentesis', '        if (!(esValido(x))) {', '        if ((esValido(x))) {'),
    @('if ( sin operador: una llamada', '        if (lista.isEmpty()) {', '        if (!lista.isEmpty()) {'),
    @('if ( sin operador: un equals', '        if ("A".equals(tipo)) {', '        if (!"A".equals(tipo)) {'),
    @('if ( sin operador: una llamada a un fichero', '        if (fichero.exists()) {', '        if (!fichero.exists()) {'),
    @('if ( sin operador: un nombre', '        if (found) {', '        if (!found) {'),
    @('else if ( sin operador', '        } else if (esUrgente) {', '        } else if (!esUrgente) {'),
    @('while ( sin operador', '        while (it.hasNext()) {', '        while (!it.hasNext()) {'),
    @('if( pegado al parentesis', '        if(lista.isEmpty()) {', '        if(!lista.isEmpty()) {')
  )
  foreach ($c in $casos) {
    $m = Get-MutanteLinea $c[1]
    Comprueba "$($c[0]): '$($c[1].Trim())'" ($null -ne $m -and $m.Linea -ceq $c[2]) ("hay '" + $(if ($m) { $m.Linea } else { '(nada)' }) + "'")
  }
  # el primer cambio que aplica va en el orden de la lista, no en el de la linea
  Igual 'orden: >= antes que &&' '        if (a && x < 10) {' (Get-MutanteLinea '        if (a && x >= 10) {').Linea
  Igual 'orden: > antes que &&' '        if (x <= 3 && b) {' (Get-MutanteLinea '        if (x > 3 && b) {').Linea
  Igual 'orden: == antes que !' '        if (!a != b) {' (Get-MutanteLinea '        if (!a == b) {').Linea
  Igual 'orden: && antes que ||' '        if (a || b || c) {' (Get-MutanteLinea '        if (a && b || c) {').Linea
  Igual 'orden: || antes que true' '        return a && true;' (Get-MutanteLinea '        return a || true;').Linea
  Igual 'orden: true antes que !' '        vistos = !seen.add(false);' (Get-MutanteLinea '        vistos = !seen.add(true);').Linea
  # el cambio de if ( y while ( es el ultimo: solo si no aplica ninguno de los otros
  Igual 'orden: == antes que if (' '        if (a != b) {' (Get-MutanteLinea '        if (a == b) {').Linea
  Igual 'orden: == antes que if (: lo que cambia' '==' (Get-MutanteLinea '        if (a == b) {').Antes
  Igual 'orden: && antes que while (' '        while (a || b) {' (Get-MutanteLinea '        while (a && b) {').Linea
  Igual 'orden: true antes que if (' '        if (flag.get(false)) {' (Get-MutanteLinea '        if (flag.get(true)) {').Linea
  Igual 'orden: ! antes que if (: quita el !' '        if (found) {' (Get-MutanteLinea '        if (!found) {').Linea
  Igual 'orden: ! antes que if (: lo que cambia' '!' (Get-MutanteLinea '        if (!found) {').Antes
  Igual 'orden: ! antes que if (: con espacio' '        if ( found) {' (Get-MutanteLinea '        if ( !found) {').Linea
  $m = Get-MutanteLinea '        if (lista.isEmpty()) {'
  Igual 'if (: Antes' 'if (' $m.Antes
  Igual 'if (: Despues' 'if (!' $m.Despues
  $m = Get-MutanteLinea '        while (it.hasNext()) {'
  Igual 'while (: Antes' 'while (' $m.Antes
  Igual 'while (: Despues' 'while (!' $m.Despues
  Igual 'if ( dentro de un texto no cuenta' $null (Get-MutanteLinea '        log.info("if (lista.isEmpty())");')
  Igual 'if ( dentro de un comentario no cuenta' $null (Get-MutanteLinea '        // if (lista.isEmpty()) {')
  Igual 'una palabra que acaba en if no cuenta' $null (Get-MutanteLinea '        notif (x);')
  # el primero de la linea cuando hay varios iguales
  Igual 'el primero de dos ==' '        if (a != b && c == d) {' (Get-MutanteLinea '        if (a == b && c == d) {').Linea
  # lo que no es un operador de comparacion o logico
  foreach ($l in @('        return repositorio.buscar(codigo);', '        List<String> lista = new ArrayList<>();', '        x -> x.getId();', '        i++;', '        total += importe;', '        int y = x >> 2;', '        x = a ? b : c;', '    }', '', '        // si importe >= 0 y no es true', '        log.info("importe >= 0 && true");', "        char c = '!';", '        if (a!=b) { }')) {
    $m = Get-MutanteLinea $l
    $dice = '(nada)'
    if ($m) { $dice = $m.Linea }
    if ($l -ceq '        if (a!=b) { }') { Comprueba "'$($l.Trim())': != pegado a sus operandos tambien cuenta" ($null -ne $m -and $m.Linea -ceq '        if (a==b) { }') $dice }
    else { Comprueba "sin cambio: '$($l.Trim())'" ($null -eq $m) $dice }
  }
  # un lambda con -> no es un >, pero un > con espacios en la misma linea si
  Igual 'lambda con un > despues' '        lista.stream().filter(x -> x <= 0)' (Get-MutanteLinea '        lista.stream().filter(x -> x > 0)').Linea
  Igual 'sin cambiar los finales de linea (CRLF)' "        if (a && b) {`r" (Get-MutanteLinea "        if (a || b) {`r").Linea
  $m = Get-MutanteLinea '        if (x >= 10) {'
  Igual 'Antes' '>=' $m.Antes
  Igual 'Despues' '<' $m.Despues
  $m = Get-MutanteLinea '        if (!found) {'
  Igual 'quitar un !: Antes' '!' $m.Antes
  Igual 'quitar un !: Despues, vacio' '' $m.Despues
}

$Pruebas['11 i) un test que ya existe: la tarea se salta, sin llamar a Copilot'] = {
  $previo = "package com.acme.recibos;`n`nclass ReciboValidatorReglasTest { }`n"
  $E = Nuevo-Escenario35 'i' @('importe', 'cliente', 'urgente') @{ Extra = @{ (Test-De 'ReciboValidator') = $previo } }
  $x = Fase35 $E
  Igual 'solo se commitea el de RemesaCalculador' ("$Commit35$(Test-De 'RemesaCalculador')|inicial") ($x.Commits -join '|')
  Igual 'una sola llamada a Copilot' 1 (Llamadas-De $E.Copilot).Count
  Igual 'el test que ya estaba no se toca' $previo (Lee $E.Repo (Test-De 'ReciboValidator'))
  $f = Fila35 $x 'ReciboValidator'
  Igual 'JSON: saltada' 'saltada' $f.estado
  Comprueba 'JSON: dice que ya existe' ($f.motivo -match 'ya existe') $f.motivo
  Comprueba 'la consola dice la saltada' ($x.Texto -match 'Tests de reglas: 1 clases con test \(1 reglas vigiladas\), 0 atascadas, 1 saltadas') $x.Texto
}

$Pruebas['12 j) un migrado que no compila antes de empezar: parada con el fallo de Maven y sin llamadas a Copilot'] = {
  $E = Nuevo-Escenario35 'j'
  $x = Fase35 $E @{ M35_NO_COMPILA = 'getDias' }
  Igual 'la fase no deja seguir' $false $x.Sigue
  Igual 'una parada' 1 $script:Paradas.Count
  if ($script:Paradas.Count -ne 1) { return }
  Igual 'motivo no-compila' 'no-compila' $script:Paradas[0][0]
  Comprueba 'el detalle lleva el error de Maven' ($script:Paradas[0][1] -match 'COMPILATION ERROR' -and $script:Paradas[0][1] -match 'RemesaCalculador\.java') $script:Paradas[0][1]
  Comprueba 'el registro es el de Maven y existe' (Test-Path -LiteralPath $script:Paradas[0][2])
  Igual 'ninguna llamada a Copilot' 0 (Llamadas-De $E.Copilot).Count
}

$Pruebas['13 k) Copilot que falla varias veces seguidas: parada copilot-no-responde y las tareas vuelven a empezar'] = {
  $E = Nuevo-Escenario35 'k'
  $x = Fase35 $E @{ RESCATE_FALSO = 'falla' } @{ FallosSeguidos = 2 }
  Igual 'la fase no deja seguir' $false $x.Sigue
  Igual 'una parada' 1 $script:Paradas.Count
  if ($script:Paradas.Count -ne 1) { return }
  Igual 'motivo copilot-no-responde' 'copilot-no-responde' $script:Paradas[0][0]
  Igual 'ningun commit' 'inicial' ($x.Commits -join '|')
  Igual 'las tareas vuelven a pendiente y sin intentos' 2 @($x.Tareas | Where-Object { $_.estado -ceq 'pendiente' -and $_.intentos -eq 0 }).Count
  Igual 'el worktree queda limpio' '' (Estado-Git35 $E)
}

$Pruebas['13b k2) una llamada que falla despues de escribir el test: se borra y se atasca con el codigo de Copilot, sin parar a las demas'] = {
  $E = Nuevo-Escenario35 'k2'
  $x = Fase35 $E @{ RESCATE_FALSO = 'falla-cambia:ReciboValidator' }
  Igual 'la fase deja seguir' $true $x.Sigue
  Igual 'solo se commitea el de RemesaCalculador' ("$Commit35$(Test-De 'RemesaCalculador')|inicial") ($x.Commits -join '|')
  Igual 'el worktree queda limpio' '' (Estado-Git35 $E)
  $t = Tarea35 $x 'ReciboValidator'
  Igual 'ReciboValidator: atascada' 'atascada' $t.estado
  Comprueba 'el motivo es el codigo de Copilot' ($t.motivo -match 'Copilot salio con codigo 1') $t.motivo
}

$Pruebas['14 l) la IA no escribe el test o lo borra: invalida con su motivo; la IA hace un commit: se deshace'] = {
  $E = Nuevo-Escenario35 'l' @('importe', 'cliente')
  $x = Fase35 $E @{ RESCATE_FALSO = 'nada' }
  $t = Tarea35 $x 'ReciboValidator'
  Igual 'sin test: atascada' 'atascada' $t.estado
  Comprueba 'el motivo dice que falta el fichero' ($t.motivo -match 'No has escrito' -and $t.motivo.Contains((Test-De 'ReciboValidator'))) $t.motivo
  Igual 'ningun commit' 'inicial' ($x.Commits -join '|')
  $E = Nuevo-Escenario35 'l2' @('importe', 'cliente')
  $x = Fase35 $E @{ RESCATE_FALSO = 'commit' }
  Igual 'ningun commit de la IA ni de la fase' 'inicial' ($x.Commits -join '|')
  Igual 'el worktree queda limpio' '' (Estado-Git35 $E)
  $t = Tarea35 $x 'ReciboValidator'
  Igual 'con commit de la IA: atascada' 'atascada' $t.estado
  Comprueba 'el motivo dice que ha hecho un commit' ($t.motivo -match 'commit') $t.motivo
}

$Pruebas['15 m) un commit que git rechaza (un hook): parada git con su salida, el test borrado y la tarea sin gastar el intento'] = {
  $E = Nuevo-Escenario35 'm' @('importe', 'cliente')
  [void](GitEn $E.Repo @('config', 'core.hooksPath', '.git/hooks'))   # el global del usuario, si lo hay, no cuenta aqui
  Escribe $E.Repo '.git/hooks/pre-commit' "#!/bin/sh`necho 'hook de mentira: no se commitea'`nexit 1`n"
  if (Get-Command chmod -ErrorAction SilentlyContinue) { & chmod +x (Get-Ruta $E.Repo '.git/hooks/pre-commit') }
  $x = Fase35 $E
  Igual 'la fase no deja seguir' $false $x.Sigue
  Igual 'una parada' 1 $script:Paradas.Count
  if ($script:Paradas.Count -ne 1) { return }
  Igual 'motivo git' 'git' $script:Paradas[0][0]
  Comprueba 'el detalle lleva el test y lo que dijo git' ($script:Paradas[0][1].Contains((Test-De 'ReciboValidator')) -and $script:Paradas[0][1] -match 'hook de mentira') $script:Paradas[0][1]
  Comprueba 'el test no se queda en el migrado' (-not (Test-Path -LiteralPath (Get-Ruta $E.Repo (Test-De 'ReciboValidator'))))
  Igual 'el worktree queda limpio' '' (Estado-Git35 $E)
  $t = Tarea35 $x 'ReciboValidator'
  Igual 'sigue pendiente, sin intentos gastados' 'pendiente' $t.estado
  Igual 'cero intentos' 0 $t.intentos
}

$Pruebas['16 n) lo que habia sin confirmar en el worktree se deshace al empezar, con su aviso'] = {
  $E = Nuevo-Escenario35 'n' @('importe', 'cliente')
  Escribe $E.Repo "${Ruta35}Recibo.java" ($Fuentes35['Recibo'] + "// resto de una pasada que se corto`n")
  Escribe $E.Repo "${Ruta35}Suelto.java" "class Suelto { }`n"
  $x = Fase35 $E
  Comprueba 'lo dice, con los dos ficheros' ($x.Texto -match 'Deshago lo que habia sin confirmar' -and $x.Texto.Contains("${Ruta35}Recibo.java") -and $x.Texto.Contains("${Ruta35}Suelto.java")) $x.Texto
  Igual 'src/main queda como en el commit' $true (Main-Igual35 $E)
  Comprueba 'el fichero nuevo ya no esta' (-not (Test-Path -LiteralPath (Get-Ruta $E.Repo "${Ruta35}Suelto.java")))
  Igual 'el commit de ReciboValidator y nada mas' ("$Commit35$(Test-De 'ReciboValidator')|inicial") ($x.Commits -join '|')
}

$Pruebas['17 o) -MaxHoras: pasado el tiempo no empieza una ronda nueva y para con tope-de-tiempo'] = {
  $E = Nuevo-Escenario35 'o'
  $MaxHoras = 0.00000001
  $reloj = [System.Diagnostics.Stopwatch]::StartNew()
  Start-Sleep -Milliseconds 50
  $x = Fase35 $E @{ RESCATE_FALSO = 'parcial:ReciboValidator' } @{ Paralelo = 1 }
  Igual 'la fase no deja seguir' $false $x.Sigue
  Igual 'una parada' 1 $script:Paradas.Count
  if ($script:Paradas.Count -ne 1) { return }
  Igual 'motivo tope-de-tiempo' 'tope-de-tiempo' $script:Paradas[0][0]
  Igual 'la primera ronda si se hizo (con Paralelo 1: una clase)' 1 (Llamadas-De $E.Copilot).Count
}

$Pruebas['18 p) sin datos de comparacion: un aviso y ninguna llamada; sin reglas iguales, una linea con ceros'] = {
  $E = Nuevo-Escenario35 'p'
  Remove-Item -LiteralPath (Join-Path $E.Datos 'comparacion') -Recurse -Force
  $x = Fase35 $E
  Igual 'la fase deja seguir' $true $x.Sigue
  Igual 'ninguna llamada a Copilot' 0 (Llamadas-De $E.Copilot).Count
  Igual 'ninguna llamada a Maven' 0 (Llamadas-De $E.Mvn).Count
  Comprueba 'el aviso dice que faltan los datos de la comparacion' (@($x.Avisos | Where-Object { $_ -match 'No hay datos/comparacion' }).Count -eq 1) ($x.Avisos -join ' / ')
  $E = Nuevo-Escenario35 'p2' @()
  $x = Fase35 $E
  Igual 'la fase deja seguir' $true $x.Sigue
  Igual 'ninguna llamada a Copilot' 0 (Llamadas-De $E.Copilot).Count
  Igual 'ninguna llamada a Maven' 0 (Llamadas-De $E.Mvn).Count
  Comprueba 'una linea con los numeros a cero' ($x.Texto -match '(?m)^Tests de reglas: 0 clases con test \(0 reglas vigiladas\), 0 atascadas, 0 saltadas') $x.Texto
  Igual 'el JSON, sin tareas' 0 @($x.Json.tareas).Count
}

$Pruebas['19 q) un cambio que no compila: la regla queda sin-mutante con su motivo y no bloquea'] = {
  $E = Nuevo-Escenario35 'q' @('importe', 'cliente')
  # con el cambio de >= y <= (importe), el migrado de mentira no compila; la regla de cliente si se comprueba
  $x = Fase35 $E @{ M35_NO_COMPILA = 'getImporte\(\) > 0' }
  Igual 'se commitea el test' "$Commit35$(Test-De 'ReciboValidator')" $x.Commits[0]
  $f = Fila35 $x 'ReciboValidator'
  Igual 'hecha' 'hecha' $f.estado
  $i = Regla35 $f 'El importe tiene que ser mayor que cero.'
  Igual 'importe: sin-mutante' 'sin-mutante' $i.resultado
  Comprueba 'importe: el motivo dice que el cambio no compila' ($i.motivo -match 'no compila' -and $i.motivo.Contains('<=') -and $i.motivo.Contains('>')) $i.motivo
  Igual 'cliente: vigilada' 'vigilada' (Regla35 $f 'Todo recibo lleva cliente.').resultado
  Igual 'src/main queda byte a byte igual' $true (Main-Igual35 $E)
  $E = Nuevo-Escenario35 'q2' @('importe')
  $x = Fase35 $E @{ M35_NO_COMPILA = 'getImporte\(\) > 0' }
  $t = Tarea35 $x 'ReciboValidator'
  Igual 'si ninguna regla se ha podido comprobar, el test no se acepta: atascada' 'atascada' $t.estado
  Comprueba 'el motivo lo dice' ($t.motivo -match 'ninguna regla') $t.motivo
  Igual 'ningun commit' 'inicial' ($x.Commits -join '|')
}

$Pruebas['20 r) MutantesPorClase: mas reglas que el tope, las de mas quedan sin-mutante con su motivo'] = {
  $E = Nuevo-Escenario35 'r' @('importe', 'cliente', 'urgente')
  $x = Fase35 $E @{} @{ MutantesPorClase = 1 }
  $f = Fila35 $x 'ReciboValidator'
  Igual 'hecha' 'hecha' $f.estado
  Igual 'importe: vigilada' 'vigilada' (Regla35 $f 'El importe tiene que ser mayor que cero.').resultado
  $c = Regla35 $f 'Todo recibo lleva cliente.'
  Igual 'cliente: sin-mutante' 'sin-mutante' $c.resultado
  Comprueba 'cliente: el motivo dice el tope' ($c.motivo -match 'tope' -and $c.motivo -match '1') $c.motivo
  Igual 'dos corridas de ReciboValidator: sin cambio y un mutante' 2 @(Corridas35 $E 'ReciboValidator').Count
  Igual 'src/main queda byte a byte igual' $true (Main-Igual35 $E)
}

$Pruebas['21 s) si src/main no se puede dejar como estaba: parada git, sin seguir con mas mutantes'] = {
  $E = Nuevo-Escenario35 's' @('importe', 'cliente')
  $x = Fase35 $E @{ M35_ROMPE = 'com/acme/recibos/ReciboValidator.java' }
  $lock = Get-Ruta $E.Repo '.git/index.lock'
  Remove-Item -LiteralPath $lock -Force -ErrorAction SilentlyContinue
  Igual 'la fase no deja seguir' $false $x.Sigue
  Igual 'una parada' 1 $script:Paradas.Count
  if ($script:Paradas.Count -ne 1) { return }
  Igual 'motivo git' 'git' $script:Paradas[0][0]
  Comprueba 'el detalle dice el fichero que no pudo dejar como estaba' ($script:Paradas[0][1].Contains("${Ruta35}ReciboValidator.java")) $script:Paradas[0][1]
  Comprueba 'el detalle lleva lo que dijo git al intentar restaurarlo (el index.lock)' ($script:Paradas[0][1] -match 'index\.lock') $script:Paradas[0][1]
  Igual 'solo se llego al primer mutante: dos corridas (sin cambio y el primero)' 2 @(Corridas35 $E 'ReciboValidator').Count
  Igual 'ningun commit' 'inicial' ($x.Commits -join '|')
  Igual 'la tarea sigue pendiente, sin intentos gastados' 0 (Tarea35 $x 'ReciboValidator').intentos
}

$Pruebas['22 t) las entradas de cada tarea: solo las reglas iguales, con su linea en el migrado corregida por la cita; ficheros que no son de src/main/java no tienen tarea'] = {
  # la comparacion dice la linea 4 y 12 (la cita sale en la 6 y la 9, a mas de la tolerancia de 3 de la 12); la de plazo no tiene sitio
  $E = Nuevo-Escenario35 't' @('importe', 'cliente', 'urgente') @{ Desplaza = 2 }
  $RepoRoot = $E.Repo
  $Datos = $E.Datos
  $tareas = @(Con-Falso35 @{} @{} { Get-TareasReglas $true })
  Igual 'dos tareas, una por clase' 2 $tareas.Count
  $v = @($tareas | Where-Object { $_.entradas.clase -ceq 'ReciboValidator' })[0]
  Igual 'el fichero de la clase' "${Ruta35}ReciboValidator.java" $v.entradas.fichero
  Igual 'el test, en el mismo paquete bajo src/test/java' (Test-De 'ReciboValidator') $v.entradas.test
  Igual 'el nombre del test' 'ReciboValidatorReglasTest' $v.entradas.testClase
  Igual 'el paquete' 'com.acme.recibos' $v.entradas.paquete
  Igual 'dos reglas: ni la que falta ni el dato de tipo error' 2 @($v.entradas.reglas).Count
  Igual 'importe: la linea sale de la cita (6), no de la comparacion (8)' 6 $v.entradas.reglas[0].linea
  Igual 'importe: su texto' 'El importe tiene que ser mayor que cero.' $v.entradas.reglas[0].texto
  Igual 'importe: su cita' 'if (recibo.getImporte() <= 0) {' $v.entradas.reglas[0].cita
  Igual 'cliente: la linea 9' 9 $v.entradas.reglas[1].linea
  Comprueba 'el prompt lleva el fichero, el test y cada regla con su linea y su cita' ((Get-Prompt $v '' '') -match '(?s)FICHERO: src/main/java/com/acme/recibos/ReciboValidator\.java.*TEST: src/test/java/com/acme/recibos/ReciboValidatorReglasTest\.java.*REGLA 1: El importe tiene que ser mayor que cero\.\r?\n\s+Linea 6: if \(recibo\.getImporte\(\) <= 0\) \{.*REGLA 2: Todo recibo lleva cliente\.\r?\n\s+Linea 9: ')
  Comprueba 'ya no quedan marcas {{ }} sin rellenar' ((Get-Prompt $v '' '') -notmatch '\{\{')
  $p = Get-Prompt $v '' 'el motivo de prueba'
  Comprueba 'con motivo, el prompt lleva la correccion y el motivo' ($p -match 'CORRECCI' -and $p.Contains('el motivo de prueba'))
  # una cita que no sale en el fichero: se queda con su linea y se marca como no ubicada
  $E = Nuevo-Escenario35 't2' @('importe')
  $comp = Get-Ruta $E.Datos 'comparacion/clase-1-validator.json'
  $j = Lee-Json $comp
  $j.datos[0].cita = 'if (otra cosa) {'
  Write-Json $comp $j
  $RepoRoot = $E.Repo
  $Datos = $E.Datos
  $tareas = @(Con-Falso35 @{} @{} { Get-TareasReglas $true })
  $v = @($tareas | Where-Object { $_.entradas.clase -ceq 'ReciboValidator' })[0]
  Igual 'la cita que no sale se queda con su linea' 6 $v.entradas.reglas[0].linea
  Igual 'y queda como no ubicada' $false $v.entradas.reglas[0].ubicada
  # un fichero que no es de src/main/java no tiene tarea
  $E = Nuevo-Escenario35 't3' @('importe', 'urgente') @{ Fichero = 'scripts/otro.java' }
  $RepoRoot = $E.Repo
  $Datos = $E.Datos
  Igual 'sin tareas' 0 @(Con-Falso35 @{} @{} { Get-TareasReglas $true }).Count
  # un modulo: el test va al src/test/java de su modulo
  Igual 'modulo: la ruta del test' 'modulo-a/src/test/java/com/acme/X/YReglasTest.java' (Get-RutaTestReglas 'modulo-a/src/main/java/com/acme/X/Y.java')
}

$Pruebas['23 u) la huella de la tarea cambia con el fichero y con las reglas, y no con el HEAD'] = {
  $E = Nuevo-Escenario35 'u'
  $RepoRoot = $E.Repo
  $Datos = $E.Datos
  $a = @(Con-Falso35 @{} @{} { Get-TareasReglas $true })
  [void](GitEn $E.Repo @('commit', '-q', '--allow-empty', '-m', 'otro commit'))
  $b = @(Con-Falso35 @{} @{} { Get-TareasReglas $true })
  Igual 'con otro HEAD, la misma huella' $a[0].entradas.huella $b[0].entradas.huella
  Igual 'y el mismo id' $a[0].id $b[0].id
  Escribe $E.Repo "${Ruta35}RemesaCalculador.java" ($Fuentes35['RemesaCalculador'] -replace '30', '31')
  [void](GitEn $E.Repo @('commit', '-q', '-a', '-m', 'cambia la clase'))
  $c = @(Con-Falso35 @{} @{} { Get-TareasReglas $true })
  Igual 'con la clase cambiada, otra huella' $true ($a[1].entradas.huella -cne $c[1].entradas.huella)
  Igual 'la clase que no ha cambiado, igual' $a[0].entradas.huella $c[0].entradas.huella
}

$Pruebas['24 v) tests-reglas.ps1: solo funciones, cabecera, ASCII, nada de PowerShell 7 y la plantilla en UTF-8'] = {
  foreach ($f in @('tests-reglas.ps1', 'tests/probar-reglas.ps1', 'tests/falsos/m35-mvn.ps1', 'tests/falsos/m35-copilot.ps1')) {
    $t = [System.IO.File]::ReadAllText((Get-Ruta $raiz $f))
    Comprueba "$f`: solo ASCII" ($t -notmatch '[^\x09\x0A\x0D\x20-\x7E]')
  }
  $ruta = Join-Path $raiz 'tests-reglas.ps1'
  Comprueba 'existe junto a migracion.ps1' (Test-Path -LiteralPath $ruta)
  if (-not (Test-Path -LiteralPath $ruta)) { return }
  $codigo = [System.IO.File]::ReadAllText($ruta)
  Comprueba 'empieza con su cabecera de ayuda' ($codigo.TrimStart().StartsWith('<#'))
  Comprueba 'nada de PowerShell 7 (??, ?. ni ?[)' ($codigo -notmatch '\?\?|[\w\)\]]\?\.\w|\w\?\[')
  Comprueba 'sin -AsHashtable ni ConvertFrom-Json -Depth' ($codigo -notmatch 'AsHashtable|ConvertFrom-Json[^|\r\n]*-Depth')
  $ast = [System.Management.Automation.Language.Parser]::ParseInput($codigo, [ref]$null, [ref]$null)
  $sueltas = @($ast.EndBlock.Statements | Where-Object { $_ -isnot [System.Management.Automation.Language.FunctionDefinitionAst] -and $_.Extent.Text -notmatch '^\$Cfg \+= ' })
  Igual 'nada fuera de las funciones (salvo los ajustes de $Cfg)' 0 $sueltas.Count
  $propias = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Name })
  $deMas = @(Get-ChildItem -LiteralPath $raiz -File -Filter '*.ps1' | Where-Object { $_.Name -cne 'tests-reglas.ps1' } | ForEach-Object {
      [regex]::Matches([System.IO.File]::ReadAllText($_.FullName), '(?m)^function ([\w-]+)') | ForEach-Object { $_.Groups[1].Value }
    })
  $repetidas = @($propias | Where-Object { $deMas -contains $_ })
  Comprueba 'ninguna de sus funciones esta definida en otro script' ($repetidas.Count -eq 0) ($repetidas -join ', ')
  Igual 'MutantesPorClase' 6 $Cfg.MutantesPorClase
  $md = Join-Path (Join-Path $raiz 'tareas') 'test-reglas.md'
  Comprueba 'existe la plantilla tareas/test-reglas.md' (Test-Path -LiteralPath $md)
  if (-not (Test-Path -LiteralPath $md)) { return }
  $bytes = [System.IO.File]::ReadAllBytes($md)
  $utf8 = New-Object System.Text.UTF8Encoding($false, $true)
  $texto = ''
  try { $texto = $utf8.GetString($bytes) } catch { }
  Comprueba 'la plantilla es UTF-8 valido, con acentos' ($texto -match '[\u00e1\u00e9\u00ed\u00f3\u00fa\u00f1]')
  foreach ($m in @('{{FICHERO}}', '{{TEST}}', '{{TEST_CLASE}}', '{{PAQUETE}}', '{{REGLAS}}', '{{MOTIVO}}', '<!--CORRECCION-->', '@SpringBootTest', '@DisplayName', 'JUnit 5', 'Mockito')) {
    Comprueba "la plantilla lleva $m" ($texto.Contains($m))
  }
  Comprueba 'la plantilla no deja lanzar Maven' ($texto -match 'No ejecutes Maven')
  Comprueba 'esfuerzo medium en el codigo de la ronda' ($codigo -match "Esfuerzo = 'medium'")
}

# Lo que los mutantes de tests-reglas.ps1 dejaron vivo (verif/mut-m35): cada prueba de aqui abajo mata uno o dos.
$Pruebas['25 w) un test que falla contra el codigo tal como esta: no se llega a los mutantes, reintento y atascada, sin commit'] = {
  $E = Nuevo-Escenario35 'w'
  $x = Fase35 $E @{ RESCATE_FALSO = 'falla-previo:ReciboValidator' }
  Igual 'la fase deja seguir' $true $x.Sigue
  Igual 'solo se commitea el de RemesaCalculador' ("$Commit35$(Test-De 'RemesaCalculador')|inicial") ($x.Commits -join '|')
  $t = Tarea35 $x 'ReciboValidator'
  Igual 'ReciboValidator: atascada' 'atascada' $t.estado
  Igual 'dos intentos' 2 $t.intentos
  Comprueba 'el motivo dice que no pasa con el codigo tal como esta' ($t.motivo -match 'no pasa con el codigo tal como esta') $t.motivo
  Igual 'src/main queda byte a byte igual' $true (Main-Igual35 $E)
  Igual 'el worktree queda limpio' '' (Estado-Git35 $E)
  $cv = @(Corridas35 $E 'ReciboValidator')
  Igual 'dos corridas, una por intento' 2 $cv.Count
  Igual 'ninguna con src/main cambiado: no se llega a los mutantes' 0 @($cv | Where-Object { $_ }).Count
  Igual 'JSON: ninguna regla comprobada' 0 @((Fila35 $x 'ReciboValidator').reglas).Count
}

$Pruebas['26 x) el test que no compila es el segundo de la ronda: el primero se acepta y el otro se atasca'] = {
  $E = Nuevo-Escenario35 'x'
  $x = Fase35 $E @{ RESCATE_FALSO = 'no-compila:RemesaCalculador' }
  Igual 'la fase deja seguir' $true $x.Sigue
  Igual 'solo se commitea el de ReciboValidator' ("$Commit35$(Test-De 'ReciboValidator')|inicial") ($x.Commits -join '|')
  Igual 'el worktree queda limpio' '' (Estado-Git35 $E)
  Comprueba 'lo dice: la ronda no compila y se prueba de uno en uno' ($x.Texto -match 'de uno en uno') $x.Texto
  Igual 'ReciboValidator: hecha con un intento' 'hecha' (Tarea35 $x 'ReciboValidator').estado
  Igual 'ReciboValidator: un intento' 1 (Tarea35 $x 'ReciboValidator').intentos
  $t = Tarea35 $x 'RemesaCalculador'
  Igual 'RemesaCalculador: atascada' 'atascada' $t.estado
  Comprueba 'su motivo es que no compila' ($t.motivo -match 'No compila') $t.motivo
}

$Pruebas['27 y) el tope de Maven con un cambio puesto cuenta como vigilada: el test se pasa del tiempo'] = {
  $E = Nuevo-Escenario35 'y' @('importe')
  # el Maven de mentira se duerme con src/main cambiado; con 9 s de tope se para (las demas llamadas tardan una fraccion)
  $x = Fase35 $E @{ M35_COLGAR = '1' } @{ MinutosMaven = 0.15 }
  Igual 'la fase deja seguir' $true $x.Sigue
  Igual 'se commitea el test' "$Commit35$(Test-De 'ReciboValidator')" $x.Commits[0]
  $f = Fila35 $x 'ReciboValidator'
  Igual 'hecha' 'hecha' $f.estado
  $i = Regla35 $f 'El importe tiene que ser mayor que cero.'
  Igual 'importe: vigilada' 'vigilada' $i.resultado
  Comprueba 'importe: el motivo dice que se pasa del tiempo' ($i.motivo -match 'se pasa del tiempo') $i.motivo
  Comprueba 'avisa del tope de Maven' (@($x.Avisos | Where-Object { $_ -match 'se ha pasado del tope' }).Count -ge 1) ($x.Avisos -join ' / ')
  Igual 'src/main queda byte a byte igual' $true (Main-Igual35 $E)
  Igual 'el worktree queda limpio' '' (Estado-Git35 $E)
}

$Pruebas['28 z) una cita que sale dos veces: la regla se ubica en la linea mas cercana a la de la comparacion'] = {
  $cita = 'if (recibo.getImporte() <= 0) {'
  $otra = @'

    public void revalidar(Recibo recibo) {
        if (recibo.getImporte() <= 0) {
            throw new IllegalArgumentException("Otra vez: " + recibo.getNumero());
        }
    }
}
'@
  $fuente = ($Fuentes35['ReciboValidator'] -replace '\}\s*$', '') + $otra
  $lineas = @($fuente -split "`r?`n")
  $donde = @(for ($k = 0; $k -lt $lineas.Count; $k++) { if ($lineas[$k].Trim() -ceq $cita) { $k + 1 } })
  Igual 'la cita sale en dos lineas' 2 $donde.Count
  if ($donde.Count -ne 2) { return }
  # la comparacion dice la linea de justo antes del segundo sitio (lejos del primero)
  $E = Nuevo-Escenario35 'z' @('importe') @{ Fuentes = @{ ReciboValidator = $fuente }; Desplaza = ($donde[1] - 1 - 6) }
  $RepoRoot = $E.Repo
  $Datos = $E.Datos
  $v = @(Con-Falso35 @{} @{} { Get-TareasReglas $true }) | Where-Object { $_.entradas.clase -ceq 'ReciboValidator' } | Select-Object -First 1
  Igual 'importe: el segundo sitio, el mas cercano' $donde[1] $v.entradas.reglas[0].linea
  # y si la comparacion dice la del primero, el primero
  $E = Nuevo-Escenario35 'z2' @('importe') @{ Fuentes = @{ ReciboValidator = $fuente } }
  $RepoRoot = $E.Repo
  $Datos = $E.Datos
  $v = @(Con-Falso35 @{} @{} { Get-TareasReglas $true }) | Where-Object { $_.entradas.clase -ceq 'ReciboValidator' } | Select-Object -First 1
  Igual 'importe: el primer sitio, el mas cercano' $donde[0] $v.entradas.reglas[0].linea
}

$Pruebas['29 aa) Get-SpringReglas: cada anotacion que arranca Spring se rechaza y un test con Mockito no'] = {
  foreach ($a in @('@SpringBootTest', '@SpringBootTest(classes = App.class)', '@ContextConfiguration(classes = X.class)', '@SpringJUnitConfig', '@SpringBatchTest', '@WebMvcTest(Foo.class)', '@DataJpaTest', '@JdbcTest', '@ExtendWith(SpringExtension.class)')) {
    $dice = Get-SpringReglas "package x;`n`n$a`nclass T { }`n"
    Comprueba "rechaza $a" ($dice -cne '') "no ha visto nada"
  }
  Igual 'un test con Mockito no es de Spring' '' (Get-SpringReglas "@ExtendWith(MockitoExtension.class)`nclass T { @Mock Repo r; }`n")
  Igual 'ni un nombre que solo se parece' '' (Get-SpringReglas "@SpringBootTestPlus`nclass T { }`n")
}

$Pruebas['30 ab) una regla igual con fichero y sin linea (0) en la comparacion no entra en las tareas'] = {
  $E = Nuevo-Escenario35 'ab' @('importe', 'cliente')
  $comp = Get-Ruta $E.Datos 'comparacion/clase-1-validator.json'
  $j = Lee-Json $comp
  $j.datos[0].linea = 0
  Write-Json $comp $j
  $RepoRoot = $E.Repo
  $Datos = $E.Datos
  $v = @(Con-Falso35 @{} @{} { Get-TareasReglas $true }) | Where-Object { $_.entradas.clase -ceq 'ReciboValidator' } | Select-Object -First 1
  Igual 'una sola regla' 1 @($v.entradas.reglas).Count
  Igual 'la de cliente' 'Todo recibo lleva cliente.' $v.entradas.reglas[0].texto
}

$Pruebas['31 ac) dos reglas en la misma linea: se cambia una sola vez y las dos quedan vigiladas'] = {
  $E = Nuevo-Escenario35 'ac' @('importe')
  $cita = 'if (recibo.getImporte() <= 0) {'
  # una segunda regla sobre la linea del importe, en la ficha (dato 4) y en la comparacion
  $rf = Get-Ruta $E.Datos 'fichas/clase-1-validator.json'
  $f = Lee-Json $rf
  $f.datos = @($f.datos) + [pscustomobject]@{ tipo = 'regla'; texto = 'Un importe a cero no se cobra.'; linea = 31; cita = $cita }
  Write-Json $rf $f
  $rc = Get-Ruta $E.Datos 'comparacion/clase-1-validator.json'
  $c = Lee-Json $rc
  $c.datos = @($c.datos) + [pscustomobject]@{ dato = 4; estado = 'igual'; fichero = "${Ruta35}ReciboValidator.java"; linea = 6; cita = $cita; nota = ''; probado = $true }
  Write-Json $rc $c
  $x = Fase35 $E
  Igual 'se commitea el test' "$Commit35$(Test-De 'ReciboValidator')" $x.Commits[0]
  $fila = Fila35 $x 'ReciboValidator'
  Igual 'dos reglas' 2 @($fila.reglas).Count
  Igual 'las dos, vigiladas' 2 @($fila.reglas | Where-Object { $_.resultado -ceq 'vigilada' }).Count
  Igual 'dos corridas: sin cambio y un solo mutante para las dos' 2 @(Corridas35 $E 'ReciboValidator').Count
  Igual 'src/main queda byte a byte igual' $true (Main-Igual35 $E)
}

$Pruebas['32 ad) Get-MotivoNoVigiladaReglas: la linea y el cambio, y quitar un ! lo dice con sus palabras'] = {
  $m = Get-MotivoNoVigiladaReglas 5 ([pscustomobject]@{ Antes = '!'; Despues = '' }) 'Todo recibo lleva cliente.'
  Igual 'quitar un !' 'Tu test no falla si en la linea 5 quito el `!`: no comprueba la regla "Todo recibo lleva cliente."' $m
  $m = Get-MotivoNoVigiladaReglas 9 ([pscustomobject]@{ Antes = '=='; Despues = '!=' }) 'Texto.'
  Igual 'un cambio de operador' 'Tu test no falla si en la linea 9 cambio `==` por `!=`: no comprueba la regla "Texto."' $m
}

$Pruebas['33 ae) un test sin ningun @Test (Tests run: 0): no cuenta como que ha corrido, reintento y atascada sin llegar a los mutantes'] = {
  $E = Nuevo-Escenario35 'ae'
  $x = Fase35 $E @{ RESCATE_FALSO = 'sin-tests:ReciboValidator' }
  Igual 'solo se commitea el de RemesaCalculador' ("$Commit35$(Test-De 'RemesaCalculador')|inicial") ($x.Commits -join '|')
  $t = Tarea35 $x 'ReciboValidator'
  Igual 'ReciboValidator: atascada' 'atascada' $t.estado
  Comprueba 'el motivo dice que Maven no ha ejecutado ningun test' ($t.motivo -match 'no ha ejecutado ningun test') $t.motivo
  $cv = @(Corridas35 $E 'ReciboValidator')
  Igual 'dos corridas, una por intento' 2 $cv.Count
  Igual 'ninguna con src/main cambiado: no se llega a los mutantes' 0 @($cv | Where-Object { $_ }).Count
  Igual 'src/main queda byte a byte igual' $true (Main-Igual35 $E)
  Igual 'el worktree queda limpio' '' (Estado-Git35 $E)
}

$Pruebas['34 af) Test-FicheroReglas: solo es verdad si el fichero tiene exactamente esos bytes'] = {
  $r = Join-Path $Dir 'af'
  [void](New-Item -ItemType Directory -Path $r -Force)
  $f = Join-Path $r 'X.java'
  $bytes = [byte[]](0x61, 0x62, 0x0D, 0x0A, 0xE9, 0x63)
  [System.IO.File]::WriteAllBytes($f, $bytes)
  Igual 'los mismos bytes' $true (Test-FicheroReglas $f $bytes)
  [System.IO.File]::WriteAllBytes($f, [byte[]](0x61, 0x62, 0x0D, 0x0A, 0xE8, 0x63))
  Igual 'un byte distinto de la misma longitud' $false (Test-FicheroReglas $f $bytes)
  [System.IO.File]::WriteAllBytes($f, [byte[]](0x61, 0x62, 0x0D, 0x0A, 0xC9, 0x63))
  Igual 'una mayuscula en vez de la minuscula (E9 y C9)' $false (Test-FicheroReglas $f $bytes)
  [System.IO.File]::WriteAllBytes($f, [byte[]](0x61, 0x62, 0x0A, 0xE9, 0x63))
  Igual 'sin el CR' $false (Test-FicheroReglas $f $bytes)
  Igual 'un fichero que no esta' $false (Test-FicheroReglas (Join-Path $r 'No.java') $bytes)
  Igual 'una carpeta' $false (Test-FicheroReglas $r $bytes)
}

# ================================ LANZADOR ================================
Invoke-Banco $Pruebas 'tests/probar-reglas.ps1'
