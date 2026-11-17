package com.ejemplo.lib;

import java.time.LocalDate;

/**
 * Libreria de fechas, version 3. Trabaja con java.time: ya no devuelve java.util.Date.
 */
public final class Calendario {

    private Calendario() {
    }

    public static LocalDate vencimiento(LocalDate emision, int dias) {
        return emision.plusDays(dias);
    }
}
