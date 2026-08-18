#!/usr/bin/env python3
"""Every wedge keyword reaches code, or the build fails.

`tools/gen_coverage.py` refuses an SDK entry point with no test behind it. The
wedge's keywords sit outside that check, and they have a failure mode of their
own: `gen_keywords.py` is the single source of truth for tokenising, for LIST
and for dispatch, so a name added there is immediately typed, crunched,
tokenised and listed back - and dispatches to nothing at all. The program runs,
the statement does nothing, and no build step notices.

`basic.suite` covers today's keywords by hand. That is not the same thing as
being unable to forget the next one.

This is the table-versus-code check `tools/test_blob_table.py` is, pointed at
`src/basic/dispatch.s`: walk KEYWORDS, and fail on a token no comparison in the
wedge can ever match.

**Dispatch is not one comparison per token, and the check cannot pretend it
is.** Two families are decided by range - the six file keywords in `wedge_gone`
and the six target constants in `wedge_eval` - because a range test and a
vector table are smaller than twelve comparisons. So this reads the bounds the
way the 6502 does:

  - `cmp #UCI_TOK_X` with a `beq` behind it matches exactly X.
  - `cmp #UCI_TOK_X` with a `bcc`/`bcs` behind it opens a range at X, and the
    `cmp #UCI_TOK_Y + 1` that follows closes it at Y. The `+ 1` is what makes
    the bound inclusive on a 6502, and it is what makes it findable here.

A range brings a second hole of its own: widen `wedge_gone`'s upper bound for a
seventh file keyword, forget the seventh `.addr`, and the dispatch reads two
bytes past the table and jumps through them. So the vector table is counted
against the range that indexes it as well.

SPDX-License-Identifier: MIT
"""

import os
import re
import unittest

import gen_keywords as gk

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DISPATCH = os.path.join(REPO, "src/basic/dispatch.s")

# Where a keyword of each kind is allowed to be handled. A statement that is
# only known to wedge_eval is a statement that does not run.
STATEMENT_ROUTINES = ("wedge_gone",)
# UW( and UL( are functions in name only: they are the width forcers, legal
# solely inside a UCI argument list, and wedge_arg is the whole of their
# dispatch. `PRINT UW(5)` is a syntax error on purpose.
EXPRESSION_ROUTINES = ("wedge_eval", "wedge_arg")

# A label in the first column starts a routine; `@local:` ones do not.
LABEL = re.compile(r"^([A-Za-z_]\w*):")
# `        cmp #UCI_TOK_UFETCH + 1`
CMP = re.compile(r"^\s+cmp\s+#UCI_TOK_(\w+?)\s*(\+\s*1)?\s*(?:;.*)?$")
BRANCH = re.compile(r"^\s+(b[a-z]{2})\b")
ADDR = re.compile(r"^\s+\.addr\s+(\w+)")


def routines(path):
    """{name: [line, ...]} for every first-column label in the file."""
    out = {}
    body = None
    with open(path) as fh:
        for line in fh:
            found = LABEL.match(line)
            if found:
                body = out.setdefault(found.group(1), [])
                continue
            if body is not None:
                body.append(line.rstrip("\n"))
    return out


def branch_after(lines, index):
    """The branch a comparison is decided by, or None if it is not decided."""
    for line in lines[index + 1:]:
        found = BRANCH.match(line)
        if found:
            return found.group(1)
        if line.strip() and not line.lstrip().startswith(";"):
            return None
    return None


def comparisons(lines, tokens):
    """What a routine's comparisons match: (exact, ranges, unknown).

    `tokens` maps a ca65 symbol suffix - UCI, UDATS, UW - to its token byte.
    `ranges` is a list of inclusive (low, high) pairs. An unknown symbol is a
    typo in the source and is reported rather than quietly matching nothing.
    """
    exact, ranges, unknown = set(), [], []
    low = None                       # a range opened and not yet closed
    for index, line in enumerate(lines):
        found = CMP.match(line)
        if not found:
            continue
        name, plus_one = found.group(1), bool(found.group(2))
        if name not in tokens:
            unknown.append(name)
            continue
        value = tokens[name]

        if plus_one:
            # An inclusive upper bound closes the range the last carry test
            # opened. On its own it is a bound and matches nothing.
            if low is not None:
                ranges.append((low, value))
                low = None
            continue

        branch = branch_after(lines, index)
        if branch in ("beq", "bne"):
            # `beq handler` is the obvious form. `bne skip` is the same claim
            # made backwards, and it is what a handler out of branch range
            # forces: cmp, bne past a jmp, jmp to the handler. Both mean the
            # token is compared and acted on, which is the whole question here.
            exact.add(value)
        elif branch in ("bcc", "bcs"):
            low = value
    return exact, ranges, unknown


def token_table():
    """{ca65 symbol suffix: (name, kind, token)}."""
    return {gk.symbol(name): (name, kind, token)
            for name, kind, _note, token, _match, _display in gk.entries()}


def spread(ranges):
    """Every token value the ranges cover."""
    out = set()
    for low, high in ranges:
        out |= set(range(low, high + 1))
    return out


class Dispatch(unittest.TestCase):

    def setUp(self):
        self.routines = routines(DISPATCH)
        self.table = token_table()
        values = {sym: token for sym, (_n, _k, token) in self.table.items()}
        self.exact, self.ranges = {}, {}
        unknown = []
        for name, lines in self.routines.items():
            hits, spans, bad = comparisons(lines, values)
            self.exact[name], self.ranges[name] = hits, spans
            unknown += ["%s in %s" % (sym, name) for sym in bad]
        self.assertEqual([], unknown,
                         "dispatch.s compares against a token the keyword "
                         "table does not define: " + ", ".join(unknown))

    def reachable(self, routine_names):
        out = set()
        for name in routine_names:
            self.assertIn(name, self.routines,
                          "%s is gone from dispatch.s; this check is now "
                          "looking at the wrong code" % name)
            out |= self.exact[name] | spread(self.ranges[name])
        return out

    def unhandled(self, wanted_kind, reachable):
        return ["%s ($%02X)" % (name, token)
                for _sym, (name, kind, token) in sorted(self.table.items())
                if wanted_kind(kind) and token not in reachable]

    def test_every_statement_keyword_is_dispatched(self):
        missing = self.unhandled(lambda kind: kind == gk.STATEMENT,
                                 self.reachable(STATEMENT_ROUTINES))
        self.assertEqual([], missing,
                         "tokenised and listed, but no statement dispatch will "
                         "ever match: " + ", ".join(missing))

    def test_every_function_and_constant_is_evaluated(self):
        missing = self.unhandled(lambda kind: kind != gk.STATEMENT,
                                 self.reachable(EXPRESSION_ROUTINES))
        self.assertEqual([], missing,
                         "tokenised and listed, but no expression dispatch "
                         "will ever match: " + ", ".join(missing))

    def test_the_file_vector_table_is_as_long_as_the_range_that_indexes_it(self):
        """`wedge_gone`'s range test and `wedge_file_vec` are one mechanism.

        The range decides that a token is handled; the table decides where. A
        range one wider than the table is a jump through whatever two bytes
        happen to follow it.
        """
        spans = self.ranges["wedge_gone"]
        self.assertEqual(1, len(spans),
                         "wedge_gone has %d ranged families; this check knows "
                         "how to count one" % len(spans))
        low, high = spans[0]
        vectors = [ADDR.match(line).group(1)
                   for line in self.routines["wedge_file_vec"]
                   if ADDR.match(line)]
        self.assertEqual(high - low + 1, len(vectors),
                         "wedge_gone dispatches %d tokens through a table of "
                         "%d addresses" % (high - low + 1, len(vectors)))
        self.assertEqual(len(set(vectors)), len(vectors),
                         "two file keywords share a handler: "
                         + ", ".join(vectors))

    def test_the_ranges_start_and_end_on_real_keywords(self):
        """A bound naming a token that is not in the table is a stale bound."""
        values = {token for _s, (_n, _k, token) in self.table.items()}
        for routine in STATEMENT_ROUTINES + EXPRESSION_ROUTINES:
            for low, high in self.ranges[routine]:
                self.assertIn(low, values, "%s: range opens off the table" % routine)
                self.assertIn(high, values, "%s: range closes off the table" % routine)
                self.assertLessEqual(low, high,
                                     "%s: range %02X..%02X runs backwards"
                                     % (routine, low, high))


if __name__ == "__main__":
    unittest.main()
