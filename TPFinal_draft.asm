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
.equ 	ADC_DIR 			= DDRC

.equ 	CLR_CLOCK_SELECTOR 	= 0xF8 	; Mascara para setear en cero el Clock Selector de un timer

.equ 	SERVO_STEP			= 1 	; Se va a mover el OCR1A y OCR1B entre [35, 155] con un step de 1 para ir de 0 a 180 grados
.equ 	SERVO_INITIAL_POS 	= 95 	; Posicion inicial de los servos, equivale a 90°
.equ 	LOWER_LIMIT 		= 35 	; Limite inferior para ambos servos (OCR1A y OCR1B)
.equ 	UPPER_LIMIT 		= 155 	; Limite superior para ambos servos (OCR1A y OCR1B)
.equ 	REMOTE 				= 1 	; Valor para indicar que se encuentra en modo remoto
.equ 	MANUAL 				= 0 	; Valor para indicar que se encuentra en modo manual
.equ 	CLEAR_CHANNEL 		= 0xF8 	; Valor para borrar el channel seleccionado en el ADC

.def 	MODE 				= r1 	; Registro que guarda el modo en el cual se encuentra el programa
.def 	MAPPED_VALUE  		= r2 	; Registro donde se guardar el resultado de hacer un mapeo del valor del ADC en la funcion map_value
.def 	FLAG 				= r3 	; Registro que sera utilizado como flag
.def 	FLAG_CONVERT_X 		= r4 	; Registro para saber que canal del ADC convertir. X = 1, Y = 0
.def 	ADC_HIGH 			= r19  	; Registro donde se guardara el HIGH byte de la conversion de ADC
.def 	ADC_LOW 			= r20  	; Registro donde se guardara el LOW byte de la conversion de ADC
.def 	SERVO_X_POSITION	= r21 	; Registro que contendra el valor en el que se encuentra el servo X (Low byte)
.def 	SERVO_Y_POSITION	= r22 	; Registro que contendra el valor en el que se encuentra el servo Y (Low byte)
.def	AUX_REGISTER		= r23	; Registro auxiliar para multiples propositos
.def 	AUX_REGISTER_2 		= r24 	; Registro auxiliar para multiples propositos
.def 	AUX_REGISTER_3 		= r25	; Registro auxiliar para multiples propositos

.cseg 	; Segmento de memoria de codigo
.org 0x0000
	rjmp start

.org ADCCaddr
	rjmp 	handle_adc_conversion

.org URXCaddr
    rjmp isr_dato_recibido_usart

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
	//rcall debug
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
	pop 	AUX_REGISTER
	ret

;*************************************************************************************
; Subrutina que setea el modo del programa en REMOTO
;	
;*************************************************************************************
set_remote_mode:
	ldi 	AUX_REGISTER, REMOTE
	mov 	MODE, AUX_REGISTER ; Mode = REMOTE
	rcall 	disable_adc ; Dejamos de hacer las conversiones del ADC
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
	mov 	AUX_REGISTER_2, SERVO_X_POSITION ; Cargo en el registro auxiliar el valor actual del servo
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
	mov 	AUX_REGISTER_2, SERVO_X_POSITION ; Cargo en el registro auxiliar el valor actual del servo
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
	mov 	AUX_REGISTER_2, SERVO_Y_POSITION ; Cargo en el registro auxiliar el valor actual del servo
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
	mov 	AUX_REGISTER_2, SERVO_Y_POSITION ; Cargo en el registro auxiliar el valor actual del servo
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
; + Servo X: se configura como output 
; + Servo Y: se configura como output
; + ADC X: se configura como input
; + ADC Y: se configura como input
;	
;*************************************************************************************
configure_ports:
	ldi 	AUX_REGISTER, 0x00 				; Cargo el registro R16 con 0x00
	out 	SERVOS_DIR, AUX_REGISTER 		; Cargo un cero en todos los bits del DDRB
	sbi 	SERVOS_DIR, SERVO_X_PIN_NUM  	; Configuro el pin del servo X como output
	sbi 	SERVOS_DIR, SERVO_Y_PIN_NUM  	; Configuro el pin del servo Y como output 

	// ADC
	out 	ADC_DIR, AUX_REGISTER 			; Cargo un cero en todos los bits del DDRC, seran inputs
	cbi 	ADC_PORT, ADC_X_PIN_NUM  		; Desactivo la resistencia de Pull-up, PORTC0 = 1
	cbi 	ADC_PORT, ADC_Y_PIN_NUM			; Desactivo la resistencia de Pull-up, PORTC1 = 0
	sbi    DDRB, DEBUG_PIN_NUM
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
;
; + COM1B1: 1
; + COM1B0: 0
;
;*************************************************************************************	
configure_timer_1:
	// Configuro TCCR1A
	push 	AUX_REGISTER
	clr 	AUX_REGISTER ; Limpio el registro
	lds 	AUX_REGISTER, TCCR1A ; AUX_REGISTER = TCCR1A
	andi 	AUX_REGISTER, 0x0C ; Realizo un AND con 0x3C = 0000 1100
	ori 	AUX_REGISTER, (1 << WGM11) ; Realizo un OR para configurar el WGM
	ori 	AUX_REGISTER, (1 << COM1A1) | (1 << COM1B1) ; Realizo un OR para configurar el Compare Output Mode
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
; Subrutina para configurar la interrupcion por entrada del teclado
;
;*************************************************************************************
configure_usart_interrupt:
    ; Activar interrupción por recepción de datos
    lds r16, UCSR0B
    ori r16, (1 << RXCIE0) 
    sts UCSR0B, r16
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
; Subrutina que configura los registros ADCSRA y ADMUX del ADC
;
;*************************************************************************************
configure_adc:
	rcall 	configure_ADCSRA_register
	rcall 	configure_ADMUX_register
	ret

;*************************************************************************************
; Subrutina que configura el ADCSRA Register del ADC
;
; ADC Enable: true
; + ADEN = 1
;
; ADC Interrupt Enable: true
; + ADIE = 1
;
; ADC Prescaler: 128
; + ADPS2 = 1
; + ADPS1 = 1
; + ADPS0 = 1
;*************************************************************************************
configure_ADCSRA_register:
	push 	AUX_REGISTER
	clr		AUX_REGISTER
	lds		AUX_REGISTER, ADCSRA ; AUX_REGISTER = ADCSRA
	andi	AUX_REGISTER, 0x70 ; Realizo un AND con 0111 0000 para limpiar los bits a configurar
	ori		AUX_REGISTER, (1 << ADEN) | (1 << ADIE) | (1 << ADPS2) | (1 << ADPS1) | (1 << ADPS0)
	sts		ADCSRA, AUX_REGISTER ; Cargo la configuracion en ADCSRA
	pop 	AUX_REGISTER
	ret

;*************************************************************************************
; Subrutina que configura el ADMUX Register del ADC
;
; Voltage Reference: internal VCC
; + REFS1: 0
; + REFS0: 1
;
; ADC Left Adjust Results: Right adjusted
; + ADLAR = 0 
;
; Analog Channel: ADC 0 (por default arrancamos convirtiendo este canal)
; + MUX3:0 = 0
;*************************************************************************************
configure_ADMUX_register:
	push 	AUX_REGISTER
	clr		AUX_REGISTER
	lds		AUX_REGISTER, ADMUX ; AUX_REGISTER = ADMUX
	andi	AUX_REGISTER, 0x10 ; Realizo un AND con 0001 0000 para limpiar los bits a configurar
	ori		AUX_REGISTER, (0 << REFS1) | (1 << REFS0)
	sts		ADMUX, AUX_REGISTER ; Cargo la configuracion en ADMUX
	pop 	AUX_REGISTER
	ret

;*************************************************************************************
; Subrutina que setea el channel 0 del ADC
;
; Analog Channel:
; + MUX2::0 = 000 = ADC0
;*************************************************************************************
set_channel_0:
	push 	AUX_REGISTER
	clr 	AUX_REGISTER
	lds 	AUX_REGISTER, ADMUX ; AUX_REGISTER = ADMUX
	andi 	AUX_REGISTER, CLEAR_CHANNEL ; Realizo un AND con 1111 1000 
	sts 	ADMUX, AUX_REGISTER
	pop 	AUX_REGISTER
	ret

;*************************************************************************************
; Subrutina que setea el channel 1 del ADC
;
; Analog Channel: ToDo: deberia configurarse ambos o no se
; + MUX3::0 = 0001 = ADC1
;*************************************************************************************
set_channel_1:
	push 	AUX_REGISTER
	clr 	AUX_REGISTER
	lds 	AUX_REGISTER, ADMUX ; AUX_REGISTER = ADMUX
	andi 	AUX_REGISTER, CLEAR_CHANNEL ; Realizo un AND con 1111 1000
	ori 	AUX_REGISTER, (1 << MUX0) ; Pongo en 1 el bit de MUX0
	sts 	ADMUX, AUX_REGISTER
	pop  	AUX_REGISTER
	ret

;*************************************************************************************
; Subrutina que activa la conversion del ADC
; + ADSC = 1
;
;*************************************************************************************
adc_start_conversion:
	push 	AUX_REGISTER
	clr		AUX_REGISTER
	lds		AUX_REGISTER, ADCSRA ; AUX_REGISTER = ADCSRA
	andi	AUX_REGISTER, 0xBF ; Realizo un AND con 1011 1111 para limpiar el bit a configurar
	ori		AUX_REGISTER, (1 << ADSC)
	sts		ADCSRA, AUX_REGISTER ; Cargo la configuracion en ADCSRA
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

;*************************************************************************************
; Subrutina que chequea si el valor del ADC es mayor a 512
; Si es verdad, FLAG contiene un 1, 0 en caso contrario
;
;*************************************************************************************
greater_than_512:
	// 513 = 0x0201
	push 	AUX_REGISTER
	clr 	FLAG ; Limpio el registro
	cpi 	ADC_HIGH, 0x02 ; Comparo con el valor del high byte
	breq	keep_checking ; Su parte alta coincide, la baja si o si tiene que ser mayor o igual, sino es menor
	brlo 	end_greater_than_512 ; Si su parte alta es menor ya sabemos que es menor a 512
	// Si llego aca si o si es mayor a 512
	rjmp 	is_greater

keep_checking:
	cpi 	ADC_LOW, 0x01
	brlo 	end_greater_than_512 ; Si es menor, no hay forma de que sea mas grande

is_greater:
	inc 	FLAG ; Cargo un 1 para indicar que es mayor

end_greater_than_512:
	pop 	AUX_REGISTER
	ret

;*************************************************************************************
; Subrutina que le resta 512 al valor del ADC
; Los nuevos valores de los bytes del ADC se mantienen en ADC_HIGH y ADC_LOW
;
;*************************************************************************************
subtract_512_to_ADC:
	push 	AUX_REGISTER
	push 	AUX_REGISTER_2
	// 512 = 0x0200 
	ldi 	AUX_REGISTER, 0x00 // Cargo el low byte de 512
	ldi 	AUX_REGISTER_2, 0x02 // Cargo el high byte de 512
	// Resto los low bytes
	sub 	ADC_LOW, AUX_REGISTER // ADC_LOW = ADC_LOW - AUX_REGISTER
	// Resto los high bytes
	sbc 	ADC_HIGH, AUX_REGISTER_2 // ADC_HIGH = ADC_HIGH - AUX_REGISTER_2
	pop 	AUX_REGISTER_2
	pop 	AUX_REGISTER
	ret

;*************************************************************************************
; Subrutina que mapea el valor del ADC a un valor entre los limites del servo motor.
; El valor leido del ADC se encuentra en el rango [0, 1024].
; El valor a convertir es de 16 bits.
; f(x) --> C, C E [35, 255], x E [0, 1024]
;
; f1(x) = [(x * 120) / 1024] + 35, si x E [0, 512]
; f2(x) = [(x * 120) / 1024] + 95, si x E [513, 1024]
;
; El resultado se guarda en MAPPED_VALUE
;*************************************************************************************
map_value:
	push 	AUX_REGISTER
	push 	AUX_REGISTER_2
	push 	AUX_REGISTER_3

	rcall 	greater_than_512 // Chequeo si es mayor a 512
	push 	FLAG // Pusheo el valor dado que al final lo necesito
	mov		AUX_REGISTER, FLAG
	cpi 	AUX_REGISTER, 1 // Si es igual a 1 significa que es mayor
	brne 	start_mapping // Comienzo a mapear
	
	// Antes de mapear debo restarle 512 al valor, sino la multiplicacion dara overflow
	rcall 	subtract_512_to_ADC

start_mapping:
	// 120 * x = 128 * x - 8 * x

	// 128 * x = Shift Left 7 veces
	mov 	AUX_REGISTER, ADC_LOW
	mov 	AUX_REGISTER_2, ADC_HIGH // Copio los valores del ADC en los registros

	lsr 	AUX_REGISTER // Shifteo una vez hacia la derecha

	// Shifteo 7 veces hacia la izquierda el HIGH BYTE
	ldi 	AUX_REGISTER_3, 0x00 ; Se usara como contador para el loop
loop_shift_7_times:
	lsl 	AUX_REGISTER_2
	inc 	AUX_REGISTER_3
	cpi 	AUX_REGISTER_3, 7
	brne 	loop_shift_7_times

	// El high byte se obtiene con un OR entre AUX_REGISTER y AUX_REGISTER 2
	or 		AUX_REGISTER, AUX_REGISTER_2 // AUX_REGISTER = AUX_REGISTER OR AUX_REGISTER_2
	push 	AUX_REGISTER // Guardo el valor en el stack ya que reutilizare estos registros a continuacion

	// Solo me interesa el HIGH byte de estas operaciones, ya que al dividir por 1024
	// hay que shiftear 10 veces hacia la derecha, por lo que el LOW byte y los 2 bits
	// menos significativos del high byte se 'pierden'

	// 8 * x = Shift Left 3 veces
	mov 	AUX_REGISTER, ADC_LOW
	mov 	AUX_REGISTER_2, ADC_HIGH // Copio los valores del ADC en los registros

	// Shifteo 3 veces hacia la izquierda el HIGH byte
	clr 	AUX_REGISTER_3
loop_shift_3_times:
	lsl 	AUX_REGISTER_2
	inc 	AUX_REGISTER_3
	cpi 	AUX_REGISTER_3, 3
	brne 	loop_shift_3_times

	// Shifteo 5 veces el LOW byte hacia la derecha
	clr 	AUX_REGISTER_3
loop_shift_5_times:
	lsr 	AUX_REGISTER
	inc 	AUX_REGISTER_3
	cpi 	AUX_REGISTER_3, 5
	brne 	loop_shift_5_times

	or 		AUX_REGISTER_2, AUX_REGISTER // AUX_REGISTER_2 = AUX_REGISTER_2 OR AUX_REGISTER

	// En este punto ya tengo 8x, recupero del stack 128x
	pop 	AUX_REGISTER // AUX_REGISTER tiene el valor de 128*x

	// Realizo 128x - 8x. Recordar, solo nos interesa el high byte, por lo tanto no trabajamos con 16 bits
	// sino con 8 bits. por lo que los valores estan entre 0 y 255. Al ser 128x > 8x siempre sera positivo
	// o cero el resultado
	sub 	AUX_REGISTER, AUX_REGISTER_2 // AUX_REGISTER = AUX_REGISTER - AUX_REGISTER_2 = 128x - 8x = 120x

	// value / 1024 = Shiftear 10 veces hacia la derecha
	// pero como value representa al high byte, shiftear 10 veces hacia la derecha es equivalente a shiftear
	// solo dos veces el valor que tenemos en el registro
	lsr 	AUX_REGISTER
	lsr 	AUX_REGISTER
	// Aca tenemos AUX_REGISTER = (Value * 120) / 1024

	pop 	FLAG // Recupero el valor de si es mayor a 512 dado que las funciones varian
	mov		AUX_REGISTER_2, FLAG // AUX_REGISTER_2 = FLAG
	cpi 	AUX_REGISTER_2, 0x01 // Si son iguales estoy en el caso de f2(x), en caso contrario es f1(x)
	breq 	add_95

	// Sumamos 35
	ldi 	AUX_REGISTER_2, LOWER_LIMIT
	add 	AUX_REGISTER, AUX_REGISTER_2 //AUX_REGISTER = AUX_REGISTER + 35 = f1(x)
	rjmp 	end_mapping

add_95:
	ldi 	AUX_REGISTER_2, 0x5F ; Cargo un 95
	add 	AUX_REGISTER, AUX_REGISTER_2 //AUX_REGISTER = AUX_REGISTER + 95 = f2(x)

end_mapping:
	cpi 	AUX_REGISTER, 0x9C ; Comparo el valor mapeado con 156
	brlo	set_mapped_value ; La conversion dio un numero menor al limite del servo
	ldi 	AUX_REGISTER, 0x9B ; Seteo forzosamente el 155 para no pasarme del limite
set_mapped_value:
	mov 	MAPPED_VALUE, AUX_REGISTER
	pop  	AUX_REGISTER_3
	pop  	AUX_REGISTER_2
	pop  	AUX_REGISTER
	ret

;*************************************************************************************
; Subrutinas de USART
;
;*************************************************************************************

;*************************************************************************************
; Subrutina que seta la configuración incial de USART
; 
;*************************************************************************************
USART_Init:
	push r16
	push r17

	;setear el baud rate en 9600
	ldi r16, 103
	ldi r17, 0
	sts UBRR0H, r17
	sts UBRR0L, r16

	; Activar recepción y tranmisión
	ldi r16, (1<<RXEN0)|(1<<TXEN0)
	sts UCSR0B,r16

	; Setear el formato del frame: 8 bits de datos, 2 de parada
	ldi r16, (1<<USBS0)|(3<<UCSZ00)
	sts UCSR0C,r16

	pop r17
	pop r16
	ret

;*************************************************************************************
; Subrutina para transmitir, transmite lo que este guardado en el registro r16
; 
;*************************************************************************************

USART_Transmit:
	;Esperar hasta que el buffer se vacie
	;(bit UDRE0 en 0)
	lds r17,UCSR0A
	sbrs r17,UDRE0
	rjmp USART_Transmit

	;Envia al buffer lo que haya en r16
	sts UDR0,r16
	ret

;*************************************************************************************
; Subrutina para recibir, guarda lo recibido en r16
; 
;*************************************************************************************

USART_Receive:

	;Esperar hasta recibir un dato
	;(registro RXC0 en 0)
	lds r17, UCSR0A
	sbrs r17, RXC0
	rjmp USART_Receive

	;Obtener lo recibido del buffer y guardarlo en r16
	lds r16, UDR0
	ret

;*************************************************************************************
; Subrutina para transmitir el mensaje inicial
; "Envíe R para pasar a control por modo remoto"
;*************************************************************************************

show_init_msg:

	push r16	
	push r18
	//apunta a la tabla MSG
	ldi	zl,LOW(MSJ<<1)
	ldi	zh,HIGH(MSJ<<1)
	//largo de la tabla
	ldi r18, 45

loop_show:
	//guarda el dato leido en r16
	//para que luego sea transmitido por USART_Transmit
	lpm	r16,z+
	rcall USART_Transmit
	dec r18
	brne loop_show

	pop r18
	pop r16
	ret


; ***************************** INTERRUPTS HANDLER ***********************************

;*************************************************************************************
; Subrutina para manejar la interrupcion por entrada del teclado
;
;*************************************************************************************
isr_dato_recibido_usart:
	//guardo el registro de estado
    in r24, SREG
	push r24

	//cargo en r16 el dato recibido
    lds r16, UDR0

	//primero chequeo en que modo estoy
	mov AUX_REGISTER, mode
	cpi AUX_REGISTER, REMOTE
	breq isr_remote_mode 

isr_manual_mode:
	//en caso de estar en modo manual
	//solo me importa si llega una 'r' para cambiar de modo
	cpi r16, 'r'
	breq isr_change_mode

isr_remote_mode: 

	//chequeo que tecla se presiono
	//y en base a eso muevo, cambio el modo o salgo
	cpi r16, 'm'
	breq isr_change_mode

	cpi r16, 'd'
	breq isr_move_right

	cpi r16, 'a'
	breq isr_move_left

	cpi r16, 'w'
	breq isr_move_up

	cpi r16, 's'
	breq isr_move_down
	rjmp fin_int_recibido

isr_move_right:
	rcall increase_x_position
	rjmp fin_int_recibido

isr_move_left:
	rcall decrease_x_position
	rjmp fin_int_recibido

isr_move_up:
	rcall increase_y_position
	rjmp fin_int_recibido

isr_move_down:
	rcall decrease_y_position
	rjmp fin_int_recibido

isr_change_mode:
	rcall change_mode

fin_int_recibido:
	//restauro el registro de estado
    out SREG, r24
	pop r24
    reti

;*************************************************************************************
; Handler del ADC cuando finaliza la conversion
;
;*************************************************************************************
handle_adc_conversion:
	; Guardo en el stack los siguientes valores de los registros
	push 	AUX_REGISTER
	in	 	AUX_REGISTER, SREG
	push 	AUX_REGISTER

	lds 	ADC_LOW, ADCL ; Cargo el contenido de ADCL en el registro
	lds 	ADC_HIGH, ADCH ; Cargo el contenido de ADCH en el registro
	rcall 	map_value ; Mapeo el valor al rango [35, 155]
	ldi 	AUX_REGISTER, 0x01
	cp 		FLAG_CONVERT_X, AUX_REGISTER ; Veo que canal debo analizar para actualizar la posicion del servo
	brne	conversion_y

	// Conversion de X
	mov 	SERVO_X_POSITION, MAPPED_VALUE ; Actualizo la posicion del servo en X
	rcall 	set_OCR1A
	rcall 	set_channel_1 ; Cambio de channel para actualizar la posicion en Y
	rcall 	adc_start_conversion ; Comienzo la conversion de ADC1
	clr 	FLAG_CONVERT_X ; Limpio el registro, ahora analizo y convierto Y
	rjmp 	end_handle_adc_conversion

conversion_y:
	mov 	SERVO_Y_POSITION, MAPPED_VALUE ; Actualizo la posicion del servo en Y
	rcall 	set_OCR1B
	rcall 	set_channel_0 ; Cambio al channel 0 nuevamente
	rcall 	adc_start_conversion
	ldi 	AUX_REGISTER, 0x01
	mov 	FLAG_CONVERT_X, AUX_REGISTER ; Cargo un 1 para que la proxima conversion sea de X

end_handle_adc_conversion:
	; Recupero los valores de los registros
	pop 	AUX_REGISTER
	out 	SREG, AUX_REGISTER
	pop 	AUX_REGISTER
	reti

debug:
	sbi   PORTB, DEBUG_PIN_NUM
	rrjmp debug
	ret

//len = 45
//Tabla con el mensaje "Envíe R para pasar a control por modo remoto" en ASCII
MSJ: .DB 69, 110, 118, 195, 173, 101, 32, 82, 32, 112, 97, 114, 97, 32, \
112, 97, 115, 97, 114, 32, 97, 32, 99, 111, 110, 116, 114, 111, 108, 32, 112, \
111, 114, 32, 109, 111, 100, 111, 32, 114, 101, 109, 111, 116, 111, 0