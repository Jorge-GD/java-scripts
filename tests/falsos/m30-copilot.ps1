# m30-copilot.ps1 - Copilot de mentira para los tests m30 de tests/probar-local.ps1 (lo que la IA toca de mas, el script lo deshace y prueba
# lo que queda). Hace lo de m25-copilot.ps1 (y con el, lo de copilot-local.ps1) y, si el guion de RESCATE_FALSO ('guion' o 'guion:regex', como
# en copilot-local.ps1) es de esta lista, ademas:
#   arnes-de-mas         un arnes bueno y, ademas, META-INF/MANIFEST.MF y com/x/Y.class en la raiz de la copia (un jar descomprimido) y
#                        un comentario en src/main/**/App.java; en el arnes sin pom (POM: no), tambien en el pom.xml
#   arnes-de-mas-muchos  un arnes bueno y siete ficheros nuevos en fuera/
#   arnes-pom-lombok     un arnes bueno y un pom.xml que cambia la <version> de org.projectlombok:lombok (ya estaba), anade
#                        com.acme:nueva-sin-scope (sin scope) y com.acme:nueva-test (con <scope>test</scope>)
#   arnes-pom-mas        un arnes bueno y un pom.xml que quita el <scope> de com.acme:otra, anade una <properties> y la dependencia
#                        com.acme:nueva-sin-scope
#   arnes-pom-roto       un arnes bueno y un pom.xml que no es XML valido
#   arnes-solo-con-main  un arnes que lleva NECESITA_MAIN y un comentario MAIN_TOCADO en src/main/**/App.java: m30-mvn.ps1 solo lo compila
#                        con ese cambio de src/main
#   reparar-solo-test    (tarea reparar) solo toca src/test/java/com/acme/nuevo/ReglaTest.java
#   reparar-test-inutil  (tarea reparar) toca ReglaTest.java y deja src/main/resources/nota.txt, que no cambia ninguna salida, en todos los intentos
#   reparar-inutil1      (tarea reparar) en el primer intento solo deja nota.txt; en el reintento (su prompt lleva la CORRECCION) arregla:
#                        pone minimo=5.00 en src/main/resources/regla.txt
# Un guion solo vale en su tarea (arnes-* en las de arnes, reparar-solo-test en las de reparar); en las demas se hace lo de siempre.
# Los guiones arnes-pom-* parten del pom que escribe Pom-M30 de tests/probar-local.ps1 (con CRLF o LF: el falso respeta el del original).
$texto = ''
for ($i = 0; $i -lt $args.Count; $i++) { if ("$($args[$i])" -eq '-p') { $texto = "$($args[$i + 1])" } }
$raiz = (Get-Location).Path
$id = ''
if ($texto -match 'tareas/([\w\-]+)\.prompt\.md') { $id = $Matches[1] }
$prompt = ''
if ($id) { $prompt = [System.IO.File]::ReadAllText((Join-Path (Join-Path (Join-Path $raiz '.rescate') 'tareas') ($id + '.prompt.md'))) }
$guion = ''
foreach ($g in ("$env:RESCATE_FALSO" -split ';')) {
  $nombre, $solo = ($g -split ':', 2)
  if (-not $solo) { $solo = '.' }
  if ($nombre -and -not $guion -and $id -match $solo) { $guion = $nombre }
}
$tipo = ([regex]::Match($prompt, '(?m)^TIPO: (.*?)\s*$')).Groups[1].Value
$mio = ($tipo -eq 'arnes-local' -and @('arnes-de-mas', 'arnes-de-mas-muchos', 'arnes-pom-lombok', 'arnes-pom-mas', 'arnes-pom-roto', 'arnes-solo-con-main') -contains $guion) -or ($tipo -eq 'reparar' -and @('reparar-solo-test', 'reparar-test-inutil', 'reparar-inutil1') -contains $guion)
if (-not $mio) {
  & (Join-Path $PSScriptRoot 'm25-copilot.ps1') @args
  exit $LASTEXITCODE
}
$env:RESCATE_FALSO = ''   # lo bueno (el test del arnes) lo hace copilot-local.ps1 sin guion; lo de mas lo pongo yo
& (Join-Path $PSScriptRoot 'm25-copilot.ps1') @args
$codigo = $LASTEXITCODE
function Ruta-M30([string]$Rel) { return [System.IO.Path]::Combine([string[]](@($raiz) + $Rel.Split('/'))) }
function Escribe-M30([string]$Rel, [string]$Texto) {
  $p = Ruta-M30 $Rel
  [void](New-Item -ItemType Directory -Path (Split-Path $p -Parent) -Force)
  [System.IO.File]::WriteAllText($p, $Texto)
}
function App-M30 { return @(Get-ChildItem -LiteralPath (Join-Path $raiz 'src/main') -Recurse -File -Filter 'App.java')[0].FullName }

if ($guion -in @('reparar-solo-test', 'reparar-test-inutil')) {
  [System.IO.File]::AppendAllText((Ruta-M30 'src/test/java/com/acme/nuevo/ReglaTest.java'), "// tocado por la IA`n")
}
if ($guion -eq 'reparar-test-inutil' -or ($guion -eq 'reparar-inutil1' -and $prompt -notmatch 'CORRECCI')) { Escribe-M30 'src/main/resources/nota.txt' "sin efecto`n" }
if ($guion -eq 'reparar-inutil1' -and $prompt -match 'CORRECCI') {
  $regla = Ruta-M30 'src/main/resources/regla.txt'
  [System.IO.File]::WriteAllText($regla, [System.IO.File]::ReadAllText($regla).Replace('minimo=5.01', 'minimo=5.00'))
}
if ($guion -eq 'arnes-de-mas') {
  Escribe-M30 'META-INF/MANIFEST.MF' "Manifest-Version: 1.0`n"
  Escribe-M30 'com/x/Y.class' "CAFEBABE`n"
  [System.IO.File]::AppendAllText((App-M30), "// tocado por la IA`n")
  if ($prompt -match '(?m)^POM: no\s*$') { [System.IO.File]::AppendAllText((Ruta-M30 'pom.xml'), "<!-- tocado por la IA -->`n") }
}
if ($guion -eq 'arnes-de-mas-muchos') { foreach ($n in 1..7) { Escribe-M30 "fuera/f$n.txt" "x`n" } }
if ($guion -eq 'arnes-solo-con-main') {
  [System.IO.File]::AppendAllText((Ruta-M30 'src/test/java/com/acme/viejo/PruebaLocalTest.java'), "// NECESITA_MAIN`n")
  [System.IO.File]::AppendAllText((App-M30), "// MAIN_TOCADO`n")
}
if ($guion -like 'arnes-pom-*') {
  $null = & git -C $raiz checkout -q -- pom.xml 2>&1   # sin lo que anade copilot-local.ps1: el pom de la IA es el de este guion
  $pom = Ruta-M30 'pom.xml'
  $x = [System.IO.File]::ReadAllText($pom)
  $nl = "`n"
  if ($x.Contains("`r`n")) { $nl = "`r`n" }
  if ($guion -eq 'arnes-pom-lombok') {
    $nuevas = '    <dependency>', '      <groupId>com.acme</groupId>', '      <artifactId>nueva-sin-scope</artifactId>', '      <version>1.0</version>', '    </dependency>',
      '    <dependency>', '      <groupId>com.acme</groupId>', '      <artifactId>nueva-test</artifactId>', '      <version>2.0</version>', '      <scope>test</scope>', '    </dependency>'
    $x = $x.Replace('<version>1.16.20</version>', '<version>1.18.30</version>').Replace("  </dependencies>", (($nuevas -join $nl) + $nl + '  </dependencies>'))
  }
  if ($guion -eq 'arnes-pom-mas') {
    $nueva = '    <dependency>', '      <groupId>com.acme</groupId>', '      <artifactId>nueva-sin-scope</artifactId>', '      <version>1.0</version>', '    </dependency>'
    $x = $x.Replace(('      <scope>provided</scope>' + $nl), '').Replace('  </dependencies>', (($nueva -join $nl) + $nl + '  </dependencies>' + $nl + '  <properties>' + $nl + '    <java.version>21</java.version>' + $nl + '  </properties>'))
  }
  if ($guion -eq 'arnes-pom-roto') { $x = '<project><dependencies>' + $nl }
  [System.IO.File]::WriteAllText($pom, $x)
}
exit $codigo
