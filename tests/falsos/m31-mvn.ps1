# m31-mvn.ps1 - Maven de mentira para los tests m31 de tests/probar-local.ps1. Hace lo de m25-mvn.ps1 (y con el, lo de mvn-local.ps1) y, ademas:
#  - cada suite de tests unitarios (un 'test' sin -Dtest, que m25-mvn.ps1 resuelve sola) deja una linea en RESCATE_LLAMADAS/mvn.log, igual que
#    las demas llamadas de mvn-local.ps1 (carpeta|JAVA_HOME|argumentos): asi se ve en que orden se ejecuta lo de un arreglo;
#  - si RESCATE_M31 trae un guion, cada caso que ejecuta (-Dprueba.local.job y -Dprueba.local.caso) deja ademas en
#    target/prueba-local/<job>/<caso>/tablas/ lo que dice el guion; el lado se sabe por la carpeta (batch-viejo = original):
#      columnas             T.csv: el original ID;NOMBRE;IMPORTE (1 ana 10, 2 luis 20) y el migrado, lo mismo con las columnas y las filas en otro orden
#      columnas-valor       como columnas, pero el migrado lleva 25 y no 20 en la fila de luis
#      columnas-fila-rara   T.csv con una fila con mas campos que la cabecera, y el migrado con las columnas en otro orden
#      csv-fuera            ficheros/salida/x.csv (no es de tablas/) con las columnas permutadas en el migrado
#      framework            BATCH_JOB_INSTANCE.csv con otro contenido en cada lado y, solo en el migrado, TASK_EXECUTION.csv
$raiz = (Get-Location).Path
$suite = ($args -contains 'test' -and @($args | Where-Object { "$_" -like '-Dtest=*' }).Count -eq 0)
if ($suite -and $env:RESCATE_LLAMADAS) {
  [void](New-Item -ItemType Directory -Path $env:RESCATE_LLAMADAS -Force)
  [System.IO.File]::AppendAllText((Join-Path $env:RESCATE_LLAMADAS 'mvn.log'), ($raiz + '|' + $env:JAVA_HOME + '|' + ($args -join ' ') + "`n"))
}
& (Join-Path $PSScriptRoot 'm25-mvn.ps1') @args
$codigo = $LASTEXITCODE
$job = ''; $caso = ''
foreach ($a in $args) {
  if ("$a" -match '^-Dprueba\.local\.job=(.+)$') { $job = $Matches[1] }
  if ("$a" -match '^-Dprueba\.local\.caso=(.+)$') { $caso = $Matches[1] }
}
if ($env:RESCATE_M31 -and $codigo -eq 0 -and $job -and $caso -and $caso -ne 'vacio') {
  $original = ($raiz -like '*batch-viejo*')
  $dir = [System.IO.Path]::Combine($raiz, 'target', 'prueba-local', $job, $caso, 'tablas')
  [void](New-Item -ItemType Directory -Path $dir -Force)
  function Escribe-Tabla([string]$Nombre, [string]$Texto) { [System.IO.File]::WriteAllText((Join-Path $dir $Nombre), $Texto) }
  $g = $env:RESCATE_M31
  if ($g -eq 'columnas' -or $g -eq 'columnas-valor') {
    if ($original) { Escribe-Tabla 'T.csv' "ID;NOMBRE;IMPORTE`n1;ana;10`n2;luis;20`n" }
    elseif ($g -eq 'columnas') { Escribe-Tabla 'T.csv' "NOMBRE;IMPORTE;ID`nluis;20;2`nana;10;1`n" }
    else { Escribe-Tabla 'T.csv' "NOMBRE;IMPORTE;ID`nluis;25;2`nana;10;1`n" }
  }
  if ($g -eq 'columnas-fila-rara') {
    if ($original) { Escribe-Tabla 'T.csv' "ID;NOMBRE`n1;ana;x`n" } else { Escribe-Tabla 'T.csv' "NOMBRE;ID`nana;1;x`n" }
  }
  if ($g -eq 'csv-fuera') {
    $fich = [System.IO.Path]::Combine($raiz, 'target', 'prueba-local', $job, $caso, 'ficheros', 'salida')
    [void](New-Item -ItemType Directory -Path $fich -Force)
    if ($original) { $texto = "ID;NOMBRE;IMPORTE`n1;ana;10`n2;luis;20`n" } else { $texto = "NOMBRE;IMPORTE;ID`nana;10;1`nluis;20;2`n" }
    [System.IO.File]::WriteAllText((Join-Path $fich 'x.csv'), $texto)
  }
  if ($g -eq 'framework') {
    if ($original) { Escribe-Tabla 'BATCH_JOB_INSTANCE.csv' "JOB_INSTANCE_ID;JOB_NAME`n1;viejo`n" }
    else {
      Escribe-Tabla 'BATCH_JOB_INSTANCE.csv' "JOB_INSTANCE_ID;JOB_NAME`n7;nuevo`n"
      Escribe-Tabla 'TASK_EXECUTION.csv' "TASK_EXECUTION_ID;TASK_NAME`n1;nuevo`n"
    }
  }
}
exit $codigo
