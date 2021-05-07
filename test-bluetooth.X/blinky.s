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
    ; Configuration of the clock for the bluetooth module
    banksel  OSCCON
    movlw    01101110B
    movwf    OSCCON                 ; 4MHz frequency with the internal oscillator
    movlw    00000000B        
    movwf    OSCTUNE                ; No tuning of the frequency
    
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
    
    ; Configuration of Timer1
    ; Tune it to trigger interrupt every 5 sec
    banksel  T1CON
    movlw    00110001B
    movwf    T1CON                  ; Enable timer1 with instruction clock as
                                    ; source and prescale of 1:8
                                    ; Frequency = (4MHz/4)/8 = 0.125MHz
    
    ; Set interrupts on timer 1 and EUSART receive
    banksel  INTCON
    movlw    11000000B
    movwf    INTCON                 ; Enable interrupts and peripheral interrupts
    banksel  PIE1
    movlw    00100001B
    movwf    PIE1                   ; Enable EUSART receive interrupts

    ; Set variables locations
    local_bank EQU 0x00 ; Bank for local variables
    int_local_bank EQU 0x01 ; Bank for interrupt local variables
 
    ; Set blue locations
    blue_bank EQU 0x02
    blue_recv_counter EQU 0x20
    blue_send_enabled EQU 0x21 ; Bit 0 is command get received
    blue_send_buffer_H EQU 0x22
    blue_send_buffer_L EQU 0x23
    blue_send_size EQU 0x24
    blue_send_counter EQU 0x25
 
    blue_commands_H EQU 0x90 ; Program address 0x10XX
    blue_helo_command_L EQU 0x00 ; Program address 0xXX00
    blue_get_command_L EQU 0x05 ; Program address 0xXX05
 
    ; Initialize blue variables
    movlb blue_bank
    movlw 0x00
    movwf blue_recv_counter
    movwf blue_send_enabled
    movwf blue_send_counter
    
    ; Timer1
    timer_bank EQU 0x03
    timer_counter EQU 0x20
    timer_init EQU 0x04
 
    movlb timer_bank
    movlw timer_init
    movwf timer_counter
    return

;INTERRUPT ROUTINES
interrupt_routines:
    banksel  PIR1            
    btfsc    PIR1, 0
    call     timer1_handler         ; Call handler if timer1 interrupt bit set
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
    movlb timer_bank
    decfsz   timer_counter                ; Start measurements only every 5 sec
    return
    
    movlb timer_bank
    movlw    timer_init
    movwf    timer_counter                ; Reset timer counter
    return

blue_receive_handler:
    ; Local variables declaration
    local_recv_char EQU 0x20
    local_FSR0L EQU 0x21
    local_FSR0H EQU 0x22
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
    bsf blue_send_enabled, 0
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
    call blue_check_and_send
    goto     main_loop

blue_check_and_send:
    ; If blue_send_enabled
    ; end: main_blue_send_end_if
    movlb blue_bank
    btfss blue_send_enabled, 0
    return
    ; Set the indirect register to the helo command
    movlw blue_commands_H
    movwf blue_send_buffer_H
    movlw blue_helo_command_L
    movwf blue_send_buffer_L
    movlw 0x05
    movwf blue_send_size
    bcf blue_send_enabled, 0
    banksel PIE1
    bsf PIE1, 4
    return
    
; Data for the program
    org 0x1000
    db 'H', 'E', 'L', 'O', 0x0A
    org 0x1005
    db 'G','E', 'T', 0