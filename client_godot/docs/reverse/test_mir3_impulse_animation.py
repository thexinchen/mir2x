"""Reject drift in original motion branches, frame records and delay evidence."""
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
        self.assertEqual(len(result["checks"]), 43)
        self.assertEqual(result["motion"]["action9_direction"]["opposite_lookup"], [4, 5, 6, 7, 0, 1, 2, 3])
        self.assertEqual(result["current_comparison"]["current_enum"]["6"], "ACTION_SPACEMOVE")
        self.assertEqual(result["current_comparison"]["current_enum"]["9"], "ACTION_SPELL")
        self.assertIsNone(result["post_animation_delay"]["action_semantic_names"])
        self.assertEqual([w["delay_ms"] for w in result["post_animation_delay"]["writers"]], [300, 1000, 300, 1000])

    def test_feedback_registration_queue_and_namespace(self):
        feedback = exporter.extract(SAMPLE, ROOT)["feedback"]
        self.assertEqual({r["message"] for r in feedback["registrations"]}, {6, 7, 9, 37})
        self.assertEqual(feedback["queue_record_bytes"], 40)
        self.assertEqual(feedback["actor_fields"]["record_action"], 664)
        self.assertEqual(feedback["initial_command_translation"]["feedback6_7_9_37"], [0] * 4)
        self.assertIsNone(feedback["payload"]["existing_actor_queue_string"])

    def test_feedback_full_direction_bytes_and_local_clock(self):
        payload = struct.pack("<3I", 0x80000000, 0xFFFFFFFF, 12345)
        for message in [6, 7, 9, 37]:
            for high in range(256):
                for direction in range(8):
                    header = struct.pack("<I4H", 0xFFFFFFFF, message, 65535, 32768, high * 256 + direction)
                    result = exporter.decode_feedback(header, payload, 0xFFFFFFFF)
                    self.assertEqual(result["queue_record_u32"], [message, 65535, 32768, direction, 0x80000000, 0xFFFFFFFF, 0, 0, 0, 12345])
                    self.assertEqual(result["actor684_u8"], high)
                    self.assertEqual(result["stamp_local_impulse_clock"], message == 6)
                    self.assertTrue(result["local_actor"])
            remote = exporter.decode_feedback(struct.pack("<I4H", 123, message, 0, 0, 0xFFFF), payload, 456)
            self.assertFalse(remote["local_actor"])
            self.assertFalse(remote["stamp_local_impulse_clock"])
            self.assertEqual(remote["direction_raw_u8"], 255)  # Preserve raw invalid directions.

    def test_feedback_description_is_all_or_nothing_and_not_a_queue_string(self):
        header = struct.pack("<I4H", 1, 6, 2, 3, 4)
        prefix = struct.pack("<3I", 5, 6, 7)
        description = bytes(range(64))
        for length in [12, 13, 37, 75, 76, 77, 100]:
            payload = (prefix + description + bytes(24))[:length]
            result = exporter.decode_feedback(header, payload, 1)
            self.assertEqual(result["description_hex"], description.hex() if length >= 76 else None)
            self.assertEqual(result["queue_record_u32"][6:9], [0, 0, 0])
            self.assertEqual(result["queue_record_u32"][9], 7)

    def test_feedback_rejects_truncation_wrong_domain_and_invalid_local_uid(self):
        header = struct.pack("<I4H", 1, 6, 2, 3, 4)
        for bad_header, payload in [(header[:i], bytes(12)) for i in range(12)] + [(header + b"x", bytes(12))] + [(header, bytes(i)) for i in range(12)]:
            with self.assertRaisesRegex(ValueError, "header bytes"):
                exporter.decode_feedback(bad_header, payload, 1)
        for uid in [-1, 2**32, True, None, "1"]:
            with self.assertRaisesRegex(ValueError, "unsigned32"):
                exporter.decode_feedback(header, bytes(12), uid)
        for message in [0, 5, 3017, 65535]:
            with self.assertRaisesRegex(ValueError, "supports original messages"):
                exporter.decode_feedback(struct.pack("<I4H", 1, message, 0, 0, 0), bytes(12), 1)

    def test_feedback_rejects_misbound_registrations_and_pointers(self):
        source = json.loads((ROOT / "client_godot/docs/reverse/mir3-socket-registry.json").read_text(encoding="utf-8"))
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            registry = root / "client_godot/docs/reverse/mir3-socket-registry.json"
            registry.parent.mkdir(parents=True)
            for message in [6, 7, 9, 37]:
                for field, value in [("handler", "0x683875"), ("call", "0x67eac8"), ("registration_ecx", 14), ("register_function", "0x67ea1d")]:
                    changed = copy.deepcopy(source)
                    next(r for r in changed["records"] if r["message"] == message)[field] = value
                    registry.write_text(json.dumps(changed), encoding="utf-8")
                    with self.subTest(message=message, field=field), self.assertRaisesRegex(ValueError, "feedback registration"):
                        exporter.feedback_evidence(SAMPLE.read_bytes(), root)
        for address in [0x729D0C, 0x6DA738]:
            with self.subTest(address=hex(address)), self.changed_read(address):
                with self.assertRaisesRegex(ValueError, "unexpected"):
                    exporter.extract(SAMPLE, ROOT)

    def test_cli_decodes_feedback_fields_without_runtime_connection(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            header, payload, output = [path / name for name in ["header.bin", "payload.bin", "result.json"]]
            header.write_bytes(struct.pack("<I4H", 123, 9, 65535, 5, 0x8107))
            payload.write_bytes(struct.pack("<3I", 11, 22, 33))
            command = [sys.executable, str(Path(exporter.__file__)), "--sample", str(SAMPLE), "--root", str(ROOT), "--output", str(output)]
            completed = subprocess.run(command + ["--header", str(header), "--payload", str(payload), "--local-uid", "123"], capture_output=True, text=True)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            decoded = json.loads(output.read_text(encoding="utf-8"))["decoded_feedback"]
            self.assertEqual(decoded["queue_record_u32"], [9, 65535, 5, 7, 11, 22, 0, 0, 0, 33])
            self.assertFalse(decoded["stamp_local_impulse_clock"])
            completed = subprocess.run(command + ["--header", str(header)], capture_output=True, text=True)
            self.assertEqual(completed.returncode, 2)
            self.assertIn("must be supplied together", completed.stderr)

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
