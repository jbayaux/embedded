; *********************************************************** ;
;                 MUSHROOM CONTROL STATION                    ;
;  collect data from sensors and transmit them over bluetooth ;
;                                                             ;
;               INFO2055 - Embedded Systems Project           ;
;              Antoine Malherbe  -  Chloe Preud'Homme         ;
;                 Jerome Bayaux  -  Tom Piron                 ;
;                                                             ;
; *********************************************************** ;


    processor    16f1789
    #include     "config.inc"
    ; Constants for measurements
    ; Initiallisation of the counter to make measurements every 15 min 0.202 s
    ; 1717 * 0.524288 s = 900.202 s
    #define measure_counter_init_L 0xB5
    #define measure_counter_init_H 0x06

    PSECT text, abs, class=CODE, delta=2

; That is where the MCU will start executing the program (0x00)
    org      0x0000
    goto     start                  ; jump to the beginning of the code

; That is where the MCU will jump when an interrupt occur (0x04)
    org      0x0004
    goto     interrupt_routines     ; jump to the interrupt routine


;BEGINNING OF THE PROGRAM
start:
    call     initialisation         ; initialisation routine configuring the MCU
    goto     main_loop              ; main loop


;INITIALISATION
initialisation:
    ; configuration of the GPIO
    banksel  TRISA
    bsf      TRISA, 0               ; Set RA0 to input for temp sensor
    bsf      TRISA, 1               ; Set RA1 to input for luminosity sensor
    bsf      TRISB, 4               ; Set RB4 to input for humidity sensor
    banksel  ANSELA
    bsf      ANSELA, 0              ; Set input mode of RA0 to analog
    bsf      ANSELA, 1              ; Set input mode of RA1 to analog
    bsf      ANSELB, 4              ; Set input mode of RB4 to analog
    banksel  WPUA
    bcf      WPUA, 0                ; Disable weak pull-up on RA0
    bcf      WPUA, 1                ; Disable weak pull-up on RA1
    bcf      WPUB, 4                ; Disable weak pull-up on RB4

    ; Configuration of ADC
    banksel  ADCON1
    ; Frequency = Fosc/4, result as sign-magnitude
    movlw    01000000B
    movwf    ADCON1
    ; Negative ref set to VSS
    movlw    00001111B
    movwf    ADCON2

    ; Configuration of clock
    banksel  OSCCON
    ; 4MHz frequency with the internal oscillator
    movlw    01101110B
    movwf    OSCCON
    ; No tuning of the frequency
    movlw    00000000B
    movwf    OSCTUNE

    ; Configuration of Timer1
    ; Tune it to trigger interrupt every 0.524288 s
    ; Enable timer1 with instruction clock as source and prescale of 1:8
    ; Frequency = (4MHz/4)/8/65536 = 1.907348Hz
    banksel  T1CON
    movlw    00110001B
    movwf    T1CON

    ; Configuration of EUSART for the bluetooth module
    banksel  TX1STA
    bcf      TX1STA, 4              ; Set Asynchronous mode
    bsf      TX1STA, 5              ; Enable transmition circuit of EUSART
    bsf      RC1STA, 4              ; Enable the receiver circuit of EUSART
    ; Configure baud-rate, depend on the 4MHz clock
    ; Baud-rate of 111100 Kbps, 115200 Kbps needed but ok
    bsf      TX1STA, 2
    bsf      BAUD1CON, 3
    movlw    0x00
    movwf    SP1BRGH
    movlw    0x08
    movwf    SP1BRGL
    ; Enables EUSART and configure pins automagically
    bsf      RC1STA, 7

    ; Set interrupts on timer 1, ADC and EUSART receive
    ; Enable interrupts and peripheral interrupts
    movlw    11000000B
    movwf    INTCON
    ; Enable timer1, ADC and EUSART receive interrupts
    banksel  PIE1
    movlw    01100001B
    movwf    PIE1

    ; Declare and initialize variables
    ; Location for measurements
    measure_bank           EQU 0x00
    measure_task_flags     EQU 0x20
    measure_temp_bit       EQU 0x00 ; Bit 0 : flag for temp task
    measure_humidity_bit   EQU 0x01 ; Bit 1 : flag for humidity task
    measure_luminosity_bit EQU 0x02 ; Bit 2 : flag for luminosity task
    measure_check_full_bit EQU 0x03 ; Bit 3 : flag to check empty space
    ; Bit 4 : flag to send data through bluetooth (see bluetooth variables)
    measure_status_flags   EQU 0x21
    ; Bit 0 : flag to stop writing data (no more free space)
    measure_stop_writing_bit EQU 0x00

    measure_counter_L      EQU 0x22
    measure_counter_H      EQU 0x23
    measure_current_addr_write_L EQU 0x24
    measure_current_addr_write_H EQU 0x25
    ; Linear access memory for storing measurements
    measure_base_addr_H    EQU 0x20
    measure_base_addr_L    EQU 0x50
    measure_max_addr_H     EQU 0x29
    measure_max_addr_L     EQU 0xb0

    ; Initialise variables for measurements
    movlb    measure_bank
    movlw    00000000B
    movwf    measure_task_flags     ; Reset all task_flags
    movlw    measure_counter_init_L
    movwf    measure_counter_L
    movlw    measure_counter_init_H
    movwf    measure_counter_H      ; Init measure_counter
    movlw    measure_base_addr_L
    movwf    measure_current_addr_write_L
    movlw    measure_base_addr_H
    movwf    measure_current_addr_write_H ; Init measure_current_addr_write

    ; Set blue locations
    blue_bank              EQU 0x00
    blue_recv_counter      EQU 0x26
    blue_send_enabled      EQU 0x20
    blue_send_enabled_bit  EQU 0x04 ; Bit 4 : flag to send data through bluetooth
    blue_send_buffer_H     EQU 0x27
    blue_send_buffer_L     EQU 0x28
    blue_send_size_H       EQU 0x29
    blue_send_size_L       EQU 0x2A
    blue_send_counter_H    EQU 0x2B
    blue_send_counter_L    EQU 0x2C

    ; In program memory
    blue_data_H            EQU 0x90 ; Program address 0x10XX
    blue_get_command_L     EQU 0x00
    blue_no_data_L         EQU 0x04
    blue_no_data_size_L    EQU 0x06

    ; Initialize blue variables
    movlb    blue_bank
    movlw    0x00
    movwf    blue_recv_counter
    movwf    blue_send_counter_H
    movwf    blue_send_counter_L
    bcf      blue_send_enabled, blue_send_enabled_bit

    ; Set local variables locations
    ; Used in functions for local variables
    int_local_bank         EQU 0x00 ; Bank for interrupt local variables
    int_local_start        EQU 0x2D

    return


;INTERRUPT ROUTINES
interrupt_routines:
    banksel  PIR1
    btfsc    PIR1, 0
    call     timer1_handler         ; Call handler if timer1 interrupt bit set
    banksel  PIR1
    btfsc    PIR1, 6
    call     adc_completion_handler
    banksel  PIR1
    btfsc    PIR1, 5
    call     blue_receive_handler   ; Call handler when data received over bluetooth
    banksel  PIE1
    ; PIR1 bit 4 is always set when ready to send, even if PIE1 bit 4 is cleared
    btfss    PIE1, 4
    goto     after_send_handler
    banksel  PIR1
    btfsc    PIR1, 4
    call     blue_send_handler      ; Call handler when data transmitted over bluetooth
    goto     after_send_handler

after_send_handler:
    retfie


timer1_handler:
    bcf      PIR1, 0                ; Reset interrupt notification bit
    ; Secondary counter to have time > 0.5 s between measurements
    ; if --measure_counter == 0
    ;     return
    decfsz   measure_counter_L
    bra      0x01
    goto     timer1_counter_H_check ; Check measure_counter_H == 0
    ; Bit carry to measure_counter_H if necessary
    movlw    0xFF
    xorwf    measure_counter_L, 0
    btfsc    STATUS, 2
    decf     measure_counter_H, 1
    return

timer1_counter_H_check:
    movf     measure_counter_H, 1
    btfss    STATUS, 2
    return
    ; Reset measure_counter
    movlw    measure_counter_init_L
    movwf    measure_counter_L
    movlw    measure_counter_init_H
    movwf    measure_counter_H
    ; Check if there is still some space available for measurements
    btfsc    measure_status_flags, 0
    return
    ; Start task for temp measurement
    bsf      measure_task_flags, measure_temp_bit
    return


adc_completion_handler:
    bcf      PIR1, 6                ; Reset interrupt notification bit
    movf     measure_current_addr_write_L, 0
    movwf    FSR0L
    movf     measure_current_addr_write_H, 0
    movwf    FSR0H
    banksel  ADRESH
    movf     ADRESH, 0
    movwi    FSR0++
    movf     ADRESL, 0
    movwi    FSR0++
    movlb    00h
    movf     FSR0L, 0
    movwf    measure_current_addr_write_L
    movf     FSR0H, 0
    movwf    measure_current_addr_write_H
    return


blue_receive_handler:
    ; Local variables declaration
    local_recv_char        EQU int_local_start + 0x00
    local_FSR0L            EQU int_local_start + 0x01
    local_FSR0H            EQU int_local_start + 0x02
    ; Don't reset interrupt bit, automatically reset when the receive
    ; buffer is empty.
    ; Save FSR0 as it will be modified
    movlb    int_local_bank
    movf     FSR0L, 0
    movwf    local_FSR0L
    movf     FSR0H, 0
    movwf    local_FSR0H
    ; Save received char to local variable
    banksel  RC1REG
    movf     RC1REG, 0
    movlb    int_local_bank
    movwf    local_recv_char
    ; Set the indirect register to the nth character of the get command
    ; n being contained in blue_recv_counter
    movlb    blue_bank
    movf     blue_recv_counter, 0
    addlw    blue_get_command_L
    movwf    FSR0L
    movlw    blue_data_H
    movwf    FSR0H
    ; Get the nth char of the get command
    moviw    FSR0 ++
    ; If received char == nth char of get command
    ; else: blue_recv_else
    ; end: blue_recv_end_if
    movlb    int_local_bank
    subwf    local_recv_char, 0
    btfss    STATUS, 2
    goto     blue_recv_else
    ; If next character of the get command != \0
    ; else: blue_zero_check_else
    ; end: blue_zero_check_end_if
    moviw    FSR0 ++
    btfsc    STATUS, 2
    goto     blue_zero_check_else
    ; blue_recv_counter++
    movlb    blue_bank
    incfsz   blue_recv_counter
    goto     blue_zero_check_end_if
    goto     blue_zero_check_else

blue_zero_check_else:
    ; Enable sending data
    movlb    blue_bank
    bsf      blue_send_enabled, blue_send_enabled_bit
    ; Reset blue_recv_counter
    movlw    00h
    movwf    blue_recv_counter
    goto     blue_zero_check_end_if

blue_zero_check_end_if:
    goto     blue_recv_end_if

blue_recv_else:
    ; Reset blue_recv_counter
    movlb    blue_bank
    movlw    00h
    movwf    blue_recv_counter
    goto     blue_recv_end_if

blue_recv_end_if:
    ; Restaure FSR0
    movlb    int_local_bank
    movf     local_FSR0L, 0
    movwf    FSR0L
    movf     local_FSR0H, 0
    movwf    FSR0H
    return


blue_send_handler:
    ; Local variables declaration
    local_FSR0L_1          EQU int_local_start + 0x00
    local_FSR0H_1          EQU int_local_start + 0x01
    ; Don't reset interrupt bit, automatically reset when the send
    ; buffer is written.
    ; Save FSR0 as it will be modified
    movlb    int_local_bank
    movf     FSR0L, 0
    movwf    local_FSR0L_1
    movf     FSR0H, 0
    movwf    local_FSR0H_1
    ; Set the indirect register to blue_send_buffer + blue_send_counter
    movlb    blue_bank
    movf     blue_send_buffer_L, 0
    addwf    blue_send_counter_L, 0
    movwf    FSR0L
    movf     blue_send_buffer_H, 0
    ; If there was a carry for the low byte
    btfsc    STATUS, 0
    incf     WREG, 0
    addwf    blue_send_counter_H, 0
    movwf    FSR0H
    ; Send byte
    banksel  TX1REG
    moviw    0[FSR0]
    movwf    TX1REG
    ; if ++blue_send_counter != blue_send_size
    ;     return
    movlb    blue_bank
    incf     blue_send_counter_L, 1
    btfsc    STATUS, 2              ; If carry
    incf     blue_send_counter_H, 1
    movf     blue_send_counter_L, 0
    subwf    blue_send_size_L, 0
    btfss    STATUS, 2
    return
    movf     blue_send_counter_H, 0
    subwf    blue_send_size_H, 0
    btfss    STATUS, 2
    return
    ; Reset blue_send_counter
    movlw    0x00
    movwf    blue_send_counter_L
    movwf    blue_send_counter_H
    call     clear_data             ; Empty measurement memory
    ; Restaure FSR0
    movlb    int_local_bank
    movf     local_FSR0L_1, 0
    movwf    FSR0L
    movf     local_FSR0H_1, 0
    movwf    FSR0H
    ; End the transmition
    banksel  PIE1
    bcf      PIE1, 4
    return


clear_data:
    ; Clear task and reset the memory
    movlb    measure_bank
    movlw    measure_base_addr_L
    movwf    measure_current_addr_write_L
    movlw    measure_base_addr_H
    movwf    measure_current_addr_write_H
    bcf      measure_status_flags, measure_stop_writing_bit
    return


;MAIN LOOP
main_loop:
    movlb    measure_bank
    btfsc    measure_task_flags, measure_temp_bit
    call     get_temp
    movlb    measure_bank
    btfsc    measure_task_flags, measure_humidity_bit
    call     get_humidity
    movlb    measure_bank
    btfsc    measure_task_flags, measure_luminosity_bit
    call     get_luminosity
    movlb    measure_bank
    btfsc    measure_task_flags, measure_check_full_bit
    call     check_empty_space
    movlb    measure_bank
    btfsc    blue_send_enabled, blue_send_enabled_bit
    call     blue_send_data
    goto     main_loop


; Sensor data colection
get_temp:
    banksel  ADCON0
    btfsc    ADCON0, 1              ; Test if ADC already used
    return

    movlw    00000001B              ; ADC enabled and AN0 selected as source
    movwf    ADCON0
    call     wait_acquisition
    bsf      ADCON0, 1              ; Set ADC Conversion Status bit
                                    ; to start conversion
    movlb    00h
    bcf      measure_task_flags, measure_temp_bit
    bsf      measure_task_flags, measure_humidity_bit
    return


get_humidity:
    banksel  ADCON0
    btfsc    ADCON0, 1              ; Test if ADC already used
    return

    movlw    00101101B              ; ADC enabled and AN11 selected as source
    movwf    ADCON0
    call     wait_acquisition
    bsf      ADCON0, 1              ; Set ADC Conversion Status bit
                                    ; to start conversion
    movlb    00h
    bcf      measure_task_flags, measure_humidity_bit
    bsf      measure_task_flags, measure_luminosity_bit
    return


get_luminosity:
    banksel  ADCON0
    btfsc    ADCON0, 1              ; Test if ADC already used
    return

    movlw    00000101B              ; ADC enabled and AN1 selected as source
    movwf    ADCON0
    call     wait_acquisition
    bsf      ADCON0, 1              ; Set ADC Conversion Status bit
                                    ; to start conversion
    movlb    00h
    bcf      measure_task_flags, measure_luminosity_bit
    bsf      measure_task_flags, measure_check_full_bit
    return


wait_acquisition:
    ; Wait for acquisition (6 us)
    nop
    return


check_empty_space:
    ; Check if there is still space to store future measurements
    bcf      measure_task_flags, measure_check_full_bit
    movf     FSR0H, 0
    xorlw    measure_max_addr_H
    btfss    STATUS, 2
    return
    movf     FSR0L, 0
    xorlw    measure_max_addr_L
    btfsc    STATUS, 2
    bsf      measure_status_flags, measure_stop_writing_bit
    return

blue_send_data:
    ; Stop any new measure during transmition
    movlb    measure_bank
    bsf      measure_status_flags, measure_stop_writing_bit

    ; Set send counter to current - base
    movlw    measure_base_addr_H
    subwf    measure_current_addr_write_H, 0
    movwf    blue_send_size_H
    movlw    measure_base_addr_L
    subwf    measure_current_addr_write_L, 0
    movwf    blue_send_size_L

    ; If send_size == 0, send 6 times 0
    movf     blue_send_size_L, 1
    btfss    STATUS, 2
    goto     size_not_zero
    movf     blue_send_size_H, 1
    btfss    STATUS, 2
    goto     size_not_zero
    movlw    blue_data_H
    movwf    blue_send_buffer_H
    movlw    blue_no_data_L
    movwf    blue_send_buffer_L
    movlw    blue_no_data_size_L
    movwf    blue_send_size_L
    goto     activate_send

size_not_zero:
    movlw    measure_base_addr_H
    movwf    blue_send_buffer_H
    movlw    measure_base_addr_L
    movwf    blue_send_buffer_L
    goto     activate_send

activate_send:
    bcf      blue_send_enabled, blue_send_enabled_bit
    banksel  PIE1
    bsf      PIE1, 4
    return

; Data for the program
    ; Get command
    org      0x1000
    db       'G','E', 'T', 0
    ; 6 times 0 to send when no measure available
    org      0x1004
    db       0, 0, 0, 0, 0, 0
