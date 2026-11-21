# w2-copilot.ps1 - Copilot CLI de mentira de los tests w2 de tests/probar-migracion.ps1 (la revision por flujos y el yml de propiedades como fases de la pasada).
# Lee .rescate/tareas/<id>.prompt.md, saca su linea 'TIPO: <tipo>' y, segun el tipo:
#   revision-flujo   escribe .rescate/tareas/<id>.json con W2_RESPUESTAS\<id>.json (sin fichero, {"hallazgos": []}) y apunta '<id>|<reintento: 0 o 1>' en
#                    la carpeta W2_LLAMADAS (un fichero por llamada: van varias a la vez). Con W2_TOCA (una ruta del repo) anade ademas una linea a ese fichero: una lectura que cambia el repositorio.
#   propiedades      lo que hace c6b-copilot.ps1 (los planes de C6B_PLANES)
#   los demas        lo que hace copilot.ps1
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
if ($tipo -ceq 'propiedades') {
  & (Join-Path $PSScriptRoot 'c6b-copilot.ps1') @args
  exit $LASTEXITCODE
}
if ($tipo -cne 'revision-flujo') {
  & (Join-Path $PSScriptRoot 'copilot.ps1') @args
  exit $LASTEXITCODE
}
$reintento = 0
if ($prompt -match 'CORRECCI') { $reintento = 1 }
if ($env:W2_LLAMADAS) {
  [void](New-Item -ItemType Directory -Path $env:W2_LLAMADAS -Force)
  [System.IO.File]::AppendAllText([System.IO.Path]::Combine($env:W2_LLAMADAS, "$id-$PID.txt"), "$id|$reintento`n")
}
if ($env:W2_TOCA) { [System.IO.File]::AppendAllText([System.IO.Path]::Combine([string[]](@($raiz) + $env:W2_TOCA.Split('/'))), "// W2_TOCA`n") }
$salida = '{"hallazgos": []}'
if ($env:W2_RESPUESTAS) {
  $f = [System.IO.Path]::Combine($env:W2_RESPUESTAS, ($id + '.json'))
  if (Test-Path -LiteralPath $f) { $salida = [System.IO.File]::ReadAllText($f) }
}
$dir = [System.IO.Path]::Combine($raiz, '.rescate', 'tareas')
if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
[System.IO.File]::WriteAllText([System.IO.Path]::Combine($dir, ($id + '.json')), $salida)
'hecho'
exit 0
