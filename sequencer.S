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

seq_data_base equ $4000
seq_tempo equ $4040	; The tempo value
seq_record equ $4042	; The address in the data of the track being recorded
seq_temp_tempo equ $4044 ; The temporary tempo storing the values as a tempo is being entered


; =========================
; Entry
; =========================
	org $8000

	;fcb 0x10
	;fcb 0x4a

	; Print banner
	jsr [pcrlf]

	lda #30
	jsr printspaces
	ldx #banner
	jsr [pdata]

	lda #20
	jsr printspaces
	ldx #controls
	jsr [pdata]

	; Set default tempo
	ldd #5
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
crashme
	ldx #cm_msg
	jsr [pdata]
crashmenow
	fcb $10
	fcb $45
cm_msg	fcc "\r\nThis crash is manually triggered\r\n"
	fcb $4

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
; Record subroutine
; =========================
rc_quit	rts
rc_clrv	lda #'.'
	jsr [outch]
	lda #0
	lbra rc_write
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
	subb #49  ; Convert '1'-'4' to 0-3
	lda #0x10
	mul
	ldx #seq_data_base
	abx
	stx seq_record

	; Clear the existing channel of data
	ldb #0x10
	clra
rc_clr	sta ,x+
	decb
	bne rc_clr

	; Print rfecord message
	ldx #record_msg
	jsr [pdata]
	lda #6
	jsr printspaces

rc_run	lda #'|'
	jsr [outch]
	
	clra
	clrb
	pshs a

rc_loop	lda #2
	jsr printspaces

	; Delay at start to see if press is entered
	jsr delay_tempo
	
	ldx seq_record
	puls b
	pshs b
	abx

	jsr [inchek]
	beq rc_no_input
	jsr [inch]
	cmpa #'s'
	beq rc_done
	cmpa #'.'
	lbeq rc_clrv
	cmpa #'1'
	blt rc_no_input
	cmpa #'8'
	bgt rc_no_input

	; Echo printed character
	tfr a,b
	jsr [outch]

	; Convert entered character to value
	subb #48
	lda #1
rc_conv	decb
	beq rc_write
	lsla
	bra rc_conv
	
rc_write ; Store entered character
	sta ,x

	puls a
	pshs a
	tfr a,b

	; Play current beat
	jsr play_beat
	bra rc_cont
rc_no_input
	puls a
	pshs a
	jsr play_beat

	; Print previous value on no input
	ldb ,x
	lda #1
rc_check_bit
	bitb #1
	bne rc_print_val
	lsrb
	inca
	cmpa #9
	bne rc_check_bit
	lda #-2  ; When 48 is added it will turn into a dot
rc_print_val
	adda #48
	jsr [outch]

	; Get data for checking end of line
	puls b
	pshs b
	
rc_cont	; Print the end mark if at end of line
	cmpb #15
	bne rc_next
	lda #'|'
	jsr [outch]

	; Increment beat counter
rc_next	puls a
	inca
	pshs a
	tfr a,b
	cmpa #16
	lblt rc_loop

	; If at end of line, start a new one
	jsr [pcrlf]
	lda #15
	jsr printspaces
	puls a
	lbra rc_run
	
rc_done	puls a

	ldx #seq_io_base
	clra
	clrb
	std ,x
	std 2,x

	rts

; =========================
; Playback subroutine
; =========================
playback
	; Print playback symbol
	ldx #playback_msg
	jsr [pdata]
	lda #7
	jsr printspaces

pb_run	lda #'|'
	jsr [outch]
	
	clra
	clrb
	pshs a

pb_loop	jsr play_beat

	; Print tick
	lda #2
	jsr printspaces
	lda #'.'
	jsr [outch]
	
	; Print the end mark if at end of line
	cmpb #15
	bne pb_del
	lda #'|'
	jsr [outch]

	; Delay
pb_del	jsr delay_tempo

	; Check for input after delay
pb_poll	jsr [inchek]
	beq pb_no_input
	jsr [inch]
	cmpa #'s'
	beq pb_done
	bra pb_poll
pb_no_input
	; Increment beat counter
	puls a
	inca
	pshs a
	tfr a,b
	cmpa #16
	blt pb_loop

	; If at end of line, start a new one
	jsr [pcrlf]
	lda #15
	jsr printspaces
	puls a
	bra pb_run
	
pb_done	puls a

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
	tfr x,y
	ldx #0
	ldb #1
d_ms	clra
d_cyc
	inca
	nop
	cmpa #74
	bne d_cyc

	abx
	cmpx seq_tempo
	bne d_ms
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
; Data Section
; =========================

banner	fcc "***Basic Sequencer***\r\n"
	fcb $04
controls
	fcc "P: Play - R: Record - T: Tempo - S: Stop"
	fcb $04
playback_msg
	fcc "Playback"
	fcb $04
record_msg
	fcc ":Rec"
	fcb $04
channel_prompt_msg
	fcc "Ch? "
	fcb $04
tempo_prompt_msg
	fcc "Enter Tempo (. to end, other to abort): "
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
