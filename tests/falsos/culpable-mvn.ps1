# culpable-mvn.ps1 - Maven de mentira para probar que -Deshacer de prueba-local.ps1 no da por buenos los cambios ajenos.
# Pasa todo a mvn-local.ps1. Con RESCATE_TOCA='<carpeta>|<modo>', en la primera llamada de 'test' toca <carpeta> (el worktree de
# rescate) una sola vez, como lo haria alguien ajeno al script a mitad de la prueba. La marca de que ya lo ha hecho es
# RESCATE_LLAMADAS\toco.txt. Modos:
#   commit               hace un commit vacio ('cambio ajeno')
#   fichero              escribe un fichero nuevo sin commit (ajeno.txt)
#   fichero-tras-revert  igual, pero solo cuando el ultimo commit de <carpeta> es un revert (es decir, ya despues de deshacer)
#   reset                quita el ultimo commit de <carpeta> (git reset --hard HEAD~1)
# Ademas: si la carpeta donde se lanza Maven lleva un fichero cuelga.txt (lo mete un commit), cada 'test' se cuelga como el de
# mvn-dormido.ps1 (RESCATE_MVN_PIDS: donde apunta sus PID; RESCATE_MVN_SEGUNDOS: lo que duerme), para probar el tope de Maven en
# un commit concreto de la busqueda.
if ($env:RESCATE_TOCA -and ($args -contains 'test')) {
  $carpeta, $modo = "$env:RESCATE_TOCA" -split '\|', 2
  $marca = Join-Path $env:RESCATE_LLAMADAS 'toco.txt'
  $asunto = (@(& git -C $carpeta log -1 --format=%s 2>&1 | ForEach-Object { "$_" }) -join '')
  $toca = ($modo -ne 'fichero-tras-revert') -or ($asunto -like 'Revert *')
  if ($toca -and -not (Test-Path -LiteralPath $marca)) {
    [void](New-Item -ItemType Directory -Path $env:RESCATE_LLAMADAS -Force)
    [System.IO.File]::WriteAllText($marca, "$modo`n")
    if ($modo -eq 'commit') { $null = & git -C $carpeta commit -q --allow-empty -m 'cambio ajeno' 2>&1 }
    elseif ($modo -eq 'reset') { $null = & git -C $carpeta reset -q --hard HEAD~1 2>&1 }
    else { [System.IO.File]::WriteAllText((Join-Path $carpeta 'ajeno.txt'), "ajeno`n") }
  }
}
if ($args -contains 'test' -and (Test-Path -LiteralPath (Join-Path (Get-Location).Path 'cuelga.txt'))) {
  $env:RESCATE_MVN_CUELGA = '.'   # casa con cualquier llamada
  & (Join-Path $PSScriptRoot 'mvn-dormido.ps1') @args
  exit $LASTEXITCODE
}
& (Join-Path $PSScriptRoot 'mvn-local.ps1') @args
exit $LASTEXITCODE
