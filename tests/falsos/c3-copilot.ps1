# c3-copilot.ps1 - Copilot CLI de mentira del banco tests/probar-revision.ps1 (C3, revision por flujos). Lee el prompt de
# .rescate/tareas/<id>.prompt.md, saca su linea 'TIPO: <tipo>' y escribe la salida de la tarea en .rescate/tareas/<id>.json. Nunca toca otro
# fichero. Variables:
#   C3_RESPUESTAS  carpeta con una respuesta por tarea: <id>.json (la primera llamada) y <id>.reintento.json (la llamada cuyo prompt lleva la
#                  seccion de correccion; si no esta, vale la misma). Sin fichero para ese id escribe {"hallazgos": []}. Un fichero que
#                  solo dice SIN-SALIDA no escribe nada (la tarea queda invalida) y uno que solo dice FALLA sale con 1 sin escribir.
#   C3_LLAMADAS    fichero: cada llamada anade 'id|tipo|reintento (0 o 1)|flags|carpeta de trabajo'
$texto = ''
for ($i = 0; $i -lt $args.Count; $i++) { if ("$($args[$i])" -eq '-p') { $texto = "$($args[$i + 1])" } }
$raiz = (Get-Location).Path
$id = ''
$prompt = ''
if ($texto -match 'tareas/([\w\-\.]+)\.prompt\.md') {
  $id = $Matches[1]
  $prompt = [System.IO.File]::ReadAllText([System.IO.Path]::Combine($raiz, '.rescate', 'tareas', ($id + '.prompt.md')))
}
$tipo = ''
if ($prompt -match '(?m)^TIPO: (\S+)') { $tipo = $Matches[1] }
$reintento = 0
if ($prompt -match 'CORRECCI') { $reintento = 1 }
$flags = (@($args | Where-Object { "$_" -match '^--(model=|effort=|add-dir=)' }) -join ' ')
if ($env:C3_LLAMADAS) { [System.IO.File]::AppendAllText($env:C3_LLAMADAS, "$id|$tipo|$reintento|$flags|$raiz`n") }
$salida = '{"hallazgos": []}'
if ($env:C3_RESPUESTAS) {
  $f = [System.IO.Path]::Combine($env:C3_RESPUESTAS, ($id + '.json'))
  $r = [System.IO.Path]::Combine($env:C3_RESPUESTAS, ($id + '.reintento.json'))
  if ($reintento -eq 1 -and (Test-Path -LiteralPath $r)) { $f = $r }
  if (Test-Path -LiteralPath $f) { $salida = [System.IO.File]::ReadAllText($f) }
}
if ($salida.Trim() -ceq 'FALLA') { [Console]::Error.WriteLine('Error de mentira: sin sesion'); exit 1 }
if ($salida.Trim() -cne 'SIN-SALIDA') {
  $dir = [System.IO.Path]::Combine($raiz, '.rescate', 'tareas')
  if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
  [System.IO.File]::WriteAllText([System.IO.Path]::Combine($dir, ($id + '.json')), $salida)
}
'hecho'
exit 0
