;*************************************************************************************
; Trabajo practico Integrador
;
; Integrantes:
;
; Nombre: 	Violeta 
; Apellido: Perez Andrade
; Padron: 	101456
;
; Nombre: 	Lisandro 
; Apellido: Torresetti
; Padron: 	99846
;
;*************************************************************************************

.include "m328Pdef.inc"
.dseg 	; Segmento de datos en memoria RAM
.org 	SRAM_START

; Defino los conjuntos de segmentos, pines y puertos a utilizar

.equ 	SERVO_X_PIN_NUM		= 1
.equ 	SERVO_Y_PIN_NUM		= 2 
.equ	SERVOS_PORT			= PORTB
.equ	SERVOS_DIR			= DDRB

// ToDo: Vamos a tener que usar los overflows para mover los servos un poco mas tranquis
.equ 	OVERFLOW_LIMIT_1 	= 3 	; Cantidad de overflows a contar en el timer0 y timer2 la primera vez que se aprieta un switch
.equ 	OVERFLOW_LIMIT_2	= 10 	; Cantidad de overflows a contar en el timer0 y timer2 mientras se mantiene apretado un switch
.equ 	CLR_CLOCK_SELECTOR 	= 0xF8 	; Mascara para setear en cero el Clock Selector de un timer

// Si tenemos el teclado deberiamos usar esto, pero quizas con un limite mas chico arriba asi es mas fluido
.equ 	SERVO_STEP			= 2 	; Se va a mover el OCR1A y OCR1B entre [35, 155] con un step de 2 para ir de 0 a 180 grados
.equ 	MIN_SERVO_STEP 		= 4 	; Velocidad normal para mover el servo
.equ 	MAX_SERVO_STEP 		= 6 	; Para mover mas rapido en caso de que el joystick se encuentre en los extremos
.equ 	SERVO_INITIAL_POS 	= 95 	; Posicion inicial de los servos, equivale a 90°
.equ 	LOWER_LIMIT 		= 35 	; Limite inferior para ambos servos (OCR1A y OCR1B)
.equ 	UPPER_LIMIT 		= 155 	; Limite superior para el servos (OCR1A y OCR1B)
.equ 	REMOTE 				= 1 	; Valor para indicar que se encuentra en modo remoto
.equ 	MANUAL 				= 0 	; Valor para indicar que se encuentra en modo manual

// Los switches pasan a ser cosas del teclado ahora
.def 	MODE 				= r1 	; Registro que guarda el modo en el cual se encuentra el programa
.def 	DEBOUNCE_1_FINISHED = r16 	; Registro para chequear si el debounce del switch 1 finalizo
.def 	DEBOUNCE_2_FINISHED = r17 	; Registro para chequear si el debounce del switch 2 finalizo
.def 	DEBOUNCE_1_TOP 		= r18 	; Registro que contendra la cantidad de overflows a contar del timer 0
.def 	DEBOUNCE_2_TOP 		= r19 	; Registro que contendra la cantidad de overflows a contar del timer 2
.def 	OVERFLOW_1_COUNTER 	= r20 	; Registro que contara la cantidad de overflows que ocurrieron 		
.def 	OVERFLOW_2_COUNTER 	= r21
.def 	SERVO_X_POSITION	= r22 	; Registro que contendra el valor en el que se encuentra el servo X (Low byte)
.def 	SERVO_Y_POSITION	= r23 	; Registro que contendra el valor en el que se encuentra el servo Y (Low byte)
.def	AUX_REGISTER		= r24	; Registro auxiliar para multiples propositos
.def 	AUX_REGISTER_2 		= r25 	; Registro auxiliar para multiples propositos

.cseg 	; Segmento de memoria de codigo
.org 0x0000
	rjmp start

.org INT0addr
	rjmp	handle_int_ext0

.org INT1addr
	rjmp	handle_int_ext1

.org OVF0addr
	rjmp 	handle_timer0_overflow

.org OVF2addr
	rjmp 	handle_timer2_overflow

.org ADCCaddr
	rjmo 	handle_adc_conversion

.org INT_VECTORS_SIZE

start:

; Se inicializa el Stack Pointer al final de la RAM utilizando la definicion global
; RAMEND
	ldi		r16, HIGH(RAMEND)
	out		sph, r16
	ldi		r16, LOW(RAMEND)
	out		spl, r16.

	; Realizo las configuraciones iniciales
	rcall	configure_ports		; Configuro los puertos
	rcall	configure_timers	; Configuro el WGM de los timers
	rcall	configure_int0		; Configuro la int0
	rcall	configure_int1		; Configuro la int1

	; Habilito las interrupciones
	rcall	enable_int0
	rcall	enable_int1
	rcall 	enable_timers_interrupts

	clr		DEBOUNCE_1_FINISHED ; Limpio los registros para que comiencen en cero
	clr		DEBOUNCE_2_FINISHED
	rcall 	initialize_timer1 ; Inicializo el timer encargado de mover el servo
	sei		; Habilito las interrupciones

main_loop:
	sbrc 	DEBOUNCE_1_FINISHED, 0 ; Si el valor del primer bit menos significativo es cero, salteo la siguiente instruccion
	rcall 	check_switch_1
	sbrc 	DEBOUNCE_2_FINISHED, 0 
	rcall 	check_switch_2
	rjmp	main_loop

// ToDo: las siguientes funciones cambiar para las teclas, creo que en modo REMOTO las teclas
// deberian funcionar de manera similar a los switches, CREO 
// REMOTO === TECLADO
// MANUAL === JOYSTCIK

;*************************************************************************************
; Subrutina que cambia el modo en el que se encuentra el programa.
;	
;*************************************************************************************
change_mode:
	clr 	AUX_REGISTER
	mov 	AUX_REGISTER, MODE ; Copio el valor de MODE en AUX_REGISTER
	cpi 	AUX_REGISTER, REMOTE ; Chequeo si se encuentra en modo remoto
	breq 	change_to_manual ; Lo paso a manual
	rcall 	set_remote_mode ; Se encontraba en modo manual, lo paso a remoto
	rjmp 	end_change_mode

change_to_manual:
	rcall 	set_manual_mode

end_change_mode:
	ret

;*************************************************************************************
; Subrutina que setea el modo del programa en MANUAL
;	
;*************************************************************************************
set_manual_mode:
	ldi 	AUX_REGISTER, MANUAL
	mov 	MODE, AUX_REGISTER ; Mode = MANUAL
	// ToDo: habilitar la interrupcion correspodiente para que pueda convertir adc, quizas deberia mandar el ojo a su posicion inicial
	ret

;*************************************************************************************
; Subrutina que setea el modo del programa en REMOTO
;	
;*************************************************************************************
set_manual_mode:
	ldi 	AUX_REGISTER, REMOTE
	mov 	MODE, AUX_REGISTER ; Mode = REMOTE
	// ToDo: deshabilitar la interrupcion correspodiente para que pueda convertir adc, quizas deberia mandar el ojo a su posicion inicial
	ret

;*************************************************************************************
; Subrutina que setea ambos servos a 90°
;	
;*************************************************************************************
set_initial_position_servos:
	ldi 	SERVO_X_POSITION, SERVO_INITIAL_POS ; SERVO_X_POSITION = 90°
	rcall 	set_OCR1A
	ldi 	SERVO_Y_POSITION, SERVO_INITIAL_POS ; SERVO_Y_POSITION = 90°
	rcall 	set_OCR1B
	ret

;*************************************************************************************
; Subrutina que actualiza la posicion del servo X
;	
;*************************************************************************************
update_x_position:
	// ToDo: chequear si te fijas aca si se mueve para la izquierda o derecha, o sea aca analizas lo de ADC
	// Si lo queres hacer de forma general podrias hacer un if mode === remote {codigo remote} else {codigo manual}
	// En manual analizas el ADCH|ADCL, mientras que en remoto las teclas
	ret

;*************************************************************************************
; Subrutina que incrementa la posicion del servo en X
;	
;*************************************************************************************
increase_x_position:
	ldi 	AUX_REGISTER_2, SERVO_X_POSITION ; Cargo en el registro auxiliar el valor actual del servo
	rcall 	check_servo_upper_limit
	cpi 	AUX_REGISTER, 0x01 ; Comparo el registro auxiliar con 1, si son iguales estoy en el limite, no realizo nada mas
	breq 	end_increase_x_position
	// No me encuentro en el limite, actualizo la posicion
	ldi 	AUX_REGISTER, SERVO_STEP
	add 	SERVO_X_POSITION, AUX_REGISTER ; SERVO_X_POSITION = SERVO_X_POSITION + SERVO_STEP
	cpi 	SERVO_X_POSITION, UPPER_LIMIT ; Comparo para ver si no pase el limite, en caso de hacerlo seteo el UPPER_LIMIT
	brlo 	end_increase_x_position
	ldi 	SERVO_X_POSITION, UPPER_LIMIT ; SERVO_X_POSITION = UPPER_LIMIT

end_increase_x_position:
	ret

;*************************************************************************************
; Subrutina que decrementa la posicion del servo en X
;	
;*************************************************************************************
decrease_x_position:
	ldi 	AUX_REGISTER_2, SERVO_X_POSITION ; Cargo en el registro auxiliar el valor actual del servo
	rcall 	check_servo_lower_limit
	cpi 	AUX_REGISTER, 0x01 ; Comparo el registro auxiliar con 1, si son iguales estoy en el limite, no realizo nada mas
	breq 	end_decrease_x_position
	// No me encuentro en el limite, actualizo la posicion
	subi 	SERVO_X_POSITION, SERVO_STEP ; SERVO_X_POSITION = SERVO_X_POSITION - SERVO_STEP
	cpi 	SERVO_X_POSITION, LOWER_LIMIT ; Comparo para ver si no pase el limite, en caso de hacerlo seteo el LOWER_LIMIT
	brlo 	end_decrease_x_position
	ldi 	SERVO_X_POSITION, LOWER_LIMIT ; SERVO_X_POSITION = LOWER_LIMIT

end_decrease_x_position:
	ret

;*************************************************************************************
; Subrutina que actualiza la posicion del servo Y
;	
;*************************************************************************************
update_y_position:
	// ToDo: va a ser una calcomania de lo de X
	ret

;*************************************************************************************
; Subrutina que incrementa la posicion del servo en Y
;	
;*************************************************************************************
increase_y_position:
	ldi 	AUX_REGISTER_2, SERVO_Y_POSITION ; Cargo en el registro auxiliar el valor actual del servo
	rcall 	check_servo_upper_limit
	cpi 	AUX_REGISTER, 0x01 ; Comparo el registro auxiliar con 1, si son iguales estoy en el limite, no realizo nada mas
	breq 	end_increase_y_position
	// No me encuentro en el limite, actualizo la posicion
	ldi 	AUX_REGISTER, SERVO_STEP
	add 	SERVO_Y_POSITION, AUX_REGISTER ; SERVO_Y_POSITION = SERVO_Y_POSITION + SERVO_STEP
	cpi 	SERVO_Y_POSITION, UPPER_LIMIT ; Comparo para ver si no pase el limite, en caso de hacerlo seteo el UPPER_LIMIT
	brlo 	end_increase_y_position
	ldi 	SERVO_Y_POSITION, UPPER_LIMIT ; SERVO_Y_POSITION = UPPER_LIMIT

end_increase_y_position:
	ret

;*************************************************************************************
; Subrutina que decrementa la posicion del servo en Y
;	
;*************************************************************************************
decrease_y_position:
	ldi 	AUX_REGISTER_2, SERVO_Y_POSITION ; Cargo en el registro auxiliar el valor actual del servo
	rcall 	check_servo_lower_limit
	cpi 	AUX_REGISTER, 0x01 ; Comparo el registro auxiliar con 1, si son iguales estoy en el limite, no realizo nada mas
	breq 	end_decrease_y_position
	// No me encuentro en el limite, actualizo la posicion
	subi 	SERVO_Y_POSITION, SERVO_STEP ; SERVO_Y_POSITION = SERVO_Y_POSITION - SERVO_STEP
	cpi 	SERVO_Y_POSITION, LOWER_LIMIT ; Comparo para ver si no pase el limite, en caso de hacerlo seteo el LOWER_LIMIT
	brlo 	end_decrease_y_position
	ldi 	SERVO_Y_POSITION, LOWER_LIMIT ; SERVO_Y_POSITION = LOWER_LIMIT

end_decrease_y_position:
	ret

;*************************************************************************************
; Subrutina que chequea el estado del switch 1 y actualiza la posicion del servo
;	
;*************************************************************************************
check_switch_1:
	sbic 	SWITCHES_PIN, SWITCH_1_PIN_NUM ; Salteo la proxima instruccion si el switch 1 no esta siendo presionado
	rjmp 	clear_values_switch_1 ; Fue un falso positivo

	; Para chequear en caso de que haya un cambio me aseguro de que el valor de SWITCH_1_STATE sea que esta presionado
	ldi 	AUX_REGISTER, PRESSED
	cp 		SWITCH_1_STATE, AUX_REGISTER
	brne	clear_values_switch_1 ; Si no coinciden significa que el pulsador NO esta siendo presionado

	rcall 	check_servo_lower_limit
	cpi 	AUX_REGISTER, 1 ; Comparo con 1
	breq 	end_check_switch_1 ; Finalizo el chequeo ya que no voy a poder moverlo por estar en el limite

	; Actualizo la posicion del servo, en este caso RESTO el step
	subi 	SERVO_VALUE_LOW, SERVO_STEP ; SERVO_VALUE_LOW = SERVO_VALUE_LOW - 2
	rcall 	set_OCR1A ; Actualizo el valor del 0CR1A
	ldi 	DEBOUNCE_1_TOP, OVERFLOW_LIMIT_2 ; Ahora cuento una cantidad de overflows igual al segundo limite, o sea 10
	rjmp end_check_switch_1

clear_values_switch_1:
	; Limpio los registros y apago el timer 0 ya que el pulsador no fue presionado
	ldi 	AUX_REGISTER, NOT_PRESSED 		; Cargo en AUX_REGISTER el valor de NOT_PRESSED
	mov 	SWITCH_1_STATE, AUX_REGISTER 	; SWITCH_1_STATE = NOT_PRESSED
	rcall 	stop_timer0

end_check_switch_1:
	clr 	DEBOUNCE_1_FINISHED
	ret

;*************************************************************************************
; Subrutina que chequea el estado del switch 2 y actualiza la posicion del servo
;	
;*************************************************************************************

check_switch_2:
	sbic 	SWITCHES_PIN, SWITCH_2_PIN_NUM ; Salteo la proxima instruccion si el switch 2 no esta siendo presionado
	rjmp 	clear_values_switch_2 ; Fue un falso positivo

	; Para chequear en caso de que haya un cambio me aseguro de que el valor de SWITCH_2_STATE sea que esta presionado
	ldi 	AUX_REGISTER, PRESSED
	cp 		SWITCH_2_STATE, AUX_REGISTER
	brne	clear_values_switch_2 ; Si no coinciden significa que el pulsador NO esta siendo presionado

	rcall 	check_servo_upper_limit
	cpi 	AUX_REGISTER, 1 ; Comparo con 1
	breq 	end_check_switch_2 ; Finalizo el chequeo ya que no voy a poder moverlo por estar en el limite

	; Actualizo la posicion del servo, en este caso SUMO el step
	ldi 	AUX_REGISTER, SERVO_STEP ; AUX_REGISTER = SERVO_STEP = 2
	add 	SERVO_VALUE_LOW, AUX_REGISTER ; SERVO_VALUE_LOW = SERVO_VALUE_LOW + 2  
	rcall 	set_OCR1A ; Actualizo el valor del 0CR1A
	ldi 	DEBOUNCE_2_TOP, OVERFLOW_LIMIT_2 ; Ahora cuento una cantidad de overflows igual al segundo limite, o sea 10
	rjmp end_check_switch_2

clear_values_switch_2:
	; Limpio los registros y apago el timer 0 ya que el pulsador no fue presionado
	ldi 	AUX_REGISTER, NOT_PRESSED 		; Cargo en AUX_REGISTER el valor de NOT_PRESSED
	mov 	SWITCH_2_STATE, AUX_REGISTER 	; SWITCH_2_STATE = NOT_PRESSED
	rcall 	stop_timer2

end_check_switch_2:
	clr 	DEBOUNCE_2_FINISHED
	ret

;*************************************************************************************
; Subrutina que chequea si el servo se encuentra en su limite superior. Si es asi,
; AUX_REGISTER se carga con 1, 0 en caso contrario.
; AUX_REGISTER_2 posee el valor del servo a chequear si se encuentra en su limite
;
;*************************************************************************************

check_servo_upper_limit:
	clr 	AUX_REGISTER ; Limpio el registro
	cpi 	AUX_REGISTER_2, UPPER_LIMIT ; Chequeo si el valor del servo solicitado es igual al UPPER_LIMIT (155)
	brne 	end_check_upper_limit ; No son iguales, termino la funcion
	ldi 	AUX_REGISTER, 0x01 ; Cargo un 1 en AUX_REGISTER ya que el servo se encuentra en su valor superior

end_check_upper_limit:
	ret	

;*************************************************************************************
; Subrutina que chequea si el servo se encuentra en su limite inferior. Si es asi,
; AUX_REGISTER se carga con 1, 0 en caso contrario
; AUX_REGISTER_2 posee el valor del servo a chequear si se encuentra en su limite
;
;*************************************************************************************

check_servo_lower_limit:
	clr 	AUX_REGISTER ; Limpio el registro
	cpi 	AUX_REGISTER_2, LOWER_LIMIT ; Chequeo si el valor del servo solicitado es igual al LOWER_LIMIT (35)
	brne 	end_check_lower_limit ; No son iguales, termino la funcion
	ldi 	AUX_REGISTER, 0x01 ; Cargo un 1 en AUX_REGISTER ya que el servo se encuentra en su valor inferior

end_check_lower_limit:
	ret

;*************************************************************************************
; Subrutina que setea el valor de OCR1A. El valor que va a tomar esta dado por el
; contenido que tenga el registro SERVO_X_POSITION
;
;*************************************************************************************

set_OCR1A:
	// Primero escribo el high byte y luego el low
	clr AUX_REGISTER
	sts OCR1AH, AUX_REGISTER ; El High byte siempre es cero ya que el maximo valor que puede tomar el OCR1A es 155
	sts OCR1AL, SERVO_X_POSITION
	ret

;*************************************************************************************
; Subrutina que setea el valor de OCR1B. El valor que va a tomar esta dado por el
; contenido que tenga el registro SERVO_Y_POSITION
;
;*************************************************************************************

set_OCR1B:
	// Primero escribo el high byte y luego el low
	clr AUX_REGISTER
	sts OCR1BH, AUX_REGISTER ; El High byte siempre es cero ya que el maximo valor que puede tomar el OCR1B es 155
	sts OCR1BL, SERVO_Y_POSITION
	ret

;*************************************************************************************
; Se configuran los puertos del microcontrolador como entrada/salida
;
; En este caso la configuracion es la siguiente:
; + Switch 1: se configura como entrada 
; + Switch 2: se configura como entrada
; + Servo: se configura como output
;	
;*************************************************************************************

configure_ports:
	ldi 	AUX_REGISTER, 0x00 				; Cargo el registro R16 con 0x00
	out 	SWITCHES_DIR, AUX_REGISTER 		; Cargo un cero en todos los bits del DDRD
	out 	SWITCHES_PORT, AUX_REGISTER		; Cargo un cero en todos los bits del PORTD
	out 	SERVO_DIR, AUX_REGISTER 		; Cargo un cero en todos los bits del DDRB
	sbi 	SERVOS_DIR, SERVO_X_PIN_NUM  	; Configuro el pin del servo X como output
	sbi 	SERVOS_DIR, SERVO_Y_PIN_NUM  	; Configuro el pin del servo Y como output 	

	sbi 	SWITCHES_PORT, SWITCH_1_PIN_NUM ; Activo la resistencia de Pull-up del pulsador 1, PORTD2 = 1
	sbi 	SWITCHES_PORT, SWITCH_2_PIN_NUM ; Activo la resistencia de Pull-up del pulsador 2, PORTD3 = 1
	ret

;*************************************************************************************
; Subrutina que configura los timers 0, 1 y 2
;	
;*************************************************************************************

configure_timers:
	rcall configure_timer_0
	rcall configure_timer_1
	rcall configure_timer_2
	ret

;*************************************************************************************
; Subrutina que configura el Timer 0
;
; Mode: Normal
; + WGM02: 0
; + WGM01: 0
; + WGM00: 0
;*************************************************************************************

configure_timer_0:
	// TCCR0A
	clr 	AUX_REGISTER ; Limpio el registro
	in 		AUX_REGISTER, TCCR0A ; AUX_REGISTER = TCCR0A
	andi 	AUX_REGISTER, 0x1C ; Realizo uno AND con 0x1C = 1111 1100
	out 	TCCR0A, AUX_REGISTER ; Cargo el contenido de AUX_REGISTER en TCCR0A

	// TCCR0B
	clr 	AUX_REGISTER ; Limpio el registro
	in 		AUX_REGISTER, TCCR0B ; AUX_REGISTER = TCCR0B
	andi 	AUX_REGISTER, 0xF7 ; Realizo uno AND con 0xF7 = 1111 0111
	out 	TCCR0B, AUX_REGISTER ; Cargo el contenido de AUX_REGISTER en TCCR0B

	ret

;*************************************************************************************
; Subrutina que configura el Timer 1
;
; Mode: PWM, Fast PWM (14)
; + WGM13: 1
; + WGM12: 1
; + WGM11: 1
; + WGM10: 0
;
; OCR1A initial value: 0 
;
; Compare Output Mode:
; + COM1A1: 1
; + COM1A0: 0
;*************************************************************************************	

configure_timer_1:
	// Configuro TCCR1A
	clr 	AUX_REGISTER ; Limpio el registro
	lds 	AUX_REGISTER, TCCR1A ; AUX_REGISTER = TCCR1A
	andi 	AUX_REGISTER, 0xFC ; Realizo un AND con 0x3C = 0011 1100
	ori 	AUX_REGISTER, (1 << WGM11) ; Realizo un OR para configurar el WGM
	ori 	AUX_REGISTER, (1 << COM1A1) ; Realizo un OR para configurar el Compare Output Mode
	sts 	TCCR1A, AUX_REGISTER ; Paso el contenido del AUX_REGISTER a TCCR1A

	// Configuro TCCR1B
	clr 	AUX_REGISTER ; Limpio el registro
	lds 	AUX_REGISTER, TCCR1B ; AUX_REGISTER = TCCR1B
	andi 	AUX_REGISTER, 0xE3 ; Realizo un AND con 0xE3 = 1110 0111
	ori 	AUX_REGISTER, (1 << WGM13) | (1 << WGM12) ; Realizo un OR para configurar el WGM
	sts 	TCCR1B, AUX_REGISTER ; Paso el contenido del AUX_REGISTER a TCCR1B

	// Configuro el TOP (ICR1) del Timer 1, primero escribo el high byte y luego el low
	// ICR1H | ICR1L = 0000 0100 | 1110 0001 = 1249 (0x04E1), de esta forma el periodo es de 20ms
	ldi		AUX_REGISTER, 0x04 ; Cargo un 4 en AUX_REGISTER
	sts		ICR1H, AUX_REGISTER ; ICR1H = 0000 0100
	ldi		AUX_REGISTER, 0xE1 ; Cargo 0xE1 en el registro
	sts		ICR1L, AUX_REGISTER ; ICR1L = 1110 0001

	ldi 	SERVO_VALUE_LOW, LOWER_LIMIT ; Cargo el LOWER_LIMIT en SERVO_VALUE_LOW, asi siempre arranca con el mismo pulso
	rcall 	set_OCR1A
	ret

;*************************************************************************************
; Subrutina que configura el Timer 2
;
; Mode: Normal
; + WGM22: 0
; + WGM21: 0
; + WGM20: 0
;*************************************************************************************

configure_timer_2:
	// TCCR2A
	clr 	AUX_REGISTER ; Limpio el registro
	lds 	AUX_REGISTER, TCCR2A ; AUX_REGISTER = TCCR2A
	andi 	AUX_REGISTER, 0x1C ; Realizo uno AND con 0x1C = 1111 1100
	sts 	TCCR2A, AUX_REGISTER ; Cargo el contenido de AUX_REGISTER en TCCR2A

	// TCCR2B
	clr 	AUX_REGISTER ; Limpio el registro
	lds 	AUX_REGISTER, TCCR2B ; AUX_REGISTER = TCCR2B
	andi 	AUX_REGISTER, 0xF7 ; Realizo uno AND con 0xF7 = 1111 0111
	sts 	TCCR2B, AUX_REGISTER ; Cargo el contenido de AUX_REGISTER en TCCR2B
	ret

;*************************************************************************************
; Subrutina que habilita las interrupciones de los Timers 0 y 2
;
;*************************************************************************************

enable_timers_interrupts:
	// Configuro la interrupcion por overflow del Timer 0
	lds AUX_REGISTER, TIMSK0 ; AUX_REGISTER = TIMSK0
	ori AUX_REGISTER, (1 << TOIE0)
	sts TIMSK0, AUX_REGISTER

	// Configuro la interrupcion por overflow del Timer 2
	lds	AUX_REGISTER, TIMSK2 ; AUX_REGISTER = TIMSK2
	ori AUX_REGISTER, (1 << TOIE2)
	sts TIMSK2, AUX_REGISTER
	ret

;*************************************************************************************
; Subrutina que inicializa el Timer 0
;
; Clock Selector: clk / 1024
; + CS02: 1
; + CS01: 0
; + CS00: 1
;	
;*************************************************************************************

initialize_timer0:
	clr 	AUX_REGISTER ; Limpio el registro
	sts 	TCNT0, AUX_REGISTER ; Pongo en cero el contador
	in  	AUX_REGISTER, TCCR0B ; AUX_REGISTER = TCCR0B
	andi 	AUX_REGISTER, CLR_CLOCK_SELECTOR ; Realizo un AND con 0xF8 = b1111 1000

	; Configuro el Clock Selector con prescaling igual a 1024
	ori 	AUX_REGISTER, (1 << CS02) | (1 << CS00)
	out 	TCCR0B, AUX_REGISTER
	ret

;*************************************************************************************
; Subrutina que apaga el Timer 0
;	
;*************************************************************************************

stop_timer0:
	clr 	AUX_REGISTER 						; Limpio el registro
	in	 	AUX_REGISTER, TCCR0B 				; AUX_REGISTER = TCCR0B
	andi 	AUX_REGISTER, CLR_CLOCK_SELECTOR 	; Realizo un AND con 0xF8 = b1111 1000 
	out 	TCCR0B, AUX_REGISTER
	ret

;*************************************************************************************
; Subrutina que inicializa el Timer 1
;
; Clock Selector: clk / 256
; + CS12: 1
; + CS11: 0
; + CS10: 0	
;*************************************************************************************

initialize_timer1:
	clr 	AUX_REGISTER ; Limpio el registro
	sts 	TCNT1H, AUX_REGISTER ; Pongo en cero el contador del timer 1
	sts 	TCNT1L, AUX_REGISTER
	lds  	AUX_REGISTER, TCCR1B ; AUX_REGISTER = TCCR1B
	andi 	AUX_REGISTER, CLR_CLOCK_SELECTOR ; Realizo un AND con 0xF8 = b1111 1000

	; Configuro el Clock Selector con prescaling igual a 256
	ori 	AUX_REGISTER, (1 << CS12)
	sts 	TCCR1B, AUX_REGISTER
	ret

;*************************************************************************************
; Subrutina que inicializa el Timer 2
;
; Clock Selector: clk / 1024
; + CS22: 1
; + CS21: 1
; + CS20: 1	
;*************************************************************************************

initialize_timer2:
	clr 	AUX_REGISTER ; Limpio el registro
	sts 	TCNT2, AUX_REGISTER ; Pongo en cero el contador
	lds  	AUX_REGISTER, TCCR2B ; AUX_REGISTER = TCCR2B
	andi 	AUX_REGISTER, CLR_CLOCK_SELECTOR ; Realizo un AND con 0xF8 = 1111 1000
	; Configuro el Clock Selector con prescaling igual a 1024
	ori 	AUX_REGISTER, (1 << CS22) | (1 << CS21) | (1 << CS20)
	sts 	TCCR2B, AUX_REGISTER
	ret

;*************************************************************************************
; Subrutina que apaga el Timer 2
;	
;*************************************************************************************

stop_timer2:
	clr 	AUX_REGISTER ; Limpio el registro
	lds 	AUX_REGISTER, TCCR2B
	andi 	AUX_REGISTER, CLR_CLOCK_SELECTOR ; Realizo un AND con 0xF8 = b1111 1000 
	sts 	TCCR2B, AUX_REGISTER
	ret

;*************************************************************************************
; Configura la interrupcion externa 0 (INT0) para flanco acendente y descendente
;
;*************************************************************************************

configure_int0:
	lds  AUX_REGISTER, EICRA
	ori  AUX_REGISTER, (1 << ISC00) | (0 << ISC01)
	sts  EICRA, AUX_REGISTER
	ret

;*************************************************************************************
; Habilita la interrupcion externa 0 (INT0)
;
;*************************************************************************************

enable_int0:
	in	AUX_REGISTER, EIMSK
	ori	AUX_REGISTER, (1 << INT0)
	out EIMSK, AUX_REGISTER
	ret

;*************************************************************************************
; Configura la interrupcion externa 1 (INT1) para flanco acendente y descendente
;
;*************************************************************************************

configure_int1:
	lds  AUX_REGISTER, EICRA
	ori  AUX_REGISTER, (1 << ISC10) | (0 << ISC11)
	sts  EICRA, AUX_REGISTER 
	ret
	
;*************************************************************************************
; Habilita la interrupcion externa 1 (INT1)
;
;*************************************************************************************

enable_int1:
	in  AUX_REGISTER, EIMSK
	ori AUX_REGISTER, (1 << INT1)
	out EIMSK, AUX_REGISTER
	ret


; ***************************** INTERRUPT HANDLERS ***********************************

;*************************************************************************************
; Handler de la interrupción externa 0 (INT0)
;
;*************************************************************************************

handle_int_ext0:
	; Guardo en el stack los siguientes valores de los registros
	push 	AUX_REGISTER
	in	 	AUX_REGISTER, SREG
	push 	AUX_REGISTER

	clr 	DEBOUNCE_1_FINISHED ; Limpio el valor de los registros
	clr 	OVERFLOW_1_COUNTER

	; Chequeo si me encuentro en el limite inferior, si es asi finalizo la interrupcion dado que no podre mover el servo
	rcall 	check_servo_lower_limit
	cpi 	AUX_REGISTER, 1
	breq 	turn_off_timer0

	sbic 	SWITCHES_PIN, SWITCH_1_PIN_NUM ; Si el pulsador es presionado salteo la siguiente instruccion
	rjmp 	turn_off_timer0 ; No esta siendo presionado, apago el timer0 para dejar de mover el servo
	ldi 	DEBOUNCE_1_TOP, OVERFLOW_LIMIT_1 ; Cuento OVERFLOW_LIMIT_1 (3) overflows por ser la primera vez
	rcall 	initialize_timer0
	ldi 	AUX_REGISTER, PRESSED ; AUX_REGISTER = PRESSED
	mov 	SWITCH_1_STATE, AUX_REGISTER ; Cargo el contenido de AUX_REGISTER en SWITCH_1_STATE, o sea SWITCH_1_STATE = PRESSED
	rjmp 	end_handle_int0

turn_off_timer0:
	rcall 	stop_timer0
	ldi 	AUX_REGISTER, NOT_PRESSED ; Cargo en AUX_REGISTER el valor de NOT_PRESSED
	mov 	SWITCH_1_STATE, AUX_REGISTER ; SWITCH_1_STATE = NOT_PRESSED

end_handle_int0:
	; Recupero los valores de los registros
	pop 	AUX_REGISTER
	out 	SREG, AUX_REGISTER
	pop 	AUX_REGISTER
	reti

;*************************************************************************************
; Handler de la interrupción externa 1 (INT1)
;
;*************************************************************************************

handle_int_ext1:
	; Guardo en el stack los siguientes valores de los registros
	push 	AUX_REGISTER
	in	 	AUX_REGISTER, SREG
	push 	AUX_REGISTER

	clr 	DEBOUNCE_2_FINISHED ; Limpio el valor de los registros
	clr 	OVERFLOW_2_COUNTER

	; Chequeo si me encuentro en el limite superior, si es asi finalizo la interrupcion dado que no podre mover el servo
	rcall 	check_servo_upper_limit
	cpi 	AUX_REGISTER, 1
	breq 	turn_off_timer2

	sbic 	SWITCHES_PIN, SWITCH_2_PIN_NUM ; Si el pulsador es presionado salteo la siguiente instruccion
	rjmp 	turn_off_timer2 ; No esta siendo presionado, apago el timer2 para dejar de mover el servo
	ldi 	DEBOUNCE_2_TOP, OVERFLOW_LIMIT_1 ; Cuento OVERFLOW_LIMIT_1 (3) overflows por ser la primera vez
	rcall 	initialize_timer2
	ldi 	AUX_REGISTER, PRESSED ; AUX_REGISTER = PRESSED
	mov 	SWITCH_2_STATE, AUX_REGISTER ; Cargo el contenido de AUX_REGISTER en SWITCH_2_STATE, o sea SWITCH_2_STATE = PRESSED
	rjmp 	end_handle_int1

turn_off_timer2:
	rcall 	stop_timer2
	ldi 	AUX_REGISTER, NOT_PRESSED ; Cargo en AUX_REGISTER el valor de NOT_PRESSED
	mov 	SWITCH_2_STATE, AUX_REGISTER ; SWITCH_2_STATE = NOT_PRESSED

end_handle_int1:
	; Recupero los valores de los registros
	pop 	AUX_REGISTER
	out 	SREG, AUX_REGISTER
	pop 	AUX_REGISTER
	reti

;*************************************************************************************
; Handler del overflow del Timer0
;
;*************************************************************************************

handle_timer0_overflow:
	; Guardo en el stack los siguientes valores de los registros
	push 	AUX_REGISTER
	in	 	AUX_REGISTER, SREG
	push 	AUX_REGISTER
	
	cp 		DEBOUNCE_1_TOP, OVERFLOW_1_COUNTER ; Veo si se dieron la cantidad de overflows que necesito para el delay
	breq 	stop_debounce_timer0
	inc 	OVERFLOW_1_COUNTER ; Incremento en uno la cantidad de overflows que se captaron hasta el momento
	rjmp 	end_timer0_overflow

stop_debounce_timer0:
	clr 	OVERFLOW_1_COUNTER 	; Limpio el contador de overflows
	inc 	DEBOUNCE_1_FINISHED ; Seteo en el registro un 1 para indicar que finalizo el debounce del switch 1

end_timer0_overflow:
	; Recupero los valores de los registros
	pop 	AUX_REGISTER
	out 	SREG, AUX_REGISTER
	pop 	AUX_REGISTER
	reti


;*************************************************************************************
; Handler del overflow del Timer2
;
;*************************************************************************************

handle_timer2_overflow:
	; Guardo en el stack los siguientes valores de los registros
	push 	AUX_REGISTER
	in	 	AUX_REGISTER, SREG
	push 	AUX_REGISTER

	cp 		DEBOUNCE_2_TOP, OVERFLOW_2_COUNTER ; Veo si se dieron la cantidad de overflows que necesito para el delay
	breq 	stop_debounce_timer2
	inc 	OVERFLOW_2_COUNTER ; Incremento en uno la cantidad de overflows que se captaron hasta el momento
	rjmp 	end_timer2_overflow

stop_debounce_timer2:
	clr 	OVERFLOW_2_COUNTER 	; Limpio el contador de overflows
	inc 	DEBOUNCE_2_FINISHED ; Seteo en el registro un 1 para indicar que finalizo el debounce del switch 2

end_timer2_overflow:
	; Recupero los valores de los registros
	pop 	AUX_REGISTER
	out 	SREG, AUX_REGISTER
	pop 	AUX_REGISTER
	reti

;*************************************************************************************
; Handler del ADC
;
;*************************************************************************************
handle_adc_conversion:
; Guardo en el stack los siguientes valores de los registros
	push 	AUX_REGISTER
	push 	AUX_REGISTER_2
	in	 	AUX_REGISTER, SREG
	push 	AUX_REGISTER

	// ToDo: add code

	; Recupero los valores de los registros
	pop 	AUX_REGISTER
	out 	SREG, AUX_REGISTER
	pop 	AUX_REGISTER_2
	pop 	AUX_REGISTER
	reti
	reti