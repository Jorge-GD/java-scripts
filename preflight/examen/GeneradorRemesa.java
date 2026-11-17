package com.acme.recibos;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.io.FileWriter;
import java.math.BigInteger;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.Date;
import java.util.Vector;

import org.springframework.stereotype.Component;

import com.acme.recibos.util.Utils;

// Remesa al banco: fichero de ancho fijo (120 posiciones) con cabecera, un registro por recibo y un total.
// 01 = cabecera, 02 = recibo, 09 = total
@Component
public class GeneradorRemesa {

    private static final String RAIZ = System.getProperty("batch.home", "C:\\batch\\recibos");
    private static final String SALIDA = RAIZ + "/remesas";
    private static final String ENVIADOS = RAIZ + "/enviados";

    // datos del ordenante, los da el banco
    private static final String ORDENANTE_NIF = "A00012345";
    private static final String ORDENANTE_NOMBRE = "ACME SEGUROS Y REASEGUROS SA";
    private static final String ORDENANTE_IBAN = "ES5699990091000001712710";

    public void generar() throws Exception {
        Statement st = Conexion.get().createStatement();
        ResultSet rs = st.executeQuery("SELECT NUM_RECIBO, POLIZA, NOMBRE_TOMADOR, IMPORTE, IBAN, FECHA_CARGO, MANDATO "
                + "FROM RECIBOS WHERE ESTADO = 'P' ORDER BY FECHA_CARGO, NUM_RECIBO");
        Vector buenos = new Vector();
        Vector malos = new Vector();
        while (rs.next()) {
            Recibo r = new Recibo();
            r.setNumRecibo(rs.getString("NUM_RECIBO"));
            r.setPoliza(rs.getString("POLIZA"));
            r.setNombreTomador(rs.getString("NOMBRE_TOMADOR"));
            r.setImporte(rs.getDouble("IMPORTE"));
            r.setIban(rs.getString("IBAN"));
            r.setFechaCargo(rs.getDate("FECHA_CARGO"));
            r.setMandato(rs.getString("MANDATO"));

            String[] error = validarParaBanco(r);
            if (error == null) {
                buenos.add(r);
            } else {
                malos.add(new Object[] { r, error });
            }
        }
        rs.close();
        st.close();

        // los que el banco no aceptaria se apartan
        for (int i = 0; i < malos.size(); i++) {
            Object[] m = (Object[]) malos.get(i);
            rechazarEnRemesa((Recibo) m[0], (String[]) m[1]);
        }

        if (buenos.size() == 0) {
            System.out.println("No hay recibos pendientes de remesar");
            Estado.ficheroRemesa = null;
            return;
        }

        int numRemesa = siguienteNumero();
        String nombre = "REMESA_ACME_" + Utils.fechaFichero(new Date()) + "_" + Utils.rellenarIzq("" + numRemesa, 3, '0')
                + ".txt";
        System.out.println("Generando " + nombre + " con " + buenos.size() + " recibos");

        FileWriter fw = new FileWriter(SALIDA + "/" + nombre);
        fw.write(cabecera(numRemesa));
        long total = 0;
        for (int i = 0; i < buenos.size(); i++) {
            Recibo r = (Recibo) buenos.get(i);
            fw.write(detalle(r));
            total = total + Utils.centimos(r.getImporte());
        }
        fw.write(totales(buenos.size(), total));
        fw.close();
        comprobarRemesa(SALIDA + "/" + nombre, buenos.size(), total);

        // se marcan como enviados (el fichero se copia despues, en el paso siguiente)
        for (int i = 0; i < buenos.size(); i++) {
            Recibo r = (Recibo) buenos.get(i);
            Statement up = Conexion.get().createStatement();
            up.executeUpdate("UPDATE RECIBOS SET ESTADO = 'E', NUM_REMESA = " + numRemesa
                    + ", FECHA_ENVIO = CURRENT_TIMESTAMP WHERE NUM_RECIBO = '" + r.getNumRecibo() + "'");
            up.close();
        }
        Statement ins = Conexion.get().createStatement();
        ins.executeUpdate("INSERT INTO REMESAS (NUMERO, FICHERO, FECHA_GENERACION, NUM_RECIBOS, TOTAL_CENTIMOS) VALUES ("
                + numRemesa + ", '" + nombre + "', CURRENT_TIMESTAMP, " + buenos.size() + ", " + total + ")");
        ins.close();

        Estado.ficheroRemesa = nombre;
        Estado.numRemesa = numRemesa;
        Estado.remesados = buenos.size();
        Estado.totalCentimos = total;
    }

    // "envia" la remesa. De momento es copiarla a la carpeta enviados, luego la recoge el programa del banco
    public void enviar() throws Exception {
        if (Estado.ficheroRemesa == null) {
            System.out.println("No hay remesa que enviar");
            return;
        }
        File origen = new File(SALIDA + "/" + Estado.ficheroRemesa);
        File destino = new File(ENVIADOS + "/" + Estado.ficheroRemesa);
        Utils.copiar(origen, destino);
        System.out.println("Remesa copiada a " + ENVIADOS);
        // TODO cuando el banco nos de el sftp hay que subirla alli (ab 2015-11)
    }

    // lee el fichero otra vez y comprueba que cuadra el numero de registros y el total
    private void comprobarRemesa(String ruta, int esperados, long totalEsperado) throws Exception {
        BufferedReader br = new BufferedReader(new FileReader(ruta));
        int registros = 0;
        long suma = 0;
        String linea;
        while ((linea = br.readLine()) != null) {
            if (linea.startsWith("02")) {
                registros++;
                suma = suma + Long.parseLong(linea.substring(50, 60));
            }
        }
        br.close();
        if (registros != esperados || suma != totalEsperado) {
            throw new Exception("La remesa no cuadra: " + registros + " registros y " + suma + " centimos");
        }
        System.out.println("Remesa comprobada: " + registros + " registros, " + suma + " centimos");
    }

    private int siguienteNumero() throws Exception {
        Statement st = Conexion.get().createStatement();
        ResultSet rs = st.executeQuery("SELECT MAX(NUMERO) FROM REMESAS");
        int n = 0;
        if (rs.next()) {
            n = rs.getInt(1);
        }
        rs.close();
        st.close();
        return n + 1;
    }

    // Validaciones que pide el banco. Son las mismas de la carga (R002 y R004) por si algo ha cambiado en la base de datos
    private String[] validarParaBanco(Recibo r) {
        // R002 importe maximo
        if (r.getImporte() >= 6000.00) {
            return new String[] { "R002", "Importe " + Utils.importe(r.getImporte()) + " superior al maximo de 6000,00" };
        }
        // R004 iban
        if (!ibanOk(r.getIban())) {
            return new String[] { "R004", "IBAN no valido: " + r.getIban() };
        }
        return null;
    }

    private boolean ibanOk(String iban) {
        if (iban == null || iban.length() != 24) {
            return false;
        }
        String r = iban.substring(4) + iban.substring(0, 4);
        StringBuffer sb = new StringBuffer();
        for (int i = 0; i < r.length(); i++) {
            char c = r.charAt(i);
            if (c >= '0' && c <= '9') {
                sb.append(c);
            } else if (c >= 'A' && c <= 'Z') {
                sb.append((int) c - 55);
            } else {
                return false;
            }
        }
        return new BigInteger(sb.toString()).mod(BigInteger.valueOf(97)).intValue() == 1;
    }

    private void rechazarEnRemesa(Recibo r, String[] error) throws Exception {
        System.out.println("  NO SE REMESA " + r.getNumRecibo() + " " + error[0] + " " + error[1]);
        Statement st = Conexion.get().createStatement();
        st.executeUpdate("UPDATE RECIBOS SET ESTADO = 'R' WHERE NUM_RECIBO = '" + r.getNumRecibo() + "'");
        st.executeUpdate("INSERT INTO RECIBOS_RECHAZADOS (FICHERO, LINEA, NUM_RECIBO, CODIGO, MOTIVO, ORIGEN, FECHA) VALUES "
                + "('-', 0, '" + r.getNumRecibo() + "', '" + error[0] + "', '" + Utils.comillas(error[1])
                + "', 'REMESA', CURRENT_TIMESTAMP)");
        st.close();
        Estado.rechazadosRemesa++;
        Estado.errorRemesa = error[0] + " " + r.getNumRecibo();
    }

    // 01 + nif ordenante (9) + nombre (30) + iban de abono (24) + fecha ddMMyyyy (8) + numero de remesa (6) + relleno
    private String cabecera(int numRemesa) {
        String s = "01" + ORDENANTE_NIF + Utils.rellenarDer(ORDENANTE_NOMBRE, 30) + ORDENANTE_IBAN
                + Utils.fechaCorta(new Date()) + Utils.rellenarIzq("" + numRemesa, 6, '0');
        return Utils.rellenarDer(s, 120) + "\r\n";
    }

    // 02 + recibo (12) + poliza (12) + iban (24) + importe en centimos (10) + fecha de cargo (8) + mandato (20) + nombre (30)
    private String detalle(Recibo r) {
        String s = "02" + Utils.rellenarDer(r.getNumRecibo(), 12) + Utils.rellenarDer(r.getPoliza(), 12)
                + Utils.rellenarDer(r.getIban(), 24) + Utils.rellenarIzq("" + Utils.centimos(r.getImporte()), 10, '0')
                + Utils.fechaCorta(r.getFechaCargo()) + Utils.rellenarDer(r.getMandato(), 20)
                + Utils.rellenarDer(r.getNombreTomador().toUpperCase(), 30);
        return Utils.rellenarDer(s, 120) + "\r\n";
    }

    // 09 + numero de registros (6) + total en centimos (12)
    private String totales(int registros, long total) {
        String s = "09" + Utils.rellenarIzq("" + registros, 6, '0') + Utils.rellenarIzq("" + total, 12, '0');
        return Utils.rellenarDer(s, 120) + "\r\n";
    }
}
