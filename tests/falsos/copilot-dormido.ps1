# copilot-dormido.ps1 - Copilot de mentira que se cuelga, para probar el tope de Copilot (MinutosCopilot).
# Reparte el trabajo con otro falso: si la llamada no se cuelga, hace '& <RESCATE_COP_FALSO o copilot.ps1> @args' y sale
# con su codigo (copilot.ps1 por defecto; copilot-m6.ps1 para los guiones del M6).
# La clave de una llamada es la primera linea de .rescate/prompt.md (la de un lote es 'rescate de migracion: paso ...' y la de la
# revision previa, '... revision previa del paso ...'). Variables:
#   RESCATE_COP_CUELGA    regex: solo las llamadas cuya clave casa con ella cuentan y pueden colgarse.
#   RESCATE_COP_PIDS      carpeta (obligatoria con RESCATE_COP_CUELGA): cuenta.txt lleva una linea (la clave) por llamada que casa y
#                         pids.txt, un PID por linea (el de este proceso y el de su hijo dormido).
#   RESCATE_COP_ANTES     si no esta vacia, la llamada que se cuelga hace antes lo del otro falso (arregla) y despues se cuelga.
#   RESCATE_COP_SEGUNDOS  lo que duerme (40 si no esta).
#   RESCATE_COP_FALSO     el otro falso (copilot.ps1 si no esta).
# Una llamada que se cuelga lanza un hijo que hereda las tuberias, apunta los dos PID y duerme: si el tope no la para con sus
# hijos, la prueba lo ve.
$prompt = Join-Path (Join-Path (Get-Location).Path '.rescate') 'prompt.md'
$clave = ''
if (Test-Path -LiteralPath $prompt) { $clave = @([System.IO.File]::ReadAllLines($prompt))[0] }
$cuelga = [bool]($env:RESCATE_COP_CUELGA -and ($clave -match $env:RESCATE_COP_CUELGA))
$otro = 'copilot.ps1'
if ($env:RESCATE_COP_FALSO) { $otro = $env:RESCATE_COP_FALSO }
if (-not $cuelga -or $env:RESCATE_COP_ANTES) {
  & (Join-Path $PSScriptRoot $otro) @args
  $codigo = $LASTEXITCODE
  if (-not $cuelga) { exit $codigo }
}
[void](New-Item -ItemType Directory -Path $env:RESCATE_COP_PIDS -Force)
[System.IO.File]::AppendAllText((Join-Path $env:RESCATE_COP_PIDS 'cuenta.txt'), $clave + "`n")
$seg = 40
if ($env:RESCATE_COP_SEGUNDOS) { $seg = [int]$env:RESCATE_COP_SEGUNDOS }
'Copilot (de mentira) se ha quedado pensando'
# El mismo PowerShell que corre este falso; si pwsh esta instalado como herramienta de dotnet, el proceso se llama 'dotnet'
# y se busca en el PATH (como tests/comun-banco.ps1).
$ps = (Get-Process -Id $PID).Path
if ([System.IO.Path]::GetFileNameWithoutExtension($ps) -notmatch '^(pwsh|powershell)') { $ps = (@(Get-Command pwsh, powershell -ErrorAction SilentlyContinue)[0]).Source }
$hijo = Start-Process -FilePath $ps -ArgumentList @('-NoProfile', '-Command', "Start-Sleep -Seconds $seg") -NoNewWindow -PassThru
[System.IO.File]::AppendAllText((Join-Path $env:RESCATE_COP_PIDS 'pids.txt'), "$PID`n$($hijo.Id)`n")
Start-Sleep -Seconds $seg
exit 0
