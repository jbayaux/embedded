; *********************************************************** ;
;                           Mushroom                          ;
;       Collect temperature, humidity and luminosity          ;
;             Store it into an external flash                 ;
;                                                             ;
;               INFO2055 - Embedded Systems Project           ;
;              Antoine Malherbe  -  Chloe Preud'Homme         ;
;                   Jerome Bayaux  -  Tom Piron               ;
;                                                             ;
; *********************************************************** ;


    processor	 16f1789
    #include     "config.inc"
    #define      measure_counter    10h

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

    ; Configuration of ADC
    banksel  ADCON1
    movlw    01000000B              ; Frequency = Fosc/4, result as sign-magnitude
    movwf    ADCON1
    movlw    00001111B              ; Negative ref set to VSS
    movwf    ADCON2

    ; Configuration of Flash modules pins
    banksel  TRISC
    bcf      TRISC, 3               ; Set SCK pin to ouptut mode
    bcf      TRISC, 5               ; Set SDO pin to output mode
    bsf      TRISC, 4               ; Set SDI pin to input mode
    bcf	     TRISD, 0		    ; Set RD0 pin to output (SPI SS)
    bcf      TRISD, 4               ; Set RD4 pin to output (SPI HLD)
    bcf      TRISD, 5               ; Set RD5 pin to output (SPI WP)
    
    ; Configuration of SPI module
    banksel  SSP1CON1
    movlw    00000010B
    movwf    SSP1CON1		    ; Set SPI clock frequency to F_OSC / 64
    
    bcf      SSP1STAT, 6            ; Set CKE bit to 0 (Clock Edge for SPI)
    bsf      SSP1CON1, 4            ; Set CKP bit to 1 (Clock polarity for SPI)
    bsf      SSP1CON1, 5            ; Enable Serial port pins

    banksel  PORTD
    bsf      PORTD, 4               ; Set HLD signal to 1
    bsf      PORTD, 5               ; Set WP signal to 1
    bsf      PORTD, 0               ; Initialize ~SS to 1

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
    task_flags   EQU 20h            ; Bit 0 : flag for temp task
                                    ; Bit 1 : flag for humidity task
                                    ; Bit 2 : flag for luminosity task
                                    ; Bit 3 : flag to enable write
                                    ; Bit 4 : flag to store data
                                    ; Bit 5 : flag to compute next data to send
                                    ; Bit 6 : flag to clear transmission with flash
    task_flags2  EQU 21h            ; Bit 0 : flag to read data
                                    ; Bit 1 : flag to use read data

    counter      EQU 22h

    ; In Bank 1
    TEMPL        EQU 20h
    TEMPH        EQU 21h
    HUML         EQU 22h
    HUMH         EQU 23h
    LUML         EQU 24h
    LUMH         EQU 25h

    ; In Bank 4
    flash_status          EQU 20h   ; Bit 0 : Still something to send
                                    ; Bit 1 : Address byte 1
                                    ; Bit 2 : Address byte 2
                                    ; Bit 3 : Address byte 3
                                    ; Bit 4 : PROGRAM command
                                    ; Bit 5 : Luminosity
                                    ; Bit 6 : Humidity
                                    ; Bit 7 : Light

    next_data             EQU 21h
    next_address_byte_write1    EQU 22h
    next_address_byte_write2    EQU 23h
    next_address_byte_write3    EQU 24h
    next_address_byte_read1    EQU 25h
    next_address_byte_read2    EQU 26h
    next_address_byte_read3    EQU 27h
    flash_status2         EQU 28h   ; Bit 0 : High or low part of data, 0 means "high"
                                    ; Bit 1 : Read mode
                                    ; Bit 2 : Next data is bullshit
				    ; Bit 3 : Still something to read
    
    ; Initialise variables
    movlb    00h
    movlw    00000000B
    movwf    task_flags
    movwf    task_flags2
    movlw    measure_counter
    movwf    counter
    movlb    04h
    movlw    00000000B
    movwf    flash_status
    movwf    flash_status2
    movwf    next_data
    movwf    next_address_byte_write1
    movwf    next_address_byte_write2
    movwf    next_address_byte_write3
    movwf    next_address_byte_read1
    movwf    next_address_byte_read2
    movwf    next_address_byte_read3
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
    call     timer1_handler         ; Call handler if timer1 interrupt bit set
    banksel  PIR1
    btfsc    PIR1, 6
    call     adc_completion
    retfie

spi_completion:
    bcf      PIR1, 3
    movlb    04h
    btfsc    flash_status, 0        ; If still something to send
    goto     write_data             ; Copy next data to send into the buffer for immediate transmission
    btfsc    flash_status2, 3       ; If still something to read
    goto     save_data              ; Save what has been read by the SPI module and relaunch a data cycle
    btfsc    flash_status, 4        ; If write_enable was sent
    goto     start_program          ; Start sending data to write in memory
    movlb    00h
    bsf      task_flags, 6          ; Launch clear task
    return

write_data:
    movf     next_data, 0
    movwf    SSP1BUF
    movlb    00h
    bsf      task_flags, 5          ; Compute next data to send
    return

save_data:
    movf     SSP1BUF, 0
    movwf    SSP1BUF                ; Relaunch a data cycle
    movlb    00h
    bsf      task_flags2, 1         ; Use the extracted data
    return
    
    
start_program:
    bcf      flash_status, 4
    movlb    00h
    bsf      task_flags, 4          ; Enable store_data task
    return

timer1_handler:
    bcf      PIR1, 0                ; Reset interrupt notification bit
    decfsz   counter                ; Start measurements only every 5 sec
    return
    
    bsf      task_flags, 0          ; Start task for temp measurement
    movlw    measure_counter
    movwf    counter                ; Reset timer counter
    return
    
adc_completion:
    bcf      PIR1, 6                ; Reset interrupt notification bit
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
    movlb    00h
    btfsc    task_flags2, 0
    call     read_data
    movlb    00h
    btfsc    task_flags2, 1
    call     use_data
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
    
    ; movlw    00000101B              ; ADC enabled and AN1 selected as source
    ; movwf    ADCON0
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

; Flash module operations
enable_write:
; Send a WRITE ENABLE instruction to the flash
    bcf      task_flags, 3
    banksel  PORTD
    bcf      PORTD, 0               ; Select flash
    banksel  SSP1BUF
    movlw    06h                    ; WRITE ENABLE instruction code
    movwf    SSP1BUF
    bsf      flash_status, 4        ; Tell that a PROGRAM instruction have to be done next
    ; movlb    00h
    ; movf     task_flags, 0          ; Why ??
    return
    
store_data:
; Store the last measurement on the flash memory
    banksel  PORTD
    bsf      PORTD, 0               ; Deselect flash module to apply WRITE ENABLED COMMAND
    nop                             ; Wait for the slave deselect to be seen by the flash memory ?
    nop
    bcf      PORTD, 0               ; Select flash
    banksel  SSP1BUF
    movlw    02h                    ; PROGRAM command
    movwf    SSP1BUF
    bsf      flash_status, 0        ; Tell that there is still something to send
    bsf      flash_status, 3        ; Set flag to send the first address byte next
    movlb    00h
    bsf      task_flags, 5          ; Compute what to send next
    bcf      task_flags, 4
    return

compute_next_data:
; Compute which byte should be sent next and store it in next_data
    bcf      task_flags, 5
    movlb    04h
    btfsc    flash_status2, 1
    goto     compute_next_data_read
    goto     compute_next_data_write
    
compute_next_data_write:
    btfsc    flash_status, 1
    goto     address_byte1
    btfsc    flash_status, 2
    goto     address_byte2
    btfsc    flash_status, 3
    goto     address_byte3
    btfsc    flash_status, 5
    goto     temperature
    btfsc    flash_status, 6
    goto     humidity
    ; btfsc    flash_status, 7
    ; goto     luminosity

    bcf      flash_status, 0     ; Nothing left to send
    return

address_byte1:
    movf     next_address_byte_write1, 0
    movwf    next_data
    bcf      flash_status, 1
    bsf      flash_status, 5
    return

address_byte2:
    movf     next_address_byte_write2, 0
    movwf    next_data
    bcf      flash_status, 2
    bsf      flash_status, 1
    return

address_byte3:
    movf     next_address_byte_write3, 0
    movwf    next_data
    bcf      flash_status, 3
    bsf      flash_status, 2
    return

temperature:
    btfss    flash_status2, 0
    goto     temperature_high
    bcf      flash_status2, 0       ; Tell that next byte to send is the high one
    movlb    01h
    movf     TEMPL, 0
    movlb    04h
    movwf    next_data
    bcf      flash_status, 5
    bsf      flash_status, 6
    return

temperature_high:
    bsf      flash_status2, 0       ; Tell that next byte to send is the low one
    movlb    01h
    movf     TEMPH, 0
    movlb    04h
    movwf    next_data
    return

humidity:
    btfss    flash_status2, 0
    goto     humidity_high
    bcf      flash_status2, 0       ; Tell that next byte to send is the high one
    movlb    01h
    movf     HUML, 0
    movlb    04h
    movwf    next_data
    bcf      flash_status, 6
    bsf      flash_status, 7
    return

humidity_high:
    bsf      flash_status2, 0       ; Tell that next byte to send is the low one
    movlb    01h
    movf     HUMH, 0
    movlb    04h
    movwf    next_data
    return

luminosity:
    btfss    flash_status2, 0
    goto     luminosity_high
    bcf      flash_status2, 0       ; Tell that next byte to send is the high one
    movlb    01h
    movf     LUML, 0
    movlb    04h
    movwf    next_data
    bcf      flash_status, 7
    return

luminosity_high:
    bsf      flash_status2, 0       ; Tell that next byte to send is the low one
    movlb    01h
    movf     LUMH, 0
    movlb    04h
    movwf    next_data
    return

compute_next_data_read:
; store the n-th byte of the address to read
    movlb    04h
    btfsc    flash_status, 1
    goto     address_byte1_read
    btfsc    flash_status, 2
    goto     address_byte2_read 
    btfsc    flash_status, 3
    goto     address_byte3_read
    btfsc    flash_status, 5
    bcf	     flash_status, 0        ; Nothing left to send
    return

address_byte1_read:
    bcf      flash_status, 1
    movf     next_address_byte_read1, 0
    movwf    next_data
    bsf      flash_status, 5        ; Next SPI completion means that we will start to read
    return

address_byte2_read:
    bcf      flash_status, 2
    movf     next_address_byte_read2, 0
    movwf    next_data
    bsf      flash_status, 1
    return

address_byte3_read:
    bcf      flash_status, 3
    movf     next_address_byte_read3, 0
    movwf    next_data
    bsf      flash_status, 2
    return

clear_flash:
    bcf      task_flags, 6
    bsf      PORTD, 0               ; Deselect flash
    ; If the flash was writing data, we need to increment the writing
    ; address for the next write operation
    movlb    04h
    btfsc    flash_status2, 1
    goto     clear_read
    goto     update_next_address

clear_read:
    bcf	     flash_status2, 1
    movlb    04h
    movlw    00000000B
    movwf    next_address_byte_write1
    movwf    next_address_byte_write2
    movwf    next_address_byte_write3
    movwf    next_address_byte_read1
    movwf    next_address_byte_read2
    movwf    next_address_byte_read3
    return

update_next_address:
    movlw    08h
    addwf    next_address_byte_write1, 1
    movlw    00h
    ; If the addition leads to an overflow, the Carry bit is set to 1
    ; 'addwfc' add the carry to the result of the next addition
    addwfc   next_address_byte_write2, 1
    addwfc   next_address_byte_write3, 1
    movlb    00h
    bsf      task_flags2, 0         ; TO REMOVE !!! Trigger a read operation
    return

read_data:
; Start a READ operation from the flash
; Will be triggered by a connection from Bluetooth
    bcf      task_flags2, 0
    ; Check whether there is something to read or not
    call check_if_read
    btfsc    STATUS, 2
    return

    movlb    00h
    bcf      PORTD, 0               ; Select flash
    movlb    04h
    bsf      flash_status2, 3       ; Tell that there is still something to read
    bsf	     flash_status2, 1	    ; Set read mode
    movlw    03h                    ; READ command
    movwf    SSP1BUF
    bsf      flash_status, 0        ; Tell that there is still something to send
    bsf      flash_status, 3        ; Set flag to send the first address byte next
    movlb    00h
    bsf      task_flags, 5          ; Compute next data to write
    return

check_if_read:
    movlb    04h
    movf     next_address_byte_write1, 0
    xorlw    00h
    btfss    STATUS, 2
    return
    movf     next_address_byte_write2, 0
    xorlw    00h
    btfss    STATUS, 2
    return
    movf     next_address_byte_write3, 0
    xorlw    00h
    return

use_data:
; Data has been exchanged through SPI and now need to be read
; Exchanged data can be found in SSP1BUF
    bcf      task_flags2, 1
    movlb    04h
    ; Increment address_read
    movlw    01h
    addwf    next_address_byte_read1, 1
    movlw    00h
    ; If the addition leads to an overflow, the Carry bit is set to 1
    ; 'addwfc' add the carry to the result of the next addition
    addwfc   next_address_byte_read2, 1
    addwfc   next_address_byte_read3, 1
    btfsc    flash_status2, 2
    goto     bullshit_data
    
    ; TODO: Send data from SSP1BUF into Bluetooth but !!timing
    movf     SSP1BUF, 0

    ; Check if address_read = address write
    movf     next_address_byte_write1, 0
    xorwf    next_address_byte_read1, 0
    btfss    STATUS, 2
    return
    movf     next_address_byte_write2, 0
    xorwf    next_address_byte_read2, 0
    btfss    STATUS, 2
    return
    movf     next_address_byte_write3, 0
    xorwf    next_address_byte_read3, 0
    btfsc    STATUS, 2
    bcf      flash_status2, 3       ; Tell that there is nothing left to read
    return

bullshit_data:
    bcf      flash_status2, 2       ; Data is not bullshit anymore
    return