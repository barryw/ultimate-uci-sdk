# Disk-streamed PCM visualizer

This Ultimate-only demo plays `/USB1/HALL22.WAV` as 22.05 kHz, signed 16-bit
stereo PCM. UCI reads 16 KiB at a time through a C64 RAM staging buffer, then
REU DMA copies it into one of two alternating 1 MiB buffers while Ultimate
Audio plays the other. The full WAV is never held in C64 RAM or the REU.

The six bars are the left and right low, mid, and high bands. Each video frame
the demo fetches a small window from the active REU buffer and analyzes those
actual PCM bytes. The display therefore follows the sample being played rather
than a precomputed animation.

`HallOfTheMountainKing.mid` is Coyau's public-domain Mutopia Project typesetting
of Edvard Grieg's public-domain work (Mutopia reference 1888). The release WAV
is rendered with MuseScore General, distributed under the MIT license. See
`ASSET-LICENSES.md` for source links and exact terms.

Build and run:

```sh
make
make run U64_HOST=192.168.1.62
```
