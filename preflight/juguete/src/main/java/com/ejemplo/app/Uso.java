package com.ejemplo.app;

import com.ejemplo.service.Saludo;

public class Uso {
    private final Saludo saludo = new Saludo();

    public String saludar(String nombre) {
        return saludo.hola(nombre);
    }
}
