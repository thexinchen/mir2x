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
    (0x6838CC, "8b450883e80c83f8407c1f", "optional description requires76 payload bytes"),
    (0x6838E4, "8b55fc8d430cb940000000e8e0fad7ff", "copy64 description bytes from payload12"),
    (0x683917, "0fb746040fb7d081fa210300007f14742d83c2fa83ea0272254a742283ea1c741d", "local messages6/7/9/37 enter common actor routing"),
    (0x683990, "0fb74606500fb74608500fb7460a508b07508b4704508b45fc506a008b4708508b0e0fb756048b45f8e82657ffff", "forward header coordinates/packed direction and three payload DWORDs to6790E4"),
    (0x6791EA, "0fb7451cc1e8080fb6c08986ac0200000fb6451c89451c", "packed direction high byte goes to actor684; only low byte continues"),
    (0x679296, "8b4520508b451c508b4518508b4514506a006a008b450c508b4508508b4d248bd38bc6e8961d0600", "enqueue received action with null string/zero auxiliary fields"),
    (0x6DB08A, "0fb7c789038b45fc8943048b45248943088b452089430c8b451c8943108b4518894314", "write received action and first five queue DWORDs"),
    (0x6DB0AD, "8d43188b5514e8e8a1d2ff8b451089431c8b450c8943208b4508894324", "write remaining fields of40-byte queue record"),
    (0x6DB674, "8b45dc8943158b45e08943190fb655e48bc3e8cd100000", "apply record coordinates and facing to actor"),
    (0x6DB68B, "8b45f88983a00200008b45d8898398020000", "queue action number becomes actor664"),
    (0x6DB69D, "a1c09372003b1874098b45fc89839c0200008bc38b10ff520c", "remote actor668 update then virtual frame setup"),
    (0x6DE70A, "8b068b8098020000", "frame selector reads actor664"),
    (0x66CB3C, "b8104e730033c9ba00000200e87f6ed9ff33d2b8104e7300", "initialize65536 WORD command-translation entries to zero"),
    (0x66CB54, "8bc88bda81c346f4ffff83fb410f873b010000", "translation writes are restricted to command3002 through3067"),
    (0x66CCA2, "4283c00281fa000001000f85a2feffff", "translation initialization visits every WORD entry"),
    (0x6DB42F, "a10c9d72008b55d866833c5000", "local action remaps only a nonzero command-table entry"),
    (0x6DB479, "a10c9d72008b55d80fb704508945d8", "local command-table remap assigns resulting action"),
    (0x6839BE, "0fb746046683e8067451", "message6 selects the local impulse-clock branch"),
    (0x683A23, "3b420c0f85a8000000e8cfd108008b15f09772008902", "only local message6 stamps shared impulse clock"),
]

FEEDBACK_REGISTRATIONS = {6: "0x67eac9", 7: "0x67eaf3", 9: "0x67ebda", 37: "0x67eade"}


def decode_feedback(header, payload, local_uid):
    """Decode already-unframed original fields, without changing actor state."""
    if len(header) != 12 or len(payload) < 12:
        raise ValueError("requires exactly12 header bytes and at least12 payload bytes")
    if not isinstance(local_uid, int) or isinstance(local_uid, bool) or not 0 <= local_uid <= 0xFFFFFFFF:
        raise ValueError("local UID must be an unsigned32-bit integer")
    uid, message, x, y, packed = struct.unpack("<I4H", header)
    if message not in FEEDBACK_REGISTRATIONS:
        raise ValueError("decoder supports original messages6/7/9/37 only")
    p0, p1, p2 = struct.unpack_from("<3I", payload)
    return {"uid": uid, "message": message, "x": x, "y": y,
            "direction_raw_u8": packed & 255, "actor684_u8": packed >> 8,
            "payload_u32": [p0, p1, p2],
            "description_hex": payload[12:76].hex() if len(payload) >= 76 else None,
            "queue_record_u32": [message, x, y, packed & 255, p0, p1, 0, 0, 0, p2],
            "stamp_local_impulse_clock": message == 6 and uid == local_uid,
            "local_actor": uid == local_uid}


def feedback_evidence(sample, root):
    registry = json.loads((root / "client_godot/docs/reverse/mir3-socket-registry.json").read_text(encoding="utf-8"))
    if registry["sample_sha256"] != EXPECTED_SAMPLE:
        raise ValueError("feedback registry sample mismatch")
    registrations = []
    for message, call in FEEDBACK_REGISTRATIONS.items():
        rows = [r for r in registry["records"] if r["message"] == message]
        if len(rows) != 1 or any(rows[0].get(k) != v for k, v in {
            "call": call, "handler": "0x683874", "registration_ecx": 6,
            "register_function": "0x67ea1c",
        }.items()):
            raise ValueError(f"unexpected impulse feedback registration for{message}")
        registrations.extend(rows)
    if struct.unpack("<I", read_va(sample, 0x729D0C, 4))[0] != 0x734E10:
        raise ValueError("unexpected command translation table pointer")
    if struct.unpack("<I", read_va(sample, 0x6DA738, 4))[0] != 0x6DE6E0:
        raise ValueError("unexpected actor frame setup virtual method")
    return {"registrations": registrations, "handler": "0x683874",
            "actor_router": "0x6790e4", "enqueue": "0x6db054", "apply": "0x6db2f0",
            "header": {"bytes": 12, "uid_u32": 0, "message_u16": 4,
                       "x_u16": 6, "y_u16": 8, "packed_direction_u16": 10},
            "payload": {"minimum_decoder_bytes": 12, "raw_u32_offsets": [0, 4, 8],
                        "optional_description_offset": 12, "optional_description_bytes": 64,
                        "description_rule": "only copy when payload length>=76; shorter tail is not partially copied",
                        "existing_actor_queue_string": None},
            "queue_record_bytes": 40,
            "queue_u32_fields": ["original_message", "x", "y", "direction_low_byte", "payload0", "payload4", "null_string", "zero", "zero", "payload8"],
            "actor_fields": {"packed_high_byte": 684, "record_action": 664,
                             "coordinates": [21, 25], "remote_payload8": 668},
            "initial_command_translation": {"pointer": "0x729d0c", "table": "0x734e10",
                                            "initializer": "0x66cb38", "feedback6_7_9_37": [0, 0, 0, 0]},
            "frame_virtual_entry": {"entry": "0x6da738", "method": "0x6de6e0"},
            "local_clock": "only message6 with UID==local UID stamps7297F0",
            "limits": "Decoded queue fields are not a guarantee the actor applies them: actor eligibility, unknown actor creation and runtime command-table mutation are separate. Packed high byte and raw payload DWORDs have no inferred business names."}


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
        "schema_version": 2, "sample_sha256": EXPECTED_SAMPLE,
        "checks": [{"va": hex(a), "hex": c, "role": label} for a, c, label in CHECKS],
        "feedback": feedback_evidence(sample, root),
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
        "limits": ["Original messages6/7/9/37 reach the same-numbered queue and frame domain after the documented initialization; business names and server impulse settlement are incomplete.",
                   "No original record frame interval is substituted for current network speed or potion delay.",
                   "Effect argument235 is in the original effect domain, not current magicID235.",
                   "No changes to production gameplay or client-selected teleport destinations are made by this extractor."]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sample", required=True, type=Path)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--header", type=Path, help="Already-unframed original12-byte header")
    parser.add_argument("--payload", type=Path, help="Already-decoded original payload, not current mir2x data")
    parser.add_argument("--local-uid", type=lambda value: int(value, 0))
    args = parser.parse_args()
    if any(v is not None for v in [args.header, args.payload, args.local_uid]) and not all(v is not None for v in [args.header, args.payload, args.local_uid]):
        parser.error("--header, --payload and --local-uid must be supplied together")
    result = extract(args.sample, args.root)
    if args.header is not None:
        result["decoded_feedback"] = decode_feedback(args.header.read_bytes(), args.payload.read_bytes(), args.local_uid)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps({"checks": len(CHECKS), "frame_records": len(result["frame_setup"]["records"]), "production_gameplay_changed": False}))


if __name__ == "__main__":
    main()
