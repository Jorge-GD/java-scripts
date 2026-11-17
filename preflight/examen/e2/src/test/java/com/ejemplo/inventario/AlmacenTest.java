package com.ejemplo.inventario;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.List;

import org.junit.jupiter.api.Test;

class AlmacenTest {

    @Test
    void entradaYSalidaCambianLasExistencias() {
        Almacen a = new Almacen();
        a.entrada("A-1", 10);
        assertTrue(a.salida("A-1", 4));
        assertEquals(6, a.existencias("A-1"));
        assertEquals(6, a.total());
    }

    @Test
    void noSeSacaMasDeLoQueHay() {
        Almacen a = new Almacen();
        a.entrada("A-1", 3);
        assertFalse(a.salida("A-1", 4));
        assertEquals(3, a.existencias("A-1"));
    }

    @Test
    void noSePasaDelMaximoNiSeEntraCeroOMenos() {
        Almacen a = new Almacen();
        assertThrows(IllegalArgumentException.class, () -> a.entrada("A-1", 0));
        a.entrada("A-1", Almacen.MAXIMO_POR_REFERENCIA);
        assertThrows(IllegalStateException.class, () -> a.entrada("A-1", 1));
    }

    @Test
    void agotadasYHistorial() {
        Almacen a = new Almacen();
        a.entrada("B-2", 2);
        a.entrada("A-1", 1);
        a.salida("B-2", 2);
        assertEquals(List.of("B-2"), a.agotadas());
        assertEquals(3, a.historial().size());
        assertEquals(new Almacen.Movimiento("B-2", -2), a.historial().get(2));
    }

    @Test
    void laAyudaNoCambia() {
        assertEquals("Manual en http://ejemplo.invalid/almacen // sin version", new Almacen().ayuda());
    }
}
