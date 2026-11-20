# bp0-mvn.ps1 - Maven de mentira para tests/probar-practicas.ps1 (BP-0). La unica llamada que hace practicas.ps1 es la de javac, '-B compile':
# este falso la apunta (BP0_LLAMADAS) y la contesta; cualquier otra llamada tambien se apunta, y asi las pruebas cuentan las que sobran. Variables:
#   BP0_LLAMADAS       fichero: cada llamada anade '<carpeta>|<argumentos>|clases-antes=<n>' (n = ficheros en target/classes al llegar).
#   BP0_JAVAC_SALIDA   fichero con lo que imprime javac; '{{RAIZ}}' se cambia por la carpeta donde se lanza Maven.
#   BP0_JAVAC_ERROR    no compila: imprime '[ERROR] COMPILATION ERROR :' y '[ERROR] <este texto>' y sale con 1.
#   BP0_JAVAC_ESPERA   segundos que tarda antes de hacer nada (para probar el tope).
#   BP0_CLASES         carpeta cuyo contenido se copia a target/classes al compilar (los falsos .class llevan el texto de javap).
if ($args -contains '--version') { 'Apache Maven 3.9.8 (de mentira)'; exit 0 }
$raiz = (Get-Location).Path
$clases = Join-Path (Join-Path $raiz 'target') 'classes'
if ($env:BP0_LLAMADAS) {
  $antes = 0
  if (Test-Path -LiteralPath $clases) { $antes = @(Get-ChildItem -LiteralPath $clases -Recurse -File).Count }
  [System.IO.File]::AppendAllText($env:BP0_LLAMADAS, $raiz + '|' + ($args -join ' ') + '|clases-antes=' + $antes + "`n")
}
if ($env:BP0_JAVAC_ESPERA) { Start-Sleep -Seconds ([int]$env:BP0_JAVAC_ESPERA) }
'[INFO] Scanning for projects...'
if ($env:BP0_JAVAC_ERROR) {
  '[ERROR] COMPILATION ERROR : '
  '[ERROR] ' + $env:BP0_JAVAC_ERROR
  '[INFO] BUILD FAILURE'
  exit 1
}
if ($env:BP0_CLASES) {
  [void](New-Item -ItemType Directory -Path $clases -Force)
  Copy-Item -Path (Join-Path $env:BP0_CLASES '*') -Destination $clases -Recurse -Force
}
if ($env:BP0_JAVAC_SALIDA) { [System.IO.File]::ReadAllText($env:BP0_JAVAC_SALIDA).Replace('{{RAIZ}}', ($raiz -replace '\\', '/')).TrimEnd() }
'[INFO] BUILD SUCCESS'
exit 0
