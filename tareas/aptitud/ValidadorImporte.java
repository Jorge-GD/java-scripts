package ejemplo;

import java.math.BigDecimal;

/** Clase de juguete para la prueba de aptitud: valida el importe de un recibo. */
public class ValidadorImporte {

    private static final BigDecimal MAXIMO = new BigDecimal("1000000");

    /** Devuelve true si el importe es mayor que cero y no pasa del máximo. */
    public boolean esValido(BigDecimal importe) {
        if (importe.signum() <= 0) {
            return false;
        }
        return importe.compareTo(MAXIMO) <= 0;
    }
}
