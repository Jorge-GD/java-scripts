# m20c-copilot-commit.ps1 - Copilot de mentira para tests/probar-migracion.ps1 (grupo m20c): una lectura que hace git commit.
# Una llamada de lectura (su -p nombra .rescate/tareas/<id>.prompt.md) hace lo de copilot.ps1 y, ademas, deja un fichero
# nuevo en src/main/resources y lo mete en un commit del repositorio donde corre, como haria un modelo con --allow-all-tools.
# Cualquier otra llamada se la pasa a copilot.ps1 sin mas.
# Con M20C_COMMIT=rama, el commit se hace en una rama nueva (git checkout -b) y el repositorio se queda en ella.
# Con M20C_COMMIT=solo-rama, solo cambia a una rama nueva: sin fichero ni commit (el HEAD no cambia, la rama si).
$texto = ''
for ($i = 0; $i -lt $args.Count - 1; $i++) { if ("$($args[$i])" -eq '-p') { $texto = "$($args[$i + 1])" } }
& (Join-Path $PSScriptRoot 'copilot.ps1') @args
$codigo = $LASTEXITCODE
if ($texto -notmatch '\.rescate/tareas/') { exit $codigo }
$raiz = (Get-Location).Path
if ($env:M20C_COMMIT -eq 'solo-rama') { [void](& git -C $raiz checkout -q -b "rama-de-la-ia-$PID" 2>&1); exit $codigo }
$nombre = "commit-de-la-ia-$PID.txt"
$dir = Join-Path (Join-Path (Join-Path $raiz 'src') 'main') 'resources'
[void](New-Item -ItemType Directory -Path $dir -Force)
[System.IO.File]::WriteAllText((Join-Path $dir $nombre), "la lectura hizo un commit`n")
if ($env:M20C_COMMIT -eq 'rama') { [void](& git -C $raiz checkout -q -b "rama-de-la-ia-$PID" 2>&1) }
# varias lecturas a la vez comparten el repositorio: si git tiene el indice cogido, se vuelve a intentar
for ($k = 0; $k -lt 10; $k++) {
  [void](& git -C $raiz add -- "src/main/resources/$nombre" 2>&1)
  [void](& git -C $raiz commit -q -m "commit de la lectura $PID" 2>&1)
  if ($LASTEXITCODE -eq 0) { break }
  Start-Sleep -Milliseconds 200
}
exit $codigo
