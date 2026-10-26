"""Extract original automatic protection settings and controller evidence.

This is a verified source specification, not an automatic consumption feature.
Original slot numbers and item names are kept in their original domains.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct

from export_mir3_target_history import EXPECTED_SAMPLE, read_va


CHECKS = [
    (0x6C33D0, "404a6c00", "helper virtual method4 is automatic protection timer"),
    (0x6C3655, "8b4004508b45f08b4008e8a092d7ff", "install virtual method4 on timer object8"),
    (0x6C366A, "ba32000000e88092d7ff", "automatic protection timer period50ms"),
    (0x6C4A55, "8b030fb650118b03e8fe010000", "dispatch current channel from helper byte17"),
    (0x6C4A78, "8078110374d7", "after unsuccessful channel2 immediately evaluate channel3"),
    (0x6C4A21, "80781103750c8b45088b40fcc6401100", "advance channel3 back to0"),
    (0x6C4A39, "fe4011", "advance other channels by1"),
    (0x6C4CCA, "837804000f86ad010000", "disabled zero interval does not trigger"),
    (0x6C4CD7, "8bd62b500c8b45f83b50040f8299010000", "unsigned elapsed below interval skips; equality passes"),
    (0x6C4CE8, "8b47158b55f83b42080f8d8a010000", "HP scalar comparison is signed and strictly below threshold"),
    (0x6C4CF7, "6a0033c933d28bc3e8c4030000", "HP selects channel0 grade0 mode0"),
    (0x6C4D0A, "89700c", "HP attempt updates last tick regardless of selection success"),
    (0x6C4D4C, "8b47198b55f43b42080f8d26010000", "MP scalar comparison is strictly below threshold"),
    (0x6C4D5B, "6a00b10133d28bc3e860030000", "MP selects channel1 grade0 mode0"),
    (0x6C4E65, "837b64ff7416", "book protection additionally requires selection other than minus1"),
    (0x6C4EEA, "bb06000000", "inventory search starts original slot6"),
    (0x6C4F82, "4383fb340f8563ffffff", "inventory search stops before original slot52"),
    (0x6C4FF2, "33ff", "belt search starts original slot0"),
    (0x6C506A, "4783ff067584", "belt search stops before original slot6"),
    (0x6C52E0, "e8d3fcffff", "same grade falls back to belt lookup"),
    (0x6C52FE, "6a008b55f8420fb64df78bc6e8b9fdffff", "missing grade increments index and recurses with mode0"),
    (0x6C4A99, "8b15689d72002b023d20030000720e", "automatic use shares pending item with800ms retry window"),
    (0x683469, "8983690100008b460489836d010000", "health notification copies raw HP and MP into actor361 and365"),
    (0x5FD081, "2b967403000081fae80300000f828e010000", "separate GUI protection controller has1000ms unsigned check"),
    (0x5FD0A2, "8bb869010000a1c09372008b003bb8710100007d69", "GUI controller distinguishes current HP361 from maximum HP369"),
    (0x5FD13C, "3bbe2c0300007d0d8d8628030000e8b50e0000", "GUI protection compares raw HP against its own threshold before action"),
]

# Each row is (channel, object offset, enable/interval/threshold push addresses).
CHANNELS = [
    ("HP", 104, [(0x6C3A36, "RenewHPIsAuto", 0), (0x6C3A4E, "RenewHPTime", 2500), (0x6C3A6A, "RenewHPPercent", 10)]),
    ("MP", 120, [(0x6C3A92, "RenewMPIsAuto", 0), (0x6C3AAA, "RenewMPTime", 3500), (0x6C3AC6, "RenewMPPercent", 10)]),
    ("special", 136, [(0x6C3AF0, "RenewSpecialIsAuto", 0), (0x6C3B08, "RenewSpecialTime", 300), (0x6C3B24, "RenewSpecialPercent", 10)]),
    ("book", 152, [(0x6C3B4E, "RenewBookIsAuto", 0), (0x6C3B66, "RenewBookTime", 100), (0x6C3B7F, "RenewBookPercent", 10)]),
]
TABLES = [
    (0x727408, ["金创药(小)", "金创药(中)", "强效金创药", "", "", "", "", ""]),
    (0x727500, ["魔法药(小)", "魔法药(中)", "强效魔法药", "", "", "", "", ""]),
    (0x7275F8, ["太阳水", "强效太阳水", "万年雪霜", "疗伤药", "", "", "", ""]),
]


def ansi_string(sample, address):
    length = struct.unpack("<I", read_va(sample, address - 4, 4))[0]
    if length > 64:
        raise ValueError("unexpected configuration key length")
    return read_va(sample, address, length).decode("ascii")


def config_default(sample, address, expected_key, expected_default):
    code = read_va(sample, address, 32)
    if code[0] == 0x6A:
        value, size = struct.unpack("<b", code[1:2])[0], 2
    elif code[0] == 0x68:
        value, size = struct.unpack("<i", code[1:5])[0], 5
    else:
        raise ValueError(f"unexpected config default push at {address:#x}")
    if code[size] != 0xB9 or code[size + 5] != 0xBA:
        raise ValueError(f"unexpected config key load at {address:#x}")
    key = ansi_string(sample, struct.unpack_from("<I", code, size + 1)[0])
    section = ansi_string(sample, struct.unpack_from("<I", code, size + 6)[0])
    reader = (bytes.fromhex("8bc38b18ff5308") if key == "RenewBookNowBookIndex"
              else bytes.fromhex("8bc38b38ff57") + bytes([16 if key.endswith("IsAuto") else 8]))
    if key != expected_key or section != "Protect" or value != expected_default or code[size + 10:size + 17] != reader:
        raise ValueError(f"unexpected config default/key/reader at {address:#x}")
    return {"key": key, "section": section, "default": value, "va": hex(address),
            "hex": code[:size + 17].hex()}


def medicine_tables(sample):
    result = []
    for address, expected in TABLES:
        data = read_va(sample, address, 248)
        names = []
        for index in range(8):
            record = data[index * 31:(index + 1) * 31]
            length = record[0]
            if length > 30 or any(record[1 + length:]):
                raise ValueError(f"invalid medicine shortstring at {address:#x} index{index}")
            names.append(record[1:1 + length].decode("gb18030"))
        if names != expected:
            raise ValueError(f"unexpected initial medicine names at {address:#x}")
        result.append({"va": hex(address), "record_bytes": 31, "names": names,
                       "sha256": hashlib.sha256(data).hexdigest()})
    return result


def compare_items(path):
    data = path.read_bytes()
    if len(data) < 12 or data[:4] != b"M2SP" or struct.unpack_from("<I", data, 4)[0] != 1:
        raise ValueError("invalid current item name manifest")
    count = struct.unpack_from("<I", data, 8)[0]
    position, names, identities = 12, {}, set()
    for _ in range(count):
        if position + 6 > len(data):
            raise ValueError("truncated current item name manifest")
        identity, length = struct.unpack_from("<IH", data, position)
        position += 6
        if position + length > len(data) or not identity or identity in identities:
            raise ValueError("invalid current item name record")
        identities.add(identity)
        name = data[position:position + length].decode("utf-8")
        position += length
        names.setdefault(name, []).append(identity)
    if position != len(data):
        raise ValueError("trailing current item name data")
    def normalize(name):
        return name.replace("（", "(").replace("）", ")")
    rows = []
    for _, table in TABLES:
        for name in table:
            if not name:
                continue
            matches = [{"item_id": identity, "current_name": current,
                        "match": "exact" if current == name else "parenthesis_only"}
                       for current, ids in names.items() if normalize(current) == name
                       for identity in ids]
            rows.append({"original_name": name, "candidates": matches})
    return {"manifest_sha256": hashlib.sha256(data).hexdigest(), "item_count": count, "rows": rows,
            "limits": "Name correspondence only; punctuation normalization is an explicit catalog adapter. No strong-to-large medicine mapping or equal recovery values inferred."}


def extract(path, item_names=None):
    sample = path.read_bytes()
    if hashlib.sha256(sample).hexdigest() != EXPECTED_SAMPLE:
        raise ValueError("requires documented unpacked sample")
    evidence = []
    for address, expected, role in CHECKS:
        if read_va(sample, address, len(bytes.fromhex(expected))).hex() != expected:
            raise ValueError(f"unexpected instruction at {address:#x}: {role}")
        evidence.append({"va": hex(address), "hex": expected, "role": role})
    channels = []
    for name, offset, defaults in CHANNELS:
        channels.append({"name": name, "helper_offset": offset,
                         "fields": {"enabled": 0, "interval_ms": 4, "threshold": 8, "last_tick": 12},
                         "settings": [config_default(sample, *row) for row in defaults],
                         "actor_scalar_offset": 365 if name == "MP" else 361})
    result = {
        "schema_version": 1, "sample_sha256": EXPECTED_SAMPLE,
        "instruction_checks": evidence, "channels": channels,
        "book_selection": config_default(sample, 0x6C3B98, "RenewBookNowBookIndex", -1),
        "initial_medicine_tables": medicine_tables(sample),
        "controller": {"function": "0x6c4a40", "timer_ms": 50,
                       "channel_field": 17, "sequence": ["HP", "MP", "special", "book"],
                       "failure_rule": "advance once; only if new channel is3 evaluate it immediately; otherwise return",
                       "success_rule": "advance once and return", "requires_actor": True},
        "trigger": {"enabled": True, "nonzero_interval": True,
                    "elapsed": "u32(now-last_tick) >= interval", "health": "signed actor scalar < configured threshold",
                    "attempt_tick": "updated even if no medicine found or shared pending gate suppresses dispatch",
                    "threshold_units": "raw actor361/365 values; no maxHP/maxMP percentage calculation in this controller"},
        "selection_mode0": {"inventory_slots": [6, 51], "belt_slots": [0, 5],
                            "order": "for each grade: inventory first, then belt; then next grade",
                            "comparison": "CompareStringA locale0x400 with NORM_IGNORECASE",
                            "regular_initial_grade": 0,
                            "special": "try table2 grade0 inventory/belt, then mode0 table2 starting at grade1",
                            "pending_retry_ms": 800},
        "separate_gui_protection": {"controller": "0x5fd040", "check_ms": 1000,
                                    "hp": 361, "max_hp": 369, "mp": 365, "max_mp": 373,
                                    "action_dispatch": "0x5fe004", "item_use": ["0x5f5140", "0x690494"],
                                    "selection6": "explicit exit via66D4F0, not a medicine",
                                    "scope": "Separate GUI protection path uses manual inventory entry; do not assign the helper's800ms window to every automatic action. Configuration and activation require further analysis."},
        "limits": [
            "Static initial medicine tables; runtime table editing has not been traced.",
            "Stored Percent keys compare raw scalar values; user-facing editor conversion remains unaudited.",
            "Timer activation, configuration UI, derived helpers, mode1 callers and full book/escape actions remain incomplete.",
            "Original slots0-51 are not mir2x itemID/seqID or a reason to resize its belt protocol.",
            "This evidence does not enable automatic use in Godot; original defaults are disabled, unlike current mir2x protection booleans.",
        ],
    }
    if item_names is not None:
        result["current_item_name_comparison"] = compare_items(item_names)
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sample", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--item-names", type=Path)
    args = parser.parse_args()
    result = extract(args.sample, args.item_names)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps({"checks": len(result["instruction_checks"]), "channels": len(result["channels"]), "tables": len(result["initial_medicine_tables"])}))
