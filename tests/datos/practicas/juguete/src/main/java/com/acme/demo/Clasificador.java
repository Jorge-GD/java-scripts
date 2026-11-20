package com.acme.demo;

import java.util.List;

/** Clasificador de juguete: una complejidad cognitiva alta y un campo privado sin uso. */
public class Clasificador {

    /** Problema 4: campo privado que nadie usa. */
    private String sinUso = "x";

    /** Problema 3: complejidad cognitiva de 20, con anidamiento. */
    public int clasificar(List<List<Integer>> grupos, int limite) {
        int resultado = 0;
        for (List<Integer> grupo : grupos) {
            if (grupo == null) {
                continue;
            }
            for (Integer n : grupo) {
                if (n > limite) {
                    if (n % 2 == 0) {
                        resultado += 2;
                    } else if (n % 3 == 0) {
                        resultado += 3;
                    } else {
                        resultado += 1;
                    }
                } else if (n < 0) {
                    while (resultado > 0 && n < -limite) {
                        resultado--;
                    }
                }
            }
        }
        return resultado;
    }
}
