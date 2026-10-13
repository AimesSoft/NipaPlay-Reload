"""CLI data constraints: complete spill, redaction, bounded display, no repeat call."""
import contextlib
import io
import json
from pathlib import Path
import runpy
import tempfile
import unittest


class OutputConstraints(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="x50-output-")
        self.root = Path(self.temporary.name)
        self.cli = runpy.run_path("assets/next/harness/nipa")
        self.emit = self.cli["output_result"]
        self.emit.__globals__["__file__"] = str(self.root / "nipa")

    def tearDown(self):
        self.temporary.cleanup()

    def output(self, data, full=False):
        stream = io.StringIO()
        with contextlib.redirect_stdout(stream):
            self.emit(data, full)
        return stream.getvalue()

    def test_complete_redacted_record_and_bounded_preview(self):
        source = {"status": "completed", "result": {"rows": [
            {"id": i, "title": "字幕" * 200, "cookie": "synthetic-private",
             "url": "https://example.test/media?token=synthetic-private"}
            for i in range(300)]}}
        safe = self.cli["redact"](source, ["synthetic-private"])
        displayed = self.output(safe)
        self.assertLessEqual(len(displayed.encode()), 24577)
        summary = json.loads(displayed)
        record = Path(summary["file"])
        self.assertEqual(json.loads(record.read_text()), safe)
        self.assertNotIn("synthetic-private", record.read_text())
        self.assertEqual(record.stat().st_mode & 0o777, 0o600)
        self.assertEqual(summary["bytes"], record.stat().st_size)
        self.assertEqual(summary["status"], "completed")
        self.assertEqual(len(list((self.root / "records").iterdir())), 1)

    def test_full_output_retains_result_without_spilling(self):
        source = {"rows": ["a" * 50000]}
        self.assertEqual(json.loads(self.output(source, True)), source)
        self.assertFalse((self.root / "records").exists())

    def test_broad_nested_objects_still_fit_display_budget(self):
        source = {"key" + str(i): {"nested" + str(j): ["字" * 1000] * 10
                                  for j in range(30)} for i in range(30)}
        self.assertLessEqual(len(self.output(source).encode()), 24577)
        source = 'value'
        for depth in range(5):
            source = {'长键' * 100 + str(i): source for i in range(8)}
        self.assertLessEqual(len(self.output(source).encode()), 24577)

    def test_instruction_sizes_use_utf8_bytes_and_only_resident_memory(self):
        (self.root / 'AGENTS.md').write_text('字幕')
        memory = self.root / 'memory'
        memory.mkdir()
        (memory / 'preferences.md').write_text('偏好')
        (memory / 'MEMORY.md').write_text('索引')
        (memory / 'environment.md').write_text('按需读取' * 100)
        sizes = self.cli['instruction_sizes']()
        self.assertEqual(sizes['AGENTS.md']['bytes'], 6)
        self.assertEqual(sizes['AGENTS.md']['limitBytes'], 32768)
        self.assertEqual(sizes['memory']['residentBytes'], 12)


if __name__ == "__main__":
    unittest.main()
