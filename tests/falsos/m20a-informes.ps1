# m20a-informes.ps1 - Deja los informes de surefire (target/surefire-reports) de lo que hay en src/test/java, como los dejaria Maven con 'test', y
# sale con 1 si algun test falla. Lo llaman m20a-mvn.ps1 y m20a-cobertura-mvn.ps1 cuando su Maven de mentira sale con 0.
# Cada metodo de test es una linea '@Test ... void nombre(...) {...}' y lo que dice esa linea decide su estado:
#   M20A_FALLA                   el test falla
#   M20A_SALTA o @Disabled...    el test se salta (tambien con @DisabledOnOs, que rescate.ps1 no ve como @Disabled)
# Un fichero de test sin ningun metodo @Test cuenta como un test que pasa (los repos de juguete del banco los traen asi).
# El pom manda, como en Maven: un <skipTests>true</skipTests> dentro de <configuration> no ejecuta nada (gana al -DskipTests=false de la linea
# de comandos) y un <testFailureIgnore>true</testFailureIgnore> hace salir con 0 aunque falle algun test.
# M20A_FORMATO: (vacio) deja el .xml y el .txt de cada clase, como surefire; txt, solo el .txt (surefire antiguos); xml-roto, un .xml
# cortado a la mitad y el .txt; xml-sin-casos, un .xml con los fallos en la cabecera de la clase y ningun <testcase> que falle.
$raiz = (Get-Location).Path
$pom = ''
$rutaPom = Join-Path $raiz 'pom.xml'
if (Test-Path -LiteralPath $rutaPom) { $pom = [System.IO.File]::ReadAllText($rutaPom) }
$srcTest = Join-Path (Join-Path $raiz 'src') 'test'
$srcTest = Join-Path $srcTest 'java'
if ($pom -match '(?s)<configuration>.*?<skipTests>\s*true\s*</skipTests>' -or -not (Test-Path -LiteralPath $srcTest)) { exit 0 }
$rep = Join-Path (Join-Path $raiz 'target') 'surefire-reports'
[void](New-Item -ItemType Directory -Path $rep -Force)
$formato = "$env:M20A_FORMATO"
$fallan = 0
foreach ($f in @(Get-ChildItem -LiteralPath $srcTest -Recurse -File -Filter '*.java')) {
  $texto = [System.IO.File]::ReadAllText($f.FullName)
  $paq = [regex]::Match($texto, '(?m)^package\s+([\w.]+);').Groups[1].Value
  $clase = $f.BaseName
  if ($paq) { $clase = $paq + '.' + $f.BaseName }
  $metodos = @()
  foreach ($l in ($texto -split "`r?`n")) {
    if ($l -match '^\s*//') { continue }
    $m = [regex]::Match($l, '@(Test|ParameterizedTest|RepeatedTest|TestFactory)\b.*?\bvoid\s+(\w+)\s*\(')
    if (-not $m.Success) { continue }
    $estado = 'pasa'
    if ($l -match 'M20A_SALTA|@Disabled') { $estado = 'salta' }
    elseif ($l -match 'M20A_FALLA') { $estado = 'falla' }
    $metodos += [pscustomobject]@{ Nombre = $m.Groups[2].Value; Estado = $estado }
  }
  if ($metodos.Count -eq 0) { $metodos = @([pscustomobject]@{ Nombre = 'test'; Estado = 'pasa' }) }
  $rotos = @($metodos | Where-Object { $_.Estado -eq 'falla' })
  $saltados = @($metodos | Where-Object { $_.Estado -eq 'salta' })
  $fallan += $rotos.Count

  $xml = New-Object System.Collections.Generic.List[string]
  $xml.Add('<?xml version="1.0" encoding="UTF-8"?>')
  $xml.Add('<testsuite name="' + $clase + '" time="0.01" tests="' + $metodos.Count + '" errors="0" skipped="' + $saltados.Count + '" failures="' + $rotos.Count + '">')
  foreach ($m in $metodos) {
    $cab = '  <testcase name="' + $m.Nombre + '" classname="' + $clase + '" time="0.001"'
    if ($m.Estado -eq 'pasa' -or ($m.Estado -eq 'falla' -and $formato -eq 'xml-sin-casos')) { $xml.Add($cab + '/>') }
    elseif ($m.Estado -eq 'salta') { $xml.Add($cab + '><skipped/></testcase>') }
    else {
      $xml.Add($cab + '>')
      $xml.Add('    <failure message="expected: &lt;1&gt; but was: &lt;2&gt;" type="org.opentest4j.AssertionFailedError">org.opentest4j.AssertionFailedError: expected: &lt;1&gt; but was: &lt;2&gt;')
      $xml.Add("`tat $clase.$($m.Nombre)($($f.Name):1)")
      $xml.Add('</failure>')
      $xml.Add('  </testcase>')
    }
  }
  $xml.Add('</testsuite>')

  $marca = ''
  if ($rotos.Count -gt 0) { $marca = ' <<< FAILURE!' }
  $txt = @('-------------------------------------------------------------------------------', "Test set: $clase", '-------------------------------------------------------------------------------')
  $txt += "Tests run: $($metodos.Count), Failures: $($rotos.Count), Errors: 0, Skipped: $($saltados.Count), Time elapsed: 0.01 s$marca - in $clase"
  foreach ($m in $rotos) {
    $txt += "$($m.Nombre)  Time elapsed: 0.001 s  <<< FAILURE!"
    $txt += 'org.opentest4j.AssertionFailedError: expected: <1> but was: <2>'
    $txt += "`tat $clase.$($m.Nombre)($($f.Name):1)"
  }

  if ($formato -eq 'xml-roto') { [System.IO.File]::WriteAllText((Join-Path $rep "TEST-$clase.xml"), (($xml | Select-Object -First 3) -join "`n")) }
  elseif ($formato -ne 'txt') { [System.IO.File]::WriteAllText((Join-Path $rep "TEST-$clase.xml"), (($xml -join "`n") + "`n")) }
  [System.IO.File]::WriteAllText((Join-Path $rep "$clase.txt"), (($txt -join "`n") + "`n"))
}
if ($fallan -gt 0 -and $pom -notmatch '<testFailureIgnore>\s*true\s*</testFailureIgnore>') {
  "[ERROR] Tests run: $fallan, Failures: $fallan, Errors: 0, Skipped: 0"
  exit 1
}
exit 0
