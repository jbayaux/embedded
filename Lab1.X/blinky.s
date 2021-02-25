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
    org     00h
    goto    start                   ; jump to the beginning of the code
; That is where the MCU will jump when an interrupt occur (0x04)
    org     04h
    goto    interrupt_routines      ; jump to the interrupt routine
    
;BEGINNING OF THE PROGRAM
start:
    call    initialisation          ; initialisation routine configuring the MCU
    goto    main_loop               ; main loop

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
    movlw    01000001B
    movwf    PIE1                   ; Enable timer1 and ADC interrupts
    
    ; Declare variables in GPRs
    ; In Bank 0
    task_flags EQU 20h		    ; Bit 0 : flag for temp task
				    ; Bit 1 : flag for humidity task
				    ; Bit 2 : flag for luminosity task
    counter    EQU 21h
    ; In Bank 1
    TEMPL EQU 20h
    TEMPH EQU 21h
    HUML  EQU 22h
    HUMH  EQU 23h
    LUML  EQU 24h
    LUMH  EQU 25h
    
    ; Initialise variables
    movlb    00h
    movlw    00000000B
    movwf    task_flags
    movlw    0Ah
    movwf    counter
    return

;INTERRUPT ROUTINES
interrupt_routines:
    movlb    00h
    btfsc    PIR1, 0
    call     timer1_handler	    ; Call handler if timer1 interrupt bit set
    btfsc    PIR1, 6
    call     adc_completion
    ;movlb    00h   ; Put this if other checks on registers of Bank 0 appear after
    retfie
    
timer1_handler:
    ;banksel  PIR1
    bcf	     PIR1, 0                ; Reset interrupt notification bit
    decfsz   counter		    ; Start measurements only every 5 sec
    return
    
    bsf	     task_flags, 0	    ; Start task for temp measurement
    movlw    0Ah
    movwf    counter
    return
    
adc_completion:
    ;banksel  PIR1
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
    bcf	     task_flags, 2
    return
    
wait_acquisition:		    ; Wait for acquisition (6 us)
    nop
    return