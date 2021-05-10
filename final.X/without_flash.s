; *********************************************************** ;
;                       STORE IN RAM                          ;
;       collect data from ADC and store it in RAM             ;
;                                                             ;
;               INFO2055 - Embedded Systems Project           ;
;              Antoine Malherbe  -  Chloe Preud'Homme         ;
;                 Jerome Bayaux  -  Tom Piron                 ;
;                                                             ;
; *********************************************************** ;


    processor	 16f1789
    #include     "config.inc"
    #define      measure_counter    0x10
    #define      base_address_high  0x20
    #define      base_address_low   0x50
    #define      max_address_high   0x29
    #define      max_address_low    0xb0

    PSECT text, abs, class=CODE, delta=2
    
; That is where the MCU will start executing the program (0x00)
    org      00h
    goto     start                  ; jump to the beginning of the code

; That is where the MCU will jump when an interrupt occur (0x04)
    org      04h
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
    movlw    01000000B              ; Frequency = Fosc/4, result as sign-magnitude
    movwf    ADCON1
    movlw    00001111B              ; Negative ref set to VSS
    movwf    ADCON2

    ; Configuration of clock
    banksel  OSCCON
    movlw    01101110B
    movwf    OSCCON                 ; 4MHz frequency with the internal oscillator
    movlw    00000000B        
    movwf    OSCTUNE                ; No tuning of the frequency
    
    ; Configuration of Timer1
    ; Tune it to trigger interrupt every 5 sec
    banksel  T1CON
    movlw    00110001B
    movwf    T1CON                  ; Enable timer1 with instruction clock as
                                    ; source and prescale of 1:8
                                    ; Frequency = (4MHz/4)/8 = 0.125MHz

    ; Configuration of EUSART for the bluetooth module
    banksel TX1STA
    bcf TX1STA, 4 ; Set Asynchronous mode
    bsf TX1STA, 5 ; Enable transmition circuit of EUSART
    bsf RC1STA, 4 ; Enable the receiver circuit of EUSART
    ; Configure baud-rate, depend on the 4MHz clock
    ; Baud-rate of 111100 Kbps, 115200 Kbps needed
    bsf TX1STA, 2
    bsf BAUD1CON, 3
    movlw 0x00
    movwf SP1BRGH
    movlw 0x08
    movwf SP1BRGL
    
    bsf RC1STA, 7 ; Enables EUSART and configure pins automagically
    
    ; Set interrupts on timer 1 and ADC
    movlw    11000000B
    movwf    INTCON                 ; Enable interrupts and peripheral interrupts
    banksel  PIE1
    movlw    01101001B
    movwf    PIE1                   ; Enable timer1, ADC, SPI and EUSART receive interrupts
    
    ; Declare variables in GPRs
    ; In Bank 0
    task_flags   EQU 20h            ; Bit 0 : flag for temp task
                                    ; Bit 1 : flag for humidity task
                                    ; Bit 2 : flag for luminosity task
                                    ; Bit 3 : flag to check empty space
                                    ; Bit 4 : flag to read data
				    ; Bit 5 : flag to send data through bluetooth
    status_flags  EQU 21h           ; Bit 0 : flag to stop writing data (no more free space)

    counter      EQU 22h
    current_address_write_low  EQU 23h
    current_address_write_high EQU 24h
    current_address_read_low   EQU 25h
    current_address_read_high  EQU 26h
    
    ; Initialise variables
    movlb    00h
    movlw    00000000B
    movwf    task_flags
    movlw    measure_counter
    movwf    counter
    movlw    base_address_low
    movwf    current_address_write_low      ; FSR0 is used to store the actual write address
    movwf    current_address_read_low       ; FSR1 is used to store the actual read address
    movlw    base_address_high
    movwf    current_address_write_high
    movwf    current_address_read_high
    
    ; Set variables locations
    int_local_bank EQU 0x00 ; Bank for interrupt local variables
    int_local_start EQU 0x2D
 
    ; Set blue locations
    blue_bank EQU 0x00
    blue_recv_counter EQU 0x27
    blue_send_enabled_addr EQU 0x20 ; Bit 5 is command get received
    blue_send_enabled_bit EQU 0x05
    blue_send_buffer_H EQU 0x29
    blue_send_buffer_L EQU 0x2A
    blue_send_size EQU 0x2B
    blue_send_counter EQU 0x2C
 
    ; TODO
    blue_commands_H EQU 0x90 ; Program address 0x10XX
    blue_helo_command_L EQU 0x00 ; Program address 0xXX00
    blue_get_command_L EQU 0x05 ; Program address 0xXX05
 
    ; Initialize blue variables
    movlb blue_bank
    movlw 0x00
    movwf blue_recv_counter
    movwf blue_send_counter
    bcf blue_send_enabled_addr, blue_send_enabled_bit
    
    return

;INTERRUPT ROUTINES
interrupt_routines:
    banksel  PIR1
    btfsc    PIR1, 0
    call     timer1_handler         ; Call handler if timer1 interrupt bit set
    banksel  PIR1
    btfsc    PIR1, 6
    call     adc_completion
    banksel  PIR1
    btfsc    PIR1, 5
    call     blue_receive_handler   ; Call handler when data received over bluetooth
    banksel  PIE1
    btfss PIE1, 4
    goto after_send_handler
    banksel  PIR1
    btfsc    PIR1, 4
    call     blue_send_handler   ; Call handler when data transmitted over bluetooth
after_send_handler:
    retfie

timer1_handler:
    bcf      PIR1, 0                ; Reset interrupt notification bit
    decfsz   counter                ; Start measurements only every 5 sec
    return
    movlw    measure_counter
    movwf    counter                ; Reset timer counter
    btfsc    status_flags, 0        ; Check if there is still some space available for measurements
    return
    bsf      task_flags, 0          ; Start task for temp measurement
    return
    
adc_completion:
    bcf      PIR1, 6                ; Reset interrupt notification bit
    movf     current_address_write_low, 0
    movwf    FSR0L
    movf     current_address_write_high, 0
    movwf    FSR0H
    banksel  ADRESH
    movf     ADRESH, 0
    movwi    FSR0++
    movf     ADRESL, 0
    movwi    FSR0++
    movlb    00h
    movf     FSR0L, 0
    movwf    current_address_write_low
    movf     FSR0H, 0
    movwf    current_address_write_high
    return

blue_receive_handler:
    ; Local variables declaration
    local_recv_char EQU int_local_start + 0x00
    local_FSR0L EQU int_local_start + 0x01
    local_FSR0H EQU int_local_start + 0x02
    ; Set the indirect register to the helo command
    ; Don't reset interrupt bit, automatically reset when the receive
    ; buffer is empty.
    ; Save FSR0 as it will be modified
    movlb int_local_bank
    movf FSR0L, 0
    movwf local_FSR0L
    movf FSR0H, 0
    movwf local_FSR0H
    ; Save received char to local variable
    banksel RC1REG
    movf RC1REG, 0
    movlb int_local_bank
    movwf local_recv_char
    ; Set the indirect register to the nth character of the get command
    ; n being contained in blue_recv_counter
    movlb blue_bank
    movf blue_recv_counter, 0
    addlw blue_get_command_L
    movwf FSR0L
    movlw blue_commands_H
    movwf FSR0H
    ; Get the nth char of the get command
    moviw FSR0 ++
    ; If received char == nth char of get command
    ; else: blue_recv_else
    ; end: blue_recv_end_if
    movlb int_local_bank
    subwf local_recv_char, 0
    btfss STATUS, 2
    goto blue_recv_else
    ; If next character of the get command != \0
    ; else: blue_zero_check_else
    ; end: blue_zero_check_end_if
    moviw FSR0 ++
    btfsc STATUS, 2
    goto blue_zero_check_else
    movlb blue_bank
    incfsz blue_recv_counter
    goto blue_zero_check_end_if
blue_zero_check_else:
    ; Enable sending data
    movlb blue_bank
    bsf blue_send_enabled_addr, blue_send_enabled_bit
    ; Reset blue_recv_counter
    movlw 0x00
    movwf blue_recv_counter
blue_zero_check_end_if:
    goto blue_recv_end_if
blue_recv_else:
    ; Reset blue_recv_counter
    movlb blue_bank
    movlw 0x00
    movwf blue_recv_counter
blue_recv_end_if:
    ; Restaure FSR0
    movlb int_local_bank
    movf local_FSR0L, 0
    movwf FSR0L
    movf local_FSR0H, 0
    movwf FSR0H
    return
    
blue_send_handler:
    movlb blue_bank
    movf blue_send_buffer_H, 0
    movwf FSR0H
    movf blue_send_buffer_L, 0
    addwf blue_send_counter, 0
    movwf FSR0L
    banksel TX1REG
    moviw 0[FSR0]
    movwf TX1REG
    movlb blue_bank
    incfsz blue_send_counter, 1
    nop
    movf blue_send_counter, 0
    subwf blue_send_size, 0
    btfss STATUS, 2
    return
    movlw 0x00
    movwf blue_send_counter
    banksel PIE1
    bcf PIE1, 4
    return
    
;MAIN LOOP
main_loop:
    movlb    00h
    btfsc    task_flags, 0
    call     get_temp
    movlb    00h
    btfsc    task_flags, 1
    call     get_humidity
    movlb    00h
    btfsc    task_flags, 2
    call     get_luminosity
    movlb    00h
    btfsc    task_flags, 3
    call     check_empty_space
    movlb    00h
    btfsc    task_flags, 4
    call     try_read
    call blue_check_and_send
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
    bcf      task_flags, 0
    bsf      task_flags, 1
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
    bcf      task_flags, 1
    bsf      task_flags, 2
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
    bcf      task_flags, 2
    bsf      task_flags, 3
    return

wait_acquisition:                   ; Wait for acquisition (6 us)
    nop
    return

check_empty_space:
    bcf      task_flags, 3
    bsf	     task_flags, 4	    ; To remove when Bluetooth is configured
    movf     FSR0H, 0
    xorlw    max_address_high
    btfss    STATUS, 2
    goto     end_check
    movf     FSR0L, 0
    xorlw    max_address_low
    btfsc    STATUS, 2
    bsf      status_flags, 0
    goto     end_check
    return

end_check:
    ; sleep			    ; To remove when Bluetooth managed
    return

; Task triggered by a Bluetooth connection
try_read:
    ; Check read = write address
    movf     current_address_write_high, 0
    xorwf    current_address_read_high, 0
    btfss    STATUS, 2
    goto     read_data              ; Still smthg to read
    movf     current_address_write_low, 0
    xorwf    current_address_read_low, 0
    btfsc    STATUS, 2
    goto     clear_data
    goto     read_data              ; Still smthg to read

read_data:
    ; Load the addresses
    movf     current_address_read_low, 0
    movwf    FSR1L
    movf     current_address_read_high, 0
    movwf    FSR1H
    ; Increment read adresses at each step
    ; TODO : 6 times
    moviw    FSR1++
    movf     FSR1L, 0
    movwf    current_address_read_low
    movf     FSR1H, 0
    movwf    current_address_read_high
    return
    
; Clear task and reset all addresses
clear_data:
    bcf      task_flags, 4
    movlw    base_address_low
    movwf    current_address_write_low
    movwf    current_address_read_low
    movlw    base_address_high
    movwf    current_address_write_high
    movwf    current_address_read_high
    return
   
blue_check_and_send:
    ; If blue_send_enabled
    ; end: main_blue_send_end_if
    movlb blue_bank
    btfss blue_send_enabled_addr, blue_send_enabled_bit
    return
    ; Set the indirect register to the helo command
    movlw blue_commands_H
    movwf blue_send_buffer_H
    movlw blue_helo_command_L
    movwf blue_send_buffer_L
    movlw 0x05
    movwf blue_send_size
    bcf blue_send_enabled_addr, blue_send_enabled_bit
    banksel PIE1
    bsf PIE1, 4
    return

; Data for the program
    org 0x1000
    db 'H', 'E', 'L', 'O', 0x0A
    org 0x1005
    db 'G','E', 'T', 0