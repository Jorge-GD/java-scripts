# m73-libro.ps1 - Escribe en <Ruta> un .xlsx de mentira (el XML minimo de un libro de una hoja): Hoja1!A1 'importe', Hoja1!B1 10, Hoja1!A2 'generado <Generado>' y
# Hoja1!B3 <Celda>, y en docProps/core.xml la fecha de creacion <Creado>. Las entradas del zip llevan una fecha fija: con los mismos datos salen los mismos bytes.
# Lo usan m73-mvn.ps1 y m73-regresion-mvn.ps1.
param([string]$Ruta, [string]$Creado, [string]$Generado, [string]$Celda)
Add-Type -AssemblyName System.IO.Compression
$fijo = New-Object System.DateTimeOffset(2020, 1, 1, 0, 0, 0, [System.TimeSpan]::Zero)
$partes = [ordered]@{
  '[Content_Types].xml' = '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="xml" ContentType="application/xml"/></Types>'
  'docProps/core.xml' = '<?xml version="1.0" encoding="UTF-8"?><cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dcterms="http://purl.org/dc/terms/"><dcterms:created>' + $Creado + '</dcterms:created></cp:coreProperties>'
  'xl/workbook.xml' = '<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Hoja1" sheetId="1" r:id="rId1"/></sheets></workbook>'
  'xl/_rels/workbook.xml.rels' = '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>'
  'xl/worksheets/sheet1.xml' = '<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>importe</t></is></c><c r="B1"><v>10</v></c></row><row r="2"><c r="A2" t="inlineStr"><is><t>generado ' + $Generado + '</t></is></c></row><row r="3"><c r="B3" t="inlineStr"><is><t>' + $Celda + '</t></is></c></row></sheetData></worksheet>'
}
[void](New-Item -ItemType Directory -Path (Split-Path $Ruta -Parent) -Force)
$flujo = New-Object System.IO.FileStream($Ruta, [System.IO.FileMode]::Create)
$zip = New-Object System.IO.Compression.ZipArchive($flujo, [System.IO.Compression.ZipArchiveMode]::Create)
foreach ($k in $partes.Keys) {
  $e = $zip.CreateEntry($k)
  $e.LastWriteTime = $fijo
  $w = New-Object System.IO.StreamWriter($e.Open(), (New-Object System.Text.UTF8Encoding($false)))
  $w.Write($partes[$k]); $w.Dispose()
}
$zip.Dispose(); $flujo.Dispose()
