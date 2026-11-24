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
  Comprueba 'dice como traer los cambios' ($r.Salida -match 'git -C "[^"]+" merge rescate/main-')
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
  Igual 'MvnExe fuera del repo: su ruta, sin ./' (Join-Path $falsos 'm20a-mvn.ps1') (Maven-Del-Prompt $e)   # el de Pon-Config
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
  Escribe $e.Repo '.mvn/wrapper/maven-wrapper.properties' "distributionUrl=x`n"   # sin este fichero Get-Mvn no usa el mvnw (M30)
  [void](GitEn $e.Repo @('add', '--', $w, '.mvn/wrapper/maven-wrapper.properties'))
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
  ($Base + 'infrastructure/adapters/output/ftp/LectorLocal.java') = "package com.acme.plantilla.infrastructure.adapters.output.ftp;`n`nimport java.io.File;`n`n/** Lee ficheros locales a pelo. */`npublic class LectorLocal {`n    private final File carpeta = new File(`".`");`n}`n"
  ($Base + 'infrastructure/adapters/output/ftp/EscritorLocal.java') = "package com.acme.plantilla.infrastructure.adapters.output.ftp;`n`nimport java.io.FileWriter;`n`n/** Escribe ficheros locales a pelo. */`npublic class EscritorLocal {`n    private FileWriter salida;`n}`n"
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
$LectorFuera = "package com.acme.plantilla.infrastructure.adapters.output.ftp;`n`nimport java.io.File;`n`n/** Lee ficheros locales a pelo. */`npublic class LectorLocal {`n    private final File carpeta = new File(`".`");`n}`n"

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
      ($Base + 'infrastructure/adapters/output/ftp/LectorLocal.java')          = $LectorFuera
    })
  $r = Rescate @('-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-SinBuild')
  Igual 'sale con 0' 0 $r.Codigo
  Comprueba 'la consola dice ficheros 1' (@($r.Salida -split "`r?`n") -contains 'Plantilla incumple: capas 0 | ficheros 1 | calidad 0 | secretos 0') (Cola $r.Salida)
  $p = Permitido-Del-Informe $e
  Comprueba 'lo permitido lista solo el uso de fuera' ($p -match '- infrastructure/adapters/output/ftp -> java\.io' -and $p -notmatch 'output/file' -and $p -notmatch 'java\.nio') $p
}

# ======================= LATIDO MIENTRAS ESPERA ========================
# Mientras Copilot o Maven tardan, la consola escribe cada SegundosLatido una linea
# "  ... sigue: <que> (lleva N min M s)" para que se vea que el script no esta colgado.
function Lineas-Latido([string]$Salida) { return @($Salida -split "`r?`n" | Where-Object { $_ -match '^\s*\.\.\. sigue' }) }

# El config.json del repo del escenario: Maven y Copilot, los falsos, y sin reflexion (estas pruebas cuentan las llamadas
# a Copilot; la reflexion tiene las suyas, en M6), mas estos ajustes (nombre -> valor).
function Pon-Config($E, [hashtable]$Mas) {
  $cfg = [ordered]@{ CopilotExe = (Join-Path $falsos 'copilot.ps1'); MvnExe = (Join-Path $falsos 'm20a-mvn.ps1'); Reflexionar = $false }
  foreach ($k in $Mas.Keys) { $cfg[$k] = $Mas[$k] }
  Escribe $E.Repo '.rescate/config.json' (ConvertTo-Json -InputObject $cfg)
}

$ArgsFix = @('-Modo', 'fix', '-Paso', 'estructura', '-SinPlan', '-Auto', '-Si', '-MaxIntentos', '1')

$Pruebas['latido: mientras Copilot tarda, la consola dice que sigue, y el arreglo sale como siempre'] = {
  $e = Nuevo-Escenario 'latido-copilot'
  Pon-Config $e @{ SegundosLatido = 1 }
  $r = Rescate (@('-Repo', $e.Repo, '-Plantilla', $e.Plantilla) + $ArgsFix) 'lento'
  Igual 'el fix sale con 0' 0 $r.Codigo
  # Con la maquina cargada, el Maven falso tambien puede pasar de 1 s y dejar su linea: aqui solo cuentan las de Copilot
  $l = Lineas-Latido $r.Salida
  $lc = @($l | Where-Object { $_ -match '^  \.\.\. sigue: Copilot ' })
  Comprueba 'hay al menos una linea del latido de Copilot' ($lc.Count -ge 1) (Cola $r.Salida)
  # el tope es holgado a proposito: el arranque de pwsh bajo carga suma segundos a los 3 del falso
  Comprueba 'y no un aluvion (como mucho 6)' ($lc.Count -le 6) ($lc.Count.ToString() + ' lineas')
  Comprueba 'cada una dice a quien espera y cuanto lleva' (@($l | Where-Object { $_ -match '^  \.\.\. sigue: (Copilot|Maven) .*\(lleva \d+ min \d+ s\)$' }).Count -eq $l.Count) ($l -join ' / ')
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
# tests/falsos/mvn-dormido.ps1 (escribe una linea, lanza un hijo que duerme y duerme 120 s) y un tope de 0.05 min (3 s). Si el tope
# no parase a Maven, la pasada duraria mas de 120 s: el limite de 90 s deja margen al resto de la pasada con la maquina cargada.

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
  $env:RESCATE_MVN_SEGUNDOS = '120'
  $reloj = [System.Diagnostics.Stopwatch]::StartNew()
  try { $r = Rescate @('-Repo', $e.Repo, '-Plantilla', $e.Plantilla) }
  finally { $env:RESCATE_MVN_CUELGA = ''; $env:RESCATE_MVN_PIDS = ''; $env:RESCATE_MVN_SEGUNDOS = '' }
  $seg = $reloj.Elapsed.TotalSeconds
  Igual 'el diagnostico sale con 0, como con un build que falla' 0 $r.Codigo
  $h = @(Hallazgos $e.Repo | Where-Object { $_.Cat -eq 'build' -and $_.Sev -eq 'error' })
  Igual 'hay un hallazgo de build' 1 $h.Count
  $reg = Join-Path (Join-Path $e.Repo '.rescate') 'build.log'
  $ini = 'el build falla: Maven se ha pasado del tope de 0.05 min y se ha parado (Maven (tests)). Registro: '
  Comprueba 'su detalle dice que el build falla y que Maven se paso (0.05: manda el config.json)' ($h.Count -gt 0 -and $h[0].Detalle.StartsWith($ini)) (Cola $r.Salida)
  Comprueba 'y acaba en la ruta del registro' ($h.Count -gt 0 -and $h[0].Detalle.EndsWith('build.log.')) (Cola $r.Salida)
  Comprueba-Tope $carpPids $seg 90 $reg
}

$Pruebas['tope de Maven: rescate, lote: si Maven se pasa al comprobar, el lote se deshace y la consola lo dice'] = {
  $e = Nuevo-Escenario 'tope-lote'
  Pon-Config $e @{ MvnExe = (Join-Path $falsos 'mvn-dormido.ps1'); MinutosMaven = 0.05 }
  $carpPids = Join-Path $Dir 'tope-t4-pids'
  $env:RESCATE_MVN_CUELGA = '[ |]test$'
  $env:RESCATE_MVN_PIDS = $carpPids
  $env:RESCATE_MVN_DESDE = '2'
  $env:RESCATE_MVN_SEGUNDOS = '120'
  $reloj = [System.Diagnostics.Stopwatch]::StartNew()
  try { $r = Rescate (@('-Repo', $e.Repo, '-Plantilla', $e.Plantilla) + $ArgsFix) }
  finally { $env:RESCATE_MVN_CUELGA = ''; $env:RESCATE_MVN_PIDS = ''; $env:RESCATE_MVN_DESDE = ''; $env:RESCATE_MVN_SEGUNDOS = '' }
  $seg = $reloj.Elapsed.TotalSeconds
  # el diagnostico inicial hace una sola llamada de tests (la 1.a, que pasa); se cuelgan todas las demas (la del lote y los reintentos
  # de uno en uno, hasta que paran los lotes deshechos seguidos), y cada llamada colgada anota 2 PID
  $cuenta = @([System.IO.File]::ReadAllLines((Join-Path $carpPids 'cuenta.txt')))
  $colgadas = @([System.IO.File]::ReadAllLines((Join-Path $carpPids 'pids.txt')) | Where-Object { $_ }).Count
  Comprueba 'la 1.a llamada de tests (el diagnostico inicial) pasa y se cuelgan todas las demas, desde la del lote' ($cuenta.Count -ge 2 -and $colgadas -eq 2 * ($cuenta.Count - 1)) "llamadas: $($cuenta.Count), PID anotados: $colgadas"
  Comprueba 'el lote 1 se deshace' ($r.Salida -match 'Lote 1 DESHECHO') (Cola $r.Salida)
  Comprueba 'y la consola dice que Maven se paso' ($r.Salida -match [regex]::Escape('Maven se ha pasado del tope de 0.05 min y se ha parado (Maven (tests)). Registro: ')) (Cola $r.Salida)
  Comprueba 'sin ningun commit del lote' (-not (Hay-Commit-Del-Lote $e)) (Cola $r.Salida)
  Comprueba-Tope $carpPids $seg 90 (Join-Path (Join-Path $e.Wt '.rescate') 'build.log')
}

# ============================ TOPE DE COPILOT ============================
# Pasados MinutosCopilot minutos se para Copilot con sus procesos hijos y la llamada cuenta como fallida (Codigo -1, Tope con el
# mensaje). El intento se evalua como cualquier otro y no se repite la llamada por el 'rc distinto de 0 sin cambios' del M9 A.
# Estas pruebas lo cuelgan con tests/falsos/copilot-dormido.ps1 (lanza un hijo que duerme y duerme 120 s) y un tope de 0.05 min (3 s).

# Lo que se comprueba en todo tope hecho con copilot-dormido.ps1: sus PID (el del falso y el de su hijo, en $CarpetaPids\pids.txt)
# ya no viven (10 s de plazo) y la pasada entera ha tardado menos de $Limite s (el falso duerme 120 por llamada).
function Comprueba-Tope-Copilot([string]$CarpetaPids, [double]$Segundos, [int]$Limite) {
  $nums = @()
  $f = Join-Path $CarpetaPids 'pids.txt'
  if (Test-Path -LiteralPath $f) { $nums = @([System.IO.File]::ReadAllLines($f) | Where-Object { $_ } | ForEach-Object { [int]$_ }) }
  $plazo = (Get-Date).AddSeconds(10)
  do {
    $vivos = @($nums | Where-Object { Proceso-Vivo $_ })
    if ($vivos.Count -eq 0) { break }
    Start-Sleep -Milliseconds 200
  } while ((Get-Date) -lt $plazo)
  Comprueba 'Copilot se colgo (anoto su PID y el de su hijo) y ninguno de los dos vive' ($nums.Count -ge 2 -and $vivos.Count -eq 0) ("PID: $($nums -join ' '), vivos: $($vivos -join ' ')")
  Comprueba "la pasada no espero al falso: menos de $Limite s" ($Segundos -lt $Limite) "$Segundos s"
}

# Lanza rescate.ps1 con estos argumentos y el Copilot que se cuelga en las llamadas cuya primera linea del prompt casa con $Cuelga
# ($Antes: antes de colgarse hace lo que haria el Copilot normal). Devuelve R (codigo y consola), Segundos, Pids (la carpeta de los
# PID), Llamadas (las que se colgaron: una linea por llamada) y Dormidos (los PID anotados).
function Rescate-Dormido($E, [string]$Cuelga, [string[]]$A, [bool]$Antes = $false) {
  $carp = Join-Path (Split-Path -Parent $E.Repo) 'cop-pids'
  $env:RESCATE_COP_CUELGA = $Cuelga
  $env:RESCATE_COP_PIDS = $carp
  if ($Antes) { $env:RESCATE_COP_ANTES = '1' }
  $env:RESCATE_COP_SEGUNDOS = '120'
  $reloj = [System.Diagnostics.Stopwatch]::StartNew()
  try { $r = Rescate $A }
  finally { $env:RESCATE_COP_CUELGA = ''; $env:RESCATE_COP_PIDS = ''; $env:RESCATE_COP_ANTES = ''; $env:RESCATE_COP_SEGUNDOS = '' }
  $seg = $reloj.Elapsed.TotalSeconds
  $cuenta = Join-Path $carp 'cuenta.txt'
  $llamadas = @()
  if (Test-Path -LiteralPath $cuenta) { $llamadas = @([System.IO.File]::ReadAllLines($cuenta) | Where-Object { $_ }) }
  return [pscustomobject]@{ R = $r; Segundos = $seg; Pids = $carp; Llamadas = $llamadas }
}

$TopeCopilotLote = 'Copilot se ha pasado del tope de 0.05 min y se ha parado (Copilot (paso estructura, lote 1, intento 1)).'

$Pruebas['tope de Copilot: un lote que se cuelga se para con sus hijos, la consola lo dice, el intento se evalua y no se repite la llamada'] = {
  $e = Nuevo-Escenario 'cop-tope-lote'
  Pon-Config $e @{ CopilotExe = (Join-Path $falsos 'copilot-dormido.ps1'); MinutosCopilot = 0.05 }
  $x = Rescate-Dormido $e 'rescate de migracion: paso' (@('-Repo', $e.Repo, '-Plantilla', $e.Plantilla) + $ArgsFix)
  $r = $x.R
  Comprueba 'la consola dice que Copilot se paso del tope de 0.05 min (el de .rescate/config.json) y que se ha parado' (@($r.Salida -split "`n") -contains $TopeCopilotLote) (Cola $r.Salida)
  Comprueba 'el intento se evalua: no cambio ningun fichero y el lote se deshace' ($r.Salida -match 'Lote 1 DESHECHO: no paso las comprobaciones tras 1 intento\(s\)' -and (Lee $e.Wt '.rescate/intento-estructura-1-1.md') -match 'No has cambiado ningun fichero') (Cola $r.Salida)
  Comprueba 'no se repite la llamada por salir con error sin cambios' ($r.Salida -notmatch 'repito la llamada una vez' -and -not (Test-Path -LiteralPath (Get-Ruta $e.Wt '.rescate/lote-estructura-1-1-repeticion.log'))) (Cola $r.Salida)
  Comprueba 'y el registro del intento esta' (Test-Path -LiteralPath (Get-Ruta $e.Wt '.rescate/lote-estructura-1-1.log')) (Cola $r.Salida)
  Comprueba-Tope-Copilot $x.Pids $x.Segundos 90
}

$Pruebas['tope de Copilot: si Copilot arregla y despues se cuelga, el intento se evalua con lo que dejo en el arbol y pasa'] = {
  $e = Nuevo-Escenario 'cop-tope-arregla'
  Pon-Config $e @{ CopilotExe = (Join-Path $falsos 'copilot-dormido.ps1'); MinutosCopilot = 0.05 }
  $x = Rescate-Dormido $e 'rescate de migracion: paso' (@('-Repo', $e.Repo, '-Plantilla', $e.Plantilla) + $ArgsFix) $true
  $r = $x.R
  Comprueba 'la consola dice que Copilot se paso del tope' (@($r.Salida -split "`n") -contains $TopeCopilotLote) (Cola $r.Salida)
  Comprueba 'las puertas dan por bueno lo que dejo: lote 1 OK' ($r.Salida -match "Lote 1 OK: 'estructura'" -and $r.Salida -notmatch 'DESHECHO') (Cola $r.Salida)
  Comprueba 'hay commit del lote' ((GitEn $e.Wt @('log', '--format=%s')) -match 'rescate\(estructura\): lote 1') (Cola $r.Salida)
  Igual 'una sola llamada a Copilot, sin repeticion' 1 $x.Llamadas.Count
  Igual 'sale con 0' 0 $r.Codigo
  Comprueba-Tope-Copilot $x.Pids $x.Segundos 90
}

$Pruebas['tope de Copilot: sin pasar el tope todo sigue igual: el registro, la salida de la consola y la repeticion del M9 A'] = {
  $e = Escenario-M6 'cop-tope-igual' @{ Orden = @('estructura') }
  $r = Fix-M6 $e 'estructura' 1 @() 'falla-copilot'
  $nueve = "SALIDA-A primera`nSALIDA-B`n`nSALIDA-C`nSALIDA-D`n   `nSALIDA-E`nSALIDA-F`nSALIDA-G ultima"
  $reg = (Lee $e.Wt '.rescate/lote-estructura-1-1.log') -replace "`r", ''
  Igual 'el registro lleva las nueve lineas que escribio Copilot' ($nueve + "`n") $reg
  Comprueba 'la consola dice el codigo y el registro' ($r.Salida -match [regex]::Escape('Copilot termino con codigo 1 (ver .rescate/lote-estructura-1-1.log)')) (Cola $r.Salida)
  Comprueba 'y sus ultimas cinco lineas con texto' ($r.Salida -match '(?m)^    SALIDA-C' -and $r.Salida -match '(?m)^    SALIDA-G ultima' -and $r.Salida -notmatch '(?m)^    SALIDA-B') (Cola $r.Salida)
  Comprueba 'sin cambios y sin tope, se repite la llamada una vez' ($r.Salida -match 'repito la llamada una vez \(no cuenta como intento\)' -and $r.Salida -match 'Copilot termino otra vez con codigo 1') (Cola $r.Salida)
  Comprueba 'y no habla de ningun tope' ($r.Salida -notmatch 'se ha pasado del tope') (Cola $r.Salida)
  Comprueba 'el lote se deshace con su unico intento' ($r.Salida -match 'Lote 1 DESHECHO: no paso las comprobaciones tras 1 intento\(s\)') (Cola $r.Salida)
}

$GuionCfgCopilot = @'
param([string]$Sis, [string]$Repo)
. (Join-Path $Sis 'comun.ps1')
'DEFECTO ' + $Cfg.MinutosCopilot
$d = Read-CfgFile (Get-RutaAjustes) @() $false
'AJUSTES ' + $Cfg.MinutosCopilot
Read-Config $Repo
'REPO ' + $Cfg.MinutosCopilot
'@

$Pruebas['tope de Copilot: MinutosCopilot vale 20 por defecto, admite decimales y lo pisan ajustes.json y .rescate/config.json (el del repo, el ultimo)'] = {
  $e = Nuevo-Escenario 'cop-tope-config'
  $f = Join-Path $Dir 'cop-tope-guion.ps1'
  [System.IO.File]::WriteAllText($f, $GuionCfgCopilot)
  $casa = Join-Path $Dir 'cop-tope-casa'
  [void](New-Item -ItemType Directory -Path $casa -Force)
  [System.IO.File]::WriteAllText((Join-Path $casa 'ajustes.json'), '{ "MinutosCopilot": 7.5 }')
  Pon-Config $e @{ MinutosCopilot = 0.25 }
  $antes = $env:RESCATE_HOME
  try {
    $env:RESCATE_HOME = $CasaVacia
    $v1 = Claves-Del-Guion (Lanzar $f @((Split-Path -Parent $Script), $e.Repo)).Salida
    $env:RESCATE_HOME = $casa
    $v2 = Claves-Del-Guion (Lanzar $f @((Split-Path -Parent $Script), $e.Repo)).Salida
  }
  finally { $env:RESCATE_HOME = $antes }
  Igual 'el tope por defecto es de 20 minutos' '20' $v1['DEFECTO']
  Igual 'sin ajustes.json sigue valiendo 20' '20' $v1['AJUSTES']
  Igual 'con ajustes.json vale lo que dice (7.5, con decimales)' '7.5' $v2['AJUSTES']
  Igual 'el config.json del repo manda sobre el de por defecto' '0.25' $v1['REPO']
  Igual 'y sobre el de ajustes.json' '0.25' $v2['REPO']
}

$GuionNativo = @'
param([string]$Sis, [string]$Falso, [string]$Como)
. (Join-Path $Sis 'comun.ps1')
$p = Invoke-Proceso $Falso @() '' 20 ($Como -eq '1')
'CODIGO ' + $p.Codigo
'TEXTO ' + $p.Texto.Trim()
'@

$Pruebas['tope de Copilot: Invoke-Proceso con ComoNativo hereda la entrada del script, como Invoke-Nativo; sin ComoNativo la cierra, como siempre'] = {
  $f = Join-Path $Dir 'cop-nativo-guion.ps1'
  [System.IO.File]::WriteAllText($f, $GuionNativo)
  $lee = Join-Path $Dir 'cop-lee-entrada.ps1'
  [System.IO.File]::WriteAllText($lee, "'ENTRADA[' + [Console]::In.ReadToEnd().Trim() + ']'`n")
  $sis = Split-Path -Parent $Script
  $v1 = Claves-Del-Guion (Lanzar $f @($sis, $lee, '1') '' @('hola')).Salida
  $v0 = Claves-Del-Guion (Lanzar $f @($sis, $lee, '0') '' @('hola')).Salida
  Igual 'ComoNativo: el hijo lee lo que recibe el script' 'ENTRADA[hola]' $v1['TEXTO']
  Igual 'sin ComoNativo: la entrada esta cerrada' 'ENTRADA[]' $v0['TEXTO']
  Igual 'los dos salen con 0' '0 0' ($v1['CODIGO'] + ' ' + $v0['CODIGO'])
}

$Pruebas['tope de Copilot: la revision previa que se cuelga cuenta como fallida: sin plan, la consola lo dice y no se repite'] = {
  $e = Nuevo-Escenario 'cop-tope-plan'
  Pon-Config $e @{ CopilotExe = (Join-Path $falsos 'copilot-dormido.ps1'); MinutosCopilot = 0.05 }
  $x = Rescate-Dormido $e 'revision previa' @('-Modo', 'plan', '-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-Paso', 'estructura', '-SinBuild', '-Si')
  $r = $x.R
  Comprueba 'la consola dice que la revision previa se paso del tope' (@($r.Salida -split "`n") -contains 'Copilot se ha pasado del tope de 0.05 min y se ha parado (Copilot (revision previa, paso estructura)).') (Cola $r.Salida)
  Comprueba 'cuenta como fallida, igual que hoy: no ha escrito el plan y sigue sin plan' ($r.Salida -match 'Copilot no ha escrito el plan \(ver \.rescate/plan-estructura\.log\)\. Sigo sin plan\.' -and -not (Test-Path -LiteralPath (Get-Ruta $e.Wt '.rescate/plan-estructura.md'))) (Cola $r.Salida)
  Igual 'una sola llamada a Copilot' 1 $x.Llamadas.Count
  Igual 'sale con 0, como cuando Copilot falla' 0 $r.Codigo
  Comprueba-Tope-Copilot $x.Pids $x.Segundos 90
}

# ============================ SFTP COMO REGLA FIJA ============================
# Si el batch migrado maneja ficheros, tiene que traer el adaptador SFTP y su configuracion, tenga lo que tenga la
# referencia y tambien sin ella. El interruptor ExigirSftp (por defecto true) lo apaga: entonces solo se exige lo que la referencia tiene.
$SinAdaptadorSftp = 'no hay adaptador SFTP*'
$SinYmlSftp = 'application.yml no tiene configuracion sftp*'
# El texto cuando la plantilla no tiene un bloque sftp en un yml que copiar (M9.5).
$TextoSinBloqueM95 = 'application.yml no tiene configuracion sftp: anade un bloque ''sftp:'' (servidor, puerto, usuario, contrasena y rutas) con valores ${...} que salgan de la configuracion externa, como el resto de este application.yml; ningun valor real'

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
  Comprueba 'con lo que lleva el bloque' ($d -match [regex]::Escape('(servidor, puerto, usuario, contrasena y rutas)')) $d
  Comprueba 'y los valores salen de la configuracion externa' ($d -match [regex]::Escape('con valores ${...} que salgan de la configuracion externa, como el resto de este application.yml; ningun valor real')) $d
  Comprueba 'sin pedir copiar nada de la plantilla' ($d -notmatch 'PLANTILLA|plantilla') $d
  Comprueba 'el texto entero' ($d -ceq $TextoSinBloqueM95) $d
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
  Comprueba 'el aviso dice como recuperarlo, con el hash de ese stash (m45)' ($r.Salida.Contains('Lo he guardado en git stash (recuperalo con: git -C "' + $e.Wt + '" stash apply ' + (GitEn $e.Wt @('rev-parse', 'refs/stash')) + ').')) (Cola $r.Salida)
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
  Comprueba 'y salen tambien los hallazgos del paso' (@($det | Where-Object { $_ -match 'acceso directo a ficheros locales \(.+\): debe ir por el puerto de ficheros, una interfaz de application/ports/output que implementa un adaptador de infrastructure/adapters/output/file o sftp; fuera de esos adaptadores no se abre, lee, escribe, lista ni borra ningun fichero \(pasar un Path como dato si vale\)$' }).Count -eq 1) $c1
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
  Comprueba 'la nota del atascado lleva las lineas de detalle del ultimo intento' ($at -match '(?m)^    - src/main/java/com/acme/life/application/usecases/LeerOtro\d+\.java:\d+ - acceso directo a ficheros locales \(.+\): debe ir por el puerto de ficheros, una interfaz de application/ports/output que implementa un adaptador de infrastructure/adapters/output/file o sftp; fuera de esos adaptadores no se abre, lee, escribe, lista ni borra ningun fichero \(pasar un Path como dato si vale\)' -and $at -match '(?m)^    \(\d+ mas en \.rescate/intento-ficheros-\d+-\d+\.md\)') $at
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
  Escribe $e.Repo '.rescate/config.json' (ConvertTo-Json -InputObject ([ordered]@{ CopilotExe = (Join-Path $falsos 'copilot-m6.ps1'); MvnExe = (Join-Path $falsos 'm20a-mvn.ps1'); Orden = @('estructura', 'tests') }))
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
  Escribe $e.Repo '.rescate/config.json' (ConvertTo-Json -InputObject ([ordered]@{ CopilotExe = (Join-Path $falsos 'copilot-m6.ps1'); MvnExe = (Join-Path $falsos 'm20a-mvn.ps1'); Orden = @('estructura', 'tests') }))
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
    Comprueba "el prompt $($q[0]) pide despues los tests de Maven" ($q[1] -match '(?m)^- Ejecuta: .* -q -B -DskipTests=false "-Dmaven\.test\.skip=false" "-Dmaven\.test\.failure\.ignore=false" test  y corrige los tests que fallen\.$') $q[1]
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

# ----- M9.7: el plan no marca los paquetes que ya existen en el repo migrado -----
# Plan-M9 con una clase del repo (ya en su commit) en este paquete de com.acme.life (ruta con '/', relativa al paquete base).
function Plan-M97([string]$Nombre, [string]$Guion, [string]$PaqueteEnRepo) {
  $e = Escenario-M6 $Nombre
  $pk = 'com.acme.life.' + $PaqueteEnRepo.Replace('/', '.')
  Escribe $e.Repo ('src/main/java/com/acme/life/' + $PaqueteEnRepo + '/Marca.java') "package $pk;`n`n/** Clase que ya estaba en el repo migrado. */`npublic class Marca {`n}`n"
  [void](GitEn $e.Repo @('add', '--', 'src'))
  [void](GitEn $e.Repo @('commit', '-q', '-m', 'un paquete mas'))
  $r = Rescate @('-Modo', 'plan', '-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-Paso', 'estructura', '-SinBuild', '-Si') $Guion
  return [pscustomobject]@{ E = $e; R = $r; Llamadas = @(Llamadas-M6 $e 'plan') }
}

$Pruebas['m97 plan: un paquete que la plantilla no tiene pero el repo si (carpeta con clases o carpeta de un paquete con clases) no se marca ni se repite'] = {
  # guion, paquete que ya tiene el repo y lo que el plan nombra (el plan lista tambien la clase del repo, por eso se mira su nombre entero)
  foreach ($c in @(@('plan-paquete-nuevo', 'infrastructure/util', 'com\.acme\.life\.infrastructure\.util\.LeerFichero'), @('plan-destino-nuevo', 'infrastructure/util', 'destino: infrastructure/util'), @('plan-paquete-nuevo', 'infrastructure/util/interno', 'com\.acme\.life\.infrastructure\.util\.LeerFichero'))) {
    $x = Plan-M97 ('m97-plan-en-repo-' + $c[0] + '-' + $c[1].Replace('/', '-')) $c[0] $c[1]
    $q = "$($c[0]) con el repo en $($c[1])"
    Igual "$q`: una sola llamada de plan" 1 $x.Llamadas.Count
    Comprueba "$q`: no habla de repetir ni de paquetes que la plantilla no tiene" ($x.R.Salida -notmatch 'lo repito una vez' -and $x.R.Salida -notmatch 'nombra paquetes que la plantilla no tiene' -and $x.R.Salida -notmatch 'sigue nombrando') (Cola $x.R.Salida)
    Comprueba "$q`: el plan queda como lo escribio la IA, con el paquete del repo" ((Lee $x.E.Wt '.rescate/plan-estructura.md') -match $c[2]) (Cola $x.R.Salida)
    Comprueba "$q`: dice el plan escrito" ($x.R.Salida -match 'Plan escrito') (Cola $x.R.Salida)
    Igual "$q`: sale con 0" 0 $x.R.Codigo
  }
}

$Pruebas['m97 plan: un paquete que no tienen ni la plantilla ni el repo se sigue marcando, aunque el repo tenga otros que la plantilla no tiene'] = {
  # el repo tiene infrastructure/otra y el plan nombra infrastructure/util: ese no esta en ningun sitio
  $x = Plan-M97 'm97-plan-fuera-de-los-dos' 'plan-paquete-nuevo' 'infrastructure/otra'
  Igual 'dos llamadas de plan' 2 $x.Llamadas.Count
  if ($x.Llamadas.Count -lt 2) { Comprueba 'salida' $false (Cola $x.R.Salida); return }
  Comprueba 'la consola dice que lo repite y nombra el paquete y la clase' ($x.R.Salida -match 'lo repito una vez con el motivo' -and $x.R.Salida -match 'infrastructure/util \(en com\.acme\.life\.infrastructure\.util\.LeerFichero\)') (Cola $x.R.Salida)
  Comprueba 'sin nombrar el paquete que si esta en el repo' ($x.R.Salida -notmatch 'infrastructure/otra') (Cola $x.R.Salida)
  Comprueba 'la segunda llamada lleva el motivo' ((Prompt-M6 $x.E $x.Llamadas[1]) -match '## CORRECCION') (Cola $x.R.Salida)
  Comprueba 'el plan que queda es el bueno' ((Lee $x.E.Wt '.rescate/plan-estructura.md') -notmatch 'com\.acme\.life\.infrastructure\.util\.LeerFichero') (Cola $x.R.Salida)
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
  Igual 'el detalle es el del informe .txt: un hallazgo numerado por fallo, sin el motivo' "test 1 de 1 que fallan en $ClaseM92" $h.Detalle
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
  Igual 'el detalle es el del informe .txt: numerado, sin el motivo' "test 1 de 1 que fallan en $ClaseM92" $d.H[0].Detalle
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
  $linea = '- ' + $TestM92 + " - test 1 de 1 que fallan en $ClaseM92 - motivo: " + $MotivoArchM92
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

# ===== M9.3: LA CARPETA SFTP ES DE ADAPTADORES, Y LOS TEXTOS DE FICHEROS Y DE ENTRADA/SALIDA =====
$PkM93 = 'src/main/java/com/acme/life/'
$PorEntradaM93 = 'un adaptador de entrada no importa uno de salida: usa la interfaz de su puerto (application/ports/output) o un caso de uso, como en la PLANTILLA'
$FicherosM93 = 'acceso directo a ficheros locales (java.nio.file.Files): debe ir por el puerto de ficheros, una interfaz de application/ports/output que implementa un adaptador de infrastructure/adapters/output/file o sftp; fuera de esos adaptadores no se abre, lee, escribe, lista ni borra ningun fichero (pasar un Path como dato si vale)'
$AdaptadorRecursoM93 = "package com.acme.life.infrastructure.adapters.output.{0};`n`nimport org.springframework.core.io.FileSystemResource;`n`n/** Adaptador de salida que abre un recurso. */`npublic class Recurso {{`n    private FileSystemResource recurso;`n}}`n"

# Repo de juguete con: un adaptador de salida sftp y otro ftp que importan FileSystemResource, un tasklet de entrada que importa el adaptador de
# salida de ficheros y un caso de uso con java.nio.file.Files. Diagnostico sin Maven: lo que sale y los hallazgos.
function Escenario-M93([string]$Nombre) {
  $e = Nuevo-Escenario $Nombre
  Escribe $e.Repo ($PkM93 + 'infrastructure/adapters/output/sftp/RecursoSftp.java') ($AdaptadorRecursoM93 -f 'sftp')
  Escribe $e.Repo ($PkM93 + 'infrastructure/adapters/output/ftp/RecursoFtp.java') ($AdaptadorRecursoM93 -f 'ftp')
  Escribe $e.Repo ($PkM93 + 'infrastructure/adapters/input/job/CargaTasklet.java') "package com.acme.life.infrastructure.adapters.input.job;`n`nimport com.acme.life.infrastructure.adapters.output.file.FicheroLocalAdapter;`n`n/** Tasklet de entrada. */`npublic class CargaTasklet {`n    private FicheroLocalAdapter ficheros;`n}`n"
  Escribe $e.Repo ($PkM93 + 'application/usecases/RutaUseCase.java') "package com.acme.life.application.usecases;`n`nimport java.nio.file.Files;`n`n/** Caso de uso con una ruta. */`npublic class RutaUseCase {`n    private Files ruta;`n}`n"
  [void](GitEn $e.Repo @('add', '--', 'src/main/java'))
  [void](GitEn $e.Repo @('commit', '-q', '-m', 'm93'))
  $r = Rescate @('-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-SinBuild')
  return [pscustomobject]@{ E = $e; R = $r; H = @(Hallazgos $e.Repo) }
}

$Pruebas['m93 sftp: un fichero de output/sftp que importa FileSystemResource no da hallazgo de ficheros; el mismo codigo en output/ftp, si'] = {
  $x = Escenario-M93 'm93-sftp'
  Igual 'sale con 0' 0 $x.R.Codigo
  $f = @($x.H | Where-Object { $_.Cat -eq 'ficheros' })
  Igual 'el adaptador de output/sftp no tiene hallazgo de ficheros' 0 @($f | Where-Object { $_.Fichero -like '*output/sftp/*' }).Count
  Igual 'el de output/ftp, que no es de adaptadores permitidos, si' 1 @($f | Where-Object { $_.Fichero -like '*output/ftp/*' }).Count
}

$Pruebas['m93 sftp: una plantilla con un adaptador SFTP que abre FileSystemResource no incumple en ficheros'] = {
  $adaptador = ($AdaptadorRecursoM93 -f 'sftp').Replace('com.acme.life.', 'com.acme.plantilla.')
  $e = Escenario-Con-Plantilla 'm93-plantilla-sftp' (Limpia-Mas @{ ($Base + 'infrastructure/adapters/output/sftp/Recurso.java') = $adaptador })
  $r = Rescate @('-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-SinBuild')
  Igual 'sale con 0' 0 $r.Codigo
  Comprueba 'la consola dice ficheros 0' (@($r.Salida -split "`r?`n") -contains 'Plantilla incumple: capas 0 | ficheros 0 | calidad 0 | secretos 0') (Cola $r.Salida)
}

$Pruebas['m93 textos: el hallazgo de un adaptador de entrada y el de ficheros salen con el texto nuevo, tal cual y en ASCII'] = {
  $x = Escenario-M93 'm93-textos'
  $hex = @($x.H | Where-Object { $_.Cat -eq 'hexagonal' -and $_.Fichero -like '*CargaTasklet.java' })
  Igual 'un hallazgo de hexagonal en el tasklet' 1 $hex.Count
  if ($hex.Count -eq 1) {
    Igual 'su texto es el nuevo, entero' ('importa com.acme.life.infrastructure.adapters.output.file.FicheroLocalAdapter (' + $PorEntradaM93 + ')') $hex[0].Detalle
    Comprueba 'y es ASCII' ([string]$hex[0].Detalle -cmatch '^[\x20-\x7E]+$') $hex[0].Detalle
  }
  $fic = @($x.H | Where-Object { $_.Cat -eq 'ficheros' -and $_.Fichero -like '*RutaUseCase.java' })
  Igual 'un hallazgo de ficheros en el caso de uso' 1 $fic.Count
  if ($fic.Count -eq 1) {
    Igual 'su texto es el nuevo, entero' $FicherosM93 $fic[0].Detalle
    Comprueba 'y es ASCII' ([string]$fic[0].Detalle -cmatch '^[\x20-\x7E]+$') $fic[0].Detalle
  }
}

# ===== M9.4: EL YML DE config/ CUENTA, Y UN Path ES UN DATO, NO ACCESO A FICHEROS =====
# Spring Boot carga tambien classpath:/config/application*: el yml de src/main/resources/config se lee igual que el de la raiz.
# Quita el yml de la raiz de un repo de juguete y deja este texto en src/main/resources/config/application.yml, todo en un commit.
function Mueve-Yml-A-Config([string]$Raiz, [string]$Texto) {
  Remove-Item -LiteralPath (Get-Ruta $Raiz 'src/main/resources/application.yml') -Force
  Escribe $Raiz 'src/main/resources/config/application.yml' $Texto
  [void](GitEn $Raiz @('add', '--', 'src/main/resources'))
  [void](GitEn $Raiz @('commit', '-q', '-m', 'yml en config'))
}

$Pruebas['m94 config: el yml solo en src/main/resources/config con bloque sftp no da el error de configuracion sftp; sin el bloque, si'] = {
  $e = Nuevo-Escenario 'm94-yml-config'
  Mueve-Yml-A-Config $e.Repo "batch:`n  nombre: ejemplo`nsftp:`n  host: `${SFTP_HOST}`n"
  $r = Rescate @('-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-SinBuild')
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'con el bloque sftp en config/ no hay error de configuracion sftp' 0 (Hallazgos-Sftp $e.Repo $SinYmlSftp).Count
  Escribe $e.Repo 'src/main/resources/config/application.yml' "batch:`n  nombre: ejemplo`n"
  [void](Rescate @('-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-SinBuild'))
  Igual 'sin el bloque en el yml de config/, si salta (el fichero se lee)' 1 (Hallazgos-Sftp $e.Repo $SinYmlSftp).Count
}

$Pruebas['m94 config: un secreto en claro en config/application.yml da el mismo hallazgo que en la raiz, con el Rel de config/'] = {
  $e = Escenario-Con-Recursos 'm94-secreto-config' @{ 'config/application.yml' = @'
spring:
  datasource:
    username: life
    password: "acme2015"   # clave de pruebas
'@ }
  $d = Diagnostica-Secretos $e
  Igual 'sale con 0' 0 $d.R.Codigo
  Igual 'un hallazgo' 1 $d.H.Count
  Igual 'es un error' 'error' $d.H[0].Sev
  Igual 'del fichero de config/' 'src/main/resources/config/application.yml' $d.H[0].Fichero
  Igual 'en su linea' 4 $d.H[0].Linea
  Igual 'con su detalle, el de siempre' ($DetalleSecreto -f 'password') $d.H[0].Detalle
  Comprueba 'el valor no sale ni en la consola, ni en hallazgos.json, ni en el informe' (-not (Lo-Que-Sale $e.Repo $d.R.Salida).Contains('acme2015'))
}

$Pruebas['m94 sftp: una plantilla con el yml solo en config/ y con sftp se detecta como YmlSftp (la plantilla si)'] = {
  $e = Nuevo-Escenario 'm94-plantilla-config'
  Mueve-Yml-A-Config $e.Plantilla "batch:`n  carpeta: `${BATCH_CARPETA:/datos}`nsftp:`n  host: `${SFTP_HOST:}`n"
  $r = Rescate @('-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-SinBuild')
  Igual 'sale con 0' 0 $r.Codigo
  $y = Hallazgos-Sftp $e.Repo $SinYmlSftp
  Igual 'un error de configuracion sftp (el repo no lo tiene)' 1 $y.Count
  Comprueba 'dice que la plantilla si lo tiene' ($y.Count -eq 1 -and $y[0].Detalle -match '\(la plantilla si\)') (Cola $r.Salida)
}

# Repo de juguete con tres tasklets de entrada: uno que solo lleva una ruta (Path y Paths), uno que ademas importa Files y uno con el
# comodin java.nio.file.*. Diagnostico sin Maven.
function Escenario-M94([string]$Nombre) {
  $e = Nuevo-Escenario $Nombre
  $pk = $PkM93 + 'infrastructure/adapters/input/job/'
  $cab = "package com.acme.life.infrastructure.adapters.input.job;`n`n"
  Escribe $e.Repo ($pk + 'RutaTasklet.java') ($cab + "import java.nio.file.Path;`nimport java.nio.file.Paths;`n`n/** Tasklet que lleva una ruta como dato. */`npublic class RutaTasklet {`n    private Path ruta = Paths.get(`"x`");`n}`n")
  Escribe $e.Repo ($pk + 'FilesTasklet.java') ($cab + "import java.nio.file.Files;`nimport java.nio.file.Path;`nimport java.nio.file.Paths;`n`n/** Tasklet que abre un fichero. */`npublic class FilesTasklet {`n    private Path ruta = Paths.get(`"x`");`n    private Files abre;`n}`n")
  Escribe $e.Repo ($pk + 'ComodinTasklet.java') ($cab + "import java.nio.file.*;`n`n/** Tasklet con el comodin. */`npublic class ComodinTasklet {`n    private Path ruta;`n}`n")
  [void](GitEn $e.Repo @('add', '--', 'src/main/java'))
  [void](GitEn $e.Repo @('commit', '-q', '-m', 'm94'))
  $r = Rescate @('-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-SinBuild')
  return [pscustomobject]@{ E = $e; R = $r; H = @(Hallazgos $e.Repo) }
}

$Pruebas['m94 ficheros: importar solo Path y Paths no es acceso a ficheros; con Files si, y lista Files; el resto de java.nio.file sigue marcado'] = {
  $x = Escenario-M94 'm94-path'
  Igual 'sale con 0' 0 $x.R.Codigo
  $f = @($x.H | Where-Object { $_.Cat -eq 'ficheros' })
  Igual 'el tasklet que solo importa Path y Paths no tiene hallazgo de ficheros' 0 @($f | Where-Object { $_.Fichero -like '*RutaTasklet.java' }).Count
  $con = @($f | Where-Object { $_.Fichero -like '*FilesTasklet.java' })
  Igual 'el que importa tambien Files, si' 1 $con.Count
  if ($con.Count -eq 1) { Comprueba 'y lista solo Files' ($con[0].Detalle -match '^acceso directo a ficheros locales \(java\.nio\.file\.Files\): ') $con[0].Detalle }
  $com = @($f | Where-Object { $_.Fichero -like '*ComodinTasklet.java' })
  Igual 'el del comodin java.nio.file.* sigue marcado' 1 $com.Count
  if ($com.Count -eq 1) { Comprueba 'y lista el comodin' ($com[0].Detalle -match '^acceso directo a ficheros locales \(java\.nio\.file\.\*\): ') $com[0].Detalle }
  # FicheroImport se sigue cambiando desde la config: con Path en la lista, el tasklet de la ruta vuelve a salir
  Pon-Config $x.E @{ FicheroImport = '^java\.nio\.file\.Paths?$' }
  [void](Rescate @('-Repo', $x.E.Repo, '-Plantilla', $x.E.Plantilla, '-SinBuild'))
  $otra = @(Hallazgos $x.E.Repo | Where-Object { $_.Cat -eq 'ficheros' -and $_.Fichero -like '*RutaTasklet.java' })
  Igual 'con FicheroImport de la config que marca Path y Paths, el tasklet de la ruta sale' 1 $otra.Count
}

$Pruebas['m94 textos: el hallazgo de ficheros sale con el texto nuevo, entero y en ASCII'] = {
  $x = Escenario-M94 'm94-textos'
  $fic = @($x.H | Where-Object { $_.Cat -eq 'ficheros' -and $_.Fichero -like '*FilesTasklet.java' })
  Igual 'un hallazgo de ficheros en el tasklet con Files' 1 $fic.Count
  if ($fic.Count -eq 1) {
    Igual 'su texto es el nuevo, entero' $FicherosM93 $fic[0].Detalle
    Comprueba 'y es ASCII' ([string]$fic[0].Detalle -cmatch '^[\x20-\x7E]+$') $fic[0].Detalle
    Comprueba 'dice que pasar un Path como dato si vale' ([string]$fic[0].Detalle).EndsWith('(pasar un Path como dato si vale)') $fic[0].Detalle
  }
}

# ===== M9.5: LA PLANTILLA DICE COMO SE ESCRIBE EL BLOQUE SFTP =====
# La plantilla del equipo lleva el sftp anidado bajo el prefijo de su batch y con valores ${env.x} (salen del configmap). El hallazgo manda
# copiar ese bloque: su ruta, sus claves y el yml donde esta; nunca un valor. Nombres inventados.
$YmlPlantillaM95 = @'
plantillabatch:
  sftp:
    enabled: ${env.x}
    domain: host-que-no-sale
    user: ${env.valor-que-no-sale}
    password: ${env.x}
    port: ${env.x}
    allow-unknown-keys: ${env.x}
    input-path: ${env.x}
    archive-path: ${env.x}
    quarantine-path: ${env.x}
  input-directory: ${env.x:}
'@

$Pruebas['m95 sftp: con el bloque en config/ de la plantilla, el hallazgo manda copiarlo (prefijo, claves en orden, su yml, la plantilla si) y ningun valor sale'] = {
  $e = Nuevo-Escenario 'm95-bloque'
  Mueve-Yml-A-Config $e.Plantilla $YmlPlantillaM95
  $r = Rescate @('-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-SinBuild')
  Igual 'sale con 0' 0 $r.Codigo
  $y = Hallazgos-Sftp $e.Repo $SinYmlSftp
  Igual 'un error de configuracion sftp' 1 $y.Count
  $d = ''
  if ($y.Count -eq 1) { $d = [string]$y[0].Detalle }
  Comprueba 'lleva el bloque con el prefijo de la plantilla' ($d.Contains("copia el bloque 'plantillabatch.sftp' de la PLANTILLA")) $d
  Comprueba 'y el yml de la plantilla donde esta' ($d.Contains('(src/main/resources/config/application.yml)')) $d
  Comprueba 'las 9 claves, en orden' ($d.Contains('con sus claves (enabled, domain, user, password, port, allow-unknown-keys, input-path, archive-path, quarantine-path), bajo')) $d
  Comprueba 'sin la clave que cuelga del prefijo y no del sftp' (-not $d.Contains('input-directory')) $d
  Comprueba 'y acaba con (la plantilla si)' ($d.EndsWith('ningun valor real (la plantilla si)')) $d
  Igual 'el texto entero' "application.yml no tiene configuracion sftp: copia el bloque 'plantillabatch.sftp' de la PLANTILLA (src/main/resources/config/application.yml) con sus claves (enabled, domain, user, password, port, allow-unknown-keys, input-path, archive-path, quarantine-path), bajo el prefijo propio de este batch, con valores `${...} como los suyos (salen del configmap); ningun valor real (la plantilla si)" $d
  Comprueba 'y es ASCII' ($d -cmatch '^[\x20-\x7e]+$') $d
  $todo = Lo-Que-Sale $e.Repo $r.Salida
  Comprueba 'el valor ${env.valor-que-no-sale} no sale en ninguna salida' (-not $todo.Contains('valor-que-no-sale')) (Cola $r.Salida)
  Comprueba 'el literal host-que-no-sale no sale en ninguna salida' (-not $todo.Contains('host-que-no-sale')) (Cola $r.Salida)
}

$Pruebas['m95 sftp: el bloque se lee por indentacion: padres, hijos directos sin repetir ni nietos ni comentarios, el primero que haya, y ningun valor'] = {
  $e = Nuevo-Escenario 'm95-indentacion'
  Mueve-Yml-A-Config $e.Plantilla @'
app:
  batch:
    # sftp:
    nombre: ejemplo
    sftp:

      host: ${env.a}
      # port: comentado
      port: ${env.b}
      opciones:
        nodo: valor-literal-que-no-sale
      host: ${env.c}
      user: ${env.valor-que-no-sale}
    otro: 1
sftp:
  falso: ${env.z}
'@
  $r = Rescate @('-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-SinBuild')
  Igual 'sale con 0' 0 $r.Codigo
  $y = Hallazgos-Sftp $e.Repo $SinYmlSftp
  Igual 'un error de configuracion sftp' 1 $y.Count
  $d = ''
  if ($y.Count -eq 1) { $d = [string]$y[0].Detalle }
  Comprueba 'la ruta sube por los dos padres' ($d.Contains("copia el bloque 'app.batch.sftp' de la PLANTILLA")) $d
  Comprueba 'claves: host, port, opciones y user, una vez cada una, sin el nieto ni el comentario ni lo que viene despues' ($d.Contains('con sus claves (host, port, opciones, user), bajo')) $d
  Comprueba 'no usa el sftp: de la raiz que viene despues' (-not $d.Contains('falso')) $d
  $todo = Lo-Que-Sale $e.Repo $r.Salida
  Comprueba 'ningun valor sale en ninguna salida' (-not ($todo.Contains('valor-que-no-sale') -or $todo.Contains('${env.c}'))) (Cola $r.Salida)
}

$Pruebas['m95 sftp: sin un bloque sftp en un yml de la plantilla el texto es el generico, entero y en ASCII, y sin (la plantilla si)'] = {
  # la plantilla no tiene sftp
  $e = Escenario-Referencia-Sin-Sftp 'm95-generico'
  $r = Rescate @('-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-SinBuild')
  Igual 'sale con 0' 0 $r.Codigo
  $y = Hallazgos-Sftp $e.Repo $SinYmlSftp
  Igual 'un error de configuracion sftp' 1 $y.Count
  if ($y.Count -eq 1) {
    Igual 'su texto es el generico, entero' $TextoSinBloqueM95 $y[0].Detalle
    Comprueba 'y es ASCII' ([string]$y[0].Detalle -cmatch '^[\x20-\x7e]+$') $y[0].Detalle
  }
  # la plantilla lo tiene solo en un .properties: no hay bloque yml que copiar
  $p = Nuevo-Escenario 'm95-properties'
  Remove-Item -LiteralPath (Get-Ruta $p.Plantilla 'src/main/resources/application.yml') -Force
  Escribe $p.Plantilla 'src/main/resources/application.properties' "sftp.host=`${SFTP_HOST}`n"
  [void](GitEn $p.Plantilla @('add', '--', 'src/main/resources'))
  [void](GitEn $p.Plantilla @('commit', '-q', '-m', 'sftp en properties'))
  $r2 = Rescate @('-Repo', $p.Repo, '-Plantilla', $p.Plantilla, '-SinBuild')
  Igual 'con el sftp de la plantilla en un .properties, sale con 0' 0 $r2.Codigo
  $y2 = Hallazgos-Sftp $p.Repo $SinYmlSftp
  Igual 'un error de configuracion sftp' 1 $y2.Count
  if ($y2.Count -eq 1) { Igual 'y su texto es el generico' $TextoSinBloqueM95 $y2[0].Detalle }
}

# El bloque sftp acaba al volver a la indentacion de sftp: o a una menor: un bloque hermano cuyos hijos tienen la misma indentacion que los de
# sftp no aporta claves.
$Pruebas['m95 sftp: un bloque hermano de sftp con hijos a la misma indentacion no aporta claves'] = {
  $e = Nuevo-Escenario 'm95-hermano'
  Mueve-Yml-A-Config $e.Plantilla @'
plantillabatch:
  sftp:
    domain: ${env.x}
    user: ${env.x}
  otro:
    url: ${env.y}
    timeout: ${env.z}
'@
  $r = Rescate @('-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-SinBuild')
  Igual 'sale con 0' 0 $r.Codigo
  $y = Hallazgos-Sftp $e.Repo $SinYmlSftp
  Igual 'un error de configuracion sftp' 1 $y.Count
  $d = ''
  if ($y.Count -eq 1) { $d = [string]$y[0].Detalle }
  Comprueba 'las claves son solo las de sftp' ($d.Contains("copia el bloque 'plantillabatch.sftp' de la PLANTILLA") -and $d.Contains('con sus claves (domain, user), bajo')) $d
  Comprueba 'sin url ni timeout, que son del bloque otro' (-not ($d.Contains('url') -or $d.Contains('timeout'))) $d
}

# El motivo es el del primer metodo que falla: al llegar al siguiente metodo (otra linea <<< FAILURE!) o a otra linea 'Tests run:' se para.
$Pruebas['m95 motivo: con dos metodos que fallan, el motivo lleva solo la linea del primero, sin la del segundo ni Tests run'] = {
  $e = Escenario-Test-Roto 'm95-dos-fallos'
  $resumen = "Tests run: 2, Failures: 2, Errors: 0, Skipped: 0, Time elapsed: 0.8 s <<< FAILURE! - in $ClaseM92"
  $metodos = @('primeroFalla  Time elapsed: 0.4 s  <<< FAILURE!', 'java.lang.AssertionError: motivo-del-primero') +
    (Pila-M92 @('com.acme.life.ArquitecturaTest.primeroFalla(ArquitecturaTest.java:20)')) +
    @('segundoFalla  Time elapsed: 0.1 s  <<< FAILURE!', 'java.lang.AssertionError: motivo-del-segundo') +
    (Pila-M92 @('com.acme.life.ArquitecturaTest.segundoFalla(ArquitecturaTest.java:30)')) +
    @('Tests run: 2, Failures: 2, Errors: 0, Skipped: 0')
  $d = Diagnostica-Con-Informe $e (Informe-M92 $resumen $metodos)
  Igual 'sale con 0' 0 $d.R.Codigo
  Igual 'un hallazgo de tests por cada fallo' 2 $d.H.Count
  if ($d.H.Count -ne 2) { return }
  Igual 'el primero cuenta el 1 de 2' "test 1 de 2 que fallan en $ClaseM92" $d.H[0].Detalle
  Igual 'el segundo, el 2 de 2' "test 2 de 2 que fallan en $ClaseM92" $d.H[1].Detalle
  Igual 'el motivo es la linea del primero' 'java.lang.AssertionError: motivo-del-primero' $d.H[0].Motivo
  Comprueba 'y no lleva la del segundo' (-not ([string]$d.H[0].Motivo).Contains('motivo-del-segundo')) $d.H[0].Motivo
  Comprueba 'ni una linea Tests run' (-not ([string]$d.H[0].Motivo).Contains('Tests run')) $d.H[0].Motivo
  Comprueba 'el segundo no lleva motivo (no se repite el del primero)' ($null -eq $d.H[1].PSObject.Properties['Motivo']) ($d.H[1] | ConvertTo-Json -Compress)
}

# ============================ M10: PASO SONAR ============================
# El informe de Sonar (.xlsx) se FABRICA aqui con System.IO.Compression: nunca hay un binario en el repo. Paquetes y mensajes inventados.
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Xml-Esc([string]$T) { return [System.Security.SecurityElement]::Escape($T) }
function Letra-Col([int]$I) { return [string][char](65 + $I) }

# Escribe un .xlsx. $Hojas: lista de @{ Nombre; Filas }. Una fila es una lista de valores (columnas A, B, C...; $null = sin celda; un entero es un
# numero; @{ Partes = ... } es un texto enriquecido con varios <r><t>) o @{ Celdas = @(@('I', valor), @('A', valor)) }: columnas explicitas y en ese
# orden. Las cadenas van en sharedStrings. El fichero de cada hoja se numera al reves de su posicion, para que quien lea por posicion falle.
# $Nota entra en otro miembro del zip: cambia el hash del fichero sin tocar las hojas.
function Nuevo-Xlsx([string]$Ruta, $Hojas, [string]$Nota = '') {
  $comp = New-Object System.Collections.Generic.List[string]
  $indice = @{}
  $comparte = {
    param([string]$Interior)
    if (-not $indice.ContainsKey($Interior)) { $indice[$Interior] = $comp.Count; $comp.Add($Interior) }
    return $indice[$Interior]
  }
  $ns = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'
  $rel = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
  $cab = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
  $miembros = [ordered]@{}
  $hojasXml = ''
  $relsXml = ''
  $n = @($Hojas).Count
  $i = 0
  foreach ($h in $Hojas) {
    $i++
    $k = $n - $i + 1
    $filasXml = ''
    $num = 0
    foreach ($f in $h.Filas) {
      $num++
      $pares = @()
      if ($f -is [hashtable]) { $pares = @($f.Celdas) }
      else { for ($c = 0; $c -lt $f.Count; $c++) { $pares += , @((Letra-Col $c), $f[$c]) } }
      $celdas = ''
      foreach ($p in $pares) {
        $v = $p[1]
        $ref = $p[0] + $num
        if ($null -eq $v) { continue }
        if ($v -is [int]) { $celdas += '<c r="' + $ref + '"><v>' + $v + '</v></c>'; continue }
        if ($v -is [hashtable]) { $interior = (@($v.Partes | ForEach-Object { '<r><rPr><b/></rPr><t xml:space="preserve">' + (Xml-Esc $_) + '</t></r>' }) -join '') }
        else { $interior = '<t xml:space="preserve">' + (Xml-Esc "$v") + '</t>' }
        $celdas += '<c r="' + $ref + '" t="s"><v>' + (& $comparte $interior) + '</v></c>'
      }
      $filasXml += '<row r="' + $num + '">' + $celdas + '</row>'
    }
    $miembros["xl/worksheets/sheet$k.xml"] = $cab + '<worksheet xmlns="' + $ns + '"><sheetData>' + $filasXml + '</sheetData></worksheet>'
    $hojasXml += '<sheet name="' + (Xml-Esc $h.Nombre) + '" sheetId="' + $i + '" r:id="rId' + $i + '"/>'
    $relsXml += '<Relationship Id="rId' + $i + '" Type="' + $rel + '/worksheet" Target="worksheets/sheet' + $k + '.xml"/>'
  }
  $relsXml += '<Relationship Id="rId' + ($n + 1) + '" Type="' + $rel + '/sharedStrings" Target="sharedStrings.xml"/>'
  $miembros['xl/workbook.xml'] = $cab + '<workbook xmlns="' + $ns + '" xmlns:r="' + $rel + '"><sheets>' + $hojasXml + '</sheets></workbook>'
  $miembros['xl/_rels/workbook.xml.rels'] = $cab + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' + $relsXml + '</Relationships>'
  $miembros['xl/sharedStrings.xml'] = $cab + '<sst xmlns="' + $ns + '" count="' + $comp.Count + '" uniqueCount="' + $comp.Count + '">' + ((@($comp | ForEach-Object { '<si>' + $_ + '</si>' })) -join '') + '</sst>'
  $miembros['[Content_Types].xml'] = $cab + '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="xml" ContentType="application/xml"/></Types>'
  if ($Nota) { $miembros['docProps/nota.txt'] = $Nota }
  $fs = [System.IO.File]::Create($Ruta)
  $zip = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
  foreach ($nombre in $miembros.Keys) {
    $e = $zip.CreateEntry($nombre)
    $sw = New-Object System.IO.StreamWriter($e.Open(), (New-Object System.Text.UTF8Encoding($false)))
    $sw.Write([string]$miembros[$nombre])
    $sw.Dispose()
  }
  $zip.Dispose()
  $fs.Dispose()
}

$CabSonar = @('Severity', 'Message', 'Language', 'Issue Type', 'Resource', 'Path', 'Line Number', 'Tags')

# Una incidencia (una fila de Issues Breakdown).
function Inc([string]$Sev, [string]$Msg, [string]$Tipo, [string]$Rec, [string]$Ruta, [string]$Linea = '', [string]$Lang = 'Java') {
  return , @($Sev, $Msg, $Lang, $Tipo, $Rec, $Ruta, $Linea, 'cwe, owasp')
}

# Un informe como el de Sonar: Summary, Issues Breakdown y Hotspots. $Incs: lista de Inc.
function Informe-Sonar([string]$Ruta, $Incs, [string]$Nota = '') {
  $lista = @($Incs)
  if ($lista.Count -gt 0 -and $lista[0] -is [string]) { $lista = @(, $lista) }
  $filas = New-Object System.Collections.ArrayList
  [void]$filas.Add($CabSonar)
  foreach ($x in $lista) { [void]$filas.Add($x) }
  Nuevo-Xlsx $Ruta @(
    @{ Nombre = 'Summary'; Filas = @(, @('Project', 'batch')) },
    @{ Nombre = 'Issues Breakdown'; Filas = $filas.ToArray() },
    @{ Nombre = 'Hotspots'; Filas = @(, @('Rule', 'Count')) }) $Nota
}

function Linea-De([string]$Texto, [string]$Frag) {
  $l = @($Texto -split "`r?`n")
  for ($i = 0; $i -lt $l.Count; $i++) { if ($l[$i].Contains($Frag)) { return ($i + 1) } }
  return 0
}

$RutaSv = 'src/main/java/com/acme/plantillabatch/'
$AppSonar = @'
package com.acme.plantillabatch;

import org.springframework.boot.autoconfigure.SpringBootApplication;

/** Arranque del batch de prueba. */
@SpringBootApplication
public class PlantillaBatchApplication {

    /**
     * Arranca el batch.
     *
     * @param args argumentos
     */
    public static void main(String[] args) {
    }
}
'@
$TestSonar = @'
package com.acme.plantillabatch.service;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

class TotalServiceTest {

    @Test
    void suma() {
        assertEquals(2, 1 + 1);
    }
}
'@

# Una clase de servicio con su linea marcada ('int resultado = a + b;'). Con $SinDoc sale sin Javadoc (dos errores de calidad).
function Servicio-Java([string]$Clase, [string]$Sub, [bool]$SinDoc = $false) {
  if ($SinDoc) {
    return @"
package com.acme.plantillabatch.$Sub;

public class $Clase {
    public int suma(int a, int b) {
        int resultado = a + b;
        return resultado;
    }
}
"@
  }
  return @"
package com.acme.plantillabatch.$Sub;

/** Calcula totales en $Clase. */
public class $Clase {

    /**
     * Suma dos numeros.
     *
     * @param a primero
     * @param b segundo
     * @return la suma
     */
    public int suma(int a, int b) {
        int resultado = a + b;
        return resultado;
    }
}
"@
}

# Ajustes de un repo de Sonar: Maven y Copilot de mentira, mas lo de $Mas (con profundidad para listas de tablas). Cada test carga sus recetas,
# exclusiones y prohibiciones: por defecto las tres listas van vacias, para que el contenido por defecto del script no cambie ningun test.
function Config-Sonar($E, [hashtable]$Mas) {
  $cfg = [ordered]@{ CopilotExe = (Join-Path $falsos 'copilot.ps1'); MvnExe = (Join-Path $falsos 'm20a-mvn.ps1'); Reflexionar = $false; SonarRecetas = @(); SonarNoAutomatizar = @(); SonarProhibido = @() }
  foreach ($k in $Mas.Keys) { $cfg[$k] = $Mas[$k] }
  Escribe $E.Repo '.rescate/config.json' (ConvertTo-Json -InputObject $cfg -Depth 6)
}

# Un repo Java con Maven que no es una migracion (sin plantilla): una clase por cada 'subpaquete/Clase' de $Clases, las de $SinDoc sin Javadoc y los ficheros de $Extra (ruta bajo el paquete sin .java -> texto; o una ruta del repo que empieza por /).
function Escenario-Sonar([string]$Nombre, [string[]]$Clases = @('service/TotalService', 'service/ReciboService'), [hashtable]$Mas = @{}, [string[]]$SinDoc = @(), [hashtable]$Extra = @{}) {
  $raiz = Join-Path $Dir $Nombre
  if (Test-Path -LiteralPath $raiz) { Remove-Item -LiteralPath $raiz -Recurse -Force }
  $repo = Join-Path $raiz 'batch'
  Escribe $repo 'pom.xml' $Pom
  Escribe $repo ($RutaSv + 'PlantillaBatchApplication.java') $AppSonar
  Escribe $repo 'src/test/java/com/acme/plantillabatch/service/TotalServiceTest.java' $TestSonar
  foreach ($c in $Clases) { $p = $c -split '/'; Escribe $repo ($RutaSv + $p[0] + '/' + $p[1] + '.java') (Servicio-Java $p[1] $p[0]) }
  foreach ($c in $SinDoc) { $p = $c -split '/'; Escribe $repo ($RutaSv + $p[0] + '/' + $p[1] + '.java') (Servicio-Java $p[1] $p[0] $true) }
  foreach ($k in $Extra.Keys) {
    if ($k.StartsWith('/')) { Escribe $repo $k.TrimStart('/') $Extra[$k] }   # una ruta del repo tal cual (por ejemplo un yml de resources)
    else { Escribe $repo ($RutaSv + $k + '.java') $Extra[$k] }
  }
  Inicia-Repo $repo
  $e = [pscustomobject]@{ Raiz = $raiz; Repo = $repo; Wt = ($repo + '-rescate'); Plantilla = ''; Xlsx = (Join-Path $raiz 'informe.xlsx') }
  Config-Sonar $e $Mas
  return $e
}

# Lanza rescate.ps1 sobre el repo del escenario, sin plantilla.
function Sonar-Lanza($E, [string[]]$A, [string]$Guion = '', [string[]]$Entrada = @('')) { return (Lanzar $Script (@('-Repo', $E.Repo) + $A) $Guion $Entrada) }

function Hallazgos-Sonar([string]$Raiz, [string]$Sev = '') {
  return @(Hallazgos $Raiz | Where-Object { $_.Cat -eq 'sonar' -and ((-not $Sev) -or $_.Sev -eq $Sev) })
}

# Las funciones del lector y del filtro, para probarlas sin lanzar el script entero.
$FnLectorSonar = @('Get-SonarPlegado', 'Get-SonarTextoRico', 'Read-SonarXml', 'Get-SonarCeldasHoja', 'Get-SonarCabecera', 'Get-SonarNumeroLinea', 'Read-SonarXlsx', 'Get-SonarFiltradas',
  'Get-Limpio', 'Get-SonarNormal', 'Get-SonarUnidad', 'Test-SonarSigueAhi', 'Get-SonarProhibidas')

# El texto para cargar esas funciones sin lanzar el script: antes, el regex de comentarios y cadenas del que cuelgan (una variable de script).
function Texto-Sonar {
  $ast = [System.Management.Automation.Language.Parser]::ParseFile($Script, [ref]$null, [ref]$null)
  $v = @($ast.FindAll({ param($x) $x -is [System.Management.Automation.Language.AssignmentStatementAst] -and $x.Left.Extent.Text -eq '$RxLexico' }, $true))[0]
  return ('$script:RxLexico = ' + $v.Right.Extent.Text + "`n" + (Texto-De-Funciones $FnLectorSonar))
}
$ColumnasSonar = @{
  'Severity' = @('Severity'); 'Message' = @('Message'); 'Issue Type' = @('Issue Type'); 'Path' = @('Path')
  'Line Number' = @('Line Number'); 'Resource' = @('Resource'); 'Tags' = @('Tags'); 'Language' = @('Language')
}

$Pruebas['m10 sonar: lector - cadenas compartidas con texto enriquecido, celdas en orden raro y una columna vacia'] = {
  . ([scriptblock]::Create((Texto-Sonar)))
  $x = Join-Path $Dir 'm10-lector.xlsx'
  $r = 'src/main/java/com/acme/plantillabatch/service/'
  $filas = New-Object System.Collections.ArrayList
  [void]$filas.Add(@('Informe de Sonar de prueba'))
  [void]$filas.Add(@('Severity', 'Message', $null, 'Language', 'Issue Type', 'Resource', 'Path', 'Line Number', 'Tags'))
  [void]$filas.Add(@{ Celdas = @(
        @('I', 'cwe, security,owasp-a1'), @('A', 'CRITICAL'), @('H', 'L32'), @('G', ($r + 'TotalService.java')), @('E', 'BUG'),
        @('F', 'TotalService.java'), @('D', 'Java'), @('B', @{ Partes = @('Refactor this ', 'method ', "it's too complex & long.") })) })
  [void]$filas.Add(@('MAJOR', 'Remove this unused import.', $null, 'Java', 'CODE_SMELL', 'A.java', ($r + 'A.java'), '-', ''))
  [void]$filas.Add(@('MINOR', 'Rename this field.', $null, 'Java', 'CODE_SMELL', 'B.java', ($r + 'B.java'), '40L', 'convention'))
  [void]$filas.Add(@('INFO', 'Todo comment.', $null, 'Java', 'CODE_SMELL', 'C.java', ($r + 'C.java'), 7, 'a,b'))
  Nuevo-Xlsx $x @(
    @{ Nombre = 'Resumen'; Filas = @(, @('Proyecto', 'batch')) },
    @{ Nombre = 'Issues Breakdown'; Filas = $filas.ToArray() })
  $f = @(Read-SonarXlsx $x $ColumnasSonar)
  Igual 'salen cuatro incidencias' 4 $f.Count
  if ($f.Count -ne 4) { return }
  Igual 'la primera incidencia esta en la fila 3 de la hoja (cabecera en la 2)' 3 $f[0].Fila
  Igual 'el mensaje de varias partes sale entero y exacto' "Refactor this method it's too complex & long." $f[0].Mensaje
  Igual 'la severidad' 'CRITICAL' $f[0].Severidad
  Igual 'el tipo' 'BUG' $f[0].Tipo
  Igual 'el lenguaje' 'Java' $f[0].Lenguaje
  Igual 'el recurso' 'TotalService.java' $f[0].Recurso
  Igual 'la ruta exacta' ($r + 'TotalService.java') $f[0].Ruta
  Igual 'L32 da 32' 32 $f[0].Linea
  Igual 'los tags quedan separados' 'cwe|security|owasp-a1' (@($f[0].Etiquetas) -join '|')
  Igual 'el guion da linea 0' 0 $f[1].Linea
  Igual 'sin tags no hay ninguno' 0 @($f[1].Etiquetas).Count
  Igual '40L da 40' 40 $f[2].Linea
  Igual 'una celda numerica da su numero' 7 $f[3].Linea
  Igual 'la columna vacia no desplaza las demas' 'Rename this field.' $f[2].Mensaje
}

$Pruebas['m10 sonar: sin la hoja o sin una columna obligatoria, el error dice cual falta'] = {
  $e = Escenario-Sonar 'm10-errores'
  $d = @('-Modo', 'diagnostico', '-SinBuild', '-Sonar')
  # ninguna hoja sirve
  $sin = Join-Path $e.Raiz 'sin-hoja.xlsx'
  Nuevo-Xlsx $sin @(@{ Nombre = 'Otra'; Filas = @(, @('Algo', 'Distinto')) })
  $r1 = Sonar-Lanza $e ($d + $sin)
  Igual 'sin la hoja sale con 1' 1 $r1.Codigo
  Comprueba 'el error nombra la hoja que buscaba' ($r1.Salida -match "Issues Breakdown") (Cola $r1.Salida)
  Comprueba 'y las columnas obligatorias' ($r1.Salida -match 'Severity' -and $r1.Salida -match 'Message' -and $r1.Salida -match 'Issue Type' -and $r1.Salida -match 'Path') (Cola $r1.Salida)
  # la hoja esta pero falta Path
  $sinp = Join-Path $e.Raiz 'sin-path.xlsx'
  Nuevo-Xlsx $sinp @(@{ Nombre = 'Issues Breakdown'; Filas = @(@('Severity', 'Message', 'Issue Type', 'Line Number'), @('CRITICAL', 'Fix this.', 'BUG', '3L')) })
  $r2 = Sonar-Lanza $e ($d + $sinp)
  Igual 'sin Path sale con 1' 1 $r2.Codigo
  Comprueba "el error dice que falta la columna 'Path'" ($r2.Salida -match "falta la columna obligatoria 'Path'") (Cola $r2.Salida)
  Comprueba 'y no inventa otra' ($r2.Salida -notmatch "falta la columna obligatoria 'Severity'" -and $r2.Salida -notmatch "falta la columna obligatoria 'Message'") (Cola $r2.Salida)
  # no es un xlsx y no existe
  $txt = Join-Path $e.Raiz 'texto.xlsx'
  [System.IO.File]::WriteAllText($txt, 'esto no es un zip')
  $r3 = Sonar-Lanza $e ($d + $txt)
  Igual 'un fichero que no es un xlsx sale con 1' 1 $r3.Codigo
  Comprueba 'y lo dice' ($r3.Salida -match 'no es un \.xlsx') (Cola $r3.Salida)
  $r4 = Sonar-Lanza $e ($d + (Join-Path $e.Raiz 'no-existe.xlsx'))
  Igual 'un informe que no existe sale con 1' 1 $r4.Codigo
  Comprueba 'y lo dice' ($r4.Salida -match 'No existe el informe de Sonar') (Cola $r4.Salida)
  Comprueba 'con -Paso sonar y sin -Sonar tambien hay un error claro' ((Sonar-Lanza $e @('-Modo', 'diagnostico', '-SinBuild', '-Paso', 'sonar')).Salida -match "necesita -Sonar") 'sin -Sonar'
}

$Pruebas['m10 sonar: filtro - BUG, VULNERABILITY, BLOCKER, CRITICAL y MAJOR; MINOR e INFO nunca; solo Java'] = {
  . ([scriptblock]::Create((Texto-Sonar)))
  $Cfg = @{ SonarTipos = @('BUG', 'VULNERABILITY'); SonarSeveridades = @('BLOCKER', 'CRITICAL', 'MAJOR') }
  function F([int]$N, [string]$Tipo, [string]$Sev, [string]$Lang = 'Java', [string]$Ruta = 'src/main/java/A.java') {
    return [pscustomobject]@{ Fila = $N; Severidad = $Sev; Mensaje = 'm'; Lenguaje = $Lang; Tipo = $Tipo; Recurso = 'A.java'; Ruta = $Ruta; Linea = 1; Etiquetas = @() }
  }
  $filas = @(
    (F 1 'BUG' 'MAJOR'), (F 2 'VULNERABILITY' 'CRITICAL'), (F 3 'CODE_SMELL' 'CRITICAL'), (F 4 'CODE_SMELL' 'BLOCKER'),
    (F 5 'CODE_SMELL' 'MAJOR'), (F 6 'CODE_SMELL' 'MINOR'), (F 7 'CODE_SMELL' 'INFO'), (F 8 'BUG' 'MINOR'),
    (F 9 'BUG' 'CRITICAL' 'JavaScript' 'src/main/webapp/a.js'), (F 10 'BUG' 'CRITICAL' '' 'src/main/resources/a.xml'), (F 11 'BUG' 'CRITICAL' '' 'src/main/java/B.java'))
  $filtra = { (@(Get-SonarFiltradas $filas | ForEach-Object { $_.Fila }) -join ' ') }
  Igual 'por defecto: BUG, VULNERABILITY, BLOCKER, CRITICAL y MAJOR (y Java por la ruta si no hay lenguaje)' '1 2 3 4 5 11' (& $filtra)
  $Cfg.SonarSeveridades = @('BLOCKER', 'CRITICAL', 'MAJOR', 'MINOR')
  Igual 'MINOR solo entra si esta en la lista de severidades (INFO sigue fuera)' '1 2 3 4 5 6 8 11' (& $filtra)
  $Cfg = @{ SonarTipos = @('VULNERABILITY'); SonarSeveridades = @('BLOCKER') }
  Igual 'con otras listas entra lo de esas listas' '2 4' (& $filtra)
}

$Pruebas['m10 sonar: la tabla del diagnostico no cambia sin -Sonar y con -Sonar lleva la fila sonar con sus errores'] = {
  $e = Escenario-Sonar 'm10-tabla'
  $total = $RutaSv + 'service/TotalService.java'
  $recibo = $RutaSv + 'service/ReciboService.java'
  $ln = Linea-De (Lee $e.Repo $total) 'int resultado'
  Informe-Sonar $e.Xlsx @(
    (Inc 'CRITICAL' 'Fix this null dereference.' 'BUG' 'TotalService.java' $total "${ln}L"),
    (Inc 'MAJOR' 'Reduce this method.' 'CODE_SMELL' 'ReciboService.java' $recibo "${ln}L"),
    (Inc 'MINOR' 'Rename this field.' 'CODE_SMELL' 'ReciboService.java' $recibo "${ln}L"),
    (Inc 'INFO' 'Todo comment.' 'CODE_SMELL' 'ReciboService.java' $recibo "${ln}L"),
    (Inc 'CRITICAL' 'Script issue.' 'BUG' 'app.js' 'src/main/webapp/app.js' '3L' 'JavaScript'))
  $r0 = Sonar-Lanza $e @('-Modo', 'diagnostico', '-SinBuild')
  Igual 'sin -Sonar sale con 0' 0 $r0.Codigo
  Igual 'la tabla tiene sus nueve pasos de siempre' 9 ([regex]::Matches($r0.Salida, '(?m)^(build|estructura|hexagonal|ficheros|config|paridad|e2e|tests|calidad)\s+\d+\s+\d+\s*$')).Count
  Comprueba 'sin fila sonar en la consola' ($r0.Salida -notmatch '(?m)^sonar\s') (Cola $r0.Salida)
  Comprueba 'ni en diagnostico.md' ((Lee $e.Repo '.rescate/diagnostico.md') -notmatch '\| sonar \|')
  Igual 'ni hallazgos sonar' 0 (Hallazgos-Sonar $e.Repo).Count
  Comprueba 'ni la frase de Sonar en el resumen' ($r0.Salida -notmatch 'Sonar: ')

  $r1 = Sonar-Lanza $e @('-Modo', 'diagnostico', '-SinBuild', '-Sonar', $e.Xlsx)
  Igual 'con -Sonar sale con 0' 0 $r1.Codigo
  Comprueba 'la consola lleva la fila sonar con 2 errores' ($r1.Salida -match '(?m)^sonar\s+2\s+0\s*$') (Cola $r1.Salida)
  Comprueba 'y diagnostico.md tambien' ((Lee $e.Repo '.rescate/diagnostico.md') -match '\| sonar \| 2 \| 0 \|')
  $hs = @(Hallazgos-Sonar $e.Repo)
  Igual 'dos hallazgos sonar (BUG CRITICAL y CODE_SMELL MAJOR; MINOR, INFO y JavaScript fuera)' 2 $hs.Count
  $h1 = @($hs | Where-Object { $_.Fichero -eq $total })
  if ($h1.Count -eq 1) {
    Igual 'su linea' $ln $h1[0].Linea
    Igual 'su detalle, con tipo y severidad' 'Fix this null dereference. [BUG CRITICAL]' $h1[0].Detalle
    Igual 'es un error' 'error' $h1[0].Sev
  }
  else { Comprueba 'el de TotalService esta' $false '' }
  Igual 'el MAJOR entra sin ninguna opcion' 'Reduce this method. [CODE_SMELL MAJOR]' (@($hs | Where-Object { $_.Fichero -eq $recibo })[0]).Detalle
  Comprueba 'el resumen dice cuantas lleva resueltas y que la prueba es volver a pasar Sonar' ($r1.Salida -match 'Sonar: 0 resueltas aqui\. La prueba de verdad es volver a pasar Sonar y relanzar con el xlsx nuevo\.') (Cola $r1.Salida)
}

$Pruebas['m10 sonar: -Paso sonar con el Copilot falso que cambia la linea marcada hace el lote y un commit'] = {
  $e = Escenario-Sonar 'm10-fix' @('service/TotalService')
  $total = $RutaSv + 'service/TotalService.java'
  $ln = Linea-De (Lee $e.Repo $total) 'int resultado'
  Informe-Sonar $e.Xlsx @(, (Inc 'CRITICAL' 'Fix this null dereference.' 'BUG' 'TotalService.java' $total "${ln}L"))
  $r = Sonar-Lanza $e @('-Modo', 'fix', '-Paso', 'sonar', '-Sonar', $e.Xlsx, '-Auto', '-Si', '-MaxIntentos', '1')
  Igual 'sale con 0' 0 $r.Codigo
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  Comprueba "Lote 1 OK: 'sonar' 1 -> 0" ($r.Salida -match "Lote 1 OK: 'sonar' 1 -> 0") (Cola $r.Salida)
  Comprueba 'hay un commit del lote' ((GitEn $e.Wt @('log', '--format=%s')) -match 'rescate\(sonar\): lote 1, hallazgos 1 a 0') (GitEn $e.Wt @('log', '--format=%s'))
  Comprueba 'la linea marcada ha cambiado' ((Lee $e.Wt $total) -match 'int resultado = a \+ b \+ 0;')
  Igual 'sonar queda a 0 en el worktree' 0 (Hallazgos-Sonar $e.Wt 'error').Count
  Comprueba 'el resumen cuenta 1 resuelta' ($r.Salida -match 'Sonar: 1 resueltas aqui\.') (Cola $r.Salida)
  Comprueba 'no falta ninguna de las listadas' ($r.Salida -match 'Sonar: no falta ninguna de las listadas; la prueba de verdad es volver a pasar Sonar') (Cola $r.Salida)
  Comprueba 'y no hay lista de faltan' ($r.Salida -notmatch 'Faltan \d+ de Sonar' -and (Lee $e.Wt '.rescate/sonar-faltan.md') -notmatch 'Faltan \d+ de Sonar')
  $prompt = Lee $e.Wt '.rescate/prompt.md'
  Comprueba 'el prompt nombra el fichero donde el modelo deja las que no corrige' ($prompt.Contains('.rescate/sonar-sin-arreglar.txt')) $prompt
  Comprueba 'y la incidencia con su fichero y su linea' ($prompt.Contains("- ${total}:${ln} - Fix this null dereference. [BUG CRITICAL]")) $prompt
  Igual 'el worktree queda limpio' '' (GitEn $e.Wt @('status', '--porcelain'))
}

$Pruebas['m10 sonar: un Copilot falso que no toca la linea marcada deja el lote sin bajar y el fichero atascado'] = {
  $e = Escenario-Sonar 'm10-sin-tocar' @('service/TotalService')
  $total = $RutaSv + 'service/TotalService.java'
  $ln = Linea-De (Lee $e.Repo $total) 'int resultado'
  Informe-Sonar $e.Xlsx @(, (Inc 'CRITICAL' 'Fix this null dereference.' 'BUG' 'TotalService.java' $total "${ln}L"))
  $r = Sonar-Lanza $e @('-Modo', 'fix', '-Paso', 'sonar', '-Sonar', $e.Xlsx, '-Auto', '-Si', '-MaxIntentos', '1') 'sonar-sin-tocar'
  Igual 'sale con 2' 2 $r.Codigo
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  Comprueba 'el intento dice que los hallazgos no han bajado' ($r.Salida -match "Los hallazgos de 'sonar' no han bajado \(1 -> 1\)") (Cola $r.Salida)
  Comprueba 'el lote se deshace' ($r.Salida -match 'Lote 1 DESHECHO') (Cola $r.Salida)
  Comprueba 'el fichero queda atascado' ($r.Salida -match "ATASCADO en 'sonar'") (Cola $r.Salida)
  Comprueba 'y apuntado' (Test-Path -LiteralPath (Get-Ruta $e.Wt '.rescate/atascados.md'))
  Comprueba 'al final faltan 1 de Sonar, atascada tras los intentos' ($r.Salida -match 'Faltan 1 de Sonar' -and $r.Salida -match 'atascada tras los intentos') (Cola $r.Salida)
  Igual 'no hay commits nuevos' 'inicial' (GitEn $e.Wt @('log', '--format=%s'))
  Igual 'el worktree queda limpio' '' (GitEn $e.Wt @('status', '--porcelain'))
}

$Pruebas['m10 sonar: un fichero movido se encuentra por su nombre; con el nombre repetido o sin fichero sale el aviso y no entra en lotes'] = {
  $e = Escenario-Sonar 'm10-movido' @('service/Mover', 'a/Repetida', 'b/Repetida')
  $real = $RutaSv + 'service/Mover.java'
  $ln = Linea-De (Lee $e.Repo $real) 'int resultado'
  Informe-Sonar $e.Xlsx @(
    (Inc 'CRITICAL' 'Moved bug.' 'BUG' 'Mover.java' ($RutaSv + 'vieja/Mover.java') "${ln}L"),
    (Inc 'CRITICAL' 'Ambiguous bug.' 'BUG' 'Repetida.java' ($RutaSv + 'c/Repetida.java') "${ln}L"),
    (Inc 'CRITICAL' 'Missing bug.' 'BUG' 'Nada.java' ($RutaSv + 'c/Nada.java') "${ln}L"))
  $r = Sonar-Lanza $e @('-Modo', 'diagnostico', '-SinBuild', '-Sonar', $e.Xlsx)
  Igual 'sale con 0' 0 $r.Codigo
  $err = @(Hallazgos-Sonar $e.Repo 'error')
  $av = @(Hallazgos-Sonar $e.Repo 'aviso')
  Igual 'solo el movido es un error' 1 $err.Count
  if ($err.Count -eq 1) { Igual 'y apunta al fichero de verdad' $real $err[0].Fichero }
  Igual 'los otros dos son avisos' 2 $av.Count
  Comprueba 'que dicen que no encuentran el fichero' (@($av | Where-Object { $_.Detalle -like 'no encuentro el fichero*' }).Count -eq 2) (($av | ForEach-Object { $_.Detalle }) -join ' / ')
  Comprueba 'la tabla cuenta 1 error y 2 avisos' ($r.Salida -match '(?m)^sonar\s+1\s+2\s*$') (Cola $r.Salida)
  Comprueba 'el resumen no da por resueltas las que no encuentra' ($r.Salida -match 'Sonar: 0 resueltas aqui\.') (Cola $r.Salida)
}

$Pruebas['m10 sonar: la base guarda la unidad marcada y el hash; sin cambios la incidencia se da por resuelta y un xlsx nuevo rehace la base'] = {
  $e = Escenario-Sonar 'm10-base' @('service/TotalService')
  $total = $RutaSv + 'service/TotalService.java'
  $ln = Linea-De (Lee $e.Repo $total) 'int resultado'
  $incs = @(, (Inc 'CRITICAL' 'Fix this null dereference.' 'BUG' 'TotalService.java' $total "${ln}L"))
  Informe-Sonar $e.Xlsx $incs
  $d = @('-Modo', 'diagnostico', '-SinBuild', '-Sonar', $e.Xlsx)
  $r1 = Sonar-Lanza $e $d
  $b1 = (Lee $e.Repo '.rescate/sonar-base.json') | ConvertFrom-Json
  Igual 'la base lleva el hash del xlsx' (Get-FileHash -LiteralPath $e.Xlsx -Algorithm SHA256).Hash "$($b1.hash)"
  $i1 = @($b1.incidencias | Where-Object { $_.fichero -eq $total })
  Igual 'la base lleva la incidencia' 1 $i1.Count
  if ($i1.Count -eq 1) {
    Igual 'su unidad normalizada: la linea marcada sin espacios' 'intresultado=a+b;' "$($i1[0].unidad)"
    Igual 'su linea' $ln "$($i1[0].linea)"
  }
  Igual 'al principio hay un error' 1 (Hallazgos-Sonar $e.Repo 'error').Count
  # cambia la linea marcada (sin commit): la incidencia ya no esta, y el mismo xlsx no rehace la base
  Escribe $e.Repo $total ((Lee $e.Repo $total).Replace('int resultado = a + b;', 'int resultado = b + a;'))
  $r2 = Sonar-Lanza $e $d
  Igual 'sin la linea marcada no hay error' 0 (Hallazgos-Sonar $e.Repo 'error').Count
  Comprueba 'y el resumen cuenta 1 resuelta' ($r2.Salida -match 'Sonar: 1 resueltas aqui\.') (Cola $r2.Salida)
  $b2 = (Lee $e.Repo '.rescate/sonar-base.json') | ConvertFrom-Json
  Igual 'el mismo xlsx conserva la base (la unidad de antes)' 'intresultado=a+b;' "$(@($b2.incidencias)[0].unidad)"
  # otro xlsx (otro hash, mismas filas): la base se rehace con lo que hay ahora en el fichero
  Informe-Sonar $e.Xlsx $incs 'otra pasada de Sonar'
  $h2 = (Get-FileHash -LiteralPath $e.Xlsx -Algorithm SHA256).Hash
  Comprueba 'el xlsx nuevo tiene otro hash' ($h2 -ne $b1.hash)
  $r3 = Sonar-Lanza $e $d
  $b3 = (Lee $e.Repo '.rescate/sonar-base.json') | ConvertFrom-Json
  Igual 'la base lleva el hash nuevo' $h2 "$($b3.hash)"
  Igual 'y la unidad de ahora' 'intresultado=b+a;' "$(@($b3.incidencias)[0].unidad)"
  Igual 'la incidencia vuelve a contar como pendiente' 1 (Hallazgos-Sonar $e.Repo 'error').Count
}

$Pruebas['m10 sonar: un xlsx con otro hash guarda la base anterior en sonar-base-anterior.json, con las resueltas, su regla y el commit del lote'] = {
  $rec = @(, @{ Rx = 'null dereference'; Texto = 'RECETA-PRUEBA-H2: nada raro.' })
  $e = Escenario-Sonar 'm10-base-anterior' @('service/TotalService', 'service/ReciboService') @{ SonarRecetas = $rec }
  $total = $RutaSv + 'service/TotalService.java'
  $recibo = $RutaSv + 'service/ReciboService.java'
  $incs = @(
    (Inc 'CRITICAL' 'Fix this null dereference.' 'BUG' 'TotalService.java' $total ((Linea-De (Lee $e.Repo $total) 'int resultado').ToString() + 'L')),
    (Inc 'CRITICAL' 'Mensaje-sin-receta-h2.' 'BUG' 'ReciboService.java' $recibo ((Linea-De (Lee $e.Repo $recibo) 'int resultado').ToString() + 'L')))
  Informe-Sonar $e.Xlsx $incs
  $a = @('-Modo', 'fix', '-Paso', 'sonar', '-Auto', '-Si', '-MaxIntentos', '1', '-Sonar', $e.Xlsx)
  $r1 = Sonar-Lanza $e $a
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r1.Salida); return }
  $hash1 = (Get-FileHash -LiteralPath $e.Xlsx -Algorithm SHA256).Hash
  Comprueba 'la primera pasada resuelve las dos' ($r1.Salida -match 'Sonar: 2 resueltas aqui\.') (Cola $r1.Salida)
  $dir = Join-Path $e.Wt '.rescate'
  Comprueba 'con el primer xlsx no hay base anterior' (-not (Test-Path -LiteralPath (Join-Path $dir 'sonar-base-anterior.json')))
  $b1 = (Lee $e.Wt '.rescate/sonar-base.json') | ConvertFrom-Json
  Igual 'la base de la primera pasada lleva su hash' $hash1 "$($b1.hash)"
  $x1 = @($b1.incidencias | Where-Object { $_.fichero -eq $total })
  $x2 = @($b1.incidencias | Where-Object { $_.fichero -eq $recibo })
  Igual 'la base lleva las dos incidencias' 2 (@($b1.incidencias).Count)
  if ($x1.Count -eq 1 -and $x2.Count -eq 1) {
    Igual 'la primera consta como resuelta en esta pasada' 'True' "$($x1[0].resuelta)"
    Igual 'por la regla de la receta que le toco' 'null dereference' "$($x1[0].regla)"
    Igual 'la segunda, sin receta, con la regla vacia' '' "$($x2[0].regla)"
    $commit = "$($x1[0].commit)"
    Comprueba 'lleva el commit del lote, que existe en el repo' ($commit -and ((GitEn $e.Wt @('cat-file', '-t', $commit)) -eq 'commit')) $commit
    Comprueba 'y es el commit de un lote de sonar' ((GitEn $e.Wt @('log', '-1', '--format=%s', $commit)) -match '^rescate\(sonar\): lote ') (GitEn $e.Wt @('log', '--format=%h %s'))
  }
  else { Comprueba 'estan las dos incidencias en la base' $false (($b1.incidencias | ForEach-Object { $_.fichero }) -join ' ') }
  # el xlsx nuevo (otro hash): la base de antes se guarda y la nueva se hace de cero
  Informe-Sonar $e.Xlsx $incs 'otra pasada de Sonar'
  $hash2 = (Get-FileHash -LiteralPath $e.Xlsx -Algorithm SHA256).Hash
  Comprueba 'el xlsx nuevo tiene otro hash' ($hash2 -ne $hash1)
  $r2 = Sonar-Lanza $e $a
  Comprueba 'la segunda pasada sale bien' ($r2.Codigo -eq 0) (Cola $r2.Salida)
  Comprueba 'estan los dos ficheros' ((Test-Path -LiteralPath (Join-Path $dir 'sonar-base.json')) -and (Test-Path -LiteralPath (Join-Path $dir 'sonar-base-anterior.json'))) (Cola $r2.Salida)
  if (Test-Path -LiteralPath (Join-Path $dir 'sonar-base-anterior.json')) {
    $ant = (Lee $e.Wt '.rescate/sonar-base-anterior.json') | ConvertFrom-Json
    $nueva = (Lee $e.Wt '.rescate/sonar-base.json') | ConvertFrom-Json
    Igual 'la anterior es la de la primera pasada (su hash)' $hash1 "$($ant.hash)"
    Igual 'la nueva lleva el hash nuevo' $hash2 "$($nueva.hash)"
    $a1 = @($ant.incidencias | Where-Object { $_.fichero -eq $total })
    Comprueba 'la anterior conserva la resuelta con su regla y su commit' ($a1.Count -eq 1 -and "$($a1[0].resuelta)" -eq 'True' -and "$($a1[0].regla)" -eq 'null dereference' -and "$($a1[0].commit)" -eq $commit) (($ant.incidencias | ConvertTo-Json -Compress))
  }
  # una tercera con otro hash vuelve a machacar la anterior: queda la de la segunda pasada
  Informe-Sonar $e.Xlsx $incs 'y otra mas'
  $hash3 = (Get-FileHash -LiteralPath $e.Xlsx -Algorithm SHA256).Hash
  $r3 = Sonar-Lanza $e $a
  if (Test-Path -LiteralPath (Join-Path $dir 'sonar-base-anterior.json')) {
    $ant3 = (Lee $e.Wt '.rescate/sonar-base-anterior.json') | ConvertFrom-Json
    Igual 'la tercera machaca la anterior con la de la segunda pasada' $hash2 "$($ant3.hash)"
  }
  # el mismo xlsx otra vez no rehace nada ni guarda otra anterior
  $r4 = Sonar-Lanza $e $a
  $ant4 = (Lee $e.Wt '.rescate/sonar-base-anterior.json') | ConvertFrom-Json
  Igual 'con el mismo xlsx la anterior no cambia' $hash2 "$($ant4.hash)"
}

$Pruebas['m10 sonar: el texto de calidad sobre inyeccion pide un unico constructor, campos final y sin estado mutable'] = {
  $e = Escenario-Sonar 'm10-calidad' @('service/TotalService') @{} @('service/SinDoc1', 'service/SinDoc2')
  $r = Sonar-Lanza $e @('-Modo', 'fix', '-Paso', 'calidad', '-Auto', '-Si', '-MaxIntentos', '1', '-MaxLotes', '1') 'nada'
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  $prompt = Lee $e.Wt '.rescate/prompt.md'
  Comprueba 'el prompt de calidad lleva la frase nueva' ($prompt.Contains('inyeccion por un unico constructor, campos final, sin estado mutable en el componente')) $prompt
  Comprueba 'y sigue pidiendo inyeccion por constructor' ($prompt.Contains('@Autowired en un campo: pasa a inyeccion por constructor con campos private final'))
  Comprueba 'sin -Sonar y sin plantilla el aviso de siempre sigue' ($r.Salida -match 'Sin -Plantilla el arreglo va a ciegas') (Cola $r.Salida)
}

$Pruebas['m10 sonar: solo -Repo y -Sonar hace el paso sonar entero, sin parar a preguntar y sin tocar calidad'] = {
  $cl = @('service/TotalService', 'service/ReciboService', 'service/PagoService', 'service/CobroService', 'service/AjusteService', 'service/CierreService')
  $e = Escenario-Sonar 'm10-corto' $cl @{} @('service/SinDoc1')
  $incs = @()
  foreach ($c in $cl) {
    $nombre = ($c -split '/')[1]
    $ruta = $RutaSv + $c + '.java'
    $incs += , (Inc 'CRITICAL' "Fix this bug in $nombre." 'BUG' ($nombre + '.java') $ruta ((Linea-De (Lee $e.Repo $ruta) 'int resultado').ToString() + 'L'))
  }
  Informe-Sonar $e.Xlsx $incs
  $r0 = Sonar-Lanza $e @('-Modo', 'diagnostico', '-SinBuild')
  $calidad0 = (Hallazgos $e.Repo | Where-Object { $_.Cat -eq 'calidad' -and $_.Sev -eq 'error' }).Count
  Comprueba 'el repo tiene errores de calidad' ($calidad0 -ge 2) "$calidad0"
  # la unica respuesta es 's' al 'Seguir?' de crear el worktree; despues no debe preguntar nada
  $r = Lanzar $Script @('-Repo', $e.Repo, '-Sonar', $e.Xlsx) '' @('s')
  Igual 'sale con 0' 0 $r.Codigo
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  Comprueba 'va directo al paso sonar aunque calidad tenga errores' ($r.Salida -match "=== Paso 'sonar' en lotes de 5 ===") (Cola $r.Salida)
  Comprueba "primer lote: 'sonar' 6 -> 1" ($r.Salida -match "Lote 1 OK: 'sonar' 6 -> 1") (Cola $r.Salida)
  Comprueba "segundo lote: 'sonar' 1 -> 0, sin que nadie diga que siga" ($r.Salida -match "Lote 2 OK: 'sonar' 1 -> 0") (Cola $r.Salida)
  Comprueba 'no pregunta entre lotes' ($r.Salida -notmatch 'siguiente lote') (Cola $r.Salida)
  $log = GitEn $e.Wt @('log', '--format=%s')
  Comprueba 'hay dos commits de sonar' ($log -match 'rescate\(sonar\): lote 1' -and $log -match 'rescate\(sonar\): lote 2') $log
  Comprueba 'y ninguno de calidad' ($log -notmatch 'rescate\(calidad\)') $log
  Igual 'los errores de calidad siguen como estaban' $calidad0 (@(Hallazgos $e.Wt | Where-Object { $_.Cat -eq 'calidad' -and $_.Sev -eq 'error' })).Count
  Comprueba 'sin plantilla no hay aviso de que el arreglo va a ciegas' ($r.Salida -notmatch 'a ciegas') (Cola $r.Salida)
  Comprueba 'no falta ninguna de las listadas' ($r.Salida -match 'Sonar: no falta ninguna de las listadas') (Cola $r.Salida)
  $prompt = Lee $e.Wt '.rescate/prompt.md'
  Comprueba 'ni lleva hallazgos de calidad' ($prompt -notmatch 'javadoc-') $prompt
}

$Pruebas['m10 sonar: con -Todo se encadenan los pasos y sonar va el ultimo'] = {
  $modelo = @'
package com.acme.plantillabatch.domain;

import org.springframework.stereotype.Component;

/** Modelo de dominio de prueba. */
@Component
public class Modelo {
}
'@
  # Orden de la config reducido a hexagonal: -Sonar le anade sonar al final
  $e = Escenario-Sonar 'm10-todo' @('service/TotalService') @{ Orden = @('hexagonal') } @() @{ 'domain/Modelo' = $modelo }
  $total = $RutaSv + 'service/TotalService.java'
  $ln = Linea-De (Lee $e.Repo $total) 'int resultado'
  Informe-Sonar $e.Xlsx @(, (Inc 'CRITICAL' 'Fix this null dereference.' 'BUG' 'TotalService.java' $total "${ln}L"))
  $r = Sonar-Lanza $e @('-Modo', 'fix', '-Todo', '-Sonar', $e.Xlsx, '-Si', '-SinPlan', '-MaxIntentos', '1')
  Igual 'sale con 0' 0 $r.Codigo
  $pasos = @([regex]::Matches($r.Salida, "(?m)^=== Paso '(\w+)' en lotes") | ForEach-Object { $_.Groups[1].Value })
  Igual 'primero hexagonal y sonar el ultimo' 'hexagonal sonar' ($pasos -join ' ')
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { return }
  $log = GitEn $e.Wt @('log', '--format=%s')
  Comprueba 'hay un commit de cada paso' ($log -match 'rescate\(hexagonal\): lote 1' -and $log -match 'rescate\(sonar\): lote 1') $log
}

$Pruebas['m10 sonar: la receta de una regla sale una sola vez, con la cabecera de las incidencias a las que se aplica, y solo si casa con algun mensaje'] = {
  $rec = @(
    @{ Rx = 'cognitive complexity'; Texto = 'RECETA-PRUEBA-UNO: extrae un metodo privado.' },
    @{ Rx = 'remove this unused'; Texto = 'RECETA-PRUEBA-DOS: borra lo que sobra.' })
  $e = Escenario-Sonar 'm10-recetas' @('service/TotalService', 'service/ReciboService', 'service/PagoService') @{ SonarRecetas = $rec }
  $incs = @()
  $lns = @{}
  $msgs = @('Refactor this method to reduce its Cognitive Complexity from 25 to the 15 allowed.', 'Refactor this method to reduce its Cognitive Complexity from 18 to the 15 allowed.', 'Replace this generic exception with a more specific one.')
  $i = 0
  foreach ($n in @('TotalService', 'ReciboService', 'PagoService')) {
    $ruta = $RutaSv + 'service/' + $n + '.java'
    $lns[$n] = Linea-De (Lee $e.Repo $ruta) 'int resultado'
    $incs += , (Inc 'CRITICAL' $msgs[$i] 'BUG' ($n + '.java') $ruta ($lns[$n].ToString() + 'L'))
    $i++
  }
  Informe-Sonar $e.Xlsx $incs
  $r = Sonar-Lanza $e @('-Modo', 'fix', '-Paso', 'sonar', '-Sonar', $e.Xlsx, '-Auto', '-Si', '-MaxIntentos', '1', '-MaxLotes', '1') 'nada'
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  $prompt = Lee $e.Wt '.rescate/prompt.md'
  Igual 'la receta de complejidad sale una vez (dos mensajes de la misma regla)' 1 ([regex]::Matches($prompt, 'RECETA-PRUEBA-UNO')).Count
  Comprueba 'la otra, sin mensaje que case, no sale' ($prompt -notmatch 'RECETA-PRUEBA-DOS') $prompt
  $cab = 'RECETA para ' + $RutaSv + 'service/TotalService.java:' + $lns['TotalService'] + ', ' + $RutaSv + 'service/ReciboService.java:' + $lns['ReciboService'] + ':'
  Comprueba 'lleva la cabecera con las dos incidencias a las que se aplica (y no la tercera)' ($prompt.Contains($cab) -and -not $prompt.Contains('RECETA para ' + $RutaSv + 'service/PagoService')) $prompt
  Comprueba 'y su texto debajo de la cabecera' ($prompt.IndexOf('RECETA-PRUEBA-UNO') -gt $prompt.IndexOf($cab)) $prompt
}

$Pruebas['m10 sonar: no se vale silenciar a Sonar ni quitar tests: el intento cuenta como fallido aunque la linea haya cambiado'] = {
  $proh = @(
    @{ Rx = 'NOSONAR|@SuppressWarnings'; Modo = 'anadida'; Motivo = 'MOTIVO-PRUEBA-SILENCIO: no se silencia a Sonar, se corrige el codigo' },
    @{ Rx = '@Disabled'; Modo = 'anadida'; Motivo = 'MOTIVO-PRUEBA-DESACTIVADO: no se desactivan tests' })
  foreach ($caso in @('sonar-nosonar', 'sonar-suppress', 'sonar-disabled', 'sonar-borra-test')) {
    $e = Escenario-Sonar ('m10-trampa-' + $caso) @('service/TotalService', 'service/ReciboService') @{ SonarProhibido = $proh }
    $incs = @()
    foreach ($n in @('TotalService', 'ReciboService')) {
      $ruta = $RutaSv + 'service/' + $n + '.java'
      $incs += , (Inc 'CRITICAL' "Fix this bug in $n." 'BUG' ($n + '.java') $ruta ((Linea-De (Lee $e.Repo $ruta) 'int resultado').ToString() + 'L'))
    }
    Informe-Sonar $e.Xlsx $incs
    $r = Sonar-Lanza $e @('-Modo', 'fix', '-Paso', 'sonar', '-Sonar', $e.Xlsx, '-Auto', '-Si', '-MaxIntentos', '2', '-MaxLotes', '1') $caso
    if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba "$caso : existe el worktree" $false (Cola $r.Salida); continue }
    $motivo = 'MOTIVO-PRUEBA-SILENCIO'
    if ($caso -eq 'sonar-disabled') { $motivo = 'MOTIVO-PRUEBA-DESACTIVADO' }
    if ($caso -eq 'sonar-borra-test') { $motivo = 'borrar ni renombrar' }
    Comprueba "$caso : el intento no pasa y dice el motivo de la entrada" ($r.Salida -match ('NO PASA: .*' + $motivo)) (Cola $r.Salida)
    Comprueba "$caso : el lote se deshace" ($r.Salida -match 'Lote 1 DESHECHO') (Cola $r.Salida)
    Igual "$caso : no hay commits nuevos" 'inicial' (GitEn $e.Wt @('log', '--format=%s'))
    if ($caso -eq 'sonar-nosonar') {
      Comprueba 'con solo un NOSONAR los hallazgos si habian bajado (el codigo ha cambiado) y aun asi no pasa' ($r.Salida -notmatch "no han bajado") (Cola $r.Salida)
      $prompt = Lee $e.Wt '.rescate/prompt.md'
      Comprueba 'el motivo va al siguiente intento' ($prompt -match '## CORRECCION' -and $prompt.Contains('MOTIVO-PRUEBA-SILENCIO')) $prompt
      Comprueba 'con el fichero que lo silencia' ($prompt -match 'TotalService\.java') $prompt
    }
  }
}

$Pruebas['m10 sonar: sin plantilla ni migracion, el paso funciona en un repo Java cualquiera'] = {
  $e = Escenario-Sonar 'm10-general' @('service/TotalService')
  $total = $RutaSv + 'service/TotalService.java'
  $ln = Linea-De (Lee $e.Repo $total) 'int resultado'
  Informe-Sonar $e.Xlsx @(, (Inc 'BLOCKER' 'Fix this blocker.' 'CODE_SMELL' 'TotalService.java' $total "${ln}L"))
  $r = Lanzar $Script @('-Repo', $e.Repo, '-Sonar', $e.Xlsx) '' @('s')
  Igual 'sale con 0' 0 $r.Codigo
  Comprueba "Lote 1 OK: 'sonar' 1 -> 0" ($r.Salida -match "Lote 1 OK: 'sonar' 1 -> 0") (Cola $r.Salida)
  Comprueba 'sin plantilla no avisa de que va a ciegas' ($r.Salida -notmatch 'a ciegas') (Cola $r.Salida)
  Comprueba 'ni pide plantilla ni original' ($r.Salida -notmatch 'Plantilla incumple') (Cola $r.Salida)
}

$Pruebas['m10 sonar: columnas por alias en espanol y la primera hoja con las columnas cuando no hay Issues Breakdown'] = {
  $e = Escenario-Sonar 'm10-alias' @('service/TotalService')
  $total = $RutaSv + 'service/TotalService.java'
  $ln = Linea-De (Lee $e.Repo $total) 'int resultado'
  $lin = 'L' + [char]0x00ED + 'nea'
  $sev = 'Severidad'
  # otra hoja primero, sin Issues Breakdown, cabeceras en espanol (con tilde, mayusculas y espacios), sin columna de lenguaje
  $x1 = Join-Path $e.Raiz 'alias.xlsx'
  Nuevo-Xlsx $x1 @(
    @{ Nombre = 'Portada'; Filas = @(, @('Informe', 'batch')) },
    @{ Nombre = 'Hallazgos'; Filas = @(
        @(" $sev ", 'MENSAJE', 'Tipo', ' ruta', $lin, ' RECURSO ', 'Etiquetas'),
        @('CRITICAL', 'Corrige este fallo.', 'BUG', $total, $ln, 'TotalService.java', 'cwe'),
        @('MINOR', 'Un menor.', 'CODE_SMELL', $total, $ln, 'TotalService.java', 'x')) })
  $d = @('-Modo', 'diagnostico', '-SinBuild', '-Sonar')
  $r1 = Sonar-Lanza $e ($d + $x1)
  Igual 'con otra hoja y cabeceras en espanol sale con 0' 0 $r1.Codigo
  $h1 = @(Hallazgos-Sonar $e.Repo 'error')
  Igual 'entra la incidencia (Java por el .java de la ruta)' 1 $h1.Count
  if ($h1.Count -eq 1) {
    Igual 'su mensaje' 'Corrige este fallo. [BUG CRITICAL]' $h1[0].Detalle
    Igual 'su linea (una celda numerica)' $ln $h1[0].Linea
  }
  # si Issues Breakdown esta, manda aunque haya otra hoja anterior con las columnas
  $x2 = Join-Path $e.Raiz 'primero.xlsx'
  Nuevo-Xlsx $x2 @(
    @{ Nombre = 'Datos'; Filas = @(@('Severity', 'Message', 'Issue Type', 'Path', 'Line Number'), @('CRITICAL', 'De la otra hoja.', 'BUG', $total, "${ln}L")) },
    @{ Nombre = 'Issues Breakdown'; Filas = @(@('Severity', 'Message', 'Issue Type', 'Path', 'Line Number'), @('BLOCKER', 'De Issues Breakdown.', 'CODE_SMELL', $total, "${ln}L")) })
  $r2 = Sonar-Lanza $e ($d + $x2)
  $h2 = @(Hallazgos-Sonar $e.Repo 'error')
  Igual 'con Issues Breakdown entra una sola incidencia' 1 $h2.Count
  if ($h2.Count -eq 1) { Igual 'y es la de Issues Breakdown' 'De Issues Breakdown. [CODE_SMELL BLOCKER]' $h2[0].Detalle }
  # sin Issues Breakdown ni hoja con las columnas, el error dice cuales buscaba
  $x3 = Join-Path $e.Raiz 'nada.xlsx'
  Nuevo-Xlsx $x3 @(@{ Nombre = 'Datos'; Filas = @(, @('Severidad', 'Mensaje')) })
  $r3 = Sonar-Lanza $e ($d + $x3)
  Igual 'sin ninguna hoja valida sale con 1' 1 $r3.Codigo
  Comprueba 'y dice que columnas buscaba' ($r3.Salida -match 'Severity' -and $r3.Salida -match 'Issue Type' -and $r3.Salida -match 'Path') (Cola $r3.Salida)
}

$Pruebas['m10 sonar: el filtro sale de SonarTipos y SonarSeveridades de .rescate/config.json'] = {
  $e = Escenario-Sonar 'm10-filtro-config' @('service/TotalService') @{ SonarTipos = @('VULNERABILITY'); SonarSeveridades = @('BLOCKER') }
  $total = $RutaSv + 'service/TotalService.java'
  $ln = Linea-De (Lee $e.Repo $total) 'int resultado'
  Informe-Sonar $e.Xlsx @(
    (Inc 'CRITICAL' 'Bug critico.' 'BUG' 'TotalService.java' $total "${ln}L"),
    (Inc 'MAJOR' 'Vulnerabilidad mayor.' 'VULNERABILITY' 'TotalService.java' $total "${ln}L"),
    (Inc 'BLOCKER' 'Olor bloqueante.' 'CODE_SMELL' 'TotalService.java' $total "${ln}L"),
    (Inc 'MAJOR' 'Olor mayor.' 'CODE_SMELL' 'TotalService.java' $total "${ln}L"))
  $r1 = Sonar-Lanza $e @('-Modo', 'diagnostico', '-SinBuild', '-Sonar', $e.Xlsx)
  Igual 'con la config entran la vulnerabilidad y el bloqueante' 'Olor bloqueante. [CODE_SMELL BLOCKER]|Vulnerabilidad mayor. [VULNERABILITY MAJOR]' ((@(Hallazgos-Sonar $e.Repo 'error' | ForEach-Object { $_.Detalle }) | Sort-Object) -join '|')
}

$Pruebas['m10 sonar: el modelo deja una incidencia con motivo: el lote vale sin reintento y la dejada sale en Faltan con su motivo'] = {
  $e = Escenario-Sonar 'm10-deja' @('service/TotalService', 'service/ReciboService')
  $total = $RutaSv + 'service/TotalService.java'
  $recibo = $RutaSv + 'service/ReciboService.java'
  $lnT = Linea-De (Lee $e.Repo $total) 'int resultado'
  $lnR = Linea-De (Lee $e.Repo $recibo) 'int resultado'
  Informe-Sonar $e.Xlsx @(
    (Inc 'CRITICAL' 'Fix this bug in TotalService.' 'BUG' 'TotalService.java' $total "${lnT}L"),
    (Inc 'CRITICAL' 'DEJAME: change the public API of ReciboService.' 'BUG' 'ReciboService.java' $recibo "${lnR}L"))
  $r = Sonar-Lanza $e @('-Modo', 'fix', '-Paso', 'sonar', '-Sonar', $e.Xlsx, '-Auto', '-Si', '-MaxIntentos', '3') 'sonar-deja'
  Igual 'sale con 0: lo dejado no es un atasco' 0 $r.Codigo
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  Comprueba "Lote 1 OK: 'sonar' 2 -> 0 (la dejada no cuenta para bajar)" ($r.Salida -match "Lote 1 OK: 'sonar' 2 -> 0") (Cola $r.Salida)
  Comprueba 'sin segundo intento ni segundo lote' ($r.Salida -notmatch 'intento 2 de' -and $r.Salida -notmatch 'Lote 2') (Cola $r.Salida)
  Comprueba 'hay un commit de lo arreglado' ((GitEn $e.Wt @('log', '--format=%s')) -match 'rescate\(sonar\): lote 1, hallazgos 2 a 0') (GitEn $e.Wt @('log', '--format=%s'))
  Comprueba 'la linea arreglada ha cambiado' ((Lee $e.Wt $total) -match 'int resultado = a \+ b \+ 0;')
  Comprueba 'la dejada se queda como estaba' ((Lee $e.Wt $recibo) -match 'int resultado = a \+ b;')
  Comprueba 'el script ha leido y borrado sonar-sin-arreglar.txt' (-not (Test-Path -LiteralPath (Get-Ruta $e.Wt '.rescate/sonar-sin-arreglar.txt')))
  Comprueba 'el prompt le dice al modelo donde dejar las que no corrige' ((Lee $e.Wt '.rescate/prompt.md').Contains('.rescate/sonar-sin-arreglar.txt'))
  Comprueba 'faltan 1 de Sonar' ($r.Salida -match 'Faltan 1 de Sonar') (Cola $r.Salida)
  Comprueba 'agrupada por motivo' ($r.Salida -match 'dejada por el modelo: cambiaria la API publica') (Cola $r.Salida)
  Comprueba 'con ruta:linea, mensaje y tipo/severidad' ($r.Salida.Contains("${recibo}:${lnR} - DEJAME: change the public API of ReciboService. [BUG CRITICAL]")) (Cola $r.Salida)
  Comprueba 'la linea que no casa con ninguna incidencia se ignora' ($r.Salida -notmatch 'NoExiste')
  $md = ''
  if (Test-Path -LiteralPath (Get-Ruta $e.Wt '.rescate/sonar-faltan.md')) { $md = Lee $e.Wt '.rescate/sonar-faltan.md' }
  Comprueba 'la lista tambien esta en .rescate/sonar-faltan.md' ($md -match 'dejada por el modelo: cambiaria la API publica' -and $md.Contains("${recibo}:${lnR}")) $md
  Comprueba 'y su ruta va en el resumen final' ($r.Salida -match 'sonar-faltan\.md') (Cola $r.Salida)
  Comprueba 'la dejada es un aviso en la tabla: sonar 0 errores y 1 aviso' ($r.Salida -match '(?m)^sonar\s+0\s+1\s*$') (Cola $r.Salida)
  Comprueba 'el resumen cuenta 1 resuelta (la dejada no)' ($r.Salida -match 'Sonar: 1 resueltas aqui\.') (Cola $r.Salida)
}

# Una clase con dos lineas distintas que se pueden marcar en un mismo fichero.
$DosLineas = @'
package com.acme.plantillabatch.service;

/** Dos calculos en una clase. */
public class DosLineasService {

    /**
     * Primer calculo.
     *
     * @param a primero
     * @param b segundo
     * @return la suma
     */
    public int primero(int a, int b) {
        int primero = a + b;
        return primero;
    }

    /**
     * Segundo calculo.
     *
     * @param a primero
     * @param b segundo
     * @return la resta
     */
    public int segundo(int a, int b) {
        int segundo = a - b;
        return segundo;
    }
}
'@

$Pruebas['m10 sonar: dos incidencias de un mismo fichero, el modelo deja una con motivo y no toca la otra: solo la apuntada es dejada, la otra sigue pendiente y se atasca'] = {
  $e = Escenario-Sonar 'm10-deja-linea' @('service/TotalService') @{ CopilotExe = (Join-Path $falsos 'sonar-copilot.ps1') } @() @{ 'service/DosLineasService' = $DosLineas }
  $total = $RutaSv + 'service/TotalService.java'
  $f = $RutaSv + 'service/DosLineasService.java'
  $lnT = Linea-De (Lee $e.Repo $total) 'int resultado'
  $l1 = Linea-De (Lee $e.Repo $f) 'int primero = a + b;'
  $l2 = Linea-De (Lee $e.Repo $f) 'int segundo = a - b;'
  Informe-Sonar $e.Xlsx @(
    (Inc 'CRITICAL' 'Fix this bug in TotalService.' 'BUG' 'TotalService.java' $total "${lnT}L"),
    (Inc 'CRITICAL' 'DEJAME: change the public API of primero.' 'BUG' 'DosLineasService.java' $f "${l1}L"),
    (Inc 'CRITICAL' 'ATASCA: this one cannot be fixed.' 'BUG' 'DosLineasService.java' $f "${l2}L"))
  $r = Sonar-Lanza $e @('-Modo', 'fix', '-Paso', 'sonar', '-Sonar', $e.Xlsx, '-Auto', '-Si', '-MaxIntentos', '1') 'sonar-deja-y-atasca'
  Igual 'sale con 2: la otra incidencia del fichero se atasca' 2 $r.Codigo
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  Comprueba "Lote 1 OK: 'sonar' 3 -> 1 (solo la linea apuntada es dejada, la otra sigue pendiente)" ($r.Salida -match "Lote 1 OK: 'sonar' 3 -> 1") (Cola $r.Salida)
  Comprueba 'la otra se intenta en un lote 2 de 1 hallazgo y se deshace' ($r.Salida -match 'Lote 2 : 1 hallazgo\(s\) en 1 fichero\(s\)' -and $r.Salida -match 'Lote 2 DESHECHO') (Cola $r.Salida)
  Comprueba 'faltan 2 de Sonar: la dejada y la atascada' ($r.Salida -match 'Faltan 2 de Sonar') (Cola $r.Salida)
  Comprueba 'la apuntada sale dejada por el modelo, y es la unica de ese grupo' ($r.Salida -match "dejada por el modelo: cambiaria la API publica \(1\):\s*\n\s*- $([regex]::Escape($f)):${l1} - DEJAME") (Cola $r.Salida)
  Comprueba 'la otra sale atascada tras los intentos, no dejada' ($r.Salida -match "atascada tras los intentos \(1\):\s*\n\s*- $([regex]::Escape($f)):${l2} - ATASCA") (Cola $r.Salida)
}

# Una clase con la misma linea de codigo dos veces ('return null;').
$DosNulos = @'
package com.acme.plantillabatch.service;

/** Dos salidas nulas. */
public class NuloService {

    /**
     * Busca uno.
     *
     * @param a clave
     * @return nada
     */
    public String uno(String a) {
        return null;
    }

    /**
     * Busca otro.
     *
     * @param a clave
     * @return nada
     */
    public String otro(String a) {
        return null;
    }
}
'@

$Pruebas['m10 sonar: la misma linea dos veces en el fichero: si el arreglo deja una sola, la incidencia de orden 1 se da por arreglada y la de orden 0 no'] = {
  $e = Escenario-Sonar 'm10-unidad-repetida' @('service/TotalService') @{} @() @{ 'service/NuloService' = $DosNulos }
  $f = $RutaSv + 'service/NuloService.java'
  $lineas = @((Lee $e.Repo $f) -split "`r?`n")
  $nulos = @(1..$lineas.Count | Where-Object { $lineas[$_ - 1].Trim() -eq 'return null;' })
  Igual 'el fichero tiene dos veces return null;' 2 $nulos.Count
  Informe-Sonar $e.Xlsx @(
    (Inc 'CRITICAL' 'ATASCA: return null en uno.' 'BUG' 'NuloService.java' $f "$($nulos[0])L"),
    (Inc 'CRITICAL' 'Return an empty value en otro.' 'BUG' 'NuloService.java' $f "$($nulos[1])L"))
  # el Copilot falso no toca la primera (ATASCA) y cambia la segunda: queda una sola linea 'return null;'
  $r = Sonar-Lanza $e @('-Modo', 'fix', '-Paso', 'sonar', '-Sonar', $e.Xlsx, '-Auto', '-Si', '-MaxIntentos', '1') 'sonar-atasca'
  Igual 'sale con 2: la primera sigue pendiente y se atasca' 2 $r.Codigo
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  Comprueba "Lote 1 OK: 'sonar' 2 -> 1 (la segunda cuenta como arreglada)" ($r.Salida -match "Lote 1 OK: 'sonar' 2 -> 1") (Cola $r.Salida)
  Igual 'queda una sola linea return null;' 1 @((Lee $e.Wt $f) -split "`r?`n" | Where-Object { $_.Trim() -eq 'return null;' }).Count
  $base = (Lee $e.Wt '.rescate/sonar-base.json') | ConvertFrom-Json
  $i0 = @($base.incidencias | Where-Object { $_.linea -eq $nulos[0] })[0]
  $i1 = @($base.incidencias | Where-Object { $_.linea -eq $nulos[1] })[0]
  Igual 'la primera lleva el orden 0 y sigue sin resolver' '0 False' "$($i0.indice) $($i0.resuelta)"
  Igual 'la segunda lleva el orden 1 y consta como resuelta' '1 True' "$($i1.indice) $($i1.resuelta)"
  Comprueba 'el resumen cuenta 1 resuelta' ($r.Salida -match 'Sonar: 1 resueltas aqui\.') (Cola $r.Salida)
  Comprueba 'faltan 1 de Sonar: la primera, atascada' ($r.Salida -match 'Faltan 1 de Sonar' -and $r.Salida -match 'atascada tras los intentos') (Cola $r.Salida)
}

$Pruebas['m10 sonar: una incidencia que casa con SonarNoAutomatizar no llega al modelo y sale en Faltan con su motivo'] = {
  $no = @(, @{ Rx = 'enum-prueba'; Motivo = 'prueba: esta regla no se automatiza' })
  $e = Escenario-Sonar 'm10-noauto' @('service/TotalService', 'service/ReciboService') @{ SonarNoAutomatizar = $no }
  $total = $RutaSv + 'service/TotalService.java'
  $recibo = $RutaSv + 'service/ReciboService.java'
  $lnT = Linea-De (Lee $e.Repo $total) 'int resultado'
  $lnR = Linea-De (Lee $e.Repo $recibo) 'int resultado'
  Informe-Sonar $e.Xlsx @(
    (Inc 'CRITICAL' 'Fix this bug in TotalService.' 'BUG' 'TotalService.java' $total "${lnT}L"),
    (Inc 'CRITICAL' 'ENUM-PRUEBA: do not touch this in ReciboService.' 'BUG' 'ReciboService.java' $recibo "${lnR}L"))
  $r0 = Sonar-Lanza $e @('-Modo', 'diagnostico', '-SinBuild', '-Sonar', $e.Xlsx)
  Comprueba 'la tabla cuenta 1 error y 1 aviso (la no automatizable es un aviso)' ($r0.Salida -match '(?m)^sonar\s+1\s+1\s*$') (Cola $r0.Salida)
  $r = Sonar-Lanza $e @('-Modo', 'fix', '-Paso', 'sonar', '-Sonar', $e.Xlsx, '-Auto', '-Si', '-MaxIntentos', '1')
  Igual 'sale con 0' 0 $r.Codigo
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  Comprueba "Lote 1 OK: 'sonar' 1 -> 0" ($r.Salida -match "Lote 1 OK: 'sonar' 1 -> 0") (Cola $r.Salida)
  $prompt = Lee $e.Wt '.rescate/prompt.md'
  Comprueba 'la que si se automatiza va al prompt' ($prompt.Contains("${total}:${lnT} - Fix this bug in TotalService.")) $prompt
  Comprueba 'la no automatizable no llega al prompt (ni su fichero ni su mensaje)' (-not $prompt.Contains('ENUM-PRUEBA') -and -not $prompt.Contains('ReciboService.java')) $prompt
  Comprueba 'su linea queda como estaba' ((Lee $e.Wt $recibo) -match 'int resultado = a \+ b;')
  Comprueba 'faltan 1 de Sonar' ($r.Salida -match 'Faltan 1 de Sonar') (Cola $r.Salida)
  Comprueba 'con su motivo' ($r.Salida -match 'no se automatiza: prueba: esta regla no se automatiza') (Cola $r.Salida)
  Comprueba 'con ruta:linea, mensaje y tipo/severidad' ($r.Salida.Contains("${recibo}:${lnR} - ENUM-PRUEBA: do not touch this in ReciboService. [BUG CRITICAL]")) (Cola $r.Salida)
}

$Pruebas['m10 sonar: un atasco en el lote 1 no para la pasada: el lote 2 y el 3 se hacen y todo sale contado al final'] = {
  $e = Escenario-Sonar 'm10-atasco' @('service/TotalService', 'service/ReciboService', 'service/PagoService')
  $total = $RutaSv + 'service/TotalService.java'
  $incs = @(, (Inc 'CRITICAL' 'ATASCA: this one cannot be fixed.' 'BUG' 'TotalService.java' $total ((Linea-De (Lee $e.Repo $total) 'int resultado').ToString() + 'L')))
  foreach ($n in @('ReciboService', 'PagoService')) {
    $ruta = $RutaSv + 'service/' + $n + '.java'
    $incs += , (Inc 'CRITICAL' "Fix this bug in $n." 'BUG' ($n + '.java') $ruta ((Linea-De (Lee $e.Repo $ruta) 'int resultado').ToString() + 'L'))
  }
  Informe-Sonar $e.Xlsx $incs
  $r = Sonar-Lanza $e @('-Modo', 'fix', '-Paso', 'sonar', '-Sonar', $e.Xlsx, '-Auto', '-Si', '-MaxIntentos', '1', '-Lote', '1') 'sonar-atasca'
  Igual 'sale con 2 (hay un fichero atascado)' 2 $r.Codigo
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  Comprueba 'el lote 1 queda atascado' ($r.Salida -match "ATASCADO en 'sonar': $([regex]::Escape($total))") (Cola $r.Salida)
  Comprueba "el lote 2 sigue: 'sonar' 3 -> 2" ($r.Salida -match "Lote 2 OK: 'sonar' 3 -> 2") (Cola $r.Salida)
  Comprueba "y el lote 3: 'sonar' 2 -> 1" ($r.Salida -match "Lote 3 OK: 'sonar' 2 -> 1") (Cola $r.Salida)
  $log = GitEn $e.Wt @('log', '--format=%s')
  Comprueba 'hay dos commits de sonar, el 2 y el 3' ($log -match 'rescate\(sonar\): lote 2' -and $log -match 'rescate\(sonar\): lote 3' -and $log -notmatch 'lote 1') $log
  Comprueba 'faltan 1 de Sonar' ($r.Salida -match 'Faltan 1 de Sonar') (Cola $r.Salida)
  Comprueba 'atascada tras los intentos, con ruta:linea, mensaje y tipo/severidad' ($r.Salida -match 'atascada tras los intentos' -and $r.Salida -match [regex]::Escape("${total}:") -and $r.Salida.Contains('ATASCA: this one cannot be fixed. [BUG CRITICAL]')) (Cola $r.Salida)
  Comprueba 'el resumen cuenta las 2 resueltas' ($r.Salida -match 'Sonar: 2 resueltas aqui\.') (Cola $r.Salida)
  Comprueba 'y deja la lista en sonar-faltan.md' (Test-Path -LiteralPath (Get-Ruta $e.Wt '.rescate/sonar-faltan.md'))
}

$Pruebas['m10 sonar: reformatear la linea marcada (espacios, saltos, comentarios) no resuelve la incidencia; cambiar su codigo si'] = {
  $e = Escenario-Sonar 'm10-reformato' @('service/TotalService')
  $total = $RutaSv + 'service/TotalService.java'
  $ln = Linea-De (Lee $e.Repo $total) 'int resultado'
  Informe-Sonar $e.Xlsx @(, (Inc 'CRITICAL' 'Fix this null dereference.' 'BUG' 'TotalService.java' $total "${ln}L"))
  $d = @('-Modo', 'diagnostico', '-SinBuild', '-Sonar', $e.Xlsx)
  [void](Sonar-Lanza $e $d)
  Igual 'al principio hay un error' 1 (Hallazgos-Sonar $e.Repo 'error').Count
  $orig = Lee $e.Repo $total
  # solo espacios y un comentario nuevo
  Escribe $e.Repo $total ($orig.Replace('int resultado = a + b;', "int   resultado=a+b ;   // comentario nuevo`n        /* otro comentario */"))
  $r1 = Sonar-Lanza $e $d
  Igual 'con otros espacios y comentarios sigue habiendo un error' 1 (Hallazgos-Sonar $e.Repo 'error').Count
  Comprueba 'y no cuenta ninguna resuelta' ($r1.Salida -match 'Sonar: 0 resueltas aqui\.') (Cola $r1.Salida)
  # la misma linea partida en tres
  Escribe $e.Repo $total ($orig.Replace('int resultado = a + b;', "int resultado =`n            a`n            + b;"))
  [void](Sonar-Lanza $e $d)
  Igual 'partida en varias lineas sigue habiendo un error' 1 (Hallazgos-Sonar $e.Repo 'error').Count
  # cambiar el codigo si la resuelve
  Escribe $e.Repo $total ($orig.Replace('int resultado = a + b;', 'int resultado = a - b;'))
  $r3 = Sonar-Lanza $e $d
  Igual 'cambiando el codigo ya no hay error' 0 (Hallazgos-Sonar $e.Repo 'error').Count
  Comprueba 'y cuenta 1 resuelta' ($r3.Salida -match 'Sonar: 1 resueltas aqui\.') (Cola $r3.Salida)
}

$Pruebas['m10 sonar: un metodo marcado en su declaracion se resuelve si el modelo extrae parte de su cuerpo, aunque la linea marcada no cambie'] = {
  $e = Escenario-Sonar 'm10-extrae' @('service/TotalService')
  $total = $RutaSv + 'service/TotalService.java'
  $ln = Linea-De (Lee $e.Repo $total) 'public int suma('
  Informe-Sonar $e.Xlsx @(, (Inc 'CRITICAL' 'Refactor this method to reduce its complexity.' 'CODE_SMELL' 'TotalService.java' $total "${ln}L"))
  $r = Sonar-Lanza $e @('-Modo', 'fix', '-Paso', 'sonar', '-Sonar', $e.Xlsx, '-Auto', '-Si', '-MaxIntentos', '1') 'sonar-extrae'
  Igual 'sale con 0' 0 $r.Codigo
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  $nuevo = Lee $e.Wt $total
  Comprueba 'la declaracion marcada se queda igual' ($nuevo.Contains('public int suma(int a, int b) {')) $nuevo
  Comprueba 'y el cuerpo se ha extraido a un metodo privado' ($nuevo.Contains('private int sumaAuxiliar(int a, int b)')) $nuevo
  Comprueba "Lote 1 OK: 'sonar' 1 -> 0" ($r.Salida -match "Lote 1 OK: 'sonar' 1 -> 0") (Cola $r.Salida)
  Comprueba 'el resumen cuenta 1 resuelta' ($r.Salida -match 'Sonar: 1 resueltas aqui\.') (Cola $r.Salida)
}

$Pruebas['m10 sonar: anadir Javadoc encima de un metodo marcado lo resuelve; un comentario normal no'] = {
  $e = Escenario-Sonar 'm10-javadoc' @() @{} @('service/Pelado')
  $fich = $RutaSv + 'service/Pelado.java'
  $ln = Linea-De (Lee $e.Repo $fich) 'public int suma('
  Informe-Sonar $e.Xlsx @(, (Inc 'MAJOR' 'Add a Javadoc comment to this method.' 'CODE_SMELL' 'Pelado.java' $fich "${ln}L"))
  $d = @('-Modo', 'diagnostico', '-SinBuild', '-Sonar', $e.Xlsx)
  [void](Sonar-Lanza $e $d)
  Igual 'al principio hay un error' 1 (Hallazgos-Sonar $e.Repo 'error').Count
  $orig = Lee $e.Repo $fich
  $metodo = '    public int suma(int a, int b) {'
  Escribe $e.Repo $fich ($orig.Replace($metodo, "    /* una nota normal */`n" + $metodo))
  $r1 = Sonar-Lanza $e $d
  Igual 'un comentario normal encima no la resuelve' 1 (Hallazgos-Sonar $e.Repo 'error').Count
  Comprueba 'y no cuenta ninguna resuelta' ($r1.Salida -match 'Sonar: 0 resueltas aqui\.') (Cola $r1.Salida)
  Escribe $e.Repo $fich ($orig.Replace($metodo, "    /**`n     * Suma dos numeros.`n     *`n     * @param a primero`n     * @param b segundo`n     * @return la suma`n     */`n" + $metodo))
  $r2 = Sonar-Lanza $e $d
  Igual 'con un Javadoc encima ya no hay error' 0 (Hallazgos-Sonar $e.Repo 'error').Count
  Comprueba 'y cuenta 1 resuelta' ($r2.Salida -match 'Sonar: 1 resueltas aqui\.') (Cola $r2.Salida)
}

$Pruebas['m10 sonar: unidad de una incidencia - la linea, o el bloque que abre con su Javadoc y sus anotaciones; normalizada'] = {
  . ([scriptblock]::Create((Texto-Sonar)))
  $java = @'
class A {
    /** Doc. */
    @Override
    public String f(String s) {   // marcada
        String t = "}{ y // no es comentario";
        // } llave en comentario
        if (s == null) {
            return t;
        }
        return s;
    }

    int x = 1;
    int y = 2; // mia
}
'@
  $u = Get-SonarUnidad $java 4
  Igual 'un metodo con Javadoc y anotacion: todo el bloque, sin espacios, con cadenas y Javadoc, sin comentarios normales' '/**Doc.*/@OverridepublicStringf(Strings){Stringt="}{y//noescomentario";if(s==null){returnt;}returns;}' $u.Unidad
  Igual 'y no se dice sin Javadoc' $false $u.SinDoc
  Igual 'una linea que no abre bloque: solo ella' 'intx=1;' (Get-SonarUnidad $java 13).Unidad
  Igual 'sin su comentario final' 'inty=2;' (Get-SonarUnidad $java 14).Unidad
  Igual 'una linea sola no lleva marca de sin Javadoc' $false (Get-SonarUnidad $java 13).SinDoc
  $b = @'
class B {
    @Override
    public String g() {
        return "x";
    }
}
'@
  $ub = Get-SonarUnidad $b 3
  Igual 'sin Javadoc: la anotacion y el metodo' '@OverridepublicStringg(){return"x";}' $ub.Unidad
  Igual 'y queda marcado como sin Javadoc' $true $ub.SinDoc
  Igual 'la clase entera si la marcada es su declaracion' 'classB{@OverridepublicStringg(){return"x";}}' (Get-SonarUnidad $b 1).Unidad
  Igual 'sin numero de linea (0) o fuera de rango, el fichero entero' 'classB{@OverridepublicStringg(){return"x";}}' (Get-SonarUnidad $b 0).Unidad
  Igual 'fuera de rango, el fichero entero' 'classB{@OverridepublicStringg(){return"x";}}' (Get-SonarUnidad $b 99).Unidad
  # esta ahi o no
  $normal = Get-SonarNormal $b
  Igual 'el mismo fichero: sigue ahi' $true (Test-SonarSigueAhi $ub.Unidad $ub.SinDoc $normal)
  Igual 'con otros espacios: sigue ahi' $true (Test-SonarSigueAhi $ub.Unidad $ub.SinDoc (Get-SonarNormal ($b.Replace('return "x";', "return   `"x`" ;  // nota"))))
  Igual 'con otro cuerpo: ya no' $false (Test-SonarSigueAhi $ub.Unidad $ub.SinDoc (Get-SonarNormal ($b.Replace('"x"', '"y"'))))
  Igual 'con un Javadoc encima: ya no' $false (Test-SonarSigueAhi $ub.Unidad $ub.SinDoc (Get-SonarNormal ($b.Replace('    @Override', "    /** Doc. */`n    @Override"))))
  Igual 'con un comentario normal encima: sigue ahi' $true (Test-SonarSigueAhi $ub.Unidad $ub.SinDoc (Get-SonarNormal ($b.Replace('    @Override', "    /* nota */`n    @Override"))))
  Igual 'un metodo que ya tenia Javadoc: sigue ahi aunque lleve Javadoc encima' $true (Test-SonarSigueAhi $u.Unidad $u.SinDoc (Get-SonarNormal $java))
  Igual 'con el Javadoc cambiado: ya no' $false (Test-SonarSigueAhi $u.Unidad $u.SinDoc (Get-SonarNormal ($java.Replace('Doc.', 'Otro texto.'))))
}

$Pruebas['m10 sonar: puertas del diff - anadida, neto+, neto-, neto0, sumando todo el diff, y las condiciones Si y Salvo'] = {
  . ([scriptblock]::Create((Texto-Sonar)))
  # un diff como el de git: por fichero, con sus lineas + y -
  function Diff-De($Ficheros) {
    $t = New-Object System.Collections.ArrayList
    foreach ($f in $Ficheros.Keys) {
      foreach ($x in @("diff --git a/$f b/$f", "--- a/$f", "+++ b/$f", '@@ -1,3 +1,3 @@')) { [void]$t.Add($x) }
      foreach ($l in @($Ficheros[$f])) { [void]$t.Add($l) }
    }
    return (($t.ToArray()) -join "`n") + "`n"
  }
  function Pasa([string]$Diff, $Entradas, [string[]]$Mensajes = @()) { return (@(Get-SonarProhibidas $Diff $Entradas $Mensajes)).Count -eq 0 }
  $anad = @(, @{ Rx = '@Disabled'; Modo = 'anadida'; Motivo = 'm-anadida' })
  Igual 'anadida: una linea + que casa falla' $false (Pasa (Diff-De @{ 'a/A.java' = @('+    @Disabled', '-    foo();') }) $anad)
  Igual 'anadida: la misma linea quitada (-) no falla' $true (Pasa (Diff-De @{ 'a/A.java' = @('-    @Disabled') }) $anad)
  Igual 'anadida: una + que no casa no falla' $true (Pasa (Diff-De @{ 'a/A.java' = @('+    foo();') }) $anad)
  Igual 'anadida: no cuenta las cabeceras +++ del diff (el nombre del fichero no es una linea anadida)' $true (Pasa (Diff-De @{ 'a/Disabled.java' = @('+    foo();') }) @(, @{ Rx = 'Disabled\.java'; Modo = 'anadida'; Motivo = 'm-cabecera' }))
  $mas = @(, @{ Rx = 'catch \(Exception'; Modo = 'neto+'; Motivo = 'm-mas' })
  Igual 'neto+: una mas que menos falla' $false (Pasa (Diff-De @{ 'a/A.java' = @('+    } catch (Exception e) {') }) $mas)
  Igual 'neto+: una que sale y otra que entra no falla' $true (Pasa (Diff-De @{ 'a/A.java' = @('-    } catch (Exception e) {', '+    } catch (Exception ex) {') }) $mas)
  Igual 'neto+: de mas a menos no falla' $true (Pasa (Diff-De @{ 'a/A.java' = @('-    } catch (Exception e) {') }) $mas)
  $menos = @(, @{ Rx = '@Test'; Modo = 'neto-'; Motivo = 'm-menos' })
  Igual 'neto-: una menos que mas falla' $false (Pasa (Diff-De @{ 'a/A.java' = @('-    @Test') }) $menos)
  Igual 'neto-: mover la linea (sale y entra) no falla' $true (Pasa (Diff-De @{ 'a/A.java' = @('-    @Test', '+    @Test') }) $menos)
  Igual 'neto-: anadir no falla' $true (Pasa (Diff-De @{ 'a/A.java' = @('+    @Test') }) $menos)
  Igual 'neto- suma todo el diff: lo que sale de un fichero lo compensa lo que entra en otro (mover a otra clase da 0)' $true (Pasa (Diff-De @{ 'a/A.java' = @('-    @Test'); 'a/B.java' = @('+    @Test') }) $menos)
  Igual 'neto- suma todo el diff: si en total salen mas de las que entran, falla' $false (Pasa (Diff-De @{ 'a/A.java' = @('-    @Test', '-    @Test'); 'a/B.java' = @('+    @Test') }) $menos)
  $cero = @(, @{ Rx = 'foo'; Modo = 'neto0'; Motivo = 'm-cero' })
  Igual 'neto0: mas que menos falla' $false (Pasa (Diff-De @{ 'a/A.java' = @('+    foo(1);', '+    foo(2);', '-    foo(0);') }) $cero)
  Igual 'neto0: menos que mas falla' $false (Pasa (Diff-De @{ 'a/A.java' = @('-    foo(1);') }) $cero)
  Igual 'neto0: igual no falla' $true (Pasa (Diff-De @{ 'a/A.java' = @('+    foo(1);', '-    foo(0);') }) $cero)
  Igual 'neto0: sin ninguna no falla' $true (Pasa (Diff-De @{ 'a/A.java' = @('+    bar();') }) $cero)
  # el motivo de cada entrada que falla, una vez cada una
  $todas = @($anad[0], $mas[0], $menos[0])
  $m = @(Get-SonarProhibidas (Diff-De @{ 'a/A.java' = @('+    @Disabled', '+    } catch (Exception e) {', '-    @Test') }) $todas @())
  Igual 'los motivos de las tres que fallan, en el orden de la lista' 'm-anadida|m-mas|m-menos' ($m -join '|')
  # la condicion Si: solo se aplica si algun mensaje del lote casa
  $si = @(, @{ Rx = '@Test'; Modo = 'neto-'; Motivo = 'm-si'; Si = 'condicion-prueba' })
  $dif = Diff-De @{ 'a/A.java' = @('-    @Test') }
  Igual 'Si: con un mensaje que no la cumple no cuenta' $true (Pasa $dif $si @('otro mensaje', 'y otro'))
  Igual 'Si: sin mensajes no cuenta' $true (Pasa $dif $si @())
  Igual 'Si: con un mensaje que la cumple cuenta (sin mirar mayusculas)' $false (Pasa $dif $si @('otro mensaje', 'Mensaje CONDICION-PRUEBA con texto'))
  Igual 'sin Si se aplica con cualquier mensaje' $false (Pasa $dif $menos @('lo que sea'))
  # la condicion Salvo, lo contrario de Si: la entrada no se aplica si algun mensaje del lote casa
  $salvo = @(, @{ Rx = '@Test'; Modo = 'neto-'; Motivo = 'm-salvo'; Salvo = 'excepcion-prueba' })
  Igual 'Salvo: con mensajes que no la cumplen la entrada se aplica' $false (Pasa $dif $salvo @('otro mensaje', 'y otro'))
  Igual 'Salvo: sin mensajes la entrada se aplica' $false (Pasa $dif $salvo @())
  Igual 'Salvo: con un mensaje que la cumple (sin mirar mayusculas) no se aplica' $true (Pasa $dif $salvo @('otro mensaje', 'Mensaje EXCEPCION-PRUEBA con texto'))
  $ambas = @(, @{ Rx = '@Test'; Modo = 'neto-'; Motivo = 'm-ambas'; Si = 'condicion-prueba'; Salvo = 'excepcion-prueba' })
  Igual 'Si y Salvo juntas: casa Si y no Salvo, se aplica' $false (Pasa $dif $ambas @('condicion-prueba aqui'))
  Igual 'Si y Salvo juntas: casan las dos, no se aplica' $true (Pasa $dif $ambas @('condicion-prueba aqui', 'excepcion-prueba aqui'))
  Igual 'Si y Salvo juntas: solo casa Salvo, no se aplica' $true (Pasa $dif $ambas @('excepcion-prueba aqui'))
  Igual 'Si y Salvo juntas: no casa ninguna, no se aplica' $true (Pasa $dif $ambas @('otro mensaje'))
  Igual 'Si y Salvo en mensajes distintos del lote: Salvo manda' $true (Pasa $dif $ambas @('condicion-prueba aqui', 'otro', 'excepcion-prueba'))
  # las Rx se aplican al texto de la linea SIN el + o - del diff, y sin distinguir mayusculas ((?-i:...) vuelve a distinguirlas)
  $ancla = @(, @{ Rx = '^\s*@Disabled\b'; Modo = 'anadida'; Motivo = 'm-ancla' })
  Igual 'Rx anclada: ^\s* casa con la linea sin el + del diff' $false (Pasa (Diff-De @{ 'a/A.java' = @('+    @Disabled') }) $ancla)
  Igual 'Rx anclada: si la linea no empieza por la anotacion no casa' $true (Pasa (Diff-De @{ 'a/A.java' = @('+    // @Disabled') }) $ancla)
  Igual 'Rx anclada con neto-: casa con la linea sin el - del diff' $false (Pasa (Diff-De @{ 'a/A.java' = @('-    @Test') }) @(, @{ Rx = '^\s*@Test\b'; Modo = 'neto-'; Motivo = 'm-ancla-menos' }))
  $may = @(, @{ Rx = 'nosonar'; Modo = 'anadida'; Motivo = 'm-may' })
  Igual 'sin distinguir mayusculas: nosonar casa con NOSONAR' $false (Pasa (Diff-De @{ 'a/A.java' = @('+    int x = 1; // NOSONAR') }) $may)
  $dist = @(, @{ Rx = '(?-i:NOSONAR)'; Modo = 'anadida'; Motivo = 'm-dist' })
  Igual '(?-i:) distingue: NOSONAR casa' $false (Pasa (Diff-De @{ 'a/A.java' = @('+    int x = 1; // NOSONAR') }) $dist)
  Igual '(?-i:) distingue: nosonar no casa' $true (Pasa (Diff-De @{ 'a/A.java' = @('+    int x = 1; // nosonar') }) $dist)
}

$Pruebas['m10 sonar: SonarProhibido neto-: quitar un @Test invalida el intento aunque arregle la linea; sin la entrada lo para la puerta de metodos de test'] = {
  $proh = @(, @{ Rx = '@Test'; Modo = 'neto-'; Motivo = 'MOTIVO-PRUEBA-NETO: no se quitan tests' })
  $e = Escenario-Sonar 'm10-neto' @('service/TotalService') @{ SonarProhibido = $proh }
  $total = $RutaSv + 'service/TotalService.java'
  $ln = Linea-De (Lee $e.Repo $total) 'int resultado'
  Informe-Sonar $e.Xlsx @(, (Inc 'CRITICAL' 'Fix this null dereference.' 'BUG' 'TotalService.java' $total "${ln}L"))
  $a = @('-Modo', 'fix', '-Paso', 'sonar', '-Sonar', $e.Xlsx, '-Auto', '-Si', '-MaxIntentos', '2', '-MaxLotes', '1')
  $r = Sonar-Lanza $e $a 'sonar-quita-test'
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  Comprueba 'el intento no pasa y dice el motivo de la entrada' ($r.Salida -match 'NO PASA: .*MOTIVO-PRUEBA-NETO') (Cola $r.Salida)
  Comprueba 'el lote se deshace' ($r.Salida -match 'Lote 1 DESHECHO') (Cola $r.Salida)
  Igual 'no hay commits nuevos' 'inicial' (GitEn $e.Wt @('log', '--format=%s'))
  Comprueba 'el test conserva su @Test' ((Lee $e.Wt 'src/test/java/com/acme/plantillabatch/service/TotalServiceTest.java').Contains('@Test'))
  Comprueba 'el motivo va al siguiente intento' ((Lee $e.Wt '.rescate/prompt.md').Contains('MOTIVO-PRUEBA-NETO')) (Cola $r.Salida)
  # el mismo intento sin la entrada: pasa (la regla viene de la config, no esta en el codigo)
  $e2 = Escenario-Sonar 'm10-neto-control' @('service/TotalService')
  Informe-Sonar $e2.Xlsx @(, (Inc 'CRITICAL' 'Fix this null dereference.' 'BUG' 'TotalService.java' $total "${ln}L"))
  $r2 = Sonar-Lanza $e2 @('-Modo', 'fix', '-Paso', 'sonar', '-Sonar', $e2.Xlsx, '-Auto', '-Si', '-MaxIntentos', '2', '-MaxLotes', '1') 'sonar-quita-test'
  # sin la entrada, quitar el @Test ya no pasa: lo para la puerta general de metodos de test (M20a), no la entrada
  Comprueba 'sin la entrada no sale su motivo: lo para la puerta de metodos de test' ($r2.Salida -match 'NO PASA: .*Has borrado 1 metodos de test \(1 -> 0\)' -and $r2.Salida -notmatch 'MOTIVO-PRUEBA-NETO') (Cola $r2.Salida)
}

$Pruebas['m10 sonar: crear .java nuevos se permite; tocar ficheros que no son .java, o borrar o renombrar algo de src/test, invalida el intento'] = {
  $total = $RutaSv + 'service/TotalService.java'
  $casos = @(
    @{ G = 'sonar-fichero-nuevo'; Pasa = $true; Motivo = '' },
    @{ G = 'sonar-toca-pom'; Pasa = $false; Motivo = 'que no son \.java' },
    @{ G = 'sonar-borra-test'; Pasa = $false; Motivo = 'borrar ni renombrar.*src/test' },
    @{ G = 'sonar-renombra-test'; Pasa = $false; Motivo = 'borrar ni renombrar.*src/test' })
  foreach ($c in $casos) {
    $caso = $c.G
    $e = Escenario-Sonar ('m10-estructura-' + $caso) @('service/TotalService')
    $ln = Linea-De (Lee $e.Repo $total) 'int resultado'
    Informe-Sonar $e.Xlsx @(, (Inc 'CRITICAL' 'Fix this null dereference.' 'BUG' 'TotalService.java' $total "${ln}L"))
    $r = Sonar-Lanza $e @('-Modo', 'fix', '-Paso', 'sonar', '-Sonar', $e.Xlsx, '-Auto', '-Si', '-MaxIntentos', '1', '-MaxLotes', '1') $caso
    if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba "$caso : existe el worktree" $false (Cola $r.Salida); continue }
    if ($c.Pasa) {
      Comprueba "$caso : el lote pasa" ($r.Salida -match "Lote 1 OK: 'sonar' 1 -> 0") (Cola $r.Salida)
      Comprueba "$caso : y el fichero nuevo entra en el commit" ((GitEn $e.Wt @('show', '--stat', '--format=', 'HEAD')) -match 'Nuevo\.java') (GitEn $e.Wt @('show', '--stat', '--format=', 'HEAD'))
      Igual "$caso : el worktree queda limpio" '' (GitEn $e.Wt @('status', '--porcelain'))
    }
    else {
      Comprueba "$caso : el intento no pasa y dice por que" ($r.Salida -match ('NO PASA: .*' + $c.Motivo)) (Cola $r.Salida)
      Comprueba "$caso : el lote se deshace" ($r.Salida -match 'Lote 1 DESHECHO') (Cola $r.Salida)
      Igual "$caso : no hay commits nuevos" 'inicial' (GitEn $e.Wt @('log', '--format=%s'))
      Igual "$caso : el worktree queda limpio" '' (GitEn $e.Wt @('status', '--porcelain'))
    }
  }
}

$Pruebas['m10 sonar: un .java nuevo solo vale en la carpeta de una clase que el lote ya modifica; sus lineas cuentan en los neto; el indice queda como estaba; .rescate se ignora'] = {
  $total = $RutaSv + 'service/TotalService.java'
  $nuevo = $RutaSv + 'service/Nuevo.java'
  function Escenario-Nuevo([string]$Nombre, [hashtable]$Mas) {
    $e = Escenario-Sonar $Nombre @('service/TotalService') $Mas
    $ln = Linea-De (Lee $e.Repo $total) 'int resultado'
    Informe-Sonar $e.Xlsx @(, (Inc 'CRITICAL' 'Fix this null dereference.' 'BUG' 'TotalService.java' $total "${ln}L"))
    return $e
  }
  $a = @('-Modo', 'fix', '-Paso', 'sonar', '-Auto', '-Si', '-MaxIntentos', '1', '-MaxLotes', '1')
  # en el mismo paquete que la clase que arregla: pasa (y el modelo deja ademas su fichero en .rescate sin que moleste)
  $e1 = Escenario-Nuevo 'm10-nuevo-mismo' @{}
  $r1 = Sonar-Lanza $e1 ($a + @('-Sonar', $e1.Xlsx)) 'sonar-fichero-nuevo'
  if (-not (Test-Path -LiteralPath (Join-Path $e1.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r1.Salida); return }
  Comprueba 'mismo paquete: el lote pasa' ($r1.Salida -match "Lote 1 OK: 'sonar' 1 -> 0") (Cola $r1.Salida)
  Comprueba 'mismo paquete: el fichero nuevo entra en el commit' ((GitEn $e1.Wt @('show', '--stat', '--format=', 'HEAD')) -match 'Nuevo\.java')
  # sus lineas cuentan en los neto: con un neto+ que casa con una linea de la clase nueva, el mismo intento no pasa
  $proh = @(, @{ Rx = 'public class Nuevo'; Modo = 'neto+'; Motivo = 'MOTIVO-PRUEBA-NETO-NUEVO' })
  $e2 = Escenario-Nuevo 'm10-nuevo-neto' @{ SonarProhibido = $proh }
  $r2 = Sonar-Lanza $e2 ($a + @('-Sonar', $e2.Xlsx)) 'sonar-fichero-nuevo'
  Comprueba 'mismo paquete con neto+: el intento no pasa y dice el motivo' ($r2.Salida -match 'NO PASA: .*MOTIVO-PRUEBA-NETO-NUEVO') (Cola $r2.Salida)
  # el indice de git queda como estaba tras comprobar el diff, pase o no el intento
  Igual 'el indice queda limpio (nada preparado) tras el intento que no pasa' '' (GitEn $e2.Wt @('diff', '--cached', '--name-only'))
  # en otro paquete: no pasa y dice donde crearla
  $e3 = Escenario-Nuevo 'm10-nuevo-otro' @{}
  $r3 = Sonar-Lanza $e3 ($a + @('-Sonar', $e3.Xlsx)) 'sonar-fichero-nuevo-otro'
  Comprueba 'otro paquete: el intento no pasa y dice que la cree en el mismo paquete que la clase que arregla' ($r3.Salida -match 'NO PASA: .*crea la clase nueva en el mismo paquete que la clase que arreglas') (Cola $r3.Salida)
  Comprueba 'otro paquete: el lote se deshace' ($r3.Salida -match 'Lote 1 DESHECHO') (Cola $r3.Salida)
  Igual 'otro paquete: no hay commits nuevos' 'inicial' (GitEn $e3.Wt @('log', '--format=%s'))
  Igual 'otro paquete: el worktree queda limpio' '' (GitEn $e3.Wt @('status', '--porcelain'))
  Igual 'otro paquete: el indice queda limpio' '' (GitEn $e3.Wt @('diff', '--cached', '--name-only'))
  # lo que el modelo escribe en .rescate (sonar-sin-arreglar.txt) no cuenta como fichero tocado que no es .java
  $e4 = Escenario-Sonar 'm10-nuevo-rescate' @('service/TotalService', 'service/ReciboService')
  $lnT = Linea-De (Lee $e4.Repo $total) 'int resultado'
  $recibo = $RutaSv + 'service/ReciboService.java'
  $lnR = Linea-De (Lee $e4.Repo $recibo) 'int resultado'
  Informe-Sonar $e4.Xlsx @((Inc 'CRITICAL' 'Fix this null dereference.' 'BUG' 'TotalService.java' $total "${lnT}L"), (Inc 'CRITICAL' 'DEJAME: no se toca.' 'BUG' 'ReciboService.java' $recibo "${lnR}L"))
  $r4 = Sonar-Lanza $e4 ($a + @('-Sonar', $e4.Xlsx)) 'sonar-deja'
  Comprueba 'con lo apuntado en .rescate el lote pasa' ($r4.Salida -match "Lote 1 OK: 'sonar' 2 -> 0") (Cola $r4.Salida)
  Comprueba 'y no dice que haya tocado ficheros que no son .java' ($r4.Salida -notmatch 'que no son \.java') (Cola $r4.Salida)
}

$Pruebas['m10 sonar: una clase nueva sin Javadoc hace fallar el intento por calidad; con Javadoc pasa'] = {
  $total = $RutaSv + 'service/TotalService.java'
  $e = Escenario-Sonar 'm10-nuevo-sindoc' @('service/TotalService')
  $ln = Linea-De (Lee $e.Repo $total) 'int resultado'
  Informe-Sonar $e.Xlsx @(, (Inc 'CRITICAL' 'Fix this null dereference.' 'BUG' 'TotalService.java' $total "${ln}L"))
  $a = @('-Modo', 'fix', '-Paso', 'sonar', '-Auto', '-Si', '-MaxIntentos', '1', '-MaxLotes', '1', '-Sonar', $e.Xlsx)
  $r = Sonar-Lanza $e $a 'sonar-fichero-nuevo-sin-doc'
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  Comprueba 'sin Javadoc: el intento no pasa y dice que anade hallazgos de calidad' ($r.Salida -match 'NO PASA: .*hallazgos de calidad') (Cola $r.Salida)
  Comprueba 'sin Javadoc: el lote se deshace' ($r.Salida -match 'Lote 1 DESHECHO') (Cola $r.Salida)
  Igual 'sin Javadoc: no hay commits nuevos' 'inicial' (GitEn $e.Wt @('log', '--format=%s'))
  Igual 'sin Javadoc: el worktree queda limpio' '' (GitEn $e.Wt @('status', '--porcelain'))
}

$Pruebas['m10 sonar: con plantilla la colocacion cuenta (una clase nueva fuera de las capas empeora estructura); sin plantilla no'] = {
  $total = $RutaSv + 'service/TotalService.java'
  $e = Escenario-Sonar 'm10-nuevo-plantilla' @('service/TotalService')
  $ln = Linea-De (Lee $e.Repo $total) 'int resultado'
  Informe-Sonar $e.Xlsx @(, (Inc 'CRITICAL' 'Fix this null dereference.' 'BUG' 'TotalService.java' $total "${ln}L"))
  $pl = Join-Path $e.Raiz 'plantilla'
  Nueva-Plantilla $pl
  $a = @('-Modo', 'fix', '-Paso', 'sonar', '-Auto', '-Si', '-MaxIntentos', '1', '-MaxLotes', '1', '-Sonar', $e.Xlsx)
  $r = Sonar-Lanza $e ($a + @('-Plantilla', $pl)) 'sonar-fichero-nuevo'
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  Comprueba 'con plantilla el intento no pasa y dice que ha empeorado estructura' ($r.Salida -match "NO PASA: .*empeorado el paso anterior 'estructura'") (Cola $r.Salida)
  Comprueba 'con plantilla el lote se deshace' ($r.Salida -match 'Lote 1 DESHECHO') (Cola $r.Salida)
  # el mismo intento sin plantilla ya esta cubierto por el test de .java nuevos: pasa
  $e2 = Escenario-Sonar 'm10-nuevo-sinplantilla' @('service/TotalService')
  Informe-Sonar $e2.Xlsx @(, (Inc 'CRITICAL' 'Fix this null dereference.' 'BUG' 'TotalService.java' $total "${ln}L"))
  $r2 = Sonar-Lanza $e2 ($a[0..($a.Count - 2)] + @($e2.Xlsx)) 'sonar-fichero-nuevo'
  Comprueba 'sin plantilla el mismo intento pasa' ($r2.Salida -match "Lote 1 OK: 'sonar' 1 -> 0") (Cola $r2.Salida)
}

$Pruebas['m10 sonar: el hallazgo de inyeccion en campo pide ademas no tocar el estado mutable del componente'] = {
  $campo = "package com.acme.plantillabatch.service;`n`nimport org.springframework.beans.factory.annotation.Autowired;`n`n/** Servicio con inyeccion por campo. */`npublic class Campo {`n`n    @Autowired`n    private TotalService total;`n}`n"
  $e = Escenario-Sonar 'm10-inyeccion' @('service/TotalService') @{} @() @{ 'service/Campo' = $campo }
  $r = Sonar-Lanza $e @('-Modo', 'diagnostico', '-SinBuild')
  $h = @(Hallazgos $e.Repo | Where-Object { $_.Cat -eq 'calidad' -and $_.Detalle -like '*@Autowired en el campo*' })
  Igual 'sale el hallazgo de inyeccion en campo' 1 $h.Count
  if ($h.Count -eq 1) {
    Comprueba 'sigue pidiendo constructor con campos private final' ($h[0].Detalle.Contains('usa inyeccion por constructor con campos private final')) $h[0].Detalle
    Comprueba 'y dice que un campo con estado entre llamadas no se convierte en final ni se inicializa en el constructor, que lo diga' ($h[0].Detalle.EndsWith('; sin estado mutable en el componente: si un campo guarda estado entre llamadas, no lo conviertas en final ni lo inicialices en el constructor; dilo')) $h[0].Detalle
  }
}

$Pruebas['m10 sonar: las reglas por defecto salen de sonar-reglas.ps1; sin ese fichero junto al script, -Sonar lo dice y sale con 1'] = {
  $reglas = Join-Path (Split-Path -Parent $Script) 'sonar-reglas.ps1'
  Comprueba 'existe sonar-reglas.ps1 junto a rescate.ps1' (Test-Path -LiteralPath $reglas)
  if (-not (Test-Path -LiteralPath $reglas)) { return }
  . $reglas
  $total = $RutaSv + 'service/TotalService.java'
  $e = Escenario-Sonar 'm10-reglas' @('service/TotalService')
  $ln = Linea-De (Lee $e.Repo $total) 'int resultado'
  Informe-Sonar $e.Xlsx @(, (Inc 'CRITICAL' 'Fix this null dereference.' 'BUG' 'TotalService.java' $total "${ln}L"))
  $r = Sonar-Lanza $e @('-Modo', 'fix', '-Paso', 'sonar', '-Sonar', $e.Xlsx, '-Auto', '-Si', '-MaxIntentos', '1', '-MaxLotes', '1')
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  $prompt = Lee $e.Wt '.rescate/prompt.md'
  $primera = @("$SonarPromptReal" -split "`r?`n" | Where-Object { $_.Trim() })[0].Trim()
  Comprueba 'el prompt lleva el texto general del fichero de reglas' ($prompt.Contains($primera)) $primera
  Comprueba 'y las reglas del fichero tienen las cuatro listas' ((@($SonarRecetasReal).Count -gt 0) -and (@($SonarNoAutomatizarReal).Count -gt 0) -and (@($SonarProhibidoReal).Count -gt 0))
  # sin el fichero, rescate.ps1 y comun.ps1 solos: sin -Sonar funciona y con -Sonar dice que falta
  $solos = Join-Path $e.Raiz 'solos'
  [void](New-Item -ItemType Directory -Path $solos -Force)
  Copy-Item -LiteralPath $Script, (Join-Path (Split-Path -Parent $Script) 'comun.ps1') -Destination $solos
  $r2 = Lanzar (Join-Path $solos 'rescate.ps1') @('-Repo', $e.Repo, '-Sonar', $e.Xlsx, '-Modo', 'diagnostico', '-SinBuild')
  Igual 'sin sonar-reglas.ps1 y con -Sonar sale con 1' 1 $r2.Codigo
  Comprueba 'y dice que falta sonar-reglas.ps1' ($r2.Salida -match 'sonar-reglas\.ps1') (Cola $r2.Salida)
  $r3 = Lanzar (Join-Path $solos 'rescate.ps1') @('-Repo', $e.Repo, '-Modo', 'diagnostico', '-SinBuild')
  Igual 'sin sonar-reglas.ps1 y sin -Sonar el diagnostico sale con 0' 0 $r3.Codigo
}

$Pruebas['m10 sonar: partir una clase en dos, con una nueva en otro fichero, pasa y resuelve la incidencia; las lineas del fichero nuevo cuentan como anadidas'] = {
  $total = $RutaSv + 'service/TotalService.java'
  $recibo = $RutaSv + 'service/ReciboService.java'
  $nuevo = $RutaSv + 'service/TotalServiceSuma.java'
  function Escenario-Parte([string]$Nombre, [hashtable]$Mas) {
    $e = Escenario-Sonar $Nombre @('service/TotalService', 'service/ReciboService') $Mas
    $lnClase = Linea-De (Lee $e.Repo $total) 'public class TotalService'
    $lnLinea = Linea-De (Lee $e.Repo $recibo) 'int resultado'
    # una incidencia de la clase entera y otra de una linea que se va a la clase nueva
    Informe-Sonar $e.Xlsx @(
      (Inc 'MAJOR' 'Split this class, it has too many responsibilities.' 'CODE_SMELL' 'TotalService.java' $total "${lnClase}L"),
      (Inc 'CRITICAL' 'Fix this null dereference.' 'BUG' 'ReciboService.java' $recibo "${lnLinea}L"))
    return $e
  }
  $a = @('-Modo', 'fix', '-Paso', 'sonar', '-Auto', '-Si', '-MaxIntentos', '1', '-MaxLotes', '1')
  $e = Escenario-Parte 'm10-parte' @{}
  $r = Sonar-Lanza $e ($a + @('-Sonar', $e.Xlsx)) 'sonar-parte-clase'
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  Comprueba 'el lote pasa' ($r.Salida -match "Lote 1 OK: 'sonar' 2 -> 0") (Cola $r.Salida)
  Comprueba 'la clase nueva esta en su fichero' ((Lee $e.Wt $nuevo).Contains('public class TotalServiceSuma')) (Cola $r.Salida)
  Comprueba 'y el metodo ya no esta en la original' (-not (Lee $e.Wt $total).Contains('public int suma(')) (Cola $r.Salida)
  Comprueba 'las dos incidencias cuentan como resueltas' ($r.Salida -match 'Sonar: 2 resueltas aqui\.') (Cola $r.Salida)
  Comprueba 'el fichero nuevo entra en el commit' ((GitEn $e.Wt @('show', '--stat', '--format=', 'HEAD')) -match 'TotalServiceSuma\.java') (GitEn $e.Wt @('show', '--stat', '--format=', 'HEAD'))
  # con una entrada anadida que casa con una linea de la clase nueva, el mismo intento no pasa: las lineas de un fichero nuevo cuentan como +
  $proh = @(, @{ Rx = 'public class \w+Suma'; Modo = 'anadida'; Motivo = 'MOTIVO-PRUEBA-CLASE-NUEVA' })
  $e2 = Escenario-Parte 'm10-parte-prohibida' @{ SonarProhibido = $proh }
  $r2 = Sonar-Lanza $e2 ($a + @('-Sonar', $e2.Xlsx)) 'sonar-parte-clase'
  Comprueba 'con la entrada el intento no pasa y dice el motivo' ($r2.Salida -match 'NO PASA: .*MOTIVO-PRUEBA-CLASE-NUEVA') (Cola $r2.Salida)
}

$Pruebas['m10 sonar: borrar una clase cuyo nombre aparece en src/main/resources invalida el intento; si no aparece, se permite'] = {
  $yml = "servicios:`n  recibo: com.acme.plantillabatch.service.ReciboService`n"
  foreach ($caso in @(@{ N = 'recibo'; Clase = 'ReciboService'; Pasa = $false }, @{ N = 'pago'; Clase = 'PagoService'; Pasa = $true })) {
    $e = Escenario-Sonar ('m10-borra-' + $caso.N) @('service/ReciboService', 'service/PagoService') @{} @() @{ '/src/main/resources/application.yml' = $yml }
    $ruta = $RutaSv + 'service/' + $caso.Clase + '.java'
    $ln = Linea-De (Lee $e.Repo $ruta) 'int resultado'
    Informe-Sonar $e.Xlsx @(, (Inc 'MAJOR' 'Remove this empty class.' 'CODE_SMELL' ($caso.Clase + '.java') $ruta "${ln}L"))
    $r = Sonar-Lanza $e @('-Modo', 'fix', '-Paso', 'sonar', '-Sonar', $e.Xlsx, '-Auto', '-Si', '-MaxIntentos', '1', '-MaxLotes', '1') 'sonar-borra-clase'
    if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba "$($caso.N) : existe el worktree" $false (Cola $r.Salida); continue }
    if ($caso.Pasa) {
      Comprueba "$($caso.N) : sin el nombre en resources el lote pasa" ($r.Salida -match "Lote 1 OK: 'sonar' 1 -> 0") (Cola $r.Salida)
      Comprueba "$($caso.N) : y la clase ya no esta" (-not (Test-Path -LiteralPath (Get-Ruta $e.Wt $ruta)))
      Comprueba "$($caso.N) : la incidencia cuenta como resuelta (el fichero ya no existe)" ($r.Salida -match 'Sonar: 1 resueltas aqui\.') (Cola $r.Salida)
    }
    else {
      Comprueba "$($caso.N) : con el nombre en application.yml el intento no pasa y dice por que" ($r.Salida -match ('NO PASA: .*' + $caso.Clase + '.*application\.yml') -and $r.Salida -match 'se cablea por nombre') (Cola $r.Salida)
      Comprueba "$($caso.N) : el lote se deshace y la clase sigue" ($r.Salida -match 'Lote 1 DESHECHO' -and (Test-Path -LiteralPath (Get-Ruta $e.Wt $ruta))) (Cola $r.Salida)
    }
  }
}

$Pruebas['m10 sonar: una entrada de SonarProhibido con Si solo cuenta en el lote que tiene un mensaje que la cumple'] = {
  $proh = @(, @{ Rx = '@Test'; Modo = 'neto-'; Motivo = 'MOTIVO-PRUEBA-SI'; Si = 'SI-PRUEBA' })
  $total = $RutaSv + 'service/TotalService.java'
  # lote sin el mensaje: la entrada no se aplica (su motivo no sale); quitar el @Test lo para la puerta general de metodos de test (M20a)
  $e1 = Escenario-Sonar 'm10-si-sin' @('service/TotalService') @{ SonarProhibido = $proh }
  $ln = Linea-De (Lee $e1.Repo $total) 'int resultado'
  Informe-Sonar $e1.Xlsx @(, (Inc 'CRITICAL' 'Fix this null dereference.' 'BUG' 'TotalService.java' $total "${ln}L"))
  $r1 = Sonar-Lanza $e1 @('-Modo', 'fix', '-Paso', 'sonar', '-Sonar', $e1.Xlsx, '-Auto', '-Si', '-MaxIntentos', '1', '-MaxLotes', '1') 'sonar-quita-test'
  Comprueba 'sin el mensaje la entrada no se aplica: no sale su motivo' ($r1.Salida -match 'NO PASA: .*Has borrado 1 metodos de test \(1 -> 0\)' -and $r1.Salida -notmatch 'MOTIVO-PRUEBA-SI') (Cola $r1.Salida)
  # lote con el mensaje: la entrada se aplica
  $e2 = Escenario-Sonar 'm10-si-con' @('service/TotalService') @{ SonarProhibido = $proh }
  Informe-Sonar $e2.Xlsx @(, (Inc 'CRITICAL' 'Fix this SI-PRUEBA null dereference.' 'BUG' 'TotalService.java' $total "${ln}L"))
  $r2 = Sonar-Lanza $e2 @('-Modo', 'fix', '-Paso', 'sonar', '-Sonar', $e2.Xlsx, '-Auto', '-Si', '-MaxIntentos', '1', '-MaxLotes', '1') 'sonar-quita-test'
  Comprueba 'con el mensaje el intento no pasa y dice el motivo' ($r2.Salida -match 'NO PASA: .*MOTIVO-PRUEBA-SI') (Cola $r2.Salida)
  Comprueba 'y el lote se deshace' ($r2.Salida -match 'Lote 1 DESHECHO') (Cola $r2.Salida)
}

$Pruebas['m10 sonar: las recetas con Avisar listan lo arreglado a proposito; y los mensajes sin receta ni exclusion salen contados, en consola y en sonar-faltan.md'] = {
  $rec = @(
    @{ Rx = 'cognitive complexity'; Texto = 'RECETA-PRUEBA-AVISO: cambia el resultado a proposito.'; Avisar = $true },
    @{ Rx = 'generic exception'; Texto = 'RECETA-PRUEBA-NORMAL: nada raro.' })
  $no = @(, @{ Rx = 'enum-prueba'; Motivo = 'prueba: no se automatiza' })
  $cl = @('service/TotalService', 'service/ReciboService', 'service/PagoService', 'service/CobroService', 'service/AjusteService')
  $e = Escenario-Sonar 'm10-avisar' $cl @{ SonarRecetas = $rec; SonarNoAutomatizar = $no }
  $msgs = @('Refactor this method to reduce its Cognitive Complexity from 25 to the 15 allowed.', 'Replace this generic exception with a more specific one.', 'Mensaje-sin-receta-uno.', 'Mensaje-sin-receta-uno.', 'ENUM-PRUEBA: no tocar.')
  $incs = @()
  $lns = @{}
  for ($i = 0; $i -lt $cl.Count; $i++) {
    $nombre = ($cl[$i] -split '/')[1]
    $ruta = $RutaSv + $cl[$i] + '.java'
    $lns[$nombre] = Linea-De (Lee $e.Repo $ruta) 'int resultado'
    $incs += , (Inc 'CRITICAL' $msgs[$i] 'CODE_SMELL' ($nombre + '.java') $ruta ($lns[$nombre].ToString() + 'L'))
  }
  Informe-Sonar $e.Xlsx $incs
  $r = Sonar-Lanza $e @('-Modo', 'fix', '-Paso', 'sonar', '-Sonar', $e.Xlsx, '-Auto', '-Si', '-MaxIntentos', '1')
  Igual 'sale con 0' 0 $r.Codigo
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  $md = ''
  if (Test-Path -LiteralPath (Get-Ruta $e.Wt '.rescate/sonar-faltan.md')) { $md = Lee $e.Wt '.rescate/sonar-faltan.md' }
  $total = $RutaSv + 'service/TotalService.java'
  $recibo = $RutaSv + 'service/ReciboService.java'
  foreach ($donde in @(@{ N = 'la consola'; T = $r.Salida }, @{ N = 'sonar-faltan.md'; T = $md })) {
    $t = $donde.T
    $m = [regex]::Match($t, '(?s)Arregladas que cambian el resultado a proposito \(revisalas\):(.*?)(\r?\n\s*\r?\n|$)')
    Comprueba "$($donde.N): sale la seccion de arregladas a proposito" $m.Success $t
    if ($m.Success) {
      $s = $m.Groups[1].Value
      Comprueba "$($donde.N): lleva la que casa con la receta Avisar, con ruta:linea, mensaje y tipo/severidad" ($s.Contains("${total}:$($lns['TotalService']) - $($msgs[0]) [CODE_SMELL CRITICAL]")) $s
      Comprueba "$($donde.N): no lleva la de la receta sin Avisar ni las demas" (-not $s.Contains('ReciboService') -and -not $s.Contains('Mensaje-sin-receta')) $s
    }
    $m2 = [regex]::Match($t, '(?s)Mensajes sin receta ni exclusion \(para ampliar\)[^\r\n]*(.*?)(\r?\n\s*\r?\n|$)')
    Comprueba "$($donde.N): sale la seccion de mensajes sin receta" $m2.Success $t
    if ($m2.Success) {
      $s2 = $m2.Groups[1].Value
      Comprueba "$($donde.N): el mensaje sin receta sale contado (2 veces)" ($s2.Contains('2 x Mensaje-sin-receta-uno.')) $s2
      Comprueba "$($donde.N): no salen los que casan con receta ni con exclusion" (-not $s2.Contains('Cognitive') -and -not $s2.Contains('generic exception') -and -not $s2.Contains('ENUM-PRUEBA')) $s2
    }
  }
  Comprueba 'faltan 1 de Sonar (la no automatizable)' ($r.Salida -match 'Faltan 1 de Sonar') (Cola $r.Salida)
}

$Pruebas['m10 sonar: todo en ASCII (el script, el banco y los falsos)'] = {
  foreach ($f in @($Script, (Join-Path (Split-Path -Parent $Script) 'sonar-reglas.ps1'), (Join-Path $aqui 'probar.ps1'), (Join-Path $falsos 'copilot.ps1'))) {
    $malos = @([System.IO.File]::ReadAllBytes($f) | Where-Object { $_ -gt 127 }).Count
    Igual ('sin bytes fuera de ASCII en ' + (Split-Path $f -Leaf)) 0 $malos
  }
}

# ===== M21: EN SONAR EL MODELO SOLO COMPILA, Y CADA INTENTO DEJA SU TIEMPO APUNTADO =====
# Usan los falsos de M10 (Escenario-Sonar, copilot.ps1, m20a-mvn.ps1) y m21-copilot.ps1 (tarda y no toca nada). El Maven de mentira deja cada
# llamada en .rescate/mvn-llamadas.log; con RESCATE_MVN_ESPERA=<n>, cada llamada tarda n segundos mas.
$CabeceraIntentos = "fecha`tpaso`tlote`tintento`tficheros`thallazgos`treglas`tseg_copilot`tseg_maven`tresultado`tpuerta"
$MvnConTests = '\| -q -B -DskipTests=false -Dmaven\.test\.skip=false -Dmaven\.test\.failure\.ignore=false test$'

# Una incidencia (de Inc) de la clase $Clase, en la primera linea que lleva $Frag.
function Inc-M21($E, [string]$Clase, [string]$Msg, [string]$Frag = 'int resultado') {
  $ruta = $RutaSv + 'service/' + $Clase + '.java'
  return , (Inc 'CRITICAL' $Msg 'BUG' ($Clase + '.java') $ruta ((Linea-De (Lee $E.Repo $ruta) $Frag).ToString() + 'L'))
}

# Las llamadas de Maven con tests que ha hecho el script en el worktree.
function Mvn-Tests-M21($E) {
  return @([System.IO.File]::ReadAllLines((Get-Ruta $E.Wt '.rescate/mvn-llamadas.log')) | Where-Object { $_ -match $MvnConTests })
}

# .rescate/intentos.tsv del worktree: la cabecera, las lineas y cada fila con sus columnas (campo -> texto). $null si no existe.
function Intentos-M21($E) {
  $ruta = Get-Ruta $E.Wt '.rescate/intentos.tsv'
  if (-not (Test-Path -LiteralPath $ruta -PathType Leaf)) { return $null }
  $l = @([System.IO.File]::ReadAllLines($ruta))
  $cab = @($l[0] -split "`t")
  $filas = @()
  foreach ($x in @($l | Select-Object -Skip 1)) {
    $v = @($x -split "`t")
    $o = [ordered]@{ Campos = $v.Count }
    for ($k = 0; $k -lt $cab.Count; $k++) { $o[$cab[$k]] = $v[$k] }
    $filas += [pscustomobject]$o
  }
  return [pscustomobject]@{ Cabecera = $l[0]; Lineas = $l; Filas = $filas }
}

$Pruebas['m21 (a): en sonar el prompt manda solo compilar, y el script pasa los tests en sus puertas'] = {
  $e = Escenario-Sonar 'm21-a' @('service/TotalService')
  Informe-Sonar $e.Xlsx @(, (Inc-M21 $e 'TotalService' 'Fix this null dereference.'))
  $r = Sonar-Lanza $e @('-Modo', 'fix', '-Paso', 'sonar', '-Sonar', $e.Xlsx, '-Auto', '-Si', '-MaxIntentos', '1')
  Igual 'sale con 0' 0 $r.Codigo
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  $prompt = Lee $e.Wt '.rescate/prompt.md'
  Comprueba 'el prompt lleva la orden de compilar y dice que los tests los pasa el script' ($prompt -match '(?m)^- Ejecuta: .* -q -B -DskipTests test-compile  y corrige hasta que compile\. Los tests los pasa el script despues\.$') $prompt
  Comprueba 'y no lleva la orden de los tests' ($prompt -notmatch 'DskipTests=false' -and $prompt -notmatch 'corrige los tests que fallen') $prompt
  $t = @(Mvn-Tests-M21 $e)
  Comprueba 'el script ejecuta Maven con tests: el diagnostico y el intento' ($t.Count -ge 2) ($t -join ' // ')
  Comprueba 'el lote pasa y se guarda' ($r.Salida -match "Lote 1 OK: 'sonar' 1 -> 0") (Cola $r.Salida)
}

$Pruebas['m21 (a2): con -SinTests el script no pasa tests y el prompt de sonar sigue como antes: compilar, sin decir que los pasa el script'] = {
  $e = Escenario-Sonar 'm21-a2' @('service/TotalService')
  Informe-Sonar $e.Xlsx @(, (Inc-M21 $e 'TotalService' 'Fix this null dereference.'))
  $r = Sonar-Lanza $e @('-Modo', 'fix', '-Paso', 'sonar', '-Sonar', $e.Xlsx, '-Auto', '-Si', '-MaxIntentos', '1', '-SinTests')
  Igual 'sale con 0' 0 $r.Codigo
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  $prompt = Lee $e.Wt '.rescate/prompt.md'
  Comprueba 'el prompt compila y no habla de tests' ($prompt -match '(?m)^- Ejecuta: .* -q -B -DskipTests test-compile  y corrige hasta que compile\.$' -and $prompt -notmatch 'Los tests los pasa el script') $prompt
  Igual 'el script no ejecuta tests' 0 @(Mvn-Tests-M21 $e).Count
}

$Pruebas['m21 (b): el prompt de otro paso (calidad) sigue llevando los tests, y su intento tambien deja su linea con reglas -'] = {
  $e = Escenario-Sonar 'm21-b' @('service/TotalService') @{} @('service/SinDoc1', 'service/SinDoc2')
  $r = Sonar-Lanza $e @('-Modo', 'fix', '-Paso', 'calidad', '-Auto', '-Si', '-MaxIntentos', '1', '-MaxLotes', '1') 'nada'
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  $prompt = Lee $e.Wt '.rescate/prompt.md'
  Comprueba 'el prompt lleva la orden de los tests' ($prompt -match '(?m)^- Ejecuta: .* -q -B -DskipTests=false "-Dmaven\.test\.skip=false" "-Dmaven\.test\.failure\.ignore=false" test  y corrige los tests que fallen\.$') $prompt
  Comprueba 'y no dice que los tests los pasa el script' ($prompt -notmatch 'Los tests los pasa el script') $prompt
  $t = Intentos-M21 $e
  if (-not $t) { Comprueba 'existe .rescate/intentos.tsv' $false (Cola $r.Salida); return }
  Igual 'una sola linea de intento' 1 $t.Filas.Count
  Igual 'paso calidad' 'calidad' $t.Filas[0].paso
  Igual 'sin familias fuera de sonar: reglas -' '-' $t.Filas[0].reglas
  Igual 'no pasa (Copilot no cambio nada)' 'no pasa' $t.Filas[0].resultado
  Comprueba 'la consola cuenta los tiempos del paso calidad' ($r.Salida -match 'Tiempos del paso calidad: 1 intentos, Copilot [\d,]+ min, Maven [\d,]+ min \(detalle: \.rescate/intentos\.tsv\)') (Cola $r.Salida)
}

$Pruebas['m21 (c): dos lotes, uno que no pasa y otro que si: intentos.tsv con la cabecera y una linea por intento'] = {
  $e = Escenario-Sonar 'm21-c' @('service/TotalService', 'service/ReciboService')
  $incs = @((Inc-M21 $e 'TotalService' 'ATASCA: this one cannot be fixed.'), (Inc-M21 $e 'ReciboService' 'Fix this bug in ReciboService.'))
  Informe-Sonar $e.Xlsx $incs
  $r = Sonar-Lanza $e @('-Modo', 'fix', '-Paso', 'sonar', '-Sonar', $e.Xlsx, '-Auto', '-Si', '-MaxIntentos', '2', '-Lote', '1') 'sonar-atasca'
  Igual 'sale con 2 (hay un fichero atascado)' 2 $r.Codigo
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  $t = Intentos-M21 $e
  if (-not $t) { Comprueba 'existe .rescate/intentos.tsv' $false (Cola $r.Salida); return }
  Igual 'la cabecera, con las 11 columnas' $CabeceraIntentos $t.Cabecera
  Igual 'una linea por intento: 2 del lote 1 y 1 del lote 2' 3 $t.Filas.Count
  Igual 'todas con sus 11 campos' '11 11 11' ((@($t.Filas | ForEach-Object { $_.Campos })) -join ' ')
  Igual 'paso' 'sonar sonar sonar' ((@($t.Filas | ForEach-Object { $_.paso })) -join ' ')
  Igual 'lote' '1 1 2' ((@($t.Filas | ForEach-Object { $_.lote })) -join ' ')
  Igual 'intento' '1 2 1' ((@($t.Filas | ForEach-Object { $_.intento })) -join ' ')
  Igual 'resultado' 'no pasa|no pasa|pasa' ((@($t.Filas | ForEach-Object { $_.resultado })) -join '|')
  Igual 'ficheros y hallazgos del lote: 1 y 1' '1/1 1/1 1/1' ((@($t.Filas | ForEach-Object { $_.ficheros + '/' + $_.hallazgos })) -join ' ')
  Igual 'reglas: la familia de la incidencia del lote (sin receta, el mensaje)' 'ATASCA: this one cannot be fixed.|ATASCA: this one cannot be fixed.|Fix this bug in ReciboService.' ((@($t.Filas | ForEach-Object { $_.reglas })) -join '|')
  Comprueba 'la fecha es yyyy-MM-dd HH:mm:ss' (@($t.Filas | Where-Object { $_.fecha -notmatch '^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d$' }).Count -eq 0) ((@($t.Filas | ForEach-Object { $_.fecha })) -join ' / ')
  Comprueba 'los segundos de Copilot y de Maven son numeros' (@($t.Filas | Where-Object { $_.seg_copilot -notmatch '^\d+$' -or $_.seg_maven -notmatch '^\d+$' }).Count -eq 0) ((@($t.Filas | ForEach-Object { $_.seg_copilot + '/' + $_.seg_maven })) -join ' ')
  Igual 'puerta del que no pasa: la primera' 'No has cambiado ningun fichero.' $t.Filas[0].puerta
  Igual 'puerta del que pasa: vacia' '' $t.Filas[2].puerta
  Comprueba 'la consola cuenta los tiempos del paso: 3 intentos' ($r.Salida -match 'Tiempos del paso sonar: 3 intentos, Copilot [\d,]+ min, Maven [\d,]+ min \(detalle: \.rescate/intentos\.tsv\)') (Cola $r.Salida)
}

$Pruebas['m21 (c2): un intento que cambia el codigo pero no baja los hallazgos apunta su puerta, sin tabuladores ni saltos y cortada a 200'] = {
  $proh = @(@{ Rx = 'NOSONAR'; Modo = 'anadida'; Motivo = ("inicio`tcon tab`ny salto " + ('x' * 300)) })
  $e = Escenario-Sonar 'm21-c2' @('service/TotalService') @{ SonarProhibido = $proh }
  Informe-Sonar $e.Xlsx @(, (Inc-M21 $e 'TotalService' 'Fix this bug in TotalService.'))
  $r = Sonar-Lanza $e @('-Modo', 'fix', '-Paso', 'sonar', '-Sonar', $e.Xlsx, '-Auto', '-Si', '-MaxIntentos', '1', '-MaxLotes', '1') 'sonar-nosonar'
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  $t = Intentos-M21 $e
  if (-not $t) { Comprueba 'existe .rescate/intentos.tsv' $false (Cola $r.Salida); return }
  Igual 'una linea' 1 $t.Filas.Count
  Igual 'con sus 11 campos: ningun tabulador del motivo la parte' 11 $t.Filas[0].Campos
  Igual 'no pasa' 'no pasa' $t.Filas[0].resultado
  Igual 'la puerta mide 200' 200 $t.Filas[0].puerta.Length
  Comprueba 'y es el primer problema, con el tabulador y el salto cambiados por espacios' ($t.Filas[0].puerta.StartsWith('Cambio no permitido: inicio con tab y salto xxx')) $t.Filas[0].puerta
}

$Pruebas['m21 (c3): los segundos de Copilot suman la repeticion, y los de Maven son los del intento'] = {
  $e = Escenario-Sonar 'm21-c3' @('service/TotalService') @{ CopilotExe = (Join-Path $falsos 'm21-copilot.ps1') }
  Informe-Sonar $e.Xlsx @(, (Inc-M21 $e 'TotalService' 'Fix this bug in TotalService.'))
  $env:RESCATE_M21_ESPERA = '2'
  try { $r = Sonar-Lanza $e @('-Modo', 'fix', '-Paso', 'sonar', '-Sonar', $e.Xlsx, '-Auto', '-Si', '-MaxIntentos', '1', '-MaxLotes', '1') }
  finally { Remove-Item Env:\RESCATE_M21_ESPERA -ErrorAction SilentlyContinue }
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  Comprueba 'Copilot falla sin tocar nada y el script repite la llamada' ($r.Salida -match 'repito la llamada una vez') (Cola $r.Salida)
  $t = Intentos-M21 $e
  if (-not $t) { Comprueba 'existe .rescate/intentos.tsv' $false (Cola $r.Salida); return }
  Igual 'una linea' 1 $t.Filas.Count
  Comprueba 'seg_copilot: las dos llamadas de 2 s (la repeticion cuenta)' ([int]$t.Filas[0].seg_copilot -ge 4) "seg_copilot=$($t.Filas[0].seg_copilot)"
  Igual 'sin Maven en el intento (no cambio nada): seg_maven 0' '0' $t.Filas[0].seg_maven
  Igual 'no pasa' 'no pasa' $t.Filas[0].resultado
  Igual 'la puerta: no cambio nada' 'No has cambiado ningun fichero.' $t.Filas[0].puerta
}

$Pruebas['m21 (c4): seg_maven es lo que tardan los Maven del intento, sin el diagnostico de antes'] = {
  $e = Escenario-Sonar 'm21-c4' @('service/TotalService')
  Informe-Sonar $e.Xlsx @(, (Inc-M21 $e 'TotalService' 'Fix this null dereference.'))
  $env:RESCATE_MVN_ESPERA = '4'
  try { $r = Sonar-Lanza $e @('-Modo', 'fix', '-Paso', 'sonar', '-Sonar', $e.Xlsx, '-Auto', '-Si', '-MaxIntentos', '1') }
  finally { Remove-Item Env:\RESCATE_MVN_ESPERA -ErrorAction SilentlyContinue }
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  $t = Intentos-M21 $e
  if (-not $t) { Comprueba 'existe .rescate/intentos.tsv' $false (Cola $r.Salida); return }
  Igual 'una linea, y pasa' 'pasa' $t.Filas[0].resultado
  $s = [int]$t.Filas[0].seg_maven
  Comprueba 'un Maven de 4 s en el intento: entre 4 y 7 (el del diagnostico de antes no cuenta)' ($s -ge 4 -and $s -lt 8) "seg_maven=$s"
}

$Pruebas['m21 (d): relanzar anade lineas a intentos.tsv: ni borra las de antes ni repite la cabecera'] = {
  $e = Escenario-Sonar 'm21-d' @('service/TotalService', 'service/ReciboService')
  Informe-Sonar $e.Xlsx @((Inc-M21 $e 'TotalService' 'Fix this bug in TotalService.'), (Inc-M21 $e 'ReciboService' 'Fix this bug in ReciboService.'))
  $a = @('-Modo', 'fix', '-Paso', 'sonar', '-Sonar', $e.Xlsx, '-Auto', '-Si', '-MaxIntentos', '1', '-Lote', '1', '-MaxLotes', '1')
  $r1 = Sonar-Lanza $e $a
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r1.Salida); return }
  $t1 = Intentos-M21 $e
  if (-not $t1) { Comprueba 'existe .rescate/intentos.tsv' $false (Cola $r1.Salida); return }
  Igual 'tras la primera pasada: cabecera y una linea' 2 $t1.Lineas.Count
  $r2 = Sonar-Lanza $e $a
  $t2 = Intentos-M21 $e
  Igual 'tras la segunda: cabecera y dos lineas' 3 $t2.Lineas.Count
  Igual 'la linea de antes sigue igual' $t1.Lineas[1] $t2.Lineas[1]
  Igual 'la cabecera esta una sola vez' 1 @($t2.Lineas | Where-Object { $_ -eq $CabeceraIntentos }).Count
  Igual 'las dos lineas son pasa' 'pasa pasa' ((@($t2.Filas | ForEach-Object { $_.resultado })) -join ' ')
  Comprueba 'la segunda pasada cuenta solo sus tiempos: 1 intentos' ($r2.Salida -match 'Tiempos del paso sonar: 1 intentos,') (Cola $r2.Salida)
}

$Pruebas['m21 (e): sonar-por-familia.tsv cuenta por familia (dos con receta y una sin ella) y la consola ensena la tabla'] = {
  $rec = @(
    @{ Nombre = 'complejidad'; Rx = 'cognitive complexity'; Texto = 'RECETA-M21-UNO' },
    @{ Rx = 'remove this unused'; Texto = 'RECETA-M21-DOS' })
  $e = Escenario-Sonar 'm21-e' @('service/TotalService', 'service/ReciboService', 'service/PagoService') @{ SonarRecetas = $rec }
  $incs = @(
    (Inc-M21 $e 'TotalService' 'Refactor this method to reduce its Cognitive Complexity from 25 to the 15 allowed.'),
    (Inc-M21 $e 'ReciboService' 'Refactor this method to reduce its Cognitive Complexity from 18 to the 15 allowed.'),
    (Inc-M21 $e 'PagoService' 'Refactor this method to reduce its Cognitive Complexity from 40 to the 15 allowed.'),
    (Inc-M21 $e 'ReciboService' 'Remove this unused private "total" field.' 'return resultado'),
    (Inc-M21 $e 'PagoService' 'Remove this unused private "saldo" field.' 'return resultado'),
    (Inc-M21 $e 'TotalService' 'Define a constant instead of duplicating this literal "abc" 3 times.' 'return resultado'))
  Informe-Sonar $e.Xlsx $incs
  $r = Sonar-Lanza $e @('-Modo', 'fix', '-Paso', 'sonar', '-Sonar', $e.Xlsx, '-Auto', '-Si', '-MaxIntentos', '1', '-MaxLotes', '0')
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  $ruta = Get-Ruta $e.Wt '.rescate/sonar-por-familia.tsv'
  if (-not (Test-Path -LiteralPath $ruta -PathType Leaf)) { Comprueba 'existe .rescate/sonar-por-familia.tsv' $false (Cola $r.Salida); return }
  $l = @([System.IO.File]::ReadAllLines($ruta))
  Igual 'la cabecera' "familia`tincidencias`tficheros`treceta" $l[0]
  Igual 'tres familias' 4 $l.Count
  Igual 'la de la receta con nombre: 3 incidencias en 3 ficheros' "complejidad`t3`t3`tsi" $l[1]
  Igual 'la receta sin nombre es receta-N, con N su lugar en SonarRecetas: 2 en 2' "receta-2`t2`t2`tsi" $l[2]
  Igual 'la que no tiene receta: el mensaje con las comillas y las cifras en #' "Define a constant instead of duplicating this literal # # times.`t1`t1`tno" $l[3]
  Comprueba 'la consola ensena la tabla: la primera familia' ($r.Salida -match '(?m)^\s*3\s+3\s+si\s+complejidad\s*$') (Cola $r.Salida)
  Comprueba 'la segunda' ($r.Salida -match '(?m)^\s*2\s+2\s+si\s+receta-2\s*$') (Cola $r.Salida)
  Comprueba 'la tercera' ($r.Salida -match '(?m)^\s*1\s+1\s+no\s+Define a constant instead of duplicating this literal # # times\.\s*$') (Cola $r.Salida)
  Comprueba 'y una linea con el total y la ruta del fichero' ($r.Salida -match 'Total: 6 incidencias en 3 familias \(detalle: \.rescate/sonar-por-familia\.tsv\)') (Cola $r.Salida)
}

$Pruebas['m21 (e2): la consola ensena las 10 primeras familias y el fichero las lleva todas, de mas a menos'] = {
  $nombres = @('alpha', 'beta', 'gamma', 'delta', 'epsilon', 'zeta', 'eta', 'theta', 'iota', 'kappa', 'lambda', 'mu')
  $e = Escenario-Sonar 'm21-e2' @('service/TotalService')
  $incs = @()
  foreach ($n in $nombres) { $incs += , (Inc 'CRITICAL' "Do the $n thing." 'BUG' 'TotalService.java' ($RutaSv + 'service/TotalService.java') '') }
  $incs += , (Inc 'CRITICAL' 'Do the mu thing.' 'BUG' 'TotalService.java' ($RutaSv + 'service/TotalService.java') '')
  Informe-Sonar $e.Xlsx $incs
  $r = Sonar-Lanza $e @('-Modo', 'fix', '-Paso', 'sonar', '-Sonar', $e.Xlsx, '-Auto', '-Si', '-MaxIntentos', '1', '-MaxLotes', '0')
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  $ruta = Get-Ruta $e.Wt '.rescate/sonar-por-familia.tsv'
  if (-not (Test-Path -LiteralPath $ruta -PathType Leaf)) { Comprueba 'existe .rescate/sonar-por-familia.tsv' $false (Cola $r.Salida); return }
  $l = @([System.IO.File]::ReadAllLines($ruta))
  Igual 'el fichero: la cabecera y las 12 familias' 13 $l.Count
  Igual 'la primera es la que mas incidencias lleva (mu, 2)' "Do the mu thing.`t2`t1`tno" $l[1]
  Igual 'la consola ensena 10 familias' 10 @($r.Salida -split "`n" | Where-Object { $_ -match '^\s*\d+\s+\d+\s+no\s+Do the ' }).Count
  Comprueba 'y el total: 13 incidencias en 12 familias' ($r.Salida -match 'Total: 13 incidencias en 12 familias \(detalle: \.rescate/sonar-por-familia\.tsv\)') (Cola $r.Salida)
}

$Pruebas['m21 (f): si intentos.tsv no se puede escribir (es una carpeta) sale un aviso y el lote sigue'] = {
  $e = Escenario-Sonar 'm21-f' @('service/TotalService')
  $total = $RutaSv + 'service/TotalService.java'
  Informe-Sonar $e.Xlsx @(, (Inc-M21 $e 'TotalService' 'Fix this null dereference.'))
  [void](New-Item -ItemType Directory -Path (Get-Ruta $e.Repo '.rescate/intentos.tsv') -Force)
  $r = Sonar-Lanza $e @('-Modo', 'fix', '-Paso', 'sonar', '-Sonar', $e.Xlsx, '-Auto', '-Si', '-MaxIntentos', '1', '-SinWorktree')
  Igual 'sale con 0' 0 $r.Codigo
  Comprueba 'un aviso dice que no ha podido apuntar el intento' ($r.Salida -match 'No he podido apuntar el intento en .*intentos\.tsv') (Cola $r.Salida)
  Comprueba 'el lote sigue y pasa' ($r.Salida -match "Lote 1 OK: 'sonar' 1 -> 0") (Cola $r.Salida)
  Comprueba 'hay un commit del lote' ((GitEn $e.Repo @('log', '--format=%s')) -match 'rescate\(sonar\): lote 1, hallazgos 1 a 0') (GitEn $e.Repo @('log', '--format=%s'))
  Comprueba 'la linea marcada ha cambiado' ((Lee $e.Repo $total) -match 'int resultado = a \+ b \+ 0;')
  Comprueba 'intentos.tsv sigue siendo una carpeta' (Test-Path -LiteralPath (Get-Ruta $e.Repo '.rescate/intentos.tsv') -PathType Container)
}

$Pruebas['m21: todo en ASCII (el falso nuevo)'] = {
  $f = Join-Path $falsos 'm21-copilot.ps1'
  Igual 'sin bytes fuera de ASCII en m21-copilot.ps1' 0 @([System.IO.File]::ReadAllBytes($f) | Where-Object { $_ -gt 127 }).Count
}

# ================================ M14: PASO COBERTURA ================================
# El paso 'cobertura' (-Cobertura) escribe tests hasta que la cobertura de lineas llega al objetivo. Los falsos son cobertura-mvn.ps1 y
# cobertura-copilot.ps1: la cobertura de una clase sale de marcadores (un '// LINEAS: n' en su fuente y los '// CUBRE: n' de su test).
$CabJacoco = 'GROUP,PACKAGE,CLASS,INSTRUCTION_MISSED,INSTRUCTION_COVERED,BRANCH_MISSED,BRANCH_COVERED,LINE_MISSED,LINE_COVERED,COMPLEXITY_MISSED,COMPLEXITY_COVERED,METHOD_MISSED,METHOD_COVERED'

# Una fila de jacoco.csv como la de JaCoCo: paquete, clase, lineas sin cubrir y cubiertas (lo demas, de relleno).
function Fila-Jacoco([string]$Paquete, [string]$Clase, [int]$Faltan, [int]$Cubiertas) {
  return "batch,$Paquete,$Clase,$($Faltan * 3),$($Cubiertas * 3),2,1,$Faltan,$Cubiertas,3,1,1,1"
}

$Pruebas['m14 cobertura: Get-Cobertura con un jacoco.csv de 3 clases devuelve clases con sus lineas y la ruta del fichero; el total no cambia'] = {
  $raiz = Join-Path $Dir 'm14-clases'
  if (Test-Path -LiteralPath $raiz) { Remove-Item -LiteralPath $raiz -Recurse -Force }
  Escribe $raiz 'src/main/java/com/acme/batch/service/TotalService.java' "package com.acme.batch.service;`npublic class TotalService {}`n"
  Escribe $raiz 'src/main/java/com/acme/batch/service/ReciboService.java' "package com.acme.batch.service;`npublic class ReciboService {}`n"
  $csv = Join-Path $Dir 'm14-clases.csv'
  [System.IO.File]::WriteAllText($csv, (@($CabJacoco, (Fila-Jacoco 'com.acme.batch.service' 'TotalService' 8 2), (Fila-Jacoco 'com.acme.batch.service' 'ReciboService' 0 10), (Fila-Jacoco 'com.acme.batch.config' 'AppConfig' 3 0)) -join "`n") + "`n")
  $f = Join-Path $Dir 'm14-clases.ps1'
  [System.IO.File]::WriteAllText($f, @'
param([string]$Sis, [string]$Mvn, [string]$Carpeta, [string]$Registro)
. (Join-Path $Sis 'comun.ps1')
$Cfg.MvnExe = $Mvn
$Cfg.SegundosLatido = 0
$o = Get-Cobertura $Carpeta $Registro $true $true
$sin = Get-Cobertura $Carpeta $Registro $true
'CAMPOS ' + (@($sin.Keys) -join ' ')
ConvertTo-Json -InputObject $o -Depth 6 -Compress
'@)
  $env:RESCATE_JACOCO_CSV = $csv
  try { $r = Lanzar $f @((Split-Path -Parent $Script), (Join-Path $falsos 'mvn.ps1'), $raiz, (Join-Path $Dir 'm14-clases.log')) }
  finally { $env:RESCATE_JACOCO_CSV = '' }
  $o = $null
  $lineas = @($r.Salida -split "`r?`n")
  try { $o = $lineas[-1] | ConvertFrom-Json } catch { }
  if (-not $o) { Comprueba 'la salida es un JSON' $false (Cola $r.Salida); return }
  Igual 'sin pedir las clases, los campos son los de siempre' 'CAMPOS medida porcentaje cubiertas total minima motivo' (@($lineas | Where-Object { $_ -match '^CAMPOS ' })[0])
  Comprueba 'medida' ($o.medida -eq $true) (Cola $r.Salida)
  Igual 'el total sigue igual: 12 cubiertas' 12 $o.cubiertas
  Igual 'el total sigue igual: 23 lineas' 23 $o.total
  Igual 'el total sigue igual: 52,2 %' 52.2 $o.porcentaje
  Igual 'la minima sigue en 80' 80 $o.minima
  $c = @($o.clases)
  Igual 'hay 3 clases, una por fila del csv' 3 $c.Count
  Igual 'la primera clase lleva paquete y nombre' 'com.acme.batch.service.TotalService' $c[0].Clase
  Igual 'su fichero es la ruta relativa del .java' 'src/main/java/com/acme/batch/service/TotalService.java' $c[0].Fichero
  Igual 'faltan 8' 8 $c[0].Faltan
  Igual 'y 2 cubiertas' 2 $c[0].Cubiertas
  Igual 'la segunda esta entera cubierta' '0/10' ("$($c[1].Faltan)/$($c[1].Cubiertas)")
  Igual 'la tercera no tiene .java en el repo: su fichero va vacio' '' "$($c[2].Fichero)"
  Igual 'y sus numeros salen igual' '3/0' ("$($c[2].Faltan)/$($c[2].Cubiertas)")
}

# Ajustes de un repo de cobertura: Maven y Copilot de mentira, mas lo de $Mas.
function Config-Cob($E, [hashtable]$Mas = @{}) {
  $cfg = [ordered]@{ CopilotExe = (Join-Path $falsos 'cobertura-copilot.ps1'); MvnExe = (Join-Path $falsos 'm20a-cobertura-mvn.ps1'); Reflexionar = $false }
  foreach ($k in $Mas.Keys) { $cfg[$k] = $Mas[$k] }
  Escribe $E.Repo '.rescate/config.json' (ConvertTo-Json -InputObject $cfg -Depth 6)
}

# Una clase de servicio con su marcador '// LINEAS: n' (las lineas medibles que lee el Maven falso) y Javadoc.
function Servicio-Cob([string]$Sub, [string]$Clase, [int]$Lineas) {
  return @"
package com.acme.plantillabatch.$Sub;

/** Servicio $Clase. */
public class $Clase {
    // LINEAS: $Lineas

    /**
     * Suma dos numeros.
     *
     * @param a primero
     * @param b segundo
     * @return la suma
     */
    public int suma(int a, int b) {
        return a + b;
    }
}
"@
}

# Su test de partida: cubre $Cubre de sus lineas (el marcador '// CUBRE: n' que lee el Maven falso).
function Test-Cob([string]$Sub, [string]$Clase, [int]$Cubre) {
  return @"
package com.acme.plantillabatch.$Sub;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

class ${Clase}Test {

    @Test
    void sumaBase() {
        assertEquals(3, new $Clase().suma(1, 2));
        // CUBRE: $Cubre
    }
}
"@
}

# Un repo Java con Maven y los dos falsos de cobertura. $Clases: 'subpaquete/Clase', lineas y cubiertas al empezar (sin test si 0). Con
# $ConApp lleva la clase @SpringBootApplication (2 lineas sin cubrir). $Extra: ruta del repo (con /) -> texto.
function Escenario-Cob([string]$Nombre, $Clases, [hashtable]$Mas = @{}, [hashtable]$Extra = @{}, [bool]$ConApp = $true) {
  $raiz = Join-Path $Dir $Nombre
  if (Test-Path -LiteralPath $raiz) { Remove-Item -LiteralPath $raiz -Recurse -Force }
  $repo = Join-Path $raiz 'batch'
  Escribe $repo 'pom.xml' $Pom
  if ($ConApp) { Escribe $repo ($RutaSv + 'PlantillaBatchApplication.java') ($AppSonar.Replace('public class PlantillaBatchApplication {', "public class PlantillaBatchApplication {`n    // LINEAS: 2")) }
  foreach ($c in $Clases) {
    $p = ([string]$c[0]) -split '/'
    Escribe $repo ($RutaSv + $p[0] + '/' + $p[1] + '.java') (Servicio-Cob $p[0] $p[1] ([int]$c[1]))
    if ([int]$c[2] -gt 0) { Escribe $repo ('src/test/java/com/acme/plantillabatch/' + $p[0] + '/' + $p[1] + 'Test.java') (Test-Cob $p[0] $p[1] ([int]$c[2])) }
  }
  foreach ($k in $Extra.Keys) { Escribe $repo $k.TrimStart('/') $Extra[$k] }
  Inicia-Repo $repo
  $e = [pscustomobject]@{ Raiz = $raiz; Repo = $repo; Wt = ($repo + '-rescate') }
  Config-Cob $e $Mas
  return $e
}

function Hallazgos-Cob([string]$Raiz, [string]$Sev = '') {
  return @(Hallazgos $Raiz | Where-Object { $_.Cat -eq 'cobertura' -and ((-not $Sev) -or $_.Sev -eq $Sev) })
}

# Un repo de clases con distinta cobertura y las que el paso no propone: un record sin metodos, y config, dto y model. 68 lineas, 26 cubiertas (38,2 %).
function Escenario-Cob-Varias([string]$Nombre, [hashtable]$Mas = @{}) {
  $record = @{
    '/src/main/java/com/acme/plantillabatch/service/Importe.java' = "package com.acme.plantillabatch.service;`n`n/** Un importe. */`npublic record Importe(int valor) {`n    // LINEAS: 6`n`n    /**`n     * Dobla el valor.`n     *`n     * @return el doble`n     */`n    public int doble() {`n        return valor * 2;`n    }`n}`n"
    '/src/main/java/com/acme/plantillabatch/service/Cantidad.java' = "package com.acme.plantillabatch.service;`n`n/** Una cantidad. */`npublic record Cantidad(int unidades) {`n    // LINEAS: 4`n}`n"
  }
  $cl = @(, @('service/AltaService', 10, 2)) + @(, @('service/BajaService', 10, 9)) + @(, @('service/CobroService', 10, 5)) + @(, @('service/PagoService', 10, 10)) +
    @(, @('config/AjusteConfig', 10, 0)) + @(, @('dto/ClienteDto', 3, 0)) + @(, @('model/Cliente', 3, 0))
  return (Escenario-Cob $Nombre $cl $Mas $record)
}

$Pruebas['m14 cobertura: el diagnostico sin -Cobertura no cambia: ni fila, ni hallazgos, ni Maven de JaCoCo; -Paso cobertura sin -Cobertura se rechaza'] = {
  $e = Escenario-Cob-Varias 'm14-sin'
  $r = Lanzar $Script @('-Repo', $e.Repo, '-Modo', 'diagnostico')
  Igual 'el diagnostico sale con 0' 0 $r.Codigo
  Igual 'ningun hallazgo de cobertura' 0 (Hallazgos-Cob $e.Repo).Count
  Comprueba 'la tabla no tiene la fila cobertura' ($r.Salida -notmatch '(?m)^cobertura\s') (Cola $r.Salida)
  Comprueba 'el diagnostico.md tampoco' ((Lee $e.Repo '.rescate/diagnostico.md') -notmatch '\| cobertura \|')
  $ll = ''
  if (Test-Path -LiteralPath (Get-Ruta $e.Repo '.rescate/cobertura-mvn.log')) { $ll = Lee $e.Repo '.rescate/cobertura-mvn.log' }
  Comprueba 'Maven se lanza sin JaCoCo' ($ll -notmatch 'jacoco') $ll
  $r2 = Lanzar $Script @('-Repo', $e.Repo, '-Modo', 'fix', '-Paso', 'cobertura', '-Auto', '-Si')
  Igual 'con -Paso cobertura sin -Cobertura sale con 1' 1 $r2.Codigo
  Comprueba 'y dice que el paso necesita -Cobertura' ($r2.Salida -match "El paso 'cobertura' necesita -Cobertura") (Cola $r2.Salida)
}

$Pruebas['m14 cobertura: diagnostico - por encima del objetivo ningun hallazgo; por debajo, uno por clase con lineas sin cubrir, de mas a menos, sin las excluidas'] = {
  $e = Escenario-Cob-Varias 'm14-diag' @{ CoberturaMinima = 80 }
  $r = Lanzar $Script @('-Repo', $e.Repo, '-Modo', 'diagnostico', '-Cobertura')
  Igual 'sale con 0' 0 $r.Codigo
  $h = @(Hallazgos-Cob $e.Repo)
  Igual 'hay 4 hallazgos: AltaService, Importe, CobroService y BajaService' 4 $h.Count
  Igual 'todos son errores' 4 (Hallazgos-Cob $e.Repo 'error').Count
  Igual 'ordenados por lo que falta' 'AltaService Importe CobroService BajaService' ((@($h | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Fichero) })) -join ' ')
  Igual 'el fichero es la ruta del .java' ($RutaSv + 'service/AltaService.java') $h[0].Fichero
  Igual 'AltaService: 2/10 lineas (20 %)' '2/10 lineas (20 %)' $h[0].Detalle
  Igual 'Importe: 0/6 lineas (0 %)' '0/6 lineas (0 %)' $h[1].Detalle
  Igual 'CobroService: 5/10 lineas (50 %)' '5/10 lineas (50 %)' $h[2].Detalle
  Igual 'BajaService: 9/10 lineas (90 %)' '9/10 lineas (90 %)' $h[3].Detalle
  Comprueba 'la tabla lleva la fila cobertura con 4 errores' ($r.Salida -match '(?m)^cobertura\s+4\s') (Cola $r.Salida)
  Comprueba 'Maven midio con JaCoCo una sola vez' ((@([System.IO.File]::ReadAllLines((Get-Ruta $e.Repo '.rescate/cobertura-mvn.log')) | Where-Object { $_ -match 'jacoco' })).Count -eq 1)
  # por encima del objetivo: 38,2 % con un objetivo de 38
  Config-Cob $e @{ CoberturaMinima = 38 }
  $r2 = Lanzar $Script @('-Repo', $e.Repo, '-Modo', 'diagnostico', '-Cobertura')
  Igual 'con el objetivo alcanzado sale con 0' 0 $r2.Codigo
  Igual 'ningun hallazgo, ni aviso' 0 (Hallazgos-Cob $e.Repo).Count
  # una clase interna cuenta en el fichero de la externa: un solo hallazgo, con las lineas de las dos
  Config-Cob $e @{ CoberturaMinima = 80 }
  $csv = Join-Path $e.Raiz 'interna.csv'
  [System.IO.File]::WriteAllText($csv, (@($CabJacoco, (Fila-Jacoco 'com.acme.plantillabatch.service' 'AltaService' 6 2), (Fila-Jacoco 'com.acme.plantillabatch.service' 'AltaService$Linea' 2 0)) -join "`n") + "`n")
  $env:RESCATE_JACOCO_CSV = $csv
  try { $r3 = Lanzar $Script @('-Repo', $e.Repo, '-Modo', 'diagnostico', '-Cobertura') }
  finally { $env:RESCATE_JACOCO_CSV = '' }
  $h3 = @(Hallazgos-Cob $e.Repo)
  Igual 'la clase interna no hace otro hallazgo' 1 $h3.Count
  Igual 'y suma sus lineas a las de la externa' '2/10 lineas (20 %)' $h3[0].Detalle
}

$Pruebas['m14 cobertura: sin poder medir (Maven falla) no hay hallazgos de error: un aviso con el motivo'] = {
  $e = Escenario-Cob-Varias 'm14-sinmedida'
  $r = Lanzar $Script @('-Repo', $e.Repo, '-Modo', 'diagnostico', '-Cobertura') 'cob-mvn-error:no hay jacoco en este equipo'
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'ningun error de cobertura' 0 (Hallazgos-Cob $e.Repo 'error').Count
  $a = @(Hallazgos-Cob $e.Repo 'aviso')
  Igual 'un aviso' 1 $a.Count
  Comprueba 'que dice que no se ha podido medir y por que' ($a.Count -eq 1 -and $a[0].Detalle -match 'no se ha podido medir la cobertura' -and $a[0].Detalle -match 'no hay jacoco en este equipo') ($a | ForEach-Object { $_.Detalle })
}

# Tres clases de 10 lineas con 0, 2 y 5 cubiertas (7 de 30, 23,3 %); sin la clase de arranque. Con el objetivo en 80 bastan dos lotes: Alta y Baja.
function Escenario-Cob-Tres([string]$Nombre, [hashtable]$Mas = @{}, [hashtable]$Extra = @{}) {
  $cl = @(, @('service/AltaService', 10, 0)) + @(, @('service/BajaService', 10, 2)) + @(, @('service/CobroService', 10, 5))
  return (Escenario-Cob $Nombre $cl $Mas $Extra $false)
}

# Una sola clase de 10 lineas sin cubrir.
function Escenario-Cob-Una([string]$Nombre, [hashtable]$Mas = @{}) {
  return (Escenario-Cob $Nombre @(, @('service/AltaService', 10, 0)) $Mas @{} $false)
}

# El fix del paso cobertura, con un intento por lote, en el repo del escenario.
function Cob-Fix($E, [string]$Guion = '', [string[]]$Mas = @()) {
  return (Lanzar $Script (@('-Repo', $E.Repo, '-Modo', 'fix', '-Paso', 'cobertura', '-Cobertura', '-Auto', '-Si', '-MaxIntentos', '1') + $Mas) $Guion)
}

$Pruebas['m14 cobertura: solo -Repo y -Cobertura arregla sin preguntar, en el worktree, con un commit por lote y pasando 3 veces los tests de cada clase'] = {
  $e = Escenario-Cob-Tres 'm14-corto'
  $r = Lanzar $Script @('-Repo', $e.Repo, '-Cobertura') '' @('s')
  Igual 'sale con 0' 0 $r.Codigo
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  Comprueba 'va directo al paso cobertura, una clase por lote' ($r.Salida -match "=== Paso 'cobertura' en lotes de 1 ===") (Cola $r.Salida)
  Comprueba 'primer lote: AltaService, la que mas falta' ($r.Salida -match 'Lote 1 OK' -and $r.Salida -match 'service/AltaService\.java') (Cola $r.Salida)
  Comprueba 'segundo lote OK' ($r.Salida -match 'Lote 2 OK') (Cola $r.Salida)
  Comprueba 'no pregunta entre lotes' ($r.Salida -notmatch 'siguiente lote') (Cola $r.Salida)
  Comprueba 'sin plantilla no hay aviso de que el arreglo va a ciegas' ($r.Salida -notmatch 'a ciegas') (Cola $r.Salida)
  $log = GitEn $e.Wt @('log', '--format=%s')
  Comprueba 'hay un commit por lote' ($log -match 'rescate\(cobertura\): lote 1' -and $log -match 'rescate\(cobertura\): lote 2') $log
  Comprueba 'los tests nuevos estan en el worktree' ((Test-Path -LiteralPath (Get-Ruta $e.Wt ($RutaSv.Replace('main', 'test') + 'service/AltaServiceTest.java'))) -and (Test-Path -LiteralPath (Get-Ruta $e.Wt ($RutaSv.Replace('main', 'test') + 'service/BajaServiceTest.java'))))
  Igual 'el repo del usuario sigue como estaba' '' (GitEn $e.Repo @('status', '--porcelain'))
  Igual 'el worktree queda limpio' '' (GitEn $e.Wt @('status', '--porcelain'))
  $rep = @([System.IO.File]::ReadAllLines((Get-Ruta $e.Wt '.rescate/cobertura-rep.log')))
  Igual 'los tests de cada clase se repiten 3 veces (6 en dos lotes)' 6 $rep.Count
  Comprueba 'con -Dtest=<Clase>Test' (@($rep | Where-Object { $_ -eq '-Dtest=AltaServiceTest' }).Count -eq 3 -and @($rep | Where-Object { $_ -eq '-Dtest=BajaServiceTest' }).Count -eq 3) ($rep -join ' ')
  $prompt = Lee $e.Wt '.rescate/prompt.md'
  Comprueba 'el prompt es el de cobertura' ($prompt.StartsWith("# Tarea de cobertura: paso 'cobertura'")) $prompt
}

$Pruebas['m14 cobertura: el prompt lleva la clase entera, su test, lo que falta segun JaCoCo y la regla de solo src/test, sin dependencias nuevas'] = {
  $e = Escenario-Cob-Tres 'm14-prompt'
  $r = Cob-Fix $e '' @('-Lote', '1')
  Igual 'sale con 0' 0 $r.Codigo
  # el prompt del primer lote se machaca con el del segundo: se mira el del ultimo (BajaService, que ya tenia test)
  $prompt = Lee $e.Wt '.rescate/prompt.md'
  $baja = $RutaSv + 'service/BajaService.java'
  Comprueba 'nombra la clase con sus lineas' ($prompt.Contains("- $baja - 2/10 lineas (20 %)")) $prompt
  Comprueba 'lleva la clase entera' ($prompt.Contains('public class BajaService {') -and $prompt.Contains('// LINEAS: 10')) $prompt
  Comprueba 'y su test, que ya existia' ($prompt.Contains('class BajaServiceTest {')) $prompt
  Comprueba 'y las lineas que JaCoCo da como no cubiertas (3-10)' ($prompt -match 'Lineas que JaCoCo da como no cubiertas: 3-10') $prompt
  Comprueba 'pide escribir src/test/java/<mismo paquete>/<Clase>Test.java' ($prompt.Contains('src/test/java/<mismo paquete>/<Clase>Test.java')) $prompt
  Comprueba 'solo ficheros bajo src/test' ($prompt -match 'Solo creas o cambias ficheros bajo src/test/') $prompt
  Comprueba 'sin dependencias nuevas' ($prompt -match 'No anadas dependencias') $prompt
  Comprueba 'y el comentario OJO para lo que parezca un error' ($prompt.Contains('// OJO: parece un error: <motivo>')) $prompt
  Comprueba 'el texto es ASCII' (@([System.Text.Encoding]::UTF8.GetBytes($prompt) | Where-Object { $_ -gt 127 }).Count -eq 0)
}

$Pruebas['m14 cobertura: P1 - un intento que toca src/main o el pom no vale, y el motivo lo dice; sin Maven'] = {
  foreach ($caso in @(@{ N = 'main'; G = 'cob-toca-main'; Frag = 'src/main/java/com/acme/plantillabatch/service/AltaService.java' }, @{ N = 'pom'; G = 'cob-toca-pom'; Frag = 'pom.xml' })) {
    $e = Escenario-Cob-Una ('m14-p1-' + $caso.N)
    $r = Cob-Fix $e $caso.G
    Igual "$($caso.N): sale con 2" 2 $r.Codigo
    if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
    Comprueba "$($caso.N): NO PASA con el fichero tocado y la regla de src/test" ($r.Salida -match 'NO PASA: Has tocado ficheros que no son de src/test/' -and $r.Salida.Contains($caso.Frag)) (Cola $r.Salida)
    Comprueba "$($caso.N): sin Maven" ($r.Salida -match 'Sin Maven: el intento ya incumple las reglas del paso') (Cola $r.Salida)
    Comprueba "$($caso.N): el lote se deshace y la clase queda atascada" ($r.Salida -match 'Lote 1 DESHECHO' -and $r.Salida -match "ATASCADO en 'cobertura'") (Cola $r.Salida)
    Igual "$($caso.N): no hay commits nuevos" 'inicial' (GitEn $e.Wt @('log', '--format=%s'))
    Igual "$($caso.N): el worktree queda limpio" '' (GitEn $e.Wt @('status', '--porcelain'))
    Comprueba "$($caso.N): el final dice que faltan esas clases" ($r.Salida -match 'Faltan estas clases' -and $r.Salida -match 'atascada') (Cola $r.Salida)
  }
}

$Pruebas['m14 cobertura: P2 - un test que falla 1 vez de cada 3 hace inestable el lote: no vale y el motivo lo dice'] = {
  $e = Escenario-Cob-Una 'm14-p2'
  $r = Cob-Fix $e 'cob-inestable'
  Igual 'sale con 2' 2 $r.Codigo
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  Comprueba 'NO PASA: inestables, en la repeticion 2 de 3' ($r.Salida -match 'NO PASA: Los tests de AltaService son inestables' -and $r.Salida -match 'repeticion 2 de 3') (Cola $r.Salida)
  Comprueba 'el lote se deshace' ($r.Salida -match 'Lote 1 DESHECHO') (Cola $r.Salida)
  Igual 'no hay commits nuevos' 'inicial' (GitEn $e.Wt @('log', '--format=%s'))
  Igual 'se repitio hasta el primer fallo: 2 veces' 2 @([System.IO.File]::ReadAllLines((Get-Ruta $e.Wt '.rescate/cobertura-rep.log'))).Count
}

$Pruebas['m14 cobertura: P3 - un test que no sube la cobertura de la clase no vale; ni el que baja el total'] = {
  $e = Escenario-Cob-Una 'm14-p3'
  $r = Cob-Fix $e 'cob-no-sube'
  Igual 'sale con 2' 2 $r.Codigo
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  Comprueba 'NO PASA: la cobertura de AltaService no sube (0/10 -> 0/10)' ($r.Salida -match 'NO PASA: La cobertura de AltaService no sube \(0/10 -> 0/10 lineas\)') (Cola $r.Salida)
  Comprueba 'el lote se deshace' ($r.Salida -match 'Lote 1 DESHECHO') (Cola $r.Salida)
  Igual 'no hay commits nuevos' 'inicial' (GitEn $e.Wt @('log', '--format=%s'))
  # sube la clase (0 -> 2 lineas) pero un test de otra pierde 5 cubiertas: el total baja
  $e2 = Escenario-Cob 'm14-p3-total' @(@('service/AltaService', 10, 0), @('service/BajaService', 10, 5)) @{} @{} $false
  $r2 = Cob-Fix $e2 'cob-rompe-otra:AltaService'
  Igual 'con el total a la baja sale con 2' 2 $r2.Codigo
  Comprueba 'NO PASA: el total baja de 5 a 2 lineas cubiertas' ($r2.Salida -match 'NO PASA: La cobertura total baja \(5 -> 2 lineas cubiertas\)') (Cola $r2.Salida)
  Comprueba 'y la clase si subia: no hay NO PASA de AltaService' ($r2.Salida -notmatch 'AltaService no sube') (Cola $r2.Salida)
}

$Pruebas['m14 cobertura: P4 - sin aserciones, assertTrue(true), @Disabled, Thread.sleep o un catch vacio: el lote no vale y el motivo lo dice'] = {
  $casos = @(
    @{ G = 'cob-sin-asercion'; Rx = 'cubre1 .* no tiene ninguna asercion \(assert\*, verify'; NoRx = 'asercion de verdad' },
    @{ G = 'cob-assert-true'; Rx = 'cubre1 .* no tiene ninguna asercion de verdad: assertTrue\(true\)'; NoRx = 'ninguna asercion \(assert' },
    @{ G = 'cob-disabled'; Rx = 'has anadido un test desactivado' },
    @{ G = 'cob-sleep'; Rx = 'has anadido Thread\.sleep' },
    @{ G = 'cob-catch-vacio'; Rx = 'has anadido un catch vacio' })
  foreach ($c in $casos) {
    $e = Escenario-Cob-Una ('m14-p4-' + $c.G)
    $r = Cob-Fix $e $c.G
    Igual "$($c.G): sale con 2" 2 $r.Codigo
    if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
    Comprueba "$($c.G): NO PASA y el motivo" ($r.Salida -match ('NO PASA: .*' + $c.Rx)) (Cola $r.Salida)
    if ($c.NoRx) { Comprueba "$($c.G): y no sale con el motivo del otro caso" ($r.Salida -notmatch $c.NoRx) (Cola $r.Salida) }
    Comprueba "$($c.G): el lote se deshace" ($r.Salida -match 'Lote 1 DESHECHO') (Cola $r.Salida)
    Igual "$($c.G): no hay commits nuevos" 'inicial' (GitEn $e.Wt @('log', '--format=%s'))
  }
}

$Pruebas['m14 cobertura: un test que falla (TEST_FALLA) no vale: no hay mas tests fallando que antes y la cobertura no se mide'] = {
  $e = Escenario-Cob-Una 'm14-p5'
  $r = Cob-Fix $e 'cob-test-falla'
  Igual 'sale con 2' 2 $r.Codigo
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  Comprueba 'NO PASA: mas tests fallando que antes (0 -> 1)' ($r.Salida -match 'NO PASA: Hay mas tests fallando que antes \(0 -> 1\)') (Cola $r.Salida)
  Comprueba 'el lote se deshace' ($r.Salida -match 'Lote 1 DESHECHO') (Cola $r.Salida)
  Comprueba 'las repeticiones no se lanzan' (-not (Test-Path -LiteralPath (Get-Ruta $e.Wt '.rescate/cobertura-rep.log')))
}

$Pruebas['m14 cobertura: al llegar al objetivo para: con 5 clases y el objetivo alcanzado tras la 2.a no hay 3.er lote'] = {
  $cl = @(@('service/AaService', 10, 0), @('service/BbService', 10, 0), @('service/CcService', 10, 0), @('service/DdService', 10, 0), @('service/EeService', 10, 0))
  $e = Escenario-Cob 'm14-para' $cl @{ CoberturaMinima = 40 } @{} $false
  $r = Cob-Fix $e
  Igual 'sale con 0' 0 $r.Codigo
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  Comprueba 'hay lote 1 y lote 2' ($r.Salida -match 'Lote 1 OK' -and $r.Salida -match 'Lote 2 OK') (Cola $r.Salida)
  Comprueba 'no hay lote 3' ($r.Salida -notmatch 'Lote 3') (Cola $r.Salida)
  Igual 'dos commits de cobertura' 2 @((GitEn $e.Wt @('log', '--format=%s')) -split "`n" | Where-Object { $_ -match '^rescate\(cobertura\)' }).Count
  Comprueba 'el resumen dice 0 % -> 40 % (objetivo 40 %)' ($r.Salida -match 'Cobertura: 0 % -> 40 % \(objetivo 40 %\)') (Cola $r.Salida)
  Comprueba 'y no dice que falten clases' ($r.Salida -notmatch 'Faltan estas clases') (Cola $r.Salida)
}

$Pruebas['m14 cobertura: CoberturaClasesMax limita las clases de la pasada y el resto sale como sin intentar'] = {
  $e = Escenario-Cob-Tres 'm14-tope' @{ CoberturaClasesMax = 1 }
  $r = Cob-Fix $e
  Igual 'sale con 0' 0 $r.Codigo
  Comprueba 'un solo lote' ($r.Salida -match 'Lote 1 OK' -and $r.Salida -notmatch 'Lote 2') (Cola $r.Salida)
  Comprueba 'dice el tope' ($r.Salida -match 'Tope de gasto: 1 clase') (Cola $r.Salida)
  Comprueba 'y las que quedan salen sin intentar por el tope' ($r.Salida -match 'sin intentar: tope de 1 clase') (Cola $r.Salida)
}

$Pruebas['m14 cobertura: el final dice X % -> Y %, las clases que faltan con su motivo, las excluidas y los OJO; todo tambien en cobertura-faltan.md'] = {
  $cl = @(@('service/AltaService', 10, 0), @('service/BajaService', 10, 2), @('service/CobroService', 10, 5), @('config/AjusteConfig', 10, 0))
  $e = Escenario-Cob 'm14-final' $cl @{ CoberturaMinima = 95 } @{} $false
  $r = Cob-Fix $e 'cob-parcial:Alta;cob-ojo:Baja;cob-no-sube:Cobro'
  Igual 'sale con 2: una clase atascada' 2 $r.Codigo
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  $md = Lee $e.Wt '.rescate/cobertura-faltan.md'
  foreach ($donde in @(@('la consola', $r.Salida), @('cobertura-faltan.md', $md))) {
    $n = $donde[0]; $txt = $donde[1]
    Comprueba "$n : Cobertura: 17,5 % -> 42,5 % (objetivo 95 %)" ($txt -match 'Cobertura: 17,5 % -> 42,5 % \(objetivo 95 %\)') (Cola $txt)
    Comprueba "$n : Faltan estas clases" ($txt -match 'Faltan estas clases') (Cola $txt)
    Comprueba "$n : AltaService subida pero sin llegar, con sus lineas" ($txt -match 'AltaService\.java - 2/10 lineas \(20 %\): .*aun le faltan lineas') (Cola $txt)
    Comprueba "$n : CobroService atascada, con el motivo" ($txt -match 'CobroService\.java - 5/10 lineas \(50 %\): atascada tras los intentos: .*no sube') (Cola $txt)
    Comprueba "$n : BajaService, que llego al 100 %, no esta entre las que faltan" ($txt -notmatch 'BajaService\.java - ') (Cola $txt)
    Comprueba "$n : las excluidas se dicen" ($txt -match 'No se proponen \(CoberturaExcluir\): 1 clases?' -and $txt.Contains('config/AjusteConfig.java')) (Cola $txt)
    Comprueba "$n : el OJO con su fichero:linea y su texto" ($txt -match 'BajaServiceTest\.java:\d+ - // OJO: parece un error: suma al reves') (Cola $txt)
  }
  Comprueba 'la consola dice donde esta la lista' ($r.Salida.Contains('cobertura-faltan.md'))
}

$Pruebas['m14 cobertura: P4 - un @Test que ya existia y al que el lote le quita la asercion tambien se mira: el lote no vale y el motivo nombra el test'] = {
  $e = Escenario-Cob 'm14-p4-cambiado' @(, @('service/BajaService', 10, 2)) @{} @{} $false
  $r = Cob-Fix $e 'cob-quita-asercion'
  Igual 'sale con 2' 2 $r.Codigo
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  $fich = [regex]::Escape('src/test/java/com/acme/plantillabatch/service/BajaServiceTest.java')
  Comprueba 'NO PASA con el nombre del test que ya existia y su fichero' ($r.Salida -match ('NO PASA: El test sumaBase \(' + $fich + '\) no tiene ninguna asercion \(assert\*')) (Cola $r.Salida)
  Comprueba 'sin Maven' ($r.Salida -match 'Sin Maven: el intento ya incumple las reglas del paso') (Cola $r.Salida)
  Comprueba 'el lote se deshace' ($r.Salida -match 'Lote 1 DESHECHO') (Cola $r.Salida)
  Igual 'no hay commits nuevos' 'inicial' (GitEn $e.Wt @('log', '--format=%s'))
}

$Pruebas['m14 cobertura: P1 - el lote que escribe sus tests en otro fichero y no en <Clase>Test.java no vale: dice cual falta'] = {
  $e = Escenario-Cob-Una 'm14-p1-otro-fichero'
  $r = Cob-Fix $e 'cob-otro-fichero'
  Igual 'sale con 2' 2 $r.Codigo
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  Comprueba 'NO PASA: No has escrito AltaServiceTest.java, y donde va' ($r.Salida -match 'NO PASA: No has escrito AltaServiceTest\.java: escribe o amplia src/test/java/<mismo paquete>/AltaServiceTest\.java') (Cola $r.Salida)
  Comprueba 'sin Maven' ($r.Salida -match 'Sin Maven: el intento ya incumple las reglas del paso') (Cola $r.Salida)
  Comprueba 'el lote se deshace' ($r.Salida -match 'Lote 1 DESHECHO') (Cola $r.Salida)
  Igual 'no hay commits nuevos' 'inicial' (GitEn $e.Wt @('log', '--format=%s'))
}

# ===================== M18: lo que la plantilla tiene y el repo no, y el texto de fecha-antigua =====================
# Lo que dice el diagnostico de los ficheros de la plantilla que faltan en el repo (un aviso de config), o '' si no dice nada.
function Faltan-De-La-Plantilla($E) {
  $r = Rescate @('-Repo', $E.Repo, '-Plantilla', $E.Plantilla, '-SinBuild')
  if ($r.Codigo -ne 0) { return "rescate.ps1 salio con $($r.Codigo): " + (Cola $r.Salida) }
  $a = @(Hallazgos $E.Repo | Where-Object { $_.Cat -eq 'config' -and $_.Detalle -like 'ficheros que la plantilla tiene*' })
  if ($a.Count -eq 0) { return '' }
  return "$($a[0].Detalle)"
}

# Deja en la plantilla (despues de su commit) un Dockerfile, un datos.txt y un docs/INFORME.md; si $EnGit, tambien en git.
function Pon-Ficheros-De-Plantilla($E, [bool]$EnGit) {
  Escribe $E.Plantilla 'Dockerfile' "FROM eclipse-temurin:21`n"
  Escribe $E.Plantilla 'datos.txt' "uno`ndos`n"
  Escribe $E.Plantilla 'docs/INFORME.md' "# Informe`n"
  if ($EnGit) {
    [void](GitEn $E.Plantilla @('add', '--', 'Dockerfile', 'datos.txt', 'docs/INFORME.md'))
    [void](GitEn $E.Plantilla @('commit', '-q', '-m', 'ficheros'))
  }
  Escribe $E.Plantilla 'salida-x/graph.json' "{}`n"
}

$Pruebas['m18 plantilla (h): la referencia con git solo cuenta lo que esta en git y no es de datos: Dockerfile si; graph.json y herramienta-out/config.yml (fuera de git), datos.txt e INFORME.md no'] = {
  $e = Nuevo-Escenario 'm18-h'
  Pon-Ficheros-De-Plantilla $e $true
  Escribe $e.Plantilla 'herramienta-out/config.yml' "a: b`n"   # fuera de git y que no es de datos: con git, tampoco cuenta
  Igual 'solo avisa del Dockerfile' 'ficheros que la plantilla tiene y aqui faltan: Dockerfile' (Faltan-De-La-Plantilla $e)
}

$Pruebas['m18 plantilla (i): la referencia sin git lista como hoy, pero sin las extensiones de datos'] = {
  $e = Nuevo-Escenario 'm18-i'
  Pon-Ficheros-De-Plantilla $e $false
  Escribe $e.Plantilla 'config/app.properties' "a=b`n"
  Remove-Item -LiteralPath (Join-Path $e.Plantilla '.git') -Recurse -Force
  Igual 'avisa del Dockerfile y de lo que no es de datos, sin graph.json, datos.txt ni INFORME.md' 'ficheros que la plantilla tiene y aqui faltan: Dockerfile, config/app.properties' (Faltan-De-La-Plantilla $e)
}

$Pruebas['m18 plantilla (j): fecha-antigua dice que usa la API antigua y que pasarla a java.time pide un test delante'] = {
  $e = Nuevo-Escenario 'm18-j'
  [void](Rescate @('-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-SinBuild'))
  $f = @(Hallazgos $e.Repo | Where-Object { $_.Detalle -like '`[fecha-antigua`]*' })
  Igual 'hay un aviso de fecha-antigua' 1 $f.Count
  Igual 'con el texto nuevo' '[fecha-antigua] usa java.util.Date (API antigua de fechas). Pasarlo a java.time puede cambiar el formato o la zona: hazlo solo con un test delante' "$($f[0].Detalle)"
  Comprueba 'y ya no dice que usa java.time en vez de la antigua' (("$($f[0].Detalle)") -notmatch 'usa java\.time en vez de')
}

# ===== M20a: LA PUERTA DE LOS TESTS MIRA LOS TESTS DE VERDAD =====
# Los falsos son m20a-mvn.ps1 y m20a-copilot.ps1. Los informes de surefire (XML y .txt) salen de los metodos '@Test ... void x() {...}' de
# src/test/java: M20A_FALLA en la linea, el test falla; @DisabledOnOs, se salta. El pom manda, como en Maven: un <skipTests>true</skipTests> dentro
# de <configuration> no ejecuta nada (gana al -DskipTests=false) y un <testFailureIgnore>true</testFailureIgnore> hace salir con 0 aunque falle.
$TestM20a = 'src/test/java/com/acme/life/FacturaServiceTest.java'
$ClaseM20a = 'com.acme.life.FacturaServiceTest'
$FacturaM20a = @'
package com.acme.life;

class FacturaServiceTest {
    @Test void calculaRecargo() { /* M20A_FALLA */ }
    @Test void calculaBase() { }
    @Test void calculaIva() { }
    @Test void calculaTotal() { }
    @Test void redondea() { }
}
'@
$TresRotosM20a = @'
package com.acme.life;

class FacturaServiceTest {
    @Test void uno() { /* M20A_FALLA */ }
    @Test void dos() { /* M20A_FALLA */ }
    @Test void dos(int n) { /* M20A_FALLA */ }
    @Test void cuatro() { }
}
'@
$AnotacionesM20a = @'
package com.acme.life;

class FacturaServiceTest {
    @Test void a() { /* M20A_FALLA */ }
    @ParameterizedTest void b() { }
    @RepeatedTest void c() { }
    @TestFactory void d() { }
    @org.junit.jupiter.api.Test void e() { }
}
'@
$MotivoM20a = 'org.opentest4j.AssertionFailedError: expected: <1> but was: <2>'

# El pom del banco con esto dentro de la configuracion del plugin de surefire.
function Pom-Surefire([string]$Config) {
  return ($Pom -replace '</project>', ('<build><plugins><plugin><artifactId>maven-surefire-plugin</artifactId><configuration>' + $Config + '</configuration></plugin></plugins></build></project>'))
}

# Repo de juguete con FacturaServiceTest como unico test (1 metodo que falla y 4 que pasan, o el texto de $Test) ya en un commit, con el
# Maven y el Copilot de m20a. $Mas: ajustes de mas (nombre -> valor).
function Escenario-M20a([string]$Nombre, [string]$Test = $FacturaM20a, [hashtable]$Mas = @{}) {
  $cfg = @{ CopilotExe = (Join-Path $falsos 'm20a-copilot.ps1'); MvnExe = (Join-Path $falsos 'm20a-mvn.ps1') }
  foreach ($k in $Mas.Keys) { $cfg[$k] = $Mas[$k] }
  $e = Escenario-M6 $Nombre $cfg
  Remove-Item -LiteralPath (Get-Ruta $e.Repo 'src/test/java/com/acme/life/PolizaServiceTest.java') -Force
  Escribe $e.Repo $TestM20a $Test
  [void](GitEn $e.Repo @('add', '-A', '--', 'src/test'))
  [void](GitEn $e.Repo @('commit', '-q', '-m', 'tests de m20a'))
  return $e
}

# El diagnostico con Maven del repo (con M20A_FORMATO si se pide): lo que sale y los hallazgos de 'tests' que son errores.
function Diagnostica-M20a($E, [string]$Formato = '') {
  $env:M20A_FORMATO = $Formato
  try { $r = Rescate @('-Repo', $E.Repo, '-Plantilla', $E.Plantilla) }
  finally { $env:M20A_FORMATO = '' }
  return [pscustomobject]@{ R = $r; H = @(Hallazgos $E.Repo | Where-Object { $_.Cat -eq 'tests' -and $_.Sev -eq 'error' }) }
}

# Un lote del paso 'estructura' (un solo fichero, un lote) con estos guiones de RESCATE_FALSO y este M20A_FORMATO.
function Lote-M20a($E, [string]$Guion, [string]$Formato = '') {
  $env:M20A_FORMATO = $Formato
  try { return (Fix-M6 $E 'estructura' 1 @('-Lote', '1', '-MaxLotes', '1') $Guion) }
  finally { $env:M20A_FORMATO = '' }
}

$Pruebas['m20a (a): Maven sale con 0 pero el informe XML trae 1 fallo: los tests no estan bien y sale un hallazgo con el nombre del metodo y su motivo'] = {
  $e = Escenario-M20a 'm20a-a'
  Escribe $e.Repo 'pom.xml' (Pom-Surefire '<testFailureIgnore>true</testFailureIgnore>')
  [void](GitEn $e.Repo @('commit', '-q', '-am', 'testFailureIgnore'))
  $d = Diagnostica-M20a $e
  Igual 'sale con 0' 0 $d.R.Codigo
  Comprueba 'el estado dice que los tests fallan' ($d.R.Salida -match 'compila: SI \| tests: FALLAN') (Cola $d.R.Salida)
  Igual 'un hallazgo de tests' 1 $d.H.Count
  if ($d.H.Count -ne 1) { return }
  Igual 'el detalle nombra el metodo y la clase' "falla calculaRecargo en $ClaseM20a" $d.H[0].Detalle
  Igual 'el fichero es el de la clase de test' $TestM20a $d.H[0].Fichero
  Igual 'el motivo es el del metodo' $MotivoM20a $d.H[0].Motivo
}

$Pruebas['m20a (a2): con Maven saliendo con 1 los hallazgos son los mismos: uno por metodo que falla, no uno por clase'] = {
  $e = Escenario-M20a 'm20a-a2' $TresRotosM20a
  $d = Diagnostica-M20a $e
  Comprueba 'el estado dice que los tests fallan' ($d.R.Salida -match 'compila: SI \| tests: FALLAN') (Cola $d.R.Salida)
  Igual 'tres hallazgos de tests, uno por metodo, y el segundo "dos" (una sobrecarga) con su numero' ("falla dos (2) en $ClaseM20a|falla dos en $ClaseM20a|falla uno en $ClaseM20a") ((@($d.H | ForEach-Object { $_.Detalle }) | Sort-Object) -join '|')
  $s = Diagnostica-M20a $e 'xml-sin-casos'
  Igual 'un fallo de la clase entera, sin <testcase> que lo lleve, tambien sale: numerado' ("test 1 de 3 que fallan en $ClaseM20a|test 2 de 3 que fallan en $ClaseM20a|test 3 de 3 que fallan en $ClaseM20a") ((@($s.H | ForEach-Object { $_.Detalle }) | Sort-Object) -join '|')
  # con Maven saliendo con 0 (testFailureIgnore en el pom) el fallo de la clase entera tambien hace fallar los tests
  Escribe $e.Repo 'pom.xml' (Pom-Surefire '<testFailureIgnore>true</testFailureIgnore>')
  [void](GitEn $e.Repo @('commit', '-q', '-am', 'testFailureIgnore'))
  $z = Diagnostica-M20a $e 'xml-sin-casos'
  Comprueba 'con Maven saliendo con 0, el fallo de la clase entera hace que los tests fallen' ($z.R.Codigo -eq 0 -and $z.R.Salida -match 'compila: SI \| tests: FALLAN') (Cola $z.R.Salida)
}

$Pruebas['m20a (b): Maven sale con 0, hay un test en src/test/java y no se ha ejecutado ninguno (skipTests en el pom): hallazgo de tests en pom.xml'] = {
  $e = Escenario-M20a 'm20a-b'
  Escribe $e.Repo 'pom.xml' (Pom-Surefire '<skipTests>true</skipTests>')
  [void](GitEn $e.Repo @('commit', '-q', '-am', 'skipTests'))
  $d = Diagnostica-M20a $e
  Igual 'sale con 0' 0 $d.R.Codigo
  Comprueba 'el estado dice que los tests fallan' ($d.R.Salida -match 'compila: SI \| tests: FALLAN') (Cola $d.R.Salida)
  Igual 'un hallazgo de tests' 1 $d.H.Count
  if ($d.H.Count -ne 1) { return }
  Igual 'el fichero es el pom' 'pom.xml' $d.H[0].Fichero
  Igual 'el detalle manda mirar el pom' 'Hay tests en src/test/java, pero Maven no ha ejecutado ninguno: mira skipTests, testFailureIgnore, excludes o el perfil del pom' $d.H[0].Detalle
}

$Pruebas['m20a (c): Maven sale con 0 y no hay src/test/java: los tests estan bien y no hay hallazgo de error'] = {
  $e = Escenario-M20a 'm20a-c'
  [void](GitEn $e.Repo @('rm', '-q', '-r', '--', 'src/test'))
  [void](GitEn $e.Repo @('commit', '-q', '-m', 'sin tests'))
  $d = Diagnostica-M20a $e
  Igual 'sale con 0' 0 $d.R.Codigo
  Comprueba 'el estado dice que los tests estan bien' ($d.R.Salida -match 'compila: SI \| tests: OK') (Cola $d.R.Salida)
  Igual 'ningun hallazgo de tests' 0 $d.H.Count
}

$Pruebas['m20a (d): una clase con 1 metodo que falla antes del lote y 5 despues: el lote no pasa y sale "Hay mas tests fallando que antes (1 -> 5)"'] = {
  $e = Escenario-M20a 'm20a-d'
  $r = Lote-M20a $e 'm20a-rompe-mas'
  Comprueba 'NO PASA: Hay mas tests fallando que antes (1 -> 5)' ($r.Salida -match 'NO PASA: .*Hay mas tests fallando que antes \(1 -> 5\)') (Cola $r.Salida)
  Comprueba 'el lote se deshace' ($r.Salida -match 'Lote 1 DESHECHO') (Cola $r.Salida)
}

$Pruebas['m20a (control): un lote que no toca los tests pasa: con 5 tests antes y despues, y el que falla seguiendo igual, ninguna puerta nueva salta'] = {
  $e = Escenario-M20a 'm20a-control'
  $r = Lote-M20a $e ''
  Comprueba 'el lote sale bien' ($r.Salida -match "Lote 1 OK: 'estructura'") (Cola $r.Salida)
  Comprueba 'ninguna puerta nueva' ($r.Salida -notmatch 'Se ejecutan menos tests|Has borrado \d+ metodos|Hay mas tests fallando') (Cola $r.Salida)
}

$Pruebas['m20a (e): el lote borra el metodo de test que fallaba pero deja el fichero: no pasa, por los metodos borrados y por los tests que se ejecutan'] = {
  $e = Escenario-M20a 'm20a-e'
  $r = Lote-M20a $e 'm20a-borra-metodo'
  Comprueba 'NO PASA: Has borrado 1 metodos de test (5 -> 4)' ($r.Salida -match 'NO PASA: .*Has borrado 1 metodos de test \(5 -> 4\)\. Restauralos\.') (Cola $r.Salida)
  Comprueba 'y Se ejecutan menos tests que antes (5 -> 4)' ($r.Salida -match 'Se ejecutan menos tests que antes \(5 -> 4\)\. No borres, saltes ni excluyas tests\.') (Cola $r.Salida)
  Comprueba 'el lote se deshace' ($r.Salida -match 'Lote 1 DESHECHO') (Cola $r.Salida)
}

$Pruebas['m20a (e2): comentar el metodo con // tampoco vale: un @Test comentado no cuenta como metodo'] = {
  $e = Escenario-M20a 'm20a-e2'
  $r = Lote-M20a $e 'm20a-comenta-metodo'
  Comprueba 'NO PASA: Has borrado 1 metodos de test (5 -> 4)' ($r.Salida -match 'NO PASA: .*Has borrado 1 metodos de test \(5 -> 4\)\. Restauralos\.') (Cola $r.Salida)
  Comprueba 'el lote se deshace' ($r.Salida -match 'Lote 1 DESHECHO') (Cola $r.Salida)
}

$Pruebas['m20a (e3): se cuentan @Test, @ParameterizedTest, @RepeatedTest, @TestFactory y @org.junit.jupiter.api.Test: vaciar la clase borra 5 metodos'] = {
  $e = Escenario-M20a 'm20a-e3' $AnotacionesM20a
  $r = Lote-M20a $e 'm20a-vacia-test'
  Comprueba 'NO PASA: Has borrado 5 metodos de test (5 -> 0)' ($r.Salida -match 'NO PASA: .*Has borrado 5 metodos de test \(5 -> 0\)\. Restauralos\.') (Cola $r.Salida)
}

$Pruebas['m20a (f): el lote pone skipTests en el pom y Maven ejecuta 0 tests: no pasa y sale "Se ejecutan menos tests que antes (5 -> 0)"'] = {
  $e = Escenario-M20a 'm20a-f'
  $r = Lote-M20a $e 'm20a-skip-pom'
  Comprueba 'NO PASA: Se ejecutan menos tests que antes (5 -> 0)' ($r.Salida -match 'NO PASA: .*Se ejecutan menos tests que antes \(5 -> 0\)\. No borres, saltes ni excluyas tests\.') (Cola $r.Salida)
  Comprueba 'el lote se deshace' ($r.Salida -match 'Lote 1 DESHECHO') (Cola $r.Salida)
}

$Pruebas['m20a (g): MvnTests lleva -DskipTests=false, -Dmaven.test.skip=false y -Dmaven.test.failure.ignore=false'] = {
  $e = Escenario-M20a 'm20a-g'
  $d = Diagnostica-M20a $e
  Igual 'sale con 0' 0 $d.R.Codigo
  $l = @([System.IO.File]::ReadAllLines((Get-Ruta $e.Repo '.rescate/mvn-llamadas.log')) | Where-Object { $_ -match ' test$' })
  Comprueba 'hay una llamada de tests' ($l.Count -ge 1) ($l -join ' // ')
  Comprueba 'la orden lleva los tres -D, antes de test' (@($l | Where-Object { $_ -match '\| -q -B -DskipTests=false -Dmaven\.test\.skip=false -Dmaven\.test\.failure\.ignore=false test$' }).Count -eq $l.Count) ($l -join ' // ')
  # la orden que el prompt le da a la IA: PowerShell parte -Dmaven.test.skip=false en dos argumentos si no va entre comillas
  [void](Rescate @('-Modo', 'fix', '-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-Paso', 'tests', '-SinPlan', '-Lote', '1', '-Auto', '-Si', '-MaxIntentos', '1'))
  $p = Lee $e.Wt '.rescate/prompt.md'
  Comprueba 'el prompt lleva la orden con los -D con punto entre comillas' ($p -match '(?m)^- Ejecuta: .* -q -B -DskipTests=false "-Dmaven\.test\.skip=false" "-Dmaven\.test\.failure\.ignore=false" test ') $p
}

$Pruebas['m20a (h): sin XML, con el .txt antiguo, se cuenta igual: un hallazgo numerado por fallo y los tests que se ejecutan'] = {
  $e = Escenario-M20a 'm20a-h' $TresRotosM20a
  $dx = Diagnostica-M20a $e
  $dt = Diagnostica-M20a $e 'txt'
  Igual 'con el .xml, 3 hallazgos' 3 $dx.H.Count
  Igual 'con solo el .txt, 3 hallazgos' 3 $dt.H.Count
  $esperado = (1..3 | ForEach-Object { "test $_ de 3 que fallan en $ClaseM20a" }) -join '|'
  Igual 'cada uno con su numero, y no hay dos con el mismo texto' $esperado ((@($dt.H | ForEach-Object { $_.Detalle }) | Sort-Object) -join '|')
  Igual 'con el .xml roto cae al .txt: los mismos numerados' $esperado ((@((Diagnostica-M20a $e 'xml-roto').H | ForEach-Object { $_.Detalle }) | Sort-Object) -join '|')
  $e2 = Escenario-M20a 'm20a-h2'
  $r = Lote-M20a $e2 'm20a-borra-metodo' 'txt'
  Comprueba 'con solo el .txt, borrar el metodo baja los tests que se ejecutan (5 -> 4)' ($r.Salida -match 'Se ejecutan menos tests que antes \(5 -> 4\)') (Cola $r.Salida)
  Comprueba 'y los metodos (5 -> 4)' ($r.Salida -match 'Has borrado 1 metodos de test \(5 -> 4\)') (Cola $r.Salida)
}

$Pruebas['m20a (i): un test saltado (@DisabledOnOs) no cuenta como ejecutado: el lote no pasa aunque el metodo siga y el fallo baje'] = {
  $e = Escenario-M20a 'm20a-i'
  $r = Lote-M20a $e 'm20a-salta-metodo'
  Comprueba 'NO PASA: Se ejecutan menos tests que antes (5 -> 4)' ($r.Salida -match 'NO PASA: .*Se ejecutan menos tests que antes \(5 -> 4\)') (Cola $r.Salida)
  Comprueba 'el metodo sigue en el fichero: no dice que se hayan borrado' ($r.Salida -notmatch 'Has borrado \d+ metodos') (Cola $r.Salida)
  Comprueba 'el lote se deshace' ($r.Salida -match 'Lote 1 DESHECHO') (Cola $r.Salida)
  $e2 = Escenario-M20a 'm20a-i2'
  $rs = Lote-M20a $e2 'm20a-salta-metodo' 'txt'
  Comprueba 'con el .txt antiguo (Skipped: 1) tambien' ($rs.Salida -match 'Se ejecutan menos tests que antes \(5 -> 4\)') (Cola $rs.Salida)
}

# ===== M22: EN SONAR CADA LOTE PASA SOLO LOS TESTS LIGEROS, Y LA SUITE ENTERA VA EN UN CONTROL =====
# El Maven de mentira es m22-mvn.ps1: lee -Dsurefire.excludesFile y -Dtest, deja un TEST-<clase>.xml por clase y hace fallar una clase segun lo que
# dice su texto (M22_FALLA, M22_FALLA_CON:<Clase>, M22_FALLA_SI_CAMBIA, M22_INESTABLE:<n>, M22_FALLA_DESDE:<n>; mas en su cabecera). Con
# RESCATE_M22_LOG deja una linea por llamada: las pruebas cuentan suites (sin excludesFile ni -Dtest), parciales (con excludesFile) y solas (-Dtest).
$M22Mvn = Join-Path $falsos 'm22-mvn.ps1'
$M22Dir = 'src/test/java/com/acme/plantillabatch/'

# Un test de src/test/java/com/acme/plantillabatch: $Marcas va en un comentario (lo que lee el Maven de mentira), $Anotacion antes de la clase.
function Test-Java-M22([string]$Clase, [string]$Marcas = '', [string]$Anotacion = '', [string]$Hereda = '') {
  $ext = ''
  if ($Hereda) { $ext = " extends $Hereda" }
  return @"
package com.acme.plantillabatch;

import org.junit.jupiter.api.Test;

// $Marcas
$Anotacion
class $Clase$ext {

    @Test
    void ${Clase}Metodo() {
        int base = 1;
    }
}
"@
}

# Un repo de Sonar con el Maven de las pruebas m22. $Tests: nombre de clase de test -> su texto (Test-Java-M22). $Mas: ajustes del repo.
function Escenario-M22([string]$Nombre, [string[]]$Clases, [hashtable]$Tests = @{}, [hashtable]$Mas = @{}) {
  $extra = @{}
  foreach ($k in $Tests.Keys) { $extra['/' + $M22Dir + $k + '.java'] = $Tests[$k] }
  $cfg = @{ MvnExe = $M22Mvn; CopilotExe = (Join-Path $falsos 'm22-copilot.ps1') }
  foreach ($k in $Mas.Keys) { $cfg[$k] = $Mas[$k] }
  $e = Escenario-Sonar $Nombre $Clases $cfg @() $extra
  Informe-Sonar $e.Xlsx @($Clases | ForEach-Object { Inc-M21 $e ($_ -split '/')[1] "Fix this bug in $_." })
  return $e
}

# Lanza el paso sonar del escenario (con -Sonar el script no para entre lotes). $Registro: el fichero donde el Maven de mentira apunta sus llamadas;
# $Mas: argumentos de mas; $Env: variables de entorno de las pruebas (RESCATE_M22_*, RESCATE_MVN_ESPERA) mientras dura.
function Lanza-M22($E, [string]$Registro, [string[]]$Mas = @(), [hashtable]$Env = @{}) {
  $a = @('-Modo', 'fix', '-Paso', 'sonar', '-Sonar', $E.Xlsx, '-Si', '-MaxIntentos', '1', '-Lote', '1') + $Mas
  $env:RESCATE_M22_LOG = $Registro
  $env:RESCATE_M22_ESTADO = Join-Path $E.Raiz 'estado'
  foreach ($k in $Env.Keys) { Set-Item -Path ('Env:' + $k) -Value $Env[$k] }
  try { return (Sonar-Lanza $E $a) }
  finally { Remove-Item (@('Env:RESCATE_M22_LOG', 'Env:RESCATE_M22_ESTADO') + @($Env.Keys | ForEach-Object { 'Env:' + $_ })) -ErrorAction SilentlyContinue }
}

# Las llamadas de Maven con tests del registro: Donde (carpeta), Clases (las que ejecuta), Args y Tipo (suite, parcial o solas).
function Llamadas-M22([string]$Registro) {
  $r = @()
  if (-not (Test-Path -LiteralPath $Registro)) { return $r }
  foreach ($l in [System.IO.File]::ReadAllLines($Registro)) {
    $p = @($l -split ' \| ', 3)
    if ($p[2] -notmatch 'DskipTests=false') { continue }
    $tipo = 'suite'
    if ($p[2] -match '-Dtest=') { $tipo = 'solas' } elseif ($p[2] -match '-Dsurefire\.excludesFile=') { $tipo = 'parcial' }
    $r += [pscustomobject]@{ Donde = $p[0]; Clases = $p[1]; Args = $p[2]; Tipo = $tipo }
  }
  return $r
}

function Cuenta-M22($Llamadas, [string]$Tipo) { return @($Llamadas | Where-Object { $_.Tipo -eq $Tipo }).Count }

# El commit al que apunta la marca refs/rescate/control-ok del worktree ('' si no hay).
function Marca-M22($E) {
  $ErrorActionPreference = 'Continue'
  $o = & git -C $E.Wt rev-parse --verify -q refs/rescate/control-ok 2>$null
  if ($LASTEXITCODE -ne 0) { return '' }
  return "$o".Trim()
}

function Head-M22($E) { return (GitEn $E.Wt @('rev-parse', 'HEAD')).Trim() }

# Las lineas de control de intentos.tsv.
function Controles-M22($E) {
  $t = Intentos-M21 $E
  if (-not $t) { return @() }
  return @($t.Filas | Where-Object { $_.paso -eq 'control' })
}

$CtxM22 = @{ AppContextTest = (Test-Java-M22 'AppContextTest' '' '@SpringBootTest') }

$Pruebas['m22 (a): la lista de contexto: @SpringBootTest, lo que hereda de eso, SpringExtension y el job; un JUnit sin Spring es ligero'] = {
  $t = [ordered]@{
    AppContextTest   = (Test-Java-M22 'AppContextTest' '' '@SpringBootTest')
    HijoContextoTest = (Test-Java-M22 'HijoContextoTest' '' '' 'AppContextTest')
    NietoContextoTest = (Test-Java-M22 'NietoContextoTest' '' '' 'HijoContextoTest')
    ExtensionTest    = (Test-Java-M22 'ExtensionTest' '' '@ExtendWith(SpringExtension.class)')
    JobTest          = (Test-Java-M22 'JobTest' 'new JobLauncherTestUtils()' '')
    PlanoTest        = (Test-Java-M22 'PlanoTest' 'JUnit sin Spring' '')
    OtroPlanoTest    = (Test-Java-M22 'OtroPlanoTest' '' '' 'PlanoTest')
  }
  $e = Escenario-M22 'm22-a' @('service/TotalService') $t
  $r = Sonar-Lanza $e @('-Modo', 'fix', '-Paso', 'sonar', '-Sonar', $e.Xlsx, '-Auto', '-Si', '-MaxIntentos', '1', '-MaxLotes', '0')
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  $ruta = Get-Ruta $e.Wt '.rescate/tests-de-contexto.txt'
  if (-not (Test-Path -LiteralPath $ruta -PathType Leaf)) { Comprueba 'existe .rescate/tests-de-contexto.txt' $false (Cola $r.Salida); return }
  $l = @([System.IO.File]::ReadAllLines($ruta) | Where-Object { $_ } | Sort-Object)
  $p = 'com/acme/plantillabatch/'
  Igual 'son de contexto las cinco, una por linea y en el formato de excludesFile (paquete/Clase.*)' (@("${p}AppContextTest.*", "${p}ExtensionTest.*", "${p}HijoContextoTest.*", "${p}JobTest.*", "${p}NietoContextoTest.*") -join ' ') ($l -join ' ')
  Comprueba 'un JUnit sin Spring, el que hereda de el y TotalServiceTest son ligeros: no salen' ((@($l | Where-Object { $_ -match 'PlanoTest|TotalServiceTest' })).Count -eq 0) ($l -join ' ')
}

$Pruebas['m22 (b): un lote de sonar pasa las puertas con el excludesFile (el Maven falso lo registra); fuera de PasosTestsElegidos pasa la suite entera'] = {
  $e = Escenario-M22 'm22-b' @('service/TotalService') $CtxM22
  $log = Join-Path $e.Raiz 'mvn-m22.log'
  $r = Lanza-M22 $e $log
  Igual 'sale con 0' 0 $r.Codigo
  Comprueba 'el lote pasa' ($r.Salida -match "Lote 1 OK: 'sonar' 1 -> 0") (Cola $r.Salida)
  $c = @(Llamadas-M22 $log)
  $parc = @($c | Where-Object { $_.Tipo -eq 'parcial' })
  Comprueba 'el Maven del lote lleva -Dsurefire.excludesFile con la lista de contexto' ($parc.Count -ge 1 -and $parc[0].Args -match '-Dsurefire\.excludesFile=\S*tests-de-contexto\.txt') (($c | ForEach-Object { $_.Tipo + ': ' + $_.Args }) -join ' // ')
  Comprueba 'y solo ejecuta el test ligero' ($parc.Count -ge 1 -and $parc[0].Clases -eq 'TotalServiceTest') (($parc | ForEach-Object { $_.Clases }) -join ' | ')
  Comprueba 'el diagnostico de antes pasa la suite entera: ejecuta los dos tests' (@($c | Where-Object { $_.Tipo -eq 'suite' -and (@($_.Clases -split ',') | Sort-Object) -join ',' -eq 'AppContextTest,TotalServiceTest' }).Count -ge 1) (($c | ForEach-Object { $_.Tipo + ': ' + $_.Clases }) -join ' | ')
  # un paso que no esta en PasosTestsElegidos (como calidad; el Copilot de mentira no arregla calidad, por eso es sonar con la lista vacia): la suite entera en
  # cada lote, sin excludesFile ni lista ni marca
  $e2 = Escenario-M22 'm22-b2' @('service/TotalService') $CtxM22 @{ PasosTestsElegidos = @() }
  $log2 = Join-Path $e2.Raiz 'mvn-m22.log'
  $r2 = Lanza-M22 $e2 $log2
  $c2 = @(Llamadas-M22 $log2)
  Comprueba 'fuera de PasosTestsElegidos el lote pasa' ($r2.Salida -match "Lote 1 OK: 'sonar' 1 -> 0") (Cola $r2.Salida)
  Igual 'dos suites enteras: el diagnostico y el lote' 2 (Cuenta-M22 $c2 'suite')
  Igual 'ningun Maven con excludesFile' 0 (Cuenta-M22 $c2 'parcial')
  Comprueba 'ni lista de contexto ni marca' (-not (Test-Path -LiteralPath (Get-Ruta $e2.Wt '.rescate/tests-de-contexto.txt')) -and -not (Marca-M22 $e2)) (Cola $r2.Salida)
}

$Pruebas['m22 (c): un lote que toca un test de contexto lo pasa en ese lote; si no lo toca, ese test no se ejecuta en el lote'] = {
  $t = @{ AppContextTest = (Test-Java-M22 'AppContextTest' 'M22_FALLA_SI_CAMBIA' '@SpringBootTest') }
  # el lote arregla una incidencia del propio test de contexto: el Copilot de mentira le anade ' + 0;' y el test de mentira falla si lo lleva
  $e = Escenario-M22 'm22-c' @('service/TotalService') $t
  $prop = $M22Dir + 'AppContextTest.java'
  Informe-Sonar $e.Xlsx @(, (Inc 'CRITICAL' 'Fix this bug in the test.' 'BUG' 'AppContextTest.java' $prop ((Linea-De (Lee $e.Repo $prop) 'int base').ToString() + 'L')))
  $log = Join-Path $e.Raiz 'mvn-m22.log'
  $r = Lanza-M22 $e $log
  $c = @(Llamadas-M22 $log)
  $parc = @($c | Where-Object { $_.Tipo -eq 'parcial' })
  Comprueba 'el Maven del lote ejecuta el test de contexto que el lote toca' ($parc.Count -ge 1 -and (@($parc[0].Clases -split ',') -contains 'AppContextTest')) (($c | ForEach-Object { $_.Tipo + ': ' + $_.Clases }) -join ' | ')
  Comprueba 'con una lista sin ese test (otro fichero)' ($parc.Count -ge 1 -and $parc[0].Args -match '-Dsurefire\.excludesFile=\S*tests-de-contexto-lote\.txt') (($parc | ForEach-Object { $_.Args }) -join ' | ')
  Comprueba 'y como el lote lo rompe, no pasa: falla un test que no fallaba en el ultimo control' ($r.Salida -match 'NO PASA: .*[Ff]alla un test que no fallaba en el ultimo control' -and $r.Salida -match 'Lote 1 DESHECHO') (Cola $r.Salida)
  # el mismo test, sin tocarlo: el lote arregla otra clase y el de contexto se queda fuera del lote (el control es quien lo pasa)
  $e2 = Escenario-M22 'm22-c2' @('service/TotalService') $t
  $log2 = Join-Path $e2.Raiz 'mvn-m22.log'
  $r2 = Lanza-M22 $e2 $log2
  $parc2 = @(Llamadas-M22 $log2 | Where-Object { $_.Tipo -eq 'parcial' })
  Comprueba 'si el lote no lo toca, no lo ejecuta' ($parc2.Count -ge 1 -and $parc2[0].Clases -eq 'TotalServiceTest') (($parc2 | ForEach-Object { $_.Clases }) -join ' | ')
  Comprueba 'y el lote pasa' ($r2.Salida -match "Lote 1 OK: 'sonar' 1 -> 0") (Cola $r2.Salida)
}

$Pruebas['m22 (d): con LotesEntreControles = 2 y 4 lotes buenos hay dos controles y la marca acaba en el HEAD; con 3, el segundo es el del final'] = {
  $cl = @('service/TotalService', 'service/ReciboService', 'service/PagoService', 'service/CobroService')
  $e = Escenario-M22 'm22-d' $cl $CtxM22 @{ LotesEntreControles = 2 }
  $log = Join-Path $e.Raiz 'mvn-m22.log'
  $r = Lanza-M22 $e $log @() @{ RESCATE_MVN_ESPERA = '1' }
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'cuatro lotes buenos' 4 @([regex]::Matches($r.Salida, "Lote \d OK: 'sonar'")).Count
  $c = @(Llamadas-M22 $log)
  Igual 'cada lote pasa solo los ligeros: 4 Maven parciales' 4 (Cuenta-M22 $c 'parcial')
  Igual 'la suite entera, tres veces: el diagnostico de antes y los dos controles (el del final no hace falta: la marca ya esta en el HEAD)' 3 (Cuenta-M22 $c 'suite')
  Igual 'ni una pasada con -Dtest: no hubo culpables' 0 (Cuenta-M22 $c 'solas')
  Igual 'la marca refs/rescate/control-ok esta en el HEAD' (Head-M22 $e) (Marca-M22 $e)
  $k = @(Controles-M22 $e)
  Igual 'intentos.tsv lleva dos lineas de control' 2 $k.Count
  Igual 'las dos en verde' 'verde verde' ((@($k | ForEach-Object { $_.resultado })) -join ' ')
  Igual 'tras el lote 2 y tras el 4' '2 4' ((@($k | ForEach-Object { $_.lote })) -join ' ')
  Comprueba 'con los segundos de Maven de la suite (cada llamada tarda 1 s)' (@($k | Where-Object { $_.seg_maven -notmatch '^\d+$' -or [int]$_.seg_maven -lt 1 }).Count -eq 0) ((@($k | ForEach-Object { $_.seg_maven })) -join ' ')
  Igual 'sus 11 campos' '11 11' ((@($k | ForEach-Object { $_.Campos })) -join ' ')
  # tres lotes: el control del lote 2 y el del final
  $e2 = Escenario-M22 'm22-d2' $cl[0..2] $CtxM22 @{ LotesEntreControles = 2 }
  $log2 = Join-Path $e2.Raiz 'mvn-m22.log'
  $r2 = Lanza-M22 $e2 $log2
  $c2 = @(Llamadas-M22 $log2)
  Igual 'tres lotes: la suite entera tres veces (el diagnostico, el control del lote 2 y el del final)' 3 (Cuenta-M22 $c2 'suite')
  Igual 'y la marca en el HEAD' (Head-M22 $e2) (Marca-M22 $e2)
  Igual 'dos controles, el segundo tras el lote 3' '2 3' ((@(Controles-M22 $e2 | ForEach-Object { $_.lote })) -join ' ')
}

# El escenario de (e) y (n): cuatro lotes buenos y el de ReciboService rompe el test de contexto en el control (el de los lotes 1 y 2, y el de los 3 y 4).
function Corre-E-M22([string]$Nombre) {
  $cl = @('service/TotalService', 'service/ReciboService', 'service/PagoService', 'service/CobroService')
  $t = @{ AppContextTest = (Test-Java-M22 'AppContextTest' 'M22_FALLA_CON:ReciboService' '@SpringBootTest') }
  $e = Escenario-M22 $Nombre $cl $t @{ LotesEntreControles = 2 }
  $log = Join-Path $e.Raiz 'mvn-m22.log'
  return [pscustomobject]@{ E = $e; Log = $log; R = (Lanza-M22 $e $log) }
}

$Pruebas['m22 (e): un lote rompe un test de contexto y pasa su lote; el control sale rojo, la biseccion da ese lote, se revierte y la marca se mueve'] = {
  $x = Corre-E-M22 'm22-e'
  $e = $x.E; $log = $x.Log; $r = $x.R
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'los cuatro lotes pasan sus puertas (el de contexto no se ejecuta en el lote)' 4 @([regex]::Matches($r.Salida, "Lote \d OK: 'sonar'")).Count
  Comprueba 'la consola dice que el control sale rojo y que el lote rompe el test de contexto' ($r.Salida -match 'rompe com\.acme\.plantillabatch\.AppContextTest en el control') (Cola $r.Salida)
  Comprueba 'y que el fichero no se vuelve a intentar en esta pasada' ($r.Salida -match 'ReciboService\.java: .*no se vuelve a intentar') (Cola $r.Salida)
  $sub = @((GitEn $e.Wt @('log', '--format=%s')) -split "`n")
  Igual 'hay un commit de revert del control' 1 @($sub | Where-Object { $_ -match '^rescate\(control\): ' }).Count
  Igual 'los cuatro lotes siguen en la rama' 4 @($sub | Where-Object { $_ -match '^rescate\(sonar\): lote \d' }).Count
  $dir = 'src/main/java/com/acme/plantillabatch/service/'
  Comprueba 'el codigo del culpable (ReciboService) vuelve a como estaba' ((Lee $e.Wt ($dir + 'ReciboService.java')) -notmatch '\+ 0;') ''
  Comprueba 'y los otros tres lotes siguen puestos' ((@('TotalService', 'PagoService', 'CobroService') | Where-Object { (Lee $e.Wt ($dir + $_ + '.java')) -match 'a \+ b \+ 0;' }).Count -eq 3) ''
  Igual 'la marca esta en el HEAD' (Head-M22 $e) (Marca-M22 $e)
  Igual 'el lote culpable no se reintenta: cuatro intentos de sonar y ninguno mas' 4 @((Intentos-M21 $e).Filas | Where-Object { $_.paso -eq 'sonar' }).Count
  $pend = @(Hallazgos-Sonar $e.Wt 'error')
  Igual 'su incidencia vuelve a pendiente (el codigo es el de antes)' 1 $pend.Count
  $k = @(Controles-M22 $e)
  Igual 'intentos.tsv: el primer control, revertido 1, y el segundo, verde' 'revertido 1 verde' ((@($k | ForEach-Object { $_.resultado })) -join ' ')
  $c = @(Llamadas-M22 $log)
  Igual 'la suite entera, cuatro veces: diagnostico, control rojo, la que confirma y el control del lote 4' 4 (Cuenta-M22 $c 'suite')
  $solas = @($c | Where-Object { $_.Tipo -eq 'solas' })
  Igual 'dos pasadas con -Dtest: en el HEAD y la de la biseccion' 2 $solas.Count
  Comprueba 'la de la biseccion corre en un worktree aparte' ($solas.Count -eq 2 -and $solas[0].Donde -ne $solas[1].Donde) (($solas | ForEach-Object { $_.Donde }) -join ' | ')
  Comprueba 'que no queda: ni worktree de control ni carpeta' (-not (Test-Path -LiteralPath (Get-Ruta $e.Wt '.rescate/control-wt')) -and ((GitEn $e.Wt @('worktree', 'list')) -split "`n").Count -eq 2) (GitEn $e.Wt @('worktree', 'list'))
}

$Pruebas['m22 (n): tras revertir el lote culpable, su incidencia de Sonar vuelve a pendiente en la base (sin resuelta, regla ni commit) y las de los otros tres siguen resueltas'] = {
  $x = Corre-E-M22 'm22-n'
  $e = $x.E
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $x.R.Salida); return }
  $ruta = Get-Ruta $e.Wt '.rescate/sonar-base.json'
  if (-not (Test-Path -LiteralPath $ruta -PathType Leaf)) { Comprueba 'existe .rescate/sonar-base.json' $false (Cola $x.R.Salida); return }
  $inc = @(([System.IO.File]::ReadAllText($ruta) | ConvertFrom-Json).incidencias)
  Igual 'cuatro incidencias en la base' 4 $inc.Count
  $rec = @($inc | Where-Object { $_.fichero -like '*ReciboService.java' })
  Igual 'la del lote revertido (ReciboService) no esta resuelta' 'False' "$($rec[0].resuelta)"
  Igual 'y no guarda el commit del lote' '' "$($rec[0].commit)"
  Igual 'ni la regla con la que se arreglo' '' "$($rec[0].regla)"
  $otras = @($inc | Where-Object { $_.fichero -notlike '*ReciboService.java' })
  Igual 'las otras tres siguen resueltas y con el commit de su lote' 3 @($otras | Where-Object { $_.resuelta -eq $true -and "$($_.commit)" -match '^[0-9a-f]{40}$' }).Count
}

$Pruebas['m22 (e2): las pasadas de Maven de un control rojo con un culpable: 4 lotes sin controles intermedios'] = {
  $cl = @('service/TotalService', 'service/ReciboService', 'service/PagoService', 'service/CobroService')
  $t = @{ AppContextTest = (Test-Java-M22 'AppContextTest' 'M22_FALLA_CON:PagoService' '@SpringBootTest') }
  $e = Escenario-M22 'm22-e2' $cl $t
  $log = Join-Path $e.Raiz 'mvn-m22.log'
  $r = Lanza-M22 $e $log
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  $c = @(Llamadas-M22 $log)
  $desdeCtl = @($c | Select-Object -Skip (1 + (Cuenta-M22 $c 'parcial')))   # lo que va despues del diagnostico y de los cuatro lotes
  Igual 'cuatro lotes: cuatro Maven parciales' 4 (Cuenta-M22 $c 'parcial')
  Igual 'el control rojo: la suite, las clases en el HEAD, 2 de biseccion (4 commits) y la suite que confirma: 5 pasadas' 5 $desdeCtl.Count
  Igual 'en este orden' 'suite solas solas solas suite' ((@($desdeCtl | ForEach-Object { $_.Tipo })) -join ' ')
  Igual 'el culpable es el lote 3 (PagoService revertido)' 'ok' $(if ((Lee $e.Wt 'src/main/java/com/acme/plantillabatch/service/PagoService.java') -notmatch '\+ 0;' -and (Lee $e.Wt 'src/main/java/com/acme/plantillabatch/service/CobroService.java') -match '\+ 0;') { 'ok' } else { 'no' })
  Igual 'la marca esta en el HEAD' (Head-M22 $e) (Marca-M22 $e)
  Igual 'una sola linea de control: revertido 1' 'revertido 1' ((@(Controles-M22 $e | ForEach-Object { $_.resultado })) -join ' ')
}

$Pruebas['m22 (e3): revertir un lote que choca con uno posterior da conflicto: se aborta y el arbol queda limpio; revertir los dos, del mas nuevo al mas viejo, lo deja como antes'] = {
  $d = Join-Path $Dir 'm22-e3'
  if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force }
  Escribe $d 'f.txt' "uno`ndos`ntres`n"
  Inicia-Repo $d
  Escribe $d 'f.txt' "uno`nDOS`ntres`n"; [void](GitEn $d @('commit', '-q', '-am', 'rescate(sonar): lote 1'))
  $c1 = (GitEn $d @('rev-parse', 'HEAD')).Trim()
  Escribe $d 'f.txt' "uno`nDOS-DOS`ntres`n"; [void](GitEn $d @('commit', '-q', '-am', 'rescate(sonar): lote 2'))
  $c2 = (GitEn $d @('rev-parse', 'HEAD')).Trim()
  function Invoke-Git([string]$D, [string[]]$A) {
    $ErrorActionPreference = 'Continue'
    $o = & git -C $D @A 2>&1 | ForEach-Object { "$_" }
    return [pscustomobject]@{ Codigo = $LASTEXITCODE; Salida = @($o) }
  }
  $RepoRoot = $d
  $Cfg = @{ CommitArgs = @() }
  . ([scriptblock]::Create((Texto-De-Funciones @('Undo-LotesGit'))))
  $ok1 = Undo-LotesGit @($c1) 'revierte uno'
  Igual 'revertir solo el lote 1 da conflicto: devuelve falso' 'False' "$ok1"
  Igual 'el HEAD no se mueve' $c2 (GitEn $d @('rev-parse', 'HEAD')).Trim()
  Igual 'y el arbol queda limpio (nada a medias)' '' (GitEn $d @('status', '--porcelain')).Trim()
  $ok2 = Undo-LotesGit @($c2, $c1) 'revierte dos'
  Igual 'revertir los dos, del mas nuevo al mas viejo: devuelve cierto' 'True' "$ok2"
  Igual 'el fichero vuelve a como era antes de los dos' "uno`ndos`ntres`n" (Lee $d 'f.txt')
  Igual 'con un commit nuevo encima de los dos' '3' (GitEn $d @('rev-list', '--count', "$c1^..HEAD")).Trim()
  Igual 'y el arbol limpio' '' (GitEn $d @('status', '--porcelain')).Trim()
}

$Pruebas['m22 (m): un commit que no es de un lote (arreglo a mano) deja la marca sin valor: la siguiente pasada no empieza con un control y el commit sigue en la rama'] = {
  $e = Escenario-M22 'm22-m' @('service/TotalService', 'service/ReciboService') $CtxM22
  $log1 = Join-Path $e.Raiz 'mvn-m22-1.log'
  $r1 = Lanza-M22 $e $log1 @('-MaxLotes', '1')
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r1.Salida); return }
  Igual 'la primera pasada deja la marca en el HEAD' (Head-M22 $e) (Marca-M22 $e)
  $marca = Marca-M22 $e
  Escribe $e.Wt 'NOTAS.md' 'lo he tocado yo'
  [void](GitEn $e.Wt @('add', '--', 'NOTAS.md'))
  [void](GitEn $e.Wt @('commit', '-q', '-m', 'arreglo a mano'))
  $log2 = Join-Path $e.Raiz 'mvn-m22-2.log'
  $r2 = Lanza-M22 $e $log2
  Igual 'la segunda pasada sale con 0' 0 $r2.Codigo
  Comprueba 'dice que la marca ya no vale' ($r2.Salida -match 'La marca del ultimo control ya no vale') (Cola $r2.Salida)
  Comprueba 'y no empieza con un control' ($r2.Salida -notmatch 'empiezo con un control') (Cola $r2.Salida)
  Igual 'ningun control en el lote 0: solo el del final de cada pasada' '1 1' ((@(Controles-M22 $e | ForEach-Object { $_.lote })) -join ' ')
  $sub = @((GitEn $e.Wt @('log', '--format=%s')) -split "`n")
  Igual 'el commit a mano sigue en la rama' 1 @($sub | Where-Object { $_ -eq 'arreglo a mano' }).Count
  Igual 'y no hay ningun revert' 0 @($sub | Where-Object { $_ -match '^rescate\(control\): ' }).Count
  Comprueba 'el commit a mano es ancestro del HEAD y la marca esta en el HEAD' ((Head-M22 $e) -eq (Marca-M22 $e) -and (Marca-M22 $e) -ne $marca) ''
}

$Pruebas['m22 (o): un lote hace que se ejecuten menos tests (sin tocar los tests): el control sale rojo por la cuenta, revierte los lotes desde la marca y la suite vuelve a pasar'] = {
  $t = @{ AppContextTest = (Test-Java-M22 'AppContextTest' 'M22_SALTA_CON:ReciboService' '@SpringBootTest') }
  $e = Escenario-M22 'm22-o' @('service/TotalService', 'service/ReciboService') $t @{ LotesEntreControles = 2 }
  $log = Join-Path $e.Raiz 'mvn-m22.log'
  $r = Lanza-M22 $e $log
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  Igual 'los dos lotes pasan sus puertas (el de contexto no corre en el lote)' 2 @([regex]::Matches($r.Salida, "Lote \d OK: 'sonar'")).Count
  Comprueba 'el control dice que se ejecutan menos tests que en el ultimo control (2 -> 1)' ($r.Salida -match 'se ejecutan menos tests que en el ultimo control \(2 -> 1\)') (Cola $r.Salida)
  Comprueba 'y revierte todos los lotes desde la marca' ($r.Salida -match 'revierto todos los lotes desde la marca \(2\)') (Cola $r.Salida)
  $k = @(Controles-M22 $e)
  Igual 'intentos.tsv: un control, revertido 2' 'revertido 2' ((@($k | ForEach-Object { $_.resultado })) -join ' ')
  Comprueba 'con la puerta que lo explica' ($k.Count -eq 1 -and $k[0].puerta -match 'se ejecutan menos tests') (($k | ForEach-Object { $_.puerta }) -join ' ')
  $dir = 'src/main/java/com/acme/plantillabatch/service/'
  Comprueba 'el codigo de los dos lotes vuelve a como estaba' ((@('TotalService', 'ReciboService') | Where-Object { (Lee $e.Wt ($dir + $_ + '.java')) -match '\+ 0;' }).Count -eq 0) ''
  Igual 'la marca esta en el HEAD (la suite vuelve a pasar con los dos tests)' (Head-M22 $e) (Marca-M22 $e)
}

$Pruebas['m22 (f): un test inestable (falla en la suite del control y pasa solo) deja el control en verde, con el aviso'] = {
  $t = @{ AppContextTest = (Test-Java-M22 'AppContextTest' 'M22_INESTABLE:2' '@SpringBootTest') }
  $e = Escenario-M22 'm22-f' @('service/TotalService', 'service/ReciboService') $t @{ LotesEntreControles = 2 }
  $log = Join-Path $e.Raiz 'mvn-m22.log'
  $r = Lanza-M22 $e $log
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  Igual 'sale con 0' 0 $r.Codigo
  Comprueba 'el aviso dice que el test es inestable y cual' ($r.Salida -match 'inestable.*AppContextTest|AppContextTest.*inestable') (Cola $r.Salida)
  $c = @(Llamadas-M22 $log)
  Igual 'la suite entera tres veces: el diagnostico, el control (rojo) y la repeticion' 3 (Cuenta-M22 $c 'suite')
  Igual 'y una pasada de la clase sola' 1 (Cuenta-M22 $c 'solas')
  Igual 'ningun revert' 0 @((GitEn $e.Wt @('log', '--format=%s')) -split "`n" | Where-Object { $_ -match '^rescate\(control\)' }).Count
  Igual 'la marca esta en el HEAD' (Head-M22 $e) (Marca-M22 $e)
  Igual 'intentos.tsv: el control en verde' 'verde' ((@(Controles-M22 $e | ForEach-Object { $_.resultado })) -join ' ')
}

$Pruebas['m22 (g): un test que fallaba en el ultimo control y sigue fallando no para ningun lote; uno nuevo que falla en un ligero si lo para'] = {
  $t = @{
    AppContextTest = (Test-Java-M22 'AppContextTest' '' '@SpringBootTest')
    FallaTest      = (Test-Java-M22 'FallaTest' 'M22_FALLA' '')
    RotoTest       = (Test-Java-M22 'RotoTest' 'M22_FALLA_CON:ReciboService' '')
  }
  $e = Escenario-M22 'm22-g' @('service/TotalService', 'service/ReciboService') $t
  $log = Join-Path $e.Raiz 'mvn-m22.log'
  $r = Lanza-M22 $e $log
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  Comprueba 'lote 1: FallaTest fallaba desde el principio y sigue: el lote pasa' ($r.Salida -match "Lote 1 OK: 'sonar'") (Cola $r.Salida)
  Comprueba 'lote 2: rompe RotoTest, un ligero que no fallaba: no pasa, con el test en el mensaje' ($r.Salida -match 'NO PASA: .*[Ff]alla un test que no fallaba en el ultimo control.*RotoTestMetodo en com\.acme\.plantillabatch\.RotoTest') (Cola $r.Salida)
  Comprueba 'y el lote 2 se deshace' ($r.Salida -match 'Lote 2 DESHECHO') (Cola $r.Salida)
  Comprueba 'ya no sale la puerta de las cuentas' ($r.Salida -notmatch 'Hay mas tests fallando que antes') (Cola $r.Salida)
  $parc = @(Llamadas-M22 $log | Where-Object { $_.Tipo -eq 'parcial' })
  Comprueba 'el lote ejecuta los ligeros (con FallaTest y RotoTest) y deja fuera el de contexto' ($parc.Count -ge 1 -and (@($parc[0].Clases -split ',') | Sort-Object) -join ',' -eq 'FallaTest,RotoTest,TotalServiceTest') (($parc | ForEach-Object { $_.Clases }) -join ' | ')
  Igual 'el control del final lo deja pasar: el unico que falla es el de antes' 'verde' ((@(Controles-M22 $e | ForEach-Object { $_.resultado })) -join ' ')
}

$Pruebas['m22 (h): una pasada que se corta tras 3 lotes sin control dice cuantos quedan sin comprobar, y la siguiente empieza con un control'] = {
  $cl = @('service/TotalService', 'service/ReciboService', 'service/PagoService', 'service/CobroService')
  $e = Escenario-M22 'm22-h' $cl $CtxM22
  # el corte: la 4.a llamada al modelo toca la carpeta del repo original (-Legacy): el script lo ve, deshace ese lote y para con ALTO
  $orig = Join-Path $e.Raiz 'original'
  Escribe $orig 'leeme.txt' 'el repo original'
  $log1 = Join-Path $e.Raiz 'mvn-m22-1.log'
  $r1 = Lanza-M22 $e $log1 @('-Legacy', $orig) @{ RESCATE_M22_CORTA = '4'; RESCATE_M22_TOCA = $orig }
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r1.Salida); return }
  Igual 'la pasada para con 4 (ALTO)' 4 $r1.Codigo
  $m1 = Marca-M22 $e
  $h1 = Head-M22 $e
  if ($m1.Length -lt 7) { Comprueba 'la pasada deja una marca' $false (Cola $r1.Salida); return }
  Igual 'tres lotes buenos antes del corte' 3 @([regex]::Matches($r1.Salida, "Lote \d OK: 'sonar'")).Count
  Comprueba "la consola dice: comprobado con la suite entera hasta <commit>; 3 lotes sin comprobar" ($r1.Salida -match ('comprobado con la suite entera hasta ' + $m1.Substring(0, 7) + '; 3 lotes sin comprobar')) (Cola $r1.Salida)
  Comprueba 'la marca se ha quedado atras' ($m1 -ne $h1) "marca=$m1 head=$h1"
  Igual 'sin ningun control en esa pasada' 0 @(Controles-M22 $e).Count
  $log2 = Join-Path $e.Raiz 'mvn-m22-2.log'
  $r2 = Lanza-M22 $e $log2
  Igual 'la siguiente pasada sale con 0' 0 $r2.Codigo
  Comprueba 'la siguiente pasada dice que empieza con un control' ($r2.Salida -match 'empiezo con un control') (Cola $r2.Salida)
  $k = @(Controles-M22 $e)
  Igual 'intentos.tsv: el control del principio (lote 0) y el del final (tras el lote 1 de esta pasada)' '0 1' ((@($k | ForEach-Object { $_.lote })) -join ' ')
  Igual 'los dos en verde' 'verde verde' ((@($k | ForEach-Object { $_.resultado })) -join ' ')
  $t = Intentos-M21 $e
  Igual 'el del principio va despues de las 3 lineas de la primera pasada' 'control' $t.Filas[3].paso
  Igual 'la marca esta en el HEAD' (Head-M22 $e) (Marca-M22 $e)
  Igual 'la suite entera, dos veces: el diagnostico (que hace de control) y el del final' 2 (Cuenta-M22 @(Llamadas-M22 $log2) 'suite')
}

$Pruebas['m22 (l): todos los tests con @Test son de contexto y hay un ayudante sin @Test: los lotes pasan sin el hallazgo de "ninguno ejecutado" y el control final pasa la suite entera'] = {
  $ayudante = "package com.acme.plantillabatch;`n`nclass TestDataFactory {`n    static int numero() {`n        return 1;`n    }`n}`n"
  $totalCtx = "package com.acme.plantillabatch.service;`n`nimport org.junit.jupiter.api.Test;`n`n@SpringBootTest`nclass TotalServiceTest {`n`n    @Test`n    void suma() {`n        int base = 1;`n    }`n}`n"
  $t = @{ AppContextTest = (Test-Java-M22 'AppContextTest' '' '@SpringBootTest'); 'service/TotalServiceTest' = $totalCtx; TestDataFactory = $ayudante }
  $e = Escenario-M22 'm22-l' @('service/TotalService', 'service/ReciboService') $t
  $log = Join-Path $e.Raiz 'mvn-m22.log'
  $r = Lanza-M22 $e $log
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'los dos lotes pasan' 2 @([regex]::Matches($r.Salida, "Lote \d OK: 'sonar'")).Count
  Comprueba 'no sale el hallazgo de que Maven no ha ejecutado ninguno' ($r.Salida -notmatch 'no ha ejecutado ninguno') (Cola $r.Salida)
  Comprueba 'ni el de un test que fallaba' ($r.Salida -notmatch 'Falla un test que no fallaba') (Cola $r.Salida)
  $c = @(Llamadas-M22 $log)
  Igual 'cada lote deja fuera todos los tests: 2 Maven parciales' 2 (Cuenta-M22 $c 'parcial')
  Igual 'la suite entera, dos veces: el diagnostico y el control del final' 2 (Cuenta-M22 $c 'suite')
  $k = @(Controles-M22 $e)
  Igual 'una linea de control, en verde y tras el lote 2' 'verde 2' ((@($k | ForEach-Object { $_.resultado + ' ' + $_.lote })) -join ' ')
  Igual 'la marca esta en el HEAD' (Head-M22 $e) (Marca-M22 $e)
}

$Pruebas['m22 (i): sin tests de contexto no hay control ni lista, y la marca se mueve con cada lote; con -SinTests, nada de esto'] = {
  $e = Escenario-M22 'm22-i' @('service/TotalService', 'service/ReciboService', 'service/PagoService')
  $log = Join-Path $e.Raiz 'mvn-m22.log'
  $r = Lanza-M22 $e $log @('-MaxLotes', '2')
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  $c = @(Llamadas-M22 $log)
  Igual 'ningun Maven con excludesFile: cada lote pasa la suite entera' 0 (Cuenta-M22 $c 'parcial')
  Igual 'el diagnostico y los dos lotes: tres suites' 3 (Cuenta-M22 $c 'suite')
  Igual 'ninguna linea de control en intentos.tsv' 0 @(Controles-M22 $e).Count
  Comprueba 'ni lista de contexto' (-not (Test-Path -LiteralPath (Get-Ruta $e.Wt '.rescate/tests-de-contexto.txt'))) ''
  Igual 'dos lotes' 2 @([regex]::Matches($r.Salida, "Lote \d OK: 'sonar'")).Count
  Igual 'la marca esta en el HEAD (se movio con cada lote, no hay control)' (Head-M22 $e) (Marca-M22 $e)
  # -SinTests: ni lista ni marca ni excludesFile
  $e2 = Escenario-M22 'm22-i2' @('service/TotalService') $CtxM22
  $log2 = Join-Path $e2.Raiz 'mvn-m22.log'
  $r2 = Lanza-M22 $e2 $log2 @('-SinTests')
  Comprueba '-SinTests: el lote pasa y no se pasa ningun test' ($r2.Salida -match "Lote 1 OK: 'sonar'" -and @(Llamadas-M22 $log2).Count -eq 0) (Cola $r2.Salida)
  Comprueba '-SinTests: sin lista ni marca' (-not (Test-Path -LiteralPath (Get-Ruta $e2.Wt '.rescate/tests-de-contexto.txt')) -and -not (Marca-M22 $e2)) ''
}

$Pruebas['m22 (k): si el control sigue rojo tras las rondas, revierte todos los lotes desde la marca y lo dice en rojo'] = {
  $t = @{
    Ctx1Test = (Test-Java-M22 'Ctx1Test' 'M22_FALLA_CON:TotalService' '@SpringBootTest')
    Ctx2Test = (Test-Java-M22 'Ctx2Test' 'M22_FALLA_CON:ReciboService' '@SpringBootTest')
  }
  $e = Escenario-M22 'm22-k' @('service/TotalService', 'service/ReciboService', 'service/PagoService') $t @{ ControlRondas = 1 }
  $log = Join-Path $e.Raiz 'mvn-m22.log'
  $r = Lanza-M22 $e $log
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  Comprueba 'la consola dice que revierte todos los lotes desde la marca' ($r.Salida -match 'revierto todos los lotes') (Cola $r.Salida)
  $dir = 'src/main/java/com/acme/plantillabatch/service/'
  Comprueba 'ninguno de los tres lotes queda en el codigo' ((@('TotalService', 'ReciboService', 'PagoService') | Where-Object { (Lee $e.Wt ($dir + $_ + '.java')) -match '\+ 0;' }).Count -eq 0) ''
  Igual 'intentos.tsv: revertido 3' 'revertido 3' ((@(Controles-M22 $e | ForEach-Object { $_.resultado })) -join ' ')
  Igual 'la marca esta en el HEAD (el arbol es el de la marca y la suite lo confirma)' (Head-M22 $e) (Marca-M22 $e)
  $c = @(Llamadas-M22 $log)
  Igual 'la suite: el diagnostico, el control, la de despues del primer revert y la de despues de revertirlo todo' 4 (Cuenta-M22 $c 'suite')
}

$Pruebas['m22 (k2): si tras revertirlo todo la suite sigue en rojo, el control sale rojo: la marca no se mueve y el script sale con 2'] = {
  $t = @{ AppContextTest = (Test-Java-M22 'AppContextTest' 'M22_FALLA_DESDE:2' '@SpringBootTest') }
  $e = Escenario-M22 'm22-k2' @('service/TotalService', 'service/ReciboService') $t
  $log = Join-Path $e.Raiz 'mvn-m22.log'
  $r = Lanza-M22 $e $log
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  Igual 'sale con 2' 2 $r.Codigo
  Comprueba 'dice en rojo que el HEAD no ha pasado la suite entera' ($r.Salida -match 'no ha pasado la suite entera') (Cola $r.Salida)
  Igual 'intentos.tsv: rojo' 'rojo' ((@(Controles-M22 $e | ForEach-Object { $_.resultado })) -join ' ')
  Comprueba 'la marca no se mueve: sigue donde estaba' ((Marca-M22 $e) -and (Marca-M22 $e) -ne (Head-M22 $e)) ''
}

$Pruebas['m22: todo en ASCII (el falso nuevo)'] = {
  $f = Join-Path $falsos 'm22-mvn.ps1'
  Igual 'sin bytes fuera de ASCII en m22-mvn.ps1' 0 @([System.IO.File]::ReadAllBytes($f) | Where-Object { $_ -gt 127 }).Count
}

# ===== M23: EL PASO CALIDAD PUEDE IR COMO SONAR (SOLO COMPILA Y TESTS ELEGIDOS), ACTIVANDOLO EN config.json =====
# Reutilizan Escenario-Sonar, el Maven de m22 (m22-mvn.ps1) y los ayudantes de M21 y M22 (Lanza-M22, Llamadas-M22, Marca-M22, Controles-M22...). El Copilot de
# mentira es m23-copilot.ps1: en calidad pone un Javadoc a lo que el prompt marca (con RESCATE_M23_ROMPE=<Clase> deja ademas ' + 0;' en esa clase, que es lo
# que hace fallar su test de contexto en m22-mvn.ps1) y en build quita NO_COMPILA; en lo demas es el de m22.
$M23Config = @{ PasosSoloCompila = @('sonar', 'calidad'); PasosTestsElegidos = @('sonar', 'calidad') }

# Un repo con clases sin Javadoc (las de $SinDoc, dos errores de calidad cada una) y el config.json de arriba: calidad va como sonar.
function Escenario-M23([string]$Nombre, [string[]]$SinDoc, [hashtable]$Tests = @{}, [hashtable]$Mas = @{}, [hashtable]$Extra = @{}) {
  $cfg = @{ MvnExe = $M22Mvn; CopilotExe = (Join-Path $falsos 'm23-copilot.ps1') }
  foreach ($k in $M23Config.Keys) { $cfg[$k] = $M23Config[$k] }
  foreach ($k in $Mas.Keys) { $cfg[$k] = $Mas[$k] }
  $ficheros = @{}
  foreach ($k in $Tests.Keys) { $ficheros['/' + $M22Dir + $k + '.java'] = $Tests[$k] }
  foreach ($k in $Extra.Keys) { $ficheros[$k] = $Extra[$k] }
  return (Escenario-Sonar $Nombre @('service/TotalService') $cfg $SinDoc $ficheros)
}

# Lanza el fix del escenario (lotes de un fichero, sin -Sonar), con el registro de Maven de M22. $Mas: -Paso calidad o -Todo. $Env: variables de entorno mientras dura.
function Lanza-M23($E, [string]$Registro, [string[]]$Mas, [hashtable]$Env = @{}) {
  $a = @('-Modo', 'fix', '-Si', '-MaxIntentos', '1', '-Lote', '1') + $Mas
  $env:RESCATE_M22_LOG = $Registro
  $env:RESCATE_M22_ESTADO = Join-Path $E.Raiz 'estado'
  foreach ($k in $Env.Keys) { Set-Item -Path ('Env:' + $k) -Value $Env[$k] }
  try { return (Sonar-Lanza $E $a) }
  finally { Remove-Item (@('Env:RESCATE_M22_LOG', 'Env:RESCATE_M22_ESTADO') + @($Env.Keys | ForEach-Object { 'Env:' + $_ })) -ErrorAction SilentlyContinue }
}

# Nada de lo especifico de Sonar se escribe en un paso que no es sonar.
function Sin-Sonar-M23($E) {
  return (@('sonar-base.json', 'sonar-faltan.md', 'sonar-por-familia.tsv') | Where-Object { Test-Path -LiteralPath (Get-Ruta $E.Wt ('.rescate/' + $_)) }).Count -eq 0
}

$Pruebas['m23 (a): con calidad en las dos listas de config.json, dos lotes buenos: el prompt solo compila, las puertas llevan el excludesFile y un control cierra la pasada'] = {
  $e = Escenario-M23 'm23-a' @('service/SinDoc1', 'service/SinDoc2') $CtxM22
  $log = Join-Path $e.Raiz 'mvn-m22.log'
  $r = Lanza-M23 $e $log @('-Paso', 'calidad')
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  Igual 'sale con 0' 0 $r.Codigo
  Igual 'dos lotes buenos de calidad' 2 @([regex]::Matches($r.Salida, "Lote \d OK: 'calidad'")).Count
  $prompt = Lee $e.Wt '.rescate/prompt.md'
  Comprueba 'el prompt lleva la orden de compilar y dice que los tests los pasa el script' ($prompt -match '(?m)^- Ejecuta: .* -q -B -DskipTests test-compile  y corrige hasta que compile\. Los tests los pasa el script despues\.$') $prompt
  Comprueba 'y no lleva la orden de los tests' ($prompt -notmatch 'DskipTests=false' -and $prompt -notmatch 'corrige los tests que fallen') $prompt
  $c = @(Llamadas-M22 $log)
  $parc = @($c | Where-Object { $_.Tipo -eq 'parcial' })
  Igual 'cada lote pasa las puertas con el excludesFile de la lista de contexto: 2 Maven parciales' 2 $parc.Count
  Comprueba 'con -Dsurefire.excludesFile y solo el test ligero' (@($parc | Where-Object { $_.Args -match '-Dsurefire\.excludesFile=\S*tests-de-contexto\.txt' -and $_.Clases -eq 'TotalServiceTest' }).Count -eq 2) (($c | ForEach-Object { $_.Tipo + ': ' + $_.Clases + ' ' + $_.Args }) -join ' // ')
  Igual 'la suite entera, dos veces: el diagnostico de antes y el control final' 2 (Cuenta-M22 $c 'suite')
  Igual 'la marca refs/rescate/control-ok esta en el HEAD' (Head-M22 $e) (Marca-M22 $e)
  $k = @(Controles-M22 $e)
  Igual 'intentos.tsv lleva una linea de control, verde, tras el lote 2' 'verde 2' ((@($k | ForEach-Object { $_.resultado + ' ' + $_.lote })) -join ' ')
  $t = Intentos-M21 $e
  Igual 'y dos lineas de intento del paso calidad' 2 @($t.Filas | Where-Object { $_.paso -eq 'calidad' -and $_.resultado -eq 'pasa' }).Count
  Comprueba 'nada de lo de Sonar: ni base, ni faltan, ni familias' (Sin-Sonar-M23 $e) (Cola $r.Salida)
}

$Pruebas['m23 (b): un lote de calidad rompe un test de contexto: el control sale rojo, la biseccion da ese lote, se revierte y su fichero no se reintenta'] = {
  $t = @{ AppContextTest = (Test-Java-M22 'AppContextTest' 'M22_FALLA_CON:SinDoc2' '@SpringBootTest') }
  $e = Escenario-M23 'm23-b' @('service/SinDoc1', 'service/SinDoc2', 'service/SinDoc3') $t
  $log = Join-Path $e.Raiz 'mvn-m22.log'
  $r = Lanza-M23 $e $log @('-Paso', 'calidad') @{ RESCATE_M23_ROMPE = 'SinDoc2' }
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  Igual 'sale con 0: la pasada no falla' 0 $r.Codigo
  Igual 'los tres lotes pasan sus puertas (el test de contexto no se ejecuta en el lote)' 3 @([regex]::Matches($r.Salida, "Lote \d OK: 'calidad'")).Count
  Comprueba 'la consola dice que el lote rompe el test de contexto en el control' ($r.Salida -match 'rompe com\.acme\.plantillabatch\.AppContextTest en el control') (Cola $r.Salida)
  Comprueba 'y que el fichero no se vuelve a intentar en esta pasada' ($r.Salida -match 'SinDoc2\.java: .*no se vuelve a intentar') (Cola $r.Salida)
  $sub = @((GitEn $e.Wt @('log', '--format=%s')) -split "`n")
  Igual 'un commit de revert del control' 1 @($sub | Where-Object { $_ -match '^rescate\(control\): ' }).Count
  Igual 'los tres lotes siguen en la rama' 3 @($sub | Where-Object { $_ -match '^rescate\(calidad\): lote \d' }).Count
  $dir = 'src/main/java/com/acme/plantillabatch/service/'
  Comprueba 'SinDoc2 vuelve a como estaba: ni su Javadoc ni su cambio' ((Lee $e.Wt ($dir + 'SinDoc2.java')) -notmatch '/\*\* Documentado' -and (Lee $e.Wt ($dir + 'SinDoc2.java')) -notmatch '\+ 0;') ''
  Comprueba 'SinDoc1 y SinDoc3 siguen con su Javadoc' ((@('SinDoc1', 'SinDoc3') | Where-Object { (Lee $e.Wt ($dir + $_ + '.java')) -match '/\*\* Documentado' }).Count -eq 2) ''
  Igual 'el lote culpable no se reintenta: tres intentos de calidad y ninguno mas' 3 @((Intentos-M21 $e).Filas | Where-Object { $_.paso -eq 'calidad' }).Count
  Igual 'sus dos errores de calidad vuelven a pendientes' 2 (Cuenta (Hallazgos $e.Wt) 'calidad')
  Igual 'intentos.tsv: un control, revertido 1' 'revertido 1' ((@(Controles-M22 $e | ForEach-Object { $_.resultado })) -join ' ')
  Igual 'la marca esta en el HEAD' (Head-M22 $e) (Marca-M22 $e)
  $solas = @(Llamadas-M22 $log | Where-Object { $_.Tipo -eq 'solas' })
  Igual 'tres pasadas con -Dtest: en el HEAD y las dos de la biseccion entre tres lotes' 3 $solas.Count
  Comprueba 'nada de lo de Sonar: ni base, ni faltan, ni familias' (Sin-Sonar-M23 $e) (Cola $r.Salida)
}

$Pruebas['m23 (c): con -Todo, el paso anterior a calidad (build) pasa la suite entera en cada lote y calidad solo los ligeros'] = {
  $roto = 'src/main/java/com/acme/plantillabatch/service/Roto.java'
  $texto = "package com.acme.plantillabatch.service;`n`n/** Roto. */`npublic class Roto {`n    // NO_COMPILA`n}`n"
  # Orden reducido a build y calidad (como m10 -Todo): el paso anterior a calidad es build
  $e = Escenario-M23 'm23-c' @('service/SinDoc1', 'service/SinDoc2') $CtxM22 @{ Orden = @('build', 'calidad') } @{ ('/' + $roto) = $texto }
  $log = Join-Path $e.Raiz 'mvn-m22.log'
  $r = Lanza-M23 $e $log @('-Todo', '-SinPlan')
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r.Salida); return }
  Igual 'sale con 0' 0 $r.Codigo
  Comprueba 'el lote de build pasa' ($r.Salida -match "Lote 1 OK: 'build'") (Cola $r.Salida)
  Igual 'y los dos de calidad' 2 @([regex]::Matches($r.Salida, "Lote \d OK: 'calidad'")).Count
  $c = @(Llamadas-M22 $log)
  Igual 'Maven con tests, en orden: el diagnostico (no compila), el lote de build, los dos de calidad y el control final' 'suite suite parcial parcial suite' ((@($c | ForEach-Object { $_.Tipo })) -join ' ')
  Igual 'el lote de build pasa la suite entera, la de contexto tambien' 'AppContextTest,TotalServiceTest' ((@($c[1].Clases -split ',') | Sort-Object) -join ',')
  Igual 'la marca esta en el HEAD' (Head-M22 $e) (Marca-M22 $e)
}

$Pruebas['m23 (d): migracion.ps1 lanza rescate.ps1 sobre el worktree (-Repo <migrado>-rescate): manda el config.json del worktree y no el del migrado'] = {
  # el migrado trae el config.json por defecto (calidad con el modelo pasando la suite entera) y el del worktree activa las dos listas
  $e = Escenario-M23 'm23-d' @('service/SinDoc1') $CtxM22 @{ PasosSoloCompila = @('sonar'); PasosTestsElegidos = @('sonar') }
  $r0 = Sonar-Lanza $e @('-Modo', 'fix', '-Paso', 'calidad', '-Si', '-MaxLotes', '0')   # solo crea el worktree
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false (Cola $r0.Salida); return }
  Config-Sonar ([pscustomobject]@{ Repo = $e.Wt }) @{ MvnExe = $M22Mvn; CopilotExe = (Join-Path $falsos 'm23-copilot.ps1'); PasosSoloCompila = @('sonar', 'calidad'); PasosTestsElegidos = @('sonar', 'calidad') }
  $log = Join-Path $e.Raiz 'mvn-m22.log'
  $env:RESCATE_M22_LOG = $log
  try { $r = Sonar-Lanza ([pscustomobject]@{ Repo = $e.Wt }) @('-Modo', 'fix', '-Paso', 'calidad', '-Si', '-MaxIntentos', '1', '-Lote', '1') }
  finally { Remove-Item 'Env:RESCATE_M22_LOG' -ErrorAction SilentlyContinue }
  Igual 'sale con 0' 0 $r.Codigo
  Comprueba 'el lote pasa' ($r.Salida -match "Lote 1 OK: 'calidad'") (Cola $r.Salida)
  Comprueba 'el prompt solo compila: manda el config.json del worktree' ((Lee $e.Wt '.rescate/prompt.md') -match 'Los tests los pasa el script despues\.') ''
  Comprueba 'y el lote pasa las puertas con el excludesFile' (Cuenta-M22 @(Llamadas-M22 $log) 'parcial' -eq 1) (Cola $r.Salida)
}

$Pruebas['m23: todo en ASCII (el falso nuevo)'] = {
  $f = Join-Path $falsos 'm23-copilot.ps1'
  Igual 'sin bytes fuera de ASCII en m23-copilot.ps1' 0 @([System.IO.File]::ReadAllBytes($f) | Where-Object { $_ -gt 127 }).Count
}

# ===================== LOS COMANDOS DEL FINAL SE PEGAN ENTEROS (m27) =====================
$Pruebas['m27 final del fix: las tres ordenes de git salen cada una en su linea, con git -C "<tu carpeta>" delante y la explicacion detras de #, para pegarlas enteras desde cualquier carpeta'] = {
  $e = Nuevo-Escenario 'm27-final'
  $r = Rescate @('-Modo', 'fix', '-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-Paso', 'estructura', '-SinPlan', '-Auto', '-Si')
  Igual 'el fix sale con 0' 0 $r.Codigo
  $ramaFin = GitEn $e.Wt @('rev-parse', '--abbrev-ref', 'HEAD')
  $lineas = @($r.Salida -split "`n" | Where-Object { $_ -match 'diff --stat|merge rescate/|worktree remove' })
  Igual 'tres lineas: ver lo que ha cambiado, traerlo y borrar el worktree' 3 $lineas.Count
  Comprueba 'cada una empieza por git -C " (solo espacios delante)' (@($lineas | Where-Object { $_ -match '^\s*git -C "' }).Count -eq 3) ($lineas -join ' / ')
  Comprueba 'con la carpeta del usuario entre comillas' (@($lineas | Where-Object { $_ -match ('^\s*git -C "' + [regex]::Escape($e.Repo) + '" ') }).Count -eq 3) ($lineas -join ' / ')
  Comprueba 'y la explicacion detras de #, tras una orden que acaba antes' (@($lineas | Where-Object { $_ -match '^\s*git -C "[^"]+" \S.*\S\s+# \S' }).Count -eq 3) ($lineas -join ' / ')
  Comprueba 'ver: diff --stat con la rama de la carpeta y la de rescate' ($lineas[0] -match ('^\s*git -C "[^"]+" diff --stat main\.\.\.' + [regex]::Escape($ramaFin) + '\s+# ver que ha cambiado$')) $lineas[0]
  Comprueba 'traer: merge, con la alternativa del PR en el comentario' ($lineas[1] -match ('^\s*git -C "[^"]+" merge ' + [regex]::Escape($ramaFin) + '\s+# traerlo a tu rama \(o sube la rama y abre un PR\)$')) $lineas[1]
  Comprueba 'borrar: worktree remove, que se haga al acabar con prueba-local.ps1 y que la rama se conserva' ($lineas[2] -match ('^\s*git -C "[^"]+" worktree remove "' + [regex]::Escape($e.Wt) + '"\s+# borrar el worktree cuando acabes con prueba-local\.ps1 \(la rama se conserva\)$')) $lineas[2]
  Comprueba 'antes de ellas, la frase que dice que se copia cada linea entera' ($r.Salida -match 'Copia cada linea entera; lo que va detras de # es solo la explicacion') (Cola $r.Salida)
}

# ============== UNA RAMA DE RESCATE SIN UNIR IMPIDE CREAR OTRA (m41) ==============
$Pruebas['m41 (h) -Modo fix y -Modo plan con una rama rescate/<rama>-<fecha> sin unir y sin worktree: paran igual, sin crear nada y con las tres salidas'] = {
  $e = Nuevo-Escenario 'm41-h'
  $nombre = 'rescate/main-20250101-0000'
  $temporal = Join-Path (Split-Path -Parent $e.Repo) 'wt-temporal'
  # el usuario tuvo un worktree de rescate, hizo un arreglo y lo borro sin unir la rama
  [void](GitEn $e.Repo @('worktree', 'add', '-q', '-b', $nombre, $temporal, 'main'))
  Escribe $temporal 'notas/arreglo.txt' 'arreglo'
  [void](GitEn $temporal @('add', '--', 'notas/arreglo.txt'))
  [void](GitEn $temporal @('commit', '-q', '-m', 'rescate(estructura): lote 1, hallazgos 2 a 0'))
  [void](GitEn $e.Repo @('worktree', 'remove', '--force', $temporal))
  $ramas = GitEn $e.Repo @('branch', '--list')
  foreach ($modo in @('fix', 'plan')) {
    $a = @('-Modo', $modo, '-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-Paso', 'estructura', '-SinPlan', '-Auto', '-Si')
    if ($modo -eq 'plan') { $a = @('-Modo', 'plan', '-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-Paso', 'estructura', '-SinBuild', '-Si') }
    $r = Rescate $a
    Igual "$modo : sale con 1" 1 $r.Codigo
    Comprueba "$modo : nombra la rama y dice que no crea otra" ($r.Salida.Contains("Hay una rama de rescate con arreglos que no estan en tu rama: $nombre. No creo otra, para no dejarla olvidada.")) (Cola $r.Salida)
    Comprueba "$modo : unirla, seguir en ella y borrarla, con la carpeta entre comillas" ($r.Salida.Contains("git -C `"$($e.Repo)`" merge $nombre") -and $r.Salida.Contains("git -C `"$($e.Repo)`" worktree add `"$($e.Wt)`" $nombre") -and $r.Salida.Contains("git -C `"$($e.Repo)`" branch -D $nombre")) (Cola $r.Salida)
    Comprueba "$modo : y que despues se lance el mismo comando" ($r.Salida.Contains('Despues, lanza el mismo comando.')) (Cola $r.Salida)
    Igual "$modo : la lista de ramas no cambia" $ramas (GitEn $e.Repo @('branch', '--list'))
    Comprueba "$modo : no hay worktree" (-not (Test-Path -LiteralPath $e.Wt))
  }
  # unida a la rama del usuario, ya no impide nada
  [void](GitEn $e.Repo @('merge', '-q', '--no-edit', $nombre))
  $r = Rescate @('-Modo', 'fix', '-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-Paso', 'estructura', '-SinPlan', '-Auto', '-Si')
  Igual 'con la rama unida el fix sale con 0' 0 $r.Codigo
  Comprueba 'y crea el worktree' (Test-Path -LiteralPath (Join-Path $e.Wt '.git')) (Cola $r.Salida)
}

$Pruebas['m41 (i) la rama de rescate sin unir de OTRA rama (main-2, que tambien empieza por rescate/main-) no para a quien esta en main'] = {
  $e = Nuevo-Escenario 'm41-i'
  $otra = 'rescate/main-2-20250101-0000'
  $temporal = Join-Path (Split-Path -Parent $e.Repo) 'wt-temporal'
  [void](GitEn $e.Repo @('worktree', 'add', '-q', '-b', $otra, $temporal, 'main'))
  Escribe $temporal 'notas/arreglo.txt' 'arreglo'
  [void](GitEn $temporal @('add', '--', 'notas/arreglo.txt'))
  [void](GitEn $temporal @('commit', '-q', '-m', 'rescate(estructura): lote 1, hallazgos 2 a 0'))
  [void](GitEn $e.Repo @('worktree', 'remove', '--force', $temporal))
  $r = Rescate @('-Modo', 'fix', '-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-Paso', 'estructura', '-SinPlan', '-Auto', '-Si')
  Igual 'el fix sale con 0' 0 $r.Codigo
  Comprueba 'no habla de una rama de rescate sin unir' (-not $r.Salida.Contains('Hay una rama de rescate con arreglos')) (Cola $r.Salida)
  Comprueba 'y crea el worktree' (Test-Path -LiteralPath (Join-Path $e.Wt '.git')) (Cola $r.Salida)
}

# ============== LA CARPETA DE RESCATE QUE NO ES UN WORKTREE NO SE MANDA BORRAR (m45) ==============
$Pruebas['m45 (h) una carpeta que ya existe y no es un worktree de rescate: el texto manda mirar si tiene algo tuyo y moverla, no borrarla; la carpeta queda como estaba'] = {
  $e = Nuevo-Escenario 'm45-h'
  Escribe $e.Wt 'notas-del-usuario.txt' 'a medias'
  $r = Rescate @('-Modo', 'fix', '-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-Paso', 'estructura', '-SinPlan', '-Auto', '-Si')
  Igual 'sale con 1' 1 $r.Codigo
  Comprueba 'dice que la carpeta ya existe y no es un worktree de rescate de este repo' ($r.Salida.Contains("La carpeta '$($e.Wt)' ya existe y no es un worktree de rescate de este repo.")) (Cola $r.Salida)
  Comprueba 'manda mirar antes si tiene algo suyo, con la carpeta entre comillas' ($r.Salida.Contains("Mira antes si tiene algo tuyo (git -C `"$($e.Wt)`" status); despues, muevela o elige otra con -Worktree.")) (Cola $r.Salida)
  Comprueba 'ya no dice Borrala' ($r.Salida -notmatch 'Borrala') (Cola $r.Salida)
  Igual 'el fichero de la carpeta sigue como estaba' 'a medias' (Lee $e.Wt 'notas-del-usuario.txt')
}

# ============== M70: REGLAS DE SPRING DE SONAR WAY Y ESTILO COHERENTE, EN LA CALIDAD (sin IA) ==============
# Clase de un escenario M70. $Cabeza lleva las anotaciones de la clase y $Miembros lo que hay dentro (4 espacios de sangria).
function Clase-M70([string]$Nombre, [string]$Cabeza, [string]$Miembros, [string]$Pkg = 'com.acme.life.application.usecases') {
  return "package $Pkg;`n`n/** Clase $Nombre. */`n$Cabeza`npublic class $Nombre {`n$Miembros}`n"
}

# Un constructor escrito: con su anotacion encima (vacia = ninguna) y sus parametros.
function Ctor-M70([string]$Nombre, [string]$Anot, [string]$Params) {
  $a = ''
  if ($Anot) { $a = "    $Anot`n" }
  return "$a    public $Nombre($Params) {`n    }`n`n"
}

# Una clase con dependencias, con Lombok (@RequiredArgsConstructor) o con el constructor escrito a mano.
function Dependencias-M70([string]$Nombre, [bool]$Lombok, [string]$Pkg = 'com.acme.life.application.usecases') {
  if ($Lombok) { return (Clase-M70 $Nombre "@Service`n@RequiredArgsConstructor" "    private final String dep;`n" $Pkg) }
  return (Clase-M70 $Nombre '@Service' ("    private final String dep;`n`n" + (Ctor-M70 $Nombre '' 'String dep')) $Pkg)
}

# Una clase con un logger: 'slf4j' (@Slf4j), 'factory' (LoggerFactory), 'otro' (LogManager) o 'local' (LoggerFactory solo dentro de un metodo: no declara ninguno).
function Logger-M70([string]$Nombre, [string]$Estilo, [string]$Pkg = 'com.acme.life.application.usecases') {
  if ($Estilo -eq 'slf4j') { return (Clase-M70 $Nombre '@Slf4j' "    public void hace() {`n        log.info(`"hola`");`n    }`n" $Pkg) }
  if ($Estilo -eq 'factory') { return (Clase-M70 $Nombre '' "    private static final Logger LOG = LoggerFactory.getLogger($Nombre.class);`n" $Pkg) }
  if ($Estilo -eq 'otro') { return (Clase-M70 $Nombre '' "    private static final Logger LOG = LogManager.getLogger($Nombre.class);`n" $Pkg) }
  return (Clase-M70 $Nombre '' "    public void hace() {`n        Logger l = LoggerFactory.getLogger($Nombre.class);`n    }`n" $Pkg)
}

# Escenario con estos ficheros en el repo y en la plantilla (nombre -> texto). Con $Lombok el pom del repo lleva la dependencia de Lombok.
function Escenario-M70([string]$Nombre, $Repo, $Plantilla = @{}, [bool]$Lombok = $false) {
  $e = Nuevo-Escenario $Nombre
  foreach ($k in $Repo.Keys) { Escribe $e.Repo ('src/main/java/com/acme/life/application/usecases/' + $k + '.java') $Repo[$k] }
  foreach ($k in $Plantilla.Keys) { Escribe $e.Plantilla ('src/main/java/com/acme/plantilla/application/usecases/' + $k + '.java') $Plantilla[$k] }
  if ($Lombok) { Escribe $e.Repo 'pom.xml' ($Pom -replace '</dependencies>', "  <dependency><groupId>org.projectlombok</groupId><artifactId>lombok</artifactId></dependency>`n  </dependencies>") }
  return $e
}

# Diagnostico del escenario (sin Maven) y sus hallazgos de calidad de esa regla.
function Cal-M70($E, [string]$Regla) {
  [void](Rescate @('-Repo', $E.Repo, '-Plantilla', $E.Plantilla, '-SinBuild'))
  return @(Hallazgos $E.Repo | Where-Object { $_.Cat -eq 'calidad' -and $_.Detalle.StartsWith('[' + $Regla + ']') })
}

# Los ficheros de unos hallazgos, sin la extension, ordenados y unidos con espacios.
function Ficheros-M70($H) { return ((@($H | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Fichero) }) | Sort-Object) -join ' ') }

$Pruebas['m70 (a1) constructores-sin-autowired (S6829): dos constructores o mas y ninguno con @Autowired ni @Inject'] = {
  $externa = @'
package com.acme.life.application.usecases;

/** Una clase con otra dentro. */
@Component
public class Externa {

    public Externa(String a) {
    }

    /** Anidada que tambien es un bean. */
    @Configuration
    static class Anidada {

        Anidada() {
        }

        Anidada(String a) {
        }
    }
}
'@
  $dos = (Ctor-M70 'DosSin' '' '') + (Ctor-M70 'DosSin' '' 'String a')
  $e = Escenario-M70 'm70-a1' @{
    DosSin  = (Clase-M70 'DosSin' '@Component' $dos)
    DosAut  = (Clase-M70 'DosAut' '@Component' ((Ctor-M70 'DosAut' '' '') + (Ctor-M70 'DosAut' '@Autowired' 'String a')))
    DosInj  = (Clase-M70 'DosInj' '@Service' ((Ctor-M70 'DosInj' '@jakarta.inject.Inject' 'String a') + (Ctor-M70 'DosInj' '' '')))
    Uno     = (Clase-M70 'Uno' '@Component' (Ctor-M70 'Uno' '' 'String a'))
    Fuera   = (Clase-M70 'Fuera' '' ((Ctor-M70 'Fuera' '' '') + (Ctor-M70 'Fuera' '' 'String a')))
    Tres    = (Clase-M70 'Tres' '@RestController' ((Ctor-M70 'Tres' '' '') + (Ctor-M70 'Tres' '' 'String a') + (Ctor-M70 'Tres' '' 'String a, int b')))
    Externa = $externa
  }
  $h = Cal-M70 $e 'constructores-sin-autowired'
  Igual 'sale en la que tiene dos sin marcar, en la de tres y en la anidada (que cuenta aparte), y en ninguna mas' 'DosSin Externa Tres' (Ficheros-M70 $h)
  $d = @($h | Where-Object { $_.Fichero -like '*DosSin.java' })
  Igual 'es un error' 'error' $d[0].Sev
  Igual 'en la linea de la clase' (Linea-De (Lee $e.Repo 'src/main/java/com/acme/life/application/usecases/DosSin.java') 'public class DosSin') $d[0].Linea
  Comprueba 'dice cuantos constructores, cita a Sonar y da las dos salidas' ($d[0].Detalle -like '*2 constructores y ninguno con @Autowired*Sonar S6829*un solo constructor*marca con @Autowired*') $d[0].Detalle
  Comprueba 'el de tres dice 3' (@($h | Where-Object { $_.Fichero -like '*Tres.java' -and $_.Detalle -like '*3 constructores y ninguno*' }).Count -eq 1)
  $a = @($h | Where-Object { $_.Fichero -like '*Externa.java' })
  Igual 'la anidada sale en su propia linea, no en la de la externa' (Linea-De (Lee $e.Repo 'src/main/java/com/acme/life/application/usecases/Externa.java') 'static class Anidada') $a[0].Linea
  Comprueba 'y cuenta los suyos (2), no los de la externa' ($a[0].Detalle -like '*2 constructores*') $a[0].Detalle
  Igual 'ninguna sale como autowired-varios' 0 @(Hallazgos $e.Repo | Where-Object { $_.Detalle -like '`[autowired-varios`]*' }).Count
}

$Pruebas['m70 (a2) constructores-sin-autowired: cuentan los constructores de Lombok; una clase que no es un componente no cuenta'] = {
  $e = Escenario-M70 'm70-a2' @{
    Mixto      = (Clase-M70 'Mixto' "@Service`n@NoArgsConstructor" (Ctor-M70 'Mixto' '' 'String a'))
    SoloLombok = (Clase-M70 'SoloLombok' "@Service`n@RequiredArgsConstructor" "    private final String dep;`n")
    LombokAut  = (Clase-M70 'LombokAut' "@Service`n@NoArgsConstructor`n@RequiredArgsConstructor(onConstructor_ = @__(@Autowired))" "    private final String dep;`n")
    LombokDos  = (Clase-M70 'LombokDos' "@Component`n@NoArgsConstructor`n@AllArgsConstructor" "    private String dep;`n")
    Plana      = (Clase-M70 'Plana' "@NoArgsConstructor" (Ctor-M70 'Plana' '' 'String a'))
  }
  $h = Cal-M70 $e 'constructores-sin-autowired'
  Igual 'sale en el servicio con @NoArgsConstructor y un constructor escrito y en el que junta dos de Lombok' 'LombokDos Mixto' (Ficheros-M70 $h)
  Comprueba 'los cuenta: 2 constructores' (@($h | Where-Object { $_.Detalle -like '*2 constructores y ninguno*' }).Count -eq 2)
  Igual 'el @RequiredArgsConstructor con onConstructor_ @Autowired cuenta como marcado, y uno solo, un constructor, no sale; la clase sin anotacion de componente tampoco' 0 @($h | Where-Object { $_.Fichero -match 'SoloLombok|LombokAut|Plana' }).Count
}

$Pruebas['m70 (a3) autowired-varios (S6818): dos constructores o mas con @Autowired sin required = false'] = {
  $e = Escenario-M70 'm70-a3' @{
    DosAut  = (Clase-M70 'DosAut' '@Component' ((Ctor-M70 'DosAut' '@Autowired' 'String a') + (Ctor-M70 'DosAut' '@Autowired' 'String a, int b')))
    DosOpt  = (Clase-M70 'DosOpt' '@Component' ((Ctor-M70 'DosOpt' '@Autowired(required = false)' 'String a') + (Ctor-M70 'DosOpt' '@Autowired(required = false)' 'String a, int b')))
    UnoOpt  = (Clase-M70 'UnoOpt' '@Component' ((Ctor-M70 'UnoOpt' '@Autowired' 'String a') + (Ctor-M70 'UnoOpt' '@Autowired(required = false)' 'String a, int b')))
    SinTipo = (Clase-M70 'SinTipo' '' ((Ctor-M70 'SinTipo' '@Autowired' 'String a') + (Ctor-M70 'SinTipo' '@Autowired' 'String a, int b')))
  }
  $h = Cal-M70 $e 'autowired-varios'
  Igual 'sale con dos @Autowired y no con required = false (en los dos, o en uno de los dos); una clase que no es un componente tambien: Sonar mira cualquier clase' 'DosAut SinTipo' (Ficheros-M70 $h)
  $d = @($h | Where-Object { $_.Fichero -like '*DosAut.java' })
  Igual 'es un error' 'error' $d[0].Sev
  Igual 'en la linea de la clase' (Linea-De (Lee $e.Repo 'src/main/java/com/acme/life/application/usecases/DosAut.java') 'public class DosAut') $d[0].Linea
  Comprueba 'dice cuantos y cita a Sonar' ($d[0].Detalle -like '*@Autowired en 2 constructores: solo uno puede llevarlo (Sonar S6818)*') $d[0].Detalle
  Igual 'con @Autowired en los constructores, constructores-sin-autowired no sale' 0 @(Hallazgos $e.Repo | Where-Object { $_.Detalle -like '`[constructores-sin-autowired`]*' }).Count
}

$Pruebas['m70 (a4) inyeccion-estatica (S7178): @Value, @Autowired o @Inject en un campo static, y no sale ademas como inyeccion-campo'] = {
  $miembros = @'
    @Value("${x}")
    private static String x;

    @Autowired
    private static Servicio servicio;

    @Inject
    public static final Servicio otro = null;

    @Value("${p}") private static String q = null;

    @Autowired
    private Servicio normal;
'@ + "`n"
  $e = Escenario-M70 'm70-a4' @{ Estatica = (Clase-M70 'Estatica' '@Component' $miembros) }
  $h = Cal-M70 $e 'inyeccion-estatica'
  $h = @($h | Where-Object { $_.Fichero -like '*Estatica.java' })
  Igual 'salen los cuatro campos static' 4 $h.Count
  $t = Lee $e.Repo 'src/main/java/com/acme/life/application/usecases/Estatica.java'
  Igual 'el primero, en la linea de su @Value' (Linea-De $t '@Value("${x}")') $h[0].Linea
  Comprueba 'dice que Spring no los inyecta, cita a Sonar y da la salida' ($h[0].Detalle -like '*Spring no inyecta campos static: queda a null (Sonar S7178). Quita static o la anotacion.*') $h[0].Detalle
  Igual 'es un error' 'error' $h[0].Sev
  $campo = @(Hallazgos $e.Repo | Where-Object { $_.Cat -eq 'calidad' -and $_.Fichero -like '*Estatica.java' -and $_.Detalle -like '`[inyeccion-campo`]*' })
  Igual 'inyeccion-campo solo sale en el campo que no es static' 1 $campo.Count
  Comprueba 'y es el campo normal' ($campo[0].Detalle -like "*en el campo 'normal'*") $campo[0].Detalle
}

$Pruebas['m70 (a5) value-sin-expresion (S6804): @Value en un campo sin ${...} ni #{...}'] = {
  $miembros = @'
    @Value("hola")
    private String saludo;

    @Value("${hola}")
    private String propiedad;

    @Value("#{1+1}")
    private int suma;

    @Value("${a:b}") private String conDefecto;

    @Value("a.b") private String conInicial = "x";

    @Value(value = "texto")
    private String conNombre;

    // @Value("comentado") private String comentado;

    @Value("hola")
    public void setMetodo(String metodo) {
    }

    public Valores(@Value("hola") String parametro) {
    }
'@ + "`n"
  $e = Escenario-M70 'm70-a5' @{ Valores = (Clase-M70 'Valores' '@Component' $miembros) }
  $h = @(Cal-M70 $e 'value-sin-expresion' | Where-Object { $_.Fichero -like '*Valores.java' })
  $t = Lee $e.Repo 'src/main/java/com/acme/life/application/usecases/Valores.java'
  Igual 'salen el campo con un texto, el que tiene un valor inicial y el de value = ; no los de ${...} y #{...}, ni el metodo, ni el parametro, ni el comentario' (@((Linea-De $t '@Value("hola")'), (Linea-De $t '@Value("a.b")'), (Linea-De $t '@Value(value = "texto")')) -join ' ') (@($h | ForEach-Object { $_.Linea }) -join ' ')
  Comprueba 'dice que es una constante, cita a Sonar y da la salida' ($h[0].Detalle -like '*@Value sin ${...} ni #{...}: es una constante (Sonar S6804). Si es una propiedad, falta el ${...}.*') $h[0].Detalle
  Igual 'es un error' 'error' $h[0].Sev
}

$Pruebas['m70 (a6) las cuatro reglas de Spring se exigen aunque la plantilla tambien las tenga'] = {
  $campos = @'
    @Value("${x}")
    private static String x;

    @Value("hola")
    private String y;
'@ + "`n"
  $miembros = (Ctor-M70 'Fallos' '' '') + (Ctor-M70 'Fallos' '' 'String a') + $campos
  $fallos = { param($pkg) @{
      Fallos = (Clase-M70 'Fallos' '@Component' $miembros $pkg)
      Dos    = (Clase-M70 'Dos' '@Component' ((Ctor-M70 'Dos' '@Autowired' 'String a') + (Ctor-M70 'Dos' '@Autowired' 'String a, int b')) $pkg)
    } }
  $e = Escenario-M70 'm70-a6' (& $fallos 'com.acme.life.application.usecases') (& $fallos 'com.acme.plantilla.application.usecases')
  [void](Rescate @('-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-SinBuild'))
  $cal = @(Hallazgos $e.Repo | Where-Object { $_.Cat -eq 'calidad' })
  foreach ($regla in @('constructores-sin-autowired', 'autowired-varios', 'inyeccion-estatica', 'value-sin-expresion')) {
    $h = @($cal | Where-Object { $_.Detalle.StartsWith("[$regla]") })
    Igual "$regla : sale una vez" 1 $h.Count
    if ($h.Count -eq 1) {
      Igual "$regla : sigue siendo error" 'error' $h[0].Sev
      Comprueba "$regla : y no dice que se queda en aviso" ($h[0].Detalle -notlike '*se queda en aviso*') $h[0].Detalle
    }
  }
}

$Pruebas['m70 (a7) value-sin-expresion: un comentario de varias lineas encima no descuadra la linea del @Value'] = {
  $miembros = @'
    /**
     * Texto del saludo.
     * Va en una constante, no en una propiedad.
     * Tres lineas de comentario encima.
     */
    @Value("hola")
    private String x;

    private int relleno;

    /*
     * Otro comentario de varias lineas.
     * Y despues, una propiedad de verdad.
     * Sin nada que contar.
     */
    @Value("${y}")
    private String y;

    private int mas;
'@ + "`n"
  $e = Escenario-M70 'm70-a7' @{ Comentarios = (Clase-M70 'Comentarios' '@Component' $miembros) }
  $h = @(Cal-M70 $e 'value-sin-expresion' | Where-Object { $_.Fichero -like '*Comentarios.java' })
  $t = Lee $e.Repo 'src/main/java/com/acme/life/application/usecases/Comentarios.java'
  Igual 'sale solo el campo x, en la linea de su @Value' (Linea-De $t '@Value("hola")') (@($h | ForEach-Object { $_.Linea }) -join ' ')
  Comprueba 'y el de la propiedad (y) no sale' (@($h | Where-Object { $_.Linea -eq (Linea-De $t '@Value("${y}")') }).Count -eq 0) ($h | ForEach-Object { $_.Linea })
}

$PkgPlantilla = 'com.acme.plantilla.application.usecases'

$Pruebas['m70 (b1) estilo-constructor: la plantilla usa Lombok y una clase lo escribe a mano'] = {
  $e = Escenario-M70 'm70-b1' @{
    A1      = (Dependencias-M70 'A1' $true)
    A2      = (Dependencias-M70 'A2' $true)
    A3      = (Dependencias-M70 'A3' $true)
    M1      = (Dependencias-M70 'M1' $false)
    SinDeps = (Clase-M70 'SinDeps' '@Service' (Ctor-M70 'SinDeps' '' ''))
    Vacio   = (Clase-M70 'Vacio' "@Service`n@NoArgsConstructor" '')
    Plana   = (Clase-M70 'Plana' '' (Ctor-M70 'Plana' '' 'String a'))
  } @{ P1 = (Dependencias-M70 'P1' $true $PkgPlantilla) }
  $h = Cal-M70 $e 'estilo-constructor'
  Igual 'sale solo en la de a mano (las clases sin dependencias, con el constructor vacio escrito o de Lombok, y la que no es un componente no cuentan)' 'M1' (Ficheros-M70 $h)
  Igual 'es un error' 'error' $h[0].Sev
  Igual 'en la linea de la clase' (Linea-De (Lee $e.Repo 'src/main/java/com/acme/life/application/usecases/M1.java') 'public class M1') $h[0].Linea
  Comprueba 'dice cuantas clases usan Lombok (3 de 4) y que la plantilla tambien' ($h[0].Detalle -like '*Constructor escrito a mano; en el resto del batch (3 de 4 clases) y en la plantilla se usa Lombok. Pasala a @RequiredArgsConstructor*') $h[0].Detalle
}

$Pruebas['m70 (b2) estilo-constructor: manda el estilo de la plantilla, aunque el migrado use mas el otro'] = {
  $e = Escenario-M70 'm70-b2' @{
    L1 = (Dependencias-M70 'L1' $true)
    M1 = (Dependencias-M70 'M1' $false)
    M2 = (Dependencias-M70 'M2' $false)
    M3 = (Dependencias-M70 'M3' $false)
  } @{ P1 = (Dependencias-M70 'P1' $false $PkgPlantilla) }
  $h = Cal-M70 $e 'estilo-constructor'
  Igual 'con la plantilla a mano sale en la de Lombok' 'L1' (Ficheros-M70 $h)
  Comprueba 'y dice que en el resto del batch (3 de 4) y en la plantilla se escribe a mano' ($h[0].Detalle -like '*Constructor con Lombok; en el resto del batch (3 de 4 clases) y en la plantilla se usa el constructor a mano.*') $h[0].Detalle
  # la plantilla con Lombok y el migrado con 1 de Lombok y 3 a mano: manda la plantilla y salen las tres de a mano
  $e2 = Escenario-M70 'm70-b2-contraria' @{
    L1 = (Dependencias-M70 'L1' $true)
    M1 = (Dependencias-M70 'M1' $false)
    M2 = (Dependencias-M70 'M2' $false)
    M3 = (Dependencias-M70 'M3' $false)
  } @{ P1 = (Dependencias-M70 'P1' $true $PkgPlantilla) }
  $h2 = Cal-M70 $e2 'estilo-constructor'
  Igual 'con la plantilla en Lombok salen las tres de a mano, aunque sean mayoria' 'M1 M2 M3' (Ficheros-M70 $h2)
  Comprueba 'y el texto cuenta la de Lombok (1 de 4) y la plantilla' ($h2[0].Detalle -like '*Constructor escrito a mano; en el resto del batch (1 de 4 clases) y en la plantilla se usa Lombok.*') $h2[0].Detalle
}

$Pruebas['m70 (b3) estilo-constructor: sin clases en la plantilla, manda el que mas usa el migrado y, si empatan, Lombok solo si el pom lo tiene'] = {
  $dos = @{ L1 = (Dependencias-M70 'L1' $true); L2 = (Dependencias-M70 'L2' $true); M1 = (Dependencias-M70 'M1' $false); M2 = (Dependencias-M70 'M2' $false) }
  $e = Escenario-M70 'm70-b3-lombok' $dos @{} $true
  $h = Cal-M70 $e 'estilo-constructor'
  Igual 'empate con Lombok en el pom: manda Lombok y salen las dos de a mano' 'M1 M2' (Ficheros-M70 $h)
  Comprueba 'el texto cuenta el batch (2 de 4) y no habla de la plantilla' ($h[0].Detalle -like '*en el resto del batch (2 de 4 clases) se usa Lombok.*') $h[0].Detalle
  $e2 = Escenario-M70 'm70-b3-sin' $dos @{} $false
  $h2 = Cal-M70 $e2 'estilo-constructor'
  Igual 'empate sin Lombok en el pom: manda el constructor a mano y salen las dos de Lombok' 'L1 L2' (Ficheros-M70 $h2)
  $e3 = Escenario-M70 'm70-b3-mayoria' @{ L1 = (Dependencias-M70 'L1' $true); M1 = (Dependencias-M70 'M1' $false); M2 = (Dependencias-M70 'M2' $false) } @{} $true
  Igual 'sin empate manda el que mas usa, haya o no Lombok en el pom' 'L1' (Ficheros-M70 (Cal-M70 $e3 'estilo-constructor'))
}

$Pruebas['m70 (b4) estilo-constructor y estilo-logger: si la plantilla tambien mezcla estilos, salen igual como error (cambiado en M72 b)'] = {
  $e = Escenario-M70 'm70-b4' @{
    A1 = (Dependencias-M70 'A1' $true)
    A2 = (Dependencias-M70 'A2' $true)
    M1 = (Dependencias-M70 'M1' $false)
    S1 = (Logger-M70 'S1' 'slf4j')
    S2 = (Logger-M70 'S2' 'slf4j')
    F1 = (Logger-M70 'F1' 'factory')
  } @{
    P1 = (Dependencias-M70 'P1' $true $PkgPlantilla)
    P2 = (Dependencias-M70 'P2' $true $PkgPlantilla)
    P3 = (Dependencias-M70 'P3' $false $PkgPlantilla)
    Q1 = (Logger-M70 'Q1' 'slf4j' $PkgPlantilla)
    Q2 = (Logger-M70 'Q2' 'slf4j' $PkgPlantilla)
    Q3 = (Logger-M70 'Q3' 'factory' $PkgPlantilla)
  }
  [void](Rescate @('-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-SinBuild'))
  $cal = @(Hallazgos $e.Repo | Where-Object { $_.Cat -eq 'calidad' })
  foreach ($regla in @('estilo-constructor', 'estilo-logger')) {
    $h = @($cal | Where-Object { $_.Detalle.StartsWith("[$regla]") })
    Igual "$regla : sale una vez" 1 $h.Count
    if ($h.Count -eq 1) {
      Igual "$regla : como error, aunque la plantilla tambien mezcle" 'error' $h[0].Sev
      Comprueba "$regla : y no dice que se queda en aviso" ($h[0].Detalle -notlike '*se queda en aviso*') $h[0].Detalle
    }
  }
}

$Pruebas['m70 (b5) estilo-logger: la clase con otro logger sale; un logger dentro de un metodo no cuenta; todas iguales, nada'] = {
  $e = Escenario-M70 'm70-b5' @{
    S1    = (Logger-M70 'S1' 'slf4j')
    S2    = (Logger-M70 'S2' 'slf4j')
    F1    = (Logger-M70 'F1' 'factory')
    O1    = (Logger-M70 'O1' 'otro')
    Local = (Logger-M70 'Local' 'local')
  }
  $h = Cal-M70 $e 'estilo-logger'
  Igual '2 con @Slf4j, 1 con LoggerFactory y 1 con LogManager: salen la de LoggerFactory y la de LogManager' 'F1 O1' (Ficheros-M70 $h)
  $f1 = @($h | Where-Object { $_.Fichero -like '*F1.java' })
  Igual 'es un error' 'error' $f1[0].Sev
  Igual 'en la linea de la clase' (Linea-De (Lee $e.Repo 'src/main/java/com/acme/life/application/usecases/F1.java') 'public class F1') $f1[0].Linea
  Comprueba 'dice cuantas clases usan @Slf4j (2 de 4)' ($f1[0].Detalle -like '*Logger con LoggerFactory; en el resto del batch (2 de 4 clases) se usa @Slf4j.*') $f1[0].Detalle
  $e2 = Escenario-M70 'm70-b5-iguales' @{ F1 = (Logger-M70 'F1' 'factory'); F2 = (Logger-M70 'F2' 'factory'); F3 = (Logger-M70 'F3' 'factory') }
  Igual 'todas iguales: no sale nada' 0 (Cal-M70 $e2 'estilo-logger').Count
  $e3 = Escenario-M70 'm70-b5-plantilla' @{ S1 = (Logger-M70 'S1' 'slf4j'); S2 = (Logger-M70 'S2' 'slf4j'); F1 = (Logger-M70 'F1' 'factory') } @{ Q1 = (Logger-M70 'Q1' 'factory' $PkgPlantilla) }
  Igual 'la plantilla con LoggerFactory manda aunque el batch use mas @Slf4j: salen las dos de @Slf4j' 'S1 S2' (Ficheros-M70 (Cal-M70 $e3 'estilo-logger'))
}

$Pruebas['m70 (b6) estilo: la consola dice cuantas clases usan cada estilo, solo cuando hay mezcla'] = {
  $e = Escenario-M70 'm70-b6' @{
    A1 = (Dependencias-M70 'A1' $true)
    A2 = (Dependencias-M70 'A2' $true)
    A3 = (Dependencias-M70 'A3' $true)
    M1 = (Dependencias-M70 'M1' $false)
    S1 = (Logger-M70 'S1' 'slf4j')
    S2 = (Logger-M70 'S2' 'slf4j')
    F1 = (Logger-M70 'F1' 'factory')
  }
  $r = Rescate @('-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-SinBuild')
  Comprueba 'con mezcla sale la linea con los dos recuentos' ($r.Salida.Contains('Estilo: 1 clase con el constructor a mano frente a 3 con Lombok; 1 logger con LoggerFactory frente a 2 con @Slf4j')) (Cola $r.Salida)
  $e2 = Escenario-M70 'm70-b6-iguales' @{ A1 = (Dependencias-M70 'A1' $true); A2 = (Dependencias-M70 'A2' $true); S1 = (Logger-M70 'S1' 'slf4j') }
  $r2 = Rescate @('-Repo', $e2.Repo, '-Plantilla', $e2.Plantilla, '-SinBuild')
  Comprueba 'sin mezcla no sale la linea' (-not $r2.Salida.Contains('Estilo:')) (Cola $r2.Salida)
}

$Pruebas['m70 (c) el prompt del paso calidad y las reglas de calidad del codigo nuevo hablan de constructores, @Value y estilo'] = {
  $e = Escenario-M70 'm70-c' @{ DosSin = (Clase-M70 'DosSin' '@Component' ((Ctor-M70 'DosSin' '' '') + (Ctor-M70 'DosSin' '' 'String a'))) }
  [void](Rescate @('-Modo', 'fix', '-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-Paso', 'calidad', '-SinPlan', '-Auto', '-Si', '-MaxIntentos', '1', '-MaxLotes', '1'))
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false; return }
  $prompt = Lee $e.Wt '.rescate/prompt.md'
  Comprueba 'el hallazgo del lote es el de los constructores' ($prompt -match 'DosSin\.java:\d+ - \[constructores-sin-autowired\] 2 constructores') $prompt
  Comprueba 'el paso dice que hacer con varios constructores, con @Value y con el estilo' ($prompt -match 'Varios constructores sin @Autowired: deja uno solo' -and $prompt -match 'Estilo \(constructor, logger\): pasa la clase al estilo que dice el hallazgo') $prompt
  Comprueba 'las reglas del codigo nuevo piden un solo constructor, @Value con expresion y el estilo del batch' ($prompt -match 'Un solo constructor por componente de Spring' -and $prompt -match 'mismo estilo que el resto del batch y la PLANTILLA') $prompt
}

# ============== M72: CLASES FINAL QUE SPRING TIENE QUE ENVOLVER Y ESTILO SIN BATIBURRILLO (sin IA) ==============
# Clase de un escenario M72: como Clase-M70, pero con los modificadores a elegir (por defecto 'public final').
function Clase-M72([string]$Nombre, [string]$Cabeza, [string]$Miembros, [string]$Mods = 'public final', [string]$Pkg = 'com.acme.life.application.usecases') {
  return "package $Pkg;`n`n/** Clase $Nombre. */`n$Cabeza`n$Mods class $Nombre {`n$Miembros}`n"
}

# Un metodo vacio con su anotacion encima (vacia = ninguna) y sus modificadores.
function Metodo-M72([string]$Nombre, [string]$Anot, [string]$Mods = 'public') {
  $a = ''
  if ($Anot) { $a = "    $Anot`n" }
  return "$a    $Mods void $Nombre() {`n    }`n`n"
}

# El texto de un fichero del repo del escenario (para buscar en que linea esta una clase).
function Fuente-M72($E, [string]$Nombre) { return (Lee $E.Repo ('src/main/java/com/acme/life/application/usecases/' + $Nombre + '.java')) }

$Pruebas['m72 (a1) clase-final-proxy: una clase final con @Repository sale; sin final, no'] = {
  $e = Escenario-M70 'm72-a1' @{
    RepoFinal   = (Clase-M72 'RepoFinal' '@Repository' '')
    RepoPaquete = (Clase-M72 'RepoPaquete' '@Repository' '' 'final')
    RepoLargo   = (Clase-M72 'RepoLargo' '@org.springframework.stereotype.Repository' '')
    RepoAbierto = (Clase-M72 'RepoAbierto' '@Repository' '' 'public')
  }
  $h = Cal-M70 $e 'clase-final-proxy'
  Igual 'sale en las tres finales (tambien sin public y con el nombre completo de la anotacion) y no en la que no es final' 'RepoFinal RepoLargo RepoPaquete' (Ficheros-M70 $h)
  $d = @($h | Where-Object { $_.Fichero -like '*RepoFinal.java' })
  Igual 'es un error' 'error' $d[0].Sev
  Igual 'en la linea de la clase' (Linea-De (Fuente-M72 $e 'RepoFinal') 'public final class RepoFinal') $d[0].Linea
  Comprueba 'dice por que anotacion, que el bean no se crea y el job no arranca, y que se quita final' ($d[0].Detalle -like '*Clase final que Spring tiene que envolver con un proxy (por @Repository): el bean no se crea y el job no arranca ("Cannot subclass final class"). Quita final de la clase.') $d[0].Detalle
  Igual 'ninguna sale ademas como metodo-final-proxy' 0 @(Hallazgos $e.Repo | Where-Object { $_.Detalle -like '`[metodo-final-proxy`]*' }).Count
}

$Pruebas['m72 (a2) clase-final-proxy: un @Component final con un metodo @Transactional, @Async, @Retryable o de cache sale; sin esas anotaciones, no'] = {
  $e = Escenario-M70 'm72-a2' @{
    ConTx      = (Clase-M72 'ConTx' '@Component' ((Metodo-M72 'antes' '') + (Metodo-M72 'guarda' '@Transactional')))
    ConTxArgs  = (Clase-M72 'ConTxArgs' '@Component' (Metodo-M72 'guarda' "@Transactional(rollbackFor = Exception.class, readOnly = true)`n    @SuppressWarnings(`"x`")"))
    ConAsync   = (Clase-M72 'ConAsync' '@Service' (Metodo-M72 'sube' '@Async'))
    ConRetry   = (Clase-M72 'ConRetry' '@Component' (Metodo-M72 'reintenta' '@Retryable(maxAttempts = 3)'))
    ConCache   = (Clase-M72 'ConCache' '@Component' (Metodo-M72 'lee' '@Cacheable("clientes")'))
    ConPut     = (Clase-M72 'ConPut' '@Component' (Metodo-M72 'pon' '@CachePut(value = "clientes", key = "#a")'))
    ConEvict   = (Clase-M72 'ConEvict' '@Component' (Metodo-M72 'borra' '@CacheEvict(allEntries = true)'))
    ConCaching = (Clase-M72 'ConCaching' '@Component' (Metodo-M72 'varias' '@Caching(evict = { @CacheEvict("a"), @CacheEvict("b") })'))
    Pasivo     = (Clase-M72 'Pasivo' '@Component' ((Metodo-M72 'cada' '@Scheduled(fixedRate = 1000)') + (Metodo-M72 'oye' '@EventListener') + (Metodo-M72 'otra' '@Override')))
    Abierto    = (Clase-M72 'Abierto' '@Component' (Metodo-M72 'guarda' '@Transactional') 'public')
  }
  $h = Cal-M70 $e 'clase-final-proxy'
  Igual 'sale en las ocho finales con un metodo anotado, y no en la que no tiene esas anotaciones ni en la que no es final' 'ConAsync ConCache ConCaching ConEvict ConPut ConRetry ConTx ConTxArgs' (Ficheros-M70 $h)
  $d = @($h | Where-Object { $_.Fichero -like '*ConTx.java' })
  Comprueba 'dice la anotacion y que esta en un metodo' ($d[0].Detalle -like '*(por @Transactional en un metodo): el bean no se crea*') $d[0].Detalle
  Igual 'en la linea de la clase, no en la del metodo' (Linea-De (Fuente-M72 $e 'ConTx') 'public final class ConTx') $d[0].Linea
  $c = @($h | Where-Object { $_.Fichero -like '*ConCaching.java' })
  Comprueba 'una anotacion con otras dentro cuenta una vez, con su nombre' ($c[0].Detalle -like '*(por @Caching en un metodo)*') $c[0].Detalle
}

$Pruebas['m72 (a3) clase-final-proxy: una @Configuration final sale, salvo con proxyBeanMethods = false'] = {
  $e = Escenario-M70 'm72-a3' @{
    CfgFinal  = (Clase-M72 'CfgFinal' '@Configuration' '')
    CfgTrue   = (Clase-M72 'CfgTrue' '@Configuration(proxyBeanMethods = true)' '')
    CfgFalse  = (Clase-M72 'CfgFalse' '@Configuration(proxyBeanMethods = false)' '')
    CfgOtros  = (Clase-M72 'CfgOtros' '@Configuration(value = "cfg", proxyBeanMethods=false)' '')
    CfgAbierta = (Clase-M72 'CfgAbierta' '@Configuration' '' 'public')
  }
  $h = Cal-M70 $e 'clase-final-proxy'
  Igual 'sale en la final y en la que dice proxyBeanMethods = true; no con proxyBeanMethods = false (con otros argumentos, tampoco) ni sin final' 'CfgFinal CfgTrue' (Ficheros-M70 $h)
  $d = @($h | Where-Object { $_.Fichero -like '*CfgFinal.java' })
  Comprueba 'dice que es por @Configuration' ($d[0].Detalle -like '*(por @Configuration):*') $d[0].Detalle
}

$Pruebas['m72 (a4) clase-final-proxy: un @Bean con @StepScope, @JobScope o @Scope(TARGET_CLASS) que devuelve una clase final del migrado: sale en esa clase'] = {
  $config = @'
package com.acme.life.application.usecases;

/** Beans con scope. */
@Configuration
public class Config {

    /** Con scope de step. */
    @Bean
    @StepScope
    public Lector lector() {
        return new Lector();
    }

    /** Con scope de job y el tipo con su paquete. */
    @Bean
    @JobScope
    public com.acme.life.application.usecases.Escritor escritor() {
        return new Escritor();
    }

    /** Con un scope de proxy de clase. */
    @Bean
    @Scope(value = "step", proxyMode = ScopedProxyMode.TARGET_CLASS)
    public Otro otro() {
        return new Otro();
    }

    /** Sin scope. */
    @Bean
    public Plano plano() {
        return new Plano();
    }

    /** Con scope, pero la clase no es final. */
    @Bean
    @StepScope
    public Abierto abierto() {
        return new Abierto();
    }

    /** Con un scope que no es de proxy de clase. */
    @Bean
    @Scope("prototype")
    public Proto proto() {
        return new Proto();
    }
}
'@
  $e = Escenario-M70 'm72-a4' @{
    Config   = $config
    Lector   = (Clase-M72 'Lector' '' '')
    Escritor = (Clase-M72 'Escritor' '' '')
    Otro     = (Clase-M72 'Otro' '' '')
    Plano    = (Clase-M72 'Plano' '' '')
    Abierto  = (Clase-M72 'Abierto' '' '' 'public')
    Proto    = (Clase-M72 'Proto' '' '')
  }
  $h = Cal-M70 $e 'clase-final-proxy'
  Igual 'sale en las tres finales que devuelve un @Bean con scope de proxy, y no en la del @Bean sin scope, en la que no es final, en la del scope prototype ni en la Config' 'Escritor Lector Otro' (Ficheros-M70 $h)
  $l = @($h | Where-Object { $_.Fichero -like '*Lector.java' })
  Igual 'sale en la linea de la clase final, no en la del @Bean' (Linea-De (Fuente-M72 $e 'Lector') 'public final class Lector') $l[0].Linea
  Comprueba 'dice que es por @StepScope del @Bean lector()' ($l[0].Detalle -like '*(por @StepScope en el @Bean lector()): el bean no se crea*') $l[0].Detalle
  $s = @($h | Where-Object { $_.Fichero -like '*Escritor.java' })
  Comprueba 'con @JobScope y el tipo con su paquete, igual' ($s[0].Detalle -like '*(por @JobScope en el @Bean escritor())*') $s[0].Detalle
}

$Pruebas['m72 (a5) metodo-final-proxy: un metodo final con @Transactional, @Async, @Retryable o de cache en una clase que no es final'] = {
  $miembros = (Metodo-M72 'guarda' '@Transactional' 'public final') + (Metodo-M72 'sube' '@Async' 'public final') + (Metodo-M72 'reintenta' '@Retryable' 'final') +
    (Metodo-M72 'lee' '@Cacheable("x")' 'public final synchronized') + (Metodo-M72 'libre' '' 'public final') + (Metodo-M72 'normal' '@Transactional' 'public') +
    (Metodo-M72 'cada' '@Scheduled(fixedRate = 1000)' 'public final')
  $e = Escenario-M70 'm72-a5' @{
    Servicio = (Clase-M72 'Servicio' '@Service' $miembros 'public')
    Cerrada  = (Clase-M72 'Cerrada' '@Service' (Metodo-M72 'guarda' '@Transactional' 'public final'))
  }
  $h = Cal-M70 $e 'metodo-final-proxy'
  Igual 'sale en los cuatro metodos final con anotacion de proxy de la clase abierta, y en ninguno mas' 'Servicio Servicio Servicio Servicio' (Ficheros-M70 $h)
  $g = @($h | Where-Object { $_.Linea -eq (Linea-De (Fuente-M72 $e 'Servicio') 'public final void guarda()') })
  Igual 'sale en la linea del metodo' 1 $g.Count
  $l = @($h | Where-Object { $_.Linea -eq (Linea-De (Fuente-M72 $e 'Servicio') 'public final synchronized void lee()') })
  Igual 'y el cuarto, detras de tres metodos con cuerpo, tambien en su linea' 1 $l.Count
  Igual 'es un error' 'error' $g[0].Sev
  Comprueba 'dice la anotacion, que Spring no puede interceptarlo y que se quita final' ($g[0].Detalle -like '*Metodo final con @Transactional: Spring no lo puede interceptar y la anotacion no hace nada. Quita final.') $g[0].Detalle
  Comprueba 'y el de @Async dice @Async' (@($h | Where-Object { $_.Detalle -like '*Metodo final con @Async:*' }).Count -eq 1)
  Igual 'en la clase final, el metodo no sale aparte: sale la clase (clase-final-proxy)' 'Cerrada' (Ficheros-M70 (Cal-M70 $e 'clase-final-proxy'))
}

$Pruebas['m72 (a6) una clase final sin nada de eso, un record, un @Validated de @ConfigurationProperties, metodos private o static y lo que esta en comentarios o cadenas: no sale nada'] = {
  $record = @'
package com.acme.life.application.usecases;

/** Un par de valores. */
public record Par(String a, int b) {
}
'@
  $comentado = (Clase-M72 'Comentado' "@Service`n/* @Transactional */" ("    // @Transactional`n    private static final String X = `"@Repository @Transactional`";`n`n" + (Metodo-M72 'f' '' 'public final')))
  $e = Escenario-M70 'm72-a6' @{
    Util      = (Clase-M72 'Util' '' "    private Util() {`n    }`n`n    /** Devuelve lo mismo. */`n    public static String f(String a) {`n        return a;`n    }`n")
    Par       = $record
    Componente = (Clase-M72 'Componente' '@Component' ((Metodo-M72 'cada' '@Scheduled(fixedRate = 1000)') + (Metodo-M72 'oye' '@EventListener')))
    Comentado = $comentado
    Config    = (Clase-M72 'Config' '@Configuration(proxyBeanMethods = false)' '')
    Props     = (Clase-M72 'Props' "@ConfigurationProperties(`"acme`")`n@Validated" '')
    Privado   = (Clase-M72 'Privado' '@Component' ((Metodo-M72 'a' '@Transactional' 'private') + (Metodo-M72 'b' '@Async' 'static')))
  }
  Igual 'ni clase-final-proxy' 0 (Cal-M70 $e 'clase-final-proxy').Count
  Igual 'ni metodo-final-proxy' 0 (Cal-M70 $e 'metodo-final-proxy').Count
}

$Pruebas['m72 (a8) el prompt del paso calidad y las reglas del codigo nuevo dicen que una clase o un metodo que Spring envuelve no lleva final'] = {
  $e = Escenario-M70 'm72-a8' @{ RepoFinal = (Clase-M72 'RepoFinal' '@Repository' '') }
  [void](Rescate @('-Modo', 'fix', '-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-Paso', 'calidad', '-SinPlan', '-Auto', '-Si', '-MaxIntentos', '1', '-MaxLotes', '1'))
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false; return }
  $prompt = Lee $e.Wt '.rescate/prompt.md'
  Comprueba 'el hallazgo del lote es el de la clase final' ($prompt -match 'RepoFinal\.java:\d+ - \[clase-final-proxy\] Clase final que Spring tiene que envolver') $prompt
  Comprueba 'el paso dice que se quita final y nada mas' ($prompt -match 'Clase o metodo final que Spring envuelve con un proxy: quita final y nada mas') $prompt
  Comprueba 'las reglas del codigo nuevo piden no poner final en lo que Spring envuelve' ($prompt -match 'Sin final en una clase ni en un metodo que Spring envuelve con un proxy') $prompt
}

$Pruebas['m72 (a7) las dos reglas de proxy se exigen aunque la plantilla tambien las tenga'] = {
  $fallos = { param($pkg) @{
      RepoFinal = (Clase-M72 'RepoFinal' '@Repository' '' 'public final' $pkg)
      Servicio  = (Clase-M72 'Servicio' '@Service' (Metodo-M72 'guarda' '@Transactional' 'public final') 'public' $pkg)
    } }
  $e = Escenario-M70 'm72-a7' (& $fallos 'com.acme.life.application.usecases') (& $fallos 'com.acme.plantilla.application.usecases')
  [void](Rescate @('-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-SinBuild'))
  $cal = @(Hallazgos $e.Repo | Where-Object { $_.Cat -eq 'calidad' })
  foreach ($regla in @('clase-final-proxy', 'metodo-final-proxy')) {
    $h = @($cal | Where-Object { $_.Detalle.StartsWith("[$regla]") })
    Igual "$regla : sale una vez" 1 $h.Count
    if ($h.Count -eq 1) {
      Igual "$regla : sigue siendo error" 'error' $h[0].Sev
      Comprueba "$regla : y no dice que se queda en aviso" ($h[0].Detalle -notlike '*se queda en aviso*') $h[0].Detalle
    }
  }
}

$Pruebas['m72 (b1) estilo-logger y estilo-constructor: aunque la plantilla mezcle, manda lo que mas usa el migrado y salen como error solo las pocas'] = {
  $repo = @{ F1 = (Logger-M70 'F1' 'factory') }
  foreach ($i in 1..20) { $repo["S$i"] = (Logger-M70 "S$i" 'slf4j') }
  $e = Escenario-M70 'm72-b1' $repo @{
    Q1 = (Logger-M70 'Q1' 'slf4j' $PkgPlantilla)
    Q2 = (Logger-M70 'Q2' 'factory' $PkgPlantilla)
    Q3 = (Logger-M70 'Q3' 'factory' $PkgPlantilla)
  }
  $h = Cal-M70 $e 'estilo-logger'
  Igual 'con 20 con @Slf4j y 1 con LoggerFactory (la plantilla mezcla y usa mas LoggerFactory) sale solo la de LoggerFactory' 'F1' (Ficheros-M70 $h)
  Igual 'es un error' 'error' $h[0].Sev
  Comprueba 'cuenta el migrado (20 de 21) y no habla de la plantilla' ($h[0].Detalle -like '*Logger con LoggerFactory; en el resto del batch (20 de 21 clases) se usa @Slf4j.*' -and $h[0].Detalle -notlike '*plantilla*') $h[0].Detalle
  $c = Escenario-M70 'm72-b1-ctor' @{
    L1 = (Dependencias-M70 'L1' $true)
    L2 = (Dependencias-M70 'L2' $true)
    L3 = (Dependencias-M70 'L3' $true)
    M1 = (Dependencias-M70 'M1' $false)
  } @{
    P1 = (Dependencias-M70 'P1' $false $PkgPlantilla)
    P2 = (Dependencias-M70 'P2' $false $PkgPlantilla)
    P3 = (Dependencias-M70 'P3' $true $PkgPlantilla)
  }
  $hc = Cal-M70 $c 'estilo-constructor'
  Igual 'con el constructor igual: la plantilla mezcla y usa mas el constructor a mano, pero sale solo la de a mano (el migrado usa 3 con Lombok)' 'M1' (Ficheros-M70 $hc)
  Igual 'y es un error' 'error' $hc[0].Sev
}

$Pruebas['m72 (b2) estilo: si la plantilla usa un solo estilo, manda la plantilla; si mezcla y el migrado empata, Lombok solo si el pom lo tiene'] = {
  $e = Escenario-M70 'm72-b2' @{ S1 = (Logger-M70 'S1' 'slf4j'); S2 = (Logger-M70 'S2' 'slf4j'); S3 = (Logger-M70 'S3' 'slf4j'); F1 = (Logger-M70 'F1' 'factory') } @{
    Q1 = (Logger-M70 'Q1' 'factory' $PkgPlantilla)
    Q2 = (Logger-M70 'Q2' 'factory' $PkgPlantilla)
  }
  $h = Cal-M70 $e 'estilo-logger'
  Igual 'la plantilla solo usa LoggerFactory: salen las tres con @Slf4j, aunque sean mayoria' 'S1 S2 S3' (Ficheros-M70 $h)
  Igual 'como error' 'error' $h[0].Sev
  Comprueba 'y el texto dice que en la plantilla tambien se usa LoggerFactory' ($h[0].Detalle -like '*Logger con @Slf4j; en el resto del batch (1 de 4 clases) y en la plantilla se usa LoggerFactory.*') $h[0].Detalle
  $dos = @{ L1 = (Dependencias-M70 'L1' $true); M1 = (Dependencias-M70 'M1' $false) }
  $masMano = @{ P1 = (Dependencias-M70 'P1' $true $PkgPlantilla); P2 = (Dependencias-M70 'P2' $false $PkgPlantilla); P3 = (Dependencias-M70 'P3' $false $PkgPlantilla) }
  $masLombok = @{ P1 = (Dependencias-M70 'P1' $true $PkgPlantilla); P2 = (Dependencias-M70 'P2' $true $PkgPlantilla); P3 = (Dependencias-M70 'P3' $false $PkgPlantilla) }
  Igual 'la plantilla mezcla (mas a mano) y el migrado empata, con Lombok en el pom: manda Lombok y sale la de a mano' 'M1' (Ficheros-M70 (Cal-M70 (Escenario-M70 'm72-b2-lombok' $dos $masMano $true) 'estilo-constructor'))
  Igual 'la plantilla mezcla (mas con Lombok) y el migrado empata, sin Lombok en el pom: manda el constructor a mano y sale la de Lombok' 'L1' (Ficheros-M70 (Cal-M70 (Escenario-M70 'm72-b2-sin' $dos $masLombok $false) 'estilo-constructor'))
}

$Pruebas['m72 (c1) estilo: la linea de la consola solo nombra los estilos que tienen alguna clase'] = {
  $e = Escenario-M70 'm72-c1' @{ S1 = (Logger-M70 'S1' 'slf4j'); S2 = (Logger-M70 'S2' 'slf4j'); F1 = (Logger-M70 'F1' 'factory') } @{ Q1 = (Logger-M70 'Q1' 'factory' $PkgPlantilla) }
  $r = Rescate @('-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-SinBuild')
  Comprueba 'con la plantilla en LoggerFactory: 2 con @Slf4j frente a 1 con LoggerFactory' ($r.Salida.Contains('Estilo: 2 loggers con @Slf4j frente a 1 con LoggerFactory')) (Cola $r.Salida)
  # la plantilla usa solo otro logger y el migrado no tiene ninguna clase con ese: no sale 'frente a 0 con otro logger'
  $e2 = Escenario-M70 'm72-c1-otro' @{ S1 = (Logger-M70 'S1' 'slf4j'); S2 = (Logger-M70 'S2' 'slf4j'); F1 = (Logger-M70 'F1' 'factory') } @{ O1 = (Logger-M70 'O1' 'otro' $PkgPlantilla) }
  $r2 = Rescate @('-Repo', $e2.Repo, '-Plantilla', $e2.Plantilla, '-SinBuild')
  $linea = @($r2.Salida -split "`r?`n" | Where-Object { $_.Contains('Estilo:') })
  Igual 'sale una linea de estilo' 1 $linea.Count
  if ($linea.Count -eq 1) {
    Comprueba 'nombra los dos estilos del migrado, con sus numeros' ($linea[0].Contains('2 con @Slf4j') -and $linea[0].Contains('1 logger con LoggerFactory')) $linea[0]
    Comprueba 'no dice frente a 0 ni nombra el logger que ninguna clase usa' (-not $linea[0].Contains('frente a') -and -not $linea[0].Contains('otro logger')) $linea[0]
  }
}

# ============== M76: LO QUE COMPILA PERO NO ARRANCA, O CAMBIA SIN AVISAR (de las guias de migracion; sin IA) ==============
# Diagnostico del escenario (sin Maven), con el original si se da, y sus hallazgos de calidad de esa regla.
function Cal-M76($E, [string]$Regla, [string]$Legacy = '') {
  $a = @('-Repo', $E.Repo, '-Plantilla', $E.Plantilla, '-SinBuild')
  if ($Legacy) { $a += @('-Legacy', $Legacy) }
  [void](Rescate $a)
  return @(Hallazgos $E.Repo | Where-Object { $_.Cat -eq 'calidad' -and $_.Detalle.StartsWith('[' + $Regla + ']') })
}

# Una clase de componente que pide estas dependencias por constructor ("Tipo nombre, ...") y, si se dan, tiene estos miembros mas (campos).
function Pide-M76([string]$Nombre, [string]$Params, [string]$Cabeza = '@Service', [string]$Campos = '') {
  $miembros = $Campos
  if ($Params) {
    foreach ($p in $Params.Split(',')) { $miembros += '    private final ' + ($p.Trim() -replace '^@\w+\s+', '') + ";`n" }
    $miembros += "`n" + (Ctor-M70 $Nombre '' $Params)
  }
  return (Clase-M70 $Nombre $Cabeza $miembros)
}

# Una clase de componente que implementa una interfaz y pide estas dependencias por constructor.
function Implementa-M76([string]$Nombre, [string]$Interfaz, [string]$Params) {
  return ((Pide-M76 $Nombre $Params '@Component') -replace "public class $Nombre ", "public class $Nombre implements $Interfaz ")
}

# Un fichero Java a mano (una interfaz, una clase sin anotaciones...).
function Java-M76([string]$Nombre, [string]$Tipo = 'class', [string]$Miembros = '', [string]$Extra = '') {
  return "package com.acme.life.application.usecases;`n`n/** $Nombre. */`npublic $Tipo $Nombre$Extra {`n$Miembros}`n"
}

$Pruebas['m76 (a1) referencia-circular (SB26): un ciclo de dos por constructor sale en las dos clases, con el ciclo entero; el que depende del ciclo sin estar en el, no'] = {
  $e = Escenario-M70 'm76-a1' @{
    ServicioA = (Pide-M76 'ServicioA' 'ServicioB b')
    ServicioB = (Pide-M76 'ServicioB' 'ServicioA a')
    ServicioC = (Pide-M76 'ServicioC' 'ServicioA a')
    ServicioD = (Pide-M76 'ServicioD' 'String nombre')
  }
  $h = Cal-M76 $e 'referencia-circular'
  Igual 'sale en A y B' 'ServicioA ServicioB' (Ficheros-M70 $h)
  $a = @($h | Where-Object { $_.Fichero -like '*ServicioA.java' })
  Igual 'es un error' 'error' $a[0].Sev
  Igual 'en la linea de la clase' (Linea-De (Fuente-M72 $e 'ServicioA') 'public class ServicioA') $a[0].Linea
  Comprueba 'el texto trae el ciclo entero, dice que Spring Boot 2.6 lo prohibe y que el job no arranca, y que hacer' ($a[0].Detalle -like '*Referencia circular entre beans: ServicioA -> ServicioB -> ServicioA. Desde Spring Boot 2.6 estan prohibidas por defecto y la aplicacion no arranca (BeanCurrentlyInCreationException). Rompe el ciclo*') $a[0].Detalle
  $b = @($h | Where-Object { $_.Fichero -like '*ServicioB.java' })
  Comprueba 'cada clase lleva el ciclo desde ella' ($b[0].Detalle -like '*ServicioB -> ServicioA -> ServicioB.*') $b[0].Detalle
}

$Pruebas['m76 (a2) referencia-circular: un ciclo de tres que mezcla un campo @Autowired, un constructor y un parametro de un metodo @Bean sale en cada clase, y tambien con Lombok'] = {
  $config = @'
package com.acme.life.application.usecases;

/** Beans a mano. */
@Configuration
public class Config {

    /** El contador, que pide al servicio A. */
    @Bean
    public Contador contador(ServicioA a) {
        return new Contador();
    }
}
'@
  $e = Escenario-M70 'm76-a2' @{
    ServicioA = (Clase-M70 'ServicioA' '@Service' "    @Autowired`n    private ServicioB b;`n")
    ServicioB = (Pide-M76 'ServicioB' 'Contador c')
    Contador  = (Java-M76 'Contador')
    Config    = $config
    LombokA   = (Clase-M70 'LombokA' "@Service`n@RequiredArgsConstructor" "    private final LombokB b;`n")
    LombokB   = (Clase-M70 'LombokB' "@Service`n@RequiredArgsConstructor" "    private final LombokA a;`n    private String nombre;`n")
  }
  $h = Cal-M76 $e 'referencia-circular'
  Igual 'sale en las tres clases del ciclo (la del @Bean es la Config) y en las dos con Lombok' 'Config LombokA LombokB ServicioA ServicioB' (Ficheros-M70 $h)
  $c = @($h | Where-Object { $_.Fichero -like '*Config.java' })
  Igual 'la del @Bean sale en la linea del metodo' (Linea-De (Fuente-M72 $e 'Config') 'public Contador contador(') $c[0].Linea
  Comprueba 'y el texto nombra el bean como Config.contador()' ($c[0].Detalle -like '*Config.contador() -> ServicioA -> ServicioB -> Config.contador().*') $c[0].Detalle
  $a = @($h | Where-Object { $_.Fichero -like '*ServicioA.java' })
  Comprueba 'el texto de A trae los tres' ($a[0].Detalle -like '*ServicioA -> ServicioB -> Config.contador() -> ServicioA.*') $a[0].Detalle
}

$Pruebas['m76 (a3) referencia-circular: @Lazy, ObjectProvider o Provider en un eslabon, o un bean con @StepScope en el ciclo: no sale'] = {
  $e = Escenario-M70 'm76-a3' @{
    L1A = (Pide-M76 'L1A' '@Lazy L1B b')
    L1B = (Pide-M76 'L1B' 'L1A a')
    L2A = (Pide-M76 'L2A' 'ObjectProvider<L2B> b')
    L2B = (Pide-M76 'L2B' 'L2A a')
    L3A = (Pide-M76 'L3A' 'Provider<L3B> b')
    L3B = (Pide-M76 'L3B' 'L3A a')
    L4A = (Clase-M70 'L4A' '@Service' "    @Autowired`n    @Lazy`n    private L4B b;`n")
    L4B = (Pide-M76 'L4B' 'L4A a')
    L5A = (Pide-M76 'L5A' 'Lector l')
    L5C = @'
package com.acme.life.application.usecases;

/** Beans con scope de step. */
@Configuration
public class L5C {

    /** El lector se crea al empezar el step: no es una dependencia del arranque. */
    @Bean
    @StepScope
    public Lector lector(L5A a) {
        return new Lector();
    }
}
'@
    Lector = (Java-M76 'Lector')
    RealA  = (Pide-M76 'RealA' 'RealB b')
    RealB  = (Pide-M76 'RealB' 'RealA a')
  }
  $h = Cal-M76 $e 'referencia-circular'
  Igual 'solo sale el ciclo de verdad' 'RealA RealB' (Ficheros-M70 $h)
}

$Pruebas['m76 (a4) referencia-circular: una dependencia por una interfaz se sigue hasta la clase que la implementa; con dos clases que la implementan, no se sabe cual y no sale'] = {
  $e = Escenario-M70 'm76-a4' @{
    ServicioA   = (Pide-M76 'ServicioA' 'PuertoB b')
    PuertoB     = (Java-M76 'PuertoB' 'interface')
    AdaptadorB  = (Implementa-M76 'AdaptadorB' 'PuertoB' 'ServicioA a')
    ServicioX   = (Pide-M76 'ServicioX' 'PuertoY y')
    PuertoY     = (Java-M76 'PuertoY' 'interface')
    AdaptadorY1 = (Implementa-M76 'AdaptadorY1' 'PuertoY' 'ServicioX x')
    AdaptadorY2 = (Implementa-M76 'AdaptadorY2' 'PuertoY' '')
  }
  Igual 'sale el ciclo ServicioA -> AdaptadorB; el de PuertoY, con dos implementaciones, no' 'AdaptadorB ServicioA' (Ficheros-M70 (Cal-M76 $e 'referencia-circular'))
}

$Pruebas['m76 (a5) referencia-circular: con spring.main.allow-circular-references a true (en un yml o un properties del migrado) baja a aviso; a false sigue siendo error'] = {
  $repo = @{ ServicioA = (Pide-M76 'ServicioA' 'ServicioB b'); ServicioB = (Pide-M76 'ServicioB' 'ServicioA a') }
  $y = Escenario-M70 'm76-a5-yml' $repo
  Escribe $y.Repo 'src/main/resources/application.yml' "spring:`n  main:`n    allow-circular-references: true`n"
  $h = Cal-M76 $y 'referencia-circular'
  Igual 'con el yml: salen las dos' 'ServicioA ServicioB' (Ficheros-M70 $h)
  Igual 'como aviso' 'aviso aviso' (($h | ForEach-Object { $_.Sev }) -join ' ')
  Comprueba 'y el texto dice por que es aviso y en que fichero esta la propiedad' ($h[0].Detalle -like '*spring.main.allow-circular-references esta a true en src/main/resources/application.yml*') $h[0].Detalle
  $p = Escenario-M70 'm76-a5-prop' $repo
  Escribe $p.Repo 'src/main/resources/application-pre.properties' "spring.main.allow-circular-references=true`n"
  Igual 'con el properties de un perfil: aviso' 'aviso aviso' ((Cal-M76 $p 'referencia-circular' | ForEach-Object { $_.Sev }) -join ' ')
  $f = Escenario-M70 'm76-a5-false' $repo
  Escribe $f.Repo 'src/main/resources/application.yml' "spring:`n  main:`n    allow-circular-references: false`n"
  Igual 'con false: error' 'error error' ((Cal-M76 $f 'referencia-circular' | ForEach-Object { $_.Sev }) -join ' ')
}

$Pruebas['m76 (a6) referencia-circular: una @Configuration que pide con @Autowired un bean que ella misma crea sale una sola vez'] = {
  $config = @'
package com.acme.life.application.usecases;

/** Beans a mano. */
@Configuration
public class Config {

    @Autowired
    private Paso paso;

    /** El paso. */
    @Bean
    public Paso paso() {
        return new Paso();
    }

    /** Un bean estatico no necesita la instancia de Config. */
    @Bean
    public static Otro otro() {
        return new Otro();
    }
}
'@
  $e = Escenario-M70 'm76-a6' @{ Config = $config; Paso = (Java-M76 'Paso'); Otro = (Java-M76 'Otro') }
  $h = Cal-M76 $e 'referencia-circular'
  Igual 'sale en Config, una vez' 'Config' (Ficheros-M70 $h)
}

# Una @Configuration con estos beans (cada uno: la anotacion y el metodo), en el paquete que se diga.
function Beans-M76([string]$Nombre, [string[]]$Beans, [string]$Cabeza = '@Configuration', [string]$Pkg = 'com.acme.life.application.usecases') {
  $m = ''
  foreach ($b in $Beans) { $m += "    $b`n        return null;`n    }`n`n" }
  return (Clase-M70 $Nombre $Cabeza $m $Pkg)
}

$Pruebas['m76 (b1) bean-repetido (SB21-01): dos metodos @Bean con el mismo nombre en clases distintas salen en las dos; con otro nombre o en la misma clase, no'] = {
  $e = Escenario-M70 'm76-b1' @{
    CfgA  = (Beans-M76 'CfgA' @('@Bean public Lector lector() {', '@Bean public Escritor escritor() {'))
    CfgB  = (Beans-M76 'CfgB' @('@Bean public Lector lector() {', '@Bean public Otro otro() {'))
    CfgC  = (Beans-M76 'CfgC' @('@Bean public Lector lectorPropio() {', '@Bean public Procesador procesar(String a) {', '@Bean public Procesador procesar(int a, int b) {'))
  }
  $h = Cal-M76 $e 'bean-repetido'
  Igual 'sale en las dos clases con lector(), y no en la que tiene otro nombre ni en la que sobrecarga el suyo' 'CfgA CfgB' (Ficheros-M70 $h)
  $a = @($h | Where-Object { $_.Fichero -like '*CfgA.java' })
  Igual 'es un error' 'error' $a[0].Sev
  Igual 'en la linea del metodo' (Linea-De (Fuente-M72 $e 'CfgA') 'public Lector lector()') $a[0].Linea
  Comprueba 'el texto dice el nombre, la otra clase, que la sobrescritura esta desactivada desde Spring Boot 2.1 y que hacer' ($a[0].Detalle -like "*Dos beans se llaman 'lector' (tambien en*CfgB.java*): desde Spring Boot 2.1 la sobrescritura de beans esta desactivada y la aplicacion no arranca. Cambia el nombre de uno (el metodo o @Bean(`"otroNombre`")) o quita el que sobra.*") $a[0].Detalle
}

$Pruebas['m76 (b2) bean-repetido: el nombre explicito de @Bean cuenta (value, name o una lista); un @Profile o @Conditional en la clase o en el metodo hace que no cuente'] = {
  $e = Escenario-M70 'm76-b2' @{
    ExA = (Beans-M76 'ExA' @('@Bean("compartido") public Uno uno() {'))
    ExB = (Beans-M76 'ExB' @('@Bean(name = "compartido") public Dos dos() {'))
    ExC = (Beans-M76 'ExC' @('@Bean(autowireCandidate = false, name = {"alias", "tercero"}) public Tres tres() {'))
    ExD = (Beans-M76 'ExD' @('@Bean(initMethod = "close") public Cuatro tercero() {'))
    ExE = (Beans-M76 'ExE' @('@Bean(initMethod = "close") public Cinco cinco() {'))
    PfA = (Beans-M76 'PfA' @('@Bean public Fuente fuente() {') '@Configuration' )
    PfB = (Beans-M76 'PfB' @('@Bean @Profile("pre") public Fuente fuente() {'))
    CnA = (Beans-M76 'CnA' @('@Bean public Fuente conectar() {') "@Configuration`n@Profile(`"dev`")")
    CnB = (Beans-M76 'CnB' @('@Bean public Fuente conectar() {') "@Configuration`n@ConditionalOnProperty(`"x`")")
  }
  $h = Cal-M76 $e 'bean-repetido'
  Igual 'salen ExA y ExB (compartido) y ExC y ExD (tercero: un alias y el nombre de un metodo); ExE no, y los de perfil tampoco' 'ExA ExB ExC ExD' (Ficheros-M70 $h)
}

$Pruebas['m76 (b3) bean-repetido: con spring.main.allow-bean-definition-overriding a true, los @Bean repetidos bajan a aviso'] = {
  $repo = @{ CfgA = (Beans-M76 'CfgA' @('@Bean public Lector lector() {')); CfgB = (Beans-M76 'CfgB' @('@Bean public Lector lector() {')) }
  $e = Escenario-M70 'm76-b3' $repo
  Escribe $e.Repo 'src/main/resources/application.yml' "spring:`n  main:`n    allow-bean-definition-overriding: true`n"
  $h = Cal-M76 $e 'bean-repetido'
  Igual 'salen los dos' 'CfgA CfgB' (Ficheros-M70 $h)
  Igual 'como aviso' 'aviso aviso' (($h | ForEach-Object { $_.Sev }) -join ' ')
  Comprueba 'y dice que la propiedad esta a true en el yml' ($h[0].Detalle -like '*spring.main.allow-bean-definition-overriding esta a true en src/main/resources/application.yml*') $h[0].Detalle
}

$Pruebas['m76 (b4) bean-repetido: dos componentes con el mismo nombre de clase en paquetes distintos y sin nombre explicito salen en los dos, aunque se permita la sobrescritura'] = {
  $e = Escenario-M70 'm76-b4' @{
    Duplicada = (Clase-M70 'Duplicada' '@Service' '')
    Nombrada  = (Clase-M70 'Nombrada' '@Service' '')
    Perfil    = (Clase-M70 'Perfil' "@Service`n@Profile(`"dev`")" '')
  }
  $otro = 'com.acme.life.infrastructure.adapters'
  Escribe $e.Repo 'src/main/java/com/acme/life/infrastructure/adapters/Duplicada.java' (Clase-M70 'Duplicada' '@Component' '' $otro)
  Escribe $e.Repo 'src/main/java/com/acme/life/infrastructure/adapters/Nombrada.java' (Clase-M70 'Nombrada' '@Service("otra")' '' $otro)
  Escribe $e.Repo 'src/main/java/com/acme/life/infrastructure/adapters/Perfil.java' (Clase-M70 'Perfil' "@Service`n@Profile(`"pre`")" '' $otro)
  Escribe $e.Repo 'src/main/resources/application.yml' "spring.main.allow-bean-definition-overriding: true`n"
  $h = Cal-M76 $e 'bean-repetido'
  Igual 'sale Duplicada en sus dos paquetes; Nombrada (una con nombre explicito) y Perfil (con @Profile) no' 'Duplicada Duplicada' (Ficheros-M70 $h)
  Igual 'como error, porque la propiedad no vale para los componentes' 'error error' (($h | ForEach-Object { $_.Sev }) -join ' ')
  Comprueba 'el texto dice el nombre del bean, la otra clase y que hacer' ($h[0].Detalle -like "*Dos clases dan el mismo nombre de bean 'duplicada' (tambien*Duplicada.java*): Spring no arranca (ConflictingBeanDefinitionException), ni permitiendo la sobrescritura. Ponle nombre a una (@Service(`"otroNombre`")) o renombra la clase.*") $h[0].Detalle
}

$Pruebas['m76 (c1) enable-batch (SB30-08): @EnableBatchProcessing o extender DefaultBatchConfiguration sale como error; con la plantilla igual, aviso; sin eso, nada'] = {
  $e = Escenario-M70 'm76-c1' @{
    Anotada  = (Clase-M70 'Anotada' "@Configuration`n@EnableBatchProcessing" '')
    Extiende = (Java-M76 'Extiende' 'class' '' ' extends DefaultBatchConfiguration')
    Larga    = (Clase-M70 'Larga' "@Configuration`n@org.springframework.batch.core.configuration.annotation.EnableBatchProcessing(modular = true)" '')
    Normal   = (Clase-M70 'Normal' '@Configuration' "    // @EnableBatchProcessing en un comentario`n    private static final String X = `"EnableBatchProcessing`";`n")
    Hija     = (Java-M76 'Hija' 'class' '' ' extends Normal implements Serializable')
  }
  $h = Cal-M76 $e 'enable-batch'
  Igual 'sale en las tres clases que lo hacen' 'Anotada Extiende Larga' (Ficheros-M70 $h)
  $a = @($h | Where-Object { $_.Fichero -like '*Anotada.java' })
  Igual 'es un error' 'error' $a[0].Sev
  Igual 'en la linea de la clase' (Linea-De (Fuente-M72 $e 'Anotada') 'public class Anotada') $a[0].Linea
  Comprueba 'el texto dice que la configuracion automatica se aparta, que el job no se lanza ni se crean las tablas, y que hacer' ($a[0].Detalle -like '*@EnableBatchProcessing (o extender DefaultBatchConfiguration): en Spring Boot 3 la configuracion automatica de Batch se aparta, asi que el job no se lanza al arrancar y no se crean las tablas BATCH_. Quita la anotacion (o la clase) y deja la configuracion automatica*') $a[0].Detalle
  $p = Escenario-M70 'm76-c1-plantilla' @{ Anotada = (Clase-M70 'Anotada' "@Configuration`n@EnableBatchProcessing" '') } @{ Plantilla = (Clase-M70 'Plantilla' "@Configuration`n@EnableBatchProcessing" '' $PkgPlantilla) }
  $hp = Cal-M76 $p 'enable-batch'
  Igual 'con la plantilla haciendo lo mismo: sale una vez, como aviso' 'aviso' (($hp | ForEach-Object { $_.Sev }) -join ' ')
  Comprueba 'y dice que se queda en aviso porque la plantilla tambien lo hace' ($hp[0].Detalle -like '*(se queda en aviso: la plantilla tambien lo hace)') $hp[0].Detalle
}

$Pruebas['m76 (c2) revision.ps1 ya no lleva BOOT-ENABLEBATCH: lo mide rescate.ps1 sin IA'] = {
  $texto = Lee (Split-Path -Parent $aqui) 'revision.ps1'
  Comprueba 'el catalogo de la revision no tiene BOOT-ENABLEBATCH' (-not $texto.Contains("@('BOOT-ENABLEBATCH'")) ''
  Comprueba 'y la cabecera dice que ya sale del diagnostico' ($texto -match 'BOOT-ENABLEBATCH[^\r\n]*rescate\.ps1') ''
}

$Pruebas['m76 (d1) parametros-v4 (SBT5-09): fecha(date)=valor en un .sh sale; la notacion nueva, no'] = {
  $e = Escenario-M70 'm76-d1' @{}
  Escribe $e.Repo 'scripts/vieja.sh' "#!/bin/sh`njava -jar batch-life.jar `"fecha(date)=2024-01-01`" `"id(long)=7`"`n"
  Escribe $e.Repo 'scripts/nueva.sh' "#!/bin/sh`njava -jar batch-life.jar fecha=2024-01-01,java.time.LocalDate id=7,java.lang.Long`n"
  $h = Cal-M76 $e 'parametros-v4'
  Igual 'sale solo en el script viejo, una vez aunque lleve dos parametros' 'vieja' (Ficheros-M70 $h)
  Igual 'es un error' 'error' $h[0].Sev
  Igual 'en la linea del java' 2 $h[0].Linea
  Igual 'con la ruta del fichero' 'scripts/vieja.sh' ($h[0].Fichero -replace '\\', '/')
  Comprueba 'el texto dice que se lee como un texto, que el job no recibe el parametro y no falla, y la notacion nueva de cada uno' ($h[0].Detalle -like "*Parametro de job con la notacion de Spring Batch 4: en Spring Batch 5 se lee como un texto cuyo nombre es 'fecha(date)', asi que el job no recibe el parametro y no falla. Cambia 'fecha(date)=2024-01-01' por 'fecha=2024-01-01,java.time.LocalDate' y 'id(long)=7' por 'id=7,java.lang.Long'.*") $h[0].Detalle
}

$Pruebas['m76 (d2) parametros-v4: tambien en .cmd, .bat, .yml, .properties, Dockerfile y un literal de Java, con o sin barras; no en un comentario ni en src/test'] = {
  $e = Escenario-M70 'm76-d2' @{
    Lanza = (Clase-M70 'Lanza' '@Component' "    String[] args = {`"total(double)=1.5`"};`n    // `"borrado(long)=1`"`n")
  }
  Escribe $e.Repo 'bin/a.cmd' "java -jar b.jar nombre(string)=x`r`n"
  Escribe $e.Repo 'bin/b.bat' "REM java -jar b.jar viejo(long)=1`r`njava -jar b.jar n(long)=%NUM%`r`n"
  Escribe $e.Repo 'k8s/c.yml' "args:`n  - `"fecha(date)=2024-01-01`"`n"
  Escribe $e.Repo 'k8s/d.yaml' "args: [`"x(long)=3`"]`n"
  Escribe $e.Repo 'k8s/e.properties' "job.args=y(long)=4`n"
  Escribe $e.Repo 'Dockerfile' "FROM eclipse-temurin:21`nCMD [`"java`", `"-jar`", `"b.jar`", `"z(long)=5`"]`n"
  Escribe $e.Repo 'bin/f.sh' "# java -jar b.jar viejo(long)=1`njava -jar b.jar fecha\(date\)=2024-01-01`n"
  Escribe $e.Repo 'src/test/resources/test.properties' "t(long)=1`n"
  Escribe $e.Repo 'notas.txt' "n(long)=1`n"
  $h = Cal-M76 $e 'parametros-v4'
  Igual 'salen los ocho que lo llevan en codigo, y no el comentario de f.sh, el de b.bat, el de Lanza, src/test ni notas.txt' 'a b c d Dockerfile e f Lanza' (Ficheros-M70 $h)
  Igual 'de b.bat, la linea 2 (no la del REM)' '2' (@($h | Where-Object { $_.Fichero -like '*b.bat' } | ForEach-Object { $_.Linea }) -join ' ')
  Igual 'de Lanza, la linea del literal y no la del comentario' (Linea-De (Fuente-M72 $e 'Lanza') 'total(double)') (@($h | Where-Object { $_.Fichero -like '*Lanza.java' } | ForEach-Object { $_.Linea }) -join ' ')
  $f = @($h | Where-Object { $_.Fichero -like '*f.sh' })
  Comprueba 'con la barra del shell el texto dice el nombre sin ella' ($f[0].Detalle -like "*cuyo nombre es 'fecha(date)'*por 'fecha=2024-01-01,java.time.LocalDate'*") $f[0].Detalle
}

$Pruebas['m76 (e1) varios-jobs-sin-nombre (SB30-09): dos jobs y ningun spring.batch.job.name es un aviso, una vez; con el nombre en el yml, en un script o con el runner apagado, nada; con un solo job, nada'] = {
  $dos = @{
    Jobs1 = (Beans-M76 'Jobs1' @('@Bean public Job altaJob(JobRepository r) {'))
    Jobs2 = (Beans-M76 'Jobs2' @('@Bean public Job bajaJob(JobRepository r) {', '@Bean public Step paso() {'))
  }
  $e = Escenario-M70 'm76-e1' $dos
  $h = Cal-M76 $e 'varios-jobs-sin-nombre'
  Igual 'sale una vez, en el primer job' 'Jobs1' (Ficheros-M70 $h)
  Igual 'es un aviso' 'aviso' $h[0].Sev
  Igual 'en la linea del metodo' (Linea-De (Fuente-M72 $e 'Jobs1') 'public Job altaJob') $h[0].Linea
  Comprueba 'el texto dice los jobs, que Spring Boot 3 ya no arranca varios sin nombre, que hacer y que puede venir de fuera' ($h[0].Detalle -like "*Hay 2 jobs (altaJob, bajaJob) y ninguna spring.batch.job.name en la configuracion: Spring Boot 3 ya no admite arrancar varios jobs y exige decir cual con spring.batch.job.name. Ponla en application.yml o en el lanzador (-Dspring.batch.job.name=...); si el nombre viene de fuera del repo (un configmap), deja este aviso.*") $h[0].Detalle

  Escribe $e.Repo 'src/main/resources/application.yml' "spring:`n  batch:`n    job:`n      name: altaJob`n"
  Igual 'con spring.batch.job.name en el yml, no sale' 0 @(Cal-M76 $e 'varios-jobs-sin-nombre').Count
  Escribe $e.Repo 'src/main/resources/application.yml' "spring:`n  batch:`n    job:`n      enabled: false`n"
  Igual 'con el runner apagado (spring.batch.job.enabled: false), no sale' 0 @(Cal-M76 $e 'varios-jobs-sin-nombre').Count
  Escribe $e.Repo 'src/main/resources/application.yml' "life:`n  inventory: legado`n"
  Escribe $e.Repo 'bin/lanza.sh' "#!/bin/sh`njava -Dspring.batch.job.name=altaJob -jar batch-life.jar`n"
  Igual 'con -Dspring.batch.job.name en un script, no sale' 0 @(Cal-M76 $e 'varios-jobs-sin-nombre').Count
  Remove-Item -LiteralPath (Join-Path $e.Repo 'bin/lanza.sh') -Force
  Escribe $e.Repo ('src/main/java/com/acme/life/application/usecases/Jobs2.java') (Beans-M76 'Jobs2' @('@Bean public Step bajaStep() {'))
  Igual 'con un solo job, no sale' 0 @(Cal-M76 $e 'varios-jobs-sin-nombre').Count
  Escribe $e.Repo ('src/main/java/com/acme/life/application/usecases/Jobs2.java') (Beans-M76 'Jobs2' @('@Bean public Job bajaJob(JobRepository r) {') "@Configuration`n@Profile(`"pre`")")
  Igual 'con el otro job en un @Profile, no sale' 0 @(Cal-M76 $e 'varios-jobs-sin-nombre').Count
}

# El pom del repo del escenario con estas dependencias mas (solo el artifactId; el grupo es inventado).
function Pom-M76($E, [string[]]$Deps) {
  $x = ''
  foreach ($d in $Deps) { $x += "  <dependency><groupId>com.acme.dep</groupId><artifactId>$d</artifactId></dependency>`n" }
  Escribe $E.Repo 'pom.xml' ($Pom -replace '</dependencies>', ($x + '  </dependencies>'))
}

# Una clase de componente con un solo metodo cuyo cuerpo es esto.
function Metodo-M76([string]$Nombre, [string]$Cuerpo) {
  return (Clase-M70 $Nombre '@Component' "    public void corre() {`n        $Cuerpo`n    }`n")
}

$Pruebas['m76 (f1) nashorn (JDK-06): getEngineByName con nashorn, javascript, js o ecmascript sale como error; otro motor, un comentario o nashorn-core en el pom, no'] = {
  $e = Escenario-M70 'm76-f1' @{
    Nashorn = (Metodo-M76 'Nashorn' 'Object m = new ScriptEngineManager().getEngineByName("nashorn");')
    Js      = (Metodo-M76 'Js' 'Object m = manager.getEngineByName("JavaScript");')
    Corto   = (Metodo-M76 'Corto' 'Object m = manager.getEngineByName( "js" );')
    Ecma    = (Metodo-M76 'Ecma' 'Object m = manager.getEngineByName("ECMAScript");')
    Groovy  = (Metodo-M76 'Groovy' 'Object m = manager.getEngineByName("groovy");')
    Coment  = (Metodo-M76 'Coment' '// getEngineByName("nashorn")')
  }
  $h = Cal-M76 $e 'nashorn'
  Igual 'sale con los cuatro nombres, y no con groovy ni en un comentario' 'Corto Ecma Js Nashorn' (Ficheros-M70 $h)
  $a = @($h | Where-Object { $_.Fichero -like '*Nashorn.java' })
  Igual 'es un error' 'error' $a[0].Sev
  Igual 'en la linea de la llamada' (Linea-De (Fuente-M72 $e 'Nashorn') 'getEngineByName') $a[0].Linea
  Comprueba 'el texto dice que devuelve null desde Java 15, que el job falla con NullPointerException y que hacer' ($a[0].Detalle -like '*getEngineByName("nashorn") devuelve null desde Java 15 (JEP 372 quito Nashorn del JDK) y el job falla con un NullPointerException al usar el motor. Anade org.openjdk.nashorn:nashorn-core al pom (Nashorn como libreria aparte) o GraalJS (js-scriptengine), o pasa el script a Java.*') $a[0].Detalle
  Pom-M76 $e @('nashorn-core')
  Igual 'con nashorn-core en el pom, no sale' 0 @(Cal-M76 $e 'nashorn').Count
  Pom-M76 $e @('js-scriptengine')
  Igual 'con js-scriptengine (GraalJS) en el pom, no sale' 0 @(Cal-M76 $e 'nashorn').Count
}

$Pruebas['m76 (f2) comando-sin-partir (SBT5-18): SystemCommandTasklet con setCommand("ls -l") en un solo argumento sale como error; con varios argumentos, un programa sin espacios o una ruta con espacios, no'] = {
  $e = Escenario-M70 'm76-f2' @{
    Junto   = (Metodo-M76 'Junto' 'SystemCommandTasklet t = new SystemCommandTasklet(); t.setCommand("ls -l");')
    Partido = (Metodo-M76 'Partido' 'SystemCommandTasklet t = new SystemCommandTasklet(); t.setCommand("ls", "-l");')
    Solo    = (Metodo-M76 'Solo' 'SystemCommandTasklet t = new SystemCommandTasklet(); t.setCommand("ls");')
    Ruta    = (Metodo-M76 'Ruta' 'SystemCommandTasklet t = new SystemCommandTasklet(); t.setCommand("C:/Program Files/app/run.exe");')
    Variable = (Metodo-M76 'Variable' 'SystemCommandTasklet t = new SystemCommandTasklet(); t.setCommand(texto);')
    Otra    = (Metodo-M76 'Otra' 'MiClase t = new MiClase(); t.setCommand("ls -l");')
  }
  $h = Cal-M76 $e 'comando-sin-partir'
  Igual 'sale solo en el comando junto' 'Junto' (Ficheros-M70 $h)
  Igual 'es un error' 'error' $h[0].Sev
  Igual 'en la linea de la llamada' (Linea-De (Fuente-M72 $e 'Junto') 'setCommand') $h[0].Linea
  Comprueba 'el texto dice que Spring Batch 5 ya no parte el comando, que busca un programa con ese nombre y como separarlo' ($h[0].Detalle -like '*SystemCommandTasklet.setCommand("ls -l") con el comando entero en un solo argumento: desde Spring Batch 5 setCommand recibe un array y ya no parte el comando por los espacios, asi que busca un programa que se llama "ls -l" y falla. Separa los argumentos: setCommand("ls", "-l").*') $h[0].Detalle
}

# El escenario con un schema.sql (y, si se pide, un data.sql) y esta configuracion de Spring en application.yml.
function Sql-M76([string]$Nombre, [string]$Yml, [string[]]$Sql = @('schema.sql')) {
  $e = Escenario-M70 $Nombre @{}
  foreach ($s in $Sql) { Escribe $e.Repo ('src/main/resources/' + $s) "create table recibo (id bigint);`n" }
  Escribe $e.Repo 'src/main/resources/application.yml' $Yml
  return $e
}

$Pruebas['m76 (g1) sql-init-no-embebida (SB25-01): schema.sql o data.sql con una base que no es H2 en memoria y sin spring.sql.init.mode es un aviso por fichero; con jdbc:h2:mem o con el modo, no'] = {
  $e = Sql-M76 'm76-g1' "spring:`n  datasource:`n    url: `${DB_URL}`n" @('schema.sql', 'data.sql', 'schema-oracle.sql')
  Escribe $e.Repo 'src/main/resources/otro.sql' "select 1;`n"
  $h = Cal-M76 $e 'sql-init-no-embebida'
  Igual 'sale en los tres scripts de arranque y no en otro.sql' 'data schema schema-oracle' (Ficheros-M70 $h)
  Igual 'es un aviso' 'aviso aviso aviso' (($h | ForEach-Object { $_.Sev }) -join ' ')
  $a = @($h | Where-Object { $_.Fichero -like '*src/main/resources/schema.sql' -or $_.Fichero -like '*src\main\resources\schema.sql' })
  Igual 'en la linea 1' 1 $a[0].Linea
  Comprueba 'el texto dice que desde Spring Boot 2.5 solo corre con una base embebida en memoria, la url que ve y que hacer' ($a[0].Detalle -like '*schema.sql ya no se ejecuta solo: desde Spring Boot 2.5 la inicializacion SQL solo corre por defecto con una base embebida en memoria, y esta no lo es (spring.datasource.url es ${DB_URL}, en src/main/resources/application.yml:3). Pon spring.sql.init.mode=always si debe ejecutarse (cuidado: en una base con datos vuelve a correr el script) o never si no.*') $a[0].Detalle

  $m = Sql-M76 'm76-g1-mem' "spring:`n  datasource:`n    url: jdbc:h2:mem:testdb;DB_CLOSE_DELAY=-1`n"
  Igual 'con jdbc:h2:mem, no sale' 0 @(Cal-M76 $m 'sql-init-no-embebida').Count
  $o = Sql-M76 'm76-g1-modo' "spring:`n  datasource:`n    url: `${DB_URL}`n  sql:`n    init:`n      mode: always`n"
  Igual 'con spring.sql.init.mode, no sale' 0 @(Cal-M76 $o 'sql-init-no-embebida').Count
  $s = Sql-M76 'm76-g1-sin' "spring:`n  datasource:`n    url: `${DB_URL}`n" @()
  Igual 'sin schema.sql ni data.sql, no sale' 0 @(Cal-M76 $s 'sql-init-no-embebida').Count
}

$Pruebas['m76 (g2) sql-init-no-embebida: con una url en memoria en un perfil y otra de variable en otro, sale; sin url, depende de si el pom trae una base embebida'] = {
  $e = Sql-M76 'm76-g2' "spring.datasource.url: jdbc:h2:mem:local`n"
  Escribe $e.Repo 'src/main/resources/application-pre.properties' "spring.datasource.url=jdbc:oracle:thin:@//host:1521/svc`n"
  Igual 'con una url en memoria y otra de Oracle, sale (la de pre)' 1 @(Cal-M76 $e 'sql-init-no-embebida').Count
  $s = Sql-M76 'm76-g2-sin' "life:`n  inventory: legado`n"
  Igual 'sin url y sin base embebida en el pom, sale' 1 @(Cal-M76 $s 'sql-init-no-embebida').Count
  Pom-M76 $s @('h2')
  Igual 'sin url y con h2 en el pom, no sale' 0 @(Cal-M76 $s 'sql-init-no-embebida').Count
}

# El original de un escenario (una carpeta junto al repo) con estos ficheros (ruta -> texto).
function Original-M76($E, [hashtable]$Ficheros) {
  $o = Join-Path (Split-Path -Parent $E.Repo) 'original'
  if (Test-Path -LiteralPath $o) { Remove-Item -LiteralPath $o -Recurse -Force }
  foreach ($k in $Ficheros.Keys) { Escribe $o $k $Ficheros[$k] }
  return $o
}

$OriginalMapa = @{ 'src/main/java/com/acme/life/config/RepoMapa.java' = "package com.acme.life.config;`n`n/** Repositorio en memoria. */`npublic class RepoMapa {`n    JobRepository repo() throws Exception {`n        MapJobRepositoryFactoryBean f = new MapJobRepositoryFactoryBean();`n        return f.getObject();`n    }`n}`n" }

# Una @Configuration que da a Batch su base: $Cuerpo es el cuerpo del metodo que devuelve el DataSource.
function BaseBatch-M76([string]$Anot, [string]$Cuerpo, [string]$Pkg = 'com.acme.plantilla.application.usecases') {
  return (Clase-M70 'BaseBatch' '@Configuration' "    @Bean`n    $Anot`n    public DataSource baseBatch() {`n        $Cuerpo`n    }`n" $Pkg)
}
$MemoriaH2 = 'return new EmbeddedDatabaseBuilder().setType(EmbeddedDatabaseType.H2).build();'

$Pruebas['m76 (h1) repositorio-batch (SBT5-04): el original no guarda las ejecuciones (Map) y el migrado acaba en la base del negocio: sale una vez, como error, en la clase de arranque'] = {
  $e = Escenario-M70 'm76-h1' @{ Uno = (Pide-M76 'Uno' 'String a'); Dos = (Pide-M76 'Dos' 'String b') } @{ BaseBatch = (BaseBatch-M76 '@BatchDataSource' $MemoriaH2) }
  Escribe $e.Repo 'src/main/resources/application.yml' "spring:`n  datasource:`n    url: `${DB_URL}`n"
  $o = Original-M76 $e $OriginalMapa
  $h = Cal-M76 $e 'repositorio-batch' $o
  Igual 'sale una vez, en LifeApplication' 'LifeApplication' (Ficheros-M70 $h)
  Igual 'es un error' 'error' $h[0].Sev
  Igual 'en la linea de @SpringBootApplication' 6 $h[0].Linea
  Comprueba 'el texto dice lo que hace el original, donde acaba Batch en el migrado, por que falla en pre y no en local, que hacer y lo que hace la plantilla' ($h[0].Detalle -like "*El original no guarda las ejecuciones de Batch (usa MapJobRepositoryFactoryBean, que las deja en memoria) y en el migrado Spring Batch acaba en la base del negocio (spring.datasource.url es `${DB_URL}, en src/main/resources/application.yml:3). Spring Batch 5 quito el repositorio en memoria y Spring Boot 3 usa el DataSource normal: en pre el primer arranque falla porque faltan las tablas BATCH_ (o las crea en la base del negocio si alguien pone spring.batch.jdbc.initialize-schema=always); en local no se ve porque la prueba usa H2. Dale a Batch una base propia en memoria: un DataSource H2 con @BatchDataSource, sin perder el del negocio (con Spring Boot 3.4 o mas, @Bean(defaultCandidate = false) en el de Batch; antes, declara el del negocio y marcalo @Primary) y con H2 en el pom fuera del scope test. La plantilla lo resuelve con src/main/java/com/acme/plantilla/application/usecases/BaseBatch.java (un DataSource con @BatchDataSource en memoria): copialo.") $h[0].Detalle
  Igual 'sin original, no sale' 0 @(Cal-M76 $e 'repositorio-batch').Count
  Escribe $e.Repo '.rescate/contrato.json' (ConvertTo-Json -InputObject @{ original = $o; jobs = @() })
  Igual 'con el original solo en el contrato (sin -Legacy), sale' 1 @(Cal-M76 $e 'repositorio-batch').Count
  Remove-Item -LiteralPath (Join-Path $e.Repo '.rescate/contrato.json') -Force
}

$Pruebas['m76 (h2) repositorio-batch: no sale si el migrado le da a Batch una base propia en memoria (@BatchDataSource, DefaultBatchConfiguration o ResourcelessJobRepository) o si la suya ya es H2 en memoria; con @BatchDataSource a otra base, sale'] = {
  $e = Escenario-M70 'm76-h2' @{} @{ BaseBatch = (BaseBatch-M76 '@BatchDataSource' $MemoriaH2) }
  Escribe $e.Repo 'src/main/resources/application.yml' "spring:`n  datasource:`n    url: `${DB_URL}`n"
  $o = Original-M76 $e $OriginalMapa
  $ruta = 'src/main/java/com/acme/life/application/usecases/'
  Escribe $e.Repo ($ruta + 'BaseBatch.java') (BaseBatch-M76 '@BatchDataSource' $MemoriaH2 'com.acme.life.application.usecases')
  Igual 'con @BatchDataSource a una H2 en memoria, no sale' 0 @(Cal-M76 $e 'repositorio-batch' $o).Count
  Escribe $e.Repo ($ruta + 'BaseBatch.java') (BaseBatch-M76 '@BatchDataSource' 'return DataSourceBuilder.create().url("jdbc:oracle:thin:@//host:1521/svc").build();' 'com.acme.life.application.usecases')
  Igual 'con @BatchDataSource a Oracle, sale' 1 @(Cal-M76 $e 'repositorio-batch' $o).Count
  Escribe $e.Repo ($ruta + 'BaseBatch.java') (Clase-M70 'BaseBatch' '@Configuration' "    @Bean`n    public JobRepository repo() {`n        return new ResourcelessJobRepository();`n    }`n")
  Igual 'con un ResourcelessJobRepository, no sale' 0 @(Cal-M76 $e 'repositorio-batch' $o).Count
  Escribe $e.Repo ($ruta + 'BaseBatch.java') (Java-M76 'BaseBatch' 'class' "    @Override`n    protected DataSource getDataSource() {`n        $MemoriaH2`n    }`n" ' extends DefaultBatchConfiguration')
  Igual 'con un DefaultBatchConfiguration que da una H2 en memoria, no sale' 0 @(Cal-M76 $e 'repositorio-batch' $o).Count
  Remove-Item -LiteralPath (Join-Path $e.Repo ($ruta + 'BaseBatch.java')) -Force
  Escribe $e.Repo 'src/main/resources/application.yml' "spring:`n  datasource:`n    url: jdbc:h2:mem:batch`n"
  Igual 'con la url del migrado en H2 en memoria, no sale' 0 @(Cal-M76 $e 'repositorio-batch' $o).Count
}

$Pruebas['m76 (h3) repositorio-batch: si la plantilla tambien acaba en la base del negocio, aviso'] = {
  $e = Escenario-M70 'm76-h3' @{} @{}
  Escribe $e.Repo 'src/main/resources/application.yml' "spring:`n  datasource:`n    url: `${DB_URL}`n"
  $o = Original-M76 $e $OriginalMapa
  $h = Cal-M76 $e 'repositorio-batch' $o
  Igual 'sale una vez' 1 $h.Count
  Igual 'como aviso' 'aviso' $h[0].Sev
  Comprueba 'con la nota de la plantilla' ($h[0].Detalle -like '*(se queda en aviso: la plantilla tambien lo hace)') $h[0].Detalle
  Comprueba 'y el texto dice que la plantilla tampoco le da una base propia' ($h[0].Detalle -like '*La plantilla tampoco le da a Batch una base propia*') $h[0].Detalle
}

$Pruebas['m76 (h4) repositorio-batch: el original que guarda en una base real, o con una url de variable y una H2 solo en src/test, no cuenta; el que usa solo una H2 en memoria, si'] = {
  $e = Escenario-M70 'm76-h4' @{} @{ BaseBatch = (BaseBatch-M76 '@BatchDataSource' $MemoriaH2) }
  Escribe $e.Repo 'src/main/resources/application.yml' "spring:`n  datasource:`n    url: `${DB_URL}`n"
  $o = Original-M76 $e @{ 'src/main/resources/application.yml' = "spring:`n  datasource:`n    url: jdbc:oracle:thin:@//host:1521/svc`n" }
  Igual 'el original con Oracle y sin Map, no sale' 0 @(Cal-M76 $e 'repositorio-batch' $o).Count
  $o = Original-M76 $e @{ 'src/main/resources/application.yml' = "spring:`n  datasource:`n    url: `${DB_URL}`n"; 'src/test/resources/application.yml' = "spring:`n  datasource:`n    url: jdbc:h2:mem:t`n" }
  Igual 'el original con url de variable y una H2 solo en src/test, no sale' 0 @(Cal-M76 $e 'repositorio-batch' $o).Count
  $o = Original-M76 $e @{ 'src/main/resources/application.yml' = "spring:`n  datasource:`n    url: jdbc:h2:mem:legado`n" }
  $h = Cal-M76 $e 'repositorio-batch' $o
  Igual 'el original con solo una H2 en memoria, sale' 1 $h.Count
  Comprueba 'y dice que su base es una H2 en memoria' ($h[0].Detalle -like '*El original no guarda las ejecuciones de Batch (su base es una H2 en memoria)*') $h[0].Detalle
}

$Pruebas['m76 (i1) las reglas que fallan al arrancar o cambian en silencio se exigen aunque la plantilla tambien las tenga (circular, bean repetido, parametros v4, nashorn, comando junto); enable-batch no'] = {
  $mismo = { param($pkg) @{
      CiA   = (Pide-M76 'CiA' 'CiB b')
      CiB   = (Pide-M76 'CiB' 'CiA a')
      CfgA  = (Beans-M76 'CfgA' @('@Bean public Lector lector() {') '@Configuration' $pkg)
      CfgB  = (Beans-M76 'CfgB' @('@Bean public Lector lector() {') '@Configuration' $pkg)
      Motor = (Metodo-M76 'Motor' 'Object m = manager.getEngineByName("nashorn"); SystemCommandTasklet t = null; t.setCommand("ls -l");')
      Batch = (Clase-M70 'Batch' "@Configuration`n@EnableBatchProcessing" '')
    } }
  $e = Escenario-M70 'm76-i1' (& $mismo 'com.acme.life.application.usecases') (& $mismo 'com.acme.plantilla.application.usecases')
  Escribe $e.Repo 'bin/lanza.sh' "java -jar b.jar `"n(long)=1`"`n"
  Escribe $e.Plantilla 'bin/lanza.sh' "java -jar b.jar `"n(long)=1`"`n"
  [void](Rescate @('-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-SinBuild'))
  $cal = @(Hallazgos $e.Repo | Where-Object { $_.Cat -eq 'calidad' })
  foreach ($regla in @('referencia-circular', 'bean-repetido', 'parametros-v4', 'nashorn', 'comando-sin-partir')) {
    $r = @($cal | Where-Object { $_.Detalle.StartsWith('[' + $regla + ']') })
    Comprueba "$regla sale" ($r.Count -gt 0) ''
    Igual "$regla sigue siendo error" '' ((@($r | Where-Object { $_.Sev -ne 'error' } | ForEach-Object { $_.Sev }) | Select-Object -Unique) -join ' ')
  }
  $b = @($cal | Where-Object { $_.Detalle.StartsWith('[enable-batch]') })
  Igual 'enable-batch, con la plantilla igual, es aviso' 'aviso' ((@($b | ForEach-Object { $_.Sev }) | Select-Object -Unique) -join ' ')
}

$Pruebas['m76 (i2) el prompt del paso calidad dice que hacer con las reglas de las guias de migracion, y el hallazgo lleva su texto'] = {
  $e = Escenario-M70 'm76-i2' @{ ServicioA = (Pide-M76 'ServicioA' 'ServicioB b'); ServicioB = (Pide-M76 'ServicioB' 'ServicioA a') }
  [void](Rescate @('-Modo', 'fix', '-Repo', $e.Repo, '-Plantilla', $e.Plantilla, '-Paso', 'calidad', '-SinPlan', '-Auto', '-Si', '-MaxIntentos', '1', '-MaxLotes', '1'))
  if (-not (Test-Path -LiteralPath (Join-Path $e.Wt '.git'))) { Comprueba 'existe el worktree' $false; return }
  $prompt = Lee $e.Wt '.rescate/prompt.md'
  Comprueba 'el hallazgo del lote es el del ciclo' ($prompt -match 'ServicioA\.java:\d+ - \[referencia-circular\] Referencia circular entre beans') $prompt
  Comprueba 'el paso dice como romper un ciclo' ($prompt -match 'Referencia circular entre beans: rompe el ciclo sin cambiar lo que hace') $prompt
  Comprueba 'y como dar su base a Batch, avisando de que crea un fichero nuevo' ($prompt -match 'Repositorio de Batch: crea una @Configuration en el paquete de configuracion con un DataSource H2 en memoria marcado con @BatchDataSource') $prompt
  # Spring Boot, How-to Batch (fuentes-m76/sboot-howto-batch.html y sboot32-howto.html): con un @BatchDataSource, el DataSource del negocio se pierde si no se dice nada
  Comprueba 'sin perder el DataSource del negocio (defaultCandidate = false desde Boot 3.4, @Primary antes) y con H2 fuera de test' ($prompt.Contains('sin perder el DataSource del negocio: con Spring Boot 3.4 o mas, @Bean(defaultCandidate = false) en el de Batch; antes, declara el del negocio y marcalo @Primary. H2 va en el pom con scope runtime, no test.')) $prompt
}

# Un original (Spring Batch 4) con un DefaultBatchConfigurer: $Setter es el metodo setDataSource que lleva ($Cabeza, lo que va antes de la clase).
function OriginalConfigurador-M76($E, [string]$Setter, [string]$Cabeza = 'public class SinBase extends DefaultBatchConfigurer') {
  return (Original-M76 $E @{ 'src/main/java/com/acme/life/config/SinBase.java' = "package com.acme.life.config;`n`nimport javax.sql.DataSource;`n`n/** Configurador de Batch. */`n$Cabeza {`n$Setter`n}`n" })
}

# Un escenario con el migrado a la base del negocio (url de variable) y la plantilla con su base propia de Batch.
function EscenarioBase-M76([string]$Nombre, [hashtable]$Repo = @{}) {
  $e = Escenario-M70 $Nombre $Repo @{ BaseBatch = (BaseBatch-M76 '@BatchDataSource' $MemoriaH2) }
  Escribe $e.Repo 'src/main/resources/application.yml' "spring:`n  datasource:`n    url: `${DB_URL}`n"
  return $e
}

$Pruebas['m76 (i3) repositorio-batch: un DefaultBatchConfigurer del original (con extends o anonimo) que sobrescribe setDataSource con el cuerpo vacio deja el repositorio en memoria: sale'] = {
  $e = EscenarioBase-M76 'm76-i3'
  $vacio = "    @Override`n    public void setDataSource(DataSource dataSource) {`n    }"
  $o = OriginalConfigurador-M76 $e $vacio
  $h = Cal-M76 $e 'repositorio-batch' $o
  Igual 'con extends y el cuerpo vacio, sale una vez' 1 $h.Count
  Comprueba 'y el texto dice por que' ($h[0].Detalle -like '*El original no guarda las ejecuciones de Batch (sobrescribe setDataSource vacio en DefaultBatchConfigurer, que deja el repositorio en memoria)*') $h[0].Detalle
  $o = OriginalConfigurador-M76 $e "    @Bean`n    BatchConfigurer configurer() {`n        return new DefaultBatchConfigurer() {`n            @Override`n            public void setDataSource(final DataSource ds) {}`n        };`n    }" 'public class Configuracion'
  Igual 'anonimo, con un parametro final y las llaves juntas, sale' 1 @(Cal-M76 $e 'repositorio-batch' $o).Count
  $o = OriginalConfigurador-M76 $e "    @Override`n    public void setDataSource(DataSource dataSource) {`n        // sin base: el repositorio va en memoria`n        /* nada */`n    }"
  Igual 'con el cuerpo solo de comentarios, sale' 1 @(Cal-M76 $e 'repositorio-batch' $o).Count
}

$Pruebas['m76 (i4) repositorio-batch: un setDataSource del original que llama a super o asigna el campo, o uno vacio en un fichero que no nombra DefaultBatchConfigurer, no cuenta'] = {
  $e = EscenarioBase-M76 'm76-i4'
  $o = OriginalConfigurador-M76 $e "    @Override`n    public void setDataSource(DataSource dataSource) {`n        super.setDataSource(dataSource);`n    }"
  Igual 'con una llamada a super, no sale' 0 @(Cal-M76 $e 'repositorio-batch' $o).Count
  $o = OriginalConfigurador-M76 $e "    private DataSource ds;`n`n    @Override`n    public void setDataSource(DataSource dataSource) {`n        this.ds = dataSource;`n    }"
  Igual 'con una asignacion al campo, no sale' 0 @(Cal-M76 $e 'repositorio-batch' $o).Count
  $o = OriginalConfigurador-M76 $e "    public void setDataSource(DataSource dataSource) {`n    }" 'public class Gestor'
  Igual 'vacio en una clase que no es un DefaultBatchConfigurer, no sale' 0 @(Cal-M76 $e 'repositorio-batch' $o).Count
}

$Pruebas['m76 (i5) repositorio-batch: un setDataSource vacio dentro de un comentario del original no cuenta'] = {
  $e = EscenarioBase-M76 'm76-i5'
  $o = OriginalConfigurador-M76 $e "    // public void setDataSource(DataSource dataSource) {`n    // }`n    /*`n    public void setDataSource(DataSource dataSource) { }`n    */`n    /** Antes: setDataSource(DataSource d) { }. */`n    void otra() {}"
  Igual 'en comentarios de linea, de bloque y de javadoc, no sale' 0 @(Cal-M76 $e 'repositorio-batch' $o).Count
}

$Pruebas['m76 (i6) repositorio-batch: @EnableBatchProcessing(dataSourceRef = "x") con un DataSource en memoria en el mismo fichero es una base propia de Batch (Spring Batch 5); enable-batch sigue saliendo'] = {
  $cuerpo = "    @Bean(`"batchDs`")`n    public DataSource batchDs() {`n        $MemoriaH2`n    }`n"
  $e = EscenarioBase-M76 'm76-i6' @{ BatchCfg = (Clase-M70 'BatchCfg' "@Configuration`n@EnableBatchProcessing(dataSourceRef = `"batchDs`")" $cuerpo) }
  $o = Original-M76 $e $OriginalMapa
  Igual 'con dataSourceRef y una H2 en memoria, repositorio-batch no sale' 0 @(Cal-M76 $e 'repositorio-batch' $o).Count
  Igual 'y enable-batch sale en esa clase' 'BatchCfg' (Ficheros-M70 @(Cal-M76 $e 'enable-batch' $o))
  Escribe $e.Repo 'src/main/java/com/acme/life/application/usecases/BatchCfg.java' (Clase-M70 'BatchCfg' "@Configuration`n@EnableBatchProcessing(dataSourceRef = `"batchDs`")" $cuerpo.Replace($MemoriaH2, 'return DataSourceBuilder.create().url("jdbc:oracle:thin:@//host:1521/svc").build();'))
  Igual 'con dataSourceRef y un DataSource que no es en memoria, sale' 1 @(Cal-M76 $e 'repositorio-batch' $o).Count
  Escribe $e.Repo 'src/main/java/com/acme/life/application/usecases/BatchCfg.java' (Clase-M70 'BatchCfg' "@Configuration`n@EnableBatchProcessing" $cuerpo)
  Igual 'con un DataSource en memoria pero sin dataSourceRef (Batch sigue en dataSource), sale' 1 @(Cal-M76 $e 'repositorio-batch' $o).Count
}

# Los dos ficheros de un ciclo por constructor entre dos componentes: Pide-M76 de cada uno con lo que pide (para varios pares a la vez).
function Par-M76([string]$A, [string]$ParamA, [string]$B, [string]$ParamB, [string]$Cabeza = '@Service') {
  return @{ $A = (Pide-M76 $A $ParamA $Cabeza); $B = (Pide-M76 $B $ParamB $Cabeza) }
}

$Pruebas['m76 (j1) referencia-circular: un ciclo a traves de List<X>, Optional<X> o Set<? extends X> en el constructor sale (pide los beans del ultimo generico)'] = {
  $repo = @{}
  foreach ($par in @(@('LiA', 'List<LiB> bs', 'LiB', 'LiA a'), @('OpA', 'Optional<OpB> b', 'OpB', 'OpA a'), @('SeA', 'Set<? extends SeB> bs', 'SeB', 'SeA a'))) { $repo += Par-M76 $par[0] $par[1] $par[2] $par[3] }
  $e = Escenario-M70 'm76-j1' $repo
  Igual 'salen las seis clases' 'LiA LiB OpA OpB SeA SeB' (Ficheros-M70 (Cal-M76 $e 'referencia-circular'))
}

$Pruebas['m76 (j2) referencia-circular: un ciclo a traves de un supertipo de un supertipo (clase -> clase -> interfaz que se pide) sale'] = {
  $e = Escenario-M70 'm76-j2' @{
    Puerto0    = (Java-M76 'Puerto0' 'interface')
    Base       = (Java-M76 'Base' 'class' '' ' implements Puerto0')
    Adap       = ((Pide-M76 'Adap' 'Consumidor c' '@Component') -replace 'public class Adap ', 'public class Adap extends Base ')
    Consumidor = (Pide-M76 'Consumidor' 'Puerto0 p')
  }
  Igual 'salen Adap y Consumidor' 'Adap Consumidor' (Ficheros-M70 (Cal-M76 $e 'referencia-circular'))
}

$Pruebas['m76 (j3) referencia-circular: un ciclo a traves de implements Puerto<Algo> (interfaz con genericos) sale'] = {
  $e = Escenario-M70 'm76-j3' @{
    PuertoG  = (Java-M76 'PuertoG<T>' 'interface')
    AdapG    = (Implementa-M76 'AdapG' 'PuertoG<String>' 'ClienteG c')
    ClienteG = (Pide-M76 'ClienteG' 'PuertoG p')
  }
  Igual 'salen AdapG y ClienteG' 'AdapG ClienteG' (Ficheros-M70 (Cal-M76 $e 'referencia-circular'))
}

$Pruebas['m76 (j4) referencia-circular: un ciclo a traves de un metodo @Autowired (un setter) sale; con @Lazy en el metodo, no'] = {
  $e = Escenario-M70 'm76-j4' @{
    SetA = (Clase-M70 'SetA' '@Service' "    @Autowired`n    public void setB(SetB b) {`n    }`n")
    SetB = (Pide-M76 'SetB' 'SetA a')
    SetC = (Clase-M70 'SetC' '@Service' "    @Autowired`n    @Lazy`n    public void setD(SetD d) {`n    }`n")
    SetD = (Pide-M76 'SetD' 'SetC c')
  }
  Igual 'salen SetA y SetB, y no SetC ni SetD (con @Lazy)' 'SetA SetB' (Ficheros-M70 (Cal-M76 $e 'referencia-circular'))
}

$Pruebas['m76 (j5) bean-repetido: el nombre del bean de una clase es el de Introspector.decapitalize: URLLector se queda como esta y Servicio pasa a servicio'] = {
  $e = Escenario-M70 'm76-j5' @{ URLLector = (Clase-M70 'URLLector' '@Service' ''); Servicio = (Clase-M70 'Servicio' '@Service' '') }
  $otro = 'com.acme.life.infrastructure.adapters'
  Escribe $e.Repo 'src/main/java/com/acme/life/infrastructure/adapters/URLLector.java' (Clase-M70 'URLLector' '@Component' '' $otro)
  Escribe $e.Repo 'src/main/java/com/acme/life/infrastructure/adapters/Servicio.java' (Clase-M70 'Servicio' '@Component' '' $otro)
  $h = Cal-M76 $e 'bean-repetido'
  Igual 'salen las dos clases en sus dos paquetes' 'Servicio Servicio URLLector URLLector' (Ficheros-M70 $h)
  Comprueba "el nombre de URLLector es 'URLLector' (las dos primeras en mayuscula)" (@($h | Where-Object { $_.Fichero -like '*URLLector.java' -and $_.Detalle -clike "*el mismo nombre de bean 'URLLector' (*" }).Count -eq 2) (($h | ForEach-Object { $_.Detalle }) -join ' / ')
  Comprueba "y el de Servicio es 'servicio'" (@($h | Where-Object { $_.Fichero -like '*Servicio.java' -and $_.Detalle -clike "*el mismo nombre de bean 'servicio' (*" }).Count -eq 2) (($h | ForEach-Object { $_.Detalle }) -join ' / ')
}

$Pruebas['m76 (j6) varios-jobs-sin-nombre: SPRING_BATCH_JOB_NAME como variable de entorno en un script o en el Dockerfile cuenta como nombre'] = {
  $e = Escenario-M70 'm76-j6' @{
    Jobs1 = (Beans-M76 'Jobs1' @('@Bean public Job altaJob(JobRepository r) {'))
    Jobs2 = (Beans-M76 'Jobs2' @('@Bean public Job bajaJob(JobRepository r) {'))
  }
  Igual 'sin nombre, sale' 1 @(Cal-M76 $e 'varios-jobs-sin-nombre').Count
  Escribe $e.Repo 'bin/lanza.sh' "#!/bin/sh`nSPRING_BATCH_JOB_NAME=altaJob java -jar batch-life.jar`n"
  Igual 'con la variable en un script, no sale' 0 @(Cal-M76 $e 'varios-jobs-sin-nombre').Count
  Remove-Item -LiteralPath (Join-Path $e.Repo 'bin/lanza.sh') -Force
  Escribe $e.Repo 'Dockerfile' "FROM eclipse-temurin:21`nENV SPRING_BATCH_JOB_NAME=altaJob`nCMD [`"java`", `"-jar`", `"batch-life.jar`"]`n"
  Igual 'con ENV en el Dockerfile, no sale' 0 @(Cal-M76 $e 'varios-jobs-sin-nombre').Count
}

$Pruebas['m76 (j7) referencia-circular: un componente con @StepScope o @JobScope dentro de un ciclo no cuenta (Spring lo crea al empezar el step, no al arrancar)'] = {
  $repo = Par-M76 'SsA' 'SsB b' 'SsB' 'SsA a'
  $repo['SsA'] = (Pide-M76 'SsA' 'SsB b' "@Component`n@StepScope")
  $repo += @{ JsA = (Pide-M76 'JsA' 'JsB b' "@Component`n@JobScope"); JsB = (Pide-M76 'JsB' 'JsA a') }
  $e = Escenario-M70 'm76-j7' $repo
  Igual 'no sale ninguno' '' (Ficheros-M70 (Cal-M76 $e 'referencia-circular'))
}

$Pruebas['m76 (j8) referencia-circular: un @Bean static no depende de su clase de configuracion; sin static, el ciclo sale'] = {
  $miembros = { param($mod) "    private final Lector lector;`n`n" + (Ctor-M70 'FabCfg' '' 'Lector lector') + "    @Bean`n    public $mod Lector lector() {`n        return null;`n    }`n" }
  $e = Escenario-M70 'm76-j8' @{ FabCfg = (Clase-M70 'FabCfg' '@Configuration' (& $miembros 'static')) }
  Igual 'con static, no sale' '' (Ficheros-M70 (Cal-M76 $e 'referencia-circular'))
  Escribe $e.Repo 'src/main/java/com/acme/life/application/usecases/FabCfg.java' (Clase-M70 'FabCfg' '@Configuration' (& $miembros ''))
  Igual 'sin static, sale' 'FabCfg' (Ficheros-M70 (Cal-M76 $e 'referencia-circular'))
}

$Pruebas['m76 (j9) referencia-circular: con @RequiredArgsConstructor un campo final con valor inicial no se pide; sin valor inicial, si'] = {
  $e = Escenario-M70 'm76-j9' @{
    RqA = (Clase-M70 'RqA' "@Service`n@RequiredArgsConstructor" "    private final RqB b = new RqB(null);`n")
    RqB = (Pide-M76 'RqB' 'RqA a')
    RqD = (Clase-M70 'RqD' "@Service`n@RequiredArgsConstructor" "    private final RqE e;`n")
    RqE = (Pide-M76 'RqE' 'RqD d')
  }
  Igual 'salen RqD y RqE, y no RqA ni RqB' 'RqD RqE' (Ficheros-M70 (Cal-M76 $e 'referencia-circular'))
}

$Pruebas['m76 (j10) bean-repetido: dos componentes con el mismo nombre de clase, uno con @Conditional* o @Conditional(...), no salen; sin condicion, si'] = {
  $e = Escenario-M70 'm76-j10' @{
    Cond1 = (Clase-M70 'Cond1' "@Service`n@ConditionalOnMissingBean" '')
    Cond2 = (Clase-M70 'Cond2' "@Service`n@Conditional(MiCondicion.class)" '')
    Libre = (Clase-M70 'Libre' '@Service' '')
  }
  $otro = 'com.acme.life.infrastructure.adapters'
  foreach ($n in @('Cond1', 'Cond2', 'Libre')) { Escribe $e.Repo "src/main/java/com/acme/life/infrastructure/adapters/$n.java" (Clase-M70 $n '@Component' '' $otro) }
  Igual 'sale Libre en sus dos paquetes, y no Cond1 ni Cond2' 'Libre Libre' (Ficheros-M70 (Cal-M76 $e 'bean-repetido'))
}

$Pruebas['m76 (j11) nashorn: getEngineByName("nashorn") dentro de un comentario de linea o de bloque no sale'] = {
  $e = Escenario-M70 'm76-j11' @{
    Real   = (Metodo-M76 'Real' 'Object m = manager.getEngineByName("nashorn");')
    Linea  = (Metodo-M76 'Linea' '// Object m = manager.getEngineByName("nashorn");')
    Bloque = (Metodo-M76 'Bloque' '/* Object m = manager.getEngineByName("js"); */')
  }
  Igual 'sale Real y no los comentarios' 'Real' (Ficheros-M70 (Cal-M76 $e 'nashorn'))
}

$Pruebas['m76 (j12) referencia-circular: con dos constructores solo cuenta el que lleva @Autowired; los parametros del otro no crean un ciclo'] = {
  $e = Escenario-M70 'm76-j12' @{
    CtA = (Clase-M70 'CtA' '@Service' ((Ctor-M70 'CtA' '@Autowired' 'String texto') + (Ctor-M70 'CtA' '' 'CtB b')))
    CtB = (Pide-M76 'CtB' 'CtA a')
  }
  Igual 'con @Autowired en el que no pide CtB, no sale' '' (Ficheros-M70 (Cal-M76 $e 'referencia-circular'))
  Escribe $e.Repo 'src/main/java/com/acme/life/application/usecases/CtA.java' (Clase-M70 'CtA' '@Service' ((Ctor-M70 'CtA' '' 'String texto') + (Ctor-M70 'CtA' '@Autowired' 'CtB b')))
  Igual 'con @Autowired en el que pide CtB, sale' 'CtA CtB' (Ficheros-M70 (Cal-M76 $e 'referencia-circular'))
}

$Pruebas['m76 (j13) referencia-circular: un ciclo a traves de una interfaz que extiende la que se pide (interface Puerto1 extends Puerto0, con o sin genericos) sale'] = {
  $e = Escenario-M70 'm76-j13' @{
    Puerto0     = (Java-M76 'Puerto0' 'interface')
    Puerto1     = (Java-M76 'Puerto1' 'interface' '' ' extends Puerto0')
    Adap        = (Implementa-M76 'Adap' 'Puerto1' 'Consumidor c')
    Consumidor  = (Pide-M76 'Consumidor' 'Puerto0 p')
    PuertoG0    = (Java-M76 'PuertoG0<T>' 'interface')
    PuertoG1    = (Java-M76 'PuertoG1<T>' 'interface' '' ' extends PuertoG0<T>')
    AdapG       = (Implementa-M76 'AdapG' 'PuertoG1<String>' 'ConsumidorG c')
    ConsumidorG = (Pide-M76 'ConsumidorG' 'PuertoG0 p')
  }
  Igual 'salen los dos ciclos' 'Adap AdapG Consumidor ConsumidorG' (Ficheros-M70 (Cal-M76 $e 'referencia-circular'))
}

# ================================ M99: COBERTURA CUANDO EL POM YA TRAE JACOCO ================================
# Si el pom (o su padre) ya ata prepare-agent de JaCoCo con otra version, la JVM de los tests arranca con dos agentes y muere (LinkageError):
# Get-Cobertura usa entonces las coordenadas sin version (la que declara el pom). Si el pom no lo trae pero el padre si, repite una vez sin version.
$PomJacoco = $Pom.Replace('</project>', "  <build><plugins><plugin><groupId>org.jacoco</groupId><artifactId>jacoco-maven-plugin</artifactId><version>0.8.14</version></plugin></plugins></build>`n</project>")

# Get-Cobertura sobre un repo de una clase (4 lineas, 2 cubiertas) con el Maven de mentira de cobertura-mvn.ps1 y el guion $Guion.
# Devuelve la medida, las lineas de JaCoCo que dejo Maven en .rescate/cobertura-mvn.log (una por llamada) y lo que escribio el proceso.
function Cobertura-M99([string]$Nombre, [string]$PomTexto, [string]$Guion = '') {
  $raiz = Join-Path $Dir $Nombre
  if (Test-Path -LiteralPath $raiz) { Remove-Item -LiteralPath $raiz -Recurse -Force }
  Escribe $raiz 'pom.xml' $PomTexto
  Escribe $raiz 'src/main/java/com/acme/batch/Alta.java' "package com.acme.batch;`npublic class Alta {`n    // LINEAS: 4`n}`n"
  Escribe $raiz 'src/test/java/com/acme/batch/AltaTest.java' "package com.acme.batch;`npublic class AltaTest {`n    // CUBRE: 2`n}`n"
  [void](New-Item -ItemType Directory -Path (Join-Path $raiz '.rescate') -Force)
  $f = Join-Path $Dir ($Nombre + '.ps1')
  [System.IO.File]::WriteAllText($f, @'
param([string]$Sis, [string]$Mvn, [string]$Carpeta, [string]$Registro)
. (Join-Path $Sis 'comun.ps1')
$Cfg.MvnExe = $Mvn
$Cfg.SegundosLatido = 0
ConvertTo-Json -InputObject (Get-Cobertura $Carpeta $Registro $true) -Depth 4 -Compress
'@)
  $r = Lanzar $f @((Split-Path -Parent $Script), (Join-Path $falsos 'cobertura-mvn.ps1'), $raiz, (Join-Path $Dir ($Nombre + '.log'))) $Guion
  $o = $null
  try { $o = @($r.Salida -split "`r?`n")[-1] | ConvertFrom-Json } catch { }
  $ll = @([System.IO.File]::ReadAllLines((Join-Path (Join-Path $raiz '.rescate') 'cobertura-mvn.log')) | Where-Object { $_ -match 'jacoco' })
  return [pscustomobject]@{ Medida = $o; Jacoco = $ll; Salida = $r.Salida }
}

$Pruebas['m99 cobertura: con jacoco-maven-plugin en el pom Maven lleva las coordenadas sin version; sin el, la version fija'] = {
  $con = Cobertura-M99 'm99-con' $PomJacoco
  Comprueba 'mide' ($con.Medida.medida -eq $true) (Cola $con.Salida)
  Igual 'un solo Maven de JaCoCo' 1 $con.Jacoco.Count
  Comprueba 'lleva org.jacoco:jacoco-maven-plugin:prepare-agent' ("$($con.Jacoco[0])" -match 'org\.jacoco:jacoco-maven-plugin:prepare-agent') "$($con.Jacoco -join ' / ')"
  Comprueba 'y no lleva 0.8.16' ("$($con.Jacoco[0])" -notmatch '0\.8\.16') "$($con.Jacoco -join ' / ')"
  $sin = Cobertura-M99 'm99-sin' $Pom
  Comprueba 'sin jacoco en el pom mide' ($sin.Medida.medida -eq $true) (Cola $sin.Salida)
  Igual 'un solo Maven de JaCoCo' 1 $sin.Jacoco.Count
  Comprueba 'lleva org.jacoco:jacoco-maven-plugin:0.8.16:prepare-agent' ("$($sin.Jacoco[0])" -match 'org\.jacoco:jacoco-maven-plugin:0\.8\.16:prepare-agent') "$($sin.Jacoco -join ' / ')"
}

$Pruebas['m99 cobertura: dos agentes por el pom padre - falla con la version fija, repite una vez sin version y mide'] = {
  $r = Cobertura-M99 'm99-padre' $Pom 'cob-mvn-doble'
  Comprueba 'mide' ($r.Medida.medida -eq $true) (Cola $r.Salida)
  Igual 'el 50 % de las 4 lineas' 50 $r.Medida.porcentaje
  Igual 'dos Maven de JaCoCo' 2 $r.Jacoco.Count
  Comprueba 'el primero con la version fija' ("$($r.Jacoco[0])" -match 'jacoco-maven-plugin:0\.8\.16:prepare-agent') "$($r.Jacoco -join ' / ')"
  Comprueba 'el segundo sin version' ("$($r.Jacoco[-1])" -match 'org\.jacoco:jacoco-maven-plugin:prepare-agent' -and "$($r.Jacoco[-1])" -notmatch '0\.8\.16') "$($r.Jacoco -join ' / ')"
}

$Pruebas['m99 cobertura: dos agentes aun sin version - no mide, el motivo lo dice y no hay un tercer intento; con el plugin en el pom, un solo intento'] = {
  $r = Cobertura-M99 'm99-siempre' $Pom 'cob-mvn-doble-siempre'
  Igual 'no hay medida' $false $r.Medida.medida
  Comprueba 'el motivo habla de dos agentes de JaCoCo' ("$($r.Medida.motivo)" -match 'dos agentes de JaCoCo' -and "$($r.Medida.motivo)" -notmatch 'surefire') "$($r.Medida.motivo)"
  Igual 'dos Maven de JaCoCo, no tres' 2 $r.Jacoco.Count
  $c = Cobertura-M99 'm99-siempre-pom' $PomJacoco 'cob-mvn-doble-siempre'
  Comprueba 'con el plugin en el pom el motivo es el mismo' ("$($c.Medida.motivo)" -match 'dos agentes de JaCoCo') "$($c.Medida.motivo)"
  Igual 'y Maven se lanza una sola vez' 1 $c.Jacoco.Count
}

# ================================ LANZADOR ================================
Invoke-Banco $Pruebas $Script
