;*************************************************************************************
; Trabajo practico Integrador
;
; El trabajo practico consiste en hacer un ojo animatronico el cual puede controlarse
; por teclado en caso de que el programa este en modo REMOTO o con un joystick si se
; encuentra en modo MANUAL.
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

// Incluimos las definiciones de los registros y las constantes
.include "definitions.asm"

.cseg 	; Segmento de memoria de codigo
.org 0x0000
	rjmp start

.org ADCCaddr
	rjmp 	handle_adc_conversion

.org URXCaddr
    rjmp isr_dato_recibido_usart

.org INT_VECTORS_SIZE
// Inlcuimos las definiciones de otros modulos
.include "config.asm"
.include "USART.asm"
.include "ADC.asm"
start:

; Se inicializa el Stack Pointer al final de la RAM utilizando la definicion global
; RAMEND
	ldi		r16, HIGH(RAMEND)
	out		sph, r16
	ldi		r16, LOW(RAMEND)
	out		spl, r16.

	; Realizo las configuraciones iniciales
	rcall	configure_ports		; Configuro los puertos
	rcall	configure_timer_1	; Configuro el WGM de los timers
	rcall 	configure_adc 		; Configuro el ADC
	rcall	USART_Init			; Inicializo el USART
	rcall	configure_usart_interrupt ; Configurar interrupciones del teclado

	clr		MODE
	clr 	FLAG_CONVERT_X ; Limpio el registro para asegurarme de que este en cero
	inc 	FLAG_CONVERT_X ; Cargo un 1 dado que siempre convierto primero X
	
	rcall 	set_default_position_servos
	rcall show_init_msg ;mostrar mensaje inicial

	rcall 	initialize_timer1 	; Inicializo el timer encargado de mover el servo
	rcall 	adc_start_conversion
	sei		; Habilito las interrupciones

// REMOTO === TECLADO
// MANUAL === JOYSTCIK
main_loop:
	rjmp	main_loop

;*************************************************************************************
; Subrutina que cambia el modo en el que se encuentra el programa.
; Al cambiar de modo los servos vuelven a su posicion default
;
;*************************************************************************************
change_mode:
	push 	AUX_REGISTER
	clr 	AUX_REGISTER
	mov 	AUX_REGISTER, MODE ; Copio el valor de MODE en AUX_REGISTER
	cpi 	AUX_REGISTER, REMOTE ; Chequeo si se encuentra en modo remoto
	breq 	change_to_manual ; Lo paso a manual
	rcall 	set_remote_mode ; Se encontraba en modo manual, lo paso a remoto
	rjmp 	end_change_mode

change_to_manual:
	rcall 	set_manual_mode

end_change_mode:
	rcall 	set_default_position_servos
	pop 	AUX_REGISTER
	ret

;*************************************************************************************
; Subrutina que setea el modo del programa en MANUAL
;	
;*************************************************************************************
set_manual_mode:
	push 	AUX_REGISTER
	ldi 	AUX_REGISTER, MANUAL
	mov 	MODE, AUX_REGISTER ; Mode = MANUAL
	rcall 	enable_adc ; Habilitamos nuevamente las conversiones del ADC
	rcall   adc_start_conversion
	pop 	AUX_REGISTER
	ret

;*************************************************************************************
; Subrutina que setea el modo del programa en REMOTO
;	
;*************************************************************************************
set_remote_mode:
	push 	AUX_REGISTER
	ldi 	AUX_REGISTER, REMOTE
	mov 	MODE, AUX_REGISTER ; Mode = REMOTE
	rcall 	disable_adc ; Dejamos de hacer las conversiones del ADC
	pop 	AUX_REGISTER
	ret

;*************************************************************************************
; Subrutina que setea ambos servos a su posicion default de 90°
;	
;*************************************************************************************
set_default_position_servos:
	ldi 	SERVO_X_POSITION, SERVO_INITIAL_POS ; SERVO_X_POSITION = 90°
	rcall 	set_OCR1A
	ldi 	SERVO_Y_POSITION, SERVO_INITIAL_POS ; SERVO_Y_POSITION = 90°
	rcall 	set_OCR1B
	ret

;*************************************************************************************
; Subrutina que incrementa la posicion del servo en X
;	
;*************************************************************************************
increase_x_position:
	push 	AUX_REGISTER
	push 	AUX_REGISTER_2
	push	AUX_REGISTER_3
	mov 	AUX_REGISTER, SERVO_X_POSITION ; Cargo en el registro auxiliar el valor actual del servo
	rcall 	check_servo_upper_limit
	mov		AUX_REGISTER_3, FLAG
	cpi 	AUX_REGISTER_3, 0x01 ; Comparo el registro auxiliar con 1, si son iguales estoy en el limite, no realizo nada mas
	breq 	end_increase_x_position
	// No me encuentro en el limite, actualizo la posicion
	ldi 	AUX_REGISTER, SERVO_STEP
	add 	SERVO_X_POSITION, AUX_REGISTER ; SERVO_X_POSITION = SERVO_X_POSITION + SERVO_STEP
	cpi 	SERVO_X_POSITION, UPPER_LIMIT ; Comparo para ver si no pase el limite, en caso de hacerlo seteo el UPPER_LIMIT
	brlo 	end_increase_x_position
	ldi 	SERVO_X_POSITION, UPPER_LIMIT ; SERVO_X_POSITION = UPPER_LIMIT

end_increase_x_position:
	rcall	set_OCR1A
	pop		AUX_REGISTER_3
	pop  	AUX_REGISTER_2
	pop  	AUX_REGISTER
	ret

;*************************************************************************************
; Subrutina que decrementa la posicion del servo en X
;	
;*************************************************************************************
decrease_x_position:
	push 	AUX_REGISTER
	push 	AUX_REGISTER_2
	push	AUX_REGISTER_3
	mov 	AUX_REGISTER, SERVO_X_POSITION ; Cargo en el registro auxiliar el valor actual del servo
	rcall 	check_servo_lower_limit
	mov		AUX_REGISTER_3, FLAG
	cpi 	AUX_REGISTER_3, 0x01 ; Comparo el registro auxiliar con 1, si son iguales estoy en el limite, no realizo nada mas
	breq 	end_decrease_x_position
	// No me encuentro en el limite, actualizo la posicion
	subi 	SERVO_X_POSITION, SERVO_STEP ; SERVO_X_POSITION = SERVO_X_POSITION - SERVO_STEP
	cpi 	SERVO_X_POSITION, LOWER_LIMIT ; Comparo para ver si no pase el limite, en caso de hacerlo seteo el LOWER_LIMIT
	brsh 	end_decrease_x_position
	ldi 	SERVO_X_POSITION, LOWER_LIMIT ; SERVO_X_POSITION = LOWER_LIMIT

end_decrease_x_position:
	rcall	set_OCR1A
	pop		AUX_REGISTER_3
	pop  	AUX_REGISTER_2
	pop  	AUX_REGISTER
	ret

;*************************************************************************************
; Subrutina que incrementa la posicion del servo en Y
;	
;*************************************************************************************
increase_y_position:
	push 	AUX_REGISTER
	push 	AUX_REGISTER_2
	push	AUX_REGISTER_3
	mov 	AUX_REGISTER, SERVO_Y_POSITION ; Cargo en el registro auxiliar el valor actual del servo
	rcall 	check_servo_upper_limit
	mov		AUX_REGISTER_3, FLAG
	cpi 	AUX_REGISTER_3, 0x01 ; Comparo el registro auxiliar con 1, si son iguales estoy en el limite, no realizo nada mas
	breq 	end_increase_y_position
	// No me encuentro en el limite, actualizo la posicion
	ldi 	AUX_REGISTER, SERVO_STEP
	add 	SERVO_Y_POSITION, AUX_REGISTER ; SERVO_Y_POSITION = SERVO_Y_POSITION + SERVO_STEP
	cpi 	SERVO_Y_POSITION, UPPER_LIMIT ; Comparo para ver si no pase el limite, en caso de hacerlo seteo el UPPER_LIMIT
	brlo 	end_increase_y_position
	ldi 	SERVO_Y_POSITION, UPPER_LIMIT ; SERVO_Y_POSITION = UPPER_LIMIT

end_increase_y_position:
	rcall	set_OCR1B
	pop		AUX_REGISTER_3
	pop  	AUX_REGISTER_2
	pop  	AUX_REGISTER
	ret

;*************************************************************************************
; Subrutina que decrementa la posicion del servo en Y
;	
;*************************************************************************************
decrease_y_position:
	push 	AUX_REGISTER
	push 	AUX_REGISTER_2
	push	AUX_REGISTER_3
	mov 	AUX_REGISTER, SERVO_Y_POSITION ; Cargo en el registro auxiliar el valor actual del servo
	rcall 	check_servo_lower_limit
	mov		AUX_REGISTER_3, FLAG
	cpi 	AUX_REGISTER_3, 0x01 ; Comparo el registro auxiliar con 1, si son iguales estoy en el limite, no realizo nada mas
	breq 	end_decrease_y_position
	// No me encuentro en el limite, actualizo la posicion
	subi 	SERVO_Y_POSITION, SERVO_STEP ; SERVO_Y_POSITION = SERVO_Y_POSITION - SERVO_STEP
	cpi 	SERVO_Y_POSITION, LOWER_LIMIT ; Comparo para ver si no pase el limite, en caso de hacerlo seteo el LOWER_LIMIT
	brsh 	end_decrease_y_position
	ldi 	SERVO_Y_POSITION, LOWER_LIMIT ; SERVO_Y_POSITION = LOWER_LIMIT

end_decrease_y_position:
	rcall	set_OCR1B
	pop		AUX_REGISTER_3
	pop  	AUX_REGISTER_2
	pop  	AUX_REGISTER
	ret

;*************************************************************************************
; Subrutina que chequea si el servo se encuentra en su limite superior. Si es asi,
; FLAG se carga con 1, 0 en caso contrario.
; AUX_REGISTER posee el valor del servo a chequear si se encuentra en su limite
;
;*************************************************************************************
check_servo_upper_limit:
	clr 	FLAG ; Limpio el registro
	cpi 	AUX_REGISTER, UPPER_LIMIT ; Chequeo si el valor del servo solicitado es igual al UPPER_LIMIT (155)
	brne 	end_check_upper_limit ; No son iguales, termino la funcion
	inc 	FLAG ; Pongo un 1 en el flag dado que se encuentra en el limite superior

end_check_upper_limit:
	ret		

;*************************************************************************************
; Subrutina que chequea si el servo se encuentra en su limite inferior. Si es asi,
; FLAG se carga con 1, 0 en caso contrario
; AUX_REGISTER posee el valor del servo a chequear si se encuentra en su limite
;
;*************************************************************************************
check_servo_lower_limit:
	clr 	FLAG ; Limpio el registro
	cpi 	AUX_REGISTER, LOWER_LIMIT ; Chequeo si el valor del servo solicitado es igual al LOWER_LIMIT (35)
	brne 	end_check_lower_limit ; No son iguales, termino la funcion
	inc 	FLAG ; Pongo un 1 en el flag dado que se encuentra en el limite inferior

end_check_lower_limit:
	ret

;*************************************************************************************
; Subrutina que setea el valor de OCR1A. El valor que va a tomar esta dado por el
; contenido que tenga el registro SERVO_X_POSITION
;
;*************************************************************************************
set_OCR1A:
	// Primero escribo el high byte y luego el low
	push 	AUX_REGISTER
	clr 	AUX_REGISTER
	sts 	OCR1AH, AUX_REGISTER ; El High byte siempre es cero ya que el maximo valor que puede tomar el OCR1A es 155
	sts 	OCR1AL, SERVO_X_POSITION
	pop 	AUX_REGISTER
	ret

;*************************************************************************************
; Subrutina que setea el valor de OCR1B. El valor que va a tomar esta dado por el
; contenido que tenga el registro SERVO_Y_POSITION
;
;*************************************************************************************
set_OCR1B:
	// Primero escribo el high byte y luego el low
	push 	AUX_REGISTER
	clr AUX_REGISTER
	sts OCR1BH, AUX_REGISTER ; El High byte siempre es cero ya que el maximo valor que puede tomar el OCR1B es 155
	sts OCR1BL, SERVO_Y_POSITION
	pop 	AUX_REGISTER
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
	push 	AUX_REGISTER
	clr 	AUX_REGISTER ; Limpio el registro
	sts 	TCNT1H, AUX_REGISTER ; Pongo en cero el contador del timer 1
	sts 	TCNT1L, AUX_REGISTER
	lds  	AUX_REGISTER, TCCR1B ; AUX_REGISTER = TCCR1B
	andi 	AUX_REGISTER, CLR_CLOCK_SELECTOR ; Realizo un AND con 0xF8 = b1111 1000

	; Configuro el Clock Selector con prescaling igual a 256
	ori 	AUX_REGISTER, (1 << CS12)
	sts 	TCCR1B, AUX_REGISTER
	pop 	AUX_REGISTER
	ret

//len = 45
//Tabla con el mensaje "Envíe R para pasar a control por modo remoto" en ASCII
MSJ: .DB 69, 110, 118, 195, 173, 101, 32, 82, 32, 112, 97, 114, 97, 32, \
112, 97, 115, 97, 114, 32, 97, 32, 99, 111, 110, 116, 114, 111, 108, 32, 112, \
111, 114, 32, 109, 111, 100, 111, 32, 114, 101, 109, 111, 116, 111, 0