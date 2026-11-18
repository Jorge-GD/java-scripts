# cobertura-copilot.ps1 - Copilot CLI de mentira para el grupo 'm14 cobertura' de tests/probar.ps1.
# Lee .rescate/prompt.md. En un lote de cobertura (la clase va en la primera linea '- <ruta>.java - <cubiertas>/<total> lineas ...' de
# la seccion 'Hallazgos de este lote') escribe o amplia src/test/java/<paquete>/<Clase>Test.java con un test que lleva el marcador
# '// CUBRE: n' que lee cobertura-mvn.ps1. Con cualquier otro prompt (consejo, reflexion) no hace nada.
# RESCATE_FALSO son guiones 'nombre' o 'nombre:regex' (regex sobre el nombre de la clase; sin regex, para todas) separados por ';'; gana
# el primero que encaja y las demas clases salen bien:
#   (vacio)            un test con aserciones que cubre toda la clase (CUBRE: 1000)
#   cob-parcial        cubre solo 2 lineas mas (RESCATE_COB_SUBE las cambia)
#   cob-no-sube        un test con asercion que no cubre nada nuevo (CUBRE: 0)
#   cob-toca-main      ademas cambia la fuente de src/main/java
#   cob-toca-pom       ademas cambia el pom.xml
#   cob-rompe-otra     cubre 2 lineas mas y pone a 0 el CUBRE de los tests de las otras clases (el total baja)
#   cob-sin-asercion   un test sin aserciones
#   cob-assert-true    un test cuya unica asercion es assertTrue(true)
#   cob-disabled       un test con @Disabled
#   cob-sleep          un test con Thread.sleep
#   cob-catch-vacio    un test con un catch vacio
#   cob-ojo            un test bueno, con el comentario '// OJO: parece un error: suma al reves'
#   cob-test-falla     un test que contiene TEST_FALLA (el Maven falso lo hace fallar)
#   cob-quita-asercion quita las aserciones del test que ya existia (no anade ninguno)
#   cob-otro-fichero   escribe un test bueno en OtraTest.java y no en <Clase>Test.java
#   cob-nada           no cambia nada
# Cada llamada deja una linea en .rescate/llamadas.log con la clase y el guion aplicado.
if ($args -contains '--version') { 'GitHub Copilot CLI 1.0.112 (de mentira).'; exit 0 }
$raiz = (Get-Location).Path
$rescate = Join-Path $raiz '.rescate'
$prompt = [System.IO.File]::ReadAllText((Join-Path $rescate 'prompt.md'))
$titulo = ($prompt -split "`r?`n")[0]
if ($titulo -notmatch "^# Tarea de cobertura") { 'hecho'; exit 0 }

function Get-Ruta([string]$Rel) {
  $p = $raiz
  foreach ($s in $Rel.Split('/')) { if ($s) { $p = Join-Path $p $s } }
  return $p
}
function Escribir([string]$Rel, [string]$Texto) {
  $ruta = Get-Ruta $Rel
  $dir = Split-Path $ruta -Parent
  if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
  [System.IO.File]::WriteAllText($ruta, $Texto)
}

# la clase del lote: el primer '- <ruta>.java - ' despues de 'Hallazgos de este lote'
$fichero = ''
$dentro = $false
foreach ($l in ($prompt -split "`r?`n")) {
  if ($l -match '^## Hallazgos de este lote') { $dentro = $true; continue }
  if ($dentro -and $l -match '^## ') { break }
  if ($dentro -and $l -match '^- (\S+\.java) - ') { $fichero = $Matches[1]; break }
}
if (-not $fichero) { 'hecho'; exit 0 }
$clase = [System.IO.Path]::GetFileNameWithoutExtension($fichero)
$paquete = (Split-Path ($fichero -replace '^src/main/java/', '') -Parent) -replace '\\', '/'
$test = "src/test/java/$paquete/${clase}Test.java"

$guion = ''
foreach ($g in ("$env:RESCATE_FALSO" -split ';')) {
  $nombre, $solo = ($g -split ':', 2)
  if ($nombre -notlike 'cob-*' -or $nombre -eq 'cob-mvn-error' -or $nombre -eq 'cob-inestable') { continue }
  if (-not $solo -or $clase -match $solo) { $guion = $nombre; break }
}
[System.IO.File]::AppendAllText((Join-Path $rescate 'llamadas.log'), "cobertura | $clase | $guion`n")
if ($guion -eq 'cob-nada') { 'hecho'; exit 0 }
if ($guion -eq 'cob-quita-asercion') {
  if (Test-Path -LiteralPath (Get-Ruta $test)) {
    $sin = @([System.IO.File]::ReadAllText((Get-Ruta $test)) -split "\r?\n" | Where-Object { $_ -notmatch '\bassert\w*\s*\(' })
    Escribir $test ($sin -join "`n")
  }
  'hecho'; exit 0
}

$sube = 1000
if ($guion -eq 'cob-no-sube') { $sube = 0 }
if ($guion -in @('cob-parcial', 'cob-rompe-otra')) { $sube = 2; if ($env:RESCATE_COB_SUBE) { $sube = [int]$env:RESCATE_COB_SUBE } }

$nombreTest = "${clase}Test"
if ($guion -eq 'cob-otro-fichero') { $nombreTest = 'OtraTest'; $test = "src/test/java/$paquete/OtraTest.java" }
$existe = Test-Path -LiteralPath (Get-Ruta $test)
$texto = ''
if ($existe) { $texto = [System.IO.File]::ReadAllText((Get-Ruta $test)) }
$n = [regex]::Matches($texto, '@Test').Count + 1

$antes = ''
$cuerpo = "        assertEquals(3, new $clase().suma(1, 2));"
$anota = '    @Test'
if ($guion -eq 'cob-sin-asercion') { $cuerpo = "        int x = new $clase().suma(1, 2);" }
if ($guion -eq 'cob-assert-true') { $cuerpo = "        org.junit.jupiter.api.Assertions.assertTrue(true);" }
if ($guion -eq 'cob-disabled') { $anota = "    @org.junit.jupiter.api.Disabled`n    @Test" }
if ($guion -eq 'cob-sleep') { $cuerpo = "        try { Thread.sleep(10); } catch (InterruptedException e) { throw new IllegalStateException(e); }`n" + $cuerpo }
if ($guion -eq 'cob-catch-vacio') { $cuerpo = "        try { new $clase().suma(1, 2); } catch (RuntimeException e) { }`n" + $cuerpo }
if ($guion -eq 'cob-test-falla') { $cuerpo = "        // TEST_FALLA`n" + $cuerpo }
if ($guion -eq 'cob-ojo') { $cuerpo = "        // OJO: parece un error: suma al reves`n" + $cuerpo }
$metodo = "$anota`n    void cubre$n() {`n$cuerpo`n        // CUBRE: $sube`n    }`n"

if ($existe) {
  $i = $texto.LastIndexOf('}')
  Escribir $test ($texto.Substring(0, $i).TrimEnd() + "`n`n" + $metodo + "}`n")
}
else {
  $pq = ($paquete -replace '/', '.')
  Escribir $test "package $pq;`n`nimport static org.junit.jupiter.api.Assertions.assertEquals;`n`nimport org.junit.jupiter.api.Test;`n`nclass $nombreTest {`n`n$metodo}`n"
}
if ($guion -eq 'cob-toca-main') { [System.IO.File]::AppendAllText((Get-Ruta $fichero), "`n// tocado por el modelo`n") }
if ($guion -eq 'cob-toca-pom') { [System.IO.File]::AppendAllText((Get-Ruta 'pom.xml'), "`n<!-- tocado -->`n") }
if ($guion -eq 'cob-rompe-otra') {
  foreach ($f in @(Get-ChildItem -LiteralPath (Get-Ruta 'src/test') -Recurse -File -Filter '*Test.java' | Where-Object { $_.BaseName -ne "${clase}Test" })) {
    [System.IO.File]::WriteAllText($f.FullName, ([System.IO.File]::ReadAllText($f.FullName) -replace '//\s*CUBRE:\s*\d+', '// CUBRE: 0'))
  }
}
'hecho'
exit 0
