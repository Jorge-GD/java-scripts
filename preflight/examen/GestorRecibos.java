package com.acme.recibos;

import java.io.File;
import java.io.FileWriter;
import java.math.BigInteger;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.Date;
import java.util.Hashtable;
import java.util.Vector;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import com.acme.recibos.util.Utils;

// Carga de recibos: lee los CSV de la carpeta de entrada, los valida, los guarda
// en la base de datos y apunta los rechazados.
// (aqui esta todo junto para no andar saltando de clase en clase, ab)
@Component
public class GestorRecibos {

    // carpetas, cuelgan de batch.home
    private static final String RAIZ = System.getProperty("batch.home", "C:\\batch\\recibos");
    private static final String ENTRADA = RAIZ + File.separator + "entrada";
    private static final String PROCESADOS = RAIZ + File.separator + "procesados";
    private static final String ERRORES = RAIZ + File.separator + "errores";

    // limites de negocio
    private static final double IMPORTE_MIN = 5.0;
    private static final double IMPORTE_MAX = 6000.0;
    private static final int MAX_RECHAZOS = 10; // por fichero
    private static final int DIAS_RETENCION = 90; // los procesados se borran a los 90 dias

    @Autowired
    private ParserCsv parser;

    @Autowired
    private Avisador avisador;

    // lo que se va leyendo del fichero actual
    private static int numLinea = 0;
    private static Hashtable vistos = new Hashtable();
    private static FileWriter ficheroErrores = null;

    private void procesarFichero(File f) throws Exception {
        System.out.println("Procesando " + f.getName());
        Estado.ficheroActual = f.getName();
        Estado.rechazadosFichero = 0;
        vistos.clear();
        numLinea = 0;
        int cargadosAntes = Estado.cargados;
        int leidosAntes = Estado.leidos;
        Date fechaFichero = Utils.fechaDelNombre(f.getName());
        abrirErrores(f.getName());

        Vector lineas = parser.leerLineas(f);
        System.out.println("  El fichero trae " + lineas.size() + " lineas (con la cabecera), fecha " + Utils.fecha(fechaFichero));
        for (int i = 0; i < lineas.size(); i++) {
            String linea = (String) lineas.get(i);
            numLinea++;
            if (numLinea == 1) {
                parser.comprobarCabecera(linea);
                continue; // la primera linea es la cabecera
            }
            if (linea.trim().length() == 0) {
                continue;
            }
            Estado.leidos++;

            Recibo r = null;
            String[] rechazo = null;
            try {
                r = parser.parsear(linea);
                r.setLinea(numLinea);
            } catch (Exception e) {
                rechazo = new String[] { "R010", "Linea mal formada: " + e.getMessage() };
            }

            if (rechazo == null) {
                rechazo = validar(r, fechaFichero);
            }

            if (rechazo == null) {
                guardar(r);
                Estado.cargados++;
            } else {
                String num = (r != null) ? r.getNumRecibo() : parser.primerCampo(linea);
                rechazar(f.getName(), numLinea, num, rechazo[0], rechazo[1]);
            }
        }

        ficheroErrores.write("-- " + f.getName() + ": " + (Estado.leidos - leidosAntes) + " leidos, "
                + (Estado.cargados - cargadosAntes) + " cargados, " + Estado.rechazadosFichero + " rechazados\r\n");
        ficheroErrores.flush();
        registrarCarga(f.getName(), Estado.leidos - leidosAntes, Estado.cargados - cargadosAntes, Estado.rechazadosFichero);

        // mover el fichero a procesados
        File destino = Utils.mover(f, PROCESADOS);
        System.out.println("Fichero movido a " + destino.getName());
        Estado.ficherosProcesados++;
    }

    // Devuelve null si el recibo es valido, o {codigo, motivo} de la primera regla que falla
    private String[] validar(Recibo r, Date fechaFichero) throws SQLException {

        // R001 importe minimo
        if (r.getImporte() < IMPORTE_MIN) {
            return new String[] { "R001", "Importe " + Utils.importe(r.getImporte()) + " inferior al minimo de 5,00" };
        }

        // R002 importe maximo
        if (r.getImporte() > IMPORTE_MAX) {
            return new String[] { "R002", "Importe " + Utils.importe(r.getImporte()) + " superior al maximo de 6000,00" };
        }

        // R003 solo se admite el euro
        if (!r.getMoneda().equals("EUR")) {
            String nombreMoneda = (String) Utils.MONEDAS.get(r.getMoneda());
            if (nombreMoneda == null) {
                nombreMoneda = "desconocida";
            }
            return new String[] { "R003", "Moneda " + r.getMoneda() + " (" + nombreMoneda + ") no admitida, solo EUR" };
        }

        // R004 iban
        if (!ibanValido(r.getIban())) {
            return new String[] { "R004", "IBAN no valido: " + r.getIban() };
        }

        // R005 fecha de cargo
        String[] errorFecha = validarFecha(r, fechaFichero);
        if (errorFecha != null) {
            return errorFecha;
        }

        // R006 mandato
        String[] errorMandato = validarMandato(r);
        if (errorMandato != null) {
            return errorMandato;
        }

        // R007 poliza
        String[] errorPoliza = validarPoliza(r);
        if (errorPoliza != null) {
            return errorPoliza;
        }

        // R008 duplicados
        Integer previa = (Integer) vistos.get(r.getNumRecibo());
        if (previa != null) {
            return new String[] { "R008", "Recibo duplicado en el fichero (ya viene en la linea " + previa + ")" };
        }
        vistos.put(r.getNumRecibo(), new Integer(numLinea));
        Statement st = Conexion.get().createStatement();
        ResultSet rs = st.executeQuery("SELECT COUNT(*) FROM RECIBOS WHERE NUM_RECIBO = '" + r.getNumRecibo() + "'");
        rs.next();
        int ya = rs.getInt(1);
        rs.close();
        st.close();
        if (ya > 0) {
            return new String[] { "R008", "Recibo ya cargado anteriormente" };
        }

        // if (!r.getNifTomador().matches("[0-9]{8}[A-Z]")) {
        //     return new String[] { "R0xx", "NIF no valido" };   // lo quito, hay NIE y CIF y daba mil rechazos
        // }
        // TODO comprobar que el NIF del tomador es el de la poliza (ab 2015-06)

        return null;
    }

    private String[] validarFecha(Recibo r, Date fechaFichero) {
        Date fc = r.getFechaCargo();
        if (fc == null) {
            return new String[] { "R005", "Fecha de cargo mal formada: '" + r.getFechaTexto() + "'" };
        }
        if (fc.before(fechaFichero)) {
            return new String[] { "R005", "Fecha de cargo " + Utils.fecha(fc) + " anterior a la del fichero "
                    + Utils.fecha(fechaFichero) };
        }
        if (Utils.diasEntre(fechaFichero, fc) > 45) {
            return new String[] { "R005", "Fecha de cargo " + Utils.fecha(fc) + " a mas de 45 dias del fichero" };
        }
        if (Utils.esFinDeSemana(fc)) {
            return new String[] { "R005", "Fecha de cargo " + Utils.fecha(fc) + " cae en sabado o domingo" };
        }
        return null;
    }

    private String[] validarMandato(Recibo r) throws SQLException {
        Statement st = Conexion.get().createStatement();
        ResultSet rs = st.executeQuery("SELECT IBAN, ESTADO FROM MANDATOS WHERE REFERENCIA = '" + r.getMandato() + "'");
        if (!rs.next()) {
            return new String[] { "R006", "Mandato " + r.getMandato() + " inexistente" };
        }
        String ibanMandato = rs.getString("IBAN");
        String estado = rs.getString("ESTADO");
        rs.close();
        st.close();
        if (estado.equals("R")) {
            return new String[] { "R006", "Mandato " + r.getMandato() + " revocado" };
        }
        if (!ibanMandato.equals(r.getIban())) {
            return new String[] { "R006", "Mandato " + r.getMandato() + " pertenece a otro IBAN" };
        }
        return null;
    }

    private String[] validarPoliza(Recibo r) throws SQLException {
        Statement st = Conexion.get().createStatement();
        ResultSet rs = st.executeQuery("SELECT ESTADO FROM POLIZAS WHERE NUMERO = '" + r.getPoliza() + "'");
        if (!rs.next()) {
            return new String[] { "R007", "Poliza " + r.getPoliza() + " inexistente" };
        }
        String estado = rs.getString(1);
        rs.close();
        st.close();
        // A = activa, S = suspendida, B = baja
        if (!estado.equals("A")) {
            return new String[] { "R007", "Poliza " + r.getPoliza() + " no esta activa (estado " + estado + ")" };
        }
        return null;
    }

    // digitos de control del IBAN (mod 97)
    private boolean ibanValido(String iban) {
        if (iban == null || iban.length() != 24) {
            return false;
        }
        if (!iban.startsWith("ES")) {
            return false;
        }
        // se pasan los 4 primeros al final y las letras a numeros (A=10...)
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
        BigInteger n = new BigInteger(sb.toString());
        return n.mod(new BigInteger("97")).intValue() == 1;
    }

    private void guardar(Recibo r) throws SQLException {
        String sql = "INSERT INTO RECIBOS (NUM_RECIBO, POLIZA, NIF_TOMADOR, NOMBRE_TOMADOR, IMPORTE, MONEDA, IBAN, "
                + "FECHA_CARGO, MANDATO, ESTADO, FICHERO_ORIGEN, FECHA_ALTA) VALUES ('"
                + r.getNumRecibo() + "', '" + r.getPoliza() + "', '" + r.getNifTomador() + "', '"
                + Utils.comillas(r.getNombreTomador()) + "', " + r.getImporte() + ", '" + r.getMoneda() + "', '"
                + r.getIban() + "', '" + Utils.fechaIso(r.getFechaCargo()) + "', '" + r.getMandato() + "', 'P', '"
                + Estado.ficheroActual + "', CURRENT_TIMESTAMP)";
        Statement st = Conexion.get().createStatement();
        st.executeUpdate(sql);
        st.close();
    }

    private void rechazar(String fichero, int linea, String numRecibo, String codigo, String motivo) throws Exception {
        Estado.rechazados++;
        Estado.rechazadosFichero++;
        Estado.rechazos.add(new ReciboRechazado(fichero, linea, numRecibo, codigo, motivo));

        String sql = "INSERT INTO RECIBOS_RECHAZADOS (FICHERO, LINEA, NUM_RECIBO, CODIGO, MOTIVO, ORIGEN, FECHA) VALUES ('"
                + fichero + "', " + linea + ", '" + Utils.comillas(numRecibo) + "', '" + codigo + "', '"
                + Utils.comillas(motivo) + "', 'CARGA', CURRENT_TIMESTAMP)";
        Statement st = Conexion.get().createStatement();
        st.executeUpdate(sql);
        st.close();

        ficheroErrores.write(fichero + ";" + linea + ";" + numRecibo + ";" + codigo + ";" + motivo + "\r\n");
        ficheroErrores.flush();
        System.out.println("  RECHAZADO linea " + linea + " " + numRecibo + " " + codigo + " " + motivo);

        // R009 tope de rechazos: si el fichero viene muy mal se para todo
        if (Estado.rechazadosFichero > MAX_RECHAZOS) {
            ficheroErrores.write("R009 tope de rechazos superado en " + fichero + "\r\n");
            ficheroErrores.flush();
            throw new IllegalStateException("R009 Tope de rechazos superado en " + fichero + " (mas de "
                    + MAX_RECHAZOS + ")");
        }
    }
}
