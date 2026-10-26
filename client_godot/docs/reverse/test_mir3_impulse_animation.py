"""Reject drift in original motion branches, frame records and delay evidence."""
import argparse
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import export_mir3_impulse_animation as exporter


class ImpulseAnimationEvidenceTest(unittest.TestCase):
    def changed_read(self, address, index=0):
        original = exporter.read_va

        def read(sample, va, size):
            value = bytearray(original(sample, va, size))
            if va == address:
                value[index] ^= 1
            return bytes(value)

        return patch.object(exporter, "read_va", read)

    def test_documented_sample_and_comparison(self):
        result = exporter.extract(SAMPLE, ROOT)
        self.assertEqual(len(result["checks"]), 24)
        self.assertEqual(result["motion"]["action9_direction"]["opposite_lookup"], [4, 5, 6, 7, 0, 1, 2, 3])
        self.assertEqual(result["current_comparison"]["current_enum"]["6"], "ACTION_SPACEMOVE")
        self.assertEqual(result["current_comparison"]["current_enum"]["9"], "ACTION_SPELL")
        self.assertIsNone(result["post_animation_delay"]["action_semantic_names"])
        self.assertEqual([w["delay_ms"] for w in result["post_animation_delay"]["writers"]], [300, 1000, 300, 1000])

    def test_frame_records_distinguish_reverse_walk_and_forward(self):
        records, _, _ = exporter.checked_records(SAMPLE.read_bytes())
        by_va = {r["va"]: r for r in records}
        self.assertEqual([by_va[a]["base_frame"] for a in ["0x7278a8", "0x7278c0", "0x727980", "0x727a0c", "0x727a24", "0x727ae4", "0x727c6c"]], [80, 240, 1520, 1600, 1680, 2080, 1760])
        self.assertEqual([by_va[a]["frame_interval_ms"] for a in ["0x7278a8", "0x7278c0", "0x727a0c", "0x727a24"]], [200, 100, 200, 100])
        self.assertTrue(all(r["frame_count"] == 6 and r["direction_gap"] == 4 for r in records))

    def test_each_instruction_change_is_rejected(self):
        for address, _, label in exporter.CHECKS:
            with self.subTest(label=label), self.changed_read(address):
                with self.assertRaisesRegex(ValueError, "unexpected"):
                    exporter.checked_records(SAMPLE.read_bytes())

    def test_switch_action_namespace_cannot_silently_change(self):
        for action in [6, 7, 9, 11, 37]:
            with self.subTest(action=action), self.changed_read(0x6DE736, 4 * (action - 6)):
                with self.assertRaisesRegex(ValueError, "frame branch"):
                    exporter.checked_records(SAMPLE.read_bytes())

    def test_record_count_gap_interval_and_opaque_field_are_checked(self):
        for address in [0x7278A8, 0x7278C0, 0x727980, 0x727A0C, 0x727A24, 0x727AE4]:
            for index in [4, 5, 6, 8]:
                with self.subTest(address=hex(address), index=index), self.changed_read(address, index):
                    with self.assertRaisesRegex(ValueError, "frame record layout"):
                        exporter.checked_records(SAMPLE.read_bytes())

    def test_special_frame_record_is_checked(self):
        for index in [0, 4, 5, 6, 8]:
            with self.subTest(index=index), self.changed_read(0x727C6C, index):
                with self.assertRaisesRegex(ValueError, "special6/7"):
                    exporter.checked_records(SAMPLE.read_bytes())

    def test_opposite_direction_result_cannot_become_identity(self):
        with self.changed_read(0x6FED4A, 1):
            with self.assertRaisesRegex(ValueError, "opposite direction table"):
                exporter.checked_records(SAMPLE.read_bytes())

    def test_other_sample_is_rejected_before_address_reads(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "other.exe"
            path.write_bytes(b"MZ")
            with self.assertRaisesRegex(ValueError, "documented unpacked"):
                exporter.extract(path, ROOT)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sample", required=True, type=Path)
    args = parser.parse_args()
    SAMPLE = args.sample
    ROOT = Path(__file__).resolve().parents[3]
    unittest.main(argv=[__file__])
