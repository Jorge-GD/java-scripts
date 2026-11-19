<#
probar-practicas.ps1 - Banco de pruebas de practicas.ps1 (BP-0: las buenas practicas dentro del diagnostico, sin IA).
No necesita Maven ni Java: usa el Maven de mentira tests/falsos/bp0-mvn.ps1 (el javac sale de un fichero con lineas como las de Maven; SpotBugs y
PMD, de los XML reales de tests/datos/analisis) y el javap de mentira tests/falsos/bp0-javap.ps1, cuyos .class de mentira llevan el texto que dio
un javap real (JDK 21, -c -l -p) sobre dos clases de juguete. Nunca llama al Maven ni al JDK reales.
Vale para Windows PowerShell 5.1 y para PowerShell 7. Solo ASCII a proposito.

  .\tests\probar-practicas.ps1                       # todas las pruebas
  .\tests\probar-practicas.ps1 -Solo cache           # las que llevan 'cache' en el nombre
  .\tests\probar-practicas.ps1 -Dir D:\tmp\x -Conservar

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
$datos = Join-Path (Join-Path $aqui 'datos') 'analisis'
. (Join-Path $aqui 'comun-banco.ps1')
. (Join-Path $raiz 'comun.ps1')
. (Join-Path $raiz 'tareas.ps1')
. (Join-Path $raiz 'analisis.ps1')
. (Join-Path $raiz 'practicas.ps1')

# ================================ DATOS ================================
# Lo que dio javap -c -l -p (JDK 21) sobre estas dos clases. Remesa lleva sus getters y setters escritos a mano (3 getters triviales: getId,
# getImporte e isActiva, y 2 setters: setId y setImporte; getLineas no es trivial, total no es un getter). Cliente es lo que genera Lombok:
# el .java lleva @Getter y @Setter y ninguno de sus metodos.
$JavapRemesa = @'
Compiled from "Remesa.java"
public class com.acme.domain.Remesa {
  private java.lang.String id;

  private long importe;

  private boolean activa;

  private java.util.List<java.lang.String> lineas;

  public com.acme.domain.Remesa();
    Code:
       0: aload_0
       1: invokespecial #1                  // Method java/lang/Object."<init>":()V
       4: aload_0
       5: new           #7                  // class java/util/ArrayList
       8: dup
       9: invokespecial #9                  // Method java/util/ArrayList."<init>":()V
      12: putfield      #10                 // Field lineas:Ljava/util/List;
      15: return
    LineNumberTable:
      line 12: 0
      line 10: 4
      line 13: 15

  public java.lang.String getId();
    Code:
       0: aload_0
       1: getfield      #16                 // Field id:Ljava/lang/String;
       4: areturn
    LineNumberTable:
      line 16: 0

  public void setId(java.lang.String);
    Code:
       0: aload_0
       1: aload_1
       2: putfield      #16                 // Field id:Ljava/lang/String;
       5: return
    LineNumberTable:
      line 20: 0
      line 21: 5

  public long getImporte();
    Code:
       0: aload_0
       1: getfield      #20                 // Field importe:J
       4: lreturn
    LineNumberTable:
      line 24: 0

  public void setImporte(long);
    Code:
       0: aload_0
       1: lload_1
       2: putfield      #20                 // Field importe:J
       5: return
    LineNumberTable:
      line 28: 0
      line 29: 5

  public boolean isActiva();
    Code:
       0: aload_0
       1: getfield      #24                 // Field activa:Z
       4: ireturn
    LineNumberTable:
      line 32: 0

  public java.util.List<java.lang.String> getLineas();
    Code:
       0: new           #7                  // class java/util/ArrayList
       3: dup
       4: aload_0
       5: getfield      #10                 // Field lineas:Ljava/util/List;
       8: invokespecial #28                 // Method java/util/ArrayList."<init>":(Ljava/util/Collection;)V
      11: areturn
    LineNumberTable:
      line 36: 0

  public long total();
    Code:
       0: aload_0
       1: getfield      #20                 // Field importe:J
       4: ldc2_w        #31                 // long 2l
       7: lmul
       8: lreturn
    LineNumberTable:
      line 40: 0
}
'@
$JavapCliente = @'
Compiled from "Cliente.java"
public class com.acme.domain.Cliente {
  private java.lang.String nombre;

  private int edad;

  public com.acme.domain.Cliente();
    Code:
       0: aload_0
       1: invokespecial #1                  // Method java/lang/Object."<init>":()V
       4: return
    LineNumberTable:
      line 3: 0

  public java.lang.String getNombre();
    Code:
       0: aload_0
       1: getfield      #7                  // Field nombre:Ljava/lang/String;
       4: areturn
    LineNumberTable:
      line 8: 0

  public int getEdad();
    Code:
       0: aload_0
       1: getfield      #13                 // Field edad:I
       4: ireturn
    LineNumberTable:
      line 12: 0

  public void setNombre(java.lang.String);
    Code:
       0: aload_0
       1: aload_1
       2: putfield      #7                  // Field nombre:Ljava/lang/String;
       5: return
    LineNumberTable:
      line 16: 0
      line 17: 5

  public com.acme.domain.Cliente conEdad(int);
    Code:
       0: aload_0
       1: iload_1
       2: putfield      #13                 // Field edad:I
       5: aload_0
       6: areturn
    LineNumberTable:
      line 20: 0
      line 21: 5
}
'@
$FuenteRemesa = @'
package com.acme.domain;

import java.util.ArrayList;
import java.util.List;

public class Remesa {
    private String id;
    private long importe;
    private boolean activa;
    private List<String> lineas = new ArrayList<>();

    public Remesa() {
    }

    public String getId() {
        return id;
    }

    public void setId(String id) {
        this.id = id;
    }

    public long getImporte() {
        return importe;
    }

    public void setImporte(long importe) {
        this.importe = importe;
    }

    public boolean isActiva() {
        return activa;
    }

    public List<String> getLineas() {
        return new ArrayList<>(lineas);
    }

    public long total() {
        return importe * 2;
    }
}
'@
$FuenteCliente = @'
package com.acme.domain;

import lombok.Getter;
import lombok.Setter;

@Getter
@Setter
public class Cliente {
    private String nombre;
    private int edad;

    public Cliente conEdad(int e) {
        this.edad = e;
        return this;
    }

    public String etiqueta() {
        return getNombre() + edad;
    }
}
'@
# Las tres formas de un aviso de javac: el tipo es lo que va detras de ' in ' (el miembro puede ser un metodo de otro paquete).
$TextoSpring = 'org.springframework.batch.core.configuration.annotation.JobBuilderFactory in org.springframework.batch.core.configuration.annotation has been deprecated and marked for removal'
$TextoInteger = 'Integer(int) in java.lang.Integer has been deprecated and marked for removal'
$TextoTasklet = 'tasklet(org.springframework.batch.core.step.tasklet.Tasklet) in org.springframework.batch.core.step.builder.StepBuilder has been deprecated and marked for removal'
$FichConfig = 'src/main/java/com/acme/demo/BatchConfig.java'

# ============================== UTILIDADES ==============================
function Lee-Json([string]$Ruta) {
  if (-not (Test-Path -LiteralPath $Ruta -PathType Leaf)) { return $null }
  return ([System.IO.File]::ReadAllText($Ruta) | ConvertFrom-Json)
}

# Un aviso de javac como lo imprime Maven (con {{RAIZ}}, que el Maven falso cambia por la carpeta donde se lanza).
function Aviso-Javac([string]$Fichero, [int]$Linea, [string]$Texto) { return "[WARNING] {{RAIZ}}/${Fichero}:[$Linea,26] $Texto" }

function Escribe-Salida($E, [string[]]$Lineas) {
  Escribe $E.Raiz 'salida-javac.txt' (($Lineas -join "`n") + "`n")
  return (Join-Path $E.Raiz 'salida-javac.txt')
}

# Un escenario: el migrado (un repo git con las dos clases de analisis, mas Remesa y Cliente), la referencia (con o sin Lombok), los .class de
# mentira que 'compila' el Maven falso (en clases/) y las carpetas de datos y registros.
function Nuevo-Escenario([string]$Nombre, [bool]$RefLombok = $false) {
  $r = Join-Path $Dir $Nombre
  if (Test-Path -LiteralPath $r) { Remove-Item -LiteralPath $r -Recurse -Force }
  $mig = Join-Path $r 'migrado'
  Copy-Item -LiteralPath (Join-Path $datos 'juguete') -Destination $mig -Recurse
  Escribe $mig 'src/main/java/com/acme/domain/Remesa.java' $FuenteRemesa
  Escribe $mig 'src/main/java/com/acme/domain/Cliente.java' $FuenteCliente
  Inicia-Repo $mig
  $ref = Join-Path $r 'batch-ejemplo'
  $dep = ''
  if ($RefLombok) { $dep = '<dependencies><dependency><groupId>org.projectlombok</groupId><artifactId>lombok</artifactId><version>1.18.34</version></dependency></dependencies>' }
  Escribe $ref 'pom.xml' "<project><modelVersion>4.0.0</modelVersion><groupId>com.acme</groupId><artifactId>batch-ejemplo</artifactId><version>1</version>$dep</project>`n"
  $imp = ''
  if ($RefLombok) { $imp = "import lombok.Getter;`n`n" }
  Escribe $ref 'src/main/java/com/acme/ejemplo/Ref.java' "package com.acme.ejemplo;`n`n${imp}public class Ref { }`n"
  Escribe $r 'clases/com/acme/domain/Remesa.class' $JavapRemesa
  Escribe $r 'clases/com/acme/domain/Cliente.class' $JavapCliente
  foreach ($d in @('datos', 'registros')) { [void](New-Item -ItemType Directory -Path (Join-Path $r $d) -Force) }
  return [pscustomobject]@{
    Raiz = $r; Repo = $mig; Ref = $ref; Datos = (Join-Path $r 'datos'); Registros = (Join-Path $r 'registros'); Clases = (Join-Path $r 'clases')
    Hallazgos = (Join-Path $r 'hallazgos.json'); Llamadas = (Join-Path $r 'mvn-llamadas.txt'); Javap = (Join-Path $r 'javap-llamadas.txt')
  }
}

# Corre $Bloque con los falsos (Cfg.MvnExe y Cfg.JavapExe), los ajustes de $Ajustes en $Cfg y las variables de entorno de $Entorno; al salir deja todo como estaba.
function Con-Falso([hashtable]$Entorno, [hashtable]$Ajustes, [scriptblock]$Bloque) {
  $todo = @{ MvnExe = (Join-Path $falsos 'bp0-mvn.ps1'); JavapExe = (Join-Path $falsos 'bp0-javap.ps1'); SegundosLatido = 0 }
  foreach ($k in $Ajustes.Keys) { $todo[$k] = $Ajustes[$k] }
  $cfgAntes = @{}
  foreach ($k in $todo.Keys) { $cfgAntes[$k] = $Cfg[$k]; $Cfg[$k] = $todo[$k] }
  $envAntes = @{}
  foreach ($k in $Entorno.Keys) { $envAntes[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $Entorno[$k]) }
  try { return (& $Bloque) }
  finally {
    foreach ($k in $Entorno.Keys) { [Environment]::SetEnvironmentVariable($k, $envAntes[$k]) }
    foreach ($k in $cfgAntes.Keys) { $Cfg[$k] = $cfgAntes[$k] }
  }
}

# Invoke-Practicas sobre el escenario con los falsos. Devuelve el JSON que dejo, lo que dijo por consola (Texto) y los avisos (las lineas amarillas).
function Mide($E, [hashtable]$Entorno = @{}, [hashtable]$Ajustes = @{}, [string]$Cuando = 'antes', [switch]$ConCache) {
  # sin -ConCache se borra el JSON de antes: la prueba cambia cosas que la clave no mira (la referencia, los falsos)
  if (-not $ConCache) { Remove-Item -LiteralPath (Join-Path $E.Datos "practicas-$Cuando.json") -Force -ErrorAction SilentlyContinue }
  $Entorno['BP0_LLAMADAS'] = $E.Llamadas
  $Entorno['BP0_JAVAP_LLAMADAS'] = $E.Javap
  $todo = @(Con-Falso $Entorno $Ajustes { Invoke-Practicas $E.Repo $E.Ref $Cuando $E.Datos $E.Registros $E.Hallazgos } 6>&1)
  $info = @($todo | Where-Object { $_ -is [System.Management.Automation.InformationRecord] })
  return [pscustomobject]@{
    Json = (Lee-Json (Join-Path $E.Datos "practicas-$Cuando.json"))
    Texto = (@($info | ForEach-Object { "$_" }) -join "`n")
    Avisos = @($info | Where-Object { "$($_.MessageData.ForegroundColor)" -ceq 'Yellow' } | ForEach-Object { "$_" })
  }
}

function Llamadas-De([string]$Fichero) {
  if (-not (Test-Path -LiteralPath $Fichero)) { return , @() }
  return , @([System.IO.File]::ReadAllLines($Fichero) | Where-Object { $_ })
}

function Det($J, [string]$Id) { return @($J.detectores | Where-Object { $_.id -ceq $Id })[0] }

function Inc($J, [string]$Herramienta) { return , @($J.incidencias | Where-Object { $_.herramienta -ceq $Herramienta }) }

# El hallazgo de un motor de mentira, como los escribe rescate.ps1 en hallazgos.json (Cat, Sev, Fichero, Linea y Detalle).
function Hallazgo([string]$Sev, [string]$Fichero, [int]$Linea) {
  return [ordered]@{ Cat = 'calidad'; Sev = $Sev; Fichero = $Fichero; Linea = $Linea; Detalle = 'un problema de ejemplo' }
}

# ================================ PRUEBAS ================================
$Pruebas = [ordered]@{}

# Con 25 s de tope total quedan menos de 30 s para PMD y SpotBugs: no se miden (no medido (tope)) y la prueba no gasta sus 4 llamadas a Maven.
$Rapido = @{ SegundosPracticas = 25 }

$AvisoTexto = 'viejo() in com.acme.demo.Viejo has been deprecated'
$FichUtil = 'src/main/java/com/acme/demo/Util.java'

$FuenteServicio = @'
package com.acme.demo;

import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;

@RequiredArgsConstructor
public class Servicio {
    @Qualifier("remesas")
    private final Repositorio repositorio;

    @Value("${acme.destino}")
    private final String destino;

    @Value("${acme.opcional}")
    private String opcional;

    private final Otro otro;
}
'@

# Comprobaciones de las incidencias de la clase Servicio: cuantas hay de Lombok-qualifier y de que campos.
function Qualifier-De($J) { return , @($J.incidencias | Where-Object { $_.regla -ceq 'qualifier-sin-copiar' } | Sort-Object { [int]$_.linea }) }

$Pruebas['1 a) javac: un aviso for removal de Spring y otro de java.lang dan dos incidencias S5738, cada una en su area'] = {
  $E = Nuevo-Escenario 'a1'
  $salida = Escribe-Salida $E @(
    (Aviso-Javac $FichConfig 16 $TextoSpring),
    (Aviso-Javac $FichConfig 16 $TextoSpring),
    (Aviso-Javac $FichUtil 9 $TextoInteger),
    (Aviso-Javac $FichUtil 12 $AvisoTexto),
    '[WARNING] Some problems were encountered while building the effective model')
  Escribe $E.Repo 'target/classes/viejo/Viejo.class' 'x'
  Escribe $E.Repo 'target/maven-status/viejo.lst' 'x'
  Escribe $E.Repo 'target/reports/queda.txt' 'x'
  $m = Mide $E @{ BP0_JAVAC_SALIDA = $salida } $Rapido
  $j = $m.Json
  Comprueba 'deja datos\practicas-antes.json' ($null -ne $j)
  $d = Det $j 'javac'
  Igual 'javac: estado' 'ok' $d.estado
  Igual 'javac: motivo vacio' '' $d.motivo
  Igual 'javac: 4 avisos de ficheros .java, sin corte' $false $d.corte
  $jv = Inc $j 'javac'
  Igual 'dos incidencias (el aviso repetido cuenta una vez; el deprecated sin removal y el de Maven, ninguna)' 2 $jv.Count
  $sp = @($jv | Where-Object { $_.fichero -ceq $FichConfig })
  Igual 'Spring: una incidencia en BatchConfig.java' 1 $sp.Count
  Igual 'Spring: area' 'boot3-batch5' $sp[0].area
  Igual 'Spring: linea' 16 $sp[0].linea
  Igual 'Spring: sonar S5738' 'S5738' $sp[0].sonar
  Igual 'Spring: origen' 'sonar' $sp[0].origen
  Igual 'Spring: queHago' 'sonar' $sp[0].queHago
  Igual 'Spring: herramienta' 'javac' $sp[0].herramienta
  Comprueba 'Spring: el texto es el de javac' ("$($sp[0].texto)" -like '*JobBuilderFactory*marked for removal') "$($sp[0].texto)"
  $ja = @($jv | Where-Object { $_.fichero -ceq $FichUtil })
  Igual 'java.lang: una incidencia en Util.java' 1 $ja.Count
  Igual 'java.lang: area' 'java21' $ja[0].area
  Igual 'java.lang: linea' 9 $ja[0].linea
  Igual 'java.lang: sonar S5738' 'S5738' $ja[0].sonar
  $ll = Llamadas-De $E.Llamadas
  Igual 'Maven se llama una vez (PMD y SpotBugs no caben en el tope)' 1 $ll.Count
  $c = "$($ll[0])".Split('|')
  Igual 'la llamada: en la carpeta del migrado' $E.Repo $c[0]
  Igual 'la llamada: mvn -B compile, sin -q ni clean' '-B compile' $c[1]
  Igual 'antes de compilar target/classes no tenia ni un fichero' 'clases-antes=0' $c[2]
  Comprueba 'se borra target/maven-status' (-not (Test-Path -LiteralPath (Get-Ruta $E.Repo 'target/maven-status')))
  Comprueba 'se borra target/classes' (-not (Test-Path -LiteralPath (Get-Ruta $E.Repo 'target/classes/viejo/Viejo.class')))
  Comprueba 'lo demas de target se queda (nada de clean)' (Test-Path -LiteralPath (Get-Ruta $E.Repo 'target/reports/queda.txt'))
  Igual 'MinutosMaven vuelve a lo que era' 30 $Cfg.MinutosMaven
}

$Pruebas['2 a) javac: con 100 avisos justos corte es true; con 99, false'] = {
  $E = Nuevo-Escenario 'a2'
  $l = @()
  for ($i = 1; $i -le 99; $i++) { $l += (Aviso-Javac $FichConfig $i $TextoSpring) }
  $l += (Aviso-Javac $FichUtil 150 $AvisoTexto)
  $m = Mide $E @{ BP0_JAVAC_SALIDA = (Escribe-Salida $E $l) } $Rapido
  $d = Det $m.Json 'javac'
  Igual '100 avisos de .java (99 for removal y 1 deprecated): corte' $true $d.corte
  Igual 'cada for removal distinto es una incidencia: 99' 99 (Inc $m.Json 'javac').Count
  $m = Mide $E @{ BP0_JAVAC_SALIDA = (Escribe-Salida $E @($l | Select-Object -First 99)) } $Rapido
  Igual '99 avisos: sin corte' $false (Det $m.Json 'javac').corte
  Igual '99 avisos: 99 incidencias' 99 (Inc $m.Json 'javac').Count
}

$Pruebas['3 a) javac: si no compila, no se pudo medir con la primera linea [ERROR] y los demas detectores siguen'] = {
  $E = Nuevo-Escenario 'a3' $true
  $m = Mide $E @{ BP0_JAVAC_ERROR = 'cannot find symbol: class Falta' } $Rapido
  $j = $m.Json
  Comprueba 'el JSON se escribe igual' ($null -ne $j)
  $d = Det $j 'javac'
  Igual 'javac: estado' 'no se pudo medir' $d.estado
  Comprueba 'javac: el motivo es la primera linea [ERROR] con informacion' ("$($d.motivo)" -like '*cannot find symbol: class Falta*') "$($d.motivo)"
  Igual 'sin incidencias de javac' 0 (Inc $j 'javac').Count
  $l = Det $j 'lombok-a-mano'
  Igual 'lombok-a-mano sin clases: no se pudo medir' 'no se pudo medir' $l.estado
  Comprueba 'lombok-a-mano: dice que no hay clases' ("$($l.motivo)" -like '*target/classes*') "$($l.motivo)"
  Igual 'lombok-qualifier sigue: ok' 'ok' (Det $j 'lombok-qualifier').estado
  Comprueba 'un Aviso por el detector que no esta ok (javac)' (@($m.Avisos | Where-Object { $_ -like '*javac*' }).Count -ge 1) ($m.Avisos -join ' / ')
  Comprueba 'un Aviso por lombok-a-mano' (@($m.Avisos | Where-Object { $_ -like '*lombok-a-mano*' }).Count -ge 1) ($m.Avisos -join ' / ')
  Comprueba 'ninguno por lombok-qualifier (ok)' (@($m.Avisos | Where-Object { $_ -like '*lombok-qualifier*' }).Count -eq 0) ($m.Avisos -join ' / ')
}

$Pruebas['4 b) lombok-a-mano: con una referencia con Lombok sale la clase con getters y setters escritos y no la que los tiene en el .class'] = {
  $E = Nuevo-Escenario 'b1' $true
  $m = Mide $E @{ BP0_CLASES = $E.Clases } $Rapido
  $j = $m.Json
  $d = Det $j 'lombok-a-mano'
  Igual 'estado' 'ok' $d.estado
  $h = @($j.incidencias | Where-Object { $_.regla -ceq 'getter-setter-a-mano' })
  Igual 'una sola incidencia: Remesa (Cliente tiene getters en el .class pero no en el .java)' 1 $h.Count
  Igual 'fichero' 'src/main/java/com/acme/domain/Remesa.java' $h[0].fichero
  Igual 'linea: la del primer getter escrito (getId)' 15 $h[0].linea
  Igual 'texto: 3 getters (getId, getImporte, isActiva; no getLineas ni total) y 2 setters' '3 getters y 2 setters escritos a mano: con Lombok son @Getter y @Setter' $h[0].texto
  Igual 'area' 'lombok' $h[0].area
  Igual 'origen' 'referencia' $h[0].origen
  Igual 'herramienta' 'lombok' $h[0].herramienta
  Igual 'sonar vacio' '' $h[0].sonar
  Igual 'queHago: mano' 'mano' $h[0].queHago
  $jl = Llamadas-De $E.Javap
  Igual 'javap: una llamada para las dos clases' 1 $jl.Count
  Comprueba 'javap -c -l -p con las dos clases' ("$($jl[0])" -match '^5\|\d+\|-c -l -p .*Cliente\.class .*Remesa\.class$' -or "$($jl[0])" -match '^5\|\d+\|-c -l -p .*Remesa\.class .*Cliente\.class$') "$($jl[0])"
  Igual 'lombok-qualifier: ninguna incidencia (no hay @RequiredArgsConstructor)' 0 (Qualifier-De $j).Count
}

$Pruebas['5 b) lombok-a-mano: si la referencia no usa Lombok, no aplica con su motivo y javap no se llama'] = {
  $E = Nuevo-Escenario 'b2'
  $m = Mide $E @{ BP0_CLASES = $E.Clases } $Rapido
  $d = Det $m.Json 'lombok-a-mano'
  Igual 'sin Lombok en la referencia: no aplica' 'no aplica' $d.estado
  Comprueba 'el motivo lo dice' ("$($d.motivo)" -like '*no usa Lombok*') "$($d.motivo)"
  Igual 'javap no se llama' 0 (Llamadas-De $E.Javap).Count
  Igual 'ninguna incidencia de getters' 0 @($m.Json.incidencias | Where-Object { $_.regla -ceq 'getter-setter-a-mano' }).Count
  Comprueba 'no aplica no da Aviso' (@($m.Avisos | Where-Object { $_ -like '*lombok-a-mano*' }).Count -eq 0) ($m.Avisos -join ' / ')
  # pom con Lombok pero ningun import: tampoco aplica
  Escribe $E.Ref 'pom.xml' "<project><modelVersion>4.0.0</modelVersion><groupId>com.acme</groupId><artifactId>batch-ejemplo</artifactId><version>1</version><dependencies><dependency><groupId>org.projectlombok</groupId><artifactId>lombok</artifactId></dependency></dependencies></project>`n"
  Escribe $E.Ref 'src/main/java/com/acme/ejemplo/Ref.java' "package com.acme.ejemplo;`npublic class Ref { }`n"
  $m = Mide $E @{ BP0_CLASES = $E.Clases } $Rapido 'despues'
  Igual 'pom con Lombok y ningun import lombok.: no aplica' 'no aplica' (Det $m.Json 'lombok-a-mano').estado
  # import de Lombok pero sin la dependencia en el pom
  Escribe $E.Ref 'pom.xml' "<project><modelVersion>4.0.0</modelVersion><groupId>com.acme</groupId><artifactId>batch-ejemplo</artifactId><version>1</version></project>`n"
  Escribe $E.Ref 'src/main/java/com/acme/ejemplo/Ref.java' "package com.acme.ejemplo;`nimport lombok.Getter;`npublic class Ref { }`n"
  $m = Mide $E @{ BP0_CLASES = $E.Clases } $Rapido 'despues'
  Igual 'import lombok. y el pom sin org.projectlombok: no aplica' 'no aplica' (Det $m.Json 'lombok-a-mano').estado
  # la carpeta de la referencia no existe
  Remove-Item -LiteralPath $E.Ref -Recurse -Force
  $m = Mide $E @{ BP0_CLASES = $E.Clases } $Rapido
  Igual 'sin carpeta de referencia: no aplica' 'no aplica' (Det $m.Json 'lombok-a-mano').estado
  Igual 'sin carpeta de referencia: el JSON lleva el nombre de la carpeta' 'batch-ejemplo' $m.Json.referencia
}

$Pruebas['6 b) lombok-a-mano: javap va en lotes de menos de 8.000 caracteres y no se pierde ninguna clase'] = {
  $E = Nuevo-Escenario 'b3' $true
  for ($i = 1; $i -le 100; $i++) { Escribe $E.Raiz ('clases/com/acme/domain/ClaseDeRelleno{0:D3}.class' -f $i) '' }
  $m = Mide $E @{ BP0_CLASES = $E.Clases } $Rapido
  Igual 'estado' 'ok' (Det $m.Json 'lombok-a-mano').estado
  $jl = Llamadas-De $E.Javap
  Comprueba 'mas de una llamada (no una por clase, ni todas a la vez)' ($jl.Count -ge 2 -and $jl.Count -le 20) "$($jl.Count) llamadas"
  $largos = @($jl | Where-Object { [int]("$_".Split('|')[1]) -ge 8000 })
  Igual 'ninguna llamada llega a 8.000 caracteres' 0 $largos.Count
  $clases = 0
  foreach ($l in $jl) { $clases += ([int]("$l".Split('|')[0]) - 3) }
  Igual 'las 102 clases pasan por javap (3 argumentos de cada llamada son -c -l -p)' 102 $clases
  Igual 'sigue saliendo la incidencia de Remesa' 1 @($m.Json.incidencias | Where-Object { $_.regla -ceq 'getter-setter-a-mano' }).Count
}

$Pruebas['7 b) javap: sin JAVA_HOME, sin javap o con javap roto, lombok-a-mano no se pudo medir y los demas siguen'] = {
  $E = Nuevo-Escenario 'b4' $true
  $m = Mide $E @{ BP0_CLASES = $E.Clases; JAVA_HOME = '' } @{ SegundosPracticas = 25; JavapExe = '' }
  $d = Det $m.Json 'lombok-a-mano'
  Igual 'sin JAVA_HOME ni JavapExe: no se pudo medir' 'no se pudo medir' $d.estado
  Comprueba 'el motivo dice JAVA_HOME' ("$($d.motivo)" -like '*JAVA_HOME*') "$($d.motivo)"
  Igual 'javac sigue: ok' 'ok' (Det $m.Json 'javac').estado
  Igual 'lombok-qualifier sigue: ok' 'ok' (Det $m.Json 'lombok-qualifier').estado
  $jdk = Join-Path $E.Raiz 'jdk'
  [void](New-Item -ItemType Directory -Path (Join-Path $jdk 'bin') -Force)
  $m = Mide $E @{ BP0_CLASES = $E.Clases; JAVA_HOME = $jdk } @{ SegundosPracticas = 25; JavapExe = '' }
  Comprueba 'JAVA_HOME sin bin/javap: no se pudo medir y el motivo dice javap' ((Det $m.Json 'lombok-a-mano').estado -ceq 'no se pudo medir' -and "$((Det $m.Json 'lombok-a-mano').motivo)" -like '*javap*') "$((Det $m.Json 'lombok-a-mano').motivo)"
  $nombre = 'javap'
  if ($env:OS -eq 'Windows_NT') { $nombre = 'javap.exe' }
  Escribe $jdk "bin/$nombre" ''
  $antes = $env:JAVA_HOME
  $env:JAVA_HOME = $jdk
  try { $exe = Get-JavapExe } finally { $env:JAVA_HOME = $antes }
  Igual 'Get-JavapExe: JAVA_HOME/bin/javap' (Join-Path (Join-Path $jdk 'bin') $nombre) $exe
  $m = Mide $E @{ BP0_CLASES = $E.Clases } @{ SegundosPracticas = 25; JavapExe = (Join-Path $E.Raiz 'javap-que-no-existe-xq') }
  Igual 'JavapExe que no existe: no se pudo medir' 'no se pudo medir' (Det $m.Json 'lombok-a-mano').estado
  Igual 'y javac sigue ok' 'ok' (Det $m.Json 'javac').estado
  $m = Mide $E @{ BP0_CLASES = $E.Clases; BP0_JAVAP_ERROR = 'Error: javap de mentira roto' } $Rapido
  $d = Det $m.Json 'lombok-a-mano'
  Igual 'javap que sale con error: no se pudo medir' 'no se pudo medir' $d.estado
  Comprueba 'el motivo trae lo que dijo javap' ("$($d.motivo)" -like '*javap de mentira roto*') "$($d.motivo)"
}

$Pruebas['8 c) lombok-qualifier: sale sin lombok.config y no sale con copyableAnnotations (carpeta o ancestros)'] = {
  $E = Nuevo-Escenario 'c'
  Escribe $E.Repo 'src/main/java/com/acme/demo/Servicio.java' $FuenteServicio
  $m = Mide $E @{} $Rapido
  $d = Det $m.Json 'lombok-qualifier'
  Igual 'estado: ok aunque la referencia no use Lombok (siempre activo)' 'ok' $d.estado
  $q = Qualifier-De $m.Json
  Igual 'dos incidencias: @Qualifier y @Value de campos final (opcional no es final, otro no lleva anotacion)' 2 $q.Count
  Igual 'fichero' 'src/main/java/com/acme/demo/Servicio.java' $q[0].fichero
  Igual 'Qualifier: linea del campo' 10 $q[0].linea
  Igual 'Value: linea del campo' 13 $q[1].linea
  Igual 'area' 'lombok' $q[0].area
  Igual 'origen' 'referencia' $q[0].origen
  Igual 'herramienta' 'lombok' $q[0].herramienta
  Igual 'queHago' 'mano' $q[0].queHago
  Comprueba 'texto de Qualifier' ("$($q[0].texto)" -ceq 'Lombok no copia @Qualifier al constructor: Spring puede inyectar otro bean. Falta lombok.copyableAnnotations') "$($q[0].texto)"
  Comprueba 'texto de Value' ("$($q[1].texto)" -like 'Lombok no copia @Value al constructor*Falta lombok.copyableAnnotations') "$($q[1].texto)"
  # lombok.config en la carpeta del fichero: Qualifier cubierto, Value no
  Escribe $E.Repo 'src/main/java/com/acme/demo/lombok.config' "# del paquete`nlombok.copyableAnnotations += org.springframework.beans.factory.annotation.Qualifier`n"
  $q = Qualifier-De (Mide $E @{} $Rapido).Json
  Igual 'con copyableAnnotations de Qualifier en la carpeta: solo queda @Value' 1 $q.Count
  Igual 'y es la de Value' 13 $q[0].linea
  # el de la raiz cubre las dos
  Remove-Item -LiteralPath (Get-Ruta $E.Repo 'src/main/java/com/acme/demo/lombok.config') -Force
  Escribe $E.Repo 'lombok.config' "config.stopBubbling = true`nlombok.copyableAnnotations += org.springframework.beans.factory.annotation.Qualifier`nlombok.copyableAnnotations += org.springframework.beans.factory.annotation.Value`n"
  Igual 'lombok.config de la raiz del repo con las dos: ninguna incidencia' 0 (Qualifier-De (Mide $E @{} $Rapido).Json).Count
  # uno de otra carpeta, o de otra anotacion, no cuenta
  Remove-Item -LiteralPath (Get-Ruta $E.Repo 'lombok.config') -Force
  Escribe $E.Repo 'src/main/java/com/acme/otro/lombok.config' "lombok.copyableAnnotations += org.springframework.beans.factory.annotation.Qualifier`n"
  Escribe $E.Repo 'src/main/java/com/acme/lombok.config' "lombok.copyableAnnotations += javax.inject.Named`n"
  Igual 'config de una carpeta hermana o de otra anotacion: siguen las dos' 2 (Qualifier-De (Mide $E @{} $Rapido).Json).Count
  # AllArgsConstructor cuenta tambien los campos que no son final; una clase sin constructor de Lombok, ninguno
  Remove-Item -LiteralPath (Get-Ruta $E.Repo 'src/main/java/com/acme/otro/lombok.config') -Force
  Remove-Item -LiteralPath (Get-Ruta $E.Repo 'src/main/java/com/acme/lombok.config') -Force
  Escribe $E.Repo 'src/main/java/com/acme/demo/Servicio.java' ($FuenteServicio.Replace('@RequiredArgsConstructor', '@AllArgsConstructor'))
  $q = Qualifier-De (Mide $E @{} $Rapido).Json
  Igual '@AllArgsConstructor: tambien el campo @Value que no es final' 3 $q.Count
  Escribe $E.Repo 'src/main/java/com/acme/demo/Servicio.java' ($FuenteServicio.Replace('@RequiredArgsConstructor', '@Service'))
  Igual 'sin @RequiredArgsConstructor ni @AllArgsConstructor: ninguna' 0 (Qualifier-De (Mide $E @{} $Rapido).Json).Count
}

$Pruebas['9 d) PMD y SpotBugs: claves de Sonar de pmd-sonar.xml, origen spotbugs y queHago paso2, sonar y mano'] = {
  $E = Nuevo-Escenario 'd' $true
  $tot = 'src/main/java/com/acme/demo/Totales.java'
  $cla = 'src/main/java/com/acme/demo/Clasificador.java'
  # lo que el motor dejaria en .rescate\hallazgos.json: una matriz de objetos con Cat, Sev, Fichero, Linea y Detalle
  $motor = ConvertTo-Json -InputObject @((Hallazgo 'error' $tot 10), (Hallazgo 'warn' $cla 99)) -Depth 4
  Escribe $E.Raiz 'hallazgos.json' $motor
  $m = Mide $E @{ BP0_CLASES = $E.Clases }
  $j = $m.Json
  Igual 'pmd: estado' 'ok' (Det $j 'pmd').estado
  Igual 'spotbugs: estado' 'ok' (Det $j 'spotbugs').estado
  $pm = Inc $j 'pmd'
  $sb = Inc $j 'spotbugs'
  Igual 'PMD: 2 incidencias' 2 $pm.Count
  Igual 'SpotBugs: 7 incidencias' 7 $sb.Count
  Igual 'todas de area java21' 9 @($pm + $sb | Where-Object { $_.area -ceq 'java21' }).Count
  $c = @($pm | Where-Object { $_.regla -ceq 'CognitiveComplexity' })
  Igual 'CognitiveComplexity: sonar (de pmd-sonar.xml)' 'S3776' $c[0].sonar
  Igual 'CognitiveComplexity: origen' 'sonar' $c[0].origen
  Igual 'CognitiveComplexity: fichero y linea' "$cla|12" "$($c[0].fichero)|$($c[0].linea)"
  Igual 'CognitiveComplexity: queHago (otra linea en el motor: no es paso2)' 'sonar' $c[0].queHago
  Comprueba 'CognitiveComplexity: el texto es el de PMD' ("$($c[0].texto)" -like "The method 'clasificar(*cognitive complexity of 20*") "$($c[0].texto)"
  $u = @($pm | Where-Object { $_.regla -ceq 'UnusedPrivateField' })
  Igual 'UnusedPrivateField: sonar' 'S1068' $u[0].sonar
  Igual 'todo PMD lleva origen sonar' 2 @($pm | Where-Object { $_.origen -ceq 'sonar' -and $_.herramienta -ceq 'pmd' }).Count
  Igual 'todo SpotBugs lleva origen spotbugs' 7 @($sb | Where-Object { $_.origen -ceq 'spotbugs' -and $_.herramienta -ceq 'spotbugs' }).Count
  Igual 'SpotBugs: sin clave de Sonar' 0 @($sb | Where-Object { $_.sonar -cne '' }).Count
  $b = @($sb | Where-Object { $_.regla -ceq 'BX_UNBOXING_IMMEDIATELY_REBOXED' })
  Igual 'BX_UNBOXING: fichero y linea' "$tot|10" "$($b[0].fichero)|$($b[0].linea)"
  Igual 'BX_UNBOXING: el motor tiene ese fichero y esa linea: paso2' 'paso2' $b[0].queHago
  $n = @($sb | Where-Object { $_.regla -ceq 'NAB_NEEDLESS_AUTOBOXING_VALUEOF' })
  Igual 'NAB_NEEDLESS: misma linea 10: paso2' 'paso2' $n[0].queHago
  $f = @($sb | Where-Object { $_.regla -ceq 'FCBL_FIELD_COULD_BE_LOCAL' -and $_.fichero -ceq $tot })
  Igual 'FCBL de Totales (linea 15, el motor no lo dice): sonar' 'sonar' $f[0].queHago
  Igual 'paso2 son exactamente 2 (las dos de la linea 10)' 2 @($j.incidencias | Where-Object { $_.queHago -ceq 'paso2' }).Count
  Igual 'mano: la de Lombok' 1 @($j.incidencias | Where-Object { $_.queHago -ceq 'mano' -and $_.herramienta -ceq 'lombok' }).Count
  $sonar = @([System.IO.File]::ReadAllText($Cfg.PmdReglas) | Select-String -Pattern '<!-- java:(S\d+) ' -AllMatches | ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
  Igual 'sonar.reglasWay: 608' 608 $j.sonar.reglasWay
  Igual 'sonar.reglasAqui: las claves distintas de pmd-sonar.xml mas S5738' ($sonar.Count + 1) $j.sonar.reglasAqui
  # sin hallazgos del motor, ni una es paso2
  Remove-Item -LiteralPath $E.Hallazgos -Force
  $m = Mide $E @{ BP0_CLASES = $E.Clases }
  Igual 'sin hallazgos del motor: ninguna paso2' 0 @($m.Json.incidencias | Where-Object { $_.queHago -ceq 'paso2' }).Count
  Igual 'sin hallazgos del motor: BX_UNBOXING pasa a sonar' 'sonar' @($m.Json.incidencias | Where-Object { $_.regla -ceq 'BX_UNBOXING_IMMEDIATELY_REBOXED' })[0].queHago
  Comprueba-Formato $m.Json $E
}

# El formato de BP-datos.md: los campos, el orden de los detectores y el registro.
function Comprueba-Formato($J, $E) {
  Igual 'formato: version' 1 $J.version
  Igual 'formato: cuando' 'antes' $J.cuando
  Comprueba 'formato: clave de 8 hex' ("$($J.clave)" -match '^[0-9a-f]{8}$') "$($J.clave)"
  # (PowerShell 7 convierte esa cadena en fecha al leer el JSON: se mira el texto del fichero)
  $crudo = [System.IO.File]::ReadAllText((Join-Path $E.Datos 'practicas-antes.json'))
  Comprueba 'formato: medido es una fecha con hora ISO' ($crudo -match '"medido": "\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d"') ($crudo.Substring(0, [Math]::Min(300, $crudo.Length)))
  Comprueba 'formato: segundos es un numero' ($J.segundos -is [double] -or $J.segundos -is [int] -or $J.segundos -is [decimal]) "$($J.segundos)"
  Igual 'formato: paquete (el prefijo comun de los paquetes de src/main/java)' 'com.acme' $J.paquete
  Igual 'formato: referencia (el nombre de su carpeta)' 'batch-ejemplo' $J.referencia
  Comprueba 'formato: arquitectura existe y es null' ($J.PSObject.Properties.Name -contains 'arquitectura' -and $null -eq $J.arquitectura)
  Igual 'formato: los 5 detectores en orden' 'javac,pmd,spotbugs,lombok-a-mano,lombok-qualifier' ((@($J.detectores | ForEach-Object { $_.id })) -join ',')
  $mal = @($J.detectores | Where-Object { -not ($_.PSObject.Properties.Name -join ',' -ceq 'id,estado,motivo,segundos,corte') })
  Igual 'formato: cada detector lleva id, estado, motivo, segundos y corte' 0 $mal.Count
  $estados = @('ok', 'no medido (tope)', 'no se pudo medir', 'no aplica')
  Igual 'formato: estados validos' 0 @($J.detectores | Where-Object { $estados -cnotcontains $_.estado }).Count
  $campos = 'area,fichero,linea,herramienta,regla,origen,sonar,texto,queHago'
  $malI = @($J.incidencias | Where-Object { -not ($_.PSObject.Properties.Name -join ',' -ceq $campos) })
  Igual 'formato: cada incidencia lleva sus 9 campos' 0 $malI.Count
  Igual 'formato: ficheros relativos y con /' 0 @($J.incidencias | Where-Object { $_.fichero -match '^(/|[A-Za-z]:)' -or $_.fichero -match '\\' }).Count
  Igual 'formato: textos de hasta 300' 0 @($J.incidencias | Where-Object { "$($_.texto)".Length -gt 300 }).Count
  $reg = Join-Path $E.Registros 'practicas-antes.log'
  Comprueba 'el registro registros\practicas-antes.log existe' (Test-Path -LiteralPath $reg)
  $txt = ''
  if (Test-Path -LiteralPath $reg) { $txt = [System.IO.File]::ReadAllText($reg) }
  Comprueba 'el registro lleva la salida de Maven y el resumen de los detectores' ($txt -match 'BUILD SUCCESS' -and $txt -match 'javac' -and $txt -match 'spotbugs' -and $txt -match 'lombok-qualifier') (Cola $txt)
}

$Pruebas['10 d) consola: una linea Info con las incidencias por area y los segundos'] = {
  $E = Nuevo-Escenario 'consola' $true
  Escribe $E.Repo 'src/main/java/com/acme/demo/Servicio.java' $FuenteServicio
  $salida = Escribe-Salida $E @((Aviso-Javac $FichConfig 16 $TextoSpring))
  $m = Mide $E @{ BP0_CLASES = $E.Clases; BP0_JAVAC_SALIDA = $salida }
  $l = @(($m.Texto -split "`n") | Where-Object { $_ -like 'Buenas practicas (antes):*' })
  Igual 'una sola linea de resumen' 1 $l.Count
  Comprueba 'dice las incidencias por area: java21 9, boot3-batch5 1, lombok 3' ("$($l[0])" -match 'java21: 9' -and "$($l[0])" -match 'boot3-batch5: 1' -and "$($l[0])" -match 'lombok: 3') "$($l[0])"
  Comprueba 'dice los segundos' ("$($l[0])" -match ' en \d+,\d s') "$($l[0])"
  Igual 'ningun Aviso: todos los detectores estan ok' 0 $m.Avisos.Count
}

$Pruebas['11 e) tope: sin 30 s para PMD y SpotBugs quedan en no medido (tope) y el JSON se escribe igual'] = {
  $E = Nuevo-Escenario 'e1'
  $m = Mide $E @{ BP0_JAVAC_ESPERA = '5' } @{ SegundosPracticas = 33 }
  $j = $m.Json
  Comprueba 'el JSON se escribe' ($null -ne $j)
  Igual 'javac: ok (con su espera)' 'ok' (Det $j 'javac').estado
  Comprueba 'javac: tardo lo que esperaba el falso' ((Det $j 'javac').segundos -ge 5) "$((Det $j 'javac').segundos)"
  Igual 'pmd: no medido (tope)' 'no medido (tope)' (Det $j 'pmd').estado
  Igual 'spotbugs: no medido (tope)' 'no medido (tope)' (Det $j 'spotbugs').estado
  Igual 'pmd: 0 s' 0 (Det $j 'pmd').segundos
  Igual 'lombok-qualifier: ok' 'ok' (Det $j 'lombok-qualifier').estado
  Igual 'Maven solo se llama para javac: ni SpotBugs ni PMD' 1 (Llamadas-De $E.Llamadas).Count
  Comprueba 'un Aviso por pmd y otro por spotbugs' (@($m.Avisos | Where-Object { $_ -like '*pmd*' }).Count -ge 1 -and @($m.Avisos | Where-Object { $_ -like '*spotbugs*' }).Count -ge 1) ($m.Avisos -join ' / ')
  Igual 'MinutosMaven vuelve a lo que era' 30 $Cfg.MinutosMaven
}

$Pruebas['12 e) tope: un javac que se pasa del tiempo queda en no medido (tope), no espera al falso y el JSON se escribe'] = {
  $E = Nuevo-Escenario 'e2' $true
  $reloj = [System.Diagnostics.Stopwatch]::StartNew()
  $m = Mide $E @{ BP0_JAVAC_ESPERA = '40'; BP0_CLASES = $E.Clases } @{ SegundosPracticas = 3 }
  Comprueba 'no espero al falso: menos de 25 s' ($reloj.Elapsed.TotalSeconds -lt 25) ([string]$reloj.Elapsed.TotalSeconds)
  $j = $m.Json
  Comprueba 'el JSON se escribe' ($null -ne $j)
  Igual 'javac: no medido (tope)' 'no medido (tope)' (Det $j 'javac').estado
  Igual 'pmd: no medido (tope)' 'no medido (tope)' (Det $j 'pmd').estado
  Igual 'spotbugs: no medido (tope)' 'no medido (tope)' (Det $j 'spotbugs').estado
  Igual 'sin incidencias de javac' 0 (Inc $j 'javac').Count
  Igual 'lombok-a-mano: no se pudo medir (no hay clases)' 'no se pudo medir' (Det $j 'lombok-a-mano').estado
  Igual 'MinutosMaven vuelve a lo que era' 30 $Cfg.MinutosMaven
}

$Pruebas['13 e) tope: si PMD y SpotBugs se pasan del tiempo que queda, los dos quedan en no medido (tope)'] = {
  $E = Nuevo-Escenario 'e3'
  $reloj = [System.Diagnostics.Stopwatch]::StartNew()
  $m = Mide $E @{ RESCATE_ANALISIS_ESPERA = '40' } @{ SegundosPracticas = 8; SegundosMinAnalisis = 1 }
  Comprueba 'no espero al falso: menos de 30 s' ($reloj.Elapsed.TotalSeconds -lt 30) ([string]$reloj.Elapsed.TotalSeconds)
  $j = $m.Json
  Igual 'javac: ok' 'ok' (Det $j 'javac').estado
  Igual 'pmd: no medido (tope)' 'no medido (tope)' (Det $j 'pmd').estado
  Igual 'spotbugs: no medido (tope)' 'no medido (tope)' (Det $j 'spotbugs').estado
  Comprueba 'Maven se llamo para SpotBugs (y se paro)' (@(Llamadas-De $E.Llamadas | Where-Object { "$_" -match 'spotbugs-maven-plugin' }).Count -eq 1)
  Igual 'MinutosMaven vuelve a lo que era' 30 $Cfg.MinutosMaven
}

$Pruebas['14 d) PMD y SpotBugs: si Invoke-Analisis no esta ok, los dos detectores copian su estado como motivo'] = {
  $E = Nuevo-Escenario 'd2'
  $m = Mide $E @{ RESCATE_ANALISIS_ERROR = 'Plugin com.github.spotbugs:spotbugs-maven-plugin:4.10.5.0 or one of its dependencies could not be resolved' }
  $j = $m.Json
  foreach ($id in @('pmd', 'spotbugs')) {
    $d = Det $j $id
    Igual "$id`: no se pudo medir" 'no se pudo medir' $d.estado
    Igual "$id`: el motivo es el estado de Invoke-Analisis" 'no disponible: no se descarga el plugin' $d.motivo
  }
  Igual 'ninguna incidencia de PMD ni de SpotBugs' 0 ((Inc $j 'pmd').Count + (Inc $j 'spotbugs').Count)
  Igual 'javac sigue ok' 'ok' (Det $j 'javac').estado
}

$Pruebas['15 f) cache: sin cambios no se lanza Maven; con un fichero cambiado vuelve a medir'] = {
  $E = Nuevo-Escenario 'f'
  $m1 = Mide $E @{} $Rapido 'antes' -ConCache
  $n1 = (Llamadas-De $E.Llamadas).Count
  Igual 'la primera vez mide: una llamada a Maven (javac)' 1 $n1
  $m2 = Mide $E @{} $Rapido 'antes' -ConCache
  Igual 'la segunda, sin cambios: ninguna llamada a Maven mas' $n1 (Llamadas-De $E.Llamadas).Count
  Comprueba 'sale una linea Info que dice que ya estaba medido' ("$($m2.Texto)" -match 'ya medidas') $m2.Texto
  Igual 'el JSON es el mismo (medido)' $m1.Json.medido $m2.Json.medido
  Igual 'la misma clave' $m1.Json.clave $m2.Json.clave
  Escribe $E.Repo 'target/otra.txt' 'x'
  Escribe $E.Repo 'target/classes/otra.class' 'x'
  Escribe $E.Repo 'migracion-2026-11-19/informe.txt' 'x'
  Escribe $E.Repo '.rescate/hallazgos.json' '[]'
  [void](Mide $E @{} $Rapido 'antes' -ConCache)
  Igual 'target, .rescate y migracion-* no cambian la clave: sigue sin llamar' $n1 (Llamadas-De $E.Llamadas).Count
  # un fichero nuevo
  Escribe $E.Repo 'src/main/java/com/acme/demo/Nuevo.java' "package com.acme.demo;`npublic class Nuevo { }`n"
  $m4 = Mide $E @{} $Rapido 'antes' -ConCache
  Igual 'un fichero nuevo: vuelve a medir' ($n1 + 1) (Llamadas-De $E.Llamadas).Count
  Comprueba 'la clave cambia' ($m4.Json.clave -cne $m1.Json.clave) "$($m4.Json.clave)"
  Comprueba 'y ya no dice que estaba medido' ("$($m4.Texto)" -notmatch 'ya medidas')
  # el mismo fichero, con otro contenido: el status es igual, el contenido no
  Escribe $E.Repo 'src/main/java/com/acme/demo/Nuevo.java' "package com.acme.demo;`npublic class Nuevo { int a; }`n"
  $m5 = Mide $E @{} $Rapido 'antes' -ConCache
  Igual 'el mismo fichero con otro contenido: vuelve a medir' ($n1 + 2) (Llamadas-De $E.Llamadas).Count
  Comprueba 'otra clave' ($m5.Json.clave -cne $m4.Json.clave)
  # un commit cambia el HEAD
  [void](GitEn $E.Repo @('add', '-A'))
  [void](GitEn $E.Repo @('commit', '-q', '-m', 'cambio'))
  $m6 = Mide $E @{} $Rapido 'antes' -ConCache
  Igual 'con un commit nuevo: vuelve a medir' ($n1 + 3) (Llamadas-De $E.Llamadas).Count
  Comprueba 'otra clave con otro HEAD' ($m6.Json.clave -cne $m5.Json.clave)
  # <Cuando> distinto: su propio JSON
  [void](Mide $E @{} $Rapido 'despues' -ConCache)
  Igual 'despues no usa lo de antes: mide' ($n1 + 4) (Llamadas-De $E.Llamadas).Count
  Comprueba 'y deja practicas-despues.json' (Test-Path -LiteralPath (Join-Path $E.Datos 'practicas-despues.json'))
}

$Pruebas['16 g) un detector que falla no para a los demas ni a la medida; nada lanza una excepcion'] = {
  $E = Nuevo-Escenario 'g' $true
  Escribe $E.Raiz 'hallazgos.json' 'esto no es json {{{'
  $m = Mide $E @{ BP0_CLASES = $E.Clases } @{ JavapExe = (Join-Path $E.Raiz 'javap-que-no-existe-xq') }
  $j = $m.Json
  Comprueba 'el JSON se escribe' ($null -ne $j)
  $d = Det $j 'lombok-a-mano'
  Igual 'lombok-a-mano: no se pudo medir' 'no se pudo medir' $d.estado
  Comprueba 'con su motivo' ("$($d.motivo)".Length -gt 0) "$($d.motivo)"
  Igual 'javac sigue: ok' 'ok' (Det $j 'javac').estado
  Igual 'pmd sigue: ok' 'ok' (Det $j 'pmd').estado
  Igual 'spotbugs sigue: ok' 'ok' (Det $j 'spotbugs').estado
  Igual 'lombok-qualifier sigue: ok' 'ok' (Det $j 'lombok-qualifier').estado
  Igual 'hallazgos del motor ilegibles: las 9 incidencias de PMD y SpotBugs salen' 9 ((Inc $j 'pmd').Count + (Inc $j 'spotbugs').Count)
  Igual 'hallazgos del motor ilegibles: ninguna paso2' 0 @($j.incidencias | Where-Object { $_.queHago -ceq 'paso2' }).Count
  # un JSON de antes ilegible no impide medir
  Escribe $E.Datos 'practicas-antes.json' 'basura'
  $m = Mide $E @{} $Rapido 'antes' -ConCache
  Igual 'practicas-antes.json ilegible: mide' 'ok' (Det $m.Json 'javac').estado
  # no se puede escribir el JSON (datos es un fichero, no una carpeta): no lanza, avisa y el registro queda
  $E2 = Nuevo-Escenario 'g2'
  Remove-Item -LiteralPath $E2.Datos -Recurse -Force
  Escribe $E2.Raiz 'datos' 'soy un fichero'
  $lanza = $false
  $t = ''
  try { $t = @(Con-Falso @{} $Rapido { Invoke-Practicas $E2.Repo $E2.Ref 'antes' $E2.Datos $E2.Registros $E2.Hallazgos } 6>&1 | ForEach-Object { "$_" }) -join "`n" } catch { $lanza = $true }
  Igual 'sin poder escribir el JSON: no lanza excepcion' $false $lanza
  Comprueba 'sin poder escribir el JSON: avisa de que no lo ha escrito' ($t -match 'practicas-antes\.json') $t
  Comprueba 'el registro queda aunque el JSON no' (Test-Path -LiteralPath (Join-Path $E2.Registros 'practicas-antes.log'))
  # Datos y Registros que no existen: se crean
  $E3 = Nuevo-Escenario 'g3'
  Remove-Item -LiteralPath $E3.Datos -Recurse -Force
  Remove-Item -LiteralPath $E3.Registros -Recurse -Force
  [void](Mide $E3 @{} $Rapido)
  Comprueba 'las carpetas de datos y de registros que faltaban se crean' ((Test-Path -LiteralPath (Join-Path $E3.Datos 'practicas-antes.json')) -and (Test-Path -LiteralPath (Join-Path $E3.Registros 'practicas-antes.log')))
}

$Pruebas['17 ficheros y ajustes: ASCII, nada de PowerShell 7 y los ajustes en $Cfg'] = {
  Igual 'SegundosPracticas' 300 $Cfg.SegundosPracticas
  Igual 'SegundosMinAnalisis' 30 $Cfg.SegundosMinAnalisis
  foreach ($f in @('practicas.ps1', 'tests/probar-practicas.ps1', 'tests/falsos/bp0-mvn.ps1', 'tests/falsos/bp0-javap.ps1')) {
    $t = [System.IO.File]::ReadAllText((Get-Ruta $raiz $f))
    Comprueba "$f`: solo ASCII" ($t -notmatch '[^\x09\x0A\x0D\x20-\x7E]')
  }
  $codigo = [System.IO.File]::ReadAllText((Join-Path $raiz 'practicas.ps1'))
  Comprueba 'practicas.ps1: nada de PowerShell 7 (??, ?. ni ?[)' ($codigo -notmatch '\?\?|[\w\)\]]\?\.\w|\w\?\[')
  Comprueba 'practicas.ps1: sin -AsHashtable ni ConvertFrom-Json -Depth' ($codigo -notmatch 'AsHashtable|ConvertFrom-Json[^|\r\n]*-Depth')
  Comprueba 'practicas.ps1: empieza con su cabecera de ayuda' ($codigo.TrimStart().StartsWith('<#'))
  Comprueba 'practicas.ps1: solo funciones (ni una llamada suelta fuera del $Cfg)' (-not ($codigo -match '(?m)^Invoke-Practicas'))
}

# ================================ LANZADOR ================================
Invoke-Banco $Pruebas 'tests/probar-practicas.ps1'
