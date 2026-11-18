# copilot-local.ps1 - Copilot CLI de mentira para tests/probar-local.ps1 (prueba-local.ps1).
# Lee el prompt que nombra el texto de -p (.rescate/tareas/<id>.prompt.md) y, segun su linea TIPO:
#   arnes-local  escribe el fichero de la linea ESCRIBIR (un PruebaLocalTest que mvn-local.ps1 sabe "ejecutar") y, si
#                el prompt deja tocar el pom.xml, le anade una dependencia con <scope>test</scope>.
#   caso-local   escribe en la carpeta de la linea CARPETA el fichero ficheros/entrada/datos.txt con el texto de la
#                linea ENTRADA del prompt. Si ENTRADA lleva ' | SQL ', lo que va detras va a datos.sql (y lo de delante,
#                si hay algo, a datos.txt).
# RESCATE_FALSO es 'guion' o 'guion:regex' (la regex, sobre el id de la tarea), separados por ';'. Gana el primero:
#   arnes-toca-main      el arnes escribe ademas src/main/java/Tocado.java (prohibido)
#   arnes-dep-sin-test   el arnes anade al pom.xml una dependencia sin <scope>test</scope> (prohibido)
#   arnes-no-compila     el test lleva NO_COMPILA (mvn-local.ps1 no lo compila)
#   caso-fuera           el caso escribe ademas src/main/resources/fuera.txt (prohibido), en todos los intentos
#   caso-no-aplica       el caso solo escribe no-aplica.txt con una frase
#   caso-nada            el caso no escribe nada
#   caso-carpeta-vacia   el caso solo crea la carpeta ficheros/entrada, vacia
#   caso-sin-efecto      el caso solo escribe parametros.properties (su salida es la de un caso vacio)
#   caso-commit          el caso escribe lo suyo y src/main/resources/fuera.txt, y hace git add y git commit
# Cada llamada deja en la carpeta RESCATE_LLAMADAS (si esta) <id>-<pid>.txt con id, tipo, flags y las horas de inicio y
# de fin (ticks UTC). Con RESCATE_ESPERA=<n>, cada llamada tarda n segundos (para ver cuantas van a la vez).
$texto = ''
for ($i = 0; $i -lt $args.Count; $i++) { if ("$($args[$i])" -eq '-p') { $texto = "$($args[$i + 1])" } }
if ($texto -notmatch 'tareas/([\w\-]+)\.prompt\.md') { 'no entiendo el prompt'; exit 1 }
$id = $Matches[1]
$raiz = (Get-Location).Path
$prompt = [System.IO.File]::ReadAllText((Join-Path (Join-Path (Join-Path $raiz '.rescate') 'tareas') ($id + '.prompt.md')))
function Linea([string]$Clave) { return ([regex]::Match($prompt, '(?m)^' + $Clave + ': (.*?)\s*$')).Groups[1].Value }
$tipo = Linea 'TIPO'
$guion = ''
foreach ($g in ("$env:RESCATE_FALSO" -split ';')) {
  $nombre, $solo = ($g -split ':', 2)
  if (-not $solo) { $solo = '.' }
  if ($nombre -and -not $guion -and $id -match $solo) { $guion = $nombre }
}
$flags = (@($args | Where-Object { "$_" -match '^--(model=|effort=|add-dir=)' }) -join ' ')
$reg = @("id=$id", "pid=$PID", "tipo=$tipo", "flags=$flags", "guion=$guion", ('inicio=' + [DateTime]::UtcNow.Ticks))
$fichero = ''
if ($env:RESCATE_LLAMADAS) {
  [void](New-Item -ItemType Directory -Path $env:RESCATE_LLAMADAS -Force)
  $fichero = Join-Path $env:RESCATE_LLAMADAS ($id + '-' + $PID + '.txt')
  [System.IO.File]::WriteAllLines($fichero, [string[]]$reg)
}
if ($env:RESCATE_ESPERA) { Start-Sleep -Seconds ([int]$env:RESCATE_ESPERA) }

function Escribir([string]$Rel, [string]$Texto) {
  $p = $raiz
  foreach ($s in $Rel.Split('/')) { if ($s) { $p = Join-Path $p $s } }
  [void](New-Item -ItemType Directory -Path (Split-Path $p -Parent) -Force)
  [System.IO.File]::WriteAllText($p, $Texto)
}

if ($tipo -eq 'arnes-local') {
  $test = "// PruebaLocalTest de mentira: mvn-local.ps1 hace lo que haria`nclass PruebaLocalTest {}`n"
  if ($guion -eq 'arnes-no-compila') { $test += "// NO_COMPILA`n" }
  Escribir (Linea 'ESCRIBIR') $test
  $pom = Join-Path $raiz 'pom.xml'
  $dep = '<dependency><groupId>org.ejemplo</groupId><artifactId>prueba</artifactId><version>1.0</version><scope>test</scope></dependency>'
  if ($guion -eq 'arnes-dep-sin-test') { $dep = '<dependency><groupId>org.ejemplo</groupId><artifactId>runtime</artifactId><version>1.0</version></dependency>' }
  if ((Linea 'POM') -eq 'si' -or $guion -eq 'arnes-dep-sin-test') {
    $x = [System.IO.File]::ReadAllText($pom)
    if ($x -notmatch '<dependencies>') { $x = $x.Replace('</project>', "  <dependencies>`n  </dependencies>`n</project>") }
    [System.IO.File]::WriteAllText($pom, $x.Replace('</dependencies>', "  $dep`n  </dependencies>"))
  }
  if ($guion -eq 'arnes-toca-main') { Escribir 'src/main/java/Tocado.java' "class Tocado {}`n" }
}
elseif ($tipo -eq 'caso-local') {
  $carpeta = Linea 'CARPETA'
  $entrada, $sql = ((Linea 'ENTRADA') -split ' \| SQL ', 2)
  if ($guion -eq 'caso-no-aplica') { Escribir ($carpeta + '/no-aplica.txt') "Este caso pide encender el correo.`n" }
  elseif ($guion -eq 'caso-carpeta-vacia') { [void](New-Item -ItemType Directory -Path (Join-Path $raiz ($carpeta + '/ficheros/entrada')) -Force) }
  elseif ($guion -eq 'caso-sin-efecto') { Escribir ($carpeta + '/parametros.properties') "modo=prueba`n" }
  elseif ($guion -ne 'caso-nada') {
    if ($entrada) { Escribir ($carpeta + '/ficheros/entrada/datos.txt') ($entrada + "`n") }
    if ($sql) { Escribir ($carpeta + '/datos.sql') ($sql + "`n") }
  }
  if ($guion -eq 'caso-fuera' -or $guion -eq 'caso-commit') { Escribir 'src/main/resources/fuera.txt' "fuera`n" }
  if ($guion -eq 'caso-commit') { $null = & git -C $raiz add -A 2>&1; $null = & git -C $raiz commit -q -m 'la IA hace commit' 2>&1 }
}
else { 'no entiendo el tipo'; exit 1 }
if ($fichero) { [System.IO.File]::AppendAllText($fichero, ('fin=' + [DateTime]::UtcNow.Ticks + "`n")) }
'hecho'
exit 0
