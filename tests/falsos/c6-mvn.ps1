# c6-mvn.ps1 - Maven de mentira para tests/probar-propiedades.ps1 (C6a). La unica llamada que hace propiedades.ps1 es
# 'dependency:build-classpath -Dmdep.outputFile=<fichero>': este falso la apunta y la contesta. Cualquier otra llamada tambien se apunta.
# Variables de entorno:
#   C6_LLAMADAS   fichero: cada llamada anade '<carpeta>|<argumentos>'.
#   C6_CLASSPATH  texto que deja en el fichero de -Dmdep.outputFile (los jars, separados por el separador de rutas del sistema).
#                 Sin esta variable no deja ningun fichero.
#   C6_RC         codigo de salida (por defecto 0). Con otro, imprime '[ERROR] <C6_ERROR>' y no deja ningun classpath.
if ($args -contains '--version') { 'Apache Maven 3.9.8 (de mentira)'; exit 0 }
$raiz = (Get-Location).Path
if ($env:C6_LLAMADAS) { [System.IO.File]::AppendAllText($env:C6_LLAMADAS, $raiz + '|' + ($args -join ' ') + "`n") }
'[INFO] Scanning for projects...'
if ($env:C6_RC -and [int]$env:C6_RC -ne 0) {
  '[ERROR] ' + $env:C6_ERROR
  '[ERROR] Failed to execute goal on project batch-recibos'
  exit ([int]$env:C6_RC)
}
if ($env:C6_CLASSPATH) {
  foreach ($a in $args) {
    if ("$a".StartsWith('-Dmdep.outputFile=')) { [System.IO.File]::WriteAllText("$a".Substring('-Dmdep.outputFile='.Length), $env:C6_CLASSPATH) }
  }
}
'[INFO] BUILD SUCCESS'
exit 0
