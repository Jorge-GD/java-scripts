package com.ejemplo.facturas;

import static org.junit.jupiter.api.Assertions.assertEquals;

import java.math.BigDecimal;
import java.time.LocalDate;

import org.junit.jupiter.api.Test;

class FacturaTest {

    @Test
    void totalConIva() {
        Factura f = new Factura("F-1", new BigDecimal("100.00"), LocalDate.of(2025, 3, 1));
        assertEquals(new BigDecimal("121.00"), f.total());
    }

    @Test
    void totalRedondeaLaMitadHaciaArriba() {
        Factura f = new Factura("F-2", new BigDecimal("2.50"), LocalDate.of(2025, 3, 1));
        assertEquals(new BigDecimal("3.03"), f.total());
    }

    @Test
    void vencimientoATreintaDias() {
        Factura f = new Factura("F-3", new BigDecimal("10.00"), LocalDate.of(2025, 3, 1));
        assertEquals("31/03/2025", f.vencimiento());
    }
}
