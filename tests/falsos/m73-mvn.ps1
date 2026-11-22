# m73-mvn.ps1 - Maven de mentira para los tests m73 de tests/probar-local.ps1. Hace lo de m68-mvn.ps1 (y con el, lo de m40-mvn.ps1 y mvn-local.ps1) y, en cada caso que
# ejecuta (-Dprueba.local.job y -Dprueba.local.caso; ni el vacio ni 'otro'), mira el datos.sql que ve el caso. RESCATE_M73 trae banderas separadas por ';':
#   ya=<A>,<B>   la base de prueba ya tiene esos objetos (secuencias, indices, esquemas, vistas, restricciones, columnas...): si el datos.sql los crea sin IF NOT EXISTS,
#                el caso no deja estado.txt y su error.txt dice, como H2, que ya existe (en espanol; con la bandera en, en ingles) y lleva su codigo [90035-200]...
#   en           los mensajes de ya=, en ingles
#   informes     cada lado deja ficheros/informes/<hoy>-<hora>/resumen.xlsx: el original con la hora 10-26-58 y el migrado con la 10-31-07, las mismas celdas
#                (Hoja1!A1 'importe', Hoja1!B1 10, Hoja1!A2 la fecha de hoy con la hora de cada lado en texto) y un docProps/core.xml con la fecha de creacion de cada lado
#   informes-txt lo mismo con ficheros/informes/<hoy>-<hora>/resumen.txt: las mismas lineas en los dos lados (la hora del nombre es la unica diferencia)
#   celda        con informes, el migrado cambia la celda Hoja1!B3 (uno 'x', el otro 'y')
#   png          cada lado deja ficheros/logo.png: los mismos bytes, salvo con la bandera png-otro (el migrado lleva otro byte)
$raiz = (Get-Location).Path
$job = ''; $caso = ''
foreach ($a in $args) {
  if ("$a" -match '^-Dprueba\.local\.job=(.+)$') { $job = $Matches[1] }
  if ("$a" -match '^-Dprueba\.local\.caso=(.+)$') { $caso = $Matches[1] }
}
$salida = & (Join-Path $PSScriptRoot 'm68-mvn.ps1') @args
$codigo = $LASTEXITCODE
if ($args -notcontains 'test' -or -not $job -or -not $caso -or $caso -eq 'otro' -or $caso -eq 'vacio') { $salida; exit $codigo }
$banderas = @("$env:RESCATE_M73" -split ';')
$dir = [System.IO.Path]::Combine($raiz, 'target', 'prueba-local', $job, $caso)
$sql = [System.IO.Path]::Combine($raiz, 'src', 'test', 'resources', 'prueba-local', $job, $caso, 'datos.sql')
$ya = @()
foreach ($b in $banderas) { if ($b -match '^ya=(.+)$') { $ya = @($Matches[1] -split ',') } }
if ($ya.Count -gt 0 -and (Test-Path -LiteralPath $sql) -and (Test-Path -LiteralPath $dir)) {
  $texto = [System.IO.File]::ReadAllText($sql)
  $en = $banderas -contains 'en'
  $tipos = @(
    @('CREATE\s+SEQUENCE', 'Sequence', 90035, 'Sequence'),
    @('CREATE\s+(?:UNIQUE\s+)?INDEX', 'Index', 42111, 'Indice'),
    @('CREATE\s+SCHEMA', 'Schema', 90078, 'Schema'),
    @('CREATE\s+(?:FORCE\s+)?VIEW', 'View', 90038, 'View'),
    @('ALTER\s+TABLE\s+\S+\s+ADD\s+CONSTRAINT', 'Constraint', 90045, 'Constraint'),
    @('ALTER\s+TABLE\s+\S+\s+ADD(?:\s+COLUMN)?', 'Duplicate column name', 42121, 'Nombre de columna Duplicada')
  )
  foreach ($t in $tipos) {
    foreach ($nombre in $ya) {
      $m = [regex]::Match($texto, '(?i)\b' + $t[0] + '(?>\s+)(?!IF\s+NOT\s+EXISTS\b)(' + [regex]::Escape($nombre) + ')\b')
      if (-not $m.Success) { continue }
      $frase = $t[3] + ' "' + $nombre.ToUpperInvariant() + '" ya existe'
      if ($t[2] -eq 42121) { $frase = $t[3] + ' "' + $nombre.ToUpperInvariant() + '"' }
      if ($en) { $frase = $t[1] + ' "' + $nombre.ToUpperInvariant() + '"'; if ($t[2] -ne 42121) { $frase += ' already exists' } }
      $sentencia = $texto.Substring($m.Index).Split(';')[0].Trim()
      $fallo = "org.springframework.jdbc.datasource.init.ScriptStatementFailedException: Failed to execute SQL script statement #1 of class path resource [prueba-local/$job/$caso/datos.sql]: $sentencia; nested exception is org.h2.jdbc.JdbcSQLException: $frase; SQL statement:`n$sentencia [$($t[2])-200]"
      Get-ChildItem -LiteralPath $dir | Remove-Item -Recurse -Force
      [System.IO.File]::WriteAllText((Join-Path $dir 'error.txt'), ($fallo + "`n"))
      '[ERROR] El test no prepara el caso'
      exit 1
    }
  }
}
$migrado = ($raiz -like '*batch-nuevo*')
if (Test-Path -LiteralPath $dir) {
  $hoy = (Get-Date).ToString('yyyy-MM-dd')
  if ($banderas -contains 'informes-txt') {
    $hora = '10-26-58'
    if ($migrado) { $hora = '10-31-07' }
    $f = [System.IO.Path]::Combine($dir, 'ficheros', 'informes', ($hoy + '-' + $hora), 'resumen.txt')
    [void](New-Item -ItemType Directory -Path (Split-Path $f -Parent) -Force)
    [System.IO.File]::WriteAllText($f, "importe;10`n")
  }
  if ($banderas -contains 'informes') {
    $hora = '10-26-58'; $creado = $hoy + 'T10:26:58Z'; $celda = 'x'
    if ($migrado) { $hora = '10-31-07'; $creado = $hoy + 'T10:31:07Z'; $celda = 'y' }
    if ($banderas -notcontains 'celda') { $celda = 'x' }
    Add-Type -AssemblyName System.IO.Compression
    $fijo = New-Object System.DateTimeOffset(2020, 1, 1, 0, 0, 0, [System.TimeSpan]::Zero)
    $partes = [ordered]@{
      '[Content_Types].xml' = '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="xml" ContentType="application/xml"/></Types>'
      'docProps/core.xml' = '<?xml version="1.0" encoding="UTF-8"?><cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dcterms="http://purl.org/dc/terms/"><dcterms:created>' + $creado + '</dcterms:created></cp:coreProperties>'
      'xl/workbook.xml' = '<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Hoja1" sheetId="1" r:id="rId1"/></sheets></workbook>'
      'xl/_rels/workbook.xml.rels' = '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>'
      'xl/worksheets/sheet1.xml' = '<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>importe</t></is></c><c r="B1"><v>10</v></c></row><row r="2"><c r="A2" t="inlineStr"><is><t>generado ' + $hoy + ' ' + $hora.Replace('-', ':') + '</t></is></c></row><row r="3"><c r="B3" t="inlineStr"><is><t>' + $celda + '</t></is></c></row></sheetData></worksheet>'
    }
    $f = [System.IO.Path]::Combine($dir, 'ficheros', 'informes', ($hoy + '-' + $hora), 'resumen.xlsx')
    [void](New-Item -ItemType Directory -Path (Split-Path $f -Parent) -Force)
    $flujo = New-Object System.IO.FileStream($f, [System.IO.FileMode]::Create)
    $zip = New-Object System.IO.Compression.ZipArchive($flujo, [System.IO.Compression.ZipArchiveMode]::Create)
    foreach ($k in $partes.Keys) {
      $e = $zip.CreateEntry($k)
      $e.LastWriteTime = $fijo
      $w = New-Object System.IO.StreamWriter($e.Open(), (New-Object System.Text.UTF8Encoding($false)))
      $w.Write($partes[$k]); $w.Dispose()
    }
    $zip.Dispose(); $flujo.Dispose()
  }
  if ($banderas -contains 'png' -or $banderas -contains 'png-otro') {
    $bytes = [byte[]](0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0xFF, 0xFE, 0x80)
    if ($migrado -and $banderas -contains 'png-otro') { $bytes[18] = 0x81 }
    $f = [System.IO.Path]::Combine($dir, 'ficheros', 'logo.png')
    [void](New-Item -ItemType Directory -Path (Split-Path $f -Parent) -Force)
    [System.IO.File]::WriteAllBytes($f, $bytes)
  }
}
$salida
exit $codigo
