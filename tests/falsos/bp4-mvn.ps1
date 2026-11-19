# bp4-mvn.ps1 - Maven de mentira para el grupo bp4 de tests/probar-practicas.ps1 (arreglo-practicas.ps1, BP-4).
# 'mvn -B compile' deja en target/classes un .class de mentira por cada .java de src/main/java, y uno mas por cada clase interna ('class Nombre'
# declarada dentro): su contenido es un texto como el de 'javap -v -p' (bp3-javap.ps1 lo imprime tal cual), hecho con el codigo del .java sin
# comentarios ni lineas en blanco. Dos .java que solo se diferencian en comentarios dan clases iguales; si cambia el codigo, cambian. Un .java
# con 'NO-COMPILA' en su codigo no compila: se imprime el error y se sale con 1. Cualquier otra llamada sale con 0 sin hacer nada.
# Variables:
#   BP4_LLAMADAS   fichero: cada llamada anade '<carpeta>|<argumentos>'
#   BP4_SUELTA     con ella, si dos o mas ficheros de src estan cambiados sin confirmar (git status), se compila ademas la clase
#                  com/acme/p4/Suelta.class, que no es de ningun .java: la diferencia de una ronda entera que no es de ningun fichero suyo
if ($args -contains '--version') { 'Apache Maven 3.9.8 (de mentira)'; exit 0 }
$raiz = (Get-Location).Path
if ($env:BP4_LLAMADAS) { [System.IO.File]::AppendAllText($env:BP4_LLAMADAS, $raiz + '|' + ($args -join ' ') + "`n") }
if (-not ($args.Count -eq 2 -and $args[0] -ceq '-B' -and $args[1] -ceq 'compile')) { exit 0 }
'[INFO] Scanning for projects...'
$fuentes = Join-Path (Join-Path (Join-Path $raiz 'src') 'main') 'java'
$clases = Join-Path (Join-Path $raiz 'target') 'classes'
$errores = @()
$salida = @{}
foreach ($f in @(Get-ChildItem -LiteralPath $fuentes -Recurse -File -Filter '*.java' | Sort-Object FullName)) {
  $codigo = [System.IO.File]::ReadAllText($f.FullName)
  $codigo = [regex]::Replace($codigo, '(?s)/\*.*?\*/', '')
  $codigo = [regex]::Replace($codigo, '//[^\n]*', '')
  $lineas = @($codigo -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  $rel = $f.FullName.Substring($fuentes.Length + 1).Replace('\', '/')
  if ($codigo.Contains('NO-COMPILA')) { $errores += $rel; continue }
  $base = $rel -replace '\.java$', ''
  $nombres = @($base)
  foreach ($m in [regex]::Matches($codigo, '\bclass\s+(\w+)')) {
    if ($m.Groups[1].Value -cne $f.BaseName) { $nombres += ($base + '$' + $m.Groups[1].Value) }
  }
  foreach ($n in $nombres) {
    $t = "Compiled from `"$($f.Name)`"`npublic class $($n.Replace('/', '.'))`n  minor version: 0`nConstant pool:`n   #1 = Utf8               de-mentira`n{`n"
    for ($i = 0; $i -lt $lineas.Count; $i++) { $t += "  void codigo$($i + 1)();`n    Code:`n       0: $($lineas[$i])`n" }
    $salida[$n + '.class'] = $t + "}`n"
  }
}
if ($env:BP4_SUELTA -and @(& git -C $raiz status --porcelain -- src).Count -ge 2) {
  $salida['com/acme/p4/Suelta.class'] = "Compiled from `"Suelta.java`"`npublic class com.acme.p4.Suelta`n  minor version: 0`nConstant pool:`n   #1 = Utf8               de-mentira`n{`n  void suelta();`n}`n"
}
if ($errores.Count -gt 0) {
  '[ERROR] COMPILATION ERROR : '
  foreach ($e in $errores) { "[ERROR] $e`:[1,1] no compila (de mentira)" }
  '[INFO] BUILD FAILURE'
  exit 1
}
if (Test-Path -LiteralPath $clases) { Remove-Item -LiteralPath $clases -Recurse -Force }   # como Maven al ver cambios: recompila todo
foreach ($k in $salida.Keys) {
  $ruta = Join-Path $clases $k.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
  [void](New-Item -ItemType Directory -Path (Split-Path $ruta -Parent) -Force)
  [System.IO.File]::WriteAllText($ruta, $salida[$k])
}
'[INFO] BUILD SUCCESS'
exit 0
