# Logan Approach

Offline ElevenLabs voice generation and signed 8-bit/11.025 kHz PCM packing for
the Ultimate Audio sampler.

The generator uses only Python's standard library and FFmpeg. It caches the
Voice Design response under `generated/`, so an ordinary rerun does not spend
more ElevenLabs credits.

```sh
python3 generate_previews.py --check
python3 generate_previews.py --key-file /private/tmp/logan-elevenlabs.key
afplay generated/controller-1-radio.wav
python3 generate_previews.py --key-file /private/tmp/logan-elevenlabs.key --select 1
```

The finite controller/pilot phrase inventory is in `comms.json`. Each template
expands to a natural radio-sized clip, not individual words.

Generate the complete bank, then build a representative hardware audition:

```sh
python3 generate_previews.py --estimate
python3 generate_previews.py --generate-all
make
```

`generated/logan-comms.reu` is the complete bank; offsets and lengths are in
`generated/logan-comms.json`. Copy `generated/logan-auditions.reu` to
`/usb1/logan-auditions.reu`, run `logan-comms.prg`, select with the cursor keys,
and play with Return, Space, or joystick fire.
