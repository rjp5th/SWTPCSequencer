; Basic sequencer program
; Can be jumped into at entry address
; Expects stack to be set up

; =========================
; Monitor Function Addresses
; =========================
inch	equ $F804
inche	equ $F806
inchek	equ $F808
outch	equ $F80A
pdata	equ $F80C
pcrlf	equ $F80E

; =========================
; Sequencer Addresses
; =========================
seq_io_base equ $E020

seq_data_base equ $4000		; The base of channel data (4 0x10-length byte arrays for each channel)
seq_tempo equ $4040		; The tempo value
seq_record equ $4042		; The address in the data of the track being recorded
seq_temp_tempo equ $4044	; The temporary tempo storing the values as a tempo is being entered
seq_record_ch equ $4046		; The channel to record sequences to
				; Note: this variable can take on special values to control the flow of the main playback logic
				; 0: Not recording, and doing standard playback
				; 0xFF: Playback stopped, should return to main menu
				; 0xFE: Playback paused, pending channel input from user to specify which channel to record to
seq_cur_beat equ $4047		; The current beat being played
seq_num_spaces equ $4048	; The number of spaces to print between markings, allows printing extra info in ISR without breaking spacing
seq_in_delay equ $4049		; If the sequence is currently in the delay loop, if not the isr should not do anything (can sometimes miss keypresses, but the alternative is a race condition)
seq_timer_fired equ $4050


; =========================
; Serial Addresses/Config
; =========================
serial_io_address equ $E004
serial_base_config equ $11
firq_jump_address equ $dfc6
timer_io_address equ $E008

; =========================
; Entry
; =========================
	org $F000

	;fcb 0x10
	;fcb 0x4a

	; Print banner
	jsr [pcrlf]

	lda #30
	jsr printspaces
	ldx #banner
	jsr [pdata]

	; Print Controls
	lda #13
	jsr printspaces
	ldx #controls
	jsr [pdata]
	jsr [pcrlf]
	lda #22
	jsr printspaces
	ldx #controls2
	jsr [pdata]

	; Set default tempo
	ldd #20
	std seq_tempo

redraw	jsr drawscreen
poll	jsr [inchek]
	bne poll

	jsr [inch]
	cmpa #'f'
	beq crashme
	cmpa #'p'
	beq do_playback
	cmpa #'r'
	beq do_record
	cmpa #'t'
	beq do_tempo
	cmpa #'c'
	beq do_clear
	cmpa #'d'
	beq do_realtime_playback
	cmpa #'m'
	beq do_manual_entry

	bra poll
do_playback
	jsr playback
	bra redraw
do_record
	jsr record
	bra redraw
do_tempo
	jsr tempo
	bra redraw
do_clear
	jsr clear
	bra redraw
do_realtime_playback
	jsr realtime_playback
	bra redraw
do_manual_entry
	jsr manual_entry
	bra redraw
crashme
	ldx #cm_msg
	jsr [pdata]
crashmenow
	fcb $10
	fcb $45
cm_msg	fcc "ManCrash"
	fcb $4

; =========================
; Manual Entry subroutine
; =========================
manual_entry
	; Prompt for channel
	ldx #channel_prompt_msg
	jsr [pdata]

	; Get channel to record
me_wfch	jsr [inchek]
	beq me_wfch
	jsr [inch]
	cmpa #'s'
	beq me_done
	cmpa #'1'
	blt me_wfch
	cmpa #'4'
	bgt me_wfch
	
	; Echo channel select
	tfr a,b
	jsr [outch]

	; Store channel
	subb #48
	stb seq_record_ch

	; Make channel range 0-3 to calculate record address (stored in x)
	decb
	lda #0x10
	mul
	ldx #seq_data_base
	abx

	pshs x
	; Print manual message
	ldx #manual_msg
	jsr [pdata]
	lda #5
	jsr printspaces
	puls x

	lda #'|'
	jsr [outch]

	clra
me_loop	pshs a
	jsr [inchek]
	bne me_loop
	jsr [inch]

	; Check for stop
	cmpa #'s'
	beq me_done

	; Do input processing
	ldb seq_record_ch
	jsr get_beat
	bne me_loop

	; Play Beat
	puls a
	pshs a
	jsr play_beat

	; ===Print tick===
	lda #2
	jsr printspaces
	
	ldb ,x+
	lda #1
me_check_bit
	bitb #1
	bne me_print_val
	lsrb
	inca
	cmpa #9
	bne me_check_bit
	lda #-2  ; When 48 is added it will turn into a dot
me_print_val
	adda #48
	jsr [outch]

	; Increment beat counter
	puls a
	inca
	cmpa #16
	blt me_loop

	; If at end of line, print line terminator and quit
	lda #'|'
	jsr [outch]
	jsr [pcrlf]

me_done	; Stop any notes being played
	ldx #seq_io_base
	clra
	clrb
	std ,x
	std 2,x

	rts


; =========================
; Realtime Playback subroutine
; =========================
realtime_playback
	; Clear any pending played notes (when called internally)
	ldx #seq_io_base
	clra
	clrb
	std ,x
	std 2,x

	ldx #realtime_ch_prompt_msg
	jsr [pdata]

rp_wfch	jsr [inchek]
	beq rp_wfch
	jsr [inch]
	cmpa #'1'
	blt rp_done
	cmpa #'4'
	bgt rp_done

	; Echo selected channel to console, and give prompt to play data
	pshs a
	jsr [outch]
	ldx #realtime_entry_msg
	jsr [pdata]
	puls b

	; Load the address to write channel data to
	subb #48
	stb seq_record_ch
	decb
	ldx #seq_io_base
	abx

	; Get input from user
rp_play	jsr [inchek]
	beq rp_play
	jsr [inch]
	cmpa #'c'
	beq realtime_playback

	; Do processing on input data
	ldb seq_record_ch
	jsr get_beat
	bne rp_done
	
	bra rp_play

rp_done	; Stop any pending playback
	ldx #seq_io_base
	clra
	clrb
	std ,x
	std 2,x

	rts

; =========================
; Tempo subroutine
; =========================
tempo
	ldx #tempo_prompt_msg
	jsr [pdata]

	; Clear temporary tempo
	ldd #0
	std seq_temp_tempo

t_waitc	jsr [inchek]
	beq t_waitc
	jsr [inche]
	cmpa #'.'
	beq t_write
	cmpa #'0'
	blt t_done
	cmpa #'9'
	bgt t_done

	; Convert char to number
	suba #48
	pshs a

	; Multiply existing temporary tempo by 10 and add entered number
	ldy #seq_temp_tempo
	ldb 1,y
	lda #10
	mul
	tfr d,x
	puls b
	abx
	stx ,y

	; If the number is too big to fit into b before multiplication, write it (gives range of 2559)
	cmpx #255
	bgt t_write

	bra t_waitc
t_write	ldd seq_temp_tempo
	std seq_tempo

	ldx #tempo_set_msg
	jsr [pdata]
t_done	jsr [pcrlf]
	rts

; =========================
; Clear subroutine
; =========================
clear
	; Prompt for channel
	ldx #clear_prompt_msg
	jsr [pdata]

	; Get channel to clear
cl_wfch	jsr [inchek]
	beq cl_wfch
	jsr [inch]
	cmpa #'1'
	blt cl_done
	cmpa #'4'
	bgt cl_done

	; Echo channel select
	tfr a,b
	jsr [outch]

	; Calculate address of sequence data
	subb #49
	lda #0x10
	mul
	ldx #seq_data_base
	abx
	
	; Clear the channel of existing data
	ldb #0x10
	clra
cl_loop	sta ,x+
	decb
	bne cl_loop
cl_done	rts

; =========================
; Record subroutine
; =========================
rc_quit	rts
record
	; Prompt for channel
	ldx #channel_prompt_msg
	jsr [pdata]

	; Get channel to record
rc_wfch	jsr [inchek]
	beq rc_wfch
	jsr [inch]
	cmpa #'s'
	beq rc_quit
	cmpa #'1'
	blt rc_wfch
	cmpa #'4'
	bgt rc_wfch
	
	; Echo channel select
	tfr a,b
	jsr [outch]
	
	; Store selected channel
	subb #48  ; Convert '1'-'4' to 1-4
	stb seq_record_ch

	; Make channel range 0-3 to calculate record address
	decb
	lda #0x10
	mul
	ldx #seq_data_base
	abx
	stx seq_record

	; Print record message
	ldx #record_msg
	jsr [pdata]
	lda #6
	jsr printspaces

	bra pb_common


; =========================
; Playback subroutine
; =========================
playback
	; Print playback symbol
	ldx #playback_msg
	jsr [pdata]
	lda #7
	jsr printspaces

	clr seq_record_ch 	; Set playback channel to 0 (No recording)
pb_common	
	; Enable interrupts for serial input, allowing processing during playback
	clr seq_in_delay 	; Make sure the interrupts don't mess with anything before it is in the delay
	ldx firq_jump_address
	pshs cc,x		; Save the cc register and the previous irq data, so if firqs are already enabled then they will remain enabled after the function exits
	ldx #playback_isr
	stx firq_jump_address	; Set the new irq function
	lda #0x80		; Enable serial irqs
	jsr serial_set_interrupt
	lda #1			; Enable timer irqs
	sta timer_io_address
	andcc #0xBF		; Enable FIRQ
	clr seq_timer_fired		; Clear pending timer interrupts

	; Set the default number of spaces to print between marks
	lda #2
	sta seq_num_spaces

pb_run	lda #'|'
	jsr [outch]
	
	clr seq_cur_beat   	; Set the currently played beat to 0
	
pb_loop	
	; Delay
	inc seq_in_delay	; Note this is under the assumption that pb_loop is always jumped to with seq_in_delay cleared
	jsr delay_tempo

	; Check if input is pending for changing record channel
pb_wait	lda seq_record_ch
	cmpa #0xFE
	beq pb_wait
	
	clr seq_in_delay

	; Check if during delay an interrupt fired which stopped playback
	lda seq_record_ch
	cmpa #0xFF
	beq pb_done

	; Play Beat
	lda seq_cur_beat
	jsr play_beat

	; ===Print tick===

	; Print number of spaces required, then reset the value
	lda seq_num_spaces
	jsr printspaces
	lda #2
	sta seq_num_spaces
	
	; Tick will be different for playback vs recording
	lda seq_record_ch
	bne pb_rec
	
	; Character to display during playback
	lda #'.'
	bra pb_drawch
	
pb_rec	; This code will run when it is recording
	ldx seq_record
	lda seq_cur_beat
	ldb a,x
	
	lda #1
pb_check_bit
	bitb #1
	bne pb_print_val
	lsrb
	inca
	cmpa #9
	bne pb_check_bit
	lda #-2  ; When 48 is added it will turn into a dot
pb_print_val
	adda #48
pb_drawch
	jsr [outch]

	; Increment beat counter
	lda seq_cur_beat
	inca
	sta seq_cur_beat
	cmpa #16
	blt pb_loop

	; If at end of line, start a new one
	lda #'|'
	jsr [outch]
	jsr [pcrlf]
	lda #15
	jsr printspaces
	bra pb_run

pb_done	; Stop serial interrupts
	puls cc,x
	stx firq_jump_address
	clra
	jsr serial_set_interrupt
	clr timer_io_address

	; Stop any notes being played
	ldx #seq_io_base
	clra
	clrb
	std ,x
	std 2,x

	rts


; =========================
; Draw Screen subroutine
; =========================
; Draws the screen displaying the sequence
drawscreen
	jsr [pcrlf]
	clra
	pshs a
	
ds_drawrow
	; Print out the pre-padding
	lda #10	; Pre-padding
	jsr printspaces

	; Print row title
	puls b
	pshs b
	lslb
	ldx #header_table
	abx
	ldx ,x
	jsr [pdata]

	; Print space
	lda #32
	jsr [outch]

	; Print table right border
	ldb #0
ds_draw_border
	puls a
	pshs a
	cmpa #0
	beq ds_fr_c
	lda #0x1D  ; If A is not the first row, set to '|' (0x7C), else set to 0x5C
ds_fr_c	adda #0x5F
	jsr [outch]
	cmpb #1
	lbeq ds_loop

	; Print contents of table
	puls a
	pshs a
	cmpa #0
	beq ds_top_row
	cmpa #1
	beq ds_beats_row
	cmpa #2
	beq ds_mid_row
	cmpa #7
	beq ds_mid_row

	; Else channel row
	; Load base address of sequence
	puls a
	pshs a
	suba #3
	ldb #0x10
	mul
	ldx #seq_data_base
	abx
	
	clra
	pshs a
ds_draw_channel_beat
	lda #2
	jsr printspaces
	ldb ,x+
	lda #1

ds_channel_check_bit
	bitb #1
	bne ds_print_channel_val
	lsrb
	inca
	cmpa #9
	bne ds_channel_check_bit
	lda #-16  ; When 48 is added it will turn into a space

ds_print_channel_val
	adda #48
	jsr [outch]

	puls a
	inca
	pshs a
	cmpa #16

	bne ds_draw_channel_beat
	puls a

	bra ds_border_close


ds_mid_row
	lda #'-'
	bra ds_draw_row
ds_top_row
	lda #'_'
ds_draw_row
	pshs a
	ldb #0x30	; Row Width: 48
ds_dr_l	puls a		; Print variable on stack b times
	pshs a
	jsr [outch]
	decb
	bne ds_dr_l
	puls a
	bra ds_border_close

ds_beats_row
	ldb #1

ds_print_beat
	; Print space
	lda #32
	jsr [outch]

	; Print tens digit, or space
	lda #32
	cmpb #10
	blt ds_beat_print_tens
	lda #'1'
ds_beat_print_tens
	jsr [outch]

	; Print ones digit
	tfr b,a
	cmpb #10
	blt ds_beat_skip_subtract
	suba #10
ds_beat_skip_subtract
	adda #48
	jsr [outch]

	incb
	cmpb #16
	ble ds_print_beat

	bra ds_border_close


	; Print table border
ds_border_close
	ldb #1
	lbra ds_draw_border
ds_loop
	jsr [pcrlf]
	puls a
	inca

	cmpa #8
	beq ds_done
	
	pshs a
	lbra ds_drawrow

ds_done	rts

; =========================
; Print Spaces Subroutine
; =========================
; Prints number of spaces in A register
printspaces
	pshs b
	tfr a,b
ps_loop	tstb
	beq ps_done
	pshs b
	lda #32  ; Load with space
	jsr [outch]
	puls b
	decb
	bra ps_loop
ps_done	puls b
	rts

; =========================
; Delay Subroutine
; =========================
delay_tempo
	pshs x
	ldx #0
	ldb #1
	tst seq_timer_fired
	bne d_nowait
d_wait	tst seq_timer_fired
	beq d_wait
d_nowait
	clr seq_timer_fired
	abx
	cmpx seq_tempo
	bne d_wait

	puls x
	rts

; =========================
; Play Beat Subroutine
; =========================
; The a register should contain the offset
; The b,x register is saved
play_beat
	pshs x,b

	; Setup initial address
	ldx #seq_data_base
	tfr a,b
	abx
	ldy #seq_io_base

	; Set channel count to transfer
	ldb #4
	
	; Write each channel's value for the given beat
p_b_wch	pshs b
	lda ,x
	sta ,y+
	ldb #16
	abx
	puls b
	decb
	bne p_b_wch

	puls x,b
	rts

; =========================
; Get Beat Subroutine
; =========================
; a is the beat to get
; b is the channel to record to (used in decoding logic)
; x is the address to store data in
; Returns: cc.z = 0 on failure decoding, cc.z = 1 on successful decoding
get_beat
	cmpa #'.'
	beq gb_clrv
	cmpa #32
	beq gb_done
	cmpa #'1'
	blt gb_done
	cmpa #'8'
	bgt gb_done

	; a is now loaded with a character between 1 and 8
	; Convert entered character to value
	suba #48
	ldb #1
gb_conv deca
	beq gb_write
	lslb
	bra gb_conv
gb_clrv ; Create a value to clear when writing to memory
	clrb
gb_write
	; Write the calculated value to the sequencer memory
	stb ,x

	; Dirty hack to make it return success on either space or successful decoding
	lda #32
gb_done	cmpa #32
	rts

; =========================
; Serial Interrupt Routines
; =========================
; a register: 0x80 for enable interrupts, 0 for disable
serial_set_interrupt
	adda #serial_base_config
	sta serial_io_address
	rts

playback_isr
	pshs a,b

	jsr [inchek]
	bne isr_key

	tst timer_io_address+1
	bne isr_timer

	lbra isr_end

isr_timer
	clr timer_io_address+1
	lda #1
	sta seq_timer_fired
	lbra isr_end

isr_key	jsr [inch]

	; Check if it is okay to do handling of incoming serial data
	ldb seq_in_delay
	beq isr_end

	; Process universal keypresses
	cmpa #'s'
	beq isr_stop_playback
	cmpa #'p'
	beq isr_do_playback
	cmpa #'r'
	beq isr_do_record

	; Process keypresses depending on recording/playback/expecting channel data
	ldb seq_record_ch
	beq isr_end	; Nothing special to do during playback, only universal keypresses
	cmpb #0xFF
	beq isr_end	; Don't do anything special if it is stopping
	cmpb #0xFE
	beq isr_sel_ch	; Do channel selection if it is waiting for a channel
	
	; Everything else is recording and b now contains the channel to record to
	pshs x,b
	ldb seq_cur_beat
	ldx seq_record
	abx
	puls b
	jsr get_beat
	puls x
	
	bra isr_end

isr_sel_ch
	cmpa #'1'
	blt isr_end
	cmpa #'4'
	bgt isr_end
	
	; Store selected channel
	suba #48  ; Convert '1'-'4' to 1-4
	sta seq_record_ch

	; Make channel range 0-3 to calculate record address
	pshs x
	deca
	ldb #0x10
	mul
	ldx #seq_data_base
	abx
	stx seq_record
	puls x

	bra isr_end

isr_stop_playback
	lda #0xFF
	sta seq_record_ch
	bra isr_end

isr_do_record
	; Print command to display
	lda #'R'
	jsr [outch]
	dec seq_num_spaces

	; Set to wait for pending press to switch recording channel
	lda #0xFE
	sta seq_record_ch
	bra isr_end

isr_do_playback
	; Print command to display
	lda #'P'
	jsr [outch]
	dec seq_num_spaces

	; Set to playback
	clr seq_record_ch

isr_end	puls a,b
	rti

; =========================
; Data Section
; =========================
banner	fcc "***Basic Sequencer***\r\n"
	fcb $04
controls
	fcc "P: Play - R: Record - S: Stop - C: Clear Ch - T: Tempo"
	fcb $04
controls2
	fcc "D: Direct Playback - M: Manual Entry"
	fcb $04
playback_msg
	fcc "Playback"
	fcb $04
record_msg
	fcc ":Rec"
	fcb $04
manual_msg
	fcc ":Manu"
	fcb $04
channel_prompt_msg
	fcc "Ch? "
	fcb $04
tempo_prompt_msg
	fcc "Enter Tempo (. to end, other to abort): "
	fcb $04
clear_prompt_msg
	fcc "Enter Channel to Clear (other to abort): "
	fcb $04
realtime_ch_prompt_msg
	fcc "Enter Channel to Play (other to abort): "
	fcb $04
realtime_entry_msg
	fcc "\n\rPress Keys to Play... (c to change channel, other to abort)\n\r"
	fcb $04
tempo_set_msg
	fcc " - Tempo Set"
	fcb $04
header_table
	fdb header_blank
	fdb header_beat
	fdb header_blank
	fdb header_ch1
	fdb header_ch2
	fdb header_ch3
	fdb header_ch4
	fdb header_blank

header_blank
	fcc "    "
	fcb $04

header_beat
	fcc "Beat"
	fcb $04

header_ch1
	fcc "Ch 1"
	fcb $04

header_ch2
	fcc "Ch 2"
	fcb $04

header_ch3
	fcc "Ch 3"
	fcb $04

header_ch4
	fcc "Ch 4"
	fcb $04
