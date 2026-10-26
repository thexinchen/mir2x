"""Validate source routing and unframed legacy command bytes, never live send."""
import argparse
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch

import export_mir3_rush_command as exporter


class RushCommandTest(unittest.TestCase):
    def test_documented_sample(self):
        result = exporter.extract(SAMPLE)
        self.assertEqual(len(result["instruction_checks"]), 17)
        self.assertEqual(result["identity"]["original_dispatch_id"], 27)
        self.assertEqual(result["identity"]["current_mir2x_id"], 39)
        self.assertEqual(result["request"]["original_command"], 3017)
        self.assertIn("local server message6", result["timing"]["rush_clock"])

    def test_each_source_instruction_is_checked(self):
        original = exporter.read_va
        for address, _, _ in exporter.CHECKS:
            def altered(sample, va, length):
                data = bytearray(original(sample, va, length))
                if va == address: data[0] ^= 1
                return bytes(data)
            with self.subTest(address=hex(address)), patch.object(exporter, "read_va", altered):
                with self.assertRaisesRegex(ValueError, "unexpected instruction"):
                    exporter.extract(SAMPLE)

    def test_legacy_header_directions_and_zero_payload(self):
        for direction in range(8):
            packet = exporter.encode_unframed_command(direction)
            self.assertEqual(len(packet), 16)
            self.assertEqual(packet[:6], bytes.fromhex("00000000c90b"))
            self.assertEqual(struct.unpack_from("<H", packet, 6)[0], direction)
            self.assertEqual(packet[8:], bytes.fromhex("00001b0000000000"))
        for invalid in [-1, 8, 39, 3017, True, 1.5, "2"]:
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                exporter.encode_unframed_command(invalid)

    def test_changed_sample_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "different.exe"
            path.write_bytes(b"not documented sample")
            with self.assertRaisesRegex(ValueError, "unpacked sample"):
                exporter.extract(path)

    def test_identity_mismatch_is_not_silently_remapped(self):
        identity = json.loads(Path(exporter.__file__).with_name("mir3-skill-identity.json").read_bytes())
        for row in identity["skills"]:
            if row["current_name"] == "野蛮冲撞": row["original_resource_id"] = 39
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "identity.json"
            path.write_text(json.dumps(identity), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "rush identity"):
                exporter.extract(SAMPLE, path)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sample", required=True, type=Path)
    args = parser.parse_args()
    SAMPLE = args.sample
    unittest.main(argv=[__file__])
