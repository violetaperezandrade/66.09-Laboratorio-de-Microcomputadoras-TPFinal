;*************************************************************************************
; Este modulo posee todas las subrutinas relacionadas con el Analog to Digital Converter (ADC)
;
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