# m20d-rescate.ps1 - rescate.ps1 de mentira para el bloque 7 del preflight (tests/probar-preflight.ps1, pruebas m20d).
# Apunta lo que ve en $env:M20D_REGISTRO (una linea clave=valor por dato) y hace lo que diga $env:M20D_MODO:
#   bien      escribe el diagnostico de siempre y sale con 0
#   falla     escribe el diagnostico y sale con 3
#   cuelga    duerme 60 s: el tope del preflight lo para antes
#   bloquea   como bien, y deja en -Repo una carpeta sin permiso de escritura (el borrado de la copia falla; solo fuera de Windows)
param([string]$Repo = '', [string]$Plantilla = '', [switch]$SinWorktree)
$clase = Join-Path (Join-Path (Join-Path (Join-Path (Join-Path $Repo 'src') 'main') 'java') 'com') 'zorba'
$clase = Join-Path (Join-Path $clase 'migrado') 'ZorbaNuevaUno.java'
$editada = $false
if (Test-Path -LiteralPath $clase) { $editada = ([System.IO.File]::ReadAllText($clase) -match 'editado-sin-commit') }
$sinSeguir = Join-Path (Split-Path $clase -Parent) 'ZorbaSinSeguir.java'
$lineas = @(
  "repo=$Repo",
  "existe=$(Test-Path -LiteralPath $Repo)",
  "git=$(Test-Path -LiteralPath (Join-Path $Repo '.git'))",
  "config=$(Test-Path -LiteralPath (Join-Path (Join-Path $Repo '.rescate') 'config.json'))",
  "editada=$editada",
  "sinseguir=$(Test-Path -LiteralPath $sinSeguir)",
  "plantilla=$Plantilla",
  "sinworktree=$SinWorktree"
)
[System.IO.File]::WriteAllLines($env:M20D_REGISTRO, [string[]]$lineas)
if ($env:M20D_MODO -eq 'cuelga') { Start-Sleep -Seconds 60; exit 0 }
Write-Host 'build               0        0'
Write-Host 'Plantilla incumple: capas 0 | ficheros 0 | calidad 0 | secretos 0'
if ($env:M20D_MODO -eq 'bloquea') {
  $d = Join-Path $Repo 'zz-bloqueada'
  [void](New-Item -ItemType Directory -Path $d -Force)
  [System.IO.File]::WriteAllText((Join-Path $d 'f.txt'), 'x')
  & chmod 555 $d
}
if ($env:M20D_MODO -eq 'falla') { exit 3 }
exit 0
