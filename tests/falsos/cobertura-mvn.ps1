# cobertura-mvn.ps1 - Maven de mentira para el grupo 'm14 cobertura' de tests/probar.ps1. Hace lo de mvn.ps1 (compila, falla con
# NO_COMPILA o TEST_FALLA) y ademas:
#  - el paso de JaCoCo deja target/site/jacoco/jacoco.csv y jacoco.xml sacados de marcadores: cada fuente de src/main/java con un
#    '// LINEAS: n' es una clase de n lineas; las cubiertas son la suma de los '// CUBRE: n' de los ficheros <Clase>Test.java de
#    src/test/java (sin pasar de n). Con RESCATE_JACOCO_CSV (una ruta) deja ese fichero como jacoco.csv, como mvn.ps1.
#  - una llamada con -Dtest=<clases> deja una linea en .rescate/cobertura-rep.log. Con el guion cob-inestable en RESCATE_FALSO, la
#    segunda de cada tres sale con 1 ('[ERROR] Tests run: 1, Failures: 1'): un test que a veces pasa y a veces no.
#  - con el guion cob-mvn-error:<texto>, el paso de JaCoCo sale con 1 y '[ERROR] <texto>' (la cobertura no se puede medir).
if ($args -contains '--version') { & (Join-Path $PSScriptRoot 'mvn.ps1') @args; exit $LASTEXITCODE }
$raiz = (Get-Location).Path
$resc = Join-Path $raiz '.rescate'
$conJacoco = (@($args | Where-Object { "$_" -match 'jacoco-maven-plugin' }).Count -gt 0)
$guion = "$env:RESCATE_FALSO"
if (Test-Path -LiteralPath $resc) { [System.IO.File]::AppendAllText((Join-Path $resc 'cobertura-mvn.log'), (($args -join ' ') + "`n")) }
$prueba = @($args | Where-Object { "$_" -like '-Dtest=*' })
if ($prueba.Count -gt 0 -and (Test-Path -LiteralPath $resc)) {
  [System.IO.File]::AppendAllText((Join-Path $resc 'cobertura-rep.log'), ($prueba[0] + "`n"))
  if ($guion -match 'cob-inestable') {
    $cont = Join-Path $resc 'cobertura-rep.cnt'
    $n = 0
    if (Test-Path -LiteralPath $cont) { $n = [int][System.IO.File]::ReadAllText($cont).Trim() }
    $n++
    [System.IO.File]::WriteAllText($cont, "$n")
    if ($n % 3 -eq 2) { '[ERROR] Tests run: 1, Failures: 1, Errors: 0, Skipped: 0'; exit 1 }
  }
}
if ($conJacoco -and $guion -match 'cob-mvn-error:(.*)$') { '[ERROR] ' + $Matches[1]; exit 1 }
if ($conJacoco -and $env:RESCATE_JACOCO_CSV) { & (Join-Path $PSScriptRoot 'mvn.ps1') @args; exit $LASTEXITCODE }
$resto = @($args | Where-Object { "$_" -notmatch 'jacoco-maven-plugin' })
& (Join-Path $PSScriptRoot 'mvn.ps1') @resto
$codigo = $LASTEXITCODE
if ($codigo -ne 0) { exit $codigo }
if ($conJacoco) {
  $dest = Join-Path $raiz 'target/site/jacoco'
  [void](New-Item -ItemType Directory -Path $dest -Force)
  $tests = @(Get-ChildItem -LiteralPath (Join-Path $raiz 'src/test') -Recurse -File -Filter '*Test.java' -ErrorAction SilentlyContinue)
  $csv = @('GROUP,PACKAGE,CLASS,INSTRUCTION_MISSED,INSTRUCTION_COVERED,BRANCH_MISSED,BRANCH_COVERED,LINE_MISSED,LINE_COVERED,COMPLEXITY_MISSED,COMPLEXITY_COVERED,METHOD_MISSED,METHOD_COVERED')
  $xml = New-Object System.Collections.Generic.List[string]
  $xml.Add('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
  $xml.Add('<!DOCTYPE report PUBLIC "-//JACOCO//DTD Report 1.1//EN" "report.dtd">')
  $xml.Add('<report name="batch">')
  foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $raiz 'src/main') -Recurse -File -Filter '*.java' -ErrorAction SilentlyContinue | Sort-Object FullName)) {
    $t = [System.IO.File]::ReadAllText($f.FullName)
    $m = [regex]::Match($t, '//\s*LINEAS:\s*(\d+)')
    if (-not $m.Success) { continue }
    $total = [int]$m.Groups[1].Value
    $paq = [regex]::Match($t, '(?m)^package\s+([\w.]+);').Groups[1].Value
    $cub = 0
    foreach ($x in @($tests | Where-Object { $_.BaseName -eq ($f.BaseName + 'Test') })) {
      foreach ($c in [regex]::Matches([System.IO.File]::ReadAllText($x.FullName), '//\s*CUBRE:\s*(\d+)')) { $cub += [int]$c.Groups[1].Value }
    }
    if ($cub -gt $total) { $cub = $total }
    $csv += "batch,$paq,$($f.BaseName),$(($total - $cub) * 3),$($cub * 3),0,0,$($total - $cub),$cub,1,1,1,1"
    $xml.Add('<package name="' + $paq.Replace('.', '/') + '"><sourcefile name="' + $f.Name + '">')
    for ($i = 1; $i -le $total; $i++) {
      if ($i -le $cub) { $xml.Add('<line nr="' + $i + '" mi="0" ci="3"/>') } else { $xml.Add('<line nr="' + $i + '" mi="3" ci="0"/>') }
    }
    $xml.Add('</sourcefile></package>')
  }
  $xml.Add('</report>')
  [System.IO.File]::WriteAllText((Join-Path $dest 'jacoco.csv'), (($csv -join "`n") + "`n"))
  [System.IO.File]::WriteAllText((Join-Path $dest 'jacoco.xml'), (($xml -join "`n") + "`n"))
}
exit 0
