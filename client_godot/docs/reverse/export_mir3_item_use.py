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
    (0x64A0E4, "8d84b3500100008bd7e876d1dbff", "shortcut setter copies interface into indexed reference"),
    (0x64A426, "8b4310e8dac5040084c0740c0fb6430c2c0174092c067405", "drop accepts item interface from source kinds1 or7"),
    (0x64A455, "8d84b350010000e8efcddbff", "clear shortcut reference without inventory removal"),
    (0x64D946, "8b94bb50010000e81699dbff", "shortcut getter copies indexed interface"),
    (0x64DB24, "b007c3", "shortcut drag interface kind is7"),
    (0x66D631, "baf1030000e8c9ee0500", "explicit exit path sends original command1009"),
    (0x66D680, "e84ba60500", "explicit exit calls common session cleanup6C7CD0"),
    (0x6CC89C, "e827000000", "endpoint/role transition handler calls6CC8C8"),
    (0x6CC9A0, "e82bb3ffff", "transition cleanup joins6C7CD0"),
    (0x6C7D18, "a1749b72008b00e83c7cf8ff", "common cleanup resets current operate-board shortcuts"),
    (0x64F9A8, "33db8d849e50010000e8f26f04004383fb0a75ee", "clear all ten references at object336 with four-byte stride"),
    (0x6969AE, "8bc3e89b08d7ff5b5dc3", "cleanup wrapper invokes System.IntfClear"),
    (0x64DA88, "b002c3", "shortcut reference conversion mode2"),
    (0x64DA8C, "0fb60594da6400c303", "shortcut drag property flags3"),
    (0x64DB3C, "807a0c077506807a1c01740333c0c3b001c3", "custom transfer accepts shortcut kind7 to inventory kind1"),
    (0x6FDD24, "837820000f95c0c3837810000f95c0c3", "state predicates test target32 and held16"),
    (0x6FE160, "8b4624508b4628500fb64e1c8b56208b4608e8f5f5ffff", "pickup records target slot/owner/kind/item in persistent cursor"),
    (0x6FDE7C, "0fb6500c3a501c0f94c0c3", "compare source kind12 and target kind28"),
    (0x6FDE88, "8b50143b50240f94c0c3", "compare source slot20 and target slot36"),
    (0x6FDC1B, "8b50248b40288b08ff511c", "clear target via target owner and slot"),
    (0x6FDC2B, "8b50148b40188b08ff511c", "clear source via source owner and slot"),
    (0x6FDFA6, "8b4b208b53148b43188b30ff56188b53208b4308e801f8ffff", "swap writes displaced target to source and keeps displaced item on cursor"),
    (0x6FDBCC, "8bc6e8550000008bc6e83e0000008bc6e8b70300008bc6e8b4fcffff", "occupied same-kind transfer clears slots, replaces source and sets destination"),
    (0x6FE1B8, "8bc6e8c9fcffff84c0756d", "same source slot skips slot mutation before ending drag"),
    (0x6FE1C3, "8bc6e85efaffff8bc6e8cbf6ffff", "empty same-kind target clears source then sets target"),
    (0x6FE23F, "8bc6e8e6f7ffff", "empty target transfer ends persistent cursor"),
    (0x6FD7DB, "33c0894310c6431800c64319008d4314e8609ad0ff", "cursor cleanup resets metadata and clears owner interface"),
    (0x6FD985, "e8d6ffffff", "cancel checks source release property bit0"),
    (0x6FD990, "e893020000", "permitted cancel clears active source reference"),
    (0x65F526, "807dff017515e8ef77030084c0740c8bc6e8ec3e0000e948020000", "right press with held cursor cancels before GUI dispatch"),
    (0x65F388, "c745f8181b6600", "input callback record ends with661B18"),
    (0x708C8E, "8b46388983180100008b463c89831c010000", "D3D backend installs final callback as control event280"),
    (0x708DC6, "8b46388983180100008b463c89831c010000", "DDraw backend installs final callback as control event280"),
    (0x452C88, "f6435008740b8bc366bee9ffe8ab17fbff", "left double-click handler invokes dynamic methodFFE9"),
    (0x452B2B, "8b831c010000ff9318010000", "dynamic double-click method invokes event280"),
    (0x661B29, "c645f004", "double-click callback emits GUI event4"),
    (0x661B37, "c645f101", "double-click callback identifies left button1"),
    (0x6EAED8, "2c030f8488000000", "GUI event4 selects slot secondary action"),
    (0x6EAF81, "ff97a8000000", "GUI event4 invokes field168 bound to shortcut use"),
    (0x6EAF09, "807e0101757cc6474000", "GUI release requires left button and resets pressed flag"),
    (0x6EAF59, "8b4e088b56048bc7e88af9ffff", "release inside control invokes ordinary click"),
    (0x6EA922, "ff93a0000000", "ordinary click invokes field160 bound to shortcut transfer"),
    (0x64F598, "80781807751ce8e149eaff3b58107512", "held shortcut kind7 and matching source slot take priority"),
    (0x64F5A8, "e8d749eaff8b500c8d45fce8b07cdbffeb0f", "use selects held proxy instead of slot reference"),
    (0x6D93E9, "ff51188b55f48d4dfc8bc7e8ef0e0000", "non-grouped refresh passes item name to first-match lookup"),
    (0x6D93FD, "8bd68b45fc8b008b08ff5158", "non-grouped refresh clones the matched inventory item"),
    (0x6DA32F, "ff51188b45f08b55fce847b3d2ff7511", "first-match lookup compares item name strings"),
    (0x6DA33F, "8b46088d04988b55f88902c645f701eb04", "first matching name returns its slot without scanning later matches"),
    (0x6526FB, "ba9c2765008b06e8f912dcff84c0744c8b55fc8b45f88b08ff5118", "refresh replaces the item through shared proxy interface method24"),
    (0x4F28D7, "83c0e8508b008b400c870424c3", "proxy interface setter adjusts object24 and dispatches virtual method12"),
    (0x4F3065, "8bd68bc3e87afeffff", "shortcut proxy setter replaces underlying item through4F2EE8"),
    (0x4F2F01, "8d43148bd6e85d43f1ff", "proxy replacement copies new item into object20 without replacing shared wrapper"),
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


def shortcut_interface(sample):
    table = 0x64A003
    count = struct.unpack("<I", read_va(sample, table, 4))[0]
    if count != 3:
        raise ValueError("unexpected shortcut interface table count")
    matches = []
    for index in range(count):
        record = read_va(sample, table + 4 + 28 * index, 28)
        vtable, offset, getter = struct.unpack_from("<III", record, 16)
        if offset == 0x3A0: matches.append(vtable)
    if len(matches) != 1:
        raise ValueError("missing unique shortcut drag interface")
    methods = []
    for slot, name, expected in [(3, "kind", 0x64DB24), (4, "accept", 0x64A420),
                                  (5, "get", 0x64D930), (6, "set", 0x64A0D8),
                                  (7, "clear", 0x64A44C)]:
        wrapper = struct.unpack("<I", read_va(sample, matches[0] + slot * 4, 4))[0]
        code = read_va(sample, wrapper, 10)
        if code[:6] != bytes.fromhex("0560fcffffe9"):
            raise ValueError(f"unexpected shortcut interface wrapper for {name}")
        target = wrapper + 10 + struct.unpack_from("<i", code, 6)[0]
        if target != expected:
            raise ValueError(f"unexpected shortcut interface target for {name}")
        methods.append({"method": name, "vtable_offset": slot * 4,
                        "wrapper": hex(wrapper), "hex": code.hex(), "target": hex(target)})
    return {"table_va": hex(table), "vtable": hex(matches[0]),
            "object_offset": 928, "methods": methods, "source_kind": 7,
            "accepted_source_kinds": [1, 7]}


def shortcut_drag_rules(sample):
    entry = read_va(sample, 0x64A007, 28)
    if any(read_va(sample, address, 16) != entry[:16]
           for address in [0x6FDAC0, 0x6FDCA4, 0x6FDD9C]):
        raise ValueError("shortcut property interface queries disagree")
    vtable, offset = struct.unpack_from("<II", entry, 16)
    if offset != 920:
        raise ValueError("unexpected shortcut property interface offset")
    methods = []
    for slot, name, expected in [(3, "flags", 0x64DA8C), (4, "conversion_mode", 0x64DA88)]:
        wrapper = struct.unpack("<I", read_va(sample, vtable + slot * 4, 4))[0]
        code = read_va(sample, wrapper, 10)
        if code[:6] != bytes.fromhex("0568fcffffe9") or wrapper + 10 + struct.unpack_from("<i", code, 6)[0] != expected:
            raise ValueError(f"unexpected shortcut property wrapper for {name}")
        methods.append({"name": name, "wrapper": hex(wrapper), "target": hex(expected), "hex": code.hex()})
    return {
        "properties": {"object_offset": offset, "vtable": hex(vtable), "methods": methods,
                       "flags": 3, "conversion_mode": 2},
        "context_fields": {"held_item": 16, "source_kind": 12, "source_slot": 20,
                           "source_owner": 24, "target_kind": 28, "target_item": 32,
                           "target_slot": 36, "target_owner": 40},
        "pickup": "record cursor without clearing source slot",
        "occupied_same_kind": "swap slot references; keep displaced target on cursor with original source slot",
        "empty_same_kind": "clear original source, set target, end cursor",
        "same_slot": "end cursor without mutating the source reference",
        "explicit_cancel": "flags bit0 permits clearing only the active source reference",
        "inventory_target": "custom kind7-to-kind1 handler completes by clearing shortcut source; no real item drop inferred",
        "limits": "Ordinary shortcut transfers; custom merging and other owners' conversion/callback rules are not fully recovered.",
    }


def shortcut_mouse_rules(sample):
    # Delphi dynamic table: count, count WORD keys, then count DWORD handlers.
    count = struct.unpack("<H", read_va(sample, 0x44C3FE, 2))[0]
    if count != 77:
        raise ValueError("unexpected control dynamic method count")
    entries = []
    for key, expected in [(0x203, 0x452C60), (0x206, 0x452D84), (0xFFE9, 0x452B1C)]:
        keys = struct.unpack("<77H", read_va(sample, 0x44C400, count * 2))
        if keys.count(key) != 1:
            raise ValueError(f"unexpected control dynamic key {key:#x}")
        address = 0x44C400 + count * 2 + keys.index(key) * 4
        target = struct.unpack("<I", read_va(sample, address, 4))[0]
        if target != expected:
            raise ValueError(f"unexpected control dynamic target for {key:#x}")
        entries.append({"key": hex(key), "entry": hex(address), "target": hex(target)})
    return {
        "control_dynamic_entries": entries,
        "left_click": "transfer reference on release inside the pressed control, not on press",
        "left_double_click": {"native_message": "0x203", "dynamic_method": "0xffe9",
                              "event_field": 280, "callback": "0x661b18", "gui_event": 4,
                              "slot_callback_field": 168, "use": "0x64f560"},
        "right_press": "held cursor cancellation precedes GUI routing; ordinary shortcut right click does not use an item",
        "digit_keys": "invoke64F560 directly, independently of mouse event dispatch",
        "limits": "Established current rendering backends and ordinary shortcut controls; special merging and other GUI owners remain separate.",
    }


def shortcut_reference_refresh(sample):
    entry = read_va(sample, 0x4F2ACD, 28)
    if entry[:16] != read_va(sample, 0x65279C, 16):
        raise ValueError("shortcut refresh proxy GUID disagrees")
    vtable, offset = struct.unpack_from("<II", entry, 16)
    if vtable != 0x4F2A21 or offset != 24:
        raise ValueError("unexpected shortcut proxy interface layout")
    setter = struct.unpack("<I", read_va(sample, vtable + 24, 4))[0]
    target = struct.unpack("<I", read_va(sample, 0x4F2C50 + 12, 4))[0]
    if setter != 0x4F28D7 or target != 0x4F3048:
        raise ValueError("unexpected shortcut proxy setter")
    return {
        "proxy_interface": {"entry": "0x4f2acd", "object_offset": offset,
                            "vtable": hex(vtable), "setter_wrapper": hex(setter),
                            "shortcut_setter": hex(target), "item_field": 20},
        "non_grouped": "lookup first inventory item by name, clone it, replace the underlying item of the existing shortcut proxy",
        "grouped": "clone and set current inventory name total, including zero",
        "held_cursor": "shares the same shortcut proxy; replacing underlying item is visible through source and cursor references",
        "source_key": "matching kind7 cursor source slot selects the held proxy before the slot's current reference",
        "pending_missing": "matching pending item name preserves the existing proxy without replacing its cached contents",
        "missing_non_grouped": "clear the slot reference; a separately held interface remains alive",
        "identity_limit": "Original string names, flag bits and opaque64-bit IDs remain distinct from mir2x itemID/seqID and packable metadata.",
    }


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
        "schema_version": 8, "sample_sha256": EXPECTED_SAMPLE,
        "instruction_checks": evidence, "reply_registrations": registrations,
        "shortcut_rectangles": shortcut_rectangles(sample),
        "shortcut_drag_interface": shortcut_interface(sample),
        "shortcut_drag_rules": shortcut_drag_rules(sample),
        "shortcut_mouse_rules": shortcut_mouse_rules(sample),
        "shortcut_reference_refresh": shortcut_reference_refresh(sample),
        "shortcut_session_cleanup": {
            "explicit_exit": "0x66d4f0", "request_command": 1009,
            "role_endpoint_transition": ["0x6cc7ac", "0x6cc8c8"],
            "shared_cleanup": "0x6c7cd0", "shortcut_reset": "0x64f960",
            "reference_offset": 336, "stride": 4, "count": 10,
            "clear_wrapper": "0x6969a8", "operation": "System.IntfClear",
            "scope": "Established exit/role-transition cleanup; not a claim that every TCP event or ordinary map update uses this path.",
            "persistence": "No paired shortcut save/restore established; do not infer persistent bindings from generic character.Set configuration.",
        },
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
            "shortcut_session_boundary": "explicit exit and role endpoint transition clear all ten references through the same reset routine",
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
            "Drop-interface kind/accept/get/set/clear are recovered; persistence, remaining drag callbacks and special action behavior are incomplete.",
            "Current packable/itemID grouping adapts original flag-bit2/name grouping; numeric pairs are not recovered business names.",
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
