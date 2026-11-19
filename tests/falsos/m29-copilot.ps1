# m29-copilot.ps1 - Copilot de mentira para los tests m29 de tests/probar-local.ps1 (el test del migrado se escribe traduciendo el del
# original). Hace lo de m25-copilot.ps1 (y con el, lo de copilot-local.ps1) y, en una tarea de arnes (TIPO: arnes-local), ademas:
#   - apunta en su fichero de RESCATE_LLAMADAS (<id>-<pid>.txt) lo que ve del prompt y del orden:
#       traduce=si|no            el prompt lleva la seccion del test del original (la palabra 'traducelo')
#       original=<ruta>          la ruta del test del original que dice esa seccion
#       original-existe=si|no    si ese fichero existe en el momento de la llamada (el del original ya esta guardado)
#   - deja en el test que escribe la marca '// MARCA_ARNES=<repo>-<n>' (n: la llamada de arnes de ese repo, esta incluida): un arnes
#     que se rehace no queda con el mismo texto que el de antes, y m29-mvn.ps1 dice con que marca se ejecuto cada caso.
$texto = ''
for ($i = 0; $i -lt $args.Count; $i++) { if ("$($args[$i])" -eq '-p') { $texto = "$($args[$i + 1])" } }
$raiz = (Get-Location).Path
$id = ''
if ($texto -match 'tareas/([\w\-]+)\.prompt\.md') { $id = $Matches[1] }
$prompt = ''
if ($id) { $prompt = [System.IO.File]::ReadAllText((Join-Path (Join-Path (Join-Path $raiz '.rescate') 'tareas') ($id + '.prompt.md'))) }
$esArnes = ($prompt -match '(?m)^TIPO: arnes-local\s*$')
$apunte = @()
if ($esArnes) {
  $traduce = 'no'
  $ruta = ''
  $existe = 'no'
  if ($prompt -match 'trad.celo') { $traduce = 'si' }
  $m = [regex]::Match($prompt, 'El test del original ya est. escrito y vale: `([^`]+)`')
  if ($m.Success) { $ruta = $m.Groups[1].Value; if (Test-Path -LiteralPath $ruta) { $existe = 'si' } }
  $apunte = @("traduce=$traduce", "original=$ruta", "original-existe=$existe")
}
& (Join-Path $PSScriptRoot 'm25-copilot.ps1') @args
$codigo = $LASTEXITCODE
if ($esArnes -and $env:RESCATE_LLAMADAS) {
  $repo = $id -replace '^arnes-', ''
  $n = @(Get-ChildItem -LiteralPath $env:RESCATE_LLAMADAS -File -Filter "arnes-$repo-*.txt").Count
  foreach ($f in @(Get-ChildItem -LiteralPath $raiz -Recurse -File -Filter 'PruebaLocalTest.java')) { [System.IO.File]::AppendAllText($f.FullName, "// MARCA_ARNES=$repo-$n`n") }
  [System.IO.File]::AppendAllLines((Join-Path $env:RESCATE_LLAMADAS ($id + '-' + $PID + '.txt')), [string[]]$apunte)
}
exit $codigo
