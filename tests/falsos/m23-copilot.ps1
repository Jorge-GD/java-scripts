# m23-copilot.ps1 - Copilot CLI de mentira de las pruebas 'm23' (tests/probar.ps1). copilot.ps1 no arregla calidad ni build: este si.
#   paso calidad  pone '/** Documentado. */' encima de cada linea que el prompt marca (- fichero:linea - [regla] ...). Con RESCATE_M23_ROMPE=<Clase>,
#                 a esa clase le cambia ademas el codigo (' + 0;'), que es lo que hace fallar su test de contexto en m22-mvn.ps1 (M22_FALLA_CON).
#   paso build    quita NO_COMPILA de los .java de src.
# Con cualquier otra llamada hace lo de m22-copilot.ps1 (que hace lo de copilot.ps1).
$raiz = (Get-Location).Path
$ruta = Join-Path (Join-Path $raiz '.rescate') 'prompt.md'
$paso = ''
if ($args -contains '-p' -and (Test-Path -LiteralPath $ruta)) {
  $m = [regex]::Match(([System.IO.File]::ReadAllLines($ruta) | Select-Object -First 1), "paso '(\w+)'")
  if ($m.Success) { $paso = $m.Groups[1].Value }
}
if ($paso -ne 'calidad' -and $paso -ne 'build') {
  & (Join-Path $PSScriptRoot 'm22-copilot.ps1') @args
  exit $LASTEXITCODE
}

function Ruta-M23([string]$Rel) { return [System.IO.Path]::Combine([string[]](@($raiz) + $Rel.Split('/'))) }

if ($paso -eq 'build') {
  foreach ($f in @(Get-ChildItem -LiteralPath (Ruta-M23 'src') -Recurse -File -Filter '*.java')) {
    $t = [System.IO.File]::ReadAllText($f.FullName)
    if ($t.Contains('NO_COMPILA')) { [System.IO.File]::WriteAllText($f.FullName, $t.Replace('NO_COMPILA', 'compila')) }
  }
  'hecho'
  exit 0
}

# calidad: las lineas marcadas de cada fichero, de la ultima a la primera para que sus numeros no se muevan
$marcas = @{}
$dentro = $false
foreach ($l in ([System.IO.File]::ReadAllLines($ruta))) {
  if ($l -match '^## Hallazgos') { $dentro = $true; continue }
  if ($dentro -and $l -match '^## ') { break }
  if ($dentro -and $l -match '^- (\S+?):(\d+) - ') {
    if (-not $marcas.ContainsKey($Matches[1])) { $marcas[$Matches[1]] = @() }
    $marcas[$Matches[1]] += [int]$Matches[2]
  }
}
foreach ($f in $marcas.Keys) {
  $lineas = New-Object System.Collections.Generic.List[string]
  $lineas.AddRange([string[]]@([System.IO.File]::ReadAllLines((Ruta-M23 $f))))
  foreach ($n in @($marcas[$f] | Sort-Object -Descending)) {
    $sangria = [regex]::Match($lineas[$n - 1], '^\s*').Value
    $lineas.Insert($n - 1, $sangria + '/** Documentado. */')
  }
  $texto = ($lineas -join "`n") + "`n"
  if ($env:RESCATE_M23_ROMPE -and [System.IO.Path]::GetFileNameWithoutExtension($f) -eq $env:RESCATE_M23_ROMPE) { $texto = $texto.Replace('int resultado = a + b;', 'int resultado = a + b + 0;') }
  [System.IO.File]::WriteAllText((Ruta-M23 $f), $texto)
}
'hecho'
exit 0
