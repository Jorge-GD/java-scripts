# mvn-dormido.ps1 - Maven de mentira que se cuelga, para probar el tope de Maven (MinutosMaven).
# Reparte el trabajo con otro falso: si la llamada no se cuelga, hace '& <RESCATE_MVN_FALSO o mvn.ps1> @args' y sale
# con su codigo (mvn.ps1 en tests/probar.ps1; mvn-local.ps1 en tests/probar-local.ps1).
# La clave de una llamada es '<carpeta>|<argumentos>' (la carpeta es donde se lanza Maven). Variables:
#   RESCATE_MVN_CUELGA    regex: solo las llamadas cuya clave casa con ella cuentan y pueden colgarse.
#   RESCATE_MVN_PIDS      carpeta (obligatoria con RESCATE_MVN_CUELGA): cuenta.txt lleva una linea por llamada que casa y
#                         pids.txt, un PID por linea (el de este proceso y el de su hijo dormido).
#   RESCATE_MVN_DESDE     numero de la primera llamada que se cuelga (1 si no esta); las anteriores que casan van al otro falso.
#   RESCATE_MVN_SEGUNDOS  lo que duerme (40 si no esta).
# Una llamada que se cuelga escribe '[INFO] Running com.ejemplo.CuelgaTest', lanza un hijo que hereda las tuberias (como la
# JVM de los tests de Maven), apunta los dos PID y duerme: si Maven no la para con sus hijos, la prueba lo ve.
$clave = (Get-Location).Path + '|' + ($args -join ' ')
$cuelga = $false
if ($env:RESCATE_MVN_CUELGA -and ($clave -match $env:RESCATE_MVN_CUELGA)) {
  [void](New-Item -ItemType Directory -Path $env:RESCATE_MVN_PIDS -Force)
  [System.IO.File]::AppendAllText((Join-Path $env:RESCATE_MVN_PIDS 'cuenta.txt'), $clave + "`n")
  $desde = 1
  if ($env:RESCATE_MVN_DESDE) { $desde = [int]$env:RESCATE_MVN_DESDE }
  $cuelga = (@([System.IO.File]::ReadAllLines((Join-Path $env:RESCATE_MVN_PIDS 'cuenta.txt'))).Count -ge $desde)
}
if (-not $cuelga) {
  $otro = 'mvn.ps1'
  if ($env:RESCATE_MVN_FALSO) { $otro = $env:RESCATE_MVN_FALSO }
  & (Join-Path $PSScriptRoot $otro) @args
  exit $LASTEXITCODE
}
$seg = 40
if ($env:RESCATE_MVN_SEGUNDOS) { $seg = [int]$env:RESCATE_MVN_SEGUNDOS }
'[INFO] Running com.ejemplo.CuelgaTest'
# El mismo PowerShell que corre este falso; si pwsh esta instalado como herramienta de dotnet, el proceso se llama 'dotnet'
# y se busca en el PATH (como tests/comun-banco.ps1).
$ps = (Get-Process -Id $PID).Path
if ([System.IO.Path]::GetFileNameWithoutExtension($ps) -notmatch '^(pwsh|powershell)') { $ps = (@(Get-Command pwsh, powershell -ErrorAction SilentlyContinue)[0]).Source }
$hijo = Start-Process -FilePath $ps -ArgumentList @('-NoProfile', '-Command', "Start-Sleep -Seconds $seg") -NoNewWindow -PassThru
[System.IO.File]::AppendAllText((Join-Path $env:RESCATE_MVN_PIDS 'pids.txt'), "$PID`n$($hijo.Id)`n")
Start-Sleep -Seconds $seg
exit 0
