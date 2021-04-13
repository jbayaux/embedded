; *********************************************************** ;
;                       Flash Test                            ;
;      Test a flash module by reading its status registers    ;
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
    ; Configuration of Flash modules pins
    banksel  TRISA
    bcf	     TRISA, 5		    ; Set ~SS pin to output mode
    bcf	     TRISC, 3		    ; Set SCK pin to ouptut mode
    bcf	     TRISC, 5		    ; Set SDO pin to output mode
    bsf	     TRISC, 4		    ; Set SDI pin to input mode
    bcf	     TRISD, 4		    ; Set RD4 pin to output (SPI HLD)
    bcf	     TRISD, 5		    ; Set RD5 pin to output (SPI WP)
    
    ; Configuration of SPI module

    ; SCK frequency
    ; Default = 00000010B
    ; Custom  = 00001010B
    movlw    00000010B		; Enable Serial port pins, CKP bit to 1 and SCK freq = F_osc / 64
    movwf    SSP1CON1
    movlw    8fh		; Set SCK frequency to F_osc / (143 + 1) / 4
    movwf    SSP1ADD
    
    banksel  SSP1STAT
    bcf      SSP1STAT, 6        ; Set CKE bit to 0 (Clock Edge for SPI)    
    bsf      SSP1CON1, 4        ; Set CKP bit to 1 (Clock polarity for SPI)
    bsf      SSP1CON1, 5        ; Enable Serial port pins

    banksel  PORTD
    bcf	     PORTD, 4	        ; Set ~HLD signal to 1
    bcf	     PORTD, 5	        ; Set ~WP signal to 1
    bsf	     PORTA, 5	        ; Initialize ~SS to 1

    ; Configuration of internal clock
    banksel  OSCCON
    movlw    01101110B
    movwf    OSCCON             ; 4MHz frequency with the internal oscillator
    movlw    00000000B        
    movwf    OSCTUNE            ; No tuning of the frequency
    
    ; Configuration of Timer1
    ; Tune it to trigger interrupt every 5 sec
    banksel  T1CON
    movlw    00110001B
    movwf    T1CON              ; Enable timer1 with instruction clock as
                                ; source and prescale of 1:8
                                ; Frequency = (4MHz/4)/8 = 0.125MHz
    
    ; Set interrupts on timer 1 and ADC
    movlw    11000000B
    movwf    INTCON             ; Enable interrupts and peripheral interrupts
    banksel  PIE1
    movlw    01001001B
    movwf    PIE1               ; Enable timer1, ADC and SPI interrupts
    
    ; Declare variables in GPRs
    ; In Bank 0
    task_flags	    EQU 20h	; Bit 0 : clear_flash
                                ; Bit 1 : write_enable
                                ; Bit 2 : read_status1
                                ; Bit 3 : read_status2
    next	    EQU 21h
    counter	    EQU 22h

    ; In Bank 4
    data_count	    EQU 20h     ; Number of spi_completion to wait before reading data
    
    ; Initialise variables
    movlb    00h
    movlw    00000000B
    movwf    task_flags
    movwf    next
    movlw    10h
    movwf    counter
    movlb    04h
    movlw    00000000B
    movwf    data_count
    return

;INTERRUPT ROUTINES
interrupt_routines:
    banksel  PIR1
    btfsc    PIR1, 3
    call     spi_completion
    ; If the previous interrupt routines performs a banksel inside,
    ; we must set the bank again to look at PIR1
    banksel  PIR1		    
    btfsc    PIR1, 0
    call     timer1_handler	    ; Call handler if timer1 interrupt bit set
    retfie

spi_completion:
    bcf	     PIR1, 3
    movlb    04h
    movf     data_count, 0
    decfsz   data_count
    goto     refresh_buf
    movlb    00h
    bsf	     task_flags, 0	    ; Launch clear task
    return

refresh_buf:
    movf     SSP1BUF, 0
    movwf    SSP1BUF
    banksel  PIR1
    bsf	     PIR1, 3
    return

timer1_handler:
    bcf	     PIR1, 0		    ; Reset interrupt notification bit
    decfsz   counter
    return
    
    btfsc    next, 0
    goto     enable_next_task

    bsf	     next, 0
    bsf	     task_flags, 1	    ; Start recurrent task
    ; Bit 1 : Write enable
    ; Bit 2 : Read status 1
    ; Bit 3 : Read status 2
    movlw    10h		    ; Start measurements only every ?? sec
    movwf    counter
    return

enable_next_task:
    bsf      task_flags, 2
    bcf	     next, 0
    movlw    12h
    movwf    counter
    return

;MAIN LOOP
main_loop:
    movlb    00h
    btfsc    task_flags, 0
    call     clear_flash
    movlb    00h
    btfsc    task_flags, 1
    call     enable_write
    movlb    00h
    btfsc    task_flags, 2
    call     read_status1
    movlb    00h
    btfsc    task_flags, 3
    call     read_status2
    goto     main_loop

; Flash module operations
clear_flash:
    bcf      task_flags, 0
    bsf      PORTA, 5           ; Deselect flash
    return

enable_write:
    bcf      task_flags, 1
    bcf	     PORTA, 5		    ; Select flash
    banksel  SSP1BUF
    movlw    06h		        ; WRITE ENABLE instruction code
    movwf    SSP1BUF            ; send_instruction
    movlw    01h
    movwf    data_count         ; 1 bit exchanged
    banksel  PIR1
    bsf	     PIR1, 3
    return

read_status1:
    bcf      task_flags, 2
    bcf      PORTA, 5
    banksel  SSP1BUF
    movlw    05h                ; Register Status
    movwf    SSP1BUF
    movlw    02h                ; 2 bits exchanged
    movwf    data_count
    banksel  PIR1
    bsf	     PIR1, 3
    return

read_status2:
    bcf      task_flags, 3
    bcf      PORTA, 5
    banksel  SSP1BUF
    movlw    70h                ; Flag Status
    movwf    SSP1BUF
    movlw    03h                ; 3 bits exchanged
    movwf    data_count
    return
