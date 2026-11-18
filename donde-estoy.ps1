<#
donde-estoy.ps1 - En que punto va cada batch y que comando toca ahora. Solo lee: no escribe en ningun repo ni en las carpetas
migracion-*, no llama a Copilot ni a Maven. Compatible con Windows PowerShell 5.1 y PowerShell 7. Solo ASCII a proposito.
Necesita comun.ps1, tareas.ps1, informe.ps1 y la carpeta informe\ junto a este script.

QUE HACE
  Para cada batch da un bloque corto con lo que ya dice el recuadro "Siguiente paso" de la portada (index.html), sin abrir el HTML:
    Punto      la fase en que va (o "terminado") y su fecha: el fin de la pasada o, si sigue corriendo, la del fichero estado.json.
    Siguiente  lo que toca hacer ahora y, debajo, sangrado y listo para copiar, su comando. Es el texto y el comando de la portada
               (Get-SiguientePaso y Get-SiguienteHtml de informe.ps1): este script no los reescribe, solo los pasa a texto plano.
               Si la pasada esta parada y estado.json trae su ayuda (parada.ayuda), debajo va "Para pegar en Copilot:" y el texto.
    Despues    solo si la cobertura medida (la de despues de corregir o, si no la hay, la de antes) esta por debajo de
               CoberturaMinima: dice cuando se midio (la fecha de su fichero), da el comando de rescate.ps1 -Cobertura y,
               debajo, donde mirar si ya se lanzo despues de esa fecha (<migrado>-rescate\.rescate\cobertura-faltan.md).
  Un batch sin datos\estado.json esta "sin empezar": da el comando de migracion.ps1 con -SoloInforme.
  Si junto a los scripts no esta preflight-resultado.txt, empieza diciendo que falta pasar el preflight. Acaba mandando a FLUJO.md.
  Si un batch tiene varias carpetas migracion-*, usa la del estado.json mas reciente.

  Pensado tambien para la IA: ejecutalo y repite lo que dice, sin deducir el punto leyendo los JSON.

USO
  .\donde-estoy.ps1                                        # todos los batchs que hay junto a la carpeta de los scripts, por orden alfabetico
  .\donde-estoy.ps1 -Migrado C:\ruta\batch-recibos         # solo ese batch
  .\donde-estoy.ps1 -Migrado C:\ruta\batch-nuevo -Legacy C:\ruta\original-nuevo   # un batch sin empezar: el comando ya lleva su original

  Sin -Migrado busca *\migracion-*\datos\estado.json (un nivel) en la carpeta padre de la de los scripts, donde se suelen tener
  los batchs. Un batch sin estado.json no sale (con -Migrado, si sale como sin empezar).
  Salida: 0 siempre que haya podido leer; 1 si la ruta de -Migrado no existe.
  Antes de darlo por bueno, pasa tests\probar-donde.ps1.
#>
[CmdletBinding()]
param(
  [string]$Migrado = '',   # un solo batch: su carpeta (repo git migrado)
  [string]$Legacy = ''     # solo para el comando de un batch sin empezar: la carpeta del original (sin ella, un ejemplo)
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'comun.ps1')
. (Join-Path $PSScriptRoot 'tareas.ps1')
. (Join-Path $PSScriptRoot 'informe.ps1')

# Las tres letras con tilde que dice el script (el codigo es ASCII).
$a_ = [string][char]0xE1
$e_ = [string][char]0xE9
$i_ = [string][char]0xED

# ============================== TEXTO PLANO ==============================
# Un trozo de HTML de la portada en texto plano: sin etiquetas y con las entidades decodificadas. Primero las etiquetas y despues las entidades:
# un dato con < o > llega escapado (&lt;) y no es una etiqueta.
function ConvertTo-TextoPlano([string]$Html) {
  $t = [System.Net.WebUtility]::HtmlDecode([regex]::Replace($Html, '<[^>]+>', ''))
  return ([regex]::Replace($t, '\s+', ' ')).Trim()
}

# El recuadro "Siguiente paso" de la portada, en texto plano: Texto (el parrafo) y Comando (una cadena por linea; vacio si no hay).
# No lleva el titulo ni la linea que manda a FLUJO.md: eso lo dice este script al final.
function Get-SiguienteTexto($D, $T) {
  $html = Get-SiguienteHtml $D $T
  $cmd = @()
  $m = [regex]::Match($html, '(?s)<pre class="cmd">(.*?)</pre>')
  if ($m.Success) {
    $cmd = @([System.Net.WebUtility]::HtmlDecode($m.Groups[1].Value) -split "\r?\n" | Where-Object { $_ -ne '' })
    $html = $html.Remove($m.Index, $m.Length)
  }
  $html = [regex]::Replace($html, '(?s)<h2[^>]*>.*?</h2>|<p class="muted">.*?</p>', '')
  return [pscustomobject]@{ Texto = (ConvertTo-TextoPlano $html); Comando = $cmd }
}

# ================================ LOS DATOS ================================
# El estado.json mas reciente de las carpetas migracion-* de un batch ($null si no hay ninguno).
function Find-Estado([string]$CarpetaBatch) {
  $hallados = @()
  foreach ($d in @(Get-ChildItem -LiteralPath $CarpetaBatch -Directory -Filter 'migracion-*' -ErrorAction SilentlyContinue)) {
    $f = Join-Ruta $d.FullName 'datos/estado.json'
    if (Test-Path -LiteralPath $f -PathType Leaf) { $hallados += (Get-Item -LiteralPath $f) }
  }
  if ($hallados.Count -eq 0) { return $null }
  return @($hallados | Sort-Object @{ Expression = { $_.LastWriteTime }; Descending = $true }, FullName)[0]
}

# Lo justo del informe para el siguiente paso, sin leer fichas, tareas ni comparaciones (Read-DatosInforme lo lee todo).
function Read-DatosPaso([string]$Salida) {
  $datos = Join-Ruta $Salida 'datos'
  return [pscustomobject]@{
    Salida = $Salida; Estado = (Read-JsonSuave (Join-Path $datos 'estado.json')); Diag = (Read-Diagnostico $datos)
    Correccion = (Read-JsonSuave (Join-Path $datos 'correcciones.json')); PruebaLocal = (Read-JsonSuave (Join-Path $datos 'prueba-local.json'))
    CobAntes = (Read-JsonSuave (Join-Path $datos 'cobertura-antes.json')); CobDespues = (Read-JsonSuave (Join-Path $datos 'cobertura-despues.json'))
  }
}

# ================================ EL BLOQUE ================================
function Get-Campo([string]$Etiqueta, [string]$Texto) { return (($Etiqueta + ':').PadRight(11) + $Texto) }

function Get-LineasComando($Comando) { return @($Comando | ForEach-Object { ('    ' + $_).TrimEnd() }) }

# Un batch sin datos\estado.json: el comando de la primera pasada, solo con informe.
function Get-LineasSinEmpezar([string]$Nombre, [string]$Ruta) {
  $original = $Legacy
  if (-not $original) { $original = 'C:\ruta\original' }
  $l = @("=== $Nombre ===", (Get-Campo 'Punto' 'Sin empezar'))
  $l += (Get-Campo 'Siguiente' 'No hay nada hecho. Lanza la primera pasada, que solo monta el informe y no corrige nada:')
  $l += (Get-LineasComando @('.\migracion.ps1 -Legacy "' + $original + '" -Migrado "' + $Ruta + '" -SoloInforme'))
  return $l
}

# El bloque de un batch con estado.json ($Item es el fichero): su punto, su siguiente paso y, si la cobertura es baja, el paso de despues.
function Get-LineasBatch($Item, $T) {
  $datos = Split-Path $Item.FullName -Parent
  $salida = Split-Path $datos -Parent
  $D = Read-DatosPaso $salida
  $nombre = Get-BatchInforme $D
  if ($null -eq $D.Estado -or $D.Estado -isnot [System.Management.Automation.PSCustomObject]) {
    return @("=== $nombre ===", (Get-Campo 'Punto' ('No puedo leer ' + $Item.FullName + ': no es un JSON valido.')))
  }
  $paso = Get-SiguientePaso $D.Estado $D
  $punto = 'terminado'
  if ($paso.Caso -ceq 'corriendo') { $punto = 'fase ' + $paso.Fase + ', corriendo' }
  elseif ($paso.Caso -ceq 'parada') { $punto = 'fase ' + $paso.Fase + ', parada'; if ($paso.Motivo) { $punto += ': ' + $paso.Motivo } }
  elseif ($paso.Caso -ceq 'cortada') { $punto = 'fase ' + $paso.Fase + ', cortada' }
  $cuando = ConvertTo-FechaInforme $D.Estado.fin
  if ($null -eq $cuando) { $cuando = $Item.LastWriteTime }
  $l = @("=== $nombre ===", (Get-Campo 'Punto' ($punto + ' (' + $cuando.ToString('dd-MM-yyyy HH:mm', [System.Globalization.CultureInfo]::InvariantCulture) + ')')))
  $sig = Get-SiguienteTexto $D $T
  $l += (Get-Campo 'Siguiente' $sig.Texto)
  $l += (Get-LineasComando $sig.Comando)
  if ($paso.Caso -ceq 'parada' -and $D.Estado.parada.ayuda) {
    $l += 'Para pegar en Copilot:'
    $l += (Get-LineasComando @(([string]$D.Estado.parada.ayuda) -split "\r?\n"))
  }
  $c = $D.CobDespues
  $fichero = 'cobertura-despues.json'
  if ($null -eq $c) { $c = $D.CobAntes; $fichero = 'cobertura-antes.json' }
  if ($c -and $c.medida -eq $true -and $null -ne $c.porcentaje -and [double]$c.porcentaje -lt [double]$Cfg.CoberturaMinima) {
    $migrado = [string]$D.Estado.migrado
    if (-not $migrado) { $migrado = Split-Path $salida -Parent }
    $pct = Format-Trozo $T 'cob-pct' @{ PCT = "$($c.porcentaje)".Replace('.', ',') }
    # la medida puede ser vieja (el usuario pudo lanzar rescate.ps1 -Cobertura despues): lleva la fecha de su fichero, que no trae otra
    $medida = (Get-Item -LiteralPath (Join-Ruta $datos $fichero)).LastWriteTime.ToString('dd-MM-yyyy HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
    $l += (Get-Campo "Despu${e_}s" "La cobertura medida el $medida es $pct (m${i_}nimo $($Cfg.CoberturaMinima) %).")
    $l += (Get-LineasComando @('.\rescate.ps1 -Repo "' + $migrado + '" -Cobertura'))
    $l += "Si ya lo has lanzado despu${e_}s de esa fecha, mira el resultado en ${migrado}-rescate\.rescate\cobertura-faltan.md."
  }
  return $l
}

# ================================== PRINCIPAL ==================================
$marco = Split-Plantilla (Read-PlantillaInforme 'marco.html')
$portada = Split-Plantilla (Read-PlantillaInforme 'index.html')
$Trozos = Merge-Trozos $marco.Trozos $portada.Trozos

if ($Migrado -and -not (Test-Path -LiteralPath $Migrado -PathType Container)) { Fallo "No existe la carpeta de -Migrado: $Migrado"; exit 1 }

if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'preflight-resultado.txt'))) {
  Write-Host 'No has pasado el preflight en este equipo. Lanza esto antes de migrar:'
  Write-Host '    .\preflight.ps1'
}

$bloques = @()
if ($Migrado) {
  $ruta = (Resolve-Path -LiteralPath $Migrado).Path.TrimEnd('\', '/')
  $item = Find-Estado $ruta
  if ($item) { $bloques += , @{ Nombre = (Split-Path $ruta -Leaf); Fichero = $item } }
  else { $bloques += , @{ Nombre = (Split-Path $ruta -Leaf); Ruta = $ruta } }
}
else {
  $padre = Split-Path $PSScriptRoot -Parent
  foreach ($d in @(Get-ChildItem -LiteralPath $padre -Directory | Sort-Object Name)) {
    $item = Find-Estado $d.FullName
    if ($item) { $bloques += , @{ Nombre = $d.Name; Fichero = $item } }
  }
  if ($bloques.Count -eq 0) {
    Write-Host ''
    Write-Host "No he encontrado ningun batch con migracion-*\datos\estado.json en $padre."
    Write-Host 'Si el batch esta en otra carpeta, di cual con -Migrado:'
    Write-Host '    .\donde-estoy.ps1 -Migrado C:\ruta\batch-recibos'
  }
}

foreach ($b in $bloques) {
  try {
    if ($b.Fichero) { $l = @(Get-LineasBatch $b.Fichero $Trozos) } else { $l = @(Get-LineasSinEmpezar $b.Nombre $b.Ruta) }
  }
  catch { $l = @("=== $($b.Nombre) ===", (Get-Campo 'Punto' ('No he podido leerlo: ' + $_.Exception.Message))) }
  Write-Host ''
  foreach ($x in $l) { Write-Host $x }
}
Write-Host ''
Write-Host "Los pasos completos est${a_}n en FLUJO.md."
