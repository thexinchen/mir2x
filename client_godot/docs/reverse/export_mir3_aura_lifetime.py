"""Verify original owner-aura loop and shield-hit lifetime instructions."""
import argparse
import hashlib
import json
from pathlib import Path

from export_mir3_target_history import EXPECTED_SAMPLE, read_va


def extract(path):
    sample = path.read_bytes()
    if hashlib.sha256(sample).hexdigest() != EXPECTED_SAMPLE:
        raise ValueError("requires documented unpacked sample")
    checks = [
        (0x6E2CA4, "0c544d61676963536865696c64", "Pascal class name TMagicSheild"),
        (0x6E2D0C, "0d544d61676963536865696c6432", "Pascal class name TMagicSheild2"),
        (0x6E2C98, "cc466e0064346e0044346e00", "shield VMT: draw, update, initialize"),
        (0x6E2D00, "cc466e00bc486e00844a6e00", "shield2 VMT: draw, update, initialize"),
        (0x6DAA00, "6a7a8bc8b201a1b42c6e00e8b48a0000", "owner-state factory creates shield2 resource122"),
        (0x6E3409, "6a016a006aff6a0033d28bc6e8ee110000", "shield constructor passes negative cycle counter"),
        (0x6E34DD, "6a016a006aff6a0033d28bc6e81a110000", "shield2 constructor passes negative cycle counter"),
        (0x6E4620, "0fb64514500fb64510508b450c508b4d1833d28bc7e82a030000", "owner constructor forwards counter to base constructor"),
        (0x6E4993, "8b4508894718", "base constructor stores counter at offset24"),
        (0x6E4BA7, "89460cff46080fb7463a3b46087f26", "update increments frame and compares end-exclusive frame"),
        (0x6E4BBC, "0fb74638894608837e18007e13ff4e18837e1800750ac6460401", "wrap frame; decrement only positive counters; mark done at zero"),
        (0x6E34A5, "885068c7401801000000", "hit switches flag and sets one cycle"),
        (0x6E34AF, "0fb750306603503c668950386603503c6689503a", "hit frame range is start+count through start+2count"),
        (0x6E346C, "e84b14000084c07527", "shield update waits for owner update to finish"),
        (0x6E3475, "807b68007421", "only hit state restores run after completion"),
        (0x6E347B, "0fb74330668943386603433c6689433a", "restore original run frame range"),
        (0x6E348B, "c6430400c74318ffffffffc6436800b001", "clear done, restore counter=-1, clear hit, return alive"),
        (0x6DA66C, "60256e00", "actor VMT+72 is state-aura reconciliation"),
        (0x6DB6D7, "83f820740583f8227524c6437c018bc38b10ff5248", "death actions32/34 set dead flag124 then call VMT+72"),
        (0x6E2904, "000000000000", "initial desired-aura bitset is empty"),
        (0x6E256B, "8b0504296e008945fa668b0508296e00668945fe", "initialize six-byte desired set from empty constant"),
        (0x6E257F, "807f7c000f8556020000", "dead actor skips ordinary status-derived aura bits"),
        (0x6E2595, "8b9f94000000f7c3000010007e04804dfa02", "actor+148 mask0x100000 requests effect1, shield"),
        (0x6E25B3, "8b9f84000000f7c3000000807604804dfa04", "actor+132 mask0x80000000 requests effect2, ring"),
        (0x6E283A, "8bf08bc68b15e02b6e00e88b1bd2ff", "reconcile only effects deriving from aura base class"),
        (0x6E2853, "0fb646603c2f770783e07f0fa345fa7311", "effect96 indexes desired set; absent bit jumps to done"),
        (0x6E2875, "c6460401", "mark obsolete aura done"),
        (0x6E28DA, "8bd38bc78b08ff51048bf085f6740d885e608bd68b4708e83623dbff", "create missing desired aura, assign effect96, append to actor list"),
    ]
    evidence = []
    for address, expected, role in checks:
        if read_va(sample, address, len(bytes.fromhex(expected))).hex() != expected:
            raise ValueError(f"unexpected aura instruction at {address:#x}")
        evidence.append({"va": hex(address), "hex": expected, "role": role})
    return {
        "schema_version": 1, "sample_sha256": EXPECTED_SAMPLE,
        "instruction_checks": evidence,
        "fields": {"done": 4, "frame": 8, "last_tick": 12,
                   "hold_final_frame": 20, "remaining_cycles": 24,
                   "resource_start": 48, "frame_interval_ms": 52,
                   "begin_frame": 56, "end_frame_exclusive": 58,
                   "frame_count": 60, "owner": 80, "shield_hit": 104},
        "findings": {
            "constructors": ["0x6e33f0", "0x6e34c4"],
            "negative_cycles": "wrap without decrement; no local fixed-cycle expiry",
            "positive_cycles": "decrement on wrap; done when decremented to zero",
            "shield_hit": "one hit cycle then restore original run range and counter=-1",
            "ring_identity": "owner-state factory constructs TMagicSheild2 using resource122",
            "state_reconciliation": "0x6e2560 retires absent status auras and creates missing desired auras via VMT+4",
            "death": "actions32/34 set actor124 and invoke reconciliation; ordinary state-derived shield/ring bits are skipped",
        },
        "baseline_commit": "830dc79",
        "baseline_gaps": [
            "Baseline Godot discards shield and ring after two cycles.",
            "Baseline Godot restores two cycles after shield hit, rather than indefinite run.",
            "Baseline resource exporter selects first run entry and omits later loop continuation.",
            "Baseline server sends shield OFF after10s for both shield and ring; ring needs its own matching termination.",
            "Repeated casts need stale-expiry protection and same-kind attachment replacement.",
        ],
        "limits": [
            "Negative cycle counter proves local animation persistence, not permanent gameplay protection.",
            "State-driven removal is proven; original server duration, absorption and map replay remain unproven.",
            "Current server10s duration is an adapter behavior, not recovered original duration.",
            "Resource122 mapping uses existing independently verified skill identity; it is not an original network capture.",
            "External appearance mapping provenance is documented by mir3-aura-state.json; this lifetime extractor alone does not inspect its configuration.",
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sample", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    result = extract(args.sample)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n",
                           encoding="utf-8", newline="\n")
    print(json.dumps({"checks": len(result["instruction_checks"]),
                      "negative_cycles": -1, "hit_cycles": 1}))


if __name__ == "__main__":
    main()
