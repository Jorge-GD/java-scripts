# m65-mvn.ps1 - Maven de mentira del grupo m65 de tests/probar-practicas.ps1 (arreglo-practicas.ps1: Lombok en el pom.xml). Es bp4-mvn.ps1 (el
# mismo '<carpeta>|<argumentos>' en BP4_LLAMADAS y los mismos .class de mentira) con un fallo mas: con M65_ROTO, un 'mvn -B compile' en una
# carpeta cuyo pom.xml nombra a Lombok no compila (se imprime el error y se sale con 1), como un pom con una dependencia o un procesador
# que Maven no resuelve. Sin M65_ROTO, o en un pom sin Lombok, es el de BP-4.
$pom = Join-Path (Get-Location).Path 'pom.xml'
if ($env:M65_ROTO -and ($args -contains 'compile') -and (Test-Path -LiteralPath $pom) -and ([System.IO.File]::ReadAllText($pom) -match 'org\.projectlombok')) {
  if ($env:BP4_LLAMADAS) { [System.IO.File]::AppendAllText($env:BP4_LLAMADAS, (Get-Location).Path + '|' + ($args -join ' ') + "`n") }
  '[INFO] Scanning for projects...'
  '[ERROR] Failed to execute goal on project p4: Could not resolve dependencies: org.projectlombok:lombok (de mentira)'
  '[INFO] BUILD FAILURE'
  exit 1
}
& (Join-Path $PSScriptRoot 'bp4-mvn.ps1') @args
exit $LASTEXITCODE
