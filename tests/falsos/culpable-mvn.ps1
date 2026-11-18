# culpable-mvn.ps1 - Maven de mentira para probar que -Deshacer de prueba-local.ps1 no da por buenos los cambios ajenos.
# Pasa todo a mvn-local.ps1. Con RESCATE_TOCA='<carpeta>|<modo>', en la primera llamada de 'test' toca <carpeta> (el worktree de
# rescate) una sola vez, como lo haria alguien ajeno al script a mitad de la prueba. La marca de que ya lo ha hecho es
# RESCATE_LLAMADAS\toco.txt. Modos:
#   commit               hace un commit vacio ('cambio ajeno')
#   fichero              escribe un fichero nuevo sin commit (ajeno.txt)
#   fichero-tras-revert  igual, pero solo cuando el ultimo commit de <carpeta> es un revert (es decir, ya despues de deshacer)
if ($env:RESCATE_TOCA -and ($args -contains 'test')) {
  $carpeta, $modo = "$env:RESCATE_TOCA" -split '\|', 2
  $marca = Join-Path $env:RESCATE_LLAMADAS 'toco.txt'
  $asunto = (@(& git -C $carpeta log -1 --format=%s 2>&1 | ForEach-Object { "$_" }) -join '')
  $toca = ($modo -ne 'fichero-tras-revert') -or ($asunto -like 'Revert *')
  if ($toca -and -not (Test-Path -LiteralPath $marca)) {
    [void](New-Item -ItemType Directory -Path $env:RESCATE_LLAMADAS -Force)
    [System.IO.File]::WriteAllText($marca, "$modo`n")
    if ($modo -eq 'commit') { $null = & git -C $carpeta commit -q --allow-empty -m 'cambio ajeno' 2>&1 }
    else { [System.IO.File]::WriteAllText((Join-Path $carpeta 'ajeno.txt'), "ajeno`n") }
  }
}
& (Join-Path $PSScriptRoot 'mvn-local.ps1') @args
exit $LASTEXITCODE
