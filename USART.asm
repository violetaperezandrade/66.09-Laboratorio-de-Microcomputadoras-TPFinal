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
; Subrutinas de USART
;
;*************************************************************************************

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