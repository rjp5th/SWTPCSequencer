VERSION_FILE := build.version
HISTORY_DIR := history
ROM_SIZE := 2048

all : sequencer.bin

sequencer.bin: sequencer.S
	$(eval BUILD_ID := $(shell { cat "$(VERSION_FILE)" 2>/dev/null || echo; } | awk -F "-" 'END{printf($$1=""?1:$$1+1);if($$2)printf"-"$$2;print""};'))
	../asm6809-2.12/src/asm6809 --definestr=BUILD_ID=$(BUILD_ID) -B -l "$(basename $@).lst" -9 "$<" -o "$@"

	@wc -c <$@ | awk 'END{printf"\nROM %.2f%% full; %d out of %d bytes used\n",$$1/$(ROM_SIZE)*100,$$1,$(ROM_SIZE)}'
	@! { test `wc -c <$@` -gt $(ROM_SIZE) && echo 'Filesize too large!'; }
	@if [ -d "$(HISTORY_DIR)" ]; then cp "$@" "$(HISTORY_DIR)"/"$(basename $(notdir $@))_$(BUILD_ID)$(suffix $@)"; fi
	@if [ -d "$(HISTORY_DIR)" ]; then cp "$<" "$(HISTORY_DIR)"/"$(basename $(notdir $<))_$(BUILD_ID)$(suffix $<)"; fi
	@echo $(BUILD_ID) > $(VERSION_FILE)

.PHONY: clean
clean:
	rm -f *.bin *.lst
