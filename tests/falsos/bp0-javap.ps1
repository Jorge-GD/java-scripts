# bp0-javap.ps1 - javap de mentira para tests/probar-practicas.ps1 (BP-0). Cada argumento que no empieza por '-' es un fichero
# .class de mentira: su contenido es lo que javap -c -l -p habria sacado de el (el texto lo copia el test de un javap real).
#   BP0_JAVAP_LLAMADAS  fichero: cada llamada anade '<n argumentos>|<largo de los argumentos>|<argumentos>'.
#   BP0_JAVAP_ERROR     sale con 2 e imprime este texto en vez de nada.
if ($env:BP0_JAVAP_LLAMADAS) {
  $linea = $args -join ' '
  [System.IO.File]::AppendAllText($env:BP0_JAVAP_LLAMADAS, "$($args.Count)|$($linea.Length)|$linea`n")
}
if ($env:BP0_JAVAP_ERROR) { $env:BP0_JAVAP_ERROR; exit 2 }
foreach ($a in $args) {
  if ("$a".StartsWith('-')) { continue }
  if (-not (Test-Path -LiteralPath $a)) { "Error: no se encuentra $a"; exit 1 }
  [Console]::Out.Write([System.IO.File]::ReadAllText($a))
}
exit 0
