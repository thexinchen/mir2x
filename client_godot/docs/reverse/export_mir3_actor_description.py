"""Trace the original manual-use flag to server descriptions; decode offline payloads."""
import argparse
import hashlib
import json
from pathlib import Path
import struct

from export_mir3_target_history import EXPECTED_SAMPLE, read_va


CHECKS = [
    (0x6DC461, "8bf28d7828b910000000f3a5", "copy64 bytes to actor40"),
    (0x6DC46D, "8b15c09372003b027417", "local actor skips remote side effects"),
    (0x6DC477, "807828030f94c28890f8020000", "remote actor760 is description byte0 equals3"),
    (0x6DF7F4, "f64035080f95c0c3", "manual-use flag is actor byte53 mask8"),
    (0x687467, "837d084c7c2f", "message41 requires76 payload bytes"),
    (0x687476, "85db7422", "message41 ignores an unknown actor"),
    (0x68747A, "8bc68b108993800000008d500c8bc3e8ce4f0500", "message41 description starts at payload12"),
    (0x68878D, "817d08820000000f8c62020000", "message50 requires130 payload bytes"),
    (0x688875, "8d45bc33c9ba40000000e848b1d7ff", "message50 clears a64-byte description"),
    (0x688884, "8d55bc8d4339b914000000e840abd7ff", "message50 copies20 bytes from payload57"),
    (0x688894, "8d55bca1c09372008b00e8b93b0500", "message50 applies the padded local description"),
    (0x682863, "0fb74606508d5590b9580000008d45f0e820cae0ff", "message1500 reads header word6 into88-byte snapshot"),
    (0x6828A5, "8d55a88bc3e8ad9b0500", "message1500 applies description at snapshot24"),
    (0x48F2B9, "8b7df83bdf7d028bfb", "stream copy uses minimum of record and declared lengths"),
    (0x48F2D3, "8b45fc03c78b55f82bd733c9e8e846f7ff", "short available field is zero padded"),
]


def decode_description(description):
    if len(description) != 64:
        raise ValueError("description must contain exactly64 bytes")
    flags = description[13]
    return {"description_hex": description.hex(), "actor_byte53": flags,
            "manual_use_guard_set": bool(flags & 8)}


def decode_message41(payload):
    if len(payload) < 76:
        raise ValueError("message41 payload requires at least76 bytes")
    result = decode_description(payload[12:76])
    result["actor128_u32"] = struct.unpack_from("<I", payload)[0]
    return result


def decode_message50(payload):
    if len(payload) < 130:
        raise ValueError("message50 payload requires at least130 bytes")
    return decode_description(payload[57:77] + bytes(44))


def decode_snapshot1500(field, declared_length):
    # Input begins at the snapshot field, after the original stream envelope.
    # Match the available-field copy/pad/skip contract, never uninitialized data.
    if not 0 <= declared_length <= 0xFFFF:
        raise ValueError("snapshot field length must fit header WORD6")
    if len(field) < declared_length:
        raise ValueError("snapshot stream does not contain the declared field")
    snapshot = field[:min(declared_length, 88)].ljust(88, b"\0")
    result = decode_description(snapshot[24:88])
    result["consumed_field_bytes"] = declared_length
    return result


def extract(sample_path, registry_path):
    sample = sample_path.read_bytes()
    if hashlib.sha256(sample).hexdigest() != EXPECTED_SAMPLE:
        raise ValueError("requires documented unpacked sample")
    for address, code, label in CHECKS:
        if read_va(sample, address, len(bytes.fromhex(code))).hex() != code:
            raise ValueError(f"unexpected {label} at {address:#x}")
    registry = json.loads(registry_path.read_text(encoding="utf-8"))
    if registry["sample_sha256"] != EXPECTED_SAMPLE:
        raise ValueError("registry sample mismatch")
    registrations = []
    for message, handler, call, mode in [(41, "0x687460", "0x67f05d", 6),
                                         (50, "0x68875c", "0x67f1ec", 14),
                                         (1500, "0x68281c", "0x67f2fd", 6)]:
        rows = [r for r in registry["records"] if r["message"] == message]
        expected = {"handler": handler, "call": call, "registration_ecx": mode, "register_function": "0x67ea1c"}
        if len(rows) != 1 or any(rows[0].get(key) != value for key, value in expected.items()):
            raise ValueError(f"unexpected actor description handler for{message}")
        registrations.extend(rows)
    return {
        "schema_version": 1, "sample_sha256": EXPECTED_SAMPLE,
        "instruction_checks": [{"va": hex(a), "hex": c, "role": label} for a, c, label in CHECKS],
        "registrations": registrations,
        "description": {"setter": "0x6dc45c", "actor_offset": 40, "bytes": 64,
                        "manual_use_flag": {"description_offset": 13, "actor_offset": 53,
                                            "mask": 8, "semantic_name": None},
                        "remote_only_side_effect": "description byte0==3 sets actor760; local actor bypasses this assignment"},
        "message41": {"handler": "0x687460", "minimum_payload_bytes": 76,
                      "actor128_u32_offset": 0, "description_offset": 12,
                      "description_bytes": 64, "manual_flag_payload_offset": 25,
                      "requires_known_actor": True},
        "message50": {"handler": "0x68875c", "minimum_payload_bytes": 130,
                      "description_prefix_offset": 57, "copied_prefix_bytes": 20,
                      "zero_tail_bytes": 44, "manual_flag_payload_offset": 70,
                      "actor": "current local actor after creation"},
        "message1500": {"handler": "0x68281c", "snapshot_field_length": "original header WORD6",
                        "snapshot_bytes": 88, "description_snapshot_offset": 24,
                        "manual_flag_snapshot_offset": 37,
                        "copy": "copy min(declared_length,88), zero-pad short available field, skip declared excess",
                        "decoder_input": "snapshot field bytes after original stream envelope, not raw framed or compressed wire data"},
        "current_gap": "Current SM_PLAYERWLDESP is a different structure. No equivalent current field or Buff has been established; no runtime item-use restriction is added.",
        "limits": ["The source is a server-supplied appearance description; its mask8 business meaning remains unresolved.",
                   "This predicate gates original manual690494; do not apply it to automatic or Book paths without separate evidence.",
                   "Offline decoders do not perform UID lookup, update GameState or implement original transport framing.",
                   "Insufficient snapshot input is rejected rather than emulating the original caller's uninitialized destination after a failed stream read.",
                   "Synthetic payload checks validate field interpretation, not a captured original server roundtrip."]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sample", required=True, type=Path)
    parser.add_argument("--registry", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--payload", type=Path)
    parser.add_argument("--payload-kind", choices=["message41", "message50", "snapshot1500"])
    parser.add_argument("--field-length", type=int)
    args = parser.parse_args()
    if bool(args.payload) != bool(args.payload_kind):
        parser.error("--payload and --payload-kind must be supplied together")
    if (args.payload_kind == "snapshot1500") != (args.field_length is not None):
        parser.error("--field-length is required only for snapshot1500")
    result = extract(args.sample, args.registry)
    if args.payload:
        data = args.payload.read_bytes()
        decoder = {"message41": decode_message41, "message50": decode_message50}.get(args.payload_kind)
        result["decoded_payload"] = decoder(data) if decoder else decode_snapshot1500(data, args.field_length)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps({"checks": len(CHECKS), "registrations": len(result["registrations"]), "runtime_changed": False}))


if __name__ == "__main__":
    main()
