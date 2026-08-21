# Legacy SID address example

Install the BASIC wedge, then load or type `sid-info.bas`. It sends the
deprecated `CTRL_CMD_GET_HWINFO` (`40`) with the explicit SID selector (`1`).
Firmware still implements it but may remove it; no replacement C64-side UCI
command is currently published. The first reply byte is the record count; each
record begins with a little-endian primary address.

On an Ultimate 64 with both UltiSIDs and both physical sockets mapped at
`$D400`, `RUN` prints:

```text
SID COUNT: 4
SID 1: 54272
SID 2: 54272
SID 3: 54272
SID 4: 54272
READY.
```
