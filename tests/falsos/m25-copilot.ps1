# m25-copilot.ps1 - Copilot CLI de mentira para los tests m25 de tests/probar-local.ps1 (-Reparar). Las tareas de arnes y de casos las hace
# copilot-local.ps1. Una tarea 'reparar' hace lo que diga el guion de RESCATE_FALSO ('guion' o 'guion:regex', como en copilot-local.ps1; la
# regex, sobre el id de la tarea). Sin guion, no hace nada. El migrado de los tests lleva minimo=5.01 en src/main/resources/regla.txt y el
# original 5.00: arreglarlo es dejar minimo=5.00 ahi.
#   reparar-arregla    pone minimo=5.00 en src/main/resources/regla.txt
#   reparar-test       lo mismo y, ademas, toca src/test/java/com/acme/nuevo/ReglaTest.java (prohibido), en todos los intentos
#   reparar-test1      como reparar-test, pero solo en el primer intento: el reintento (su prompt lleva la CORRECCION) solo arregla
#   reparar-rompe      arregla y, ademas, pone mayus=si en esa regla: los casos con LATIN dejan la enie en mayuscula, y el original no
#   reparar-sin-tests  arregla y deja src/main/resources/sin-tests.txt: m25-mvn.ps1 ya no ejecuta ninguna clase de la suite
#   reparar-no         no toca nada y escribe .rescate/reparar-no.txt
#   reparar-inutil     solo deja src/main/resources/nota.txt, que ningun Maven falso lee: cambia src/main/ sin cambiar ninguna salida
#   reparar-pasado     pone minimo=4.50 (se pasa del 5.00 del original): arregla los casos de importe=5.00 y estropea los de importe=4.80
#   reparar-cuelga     arregla y pone cuelga=caso-02 en regla.txt: m25-mvn.ps1 se cuelga en ese caso (lo para MinutosMaven)
#   reparar-nada       no toca nada (como cualquier otro nombre)
#   reparar-ruido      (m26) arregla y deja logs/batch.log y datos/h2.mv.db, nuevos en la raiz: lo que deja la ejecucion de un batch
#   reparar-ruido-solo (m26) solo deja logs/batch.log, sin tocar src/main/
#   reparar-test-nuevo (m26) arregla y crea src/test/java/com/acme/nuevo/NuevoTest.java (un fichero nuevo bajo src/ que no es de src/main/)
#   reparar-pom        (m26) arregla y cambia pom.xml, que tiene seguimiento
# Una tarea de caso (la hace copilot-local.ps1) con ' ;; ' en su ENTRADA deja una linea de datos.txt por cada trozo.
# Cada llamada deja en RESCATE_LLAMADAS (si esta) <id>-<pid>.txt con id, tipo, flags y guion.
$texto = ''
for ($i = 0; $i -lt $args.Count; $i++) { if ("$($args[$i])" -eq '-p') { $texto = "$($args[$i + 1])" } }
$raiz = (Get-Location).Path
$id = ''
if ($texto -match 'tareas/([\w\-]+)\.prompt\.md') { $id = $Matches[1] }
$prompt = ''
if ($id) { $prompt = [System.IO.File]::ReadAllText((Join-Path (Join-Path (Join-Path $raiz '.rescate') 'tareas') ($id + '.prompt.md'))) }
function Ruta-M25([string]$Rel) { return [System.IO.Path]::Combine([string[]](@($raiz) + $Rel.Split('/'))) }

if ($prompt -notmatch '(?m)^TIPO: reparar\s*$') {
  & (Join-Path $PSScriptRoot 'copilot-local.ps1') @args
  $rc = $LASTEXITCODE
  if ($prompt -match '(?m)^TIPO: caso-local\s*$' -and $prompt -match '(?m)^CARPETA: (.*?)\s*$') {
    $datos = Ruta-M25 ($Matches[1] + '/ficheros/entrada/datos.txt')
    if (Test-Path -LiteralPath $datos) { [System.IO.File]::WriteAllText($datos, [System.IO.File]::ReadAllText($datos).Replace(';;', "`n")) }
  }
  exit $rc
}
$guion = ''
foreach ($g in ("$env:RESCATE_FALSO" -split ';')) {
  $nombre, $solo = ($g -split ':', 2)
  if (-not $solo) { $solo = '.' }
  if ($nombre -and -not $guion -and $id -match $solo) { $guion = $nombre }
}
if ($env:RESCATE_LLAMADAS) {
  [void](New-Item -ItemType Directory -Path $env:RESCATE_LLAMADAS -Force)
  $flags = (@($args | Where-Object { "$_" -match '^--(model=|effort=|add-dir=)' }) -join ' ')
  [System.IO.File]::WriteAllLines((Join-Path $env:RESCATE_LLAMADAS ($id + '-' + $PID + '.txt')), [string[]]@("id=$id", 'tipo=reparar', "flags=$flags", "guion=$guion"))
}

$regla = Ruta-M25 'src/main/resources/regla.txt'
$reintento = ($prompt -match 'CORRECCI')
if ($guion -in @('reparar-arregla', 'reparar-test', 'reparar-test1', 'reparar-rompe', 'reparar-sin-tests', 'reparar-cuelga', 'reparar-ruido', 'reparar-test-nuevo', 'reparar-pom')) {
  [System.IO.File]::WriteAllText($regla, [System.IO.File]::ReadAllText($regla).Replace('minimo=5.01', 'minimo=5.00'))
}
if ($guion -eq 'reparar-pasado') { [System.IO.File]::WriteAllText($regla, [System.IO.File]::ReadAllText($regla).Replace('minimo=5.01', 'minimo=4.50')) }
if ($guion -eq 'reparar-cuelga') { [System.IO.File]::AppendAllText($regla, "cuelga=caso-02`n") }
if ($guion -eq 'reparar-inutil') { [System.IO.File]::WriteAllText((Ruta-M25 'src/main/resources/nota.txt'), "sin efecto`n") }
if ($guion -eq 'reparar-rompe') { [System.IO.File]::AppendAllText($regla, "mayus=si`n") }
if ($guion -eq 'reparar-test' -or ($guion -eq 'reparar-test1' -and -not $reintento)) {
  $t = Ruta-M25 'src/test/java/com/acme/nuevo/ReglaTest.java'
  [void](New-Item -ItemType Directory -Path (Split-Path $t -Parent) -Force)
  [System.IO.File]::AppendAllText($t, "// tocado por la IA`n")
}
if ($guion -in @('reparar-ruido', 'reparar-ruido-solo')) {
  [void](New-Item -ItemType Directory -Path (Ruta-M25 'logs') -Force)
  [System.IO.File]::WriteAllText((Ruta-M25 'logs/batch.log'), "arranque del batch`n")
}
if ($guion -eq 'reparar-ruido') {
  [void](New-Item -ItemType Directory -Path (Ruta-M25 'datos') -Force)
  [System.IO.File]::WriteAllText((Ruta-M25 'datos/h2.mv.db'), "base h2`n")
}
if ($guion -eq 'reparar-test-nuevo') {
  $t = Ruta-M25 'src/test/java/com/acme/nuevo/NuevoTest.java'
  [void](New-Item -ItemType Directory -Path (Split-Path $t -Parent) -Force)
  [System.IO.File]::WriteAllText($t, "package com.acme.nuevo;`nclass NuevoTest {}`n")
}
if ($guion -eq 'reparar-pom') { [System.IO.File]::AppendAllText((Ruta-M25 'pom.xml'), "<!-- tocado por la IA -->`n") }
if ($guion -eq 'reparar-sin-tests') { [System.IO.File]::WriteAllText((Ruta-M25 'src/main/resources/sin-tests.txt'), "sin tests`n") }
if ($guion -eq 'reparar-no') {
  [void](New-Item -ItemType Directory -Path (Ruta-M25 '.rescate') -Force)
  [System.IO.File]::WriteAllText((Ruta-M25 '.rescate/reparar-no.txt'), "La prueba local simula el correo y en el entorno real ya esta bien.`n")
}
'hecho'
exit 0
