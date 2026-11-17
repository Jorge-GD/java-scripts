<#
probar.ps1 - Banco de pruebas de rescate.ps1.
No necesita Maven ni Copilot: usa los dos programas de mentira de tests/falsos
y repos de juguete que crea en una carpeta temporal. Solo hace falta git.
Vale para Windows PowerShell 5.1 y para PowerShell 7. Solo ASCII a proposito.

  .\tests\probar.ps1                          # todas las pruebas
  .\tests\probar.ps1 -Solo calidad            # las que llevan 'calidad' en el nombre
  .\tests\probar.ps1 -Dir D:\tmp\x -Conservar # deja los repos de juguete para mirarlos
  .\tests\probar.ps1 -Script C:\otra\rescate.ps1   # prueba otra version del script

Sale con 0 si todo pasa y con 1 si algo falla.
#>
param(
  [string]$Dir = '',
  [string]$Script = '',
  [string]$Solo = '',
  [switch]$Conservar
)
$ErrorActionPreference = 'Stop'
$aqui = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $Script) { $Script = Join-Path (Split-Path -Parent $aqui) 'rescate.ps1' }
$Script = (Resolve-Path -LiteralPath $Script).Path
$falsos = Join-Path $aqui 'falsos'
# El mismo PowerShell que ejecuta estas pruebas. Si pwsh esta instalado como
# herramienta de dotnet, el proceso se llama 'dotnet': entonces se busca en el PATH.
$ps = (Get-Process -Id $PID).Path
if ([System.IO.Path]::GetFileNameWithoutExtension($ps) -notmatch '^(pwsh|powershell)') {
  $cmd = Get-Command pwsh -ErrorAction SilentlyContinue
  if (-not $cmd) { $cmd = Get-Command powershell -ErrorAction SilentlyContinue }
  if (-not $cmd) { throw 'No encuentro pwsh ni powershell en el PATH.' }
  $ps = $cmd.Source
}
if (-not $Dir) { $Dir = Join-Path ([System.IO.Path]::GetTempPath()) ('rescate-pruebas-' + [System.Guid]::NewGuid().ToString('N').Substring(0, 8)) }
[void](New-Item -ItemType Directory -Path $Dir -Force)
$Dir = (Resolve-Path -LiteralPath $Dir).Path
$script:Pasan = 0
$script:Fallan = 0

# ============================== UTILIDADES ==============================
function Get-Ruta([string]$Raiz, [string]$Rel) {
  $p = $Raiz
  foreach ($s in $Rel.Split('/')) { if ($s) { $p = Join-Path $p $s } }
  return $p
}

function Escribe([string]$Raiz, [string]$Rel, [string]$Texto) {
  $ruta = Get-Ruta $Raiz $Rel
  $d = Split-Path $ruta -Parent
  if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -Force) }
  [System.IO.File]::WriteAllText($ruta, $Texto)
}

function Lee([string]$Raiz, [string]$Rel) { return [System.IO.File]::ReadAllText((Get-Ruta $Raiz $Rel)) }

function GitEn([string]$D, [string[]]$A) {
  $ErrorActionPreference = 'Continue'
  $o = & git -C $D @A 2>&1 | ForEach-Object { "$_" }
  if ($LASTEXITCODE -ne 0) { throw ('git ' + ($A -join ' ') + ' ha fallado en ' + $D + ': ' + (@($o) -join ' ')) }
  return (@($o) -join "`n")
}

# Lanza rescate.ps1 en otro proceso. Devuelve su codigo de salida y lo que escribe.
function Rescate([string[]]$A, [string]$Guion = '') {
  $ErrorActionPreference = 'Continue'
  $env:RESCATE_FALSO = $Guion
  $pre = @('-NoProfile')
  if ($env:OS -eq 'Windows_NT') { $pre += @('-ExecutionPolicy', 'Bypass') }
  # la linea vacia por la entrada evita que un Read-Host inesperado lo deje colgado
  $o = '' | & $ps @pre -File $Script @A 2>&1 | ForEach-Object { "$_" }
  $c = $LASTEXITCODE
  $env:RESCATE_FALSO = ''
  return [pscustomobject]@{ Codigo = $c; Salida = (@($o) -join "`n") }
}

function Comprueba([string]$Que, [bool]$Ok, [string]$Detalle = '') {
  if ($Ok) {
    $script:Pasan++
    Write-Host "  ok    $Que" -ForegroundColor Green
  }
  else {
    $script:Fallan++
    Write-Host "  FALLA $Que" -ForegroundColor Red
    if ($Detalle) { Write-Host "        $Detalle" }
  }
}

function Igual([string]$Que, $Esperado, $Real) {
  Comprueba $Que ("$Esperado" -ceq "$Real") "esperaba '$Esperado' y hay '$Real'"
}

function Hallazgos([string]$Repo) {
  $p = Get-Ruta $Repo '.rescate/hallazgos.json'
  if (-not (Test-Path -LiteralPath $p)) { return @() }
  $a = [System.IO.File]::ReadAllText($p) | ConvertFrom-Json
  return @($a | ForEach-Object { $_ })
}

function Cuenta($H, [string]$Cat, [string]$Sev = 'error') {
  return @($H | Where-Object { $_.Cat -eq $Cat -and $_.Sev -eq $Sev }).Count
}

# 'regla:metodo' de cada hallazgo de calidad, ordenado y unido con espacios
function Reglas($H) {
  $r = @($H | ForEach-Object {
      if ($_.Detalle -match "^\[([\w-]+)\](?: metodo publico '(\w+)')?") { $Matches[1] + ':' + $Matches[2] } else { '?' }
    } | Sort-Object)
  return ($r -join ' ')
}

function Cola([string]$Texto) { return ((@($Texto -split "`n") | Select-Object -Last 12) -join ' / ') }

# ============================ REPOS DE JUGUETE ============================
$Pom = @'
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>3.2.0</version>
  </parent>
  <groupId>com.acme</groupId>
  <artifactId>batch</artifactId>
  <version>1.0.0</version>
  <properties>
    <java.version>21</java.version>
  </properties>
  <dependencies>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-batch</artifactId>
    </dependency>
  </dependencies>
</project>
'@

function Nueva-Plantilla([string]$Raiz) {
  $b = 'src/main/java/com/acme/plantilla/'
  Escribe $Raiz 'pom.xml' $Pom
  Escribe $Raiz ($b + 'PlantillaApplication.java') @'
package com.acme.plantilla;

import org.springframework.boot.autoconfigure.SpringBootApplication;

/** Arranque del batch de plantilla. */
@SpringBootApplication
public class PlantillaApplication {
    public static void main(String[] args) {
    }
}
'@
  Escribe $Raiz ($b + 'domain/model/Poliza.java') @'
package com.acme.plantilla.domain.model;

/** Poliza que carga el batch. */
public record Poliza(String numero) {
}
'@
  Escribe $Raiz ($b + 'application/ports/output/FicheroPort.java') @'
package com.acme.plantilla.application.ports.output;

import java.util.List;

/** Puerto de salida para leer ficheros de entrada. */
public interface FicheroPort {

    /**
     * Lee las lineas de un fichero.
     *
     * @param nombre nombre del fichero
     * @return las lineas
     */
    List<String> leer(String nombre);
}
'@
  Escribe $Raiz ($b + 'application/usecases/CargarPolizasUseCase.java') @'
package com.acme.plantilla.application.usecases;

import com.acme.plantilla.application.ports.output.FicheroPort;

/** Caso de uso que carga las polizas de un fichero. */
public class CargarPolizasUseCase {

    private final FicheroPort ficheros;

    public CargarPolizasUseCase(FicheroPort ficheros) {
        this.ficheros = ficheros;
    }

    /**
     * Carga las polizas.
     *
     * @param nombre fichero de entrada
     * @return cuantas ha cargado
     */
    public int cargar(String nombre) {
        return ficheros.leer(nombre).size();
    }
}
'@
  Escribe $Raiz ($b + 'infrastructure/adapters/output/file/FicheroLocalAdapter.java') @'
package com.acme.plantilla.infrastructure.adapters.output.file;

import com.acme.plantilla.application.ports.output.FicheroPort;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

/** Adaptador que lee los ficheros del disco local. */
public class FicheroLocalAdapter implements FicheroPort {

    @Override
    public List<String> leer(String nombre) {
        try {
            return Files.readAllLines(Path.of(nombre));
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }
}
'@
  Escribe $Raiz ($b + 'infrastructure/adapters/output/sftp/FicheroSftpAdapter.java') @'
package com.acme.plantilla.infrastructure.adapters.output.sftp;

import com.acme.plantilla.application.ports.output.FicheroPort;
import java.util.List;

/** Adaptador que lee los ficheros de un servidor SFTP. */
public class FicheroSftpAdapter implements FicheroPort {

    @Override
    public List<String> leer(String nombre) {
        return List.of();
    }
}
'@
  Escribe $Raiz ($b + 'infrastructure/config/BatchProperties.java') @'
package com.acme.plantilla.infrastructure.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

/** Propiedades del batch, leidas de application.yml. */
@ConfigurationProperties(prefix = "batch")
public record BatchProperties(String carpeta) {
}
'@
  Escribe $Raiz 'src/main/resources/application.yml' @'
batch:
  carpeta: ${BATCH_CARPETA:/datos}
sftp:
  host: ${SFTP_HOST:}
'@
  Escribe $Raiz 'src/test/java/com/acme/plantilla/CargarPolizasUseCaseTest.java' @'
package com.acme.plantilla;

class CargarPolizasUseCaseTest {
    void carga() {
        assertEquals(1, 1);
    }
}
'@
}

# Repo a medio migrar. Con la plantilla de arriba, el diagnostico da:
# estructura 2, hexagonal 1, ficheros 3, config 2 y calidad 8.
function Nuevo-Repo([string]$Raiz) {
  $b = 'src/main/java/com/acme/life/'
  Escribe $Raiz 'pom.xml' $Pom
  Escribe $Raiz '.gitignore' "local.env`n"
  Escribe $Raiz ($b + 'LifeApplication.java') @'
package com.acme.life;

import org.springframework.boot.autoconfigure.SpringBootApplication;

/** Arranque del batch de vida. */
@SpringBootApplication
public class LifeApplication {
    public static void main(String[] args) {
    }
}
'@
  # estructura: clase suelta en el paquete base
  Escribe $Raiz ($b + 'Suelta.java') @'
package com.acme.life;

/** Clase que se quedo en el paquete base. */
public class Suelta {
}
'@
  # estructura: paquete fuera de las capas. calidad: 4 errores
  Escribe $Raiz ($b + 'service/PolizaService.java') @'
package com.acme.life.service;

import org.springframework.beans.factory.annotation.Autowired;

public class PolizaService {

    @Autowired
    private Suelta suelta;

    public int procesar(String nombre) {
        System.out.println("procesando " + nombre);
        return 1;
    }

    public String getNombre() {
        return "x";
    }
}
'@
  # ficheros: acceso directo a ficheros locales fuera del adaptador
  Escribe $Raiz ($b + 'application/usecases/LeerFichero.java') @'
package com.acme.life.application.usecases;

import java.io.File;

/** Caso de uso que lee un fichero de entrada. */
public class LeerFichero {

    /**
     * Dice si el fichero existe.
     *
     * @param ruta ruta del fichero
     * @return true si existe
     */
    public boolean existe(String ruta) {
        return new File(ruta).exists();
    }
}
'@
  # hexagonal: el dominio depende de Spring
  Escribe $Raiz ($b + 'domain/model/Cliente.java') @'
package com.acme.life.domain.model;

import org.springframework.stereotype.Component;

/** Cliente de una poliza. */
@Component
public class Cliente {
}
'@
  # calidad: 4 errores y 2 avisos, y varios casos que NO deben contar
  Escribe $Raiz ($b + 'application/usecases/CalidadMuestra.java') @'
package com.acme.life.application.usecases;

import java.util.Date;
import java.util.List;

/**
 * Muestra para las reglas de calidad.
 */
public class CalidadMuestra implements Comparable<CalidadMuestra> {

    private final List<String> datos;

    public CalidadMuestra(List<String> datos) {
        this.datos = datos;
    }

    /** Documentado: no cuenta. */
    public int documentado() {
        return 1;
    }

    @Override
    public String toString() {
        return "muestra";
    }

    @Override
    public int compareTo(CalidadMuestra otra) {
        return 0;
    }

    public boolean isListo() {
        return true;
    }

    public void sinDocumentar(Object o) {
        try {
            String s = "System.out.println(no cuenta: es un literal)";
            // System.out.println("tampoco cuenta: es un comentario");
            Integer n = new Integer(3);
            if (o instanceof String) {
                String t = (String) o;
            }
        } catch (Exception e) {
        }
        try {
            datos.size();
        } catch (RuntimeException e) {
            // se ignora a proposito
        }
    }

    public <T> List<T> generico(List<T> entrada,
                                Date desde) {
        return entrada;
    }
}
'@
  # config: palabra de la configuracion antigua, y falta el bloque sftp
  Escribe $Raiz 'src/main/resources/application.yml' @'
life:
  inventory: legado
'@
  Escribe $Raiz 'src/test/java/com/acme/life/PolizaServiceTest.java' @'
package com.acme.life;

class PolizaServiceTest {
    void procesa() {
        assertEquals(1, 1);
    }
}
'@
}

function Nuevo-Escenario([string]$Nombre) {
  $raiz = Join-Path $Dir $Nombre
  if (Test-Path -LiteralPath $raiz) { Remove-Item -LiteralPath $raiz -Recurse -Force }
  $pl = Join-Path $raiz 'plantilla'
  $repo = Join-Path $raiz 'batch-life'
  Nueva-Plantilla $pl
  Nuevo-Repo $repo
  foreach ($d in @($pl, $repo)) {
    [void](GitEn $d @('init', '-q'))
    [void](GitEn $d @('symbolic-ref', 'HEAD', 'refs/heads/main'))
    [void](GitEn $d @('config', 'user.name', 'Pruebas'))
    [void](GitEn $d @('config', 'user.email', 'pruebas@example.invalid'))
    [void](GitEn $d @('config', 'commit.gpgsign', 'false'))
    [void](GitEn $d @('config', 'core.autocrlf', 'false'))
    [void](GitEn $d @('add', '-A'))
    [void](GitEn $d @('commit', '-q', '-m', 'inicial'))
  }
  # ajustes del repo: Maven y Copilot de mentira (despues del commit: .rescate no se versiona)
  $cfg = [pscustomobject]@{ CopilotExe = (Join-Path $falsos 'copilot.ps1'); MvnExe = (Join-Path $falsos 'mvn.ps1') }
  Escribe $repo '.rescate/config.json' (ConvertTo-Json -InputObject $cfg)
  return [pscustomobject]@{ Plantilla = $pl; Repo = $repo; Wt = ($repo + '-rescate') }
}

# ================================ PRUEBAS ================================
$Pruebas = [ordered]@{}

$Pruebas['cuentas: el diagnostico cuenta lo de siempre y no toca nada'] = {
  $e = Nuevo-Escenario 'cuentas'
  $r = Rescate @('-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-SinBuild')
  Igual 'sale con 0' 0 $r.Codigo
  $h = Hallazgos $e.Repo
  Igual 'build' 0 (Cuenta $h 'build')
  Igual 'estructura' 2 (Cuenta $h 'estructura')
  Igual 'hexagonal' 1 (Cuenta $h 'hexagonal')
  Igual 'ficheros' 3 (Cuenta $h 'ficheros')
  Igual 'config' 2 (Cuenta $h 'config')
  Igual 'git no ve cambios (.rescate esta excluido)' '' (GitEn $e.Repo @('status', '--porcelain'))
  Comprueba 'el diagnostico no crea worktree' (-not (Test-Path -LiteralPath $e.Wt))
}

$Pruebas['build: con el Maven de mentira compila y pasan los tests'] = {
  $e = Nuevo-Escenario 'build'
  $r = Rescate @('-Repo', $e.Repo, '-Plantilla', $e.Plantilla)
  Igual 'sale con 0' 0 $r.Codigo
  Comprueba 'dice compila SI y tests OK' ($r.Salida -match 'compila: SI \| tests: OK') (Cola $r.Salida)
  Igual 'git no ve cambios (target esta excluido)' '' (GitEn $e.Repo @('status', '--porcelain'))
}

$Pruebas['calidad: Javadoc y practicas, con sus exenciones'] = {
  $e = Nuevo-Escenario 'calidad'
  [void](Rescate @('-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-SinBuild'))
  $cal = @(Hallazgos $e.Repo | Where-Object { $_.Cat -eq 'calidad' })
  Igual 'errores de calidad en total' 8 (Cuenta $cal 'calidad')
  $m = @($cal | Where-Object { $_.Fichero -like '*CalidadMuestra.java' })
  Igual 'muestra: errores' 'catch-vacio: envoltorio-new: javadoc-metodo:generico javadoc-metodo:sinDocumentar' (Reglas @($m | Where-Object { $_.Sev -eq 'error' }))
  Igual 'muestra: avisos' 'fecha-antigua: instanceof-cast:' (Reglas @($m | Where-Object { $_.Sev -eq 'aviso' }))
  $p = @($cal | Where-Object { $_.Fichero -like '*PolizaService.java' })
  Igual 'servicio: errores' 'inyeccion-campo: javadoc-metodo:procesar javadoc-tipo: salida-consola:' (Reglas @($p | Where-Object { $_.Sev -eq 'error' }))
  $tipo = @($p | Where-Object { $_.Detalle -match '^\[javadoc-tipo\]' })
  Igual 'servicio: linea de la clase' 5 $tipo[0].Linea
  $sal = @($p | Where-Object { $_.Detalle -match '^\[salida-consola\]' })
  Igual 'servicio: linea del System.out' 11 $sal[0].Linea
  $otros = @($cal | Where-Object { $_.Fichero -notlike '*CalidadMuestra.java' -and $_.Fichero -notlike '*PolizaService.java' })
  Igual 'el resto de clases, documentadas, no dan nada' 0 $otros.Count
}

$Pruebas['calidad: la plantilla manda, salvo en el Javadoc'] = {
  $e = Nuevo-Escenario 'calidad-plantilla'
  # la plantilla tambien escribe por consola y tiene un metodo sin Javadoc
  $f = 'src/main/java/com/acme/plantilla/application/usecases/CargarPolizasUseCase.java'
  $t = (Lee $e.Plantilla $f) -replace '(?s)\}\s*$', "`n    public void avisar() {`n        System.out.println(`"aviso`");`n    }`n}`n"
  Escribe $e.Plantilla $f $t
  [void](GitEn $e.Plantilla @('commit', '-q', '-a', '-m', 'consola'))
  [void](Rescate @('-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-SinBuild'))
  $p = @(Hallazgos $e.Repo | Where-Object { $_.Cat -eq 'calidad' -and $_.Fichero -like '*PolizaService.java' })
  Igual 'System.out baja a aviso' 'salida-consola:' (Reglas @($p | Where-Object { $_.Sev -eq 'aviso' }))
  Igual 'el Javadoc se sigue exigiendo' 'inyeccion-campo: javadoc-metodo:procesar javadoc-tipo:' (Reglas @($p | Where-Object { $_.Sev -eq 'error' }))
}

$Pruebas['worktree: el fix trabaja aparte y la carpeta original no se toca'] = {
  $e = Nuevo-Escenario 'worktree'
  [void](Rescate @('-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-SinBuild'))
  # cambios sin commit en la carpeta original: uno en un fichero seguido, uno nuevo y uno ignorado
  $suelta = 'src/main/java/com/acme/life/Suelta.java'
  Escribe $e.Repo $suelta ((Lee $e.Repo $suelta) + "// cambio sin commit`n")
  Escribe $e.Repo 'notas/pendiente.txt' 'sin seguimiento'
  Escribe $e.Repo 'local.env' 'CLAVE=x'
  $estado = GitEn $e.Repo @('status', '--porcelain')
  $head = GitEn $e.Repo @('rev-parse', 'HEAD')

  $r = Rescate @('-Modo', 'fix', '-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-Paso', 'estructura', '-SinPlan', '-Auto', '-Si')
  Igual 'el fix sale con 0' 0 $r.Codigo
  Comprueba 'existe el worktree al lado' (Test-Path -LiteralPath (Join-Path $e.Wt '.git')) (Cola $r.Salida)
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { return }
  Igual 'la original sigue en su rama' 'main' (GitEn $e.Repo @('rev-parse', '--abbrev-ref', 'HEAD'))
  Igual 'la original sigue en su commit' $head (GitEn $e.Repo @('rev-parse', 'HEAD'))
  Igual 'la original conserva sus cambios sin commit' $estado (GitEn $e.Repo @('status', '--porcelain'))
  Comprueba 'el worktree esta en una rama rescate/' ((GitEn $e.Wt @('rev-parse', '--abbrev-ref', 'HEAD')).StartsWith('rescate/main-'))
  $log = GitEn $e.Wt @('log', '--format=%s')
  Comprueba 'hay commit foto' ($log -match 'rescate: foto del estado antes de empezar') $log
  Comprueba 'hay commit del lote' ($log -match 'rescate\(estructura\): lote 1, hallazgos 2 a 0') $log
  Comprueba 'la foto lleva el cambio del fichero seguido' ((Lee $e.Wt 'src/main/java/com/acme/life/application/usecases/Suelta.java') -match 'cambio sin commit')
  Comprueba 'la foto lleva el fichero nuevo' (Test-Path -LiteralPath (Get-Ruta $e.Wt 'notas/pendiente.txt'))
  Comprueba 'lo ignorado no viaja' (-not (Test-Path -LiteralPath (Get-Ruta $e.Wt 'local.env')))
  Comprueba 'y el script avisa de lo ignorado' ($r.Salida -match 'local\.env')
  Comprueba 'dice como traer los cambios' ($r.Salida -match 'git merge rescate/main-')
  $hw = Hallazgos $e.Wt
  Igual 'estructura queda a 0 en el worktree' 0 (Cuenta $hw 'estructura')
  Igual 'la calidad no empeora al mover' 8 (Cuenta $hw 'calidad')
  Igual 'el worktree queda limpio' '' (GitEn $e.Wt @('status', '--porcelain'))

  # con el worktree creado, el diagnostico trabaja en el
  $r2 = Rescate @('-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-SinBuild')
  Comprueba 'el diagnostico dice que usa el worktree' ($r2.Salida -match 'Carpeta de trabajo')
  $r3 = Rescate @('-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-SinBuild', '-SinWorktree')
  Igual '-SinWorktree mira la original' 2 (Cuenta (Hallazgos $e.Repo) 'estructura')
  Igual 'y solo hay un worktree de rescate' 1 (@((GitEn $e.Repo @('branch', '--list', 'rescate/*')) -split "`n" | Where-Object { $_ }).Count)

  # deshacer quita el lote del worktree, no la foto
  $r4 = Rescate @('-Modo', 'deshacer', '-Repo', $e.Repo, '-Si')
  $log2 = GitEn $e.Wt @('log', '--format=%s')
  Comprueba 'deshacer quita el commit del lote' ($log2 -notmatch 'rescate\(estructura\)') $log2
  Comprueba 'deshacer conserva la foto' ($log2 -match 'rescate: foto')
  Igual 'la original sigue igual despues de todo' $estado (GitEn $e.Repo @('status', '--porcelain'))
}

$Pruebas['plan: revision previa y calidad exigida al codigo nuevo'] = {
  $e = Nuevo-Escenario 'plan'
  $r = Rescate @('-Modo', 'fix', '-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-Paso', 'hexagonal', '-Auto', '-Si', '-Modelo', 'modelo-x', '-Esfuerzo', 'medium', '-EsfuerzoPlan', 'high') 'sin-javadoc'
  Igual 'el fix sale con 0' 0 $r.Codigo
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  Comprueba 'el plan esta escrito' (Test-Path -LiteralPath (Get-Ruta $e.Wt '.rescate/plan-hexagonal.md'))
  Comprueba 'el primer intento no pasa por calidad' ($r.Salida -match 'anade hallazgos de calidad \(8 -> 10\)') (Cola $r.Salida)
  Comprueba 'el lote pasa al corregirlo' ($r.Salida -match "Lote 1 OK: 'hexagonal' 1 -> 0") (Cola $r.Salida)
  $ll = @((Lee $e.Wt '.rescate/llamadas.log') -split "`n" | Where-Object { $_ })
  Igual 'tres llamadas a Copilot: plan, lote y correccion' 3 $ll.Count
  if ($ll.Count -eq 3) {
    Comprueba 'la primera es la revision previa' ($ll[0] -match 'revision previa')
    Comprueba 'el lote recibe el plan' ($ll[1] -match 'correccion=False \| plan=True')
    Comprueba 'el reintento es una correccion' ($ll[2] -match 'correccion=True')
    Comprueba 'la revision previa va con su modelo y su esfuerzo' ($ll[0].TrimEnd().EndsWith('| --model=modelo-x --effort=high')) $ll[0]
    Comprueba 'los lotes van con el esfuerzo de los lotes' ($ll[1].TrimEnd().EndsWith('| --model=modelo-x --effort=medium')) $ll[1]
  }
  $prompt = Lee $e.Wt '.rescate/prompt.md'
  Comprueba 'la correccion senala el fichero nuevo sin Javadoc' ($prompt -match 'ClientePort\.java:\d+ - \[javadoc-tipo\]')
  Comprueba 'el prompt lleva las reglas de calidad' ($prompt -match '## Calidad del codigo que escribas')
  $hw = Hallazgos $e.Wt
  Igual 'hexagonal queda a 0' 0 (Cuenta $hw 'hexagonal')
  Igual 'la calidad no ha subido' 8 (Cuenta $hw 'calidad')
  Comprueba 'el puerto nuevo lleva Javadoc' ((Lee $e.Wt 'src/main/java/com/acme/life/application/ports/output/ClientePort.java') -match '/\*\*')
}

$Pruebas['plan: la revision previa no puede tocar codigo'] = {
  $e = Nuevo-Escenario 'plan-lectura'
  $r = Rescate @('-Modo', 'plan', '-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-Paso', 'ficheros', '-SinBuild', '-Si') 'plan-toca-codigo'
  Igual 'sale con 0' 0 $r.Codigo
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  Comprueba 'el plan esta escrito' (Test-Path -LiteralPath (Get-Ruta $e.Wt '.rescate/plan-ficheros.md'))
  Comprueba 'avisa de que lo ha deshecho' ($r.Salida -match 'lo he deshecho') (Cola $r.Salida)
  Igual 'el worktree queda limpio' '' (GitEn $e.Wt @('status', '--porcelain'))
  Igual 'no hay commits nuevos' 'inicial' (GitEn $e.Wt @('log', '--format=%s'))
}

$Pruebas['puertas: un lote que no cambia nada se deshace y queda apuntado'] = {
  $e = Nuevo-Escenario 'nada'
  # sin -Modelo ni -Esfuerzo no se pasa ninguno de los dos: manda lo que tenga Copilot
  $r = Rescate @('-Modo', 'fix', '-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-Paso', 'estructura', '-SinPlan', '-Auto', '-Si', '-MaxIntentos', '1') 'nada'
  Igual 'sale con 2' 2 $r.Codigo
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  Comprueba 'apunta los atascados' (Test-Path -LiteralPath (Get-Ruta $e.Wt '.rescate/atascados.md'))
  Igual 'no hay commits nuevos' 'inicial' (GitEn $e.Wt @('log', '--format=%s'))
  Igual 'el worktree queda limpio' '' (GitEn $e.Wt @('status', '--porcelain'))
  $ll = Lee $e.Wt '.rescate/llamadas.log'
  Comprueba 'lo intenta con el lote entero y despues fichero a fichero' (@($ll -split "`n" | Where-Object { $_ }).Count -eq 3) $ll
  Comprueba 'a Copilot no le llega ni modelo ni esfuerzo' ($ll -notmatch '--(model|effort)=') $ll
}

$Pruebas['puertas: si la IA toca la plantilla, se para y se deshace'] = {
  $e = Nuevo-Escenario 'toca-plantilla'
  $r = Rescate @('-Modo', 'fix', '-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-Paso', 'estructura', '-SinPlan', '-Auto', '-Si') 'toca-plantilla'
  Igual 'sale con 4' 4 $r.Codigo
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  Igual 'no hay commits nuevos' 'inicial' (GitEn $e.Wt @('log', '--format=%s'))
  Igual 'el worktree queda limpio' '' (GitEn $e.Wt @('status', '--porcelain'))
}

$Pruebas['sinworktree: -SinWorktree arregla en la misma carpeta, como antes'] = {
  $e = Nuevo-Escenario 'sinworktree'
  $r = Rescate @('-Modo', 'fix', '-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-Paso', 'estructura', '-SinPlan', '-SinWorktree', '-Auto', '-Si')
  Igual 'sale con 0' 0 $r.Codigo
  Comprueba 'no crea worktree' (-not (Test-Path -LiteralPath $e.Wt))
  Comprueba 'la carpeta pasa a una rama rescate/' ((GitEn $e.Repo @('rev-parse', '--abbrev-ref', 'HEAD')).StartsWith('rescate/main-')) (Cola $r.Salida)
  Igual 'estructura queda a 0' 0 (Cuenta (Hallazgos $e.Repo) 'estructura')
}

# ================================ LANZADOR ================================
Write-Host ('Script: ' + $Script)
Write-Host ('Carpeta de pruebas: ' + $Dir)
foreach ($nombre in $Pruebas.Keys) {
  if ($Solo -and $nombre -notlike ('*' + $Solo + '*')) { continue }
  Write-Host ''
  Write-Host $nombre
  try { & $Pruebas[$nombre] }
  catch { Comprueba 'la prueba termina sin excepcion' $false ($_.Exception.Message) }
}
Write-Host ''
if ($script:Fallan -eq 0) { Write-Host "TODO BIEN: $($script:Pasan) comprobaciones." -ForegroundColor Green }
else { Write-Host "FALLAN $($script:Fallan) de $($script:Pasan + $script:Fallan) comprobaciones." -ForegroundColor Red }
if (-not $Conservar) {
  try { Remove-Item -LiteralPath $Dir -Recurse -Force } catch { Write-Host ('No pude borrar ' + $Dir + ': ' + $_.Exception.Message) }
}
if ($script:Fallan -gt 0) { exit 1 }
exit 0
