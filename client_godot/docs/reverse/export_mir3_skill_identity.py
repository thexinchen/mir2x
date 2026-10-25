"""Join the original client's upgrade resource with current skill identities.

This establishes resource IDs, not missing server skill-record mode/delay bytes.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import xml.etree.ElementTree as ET
from compare_mir3_skill_descriptions import header
from export_mir3_target_history import EXPECTED_SAMPLE, read_va
from export_mir3_skill_learning import extract_learning_evidence


def extract(sample_path, upgrades_path, sprites, history_path, magic_records_path):
    sample = sample_path.read_bytes()
    if hashlib.sha256(sample).hexdigest() != EXPECTED_SAMPLE:
        raise ValueError("requires the documented unpacked Mir3 sample")
    if read_va(sample, 0x627914, 19) != b"MagicUpgradeSetting":
        raise ValueError("unexpected original resource loader name")
    learning = extract_learning_evidence(sample)
    raw = upgrades_path.read_bytes()
    tree = ET.fromstring(raw)  # XML declaration/BOM determines UTF-8 encoding.
    if tree.tag != "RES_MAGIC":
        raise ValueError("unexpected original skill resource root")
    by_name, by_id = {}, {}
    row_count = 0
    for node in tree:
        if node.tag != "VALUE":
            raise ValueError("unexpected original skill resource record")
        sid = int(node.attrib["MAGIC_ID"])
        name = node.attrib["MAGIC_NAME"]
        level = int(node.attrib["MAGIC_LEVEL"])
        if not 0 < sid <= 65535 or not name or not 0 <= level <= 255:
            raise ValueError("original skill ID/name/level outside loader range")
        if name in by_name and by_name[name]["id"] != sid:
            raise ValueError(f"ambiguous original name: {name}")
        if sid in by_id and by_id[sid] != name:
            raise ValueError(f"ambiguous original ID: {sid}")
        by_name.setdefault(name, {"id": sid, "levels": []})["levels"].append(level)
        by_id[sid] = name
        row_count += 1

    names_raw = (sprites / "magic_name.m2xmeta").read_bytes()
    _, count = header(names_raw, [1])
    names, offset = {}, 12
    for _ in range(count):
        sid, length = struct.unpack_from("<IH", names_raw, offset)
        offset += 6
        names[sid] = names_raw[offset:offset + length].decode("utf-8")
        offset += length
    if offset != len(names_raw) or len(names) != count:
        raise ValueError("invalid current name metadata length/duplicates")
    skills_raw = (sprites / "skill.m2xmeta").read_bytes()
    version, count = header(skills_raw, [1, 2])
    fmt = "<IIIBBBB" if version == 2 else "<IIBBBB"
    offset, current_ids = 12, []
    for _ in range(count):
        current_ids.append(struct.unpack_from(fmt, skills_raw, offset)[0])
        offset += struct.calcsize(fmt)
    if offset != len(skills_raw) or len(set(current_ids)) != count:
        raise ValueError("invalid current skill metadata length/duplicates")

    history_raw = history_path.read_bytes()
    history = json.loads(history_raw)
    if history["sample_sha256"] != EXPECTED_SAMPLE:
        raise ValueError("history evidence sample mismatch")
    lock_ids = set(history["explicit_lock_target"]["enabled_base_ids"])
    positive_history_ids = set(history["predicate"]["static_enabled_ids"]) | set(history["config"]["enabled_ids"])
    records_raw = magic_records_path.read_bytes()
    records = records_raw.decode("utf-8")
    starts = list(re.finditer(r'^\{\s+\.name\s*=\s*u8"([^"]+)"', records, re.M))
    current_records = {}
    for index, match in enumerate(starts):
        end = starts[index + 1].start() if index + 1 < len(starts) else len(records)
        current_records[match[1]] = records[match.start():end]

    rows = []
    for current_id in sorted(current_ids):
        name = names[current_id]
        original_name = name
        match_type = "exact_name"
        alias_evidence = None
        if name == "异形换位" and name not in by_name:
            # Explicit spelling alias, independently anchored by the current
            # record's original-MagID sound reference. Never fuzzy-match names.
            original_name = "移形换位"
            record = current_records.get(name, "")
            sound = re.search(r"\.seffBase\s*=\s*(\d+)", record)
            if not sound or int(sound[1]) != 104 or by_name.get(original_name, {}).get("id") != 104:
                raise ValueError("unverified teleport spelling alias")
            match_type = "explicit_spelling_alias"
            alias_evidence = "current MagicRecord.seffBase=104; original resource MAGIC_ID=104 and MAGIC_NAME=移形换位"
        original = by_name.get(original_name)
        original_id = original["id"] if original else None
        rows.append({"current_id": current_id, "current_name": name,
                     "original_resource_id": original_id,
                     "original_resource_name": original_name if original else None,
                     "original_dispatch_id_after_exact_learn_update": original_id,
                     "match": match_type if original else "unmapped",
                     "alias_evidence": alias_evidence,
                     "explicit_lock_allowed": original_id in lock_ids if original else None,
                     "history_known_positive": original_id in positive_history_ids if original else None,
                     "history_negative_is_final": False})
    return {"schema_version": 2, "sample_sha256": EXPECTED_SAMPLE,
            "source_sha256": {"original_upgrades": hashlib.sha256(raw).hexdigest(),
                              "current_names": hashlib.sha256(names_raw).hexdigest(),
                              "current_skills": hashlib.sha256(skills_raw).hexdigest(),
                              "target_history_evidence": hashlib.sha256(history_raw).hexdigest(),
                              "current_magic_records": hashlib.sha256(records_raw).hexdigest()},
            "original_loader": {"function": "0x62761c", "filename_va": "0x627914",
                                "filename": "MagicUpgradeSetting.dat", "id_assignment": "0x62775f",
                                "name_assignment": "0x627795", "name_max_encoded_bytes": 30},
            "original_resource_rows": row_count, "original_resource_names": len(by_name),
            "normal_learning_path": learning,
            "skills": rows,
            "limits": ["Resource identity does not recover server record byte81 target mode or byte64 delay.",
                       "Exact lookup/learn update assigns matched base ID to dispatch ID; this relation is scoped to that update path, not every possible later write.",
                       "Known-positive history permission combines static/config evidence; a negative remains unknown because server mode1 can enable it.",
                       "Explicit-lock permission uses the separate recovered base-ID predicate.",
                       "The one spelling alias is explicit and source-checked; no fuzzy name matching or King_Magic.csv inference is used."]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sample", required=True, type=Path)
    parser.add_argument("--upgrades", required=True, type=Path)
    parser.add_argument("--sprites", required=True, type=Path)
    parser.add_argument("--history", required=True, type=Path)
    parser.add_argument("--magic-records", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    result = extract(args.sample, args.upgrades, args.sprites, args.history, args.magic_records)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps({"original_names": result["original_resource_names"],
                      "exact": sum(row["match"] == "exact_name" for row in result["skills"]),
                      "aliases": sum(row["match"] == "explicit_spelling_alias" for row in result["skills"]),
                      "unmapped": [row["current_name"] for row in result["skills"] if row["match"] == "unmapped"]}, ensure_ascii=True))


if __name__ == "__main__":
    main()
