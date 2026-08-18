#!/usr/bin/env python3
"""The generated constant files, put through the assemblers they are for.

`bindings/acme/uci_protocol.a` and `bindings/kickass/uci_protocol.asm` are
written for assemblers this project does not otherwise run. Nothing in the build
has ever fed them to ACME or KickAssembler, so a syntax change in
`tools/gen_protocol.py` - a stray character in a comment, a value the emitter
formats differently - would ship broken and be found by a user.

**Skipped when the assembler is not installed**, the same bargain
`tests/emulator`'s BASIC suite makes for Commodore's ROMs: CI keeps running, and
anyone with the tool gets the check for free.

    brew install acme                      # or apt-get install acme
    KICKASS_JAR=/path/to/KickAss.jar       # KickAssembler is a jar
"""

import os
import shutil
import subprocess
import tempfile
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

ACME_SOURCE = os.path.join(REPO, "bindings/acme/uci_protocol.a")
KICKASS_SOURCE = os.path.join(REPO, "bindings/kickass/uci_protocol.asm")

# One constant of each kind the emitters produce: a 16-bit register address, an
# 8-bit command, and a result code. If the file assembles and these three
# resolve, the format is intact.
ACME_PROGRAM = """!source "%s"
        * = $c000
        lda #ULTIMATE_OK
        ldx #UCI_TARGET_DOS1
        sta UCI_REG_CONTROL
        rts
"""

KICKASS_PROGRAM = """#import "%s"
        *=$c000
        lda #uci.ULTIMATE_OK
        ldx #uci.UCI_TARGET_DOS1
        sta uci.UCI_REG_CONTROL
        rts
"""


def kickass_jar():
    """The KickAssembler jar, from the environment or the usual place."""
    jar = os.environ.get("KICKASS_JAR")
    if jar and os.path.exists(jar):
        return jar
    default = os.path.expanduser("~/Development/Kickassembler/KickAss.jar")
    return default if os.path.exists(default) else None


class GeneratedFilesAssemble(unittest.TestCase):

    def build(self, program, source, argv, out_name):
        with tempfile.TemporaryDirectory() as tmp:
            src = os.path.join(tmp, "check.asm")
            with open(src, "w") as fh:
                fh.write(program % source)
            out = os.path.join(tmp, out_name)
            result = subprocess.run(argv(src, out), capture_output=True,
                                    text=True, cwd=tmp)
            self.assertEqual(0, result.returncode,
                             "%s\n%s" % (result.stdout, result.stderr))
            self.assertTrue(os.path.exists(out), "no output was produced")

    @unittest.skipUnless(shutil.which("acme"), "acme is not installed")
    def test_acme_assembles_its_constants(self):
        self.build(ACME_PROGRAM, ACME_SOURCE,
                   lambda src, out: ["acme", "-f", "plain", "-o", out, src],
                   "check.bin")

    @unittest.skipUnless(kickass_jar(), "KickAssembler is not installed")
    def test_kickassembler_assembles_its_constants(self):
        self.build(KICKASS_PROGRAM, KICKASS_SOURCE,
                   lambda src, out: ["java", "-jar", kickass_jar(), src,
                                     "-o", out],
                   "check.prg")


if __name__ == "__main__":
    unittest.main()
