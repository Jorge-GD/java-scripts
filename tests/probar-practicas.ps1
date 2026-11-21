<#
probar-practicas.ps1 - Banco de pruebas de practicas.ps1 (BP-0: las buenas practicas dentro del diagnostico, sin IA) y de arreglo-practicas.ps1
(BP-4: pasar a Lombok los getters y setters escritos a mano, con el Maven de mentira bp4-mvn.ps1 y el Copilot de mentira bp4-copilot.ps1).
No necesita Maven ni Java: usa el Maven de mentira tests/falsos/bp0-mvn.ps1 (el javac sale de un fichero con lineas como las de Maven) y el javap de mentira tests/falsos/bp0-javap.ps1, cuyos .class de mentira llevan el texto que dio
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
$datos = Join-Path (Join-Path $aqui 'datos') 'practicas'
. (Join-Path $aqui 'comun-banco.ps1')
. (Join-Path $raiz 'comun.ps1')
. (Join-Path $raiz 'tareas.ps1')
. (Join-Path $raiz 'practicas.ps1')
. (Join-Path $raiz 'huella.ps1')
. (Join-Path $raiz 'arreglo-practicas.ps1')

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

# Un escenario: el migrado (un repo git con las dos clases del juguete, mas Remesa y Cliente), la referencia (con o sin Lombok), los .class de
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
  $m = Mide $E @{ BP0_JAVAC_SALIDA = $salida }
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
  Igual 'Maven se llama una vez (javac)' 1 $ll.Count
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
  $m = Mide $E @{ BP0_JAVAC_SALIDA = (Escribe-Salida $E $l) }
  $d = Det $m.Json 'javac'
  Igual '100 avisos de .java (99 for removal y 1 deprecated): corte' $true $d.corte
  Igual 'cada for removal distinto es una incidencia: 99' 99 (Inc $m.Json 'javac').Count
  $m = Mide $E @{ BP0_JAVAC_SALIDA = (Escribe-Salida $E @($l | Select-Object -First 99)) }
  Igual '99 avisos: sin corte' $false (Det $m.Json 'javac').corte
  Igual '99 avisos: 99 incidencias' 99 (Inc $m.Json 'javac').Count
}

$Pruebas['3 a) javac: si no compila, no se pudo medir con la primera linea [ERROR] y los demas detectores siguen'] = {
  $E = Nuevo-Escenario 'a3' $true
  $m = Mide $E @{ BP0_JAVAC_ERROR = 'cannot find symbol: class Falta' }
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
  $m = Mide $E @{ BP0_CLASES = $E.Clases }
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
  $m = Mide $E @{ BP0_CLASES = $E.Clases }
  $d = Det $m.Json 'lombok-a-mano'
  Igual 'sin Lombok en la referencia: no aplica' 'no aplica' $d.estado
  Comprueba 'el motivo lo dice' ("$($d.motivo)" -like '*no usa Lombok*') "$($d.motivo)"
  Igual 'javap no se llama' 0 (Llamadas-De $E.Javap).Count
  Igual 'ninguna incidencia de getters' 0 @($m.Json.incidencias | Where-Object { $_.regla -ceq 'getter-setter-a-mano' }).Count
  Comprueba 'no aplica no da Aviso' (@($m.Avisos | Where-Object { $_ -like '*lombok-a-mano*' }).Count -eq 0) ($m.Avisos -join ' / ')
  # pom con Lombok pero ningun import: tampoco aplica
  Escribe $E.Ref 'pom.xml' "<project><modelVersion>4.0.0</modelVersion><groupId>com.acme</groupId><artifactId>batch-ejemplo</artifactId><version>1</version><dependencies><dependency><groupId>org.projectlombok</groupId><artifactId>lombok</artifactId></dependency></dependencies></project>`n"
  Escribe $E.Ref 'src/main/java/com/acme/ejemplo/Ref.java' "package com.acme.ejemplo;`npublic class Ref { }`n"
  $m = Mide $E @{ BP0_CLASES = $E.Clases } @{} 'despues'
  Igual 'pom con Lombok y ningun import lombok.: no aplica' 'no aplica' (Det $m.Json 'lombok-a-mano').estado
  # import de Lombok pero sin la dependencia en el pom
  Escribe $E.Ref 'pom.xml' "<project><modelVersion>4.0.0</modelVersion><groupId>com.acme</groupId><artifactId>batch-ejemplo</artifactId><version>1</version></project>`n"
  Escribe $E.Ref 'src/main/java/com/acme/ejemplo/Ref.java' "package com.acme.ejemplo;`nimport lombok.Getter;`npublic class Ref { }`n"
  $m = Mide $E @{ BP0_CLASES = $E.Clases } @{} 'despues'
  Igual 'import lombok. y el pom sin org.projectlombok: no aplica' 'no aplica' (Det $m.Json 'lombok-a-mano').estado
  # la carpeta de la referencia no existe
  Remove-Item -LiteralPath $E.Ref -Recurse -Force
  $m = Mide $E @{ BP0_CLASES = $E.Clases }
  Igual 'sin carpeta de referencia: no aplica' 'no aplica' (Det $m.Json 'lombok-a-mano').estado
  Igual 'sin carpeta de referencia: el JSON lleva el nombre de la carpeta' 'batch-ejemplo' $m.Json.referencia
}

$Pruebas['6 b) lombok-a-mano: javap va en lotes de menos de 8.000 caracteres y no se pierde ninguna clase'] = {
  $E = Nuevo-Escenario 'b3' $true
  for ($i = 1; $i -le 100; $i++) { Escribe $E.Raiz ('clases/com/acme/domain/ClaseDeRelleno{0:D3}.class' -f $i) '' }
  $m = Mide $E @{ BP0_CLASES = $E.Clases }
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
  $m = Mide $E @{ BP0_CLASES = $E.Clases; BP0_JAVAP_ERROR = 'Error: javap de mentira roto' }
  $d = Det $m.Json 'lombok-a-mano'
  Igual 'javap que sale con error: no se pudo medir' 'no se pudo medir' $d.estado
  Comprueba 'el motivo trae lo que dijo javap' ("$($d.motivo)" -like '*javap de mentira roto*') "$($d.motivo)"
}

$Pruebas['8 c) lombok-qualifier: sale sin lombok.config y no sale con copyableAnnotations (carpeta o ancestros)'] = {
  $E = Nuevo-Escenario 'c'
  Escribe $E.Repo 'src/main/java/com/acme/demo/Servicio.java' $FuenteServicio
  $m = Mide $E @{}
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
  $q = Qualifier-De (Mide $E @{}).Json
  Igual 'con copyableAnnotations de Qualifier en la carpeta: solo queda @Value' 1 $q.Count
  Igual 'y es la de Value' 13 $q[0].linea
  # uno en una carpeta intermedia (ni la del fichero ni la raiz) tambien cuenta: com/acme cubre a com/acme/demo
  Remove-Item -LiteralPath (Get-Ruta $E.Repo 'src/main/java/com/acme/demo/lombok.config') -Force
  Escribe $E.Repo 'src/main/java/com/acme/lombok.config' "lombok.copyableAnnotations += org.springframework.beans.factory.annotation.Qualifier`n"
  $q = Qualifier-De (Mide $E @{}).Json
  Igual 'con copyableAnnotations de Qualifier en una carpeta intermedia (com/acme): solo queda @Value' 1 $q.Count
  Igual 'y es la de Value, en la linea del campo' 13 $q[0].linea
  Remove-Item -LiteralPath (Get-Ruta $E.Repo 'src/main/java/com/acme/lombok.config') -Force
  # el de la raiz cubre las dos
  Escribe $E.Repo 'lombok.config' "config.stopBubbling = true`nlombok.copyableAnnotations += org.springframework.beans.factory.annotation.Qualifier`nlombok.copyableAnnotations += org.springframework.beans.factory.annotation.Value`n"
  Igual 'lombok.config de la raiz del repo con las dos: ninguna incidencia' 0 (Qualifier-De (Mide $E @{}).Json).Count
  # uno de otra carpeta, o de otra anotacion, no cuenta
  Remove-Item -LiteralPath (Get-Ruta $E.Repo 'lombok.config') -Force
  Escribe $E.Repo 'src/main/java/com/acme/otro/lombok.config' "lombok.copyableAnnotations += org.springframework.beans.factory.annotation.Qualifier`n"
  Escribe $E.Repo 'src/main/java/com/acme/lombok.config' "lombok.copyableAnnotations += javax.inject.Named`n"
  Igual 'config de una carpeta hermana o de otra anotacion: siguen las dos' 2 (Qualifier-De (Mide $E @{}).Json).Count
  # AllArgsConstructor cuenta tambien los campos que no son final; una clase sin constructor de Lombok, ninguno
  Remove-Item -LiteralPath (Get-Ruta $E.Repo 'src/main/java/com/acme/otro/lombok.config') -Force
  Remove-Item -LiteralPath (Get-Ruta $E.Repo 'src/main/java/com/acme/lombok.config') -Force
  Escribe $E.Repo 'src/main/java/com/acme/demo/Servicio.java' ($FuenteServicio.Replace('@RequiredArgsConstructor', '@AllArgsConstructor'))
  $q = Qualifier-De (Mide $E @{}).Json
  Igual '@AllArgsConstructor: tambien el campo @Value que no es final' 3 $q.Count
  Escribe $E.Repo 'src/main/java/com/acme/demo/Servicio.java' ($FuenteServicio.Replace('@RequiredArgsConstructor', '@Service'))
  Igual 'sin @RequiredArgsConstructor ni @AllArgsConstructor: ninguna' 0 (Qualifier-De (Mide $E @{}).Json).Count
}

$Pruebas['9 d) queHago: paso2 si el motor dice ese fichero y esa linea, sonar si no (javac) y mano (Lombok); sonar.reglasAqui es 4 (S5738, S125, S1135 y S1134)'] = {
  $E = Nuevo-Escenario 'd' $true
  $tot = 'src/main/java/com/acme/demo/Totales.java'
  $cla = 'src/main/java/com/acme/demo/Clasificador.java'
  # lo que el motor dejaria en .rescate\hallazgos.json: una matriz de objetos con Cat, Sev, Fichero, Linea y Detalle
  $motor = ConvertTo-Json -InputObject @((Hallazgo 'error' $tot 10), (Hallazgo 'warn' $cla 99)) -Depth 4
  Escribe $E.Raiz 'hallazgos.json' $motor
  $salida = Escribe-Salida $E @((Aviso-Javac $tot 10 $TextoInteger), (Aviso-Javac $cla 12 $TextoInteger))
  $m = Mide $E @{ BP0_CLASES = $E.Clases; BP0_JAVAC_SALIDA = $salida }
  $j = $m.Json
  Igual 'javac: estado' 'ok' (Det $j 'javac').estado
  Igual 'javac: 2 incidencias' 2 (Inc $j 'javac').Count
  $a = @((Inc $j 'javac') | Where-Object { $_.fichero -ceq $tot })
  Igual 'Totales:10 (el motor tiene ese fichero y esa linea): paso2' 'paso2' $a[0].queHago
  $b = @((Inc $j 'javac') | Where-Object { $_.fichero -ceq $cla })
  Igual 'Clasificador:12 (el motor dice otra linea): sonar' 'sonar' $b[0].queHago
  Igual 'paso2 es exactamente 1' 1 @($j.incidencias | Where-Object { $_.queHago -ceq 'paso2' }).Count
  Igual 'mano: la de Lombok' 1 @($j.incidencias | Where-Object { $_.queHago -ceq 'mano' -and $_.herramienta -ceq 'lombok' }).Count
  Igual 'ninguna incidencia con origen spotbugs' 0 @($j.incidencias | Where-Object { $_.origen -ceq 'spotbugs' }).Count
  Igual 'sonar.reglasWay: 608' 608 $j.sonar.reglasWay
  Igual 'sonar.reglasAqui: 4 (S5738 de javac, S125, S1135 y S1134 de limpieza)' 4 $j.sonar.reglasAqui
  # sin hallazgos del motor, ni una es paso2
  Remove-Item -LiteralPath $E.Hallazgos -Force
  $m = Mide $E @{ BP0_CLASES = $E.Clases; BP0_JAVAC_SALIDA = $salida }
  Igual 'sin hallazgos del motor: ninguna paso2' 0 @($m.Json.incidencias | Where-Object { $_.queHago -ceq 'paso2' }).Count
  Igual 'sin hallazgos del motor: Totales:10 pasa a sonar' 'sonar' @($m.Json.incidencias | Where-Object { $_.fichero -ceq $tot })[0].queHago
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
  Igual 'formato: los 5 detectores en orden' 'javac,lombok-a-mano,lombok-qualifier,java21-texto,limpieza' ((@($J.detectores | ForEach-Object { $_.id })) -join ',')
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
  Comprueba 'el registro lleva la salida de Maven y el resumen de los detectores' ($txt -match 'BUILD SUCCESS' -and $txt -match 'javac' -and $txt -match 'lombok-qualifier' -and $txt -match 'java21-texto' -and $txt -match 'limpieza' -and $txt -notmatch 'pmd|spotbugs') (Cola $txt)
}

$Pruebas['10 d) consola: una linea Info con las incidencias por area y los segundos'] = {
  $E = Nuevo-Escenario 'consola' $true
  Escribe $E.Repo 'src/main/java/com/acme/demo/Servicio.java' $FuenteServicio
  $salida = Escribe-Salida $E @((Aviso-Javac $FichConfig 16 $TextoSpring))
  $m = Mide $E @{ BP0_CLASES = $E.Clases; BP0_JAVAC_SALIDA = $salida }
  $l = @(($m.Texto -split "`n") | Where-Object { $_ -like 'Buenas practicas (antes):*' })
  Igual 'una sola linea de resumen' 1 $l.Count
  Comprueba 'dice las incidencias por area: boot3-batch5 1, lombok 3 (y java21 ninguna)' ("$($l[0])" -match 'boot3-batch5: 1' -and "$($l[0])" -match 'lombok: 3' -and "$($l[0])" -notmatch 'java21') "$($l[0])"
  Comprueba 'dice los segundos' ("$($l[0])" -match ' en \d+,\d s') "$($l[0])"
  Igual 'ningun Aviso: todos los detectores estan ok' 0 $m.Avisos.Count
}

$Pruebas['11 e) tope: un javac que tarda 5 s cabe en el tope: ok, una sola llamada a Maven y el JSON se escribe'] = {
  $E = Nuevo-Escenario 'e1'
  $m = Mide $E @{ BP0_JAVAC_ESPERA = '5' }
  $j = $m.Json
  Comprueba 'el JSON se escribe' ($null -ne $j)
  Igual 'javac: ok (con su espera)' 'ok' (Det $j 'javac').estado
  Comprueba 'javac: tardo lo que esperaba el falso' ((Det $j 'javac').segundos -ge 5) "$((Det $j 'javac').segundos)"
  Igual 'lombok-qualifier: ok' 'ok' (Det $j 'lombok-qualifier').estado
  Igual 'Maven solo se llama para javac' 1 (Llamadas-De $E.Llamadas).Count
  Igual 'ningun Aviso: todos los detectores estan ok' 0 $m.Avisos.Count
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
  Igual 'sin incidencias de javac' 0 (Inc $j 'javac').Count
  Igual 'lombok-a-mano: no se pudo medir (no hay clases)' 'no se pudo medir' (Det $j 'lombok-a-mano').estado
  Igual 'MinutosMaven vuelve a lo que era' 30 $Cfg.MinutosMaven
}

$Pruebas['15 f) cache: sin cambios no se lanza Maven; con un fichero cambiado vuelve a medir'] = {
  $E = Nuevo-Escenario 'f'
  $m1 = Mide $E @{} @{} 'antes' -ConCache
  $n1 = (Llamadas-De $E.Llamadas).Count
  Igual 'la primera vez mide: una llamada a Maven (javac)' 1 $n1
  $m2 = Mide $E @{} @{} 'antes' -ConCache
  Igual 'la segunda, sin cambios: ninguna llamada a Maven mas' $n1 (Llamadas-De $E.Llamadas).Count
  Comprueba 'sale una linea Info que dice que ya estaba medido' ("$($m2.Texto)" -match 'ya medidas') $m2.Texto
  Igual 'el JSON es el mismo (medido)' $m1.Json.medido $m2.Json.medido
  Igual 'la misma clave' $m1.Json.clave $m2.Json.clave
  Escribe $E.Repo 'target/otra.txt' 'x'
  Escribe $E.Repo 'target/classes/otra.class' 'x'
  Escribe $E.Repo 'migracion-2026-11-19/informe.txt' 'x'
  Escribe $E.Repo '.rescate/hallazgos.json' '[]'
  [void](Mide $E @{} @{} 'antes' -ConCache)
  Igual 'target, .rescate y migracion-* no cambian la clave: sigue sin llamar' $n1 (Llamadas-De $E.Llamadas).Count
  # un fichero nuevo
  Escribe $E.Repo 'src/main/java/com/acme/demo/Nuevo.java' "package com.acme.demo;`npublic class Nuevo { }`n"
  $m4 = Mide $E @{} @{} 'antes' -ConCache
  Igual 'un fichero nuevo: vuelve a medir' ($n1 + 1) (Llamadas-De $E.Llamadas).Count
  Comprueba 'la clave cambia' ($m4.Json.clave -cne $m1.Json.clave) "$($m4.Json.clave)"
  Comprueba 'y ya no dice que estaba medido' ("$($m4.Texto)" -notmatch 'ya medidas')
  # el mismo fichero, con otro contenido: el status es igual, el contenido no
  Escribe $E.Repo 'src/main/java/com/acme/demo/Nuevo.java' "package com.acme.demo;`npublic class Nuevo { int a; }`n"
  $m5 = Mide $E @{} @{} 'antes' -ConCache
  Igual 'el mismo fichero con otro contenido: vuelve a medir' ($n1 + 2) (Llamadas-De $E.Llamadas).Count
  Comprueba 'otra clave' ($m5.Json.clave -cne $m4.Json.clave)
  # un commit cambia el HEAD
  [void](GitEn $E.Repo @('add', '-A'))
  [void](GitEn $E.Repo @('commit', '-q', '-m', 'cambio'))
  $m6 = Mide $E @{} @{} 'antes' -ConCache
  Igual 'con un commit nuevo: vuelve a medir' ($n1 + 3) (Llamadas-De $E.Llamadas).Count
  Comprueba 'otra clave con otro HEAD' ($m6.Json.clave -cne $m5.Json.clave)
  # <Cuando> distinto: su propio JSON
  [void](Mide $E @{} @{} 'despues' -ConCache)
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
  Igual 'lombok-qualifier sigue: ok' 'ok' (Det $j 'lombok-qualifier').estado
  Igual 'hallazgos del motor ilegibles: ninguna paso2' 0 @($j.incidencias | Where-Object { $_.queHago -ceq 'paso2' }).Count
  # un JSON de antes ilegible no impide medir
  Escribe $E.Datos 'practicas-antes.json' 'basura'
  $m = Mide $E @{} @{} 'antes' -ConCache
  Igual 'practicas-antes.json ilegible: mide' 'ok' (Det $m.Json 'javac').estado
  # no se puede escribir el JSON (datos es un fichero, no una carpeta): no lanza, avisa y el registro queda
  $E2 = Nuevo-Escenario 'g2'
  Remove-Item -LiteralPath $E2.Datos -Recurse -Force
  Escribe $E2.Raiz 'datos' 'soy un fichero'
  $lanza = $false
  $t = ''
  try { $t = @(Con-Falso @{} @{} { Invoke-Practicas $E2.Repo $E2.Ref 'antes' $E2.Datos $E2.Registros $E2.Hallazgos } 6>&1 | ForEach-Object { "$_" }) -join "`n" } catch { $lanza = $true }
  Igual 'sin poder escribir el JSON: no lanza excepcion' $false $lanza
  Comprueba 'sin poder escribir el JSON: avisa de que no lo ha escrito' ($t -match 'practicas-antes\.json') $t
  Comprueba 'el registro queda aunque el JSON no' (Test-Path -LiteralPath (Join-Path $E2.Registros 'practicas-antes.log'))
  # Datos y Registros que no existen: se crean
  $E3 = Nuevo-Escenario 'g3'
  Remove-Item -LiteralPath $E3.Datos -Recurse -Force
  Remove-Item -LiteralPath $E3.Registros -Recurse -Force
  [void](Mide $E3 @{})
  Comprueba 'las carpetas de datos y de registros que faltaban se crean' ((Test-Path -LiteralPath (Join-Path $E3.Datos 'practicas-antes.json')) -and (Test-Path -LiteralPath (Join-Path $E3.Registros 'practicas-antes.log')))
}

$Pruebas['17 ficheros y ajustes: ASCII, nada de PowerShell 7 y los ajustes en $Cfg'] = {
  Igual 'SegundosPracticas' 300 $Cfg.SegundosPracticas
  Igual 'SonarReglasAqui' 4 $Cfg.SonarReglasAqui
  Comprueba 'SegundosMinAnalisis ya no existe' (-not $Cfg.ContainsKey('SegundosMinAnalisis'))
  foreach ($f in @('practicas.ps1', 'arreglo-practicas.ps1', 'tests/probar-practicas.ps1', 'tests/falsos/bp0-mvn.ps1', 'tests/falsos/bp0-javap.ps1', 'tests/falsos/bp4-mvn.ps1', 'tests/falsos/bp4-copilot.ps1', 'tests/falsos/m65-mvn.ps1')) {
    $t = [System.IO.File]::ReadAllText((Get-Ruta $raiz $f))
    Comprueba "$f`: solo ASCII" ($t -notmatch '[^\x09\x0A\x0D\x20-\x7E]')
  }
  $codigo = [System.IO.File]::ReadAllText((Join-Path $raiz 'practicas.ps1'))
  Comprueba 'practicas.ps1: nada de PowerShell 7 (??, ?. ni ?[)' ($codigo -notmatch '\?\?|[\w\)\]]\?\.\w|\w\?\[')
  Comprueba 'practicas.ps1: sin -AsHashtable ni ConvertFrom-Json -Depth' ($codigo -notmatch 'AsHashtable|ConvertFrom-Json[^|\r\n]*-Depth')
  Comprueba 'practicas.ps1: empieza con su cabecera de ayuda' ($codigo.TrimStart().StartsWith('<#'))
  Comprueba 'practicas.ps1: solo funciones (ni una llamada suelta fuera del $Cfg)' (-not ($codigo -match '(?m)^Invoke-Practicas'))
}

# ================================ BP-4: arreglo-practicas.ps1 ================================
# Maven (bp4-mvn.ps1), javap (bp3-javap.ps1: imprime el texto de cada .class) y Copilot (bp4-copilot.ps1) de mentira. El migrado de cada escenario
# lleva Alfa, Beta, Gama y Delta (com.acme.p4); las incidencias de datos/practicas-antes.json se escriben a mano, sin pasar por el detector.
$Aj4 = @{
  MvnExe = (Join-Path $falsos 'bp4-mvn.ps1'); JavapExe = (Join-Path $falsos 'bp3-javap.ps1'); CopilotExe = (Join-Path $falsos 'bp4-copilot.ps1')
  FallosSeguidos = 3; SegundosPorLlamada = 60
}
$Ruta4 = 'src/main/java/com/acme/p4/'
$Commit4 = 'practica(lombok): '

function Fuente-P4([string]$Clase) {
  return @"
package com.acme.p4;

import java.util.List;

public class $Clase {
    private String id;
    private long importe;

    // el identificador
    public String getId() { return id; }

    public void setId(String id) { this.id = id; }

    /* el importe, en centimos */
    public long getImporte() { return importe; }
}
"@
}

# Lo que pone el script que carga arreglo-practicas.ps1 (migracion.ps1) y aqui se simula: el estado, su guardado y la parada.
$Estado = [ordered]@{ fase = '' }
$script:Paradas = @()
function Save-Estado { }
function Save-Informes { }
function Set-Parada([string]$Motivo, [string]$Detalle, [string]$Registro) { $script:Paradas += , @($Motivo, $Detalle, $Registro) }

# $Pom es el pom.xml del migrado (sin el, uno de una linea con o sin Lombok segun $Lombok); con $PomRef hay una referencia con ese pom.xml.
function Nuevo-Escenario4([string]$Nombre, [string[]]$Incidencias, [bool]$Lombok = $true, [string[]]$Rotas = @(), [string]$Pom = '', [string]$PomRef = '') {
  $r = Join-Path $Dir $Nombre
  if (Test-Path -LiteralPath $r) { Remove-Item -LiteralPath $r -Recurse -Force }
  $mig = Join-Path $r 'migrado'
  $dep = ''
  if ($Lombok) { $dep = '<dependencies><dependency><groupId>org.projectlombok</groupId><artifactId>lombok</artifactId><version>1.18.34</version></dependency></dependencies>' }
  if (-not $Pom) { $Pom = "<project><modelVersion>4.0.0</modelVersion><groupId>com.acme</groupId><artifactId>p4</artifactId><version>1</version>$dep</project>`n" }
  Escribe $mig 'pom.xml' $Pom
  $ref = ''
  if ($PomRef) { $ref = Join-Path $r 'batch-ejemplo'; Escribe $ref 'pom.xml' $PomRef }
  foreach ($c in @('Alfa', 'Beta', 'Gama', 'Delta')) {
    $fuente = Fuente-P4 $c
    if ($Rotas -contains $c) { $fuente = $fuente.Replace('private long importe;', 'private long importe = NO-COMPILA;') }
    Escribe $mig "$Ruta4$c.java" $fuente
  }
  Inicia-Repo $mig
  Set-Excluidos $mig
  foreach ($d in @('datos', 'registros')) { [void](New-Item -ItemType Directory -Path (Join-Path $r $d) -Force) }
  $inc = @($Incidencias | ForEach-Object { New-Incidencia 'lombok' "$Ruta4$_.java" 10 'lombok' 'getter-setter-a-mano' 'referencia' '' '2 getters y 1 setters escritos a mano: con Lombok son @Getter y @Setter' })
  Write-Json (Join-Path (Join-Path $r 'datos') 'practicas-antes.json') ([ordered]@{ version = 1; cuando = ''; detectores = @(); incidencias = $inc })
  return [pscustomobject]@{
    Raiz = $r; Repo = $mig; Plantilla = $ref; Datos = (Join-Path $r 'datos'); Registros = (Join-Path $r 'registros')
    Mvn = (Join-Path $r 'mvn-llamadas.txt'); Copilot = (Join-Path $r 'copilot-llamadas.txt')
  }
}

# Invoke-FasePracticas sobre el escenario, con los falsos y las variables del script que la carga. Devuelve lo que dijo (Sigue), la consola
# (Texto y Avisos), el JSON de resultados, las tareas guardadas y los commits del migrado (el asunto de cada uno, el ultimo primero).
function Fase4($E, [hashtable]$Entorno = @{}, [hashtable]$Cambios = @{}, [bool]$Mantener = $true) {
  $Entorno['BP4_LLAMADAS'] = $E.Mvn
  $Entorno['BP4_COPILOT'] = $E.Copilot
  $ajustes4 = @{}
  foreach ($k in $Aj4.Keys) { $ajustes4[$k] = $Aj4[$k] }
  foreach ($k in $Cambios.Keys) { $ajustes4[$k] = $Cambios[$k] }
  $RepoRoot = $E.Repo
  $PlantillaRoot = $E.Plantilla
  $Datos = $E.Datos
  $Registros = $E.Registros
  $ModeloElegido = 'modelo-x'
  $script:Parada = $false
  $script:Paradas = @()
  $script:Todas = @()
  $salida = @(Con-Falso $Entorno $ajustes4 { Invoke-FasePracticas $Mantener } 6>&1)
  $info = @($salida | Where-Object { $_ -is [System.Management.Automation.InformationRecord] })
  $tareas = @()
  if (Test-Path -LiteralPath (Join-Path $E.Datos 'tareas')) { $tareas = @(Get-ChildItem -LiteralPath (Join-Path $E.Datos 'tareas') -Filter '*.json' | ForEach-Object { Lee-Json $_.FullName }) }
  return [pscustomobject]@{
    Sigue = (@($salida | Where-Object { $_ -is [bool] })[0])
    Texto = (@($info | ForEach-Object { "$_" }) -join "`n")
    Avisos = @($info | Where-Object { "$($_.MessageData.ForegroundColor)" -ceq 'Yellow' } | ForEach-Object { "$_" })
    Json = (Lee-Json (Join-Path $E.Datos 'practicas-arreglos.json'))
    Tareas = $tareas
    Commits = @((GitEn $E.Repo @('log', '--format=%s')) -split "`n")
  }
}

function Tarea4($X, [string]$Clase) { return @($X.Tareas | Where-Object { $_.entradas.fichero -ceq "$Ruta4$Clase.java" })[0] }
function Compilaciones4($E) { return @(Llamadas-De $E.Mvn | Where-Object { $_ -match '\|-B compile$' }) }
function Estado-Git4($E) { return (GitEn $E.Repo @('status', '--short')) }
function Quedan-Cambios4($E, [string]$Clase) { return ((Lee $E.Repo "$Ruta4$Clase.java") -cne (Fuente-P4 $Clase)) }

$Pruebas['18 bp4 a) dos ficheros con solo comentarios nuevos: un commit por fichero y las dos tareas hechas'] = {
  $E = Nuevo-Escenario4 'p4a' @('Alfa', 'Beta')
  $x = Fase4 $E
  Igual 'la fase deja seguir' $true $x.Sigue
  Igual 'ninguna parada' 0 $script:Paradas.Count
  Igual 'los commits: uno por fichero, en orden' ("$Commit4${Ruta4}Beta.java|$Commit4${Ruta4}Alfa.java|inicial") ($x.Commits -join '|')
  foreach ($c in @('Alfa', 'Beta')) {
    $t = Tarea4 $x $c
    Igual "$c`: tarea hecha" 'hecha' $t.estado
    Igual "$c`: con un solo intento" 1 $t.intentos
    Comprueba "$c`: el fichero lleva el cambio de la IA" ((Lee $E.Repo "$Ruta4$c.java") -match '// pasado a Lombok')
  }
  $quien = @((GitEn $E.Repo @('show', '--name-only', '--format=', 'HEAD')) -split "`n")
  Igual 'el ultimo commit solo toca su fichero' "${Ruta4}Beta.java" ($quien -join '|')
  $quien = @((GitEn $E.Repo @('show', '--name-only', '--format=', 'HEAD~1')) -split "`n")
  Igual 'el anterior, el suyo' "${Ruta4}Alfa.java" ($quien -join '|')
  Igual 'el worktree queda limpio' '' (Estado-Git4 $E)
  Igual 'dos llamadas a Copilot' 2 (Llamadas-De $E.Copilot).Count
  Igual 'Maven: la foto y una compilacion de la ronda' 2 (Compilaciones4 $E).Count
  Comprueba 'la foto de antes esta en .rescate/practicas/antes' (Test-Path -LiteralPath (Get-Ruta $E.Repo '.rescate/practicas/antes/com/acme/p4/Alfa.class'))
}

$Pruebas['19 bp4 b) codigo cambiado en uno: vuelve atras, se reintenta con el motivo y al segundo fallo queda atascado; el otro se commitea'] = {
  $E = Nuevo-Escenario4 'p4b' @('Alfa', 'Beta')
  $x = Fase4 $E @{ RESCATE_FALSO = 'codigo:Alfa' }
  Igual 'la fase deja seguir (una atascada no para)' $true $x.Sigue
  Igual 'ninguna parada' 0 $script:Paradas.Count
  Igual 'solo se commitea Beta' ("$Commit4${Ruta4}Beta.java|inicial") ($x.Commits -join '|')
  Comprueba 'Alfa vuelve a como estaba' (-not (Quedan-Cambios4 $E 'Alfa'))
  Igual 'el worktree queda limpio' '' (Estado-Git4 $E)
  $t = Tarea4 $x 'Alfa'
  Igual 'Alfa: atascada' 'atascada' $t.estado
  Igual 'Alfa: dos intentos' 2 $t.intentos
  Comprueba 'Alfa: el motivo dice las partes de la huella que cambian' ($t.motivo -match 'metodos:') $t.motivo
  Igual 'Beta: hecha' 'hecha' (Tarea4 $x 'Beta').estado
  $log = Lee $E.Registros ($t.id + '-2.log')
  Comprueba 'el segundo prompt lleva la correccion con el motivo' ($log -match 'CORRECCI' -and $log.Contains($t.motivo)) 
  Comprueba 'el primer prompt no la lleva' ((Lee $E.Registros ($t.id + '-1.log')) -notmatch 'CORRECCI')
  $ll = Llamadas-De $E.Copilot
  Igual 'tres llamadas: Alfa, Beta y el reintento de Alfa' 3 $ll.Count
  Igual 'dos de ellas son de Alfa (una con correccion)' 2 @($ll | Where-Object { $_ -match 'Alfa\.java\|codigo\|' }).Count
  Igual 'una es el reintento' 1 @($ll | Where-Object { $_ -match '\|1$' }).Count
  Comprueba 'avisa de la atascada con su fichero' (@($x.Avisos | Where-Object { $_ -match ('Atascada: ' + [regex]::Escape("${Ruta4}Alfa.java")) }).Count -eq 1) ($x.Avisos -join ' / ')
}

$Pruebas['19b bp4 b3) el fichero rechazado en la primera ronda esta como en HEAD cuando empieza el reintento'] = {
  $E = Nuevo-Escenario4 'p4b3' @('Alfa', 'Beta')
  $deHead = Join-Path $E.Raiz 'copilot-estado.txt'
  [void](Fase4 $E @{ RESCATE_FALSO = 'codigo:Alfa'; BP4_ESTADO = $deHead })
  $todas = Llamadas-De $deHead
  $ll = @($todas | Where-Object { $_ -match 'Alfa\.java\|' })
  Igual 'dos llamadas a Alfa: la primera ronda y el reintento' 2 $ll.Count
  if ($ll.Count -ne 2) { return }
  Comprueba 'la primera: el fichero empieza como en HEAD' ($ll[0] -match '\|0\|0$') $ll[0]
  Comprueba 'el reintento: el fichero rechazado esta como en HEAD, sin lo que cambio la primera vez' ($ll[1] -match '\|1\|0$') $ll[1]
}

$Pruebas['20 bp4 b2) el primer intento cambia el codigo y el reintento, con el motivo, lo hace bien: hecha con dos intentos'] = {
  $E = Nuevo-Escenario4 'p4b2' @('Alfa', 'Beta')
  $x = Fase4 $E @{ RESCATE_FALSO = 'codigo1:Alfa' }
  Igual 'los dos commits: el de Beta en la primera ronda y el de Alfa en el reintento' ("$Commit4${Ruta4}Alfa.java|$Commit4${Ruta4}Beta.java|inicial") ($x.Commits -join '|')
  $t = Tarea4 $x 'Alfa'
  Igual 'Alfa: hecha' 'hecha' $t.estado
  Igual 'Alfa: dos intentos' 2 $t.intentos
  Igual 'sin avisos de atascadas' 0 @($x.Avisos | Where-Object { $_ -match 'Atascada' }).Count
}

$Pruebas['21 bp4 c) la IA toca ademas otro fichero: se deshace ese y el suyo se acepta'] = {
  $E = Nuevo-Escenario4 'p4c' @('Alfa', 'Beta')
  $x = Fase4 $E @{ RESCATE_FALSO = 'otro:Alfa' }
  Igual 'la fase deja seguir' $true $x.Sigue
  Igual 'los dos commits' ("$Commit4${Ruta4}Beta.java|$Commit4${Ruta4}Alfa.java|inicial") ($x.Commits -join '|')
  Comprueba 'Delta vuelve a como estaba' (-not (Quedan-Cambios4 $E 'Delta'))
  Igual 'el worktree queda limpio' '' (Estado-Git4 $E)
  Igual 'el commit de Alfa solo lleva Alfa' "${Ruta4}Alfa.java" ((GitEn $E.Repo @('show', '--name-only', '--format=', 'HEAD~1')) -split "`n" -join '|')
  Comprueba 'lo dice con Info y la ruta deshecha' ($x.Texto.Contains("Deshago lo que la IA ha tocado fuera de lo suyo: ${Ruta4}Delta.java")) $x.Texto
  Igual 'Alfa: hecha' 'hecha' (Tarea4 $x 'Alfa').estado
}

$Pruebas['21b bp4 c2) la IA deja sus cambios en el indice con git add: se ven igual, se deshace lo ajeno y lo suyo se acepta'] = {
  $E = Nuevo-Escenario4 'p4c2' @('Alfa', 'Beta')
  $x = Fase4 $E @{ RESCATE_FALSO = 'otro-add:Alfa' }
  Igual 'los dos commits' ("$Commit4${Ruta4}Beta.java|$Commit4${Ruta4}Alfa.java|inicial") ($x.Commits -join '|')
  Comprueba 'Delta vuelve a como estaba' (-not (Quedan-Cambios4 $E 'Delta'))
  Igual 'ni el indice ni el worktree llevan nada' '' (Estado-Git4 $E)
  Igual 'el commit de Alfa solo lleva Alfa' "${Ruta4}Alfa.java" ((GitEn $E.Repo @('show', '--name-only', '--format=', 'HEAD~1')) -split "`n" -join '|')
  Igual 'Alfa: hecha' 'hecha' (Tarea4 $x 'Alfa').estado
}

$Pruebas['22 bp4 d) un fichero no compila: la ronda se deshace, se prueban de uno en uno y el que compila se acepta'] = {
  $E = Nuevo-Escenario4 'p4d' @('Alfa', 'Beta')
  $x = Fase4 $E @{ RESCATE_FALSO = 'no-compila:Alfa' }
  Igual 'la fase deja seguir' $true $x.Sigue
  Igual 'solo se commitea Beta' ("$Commit4${Ruta4}Beta.java|inicial") ($x.Commits -join '|')
  Comprueba 'Alfa vuelve a como estaba' (-not (Quedan-Cambios4 $E 'Alfa'))
  Igual 'el worktree queda limpio' '' (Estado-Git4 $E)
  Comprueba 'lo dice: la ronda no compila y se prueba de uno en uno' ($x.Texto -match 'de uno en uno') $x.Texto
  $t = Tarea4 $x 'Alfa'
  Igual 'Alfa: atascada tras dos intentos' 'atascada' $t.estado
  Comprueba 'Alfa: el motivo es que no compila, con la linea de Maven' ($t.motivo -match 'no compila' -and $t.motivo -match 'Alfa\.java') $t.motivo
  Igual 'Beta: hecha' 'hecha' (Tarea4 $x 'Beta').estado
  # foto (1) + la ronda entera (1) + Alfa sola (1) y Beta sola (1) + el reintento de Alfa, que va sola (1)
  Igual 'Maven: 5 compilaciones' 5 (Compilaciones4 $E).Count
}

$Pruebas['22b bp4 d2) el que no compila va el segundo: de uno en uno cada fichero se prueba aislado, el primero se acepta'] = {
  $E = Nuevo-Escenario4 'p4d2' @('Alfa', 'Beta')
  $x = Fase4 $E @{ RESCATE_FALSO = 'no-compila:Beta' }
  Igual 'la fase deja seguir' $true $x.Sigue
  Igual 'solo se commitea Alfa' ("$Commit4${Ruta4}Alfa.java|inicial") ($x.Commits -join '|')
  Comprueba 'Beta vuelve a como estaba' (-not (Quedan-Cambios4 $E 'Beta'))
  Igual 'el worktree queda limpio' '' (Estado-Git4 $E)
  Comprueba 'lo dice: la ronda no compila y se prueba de uno en uno' ($x.Texto -match 'de uno en uno') $x.Texto
  Igual 'Alfa: hecha' 'hecha' (Tarea4 $x 'Alfa').estado
  $t = Tarea4 $x 'Beta'
  Igual 'Beta: atascada tras dos intentos' 'atascada' $t.estado
  Comprueba 'Beta: el motivo es que no compila, con la linea de Maven' ($t.motivo -match 'no compila' -and $t.motivo -match 'Beta\.java') $t.motivo
  # foto (1) + la ronda entera (1) + Alfa sola (1) y Beta sola (1) + el reintento de Beta, que va sola (1)
  Igual 'Maven: 5 compilaciones' 5 (Compilaciones4 $E).Count
}

$Pruebas['24 bp4 f) relanzar no repite las tareas hechas ni rehace la foto'] = {
  $E = Nuevo-Escenario4 'p4f' @('Alfa', 'Beta')
  [void](Fase4 $E)
  $copias = (Llamadas-De $E.Copilot).Count
  $mvn = (Llamadas-De $E.Mvn).Count
  $hash = (GitEn $E.Repo @('rev-parse', 'HEAD'))
  $foto = Get-Ruta $E.Repo '.rescate/practicas/antes/com/acme/p4/Alfa.class'
  $antes = (Get-Item -LiteralPath $foto).LastWriteTimeUtc.Ticks
  $x = Fase4 $E
  Igual 'la fase deja seguir' $true $x.Sigue
  Igual 'ninguna llamada nueva a Copilot' $copias (Llamadas-De $E.Copilot).Count
  Igual 'ninguna llamada nueva a Maven (ni foto ni ronda)' $mvn (Llamadas-De $E.Mvn).Count
  Igual 'ningun commit nuevo' $hash (GitEn $E.Repo @('rev-parse', 'HEAD'))
  Igual 'la foto no se toca' $antes (Get-Item -LiteralPath $foto).LastWriteTimeUtc.Ticks
  Igual 'las dos tareas siguen hechas' 2 @($x.Tareas | Where-Object { $_.estado -ceq 'hecha' }).Count
  Comprueba 'la consola sigue diciendo los dos pasados' ($x.Texto -match 'Buenas practicas: 2 ficheros pasados a Lombok, 0 atascados, 0 sin cambios') $x.Texto
}

$Pruebas['24b bp4 f2) relanzar con una atascada: se conserva sin repetir; con -Reintentar vuelve a intentarse y reutiliza la foto'] = {
  $E = Nuevo-Escenario4 'p4f2' @('Alfa', 'Beta')
  [void](Fase4 $E @{ RESCATE_FALSO = 'codigo:Alfa' })
  $copias = (Llamadas-De $E.Copilot).Count
  $mvn = (Compilaciones4 $E).Count
  $x = Fase4 $E @{ RESCATE_FALSO = 'bien' }
  Igual 'la fase deja seguir' $true $x.Sigue
  Igual 'Alfa sigue atascada' 'atascada' (Tarea4 $x 'Alfa').estado
  Igual 'ninguna llamada nueva a Copilot' $copias (Llamadas-De $E.Copilot).Count
  Igual 'ninguna compilacion nueva' $mvn (Compilaciones4 $E).Count
  $x = Fase4 $E @{ RESCATE_FALSO = 'bien' } @{} $false
  Igual 'con -Reintentar: Alfa, hecha' 'hecha' (Tarea4 $x 'Alfa').estado
  Igual 'una llamada nueva a Copilot' ($copias + 1) (Llamadas-De $E.Copilot).Count
  Igual 'una sola compilacion nueva: la de la ronda, sin rehacer la foto' ($mvn + 1) (Compilaciones4 $E).Count
  Igual 'los dos commits' ("$Commit4${Ruta4}Alfa.java|$Commit4${Ruta4}Beta.java|inicial") ($x.Commits -join '|')
}

$Pruebas['24c bp4 f3) un commit ajeno entre dos lanzamientos cambia el HEAD de partida: la foto se rehace con el HEAD nuevo'] = {
  $E = Nuevo-Escenario4 'p4f3' @('Alfa')
  [void](Fase4 $E @{ RESCATE_FALSO = 'codigo:Alfa' })
  Igual 'Alfa, atascada' 'atascada' (Tarea4 (Fase4 $E @{ RESCATE_FALSO = 'bien' }) 'Alfa').estado
  # un cambio de codigo en una clase que no es de ninguna tarea, confirmado por otra mano
  Escribe $E.Repo "${Ruta4}Gama.java" ((Fuente-P4 'Gama').Replace('private long importe;', "private long importe;`n    private int nuevo;"))
  [void](GitEn $E.Repo @('commit', '-q', '-a', '-m', 'cambio ajeno'))
  $head = GitEn $E.Repo @('rev-parse', 'HEAD')
  $mvn = (Compilaciones4 $E).Count
  $x = Fase4 $E @{ RESCATE_FALSO = 'bien' } @{} $false
  Igual 'con -Reintentar: Alfa, hecha (la foto vieja no tiene lo nuevo de Gama)' 'hecha' (Tarea4 $x 'Alfa').estado
  Igual 'dos compilaciones nuevas: la foto, rehecha, y la ronda' ($mvn + 2) (Compilaciones4 $E).Count
  Comprueba 'la foto nueva lleva lo nuevo de Gama' ((Lee $E.Repo '.rescate/practicas/antes/com/acme/p4/Gama.class') -match 'nuevo')
  Igual 'partida.txt lleva el HEAD nuevo' $head ((Lee $E.Repo '.rescate/practicas/partida.txt').Trim())
  Igual 'el commit de Alfa y el ajeno' ("$Commit4${Ruta4}Alfa.java|cambio ajeno|inicial") ($x.Commits -join '|')
}

$Pruebas['25 bp4 g) migracion.ps1: -Practicas es un switch y la fase solo se llama con el, despues de la correccion y antes de la prueba en local'] = {
  $t = [System.IO.File]::ReadAllText((Join-Path $raiz 'migracion.ps1'))
  Comprueba 'parametro [switch]$Practicas' ($t -match '(?m)^\s*\[switch\]\$Practicas\b')
  Comprueba 'carga huella.ps1 y arreglo-practicas.ps1 junto a los demas' ($t -match "(?m)^\. \(Join-Path \`$PSScriptRoot 'huella\.ps1'\)" -and $t -match "(?m)^\. \(Join-Path \`$PSScriptRoot 'arreglo-practicas\.ps1'\)")
  Comprueba 'la ayuda lo dice en el USO' ($t -match '(?m)^\s+\.\\migracion\.ps1 \.\.\. -Practicas\b')
  $llamadas = @([regex]::Matches($t, '(?m)^.*Invoke-FasePracticas.*$'))
  Igual 'la fase se llama en un solo sitio' 1 $llamadas.Count
  if ($llamadas.Count -ne 1) { return }
  Comprueba 'esa llamada solo vale con $Practicas' ($llamadas[0].Value -match 'if \(\$sigue -and \$Practicas\)') $llamadas[0].Value
  $corr = $t.LastIndexOf('Invoke-FaseCorreccion')
  $prueba = $t.LastIndexOf('Invoke-FasePruebaLocal')
  Comprueba 'va despues de la correccion y antes de la prueba en local' ($corr -ge 0 -and $corr -lt $llamadas[0].Index -and $llamadas[0].Index -lt $prueba)
}

$Pruebas['26 bp4 h) el JSON de resultados y la consola llevan los mismos numeros: pasados, atascados y sin cambios'] = {
  $E = Nuevo-Escenario4 'p4h' @('Alfa', 'Beta', 'Gama')
  $x = Fase4 $E @{ RESCATE_FALSO = 'codigo:Beta;nada:Gama' }
  Comprueba 'la consola dice los tres numeros' ($x.Texto -match '(?m)^Buenas practicas: 1 ficheros pasados a Lombok, 1 atascados, 1 sin cambios\s*$') $x.Texto
  $j = $x.Json
  Comprueba 'existe datos/practicas-arreglos.json' ($null -ne $j)
  if ($null -eq $j) { return }
  Igual 'JSON: pasados' 1 $j.pasados
  Igual 'JSON: atascados' 1 $j.atascados
  Igual 'JSON: sinCambios' 1 $j.sinCambios
  Igual 'JSON: una entrada por tarea' 3 @($j.tareas).Count
  $a = @($j.tareas | Where-Object { $_.fichero -ceq "${Ruta4}Alfa.java" })[0]
  Igual 'Alfa: hecha' 'hecha' $a.estado
  Igual 'Alfa: su commit' (GitEn $E.Repo @('rev-parse', 'HEAD')) $a.commit
  Igual 'Alfa: sin motivo' '' $a.motivo
  $b = @($j.tareas | Where-Object { $_.fichero -ceq "${Ruta4}Beta.java" })[0]
  Igual 'Beta: atascada' 'atascada' $b.estado
  Igual 'Beta: sin commit' '' $b.commit
  Comprueba 'Beta: con su motivo' ($b.motivo -match 'metodos:') $b.motivo
  $g = @($j.tareas | Where-Object { $_.fichero -ceq "${Ruta4}Gama.java" })[0]
  Igual 'Gama: hecha' 'hecha' $g.estado
  Igual 'Gama: sin commit' '' $g.commit
  Igual 'Gama: sin cambios' 'sin cambios' $g.motivo
}

$Pruebas['27 bp4 i) sin incidencias de Lombok: ninguna llamada y una linea'] = {
  $E = Nuevo-Escenario4 'p4i' @()
  $x = Fase4 $E
  Igual 'la fase deja seguir' $true $x.Sigue
  Igual 'ninguna llamada a Copilot' 0 (Llamadas-De $E.Copilot).Count
  Igual 'ninguna llamada a Maven' 0 (Llamadas-De $E.Mvn).Count
  Comprueba 'una linea con los tres numeros a cero' ($x.Texto -match '(?m)^Buenas practicas: 0 ficheros pasados a Lombok, 0 atascados, 0 sin cambios') $x.Texto
  Igual 'el JSON, sin tareas' 0 @($x.Json.tareas).Count
}

$Pruebas['28 bp4 j) un migrado que no compila: parada con el fallo de Maven y sin llamadas a Copilot'] = {
  $E = Nuevo-Escenario4 'p4j' @('Alfa') $true @('Gama')
  $x = Fase4 $E
  Igual 'la fase no deja seguir' $false $x.Sigue
  Igual 'una parada' 1 $script:Paradas.Count
  if ($script:Paradas.Count -ne 1) { return }
  Igual 'motivo no-compila' 'no-compila' $script:Paradas[0][0]
  Comprueba 'el detalle lleva el error de Maven' ($script:Paradas[0][1] -match 'COMPILATION ERROR' -and $script:Paradas[0][1] -match 'Gama\.java') $script:Paradas[0][1]
  Comprueba 'el registro es el de Maven y existe' (Test-Path -LiteralPath $script:Paradas[0][2])
  Igual 'ninguna llamada a Copilot' 0 (Llamadas-De $E.Copilot).Count
}

$Pruebas['29 bp4 k) Copilot que falla varias veces seguidas: parada copilot-no-responde y las tareas vuelven a empezar'] = {
  $E = Nuevo-Escenario4 'p4k' @('Alfa', 'Beta')
  $x = Fase4 $E @{ RESCATE_FALSO = 'falla' }
  Igual 'la fase no deja seguir' $false $x.Sigue
  Igual 'una parada' 1 $script:Paradas.Count
  if ($script:Paradas.Count -ne 1) { return }
  Igual 'motivo copilot-no-responde' 'copilot-no-responde' $script:Paradas[0][0]
  Igual 'ningun commit' 'inicial' ($x.Commits -join '|')
  Igual 'las tareas vuelven a pendiente y sin intentos' 2 @($x.Tareas | Where-Object { $_.estado -ceq 'pendiente' -and $_.intentos -eq 0 }).Count
  Igual 'el worktree queda limpio' '' (Estado-Git4 $E)
}

$Pruebas['29b bp4 k2) una llamada que falla despues de cambiar el fichero: se deshace su cambio y se atasca con el codigo de Copilot, sin parar a las demas'] = {
  $E = Nuevo-Escenario4 'p4k2' @('Alfa', 'Beta')
  $x = Fase4 $E @{ RESCATE_FALSO = 'falla-cambia:Alfa' }
  Igual 'la fase deja seguir' $true $x.Sigue
  Igual 'solo se commitea Beta' ("$Commit4${Ruta4}Beta.java|inicial") ($x.Commits -join '|')
  Comprueba 'Alfa vuelve a como estaba' (-not (Quedan-Cambios4 $E 'Alfa'))
  Igual 'el worktree queda limpio' '' (Estado-Git4 $E)
  $t = Tarea4 $x 'Alfa'
  Igual 'Alfa: atascada' 'atascada' $t.estado
  Comprueba 'Alfa: el motivo es el codigo de Copilot' ($t.motivo -match 'Copilot salio con codigo 1') $t.motivo
  Igual 'Alfa: el reintento va sin correccion (fue un fallo de Copilot, no del arreglo)' 0 @((Llamadas-De $E.Copilot) | Where-Object { $_ -match '\|1$' }).Count
}

$Pruebas['30 bp4 l) Test-ClaseDeFichero: X.class y X$Interna.class son del fichero X.java; XY.class y X2.class, no'] = {
  $f = "${Ruta4}Alfa.java"
  Igual 'la clase' $true (Test-ClaseDeFichero 'com/acme/p4/Alfa.class' $f)
  Igual 'una interna' $true (Test-ClaseDeFichero 'com/acme/p4/Alfa$Interna.class' $f)
  Igual 'una interna de una interna' $true (Test-ClaseDeFichero 'com/acme/p4/Alfa$Interna$Mas.class' $f)
  Igual 'otra clase que empieza igual' $false (Test-ClaseDeFichero 'com/acme/p4/AlfaBeta.class' $f)
  Igual 'otra con numero' $false (Test-ClaseDeFichero 'com/acme/p4/Alfa2.class' $f)
  Igual 'otro paquete' $false (Test-ClaseDeFichero 'com/acme/otro/Alfa.class' $f)
  Igual 'no es una clase' $false (Test-ClaseDeFichero 'com/acme/p4/Alfa.properties' $f)
  Igual 'un modulo: la ruta del fichero lleva carpeta delante' $true (Test-ClaseDeFichero 'com/acme/p4/Alfa.class' "modulo/$f")
}

$Pruebas['31 bp4 n) Test-PomLombok: lo encuentra en el pom de un modulo y no mira target ni .git ni src'] = {
  $E = Nuevo-Escenario4 'p4n' @('Alfa') $false
  $RepoRoot = $E.Repo
  $dep = '<project><dependencies><dependency><groupId>org.projectlombok</groupId><artifactId>lombok</artifactId></dependency></dependencies></project>'
  Igual 'sin Lombok en ningun pom' $false (Test-PomLombok)
  foreach ($d in @('target/x', 'src/main/java/y', '.git/z', '.rescate/w')) { Escribe $E.Repo "$d/pom.xml" $dep }
  Igual 'con un pom suyo en target, src, .git y .rescate, tampoco' $false (Test-PomLombok)
  Escribe $E.Repo 'modulo-a/pom.xml' $dep
  Igual 'con Lombok en el pom de un modulo' $true (Test-PomLombok)
}

$Pruebas['32 bp4 o) una diferencia en una clase que no es de ningun fichero de la ronda: no se da por buena en bloque y se prueba de uno en uno'] = {
  $E = Nuevo-Escenario4 'p4o' @('Alfa', 'Beta')
  $x = Fase4 $E @{ BP4_SUELTA = '1' }
  Igual 'los dos commits' ("$Commit4${Ruta4}Beta.java|$Commit4${Ruta4}Alfa.java|inicial") ($x.Commits -join '|')
  Comprueba 'lo dice, con la clase suelta' ($x.Texto -match 'de uno en uno' -and $x.Texto -match 'Suelta\.class') $x.Texto
  # foto (1) + la ronda entera (1) + cada fichero solo (2)
  Igual 'Maven: 4 compilaciones' 4 (Compilaciones4 $E).Count
}

$Pruebas['33 bp4 p) la IA hace un commit: se deshace, se avisa con el motivo y el reintento tambien se deshace'] = {
  $E = Nuevo-Escenario4 'p4p' @('Alfa', 'Beta')
  $x = Fase4 $E @{ RESCATE_FALSO = 'commit:Alfa' }
  Igual 'la fase deja seguir' $true $x.Sigue
  Igual 'ningun commit de la IA ni de la fase: el commit de la IA lleva a repetir tambien a Beta, que solo comenta' 'inicial' (($x.Commits | Where-Object { $_ -notmatch 'practica\(lombok\)' }) -join '|')
  Igual 'el worktree queda limpio' '' (Estado-Git4 $E)
  $t = Tarea4 $x 'Alfa'
  Igual 'Alfa: atascada' 'atascada' $t.estado
  Comprueba 'Alfa: el motivo dice que ha hecho un commit' ($t.motivo -match 'commit') $t.motivo
}

$Pruebas['34 bp4 q) la IA borra el fichero: vuelve atras y se reintenta con el motivo'] = {
  $E = Nuevo-Escenario4 'p4q' @('Alfa', 'Beta')
  $x = Fase4 $E @{ RESCATE_FALSO = 'borra:Alfa' }
  Igual 'solo se commitea Beta' ("$Commit4${Ruta4}Beta.java|inicial") ($x.Commits -join '|')
  Comprueba 'Alfa esta como estaba' (-not (Quedan-Cambios4 $E 'Alfa'))
  Igual 'el worktree queda limpio' '' (Estado-Git4 $E)
  $t = Tarea4 $x 'Alfa'
  Igual 'Alfa: atascada' 'atascada' $t.estado
  Comprueba 'Alfa: el motivo dice que ha borrado el fichero' ($t.motivo -match 'borrado') $t.motivo
}

$Pruebas['35 bp4 r) un commit que git rechaza (un hook): parada git con su salida, el fichero como estaba y la tarea sin gastar el intento'] = {
  $E = Nuevo-Escenario4 'p4r' @('Alfa')
  [void](GitEn $E.Repo @('config', 'core.hooksPath', '.git/hooks'))   # el global del usuario, si lo hay, no cuenta aqui
  Escribe $E.Repo '.git/hooks/pre-commit' "#!/bin/sh`necho 'hook de mentira: no se commitea'`nexit 1`n"
  if (Get-Command chmod -ErrorAction SilentlyContinue) { & chmod +x (Get-Ruta $E.Repo '.git/hooks/pre-commit') }
  $x = Fase4 $E
  Igual 'la fase no deja seguir' $false $x.Sigue
  Igual 'una parada' 1 $script:Paradas.Count
  if ($script:Paradas.Count -ne 1) { return }
  Igual 'motivo git' 'git' $script:Paradas[0][0]
  Comprueba 'el detalle lleva el fichero y lo que dijo git' ($script:Paradas[0][1] -match 'Alfa\.java' -and $script:Paradas[0][1] -match 'hook de mentira') $script:Paradas[0][1]
  Comprueba 'Alfa vuelve a como estaba' (-not (Quedan-Cambios4 $E 'Alfa'))
  Igual 'el worktree queda limpio' '' (Estado-Git4 $E)
  $t = Tarea4 $x 'Alfa'
  Igual 'Alfa: sigue pendiente, sin intentos gastados' 'pendiente' $t.estado
  Igual 'Alfa: cero intentos' 0 $t.intentos
}

$Pruebas['36 bp4 s) lo que habia sin confirmar en el worktree se aparta a un git stash al empezar, con su aviso'] = {
  $E = Nuevo-Escenario4 'p4s' @('Alfa')
  Escribe $E.Repo "${Ruta4}Delta.java" ((Fuente-P4 'Delta') + "// resto de una pasada que se corto`n")
  Escribe $E.Repo "${Ruta4}Suelto.java" "class Suelto { }`n"
  $x = Fase4 $E
  Comprueba 'lo dice, con los dos ficheros y como recuperarlo (stash apply <hash>, m45)' ($x.Texto.Contains('Aparto lo que habia sin confirmar en el worktree (git stash): ') -and $x.Texto.Contains("${Ruta4}Delta.java") -and $x.Texto.Contains("${Ruta4}Suelto.java") -and $x.Texto.Contains('Para recuperarlo: git -C "' + $E.Repo + '" stash apply ' + (GitEn $E.Repo @('rev-parse', 'refs/stash')))) $x.Texto
  Comprueba 'ya no dice que lo deshace' ($x.Texto -notmatch 'Deshago lo que habia sin confirmar') $x.Texto
  $st = @((GitEn $E.Repo @('stash', 'list')) -split "`n" | Where-Object { $_ })
  Igual 'hay un stash' 1 $st.Count
  Comprueba 'con su mensaje' ($st.Count -eq 1 -and $st[0] -match 'practicas: cambios sin commit de antes') ($st -join ' / ')
  Comprueba 'el stash lleva el cambio de Delta' ((GitEn $E.Repo @('show', 'stash@{0}')) -match 'resto de una pasada que se corto')
  Comprueba 'y el fichero nuevo' ((GitEn $E.Repo @('show', ('stash@{0}^3:' + "${Ruta4}Suelto.java"))) -match 'class Suelto')
  Comprueba 'Delta vuelve a como estaba' (-not (Quedan-Cambios4 $E 'Delta'))
  Comprueba 'el fichero nuevo ya no esta' (-not (Test-Path -LiteralPath (Get-Ruta $E.Repo "${Ruta4}Suelto.java")))
  Igual 'el commit de Alfa y nada mas' ("$Commit4${Ruta4}Alfa.java|inicial") ($x.Commits -join '|')
  Igual 'el worktree queda limpio' '' (Estado-Git4 $E)
  # si el git stash no puede guardarlo (un cerrojo en refs/stash), no se borra nada: parada git
  $E = Nuevo-Escenario4 'p4s2' @('Alfa')
  Escribe $E.Repo "${Ruta4}Delta.java" ((Fuente-P4 'Delta') + "// resto de una pasada que se corto`n")
  Escribe $E.Repo '.git/refs/stash.lock' ''   # un cerrojo en refs/stash: git stash falla sin tocar nada
  $x = Fase4 $E
  Remove-Item -LiteralPath (Get-Ruta $E.Repo '.git/refs/stash.lock') -Force
  Igual 'la fase no deja seguir' $false $x.Sigue
  Igual 'una parada' 1 $script:Paradas.Count
  if ($script:Paradas.Count -ne 1) { return }
  Igual 'motivo git' 'git' $script:Paradas[0][0]
  Comprueba 'el detalle dice que no ha podido apartarlo' ($script:Paradas[0][1] -match 'No he podido apartar con git stash lo que habia sin confirmar') $script:Paradas[0][1]
  Comprueba 'Delta sigue con el cambio sin commit' (Quedan-Cambios4 $E 'Delta')
  Igual 'ninguna llamada a Copilot' 0 (Llamadas-De $E.Copilot).Count
}

$Pruebas['37 bp4 t) sin javap no se puede comparar: parada otro, sin llamadas'] = {
  $E = Nuevo-Escenario4 'p4t' @('Alfa')
  $x = Fase4 $E @{ JAVA_HOME = '' } @{ JavapExe = '' }
  Igual 'la fase no deja seguir' $false $x.Sigue
  Igual 'una parada' 1 $script:Paradas.Count
  if ($script:Paradas.Count -ne 1) { return }
  Igual 'motivo otro' 'otro' $script:Paradas[0][0]
  Comprueba 'el detalle dice lo de javap' ($script:Paradas[0][1] -match 'JAVA_HOME') $script:Paradas[0][1]
  Igual 'ninguna llamada a Copilot' 0 (Llamadas-De $E.Copilot).Count
  Igual 'ninguna llamada a Maven' 0 (Llamadas-De $E.Mvn).Count
}

$Pruebas['38 bp4 u) -MaxHoras: pasado el tiempo no empieza una ronda nueva y para con tope-de-tiempo'] = {
  $E = Nuevo-Escenario4 'p4u' @('Alfa', 'Beta')
  $MaxHoras = 0.00000001
  $reloj = [System.Diagnostics.Stopwatch]::StartNew()
  Start-Sleep -Milliseconds 50
  $x = Fase4 $E @{ RESCATE_FALSO = 'codigo:Alfa' }
  Igual 'la fase no deja seguir' $false $x.Sigue
  Igual 'una parada' 1 $script:Paradas.Count
  if ($script:Paradas.Count -ne 1) { return }
  Igual 'motivo tope-de-tiempo' 'tope-de-tiempo' $script:Paradas[0][0]
  Igual 'la primera ronda si se hizo: Beta commiteada' ("$Commit4${Ruta4}Beta.java|inicial") ($x.Commits -join '|')
  Igual 'Alfa, pendiente con su primer intento' 'pendiente' (Tarea4 $x 'Alfa').estado
}

$Pruebas['39 bp4 v) sin datos/practicas-antes.json: un aviso y ninguna llamada'] = {
  $E = Nuevo-Escenario4 'p4v' @('Alfa')
  Remove-Item -LiteralPath (Join-Path $E.Datos 'practicas-antes.json') -Force
  $x = Fase4 $E
  Igual 'la fase deja seguir' $true $x.Sigue
  Comprueba 'el aviso dice que falta el JSON' (@($x.Avisos | Where-Object { $_ -match 'practicas-antes\.json' }).Count -eq 1) ($x.Avisos -join ' / ')
  Igual 'ninguna llamada a Copilot' 0 (Llamadas-De $E.Copilot).Count
}

$Pruebas['39b bp4 v2) practicas-despues.json manda sobre practicas-antes.json'] = {
  $E = Nuevo-Escenario4 'p4v2' @('Alfa', 'Beta')
  $inc = @(New-Incidencia 'lombok' "${Ruta4}Beta.java" 10 'lombok' 'getter-setter-a-mano' 'referencia' '' '2 getters y 1 setters escritos a mano: con Lombok son @Getter y @Setter')
  Write-Json (Join-Path $E.Datos 'practicas-despues.json') ([ordered]@{ version = 1; cuando = ''; detectores = @(); incidencias = $inc })
  $x = Fase4 $E
  Igual 'una sola tarea' 1 $x.Tareas.Count
  Igual 'la de Beta, que es lo que queda segun el despues' "$Commit4${Ruta4}Beta.java|inicial" ($x.Commits -join '|')
}

$Pruebas['32 bp4 m) arreglo-practicas.ps1: solo funciones, cabecera, ASCII y nada de PowerShell 7'] = {
  $ruta = Join-Path $raiz 'arreglo-practicas.ps1'
  Comprueba 'existe junto a migracion.ps1' (Test-Path -LiteralPath $ruta)
  if (-not (Test-Path -LiteralPath $ruta)) { return }
  $codigo = [System.IO.File]::ReadAllText($ruta)
  Comprueba 'empieza con su cabecera de ayuda' ($codigo.TrimStart().StartsWith('<#'))
  Comprueba 'nada de PowerShell 7 (??, ?. ni ?[)' ($codigo -notmatch '\?\?|[\w\)\]]\?\.\w|\w\?\[')
  Comprueba 'sin -AsHashtable ni ConvertFrom-Json -Depth' ($codigo -notmatch 'AsHashtable|ConvertFrom-Json[^|\r\n]*-Depth')
  $ast = [System.Management.Automation.Language.Parser]::ParseInput($codigo, [ref]$null, [ref]$null)
  $sueltas = @($ast.EndBlock.Statements | Where-Object { $_ -isnot [System.Management.Automation.Language.FunctionDefinitionAst] -and -not ($_ -is [System.Management.Automation.Language.AssignmentStatementAst] -and $_.Left.Extent.Text -ceq '$Cfg') })
  Igual 'nada fuera de las funciones y de su $Cfg' 0 $sueltas.Count
  $otras = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Name })
  $deMas = @(@('practicas.ps1', 'huella.ps1', 'comun.ps1', 'tareas.ps1', 'informe.ps1', 'lanzadores.ps1', 'migracion.ps1', 'prueba-local.ps1') | ForEach-Object {
      $f = Join-Path $raiz $_
      if (Test-Path -LiteralPath $f) { [regex]::Matches([System.IO.File]::ReadAllText($f), '(?m)^function ([\w-]+)') | ForEach-Object { $_.Groups[1].Value } }
    })
  $repetidas = @($otras | Where-Object { $deMas -contains $_ })
  Comprueba 'ninguna de sus funciones esta definida en otro script' ($repetidas.Count -eq 0) ($repetidas -join ', ')
}

# ================================ BP-6: java21-texto ================================
# El detector de texto que cambia en Java 21: juego de caracteres por defecto (JEP 400) y formatos de fecha y numero (CLDR). Sin Maven: lee los
# .java de src/main/java. Cada linea que tiene que dar una incidencia acaba en '// X' (el detector no mira los comentarios).
$Fuente6Charset = @'
package com.acme.texto;

import java.io.*;

public class Entrada {
    void abre(String ruta, File fichero, InputStream entrada, OutputStream salida) throws Exception {
        Reader a = new FileReader(ruta); // X
        Reader b = new FileReader(fichero); // X
        Writer c = new FileWriter(ruta); // X
        Writer d = new FileWriter(fichero, true); // X
        Reader e = new InputStreamReader(entrada); // X
        Writer f = new OutputStreamWriter(salida); // X
        PrintWriter g = new PrintWriter(fichero); // X
        PrintWriter h = new PrintWriter("salida.txt"); // X
        PrintStream i = new PrintStream(new File(ruta)); // X
        PrintStream j = new PrintStream(ruta); // X
        byte[] k = ruta.getBytes(); // X
        Writer m = new FileWriter( // X
                fichero,
                true);
        BufferedReader n = new BufferedReader(new FileReader(ruta)); // X
        byte[] o = new FileReader(ruta).toString().getBytes(); // X
        Reader p = new InputStreamReader(abrir(ruta, fichero)); // X
        Reader q = new FileReader("a,b.txt"); // X
        Reader r = new FileReader("a)b(c.txt"); // X
        System.out.println(new String(k));
    }
}
'@

$Fuente6Explicito = @'
package com.acme.texto;

import java.io.*;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;

public class Explicito {
    void abre(String ruta, File fichero, InputStream entrada, OutputStream salida, Charset charset, Charset juegoCharset) throws Exception {
        Reader a = new FileReader(ruta, StandardCharsets.UTF_8);
        Reader b = new FileReader(fichero, Charset.forName("ISO-8859-1"));
        Writer c = new FileWriter(ruta, StandardCharsets.UTF_8);
        Writer d = new FileWriter(fichero, charset, true);
        Writer e = new FileWriter(fichero, juegoCharset);
        Writer f = new FileWriter(
                fichero,
                StandardCharsets.UTF_8);
        Reader g = new InputStreamReader(entrada, StandardCharsets.UTF_8);
        Reader h = new InputStreamReader(entrada, "UTF-8");
        Writer i = new OutputStreamWriter(salida, StandardCharsets.UTF_8);
        PrintWriter j = new PrintWriter(fichero, "UTF-8");
        PrintWriter k = new PrintWriter(fichero, StandardCharsets.UTF_8);
        PrintStream m = new PrintStream(ruta, "UTF-8");
        PrintWriter r = new PrintWriter(writer);
        PrintWriter s = new PrintWriter(fileWriter);
        PrintStream t = new PrintStream(System.out);
        byte[] n = ruta.getBytes(StandardCharsets.UTF_8);
        byte[] o = ruta.getBytes("UTF-8");
        BufferedReader p = Files.newBufferedReader(fichero.toPath());
        java.util.List<String> q = Files.readAllLines(fichero.toPath());
    }
}
'@

$Fuente6Comentarios = @'
package com.acme.texto;

// Reader a = new FileReader(ruta);
/* byte[] b = texto.getBytes(); */
/*
 * Writer c = new FileWriter(ruta);
 * new InputStreamReader(entrada);
 */
public class Comentado {
    /** Antes: new OutputStreamWriter(salida), new PrintWriter(fichero) y NumberFormat.getInstance(). */
    void abre(String ruta) throws Exception {
        String url = "http://acme.example/ruta"; byte[] k = url.getBytes(); // X
        String dos = "/* no es un comentario */"; Object o = new FileReader(ruta); // X
        String ayuda = "No uses new FileReader(ruta) ni ruta.getBytes() ni NumberFormat.getInstance() ni new SimpleDateFormat(\"MMM\")";
        String bloque = """
            // new FileWriter(ruta)
            ruta.getBytes() y new DecimalFormat("0.00")
            """;
        Reader a = null; // new FileReader(ruta)
        // SimpleDateFormat f = new SimpleDateFormat("dd-MMM-yyyy");
        Reader b = null; /* new FileReader(ruta) */ Reader c = new FileReader(ruta); // X
    }
}
'@

$Fuente6FlatCon = @'
package com.acme.texto;

public class LectorCon {
    FlatFileItemReader<Remesa> lector() {
        return new FlatFileItemReaderBuilder<Remesa>()
                .name("lector")
                .encoding("ISO-8859-1")
                .resource(recurso)
                .build();
    }

    FlatFileItemWriter<Remesa> escritor() {
        FlatFileItemWriter<Remesa> w = new FlatFileItemWriter<>();
        w.setEncoding("ISO-8859-1");
        return w;
    }
}
'@

$Fuente6FlatSet = @'
package com.acme.texto;

public class LectorSet {
    FlatFileItemReader<Remesa> lector() {
        FlatFileItemReader<Remesa> reader = new FlatFileItemReader<>();
        reader.setEncoding("ISO-8859-1");
        return reader;
    }
}
'@

$Fuente6FlatSin = @'
package com.acme.texto;

public class LectorSin {
    // el juego de caracteres: .encoding("ISO-8859-1") o setEncoding(...)
    FlatFileItemReader<Remesa> lector() {
        return new FlatFileItemReaderBuilder<Remesa>() // X
                .name("lector")
                .resource(recurso)
                .build();
    }

    FlatFileItemWriter<Remesa> escritor() {
        FlatFileItemWriter<Remesa> w = new FlatFileItemWriter<>(); // X
        return w;
    }

    FlatFileItemReader<Remesa> viejo() {
        return new FlatFileItemReader<>(); // X
    }

    FlatFileItemWriterBuilder<Remesa> constructor;
}
'@

$Fuente6Formatos = @'
package com.acme.texto;

public class Formatos {
    void formatea(java.util.Locale locale) {
        SimpleDateFormat a = new SimpleDateFormat("dd-MMM-yyyy"); // X
        SimpleDateFormat b = new SimpleDateFormat("EEE dd/MM/yyyy", locale); // X
        DateTimeFormatter c = DateTimeFormatter.ofPattern("dd MMMM yyyy"); // X
        NumberFormat d = NumberFormat.getInstance(); // X
        NumberFormat e = NumberFormat.getCurrencyInstance(locale); // X
        DecimalFormat f = new DecimalFormat("#,##0.00"); // X
        SimpleDateFormat g = new SimpleDateFormat("dd/MM/yyyy");
        DateTimeFormatter h = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm");
        DateTimeFormatter i = DateTimeFormatter.ofPattern(PATRON);
        SimpleDateFormat j = new SimpleDateFormat( // X
                "dd-MMM-yyyy");
    }
}
'@

$Dir6 = 'src/main/java/com/acme/texto/'
$Texto6Charset = 'Usa el juego de caracteres por defecto. En Java 8 era el del servidor; desde Java 18 es UTF-8. Si el fichero no es UTF-8 (n con tilde, acentos), sale distinto. Pon el juego de caracteres de forma explicita, o lanza con -Dfile.encoding=COMPAT mientras lo decidis.'
$Texto6Cldr = 'Desde Java 9 los nombres de mes y dia y los separadores de numeros salen de CLDR y pueden cambiar. Comprueba la salida, o lanza con -Djava.locale.providers=COMPAT.'

# Los numeros de linea de un texto cuya linea acaba en '// X': donde el detector tiene que dar una incidencia.
function Marcadas6([string]$Fuente) {
  $r = @()
  $n = 0
  foreach ($l in ($Fuente -split "`n")) { $n++; if ($l -match '// X\s*$') { $r += $n } }
  return ($r -join ',')
}

# Las lineas (ordenadas) de las incidencias de java21-texto de un fichero y una regla.
function Lineas6($J, [string]$Fichero, [string]$Regla) {
  return (@($J.incidencias | Where-Object { $_.herramienta -ceq 'java21-texto' -and $_.fichero -ceq $Fichero -and $_.regla -ceq $Regla } | ForEach-Object { [int]$_.linea } | Sort-Object) -join ',')
}

# Un escenario con el .java de cada nombre del diccionario en src/main/java/com/acme/texto/ y, medido, el JSON que deja.
function Mide6([string]$Nombre, [hashtable]$Fuentes) {
  $E = Nuevo-Escenario $Nombre
  foreach ($k in $Fuentes.Keys) { Escribe $E.Repo "$Dir6$k.java" $Fuentes[$k] }
  return [pscustomobject]@{ E = $E; Json = (Mide $E @{}).Json }
}

# Monta las paginas con un practicas-antes.json (el que se da) y devuelve la 5.
function Pagina5-De6([string]$Nombre, $Json) {
  $s = Join-Path (Join-Path $Dir $Nombre) 'migracion-batch-recibos'
  [void](New-Item -ItemType Directory -Path (Join-Path $s 'datos') -Force)
  [System.IO.File]::WriteAllText((Join-Path $s 'datos/estado.json'), '{"batch":"batch-recibos","legacy":"acme/recibos-java8","migrado":"acme/batch-recibos","plantilla":"acme/batch-referencia","modelo":"modelo-x","creado":"2026-11-19T10:00:00","actualizado":"2026-11-19T11:00:00","fase":"hecha","respuesta":"parar"}')
  [System.IO.File]::WriteAllText((Join-Path $s 'datos/practicas-antes.json'), (ConvertTo-Json -InputObject $Json -Depth 8))
  $cab = "`$ErrorActionPreference = 'Stop'`n. '" + (Join-Path $raiz 'comun.ps1') + "'`n. '" + (Join-Path $raiz 'tareas.ps1') + "'`n"
  if (Test-Path -LiteralPath (Join-Path $raiz 'lanzadores.ps1')) { $cab += ". '" + (Join-Path $raiz 'lanzadores.ps1') + "'`n" }
  $cab += ". '" + (Join-Path $raiz 'informe.ps1') + "'`nWrite-Informes -Salida '" + $s + "'`n'INFORMES-OK'`n"
  Escribe (Join-Path $Dir $Nombre) 'informes.ps1' $cab
  $g = Lanzar (Join-Path (Join-Path $Dir $Nombre) 'informes.ps1') @()
  Comprueba "$Nombre : Write-Informes sale bien" ($g.Codigo -eq 0 -and $g.Salida -match 'INFORMES-OK') (Cola $g.Salida)
  $p5 = Join-Path $s '5-buenas-practicas.html'
  if (-not (Test-Path -LiteralPath $p5)) { return '' }
  return [System.IO.File]::ReadAllText($p5, (New-Object System.Text.UTF8Encoding($false)))
}

$Pruebas['40 bp6 a) charset-por-defecto: cada patron da una incidencia en su fichero y su linea (una por linea) y con el texto del contrato'] = {
  $x = Mide6 'bp6a' @{ Entrada = $Fuente6Charset }
  $fich = "${Dir6}Entrada.java"
  Igual 'las lineas con un patron (la anidada y la de dos patrones, una incidencia cada una)' (Marcadas6 $Fuente6Charset) (Lineas6 $x.Json $fich 'charset-por-defecto')
  Igual 'ninguna incidencia mas de java21-texto en ese fichero (la de limpieza que le sale a Entrada, clase-sin-uso, es de otro detector)' (Marcadas6 $Fuente6Charset).Split(',').Count @($x.Json.incidencias | Where-Object { $_.fichero -ceq $fich -and $_.herramienta -ceq 'java21-texto' }).Count
  $i = @($x.Json.incidencias | Where-Object { $_.herramienta -ceq 'java21-texto' })[0]
  Comprueba 'hay una incidencia de java21-texto' ($null -ne $i)
  if ($null -eq $i) { return }
  Igual 'area' 'java21' $i.area
  Igual 'regla' 'charset-por-defecto' $i.regla
  Igual 'origen: S1943 no esta en Sonar way, asi que referencia' 'referencia' $i.origen
  Igual 'sonar vacio' '' $i.sonar
  Igual 'queHago' 'mano' $i.queHago
  Igual 'fichero con /' $fich $i.fichero
  Igual 'texto del contrato' $Texto6Charset $i.texto
}

$Pruebas['41 bp6 b) charset-por-defecto: con juego de caracteres (StandardCharsets, Charset.forName, una variable ...charset) y con Files.* no salta nada'] = {
  $x = Mide6 'bp6b' @{ Explicito = $Fuente6Explicito }
  Igual 'java21-texto: ok' 'ok' (Det $x.Json 'java21-texto').estado
  Igual 'ninguna incidencia de java21-texto' 0 (Inc $x.Json 'java21-texto').Count
}

$Pruebas['42 bp6 c) un patron dentro de un comentario (// y /* */), de una cadena o de un bloque de texto no salta; las cadenas con // o /* no se toman por comentario y las lineas no se corren'] = {
  $x = Mide6 'bp6c' @{ Comentado = $Fuente6Comentarios }
  Igual 'solo las lineas con codigo (4 patrones en comentarios y un SimpleDateFormat comentado no cuentan)' (Marcadas6 $Fuente6Comentarios) (Lineas6 $x.Json "${Dir6}Comentado.java" 'charset-por-defecto')
  Igual 'ni charset ni formato en los comentarios: tres incidencias' 3 (Inc $x.Json 'java21-texto').Count
}

$Pruebas['43 bp6 d) FlatFileItemReader y Writer (y sus Builder): con .encoding( o con solo setEncoding( en el fichero no saltan; sin el, si, y un .encoding( en un comentario no cuenta'] = {
  $x = Mide6 'bp6d' @{ LectorCon = $Fuente6FlatCon; LectorSet = $Fuente6FlatSet; LectorSin = $Fuente6FlatSin }
  Igual 'con encoding: ninguna' '' (Lineas6 $x.Json "${Dir6}LectorCon.java" 'charset-por-defecto')
  Igual 'con solo setEncoding (sin .encoding): ninguna' '' (Lineas6 $x.Json "${Dir6}LectorSet.java" 'charset-por-defecto')
  Igual 'sin encoding: el Builder, el Writer y el Reader (no la declaracion de un campo)' (Marcadas6 $Fuente6FlatSin) (Lineas6 $x.Json "${Dir6}LectorSin.java" 'charset-por-defecto')
}

$Pruebas['44 bp6 e) formato-cldr: MMM y EEE en el patron literal salen; dd/MM/yyyy y un patron que no es literal, no; NumberFormat.get y new DecimalFormat salen siempre'] = {
  $x = Mide6 'bp6e' @{ Formatos = $Fuente6Formatos }
  $fich = "${Dir6}Formatos.java"
  Igual 'las lineas marcadas' (Marcadas6 $Fuente6Formatos) (Lineas6 $x.Json $fich 'formato-cldr')
  Igual 'ninguna es de charset' '' (Lineas6 $x.Json $fich 'charset-por-defecto')
  $i = @($x.Json.incidencias | Where-Object { $_.regla -ceq 'formato-cldr' })[0]
  Comprueba 'hay una de formato-cldr' ($null -ne $i)
  if ($null -eq $i) { return }
  Igual 'area' 'java21' $i.area
  Igual 'origen' 'referencia' $i.origen
  Igual 'queHago' 'mano' $i.queHago
  Igual 'texto del contrato' $Texto6Cldr $i.texto
}

$Pruebas['45 bp6 f) en el JSON: java21-texto va en detectores con estado ok y sus incidencias llevan el area java21 y su herramienta'] = {
  $x = Mide6 'bp6f' @{ Entrada = $Fuente6Charset; Formatos = $Fuente6Formatos }
  $j = $x.Json
  Igual 'los detectores, en orden' 'javac,lombok-a-mano,lombok-qualifier,java21-texto,limpieza' ((@($j.detectores | ForEach-Object { $_.id })) -join ',')
  $d = Det $j 'java21-texto'
  Igual 'estado ok' 'ok' $d.estado
  Igual 'motivo vacio' '' $d.motivo
  Igual 'sin corte' $false $d.corte
  Igual 'los campos de un detector' 'id,estado,motivo,segundos,corte' ($d.PSObject.Properties.Name -join ',')
  $mias = Inc $j 'java21-texto'
  Comprueba 'hay incidencias de java21-texto' ($mias.Count -gt 0)
  Igual 'todas del area java21' 0 @($mias | Where-Object { $_.area -cne 'java21' }).Count
  Igual 'todas con sus nueve campos' 0 @($mias | Where-Object { -not ($_.PSObject.Properties.Name -join ',' -ceq 'area,fichero,linea,herramienta,regla,origen,sonar,texto,queHago') }).Count
  Igual 'las reglas son las dos del contrato' 'charset-por-defecto,formato-cldr' ((@($mias | ForEach-Object { $_.regla } | Sort-Object -Unique)) -join ',')
  Comprueba-Formato $j $x.E
}

$Pruebas['46 bp6 g) la pagina 5 con ese JSON lleva las incidencias de java21-texto y el detector en la linea de los que midieron'] = {
  $x = Mide6 'bp6g' @{ Entrada = $Fuente6Charset; Formatos = $Fuente6Formatos }
  $mias = Inc $x.Json 'java21-texto'
  $h = Pagina5-De6 'bp6g-pagina' $x.Json
  Comprueba 'monta 5-buenas-practicas.html' ($h.Length -gt 0)
  if ($h.Length -eq 0) { return }
  Comprueba 'la linea Midieron lleva java21-texto' ($h -match '(?s)<dt>Midieron</dt>.*?<li>java21-texto</li>.*?</dl>')
  Igual 'cada incidencia sale en las dos vistas: charset-por-defecto' (2 * @($mias | Where-Object { $_.regla -ceq 'charset-por-defecto' }).Count) ([regex]::Matches($h, 'java21-texto charset-por-defecto').Count)
  Igual 'cada incidencia sale en las dos vistas: formato-cldr' (2 * @($mias | Where-Object { $_.regla -ceq 'formato-cldr' }).Count) ([regex]::Matches($h, 'java21-texto formato-cldr').Count)
  Comprueba 'lleva el texto de charset' ($h.Contains('Usa el juego de caracteres por defecto.'))
  Comprueba 'lleva el area Java 21' ($h.Contains('Java 21'))
  Comprueba 'la explicacion del area Java 21 nombra el detector de texto' ($h.Contains('un detector de texto que avisa de lo que cambia en Java 21'))
  Comprueba 'y no esta entre las notas de los que no midieron' ($h -notmatch '<code>java21-texto</code> <b>')
}

$Pruebas['47 bp6 h) sin src/main/java: java21-texto no aplica con su motivo y la pagina 5 lo dice en sus notas de detectores'] = {
  $E = Nuevo-Escenario 'bp6h'
  Remove-Item -LiteralPath (Get-Ruta $E.Repo 'src/main/java') -Recurse -Force
  $m = Mide $E @{}
  $d = Det $m.Json 'java21-texto'
  Igual 'estado' 'no aplica' $d.estado
  Igual 'motivo' 'no hay src/main/java' $d.motivo
  Igual 'sin incidencias' 0 (Inc $m.Json 'java21-texto').Count
  Igual 'ningun Aviso (no aplica no es un fallo)' 0 @($m.Avisos | Where-Object { $_ -like '*java21-texto*' }).Count
  $h = Pagina5-De6 'bp6h-pagina' $m.Json
  Comprueba 'la pagina dice java21-texto no aplica y por que' ($h -match '(?s)<code>java21-texto</code> <b>no aplica</b>: no hay src/main/java')
}

$Pruebas['48 bp6 i) una llamada sin cerrar (new FileWriter( sin ) ) no da incidencia ni para el detector: los demas ficheros dan las suyas'] = {
  $x = Mide6 'bp6i' @{ Entrada = $Fuente6Charset; Roto = "package com.acme.texto;`nclass Roto { Object a = new FileWriter(`n" }
  Igual 'estado ok' 'ok' (Det $x.Json 'java21-texto').estado
  Igual 'las del fichero bueno estan' (Marcadas6 $Fuente6Charset) (Lineas6 $x.Json "${Dir6}Entrada.java" 'charset-por-defecto')
  Igual 'el que no cierra el parentesis no da incidencia' '' (Lineas6 $x.Json "${Dir6}Roto.java" 'charset-por-defecto')
}

$Pruebas['49 bp6 j) ninguna funcion de practicas.ps1 esta definida tambien en otro script de la raiz (migracion.ps1 los carga todos juntos y la ultima pisaria a la otra)'] = {
  $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $raiz 'practicas.ps1'), [ref]$null, [ref]$null)
  $suyas = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Name })
  $deMas = @(Get-ChildItem -LiteralPath $raiz -File -Filter '*.ps1' | Where-Object { $_.Name -cne 'practicas.ps1' } | ForEach-Object {
      [regex]::Matches([System.IO.File]::ReadAllText($_.FullName), '(?m)^function ([\w-]+)') | ForEach-Object { $_.Groups[1].Value }
    })
  $repetidas = @($suyas | Where-Object { $deMas -contains $_ })
  Comprueba 'practicas.ps1 define funciones' ($suyas.Count -gt 0)
  Comprueba 'ninguna esta repetida en otro .ps1 de la raiz' ($repetidas.Count -eq 0) ($repetidas -join ', ')
}

$Pruebas['50 bp6 k) solo se lee src/main/java: el mismo codigo en src/test/java no da incidencias'] = {
  $E = Nuevo-Escenario 'bp6k'
  Escribe $E.Repo "${Dir6}Entrada.java" $Fuente6Charset
  Escribe $E.Repo 'src/test/java/com/acme/texto/EntradaTest.java' $Fuente6Charset
  Escribe $E.Repo 'src/test/java/com/acme/texto/FormatosTest.java' $Fuente6Formatos
  $j = (Mide $E @{}).Json
  Igual 'estado ok' 'ok' (Det $j 'java21-texto').estado
  Igual 'las de src/main/java estan' (Marcadas6 $Fuente6Charset) (Lineas6 $j "${Dir6}Entrada.java" 'charset-por-defecto')
  Igual 'ninguna en src/test/java' 0 @($j.incidencias | Where-Object { $_.herramienta -ceq 'java21-texto' -and $_.fichero -like 'src/test/*' }).Count
}

# ================================ C1: limpieza ================================
# El detector de lo que no deberia llegar al senior: restos de herramientas en git, marcas pendientes, codigo comentado y clases que nadie usa.
# Sin Maven. Solo avisa. Los ficheros de $EnGit van a un commit (los de $SinGit se quedan sin seguir).
$DirC1 = 'src/main/java/com/acme/limpio/'
$FinC1 = 'quitalo de git y anadelo a .gitignore.'

function Mide-C1([string]$Nombre, [hashtable]$EnGit, [hashtable]$SinGit = @{}) {
  $E = Nuevo-Escenario $Nombre
  foreach ($k in $EnGit.Keys) { Escribe $E.Repo $k $EnGit[$k]; [void](GitEn $E.Repo @('add', '-f', '--', $k)) }
  if ($EnGit.Count -gt 0) { [void](GitEn $E.Repo @('commit', '-q', '-m', 'c1')) }
  foreach ($k in $SinGit.Keys) { Escribe $E.Repo $k $SinGit[$k] }
  return [pscustomobject]@{ E = $E; Json = (Mide $E @{}).Json }
}

# Las incidencias de limpieza de una regla (la regla vacia: todas).
function Limpieza-De($J, [string]$Regla = '') {
  return , @($J.incidencias | Where-Object { $_.herramienta -ceq 'limpieza' -and ($Regla -ceq '' -or $_.regla -ceq $Regla) })
}

# Los ficheros de unas incidencias, ordenados y juntos (para no depender del orden en que salen).
function Ficheros-C1($Incs) { return ((@($Incs | ForEach-Object { $_.fichero }) | Sort-Object) -join '|') }

$Pruebas['51 c1 a) resto-herramienta: una incidencia por carpeta (target/ y .github/modernize/) y una por fichero, solo de lo que esta en git, con linea 0 y el texto del contrato'] = {
  $x = Mide-C1 'c1a' @{
    'notas.bak' = "x`n"
    'target/classes/A.class' = "x`n"
    'target/classes/B.class' = "x`n"
    '.github/modernize/app/plan.md' = "plan`n"
    'src/main/java/com/acme/Foo.java.orig' = "x`n"
  } @{ 'otro.bak' = "x`n" }
  $r = Limpieza-De $x.Json 'resto-herramienta'
  Igual 'cuatro incidencias: dos carpetas y dos ficheros (otro.bak no esta en git)' 4 $r.Count
  Igual 'cuales' ((@('target/', '.github/modernize/', 'notas.bak', 'src/main/java/com/acme/Foo.java.orig') | Sort-Object) -join '|') (Ficheros-C1 $r)
  Igual 'todas con linea 0' 0 @($r | Where-Object { [int]$_.linea -ne 0 }).Count
  Igual 'todas del area limpieza' 0 @($r | Where-Object { $_.area -cne 'limpieza' }).Count
  Igual 'origen referencia, sin clave de Sonar y queHago mano' 0 @($r | Where-Object { $_.origen -cne 'referencia' -or $_.sonar -cne '' -or $_.queHago -cne 'mano' }).Count
  $t = @($r | Where-Object { $_.fichero -ceq 'target/' })[0]
  Igual 'texto de la carpeta target/ (2 ficheros, un resto de Maven)' "2 ficheros de target/ estan en git: es un resto de Maven. Si no hace falta, $FinC1" $t.texto
  $m = @($r | Where-Object { $_.fichero -ceq '.github/modernize/' })[0]
  Igual 'texto de la carpeta de Copilot (1 fichero)' "1 fichero de .github/modernize/ esta en git: es un resto de Copilot. Si no hace falta, $FinC1" $m.texto
  $b = @($r | Where-Object { $_.fichero -ceq 'notas.bak' })[0]
  Igual 'texto de un fichero: un resto de un parche' "Esta en git y es un resto de un parche. Si no hace falta, $FinC1" $b.texto
}

$Pruebas['52 c1 a2) resto-herramienta: cada patron de la lista (Maven, IDE, parches, migracion y Copilot) sale y lo que puede estar a proposito (jar, zip, war, wrapper) no'] = {
  $deFichero = @('hs_err_pid42', 'replay_pid7', 'pom.xml.tag', 'pom.xml.releaseBackup', 'pom.xml.versionsBackup', 'pom.xml.next', 'release.properties',
    'dependency-reduced-pom.xml', 'buildNumber.properties', '.mvn/timing.properties', 'app.log', 'x.class', '.project', '.classpath', 'x.iml', 'x.bak', 'x.orig', 'x.rej', 'sub/mod/hs_err_pid9.log')
  $deCarpeta = @('target/', '.settings/', '.idea/', '.vscode/', 'migracion-batch-recibos/', '.rescate/', 'mod/target/', 'a/b/.idea/')
  $en = @{}
  foreach ($f in $deFichero) { $en[$f] = "x`n" }
  foreach ($c in $deCarpeta) { $en[$c + 'uno.txt'] = "x`n"; $en[$c + 'dos/tres.txt'] = "x`n" }
  $noSalen = @('pom.xml', '.mvn/wrapper/maven-wrapper.jar', '.mvn/wrapper/maven-wrapper.properties', 'libs/foo.jar', 'dist/foo.zip', 'dist/foo.war', 'src/main/resources/application.properties',
    'src/main/java/com/acme/Target.java', 'mytarget/x.txt', 'docs/migracion.md', '.github/workflows/ci.yml', 'release.properties.md', 'x.classes')
  foreach ($f in $noSalen) { $en[$f] = "x`n" }
  $x = Mide-C1 'c1a2' $en
  $r = Limpieza-De $x.Json 'resto-herramienta'
  Igual 'salen los patrones de fichero y de carpeta, y nada mas' ((@($deFichero) + @($deCarpeta) | Sort-Object) -join '|') (Ficheros-C1 $r)
  $o = @{}
  foreach ($i in $r) { $o[$i.fichero] = $i.texto -replace '^.*es un resto de (.*?)\. Si no.*$', '$1' }
  Igual 'el origen de target/' 'Maven' $o['target/']
  Igual 'el origen de .idea/' 'el IDE' $o['.idea/']
  Igual 'el origen de migracion-*/' 'la migracion' $o['migracion-batch-recibos/']
  Igual 'el origen de .rescate/' 'la migracion' $o['.rescate/']
  Igual 'la carpeta que cuelga de otra (mod/target/) cuenta en su sitio, con sus 2 ficheros' '2 ficheros de mod/target/ estan en git' (($r | Where-Object { $_.fichero -ceq 'mod/target/' }).texto -replace '^(.*?estan en git).*$', '$1')
}

$Pruebas['53 c1 b) tests-entrega: PruebaLocalTest y los casos de prueba-local dan UNA incidencia con el primer fichero, linea 0, y no son resto-herramienta'] = {
  $x = Mide-C1 'c1b' @{
    'src/test/java/com/acme/PruebaLocalTest.java' = "package com.acme;`nclass PruebaLocalTest { }`n"
    'src/test/java/com/acme/RegresionLocalTest.java' = "package com.acme;`nclass RegresionLocalTest { }`n"
    'src/test/resources/prueba-local/job/caso/entrada.csv' = "a;b`n"
    'src/test/resources/prueba-local-esperado/job/caso/salida.log' = "ok`n"
  }
  $r = Limpieza-De $x.Json 'tests-entrega'
  Igual 'una sola incidencia' 1 $r.Count
  if ($r.Count -eq 1) {
    Igual 'con el primero de esos ficheros' 'src/test/java/com/acme/PruebaLocalTest.java' $r[0].fichero
    Igual 'linea 0' 0 ([int]$r[0].linea)
    Igual 'texto del contrato' 'Tests de entrega de la prueba en local (-Regresion): no son un resto, pero decide con tu equipo si se quedan en el repo.' $r[0].texto
    Igual 'area limpieza y origen referencia' 'limpieza referencia' "$($r[0].area) $($r[0].origen)"
  }
  Igual 'ninguna resto-herramienta por ellos (ni por el .log de un caso)' 0 (Limpieza-De $x.Json 'resto-herramienta').Count
  # solo los casos, sin los tests: tambien sale, con el primer caso
  $y = Mide-C1 'c1b2' @{ 'src/test/resources/prueba-local/job/caso/entrada.csv' = "a;b`n" }
  Igual 'solo los casos: una incidencia con el caso' 'src/test/resources/prueba-local/job/caso/entrada.csv' ((Limpieza-De $y.Json 'tests-entrega') | ForEach-Object { $_.fichero })
  $z = Mide-C1 'c1b3' @{ 'src/test/java/com/acme/OtroTest.java' = "package com.acme;`nclass OtroTest { }`n" }
  Igual 'un test cualquiera no es de entrega' 0 (Limpieza-De $z.Json 'tests-entrega').Count
}

$Pruebas['54 c1 c) marca-pendiente: TODO, FIXME y XXX en mayusculas y palabra entera, en src/main, una incidencia por linea; todos, TODOS y todo no, ni src/test, ni target, ni otras extensiones'] = {
  $x = Mide-C1 'c1c' @{
    'src/main/java/com/acme/Marcas.java' = "package com.acme;`npublic class Marcas {`n    // TODO migracion`n    // todo en minusculas`n    int a; // TODOS los dias`n    // XXX revisar`n    // FIXME y TODO en la misma linea`n    int b = 1;`n}`n"
    'src/main/resources/application.yml' = "a: 1`n# FIXME ajustar`n# TODOS los dias`nb: 2`n"
    'src/main/resources/leeme.txt' = "TODO esto no se mira`n"
    'src/main/resources/db/datos.sql' = "-- TODO borrar`nselect 1;`n"
    'src/test/java/com/acme/MarcasTest.java' = "package com.acme;`n// TODO en un test`nclass MarcasTest { }`n"
    'target/classes/application.yml' = "# TODO copia en target`n"
  }
  $r = Limpieza-De $x.Json 'marca-pendiente'
  $de = @{}
  foreach ($i in $r) { $de[$i.fichero + ':' + $i.linea] = $i }
  Igual 'las lineas que saltan' ((@('src/main/java/com/acme/Marcas.java:3', 'src/main/java/com/acme/Marcas.java:6', 'src/main/java/com/acme/Marcas.java:7', 'src/main/resources/application.yml:2', 'src/main/resources/db/datos.sql:1') | Sort-Object) -join '|') ((@($de.Keys) | Sort-Object) -join '|')
  $j = $de['src/main/java/com/acme/Marcas.java:3']
  if ($null -ne $j) {
    Igual 'texto: la linea recortada' 'Marca pendiente: // TODO migracion' $j.texto
    Igual 'un TODO de un .java lleva la regla de Sonar S1135 (esta en Sonar way)' 'sonar S1135' "$($j.origen) $($j.sonar)"
    Igual 'area y queHago' 'limpieza sonar' "$($j.area) $($j.queHago)"
  }
  Igual 'un FIXME de un .java lleva S1134' 'sonar S1134' "$($de['src/main/java/com/acme/Marcas.java:7'].origen) $($de['src/main/java/com/acme/Marcas.java:7'].sonar)"
  Igual 'un XXX no tiene regla de Sonar: referencia' 'referencia ' "$($de['src/main/java/com/acme/Marcas.java:6'].origen) $($de['src/main/java/com/acme/Marcas.java:6'].sonar)"
  Igual 'un FIXME de un .yml: Sonar no lo mira, referencia' 'referencia  Marca pendiente: # FIXME ajustar' "$($de['src/main/resources/application.yml:2'].origen) $($de['src/main/resources/application.yml:2'].sonar) $($de['src/main/resources/application.yml:2'].texto)"
}

$Pruebas['55 c1 d) codigo-comentado: 3 o mas lineas seguidas con // y al menos 2 que acaban en ; { o } dan una incidencia en la primera; la prosa, dos lineas, un Javadoc y un /* */ no'] = {
  $f = @'
package com.acme;

public class Comentado {
    void a() {
        // foo();
        // if (x) {
        // }
        int y = 0;
        // esto es prosa
        // que sigue siendo prosa
        // y acaba sin nada especial
        int z = 0;
        // uno();
        // dos();
        int w = 0;
        // ajuste: ver el documento
        // una linea mas de prosa
        // llamada();
        int v = 0;
        /**
         * foo();
         * bar();
         * baz();
         */
        /* y();
           z(); */
    }
}
'@
  $x = Mide-C1 'c1d' @{ 'src/main/java/com/acme/Comentado.java' = $f }
  $r = Limpieza-De $x.Json 'codigo-comentado'
  Igual 'una incidencia, en la primera linea del tramo (la 5)' 'src/main/java/com/acme/Comentado.java:5' (($r | ForEach-Object { $_.fichero + ':' + $_.linea }) -join '|')
  if ($r.Count -eq 1) {
    Igual 'texto con el numero de lineas' '3 lineas de codigo comentado: si ya no hace falta, borralas (git lo guarda).' $r[0].texto
    Igual 'area, origen y clave de Sonar (S125 esta en Sonar way)' 'limpieza sonar S125' "$($r[0].area) $($r[0].origen) $($r[0].sonar)"
    Igual 'queHago' 'sonar' $r[0].queHago
  }
  # los .java de src/test no se miran
  $y = Mide-C1 'c1d2' @{ 'src/test/java/com/acme/ComentadoTest.java' = $f }
  Igual 'en src/test no se mira' 0 (Limpieza-De $y.Json 'codigo-comentado').Count
}

$Pruebas['56 c1 e) clase-sin-uso: la que nadie nombra en src/main es candidata (tambien la que solo usa un test, solo sale en un comentario o solo se parece a una variable con otra mayuscula); la nombrada, con una anotacion de Spring, en un .imports o un .yml, o con main, no'] = {
  $p = 'package com.acme.limpio;'
  $en = @{
    "${DirC1}LegacyDateUtils.java" = "$p`n`npublic class LegacyDateUtils {`n    public static String hoy() { return `"x`"; }`n}`n"
    "${DirC1}Principal.java" = "$p`n`n/** Arranca y usa Usada. */`npublic class Principal {`n    // EnComentario solo sale aqui, en un comentario`n    String legacyDateUtils = `"mismo nombre con otra mayuscula`";`n    public static void main(String[] args) {`n        System.out.println(new Usada().nombre());`n    }`n}`n"
    "${DirC1}Usada.java" = "$p`n`npublic class Usada {`n    public String nombre() { return `"u`"; }`n}`n"
    "${DirC1}EnComentario.java" = "$p`n`n/**`n * Una clase que nadie usa.`n */`npublic class EnComentario { }`n"
    "${DirC1}SoloTest.java" = "$p`n`npublic class SoloTest { }`n"
    "${DirC1}Registrada.java" = "$p`n`npublic class Registrada { }`n"
    "${DirC1}EnYml.java" = "$p`n`npublic class EnYml { }`n"
    "${DirC1}ConMain.java" = "$p`n`npublic class ConMain {`n    public static void main(String[] args) { }`n}`n"
    "${DirC1}package-info.java" = "$p`n"
    'src/main/resources/META-INF/spring/x.imports' = "com.acme.limpio.Registrada`n"
    'src/main/resources/application.yml' = "batch:`n  clase: com.acme.limpio.EnYml`n"
    'src/test/java/com/acme/limpio/SoloTestTest.java' = "$p`n`nclass SoloTestTest {`n    SoloTest t = new SoloTest();`n}`n"
  }
  foreach ($a in @('Configuration', 'AutoConfiguration', 'Component', 'Service', 'Repository', 'Controller', 'RestController', 'SpringBootApplication', 'ConfigurationProperties', 'EnableBatchProcessing')) {
    $en["${DirC1}Con$a.java"] = "$p`n`n@$a`npublic class Con$a { }`n"
  }
  $x = Mide-C1 'c1e' $en
  $todas = Limpieza-De $x.Json 'clase-sin-uso'
  $r = @($todas | Where-Object { $_.fichero -like "$DirC1*" })
  Igual 'las candidatas' ((@('EnComentario', 'LegacyDateUtils', 'SoloTest') | ForEach-Object { "$DirC1$_.java" } | Sort-Object) -join '|') (Ficheros-C1 $r)
  $l = @($r | Where-Object { $_.fichero -ceq "${DirC1}LegacyDateUtils.java" })[0]
  if ($null -ne $l) {
    Igual 'la linea es la de la declaracion de la clase (3)' 3 ([int]$l.linea)
    Igual 'texto del contrato' 'Nadie la nombra en src/main y no la carga Spring: puede ser codigo muerto (si solo la usan los tests, tambien). Comprueba antes de borrarla.' $l.texto
    Igual 'area, origen, sin Sonar y queHago' 'limpieza referencia  mano' "$($l.area) $($l.origen) $($l.sonar) $($l.queHago)"
  }
  Igual 'con un Javadoc encima, la linea es la de class (6)' 6 ([int]@($r | Where-Object { $_.fichero -ceq "${DirC1}EnComentario.java" })[0].linea)
}

$Pruebas['57 c1 f) en el JSON: limpieza va el ultimo de detectores, con estado ok, y sus incidencias llevan el area limpieza, la herramienta limpieza y sus nueve campos'] = {
  $x = Mide-C1 'c1f' @{
    'notas.bak' = "x`n"
    "${DirC1}LegacyDateUtils.java" = "package com.acme.limpio;`n`n// TODO migracion`npublic class LegacyDateUtils { }`n"
  }
  $j = $x.Json
  Igual 'los detectores, en orden' 'javac,lombok-a-mano,lombok-qualifier,java21-texto,limpieza' ((@($j.detectores | ForEach-Object { $_.id })) -join ',')
  $d = Det $j 'limpieza'
  Igual 'estado ok' 'ok' $d.estado
  Igual 'motivo vacio' '' $d.motivo
  Igual 'sin corte' $false $d.corte
  Igual 'los campos de un detector' 'id,estado,motivo,segundos,corte' ($d.PSObject.Properties.Name -join ',')
  $mias = Limpieza-De $j
  Comprueba 'hay incidencias de limpieza' ($mias.Count -gt 0)
  Igual 'las reglas que salen' 'clase-sin-uso,marca-pendiente,resto-herramienta' ((@($mias | ForEach-Object { $_.regla } | Sort-Object -Unique)) -join ',')
  Igual 'todas del area limpieza' 0 @($mias | Where-Object { $_.area -cne 'limpieza' }).Count
  Igual 'todas con sus nueve campos' 0 @($mias | Where-Object { -not ($_.PSObject.Properties.Name -join ',' -ceq 'area,fichero,linea,herramienta,regla,origen,sonar,texto,queHago') }).Count
  Comprueba-Formato $j $x.E
}

$Pruebas['58 c1 g) cache: un JSON de antes de limpieza (con la misma clave) no se reutiliza: se mide otra vez y sale el detector; uno completo con la misma clave si se reutiliza'] = {
  $E = Nuevo-Escenario 'c1g'
  Escribe $E.Repo 'notas.bak' "x`n"
  [void](GitEn $E.Repo @('add', '-f', '--', 'notas.bak'))
  [void](GitEn $E.Repo @('commit', '-q', '-m', 'c1'))
  $m1 = Mide $E @{} @{} 'antes'
  Comprueba 'la primera medida lleva limpieza' ($null -ne (Det $m1.Json 'limpieza'))
  $m2 = Mide $E @{} @{} 'antes' -ConCache
  Comprueba 'completo y con la misma clave: se reutiliza' ("$($m2.Texto)" -match 'ya medidas') $m2.Texto
  # el JSON de antes de esta pieza: sin el detector ni sus incidencias, con la misma clave
  $ruta = Join-Path $E.Datos 'practicas-antes.json'
  $v = Lee-Json $ruta
  $v.detectores = @($v.detectores | Where-Object { $_.id -cne 'limpieza' })
  $v.incidencias = @($v.incidencias | Where-Object { $_.herramienta -cne 'limpieza' })
  [System.IO.File]::WriteAllText($ruta, (ConvertTo-Json -InputObject $v -Depth 8))
  Igual 'el JSON viejo no lleva limpieza' 0 @((Lee-Json $ruta).detectores | Where-Object { $_.id -ceq 'limpieza' }).Count
  $m3 = Mide $E @{} @{} 'antes' -ConCache
  Comprueba 'con la misma clave, se mide otra vez (no dice que ya estaba medido)' ("$($m3.Texto)" -notmatch 'ya medidas') $m3.Texto
  Igual 'la misma clave de antes' $m1.Json.clave $m3.Json.clave
  Igual 'sale el detector limpieza' 'ok' (Det $m3.Json 'limpieza').estado
  Comprueba 'y su incidencia' ((Limpieza-De $m3.Json 'resto-herramienta').Count -eq 1)
}

$Pruebas['59 c1 h) la pagina 5 con ese JSON lleva Limpieza, su explicacion y sus incidencias (en las dos vistas)'] = {
  $x = Mide-C1 'c1h' @{
    'notas.bak' = "x`n"
    'target/classes/A.class' = "x`n"
    "${DirC1}LegacyDateUtils.java" = "package com.acme.limpio;`n`n// TODO migracion`npublic class LegacyDateUtils { }`n"
  }
  $mias = Limpieza-De $x.Json
  Comprueba 'hay incidencias de limpieza' ($mias.Count -gt 0)
  $h = Pagina5-De6 'c1h-pagina' $x.Json
  Comprueba 'monta 5-buenas-practicas.html' ($h.Length -gt 0)
  if ($h.Length -eq 0) { return }
  Comprueba 'la leyenda lleva Limpieza con su cuenta' ($h -cmatch ('(?s)bp-ley-limpieza.*?Limpieza<b class="bp-ley-n">' + $mias.Count + '</b>'))
  Comprueba 'lleva la explicacion del area' ($h -cmatch 'Lo que no deber.a llegar al senior: restos de herramientas en git, marcas pendientes, c.digo comentado y clases que nadie usa\. Solo avisa: decide t. qu. se borra\.')
  foreach ($regla in @('resto-herramienta', 'marca-pendiente', 'clase-sin-uso')) {
    Igual "cada incidencia sale en las dos vistas: $regla" (2 * @($mias | Where-Object { $_.regla -ceq $regla }).Count) ([regex]::Matches($h, "limpieza $regla").Count)
  }
  Comprueba 'y no esta entre las notas de los que no midieron' ($h -notmatch '<code>limpieza</code> <b>')
  Comprueba 'el grupo del area tiene su nombre (Limpieza) y la cuenta de las incidencias' ($h -cmatch ('<h3 id="ga-limpieza">Limpieza</h3><span class="bp-num">' + $mias.Count + '</span>'))
  Comprueba 'el resumen de la barra de areas lo dice con su nombre' ($h -cmatch ('Limpieza: ' + $mias.Count + '"'))
}

$Pruebas['60 c1 i) estado: sin git la regla de restos no mide y lo dice en el motivo (las demas siguen); sin src/main ni git no aplica; con git y sin src/main mide ok'] = {
  # una carpeta sin git: solo se miran las marcas, el codigo comentado y las clases
  $d = Join-Path $Dir 'c1i-sin-git'
  Escribe $d 'src/main/java/com/acme/Sola.java' "package com.acme;`n// TODO migracion`npublic class Sola { }`n"
  Escribe $d 'notas.bak' "x`n"
  $r = Get-ResultadoLimpieza $d
  Igual 'sin git y con src/main: ok' 'ok' $r.Estado
  Comprueba 'el motivo dice que no es un repo de git' ("$($r.Motivo)" -match 'git') "$($r.Motivo)"
  Igual 'ni resto-herramienta ni tests-entrega' 0 @($r.Incidencias | Where-Object { $_.regla -ceq 'resto-herramienta' -or $_.regla -ceq 'tests-entrega' }).Count
  Igual 'la marca y la clase si' 'clase-sin-uso,marca-pendiente' ((@($r.Incidencias | ForEach-Object { $_.regla } | Sort-Object -Unique)) -join ',')
  # una carpeta sin git ni src/main
  $v = Join-Path $Dir 'c1i-vacia'
  Escribe $v 'notas.txt' "x`n"
  $n = Get-ResultadoLimpieza $v
  Igual 'sin git ni src/main: no aplica' 'no aplica' $n.Estado
  Comprueba 'con su motivo' ("$($n.Motivo)" -ne '') "$($n.Motivo)"
  # un repo de git sin src/main: mide los restos
  $E = Nuevo-Escenario 'c1i-git'
  Remove-Item -LiteralPath (Get-Ruta $E.Repo 'src') -Recurse -Force
  Escribe $E.Repo 'notas.bak' "x`n"
  [void](GitEn $E.Repo @('add', '-A'))
  [void](GitEn $E.Repo @('commit', '-q', '-m', 'sin src'))
  $m = Mide $E @{}
  Igual 'con git y sin src/main: ok' 'ok' (Det $m.Json 'limpieza').estado
  Igual 'y el resto de notas.bak sale' 'notas.bak' ((Limpieza-De $m.Json 'resto-herramienta') | ForEach-Object { $_.fichero })
}

$Pruebas['61 c1 j) resto-herramienta: una carpeta dentro de otra (migracion-lote/target/) da UNA incidencia, con la carpeta mas alta (migracion-lote/) y ninguna con la de dentro'] = {
  $x = Mide-C1 'c1j' @{ 'migracion-lote/target/A.class' = "x`n" }
  $r = Limpieza-De $x.Json 'resto-herramienta'
  Igual 'una sola incidencia' 1 $r.Count
  Igual 'con la carpeta mas alta' 'migracion-lote/' (Ficheros-C1 $r)
  Igual 'ninguna con migracion-lote/target/' 0 @($r | Where-Object { $_.fichero -ceq 'migracion-lote/target/' }).Count
  Igual 'y es un resto de la migracion, no de Maven' 'la migracion' $(if ($r.Count -eq 1) { ($r[0].texto -replace '^.* es un resto de (.*?)\. Si no hace falta.*$', '$1') } else { '' })
}

$Pruebas['62 c1 k) codigo-comentado al final del fichero: tres lineas // ; ; } que son las ultimas, sin salto de linea final, dan una incidencia en la primera'] = {
  $f = "package com.acme;`n`npublic class Fin {`n}`n// a();`n// b();`n// }"
  Comprueba 'el fichero de la prueba no acaba en salto de linea' (-not $f.EndsWith("`n"))
  $x = Mide-C1 'c1k' @{ 'src/main/java/com/acme/Fin.java' = $f }
  $r = Limpieza-De $x.Json 'codigo-comentado'
  Igual 'una incidencia, en la primera linea del tramo (la 5)' 'src/main/java/com/acme/Fin.java:5' (($r | ForEach-Object { $_.fichero + ':' + $_.linea }) -join '|')
}

# ================================ M45: LA MARCA DE INTENTO EN CADA RONDA ================================
# m45-copilot.ps1 apunta, en cada llamada a Copilot, el HEAD y la marca .rescate/intento-en-curso.json que ve, y pasa la llamada a bp4-copilot.ps1.
# Un hook pre-commit apunta lo mismo en cada commit de la fase (lo que corre entre un commit y el siguiente).
$Aj45 = @{ CopilotExe = (Join-Path $falsos 'm45-copilot.ps1') }

function Entorno45([string]$Marcas) { return @{ M45_DELEGA = (Join-Path $falsos 'bp4-copilot.ps1'); M45_MARCAS = $Marcas } }

# Lo apuntado: una fila por llamada (Quien: copilot o commit), con su carpeta, su HEAD y su marca ($null si no habia).
function Marcas45([string]$Fichero) {
  if (-not (Test-Path -LiteralPath $Fichero)) { return @() }
  return @([System.IO.File]::ReadAllLines($Fichero) | Where-Object { $_ } | ForEach-Object {
      $p = $_ -split '\|', 4
      $m = $null
      if ($p[3] -cne '-') { $m = $p[3] | ConvertFrom-Json }
      [pscustomobject]@{ Quien = $p[0]; Dir = $p[1]; Head = $p[2]; Marca = $m }
    })
}

function Hook45($E) {
  [void](GitEn $E.Repo @('config', 'core.hooksPath', '.git/hooks'))   # el global del usuario, si lo hay, no cuenta aqui
  $h = @('#!/bin/sh', 'm=-', '[ -f .rescate/intento-en-curso.json ] && m=$(cat .rescate/intento-en-curso.json)', 'printf ''commit|%s|%s|%s\n'' "$PWD" "$(git rev-parse HEAD)" "$m" >> "$M45_MARCAS"', '')
  Escribe $E.Repo '.git/hooks/pre-commit' ($h -join "`n")
  if (Get-Command chmod -ErrorAction SilentlyContinue) { & chmod +x (Get-Ruta $E.Repo '.git/hooks/pre-commit') }
}

function HayMarca45($E) { return (Test-Path -LiteralPath (Get-Ruta $E.Repo '.rescate/intento-en-curso.json')) }

$Pruebas['m45 (a)(c) practicas: cada llamada a Copilot de la ronda ve la marca (paso practicas, ronda 1, commit = el HEAD de antes) y al acabar la fase no queda marca'] = {
  $E = Nuevo-Escenario4 'm45a' @('Alfa', 'Beta')
  $head0 = GitEn $E.Repo @('rev-parse', 'HEAD')
  $marcas = Join-Path $E.Raiz 'marcas.txt'
  $x = Fase4 $E (Entorno45 $marcas) $Aj45
  Igual 'la fase deja seguir' $true $x.Sigue
  Igual 'los dos commits de siempre' ("$Commit4${Ruta4}Beta.java|$Commit4${Ruta4}Alfa.java|inicial") ($x.Commits -join '|')
  $l = @(Marcas45 $marcas | Where-Object { $_.Quien -ceq 'copilot' })
  Igual 'dos llamadas a Copilot' 2 $l.Count
  foreach ($m in $l) {
    Comprueba 'la llamada ve la marca' ($null -ne $m.Marca)
    if ($null -eq $m.Marca) { continue }
    Igual 'su paso es practicas' 'practicas' $m.Marca.paso
    Igual 'su numero es el de la ronda' 1 $m.Marca.lote
    Igual 'su commit es el HEAD de antes de la ronda' $head0 $m.Marca.commit
    Igual 'y la llamada ve ese HEAD' $head0 $m.Head
  }
  Comprueba 'al acabar la fase no hay marca' (-not (HayMarca45 $E))
  Igual 'el worktree queda limpio' '' (Estado-Git4 $E)
}

$Pruebas['m45 (b) practicas: tras cada commit de la ronda la marca pasa al HEAD nuevo (lo ve el hook de cada commit)'] = {
  $E = Nuevo-Escenario4 'm45b' @('Alfa', 'Beta')
  Hook45 $E
  $head0 = GitEn $E.Repo @('rev-parse', 'HEAD')
  $marcas = Join-Path $E.Raiz 'marcas.txt'
  $x = Fase4 $E (Entorno45 $marcas) $Aj45
  Igual 'los dos commits de siempre' ("$Commit4${Ruta4}Beta.java|$Commit4${Ruta4}Alfa.java|inicial") ($x.Commits -join '|')
  $c = @(Marcas45 $marcas | Where-Object { $_.Quien -ceq 'commit' })
  Igual 'el hook ha visto dos commits' 2 $c.Count
  if ($c.Count -ne 2) { return }
  Comprueba 'antes del primero hay marca y su commit es el HEAD de antes' ($null -ne $c[0].Marca -and $c[0].Head -ceq $head0 -and $c[0].Marca.commit -ceq $head0) (($c[0] | ConvertTo-Json -Compress -Depth 3))
  $nuevo = GitEn $E.Repo @('rev-parse', 'HEAD~1')
  Comprueba 'antes del segundo el HEAD ya es el del primer commit' ($c[1].Head -ceq $nuevo -and $nuevo -cne $head0) "$($c[1].Head) frente a $nuevo"
  Comprueba 'y la marca ya lleva ese HEAD nuevo, no el de antes' ($null -ne $c[1].Marca -and $c[1].Marca.commit -ceq $nuevo) (($c[1] | ConvertTo-Json -Compress -Depth 3))
  Comprueba 'al acabar no hay marca' (-not (HayMarca45 $E))
}

$Pruebas['m45 (c) practicas: la ronda no deja marca al acabar, sea cual sea su final (la IA hace un commit, no cambia nada, rompe lo compilado o falla)'] = {
  foreach ($g in @('commit', 'nada', 'codigo', 'falla')) {
    $E = Nuevo-Escenario4 "m45c-$g" @('Alfa', 'Beta')
    $marcas = Join-Path $E.Raiz 'marcas.txt'
    $x = Fase4 $E ((Entorno45 $marcas) + @{ RESCATE_FALSO = $g }) $Aj45
    $l = @(Marcas45 $marcas | Where-Object { $_.Quien -ceq 'copilot' -and $null -ne $_.Marca })
    Comprueba "$g : las llamadas vieron la marca" ($l.Count -gt 0 -and $l.Count -eq @(Marcas45 $marcas).Count) "con marca $($l.Count) de $(@(Marcas45 $marcas).Count)"
    Comprueba "$g : al acabar no hay marca" (-not (HayMarca45 $E))
    Igual "$g : el worktree queda limpio" '' (Estado-Git4 $E)
  }
}

$Pruebas['m45 (i) practicas: la Info de lo apartado lista como mucho 10 ficheros y dice y N mas'] = {
  $E = Nuevo-Escenario4 'm45i' @('Alfa')
  $lista = @()
  foreach ($i in 1..12) { $f = '{0}Extra{1:00}.java' -f $Ruta4, $i; Escribe $E.Repo $f "class Extra$i { }`n"; $lista += $f }
  $x = Fase4 $E
  $diez = (@($lista | Select-Object -First 10) -join ', ')
  Comprueba 'dice los 10 primeros y y 2 mas' ($x.Texto.Contains("(git stash): $diez y 2 mas. Para recuperarlo:")) $x.Texto
  Comprueba 'y no nombra el undecimo' (-not $x.Texto.Contains('Extra11.java')) $x.Texto
  Igual 'los 12 ficheros estan en el stash' 12 @((GitEn $E.Repo @('show', '--name-only', '--format=', 'stash@{0}^3')) -split "`n" | Where-Object { $_ }).Count
}

# ================================ M65: LOMBOK EN EL POM.XML ================================
# Sin Lombok en el pom, la fase lo anade (el bloque de la referencia o uno por defecto), comprueba que compila y lo commitea; si no compila,
# deja el pom como estaba y el aviso de siempre. Maven de mentira: m65-mvn.ps1 (bp4-mvn.ps1; con M65_ROTO no compila un pom con Lombok).
$Sub65 = 'practica(lombok): anade Lombok al pom.xml'
$Lombok65 = @('<dependency>', '  <groupId>org.projectlombok</groupId>', '  <artifactId>lombok</artifactId>', '  <optional>true</optional>', '</dependency>')
$Defecto65 = @('<dependency>', '  <groupId>org.projectlombok</groupId>', '  <artifactId>lombok</artifactId>', '  <scope>provided</scope>', '  <optional>true</optional>', '</dependency>')
$Procesador65 = @('<path>', '  <groupId>org.projectlombok</groupId>', '  <artifactId>lombok</artifactId>', '  <version>1.18.30</version>', '</path>')

# Un pom.xml con sangria de 2 espacios: el padre de Spring Boot (o no), $Deps (lineas de mas dentro de <dependencies>, con la sangria relativa a
# <dependency>) y, con $Paths distinto de $null, un maven-compiler-plugin con annotationProcessorPaths: el procesador de configuracion y $Paths.
function Pom65([string[]]$Deps = @(), [bool]$Boot = $true, [string[]]$Paths = $null) {
  $n = @('<?xml version="1.0" encoding="UTF-8"?>', '<project>', '  <modelVersion>4.0.0</modelVersion>')
  if ($Boot) { $n += @('  <parent>', '    <groupId>org.springframework.boot</groupId>', '    <artifactId>spring-boot-starter-parent</artifactId>', '    <version>3.3.5</version>', '  </parent>') }
  $n += @('  <groupId>com.acme</groupId>', '  <artifactId>p4</artifactId>', '  <version>1</version>', '  <dependencies>', '    <dependency>', '      <groupId>org.springframework.boot</groupId>', '      <artifactId>spring-boot-starter-batch</artifactId>', '    </dependency>')
  $n += @($Deps | ForEach-Object { '    ' + $_ })
  $n += '  </dependencies>'
  if ($null -ne $Paths) {
    $n += @('  <build>', '    <plugins>', '      <plugin>', '        <artifactId>maven-compiler-plugin</artifactId>', '        <configuration>', '          <annotationProcessorPaths>', '            <path>', '              <groupId>org.springframework.boot</groupId>', '              <artifactId>spring-boot-configuration-processor</artifactId>', '            </path>')
    $n += @($Paths | ForEach-Object { '            ' + $_ })
    $n += @('          </annotationProcessorPaths>', '        </configuration>', '      </plugin>', '    </plugins>', '  </build>')
  }
  $n += '</project>'
  return (($n -join "`n") + "`n")
}

# Las lineas de $Bloque con la sangria $Base delante, cada una con su salto, y lo que le sigue ($Cierre: la etiqueta de cierre con su sangria).
function Con-Bloque65([string]$Pom, [string]$Cierre, [string[]]$Bloque, [string]$Base) {
  return $Pom.Replace($Cierre, ((@($Bloque | ForEach-Object { $Base + $_ }) -join "`n") + "`n" + $Cierre))
}

function Fase65($E, [hashtable]$Entorno = @{}, [hashtable]$Cambios = @{}) {
  $c = @{ MvnExe = (Join-Path $falsos 'm65-mvn.ps1') }
  foreach ($k in $Cambios.Keys) { $c[$k] = $Cambios[$k] }
  return (Fase4 $E $Entorno $c)
}

$Pruebas['m65 a) sin Lombok y la referencia lo tiene: su bloque entra en <dependencies> del pom, con su commit, y la fase sigue con las tareas'] = {
  $mig = Pom65
  $E = Nuevo-Escenario4 'm65a' @('Alfa', 'Beta') $false @() $mig (Pom65 $Lombok65)
  $x = Fase65 $E
  Igual 'la fase deja seguir' $true $x.Sigue
  Igual 'ninguna parada' 0 $script:Paradas.Count
  Igual 'el pom lleva el bloque de la referencia antes de </dependencies>' (Con-Bloque65 $mig "  </dependencies>`n" $Lombok65 '    ') (Lee $E.Repo 'pom.xml')
  Igual 'los commits: el del pom y uno por fichero' ("$Commit4${Ruta4}Beta.java|$Commit4${Ruta4}Alfa.java|$Sub65|inicial") ($x.Commits -join '|')
  Igual 'el commit del pom solo toca pom.xml' 'pom.xml' (GitEn $E.Repo @('show', '--name-only', '--format=', 'HEAD~2'))
  $sha = GitEn $E.Repo @('rev-parse', '--short=7', 'HEAD~2')
  Comprueba 'la consola lo dice, con el commit' ($x.Texto -match [regex]::Escape("Lombok no estaba en el pom.xml: lo he anadido como en la referencia (commit $sha)")) $x.Texto
  foreach ($c in @('Alfa', 'Beta')) { Igual "$c`: tarea hecha" 'hecha' (Tarea4 $x $c).estado }
  Igual 'dos llamadas a Copilot' 2 (Llamadas-De $E.Copilot).Count
  Igual 'Maven: la comprobacion del pom, la foto y la ronda' 3 (Compilaciones4 $E).Count
  Igual 'el worktree queda limpio' '' (Estado-Git4 $E)
}

$Pruebas['m65 a2) el bloque se pone con los saltos de linea del pom (CRLF) y a la sangria del migrado'] = {
  $mig = (Pom65).Replace('  ', '    ').Replace("`n", "`r`n")
  $ref = (Pom65 $Lombok65).Replace('  ', '    ')
  $E = Nuevo-Escenario4 'm65a2' @('Alfa') $false @() $mig $ref
  $x = Fase65 $E
  Igual 'la fase deja seguir' $true $x.Sigue
  $b4 = @($Lombok65 | ForEach-Object { $_.Replace('  ', '    ') })
  $esperado = (Con-Bloque65 $mig "    </dependencies>`r`n" $b4 '        ').Replace("`r`n", "`n").Replace("`n", "`r`n")
  $pom = Lee $E.Repo 'pom.xml'
  Igual 'el pom: el bloque a la sangria de las otras dependencias' $esperado $pom
  Igual 'ningun salto de linea suelto' 0 ([regex]::Matches($pom, "(?<!`r)`n")).Count
}

$Pruebas['m65 a3) varios modulos: Lombok va al pom del modulo que tiene el fichero, no al de la raiz ni al de otro modulo'] = {
  $E = Nuevo-Escenario4 'm65m' @('Alfa') $false
  $raizPom = Pom65
  $modPom = Pom65 @() $false
  Escribe $E.Repo 'pom.xml' $raizPom
  Escribe $E.Repo 'modulo-a/pom.xml' $modPom
  Escribe $E.Repo 'modulo-b/pom.xml' $modPom
  [void](GitEn $E.Repo @('add', '--', 'pom.xml', 'modulo-a/pom.xml', 'modulo-b/pom.xml'))
  [void](GitEn $E.Repo @('commit', '-q', '-m', 'modulos'))
  $RepoRoot = $E.Repo
  $PlantillaRoot = ''
  $Registros = $E.Registros
  $ficheros = [ordered]@{ 'modulo-a/src/main/java/com/acme/p4/Alfa.java' = 'x' }
  $r = Con-Falso @{ BP4_LLAMADAS = $E.Mvn } @{ MvnExe = (Join-Path $falsos 'm65-mvn.ps1') } { Add-LombokAlPom $ficheros 6>$null }
  Igual 'sin motivo de fallo' '' (@($r) -join '')
  Igual 'el pom del modulo con el fichero lleva el bloque (sin version: el padre de la raiz es Spring Boot)' (Con-Bloque65 $modPom "  </dependencies>`n" $Defecto65 '    ') (Lee $E.Repo 'modulo-a/pom.xml')
  Igual 'el de otro modulo, igual' $modPom (Lee $E.Repo 'modulo-b/pom.xml')
  Igual 'el de la raiz, igual' $raizPom (Lee $E.Repo 'pom.xml')
  Igual 'el commit solo toca el pom del modulo' 'modulo-a/pom.xml' (GitEn $E.Repo @('show', '--name-only', '--format=', 'HEAD'))
}

$Pruebas['m65 b) con annotationProcessorPaths en el migrado, Lombok entra tambien ahi: como la referencia, y si no, con ${lombok.version}'] = {
  $mig = Pom65 @() $true @()
  # la referencia lo tiene en sus dos sitios
  $E = Nuevo-Escenario4 'm65b1' @('Alfa') $false @() $mig (Pom65 $Lombok65 $true $Procesador65)
  $x = Fase65 $E
  Igual 'la fase deja seguir' $true $x.Sigue
  $esperado = Con-Bloque65 (Con-Bloque65 $mig "  </dependencies>`n" $Lombok65 '    ') "          </annotationProcessorPaths>`n" $Procesador65 '            '
  Igual 'dependencia y procesador, el de la referencia con su version' $esperado (Lee $E.Repo 'pom.xml')
  Igual 'un solo commit del pom' 1 @($x.Commits | Where-Object { $_ -ceq $Sub65 }).Count
  # la referencia solo tiene la dependencia: el procesador lleva la propiedad del padre
  $E = Nuevo-Escenario4 'm65b2' @('Alfa') $false @() $mig (Pom65 $Lombok65)
  [void](Fase65 $E)
  $sinVersion = @('<path>', '  <groupId>org.projectlombok</groupId>', '  <artifactId>lombok</artifactId>', '  <version>${lombok.version}</version>', '</path>')
  $esperado = Con-Bloque65 (Con-Bloque65 $mig "  </dependencies>`n" $Lombok65 '    ') "          </annotationProcessorPaths>`n" $sinVersion '            '
  Igual 'la referencia sin procesador: el del padre de Spring Boot' $esperado (Lee $E.Repo 'pom.xml')
}

$Pruebas['m65 c) si con Lombok el migrado no compila: el pom queda como estaba, sin commit, y sale el aviso de siempre con la salida de Maven en el registro'] = {
  $mig = Pom65
  $E = Nuevo-Escenario4 'm65c' @('Alfa', 'Beta') $false @() $mig (Pom65 $Lombok65)
  $x = Fase65 $E @{ M65_ROTO = '1' }
  Igual 'la fase deja seguir' $true $x.Sigue
  Igual 'el pom queda como estaba' $mig (Lee $E.Repo 'pom.xml')
  Igual 'ningun commit nuevo' 'inicial' ($x.Commits -join '|')
  Igual 'el worktree queda limpio' '' (Estado-Git4 $E)
  Comprueba 'el aviso de siempre' (@($x.Avisos | Where-Object { $_ -match 'El migrado no usa Lombok: anadelo al pom\.xml y vuelve a lanzar' }).Count -eq 1) ($x.Avisos -join ' / ')
  Comprueba 'el aviso dice por que: no compila con Lombok' (@($x.Avisos | Where-Object { $_ -match 'No compila: .*Could not resolve dependencies' }).Count -eq 1) ($x.Avisos -join ' / ')
  $reg = Join-Path $E.Registros 'practicas-lombok-pom.log'
  Comprueba 'y el registro de Maven lleva su salida' ((Test-Path -LiteralPath $reg) -and ((Lee $E.Registros 'practicas-lombok-pom.log') -match 'Could not resolve dependencies')) $reg
  Comprueba 'el aviso da la ruta de ese registro' (@($x.Avisos | Where-Object { $_.Contains($reg) }).Count -eq 1) ($x.Avisos -join ' / ')
  Comprueba 'la consola no dice que lo ha anadido' ($x.Texto -notmatch 'Lombok no estaba en el pom') $x.Texto
  Igual 'ninguna llamada a Copilot' 0 (Llamadas-De $E.Copilot).Count
  Igual 'Maven: solo la comprobacion del pom' 1 (Compilaciones4 $E).Count
  Igual 'ninguna parada' 0 $script:Paradas.Count
}

$Pruebas['m65 d) referencia sin Lombok: el bloque por defecto, sin version con el padre de Spring Boot y con la de $Cfg.LombokVersion si no'] = {
  Igual 'la version por defecto: la ultima estable de Maven Central (21-11-2026)' '1.18.48' $Cfg.LombokVersion
  $mig = Pom65
  $E = Nuevo-Escenario4 'm65d1' @('Alfa') $false @() $mig (Pom65)
  $x = Fase65 $E
  Igual 'la fase deja seguir' $true $x.Sigue
  Igual 'provided y optional, sin version' (Con-Bloque65 $mig "  </dependencies>`n" $Defecto65 '    ') (Lee $E.Repo 'pom.xml')
  Comprueba 'la consola dice que es el de por defecto' ($x.Texto -match 'Lombok no estaba en el pom\.xml: lo he anadido con la configuracion por defecto \(commit [0-9a-f]{7}\)') $x.Texto
  # sin padre de Spring Boot y sin referencia: con la version de $Cfg.LombokVersion
  $mig = Pom65 @() $false
  $E = Nuevo-Escenario4 'm65d2' @('Alfa') $false @() $mig
  [void](Fase65 $E @{} @{ LombokVersion = '9.9.9' })
  $conVersion = @('<dependency>', '  <groupId>org.projectlombok</groupId>', '  <artifactId>lombok</artifactId>', '  <version>9.9.9</version>', '  <scope>provided</scope>', '  <optional>true</optional>', '</dependency>')
  Igual 'sin Spring Boot y sin referencia: con la version de LombokVersion' (Con-Bloque65 $mig "  </dependencies>`n" $conVersion '    ') (Lee $E.Repo 'pom.xml')
  # Lombok solo en un comentario y en dependencyManagement de la referencia: no cuenta como dependencia
  $refTexto = (Pom65).Replace("  <dependencies>`n", "  <!-- <dependency><groupId>org.projectlombok</groupId><artifactId>lombok</artifactId><version>1.0</version></dependency> -->`n  <dependencyManagement>`n    <dependencies>`n      <dependency>`n        <groupId>org.projectlombok</groupId>`n        <artifactId>lombok</artifactId>`n        <version>1.0</version>`n      </dependency>`n    </dependencies>`n  </dependencyManagement>`n  <dependencies>`n")
  $mig = Pom65
  $E = Nuevo-Escenario4 'm65d3' @('Alfa') $false @() $mig $refTexto
  [void](Fase65 $E)
  Igual 'la referencia con Lombok solo en un comentario y en dependencyManagement: el de por defecto' (Con-Bloque65 $mig "  </dependencies>`n" $Defecto65 '    ') (Lee $E.Repo 'pom.xml')
}

$Pruebas['m65 e) un pom que ya tiene Lombok no se toca: ningun commit del pom y ni una compilacion de mas'] = {
  $mig = Pom65 $Lombok65
  $E = Nuevo-Escenario4 'm65e' @('Alfa', 'Beta') $false @() $mig (Pom65)
  $x = Fase65 $E
  Igual 'la fase deja seguir' $true $x.Sigue
  Igual 'el pom, igual' $mig (Lee $E.Repo 'pom.xml')
  Igual 'los commits: uno por fichero y ninguno del pom' ("$Commit4${Ruta4}Beta.java|$Commit4${Ruta4}Alfa.java|inicial") ($x.Commits -join '|')
  Comprueba 'la consola no dice nada de Lombok en el pom' ($x.Texto -notmatch 'Lombok no estaba') $x.Texto
  Igual 'Maven: la foto y la ronda' 2 (Compilaciones4 $E).Count
}

$Pruebas['m65 f) un pom sin <dependencies>: no se inventa nada, el aviso de siempre y el pom como estaba'] = {
  $mig = "<project><modelVersion>4.0.0</modelVersion><groupId>com.acme</groupId><artifactId>p4</artifactId><version>1</version></project>`n"
  $E = Nuevo-Escenario4 'm65f' @('Alfa') $false @() $mig
  $x = Fase65 $E
  Igual 'la fase deja seguir' $true $x.Sigue
  Igual 'el pom, igual' $mig (Lee $E.Repo 'pom.xml')
  Igual 'ningun commit nuevo' 'inicial' ($x.Commits -join '|')
  Comprueba 'el aviso de siempre, con el motivo' (@($x.Avisos | Where-Object { $_ -match 'El migrado no usa Lombok: anadelo al pom\.xml y vuelve a lanzar' -and $_ -match '<dependencies>' }).Count -eq 1) ($x.Avisos -join ' / ')
  Igual 'ninguna llamada a Copilot ni a Maven' 0 ((Llamadas-De $E.Copilot).Count + (Llamadas-De $E.Mvn).Count)
}

$Pruebas['m65 g) un pom con dependencyManagement, un comentario y un plugin con sus dependencias, antes o despues: Lombok va solo a las dependencias del proyecto'] = {
  $cabeza = @('<project xmlns="http://maven.apache.org/POM/4.0.0">', '  <modelVersion>4.0.0</modelVersion>', '  <!-- <dependencies> de mentira -->', '  <dependencyManagement>', '    <dependencies>', '      <dependency>',
    '        <groupId>com.acme</groupId>', '        <artifactId>acme-bom</artifactId>', '      </dependency>', '    </dependencies>', '  </dependencyManagement>')
  $deps = @('  <dependencies>', '    <dependency>', '      <groupId>com.acme</groupId>', '      <artifactId>acme-comun</artifactId>', '    </dependency>', '  </dependencies>')
  $build = @('  <build>', '    <plugins>', '      <plugin>', '        <artifactId>acme-plugin</artifactId>', '        <dependencies>', '          <dependency>', '            <groupId>com.acme</groupId>',
    '            <artifactId>acme-extension</artifactId>', '          </dependency>', '        </dependencies>', '      </plugin>', '    </plugins>', '  </build>')
  $conVersion = @($Defecto65[0..2]) + @("  <version>$($Cfg.LombokVersion)</version>") + @($Defecto65[3..5])
  $n = 0
  foreach ($caso in @(@{ Nombre = 'el plugin despues'; Lineas = ($cabeza + $deps + $build); Cierre = "  </dependencies>`n  <build>`n" }, @{ Nombre = 'el plugin antes'; Lineas = ($cabeza + $build + $deps); Cierre = "  </dependencies>`n</project>`n" })) {
    $n++
    $mig = (($caso.Lineas + '</project>') -join "`n") + "`n"
    $E = Nuevo-Escenario4 "m65g$n" @('Alfa') $false @() $mig
    $x = Fase65 $E
    Igual "$($caso.Nombre): la fase deja seguir" $true $x.Sigue
    Igual "$($caso.Nombre): el bloque entra en <dependencies> de <project>, con version porque no hay padre de Spring Boot" (Con-Bloque65 $mig $caso.Cierre $conVersion '    ') (Lee $E.Repo 'pom.xml')
  }
}

$Pruebas['m65 h) si git rechaza el commit del pom: el pom queda como estaba y el aviso de siempre lleva lo que dijo git'] = {
  $mig = Pom65
  $E = Nuevo-Escenario4 'm65h' @('Alfa') $false @() $mig (Pom65 $Lombok65)
  [void](GitEn $E.Repo @('config', 'core.hooksPath', '.git/hooks'))   # el global del usuario, si lo hay, no cuenta aqui
  Escribe $E.Repo '.git/hooks/pre-commit' "#!/bin/sh`necho 'hook de mentira: no se commitea'`nexit 1`n"
  if (Get-Command chmod -ErrorAction SilentlyContinue) { & chmod +x (Get-Ruta $E.Repo '.git/hooks/pre-commit') }
  $x = Fase65 $E
  Igual 'la fase deja seguir' $true $x.Sigue
  Igual 'el pom queda como estaba' $mig (Lee $E.Repo 'pom.xml')
  Igual 'ningun commit nuevo' 'inicial' ($x.Commits -join '|')
  Comprueba 'el aviso de siempre, con lo que dijo git' (@($x.Avisos | Where-Object { $_ -match 'El migrado no usa Lombok: anadelo al pom\.xml y vuelve a lanzar' -and $_ -match 'git commit ha fallado: .*hook de mentira' }).Count -eq 1) ($x.Avisos -join ' / ')
  Igual 'ninguna llamada a Copilot' 0 (Llamadas-De $E.Copilot).Count
}

# ================================ LANZADOR ================================
Invoke-Banco $Pruebas 'tests/probar-practicas.ps1'
