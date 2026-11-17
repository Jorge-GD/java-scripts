package com.ejemplo.service;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

class SaludoTest {
    @Test
    void saludaPorNombre() {
        assertEquals("hola, Ana", new Saludo().hola("Ana"));
    }
}
