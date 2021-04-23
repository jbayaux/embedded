#include     "config.inc"

init_adc:
    banksel  ADCON1
    movlw    01000000B              ; Frequency = Fosc/4, result as sign-magnitude
    movwf    ADCON1
    movlw    00001111B              ; Negative ref set to VSS
    movwf    ADCON2
    return

