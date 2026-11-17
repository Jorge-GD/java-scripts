package com.ejemplo.service;

public class Saludo {
    public String hola(String nombre) {
        if (nombre == null || nombre.isEmpty()) {
            return "hola";
        }
        return "hola, " + nombre;
    }
}
