#!/usr/bin/env python3
"""Fail when the guide's API reference drifts from its public interfaces."""

import importlib.util
import re
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent


def names(pattern, text):
    return [name.replace(r"\_", "_").replace(r"\$", "$")
            for name in re.findall(pattern, text)]


def untex(text):
    return text.replace(r"\_", "_").replace(r"\$", "$")


def compact(text):
    return re.sub(r"\s+", "", untex(text))


def macro_arguments(text, macro, count):
    """Return balanced brace arguments for every use of a TeX macro."""
    marker = "\\" + macro
    found = []
    start = 0
    while True:
        start = text.find(marker, start)
        if start < 0:
            return found
        pos = start + len(marker)
        while pos < len(text) and text[pos].isspace():
            pos += 1
        if pos == len(text) or text[pos] != "{":
            start += len(marker)
            continue
        args = []
        for _ in range(count):
            while pos < len(text) and text[pos].isspace():
                pos += 1
            if pos == len(text) or text[pos] != "{":
                raise SystemExit(f"{macro} at byte {start} has a missing argument")
            depth = 1
            begin = pos = pos + 1
            while pos < len(text) and depth:
                if text[pos] == "{" and text[pos - 1] != "\\":
                    depth += 1
                elif text[pos] == "}" and text[pos - 1] != "\\":
                    depth -= 1
                pos += 1
            if depth:
                raise SystemExit(f"{macro} at byte {start} has an unclosed argument")
            args.append(text[begin:pos - 1])
        found.append(args)
        start = pos


def compare(label, public, documented):
    duplicates = sorted(name for name, count in Counter(documented).items()
                        if count > 1)
    documented = set(documented)
    missing = sorted(public - documented)
    extra = sorted(documented - public)
    if missing or extra or duplicates:
        lines = [f"{label} reference is out of date:"]
        if missing:
            lines.append("  missing: " + ", ".join(missing))
        if extra:
            lines.append("  extra: " + ", ".join(extra))
        if duplicates:
            lines.append("  duplicate: " + ", ".join(duplicates))
        raise SystemExit("\n".join(lines))
    print(f"{label}: {len(public)} entries documented")


def basic_rows():
    spec = importlib.util.spec_from_file_location(
        "gen_keywords", ROOT / "tools" / "gen_keywords.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.entries()


def basic_public():
    return {row[0] for row in basic_rows()}


def c_headers():
    return "\n".join((ROOT / path).read_text()
                     for path in ("include/ultimate.h", "include/uci.h"))


def c_public():
    text = c_headers()
    funcs = set(re.findall(
        r"(?:uint8_t|uint16_t|uint32_t|void|const\s+char\s*\*)\s*"
        r"((?:ultimate|uci)_[A-Za-z0-9_]+)\s*\(", text))
    macros = set(re.findall(
        r"^#define\s+(ultimate_(?:has_[A-Za-z0-9_]+|device_code))\s*\(",
        text, re.MULTILINE))
    return funcs | macros


def c_prototypes():
    text = re.sub(r"/\*.*?\*/", "", c_headers(), flags=re.DOTALL)
    return {
        match.group(1): compact(match.group(0)[:-1])
        for match in re.finditer(
            r"(?:uint8_t|uint16_t|uint32_t|void|const\s+char\s*\*)\s*"
            r"((?:ultimate|uci)_[A-Za-z0-9_]+)\s*\([^;]*?\)\s*;",
            text, re.DOTALL)
    }


def c_structs():
    return set(re.findall(
        r"}\s*((?:ultimate|uci)_[A-Za-z0-9_]+)\s*;", c_headers()))


def c_struct_fields():
    text = re.sub(r"/\*.*?\*/", "", c_headers(), flags=re.DOTALL)
    structs = {}
    for body, name in re.findall(
            r"typedef\s+struct\s*\{(.*?)\}\s*((?:ultimate|uci)_[A-Za-z0-9_]+)\s*;",
            text, re.DOTALL):
        structs[name] = {compact(field) for field in body.split(";") if field.strip()}
    return structs


def check_c_details(text):
    documented = {}
    for macro in ("capiref", "capirefout"):
        for args in macro_arguments(text, macro, 8):
            documented[untex(args[0])] = compact(args[2])
    mismatches = [name for name, prototype in sorted(c_prototypes().items())
                  if documented.get(name) != prototype]
    if mismatches:
        raise SystemExit("C prototype mismatch: " + ", ".join(mismatches))

    entries = macro_arguments(text, "structref", 3)
    for index, args in enumerate(entries):
        name = untex(args[0])
        begin = text.find("\\structref{" + args[0])
        next_marker = ("\\structref{" + entries[index + 1][0]
                       if index + 1 < len(entries) else "\\section{")
        end = text.find(next_marker, begin + 1)
        section = text[begin:end]
        commands = {compact(value) for value in
                    re.findall(r"\\cmd\{([^{}]+)\}", section)}
        missing = sorted(c_struct_fields()[name] - commands)
        if missing:
            raise SystemExit(f"{name} field documentation is missing: "
                             + ", ".join(missing))
    print("C prototypes and structure fields: exact")


def check_compiled_call_coverage():
    c_calls = (ROOT / "guide" / "examples" / "c_calls.c").read_text()
    called = set(re.findall(
        r"\b((?:ultimate|uci)_[A-Za-z0-9_]+)\s*\(", c_calls))
    missing = sorted(set(c_prototypes()) - called)
    if missing:
        raise SystemExit("C compile harness does not call: " + ", ".join(missing))

    asm_calls = (ROOT / "guide" / "examples" / "assembly_calls.s").read_text()
    called = set(re.findall(
        r"\bjsr\s+((?:ultimate|uci)_[A-Za-z0-9_]+)", asm_calls))
    missing = sorted(asm_public() - called)
    if missing:
        raise SystemExit("Assembly harness does not call: " + ", ".join(missing))
    print("C and assembly compile harnesses: complete")


def check_basic_details(text):
    for name, kind, _note, token, _match, _display in basic_rows():
        escaped = name.replace("$", r"\$")
        begin = text.find("\\basicapi{" + escaped + "}")
        positions = [text.find("\\basicapi{", begin + 1), len(text)]
        end = min(pos for pos in positions if pos >= 0)
        section = text[begin:end]
        expected = rf"\cmd{{\${token:02X}}} ({token})"
        if expected not in section:
            raise SystemExit(f"{name} token documentation is not {expected}")
        required_parts = [r"\entryfield{Syntax}", r"\begin{screen}"]
        if kind != "constant":
            required_parts.append(r"\entryhead{Purpose}")
        for required in required_parts:
            if required not in section:
                raise SystemExit(f"{name} documentation is missing {required}")
        if (r"\begin{resultbox}" not in section
                and r"\begin{outputbox}" not in section):
            raise SystemExit(f"{name} documentation has no Result or Output")
    print("BASIC tokens and entry sections: exact")


def asm_public():
    text = (ROOT / "bindings/asm/ultimate.inc").read_text()
    exported = set()
    for line in text.splitlines():
        code = line.split(";", 1)[0]
        match = re.match(r"\s*\.global\s+(.+)", code)
        if match:
            exported.update(re.findall(r"(?:ultimate|uci)_[A-Za-z0-9_]+",
                                       match.group(1)))
    return exported - {"uci_req", "uci_more"}


def check_result_codes(text):
    protocol = (ROOT / "include" / "uci_protocol.h").read_text()
    expected = {
        name: int(value)
        for name, value in re.findall(
            r"^#define\s+(ULTIMATE_(?:OK|ERR_[A-Z_]+|END))\s+(\d+)",
            protocol, re.MULTILINE)
        if name != "ULTIMATE_ERR_COUNT"
    }
    documented = {
        untex(name): int(value)
        for value, name in re.findall(
            r"^(\d+)\s*&\s*\\cmd\{(ULTIMATE\\_[A-Z\\_]+)\}",
            text, re.MULTILINE)
    }
    if expected != documented:
        raise SystemExit("Guide result-code table differs from uci_protocol.h")
    print(f"Result codes: {len(expected)} values exact")


def main():
    basic_doc = (ROOT / "guide/chapters/reference-basic.tex").read_text()
    c_doc = (ROOT / "guide/chapters/reference-c.tex").read_text()
    asm_doc = (ROOT / "guide/chapters/reference-assembly.tex").read_text()
    appendix = (ROOT / "guide/chapters/appendices.tex").read_text()

    compare("BASIC", basic_public(), names(r"\\basicapi\{([^}]+)\}", basic_doc))
    compare("C", c_public(),
            names(r"\\(?:capiref|capirefout|cmacroref)\{([^}]+)\}", c_doc))
    compare("C structures", c_structs(),
            names(r"\\structref\{([^}]+)\}", c_doc))
    check_c_details(c_doc)
    check_compiled_call_coverage()
    check_basic_details(basic_doc)
    compare("Assembly", asm_public(), names(r"\\asmref\{([^}]+)\}", asm_doc))
    check_result_codes(appendix)


if __name__ == "__main__":
    main()
