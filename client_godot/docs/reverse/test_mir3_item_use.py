"""Reject stale sample, changed timing instructions and misbound reply evidence."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import export_mir3_item_use as exporter


class ItemUseEvidenceTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.registry = json.loads(REGISTRY.read_text(encoding="utf-8"))
        self.path = Path(self.temp.name) / "registry.json"

    def extract(self, registry=None, sample=None):
        self.path.write_text(json.dumps(self.registry if registry is None else registry),
                             encoding="utf-8")
        return exporter.extract(SAMPLE if sample is None else sample, self.path)

    def test_original_sample_and_registry_agree(self):
        result = self.extract()
        self.assertEqual(len(result["reply_registrations"]), 2)
        self.assertEqual(len(result["instruction_checks"]), 63)
        self.assertEqual(len(result["shortcut_rectangles"]), 10)
        self.assertEqual(len(result["special_shortcut_actions"]["records"]), 30)
        self.assertEqual(len(result["shortcut_drag_interface"]["methods"]), 5)
        self.assertEqual(result["shortcut_session_cleanup"]["count"], 10)

    def test_cleanup_cannot_silently_leave_the_tenth_reference(self):
        original = exporter.read_va
        def altered(image, address, length):
            code = bytearray(original(image, address, length))
            if address == 0x64F9A8:
                code[17] = 9
            return bytes(code)
        with patch.object(exporter, "read_va", altered):
            with self.assertRaisesRegex(ValueError, "instruction at 0x64f9a8"):
                self.extract()

    def test_interface_setter_cannot_alias_getter(self):
        original = exporter.read_va
        def altered(image, address, length):
            if address == 0x649FD7 + 6 * 4:
                return (0x649F4D).to_bytes(4, "little")
            return original(image, address, length)
        with patch.object(exporter, "read_va", altered):
            with self.assertRaisesRegex(ValueError, "interface target for set"):
                exporter.shortcut_interface(SAMPLE.read_bytes())

    def test_shortcut_control_alias_is_rejected(self):
        original = exporter.read_va
        def altered(image, address, length):
            code = bytearray(original(image, address, length))
            if address == 0x64D77A + 25:
                code[16:20] = (296).to_bytes(4, "little")
            return bytes(code)
        with patch.object(exporter, "read_va", altered):
            with self.assertRaisesRegex(ValueError, "shortcut control"):
                exporter.shortcut_rectangles(SAMPLE.read_bytes())

    def test_shortcut_rectangle_wrong_callee_is_rejected(self):
        original = exporter.read_va
        def altered(image, address, length):
            code = bytearray(original(image, address, length))
            if address == 0x64D77A:
                code[21] ^= 1
            return bytes(code)
        with patch.object(exporter, "read_va", altered):
            with self.assertRaisesRegex(ValueError, "rectangle target"):
                exporter.shortcut_rectangles(SAMPLE.read_bytes())

    def test_unrelated_sample_is_rejected(self):
        sample = Path(self.temp.name) / "other.exe"
        sample.write_bytes(b"not the documented original")
        with self.assertRaisesRegex(ValueError, "unpacked sample"):
            self.extract(sample=sample)

    def test_changed_pending_window_is_rejected_independently_of_hash(self):
        image = bytearray(SAMPLE.read_bytes())
        # Locate the complete verified instruction span, not an arbitrary800 literal.
        span = bytes.fromhex(next(raw for va, raw, _ in exporter.CHECKS if va == 0x6C4A99))
        self.assertEqual(image.count(span), 1)
        offset = image.index(span) + span.index(bytes.fromhex("20030000"))
        image[offset] ^= 1
        sample = Path(self.temp.name) / "changed.exe"
        sample.write_bytes(image)
        with patch.object(exporter, "EXPECTED_SAMPLE", hashlib.sha256(image).hexdigest()):
            with self.assertRaisesRegex(ValueError, "instruction at 0x6c4a99"):
                self.extract(sample=sample)

    def test_reply_handler_swap_is_rejected(self):
        registry = copy.deepcopy(self.registry)
        for row in registry["records"]:
            if row["call"] == "0x690e0f":
                row["handler"] = "0x6927b8"
        with self.assertRaisesRegex(ValueError, "registration for 635"):
            self.extract(registry)

    def test_missing_or_duplicate_registration_is_rejected(self):
        for count in [0, 2]:
            registry = copy.deepcopy(self.registry)
            row = next(r for r in registry["records"] if r["call"] == "0x690e24")
            registry["records"] = [r for r in registry["records"] if r["call"] != row["call"]]
            registry["records"].extend([row] * count)
            with self.subTest(count=count), self.assertRaisesRegex(ValueError, "registration for 636"):
                self.extract(registry)

    def test_other_registry_sample_is_rejected(self):
        self.registry["sample_sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "registry sample mismatch"):
            self.extract()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sample", required=True, type=Path)
    parser.add_argument("--registry", required=True, type=Path)
    args = parser.parse_args()
    SAMPLE, REGISTRY = args.sample, args.registry
    unittest.main(argv=[__file__])
