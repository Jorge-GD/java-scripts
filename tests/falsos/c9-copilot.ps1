# c9-copilot.ps1 - Copilot CLI de mentira del banco tests/probar-configmap.ps1 (C9, el repo de configmap del batch migrado). Lee el prompt de
# .rescate/tareas/<id>.prompt.md de su carpeta de trabajo, lo apunta y hace lo que diga el plan de esa tarea. Variables:
#   C9_PLANES     carpeta con un plan por tarea: <id>.json (la primera llamada) y <id>.reintento.json (la llamada cuyo prompt lleva la seccion de
#                 correccion; si no esta, vale el mismo). Sin plan no escribe nada, salvo en las tareas configmap-revision-*: {"hallazgos": []}.
#                 Un plan es un objeto JSON con cualquiera de estos campos:
#                   ficheros  objeto ruta relativa -> texto: los escribe (crea las carpetas)
#                   borra     lista de rutas relativas que borra
#                   salida    texto que escribe en .rescate/tareas/<id>.json
#                   falla     true: sale con 1 sin escribir nada
#                   copiaPrompt  ruta relativa: escribe en ella el prompt que ha recibido (una IA que copia todo lo que ve)
#   C9_LLAMADAS   fichero: cada llamada anade 'id|reintento (0 o 1)|flags|carpeta de trabajo'
#   C9_PROMPTS    carpeta: guarda el prompt de cada llamada como <id>-<n>.md
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
if ($prompt -cmatch 'CORRECCI') { $reintento = 1 }
$flags = (@($args | Where-Object { "$_" -match '^--(model=|effort=|add-dir=|deny-tool=)' }) -join ' ')
if ($env:C9_LLAMADAS) {
  # varias llamadas a la vez: sin un cerrojo, dos AppendAllText a la vez se pisan y se pierde una linea
  $sha = [System.Security.Cryptography.SHA1]::Create()
  $mx = New-Object System.Threading.Mutex($false, ('c9-llamadas-' + ((@($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($env:C9_LLAMADAS))) | ForEach-Object { $_.ToString('x2') }) -join '')))
  [void]$mx.WaitOne()
  try { [System.IO.File]::AppendAllText($env:C9_LLAMADAS, "$id|$reintento|$flags|$raiz`n") } finally { $mx.ReleaseMutex() }
}
if ($env:C9_PROMPTS) {
  $n = 1
  while (Test-Path -LiteralPath ([System.IO.Path]::Combine($env:C9_PROMPTS, "$id-$n.md"))) { $n++ }
  [System.IO.File]::WriteAllText([System.IO.Path]::Combine($env:C9_PROMPTS, "$id-$n.md"), $prompt)
}
$plan = $null
if ($env:C9_PLANES) {
  $f = [System.IO.Path]::Combine($env:C9_PLANES, ($id + '.json'))
  $r = [System.IO.Path]::Combine($env:C9_PLANES, ($id + '.reintento.json'))
  if ($reintento -eq 1 -and (Test-Path -LiteralPath $r)) { $f = $r }
  if (Test-Path -LiteralPath $f) { $plan = [System.IO.File]::ReadAllText($f) | ConvertFrom-Json }
}
if ($null -eq $plan) {
  if ($id -like 'configmap-revision-*') { $plan = [pscustomobject]@{ salida = '{"hallazgos": []}' } }
  else { 'hecho'; exit 0 }
}
if ($plan.falla) { [Console]::Error.WriteLine('Error de mentira: sin sesion'); exit 1 }
foreach ($b in @($plan.borra)) {
  if ($b) { Remove-Item -LiteralPath ([System.IO.Path]::Combine($raiz, ($b -replace '/', [System.IO.Path]::DirectorySeparatorChar))) -Force -ErrorAction SilentlyContinue }
}
if ($plan.ficheros) {
  foreach ($p in $plan.ficheros.PSObject.Properties) {
    $ruta = [System.IO.Path]::Combine($raiz, ($p.Name -replace '/', [System.IO.Path]::DirectorySeparatorChar))
    $d = [System.IO.Path]::GetDirectoryName($ruta)
    if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -Force) }
    [System.IO.File]::WriteAllText($ruta, [string]$p.Value)
  }
}
if ($plan.copiaPrompt) {
  $ruta = [System.IO.Path]::Combine($raiz, ($plan.copiaPrompt -replace '/', [System.IO.Path]::DirectorySeparatorChar))
  $d = [System.IO.Path]::GetDirectoryName($ruta)
  if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -Force) }
  [System.IO.File]::WriteAllText($ruta, $prompt)
}
if ($null -ne $plan.salida) {
  $dir = [System.IO.Path]::Combine($raiz, '.rescate', 'tareas')
  if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
  [System.IO.File]::WriteAllText([System.IO.Path]::Combine($dir, ($id + '.json')), [string]$plan.salida)
}
'hecho'
exit 0
