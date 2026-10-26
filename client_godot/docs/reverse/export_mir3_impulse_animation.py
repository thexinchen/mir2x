"""Recover original actor 6/7/9/37 frame selection without reusing mir2x IDs."""
import argparse
import hashlib
import json
from pathlib import Path
import struct

from export_mir3_target_history import EXPECTED_SAMPLE, read_va
from export_mir3_request_gate import extract_animation_delay


# Check the selectors and consumers as well as the constant records. In
# particular, action9 shares a walking frame record but runs it backwards.
CHECKS = [
    (0x6DE650, "0fb640392c037506b8007a7200c3b89c787200c3", "class table selector"),
    (0x6DE723, "83c2fa83fa1f0f87420e0000ff249536e76d00", "action switch"),
    (0x6DE994, "05e4000000e8d6fcffff", "action9 nonzero760 record"),
    (0x6DE9A9, "83c00ce8c3fcffff", "action9 zero760 walking record"),
    (0x6DE9B4, "b8010000008982e4000000", "action9 displacement one"),
    (0x6DEA0C, "e80b030200", "action9 opposite direction"),
    (0x6DEA40, "b86c7c7200e82afcffff", "action6/7 special frame record"),
    (0x6DEA55, "83c024e817fcffff", "action6/7 ordinary frame record"),
    (0x6DEA60, "b8010000008982e4000000", "action6/7 displacement one"),
    (0x6DEB51, "83c024e81bfbffff", "action37 same ordinary frame record"),
    (0x6DEB5C, "c780e400000001000000", "action37 displacement one"),
    (0x6DEB66, "68eb0000006a00", "action37 effect argument235"),
    (0x6DEB81, "e8825a0000", "action37 effect creation"),
    (0x6DEB8A, "e881390000", "action37 attach effect"),
    (0x6DE6A9, "8982b8000000", "frame start assignment"),
    (0x6DE6B8, "8982bc000000", "frame end assignment"),
    (0x6DE6C4, "8982d8000000", "frame interval assignment"),
    (0x6DE682, "a5a5a5", "frame resolver copies12-byte record"),
    (0x6DE68B, "0fb645f80fb655f903c28b130fb6521df7ea8b138b526c0355f403c2", "base plus directional count/gap stride"),
    (0x6DD9ED, "8b869802000083f809740a83f806740583f8257502b301", "fast frame actions9/6/37"),
    (0x6DDDB3, "e8b05efbff", "action9 completion delay setter"),
    (0x6DBA78, "8bc7c1e0048d04408945fc8bc7c1e0058945f8", "tile screen dimensions48/32"),
    (0x6DE981, "8b0680b8f8020000007415", "action9 byte760 branch"),
    (0x6DEA27, "a1109d72008b008078400074198b0680b8f802000000740e", "action6/7 two special predicates"),
]


def checked_records(sample):
    for address, code, label in CHECKS:
        expected = bytes.fromhex(code)
        if read_va(sample, address, len(expected)) != expected:
            raise ValueError(f"unexpected {label} at {address:#x}")
    switch = struct.unpack("<32I", read_va(sample, 0x6DE736, 128))
    branches = {6: 0x6DEA27, 7: 0x6DEA27, 9: 0x6DE981,
                11: 0x6DE8B3, 37: 0x6DEB49}
    for action, branch in branches.items():
        if switch[action - 6] != branch:
            raise ValueError(f"unexpected frame branch for actor action{action}")
    records = []
    for table in [0x72789C, 0x727A00]:
        for offset in [0x0C, 0x24, 0xE4]:
            address = table + offset
            base, count, gap, interval, opaque = struct.unpack("<IBBHI", read_va(sample, address, 12))
            if count != 6 or gap != 4 or interval not in [100, 200] or opaque != 0:
                raise ValueError("unexpected frame record layout")
            records.append({"va": hex(address), "table": hex(table), "offset": offset,
                            "base_frame": base, "frame_count": count,
                            "direction_gap": gap, "frame_interval_ms": interval,
                            "opaque_u32_8": opaque})
    base, count, gap, interval, opaque = struct.unpack("<IBBHI", read_va(sample, 0x727C6C, 12))
    if (base, count, gap, interval, opaque) != (1760, 6, 4, 100, 0):
        raise ValueError("unexpected special6/7 frame record")
    records.append({"va": "0x727c6c", "base_frame": base, "frame_count": count,
                    "direction_gap": gap, "frame_interval_ms": interval, "opaque_u32_8": opaque})
    opposite = []
    for address in struct.unpack("<8I", read_va(sample, 0x6FED2A, 32)):
        code = read_va(sample, address, 5)
        if code[0] == 0xBA:
            value = struct.unpack_from("<I", code, 1)[0]
        elif code[:2] == b"\x33\xd2":
            value = 0
        else:
            raise ValueError("unexpected opposite direction branch")
        opposite.append(value)
    if opposite != [4, 5, 6, 7, 0, 1, 2, 3]:
        raise ValueError("unexpected opposite direction table")
    return records, opposite, branches


def extract(sample_path, root):
    sample = sample_path.read_bytes()
    if hashlib.sha256(sample).hexdigest() != EXPECTED_SAMPLE:
        raise ValueError("requires documented unpacked Mir3 sample")
    records, opposite, branches = checked_records(sample)
    sources = {}
    for name in ["common/src/actionnode.hpp", "client/src/hero.cpp",
                 "client_godot/scripts/game/main.gd", "client_godot/scripts/game/world_renderer.gd"]:
        sources[name] = hashlib.sha256((root / name).read_text(encoding="utf-8").encode()).hexdigest()
    return {
        "schema_version": 1, "sample_sha256": EXPECTED_SAMPLE,
        "checks": [{"va": hex(a), "hex": c, "role": label} for a, c, label in CHECKS],
        "frame_setup": {"function": "0x6de6e0", "switch": "0x6de736",
                        "branches": {str(a): hex(b) for a, b in branches.items()},
                        "class_selector": "actor byte57 ==3 selects727A00, otherwise72789C",
                        "action9": "byte760 !=0 selects table+0xE4, otherwise table+0x0C (also ordinary walk11)",
                        "actions6_7": "global729D10->byte64 AND actor byte760: special727C6C; otherwise table+0x24",
                        "action37": "table+0x24; additionally creates and attaches effect argument235",
                        "records": records,
                        "frame_formula": "start=actor108+base+direction0to7*(count+gap); end=start+count-1",
                        "unknown_field": "record DWORD8 not consumed by6DE674; no semantic label inferred"},
        "motion": {"step_function": "0x6dba68", "screen_tile_pixels": [48, 32],
                   "displacement_units": {"6": 1, "7": 1, "9": 1, "37": 1},
                   "forward_frames": [6, 7, 37], "reverse_frames": [9],
                   "action9_direction": {"function": "0x6fed1c", "opposite_lookup": opposite},
                   "fast_frame_actions": [6, 9, 37],
                   "fast_frame_rule": "advance a second frame only while the first advance has not reached the endpoint; no skipped endpoint",
                   "action7_limit": "shares setup6 but not its300ms delay; late-frame reset restores saved actor coordinates"},
        "post_animation_delay": extract_animation_delay(sample),
        "current_comparison": {"source_sha256_lf": sources,
                               "current_enum": {"5": "ACTION_PUSHMOVE", "6": "ACTION_SPACEMOVE", "9": "ACTION_SPELL"},
                               "godot": "action3/5 share walk/run frame selection by action_step; action6 is an authoritative warp; action9 is spell animation",
                               "native": "MOTION_PUSHBACK and MOTION_PUSHBACKFLY are rejected by Hero::motionValid; numeric names alone cannot prove original9 correspondence",
                               "decision": "Do not attach original300/1000ms post-animation restrictions to current5/6/9 without a verified semantic translation"},
        "limits": ["Frame behavior and table selection are recovered; protocol semantic names and server impulse settlement are not.",
                   "No original record frame interval is substituted for current network speed or potion delay.",
                   "Effect argument235 is in the original effect domain, not current magicID235.",
                   "No changes to production gameplay or client-selected teleport destinations are made by this extractor."]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sample", required=True, type=Path)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    result = extract(args.sample, args.root)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps({"checks": len(CHECKS), "frame_records": len(result["frame_setup"]["records"]), "production_gameplay_changed": False}))


if __name__ == "__main__":
    main()
