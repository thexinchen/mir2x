"""Extract the original request-wait state machine; do not install an ACK gate.

The current transport is different: ordinary actions have no correlated owner
reply. This artifact separates evidence from a future protocol adaptation.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
from export_mir3_target_history import EXPECTED_SAMPLE, read_va


def extract(sample_path, registry_path, network_path, playerop_path, playernet_path):
    sample = sample_path.read_bytes()
    if hashlib.sha256(sample).hexdigest() != EXPECTED_SAMPLE:
        raise ValueError("requires the documented unpacked Mir3 sample")
    timeout_slot = struct.unpack("<I", read_va(sample, 0x729734, 4))[0]
    if timeout_slot != 0x71EBC8:
        raise ValueError("unexpected timeout indirection")
    timeout = struct.unpack("<I", read_va(sample, timeout_slot, 4))[0]
    helper = read_va(sample, 0x6FF670, 10)
    if helper != bytes.fromhex("c1e8100fb7c0c1e808c3"):
        raise ValueError("status helper no longer extracts the top byte")
    sentinel_instruction = read_va(sample, 0x6CBF40, 6)
    if sentinel_instruction[:2] != b"\xc7\x00":
        raise ValueError("unexpected timeout sentinel assignment")
    sentinel = struct.unpack_from("<I", sentinel_instruction, 2)[0]
    registry = json.loads(registry_path.read_text(encoding="utf-8"))
    if registry["sample_sha256"] != EXPECTED_SAMPLE:
        raise ValueError("registry sample mismatch")
    replies = [row for row in registry["records"] if row["handler"] == "0x69404c"]
    if len(replies) != 1 or replies[0]["message"] != 99:
        raise ValueError("expected original result message 99")
    sources = {}
    for label, path in [("godot_network", network_path), ("native_playerop", playerop_path), ("native_playernet", playernet_path)]:
        raw = path.read_text(encoding="utf-8").encode("utf-8")
        sources[label] = {"file": path.name, "sha256_lf": hashlib.sha256(raw).hexdigest()}
    return {
        "schema_version": 1, "sample_sha256": EXPECTED_SAMPLE,
        "wait_gate": {
            "check": "0x691738", "mark_sent": "0x691260", "clear": "0x693c4c",
            "pending_byte_offset": 3312, "sent_tick_u32_offset": 3320,
            "timeout_check": "0x68f808", "timeout_pointer": "0x729734",
            "timeout_storage": hex(timeout_slot), "sample_default_timeout_ms": timeout,
            "states": {
                "idle": "pending == 0: allow",
                "pending_not_expired": "elapsed <= timeout: deny, keep pending",
                "pending_expired": "elapsed > timeout: clear pending, still deny this check",
                "next_check_after_clear": "pending == 0: allow",
            },
            "elapsed_arithmetic": "unsigned 32-bit tick difference",
            "exceptional_timeout_assignment": {"instruction": "0x6cbf40", "value": sentinel,
                "note": "conditional packet-dispatch path; not evidence of measured RTT"},
        },
        "result_message": {
            "message": 99, "handler": "0x69404c", "registration": replies[0],
            "tracker_argument": {"offset": 0, "bytes": 4, "consumer": "0x4e7198"},
            "status_word_offset": 6,
            "nonzero_status": "clear pending through 0x693c4c, update UI",
            "zero_status": "0x68f5ec resets action state, then clear pending through 0x693c4c",
            "zero_status_restore_position_action_ids": [3006, 3007, 3011, 3013, 3056, 3057],
            "status_word_semantic_name": None,
            "note": "Do not assign success/error names without recovering the wire contract.",
        },
        "cast_permission": {
            "function": "0x68f7ac",
            "outer_guard": "global timeout value <= 10000",
            "actor_status_selector": {"function": "0x6dc440", "u32_offset": 128,
                "helper": "0x6ff670", "expression": "(actor_u32_128 >> 30) & 3",
                "semantic_name": None},
            "selected_status_branch": "selector != 0 AND dispatch_magic_id != 232: elapsed > shared_cast_delay",
            "other_branch": "actor_byte_134 bit7 must be clear",
            "shared_request_tick_pointer": "0x729380", "shared_delay_pointer": "0x7299b0",
            "ordinary_cast_delay_assignment": {"instruction": "0x67d5e5", "expression": "(skill_record_u32_64 + 1200) modulo 2^32"},
            "command_delay_assignment": {"instruction": "0x67d06a", "value": 0},
            "note": "Status selector, request pending flag and local animation are different inputs.",
        },
        "current_transport_gap": {
            "source_snapshots": sources,
            "godot_send_action": "CM_ACTION uses fixed send without a response ID",
            "godot_generic_request_timeout_ms": 1000,
            "native_cm_action": "handler ignores incoming response ID and has no generic correlated result reply",
            "native_owner_action": "on_AM_ACTION returns immediately when amA.UID == UID()",
            "required_before_runtime_wait_gate": [
                "Define a correlated action-result response for this transport.",
                "Distinguish acceptance, failure/state correction and owner action broadcasts.",
                "Carry the documented timeout and next-check behavior without reusing the generic 1s timeout.",
                "Test lost/reordered/stale replies and reconnect/map transitions before blocking user input.",
            ],
        },
        "limits": [
            "No runtime ACK gate is enabled by this artifact.",
            "No RTT meaning is inferred for the original timeout global.",
            "Actor status bit meanings and original result status semantic labels remain unresolved.",
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sample", required=True, type=Path)
    parser.add_argument("--registry", required=True, type=Path)
    parser.add_argument("--network", required=True, type=Path)
    parser.add_argument("--playerop", required=True, type=Path)
    parser.add_argument("--playernet", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    result = extract(args.sample, args.registry, args.network, args.playerop, args.playernet)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps({"timeout_ms": result["wait_gate"]["sample_default_timeout_ms"], "result_message": 99,
                      "status_selector": result["cast_permission"]["actor_status_selector"]["expression"]}))


if __name__ == "__main__":
    main()
