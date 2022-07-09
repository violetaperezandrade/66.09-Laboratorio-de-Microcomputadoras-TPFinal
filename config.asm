;*************************************************************************************
; Este modulo contiene las configuraciones de los puertos, Timer 1, USART y ADC
;
;*************************************************************************************

;*************************************************************************************
; 									PORTS
;*************************************************************************************

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
; 									Timer 1
;*************************************************************************************

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
; 									USART
;*************************************************************************************

;*************************************************************************************
; Subrutina que setea la configuración incial de USART
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
; 									ADC
;*************************************************************************************

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