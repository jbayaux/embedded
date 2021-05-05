; *********************************************************** ;
;                       Flash Test                            ;
;      Test a flash module by reading its status registers    ;
;                                                             ;
;               INFO2055 - Embedded Systems Project           ;
;              Antoine Malherbe  -  Chloe Preud'Homme         ;
;                 Jerome Bayaux  -  Tom Piron                 ;
;                                                             ;
; *********************************************************** ;

    processor  16f1789
    #include   "config.inc"
    #define    value_counter    09h

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
    banksel  TRISC
    bcf	     TRISC, 3		    ; Set SCK pin to ouptut mode
    bcf	     TRISC, 5		    ; Set SDO pin to output mode
    bsf	     TRISC, 4		    ; Set SDI pin to input mode
    bcf	     TRISD, 0		    ; Set ~SS pin to ouptut mode
    bcf	     TRISD, 4		    ; Set RD4 pin to output (SPI HLD)
    bcf	     TRISD, 5		    ; Set RD5 pin to output (SPI WP)
    
    ; Configuration of SPI module

    ; SCK frequency
    ; Default = 00000010B
    ; Custom  = 00001010B
    banksel  SSP1CON1
    movlw    00000010B		; Enable Serial port pins, CKP bit to 1 and SCK freq = F_osc / 64
    movwf    SSP1CON1
    movlw    8fh		; Set SCK frequency to F_osc / (143 + 1) / 4
    movwf    SSP1ADD
    
    bcf      SSP1STAT, 6        ; Set CKE bit to 0 (Clock Edge for SPI)    
    bsf      SSP1CON1, 4        ; Set CKP bit to 1 (Clock polarity for SPI)
    bsf      SSP1CON1, 5        ; Enable Serial port pins

    banksel  PORTD
    bsf	     PORTD, 4	        ; Set HLD signal to 1
    bsf	     PORTD, 5	        ; Set WP signal to 1
    bsf	     PORTD, 0	        ; Initialize ~SS to 1

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
                                ; Bit 2 : read_status
                                ; Bit 3 : write_status
				; Bit 4 : read_address0
				; Bit 5 : write_address0
    next_task	    EQU 21h
    counter	    EQU 22h

    ; In Bank 4
    data_count	    EQU 20h     ; Number of spi_completion to wait before reading data
    next_data	    EQU 21h	; value to send next
    send_data	    EQU 22h	; Number of bytes to send
    new_data	    EQU 23h	; Bit 0 : change data
    send_mode	    EQU 24h	; Bit 0 : send mode enable

    ; Initialise variables
    movlb    00h
    movlw    00000000B
    movwf    task_flags
    movwf    next_task
    bsf	     next_task, 1
    movlw    value_counter
    movwf    counter
    movlb    04h
    movlw    00000000B
    movwf    data_count
    movwf    next_data
    movwf    send_data
    movwf    send_mode
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
    movlb    00h
    bcf	     PIR1, 3
    movlb    04h
    btfsc    send_mode, 0
    goto     spi_complete_send
    decfsz   data_count
    goto     refresh_buf
    movlb    00h
    bsf	     task_flags, 0	    ; Launch clear task
    return

spi_complete_send:
    decfsz   send_data
    goto     send_next
    btfsc    new_data, 0
    goto     set_next
    bcf	     send_mode, 0
    goto     spi_completion

send_next:
    movf     next_data, 0
    movwf    SSP1BUF
    return

set_next:
    bcf	     new_data, 0
    movlw    42h
    movwf    next_data
    movlw    04h
    movwf    send_data
    goto     spi_completion

refresh_buf:
    movf     SSP1BUF, 0
    movwf    SSP1BUF
    return

timer1_handler:
    bcf	     PIR1, 0		    ; Reset interrupt notification bit
    decfsz   counter
    return

    movlw    value_counter	    ; Start measurements only every ?? sec
    movwf    counter

    btfsc    next_task, 1
    bsf      task_flags, 1
    btfsc    next_task, 2
    bsf      task_flags, 2
    btfsc    next_task, 3
    bsf      task_flags, 3
    btfsc    next_task, 4
    bsf      task_flags, 4
    btfsc    next_task, 5
    bsf      task_flags, 5
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
    call     read_status
    movlb    00h
    btfsc    task_flags, 3
    call     write_volatile
    movlb    00h
    btfsc    task_flags, 4
    call     read_address_0
    movlb    00h
    btfsc    task_flags, 5
    call     write_address_0
    goto     main_loop

; Flash module operations
clear_flash:
    bcf      task_flags, 0
    bsf      PORTD, 0           ; Deselect flash
    btfsc    next_task, 1
    goto     launch_task5
    ; btfsc    next_task, 3
    ; goto     launch_task2
    ; btfsc    next_task, 2
    ; goto     launch_task1
    btfsc    next_task, 4
    goto     launch_task1
    btfsc    next_task, 5
    goto     launch_task4
    return

launch_task1:
    bsf	     next_task, 1
    bcf	     next_task, 2
    bcf      next_task, 3
    bcf	     next_task, 4
    bcf	     next_task, 5
    return

launch_task2:
    bcf      next_task, 1
    bsf	     next_task, 2
    bcf      next_task, 3
    bcf	     next_task, 4
    bcf	     next_task, 5
    return

launch_task3:
    bcf	     next_task, 1
    bcf      next_task, 2
    bsf	     next_task, 3
    bcf	     next_task, 4
    bcf	     next_task, 5
    return

launch_task4:
    bcf	     next_task, 1
    bcf      next_task, 2
    bcf	     next_task, 3
    bsf	     next_task, 4
    bcf	     next_task, 5
    return

launch_task5:
    bcf	     next_task, 1
    bcf      next_task, 2
    bcf	     next_task, 3
    bcf	     next_task, 4
    bsf	     next_task, 5
    return

enable_write:
    bcf      task_flags, 1
    bcf	     PORTD, 0		    ; Select flash
    banksel  SSP1BUF
    movlw    06h		        ; WRITE ENABLE instruction code
    movwf    SSP1BUF            ; send_instruction
    movlw    01h
    movwf    data_count         ; 1 bit exchanged
    movwf    send_data
    return

read_status:
    bcf      task_flags, 2
    bcf      PORTD, 0
    banksel  SSP1BUF
    movlw    85h                ; Register Status 05h, Flag status 70h
    movwf    SSP1BUF
    movlw    02h                ; 2 bits exchanged
    movwf    data_count
    return

write_volatile:
    bcf      task_flags, 3
    bcf	     PORTD, 0
    banksel  SSP1BUF
    movlw    81h
    movwf    SSP1BUF
    movlw    00000000B
    movwf    next_data
    movlw    01h
    movwf    send_data
    movlw    01h
    movwf    data_count
    return

read_address_0:
    bcf      task_flags, 4
    bcf	     PORTD, 0
    banksel  SSP1BUF
    movlw    03h
    movwf    SSP1BUF
    movlw    00h
    movwf    next_data
    movlw    04h
    bsf	     send_mode, 0
    movwf    send_data
    movlw    03h
    movwf    data_count
    return

write_address_0:
    bcf	     task_flags, 5
    bcf	     PORTD, 0
    banksel  SSP1BUF
    movlw    02h
    movwf    SSP1BUF
    movlw    00h
    movwf    next_data
    movlw    04h
    bsf	     send_mode, 0
    movwf    send_data
    movlw    01h
    movwf    data_count
    bsf	     new_data, 0
    return
