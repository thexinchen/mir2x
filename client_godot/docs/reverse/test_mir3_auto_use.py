"""Check automatic-protection evidence and reject changed thresholds or defaults."""
import argparse
from pathlib import Path
import tempfile
import struct
import unittest
from unittest.mock import patch

import export_mir3_auto_use as exporter


class AutoUseEvidenceTest(unittest.TestCase):
    def test_documented_sample(self):
        result = exporter.extract(SAMPLE)
        self.assertEqual(len(result["instruction_checks"]), 36)
        self.assertEqual(result["controller"]["timer_ms"], 50)
        self.assertEqual([r["settings"][1]["default"] for r in result["channels"]], [2500, 3500, 300, 100])
        self.assertTrue(all(r["settings"][0]["default"] == 0 for r in result["channels"]))
        self.assertEqual(result["book_selection"]["default"], -1)
        self.assertEqual(result["initial_medicine_tables"][2]["names"][:4], ["太阳水", "强效太阳水", "万年雪霜", "疗伤药"])
        self.assertEqual(result["gui_rules"]["escape_protection"]["options"][6]["name"], "小退")

    def test_gui_hp_order_preserves_nonmonotonic_original_priority(self):
        records = exporter.gui_rules(SAMPLE.read_bytes())["automatic_recovery"]["hp_table"]
        self.assertEqual(exporter.hp_candidate_order(29, records), [])
        self.assertEqual(exporter.hp_candidate_order(30, records), ["急救丸(小)", "金创药(小)"])
        self.assertEqual(exporter.hp_candidate_order(70, records)[:4], ["急救瓶", "急救丸(中)", "太阳水", "金创药(中)"])

    def test_gui_hp_weight_change_rejected(self):
        with self.changed_read(0x725E14, lambda code: code.__setitem__(0, 31)):
            with self.assertRaisesRegex(ValueError, "HP recovery weights"):
                exporter.extract(SAMPLE)

    def test_auto_back_cannot_silently_change_to_exit_dispatch(self):
        with self.changed_read(0x5FD11B, lambda code: code.__setitem__(1, code[1] ^ 1)):
            with self.assertRaisesRegex(ValueError, "instruction at 0x5fd11b"):
                exporter.extract(SAMPLE)

    def test_gui_exit_option_cannot_alias_return_scroll(self):
        original = exporter.read_va
        def altered(sample, address, length):
            if address == 0x72603C + 6 * 4:
                return original(sample, 0x72603C, length)
            return original(sample, address, length)
        with patch.object(exporter, "read_va", altered):
            with self.assertRaisesRegex(ValueError, "GUI name table"):
                exporter.extract(SAMPLE)

    def test_gui_hp_switch_cannot_silently_read_mp_switch(self):
        original = exporter.read_va
        def altered(sample, address, length):
            code = bytearray(original(sample, address, length))
            if address == 0x5F9F11:
                code[1:5] = original(sample, 0x5FA0BF, 10)[1:5]
            return bytes(code)
        with patch.object(exporter, "read_va", altered):
            with self.assertRaisesRegex(ValueError, "GUI config key"):
                exporter.extract(SAMPLE)

    def changed_read(self, address, change):
        original = exporter.read_va
        def altered(sample, va, length):
            code = bytearray(original(sample, va, length))
            if va == address:
                change(code)
            return bytes(code)
        return patch.object(exporter, "read_va", altered)

    def test_other_sample_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "other.exe"
            path.write_bytes(b"not original sample")
            with self.assertRaisesRegex(ValueError, "unpacked sample"):
                exporter.extract(path)

    def test_interval_equality_cannot_be_silently_excluded(self):
        # JB (elapsed < interval) cannot become JBE (elapsed <= interval).
        with self.changed_read(0x6C4CD7, lambda code: code.__setitem__(12, 0x86)):
            with self.assertRaisesRegex(ValueError, "instruction at 0x6c4cd7"):
                exporter.extract(SAMPLE)

    def test_threshold_cannot_silently_change_signed_comparison(self):
        with self.changed_read(0x6C4CE8, lambda code: code.__setitem__(10, 0x83)):
            with self.assertRaisesRegex(ValueError, "instruction at 0x6c4ce8"):
                exporter.extract(SAMPLE)

    def test_changed_default_interval_rejected(self):
        with self.changed_read(0x6C3A4E, lambda code: code.__setitem__(1, 0xC5)):
            with self.assertRaisesRegex(ValueError, "default/key/reader"):
                exporter.extract(SAMPLE)

    def test_changed_config_key_rejected(self):
        def change(code):
            code[3:7] = (0x6C3EC8).to_bytes(4, "little")
        with self.changed_read(0x6C3A36, change):
            with self.assertRaisesRegex(ValueError, "default/key/reader"):
                exporter.extract(SAMPLE)

    def test_medicine_record_overflow_rejected(self):
        with self.changed_read(0x727408, lambda code: code.__setitem__(0, 31)):
            with self.assertRaisesRegex(ValueError, "shortstring"):
                exporter.extract(SAMPLE)

    def test_medicine_padding_rejected(self):
        with self.changed_read(0x727500, lambda code: code.__setitem__(30, 1)):
            with self.assertRaisesRegex(ValueError, "shortstring"):
                exporter.extract(SAMPLE)

    def test_medicine_grade_order_cannot_silently_change(self):
        def change(code):
            code[:62] = code[31:62] + code[:31]
        with self.changed_read(0x727408, change):
            with self.assertRaisesRegex(ValueError, "medicine names"):
                exporter.extract(SAMPLE)

    def test_catalog_parentheses_do_not_invent_strong_medicine_mapping(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "names.m2xmeta"
            names = [(6, "金创药（小）"), (8, "金创药（大）"), (14, "太阳水")]
            data = bytearray(b"M2SP" + struct.pack("<II", 1, len(names)))
            for identity, name in names:
                raw = name.encode("utf-8")
                data += struct.pack("<IH", identity, len(raw)) + raw
            path.write_bytes(data)
            result = exporter.compare_items(path)
            rows = {row["original_name"]: row["candidates"] for row in result["rows"]}
            self.assertEqual(rows["金创药(小)"][0]["match"], "parenthesis_only")
            self.assertEqual(rows["太阳水"][0]["match"], "exact")
            self.assertEqual(rows["强效金创药"], [])
            path.write_bytes(data[:-1])
            with self.assertRaisesRegex(ValueError, "name record"):
                exporter.compare_items(path)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sample", required=True, type=Path)
    args = parser.parse_args()
    SAMPLE = args.sample
    unittest.main(argv=[__file__])
