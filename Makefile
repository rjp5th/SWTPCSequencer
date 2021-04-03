
sequencer.bin: sequencer.S
	../asm6809-2.12/src/asm6809 -B -l sequencer.lst -9 $< -o $@