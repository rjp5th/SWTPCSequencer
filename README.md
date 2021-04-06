# Basic Sequencer for SWTPC 6809

## Features
* Recording on four different channels
    * Erases channel on record, repeats allowing modification until stopped
    * Erasing of previously played note with `.`
    * Live preview of notes as they are recorded
* Playback of recorded sequence
* Changing tempo of playback

## Configured Memory Map
* ROM Loaded at 0x8000
* Scratch RAM at 0x4000-0x4050
* IO Card at 0xE020-0xE023

## Sequencer in Action
![Sequencer Screenshot](screenshot.png)
