; TrafficLightGroupProject.asm
;
; Created: 11/18/2025 12:04:17 PM
; Authors : Timofey Yudintsev, Evan Goudy, Katharine Ringo
; Modified: 11/24/2025
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

; Timer1 for 100ms tick (16MHz, prescaler 1024)
.equ OCR1A_100MS = 15624

; Timings (in 100ms ticks)
.equ GREEN_TICKS = 30      ; 3.0s
.equ YELLOW_TICKS = 20     ; 2.0s
.equ RED_TICKS = 30        ; 3.0s both-red safety
.equ WALK_TICKS = 40       ; 4.0s walk interval

.def crossNFlag = r21
.def crossWFlag = r22

; additional working registers
.def tmp = r16
.def tmp2 = r17
.def tmp3 = r18
.def state = r19
.def stcnt = r20        ; counts 100ms ticks for current state
.def tickFlag = r23     ; set by Timer ISR
.def walkcnt = r24
.def scratch = r25

; state encodings
.equ STATE_NORTH_GREEN = 0
.equ STATE_NORTH_YELLOW = 1
.equ STATE_BOTH_RED_NS = 2
.equ STATE_WEST_GREEN = 3
.equ STATE_WEST_YELLOW = 4
.equ STATE_BOTH_RED_EW = 5

; ---------------------- VECTOR TABLE ---------------------------------
.org 0x000
          jmp       main
.org INT0addr                           ; External Interrupt Request 0 (Port-D Pin-2)
          jmp       btn_cross_w_isr
.org INT1addr                           ; External Interrupt Request 1 (Port-D Pin-3)
          jmp       btn_cross_n_isr
.org OC1Aaddr                            ; Timer/Counter1 Compare Match A
          jmp       timer1_cmpa_isr
.org INT_VECTORS_SIZE                   ; end vector table

; one-time configuration
; ----------------------------------------------------------

main:

          ; initialize stack pointer
          ldi       tmp, high(RAMEND)
          out       SPH, tmp
          ldi       tmp, low(RAMEND)
          out       SPL, tmp

          ; clear flags and counters
          clr       crossNFlag
          clr       crossWFlag
          clr       state
          clr       stcnt
          clr       tickFlag
          clr       walkcnt
          clr       scratch

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

          ; default LED states: both don't-walk (red pedestrian) on
          ldi       tmp, (1<<CROSS_RED_N_PIN)
          out       PORTB, tmp
          ldi       tmp, (1<<CROSS_RED_W_PIN)
          out       PORTC, tmp

          ; setup Cross west button (PD2 -> INT0)
          cbi       DDRD, CROSS_W_BTN              ; input mode
          sbi       PORTD, CROSS_W_BTN             ; pull-up

          ; setup Cross north button (PD3 -> INT1)
          cbi       DDRD, CROSS_N_BTN              ; input mode
          sbi       PORTD, CROSS_N_BTN             ; pull-up

          ; Configure External Interrupts: falling edge (button press to GND)
          ; ISC01 ISC00 = 1 0 -> falling edge for INT0
          ; ISC11 ISC10 = 1 0 -> falling edge for INT1
          ldi       tmp, (1<<ISC01)
          out       EICRA, tmp
          ldi       tmp, (1<<ISC11)
          lds       tmp2, EICRA
          or        tmp2, tmp
          sts       EICRA, tmp2

          ; Enable INT0 and INT1
          ldi       tmp, (1<<INT0)|(1<<INT1)
          out       EIMSK, tmp

          ; ---------- Configure Timer1 (CTC) for 100 ms tick ----------
          ; load OCR1A
          ldi       tmp, high(OCR1A_100MS)
          sts       OCR1AH, tmp
          ldi       tmp, low(OCR1A_100MS)
          sts       OCR1AL, tmp

          ; Clear TCCR1A
          ldi       tmp, 0x00
          out       TCCR1A, tmp

          ; Set WGM12 (CTC) and prescaler 1024 (CS12 and CS10)
          ldi       tmp, (1<<WGM12)|(1<<CS12)|(1<<CS10)
          out       TCCR1B, tmp

          ; Enable Timer1 Compare Match A interrupt
          ldi       tmp, (1<<OCIE1A)
          out       TIMSK1, tmp

          ; Clear pending Timer1 flags
          ldi       tmp, (1<<OCF1A)
          out       TIFR1, tmp

          sei                           ; turn global interrupts on

; start with NORTH green
          rcall     set_north_green
          ldi       state, STATE_NORTH_GREEN

main_loop:

          ; Non-blocking check: if tickFlag set, consume it and advance timers
          tst       tickFlag
          breq      skip_tick
          clr       tickFlag
          inc       stcnt

          ; run state machine only on tick increments
          ; STATE: NORTH GREEN
          cpi       state, STATE_NORTH_GREEN
          breq      handle_north_green
          ; NORTH YELLOW
          cpi       state, STATE_NORTH_YELLOW
          breq      handle_north_yellow
          ; BOTH RED after NORTH
          cpi       state, STATE_BOTH_RED_NS
          breq      handle_both_red_ns
          ; WEST GREEN
          cpi       state, STATE_WEST_GREEN
          breq      handle_west_green
          ; WEST YELLOW
          cpi       state, STATE_WEST_YELLOW
          breq      handle_west_yellow
          ; BOTH RED after WEST
          cpi       state, STATE_BOTH_RED_EW
          breq      handle_both_red_ew

          rjmp      main_loop

skip_tick:
          rjmp      main_loop

; ---------- STATE HANDLERS ----------
handle_north_green:
          ldi       tmp, GREEN_TICKS
          cp        stcnt, tmp
          brlo      main_loop
          ; transition -> north yellow
          rcall     set_north_yellow
          ldi       state, STATE_NORTH_YELLOW
          rjmp      main_loop

handle_north_yellow:
          ldi       tmp, YELLOW_TICKS
          cp        stcnt, tmp
          brlo      main_loop
          ; transition -> both red (north finished)
          rcall     set_both_red
          ldi       state, STATE_BOTH_RED_NS
          rjmp      main_loop

handle_both_red_ns:
          ldi       tmp, RED_TICKS
          cp        stcnt, tmp
          brlo      main_loop
          ; if cross north requested -> do walk now (blocking for walk duration)
          tst       crossNFlag
          breq      ns_no_walk
          rcall     do_walk_north
          clr       crossNFlag
ns_no_walk:
          ; then go to west green
          rcall     set_west_green
          ldi       state, STATE_WEST_GREEN
          rjmp      main_loop

handle_west_green:
          ldi       tmp, GREEN_TICKS
          cp        stcnt, tmp
          brlo      main_loop
          ; transition -> west yellow
          rcall     set_west_yellow
          ldi       state, STATE_WEST_YELLOW
          rjmp      main_loop

handle_west_yellow:
          ldi       tmp, YELLOW_TICKS
          cp        stcnt, tmp
          brlo      main_loop
          ; transition -> both red (west finished)
          rcall     set_both_red
          ldi       state, STATE_BOTH_RED_EW
          rjmp      main_loop

handle_both_red_ew:
          ldi       tmp, RED_TICKS
          cp        stcnt, tmp
          brlo      main_loop
          ; if cross west requested -> do walk now
          tst       crossWFlag
          breq      ew_no_walk
          rcall     do_walk_west
          clr       crossWFlag
ew_no_walk:
          ; then go back to north green
          rcall     set_north_green
          ldi       state, STATE_NORTH_GREEN
          rjmp      main_loop

; -------------------- OUTPUT SET ROUTINES -----------------------------
; set_north_green: North green ON, West red ON, ped don't-walk on
set_north_green:
          ; PORTB: NS_GREEN and CROSS_RED_N on, others off
          ldi       tmp, (1<<GREEN_N_PIN)|(1<<CROSS_RED_N_PIN)
          out       PORTB, tmp
          ; PORTC: ensure WEST is red and CROSS_RED_W on
          lds       tmp2, PORTC
          ; clear west green/yellow/white bits
          andi      tmp2, ~((1<<GREEN_W_PIN)|(1<<YELLOW_W_PIN)|(1<<CROSS_WHITE_W_PIN))
          ori       tmp2, (1<<RED_W_PIN)|(1<<CROSS_RED_W_PIN)
          out       PORTC, tmp2
          clr       stcnt
          ret

set_north_yellow:
          ; PORTB: NS_YELLOW and CROSS_RED_N on
          ldi       tmp, (1<<YELLOW_N_PIN)|(1<<CROSS_RED_N_PIN)
          out       PORTB, tmp
          ; PORTC: maintain west red/don't-walk
          lds       tmp2, PORTC
          andi      tmp2, ~((1<<GREEN_W_PIN)|(1<<YELLOW_W_PIN)|(1<<CROSS_WHITE_W_PIN))
          ori       tmp2, (1<<RED_W_PIN)|(1<<CROSS_RED_W_PIN)
          out       PORTC, tmp2
          clr       stcnt
          ret

set_both_red:
          ; PORTB: NS_RED and CROSS_RED_N on
          ldi       tmp, (1<<RED_N_PIN)|(1<<CROSS_RED_N_PIN)
          out       PORTB, tmp
          ; PORTC: WEST_RED and CROSS_RED_W on (clear west walk)
          lds       tmp2, PORTC
          andi      tmp2, ~((1<<GREEN_W_PIN)|(1<<YELLOW_W_PIN)|(1<<CROSS_WHITE_W_PIN))
          ori       tmp2, (1<<RED_W_PIN)|(1<<CROSS_RED_W_PIN)
          out       PORTC, tmp2
          clr       stcnt
          ret

set_west_green:
          ; PORTC: WEST_GREEN and CROSS_RED_W on
          lds       tmp2, PORTC
          andi      tmp2, ~((1<<YELLOW_W_PIN)|(1<<RED_W_PIN)|(1<<CROSS_WHITE_W_PIN))
          ori       tmp2, (1<<GREEN_W_PIN)|(1<<CROSS_RED_W_PIN)
          out       PORTC, tmp2
          ; PORTB: set NS_RED and CROSS_RED_N
          lds       tmp, PORTB
          andi      tmp, ~((1<<GREEN_N_PIN)|(1<<YELLOW_N_PIN)|(1<<CROSS_WHITE_N_PIN))
          ori      tmp, (1<<RED_N_PIN)|(1<<CROSS_RED_N_PIN)
          out      PORTB, tmp
          clr       stcnt
          ret

set_west_yellow:
          ; PORTC: WEST_YELLOW and CROSS_RED_W
          lds       tmp2, PORTC
          andi      tmp2, ~((1<<GREEN_W_PIN)|(1<<RED_W_PIN)|(1<<CROSS_WHITE_W_PIN))
          ori       tmp2, (1<<YELLOW_W_PIN)|(1<<CROSS_RED_W_PIN)
          out       PORTC, tmp2
          ; PORTB: ensure north red/don't-walk
          lds       tmp, PORTB
          andi      tmp, ~((1<<GREEN_N_PIN)|(1<<YELLOW_N_PIN)|(1<<CROSS_WHITE_N_PIN))
          ori      tmp, (1<<RED_N_PIN)|(1<<CROSS_RED_N_PIN)
          out      PORTB, tmp
          clr       stcnt
          ret

; -------------------- WALK ROUTINES (blocking for walk duration) -----
; do_walk_north: perform WALK_TICKS ticks, blink last half
do_walk_north:
          ; Turn on cross-white (walk) and clear cross-red
          lds       tmp, PORTB
          andi      tmp, ~(1<<CROSS_RED_N_PIN)
          out       PORTB, tmp
          sbi       PORTB, CROSS_WHITE_N_PIN

          ldi       walkcnt, WALK_TICKS

do_walk_north_wait:
          ; non-blocking wait for tick -> poll tickFlag
          tst       tickFlag
          breq      do_walk_north_wait
          clr       tickFlag
          dec       walkcnt

          ; if walkcnt <= WALK_TICKS/2 -> blink by toggling
          ldi       tmp, (WALK_TICKS/2)
          cp        walkcnt, tmp
          brsh      nw_steady_on
          ; blink: toggle CROSS_WHITE_N_PIN
          lds       tmp2, PORTB
          eor       tmp2, (1<<CROSS_WHITE_N_PIN)
          out       PORTB, tmp2
          rjmp      nw_check_done

nw_steady_on:
          sbi       PORTB, CROSS_WHITE_N_PIN

nw_check_done:
          tst       walkcnt
          brne      do_walk_north_wait

          ; done: turn off white, set red
          lds       tmp, PORTB
          andi      tmp, ~(1<<CROSS_WHITE_N_PIN)
          ori       tmp, (1<<CROSS_RED_N_PIN)
          out       PORTB, tmp
          ret

; do_walk_west: same as north but for PORTC
do_walk_west:
          ; Turn on cross-white (walk) and clear cross-red
          lds       tmp, PORTC
          andi      tmp, ~(1<<CROSS_RED_W_PIN)
          out       PORTC, tmp
          sbi       PORTC, CROSS_WHITE_W_PIN

          ldi       walkcnt, WALK_TICKS

do_walk_west_wait:
          tst       tickFlag
          breq      do_walk_west_wait
          clr       tickFlag
          dec       walkcnt

          ldi       tmp, (WALK_TICKS/2)
          cp        walkcnt, tmp
          brsh      ww_steady_on
          ; blink toggle
          lds       tmp2, PORTC
          eor       tmp2, (1<<CROSS_WHITE_W_PIN)
          out       PORTC, tmp2
          rjmp      ww_check_done

ww_steady_on:
          sbi       PORTC, CROSS_WHITE_W_PIN

ww_check_done:
          tst       walkcnt
          brne      do_walk_west_wait

          ; done: turn off white, set red
          lds       tmp, PORTC
          andi      tmp, ~(1<<CROSS_WHITE_W_PIN)
          ori       tmp, (1<<CROSS_RED_W_PIN)
          out       PORTC, tmp
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
          sts       TCCR1B, r20                   ; Clock Prescaler — setting the clock starts the timer

          ; Monitor OCF1A flag in TIFR1
Monitor_OCF1A:
          sbis      TIFR1, OCF1A
          rjmp      Monitor_OCF1A

          ; Stop timer by clearing clock (clear TCCR1B)
          clr       r20
          sts       TCCR1B, r20

          ; Clear OCF1A flag — write a 1 to OCF1A bit in TIFR1
          ldi       r20, (1 << OCF1A)
          out       TIFR1, r20

          ; Repeat steps again for multiple timers
           
          ret                           ; delay

; handle WEST cross button press (INT0)
; ----------------------------------------------------------
btn_cross_w_isr:
          ldi       crossWFlag, 1
          reti

; handle NORTH cross button press (INT1)
; ----------------------------------------------------------
btn_cross_n_isr:
          ldi       crossNFlag, 1
          reti

; Timer1 Compare Match A ISR (100 ms tick)
; ----------------------------------------------------------
timer1_cmpa_isr:
          ldi       tickFlag, 1
          reti

end_main:
          rjmp main_loop
