#!/usr/bin/env python3
"""
Guard a command against the Ultimate's settings drifting out from under it.

Firmware under test resets the Ultimate's configuration constantly, so no
script can assume a baseline - it has to read what a setting actually is,
change it only if it is wrong, and put back exactly what it found. This is
that guard, usable from any Makefile:

    python3 tools/u64_settings.py --host 192.168.1.62 \\
        --require "C64 and Cartridge Settings:Command Interface=Enabled" \\
        -- make -C tests/emulator hardware U64_HOST=192.168.1.62

Every setting named by --require is read first. Only the ones that differ
from what is required get written, and only those get restored afterwards -
a setting that was already correct is never touched, in either direction.
Restore happens whether the wrapped command succeeds, fails, or is
interrupted with Ctrl-C, and the guard exits with the wrapped command's own
status so a Makefile still fails when it should. Nothing here writes flash:
the config endpoint changes only the running configuration, so a power
cycle would restore the machine regardless.

tests/hardware/hwtest.py imports the REST client and the read/restore
helpers from this module rather than keeping its own copy; see it for a
worked example of driving a whole scenario matrix instead of one
--require.

Part of the Ultimate SDK. SPDX-License-Identifier: MIT
"""

import argparse
import json
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request


class Ultimate:
    """Minimal client for the Ultimate's REST API (v1)."""

    def __init__(self, host, port=80, timeout=15):
        self.base = "http://%s:%d/v1" % (host, port)
        self.timeout = timeout

    def _request(self, method, path, data=None, content_type=None):
        url = self.base + path
        req = urllib.request.Request(url, data=data, method=method)
        if content_type:
            req.add_header("Content-Type", content_type)
        with urllib.request.urlopen(req, timeout=self.timeout) as resp:
            return resp.read()

    def info(self):
        return json.loads(self._request("GET", "/info"))

    def get_setting(self, category, item):
        raw = self._request("GET", "/configs/" + urllib.parse.quote(category))
        return json.loads(raw)[category][item]

    def set_setting(self, category, item, value):
        path = "/configs/%s/%s?value=%s" % (
            urllib.parse.quote(category),
            urllib.parse.quote(item),
            urllib.parse.quote(str(value)),
        )
        body = json.loads(self._request("PUT", path))
        errors = body.get("errors") or []
        if errors:
            raise RuntimeError("setting %s/%s to %r failed: %s"
                               % (category, item, value, errors))

    def readmem(self, address, length):
        return self._request(
            "GET", "/machine:readmem?address=%x&length=%d" % (address, length))

    def writemem(self, address, data):
        self._request("POST", "/machine:writemem?address=%x" % address,
                      data=data, content_type="application/octet-stream")

    def run_prg(self, path):
        with open(path, "rb") as fh:
            payload = fh.read()
        self._request("POST", "/runners:run_prg", data=payload,
                      content_type="application/octet-stream")

    def run_crt(self, path):
        """Load a .crt into cartridge ROM and start the machine on it.

        The cartridge stays mapped afterwards, so a reset runs it again. Going
        back to a machine without one means run_prg, which starts the C64 with
        no cartridge - or a power cycle.
        """
        with open(path, "rb") as fh:
            payload = fh.read()
        self._request("POST", "/runners:run_crt", data=payload,
                      content_type="application/octet-stream")


def read_settings(u, keys):
    """keys: iterable of (category, item). -> {(category, item): value}."""
    return {key: u.get_setting(*key) for key in keys}


def require_settings(u, requirements):
    """Make every (category, item) -> value in `requirements` true.

    Reads each setting's current value first and writes only the ones that
    differ from what is required. Returns {(category, item): original
    value} for exactly the settings this call changed - what the caller
    must restore, and nothing else.
    """
    changed = {}
    for key, desired in requirements.items():
        current = u.get_setting(*key)
        if str(current) != str(desired):
            u.set_setting(key[0], key[1], desired)
            changed[key] = current
    return changed


def restore_settings(u, saved, warn=None):
    """Write back {(category, item): value}, best-effort, one at a time.

    This runs during cleanup, often after something has already gone
    wrong, so a failure restoring one setting must not stop the others
    from being tried. Pass `warn(message)` to report a failure and
    continue; without it, the first failure raises.
    """
    for key, value in saved.items():
        try:
            u.set_setting(key[0], key[1], value)
        except Exception as exc:            # noqa: BLE001 - best effort
            if warn is None:
                raise
            warn("could not restore %s to %r: %s" % (key[1], value, exc))


def run_and_restore(u, changed, runner, command, warn=None):
    """Run `runner(command)`, always restoring `changed` afterwards.

    `changed` is normally require_settings()'s return value: the exact set
    of settings to put back. Restoration happens in `finally`, so it runs
    whether `runner` returns a status, raises, or the process is
    interrupted with Ctrl-C. The wrapped command's own return value (its
    exit status) is passed straight through.
    """
    try:
        return runner(command)
    finally:
        if changed:
            restore_settings(u, changed, warn=warn)


def parse_setting_spec(spec):
    """'Category:Item=Value' -> ((category, item), value)."""
    if ":" not in spec or "=" not in spec:
        raise ValueError("expected CATEGORY:ITEM=VALUE, got %r" % spec)
    category, rest = spec.split(":", 1)
    item, value = rest.split("=", 1)
    return (category, item), value


def main():
    # Split our own arguments from the wrapped command ourselves, rather than
    # leaning on argparse's REMAINDER handling of "--": that interacts badly
    # with options (like the wrapped command's own --flags) appearing after
    # it in some argparse versions, and a plain str.split is unambiguous.
    argv = sys.argv[1:]
    if "--" in argv:
        idx = argv.index("--")
        own_args, command = argv[:idx], argv[idx + 1:]
    else:
        own_args, command = argv, []

    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--host", required=True, help="hostname or IP of the Ultimate")
    ap.add_argument("--port", type=int, default=80)
    ap.add_argument("--require", action="append", default=[],
                    metavar="CATEGORY:ITEM=VALUE",
                    help="a setting the wrapped command needs; repeatable")
    args = ap.parse_args(own_args)

    if not args.require:
        ap.error("at least one --require CATEGORY:ITEM=VALUE is needed")
    if not command:
        ap.error("no command given - put it after --")

    requirements = {}
    for spec in args.require:
        try:
            key, value = parse_setting_spec(spec)
        except ValueError as exc:
            ap.error(str(exc))
        requirements[key] = value

    u = Ultimate(args.host, args.port)

    try:
        changed = require_settings(u, requirements)
    except (urllib.error.URLError, OSError) as exc:
        print("cannot reach the Ultimate at %s: %s" % (args.host, exc))
        return 2

    if changed:
        for key, was in changed.items():
            print("# %s: %s -> %s (will be restored afterwards)"
                  % (key[1], was, requirements[key]))
    else:
        print("# required settings already correct, nothing changed")

    def warn(msg):
        print("# WARNING: %s" % msg)

    try:
        status = run_and_restore(u, changed, subprocess.call, command, warn=warn)
    finally:
        if changed:
            print("# settings restored")

    return status


if __name__ == "__main__":
    sys.exit(main())
