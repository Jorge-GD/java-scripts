# m30-mvn.ps1 - Maven de mentira para los tests m30 de tests/probar-local.ps1. Hace lo de m25-mvn.ps1 (y con el, lo de mvn-local.ps1) y, antes:
# si algun .java de src/test lleva NECESITA_MAIN y ningun .java de src/main lleva MAIN_TOCADO, no compila (el arnes del guion
# 'arnes-solo-con-main' de m30-copilot.ps1 solo compila con el cambio de src/main que prueba-local.ps1 deshace).
$raiz = (Get-Location).Path
$tests = Join-Path $raiz 'src/test'
$main = Join-Path $raiz 'src/main'
function Con-Texto([string]$Dir, [string]$Texto) {
  if (-not (Test-Path -LiteralPath $Dir)) { return @() }
  return @(Get-ChildItem -LiteralPath $Dir -Recurse -File -Filter '*.java' | Where-Object { [System.IO.File]::ReadAllText($_.FullName) -match $Texto })
}
if ((Con-Texto $tests 'NECESITA_MAIN').Count -gt 0 -and (Con-Texto $main 'MAIN_TOCADO').Count -eq 0) {
  '[ERROR] COMPILATION ERROR : '
  '[ERROR] PruebaLocalTest.java:[1,1] simbolo de mentira no encontrado: MAIN_TOCADO'
  exit 1
}
& (Join-Path $PSScriptRoot 'm25-mvn.ps1') @args
exit $LASTEXITCODE
