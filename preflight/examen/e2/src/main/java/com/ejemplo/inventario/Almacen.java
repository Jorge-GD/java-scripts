package com.ejemplo.inventario;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeSet;

public class Almacen {

    public static final int MAXIMO_POR_REFERENCIA = 500;

    public record Movimiento(String referencia, int cantidad) {
    }

    private final Map<String, Integer> existencias = new HashMap<>();
    private final List<Movimiento> historial = new ArrayList<>();

    public Almacen() {
    }

    public void entrada(String referencia, int cantidad) {
        if (cantidad <= 0) {
            throw new IllegalArgumentException("La cantidad tiene que ser positiva");
        }
        int nueva = existencias(referencia) + cantidad;
        if (nueva > MAXIMO_POR_REFERENCIA) {
            throw new IllegalStateException("Se pasa del maximo por referencia: " + MAXIMO_POR_REFERENCIA);
        }
        existencias.put(referencia, nueva);
        anotar(referencia, cantidad);
    }

    public boolean salida(String referencia, int cantidad) {
        int actual = existencias(referencia);
        if (cantidad <= 0 || cantidad > actual) {
            return false;
        }
        existencias.put(referencia, actual - cantidad);
        anotar(referencia, -cantidad);
        return true;
    }

    public int existencias(String referencia) {
        return existencias.getOrDefault(referencia, 0);
    }

    public List<String> agotadas() {
        TreeSet<String> agotadas = new TreeSet<>();
        for (Map.Entry<String, Integer> e : existencias.entrySet()) {
            if (e.getValue() == 0) {
                agotadas.add(e.getKey());
            }
        }
        return new ArrayList<>(agotadas);
    }

    public List<Movimiento> historial() {
        return List.copyOf(historial);
    }

    public int total() {
        int suma = 0;
        for (int v : existencias.values()) {
            suma += v;
        }
        return suma;
    }

    public String ayuda() {
        return "Manual en http://ejemplo.invalid/almacen // sin version"; // enlace de ejemplo
    }

    private void anotar(String referencia, int cantidad) {
        historial.add(new Movimiento(referencia, cantidad));
    }
}
