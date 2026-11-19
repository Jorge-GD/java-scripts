# bp4-copilot.ps1 - Copilot CLI de mentira para el grupo bp4 de tests/probar-practicas.ps1 (arreglo-practicas.ps1, BP-4). Lee el prompt de
# .rescate/tareas/<id>.prompt.md, saca su linea 'FICHERO: <ruta>' y cambia ese fichero segun el guion de RESCATE_FALSO ('guion' o
# 'guion:regex', varios separados por ';'; la regex, sobre la ruta del fichero; gana el primero que encaja; sin guion, 'bien'):
#   bien        anade un comentario al final del fichero (el compilado no cambia)
#   codigo      anade un metodo antes de la ultima llave (el compilado cambia)
#   codigo1     como codigo, pero solo en el primer intento: el reintento (su prompt lleva CORRECCION) hace bien
#   otro        como bien y, ademas, anade un comentario a src/main/java/com/acme/p4/Delta.java (otro fichero)
#   otro-add    como otro, y ademas deja los dos ficheros en el indice con 'git add' (sus cambios solo se ven con 'git diff --cached')
#   commit      como bien, y ademas hace un commit en el repositorio (prohibido)
#   borra       borra el fichero
#   nada        no toca nada
#   no-compila  anade una linea que no compila (el Maven de mentira la reconoce por NO-COMPILA)
#   falla       no toca nada y sale con 1
#   falla-cambia  como bien, pero sale con 1 (una llamada que falla despues de haber cambiado el fichero)
# Variables:
#   BP4_COPILOT   fichero: cada llamada anade '<fichero>|<guion>|<reintento: 0 o 1>'
$texto = ''
for ($i = 0; $i -lt $args.Count; $i++) { if ("$($args[$i])" -eq '-p') { $texto = "$($args[$i + 1])" } }
$raiz = (Get-Location).Path
$prompt = ''
if ($texto -match 'tareas/([\w\-]+)\.prompt\.md') { $prompt = [System.IO.File]::ReadAllText([System.IO.Path]::Combine($raiz, '.rescate', 'tareas', ($Matches[1] + '.prompt.md'))) }
$fichero = ''
if ($prompt -match '(?m)^FICHERO: (.*?)\s*$') { $fichero = $Matches[1] }
$guion = 'bien'
$elegido = $false
foreach ($g in ("$env:RESCATE_FALSO" -split ';')) {
  $nombre, $solo = ($g -split ':', 2)
  if (-not $solo) { $solo = '.' }
  if ($nombre -and -not $elegido -and $fichero -match $solo) { $guion = $nombre; $elegido = $true }
}
$reintento = 0
if ($prompt -match 'CORRECCI') { $reintento = 1 }
if ($env:BP4_COPILOT) { [System.IO.File]::AppendAllText($env:BP4_COPILOT, "$fichero|$guion|$reintento`n") }
function Ruta-Fichero([string]$Rel) { return [System.IO.Path]::Combine([string[]](@($raiz) + $Rel.Split('/'))) }
function Anade-Comentario([string]$Rel) {
  $r = Ruta-Fichero $Rel
  [System.IO.File]::WriteAllText($r, ([System.IO.File]::ReadAllText($r) + "// pasado a Lombok`n"))
}
function Anade-Codigo([string]$Rel, [string]$Linea) {
  $r = Ruta-Fichero $Rel
  $t = [System.IO.File]::ReadAllText($r)
  $k = $t.LastIndexOf('}')
  [System.IO.File]::WriteAllText($r, ($t.Substring(0, $k) + "  $Linea`n" + $t.Substring($k)))
}
if ($guion -eq 'codigo1') { if ($reintento -eq 1) { $guion = 'bien' } else { $guion = 'codigo' } }
switch ($guion) {
  'bien' { Anade-Comentario $fichero }
  'otro' { Anade-Comentario $fichero; Anade-Comentario 'src/main/java/com/acme/p4/Delta.java' }
  'otro-add' {
    Anade-Comentario $fichero
    Anade-Comentario 'src/main/java/com/acme/p4/Delta.java'
    & git -C $raiz add -- $fichero 'src/main/java/com/acme/p4/Delta.java'
  }
  'commit' {
    Anade-Comentario $fichero
    & git -C $raiz -c user.name=IA -c user.email=ia@example.invalid commit -q -a -m 'la IA commitea'
  }
  'borra' { Remove-Item -LiteralPath (Ruta-Fichero $fichero) -Force }
  'codigo' { Anade-Codigo $fichero 'int extra() { return 1; }' }
  'no-compila' { Anade-Codigo $fichero 'int x = NO-COMPILA;' }
  'falla' { [Console]::Error.WriteLine('Error de mentira: sin sesion'); exit 1 }
  'falla-cambia' { Anade-Comentario $fichero; [Console]::Error.WriteLine('Error de mentira: se corto la red'); exit 1 }
}
'hecho'
exit 0
