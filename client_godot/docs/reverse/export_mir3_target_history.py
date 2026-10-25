"""Extract target-history evidence from the documented original Mir3 sample.

This reports the predicate and its inputs; it does not treat absent static bits
as denials, because server-supplied record byte 81 can independently enable it.
"""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import struct

EXPECTED_SAMPLE = "eef5bc3ce72b8db3449389f21c367f9795dacbf919480c606717a49b052d7021"


def read_va(image, address, length):
    pe = struct.unpack_from("<I", image, 0x3C)[0]
    if image[:2] != b"MZ" or image[pe:pe + 4] != b"PE\0\0":
        raise ValueError("expected PE image")
    sections = struct.unpack_from("<H", image, pe + 6)[0]
    optional_size = struct.unpack_from("<H", image, pe + 20)[0]
    optional = pe + 24
    if struct.unpack_from("<H", image, optional)[0] != 0x10B:
        raise ValueError("expected PE32")
    base = struct.unpack_from("<I", image, optional + 28)[0]
    rva = address - base
    for index in range(sections):
        entry = optional + optional_size + index * 40
        virtual_size, section_rva, raw_size, raw_offset = struct.unpack_from("<IIII", image, entry + 8)
        if section_rva <= rva and rva + length <= section_rva + raw_size:
            offset = raw_offset + rva - section_rva
            result = image[offset:offset + length]
            if len(result) == length:
                return result
    raise ValueError(f"address {address:#x} is not backed by file bytes")


def extract(sample_path, descriptions_path):
    sample = sample_path.read_bytes()
    sample_hash = hashlib.sha256(sample).hexdigest()
    if sample_hash != EXPECTED_SAMPLE:
        raise ValueError("extractor requires the documented unpacked Mir3 sample")
    bitmap = read_va(sample, 0x723EC8, 32)
    config_key = read_va(sample, 0x6A7F24, 8).decode("gbk")
    raw_descriptions = descriptions_path.read_bytes()
    text = base64.b64decode(b"".join(raw_descriptions.split()), validate=True).decode("gbk")
    config_rows = []
    for number, line in enumerate(text.splitlines(), 1):
        key, separator, value = line.strip().partition("=")
        if separator and key == config_key:
            # The sample uses TStrings.GetValue and SetCommaText, then positive
            # StrToIntDef values. This fixture contains plain decimal IDs only.
            fields = value.split(",")
            if any(not field.strip().isdecimal() for field in fields):
                raise ValueError("config syntax outside verified plain-decimal subset")
            config_rows.append({"line": number, "ids": [int(field) for field in fields if int(field) > 0]})
    if len(config_rows) != 1:
        raise ValueError("expected exactly one verified skill-lock config row")
    static_ids = [value for value in range(256) if bitmap[value // 8] & (1 << (value % 8))]
    return {
        "schema_version": 1,
        "sample_sha256": sample_hash,
        "descriptions_sha256": hashlib.sha256(raw_descriptions).hexdigest(),
        "predicate": {
            "function": "0x504c58", "null_record": False,
            "expression": "static_bitmap[base_id] OR record_byte_101 != 0 OR record_byte_81 == 1",
            "base_id_offset": 0, "base_id_width": 2,
            "bitmap_address": "0x723ec8", "bitmap_hex": bitmap.hex(),
            "bitmap_max_id": 255, "static_enabled_ids": static_ids,
            "negative_static_bit_is_final_denial": False,
        },
        "config": {
            "key": config_key, "key_address": "0x6a7f24",
            "source": "SkillDesc.txt (base64 to GBK)",
            "line": config_rows[0]["line"], "enabled_ids": config_rows[0]["ids"],
            "reader": "0x6a7d02", "comma_parser": "0x6faf24",
            "membership": "0x6fa518", "record_assignment": "0x6ab3a9",
        },
        "skill_record": {
            "allocation_bytes": 102, "loader": "0x6ab2e8",
            "handler": "0x6940dc", "registry_message": 97,
            "server_prefix_max_bytes": 83,
            "server_prefix_note": "stride from header dword 0, or payload_length/count; copy min(stride,83) into zeroed 102-byte record",
            "fields": [
                {"offset": 0, "bytes": 2, "role": "base skill ID; history predicate and list lookup"},
                {"offset": 2, "bytes": 31, "role": "Pascal short name, maximum 30 encoded bytes"},
                {"offset": 81, "bytes": 1, "role": "server-supplied target-mode byte; value 1 enables history"},
                {"offset": 82, "bytes": 1, "role": "zero selects main list; nonzero selects alternate list"},
                {"offset": 83, "bytes": 1, "role": "learned/shortcut-enabled flag"},
                {"offset": 84, "bytes": 2, "role": "dispatch skill ID; populated by learned update, separate from base ID"},
                {"offset": 86, "bytes": 1, "role": "low nibble from learned update byte 2"},
                {"offset": 87, "bytes": 1, "role": "high nibble from learned update byte 2"},
                {"offset": 88, "bytes": 1, "role": "shortcut byte from learned update byte 3"},
                {"offset": 89, "bytes": 4, "role": "training value from learned update bytes 7..10"},
                {"offset": 93, "bytes": 4, "role": "managed description string pointer; client-owned"},
                {"offset": 97, "bytes": 4, "role": "cooldown value; separate update path"},
                {"offset": 101, "bytes": 1, "role": "membership in configured skill-lock ID set"},
            ],
            "learned_update": {"function": "0x6aadd8", "bytes": 11},
        },
        "target_paths": {
            "explicit_mode": "0x67c954 clears selection then considers current target/history; record byte 81 value 2 selects self",
            "general_mode": "0x67cc08 may retain an existing selected member; history fallback still calls predicate",
            "history_requires": ["predicate true", "actor remains a current scene member", "actor not dead"],
            "current_corpse_exception": {"dispatch_id": 77, "addresses": ["0x67ca30", "0x67cd24"]},
        },
        "limits": [
            "Static IDs refer to original base IDs, not current mir2x/Godot resource IDs.",
            "No original server record payload was supplied; byte 81 values remain unknown for individual skills.",
            "Auxiliary King_Magic.csv cannot establish current sample record byte 81.",
            "General-mode current selection and historical fallback are distinct states; do not flatten them to one unconditional cache.",
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sample", type=Path, required=True)
    parser.add_argument("--descriptions", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = extract(args.sample, args.descriptions)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps({"static_ids": len(result["predicate"]["static_enabled_ids"]), "configured_ids": len(result["config"]["enabled_ids"]), "server_record_bytes": result["skill_record"]["server_prefix_max_bytes"]}))


if __name__ == "__main__":
    main()
