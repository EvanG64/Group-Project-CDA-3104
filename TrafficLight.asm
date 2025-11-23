;
; TrafficLightGroupProject.asm
;
; Created: 11/18/2025 12:04:17 PM
; Authors : Timofey Yudintsev, Evan Goudy, Katharine Ringo
; Description: To make a 4-way intersection model,
; which can handle crosswalk input
; ----------------------------------------------------------
; declare constants and global variables
; ----------------------------------------------------------
               ; us  *  XTAL / scaler - 1
.equ DELAY_MS = 100000 * (16 / 256.0) - 1

.equ RED_N_PIN = PB4
.equ YELLOW_N_PIN = PB3
.equ GREEN_N_PIN = PB2
.equ CROSS_WHITE_N_PIN = PB1
.equ CROSS_RED_N_PIN = PB0

.equ NORTH = PORTB

.equ RED_W_PIN = PC1
.equ YELLOW_W_PIN = PC2
.equ GREEN_W_PIN = PC3
.equ CROSS_WHITE_W_PIN = PC4
.equ CROSS_RED_W_PIN = PC5

.equ WEST = PORTC

.equ CROSS_N_BTN = PD3
.equ CROSS_W_BTN = PD2

.def crossNFlag = r21
.def crossWFlag = r22


.org 0x000
          jmp       main
.org INT0addr                           ; External Interrupt Request 0 (Port-D Pin-2)
          jmp       btn_cross_w_isr
.org INT1addr                           ; External Interrupt Request 1 (Port-D Pin-3)
          jmp       btn_cross_n_isr
.org INT_VECTORS_SIZE                   ; end vector table


; one-time configuration
; ----------------------------------------------------------

main:

          ; initialize GPIO
          sbi       DDRB, RED_N_PIN               ; LED output mode
          sbi       DDRB, YELLOW_N_PIN            ; LED output mode
          sbi       DDRB, GREEN_N_PIN             ; LED output mode
          sbi       DDRB, CROSS_WHITE_N_PIN       ; LED output mode
          sbi       DDRB, CROSS_RED_N_PIN         ; LED output mode

          sbi       DDRC, RED_W_PIN               ; LED output mode
          sbi       DDRC, YELLOW_W_PIN            ; LED output mode
          sbi       DDRC, GREEN_W_PIN             ; LED output mode
          sbi       DDRC, CROSS_WHITE_W_PIN       ; LED output mode
          sbi       DDRC, CROSS_RED_W_PIN         ; LED output mode



          ; setup Cross west button
          cbi       DDRD, CROSS_W_BTN              ; input mode
          sbi       PORTD, CROSS_W_BTN             ; pull-up

          sbi       EIMSK, INT0         ; External Interrupt 0 on pin D2
          ldi       r16, (0b011 << ISC00)
          lds       r4, EICRA           ; read prior state
          or        r16, r4             ; update with prior
          sts       EICRA, r16          ; rising edge trigger


          ; setup Cross north button
          cbi       DDRD, CROSS_N_BTN              ; input mode
          sbi       PORTD, CROSS_N_BTN             ; pull-up

          sbi       EIMSK, INT1         ; External Interrupt 1 on pin D3
          ldi       r16, (0b010 << ISC10)
          lds       r4, EICRA           ; read prior state
          or        r16, r4             ; update with prior
          sts       EICRA, r16          ; rising edge trigger


          sei                           ; turn global interrupts on

main_loop:







end_main:
          rjmp main_loop









; ----------------------------------------------------------
delay:
          ; Load TCNT1H:TCNT1L with initial count
          clr       r20
          sts       TCNT1H, r20
          sts       TCNT1L, r20

          ; Load OCR1AH:OCR1AL with stop count
          ldi       r20, high(DELAY_MS)
          sts       OCR1AH, r20
          ldi       r20, low(DELAY_MS)
          sts       OCR1AL, r20

          ; Load TCCR1A & TCCR1B
          clr       r20
          sts       TCCR1A, r20                   ; CTC mode
          ldi       r20, (1 << WGM12) | (1 << CS12) 
          sts       TCCR1B, r20                   ; Clock Prescaler – setting the clock starts the timer

          ; Monitor OCF1A flag in TIFR1
Monitor_OCF1A:
          sbis      TIFR1, OCF1A
          rjmp      Monitor_OCF1A

          ; Stop timer by clearing clock (clear TCCR1B)
          clr       r20
          sts       TCCR1B, r20

          ; Clear OCF1A flag – write a 1 to OCF1A bit in TIFR1
          ldi       r20, (1 << OCF1A)
          out       TIFR1, r20


          ; Repeat steps again for multiple timers
           
          ret                           ; delay



; handle decrement button press
; ----------------------------------------------------------
btn_cross_w_isr:
          ldi       crossWFlag, 1                   ; decFlag = true

          reti                          ; btn_dec_isr

; handle increment button press
; ----------------------------------------------------------
btn_cross_n_isr:
          ldi       crossNFlag, 1                   ; incFlag = true

          reti                          ; btn_inc_isr





; ----------------------------------------------------------
my new stuff


n_green_w_red:
          sbi       NORTH, GREEN_N_PIN                   ; turn green north on
          sbi       WEST, RED_W_PIN                     ; turn red west on
          cbi       NORTH, RED_N_PIN                     ; turn red north off
          cbi       NORTH, YELLOW_N_PIN                  ; turn yellow north off
          cbi       WEST, YELLOW_W_PIN                  ; turn yellow west off
          cbi       WEST, GREEN_W_PIN                   ; turn green west off
          
          ret                                      ; return to n_green_w_red


n_red_w_green:
          sbi       NORHT, RED_N_PIN                     ; turn red north on
          sbi       WEST, GREEN_W_PIN                   ; turn green west on
          cbi       NORTH, YELLOW_N_PIN                  ; turn yellow norht off
          cbi       NORHT, GREEN_N_PIN                   ; turn green north off
          cbi       WEST, RED_W_PIN                     ;turn red west off
          cbi       WEST, YELLOW_W_PIN                  ; turn yellow west off

          ret                                     ;return n_red_w_green


n_yellow_w_red:
          sbi       NORTH, YELLOW_N_PIN                  ; turn yellow north on
          sbi       WEST, RED_W_PIN                     ; turn red west on
          cbi       NORTH, RED_N_PIN                     ; turn red north off
          cbi       NORTH, GREEN_N_PIN                   ; turn green north off
          cbi       WEST, YELLOW_W_PIN                  ; turn yellow west off
          cbi       WEST, GREEN_W_PIN                   ; turn green west off

          ret                                     ; return to n_yellow_w_red



n_red_w_yellow:
          sbi       NORTH, RED_N_PIN                     ; turn red north on
          sbi       WEST, YELLOW_W_PIN                  ; turn yellow west on
          cbi       NORTH, YELLOW_N_PIN                  ; turn yellow north off
          cbi       NORTH, GREEN_N_PIN                   ; turn green north off
          cbi       WEST, RED_W_PIN                     ; turn red west off
          cbi       WEST, GREEN_W_PIN                   ; turn green west off

          ret                                     ; return to n_red_w_yellow

n_red_w_red:
          sbi       NORTH, RED_N_PIN                     ; turn red north on
          sbi       WEST, RED_W_PIN                     ; turn red west on
          cbi       NORTH, YELLOW_N_PIN                  ; turn yellow north off
          cbi       NORTH, GREEN_N_PIN                   ; turn green north off
          cbi       WEST, YELLOW_W_PIN                  ; turn yellow west off
          cbi       WEST, GREEN_W_PIN                   ; turn green west off

          ret                                     ; return to n_red_w_red

