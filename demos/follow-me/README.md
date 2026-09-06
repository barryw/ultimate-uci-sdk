
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

Requires cc65 (ca65/ld65). `make` builds the self-contained game and links only
the SDK transport, initialization, palette, REU, and audio modules from
`ultimate.lib`. No C runtime or standalone blob is included.

`make check` checks the link map, PCM loops, and palette. `make check-vice`
checks startup, scoring, and input timeout in VICE; `make run` starts the game
interactively with its original SID fallback sounds.

`make hardware U64_HOST=<Ultimate IP>` runs the real keyboard, score, timeout,
and exit checks twice: once with Ultimate PCM/palette enabled, then with UCI
disabled to exercise SID fallback. It restores the settings it changes. Audio
and HDMI appearance still need a person to confirm.

The linker places SDK code at `$4000`, variables at `$9f00`, and SDK zero page
at `$a3-$a6`, away from the game's scratch registers.

On Ultimate hardware, enable Command Interface, REU, and `Map Ultimate Audio
$DF20-DFFF`. Firmware newer than 3.15 is required for runtime palette control.
The game automatically restores the previous palette when the player exits.

### Playing

Start by selecting a level from 1 to 5 where 1 is the fastest and 5 is the slowest. Repeat the notes that the computer plays. If you get it wrong, a buzzer will sound and the game will end.
