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
    #define    value_counter    05h

    #define TMR1H_init 10011110B 
    #define TMR1L_init 01011000B    ; TMR1 initial value = 40536
                                    ;      = 50ms with 0.5MHz clock

    PSECT text, abs, class=CODE, delta=2
    
; That is where the MCU will start executing the program (0x00)
    org     00h
    goto    start                   ; jump to the beginning of the code
; That is where the MCU will jump when an interrupt occur (0x04)
    org     04h
    goto    interrupt_routine       ; jump to the interrupt routine
    
;BEGINNING OF THE PROGRAM
start:
    call    initialisation          ; initialisation routine configuring the MCU
    goto    main_loop               ; main loop

;INITIALISATION
initialisation:
    ; configuration of the GPIO
    movlb   01h
    clrf    TRISD                   ; All pins of PORTD are output
    movlb   02h
    movlw   00000000B
    movwf   LATD                    ; RD0..7 = 0;

    ;configuration of clock
    movlb    0x01
    movlw    01101110B
    movwf    OSCCON                 ; 4MHz frequency with the internal oscillator
    movlw    00000000B        
    movwf    OSCTUNE                ; No tuning of the frequency
    
    ; Configuration of Timer1
    movlb    00h
    movlw    00010001B
    movwf    T1CON                  ; Enable timer1 with instruction clock as
                                    ; source and prescale of 1:2
                                    ; Frequency = (4MHz/4)/2 = 0.5MHz
    
    ; Set interrupt on timer 1
    movlw   11000000B
    movwf   INTCON                  ; Enable interrupts and peripheral interrupts
    movlb   01h
    movlw   00000001B
    movwf   PIE1                    ; Enable timer1 peripheral interrupts
    
    ; Set initial timer1 counter value
    call reset_tmr1
    
    ; Declare counter variable at the first GPR  adress of a bank (20h)
    counter EQU 20h
    
    ;Store initial counter value in first GPR adress of bank 2
    movlb    02h
    movlw    value_counter
    movwf    counter
    
    return
    
; Reset the timer1 to 50ms (defined by TMR1x_init)
reset_tmr1:
    movlb 00h
    movlw TMR1H_init
    movwf TMR1H
    movlw TMR1L_init
    movwf TMR1L
    return

; Global interrupt routine
interrupt_routine:
    movlb 00h
    btfsc PIR1, 0
    call timer1_handler             ; Call handler if timer1 interrupt bit set
    retfie
    
timer1_handler:
    movlb   02h
    bsf LATD, 1                     ; Switch on LED on RD1
    
    call reset_tmr1
    
    movlb   02h
    ; Decrement counter by 1. If counter == 0 after, skip next instruction.
    decfsz  counter, 1
    goto timer1_interrupt_continue
    
    ; Executed once every 5 interrupt (250ms)
    movlw   00000001B
    xorwf   LATD, 1                 ; RD0 = !RD0

    movlw   value_counter
    movwf   counter                 ; reset the value of the counter

timer1_interrupt_continue:
    movlb 00h
    bcf PIR1, 0                     ; Reset interrupt notification bit
    
    movlb   02h
    bsf LATD, 1                     ; Switch of LED on RD1
    return

;MAIN LOOP
main_loop:
    
    nop                             ; Main loop that does nothing
    goto main_loop
