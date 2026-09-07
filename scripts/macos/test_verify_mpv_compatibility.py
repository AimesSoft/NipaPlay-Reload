#!/usr/bin/env python3
"""Compile mpv's real custom Swift target and exercise the release gate.

Requires macOS, Xcode, Meson and Ninja. No Flutter, Nix or media dependencies.
Only the Swift input/bridge and media include directories are substituted.
"""

from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
from verify_mpv_compatibility import inspect_binary


ROOT = Path(__file__).resolve().parents[2]
VERIFIER = ROOT / "scripts/macos/verify_mpv_compatibility.py"


@unittest.skipUnless(sys.platform == "darwin", "requires macOS and Xcode")
class MpvSwiftCompatibilityTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="nipaplay-mpv-test-")
        cls.addClassCleanup(cls.temp.cleanup)
        cls.root = Path(cls.temp.name)
        source = cls.root / "source"
        (source / "osdep/mac").mkdir(parents=True)
        (source / "TOOLS").mkdir()
        for name in ["osdep/mac/meson.build", "TOOLS/macos-swift-lib-directory.py"]:
            shutil.copy2(ROOT / "third_party/mpv" / name, source / name)
        (source / "osdep/mac/app_bridge_objc.h").write_text("// Empty test bridge.\n")
        (source / "Fixture.swift").write_text(
            "import Foundation\n"
            "public class Application: NSObject {}\n"
            "public func values() -> [Int] { [1, 2, 3, 4, 5, 6, 7, 8] }\n"
        )
        (source / "reference.c").write_text(
            'extern void *application_class __asm__("_OBJC_CLASS_$__TtC5swift11Application");\n'
            "void *reference_application(void) { return &application_class; }\n"
        )
        (source / "meson.options").write_text("option('swift-flags', type: 'string', value: '')\n")
        swift_version = re.search(
            r"Swift version ([\d.]+)", cls.command("xcrun", "swiftc", "--version")
        ).group(1)
        (source / "meson.build").write_text(
            "project('mpv-swift-regression', 'c', 'objc',\n"
            "  default_options: ['b_lundef=false', 'optimization=2'])\n"
            "source_root = meson.project_source_root()\n"
            "build_root = meson.project_build_root()\n"
            "tools_directory = source_root / 'TOOLS'\n"
            "swift_prog = find_program(run_command('xcrun', '-find', 'swiftc', check: true).stdout().strip())\n"
            f"swift_ver = '{swift_version}'\n"
            "macos_sdk_path = run_command('xcrun', '--sdk', 'macosx', '--show-sdk-path', check: true).stdout().strip()\n"
            "features = {}\n"
            "libplacebo = declare_dependency(variables: {'includedir': source_root})\n"
            "libavutil = libplacebo\n"
            "swift_sources = files('Fixture.swift')\n"
            "sources = files('reference.c')\n"
            "subdir('osdep/mac')\n"
            "shared_library('Mpv', sources, dependencies: dependency('appleframeworks', modules: ['Foundation']))\n"
        )
        host = platform.machine()
        cls.other_arch = "x86_64" if host == "arm64" else "arm64"
        cls.binaries = {}
        # The original cross-files already contain swift_args with -target.
        # These builds demonstrate that mpv ignores those arguments unless its
        # own swift-flags option is also set.
        for label, arch, fixed in [
            ("old-host", host, False),
            ("old-cross", cls.other_arch, False),
            ("fixed-arm64", "arm64", True),
            ("fixed-x86_64", "x86_64", True),
        ]:
            cross_arch = "amd64" if arch == "x86_64" else arch
            cross = cls.root / f"macos-{cross_arch}.ini"
            original = ROOT / f"third_party/libmpv-darwin-build/cross-files/macos-{cross_arch}.ini"
            developer = cls.command("xcode-select", "-p").strip()
            cross.write_text(original.read_text().replace("/Applications/Xcode.app", str(Path(developer).parents[1])))
            build = cls.root / label
            args = ["meson", "setup", str(build), str(source), "--cross-file", str(cross)]
            if fixed:
                args.append(f"-Dswift-flags=-target {arch}-apple-macos11.0")
            cls.command(*args)
            cls.command("meson", "compile", "-C", str(build))
            cls.binaries[label] = build / "libMpv.dylib"

    @staticmethod
    def command(*args):
        result = subprocess.run(args, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if result.returncode:
            raise AssertionError(f"Command failed: {args}\n{result.stdout}")
        return result.stdout

    def test_new_runtime_is_rejected_even_when_library_says_macos_11(self):
        binary = self.binaries["old-host"]
        _, errors = inspect_binary(binary)
        imports = self.command("xcrun", "nm", "-um", str(binary))
        if "StaticArrayStorage" not in imports:
            self.skipTest("host Swift does not emit the newer runtime symbol")
        self.assertTrue(any("StaticArrayStorage" in e for e in errors), errors)
        self.assertFalse(any("deployment target" in e for e in errors), errors)

    def test_cross_build_with_wrong_swift_architecture_is_rejected(self):
        architectures, errors = inspect_binary(self.binaries["old-cross"])
        self.assertEqual(architectures, {self.other_arch})
        self.assertTrue(any("missing mpv Swift class" in e for e in errors), errors)

    def test_fixed_targets_link_swift_classes_for_both_architectures(self):
        for arch in ["arm64", "x86_64"]:
            with self.subTest(arch=arch):
                binary = self.binaries[f"fixed-{arch}"]
                architectures, errors = inspect_binary(binary)
                self.assertEqual(architectures, {arch})
                self.assertEqual(errors, [])
                symbols = self.command("xcrun", "nm", "-m", str(binary))
                definitions = [line for line in symbols.splitlines()
                               if "_OBJC_CLASS_$__TtC5swift11Application" in line
                               and "(undefined)" not in line]
                self.assertTrue(definitions, symbols)

    def test_universal_binary_checks_the_non_host_slice(self):
        binary = self.root / "Mpv-universal-broken"
        self.command("xcrun", "lipo", "-create", str(self.binaries["old-cross"]),
                     str(self.binaries[f"fixed-{platform.machine()}"]), "-output", str(binary))
        architectures, errors = inspect_binary(binary)
        self.assertEqual(architectures, {"arm64", "x86_64"})
        self.assertTrue(any("missing mpv Swift class" in e for e in errors), errors)

    def test_cli_requires_requested_architectures(self):
        result = subprocess.run(
            [sys.executable, str(VERIFIER), str(self.binaries["fixed-arm64"]),
             "--require-arch", "arm64", "--require-arch", "x86_64"],
            text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("required architecture missing: x86_64", result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
