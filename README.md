# Basic Sequencer for SWTPC 6809

## Features
* Recording on four different channels
    * Switching between channels while recording
    * Switching between recording and playback
    * Erasing of previously played note with `.`
    * Live preview of notes as they are recorded
* Playback of recorded sequence
* Clearing of entered channel data
* Changing tempo of playback
* Direct Control of channel instruments
* Manual entry of channel data

## Configured Memory Map
* ROM Loaded at 0xF000
* Scratch RAM at 0x4000-0x4050
* Audio Card at 0xE020-0xE023
* MC6850 Serial Card at 0xE004 [Uses FIRQ for interrupts]
* Timer Card at 0xE008 [Uses FIRQ for interrupts]

## Sequencer in Action
![Sequencer Screenshot](screenshot.png)
