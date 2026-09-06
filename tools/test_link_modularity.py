"""Link-only checks: unused SDK services must stay out of C and ca65 programs."""

from pathlib import Path
import hashlib
import re
import runpy
import shlex
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
BINDING = REPO / "bindings/cc65"
LIB = BINDING / "build/ultimate.lib"
TRANSPORT = {"uci_core.o", "service_common.o"}

# Expressions are never executed. These deliberately omit initialization so
# the map measures each operation's dependencies, not application startup.
CASES = (
    ("palette", "ultimate_palette_set_color(0, 0, 0, 0)",
     "ultimate_palette_set_color", TRANSPORT | {"palette.o"}, {"cc65_palette.o"}),
    ("net", 'ultimate_net_connect("localhost", 80, 0)',
     "ultimate_net_connect", TRANSPORT | {"net.o"},
     {"cc65_net.o", "cc65_helpers.o"}),
    ("http", 'ultimate_http_get("http://localhost/", 0, 0, 0)',
     "ultimate_http_get", TRANSPORT | {"http.o"},
     {"cc65_http.o", "cc65_helpers.o"}),
    ("reu", "ultimate_reu_fetch(0, 0, 1)",
     "ultimate_reu_fetch", TRANSPORT | {"reu.o"}, {"cc65_reu.o"}),
    ("file", 'ultimate_load("test.prg", 0)',
     "ultimate_load", TRANSPORT | {"file.o", "dos.o"},
     {"cc65_file.o", "cc65_helpers.o"}),
    ("audio", "ultimate_audio_start(0, 0)",
     "ultimate_audio_start", {"uci_core.o", "audio.o"}, {"cc65_audio.o"}),
    ("turbo", "ultimate_turbo_get()",
     "ultimate_turbo_get", {"turbo.o"}, set()),
    ("vsprite", "ultimate_vsprite_draw(0)",
     "ultimate_vsprite_draw", {"vsprite.o"}, set()),
)


@unittest.skipUnless(shutil.which("cl65"), "cc65 is not installed")
class LinkModularity(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        subprocess.run(["make", "-C", str(BINDING)], check=True,
                       capture_output=True, text=True)

    def link(self, directory, language, source):
        path = directory / ("probe." + language)
        path.write_text(source)
        linkmap = directory / "probe.map"
        result = subprocess.run([
            "cl65", "-t", "c64", "-Osir", "-I", str(REPO / "include"),
            "--asm-include-dir", str(REPO / "bindings/asm"),
            "-m", str(linkmap), "-o", str(directory / "probe.prg"),
            str(path), str(LIB),
        ], capture_output=True, text=True, cwd=directory)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return set(re.findall(r"ultimate\.lib\(([^)]+)\)", linkmap.read_text()))

    def test_only_selected_services_are_linked(self):
        with tempfile.TemporaryDirectory() as tmp:
            for name, expression, symbol, services, adapters in CASES:
                sources = {
                    "c": '#include "ultimate.h"\n'
                         f"int main(void) {{ return {expression}; }}\n",
                    "s": '.include "ultimate.inc"\n'
                         '.forceimport __STARTUP__\n.export _main\n.code\n'
                         f"_main:\n    jsr {symbol}\n    rts\n",
                }
                for language, source in sources.items():
                    with self.subTest(service=name, language=language):
                        modules = self.link(Path(tmp), language, source)
                        expected = services | (adapters if language == "c" else set())
                        self.assertEqual(modules, expected)

    def test_every_c_adapter_resolves(self):
        # Some seldom-used wrappers have no runtime harness entry. Reference
        # every public adapter so a missed helper export/import fails to link.
        symbols = []
        for path in sorted(BINDING.glob("cc65_*.s")):
            symbols += re.findall(r"^\s*\.export (_\w+)$", path.read_text(), re.M)
        self.assertTrue(symbols)
        source = '.forceimport __STARTUP__\n.export _main\n.code\n_main: rts\n'
        source += "\n".join(f".import {s}\n.addr {s}" for s in symbols) + "\n"
        with tempfile.TemporaryDirectory() as tmp:
            self.link(Path(tmp), "s", source)

    def test_example_and_demo_link_maps(self):
        # Use the real Makefiles, not substitute compiler commands. These
        # targets need no hardware, TeX, generated speech bank or network.
        consumers = {
            "examples/asm": ("all", {
                "identify": {"ultimate_asm"}, "sid-info": set(),
                "fileinfo": {"dos", "dosinfo", "control"},
            }),
            "examples/cc65": ("all", {
                "identify": {"ultimate_strerror"},
                "sid-info": {"ultimate_strerror"},
                "files": {"dos", "dosinfo", "clock", "control", "reu", "ultimate_strerror"},
            }),
            "guide": ("check-examples", {
                "examples/discover": set(), "examples/hello-asm": set(),
                "examples/hello-c": {"ultimate_strerror"},
            }),
            "demos/sid-visualizer": ("all", {
                "build/visualizer": {"palette", "turbo"},
            }),
            "demos/pcm-visualizer": ("all", {
                "pcm-visualizer": {"palette", "dos", "turbo", "reu", "audio"},
            }),
        }
        for directory, (target, maps) in consumers.items():
            with self.subTest(directory=directory):
                command = ["make", "-C", str(REPO / directory), target]
                result = subprocess.run(command, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                # Even an up-to-date consumer must recheck SDK sources. This
                # catches an existing-but-stale archive, especially in guide/.
                dry = subprocess.run(command + ["-n"], check=True,
                                     capture_output=True, text=True)
                self.assertIn("-C ../", dry.stdout)
                self.assertIn("bindings/cc65", dry.stdout)
                for name, services in maps.items():
                    linkmap = REPO / directory / (name + ".map")
                    modules = set(re.findall(r"ultimate\.lib\(([^)]+)\)",
                                             linkmap.read_text()))
                    selected = {m for m in modules if not m.startswith("cc65_")}
                    expected = TRANSPORT | {"ultimate.o"} | {s + ".o" for s in services}
                    self.assertEqual(selected, expected, str(linkmap))
                    if directory == "examples/asm" or name.endswith("hello-asm"):
                        self.assertEqual(modules, selected, "assembly pulled C adapters")

    def test_native_demos_select_only_required_services(self):
        demos = (
            ("boing", "boing", TRANSPORT | {"ultimate.o", "turbo.o", "reu.o", "audio.o", "vsprite.o"}),
            ("vsprites", "vsprites", {"turbo.o", "vsprite.o"}),
            ("follow-me", "followme", TRANSPORT | {"ultimate.o", "palette.o", "reu.o", "audio.o"}),
        )
        for directory, stem, expected in demos:
            with self.subTest(demo=directory):
                path = REPO / "demos" / directory
                result = subprocess.run(["make", "-C", str(path)], capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                modules = set(re.findall(r"ultimate\.lib\(([^)]+)\)",
                                         (path / (stem + ".map")).read_text()))
                self.assertEqual(modules, expected)
                dry = subprocess.run(["make", "-n", "-C", str(path), "-W", stem + ".s"],
                                     check=True, capture_output=True, text=True).stdout
                self.assertIn("bindings/cc65", dry)
                self.assertIn("ca65 -g", dry)
                self.assertIn("ld65 -C", dry)
                self.assertNotIn("bindings/blob", dry)
        subprocess.run(["make", "-C", str(REPO / "demos/follow-me"), "check"],
                       check=True, capture_output=True, text=True)

    def test_vsprite_shapes_match_original_assembler_generated_data(self):
        generator = runpy.run_path(str(REPO / "demos/vsprites/gen_shapes.py"))
        self.assertEqual(hashlib.sha256(generator["build"]()).hexdigest(),
                         "2294e4d991ba051c16264b642430067e894332ad903856626396e7787a4d000e")

    def test_documented_selective_linking_commands(self):
        # Execute the walkthrough's actual commands so copy/paste instructions
        # cannot drift from the Makefiles. shlex handles quotes without a shell.
        doc = (REPO / "docs/selective-linking.md").read_text()
        for extension in ("c", "s", "cfg"):
            source = (REPO / "guide/examples" / ("selective." + extension)).read_text()
            self.assertIn(source.rstrip() + "\n```", doc)
        for block in re.findall(r"```sh\n(.*?)```", doc, re.S):
            for command in block.replace("\\\n", "").strip().splitlines():
                result = subprocess.run(shlex.split(command), cwd=REPO,
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, command + "\n" + result.stdout + result.stderr)
        for language in ("c", "asm"):
            linkmap = (REPO / f"guide/examples/selective-{language}.map").read_text()
            modules = set(re.findall(r"ultimate\.lib\(([^)]+)\)", linkmap))
            self.assertEqual(modules, {"turbo.o"})
            if language == "asm":
                self.assertNotIn("c64.lib(", linkmap)
                self.assertRegex(linkmap, r"(?m)^CODE\s+000900\s")
        prg = (REPO / "guide/examples/selective-asm.prg").read_bytes()
        self.assertEqual(prg[:2], b"\x01\x08")
        self.assertIn(b"\x9e2304\x00", prg[:14])
        self.assertEqual(prg[0x0900 - 0x0801 + 2], 0x20)  # JSR at SYS address
        placed = (REPO / "guide/examples/hello-custom.map").read_text()
        self.assertRegex(placed, r"\bult_up\s+00CF1E\b")  # UCI_VARS + 30


if __name__ == "__main__":
    unittest.main()
