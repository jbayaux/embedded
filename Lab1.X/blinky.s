; *********************************************************** ;
;                           BLINKY                            ;
;       make a LED blink at a given frequency using Timer1    ;
;         and interrupts. Turn on an other LED while in       ;
;                    the interrupt handler.                   ;
;                                                             ;
;               INFO0064 - Embedded Systems - Lab 2           ;
;              Antoine Malherbe  -  Chloé Preud'Homme         ;
;                 Jérôme Bayaux  -  Tom Piron                 ;
;                                                             ;
; *********************************************************** ;


    processor 16f1789
    #include     "config.inc"
    ;#define    value_counter    05h

    PSECT text, abs, class=CODE, delta=2
    
; That is where the MCU will start executing the program (0x00)
    org      00h
    goto     start                   ; jump to the beginning of the code
; That is where the MCU will jump when an interrupt occur (0x04)
    org      04h
    goto     interrupt_routines      ; jump to the interrupt routine
    
;BEGINNING OF THE PROGRAM
start:
    call     initialisation          ; initialisation routine configuring the MCU
    goto     main_loop               ; main loop

;INITIALISATION
initialisation:
    ; configuration of the GPIO
    banksel  TRISA
    bsf	     TRISA, 0		    ; Set RA0 to input for temp sensor
    bsf	     TRISA, 1		    ; Set RA1 to input for luminosity sensor
    bsf	     TRISB, 4		    ; Set RB4 to input for humidity sensor
    banksel  ANSELA
    bsf	     ANSELA, 0		    ; Set input mode of RA0 to analog
    bsf	     ANSELA, 1		    ; Set input mode of RA1 to analog
    bsf	     ANSELB, 4		    ; Set input mode of RB4 to analog
    banksel  WPUA
    bcf	     WPUA, 0		    ; Disable weak pull-up on RA0
    ;bcf	     WPUA, 1		    ; Disable weak pull-up on RA1
    bcf	     WPUB, 4		    ; Disable weak pull-up on RB4

    ; Configuration of ADC
    banksel  ADCON1
    movlw    01000000B		    ; Frequency = Fosc/4, result as sign-magnitude
    movwf    ADCON1
    movlw    00001111B		    ; Negative ref set to VSS
    movwf    ADCON2

    ; Configuration of Flash modules pins
    banksel  TRISA
    bcf	     TRISA, 5		    ; Set ~SS pin to output mode
    bcf	     TRISC, 3		    ; Set SCK pin to ouptut mode
    bcf	     TRISC, 5		    ; Set SDO pin to output mode
    bsf	     TRISC, 4		    ; Set SDI pin to input mode
    bcf	     TRISD, 4		    ; Set RD4 pin to output (SPI HLD)
    bcf	     TRISD, 5		    ; Set RD5 pin to output (SPI WP)
    
    ; Configuration of SPI module
    banksel  SSP1STAT
    bcf	     SSP1STAT, 6	    ; Set CKE bit to 0 (Clock Edge for SPI)
    ; bsf    SSP1CON1, 4	    ; Set CKP bit to 1 (Clock polarity for SPI)
    ; bsf    SSP1CON1, 5	    ; Enable Serial port pins
    movlw    00110010B		    ; Enable Serial port pins, CKP bit to 1 and SCK freq = F_osc / 64
    movwf    SSP1CON1
    banksel  PORTD
    bsf	     PORTD, 4		    ; Set ~HLD signal to 1
    bsf	     PORTD, 5		    ; Set ~WP signal to 1

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
    
    ; Set interrupts on timer 1 and ADC
    movlw    11000000B
    movwf    INTCON                 ; Enable interrupts and peripheral interrupts
    banksel  PIE1
    movlw    01001001B
    movwf    PIE1                   ; Enable timer1, ADC and SPI interrupts
    
    ; Declare variables in GPRs
    ; In Bank 0
    task_flags EQU 20h		    ; Bit 0 : flag for temp task
				    ; Bit 1 : flag for humidity task
				    ; Bit 2 : flag for luminosity task
				    ; Bit 3 : flag to enable write
				    ; Bit 4 : flag to store data
				    ; Bit 5 : flag to compute next data to send

    counter    EQU 21h

    ; In Bank 1
    TEMPL EQU 20h
    TEMPH EQU 21h
    HUML  EQU 22h
    HUMH  EQU 23h
    LUML  EQU 24h
    LUMH  EQU 25h

    ; In Bank 4
    flash_status	EQU 20h	    ; Bit 0 : Still something to send
				    ; Bit 1 : Address byte 1
				    ; Bit 2 : Address byte 2
				    ; Bit 3 : Address byte 3
				    ; Bit 4 : Value
				    ; Bit 5 : PROGRAM command
    next_data		EQU 21h
    next_address_byte1	EQU 22h
    next_address_byte2	EQU 23h
    next_address_byte3	EQU 24h
    
    ; Initialise variables
    movlb    00h
    movlw    00000000B
    movwf    task_flags
    movlw    0Ah
    movwf    counter
    movlb    04h
    movlw    00000000B
    movwf    flash_status
    movwf    next_data
    movwf    next_address_byte1
    movwf    next_address_byte2
    movwf    next_address_byte3
    return

;INTERRUPT ROUTINES
interrupt_routines:
    banksel  PIR1
    btfsc    PIR1, 3
    call     spi_completion
    ; If the previous interrupt routines performs a banksel inside, we must set the bank again to look at PIR1
    banksel  PIR1		    
    btfsc    PIR1, 0
    call     timer1_handler	    ; Call handler if timer1 interrupt bit set
    banksel  PIR1
    btfsc    PIR1, 6
    call     adc_completion
    ;movlb    00h   ; Put this if other checks on registers of Bank 0 appear after
    retfie

spi_completion:
    bcf	     PIR1, 3
    movlb    04h
    btfsc    flash_status, 0
    goto     write_data
    btfsc    flash_status, 5
    goto     start_program
    ; TODO (read operation)
    bsf	     task_flags, 6	    ; Launch clear tasks

write_data:
    ; movlb    04h
    movf     next_data, 0
    movwf    SSP1BUF
    movlb    00h
    bsf	     task_flags, 5

start_program:
    bsf	     task_flags, 4	    ; Enable store_data task
    return

timer1_handler:
    bcf	     PIR1, 0                ; Reset interrupt notification bit
    decfsz   counter		    ; Start measurements only every 5 sec
    return
    
    bsf	     task_flags, 0	    ; Start task for temp measurement
    movlw    1Ah
    movwf    counter
    return
    
adc_completion:
    bcf	     PIR1, 6                ; Reset interrupt notification bit
    btfsc    task_flags, 1
    goto     store_temp
    btfsc    task_flags, 2
    goto     store_humidity
    goto     store_luminosity
    
store_temp:
    banksel  ADRESH
    movf     ADRESH, 0
    movwf    TEMPH
    movf     ADRESL, 0
    movwf    TEMPL
    return
    
store_humidity:
    banksel  ADRESH
    movf     ADRESH, 0
    movwf    HUMH
    movf     ADRESL, 0
    movwf    HUML
    return
    
store_luminosity:
    banksel  ADRESH
    movf     ADRESH, 0
    movwf    LUMH
    movf     ADRESL, 0
    movwf    LUML
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
    call     enable_write
    movlb    00h
    btfsc    task_flags, 4
    call     store_data
    movlb    00h
    btfsc    task_flags, 5
    call     compute_next_data
    movlb    00h
    btfsc    task_flags, 6
    call     clear_flash
    goto     main_loop
    
get_temp:
    banksel  ADCON0
    btfsc    ADCON0, 1		    ; Test if ADC already used
    return
    
    movlw    00000001B		    ; ADC enabled and AN0 selected as source
    movwf    ADCON0
    call     wait_acquisition
    bsf	     ADCON0, 1		    ; Set ADC Conversion Status bit
				    ; to start conversion
    movlb    00h
    bsf	     task_flags, 1
    bcf	     task_flags, 0
    return
    
get_humidity:
    banksel  ADCON0
    btfsc    ADCON0, 1		    ; Test if ADC already used
    return
    
    movlw    00101101B		    ; ADC enabled and AN11 selected as source
    movwf    ADCON0
    call     wait_acquisition
    bsf	     ADCON0, 1		    ; Set ADC Conversion Status bit
				    ; to start conversion
    movlb    00h
    bsf	     task_flags, 2
    bcf	     task_flags, 1
    return
    
get_luminosity:
    banksel  ADCON0
    btfsc    ADCON0, 1		    ; Test if ADC already used
    return
    
    ;movlw    00000101B		    ; ADC enabled and AN1 selected as source
    ;movwf    ADCON0
    call     wait_acquisition
    bsf	     ADCON0, 1		    ; Set ADC Conversion Status bit
				    ; to start conversion
    movlb    00h
    bsf	     task_flags, 3
    bcf	     task_flags, 2
    return

wait_acquisition:		    ; Wait for acquisition (6 us)
    nop
    return

; Flash module operations
enable_write:
    banksel  PORTA
    bcf	     PORTA, 5		    ; Select flash
    banksel  SSP1BUF
    movlw    06h		    ; WRITE ENABLE instruction code
    movwf    SSP1BUF
    bsf	     flash_status, 5	    ; Tell that a PROGRAM isntruction have to be done next
    bcf	     task_flags, 3
    return
    
    
store_data:
    banksel  PORTA
    bsf	     PORTA, 5		    ; Deselect flash module to apply WRITE ENABLED COMMAND
    nop
    nop
    nop
    ; TODO? : Wait for the slave deselect to be seen  by the flash memory ?
    bcf	     PORTA, 5		    ; Select flash
    banksel  SSP1BUF
    movlw    02h		    ; PROGRAM command
    movwf    SSP1BUF
    bsf	     flash_status, 0	    ; Tell that there is still something to send
    bsf	     flash_status, 3	    ; Set flag to send the first address byte next
    bsf	     task_flags, 5	    ; Enable task that compute the next data
    bcf	     task_flags, 4
    return

compute_next_data:
    movlb    00h
    bcf	     task_flags, 5	    ; Clear flag for all computation
    movlb    04h
    btfsc    flash_status, 1
    goto     address_byte1
    btfsc    flash_status, 2
    goto     address_byte2
    btfsc    flash_status, 3
    goto     address_byte3
    ; TODO : Aller chercher les valeurs dans temp, humid, ...
    bcf	     flash_status, 0	    ; Nothing left to send
    return

address_byte1:
    movf     next_address_byte1, 0
    movwf    next_data
    bcf	     flash_status, 1
    bsf	     flash_status, 4
    return

address_byte2:
    movf     next_address_byte2, 0
    movwf    next_data
    bcf	     flash_status, 2
    bsf	     flash_status, 1
    return

address_byte3:
    movf     next_address_byte3, 0
    movwf    next_data
    bcf	     flash_status, 3
    bsf	     flash_status, 2
    return

clear_flash:
    banksel  PORTA
    bsf	     PORTA, 5			; Deselect flash
    ; TODO: Increment next_address (!! sur 3 byte)
