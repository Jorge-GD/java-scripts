<#
probar-revision.ps1 - Banco de pruebas de revision.ps1 (C3: revision del arbol final por flujos, solo lee). No necesita Copilot ni Maven:
usa el Copilot de mentira tests/falsos/c3-copilot.ps1, que lee el prompt de la tarea, deja rastro de cada llamada y escribe la respuesta
que le da cada prueba. Los repos son de juguete (git en una carpeta de pruebas) con datos inventados (com.acme.recibos). Nunca llama al
Copilot ni al Maven reales. Vale para Windows PowerShell 5.1 y para PowerShell 7. Solo ASCII a proposito.

  .\tests\probar-revision.ps1                       # todas las pruebas
  .\tests\probar-revision.ps1 -Solo cache           # las que llevan 'cache' en el nombre
  .\tests\probar-revision.ps1 -Dir D:\tmp\x -Conservar

Sale con 0 si todo pasa y con 1 si algo falla.
#>
param(
  [string]$Dir = '',
  [string]$Solo = '',
  [switch]$Conservar
)
$ErrorActionPreference = 'Stop'
$aqui = Split-Path -Parent $MyInvocation.MyCommand.Path
$raiz = Split-Path -Parent $aqui
$falsos = Join-Path $aqui 'falsos'
. (Join-Path $aqui 'comun-banco.ps1')
. (Join-Path $raiz 'comun.ps1')
. (Join-Path $raiz 'tareas.ps1')
. (Join-Path $raiz 'practicas.ps1')
. (Join-Path $raiz 'revision.ps1')
$Cfg.CopilotExe = Join-Path $falsos 'c3-copilot.ps1'
$Cfg.SegundosPorLlamada = 120

# ================================ UTILIDADES ================================
$P = 'src/main/java/com/acme/recibos/'

# Un .java de juguete: package, la cabecera de la clase (con su 'public class X implements Y') y el cuerpo.
function Clase([string]$Decl, [string]$Cuerpo = '') { return "package com.acme.recibos;`n`n$Decl {`n$Cuerpo}`n" }

# Un repo de juguete: $Ficheros (ruta relativa -> texto) en main con un commit 'inicial', y encima la rama 'rescate' (donde se trabaja).
# Deja el entorno para las pruebas: las carpetas de datos y registros, y el Copilot de mentira con $Respuestas (nombre de fichero -> texto).
function Nuevo-Escenario([string]$Nombre, [hashtable]$Ficheros, [hashtable]$Respuestas = @{}) {
  $r = Join-Path $Dir $Nombre
  if (Test-Path -LiteralPath $r) { Remove-Item -LiteralPath $r -Recurse -Force }
  $wt = Join-Path $r 'wt'
  [void](New-Item -ItemType Directory -Path $wt -Force)
  foreach ($k in $Ficheros.Keys) { Escribe $wt $k $Ficheros[$k] }
  Inicia-Repo $wt
  [void](GitEn $wt @('checkout', '-q', '-b', 'rescate'))
  $resp = Join-Path $r 'respuestas'
  [void](New-Item -ItemType Directory -Path $resp -Force)
  foreach ($k in $Respuestas.Keys) { [System.IO.File]::WriteAllText((Join-Path $resp $k), [string]$Respuestas[$k]) }
  $e = [pscustomobject]@{
    Raiz = $r; Dir = $wt; Datos = (Join-Path $r 'datos'); Registros = (Join-Path $r 'registros'); Respuestas = $resp
    Llamadas = (Join-Path $r 'llamadas.txt'); Json = (Join-Path (Join-Path $r 'datos') 'revision.json')
  }
  foreach ($d in @($e.Datos, $e.Registros)) { [void](New-Item -ItemType Directory -Path $d -Force) }
  $script:Datos = $e.Datos
  $script:Registros = $e.Registros
  $script:LegacyRoot = $e.Dir
  $script:RepoRoot = $e.Dir
  $script:ModeloElegido = ''
  [Environment]::SetEnvironmentVariable('C3_RESPUESTAS', $e.Respuestas)
  [Environment]::SetEnvironmentVariable('C3_LLAMADAS', $e.Llamadas)
  return $e
}

# Cambia un fichero del repo de juguete y lo commitea en la rama de trabajo.
function Commitea([string]$D, [string]$Rel, [string]$Texto) {
  Escribe $D $Rel $Texto
  [void](GitEn $D @('add', '--', $Rel))
  [void](GitEn $D @('commit', '-q', '-m', "cambia $Rel"))
}

function Lee-Json([string]$Ruta) {
  if (-not (Test-Path -LiteralPath $Ruta)) { return $null }
  return ([System.IO.File]::ReadAllText($Ruta) | ConvertFrom-Json)
}

# Las llamadas que ha recibido el Copilot de mentira: id, tipo, reintento, flags y carpeta de trabajo.
function Llamadas-De($E) {
  if (-not (Test-Path -LiteralPath $E.Llamadas)) { return , @() }
  return , @([System.IO.File]::ReadAllLines($E.Llamadas) | Where-Object { $_ } | ForEach-Object {
      $c = $_.Split('|')
      [pscustomobject]@{ Id = $c[0]; Tipo = $c[1]; Reintento = $c[2]; Flags = $c[3]; Carpeta = $c[4] }
    })
}

# Una pasada como la de migracion.ps1: las tareas, las pendientes en tandas de Cfg.Paralelo, lo que dice cada una (hecha, o atascada tras
# Cfg.Intentos), y revision.json. Devuelve las tareas.
function Pasada($E, [bool]$Todo = $true, [string[]]$Cand = @(), [bool]$ConservarAtascadas = $false) {
  $tareas = @(Get-TareasRevision $E.Dir 'main' $Todo $Cand $ConservarAtascadas)
  while ($true) {
    $pend = @($tareas | Where-Object { $_.estado -eq 'pendiente' })
    if ($pend.Count -eq 0) { break }
    $lote = @($pend | Select-Object -First ([int]$Cfg.Paralelo))
    $res = @(Invoke-Ronda $lote $E.Dir $E.Dir)
    foreach ($o in $res) {
      $t = $o.Tarea
      $t.intentos++
      $t.motivo = $o.Motivo
      $t.ultimoEstado = $o.Estado
      if ($o.Estado -eq 'ok') { $t.estado = 'hecha'; $t.resultado = $o.Ficha }
      elseif ($t.intentos -ge [int]$Cfg.Intentos) { $t.estado = 'atascada' }
      Save-Tarea $t
    }
  }
  Save-Revision $tareas
  return $tareas
}

function Unidad-De($Unidades, [string]$Nombre) { return @($Unidades | Where-Object { $_.nombre -ceq $Nombre })[0] }

# Los nombres cortos de los ficheros de una unidad (sin la ruta ni .java), separados por coma.
function Cortos($Ficheros) { return ((@($Ficheros) | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_) }) -join ',') }

# Una tarea hecha a mano (sin pasar por Get-TareasRevision) con esta unidad: sus ficheros y sus candidatas (nombres sin ruta ni .java).
function Tarea-De([string]$Id, [string[]]$Ficheros, [string[]]$Candidatas = @()) {
  $e = [pscustomobject]@{
    unidad = $Id; tipoUnidad = 'step'; ficheros = @($Ficheros | ForEach-Object { "$P$_.java" }); candidatas = @($Candidatas | ForEach-Object { "$P$_.java" })
    sinResolver = @(); huella = 'abcd1234'; commit = 'abc1234'; todo = $false
  }
  return (New-TareaTipo 'revision-flujo' "revision-$Id" "revision-$Id" 'datos/revision.json' $e)
}

# Escribe lo que dice la IA de la tarea $T (un texto) y la comprueba con Test-Revision.
function Veredicto($E, $T, [string]$Json) {
  Escribe $E.Dir ".rescate/tareas/$($T.id).json" $Json
  return (Test-Revision $T $E.Dir)
}

# Un hallazgo como lo escribe la IA, en JSON. Lo que va en $Cambios pisa lo que trae (un campo en $null se quita).
function Hallazgo([hashtable]$Cambios = @{}) {
  $h = [ordered]@{ regla = 'SB-STEPSCOPE'; fichero = ($P + 'CargaConfig.java'); linea = 6; cita = 'public FlatFileItemReader<Recibo> lector()'; texto = 'Devuelve el reader sin ItemStream.' }
  foreach ($k in $Cambios.Keys) { if ($null -eq $Cambios[$k]) { $h.Remove($k) } else { $h[$k] = $Cambios[$k] } }
  return (ConvertTo-Json -InputObject $h -Compress)
}

function Salida([string[]]$Hallazgos) { return ('{"hallazgos": [' + ($Hallazgos -join ',') + ']}') }

# Los ficheros del escenario de las pruebas de comprobacion: la unidad es CargaConfig (el step) y Huerfana (candidata); Otra no es de la unidad.
$JavaCarga = @'
package com.acme.recibos;

public class CargaConfig {
  @Bean
  @StepScope
  public FlatFileItemReader<Recibo> lector() {
    return new FlatFileItemReader<>();
  }

  @Bean
  public Step cargaStep(JobRepository repo, PlatformTransactionManager tm) {
    return new StepBuilder("cargaStep", repo).build();
  }
}
'@
$FicherosComprobacion = @{
  ($P + 'CargaConfig.java') = $JavaCarga
  ($P + 'Huerfana.java') = (Clase 'public class Huerfana' "  int resto;`n")
  ($P + 'Otra.java') = (Clase 'public class Otra' "  int otra;`n")
}

# El escenario de comprobacion, con su tarea y sus datos. Devuelve el escenario y la tarea.
function Escenario-Comprobacion([string]$Nombre) {
  $e = Nuevo-Escenario $Nombre $FicherosComprobacion
  $t = Tarea-De 'cargaStep' @('CargaConfig', 'Huerfana') @('Huerfana')
  return [pscustomobject]@{ E = $e; T = $t }
}

# Uno bueno y uno malo: vale (justo la mitad) con un hallazgo y un descarte. Devuelve el veredicto.
function Uno-Malo([string]$Nombre, [hashtable]$Cambios, [string]$ConJson = '') {
  $x = Escenario-Comprobacion $Nombre
  $malo = Hallazgo $Cambios
  if ($ConJson) { $malo = $ConJson }
  return (Veredicto $x.E $x.T (Salida @((Hallazgo @{}), $malo)))
}

# ================================ PRUEBAS ================================
$Pruebas = [ordered]@{}

$Pruebas['1 catalogo: las siete reglas, con titulo, que busca y tokens; las tres que ya se miden no estan'] = {
  $r = @(Get-ReglasRevision)
  Igual 'los ids, en orden' 'SB-LISTENER,SB-STEPSCOPE,SB-TRANSACCION,SB-CONTEXTO,BOOT-ENABLEBATCH,J21-INTERNOS,CAND-MUERTA' (($r | ForEach-Object { $_.id }) -join ',')
  Comprueba 'cada una lleva titulo y que, con texto' (@($r | Where-Object { -not $_.titulo -or -not $_.que }).Count -eq 0)
  Comprueba 'cada una lleva al menos un token' (@($r | Where-Object { @($_.tokens).Count -eq 0 }).Count -eq 0)
  Igual 'los tokens de SB-LISTENER' 'Listener|@Before|@After|@On' ((@($r | Where-Object { $_.id -ceq 'SB-LISTENER' })[0].tokens) -join '|')
  Igual 'los de CAND-MUERTA' 'class |interface |enum |record ' ((@($r | Where-Object { $_.id -ceq 'CAND-MUERTA' })[0].tokens) -join '|')
  foreach ($quitada in @('SB-FACTORIAS', 'J21-FORMATO', 'J21-SECURITYMANAGER')) {
    Comprueba "$quitada no esta: ya lo mide practicas.ps1 o rescate.ps1" (@($r | Where-Object { $_.id -ceq $quitada }).Count -eq 0)
  }
  $l = @($r | Where-Object { $_.id -ceq 'SB-LISTENER' })[0].que
  Comprueba 'SB-LISTENER manda buscar el nombre del listener en todo el repositorio' ($l -match 'todo el repositorio')
  Comprueba 'y no es hallazgo si un job o un step lo registra con .listener( o es su reader, processor, writer o tasklet' ($l -match '\.listener\(' -and $l -match 'reader' -and $l -match 'tasklet')
  Comprueba 'los textos llevan tildes de verdad (no \u00xx sin leer)' (@($r | Where-Object { $_.que -match '\\u[0-9a-fA-F]{4}' -or $_.titulo -match '\\u[0-9a-fA-F]{4}' }).Count -eq 0)
}

# ---- (a) un step con un reader por @Bean ----
$Pruebas['2 a) .reader(miReader()) con un @Bean que devuelve FlatFileItemReader<X>: la unidad lleva el config y el fichero del @Bean'] = {
  $f = @{
    ($P + 'StepsConfig.java') = (Clase 'public class StepsConfig' ('  @Bean' + "`n" + '  public Step cargaStep(JobRepository repo, PlatformTransactionManager tm) {' + "`n" + '    return new StepBuilder("cargaStep", repo).<Recibo, Recibo>chunk(10, tm).reader(miReader()).writer(new EscritorRecibos()).build();' + "`n  }`n"))
    ($P + 'LectoresConfig.java') = (Clase 'public class LectoresConfig' ('  @Bean' + "`n" + '  @StepScope' + "`n" + '  public FlatFileItemReader<Recibo> miReader() { return null; }' + "`n"))
    ($P + 'EscritorRecibos.java') = (Clase 'public class EscritorRecibos implements ItemWriter<Recibo>')
  }
  $e = Nuevo-Escenario 'a1' $f
  $u = @(Get-UnidadesRevision $e.Dir 'main' $true @())
  Igual 'una sola unidad' 1 $u.Count
  Igual 'es un step, de nombre cargaStep' 'step|cargaStep|revision-cargaStep' "$($u[0].tipo)|$($u[0].nombre)|$($u[0].id)"
  Igual 'el config, el fichero del @Bean (el tipo FlatFileItemReader no es del proyecto) y el writer' 'StepsConfig,LectoresConfig,EscritorRecibos' (Cortos $u[0].ficheros)
  Comprueba 'las rutas son relativas, con /' ($u[0].ficheros[0] -ceq ($P + 'StepsConfig.java'))
  Igual 'nada sin resolver' 0 @($u[0].sinResolver).Count
  # el tipo del @Bean es una clase del proyecto: va su fichero y no el del @Bean (que queda suelto)
  $f2 = @{
    ($P + 'StepsConfig.java') = (Clase 'public class StepsConfig' ('  @Bean' + "`n" + '  public Step cargaStep(JobRepository repo, PlatformTransactionManager tm) {' + "`n" + '    return new StepBuilder("cargaStep", repo).reader(miLector()).build();' + "`n  }`n"))
    ($P + 'LectoresConfig.java') = (Clase 'public class LectoresConfig' ('  @Bean' + "`n" + '  public LectorRecibos miLector() { return null; }' + "`n"))
    ($P + 'LectorRecibos.java') = (Clase 'public class LectorRecibos implements ItemReader<Recibo>')
  }
  $e2 = Nuevo-Escenario 'a2' $f2
  $u2 = @(Get-UnidadesRevision $e2.Dir 'main' $true @())
  Igual 'dos unidades: el step y el config de los @Bean, que ya no esta en el step' 'step:cargaStep|fichero:LectoresConfig' (($u2 | ForEach-Object { "$($_.tipo):$($_.nombre)" }) -join '|')
  Igual 'el step lleva su config y la clase del reader' 'StepsConfig,LectorRecibos' (Cortos $u2[0].ficheros)
}

# ---- (b) como se resuelve cada nombre ----
$Pruebas['3 b) resolucion: por nombre de clase, por @Bean, por campo y por parametro; lo que no se resuelve va a sinResolver'] = {
  $pasos = @'
package com.acme.recibos;

public class Pasos {
  private LectorRecibos lector;

  @Bean
  public Step paso(JobRepository repo, PlatformTransactionManager tm, ProcesadorRecibos procesador) {
    return new StepBuilder("paso", repo)
        .<Recibo, Recibo>chunk(5, tm)
        .reader(lector)
        .processor(procesador)
        .writer(new EscritorRecibos())
        .listener(oyenteFinal())
        .listener(desconocido)
        .tasklet(limpiaTemporales(), tm)
        .build();
  }
}
'@
  $f = @{
    ($P + 'Pasos.java') = $pasos
    ($P + 'LectorRecibos.java') = (Clase 'public class LectorRecibos implements ItemReader<Recibo>')
    ($P + 'ProcesadorRecibos.java') = (Clase 'public class ProcesadorRecibos implements ItemProcessor<Recibo, Recibo>')
    ($P + 'EscritorRecibos.java') = (Clase 'public class EscritorRecibos implements ItemWriter<Recibo>')
    ($P + 'Oyentes.java') = (Clase 'public class Oyentes' ('  @Bean' + "`n" + '  public StepExecutionListener oyenteFinal() { return null; }' + "`n"))
    ($P + 'LimpiaTemporales.java') = (Clase 'public class LimpiaTemporales implements Tasklet')
  }
  $e = Nuevo-Escenario 'b' $f
  $u = @(Get-UnidadesRevision $e.Dir 'main' $true @())
  Igual 'una sola unidad: todo cae en el step' 1 $u.Count
  Igual 'campo, parametro, new X(), @Bean (su fichero, porque el tipo no es del proyecto) y x() con la primera en mayuscula, en el orden de la cadena' 'Pasos,LectorRecibos,ProcesadorRecibos,EscritorRecibos,Oyentes,LimpiaTemporales' (Cortos $u[0].ficheros)
  Igual 'sinResolver lleva el que no se encuentra' 'desconocido' (@($u[0].sinResolver) -join ',')
}

# ---- (c) mas de seis ficheros ----
$Pruebas['4 c) mas de seis ficheros: seis en el step (el suyo primero) y el resto suelto'] = {
  $nombres = @('LectorUno', 'ProcesadorDos', 'EscritorTres', 'OyenteCuatro', 'OyenteCinco', 'OyenteSeis', 'OyenteSiete')
  $cadena = '.reader(new LectorUno()).processor(new ProcesadorDos()).writer(new EscritorTres()).listener(new OyenteCuatro()).listener(new OyenteCinco()).listener(new OyenteSeis()).listener(new OyenteSiete())'
  $f = @{ ($P + 'Siete.java') = (Clase 'public class Siete' ('  Step s(JobRepository repo) { return new StepBuilder("siete", repo)' + $cadena + '.build(); }' + "`n")) }
  foreach ($n in $nombres) { $f[($P + $n + '.java')] = (Clase "public class $n") }
  $e = Nuevo-Escenario 'c' $f
  $u = @(Get-UnidadesRevision $e.Dir 'main' $true @())
  Igual 'tres unidades: el step y dos sueltas' 'step:siete|fichero:OyenteSeis|fichero:OyenteSiete' (($u | ForEach-Object { "$($_.tipo):$($_.nombre)" }) -join '|')
  Igual 'el step lleva seis: el suyo y los cinco primeros de la cadena' 'Siete,LectorUno,ProcesadorDos,EscritorTres,OyenteCuatro,OyenteCinco' (Cortos $u[0].ficheros)
  Igual 'una suelta lleva solo su fichero' 'OyenteSeis' (Cortos $u[1].ficheros)
  # sin $Todo, solo entran los que cambiaron o tienen papel; aqui los siete del final no tienen papel (ni listener: no implementan nada)
  $u2 = @(Get-UnidadesRevision $e.Dir 'main' $false @())
  Igual 'sin todo: solo el step, que tiene papel por su new StepBuilder (las dos sueltas no tienen papel ni cambios)' 'step:siete' (($u2 | ForEach-Object { "$($_.tipo):$($_.nombre)" }) -join '|')
  $u3 = @(Get-UnidadesRevision $e.Dir 'main' $false @(($P + 'OyenteSiete.java')))
  Igual 'una candidata fuera del step entra como suelta' 'step:siete|fichero:OyenteSiete' (($u3 | ForEach-Object { "$($_.tipo):$($_.nombre)" }) -join '|')
}

# ---- (d) alcance ----
$Pruebas['5 d) alcance: lo cambiado desde la base, lo que tiene papel y las candidatas; un POJO sin nada no entra; con todo, si'] = {
  $f = @{
    ($P + 'Recibo.java') = (Clase 'public class Recibo implements Serializable' ('  // @Configuration  new StepBuilder("x", repo)  implements ItemReader' + "`n" + '  /* @BeforeStep Tasklet new JobBuilder("y", repo) */' + "`n" + '  long importe;' + "`n"))
    ($P + 'Util.java') = (Clase 'public class Util' "  static int dos() { return 2; }`n")
    ($P + 'Cambiado.java') = (Clase 'public class Cambiado' "  int a;`n")
    ($P + 'Candidata.java') = (Clase 'public class Candidata' "  int b;`n")
    ($P + 'Lector.java') = (Clase 'public class Lector implements ItemReader<Recibo>')
    ($P + 'EscritorPlano.java') = (Clase 'public class EscritorPlano extends FlatFileItemWriter<Recibo>')
    ($P + 'Tarea.java') = (Clase 'public class Tarea implements Tasklet')
    ($P + 'Oyente.java') = (Clase 'public class Oyente implements StepExecutionListener')
    ($P + 'Flujo.java') = (Clase 'public class Flujo implements ItemStream, Serializable')
    ($P + 'ConfGeneral.java') = ("package com.acme.recibos;`n`n@Configuration`npublic class ConfGeneral {`n}`n")
    ($P + 'Escopado.java') = (Clase 'public class Escopado' ('  @StepScope' + "`n" + '  Object x() { return null; }' + "`n"))
    ($P + 'Antes.java') = (Clase 'public class Antes' ('  @BeforeStep' + "`n" + '  void antes(StepExecution s) { }' + "`n"))
    ($P + 'Montaje.java') = (Clase 'public class Montaje' ('  Job j(JobRepository repo) { return new JobBuilder("j", repo).build(); }' + "`n"))
    'src/main/resources/application.yml' = "spring:`n  main:`n    banner-mode: off`n"
  }
  $e = Nuevo-Escenario 'd' $f
  Commitea $e.Dir ($P + 'Cambiado.java') (Clase 'public class Cambiado' "  int a;`n  int cambiado;`n")
  Commitea $e.Dir 'src/main/resources/application.yml' "spring:`n  main:`n    banner-mode: console`n"
  $u = @(Get-UnidadesRevision $e.Dir 'main' $false @(($P + 'Candidata.java')))
  $nombres = @($u | ForEach-Object { $_.nombre })
  Igual 'sin todo: los que cambian, los que tienen papel y la candidata, en orden de ruta' 'Antes,Cambiado,Candidata,ConfGeneral,Escopado,EscritorPlano,Flujo,Lector,Montaje,Oyente,Tarea' ($nombres -join ',')
  Comprueba 'todas son sueltas (ninguna lleva new StepBuilder)' (@($u | Where-Object { $_.tipo -ne 'fichero' }).Count -eq 0)
  Comprueba 'un POJO sin cambios ni papel no entra, aunque sus comentarios nombren cosas con papel' ($nombres -cnotcontains 'Recibo' -and $nombres -cnotcontains 'Util')
  Comprueba 'el application.yml cambiado no entra: no es un .java' (@($u | Where-Object { @($_.ficheros | Where-Object { $_ -notmatch '\.java$' }).Count -gt 0 }).Count -eq 0)
  $t = @(Get-UnidadesRevision $e.Dir 'main' $true @())
  Igual 'con todo entran todos los .java de src/main/java' 13 $t.Count
  Comprueba 'con todo entra el POJO' (@($t | Where-Object { $_.nombre -ceq 'Recibo' }).Count -eq 1)
  # sin base que resolver (o sin git) no hay cambios que mirar: quedan el papel y las candidatas
  $v = @(Get-UnidadesRevision $e.Dir 'no-existe' $false @())
  Comprueba 'con una base que git no conoce, Cambiado deja de entrar y el papel sigue' (@($v | Where-Object { $_.nombre -ceq 'Cambiado' }).Count -eq 0 -and @($v | Where-Object { $_.nombre -ceq 'Lector' }).Count -eq 1)
}

# ---- (e) formas de un step ----
$Pruebas['6 e) un step sin .build() acaba en el primer ;; el nombre que no es literal sale como <Fichero>-<n>; dos steps en un fichero no se mezclan'] = {
  $config = @'
package com.acme.recibos;

public class Config {
  // new StepBuilder("comentado", repo).tasklet(new Comentada(), tm).build();
  @Bean
  public Step primero(JobRepository repo, PlatformTransactionManager tm) {
    return new StepBuilder(nombreDelPaso, repo).tasklet(new TareaUno(), tm);
  }

  @Bean
  public Step segundo(JobRepository repo, PlatformTransactionManager tm) {
    return new StepBuilder("segundo", repo)
        .tasklet((c, ch) -> { limpia(); return RepeatStatus.FINISHED; }, tm)
        .listener(new OyenteDos())
        .build();
  }

  @Bean
  public Step tercero(JobRepository repo, PlatformTransactionManager tm) {
    return new StepBuilder("tercero", repo)
        .<Recibo, Recibo>chunk(10, tm)
        .reader(new LectorFlat().nombre("r").build())
        .listener(new OyenteTres())
        .build();
  }
}
'@
  $f = @{
    ($P + 'Config.java') = $config
    ($P + 'TareaUno.java') = (Clase 'public class TareaUno implements Tasklet')
    ($P + 'OyenteDos.java') = (Clase 'public class OyenteDos implements StepExecutionListener')
    ($P + 'OyenteTres.java') = (Clase 'public class OyenteTres implements StepExecutionListener')
    ($P + 'LectorFlat.java') = (Clase 'public class LectorFlat')
    ($P + 'Comentada.java') = (Clase 'public class Comentada implements Tasklet')
  }
  $e = Nuevo-Escenario 'e' $f
  $u = @(Get-UnidadesRevision $e.Dir 'main' $true @())
  Igual 'tres steps, en el orden del fichero, y la clase Comentada, que solo sale en un comentario, suelta' 'step:Config-1|step:segundo|step:tercero|fichero:Comentada' (($u | ForEach-Object { "$($_.tipo):$($_.nombre)" }) -join '|')
  Igual 'ids: revision- y el nombre limpio' 'revision-Config-1,revision-segundo,revision-tercero,revision-Comentada' (($u | ForEach-Object { $_.id }) -join ',')
  Igual 'el primero (sin .build(), nombre no literal) acaba en el ; y no coge nada del segundo' 'Config,TareaUno' (Cortos $u[0].ficheros)
  Igual 'el segundo: la lambda con ; dentro no corta la cadena' 'Config,OyenteDos' (Cortos $u[1].ficheros)
  Igual 'el tercero: el .build() de dentro de un argumento no corta la cadena' 'Config,LectorFlat,OyenteTres' (Cortos $u[2].ficheros)
  # dos steps con el mismo nombre (en dos ficheros): -2
  $f2 = @{
    ($P + 'A.java') = (Clase 'public class A' ('  Step s(JobRepository r) { return new StepBuilder("carga", r).build(); }' + "`n"))
    ($P + 'B.java') = (Clase 'public class B' ('  Step s(JobRepository r) { return new StepBuilder("carga", r).build(); }' + "`n"))
    ($P + 'C.java') = (Clase 'public class C' ('  Step s(JobRepository r) { return new StepBuilder("carga", r).build(); }' + "`n"))
    ($P + 'Carga.java') = (Clase 'public class Carga' ('  Step s(JobRepository r) { return new StepBuilder("Carga de datos", r).build(); }' + "`n"))
  }
  $e2 = Nuevo-Escenario 'e2' $f2
  $u2 = @(Get-UnidadesRevision $e2.Dir 'main' $true @())
  Igual 'un nombre repetido lleva -2 y -3; un nombre con espacios sale limpio' 'revision-carga,revision-carga-2,revision-carga-3,revision-Carga-de-datos' (($u2 | ForEach-Object { $_.id }) -join ',')
}

# ---- (f) lo que se descarta ----
$Pruebas['7 f) un hallazgo bueno y uno con una regla que no esta en el catalogo: vale y descarta el malo con su motivo (tambien una de las quitadas)'] = {
  $v = Uno-Malo 'f1' @{ regla = 'SB-NOEXISTE' }
  Comprueba 'vale: justo la mitad' $v.Ok $v.Motivo
  Igual 'se queda el bueno' 1 @($v.Ficha.hallazgos).Count
  Igual 'y descarta uno' 1 @($v.Ficha.descartados).Count
  Igual 'con su regla y su fichero' 'SB-NOEXISTE|src/main/java/com/acme/recibos/CargaConfig.java' "$($v.Ficha.descartados[0].regla)|$($v.Ficha.descartados[0].fichero)"
  Comprueba 'el motivo dice que no esta en el catalogo' ($v.Ficha.descartados[0].motivo -match 'catalogo') $v.Ficha.descartados[0].motivo
  $w = Uno-Malo 'f1b' @{ regla = 'SB-FACTORIAS'; cita = 'new StepBuilder("cargaStep", repo)'; linea = 11 }
  Comprueba 'SB-FACTORIAS, que se quito del catalogo, tambien se descarta' (@($w.Ficha.descartados).Count -eq 1 -and $w.Ficha.descartados[0].motivo -match 'catalogo') ($w.Ficha.descartados[0].motivo)
}

$Pruebas['8 f) un fichero que no es de la unidad se descarta'] = {
  $v = Uno-Malo 'f2' @{ fichero = ($P + 'Otra.java'); linea = 3; cita = 'public class Otra' }
  Comprueba 'vale' $v.Ok $v.Motivo
  Igual 'un descarte' 1 @($v.Ficha.descartados).Count
  Comprueba 'el motivo habla de la unidad' ($v.Ficha.descartados[0].motivo -match 'no es de la unidad') $v.Ficha.descartados[0].motivo
  Igual 'sale con su fichero' ($P + 'Otra.java') $v.Ficha.descartados[0].fichero
}

$Pruebas['9 f) sin linea, con una linea que no es un numero, o con 0: se descarta'] = {
  foreach ($c in @(@('falta', $null), @('texto', 'seis'), @('cero', 0), @('decimal', 6.5))) {
    $v = Uno-Malo ('f3' + $c[0]) @{ linea = $c[1] }
    Comprueba "linea $($c[0]): vale y descarta uno" ($v.Ok -and @($v.Ficha.descartados).Count -eq 1 -and @($v.Ficha.hallazgos).Count -eq 1) $v.Motivo
    if (@($v.Ficha.descartados).Count -eq 1) { Comprueba "linea $($c[0]): el motivo habla de la linea" ($v.Ficha.descartados[0].motivo -match '\.linea') $v.Ficha.descartados[0].motivo }
  }
}

$Pruebas['10 f) sin cita, con la cita vacia o de mas de 120 caracteres: se descarta'] = {
  foreach ($c in @(@('falta', $null), @('vacia', '  '), @('larga', ('x' * 130)))) {
    $v = Uno-Malo ('f4' + $c[0]) @{ cita = $c[1] }
    Comprueba "cita $($c[0]): vale y descarta uno" ($v.Ok -and @($v.Ficha.descartados).Count -eq 1 -and @($v.Ficha.hallazgos).Count -eq 1) $v.Motivo
    if (@($v.Ficha.descartados).Count -eq 1) { Comprueba "cita $($c[0]): el motivo habla de la cita" ($v.Ficha.descartados[0].motivo -match '\.cita') $v.Ficha.descartados[0].motivo }
  }
}

$Pruebas['11 f) sin texto o con el texto vacio: se descarta'] = {
  foreach ($c in @(@('falta', $null), @('vacio', ' '))) {
    $v = Uno-Malo ('f5' + $c[0]) @{ texto = $c[1] }
    Comprueba "texto $($c[0]): vale y descarta uno" ($v.Ok -and @($v.Ficha.descartados).Count -eq 1 -and @($v.Ficha.hallazgos).Count -eq 1) $v.Motivo
    if (@($v.Ficha.descartados).Count -eq 1) { Comprueba "texto $($c[0]): el motivo habla del texto" ($v.Ficha.descartados[0].motivo -match '\.texto') $v.Ficha.descartados[0].motivo }
  }
  $x = Uno-Malo 'f5c' @{} '"esto no es un objeto"'
  Comprueba 'un elemento que no es un objeto tambien se descarta, sin romper nada' ($x.Ok -and @($x.Ficha.descartados).Count -eq 1) $x.Motivo
}

$Pruebas['12 f) una cita que no sale en el fichero se descarta; con espacios distintos si sale'] = {
  $v = Uno-Malo 'f6' @{ cita = 'public ItemReader<Recibo> inventado()' }
  Comprueba 'vale y descarta la inventada' ($v.Ok -and @($v.Ficha.descartados).Count -eq 1) $v.Motivo
  Comprueba 'el motivo dice que no sale en el fichero' ($v.Ficha.descartados[0].motivo -match 'no sale en el fichero') $v.Ficha.descartados[0].motivo
  $w = Uno-Malo 'f6b' @{ cita = "public   FlatFileItemReader<Recibo>`n  lector()" }
  Comprueba 'una cita con otros blancos que el codigo sale igual (Find-Cita no cuenta los espacios)' ($w.Ok -and @($w.Ficha.descartados).Count -eq 0 -and @($w.Ficha.hallazgos).Count -eq 2) $w.Motivo
}

$Pruebas['13 f) una cita sin ningun token de su regla se descarta; con uno, vale'] = {
  # la linea 11 sale en el fichero, pero SB-STEPSCOPE pide ItemReader, ItemWriter o ItemProcessor
  $v = Uno-Malo 'f7' @{ cita = 'public Step cargaStep(JobRepository repo, PlatformTransactionManager tm)'; linea = 11 }
  Comprueba 'vale y descarta la que no lleva token' ($v.Ok -and @($v.Ficha.descartados).Count -eq 1) $v.Motivo
  Comprueba 'el motivo habla de los tokens de la regla' ($v.Ficha.descartados[0].motivo -match 'token') $v.Ficha.descartados[0].motivo
  $w = Uno-Malo 'f7b' @{ regla = 'SB-TRANSACCION'; cita = 'public Step cargaStep(JobRepository repo, PlatformTransactionManager tm)'; linea = 11 }
  Comprueba 'la misma cita con una regla cuyo token si lleva (TransactionManager) vale' ($w.Ok -and @($w.Ficha.descartados).Count -eq 0 -and @($w.Ficha.hallazgos).Count -eq 2) $w.Motivo
}

$Pruebas['14 f) CAND-MUERTA en un fichero que no es candidata se descarta; en una candidata, vale'] = {
  $c = @{ regla = 'CAND-MUERTA'; fichero = ($P + 'Huerfana.java'); linea = 3; cita = 'public class Huerfana'; texto = 'Nadie la usa.' }
  $v = Uno-Malo 'f8' @{ regla = 'CAND-MUERTA'; fichero = ($P + 'CargaConfig.java'); linea = 3; cita = 'public class CargaConfig'; texto = 'Nadie la usa.' }
  Comprueba 'en CargaConfig (no es candidata) vale y descarta uno' ($v.Ok -and @($v.Ficha.descartados).Count -eq 1) $v.Motivo
  Comprueba 'el motivo habla de las candidatas' ($v.Ficha.descartados[0].motivo -match 'candidata') $v.Ficha.descartados[0].motivo
  $w = Uno-Malo 'f8b' $c
  Comprueba 'en Huerfana (candidata de la unidad) vale, sin descartes' ($w.Ok -and @($w.Ficha.descartados).Count -eq 0 -and @($w.Ficha.hallazgos).Count -eq 2) $w.Motivo
}

$Pruebas['15 f) la linea se corrige con CitaCerca: a 3 o menos se deja, a mas se pone la linea donde sale; los hallazgos quedan probados'] = {
  $x = Escenario-Comprobacion 'f9'
  $v = Veredicto $x.E $x.T (Salida @((Hallazgo @{ linea = 8 }), (Hallazgo @{ linea = 30 }), (Hallazgo @{ linea = 9 })))
  Comprueba 'vale' $v.Ok $v.Motivo
  # la cita sale en la linea 6: a 2 de distancia se deja, a 24 se corrige y a 3 (el limite) se deja
  Igual 'lineas dadas 8, 30 y 9 -> 8, 6 y 9' '8,6,9' (($v.Ficha.hallazgos | ForEach-Object { $_.linea }) -join ',')
  Comprueba 'todos probados' (@($v.Ficha.hallazgos | Where-Object { $_.probado -ne $true }).Count -eq 0)
  Igual 'la ficha lleva regla, fichero, linea, cita, texto y probado' 'regla,fichero,linea,cita,texto,probado' (($v.Ficha.hallazgos[0].PSObject.Properties.Name) -join ',')
  Igual 'y la ficha, hallazgos, descartados y sobran' 'hallazgos,descartados,sobran' (($v.Ficha.PSObject.Properties.Name) -join ',')
}

$Pruebas['16 g) la salida: sin fichero, sin JSON, sin hallazgos o con algo que no es una lista, es invalida con su motivo; una lista vacia vale'] = {
  $x = Escenario-Comprobacion 'g0'
  $r = Test-Revision $x.T $x.E.Dir
  Comprueba 'sin fichero de salida: invalida, y el motivo dice cual' (-not $r.Ok -and $r.Motivo -match 'revision-cargaStep\.json') $r.Motivo
  $r = Veredicto $x.E $x.T 'esto no es json {'
  Comprueba 'un texto que no es JSON: invalida' (-not $r.Ok -and $r.Motivo -match 'JSON') $r.Motivo
  $r = Veredicto $x.E $x.T '[]'
  Comprueba 'un JSON que no es un objeto: invalida' (-not $r.Ok) $r.Motivo
  $r = Veredicto $x.E $x.T '{"otra": 1}'
  Comprueba 'sin hallazgos: invalida, y el motivo nombra el campo' (-not $r.Ok -and $r.Motivo -match 'hallazgos') $r.Motivo
  $r = Veredicto $x.E $x.T '{"hallazgos": "ninguno"}'
  Comprueba 'hallazgos que no es una lista: invalida' (-not $r.Ok -and $r.Motivo -match 'hallazgos') $r.Motivo
  $r = Veredicto $x.E $x.T '{"hallazgos": []}'
  Comprueba 'una lista vacia vale' $r.Ok $r.Motivo
  Igual 'sin hallazgos, sin descartes y sin sobran' '0|0|0' "$(@($r.Ficha.hallazgos).Count)|$(@($r.Ficha.descartados).Count)|$($r.Ficha.sobran)"
}

# ---- (g) mas de la mitad descartados ----
$Pruebas['17 g) mas de la mitad descartados es invalida, con el motivo del primer descarte; justo la mitad vale; con uno solo no cuenta'] = {
  $x = Escenario-Comprobacion 'g1'
  $malo = Hallazgo @{ regla = 'SB-NOEXISTE' }
  $mal2 = Hallazgo @{ fichero = ($P + 'Otra.java') }
  $bien = Hallazgo @{}
  $r = Veredicto $x.E $x.T (Salida @($malo, $mal2, $bien))
  Comprueba '2 de 3 descartados: invalida' (-not $r.Ok) $r.Motivo
  Comprueba 'el motivo lleva el del primero (la regla que no esta)' ($r.Motivo -match 'catalogo') $r.Motivo
  Comprueba 'y las cuentas' ($r.Motivo -match '2 de 3') $r.Motivo
  $r = Veredicto $x.E $x.T (Salida @($malo, $mal2))
  Comprueba '2 de 2: invalida' (-not $r.Ok) $r.Motivo
  $r = Veredicto $x.E $x.T (Salida @($malo, $bien, $bien, $bien))
  Comprueba '1 de 4: vale' $r.Ok $r.Motivo
  $r = Veredicto $x.E $x.T (Salida @($malo, $mal2, $bien, $bien))
  Comprueba '2 de 4, justo la mitad: vale' $r.Ok $r.Motivo
  Igual 'con dos y dos' '2|2' "$(@($r.Ficha.hallazgos).Count)|$(@($r.Ficha.descartados).Count)"
  $r = Veredicto $x.E $x.T (Salida @($malo))
  Comprueba '1 de 1: vale (hace falta al menos 2 hallazgos para que cuente la mitad), sin hallazgos' ($r.Ok -and @($r.Ficha.hallazgos).Count -eq 0 -and @($r.Ficha.descartados).Count -eq 1) $r.Motivo
}

# ---- (h) como mucho cinco ----
$Pruebas['18 h) mas de cinco validos: se quedan los cinco primeros y sobran dice cuantos mas habia'] = {
  $x = Escenario-Comprobacion 'h'
  $hs = @(1..7 | ForEach-Object { Hallazgo @{ texto = "hallazgo $_" } })
  $r = Veredicto $x.E $x.T (Salida $hs)
  Comprueba 'vale' $r.Ok $r.Motivo
  Igual 'cinco' 5 @($r.Ficha.hallazgos).Count
  Igual 'los cinco primeros, en su orden' 'hallazgo 1,hallazgo 2,hallazgo 3,hallazgo 4,hallazgo 5' (($r.Ficha.hallazgos | ForEach-Object { $_.texto }) -join ',')
  Igual 'sobran 2' 2 $r.Ficha.sobran
  $r = Veredicto $x.E $x.T (Salida @(1..5 | ForEach-Object { Hallazgo @{} }))
  Igual 'con cinco justos, sobran 0' 0 $r.Ficha.sobran
  # los descartados no cuentan para los cinco
  $r = Veredicto $x.E $x.T (Salida (@(1..2 | ForEach-Object { Hallazgo @{ regla = 'SB-NOEXISTE' } }) + @(1..6 | ForEach-Object { Hallazgo @{ texto = "bueno $_" } })))
  Comprueba '2 descartados y 6 buenos: vale, con 5 y sobra 1' ($r.Ok -and @($r.Ficha.hallazgos).Count -eq 5 -and $r.Ficha.sobran -eq 1 -and @($r.Ficha.descartados).Count -eq 2) $r.Motivo
}

# ---- (i) cache, esfuerzo y reintento: con el Copilot de mentira ----
$JavaPasos = @'
package com.acme.recibos;

public class Pasos {
  @Bean
  @StepScope
  public FlatFileItemReader<Recibo> miLector() {
    return new FlatFileItemReader<>();
  }

  @Bean
  public Step paso(JobRepository repo, PlatformTransactionManager tm) {
    return new StepBuilder("paso", repo)
        .<Recibo, Recibo>chunk(10, tm)
        .reader(miLector())
        .writer(new EscritorUno())
        .build();
  }
}
'@
$JavaEscritor = @'
package com.acme.recibos;

public class EscritorUno implements ItemWriter<Recibo> {
  public void write(Chunk<Recibo> items) {
    System.out.println(items);
  }
}
'@
$JavaSuelto = @'
package com.acme.recibos;

@Configuration
public class Suelto {
  private ExecutionContext contexto;
  public void guarda() {
    contexto.put("lista", new ArrayList<Recibo>());
  }
}
'@
$FicherosFlujo = @{ ($P + 'Pasos.java') = $JavaPasos; ($P + 'EscritorUno.java') = $JavaEscritor; ($P + 'Suelto.java') = $JavaSuelto }

$Pruebas['19 i) cache: la segunda pasada sin cambios no llama a Copilot; cambiar un fichero de la unidad, las candidatas o la plantilla, si'] = {
  $e = Nuevo-Escenario 'i1' $FicherosFlujo
  $t1 = @(Pasada $e)
  $ll = (Llamadas-De $e)
  Igual 'primera pasada: una llamada por unidad (el step y la suelta)' 2 $ll.Count
  Comprueba 'las dos son de revision-flujo' (@($ll | Where-Object { $_.Tipo -eq 'revision-flujo' }).Count -eq 2)
  Comprueba 'las dos con esfuerzo de lectura (medium)' (@($ll | Where-Object { $_.Flags -match '--effort=medium' }).Count -eq 2) (($ll | ForEach-Object { $_.Flags }) -join ' / ')
  Comprueba 'y trabajan en el worktree, sin ninguna carpeta del original (sin --add-dir)' (@($ll | Where-Object { $_.Carpeta -ceq $e.Dir -and $_.Flags -notmatch 'add-dir' }).Count -eq 2) (($ll | ForEach-Object { $_.Carpeta }) -join ' / ')
  Igual 'las dos tareas, hechas' 'hecha,hecha' (($t1 | ForEach-Object { $_.estado }) -join ',')
  Comprueba 'las entradas no llevan la propiedad fichero (Invoke-Ronda la leeria del original) y si ficheros' (@($t1 | Where-Object { $_.entradas.PSObject.Properties.Name -contains 'fichero' }).Count -eq 0 -and @($t1[0].entradas.ficheros).Count -eq 2)
  Comprueba 'hay revision.json' (Test-Path -LiteralPath $e.Json)
  $t2 = @(Pasada $e)
  Igual 'segunda pasada sin cambios: ninguna llamada mas' 2 (Llamadas-De $e).Count
  Igual 'y las tareas siguen hechas' 'hecha,hecha' (($t2 | ForEach-Object { $_.estado }) -join ',')
  # un fichero de la unidad cambia (y se commitea: la huella sigue al blob de HEAD)
  Commitea $e.Dir ($P + 'EscritorUno.java') ($JavaEscritor + "// cambio`n")
  $t3 = @(Pasada $e)
  $ll = (Llamadas-De $e)
  Igual 'cambiar un fichero del step: una llamada mas, la del step' 'revision-paso' (@($ll | Select-Object -Skip 2 | ForEach-Object { $_.Id }) -join ',')
  $head = (GitEn $e.Dir @('rev-parse', 'HEAD')).Substring(0, 7)
  Igual 'la tarea reutilizada (la suelta) lleva el commit de ahora, que no esta en la huella' "$head|$head" "$($t3[0].entradas.commit)|$($t3[1].entradas.commit)"
  Igual 'y revision.json dice el commit de ahora' $head (Lee-Json $e.Json).commit
  # las candidatas de la unidad entran en la huella
  [void](Pasada $e $true @(($P + 'Suelto.java')))
  $ll = (Llamadas-De $e)
  Igual 'una candidata nueva en una unidad: una llamada mas, la suya' 'revision-Suelto' (@($ll | Select-Object -Skip 3 | ForEach-Object { $_.Id }) -join ',')
  [void](Pasada $e $true @(($P + 'Suelto.java')))
  Igual 'con las mismas candidatas, nada mas' 4 (Llamadas-De $e).Count
  # la plantilla entra en la huella
  $antes = Get-Plantilla 'revision-flujo'
  try {
    $script:Plantillas['revision-flujo'] = $antes + "`nUna linea mas.`n"
    [void](Pasada $e $true @(($P + 'Suelto.java')))
    Igual 'cambiar la plantilla: las dos unidades otra vez' 6 (Llamadas-De $e).Count
  }
  finally { $script:Plantillas['revision-flujo'] = $antes }
}

$Pruebas['20 i) el prompt: tipo, unidad, un FICHERO: por fichero, las candidatas de la unidad, el catalogo, el tope de hallazgos, la salida y la cita maxima'] = {
  $e = Nuevo-Escenario 'i2' $FicherosFlujo
  $u = @(Get-TareasRevision $e.Dir 'main' $true @(($P + 'EscritorUno.java')) $false)
  $pr = Get-Prompt $u[0] '' ''
  Comprueba 'TIPO: revision-flujo' ($pr -match '(?m)^TIPO: revision-flujo$')
  Comprueba 'dice la unidad' ($pr -match 'step paso')
  Comprueba 'una linea FICHERO: por fichero, el step primero' ($pr -match ('(?m)^FICHERO: ' + [regex]::Escape($P) + 'Pasos\.java\r?\n+FICHERO: ' + [regex]::Escape($P) + 'EscritorUno\.java$')) $pr
  Comprueba 'las candidatas de la unidad' ($pr -match ('(?s)andidatas.*' + [regex]::Escape($P) + 'EscritorUno\.java')) $pr
  foreach ($r in @(Get-ReglasRevision)) { Comprueba "el catalogo lleva $($r.id): su texto" ($pr.Contains($r.id + ': ' + $r.que)) }
  Comprueba 'el tope de hallazgos (5)' ($pr -match '\b5\b')
  Comprueba 'la salida: .rescate/tareas/revision-paso.json' ($pr.Contains('.rescate/tareas/revision-paso.json'))
  Comprueba 'la cita maxima (120)' ($pr.Contains('120'))
  Comprueba 'no deja ninguna clave sin sustituir' ($pr -notmatch '\{\{')
  Comprueba 'sin motivo no lleva la seccion de correccion' ($pr -notmatch 'CORRECCI' -and -not $pr.Contains('<!--CORRECCION-->'))
  $suelta = Get-Prompt $u[1] '' ''
  Comprueba 'una unidad sin candidatas dice ninguna' ($suelta -match '(?s)andidatas[^\n]*\n+ninguna')
  $c = Get-Prompt $u[0] '' 'Mas de la mitad de los hallazgos no valen.'
  Comprueba 'con motivo lleva la correccion y el motivo' ($c -match 'CORRECCI' -and $c.Contains('Mas de la mitad de los hallazgos no valen.'))
}

$Pruebas['21 i) reintento: una salida invalida se repite con la correccion y el esfuerzo de reintento; dos fallos dejan la tarea atascada; ConservarAtascadas la respeta'] = {
  $resp = @{ 'revision-paso.json' = 'SIN-SALIDA'; 'revision-paso.reintento.json' = (Salida @((Hallazgo @{ fichero = ($P + 'Pasos.java'); linea = 6; cita = 'public FlatFileItemReader<Recibo> miLector()' }))); 'revision-Suelto.json' = 'SIN-SALIDA'; 'revision-Suelto.reintento.json' = 'SIN-SALIDA' }
  $e = Nuevo-Escenario 'i3' $FicherosFlujo $resp
  $t = @(Pasada $e)
  $ll = (Llamadas-De $e)
  $paso = @($ll | Where-Object { $_.Id -eq 'revision-paso' })
  Igual 'el step: dos llamadas, la segunda con la correccion' '0,1' (($paso | ForEach-Object { $_.Reintento }) -join ',')
  Comprueba 'primero medium y despues high' ($paso[0].Flags -match '--effort=medium' -and $paso[1].Flags -match '--effort=high') (($paso | ForEach-Object { $_.Flags }) -join ' / ')
  Igual 'el step queda hecho, con su hallazgo' 'hecha|1' "$($t[0].estado)|$(@($t[0].resultado.hallazgos).Count)"
  Igual 'la suelta falla las dos veces: atascada' 'atascada|2' "$($t[1].estado)|$($t[1].intentos)"
  Comprueba 'con el motivo de lo que no escribio' ($t[1].motivo -match 'No has escrito el fichero de salida') $t[1].motivo
  $n = (Llamadas-De $e).Count
  $c = @(Pasada $e $true @() $true)
  Igual 'ConservarAtascadas: la atascada no se repite' $n (Llamadas-De $e).Count
  Igual 'y sigue atascada' 'hecha,atascada' (($c | ForEach-Object { $_.estado }) -join ',')
  $d = @(Pasada $e $true @() $false)
  Comprueba 'sin ConservarAtascadas se vuelve a pedir: dos llamadas mas' ((Llamadas-De $e).Count -eq ($n + 2)) "$((Llamadas-De $e).Count)"
}

# ---- (j) revision.json y los textos de consola ----
$Pruebas['22 j) revision.json: su forma, el orden de los hallazgos (unidad, fichero y linea), solo lo comprobado; y los dos textos de consola'] = {
  $resp = @{
    'revision-paso.json' = (Salida @(
        (Hallazgo @{ fichero = ($P + 'EscritorUno.java'); linea = 3; cita = 'ItemWriter<Recibo>'; texto = 'Tercero.' }),
        (Hallazgo @{ regla = 'SB-TRANSACCION'; fichero = ($P + 'Pasos.java'); linea = 13; cita = '.<Recibo, Recibo>chunk(10, tm)'; texto = 'Segundo.' }),
        (Hallazgo @{ regla = 'SB-NOEXISTE'; fichero = ($P + 'Pasos.java'); linea = 1; cita = 'package com.acme.recibos;'; texto = 'Descartado.' }),
        (Hallazgo @{ fichero = ($P + 'Pasos.java'); linea = 6; cita = 'public FlatFileItemReader<Recibo> miLector()'; texto = 'Primero.' })))
    'revision-Suelto.json' = (Salida @((Hallazgo @{ regla = 'SB-CONTEXTO'; fichero = ($P + 'Suelto.java'); linea = 7; cita = 'contexto.put("lista", new ArrayList<Recibo>());'; texto = 'Cuarto.' })))
  }
  $e = Nuevo-Escenario 'j' $FicherosFlujo $resp
  $antes = @(Get-TareasRevision $e.Dir 'main' $true @() $false)
  Igual 'el aviso antes de empezar' 'Revision por flujos: 2 unidades (1 steps y 1 ficheros sueltos), unas 2 llamadas (las ya hechas con la misma huella no se repiten), hasta 4 a la vez.' (Get-AvisoRevision $antes)
  Save-Revision $antes
  $j0 = Lee-Json $e.Json
  Igual 'sin tareas hechas: las cuentas y ningun hallazgo' '2|0|0|0|0' "$($j0.unidades)|$($j0.hechas)|$($j0.atascadas)|$(@($j0.hallazgos).Count)|$($j0.descartados)"
  Igual 'la linea de consola, con todo pendiente' 'Revision por flujos: 0 hechas, 0 atascadas, 2 pendientes; 0 hallazgos (0 descartados por no poder comprobarlos).' (Get-LineaRevision $antes)
  $t = @(Pasada $e)
  $j = Lee-Json $e.Json
  Igual 'las propiedades, en orden' 'commit,todo,unidades,hechas,atascadas,reglas,hallazgos,descartados' (($j.PSObject.Properties.Name) -join ',')
  Igual 'unidades, hechas y atascadas' '2|2|0' "$($j.unidades)|$($j.hechas)|$($j.atascadas)"
  Igual 'todo es un booleano, true' 'True' "$($j.todo)"
  Igual 'las reglas son las del catalogo, con id y titulo' ((@(Get-ReglasRevision) | ForEach-Object { $_.id + '=' + $_.titulo }) -join '|') (($j.reglas | ForEach-Object { $_.id + '=' + $_.titulo }) -join '|')
  Igual 'cada regla lleva solo id y titulo' 'id,titulo' (($j.reglas[0].PSObject.Properties.Name) -join ',')
  Igual 'cuatro hallazgos, en orden de unidad, de fichero dentro de la unidad y de linea' 'Primero.,Segundo.,Tercero.,Cuarto.' (($j.hallazgos | ForEach-Object { $_.texto }) -join ',')
  Igual 'cada hallazgo lleva sus campos, en orden' 'regla,titulo,fichero,linea,cita,texto,unidad,probado' (($j.hallazgos[0].PSObject.Properties.Name) -join ',')
  Igual 'la unidad de cada uno' 'revision-paso,revision-paso,revision-paso,revision-Suelto' (($j.hallazgos | ForEach-Object { $_.unidad }) -join ',')
  Igual 'el titulo es el de la regla' (@(Get-ReglasRevision | Where-Object { $_.id -ceq 'SB-TRANSACCION' })[0].titulo) $j.hallazgos[1].titulo
  Comprueba 'todos probados (true)' (@($j.hallazgos | Where-Object { $_.probado -ne $true }).Count -eq 0)
  Igual 'un descartado (el de la regla que no esta)' 1 $j.descartados
  # lo que no se puede romper: regla del catalogo, fichero de su unidad y una cita que existe con un token de su regla
  $ids = @(Get-ReglasRevision | ForEach-Object { $_.id })
  foreach ($h in @($j.hallazgos)) {
    $unidad = @($t | Where-Object { $_.id -ceq $h.unidad })[0]
    $regla = @(Get-ReglasRevision | Where-Object { $_.id -ceq $h.regla })[0]
    $texto = (Lee $e.Dir $h.fichero) -replace '\s', ''
    $conToken = (@($regla.tokens | Where-Object { $h.cita.Contains($_) }).Count -gt 0)
    Comprueba "hallazgo '$($h.texto)': regla del catalogo, fichero de su unidad, cita que sale en el fichero y con un token de su regla" (($ids -ccontains $h.regla) -and (@($unidad.entradas.ficheros) -ccontains $h.fichero) -and $texto.Contains(($h.cita -replace '\s', '')) -and $conToken)
  }
  Igual 'la linea de consola' 'Revision por flujos: 2 hechas, 0 atascadas, 0 pendientes; 4 hallazgos (1 descartados por no poder comprobarlos).' (Get-LineaRevision $t)
  $otra = @(Get-TareasRevision $e.Dir 'main' $true @() $false)
  Igual 'el aviso de una pasada ya hecha: ninguna llamada' 'Revision por flujos: 2 unidades (1 steps y 1 ficheros sueltos), unas 0 llamadas (las ya hechas con la misma huella no se repiten), hasta 4 a la vez.' (Get-AvisoRevision $otra)
  # sin ninguna tarea
  Save-Revision @()
  $v = Lee-Json $e.Json
  Igual 'sin ninguna unidad: todo a cero y ningun hallazgo' '0|0|0|0|0' "$($v.unidades)|$($v.hechas)|$($v.atascadas)|$(@($v.hallazgos).Count)|$($v.descartados)"
}

# ---- (l) los ficheros nuevos ----
$Pruebas['23 l) revision.ps1: solo funciones, cabecera, ASCII, nada de PowerShell 7 y ninguna funcion repetida; la plantilla y las tres lineas de tareas.ps1'] = {
  $ruta = Join-Path $raiz 'revision.ps1'
  $codigo = [System.IO.File]::ReadAllText($ruta)
  Comprueba 'empieza con su cabecera de ayuda' ($codigo.TrimStart().StartsWith('<#'))
  Comprueba 'nada de PowerShell 7 (??, ?. ni ?[)' ($codigo -notmatch '\?\?|[\w\)\]]\?\.\w|\w\?\[')
  Comprueba 'sin -AsHashtable ni ConvertFrom-Json -Depth' ($codigo -notmatch 'AsHashtable|ConvertFrom-Json[^|\r\n]*-Depth')
  Comprueba 'sin Join-Path de tres rutas' ($codigo -notmatch 'Join-Path\s+[^\s|)]+\s+[^\s|)]+\s+[^\s|)]+\s*\)')
  foreach ($f in @('revision.ps1', 'tests/probar-revision.ps1', 'tests/falsos/c3-copilot.ps1')) {
    $t = [System.IO.File]::ReadAllText((Get-Ruta $raiz $f))
    Comprueba "$f : solo ASCII" ($t -notmatch '[^\x09\x0A\x0D\x20-\x7E]')
  }
  $ast = [System.Management.Automation.Language.Parser]::ParseInput($codigo, [ref]$null, [ref]$null)
  $sueltas = @($ast.EndBlock.Statements | Where-Object { $_ -isnot [System.Management.Automation.Language.FunctionDefinitionAst] -and "$_" -notmatch '^\$Cfg \+= ' })
  Igual 'nada fuera de las funciones (salvo el $Cfg +=)' 0 $sueltas.Count
  $suyas = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Name })
  $deMas = @(Get-ChildItem -LiteralPath $raiz -File -Filter '*.ps1' | Where-Object { $_.Name -cne 'revision.ps1' } | ForEach-Object {
      [regex]::Matches([System.IO.File]::ReadAllText($_.FullName), '(?m)^function ([\w-]+)') | ForEach-Object { $_.Groups[1].Value }
    })
  $repetidas = @($suyas | Where-Object { $deMas -contains $_ })
  Comprueba 'define funciones' ($suyas.Count -gt 0)
  Comprueba 'ninguna esta repetida en otro .ps1 de la raiz' ($repetidas.Count -eq 0) ($repetidas -join ', ')
  foreach ($n in @('Get-ReglasRevision', 'Get-UnidadesRevision', 'Get-TareasRevision', 'Test-Revision', 'Save-Revision', 'Get-LineaRevision', 'Get-AvisoRevision')) {
    Comprueba "define $n" ($suyas -contains $n)
  }
  Comprueba 'no define Restore-ArbolRevision: tras cada ronda lo deshace Invoke-Fase de migracion.ps1' ($suyas -notcontains 'Restore-ArbolRevision')
  # la plantilla
  $md = Get-Ruta $raiz 'tareas/revision-flujo.md'
  Comprueba 'existe tareas/revision-flujo.md' (Test-Path -LiteralPath $md)
  if (Test-Path -LiteralPath $md) {
    $p = [System.IO.File]::ReadAllText($md)
    foreach ($k in @('UNIDAD', 'FICHEROS', 'CANDIDATAS', 'REGLAS', 'HALLAZGOS_MAX', 'SALIDA', 'CITA_MAX')) { Comprueba "la plantilla lleva {{$k}}" ($p.Contains('{{' + $k + '}}')) }
    Comprueba 'lleva TIPO: revision-flujo' ($p -match '(?m)^TIPO: revision-flujo\r?$')
    Comprueba 'y la parte de reintento tras <!--CORRECCION--> con {{MOTIVO}}' ($p -match '(?s)<!--CORRECCION-->.*\{\{MOTIVO\}\}')
    Comprueba 'dice que no se cambia ningun fichero' ($p -match 'No cambies ning')
    Comprueba 'dice que si no hay nada, hallazgos: []' ($p.Contains('"hallazgos": []'))
    Comprueba 'lleva un ejemplo con regla, fichero, linea, cita y texto' ($p -match '"regla": "SB-STEPSCOPE"' -and $p -match '"linea": \d+' -and $p -match '"cita":' -and $p -match '"texto":')
  }
  # tareas.ps1: tres lineas con revision-flujo, una por sitio
  $lineas = @([System.IO.File]::ReadAllLines((Join-Path $raiz 'tareas.ps1')) | Where-Object { $_ -match 'revision-flujo' })
  Igual 'tareas.ps1 nombra revision-flujo en tres lineas' 3 $lineas.Count
  Comprueba 'una en Get-VariablesPrompt' (@($lineas | Where-Object { $_ -match "^\s*'revision-flujo' \{.*Get-VariablesRevision" }).Count -eq 1)
  Comprueba 'una en Test-Salida' (@($lineas | Where-Object { $_ -match "^\s*'revision-flujo' \{ return \(Test-Revision" }).Count -eq 1)
  Comprueba 'y una en Invoke-Ronda, con el esfuerzo de lectura' (@($lineas | Where-Object { $_ -match 'EsfuerzoLectura' }).Count -eq 1)
}

# ---- (m) arreglos de la revision antes de juntarla ----
# Un fichero con dos steps y un @Bean que revisan las dos unidades: lo que dice la IA del bean sale en las dos.
$JavaDoble = @'
package com.acme.recibos;

public class DobleConfig {
  @Bean
  public Step primero(JobRepository repo, PlatformTransactionManager tm) {
    return new StepBuilder("primero", repo).tasklet(uno(), tm).build();
  }

  @Bean
  public Step segundo(JobRepository repo, PlatformTransactionManager tm) {
    return new StepBuilder("segundo", repo).tasklet(dos(), tm).build();
  }

  @Bean
  @StepScope
  public FlatFileItemReader<Recibo> lectorListener() {
    return new FlatFileItemReader<>();
  }
}
'@

$Pruebas['24 m) hallazgos repetidos: un fichero en dos steps da el mismo hallazgo dos veces; revision.json y la consola dejan uno por regla, fichero y linea, el de la primera unidad'] = {
  $f = $P + 'DobleConfig.java'
  $resp = @{
    'revision-primero.json' = (Salida @(
        (Hallazgo @{ fichero = $f; linea = 16; cita = 'public FlatFileItemReader<Recibo> lectorListener()'; texto = 'De primero.' }),
        (Hallazgo @{ regla = 'SB-TRANSACCION'; fichero = $f; linea = 6; cita = '.tasklet(uno(), tm)'; texto = 'Uno.' })))
    'revision-segundo.json' = (Salida @(
        (Hallazgo @{ fichero = $f; linea = 16; cita = 'public FlatFileItemReader<Recibo> lectorListener()'; texto = 'De segundo.' }),
        (Hallazgo @{ regla = 'SB-LISTENER'; fichero = $f; linea = 16; cita = 'lectorListener()'; texto = 'Otra regla en la misma linea.' }),
        (Hallazgo @{ regla = 'SB-TRANSACCION'; fichero = $f; linea = 11; cita = '.tasklet(dos(), tm)'; texto = 'Dos.' })))
  }
  $e = Nuevo-Escenario 'm1' @{ $f = $JavaDoble } $resp
  $t = @(Pasada $e)
  Igual 'las dos unidades, hechas' 'hecha,hecha' (($t | ForEach-Object { $_.estado }) -join ',')
  Igual 'cada una conserva sus hallazgos en su tarea' '2,3' (($t | ForEach-Object { @($_.resultado.hallazgos).Count }) -join ',')
  $j = Lee-Json $e.Json
  Igual 'revision.json: cuatro hallazgos, el repetido una vez' 4 @($j.hallazgos).Count
  Igual 'en orden de unidad y de linea' 'primero:6,primero:16,segundo:11,segundo:16' ((@($j.hallazgos) | ForEach-Object { ($_.unidad -replace '^revision-', '') + ':' + $_.linea }) -join ',')
  Igual 'el repetido es el de la primera unidad' 'De primero.' @($j.hallazgos | Where-Object { $_.linea -eq 16 })[0].texto
  Igual 'la consola cuenta los que quedan' 'Revision por flujos: 2 hechas, 0 atascadas, 0 pendientes; 4 hallazgos (0 descartados por no poder comprobarlos).' (Get-LineaRevision $t)
}

$JavaCadena = @'
package com.acme.recibos;

public class CadenaConfig {
  @Bean
  public Step paso(JobRepository repo, PlatformTransactionManager tm) {
    return new StepBuilder("paso", repo)
        .tasklet(tarea("x)", ')'), tm)
        .listener(new Oido())
        .build();
  }
}
'@

$Pruebas['25 m) un ) dentro de una cadena o de un caracter de un argumento no corta la cadena del step: el listener que viene despues entra en la unidad'] = {
  $e = Nuevo-Escenario 'm2' @{ ($P + 'CadenaConfig.java') = $JavaCadena; ($P + 'Oido.java') = (Clase 'public class Oido implements StepExecutionListener') }
  $u = Unidad-De (Get-UnidadesRevision $e.Dir 'main' $true @()) 'paso'
  Igual 'el step lleva el fichero de Oido' 'CadenaConfig,Oido' (Cortos $u.ficheros)
  Igual 'y tarea queda sin resolver' 'tarea' ($u.sinResolver -join ',')
}

$Pruebas['26 m) los .java de src/test no son unidad ni entran en un step, aunque tengan papel (implements Tasklet, @Configuration)'] = {
  $paso = "  public Step paso(JobRepository repo, PlatformTransactionManager tm) {`n    return new StepBuilder(`"paso`", repo).tasklet(new AlgoTest(), tm).build();`n  }`n"
  $e = Nuevo-Escenario 'm3' @{
    ($P + 'PasoConPrueba.java') = (Clase 'public class PasoConPrueba' $paso)
    'src/test/java/com/acme/recibos/AlgoTest.java' = (Clase 'public class AlgoTest implements Tasklet')
    'src/test/java/com/acme/recibos/PruebaConfig.java' = "package com.acme.recibos;`n`n@Configuration`npublic class PruebaConfig {`n}`n"
  }
  foreach ($todo in @($false, $true)) {
    $u = @(Get-UnidadesRevision $e.Dir 'main' $todo @())
    Igual "Todo=${todo}: ninguna unidad lleva un fichero de src/test" 0 @($u | ForEach-Object { $_.ficheros } | Where-Object { $_ -match 'src/test/' }).Count
    $s = Unidad-De $u 'paso'
    Igual "Todo=${todo}: el step solo lleva su fichero" 'PasoConPrueba' (Cortos $s.ficheros)
    Igual "Todo=${todo}: AlgoTest queda sin resolver" 'AlgoTest' ($s.sinResolver -join ',')
  }
}

Invoke-Banco $Pruebas 'tests/probar-revision.ps1'
