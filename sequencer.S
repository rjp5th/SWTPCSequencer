; SWTPC 6809 sequencer program
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
; Key Bindings
; =========================
playback_key	equ 'M'
record_key	equ 'N'
stop_key	equ 'Z'
clear_key	equ 'C'
tempo_key	equ 'X'
realtime_pb_key	equ 'B'
man_entry_key	equ 'V'
version_key	equ 'Q'
change_ch_key	equ 'C'
clear_note_key	equ '.'
rec_ch1_key	equ $04
rec_ch2_key	equ $10
rec_ch3_key	equ $09
rec_ch4_key	equ $02

; =========================
; Sequencer Addresses
; =========================
seq_dac_base equ $E020		; Writing to this address outputs the value on the DAC, scaled to 0-5V
seq_drum_addr equ $E024		; Writing to this address sets the drum triggers
seq_gate_addr equ $E028		; Writing to this address sets the gate triggers for the analog channels

; =========================
; Memory Addresses
; =========================
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
seq_num_spaces equ $4048	; The number of spaces to print between markings, allows printing extra info between notes without breaking spacing
realtime_temp_data equ $4049	; Address holding temporary data to be played on during realtime playback
current_octave equ $404a	; The current octave value to add to keyboard input
octave_printed equ $404b	; Set if the current octave has been printed for drawing routines
get_beat_temp equ $404c		; Temporary value for get beat when performing addition calculations
play_beat_temp	equ $404d	; Temporary value for play beat when performing additional calculations


; =========================
; Default Values
; =========================
default_tempo equ 500
gate_time equ 20

; =========================
; Entry
; =========================
	org $E800

	;fcb 0x10
	;fcb 0x4a
	
	; Set default tempo
	ldd #default_tempo
	std seq_tempo

	; Set default ocatve
	lda #103
	sta current_octave

	; Clear the data memory of existing data
	ldx #seq_data_base
	ldb #0x40
	clra
data_cl	sta ,x+
	decb
	bne data_cl

	; Print banner
	jsr [pcrlf]

	lda #30
	jsr printspaces
	ldx #banner
	jsr [pdata]

	; Print Controls	
redraw	jsr [pcrlf]
	lda #13
	jsr printspaces
	ldx #controls
	jsr [pdata]
	jsr [pcrlf]
	lda #22
	jsr printspaces
	ldx #controls2
	jsr [pdata]

	jsr drawscreen
poll	jsr [inchek]
	beq poll

	jsr [inch]
;	cmpa #'f'
;	beq crashme
	cmpa #playback_key
	beq do_playback
	cmpa #record_key
	beq do_record
	cmpa #tempo_key
	beq do_tempo
	cmpa #clear_key
	beq do_clear
	cmpa #realtime_pb_key
	beq do_realtime_playback
	cmpa #man_entry_key
	beq do_manual_entry
	cmpa #version_key
	beq do_version

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
do_version
	ldx #version
	jsr [pdata]
	bra redraw
;crashme
;	ldx #cm_msg
;	jsr [pdata]
;crashmenow
;	fcb $10
;	fcb $45
;cm_msg	fcc "ManCrash"
;	fcb $4

; =========================
; Manual Entry subroutine
; =========================
manual_entry
	; Set initial state
	clr octave_printed

	; Prompt for channel
	ldx #channel_prompt_msg
	jsr [pdata]

	; Get channel to record
me_wfch	jsr [inchek]
	beq me_wfch
	jsr [inch]
	cmpa #stop_key
	lbeq me_done
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

	; Set the default number of spaces to print between marks
	lda #2
	sta seq_num_spaces

	ldy #seq_cur_beat
	clr ,y
me_loop	jsr [inchek]
	beq me_loop
	jsr [inch]

	; Check for stop
	cmpa #stop_key
	beq me_done

	; Do input processing
	ldb seq_record_ch
	jsr get_beat
	bne me_loop

	; Play Beat
	lda ,y
	jsr play_beat
	jsr delay_gate_time

	; ===Print tick===
	lda seq_num_spaces
	tsta
	bpl me_pspa
	clra
me_pspa	jsr printspaces
	lda #2
	sta seq_num_spaces
	
	ldb ,x+
	lda #46
	tstb
	beq me_drawch
	adda #-4
me_drawch
	jsr [outch]

	; Increment beat counter
	lda ,y
	inca
	sta ,y
	cmpa #16
	blt me_loop

	; If at end of line, print line terminator and quit
	lda #'|'
	jsr [outch]
	jsr [pcrlf]

me_done	; Stop any notes being played
	jsr stop_pb

	rts


; =========================
; Realtime Playback subroutine
; =========================
realtime_playback
	; Set initial state
	clr octave_printed

	; Clear any pending played notes (when called internally)
	jsr stop_pb

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
	ldx #seq_dac_base
	abx

	; Check if drum channel, so its record address can be overidden
	cmpb #3
	bne rp_prep
	ldx #seq_drum_addr

	; Make y the actual io address,
	; And x will be the temporary realtime data
	; Required for drum data or-ing
rp_prep	tfr x,y
	ldx #realtime_temp_data

	; Get input from user
rp_play	tst octave_printed
	beq rp_inc
	clr octave_printed
	pshs x
	ldx #oct_change_rp
	jsr [pdata]
	puls x

rp_inc	jsr [inchek]
	beq rp_play
	jsr [inch]
	cmpa #change_ch_key
	beq realtime_playback
	cmpa #stop_key
	beq rp_done

	; Do processing on input data
	ldb seq_record_ch
	clr ,x
	jsr get_beat
	bne rp_play

	; Store temporary register into actual memory
	lda ,x
	sta ,y

	; Calculate and set the gate for the channel being played
	ldb seq_record_ch
	lda #1
rp_gate	lsla
	decb
	bne rp_gate
	lsra
	sta seq_gate_addr

	jsr delay_gate_time

	bra rp_play

rp_done	; Stop any pending playback
	jsr stop_pb

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
	jsr [inch]
	cmpa #$0D
	beq t_check
	jsr [outch]
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
	bgt t_check

	bra t_waitc
t_check	ldd seq_temp_tempo

	; Ensure the tempo doesn't go under minimum gate time
	cmpd #gate_time
	bge t_write
	ldd #gate_time
t_write	std seq_tempo

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
	cmpa #'A'
	beq cl_all
	cmpa #'1'
	blt cl_done
	cmpa #'4'
	bgt cl_done

	; Echo channel select
	tfr a,b
	jsr [outch]

	; Calculate address of sequence data
	subb #49

	; Jump into subroutine at this point to clear channel with b = channel-1 to clear
clear_channel
	lda #0x10
	mul
	ldx #seq_data_base
	abx
	
	; Clear the channel of existing data
	ldb #0x10
cl_loop_entry
	clra
cl_loop	sta ,x+
	decb
	bne cl_loop
cl_done
	rts

cl_all	; Clear all channels
	jsr [outch]
	ldx #seq_data_base
	ldb #0x40
	bra cl_loop_entry

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
	cmpa #stop_key
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
	; Set the default number of spaces to print between marks
	lda #2
	sta seq_num_spaces

pb_run	lda #'|'
	jsr [outch]
	
	clr seq_cur_beat   	; Set the currently played beat to 0
	
pb_loop	
	; Delay
	jsr delay_tempo

	; Check if input is pending for changing record channel
pb_wait	lda seq_record_ch
	cmpa #0xFE
	bne pb_ckqt
	jsr isr_key		; This will block until a key is entered
	bra pb_wait

pb_ckqt	; Check if during delay an interrupt fired which stopped playback
	lda seq_record_ch
	cmpa #0xFF
	beq pb_done

	; Play Beat
	lda seq_cur_beat
	jsr play_beat

	; ===Print tick===

	; Print number of spaces required, then reset the value
	lda seq_num_spaces
	tsta
	bpl pb_pspa
	clra
pb_pspa	jsr printspaces
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
	
	lda #46
	tstb
	beq pb_drawch
	adda #-4
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

pb_done	; Stop any notes being played
	jsr stop_pb

	rts


; =========================
; Draw Screen subroutine
; =========================
; Draws the screen displaying the sequence
drawscreen
	jsr [pcrlf]
	clrb
	pshs b
	
ds_drawrow
	; Print out the pre-padding
	lda #10	; Pre-padding without channel id

	; Channel headers get lower spacing for channel id prefix
	cmpb #3
	blt ds_pleadspaces
	cmpb #7
	bge ds_pleadspaces
	lda #7 ; Pre-padding with channel id
ds_pleadspaces
	jsr printspaces

	cmpb #3
	blt ds_printheader
	cmpb #7
	bge ds_printheader
	tfr b,a
	adda #46
	jsr [outch]
	lda #':'
	jsr [outch]
	lda #32
	jsr [outch]

ds_printheader
	; Print row title
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
	lda #32
	tstb
	beq ds_print_channel_val
	adda #10
ds_print_channel_val
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
	puls b
	incb

	cmpb #8
	beq ds_done
	
	pshs b
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
; x,y register is saved
delay_tempo
	pshs x,y
	tfr x,y
	ldx #0
	ldb #1
d_ms	clra
d_cyc	inca
	jsr [inchek]
	beq d_nkey
	jsr isr_key
d_nkey	cmpa #74
	bne d_cyc

	abx
	cmpx #gate_time
	bne d_cnt
	clr seq_gate_addr
	clr seq_drum_addr
d_cnt	cmpx seq_tempo
	bne d_ms
	puls x,y
	rts

; =========================
; Delay Gate Time Subroutine
; =========================
; a,b registers are not saved
delay_gate_time
	; Delay for approx. gate_time to give time for gate to settle when performing playback
	; Clears gates and drum channels at end of subroutine
	
	ldd #$C0*gate_time
rp_cyc	jsr [inchek]	; Waste cycles, value being thrown out
	subd #1
	bne rp_cyc

	clr seq_gate_addr
	clr seq_drum_addr
	rts

; =========================
; Play Beat Subroutine
; =========================
; The a register should contain the offset
; The b,x,y register is saved
p_b_incy
	tfr y,d
	addd #1
	tfr d,y
	bra p_b_skipwrite
play_beat
	pshs x,y,b

	; Setup initial address
	ldx #seq_data_base
	tfr a,b
	abx
	pshs x			; Save x register to be pulled again to save calculation time
	ldy #seq_dac_base

	; Set channel count to transfer to dac
	ldb #3
	
	; Write each channel's value for the given beat
p_b_wch	pshs b
	lda ,x
	tstb
	beq p_b_ondrum
	tsta
	beq p_b_incy
p_b_ondrum
	sta ,y+
p_b_skipwrite
	ldb #16
	abx
	puls b
	decb
	bne p_b_wch

	; Finally store last A value into drum channel
	lda ,x
	sta seq_drum_addr

	; Recalculate the gate
	; This is fine loop through again, since there will need to be at least 20us for the DAC to settle, so we can waste some time
	puls x
	lda #1			; temp register contains the value to or for that specific channel if it is non-zero for gating
	sta play_beat_temp
	clra			; a contains the value to write to the gate
	ldb #4			; b contains number of channels to search
p_b_cg	tst ,x
	beq p_b_ng
	ora play_beat_temp
p_b_ng	lsl play_beat_temp
	pshs b
	ldb #16
	abx
	puls b
	decb
	bne p_b_cg

	sta seq_gate_addr

	puls x,y,b
	rts

; =========================
; Get Beat Subroutine
; =========================
; a is the beat to get
; b is the channel to record to (used in decoding logic)
; x is the address to store data in
; Saves y,x
; Returns: cc.z = 0 on no data written, cc.z = 1 on data written
get_beat
	pshs y
	cmpa #clear_note_key
	beq gb_clrv
	cmpa #32
	beq gb_done
	cmpb #4		; If on drum channel, do different decoding
	beq gb_drum

	; Check for octave lookup
	cmpa #'1'
	blt gb_decode_key_seq
	cmpa #'4'
	bgt gb_decode_key_seq
	; Set octave
	
	; Print octave
	jsr [outch]

	; Update state for octave input
	dec seq_num_spaces
	ldb #1
	stb octave_printed

	suba #49	; Convert octave to value 0-3

	; Do octave conversion math
	ldb #51
	mul
	incb
	stb current_octave

	clra
	bra gb_done

gb_decode_key_seq
	; Try lookup key

	; Load y with the keyboard_seq lookup string
	; Search through y until either character is found or $04 is reached
	ldy #keyboard_sequence
	; b register contains value at end of index string (when search is finished)
	ldb #4
gb_lookup_key_loop
	cmpb ,y
	beq gb_done
	cmpa ,y+
	bne gb_lookup_key_loop
	
	tfr y,d
	subd keyboard_seq_offset

	; b now contains the # of half-steps up from A
	tfr b,a
	; Divide by 4
	lsra
	lsra
	sta get_beat_temp

	; Also multiply by 4
	lslb
	lslb
	; Add the val/4 + val*4
	addb get_beat_temp
	; Add octave offset
	addb current_octave

	bra gb_write

gb_drum ; Decode Drum Data
	cmpa #'1'
	blt gb_done
	cmpa #'8'
	bgt gb_done

	; a is now loaded with a character between 1 and 8
	; Convert entered character to value
	suba #48
	ldb #1
gb_conv deca
	beq gb_or_data
	lslb
	bra gb_conv
gb_or_data
	orb ,x
	bra gb_write

gb_clrv ; Create a value to clear when writing to memory
	clrb
gb_write
	; Write the calculated value to the sequencer memory
	stb ,x

	; Dirty hack to make it return success on either space or successful decoding
	lda #32
gb_done	puls y
	cmpa #32
	rts

; =========================
; Stop Playback Subroutine
; =========================
; Clears all 4 DAC channels, the 8 drum channels, and the gate signals
; Does not take any arguments
; Saves a,b,x,y
stop_pb
	pshs x,a,b
	ldx #seq_dac_base
	clra
	clrb
	std ,x
	std 2,x
	clr seq_drum_addr
	clr seq_gate_addr
	puls x,a,b
	rts

isr_key	pshs a,b
	
	ldb seq_record_ch
	cmpb #0xFF
	beq isr_end	; Don't process any keypresses if stopping
	
	jsr [inch]

	; Process universal keypresses
	cmpa #stop_key
	beq isr_stop_playback
	cmpa #playback_key
	beq isr_do_playback
	cmpa #record_key
	beq isr_do_record

	; Process keypresses depending on recording/playback/expecting channel data
	cmpb #0
	beq isr_end	; Nothing special to do during playback, only universal keypresses
	cmpb #0xFE
	beq isr_sel_ch	; Do channel selection if it is waiting for a channel

	; Check if keypress is change channel
	cmpa #rec_ch1_key
	beq isr_set_ch1
	cmpa #rec_ch2_key
	beq isr_set_ch2
	cmpa #rec_ch3_key
	beq isr_set_ch3
	cmpa #rec_ch4_key
	beq isr_set_ch4

	; Check if keypress is clear
	cmpa #clear_key
	beq isr_do_clear
	
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

isr_write_ch
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

isr_end	puls a,b
	rts

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
	bra isr_end

isr_set_ch1
	lda #1
	bra isr_set_ch
isr_set_ch2
	lda #2
	bra isr_set_ch
isr_set_ch3
	lda #3
	bra isr_set_ch
isr_set_ch4
	lda #4
	bra isr_set_ch

isr_set_ch
	adda #48
	jsr [outch]
	dec seq_num_spaces

	bra isr_write_ch

isr_do_clear
	; b contains current channel, clear that channel
	; Print command executed
	lda #'C'
	jsr [outch]
	dec seq_num_spaces

	decb
	pshs x,y
	jsr clear_channel
	puls x,y
	bra isr_end

; =========================
; Data Section
; =========================
banner	fcc "***SWTPC Sequencer***\r\n"
	fcb $04
controls
	fcc "M: Play - N: Record - Z: Stop - C: Clear Ch - X: Tempo"
	fcb $04
controls2
	fcc "B: Direct Playback - V: Manual Entry"
	fcb $04
version
	fcc "\r\nAuthor:Robert Pafford 2021-2023\r\nBuild:"
	fcc BUILD_ID
	fcb "\r\n"
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
	fcc "Enter Tempo (enter to end, other to abort): "
	fcb $04
clear_prompt_msg
	fcc "Enter Channel to Clear (A: all, other to abort): "
	fcb $04
realtime_ch_prompt_msg
	fcc "Enter Channel to Play (other to abort): "
	fcb $04
realtime_entry_msg
	fcc "\r\nPress Keys to Play... (C to change channel, Z to abort)\r\n"
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
	fcc "Lead"
	fcb $04

header_ch2
	fcc "Bass"
	fcb $04

header_ch3
	fcc "Chrd"
	fcb $04

header_ch4
	fcc "Drum"
	fcb $04
oct_change_rp
	fcc " Oct\r\n"
	fcb $04
keyboard_sequence
	fcc "AWSEDFTGYHUJKOLP;'"
	fcb $04
keyboard_seq_offset
	; Keyboard sequence address offset in big endian
	; This needs to have 2 subtracted so when the address is subtracted it reports the right number
	; Since it starts at C, and A is the base for CV conversion, it needs to shift it by 3 half-steps, minus one because of post-indexing in the loop
	fdb (keyboard_sequence-2)