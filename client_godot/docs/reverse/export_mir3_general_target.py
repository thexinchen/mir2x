"""Recover the general resolver's projection rule without assuming target modes."""
import argparse
import hashlib
import json
from pathlib import Path
from export_mir3_target_history import EXPECTED_SAMPLE, read_va


def extract(sample_path, identity_path):
    sample = sample_path.read_bytes()
    if hashlib.sha256(sample).hexdigest() != EXPECTED_SAMPLE:
        raise ValueError("requires the documented unpacked sample")
    code = read_va(sample, 0x67CE63, 0x27)
    expected = bytes.fromhex("0fb743548bd083c2f86683fa77770a83e27f0fa31534cf6700720c663d2e017406663d2002752a")
    if code != expected:
        raise ValueError("general resolver branch no longer matches verified instructions")
    bitmap = read_va(sample, 0x67CF34, 16)
    ids = [8 + bit for bit in range(120) if bitmap[bit // 8] & (1 << (bit % 8))] + [302, 544]
    raw_identity = identity_path.read_bytes()
    identity = json.loads(raw_identity)
    if identity["sample_sha256"] != EXPECTED_SAMPLE:
        raise ValueError("identity evidence sample mismatch")
    if not identity["normal_learning_path"]["dispatch"]["equals_matched_base_id_after_this_update"]:
        raise ValueError("missing exact-ID learning evidence")
    candidates = [{"current_name": row["current_name"], "original_resource_id": row["original_resource_id"],
                   "dispatch_id_after_exact_learn_update": row["original_dispatch_id_after_exact_learn_update"],
                   "explicit_lock_allowed": row["explicit_lock_allowed"]}
                  for row in identity["skills"] if row["original_resource_id"] in ids]
    return {"schema_version": 2, "sample_sha256": EXPECTED_SAMPLE,
            "identity_sha256": hashlib.sha256(raw_identity).hexdigest(),
            "general_resolver": "0x67cc08",
            "setting_forced_route": {"branch": "0x67c98a", "expression": "explicit lock permission AND setting enabled",
                                     "requires_a_valid_locked_actor": False},
            "projection": {"branch_va": "0x67ce63", "branch_hex": code.hex(),
                           "input": "record uint16 dispatch ID at offset 84; NOT base ID at offset 0",
                           "bitmap_va": "0x67cf34", "bitmap_hex": bitmap.hex(),
                           "bitmap_first_id": 8, "bitmap_last_id": 127, "dispatch_ids": ids,
                           "coordinate_assignment": "0x67ce94/0x67cea3 reset aim to player tile; 0x67ceaf steps once using pre-adjustment direction",
                           "uid_preserved": True,
                           "final_actor_direction": "0x67cef2 runs AFTER projection; may differ from the direction used for the projected tile"},
            "current_resource_candidates": candidates,
            "limits": ["Exact-ID learning sets dispatch ID equal to matched base ID; candidate dispatch IDs apply after that verified update path, not arbitrary other writes.",
                       "The runtime adapter applies the recovered projection to current 抗拒火环 only in the proven setting-forced general route.",
                       "Other general-mode entries depend on missing original server record byte81; do not globally project self spells from this table.",
                       "Current/history target storage remains incomplete; negative static history permission is not a denial."]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sample", required=True, type=Path)
    parser.add_argument("--identity", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    result = extract(args.sample, args.identity)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps({"projection_dispatch_ids": result["projection"]["dispatch_ids"],
                      "resource_candidates": len(result["current_resource_candidates"])}, ensure_ascii=True))


if __name__ == "__main__":
    main()
