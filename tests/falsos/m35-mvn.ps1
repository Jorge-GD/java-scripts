# m35-mvn.ps1 - Maven de mentira para los tests m35 de tests/probar-reglas.ps1 (tests-reglas.ps1).
# Nunca compila ni ejecuta Java. Dos llamadas:
#   'mvn -B test-compile'  sale con 0, salvo que no compile: algun .java de src lleva NO-COMPILA, o algun .java de src/main encaja con la regex de
#                          M35_NO_COMPILA (la forma de decir 'el cambio que se hace en esta linea ya no compila').
#   'mvn -B test -Dtest=<Clase>...'  lo mismo para la compilacion; despues busca src/test/java/**/<Clase>.java y lo 'ejecuta' asi: cada metodo
#                          '@Test' cuenta como un test, y cada linea '// VIGILA: <trozo>' del test falla si <trozo> ya no sale en el .java de
#                          src/main con el mismo nombre sin 'ReglasTest' y la misma carpeta (la linea de la regla se cambio: el test la vigila).
#                          Imprime como surefire (Tests run, Failures, BUILD) y sale con 1 si algo falla. Sin test, 'Tests run: 0'.
# Variables:
#   M35_LLAMADAS    fichero: cada llamada anade '<carpeta>|<argumentos>|<lineas cambiadas de src/main segun git, separadas por ;;>'
#   M35_NO_COMPILA  regex: un .java de src/main que la cumple no compila
#   M35_ROMPE       con ella (un .java bajo src/main/java), una llamada 'test' con src/main cambiado (un mutante) deja ese fichero hecho un
#                   directorio y pone .git/index.lock: ni se puede volver a escribir el fichero ni git lo puede restaurar
if ($args -contains '--version') { 'Apache Maven 3.9.8 (de mentira)'; exit 0 }
$raiz = (Get-Location).Path
$cambiadas = @(& git -C $raiz diff -U0 -- src/main 2>$null | Where-Object { $_ -match '^\+[^+]' } | ForEach-Object { $_.Substring(1) })
if ($env:M35_LLAMADAS) { [System.IO.File]::AppendAllText($env:M35_LLAMADAS, $raiz + '|' + ($args -join ' ') + '|' + ($cambiadas -join ';;') + "`n") }
$esTest = ($args -contains 'test')
$esCompile = ($args -contains 'test-compile')
if (-not ($esTest -or $esCompile)) { exit 0 }
'[INFO] Scanning for projects...'
$src = Join-Path $raiz 'src'
$errores = @()
if (Test-Path -LiteralPath $src) {
  foreach ($f in @(Get-ChildItem -LiteralPath $src -Recurse -File -Filter '*.java' | Sort-Object FullName)) {
    $t = [System.IO.File]::ReadAllText($f.FullName)
    $rel = $f.FullName.Substring($raiz.Length + 1).Replace('\', '/')
    if ($t.Contains('NO-COMPILA')) { $errores += $rel }
    elseif ($env:M35_NO_COMPILA -and $rel -like 'src/main/*' -and $t -match $env:M35_NO_COMPILA) { $errores += $rel }
  }
}
if ($errores.Count -gt 0) {
  '[ERROR] COMPILATION ERROR : '
  foreach ($e in $errores) { "[ERROR] $e`:[1,1] no compila (de mentira)" }
  '[INFO] BUILD FAILURE'
  exit 1
}
if ($esCompile) { '[INFO] BUILD SUCCESS'; exit 0 }
$clase = ''
foreach ($a in $args) { if ("$a" -match '^-Dtest=(.+)$') { $clase = $Matches[1] } }
$test = $null
if ($clase) { $test = @(Get-ChildItem -LiteralPath $src -Recurse -File -Filter ($clase + '.java') -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match '[\\/]src[\\/]test[\\/]java[\\/]' })[0] }
if ($env:M35_ROMPE -and $cambiadas.Count -gt 0) {
  $r = [System.IO.Path]::Combine($raiz, 'src', 'main', 'java', $env:M35_ROMPE)
  if (Test-Path -LiteralPath $r -PathType Leaf) {
    Remove-Item -LiteralPath $r -Force
    [void](New-Item -ItemType Directory -Path $r -Force)
    [System.IO.File]::WriteAllText((Join-Path $r 'x.txt'), 'x')
    [System.IO.File]::WriteAllText((Join-Path (Join-Path $raiz '.git') 'index.lock'), '')
  }
}
if (-not $test) {
  '[INFO] No tests to run.'
  '[INFO] BUILD SUCCESS'
  exit 0
}
$codigo = [System.IO.File]::ReadAllText($test.FullName)
$principal = $test.FullName.Replace('/src/test/java/', '/src/main/java/').Replace('\src\test\java\', '\src\main\java\') -replace 'ReglasTest\.java$', '.java'
$main = ''
if (Test-Path -LiteralPath $principal -PathType Leaf) { $main = [System.IO.File]::ReadAllText($principal) }
$tests = [regex]::Matches($codigo, '(?m)^\s*@Test\b').Count
$fallos = @()
$k = 0
foreach ($m in [regex]::Matches($codigo, '(?m)^\s*// VIGILA: (.*?)\s*$')) {
  $k++
  if (-not $main.Contains($m.Groups[1].Value)) { $fallos += "regla$k : la linea vigilada ya no es la de antes ($($m.Groups[1].Value))" }
}
"[INFO] Running $clase"
if ($fallos.Count -gt 0) {
  "[ERROR] Tests run: $tests, Failures: $($fallos.Count), Errors: 0, Skipped: 0, Time elapsed: 0.01 s <<< FAILURE! - in $clase"
  '[ERROR] Failures: '
  foreach ($f in $fallos) { "[ERROR]   $clase.$f" }
  "[ERROR] Tests run: $tests, Failures: $($fallos.Count), Errors: 0, Skipped: 0"
  '[INFO] BUILD FAILURE'
  exit 1
}
"[INFO] Tests run: $tests, Failures: 0, Errors: 0, Skipped: 0"
'[INFO] BUILD SUCCESS'
exit 0
