# c6b-copilot.ps1 - Copilot CLI de mentira del banco tests/probar-arreglo-propiedades.ps1 (C6b, propiedades al yml). Lee el prompt de
# .rescate/tareas/<id>.prompt.md y hace lo que dice el plan de esa llamada. Nunca llama a nada real. Variables:
#   C6B_PLANES    carpeta con un plan por llamada: <n>.json (la primera llamada es la 1). Sin plan para la n, vale el de la ultima que haya. Un plan:
#                 { "ficheros": { "<ruta>": "<texto entero>" }, "borra": [ "<ruta>" ], "salida": <objeto: se escribe como JSON>,
#                   "salidaTexto": "<texto crudo; SIN-SALIDA no escribe nada>", "texto": "<lo que dice al final>", "commit": true, "sale": <codigo> }
#                 Todo es opcional: sin "salida" ni "salidaTexto" no escribe el fichero de salida. Sin carpeta o sin plan, no hace nada.
#   C6B_LLAMADAS  fichero: cada llamada anade '<n>|<reintento: 0 o 1>|<flags --model, --effort y --add-dir>|<carpeta de trabajo>'
#   C6B_PROMPTS   carpeta: copia el prompt de cada llamada en <n>.md
$texto = ''
for ($i = 0; $i -lt $args.Count; $i++) { if ("$($args[$i])" -eq '-p') { $texto = "$($args[$i + 1])" } }
$raiz = (Get-Location).Path
$id = ''
$prompt = ''
if ($texto -match 'tareas/([\w\-\.]+)\.prompt\.md') {
  $id = $Matches[1]
  $prompt = [System.IO.File]::ReadAllText([System.IO.Path]::Combine($raiz, '.rescate', 'tareas', ($id + '.prompt.md')))
}
$reintento = 0
if ($prompt -match 'CORRECCI') { $reintento = 1 }
$n = 1
if ($env:C6B_LLAMADAS -and (Test-Path -LiteralPath $env:C6B_LLAMADAS)) { $n = @([System.IO.File]::ReadAllLines($env:C6B_LLAMADAS) | Where-Object { $_ }).Count + 1 }
$flags = (@($args | Where-Object { "$_" -match '^--(model=|effort=|add-dir=)' }) -join ' ')
if ($env:C6B_LLAMADAS) { [System.IO.File]::AppendAllText($env:C6B_LLAMADAS, "$n|$reintento|$flags|$raiz`n") }
if ($env:C6B_PROMPTS) { [System.IO.File]::WriteAllText([System.IO.Path]::Combine($env:C6B_PROMPTS, "$n.md"), $prompt) }
$plan = $null
if ($env:C6B_PLANES) {
  for ($k = $n; $k -ge 1 -and $null -eq $plan; $k--) {
    $f = [System.IO.Path]::Combine($env:C6B_PLANES, "$k.json")
    if (Test-Path -LiteralPath $f) { $plan = [System.IO.File]::ReadAllText($f) | ConvertFrom-Json }
  }
}
function Ruta-Rel([string]$Rel) { return [System.IO.Path]::Combine([string[]](@($raiz) + $Rel.Split('/'))) }
$dice = 'hecho'
$sale = 0
if ($plan) {
  foreach ($p in @($plan.ficheros.PSObject.Properties)) {
    $r = Ruta-Rel $p.Name
    $d = Split-Path $r -Parent
    if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -Force) }
    [System.IO.File]::WriteAllText($r, [string]$p.Value)
  }
  foreach ($b in @($plan.borra)) { if ($b) { Remove-Item -LiteralPath (Ruta-Rel $b) -Force } }
  $dirSalida = [System.IO.Path]::Combine($raiz, '.rescate', 'tareas')
  if (-not (Test-Path -LiteralPath $dirSalida)) { [void](New-Item -ItemType Directory -Path $dirSalida -Force) }
  $fSalida = [System.IO.Path]::Combine($dirSalida, ($id + '.json'))
  if ($null -ne $plan.salida) { [System.IO.File]::WriteAllText($fSalida, (ConvertTo-Json -InputObject $plan.salida -Depth 8)) }
  elseif ($null -ne $plan.salidaTexto -and "$($plan.salidaTexto)".Trim() -cne 'SIN-SALIDA') { [System.IO.File]::WriteAllText($fSalida, [string]$plan.salidaTexto) }
  if ($plan.commit) { & git -C $raiz -c user.name=IA -c user.email=ia@example.invalid commit -q -a -m 'la IA commitea' }
  if ($null -ne $plan.texto) { $dice = [string]$plan.texto }
  if ($null -ne $plan.sale) { $sale = [int]$plan.sale }
}
if ($sale -ne 0) { [Console]::Error.WriteLine('Error de mentira: ' + $dice); exit $sale }
$dice
exit 0
