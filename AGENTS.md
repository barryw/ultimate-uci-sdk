@/Users/barry/.codex/RTK.md

## Hardware verification

For changes to SDK code, demos, runnable examples, or executable documentation,
verify the affected programs on the real Ultimate before calling the work
complete. Compilation and emulator passes are necessary checks, not substitutes
for a hardware run. Use the existing hardware runners and test both working
and unavailable-feature paths where relevant.

Read settings first, restore changes afterward, and never flash firmware or
persist configuration merely to run a test. Keep test writes in disposable
scratch space; preserve pre-existing files. Do not run concurrent tests against
the same machine.

Record firmware identity, exact commands, passes, failures, and skips. Separate
status/memory checks from human confirmation of HDMI colors and audible sound.
If hardware or a fixture is unavailable, report that verification gap explicitly;
do not silently count an emulator result or skipped check as a hardware pass.
