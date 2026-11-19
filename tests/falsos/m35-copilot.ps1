# m35-copilot.ps1 - Copilot CLI de mentira para los tests m35 de tests/probar-reglas.ps1 (tests-reglas.ps1). Lee el prompt de
# .rescate/tareas/<id>.prompt.md, saca sus lineas 'FICHERO: <ruta>' (la clase), 'TEST: <ruta>' (donde escribir) y las reglas ('REGLA <n>: <texto>' y,
# debajo, '  Linea <n>: <cita>') y escribe el test segun el guion de RESCATE_FALSO ('guion' o 'guion:regex', varios separados por ';'; la regex, sobre la
# ruta de la clase; gana el primero que encaja; sin guion, 'bien'). El test lleva un metodo por regla y, en el, '// VIGILA: <cita>' (lo que el
# Maven de mentira mira para saber si el test vigila esa linea):
#   bien        un metodo por regla, todos con su VIGILA
#   parcial     como bien, pero sin el VIGILA de la ultima regla (el cambio en esa linea no lo ve)
#   parcial1    como parcial en el primer intento; el reintento (su prompt lleva CORRECCION) hace bien
#   spring      como bien, con @SpringBootTest
#   no-compila  como bien, con una linea que no compila (el Maven de mentira la reconoce por NO-COMPILA)
#   otro        como bien y, ademas, anade un comentario a la clase de src/main y a src/main/java/com/acme/recibos/Recibo.java
#   otro-add    como otro, y ademas deja los ficheros en el indice con 'git add'
#   commit      como bien, y ademas hace un commit en el repositorio (prohibido)
#   nada        no escribe nada
#   falla       no escribe nada y sale con 1
#   falla-cambia  como bien, pero sale con 1
#   falla-previo  como bien, pero cada VIGILA lleva una linea que el codigo no tiene (el test falla contra el codigo tal como esta)
#   sin-tests   como bien, pero sin ningun @Test (el Maven de mentira dice 'Tests run: 0')
# Variables:
#   M35_COPILOT   fichero: cada llamada anade '<clase>|<guion>|<reintento: 0 o 1>'
$texto = ''
for ($i = 0; $i -lt $args.Count; $i++) { if ("$($args[$i])" -eq '-p') { $texto = "$($args[$i + 1])" } }
$raiz = (Get-Location).Path
$prompt = ''
if ($texto -match 'tareas/([\w\-]+)\.prompt\.md') { $prompt = [System.IO.File]::ReadAllText([System.IO.Path]::Combine($raiz, '.rescate', 'tareas', ($Matches[1] + '.prompt.md'))) }
$fichero = ''
if ($prompt -match '(?m)^FICHERO: (.*?)\s*$') { $fichero = $Matches[1] }
$test = ''
if ($prompt -match '(?m)^TEST: (.*?)\s*$') { $test = $Matches[1] }
$guion = 'bien'
$elegido = $false
foreach ($g in ("$env:RESCATE_FALSO" -split ';')) {
  $nombre, $solo = ($g -split ':', 2)
  if (-not $solo) { $solo = '.' }
  if ($nombre -and -not $elegido -and $fichero -match $solo) { $guion = $nombre; $elegido = $true }
}
$reintento = 0
if ($prompt -match 'CORRECCI') { $reintento = 1 }
if ($env:M35_COPILOT) { [System.IO.File]::AppendAllText($env:M35_COPILOT, "$fichero|$guion|$reintento`n") }
if ($guion -eq 'parcial1') { if ($reintento -eq 1) { $guion = 'bien' } else { $guion = 'parcial' } }
function Ruta-Fichero([string]$Rel) { return [System.IO.Path]::Combine([string[]](@($raiz) + $Rel.Split('/'))) }
function Anade-Comentario([string]$Rel) {
  $r = Ruta-Fichero $Rel
  [System.IO.File]::WriteAllText($r, ([System.IO.File]::ReadAllText($r) + "// tocado por la IA`n"))
}
function Escribe-Test([bool]$Spring, [bool]$Rota, [int]$SinVigila, [bool]$Falsa = $false, [bool]$SinTests = $false) {
  $reglas = @()
  $ms = @([regex]::Matches($prompt, '(?m)^REGLA (\d+): ([^\r\n]*)\r?\n[ \t]+Linea (\d+): ([^\r\n]*)'))
  foreach ($m in $ms) { $reglas += , @($m.Groups[2].Value.Trim(), $m.Groups[4].Value.Trim()) }
  $paquete = ''
  $clase = [System.IO.Path]::GetFileNameWithoutExtension($test)
  if ($test -match 'src/test/java/(.+)/[^/]+\.java$') { $paquete = $Matches[1].Replace('/', '.') }
  $t = "package $paquete;`n`nimport org.junit.jupiter.api.DisplayName;`nimport org.junit.jupiter.api.Test;`n`n"
  if ($Spring) { $t += "@SpringBootTest`n" }
  $t += "class $clase {`n"
  for ($i = 0; $i -lt $reglas.Count; $i++) {
    if ($SinTests) { $t += "    void regla$($i + 1)() {`n" }
    else { $t += "    @Test`n    @DisplayName(`"$($reglas[$i][0])`")`n    void regla$($i + 1)() {`n" }
    $vigila = $reglas[$i][1]
    if ($Falsa) { $vigila = 'una linea que el codigo ya no tiene' }
    if ($i -lt ($reglas.Count - $SinVigila)) { $t += "        // VIGILA: $vigila`n" }
    $t += "    }`n`n"
  }
  if ($Rota) { $t += "    int x = NO-COMPILA;`n" }
  $t += "}`n"
  $r = Ruta-Fichero $test
  [void](New-Item -ItemType Directory -Path (Split-Path $r -Parent) -Force)
  [System.IO.File]::WriteAllText($r, $t)
}
switch ($guion) {
  'bien' { Escribe-Test $false $false 0 }
  'parcial' { Escribe-Test $false $false 1 }
  'spring' { Escribe-Test $true $false 0 }
  'no-compila' { Escribe-Test $false $true 0 }
  'falla-previo' { Escribe-Test $false $false 0 $true }
  'sin-tests' { Escribe-Test $false $false 0 $false $true }
  'otro' { Escribe-Test $false $false 0; Anade-Comentario $fichero; Anade-Comentario 'src/main/java/com/acme/recibos/Recibo.java' }
  'otro-add' {
    Escribe-Test $false $false 0
    Anade-Comentario $fichero
    Anade-Comentario 'src/main/java/com/acme/recibos/Recibo.java'
    & git -C $raiz add -- $fichero 'src/main/java/com/acme/recibos/Recibo.java' $test
  }
  'commit' {
    Escribe-Test $false $false 0
    & git -C $raiz add -- $test
    & git -C $raiz -c user.name=IA -c user.email=ia@example.invalid commit -q -m 'la IA commitea'
  }
  'falla' { [Console]::Error.WriteLine('Error de mentira: sin sesion'); exit 1 }
  'falla-cambia' { Escribe-Test $false $false 0; [Console]::Error.WriteLine('Error de mentira: se corto la red'); exit 1 }
}
'hecho'
exit 0
