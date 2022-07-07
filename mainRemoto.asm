.include "m328Pdef.inc"

.def contador_servo = r23
.equ TOP_20ms = 1250

.org	0x0000
	rjmp inicio
.org URXCaddr
    jmp isr_dato_recibido_usart

.org INT_VECTORS_SIZE
inicio:
	ldi		r16,HIGH(RAMEND)
	out		sph,r16
	ldi		r16,LOW(RAMEND)
	out		spl,r16
main:
	clr contador_servo
	rcall configure_ports
	rcall configure_timer1
	ldi r16, 103
	ldi r17, 0
	rcall USART_Init
	rcall configurar_interrupciones
    sei
	rcall show_init_msg2

here: 
	/*rcall USART_Receive
	//119 87
	cpi r16, 119
	brne here
	rcall change_led*/
	rjmp here
	//inc r16
	//rcall USART_Transmit
USART_Init:
	; Set baud rate
	sts UBRR0H, r17
	sts UBRR0L, r16
	; Enable receiver and transmitter
	ldi r16, (1<<RXEN0)|(1<<TXEN0)
	sts UCSR0B,r16
	; Set frame format: 8data, 2stop bit
	ldi r16, (1<<USBS0)|(3<<UCSZ00)
	sts UCSR0C,r16
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

show_init_msg:
	push r16	
	push r18
	ldi	zl,LOW(MSJ<<1)
	ldi	zh,HIGH(MSJ<<1)
	ldi r18, 45

loop_show:
	rcall delay50ms
	lpm	r16,z+
	rcall USART_Transmit
	dec r18
	brne loop_show

	pop r18
	pop r16
	ret

show_init_msg2:
	push r16	
	push r18
	ldi	zl,LOW(MSJ2<<1)
	ldi	zh,HIGH(MSJ2<<1)
	ldi r18,45
	lpm	r16,z+

loop_show2:
	//rcall delay50ms
	rcall USART_Transmit
	lpm	r16,z+
	cpi r16,0
	brne loop_show2

	pop r18
	pop r16
	ret

configure_ports:
	push r20
	ldi	r20, 0xFF
	;el servo esta en el puerto B entonces es output
	out	DDRB, r20
	pop r20
	ret

delay50ms:
	push r19
	push r18
	push r17
	ldi r19, 4
loop0:
	ldi r18, 201
loop1:
	ldi r17, 248
loop2:
	nop
	dec r17
	brne loop2
	dec r18
	brne loop1
	dec r19
	brne loop0
	pop r17
	pop r18
	pop r19
	ret

change_led:
	sbic PORTD, 2 ;skip if bit is cleared
	rjmp change_led_turn_off_led
	sbi PORTD, 2
	rjmp change_led_fin
change_led_turn_off_led:
	cbi PORTD, 2
change_led_fin:
	ret

configurar_interrupciones:
    ; Activar interrupción por recepción de datos
    lds r16, UCSR0B
    ori r16, (1 << RXCIE0) 
    sts UCSR0B, r16
    ret

configure_timer1:
	push r16
	push r17
	//TCCR1A
	//dejo el a en modo inversor
	//y el b en modo no inversor
	clr r16
	ori r16, (0 << WGM10) | (1 << WGM11) | (1 << COM1A1) | (0 << COM1A0) | (0 << COM1B1) | (0 << COM1B0)
	sts	TCCR1A, r16
	//TCCRB
	clr r16
	ori r16, (0 << ICNC1) | (0 << ICES1) | (1 << CS12) | (0 << CS11) | (0 << CS10) | (1 << WGM12) | (1 << WGM13)
	sts TCCR1B, r16
	ldi r16, 55
	ldi r17, 0
	sts OCR1AH, r17
	sts OCR1AL, r16
	ldi contador_servo, 0
	//ICR1
	//necesito que el top sea 40000=0x9C40
	//para un pulso de 20 ms
	ldi r16, HIGH(TOP_20ms)
	sts ICR1H, r16
	ldi r16, LOW(TOP_20ms)
	sts ICR1L, r16
	pop r17
	pop r16
	ret

configure_timer0:
	push r16
	ldi r16, (1 << CS02) | (0 << CS01) | (1 << CS00) ;setea el prescaler en 1024
	out TCCR0B, r16
	;activar la interrupcion del timer
	ldi r16, 1<<TOIE0
	sts TIMSK0, r16
	pop r16
	ret

isr_dato_recibido_usart:
    in r22, SREG
    lds r16, UDR0
    cpi r16, 'd'
	breq mover_derecha
	cpi r16, 'a'
	breq mover_izquierda
	rjmp fin_int_recibido
mover_derecha:
	cpi contador_servo, 16
	breq fin_int_recibido
	//quiero sumar 125 que es el paso
	//125=63+62
	lds r24, OCR1AL
	lds r25, OCR1AH
	adiw r24, 6
	sts OCR1AH, r25
	sts OCR1AL, r24
	inc contador_servo
	rjmp fin_int_recibido
mover_izquierda:
	cpi contador_servo, 0
	breq fin_int_recibido
	//quiero sumar 125 que es el paso
	//125=63+62
	lds r24, OCR1AL
	lds r25, OCR1AH
	sbiw r24, 6
	sts OCR1AH, r25
	sts OCR1AL, r24
	dec contador_servo
fin_int_recibido:
    out SREG, r22
    reti

//len = 45
MSJ: .DB 69, 110, 118, 195, 173, 101, 32, 82, 32, 112, 97, 114, 97, 32, \
112, 97, 115, 97, 114, 32, 97, 32, 99, 111, 110, 116, 114, 111, 108, 32, 112, \
111, 114, 32, 109, 111, 100, 111, 32, 114, 101, 109, 111, 116, 111

MSJ2: .DB "Envie A y D para mover el servo",0