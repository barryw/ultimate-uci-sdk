# Machine Yearning SID visualizer

This Ultimate-only demo turns six live SID voices into six independently
animated 24-bit palette colours. The first SID drives red, green, and blue;
the second drives orange, yellow, and purple. A voice is brighter at a higher
frequency and fades toward black after its gate closes.

The demo reads the player’s own SID shadow registers directly. SID frequency
registers are write-only, so reading `$D400` after playback would not recover
the notes. A 26-byte zero-page swap isolates the player locations shared with
cc65 and the SDK without slowing its 100 Hz playback loop.

Build and run:

```sh
make
```

Load `sid-visualizer.prg` on an Ultimate. `RUN/STOP` restores the previous
palette, silences both SIDs, and resets the C64. Select one of the seven songs
at build time with `make TUNE=0` through `make TUNE=6`.

| `TUNE` | Song |
|---:|---|
| 0 | Division By Zero |
| 1 | Device Not Present |
| 2 | Formula Too Complex |
| 3 | Overflow |
| 4 | Can't Continue |
| 5 | Redo From Start |
| 6 | Return Without Gosub |

Run the hardware smoke test with:

```sh
make run U64_HOST=192.168.1.62
```

It temporarily enables the command interface and maps physical SID socket 2
to `$D500`, proves that playback and the six intensity values advance, exits
through `RUN/STOP`, and restores both settings even if the test fails.

The demo normally discovers two distinct configured SID addresses through
`ultimate_legacy_get_sid_info()`. That API uses firmware’s deprecated
`CTRL_CMD_GET_HWINFO` command. If a future firmware removes it, specify the
addresses explicitly:

```sh
make SID1=0xd400 SID2=0xd500
```

The program stops with a readable message when the palette commands are
unavailable or the SID mappings are not distinct. Palette UCI commands require
firmware newer than 3.15.

## Music licence

“Machine Yearning” is copyright © 2023 Linus Åkesson and is redistributed
under [Creative Commons Attribution-NonCommercial 4.0 International][license].
The music is not covered by the SDK’s MIT licence. This demo is a modified
presentation: it uses the official PSID player and song data with a new
Ultimate palette visualizer. Music source and attribution:
[linusakesson.net/scene/machine-yearning][music].

[license]: https://creativecommons.org/licenses/by-nc/4.0/
[music]: https://linusakesson.net/scene/machine-yearning/
