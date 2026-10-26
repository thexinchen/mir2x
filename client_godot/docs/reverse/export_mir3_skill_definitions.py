"""Recover message97 skill-definition fields and decode original buffers offline.

No current mir2x cost, cooldown or targeting rule is inferred from these fields.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct

from export_mir3_target_history import EXPECTED_SAMPLE, read_va


CHECKS = [
    (0x6940E4, "8b8080030000e8f9710100", "message97 delegates to skill-definition loader"),
    (0x6AB312, "0fb7590abf530000008b3185f67510", "count from header WORD10 and stride from DWORD0"),
    (0x6AB321, "0fb7410a508b45085a8bca99f7f98bf0", "zero stride uses signed payload length divided by count"),
    (0x6AB331, "3bf77e048bc7eb028bc68945f0", "copy prefix is signed minimum of stride and83"),
    (0x6AB33E, "8bc3f76df03b45080f8fe00000008bfb4f85ff0f8cd5000000", "original bounds guard uses copied prefix times count, not final stride offset"),
    (0x6AB365, "b866000000e8d1b0d5ff8bd88bc333c9ba66000000e84d86d5ff", "allocate102 bytes and zero the entire runtime record"),
    (0x6AB37F, "8b45f4f7ee8b55f88d04028bd38b4df0e84080d5ff", "copy each prefix from payload plus stride times record index"),
    (0x6AB3CD, "807b5201752d", "record byte82 equals1 invokes additional callback"),
    (0x6AB400, "807b5200750f8b45fc8b40108bd3e87d31d7ffeb0d8b45fc8b401c8bd3e86e31d7ff", "byte82 selects main list16 or alternate list28"),
    (0x67CFD3, "0fb746448b15c09372008b123b826d0100000f8f57060000", "manual admission compares unsigned record WORD68 against signed actor MP365"),
    (0x67CFEB, "807e4c000f8539050000", "record byte76 selects ordinary cast versus command branch"),
    (0x67C9FE, "807b51027514", "target resolver branches on raw definition byte81 equals2"),
    (0x67D5D7, "8b464005b00400008b15b09972008902", "ordinary cast stores record DWORD64 plus1200 with32-bit wrap"),
    (0x67D5E7, "8b46408b15c09372008b128982dc0c0000", "actor3292 separately receives unmodified record DWORD64"),
]


def decode_definitions(header, payload):
    if len(header) != 12:
        raise ValueError("requires exactly12 original header bytes")
    stride, message, _, _, count = struct.unpack("<i4H", header)
    if message != 97:
        raise ValueError("requires original skill-definition message97")
    if stride < 0:
        raise ValueError("negative signed stride is unsafe in the original copy")
    declared_stride = stride
    if stride == 0:
        if count == 0:
            raise ValueError("original zero-stride zero-count division is undefined")
        stride = len(payload) // count
    copied = min(stride, 83)
    if copied * count > len(payload):
        raise ValueError("original copied-prefix length guard rejects this payload")
    last_end = (count - 1) * stride + copied if count else 0
    if last_end > len(payload):
        raise ValueError("last copied prefix exceeds payload despite the original coarse guard")
    records = []
    for index in range(count):
        offset = index * stride
        raw = payload[offset:offset + copied]
        prefix = raw + bytes(83 - copied)
        delay = struct.unpack_from("<I", prefix, 64)[0]
        records.append({"wire_index": index, "payload_offset": offset,
                        "copied_prefix_hex": raw.hex(), "definition_prefix83_hex": prefix.hex(),
                        "base_id": struct.unpack_from("<H", prefix)[0],
                        "cast_delay_u32": delay, "shared_cast_delay_plus1200_u32": (delay + 1200) & 0xFFFFFFFF,
                        "manual_mp_threshold_u16": struct.unpack_from("<H", prefix, 68)[0],
                        "raw_byte72": prefix[72], "command_branch_byte76": prefix[76],
                        "target_mode_byte81": prefix[81], "pool_selector_byte82": prefix[82],
                        "pool": "alternate" if prefix[82] else "main",
                        "byte82_equals1_callback": prefix[82] == 1})
    return {"declared_stride_i32": declared_stride, "effective_stride": stride, "count": count,
            "copied_prefix_bytes": copied, "payload_bytes": len(payload),
            "last_copy_end": last_end, "records_in_wire_order": records}


def extract(sample_path, registry_path):
    sample = sample_path.read_bytes()
    if hashlib.sha256(sample).hexdigest() != EXPECTED_SAMPLE:
        raise ValueError("requires documented unpacked Mir3 sample")
    for address, expected, label in CHECKS:
        if read_va(sample, address, len(bytes.fromhex(expected))).hex() != expected:
            raise ValueError(f"unexpected skill-definition instruction at {address:#x}: {label}")
    registry = json.loads(registry_path.read_text(encoding="utf-8"))
    rows = [r for r in registry["records"] if r["message"] == 97]
    if registry["sample_sha256"] != EXPECTED_SAMPLE or len(rows) != 1 or any(rows[0].get(k) != v for k, v in {
        "handler": "0x6940dc", "call": "0x691031", "registration_ecx": 6, "register_function": "0x690d74",
    }.items()):
        raise ValueError("unexpected skill-definition registration")
    return {"schema_version": 1, "sample_sha256": EXPECTED_SAMPLE,
            "instruction_checks": [{"va": hex(a), "hex": c, "role": label} for a, c, label in CHECKS],
            "registration": rows[0], "loader": "0x6ab2e8",
            "header": {"bytes": 12, "stride_signed32_offset": 0, "message_u16_offset": 4, "count_u16_offset": 10},
            "copy": {"runtime_record_bytes": 102, "zero_before_copy": True, "maximum_wire_prefix_bytes": 83,
                     "stride_zero": "signed payload length/count for nonnegative lengths; count0 would divide by zero",
                     "original_guard": "min(stride,83)*count <= payload_length using32-bit signed arithmetic",
                     "decoder_guard": "also require the last actually copied prefix to fit; reject negative stride instead of reproducing unsafe reads"},
            "fields": {"base_id_u16": 0, "cast_delay_u32": 64, "manual_mp_threshold_u16": 68,
                       "raw_byte72": 72, "command_branch_byte76": 76, "target_mode_byte81": 81, "pool_selector_byte82": 82},
            "derived": {"ordinary_shared_delay": "(record DWORD64+1200) modulo2^32", "actor3292": "unmodified record DWORD64",
                        "pool": "byte82==0 main, otherwise alternate; byte82==1 also invokes56385C"},
            "limits": ["These are server-supplied definitions. No actual original message97 payload was supplied, so real per-skill values remain unknown.",
                       "The MP field is proven as a manual admission threshold, not proof of server MP deduction or a current MagicRecord.mp formula.",
                       "Decoder output preserves wire order and duplicate IDs before original sorting/derived callbacks; names and heap pointers are not reconstructed.",
                       "Only the zero-padded83-byte wire prefix is modeled. Runtime description strings, derived byte101 and post-load alternate processing are separate.",
                       "The decoder rejects malformed buffers and does not model original overflow/overread/division faults or mutate Godot gameplay."]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sample", required=True, type=Path)
    parser.add_argument("--registry", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--header", type=Path)
    parser.add_argument("--payload", type=Path)
    args = parser.parse_args()
    if (args.header is None) != (args.payload is None):
        parser.error("--header and --payload must be supplied together")
    result = extract(args.sample, args.registry)
    if args.header is not None:
        result["decoded_definitions"] = decode_definitions(args.header.read_bytes(), args.payload.read_bytes())
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps({"checks": len(CHECKS), "message": 97, "production_gameplay_changed": False}))


if __name__ == "__main__":
    main()
