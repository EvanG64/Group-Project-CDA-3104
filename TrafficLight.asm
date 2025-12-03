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
.equ DELAY_MS = 90000 * (16 / 256.0) - 1

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

          ldi       crossWFlag, 0
          ldi       crossNFlag, 0

main_loop:

; ----------------------------------------------------------
          ldi       r16, 25
          call      n_red_w_red
          call      n_cross_red
          call      w_cross_red
          call      delay_lp
; ----------------------------------------------------------
          ldi       r16, 75
          call      n_green_w_red
          tst       crossWFlag
          breq      no_w_cross_white_1
          call      w_cross_white
no_w_cross_white_1:
          call      delay_lp
; ----------------------------------------------------------
          ldi       r16, 25
          call      n_yellow_w_red
          tst       crossWFlag
          breq      no_w_cross_white_2
          call      w_cross_white
no_w_cross_white_2:
          call      delay_lp
          ldi       crossWFlag, 0
; ----------------------------------------------------------
          ldi       r16, 25
          call      n_red_w_red
          call      n_cross_red
          call      w_cross_red
          call      delay_lp
; ----------------------------------------------------------
          ldi       r16, 75
          call      n_red_w_green
          tst       crossNFlag
          breq      no_n_cross_white_1
          call      n_cross_white
no_n_cross_white_1:
          call      delay_lp
; ----------------------------------------------------------
          ldi       r16, 25
          call      n_red_w_yellow
          tst       crossNFlag
          breq      no_n_cross_white_2
          call      n_cross_white
no_n_cross_white_2:
          call      delay_lp
          ldi       crossNFlag, 0
; ----------------------------------------------------------

         

end_main:
          rjmp main_loop




; ----------------------------------------------------------

delay_lp:                               ; do {
          

          call      delay

          cpi       r16, 10
          brge      no_blink_white

          sbic      WEST, YELLOW_W_PIN
          call      n_cross_white_blink
          sbic      NORTH, YELLOW_N_PIN
          call      w_cross_white_blink





no_blink_white:

          dec       r16                 ;   --r16
          brne      delay_lp            ; } while (r16 > 0);

          
          ret      




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







n_cross_red:
          sbi       NORTH, CROSS_RED_N_PIN
          cbi       NORTH, CROSS_WHITE_N_PIN
          ret
n_cross_white:
          sbi       NORTH, CROSS_WHITE_N_PIN
          cbi       NORTH, CROSS_RED_N_PIN
          ret
n_cross_white_off:  
          cbi       NORTH, CROSS_WHITE_N_PIN
          ret


w_cross_red:
          sbi       WEST, CROSS_RED_W_PIN
          cbi       WEST, CROSS_WHITE_W_PIN
          ret
w_cross_white:
          sbi       WEST, CROSS_WHITE_W_PIN
          cbi       WEST, CROSS_RED_W_PIN
          ret
w_cross_white_off:  
          cbi       WEST, CROSS_WHITE_W_PIN
          ret


n_cross_white_blink:
          sbic      NORTH, CROSS_WHITE_N_PIN
          rjmp      n_cross_white_blink_1
          tst       crossNFlag
          breq      n_cross_white_blink_end
          call      n_cross_white
          rjmp      n_cross_white_blink_end

n_cross_white_blink_1:
          tst       crossNFlag
          breq      n_cross_white_blink_end
          call      n_cross_white_off

n_cross_white_blink_end:
          ret



w_cross_white_blink:
          sbic      WEST, CROSS_WHITE_W_PIN
          rjmp      w_cross_white_blink_1
          tst       crossWFlag
          breq      w_cross_white_blink_end
          call      w_cross_white
          rjmp      w_cross_white_blink_end

w_cross_white_blink_1:
          tst       crossWFlag
          breq      w_cross_white_blink_end
          call      w_cross_white_off

w_cross_white_blink_end:
          ret





; ----------------------------------------------------------



n_green_w_red:
          sbi       NORTH, GREEN_N_PIN                   ; turn green north on
          sbi       WEST, RED_W_PIN                     ; turn red west on
          cbi       NORTH, RED_N_PIN                     ; turn red north off
          cbi       NORTH, YELLOW_N_PIN                  ; turn yellow north off
          cbi       WEST, YELLOW_W_PIN                  ; turn yellow west off
          cbi       WEST, GREEN_W_PIN                   ; turn green west off
          
          ret               ; return


n_red_w_green:
          sbi       NORTH, RED_N_PIN                     ; turn red north on
          sbi       WEST, GREEN_W_PIN                   ; turn green west on
          cbi       NORTH, YELLOW_N_PIN                  ; turn yellow north off
          cbi       NORTH, GREEN_N_PIN                   ; turn green north off
          cbi       WEST, RED_W_PIN                     ; turn red west off
          cbi       WEST, YELLOW_W_PIN                  ; turn yellow west off

          ret                     ;return


n_yellow_w_red:
          sbi       NORTH, YELLOW_N_PIN                  ; turn yellow north on
          sbi       WEST, RED_W_PIN                     ; turn red west on
          cbi       NORTH, RED_N_PIN                     ; turn red north off
          cbi       NORTH, GREEN_N_PIN                   ; turn green north off
          cbi       WEST, YELLOW_W_PIN                  ; turn yellow west off
          cbi       WEST, GREEN_W_PIN                   ; turn green west off

          ret      



n_red_w_yellow:
          sbi       NORTH, RED_N_PIN                     ; turn red north on
          sbi       WEST, YELLOW_W_PIN                  ; turn yellow west on
          cbi       NORTH, YELLOW_N_PIN                  ; turn yellow north off
          cbi       NORTH, GREEN_N_PIN                   ; turn green north off
          cbi       WEST, RED_W_PIN                     ; turn red west off
          cbi       WEST, GREEN_W_PIN                   ; turn green west off

          ret       

n_red_w_red:
          sbi       NORTH, RED_N_PIN                     ; turn red north on
          sbi       WEST, RED_W_PIN                     ; turn red west on
          cbi       NORTH, YELLOW_N_PIN                  ; turn yellow north off
          cbi       NORTH, GREEN_N_PIN                   ; turn green north off
          cbi       WEST, YELLOW_W_PIN                  ; turn yellow west off
          cbi       WEST, GREEN_W_PIN                   ; turn green west off

          ret       



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