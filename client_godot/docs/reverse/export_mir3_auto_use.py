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
    (0x5F9C96, "80787c007519a1289d720080780100750e", "GUI auto recovery has actor124 and global729D28 byte1 guards"),
    (0x5F97DD, "8378f41e0f8cc7000000", "GUI automatic HP requires deficit at least30"),
    (0x5F97E7, "bb110000008b049d145e7200", "GUI automatic HP scans recovery table backward from index17"),
    (0x5F9807, "85db7e0c8b049d105e72003b45f074ef", "HP groups adjacent equal recovery values and starts at their first entry"),
    (0x5F9BAD, "83e8280f82bf00000083e846720c83e846721a83e846722b", "GUI automatic MP deficit bands begin40 and increase by70"),
    (0x6911CB, "2b83180d00008b93200d00003bc2770485d27505", "GUI frame gate permits only elapsed greater than item delay, or zero delay"),
    (0x5FE01F, "b201e8caf40600", "escape selection6 invokes explicit exit with argument1"),
    (0x5FE054, "8950088b500883fa067f0485d27d0533d2895008c3", "escape selector clamps both negative and greater-than6 to0"),
    (0x690A7C, "8983180d00008d957cffffffa15c9972008b008b08ff510c8b45e08983200d0000", "manual entry stores shared actor use tick and delay from item record offset100"),
    (0x5FD11B, "e82080ffff", "AutoBack first path calls named item use directly, not escape/exit dispatcher"),
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
GUI_HP_NAMES = ["急救丸(小)", "金创药(小)", "急救丸(中)", "太阳水", "金创药(中)",
                "急救丸(大)", "强效太阳水", "金创药(大)", "九叶灵芝(小)", "急救丸(特)",
                "急救瓶", "千年雪霜", "万年雪霜", "金创药(特)", "雪霜菁华", "九叶灵芝(中)",
                "金创药(特大)", "九叶灵芝(大)"]
GUI_HP_VALUES = [30, 30, 70, 70, 70, 110, 110, 110, 140, 170, 70, 130, 170, 170, 195, 200, 200, 300]
GUI_MP_NAMES = ["魔法药(小)", "魔法药(中)", "魔法药(大)", "魔法药(特)", "清心丸(小)",
                "清心丸(中)", "清心丸(大)", "清心丸(特)", "清新瓶", "太阳水", "强效太阳水",
                "千年雪霜", "万年雪霜", "九叶灵芝(小)", "九叶灵芝(中)", "雪霜菁华", "九叶灵芝(大)"]
ESCAPE_NAMES = ["回城卷", "随机传送卷", "随机传送石", "地牢逃脱卷", "比奇传送石", "盟重传送石", "小退"]
GUI_KEY_LOADS = [
    (0x5F9F11, "AutoHP"), (0x5F9F40, "HPVal"), (0x5F9F6A, "SyncHP"), (0x5F9F8D, "ManualHP"),
    (0x5FA0BF, "AutoMP"), (0x5FA0EE, "MPVal"), (0x5FA118, "SyncMP"), (0x5FA13B, "ManualMP"),
    (0x5FA286, "AutoBackCheck"), (0x5FA2A9, "AutoBackVal"), (0x5FA2D3, "AutoBackModel"),
    (0x5FA312, "HPMaxBackCheck"), (0x5FA330, "HPMaxBackVal"), (0x5FA34A, "HPMaxBackModel"),
    (0x5FA3AA, "HPBackCheck2"), (0x5FA3C8, "HPBackVal2"), (0x5FA3E2, "HPBackModel2"),
    (0x5FA442, "MPBackCheck1"), (0x5FA460, "MPBackVal1"), (0x5FA47A, "MPBackModel1"),
    (0x5FA4DA, "MPBackCheck2"), (0x5FA4F8, "MPBackVal2"), (0x5FA512, "MPBackModel2"),
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


def gui_rules(sample):
    def string_table(address, expected):
        result = []
        for index, name in enumerate(expected):
            pointer = struct.unpack("<I", read_va(sample, address + index * 4, 4))[0]
            length = struct.unpack("<I", read_va(sample, pointer - 4, 4))[0]
            if length > 64 or read_va(sample, pointer, length).decode("gb18030") != name:
                raise ValueError(f"unexpected GUI name table at {address:#x} index{index}")
            result.append({"index": index, "name": name, "pointer": hex(pointer)})
        return result
    hp = string_table(0x725DCC, GUI_HP_NAMES)
    values = list(struct.unpack("<18I", read_va(sample, 0x725E14, 72)))
    if values != GUI_HP_VALUES:
        raise ValueError("unexpected GUI HP recovery weights")
    for row, value in zip(hp, values):
        row["selection_weight"] = value
    keys = []
    for address, expected in GUI_KEY_LOADS:
        code = read_va(sample, address, 10)
        if code[0] != 0xB9 or code[5] != 0xBA:
            raise ValueError(f"unexpected GUI config key load at {address:#x}")
        key = ansi_string(sample, struct.unpack_from("<I", code, 1)[0])
        section = ansi_string(sample, struct.unpack_from("<I", code, 6)[0])
        if key != expected or section != "Protect":
            raise ValueError(f"unexpected GUI config key at {address:#x}")
        keys.append({"key": key, "section": section, "va": hex(address), "hex": code.hex()})
    return {
        "configuration": {"file_family": "character.MFA", "loader": "0x5f9d94", "saver": "0x5fab00", "keys": keys,
                          "auto_and_manual": "automatic takes precedence; loader disables manual if both are set",
                          "defaults": "AutoHP/AutoMP/SyncHP/SyncMP/ManualHP/ManualMP and escape checks default0; HPVal/MPVal default current maxima"},
        "automatic_recovery": {"entry": "0x5f9c7c", "hp": "0x5f9738", "mp": "0x5f9b1c",
                               "order": "HP then MP", "target": "min(configured target, actor maximum)",
                               "sync": "5FCD38 updates target fields to latest maxima only when Auto and Sync controls are enabled",
                               "hp_minimum_deficit": 30, "hp_table": hp,
                               "hp_selection": "scan original indexes17..0; skip weights above deficit; try adjacent equal-weight group in forward order, then continue backward; do not sort this nonmonotonic table",
                               "mp_minimum_deficit": 40, "mp_deficit_bands": [40, 110, 180, 250],
                               "mp_name_options": string_table(0x725E5C, GUI_MP_NAMES),
                               "mp_selection_scope": "bands select5F98D4 branches; recursive medicine and special fallback still need complete extraction",
                               "item_use": ["0x5f5140", "0x690494"],
                               "frame_gate": "6911C0: unsigned elapsed since actor3352 > actor3360 delay, or delay0; separate from pending3000ms",
                               "delay_source": "690A7C stores actor3352;690A97 stores latest item record offset100 into actor3360, one shared actor pair rather than separate per-item timers",
                               "guards": {"actor124": 0, "cell729D28_byte1": 0}},
        "escape_protection": {"entry": "0x5fd040", "period_ms": 1000,
                              "options": string_table(0x72603C, ESCAPE_NAMES), "selector_bounds": [0, 6],
                              "invalid_selector": 0, "exit_selector": 6,
                              "auto_back_exception": "first AutoBack path checks selected item name and calls5F5140 directly; it does not apply5FE004's special exit-selector6 branch",
                              "damage_entry": "0x5fd228", "damage_interval_ms": 2000,
                              "damage_trigger": "positive damage strictly above HPMaxBackVal; last tick advances only after a nonzero local action result, not a server acknowledgement"},
        "limits": "GUI automatic recovery, manual deficit rows and escape protection are distinct from the helper.Set controller. Stored .MFA format and all mode callbacks are not yet migrated.",
    }


def hp_candidate_order(deficit, records):
    """Replay5F9738's automatic branch for review, without sending game requests."""
    if deficit < 30:
        return []
    result, index = [], len(records) - 1
    while index >= 0:
        value = records[index]["selection_weight"]
        if value > deficit:
            index -= 1
            continue
        start = index
        while start > 0 and records[start - 1]["selection_weight"] == value:
            start -= 1
        result.extend(row["name"] for row in records[start:index + 1])
        index = start - 1
    return result


def compare_items(path, original_names=None):
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
    for table in ([original_names] if original_names is not None else [table for _, table in TABLES]):
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
        "schema_version": 2, "sample_sha256": EXPECTED_SAMPLE,
        "instruction_checks": evidence, "channels": channels,
        "book_selection": config_default(sample, 0x6C3B98, "RenewBookNowBookIndex", -1),
        "initial_medicine_tables": medicine_tables(sample),
        "gui_rules": gui_rules(sample),
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
                                    "scope": "Escape protection, not GUI auto recovery. Uses manual inventory entry; do not assign the helper's800ms window to every automatic action. See gui_rules for separate .MFA settings."},
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
        result["gui_item_name_comparison"] = compare_items(item_names, list(dict.fromkeys(GUI_HP_NAMES + GUI_MP_NAMES + ESCAPE_NAMES[:-1])))
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
