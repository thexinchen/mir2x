"""Record the original Ctrl-right actor query and returned equipment panel."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
from export_mir3_target_history import EXPECTED_SAMPLE, read_va


def extract(sample_path, registry_path):
    sample = sample_path.read_bytes()
    if hashlib.sha256(sample).hexdigest() != EXPECTED_SAMPLE:
        raise ValueError("requires documented unpacked sample")
    checks = [(0x67B434, "807d08000f858d000000", "held repeat skips one-shot query"),
              (0x67B43E, "807e7c000f8583000000", "dead actor falls through"),
              (0x67B452, "81f9dc0500007271", "elapsed <1500 falls through; equality allowed"),
              (0x67B475, "8b4e0cba52000000e882100500", "actor UID to ECX; message82 to EDX; command builder call")]
    evidence = []
    for address, expected, role in checks:
        code = read_va(sample, address, len(bytes.fromhex(expected)))
        if code.hex() != expected:
            raise ValueError(f"unexpected inspection instructions at {address:#x}")
        evidence.append({"va": hex(address), "hex": expected, "role": role})
    call = read_va(sample, 0x68765F, 5)
    if call[0] != 0xE8 or 0x687664 + struct.unpack_from("<i", call, 1)[0] != 0x62DC2C:
        raise ValueError("unexpected returned-state panel handler")
    registry = json.loads(registry_path.read_text(encoding="utf-8"))
    if registry["sample_sha256"] != EXPECTED_SAMPLE:
        raise ValueError("registry sample mismatch")
    registration = [row for row in registry["records"] if row["message"] == 751]
    if len(registration) != 1 or registration[0]["handler"] != "0x68761c":
        raise ValueError("unexpected message751 registration")
    return {"schema_version": 1, "sample_sha256": EXPECTED_SAMPLE,
            "request": {"entry": "0x67b398", "message": 82, "minimum_interval_ms": 1500, "inclusive_boundary": True,
                        "requires": ["Ctrl takes priority over Alt", "initial event, not held repeat", "live actor"],
                        "accepted": "send actor UID plus coordinates, then exit right-button handler",
                        "rejected": "continue ground turn/run processing", "instruction_checks": evidence},
            "returned_state": {"message": 751, "registration": registration[0], "handler": "0x68761c",
                               "panel_loader": "0x62dc2c", "panel_owner_offset": 28, "show": "0x520650",
                               "legacy_payload_bytes": 7259, "name": {"offset": 4, "maximum_bytes": 25},
                               "equipment": {"offset": 115, "records": 32, "stride_source": "off_729174", "loop": "0x62de2a..0x62de70"},
                               "appearance_fields": "0x62dca3/0x62dcb5/0x62dcc9; 0x62de97; 0x62debd"},
            "protocol_name_reference": "https://github.com/ndljava/mir/blob/master/MirOnline2/src/com/leyou/net/MirProtocol.as",
            "pairing_confidence": "Sample proves request shape and independent equipment/name panel for751; related protocol source names82 CM_QUERYUSERSTATE and751 SM_SENDUSERSTATE. No original server roundtrip was captured.",
            "current_adapter": {"query": "CM_QUERYPLAYERNAME + CM_QUERYPLAYERWLDESP", "reply": "SM_PLAYERWLDESP",
                                "slots": 11, "readonly": True, "nonplayer_query_sent": False,
                                "invalidations": ["close", "actor removal", "map/session reset", "pending response timeout"]},
            "limits": ["Related protocol source is supporting nomenclature, not proof that its entire version matches this binary.",
                       "Legacy7259-byte record is not decoded as the current Cereal record; unsupported original state fields are not fabricated.",
                       "Current query only supports player UIDs; nonplayer initial consumption and held fallback are retained without sending an invalid request."]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sample", required=True, type=Path)
    parser.add_argument("--registry", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    result = extract(args.sample, args.registry)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps({"request": 82, "returned_state": 751, "legacy_slots": 32, "current_slots": 11}))


if __name__ == "__main__":
    main()
