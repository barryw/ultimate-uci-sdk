
              ______    _ _                 __  __
             |  ____|  | | |               |  \/  |
             | |__ ___ | | | _____      __ | \  / | ___
             |  __/ _ \| | |/ _ \ \ /\ / / | |\/| |/ _ \
             | | | (_) | | | (_) \ V  V /  | |  | |  __/
             |_|  \___/|_|_|\___/ \_/\_/   |_|  |_|\___|


### Introduction

This is a C64 rendition of the 70s game Simon. The object is to mimick the notes that the computer plays which gets harder and harder the more notes that are played. It was inspired by a tutorial I found on Youtube here: https://www.youtube.com/watch?v=A7vYSsLS00Y

This SDK demo preserves the original game and adds two Ultimate features:

- a 24-bit palette with dim lenses and bright illuminated colors;
- signed 8-bit PCM square waves played directly from a 956-byte REU bank.

The tones follow measurements of the full-size Simon: green 415 Hz, red 310 Hz,
yellow 252 Hz, blue 209 Hz, and a 42 Hz losing buzz. The measurements and the
square-wave shape are documented by Simon Inns:
https://www.waitingforfriday.com/?p=586

### Building

Everything is driven from a `Makefile`. `make` builds the SDK blob and the game
with KickAssembler. `make run` starts it in VICE using the original SID sounds.

On Ultimate hardware, enable Command Interface, REU, and `Map Ultimate Audio
$DF20-DFFF`. Firmware newer than 3.15 is required for runtime palette control.
The game automatically restores the previous palette when the player exits.

### Playing

Start by selecting a level from 1 to 5 where 1 is the fastest and 5 is the slowest. Repeat the notes that the computer plays. If you get it wrong, a buzzer will sound and the game will end.

