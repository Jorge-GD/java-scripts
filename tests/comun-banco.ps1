<#
comun-banco.ps1 - Lo que comparten los dos bancos de pruebas (probar.ps1 y
probar-migracion.ps1). Se carga con '. (Join-Path $aqui 'comun-banco.ps1')' despues
del bloque param. Usa $Dir, $Solo y $Conservar del banco que lo carga.
Solo ASCII a proposito.
#>
$ErrorActionPreference = 'Stop'
# El mismo PowerShell que ejecuta estas pruebas. Si pwsh esta instalado como
# herramienta de dotnet, el proceso se llama 'dotnet': entonces se busca en el PATH.
$ps = (Get-Process -Id $PID).Path
if ([System.IO.Path]::GetFileNameWithoutExtension($ps) -notmatch '^(pwsh|powershell)') {
  $cmd = Get-Command pwsh -ErrorAction SilentlyContinue
  if (-not $cmd) { $cmd = Get-Command powershell -ErrorAction SilentlyContinue }
  if (-not $cmd) { throw 'No encuentro pwsh ni powershell en el PATH.' }
  $ps = $cmd.Source
}
if (-not $Dir) { $Dir = Join-Path ([System.IO.Path]::GetTempPath()) ('rescate-pruebas-' + [System.Guid]::NewGuid().ToString('N').Substring(0, 8)) }
[void](New-Item -ItemType Directory -Path $Dir -Force)
$Dir = (Resolve-Path -LiteralPath $Dir).Path
$script:Pasan = 0
$script:Fallan = 0

# ============================== UTILIDADES ==============================
function Get-Ruta([string]$Raiz, [string]$Rel) {
  $p = $Raiz
  foreach ($s in $Rel.Split('/')) { if ($s) { $p = Join-Path $p $s } }
  return $p
}

function Escribe([string]$Raiz, [string]$Rel, [string]$Texto) {
  $ruta = Get-Ruta $Raiz $Rel
  $d = Split-Path $ruta -Parent
  if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -Force) }
  [System.IO.File]::WriteAllText($ruta, $Texto)
}

function Lee([string]$Raiz, [string]$Rel) { return [System.IO.File]::ReadAllText((Get-Ruta $Raiz $Rel)) }

function GitEn([string]$D, [string[]]$A) {
  $ErrorActionPreference = 'Continue'
  $o = & git -C $D @A 2>&1 | ForEach-Object { "$_" }
  if ($LASTEXITCODE -ne 0) { throw ('git ' + ($A -join ' ') + ' ha fallado en ' + $D + ': ' + (@($o) -join ' ')) }
  return (@($o) -join "`n")
}

# Deja $D como un repo git en la rama main con todo lo que hay en un commit 'inicial'.
function Inicia-Repo([string]$D) {
  [void](GitEn $D @('init', '-q'))
  [void](GitEn $D @('symbolic-ref', 'HEAD', 'refs/heads/main'))
  [void](GitEn $D @('config', 'user.name', 'Pruebas'))
  [void](GitEn $D @('config', 'user.email', 'pruebas@example.invalid'))
  [void](GitEn $D @('config', 'commit.gpgsign', 'false'))
  [void](GitEn $D @('config', 'core.autocrlf', 'false'))
  [void](GitEn $D @('add', '-A'))
  [void](GitEn $D @('commit', '-q', '-m', 'inicial'))
}

# Lanza un script en otro proceso. Devuelve su codigo de salida y lo que escribe.
# $Entrada son las lineas que recibe por la entrada estandar (las respuestas a un
# Read-Host); la linea vacia evita que un Read-Host inesperado lo deje colgado.
function Lanzar([string]$Ruta, [string[]]$A, [string]$Guion = '', [string[]]$Entrada = @('')) {
  $ErrorActionPreference = 'Continue'
  $env:RESCATE_FALSO = $Guion
  $pre = @('-NoProfile')
  $o = $Entrada | & $ps @pre -File $Ruta @A 2>&1 | ForEach-Object { "$_" }
  $c = $LASTEXITCODE
  $env:RESCATE_FALSO = ''
  return [pscustomobject]@{ Codigo = $c; Salida = (@($o) -join "`n") }
}

function Comprueba([string]$Que, [bool]$Ok, [string]$Detalle = '') {
  if ($Ok) {
    $script:Pasan++
    Write-Host "  ok    $Que" -ForegroundColor Green
  }
  else {
    $script:Fallan++
    Write-Host "  FALLA $Que" -ForegroundColor Red
    if ($Detalle) { Write-Host "        $Detalle" }
  }
}

function Igual([string]$Que, $Esperado, $Real) {
  Comprueba $Que ("$Esperado" -ceq "$Real") "esperaba '$Esperado' y hay '$Real'"
}

function Cola([string]$Texto) { return ((@($Texto -split "`n") | Select-Object -Last 12) -join ' / ') }

# Esta el proceso $Num? Un zombi (estado Z en /proc/<pid>/stat) ya no corre: solo espera a su padre, y cuenta como muerto.
function Proceso-Vivo([int]$Num) {
  if (-not (Get-Process -Id $Num -ErrorAction SilentlyContinue)) { return $false }
  if (-not (Test-Path -LiteralPath "/proc/$Num/stat")) { return $true }
  try { return (([System.IO.File]::ReadAllText("/proc/$Num/stat") -replace '^.*\) ', '')[0] -ne 'Z') }
  catch { return $false }
}

# Lo que se comprueba en todo tope hecho con mvn-dormido.ps1: sus PID (el del falso y el de su hijo, en $CarpetaPids\pids.txt) ya
# no viven (10 s de plazo), la llamada ha tardado menos de $Limite s (el falso duerme 40) y el registro lleva lo que escribio.
function Comprueba-Tope([string]$CarpetaPids, [double]$Segundos, [int]$Limite, [string]$Registro) {
  $nums = @()
  $f = Join-Path $CarpetaPids 'pids.txt'
  if (Test-Path -LiteralPath $f) { $nums = @([System.IO.File]::ReadAllLines($f) | Where-Object { $_ } | ForEach-Object { [int]$_ }) }
  $plazo = (Get-Date).AddSeconds(10)
  do {
    $vivos = @($nums | Where-Object { Proceso-Vivo $_ })
    if ($vivos.Count -eq 0) { break }
    Start-Sleep -Milliseconds 200
  } while ((Get-Date) -lt $plazo)
  Comprueba 'el falso se colgo (anoto su PID y el de su hijo) y ninguno de los dos vive' ($nums.Count -ge 2 -and $vivos.Count -eq 0) ("PID: $($nums -join ' '), vivos: $($vivos -join ' ')")
  Comprueba "la llamada no espero al falso: menos de $Limite s" ($Segundos -lt $Limite) "$Segundos s"
  $texto = ''
  if (Test-Path -LiteralPath $Registro) { $texto = [System.IO.File]::ReadAllText($Registro) }
  Comprueba 'el registro lleva lo que Maven habia escrito' ($texto -match [regex]::Escape('[INFO] Running com.ejemplo.CuelgaTest')) "$Registro : $texto"
}

# ================================ LANZADOR ================================
# Corre las pruebas de $Pruebas (nombre -> bloque), cuenta y sale con 0 o con 1.
function Invoke-Banco($Pruebas, [string]$Titulo) {
  Write-Host ('Script: ' + $Titulo)
  Write-Host ('Carpeta de pruebas: ' + $Dir)
  # BANCO_PARTE=i/n corre solo una de n partes (las pruebas i, i+n, i+2n...), para lanzar las partes a la vez.
  # (nombres raros a proposito: los bloques de las pruebas ven las variables de esta funcion)
  $bancoParte = 0; $bancoPartes = 1
  if ("$env:BANCO_PARTE" -match '^(\d+)/(\d+)$' -and [int]$Matches[2] -gt 1 -and [int]$Matches[1] -ge 1 -and [int]$Matches[1] -le [int]$Matches[2]) {
    $bancoParte = [int]$Matches[1] - 1; $bancoPartes = [int]$Matches[2]
    Write-Host ('Parte ' + $env:BANCO_PARTE)
  }
  $bancoIndice = -1
  foreach ($nombre in $Pruebas.Keys) {
    if ($Solo -and $nombre -notlike ('*' + $Solo + '*')) { continue }
    $bancoIndice++
    if (($bancoIndice % $bancoPartes) -ne $bancoParte) { continue }
    Write-Host ''
    Write-Host $nombre
    try { & $Pruebas[$nombre] }
    catch { Comprueba 'la prueba termina sin excepcion' $false ($_.Exception.Message) }
  }
  Write-Host ''
  if ($script:Fallan -eq 0) { Write-Host "TODO BIEN: $($script:Pasan) comprobaciones." -ForegroundColor Green }
  else { Write-Host "FALLAN $($script:Fallan) de $($script:Pasan + $script:Fallan) comprobaciones." -ForegroundColor Red }
  if (-not $Conservar) {
    try { Remove-Item -LiteralPath $Dir -Recurse -Force } catch { Write-Host ('No pude borrar ' + $Dir + ': ' + $_.Exception.Message) }
  }
  if ($script:Fallan -gt 0) { exit 1 }
  exit 0
}
