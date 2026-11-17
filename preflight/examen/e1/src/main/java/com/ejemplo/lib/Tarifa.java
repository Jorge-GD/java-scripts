package com.ejemplo.lib;

import java.math.BigDecimal;
import java.math.RoundingMode;

/**
 * Libreria de tarifas, version 3. Desde esta version el impuesto y el modo de
 * redondeo se indican en cada llamada.
 */
public final class Tarifa {

    private Tarifa() {
    }

    public static BigDecimal aplicar(BigDecimal base, BigDecimal impuesto, RoundingMode redondeo) {
        return base.add(base.multiply(impuesto)).setScale(2, redondeo);
    }
}
