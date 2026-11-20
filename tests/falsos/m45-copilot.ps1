# m45-copilot.ps1 - Copilot CLI de mentira de los tests m45 (marca de intento en las rondas). Antes de pasar la llamada al Copilot de mentira
# que dice M45_DELEGA, apunta lo que ve en la carpeta de trabajo: el HEAD y la marca .rescate/intento-en-curso.json (o '-' si no esta).
# Variables:
#   M45_DELEGA   el Copilot de mentira que hace el trabajo (bp4-copilot.ps1, m35-copilot.ps1, copilot.ps1...)
#   M45_MARCAS   fichero: cada llamada anade 'copilot|<carpeta de trabajo>|<HEAD>|<marca en una linea o ->'
$raiz = (Get-Location).Path
if ($env:M45_MARCAS) {
  $marca = '-'
  $ruta = [System.IO.Path]::Combine($raiz, '.rescate', 'intento-en-curso.json')
  if (Test-Path -LiteralPath $ruta) { $marca = ([System.IO.File]::ReadAllText($ruta) -replace '\s*[\r\n]+\s*', ' ') }
  $head = (@(& git -C $raiz rev-parse HEAD 2>$null) -join '').Trim()
  [System.IO.File]::AppendAllText($env:M45_MARCAS, "copilot|$raiz|$head|$marca`n")
}
& $env:M45_DELEGA @args
exit $LASTEXITCODE
