"""Recover exact-ID lookup and field writes in the original skill-learn update."""
import argparse
import hashlib
import json
from pathlib import Path
from export_mir3_target_history import EXPECTED_SAMPLE, read_va


def extract_learning_evidence(sample):
    if hashlib.sha256(sample).hexdigest() != EXPECTED_SAMPLE:
        raise ValueError("requires the documented unpacked sample")
    checks = [
        (0x6AADE1, "0fb7138bc6e871030000", "read payload WORD ID and call main lookup"),
        (0x6AB180, "0fb7103b55fc7406", "main lookup compares record WORD at offset0 to requested ID"),
        (0x6AADF1, "c64053010fb70a66894854", "main learned flag and identical payload ID to dispatch WORD"),
        (0x6AADFC, "80784808740a0fb64a0280e10f884856", "record byte72==8 preserves byte86; otherwise low nibble"),
        (0x6AAE0C, "0fb64a02c1e9048848570fb64a038848588b5207895059", "high nibble, shortcut byte and training DWORD"),
        (0x6AAE25, "0fb7138bc6e83d0a0000", "same payload WORD ID to alternate lookup"),
        (0x6AB890, "0fb7103b55fc7406", "alternate lookup compares record WORD at offset0 to requested ID"),
        (0x6AAE35, "c64053010fb70a668948540fb65203885058", "alternate learned flag, dispatch ID and shortcut only"),
    ]
    rows = []
    for address, expected, role in checks:
        code = read_va(sample, address, len(bytes.fromhex(expected)))
        if code.hex() != expected:
            raise ValueError(f"unexpected learning path at {address:#x}")
        rows.append({"va": hex(address), "hex": code.hex(), "role": role})
    return {"schema_version": 1, "sample_sha256": EXPECTED_SAMPLE,
            "function": "0x6aadd8", "single_update_wrapper": "0x6aae64", "minimum_payload_bytes": 11,
            "lookup": {"main": "0x6ab15c", "alternate": "0x6ab86c", "comparison": "record uint16 at offset0 == payload uint16 at offset0",
                       "order": "main first; alternate only when main has no match",
                       "creates_missing_definition": False},
            "dispatch": {"record_offset": 84, "bytes": 2, "main_assignment": "0x6aadf8", "alternate_assignment": "0x6aae3c",
                         "equals_matched_base_id_after_this_update": True,
                         "reason": "both successful exact-ID lookups write the same payload ID into dispatch offset84"},
            "main_writes": [{"record_offset": 83, "value": 1},
                            {"record_offset": 86, "value": "payload[2] & 15", "except": "preserve when record[72] == 8"},
                            {"record_offset": 87, "value": "payload[2] >> 4"},
                            {"record_offset": 88, "value": "payload[3]"},
                            {"record_offset": 89, "value": "little-endian DWORD payload[7:11]"}],
            "alternate_writes": [{"record_offset": 83, "value": 1}, {"record_offset": 88, "value": "payload[3]"}],
            "alternate_miss_tail": "0x6aae58 still calls 0x6aa8c4 with payload ID and shortcut byte",
            "instruction_checks": rows,
            "limits": ["This proves identity immediately after this exact lookup/update path; not a global claim about every indirect write in the program.",
                       "No actual server skill-definition payload was supplied; resource names do not recover byte81 target modes or byte64 cast delays.",
                       "Byte86/87 roles are not inferred merely from their nibble packing; current SDLearnedMagic carries ID and exp, not these original fields."]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sample", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = extract_learning_evidence(args.sample.read_bytes())
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps({"instruction_checks": len(result["instruction_checks"]), "dispatch_equals_matched_base_after_update": True}))


if __name__ == "__main__":
    main()
