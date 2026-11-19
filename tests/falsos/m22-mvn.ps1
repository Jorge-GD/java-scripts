# m22-mvn.ps1 - Maven de mentira de las pruebas 'm22' (tests/probar.ps1). Hace lo de mvn.ps1 (compila si ningun .java dice NO_COMPILA) y, con
# 'test', pasa como Surefire los tests de src/test/java y deja un TEST-<clase>.xml por clase que ejecuta:
#   -Dsurefire.excludesFile=<fichero>  no pasa las clases que casan con alguna linea (com/acme/FooTest.* o **/FooTest.*)
#   -Dtest=A,B                         pasa solo esas clases (por nombre simple o con su paquete)
# Una clase falla segun lo que dice su texto (falla su primer metodo):
#   M22_FALLA                  siempre
#   M22_FALLA_CON:<Clase>      si el fuente de esa clase en src/main/java lleva ' + 0;' (lo que le deja el Copilot de mentira al arreglarlo)
#   M22_FALLA_SI_CAMBIA        si la propia clase lleva ' + 0;'
#   M22_INESTABLE:<n>          solo en la suite entera n-esima (sin -Dtest ni excludesFile) de las que pasa este Maven
#   M22_FALLA_DESDE:<n>        en la suite entera n-esima y en las que siguen
# El numero de suites sale de RESCATE_M22_ESTADO (una carpeta donde deja suites.n); sin ella, esas dos marcas no fallan nunca.
# Con RESCATE_M22_LOG (un fichero) cada llamada deja una linea '<carpeta donde corre> | <clases que ejecuta> | <argumentos>'.
$argumentos = @($args)
$raiz = (Get-Location).Path
$registro = "$env:RESCATE_M22_LOG"

function Add-Registro([string]$Clases) {
  if ($registro) { [System.IO.File]::AppendAllText($registro, ((Split-Path $raiz -Leaf) + ' | ' + $Clases + ' | ' + ($argumentos -join ' ') + "`n")) }
}

& (Join-Path $PSScriptRoot 'mvn.ps1') @argumentos
$codigo = $LASTEXITCODE
if ($codigo -ne 0 -or $argumentos -notcontains 'test') { Add-Registro '-'; exit $codigo }

$excluye = ''; $solo = @()
foreach ($a in $argumentos) {
  if ("$a" -match '^-Dsurefire\.excludesFile=(.*)$') { $excluye = $Matches[1] }
  elseif ("$a" -match '^-Dtest=(.*)$') { $solo = @($Matches[1] -split ',') }
}
$patrones = @()
if ($excluye -and (Test-Path -LiteralPath $excluye)) {
  $patrones = @([System.IO.File]::ReadAllLines($excluye) | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
}
function Test-Excluido([string]$Rel) {
  foreach ($p in $patrones) {
    $rx = '^' + (([regex]::Escape($p) -replace '\\\*\\\*/', '(.*/)?') -replace '\\\*', '[^/]*') + '$'
    if ($Rel -match $rx) { return $true }
  }
  return $false
}

# Cuantas suites enteras lleva este Maven (la de ahora incluida), si hay donde contarlas.
$suite = 0
if (-not $excluye -and $solo.Count -eq 0 -and $env:RESCATE_M22_ESTADO) {
  [void](New-Item -ItemType Directory -Path $env:RESCATE_M22_ESTADO -Force)
  $f = Join-Path $env:RESCATE_M22_ESTADO 'suites.n'
  if (Test-Path -LiteralPath $f) { $suite = [int][System.IO.File]::ReadAllText($f).Trim() }
  $suite++
  [System.IO.File]::WriteAllText($f, "$suite")
}

$base = Join-Path (Join-Path (Join-Path $raiz 'src') 'test') 'java'
$rep = Join-Path (Join-Path $raiz 'target') 'surefire-reports'
[void](New-Item -ItemType Directory -Path $rep -Force)
$main = @(Get-ChildItem -LiteralPath (Join-Path (Join-Path $raiz 'src') 'main') -Recurse -File -Filter '*.java' -ErrorAction SilentlyContinue)
$ejecutadas = @(); $rotas = 0
foreach ($f in @(Get-ChildItem -LiteralPath $base -Recurse -File -Filter '*.java' -ErrorAction SilentlyContinue)) {
  $rel = ($f.FullName.Substring($base.Length).TrimStart('\', '/') -replace '\\', '/')
  $texto = [System.IO.File]::ReadAllText($f.FullName)
  $paq = [regex]::Match($texto, '(?m)^package\s+([\w.]+);').Groups[1].Value
  $clase = $f.BaseName
  if ($paq) { $clase = $paq + '.' + $f.BaseName }
  if ($solo.Count -gt 0) { if (($solo -notcontains $clase) -and ($solo -notcontains $f.BaseName)) { continue } }
  elseif (Test-Excluido $rel) { continue }

  $falla = ($texto -match 'M22_FALLA\b(?!_)')
  $m = [regex]::Match($texto, 'M22_FALLA_CON:(\w+)')
  if ($m.Success) {
    foreach ($j in @($main | Where-Object { $_.BaseName -eq $m.Groups[1].Value })) { if ([System.IO.File]::ReadAllText($j.FullName).Contains(' + 0;')) { $falla = $true } }
  }
  if ($texto -match 'M22_FALLA_SI_CAMBIA' -and $texto.Contains(' + 0;')) { $falla = $true }
  $m = [regex]::Match($texto, 'M22_INESTABLE:(\d+)')
  if ($m.Success -and $suite -gt 0 -and $suite -eq [int]$m.Groups[1].Value) { $falla = $true }
  $m = [regex]::Match($texto, 'M22_FALLA_DESDE:(\d+)')
  if ($m.Success -and $suite -gt 0 -and $suite -ge [int]$m.Groups[1].Value) { $falla = $true }

  $metodos = @([regex]::Matches($texto, '@Test\b[^{;]*?\bvoid\s+(\w+)\s*\(') | ForEach-Object { $_.Groups[1].Value })
  if ($metodos.Count -eq 0) { $metodos = @('test') }
  $rotos = 0; if ($falla) { $rotos = 1 }
  $xml = New-Object System.Collections.Generic.List[string]
  $xml.Add('<?xml version="1.0" encoding="UTF-8"?>')
  $xml.Add('<testsuite name="' + $clase + '" time="0.01" tests="' + $metodos.Count + '" errors="0" skipped="0" failures="' + $rotos + '">')
  for ($k = 0; $k -lt $metodos.Count; $k++) {
    $cab = '  <testcase name="' + $metodos[$k] + '" classname="' + $clase + '" time="0.001"'
    if ($falla -and $k -eq 0) {
      $xml.Add($cab + '>')
      $xml.Add('    <failure message="expected: &lt;1&gt; but was: &lt;2&gt;" type="org.opentest4j.AssertionFailedError">org.opentest4j.AssertionFailedError: expected: &lt;1&gt; but was: &lt;2&gt;')
      $xml.Add("`tat $clase.$($metodos[$k])($($f.Name):1)")
      $xml.Add('</failure>')
      $xml.Add('  </testcase>')
    }
    else { $xml.Add($cab + '/>') }
  }
  $xml.Add('</testsuite>')
  [System.IO.File]::WriteAllText((Join-Path $rep "TEST-$clase.xml"), (($xml -join "`n") + "`n"))
  $ejecutadas += $f.BaseName
  $rotas += $rotos
}
Add-Registro ($ejecutadas -join ',')
if ($rotas -gt 0) { "[ERROR] Tests run: $($ejecutadas.Count), Failures: $rotas, Errors: 0, Skipped: 0"; exit 1 }
exit 0
