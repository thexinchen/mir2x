"""Extract the original request-wait state machine and track its current adapter.

The current transport supplies optional correlated processing receipts. This
artifact separates original evidence from the active gameplay adaptation.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
from export_mir3_target_history import EXPECTED_SAMPLE, read_va


def extract_professions(sample):
    # 66F030 calls the selector, then indexes this switch to construct a helper.
    if read_va(sample, 0x66F048, 5) != bytes.fromhex("e8f3d30600"):
        raise ValueError("profession dispatch no longer calls the actor selector")
    table = struct.unpack("<4I", read_va(sample, 0x66F05C, 16))
    rows = []
    for value, branch, expected, role, label_va in [
        (0, 0x66F070, "TmirZSHelper", "warrior", 0x52C354),
        (1, 0x66F083, "TmirFSHelper", "wizard", 0x52C364),
        (2, 0x66F096, "TmirDSHelper", "taoist", 0x52C374),
        (3, 0x66F0A9, "TmirCKHelper", "assassin", 0x52C354),
    ]:
        code = read_va(sample, branch, 7)
        if table[value] != branch or code[:3] != bytes.fromhex("b201a1"):
            raise ValueError("unexpected profession helper switch")
        cell = struct.unpack_from("<I", code, 3)[0]
        vmt = struct.unpack("<I", read_va(sample, cell, 4))[0]
        # Delphi VMT's class name is an inline ShortString after three methods.
        length = read_va(sample, vmt + 12, 1)[0]
        name = read_va(sample, vmt + 13, length).decode("ascii")
        if name != expected:
            raise ValueError("unexpected profession helper class name")
        label = read_va(sample, label_va, 16).split(b"\0", 1)[0].decode("gbk")
        rows.append({"value": value, "role": role, "branch": hex(branch),
                     "vmt_pointer_cell": hex(cell), "vmt": hex(vmt),
                     "class_name": name, "damage_stat_label": label,
                     "damage_stat_label_va": hex(label_va)})
    return rows


def extract(sample_path, registry_path, network_path, playerop_path, playernet_path, main_path):
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
    definitions = [row for row in registry["records"] if row["handler"] == "0x6940dc"]
    if len(definitions) != 1 or definitions[0]["message"] != 97:
        raise ValueError("expected original skill definition message 97")
    if read_va(sample, 0x6AB316, 5) != bytes.fromhex("bf53000000") or read_va(sample, 0x6AB365, 5) != bytes.fromhex("b866000000"):
        raise ValueError("unexpected skill definition copy/allocation limits")
    sources = {}
    for label, path in [("godot_network", network_path), ("native_playerop", playerop_path), ("native_playernet", playernet_path), ("godot_main", main_path), ("godot_request_gate", main_path.parent / "mir3_request_gate.gd")]:
        raw = path.read_text(encoding="utf-8").encode("utf-8")
        sources[label] = {"file": path.name, "sha256_lf": hashlib.sha256(raw).hexdigest()}
    if "_send_request(CM_ACTION, action_data, false, callback, 10001, timeout_callback)" not in network_path.read_text(encoding="utf-8"):
        raise ValueError("current transport snapshot lacks optional action receipts")
    if "postNetMessage(processed ? SM_OK : SM_ERROR, respID)" not in playernet_path.read_text(encoding="utf-8"):
        raise ValueError("current server snapshot lacks correlated processing receipts")
    return {
        "schema_version": 4, "sample_sha256": EXPECTED_SAMPLE,
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
                "semantic_name": "profession",
                "evidence_function": "0x66f030", "profession_helpers": extract_professions(sample),
                "cross_check": "0x52c268 selects destruction/nature/soul damage rows for values 0-or-3/1/2"},
            "selected_status_branch": "selector != 0 AND dispatch_magic_id != 232: elapsed > shared_cast_delay",
            "other_branch": "actor_byte_134 bit7 must be clear",
            "shared_request_tick_pointer": "0x729380", "shared_delay_pointer": "0x7299b0",
            "ordinary_cast_delay_assignment": {"instruction": "0x67d5e5", "expression": "(skill_record_u32_64 + 1200) modulo 2^32"},
            "command_delay_assignment": {"instruction": "0x67d06a", "value": 0},
            "note": "Profession, request pending flag and local animation are different inputs; current job bit flags use a different numbering.",
            "skill_delay_source": {
                "message": 97, "registration": definitions[0],
                "handler": "0x6940dc", "loader": "0x6ab2e8",
                "record_count_header_offset": 10, "record_count_header_bytes": 2,
                "record_stride_header_offset": 0, "record_stride_header_bytes": 4,
                "zero_stride_fallback": "payload_bytes / record_count (signed division in original)",
                "allocation_bytes": 102, "copied_prefix_max_bytes": 83,
                "cast_delay_u32_offset": 64,
                "learned_state_loader": "0x6aadd8 (11-byte records, does not overwrite delay)",
                "availability": "Server-provided definition prefix; actual per-skill delay values are not recovered from this executable.",
                "current_metadata": "skill.m2xmeta v2 exports coolDown, not this original delay; do not substitute it or legacy CSV Delay without evidence.",
            },
        },
        "current_transport_gap": {
            "source_snapshots": sources,
            "godot_send_action": "CM_ACTION uses fixed send without a response ID",
            "godot_generic_request_timeout_ms": 1000,
            "godot_optional_action_receipt": "send_action_request uses a response ID and expiry tick sent+10001",
            "native_cm_action": "nonzero response ID receives SM_OK after a recognized handler completes; bad owner/map/type receives SM_ERROR; response ID zero retains old behavior",
            "receipt_semantics": "Processing completion only; a rejected movement also returns SM_OK and sends its normal separate correction.",
            "native_owner_action": "on_AM_ACTION returns immediately when amA.UID == UID()",
            "gameplay_wait_gate": "main.gd routes connected CM_ACTION sends through correlated receipts; mir3_request_gate.gd serializes subsequent gameplay checks, preserves committed animation and held input, and scopes callbacks by token/owner/map",
            "local_timeout_callback": "separate from server SM_ERROR; expires pending state and denies one following check",
            "remaining_alignment_work": [
                "Adapt the now-identified profession selector while preserving current multi-job semantics.",
                "Recover per-skill server definition delay values and the identity of original exception 232 before enabling the full shared cast gate.",
                "Distinguish acceptance, failure/state correction and owner action broadcasts.",
                "Exercise real packet loss beyond the deterministic timeout boundaries and held/reordered callback fixtures.",
                "Recover the original result payload before equating any status branch with current SM_OK/SM_ERROR.",
            ],
        },
        "limits": [
            "This extractor reports evidence; the active CM_ACTION wait gate is implemented in main.gd and mir3_request_gate.gd.",
            "No RTT meaning is inferred for the original timeout global.",
            "Actor byte134 bit7 meaning and original result status semantic labels remain unresolved.",
            "Profession helper names prove the selector role; they do not recover missing server-supplied delay values or the exception 232 name.",
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sample", required=True, type=Path)
    parser.add_argument("--registry", required=True, type=Path)
    parser.add_argument("--network", required=True, type=Path)
    parser.add_argument("--playerop", required=True, type=Path)
    parser.add_argument("--playernet", required=True, type=Path)
    parser.add_argument("--main", type=Path, default=Path(__file__).resolve().parents[2] / "scripts/game/main.gd")
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    result = extract(args.sample, args.registry, args.network, args.playerop, args.playernet, args.main)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps({"timeout_ms": result["wait_gate"]["sample_default_timeout_ms"], "result_message": 99,
                      "status_selector": result["cast_permission"]["actor_status_selector"]["expression"]}))


if __name__ == "__main__":
    main()
