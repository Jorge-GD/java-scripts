<#
arreglo-propiedades.ps1 - C6b: poner en el yml del migrado las propiedades del original que faltan (la fase 'propiedades' de migracion.ps1, en la pasada con
respuesta corregir, despues de corregir, de comparar, de -Practicas y de -Reglas y antes de la prueba en local).
No se ejecuta solo: solo funciones. Se carga con '. (Join-Path $PSScriptRoot 'arreglo-propiedades.ps1')' despues de comun.ps1, tareas.ps1, informe.ps1
(Get-EstadoBuild) y propiedades.ps1. Usa las variables del script que lo carga ($RepoRoot, el worktree del migrado; $LegacyRoot, $PlantillaRoot, $Datos,
$Registros, $Cfg y $ModeloElegido) y sus funciones Set-Parada (la pone Invoke-DiagnosticoMotor) e Invoke-DiagnosticoMotor. Solo ASCII. Vale para Windows
PowerShell 5.1 y para PowerShell 7.

  Invoke-FasePropiedades <conservar>   La fase. Devuelve $true si la pasada sigue (aunque la tarea se quede atascada) y $false si el motor del
                                       diagnostico se cae (ya ha puesto la parada). Con $conservar, una tarea atascada con la misma huella no se repite.
  Test-SalidaPropiedades <tarea> <dir> La comprobacion del JSON que escribe Copilot (la llama Test-Salida de tareas.ps1).

Que hace: llama a Invoke-Propiedades (datos\propiedades.json del HEAD de ahora) y pide a Copilot, en una sola tarea (tareas\propiedades.md), las claves del
original en estado falta y renombrada-falta (menos las que una pasada anterior dio por noAplica). La IA escribe en el worktree, asi que no va por
Invoke-Fase: lleva su propia ronda. Solo puede escribir en los application*.properties|yml|yaml de src/main/resources y src/main/resources/config (y crear
application-<perfil>.yml, o application.yml, si no hay fichero de ese perfil). Salida: .rescate\tareas\propiedades.json = { anadidas: [ { clave, fichero } ],
noAplica: [ { clave, motivo } ] }, con la clave del original.
Puertas, en este orden (si una falla se deshace todo lo de la tarea, y se reintenta con el motivo y mas esfuerzo; al segundo fallo queda atascada, con un
aviso, y la pasada sigue): a) el JSON vale; b) solo cambian los ficheros permitidos; c) ningun valor de un secreto del original sale en el diff (el script lo
lee del original; de menos de 4 caracteres no se vigila); d) volver a comparar: cada clave pedida ya no esta en falta ni en renombrada-falta (una renombrada
solo vale con su nombre nuevo) o esta en noAplica; f) ninguna clave empeora: una del original que estaba igual, por-variable o renombrada no pasa a distinto,
falta, renombrada-falta ni ya-no-existe (con la misma comparacion de la d, asi que va antes de compilar); e) Invoke-DiagnosticoMotor 'propiedades': compila y
los tests no peor que en diagnostico-despues.md (Get-FallosBuild de informe.ps1, la regla de Invoke-Cierre). Sin cambios (todo noAplica) no hay diagnostico
ni commit.
Un commit en el worktree: 'rescate(propiedades): <n> claves del original en el yml', solo con los ficheros permitidos que cambiaron.
Deja datos\propiedades-arreglo.json = { estado (hecha, atascada, sin-faltan o sin-cambios), commit, pedidas, anadidas[], noAplica[], motivo, huella } y la
linea 'Propiedades al yml: N anadidas, M no aplican (commit abc1234).' (o 'atascada: <motivo>' o 'ninguna falta'). Huella = claves pedidas con su valor, ficheros
permitidos y plantilla; con la misma huella una tarea hecha (o atascada, con $conservar) no vuelve a llamar. Con todo resuelto, relanzar deja el resultado de la
pasada que hizo el commit. El valor de un secreto no sale en un fichero, un commit, la consola ni un registro.
#>

# ================================ DATOS ================================
# Las claves del original que faltan en el migrado, segun datos\propiedades.json ($J): estado falta o renombrada-falta. Menos las que una pasada anterior
# ($Previo, el resultado de datos\propiedades-arreglo.json) dio por noAplica: siguen faltando y no se piden otra vez.
function Get-PedidasPropiedades($J, $Previo) {
  $resueltas = @()
  if ($null -ne $Previo -and ([string]$Previo.estado -ceq 'hecha' -or [string]$Previo.estado -ceq 'sin-cambios')) { $resueltas = @($Previo.noAplica | ForEach-Object { [string]$_.clave }) }
  return @(@($J.legacy) | Where-Object {
      $_ -and ([string]$_.estado -ceq 'falta' -or [string]$_.estado -ceq 'renombrada-falta') -and ($resueltas -cnotcontains [string]$_.clave)
    })
}

# Los ficheros del migrado donde puede escribir la IA: los application* que ya hay (resources y resources/config) y, de cada perfil pedido que no tiene
# fichero, el que puede crear (application.yml para default, application-<perfil>.yml para otro).
function Get-FicherosPermitidos($Pedidas) {
  $fallos = New-Object System.Collections.Generic.List[string]
  $existentes = @(Get-FicherosPropiedades $RepoRoot $false $fallos | ForEach-Object { $_.Rel })
  $perfiles = @($existentes | ForEach-Object { Get-PerfilFichero $_ })
  $res = @($existentes)
  foreach ($p in @($Pedidas | ForEach-Object { [string]$_.perfil } | Select-Object -Unique)) {
    if ($perfiles -ccontains $p) { continue }
    if ($p -ceq 'default') { $res += 'src/main/resources/application.yml' } else { $res += "src/main/resources/application-$p.yml" }
  }
  return $res
}

# El nombre de la variable de un secreto: la clave en mayusculas con _ (db.password -> DB_PASSWORD, app.items[0].token -> APP_ITEMS_0_TOKEN).
function Get-NombreVariableSecreto([string]$Clave) { return (($Clave.ToUpperInvariant() -replace '[^A-Z0-9]+', '_').Trim('_')) }

# Los valores de los secretos del original, para la puerta c: Clave y Valor. El JSON no los guarda: se leen de los ficheros del original. Un valor que es solo
# ${VARIABLE} no es un secreto (se mira su defecto, si lo lleva); uno de menos de 4 caracteres no se vigila (saldria en cualquier linea).
function Get-SecretosOriginal($J) {
  $res = @()
  $secretos = @(@($J.legacy) | Where-Object { $_ -and $_.secreto -eq $true })
  if ($secretos.Count -eq 0) { return $res }
  $fallos = New-Object System.Collections.Generic.List[string]
  $leidas = @(Read-PropiedadesLado @(Get-FicherosPropiedades $LegacyRoot $true $fallos) $fallos)
  foreach ($s in $secretos) {
    foreach ($e in @($leidas | Where-Object { $_.clave -ceq $s.clave -and $_.perfil -ceq $s.perfil })) {
      $v = [string]$e.valor
      $m = [regex]::Match($v, '^\$\{[^}:]*(:(?<d>.*))?\}$')
      if ($m.Success) { $v = $m.Groups['d'].Value }
      if ($v.Length -ge 4) { $res += [pscustomobject]@{ Clave = [string]$s.clave; Valor = $v } }
    }
  }
  return $res
}

# ================================ PROMPT Y HUELLA ================================
# Las claves pedidas, una por linea: la clave, el perfil, fichero:linea del original, el nombre nuevo si es renombrada-falta y el valor (de un secreto, solo
# la variable con la que se escribe).
function Get-TextoPedidas($Pedidas) {
  $lineas = @()
  foreach ($p in $Pedidas) {
    $l = "- clave: $($p.clave) | perfil: $($p.perfil) | original: $($p.fichero):$($p.linea)"
    $nombre = [string]$p.clave
    if ([string]$p.estado -ceq 'renombrada-falta') { $nombre = [string]$p.renombradaA; $l += " | nombre nuevo: $nombre" }
    if ($p.secreto -eq $true) { $l += ' | secreto: no lo copies; escribe ${' + (Get-NombreVariableSecreto $nombre) + '}' }
    else { $l += ' | valor: ' + (([string]$p.valorLegacy) -replace '\r?\n', '\n') }
    $lineas += $l
  }
  return ($lineas -join "`n")
}

function Get-TextoPermitidos($Permitidos) {
  return ((@($Permitidos | ForEach-Object {
          if (Test-Path -LiteralPath (Join-Ruta $RepoRoot $_) -PathType Leaf) { "- $_ (existe)" } else { "- $_ (nuevo: puedes crearlo)" }
        })) -join "`n")
}

# Los ficheros de configuracion de la referencia, con su ruta completa (solo para leer como ejemplo de estilo).
function Get-TextoReferencia {
  $fallos = New-Object System.Collections.Generic.List[string]
  $rutas = @(Get-FicherosPropiedades $PlantillaRoot $false $fallos | ForEach-Object { '- ' + (Join-Ruta $PlantillaRoot $_.Rel) })
  if ($rutas.Count -eq 0) { return 'No hay ninguno: sigue el estilo de los ficheros del migrado.' }
  return ($rutas -join "`n")
}

# La huella de lo que pide la tarea: las claves con su valor de comparacion, el contenido de los ficheros permitidos y la plantilla.
function Get-HuellaPropiedades($Pedidas, $Permitidos) {
  $l = @('plantilla|' + (Get-Hash8 (Get-Plantilla 'propiedades')))
  foreach ($p in $Pedidas) { $l += "clave|$($p.clave)|$($p.perfil)|$($p.estado)|$($p.renombradaA)|$($p.valorLegacy)" }
  foreach ($f in $Permitidos) {
    $h = 'sin-fichero'
    $ruta = Join-Ruta $RepoRoot $f
    if (Test-Path -LiteralPath $ruta -PathType Leaf) { $h = Get-Hash8 ([System.IO.File]::ReadAllText($ruta)) }
    $l += "fichero|$f|$h"
  }
  return (Get-Hash8 ($l -join "`n"))
}

# ================================ PUERTAS ================================
# La puerta a: lo que ha escrito Copilot en .rescate\tareas\propiedades.json. La Ficha es { anadidas, noAplica } (listas, vacias si faltan).
function Test-SalidaPropiedades($T, [string]$Dir) {
  $r = Read-Salida $T $Dir
  if (-not $r.Ok) { return $r }
  $pedidas = @($T.entradas.claves)
  $listas = @{}
  foreach ($n in @('anadidas', 'noAplica')) {
    $v = $r.Ficha.$n
    if ($null -ne $v -and $v -isnot [System.Array]) { return (New-Resultado $false "El campo $n tiene que ser una lista [ ... ]." $null) }
    $listas[$n] = @($v | Where-Object { $null -ne $_ })
    $campo = 'fichero'
    if ($n -ceq 'noAplica') { $campo = 'motivo' }
    foreach ($i in $listas[$n]) {
      if ($i -isnot [System.Management.Automation.PSCustomObject] -or -not (Test-Texto $i.clave)) { return (New-Resultado $false "Cada entrada de $n tiene que ser un objeto con clave y $campo." $null) }
      if ($pedidas -cnotcontains [string]$i.clave) { return (New-Resultado $false "La clave '$($i.clave)' de $n no es de las que se piden: usa solo las claves de la lista, tal cual (la renombrada, con la clave del original)." $null) }
      if (-not (Test-Texto $i.$campo)) { return (New-Resultado $false "$n de la clave '$($i.clave)': falta $campo (un texto que no este vacio)." $null) }
    }
  }
  $repetidas = @(@($listas.anadidas) + @($listas.noAplica) | ForEach-Object { [string]$_.clave } | Group-Object -CaseSensitive | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
  if ($repetidas.Count -gt 0) { return (New-Resultado $false ('La clave ' + ($repetidas -join ', ') + ' sale mas de una vez (en las dos listas o repetida): cada clave va en una sola entrada.') $null) }
  return (New-Resultado $true '' ([pscustomobject]@{ anadidas = @($listas.anadidas); noAplica = @($listas.noAplica) }))
}

# La puerta d: las claves pedidas que siguen sin resolver en $J (el propiedades.json de ahora): las que siguen en falta o renombrada-falta y no estan en
# $NoAplica, y las renombradas que no han quedado con su nombre nuevo (estado renombrada).
function Get-SinResolver($J, $Pedidas, [string[]]$NoAplica) {
  $sin = @()
  foreach ($p in $Pedidas) {
    if ($NoAplica -ccontains [string]$p.clave) { continue }
    $ahora = @(@($J.legacy) | Where-Object { $_ -and $_.clave -ceq $p.clave -and $_.perfil -ceq $p.perfil })
    $bien = ($ahora.Count -gt 0)
    foreach ($a in $ahora) {
      if ($a.estado -ceq 'falta' -or $a.estado -ceq 'renombrada-falta') { $bien = $false }
      if ([string]$p.estado -ceq 'renombrada-falta' -and $a.estado -cne 'renombrada') { $bien = $false }
    }
    if (-not $bien) { $sin += [string]$p.clave }
  }
  return @($sin | Select-Object -Unique)
}

# La puerta f: las claves del original que estaban bien en el migrado ($Antes, el propiedades.json de antes de llamar a la IA: igual, por-variable o
# renombrada) y que en $Ahora (el de despues) estan peor (distinto, falta, renombrada-falta o ya-no-existe). Una cadena por clave, sin su valor.
function Get-ClavesQueEmpeoran($Antes, $Ahora) {
  $bien = @('igual', 'por-variable', 'renombrada')
  $mal = @('distinto', 'falta', 'renombrada-falta', 'ya-no-existe')
  $res = @()
  foreach ($a in @(@($Antes.legacy) | Where-Object { $_ -and ($bien -ccontains [string]$_.estado) })) {
    foreach ($d in @(@($Ahora.legacy) | Where-Object {
          $_ -and $_.clave -ceq $a.clave -and $_.perfil -ceq $a.perfil -and $_.fichero -ceq $a.fichero -and $_.linea -eq $a.linea -and ($mal -ccontains [string]$_.estado)
        })) { $res += "$($a.clave) (perfil $($a.perfil), antes $($a.estado), ahora $($d.estado))" }
  }
  return $res
}

# Las puertas a-f sobre lo que ha dejado la IA en el worktree. Devuelve Motivo ('' si pasan todas), Ficha (anadidas y noAplica), Cambios (los ficheros que
# hay que commitear; vacio = nada) y Parada ($true si el motor del diagnostico se ha caido: ya ha puesto la parada). Las que cambian el indice (git add) las
# deshace quien llama.
function Confirm-CambiosPropiedades($T, $Pedidas, $Permitidos, $Secretos, $Antes) {
  $v = [pscustomobject]@{ Motivo = ''; Ficha = $null; Cambios = @(); Parada = $false }
  # a) el JSON
  $salida = Test-Salida $T $RepoRoot ''
  if (-not $salida.Ok) { $v.Motivo = $salida.Motivo; return $v }
  $v.Ficha = $salida.Ficha
  # b) solo los ficheros permitidos
  $v.Cambios = @(Get-Cambios $RepoRoot)
  $fuera = @($v.Cambios | Where-Object { $Permitidos -cnotcontains $_ })
  if ($fuera.Count -gt 0) { $v.Motivo = 'Has cambiado ficheros que no puedes tocar: ' + (Get-ListaFicheros $fuera) + '. Solo cambias los ficheros de configuracion de la lista.'; return $v }
  # c) ningun valor de un secreto en lo anadido
  if ($v.Cambios.Count -gt 0) {
    [void](Invoke-Git $RepoRoot (@('add', '--') + $v.Cambios))
    $anadido = @((Invoke-Git $RepoRoot @('diff', '--cached', '-U0', '--no-color')).Salida | Where-Object { $_ -match '^\+' -and $_ -notmatch '^\+\+\+' })
    $escritos = @()
    foreach ($s in $Secretos) { foreach ($l in $anadido) { if ($l.Contains($s.Valor)) { $escritos += $s.Clave; break } } }
    if ($escritos.Count -gt 0) {
      $nombres = @($escritos | Select-Object -Unique | ForEach-Object { $_ + ' (como ${' + (Get-NombreVariableSecreto $_) + '})' })
      $v.Motivo = 'Has escrito el valor de un secreto del original: ' + ($nombres -join ', ') + '. Un secreto va como una variable ${NOMBRE}, nunca con su valor.'
      return $v
    }
  }
  # d) volver a comparar
  Invoke-Propiedades $LegacyRoot $RepoRoot $PlantillaRoot $Datos $Registros 6>$null
  $J = $null
  try { $J = Read-Json (Join-Path $Datos 'propiedades.json') } catch { $null = $_ }
  if ($null -eq $J -or $null -eq $J.resumen) { $v.Motivo = 'El script no ha podido volver a comparar las propiedades: comprueba que los ficheros que has escrito son validos.'; return $v }
  $sin = @(Get-SinResolver $J $Pedidas @($v.Ficha.noAplica | ForEach-Object { [string]$_.clave }))
  if ($sin.Count -gt 0) {
    $v.Motivo = 'Despues de tu cambio, el script compara otra vez y estas claves siguen sin estar en el migrado (una renombrada solo vale con su nombre nuevo) ni en noAplica: ' + ($sin -join ', ') + '.'
    return $v
  }
  # f) ninguna clave que estaba bien empeora
  $peor = @(Get-ClavesQueEmpeoran $Antes $J)
  if ($peor.Count -gt 0) {
    $v.Motivo = 'Despues de tu cambio, estas claves del original ya estaban bien en el migrado y ahora no: ' + ($peor -join '; ') + '. No cambies ni borres lo que ya estaba: solo anades.'
    return $v
  }
  if ($v.Cambios.Count -eq 0) { return $v }
  # e) compila y los tests no peor que antes (la regla de Invoke-Cierre)
  if (-not (Invoke-DiagnosticoMotor 'propiedades')) { $v.Parada = $true; return $v }
  $nuevo = Get-EstadoBuild ([System.IO.File]::ReadAllText((Join-Path $Datos 'diagnostico-propiedades.md'), $Utf8))
  $antes = ''
  $rutaAntes = Join-Path $Datos 'diagnostico-despues.md'
  if (Test-Path -LiteralPath $rutaAntes) { $antes = Get-EstadoBuild ([System.IO.File]::ReadAllText($rutaAntes, $Utf8)) }
  $fallos = @(Get-FallosBuild $nuevo $antes 'el migrado de antes de tu cambio')
  if ($fallos.Count -gt 0) { $v.Motivo = 'Con tu cambio: ' + ($fallos -join '; ') + '. Un fichero de propiedades no puede empeorar la compilacion ni los tests.' }
  return $v
}

# ================================ RONDA ================================
# Una ronda: una llamada a Copilot en el worktree del migrado, las puertas y, si pasan, el commit. Devuelve Estado (ok, sin-cambios, invalida, fallo,
# tiempo, git o parada), Motivo, Commit y Ficha. Si no es ok ni sin-cambios, el worktree queda como estaba. La marca de intento (comun.ps1) va desde antes
# de la llamada hasta que todo esta commiteado o deshecho; nunca en un finally (con Ctrl+C se ejecuta y la marca tiene que quedar).
function Invoke-RondaPropiedades($T, $Pedidas, $Permitidos, $Secretos, $Antes) {
  $r = [pscustomobject]@{ Estado = 'ok'; Motivo = ''; Commit = ''; Ficha = $null }
  $motivo = ''
  $esfuerzo = $Cfg.EsfuerzoLectura
  if ($T.intentos -gt 0) {
    $esfuerzo = $Cfg.EsfuerzoReintento
    if ($T.ultimoEstado -eq 'invalida') { $motivo = $T.motivo }
  }
  $item = [pscustomobject]@{ Id = $T.id; Dir = $RepoRoot; Modelo = $ModeloElegido; Esfuerzo = $esfuerzo; Dirs = @($PlantillaRoot); Prompt = (Get-Prompt $T '' $motivo) }
  $head = Get-Head $RepoRoot
  $rama = Get-Rama $RepoRoot
  Save-Intento 'propiedades' ($T.intentos + 1) $head $Permitidos
  $c = @(Invoke-Llamadas @($item))[0]
  $texto = [string]$c.Texto
  foreach ($s in $Secretos) { $texto = $texto.Replace($s.Valor, '***') }
  $cab = "# salida (codigo $($c.Codigo), $($c.Segundos) s"
  if ($c.Agotado) { $cab += ', tiempo agotado' }
  [System.IO.File]::WriteAllText((Join-Path $Registros ($T.id + '-' + ($T.intentos + 1) + '.log')), ("# prompt`n" + $item.Prompt + "`n`n" + $cab + ")`n" + $texto + "`n"), $Utf8)
  if ($c.Agotado) { $r.Estado = 'tiempo'; $r.Motivo = "Tiempo agotado: la llamada pasaba de $($Cfg.SegundosPorLlamada) s y se mato." }
  elseif ($c.Codigo -ne 0) { $r.Estado = 'fallo'; $r.Motivo = "Copilot salio con codigo $($c.Codigo): " + (Get-UltimaLinea $texto) }
  elseif ((Get-Head $RepoRoot) -cne $head -or (Get-Rama $RepoRoot) -cne $rama) { $r.Estado = 'invalida'; $r.Motivo = 'Has hecho un commit en el repositorio. Solo cambias los ficheros: el commit lo hace el script.' }
  else {
    # un 'git add' de la IA dejaria sus cambios en el indice, donde Get-Cambios no los ve
    [void](Invoke-Git $RepoRoot @('reset', '-q'))
    $v = Confirm-CambiosPropiedades $T $Pedidas $Permitidos $Secretos $Antes
    if ($v.Parada) { $r.Estado = 'parada' }
    elseif ($v.Motivo) { $r.Estado = 'invalida'; $r.Motivo = $v.Motivo }
    else {
      $r.Ficha = $v.Ficha
      if ($v.Cambios.Count -eq 0) { $r.Estado = 'sin-cambios' }
      else {
        $g = Invoke-Git $RepoRoot (@('commit', '-q') + @($Cfg.CommitArgs) + @('-m', "rescate(propiedades): $(@($v.Ficha.anadidas).Count) claves del original en el yml", '--') + $v.Cambios)
        if ($g.Codigo -eq 0) { $r.Commit = Get-Head $RepoRoot; Update-Intento $r.Commit }
        else { $r.Estado = 'git'; $r.Motivo = 'git commit ha fallado: ' + (@($g.Salida) -join ' / ') }
      }
    }
  }
  if ($r.Estado -cne 'ok' -and $r.Estado -cne 'sin-cambios') { Undo-Lote $rama $head }
  Remove-Intento
  return $r
}

# ================================ FASE ================================
# La linea de la consola de un resultado (el de datos\propiedades-arreglo.json): un aviso si esta atascada.
function Write-LineaArreglo($R) {
  if ([string]$R.estado -ceq 'atascada') { Aviso ('Propiedades al yml: atascada: ' + $R.motivo); return }
  $l = "Propiedades al yml: $(@($R.anadidas).Count) anadidas, $(@($R.noAplica).Count) no aplican"
  if ($R.commit) { $l += " (commit $(([string]$R.commit).Substring(0, 7)))." } else { $l += ' (sin cambios).' }
  Info $l
}

# datos\propiedades-arreglo.json de una tarea hecha o atascada, y su linea de consola.
function Save-ResultadoPropiedades($T, [int]$Pedidas) {
  $estado = 'atascada'
  $commit = ''
  $anadidas = @()
  $noAplica = @()
  if ($T.estado -ceq 'hecha') {
    $estado = 'hecha'
    if ($T.resultado.sinCambios) { $estado = 'sin-cambios' }
    $commit = [string]$T.resultado.commit
    $anadidas = @($T.resultado.anadidas | ForEach-Object { [ordered]@{ clave = [string]$_.clave; fichero = [string]$_.fichero } })
    $noAplica = @($T.resultado.noAplica | ForEach-Object { [ordered]@{ clave = [string]$_.clave; motivo = [string]$_.motivo } })
  }
  $motivo = ''
  if ($estado -ceq 'atascada') { $motivo = [string]$T.motivo }
  $R = [ordered]@{ estado = $estado; commit = $commit; pedidas = $Pedidas; anadidas = $anadidas; noAplica = $noAplica; motivo = $motivo; huella = [string]$T.entradas.huella }
  Write-Json (Join-Path $Datos 'propiedades-arreglo.json') $R
  Write-LineaArreglo $R
}

# La fase 'propiedades' de migracion.ps1. Devuelve si se puede seguir (no hay parada).
function Invoke-FasePropiedades([bool]$Conservar) {
  Invoke-Propiedades $LegacyRoot $RepoRoot $PlantillaRoot $Datos $Registros
  $J = $null
  try { $J = Read-Json (Join-Path $Datos 'propiedades.json') } catch { $null = $_ }
  if ($null -eq $J -or $null -eq $J.resumen) { Aviso 'Propiedades al yml: no se han podido comparar las propiedades: no hago nada.'; return $true }
  $ruta = Join-Path $Datos 'propiedades-arreglo.json'
  $previo = $null
  if (Test-Path -LiteralPath $ruta) { try { $previo = Read-Json $ruta } catch { $null = $_ } }
  $pedidas = @(Get-PedidasPropiedades $J $previo)
  if ($pedidas.Count -eq 0) {
    # con todo resuelto, relanzar deja el resultado de la pasada que hizo el commit (ya no falta nada, y no se pierde lo que se hizo)
    if ($null -ne $previo -and ([string]$previo.estado -ceq 'hecha' -or [string]$previo.estado -ceq 'sin-cambios')) { Write-LineaArreglo $previo; return $true }
    Write-Json $ruta ([ordered]@{ estado = 'sin-faltan'; commit = ''; pedidas = 0; anadidas = @(); noAplica = @(); motivo = ''; huella = '' })
    Info 'Propiedades al yml: ninguna falta'
    return $true
  }
  $permitidos = @(Get-FicherosPermitidos $pedidas)
  $entradas = [pscustomobject]@{
    claves = @($pedidas | ForEach-Object { [string]$_.clave } | Select-Object -Unique); huella = (Get-HuellaPropiedades $pedidas $permitidos)
    prompt = [pscustomobject]@{ CLAVES = (Get-TextoPedidas $pedidas); FICHEROS = (Get-TextoPermitidos $permitidos); REFERENCIA = (Get-TextoReferencia) }
  }
  $t = Restore-Tarea (New-TareaTipo 'propiedades' 'propiedades' '' '' $entradas) $Conservar
  $parada = $false
  if ($t.estado -ceq 'pendiente') {
    $mal = Move-SinCommitAStash 'propiedades: cambios sin commit de antes'
    if ($mal) { Aviso "Propiedades al yml: no he podido apartar con git stash lo que habia sin confirmar en el worktree: $mal. No hago nada."; return $true }
    $secretos = @(Get-SecretosOriginal $J)
    while (-not $parada -and $t.estado -ceq 'pendiente') {
      $o = Invoke-RondaPropiedades $t $pedidas $permitidos $secretos $J
      if ($o.Estado -ceq 'parada') { $parada = $true; continue }
      $t.intentos++
      $t.motivo = $o.Motivo
      $t.ultimoEstado = $o.Estado
      if ($o.Estado -ceq 'ok' -or $o.Estado -ceq 'sin-cambios') {
        $t.estado = 'hecha'
        $t.ultimoEstado = 'ok'
        $t.resultado = [pscustomobject]@{ commit = $o.Commit; sinCambios = ($o.Estado -ceq 'sin-cambios'); anadidas = @($o.Ficha.anadidas); noAplica = @($o.Ficha.noAplica) }
      }
      elseif ($o.Estado -ceq 'git' -or $t.intentos -ge [int]$Cfg.Intentos) { $t.estado = 'atascada' }
      Save-Tarea $t
    }
    # propiedades.json vuelve a ser el del HEAD (la puerta d lo dejo con lo que probo la IA)
    Invoke-Propiedades $LegacyRoot $RepoRoot $PlantillaRoot $Datos $Registros 6>$null
  }
  if ($parada) { return $false }
  $script:Todas += @($t)
  Save-ResultadoPropiedades $t $pedidas.Count
  return $true
}
