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

.equ 	SERVO_STEP			= 6 	; Se va a mover el OCR1A y OCR1B entre [35, 155] con un step de 1 para ir de 0 a 180 grados
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
