"""Verify original aura state messages and the supplied ActorBuff appearance map."""
import argparse
import hashlib
import json
from pathlib import Path
import struct

from export_mir3_target_history import EXPECTED_SAMPLE, read_va

EXPECTED_ACTOR_BUFF = "19f12ea396eca7a0ecf9d6b9dff6237cc920c3002f32124fb8d2bc4d5111a3f2"


def extract(sample_path, registry_path, actor_buff_path):
    sample = sample_path.read_bytes()
    if hashlib.sha256(sample).hexdigest() != EXPECTED_SAMPLE:
        raise ValueError("requires documented unpacked sample")
    registry = json.loads(registry_path.read_text(encoding="utf-8"))
    if registry["sample_sha256"] != EXPECTED_SAMPLE:
        raise ValueError("registry sample mismatch")
    registrations = []
    for message, handler in [(657, 0x6876DC), (1500, 0x68281C)]:
        rows = [row for row in registry["records"] if row["message"] == message]
        if len(rows) != 1 or rows[0]["handler"] != hex(handler):
            raise ValueError(f"unexpected registration for message{message}")
        call = int(rows[0]["call"], 16)
        context = read_va(sample, call - 24, 29)
        if (context[24] != 0xE8 or b"\x68" + struct.pack("<I", handler) not in context[:24]
                or b"\x66\xba" + struct.pack("<H", message) not in context[:24]
                or b"\x66\xb9\x06\x00" not in context[:24]):
            raise ValueError(f"registration bytes do not support message{message}")
        registrations.append({**rows[0], "context_va": hex(call - 24), "context_hex": context.hex()})
    checks = [
        (0x6876E4, "0fb75a060fb74a080fb7db0fb7c9c1e1100bd98bcb", "combine header words6/8 into actor148 value"),
        (0x6876FB, "8b5d0885db790383c303c1fb0253", "payload byte count divided by4, truncated toward zero"),
        (0x687709, "8b5dfc53510fb74a0a516a006a006a000fb74a048b1287cae8be19ffff", "forward payload, header fields and actor UID to shared dispatch"),
        (0x679219, "8bc383e82974092d680200007417", "dispatch branch41+616 equals message657"),
        (0x679248, "8b45188986940000008b451c8b00898684000000", "actor148 from header value; actor132 from first payload dword"),
        (0x67925C, "8b4d1c8b55208bc6e8c7330600", "copy payload state-vector words to actor"),
        (0x679269, "0fb645148886c6010000", "header word10 low byte becomes actor454; semantics unproven"),
        (0x67928A, "8bc68b10ff5248", "message657 invokes actor VMT+72 reconciliation"),
        (0x6DC63C, "8d433c33c9ba2c000000e88173d2ff", "state vector clears44 bytes at actor60"),
        (0x6DC64F, "8bce03c903c98d533c8bc7e8756dd2ff", "copy4 times supplied word count to actor60"),
        (0x682863, "0fb74606508d5590b9580000008d45f0e820cae0ff", "message1500 reads up to88-byte snapshot using header length"),
        (0x682893, "8b45948983940000008b4598898384000000", "snapshot dwords4/8 become actor148/132"),
        (0x6828AF, "8bc38b10ff5248", "message1500 invokes same reconciliation"),
        (0x48F2B9, "8b7df83bdf7d028bfb", "stream helper chooses minimum of record and field lengths"),
        (0x48F2D3, "8b45fc03c78b55f82bd733c9e8e846f7ff", "short snapshot field is padded with zero"),
        (0x4F70AD, "6880724f006894724f00", "appearance map filename uses ActorBuff plus.dat literals"),
        (0x4F7280, "4163746f724275666600", "ActorBuff filename literal"),
        (0x4F7294, "2e64617400", "dat suffix literal"),
        (0x4F7209, "8943048b45f48b40608bd3e87773f2ff", "store mapping value and append pair to manager96 list"),
        (0x4F6BF9, "8b003b45fc7518", "lookup compares pair key"),
        (0x4F6C0A, "8b40048b55f88902", "lookup returns matched pair value"),
        (0x6E27E9, "8b5770e8db43e1ff", "reconciliation uses actor112 as appearance mapping key"),
        (0x6DC66F, "8b7b70897370", "appearance setter replaces actor112 key"),
        (0x6E27F5, "0fb645e43c2f770783e07f0fab45fa", "mapped byte requests effect index no greater than47"),
    ]
    evidence = []
    for address, expected, role in checks:
        if read_va(sample, address, len(bytes.fromhex(expected))).hex() != expected:
            raise ValueError(f"unexpected aura state instructions at {address:#x}")
        evidence.append({"va": hex(address), "hex": expected, "role": role})
    raw = actor_buff_path.read_bytes()
    if hashlib.sha256(raw).hexdigest() != EXPECTED_ACTOR_BUFF:
        raise ValueError("requires documented ActorBuff.dat configuration")
    mappings = []
    for line in raw.decode("gb18030").splitlines():
        fields = line.split(";", 1)[0].split()
        if not fields:
            continue
        if len(fields) != 2:
            raise ValueError("unexpected ActorBuff row")
        mappings.append({"appr": int(fields[0]), "effect": int(fields[1])})
    if mappings != [{"appr": 186, "effect": 40}, {"appr": 216, "effect": 47}]:
        raise ValueError("unexpected ActorBuff mappings")
    return {
        "schema_version": 1, "sample_sha256": EXPECTED_SAMPLE,
        "registrations": registrations, "instruction_checks": evidence,
        "message657": {"handler": "0x6876dc", "shared_dispatch": "0x6790e4",
                       "actor_uid": "header dword0", "actor148": "header dword6",
                       "actor132": "first payload dword", "state_vector_actor_offset": 60,
                       "actor454": "header word10 low byte; semantics unproven",
                       "state_vector_clear_bytes": 44, "copied_words": "payload byte length divided by4",
                       "reconcile": "actor VMT+72"},
        "message1500": {"handler": "0x68281c", "snapshot_bytes": 88,
                        "actor148_field_offset": 4, "actor132_field_offset": 8,
                        "short_fields": "zero padded when stream has the declared field length",
                        "reconcile": "actor VMT+72"},
        "aura_bits": {"shield": {"actor_offset": 148, "mask": "0x100000", "effect": 1},
                      "ring": {"actor_offset": 132, "mask": "0x80000000", "effect": 2}},
        "appearance_mapping": {"loader": "0x4f7084", "lookup": "0x4f6bcc", "actor_key_setter": "0x6dc664", "actor_key_offset": 112,
                               "filename": "ActorBuff.dat", "sha256": EXPECTED_ACTOR_BUFF, "mappings": mappings,
                               "selects_shield_or_ring": any(row["effect"] in [1, 2] for row in mappings)},
        "limits": [
            "Static sample and current local configuration evidence; no original server roundtrip was captured.",
            "Message657 vector copies and message1500 snapshots are different original representations, not current mir2x wire structs.",
            "State-driven creation/removal is proven; original server duration and damage absorption remain unknown.",
            "Current ActorBuff mappings do not select1/2; other configurations may map different effects.",
            "Do not infer a fixed44-byte payload limit from a helper which clears44 bytes then copies the supplied word count.",
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sample", required=True, type=Path)
    parser.add_argument("--registry", required=True, type=Path)
    parser.add_argument("--actor-buff", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    result = extract(args.sample, args.registry, args.actor_buff)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps({"checks": len(result["instruction_checks"]), "messages": [657, 1500],
                      "appearance_mappings": len(result["appearance_mapping"]["mappings"])}))


if __name__ == "__main__":
    main()
