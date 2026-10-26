"""Check original description provenance and bounded offline payload decoding."""
import argparse
import copy
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import export_mir3_actor_description as exporter


class ActorDescriptionTest(unittest.TestCase):
    def test_documented_source(self):
        result = exporter.extract(SAMPLE, REGISTRY)
        self.assertEqual(len(result["instruction_checks"]), 15)
        self.assertEqual([r["message"] for r in result["registrations"]], [41, 50, 1500])
        self.assertEqual(result["description"]["actor_offset"] + result["description"]["manual_use_flag"]["description_offset"], 53)
        self.assertIsNone(result["description"]["manual_use_flag"]["semantic_name"])

    def test_each_source_instruction_change_is_rejected(self):
        original = exporter.read_va
        for changed, _, _ in exporter.CHECKS:
            def altered(image, address, size):
                data = bytearray(original(image, address, size))
                if address == changed: data[0] ^= 1
                return bytes(data)
            with self.subTest(address=hex(changed)), patch.object(exporter, "read_va", altered):
                with self.assertRaisesRegex(ValueError, "unexpected"):
                    exporter.extract(SAMPLE, REGISTRY)

    def test_registration_cannot_alias_a_different_handler(self):
        registry = json.loads(REGISTRY.read_text(encoding="utf-8"))
        for message in [41, 50, 1500]:
            for key, value in [("handler", "0x69404c"), ("call", "0x67f09c"), ("registration_ecx", 0), ("register_function", "0x690d74")]:
                changed = copy.deepcopy(registry)
                next(r for r in changed["records"] if r["message"] == message)[key] = value
                with self.subTest(message=message, key=key), tempfile.TemporaryDirectory() as directory:
                    path = Path(directory) / "registry.json"
                    path.write_text(json.dumps(changed), encoding="utf-8")
                    with self.assertRaisesRegex(ValueError, "description handler"):
                        exporter.extract(SAMPLE, path)

    def test_all_flag_bytes_select_only_mask8_for_all_three_sources(self):
        for flags in range(256):
            description = bytearray(range(64))
            description[13] = flags
            message41 = struct.pack("<I", 1234) + bytes(8) + description
            message50 = bytearray(130)
            message50[57:77] = description[:20]
            snapshot = bytes(24) + description
            results = [exporter.decode_message41(message41), exporter.decode_message50(message50), exporter.decode_snapshot1500(snapshot, 88)]
            for result in results:
                self.assertEqual(result["actor_byte53"], flags)
                self.assertEqual(result["manual_use_guard_set"], bool(flags & 8))

    def test_message41_preserves_full_description_and_shape(self):
        result = exporter.decode_message41(struct.pack("<I", 0xAABBCCDD) + bytes(8) + bytes(range(64)) + b"ignored tail")
        self.assertEqual(result["description_hex"], bytes(range(64)).hex())
        self.assertEqual(result["actor128_u32"], 0xAABBCCDD)

    def test_initial_message_copies_only_twenty_bytes_then_zeros(self):
        payload = bytes([255]) * 130
        result = exporter.decode_message50(payload)
        self.assertEqual(bytes.fromhex(result["description_hex"]), bytes([255]) * 20 + bytes(44))
        self.assertFalse(exporter.decode_message50(bytes(130))["manual_use_guard_set"])

    def test_snapshot_padding_and_flag_boundary(self):
        field = bytes([255]) * 100
        for declared in [0, 1, 24, 37, 38, 87, 88, 100]:
            with self.subTest(declared=declared):
                result = exporter.decode_snapshot1500(field, declared)
                expected = field[:min(declared, 88)].ljust(88, b"\0")[24:88]
                self.assertEqual(result["description_hex"], expected.hex())
                self.assertEqual(result["consumed_field_bytes"], declared)
                self.assertEqual(result["manual_use_guard_set"], declared >= 38)

    def test_truncation_and_impossible_header_lengths_are_rejected(self):
        for decoder, size in [(exporter.decode_message41, 76), (exporter.decode_message50, 130), (exporter.decode_description, 64)]:
            for length in [0, size - 1]:
                with self.subTest(decoder=decoder.__name__, length=length), self.assertRaises(ValueError): decoder(bytes(length))
        for field, declared in [(bytes(87), 88), (bytes(100), 101), (b"", -1), (b"", 65536)]:
            with self.subTest(declared=declared), self.assertRaises(ValueError): exporter.decode_snapshot1500(field, declared)

    def test_unrelated_sample_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "sample.exe"
            path.write_bytes(b"MZ")
            with self.assertRaisesRegex(ValueError, "documented unpacked"):
                exporter.extract(path, REGISTRY)

    def test_cli_decodes_an_explicit_payload_file(self):
        with tempfile.TemporaryDirectory() as directory:
            payload = Path(directory) / "payload.bin"
            output = Path(directory) / "decoded.json"
            data = bytearray(76)
            data[25] = 8
            payload.write_bytes(data)
            result = subprocess.run([sys.executable, exporter.__file__, "--sample", str(SAMPLE), "--registry", str(REGISTRY), "--output", str(output), "--payload", str(payload), "--payload-kind", "message41"], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(json.loads(output.read_text(encoding="utf-8"))["decoded_payload"]["manual_use_guard_set"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sample", required=True, type=Path)
    parser.add_argument("--registry", required=True, type=Path)
    args = parser.parse_args()
    SAMPLE, REGISTRY = args.sample, args.registry
    unittest.main(argv=[__file__])
