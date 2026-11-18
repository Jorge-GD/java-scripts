# m20b-mvn.ps1 - Maven de mentira para los tests m20b de tests/probar-local.ps1. Pasa todo a mvn-local.ps1 y, en cada 'test', toca
# lo que ese deja en target/prueba-local:
#   IGNORA_ENTRADAS  si algun PruebaLocalTest.java de src/test/java lleva esta marca (un arnes que no le pasa las entradas al job),
#                    cada caso sale como el vacio: se borran ficheros\ y tablas\ de lo que dejo y queda solo estado.txt. Las
#                    entradas de los casos no se tocan.
#   reescribe        cada linea 'reescribe=<texto>=><otro>' de regla.txt (en la carpeta donde se lanza Maven) cambia <texto> por
#                    <otro> en los resultado_*.txt que dejo: un migrado que escribe otra fecha donde el original no tiene la linea.
$raiz = (Get-Location).Path
$test = ($args -contains 'test')
& (Join-Path $PSScriptRoot 'mvn-local.ps1') @args
$codigo = $LASTEXITCODE
$salidas = Join-Path $raiz 'target/prueba-local'
if ($test -and $codigo -eq 0 -and (Test-Path -LiteralPath $salidas)) {
  $tests = Join-Path $raiz 'src/test/java'
  $ignora = (Test-Path -LiteralPath $tests) -and (@(Get-ChildItem -LiteralPath $tests -Recurse -File -Filter 'PruebaLocalTest.java' | Where-Object { [System.IO.File]::ReadAllText($_.FullName) -match 'IGNORA_ENTRADAS' }).Count -gt 0)
  if ($ignora) {
    foreach ($d in @(Get-ChildItem -LiteralPath $salidas -Recurse -Directory | Where-Object { $_.Name -eq 'ficheros' -or $_.Name -eq 'tablas' })) {
      if (Test-Path -LiteralPath $d.FullName) { Remove-Item -LiteralPath $d.FullName -Recurse -Force }
    }
  }
  $regla = Join-Path $raiz 'regla.txt'
  if (Test-Path -LiteralPath $regla) {
    foreach ($l in [System.IO.File]::ReadAllLines($regla)) {
      if ($l -notlike 'reescribe=*') { continue }
      $de, $a = $l.Substring('reescribe='.Length) -split '=>', 2
      foreach ($f in @(Get-ChildItem -LiteralPath $salidas -Recurse -File -Filter 'resultado_*.txt')) {
        $x = [System.IO.File]::ReadAllText($f.FullName)
        if ($x.Contains($de)) { [System.IO.File]::WriteAllText($f.FullName, $x.Replace($de, $a), (New-Object System.Text.UTF8Encoding($false))) }
      }
    }
  }
}
exit $codigo
