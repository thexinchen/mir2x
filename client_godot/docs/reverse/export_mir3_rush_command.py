"""Recover the original legacy27 command without inventing server movement.

The packet helper returns only the copied default header plus four payload
bytes. It is evidence replay, not a current mir2x packet or a live sender.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct

from export_mir3_target_history import EXPECTED_SAMPLE, read_va


CHECKS = [
    (0x67CFD3, "0fb746448b15c09372008b123b826d0100000f8f57060000", "server skill WORD68 must not exceed actor MP365 before cast/command branch"),
    (0x67CFEB, "807e4c000f8539050000", "record byte76 selects ordinary-cast branch when nonzero"),
    (0x67D026, "6683e81b74066683e8097515", "legacy27 and36 share the impulse readiness check"),
    (0x67D032, "a1f09772008bd62b1081fab80b00000f8211060000", "unsigned elapsed below3000 rejects shared impulse entry"),
    (0x67D047, "a1809372008bd62b1081faf40100000f82fc050000", "command check requires elapsed500 or more"),
    (0x67D05C, "a1809372008930a1b099720033d28910", "accepted command stamps common clock and zeros actor payload delay"),
    (0x67D223, "e88ca3ffff", "rush reads current screen mouse through6775B4"),
    (0x67D228, "6a000fb7c3506a00", "rush pushes zero payload high parameter, legacy magic ID and zero default-header parameter"),
    (0x67D24B, "e8d81908000fb6c8", "rush uses6FEC28 tile-direction result as unsigned direction argument"),
    (0x67D25A, "bac90b0000e88c430100", "rush sends direct3017 command through6915F0, not enqueue"),
    (0x69160D, "0fb74dfc8b55088bc7e841a20300", "direct command builds12-byte default header from direction and stack arguments"),
    (0x6CB863, "89136689430466894b060fb74510668943080fb7450c6689430a", "default header layout DWORD0 then WORD message/direction/parameter/magicID"),
    (0x69164B, "6a048d8bdc0c00008d55f0a19c9672008b00e822af0300", "send copied default header with four-byte actor3292 payload"),
    (0x691662, "33c08983dc0c00008bc3e8effbffff", "after direct send clear actor3292 and mark action pending"),
    (0x691266, "c683f00c000001e88ef907008983f80c0000", "direct request marks actor3312 pending and stores send tick3320"),
    (0x683A23, "3b420c0f85a8000000", "received message6 stamps impulse clock only for local actor UID"),
    (0x683A2C, "e8cfd108008b15f09772008902", "received local message6 refreshes shared impulse tick"),
]


def encode_unframed_command(direction):
    if not isinstance(direction, int) or isinstance(direction, bool) or not 0 <= direction < 8:
        raise ValueError("original direction must be0..7")
    return struct.pack("<IHHHHI", 0, 3017, direction, 0, 27, 0)


def extract(path, identity_path=None):
    sample = path.read_bytes()
    if hashlib.sha256(sample).hexdigest() != EXPECTED_SAMPLE:
        raise ValueError("requires documented unpacked sample")
    evidence = []
    for address, expected, role in CHECKS:
        if read_va(sample, address, len(bytes.fromhex(expected))).hex() != expected:
            raise ValueError(f"unexpected instruction at {address:#x}: {role}")
        evidence.append({"va": hex(address), "hex": expected, "role": role})
    identity_path = identity_path or Path(__file__).with_name("mir3-skill-identity.json")
    raw_identity = identity_path.read_bytes()
    identity = json.loads(raw_identity)
    rows = [row for row in identity["skills"] if row["current_name"] == "野蛮冲撞"]
    if identity["sample_sha256"] != EXPECTED_SAMPLE or len(rows) != 1 or rows[0]["current_id"] != 39 or rows[0]["original_resource_id"] != 27 or rows[0]["original_dispatch_id_after_exact_learn_update"] != 27 or rows[0]["match"] != "exact_name":
        raise ValueError("rush identity no longer matches documented join")
    return {
        "schema_version": 1, "sample_sha256": EXPECTED_SAMPLE, "instruction_checks": evidence,
        "identity": {"name": "野蛮冲撞", "original_dispatch_id": 27, "current_mir2x_id": 39,
                     "identity_source": "mir3-skill-identity.json exact learned/resource name join",
                     "identity_sha256": hashlib.sha256(raw_identity).hexdigest()},
        "branch": {"function": "0x67cf44", "condition": "skill record byte76==0 and dispatch WORD84==27",
                   "mp_gate": "server-provided skill WORD68 <= raw actor MP365; original cost formula/values not established here",
                   "focus": "does not call ordinary target resolver67C954, does not adopt focus/history/lock UID",
                   "direction": "fresh screen-to-tile6775B4, then6FEC28 from actor tile to mouse tile; not screen-sector6FEE68",
                   "local_motion": "no action enqueue or predicted displacement in this direct request branch"},
        "request": {"sender": "0x6915f0", "original_command": 3017, "magic_id": 27,
                    "header": {"bytes": 12, "u32_at0": 0, "u16_at4": 3017, "u16_at6": "direction0..7", "u16_at8": 0, "u16_at10": 27},
                    "payload": {"bytes": 4, "u32": "actor3292, cleared to0 before this switch"},
                    "examples_without_outer_framing": [encode_unframed_command(i).hex() for i in range(8)],
                    "pending": "after send, set actor3312=1 and actor3320=now via691260"},
        "timing": {"common_command_gate_ms": 500, "shared_impulse_gate_ms": 3000,
                   "common_clock": "accepted entry stamps729380 before switch",
                   "kick_clock": "legacy36 stamps7297F0 at request entry67D081",
                   "rush_clock": "legacy27 does not stamp7297F0 in its send branch; local server message6 stamps it at683A37",
                   "mapping_limit": "Original message6 is not current ActionType6. Current SpaceMove must not be assigned this clock side effect solely by numeric equality."},
        "current_gap": "Godot still lacks a verified rush dispatch/settlement path; Player::onCMActionSpell has no rush case. This artifact is not permission to send original bytes over mir2x or fabricate travel distance, push eligibility, damage, MP cost or animation."
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sample", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    result = extract(args.sample)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps({"checks": len(result["instruction_checks"]), "directions": 8, "current_skill_supported": False}))
