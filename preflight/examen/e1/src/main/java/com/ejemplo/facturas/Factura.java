package com.ejemplo.facturas;

import java.math.BigDecimal;
import java.text.SimpleDateFormat;
import java.time.LocalDate;
import java.util.Date;

import com.ejemplo.lib.Calendario;
import com.ejemplo.lib.Tarifa;

public class Factura {

    private static final BigDecimal IVA = new BigDecimal("0.21");
    private static final int DIAS_DE_PAGO = 30;

    private final String numero;
    private final BigDecimal base;
    private final LocalDate emision;

    public Factura(String numero, BigDecimal base, LocalDate emision) {
        this.numero = numero;
        this.base = base;
        this.emision = emision;
    }

    public String numero() {
        return numero;
    }

    public BigDecimal total() {
        return Tarifa.aplicar(base);
    }

    public String vencimiento() {
        Date vence = Calendario.vencimiento(emision, DIAS_DE_PAGO);
        return new SimpleDateFormat("dd/MM/yyyy").format(vence);
    }
}
