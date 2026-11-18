# analisis-mvn.ps1 - Maven de mentira para probar analisis.ps1 (tests/probar-analisis.ps1) y el paso de SpotBugs y PMD del
# preflight (tests/probar-preflight.ps1). Para todo lo que no es SpotBugs ni PMD hace '& mvn.ps1 @args' y sale con su codigo
# (asi 'compila' o no, y '--version' contesta). Si las llamadas son de SpotBugs o de PMD:
#   - deja los XML reales de tests/datos/analisis: spotbugsXml.xml y pmd.xml en <carpeta actual>/target (con '/repo' cambiado por
#     la carpeta donde se lanza Maven, que es la del repo analizado);
#   - con RESCATE_ANALISIS_ERROR=<texto> falla con '[ERROR] <texto>' y codigo 1 (un plugin que no se descarga);
#   - con RESCATE_ANALISIS_ESPERA=<n> tarda n segundos antes de hacer nada (para probar el tope);
#   - con RESCATE_ANALISIS_SIN_XML=1 sale con 0 sin dejar ningun XML.
# Con RESCATE_ANALISIS_LLAMADAS=<fichero>, cada llamada anade una linea '<carpeta>|<argumentos>' (para ver el filtro).
if ($args -contains '--version') { 'Apache Maven 3.9.8 (de mentira)'; exit 0 }
$raiz = (Get-Location).Path
# PowerShell parte '-Dx=a:b' en dos argumentos al lanzar un .ps1 ($args): los de verdad se leen del proceso, tal como llegaron.
$crudos = @([Environment]::GetCommandLineArgs())
$desde = -1
for ($i = 0; $i -lt $crudos.Count; $i++) { if ([System.IO.Path]::GetFileName($crudos[$i]) -ceq 'analisis-mvn.ps1') { $desde = $i; break } }
$argv = @($args)
if ($desde -ge 0) { $argv = @($crudos | Select-Object -Skip ($desde + 1)) }
if ($env:RESCATE_ANALISIS_LLAMADAS) { [System.IO.File]::AppendAllText($env:RESCATE_ANALISIS_LLAMADAS, $raiz + '|' + ($argv -join ' ') + "`n") }
& (Join-Path $PSScriptRoot 'mvn.ps1') @args
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$linea = $argv -join ' '
$conSpotbugs = ($linea -match 'spotbugs-maven-plugin')
$conPmd = ($linea -match 'maven-pmd-plugin')
if (-not ($conSpotbugs -or $conPmd)) { exit 0 }
if ($env:RESCATE_ANALISIS_ESPERA) { Start-Sleep -Seconds ([int]$env:RESCATE_ANALISIS_ESPERA) }
if ($env:RESCATE_ANALISIS_ERROR) { '[ERROR] ' + $env:RESCATE_ANALISIS_ERROR; exit 1 }
if ($env:RESCATE_ANALISIS_SIN_XML) { exit 0 }
$datos = Join-Path (Split-Path $PSScriptRoot -Parent) 'datos/analisis'
function Copia-Xml([string]$Nombre, [string]$Destino) {
  $t = [System.IO.File]::ReadAllText((Join-Path $datos $Nombre)).Replace('/repo', ($raiz -replace '\\', '/'))
  [void](New-Item -ItemType Directory -Path (Split-Path $Destino -Parent) -Force)
  [System.IO.File]::WriteAllText($Destino, $t)
}
if ($conSpotbugs) { Copia-Xml 'spotbugsXml.xml' (Join-Path (Join-Path $raiz 'target') 'spotbugsXml.xml') }
if ($conPmd) { Copia-Xml 'pmd.xml' (Join-Path (Join-Path $raiz 'target') 'pmd.xml') }
exit 0
