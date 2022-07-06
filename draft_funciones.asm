Funciones a crear:

// Subrutina que actualiza la posicion del servo X, recibe por parametro la tecla presionada
// para saber que posicion actualizar.
+ update_x_position

// Subrutina que aumenta la posicion en X (va de 0 a 180). Similar a check_switch_1
+ increase_x_position ---> DONE
 
// Subrutina que decrementa la posicion en X (va de 180 a 0). Similar a check_switch_2
+ decrease_x_position ---> DONE

// Lo mismo pero para Y

+ update_y_position 

+ increase_y_position ---> DONE
+ decrease_y_position ---> DONE

// Cambia el modo del programa y actualiza las interrupciones habilitadas.
// Si pasas de modo manual a remoto, desactivas la interrupcion que escucha al joystick
// Si pasas de remoto a manual se mantiene todo igual. Para facilitar el codigo podemos llamar a los sets de abajo
+ change_mode ---> DONE

+ set_remote_mode ---> DONE

+ set_manual_mode ---> DONE

// Las siguientes tienen que habiliat la interrupcion correspondiente a convertir lo del joystick
+ disable_joystick_interruption:

+ enable_joystick_interruption:

// Muestra la secuencia inicial que realiza el ojo. Arriba, abajo, izquierda, derecha, centro
+ initial_sequence: Solo si alcanza el tiempo hacerla

+ handlers de las excepciones de puerto serie (Serial)

+ handlers de las excepciones del joystick (ADC)

+ handlers de los timers 0 y 2. El timer 1 no necesita handlear nada



// Creo que vamos a tener que convertir primero el valor de X y despues el de Y o viceversa, pero como solo hay un registro para el resultado
// una vez que termino de convertir X convierto Y


// Podemos hacer que si el valor es distinto de 512, para evitar errores +- 5, entonces lo tenes que mover
// para saber a que direccion te fijas si es mayor o menor que ese valor de referencia. Una vez que tenes eso entras a mover el servo
// en esa direccion y dependiendo del valor mapeado establezco el step

// Version incial: armas una cruz de leds y dependiendo a donde muevas el joystick encendes uno u otro

/*
		Rojo
Azul 	Verde 	Amarillo
		Rojo
*/