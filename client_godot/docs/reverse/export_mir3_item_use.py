"""Verify this Mir3 sample's pending item-use state and reply registrations.

This exports evidence, not a proposed mir2x cooldown or packet implementation.
The two DWORDs in the original request remain opaque item identity fields.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct

from export_mir3_target_history import EXPECTED_SAMPLE, read_va


CHECKS = [
    (0x68F8B6, "66b8ee03e89dbf0300", "construct original command1006"),
    (0x68F8F9, "8b550c89108b5510895004", "write two opaque identity DWORDs"),
    (0x68F908, "83c0088bd08b45f88bcbe8bd3ad7ff", "copy string after eight identity bytes"),
    (0x6C4A8A, "a15c9972008338007414", "no pending item bypasses elapsed check"),
    (0x6C4A94, "e867c10400", "read monotonic clock"),
    (0x6C4A99, "8b15689d72002b023d20030000720e", "unsigned elapsed below800 skips dispatch"),
    (0x6C4AA8, "a1c09372008b008bd3e8c2f3fcff", "dispatch item-use693E78"),
    (0x6904DD, "a15c9972008338007418", "separate inventory path also checks pending item"),
    (0x6904EC, "8b15689d72002b023db80b00000f8270060000", "inventory path uses unsigned3000ms pending window"),
    (0x693E9B, "8b155c99720083c9ff8b837c030000e88d590400", "restore previous pending item before next selection"),
    (0x693EC6, "8b068b10ff522ca80274208b068b10ff523885c07e15", "flag bit2 and positive VMT56 choose copy-only branch"),
    (0x693EDC, "8b0d5c9972008bd78b837c030000e8195c0400", "copy-only helper6D9B08"),
    (0x693EF1, "8b0d5c9972008bd78b837c030000e8285b0400", "take-from-slot helper6D9A2C"),
    (0x693F2F, "a1a09672008938e8c5cc07008b15689d72008902", "store source slot and pending clock"),
    (0x6D9A4D, "e816d8d2ff8bd68bc3e875f8ffff", "take helper copies interface then clears source slot"),
    (0x6D9B29, "e83ad7d2ff", "copy-only helper copies interface"),
    (0x6D984A, "8b168bc3e8150000008bc6e83ed1fbff", "restore helper inserts item then clears pending interface"),
    (0x690E00, "68fc27690066b9060066ba7b028bc6e8f0c20300", "register635 to success handler6927FC mode6"),
    (0x690E15, "68b827690066b9060066ba7c028bc6e8dbc20300", "register636 to failure handler6927B8 mode6"),
    (0x6927BE, "8b0da09672008b098b155c9972008b807c030000e865700400", "failure restores pending item to source slot"),
    (0x6927D7, "a1a0967200c700ffffffff", "failure resets source index to minus1"),
    (0x69283A, "8b078b10ff522ca8027430", "success tests item flag bit2"),
    (0x692845, "8b078b10ff5248487e26", "success requires count greater than1 for remainder"),
    (0x69284F, "8b078b10ff52488bd04a8b078b08ff514c", "success decrements remaining count"),
    (0x692860, "8b0da09672008b098b178b837c030000e8f36f0400", "success restores remainder to source slot"),
    (0x6928E7, "e8dc400000", "success clears shared pending item"),
    (0x6928EC, "a1a0967200c700ffffffff", "success resets source index to minus1"),
    (0x6969CB, "a15c997200e8c3ffffff", "clear wrapper addresses shared pending cell"),
    (0x6C4CFF, "e8c4030000", "automatic controller calls selection helper6C50C8"),
    (0x6C4D63, "e860030000", "second automatic controller branch calls same helper"),
    (0x6C52F4, "e88bf7ffff", "selection helper calls800ms wrapper"),
    (0x6C5359, "e826f7ffff", "second selection branch calls800ms wrapper"),
    (0x67E32D, "83c0d083e80a7213", "character dispatch accepts ASCII0 through9"),
    (0x67E348, "0fb613a1749b72008b00e85544fdff", "numeric character enters6527AC shortcut selector"),
    (0x6527AF, "0fb6d283ea304a85d27c0583fa097e05ba09000000", "characters1 through9 map slots0 through8;0 maps slot9"),
    (0x6527C4, "6a0033c98b949028010000e88ccdffff", "keyboard invokes same slot action64F560"),
    (0x64D75A, "c786a800000060f56400", "slot control also binds64F560 event handler"),
    (0x64F697, "a1c09372008b0033c98bd3e8ed0d0400", "resolved inventory slot invokes manual690494 path"),
    (0x64F5E9, "be1e0000008b1dac927200", "scan thirty special item/action pairs"),
    (0x64F617, "e838a9080085c00f8ebf000000", "special branch requires positive inventory count"),
    (0x64F624, "8b4304e894feffff", "special branch passes mapped action to64F4C0"),
    (0x64F631, "83c3084e75bd", "advance eight-byte special pair"),
    (0x64F63C, "ff521083fa00750783f8007626eb027e22", "positive signed64-bit identity selects instance lookup"),
    (0x64F666, "e8699f0800", "resolve positive identity via6D95D4"),
    (0x6526BE, "8db49f50010000", "ten shortcut references begin at object336"),
    (0x6526E6, "e8996c0800", "refresh shortcut through inventory helper6D9384"),
    (0x652718, "a15c9972008b00e840420400", "missing shortcut checks pending item before clearing"),
    (0x652749, "e8362fdbff7407", "matching pending name preserves otherwise missing shortcut"),
    (0x652750, "8bc6e8414204004383fb0a0f855dffffff", "clear unmatched shortcut and iterate ten entries"),
    (0x6D93B3, "ff522ca8027428", "refresh branches on item flag bit2"),
    (0x6D93D2, "e8e90a00008bd08b068b08ff514c", "refresh sets cloned count from inventory name total"),
]


def shortcut_rectangles(sample):
    rectangles = []
    for slot in range(10):
        address = 0x64D77A + slot * 25
        code = read_va(sample, address, 25)
        if (code[:5] != bytes.fromhex("6a206a1db9") or code[9] != 0xBA
                or code[14:16] != bytes.fromhex("8b83") or code[20] != 0xE8):
            raise ValueError(f"unexpected shortcut rectangle instructions at {address:#x}")
        control_offset = struct.unpack_from("<I", code, 16)[0]
        target = address + 25 + struct.unpack_from("<i", code, 21)[0]
        if control_offset != 296 + slot * 4 or target != 0x6EB26C:
            raise ValueError(f"unexpected shortcut control or rectangle target at {address:#x}")
        rectangles.append({"slot": slot, "key": str((slot + 1) % 10),
                           "x": struct.unpack_from("<I", code, 10)[0],
                           "y": struct.unpack_from("<I", code, 5)[0],
                           "width": code[3], "height": code[1],
                           "va": hex(address), "hex": code.hex()})
    return rectangles


def extract(sample_path, registry_path):
    sample = sample_path.read_bytes()
    if hashlib.sha256(sample).hexdigest() != EXPECTED_SAMPLE:
        raise ValueError("requires documented unpacked sample")
    evidence = []
    for address, expected, role in CHECKS:
        if read_va(sample, address, len(bytes.fromhex(expected))).hex() != expected:
            raise ValueError(f"unexpected item-use instruction at {address:#x}")
        evidence.append({"va": hex(address), "hex": expected, "role": role})
    registry = json.loads(registry_path.read_text(encoding="utf-8"))
    if registry["sample_sha256"] != EXPECTED_SAMPLE:
        raise ValueError("registry sample mismatch")
    registrations = []
    for message, handler, call in [(635, "0x6927fc", "0x690e0f"),
                                   (636, "0x6927b8", "0x690e24")]:
        matches = [r for r in registry["records"] if r["call"] == call]
        if len(matches) != 1 or any(matches[0][key] != value for key, value in {
            "message": message, "handler": handler, "registration_ecx": 6,
            "register_function": "0x690d74",
        }.items()):
            raise ValueError(f"unexpected item-use registration for {message}")
        registrations.extend(matches)
    return {
        "schema_version": 3, "sample_sha256": EXPECTED_SAMPLE,
        "instruction_checks": evidence, "reply_registrations": registrations,
        "shortcut_rectangles": shortcut_rectangles(sample),
        "special_shortcut_actions": {
            "pointer_cell": "0x7292ac", "table_va": hex(struct.unpack("<I", read_va(sample, 0x7292AC, 4))[0]),
            "records": [{"original_item_code": item, "original_action_code": action}
                        for item, action in struct.iter_unpack("<II", read_va(sample, 0x71ECD0, 30 * 8))],
            "identity_scope": "Original numeric domains; no current itemID/magicID equivalence inferred.",
        },
        "shared_cells": {"pending_interface": "0x72995c",
                         "source_index": "0x7296a0", "sent_tick": "0x729d68"},
        "findings": {
            "request": {"function": "0x68f888", "command": 1006,
                        "payload_prefix": "two opaque DWORDs then string"},
            "automatic_selection_pending_window_ms": 800,
            "inventory_pending_window_ms": 3000,
            "manual_shortcuts": {"characters": "1234567890", "slots": 10,
                                 "route": ["0x67e2d8", "0x6527ac", "0x64f560", "0x690494"],
                                 "pending_window_ms": 3000},
            "shortcut_refresh": "object336 stores ten references;6526A0 refreshes them through actor892 inventory, preserves matching pending name, otherwise clears missing entries",
            "shortcut_quantities": "6D9384 flag-bit2 branch clones the item and sets its count from inventory name total; other branch resolves a matching name and clones it",
            "pending_window": "unsigned elapsed; equality permits dispatch; null pending bypasses elapsed check",
            "retry": "restore previous pending item before selecting another; timeout is not success",
            "failure": "restore pending item to source index and clear pending interface",
            "success": "flagged stack count>1 restores count-1; then clear shared pending state",
        },
        "baseline_commit": "a1b4d1b",
        "baseline_gaps": [
            "Current CM_CONSUMEITEM and CM_CONSUMEBELTITEM differ from original1006.",
            "Current belt snapshot and inventory removal are not correlated635/636 replies.",
            "Quick-bar and inventory consume paths have no equivalent shared pending object.",
        ],
        "limits": [
            "800ms is a pending-item retry window, not a universal potion cooldown.",
            "800ms belongs to automatic selection; manual digit slots invoke the separate3000ms inventory path.",
            "Original has ten digit slots; current six-slot mir2x belt is a protocol/UI adaptation, not full original layout parity.",
            "Inventory-backed shortcut references differ from current separately stored belt items; do not expand the belt protocol solely from ten controls.",
            "Full shortcut drag/drop, persistence and special action behavior remain incomplete; numeric pairs are not recovered business names.",
            "Item flags, full descriptor layout, special success branches and server reward formulas are incomplete.",
            "Original identity DWORDs must not be assumed to equal current itemID/seqID.",
            "No original live server capture or gameplay implementation is supplied by this exporter.",
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sample", required=True, type=Path)
    parser.add_argument("--registry", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    result = extract(args.sample, args.registry)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n",
                           encoding="utf-8", newline="\n")
    print(json.dumps({"checks": len(result["instruction_checks"]),
                      "registrations": len(result["reply_registrations"])}))


if __name__ == "__main__":
    main()
