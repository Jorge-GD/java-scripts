package com.acme.demo;

/** Totales de juguete: un reboxing y un campo que solo se usa como local. */
public class Totales {

    private int acumulado;

    /** Problema 1: el valor se desempaqueta y se vuelve a empaquetar enseguida. */
    public Integer copiar(Integer valor) {
        return Integer.valueOf(valor.intValue());
    }

    /** Problema 2: el campo se escribe y se lee solo aqui, como si fuera una variable local. */
    public int sumar(int[] valores) {
        acumulado = 0;
        for (int v : valores) {
            acumulado += v;
        }
        return acumulado;
    }
}
