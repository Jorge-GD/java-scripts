# m20a-copilot.ps1 - Copilot de mentira de los grupos 'm20a' de tests/probar.ps1: en cada lote, antes de arreglar como siempre (copilot-m6.ps1),
# toca el test FacturaServiceTest o el pom como diga RESCATE_FALSO (varios guiones se separan con ';'; los demas son de copilot-m6.ps1):
#   m20a-rompe-mas      todos los metodos de FacturaServiceTest pasan a fallar (M20A_FALLA)
#   m20a-borra-metodo   borra la linea del metodo que falla (el fichero se queda)
#   m20a-comenta-metodo la linea del metodo que falla pasa a comentario (//)
#   m20a-salta-metodo   el metodo que falla pasa a llevar @DisabledOnOs(OS.LINUX): se salta
#   m20a-vacia-test     la clase se queda sin ningun metodo
#   m20a-skip-pom       el pom pone <skipTests>true</skipTests> en la configuracion del plugin de surefire
# Solo toca en un lote (el prompt dice "rescate de migracion: paso '<paso>'"); lo demas se lo pasa a copilot-m6.ps1.
$raiz = (Get-Location).Path
$guiones = @("$env:RESCATE_FALSO" -split ';' | Where-Object { $_ })
$rutaPrompt = Join-Path (Join-Path $raiz '.rescate') 'prompt.md'
$titulo = ''
if (Test-Path -LiteralPath $rutaPrompt) { $titulo = ([System.IO.File]::ReadAllText($rutaPrompt) -split "`r?`n")[0] }
if ($titulo -match "rescate de migracion: paso '\w+'") {
  $test = Join-Path $raiz 'src/test/java/com/acme/life/FacturaServiceTest.java'
  if (Test-Path -LiteralPath $test) {
    $lineas = @([System.IO.File]::ReadAllLines($test))
    if ($guiones -contains 'm20a-rompe-mas') { $lineas = @($lineas | ForEach-Object { if ($_ -match '@Test' -and $_ -notmatch 'M20A_FALLA') { $_ -replace '\{ \}', '{ /* M20A_FALLA */ }' } else { $_ } }) }
    if ($guiones -contains 'm20a-borra-metodo') { $lineas = @($lineas | Where-Object { $_ -notmatch 'M20A_FALLA' }) }
    if ($guiones -contains 'm20a-comenta-metodo') { $lineas = @($lineas | ForEach-Object { if ($_ -match 'M20A_FALLA') { '    // ' + $_.Trim() } else { $_ } }) }
    if ($guiones -contains 'm20a-salta-metodo') { $lineas = @($lineas | ForEach-Object { if ($_ -match 'M20A_FALLA') { $_ -replace '@Test', '@DisabledOnOs(OS.LINUX) @Test' } else { $_ } }) }
    if ($guiones -contains 'm20a-vacia-test') { $lineas = @('package com.acme.life;', '', 'class FacturaServiceTest {', '}') }
    [System.IO.File]::WriteAllText($test, (($lineas -join "`n") + "`n"))
  }
  if ($guiones -contains 'm20a-skip-pom') {
    $rutaPom = Join-Path $raiz 'pom.xml'
    $bloque = '<build><plugins><plugin><artifactId>maven-surefire-plugin</artifactId><configuration><skipTests>true</skipTests></configuration></plugin></plugins></build>'
    [System.IO.File]::WriteAllText($rutaPom, ([System.IO.File]::ReadAllText($rutaPom) -replace '</project>', ($bloque + "`n</project>")))
  }
}
& (Join-Path $PSScriptRoot 'copilot-m6.ps1') @args
exit $LASTEXITCODE
