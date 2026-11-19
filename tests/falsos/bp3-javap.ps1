# bp3-javap.ps1 - javap de mentira de tests/probar-huella.ps1. Cada argumento que no empieza por '-' es un .class de mentira: un fichero
# cuyo contenido ES el texto de 'javap -v -p'. Por cada uno escribe 'Classfile <ruta>' y ese texto, como el javap real (los bytes tal cual,
# sin recodificar). Lo que lee del entorno:
#   BP3_JAVAP_LOG  un fichero: cada llamada deja una linea '<clases>|<largo de la linea de comandos>|<opciones>'
#   BP3_JAVAP_RC   el codigo de salida (y no escribe nada); con 0, o sin ella, escribe todas las clases
#   BP3_JAVAP_SALTA  un numero: no escribe la clase de ese orden (la 1.a es la 1), como un javap que se salta una
$clases = @($args | Where-Object { $_ -and -not "$_".StartsWith('-') })
$opciones = @($args | Where-Object { $_ -and "$_".StartsWith('-') })
if ($env:BP3_JAVAP_LOG) {
  [System.IO.File]::AppendAllText($env:BP3_JAVAP_LOG, ("$($clases.Count)|$([Environment]::CommandLine.Length)|$($opciones -join ' ')`n"))
}
if ($env:BP3_JAVAP_RC) { exit [int]$env:BP3_JAVAP_RC }
$salida = [Console]::OpenStandardOutput()
$n = 0
foreach ($c in $clases) {
  $n++
  if ($env:BP3_JAVAP_SALTA -and [int]$env:BP3_JAVAP_SALTA -eq $n) { continue }
  $cab = [System.Text.Encoding]::ASCII.GetBytes("Classfile $c`n")
  $salida.Write($cab, 0, $cab.Length)
  $cuerpo = [System.IO.File]::ReadAllBytes($c)
  $salida.Write($cuerpo, 0, $cuerpo.Length)
}
$salida.Flush()
exit 0
