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
    bsf	     TRISA, 0		    ; Set RA0 to input
    banksel  ANSELA
    bsf	     ANSELA, 0		    ; Set input mode of RA0 to analog
    banksel  WPUA
    bcf	     WPUA, 0		    ; Disable weak pull-up on RA0
    
    ; Configuration of ADC
    banksel  ADCON0
    movlw    00000001B		    ; ADC enabled and AN0 selected as source
    movwf    ADCON0
    movlw    01000000B		    ; Frequency = Fosc/4, result as sign-magnitude
    movwf    ADCON1
    movlw    00001111B		    ; Negative ref set to VSS
    movwf    ADCON2

    ; Configuration of clock
    movlb    01h
    movlw    01101110B
    movwf    OSCCON                 ; 4MHz frequency with the internal oscillator
    movlw    00000000B        
    movwf    OSCTUNE                ; No tuning of the frequency
    
    ; Configuration of Timer1
    ; Tune it to trigger interrupt every 5 sec
    movlb    00h
    movlw    00110001B
    movwf    T1CON                  ; Enable timer1 with instruction clock as
                                    ; source and prescale of 1:8
                                    ; Frequency = (4MHz/4)/8 = 0.25MHz
    
    ; Set interrupts on timer 1 and ADC
    movlw    11000000B
    movwf    INTCON                 ; Enable interrupts and peripheral interrupts
    movlb    01h
    movlw    01000001B
    movwf    PIE1                   ; Enable timer1 and ADC interrupts
    
    ; Declare variables in GPRs
    task_flags EQU 20h		    ; Bit 0 : flag for temp task
    TEMPL EQU 20h
    TEMPH EQU 21h
    
    ; Initialise variables
    movlb    00h
    movlw    00000000B
    movwf    task_flags
    movlb    01h
    movlw    00000000B
    movwf    TEMPL
    movlw    00000000B
    movwf    TEMPH
    
    return

;INTERRUPT ROUTINES
interrupt_routines:
    movlb    00h
    btfsc    PIR1, 0
    call     timer1_handler	    ; Call handler if timer1 interrupt bit set
    btfsc    PIR1, 6
    call     adc_completion
    retfie
    
timer1_handler:
    banksel  ADCON0
    bsf	     ADCON0, 1		    ; Set ADC Conversion Status bit
				    ; to start conversion
    banksel  PIR1
    bcf	     PIR1, 0                ; Reset interrupt notification bit
    return
    
adc_completion:
    bsf	     task_flags, 0
    
    banksel  PIR1
    bcf	     PIR1, 6                ; Reset interrupt notification bit
    return

;MAIN LOOP
main_loop:
    movlb    00h
    btfsc    task_flags, 0
    call     get_temp
    goto     main_loop
    
get_temp:
    banksel  ADRESH
    movf     ADRESH, 0
    movwf    TEMPH
    movf     ADRESL, 0
    movwf    TEMPL
    movlb    00h
    bcf	     task_flags, 0
    return
    
    ; /!\ : Add code pour gérer qd on va devoir switcher d'une source analog à
    ;	    une autre dans l'ADC
    ; - Adapt timer to trigger every 5sec or smthg