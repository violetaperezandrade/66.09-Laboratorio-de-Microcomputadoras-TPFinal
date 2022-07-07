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
.equ	DEBUG_PIN_NUM		= 3

.equ 	ADC_X_PIN_NUM 		= 0
.equ 	ADC_Y_PIN_NUM 		= 1
.equ 	ADC_PORT 			= PORTC
.equ 	ADC_PIN 			= PINC
.equ 	ADC_DIR 			= DDRC

.equ 	CLR_CLOCK_SELECTOR 	= 0xF8 	; Mascara para setear en cero el Clock Selector de un timer

.equ 	SERVO_STEP			= 1 	; Se va a mover el OCR1A y OCR1B entre [35, 155] con un step de 1 para ir de 0 a 180 grados
.equ 	SERVO_INITIAL_POS 	= 95 	; Posicion inicial de los servos, equivale a 90°
.equ 	LOWER_LIMIT 		= 35 	; Limite inferior para ambos servos (OCR1A y OCR1B)
.equ 	UPPER_LIMIT 		= 155 	; Limite superior para ambos servos (OCR1A y OCR1B)
.equ 	REMOTE 				= 1 	; Valor para indicar que se encuentra en modo remoto
.equ 	MANUAL 				= 0 	; Valor para indicar que se encuentra en modo manual
.equ 	CLEAR_CHANNEL 		= 0xF8 	; Valor para borrar el channel seleccionado en el ADC

// Los switches pasan a ser cosas del teclado ahora
.def 	MODE 				= r1 	; Registro que guarda el modo en el cual se encuentra el programa
.def 	ADC_HIGH 			= r2  	; Registro donde se guardara el HIGH byte de la conversion de ADC
.def 	ADC_LOW 			= r3  	; Registro donde se guardara el LOW byte de la conversion de ADC
.def 	MAPPED_VALUE  		= r4 	; Registro donde se guardar el resultado de hacer un mapeo del valor del ADC en la funcion map_value
.def 	FLAG 				= r5 	; Registro que sera utilizado como flag
.def 	SERVO_X_POSITION	= r22 	; Registro que contendra el valor en el que se encuentra el servo X (Low byte)
.def 	SERVO_Y_POSITION	= r23 	; Registro que contendra el valor en el que se encuentra el servo Y (Low byte)
.def	AUX_REGISTER		= r23	; Registro auxiliar para multiples propositos
.def 	AUX_REGISTER_2 		= r24 	; Registro auxiliar para multiples propositos
.def 	AUX_REGISTER_3 		= r25	; Registro auxiliar para multiples propositos

.cseg 	; Segmento de memoria de codigo
.org 0x0000
	rjmp start

.org ADCCaddr
	rjmp 	handle_adc_conversion

.org URXCaddr
    jmp isr_dato_recibido_usart

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
	sei		; Habilito las interrupciones
	rcall show_init_msg2 ;mostrar ensaje inicial

main_loop:
	rjmp	main_loop

// ToDo: las siguientes funciones cambiar para las teclas, creo que en modo REMOTO las teclas
// deberian funcionar de manera similar a los switches, CREO 
// REMOTO === TECLADO
// MANUAL === JOYSTCIK

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
	rcall 	enable_adc
	pop 	AUX_REGISTER
	ret

;*************************************************************************************
; Subrutina que setea el modo del programa en REMOTO
;	
;*************************************************************************************
set_remote_mode:
	ldi 	AUX_REGISTER, REMOTE
	mov 	MODE, AUX_REGISTER ; Mode = REMOTE
	rcall 	disable_adc
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
	rcall configure_timer_1
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
	push 	AUX_REGISTER
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

;*************************************************************************************
; Subrutina que habilita el ADC
; + ADEN = 1
;
;*************************************************************************************
enable_adc:
	push  	AUX_REGISTER
	clr 	AUX_REGISTER
	lds 	AUX_REGISTER, ADCSRA ; AUX_REGISTER = ADCSRA
	ori 	AUX_REGISTER, (1 << ADEN) ; Cargo un 1 en el bit de ADEN
	sts 	ADCSRA, AUX_REGISTER ; Paso el contendio del registr oal ADCSRA
	pop  	AUX_REGISTER
	ret

;*************************************************************************************
; Subrutina que deshabilita el ADC
; + ADEN = 0
;
;*************************************************************************************
disable_adc:
	push  	AUX_REGISTER
	clr 	AUX_REGISTER
	lds 	AUX_REGISTER, ADCSRA ; AUX_REGISTER = ADCSRA
	andi 	AUX_REGISTER, 0x7F ; Realizo un AND con 0111 1111 para desactivar el ADEN
	sts 	ADCSRA, AUX_REGISTER ; Paso el contendio del registr oal ADCSRA
	pop  	AUX_REGISTER
	ret


; ***************************** INTERRUPT HANDLERS ***********************************

;*************************************************************************************
; Subrutinas de configuracion lectura y escritura de USART
;
;*************************************************************************************

USART_Init:
	; Set baud rate
	push r16
	push r17
	ldi r16, 103
	ldi r17, 0
	sts UBRR0H, r17
	sts UBRR0L, r16
	; Enable receiver and transmitter
	ldi r16, (1<<RXEN0)|(1<<TXEN0)
	sts UCSR0B,r16
	; Set frame format: 8data, 2stop bit
	ldi r16, (1<<USBS0)|(3<<UCSZ00)
	sts UCSR0C,r16
	pop r17
	pop r16
	ret

USART_Transmit:
	; Wait for empty transmit buffer
	lds r17,UCSR0A
	sbrs r17,UDRE0
	rjmp USART_Transmit
	; Put data (r16) into buffer, sends the data
	sts UDR0,r16
	ret
	
USART_Receive:
	; Wait for data to be received
	lds r17, UCSR0A
	sbrs r17, RXC0
	rjmp USART_Receive
	; Get and return received data from buffer
	lds r16, UDR0
	ret


//len = 45
//Tabla con el mensaje "Envíe R para pasar a control por modo remoto" en ASCII
MSJ: .DB 69, 110, 118, 195, 173, 101, 32, 82, 32, 112, 97, 114, 97, 32, \
112, 97, 115, 97, 114, 32, 97, 32, 99, 111, 110, 116, 114, 111, 108, 32, 112, \
111, 114, 32, 109, 111, 100, 111, 32, 114, 101, 109, 111, 116, 111