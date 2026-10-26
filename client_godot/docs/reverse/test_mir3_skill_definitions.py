"""Validate original definition fields, variable strides and unsafe-copy rejection."""
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

import export_mir3_skill_definitions as exporter


def header(stride, count, message=97):
    return struct.pack("<i4H", stride, message, 0, 0, count)


def definition(base=27, delay=0xFFFFFF00, mp=65535, mode=2, pool=0):
    raw = bytearray(83)
    struct.pack_into("<H", raw, 0, base)
    struct.pack_into("<IH", raw, 64, delay, mp)
    raw[72], raw[76], raw[81], raw[82] = 8, 1, mode, pool
    return bytes(raw)


class SkillDefinitionsTest(unittest.TestCase):
    def test_source_and_definition_registration(self):
        result = exporter.extract(SAMPLE, REGISTRY)
        self.assertEqual(len(result["instruction_checks"]), 14)
        self.assertEqual(result["registration"]["message"], 97)
        self.assertEqual(result["fields"]["manual_mp_threshold_u16"], 68)
        self.assertEqual(result["copy"]["runtime_record_bytes"], 102)

    def test_each_source_instruction_is_checked(self):
        original = exporter.read_va
        for address, _, _ in exporter.CHECKS:
            def changed(sample, va, size):
                value = bytearray(original(sample, va, size))
                if va == address: value[0] ^= 1
                return bytes(value)
            with self.subTest(address=hex(address)), patch.object(exporter, "read_va", changed):
                with self.assertRaisesRegex(ValueError, "instruction at " + hex(address)):
                    exporter.extract(SAMPLE, REGISTRY)

    def test_fields_unsigned_values_and_delay_wrap(self):
        for delay in [0, 1, 1200, 0xFFFFFFFF - 1200, 0xFFFFFFFF]:
            row = exporter.decode_definitions(header(83, 1), definition(delay=delay))["records_in_wire_order"][0]
            self.assertEqual(row["base_id"], 27)
            self.assertEqual(row["manual_mp_threshold_u16"], 65535)
            self.assertEqual(row["cast_delay_u32"], delay)
            self.assertEqual(row["shared_cast_delay_plus1200_u32"], (delay + 1200) & 0xFFFFFFFF)
            self.assertEqual((row["raw_byte72"], row["command_branch_byte76"], row["target_mode_byte81"]), (8, 1, 2))

    def test_short_prefix_is_zero_padded_at_every_boundary(self):
        raw = definition()
        for stride in range(1, 84):
            row = exporter.decode_definitions(header(stride, 1), raw[:stride])["records_in_wire_order"][0]
            prefix = raw[:stride] + bytes(83 - stride)
            self.assertEqual(row["definition_prefix83_hex"], prefix.hex())
            self.assertEqual(row["cast_delay_u32"], struct.unpack_from("<I", prefix, 64)[0])
            self.assertEqual(row["manual_mp_threshold_u16"], struct.unpack_from("<H", prefix, 68)[0])
        row = exporter.decode_definitions(header(0, 1), b"")["records_in_wire_order"][0]
        self.assertEqual(row["definition_prefix83_hex"], bytes(83).hex())

    def test_long_stride_uses_real_offsets_and_copies_only83(self):
        payload = definition(base=27) + bytes([255]) * 17 + definition(base=36, mp=9, pool=2)
        result = exporter.decode_definitions(header(100, 2), payload)
        self.assertEqual(result["last_copy_end"], 183)
        self.assertEqual([r["payload_offset"] for r in result["records_in_wire_order"]], [0, 100])
        self.assertEqual([r["base_id"] for r in result["records_in_wire_order"]], [27, 36])
        self.assertEqual(result["records_in_wire_order"][1]["manual_mp_threshold_u16"], 9)
        self.assertEqual(result["records_in_wire_order"][1]["pool"], "alternate")
        self.assertEqual(exporter.decode_definitions(header(100, 2), payload + bytes(17))["last_copy_end"], 183)

    def test_coarse_guard_does_not_hide_truncated_last_prefix(self):
        # Original min(stride,83)*count ==166 passes, but the second copy
        # at offset100 needs bytes through183. Refuse the unsafe overread.
        with self.assertRaisesRegex(ValueError, "last copied prefix"):
            exporter.decode_definitions(header(100, 2), bytes(166))
        for length in [0, 1, 82, 165]:
            with self.assertRaisesRegex(ValueError, "length guard"):
                exporter.decode_definitions(header(83, 2), bytes(length))

    def test_implicit_stride_truncates_remainder_and_preserves_duplicates(self):
        result = exporter.decode_definitions(header(0, 2), definition(base=36) + definition(base=36, pool=1) + b"x")
        self.assertEqual((result["effective_stride"], result["last_copy_end"]), (83, 166))
        rows = result["records_in_wire_order"]
        self.assertEqual([r["base_id"] for r in rows], [36, 36])
        self.assertEqual([r["pool"] for r in rows], ["main", "alternate"])

    def test_pool_and_mode_bytes_are_not_reduced_to_booleans(self):
        for value in range(256):
            row = exporter.decode_definitions(header(83, 1), definition(mode=value, pool=value))["records_in_wire_order"][0]
            self.assertEqual((row["target_mode_byte81"], row["pool_selector_byte82"]), (value, value))
            self.assertEqual(row["pool"], "alternate" if value else "main")
            self.assertEqual(row["byte82_equals1_callback"], value == 1)

    def test_bad_headers_signed_strides_and_zero_count(self):
        for size in list(range(12)) + [13]:
            with self.assertRaisesRegex(ValueError, "header bytes"):
                exporter.decode_definitions(bytes(size), bytes(83))
        with self.assertRaisesRegex(ValueError, "message97"):
            exporter.decode_definitions(header(83, 1, 98), bytes(83))
        with self.assertRaisesRegex(ValueError, "negative signed stride"):
            exporter.decode_definitions(header(-1, 1), bytes(83))
        with self.assertRaisesRegex(ValueError, "zero-count division"):
            exporter.decode_definitions(header(0, 0), b"")
        self.assertEqual(exporter.decode_definitions(header(83, 0), b"extra")["records_in_wire_order"], [])

    def test_registry_and_sample_mismatch_are_rejected(self):
        source = json.loads(REGISTRY.read_text(encoding="utf-8"))
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "registry.json"
            for key, value in [("handler", "0x6940dd"), ("call", "0x691030"), ("registration_ecx", 14), ("register_function", "0x67ea1c")]:
                changed = copy.deepcopy(source)
                next(r for r in changed["records"] if r["message"] == 97)[key] = value
                path.write_text(json.dumps(changed), encoding="utf-8")
                with self.subTest(key=key), self.assertRaisesRegex(ValueError, "registration"):
                    exporter.extract(SAMPLE, path)
            sample = Path(directory) / "other.exe"
            sample.write_bytes(b"MZ")
            with self.assertRaisesRegex(ValueError, "documented unpacked"):
                exporter.extract(sample, REGISTRY)

    def test_cli_reads_original_field_files_and_rejects_missing_pair(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            head, payload, output = [path / name for name in ["header.bin", "payload.bin", "output.json"]]
            head.write_bytes(header(83, 1))
            payload.write_bytes(definition())
            command = [sys.executable, exporter.__file__, "--sample", str(SAMPLE), "--registry", str(REGISTRY), "--output", str(output)]
            completed = subprocess.run(command + ["--header", str(head), "--payload", str(payload)], capture_output=True, text=True)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            row = json.loads(output.read_text(encoding="utf-8"))["decoded_definitions"]["records_in_wire_order"][0]
            self.assertEqual(row["manual_mp_threshold_u16"], 65535)
            completed = subprocess.run(command + ["--header", str(head)], capture_output=True, text=True)
            self.assertEqual(completed.returncode, 2)
            self.assertIn("must be supplied together", completed.stderr)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sample", required=True, type=Path)
    parser.add_argument("--registry", required=True, type=Path)
    args = parser.parse_args()
    SAMPLE, REGISTRY = args.sample, args.registry
    unittest.main(argv=[__file__])
