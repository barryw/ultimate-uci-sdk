#!/usr/bin/env python3
"""The blob's jump table and the document that promises it, kept in step.

`bindings/blob/README.md` is the caller-facing contract for every toolchain that
cannot link a ca65 object: a KickAssembler or Oscar64 program `jsr`s a number out
of that table and nothing checks its arithmetic. A row that drifts from
`blob.s` - or an entry added to the code and not to the table - is a wrong
address published as a right one.

The design asked for the table to be generated from the link map. This is the
cheaper half of that: the table stays hand-written, and the build fails if the
two ever disagree.

Three rules:

  - Every `jmp` in the header is documented, at the offset it really has.
  - The offsets are contiguous: `$04`, `$07`, `$0A`, ... with no gaps, because
    the table is a jump table and a gap is a typo.
  - The parameter block's fields are documented at the offsets `blob.s`
    reserves for them.

**The table is append-only.** A test that pinned the offsets literally would
also fail on a legal addition, so this pins the *relationship* instead: what the
code does and what the document says are the same thing.
"""

import os
import re
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BLOB = os.path.join(REPO, "bindings/blob/blob.s")
DOC = os.path.join(REPO, "bindings/blob/README.md")

# `        jmp ultimate_init               ; +$1C`
JUMP = re.compile(r"^\s+jmp\s+(\w+)\s*;\s*\+\$([0-9A-F]{2})", re.M)
# `| `+$1C` | `ultimate_init` | | `A` = result |`
DOC_ROW = re.compile(r"^\|\s*`\+\$([0-9A-F]+)`\s*\|\s*`?([A-Za-z_0-9]+)", re.M)
# The README documents two different things with the same `+$NN` notation - the
# jump table, offsets from the base, and the parameter block, offsets from the
# block - so `+$07` means one thing above this heading and another below it.
PARAM_HEADING = "## The parameter block"
# `bp_attrib:  .res 1                  ; +$151 open's ...`
FIELD = re.compile(r"^(bp_\w+):\s+\.res\s+(\S+)\s*;\s*\+\$([0-9A-F]+)", re.M)


def code_entries():
    """(offset, name) for every entry in the jump table, in order."""
    out = []
    for name, off in JUMP.findall(open(BLOB).read()):
        out.append((int(off, 16), name))
    return out


def doc_sections():
    """The README either side of the parameter block heading."""
    text = open(DOC).read()
    head, _, tail = text.partition(PARAM_HEADING)
    return head, tail


def doc_entries():
    """(offset, name) for every jump table row."""
    head, _tail = doc_sections()
    return [(int(off, 16), name) for off, name in DOC_ROW.findall(head)]


def doc_fields():
    """The offsets the parameter block section documents."""
    _head, tail = doc_sections()
    return {int(off, 16) for off, _name in DOC_ROW.findall(tail)}


def normalise(name):
    """`blob_chdir` in the code is `chdir` in the document, deliberately.

    The shims are named for the file they live in; the document names the
    operation, because that is what a caller is looking for.
    """
    return name[5:] if name.startswith("blob_") else name


class JumpTable(unittest.TestCase):

    def test_the_table_has_no_gaps(self):
        offsets = [off for off, _ in code_entries()]
        self.assertEqual(offsets, list(range(4, 4 + 3 * len(offsets), 3)),
                         "the jump table is three bytes per entry and starts at "
                         "+$04; a gap means a mistyped comment or a missing jmp")

    def test_every_entry_is_documented_at_its_real_offset(self):
        documented = dict(doc_entries())
        missing = []
        wrong = []
        for off, name in code_entries():
            name = normalise(name)
            if off not in documented:
                missing.append("+$%02X %s" % (off, name))
            elif documented[off] != name:
                wrong.append("+$%02X: code says %s, README says %s"
                             % (off, name, documented[off]))
        self.assertEqual([], missing,
                         "in bindings/blob/blob.s and not in its README:\n  "
                         + "\n  ".join(missing))
        self.assertEqual([], wrong, "\n  ".join(wrong))

    def test_the_document_invents_no_entries(self):
        code = {off for off, _ in code_entries()}
        extra = ["+$%02X" % off for off, _n in doc_entries() if off not in code]
        self.assertEqual([], extra,
                         "documented jump table entries the code does not have: "
                         + ", ".join(extra))

    def test_the_parameter_block_fields_are_documented(self):
        documented = doc_fields()
        missing = ["%s at +$%s" % (name, off)
                   for name, _size, off in FIELD.findall(open(BLOB).read())
                   if int(off, 16) not in documented]
        self.assertEqual([], missing,
                         "reserved in blob.s and not in its README: "
                         + "; ".join(missing))


if __name__ == "__main__":
    unittest.main()
