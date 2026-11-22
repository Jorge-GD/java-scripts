# m77-mvn.ps1 - Maven de mentira para los tests m77 de tests/probar-local.ps1. Hace lo de m48-mvn.ps1 (y con el, lo de m33-mvn.ps1, m25-mvn.ps1 y mvn-local.ps1)
# y, si RESCATE_M77 trae guiones ('guion' o 'guion:regex', separados por ';'; la regex, sobre 'job/caso'; gana el primero que casa), cada ejecucion de un caso
# (-Dprueba.local.caso, tambien el vacio del arnes: 'job/vacio') deja un job que no arranca, como el de los jobs de verdad: estado=EXCEPCION, salida=<clase> (sin
# error.txt; con FAILED, estado=FAILED) y, en la salida de Maven, 'Caused by: <causa>'. Segun el lado (batch-viejo = original):
#   orig-bean        original: NoSuchBeanDefinitionException (No bean named 'contableConfig' available)
#   orig-creacion    original: BeanCreationException (Error creating bean with name 'contableConfig')
#   orig-parametros  original: JobParametersInvalidException (no es un contexto que no se monta: lo que un caso puede buscar justo)
#   orig-failed      original: FAILED con java.nio.file.NoSuchFileException: C:\datos\salida\outbox (una carpeta de Windows fija que el test no lleva a la del caso)
#   orig-failed-caso original: FAILED con una NoSuchFileException cuya ruta lleva el nombre del caso (C:\datos\salida\<caso>\outbox)
#   mig-proxy        migrado: UnsatisfiedDependencyException, causa IllegalArgumentException: Cannot subclass final class com.acme.poliza.PolizaJdbcAdapter
#   mig-circular     migrado: UnsatisfiedDependencyException, causa BeanCurrentlyInCreationException (circular reference)
#   mig-override     migrado: BeanDefinitionOverrideException (Invalid bean definition con un nombre que ya esta)
#   ambos-bean       los dos lados: NoSuchBeanDefinitionException (el caso sale igual)
$raiz = (Get-Location).Path
& (Join-Path $PSScriptRoot 'm48-mvn.ps1') @args
$codigo = $LASTEXITCODE
$job = ''; $caso = ''
foreach ($a in $args) {
  if ("$a" -match '^-Dprueba\.local\.job=(.+)$') { $job = $Matches[1] }
  if ("$a" -match '^-Dprueba\.local\.caso=(.+)$') { $caso = $Matches[1] }
}
# lado, estado, clase (la linea salida=), causa
$excepciones = @{
  'orig-bean'       = @('original', 'EXCEPCION', 'NoSuchBeanDefinitionException', "org.springframework.beans.factory.NoSuchBeanDefinitionException: No bean named 'contableConfig' available")
  'orig-creacion'   = @('original', 'EXCEPCION', 'BeanCreationException', "org.springframework.beans.factory.BeanCreationException: Error creating bean with name 'contableConfig'")
  'orig-parametros' = @('original', 'EXCEPCION', 'JobParametersInvalidException', 'org.springframework.batch.core.JobParametersInvalidException: The Job Parameters for the importe are invalid')
  'orig-failed'     = @('original', 'FAILED', 'FAILED', 'java.nio.file.NoSuchFileException: C:\datos\salida\outbox')
  'orig-failed-caso' = @('original', 'FAILED', 'FAILED', 'java.nio.file.NoSuchFileException: C:\datos\salida\<caso>\outbox')
  'mig-proxy'       = @('migrado', 'EXCEPCION', 'UnsatisfiedDependencyException', 'java.lang.IllegalArgumentException: Cannot subclass final class com.acme.poliza.PolizaJdbcAdapter')
  'mig-circular'    = @('migrado', 'EXCEPCION', 'UnsatisfiedDependencyException', 'org.springframework.beans.factory.BeanCurrentlyInCreationException: Error creating bean with name ''remesaServicio'': Requested bean is currently in creation: Is there an unresolvable circular reference or an asynchronous initialization dependency?')
  'mig-override'    = @('migrado', 'EXCEPCION', 'BeanDefinitionOverrideException', "org.springframework.beans.factory.support.BeanDefinitionOverrideException: Invalid bean definition with name 'tarifaServicio' defined in class path resource [com/acme/Config.class]: Cannot register bean definition for bean 'tarifaServicio' since there is already one bound")
  'ambos-bean'      = @('ambos', 'EXCEPCION', 'NoSuchBeanDefinitionException', "org.springframework.beans.factory.NoSuchBeanDefinitionException: No bean named 'contableConfig' available")
}
$base = [System.IO.Path]::Combine($raiz, 'target', 'prueba-local')
if ($env:RESCATE_M77 -and $codigo -eq 0 -and $caso -and (Test-Path -LiteralPath $base)) {
  $original = ($raiz -like '*batch-viejo*')
  foreach ($dj in @(Get-ChildItem -LiteralPath $base -Directory | Sort-Object Name)) {
    if ($job -and $dj.Name -ne $job) { continue }
    $dir = [System.IO.Path]::Combine($base, $dj.Name, $caso)
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    $guion = ''
    foreach ($g in ($env:RESCATE_M77 -split ';')) {
      $nombre, $solo = ($g -split ':', 2)
      if (-not $solo) { $solo = '.' }
      if ($nombre -and -not $guion -and ($dj.Name + '/' + $caso) -match $solo) { $guion = $nombre }
    }
    if (-not $excepciones.ContainsKey($guion)) { continue }
    $lado, $estado, $clase, $causa = $excepciones[$guion]
    $causa = $causa.Replace('<caso>', $caso)
    if ($lado -ne 'ambos' -and ($lado -eq 'original') -ne $original) { continue }
    Get-ChildItem -LiteralPath $dir | Remove-Item -Recurse -Force
    [System.IO.File]::WriteAllText([System.IO.Path]::Combine($dir, 'estado.txt'), "estado=$estado`nsalida=$clase`n")
    'Caused by: ' + $causa
  }
}
exit $codigo
