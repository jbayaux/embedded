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


    processor	 16f1789
    #include     "config.inc"
    #define      measure_counter    04h

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
    ; bcf      WPUA, 1                ; Disable weak pull-up on RA1
    bcf      WPUB, 4                ; Disable weak pull-up on RB4
    
    ; Configuration of the bluetooth module
    banksel TX1STA
     bcf RC1STA, 4 ; Enable the receiver circuit of EUSART
     bcf TX1STA, 4 ; Set asynchronous mode
     bcf RC1STA, 7 ; Enables EUSART
     bcf RC1STA, 6 ; Enable 9th bit

    ; Configuration of clock
    banksel  OSCCON
    movlw    01110110B
    movwf    OSCCON                 ; 4MHz frequency with the internal oscillator
    movlw    00100000B        
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
    movlw    00100000B
    movwf    PIE1                   ; Enable timer1 interrupts

    counter      EQU 22h
    
    ; Initialise variables
    movlb    00h
    movlw    measure_counter
    movwf    counter
    movlb    04h
    movlw    00000000B
    return

;INTERRUPT ROUTINES
interrupt_routines:
    banksel  PIR1            
    btfsc    PIR1, 5
    call     timer1_handler         ; Call handler if timer1 interrupt bit set
    retfie

timer1_handler:
    bcf      PIR1, 0                ; Reset interrupt notification bit
    
    banksel RC1REG
    movfw RC1REG
if:
    sublw 0x2A ; If received character == *
    btfsc STATUS, 2
    goto end_if
    ; Add code to ligth a LED
end_if:
    return

;MAIN LOOP
main_loop:
    goto     main_loop