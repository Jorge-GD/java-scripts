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
. (Join-Path $aqui 'comun-banco.ps1')

# Ningun lanzamiento lee el ajustes.json de quien pasa el banco (en su equipo apunta al Copilot de verdad):
# RESCATE_HOME va a una carpeta de aqui, vacia. Las pruebas de ajustes.json ponen la suya.
$CasaVacia = Join-Path $Dir 'casa-vacia'
[void](New-Item -ItemType Directory -Path $CasaVacia -Force)
$env:RESCATE_HOME = $CasaVacia

# ============================== UTILIDADES ==============================
# Lanza rescate.ps1 en otro proceso (Lanzar esta en comun-banco.ps1).
function Rescate([string[]]$A, [string]$Guion = '') { return Lanzar $Script $A $Guion }

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
  foreach ($d in @($pl, $repo)) { Inicia-Repo $d }
  # ajustes del repo: Maven y Copilot de mentira (despues del commit: .rescate no se versiona)
  $e = [pscustomobject]@{ Plantilla = $pl; Repo = $repo; Wt = ($repo + '-rescate') }
  Pon-Config $e @{}
  return $e
}

# Nombres (ordenados y unidos con espacios) de los jobs que saca '-Modo pre -SinIA'
# de un original con esos ficheros (ruta -> texto).
function Jobs-Del-Original([string]$Nombre, $Ficheros) {
  $e = Nuevo-Escenario $Nombre
  $orig = Join-Path (Join-Path $Dir $Nombre) 'original'
  foreach ($ruta in $Ficheros.Keys) { Escribe $orig $ruta $Ficheros[$ruta] }
  $r = Rescate @('-Modo', 'pre', '-Repo', $e.Repo, '-Legacy', $orig, '-SinIA')
  Igual 'el pre sale con 0' 0 $r.Codigo
  $c = (Lee $e.Repo '.rescate/contrato.json') | ConvertFrom-Json
  return (@($c.jobs | ForEach-Object { $_.nombre } | Sort-Object) -join ' ')
}

# Prompt de un lote de un solo fichero (el segundo pendiente) del paso 'estructura',
# con este plan escrito a mano (el plan se hace antes con el Copilot de mentira).
function Prompt-Con-Plan([string]$Nombre, [string]$Plan) {
  $e = Nuevo-Escenario $Nombre
  [void](Rescate @('-Modo', 'plan', '-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-Paso', 'estructura', '-SinBuild', '-Si'))
  Escribe $e.Wt '.rescate/plan-estructura.md' $Plan
  [void](Rescate @('-Modo', 'fix', '-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-Paso', 'estructura', '-Lote', '1', '-Saltar', '1', '-Auto', '-Si', '-MaxIntentos', '1'))
  return (Lee $e.Wt '.rescate/prompt.md')
}

# Las lineas del prompt que van citadas ('> '), sin la cita, unidas con saltos de linea.
function Citado([string]$Prompt) {
  return (@($Prompt -split "`r?`n" | Where-Object { $_.StartsWith('> ') } | ForEach-Object { $_.Substring(2) }) -join "`n")
}

# Nombre de la clase del primer hallazgo del lote de un prompt.
function Clase-Del-Lote([string]$Prompt) {
  $m = [regex]::Match($Prompt, '(?m)^## Hallazgos de este lote[^\n]*\n- (\S+?)(?::\d+)? - ')
  return [System.IO.Path]::GetFileNameWithoutExtension($m.Groups[1].Value)
}

# La orden de Maven que lleva el prompt del lote de un solo fichero de 'estructura' (sin plan).
function Maven-Del-Prompt($E) {
  [void](Rescate @('-Modo', 'fix', '-Repo', $E.Repo, '-Plantilla', $E.Plantilla, '-Paso', 'estructura', '-SinPlan', '-Lote', '1', '-Saltar', '1', '-Auto', '-Si', '-MaxIntentos', '1'))
  return ([regex]::Match((Lee $E.Wt '.rescate/prompt.md'), '(?m)^- Ejecuta: (.+?) -q -B')).Groups[1].Value
}

# Repo de juguete con estos ficheros de src/main/resources (nombre -> texto) ya en un commit.
function Escenario-Con-Recursos([string]$Nombre, $Ficheros) {
  $e = Nuevo-Escenario $Nombre
  foreach ($f in $Ficheros.Keys) {
    Escribe $e.Repo ('src/main/resources/' + $f) $Ficheros[$f]
    [void](GitEn $e.Repo @('add', '--', ('src/main/resources/' + $f)))
  }
  [void](GitEn $e.Repo @('commit', '-q', '-m', 'recursos'))
  return $e
}

# Diagnostica el repo y devuelve lo que ha salido por consola y los hallazgos de secretos en claro.
function Diagnostica-Secretos($E) {
  $r = Rescate @('-Repo', $E.Repo, '-Plantilla', $E.Plantilla, '-SinBuild')
  $h = @(Hallazgos $E.Repo | Where-Object { $_.Cat -eq 'config' -and $_.Detalle -like 'secreto escrito en claro*' })
  return [pscustomobject]@{ R = $r; H = $h }
}

# Todo lo que han escrito el script y la consola en una carpeta .rescate de este repo o worktree.
function Lo-Que-Sale([string]$Raiz, [string]$Consola) {
  $t = $Consola
  foreach ($f in @(Get-ChildItem -LiteralPath (Get-Ruta $Raiz '.rescate') -Recurse -File)) { $t += "`n" + [System.IO.File]::ReadAllText($f.FullName) }
  return $t
}

# Plan de tres ficheros: dos con hallazgos en 'estructura' y un tercero (Cliente) que no.
$PlanTres = @'
# Plan del paso 'estructura'

## Piezas comunes
- `com.acme.life.application.ports.output.PagoPort` PIEZA-COMUN-MARCA: puerto que comparten los ficheros

## Ficheros
- `src/main/java/com/acme/life/Suelta.java` -> mover a usecases | destino: application.usecases | riesgo: bajo
- `src/main/java/com/acme/life/service/PolizaService.java` -> mover a usecases | destino: application.usecases | riesgo: bajo
- `src/main/java/com/acme/life/domain/model/Cliente.java` -> dejarlo donde esta | destino: - | riesgo: bajo

## Orden
ORDEN-MARCA: primero lo que otros necesitan.

## Dudas
DUDAS-MARCA: ninguna de momento.
'@

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
  # las llamadas de los lotes (las de consejo y reflexion van aparte, con su esfuerzo)
  $ll = (@((Lee $e.Wt '.rescate/llamadas.log') -split "`n" | Where-Object { $_ -match "paso 'estructura'" }) -join "`n")
  Comprueba 'lo intenta con el lote entero y despues fichero a fichero' (@($ll -split "`n" | Where-Object { $_ }).Count -eq 3) $ll
  # el primer intento va sin modelo ni esfuerzo; los escalones, solo con el esfuerzo de los reintentos (high, el defecto), sin modelo
  $fl = @($ll -split "`n" | Where-Object { $_ })
  Comprueba 'al lote entero no le llega ni modelo ni esfuerzo, y a cada reintento solo el esfuerzo high' ($fl.Count -eq 3 -and $fl[0] -notmatch '--(model|effort)=' -and @($fl | Select-Object -Skip 1 | Where-Object { $_ -match '--effort=high' -and $_ -notmatch '--model=' }).Count -eq 2) $ll
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

$Pruebas['jobs: un job dentro de un comentario no es un job'] = {
  $java = @'
package com.acme.old;

public class Cargas {
    // jobBuilderFactory.get("jobEnLinea").start(paso).build();
    /*
     * new JobBuilder("jobEnBloque", repo).start(paso).build();
     */
    /** Antes: jobBuilderFactory.get("jobEnJavadoc"). */
    public Job real() {
        return jobBuilderFactory.get("jobReal").start(paso).build();
    }
}
'@
  $xml = @'
<beans>
  <!-- <job id="jobEnXml"><step id="uno"/></job> -->
  <bean id="otra" class="com.acme.Otra"/>
</beans>
'@
  $f = @{ 'src/main/java/com/acme/old/Cargas.java' = $java; 'src/main/resources/jobs.xml' = $xml }
  Igual 'el contrato trae solo el job de verdad' 'jobReal' (Jobs-Del-Original 'jobs-comentarios' $f)
}

$Pruebas['jobs: el comentario detras de un job no lo cuenta'] = {
  $java = @'
package com.acme.old;

public class Cargas {
    public Job carga() {
        return jobBuilderFactory.get("cargaJob").start(paso).build(); // antes: jobBuilderFactory.get("reprocesoJob")
    }
}
'@
  Igual 'sale cargaJob y no reprocesoJob' 'cargaJob' (Jobs-Del-Original 'jobs-detras' @{ 'src/main/java/com/acme/old/Cargas.java' = $java })
}

$Pruebas['jobs: un // dentro de una cadena no es un comentario'] = {
  $java = @'
package com.acme.old;

public class Cargas {
    private static final String URL = "http://servidor/api"; Job a = jobBuilderFactory.get("jobMismaLinea").build();
    private static final String RARA = "a\"//b"; Job b = new JobBuilder("jobTrasEscape", repo).build();
    public Job c() {
        return jobBuilderFactory.get("jobDespues").start(paso).build();
    }
}
'@
  Igual 'salen los tres jobs, los de detras de la cadena tambien' 'jobDespues jobMismaLinea jobTrasEscape' (Jobs-Del-Original 'jobs-cadena' @{ 'src/main/java/com/acme/old/Cargas.java' = $java })
}

$Pruebas['prompt: el lote solo lleva su parte del plan'] = {
  $p = Prompt-Con-Plan 'prompt-parte' $PlanTres
  $c = Citado $p
  $suya = Clase-Del-Lote $p
  Comprueba 'el lote es de un fichero de los dos con hallazgos' (@('Suelta', 'PolizaService') -contains $suya) "clase del lote: '$suya'"
  Comprueba 'el titulo dice que es solo la parte del lote' $p.Contains('## Plan aprobado de este paso (solo la parte de este lote)')
  Comprueba 'lleva la frase de los demas ficheros' $p.Contains('El plan completo tiene mas ficheros. Los hara otro lote: no los muevas ni los cambies. Toca otro fichero solo si hace falta para que compile (su import o la llamada que cambia).')
  Comprueba 'cita la primera linea del plan' $c.Contains("# Plan del paso 'estructura'")
  Comprueba 'cita las piezas comunes' ($c.Contains('## Piezas comunes') -and $c.Contains('PIEZA-COMUN-MARCA'))
  Comprueba 'cita la linea de su fichero' ($c -match ('(?m)^- `[^`]*' + $suya + '\.java` -> '))
  foreach ($otra in @(@('Suelta', 'PolizaService', 'Cliente') | Where-Object { $_ -ne $suya })) {
    Comprueba "no cita la linea de $otra" ($c -notmatch ('(?<![\w])' + $otra + '(?![\w])'))
  }
  Comprueba 'no cita ## Orden ni su texto' (-not $p.Contains('ORDEN-MARCA') -and -not $p.Contains('## Orden'))
  Comprueba 'no cita ## Dudas ni su texto' (-not $p.Contains('DUDAS-MARCA') -and -not $p.Contains('## Dudas'))
}

$Pruebas['prompt: un lote que el plan no nombra lo dice'] = {
  # El plan solo nombra a Cliente en '## Ficheros'; Suelta y PolizaService salen en el texto de '## Orden'
  # (por eso el script no rehace el plan) y no hay linea suya que citar. Los titulos, con otras
  # mayusculas y espacios de mas.
  $plan = @'
# Plan del paso 'estructura'

##   piezas   COMUNES  
ninguna PIEZA-COMUN-MARCA

##  FICHEROS
- `src/main/java/com/acme/life/domain/model/Cliente.java` -> dejarlo donde esta | destino: - | riesgo: bajo

## Orden
ORDEN-MARCA: primero Suelta y despues PolizaService.

## Dudas
ninguna
'@
  $p = Prompt-Con-Plan 'prompt-sin-nombrar' $plan
  $c = Citado $p
  Comprueba 'cita las piezas comunes' $c.Contains('PIEZA-COMUN-MARCA')
  Comprueba 'dice que el plan no nombra los ficheros del lote' $c.Contains('(el plan no nombra los ficheros de este lote: aplica el mismo criterio que con los demas)')
  Comprueba 'no cita la linea de otro fichero' ($c -notmatch 'Cliente')
  Comprueba 'no cita ## Orden' (-not $p.Contains('ORDEN-MARCA'))
}

$Pruebas['prompt: un plan sin ## Ficheros se cita entero'] = {
  $plan = @'
# Plan del paso 'estructura'

## Piezas comunes
ninguna PIEZA-COMUN-MARCA

## Cambios
- `src/main/java/com/acme/life/Suelta.java` -> mover a usecases
- `src/main/java/com/acme/life/service/PolizaService.java` -> mover a usecases

## Orden
ORDEN-MARCA: el de la lista.

## Dudas
DUDAS-MARCA: ninguna
'@
  $p = Prompt-Con-Plan 'prompt-entero' $plan
  Igual 'el plan va citado tal cual' ($plan.Trim() -replace "`r", '') (Citado $p)
}

# Lo que tiene que citar el prompt de un lote cuyo plan lleva estos titulos: las piezas comunes y
# solo la linea de su fichero, con los titulos tal como los escribio el plan.
function Comprueba-Parte-Del-Plan([string]$P, [string]$TituloPiezas, [string]$TituloFicheros) {
  $c = Citado $P
  $suya = Clase-Del-Lote $P
  Comprueba 'el lote es de un fichero de los dos con hallazgos' (@('Suelta', 'PolizaService') -contains $suya) "clase del lote: '$suya'"
  Comprueba 'cita el titulo de las piezas comunes como lo escribio el plan' $c.Contains($TituloPiezas)
  Comprueba 'cita las piezas comunes' $c.Contains('PIEZA-COMUN-MARCA')
  Comprueba 'cita el titulo de los ficheros como lo escribio el plan' $c.Contains($TituloFicheros)
  Comprueba 'cita la linea de su fichero' ($c -match ('(?m)^- `[^`]*' + $suya + '\.java` -> '))
  foreach ($otra in @(@('Suelta', 'PolizaService', 'Cliente') | Where-Object { $_ -ne $suya })) {
    Comprueba "no cita la linea de $otra" ($c -notmatch ('(?<![\w])' + $otra + '(?![\w])'))
  }
  Comprueba 'no cita ## Orden ni ## Dudas' (-not $P.Contains('ORDEN-MARCA') -and -not $P.Contains('DUDAS-MARCA'))
}

$Pruebas['prompt: un plan con titulos con dos puntos o en mayusculas lleva solo su parte'] = {
  $plan = $PlanTres.Replace('## Piezas comunes', '## Piezas comunes:').Replace('## Ficheros', '## FICHEROS')
  Comprueba-Parte-Del-Plan (Prompt-Con-Plan 'prompt-titulos-puntos' $plan) '## Piezas comunes:' '## FICHEROS'
}

$Pruebas['prompt: un plan con titulos en negrita lleva solo su parte'] = {
  $plan = $PlanTres.Replace('## Piezas comunes', '## **Piezas comunes**').Replace('## Ficheros', '## **Ficheros**')
  Comprueba-Parte-Del-Plan (Prompt-Con-Plan 'prompt-titulos-negrita' $plan) '## **Piezas comunes**' '## **Ficheros**'
}

$Pruebas['prompt: Maven fuera del repo va con su ruta, y entre comillas si tiene espacios'] = {
  $e = Nuevo-Escenario 'maven-fuera'
  $mvn = Join-Path $falsos 'mvn.ps1'
  Igual 'MvnExe fuera del repo: su ruta, sin ./' $mvn (Maven-Del-Prompt $e)
  $e2 = Nuevo-Escenario 'maven-espacios'
  $conEspacios = Join-Path $Dir 'con espacios'
  [void](New-Item -ItemType Directory -Path $conEspacios -Force)
  Copy-Item -LiteralPath $mvn -Destination (Join-Path $conEspacios 'mvn.ps1')
  $cfg = [pscustomobject]@{ CopilotExe = (Join-Path $falsos 'copilot.ps1'); MvnExe = (Join-Path $conEspacios 'mvn.ps1') }
  Escribe $e2.Repo '.rescate/config.json' (ConvertTo-Json -InputObject $cfg)
  Igual 'con espacios: entre comillas dobles' ('"' + (Join-Path $conEspacios 'mvn.ps1') + '"') (Maven-Del-Prompt $e2)
}

$Pruebas['prompt: con mvnw en la raiz del repo el prompt dice ./mvnw'] = {
  $e = Nuevo-Escenario 'maven-mvnw'
  $mvn = Join-Path $falsos 'mvn.ps1'
  # un mvnw de mentira que llama al Maven de mentira
  if ($env:OS -eq 'Windows_NT') {
    $w = 'mvnw.cmd'; $esperado = '.\mvnw.cmd'
    Escribe $e.Repo $w ('@echo off' + "`r`n" + '"' + $ps + '" -NoProfile -File "' + $mvn + '" %*' + "`r`n" + 'exit /b %ERRORLEVEL%' + "`r`n")
  }
  else {
    $w = 'mvnw'; $esperado = './mvnw'
    Escribe $e.Repo $w ('#!/bin/sh' + "`n" + 'exec "' + $ps + '" -NoProfile -File "' + $mvn + '" "$@"' + "`n")
    & chmod +x (Get-Ruta $e.Repo $w)   # ejecutable de verdad: un mvnw que no se puede lanzar ya no pasa por un build bueno
  }
  [void](GitEn $e.Repo @('add', '--', $w))
  [void](GitEn $e.Repo @('update-index', '--chmod=+x', '--', $w))
  [void](GitEn $e.Repo @('commit', '-q', '-m', 'mvnw'))
  Escribe $e.Repo '.rescate/config.json' (ConvertTo-Json -InputObject ([pscustomobject]@{ CopilotExe = (Join-Path $falsos 'copilot.ps1') }))
  Igual 'dentro del repo: ./mvnw' $esperado (Maven-Del-Prompt $e)
}

$DetalleSecreto = "secreto escrito en claro ('{0}'): tiene que entrar por una variable de entorno, sin valor por defecto"

$Pruebas['config: un secreto escrito en claro en application.properties es un error y su valor no sale'] = {
  $e = Escenario-Con-Recursos 'secreto-properties' @{ 'application.properties' = @'
# conexion de la base de datos
spring.application.name=life
spring.datasource.url=jdbc:h2:mem:life
spring.datasource.password=acme2015
spring.mail.password=${MAIL_PASSWORD}
'@ }
  $d = Diagnostica-Secretos $e
  Igual 'sale con 0' 0 $d.R.Codigo
  Igual 'un hallazgo' 1 $d.H.Count
  Igual 'es un error' 'error' $d.H[0].Sev
  Igual 'del fichero' 'src/main/resources/application.properties' $d.H[0].Fichero
  Igual 'en su linea' 4 $d.H[0].Linea
  Igual 'con su detalle' ($DetalleSecreto -f 'spring.datasource.password') $d.H[0].Detalle
  Comprueba 'el valor no sale ni en la consola, ni en hallazgos.json, ni en el informe' (-not (Lo-Que-Sale $e.Repo $d.R.Salida).Contains('acme2015'))
}

$Pruebas['config: en application.yml, con comillas y comentario es un error; con variable, no'] = {
  $e = Escenario-Con-Recursos 'secreto-yml' @{ 'application.yml' = @'
spring:
  datasource:
    username: life
    password: "acme2015"   # clave de pruebas
sftp:
  password: ${SFTP_PASSWORD:}
mail:
  password: ${DB_PASSWORD}   # sale del entorno
'@ }
  $d = Diagnostica-Secretos $e
  Igual 'un hallazgo' 1 $d.H.Count
  Igual 'es un error' 'error' $d.H[0].Sev
  Igual 'del fichero' 'src/main/resources/application.yml' $d.H[0].Fichero
  Igual 'en su linea' 4 $d.H[0].Linea
  Igual 'con su detalle' ($DetalleSecreto -f 'password') $d.H[0].Detalle
  Comprueba 'el valor no sale' (-not (Lo-Que-Sale $e.Repo $d.R.Salida).Contains('acme2015'))
}

$Pruebas['config: una variable con valor por defecto es un error'] = {
  $e = Escenario-Con-Recursos 'secreto-defecto' @{ 'application.yml' = @'
spring:
  datasource:
    password: ${DB_PASSWORD:acme2015}
'@ }
  $d = Diagnostica-Secretos $e
  Igual 'un hallazgo' 1 $d.H.Count
  Igual 'es un error' 'error' $d.H[0].Sev
  Igual 'en su linea' 3 $d.H[0].Linea
  Comprueba 'el valor por defecto no sale' (-not (Lo-Que-Sale $e.Repo $d.R.Salida).Contains('acme2015'))
}

$Pruebas['config: en un fichero con perfil es un aviso'] = {
  $e = Escenario-Con-Recursos 'secreto-perfil' @{
    'application-local.yml'      = "spring:`n  datasource:`n    password: acme2015`n"
    'application-pro.properties' = "spring.datasource.password=acme2015`n"
  }
  $d = Diagnostica-Secretos $e
  Igual 'dos hallazgos' 2 $d.H.Count
  Igual 'ninguno es un error' 0 @($d.H | Where-Object { $_.Sev -eq 'error' }).Count
  Igual 'ficheros' 'src/main/resources/application-local.yml src/main/resources/application-pro.properties' (@($d.H | ForEach-Object { $_.Fichero } | Sort-Object) -join ' ')
  Comprueba 'el valor no sale' (-not (Lo-Que-Sale $e.Repo $d.R.Salida).Contains('acme2015'))
}

$Pruebas['config: cuenta por el final de la clave'] = {
  $e = Escenario-Con-Recursos 'secreto-claves' @{ 'application.yml' = @'
oauth:
  token-uri: https://auth.example.invalid/token
  password-file: /run/x
  clientSecret: abc
  api-key: abc
'@ }
  $d = Diagnostica-Secretos $e
  Igual 'dos hallazgos' 2 $d.H.Count
  Igual 'lineas' '4 5' (@($d.H | ForEach-Object { $_.Linea } | Sort-Object) -join ' ')
  Igual 'claves' ('api-key clientSecret') (@($d.H | ForEach-Object { [regex]::Match($_.Detalle, "\('([^']+)'\)").Groups[1].Value } | Sort-Object) -join ' ')
  Igual 'son errores' 2 @($d.H | Where-Object { $_.Sev -eq 'error' }).Count
}

$Pruebas['config: una linea comentada no cuenta'] = {
  $e = Escenario-Con-Recursos 'secreto-comentado' @{
    'application.yml'        = "spring:`n  datasource:`n    # password: acme2015`n    username: life`n"
    'application.properties' = "#spring.datasource.password=acme2015`n! spring.mail.password=acme2015`n    # sftp.password=acme2015`n"
  }
  $d = Diagnostica-Secretos $e
  Igual 'ningun hallazgo' 0 $d.H.Count
}

$Pruebas['config: PalabrasSecreto se cambia en .rescate/config.json'] = {
  $e = Escenario-Con-Recursos 'secreto-palabras' @{ 'application.properties' = "spring.datasource.password=acme2015`nsftp.pin=4321`n" }
  $cfg = [pscustomobject]@{ CopilotExe = (Join-Path $falsos 'copilot.ps1'); MvnExe = (Join-Path $falsos 'mvn.ps1'); PalabrasSecreto = @() }
  Escribe $e.Repo '.rescate/config.json' (ConvertTo-Json -InputObject $cfg)
  Igual 'con la lista vacia no hay hallazgos' 0 (Diagnostica-Secretos $e).H.Count
  $cfg.PalabrasSecreto = @('pin')
  Escribe $e.Repo '.rescate/config.json' (ConvertTo-Json -InputObject $cfg)
  $d = Diagnostica-Secretos $e
  Igual 'con otra lista solo cuenta la suya' 1 $d.H.Count
  Igual 'es la clave pin' ($DetalleSecreto -f 'sftp.pin') $d.H[0].Detalle
  Igual 'en su linea' 2 $d.H[0].Linea
}

$Pruebas['config: el prompt lleva el texto nuevo y no el valor del secreto'] = {
  $e = Escenario-Con-Recursos 'secreto-prompt' @{ 'application.properties' = "spring.datasource.password=acme2015`n" }
  $r = Rescate @('-Modo', 'fix', '-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-Paso', 'config', '-SinPlan', '-Lote', '20', '-MaxLotes', '1', '-Auto', '-Si', '-MaxIntentos', '1')
  $p = Lee $e.Wt '.rescate/prompt.md'
  $texto = 'Ningun secreto (contrasena, token, clave) puede quedar escrito en application.yml o application.properties, ni como valor por defecto: se leen de una variable de entorno (`${NOMBRE}`). No escribas el valor en ningun otro fichero del repo; si un test lo necesita, usa un valor inventado en src/test/resources.'
  Comprueba 'lleva el texto nuevo del paso' $p.Contains($texto)
  Comprueba 'ya no dice que los secretos se quedan como variables' (-not $p.Contains('no escribas ninguno'))
  Comprueba 'lleva el hallazgo, con su fichero y su linea' $p.Contains("- src/main/resources/application.properties:1 - " + ($DetalleSecreto -f 'spring.datasource.password'))
  Comprueba 'el valor no sale ni en el prompt, ni en la consola, ni en lo que deja el script' (-not ((Lo-Que-Sale $e.Wt $r.Salida) + $p).Contains('acme2015'))
}

$Pruebas['config: unas comillas vacias no son un secreto'] = {
  $e = Escenario-Con-Recursos 'secreto-comillas-vacias' @{ 'application.yml' = "app:`n  password: `"`"`n  secret: ''`n" }
  Igual 'ningun hallazgo' 0 (Diagnostica-Secretos $e).H.Count
}

$Pruebas['config: en YAML un comentario solo no es un valor y el del final no se lee como valor'] = {
  $e = Escenario-Con-Recursos 'secreto-yml-comentario' @{ 'application.yml' = "app:`n  password: # solo un comentario`n  secret: abc # comentario`n" }
  $d = Diagnostica-Secretos $e
  Igual 'un hallazgo' 1 $d.H.Count
  Igual 'es el de la linea con valor' 3 $d.H[0].Linea
  Igual 'es un error' 'error' $d.H[0].Sev
}

$Pruebas['config: en .properties un ! pegado a la clave es un comentario'] = {
  $e = Escenario-Con-Recursos 'secreto-admiracion' @{ 'application.properties' = "!spring.datasource.password=abc`n" }
  Igual 'ningun hallazgo' 0 (Diagnostica-Secretos $e).H.Count
}

$Pruebas['config: en .properties el separador puede ser dos puntos'] = {
  $e = Escenario-Con-Recursos 'secreto-dos-puntos' @{ 'application.properties' = "mi.password: abc`n" }
  $d = Diagnostica-Secretos $e
  Igual 'un hallazgo' 1 $d.H.Count
  Igual 'es un error' 'error' $d.H[0].Sev
  Igual 'con su clave' ($DetalleSecreto -f 'mi.password') $d.H[0].Detalle
}

# ===================== LA PLANTILLA INCUMPLE LO QUE EXIGE =====================
# Escenario cuya plantilla son estos ficheros (ruta -> texto) en vez de la de siempre.
function Escenario-Con-Plantilla([string]$Nombre, $Ficheros) {
  $e = Nuevo-Escenario $Nombre
  Remove-Item -LiteralPath $e.Plantilla -Recurse -Force
  Escribe $e.Plantilla 'pom.xml' $Pom
  foreach ($ruta in $Ficheros.Keys) { Escribe $e.Plantilla $ruta $Ficheros[$ruta] }
  return $e
}

$Base = 'src/main/java/com/acme/plantilla/'
$Arranque = "package com.acme.plantilla;`n`n/** Arranque. */`n@org.springframework.boot.autoconfigure.SpringBootApplication`npublic class PlantillaApplication {`n}`n"
# Incumple: dos clases de dominio que importan el mismo paquete de infrastructure (1 capa, no 2), dos clases que abren
# ficheros en la misma carpeta (1 fichero, no 2), dos tipos publicos sin Javadoc y un println (2 reglas de calidad, no 3
# hallazgos) y un secreto en application.yml (1 error; el de application-local.yml es un aviso y no cuenta).
$PlantillaIncumple = [ordered]@{
  ($Base + 'PlantillaApplication.java') = $Arranque
  ($Base + 'infrastructure/config/BatchProperties.java') = "package com.acme.plantilla.infrastructure.config;`n`n/** Propiedades. */`npublic record BatchProperties(String carpeta) {`n}`n"
  ($Base + 'domain/model/Poliza.java') = "package com.acme.plantilla.domain.model;`n`nimport com.acme.plantilla.infrastructure.config.BatchProperties;`n`n/** Poliza. */`npublic record Poliza(String numero) {`n}`n"
  ($Base + 'domain/model/Cliente.java') = "package com.acme.plantilla.domain.model;`n`nimport com.acme.plantilla.infrastructure.config.BatchProperties;`n`n/** Cliente. */`npublic record Cliente(String nombre) {`n}`n"
  ($Base + 'infrastructure/adapters/output/sftp/LectorLocal.java') = "package com.acme.plantilla.infrastructure.adapters.output.sftp;`n`nimport java.io.File;`n`n/** Lee ficheros locales a pelo. */`npublic class LectorLocal {`n    private final File carpeta = new File(`".`");`n}`n"
  ($Base + 'infrastructure/adapters/output/sftp/EscritorLocal.java') = "package com.acme.plantilla.infrastructure.adapters.output.sftp;`n`nimport java.io.FileWriter;`n`n/** Escribe ficheros locales a pelo. */`npublic class EscritorLocal {`n    private FileWriter salida;`n}`n"
  ($Base + 'application/usecases/SinDocUno.java') = "package com.acme.plantilla.application.usecases;`n`npublic class SinDocUno {`n    void saluda() {`n        System.out.println(`"hola`");`n    }`n}`n"
  ($Base + 'application/usecases/SinDocDos.java') = "package com.acme.plantilla.application.usecases;`n`npublic class SinDocDos {`n}`n"
  'src/main/resources/application.yml' = "sftp:`n  password: valor-secreto-9z`n"
  'src/main/resources/application-local.yml' = "sftp:`n  token: otro-valor-secreto-7y`n"
}
# Cumple todo: Javadoc, capas respetadas, ningun fichero local y el secreto entra por una variable sin valor por defecto.
$PlantillaLimpia = [ordered]@{
  ($Base + 'PlantillaApplication.java') = $Arranque
  ($Base + 'domain/model/Poliza.java') = "package com.acme.plantilla.domain.model;`n`n/** Poliza. */`npublic record Poliza(String numero) {`n}`n"
  ($Base + 'application/usecases/CargarUseCase.java') = "package com.acme.plantilla.application.usecases;`n`nimport com.acme.plantilla.domain.model.Poliza;`n`n/** Carga. */`npublic class CargarUseCase {`n    private Poliza ultima;`n}`n"
  'src/main/resources/application.yml' = "sftp:`n  password: `${SFTP_PASSWORD}`n"
}
$SecretosPlantilla = @('valor-secreto-9z', 'otro-valor-secreto-7y')

$Pruebas['plantilla incumple: la consola y diagnostico.md cuentan capas, ficheros, calidad y secretos, sin el valor del secreto'] = {
  $e = Escenario-Con-Plantilla 'incumple' $PlantillaIncumple
  $r = Rescate @('-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-SinBuild')
  Igual 'sale con 0' 0 $r.Codigo
  $linea = 'capas 1 | ficheros 1 | calidad 2 | secretos 1'
  $consola = @($r.Salida -split "`r?`n")
  $i = [array]::IndexOf($consola, 'Plantilla incumple: ' + $linea)
  Comprueba 'la consola trae la linea con los numeros de la plantilla' ($i -ge 0) (Cola $r.Salida)
  Comprueba 'va justo despues de leer la plantilla' ($i -gt 0 -and $consola[$i - 1] -ceq 'Leyendo la plantilla...') (Cola $r.Salida)
  $md = @((Lee $e.Repo '.rescate/diagnostico.md') -split "`r?`n")
  $j = [array]::IndexOf($md, '- La plantilla incumple: ' + $linea)
  Comprueba 'diagnostico.md trae los mismos numeros' ($j -ge 0) ($md -join ' / ')
  Comprueba 'y va debajo de la linea de la plantilla' ($j -gt 0 -and $md[$j - 1] -clike '- Plantilla: *') ($md -join ' / ')
  $todo = Lo-Que-Sale $e.Repo $r.Salida
  foreach ($s in $SecretosPlantilla) { Comprueba ('el valor del secreto ' + $s.Substring(0, 5) + '... no sale en ninguna salida') (-not $todo.Contains($s)) }
}

$Pruebas['plantilla incumple: una plantilla que cumple todo cuenta cero'] = {
  $e = Escenario-Con-Plantilla 'limpia' $PlantillaLimpia
  $r = Rescate @('-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-SinBuild')
  Igual 'sale con 0' 0 $r.Codigo
  $linea = 'capas 0 | ficheros 0 | calidad 0 | secretos 0'
  Comprueba 'la consola dice todo a cero' (@($r.Salida -split "`r?`n") -contains ('Plantilla incumple: ' + $linea)) (Cola $r.Salida)
  Comprueba 'y diagnostico.md tambien' (@((Lee $e.Repo '.rescate/diagnostico.md') -split "`r?`n") -contains ('- La plantilla incumple: ' + $linea))
}

$Pruebas['plantilla incumple: sin -Plantilla no hay linea; con ella, la hay tambien en el modo pre'] = {
  $e = Escenario-Con-Plantilla 'sin-plantilla' $PlantillaIncumple
  $r = Rescate @('-Repo', $e.Repo, '-SinBuild')
  Igual 'sale con 0' 0 $r.Codigo
  Comprueba 'la consola no dice nada de lo que incumple' ($r.Salida -notmatch 'incumple') (Cola $r.Salida)
  Comprueba 'diagnostico.md tampoco' ((Lee $e.Repo '.rescate/diagnostico.md') -notmatch 'incumple')
  $orig = Join-Path (Join-Path $Dir 'sin-plantilla') 'original'
  Escribe $orig 'src/main/java/com/acme/viejo/Viejo.java' "package com.acme.viejo;`n`npublic class Viejo {`n}`n"
  $pre = Rescate @('-Modo', 'pre', '-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-Legacy', $orig, '-SinIA')
  Igual 'el modo pre sale con 0' 0 $pre.Codigo
  Comprueba 'el modo pre trae la linea' (@($pre.Salida -split "`r?`n") -contains 'Plantilla incumple: capas 1 | ficheros 1 | calidad 2 | secretos 1') (Cola $pre.Salida)
}

# Un adaptador que abre ficheros donde se puede (infrastructure/adapters/output/file) no es un incumplimiento de la referencia.
$AdaptadorFichero = "package com.acme.plantilla.infrastructure.adapters.output.file;`n`nimport java.nio.file.Files;`n`n/** Lee ficheros del disco. */`npublic class FicheroLocalAdapter {`n    private Files ayuda;`n}`n"
$LectorFuera = "package com.acme.plantilla.infrastructure.adapters.output.sftp;`n`nimport java.io.File;`n`n/** Lee ficheros locales a pelo. */`npublic class LectorLocal {`n    private final File carpeta = new File(`".`");`n}`n"

# La plantilla que cumple todo, con estos ficheros mas (ruta -> texto).
function Limpia-Mas([hashtable]$Mas) {
  $f = @{}
  foreach ($k in $PlantillaLimpia.Keys) { $f[$k] = $PlantillaLimpia[$k] }
  foreach ($k in $Mas.Keys) { $f[$k] = $Mas[$k] }
  return $f
}

# Lo que dice diagnostico.md de lo que se permite porque la plantilla tambien lo hace (desde su titulo hasta el final).
function Permitido-Del-Informe($E) {
  $md = Lee $E.Repo '.rescate/diagnostico.md'
  return $md.Substring($md.IndexOf('## Permitido porque la plantilla tambien lo hace'))
}

$Pruebas['plantilla incumple: el adaptador de ficheros de su carpeta permitida no cuenta ni sale en lo permitido'] = {
  $e = Escenario-Con-Plantilla 'adaptador-permitido' (Limpia-Mas @{ ($Base + 'infrastructure/adapters/output/file/FicheroLocalAdapter.java') = $AdaptadorFichero })
  $r = Rescate @('-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-SinBuild')
  Igual 'sale con 0' 0 $r.Codigo
  Comprueba 'la consola dice ficheros 0' (@($r.Salida -split "`r?`n") -contains 'Plantilla incumple: capas 0 | ficheros 0 | calidad 0 | secretos 0') (Cola $r.Salida)
  $p = Permitido-Del-Informe $e
  Comprueba 'lo permitido dice que no hay nada' ($p -match '- \(nada: la plantilla cumple todas las reglas\)') $p
  Comprueba 'y no lista el uso de ficheros del adaptador' ($p -notmatch 'java\.nio') $p
}

$Pruebas['plantilla incumple: con el adaptador permitido y un uso de ficheros en otra carpeta, ficheros 1'] = {
  $e = Escenario-Con-Plantilla 'adaptador-y-fuera' (Limpia-Mas @{
      ($Base + 'infrastructure/adapters/output/file/FicheroLocalAdapter.java') = $AdaptadorFichero
      ($Base + 'infrastructure/adapters/output/sftp/LectorLocal.java')         = $LectorFuera
    })
  $r = Rescate @('-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-SinBuild')
  Igual 'sale con 0' 0 $r.Codigo
  Comprueba 'la consola dice ficheros 1' (@($r.Salida -split "`r?`n") -contains 'Plantilla incumple: capas 0 | ficheros 1 | calidad 0 | secretos 0') (Cola $r.Salida)
  $p = Permitido-Del-Informe $e
  Comprueba 'lo permitido lista solo el uso de fuera' ($p -match '- infrastructure/adapters/output/sftp -> java\.io' -and $p -notmatch 'output/file' -and $p -notmatch 'java\.nio') $p
}

# ======================= LATIDO MIENTRAS ESPERA ========================
# Mientras Copilot o Maven tardan, la consola escribe cada SegundosLatido una linea
# "  ... sigue: <que> (lleva N min M s)" para que se vea que el script no esta colgado.
function Lineas-Latido([string]$Salida) { return @($Salida -split "`r?`n" | Where-Object { $_ -match '^\s*\.\.\. sigue' }) }

# El config.json del repo del escenario: Maven y Copilot, los falsos, y sin reflexion (estas pruebas cuentan las llamadas
# a Copilot; la reflexion tiene las suyas, en M6), mas estos ajustes (nombre -> valor).
function Pon-Config($E, [hashtable]$Mas) {
  $cfg = [ordered]@{ CopilotExe = (Join-Path $falsos 'copilot.ps1'); MvnExe = (Join-Path $falsos 'mvn.ps1'); Reflexionar = $false }
  foreach ($k in $Mas.Keys) { $cfg[$k] = $Mas[$k] }
  Escribe $E.Repo '.rescate/config.json' (ConvertTo-Json -InputObject $cfg)
}

$ArgsFix = @('-Modo', 'fix', '-Paso', 'estructura', '-SinPlan', '-Auto', '-Si', '-MaxIntentos', '1')

$Pruebas['latido: mientras Copilot tarda, la consola dice que sigue, y el arreglo sale como siempre'] = {
  $e = Nuevo-Escenario 'latido-copilot'
  Pon-Config $e @{ SegundosLatido = 1 }
  $r = Rescate (@('-Repo', $e.Repo, '-Plantilla', $e.Plantilla) + $ArgsFix) 'lento'
  Igual 'el fix sale con 0' 0 $r.Codigo
  $l = Lineas-Latido $r.Salida
  Comprueba 'hay al menos una linea del latido' ($l.Count -ge 1) (Cola $r.Salida)
  # el tope es holgado a proposito: el arranque de pwsh bajo carga suma segundos a los 3 del falso
  Comprueba 'y no un aluvion (como mucho 6)' ($l.Count -le 6) ($l.Count.ToString() + ' lineas')
  Comprueba 'cada una dice que espera a Copilot y cuanto lleva' (@($l | Where-Object { $_ -match '^  \.\.\. sigue: Copilot .*\(lleva \d+ min \d+ s\)$' }).Count -eq $l.Count) ($l -join ' / ')
  $hw = Hallazgos $e.Wt
  Igual 'estructura queda a 0 en el worktree' 0 (Cuenta $hw 'estructura')
  Comprueba 'hay commit del lote' ((GitEn $e.Wt @('log', '--format=%s')) -match 'rescate\(estructura\): lote 1') (Cola $r.Salida)
}

$Pruebas['latido: mientras Maven tarda, la consola dice que sigue'] = {
  $e = Nuevo-Escenario 'latido-maven'
  Pon-Config $e @{ SegundosLatido = 1 }
  $env:RESCATE_MVN_ESPERA = '3'
  try { $r = Rescate @('-Repo', $e.Repo, '-Plantilla', $e.Plantilla) }
  finally { $env:RESCATE_MVN_ESPERA = '' }
  Igual 'el diagnostico sale con 0' 0 $r.Codigo
  $l = Lineas-Latido $r.Salida
  Comprueba 'hay al menos una linea del latido de Maven' (@($l | Where-Object { $_ -match '^  \.\.\. sigue: Maven \((compilar|tests)\) \(lleva \d+ min \d+ s\)$' }).Count -ge 1) (Cola $r.Salida)
}

$Pruebas['latido: con los falsos rapidos y el intervalo por defecto no sale ninguna linea'] = {
  $e = Nuevo-Escenario 'latido-rapido'
  $r = Rescate (@('-Repo', $e.Repo, '-Plantilla', $e.Plantilla) + $ArgsFix)
  Igual 'el fix sale con 0' 0 $r.Codigo
  Igual 'ninguna linea del latido' 0 (Lineas-Latido $r.Salida).Count
}

# ============================= TOPE DE MAVEN =============================
# Pasados MinutosMaven minutos se para Maven con sus procesos hijos y la llamada cuenta como fallida. Estas pruebas lo cuelgan con
# tests/falsos/mvn-dormido.ps1 (escribe una linea, lanza un hijo que duerme y duerme 40 s) y un tope de 0.05 min (3 s).

# Un script que carga comun.ps1, pone el Maven que se le pasa y un tope de 0.05 min y llama a Invoke-MavenTope; dice lo que
# da la funcion (una clave por linea: DEFECTO, CODIGO, TOPE, SALIDA y SEGUNDOS).
$GuionTope = @'
param([string]$Sis, [string]$Mvn, [string]$Carpeta, [string]$Registro)
. (Join-Path $Sis 'comun.ps1')
'DEFECTO ' + $Cfg.MinutosMaven
$Cfg.MvnExe = $Mvn
$Cfg.MinutosMaven = 0.05
$Cfg.SegundosLatido = 0
$reloj = [System.Diagnostics.Stopwatch]::StartNew()
$r = Invoke-MavenTope $Carpeta @('-B', 'test') 'prueba' $Registro
'CODIGO ' + $r.Codigo
'TOPE ' + $r.Tope
'SALIDA ' + ($r.Salida -join ',')
'SEGUNDOS ' + $reloj.Elapsed.TotalSeconds
'@

# Lo que el guion de arriba ha dicho: clave -> texto.
function Claves-Del-Guion([string]$Salida) {
  $v = @{}
  foreach ($l in @($Salida -split "`n")) { if ($l -cmatch '^([A-Z]+) (.*)$') { $v[$Matches[1]] = $Matches[2] } }
  return $v
}

$Pruebas['tope de Maven: comun.ps1 para a Maven y a sus hijos, la llamada falla con el mensaje y el registro guarda lo escrito'] = {
  $f = Join-Path $Dir 'tope-guion.ps1'
  [System.IO.File]::WriteAllText($f, $GuionTope)
  $reg = Join-Path $Dir 'tope-t1.log'
  $carpPids = Join-Path $Dir 'tope-t1-pids'
  $env:RESCATE_MVN_CUELGA = '.'
  $env:RESCATE_MVN_PIDS = $carpPids
  try { $r = Lanzar $f @((Split-Path -Parent $Script), (Join-Path $falsos 'mvn-dormido.ps1'), $Dir, $reg) }
  finally { $env:RESCATE_MVN_CUELGA = ''; $env:RESCATE_MVN_PIDS = '' }
  $v = Claves-Del-Guion $r.Salida
  $tope = "Maven se ha pasado del tope de 0.05 min y se ha parado (prueba). Registro: $reg."
  Igual 'el tope por defecto es de 30 minutos' '30' $v['DEFECTO']
  Comprueba 'la llamada falla (codigo distinto de 0)' ($v['CODIGO'] -and $v['CODIGO'] -ne '0') (Cola $r.Salida)
  Igual 'el tope dice que se ha pasado y donde queda el registro' $tope $v['TOPE']
  Comprueba 'y sale tambien por la consola' (@($r.Salida -split "`n") -contains $tope) (Cola $r.Salida)
  Comprueba-Tope $carpPids ([double]$v['SEGUNDOS']) 20 $reg
}

$Pruebas['tope de Maven: un Maven rapido sale igual: codigo, lineas y registro'] = {
  $f = Join-Path $Dir 'tope-guion.ps1'
  [System.IO.File]::WriteAllText($f, $GuionTope)
  $rapido = Join-Path $Dir 'mvn-rapido.ps1'
  [System.IO.File]::WriteAllText($rapido, "'uno'`n'dos'`n[Console]::Error.WriteLine('tres')`nexit 3`n")
  $reg = Join-Path $Dir 'tope-t2.log'
  $r = Lanzar $f @((Split-Path -Parent $Script), $rapido, $Dir, $reg)
  $v = Claves-Del-Guion $r.Salida
  Igual 'el codigo es el del Maven' '3' $v['CODIGO']
  Igual 'las lineas: las de la salida y despues las de errores' 'uno,dos,tres' $v['SALIDA']
  Igual 'sin tope' '' $v['TOPE']
  Igual 'el registro lleva las tres lineas' "uno`ndos`ntres`n" ([System.IO.File]::ReadAllText($reg))
  Comprueba 'la consola no dice nada del tope' ($r.Salida -notmatch 'se ha pasado del tope') (Cola $r.Salida)
}

$Pruebas['tope de Maven: rescate, diagnostico: el hallazgo de build lleva el mensaje (MinutosMaven de .rescate/config.json)'] = {
  $e = Nuevo-Escenario 'tope-diagnostico'
  Pon-Config $e @{ MvnExe = (Join-Path $falsos 'mvn-dormido.ps1'); MinutosMaven = 0.05 }
  $carpPids = Join-Path $Dir 'tope-t3-pids'
  $env:RESCATE_MVN_CUELGA = '[ |]test$'
  $env:RESCATE_MVN_PIDS = $carpPids
  $reloj = [System.Diagnostics.Stopwatch]::StartNew()
  try { $r = Rescate @('-Repo', $e.Repo, '-Plantilla', $e.Plantilla) }
  finally { $env:RESCATE_MVN_CUELGA = ''; $env:RESCATE_MVN_PIDS = '' }
  $seg = $reloj.Elapsed.TotalSeconds
  Igual 'el diagnostico sale con 0, como con un build que falla' 0 $r.Codigo
  $h = @(Hallazgos $e.Repo | Where-Object { $_.Cat -eq 'build' -and $_.Sev -eq 'error' })
  Igual 'hay un hallazgo de build' 1 $h.Count
  $reg = Join-Path (Join-Path $e.Repo '.rescate') 'build.log'
  $ini = 'el build falla: Maven se ha pasado del tope de 0.05 min y se ha parado (Maven (tests)). Registro: '
  Comprueba 'su detalle dice que el build falla y que Maven se paso (0.05: manda el config.json)' ($h.Count -gt 0 -and $h[0].Detalle.StartsWith($ini)) (Cola $r.Salida)
  Comprueba 'y acaba en la ruta del registro' ($h.Count -gt 0 -and $h[0].Detalle.EndsWith('build.log.')) (Cola $r.Salida)
  Comprueba-Tope $carpPids $seg 30 $reg
}

$Pruebas['tope de Maven: rescate, lote: si Maven se pasa al comprobar, el lote se deshace y la consola lo dice'] = {
  $e = Nuevo-Escenario 'tope-lote'
  Pon-Config $e @{ MvnExe = (Join-Path $falsos 'mvn-dormido.ps1'); MinutosMaven = 0.05 }
  $carpPids = Join-Path $Dir 'tope-t4-pids'
  $env:RESCATE_MVN_CUELGA = '[ |]test$'
  $env:RESCATE_MVN_PIDS = $carpPids
  $env:RESCATE_MVN_DESDE = '2'
  $reloj = [System.Diagnostics.Stopwatch]::StartNew()
  try { $r = Rescate (@('-Repo', $e.Repo, '-Plantilla', $e.Plantilla) + $ArgsFix) }
  finally { $env:RESCATE_MVN_CUELGA = ''; $env:RESCATE_MVN_PIDS = ''; $env:RESCATE_MVN_DESDE = '' }
  $seg = $reloj.Elapsed.TotalSeconds
  # el diagnostico inicial hace una sola llamada de tests (la 1.a, que pasa); se cuelgan todas las demas (la del lote y los reintentos
  # de uno en uno, hasta que paran los lotes deshechos seguidos), y cada llamada colgada anota 2 PID
  $cuenta = @([System.IO.File]::ReadAllLines((Join-Path $carpPids 'cuenta.txt')))
  $colgadas = @([System.IO.File]::ReadAllLines((Join-Path $carpPids 'pids.txt')) | Where-Object { $_ }).Count
  Comprueba 'la 1.a llamada de tests (el diagnostico inicial) pasa y se cuelgan todas las demas, desde la del lote' ($cuenta.Count -ge 2 -and $colgadas -eq 2 * ($cuenta.Count - 1)) "llamadas: $($cuenta.Count), PID anotados: $colgadas"
  Comprueba 'el lote 1 se deshace' ($r.Salida -match 'Lote 1 DESHECHO') (Cola $r.Salida)
  Comprueba 'y la consola dice que Maven se paso' ($r.Salida -match [regex]::Escape('Maven se ha pasado del tope de 0.05 min y se ha parado (Maven (tests)). Registro: ')) (Cola $r.Salida)
  Comprueba 'sin ningun commit del lote' (-not (Hay-Commit-Del-Lote $e)) (Cola $r.Salida)
  Comprueba-Tope $carpPids $seg 30 (Join-Path (Join-Path $e.Wt '.rescate') 'build.log')
}

# ============================ SFTP COMO REGLA FIJA ============================
# Si el batch migrado maneja ficheros, tiene que traer el adaptador SFTP y su configuracion, tenga lo que tenga la
# referencia y tambien sin ella. El interruptor ExigirSftp (por defecto true) lo apaga: entonces solo se exige lo que la referencia tiene.
$SinAdaptadorSftp = 'no hay adaptador SFTP*'
$SinYmlSftp = 'application.yml no tiene configuracion sftp*'

# Los hallazgos de ficheros del repo que dicen eso (patron -like sobre el detalle).
function Hallazgos-Sftp([string]$Repo, [string]$Patron) {
  return @(Hallazgos $Repo | Where-Object { $_.Cat -eq 'ficheros' -and $_.Sev -eq 'error' -and $_.Detalle -like $Patron })
}

# Una referencia que no sabe nada de SFTP: ni carpeta sftp ni configuracion sftp.
$ConfigSinSftp = "batch:`n  nombre: ejemplo`n"
function Escenario-Referencia-Sin-Sftp([string]$Nombre) {
  return (Escenario-Con-Plantilla $Nombre (Limpia-Mas @{ 'src/main/resources/application.yml' = $ConfigSinSftp }))
}

$Pruebas['sftp fijo: migrado con ficheros y sin carpeta sftp, con una referencia sin SFTP, tiene el error y no dice que la plantilla lo tenga'] = {
  $e = Escenario-Referencia-Sin-Sftp 'sftp-ref-sin'
  $r = Rescate @('-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-SinBuild')
  Igual 'sale con 0' 0 $r.Codigo
  $a = Hallazgos-Sftp $e.Repo $SinAdaptadorSftp
  Igual 'un error de adaptador SFTP' 1 $a.Count
  Comprueba 'no dice que la plantilla lo tenga' ($a.Count -eq 1 -and $a[0].Detalle -notmatch 'plantilla') (Cola $r.Salida)
  Comprueba 'dice donde va' ($a.Count -eq 1 -and $a[0].Detalle -match 'infrastructure/adapters/output/sftp')
  $y = Hallazgos-Sftp $e.Repo $SinYmlSftp
  Igual 'y un error de configuracion sftp' 1 $y.Count
  Comprueba 'que tampoco habla de la plantilla' ($y.Count -eq 1 -and $y[0].Detalle -notmatch 'plantilla')
}

$Pruebas['sftp fijo: con una referencia que si lo tiene, el texto sigue diciendolo'] = {
  $e = Nuevo-Escenario 'sftp-ref-con'
  $r = Rescate @('-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-SinBuild')
  Igual 'sale con 0' 0 $r.Codigo
  $a = Hallazgos-Sftp $e.Repo $SinAdaptadorSftp
  Comprueba 'el adaptador: la plantilla lo tiene en su carpeta' ($a.Count -eq 1 -and $a[0].Detalle -match 'la plantilla lo tiene en infrastructure/adapters/output/sftp')
  $y = Hallazgos-Sftp $e.Repo $SinYmlSftp
  Comprueba 'la configuracion: la plantilla si' ($y.Count -eq 1 -and $y[0].Detalle -match '\(la plantilla si\)')
}

$Pruebas['sftp fijo: sin -Plantilla tambien salta'] = {
  $e = Nuevo-Escenario 'sftp-sin-plantilla'
  $r = Rescate @('-Repo', $e.Repo, '-SinBuild')
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'un error de adaptador SFTP' 1 (Hallazgos-Sftp $e.Repo $SinAdaptadorSftp).Count
  Igual 'y uno de configuracion sftp' 1 (Hallazgos-Sftp $e.Repo $SinYmlSftp).Count
}

$Pruebas['sftp fijo: con ExigirSftp en false y una referencia sin SFTP no salta nada, como antes'] = {
  $e = Escenario-Referencia-Sin-Sftp 'sftp-apagado'
  Pon-Config $e @{ ExigirSftp = $false }
  $r = Rescate @('-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-SinBuild')
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'ni adaptador SFTP' 0 (Hallazgos-Sftp $e.Repo $SinAdaptadorSftp).Count
  Igual 'ni configuracion sftp' 0 (Hallazgos-Sftp $e.Repo $SinYmlSftp).Count
  Igual 'solo queda el acceso directo a ficheros' 1 (Cuenta (Hallazgos $e.Repo) 'ficheros')
}

$Pruebas['sftp fijo: con ExigirSftp en false y una referencia que si lo tiene, salta como antes'] = {
  $e = Nuevo-Escenario 'sftp-apagado-ref-con'
  Pon-Config $e @{ ExigirSftp = $false }
  $r = Rescate @('-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-SinBuild')
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'los tres hallazgos de ficheros de siempre' 3 (Cuenta (Hallazgos $e.Repo) 'ficheros')
}

$Pruebas['sftp fijo: un migrado que no usa ficheros no tiene nada que exigir'] = {
  $e = Escenario-Referencia-Sin-Sftp 'sftp-sin-ficheros'
  Remove-Item -LiteralPath (Get-Ruta $e.Repo 'src/main/java/com/acme/life/application/usecases/LeerFichero.java') -Force
  [void](GitEn $e.Repo @('add', '-u'))
  [void](GitEn $e.Repo @('commit', '-q', '-m', 'sin ficheros'))
  $r = Rescate @('-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-SinBuild')
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'ningun hallazgo de ficheros' 0 (Cuenta (Hallazgos $e.Repo) 'ficheros')
}

$Pruebas['sftp fijo: application.yml sin sftp es un error con una referencia sin SFTP, y con el interruptor apagado no'] = {
  $e = Escenario-Referencia-Sin-Sftp 'sftp-yml'
  # el migrado trae su adaptador SFTP: solo falta la configuracion
  Escribe $e.Repo 'src/main/java/com/acme/life/infrastructure/adapters/output/sftp/FicheroSftp.java' "package com.acme.life.infrastructure.adapters.output.sftp;`n`n/** Adaptador SFTP. */`npublic class FicheroSftp {`n}`n"
  [void](GitEn $e.Repo @('add', '--', 'src/main/java/com/acme/life/infrastructure/adapters/output/sftp/FicheroSftp.java'))
  [void](GitEn $e.Repo @('commit', '-q', '-m', 'adaptador sftp'))
  [void](Rescate @('-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-SinBuild'))
  Igual 'con el adaptador no salta el del adaptador' 0 (Hallazgos-Sftp $e.Repo $SinAdaptadorSftp).Count
  Igual 'pero si el de la configuracion' 1 (Hallazgos-Sftp $e.Repo $SinYmlSftp).Count
  Pon-Config $e @{ ExigirSftp = $false }
  [void](Rescate @('-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-SinBuild'))
  Igual 'apagado el interruptor, nada' 0 (Hallazgos-Sftp $e.Repo $SinYmlSftp).Count
}

# La configuracion SFTP tambien puede entrar por una clase de src/main/java (un @ConfigurationProperties con prefijo sftp
# o un @Value con una clave sftp, que Spring une con SFTP_HOST sin tocar el yml): entonces el yml no tiene que traer el bloque.
# Escenario con el adaptador SFTP, sin sftp en el yml de la referencia ni en el del migrado, y esta clase de configuracion.
function Hallazgos-Yml-Con-Clase([string]$Nombre, [string]$Clase) {
  $e = Escenario-Referencia-Sin-Sftp $Nombre
  $pk = 'src/main/java/com/acme/life/infrastructure/'
  Escribe $e.Repo ($pk + 'adapters/output/sftp/FicheroSftp.java') "package com.acme.life.infrastructure.adapters.output.sftp;`n`n/** Adaptador SFTP. */`npublic class FicheroSftp {`n}`n"
  $ficheros = @($pk + 'adapters/output/sftp/FicheroSftp.java')
  if ($Clase) {
    Escribe $e.Repo ($pk + 'config/Ajustes.java') $Clase
    $ficheros += ($pk + 'config/Ajustes.java')
  }
  [void](GitEn $e.Repo (@('add', '--') + $ficheros))
  [void](GitEn $e.Repo @('commit', '-q', '-m', 'adaptador y ajustes'))
  $r = Rescate @('-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-SinBuild')
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'con el adaptador no salta el del adaptador' 0 (Hallazgos-Sftp $e.Repo $SinAdaptadorSftp).Count
  return @(Hallazgos-Sftp $e.Repo $SinYmlSftp)
}

$ClaseCabecera = "package com.acme.life.infrastructure.config;`n`nimport org.springframework.beans.factory.annotation.Value;`nimport org.springframework.boot.context.properties.ConfigurationProperties;`n`n"

$Pruebas['sftp en java: un @ConfigurationProperties con prefijo sftp (prefix, value o directo, sin mirar mayusculas) cuenta como configuracion'] = {
  $formas = [ordered]@{
    'prefix'  = '@ConfigurationProperties(prefix = "sftp")'
    'value'   = '@ConfigurationProperties(value = "app.SFTP", ignoreUnknownFields = false)'
    'directo' = '@ConfigurationProperties("sftp.destino")'
  }
  foreach ($k in $formas.Keys) {
    $clase = $ClaseCabecera + "/** Ajustes. */`n" + $formas[$k] + "`npublic class Ajustes {`n    private String host;`n}`n"
    Igual ("forma " + $k + ': no hay hallazgo de configuracion sftp') 0 (Hallazgos-Yml-Con-Clase ('sftp-java-cp-' + $k) $clase).Count
  }
}

$Pruebas['sftp en java: un @Value con una clave sftp cuenta como configuracion'] = {
  $clase = $ClaseCabecera + "/** Ajustes. */`npublic class Ajustes {`n    @Value(`"`${sftp.host}`")`n    private String host;`n}`n"
  Igual 'no hay hallazgo de configuracion sftp' 0 (Hallazgos-Yml-Con-Clase 'sftp-java-value' $clase).Count
}

$Pruebas['sftp en java: sin la configuracion en el yml ni en una clase, el error dice que escribir'] = {
  $y = @(Hallazgos-Yml-Con-Clase 'sftp-java-nada' '')
  Igual 'un error de configuracion sftp' 1 $y.Count
  $d = ''
  if ($y.Count -eq 1) { $d = $y[0].Detalle }
  Comprueba 'lleva la instruccion del bloque' ($d -match [regex]::Escape("anade un bloque 'sftp:'")) $d
  Comprueba 'con las claves' ($d -match [regex]::Escape('(host, port, username, password, remote-dir)')) $d
  Comprueba 'y el ejemplo con la variable de entorno' ($d -match [regex]::Escape('por ejemplo host: ${SFTP_HOST}; ningun valor real')) $d
  Comprueba 'el texto entero' ($d -ceq 'application.yml no tiene configuracion sftp: anade un bloque ''sftp:'' (host, port, username, password, remote-dir) que lea variables de entorno, por ejemplo host: ${SFTP_HOST}; ningun valor real') $d
  Comprueba 'y es ASCII' ($d -cmatch '^[\x20-\x7e]*$') $d
  # otra configuracion que no es de sftp no la salva
  $otra = $ClaseCabecera + "/** Ajustes. */`n@ConfigurationProperties(prefix = `"batch`")`npublic class Ajustes {`n    @Value(`"`${batch.nombre}`")`n    private String nombre;`n}`n"
  Igual 'con otra configuracion que no es de sftp, tambien salta' 1 (Hallazgos-Yml-Con-Clase 'sftp-java-otra' $otra).Count
}

$Pruebas['sftp en java: sftp en un comentario de Java no cuenta'] = {
  $clase = $ClaseCabecera + "/**`n * Ajustes. Antes: @ConfigurationProperties(prefix = `"sftp`").`n */`n// @Value(`"`${sftp.host}`")`n/* @ConfigurationProperties(`"sftp`") y la clave sftp.host */`npublic class Ajustes {`n    private String host; // sftp`n}`n"
  Igual 'salta el error de configuracion sftp' 1 (Hallazgos-Yml-Con-Clase 'sftp-java-comentario' $clase).Count
}

# ================ AJUSTES.JSON Y EL PROGRAMA DE COPILOT ================
# rescate.ps1 lee ajustes.json (RESCATE_HOME o la carpeta .rescate del usuario) antes que el config.json del repo, que
# manda. El programa de Copilot se busca una vez, con la misma regla que el preflight (Get-Lanzable), antes de tocar el repo.

# Escribe el ajustes.json de este escenario en su propia carpeta y lanza rescate.ps1 con RESCATE_HOME apuntando alli.
function Rescate-Con-Ajustes([string]$Nombre, [hashtable]$Ajustes, [string[]]$A, [string]$Guion = '') {
  $casa = Join-Path $Dir ($Nombre + '-casa')
  Escribe $casa 'ajustes.json' (ConvertTo-Json -InputObject $Ajustes)
  $antes = $env:RESCATE_HOME
  $env:RESCATE_HOME = $casa
  try { return (Rescate $A $Guion) }
  finally { $env:RESCATE_HOME = $antes }
}

# Hay en el worktree el commit del primer lote de 'estructura'? (sin worktree, no.)
function Hay-Commit-Del-Lote($E) {
  return ((Test-Path -LiteralPath $E.Wt) -and ((GitEn $E.Wt @('log', '--format=%s')) -match 'rescate\(estructura\): lote 1'))
}

# El config.json del repo con el Maven de mentira y sin CopilotExe, mas estos ajustes (nombre -> valor).
function Config-Sin-Copilot($E, [hashtable]$Mas = @{}) {
  $cfg = [ordered]@{ MvnExe = (Join-Path $falsos 'mvn.ps1') }
  foreach ($k in $Mas.Keys) { $cfg[$k] = $Mas[$k] }
  Escribe $E.Repo '.rescate/config.json' (ConvertTo-Json -InputObject $cfg)
}

$Pruebas['ajustes: el banco no lee los ajustes del usuario, y sin CopilotExe en el repo vale el de ajustes.json'] = {
  Comprueba 'RESCATE_HOME del banco es una carpeta suya y no tiene ajustes.json' ($env:RESCATE_HOME.StartsWith($Dir) -and -not (Test-Path -LiteralPath (Join-Path $env:RESCATE_HOME 'ajustes.json'))) $env:RESCATE_HOME
  $e = Nuevo-Escenario 'ajustes-copilot'
  Config-Sin-Copilot $e
  $r = Rescate-Con-Ajustes 'ajustes-copilot' @{ CopilotExe = (Join-Path $falsos 'copilot.ps1') } (@('-Repo', $e.Repo, '-Plantilla', $e.Plantilla) + $ArgsFix)
  Igual 'el fix sale con 0' 0 $r.Codigo
  Comprueba 'el Copilot que se ha llamado es el de ajustes.json' (Test-Path -LiteralPath (Get-Ruta $e.Wt '.rescate/llamadas.log')) (Cola $r.Salida)
  Comprueba 'el arreglo hace su commit del lote' (Hay-Commit-Del-Lote $e) (Cola $r.Salida)
}

$Pruebas['ajustes: si los dos dicen CopilotExe, manda el config.json del repo'] = {
  $e = Nuevo-Escenario 'ajustes-manda-repo'
  Pon-Config $e @{}
  $r = Rescate-Con-Ajustes 'ajustes-manda-repo' @{ CopilotExe = 'copilotinexistentexq' } (@('-Repo', $e.Repo, '-Plantilla', $e.Plantilla) + $ArgsFix)
  Igual 'el fix sale con 0' 0 $r.Codigo
  Comprueba 'el arreglo hace su commit del lote' (Hay-Commit-Del-Lote $e) (Cola $r.Salida)
}

$Pruebas['ajustes: una clave de ajustes.json que el motor no conoce ni avisa ni falla; en el config.json del repo si avisa'] = {
  $e = Nuevo-Escenario 'ajustes-clave-rara'
  Config-Sin-Copilot $e
  $r = Rescate-Con-Ajustes 'ajustes-clave-rara' @{ CopilotExe = (Join-Path $falsos 'copilot.ps1'); Plantilla = 'D:\algo'; ClaveDeMigracion = 'x' } @('-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-SinBuild')
  Igual 'sale con 0' 0 $r.Codigo
  Comprueba 'ni un aviso de clave desconocida' ($r.Salida -notmatch 'clave desconocida') (Cola $r.Salida)
  Pon-Config $e @{ ClaveRara = 1 }
  $r2 = Rescate @('-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-SinBuild')
  Comprueba 'la del config.json del repo sigue avisando' ($r2.Salida -match "config.json: clave desconocida 'ClaveRara'") (Cola $r2.Salida)
}

$Pruebas['ajustes: un CopilotExe que no se puede lanzar para el fix y el plan antes de tocar el repo; el pre sigue con la busqueda por texto'] = {
  $e = Nuevo-Escenario 'ajustes-sin-copilot'
  Pon-Config $e @{ CopilotExe = 'copilotinexistentexq' }
  foreach ($modo in @('fix', 'plan')) {
    $r = Rescate @('-Modo', $modo, '-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-Paso', 'estructura', '-SinBuild', '-Auto', '-Si')
    Igual "$modo sale con 1" 1 $r.Codigo
    Comprueba "$modo dice que no puede lanzar y que es nada" ($r.Salida -match "No puedo lanzar 'copilotinexistentexq': aqui es nada\. Pon la ruta entera") (Cola $r.Salida)
    Comprueba "$modo no crea el worktree" (-not (Test-Path -LiteralPath $e.Wt))
    Igual "$modo no crea ninguna rama de rescate" '' ((GitEn $e.Repo @('branch', '--list', 'rescate/*')).Trim())
    Igual "$modo deja el repo sin cambios" '' ((GitEn $e.Repo @('status', '--porcelain')).Trim())
  }
  $orig = Join-Path (Join-Path $Dir 'ajustes-sin-copilot') 'original'
  Escribe $orig 'src/main/java/com/acme/Cargador.java' "package com.acme;`n`npublic class Cargador {`n    public static void main(String[] args) {`n    }`n}`n"
  $r = Rescate @('-Modo', 'pre', '-Repo', $e.Repo, '-Legacy', $orig)
  Igual 'pre sale con 0' 0 $r.Codigo
  Comprueba 'pre avisa y sigue solo con el texto' ($r.Salida -match "No puedo lanzar 'copilotinexistentexq'" -and $r.Salida -match 'sigo solo con la busqueda por texto') (Cola $r.Salida)
}

$Pruebas['ajustes: un nombre a secas que en el PATH solo es un .ps1 se lanza por su ruta'] = {
  $e = Nuevo-Escenario 'ajustes-ps1-en-path'
  $bin = Join-Path $Dir 'bin-ps1-en-path'
  Escribe $bin 'copilotfalsoxq.ps1' ("& '" + (Join-Path $falsos 'copilot.ps1') + "' @args`nexit `$LASTEXITCODE`n")
  Pon-Config $e @{ CopilotExe = 'copilotfalsoxq' }
  $pathAntes = $env:PATH
  $env:PATH = $bin + [System.IO.Path]::PathSeparator + $env:PATH
  try { $r = Rescate (@('-Repo', $e.Repo, '-Plantilla', $e.Plantilla) + $ArgsFix) }
  finally { $env:PATH = $pathAntes }
  Igual 'el fix sale con 0' 0 $r.Codigo
  Comprueba 'Copilot se ha llamado' (Test-Path -LiteralPath (Get-Ruta $e.Wt '.rescate/llamadas.log')) (Cola $r.Salida)
  Comprueba 'el arreglo hace su commit del lote' (Hay-Commit-Del-Lote $e) (Cola $r.Salida)
}

# ======================= EL REINTENTO Y EL FINAL =======================
$Pruebas['reintento: el detalle de la correccion lleva los hallazgos de la ruta nueva, con los paquetes que valen'] = {
  $e = Nuevo-Escenario 'reintento-ruta-nueva'
  # el Copilot de mentira mueve la clase a infrastructure/util: un subpaquete que la plantilla no tiene (alli: adapters).
  # Con el del M6 (que le pasa los lotes al de siempre) queda el prompt de cada llamada: despues de los dos intentos
  # vienen el consejo del atascado y el intento con el.
  Pon-Config $e @{ CopilotExe = (Join-Path $falsos 'copilot-m6.ps1') }
  $r = Rescate @('-Modo', 'fix', '-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-Paso', 'estructura', '-SinPlan', '-Lote', '1', '-Saltar', '1', '-Auto', '-Si', '-MaxIntentos', '2') 'mueve-a-infrastructure'
  $lotes = @(Llamadas-M6 $e 'lote')
  Comprueba 'dos intentos del lote' ($lotes.Count -ge 2) ("$($lotes.Count) lotes`n" + (Cola $r.Salida))
  $p = ''
  if ($lotes.Count -ge 2) { $p = Prompt-M6 $e $lotes[1] }
  Comprueba 'el prompt del segundo intento lleva la correccion' ($p -match '## CORRECCION') $p
  Comprueba 'y el hallazgo de la ruta nueva, con los paquetes que valen' ($p -match "- src/main/java/com/acme/life/infrastructure/util/\w+\.java - subpaquete 'infrastructure/util' no existe en la plantilla \(alli: [^)]*adapters[^)]*\)") $p
}

$Pruebas['final: con un paso atascado no dice que no quedan errores; con la pasada limpia, si'] = {
  $e = Nuevo-Escenario 'final-atascado'
  # solo estructura (y tests: con un Orden sin 'tests' el script cuenta mal los tests fallando) para que no haya otro paso pendiente
  Pon-Config $e @{ Orden = @('estructura', 'tests') }
  $r = Rescate @('-Modo', 'fix', '-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-Paso', 'estructura', '-SinPlan', '-Auto', '-Si', '-MaxIntentos', '1') 'nada'
  Igual 'sale con 2, como siempre' 2 $r.Codigo
  Comprueba 'no dice que no quedan errores' ($r.Salida -notmatch 'No quedan errores') (Cola $r.Salida)
  Comprueba 'dice que no quedan pasos que arregle solo' ($r.Salida -match 'No quedan pasos que el script pueda arreglar solo') (Cola $r.Salida)
  Comprueba 'y despues, lo que se ha quedado sin arreglar' ($r.Salida -match '(?s)No quedan pasos.*Se ha quedado sin arreglar') (Cola $r.Salida)
  $e2 = Nuevo-Escenario 'final-limpio'
  Pon-Config $e2 @{ Orden = @('estructura', 'tests') }
  $r2 = Rescate @('-Modo', 'fix', '-Repo', $e2.Repo, '-Plantilla', $e2.Plantilla, '-Paso', 'estructura', '-SinPlan', '-Auto', '-Si', '-MaxIntentos', '1')
  Igual 'la pasada limpia sale con 0' 0 $r2.Codigo
  Comprueba 'la pasada limpia dice que no quedan errores' ($r2.Salida -match 'No quedan errores') (Cola $r2.Salida)
  Comprueba 'y no habla de pasos sin arreglar' ($r2.Salida -notmatch 'No quedan pasos|Se ha quedado sin arreglar') (Cola $r2.Salida)
}

# ================== PARENT DISTINTO: LO DECIDE EL EQUIPO ==================
# Cambiar el parent (por ejemplo, a otra version mayor de Spring Boot) no es un arreglo mecanico: es un aviso de
# 'build', no un error, y -Todo no lo toca.
$Pruebas['parent distinto al de la plantilla: aviso de build (decision del equipo), sin error, en el informe, y -Todo no lo toca'] = {
  $e = Nuevo-Escenario 'parent-distinto'
  Escribe $e.Repo 'pom.xml' ($Pom -replace '(?s)(<parent>.*?<version>)3\.2\.0(</version>)', '${1}2.7.18${2}')
  [void](GitEn $e.Repo @('commit', '-q', '-am', 'parent viejo'))
  Pon-Config $e @{ Orden = @('build', 'estructura', 'tests') }
  [void](Rescate @('-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-SinBuild'))
  $h = @(Hallazgos $e.Repo | Where-Object { $_.Cat -eq 'build' })
  Igual 'build sin errores' 0 (Cuenta $h 'build')
  $av = @($h | Where-Object { $_.Sev -eq 'aviso' -and $_.Detalle -match 'parent distinto' })
  Comprueba 'el parent distinto es un aviso que dice que lo decide el equipo' ($av.Count -eq 1 -and $av[0].Detalle -match "aqui: '[^']*2\.7\.18'" -and $av[0].Detalle -match 'decision del equipo: no se cambia solo') (@($h | ForEach-Object { $_.Sev + ' ' + $_.Detalle }) -join ' / ')
  $inf = Lee $e.Repo '.rescate/diagnostico.md'
  Comprueba 'y sale en el informe' ($inf -match '\[aviso\] `pom\.xml` - parent distinto.*decision del equipo: no se cambia solo') $inf
  $r = Rescate @('-Modo', 'fix', '-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-Todo', '-SinPlan', '-Si', '-MaxIntentos', '1')
  Comprueba '-Todo sale con 0' ($r.Codigo -eq 0) ("$($r.Codigo) | " + (Cola $r.Salida))
  $log = Lee $e.Wt '.rescate/llamadas.log'
  Comprueba '-Todo no hace ningun lote de build' ($log -match "paso 'estructura'" -and $log -notmatch "paso 'build'") $log
  Comprueba 'y el pom sigue con el parent viejo' ((Lee $e.Wt 'pom.xml') -match '<version>2\.7\.18</version>') (Cola $r.Salida)
}

# ============= M6: ATASCADOS, RUIDO DE MAVEN, CONSEJO, REFLEXION Y -Todo =============
# Escenario con el Copilot del M6 (tests/falsos/copilot-m6.ps1), solo los pasos estructura y tests y sin reflexion,
# mas estos ajustes (nombre -> valor).
function Escenario-M6([string]$Nombre, [hashtable]$Mas = @{}) {
  $e = Nuevo-Escenario $Nombre
  $cfg = @{ CopilotExe = (Join-Path $falsos 'copilot-m6.ps1'); Orden = @('estructura', 'tests') }
  foreach ($k in $Mas.Keys) { $cfg[$k] = $Mas[$k] }
  Pon-Config $e $cfg
  return $e
}

# Lanza el fix de un paso con -SinPlan, -Auto y -Si, con estos intentos por lote y estos argumentos de mas.
function Fix-M6($E, [string]$PasoId, [int]$Intentos, [string[]]$Mas, [string]$Guion) {
  return (Rescate (@('-Modo', 'fix', '-Repo', $E.Repo, '-Plantilla', $E.Plantilla, '-Paso', $PasoId, '-SinPlan', '-Auto', '-Si', '-MaxIntentos', "$Intentos") + $Mas) $Guion)
}

# Las llamadas de un tipo que ha recibido el Copilot del M6 (lineas de .rescate/llamadas-m6.log del worktree).
function Llamadas-M6($E, [string]$Tipo) {
  $p = Get-Ruta $E.Wt '.rescate/llamadas-m6.log'
  if (-not (Test-Path -LiteralPath $p)) { return @() }
  return @([System.IO.File]::ReadAllLines($p) | Where-Object { $_ -match "^\d+ \| $Tipo \|" })
}

# Los lotes del Copilot del M6 que llevan Suelta.java.
function Lotes-Suelta($E) { return @(Llamadas-M6 $E 'lote' | Where-Object { $_ -match 'Suelta\.java' }) }

# El prompt que recibio una llamada del Copilot del M6 (por su linea de llamadas-m6.log).
function Prompt-M6($E, [string]$Linea) { return (Lee $E.Wt ('.rescate/falso-m6/' + ($Linea -split ' ')[0] + '.md')) }

# Desde 'Te toca decidir' hasta el final de la consola.
function Te-Toca([string]$Salida) { return ([regex]::Match($Salida, '(?s)Te toca decidir.*$')).Value }

$SueltaM6 = 'src/main/java/com/acme/life/Suelta.java'

$Pruebas['m6 atascados: se recuerdan entre pasadas; -Reintentar o un cambio del fichero los vuelven a intentar'] = {
  $e = Escenario-M6 'm6-atascados'
  $r = Fix-M6 $e 'estructura' 1 @() 'atasca;consejo-nada'
  Igual 'la primera pasada sale con 2' 2 $r.Codigo
  if (-not (Test-Path -LiteralPath (Get-Ruta $e.Wt '.rescate/atascados.json'))) { Comprueba 'hay atascados.json' $false (Cola $r.Salida); return }
  $j = @((Lee $e.Wt '.rescate/atascados.json') | ConvertFrom-Json | ForEach-Object { $_ })
  Igual 'atascados.json tiene un atascado' 1 $j.Count
  Comprueba 'con su paso, su fichero, el motivo y la huella del fichero' ($j[0].paso -eq 'estructura' -and $j[0].fichero -eq $SueltaM6 -and "$($j[0].motivo)" -match 'No has cambiado' -and "$($j[0].huella)".Length -ge 16) (ConvertTo-Json -InputObject $j -Compress)
  $n1 = (Lotes-Suelta $e).Count
  $r2 = Fix-M6 $e 'estructura' 1 @() 'atasca;consejo-nada'
  Igual 'la segunda pasada sale con 2' 2 $r2.Codigo
  Igual 'no llama a Copilot para el atascado' $n1 (Lotes-Suelta $e).Count
  Igual 'lo dice una vez' 1 ([regex]::Matches($r2.Salida, '1 ficheros atascados de antes: no los reintento \(usa -Reintentar\)')).Count
  Comprueba 'y sigue en la lista del final' ($r2.Salida -match ('\[estructura\] ' + [regex]::Escape($SueltaM6))) (Cola $r2.Salida)
  $r3 = Fix-M6 $e 'estructura' 1 @('-Reintentar') 'atasca;consejo-nada'
  $n3 = (Lotes-Suelta $e).Count
  Comprueba 'con -Reintentar se vuelve a intentar' ($n3 -gt $n1) "$n1 -> $n3"
  Comprueba 'y no dice que no lo reintenta' ($r3.Salida -notmatch 'no los reintento') (Cola $r3.Salida)
  Escribe $e.Wt $SueltaM6 ((Lee $e.Wt $SueltaM6) + "// arreglado a mano`n")
  $r4 = Fix-M6 $e 'estructura' 1 @() 'atasca;consejo-nada'
  $n4 = (Lotes-Suelta $e).Count
  Comprueba 'si el fichero ha cambiado, se intenta' ($n4 -gt $n3) (Cola $r4.Salida)
  $r5 = Fix-M6 $e 'estructura' 1 @() 'atasca;consejo-nada'
  Igual 'sin nada nuevo desde que se atasco, no se intenta' $n4 (Lotes-Suelta $e).Count
  # un lote del script (su commit no es ajeno) que cambia el atascado: se intenta por la huella
  Escribe $e.Wt $SueltaM6 ((Lee $e.Wt $SueltaM6) + "// tocado por otro lote`n")
  [void](GitEn $e.Wt @('add', '--', $SueltaM6))
  [void](GitEn $e.Wt @('commit', '-q', '-m', 'rescate(estructura): lote 9, hallazgos 1 a 1'))
  $r5b = Fix-M6 $e 'estructura' 1 @() 'atasca;consejo-nada'
  $n5 = (Lotes-Suelta $e).Count
  Comprueba 'si un lote del script cambia el fichero, se intenta' ($n5 -gt $n4) (Cola $r5b.Salida)
  # la pieza que le faltaba la arregla una persona en otro fichero, con un commit suyo: el atascado no cambia, pero se intenta
  Escribe $e.Wt 'docs/pieza-comun.md' "La pieza comun, hecha a mano.`n"
  [void](GitEn $e.Wt @('add', '--', 'docs/pieza-comun.md'))
  [void](GitEn $e.Wt @('commit', '-q', '-m', 'pieza comun hecha a mano'))
  $r6 = Fix-M6 $e 'estructura' 1 @() 'atasca;consejo-nada'
  Comprueba 'con un commit que no es del script desde que se atasco, se intenta' ((Lotes-Suelta $e).Count -gt $n5) (Cola $r6.Salida)
  Comprueba 'y no dice que no lo reintenta' ($r6.Salida -notmatch 'no los reintento') (Cola $r6.Salida)
}

$Pruebas['m6 atascados: un hallazgo sin fichero (no hay adaptador SFTP) tambien se recuerda'] = {
  $e = Escenario-M6 'm6-atascado-repo' @{ Orden = @('ficheros') }
  $r = Fix-M6 $e 'ficheros' 1 @() 'nada-sin-correccion;consejo-nada'
  Igual 'la primera pasada sale con 2' 2 $r.Codigo
  Comprueba 'el del adaptador SFTP queda atascado y sale como (repo)' ($r.Salida -match '\[ficheros\] \(repo\)') (Cola $r.Salida)
  $n1 = (Llamadas-M6 $e 'lote').Count
  $r2 = Fix-M6 $e 'ficheros' 1 @() 'nada-sin-correccion;consejo-nada'
  Comprueba 'la segunda pasada los recuerda todos' ($r2.Salida -match '3 ficheros atascados de antes: no los reintento') (Cola $r2.Salida)
  Igual 'y no llama a Copilot para ninguno' $n1 (Llamadas-M6 $e 'lote').Count
}

$Pruebas['m6 atascados: si build se atasca y el proyecto no compila, -Todo para con la lista y Te toca decidir'] = {
  $e = Escenario-M6 'm6-build' @{ Orden = @('build', 'estructura') }
  Escribe $e.Repo $SueltaM6 ((Lee $e.Repo $SueltaM6) + "// NO_COMPILA`n")
  [void](GitEn $e.Repo @('add', '--', $SueltaM6))
  [void](GitEn $e.Repo @('commit', '-q', '-m', 'no compila'))
  $r = Rescate @('-Modo', 'fix', '-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-Todo', '-SinPlan', '-Si', '-MaxIntentos', '1') 'atasca;consejo-persona'
  Igual 'sale con 2' 2 $r.Codigo
  Comprueba 'dice que no compila' ($r.Salida -match 'no compila') (Cola $r.Salida)
  Comprueba 'lista el atascado de build' ($r.Salida -match ('\[build\] ' + [regex]::Escape($SueltaM6))) (Cola $r.Salida)
  Comprueba 'y la duda de persona en Te toca decidir' ((Te-Toca $r.Salida) -match 'OPCION-C-MARCA') (Cola $r.Salida)
}

$Pruebas['m6 ruido: lo que deja Maven fuera de target no entra en los commits; lo que crea la IA, si'] = {
  $e = Escenario-M6 'm6-ruido' @{ MvnExe = (Join-Path $falsos 'mvn-m6.ps1') }
  $r = Fix-M6 $e 'estructura' 1 @() 'crea-fichero'
  Igual 'sale con 0' 0 $r.Codigo
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  $todos = GitEn $e.Wt @('log', '--name-only', '--format=')
  Comprueba 'ningun commit lleva output/x.csv' ($todos -notmatch 'output/x\.csv') $todos
  Comprueba 'el commit del lote lleva lo que ha creado la IA' ((GitEn $e.Wt @('show', '--name-only', '--format=', 'HEAD')) -match 'output/de-la-ia\.csv') $todos
  Igual 'el worktree queda limpio' '' (GitEn $e.Wt @('status', '--porcelain'))
  Comprueba 'y sin output/x.csv' (-not (Test-Path -LiteralPath (Get-Ruta $e.Wt 'output/x.csv')))
}

$Pruebas['m6 consejo del plan: la duda de codigo va al plan en ## Decisiones y la de persona a Te toca decidir'] = {
  $e = Escenario-M6 'm6-plan-dudas'
  $r = Rescate @('-Modo', 'fix', '-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-Paso', 'estructura', '-Auto', '-Si', '-MaxIntentos', '1', '-Modelo', 'modelo-x', '-ModeloDudas', 'modelo-fuerte') 'duda-plan;consejo-mixto'
  Igual 'sale con 0' 0 $r.Codigo
  $c = @(Llamadas-M6 $e 'consejo')
  Igual 'una llamada de consejo' 1 $c.Count
  if ($c.Count -ne 1) { return }
  Comprueba 'con el modelo de las dudas y esfuerzo max' ($c[0] -match '--model=modelo-fuerte --effort=max') $c[0]
  Comprueba 'que nombra el fichero de la duda' ($c[0] -match 'Suelta\.java') $c[0]
  $pc = Prompt-M6 $e $c[0]
  Comprueba 'el consejo recibe las dudas y el plan' ($pc -match 'DUDA-PLAN-MARCA' -and $pc -match 'plan-estructura\.md') $pc
  $plan = Lee $e.Wt '.rescate/plan-estructura.md'
  $dec = ([regex]::Match($plan, '(?s)## Decisiones(.*)$')).Groups[1].Value
  Comprueba 'el plan lleva ## Decisiones con la elegida y su porque' ($dec -match 'OPCION-B-MARCA' -and $dec -match 'PORQUE-MARCA') $plan
  Comprueba 'y no la duda de persona' ($dec -notmatch 'OPCION-F-MARCA|DUDA-PERSONA-MARCA') $dec
  $l = @(Llamadas-M6 $e 'lote')
  Comprueba 'el lote recibe la decision' ($l.Count -ge 1 -and (Prompt-M6 $e $l[0]) -match 'OPCION-B-MARCA') ($l -join ' / ')
  $d = Lee $e.Wt '.rescate/decisiones.md'
  Comprueba 'decisiones.md: la duda, las 3 opciones, la elegida, el porque, el tipo y donde se aplico' ($d -match 'DUDA-MARCA' -and $d -match 'OPCION-A-MARCA' -and $d -match '2\. OPCION-B-MARCA[^\r\n]*\(elegida\)' -and $d -match 'OPCION-C-MARCA' -and $d -match 'PORQUE-MARCA' -and $d -match 'Tipo: codigo' -and $d -match 'Aplicada: en el plan') $d
  Comprueba 'y la de persona' ($d -match 'DUDA-PERSONA-MARCA' -and $d -match 'Tipo: persona' -and $d -match 'Aplicada: no, la decide una persona') $d
  $toca = Te-Toca $r.Salida
  Comprueba 'Te toca decidir: la duda de persona con la recomendada y su porque' ($toca -match 'DUDA-PERSONA-MARCA' -and $toca -match 'OPCION-F-MARCA' -and $toca -match 'PORQUE-PERSONA-MARCA') (Cola $r.Salida)
  Comprueba 'con la ruta de decisiones.md' ($toca -match 'decisiones\.md') $toca
  Comprueba 'la de codigo no sale ahi' ($toca -notmatch 'OPCION-B-MARCA') $toca
}

$Pruebas['m6 consejo del atascado: si es de codigo, un intento mas con la instruccion y, si pasa, commit'] = {
  $e = Escenario-M6 'm6-atascado-codigo'
  $r = Fix-M6 $e 'estructura' 1 @('-Modelo', 'modelo-x', '-ModeloB', 'modelo-b', '-ModeloDudas', 'modelo-fuerte') 'atasca;consejo-codigo'
  Igual 'sale con 0: el consejo lo desatasca' 0 $r.Codigo
  $s = Lotes-Suelta $e
  Igual 'Suelta va en el lote, solo, con el de reserva y con el consejo' 4 $s.Count
  if ($s.Count -ne 4) { return }
  Comprueba 'el de reserva va antes del consejo' ($s[2] -match '--model=modelo-b') $s[2]
  Comprueba 'el intento del consejo va con -Modelo' ($s[3] -match '--model=modelo-x') $s[3]
  $p = Prompt-M6 $e $s[3]
  Comprueba 'y lleva la instruccion en el prompt' ($p -match '## Consejo' -and $p -match 'OPCION-B-MARCA' -and $p -match 'PORQUE-MARCA') $p
  $c = @(Llamadas-M6 $e 'consejo')
  Igual 'una llamada de consejo' 1 $c.Count
  if ($c.Count -eq 1) {
    $pc = Prompt-M6 $e $c[0]
    Comprueba 'el consejo recibe el fichero, el paso, los hallazgos y los motivos' ($c[0] -match '--model=modelo-fuerte' -and $pc -match 'Suelta\.java' -and $pc -match "paso 'estructura'" -and $pc -match 'No has cambiado ningun fichero') $pc
  }
  Igual 'estructura queda a 0' 0 (Cuenta (Hallazgos $e.Wt) 'estructura')
  $log = GitEn $e.Wt @('log', '--format=%s')
  Igual 'dos commits de lote' 2 @($log -split "`n" | Where-Object { $_ -match '^rescate\(estructura\)' }).Count
  $h = GitEn $e.Wt @('log', '-1', '--format=%h', '--', 'src/main/java/com/acme/life/application/usecases/Suelta.java')
  $d = Lee $e.Wt '.rescate/decisiones.md'
  Comprueba 'decisiones.md dice que se aplico y en que commit' ($d -match ('Aplicada: si, commit ' + $h)) $d
  Comprueba 'no queda nada atascado' ($r.Salida -notmatch 'Se ha quedado sin arreglar') (Cola $r.Salida)
}

$Pruebas['m6 consejo del atascado: si es de persona, o si su intento no pasa, queda atascado con las 3 opciones'] = {
  $e = Escenario-M6 'm6-atascado-persona'
  $r = Fix-M6 $e 'estructura' 1 @() 'atasca;consejo-persona'
  Igual 'sale con 2' 2 $r.Codigo
  Igual 'no hay intento con el consejo' 2 (Lotes-Suelta $e).Count
  $a = Lee $e.Wt '.rescate/atascados.md'
  Comprueba 'atascados.md lleva las 3 opciones y la recomendada con su porque' ($a -match 'OPCION-A-MARCA' -and $a -match 'OPCION-B-MARCA' -and $a -match 'OPCION-C-MARCA' -and $a -match 'recomendada: 3' -and $a -match 'PORQUE-MARCA') $a
  $j = @((Lee $e.Wt '.rescate/atascados.json') | ConvertFrom-Json | ForEach-Object { $_ })
  Comprueba 'atascados.json tambien' ($j.Count -eq 1 -and $j[0].consejo.elegida -eq 3 -and $j[0].consejo.tipo -eq 'persona' -and @($j[0].consejo.opciones).Count -eq 3) (ConvertTo-Json -InputObject $j -Compress -Depth 5)
  $toca = Te-Toca $r.Salida
  Comprueba 'y sale en Te toca decidir' ($toca -match 'DUDA-MARCA' -and $toca -match 'OPCION-C-MARCA') (Cola $r.Salida)
  $e2 = Escenario-M6 'm6-atascado-consejo-falla'
  $r2 = Fix-M6 $e2 'estructura' 1 @() 'atasca-siempre;consejo-codigo'
  Igual 'si el intento del consejo no pasa, sale con 2' 2 $r2.Codigo
  Igual 'hay un intento con el consejo' 3 (Lotes-Suelta $e2).Count
  Comprueba 'queda atascado con las opciones' ((Lee $e2.Wt '.rescate/atascados.md') -match 'OPCION-B-MARCA') (Cola $r2.Salida)
  Comprueba 'y decisiones.md dice que no paso' ((Lee $e2.Wt '.rescate/decisiones.md') -match 'Aplicada: se intento y no paso') (Cola $r2.Salida)
}

$Pruebas['m6 consejo que no vale: se repite una vez con el motivo y, si sigue mal, se sigue sin consejo'] = {
  $e = Escenario-M6 'm6-consejo-dos'
  $r = Fix-M6 $e 'estructura' 1 @('-Modelo', 'modelo-x') 'atasca;consejo-dos'
  Igual 'sale con 2, como sin consejo' 2 $r.Codigo
  $c = @(Llamadas-M6 $e 'consejo')
  Igual 'dos llamadas de consejo' 2 $c.Count
  if ($c.Count -eq 2) {
    Comprueba 'el modelo de las dudas es por defecto el de -Modelo' ($c[0] -match '--model=modelo-x --effort=max') $c[0]
    $p2 = Prompt-M6 $e $c[1]
    Comprueba 'la segunda lleva el motivo' ($p2 -match '## CORRECCION' -and $p2 -match 'exactamente 3 opciones') $p2
  }
  Comprueba 'dice que sigue sin consejo' ($r.Salida -match 'sin consejo') (Cola $r.Salida)
  Igual 'sin intento con el consejo' 2 (Lotes-Suelta $e).Count
  $e2 = Escenario-M6 'm6-consejo-elegida'
  $r2 = Fix-M6 $e2 'estructura' 1 @() 'atasca;consejo-elegida-4'
  Igual 'con elegida 4 el reintento vale y lo desatasca: sale con 0' 0 $r2.Codigo
  $c2 = @(Llamadas-M6 $e2 'consejo')
  Igual 'dos llamadas de consejo' 2 $c2.Count
  if ($c2.Count -eq 2) { Comprueba 'el motivo dice que elegida va de 1 a 3' ((Prompt-M6 $e2 $c2[1]) -match 'elegida tiene que ser 1, 2 o 3') }
}

$Pruebas['m6 esfuerzo: si Copilot no admite max, baja a xhigh; ModeloDudas y EsfuerzoDudas tambien en config.json'] = {
  $e = Escenario-M6 'm6-sin-max'
  $r = Fix-M6 $e 'estructura' 1 @('-ModeloDudas', 'modelo-fuerte') 'atasca;consejo-codigo;sin-max'
  Igual 'sale con 0' 0 $r.Codigo
  $x = @(Llamadas-M6 $e 'rechazo')
  $c = @(Llamadas-M6 $e 'consejo')
  Comprueba 'max se rechaza una vez' ($x.Count -eq 1 -and $x[0] -match '--effort=max') ($x -join ' / ')
  Comprueba 'y el consejo va con xhigh' ($c.Count -eq 1 -and $c[0] -match '--model=modelo-fuerte --effort=xhigh') ($c -join ' / ')
  Comprueba 'lo dice' ($r.Salida -match "esfuerzo 'max'.*'xhigh'") (Cola $r.Salida)
  $e2 = Escenario-M6 'm6-dudas-config' @{ ModeloDudas = 'modelo-de-config'; EsfuerzoDudas = 'high' }
  $r2 = Fix-M6 $e2 'estructura' 1 @() 'atasca;consejo-codigo'
  $c2 = @(Llamadas-M6 $e2 'consejo')
  Comprueba 'config.json manda el modelo y el esfuerzo del consejo' ($c2.Count -eq 1 -and $c2[0] -match '--model=modelo-de-config --effort=high') (($c2 -join ' / ') + ' | ' + (Cola $r2.Salida))
}

$Pruebas['m6 todo: -Todo sin contrato hace primero el pre y sigue; con contrato, no'] = {
  $orig = Join-Path (Join-Path $Dir 'm6-todo-original') 'original'
  Escribe $orig 'src/main/java/com/acme/CargaJob.java' "package com.acme;`n`npublic class CargaJob {`n    Object job() { return new JobBuilder(`"cargaPolizas`", null); }`n}`n"
  $args3 = { param($E) @('-Modo', 'fix', '-Repo', $E.Repo, '-Plantilla', $E.Plantilla, '-Legacy', $orig, '-Paso', 'estructura', '-SinPlan', '-Todo', '-Si', '-MaxIntentos', '1') }
  $e = Escenario-M6 'm6-todo'
  $r = Rescate (& $args3 $e) ''
  Igual 'sale con 0' 0 $r.Codigo
  Comprueba 'hace el pre en el worktree' (Test-Path -LiteralPath (Get-Ruta $e.Wt '.rescate/contrato.json')) (Cola $r.Salida)
  Igual 'con IA: una llamada del pre' 1 (Llamadas-M6 $e 'pre').Count
  if (Test-Path -LiteralPath (Get-Ruta $e.Wt '.rescate/contrato.json')) { Comprueba 'el contrato lleva el job del original' ((Lee $e.Wt '.rescate/contrato.json') -match 'cargaPolizas') }
  Comprueba 'dice que la lista de jobs no la ha revisado nadie y donde esta' ($r.Salida -match 'no la ha revisado nadie' -and $r.Salida -match 'contrato\.json') (Cola $r.Salida)
  Comprueba 'y sigue con el arreglo' (Hay-Commit-Del-Lote $e) (Cola $r.Salida)
  $e2 = Escenario-M6 'm6-todo-con-contrato'
  $hecho = '{ "generado": "a mano", "jobs": [] }'
  Escribe $e2.Repo '.rescate/contrato.json' $hecho
  $r2 = Rescate (& $args3 $e2) ''
  Igual 'con contrato sale con 0' 0 $r2.Codigo
  Igual 'y no hay pre' 0 (Llamadas-M6 $e2 'pre').Count
  if (Test-Path -LiteralPath (Get-Ruta $e2.Wt '.rescate/contrato.json')) { Igual 'el contrato no cambia' $hecho (Lee $e2.Wt '.rescate/contrato.json') }
  Comprueba 'ni habla de la lista de jobs' ($r2.Salida -notmatch 'no la ha revisado nadie') (Cola $r2.Salida)
  $e3 = Escenario-M6 'm6-todo-sinia'
  $r3 = Rescate ((& $args3 $e3) + '-SinIA') ''
  Comprueba 'con -SinIA el pre se hace sin Copilot' ($r3.Codigo -eq 0 -and (Test-Path -LiteralPath (Get-Ruta $e3.Wt '.rescate/contrato.json')) -and (Llamadas-M6 $e3 'pre').Count -eq 0) (Cola $r3.Salida)
}

$Pruebas['m6 sin -Auto: las dudas del plan se preguntan como hoy, sin consejo'] = {
  $e = Escenario-M6 'm6-sin-auto'
  $r = Rescate @('-Modo', 'fix', '-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-Paso', 'estructura', '-Si', '-MaxIntentos', '1') 'duda-plan;consejo-codigo'
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'ninguna llamada de consejo' 0 (Llamadas-M6 $e 'consejo').Count
  if (Test-Path -LiteralPath (Get-Ruta $e.Wt '.rescate/plan-estructura.md')) { Comprueba 'el plan no lleva ## Decisiones' ((Lee $e.Wt '.rescate/plan-estructura.md') -notmatch '## Decisiones') }
  else { Comprueba 'hay plan' $false (Cola $r.Salida) }
}

$Pruebas['m6 reflexion: tras un intento que no pasa hay una reflexion y el siguiente la lleva en la CORRECCION'] = {
  $e = Escenario-M6 'm6-reflexion' @{ Reflexionar = $true; Orden = @('hexagonal', 'tests') }
  # el primer intento crea un puerto sin Javadoc (no pasa por calidad) y el segundo, con la correccion, pasa
  $r = Fix-M6 $e 'hexagonal' 2 @('-ModeloDudas', 'modelo-fuerte') 'sin-javadoc'
  Igual 'sale con 0' 0 $r.Codigo
  $rf = @(Llamadas-M6 $e 'reflexion')
  Igual 'una reflexion' 1 $rf.Count
  if ($rf.Count -ne 1) { return }
  Comprueba 'con el modelo de las dudas y max' ($rf[0] -match '--model=modelo-fuerte --effort=max') $rf[0]
  $pr = Prompt-M6 $e $rf[0]
  Comprueba 'recibe el objetivo, los hallazgos, los NO PASA, el diff y lo nuevo' ($pr -match 'Elimina las dependencias prohibidas' -and $pr -match 'Cliente\.java' -and $pr -match 'anade hallazgos de calidad' -and $pr -match '(?m)^-import org\.springframework' -and $pr -match 'ClientePort\.java') $pr
  Comprueba 'deja su fichero' (Test-Path -LiteralPath (Get-Ruta $e.Wt '.rescate/reflexion-hexagonal-1-1.md'))
  $l = @(Llamadas-M6 $e 'lote')
  Igual 'dos intentos' 2 $l.Count
  if ($l.Count -eq 2) {
    $corr = ([regex]::Match((Prompt-M6 $e $l[1]), '(?s)## CORRECCION.*$')).Value
    Comprueba 'el segundo lleva la reflexion en la CORRECCION, con los NO PASA' ($corr -match 'REFLEXION-MARCA-hexagonal-1-1' -and $corr -match 'anade hallazgos de calidad') $corr
    Comprueba 'el primero no lleva ninguna' ((Prompt-M6 $e $l[0]) -notmatch 'REFLEXION-MARCA')
  }
  Comprueba 'decisiones.md apunta la reflexion' ((Lee $e.Wt '.rescate/decisiones.md') -match 'REFLEXION-MARCA-hexagonal-1-1')
}

$Pruebas['m6 reflexion: las reflexiones viajan con el fichero al modelo de reserva y al consejo final'] = {
  $e = Escenario-M6 'm6-reflexion-reserva' @{ Reflexionar = $true }
  $r = Fix-M6 $e 'estructura' 1 @('-ModeloB', 'modelo-b') 'atasca;consejo-nada'
  Igual 'sale con 2' 2 $r.Codigo
  $b = @(Lotes-Suelta $e | Where-Object { $_ -match '--model=modelo-b' })
  Igual 'un intento con el de reserva' 1 $b.Count
  if ($b.Count -ne 1) { return }
  $kb = [int](($b[0] -split ' ')[0])
  $rf = @(Llamadas-M6 $e 'reflexion')
  $antes = @($rf | Where-Object { [int](($_ -split ' ')[0]) -lt $kb } | ForEach-Object { ($_ -split ' \| ')[-1].Trim() })
  Igual 'dos reflexiones antes: la del lote entero y la de Suelta sola' 2 $antes.Count
  $pb = Prompt-M6 $e $b[0]
  Comprueba 'el de reserva las lleva' ($pb -match 'Lo que ya se intento y por que fallo' -and @($antes | Where-Object { $pb -notmatch ('REFLEXION-MARCA-' + $_) }).Count -eq 0) $pb
  $c = @(Llamadas-M6 $e 'consejo')
  if ($c.Count -ge 1) {
    $pc = Prompt-M6 $e $c[0]
    $todas = @($rf | ForEach-Object { ($_ -split ' \| ')[-1].Trim() })
    Comprueba 'el consejo final lleva todas las del fichero' ($todas.Count -eq 3 -and $pc -match 'Lo que ya se intento y por que fallo' -and @($todas | Where-Object { $pc -notmatch ('REFLEXION-MARCA-' + $_) }).Count -eq 0) $pc
  }
  else { Comprueba 'hay consejo final' $false (Cola $r.Salida) }
}

$Pruebas['m6 reflexion: sin las cuatro secciones se sigue sin ella; con Reflexionar en false no hay llamada'] = {
  $e = Escenario-M6 'm6-reflexion-mala' @{ Reflexionar = $true }
  $r = Fix-M6 $e 'estructura' 2 @() 'nada-sin-correccion;reflexion-mala'
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'una reflexion' 1 (Llamadas-M6 $e 'reflexion').Count
  $l = @(Llamadas-M6 $e 'lote')
  if ($l.Count -eq 2) {
    $p2 = Prompt-M6 $e $l[1]
    Comprueba 'el segundo intento va con la CORRECCION y sin la reflexion' ($p2 -match '## CORRECCION' -and $p2 -notmatch 'REFLEXION-MARCA') $p2
  }
  else { Comprueba 'dos intentos' $false ($l -join ' / ') }
  Comprueba 'lo dice' ($r.Salida -match 'sigo sin ella') (Cola $r.Salida)
  $e2 = Escenario-M6 'm6-sin-reflexion' @{ Reflexionar = $false }
  $r2 = Fix-M6 $e2 'estructura' 2 @() 'nada-sin-correccion'
  Igual 'con Reflexionar en false sale con 0' 0 $r2.Codigo
  Igual 'y no hay ninguna reflexion' 0 (Llamadas-M6 $e2 'reflexion').Count
}

# ============= M7: UN LOTE NO CAMBIA COMO SE TRATAN LOS ERRORES =============
# CalidadMuestra tiene dos catch; el segundo sigue tras el error. El script cuenta los catch de src/main/java
# (sin comentarios ni textos) antes y despues de cada lote: si bajan, el lote no pasa.
$CalidadM7 = 'src/main/java/com/acme/life/application/usecases/CalidadMuestra.java'
function Catch-En($E, [string]$Rel) { return ([regex]::Matches((Lee $E.Wt $Rel), '\bcatch\s*\(')).Count }

$Pruebas['m7 catch: un lote que quita un catch no pasa y la correccion dice en que fichero'] = {
  $e = Escenario-M6 'm7-quita-catch'
  $r = Fix-M6 $e 'estructura' 2 @() 'quita-catch'
  Igual 'sale con 0' 0 $r.Codigo
  Comprueba 'el primer intento no pasa por el catch quitado' ($r.Salida -match 'NO PASA: Has quitado 1 catch \(2 -> 1\)\. El original sigue tras esos errores: manten el mismo tratamiento\.') (Cola $r.Salida)
  $lotes = @(Llamadas-M6 $e 'lote')
  Igual 'dos intentos' 2 $lotes.Count
  $p = Prompt-M6 $e $lotes[1]
  Comprueba 'la correccion dice en que fichero bajo' ($p -match 'CalidadMuestra\.java - catch: 2 -> 1') $p
  Igual 'el catch sigue en el fichero' 2 (Catch-En $e $CalidadM7)
}

$Pruebas['m7 catch: llevar el catch a un fichero nuevo pasa (la cuenta es de todo el repo)'] = {
  $e = Escenario-M6 'm7-mueve-catch'
  $r = Fix-M6 $e 'estructura' 1 @() 'mueve-catch'
  Igual 'sale con 0' 0 $r.Codigo
  Comprueba 'no dice que se ha quitado un catch' ($r.Salida -notmatch 'Has quitado') (Cola $r.Salida)
  Igual 'un solo intento' 1 @(Llamadas-M6 $e 'lote').Count
  Igual 'CalidadMuestra se queda con 1 catch' 1 (Catch-En $e $CalidadM7)
  Igual 'y la clase nueva lleva el otro, en el commit' 1 (Catch-En $e 'src/main/java/com/acme/life/application/usecases/TamanoSeguro.java')
  Comprueba 'la clase nueva entra en el commit' ((GitEn $e.Wt @('log', '-1', '--name-only', '--format=')) -match 'TamanoSeguro\.java') ''
}

$Pruebas['m7 catch: un catch en un comentario o en un texto no cuenta'] = {
  $e = Escenario-M6 'm7-catch-comentario'
  $r = Fix-M6 $e 'estructura' 1 @() 'catch-en-comentario'
  # el primer lote se deshace; el escalon siguiente parte de su arbol (compilaba y bajaba los hallazgos) con la correccion, y ahi pasa
  Comprueba 'el primer lote se deshace' ($r.Salida -match 'Lote 1 DESHECHO') (Cola $r.Salida)
  Comprueba 'cuenta 2 -> 1: el comentario y el texto no son catch' ($r.Salida -match 'Has quitado 1 catch \(2 -> 1\)') (Cola $r.Salida)
}

$Pruebas['m7 catch: el prompt del lote ya no dice que se relance, y el del plan dice que tratar errores es comportamiento'] = {
  $e = Escenario-M6 'm7-textos'
  [void](Rescate @('-Modo', 'fix', '-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-Paso', 'estructura', '-Auto', '-Si', '-MaxIntentos', '1') '')
  $plan = Prompt-M6 $e @(Llamadas-M6 $e 'plan')[0]
  Comprueba 'el plan dice que capturar o propagar es comportamiento y no lo cambia' ($plan -match 'capturar y seguir, o propagar\) es comportamiento: el plan no lo cambia') $plan
  $lote = Prompt-M6 $e @(Llamadas-M6 $e 'lote')[0]
  Comprueba 'el lote no dice que se relance' ($lote -notmatch 'se relanza') $lote
  Comprueba 'el lote dice que no se relance ni se quite el catch' ($lote -match 'No la relances ni quites el catch: cambia el comportamiento\.') $lote
}

# migracion.ps1 lanza el fix sin -ModeloB: el modelo de reserva tambien sale de ajustes.json (o de config.json), y el
# parametro manda.
$Pruebas['m7 ModeloB: sin el parametro, el reintento con el modelo de reserva usa el de ajustes.json; con el, el parametro'] = {
  $mas = @('-Modelo', 'modelo-x')
  $e = Escenario-M6 'm7-modelob-ajustes'
  $a = @('-Modo', 'fix', '-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-Paso', 'estructura', '-SinPlan', '-Auto', '-Si', '-MaxIntentos', '1')
  $r = Rescate-Con-Ajustes 'm7-modelob-ajustes' @{ ModeloB = 'modelo-b-ajustes' } ($a + $mas) 'atasca;consejo-nada'
  $s = Lotes-Suelta $e
  Comprueba 'Suelta se reintenta con el modelo de reserva de ajustes.json' (@($s | Where-Object { $_ -match '--model=modelo-b-ajustes' }).Count -eq 1) (($s -join ' / ') + ' | ' + (Cola $r.Salida))
  Comprueba 'la cabecera lo dice' ($r.Salida -match 'modelo de reserva: modelo-b-ajustes') (Cola $r.Salida)
  $e2 = Escenario-M6 'm7-modelob-param'
  $a2 = @('-Modo', 'fix', '-Repo', $e2.Repo, '-Plantilla', $e2.Plantilla, '-Paso', 'estructura', '-SinPlan', '-Auto', '-Si', '-MaxIntentos', '1')
  [void](Rescate-Con-Ajustes 'm7-modelob-param' @{ ModeloB = 'modelo-b-ajustes' } ($a2 + $mas + @('-ModeloB', 'modelo-b-param')) 'atasca;consejo-nada')
  $s2 = Lotes-Suelta $e2
  Comprueba 'con -ModeloB manda el parametro' ((@($s2 | Where-Object { $_ -match '--model=modelo-b-param' }).Count -eq 1) -and (@($s2 | Where-Object { $_ -match 'modelo-b-ajustes' }).Count -eq 0)) ($s2 -join ' / ')
}

# El paso build no sube el parent por su cuenta: es decision del equipo (el parent distinto ya es un aviso).
$Pruebas['m7 build: el prompt del paso build no manda cambiar el parent; si hace falta otro, es una duda'] = {
  $e = Escenario-M6 'm7-build-texto' @{ Orden = @('build', 'estructura', 'tests') }
  Escribe $e.Repo 'pom.xml' ($Pom -replace '<java.version>21</java.version>', '<java.version>1.8</java.version>')
  [void](GitEn $e.Repo @('commit', '-q', '-am', 'java 8'))
  $r = Fix-M6 $e 'build' 1 @() 'consejo-nada'
  $l = @(Llamadas-M6 $e 'lote')
  Comprueba 'hay un lote de build' ($l.Count -ge 1) (Cola $r.Salida)
  if ($l.Count -eq 0) { return }
  $p = Prompt-M6 $e $l[0]
  Comprueba 'no dice que use el mismo parent que la plantilla' ($p -notmatch 'mismo parent') $p
  Comprueba 'dice que no cambie el parent y que, si hace falta otro, lo apunte como duda' ($p -match 'sin cambiar el parent: si hace falta otro, apuntalo como duda') $p
}

# Con un Orden sin 'tests' y los tests activos no hay cuenta de antes: la puerta de tests no compara (antes comparaba
# con nada y no pasaba ningun lote).
$Pruebas['m7 orden sin tests: la puerta de tests solo compara si hay cuenta de antes'] = {
  $e = Nuevo-Escenario 'm7-orden-sin-tests'
  Pon-Config $e @{ Orden = @('estructura') }
  $r = Rescate @('-Modo', 'fix', '-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-Paso', 'estructura', '-SinPlan', '-Auto', '-Si', '-MaxIntentos', '1')
  Comprueba 'sale con 0' ($r.Codigo -eq 0) ("$($r.Codigo) | " + (Cola $r.Salida))
  Comprueba 'no dice que hay mas tests fallando' ($r.Salida -notmatch 'Hay mas tests fallando') (Cola $r.Salida)
}

# ===== M8: EL MODELO VE LO QUE HA ROTO Y UN INTENTO CORTADO NO ENTRA EN LA FOTO =====
# Con 'estructura' antes de 'ficheros', el lote de 'ficheros' del guion mueve-a-util lleva LeerFichero a un subpaquete que
# la plantilla no tiene: estructura pasa de 2 hallazgos (Suelta y PolizaService, que ya estaban) a 3.
$LeerM8 = 'src/main/java/com/acme/life/application/usecases/LeerFichero.java'
$LeerMovidoM8 = 'src/main/java/com/acme/life/infrastructure/util/LeerFichero.java'

# La CORRECCION de un prompt: desde su titulo hasta el final.
function Correccion-De([string]$Prompt) { return ([regex]::Match($Prompt, '(?s)## CORRECCION.*$')).Value }

# Lo que ha visto el Copilot del M6 en .rescate/intento-en-curso.json en cada lote (guion ve-marca), una linea por llamada.
function Marcas-Vistas($E) { return @([System.IO.File]::ReadAllLines((Get-Ruta $E.Wt '.rescate/marca-vista.log'))) }

$Pruebas['m8 detalle: lo que el intento ha roto en un paso anterior sale en la correccion; lo que ya estaba, no'] = {
  $e = Escenario-M6 'm8-detalle' @{ Orden = @('estructura', 'ficheros') }
  $r = Fix-M6 $e 'ficheros' 2 @() 'mueve-a-util'
  Comprueba 'el primer intento no pasa por haber empeorado estructura' ($r.Salida -match "NO PASA: Has empeorado el paso anterior 'estructura' \(2 -> 3 hallazgos\)\.") (Cola $r.Salida)
  $lotes = @(Llamadas-M6 $e 'lote')
  Comprueba 'hay un segundo intento' ($lotes.Count -ge 2) (Cola $r.Salida)
  if ($lotes.Count -lt 2) { return }
  $c = Correccion-De (Prompt-M6 $e $lotes[1])
  Comprueba 'la correccion cuenta lo que ha empeorado' ($c -match "Has empeorado el paso anterior 'estructura' \(2 -> 3 hallazgos\)") $c
  Comprueba 'y lista el hallazgo nuevo de estructura con su fichero' ($c -match ('(?m)^  - ' + [regex]::Escape($LeerMovidoM8) + " - subpaquete 'infrastructure/util' no existe en la plantilla")) $c
  Comprueba 'sin los de estructura que ya estaban antes del intento' ($c -notmatch 'Suelta\.java' -and $c -notmatch 'PolizaService\.java') $c
}

$Pruebas['m8 detalle: si ningun paso anterior empeora, el detalle no lleva hallazgos de otros pasos'] = {
  $e = Escenario-M6 'm8-detalle-nada' @{ Orden = @('estructura', 'ficheros') }
  $r = Fix-M6 $e 'ficheros' 2 @() 'nada-sin-correccion'
  $lotes = @(Llamadas-M6 $e 'lote')
  Comprueba 'hay un segundo intento' ($lotes.Count -ge 2) (Cola $r.Salida)
  if ($lotes.Count -lt 2) { return }
  $c = Correccion-De (Prompt-M6 $e $lotes[1])
  Comprueba 'la correccion no dice que un paso anterior haya empeorado' ($c -notmatch 'Has empeorado') $c
  Comprueba 'ni lista hallazgos de estructura' ($c -notmatch 'Suelta\.java|PolizaService\.java') $c
}

$Pruebas['m8 marca: cada intento tiene su marca con el commit de partida y, al acabar el lote, pase o no, ya no esta'] = {
  $e = Escenario-M6 'm8-marca'
  $r = Fix-M6 $e 'estructura' 2 @() 've-marca;nada-sin-correccion'
  Igual 'sale con 0' 0 $r.Codigo
  $partida = GitEn $e.Wt @('rev-parse', 'HEAD~1')
  $v = @(Marcas-Vistas $e)
  Igual 'los dos intentos ven la marca' 2 $v.Count
  foreach ($linea in $v) {
    $m = $null
    try { $m = $linea | ConvertFrom-Json } catch { }
    Comprueba 'la marca dice el paso, el lote y el commit de partida' ($m -and $m.paso -eq 'estructura' -and $m.lote -eq 1 -and $m.commit -eq $partida) $linea
  }
  Comprueba 'el lote pasa: la marca ya no esta' (-not (Test-Path -LiteralPath (Get-Ruta $e.Wt '.rescate/intento-en-curso.json'))) (Cola $r.Salida)
  $e2 = Escenario-M6 'm8-marca-no-pasa'
  $r2 = Fix-M6 $e2 'estructura' 1 @() 'atasca-siempre;ve-marca;consejo-nada'
  Igual 'con un atascado sale con 2' 2 $r2.Codigo
  Comprueba 'hubo un lote deshecho' ($r2.Salida -match 'DESHECHO') (Cola $r2.Salida)
  Comprueba 'todos los intentos vieron una marca' (@(Marcas-Vistas $e2 | Where-Object { $_ -match '"commit"' }).Count -eq @(Marcas-Vistas $e2).Count) ((Marcas-Vistas $e2) -join ' / ')
  Comprueba 'el lote no pasa: la marca ya no esta' (-not (Test-Path -LiteralPath (Get-Ruta $e2.Wt '.rescate/intento-en-curso.json'))) (Cola $r2.Salida)
}

$Pruebas['m8 cortado: un intento a medias (con marca) se deshace al arrancar con -Todo y no entra en la foto'] = {
  $e = Escenario-M6 'm8-cortado'
  $r0 = Fix-M6 $e 'estructura' 1 @() ''
  Igual 'la primera pasada sale con 0' 0 $r0.Codigo
  $partida = GitEn $e.Wt @('rev-parse', 'HEAD')
  $texto = Lee $e.Wt $LeerM8
  # el corte: el intento dejo un fichero tocado y otro nuevo, sin commit, y su marca
  Escribe $e.Wt $LeerM8 ($texto + "// a medias`n")
  Escribe $e.Wt 'src/main/java/com/acme/life/application/usecases/AMedias.java' "class AMedias {}`n"
  Escribe $e.Wt '.rescate/intento-en-curso.json' ('{"paso":"estructura","lote":7,"commit":"' + $partida + '"}')
  $r = Rescate @('-Modo', 'fix', '-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-Todo', '-SinPlan', '-Si', '-MaxIntentos', '1')
  Igual 'sale con 0' 0 $r.Codigo
  Comprueba 'dice que habia un intento cortado, con su paso, su lote y su commit' ($r.Salida -match ('Habia un intento cortado \(paso estructura, lote 7\): lo deshago y sigo desde ' + $partida.Substring(0, 7))) (Cola $r.Salida)
  Comprueba 'no pregunta por una foto' ($r.Salida -notmatch 'Hay \d+ cambios sin commit') (Cola $r.Salida)
  Igual 'la rama sigue en el commit apuntado' $partida (GitEn $e.Wt @('rev-parse', 'HEAD'))
  Comprueba 'no hay commit foto' ((GitEn $e.Wt @('log', '--format=%s')) -notmatch 'foto') (GitEn $e.Wt @('log', '--format=%s'))
  Igual 'el fichero tocado vuelve a como estaba' $texto (Lee $e.Wt $LeerM8)
  Comprueba 'el fichero nuevo ya no esta' (-not (Test-Path -LiteralPath (Get-Ruta $e.Wt 'src/main/java/com/acme/life/application/usecases/AMedias.java')))
  Igual 'el worktree queda limpio' '' (GitEn $e.Wt @('status', '--porcelain'))
  Comprueba 'la marca ya no esta' (-not (Test-Path -LiteralPath (Get-Ruta $e.Wt '.rescate/intento-en-curso.json')))
}

$Pruebas['m8 cortado: sin marca, los cambios sin commit siguen yendo a la foto'] = {
  $e = Escenario-M6 'm8-sin-marca'
  $r0 = Fix-M6 $e 'estructura' 1 @() ''
  Igual 'la primera pasada sale con 0' 0 $r0.Codigo
  $texto = Lee $e.Wt $LeerM8
  Escribe $e.Wt $LeerM8 ($texto + "// del usuario`n")
  $r = Rescate @('-Modo', 'fix', '-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-Todo', '-SinPlan', '-Si', '-MaxIntentos', '1')
  Igual 'sale con 0' 0 $r.Codigo
  Comprueba 'no habla de un intento cortado' ($r.Salida -notmatch 'intento cortado') (Cola $r.Salida)
  Igual 'el ultimo commit es la foto' 'rescate: foto del estado antes de empezar' (GitEn $e.Wt @('log', '-1', '--format=%s'))
  Comprueba 'la foto lleva el cambio' ((Lee $e.Wt $LeerM8) -match 'del usuario') (Cola $r.Salida)
  Igual 'el worktree queda limpio' '' (GitEn $e.Wt @('status', '--porcelain'))
}

$Pruebas['m8 cortado: si la rama ha avanzado desde la marca (un commit del usuario), no se deshace nada y la marca se borra'] = {
  $e = Escenario-M6 'm8-cortado-avanzado'
  $r0 = Fix-M6 $e 'estructura' 1 @() ''
  Igual 'la primera pasada sale con 0' 0 $r0.Codigo
  $partida = GitEn $e.Wt @('rev-parse', 'HEAD')
  $texto = Lee $e.Wt $LeerM8
  $suyo = 'src/main/java/com/acme/life/application/usecases/DelUsuario.java'
  # el usuario corta la pasada, arregla a mano con su commit en la rama de rescate y deja algo sin commit; la marca queda vieja
  Escribe $e.Wt $suyo "class DelUsuario {}`n"
  [void](GitEn $e.Wt @('add', '--', $suyo))
  [void](GitEn $e.Wt @('commit', '-q', '-m', 'arreglo a mano del usuario'))
  Escribe $e.Wt $LeerM8 ($texto + "// sin commit del usuario`n")
  Escribe $e.Wt '.rescate/intento-en-curso.json' ('{"paso":"estructura","lote":7,"commit":"' + $partida + '"}')
  $r = Rescate @('-Modo', 'fix', '-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-Todo', '-SinPlan', '-Si', '-MaxIntentos', '1')
  Igual 'sale con 0' 0 $r.Codigo
  Comprueba 'dice en una linea que no deshace nada' ($r.Salida -match 'Habia un intento cortado \(paso estructura, lote 7\), pero la rama ha avanzado desde entonces: no deshago nada\.') (Cola $r.Salida)
  Comprueba 'el commit del usuario sigue en la rama' ((GitEn $e.Wt @('log', '--format=%s')) -match 'arreglo a mano del usuario') (GitEn $e.Wt @('log', '--format=%s'))
  Comprueba 'y su fichero' (Test-Path -LiteralPath (Get-Ruta $e.Wt $suyo))
  Comprueba 'lo que dejo sin commit no se pierde: va a la foto, como sin marca' ((GitEn $e.Wt @('log', '--format=%s')) -match 'foto' -and (Lee $e.Wt $LeerM8) -match 'sin commit del usuario') (GitEn $e.Wt @('log', '--format=%s'))
  Igual 'no hay stash' '' (GitEn $e.Wt @('stash', 'list'))
  Comprueba 'la marca ya no esta' (-not (Test-Path -LiteralPath (Get-Ruta $e.Wt '.rescate/intento-en-curso.json')))
}

$Pruebas['m8 cortado: con la marca al dia y cambios, van a un stash y el arbol queda limpio en el commit de la marca'] = {
  $e = Escenario-M6 'm8-cortado-stash'
  $r0 = Fix-M6 $e 'estructura' 1 @() ''
  Igual 'la primera pasada sale con 0' 0 $r0.Codigo
  $partida = GitEn $e.Wt @('rev-parse', 'HEAD')
  $texto = Lee $e.Wt $LeerM8
  $nuevo = 'src/main/java/com/acme/life/application/usecases/AMedias.java'
  Escribe $e.Wt $LeerM8 ($texto + "// a medias`n")
  Escribe $e.Wt $nuevo "class AMedias {}`n"
  Escribe $e.Wt '.rescate/intento-en-curso.json' ('{"paso":"estructura","lote":7,"commit":"' + $partida + '"}')
  $r = Rescate @('-Modo', 'fix', '-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-Todo', '-SinPlan', '-Si', '-MaxIntentos', '1')
  Igual 'sale con 0' 0 $r.Codigo
  $st = @((GitEn $e.Wt @('stash', 'list')) -split "`n" | Where-Object { $_ })
  Igual 'hay un stash' 1 $st.Count
  Comprueba 'con el paso y el lote en su nombre' ($st.Count -eq 1 -and $st[0] -match 'rescate: intento cortado \(paso estructura, lote 7\)') ($st -join ' / ')
  Comprueba 'el aviso dice como recuperarlo' ($r.Salida -match 'Lo he guardado en git stash \(recuperalo con: git stash list / git stash pop\)\.') (Cola $r.Salida)
  Comprueba 'el stash lleva el cambio del fichero tocado' ((GitEn $e.Wt @('show', 'stash@{0}')) -match '// a medias')
  Comprueba 'y el fichero nuevo' ((GitEn $e.Wt @('show', ('stash@{0}^3:' + $nuevo))) -match 'class AMedias')
  Igual 'el arbol queda en el commit de la marca' $partida (GitEn $e.Wt @('rev-parse', 'HEAD'))
  Igual 'y limpio' '' (GitEn $e.Wt @('status', '--porcelain'))
  Comprueba 'no hay commit foto' ((GitEn $e.Wt @('log', '--format=%s')) -notmatch 'foto')
  Comprueba 'la marca ya no esta' (-not (Test-Path -LiteralPath (Get-Ruta $e.Wt '.rescate/intento-en-curso.json')))
}

$Pruebas['m8 marca: el commit del lote se hace con la marca puesta y se borra despues'] = {
  $e = Escenario-M6 'm8-marca-commit'
  # un hook de commit apunta si la marca esta cuando se commitea (los worktrees usan los hooks del repo)
  $hook = Get-Ruta $e.Repo '.git/hooks/pre-commit'
  [void](GitEn $e.Repo @('config', 'core.hooksPath', (Get-Ruta $e.Repo '.git/hooks')))   # por si la maquina trae los suyos
  Escribe $e.Repo '.git/hooks/pre-commit' "#!/bin/sh`nif [ -f .rescate/intento-en-curso.json ]; then echo con >> .rescate/hook-marca.log; else echo sin >> .rescate/hook-marca.log; fi`n"
  if (Get-Command chmod -ErrorAction SilentlyContinue) { & chmod +x $hook }
  $r = Fix-M6 $e 'estructura' 1 @() ''
  Igual 'sale con 0' 0 $r.Codigo
  $log = Get-Ruta $e.Wt '.rescate/hook-marca.log'
  if (-not (Test-Path -LiteralPath $log)) { Comprueba 'el hook se ejecuto en el commit del lote' $false (Cola $r.Salida); return }
  $v = @([System.IO.File]::ReadAllLines($log) | Where-Object { $_ })
  Comprueba 'el commit del lote vio la marca' ($v.Count -ge 1 -and @($v | Where-Object { $_ -ne 'con' }).Count -eq 0) ($v -join ',')
  Comprueba 'despues no esta' (-not (Test-Path -LiteralPath (Get-Ruta $e.Wt '.rescate/intento-en-curso.json')))
}

# ===== M8 (parte 6): DESCRIPTIVO POR CONSOLA Y EN LOS LOGS =====
# Lo que sale por consola en el intento $I de un lote: desde su 'Copilot trabajando (intento I de N)' hasta el siguiente
# intento, el siguiente lote o el final (el aviso del lote deshecho va dentro del ultimo intento).
function Consola-Del-Intento([string]$Salida, [int]$I) {
  return ([regex]::Match($Salida, "(?s)Copilot trabajando \(intento $I de \d+\)\.\.\.(.*?)(?=Copilot trabajando \(intento|--- Lote \d|\z)")).Groups[1].Value
}

# Las lineas del detalle de un texto de consola: con 4 espacios y '- '.
function Detalle-De-Consola([string]$Texto) { return @($Texto -split "`r?`n" | Where-Object { $_ -match '^    - ' }) }

$Pruebas['m8 consola: tras los NO PASA salen las lineas del detalle (lo roto primero) y la correccion completa queda en .rescate/intento-*.md'] = {
  $e = Escenario-M6 'm8-consola' @{ Orden = @('estructura', 'ficheros') }
  $r = Fix-M6 $e 'ficheros' 2 @() 'mueve-a-util'
  $c1 = Consola-Del-Intento $r.Salida 1
  $det = Detalle-De-Consola $c1
  $nuevoL = '    - ' + $LeerMovidoM8 + " - subpaquete 'infrastructure/util' no existe en la plantilla"
  Comprueba 'tras los NO PASA sale el detalle del intento' ($det.Count -gt 0 -and $c1.IndexOf('NO PASA') -ge 0 -and $c1.IndexOf('NO PASA') -lt $c1.IndexOf($det[0])) $c1
  Comprueba 'su primera linea es lo nuevo de estructura, con fichero y regla' ($det.Count -gt 0 -and $det[0].StartsWith($nuevoL)) (($det | Select-Object -First 2) -join ' / ')
  Comprueba 'y salen tambien los hallazgos del paso' (@($det | Where-Object { $_ -match 'acceso directo a ficheros locales' }).Count -eq 1) $c1
  Comprueba 'con tan pocas lineas no dice que falten' ($c1 -notmatch ' mas en ') $c1
  $ruta = Get-Ruta $e.Wt '.rescate/intento-ficheros-1-1.md'
  if (-not (Test-Path -LiteralPath $ruta)) { Comprueba 'existe .rescate/intento-ficheros-1-1.md' $false (Cola $r.Salida); return }
  $f1 = Lee $e.Wt '.rescate/intento-ficheros-1-1.md'
  Comprueba 'el fichero lleva los motivos y el detalle completo' ($f1 -match "Has empeorado el paso anterior 'estructura' \(2 -> 3 hallazgos\)" -and $f1 -match 'Detalle:' -and $f1.Contains($LeerMovidoM8) -and $f1 -match '\(repo\) - no hay adaptador SFTP') $f1
  Comprueba 'el intento 2 tiene el suyo' (Test-Path -LiteralPath (Get-Ruta $e.Wt '.rescate/intento-ficheros-1-2.md'))
  $lotes = @(Llamadas-M6 $e 'lote')
  if ($lotes.Count -ge 2) {
    $c = Correccion-De (Prompt-M6 $e $lotes[1])
    $detalle = $f1.Substring($f1.IndexOf('Detalle:')).Trim()
    Comprueba 'es la misma correccion que recibe el intento siguiente' ($c.Contains($detalle)) $c
  }
}

$Pruebas['m8 consola: con mas de 8 lineas salen 8 y dice cuantas faltan; el lote deshecho y el atascado traen su detalle'] = {
  $e = Escenario-M6 'm8-consola-8' @{ Orden = @('ficheros') }
  $r = Fix-M6 $e 'ficheros' 2 @() 'muchos-ficheros'
  $c1 = Consola-Del-Intento $r.Salida 1
  $ruta = Get-Ruta $e.Wt '.rescate/intento-ficheros-1-1.md'
  if (-not (Test-Path -LiteralPath $ruta)) { Comprueba 'existe .rescate/intento-ficheros-1-1.md' $false (Cola $r.Salida); return }
  $total = @((Lee $e.Wt '.rescate/intento-ficheros-1-1.md') -split "`r?`n" | Where-Object { $_ -match '^  - ' }).Count
  Comprueba 'el fichero del intento lleva mas de 8 lineas de detalle' ($total -gt 8) "$total"
  Igual 'por consola salen 8 lineas del detalle' 8 (Detalle-De-Consola $c1).Count
  $mas = [regex]::Match($c1, '(?m)^    \((\d+) mas en \.rescate/intento-ficheros-1-1\.md\)\s*$')
  Comprueba 'y dice cuantas faltan y donde estan' ($mas.Success -and [int]$mas.Groups[1].Value -eq ($total - 8)) "$($mas.Value) / total $total"
  # el lote deshecho: sus motivos, 8 lineas del detalle del ultimo intento y donde esta su correccion completa
  $c2 = Consola-Del-Intento $r.Salida 2
  $i = $c2.IndexOf('Lote 1 DESHECHO')
  if ($i -lt 0) { Comprueba 'el lote 1 se deshace' $false (Cola $r.Salida); return }
  $des = $c2.Substring($i)
  Igual 'el aviso del lote deshecho trae 8 lineas del detalle del ultimo intento' 8 (Detalle-De-Consola $des).Count
  Comprueba 'con cuantas faltan' ($des -match '(?m)^    \(\d+ mas en \.rescate/intento-ficheros-1-2\.md\)') $des
  Comprueba 'y la ruta de la correccion completa del ultimo intento' ($des -match 'Correccion completa del ultimo intento: \.rescate/intento-ficheros-1-2\.md') $des
  # el atascado: su nota lleva las lineas del detalle del ultimo intento
  $at = Lee $e.Wt '.rescate/atascados.md'
  Comprueba 'la nota del atascado lleva las lineas de detalle del ultimo intento' ($at -match '(?m)^    - src/main/java/com/acme/life/application/usecases/LeerOtro\d+\.java:\d+ - acceso directo a ficheros locales' -and $at -match '(?m)^    \(\d+ mas en \.rescate/intento-ficheros-\d+-\d+\.md\)') $at
}

$Pruebas['m8 consola: si Copilot sale con un codigo distinto de 0 salen las ultimas 5 lineas no vacias de su salida'] = {
  $e = Escenario-M6 'm8-copilot-rc' @{ Orden = @('estructura') }
  $r = Fix-M6 $e 'estructura' 1 @() 'falla-copilot'
  $c1 = Consola-Del-Intento $r.Salida 1
  Comprueba 'dice el codigo y el registro, como antes' ($c1 -match 'Copilot termino con codigo 1 \(ver \.rescate/lote-estructura-1-1\.log\)') $c1
  $salen = @('SALIDA-C', 'SALIDA-D', 'SALIDA-E', 'SALIDA-F', 'SALIDA-G ultima' | Where-Object { $c1 -match ('(?m)^    ' + [regex]::Escape($_) + '\s*$') })
  Igual 'salen sus ultimas 5 lineas no vacias, con sangria' 5 $salen.Count
  Comprueba 'y no las anteriores' ($c1 -notmatch 'SALIDA-A|SALIDA-B') $c1
}

$Pruebas['m8 reflexion: el lector acepta titulos con # a ####, numerados, en negrita y con signos de pregunta'] = {
  $e = Escenario-M6 'm8-reflexion-formato' @{ Reflexionar = $true }
  $r = Fix-M6 $e 'estructura' 2 @() 'nada-sin-correccion;reflexion-formato'
  Comprueba 'no dice que falte ninguna seccion' ($r.Salida -notmatch 'A la reflexion le falta') (Cola $r.Salida)
  $l = @(Llamadas-M6 $e 'lote')
  if ($l.Count -lt 2) { Comprueba 'dos intentos' $false ($l -join ' / '); return }
  Comprueba 'y el segundo intento lleva la reflexion' ((Prompt-M6 $e $l[1]) -match 'REFLEXION-MARCA-estructura-1-1') (Cola $r.Salida)
}

$Pruebas['m8 reflexion: si aun falta una seccion, el aviso dice que titulos trae y la ruta del fichero'] = {
  $e = Escenario-M6 'm8-reflexion-trae' @{ Reflexionar = $true }
  $r = Fix-M6 $e 'estructura' 2 @() 'nada-sin-correccion;reflexion-mala'
  Comprueba 'dice lo que falta, los titulos que trae y el fichero' ($r.Salida -match "(?m)^  A la reflexion le falta 'Que hacer ahora', 'Que no hacer': sigo sin ella\. Trae los titulos 'Que se intento', 'Por que no paso' \(ver \.rescate/reflexion-estructura-1-1\.md\)\.") (Cola $r.Salida)
  $e2 = Escenario-M6 'm8-reflexion-sin-titulos' @{ Reflexionar = $true }
  $r2 = Fix-M6 $e2 'estructura' 2 @() 'nada-sin-correccion;reflexion-sin-titulos'
  Comprueba 'sin titulos dice que no trae ninguno' ($r2.Salida -match "(?m)^  A la reflexion le falta 'Que se intento', 'Por que no paso', 'Que hacer ahora', 'Que no hacer': sigo sin ella\. No trae ningun titulo \(ver \.rescate/reflexion-estructura-1-1\.md\)\.") (Cola $r2.Salida)
}

$Pruebas['m8 reflexion: sin decir nada en la config, corre cuando el fallo se repite y el siguiente la lleva'] = {
  $e = Escenario-M6 'm8-reflexion-defecto'
  Escribe $e.Repo '.rescate/config.json' (ConvertTo-Json -InputObject ([ordered]@{ CopilotExe = (Join-Path $falsos 'copilot-m6.ps1'); MvnExe = (Join-Path $falsos 'mvn.ps1'); Orden = @('estructura', 'tests') }))
  $r = Fix-M6 $e 'estructura' 3 @() 'nada-hasta-reflexion'
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'hay una reflexion, tras el segundo intento (el primero no tenia otro con el que compararse)' 1 (Llamadas-M6 $e 'reflexion').Count
  $l = @(Llamadas-M6 $e 'lote')
  Igual 'tres intentos' 3 $l.Count
  if ($l.Count -eq 3) {
    Comprueba 'el segundo no lleva reflexion' ((Prompt-M6 $e $l[1]) -notmatch 'REFLEXION-MARCA') (Prompt-M6 $e $l[1])
    Comprueba 'el tercero lleva la del intento 2 en la CORRECCION' ((Correccion-De (Prompt-M6 $e $l[2])) -match 'REFLEXION-MARCA-estructura-1-2') (Prompt-M6 $e $l[2])
  }
  Comprueba 'la cabecera no dice que va sin reflexion' ($r.Salida -notmatch '\(sin reflexion\)') (Cola $r.Salida)
}

# ===== M9 (parte A): ARREGLOS RAPIDOS QUE AHORRAN HORAS =====
# Los ficheros de un lote, de una linea de llamadas-m6.log.
function Ficheros-Del-Lote([string]$Linea) { return @((([regex]::Match($Linea, '^\d+ \| lote \|[^|]*\| (.*)$')).Groups[1].Value) -split ',' | Where-Object { $_ }) }

$Pruebas['m9 lotes: tras deshacer un lote, los ficheros de despues vuelven al tamano del paso'] = {
  $e = Escenario-M6 'm9-tamano'
  # cinco clases sueltas mas: con Suelta y PolizaService, siete ficheros con hallazgos de estructura
  foreach ($k in 1..5) { Escribe $e.Repo "src/main/java/com/acme/life/Extra$k.java" "package com.acme.life;`n`n/** Clase $k. */`npublic class Extra$k {`n}`n" }
  [void](GitEn $e.Repo @('add', '--', 'src'))
  [void](GitEn $e.Repo @('commit', '-q', '-m', 'cinco clases mas'))
  $r = Fix-M6 $e 'estructura' 1 @('-Lote', '5') 'primer-lote-falla'
  Igual 'sale con 0' 0 $r.Codigo
  $tam = @(Llamadas-M6 $e 'lote' | ForEach-Object { (Ficheros-Del-Lote $_).Count })
  Igual 'un lote de 5 (deshecho), cinco de uno y el ultimo con los dos que quedaban' '5,1,1,1,1,1,2' ($tam -join ',')
}

$Pruebas['m9 maven: el paso siguiente reutiliza el diagnostico del ultimo lote (mismo commit, arbol limpio) y no lanza Maven al empezar'] = {
  $e = Escenario-M6 'm9-maven' @{ Orden = @('estructura', 'ficheros') }
  $r = Rescate @('-Modo', 'fix', '-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-Todo', '-SinPlan', '-Si', '-MaxIntentos', '1')
  $pasos = (($r.Salida -split "`n") | Where-Object { $_ -match "=== Paso|Lote \d+ (OK|DESHECHO)|Diagnostico inicial" }) -join ' / '
  Comprueba 'hace el lote de estructura y pasa al paso siguiente' ($r.Salida -match "Lote \d+ OK: 'estructura'" -and $r.Salida -match "=== Paso 'ficheros'") $pasos
  Comprueba 'dice que reutiliza los hallazgos' ($r.Salida -match 'mismo commit y arbol limpio que en el ultimo diagnostico con Maven: reutilizo sus hallazgos') $pasos
  Igual 'y solo lo dice una vez: el diagnostico inicial del primer paso si lanza Maven' 1 ([regex]::Matches($r.Salida, 'reutilizo sus hallazgos')).Count
  $log = Get-Ruta $e.Wt '.rescate/mvn-llamadas.log'
  if (-not (Test-Path -LiteralPath $log)) { Comprueba 'hay registro de llamadas a Maven' $false (Cola $r.Salida); return }
  # llamadas a Maven por cada "llamadas de Copilot hasta ahora": el diagnostico inicial (0) cuesta lo que cuesta un diagnostico
  $por = @{}
  foreach ($l in [System.IO.File]::ReadAllLines($log)) { if ($l -match '^(\d+) \|') { $por[[int]$Matches[1]] = 1 + [int]$por[[int]$Matches[1]] } }
  $resumen = (($por.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' ')
  $c0 = [int]$por[0]
  Comprueba 'el diagnostico inicial lanza Maven' ($c0 -gt 0) $resumen
  $de = @($por.Keys | Where-Object { $por[$_] -gt $c0 })
  Comprueba 'entre el ultimo lote de un paso y el inicio del siguiente no sube el contador de Maven' ($de.Count -eq 0) $resumen
}

$Pruebas['m9 fallos seguidos: la cascada de un fichero cuenta como un fallo, no uno por escalon'] = {
  $e = Escenario-M6 'm9-cascada' @{ MaxFallosSeguidos = 3 }
  $r = Fix-M6 $e 'estructura' 1 @('-ModeloB', 'modelo-b') 'nada-sin-correccion'
  Comprueba 'no hay paro por lotes deshechos seguidos' ($r.Salida -notmatch 'PARO') (Cola $r.Salida)
  Comprueba 'los dos ficheros acaban atascados' (@([regex]::Matches($r.Salida, 'ATASCADO en')).Count -eq 2) (Cola $r.Salida)
  Igual 'sale con 2, el de los atascados' 2 $r.Codigo
}

$Pruebas['m9 copilot: si sale con error sin cambiar nada se repite una vez sin gastar intento; si vuelve a salir igual, cuenta'] = {
  $e = Escenario-M6 'm9-repite' @{ Orden = @('estructura') }
  $r = Fix-M6 $e 'estructura' 1 @() 'falla-una-vez'
  Igual 'sale con 0' 0 $r.Codigo
  $lotes = @(Llamadas-M6 $e 'lote')
  Comprueba 'el primer lote hizo dos llamadas con los mismos ficheros' ($lotes.Count -ge 2 -and ((Ficheros-Del-Lote $lotes[0]) -join ',') -eq ((Ficheros-Del-Lote $lotes[1]) -join ',')) ($lotes -join ' / ')
  Comprueba 'lo dice' ($r.Salida -match 'repito la llamada una vez \(no cuenta como intento\)') (Cola $r.Salida)
  Comprueba 'y el lote pasa con su unico intento' ($r.Salida -match "Lote 1 OK: 'estructura'" -and $r.Salida -notmatch 'DESHECHO') (Cola $r.Salida)
  $e2 = Escenario-M6 'm9-repite-siempre' @{ Orden = @('estructura') }
  $r2 = Fix-M6 $e2 'estructura' 1 @() 'falla-copilot'
  $l2 = @(Llamadas-M6 $e2 'lote')
  Comprueba 'si vuelve a salir igual, el lote se deshace con su unico intento' ($r2.Salida -match 'Lote 1 DESHECHO: no paso las comprobaciones tras 1 intento\(s\)') (Cola $r2.Salida)
  Comprueba 'tras repetir una vez, no mas' ($l2.Count -ge 2 -and ((Ficheros-Del-Lote $l2[0]) -join ',') -eq ((Ficheros-Del-Lote $l2[1]) -join ',') -and ((Ficheros-Del-Lote $l2[2]) -join ',') -ne ((Ficheros-Del-Lote $l2[0]) -join ',')) ($l2 -join ' / ')
}

# ----- A.4: la reflexion, solo cuando el fallo se repite -----
# Los intentos tras los que se reflexiono, de llamadas-m6.log ('estructura-1-2' = paso, lote, intento).
function Reflexiones-De($E) { return @(Llamadas-M6 $E 'reflexion' | ForEach-Object { ($_ -split ' \| ')[3].Trim() }) }

$Pruebas['m9 reflexion: con fallos distintos en los intentos 1 y 2 no se reflexiona (repetido, el defecto)'] = {
  $e = Escenario-M6 'm9-refl-distintos'
  Escribe $e.Repo '.rescate/config.json' (ConvertTo-Json -InputObject ([ordered]@{ CopilotExe = (Join-Path $falsos 'copilot-m6.ps1'); MvnExe = (Join-Path $falsos 'mvn.ps1'); Orden = @('estructura', 'tests') }))
  $r = Fix-M6 $e 'estructura' 3 @('-Lote', '1', '-Saltar', '1') 'fallos-distintos'
  Igual 'sale con 0' 0 $r.Codigo
  $c1 = Lee $e.Wt '.rescate/intento-estructura-1-1.md'; $c2 = Lee $e.Wt '.rescate/intento-estructura-1-2.md'
  Comprueba 'el intento 1 no cambia nada y el 2 no baja los hallazgos: son fallos distintos' ($c1 -match 'No has cambiado' -and $c2 -match 'no han bajado' -and $c2 -notmatch 'No has cambiado') ($c1 + ' // ' + $c2)
  Comprueba 'el lote pasa en el tercero' ($r.Salida -match "Lote 1 OK: 'estructura'") (Cola $r.Salida)
  Igual 'no se reflexiona nunca' 0 (Reflexiones-De $e).Count
}

$Pruebas['m9 reflexion: siempre y true reflexionan tras cada intento que no pasa; nunca y false, ninguno; un valor raro, como repetido'] = {
  foreach ($q in @(@('true', $true, 'estructura-1-1,estructura-1-2'), @('siempre', 'siempre', 'estructura-1-1,estructura-1-2'), @('false', $false, ''), @('nunca', 'nunca', ''), @('repetido', 'repetido', 'estructura-1-2'))) {
    $e = Escenario-M6 ('m9-refl-' + $q[0]) @{ Reflexionar = $q[1] }
    $r = Fix-M6 $e 'estructura' 2 @() 'atasca-siempre;consejo-nada'
    Igual "Reflexionar $($q[0]): las reflexiones del primer lote" $q[2] ((Reflexiones-De $e | Where-Object { $_ -match '^estructura-1-' }) -join ',')
  }
  $e = Escenario-M6 'm9-refl-raro' @{ Reflexionar = 'quizas' }
  $r = Fix-M6 $e 'estructura' 2 @() 'atasca-siempre;consejo-nada'
  Comprueba 'avisa de que el valor no vale' ($r.Salida -match "Reflexionar 'quizas' no vale") (Cola $r.Salida)
  Igual 'y reflexiona como repetido' 'estructura-1-2' ((Reflexiones-De $e | Where-Object { $_ -match '^estructura-1-' }) -join ',')
}

# ----- A.5: los reintentos suben el esfuerzo -----
# El esfuerzo (--effort=) de cada llamada de lote, en orden.
function Esfuerzos-De-Lotes($E) { return @(Llamadas-M6 $E 'lote' | ForEach-Object { ([regex]::Match($_, '--effort=(\w+)')).Groups[1].Value }) }

$Pruebas['m9 esfuerzo: el intento 1 va con el de -Esfuerzo y los siguientes con EsfuerzoReintento (high), si es mayor'] = {
  $e = Escenario-M6 'm9-esf-defecto'
  $r = Fix-M6 $e 'estructura' 2 @('-Lote', '1', '-Saltar', '1', '-Esfuerzo', 'medium') 'nada-sin-correccion'
  Igual 'el intento 1 con medium y el 2 con high' 'medium,high' ((Esfuerzos-De-Lotes $e) -join ',')
  $e2 = Escenario-M6 'm9-esf-igual' @{ EsfuerzoReintento = 'high' }
  [void](Fix-M6 $e2 'estructura' 2 @('-Lote', '1', '-Saltar', '1', '-Esfuerzo', 'high') 'nada-sin-correccion')
  Igual 'con -Esfuerzo high, todo va con high' 'high,high' ((Esfuerzos-De-Lotes $e2) -join ',')
  $e3 = Escenario-M6 'm9-esf-mayor'
  [void](Fix-M6 $e3 'estructura' 2 @('-Lote', '1', '-Saltar', '1', '-Esfuerzo', 'xhigh') 'nada-sin-correccion')
  Igual 'con -Esfuerzo xhigh (mayor), el reintento no lo baja' 'xhigh,xhigh' ((Esfuerzos-De-Lotes $e3) -join ',')
  $e4 = Escenario-M6 'm9-esf-vacio' @{ EsfuerzoReintento = '' }
  [void](Fix-M6 $e4 'estructura' 2 @('-Lote', '1', '-Saltar', '1', '-Esfuerzo', 'medium') 'nada-sin-correccion')
  Igual 'con EsfuerzoReintento vacio, como hasta ahora' 'medium,medium' ((Esfuerzos-De-Lotes $e4) -join ',')
  $e5 = Escenario-M6 'm9-esf-sin-esfuerzo'
  [void](Fix-M6 $e5 'estructura' 2 @('-Lote', '1', '-Saltar', '1') 'nada-sin-correccion')
  Igual 'sin -Esfuerzo (el de Copilot), el intento 1 no pide ninguno y el 2 pide high' ',high' ((Esfuerzos-De-Lotes $e5) -join ',')
}

$Pruebas['m9 esfuerzo: los escalones (de uno en uno, reserva y consejo) van con el esfuerzo de reintento'] = {
  $e = Escenario-M6 'm9-esf-escalones'
  $r = Fix-M6 $e 'estructura' 1 @('-Lote', '2', '-Esfuerzo', 'medium', '-ModeloB', 'modelo-b') 'atasca-siempre;consejo-codigo'
  $es = @(Esfuerzos-De-Lotes $e)
  Comprueba 'hay el lote de dos, uno de uno en uno, la reserva y el consejo' ($es.Count -ge 4) ($es -join ',')
  if ($es.Count -ge 4) {
    Igual 'el primer lote, con medium' 'medium' $es[0]
    Igual 'todos los escalones, con high' 'high' (($es | Select-Object -Skip 1 | Select-Object -Unique) -join ',')
  }
}

$Pruebas['m9 esfuerzo: si Copilot no admite el esfuerzo del reintento, se baja con la regla de siempre y se queda'] = {
  $e = Escenario-M6 'm9-esf-baja' @{ EsfuerzoReintento = 'max' }
  $r = Fix-M6 $e 'estructura' 2 @('-Lote', '1', '-Esfuerzo', 'medium') 'nada-sin-correccion;sin-max'
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'dos lotes: el intento 2 pide max, se rechaza y se repite con xhigh; en el lote siguiente el 2 ya pide xhigh' 'medium,xhigh,medium,xhigh' ((Esfuerzos-De-Lotes $e) -join ',')
  Igual 'un solo rechazo' 1 @(Llamadas-M6 $e 'rechazo').Count
  Comprueba 'lo dice' ($r.Salida -match "esfuerzo 'max'.*'xhigh'") (Cola $r.Salida)
}

# ===== M9 (parte B): REPARAR, NO REPETIR =====
$FraseReparacion = 'Tu intento anterior sigue en el arbol de trabajo. No vuelvas a explorar el repo: arregla solo esto.'

$Pruebas['m9 reparar: los intentos 2 y 3 llevan el prompt corto de reparacion; un intento peor se descarta y el siguiente parte del mejor'] = {
  $e = Escenario-M6 'm9-reparar'
  $r = Fix-M6 $e 'estructura' 3 @('-Lote', '1') 'mejor-peor'
  $ls = @(Lotes-Suelta $e)
  Comprueba 'Suelta tiene tres llamadas' ($ls.Count -eq 3) ($ls -join ' / ')
  if ($ls.Count -lt 3) { return }
  $p1 = Prompt-M6 $e $ls[0]; $p2 = Prompt-M6 $e $ls[1]; $p3 = Prompt-M6 $e $ls[2]
  Comprueba 'el primero es el prompt de siempre' ($p1 -match 'resuelve estos y nada mas' -and $p1 -notmatch [regex]::Escape($FraseReparacion)) $p1
  foreach ($q in @(@(2, $p2), @(3, $p3))) {
    $p = $q[1]
    Comprueba "el intento $($q[0]) empieza por la frase de reparacion" ($p -match ('(?s)^# [^\n]*\n\n' + [regex]::Escape($FraseReparacion) + '\n')) $p
    Comprueba "el intento $($q[0]) no dice 'nada mas'" ($p -notmatch 'nada mas') $p
    Comprueba "el intento $($q[0]) lleva la correccion completa, con el detalle" ($p -match '## CORRECCION' -and $p -match "Los hallazgos de 'estructura' no han bajado" -and $p -match 'Detalle:') $p
    Comprueba "el intento $($q[0]) lleva los ficheros del lote, la orden de Maven y las reglas" ($p -match '(?m)^## Ficheros del lote\n- src/main/java/com/acme/life/Suelta\.java\n' -and $p -match '(?m)^- Ejecuta: .* -q -B' -and $p -match '## Reglas obligatorias') $p
    Comprueba "el intento $($q[0]) es corto: sin las referencias ni el 'Antes de tocar nada', y con las reglas de calidad" ($p -notmatch 'Antes de tocar nada' -and $p -notmatch '## Referencias' -and $p -match '## Calidad del codigo que escribas') $p
  }
  Comprueba 'dice que el intento 2 es peor que el 1 y vuelve a su arbol' ($r.Salida -match 'El intento 2 es peor que el intento 1.*vuelvo a su arbol') (Cola $r.Salida)
  Comprueba 'el 3 lleva la correccion del mejor (el 1), no la del peor' ($p3 -notmatch 'mas tests fallando') $p3
  $v = @([System.IO.File]::ReadAllLines((Get-Ruta $e.Wt '.rescate/arbol-visto.log')))
  Igual 'el 3 ve el arbol del 1 sin lo del 2' 'mejor=True peor=False rompe=False' ($v -join '|')
  Comprueba 'y el lote pasa en el intento 3' ($r.Salida -match "Lote 1 OK: 'estructura'") (Cola $r.Salida)
}

$Pruebas['m9 reparar: al rendirse la ref guarda el mejor intento y el escalon siguiente parte de su arbol (pero solo si la rama no ha avanzado)'] = {
  $e = Escenario-M6 'm9-ref'
  $r = Fix-M6 $e 'estructura' 1 @() 'parcial-roto'
  $ref = 'refs/rescate/estructura-1'
  Comprueba 'dice que el lote se deshace y donde queda el mejor intento' ($r.Salida -match 'Lote 1 DESHECHO' -and $r.Salida -match [regex]::Escape($ref)) (Cola $r.Salida)
  $refs = GitEn $e.Wt @('for-each-ref', '--format=%(refname)', 'refs/rescate/')
  Comprueba 'existe la ref' ($refs -match [regex]::Escape($ref)) $refs
  $arbol = GitEn $e.Wt @('ls-tree', '-r', '--name-only', $ref)
  Comprueba 'la ref guarda el arbol del intento: Suelta movida y el test roto' ($arbol -match 'application/usecases/Suelta\.java' -and $arbol -match 'RompeTest\.java') $arbol
  Igual 'no es un commit de la rama' '' (GitEn $e.Wt @('branch', '--contains', $ref))
  $v = @([System.IO.File]::ReadAllLines((Get-Ruta $e.Wt '.rescate/arbol-visto.log')))
  Comprueba 'el escalon siguiente (Suelta de uno en uno) empieza con el arbol del mejor' ($v.Count -ge 1 -and $v[0] -eq 'suelta-movida=True') ($v -join '|')
  $ll = @(Llamadas-M6 $e 'lote')
  Comprueba 'y lleva el prompt de reparacion' ($ll.Count -ge 2 -and (Prompt-M6 $e $ll[1]).Contains($FraseReparacion)) (Cola $r.Salida)
  Comprueba 'el lote de Suelta pasa' ($r.Salida -match "Lote 2 OK: 'estructura'") (Cola $r.Salida)
  Comprueba 'el del otro fichero va de cero, con el prompt de siempre: la rama habia avanzado' ($ll.Count -ge 3 -and -not (Prompt-M6 $e $ll[2]).Contains($FraseReparacion) -and (Prompt-M6 $e $ll[2]) -match 'Hallazgos de este lote') (Cola $r.Salida)
  Igual 'sale con 0' 0 $r.Codigo
  Comprueba 'el test roto no llego a la rama' ((GitEn $e.Wt @('ls-tree', '-r', '--name-only', 'HEAD')) -notmatch 'RompeTest')
}

# ===== M9 (parte C): LA HERRAMIENTA DENTRO DE LA SESION (-Modo comprobar) =====
# Los bloques de .rescate/comprobar-visto.log (guion comprueba): la cabecera 'rc=.. rescate-igual=..' y su salida.
function Comprobar-Visto($E) {
  $p = Get-Ruta $E.Wt '.rescate/comprobar-visto.log'
  if (-not (Test-Path -LiteralPath $p)) { return @() }
  $bloques = @()
  foreach ($l in [System.IO.File]::ReadAllLines($p)) {
    if ($l -match '^(rc=|sin-orden)') { $bloques += ,@($l) } elseif ($bloques.Count -gt 0) { $bloques[$bloques.Count - 1] += $l }
  }
  return $bloques
}

$Pruebas['m9 comprobar: lista lo que el arbol ha roto frente al commit de partida (fichero, linea y regla) y sale con 1'] = {
  $e = Escenario-M6 'm9-comprobar-roto'
  $r = Fix-M6 $e 'estructura' 1 @('-Lote', '1', '-Saltar', '1') 'mueve-a-util;comprueba'
  $b = @(Comprobar-Visto $e)
  Comprueba 'el Copilot ejecuto la orden del prompt' ($b.Count -ge 1) (Cola $r.Salida)
  if ($b.Count -lt 1) { return }
  $txt = $b[0] -join "`n"
  Comprueba 'sale con 1' ($b[0][0] -match '^rc=1 ') $txt
  Comprueba 'no escribe nada en .rescate' ($b[0][0] -match 'rescate-igual=True') $txt
  $roto = ([regex]::Match($txt, '(?s)HAS ROTO.*?(?=Siguen sin resolver|$)')).Value
  Comprueba 'lista lo nuevo con su fichero y su regla' ($roto -match '- src/main/java/com/acme/life/infrastructure/util/LeerFichero\.java - subpaquete .infrastructure/util. no existe en la plantilla') $txt
  Comprueba 'y no lo que ya estaba (Suelta)' ($roto -notmatch 'Suelta') $txt
}

$Pruebas['m9 comprobar: sin regresion sale con 0 y no deja nada en .rescate'] = {
  $e = Escenario-M6 'm9-comprobar-limpio'
  $r = Fix-M6 $e 'estructura' 1 @('-Lote', '1') 'comprueba'
  $b = @(Comprobar-Visto $e)
  Comprueba 'el Copilot ejecuto la orden del prompt' ($b.Count -ge 1) (Cola $r.Salida)
  if ($b.Count -lt 1) { return }
  $txt = $b[0] -join "`n"
  Comprueba 'sale con 0 y .rescate queda igual' ($b[0][0] -match '^rc=0 rescate-igual=True') $txt
  Comprueba 'dice que no ha roto nada' ($txt -match 'No has roto nada nuevo') $txt
  Comprueba 'el lote pasa' ($r.Salida -match "Lote 1 OK: 'estructura'") (Cola $r.Salida)
}

$Pruebas['m9 comprobar: el prompt de cada lote y el de reparacion llevan la orden exacta; sin intento en curso no hace nada'] = {
  $e = Escenario-M6 'm9-comprobar-prompt'
  $r = Fix-M6 $e 'estructura' 2 @('-Lote', '1') 'mejor-peor'
  $ls = @(Lotes-Suelta $e)
  Comprueba 'hay dos intentos' ($ls.Count -ge 2) (Cola $r.Salida)
  if ($ls.Count -lt 2) { return }
  $orden = '(?m)^- Ejecuta: (pwsh|powershell) -NoProfile -File "([^"\r\n]*rescate\.ps1)" -Modo comprobar -Repo "([^"\r\n]+)" -Plantilla "[^"\r\n]+"  y corrige lo que liste \(como mucho 3 veces\)\.$'
  foreach ($q in @(@('normal', (Prompt-M6 $e $ls[0])), @('de reparacion', (Prompt-M6 $e $ls[1])))) {
    $m = [regex]::Match($q[1], $orden)
    Comprueba "el prompt $($q[0]) lleva la orden de comprobar" $m.Success $q[1]
    if ($m.Success) { Comprueba "la orden del prompt $($q[0]) apunta a un rescate.ps1 y al repo de verdad" ((Test-Path -LiteralPath $m.Groups[2].Value) -and ($m.Groups[3].Value -eq $e.Repo)) $m.Value }
    Comprueba "el prompt $($q[0]) pide despues los tests de Maven" ($q[1] -match '(?m)^- Ejecuta: .* -q -B test  y corrige los tests que fallen\.$') $q[1]
  }
  $e2 = Escenario-M6 'm9-comprobar-sin-marca'
  $foto = { (@(Get-ChildItem -LiteralPath $e2.Repo -Recurse -Force -File | Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' } | ForEach-Object { $_.FullName + '|' + $_.Length + '|' + $_.LastWriteTimeUtc.Ticks }) | Sort-Object) -join "`n" }
  $antes = & $foto
  $r2 = Rescate @('-Modo', 'comprobar', '-Repo', $e2.Repo, '-Plantilla', $e2.Plantilla)
  $despues = & $foto
  Igual 'sin intento en curso sale con 0' 0 $r2.Codigo
  Comprueba 'dice que no hay un intento en curso' ($r2.Salida -match 'No hay un intento en curso') (Cola $r2.Salida)
  Comprueba 'no cambia ni un fichero del repo' ($antes -eq $despues) $despues
}

# ===== M9 (parte D): EL PLAN Y LOS LOTES CON LOS PAQUETES DE LA PLANTILLA, Y EL PLAN COMPROBADO =====
$CabeceraMapa = 'Paquetes de la PLANTILLA. Cada clase nueva va en el paquete de su equivalente de esta lista. No crees paquetes que no esten aqui.'
$ReglaCapas = 'El dominio no depende de nada externo. La aplicacion solo depende del dominio y de sus puertos (interfaces en application/ports).'

# Las lineas del mapa de paquetes de un prompt: desde su titulo hasta la seccion siguiente (la primera es la cabecera).
function Mapa-Del-Prompt([string]$Prompt) {
  return @([regex]::Match($Prompt, '(?s)## Mapa de paquetes\r?\n(.*?)(?:\r?\n## |$)').Groups[1].Value -split "`r?`n" | Where-Object { $_ })
}

# La seccion 'Antes de tocar nada' de un prompt.
function Antes-De-Tocar([string]$Prompt) { return ([regex]::Match($Prompt, '(?s)## Antes de tocar nada.*?(?:\r?\n## |$)')).Value }

$Pruebas['m9 mapa: el prompt de un lote de ficheros lleva los paquetes de la plantilla con sus clases y la regla de capas'] = {
  $e = Escenario-M6 'm9-mapa' @{ Orden = @('estructura', 'ficheros') }
  $r = Fix-M6 $e 'ficheros' 1 @() ''
  $l = @(Llamadas-M6 $e 'lote')
  if ($l.Count -eq 0) { Comprueba 'hay un lote' $false (Cola $r.Salida); return }
  $p = Prompt-M6 $e $l[0]
  $m = @(Mapa-Del-Prompt $p)
  Comprueba 'la cabecera dice que cada clase nueva va en el paquete de su equivalente y que no se creen paquetes' ($m.Count -gt 0 -and $m[0] -ceq $CabeceraMapa) $p
  Comprueba 'lleva el paquete de los puertos de salida con su clase' ($m -contains '- application/ports/output: FicheroPort') ($m -join ' / ')
  Comprueba 'y el del adaptador local' ($m -contains '- infrastructure/adapters/output/file: FicheroLocalAdapter') ($m -join ' / ')
  Igual 'una linea por paquete de la plantilla (la clase del paquete base no cuenta)' 6 ($m.Count - 1)
  Comprueba 'un paquete que solo existe en el migrado no sale' (@($m | Where-Object { $_ -match 'service|PolizaService|Suelta' }).Count -eq 0) ($m -join ' / ')
  Comprueba 'va despues de las referencias y antes de lo que hay que hacer antes de tocar' (($p.IndexOf('## Referencias') -lt $p.IndexOf('## Mapa de paquetes')) -and ($p.IndexOf('## Mapa de paquetes') -lt $p.IndexOf('## Antes de tocar nada'))) $p
  Comprueba 'la regla de capas sale en un paso que no es hexagonal' ((Antes-De-Tocar $p).Contains($ReglaCapas)) $p
}

$Pruebas['m9 mapa: con muchos paquetes se corta en 60 lineas y lo dice; de cada paquete salen 4 clases como mucho'] = {
  $e = Escenario-M6 'm9-mapa-tope' @{ Orden = @('estructura', 'ficheros') }
  $b = 'src/main/java/com/acme/plantilla/application/'
  foreach ($n in 1..65) { Escribe $e.Plantilla ($b + ('extra/p{0:d2}/C{0:d2}.java' -f $n)) ('package com.acme.plantilla.application.extra.p{0:d2};{1}{1}/** Clase de relleno. */{1}public class C{0:d2} {{{1}}}{1}' -f $n, "`n") }
  foreach ($n in 1..6) { Escribe $e.Plantilla ($b + "a1/K$n.java") "package com.acme.plantilla.application.a1;`n`n/** Clase de relleno. */`npublic class K$n {`n}`n" }
  $r = Fix-M6 $e 'ficheros' 1 @() ''
  $l = @(Llamadas-M6 $e 'lote')
  if ($l.Count -eq 0) { Comprueba 'hay un lote' $false (Cola $r.Salida); return }
  $m = @(Mapa-Del-Prompt (Prompt-M6 $e $l[0]))
  Comprueba 'no pasa de 60 lineas' (($m.Count - 1) -le 60 -and ($m.Count - 1) -ge 50) ('lineas: ' + ($m.Count - 1))
  Comprueba 'la ultima dice cuantos paquetes faltan' ($m[-1] -match '^\(y \d+ paquetes mas') $m[-1]
  Comprueba 'de un paquete con 6 clases salen 4 y los puntos suspensivos' ($m -contains '- application/a1: K1, K2, K3, K4, ...') (($m | Select-Object -First 4) -join ' / ')
}

$Pruebas['m9 mapa: sin plantilla el prompt no lleva mapa, y la regla de capas sale igual'] = {
  $e = Escenario-M6 'm9-mapa-sin-plantilla'
  $r = Rescate @('-Modo', 'fix', '-Repo', $e.Repo, '-Paso', 'estructura', '-SinPlan', '-Auto', '-Si', '-MaxIntentos', '1') ''
  $l = @(Llamadas-M6 $e 'lote')
  if ($l.Count -eq 0) { Comprueba 'hay un lote' $false (Cola $r.Salida); return }
  $p = Prompt-M6 $e $l[0]
  Comprueba 'no hay mapa' ($p -notmatch 'Mapa de paquetes' -and $p -notmatch 'Paquetes de la PLANTILLA') $p
  Comprueba 'la regla de capas sale' ((Antes-De-Tocar $p).Contains($ReglaCapas)) $p
}

$LineaAdaptadores = 'El adaptador de entrada depende del puerto, nunca de un adaptador de salida. Si la pieza comun necesita otra operacion, anadela al puerto y a todos sus adaptadores.'

$Pruebas['m9 mapa: el prompt de un lote lleva tambien la linea de adaptadores, junto a la regla de capas'] = {
  $e = Escenario-M6 'm9-mapa-adaptadores' @{ Orden = @('estructura', 'ficheros') }
  $r = Fix-M6 $e 'ficheros' 1 @() ''
  $l = @(Llamadas-M6 $e 'lote')
  if ($l.Count -eq 0) { Comprueba 'hay un lote' $false (Cola $r.Salida); return }
  $a = Antes-De-Tocar (Prompt-M6 $e $l[0])
  Comprueba 'la regla de capas y la de adaptadores, en la misma linea' ($a.Contains($ReglaCapas + ' ' + $LineaAdaptadores)) $a
}

# El plan: lo que escribe la IA se comprueba contra los paquetes de la plantilla.
function Plan-M9([string]$Nombre, [string]$Guion) {
  $e = Escenario-M6 $Nombre
  $r = Rescate @('-Modo', 'plan', '-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-Paso', 'estructura', '-SinBuild', '-Si') $Guion
  return [pscustomobject]@{ E = $e; R = $r; Llamadas = @(Llamadas-M6 $e 'plan') }
}

$Pruebas['m9 plan: el prompt del plan lleva el mapa de paquetes de la plantilla, la regla de capas y la linea de adaptadores'] = {
  $x = Plan-M9 'm9-plan-prompt' ''
  if ($x.Llamadas.Count -eq 0) { Comprueba 'hay una llamada de plan' $false (Cola $x.R.Salida); return }
  $p = Prompt-M6 $x.E $x.Llamadas[0]
  $m = @(Mapa-Del-Prompt $p)
  Comprueba 'la cabecera del mapa' ($m.Count -gt 0 -and $m[0] -ceq $CabeceraMapa) $p
  Comprueba 'lleva el paquete de los puertos de salida con su clase' ($m -contains '- application/ports/output: FicheroPort') ($m -join ' / ')
  Comprueba 'va despues de las referencias' ($p.IndexOf('## Referencias') -lt $p.IndexOf('## Mapa de paquetes')) $p
  Comprueba 'lleva la regla de capas y la linea de adaptadores' ($p.Contains($ReglaCapas) -and $p.Contains($LineaAdaptadores)) $p
}

$Pruebas['m9 plan: un paquete que la plantilla no tiene, en las piezas comunes o en un destino, repite el plan una vez con el motivo'] = {
  foreach ($g in @('plan-paquete-nuevo', 'plan-destino-nuevo')) {
    $x = Plan-M9 "m9-plan-malo-$g" $g
    Igual "$g`: dos llamadas de plan" 2 $x.Llamadas.Count
    if ($x.Llamadas.Count -lt 2) { Comprueba "$g`: salida" $false (Cola $x.R.Salida); continue }
    $p2 = Prompt-M6 $x.E $x.Llamadas[1]
    Comprueba "$g`: la segunda lleva el motivo con el paquete y la clase o fichero" ($p2 -match '## CORRECCION' -and $p2 -match 'infrastructure/util') $p2
    Comprueba "$g`: la segunda sigue siendo la revision previa del mismo paso" ($p2 -match "revision previa del paso 'estructura'") $p2
    Comprueba "$g`: la primera no lleva correccion" ((Prompt-M6 $x.E $x.Llamadas[0]) -notmatch '## CORRECCION')
    Comprueba "$g`: la consola dice que lo repite" ($x.R.Salida -match 'lo repito una vez con el motivo') (Cola $x.R.Salida)
    $plan = Lee $x.E.Wt '.rescate/plan-estructura.md'
    Comprueba "$g`: el plan que queda es el bueno" ($plan -notmatch 'infrastructure[/.]util' -and $plan -match 'ports[/.]output|application/ports/output') $plan
    Comprueba "$g`: no avisa de paquetes de mas" ($x.R.Salida -notmatch 'sigue nombrando') (Cola $x.R.Salida)
    Igual "$g`: sale con 0" 0 $x.R.Codigo
  }
}

$Pruebas['m9 plan: un plan bueno no se repite, ni uno sin nada que comprobar'] = {
  foreach ($g in @('plan-paquete-bueno', '', 'plan-ilegible')) {
    $x = Plan-M9 "m9-plan-ok-$g" $g
    Igual "'$g'`: una sola llamada de plan" 1 $x.Llamadas.Count
    Comprueba "'$g'`: no habla de repetir" ($x.R.Salida -notmatch 'lo repito una vez') (Cola $x.R.Salida)
    Igual "'$g'`: sale con 0" 0 $x.R.Codigo
  }
}

$Pruebas['m9 plan: si la repeticion vuelve a nombrar un paquete que no esta, sigue con el plan y lo avisa'] = {
  $x = Plan-M9 'm9-plan-siempre' 'plan-paquete-nuevo-siempre'
  Igual 'dos llamadas de plan, no tres' 2 $x.Llamadas.Count
  Comprueba 'avisa de que sigue nombrando el paquete' ($x.R.Salida -match 'El plan sigue nombrando paquetes que la plantilla no tiene: .*infrastructure/util') (Cola $x.R.Salida)
  Comprueba 'el plan queda escrito' (Test-Path -LiteralPath (Get-Ruta $x.E.Wt '.rescate/plan-estructura.md')) (Cola $x.R.Salida)
  Comprueba 'dice el plan escrito y no para' ($x.R.Salida -match 'Plan escrito') (Cola $x.R.Salida)
  Igual 'sale con 0' 0 $x.R.Codigo
}

# ===== M9.2: EL MOTIVO DEL TEST QUE FALLA Y EL TEXTO DE 'estructura' =====
# Informes de surefire como los que escribe Maven (el fallo de ArchUnit y el de una excepcion), con sus lineas 'at' con tabulador.
$ClaseM92 = 'com.acme.life.ArquitecturaTest'
$TestM92 = 'src/test/java/com/acme/life/ArquitecturaTest.java'
$RayaM92 = '-------------------------------------------------------------------------------'
$ReglaM92 = "Architecture Violation [Priority: MEDIUM] - Rule 'domain must not depend on application' was violated (2 times):"
$ClaseUnoM92 = 'Class <com.acme.life.domain.model.Poliza> depends on class <com.acme.life.application.usecases.Suelta> in (Poliza.java:12)'
$ClaseDosM92 = 'Class <com.acme.life.domain.model.Poliza> depends on class <com.acme.life.application.usecases.LeerFichero> in (Poliza.java:15)'
$MotivoArchM92 = 'java.lang.AssertionError: | ' + $ReglaM92 + ' | ' + $ClaseUnoM92

function Pila-M92([string[]]$Lineas) { return @($Lineas | ForEach-Object { "`tat " + $_ }) }

# El informe de surefire de $ClaseM92: la cabecera, la linea de resumen y las lineas de sus metodos que fallan.
function Informe-M92([string]$Resumen, [string[]]$Metodos) {
  return ((@($RayaM92, "Test set: $ClaseM92", $RayaM92, $Resumen) + @($Metodos)) -join "`n") + "`n"
}

$ResumenFalloM92 = "Tests run: 2, Failures: 1, Errors: 0, Skipped: 0, Time elapsed: 0.8 s <<< FAILURE! - in $ClaseM92"

function Informe-Arch {
  return (Informe-M92 $ResumenFalloM92 (@('capasRespetadas  Time elapsed: 0.4 s  <<< FAILURE!', 'java.lang.AssertionError: ', $ReglaM92, $ClaseUnoM92, $ClaseDosM92, '') +
      (Pila-M92 @('com.tngtech.archunit.lang.ArchRule$Assertions.assertNoViolation(ArchRule.java:94)', 'com.acme.life.ArquitecturaTest.capasRespetadas(ArquitecturaTest.java:20)'))))
}

# El motivo de un metodo con <<< ERROR!: la excepcion, su pila, y la causa con la suya y con otra pila.
$ExcepcionM92 = 'java.lang.IllegalStateException: Failed to load ApplicationContext'
$CausaM92 = "Caused by: org.springframework.beans.factory.BeanCreationException: Error creating bean with name 'pagoPort'"
function Informe-Error {
  $r = "Tests run: 1, Failures: 0, Errors: 1, Skipped: 0, Time elapsed: 0.3 s <<< FAILURE! - in $ClaseM92"
  return (Informe-M92 $r (@('cargaElContexto  Time elapsed: 0.2 s  <<< ERROR!', $ExcepcionM92) +
      (Pila-M92 @('org.springframework.test.context.cache.DefaultCacheAwareContextLoaderDelegate.loadContext(DefaultCacheAwareContextLoaderDelegate.java:132)', 'org.springframework.test.context.support.DefaultTestContext.getApplicationContext(DefaultTestContext.java:124)')) +
      @($CausaM92) + (Pila-M92 @('org.springframework.beans.factory.support.AbstractAutowireCapableBeanFactory.createBean(AbstractAutowireCapableBeanFactory.java:597)'))))
}

# Repo de juguete con un test que falla (ArquitecturaTest, con paquete) ya en un commit.
function Escenario-Test-Roto([string]$Nombre, [hashtable]$Mas = @{}) {
  $e = Escenario-M6 $Nombre $Mas
  Escribe $e.Repo $TestM92 "package com.acme.life;`n`nclass ArquitecturaTest { /* TEST_FALLA */ }`n"
  [void](GitEn $e.Repo @('add', '--', $TestM92))
  [void](GitEn $e.Repo @('commit', '-q', '-m', 'test de arquitectura'))
  return $e
}

# Pone el informe de surefire que dejara el Maven de mentira (RESCATE_SUREFIRE_TXT) y devuelve la ruta de su fichero.
function Pon-Informe([string]$Texto) {
  $f = Join-Path $Dir ('informe-surefire-' + [System.Guid]::NewGuid().ToString('N').Substring(0, 8) + '.txt')
  [System.IO.File]::WriteAllText($f, $Texto)
  $env:RESCATE_SUREFIRE_TXT = $f
}

# El diagnostico con Maven del repo con ese informe de surefire: lo que sale y los hallazgos de 'tests'.
function Diagnostica-Con-Informe($E, [string]$Texto) {
  Pon-Informe $Texto
  try { $r = Rescate @('-Repo', $E.Repo, '-Plantilla', $E.Plantilla) }
  finally { $env:RESCATE_SUREFIRE_TXT = '' }
  return [pscustomobject]@{ R = $r; H = @(Hallazgos $E.Repo | Where-Object { $_.Cat -eq 'tests' }) }
}

# El texto de esas funciones de rescate.ps1, para cargarlas sin ejecutarlo: . ([scriptblock]::Create(...)).
function Texto-De-Funciones([string[]]$Nombres) {
  $ast = [System.Management.Automation.Language.Parser]::ParseFile($Script, [ref]$null, [ref]$null)
  $fs = @($ast.FindAll({ param($x) $x -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | Where-Object { $Nombres -contains $_.Name })
  return (@($fs | ForEach-Object { $_.Extent.Text }) -join "`n")
}

# El hallazgo tal como era antes del motivo: sin esa propiedad.
function Sin-Motivo($H) { return [pscustomobject]@{ Cat = $H.Cat; Sev = $H.Sev; Fichero = $H.Fichero; Linea = $H.Linea; Detalle = $H.Detalle } }

$Pruebas['m92 motivo: un fallo de ArchUnit con su pila deja las 3 primeras lineas sin at como motivo, aparte del detalle'] = {
  $e = Escenario-Test-Roto 'm92-arch'
  $d = Diagnostica-Con-Informe $e (Informe-Arch)
  Igual 'sale con 0' 0 $d.R.Codigo
  Igual 'un hallazgo de tests' 1 $d.H.Count
  if ($d.H.Count -ne 1) { return }
  $h = $d.H[0]
  Igual 'el fichero es el del test' $TestM92 $h.Fichero
  Igual 'el detalle es el de siempre, sin el motivo' "1 test(s) fallan en $ClaseM92 (ver target/surefire-reports)" $h.Detalle
  Igual 'el motivo son las 3 primeras lineas, unidas con " | " y sin la linea Class de mas' $MotivoArchM92 $h.Motivo
  Comprueba 'sin lineas at ni Time elapsed' ($h.Motivo -and $h.Motivo -notmatch '(^| \| )at ' -and $h.Motivo -notmatch 'Time elapsed' -and $h.Motivo -notmatch 'LeerFichero') $h.Motivo
  . ([scriptblock]::Create((Texto-De-Funciones @('Get-ClaveHallazgo'))))
  Igual 'la clave del hallazgo es la misma que sin motivo' (Get-ClaveHallazgo (Sin-Motivo $h)) (Get-ClaveHallazgo $h)
}

$Pruebas['m92 motivo: con <<< ERROR! (una excepcion) tambien sale el motivo, con su causa y sin la pila'] = {
  $e = Escenario-Test-Roto 'm92-error'
  $d = Diagnostica-Con-Informe $e (Informe-Error)
  Igual 'un hallazgo de tests' 1 $d.H.Count
  if ($d.H.Count -ne 1) { return }
  Igual 'el motivo es la excepcion y su causa' ($ExcepcionM92 + ' | ' + $CausaM92) $d.H[0].Motivo
}

$Pruebas['m92 motivo: sin motivo legible el hallazgo es el de siempre, sin propiedad nueva'] = {
  $e = Escenario-Test-Roto 'm92-sin-motivo'
  # solo la linea de resumen (lleva <<< FAILURE!, pero es la de la clase: no es un metodo)
  $d = Diagnostica-Con-Informe $e (Informe-M92 $ResumenFalloM92 @())
  Igual 'un hallazgo de tests' 1 $d.H.Count
  if ($d.H.Count -ne 1) { return }
  Igual 'el hallazgo solo tiene las 5 propiedades de siempre' 'Cat Detalle Fichero Linea Sev' ((@($d.H[0].PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object)) -join ' ')
  Igual 'el detalle es el de siempre' "1 test(s) fallan en $ClaseM92 (ver target/surefire-reports)" $d.H[0].Detalle
  # un metodo que falla pero solo trae la pila
  $d2 = Diagnostica-Con-Informe $e (Informe-M92 $ResumenFalloM92 (@('capasRespetadas  Time elapsed: 0.4 s  <<< FAILURE!') + (Pila-M92 @('com.acme.life.ArquitecturaTest.capasRespetadas(ArquitecturaTest.java:20)'))))
  Igual 'con solo la pila, un hallazgo de tests' 1 $d2.H.Count
  if ($d2.H.Count -eq 1) { Comprueba 'con solo la pila tampoco hay motivo' ($null -eq $d2.H[0].PSObject.Properties['Motivo']) ($d2.H[0] | ConvertTo-Json -Compress) }
}

$Pruebas['m92 motivo: un motivo de 2000 caracteres se corta a 400'] = {
  $e = Escenario-Test-Roto 'm92-tope'
  $largo = 'java.lang.AssertionError: ' + ('x' * 2000)
  $d = Diagnostica-Con-Informe $e (Informe-M92 $ResumenFalloM92 @('capasRespetadas  Time elapsed: 0.4 s  <<< FAILURE!', $largo, $ClaseUnoM92))
  Igual 'un hallazgo de tests' 1 $d.H.Count
  if ($d.H.Count -ne 1) { return }
  Igual 'el motivo mide 400' 400 ([string]$d.H[0].Motivo).Length
  Comprueba 'y es el principio de la linea larga' ([bool]$d.H[0].Motivo -and $largo.StartsWith(([string]$d.H[0].Motivo))) ('motivo: ' + [string]$d.H[0].Motivo)
}

$Pruebas['m92 motivo: la linea del prompt del lote y el detalle de la consola tras un NO PASA llevan motivo:'] = {
  $e = Escenario-Test-Roto 'm92-linea' @{ Orden = @('tests') }
  Pon-Informe (Informe-Arch)
  try { $r = Fix-M6 $e 'tests' 1 @() 'crea-fichero' }
  finally { $env:RESCATE_SUREFIRE_TXT = '' }
  $lotes = @(Llamadas-M6 $e 'lote')
  Comprueba 'hay un lote de tests' ($lotes.Count -ge 1) (Cola $r.Salida)
  if ($lotes.Count -eq 0) { return }
  $linea = '- ' + $TestM92 + " - 1 test(s) fallan en $ClaseM92 (ver target/surefire-reports) - motivo: " + $MotivoArchM92
  $p = Prompt-M6 $e $lotes[0]
  Comprueba 'la linea del hallazgo del prompt lleva el motivo' (@($p -split "`r?`n") -contains $linea) (([regex]::Match($p, '(?s)## Hallazgos de este lote.*?(?=## Reglas)')).Value)
  $c1 = Consola-Del-Intento $r.Salida 1
  Comprueba 'el intento no pasa' ($c1 -match 'NO PASA') $c1
  $det = @(Detalle-De-Consola $c1 | Where-Object { $_ -match 'ArquitecturaTest' })
  Comprueba 'el detalle de la consola lleva la linea con el motivo' ($det.Count -ge 1 -and $det[0] -ceq ('    ' + $linea)) ($det -join ' / ')
}

$Pruebas['m92 motivo: la misma clase que falla antes y despues con otro motivo no es un hallazgo nuevo ni otro fallo'] = {
  $e = Escenario-Test-Roto 'm92-mismo'
  $antes = Diagnostica-Con-Informe $e (Informe-Arch)
  $despues = Diagnostica-Con-Informe $e (Informe-M92 $ResumenFalloM92 @('capasRespetadas  Time elapsed: 0.4 s  <<< FAILURE!', 'java.lang.AssertionError: ', "Architecture Violation [Priority: MEDIUM] - Rule 'application must not depend on infrastructure' was violated (1 times):", 'Class <com.acme.life.application.usecases.CargarPolizasUseCase> depends on class <com.acme.life.infrastructure.adapters.output.file.FicheroLocalAdapter> in (CargarPolizasUseCase.java:7)'))
  Comprueba 'antes y despues hay un hallazgo de tests' ($antes.H.Count -eq 1 -and $despues.H.Count -eq 1) "$($antes.H.Count) y $($despues.H.Count)"
  if ($antes.H.Count -ne 1 -or $despues.H.Count -ne 1) { return }
  Comprueba 'los motivos son distintos' ($antes.H[0].Motivo -and $despues.H[0].Motivo -and $antes.H[0].Motivo -cne $despues.H[0].Motivo) "$($antes.H[0].Motivo) / $($despues.H[0].Motivo)"
  . ([scriptblock]::Create((Texto-De-Funciones @('Get-ClaveHallazgo', 'Get-HallazgosNuevos', 'Get-ClaveFallo', 'Test-FalloRepetido'))))
  $hallAntes = @{}
  foreach ($x in $antes.H) { $hallAntes[(Get-ClaveHallazgo $x)] = $true }
  Igual 'Get-HallazgosNuevos no lo cuenta como nuevo' 0 @(Get-HallazgosNuevos $despues.H @('tests') $hallAntes).Count
  # como si fuera un hallazgo nuevo en los dos intentos, con otro NO PASA: solo la clave dice si es el mismo fallo
  $a = Get-ClaveFallo @('Los hallazgos de tests no han bajado (1 -> 1).') $antes.H
  $b = Get-ClaveFallo @('El proyecto no compila.') $despues.H
  Comprueba 'Test-FalloRepetido lo ve como el mismo fallo' (Test-FalloRepetido $a $b) "$($a.Nuevos) / $($b.Nuevos)"
}

$Pruebas['m92 estructura: el texto del paso manda actualizar los imports de todos los ficheros y, ante ArchUnit, cambiar el destino y no el test'] = {
  $e = Nuevo-Escenario 'm92-estructura'
  [void](Rescate @('-Modo', 'fix', '-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-Paso', 'estructura', '-SinPlan', '-Lote', '1', '-Saltar', '1', '-Auto', '-Si', '-MaxIntentos', '1'))
  $p = Lee $e.Wt '.rescate/prompt.md'
  $texto = 'Mueve las clases listadas a la capa y paquete que les corresponde, copiando exactamente la estructura de paquetes y la convencion de nombres de la PLANTILLA. Solo mover: no cambies logica. Actualiza el package de cada clase movida y los imports de TODOS los ficheros que la usan, tambien los que no estan en la lista: las clases que estaban en su mismo paquete no tenian import y ahora lo necesitan. Mueve tambien sus tests al paquete equivalente. Si falla un test de arquitectura del repo (ArchUnit), su motivo dice que regla rompes: cambia el destino de la clase, no el test.'
  $que = ([regex]::Match($p, '(?s)## Que hay que hacer.*?(?=## Hallazgos)')).Value
  Comprueba 'el prompt lleva el texto del paso entero' ($p.Contains($texto)) $que
  Comprueba 'lleva "tambien los que no estan en la lista"' ($p.Contains('tambien los que no estan en la lista')) $que
  Comprueba 'lleva "no el test"' ($p.Contains('no el test')) $que
  Comprueba 'ya no dice "Solo mover y actualizar package e imports"' (-not $p.Contains('Solo mover y actualizar package e imports')) $que
}

# ================================ LANZADOR ================================
Invoke-Banco $Pruebas $Script
