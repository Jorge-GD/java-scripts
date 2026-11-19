# m33-mvn.ps1 - Maven de mentira para tests/probar-regresion.ps1 (-Regresion de prueba-local.ps1). Hace lo de m25-mvn.ps1 (y con el, lo de
# mvn-local.ps1) y, ademas, segun las palabras de RESCATE_M33 (separadas por comas):
#   estable    tras cada 'test -Dtest=...', ficheros/salida/resultado_<aaaammdd>.txt de cada caso pierde las lineas 'procesado en' y 'hecho el' (la ruta
#              y la hora de la ejecucion) y pasa a llamarse resultado.txt: lo que sale no depende de cuando ni donde se ejecuta. Sin esta palabra,
#              lo que sale lleva la fecha, la hora y la ruta de hoy, como el de un batch que escribe su propio dia
#   estable-texto   solo lo primero: pierde las lineas 'procesado en' y 'hecho el', pero el nombre sigue llevando la fecha (la fecha solo esta en el nombre)
#   estable-nombre  solo lo segundo: pasa a llamarse resultado.txt, pero el texto sigue llevando la hora y la ruta (la fecha solo esta en el texto)
#   framework  cada caso deja ademas tablas/BATCH_JOB_INSTANCE.csv y tablas/TASK_EXECUTION.csv, con otro contenido en cada lado (el original es
#              la carpeta batch-viejo)
#   sordo      el test de regresion no compara nada: pasa siempre
#   roto       el test de regresion no compila: Maven falla sin dejar target/regresion-fallos.txt (no dice que caso)
#   todos-fallan  el test de regresion da por distintos todos los casos
#   incompleto    el test de regresion solo apunta el primer caso que falla (aunque fallen mas)
#   ruido      si algun caso sale distinto (la comprobacion de sensibilidad), el test falla apuntando otro caso, que no es el cambiado
# Un 'test' cuyo -Dtest no nombra PruebaLocalTest no deja target/prueba-local (solo lo deja el arnes), como un Surefire que solo ejecuta ese test.
# La suite de tests unitarios (un 'test' sin -Dtest, la de Measure-Tests de -Reparar) la hace m25-mvn.ps1, que deja un TEST-<clase>.xml por cada
# *Test.java menos PruebaLocalTest; aqui se quitan, como Surefire, los de las clases que casan con las lineas '**/<Nombre>*' del excludesFile.
# Un 'test' con -Dtest=...RegresionLocalTest... (los casos ya se han ejecutado todos, en una sola JVM, con lo de mvn-local.ps1) hace lo que haria el
# RegresionLocalTest de verdad: por cada src/test/resources/prueba-local-esperado/<job>/<caso>/ compara cada fichero con el de target/prueba-local/<job>/<caso>/
# (sin las tablas BATCH_ ni TASK_ y sin contar los saltos de linea) y, si algo no coincide, falla (sale con 1) y deja en target/regresion-fallos.txt una
# linea por caso: job, caso y el mensaje (fichero, primera linea distinta, lo esperado y lo que sale), separados por tabuladores.
$raiz = (Get-Location).Path
$modo = @("$env:RESCATE_M33" -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
& (Join-Path $PSScriptRoot 'm25-mvn.ps1') @args
$codigo = $LASTEXITCODE
$prueba = @($args | Where-Object { "$_" -like '-Dtest=*' })
if ($codigo -eq 0 -and $args -contains 'test' -and $prueba.Count -eq 0) {
  $excluye = ''
  foreach ($a in $args) { if ("$a" -match '^-Dsurefire\.excludesFile=(.+)$') { $excluye = $Matches[1] } }
  if ($excluye -and (Test-Path -LiteralPath $excluye)) {
    foreach ($l in @([System.IO.File]::ReadAllLines($excluye))) {
      $m = [regex]::Match($l.Trim(), '^\*\*/(\w+)\*$')
      if ($m.Success) { Get-ChildItem -LiteralPath (Join-Path $raiz 'target/surefire-reports') -File -Filter ('TEST-*' + $m.Groups[1].Value + '*.xml') -ErrorAction SilentlyContinue | Remove-Item -Force }
    }
  }
  exit $codigo
}
$salidas = Join-Path $raiz 'target/prueba-local'
if ($codigo -ne 0 -or $args -notcontains 'test' -or $prueba.Count -eq 0) { exit $codigo }
if ($prueba[0] -notmatch 'PruebaLocalTest' -and (Test-Path -LiteralPath $salidas)) { Remove-Item -LiteralPath $salidas -Recurse -Force }
$deSalida = @()
if (Test-Path -LiteralPath $salidas) { $deSalida = @(Get-ChildItem -LiteralPath $salidas -Directory | ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Directory }) }

$original = ($raiz -like '*batch-viejo*')
$textoEstable = ($modo -contains 'estable' -or $modo -contains 'estable-texto')
$nombreEstable = ($modo -contains 'estable' -or $modo -contains 'estable-nombre')
foreach ($caso in $deSalida) {
  if ($textoEstable -or $nombreEstable) {
    foreach ($f in @(Get-ChildItem -LiteralPath $caso.FullName -Recurse -File -Filter 'resultado_*.txt')) {
      $lineas = @([System.IO.File]::ReadAllLines($f.FullName))
      if ($textoEstable) { $lineas = @($lineas | Where-Object { $_ -notmatch '^(procesado en|hecho el) ' }) }
      $nombre = $f.Name
      if ($nombreEstable) { $nombre = 'resultado.txt' }
      [System.IO.File]::WriteAllText((Join-Path $f.DirectoryName $nombre), (($lineas -join "`n") + "`n"))
      if ($nombre -ne $f.Name) { Remove-Item -LiteralPath $f.FullName }
    }
  }
  if ($modo -contains 'framework' -and $caso.Name -ne 'vacio') {
    $tablas = Join-Path $caso.FullName 'tablas'
    [void](New-Item -ItemType Directory -Path $tablas -Force)
    if ($original) { $n = 'viejo' } else { $n = 'nuevo' }
    [System.IO.File]::WriteAllText((Join-Path $tablas 'BATCH_JOB_INSTANCE.csv'), "JOB_INSTANCE_ID;JOB_NAME`n1;$n`n")
    [System.IO.File]::WriteAllText((Join-Path $tablas 'TASK_EXECUTION.csv'), "TASK_EXECUTION_ID;TASK_NAME`n1;$n`n")
  }
}

if ($prueba[0] -notmatch 'RegresionLocalTest') { exit 0 }
if (@(Get-ChildItem -LiteralPath (Join-Path $raiz 'src/test/java') -Recurse -File -Filter 'RegresionLocalTest.java' -ErrorAction SilentlyContinue).Count -eq 0) {
  '[ERROR] No tests matching pattern "RegresionLocalTest" were executed!'
  exit 1
}
if ($modo -contains 'roto') {
  '[ERROR] COMPILATION ERROR : '
  '[ERROR] RegresionLocalTest.java:[1,1] simbolo de mentira no encontrado'
  exit 1
}
if ($modo -contains 'sordo') { '[INFO] BUILD SUCCESS'; exit 0 }

function Get-Lineas([string]$Ruta) {
  $l = @(([System.IO.File]::ReadAllText($Ruta)) -split '\r?\n')
  if ($l.Count -gt 0 -and $l[$l.Count - 1] -eq '') { $l = @($l | Select-Object -First ($l.Count - 1)) }
  return $l
}
function Get-Rutas([string]$Dir) {
  if (-not (Test-Path -LiteralPath $Dir)) { return @() }
  return @(Get-ChildItem -LiteralPath $Dir -Recurse -File | ForEach-Object { ($_.FullName.Substring($Dir.Length).TrimStart('\', '/')) -replace '\\', '/' } | Where-Object { $_ -cnotmatch '^tablas/(BATCH|TASK)_[^/]*\.csv$' })
}
$esperado = Join-Path $raiz 'src/test/resources/prueba-local-esperado'
$fallos = @()
foreach ($dj in @(Get-ChildItem -LiteralPath $esperado -Directory | Sort-Object Name)) {
  foreach ($dc in @(Get-ChildItem -LiteralPath $dj.FullName -Directory | Sort-Object Name)) {
    $sale = Join-Path $salidas ($dj.Name + '/' + $dc.Name)
    $mensaje = ''
    if (-not (Test-Path -LiteralPath $sale)) { $mensaje = 'no hay salida en target/prueba-local/' + $dj.Name + '/' + $dc.Name + ' (PruebaLocalTest no la ha dejado)' }
    foreach ($rel in @((Get-Rutas $dc.FullName) + (Get-Rutas $sale) | Sort-Object -Unique)) {
      if ($mensaje) { break }
      $a = Join-Path $dc.FullName $rel
      $b = Join-Path $sale $rel
      if (-not (Test-Path -LiteralPath $b)) { $mensaje = "${rel}: no sale"; break }
      if (-not (Test-Path -LiteralPath $a)) { $mensaje = "${rel}: sobra, el original no lo deja"; break }
      $x = @(Get-Lineas $a)
      $y = @(Get-Lineas $b)
      for ($i = 0; $i -lt [Math]::Max($x.Count, $y.Count) -and -not $mensaje; $i++) {
        $va = '(no hay)'; $vb = '(no hay)'
        if ($i -lt $x.Count) { $va = $x[$i] }
        if ($i -lt $y.Count) { $vb = $y[$i] }
        if ($va -cne $vb) { $mensaje = "${rel}: linea $($i + 1): esperado '$va' y sale '$vb'" }
      }
      if ($mensaje) { break }
    }
    if ($modo -contains 'todos-fallan') { $mensaje = 'estado.txt: linea 1: falla de mentira' }
    if ($mensaje) { $fallos += ($dj.Name + "`t" + $dc.Name + "`t" + $mensaje) }
  }
}
if ($modo -contains 'incompleto') { $fallos = @($fallos | Select-Object -First 1) }
if ($modo -contains 'ruido' -and $fallos.Count -gt 0) { $fallos = @("ruido`tcaso-99`tfalla otra cosa") }
if ($fallos.Count -eq 0) { '[INFO] BUILD SUCCESS'; exit 0 }
[void](New-Item -ItemType Directory -Path (Join-Path $raiz 'target') -Force)
[System.IO.File]::WriteAllText((Join-Path $raiz 'target/regresion-fallos.txt'), (($fallos -join "`n") + "`n"))
'[ERROR] Tests run: 1, Failures: 1, Errors: 0, Skipped: 0 <<< FAILURE! - in RegresionLocalTest'
foreach ($f in $fallos) { '[ERROR]   RegresionLocalTest: ' + ($f -replace "`t", ' ') }
exit 1
