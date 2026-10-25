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


def lock_target_predicate(code, base_id):
    """Evaluate this sample's EAX-only predicate; reject unknown instructions.

    This is a bounded decoder for 504C88, not a general emulator. The only
    memory read is the record's uint16 base ID. No original code is executed.
    """
    eax = 0 if base_id is None else 1  # abstract record pointer
    pc = 0
    zf = sf = of = cf = False
    mask = 0xFFFFFFFF
    for _step in range(128):
        op = code[pc:pc + 3]
        if op[:2] in [b"\x85\xc0", b"\x33\xc0"]:
            if op[:2] == b"\x33\xc0":
                eax = 0
            zf, sf, of, cf = eax == 0, bool(eax & 0x80000000), False, False
            pc += 2
        elif op == b"\x0f\xb7\x00":
            if base_id is None:
                raise ValueError("null record unexpectedly dereferenced")
            eax = base_id
            pc += 3
        elif op[:2] == b"\xb0\x01":
            eax = (eax & 0xFFFFFF00) | 1
            pc += 2
        elif op[0] == 0xC3:
            return bool(eax & 0xFF)
        elif op[0] in [0xE9, 0xEB]:
            width = 4 if op[0] == 0xE9 else 1
            delta = int.from_bytes(code[pc + 1:pc + 1 + width], "little", signed=True)
            pc += 1 + width + delta
        elif op[0] in [0x72, 0x74, 0x75, 0x7D, 0x7F] or op[:2] in [b"\x0f\x82", b"\x0f\x84", b"\x0f\x85", b"\x0f\x8d", b"\x0f\x8f"]:
            near = op[0] == 0x0F
            condition = op[1] - 0x10 if near else op[0]
            take = {0x72: cf, 0x74: zf, 0x75: not zf, 0x7D: sf == of, 0x7F: not zf and sf == of}[condition]
            width, start = (4, 2) if near else (1, 1)
            delta = int.from_bytes(code[pc + start:pc + start + width], "little", signed=True)
            pc += start + width + (delta if take else 0)
        else:
            size = 1
            save_cf = cf
            if op[0] == 0x48:  # dec eax (preserves carry)
                operation, rhs = "sub", 1
            elif op[0] in [0x3D, 0x2D]:
                operation = "cmp" if op[0] == 0x3D else "sub"
                rhs = struct.unpack_from("<I", code, pc + 1)[0]
                size = 5
            elif op[:2] in [b"\x83\xf8", b"\x83\xe8", b"\x83\xc0"]:
                operation = {0xF8: "cmp", 0xE8: "sub", 0xC0: "add"}[op[1]]
                rhs = int.from_bytes(op[2:3], "little", signed=True) & mask
                size = 3
            else:
                raise ValueError(f"unsupported lock predicate opcode at {0x504C88 + pc:#x}")
            lhs = eax
            result = (lhs + rhs if operation == "add" else lhs - rhs) & mask
            zf, sf = result == 0, bool(result & 0x80000000)
            if operation == "add":
                cf = lhs + rhs > mask
                of = bool((~(lhs ^ rhs) & (lhs ^ result)) & 0x80000000)
            else:
                cf = lhs < rhs
                of = bool(((lhs ^ rhs) & (lhs ^ result)) & 0x80000000)
            if op[0] == 0x48:
                cf = save_cf
            if operation != "cmp":
                eax = result
            pc += size
        if not 0 <= pc < len(code):
            raise ValueError("lock predicate escaped its function")
    raise ValueError("lock predicate exceeded its instruction budget")


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
    lock_code = read_va(sample, 0x504C88, 0x165)
    lock_ids = [value for value in range(65536) if lock_target_predicate(lock_code, value)]
    if lock_target_predicate(lock_code, None):
        raise ValueError("unexpected lock predicate null handling")
    return {
        "schema_version": 2,
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
        "explicit_lock_target": {
            "pointer_global": "0x729d20", "distinct_from_current": "0x72999c",
            "distinct_from_history": "0x729ce4",
            "permission_function": "0x504c88", "permission_code_sha256": hashlib.sha256(lock_code).hexdigest(),
            "permission_input": "record uint16 base ID at offset 0; all 65536 possible values evaluated",
            "null_record": False, "enabled_base_ids": lock_ids,
            "permission_vs_history": "Separate predicate; no record-byte81 or byte101 override in this function",
            "toggle_function": "0x660be8", "toggle_input_keys": [192, 229],
            "additional_key_state": "GetAsyncKeyState(192) != 0",
            "toggle_requires": "0x61bb30 setting enabled; current hover actor is live when adopting it",
            "toggle_behavior": "different non-null live hover replaces locked actor; same actor or null hover clears lock",
            "different_dead_hover": "leave the previous lock unchanged",
            "setting_getter": "0x61bb30", "setting_control_offset": 372, "checked_byte_offset": 204,
            "setting_caption_va": "0x61b08c", "setting_caption": read_va(sample, 0x61B08C, 32).split(b"\0", 1)[0].decode("gbk"),
            "setting_default": False, "default_assignment": "0x61b27c",
            "target_override": "0x67c98a selects general resolver for eligible skill+enabled setting; 0x67ccb9 then adopts locked actor only if current scene member and live",
            "status_display": "0x672413 checks setting, live locked actor and membership; 0x672444 appends its name",
            "limit": "Original base IDs are not current resource IDs; disabled/nonmember skills must not acquire this override from history permission alone.",
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
